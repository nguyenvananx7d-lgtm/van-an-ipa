import SwiftUI

/// Aimbot tab. Only the switches the injected runtime actually reads are shown
/// here, so every row does something:
///
/// - legit aim → `LegitAimbot` (the aim assist / master; also emits
///   `AimSystemEnabled` so a runtime that reads the older spelling still arms)
/// - silent aim → `SilentAim`; forces `AimTarget` to the mixed-roll mode (`0`)
///   and arms `AimEnabled`
/// - silent aim target → `AimTargetMixed` / `AimTargetHead` / `AimTargetBody`
/// - sniper scope → `SniperScope`
/// - head / body rate → `HeadRate` / `BodyRate`, the silent-aim bone split
///   (`headRate / (headRate + bodyRate)` is the head probability)
/// - bone → `AimTarget` (head `1` / neck `2` / body `3`), used when silent aim
///   is off
/// - draw FOV → `EspFov`
/// - field of view → `FovSize`
///
/// The head / body rate pair only shows while silent aim is on: it tunes a mode
/// the runtime does not run otherwise, so a hidden slider that does nothing
/// would be a lie.
struct AimbotView: View {
    @EnvironmentObject var menu: MenuStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionGroup(title: String(localized: "section_aimbot_main"), symbol: "scope") {
                ToggleRow(label: String(localized: "legit_aim"), isOn: menu.feature(\.isEnabled))
                ToggleRow(label: String(localized: "silent_aim"), isOn: menu.feature(\.silentAim))
                if menu.controls.silentAim {
                    SegmentRow(
                        label: String(localized: "silent_aim_target"),
                        selection: menu.feature(\.silentAimTarget),
                        options: [
                            SegmentOption(value: "mixed", title: String(localized: "target_mixed")),
                            SegmentOption(value: "head", title: String(localized: "target_head")),
                            SegmentOption(value: "body", title: String(localized: "target_body")),
                        ]
                    )
                    SliderRow(
                        label: String(localized: "head_rate"),
                        value: menu.feature(\.headRate),
                        unit: "%"
                    )
                    SliderRow(
                        label: String(localized: "body_rate"),
                        value: menu.feature(\.bodyRate),
                        unit: "%"
                    )
                }
            }
            SectionGroup(title: String(localized: "section_aimbot_type"), symbol: "figure.stand") {
                SegmentRow(
                    label: String(localized: "bone"),
                    selection: menu.feature(\.aimTarget),
                    options: [
                        SegmentOption(value: "head", title: String(localized: "bone_head")),
                        SegmentOption(value: "neck", title: String(localized: "bone_neck")),
                        SegmentOption(value: "body", title: String(localized: "bone_body")),
                    ]
                )
            }
            SectionGroup(title: String(localized: "section_aimbot_settings"), symbol: "slider.horizontal.3") {
                ToggleRow(label: String(localized: "draw_fov"), isOn: menu.feature(\.drawFov))
                ToggleRow(label: String(localized: "sniper_scope"), isOn: menu.feature(\.sniperScope))

                SliderRow(
                    label: String(localized: "field_of_view"),
                    value: menu.feature(\.aimbotRadiusValue),
                    range: 0...360,
                    showRange: true
                )
                ToggleRow(label: String(localized: "aim_visible_only"), isOn: menu.feature(\.aimVisibleOnly))
                SliderRow(
                    label: String(localized: "aim_distance"),
                    value: menu.feature(\.aimDistance),
                    range: 20...400,
                    unit: "m",
                    showRange: true
                )
                SliderRow(
                    label: String(localized: "aim_height"),
                    value: menu.feature(\.aimHeight),
                    range: 0.3...1.9,
                    step: 0.05,
                    showRange: true
                )
                SliderRow(
                    label: String(localized: "aim_smooth"),
                    value: menu.feature(\.aimSmooth),
                    range: 0.02...1.0,
                    step: 0.02,
                    showRange: true
                )
                SliderRow(
                    label: String(localized: "aim_reaction"),
                    value: menu.feature(\.aimReactionMs),
                    range: 80...600,
                    step: 10,
                    unit: "ms",
                    showRange: true
                )
                SliderRow(
                    label: String(localized: "aim_lead"),
                    value: menu.feature(\.aimLeadMs),
                    range: 0...200,
                    step: 5,
                    unit: "ms",
                    showRange: true
                )
            }
            SectionGroup(title: String(localized: "section_aimbot_stealth"), symbol: "shield.lefthalf.filled") {
                SegmentRow(
                    label: String(localized: "aim_stealth"),
                    selection: tierBinding,
                    options: [
                        SegmentOption(value: "0", title: String(localized: "stealth_lock")),
                        SegmentOption(value: "1", title: String(localized: "stealth_low")),
                        SegmentOption(value: "2", title: String(localized: "stealth_balanced")),
                        SegmentOption(value: "3", title: String(localized: "stealth_quiet")),
                    ]
                )
                SegmentRow(
                    label: String(localized: "aim_origin"),
                    selection: menu.feature(\.aimFrom),
                    options: [
                        SegmentOption(value: "camera", title: String(localized: "origin_camera")),
                        SegmentOption(value: "eye", title: String(localized: "origin_eye")),
                    ]
                )
                SliderRow(
                    label: String(localized: "aim_hold_gain"),
                    value: menu.feature(\.aimHoldGain),
                    range: 0.3...2.5,
                    step: 0.05,
                    showRange: true
                )
                SliderRow(
                    label: String(localized: "aim_commit"),
                    value: menu.feature(\.aimCommitMs),
                    range: 10...500,
                    step: 10,
                    unit: "ms",
                    showRange: true
                )
                Text(String(localized: "aim_stealth_note"))
                    .font(.caption)
                    .foregroundStyle(Palette.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metrics.rowPaddingH)
                    .padding(.vertical, 11)
                    .rowDivider()
                Text(String(localized: "aim_origin_note"))
                    .font(.caption)
                    .foregroundStyle(Palette.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metrics.rowPaddingH)
                    .padding(.vertical, 11)
                    .rowDivider()
                // The ban for an aim assist is statistical, not forensic: the
                // server scores headshot ratio, time-on-target and lock length
                // from the match record. The note is here because a slider that
                // quietly makes the score worse deserves an explanation.
                Text(String(localized: "aim_ban_note"))
                    .font(.caption)
                    .foregroundStyle(Palette.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metrics.rowPaddingH)
                    .padding(.vertical, 11)
                    .rowDivider()
            }
        }
    }

    /// `SegmentRow` speaks in strings and the tier is an ordinal the patch
    /// clamps to 0...3, so the conversion lives here rather than widening the
    /// row type for one control.
    private var tierBinding: Binding<String> {
        Binding(
            get: { String(menu.controls.aimStealth) },
            set: { newValue in
                var current = menu.controls
                current.aimStealth = Int(newValue) ?? 2
                // `AimLock` is tier 0 under its old name. Leaving it set while
                // the tier moves would mean two switches arguing.
                current.aimLock = current.aimStealth == 0
                menu.controls = current
            }
        )
    }
}
