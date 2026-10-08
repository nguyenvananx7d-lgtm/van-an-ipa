import SwiftUI

/// App entry point.
///
/// The scene phase is observed here rather than in a view so the session is
/// revalidated on every foreground, including the return from the game after an
/// injection — the heartbeat will have lapsed while the other app was frontmost.
@main
struct YABAOCHEATApp: App {
    @StateObject private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.language)
                .environmentObject(environment.menu)
                .environmentObject(environment.authorization)
                .environmentObject(environment.inject)
                .preferredColorScheme(environment.isDarkMode ? .dark : .light)
                .onOpenURL { url in handle(url) }
        }
        .onChange(of: scenePhase) { phase in
            environment.handle(scenePhase: phase)
        }
    }

    private func handle(_ url: URL) {
        // The licensing server can hand back a key through a redirect; anything
        // unrecognised is ignored rather than surfaced as an error.
        guard url.scheme == "ffxc" else { return }
        if url.host == "auth", let key = url.queryParameters["key"] {
            Task { await environment.authorization.submit(key: key) }
        }
    }
}

private extension URL {
    var queryParameters: [String: String] {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
    }
}
