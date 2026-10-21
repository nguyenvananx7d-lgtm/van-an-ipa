import SwiftUI

<<<<<<< HEAD
/// Inject tab — the injection pair on its own. The kernel-exploit controls live
/// in the Setting tab.
struct MiscView: View {
    var body: some View {
        InjectView()
=======
/// Misc tab — the injection cycle plus whatever the deployment catalog still
/// wants to show.
struct MiscView: View {
    @EnvironmentObject var menu: MenuStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InjectView()

            if !menu.catalog.isEmpty {
                CatalogSections()
            }
        }
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
    }
}
