import Foundation

/// Signed authorization response, exactly as the licensing server returns it.
///
/// The envelope is `data` / `ts` / `sig` / `sequence` / `aux`; `sig` is verified
/// against the pinned client public key before any of the inner fields is read.
public struct LicenseResponse: Codable, Sendable {
    public let status: String
    public let message: String?
    public let plan: String?
    public let expiresAt: String?
    public let metadata: [String: [String: String]]?
    public let session: String?
    public let sessionTtl: Int?
    public let sessionExpiresAt: String?
    public let catalog: [ControlDescriptor]?
    public let deployment: Deployment?
    public let command: RuntimeCommand?
    public let credential: Credential?
    public let licenseLabel: String?

    public var errorCode: LicenseErrorCode? {
        guard let raw = LicenseErrorCode(rawValue: status) else { return nil }
        return raw == .valid ? nil : raw
    }
}

/// Envelope as it comes off the wire, before verification.
public struct SignedEnvelope: Codable, Sendable {
    public let data: String        // base64
    public let ts: Int
    public let sig: String         // base64
    public let sequence: Int
    public let aux: [String: String]?
    public let leaseSeconds: Int
    public let mac: String?
}

/// Credential block returned on a successful bootstrap.
public struct Credential: Codable, Sendable {
    public let keyId: String
    public let deviceCredentialId: String
    public let signingHandle: String
    public let keyExpiresAt: String
}

/// Deployment directive: where to pull the next payload from and how fresh it is.
public struct Deployment: Codable, Sendable {
    public let status: DeploymentStatus
    public let encoding: DeploymentEncoding
    public let url: String?
    public let protocolVersion: Int
    public let minimumBuild: Int
    public let securitySchema: Int
    public let heartbeatSeconds: Int
    public let maxNetworkErrors: Int
    public let verifiedAt: String?
    public let validUntil: String?
}

/// Device facts the server binds a key to.
///
/// `hwid` is a hardware identifier, `mac` the Wi-Fi address; both are sent so the
/// server can detect a key replayed onto different hardware.
public struct DeviceIdentity: Codable, Sendable {
    public let hwid: String
    public let mac: String
    public let deviceName: String
    public let iOSVersion: String
    public let iPhoneModel: String

    /// Models this build is known to work on. Anything else is reported as
    /// `unsupportedHardware` before any container work is attempted.
    public static let supportedModels: Set<String> = [
        "iPhone 11 Pro Max", "iPhone 12 Pro Max", "iPhone 13 Pro Max",
        "iPhone 14 Pro Max", "iPhone 15 Pro Max", "iPhone 16 Pro Max",
    ]

    public var isSupportedModel: Bool { DeviceIdentity.supportedModels.contains(iPhoneModel) }
}

/// Result of the integrity self-check, run before the UI will allow injection.
public struct IntegrityReport: Sendable {
    public let neutralSHA256: String
    public let patchSHA256: String
    public let executableDigest: String
    public let findings: [String]

    public var isHealthy: Bool { findings.isEmpty }
}

/// Why an integrity check failed, mapped onto a license error code.
public enum IntegrityFailure: String, Sendable {
    case integrityMismatch
    case invalidNeutral
    case missingResource
}
