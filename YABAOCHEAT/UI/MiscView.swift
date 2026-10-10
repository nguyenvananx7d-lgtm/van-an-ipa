import SwiftUI

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
    }
}
