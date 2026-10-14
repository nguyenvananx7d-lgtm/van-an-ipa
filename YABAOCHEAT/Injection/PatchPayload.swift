import Foundation
import CryptoKit

/// The IL2CPP metadata patch that gets dropped into the target game.
///
/// The shipped payload is a real, populated IFix patch `Assembly-CSharp-patch.bytes`.
/// It is not generated at runtime — it is a fixed blob whose SHA-256 is pinned in
/// the licensing handshake, so a tampered payload is refused before it is written
/// anywhere.
public struct PatchPayload: Sendable {
    /// Byte length of the blob shipped in the app bundle.
    ///
    /// The app ships a real, populated IFix patch (151,730 B, targeting
    /// `Assembly-CSharp` 0.86.0.518) rather than the 322-byte zero-patch
    /// manifest. It carries the ESP/aim method overrides directly — including
    /// the patched `get_LastAimingInfoFromWeapon` two-rate silent-aim split
    /// (`HeadRate` / `BodyRate`), the 360° arrow ring, the enemy counter and
    /// the colour/chroma block — so staging it into the container is what
    /// turns the features on.
    ///
    /// This is also the "is the bundle the real blob?" gate: `RuntimeInstaller`
    /// treats a bundle whose length matches this value as the payload to write,
    /// and only falls back to adopting a staged copy when the bundle does not
    /// match. Keep it in step with the resource or injection is refused.
    public static let expectedLength = 151_730

    /// SHA-256 of the vendor's real IFix patch (76,348 B), recovered from the
    /// vendor journal's `active` field and the live container dump. Pinned here
    /// so a copy hidden anywhere in the container can be adopted by digest.
    public static let vendorPatchSHA256 = "2f86dddbf0c7a1664151f0c8b3c7115c36597e92dc70a2895b3f7943f89f3718"

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

    /// The configuration document shipped alongside the patch, if any. This is
    /// the cheat's own `localConfig.json`, staged byte for byte.
    public static func bundledConfiguration() -> Data? {
        guard let url = Bundle.main.url(forResource: "localConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return data
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

    /// The configuration document the injected runtime reads on wake.
    ///
    /// The runtime parses a single flat object in its **own** key spelling
    /// (`EspMaster`, `AimSystemEnabled`, `HeadRate`, `server_aim`, …). The
    /// cheat ships that document as `localConfig.json`, so it is used as the
    /// base: every key the panel does not expose — `NoRecoil`, `SpeedHack`,
    /// `GhostMode`, the `server_*` grants, and the `meomeo` / `sig` / `token` /
    /// `ts` session fields — keeps the value the cheat shipped with. The
    /// guest-reset block is disabled: the blob never runs it, and this document
    /// drops the `reset_guest` / `resetGuest` / `resetGuestBeforeLogin` keys and
    /// sets `ShowGuestBtn` to `false` so the reset button is never drawn.
    ///
    /// The panel's aim / ESP switches are then overlaid on top in the same key
    /// spelling, so a checkbox and the document always agree. `testCodePatch`
    /// is the recovered marker the runtime reads to know the code patch may
    /// apply.
    ///
    /// Static because it is a pure function of the controls — the live-config
    /// path re-stages it without needing the patch blob in hand.
    public static func configuration(for game: Game, controls: FeatureControls) -> Data {
        // Base: the cheat's own document. Empty only if the resource was
        // stripped, in which case the overlay stands on its own.
        var document: [String: Any] = [:]
        if let base = bundledConfiguration(),
           let object = try? JSONSerialization.jsonObject(with: base) as? [String: Any] {
            document = object
        }

        // Overlay: the panel's aim / ESP switches, translated to runtime keys.
        for (key, value) in controls.runtimeConfigDocument() { document[key] = value }

        // Recovered marker: the runtime reads it to know the patch may apply.
        document["testCodePatch"] = true

        return (try? JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data("{}".utf8)
    }
}

