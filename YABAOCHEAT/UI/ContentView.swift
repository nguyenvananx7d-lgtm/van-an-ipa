import SwiftUI

/// Main content view: a tabbed shell with status, controls and log.
struct ContentView: View {
    @StateObject private var language = LanguageStore.shared
    @StateObject private var menu = MenuStore.shared
    @StateObject private var auth = AuthorizationStore.shared
    @StateObject private var inject = InjectStore.shared

    @State private var selectedTab: Int = 0
    @State private var showLogout: Bool = false

    var body: some View {
        if !language.hasChosen {
            LanguagePickerView(store: language)
                .transition(.opacity)
        } else {
            TabView(selection: $selectedTab) {
                statusTab
                    .tabItem { Label("status", systemImage: "bolt.shield.fill") }
                    .tag(0)

                controlsTab
                    .tabItem { Label("controls", systemImage: "slider.horizontal.3") }
                    .tag(1)

                logTab
                    .tabItem { Label("log", systemImage: "text.alignleft") }
                    .tag(2)
            }
            .environmentObject(menu)
            .environmentObject(auth)
            .environmentObject(inject)
            .task { await inject.evaluate() }
            .alert("logout_confirm_title", isPresented: $showLogout) {
                Button("logout_confirm_yes", role: .destructive) { auth.logout() }
                Button("logout_confirm_cancel", role: .cancel) {}
            } message: {
                Text("logout_confirm_msg")
            }
            .onChange(of: language.selected) { _ in
                // No-op; translation layer would swap strings here.
            }
        }
    }

    // MARK: tabs

    private var statusTab: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if let msg = auth.revocationMessage {
                        Banner(kind: .error, message: msg)
                    }

                    InjectView()

                    if auth.status.isOnline {
                        LicenseView()
                    } else {
                        LicenseView()
                    }

                    Spacer(minLength: 32)
                }
                .padding(16)
            }
            .navigationTitle("status")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if auth.status.isOnline {
                        Button("logout") {
                            showLogout = true
                        }
                        .font(.callout)
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var controlsTab: some View {
        NavigationView {
            ControlsView()
                .navigationTitle("controls")
        }
        .navigationViewStyle(.stack)
    }

    private var logTab: some View {
        NavigationView {
            LogView()
                .navigationTitle("log")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: header

    private var header: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Mark(size: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("app_title")
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 4) {
                        Text("version")
                        Text("3.7.33")
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        statusBadge
                    }
                    .padding(.top, 4)
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
        }
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

