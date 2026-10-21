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

<<<<<<< HEAD
        let patchURLs = bridge.patchURLs(in: data, game: game)
        let configURLs = bridge.configURLs(in: data, game: game)

        // The app now ships the real, populated IFix blob (`expectedLength`
        // bytes) that carries the aim/ESP overrides and the `HeadRate` /
        // `BodyRate` silent-aim split directly. It is the payload we want in
        // the container — always. Adopting a larger on-disk, backed-up, or
        // vendor blob (a path that predates this, back when the bundle held a
        // 322-byte neutral manifest) would overwrite those overrides with the
        // vendor's unpatched code and silently undo the fix. So the bundle wins
        // whenever it holds the real blob; only a stripped build that does not
        // falls back to adopting one from the container.
        let bundledIsRealPatch = payload.data.count == PatchPayload.expectedLength
        let activePatch: Data
        if bundledIsRealPatch {
            // The bundled blob's digest is the pin (server-provided, else the
            // local pin), so a tampered bundle is refused before any write.
            do {
                try payload.verify(against: expectedDigest)
            } catch {
                log.log(.integrity, "payload digest mismatch; refusing to install")
                throw InstallError.integrityMismatch
            }
            activePatch = payload.data
        } else {
            let onDiskPatch = RuntimeInstaller.adoptablePatch(in: patchURLs)
            let backedUpPatch = RuntimeInstaller.adoptablePatch(in: [RuntimeInstaller.backupURL])
            // A vendor run occasionally stages the real patch outside the four
            // known names (Library/, tmp/, a Documents subfolder). A
            // whole-container scan for the pinned payload digest catches those.
            let hiddenPatch = RuntimeInstaller.whitelistedPatch(in: [data])
            guard let real = onDiskPatch ?? backedUpPatch ?? hiddenPatch else {
                log.log(.integrity, "bundled payload is not the real blob and no real patch is staged; refusing to install")
                throw InstallError.integrityMismatch
            }
            RuntimeInstaller.storeBackup(real)
            log.log(.runtime, "adopted real patch (\(real.count) bytes, sha256=\(PatchPayload.digest(of: real))) — bundled resource is not the real blob")
            activePatch = real
        }

=======
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

>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
        // Clear any previous copy first so a partial write can never be
        // mistaken for a good one on the next pass.
        for url in patchURLs + configURLs {
            try? FileManager.default.removeItem(at: url)
        }

        do {
            for url in patchURLs {
<<<<<<< HEAD
                try activePatch.write(to: url, options: .atomic)
            }
            log.log(.runtime, "staged patch (\(activePatch.count) bytes) in \(patchURLs.count) location(s)")
=======
                try payload.data.write(to: url, options: .atomic)
            }
            log.log(.runtime, "staged patch (\(payload.data.count) bytes) in \(patchURLs.count) location(s)")
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
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
<<<<<<< HEAD
            digest: PatchPayload.digest(of: activePatch),
=======
            digest: payload.sha256,
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
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
        bridge.releaseGrants()
        log.log(.runtime, "removed patch and config for \(game.rawValue) from \(urls.count) location(s) and released sandbox grants")
    }

<<<<<<< HEAD
    /// Detach the app from the session without disarming the target: the
    /// staged patch and its `localConfig.json` stay in the container untouched,
    /// so the next launch still runs with the aim / ESP the panel staged.
    /// Nothing is removed, flushed, or released — the app simply stops
    /// claiming the session. Paired with the full `uninject` as the
    /// "keep aim & ESP" option in the panel.
    public func keepFeatures(game: Game) {
        var stagedPatch = 0
        var stagedConfig = 0
        switch bridge.resolve(game: game) {
        case .resolved(let data):
            stagedPatch = bridge.patchURLs(in: data, game: game).count
            stagedConfig = bridge.configURLs(in: data, game: game).count
            log.log(.runtime, "kept \(stagedPatch) patch / \(stagedConfig) config location(s) staged for \(game.rawValue); app detached, aim/ESP stay live")
        default:
            log.log(.runtime, "keep for \(game.rawValue): container not resolved — detaching anyway, nothing on disk to touch")
        }
    }

=======
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
    /// Re-stage the same patch to force the game to reload it. Used by the reset
    /// command when the target is already running.
    public func reset(game: Game) async throws {
        log.log(.runtime, "reset requested for \(game.rawValue)")
        try await uninject(game: game)
    }
<<<<<<< HEAD

    // MARK: - real patch

    /// A staged blob larger than the neutral manifest is the vendor's real IFix
    /// patch. Nil when only neutral copies (or nothing) are present.
    private static func adoptablePatch(in urls: [URL]) -> Data? {
        let fm = FileManager.default
        for url in urls {
            guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
                  size.int64Value > Int64(PatchPayload.expectedLength),
                  let blob = try? Data(contentsOf: url) else { continue }
            return blob
        }
        return nil
    }

    /// Scan the container for any blob whose digest matches the vendor's real
    /// payload. The adoption above only looks at the four known stage names;
    /// this catches a copy that was placed (or cached) elsewhere — Library/,
    /// tmp/, a Documents subfolder.
    private static func whitelistedPatch(in roots: [URL]) -> Data? {
        let fm = FileManager.default
        for root in roots {
            if let blob = findBlob(
                matching: PatchPayload.vendorPatchSHA256,
                under: root, fm: fm, depth: 0, maxDepth: 6
            ) {
                return blob
            }
        }
        return nil
    }

    private static func findBlob(
        matching sha: String, under dir: URL, fm: FileManager, depth: Int, maxDepth: Int
    ) -> Data? {
        guard depth <= maxDepth, let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }
        for name in entries {
            if name == "." || name == ".." { continue }
            let url = dir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let found = findBlob(matching: sha, under: url, fm: fm, depth: depth + 1, maxDepth: maxDepth) {
                    return found
                }
            } else {
                // Only stat and read plausible blobs: nothing as small as the
                // neutral manifest, nothing past the patch size band.
                let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
                guard size > PatchPayload.expectedLength, size <= 262_144,
                      let data = try? Data(contentsOf: url),
                      PatchPayload.digest(of: data).caseInsensitiveCompare(sha) == .orderedSame
                else { continue }
                return data
            }
        }
        return nil
    }

    /// Keep the real patch in this app's own container so a wipe or an
    /// un-inject cannot lose the only working payload.
    private static func storeBackup(_ data: Data) {
        try? data.write(to: backupURL, options: .atomic)
    }

    private static var backupURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("ffxc_real_patch.bytes")
    }
=======
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
}