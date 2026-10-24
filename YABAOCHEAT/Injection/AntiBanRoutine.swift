import Foundation
import Darwin

/// Anti-detection sweep for an already-injected game.
///
/// This is the local half of the posture, and it covers every userspace-visible
/// signal an "is this container modified?" scanner can read out of the target's
/// own sandbox:
///
/// 1. **Residue**, anywhere in the container. The `.ffxc*` probe names, the
///    runtime's dropped `ffxc_debug.log` and the `testCodePatch*` engagement
///    marker are deleted from every directory the sweep can reach, not just the
///    two payload directories. The staged patch and the config are never
///    matched — they are the payload, not residue.
/// 2. **File timestamps.** Every staged copy (both stage names, both payload
///    directories, plus the config) is re-stamped to the container's
///    install-time reference so an "added file newer than install" or
///    "modified file" comparison finds nothing. `mtime`, `atime` and — where
///    the filesystem allows it — `birthtime` are all covered.
/// 3. **Directory timestamps.** Creating or deleting an entry bumps the
///    *parent* directory's `mtime`, which is a much more obvious tell than the
///    file itself: a scanner that only checks directories still sees
///    `Documents/` written "seconds ago". Every directory the sweep mutated is
///    restored deepest-first up to and including the container root.
/// 4. **The inode change time.** `ctime` is not settable from userspace at all.
///    `KernelMask` forges it in the vnode when the kernel R/W chain is up, so
///    the one field a `stat`-based scanner can trust stops agreeing with it.
/// 5. **String references.** Text the target or the system wrote into the
///    container (Unity logs, crash reports, caches) that still spells our
///    artifact names is rewritten in place with same-length neutral spellings,
///    then re-stamped, so a log-scraping scan finds nothing to grep.
/// 6. **Process identity.** The panel's kernel-side short name is replaced with
///    a system-looking name so a process-table walk does not surface an
///    injector next to the game.
/// 7. **How the file arrived.** iOS writes `com.apple.provenance` (and
///    sometimes quarantine / metadata attributes) onto files a *different* app
///    created. Those describe origin, not content, and no timestamp pass hides
///    them, so they are stripped from the staged payload. The POSIX mode is
///    mirrored from a file the game itself wrote, so the copy does not stand
///    out by permission bits alone.
/// 8. **Payload integrity.** A staged blob that is missing or no longer matches
///    the pinned digest (game updater replaced the container, another tool
///    overwrote the name) is repaired from the bundle before anything else, so
///    a session cannot end up "armed" with no patch while the mismatch itself
///    is the loudest thing a scanner could find.
///
/// Ordering is not incidental. The page cache is flushed before any delete
/// (anything flushed after a delete writes the removed bytes straight back).
/// Userspace stamps run before the kernel forge, because a VFS metadata write
/// re-stamps `ctime` — only the kernel write may be last. Attribute and mode
/// changes run *before* the timestamp stamp for the same reason, and the repair
/// runs before both because it writes bytes. And the signature walk runs before
/// the forge so its reads cannot bump an already-forged atime.
///
/// Limits, stated honestly: this cannot defeat server-side telemetry, an
/// in-memory integrity check inside the game, or a scanner that is running
/// *inside* the target while the payload is loaded. It defeats the filesystem
/// and process-table evidence, which is what survives a session.
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
        /// Directories whose timestamps were restored after the sweep mutated
        /// their contents or deleted residue from them.
        public let directories: [String]
        /// Nodes whose in-kernel `ctime` was forged back to the baseline.
        public let kernelForged: [String]
        /// Text files whose contents referenced our artifacts and were
        /// rewritten with neutral spellings.
        public let scrubbed: [String]

        public init(
            removed: [String],
            masked: [String],
            flagged: [String],
            directories: [String] = [],
            kernelForged: [String] = [],
            scrubbed: [String] = []
        ) {
            self.removed = removed
            self.masked = masked
            self.flagged = flagged
            self.directories = directories
            self.kernelForged = kernelForged
            self.scrubbed = scrubbed
        }

        /// True when the sweep found nothing to do at all — the steady state of
        /// a clean, idle session.
        public var isEmpty: Bool {
            removed.isEmpty && masked.isEmpty && flagged.isEmpty
                && directories.isEmpty && kernelForged.isEmpty && scrubbed.isEmpty
        }
    }

    /// Last-resort stamp when the container exposes no install-time reference.
    /// Deliberately a plainly-old fixed epoch rather than `Date()` so a missing
    /// reference can never leave the payload looking freshly written.
    static let fallbackBaseline = Date(timeIntervalSince1970: 1_700_000_000)

    /// Neutral, same-length spellings for the panel's artifact names. Length is
    /// preserved so a rewrite never changes a file's size (a size delta is its
    /// own "someone edited this" signal).
    static let scrubMap: [(from: String, to: String)] = [
        ("Assembly-CSharp-patch", "Assembly-CSharp-cache"),
        ("localConfig.json", "gameConfigs.json"),
        ("FFXC-MACHO-PREFIX-v2", "MCFG-MACHO-PREFIX-v2"),
        ("ffxc_debug.log", "mcfg_debug.log"),
        ("testCodePatch", "testAssetLoad"),
        ("ffxc", "mcfg"),
        ("FFXC", "MCFG"),
    ]

    /// Text extensions worth scanning for our strings. Anything else in a
    /// container is a game asset or a binary and is never rewritten.
    static let scrubExtensions: Set<String> = [
        "log", "txt", "json", "plist", "cfg", "ini", "xml", "csv", "yaml", "yml",
    ]

    /// Kernel-side name this process wears while a session is live. A system
    /// helper spelling, so a process walk cannot pick it out by pattern.
    static let processAlias = "WebKit.Networking"

    // MARK: - sweep

    /// Run the full sweep. Nothing is thrown: a container that cannot resolve
    /// simply reports an empty sweep, and per-file failures land in `flagged`.
    public func run(game: Game) async -> SweepResult {
        let data: URL
        switch bridge.resolve(game: game) {
        case .resolved(let d): data = d
        default:
            log.log(.antiBan, "sweep for \(game.rawValue): container not resolved — skipped")
            return SweepResult(removed: [], masked: [], flagged: [])
        }

        maskProcessIdentity()

        // Anything flushed after a delete writes the removed bytes straight
        // back, so the cache goes first — the same rule the wipe uses.
        krw.flushAll()
        log.log(.kernelRW, "anti-ban: page cache flushed for \(game.rawValue)")

        let baseline = baselineDate(in: data)
        var flagged: [String] = []

        // Repair first: it writes bytes, and the mask pass that follows is what
        // stops those bytes from looking fresh.
        let restored = restorePayload(in: data, game: game)

        let residue = removeResidue(in: data)
        flagged.append(contentsOf: residue.failures)

        let concealResult = conceal(in: data, game: game, baseline: baseline)
        flagged.append(contentsOf: concealResult.failures)

        let scrubbed = scrubReferences(in: data, baseline: baseline)

        // Directory stamps come after every mutation: scrub writes land in
        // Library / tmp, and each of those writes bumps its parent.
        var touched = Set(residue.directories)
        touched.formUnion(concealResult.directories)
        touched.formUnion(scrubbed.directories)
        let directories = restoreDirectories(Array(touched), upTo: data, baseline: baseline)

        // Observation only, and atime-preserving: reading a game file to look
        // for our signature must not leave an access-time trail.
        if let strays = scanForSignature(in: data, game: game) {
            flagged.append(contentsOf: strays)
            log.log(.antiBan, "\(strays.count) unrecognised file(s) carry the panel signature")
        }

        // Kernel forge last: it must be the final write on these inodes, and it
        // must not be followed by any VFS metadata operation.
        let forged = forgeKernelTimestamps(game: game, data: data, baseline: baseline)

        let result = SweepResult(
            removed: residue.removed,
            masked: concealResult.masked,
            flagged: flagged,
            directories: directories,
            kernelForged: forged,
            scrubbed: scrubbed.files
        )
        log.log(
            .antiBan,
            "sweep finished for \(game.rawValue): restored \(restored.count), removed \(result.removed.count), "
            + "masked \(result.masked.count), dirs \(directories.count), "
            + "ctime \(forged.count), scrubbed \(result.scrubbed.count), flagged \(flagged.count)"
        )
        return result
    }

    /// Re-stamp only. Called after a live `localConfig.json` rewrite so the
    /// just-bumped mtime does not expose the session to a "file changed
    /// recently" scanner between full sweeps. No residue removal, no flush.
    ///
    /// The config write also bumps the *directory*, and the file's `ctime`, so
    /// this does the same three parts the full sweep does for those two nodes:
    /// file stamp, parent stamp, kernel forge.
    @discardableResult
    public func conceal(game: Game) -> [String] {
        guard case .resolved(let data) = bridge.resolve(game: game) else {
            log.log(.antiBan, "mask for \(game.rawValue): container not resolved — skipped")
            return []
        }
        let baseline = baselineDate(in: data)
        let result = conceal(in: data, game: game, baseline: baseline)
        _ = restoreDirectories(result.directories, upTo: data, baseline: baseline)
        _ = forgeKernelTimestamps(game: game, data: data, baseline: baseline)
        return result.masked
    }

    // MARK: - live guard

    /// Keeps the on-disk posture steady *while* the game runs.
    ///
    /// A one-shot sweep only proves the container was clean at inject time.
    /// During a session the injected runtime rewrites `localConfig.json` on
    /// every panel change and drops its engagement marker on launch, so the
    /// files a "written after install" scan looks for go fresh again within
    /// seconds of play. The guard closes that gap:
    ///
    /// - every tick: flush, drop residue, re-stamp files *and* their
    ///   directories, forge `ctime`;
    /// - every `fullEvery` ticks: the complete sweep, signature walk and
    ///   content scrub included.
    ///
    /// The tick is jittered ±40 %. A perfectly periodic metadata pass is a
    /// schedule an observer can learn; an irregular one is not. Only one guard
    /// runs at a time; `endGuard()` fires on teardown and when the switch is
    /// turned off.
    private var guardTask: Task<Void, Never>?

    public var isGuarding: Bool { guardTask != nil }

    public func beginGuard(game: Game, tick: TimeInterval = 20, fullEvery: Int = 15) {
        guard guardTask == nil else { return }
        let interval = max(5, tick)
        let every = max(1, fullEvery)
        log.log(
            .antiBan,
            "live guard on for \(game.rawValue): jittered ~\(Int(interval))s tick, "
            + "full sweep every \(every * Int(interval))s"
        )
        guardTask = Task { [weak self] in
            var round = 0
            while !Task.isCancelled {
                let jitter = Double.random(in: 0.6...1.4)
                try? await Task.sleep(nanoseconds: UInt64(interval * jitter * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                round += 1
                if round % every == 0 {
                    _ = await self.run(game: game)
                } else {
                    await self.lightPass(game: game)
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

    /// Light pass: flush, drop residue, re-stamp files + parents, forge ctime.
    /// No signature walk, no content scrub — those read broadly and are left
    /// to the full sweep.
    private func lightPass(game: Game) async {
        guard case .resolved(let data) = bridge.resolve(game: game) else { return }
        krw.flushAll()
        let baseline = baselineDate(in: data)
        let residue = removeResidue(in: data)
        let concealed = conceal(in: data, game: game, baseline: baseline)
        var touched = Set(residue.directories)
        touched.formUnion(concealed.directories)
        let dirs = restoreDirectories(Array(touched), upTo: data, baseline: baseline)
        let forged = forgeKernelTimestamps(game: game, data: data, baseline: baseline)
        if !concealed.masked.isEmpty || !dirs.isEmpty || !forged.isEmpty {
            log.log(
                .antiBan,
                "live guard: \(concealed.masked.count) file(s), \(dirs.count) dir(s), "
                + "\(forged.count) ctime forged"
            )
        }
    }

    // MARK: - residue

    /// Delete the panel's own leftovers (probe, runtime debug log, engagement
    /// marker) from every directory in the container, and report the parents
    /// so their timestamps can be restored.
    ///
    /// `WipeRoutine.isResidue` never matches the staged patch or config, so the
    /// payload survives untouched. Hidden files are *not* skipped here — the
    /// probe is a dotfile by design.
    private func removeResidue(in data: URL) -> (removed: [String], failures: [String], directories: [String]) {
        let fm = FileManager.default
        var removed: [String] = []
        var failures: [String] = []
        var directories: Set<String> = []

        walk(data, maxDepth: 6) { url, isDirectory in
            let name = url.lastPathComponent
            guard WipeRoutine.isResidue(name) else { return }
            let parent = url.deletingLastPathComponent().path
            do {
                try fm.removeItem(at: url)
                // A directory removal takes its subtree; the parent is the node
                // whose mtime the removal actually bumped.
                directories.insert(parent)
                removed.append("\(url.deletingLastPathComponent().lastPathComponent)/\(name)")
                log.log(.antiBan, "removed \(name) from \(url.deletingLastPathComponent().lastPathComponent)")
            } catch {
                failures.append("\(parent)/\(name)")
                log.log(.antiBan, "could not remove \(name): \(error.localizedDescription)")
            }
        }
        return (removed, failures, Array(directories))
    }

    // MARK: - masking

    /// Stamp every staged payload copy and the config with the container's
    /// install-time reference, so an added-file / modified-file scan sees
    /// nothing newer than the app itself. Returns the payload directories as
    /// "touched" so the caller restores them too.
    private func conceal(in data: URL, game: Game, baseline: Date) -> (masked: [String], failures: [String], directories: [String]) {
        var masked: [String] = []
        var directories: Set<String> = []
        let reference = referenceMode(in: data)

        let targets = bridge.patchURLs(in: data, game: game) + bridge.configURLs(in: data, game: game)
        for url in targets where FileManager.default.fileExists(atPath: url.path) {
            // Origin attributes and permission bits first: both are metadata
            // writes, and the stamp below has to be the last userspace write on
            // this inode before the kernel forge.
            let cleared = stripProvenance(url)
            let modeChanged = mirrorMode(url, reference)
            if cleared || modeChanged {
                log.log(.antiBan, "normalised origin of \(url.lastPathComponent)")
            }
            if stamp(url, baseline: baseline) {
                masked.append(url.lastPathComponent)
                directories.insert(url.deletingLastPathComponent().path)
            }
        }
        // The staged file may have just been written by the installer, in which
        // case its parent's mtime is fresh even though the file itself was
        // already at the baseline.
        for dir in bridge.payloadDirectories(in: data) {
            directories.insert(dir.path)
        }
        if !masked.isEmpty {
            log.log(.antiBan, "masked \(masked.count) payload file(s) to baseline \(Self.iso(baseline))")
        }
        return (masked, [], Array(directories))
    }

    /// Re-stage the pinned payload when a staged copy is missing or replaced.
    ///
    /// Two things cause this in the wild: the game's own updater rewrites the
    /// container, or another tool overwrote the staged name. Either way the
    /// session would run without the patch while the panel still reports it as
    /// armed — and a blob that does not match its pin is the single loudest
    /// artifact in the container. The write is in place (no sibling temp, no
    /// rename) so the repair adds one modification instead of two directory
    /// events, and it refuses anything that does not match the bundle pin, so a
    /// tampered bundle cannot use this path to plant bytes.
    private func restorePayload(in data: URL, game: Game) -> [String] {
        guard let bundled = try? PatchPayload.bundled() else { return [] }
        guard bundled.data.count == PatchPayload.expectedLength else {
            log.log(.antiBan, "bundled payload length does not match the pin — not re-staging")
            return []
        }
        guard bundled.sha256.caseInsensitiveCompare(PatchPayload.vendorPatchSHA256) == .orderedSame else {
            log.log(.antiBan, "bundled payload digest does not match the pin — not re-staging")
            return []
        }
        var restored: [String] = []
        for url in bridge.patchURLs(in: data, game: game) {
            if let existing = try? Data(contentsOf: url),
               existing.count == bundled.data.count,
               PatchPayload.digest(of: existing) == bundled.sha256 {
                continue
            }
            guard QuietWrite.writeInPlace(bundled.data, to: url.path) else {
                log.log(.antiBan, "re-stage failed for \(url.lastPathComponent)")
                continue
            }
            restored.append(url.lastPathComponent)
            log.log(.antiBan, "re-staged \(url.lastPathComponent) (\(bundled.data.count) bytes)")
        }
        return restored
    }

    /// The permission bits a file in this container already wears. The MCM
    /// metadata plist is written by the system when the container is created,
    /// so it is the closest thing to "the mode this container uses".
    private func referenceMode(in data: URL) -> mode_t? {
        let candidates = [
            data.appendingPathComponent(ContainerBridge.mcmMetadataPlist),
            data.appendingPathComponent(ContainerBridge.mcmMetadataPlistWithUnderscore),
        ]
        for url in candidates {
            var info = stat()
            if stat(url.path, &info) == 0 {
                return info.st_mode & 0o777
            }
        }
        var info = stat()
        if stat(data.path, &info) == 0 {
            return info.st_mode & 0o777
        }
        return nil
    }

    /// Bring a staged file's mode in line with the container's own. A payload
    /// written by this app can carry a different `umask` result than the game's
    /// files, and `stat` reports that just as plainly as a timestamp.
    @discardableResult
    private func mirrorMode(_ url: URL, _ reference: mode_t?) -> Bool {
        guard let reference else { return false }
        var info = stat()
        guard stat(url.path, &info) == 0 else { return false }
        let current = info.st_mode & 0o777
        guard current != reference else { return false }
        return chmod(url.path, reference) == 0
    }

    /// Remove the extended attributes iOS attaches to files a different app
    /// created. `com.apple.provenance` in particular is what a forensic pass
    /// uses to separate "written by this app" from "shipped with the container",
    /// and no timestamp pass touches it.
    @discardableResult
    private func stripProvenance(_ url: URL) -> Bool {
        var cleared = false
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            let listSize = listxattr(path, nil, 0, 0)
            guard listSize > 0 else { return }
            var names = [CChar](repeating: 0, count: Int(listSize))
            let read = listxattr(path, &names, names.count, 0)
            guard read > 0 else { return }
            names.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                var offset = 0
                while offset < Int(read) {
                    let name = String(cString: base + offset)
                    offset += name.utf8.count + 1
                    guard AntiBanRoutine.isPanelProvenance(name) else { continue }
                    if removexattr(path, name, 0) == 0 {
                        cleared = true
                    }
                }
            }
        }
        return cleared
    }

    /// Only attributes that describe *how the file arrived*. Anything else on a
    /// container file may be required by the sandbox, so it stays.
    private static func isPanelProvenance(_ name: String) -> Bool {
        name.hasPrefix("com.apple.quarantine")
            || name.hasPrefix("com.apple.provenance")
            || name.hasPrefix("com.apple.metadata")
            || name.hasPrefix("com.apple.lastuseddate")
            || name.hasPrefix("com.apple.FinderInfo")
    }

    /// Restore one node's `mtime` + `atime` to `baseline`, and its `birthtime`
    /// where the filesystem accepts it.
    ///
    /// Deliberately skips nodes that already read as the baseline: every
    /// `setattrlist` / `utimes` call advances `ctime`, and a guard that
    /// re-stamps the same file every few seconds is itself a pattern. Returns
    /// true only when a write actually happened.
    @discardableResult
    private func stamp(_ url: URL, baseline: Date) -> Bool {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return false }
        let want = Int32(clamping: Int(baseline.timeIntervalSince1970))
        let mtime = Int32(clamping: Int(info.st_mtimespec.tv_sec))
        let atime = Int32(clamping: Int(info.st_atimespec.tv_sec))
        if mtime == want && atime == want { return false }

        let times = [
            timeval(tv_sec: Int(want), tv_usec: 0),
            timeval(tv_sec: Int(want), tv_usec: 0),
        ]
        let stamped = url.path.withCString { utimes($0, times) } == 0

        // Birth time is not part of `utimes`; `setattrlist`-backed
        // `FileManager` is the only userspace route and is not honoured on
        // every build, so a failure here is expected and non-fatal.
        if let birth = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.creationDate] as? Date,
           abs(birth.timeIntervalSince(baseline)) > 1 {
            try? FileManager.default.setAttributes([.creationDate: baseline], ofItemAtPath: url.path)
        }
        return stamped
    }

    /// Restore every touched directory and its ancestors up to the container
    /// root, deepest first. Restoring shallow nodes first would let a parent
    /// write re-bump a child's already-restored entry.
    private func restoreDirectories(_ paths: [String], upTo root: URL, baseline: Date) -> [String] {
        var all: Set<String> = []
        for path in paths {
            var url = URL(fileURLWithPath: path)
            while url.path.count >= root.path.count {
                all.insert(url.path)
                if url.path == root.path { break }
                let parent = url.deletingLastPathComponent()
                if parent.path == url.path { break }
                url = parent
            }
        }
        let ordered = all.sorted {
            $0.split(separator: "/").count > $1.split(separator: "/").count
        }
        var stamped: [String] = []
        for path in ordered {
            if stamp(URL(fileURLWithPath: path), baseline: baseline) {
                stamped.append((path as NSString).lastPathComponent)
            }
        }
        if !stamped.isEmpty {
            log.log(.antiBan, "restored \(stamped.count) directory timestamp(s)")
        }
        return stamped
    }

    /// The container's install-time reference.
    ///
    /// The MCM metadata plist is written once when the container is created and
    /// is never touched by the game, so its mtime is a stable "app installed
    /// at" anchor the game's own files also carry. Container creation time is
    /// the fallback; a baseline that is implausibly recent (a plist touched by
    /// something else) is rejected in favour of the fixed old epoch, because a
    /// baseline of "now" is worse than no baseline at all.
    private func baselineDate(in data: URL) -> Date {
        let fm = FileManager.default
        let parent = data.deletingLastPathComponent()
        let candidates = [
            data.appendingPathComponent(ContainerBridge.mcmMetadataPlist),
            data.appendingPathComponent(ContainerBridge.mcmMetadataPlistWithUnderscore),
            parent.appendingPathComponent(ContainerBridge.mcmMetadataPlist),
            parent.appendingPathComponent(ContainerBridge.mcmMetadataPlistWithUnderscore),
        ]
        var values: [Date] = []
        for url in candidates {
            if let date = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date {
                values.append(date)
            }
        }
        if let birth = (try? fm.attributesOfItem(atPath: data.path))?[.creationDate] as? Date {
            values.append(birth)
        }
        // Prefer the oldest plausible value: the install reference cannot be
        // newer than the app, and a later read only ever drifts forward.
        let ceiling = Date().addingTimeInterval(-3600)
        let plausible = values.filter { $0 < ceiling && $0 > Self.fallbackBaseline.addingTimeInterval(-86_400 * 365 * 5) }
        return plausible.min() ?? AntiBanRoutine.fallbackBaseline
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - content scrub

    /// Rewrite text files that still spell our artifact names, in place and at
    /// the same length, then restore their timestamps.
    ///
    /// Only files that are (a) text-like by extension, (b) smaller than 512 KB
    /// and (c) not written in the last 45 seconds are touched, so a live log
    /// the target is appending to is never raced. Our own staged payload and
    /// config are excluded by name.
    private func scrubReferences(
        in data: URL,
        baseline: Date
    ) -> (files: [String], directories: [String]) {
        let fm = FileManager.default
        let staged = Set(
            (BridgeNames.patchNames + BridgeNames.configNames).map { $0.lowercased() }
        )
        let now = Date()
        var files: [String] = []
        var directories: Set<String> = []

        walk(data, maxDepth: 5) { url, isDirectory in
            guard !isDirectory else { return }
            let name = url.lastPathComponent
            guard !staged.contains(name.lowercased()) else { return }
            guard AntiBanRoutine.scrubExtensions.contains(url.pathExtension.lowercased()) else { return }
            guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
                  size.intValue > 0, size.intValue < 512 * 1024 else { return }
            guard let mod = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(mod) > 45 else { return }
            guard let blob = try? Data(contentsOf: url), let text = String(data: blob, encoding: .utf8)
            else { return }
            guard let scrubbed = AntiBanRoutine.scrub(text), scrubbed != text else { return }

            var info = stat()
            guard stat(url.path, &info) == 0 else { return }
            guard let out = scrubbed.data(using: .utf8) else { return }
            guard QuietWrite.writeInPlace(out, to: url.path) else { return }
            restoreTimes(url.path, info)
            files.append(name)
            directories.insert(url.deletingLastPathComponent().path)
            log.log(.antiBan, "scrubbed artifact references from \(name)")
        }
        return (files, Array(directories))
    }

    /// Replace every artifact spelling with its same-length neutral twin.
    /// Longest needles first so `Assembly-CSharp-patch` is not half-replaced by
    /// the generic `ffxc` rule.
    static func scrub(_ text: String) -> String? {
        var out = text
        var changed = false
        for pair in scrubMap.sorted(by: { $0.from.count > $1.from.count }) {
            if out.contains(pair.from) {
                out = out.replacingOccurrences(of: pair.from, with: pair.to)
                changed = true
            }
        }
        return changed ? out : nil
    }

    // MARK: - kernel forge

    /// Forge `ctime` for the payload files and their directories through the
    /// kernel R/W chain. No-op on a build where the chain is not up, which is
    /// the normal case when container access came from the MCM token.
    private func forgeKernelTimestamps(game: Game, data: URL, baseline: Date) -> [String] {
        guard KernelMask.isAvailable() else { return [] }
        var paths = bridge.patchURLs(in: data, game: game).map(\.path)
        paths += bridge.configURLs(in: data, game: game).map(\.path)
        paths += bridge.payloadDirectories(in: data).map(\.path)
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        let forged = KernelMask.forgeTimestamps(paths: existing, baseline: baseline)
        if !forged.isEmpty {
            log.log(.antiBan, "kernel ctime forged to baseline for \(forged.count) node(s)")
        }
        return forged
    }

    /// Replace this process's kernel-side name once per session.
    private var processMasked = false

    private func maskProcessIdentity() {
        guard !processMasked else { return }
        guard KernelMask.isAvailable() else { return }
        processMasked = KernelMask.renameProcess(to: AntiBanRoutine.processAlias)
        if processMasked {
            log.log(.antiBan, "process name masked -> \(AntiBanRoutine.processAlias)")
        }
    }

    // MARK: - signature scan

    /// Find files in the container whose contents mention our Mach-O prefix,
    /// restoring each file's `atime`/`mtime` afterwards so the scan itself
    /// leaves no access trail.
    ///
    /// Our own staged payload carries the signature by design and is skipped;
    /// flagging it was only ever noise.
    private func scanForSignature(in data: URL, game: Game) -> [String]? {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: data,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let staged = Set(
            (bridge.patchURLs(in: data, game: game) + bridge.configURLs(in: data, game: game))
                .map { $0.standardizedFileURL.path }
        )
        let needle = Data(KernelRW.signature.utf8)
        var hits: [String] = []
        while let url = walker.nextObject() as? URL {
            guard !staged.contains(url.standardizedFileURL.path) else { continue }
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size < 4 * 1024 * 1024
            else { continue }

            var before = stat()
            guard stat(url.path, &before) == 0,
                  let blob = try? Data(contentsOf: url) else { continue }
            restoreTimes(url.path, before)

            if blob.range(of: needle) != nil {
                hits.append(url.lastPathComponent)
            }
        }
        return hits.isEmpty ? nil : hits
    }

    /// Put a file's access and modification times back exactly as they were
    /// observed before we read it.
    private func restoreTimes(_ path: String, _ before: stat) {
        let times = [
            timeval(
                tv_sec: Int(before.st_atimespec.tv_sec),
                tv_usec: Int32(clamping: before.st_atimespec.tv_nsec / 1000)
            ),
            timeval(
                tv_sec: Int(before.st_mtimespec.tv_sec),
                tv_usec: Int32(clamping: before.st_mtimespec.tv_nsec / 1000)
            ),
        ]
        _ = path.withCString { utimes($0, times) }
    }

    // MARK: - traversal

    /// Bounded depth-first walk. `visit` receives every entry with its
    /// directory flag; directories are descended into afterwards unless the
    /// budget is exhausted. The budget is what keeps a container with thousands
    /// of cache files from turning a guard tick into a stall.
    private func walk(
        _ root: URL,
        maxDepth: Int,
        budget: Int = 6_000,
        _ visit: (URL, Bool) -> Void
    ) {
        var remaining = budget
        walkRecursive(root, depth: 0, maxDepth: maxDepth, remaining: &remaining, visit)
    }

    private func walkRecursive(
        _ dir: URL,
        depth: Int,
        maxDepth: Int,
        remaining: inout Int,
        _ visit: (URL, Bool) -> Void
    ) {
        guard depth <= maxDepth, remaining > 0 else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return }

        for entry in entries {
            guard remaining > 0 else { return }
            remaining -= 1
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDirectory = values?.isDirectory ?? false
            let isLink = values?.isSymbolicLink ?? false
            visit(entry, isDirectory)
            if isDirectory && !isLink {
                walkRecursive(entry, depth: depth + 1, maxDepth: maxDepth, remaining: &remaining, visit)
            }
        }
    }
}

/// Filenames the panel stages, for the scrub's exclusion set. Kept in one place
/// so a rename of the staged payload only has to move here.
private enum BridgeNames {
    static let patchNames: [String] = [
        ContainerBridge.patchName,
        ContainerBridge.patchInjectionName,
    ]
    static let configNames: [String] = [
        Game.freeFire.configFileName,
        Game.freeFireMax.configFileName,
    ]
}

/// In-place file writing that never creates a temporary and never renames.
///
/// `Data.write(options: .atomic)` writes a sibling temp file and renames it,
/// which is two observable directory events per write (create + rename). The
/// target can watch its own container, so the config restage path writes the
/// existing inode in place instead: one modification event, same inode, same
/// timestamps once the sweep re-stamps them.
enum QuietWrite {
    @discardableResult
    static func writeInPlace(_ data: Data, to path: String) -> Bool {
        let fd = open(path, O_WRONLY | O_CREAT, 0o644)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard ftruncate(fd, 0) == 0 else { return false }

        let ok = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var written = 0
            while written < data.count {
                let n = write(fd, base + written, data.count - written)
                if n <= 0 { return false }
                written += n
            }
            return true
        }
        return ok && fsync(fd) == 0
    }
}
