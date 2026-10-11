import SwiftUI

/// Injection screen: pick the target, inject, or remove.
///
/// Two verbs only — Inject and Uninject — mirroring the vendor build. The
/// kernel-exploit controls used to live here; they have moved to the Setting
/// tab so this screen stays a single decision.
struct InjectView: View {
    @EnvironmentObject var menu: MenuStore
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var inject: InjectStore

    @State private var runningTask: Task<Void, Never>?

    var body: some View {
        Card(padding: 18, radius: 16) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if menu.injectStates[inject.game] == .unsupportedOS {
                    banner(.error, String(localized: "ios_not_supported"))
                }

                if let resolution = menu.resolutions[inject.game] {
                    resolutionBanner(resolution)
                }

                buttons

                if let status = inject.status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(Palette.textDim)
                }

                if inject.isActive {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Palette.good)
                        Text("inject_active")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textDim)
                        Spacer(minLength: 0)
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
                .foregroundStyle(Palette.text)

            SegmentedControl(
                selection: $menu.selectedGame,
                items: Game.allCases.map { SegItem(value: $0, title: $0.displayName) }
            )

            Text(inject.game.bundleIdentifier)
                .font(.caption2.monospaced())
                .foregroundStyle(Palette.textFaint)
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
        VStack(alignment: .leading, spacing: 12) {
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
                    .padding(.vertical, 14)
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(!canInject || runningTask != nil)

            VStack(alignment: .leading, spacing: 8) {
                Text("uninject")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textFaint)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Button {
                    runningTask = Task { await inject.keepFeatures() }
                } label: {
                    VStack(spacing: 2) {
                        Text("uninject_keep")
                            .font(.headline)
                        Text("uninject_keep_caption")
                            .font(.caption2)
                            .foregroundStyle(Palette.textDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .buttonStyle(AccentButtonStyle(prominent: false))
                .disabled(runningTask != nil)

                Button {
                    runningTask = Task { await inject.uninject() }
                } label: {
                    VStack(spacing: 2) {
                        Text("uninject_full")
                            .font(.headline)
                        Text("uninject_full_caption")
                            .font(.caption2)
                            .foregroundStyle(Palette.textDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .buttonStyle(AccentButtonStyle(prominent: false, destructive: true))
                .disabled(runningTask != nil)
            }
        }
    }

    private var canInject: Bool {
        menu.resolutions[inject.game] == .resolved && auth.status.isOnline
    }
}