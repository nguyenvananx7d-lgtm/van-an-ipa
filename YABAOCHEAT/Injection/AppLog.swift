import Foundation
import os

/// Ring buffer for the exploit stages. Safe to call from the background thread
/// that runs the chain; publishing is marshalled to the main queue because
/// SwiftUI reads `entries`. Every line is also appended to
/// `Documents/kexploit.log` synchronously so a panic cannot take the tail of
/// the log with it.
public final class AppLog: ObservableObject {
    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let subsystem: Subsystem
        public let message: String

        public enum Subsystem: String, Sendable {
            case chain = "CHAIN"
            case kernelRW = "KRW"
            case sandbox = "SANDBOX"
        }

        public init(id: UUID = UUID(), date: Date = Date(), subsystem: Subsystem, message: String) {
            self.id = id
            self.date = date
            self.subsystem = subsystem
            self.message = message
        }
    }

    public static let shared = AppLog()
    public static let capacity = 1500
    public static let fileName = "kexploit.log"

    @Published public private(set) var entries: [Entry] = []

    private let lock = NSLock()
    private let fileLock = NSLock()
    private var storage: [Entry] = []
    private var fileHandle: FileHandle?
    private let logger = Logger(subsystem: "com.apple.mobile.MobileHouseArrest", category: "kexploit")

    public init() {}

    @discardableResult
    public func log(_ subsystem: Entry.Subsystem, _ message: String) -> Entry {
        let entry = Entry(subsystem: subsystem, message: message)

        lock.lock()
        storage.append(entry)
        if storage.count > Self.capacity {
            storage.removeFirst(storage.count - Self.capacity)
        }
        let snapshot = storage
        lock.unlock()

        logger.log("\(subsystem.rawValue, privacy: .public) \(message, privacy: .public)")
        persist(entry)
        publish(snapshot)
        return entry
    }

    /// Clears the on-screen buffer. The file keeps the full history.
    public func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
        publish([])
    }

    public var plainText: String {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return snapshot
            .map { "\(f.string(from: $0.date)) [\($0.subsystem.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }

    /// Push the file buffer to disk. The lines are already written; this only
    /// forces them out before the process may die.
    public func flush() {
        fileLock.lock()
        fileHandle?.synchronize()
        fileLock.unlock()
    }

    private func persist(_ entry: Entry) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "\(f.string(from: entry.date)) [\(entry.subsystem.rawValue)] \(entry.message)\n"

        fileLock.lock()
        defer { fileLock.unlock() }
        if fileHandle == nil {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { return }
            let url = docs.appendingPathComponent(Self.fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            fileHandle = try? FileHandle(forWritingTo: url)
            fileHandle?.seekToEndOfFile()
        }
        fileHandle?.write(Data(line.utf8))
    }

    private func publish(_ snapshot: [Entry]) {
        if Thread.isMainThread {
            entries = snapshot
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.entries = snapshot
            }
        }
    }
}
