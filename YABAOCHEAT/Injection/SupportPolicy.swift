import Foundation
import Darwin

/// iOS version facts read on demand (cheap sysctls), shared by the OS
/// support gate and the exploit policy.
public enum DeviceOS {
    public static var versionTuple: (major: Int, minor: Int, patch: Int) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion, v.patchVersion)
    }

    public static var versionString: String {
        let v = versionTuple
        return "\(v.major).\(v.minor).\(v.patch)"
    }

    /// `kern.osversion`, e.g. `24A5390f`. The iOS 27 support table is keyed on
    /// the trailing beta build markers, so the build string is read wherever
    /// the policy is evaluated.
    public static var build: String {
        var size: size_t = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return "Unknown"
        }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &value, &size, nil, 0) == 0 else {
            return "Unknown"
        }
        return String(cString: value)
    }

    public static var displayString: String { "iOS \(versionString) (\(build))" }
}

/// Exploit support table, ported from 3105 so Delta accepts exactly the same
/// OS range and rejects everything else:
///
/// - iOS 17.0–17.7.x            → kernel exploit
/// - iOS 18.0–18.7.1            → kernel exploit
/// - iOS 26.0–26.6.1            → bad_query + sandbox escape
/// - iOS 27 beta 1–4            → bad_query + sandbox escape (build-keyed)
public enum ExploitSupportPolicy {
    public static let verifiedIOS17Range = "17.0–17.7.x"
    public static let verifiedIOS18Range = "18.0–18.7.1"
    public static let verifiedIOS26Range = "26.0–26.6.1"

    public static let verifiedIOS27Builds: [(beta: Int, publicBeta: Int?, build: String)] = [
        (1, nil, "24A5355q"),
        (2, nil, "24A5370h"),
        (3, 1, "24A5380h"),
        (4, 2, "24A5390f")
    ]

    public static func iOS27BetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.beta
    }

    public static func iOS27PublicBetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.publicBeta
    }

    public static func supportsKernelExploit(major: Int, minor: Int, patch: Int) -> Bool {
        guard minor >= 0, patch >= 0 else { return false }

        if major == 17 {
            return minor <= 7
        }

        if major == 18 {
            return minor < 7 || (minor == 7 && patch <= 1)
        }

        return false
    }

    public static func isSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        if supportsKernelExploit(major: major, minor: minor, patch: patch) {
            return true
        }

        if major == 26 {
            guard minor >= 0, patch >= 0 else { return false }
            return minor < 6 || (minor == 6 && patch <= 1)
        }

        guard major == 27, minor == 0, patch == 0 else { return false }
        return iOS27BetaNumber(for: build) != nil
    }
}

/// Outcome of the kernel-exploit chain, surfaced on the inject screen.
public enum ExploitStatus: Equatable {
    case notStarted
    case success(method: String)
    case failed(method: String, code: Int64)
    case unsupported(String)

    public var isSuccess: Bool { if case .success = self { return true }; return false }
    public var isFailed: Bool { if case .failed = self { return true }; return false }
}