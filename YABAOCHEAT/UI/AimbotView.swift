import SwiftUI

/// Aimbot tab. Only the switches the injected runtime actually reads are shown
/// here, so every row does something:
///
/// - master → `AimSystemEnabled`
/// - aim → `AimEnabled`
/// - bone → `AimTarget`
/// - hit chance → `HeadshotRate`
/// - draw FOV → `EspFov`
/// - field of view → `FovSize`
struct AimbotView: View {
    @EnvironmentObject var menu: MenuStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionGroup(title: String(localized: "section_aimbot_main")) {
                ToggleRow(label: String(localized: "master_aimbot"), isOn: menu.feature(\.isEnabled))
                ToggleRow(label: String(localized: "aim_enabled"), isOn: menu.feature(\.aimEnabled))
            }

            SectionGroup(title: String(localized: "section_aimbot_type")) {
                SegmentRow(
                    label: String(localized: "bone"),
                    selection: menu.feature(\.aimTarget),
                    options: [
                        SegmentOption(value: "head", title: String(localized: "bone_head")),
                        SegmentOption(value: "body", title: String(localized: "bone_body")),
                    ]
                )

                SliderRow(
                    label: String(localized: "hit_chance"),
                    value: menu.feature(\.hitChance),
                    unit: "%"
                )
            }

            SectionGroup(title: String(localized: "section_aimbot_settings")) {
                ToggleRow(label: String(localized: "draw_fov"), isOn: menu.feature(\.drawFov))

                SliderRow(
                    label: String(localized: "field_of_view"),
                    value: menu.feature(\.aimbotRadiusValue),
                    range: 0...360
                )
            }
        }
    }
}
