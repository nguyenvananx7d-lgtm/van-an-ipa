import Foundation
import Darwin

/// Redirects stdout/stderr into `AppLog`, so every `printf` from the C chain
/// shows up on screen and in `Documents/kexploit.log` instead of vanishing.
final class StdioCapture {
    static let shared = StdioCapture()

    private let lock = NSLock()
    private var started = false
    private var readHandle: FileHandle?
    private var buffer = Data()

    private init() {}

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true

        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return }
        dup2(fds[1], STDOUT_FILENO)
        dup2(fds[1], STDERR_FILENO)
        close(fds[1])

        // Line buffering so a crash still leaves complete lines in the pipe.
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)

        let handle = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true)
        readHandle = handle
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
    }

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let raw = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let text = String(data: raw, encoding: .utf8) {
                let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { lines.append(line) }
            }
        }
        lock.unlock()

        for line in lines {
            AppLog.shared.log(.chain, line)
        }
    }
}
