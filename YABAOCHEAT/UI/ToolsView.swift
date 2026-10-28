import SwiftUI

/// The original control shell, now reached through "Công cụ nâng cao".
///
/// Relay mode does not need any of these screens to play: the switches live on
/// the relay. They stay available because the container-injection path is still
/// shipped for devices where it works, and because the ESP/Aim configuration
/// editor is useful for exporting the profile the relay carries.
struct ToolsView: View {
    let onBack: () -> Void

    @StateObject private var language = LanguageStore.shared
    @StateObject private var menu = MenuStore.shared
    @StateObject private var auth = AuthorizationStore.shared
    @StateObject private var inject = InjectStore.shared
    @ObservedObject private var panel = PanelStore.shared

    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            ThemeBackground()
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
            PanelBubble()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
        .toggleStyle(MachinedToggleStyle())
        .tint(Palette.accent)
        .task { await inject.evaluate() }
        .fullScreenCover(isPresented: $panel.isOpen) {
            WebPanelView()
        }
    }

    // MARK: - app bar

    private var header: some View {
        topBar
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 10)
            .padding(.bottom, 12)
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
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.textDim)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.surface))
                    .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quay lại cài đặt relay")

            Mark(size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("app_title")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.text)
                    Text(verbatim: "v4.0")
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
