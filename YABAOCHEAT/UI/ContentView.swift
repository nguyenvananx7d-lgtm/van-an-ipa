import SwiftUI

/// Main shell: license gate until the session is valid, then the branded
/// header with the four tab pages from the mockup.
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
        .tint(.purple)
    }

    // MARK: - shell

    private var shell: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let msg = auth.revocationMessage {
                    Banner(kind: .error, message: msg)
                }

                tabPicker

                switch selectedTab {
                case 0:  AimbotView()
                case 1:  VisualView()
                case 2:  MiscView()
                default: SettingView()
                }

                Spacer(minLength: 24)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .task { await inject.evaluate() }
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text("tab_aimbot").tag(0)
            Text("tab_visual").tag(1)
            Text("tab_misc").tag(2)
            Text("tab_setting").tag(3)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - header

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    Mark(size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("app_title")
                            .font(.title3.weight(.bold))
                        HStack(spacing: 4) {
                            Text("version")
                            Text("3.7.33")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        statusBadge
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(auth.status.plan ?? "offline")
                            .font(.caption.weight(.semibold))
                        Text(auth.status.displayKey ?? "—")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(welcomeLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
