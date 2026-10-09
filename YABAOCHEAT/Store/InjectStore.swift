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
                Task { await self.installer.restageConfig(game: game, controls: controls) }
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

    // MARK: - install

    public func install(expectedDigest: String?, monitorMs: Int) async {
        set(.injecting, "Installing…")
        do {
            let payload = try PatchPayload.bundled()
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
            status = "Injected"

            try? launcher.launch(game: game)
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

    public func launch() {
        do {
            try launcher.launch(game: game)
        } catch {
            status = error.localizedDescription
        }
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

