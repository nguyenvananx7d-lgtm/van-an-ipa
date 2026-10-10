import Foundation

/// Reads the resolved game container and prints its current payload state to
/// the log. Observation-only: nothing is written, removed, or rewritten — the
/// only side effect is the standard writability probe `resolve` already
/// performs (which writes then deletes a canary).
///
/// Its job is ground truth for parity work: run the vendor build (`Sophia`)
/// first so its files sit in the game container, then come back to this app and
/// tap "Dump container" — the log then shows exactly where the vendor staged
/// files, the ver batim `localConfig.json`, the patch blob digest and the
/// strings it carries, and any runtime markers the game left behind.
public struct ContainerDump: Sendable {
    private let log: AppLog
    private let bridge: ContainerBridge

    public init(log: AppLog, bridge: ContainerBridge) {
        self.log = log
        self.bridge = bridge
    }

    public func dump(game: Game) {
        let path: URL
        switch bridge.resolve(game: game) {
        case .resolved(let data):
            path = data
        case .notFound:
            log.log(.runtime, "DUMP: container for \(game.bundleIdentifier) not installed")
            return
        case .accessDenied:
            log.log(.runtime, "DUMP: container sealed — \(bridge.lastAccessError ?? "access denied")")
            return
        case .bridgeUnavailable:
            log.log(.runtime, "DUMP: container bridge unavailable")
            return
        }

        log.log(.runtime, "DUMP: container \(game.bundleIdentifier) = \(path.path)")

        let fm = FileManager.default

        // 1) What is actually in the container — file names, sizes.
        for dir in bridge.payloadDirectories(in: path) {
            log.log(.runtime, "DUMP: [\(dir.lastPathComponent)] \(listing(in: dir))")
        }

        // 2) Every copy of the runtime config, verbatim. The copies may differ
        //    per directory (root vs Documents), so each is printed separately.
        for url in bridge.configURLs(in: path, game: game) where fm.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent().lastPathComponent
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                log.log(.runtime, "DUMP: \(url.lastPathComponent) @ [\(parent)]: \(text)")
            } else {
                log.log(.runtime, "DUMP: \(url.lastPathComponent) @ [\(parent)]: present but unreadable")
            }
        }

        // 3) The patch blob at every staged name: size, digest, carried strings.
        for url in bridge.patchURLs(in: path, game: game) where fm.fileExists(atPath: url.path) {
            let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
            let parent = url.deletingLastPathComponent().lastPathComponent
            guard let data = try? Data(contentsOf: url) else {
                log.log(.runtime, "DUMP: \(url.lastPathComponent) @ [\(parent)]: \(size)B unreadable")
                continue
            }
            let digest = PatchPayload.digest(of: data)
            let printable = ContainerDump.printableStrings(in: data).joined(separator: " | ")
            log.log(.runtime, "DUMP: \(url.lastPathComponent) @ [\(parent)]: \(size)B sha256=\(digest) \(printable)")
        }

        // 4) Marker / probe-document files the runtime may create or expect.
        for dir in bridge.payloadDirectories(in: path) {
            let markers = (try? fm.contentsOfDirectory(atPath: dir.path))?
                .filter { $0.contains("testCodePatch") || $0.contains("ffxc") }
                ?? []
            if !markers.isEmpty {
                for name in markers {
                    let url = dir.appendingPathComponent(name)
                    let content = (try? String(contentsOf: url, encoding: .utf8)) ?? "(unreadable)"
                    log.log(.runtime, "DUMP: marker \(name) @ [\(dir.lastPathComponent)]: \(content)")
                }
            }
        }

        // 5) The injected runtime's own debug log, if a run produced one.
        for dir in bridge.payloadDirectories(in: path) {
            let debugLog = dir.appendingPathComponent("ffxc_debug.log")
            if let text = try? String(contentsOf: debugLog, encoding: .utf8) {
                let tail = String(text.suffix(500)).replacingOccurrences(of: "\n", with: " ⏎ ")
                log.log(.runtime, "DUMP: ffxc_debug.log tail @ [\(dir.lastPathComponent)]: \(tail)")
            }
        }
    }

    /// Compact one-line listing of a directory: "name(sizeB), ...".
    private func listing(in dir: URL) -> String {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else {
            return "(unreadable: \(bridge.lastAccessError ?? "unknown"))"
        }
        let shown = entries.sorted().prefix(40).map { name -> String in
            let url = dir.appendingPathComponent(name)
            let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
            return "\(name)(\(size)B)"
        }
        let tail = entries.count > 40 ? ", …(\(entries.count - 40) more)" : ""
        return shown.joined(separator: ", ") + tail
    }

    /// Pull the printable runs out of a binary blob, for identifying a manifest.
    private static func printableStrings(in data: Data) -> [String] {
        var out: [String] = []
        var run = ""
        for byte in data {
            if byte >= 32 && byte < 127 {
                run.append(Character(UnicodeScalar(byte)))
            } else if run.count >= 4 {
                out.append(run)
                run = ""
            } else {
                run = ""
            }
        }
        if run.count >= 4 { out.append(run) }
        return out
    }
}