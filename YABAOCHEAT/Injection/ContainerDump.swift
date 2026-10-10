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
        var pending: [(label: String, data: Data)] = []
        var tally = WalkTally()

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

            // A blob larger than the neutral manifest is the real patch — the
            // artifact this build does not ship. Queue it for export; payloads
            // are emitted last so the ring buffer cannot evict them.
            if data.count != PatchPayload.expectedLength {
                pending.append((label: "\(parent)/\(url.lastPathComponent)", data: data))
            }
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

        // 6) This app's own backup, if an earlier Inject adopted the real patch.
        let ownBackup = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ffxc_real_patch.bytes")
        if let ownBackup, let data = try? Data(contentsOf: ownBackup),
           data.count != PatchPayload.expectedLength {
            log.log(.runtime, "DUMP: own backup ffxc_real_patch.bytes \(data.count)B sha256=\(PatchPayload.digest(of: data))")
            pending.append((label: "backup/ffxc_real_patch.bytes", data: data))
        }

        // 7) Quiet whole-container walk. The known copies live in root and
        //    Documents, but a vendor run may stage the real patch in Library/,
        //    tmp/, SystemData/, or a Documents subfolder. Only candidates are
        //    logged — the game's cache trees (CDNICON holds tens of thousands
        //    of icons) are skipped so the 500-line log is not flooded.
        walk(path, depth: 0, pending: &pending, tally: &tally)
        log.log(.runtime, "DUMP: walk complete dirs=\(tally.dirs) files=\(tally.files) candidates=\(tally.candidates)")

        // 8) Emit the payloads LAST. The in-app log is a 500-line ring buffer,
        //    so the PATCHB64 header and chunks must be the newest entries or
        //    they scroll off before the user can read them. Identical blobs
        //    found in several places are emitted once.
        var emitted = Set<String>()
        for (label, data) in pending {
            let digest = PatchPayload.digest(of: data)
            guard emitted.insert(digest).inserted else { continue }
            exportPatch(data: data, label: label)
        }
    }

    /// Lift the real patch off the device: a copy into this app's own
    /// Documents for a Filza/Files pull, plus base64 in the log itself so it
    /// survives even without a file manager. Chunks carry an index so the
    /// original order is recoverable; reassembled length and digest must match
    /// the header line.
    private func exportPatch(data: Data, label: String) {
        // Defensive: the payload is ~76 KB. Anything far larger is a game
        // asset, and one 4 MB blob would fill the entire ring buffer.
        guard data.count <= 300_000 else {
            log.log(.runtime, "DUMP: skip export \(label) — \(data.count)B too large for a patch")
            return
        }
        let digest = PatchPayload.digest(of: data)
        let b64 = Array(data.base64EncodedString())
        let chunk = 1000
        let total = max(1, (b64.count + chunk - 1) / chunk)
        log.log(.runtime, "DUMP: PATCHB64 \(label) bytes=\(data.count) sha256=\(digest) chunks=\(total)")

        var offset = 0
        var index = 0
        while offset < b64.count {
            let end = min(offset + chunk, b64.count)
            index += 1
            log.log(.runtime, "DUMP: PATCHB64 \(index)/\(total) \(String(b64[offset..<end]))")
            offset = end
        }

        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let name = "captured-" + label.replacingOccurrences(of: "/", with: "_")
            let out = docs.appendingPathComponent(name)
            if (try? data.write(to: out, options: .atomic)) != nil {
                log.log(.runtime, "DUMP: exported \(data.count)B to app Documents/\(name)")
            }
        }
    }

    /// Directory trees that hold no payload: the game's icon/asset/shard caches.
    /// Skipped so the walk is fast and the log stays short.
    private static let noisyDirectories: Set<String> = [
        "CDNICON", "Caches", "Cache", "ImageCache", "fsCachedData",
        "WebKit", "com.apple.WebKit.GPU", "com.apple.metal", "downscaled",
    ]

    private struct WalkTally {
        var dirs = 0
        var files = 0
        var candidates = 0
    }

    /// Recursively scan a directory tree and queue candidate patch blobs. The
    /// real patch is 76,348 B and its digest is pinned; a copy hidden under
    /// Library/, tmp/ or a Documents subfolder is queued if it is patch-named,
    /// digest-matches the pinned payload, or is exactly the known size. Only
    /// candidates are logged — never one line per file.
    private func walk(
        _ dir: URL,
        depth: Int,
        pending: inout [(label: String, data: Data)],
        tally: inout WalkTally,
        maxDepth: Int = 6
    ) {
        let fm = FileManager.default
        guard depth <= maxDepth,
              let entries = try? fm.contentsOfDirectory(atPath: dir.path)
        else { return }
        tally.dirs += 1

        for name in entries.sorted() {
            if name == "." || name == ".." { continue }
            let url = dir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if ContainerDump.noisyDirectories.contains(name) { continue }
                walk(url, depth: depth + 1, pending: &pending, tally: &tally, maxDepth: maxDepth)
                continue
            }
            tally.files += 1

            let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
            let inBand = (40_000...160_000).contains(size)
            let named = name.lowercased().contains("patch") || name.lowercased().contains("ifix")
            guard inBand || named,
                  let data = try? Data(contentsOf: url),
                  data.count > PatchPayload.expectedLength
            else { continue }

            let digest = PatchPayload.digest(of: data)
            let parent = url.deletingLastPathComponent().lastPathComponent
            tally.candidates += 1
            log.log(.runtime, "DUMP: candidate [\(parent)] \(name) \(data.count)B sha256=\(digest)")

            // Only the real payload is lifted. A loose name match is not
            // enough: the game ships asset bundles whose names contain
            // "patch" (mappatchpony…), and exporting one floods the log and
            // evicts the payload. Digest or exact size, nothing else.
            let isVendor = digest.caseInsensitiveCompare(PatchPayload.vendorPatchSHA256) == .orderedSame
            if isVendor || data.count == 76_348 {
                pending.append((label: "\(parent)/\(name)", data: data))
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