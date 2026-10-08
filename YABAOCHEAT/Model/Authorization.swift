import Foundation

/// Every terminal outcome the licensing server can report.
///
/// These raw values are the strings the server sends and the ones the app
/// switches on; they are recovered verbatim and must not be renamed without a
/// matching server change.
public enum LicenseErrorCode: String, CaseIterable, Sendable {
    // authorization verdict
    case valid
    case revoked
    case deleted
    case expired
    case deviceMismatch
    case invalid

    // transport / envelope
    case server
    case network
    case networkError
    case malformedResponse
    case invalidSignature
    case replayDetected
    case sessionInvalid

    // local
    case secureStorage
    case integrityFailed
    case fileUnavailable
    case writeFailed
    case containerNotFound
    case processResetUnavailable
    case launchFailed

    // capability
    case supported
    case unsupportedOS
    case unsupportedHardware
    case simulator

    /// Codes that mean "the key itself is no good" as opposed to "the check
    /// could not be completed". Only these clear the stored key.
    public var invalidatesKey: Bool {
        switch self {
        case .revoked, .deleted, .expired, .deviceMismatch, .invalid:
            return true
        case .valid, .server, .network, .networkError, .malformedResponse,
             .invalidSignature, .replayDetected, .sessionInvalid, .secureStorage,
             .integrityFailed, .fileUnavailable, .writeFailed, .containerNotFound,
             .processResetUnavailable, .launchFailed, .supported,
             .unsupportedOS, .unsupportedHardware, .simulator:
            return false
        }
    }

    /// Codes worth backing off on rather than retrying immediately.
    public var isTransient: Bool {
        self == .network || self == .networkError || self == .server
    }
}

public extension LicenseErrorCode {
    /// Wording for a bare code, from the same table `LicenseError` reads.
    var localizedDescription: String {
        String(localized: "license_error.\(rawValue)")
    }
}

/// Error surfaced to the UI. Carries the code plus optional server detail so the
/// license screen can show the server's own wording when it sends any.
public struct LicenseError: Error, Sendable {
    public let code: LicenseErrorCode
    public let detail: String?
    /// Device the key is actually bound to, when the server says so.
    public let boundDevice: String?

    public init(code: LicenseErrorCode, detail: String? = nil, boundDevice: String? = nil) {
        self.code = code
        self.detail = detail
        self.boundDevice = boundDevice
    }

    public var localizedDescription: String {
        if let detail, !detail.isEmpty { return detail }
        return String(localized: "license_error.\(code.rawValue)")
    }

    public static func == (a: LicenseError, b: LicenseError) -> Bool { a.code == b.code }
}

/// Authorization state, split from the error so the UI can show "online but
/// revoked" separately from "offline, last checked at ...".
public enum AuthorizationStatus: Equatable, Sendable {
    case unknown
    case checking
    case valid(plan: String, displayKey: String, expiresAt: Date)
    case invalid(LicenseErrorCode)
    case offline(since: Date, lastError: LicenseErrorCode)

    public var isOnline: Bool {
        if case .valid = self { return true }
        return false
    }

    public var plan: String? {
        if case .valid(let plan, _, _) = self { return plan }
        return nil
    }

    public var displayKey: String? {
        if case .valid(_, let key, _) = self { return key }
        return nil
    }

    public var expiresAt: Date? {
        if case .valid(_, _, let exp) = self { return exp }
        return nil
    }
}
