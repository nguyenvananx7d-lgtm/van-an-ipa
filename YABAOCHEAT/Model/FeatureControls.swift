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
    /// Remove the staged patch and config from the game container once the
    /// target has read them. App-side only — the runtime never sees this key.
    /// Worth leaving on when a ban arrives with every feature switched off: at
    /// that point the payload's existence is the evidence, not the assist.
    public var consumePayload: Bool

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
    // MARK: panel - extra ESP / aim tuning
    /// Furthest enemy drawn by the ESP, in metres. Key `EspMaxDistance`.
    public var espMaxDistance: Int
    /// When off the ESP draws through walls (`IsVisible` filter disabled).
    public var espVisibleOnly: Bool
    /// Filled box behind the corner frame. Key `EspBoxFill`.
    public var espBoxFill: Bool
    public var espBoxFillAlpha: Double
    /// Marker over the head. Key `EspHeadDot`.
    public var espHeadDot: Bool
    /// Keep drawing knocked enemies. Key `EspShowDowned`.
    public var espShowDowned: Bool
    /// Multiplier for the ESP text size. Key `EspTextScale`.
    public var espTextScale: Double
    /// Vertical aim offset (0.8 = chest, ~1.5 = head). Key `AimHeight`.
    public var aimHeight: Double
    /// Aim smoothing factor, lower is snappier. Key `AimSmooth`.
    public var aimSmooth: Double
    /// Aim only at enemies the game marks visible. Key `AimVisibleOnly`.
    public var aimVisibleOnly: Bool
    /// Delay between acquiring a target and the assist taking over, in ms.
    /// Key `AimReactionMs`. Was hardcoded at 180; a field because a constant
    /// reaction time is one of the statistics a server can score.
    public var aimReactionMs: Int
    /// How far ahead of the target's measured velocity the assist leads, in ms.
    /// Key `AimLeadMs`. Was hardcoded at 100.
    public var aimLeadMs: Int

    // MARK: panel — aim behaviour (all read by the in-game patch)
    /// Error cone, in degrees, the assist stops correcting inside. Key
    /// `AimDeadzone`; `0` disables the dead zone.
    public var aimDeadzone: Double
    /// Keep the incumbent target inside a widened cone instead of swapping to
    /// a marginally better one. Key `AimLatch`.
    public var aimLatch: Bool
    /// Ramp the correction in over 0.35 s when a lock starts. Key `AimRamp`.
    public var aimRamp: Bool
    /// Master for the humanisation layer (jitter, overshoot, breaks).
    /// Key `AimHumanize`.
    public var aimHumanize: Bool
    /// Assist only while a finger is on the screen. Key `AimTouchGate`.
    public var aimTouchGate: Bool
    /// Extra latch width, 0…1. Key `AimStickiness`.
    public var aimStickiness: Double
    /// Score bonus the current target keeps, 0…1. Key `AimSwitchBias`.
    public var aimSwitchBias: Double
    /// Angular-speed cap per frame, in degrees. Key `AimMaxTurn`.
    public var aimMaxTurn: Int
    /// Gain applied to the measured velocity lead, 0…2. Key `AimTrackGain`.
    public var aimTrackGain: Double
    /// Deliberate overshoot on acquisition, in degrees. Key `AimOvershootDeg`.
    public var aimOvershootDeg: Double
    /// Forced micro-break window on long tracks. Keys `AimBreakMinMs` /
    /// `AimBreakMaxMs`.
    public var aimBreakMinMs: Int
    public var aimBreakMaxMs: Int
    /// Write-free pause after the locked target dies. Key `AimKillGuardMs`.
    public var aimKillGuardMs: Int
    /// Hold the target continuously instead of the humanised release pattern.
    /// Key `AimLock`; it now means stealth tier 0, so it forces the engagement
    /// envelope open without touching the aim maths.
    public var aimLock: Bool
    /// Ring + centre pip drawn at the crosshair while the assist is armed.
    /// Key `AimCrosshair`.
    public var aimCrosshair: Bool
    /// Behavioural envelope the patch folds its limits into. Key `AimStealth`.
    /// `0` lock · `1` low · `2` balanced · `3` quiet. Replaces the old cliff
    /// where turning the assist up meant switching every limit off at once.
    public var aimStealth: Int
    /// Which point the assist solves its rotation from. Key `AimFrom`.
    /// `camera` is the reticle you see; `eye` is the local player's head, which
    /// is where the shot actually leaves in third person. The gap between them
    /// grows with range, so this is the difference between "on target" and
    /// "on target and hitting".
    public var aimFrom: String
    /// Multiplier on tracking gain, so the lock can be sharpened or softened
    /// without moving the stealth envelope. Key `AimHoldGain`.
    public var aimHoldGain: Double
    /// Minimum spacing between `SetAimRotation` commits, in ms. That call is the
    /// only aim write the game counts, so its rate is what a replay can score.
    /// Key `AimCommitMs`.
    public var aimCommitMs: Int

    // MARK: panel — in-game anti-ban budget
    /// Legacy. The patch used to ration itself by skipping writes on a duty
    /// cycle; that made the reticle lose the target without hiding the pattern,
    /// so it is gone and these two no longer reach the runtime. Kept in the
    /// model so a saved profile from an older build still decodes.
    public var antiBanBudget: Bool
    /// Legacy — see `antiBanBudget`.
    public var antiBanDutyCycle: Int
    /// Longest continuous lock before release, in ms. Key `AntibanMaxEngageMs`.
    public var antiBanMaxEngageMs: Int
    /// Cooldown after a release, in ms. Key `AntibanCooldownMs`.
    public var antiBanCooldownMs: Int

    // MARK: panel — ESP detail
    /// Smooth each box against its own previous frame. Key `EspSmoothBox`.
    public var espSmoothBox: Bool
    /// Fade elements as they approach the distance limit. Key `EspFadeFar`.
    public var espFadeFar: Bool
    /// Draw bearings on the 360° ring for enemies off screen.
    /// Key `EspOffscreenArrows`.
    public var espOffscreenArrows: Bool
    /// Print HP under the distance line (≤120 m). Key `EspHealthText`.
    public var espHealthText: Bool
    /// Halo behind boxes and lines. Key `EspGlow`.
    public var espGlow: Bool
    /// Dark plate behind the name tag. Key `EspNameChip`.
    public var espNameChip: Bool
    /// Rings on the skeleton joints. Key `EspSkeletonJoints`.
    public var espSkeletonJoints: Bool
    /// Extra brackets on the enemy the assist is locked onto.
    /// Key `EspTargetHighlight`.
    public var espTargetHighlight: Bool

    /// True when at least one thing the injected patch provides is switched on.
    ///
    /// The app refuses to stage the payload when this is false: loading an IFix
    /// patch to draw nothing still rewrites a game method and leaves a host
    /// object, and that footprint is exactly what an "I enabled nothing" session
    /// must not have. Visual master and the three aim gates are the switch set
    /// that decides it.
    public var hasAnyPatchFeature: Bool {
        masterEsp || isEnabled || aimEnabled || silentAim
    }
    /// Ship defaults are visual-only. The aim assist starts **off**: a ban that
    /// arrives with every feature switched off cannot be an aim score, and that
    /// is the report this build answers. ESP stays on with conservative limits,
    /// and if the assist is switched on its numbers are body-first (30% head
    /// roll, 95 px FOV, 120 m, 260 ms reaction, 0.42 smoothing) rather than the
    /// old 85% / 150 px / 200 m / 180 ms machine signature. Every value stays
    /// adjustable in the Aimbot tab.
    public init(
        isEnabled: Bool = false,
        aimEnabled: Bool = false,
        radiusValue: Double = 0,
        aimbotRadiusValue: Double = 95.0,
        radiusPolicy: ControlPolicy = .value,
        headshotValue: Bool = false,
        headshotPolicy: ControlPolicy = .value,
        aimTarget: String = "body",
        aimFovMode: String = "strict",
        aimbotType: String = "aimbot",
        silentAim: Bool = false,
        headRate: Int = 55,
        bodyRate: Int = 45,
        hitChance: Int = 50,
        aimDistance: Int = 120,
        drawFov: Bool = true,
        ignoreKnocked: Bool = true,
        antiBan: Bool = true,
        consumePayload: Bool = true,
        fastReloadPercent: Int = 0,
        fastFireLevel: Int = 0,
        espColor: Int = 0xFF00FF00,
        espThickness: Int = 1,
        espBoxScalePercent: Int = 116,
        espBoxOffsetY: Int = 8,
        masterEsp: Bool = true,
        lineEsp: Bool = true,
        boxEsp: Bool = true,
        boxType: String = "corner",
        nameEsp: Bool = true,
        distanceEsp: Bool = true,
        healthEsp: Bool = true,
        healthType: String = "right",
        skeletonEsp: Bool = true,
        tracerEsp: Bool = true,
        drawEnemyCount: Bool = true,
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
        esp360Arrows: Bool = true,
        lineTarget: String = "bottom",
        silentAimTarget: String = "mixed",
        sniperScope: Bool = false,
        fovColor: Bool = false,
        lineTracerColor: Bool = false,
        box2dColor: Bool = false,
        skeletonColor: Bool = false,
        espPalette: String = "emerald",
        rainbow: Bool = false,
        allRainbow: Bool = false,
        resetAllColors: Bool = false,
        espMaxDistance: Int = 250,
        espVisibleOnly: Bool = true,
        espBoxFill: Bool = true,
        espBoxFillAlpha: Double = 0.16,
        espHeadDot: Bool = true,
        espShowDowned: Bool = true,
        espTextScale: Double = 1.05,
        aimHeight: Double = 0.8,
        aimSmooth: Double = 0.42,
        aimVisibleOnly: Bool = true,
        aimReactionMs: Int = 260,
        aimLeadMs: Int = 60,
        aimDeadzone: Double = 0.20,
        aimLatch: Bool = true,
        aimRamp: Bool = true,
        aimHumanize: Bool = true,
        aimTouchGate: Bool = true,
        aimStickiness: Double = 0.45,
        aimSwitchBias: Double = 0.30,
        aimMaxTurn: Int = 110,
        aimTrackGain: Double = 0.70,
        aimOvershootDeg: Double = 1.8,
        aimBreakMinMs: Int = 140,
        aimBreakMaxMs: Int = 420,
        aimKillGuardMs: Int = 900,
        aimLock: Bool = false,
        aimCrosshair: Bool = true,
        aimStealth: Int = 2,
        aimFrom: String = "camera",
        aimHoldGain: Double = 1.0,
        aimCommitMs: Int = 50,
        antiBanBudget: Bool = true,
        antiBanDutyCycle: Int = 45,
        antiBanMaxEngageMs: Int = 2400,
        antiBanCooldownMs: Int = 900,
        espSmoothBox: Bool = true,
        espFadeFar: Bool = true,
        espOffscreenArrows: Bool = true,
        espHealthText: Bool = true,
        espGlow: Bool = true,
        espNameChip: Bool = true,
        espSkeletonJoints: Bool = true,
        espTargetHighlight: Bool = true
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
        self.consumePayload = consumePayload
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
        self.espMaxDistance = espMaxDistance
        self.espVisibleOnly = espVisibleOnly
        self.espBoxFill = espBoxFill
        self.espBoxFillAlpha = espBoxFillAlpha
        self.espHeadDot = espHeadDot
        self.espShowDowned = espShowDowned
        self.espTextScale = espTextScale
        self.aimHeight = aimHeight
        self.aimSmooth = aimSmooth
        self.aimVisibleOnly = aimVisibleOnly
        self.aimReactionMs = aimReactionMs
        self.aimLeadMs = aimLeadMs
        self.aimDeadzone = aimDeadzone
        self.aimLatch = aimLatch
        self.aimRamp = aimRamp
        self.aimHumanize = aimHumanize
        self.aimTouchGate = aimTouchGate
        self.aimStickiness = aimStickiness
        self.aimSwitchBias = aimSwitchBias
        self.aimMaxTurn = aimMaxTurn
        self.aimTrackGain = aimTrackGain
        self.aimOvershootDeg = aimOvershootDeg
        self.aimBreakMinMs = aimBreakMinMs
        self.aimBreakMaxMs = aimBreakMaxMs
        self.aimKillGuardMs = aimKillGuardMs
        self.aimLock = aimLock
        self.aimCrosshair = aimCrosshair
        self.aimStealth = aimStealth
        self.aimFrom = aimFrom
        self.aimHoldGain = aimHoldGain
        self.aimCommitMs = aimCommitMs
        self.antiBanBudget = antiBanBudget
        self.antiBanDutyCycle = antiBanDutyCycle
        self.antiBanMaxEngageMs = antiBanMaxEngageMs
        self.antiBanCooldownMs = antiBanCooldownMs
        self.espSmoothBox = espSmoothBox
        self.espFadeFar = espFadeFar
        self.espOffscreenArrows = espOffscreenArrows
        self.espHealthText = espHealthText
        self.espGlow = espGlow
        self.espNameChip = espNameChip
        self.espSkeletonJoints = espSkeletonJoints
        self.espTargetHighlight = espTargetHighlight
    }

    // MARK: - persistence

    /// Controls live in `UserDefaults` under a per-game prefix so the two titles
    /// keep separate profiles. The `.v6` suffix forces the armed profile onto
    /// installs that already saved an all-off profile under `.v5`.
    public static func defaultsKey(for game: Game) -> String {
        // `.v8` again abandons the saved profile on purpose: an install built
        // under `.v7` still had the aim assist armed at boot. A ban that arrives
        // with nothing switched on is not an aim score, so the safe default is
        // visual ESP only, with the assist off until the user turns it on.
        game.defaultsKeyPrefix + "controls.v8"
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
             ignoreKnocked, antiBan, consumePayload,
             fastReloadPercent, fastFireLevel,
             espColor, espThickness, espBoxScalePercent, espBoxOffsetY,
             masterEsp, lineEsp, boxEsp, boxType, nameEsp, distanceEsp,
             healthEsp, healthType, skeletonEsp, tracerEsp, drawEnemyCount, textSize,
             espBounding,
             streamProof,
             noRecoil, ghostMode, speedHack, camXa, camXaFloat, buffDamage, fastParachute,
             esp360Arrows, lineTarget, silentAimTarget, sniperScope,
             fovColor, lineTracerColor, box2dColor, skeletonColor, espPalette,
             rainbow, allRainbow, resetAllColors,
             espMaxDistance, espVisibleOnly, espBoxFill, espBoxFillAlpha,
             espHeadDot, espShowDowned, espTextScale, aimHeight, aimSmooth,
             aimVisibleOnly, aimReactionMs, aimLeadMs,
             aimDeadzone, aimLatch, aimRamp, aimHumanize, aimTouchGate,
             aimStickiness, aimSwitchBias, aimMaxTurn, aimTrackGain,
             aimOvershootDeg, aimBreakMinMs, aimBreakMaxMs, aimKillGuardMs,
             aimLock, aimCrosshair, aimStealth, aimFrom, aimHoldGain, aimCommitMs,
             antiBanBudget, antiBanDutyCycle, antiBanMaxEngageMs, antiBanCooldownMs,
             espSmoothBox, espFadeFar, espOffscreenArrows, espHealthText,
             espGlow, espNameChip, espSkeletonJoints, espTargetHighlight
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
        consumePayload    = try c.decodeIfPresent(Bool.self, forKey: .consumePayload) ?? d.consumePayload

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
        espMaxDistance    = try c.decodeIfPresent(Int.self, forKey: .espMaxDistance) ?? d.espMaxDistance
        espVisibleOnly    = try c.decodeIfPresent(Bool.self, forKey: .espVisibleOnly) ?? d.espVisibleOnly
        espBoxFill        = try c.decodeIfPresent(Bool.self, forKey: .espBoxFill) ?? d.espBoxFill
        espBoxFillAlpha   = try c.decodeIfPresent(Double.self, forKey: .espBoxFillAlpha) ?? d.espBoxFillAlpha
        espHeadDot        = try c.decodeIfPresent(Bool.self, forKey: .espHeadDot) ?? d.espHeadDot
        espShowDowned     = try c.decodeIfPresent(Bool.self, forKey: .espShowDowned) ?? d.espShowDowned
        espTextScale      = try c.decodeIfPresent(Double.self, forKey: .espTextScale) ?? d.espTextScale
        aimHeight         = try c.decodeIfPresent(Double.self, forKey: .aimHeight) ?? d.aimHeight
        aimSmooth         = try c.decodeIfPresent(Double.self, forKey: .aimSmooth) ?? d.aimSmooth
        aimVisibleOnly    = try c.decodeIfPresent(Bool.self, forKey: .aimVisibleOnly) ?? d.aimVisibleOnly
        aimReactionMs     = try c.decodeIfPresent(Int.self, forKey: .aimReactionMs) ?? d.aimReactionMs
        aimLeadMs         = try c.decodeIfPresent(Int.self, forKey: .aimLeadMs) ?? d.aimLeadMs

        aimDeadzone       = try c.decodeIfPresent(Double.self, forKey: .aimDeadzone) ?? d.aimDeadzone
        aimLatch          = try c.decodeIfPresent(Bool.self, forKey: .aimLatch) ?? d.aimLatch
        aimRamp           = try c.decodeIfPresent(Bool.self, forKey: .aimRamp) ?? d.aimRamp
        aimHumanize       = try c.decodeIfPresent(Bool.self, forKey: .aimHumanize) ?? d.aimHumanize
        aimTouchGate      = try c.decodeIfPresent(Bool.self, forKey: .aimTouchGate) ?? d.aimTouchGate
        aimStickiness     = try c.decodeIfPresent(Double.self, forKey: .aimStickiness) ?? d.aimStickiness
        aimSwitchBias     = try c.decodeIfPresent(Double.self, forKey: .aimSwitchBias) ?? d.aimSwitchBias
        aimMaxTurn        = try c.decodeIfPresent(Int.self, forKey: .aimMaxTurn) ?? d.aimMaxTurn
        aimTrackGain      = try c.decodeIfPresent(Double.self, forKey: .aimTrackGain) ?? d.aimTrackGain
        aimOvershootDeg   = try c.decodeIfPresent(Double.self, forKey: .aimOvershootDeg) ?? d.aimOvershootDeg
        aimBreakMinMs     = try c.decodeIfPresent(Int.self, forKey: .aimBreakMinMs) ?? d.aimBreakMinMs
        aimBreakMaxMs     = try c.decodeIfPresent(Int.self, forKey: .aimBreakMaxMs) ?? d.aimBreakMaxMs
        aimKillGuardMs    = try c.decodeIfPresent(Int.self, forKey: .aimKillGuardMs) ?? d.aimKillGuardMs
        aimLock           = try c.decodeIfPresent(Bool.self, forKey: .aimLock) ?? d.aimLock
        aimCrosshair      = try c.decodeIfPresent(Bool.self, forKey: .aimCrosshair) ?? d.aimCrosshair
        aimStealth        = try c.decodeIfPresent(Int.self, forKey: .aimStealth) ?? d.aimStealth
        aimFrom           = try c.decodeIfPresent(String.self, forKey: .aimFrom) ?? d.aimFrom
        aimHoldGain       = try c.decodeIfPresent(Double.self, forKey: .aimHoldGain) ?? d.aimHoldGain
        aimCommitMs       = try c.decodeIfPresent(Int.self, forKey: .aimCommitMs) ?? d.aimCommitMs

        antiBanBudget     = try c.decodeIfPresent(Bool.self, forKey: .antiBanBudget) ?? d.antiBanBudget
        antiBanDutyCycle  = try c.decodeIfPresent(Int.self, forKey: .antiBanDutyCycle) ?? d.antiBanDutyCycle
        antiBanMaxEngageMs = try c.decodeIfPresent(Int.self, forKey: .antiBanMaxEngageMs) ?? d.antiBanMaxEngageMs
        antiBanCooldownMs = try c.decodeIfPresent(Int.self, forKey: .antiBanCooldownMs) ?? d.antiBanCooldownMs

        espSmoothBox      = try c.decodeIfPresent(Bool.self, forKey: .espSmoothBox) ?? d.espSmoothBox
        espFadeFar        = try c.decodeIfPresent(Bool.self, forKey: .espFadeFar) ?? d.espFadeFar
        espOffscreenArrows = try c.decodeIfPresent(Bool.self, forKey: .espOffscreenArrows) ?? d.espOffscreenArrows
        espHealthText     = try c.decodeIfPresent(Bool.self, forKey: .espHealthText) ?? d.espHealthText
        espGlow           = try c.decodeIfPresent(Bool.self, forKey: .espGlow) ?? d.espGlow
        espNameChip       = try c.decodeIfPresent(Bool.self, forKey: .espNameChip) ?? d.espNameChip
        espSkeletonJoints = try c.decodeIfPresent(Bool.self, forKey: .espSkeletonJoints) ?? d.espSkeletonJoints
        espTargetHighlight = try c.decodeIfPresent(Bool.self, forKey: .espTargetHighlight) ?? d.espTargetHighlight
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
            "espMaxDistance": espMaxDistance,
            "espVisibleOnly": espVisibleOnly,
            "espBoxFill": espBoxFill,
            "espBoxFillAlpha": espBoxFillAlpha,
            "espHeadDot": espHeadDot,
            "espShowDowned": espShowDowned,
            "espTextScale": espTextScale,
            "aimHeight": aimHeight,
            "aimSmooth": aimSmooth,
            "aimVisibleOnly": aimVisibleOnly,
            "aimReactionMs": aimReactionMs,
            "aimLeadMs": aimLeadMs,
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
    /// `antiBan` is emitted as `AntiBan` so the rebuilt patch can gate its
    /// behavioural humanisation (post-kill pause, track micro-breaks, acquire
    /// overshoot) on the same switch the panel shows. The local trace sweep +
    /// payload timestamp masking + session re-stamp still run at the front of
    /// every inject via `AntiBanRoutine`; `streamProof` rides along in the
    /// serialized payload only.
    /// Fold the stealth tier into the individual limits it owns.
    ///
    /// `Logic.Aim.cs` applies the same ladder in the patch, but the panel emits
    /// every key it holds and an explicit key wins over the tier there — so a
    /// tier change would appear to do nothing. Applying it here as a preset
    /// keeps the sliders showing the numbers the tier actually means.
    ///
    /// These seven values must stay in step with `ApplyStealthTier()` in
    /// `ESPDESGIN/src/Logic.Aim.cs`.
    public mutating func applyStealthTier() {
        if aimLock { aimStealth = 0 }
        switch aimStealth {
        case 0:
            antiBanMaxEngageMs = 8000; antiBanCooldownMs = 0
            aimHumanize = false; aimDeadzone = 0; aimOvershootDeg = 0
            aimMaxTurn = 720; aimCommitMs = 20; aimHoldGain = 1.35
        case 1:
            antiBanMaxEngageMs = 4000; antiBanCooldownMs = 500
            aimHumanize = true; aimDeadzone = 0.14; aimOvershootDeg = 1.1
            aimMaxTurn = 240; aimCommitMs = 40; aimHoldGain = 1.15
        case 3:
            antiBanMaxEngageMs = 1400; antiBanCooldownMs = 1400
            aimHumanize = true; aimDeadzone = 0.30; aimOvershootDeg = 2.6
            aimMaxTurn = 90; aimCommitMs = 120; aimHoldGain = 0.85
        default:
            antiBanMaxEngageMs = 2400; antiBanCooldownMs = 900
            aimHumanize = true; aimDeadzone = 0.20; aimOvershootDeg = 1.8
            aimMaxTurn = 110; aimCommitMs = 50; aimHoldGain = 1.0
        }
    }

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
            // extra ESP / aim tuning (read by the rebuilt patch)
            "EspMaxDistance":   espMaxDistance,
            "EspVisibleOnly":   espVisibleOnly,
            "EspBoxFill":       espBoxFill,
            "EspBoxFillAlpha":  espBoxFillAlpha,
            "EspHeadDot":       espHeadDot,
            "EspShowDowned":    espShowDowned,
            "IgnoreKnocked":    ignoreKnocked,
            "EspTextScale":     espTextScale,
            "AimHeight":        aimHeight,
            "AimSmooth":        aimSmooth,
            "AimMaxDistance":   aimDistance,
            "AimDistance":      aimDistance,
            "AimVisibleOnly":   aimVisibleOnly,
            // box / bar style + named palette, read by the rebuilt patch
            "BoxType":          boxType,
            "HealthType":       healthType,
            "EspPalette":       espPalette,
            // sticky-assist tuning: bone, reaction, prediction, touch gate.
            // These are the exact keys the in-game patch parses, so the panel
            // can tune the feel of the assist instead of leaving it at the
            // values the shipped document happens to carry.
            "AimBone":          silentAim ? "mixed"
                                  : (aimTarget == "body" ? "chest" : aimTarget),
            "AimReactionMs":    aimReactionMs,
            "AimLeadMs":        aimLeadMs,
            "AimTouchGate":     aimTouchGate,
            // aim feel + humanisation, all read by the in-game patch
            "HitChance":        hitChance,
            "AimDeadzone":      aimDeadzone,
            "AimLatch":         aimLatch,
            "AimRamp":          aimRamp,
            "AimHumanize":      aimHumanize,
            "AimStickiness":    aimStickiness,
            "AimSwitchBias":    aimSwitchBias,
            "AimMaxTurn":       aimMaxTurn,
            "AimTrackGain":     aimTrackGain,
            "AimOvershootDeg":  aimOvershootDeg,
            "AimBreakMinMs":    aimBreakMinMs,
            "AimBreakMaxMs":    aimBreakMaxMs,
            "AimKillGuardMs":   aimKillGuardMs,
            "AimLock":          aimLock,
            "AimCrosshair":     aimCrosshair,
            // in-game anti-ban envelope. `AntibanBudget` / `AntibanDutyCycle` are
            // no longer emitted: the patch dropped per-frame write skipping, and a
            // key the runtime never reads is just another word for a scanner to
            // find in the document.
            "AimStealth":          aimStealth,
            "AimFrom":             aimFrom == "eye" ? 1 : 0,
            "AimHoldGain":         aimHoldGain,
            "AimCommitMs":         aimCommitMs,
            "AntibanMaxEngageMs":  antiBanMaxEngageMs,
            "AntibanCooldownMs":   antiBanCooldownMs,
            // ESP detail
            "EspSmoothBox":       espSmoothBox,
            "EspFadeFar":         espFadeFar,
            "EspOffscreenArrows": espOffscreenArrows,
            "EspHealthText":      espHealthText,
            "EspGlow":            espGlow,
            "EspNameChip":        espNameChip,
            "EspSkeletonJoints":  espSkeletonJoints,
            "EspTargetHighlight": espTargetHighlight,
            "AntiBan":          antiBan,
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
