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
        "Assembly-CSharp-patch.bytes",
        "localConfig.json",
        ".ffxc_access_probe",
    ]

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

        var removed: [String] = []
        var retained: [String] = []

        for name in WipeRoutine.ownedNames.sorted() {
            let url = data.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removed.append(name)
                log.log(.wipe, "removed \(name)")
            } catch {
                retained.append(name)
                log.log(.wipe, "could not remove \(name): \(error.localizedDescription)")
            }
        }

        // Any file still carrying our signature is ours even if it is not on the
        // list — flag it rather than deleting it, since we cannot prove we put
        // it there.
        if let strays = scanForSignature(in: data) {
            retained.append(contentsOf: strays)
            log.log(.wipe, "\(strays.count) unrecognised file(s) carry the injector signature")
        }

        let report = Report(removed: removed, retained: retained, filesWiped: removed.count == WipeRoutine.ownedNames.count)
        log.log(.wipe, "wipe finished: \(removed.count) removed, \(retained.count) retained")
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
                  size != nil, (size ?? 0) < 4 * 1024 * 1024,
                  let blob = try? Data(contentsOf: url)
            else { continue }
            if blob.range(of: needle) != nil {
                hits.append(url.lastPathComponent)
            }
        }
        return hits.isEmpty ? nil : hits
    }
}
