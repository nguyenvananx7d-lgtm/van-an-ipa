import SwiftUI

/// Main shell: license gate until the session is valid, then a slim app bar
/// with the four screens under an underline tab strip.
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
                    topBar

                    if let msg = auth.revocationMessage {
                        Banner(kind: .error, message: msg)
                    }

                    TabStrip(
                        selection: $selectedTab,
                        items: [
                            String(localized: "tab_aimbot"),
                            String(localized: "tab_visual"),
                            String(localized: "tab_misc"),
                            String(localized: "tab_setting"),
                        ]
                    )

                    Group {
                        switch selectedTab {
                        case 0:  AimbotView()
                        case 1:  VisualView()
                        case 2:  MiscView()
                        default: SettingView()
                        }
                    }
                    .transition(.opacity)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
        .toggleStyle(MachinedToggleStyle())
        .tint(Palette.accent)
        .task { await inject.evaluate() }
    }

    // MARK: - app bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Mark(size: 36)

            VStack(alignment: .leading, spacing: 3) {
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
                    }
                }
            }

            Spacer(minLength: 12)

            statusBadge
        }
        .padding(.bottom, 2)
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