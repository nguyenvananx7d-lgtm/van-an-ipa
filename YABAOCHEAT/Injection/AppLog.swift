import Foundation
import os

/// Ring buffer of everything the injector did, shown on the log screen.
///
/// Capped so a long session cannot grow without bound; the cap is surfaced in
/// the UI so a truncated log is never mistaken for a complete one.
public final class AppLog: ObservableObject {
    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let subsystem: Subsystem
        public let message: String

        public enum Subsystem: String, CaseIterable, Sendable {
            case auth = "AUTH"
            case kernelRW = "KRW"
            case sandbox = "SANDBOX"
            case mcm = "MCM"
            case integrity = "INTEGRITY"
            case wipe = "WIPE"
            case live = "LIVE"
            case runtime = "RUNTIME"
            case launch = "LAUNCH"
        }

        public init(id: UUID = UUID(), date: Date = Date(), subsystem: Subsystem, message: String) {
            self.id = id
            self.date = date
            self.subsystem = subsystem
            self.message = message
        }
    }

    public static let capacity = 500
    public static let fileName = "ffxc_debug.log"

    @Published public private(set) var entries: [Entry] = []

    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.apple.mobile.MobileHouseArrest", category: "injector")

    public init() {}

    @discardableResult
    public func log(_ subsystem: Entry.Subsystem, _ message: String) -> Entry {
        let entry = Entry(subsystem: subsystem, message: message)
        lock.lock()
        entries.append(entry)
        if entries.count > AppLog.capacity {
            entries.removeFirst(entries.count - AppLog.capacity)
        }
        lock.unlock()
        logger.log("\(subsystem.rawValue, privacy: .public) \(message, privacy: .public)")
        return entry
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    public var plainText: String {
        lock.lock()
        defer { lock.unlock() }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return entries.map { "\(f.string(from: $0.date)) [\($0.subsystem.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }

    /// Mirror the log into the app's Documents directory so it can be pulled off
    /// the device. Written on a background queue; failures are non-fatal.
    public func flush() {
        let text = plainText
        DispatchQueue.global(qos: .utility).async {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { return }
            let url = docs.appendingPathComponent(AppLog.fileName)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
