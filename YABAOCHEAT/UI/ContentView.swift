import SwiftUI

/// Top-level routing:
///
///   language → activation gate → relay setup → (optional) advanced tools.
///
/// Relay setup is the default screen after activation because that is the flow
/// the install video shows: certificate, Super Proxy, then the game. The old
/// tabbed shell is a sibling route, not the landing screen.
struct ContentView: View {
    @StateObject private var language = LanguageStore.shared
    @StateObject private var menu = MenuStore.shared
    @StateObject private var auth = AuthorizationStore.shared
    @StateObject private var inject = InjectStore.shared

    @State private var route: Route = .setup

    private enum Route {
        case setup
        case tools
    }

    var body: some View {
        Group {
            if !language.hasChosen {
                LanguagePickerView(store: language)
            } else if !auth.status.isOnline {
                LicenseView()
            } else {
                switch route {
                case .setup:
                    SetupView(onOpenTools: { route = .tools })
                case .tools:
                    ToolsView(onBack: { route = .setup })
                }
            }
        }
        .environmentObject(menu)
        .environmentObject(auth)
        .environmentObject(inject)
        .environmentObject(language)
        .animation(.easeInOut(duration: 0.2), value: auth.status.isOnline)
        .onChange(of: auth.status.isOnline) { online in
            if !online { route = .setup }
        }
        .tint(Palette.accent)
    }
}
