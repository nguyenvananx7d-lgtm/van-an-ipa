import Foundation

/// Conservative anti-detection sweep for an already-injected game.
///
/// This is the "anti-ban" the panel can honestly run. It is not a claim that
/// the game's server-side ban logic is defeated — it is the local half of the
/// posture, and it does three things:
///
/// 1. Removes the panel's own residue from the target container: anything
///    owning the `.ffxc*` probe name that is NOT the staged patch or config.
///    A probing crash can leave the probe behind; it is ours and only ours to
///    delete.
/// 2. Flushes the page cache *before* the sweep, because anything flushed after
///    a delete would write the removed bytes straight back (same ordering rule
///    `WipeRoutine` uses).
/// 3. Flags — never deletes — unrecognised files whose contents carry the
///    panel's Mach-O signature, so the user gets a log line instead of the
///    routine guessing about files it cannot attribute.
///
/// The staged patch (`Assembly-CSharp-patch.bytes`, both stage names) and the
/// `localConfig.json` document are deliberately kept: this is the anti-ban
/// sweep, not the wipe. Re-stamping the session document is left to the
/// caller on the main actor, where it can reach the live controls.
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
        public let flagged: [String]
        public init(removed: [String], flagged: [String]) {
            self.removed = removed
            self.flagged = flagged
        }
    }

    /// Run the sweep. Nothing is thrown: a container that cannot resolve
    /// simply reports an empty sweep, and per-file failures land in `flagged`.
    public func run(game: Game) async -> SweepResult {
        let data: URL
        switch bridge.resolve(game: game) {
        case .resolved(let d): data = d
        default:
            log.log(.runtime, "anti-ban sweep for \(game.rawValue): container not resolved — skipped")
            return SweepResult(removed: [], flagged: [])
        }

        krw.flushAll()
        log.log(.kernelRW, "anti-ban: page cache flushed for \(game.rawValue)")

        // Only the access probe is ours to delete here. The patch (both stage
        // names) and the config are the point of this sweep — they stay.
        let keep = Set([
            ContainerBridge.patchName,
            ContainerBridge.patchInjectionName,
            "localConfig.json",
        ])

        var removed: [String] = []
        var flagged: [String] = []
        for dir in bridge.payloadDirectories(in: data) {
            for name in WipeRoutine.ownedNames where !keep.contains(name) {
                let url = dir.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    try FileManager.default.removeItem(at: url)
                    removed.append("\(dir.lastPathComponent)/\(name)")
                    log.log(.runtime, "anti-ban: removed \(name) from \(dir.lastPathComponent)")
                } catch {
                    flagged.append("\(dir.lastPathComponent)/\(name)")
                    log.log(.runtime, "anti-ban: could not remove \(name): \(error.localizedDescription)")
                }
            }
        }

        if let strays = scanForSignature(in: data) {
            flagged.append(contentsOf: strays)
            log.log(.runtime, "anti-ban: \(strays.count) unrecognised file(s) carry the panel signature")
        }

        log.log(.runtime, "anti-ban sweep finished for \(game.rawValue): removed \(removed.count), flagged \(flagged.count)")
        return SweepResult(removed: removed, flagged: flagged)
    }

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