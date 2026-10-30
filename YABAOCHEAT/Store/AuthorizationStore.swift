import Foundation
import SwiftUI
/// Owns the license session: validates a key, keeps it alive, and tears it down
/// on logout or revocation.
@MainActor
public final class AuthorizationStore: ObservableObject {
    public static let shared = AuthorizationStore()
    // MARK: state
    @Published public private(set) var status: AuthorizationStatus = .unknown
    @Published public private(set) var isRefreshing: Bool = false
    /// Set when the server takes the session away; shown as a banner until the
    /// user acts on it.
    @Published public var revocationMessage: String?
    /// Non-error feedback, such as the reset confirmation. Kept separate so
    /// the gate can show it as information rather than as a failure.
    @Published public var noticeMessage: String?
    /// Consecutive transport failures. Reset by any successful check.
    public private(set) var networkErrorCount: Int = 0
    /// Set when a launch-time integrity check fails. Sticky for the run: it is
    /// a property of the binary, so no later `.valid` may clear it.
    private var integrityBlocked: Bool = false
    /// In-flight revalidation, so a manual refresh cannot stack up behind a
    /// scheduled one.
    public private(set) var revalidationTask: Task<Void, Never>?
    @Published public private(set) var isDarkMode: Bool = true
    @Published public private(set) var languageSelected: Bool = false
    @Published public private(set) var catalog: [ControlDescriptor] = []
    @Published public private(set) var expectedPatchSHA256: String?
    @Published public private(set) var expectedNeutralSHA256: String?
    @Published public private(set) var patchOpenMonitorMs: Int = 2_000
    @Published public private(set) var sessionToken: String?
    private let log: AppLog
    private let menu: MenuStore
    private let live: LiveUpdate
    private init(log: AppLog = .shared, menu: MenuStore = .shared) {
        self.log = log
        self.menu = menu
        self.live = LiveUpdate(log: log)
        observeNotifications()
    }
    // MARK: - entry points
    /// Validate a key the user typed. On success the key is persisted and the
    /// session starts. With a relay configured the exchange happens at
    /// `<host>/menu/login`; the relay is the authority on devices and resets.
    /// Only when no relay is configured does the local adoption path below run,
    /// and that path never starts a heartbeat.
    public func submit(key: String, password: String = "") async {
        if LocalMode.enabled {
            enterLocalMode()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        noticeMessage = nil

        // Relay-first: when a relay host is configured, the portal at
        // `<host>/menu/login` is the authority. It binds this device, issues the
        // session the menu uses and returns the same signed envelope as the
        // desktop endpoint. Only with no relay configured does the build fall
        // back to the local adoption path below.
        let host = Self.relayHost
        if !host.isEmpty {
            do {
                // The device id is a keychain-backed hash; resolve it off the
                // main actor so a slow securityd cannot stall the UI.
                let deviceKey = await Self.deviceKey()
                let activation = try await RelayActivationClient.activate(
                    host: host,
                    key: key,
                    password: password,
                    deviceKey: deviceKey
                )
                Task.detached(priority: .utility) {
                    try? SecureStore.storeLicenseKey(activation.key)
                    try? SecureStore.storePassword(password)
                }
                sessionToken = activation.session
                let pins = PatchPayload.localPins()
                expectedPatchSHA256 = pins.patch.isEmpty ? nil : pins.patch
                expectedNeutralSHA256 = pins.neutral
                revocationMessage = nil
                networkErrorCount = 0
                apply(.valid(
                    plan: activation.plan,
                    displayKey: activation.key,
                    expiresAt: activation.expiresAt ?? .distantFuture
                ))
                log.log(.auth, "authorized through relay \(host)")
                return
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                revocationMessage = message
                if let relay = error as? RelayActivationError,
                   case let .rejected(code, _) = relay {
                    apply(.invalid(code))
                } else {
                    apply(.invalid(.invalid))
                }
                log.log(.auth, "relay activation refused: \(message)")
                return
            }
        }

        let pins = PatchPayload.localPins()
        expectedPatchSHA256 = pins.patch.isEmpty ? nil : pins.patch
        expectedNeutralSHA256 = pins.neutral
        let resp = LicenseResponse(
            status: "valid",
            message: nil,
            plan: "Vortex Arena",
            expiresAt: nil,
            metadata: nil,
            session: "bypass",
            sessionTtl: nil,
            sessionExpiresAt: nil,
            catalog: nil,
            deployment: nil,
            command: nil,
            credential: nil,
            licenseLabel: key
        )
        adopt(resp, startHeartbeat: false)
    }
    /// Re-check the stored key, if there is one. Called on launch and whenever
    /// the app returns to the foreground.
    public func revalidate() {
        if LocalMode.enabled {
            enterLocalMode()
            return
        }
        revalidationTask?.cancel()
        revalidationTask = Task { [weak self] in
            guard let self else { return }
            await self.performRevalidation()
        }
    }

    /// Local build: no key, no relay, no server. The status is made `valid`
    /// once so every view that renders the session card keeps working, but
    /// nothing is stored in the keychain and no heartbeat is started.
    public func enterLocalMode() {
        revalidationTask?.cancel()
        revalidationTask = nil
        Task { await self.live.stop() }
        sessionToken = nil
        let pins = PatchPayload.localPins()
        expectedPatchSHA256 = pins.patch.isEmpty ? nil : pins.patch
        expectedNeutralSHA256 = pins.neutral
        revocationMessage = nil
        networkErrorCount = 0
        apply(.valid(
            plan: "Local",
            displayKey: "LOCAL",
            expiresAt: .distantFuture
        ))
        log.log(.auth, "local mode: key gate bypassed, no relay")
    }
    private func performRevalidation() async {
        // Keychain is a synchronous XPC to securityd; read it away from the
        // main actor so a slow daemon cannot trip the scene-update watchdog.
        let stored = await Task.detached(priority: .userInitiated) { () -> (key: String, password: String)? in
            guard let key = try? SecureStore.licenseKey(), !key.isEmpty else { return nil }
            return (key, (try? SecureStore.password()) ?? "")
        }.value
        guard let stored else {
            apply(.unknown)
            return
        }
        await submit(key: stored.key, password: stored.password)
    }

    private static func deviceKey() async -> String {
        let provider = DeviceIdentityProvider.shared
        return await Task.detached(priority: .userInitiated) {
            provider.activationId
        }.value
    }

    /// The relay host the portal lives on. Read from the same `UserDefaults`
    /// key the Setup screen writes, so there is one value, not a copy per view,
    /// with the build-time `FFXCRelayHost` as the fallback.
    public static var relayHost: String {
        RelayActivationClient.configuredHost
    }

    /// Release this device from the key at the portal. The relay enforces the
    /// two-per-day limit; a refusal is surfaced verbatim because only the
    /// server knows how many are left.
    @discardableResult
    public func resetDevice() async -> Bool {
        guard let session = sessionToken, !session.isEmpty,
              !Self.relayHost.isEmpty else {
            revocationMessage = "Chưa có phiên relay để reset."
            return false
        }
        do {
            let message = try await RelayActivationClient.resetDevice(
                host: Self.relayHost,
                session: session
            )
            sessionToken = nil
            Task.detached(priority: .utility) {
                SecureStore.clearLicenseKey()
                SecureStore.clearPassword()
            }
            revocationMessage = nil
            noticeMessage = message
            apply(.unknown)
            log.log(.auth, "relay device reset: \(message)")
            return true
        } catch {
            revocationMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            log.log(.auth, "relay device reset refused")
            return false
        }
    }
    /// End the session locally and drop the stored key.
    public func logout() {
        revalidationTask?.cancel()
        revalidationTask = nil
        Task { await self.live.stop() }
        Task.detached(priority: .utility) {
            SecureStore.clearLicenseKey()
            SecureStore.clearPassword()
        }
        sessionToken = nil
        catalog = []
        expectedPatchSHA256 = nil
        expectedNeutralSHA256 = nil
        menu.apply(catalog: [], sections: [])
        revocationMessage = nil
        noticeMessage = nil
        networkErrorCount = 0
        apply(.unknown)
        log.log(.auth, "logged out")
    }
    // MARK: - adopting a response
    private func adopt(_ response: LicenseResponse, startHeartbeat: Bool = true) {
        networkErrorCount = 0
        revocationMessage = nil
        if let code = response.errorCode {
            if code.invalidatesKey {
                Task.detached(priority: .utility) {
                    SecureStore.clearLicenseKey()
                }
                revocationMessage = response.message ?? code.localizedDescription
            }
            apply(.invalid(code))
            return
        }
        // An integrity failure is a verdict on the binary, not on the key. It is
        // recorded once per launch and must not lose a race against the
        // foreground revalidation, which otherwise lands on top of it and
        // reports a healthy session over a failed check.
        if integrityBlocked {
            revocationMessage = String(localized: "license_error.integrityFailed")
            log.log(.auth, "integrity failure standing; session not adopted")
            apply(.invalid(.integrityFailed))
            return
        }
        // Deployment policy: digest pins and the monitor window come from here,
        // so a compromised response cannot relax the pre-flight checks.
        if let deployment = response.deployment {
            if let digests = response.metadata?["digests"] {
                expectedPatchSHA256 = digests["patch"]
                expectedNeutralSHA256 = digests["neutral"]
            }
            patchOpenMonitorMs = ProtocolConstants.Policy.fallback.patchOpenMonitorMs
            if deployment.protocolVersion > ProtocolConstants.protocolVersion {
                log.log(.auth, "server speaks protocol v\(deployment.protocolVersion); this build speaks v\(ProtocolConstants.protocolVersion)")
            }
        }
        if let descriptors = response.catalog, !descriptors.isEmpty {
            catalog = descriptors
            let sections = response.metadata?["sections"] ?? [:]
            menu.apply(
                catalog: descriptors,
                sections: sections
                    .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                    .map { $0.value }
            )
        }
        if let session = response.session, !session.isEmpty {
            sessionToken = session
            if startHeartbeat {
                let heartbeat = response.deployment?.heartbeatSeconds
                    ?? ProtocolConstants.Policy.fallback.heartbeatSeconds
                let live = self.live
                Task {
                    await live.start(session: session, interval: heartbeat) { [weak self] update in
                        // Runs off the main actor; hop back before touching state.
                        Task { await self?.acceptHeartbeat(update) }
                    }
                }
            } else {
                log.log(.auth, "local session; heartbeat not started")
            }
        }
        apply(.valid(
            plan: response.plan ?? "—",
            displayKey: response.licenseLabel ?? "—",
            expiresAt: Self.parseDate(response.expiresAt) ?? Date().addingTimeInterval(86_400)
        ))
        log.log(.auth, "authorized")
    }
    private func acceptHeartbeat(_ response: LicenseResponse) async {
        await MainActor.run {
            if let code = response.errorCode {
                if code.invalidatesKey {
                    self.revocationMessage = response.message ?? code.localizedDescription
                    self.apply(.invalid(code))
                }
                return
            }
            self.networkErrorCount = 0
            if let plan = response.plan, let key = response.licenseLabel,
               let expires = Self.parseDate(response.expiresAt) {
                self.apply(.valid(plan: plan, displayKey: key, expiresAt: expires))
            }
        }
    }
    private func apply(_ new: AuthorizationStatus) {
        status = new
        isDarkMode = new.plan?.isEmpty == false
    }
    // MARK: - notifications
    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notifications.authorizationRevoked, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let reason = note.object as? String ?? "revoked"
            Task { @MainActor in
                if reason == "networkError" {
                    self.apply(.offline(since: Date(), lastError: .network))
                } else {
                    self.revocationMessage = reason
                    self.apply(.invalid(.revoked))
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: Notifications.integrityFailed, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.integrityBlocked = true
                self.revocationMessage = String(localized: "license_error.integrityFailed")
                self.apply(.invalid(.integrityFailed))
            }
        }
    }
    // MARK: - dates
    /// The server sends ISO-8601 with or without fractional seconds; both are
    /// accepted, and a malformed date is treated as absent rather than fatal.
    nonisolated static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        return ISO8601DateFormatter().date(from: raw)
    }
}
