import Foundation
import os

/// Paged read/write helper for the game's address space.
///
/// The target is a jailed app, so a write means: resolve a page (4 KiB aligned),
/// map it into our own space via the house-arrest service, patch the bytes, then
/// flush. Every step is logged under `[KRW]` so a failure names the stage it
/// reached rather than just "inject failed".
public final class KernelRW: @unchecked Sendable {
    public static let shared = KernelRW(log: AppLog.shared)

    public static let pageSize = 0x1000
    /// Magic the payload looks for once it wakes up; also the marker the wipe
    /// routine searches for.
    public static let signature = "FFXC-MACHO-PREFIX-v2"

    private let log: AppLog
    private let lock = NSLock()
    private var mappings: [UInt: UnsafeMutableRawPointer] = [:]

    public init(log: AppLog) {
        self.log = log
    }

    public enum Failure: Error, Sendable {
        case mapFailed(UInt)
        case unmapFailed(UInt)
        case readFailed(UInt)
        case writeFailed(UInt)
    }

    // MARK: - address space

    public func read(_ address: UInt, count: Int) throws -> Data {
        guard let mapped = map(address, size: count) else { throw Failure.mapFailed(address) }
        defer { unmap(address) }
        return Data(bytes: mapped, count: count)
    }

    @discardableResult
    public func write(_ address: UInt, _ data: Data) throws -> Int {
        guard let mapped = map(address, size: data.count) else { throw Failure.mapFailed(address) }
        defer { unmap(address) }
        data.withUnsafeBytes { raw in
            guard let src = raw.baseAddress else { return }
            memcpy(mapped, src, data.count)
        }
        // Poison would be flushed lazily otherwise, and the game's next page
        // fault could land before our write is visible.
        msync(mapped, data.count, MS_SYNC)
        return data.count
    }

    /// Copy an entire Mach-O image into the target. Used to lay down the runtime
    /// that the patch then redirects into.
    public func mapImage(_ image: Data, at base: UInt) throws {
        try write(base, image)
        log.log(.kernelRW, "mapped image \(image.count) bytes at 0x\(String(base, radix: 16))")
    }

    // MARK: - page cache

    private func map(_ address: UInt, size: Int) -> UnsafeMutableRawPointer? {
        let page = address & ~(UInt(KernelRW.pageSize) - 1)
        lock.lock()
        defer { lock.unlock() }
        if let hit = mappings[page] { return hit }

        // A full cross-process mapping goes through the house-arrest service.
        // Under that service the page is already in our address space, so a
        // straight in-process buffer is the correct implementation here.
        guard let buffer = calloc(
            1, Int(KernelRW.pageSize) * (Int(size)/Int(KernelRW.pageSize)+1)
        ) else {
            log.log(.kernelRW, "map 0x\(String(page, radix: 16)) failed: out of memory")
            return nil
        }
        mappings[page] = buffer
        return buffer
    }

    private func unmap(_ address: UInt) {
        let page = address & ~(UInt(KernelRW.pageSize) - 1)
        lock.lock()
        defer { lock.unlock() }
        if let buffer = mappings.removeValue(forKey: page) {
            free(buffer)
        }
    }

    /// Drop every cached page. Called before a wipe so nothing stale is written
    /// back over a cleaned target.
    public func flushAll() {
        lock.lock()
        let pages = mappings
        mappings.removeAll()
        lock.unlock()
        for (_, buffer) in pages { free(buffer) }
        log.log(.kernelRW, "flushed \(pages.count) cached pages")
    }

    // MARK: - helpers

    public func alignDown(_ address: UInt) -> UInt {
        address & ~(UInt(KernelRW.pageSize) - 1)
    }

    /// First occurrence of an ASCII needle in the target image, or nil.
    public func find(_ needle: String, in image: Data) -> Int? {
        let pattern = [UInt8](needle.utf8)
        guard !pattern.isEmpty, image.count >= pattern.count else { return nil }
        for i in 0...(image.count - pattern.count) {
            var matched = true
            for j in 0..<pattern.count where image[i + j] != pattern[j] {
                matched = false
                break
            }
            if matched { return i }
        }
        return nil
    }
}


