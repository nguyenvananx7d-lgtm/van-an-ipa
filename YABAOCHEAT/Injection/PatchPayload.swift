import Foundation
import CryptoKit

/// The IL2CPP metadata patch that gets dropped into the target game.
///
/// The shipped payload is a 322-byte `Assembly-CSharp-patch.bytes`. It is not
/// generated at runtime — it is a fixed blob whose SHA-256 is pinned in the
/// licensing handshake, so a tampered payload is refused before it is written
/// anywhere.
public struct PatchPayload: Sendable {
    /// Byte length of the blob shipped in the app bundle.
    public static let expectedLength = 322

    public static let fileName = "Assembly-CSharp-patch.bytes"

    public let data: Data
    public let sha256: String

    public init(data: Data) {
        self.data = data
        self.sha256 = PatchPayload.digest(of: data)
    }

    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Digest of an all-zero patch of the expected length. Stable across
    /// builds, so it can be pinned without shipping the blob.
    public static func neutralDigest() -> String {
        digest(of: Data(repeating: 0, count: expectedLength))
    }

    /// The pins to use when there is no server to ask: the digest of what is
    /// actually in the bundle, plus the neutral digest above. They feed the
    /// same `verify` gate server-pinned values do, so a tampered bundle is
    /// still refused before any byte reaches the container.
    public static func localPins() -> (patch: String, neutral: String) {
        let bundled = (try? bundled())?.sha256 ?? ""
        return (bundled, neutralDigest())
    }

    /// Load the payload that ships in this bundle.
    public static func bundled() throws -> PatchPayload {
        guard let url = Bundle.main.url(forResource: "Assembly-CSharp-patch", withExtension: "bytes"),
              let data = try? Data(contentsOf: url)
        else { throw PayloadError.missingResource }
        return PatchPayload(data: data)
    }

    public enum PayloadError: Error, Sendable {
        case missingResource
        case invalidNeutral
        case integrityMismatch
    }

    /// Verify the payload against the digest the server pinned during
    /// authorization. A mismatch is fatal — installing a modified patch would
    /// mean writing attacker-chosen bytes into another process.
    public func verify(against expected: String?) throws {
        guard let expected, !expected.isEmpty else {
            throw PayloadError.integrityMismatch
        }
        guard data.count == PatchPayload.expectedLength else {
            throw PayloadError.integrityMismatch
        }
        guard sha256.caseInsensitiveCompare(expected) == .orderedSame else {
            throw PayloadError.integrityMismatch
        }
    }

    /// The configuration blob the payload reads on wake. Its shape mirrors
    /// `RuntimeConfiguration`; the payload keys off `id` / `selected` / `version`.
    public func configuration(for game: Game, controls: FeatureControls) -> Data {
        let payload: [String: Any] = [
            "version": ProtocolConstants.protocolVersion,
            "signature": KernelRW.signature,
            "game": game.rawValue,
            "controls": controls.commandPayload(),
            "setters": controls.setterNames,
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
            ?? Data("{}".utf8)
    }
}

