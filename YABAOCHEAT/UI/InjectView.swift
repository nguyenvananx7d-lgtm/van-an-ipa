import SwiftUI

<<<<<<< HEAD
/// Injection screen: pick the target, read its state, inject, or remove.
///
/// Two verbs only — Inject and Uninject — mirroring the vendor build. The
/// kernel-exploit controls used to live here; they have moved to the Setting
/// tab so this screen stays a single decision.
=======
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
struct InjectView: View {
    @EnvironmentObject var menu: MenuStore
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var inject: InjectStore

    @State private var runningTask: Task<Void, Never>?

    var body: some View {
<<<<<<< HEAD
        VStack(alignment: .leading, spacing: Metrics.stack) {
            targetSection
            actionSection
=======
        Card(padding: 18, radius: 20) {
            VStack(alignment: .leading, spacing: 16) {
                header

                exploitSection

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
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
        }
        .onAppear {
            inject.evaluate()
        }
        .onChange(of: menu.selectedGame) { _ in
            inject.evaluate()
        }
    }

<<<<<<< HEAD
    // MARK: - target

    /// Who we are acting on and what state that target is in: the picker, the
    /// bundle id, one badge that answers "injected or not", then any banner the
    /// lookup produced.
    private var targetSection: some View {
        SectionGroup(title: String(localized: "injection"), symbol: "bolt") {
            VStack(alignment: .leading, spacing: 12) {
                SegmentedControl(
                    selection: $menu.selectedGame,
                    items: Game.allCases.map { SegItem(value: $0, title: $0.displayName) }
                )

                HStack(spacing: 8) {
                    Text(inject.game.bundleIdentifier)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Palette.textFaint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    stateBadge
                }

                if menu.injectStates[inject.game] == .unsupportedOS {
                    Banner(kind: .error, message: String(localized: "ios_not_supported"))
                }

                if let resolution = menu.resolutions[inject.game] {
                    resolutionBanner(resolution)
                }
            }
            .padding(Metrics.rowPaddingH)
        }
    }

    /// One badge for the whole state machine, so the screen never shows a bare
    /// "not resolved" with no reason.
    @ViewBuilder
    private var stateBadge: some View {
        if inject.isActive {
            StateBadge(text: String(localized: "inject_active"), tone: .good)
        } else {
            switch menu.injectStates[inject.game] ?? .checking {
            case .checking, .injecting:
                StateBadge(text: String(localized: "checking"), tone: .busy)
            case .ready:
                StateBadge(text: String(localized: "state_not_injected"), tone: .neutral)
            case .failed:
                StateBadge(text: String(localized: "state_failed"), tone: .bad)
            case .gameNotInstalled:
                StateBadge(text: String(localized: "game_not_installed"), tone: .bad)
            case .containerAccessDenied:
                StateBadge(text: String(localized: "container_access_denied"), tone: .bad)
            case .containerBridgeUnavailable:
                StateBadge(text: String(localized: "container_bridge_unavailable"), tone: .bad)
            case .unsupportedOS, .unsupportedHardware, .simulator:
                StateBadge(text: String(localized: "state_unsupported"), tone: .bad)
            case .unavailable:
                StateBadge(text: String(localized: "state_unavailable"), tone: .bad)
            }
=======
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

    /// The opt-in kernel-exploit block (Vortex Arena-specific: 3105 auto-runs, Vortex Arena
    /// keeps the chain behind an explicit button). `.unsupported` is rendered
    /// by the unsupported-OS banner instead; every other status gets a row with
    /// status text and a Run / Run-again button.
    @ViewBuilder
    private var exploitSection: some View {
        if inject.isRunningExploit {
            HStack(spacing: 10) {
                ProgressView()
                Text("exploit_status_running")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 2)
        } else {
            switch inject.exploitStatus {
            case .success:
                statusRow(
                    icon: "checkmark.seal.fill",
                    tint: .green,
                    titleKey: "exploit_status_success",
                    buttonKey: "retry_exploit"
                )
            case .failed:
                VStack(alignment: .leading, spacing: 8) {
                    banner(.error, String(localized: "exploit_status_failed"))
                    Button("retry_exploit") { inject.runExploit() }
                        .font(.footnote)
                }
            case .notStarted:
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(inject.requiresSandboxEscape ? Color.orange : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("exploit_status_not_started")
                            .font(.footnote.weight(.semibold))
                        Text(NSLocalizedString(inject.exploitHintKey, comment: ""))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("run_exploit") { inject.runExploit() }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                }
            case .unsupported:
                EmptyView()
            }
        }
    }

    private func statusRow(
        icon: String,
        tint: Color,
        titleKey: LocalizedStringKey,
        buttonKey: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(titleKey)
                .font(.footnote)
            Spacer()
            Button(buttonKey) { inject.runExploit() }
                .font(.footnote)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
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

<<<<<<< HEAD
    // MARK: - actions

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: Metrics.stack) {
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
                        .padding(.vertical, 15)
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(!canInject || runningTask != nil)

                if let status = inject.status {
                    HStack(spacing: 8) {
                        Image(systemName: inject.isActive ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(inject.isActive ? Palette.good : Palette.textFaint)
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(Palette.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

            SectionGroup(title: String(localized: "uninject"), symbol: "arrow.uturn.backward") {
                VStack(spacing: 10) {
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
                .padding(Metrics.rowPaddingH)
            }
        }
=======
    @ViewBuilder
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

        // Diagnostic: wipe the payload, launch clean, probe 10s later. Tells
        // whether the game dies on its own (sideloaded build boot-crash) or
        // because of the staged files (target self-kill after detecting them).
        Button("clean_launch_diagnostic") {
            inject.cleanLaunchDiagnostic()
        }
        .font(.footnote)
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
    }

    private var canInject: Bool {
        menu.resolutions[inject.game] == .resolved && auth.status.isOnline
    }
<<<<<<< HEAD
}
=======
}
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
