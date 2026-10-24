import SwiftUI
import UIKit

/// Setting tab — the kernel-exploit controls, license facts, compatibility,
/// language, support.
struct SettingView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var inject: InjectStore
    @EnvironmentObject var menu: MenuStore

    @State private var showLogout: Bool = false
    @State private var showLog: Bool = false
    @State private var copied: Bool = false

    /// Swap for the real invite when the server side settles.
    private let supportURL = "https://discord.gg/hcx7aP4XSp"

    private var device: DeviceIdentityProvider { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.stack) {
            exploit
            antiBanSection
            NetworkShieldSection()
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
        .onChange(of: menu.controls.antiBan) { newValue in
            if newValue {
                Task { await inject.runAntiBan() }
            } else {
                Task { await inject.stopAntiBanGuard() }
            }
        }
    }

    // MARK: - sections

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
            if inject.isGuardingAntiBan {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(Palette.good)
                    Text("anti_ban_live_guard")
                        .font(.footnote)
                        .foregroundStyle(Palette.textDim)
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 11)
                .padding(.horizontal, Metrics.rowPaddingH)
                .rowDivider()
            }
        }
    }
    private var lastAntiBanText: String {
        guard let report = inject.antiBanReport else {
            return String(localized: "anti_ban_idle")
        }
        // `isEmpty` covers the directory stamps, kernel ctime forge and content
        // scrub as well; checking only three fields reported "clean" while the
        // sweep had in fact done work on the other three channels.
        if report.isEmpty {
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
                    value: expiryRemaining)

            HStack(spacing: 10) {
                Text(String(localized: "uuid_label"))
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                Text(device.credentialId)
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    UIPasteboard.general.string = device.credentialId
                    copied = true
                } label: {
                    Text(copied ? String(localized: "copied") : String(localized: "copy"))
                }
                .buttonStyle(ChipButtonStyle())
            }
            .padding(.vertical, Metrics.rowPaddingV)
            .padding(.horizontal, Metrics.rowPaddingH)
        }
    }

    private var compatibility: some View {
        SectionGroup(title: String(localized: "section_compat"), symbol: "iphone") {
            InfoRow(label: String(localized: "ios_version_current"),
                    value: "iOS \(device.iOSVersion)")
        }
    }

    private var languageSection: some View {
        SectionGroup(title: String(localized: "section_language"), symbol: "textformat") {
            ActionRow(symbol: "globe", label: language.selected.displayName) {
                language.hasChosen = false
            }
        }
    }

    private var support: some View {
        SectionGroup(title: String(localized: "section_support"), symbol: "questionmark.circle") {
            ActionRow(symbol: "bubble.left.and.bubble.right", label: String(localized: "support_discord")) {
                guard let url = URL(string: supportURL) else { return }
                UIApplication.shared.open(url)
            }

            ActionRow(symbol: "doc.text.magnifyingglass", label: String(localized: "system_log")) {
                showLog = true
            }
            ActionRow(symbol: "rectangle.portrait.and.arrow.right", label: String(localized: "logout_account"), tint: Palette.bad) {
                showLogout = true
            }
        }
    }

    /// "30d 6h 52m" style countdown, as the mockup shows it.
    private var expiryRemaining: String {
        guard let expires = auth.status.expiresAt else { return "—" }
        let total = max(0, Int(expires.timeIntervalSinceNow))
        return "\(total / 86_400)d \((total % 86_400) / 3_600)h \((total % 3_600) / 60)m"
    }
}
