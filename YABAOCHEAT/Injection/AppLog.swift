import Foundation
import os

/// Ring buffer for the exploit stages. Safe to call from the background thread
/// that runs the chain; publishing is marshalled to the main queue because
/// SwiftUI reads `entries`.
public final class AppLog: ObservableObject {
    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let subsystem: Subsystem
        public let message: String

        public enum Subsystem: String, Sendable {
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
    private var storage: [Entry] = []
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
        publish(snapshot)
        return entry
    }

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

    /// Mirror the log into Documents so it can be pulled off the device.
    public func flush() {
        let text = plainText
        DispatchQueue.global(qos: .utility).async {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { return }
            try? text.write(
                to: docs.appendingPathComponent(AppLog.fileName),
                atomically: true,
                encoding: .utf8
            )
        }
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
