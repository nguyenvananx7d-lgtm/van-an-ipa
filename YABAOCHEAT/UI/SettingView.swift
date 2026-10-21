import SwiftUI
import UIKit

<<<<<<< HEAD
/// Setting tab — the kernel-exploit controls, license facts, compatibility,
/// language, support.
struct SettingView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var inject: InjectStore
=======
/// Setting tab — privacy, license facts, compatibility, language, support.
struct SettingView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
    @EnvironmentObject var menu: MenuStore

    @State private var showLogout: Bool = false
    @State private var showLog: Bool = false
    @State private var copied: Bool = false

    /// Swap for the real invite when the server side settles.
<<<<<<< HEAD
    private let supportURL = "https://discord.gg/hcx7aP4XSp"
=======
    private let supportURL = "https://discord.com/invite/delta"
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210

    private var device: DeviceIdentityProvider { .shared }

    var body: some View {
<<<<<<< HEAD
        VStack(alignment: .leading, spacing: Metrics.stack) {
            exploit
            antiBanSection
=======
        VStack(alignment: .leading, spacing: 16) {
            privacy
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
            licenseInfo
            compatibility
            languageSection
            support
        }
        .alert("logout_confirm_title", isPresented: $showLogout) {
            Button("logout_confirm_yes", role: .destructive) { auth.logout() }
            Button("logout_confirm_cancel", role: .cancel) {}
        } message: {
            Text("logout_confirm_msg")
        }
        .sheet(isPresented: $showLog) {
            NavigationView {
                LogView()
                    .navigationTitle("log")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showLog = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                        }
                    }
            }
            .navigationViewStyle(.stack)
        }
<<<<<<< HEAD
        .onChange(of: menu.controls.antiBan) { newValue in
            if newValue {
                Task { await inject.runAntiBan() }
            }
        }
=======
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
    }

    // MARK: - sections

<<<<<<< HEAD
    /// Kernel-exploit controls, moved here from the Inject screen. The chain is
    /// auto-run at the front of every inject; this is the manual fallback and
    /// the status read-out.
    @ViewBuilder
    private var exploit: some View {
        // Nothing to offer when this build is outside the chain's support; an
        // empty bordered group would just be a hole in the list.
        if case .unsupported = inject.exploitStatus {
            EmptyView()
        } else {
            SectionGroup(title: String(localized: "section_exploit"), symbol: "cpu") {
                exploitRow
            }
        }
    }

    /// Anti-ban: the checkbox drives a trace sweep of the panel's own residue
    /// in the container (probe leftovers, runtime debug log, engagement marker,
    /// signature strays), a timestamp-masking pass over the staged payload so
    /// a changed-file scan sees nothing newer than the app itself, and a
    /// session re-stamp. The same sweep also runs at the front of every inject
    /// while the switch is on. The staged patch and config are never removed.
    private var antiBanSection: some View {
        SectionGroup(title: String(localized: "section_anti_ban"), symbol: "shield.lefthalf.filled") {
            ToggleRow(
                label: String(localized: "anti_ban"),
                detail: String(localized: "anti_ban_caption"),
                isOn: menu.feature(\.antiBan)
            )

            HStack(spacing: 10) {
                if inject.isRunningAntiBan {
                    ProgressView()
                        .tint(Palette.accent)
                    Text("anti_ban_running")
                        .font(.footnote)
                        .foregroundStyle(Palette.textDim)
                } else {
                    Text(lastAntiBanText)
                        .font(.footnote)
                        .foregroundStyle(Palette.textDim)
                }
                Spacer(minLength: 8)
                Button {
                    Task { await inject.runAntiBan() }
                } label: {
                    Text("anti_ban_sweep_now")
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(inject.isRunningAntiBan)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, Metrics.rowPaddingH)
            .rowDivider()
        }
    }

    private var lastAntiBanText: String {
        guard let report = inject.antiBanReport else {
            return String(localized: "anti_ban_idle")
        }
        if report.removed.isEmpty && report.masked.isEmpty && report.flagged.isEmpty {
            return String(localized: "anti_ban_clean")
        }
        return String(
            format: String(localized: "anti_ban_summary"),
            report.removed.count,
            report.masked.count,
            report.flagged.count
        )
    }

    @ViewBuilder
    private var exploitRow: some View {
        if inject.isRunningExploit {
            HStack(spacing: 10) {
                ProgressView()
                Text("exploit_status_running")
                    .font(.footnote)
                    .foregroundStyle(Palette.textDim)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        } else {
            switch inject.exploitStatus {
            case .success:
                statusRow(
                    icon: "checkmark.seal.fill",
                    tint: Palette.good,
                    titleKey: "exploit_status_success",
                    buttonKey: "retry_exploit"
                )
            case .failed:
                VStack(alignment: .leading, spacing: 8) {
                    Banner(kind: .error, message: String(localized: "exploit_status_failed"))
                    Button("retry_exploit") { inject.runExploit() }
                        .buttonStyle(ChipButtonStyle())
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            case .notStarted:
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(inject.requiresSandboxEscape ? Palette.warn : Palette.textFaint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("exploit_status_not_started")
                            .font(.footnote.weight(.semibold))
                        Text(NSLocalizedString(inject.exploitHintKey, comment: ""))
                            .font(.caption2)
                            .foregroundStyle(Palette.textFaint)
                    }
                    Spacer(minLength: 0)
                    Button("run_exploit") { inject.runExploit() }
                        .buttonStyle(ChipButtonStyle())
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
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
            Spacer(minLength: 0)
            Button(buttonKey) { inject.runExploit() }
                .buttonStyle(ChipButtonStyle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private var licenseInfo: some View {
        SectionGroup(title: String(localized: "section_license_info"), symbol: "checkmark.seal") {
            InfoRow(label: String(localized: "setting_license"),
                    value: auth.status.displayKey ?? "—")

            InfoRow(label: String(localized: "validity"),
=======
    private var privacy: some View {
        SectionGroup(title: String(localized: "section_privacy")) {
            ToggleRow(
                label: String(localized: "stream_proof"),
                isOn: menu.feature(\.streamProof)
            )
        }
    }

    private var licenseInfo: some View {
        SectionGroup(title: String(localized: "section_license_info")) {
            infoRow(String(localized: "setting_license"),
                    value: auth.status.displayKey ?? "—")

            infoRow(String(localized: "validity"),
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
                    value: expiryRemaining)

            HStack(spacing: 10) {
                Text(String(localized: "uuid_label"))
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                Text(device.credentialId)
                    .font(.caption.monospaced())
<<<<<<< HEAD
                    .foregroundStyle(Palette.textDim)
=======
                    .foregroundStyle(.secondary)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    UIPasteboard.general.string = device.credentialId
                    copied = true
                } label: {
                    Text(copied ? String(localized: "copied") : String(localized: "copy"))
<<<<<<< HEAD
                }
                .buttonStyle(ChipButtonStyle())
            }
            .padding(.vertical, Metrics.rowPaddingV)
            .padding(.horizontal, Metrics.rowPaddingH)
=======
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
        }
    }

    private var compatibility: some View {
<<<<<<< HEAD
        SectionGroup(title: String(localized: "section_compat"), symbol: "iphone") {
            InfoRow(label: String(localized: "ios_version_current"),
=======
        SectionGroup(title: String(localized: "section_compat")) {
            infoRow(String(localized: "ios_version_current"),
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
                    value: "iOS \(device.iOSVersion)")
        }
    }

    private var languageSection: some View {
<<<<<<< HEAD
        SectionGroup(title: String(localized: "section_language"), symbol: "textformat") {
            ActionRow(symbol: "globe", label: language.selected.displayName) {
                language.hasChosen = false
            }
=======
        SectionGroup(title: String(localized: "section_language")) {
            Button {
                language.hasChosen = false
            } label: {
                HStack {
                    Text(language.selected.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
        }
    }

    private var support: some View {
<<<<<<< HEAD
        SectionGroup(title: String(localized: "section_support"), symbol: "questionmark.circle") {
            ActionRow(symbol: "bubble.left.and.bubble.right", label: String(localized: "support_discord")) {
=======
        SectionGroup(title: String(localized: "section_support")) {
            actionRow(String(localized: "support_discord"), tint: .primary) {
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
                guard let url = URL(string: supportURL) else { return }
                UIApplication.shared.open(url)
            }

<<<<<<< HEAD
            ActionRow(symbol: "doc.text.magnifyingglass", label: String(localized: "system_log")) {
                showLog = true
            }

            ActionRow(symbol: "rectangle.portrait.and.arrow.right", label: String(localized: "logout_account"), tint: Palette.bad) {
=======
            actionRow(String(localized: "system_log"), tint: .primary) {
                showLog = true
            }

            actionRow(String(localized: "logout_account"), tint: .red) {
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
                showLogout = true
            }
        }
    }

<<<<<<< HEAD
=======
    // MARK: - rows

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body.weight(.medium))
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }

    private func actionRow(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
    /// "30d 6h 52m" style countdown, as the mockup shows it.
    private var expiryRemaining: String {
        guard let expires = auth.status.expiresAt else { return "—" }
        let total = max(0, Int(expires.timeIntervalSinceNow))
        return "\(total / 86_400)d \((total % 86_400) / 3_600)h \((total % 3_600) / 60)m"
    }
}
