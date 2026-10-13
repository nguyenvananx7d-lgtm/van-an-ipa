import SwiftUI

/// Aimbot tab. Only the switches the injected runtime actually reads are shown
/// here, so every row does something:
///
/// - master → `AimSystemEnabled`
/// - silent aim → forces `AimTarget` to the mixed-roll mode (`0`) and arms
///   `AimEnabled`
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
                ToggleRow(label: String(localized: "master_aimbot"), isOn: menu.feature(\.isEnabled))
                ToggleRow(label: String(localized: "silent_aim"), isOn: menu.feature(\.silentAim))

                if menu.controls.silentAim {
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

                SliderRow(
                    label: String(localized: "field_of_view"),
                    value: menu.feature(\.aimbotRadiusValue),
                    range: 0...360,
                    showRange: true
                )
            }
        }
    }
}
