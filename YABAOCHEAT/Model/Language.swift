import Foundation

/// Interface language. Seven are shipped; `rawValue` doubles as the
/// `Bundle` localization directory and as the `defaultsKey` suffix.
public enum Language: String, CaseIterable, Identifiable, Codable, Sendable {
    case english
    case indonesian
    case vietnamese
    case portuguese
    case moroccan
    case arabic
    case taiwanese

    public var id: String { rawValue }

    /// Native display name, as shown in the picker itself.
    public var displayName: String {
        switch self {
        case .english:     return "English"
        case .indonesian:  return "Bahasa Indonesia"
        case .vietnamese:  return "Tiếng Việt"
        case .portuguese:  return "Português (Brasil)"
        case .moroccan:    return "Darija (المغرب)"
        case .arabic:      return "العربية"
        case .taiwanese:   return "繁體中文"
        }
    }

    /// Flag shown beside the name in the picker.
    public var flag: String {
        switch self {
        case .english:     return "🇬🇧"
        case .indonesian:  return "🇮🇩"
        case .vietnamese:  return "🇻🇳"
        case .portuguese:  return "🇧🇷"
        case .moroccan:    return "🇲🇦"
        case .arabic:      return "🇸🇦"
        case .taiwanese:   return "🇹🇼"
        }
    }

    /// Right-to-left scripts need the whole interface mirrored, not just the
    /// strings, so the flag lives here rather than in the view layer.
    public var isRightToLeft: Bool { self == .arabic }
}

/// Where the injector is in its cycle for a given game.
public enum InjectState: String, CaseIterable, Sendable {
    case unsupportedOS
    case unsupportedHardware
    case gameNotInstalled
    case containerAccessDenied
    case failed
    case checking
    case ready
    case unavailable
    case simulator
    case containerBridgeUnavailable
    case injecting

    public var isTerminal: Bool {
        switch self {
        case .ready, .failed, .unsupportedOS, .unsupportedHardware,
             .simulator, .gameNotInstalled, .containerAccessDenied,
             .containerBridgeUnavailable, .unavailable:
            return true
        case .checking, .injecting:
            return false
        }
    }

    public var isBusy: Bool { self == .checking || self == .injecting }

    /// Set while the state reflects a freshly completed attempt rather than a
    /// cached result.
    public var isResolved: Bool { self != .checking && self != .injecting }
}

/// Outcome of the container lookup, surfaced separately from `InjectState` so
/// the UI can explain *why* an otherwise generic state happened.
public enum ContainerResolution: String, Sendable {
    case resolved
    case notFound
    case accessDenied
    case bridgeUnavailable
}

/// How a live deployment is encoded on the wire.
public enum DeploymentEncoding: String, Codable, Sendable {
    case json = "application/json"
    case propertyList

    public var contentType: String { self == .json ? "application/json" : "application/x-plist" }
}

public enum DeploymentStatus: String, Codable, Sendable {
    case ok
    case updated
    case unchanged
    case unknown
}
