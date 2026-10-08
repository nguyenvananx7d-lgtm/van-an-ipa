import Foundation
import SwiftUI

/// Drives one injection cycle end to end and holds the result.
///
/// The state machine is deliberately explicit: every transition that can fail
/// maps onto one of the `InjectState` cases, so the UI never has to infer what
/// went wrong from a boolean.
@MainActor
public final class InjectStore: ObservableObject {
    public static let shared = InjectStore()

    /// The game this store is currently acting on.
    @Published public var game: Game

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

    private let log: AppLog
    private let menu: MenuStore
    private let installer: RuntimeInstaller
    private let launcher: GameLauncher
    private let wiper: WipeRoutine
    private let bridge: ContainerBridge

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
        self.game = menu.selectedGame
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
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)
        ) == false {
            set(.unsupportedOS, "iOS 16.0 or newer is required")
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
            set(.gameNotInstalled, "\(game.bundleIdentifier) is not installed")
        case .accessDenied:
            menu.resolutions[game] = .accessDenied
            set(.containerAccessDenied, "The app container is sealed")
        case .bridgeUnavailable:
            menu.resolutions[game] = .bridgeUnavailable
            set(.containerBridgeUnavailable, "The container bridge is unavailable")
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

