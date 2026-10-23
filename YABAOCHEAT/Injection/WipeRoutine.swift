import Foundation

/// Removes every trace of the injector from a target container.
///
/// This is the routine the user reaches for when something went wrong and they
/// need the game back to a clean state. It is deliberately conservative: it
/// only deletes files it can attribute to us, and it reports what it removed
/// rather than assuming success.
public struct WipeRoutine: Sendable {
    private let log: AppLog
    private let bridge: ContainerBridge
    private let krw: KernelRW

    public init(log: AppLog, bridge: ContainerBridge, krw: KernelRW) {
        self.log = log
        self.bridge = bridge
        self.krw = krw
    }

    public struct Report: Sendable {
        public let removed: [String]
        public let retained: [String]
        public let filesWiped: Bool

        public var isClean: Bool { retained.isEmpty }
    }

    /// Files we are willing to delete. Anything not on this list is left alone
    /// even if it looks like ours.
    static let ownedNames: Set<String> = [
        ContainerBridge.patchName,
        ContainerBridge.patchInjectionName,
        "localConfig.json",
        ".ffxc_access_probe",
    ]

    /// Residue the panel or the injected runtime may have dropped in the
    /// container. Unlike `ownedNames` these are optional — they are not always
    /// present — so they never count toward "wiped clean", but every sweep
    /// deletes them because a newer client flags any file whose name is not one
    /// it expects. Covers the probe (`.ffxc*`), the runtime's own debug log,
    /// and the `testCodePatch*` engagement marker.
    static let residueNames: Set<String> = [
        ContainerBridge.accessProbe,
        "ffxc_debug.log",
    ]
    static let residuePrefixes: [String] = [".ffxc"]
    static let residueSubstrings: [String] = ["testCodePatch"]
    /// True when `name` is a panel/runtime leftover safe to delete. The staged
    /// patch and config never match this — they are the payload, not residue.
    /// `testCodePatch` is matched as a substring because the runtime names its
    /// engagement marker `<something>testCodePatch<something>` (the probe's
    /// marker scan uses the same `contains` test).
    static func isResidue(_ name: String) -> Bool {
        if residueNames.contains(name) { return true }
        if residuePrefixes.contains(where: { name.hasPrefix($0) }) { return true }
        return residueSubstrings.contains { name.contains($0) }
    }
    public enum WipeError: Error, Sendable {
        case containerNotFound
        case fileUnavailable
    }

    public func wipe(game: Game) throws -> Report {
        let data: URL
        switch bridge.resolve(game: game) {
        case .resolved(let d): data = d
        case .notFound:          throw WipeError.containerNotFound
        case .accessDenied:      throw WipeError.fileUnavailable
        case .bridgeUnavailable: throw WipeError.fileUnavailable
        }

        // Drop cached pages first. Anything flushed after a delete would write
        // the removed bytes straight back.
        krw.flushAll()
        log.log(.wipe, "flushed page cache before wipe")

        var removed: Set<String> = []
        var retained: [String] = []

        // The patch is staged in more than one directory, so every payload
        // directory is swept, not just the resolved one.
        for dir in bridge.payloadDirectories(in: data) {
            for name in WipeRoutine.ownedNames.sorted() {
                let url = dir.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    try FileManager.default.removeItem(at: url)
                    removed.insert(name)
                    log.log(.wipe, "removed \(name) from \(dir.lastPathComponent)")
                } catch {
                    retained.append("\(dir.lastPathComponent)/\(name)")
                    log.log(.wipe, "could not remove \(name): \(error.localizedDescription)")
                }
            }
        }

        // Any file still carrying our signature is ours even if it is not on the
        // list — flag it rather than deleting it, since we cannot prove we put
        // it there.
        if let strays = scanForSignature(in: data) {
            retained.append(contentsOf: strays)
            log.log(.wipe, "\(strays.count) unrecognised file(s) carry the injector signature")
        }

        // Panel/runtime residue (probe, debug log, engagement marker). Removed
        // on every wipe but never counted toward `filesWiped`: it is optional,
        // so its absence is the normal case.
        var residueRemoved = 0
        for dir in bridge.payloadDirectories(in: data) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where WipeRoutine.isResidue(name) {
                let url = dir.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    try FileManager.default.removeItem(at: url)
                    residueRemoved += 1
                    log.log(.wipe, "removed residue \(name) from \(dir.lastPathComponent)")
                } catch {
                    retained.append("\(dir.lastPathComponent)/\(name)")
                    log.log(.wipe, "could not remove residue \(name): \(error.localizedDescription)")
                }
            }
        }
        let report = Report(removed: Array(removed), retained: retained, filesWiped: removed.count == WipeRoutine.ownedNames.count)
        bridge.releaseGrants()
        log.log(.wipe, "wipe finished: \(removed.count) removed, \(residueRemoved) residue, \(retained.count) retained; sandbox grants released")
        return report
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
