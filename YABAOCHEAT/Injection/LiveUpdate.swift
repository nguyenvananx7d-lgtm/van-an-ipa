import Foundation

/// Keeps an active session alive and pulls down deployment updates.
///
/// The server issues a `lease_seconds` on every response. While the lease is
/// alive the app polls at `heartbeat_seconds`; once the sequence number stops
/// advancing, the server is treating us as a replay and the session is dropped.
public actor LiveUpdate {
    public static let shared = LiveUpdate(log: AppLog.shared)

    private let log: AppLog
    private var task: Task<Void, Never>?
    private var sequence = 0
    private var consecutiveErrors = 0

    public init(log: AppLog) {
        self.log = log
    }

    public enum UpdateError: Error, Sendable {
        case sessionInvalid
        case replayDetected
    }

    /// Begin polling. `interval` comes from the server's policy block.
    public func start(session: String, interval: Int, onUpdate: @Sendable @escaping (LicenseResponse) -> Void) {
        stop()
        let seconds = max(15, interval)
        log.log(.live, "heartbeat every \(seconds)s")

        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                do {
                    onUpdate(try await self.poll(session: session))
                } catch let error as LicenseError {
                    await self.handle(error)
                } catch {
                    await self.handle(LicenseError(code: .network))
                }
            }
        }
    }

    /// One heartbeat round trip, with the sequence bookkeeping kept on the actor.
    private func poll(session: String) async throws -> LicenseResponse {
        let response = try await LicensingClient.shared.heartbeat(
            session: session, sequence: sequence
        )
        sequence += 1
        consecutiveErrors = 0
        return response
    }

    public func stop() {
        task?.cancel()
        task = nil
        sequence = 0
        consecutiveErrors = 0
    }

    public var isRunning: Bool { task != nil }

    /// Fold one failure into the running state. Enough consecutive failures trips
    /// the offline state rather than letting the UI sit on a stale "online".
    private func handle(_ error: LicenseError) async {
        switch error.code {
        case .sessionInvalid, .replayDetected:
            log.log(.live, "session dropped: \(error.code.rawValue)")
            stop()
            NotificationCenter.default.post(name: Notifications.authorizationRevoked, object: error.code.rawValue)
            return
        default:
            break
        }

        consecutiveErrors += 1
        let limit = await LicensingClient.shared.currentPolicy().maxNetworkErrors
        log.log(.live, "heartbeat failed (\(consecutiveErrors)/\(limit)): \(error.code.rawValue)")

        if consecutiveErrors >= limit {
            log.log(.live, "network error limit reached; going offline")
            stop()
            NotificationCenter.default.post(name: Notifications.authorizationRevoked, object: "networkError")
        }
    }
}

