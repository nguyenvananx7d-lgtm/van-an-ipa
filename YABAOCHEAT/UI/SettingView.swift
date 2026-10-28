import SwiftUI
import UIKit

/// Setting tab — session order: relay, anti-ban, exploit, then account facts,
/// compatibility, language and support.
struct SettingView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var inject: InjectStore
    @EnvironmentObject var menu: MenuStore

    @State private var showLogout: Bool = false
    @State private var showLog: Bool = false
    @State private var copied: Bool = false

    /// Relay host as typed by the user (`host`, `host:port` or a full URL).
    @AppStorage("relay.host") private var relayHost: String = ""
    /// Last probe result, shown under the Check button.
    @State private var relayProbe: String = ""

    /// Swap for the real invite when the server side settles.
    private let supportURL = "https://discord.gg/hcx7aP4XSp"

    private var device: DeviceIdentityProvider { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.stack) {
            // Order is by what a session actually touches: the relay that makes
            // the traffic work, the sweep that keeps the container clean, the
            // exploit that opens the path, then account facts and preferences.
            // The old network-shield block lived here; it is gone, because the
            // relay owns traffic now and two overlapping network screens made
            // the same settings look like they contradicted each other.
            relaySection
            antiBanSection
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
                nativeHookRow
                trafficRow
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
            ToggleRow(
                label: String(localized: "consume_payload"),
                detail: String(localized: "consume_payload_caption"),
                isOn: menu.feature(\.consumePayload)
            )
            ToggleRow(
                label: String(localized: "modern_inject"),
                detail: String(localized: "modern_inject_caption"),
                isOn: menu.feature(\.preferModernInjection)
            )
            HStack(spacing: 10) {
                Text(String(localized: "safe_profile_caption"))
                    .font(.ui(13))
                    .foregroundStyle(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    menu.applySafeProfile()
                } label: {
                    Text(String(localized: "safe_profile"))
                }
                .buttonStyle(ChipButtonStyle())
            }
            .padding(.horizontal, Metrics.rowPaddingH)
            .padding(.vertical, 11)
            .rowDivider()
            HStack(spacing: 10) {
                if inject.isRunningAntiBan {
                    ProgressView()
                        .tint(Palette.accent)
                    Text("anti_ban_running")
                        .font(.ui(13))
                        .foregroundStyle(Palette.textDim)
                } else {
                    Text(lastAntiBanText)
                        .font(.ui(13))
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
                        .font(.ui(12))
                        .foregroundStyle(Palette.good)
                    Text("anti_ban_live_guard")
                        .font(.ui(13))
                        .foregroundStyle(Palette.textDim)
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 11)
                .padding(.horizontal, Metrics.rowPaddingH)
                .rowDivider()
            }
        }
    }
    // MARK: - relay

    /// One-tap install for the TLS relay profile.
    ///
    /// The relay (`ffxc-auth/src/proxy`) is the model that leaves the game binary
    /// alone: the device trusts one certificate, its traffic goes through the
    /// relay, and the anti-cheat report is edited in transit instead of the
    /// client being patched. The MIZZE flow lives on the Setup screen; this
    /// section is the shortcut for the same endpoints while the advanced tools
    /// are open.
    private var relayCertificateURL: URL? {
        RelayActivationClient.certificateURL(host: relayHost)
    }

    private var relayProfileURL: URL? {
        RelayActivationClient.profileURL(host: relayHost)
    }

    private var relayPortalURL: URL? {
        RelayActivationClient.loginURL(
            host: relayHost,
            key: auth.status.displayKey ?? "",
            deviceKey: device.activationId
        )
    }

    private var relayProbeURL: URL? {
        RelayActivationClient.baseURL(from: relayHost)?.appendingPathComponent("state")
    }

    /// One round of truth from the relay: it answers with the capture count, so
    /// "did my traffic reach it?" is a button instead of a guess.
    private func probeRelay() {
        guard let url = relayProbeURL else { return }
        relayProbe = String(localized: "relay_checking")
        Task {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let captures = object?["captures"] as? [String: Any]
                let count = captures?["total"] as? Int
                await MainActor.run {
                    if code == 200, let count {
                        relayProbe = String(format: String(localized: "relay_probe_ok"), count)
                    } else {
                        relayProbe = String(format: String(localized: "relay_probe_http"), code)
                    }
                }
            } catch {
                await MainActor.run {
                    relayProbe = String(
                        format: String(localized: "relay_probe_fail"),
                        error.localizedDescription
                    )
                }
            }
        }
    }

    private var relaySection: some View {
        SectionGroup(title: String(localized: "section_relay"), symbol: "network") {
            HStack(spacing: 10) {
                TextField(String(localized: "relay_host_placeholder"), text: $relayHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.ui(15))
                if !relayHost.isEmpty {
                    Button {
                        relayHost = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, Metrics.rowPaddingH)
            .rowDivider()

            HStack(spacing: 8) {
                Button {
                    if let url = relayCertificateURL { UIApplication.shared.open(url) }
                } label: {
                    Label("Chứng chỉ", systemImage: "checkmark.shield")
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(relayCertificateURL == nil)

                Button {
                    if let url = relayPortalURL { UIApplication.shared.open(url) }
                } label: {
                    Label("Portal", systemImage: "person.badge.key")
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(relayPortalURL == nil)

                Button {
                    if let url = relayProfileURL { UIApplication.shared.open(url) }
                } label: {
                    Label("Profile", systemImage: "arrow.down.circle")
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(relayProfileURL == nil)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.rowPaddingH)
            .padding(.vertical, 11)
            .rowDivider()

            Text("Cài chứng chỉ, bật Super Proxy với địa chỉ bên dưới, rồi đăng nhập portal bằng Key, Mật khẩu và ID máy. Tin cậy chứng chỉ trong Settings → General → About → Certificate Trust Settings. Profile chỉ cần khi bạn muốn cấu hình proxy/tunnel tự động.")
                .font(.ui(12))
                .foregroundStyle(Palette.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.rowPaddingH)
                .padding(.vertical, 11)
                .rowDivider()

            HStack(spacing: 10) {
                Text(RelayActivationClient.proxyEndpoint(from: relayHost) ?? String(localized: "relay_check_caption"))
                    .font(.ui(13))
                    .foregroundStyle(Palette.textDim)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let endpoint = RelayActivationClient.proxyEndpoint(from: relayHost) {
                    Button {
                        UIPasteboard.general.string = endpoint
                    } label: {
                        Label("Chép", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(ChipButtonStyle())
                }
            }
            .padding(.horizontal, Metrics.rowPaddingH)
            .padding(.vertical, 11)
            .rowDivider()

            HStack(spacing: 10) {
                Text(relayProbe.isEmpty ? String(localized: "relay_check_caption") : relayProbe)
                    .font(.ui(13))
                    .foregroundStyle(relayProbe.isEmpty ? Palette.textDim : Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    probeRelay()
                } label: {
                    Text(String(localized: "relay_check"))
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(relayProbeURL == nil)
            }
            .padding(.horizontal, Metrics.rowPaddingH)
            .padding(.vertical, 11)
            .rowDivider()
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
                    .font(.ui(13))
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
                            .font(.ui(13, weight: .semibold))
                        Text(NSLocalizedString(inject.exploitHintKey, comment: ""))
                            .font(.ui(11))
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
                .font(.ui(13))
            Spacer(minLength: 0)
            Button(buttonKey) { inject.runExploit() }
                .buttonStyle(ChipButtonStyle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    /// Stage-1 of the native hook route (NATIVE_HOOK.md). Only meaningful once
    /// the exploit stage has won; the button plants the branch stub and reads
    /// the trampoline marker back. Everything lands in the log screen.
    private var nativeHookRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(inject.kernelReady ? Palette.good : Palette.textFaint)
            VStack(alignment: .leading, spacing: 2) {
                Text("native_hook_title")
                    .font(.ui(13, weight: .semibold))
                Text("native_hook_caption")
                    .font(.ui(11))
                    .foregroundStyle(Palette.textFaint)
            }
            Spacer(minLength: 0)
            Button("native_hook_run") { inject.runNativeHook() }
                .buttonStyle(ChipButtonStyle())
                .disabled(!inject.kernelReady)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    /// Hotfix channel (NATIVE_HOOK.md §5): the one route that exists on every
    /// iOS — 17 through 27 — because it rides the game's own loader through the
    /// relay instead of a kernel primitive. This row reports readiness.
    private var trafficRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(inject.trafficReport.contains("armed")
                                     ? Palette.good : Palette.textFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("hotfix_title")
                        .font(.ui(13, weight: .semibold))
                    Text("hotfix_caption")
                        .font(.ui(11))
                        .foregroundStyle(Palette.textFaint)
                }
                Spacer(minLength: 0)
                Button("hotfix_check") { inject.runTrafficCheck() }
                    .buttonStyle(ChipButtonStyle())
                    .disabled(inject.checkingTraffic)
            }
            if !inject.trafficReport.isEmpty {
                Text(inject.trafficReport)
                    .font(.ui(11))
                    .foregroundStyle(Palette.textDim)
            }
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
                    .font(.ui(15, weight: .medium))
                Spacer(minLength: 8)
                Text(device.credentialId)
                    .font(.ui(12))
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
