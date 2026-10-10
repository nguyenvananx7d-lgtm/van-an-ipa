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
    ///
    /// Launch mirrors the vendor build (`Sophia`): open the title's registered
    /// URL scheme directly and never gate on `canOpenURL`. On modern iOS a
    /// `canOpenURL` refusal only proves the scheme is missing from the caller's
    /// queries whitelist — exactly what an unsigned TrollStore-installed app
    /// does not reliably carry — so the old gate skipped the one call that
    /// actually opens the game and fell through to a workspace call whose reply
    /// was logged as success even when no process came up. `UIApplication.open`
    /// is itself un-gated, and its completion's `ok` is the genuine open
    /// signal. Only when the scheme open is refused do we fall back to the
    /// private app-workspace launch, and the 10 s post-launch probe is what
    /// verifies either attempt really landed a running game.
    @MainActor
    public func launch(game: Game, terminateFirst: Bool = true) throws {
        if terminateFirst, let running = runningPID(for: game) {
            log.log(.launch, "terminating \(game.bundleIdentifier) (pid \(running))")
            kill(running, SIGKILL)
            // Give the system a moment to tear the process down, otherwise the
            // relaunch lands on the outgoing instance and the patch is ignored.
            Thread.sleep(forTimeInterval: 0.6)
        }

        log.log(.launch, "requesting open of \(game.bundleIdentifier) via registered scheme")
        let url = URL(string: "\(game.bundleIdentifier)://")!
        UIApplication.shared.open(url, options: [:]) { [self] ok in
            Task { @MainActor in
                if ok {
                    log.log(.launch, "launched \(game.bundleIdentifier) via scheme")
                } else {
                    log.log(.launch, "scheme open refused for \(game.bundleIdentifier); trying app workspace")
                    if openViaWorkspace(game) {
                        // A non-nil `perform` reply means the workspace accepted
                        // the request, not that the process is up — the probe
                        // owns that verdict.
                        log.log(.launch, "workspace accepted the launch request for \(game.bundleIdentifier)")
                    } else {
                        log.log(.launch, "\(game.bundleIdentifier) not installed or not launchable")
                    }
                }
                logFireProcs("after launch attempt")
            }
        }
    }

    /// Whether the target is currently running.
    public func isRunning(game: Game) -> Bool {
        runningPID(for: game) != nil
    }

    /// Diagnostics: every running process whose short name looks Free-Fire
    /// adjacent, as "pid:name". Logged by the probe whenever the target is not
    /// matched, so a build whose binary name dodges our fragment list still
    /// leaves its real process name in the log instead of a bare "HAS EXITED".
    public func fireProcs() -> [String] {
        pidsWithComm()
            .filter { $0.comm.lowercased().contains("fire") }
            .map { "\($0.pid):\($0.comm)" }
    }

    private func logFireProcs(_ context: String) {
        let procs = fireProcs()
        guard !procs.isEmpty else { return }
        log.log(.launch, "fire-named procs \(context): \(procs.joined(separator: ", "))")
    }

    /// Launch by bundle id through `LSApplicationWorkspace`. Private API, so it
    /// is reached via the Objective-C runtime and only as a last resort; it
    /// needs the sender to be able to see the target's install (workspace
    /// entitlement or an unsandboxed process — which this build already relies
    /// on for container access).
    @MainActor
    private func openViaWorkspace(_ game: Game) -> Bool {
        guard let cls = NSClassFromString("LSApplicationWorkspace"),
              let workspace = cls.value(forKey: "defaultWorkspace") as? NSObject else {
            return false
        }
        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: selector) else { return false }
        let opened = workspace.perform(selector, with: game.bundleIdentifier)
        return opened != nil
    }

    // MARK: - process lookup

    private func runningPID(for game: Game) -> pid_t? {
        runningProcesses().first?.pid
    }

    /// Short names the two targets run under. `p_comm` is truncated to 16
    /// bytes and carries no bundle id, so match a few fragments
    /// case-insensitively — a rebuilt binary may be named `Free Fire`,
    /// `freefire`, `Free FireMax`, etc.
    private static let wantedCommFragments = ["freefire", "free fire", "com.dts.freefire"]

    /// Process check exposed to the post-launch probe.
    ///
    /// The quiet truth behind the earlier "HAS EXITED" verdicts: exec args
    /// (KERN_PROCARGS2) are gated — a sandboxed caller gets EPERM for every
    /// process but its own, so a bundle-id lookup would report the target dead
    /// even while it sat open on screen. The kernel proc table entry (pid +
    /// short name `p_comm`) is what a jailed app can actually read for other
    /// processes, so this is the only check a verdict may rely on.
    public func runningDescription(for game: Game) -> String? {
        runningProcesses().first.map { "pid \($0.pid) (\($0.comm))" }
    }

    struct Proc {
        let pid: pid_t
        let comm: String
    }

    private func runningProcesses() -> [Proc] {
        pidsWithComm().filter { proc in
            let lower = proc.comm.lowercased()
            return Self.wantedCommFragments.contains { lower.contains($0) }
        }
    }

    /// Enumerate the kernel process table with pid + process short name. The
    /// `kinfo_proc` entries themselves are readable from a sandboxed process
    /// (pid, state, and `p_comm` come along for free); only the exec argument
    /// strings and executable paths are gated.
    private func pidsWithComm() -> [Proc] {
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
        var procs: [Proc] = []
        var offset = 0
        while offset + entry <= taken {
            let info: kinfo_proc = buffer.withUnsafeBytes { raw in
                raw.load(fromByteOffset: offset, as: kinfo_proc.self)
            }
            let pid = info.kp_proc.p_pid
            if pid > 1 {
                procs.append(Proc(pid: pid, comm: Self.commName(info)))
            }
            offset += entry
        }
        return procs
    }

    /// Read `p_comm` from a `kinfo_proc` entry safely: the field is a fixed
    /// 16-byte buffer that may not be NUL-terminated, so bound the read.
    private static func commName(_ info: kinfo_proc) -> String {
        withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            guard let base = raw.baseAddress else { return "" }
            let ptr = base.assumingMemoryBound(to: CChar.self)
            let length = strnlen(ptr, raw.count)
            let bytes = UnsafeBufferPointer(start: ptr, count: length)
            return String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
    }
}