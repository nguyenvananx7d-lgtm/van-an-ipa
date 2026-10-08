import SwiftUI

/// Visual tab — the ESP block and the sizing sliders from the mockup.
struct VisualView: View {
    @EnvironmentObject var menu: MenuStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionGroup(title: String(localized: "section_esp_main")) {
                ToggleRow(label: String(localized: "master_esp"), isOn: menu.feature(\.masterEsp))
                ToggleRow(label: String(localized: "line_esp"), isOn: menu.feature(\.lineEsp))
                ToggleRow(label: String(localized: "box_esp"), isOn: menu.feature(\.boxEsp))

                SegmentRow(
                    label: String(localized: "box_type"),
                    selection: menu.feature(\.boxType),
                    options: [
                        SegmentOption(value: "corner", title: String(localized: "box_type_corner")),
                        SegmentOption(value: "edge", title: String(localized: "box_type_edge")),
                    ]
                )

                ToggleRow(label: String(localized: "name_esp"), isOn: menu.feature(\.nameEsp))
                ToggleRow(label: String(localized: "distance_esp"), isOn: menu.feature(\.distanceEsp))
                ToggleRow(label: String(localized: "health_esp"), isOn: menu.feature(\.healthEsp))

                SegmentRow(
                    label: String(localized: "health_type"),
                    selection: menu.feature(\.healthType),
                    options: [
                        SegmentOption(value: "left", title: String(localized: "health_type_left")),
                        SegmentOption(value: "right", title: String(localized: "health_type_right")),
                    ]
                )

                ToggleRow(label: String(localized: "skeleton_esp"), isOn: menu.feature(\.skeletonEsp))
                ToggleRow(label: String(localized: "draw_enemy_count"), isOn: menu.feature(\.drawEnemyCount))
            }

            SectionGroup(title: String(localized: "section_visual_sliders")) {
                SliderRow(
                    label: String(localized: "text_size"),
                    value: menu.feature(\.textSize),
                    range: 8...32
                )

                SliderRow(
                    label: String(localized: "bounding_2d"),
                    value: menu.feature(\.espBounding),
                    range: 0...10
                )

                SliderRow(
                    label: String(localized: "esp_thickness"),
                    value: menu.feature(\.espThickness),
                    range: 1...6
                )
            }
        }
    }
}
