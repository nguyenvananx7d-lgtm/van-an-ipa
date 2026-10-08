import SwiftUI

struct InjectView: View {
    @EnvironmentObject var menu: MenuStore
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var inject: InjectStore

    @State private var runningTask: Task<Void, Never>?

    var body: some View {
        Card(padding: 18, radius: 20) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let resolution = menu.resolutions[inject.game] {
                    resolutionBanner(resolution)
                }

                buttons

                if let status = inject.status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if inject.isActive {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("inject_active")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Button("uninject") { runningTask = Task { await inject.uninject() } }
                            .buttonStyle(.bordered)
                            .disabled(runningTask != nil)
                    }
                }
            }
        }
        .onAppear {
            inject.evaluate()
        }
        .onChange(of: menu.selectedGame) { _ in
            inject.evaluate()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("injection")
                .font(.headline)

            Picker("", selection: $menu.selectedGame) {
                ForEach(Game.allCases, id: \.self) { game in
                    Text(game.displayName).tag(game)
                }
            }
            .pickerStyle(.segmented)

            Text(inject.game.bundleIdentifier)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func resolutionBanner(_ resolution: ContainerResolution) -> some View {
        switch resolution {
        case .resolved:
            return banner(.info, String(localized: "container_resolved"))
        case .notFound:
            return banner(.error, String(localized: "game_not_installed"))
        case .accessDenied:
            return banner(.error, accessDeniedMessage)
        case .bridgeUnavailable:
            return banner(.warning, String(localized: "container_bridge_unavailable"))
        }
    }

    /// The red banner for `.accessDenied` shows *why* the container is sealed:
    /// the underlying FileManager error when there is one, else the entitlement
    /// status, else the short key.
    private var accessDeniedMessage: String {
        if let reason = inject.accessDeniedReason, !reason.isEmpty {
            return reason
        }
        return String(localized: "container_access_denied")
    }

    private func banner(_ kind: Banner.Kind, _ message: String) -> some View {
        Banner(kind: kind, message: message)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                runningTask = Task {
                    await inject.install(
                        expectedDigest: auth.expectedPatchSHA256,
                        monitorMs: auth.patchOpenMonitorMs
                    )
                }
            } label: {
                Text("inject")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canInject || runningTask != nil)

            Button {
                inject.wipe()
            } label: {
                Text("wipe")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(runningTask != nil)

            Button {
                inject.launch()
            } label: {
                Text("launch")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }

    private var canInject: Bool {
        menu.resolutions[inject.game] == .resolved && auth.status.isOnline
    }
}
