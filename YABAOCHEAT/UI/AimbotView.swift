import SwiftUI

<<<<<<< HEAD
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
=======
/// Aimbot tab — anti-ban, assist type, and the tuning group from the mockup.
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
struct AimbotView: View {
    @EnvironmentObject var menu: MenuStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
<<<<<<< HEAD
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
=======
            SectionGroup(title: String(localized: "section_aimbot_main")) {
                ToggleRow(label: String(localized: "master_aimbot"), isOn: menu.feature(\.isEnabled))
            }

            SectionGroup(title: String(localized: "section_antiban")) {
                ToggleRow(label: String(localized: "anti_ban"), isOn: menu.feature(\.antiBan))
            }

            SectionGroup(title: String(localized: "section_aimbot_type")) {
                SegmentRow(
                    label: String(localized: "aimbot_type"),
                    selection: menu.feature(\.aimbotType),
                    options: [
                        SegmentOption(value: "aimbot", title: String(localized: "aimbot_type_normal")),
                        SegmentOption(value: "silent", title: String(localized: "aimbot_type_silent")),
                    ]
                )

>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
                SegmentRow(
                    label: String(localized: "bone"),
                    selection: menu.feature(\.aimTarget),
                    options: [
                        SegmentOption(value: "head", title: String(localized: "bone_head")),
<<<<<<< HEAD
                        SegmentOption(value: "neck", title: String(localized: "bone_neck")),
                        SegmentOption(value: "body", title: String(localized: "bone_body")),
                    ]
                )
            }

            SectionGroup(title: String(localized: "section_aimbot_settings"), symbol: "slider.horizontal.3") {
                ToggleRow(label: String(localized: "draw_fov"), isOn: menu.feature(\.drawFov))
                ToggleRow(label: String(localized: "sniper_scope"), isOn: menu.feature(\.sniperScope))
=======
                        SegmentOption(value: "body", title: String(localized: "bone_body")),
                    ]
                )

                SliderRow(
                    label: String(localized: "hit_chance"),
                    value: menu.feature(\.hitChance),
                    unit: "%"
                )

                ToggleRow(label: String(localized: "silent_aim"), isOn: menu.feature(\.silentAim))
            }

            SectionGroup(title: String(localized: "section_aimbot_settings")) {
                ToggleRow(label: String(localized: "draw_fov"), isOn: menu.feature(\.drawFov))
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210

                SliderRow(
                    label: String(localized: "field_of_view"),
                    value: menu.feature(\.aimbotRadiusValue),
<<<<<<< HEAD
                    range: 0...360,
                    showRange: true
                )
=======
                    range: 0...360
                )

                SliderRow(
                    label: String(localized: "aimbot_distance"),
                    value: menu.feature(\.aimDistance),
                    range: 0...500,
                    unit: "m"
                )

                ToggleRow(label: String(localized: "ignore_knocked"), isOn: menu.feature(\.ignoreKnocked))
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
            }
        }
    }
}
