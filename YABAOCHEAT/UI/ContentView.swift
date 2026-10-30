import SwiftUI

/// Top-level routing:
///
///   language → local home, or the old activation gate → relay home.
///
/// `LocalMode` is the temporary build policy: no key, no relay, no CA. The
/// local home is a single switch — the injection route is chosen by the device,
/// not by a server. The relay flow stays compiled for a build that flips the
/// flag back on.
struct ContentView: View {
    @StateObject private var language = LanguageStore.shared
    @StateObject private var menu = MenuStore.shared
    @StateObject private var auth = AuthorizationStore.shared
    @StateObject private var inject = InjectStore.shared

    @State private var route: Route = .home

    private enum Route {
        case home
        case settings
    }

    var body: some View {
        Group {
            if !language.hasChosen {
                LanguagePickerView(store: language)
            } else if LocalMode.enabled {
                LocalHomeView()
            } else if !auth.status.isOnline {
                LicenseView()
            } else {
                switch route {
                case .home:
                    SetupView(onOpenSettings: { route = .settings })
                case .settings:
                    SettingsScreen(onBack: { route = .home })
                }
            }
        }
        .environmentObject(menu)
        .environmentObject(auth)
        .environmentObject(inject)
        .environmentObject(language)
        .animation(.easeInOut(duration: 0.2), value: auth.status.isOnline)
        .onChange(of: auth.status.isOnline) { online in
            if !online { route = .home }
        }
        .toggleStyle(MachinedToggleStyle())
        .tint(Palette.accent)
    }
}

/// SettingView wrapped for standalone use: background, scroll and a back bar.
private struct SettingsScreen: View {
    let onBack: () -> Void

    var body: some View {
        ZStack {
            ThemeBackground()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Palette.textDim)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Palette.surface))
                            .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quay lại")

                    Mark(size: 34)
                    Text("CÀI ĐẶT")
                        .font(.ui(17, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Palette.text)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }

                ScrollView(showsIndicators: false) {
                    SettingView()
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, Metrics.stack)
                        .padding(.bottom, 28)
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
