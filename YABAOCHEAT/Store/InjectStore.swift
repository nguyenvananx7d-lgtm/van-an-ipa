import Foundation
import SwiftUI
import Combine

/// Drives one injection cycle end to end and holds the result.
///
/// The state machine is deliberately explicit: every transition that can fail
/// maps onto one of the `InjectState` cases, so the UI never has to infer what
/// went wrong from a boolean.
@MainActor
public final class InjectStore: ObservableObject {
    public static let shared = InjectStore()

    /// The game this store is currently acting on.
    public var game: Game { menu.selectedGame }
    public var accessDeniedReason: String? {
        let diag = bridge.sandboxDiagnosis
        if let reason = bridge.lastAccessError, !reason.isEmpty {
            return "\(reason) · \(diag)"
        }
        return nil
    }

    /// Whether the running iOS needs the sandbox escape before the container
    /// scan can answer (iOS 26+). On older builds the exploit is optional.
    public var requiresSandboxEscape: Bool { KernelExploit.requiresSandboxEscape }

    /// Localization key explaining whether the exploit is required or optional.
    public var exploitHintKey: String {
        requiresSandboxEscape ? "exploit_needs_sandbox" : "exploit_optional_hint"
    }

    /// A session is active and the payload is mapped in the running target.
    @Published public var isActive: Bool = false

    /// The user has confirmed a wipe; suppresses the install prompt until the
    /// container is verified clean again.
    @Published public var filesWiped: Bool = false

    /// Human-readable progress, shown under the state badge.
    @Published public var status: String?

    /// Where the last install put its files, so the log screen can show them.
    @Published public var lastInstall: RuntimeInstaller.Result?

    @Published public var wipeReport: WipeRoutine.Report?

    /// Outcome of the most recent anti-ban sweep, shown in the Setting tab.
    @Published public var antiBanReport: AntiBanRoutine.SweepResult?

    /// A sweep is in flight (drives the spinner in the Setting tab).
    @Published public var isRunningAntiBan: Bool = false

    /// Cooldown backing the foreground re-probe so returning to the app a few
    /// times in a row does not spam the log with identical probe verdicts.
    private var lastForegroundRecheck = Date.distantPast

    /// Where the (opt-in) kernel-exploit chain stands. Always `notStarted`
    /// until the user presses the run button; iOS 26+ refuses the filesystem
    /// scan without it, iOS 17/18 work regardless via the MCM token.
    @Published public var exploitStatus: ExploitStatus = .notStarted

    /// A run of `KernelExploit.run()` is in flight (drives the spinner).
    @Published public var isRunningExploit: Bool = false

    private let log: AppLog
    private let menu: MenuStore
    private let installer: RuntimeInstaller
    private let launcher: GameLauncher
    private let wiper: WipeRoutine
    private let bridge: ContainerBridge
    private let probe: PostLaunchProbe
    private let antiBan: AntiBanRoutine

    private var cancellables: Set<AnyCancellable> = []

    private init(
        log: AppLog = .shared,
        menu: MenuStore = .shared,
        bridge: ContainerBridge? = nil
    ) {
        self.log = log
        self.menu = menu
        self.bridge = bridge ?? ContainerBridge(log: log)
        self.installer = RuntimeInstaller(log: log, bridge: self.bridge, krw: .shared)
        self.launcher = GameLauncher(log: log)
        self.wiper = WipeRoutine(log: log, bridge: self.bridge, krw: .shared)
        self.probe = PostLaunchProbe(log: log, bridge: self.bridge, launcher: self.launcher)
        // Use the store's own bridge instance, not `AntiBanRoutine.shared`:
        // `ContainerBridge` keeps the consumed `bad_query` grants on the
        // instance that resolved the container, so sharing the injector's
        // bridge means the sweep reuses one grant instead of requesting a
        // second one (which can be refused while the first is held).
        self.antiBan = AntiBanRoutine(log: log, bridge: self.bridge, krw: .shared)

        // When the game takes over the screen the injector sits in the
        // background and its scheduled probe is deferred. Re-probe whenever the
        // app returns to the foreground, so the log then shows the container
        // state the user is actually looking at. Cooldown in `foregroundRecheck`.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.foregroundRecheck() }
        }

        // Live propagation: any panel change rewrites the runtime config into
        // the resolved container so ESP / aim toggles take effect without a
        // wipe and re-inject. Debounced because sliders fire continuously, and
        // deduped so a re-render that changes nothing does not write.
        menu.$configurations
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.isActive else { return }
                let game = self.menu.selectedGame
                let controls = self.menu.controls
                Task {
                    await self.installer.restageConfig(game: game, controls: controls)
                    // The rewrite just bumped the config's mtime; re-mask it so
                    // a live panel change does not leave a freshly-dated file
                    // behind between full anti-ban sweeps.
                    if controls.antiBan { await self.antiBan.conceal(game: game) }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - capability gate

    /// Work out whether injection is even possible, and set the state to match.
    /// Cheap enough to run every time the inject screen appears.
    public func evaluate() {
        let device = DeviceIdentityProvider.shared

        if device.isSimulator {
            set(.simulator, "Simulator detected")
            return
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osSupported = ExploitSupportPolicy.isSupported(
            major: os.majorVersion,
            minor: os.minorVersion,
            patch: os.patchVersion,
            build: DeviceOS.build
        )
        refreshExploitStatus()
        guard osSupported else {
            set(.unsupportedOS, "Unsupported iOS \(DeviceOS.displayString)")
            return
        }
        if false {
            set(.unsupportedHardware, "This device is not on the supported list")
            return
        }

        switch bridge.resolve(game: game) {
        case .resolved:
            menu.resolutions[game] = .resolved
            filesWiped = false
            set(.ready, nil)
        case .notFound:
            menu.resolutions[game] = .notFound
            // The selected title may not be the one that is installed. If the
            // other title resolves, switch selection to the game actually
            // present on the device.
            let other: Game = game == .freeFire ? .freeFireMax : .freeFire
            if case .resolved = bridge.resolve(game: other) {
                log.log(.mcm, "\(game.displayName) not installed; switching to \(other.displayName)")
                menu.selectedGame = other
                // InjectView re-runs evaluate() via onChange(of: selectedGame).
                return
            }
            set(.gameNotInstalled, "\(game.displayName) (\(game.bundleIdentifier)) is not installed")
        case .accessDenied:
            menu.resolutions[game] = .accessDenied
            set(.containerAccessDenied, "The app container is sealed — \(bridge.sandboxDiagnosis)")
        case .bridgeUnavailable:
            menu.resolutions[game] = .bridgeUnavailable
            set(.containerBridgeUnavailable, "The container bridge is unavailable")
        }
    }

    // MARK: - kernel exploit (opt-in)

    /// Refresh the exploit state without touching the result of a previous run:
    /// unsupported builds flip to `.unsupported`, and an already-active sandbox
    /// escape (e.g. from a jailbreak or an earlier run) is reported as success.
    /// Cheap — safe to call on every screen appearance.
    public func refreshExploitStatus() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let supported = ExploitSupportPolicy.isSupported(
            major: os.majorVersion,
            minor: os.minorVersion,
            patch: os.patchVersion,
            build: DeviceOS.build
        )
        guard supported else {
            exploitStatus = .unsupported(DeviceOS.displayString)
            return
        }
        if case .notStarted = exploitStatus, KernelExploit.hasSandboxAccess() {
            exploitStatus = .success(method: "sandbox")
        }
    }

    /// Opt-in run of the kernel-exploit chain. The chain blocks for up to ~30 s
    /// (and may briefly freeze the device), so it runs on a background thread;
    /// on completion it writes the outcome and re-evaluates the inject screen.
    public func runExploit() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let supported = ExploitSupportPolicy.isSupported(
            major: os.majorVersion,
            minor: os.minorVersion,
            patch: os.patchVersion,
            build: DeviceOS.build
        )
        guard supported else {
            exploitStatus = .unsupported(DeviceOS.displayString)
            return
        }
        guard !isRunningExploit else { return }
        isRunningExploit = true
        status = "Running kernel exploit…"

        Task.detached(priority: .userInitiated) { [weak self] in
            let ok = KernelExploit.run()
            await MainActor.run {
                guard let self else { return }
                self.isRunningExploit = false
                let kind = KernelExploit.requiresSandboxEscape ? "sandbox" : "kernel"
                if ok {
                    self.exploitStatus = .success(method: kind)
                } else {
                    self.exploitStatus = .failed(method: kind, code: -1)
                }
                self.status = ok ? "Exploit succeeded" : "Exploit failed"
                self.evaluate()
            }
        }
    }

    /// Sophia parity. The vendor build runs its kernel chain implicitly at the
    /// front of every inject instead of waiting for an opt-in button: kernel
    /// R/W / sandbox escape first, then the container work runs against direct
    /// (grant-free) access. Blocking (10–30 s, potential brief freeze) so it
    /// runs detached; never throws, so staging still proceeds on the grant/MCM
    /// path if this boot loses the exploit race. Always logs the iOS version so
    /// the log screen shows exactly what the support table was asked about.
    @MainActor
    private func ensureExploitBeforeInject() async {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        log.log(.kernelRW, "exploit check: iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) (build \(DeviceOS.build))")

        let supported = ExploitSupportPolicy.isSupported(
            major: os.majorVersion,
            minor: os.minorVersion,
            patch: os.patchVersion,
            build: DeviceOS.build
        )
        guard supported else {
            log.log(.kernelRW, "exploit auto-run skipped — iOS \(DeviceOS.displayString) is not on the verified table")
            return
        }

        if case .success = exploitStatus {
            log.log(.kernelRW, "exploit already active — reusing it")
            return
        }
        guard !isRunningExploit else { return }
        if KernelExploit.hasSandboxAccess() {
            exploitStatus = .success(method: KernelExploit.requiresSandboxEscape ? "sandbox" : "kernel")
            log.log(.kernelRW, "outside-sandbox access already held")
            return
        }

        // The kernel chain's stage 1 (`kexploit_opa334`) is verified only on
        // iOS 17.0–18.7.1. On newer builds auto-running it here is a 10–30 s
        // wait that can only fail; the vendor build does not gate staging on it
        // either — the files land via the grant/MCM container route probed in
        // `ContainerBridge.resolve`.
        guard KernelExploit.kernelStageSupported else {
            log.log(.kernelRW, "kernel chain targets iOS 17.0–18.7.1 — skipping auto-run on iOS \(DeviceOS.displayString)")
            log.log(.kernelRW, "continuing on the grant/MCM container path (vendor parity)")
            return
        }

        isRunningExploit = true
        status = "Bringing up kernel access…"
        log.log(.kernelRW, "auto-running exploit before inject (Sophia parity)")
        let ok = await Task.detached(priority: .userInitiated) { KernelExploit.run() }.value
        isRunningExploit = false

        let kind = KernelExploit.requiresSandboxEscape ? "sandbox" : "kernel"
        if ok {
            exploitStatus = .success(method: kind)
            log.log(.kernelRW, "exploit OK — continuing install with \(kind) access")
        } else {
            exploitStatus = .failed(method: kind, code: -1)
            log.log(.kernelRW, "exploit failed — continuing install on the grant/MCM path")
        }
    }

    // MARK: - install

    public func install(expectedDigest: String?, monitorMs: Int) async {
        set(.injecting, "Installing…")
        do {
            let payload = try PatchPayload.bundled()
            // Sophia parity: bring the kernel chain up before touching the
            // target (the vendor build never waits for an opt-in button).
            // Non-fatal — if the exploit loses this boot, staging still proceeds
            // on the grant/MCM path.
            await ensureExploitBeforeInject()
            let result = try await installer.install(
                game: game,
                payload: payload,
                controls: menu.controls,
                expectedDigest: expectedDigest,
                monitorMs: monitorMs
            )
            lastInstall = result
            isActive = true
            filesWiped = false
            menu.injected.insert(game)
            menu.injectStates[game] = .ready
            if menu.controls.antiBan {
                // Sweep *after* the config re-stamp so the masking pass is the
                // last thing to touch the payload: the fresh config mtime never
                // outlives the sweep. The probe residue is cleared and the
                // session document re-stamped while the panel still has the
                // container open.
                isRunningAntiBan = true
                await installer.restageConfig(game: game, controls: menu.controls)
                antiBanReport = await antiBan.run(game: game)
                isRunningAntiBan = false
            }
            status = "Injected"

            try? launcher.launch(game: game)
            probe.schedule(game: game, patchDigest: payload.sha256)
        } catch let error as RuntimeInstaller.InstallError {
            isActive = false
            set(fallbackState(for: error), error.localizedDescription)
        } catch {
            isActive = false
            set(.failed, error.localizedDescription)
        }
    }

    // MARK: - teardown

    public func uninject() async {
        do {
            try await installer.uninject(game: game)
            isActive = false
            lastInstall = nil
            menu.injected.remove(game)
            set(.ready, "Removed")
        } catch {
            set(.failed, error.localizedDescription)
        }
    }

    /// Soft teardown, paired with the full `uninject`: the app stops managing
    /// the session (active flag, last install, injected set) but leaves the
    /// staged patch and config exactly where they are, so aim / ESP keep
    /// working on the next launch. Never throws — it only detaches state.
    public func keepFeatures() async {
        await installer.keepFeatures(game: game)
        isActive = false
        lastInstall = nil
        menu.injected.remove(game)
        set(.ready, "Removed — aim & ESP kept")
    }

    public func wipe() {
        do {
            let report = try wiper.wipe(game: game)
            wipeReport = report
            filesWiped = report.isClean
            isActive = false
            menu.injected.remove(game)
            menu.injectStates[game] = report.isClean ? .ready : .failed
            status = report.isClean ? "Container is clean" : "Some files could not be removed"
        } catch {
            set(.failed, error.localizedDescription)
        }
    }

    /// Run the anti-ban sweep now, and re-stamp the session document so the
    /// runtime reads a current config. Backed by the sweep the panel runs
    /// automatically at the front of every inject when the anti-ban switch is
    /// on; this is the manual trigger and the checkbox's run-on-toggle.
    public func runAntiBan() async {
        guard !isRunningAntiBan else { return }
        isRunningAntiBan = true
        status = "Running anti-ban sweep…"
        // Re-stamp the session document first, then sweep: the sweep's masking
        // pass must be the last write so the config's mtime is masked too.
        await installer.restageConfig(game: game, controls: menu.controls)
        let sweep = await antiBan.run(game: game)
        antiBanReport = sweep
        isRunningAntiBan = false
        status = sweep.removed.isEmpty && sweep.masked.isEmpty && sweep.flagged.isEmpty
            ? "Anti-ban sweep done — clean"
            : "Anti-ban sweep done — \(sweep.removed.count) removed, \(sweep.masked.count) masked, \(sweep.flagged.count) flagged"
    }

    public func launch() {
        do {
            try launcher.launch(game: game)
        } catch {
            status = error.localizedDescription
        }
    }

    /// Cooldown-guarded re-probe used when the injector returns to the
    /// foreground (the scheduled probe is deferred while the game owns the
    /// screen).
    private func foregroundRecheck() {
        guard isActive, lastInstall != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastForegroundRecheck) > 15 else { return }
        lastForegroundRecheck = now
        let digest = (try? PatchPayload.bundled())?.sha256 ?? ""
        Task { await probe.recheck(game: game, patchDigest: digest) }
    }

    // MARK: - helpers

    private func set(_ state: InjectState, _ message: String?) {
        menu.injectStates[game] = state
        status = message
        if let message { log.log(.runtime, "\(game.rawValue): \(state.rawValue) — \(message)") }
    }

    private func fallbackState(for error: RuntimeInstaller.InstallError) -> InjectState {
        switch error {
        case .containerNotFound:            return .gameNotInstalled
        case .fileUnavailable:              return .containerAccessDenied
        case .processResetUnavailable:      return .containerBridgeUnavailable
        case .integrityMismatch:            return .unavailable
        default:                             return .failed
        }
    }
}

