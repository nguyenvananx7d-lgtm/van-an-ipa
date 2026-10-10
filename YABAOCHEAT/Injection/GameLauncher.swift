import Foundation
import UIKit
import Darwin

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
    /// Launch mirrors the vendor build (`Sophia`): open the title by its URL
    /// scheme and never gate on `canOpenURL` — a `canOpenURL` refusal only
    /// proves the scheme is missing from the caller's queries whitelist, and an
    /// unsigned TrollStore-installed app does not reliably carry that. The
    /// scheme is the game's *registered* deep link (the bare bundle-id spelling
    /// exists only as a fallback; Garena's own links open via `dtsgff://`), so a
    /// chain of candidates is tried, each relying on `UIApplication.open`'s
    /// completion `ok` as the genuine "did it open" signal. Only after every
    /// scheme refuses do we fall back to the private launch APIs
    /// (`SBSLaunchApplicationWithIdentifier` via dlsym, then the app workspace),
    /// and the early process re-checks plus the 10 s post-launch probe are what
    /// verify an attempt really landed a running game.
    @MainActor
    public func launch(game: Game, terminateFirst: Bool = true) throws {
        if terminateFirst, let running = runningPID(for: game) {
            log.log(.launch, "terminating \(game.bundleIdentifier) (pid \(running))")
            kill(running, SIGKILL)
            // Give the system a moment to tear the process down, otherwise the
            // relaunch lands on the outgoing instance and the patch is ignored.
            Thread.sleep(forTimeInterval: 0.6)
        }

        let candidates = schemeCandidates(for: game)
        log.log(.launch, "requesting open of \(game.bundleIdentifier) via \(candidates.joined(separator: ", "))")
        tryOpen(schemes: candidates, game: game)
    }

    /// Registered deep-link spellings to try, most likely first. Free Fire's
    /// own invite/share surface opens through `dtsgff://`; the plain bundle-id
    /// scheme is not registered by the title on several builds, so it must not
    /// be the only try. Unregistered candidates return `ok == false` right away,
    /// which is exactly what moves the chain along.
    private func schemeCandidates(for game: Game) -> [String] {
        var list = ["\(game.bundleIdentifier)://"]
        for candidate in ["dtsgff://", "freefire://"] where !list.contains(candidate) {
            list.append(candidate)
        }
        return list
    }

    @MainActor
    private func tryOpen(schemes: [String], game: Game) {
        guard let first = schemes.first else {
            openViaSystemAPI(game)
            return
        }
        log.log(.launch, "trying scheme \(first)")
        guard let url = URL(string: first) else {
            tryOpen(schemes: Array(schemes.dropFirst()), game: game)
            return
        }
        UIApplication.shared.open(url, options: [:]) { [self] ok in
            Task { @MainActor in
                if ok {
                    log.log(.launch, "launched \(game.bundleIdentifier) via \(first)")
                    scheduleLaunchChecks()
                } else {
                    log.log(.launch, "scheme \(first) refused")
                    tryOpen(schemes: Array(schemes.dropFirst()), game: game)
                }
            }
        }
    }

    /// Every scheme refused — fall back to the private launch APIs.
    @MainActor
    private func openViaSystemAPI(_ game: Game) {
        if openViaSBS(game) {
            log.log(.launch, "SBS launch accepted for \(game.bundleIdentifier)")
            scheduleLaunchChecks()
            return
        }
        log.log(.launch, "SBS launch unavailable; trying app workspace")
        if openViaWorkspace(game) {
            // A non-nil `perform` reply means the workspace accepted the
            // request, not that the process is up — the checks own that.
            log.log(.launch, "workspace accepted the launch request for \(game.bundleIdentifier)")
        } else {
            log.log(.launch, "\(game.bundleIdentifier) not installed or not launchable")
            log.log(.launch, "staged files load on the game's next cold start — if nothing opened, tap the Free Fire icon manually")
        }
        scheduleLaunchChecks()
    }

    /// Early process-table re-checks after an attempt, so the log distinguishes
    /// "no process ever came up" from "game opened then died quickly" long
    /// before the 10 s post-launch probe.
    private func scheduleLaunchChecks() {
        let checks: [(delay: Double, label: String)] = [(1.5, "launch check 1.5s"), (4.0, "launch check 4s")]
        for check in checks {
            Task.detached { [self] in
                try? await Task.sleep(nanoseconds: UInt64(check.delay * 1_000_000_000))
                let procs = self.fireProcs()
                if procs.isEmpty {
                    self.log.log(.launch, "\(check.label): no fire-named process yet")
                } else {
                    self.log.log(.launch, "\(check.label): fire-named procs \(procs.joined(separator: ", "))")
                }
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

    /// Launch by bundle id through SpringBoardServices, resolved at runtime so
    /// the private framework is never linked. This is the launch route vendor
    /// injectors use on modern iOS; it needs the `springboard.launchapplications`
    /// entitlement honoured by the install (TrollStore). Returns when SpringBoard
    /// accepted the launch request (error code 0).
    private func openViaSBS(_ game: Game) -> Bool {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
            RTLD_LAZY
        ) else { return false }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "SBSLaunchApplicationWithIdentifier") else { return false }
        typealias SBSLaunch = @convention(c) (CFString, Bool) -> Int32
        let launch = unsafeBitCast(sym, to: SBSLaunch.self)
        let error = launch(game.bundleIdentifier as CFString, false)
        return error == 0
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