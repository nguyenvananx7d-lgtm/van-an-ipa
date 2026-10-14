import Foundation

/// The full set of runtime tweaks, as a value type.
///
/// The original field names here are exactly the ones the payload's property
/// setters are generated against (`setEnabled`, `setAimbotRadius`,
/// `setHeadshot`, `setAimTarget`, `setAimFovMode`, `setFastReloadPercent`,
/// `setFastFireLevel`, `setEspColor`, `setEspThickness`), so renaming one
/// breaks the wire contract.
///
/// Ship defaults are Sophia-style: master enable + the full visual ESP set are
/// on, so the first Inject already stages an armed `localConfig.json` instead
/// of a blank one. The `.v4` storage key forces these defaults even when an
/// older (all-off) profile was persisted under `.v3`.
///
/// Fields from `aimbotType` on are the panel tabs the mockups show. They ride
/// along in the serialized payload so a payload that learns them picks them up;
/// the shipped blob reads the keys it knows and ignores the rest.
public struct FeatureControls: Codable, Equatable, Sendable {
    // MARK: aimbot

    public var isEnabled: Bool
    /// Second aim gate the runtime reads under its own key (`AimEnabled`).
    /// Surfaced separately so `AimSystemEnabled` (`isEnabled`) and `AimEnabled`
    /// can be toggled independently.
    public var aimEnabled: Bool
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
    /// Silent aim / "magic bullet". Emitted as `SilentAim`, and it also arms
    /// `AimEnabled` with the mixed-roll `AimTarget` the head/body split drives.
    public var silentAim: Bool
    /// Silent-aim bone split, as percentages of the lock. `headRate` is the
    /// weight for taking the head, `bodyRate` the weight for the body; the
    /// runtime picks head with probability `headRate / (headRate + bodyRate)`.
    /// Emitted to the runtime as `HeadRate` (head) and `BodyRate` (body) and
    /// tuned live from the two sliders that appear under the silent-aim switch.
    public var headRate: Int
    public var bodyRate: Int
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

    /// Enemy-box scale, as a percentage of the runtime's natural box. `100`
    /// leaves the box exactly as drawn; higher grows it so a tall target is
    /// framed head to foot. Emitted to the runtime as `EspBoxScale` (ratio).
    public var espBoxScalePercent: Int
    /// Pushes the enemy box down by this many screen pixels, so an enlarged box
    /// still centres on the body rather than hanging off the head. Emitted to
    /// the runtime as `EspBoxOffset` (pixels).
    public var espBoxOffsetY: Int

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
    /// Tracer line to the enemy. The runtime key is `EspTracer`; the cheat's own
    /// menu labels it "Top tracer".
    public var tracerEsp: Bool
    public var drawEnemyCount: Bool
    public var textSize: Int
    public var espBounding: Int

    // MARK: panel — setting tab

    public var streamProof: Bool

    // MARK: panel — misc features

    /// The cheat's own non-ESP / non-aim switches. They already ride in the
    /// shipped `localConfig.json` under the runtime's spelling; surfacing them
    /// here is what lets the panel drive them instead of leaving them frozen at
    /// the value the document shipped with. Keys: `NoRecoil`, `GhostMode`,
    /// `SpeedHack`, `CamXa`, `CamXaFloat`, `BuffDame` (the cheat's spelling),
    /// `FastParachute`.
    public var noRecoil: Bool
    public var ghostMode: Bool
    /// The runtime reads `SpeedHack` as a number, `1` on / `0` off.
    public var speedHack: Bool
    public var camXa: Bool
    /// Distance the extended camera pushes to, emitted as `CamXaFloat`.
    public var camXaFloat: Double
    public var buffDamage: Bool
    public var fastParachute: Bool

    // MARK: panel — ESP extras

    /// Fan of arrows ringing the screen toward every enemy. Key `Esp360Arrows`.
    public var esp360Arrows: Bool
    /// Where the ESP line is anchored: `top` | `bottom` | `crosshair`.
    public var lineTarget: String

    // MARK: panel — aim extras

    /// Silent-aim target: `mixed` | `head` | `body`.
    public var silentAimTarget: String
    /// Scoped-only lock. Key `SniperScope`.
    public var sniperScope: Bool

    // MARK: panel — colour

    /// Which elements take the palette colour.
    public var fovColor: Bool
    public var lineTracerColor: Bool
    public var box2dColor: Bool
    public var skeletonColor: Bool
    /// Named palette: `default` | `red` | `green` | `blue` | `yellow` | `cyan`
    /// | `pink` | `orange` | `purple` | `white`.
    public var espPalette: String
    public var rainbow: Bool
    public var allRainbow: Bool
    public var resetAllColors: Bool

    /// Every switch starts OFF: the profile ships with nothing enabled and the
    /// player opts into each feature. Value controls (sliders, bone) keep
    /// sensible non-zero defaults so the moment a switch is turned on it does
    /// something useful.
    public init(
        isEnabled: Bool = false,
        aimEnabled: Bool = false,
        radiusValue: Double = 0,
        aimbotRadiusValue: Double = 90.0,
        radiusPolicy: ControlPolicy = .value,
        headshotValue: Bool = false,
        headshotPolicy: ControlPolicy = .value,
        aimTarget: String = "head",
        aimFovMode: String = "strict",
        aimbotType: String = "aimbot",
        silentAim: Bool = false,
        headRate: Int = 80,
        bodyRate: Int = 20,
        hitChance: Int = 85,
        aimDistance: Int = 200,
        drawFov: Bool = false,
        ignoreKnocked: Bool = false,
        antiBan: Bool = false,
        fastReloadPercent: Int = 0,
        fastFireLevel: Int = 0,
        espColor: Int = 0xFF00FF00,
        espThickness: Int = 1,
        espBoxScalePercent: Int = 115,
        espBoxOffsetY: Int = 10,
        masterEsp: Bool = false,
        lineEsp: Bool = false,
        boxEsp: Bool = false,
        boxType: String = "corner",
        nameEsp: Bool = false,
        distanceEsp: Bool = false,
        healthEsp: Bool = false,
        healthType: String = "right",
        skeletonEsp: Bool = false,
        tracerEsp: Bool = false,
        drawEnemyCount: Bool = false,
        textSize: Int = 14,
        espBounding: Int = 2,
        streamProof: Bool = false,
        noRecoil: Bool = false,
        ghostMode: Bool = false,
        speedHack: Bool = false,
        camXa: Bool = false,
        camXaFloat: Double = 1.5,
        buffDamage: Bool = false,
        fastParachute: Bool = false,
        esp360Arrows: Bool = false,
        lineTarget: String = "bottom",
        silentAimTarget: String = "mixed",
        sniperScope: Bool = false,
        fovColor: Bool = false,
        lineTracerColor: Bool = false,
        box2dColor: Bool = false,
        skeletonColor: Bool = false,
        espPalette: String = "default",
        rainbow: Bool = false,
        allRainbow: Bool = false,
        resetAllColors: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.aimEnabled = aimEnabled
        self.radiusValue = radiusValue
        self.aimbotRadiusValue = aimbotRadiusValue
        self.radiusPolicy = radiusPolicy
        self.headshotValue = headshotValue
        self.headshotPolicy = headshotPolicy
        self.aimTarget = aimTarget
        self.aimFovMode = aimFovMode
        self.aimbotType = aimbotType
        self.silentAim = silentAim
        self.headRate = headRate
        self.bodyRate = bodyRate
        self.hitChance = hitChance
        self.aimDistance = aimDistance
        self.drawFov = drawFov
        self.ignoreKnocked = ignoreKnocked
        self.antiBan = antiBan
        self.fastReloadPercent = fastReloadPercent
        self.fastFireLevel = fastFireLevel
        self.espColor = espColor
        self.espThickness = espThickness
        self.espBoxScalePercent = espBoxScalePercent
        self.espBoxOffsetY = espBoxOffsetY
        self.masterEsp = masterEsp
        self.lineEsp = lineEsp
        self.boxEsp = boxEsp
        self.boxType = boxType
        self.nameEsp = nameEsp
        self.distanceEsp = distanceEsp
        self.healthEsp = healthEsp
        self.healthType = healthType
        self.skeletonEsp = skeletonEsp
        self.tracerEsp = tracerEsp
        self.drawEnemyCount = drawEnemyCount
        self.textSize = textSize
        self.espBounding = espBounding
        self.streamProof = streamProof
        self.noRecoil = noRecoil
        self.ghostMode = ghostMode
        self.speedHack = speedHack
        self.camXa = camXa
        self.camXaFloat = camXaFloat
        self.buffDamage = buffDamage
        self.fastParachute = fastParachute
        self.esp360Arrows = esp360Arrows
        self.lineTarget = lineTarget
        self.silentAimTarget = silentAimTarget
        self.sniperScope = sniperScope
        self.fovColor = fovColor
        self.lineTracerColor = lineTracerColor
        self.box2dColor = box2dColor
        self.skeletonColor = skeletonColor
        self.espPalette = espPalette
        self.rainbow = rainbow
        self.allRainbow = allRainbow
        self.resetAllColors = resetAllColors
    }

    // MARK: - persistence

    /// Controls live in `UserDefaults` under a per-game prefix so the two titles
    /// keep separate profiles. The `.v5` suffix forces the all-off profile onto
    /// installs that already saved a default-enabled blob under `.v4`, so the
    /// switches do not come back pre-ticked after an update.
    public static func defaultsKey(for game: Game) -> String {
        game.defaultsKeyPrefix + "controls.v5"
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
        case isEnabled, aimEnabled, radiusValue, aimbotRadiusValue, radiusPolicy,
             headshotValue, headshotPolicy, aimTarget, aimFovMode,
             aimbotType, silentAim, headRate, bodyRate, hitChance, aimDistance, drawFov,
             ignoreKnocked, antiBan,
             fastReloadPercent, fastFireLevel,
             espColor, espThickness, espBoxScalePercent, espBoxOffsetY,
             masterEsp, lineEsp, boxEsp, boxType, nameEsp, distanceEsp,
             healthEsp, healthType, skeletonEsp, tracerEsp, drawEnemyCount, textSize,
             espBounding,
             streamProof,
             noRecoil, ghostMode, speedHack, camXa, camXaFloat, buffDamage, fastParachute,
             esp360Arrows, lineTarget, silentAimTarget, sniperScope,
             fovColor, lineTracerColor, box2dColor, skeletonColor, espPalette,
             rainbow, allRainbow, resetAllColors
    }

    /// Profiles written by an older build decode field by field rather than
    /// failing outright when a panel field is absent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeatureControls()

        isEnabled         = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        aimEnabled        = try c.decodeIfPresent(Bool.self, forKey: .aimEnabled) ?? d.aimEnabled
        radiusValue       = try c.decodeIfPresent(Double.self, forKey: .radiusValue) ?? d.radiusValue
        aimbotRadiusValue = try c.decodeIfPresent(Double.self, forKey: .aimbotRadiusValue) ?? d.aimbotRadiusValue
        radiusPolicy      = try c.decodeIfPresent(ControlPolicy.self, forKey: .radiusPolicy) ?? d.radiusPolicy
        headshotValue     = try c.decodeIfPresent(Bool.self, forKey: .headshotValue) ?? d.headshotValue
        headshotPolicy    = try c.decodeIfPresent(ControlPolicy.self, forKey: .headshotPolicy) ?? d.headshotPolicy
        aimTarget         = try c.decodeIfPresent(String.self, forKey: .aimTarget) ?? d.aimTarget
        aimFovMode        = try c.decodeIfPresent(String.self, forKey: .aimFovMode) ?? d.aimFovMode

        aimbotType        = try c.decodeIfPresent(String.self, forKey: .aimbotType) ?? d.aimbotType
        silentAim         = try c.decodeIfPresent(Bool.self, forKey: .silentAim) ?? d.silentAim
        headRate          = try c.decodeIfPresent(Int.self, forKey: .headRate) ?? d.headRate
        bodyRate          = try c.decodeIfPresent(Int.self, forKey: .bodyRate) ?? d.bodyRate
        hitChance         = try c.decodeIfPresent(Int.self, forKey: .hitChance) ?? d.hitChance
        aimDistance       = try c.decodeIfPresent(Int.self, forKey: .aimDistance) ?? d.aimDistance
        drawFov           = try c.decodeIfPresent(Bool.self, forKey: .drawFov) ?? d.drawFov
        ignoreKnocked     = try c.decodeIfPresent(Bool.self, forKey: .ignoreKnocked) ?? d.ignoreKnocked
        antiBan           = try c.decodeIfPresent(Bool.self, forKey: .antiBan) ?? d.antiBan

        fastReloadPercent = try c.decodeIfPresent(Int.self, forKey: .fastReloadPercent) ?? d.fastReloadPercent
        fastFireLevel     = try c.decodeIfPresent(Int.self, forKey: .fastFireLevel) ?? d.fastFireLevel

        espColor          = try c.decodeIfPresent(Int.self, forKey: .espColor) ?? d.espColor
        espThickness      = try c.decodeIfPresent(Int.self, forKey: .espThickness) ?? d.espThickness
        espBoxScalePercent = try c.decodeIfPresent(Int.self, forKey: .espBoxScalePercent) ?? d.espBoxScalePercent
        espBoxOffsetY     = try c.decodeIfPresent(Int.self, forKey: .espBoxOffsetY) ?? d.espBoxOffsetY

        masterEsp         = try c.decodeIfPresent(Bool.self, forKey: .masterEsp) ?? d.masterEsp
        lineEsp           = try c.decodeIfPresent(Bool.self, forKey: .lineEsp) ?? d.lineEsp
        boxEsp            = try c.decodeIfPresent(Bool.self, forKey: .boxEsp) ?? d.boxEsp
        boxType           = try c.decodeIfPresent(String.self, forKey: .boxType) ?? d.boxType
        nameEsp           = try c.decodeIfPresent(Bool.self, forKey: .nameEsp) ?? d.nameEsp
        distanceEsp       = try c.decodeIfPresent(Bool.self, forKey: .distanceEsp) ?? d.distanceEsp
        healthEsp         = try c.decodeIfPresent(Bool.self, forKey: .healthEsp) ?? d.healthEsp
        healthType        = try c.decodeIfPresent(String.self, forKey: .healthType) ?? d.healthType
        skeletonEsp       = try c.decodeIfPresent(Bool.self, forKey: .skeletonEsp) ?? d.skeletonEsp
        tracerEsp         = try c.decodeIfPresent(Bool.self, forKey: .tracerEsp) ?? d.tracerEsp
        drawEnemyCount    = try c.decodeIfPresent(Bool.self, forKey: .drawEnemyCount) ?? d.drawEnemyCount
        textSize          = try c.decodeIfPresent(Int.self, forKey: .textSize) ?? d.textSize
        espBounding       = try c.decodeIfPresent(Int.self, forKey: .espBounding) ?? d.espBounding

        streamProof       = try c.decodeIfPresent(Bool.self, forKey: .streamProof) ?? d.streamProof

        noRecoil          = try c.decodeIfPresent(Bool.self, forKey: .noRecoil) ?? d.noRecoil
        ghostMode         = try c.decodeIfPresent(Bool.self, forKey: .ghostMode) ?? d.ghostMode
        speedHack         = try c.decodeIfPresent(Bool.self, forKey: .speedHack) ?? d.speedHack
        camXa             = try c.decodeIfPresent(Bool.self, forKey: .camXa) ?? d.camXa
        camXaFloat        = try c.decodeIfPresent(Double.self, forKey: .camXaFloat) ?? d.camXaFloat
        buffDamage        = try c.decodeIfPresent(Bool.self, forKey: .buffDamage) ?? d.buffDamage
        fastParachute     = try c.decodeIfPresent(Bool.self, forKey: .fastParachute) ?? d.fastParachute

        esp360Arrows      = try c.decodeIfPresent(Bool.self, forKey: .esp360Arrows) ?? d.esp360Arrows
        lineTarget        = try c.decodeIfPresent(String.self, forKey: .lineTarget) ?? d.lineTarget
        silentAimTarget   = try c.decodeIfPresent(String.self, forKey: .silentAimTarget) ?? d.silentAimTarget
        sniperScope       = try c.decodeIfPresent(Bool.self, forKey: .sniperScope) ?? d.sniperScope
        fovColor          = try c.decodeIfPresent(Bool.self, forKey: .fovColor) ?? d.fovColor
        lineTracerColor   = try c.decodeIfPresent(Bool.self, forKey: .lineTracerColor) ?? d.lineTracerColor
        box2dColor        = try c.decodeIfPresent(Bool.self, forKey: .box2dColor) ?? d.box2dColor
        skeletonColor     = try c.decodeIfPresent(Bool.self, forKey: .skeletonColor) ?? d.skeletonColor
        espPalette        = try c.decodeIfPresent(String.self, forKey: .espPalette) ?? d.espPalette
        rainbow           = try c.decodeIfPresent(Bool.self, forKey: .rainbow) ?? d.rainbow
        allRainbow        = try c.decodeIfPresent(Bool.self, forKey: .allRainbow) ?? d.allRainbow
        resetAllColors    = try c.decodeIfPresent(Bool.self, forKey: .resetAllColors) ?? d.resetAllColors
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
            "espBoxScalePercent": espBoxScalePercent,
            "espBoxOffsetY": espBoxOffsetY,

            "aimbotType": aimbotType,
            "silentAim": silentAim,
            "headRate": headRate,
            "bodyRate": bodyRate,
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

            "noRecoil": noRecoil,
            "ghostMode": ghostMode,
            "speedHack": speedHack,
            "camXa": camXa,
            "camXaFloat": camXaFloat,
            "buffDamage": buffDamage,
            "fastParachute": fastParachute,

            "esp360Arrows": esp360Arrows,
            "lineTarget": lineTarget,
            "silentAimTarget": silentAimTarget,
            "sniperScope": sniperScope,
            "fovColor": fovColor,
            "lineTracerColor": lineTracerColor,
            "box2dColor": box2dColor,
            "skeletonColor": skeletonColor,
            "espPalette": espPalette,
            "rainbow": rainbow,
            "allRainbow": allRainbow,
            "resetAllColors": resetAllColors,
        ]
    }

    // MARK: - runtime configuration document
    //
    // `localConfig.json` is read back by the injected IFix runtime, not by this
    // app. The keys it actually parses are the cheat's own spelling — recovered
    // verbatim from the patch's `__cstring`:
    //
    //     EspMaster EspBox EspLine EspName EspDistance EspHealth EspSkeleton
    //     EspTracer AimSystemEnabled AimEnabled AimTarget HeadRate FovSize
    //     EspFov BodyRate
    //
    // The panel writes camelCase (`masterEsp`, `boxEsp`, `aimTarget`, …), which
    // the runtime does not match, so every switch stayed at the cheat's default.
    // This method is the single place the panel spelling is translated to the
    // runtime spelling.
    //
    // `EspBoxScale` / `EspBoxOffset` are keys the shipped patch has no literal
    // for: box geometry is baked into the runtime's draw call, so it ignores
    // them, exactly as it ignores the `server_*` block. `HeadRate` / `BodyRate`
    // *are* read: the patched `SceneEditBoxSelectTool.OnGUI` parses them next to
    // the cheat's own `HeadshotRate` (which the patch keeps as a fallback when
    // `HeadRate` is absent) and packs the pair into the silent-aim roll (head in
    // aux bits 8..15, body in 16..23), so the head-versus-body split is live the
    // moment silent aim is on. Nothing else in the document moves.
    //
    // Only the switches the panel exposes are emitted here; the keys it does not
    // expose (`NoRecoil`, `SpeedHack`, the guest-reset block, `server_*`, …) are
    // preserved from the shipped document by `PatchPayload.configuration`.

    /// The aim / ESP switches from the panel, keyed exactly as the injected
    /// runtime reads them.
    ///
    /// `antiBan` and `streamProof` are deliberately not emitted here: neither
    /// has a literal in the recovered runtime vocabulary. `antiBan` instead
    /// drives the local trace sweep + payload timestamp masking + session
    /// re-stamp (`AntiBanRoutine`) at the front of every inject; `streamProof`
    /// rides along in the serialized payload only.
    public func runtimeConfigDocument() -> [String: Any] {
        [
            // visual ESP
            "EspMaster":        masterEsp,
            "EspBox":           boxEsp,
            "EspLine":          lineEsp,
            "EspName":          nameEsp,
            "EspDistance":      distanceEsp,
            "EspHealth":        healthEsp,
            "EspSkeleton":      skeletonEsp,
            "EspTracer":        tracerEsp,

            // enemy-box geometry
            "EspBoxScale":      Double(espBoxScalePercent) / 100.0,
            "EspBoxOffset":     espBoxOffsetY,

            // aim
            "AimSystemEnabled": isEnabled,
            "AimEnabled":       aimEnabled || silentAim,
            "SilentAim":        silentAim,
            // Legit aim *is* the aim assist here: the panel's aim master. Emitted
            // under both spellings so a runtime that reads either one sees it.
            "LegitAimbot":      isEnabled,
            // Silent aim runs on the runtime's mixed-roll target (ordinal `0`):
            // that is the only state whose head/body split the roll drives.
            // With silent aim off the panel's chosen bone ordinal is emitted.
            "AimTarget":        silentAim ? 0 : aimTargetOrdinal,
            // The runtime's single head/body rate is split in two by the patch.
            // `HeadRate` (aux bits 8..15) is the head share, `BodyRate`
            // (aux bits 16..23) the body share, and `get_LastAimingInfoFromWeapon`
            // rolls  head  iff  roll * (Head + Body) < Head * 100,
            // with `roll = |instanceID| % 100`.
            "HeadRate":         headRate,
            "BodyRate":         bodyRate,
            "FovSize":          Int(aimbotRadiusValue.rounded()),
            "EspFov":           drawFov,

            // aim FOV circle + sniper scope
            "AimFovCircle":     drawFov,
            "AimFovRadius":     Int(aimbotRadiusValue.rounded()),
            "SniperScope":      sniperScope,

            // silent-aim target — exactly one of the three is on
            "AimTargetMixed":   silentAimTarget == "mixed",
            "AimTargetHead":    silentAimTarget == "head",
            "AimTargetBody":    silentAimTarget == "body",

            // headshot rate, mirroring the head/body split the sliders drive
            "HeadshotRate100":  headRate >= 100,
            "HeadshotRate75":   headRate == 75,
            "HeadshotRate50":   headRate == 50,
            "HeadshotRate25":   headRate == 25,
            "HeadshotRate0":    headRate <= 0,

            // ESP extras
            "Esp360Arrows":        esp360Arrows,
            "EnemyCount":          drawEnemyCount,
            "LineTargetTop":       lineTarget == "top",
            "LineTargetBottom":    lineTarget == "bottom",
            "LineTargetCrosshair": lineTarget == "crosshair",

            // colour targets + named palette + chroma
            "FovColor":         fovColor,
            "LineTracerColor":  lineTracerColor,
            "Box2DColor":       box2dColor,
            "SkeletonColor":    skeletonColor,
            "ColorDefault":     espPalette == "default",
            "ColorRed":         espPalette == "red",
            "ColorGreen":       espPalette == "green",
            "ColorBlue":        espPalette == "blue",
            "ColorYellow":      espPalette == "yellow",
            "ColorCyan":        espPalette == "cyan",
            "ColorPink":        espPalette == "pink",
            "ColorOrange":      espPalette == "orange",
            "ColorPurple":      espPalette == "purple",
            "ColorWhite":       espPalette == "white",
            "Rainbow":          rainbow,
            "AllRainbow":       allRainbow,
            "ResetAllColors":   resetAllColors,
        ]
    }

    /// The runtime reads `AimTarget` as an ordinal, not a word. Recovered from
    /// the patch: the status line is built from whole-string branches,
    /// `Aim system target: HEAD` / `NECK`, and the config writer emits the
    /// literals `"AimTarget":1` and `"AimTarget":2`. The patch's own menu also
    /// carries a `Target: BODY` state, which takes the next slot, so:
    /// `1` = head, `2` = neck, `3` = body. `FeatureControls` keeps the word for
    /// the panel.
    public var aimTargetOrdinal: Int {
        switch aimTarget {
        case "neck": return 2
        case "body": return 3
        default:     return 1
        }
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
        "aim_target":   ["head", "neck", "body"],
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
