import SwiftUI

/// Main shell: license gate until the session is valid, then a slim app bar
/// with the four screens under a bottom navigation bar.
struct ContentView: View {
    @StateObject private var language = LanguageStore.shared
    @StateObject private var menu = MenuStore.shared
    @StateObject private var auth = AuthorizationStore.shared
    @StateObject private var inject = InjectStore.shared

    @State private var selectedTab: Int = 0

    var body: some View {
        Group {
            if !language.hasChosen {
                LanguagePickerView(store: language)
            } else if !auth.status.isOnline {
                LicenseView()
            } else {
                shell
            }
        }
        .environmentObject(menu)
        .environmentObject(auth)
        .environmentObject(inject)
        .environmentObject(language)
        .animation(.easeInOut(duration: 0.2), value: auth.status.isOnline)
        .tint(Palette.accent)
    }

    // MARK: - shell

    private var shell: some View {
        ZStack {
            ThemeBackground()

            // The app bar is pinned and only the active screen scrolls;
            // navigation lives in the bottom bar, a thumb away. Session state
            // stays one glance away at the top.
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.stack) {
                        if let msg = auth.revocationMessage {
                            Banner(kind: .error, message: msg)
                        }

                        Group {
                            switch selectedTab {
                            case 0:  AimbotView()
                            case 1:  VisualView()
                            case 2:  MiscView()
                            default: SettingView()
                            }
                        }
                        .transition(.opacity)
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, Metrics.stack)
                    .padding(.bottom, 24)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
        .toggleStyle(MachinedToggleStyle())
        .tint(Palette.accent)
        .task { await inject.evaluate() }
    }

    // MARK: - app bar

    private var header: some View {
        topBar
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 10)
            .padding(.bottom, 12)
            // The bar is pinned above the scroll view rather than over it, and
            // carries a single hairline where the content clips: no opaque
            // backdrop, so the themed canvas stays continuous.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
            }
    }

    private var bottomBar: some View {
        BottomTabBar(
            selection: $selectedTab,
            items: [
                TabItem(index: 0, title: String(localized: "tab_aimbot"), symbol: "scope"),
                TabItem(index: 1, title: String(localized: "tab_visual"), symbol: "eye"),
                TabItem(index: 2, title: String(localized: "tab_misc"), symbol: "bolt"),
                TabItem(index: 3, title: String(localized: "tab_setting"), symbol: "slider.horizontal.3"),
            ]
        )
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Mark(size: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("app_title")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.text)
                    Text(verbatim: "v3.7.33")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.textFaint)
                }
                HStack(spacing: 8) {
                    Text(planLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    if let key = auth.status.displayKey {
                        Text(key)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Palette.textFaint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                statusBadge
                if inject.isActive {
                    StateBadge(text: String(localized: "inject_active"), tone: .good)
                }
            }
        }
    }

    private var planLabel: String {
        let s = auth.status
        if s.isOnline {
            return s.plan ?? String(localized: "plan_premium")
        }
        if case .checking = s {
            return String(localized: "checking")
        }
        return String(localized: "offline")
    }

    private var statusBadge: some View {
        let s = auth.status
        if s.isOnline {
            return StateBadge(text: String(localized: "license_valid"), tone: .good)
        }
        if case .checking = s {
            return StateBadge(text: String(localized: "checking"), tone: .busy)
        }
        if case .offline = s {
            return StateBadge(text: String(localized: "offline"), tone: .bad)
        }
        return StateBadge(text: String(localized: "unlicensed"), tone: .neutral)
    }
}