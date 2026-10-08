import Foundation

/// The two titles this build knows how to target.
///
/// Both bundle identifiers are recovered verbatim from `__TEXT,__cstring`.
public enum Game: String, CaseIterable, Identifiable, Codable, Sendable {
    case freeFire
    case freeFireMax

    public var id: String { rawValue }

    /// `UserDefaults` key holding the current selection.
    public static let defaultsKey = "ffxc.selectedGame"

    /// Control settings are namespaced per game so switching targets does not
    /// carry the previous game's tuning across.
    public static let controlsPrefix = "ffxc.controls.v3."

    public var bundleIdentifier: String {
        switch self {
        case .freeFire:    return "com.dts.freefireth"
        case .freeFireMax: return "com.dts.freefiremax"
        }
    }

    /// On-screen name, so the two titles are never confused in the picker or
    /// in status messages. Brand names stay untranslated in every language.
    public var displayName: String {
        switch self {
        case .freeFire:    return "Free Fire"
        case .freeFireMax: return "Free Fire Max"
        }
    }

    /// Filename of the IL2CPP metadata patch dropped into the target's bundle.
    public var payloadName: String { "Assembly-CSharp-patch" }

    /// Runtime configuration written alongside the payload.
    public var configFileName: String { "localConfig.json" }

    public var defaultsKeyPrefix: String { Game.controlsPrefix + rawValue }
}

/// Every control the payload understands.
///
/// The `id` values here are the wire names used by the deployment catalog and by
/// `setter` on the runtime command surface; they are recovered from `__cstring`
/// and `__swift5_reflstr` and are matched exactly.
public enum ControlID: String, CaseIterable, Sendable {
    case headshot
    case aimTarget      = "aim_target"
    case fastReload     = "fast_reload"
    case fastFire       = "fast_fire"
    case colorControl   = "color_control"
    case aimbotFov      = "aimbot_fov"
    case aimbotFovMode  = "aim_fov_mode"
    case fastReloadPercent = "fast_reload_percent"

    public var id: String { rawValue }
}

/// How a numeric control is constrained.
public enum ControlPolicy: String, Codable, Sendable {
    /// Caller supplies the value directly.
    case value
    /// Caller picks from `options`.
    case option
    /// Caller toggles between two ends.
    case exclusiveGroup
}

/// A single tunable as described by the deployment catalog.
///
/// The server sends a flat `sections` array of these; the UI renders whatever it
/// is handed, so adding a control on the backend needs no app change.
public struct ControlDescriptor: Codable, Identifiable, Sendable {
    public let id: String
    public let section: String
    public let title: String
    public let subtitle: String?
    public let symbol: String?

    public let min: Double?
    public let max: Double?
    public let step: Double?
    public let initial: Double?
    public let options: [String]?
    public let policy: ControlPolicy?
    public let exclusiveGroup: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self, forKey: .id)
        section       = try c.decode(String.self, forKey: .section)
        title         = try c.decode(String.self, forKey: .title)
        subtitle      = try c.decodeIfPresent(String.self, forKey: .subtitle)
        symbol        = try c.decodeIfPresent(String.self, forKey: .symbol)
        min           = try c.decodeIfPresent(Double.self, forKey: .min)
        max           = try c.decodeIfPresent(Double.self, forKey: .max)
        step          = try c.decodeIfPresent(Double.self, forKey: .step)
        initial       = try c.decodeIfPresent(Double.self, forKey: .initial)
        options       = try c.decodeIfPresent([String].self, forKey: .options)
        policy        = try c.decodeIfPresent(ControlPolicy.self, forKey: .policy)
        exclusiveGroup = try c.decodeIfPresent(String.self, forKey: .exclusiveGroup)
    }
}

/// Top level shape of `localConfig.json`.
public struct RuntimeConfiguration: Codable, Sendable {
    public let version: String
    public let sections: [String]
    public let options: [String: [String]]
    public let selected: [String]
    /// Anchor rows recovered from the catalog, e.g. `h0` / `a0`.
    public let anchors: [String]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version  = try c.decode(String.self, forKey: .version)
        sections = try c.decodeIfPresent([String].self, forKey: .sections) ?? []
        options  = try c.decodeIfPresent([String: [String]].self, forKey: .options) ?? [:]
        selected = try c.decodeIfPresent([String].self, forKey: .selected) ?? []
        anchors  = try c.decodeIfPresent([String].self, forKey: .anchors) ?? []
    }
}
