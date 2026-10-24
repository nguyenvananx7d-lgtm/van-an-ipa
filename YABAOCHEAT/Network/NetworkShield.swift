import Foundation
import UIKit
import Combine
import CFNetwork

/// DNS / network safety layer.
///
/// Two independent jobs:
///  1. **Encrypted DNS** — generate a system-wide DoH profile and hand it to
///     Safari through a loopback socket. No extension, no entitlement, and it
///     covers the game's lookups as well as the panel's.
///  2. **Tunnel gate** — optionally refuse an inject while no VPN/tunnel
///     interface is up, so a session is never started on a bare ISP route
///     after the user meant to be behind one.
///
/// It does not change the egress IP by itself, cannot see the game's socket
/// traffic, and cannot guarantee anything about server-side enforcement.
@MainActor
public final class NetworkShield: ObservableObject {
    public static let shared = NetworkShield()

    public enum Tone {
        case info, ok, warn, error
    }

    /// How far the user is through the profile hand-off. iOS does not expose
    /// whether a configuration profile is installed, so this is the honest
    /// local record: Safari was opened, and the user confirmed Settings.
    public enum InstallStage: String {
        case idle
        case pending
        case installed
    }

    private enum Key {
        static let enabled  = "ffxc.net.enabled"
        static let provider = "ffxc.net.provider"
        static let nextDNS  = "ffxc.net.nextdns"
        static let custom   = "ffxc.net.custom"
        static let require  = "ffxc.net.require"
        static let stage    = "ffxc.net.stage"
    }

    // MARK: - persisted settings

    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.enabled) }
    }

    @Published public var provider: DNSProvider {
        didSet {
            defaults.set(provider.rawValue, forKey: Key.provider)
            if provider != oldValue {
                installStage = .idle
                setStatus(nil, tone: .info)
            }
        }
    }

    @Published public var nextDNSID: String {
        didSet {
            defaults.set(nextDNSID, forKey: Key.nextDNS)
            if DNSProvider.normalizeNextDNSID(nextDNSID)
                != DNSProvider.normalizeNextDNSID(oldValue) {
                installStage = .idle
            }
        }
    }

    @Published public var customURL: String {
        didSet { defaults.set(customURL, forKey: Key.custom) }
    }

    /// Refuse `InjectStore.install` while `detectTunnelInterface()` is false.
    /// Off by default: the DNS profile alone is not a tunnel, and blocking on
    /// it would lock out the entitlement-free path.
    @Published public var requireTunnelBeforeInject: Bool {
        didSet {
            defaults.set(requireTunnelBeforeInject, forKey: Key.require)
            if requireTunnelBeforeInject { isEnabled = true }
        }
    }

    @Published public private(set) var installStage: InstallStage {
        didSet { defaults.set(installStage.rawValue, forKey: Key.stage) }
    }

    // MARK: - live state

    @Published public private(set) var isInstalling = false
    @Published public private(set) var isTesting = false
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var statusTone: Tone = .info
    @Published public private(set) var lastTestMS: Int?
    @Published public private(set) var tunnelActive: Bool = false

    private let defaults = UserDefaults.standard
    private let server = LoopbackProfileServer()
    private var stopTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        let d = UserDefaults.standard
        isEnabled = d.bool(forKey: Key.enabled)
        provider = DNSProvider(rawValue: d.string(forKey: Key.provider) ?? "") ?? .adguard
        nextDNSID = d.string(forKey: Key.nextDNS) ?? ""
        customURL = d.string(forKey: Key.custom) ?? ""
        requireTunnelBeforeInject = d.bool(forKey: Key.require)
        installStage = InstallStage(rawValue: d.string(forKey: Key.stage) ?? "") ?? .idle
        tunnelActive = Self.detectTunnelInterface()
    }

    // MARK: - derived

    public var profileURL: URL? {
        provider.dohURL(nextDNSID: nextDNSID, customURL: customURL)
    }

    public var isConfigured: Bool { profileURL != nil }

    /// Config IDs are copied as a bare ID, but users also paste the full DoH
    /// URL from the NextDNS dashboard. Both forms resolve to the same value.
    public var normalizedNextDNSID: String {
        DNSProvider.normalizeNextDNSID(nextDNSID)
    }

    public var isNextDNSValid: Bool {
        (6...16).contains(normalizedNextDNSID.count)
    }

    public func setNextDNSID(_ raw: String) {
        nextDNSID = DNSProvider.normalizeNextDNSID(raw)
    }

    public func refreshTunnel() {
        tunnelActive = Self.detectTunnelInterface()
    }

    // MARK: - install

    /// Builds the profile, serves it on loopback, and opens Safari.
    ///
    /// The app asks iOS for a background-task assertion first: opening Safari
    /// backgrounds the panel, and without the assertion the listener would be
    /// suspended before the user taps *Allow*.
    public func installProfile() {
        guard isConfigured else {
            setStatus("Enter a valid resolver URL or NextDNS config ID first.", tone: .error)
            return
        }
        guard let data = DNSProfile.make(
            provider: provider,
            nextDNSID: nextDNSID,
            customURL: customURL
        ) else {
            setStatus("Could not build the DNS profile.", tone: .error)
            return
        }

        isEnabled = true
        isInstalling = true
        setStatus("Starting the local profile server…", tone: .info)
        beginServingWindow()

        server.start(payload: data) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isInstalling = false

                switch result {
                case .success(let port):
                    let raw = "http://127.0.0.1:\(port)/VortexArena-DNS.mobileconfig"
                    guard let local = URL(string: raw) else {
                        self.endServingWindow()
                        self.setStatus("Could not open the local profile URL.", tone: .error)
                        return
                    }
                    UIApplication.shared.open(local, options: [:]) { opened in
                        Task { @MainActor in
                            guard opened else {
                                self.endServingWindow()
                                self.setStatus("Safari did not open. Try again from the foreground.",
                                               tone: .error)
                                return
                            }
                            self.setStatus(
                                "Safari opened. Tap Allow, then install the profile in Settings → Profile Downloaded.",
                                tone: .ok
                            )
                            self.installStage = .pending
                            // Safari downloads within a few seconds; keep the
                            // socket alive for a generous window and then stop.
                            self.scheduleStop(after: 45)
                        }
                    }

                case .failure:
                    self.endServingWindow()
                    self.setStatus("Could not start the local profile server. Try again.", tone: .error)
                }
            }
        }
    }

    private func scheduleStop(after seconds: UInt64) {
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.server.stop()
            self?.endServingWindow()
        }
    }

    private func beginServingWindow() {
        endServingWindow()
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "VortexArena.DNSProfile"
        ) { [weak self] in
            Task { @MainActor in
                self?.server.stop()
                self?.endServingWindow()
            }
        }
    }

    private func endServingWindow() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - install stage

    /// The user has been through Settings. iOS gives no API to verify the
    /// profile, so this is a local acknowledgement, not a detection.
    public func markProfileInstalled() {
        installStage = .installed
        setStatus("Profile marked as installed. Run Test resolver to confirm the endpoint answers.",
                  tone: .ok)
    }

    public func resetInstall() {
        installStage = .idle
        setStatus(nil, tone: .info)
    }

    /// Jumps to Settings → General → VPN & Device Management, where the
    /// downloaded profile lives. Falls back to the app's settings page.
    public func openSettings() {
        openFirst([
            "App-Prefs:root=General&path=ManagedConfigurationList",
            "App-Prefs:root=General",
            UIApplication.openSettingsURLString
        ])
    }

    private func openFirst(_ raws: [String]) {
        guard let raw = raws.first, let url = URL(string: raw) else {
            setStatus("Open Settings → General → VPN & Device Management to install the profile.",
                      tone: .warn)
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in self?.openFirst(Array(raws.dropFirst())) }
        }
    }

    // MARK: - resolver test

    /// Sends one DNS wire-format query to the configured DoH endpoint.
    ///
    /// This proves the endpoint is reachable and answers; iOS does not expose
    /// the *active* system resolver, so it cannot prove the profile is
    /// installed. The guide points at a DNS-leak page for that check.
    public func testResolver() async {
        guard let url = profileURL else {
            setStatus("Enter a valid resolver URL or NextDNS config ID first.", tone: .error)
            return
        }

        isTesting = true
        let started = Date()
        let ok = await Self.probe(url: url)
        let ms = max(0, Int(Date().timeIntervalSince(started) * 1_000))
        isTesting = false

        if ok {
            lastTestMS = ms
            setStatus("Resolver answered in \(ms) ms.", tone: .ok)
        } else {
            lastTestMS = nil
            setStatus("Resolver did not answer. Check the URL/ID and your connection.", tone: .error)
        }
    }

    // MARK: - inject gate

    /// Called at the front of every install. Always safe: with the shield off
    /// it is a no-op, and with `requireTunnelBeforeInject` off it only logs.
    public func preflightForInject(log: AppLog) -> Bool {
        refreshTunnel()
        guard isEnabled else { return true }

        // No network round-trip here: a DoH probe can take seconds and would
        // delay every inject. Reachability is checked on demand by the Test
        // button; this gate is about configuration and the tunnel interface.
        log.log(.network,
                "shield: \(provider.title) \(isConfigured ? "configured" : "not configured"), "
                + "tunnel \(tunnelActive ? "up" : "down")")

        if requireTunnelBeforeInject && !tunnelActive {
            log.log(.network, "shield: inject blocked — no tunnel interface")
            setStatus("Inject blocked: start your VPN/tunnel first.", tone: .warn)
            return false
        }

        if !isConfigured {
            setStatus("Resolver not configured — open Network shield and pick one.", tone: .warn)
        }
        return true
    }

    /// Opens a resolver-identity page in Safari. iOS does not expose the
    /// active system resolver, so this is the only honest end-to-end check.
    public func openLeakTest() {
        guard let url = URL(string: "https://www.dnsleaktest.com") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // MARK: - denylist helper

    /// Domains that are analytics/tracker endpoints rather than game services.
    /// Meant to be pasted into a NextDNS denylist; it deliberately leaves the
    /// game, login and social-login domains alone.
    public static let recommendedDenylist = """
    app-measurement.com
    firebase-settings.crashlytics.com
    crashlyticsreports-pa.googleapis.com
    appsflyer.com
    launch.appsflyer.com
    app.adjust.com
    api.amplitude.com
    api2.amplitude.com
    api.mixpanel.com
    api.segment.io
    api2.branch.io
    gameanalytics.com
    unityads.unity3d.com
    config.unityads.unity3d.com
    google-analytics.com
    analytics.google.com
    ssl.google-analytics.com
    stats.g.doubleclick.net
    """

    public func copyDenylist() {
        UIPasteboard.general.string = Self.recommendedDenylist
        setStatus("Tracker denylist copied. Paste it into your NextDNS denylist.", tone: .ok)
    }

    /// Publisher security/reporting hosts seen in Free Fire's DNS surface.
    ///
    /// These are the names the game uses for its security/stronghold checks and
    /// its regional game-security endpoint. Blocking them stops *DNS-based*
    /// reporting; it does not stop an in-process anti-cheat scan, and it can
    /// crash the game or block login. Add one entry at a time and test a match.
    public static let publisherDenylist = """
    csoversea.stronghold.freefiremobile.com
    gamesecurity.sea.freefiremobile.com
    adv.wfpj.freefiremobile.com
    """

    public func copyPublisherDenylist() {
        UIPasteboard.general.string = Self.publisherDenylist
        setStatus("Publisher denylist copied. Add entries one at a time in NextDNS → Denylist.",
                  tone: .ok)
    }

    /// One paste for the common case: trackers plus the publisher hosts.
    public static let fullBlocklist = recommendedDenylist + "\n" + publisherDenylist

    public func copyBlocklist() {
        UIPasteboard.general.string = Self.fullBlocklist
        setStatus("Blocklist copied. Paste it into NextDNS → Privacy → Denylist.", tone: .ok)
    }

    /// Opens the NextDNS dashboard so the denylist can be edited next to the
    /// app; the DoH profile itself only carries the config ID.
    public func openNextDNS() {
        guard let url = URL(string: "https://my.nextdns.io") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // MARK: - status

    private func setStatus(_ message: String?, tone: Tone) {
        statusMessage = message
        statusTone = tone
    }

    // MARK: - probing

    private static func probe(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.httpBody = dnsQuery(name: "example.com")

        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8

        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            return data.count > 12
        } catch {
            return false
        }
    }

    private static func dnsQuery(name: String) -> Data {
        // Header: id 0, RD set, one question, no answers/authority/additional.
        var data = Data([0x00, 0x00, 0x01, 0x00, 0x00, 0x01,
                         0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            guard bytes.count < 64 else { continue }
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        data.append(0)
        data.append(contentsOf: [0x00, 0x01, 0x00, 0x01]) // A, IN
        return data
    }

    // MARK: - tunnel probe

    /// Heuristic: the scoped proxy table carries a tunnel interface when a VPN
    /// or a tunnel-based privacy app is up. iOS keeps a few `utun` devices
    /// internally, but they are not listed here without a configured tunnel.
    private static func detectTunnelInterface() -> Bool {
        guard let unmanaged = CFNetworkCopySystemProxySettings() else { return false }
        guard let settings = unmanaged.takeRetainedValue() as? [String: Any] else { return false }
        guard let scoped = settings["__SCOPED__"] as? [String: Any] else { return false }

        let prefixes = ["utun", "tun", "tap", "ipsec", "ppp"]
        return scoped.keys.contains { key in
            let lower = key.lowercased()
            return prefixes.contains { lower.hasPrefix($0) }
        }
    }
}
