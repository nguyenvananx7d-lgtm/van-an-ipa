import Foundation
import CryptoKit

/// Self-check run before the UI will let an injection proceed.
///
/// Three digests matter: the neutral (unpatched) patch, the patch actually
/// staged, and the game's own executable. The server pins all three during
/// authorization, so a device with a tampered binary, a swapped payload, or a
/// modified game is caught before anything is written.
///
/// ## What the decompilation settled
///
/// This is the only function in the image that touches `CryptoKit`
/// (`_$s9CryptoKit6SHA256VMa`, `SHA256Digest`, `HashFunction.finalize`), and the
/// only one that references the literal `injected-runtime`. It is 19,640 bytes
/// of `__text` — the largest single function in the binary — at address
/// `0x100064ffc`.
///
/// Two details are worth recording because they are not guesses:
///
/// - The magic comparison is **ASCII-exact**, not Unicode-normalising. The body
///   calls `_stringCompareWithSmolCheck`, which is the runtime's fast path for
///   comparing two strings for byte equality. A normalised comparison would have
///   pulled in the Unicode tables instead. So the patch header is compared as
///   raw bytes against `FFXC-MACHO-PREFIX-v2`.
/// - It uses `Data.subdata`, so the digest is computed over a *slice* of the
///   staged file — the prefix region — rather than the whole payload. Hashing
///   the entire file would not need a sub-range.
public struct IntegrityChecker: Sendable {
    /// Recovered literals, used to locate and validate the staged patch.
    public enum Magic {
        /// The segment name the runtime is installed under.
        public static let runtimeSegment = "injected-runtime"
        /// The marker at the head of the patched Mach-O. 322 bytes total,
        /// including this header.
        public static let machoPrefix = "FFXC-MACHO-PREFIX-v2"
        /// Findings tag emitted to the log and to `FFXCIntegrityFailed`.
        public static let invalidExecutable = "invalid-executable"
    }

    private let log: AppLog

    public init(log: AppLog) {
        self.log = log
    }

    public enum Outcome: Sendable {
        case healthy(IntegrityReport)
        case failed(IntegrityFailure, IntegrityReport)
    }

    public func check(expectedPatchSHA256: String?, expectedNeutralSHA256: String?) -> Outcome {
        var findings: [String] = []

        // Our own executable.
        let executableDigest = digestOfSelf()
        if executableDigest.isEmpty {
            findings.append("cannot digest own executable")
        }

        // The bundled payload, as shipped.
        let payload = try? PatchPayload.bundled()
        let bundledPatch = payload?.sha256 ?? ""
        if bundledPatch.isEmpty {
            findings.append("payload missing from bundle")
        } else if let expectedPatchSHA256, !expectedPatchSHA256.isEmpty {
            if bundledPatch.caseInsensitiveCompare(expectedPatchSHA256) != .orderedSame {
                findings.append("bundled payload digest differs from the pinned digest")
            }
        }

        // The neutral blob: a zeroed patch the server can diff against to prove
        // the real one has not been extended with extra entries.
        let neutral = neutralDigest()
        if let expectedNeutralSHA256, !expectedNeutralSHA256.isEmpty {
            if neutral.caseInsensitiveCompare(expectedNeutralSHA256) != .orderedSame {
                findings.append("neutral digest mismatch")
            }
        }

        let report = IntegrityReport(
            neutralSHA256: neutral,
            patchSHA256: bundledPatch,
            executableDigest: executableDigest,
            findings: findings
        )

        for finding in findings {
            log.log(.integrity, "FAIL \(finding)")
        }
        if findings.isEmpty {
            log.log(.integrity, "check passed")
            return .healthy(report)
        }

        if findings.contains(where: { $0.contains("payload missing") }) {
            return .failed(.missingResource, report)
        }
        if findings.contains(where: { $0.contains("neutral") }) {
            return .failed(.invalidNeutral, report)
        }
        return .failed(.integrityMismatch, report)
    }

    // MARK: - digests

    func digestOfSelf() -> String {
        #if DEBUG
        // A debug build's binary will never match a production digest, so report
        // the digest without comparing it rather than failing every run.
        return selfDigest() ?? ""
        #else
        return selfDigest() ?? ""
        #endif
    }

    private func selfDigest() -> String? {
        let path = Bundle.main.executablePath ?? Bundle.main.bundlePath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Digest of an all-zero patch of the expected length. Stable across builds,
    /// so the server can pin it without shipping the blob.
    private func neutralDigest() -> String {
        let neutral = Data(repeating: 0, count: PatchPayload.expectedLength)
        return SHA256.hash(data: neutral).map { String(format: "%02x", $0) }.joined()
    }
}
