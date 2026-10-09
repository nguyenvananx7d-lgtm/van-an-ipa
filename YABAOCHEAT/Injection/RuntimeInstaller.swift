import Foundation

/// Writes the payload into a resolved container and brings the target up.
///
/// Sequence: verify the payload digest, stage the patch and config everywhere
/// the target may read them, let the caller launch, then confirm the staged
/// bytes survive the watcher window when the target is already up.
public actor RuntimeInstaller {
    public static let shared = RuntimeInstaller(log: AppLog.shared, bridge: ContainerBridge.shared, krw: KernelRW.shared)

    private let log: AppLog
    private let bridge: ContainerBridge
    private let krw: KernelRW
    private let launcher: GameLauncher

    public init(log: AppLog, bridge: ContainerBridge, krw: KernelRW, launcher: GameLauncher? = nil) {
        self.log = log
        self.bridge = bridge
        self.krw = krw
        self.launcher = launcher ?? GameLauncher(log: log)
    }

    public enum InstallError: Error, Sendable {
        case containerNotFound
        case fileUnavailable
        case writeFailed(String)
        case integrityMismatch
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

        let patchURLs = bridge.patchURLs(in: data, game: game)
        let configURLs = bridge.configURLs(in: data, game: game)

        // Clear any previous copy first so a partial write can never be
        // mistaken for a good one on the next pass.
        for url in patchURLs + configURLs {
            try? FileManager.default.removeItem(at: url)
        }

        do {
            for url in patchURLs {
                try payload.data.write(to: url, options: .atomic)
            }
            log.log(.runtime, "staged patch (\(payload.data.count) bytes) in \(patchURLs.count) location(s)")
        } catch {
            for url in patchURLs { try? FileManager.default.removeItem(at: url) }
            log.log(.runtime, "patch write failed: \(error.localizedDescription)")
            throw InstallError.writeFailed(error.localizedDescription)
        }

        do {
            let config = PatchPayload.configuration(for: game, controls: controls)
            for url in configURLs {
                try config.write(to: url, options: .atomic)
            }
            log.log(.runtime, "staged config (\(config.count) bytes) in \(configURLs.count) location(s)")
        } catch {
            for url in patchURLs + configURLs { try? FileManager.default.removeItem(at: url) }
            log.log(.runtime, "config write failed: \(error.localizedDescription)")
            throw InstallError.writeFailed(error.localizedDescription)
        }

        let elapsed = await confirmStaging(
            game: game,
            patchURLs: patchURLs,
            digest: payload.sha256,
            monitorMs: monitorMs
        )

        return Result(patchURL: patchURLs[0], configURL: configURLs[0], openedAfter: elapsed)
    }

    /// Watcher window after staging. Its job is observation, not a hard gate:
    /// the bytes are on disk either way, and the caller's launch is what puts
    /// them in front of the runtime. When the target is not running there is
    /// nothing to observe, so the window is skipped entirely.
    private func confirmStaging(game: Game, patchURLs: [URL], digest: String, monitorMs: Int) async -> TimeInterval {
        guard launcher.isRunning(game: game) else {
            log.log(.runtime, "target not running; staged patch takes effect on launch")
            return 0
        }

        let start = Date()
        let deadline = start.addingTimeInterval(Double(max(0, monitorMs)) / 1000.0)
        while Date() < deadline {
            do {
                // Confirm what we staged is still what is on disk through the
                // window, and log the rare case where the target rewrote it —
                // respecting whatever it wrote rather than clobbering it back.
                let onDisk = try Data(contentsOf: patchURLs[0])
                if PatchPayload.digest(of: onDisk) != digest {
                    log.log(.runtime, "target rewrote the staged patch; keeping the target's copy")
                    return Date().timeIntervalSince(start)
                }
            } catch {
                log.log(.runtime, "staged patch unreadable during window: \(error.localizedDescription)")
                return Date().timeIntervalSince(start)
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        log.log(.runtime, "staged patch intact after \(monitorMs)ms watcher window")
        return Date().timeIntervalSince(start)
    }

    // MARK: - live config

    /// Rewrite only `localConfig.json` from the current controls. No digest
    /// check — the config is not signed, only the patch blob is — and no touch
    /// to `Assembly-CSharp-patch.bytes`. Called whenever a panel control
    /// changes so an already-injected session picks the change up on the
    /// game's next read instead of needing a full wipe and re-inject.
    @discardableResult
    public func restageConfig(game: Game, controls: FeatureControls) -> Int {
        guard case .resolved(let data) = bridge.resolve(game: game) else {
            log.log(.runtime, "config restage skipped for \(game.rawValue): container not resolved")
            return 0
        }
        let config = PatchPayload.configuration(for: game, controls: controls)
        var written = 0
        for url in bridge.configURLs(in: data, game: game) {
            if (try? config.write(to: url, options: .atomic)) != nil { written += 1 }
        }
        log.log(.runtime, "restaged config (\(config.count) bytes) to \(written) location(s) for \(game.rawValue)")
        return written
    }

    // MARK: - remove

    public func uninject(game: Game) async throws {
        let data: URL
        switch bridge.resolve(game: game) {
        case .resolved(let d): data = d
        default: throw InstallError.containerNotFound
        }
        let urls = bridge.patchURLs(in: data, game: game) + bridge.configURLs(in: data, game: game)
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
        krw.flushAll()
        log.log(.runtime, "removed patch and config for \(game.rawValue) from \(urls.count) location(s)")
    }

    /// Re-stage the same patch to force the game to reload it. Used by the reset
    /// command when the target is already running.
    public func reset(game: Game) async throws {
        log.log(.runtime, "reset requested for \(game.rawValue)")
        try await uninject(game: game)
    }
}