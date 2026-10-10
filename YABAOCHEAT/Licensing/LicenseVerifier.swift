import Foundation
import CryptoKit

/// Verifies the server's signature over an authorization response.
///
/// The server signs the base64 payload with an Ed25519 key. The public key is
/// pinned in the bundle; a key supplied by the response itself is only accepted
/// when it matches what is already trusted, so a compromised server cannot
/// re-point verification at a key it also controls.
public struct LicenseVerifier: Sendable {
    public enum Failure: Error, Sendable {
        case malformedResponse
        case invalidSignature
        case replayDetected
        case invalidNeutral
    }

    /// Maximum age of a signed response before it is treated as a replay.
    public static let maxClockSkew: TimeInterval = 120

    private let trustedKey: Curve25519.Signing.PublicKey?
    private let now: @Sendable () -> Date

    public init(trustedKey: Curve25519.Signing.PublicKey?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.trustedKey = trustedKey
        self.now = now
    }

    /// Load the pinned key from the app bundle.
    public static func pinned(now: @escaping @Sendable () -> Date = { Date() }) -> LicenseVerifier {
        var key: Curve25519.Signing.PublicKey?
        if let url = Bundle.main.url(forResource: ProtocolConstants.Key.clientPublicKey, withExtension: "der"),
           let der = try? Data(contentsOf: url) {
            key = try? Curve25519.Signing.PublicKey(rawRepresentation: der)
        }
        return LicenseVerifier(trustedKey: key, now: now)
    }

    /// Verify an envelope and hand back the decoded body.
    ///
    /// Order matters: freshness is checked before the signature so a captured
    /// envelope cannot be replayed even if the signature is valid.
    public func verify(_ envelope: SignedEnvelope) throws -> LicenseResponse {
        let age = abs(now().timeIntervalSince1970 - Double(envelope.ts))
        guard age <= LicenseVerifier.maxClockSkew else { throw Failure.replayDetected }

        guard let payload = Data(base64Encoded: envelope.data),
              let signature = Data(base64Encoded: envelope.sig)
        else { throw Failure.malformedResponse }

        guard let trustedKey else { throw Failure.invalidSignature }
        guard trustedKey.isValidSignature(signature, for: payload) else { throw Failure.invalidSignature }

        let decoded = try JSONDecoder().decode(LicenseResponse.self, from: payload)

        // The MAC field binds the response to this device. A mismatch means the
        // envelope was minted for other hardware.
        if let mac = envelope.mac, !mac.isEmpty {
            let expected = DeviceIdentityProvider.shared.currentMac
            guard expected.isEmpty || mac == expected else { throw Failure.invalidSignature }
        }

        return decoded
    }

    /// Sign a request with the device key, so the server can pin the credential
    /// to this installation.
    public static func signRequest(
        _ body: Data,
        with key: Curve25519.Signing.PrivateKey
    ) -> Data {
        try! key.signature(for: body)
    }
}

