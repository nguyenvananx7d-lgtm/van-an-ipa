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
struct VisualView: View {
    @EnvironmentObject var menu: MenuStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionGroup(title: String(localized: "section_esp_main")) {
                ToggleRow(label: String(localized: "master_esp"), isOn: menu.feature(\.masterEsp))
                ToggleRow(label: String(localized: "line_esp"), isOn: menu.feature(\.lineEsp))
                ToggleRow(label: String(localized: "box_esp"), isOn: menu.feature(\.boxEsp))
                ToggleRow(label: String(localized: "name_esp"), isOn: menu.feature(\.nameEsp))
                ToggleRow(label: String(localized: "distance_esp"), isOn: menu.feature(\.distanceEsp))
                ToggleRow(label: String(localized: "health_esp"), isOn: menu.feature(\.healthEsp))
                ToggleRow(label: String(localized: "skeleton_esp"), isOn: menu.feature(\.skeletonEsp))
            }
        }
    }
}
