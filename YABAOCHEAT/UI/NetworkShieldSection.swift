import SwiftUI
import UIKit

/// Setting-tab section for the encrypted-DNS / tunnel layer.
///
/// The profile route is intentionally entitlement-free: it installs a
/// system-wide DoH configuration through Safari instead of shipping a Network
/// Extension the unsigned build could not load.
///
/// The main flow is one card + one button. Everything that is not needed for a
/// first install (tunnel gate, denylists, leak test, reinstall) lives behind
/// **Advanced**.
struct NetworkShieldSection: View {
    @StateObject private var shield = NetworkShield.shared
    @State private var showGuide = false
    @State private var showAdvanced = false

    var body: some View {
        SectionGroup(title: String(localized: "section_network"), symbol: "network") {
            statusRow
            actionBlock
            resolverRow

            if shield.provider == .nextdns {
                nextDNSField
            }
            if shield.provider == .custom {
                customURLField
            }

            if let message = shield.statusMessage {
                statusBanner(message)
            }

            advancedRow
            if showAdvanced {
                advancedContent
            }

            ActionRow(
                symbol: "book",
                label: String(localized: "dns_guide"),
                showsChevron: true
            ) {
                showGuide = true
            }
        }
        .onAppear { shield.refreshTunnel() }
        .sheet(isPresented: $showGuide) { guideSheet }
    }

    // MARK: - status

    private var statusRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: statusSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusTint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.text)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(Palette.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(statusBadge)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(statusTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(statusTint.opacity(0.12)))
                .overlay(Capsule().strokeBorder(statusTint.opacity(0.25), lineWidth: 1))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, Metrics.rowPaddingH)
        .rowDivider()
    }

    private var statusTitle: String {
        if !shield.isConfigured { return String(localized: "dns_state_choose") }
        switch shield.installStage {
        case .idle:      return String(localized: "dns_state_ready")
        case .pending:   return String(localized: "dns_state_pending")
        case .installed: return String(localized: "dns_state_installed")
        }
    }

    private var statusDetail: String {
        if !shield.isConfigured {
            return shield.provider == .nextdns
                ? String(localized: "dns_state_nextdns_detail")
                : String(localized: "dns_state_choose_detail")
        }
        switch shield.installStage {
        case .idle:
            return shield.provider.detail
        case .pending:
            return String(localized: "dns_state_pending_detail")
        case .installed:
            let vpn = shield.tunnelActive
                ? String(localized: "dns_tunnel_up")
                : String(localized: "dns_tunnel_down")
            return "\(shield.provider.title) · VPN \(vpn)"
        }
    }

    private var statusBadge: String {
        if !shield.isConfigured { return String(localized: "dns_badge_setup") }
        switch shield.installStage {
        case .idle:      return String(localized: "dns_badge_ready")
        case .pending:   return String(localized: "dns_badge_pending")
        case .installed: return String(localized: "dns_badge_on")
        }
    }

    private var statusTint: Color {
        if !shield.isConfigured { return Palette.warn }
        switch shield.installStage {
        case .idle:      return Palette.accent
        case .pending:   return Palette.warn
        case .installed: return Palette.good
        }
    }

    private var statusSymbol: String {
        if !shield.isConfigured { return "exclamationmark.shield" }
        switch shield.installStage {
        case .idle:      return "shield.lefthalf.filled"
        case .pending:   return "exclamationmark.shield.fill"
        case .installed: return "checkmark.shield.fill"
        }
    }

    // MARK: - primary action

    @ViewBuilder
    private var actionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !shield.isConfigured {
                primary(String(localized: "dns_install_profile"),
                        symbol: "arrow.down.circle",
                        disabled: true) {}
                hint(unconfiguredHint)
            } else {
                switch shield.installStage {
                case .idle:
                    primary(String(localized: "dns_install_profile"),
                            symbol: "arrow.down.circle",
                            busy: shield.isInstalling) {
                        shield.installProfile()
                    }
                    hint(String(localized: "dns_install_hint"))

                case .pending:
                    primary(String(localized: "dns_action_settings"), symbol: "gear") {
                        shield.openSettings()
                    }
                    HStack(spacing: 8) {
                        chip(String(localized: "dns_action_done"), symbol: "checkmark") {
                            shield.markProfileInstalled()
                        }
                        chip(String(localized: "dns_action_reinstall"), symbol: "arrow.clockwise") {
                            shield.installProfile()
                        }
                    }

                case .installed:
                    primary(String(localized: "dns_test"),
                            symbol: "waveform.path.ecg",
                            busy: shield.isTesting) {
                        Task { await shield.testResolver() }
                    }
                    HStack(spacing: 8) {
                        chip(String(localized: "dns_action_reinstall"), symbol: "arrow.clockwise") {
                            shield.installProfile()
                        }
                        chip(String(localized: "dns_leak_test"), symbol: "safari") {
                            shield.openLeakTest()
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Metrics.rowPaddingH)
        .rowDivider()
    }

    private var unconfiguredHint: String {
        shield.provider == .nextdns
            ? String(localized: "dns_state_nextdns_detail")
            : String(localized: "dns_state_choose_detail")
    }

    private func primary(
        _ title: String,
        symbol: String,
        busy: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView()
                        .tint(Palette.void)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(AccentButtonStyle())
        .disabled(busy || disabled)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Palette.textFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
            }
        }
        .buttonStyle(ChipButtonStyle())
    }

    // MARK: - resolver

    private var resolverRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(DNSProvider.allCases) { option in
                    Button {
                        shield.provider = option
                    } label: {
                        if option == shield.provider {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "dns_provider"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.text)
                        Text(shield.provider.detail)
                            .font(.caption)
                            .foregroundStyle(Palette.textFaint)
                    }
                    Spacer(minLength: 8)
                    Text(shield.provider.title)
                        .font(.caption)
                        .foregroundStyle(Palette.textDim)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.textFaint)
                }
                .padding(.vertical, Metrics.rowPaddingV)
                .padding(.horizontal, Metrics.rowPaddingH)
                .contentShape(Rectangle())
            }

            Text(String(localized: "dns_resolver_hint"))
                .font(.caption2)
                .foregroundStyle(Palette.textFaint)
                .padding(.horizontal, Metrics.rowPaddingH)
                .padding(.bottom, 10)
        }
        .rowDivider()
    }

    // MARK: - fields

    private var nextDNSField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(localized: "dns_nextdns_id"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.textDim)
                Spacer(minLength: 8)
                if shield.isNextDNSValid {
                    Label(String(localized: "dns_valid"), systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.good)
                }
            }

            HStack(spacing: 8) {
                TextField("abc123", text: $shield.nextDNSID)
                    .font(.system(.body, design: .monospaced))
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                            .fill(Palette.well)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
                    .onSubmit { shield.setNextDNSID(shield.nextDNSID) }

                Button {
                    if let raw = UIPasteboard.general.string {
                        shield.setNextDNSID(raw)
                    }
                } label: {
                    Text(String(localized: "dns_paste"))
                }
                .buttonStyle(ChipButtonStyle())
            }

            HStack(alignment: .top, spacing: 8) {
                Button {
                    shield.openNextDNS()
                } label: {
                    Text(String(localized: "dns_get_id"))
                }
                .buttonStyle(ChipButtonStyle())

                Text(String(localized: "dns_nextdns_help"))
                    .font(.caption2)
                    .foregroundStyle(Palette.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Metrics.rowPaddingV)
        .padding(.horizontal, Metrics.rowPaddingH)
        .rowDivider()
    }

    private var customURLField: some View {
        fieldRow(
            title: String(localized: "dns_custom_url"),
            hint: String(localized: "dns_custom_hint"),
            placeholder: "https://dns.example.com/dns-query",
            text: $shield.customURL,
            keyboard: .URL
        )
    }

    private func fieldRow(
        title: String,
        hint: String?,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.textDim)
            TextField(placeholder, text: text)
                .font(.system(.body, design: .monospaced))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .fill(Palette.well)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(Palette.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Metrics.rowPaddingV)
        .padding(.horizontal, Metrics.rowPaddingH)
        .rowDivider()
    }

    private func statusBanner(_ message: String) -> some View {
        Banner(kind: bannerKind, message: message)
            .padding(.horizontal, Metrics.rowPaddingH)
            .padding(.vertical, 10)
            .rowDivider()
    }

    private var bannerKind: Banner.Kind {
        switch shield.statusTone {
        case .ok, .info: return .info
        case .warn:      return .warning
        case .error:     return .error
        }
    }

    // MARK: - advanced

    private var advancedRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                showAdvanced.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text.opacity(0.9))
                    .frame(width: 20, alignment: .center)
                Text(String(localized: "dns_advanced"))
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.textFaint)
            }
            .padding(.vertical, Metrics.rowPaddingV)
            .padding(.horizontal, Metrics.rowPaddingH)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowDivider()
    }

    @ViewBuilder
    private var advancedContent: some View {
        ToggleRow(
            label: String(localized: "dns_check_before_inject"),
            detail: String(localized: "dns_check_before_inject_caption"),
            isOn: $shield.isEnabled
        )

        InfoRow(
            label: String(localized: "dns_tunnel"),
            value: shield.tunnelActive
                ? String(localized: "dns_tunnel_up")
                : String(localized: "dns_tunnel_down")
        )

        ToggleRow(
            label: String(localized: "dns_require_tunnel"),
            detail: String(localized: "dns_require_tunnel_caption"),
            isOn: $shield.requireTunnelBeforeInject
        )

        if shield.provider == .nextdns {
            ActionRow(
                symbol: "doc.on.doc",
                label: String(localized: "dns_copy_blocklist"),
                showsChevron: false
            ) {
                shield.copyBlocklist()
            }

            ActionRow(
                symbol: "safari",
                label: String(localized: "dns_open_nextdns")
            ) {
                shield.openNextDNS()
            }
        }

        ActionRow(
            symbol: "safari",
            label: String(localized: "dns_leak_test")
        ) {
            shield.openLeakTest()
        }

        if shield.isConfigured {
            ActionRow(
                symbol: "arrow.clockwise",
                label: String(localized: "dns_action_reinstall")
            ) {
                shield.installProfile()
            }
        }
    }

    // MARK: - guide

    private var guideSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Banner(
                        kind: .warning,
                        message: String(localized: "dns_guide_warning")
                    )

                    guideBlock(
                        String(localized: "dns_guide_steps_title"),
                        [
                            String(localized: "dns_guide_step_1"),
                            String(localized: "dns_guide_step_2"),
                            String(localized: "dns_guide_step_3"),
                            String(localized: "dns_guide_step_4"),
                            String(localized: "dns_guide_step_5")
                        ]
                    )

                    guideBlock(
                        String(localized: "dns_guide_publisher_title"),
                        [
                            String(localized: "dns_guide_publisher_1"),
                            String(localized: "dns_guide_publisher_2"),
                            String(localized: "dns_guide_publisher_3")
                        ]
                    )

                    guideBlock(
                        String(localized: "dns_guide_limits_title"),
                        [
                            String(localized: "dns_guide_limit_1"),
                            String(localized: "dns_guide_limit_2"),
                            String(localized: "dns_guide_limit_3")
                        ]
                    )

                    guideBlock(
                        String(localized: "dns_guide_remove_title"),
                        [String(localized: "dns_guide_remove_1")]
                    )
                }
                .padding(20)
            }
            .background(ThemeBackground())
            .navigationTitle(String(localized: "dns_guide_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "done")) { showGuide = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func guideBlock(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Palette.accent.opacity(0.8))
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
