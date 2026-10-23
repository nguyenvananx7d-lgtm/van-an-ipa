import SwiftUI

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
struct VisualView: View {
    @EnvironmentObject var menu: MenuStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            SectionGroup(title: String(localized: "section_esp_advanced"), symbol: "square.stack.3d.up") {
                ToggleRow(label: String(localized: "esp_visible_only"), isOn: menu.feature(\.espVisibleOnly))
                ToggleRow(label: String(localized: "esp_show_downed"), isOn: menu.feature(\.espShowDowned))
                ToggleRow(label: String(localized: "esp_head_dot"), isOn: menu.feature(\.espHeadDot))
                ToggleRow(label: String(localized: "esp_box_fill"), isOn: menu.feature(\.espBoxFill))
                SliderRow(
                    label: String(localized: "esp_max_distance"),
                    value: menu.feature(\.espMaxDistance),
                    range: 20...500,
                    unit: "m",
                    showRange: true
                )
                if menu.controls.espBoxFill {
                    SliderRow(
                        label: String(localized: "esp_box_fill_alpha"),
                        value: menu.feature(\.espBoxFillAlpha),
                        range: 0.05...0.9,
                        step: 0.01,
                        showRange: true
                    )
                }
                SliderRow(
                    label: String(localized: "esp_text_scale"),
                    value: menu.feature(\.espTextScale),
                    range: 0.5...1.6,
                    step: 0.05,
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
            }
        }
    }
}
