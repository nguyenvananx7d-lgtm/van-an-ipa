import Foundation

/// Conservative anti-detection sweep for an already-injected game.
///
/// This is the "anti-ban" the panel can honestly run. It is not a claim that
/// the game's server-side ban logic is defeated — it is the local half of the
/// posture, and it does four things:
///
/// 1. Removes the panel's own residue from the target container: the
///    `.ffxc*` probe names, the runtime's dropped `ffxc_debug.log`, and the
///    `testCodePatch*` marker the injected runtime writes to prove it engaged.
///    Those are ours and only ours to delete; the staged patch and the
///    `localConfig.json` document are never touched (this is the sweep, not the
///    wipe).
/// 2. Flushes the page cache *before* the sweep, because anything flushed after
///    a delete would write the removed bytes straight back (same ordering rule
///    `WipeRoutine` uses).
/// 3. **Masks the on-disk timestamps of the staged payload.** Newer clients
///    walk the container and flag files whose modification time is newer than
///    the app's own last-update baseline — an added patch written "seconds ago"
///    is a giveaway. Every staged copy (both stage names, both payload
///    directories, plus the config) is re-stamped to the container's
///    install-time reference (the MCM metadata plist's mtime), so the files
///    read as old as the app itself instead of "just modified".
/// 4. Flags — never deletes — unrecognised files whose contents carry the
///    panel's Mach-O signature, so the user gets a log line instead of the
///    routine guessing about files it cannot attribute.
///
/// Masking limits, stated honestly: `utimes`-visible `mtime`/`ctime` are
/// userspace-settable via `FileManager`, but the inode change time (`st_ctime`)
/// advances on *any* metadata write, including this masking itself. A scanner
/// that stats `ctime` — rather than `mtime` — cannot be fooled from userspace;
/// only the kernel path could, and it is not used here.
public actor AntiBanRoutine {
    public static let shared = AntiBanRoutine(log: AppLog.shared, bridge: ContainerBridge.shared, krw: KernelRW.shared)

    private let log: AppLog
    private let bridge: ContainerBridge
    private let krw: KernelRW

    public init(log: AppLog, bridge: ContainerBridge, krw: KernelRW) {
        self.log = log
        self.bridge = bridge
        self.krw = krw
    }

    public struct SweepResult: Sendable {
        public let removed: [String]
        public let masked: [String]
        public let flagged: [String]
        public init(removed: [String], masked: [String], flagged: [String]) {
            self.removed = removed
            self.masked = masked
            self.flagged = flagged
        }
    }

    /// Last-resort stamp when the container exposes no install-time reference.
    /// Deliberately a plainly-old fixed epoch rather than `Date()` so a missing
    /// reference can never leave the payload looking freshly written.
    static let fallbackBaseline = Date(timeIntervalSince1970: 1_700_000_000)

    /// Run the full sweep (residue removal + timestamp masking). Nothing is
    /// thrown: a container that cannot resolve simply reports an empty sweep,
    /// and per-file failures land in `flagged`.
    public func run(game: Game) async -> SweepResult {
        let data: URL
        switch bridge.resolve(game: game) {
        case .resolved(let d): data = d
        default:
            log.log(.antiBan, "sweep for \(game.rawValue): container not resolved — skipped")
            return SweepResult(removed: [], masked: [], flagged: [])
        }

        krw.flushAll()
        log.log(.kernelRW, "anti-ban: page cache flushed for \(game.rawValue)")

        let (removed, removeFailures) = removeResidue(in: data, game: game)
        let (masked, maskFailures) = conceal(in: data, game: game)

        var flagged = removeFailures + maskFailures
        if let strays = scanForSignature(in: data) {
            flagged.append(contentsOf: strays)
            log.log(.antiBan, "\(strays.count) unrecognised file(s) carry the panel signature")
        }

        log.log(.antiBan, "sweep finished for \(game.rawValue): removed \(removed.count), masked \(masked.count), flagged \(flagged.count)")
        return SweepResult(removed: removed, masked: masked, flagged: flagged)
    }

    /// Re-stamp only. Called after a live `localConfig.json` rewrite so the
    /// just-bumped mtime does not expose the session to a "file changed
    /// recently" scanner between full sweeps. No residue removal, no flush.
    @discardableResult
    public func conceal(game: Game) -> [String] {
        guard case .resolved(let data) = bridge.resolve(game: game) else {
            log.log(.antiBan, "mask for \(game.rawValue): container not resolved — skipped")
            return []
        }
        return conceal(in: data, game: game).masked
    }

    // MARK: - live guard

    /// Keeps the on-disk posture steady *while* the game runs.
    ///
    /// A one-shot sweep only proves the container was clean at inject time.
    /// During a session the injected runtime rewrites `localConfig.json` on
    /// every panel change, appends to its debug log and drops its engagement
    /// marker on launch, so the files a "written after install" scan looks for
    /// go fresh again within seconds of play. The guard closes that gap:
    ///
    /// - every `tick` seconds: flush the page cache, delete residue and
    ///   re-stamp the staged patch + config to the container baseline;
    /// - every `fullEvery` ticks: the complete sweep, signature walk included.
    ///
    /// Only one guard runs at a time; `endGuard()` fires on teardown and when
    /// the switch is turned off.
    private var guardTask: Task<Void, Never>?

    public var isGuarding: Bool { guardTask != nil }

    public func beginGuard(game: Game, tick: TimeInterval = 20, fullEvery: Int = 15) {
        guard guardTask == nil else { return }
        let interval = max(5, tick)
        let every = max(1, fullEvery)
        log.log(.antiBan, "live guard on for \(game.rawValue): stamp every \(Int(interval))s, full sweep every \(every * Int(interval))s")
        guardTask = Task { [weak self] in
            var round = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                round += 1
                if round % every == 0 {
                    _ = await self.run(game: game)
                } else {
                    await self.maskPass(game: game)
                }
            }
        }
    }

    public func endGuard() {
        guard guardTask != nil else { return }
        guardTask?.cancel()
        guardTask = nil
        log.log(.antiBan, "live guard stopped")
    }

    /// Light pass: flush, drop residue, re-stamp. No signature walk.
    private func maskPass(game: Game) {
        guard case .resolved(let data) = bridge.resolve(game: game) else { return }
        krw.flushAll()
        _ = removeResidue(in: data, game: game)
        let masked = conceal(in: data, game: game).masked
        if !masked.isEmpty {
            log.log(.antiBan, "live guard re-stamped \(masked.count) file(s)")
        }
    }
    // MARK: - residue

    /// Delete the panel's own leftovers (probe, runtime debug log, engagement
    /// marker) from every payload directory. The staged patch and config are
    /// never matched by `WipeRoutine.isResidue`, so they survive untouched.
    private func removeResidue(in data: URL, game: Game) -> (removed: [String], failures: [String]) {
        let fm = FileManager.default
        var removed: [String] = []
        var failures: [String] = []
        for dir in bridge.payloadDirectories(in: data) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where WipeRoutine.isResidue(name) {
                let url = dir.appendingPathComponent(name)
                do {
                    try fm.removeItem(at: url)
                    removed.append("\(dir.lastPathComponent)/\(name)")
                    log.log(.antiBan, "removed \(name) from \(dir.lastPathComponent)")
                } catch {
                    failures.append("\(dir.lastPathComponent)/\(name)")
                    log.log(.antiBan, "could not remove \(name): \(error.localizedDescription)")
                }
            }
        }
        return (removed, failures)
    }

    // MARK: - masking

    /// Stamp every staged payload copy (both stage names in both payload
    /// directories, plus the config) with the container's install-time
    /// reference, so an added-file/modified-file scan sees nothing newer than
    /// the app itself.
    private func conceal(in data: URL, game: Game) -> (masked: [String], failures: [String]) {
        let fm = FileManager.default
        let baseline = baselineDate(in: data)
        let full: [FileAttributeKey: Any] = [
            .modificationDate: baseline,
            .creationDate: baseline,
        ]
        let mtimeOnly: [FileAttributeKey: Any] = [.modificationDate: baseline]

        var masked: [String] = []
        var failures: [String] = []
        let targets = bridge.patchURLs(in: data, game: game) + bridge.configURLs(in: data, game: game)
        for url in targets where fm.fileExists(atPath: url.path) {
            do {
                try fm.setAttributes(full, ofItemAtPath: url.path)
                masked.append(url.lastPathComponent)
            } catch {
                // Birth-time is not settable on every build; mtime alone still
                // defeats the common "newer than install" comparison.
                do {
                    try fm.setAttributes(mtimeOnly, ofItemAtPath: url.path)
                    masked.append(url.lastPathComponent)
                } catch {
                    failures.append(url.lastPathComponent)
                    log.log(.antiBan, "mask failed for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        if !masked.isEmpty {
            log.log(.antiBan, "masked \(masked.count) payload file(s) to baseline \(Self.iso(baseline))")
        }
        return (masked, failures)
    }

    /// The container's install-time reference. The MCM metadata plist is
    /// written once when the container is created and is never touched by the
    /// game, so its mtime is a stable "app installed at" anchor the game's own
    /// files also carry.
    private func baselineDate(in data: URL) -> Date {
        let fm = FileManager.default
        let parent = data.deletingLastPathComponent()
        let candidates = [
            data.appendingPathComponent(ContainerBridge.mcmMetadataPlist),
            data.appendingPathComponent(ContainerBridge.mcmMetadataPlistWithUnderscore),
            parent.appendingPathComponent(ContainerBridge.mcmMetadataPlist),
            parent.appendingPathComponent(ContainerBridge.mcmMetadataPlistWithUnderscore),
        ]
        for url in candidates {
            if let date = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date {
                return date
            }
        }
        if let date = (try? fm.attributesOfItem(atPath: data.path))?[.creationDate] as? Date {
            return date
        }
        return AntiBanRoutine.fallbackBaseline
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - signature scan

    /// Find files in the container whose contents mention our Mach-O prefix.
    private func scanForSignature(in data: URL) -> [String]? {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: data,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let needle = Data(KernelRW.signature.utf8)
        var hits: [String] = []
        while let url = walker.nextObject() as? URL {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size < 4 * 1024 * 1024,
                  let blob = try? Data(contentsOf: url)
            else { continue }
            if blob.range(of: needle) != nil {
                hits.append(url.lastPathComponent)
            }
        }
        return hits.isEmpty ? nil : hits
    }
}
