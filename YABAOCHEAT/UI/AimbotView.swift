import SwiftUI

/// Aimbot tab — anti-ban, assist type, and the tuning group from the mockup.
struct AimbotView: View {
    @EnvironmentObject var menu: MenuStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

                ToggleRow(label: String(localized: "silent_aim"), isOn: menu.feature(\.silentAim))
            }

            SectionGroup(title: String(localized: "section_aimbot_settings")) {
                ToggleRow(label: String(localized: "draw_fov"), isOn: menu.feature(\.drawFov))

                SliderRow(
                    label: String(localized: "field_of_view"),
                    value: menu.feature(\.aimbotRadiusValue),
                    range: 0...360
                )

                SliderRow(
                    label: String(localized: "aimbot_distance"),
                    value: menu.feature(\.aimDistance),
                    range: 0...500,
                    unit: "m"
                )

                ToggleRow(label: String(localized: "ignore_knocked"), isOn: menu.feature(\.ignoreKnocked))
            }
        }
    }
}
