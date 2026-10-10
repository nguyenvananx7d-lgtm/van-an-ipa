import Foundation
import SwiftUI
import Combine

/// Long-lived singletons, created once and handed to the view tree.
///
/// Exists so the stores have a single explicit owner. The stores themselves are
/// still `shared` statics, because the injection machinery reaches them from
/// places SwiftUI cannot reach; this type is the place that constructs the graph
/// and drives the lifecycle transitions, not a second source of state.
@MainActor
public final class AppEnvironment: ObservableObject {
    public let language = LanguageStore.shared
    public let menu = MenuStore.shared
    public let authorization = AuthorizationStore.shared
    public let inject = InjectStore.shared
    public let log = AppLog.shared

    /// True while the app is authorized and a key is stored.
    @Published public var isAuthorized: Bool = false
    @Published public var isDarkMode: Bool = true

    private let integrity: IntegrityChecker
    private var didLoad: Bool = false

    public init() {
        integrity = IntegrityChecker(log: log)
    }

    // MARK: - lifecycle

    public func handle(scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            guard !didLoad else { return }
            didLoad = true
            bootstrap()
        case .background:
            log.flush()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    /// First-activation work: check integrity, revalidate the stored key, and
    /// resolve the container for the selected game.
    private func bootstrap() {
        log.log(.auth, "startup: protocol v\(ProtocolConstants.protocolVersion)")

        let outcome = integrity.check(expectedPatchSHA256: nil, expectedNeutralSHA256: nil)
        if case .failed(let reason, _) = outcome {
            log.log(.integrity, "startup integrity check failed: \(reason.rawValue)")
            NotificationCenter.default.post(name: Notifications.integrityFailed, object: reason.rawValue)
        }

        authorization.revalidate()
        inject.evaluate()

        // Track authorization so the root view can swap between the license
        // screen and the main shell without polling.
        authorization.$status
            .sink { [weak self] status in
                self?.isAuthorized = status.isOnline
                self?.isDarkMode = true
            }
            .store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []
}
