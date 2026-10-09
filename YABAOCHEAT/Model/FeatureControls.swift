import Foundation

/// The full set of runtime tweaks, as a value type.
///
/// The original field names here are exactly the ones the payload's property
/// setters are generated against (`setEnabled`, `setAimbotRadius`,
/// `setHeadshot`, `setAimTarget`, `setAimFovMode`, `setFastReloadPercent`,
/// `setFastFireLevel`, `setEspColor`, `setEspThickness`), so renaming one
/// breaks the wire contract.
///
/// Fields from `aimbotType` on are the panel tabs the mockups show. They ride
/// along in the serialized payload so a payload that learns them picks them up;
/// the shipped blob reads the keys it knows and ignores the rest.
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

    // MARK: panel — aimbot tab

    public var aimbotType: String
    public var silentAim: Bool
    public var hitChance: Int
    /// Maximum lock distance in metres.
    public var aimDistance: Int
    public var drawFov: Bool
    public var ignoreKnocked: Bool
    public var antiBan: Bool

    // MARK: weapon

    public var fastReloadPercent: Int
    public var fastFireLevel: Int

    // MARK: visuals

    /// Packed 0xAARRGGBB.
    public var espColor: Int
    public var espThickness: Int

    // MARK: panel — visual tab

    public var masterEsp: Bool
    public var lineEsp: Bool
    public var boxEsp: Bool
    public var boxType: String
    public var nameEsp: Bool
    public var distanceEsp: Bool
    public var healthEsp: Bool
    public var healthType: String
    public var skeletonEsp: Bool
    public var drawEnemyCount: Bool
    public var textSize: Int
    public var espBounding: Int

    // MARK: panel — setting tab

    public var streamProof: Bool

    public init(
        isEnabled: Bool = false,
        radiusValue: Double = 0,
        aimbotRadiusValue: Double = 0,
        radiusPolicy: ControlPolicy = .value,
        headshotValue: Bool = true,
        headshotPolicy: ControlPolicy = .value,
        aimTarget: String = "head",
        aimFovMode: String = "strict",
        aimbotType: String = "aimbot",
        silentAim: Bool = false,
        hitChance: Int = 85,
        aimDistance: Int = 200,
        drawFov: Bool = true,
        ignoreKnocked: Bool = false,
        antiBan: Bool = false,
        fastReloadPercent: Int = 0,
        fastFireLevel: Int = 0,
        espColor: Int = 0xFF00FF00,
        espThickness: Int = 1,
        masterEsp: Bool = false,
        lineEsp: Bool = false,
        boxEsp: Bool = false,
        boxType: String = "corner",
        nameEsp: Bool = false,
        distanceEsp: Bool = false,
        healthEsp: Bool = false,
        healthType: String = "right",
        skeletonEsp: Bool = false,
        drawEnemyCount: Bool = false,
        textSize: Int = 14,
        espBounding: Int = 2,
        streamProof: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.radiusValue = radiusValue
        self.aimbotRadiusValue = aimbotRadiusValue
        self.radiusPolicy = radiusPolicy
        self.headshotValue = headshotValue
        self.headshotPolicy = headshotPolicy
        self.aimTarget = aimTarget
        self.aimFovMode = aimFovMode
        self.aimbotType = aimbotType
        self.silentAim = silentAim
        self.hitChance = hitChance
        self.aimDistance = aimDistance
        self.drawFov = drawFov
        self.ignoreKnocked = ignoreKnocked
        self.antiBan = antiBan
        self.fastReloadPercent = fastReloadPercent
        self.fastFireLevel = fastFireLevel
        self.espColor = espColor
        self.espThickness = espThickness
        self.masterEsp = masterEsp
        self.lineEsp = lineEsp
        self.boxEsp = boxEsp
        self.boxType = boxType
        self.nameEsp = nameEsp
        self.distanceEsp = distanceEsp
        self.healthEsp = healthEsp
        self.healthType = healthType
        self.skeletonEsp = skeletonEsp
        self.drawEnemyCount = drawEnemyCount
        self.textSize = textSize
        self.espBounding = espBounding
        self.streamProof = streamProof
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

    // MARK: - wire shape

    private enum CodingKeys: String, CodingKey {
        case isEnabled, radiusValue, aimbotRadiusValue, radiusPolicy,
             headshotValue, headshotPolicy, aimTarget, aimFovMode,
             aimbotType, silentAim, hitChance, aimDistance, drawFov,
             ignoreKnocked, antiBan,
             fastReloadPercent, fastFireLevel,
             espColor, espThickness,
             masterEsp, lineEsp, boxEsp, boxType, nameEsp, distanceEsp,
             healthEsp, healthType, skeletonEsp, drawEnemyCount, textSize,
             espBounding,
             streamProof
    }

    /// Profiles written by an older build decode field by field rather than
    /// failing outright when a panel field is absent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeatureControls()

        isEnabled         = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        radiusValue       = try c.decodeIfPresent(Double.self, forKey: .radiusValue) ?? d.radiusValue
        aimbotRadiusValue = try c.decodeIfPresent(Double.self, forKey: .aimbotRadiusValue) ?? d.aimbotRadiusValue
        radiusPolicy      = try c.decodeIfPresent(ControlPolicy.self, forKey: .radiusPolicy) ?? d.radiusPolicy
        headshotValue     = try c.decodeIfPresent(Bool.self, forKey: .headshotValue) ?? d.headshotValue
        headshotPolicy    = try c.decodeIfPresent(ControlPolicy.self, forKey: .headshotPolicy) ?? d.headshotPolicy
        aimTarget         = try c.decodeIfPresent(String.self, forKey: .aimTarget) ?? d.aimTarget
        aimFovMode        = try c.decodeIfPresent(String.self, forKey: .aimFovMode) ?? d.aimFovMode

        aimbotType        = try c.decodeIfPresent(String.self, forKey: .aimbotType) ?? d.aimbotType
        silentAim         = try c.decodeIfPresent(Bool.self, forKey: .silentAim) ?? d.silentAim
        hitChance         = try c.decodeIfPresent(Int.self, forKey: .hitChance) ?? d.hitChance
        aimDistance       = try c.decodeIfPresent(Int.self, forKey: .aimDistance) ?? d.aimDistance
        drawFov           = try c.decodeIfPresent(Bool.self, forKey: .drawFov) ?? d.drawFov
        ignoreKnocked     = try c.decodeIfPresent(Bool.self, forKey: .ignoreKnocked) ?? d.ignoreKnocked
        antiBan           = try c.decodeIfPresent(Bool.self, forKey: .antiBan) ?? d.antiBan

        fastReloadPercent = try c.decodeIfPresent(Int.self, forKey: .fastReloadPercent) ?? d.fastReloadPercent
        fastFireLevel     = try c.decodeIfPresent(Int.self, forKey: .fastFireLevel) ?? d.fastFireLevel

        espColor          = try c.decodeIfPresent(Int.self, forKey: .espColor) ?? d.espColor
        espThickness      = try c.decodeIfPresent(Int.self, forKey: .espThickness) ?? d.espThickness

        masterEsp         = try c.decodeIfPresent(Bool.self, forKey: .masterEsp) ?? d.masterEsp
        lineEsp           = try c.decodeIfPresent(Bool.self, forKey: .lineEsp) ?? d.lineEsp
        boxEsp            = try c.decodeIfPresent(Bool.self, forKey: .boxEsp) ?? d.boxEsp
        boxType           = try c.decodeIfPresent(String.self, forKey: .boxType) ?? d.boxType
        nameEsp           = try c.decodeIfPresent(Bool.self, forKey: .nameEsp) ?? d.nameEsp
        distanceEsp       = try c.decodeIfPresent(Bool.self, forKey: .distanceEsp) ?? d.distanceEsp
        healthEsp         = try c.decodeIfPresent(Bool.self, forKey: .healthEsp) ?? d.healthEsp
        healthType        = try c.decodeIfPresent(String.self, forKey: .healthType) ?? d.healthType
        skeletonEsp       = try c.decodeIfPresent(Bool.self, forKey: .skeletonEsp) ?? d.skeletonEsp
        drawEnemyCount    = try c.decodeIfPresent(Bool.self, forKey: .drawEnemyCount) ?? d.drawEnemyCount
        textSize          = try c.decodeIfPresent(Int.self, forKey: .textSize) ?? d.textSize
        espBounding       = try c.decodeIfPresent(Int.self, forKey: .espBounding) ?? d.espBounding

        streamProof       = try c.decodeIfPresent(Bool.self, forKey: .streamProof) ?? d.streamProof
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

            "aimbotType": aimbotType,
            "silentAim": silentAim,
            "hitChance": hitChance,
            "aimDistance": aimDistance,
            "drawFov": drawFov,
            "ignoreKnocked": ignoreKnocked,
            "antiBan": antiBan,

            "masterEsp": masterEsp,
            "lineEsp": lineEsp,
            "boxEsp": boxEsp,
            "boxType": boxType,
            "nameEsp": nameEsp,
            "distanceEsp": distanceEsp,
            "healthEsp": healthEsp,
            "healthType": healthType,
            "skeletonEsp": skeletonEsp,
            "drawEnemyCount": drawEnemyCount,
            "textSize": textSize,
            "espBounding": espBounding,

            "streamProof": streamProof,
        ]
    }

    // MARK: - runtime configuration document
    //
    // `localConfig.json` is read back by the injected IFix runtime, not by this
    // app. The names are the ones recovered from `__cstring`
    // (`RecoveredVocabulary.RuntimeConfig`): flat, top-level, camelCase. The
    // panel keys ride in the same map so a runtime that learns them picks them
    // up; the shipped blob ignores what it does not know.
    //
    // The earlier output nested everything under `controls` with snake_case
    // keys, so the runtime — which reads top-level camelCase — found nothing.

    /// Flat key/value map the injected runtime overlays onto its own state.
    public func runtimeConfigDocument() -> [String: Any] {
        [
            // recovered runtime keys — exact spelling
            "aimbotRadius":      aimbotRadiusValue,
            "radius":            radiusValue,
            "fastReloadPercent": fastReloadPercent,
            "fastFireLevel":     fastFireLevel,
            "espColor":          espColor,
            "espThickness":      espThickness,
            "aimFovMode":        aimFovMode,
            "h0":                colorRGB,
            "a0":                colorAlpha,

            // behavioural switches
            "enabled":           isEnabled,
            "headshot":          headshotValue,
            "aimTarget":         aimTarget,
            "aim_target":        aimTarget,

            // aimbot panel
            "aimbotType":        aimbotType,
            "silentAim":         silentAim,
            "hitChance":         hitChance,
            "aimDistance":       aimDistance,
            "drawFov":           drawFov,
            "ignoreKnocked":     ignoreKnocked,
            "antiBan":           antiBan,

            // visual panel
            "masterEsp":         masterEsp,
            "lineEsp":           lineEsp,
            "boxEsp":            boxEsp,
            "boxType":           boxType,
            "nameEsp":           nameEsp,
            "distanceEsp":       distanceEsp,
            "healthEsp":         healthEsp,
            "healthType":        healthType,
            "skeletonEsp":       skeletonEsp,
            "drawEnemyCount":    drawEnemyCount,
            "textSize":          textSize,
            "espBounding":       espBounding,

            "streamProof":       streamProof,
            "radiusPolicy":      radiusPolicy.rawValue,
            "headshotPolicy":    headshotPolicy.rawValue,
        ]
    }

    /// The recovered `h0` / `a0` pair decomposed from `espColor`. The runtime
    /// reads a colour through these two keys, so splitting here keeps a single
    /// `espColor` change visible even if `espColor` itself is ignored.
    ///
    /// `h0` = the colour with alpha forced opaque; `a0` = the alpha byte. This
    /// is the only place the decomposition lives — if the recovered runtime
    /// turns out to split differently, edit these two.
    public var colorRGB: Int { espColor & 0x00FF_FFFF }
    public var colorAlpha: Int { (espColor >> 24) & 0xFF }

    /// Envelope field `selected`: the choice the runtime shows as active.
    public var selectedControlIDs: [String: String] {
        [
            "aim_target":   aimTarget,
            "aimbot_type":  aimbotType,
            "aim_fov_mode": aimFovMode,
            "box_type":     boxType,
            "health_type":  healthType,
        ]
    }

    /// Envelope field `options`: the choice set behind each control.
    public static let selectionOptions: [String: [String]] = [
        "aim_target":   ["head", "body"],
        "aimbot_type":  ["aimbot", "silent"],
        "aim_fov_mode": ["strict", "loose"],
        "box_type":     ["corner", "edge"],
        "health_type":  ["left", "right"],
    ]

    /// Envelope field `sections`: panel order the runtime renders.
    public static let panelSections = ["aimbot", "visual", "weapon", "setting"]

    /// Envelope field `anchors`: the two recovered rows that sort between
    /// `aimbotRadius` and `fastReloadPercent`.
    public static let anchors = ["h0", "a0"]
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
