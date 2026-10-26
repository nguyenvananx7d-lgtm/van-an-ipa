import Foundation
import Darwin

/// Stage-1 of the native hook route — see `NATIVE_HOOK.md` at the repo root.
///
/// The exploit chain's label patch makes `task_for_pid` answer for the game.
/// From there this installer uses only Mach VM calls: it resolves the game's
/// image base through the dyld image list, plants a position-independent
/// trampoline on a fresh page inside the game, installs a 16-byte branch stub
/// over `COW.GamePlay.Player.IsReallyInStealth`, and verifies the trampoline
/// fired by reading its marker back. No file is written anywhere, IFix is
/// never touched, and no scene object is created.
///
/// The only write into a `__TEXT` page goes through a kernel-side
/// max-protection lift (`taskport_hook_install`), which self-calibrates its
/// `vm_map_entry` layout on our own task before touching the game's.
public struct NativeHookInstaller: Sendable {
    private let log: AppLog
    private let launcher: GameLauncher

    public init(log: AppLog, launcher: GameLauncher) {
        self.log = log
        self.launcher = launcher
    }

    /// RVA of the stage-1 hook target inside the game binary (1.132.1 dump).
    /// `Player.IsReallyInStealth` runs constantly, which is what makes it the
    /// marker carrier.
    static let hookTargetRVA: UInt64 = 0x573eff8
    /// Slide sanity: arm64 app images prefer 0x100000000 as their base.
    static let arm64PreferredBase: UInt64 = 0x100000000

    public struct Result: Sendable {
        public let armed: Bool
        public let fired: Bool
        public let targetVA: UInt64
        public let trampolineVA: UInt64
        public let slide: UInt64
        public let detail: String
    }

    public func installAndVerify() async -> Result {
        func fail(_ message: String) -> Result {
            log.log(.kernelRW, "native hook: \(message)")
            return Result(armed: false, fired: false, targetVA: 0,
                          trampolineVA: 0, slide: 0, detail: message)
        }

        guard KernelExploit.kernelRWReady else {
            return fail("kernel r/w not established — run the exploit stage first")
        }
        guard let pid = launcher.gamePID() else {
            return fail("game process not found by comm fragment")
        }

        // Kernel side: locate the proc, its task, and switch exc-guard off so
        // touching the task does not kill the game.
        let proc = proc_find(pid)
        guard proc != 0 else { return fail("proc_find(\(pid)) returned 0") }
        let taskPtr = proc_task(proc)
        guard taskPtr != 0 else { return fail("proc_task returned 0") }
        let excGuard = disable_excguard_kill(taskPtr)
        log.log(.kernelRW, "native hook: disable_excguard_kill -> \(excGuard)")

        var port = mach_port_t()
        guard taskport_acquire(pid, &port) == 0 else {
            return fail("task_for_pid refused (label patch did not stick)")
        }

        // User side: the main executable is dyld image #0 in every iOS
        // process; the `.app/` fragment keeps Firebase-style frameworks out of
        // the match.
        var base: UInt64 = 0
        let brc = taskport_image_base(port, "fire.app", &base)
        guard brc == 0, base != 0 else {
            return fail("image base resolve failed (\(brc))")
        }
        let slide = base - Self.arm64PreferredBase
        let targetVA = base + Self.hookTargetRVA
        log.log(.kernelRW, String(format: "native hook: base 0x%llx slide 0x%llx target 0x%llx",
                                  base, slide, targetVA))

        // Fresh R+W+X page in the game: trampoline code, then param block.
        let pageSize: vm_size_t = 0x4000
        var trampolineVA: UInt64 = 0
        guard taskport_alloc_exec(port, pageSize, &trampolineVA) == 0 else {
            return fail("exec page alloc failed")
        }

        var original = [UInt8](repeating: 0, count: 16)
        guard taskport_read(port, targetVA, &original, 16) == 0 else {
            return fail("prologue read failed")
        }
        let codeSize = taskport_trampoline_size()
        var page = [UInt8](repeating: 0, count: Int(pageSize))
        taskport_build_trampoline(&original, &page)
        var marker: UInt64 = TASKPORT_MARKER_ARMED
        var backVA = targetVA + 16
        var targetCopy = targetVA
        var flushFn: UInt64 = 0
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "sys_icache_invalidate") {
            flushFn = UInt64(bitPattern: Int64(Int(bitPattern: sym)))
        }
        var flushStart = trampolineVA
        var flushLen = UInt64(pageSize)
        let paramOff = codeSize
        page.withUnsafeMutableBytes { raw in
            let b = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            memcpy(b + paramOff + 0, &marker, 8)
            memcpy(b + paramOff + 8, &backVA, 8)
            memcpy(b + paramOff + 16, &targetCopy, 8)
            memcpy(b + paramOff + 24, &flushFn, 8)
            memcpy(b + paramOff + 32, &flushStart, 8)
            memcpy(b + paramOff + 40, &flushLen, 8)
        }
        guard taskport_write(port, trampolineVA, &page, vm_size_t(page.count)) == 0 else {
            return fail("trampoline write failed")
        }
        log.log(.kernelRW, String(format: "native hook: trampoline 0x%llx, flush_fn 0x%llx",
                                  trampolineVA, flushFn))

        var originalOut = [UInt8](repeating: 0, count: 16)
        let hrc = taskport_hook_install(port, taskPtr, targetVA, trampolineVA, &originalOut)
        guard hrc == 0 else {
            return fail(String(format: "hook install failed 0x%x", hrc))
        }

        // Give the game a few seconds to run the hooked method, then read the
        // marker: the trampoline zeroes it on first entry.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        var firedMarker: UInt64 = 1
        let rrc = taskport_read(port, trampolineVA + UInt64(paramOff), &firedMarker, 8)
        let fired = rrc == 0 && firedMarker == TASKPORT_MARKER_FIRED
        log.log(.kernelRW, "native hook: marker read -> \(firedMarker) (fired=\(fired))")

        let detail = fired
            ? "hook verified: trampoline executed inside the game"
            : String(format: "armed but marker still 0x%llx (icache suspect, or target not called)", firedMarker)
        return Result(armed: true, fired: fired, targetVA: targetVA,
                      trampolineVA: trampolineVA, slide: slide, detail: detail)
    }
}
