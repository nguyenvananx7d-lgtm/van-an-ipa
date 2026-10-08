import Foundation
import UIKit

/// Starts or restarts the target game after a successful install.
public struct GameLauncher: Sendable {
    private let log: AppLog

    public init(log: AppLog) {
        self.log = log
    }

    public enum LaunchError: Error, Sendable {
        case gameNotInstalled
        case launchFailed
    }

    /// Open the target's bundle id, optionally forcing a cold start.
    ///
    /// `terminateFirst` matters: a warm start keeps the old runtime mapped, so a
    /// fresh patch would be loaded by nobody.
    @MainActor
    public func launch(game: Game, terminateFirst: Bool = true) throws {
        guard let url = URL(string: "\(game.bundleIdentifier)://") else {
            throw LaunchError.gameNotInstalled
        }
        guard UIApplication.shared.canOpenURL(url) else {
            log.log(.launch, "\(game.bundleIdentifier) not installed")
            throw LaunchError.gameNotInstalled
        }

        if terminateFirst, let running = runningPID(for: game) {
            log.log(.launch, "terminating \(game.bundleIdentifier) (pid \(running))")
            kill(running, SIGKILL)
            // Give the system a moment to tear the process down, otherwise the
            // relaunch lands on the outgoing instance and the patch is ignored.
            Thread.sleep(forTimeInterval: 0.6)
        }

        UIApplication.shared.open(url, options: [:]) { [log] ok in
            if ok {
                log.log(.launch, "launched \(game.bundleIdentifier)")
            } else {
                log.log(.launch, "launch refused for \(game.bundleIdentifier)")
            }
        }
    }

    /// Whether the target is currently running.
    public func isRunning(game: Game) -> Bool {
        runningPID(for: game) != nil
    }

    // MARK: - process lookup

    private func runningPID(for game: Game) -> pid_t? {
        let procs = runningProcesses()
        return procs.first { $0.bundleIdentifier == game.bundleIdentifier }?.pid
    }

    struct Proc {
        let pid: pid_t
        let bundleIdentifier: String
    }

    /// Enumerate running apps by asking `runningboard` for the set of foreground
    /// and background processes, then reading each bundle id out of its container.
    private func runningProcesses() -> [Proc] {
        var found: [Proc] = []
        let wanted = Set(Game.allCases.map(\.bundleIdentifier))

        // sysctl KERN_PROC_ALL over the kernel process table, filtered to apps
        // that have a container we can name. Kept deliberately narrow: we only
        // care about two bundle ids, so there is no reason to walk everything.
        for pid in Self.pids() {
            guard let bundle = bundleIdentifier(for: pid), wanted.contains(bundle) else { continue }
            found.append(Proc(pid: pid, bundleIdentifier: bundle))
        }
        return found
    }

    private static func pids() -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        let taken = buffer.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress,
                  sysctl(&mib, 4, base, &size, nil, 0) == 0 else { return 0 }
            return size
        }
        guard taken > 0 else { return [] }

        let entry = MemoryLayout<kinfo_proc>.stride
        var pids: [pid_t] = []
        var offset = 0
        while offset + entry <= taken {
            let info: kinfo_proc = buffer.withUnsafeBytes { raw in
                raw.load(fromByteOffset: offset, as: kinfo_proc.self)
            }
            let pid = info.kp_proc.p_pid
            if pid > 1 { pids.append(pid) }
            offset += entry
        }
        return pids
    }

    private func bundleIdentifier(for pid: pid_t) -> String? {
        // The executable path maps back to the bundle through the app's own
        // container; a proc that is not a bundled app has no path here.
        guard let path = Self.executablePath(for: pid) else { return nil }
        // …/Containers/Data/Application/<uuid>/<Game>.app/<Game>
        guard let bundle = path.split(separator: "/").first(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        return Bundle(url: URL(fileURLWithPath: String(bundle)))?.bundleIdentifier
    }

    private static func executablePath(for pid: pid_t) -> String? {
        // KERN_PROCARGS2 returns int32 argc, then the executable path
        // NUL-terminated, then the argv strings. A jailed caller gets EPERM
        // for anything but its own processes; nil then means "not resolvable".
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        let taken = buffer.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress,
                  sysctl(&mib, 3, base, &size, nil, 0) == 0 else { return 0 }
            return size
        }
        guard taken > 4 else { return nil }

        let path = buffer[4..<taken].prefix(while: { $0 != 0 })
        guard !path.isEmpty else { return nil }
        return String(decoding: path, as: UTF8.self)
    }
}

