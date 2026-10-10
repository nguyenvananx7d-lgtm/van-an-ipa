import SwiftUI
import UIKit

/// Setting tab — the kernel-exploit controls, license facts, compatibility,
/// language, support.
struct SettingView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var inject: InjectStore

    @State private var showLogout: Bool = false
    @State private var showLog: Bool = false
    @State private var copied: Bool = false

    /// Swap for the real invite when the server side settles.
    private let supportURL = "https://discord.com/invite/vortexarena"

    private var device: DeviceIdentityProvider { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            exploit
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
    }

    // MARK: - sections

    /// Kernel-exploit controls, moved here from the Inject screen. The chain is
    /// auto-run at the front of every inject; this is the manual fallback and
    /// the status read-out.
    private var exploit: some View {
        SectionGroup(title: String(localized: "section_exploit")) {
            exploitRow
        }
    }

    @ViewBuilder
    private var exploitRow: some View {
        if inject.isRunningExploit {
            HStack(spacing: 10) {
                ProgressView()
                Text("exploit_status_running")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
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
                    Banner(kind: .error, message: String(localized: "exploit_status_failed"))
                    Button("retry_exploit") { inject.runExploit() }
                        .buttonStyle(ChipButtonStyle())
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
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
        SectionGroup(title: String(localized: "section_license_info")) {
            infoRow(String(localized: "setting_license"),
                    value: auth.status.displayKey ?? "—")

            infoRow(String(localized: "validity"),
                    value: expiryRemaining)

            HStack(spacing: 10) {
                Text(String(localized: "uuid_label"))
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                Text(device.credentialId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
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
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
    }

    private var compatibility: some View {
        SectionGroup(title: String(localized: "section_compat")) {
            infoRow(String(localized: "ios_version_current"),
                    value: "iOS \(device.iOSVersion)")
        }
    }

    private var languageSection: some View {
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
        }
    }

    private var support: some View {
        SectionGroup(title: String(localized: "section_support")) {
            actionRow(String(localized: "support_discord"), tint: .primary) {
                guard let url = URL(string: supportURL) else { return }
                UIApplication.shared.open(url)
            }

            actionRow(String(localized: "system_log"), tint: .primary) {
                showLog = true
            }

            actionRow(String(localized: "logout_account"), tint: .red) {
                showLogout = true
            }
        }
    }

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

    /// "30d 6h 52m" style countdown, as the mockup shows it.
    private var expiryRemaining: String {
        guard let expires = auth.status.expiresAt else { return "—" }
        let total = max(0, Int(expires.timeIntervalSinceNow))
        return "\(total / 86_400)d \((total % 86_400) / 3_600)h \((total % 3_600) / 60)m"
    }
}
