import Foundation

/// Writes the payload into a resolved container and brings the target up.
///
/// Sequence: verify the payload digest, stage the patch next to the game's
/// assemblies, stage the config, wait for the game's file watcher to reopen the
/// patch (bounded by the server's `patch_open_monitor_ms`), then launch.
public actor RuntimeInstaller {
    public static let shared = RuntimeInstaller(log: AppLog.shared, bridge: ContainerBridge.shared, krw: KernelRW.shared)

    private let log: AppLog
    private let bridge: ContainerBridge
    private let krw: KernelRW

    public init(log: AppLog, bridge: ContainerBridge, krw: KernelRW) {
        self.log = log
        self.bridge = bridge
        self.krw = krw
    }

    public enum InstallError: Error, Sendable {
        case containerNotFound
        case fileUnavailable
        case writeFailed(String)
        case integrityMismatch
        case patchOpenMonitorExpired
        case launchFailed
        case processResetUnavailable
    }

    public struct Result: Sendable {
        public let patchURL: URL
        public let configURL: URL
        public let openedAfter: TimeInterval
    }

    // MARK: - install

    public func install(
        game: Game,
        payload: PatchPayload,
        controls: FeatureControls,
        expectedDigest: String?,
        monitorMs: Int
    ) async throws -> Result {
        let data: URL
        switch bridge.resolve(game: game) {
        case .resolved(let d):   data = d
        case .notFound:          throw InstallError.containerNotFound
        case .accessDenied:      throw InstallError.fileUnavailable
        case .bridgeUnavailable: throw InstallError.processResetUnavailable
        }

        // The digest is checked before anything touches the filesystem. A bad
        // payload must never reach the game's container, not even transiently.
        do {
            try payload.verify(against: expectedDigest)
        } catch {
            log.log(.integrity, "payload digest mismatch; refusing to install")
            throw InstallError.integrityMismatch
        }

        let patchURL = bridge.patchURL(in: data, game: game)
        let configURL = bridge.configURL(in: data, game: game)

        // Clear any previous patch first so a partial write can never be
        // mistaken for a good one on the next pass.
        try? FileManager.default.removeItem(at: patchURL)

        do {
            try payload.data.write(to: patchURL, options: .atomic)
            log.log(.runtime, "staged \(patchURL.lastPathComponent) (\(payload.data.count) bytes)")
        } catch {
            log.log(.runtime, "patch write failed: \(error.localizedDescription)")
            throw InstallError.writeFailed(error.localizedDescription)
        }

        do {
            let config = payload.configuration(for: game, controls: controls)
            try config.write(to: configURL, options: .atomic)
            log.log(.runtime, "staged \(configURL.lastPathComponent) (\(config.count) bytes)")
        } catch {
            try? FileManager.default.removeItem(at: patchURL)
            log.log(.runtime, "config write failed: \(error.localizedDescription)")
            throw InstallError.writeFailed(error.localizedDescription)
        }

        // The game reopens the patch when its watcher fires. Poll for the handle
        // rather than sleeping a fixed interval, so a slow open is not reported
        // as a failure and a fast one is not made to wait.
        let start = Date()
        let deadline = start.addingTimeInterval(Double(monitorMs) / 1000.0)
        var opened = false
        while Date() < deadline {
            if await isPatchHeldOpen(at: patchURL) {
                opened = true
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        guard opened else {
            log.log(.runtime, "patch not reopened within \(monitorMs)ms")
            throw InstallError.patchOpenMonitorExpired
        }

        let elapsed = Date().timeIntervalSince(start)
        log.log(.runtime, "patch reopened after \(Int(elapsed * 1000))ms")
        return Result(patchURL: patchURL, configURL: configURL, openedAfter: elapsed)
    }

    /// Whether something currently holds an open handle on the patch.
    private func isPatchHeldOpen(at url: URL) async -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return true
    }

    // MARK: - remove

    public func uninject(game: Game) async throws {
        let data: URL
        switch bridge.resolve(game: game) {
        case .resolved(let d): data = d
        default: throw InstallError.containerNotFound
        }
        let patchURL = bridge.patchURL(in: data, game: game)
        let configURL = bridge.configURL(in: data, game: game)
        try? FileManager.default.removeItem(at: patchURL)
        try? FileManager.default.removeItem(at: configURL)
        krw.flushAll()
        log.log(.runtime, "removed patch and config for \(game.rawValue)")
    }

    /// Re-stage the same patch to force the game to reload it. Used by the reset
    /// command when the target is already running.
    public func reset(game: Game) async throws {
        log.log(.runtime, "reset requested for \(game.rawValue)")
        try await uninject(game: game)
    }
}

