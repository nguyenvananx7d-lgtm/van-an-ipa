import SwiftUI

<<<<<<< HEAD
/// Main shell: license gate until the session is valid, then a slim app bar
/// with the four screens under a bottom navigation bar.
=======
/// Main shell: license gate until the session is valid, then the branded
/// header with the four tab pages from the mockup.
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
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
<<<<<<< HEAD
        .tint(Palette.accent)
=======
        .tint(.purple)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
    }

    // MARK: - shell

    private var shell: some View {
<<<<<<< HEAD
        ZStack {
            ThemeBackground()

            // The app bar is pinned and only the active screen scrolls;
            // navigation lives in the bottom bar, a thumb away. Session state
            // stays one glance away at the top.
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.stack) {
                        pageHeading

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
            Mark(size: 36)

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
=======
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
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
            }
        }
    }

<<<<<<< HEAD
    private var pageHeading: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("controls")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textFaint)

                Text(selectedTabTitle)
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .contentTransition(.opacity)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 7) {
                Text("0\(selectedTab + 1)")
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textFaint)
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: 22, height: 2)
            }
            .padding(.bottom, 3)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .padding(.bottom, 2)
    }

    private var selectedTabTitle: String {
        switch selectedTab {
        case 0: return String(localized: "tab_aimbot")
        case 1: return String(localized: "tab_visual")
        case 2: return String(localized: "tab_misc")
        default: return String(localized: "tab_setting")
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
=======
    private var welcomeLine: String {
        String(
            format: String(localized: "welcome_back"),
            auth.status.displayKey ?? "—"
        )
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
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
<<<<<<< HEAD
}
=======
}
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
