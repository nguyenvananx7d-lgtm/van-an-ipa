import Foundation

/// The full set of runtime tweaks, as a value type.
///
/// Field names here are exactly the ones the payload's property setters are
/// generated against (`setEnabled`, `setAimbotRadius`, `setHeadshot`,
/// `setAimTarget`, `setAimFovMode`, `setFastReloadPercent`, `setFastFireLevel`,
/// `setEspColor`, `setEspThickness`), so renaming one breaks the wire contract.
public struct FeatureControls: Codable, Equatable, Sendable {
    // MARK: aimbot

    public var isEnabled: Bool
    /// Head radius the assist locks onto.
    public var radiusValue: Double
    /// Field-of-view radius for the aim assist, distinct from the head radius.
    public var aimbotRadiusValue: Double
    public var radiusPolicy: ControlPolicy
    public var headshotValue: Bool
    public var headshotPolicy: ControlPolicy
    /// Bone the assist targets.
    public var aimTarget: String
    public var aimFovMode: String

    // MARK: weapon

    public var fastReloadPercent: Int
    public var fastFireLevel: Int

    // MARK: visuals

    /// Packed 0xAARRGGBB.
    public var espColor: Int
    public var espThickness: Int

    public init(
        isEnabled: Bool = false,
        radiusValue: Double = 0,
        aimbotRadiusValue: Double = 0,
        radiusPolicy: ControlPolicy = .value,
        headshotValue: Bool = true,
        headshotPolicy: ControlPolicy = .value,
        aimTarget: String = "head",
        aimFovMode: String = "strict",
        fastReloadPercent: Int = 0,
        fastFireLevel: Int = 0,
        espColor: Int = 0xFF00FF00,
        espThickness: Int = 1
    ) {
        self.isEnabled = isEnabled
        self.radiusValue = radiusValue
        self.aimbotRadiusValue = aimbotRadiusValue
        self.radiusPolicy = radiusPolicy
        self.headshotValue = headshotValue
        self.headshotPolicy = headshotPolicy
        self.aimTarget = aimTarget
        self.aimFovMode = aimFovMode
        self.fastReloadPercent = fastReloadPercent
        self.fastFireLevel = fastFireLevel
        self.espColor = espColor
        self.espThickness = espThickness
    }

    // MARK: - persistence

    /// Controls live in `UserDefaults` under a per-game prefix so the two titles
    /// keep separate profiles.
    public static func defaultsKey(for game: Game) -> String {
        game.defaultsKeyPrefix + "controls"
    }

    public static func load(for game: Game) -> FeatureControls {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey(for: game)),
              let decoded = try? JSONDecoder().decode(FeatureControls.self, from: data)
        else { return FeatureControls() }
        return decoded
    }

    public func save(for game: Game) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: FeatureControls.defaultsKey(for: game))
    }

    // MARK: - payload setters
    //
    // Each of these is the name the injected runtime exposes. They are grouped
    // here rather than generated so the mapping stays greppable.

    public var setterNames: [String] {
        [
            "setEnabled", "setRadius", "setAimbotRadius", "setHeadshot",
            "setAimTarget", "setAimFovMode", "setFastReloadPercent",
            "setFastFireLevel", "setEspColor", "setEspThickness",
        ]
    }

    /// Serialized form handed to the runtime command surface.
    public func commandPayload() -> [String: Any] {
        [
            "enabled": isEnabled,
            "radius": radiusValue,
            "aimbotRadius": aimbotRadiusValue,
            "radiusPolicy": radiusPolicy.rawValue,
            "headshot": headshotValue,
            "headshotPolicy": headshotPolicy.rawValue,
            "aim_target": aimTarget,
            "aim_fov_mode": aimFovMode,
            "fast_reload_percent": fastReloadPercent,
            "fastFireLevel": fastFireLevel,
            "espColor": espColor,
            "espThickness": espThickness,
        ]
    }
}

/// Swatch offered by the colour control.
public struct ColorSwatch: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let argb: Int

    public init(id: Int, name: String, argb: Int) {
        self.id = id
        self.name = name
        self.argb = argb
    }

    /// The default ramp, matching the set the payload ships with.
    public static let defaults: [ColorSwatch] = [
        ColorSwatch(id: 0, name: "green",  argb: 0xFF00FF00),
        ColorSwatch(id: 1, name: "red",    argb: 0xFFFF0000),
        ColorSwatch(id: 2, name: "blue",   argb: 0xFF0000FF),
        ColorSwatch(id: 3, name: "yellow", argb: 0xFFFFFF00),
        ColorSwatch(id: 4, name: "magenta",argb: 0xFFFF00FF),
        ColorSwatch(id: 5, name: "cyan",   argb: 0xFF00FFFF),
        ColorSwatch(id: 6, name: "white",  argb: 0xFFFFFFFF),
    ]
}

/// Live command pushed to an already-injected process.
public struct RuntimeCommand: Codable, Sendable {
    public let command: String
    public let unitMask: Int
    public let disableSequence: Int?
    public let disableMac: String?
    public let sequence: Int
    public let leaseSeconds: Int

    public init(
        command: String,
        unitMask: Int,
        disableSequence: Int? = nil,
        disableMac: String? = nil,
        sequence: Int,
        leaseSeconds: Int
    ) {
        self.command = command
        self.unitMask = unitMask
        self.disableSequence = disableSequence
        self.disableMac = disableMac
        self.sequence = sequence
        self.leaseSeconds = leaseSeconds
    }
}
