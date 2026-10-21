import SwiftUI

<<<<<<< HEAD
/// Visual tab. Only the ESP toggles the injected runtime reads are shown, so
/// every row does something:
///
/// - master → `EspMaster`
/// - box / name / distance / health / skeleton / tracer → the matching
///   `Esp*` key ("Top tracer" is `EspTracer`)
/// - line → `EspLine`, with the anchor choice under `LineTarget*`
/// - 360 arrows → `Esp360Arrows`
/// - enemy count → `EnemyCount`
/// - box size / drop → `EspBoxScale` / `EspBoxOffset`
/// - colour targets + palette + chroma → `FovColor` … `AllRainbow`
=======
/// Visual tab — the ESP block and the sizing sliders from the mockup.
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
struct VisualView: View {
    @EnvironmentObject var menu: MenuStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
<<<<<<< HEAD
            SectionGroup(title: String(localized: "section_esp_main"), symbol: "eye") {
                ToggleRow(label: String(localized: "master_esp"), isOn: menu.feature(\.masterEsp))
                ToggleRow(label: String(localized: "line_esp"), isOn: menu.feature(\.lineEsp))
                ToggleRow(label: String(localized: "box_esp"), isOn: menu.feature(\.boxEsp))
                ToggleRow(label: String(localized: "name_esp"), isOn: menu.feature(\.nameEsp))
                ToggleRow(label: String(localized: "distance_esp"), isOn: menu.feature(\.distanceEsp))
                ToggleRow(label: String(localized: "health_esp"), isOn: menu.feature(\.healthEsp))
                ToggleRow(label: String(localized: "skeleton_esp"), isOn: menu.feature(\.skeletonEsp))
                ToggleRow(label: String(localized: "tracer_esp"), isOn: menu.feature(\.tracerEsp))
                ToggleRow(label: String(localized: "esp360_arrows"), isOn: menu.feature(\.esp360Arrows))
                ToggleRow(label: String(localized: "enemy_count"), isOn: menu.feature(\.drawEnemyCount))
            }

            if menu.controls.lineEsp {
                SectionGroup(title: String(localized: "section_line_target"), symbol: "line.diagonal") {
                    SegmentRow(
                        label: String(localized: "line_target"),
                        selection: menu.feature(\.lineTarget),
                        options: [
                            SegmentOption(value: "top", title: String(localized: "line_top")),
                            SegmentOption(value: "bottom", title: String(localized: "line_bottom")),
                            SegmentOption(value: "crosshair", title: String(localized: "line_crosshair")),
                        ]
                    )
                }
            }

            SectionGroup(title: String(localized: "section_esp_box"), symbol: "rectangle.dashed") {
                SliderRow(
                    label: String(localized: "box_size"),
                    value: menu.feature(\.espBoxScalePercent),
                    range: 50...200,
                    unit: "%",
                    showRange: true
                )

                SliderRow(
                    label: String(localized: "box_offset"),
                    value: menu.feature(\.espBoxOffsetY),
                    range: -60...60,
                    unit: "px",
                    showRange: true
                )
            }

            SectionGroup(title: String(localized: "section_color"), symbol: "paintpalette") {
                ToggleRow(label: String(localized: "fov_color"), isOn: menu.feature(\.fovColor))
                ToggleRow(label: String(localized: "line_tracer_color"), isOn: menu.feature(\.lineTracerColor))
                ToggleRow(label: String(localized: "box2d_color"), isOn: menu.feature(\.box2dColor))
                ToggleRow(label: String(localized: "skeleton_color"), isOn: menu.feature(\.skeletonColor))

                PaletteRow(
                    label: String(localized: "palette"),
                    selection: menu.feature(\.espPalette)
                )

                ToggleRow(label: String(localized: "rainbow"), isOn: menu.feature(\.rainbow))
                ToggleRow(label: String(localized: "all_rainbow"), isOn: menu.feature(\.allRainbow))
                ToggleRow(label: String(localized: "reset_all_colors"), isOn: menu.feature(\.resetAllColors))
=======
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

            SectionGroup(title: String(localized: "section_esp_color")) {
                SwatchRow(label: String(localized: "esp_color"), argb: menu.feature(\.espColor))
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
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
            }
        }
    }
}
