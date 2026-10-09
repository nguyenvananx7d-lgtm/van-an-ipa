import Foundation

/// Re-reads the target's container shortly after launch and reports whether the
/// runtime ever engaged with the staged files. One round of evidence instead of a
/// black box:
///
/// - Is the target still alive a few seconds after launch, or did it die on boot?
/// - Are the staged patch/config still present, intact, rewritten, or gone?
/// - Did the runtime leave a marker (`ffxc_debug.log`, `testCodePatch*`) behind?
///
/// This is deliberate observation-only: it never rewrites or removes anything,
/// so it is safe to run on every install.
public struct PostLaunchProbe: Sendable {
    private let log: AppLog
    private let bridge: ContainerBridge
    private let launcher: GameLauncher

    public init(log: AppLog, bridge: ContainerBridge, launcher: GameLauncher) {
        self.log = log
        self.bridge = bridge
        self.launcher = launcher
    }

    /// How long the booting game gets to read, rewrite, or consume the staged
    /// files before the probe looks. Long enough for a cold start to pass its
    /// first read of `localConfig.json` / the patch, short enough that a probe
    /// run does not linger in the log long after injection.
    public static let settleSeconds: UInt64 = 10

    /// Marker filenames the injected runtime is expected to leave behind:
    /// `ffxc_debug.log` (recovered `RecoveredVocabulary.debugLogName`) and any
    /// file whose name carries `testCodePatch` (the probe document the runtime
    /// writes/reads to prove the patch took effect).
    private static let markerNames = ["ffxc_debug.log", "testCodePatch"]

    /// Fire the probe on a background thread after `settleSeconds`.
    public func schedule(game: Game, patchDigest: String) {
        Task.detached(priority: .utility) { [self] in
            try? await Task.sleep(nanoseconds: PostLaunchProbe.settleSeconds * 1_000_000_000)
            await run(game: game, patchDigest: patchDigest, label: "post-launch probe")
        }
    }

    /// Run the probe immediately — used when the injector comes back to the
    /// foreground after the target has been up for a while, so the state the
    /// user sees in the log reflects the container *now* (the scheduled probe
    /// is delayed while this app sits in the background behind the game).
    public func recheck(game: Game, patchDigest: String) async {
        await run(game: game, patchDigest: patchDigest, label: "probe recheck")
    }

    private func run(game: Game, patchDigest: String, label: String) async {
        if let detail = launcher.runningDescription(for: game) {
            log.log(.runtime, "\(label): target still running (\(detail))")
        } else {
            log.log(.runtime, "\(label): target HAS EXITED")
        }

        guard case .resolved(let data) = bridge.resolve(game: game) else {
            log.log(.runtime, "post-launch probe: container not resolvable (\(bridge.lastAccessError ?? "unknown"))")
            return
        }

        for dir in bridge.payloadDirectories(in: data) {
            probeDirectory(
                dir,
                patchDigest: patchDigest,
                configName: Game.freeFire.configFileName
            )
        }
    }

    /// One line of verdicts per payload directory so the log stays greppable.
    private func probeDirectory(_ dir: URL, patchDigest: String, configName: String) {
        let fm = FileManager.default
        var verdicts: [String] = []

        // Every patch copy: intact, rewritten (the target engaged), or gone
        // (read once and consumed, or purged).
        for name in [ContainerBridge.patchName, ContainerBridge.patchInjectionName] {
            let url = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                if let onDisk = try? Data(contentsOf: url),
                   PatchPayload.digest(of: onDisk) == patchDigest {
                    verdicts.append("\(name) intact")
                } else {
                    verdicts.append("\(name) REWRITTEN")
                }
            } else {
                verdicts.append("\(name) gone")
            }
        }

        let configURL = dir.appendingPathComponent(configName)
        if fm.fileExists(atPath: configURL.path) {
            var sizeText = ""
            if let attrs = try? fm.attributesOfItem(atPath: configURL.path),
               let number = attrs[.size] as? NSNumber {
                sizeText = " (\(number.intValue)B)"
            }
            let readable = (try? Data(contentsOf: configURL)) != nil
            let stateNote = readable ? "" : " (unreadable)"
            verdicts.append("\(configName) present\(sizeText)\(stateNote)")

            // Confirm the activation marker survived our config verbatim.
            if let data = try? Data(contentsOf: configURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (object["testCodePatch"] as? Bool) == true {
                verdicts.append("testCodePatch=true present")
            } else {
                verdicts.append("testCodePatch marker absent")
            }
        } else {
            verdicts.append("\(configName) gone")
        }

        // Marker files the runtime may have dropped after reading our payload.
        let markers = runtimeMarkers(in: dir)
        if !markers.isEmpty {
            verdicts.append("markers: \(markers.joined(separator: ", "))")
        }

        log.log(.runtime, "probe \(dir.lastPathComponent): \(verdicts.joined(separator: ", "))")
    }

    /// Top-level entries whose names match the runtime marker set. Only marker
    /// names are matched — the game's own Documents is full of freshly written
    /// files every second, so any "recently modified" heuristic would be noise.
    private func runtimeMarkers(in dir: URL) -> [String] {
        let fm = FileManager.default
        guard let entries = (try? fm.contentsOfDirectory(atPath: dir.path)) else { return [] }
        let markers = PostLaunchProbe.markerNames
        return entries
            .filter { name in markers.contains { name.contains($0) } }
            .prefix(8)
            .map { $0 }
    }
}