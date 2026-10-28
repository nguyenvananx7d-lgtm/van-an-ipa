import Foundation
import Network

/// Feature bits — must match `GhostPayload/include/ghost.h` byte for byte.
public enum GhostFlag {
    public static let esp: UInt32        = 1 << 0
    public static let box: UInt32        = 1 << 1
    public static let name: UInt32       = 1 << 2
    public static let distance: UInt32   = 1 << 3
    public static let health: UInt32     = 1 << 4
    public static let tracer: UInt32     = 1 << 6
    public static let fovRing: UInt32     = 1 << 10
    public static let aim: UInt32        = 1 << 15
    public static let aimVisible: UInt32 = 1 << 16
    public static let aimKnocked: UInt32 = 1 << 17
    public static let aimTouch: UInt32   = 1 << 18
}

/// The packed struct the payload reads over loopback.
///
/// The wire order below is exactly `ghost_settings_t`:
/// magic, version, flags, four ESP floats, six aim floats, four bytes,
/// seq, crc. Total 62 bytes. The C side is packed, so there is no padding to
/// reproduce here — every field is written little-endian in declaration order.
public struct GhostSettings: Sendable {
    public var flags: UInt32 = 0
    public var espMaxDistance: Float = 250
    public var espBoxScale: Float = 1.15
    public var espTextScale: Float = 1.0
    public var espFillAlpha: Float = 0.16
    public var aimFov: Float = 150
    public var aimSmooth: Float = 0.18
    public var aimMaxDistance: Float = 200
    public var aimHitChance: Float = 0.85
    public var aimReaction: Float = 0.18
    public var aimMaxTurn: Float = 660
    public var palette: UInt8 = 0
    public var boxStyle: UInt8 = 0
    public var aimBone: UInt8 = 0
    public var reserved: UInt8 = 0

    public init() {}

    public func encoded(seq: UInt32) -> Data {
        var data = Data(capacity: 62)
        data.putU32(0x4748_5354)          // 'GHST'
        data.putU16(4)                    // GHOST_VERSION
        data.putU32(flags)
        data.putFloat(espMaxDistance)
        data.putFloat(espBoxScale)
        data.putFloat(espTextScale)
        data.putFloat(espFillAlpha)
        data.putFloat(aimFov)
        data.putFloat(aimSmooth)
        data.putFloat(aimMaxDistance)
        data.putFloat(aimHitChance)
        data.putFloat(aimReaction)
        data.putFloat(aimMaxTurn)
        data.append(palette)
        data.append(boxStyle)
        data.append(aimBone)
        data.append(reserved)
        data.putU32(seq)
        data.putU32(GhostCRC32.checksum(data))
        assert(data.count == 62, "ghost_settings_t wire size drifted — sync GhostPayload/include/ghost.h")
        return data
    }
}

private enum GhostCRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xEDB8_8320 : 0)
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func putU16(_ value: UInt16) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func putU32(_ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func putFloat(_ value: Float) {
        putU32(value.bitPattern)
    }
}

/// Loopback server. The payload is the client; the app is the only writer.
///
/// There is no file, no shared container, no URL scheme: the last frame is
/// kept in memory and replayed to every new connection, so a payload that
/// connects late still receives the current settings.
public final class GhostChannel: @unchecked Sendable {
    public static let shared = GhostChannel()

    public static let defaultPort: UInt16 = 47_831

    private let queue = DispatchQueue(label: "com.vortex.ghost.channel")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var latest: Data?
    private var latestImage: Data?
    private var started = false

    /// Called on the main queue when a payload connection becomes ready.
    public var onConnection: (() -> Void)?

    public init() {}

    public func start(port: UInt16 = GhostChannel.defaultPort) {
        queue.async {
            guard !self.started else { return }
            self.started = true
            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
                    host: "127.0.0.1",
                    port: NWEndpoint.Port(rawValue: port) ?? 47_831
                )
                let listener = try NWListener(using: parameters)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.stateUpdateHandler = { state in
                    if case .failed = state {
                        // The next install calls `start` again after `stop`.
                    }
                }
                listener.start(queue: self.queue)
                self.listener = listener
            } catch {
                self.started = false
            }
        }
    }

    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
            self.started = false
        }
    }

    public func send(_ data: Data) {
        queue.async {
            self.latest = data
            for connection in self.connections.values {
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }

    /// The floating-icon image: a 'GHIM' frame — magic, width, height, byte
    /// count, then width*height*4 bytes of RGBA8 (top-left origin).
    public func sendImage(_ rgba: Data, width: Int, height: Int) {
        guard rgba.count == width * height * 4, width > 0, height > 0 else { return }
        var frame = Data(capacity: 16 + rgba.count)
        frame.putU32(0x4748_494D)          // 'GHIM'
        frame.putU32(UInt32(width))
        frame.putU32(UInt32(height))
        frame.putU32(UInt32(rgba.count))
        frame.append(rgba)
        queue.async {
            self.latestImage = frame
            for connection in self.connections.values {
                connection.send(content: frame, completion: .contentProcessed { _ in })
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            self.queue.async {
                switch state {
                case .ready:
                    if let latest = self.latest {
                        connection.send(content: latest, completion: .contentProcessed { _ in })
                    }
                    if let latestImage = self.latestImage {
                        connection.send(content: latestImage, completion: .contentProcessed { _ in })
                    }
                    DispatchQueue.main.async { self.onConnection?() }
                case .failed, .cancelled:
                    self.connections.removeValue(forKey: key)
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
        pump(connection)
    }

    private func pump(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self, weak connection] _, _, isComplete, error in
            guard let self, let connection else { return }
            if isComplete || error != nil {
                self.queue.async {
                    self.connections.removeValue(forKey: ObjectIdentifier(connection))
                }
                return
            }
            self.pump(connection)
        }
    }
}
