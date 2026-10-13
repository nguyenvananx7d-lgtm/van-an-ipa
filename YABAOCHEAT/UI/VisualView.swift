import SwiftUI

/// Visual tab. Only the ESP toggles the injected runtime reads are shown, so
/// every row does something:
///
/// - master → `EspMaster`
/// - line → `EspLine`
/// - box → `EspBox`
/// - name → `EspName`
/// - distance → `EspDistance`
/// - health → `EspHealth`
/// - skeleton → `EspSkeleton`
/// - tracer → `EspTracer` (the cheat's "Top tracer")
/// - box size / drop → `EspBoxScale` / `EspBoxOffset`
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
        }
    }
}
