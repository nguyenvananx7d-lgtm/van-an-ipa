import SwiftUI

/// Main shell: license gate until the session is valid, then the branded header
/// with the four tab pages.
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let msg = auth.revocationMessage {
                        Banner(kind: .error, message: msg)
                    }

                    tabBar

                    Group {
                        switch selectedTab {
                        case 0:  AimbotView()
                        case 1:  VisualView()
                        case 2:  MiscView()
                        default: SettingView()
                        }
                    }
                    .transition(.opacity)

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
        .toggleStyle(MachinedToggleStyle())
        .tint(Palette.accent)
        .task { await inject.evaluate() }
    }

    private var tabBar: some View {
        SegmentedControl(
            selection: $selectedTab,
            items: [
                SegItem(value: 0, title: String(localized: "tab_aimbot")),
                SegItem(value: 1, title: String(localized: "tab_visual")),
                SegItem(value: 2, title: String(localized: "tab_misc")),
                SegItem(value: 3, title: String(localized: "tab_setting")),
            ]
        )
    }

    // MARK: - header

    private var header: some View {
        Card(padding: 16, radius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        PulseRing(size: 62)
                        Mark(size: 54)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("app_title")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Palette.text)
                            .glitch()
                        HStack(spacing: 6) {
                            Text("version")
                                .foregroundStyle(Palette.textFaint)
                            Text("3.7.33")
                                .foregroundStyle(Palette.textDim)
                        }
                        .font(.caption)
                        statusBadge
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text(auth.status.plan ?? "offline")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                        Text(auth.status.displayKey ?? "—")
                            .font(.caption2)
                            .foregroundStyle(Palette.textDim)
                            .lineLimit(1)
                    }
                }

                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)

                Text(welcomeLine)
                    .font(.footnote)
                    .foregroundStyle(Palette.textDim)
            }
        }
    }

    private var welcomeLine: String {
        String(
            format: String(localized: "welcome_back"),
            auth.status.displayKey ?? "—"
        )
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
