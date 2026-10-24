import Foundation
import Darwin

/// Kernel-side metadata forgery used by `AntiBanRoutine`.
///
/// The userspace half of the sweep can rewrite `mtime`, `atime` and
/// `birthtime` with `utimes` / `setattrlist`, but it can never set the inode
/// change time (`st_ctime`): every metadata write the VFS performs stamps it
/// again. A scanner that compares `ctime` against the app's install baseline
/// therefore still sees a freshly-touched payload no matter how carefully the
/// sweep re-stamps. This type closes that gap by writing the vnode's timestamp
/// block straight through the kernel R/W primitives the exploit chain already
/// holds. A raw memory write bypasses the VFS entirely, so no timestamp is
/// re-stamped and no `fsevent` is emitted.
///
/// Two safeguards keep the raw write honest:
///
/// - the target vnode comes from *our own* open file descriptor
///   (`get_vnode_by_fd`), so nothing outside the staged payload can be hit;
/// - the field offset is discovered, not hardcoded. The vnode is read into a
///   bounded window and the two slots holding exactly this file's `mtime` and
///   `ctime` are located by value, then overwritten in place. A layout that
///   does not match is left untouched and skipped — never guessed at.
///
/// Everything here is a no-op unless `KernelExploit.markKernelRWReady()` has
/// run in this process. The primitives panic on a bad call before the exploit
/// wins, so the gate is not optional.
enum KernelMask {

    /// Inclusive window scanned inside a vnode. A `struct vnode` is a little
    /// over 0x300 bytes on current XNU; 0x600 leaves headroom for the struct
    /// to grow without walking into an unrelated allocation.
    private static let scanWindow = 0x600
    private static let scanStride = 4

    /// Stable per-process check: true only once the chain has won and the
    /// primitive still answers a read at a known-good address.
    static func isAvailable() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard KernelExploit.kernelRWReady else { return false }
        let proc = proc_self()
        guard proc != 0, is_kaddr_valid(proc) else { return false }
        let procRO = kread64(proc + UInt64(off_proc_p_proc_ro))
        return procRO != 0 && is_kaddr_valid(procRO)
        #endif
    }

    // MARK: - timestamps

    /// Rewrite `mtime`, `atime` and `ctime` of every existing path to
    /// `baseline`, at the vnode level. Returns the basenames it actually
    /// changed; paths that already read as the baseline are skipped so a
    /// steady-state guard pass performs no kernel writes at all.
    @discardableResult
    static func forgeTimestamps(paths: [String], baseline: Date) -> [String] {
        #if targetEnvironment(simulator)
        return []
        #else
        guard isAvailable() else { return [] }
        let target = Int32(clamping: Int(baseline.timeIntervalSince1970))
        var forged: [String] = []

        for path in paths {
            var st = stat()
            guard stat(path, &st) == 0 else { continue }

            let mtime = Int32(clamping: Int(st.st_mtimespec.tv_sec))
            let ctime = Int32(clamping: Int(st.st_ctimespec.tv_sec))
            // Nothing to do when both already read as the baseline. This is
            // the steady state: the guard runs every few seconds and must not
            // touch the inode once the posture holds.
            if mtime == target && ctime == target { continue }

            let fd = open(path, O_RDONLY)
            guard fd >= 0 else { continue }
            defer { close(fd) }

            let vnode = get_vnode_by_fd(fd)
            guard vnode != 0, is_kaddr_valid(vnode) else { continue }

            var window = [UInt8](repeating: 0, count: scanWindow)
            window.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                kreadbuf(vnode, base, UInt64(scanWindow))
            }

            guard let offset = locateTimestampPair(
                window, mtime: UInt32(bitPattern: mtime), ctime: UInt32(bitPattern: ctime),
                target: UInt32(bitPattern: target)
            ) else {
                // Unknown vnode layout for this build: report nothing rather
                // than write at a guessed offset.
                continue
            }

            kwrite32(vnode + UInt64(offset), UInt32(bitPattern: target))
            kwrite32(vnode + UInt64(offset + scanStride), UInt32(bitPattern: target))
            forged.append((path as NSString).lastPathComponent)
        }
        return forged
        #endif
    }

    /// Find the adjacent `(mtime, ctime)` pair inside the vnode window.
    ///
    /// XNU keeps the four timestamps as consecutive 32-bit seconds; the field
    /// order moved between releases, so both orders are accepted. A slot that
    /// already holds the target counts as a match too, which makes a second
    /// pass over an already-forged vnode a no-op instead of a miss.
    private static func locateTimestampPair(
        _ window: [UInt8],
        mtime: UInt32,
        ctime: UInt32,
        target: UInt32
    ) -> Int? {
        guard window.count >= scanStride * 2 else { return nil }
        var offset = 0
        while offset + scanStride * 2 <= window.count {
            let first = readU32(window, offset)
            let second = readU32(window, offset + scanStride)
            let forward = (first == mtime || first == target) && (second == ctime || second == target)
            let reverse = (first == ctime || first == target) && (second == mtime || second == target)
            // Require at least one slot to carry a real, non-zero timestamp so
            // an all-zero stretch of the struct cannot masquerade as a match.
            if (forward || reverse) && (first != 0 || second != 0) {
                return offset
            }
            offset += scanStride
        }
        return nil
    }

    private static func readU32(_ buffer: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(buffer[offset])
            | (UInt32(buffer[offset + 1]) << 8)
            | (UInt32(buffer[offset + 2]) << 16)
            | (UInt32(buffer[offset + 3]) << 24)
    }

    // MARK: - process identity

    /// Replace this process's kernel-side short name (`p_name`, what
    /// `sysctl KERN_PROC` reports as `p_comm`) with `name`.
    ///
    /// A target that walks the process table looking for an injector only ever
    /// sees a name that belongs to the system. The rename is a direct field
    /// write, so it emits nothing and survives for the life of the process.
    @discardableResult
    static func renameProcess(to name: String) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard isAvailable() else { return false }
        let proc = proc_self()
        guard proc != 0, is_kaddr_valid(proc) else { return false }

        // `p_name` is an inline 32-byte buffer (`MAXCOMLEN + 1` padded), so a
        // fixed-size overwrite clears the old spelling and its tail.
        var buffer = [UInt8](repeating: 0, count: 32)
        for (index, byte) in name.utf8.prefix(31).enumerated() {
            buffer[index] = byte
        }
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            kwritebuf(proc + UInt64(off_proc_p_name), base, 32)
        }
        return true
        #endif
    }
}
