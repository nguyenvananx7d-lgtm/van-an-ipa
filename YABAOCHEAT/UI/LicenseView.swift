import SwiftUI
import UIKit

/// Activation gate in the MIZZE 4.0 shape: Key, Mật khẩu, ID máy (64 ký tự),
/// Enter, and the reset footnote. The relay host sits below the three fields
/// because this build is self-hosted; it is the only value the reference
/// product bakes into its portal link.
///
/// The form submits through the relay (`POST /menu/login`). With no relay
/// configured the store falls back to the local adoption path, which is kept
/// for development but is no longer the flow the setup screen recommends.
struct LicenseView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore

    @State private var key: String = ""
    @State private var password: String = ""
    @State private var host: String = ""
    @State private var revealKey: Bool = false
    @State private var revealPassword: Bool = false
    @State private var copied: Bool = false
    @State private var formError: String?

    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case key
        case password
        case host
    }

    private var device: DeviceIdentityProvider { .shared }

    var body: some View {
        ZStack {
            ThemeBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: Metrics.stack) {
                    brand
                        .padding(.top, 26)

                    card

                    if let notice = auth.noticeMessage {
                        Banner(kind: .info, message: notice)
                    }
                    if let message = formError ?? auth.revocationMessage {
                        Banner(kind: .error, message: message)
                    }

                    footer
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 26)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if host.isEmpty { host = RelayActivationClient.configuredHost }
            if auth.status == .unknown {
                auth.revalidate()
            }
        }
        .onChange(of: auth.status.displayKey) { new in
            if let new, key.isEmpty { key = new }
        }
        .onChange(of: focus) { _ in
            formError = nil
        }
    }

    // MARK: - brand

    private var brand: some View {
        VStack(spacing: 12) {
            Mark(size: 78)
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("VORTEX ARENA")
                        .font(.system(size: 23, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Palette.text)
                    Text("®")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textFaint)
                        .baselineOffset(9)
                }
                Text("Kích hoạt menu")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textDim)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - form

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 6, height: 6)
                Text("ĐĂNG NHẬP")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(Palette.textFaint)
                Spacer()
                Text("MIZZE 4.0")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(Palette.textFaint)
            }

            field(title: "Key") {
                HStack(spacing: 10) {
                    Group {
                        if revealKey {
                            TextField("VT-XXXX-XXXX", text: $key)
                        } else {
                            SecureField("VT-XXXX-XXXX", text: $key)
                        }
                    }
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($focus, equals: .key)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Palette.text)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }

                    eyeButton(isRevealed: revealKey) { revealKey.toggle() }
                }
                .fieldWell(focused: focus == .key)
            }

            field(title: "Mật khẩu") {
                HStack(spacing: 10) {
                    Group {
                        if revealPassword {
                            TextField("Mật khẩu", text: $password)
                        } else {
                            SecureField("Mật khẩu", text: $password)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($focus, equals: .password)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Palette.text)
                    .submitLabel(.go)
                    .onSubmit { submit() }

                    eyeButton(isRevealed: revealPassword) { revealPassword.toggle() }
                }
                .fieldWell(focused: focus == .password)
            }

            field(title: "ID máy") {
                HStack(alignment: .top, spacing: 10) {
                    Text(device.activationId)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.textDim)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 7) {
                        Button {
                            UIPasteboard.general.string = device.activationId
                            copied = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(copied ? Palette.good : Palette.accent)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Palette.surfaceHi)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Sao chép ID máy")
                        Text("\(device.activationId.count)/64")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Palette.textFaint)
                    }
                }
                .frame(minHeight: 58, alignment: .top)
                .fieldWell(focused: false)
            }

            field(title: "Máy chủ relay") {
                TextField("relay.example.com", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focus, equals: .host)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Palette.text)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .fieldWell(focused: focus == .host)
            }

            Button(action: submit) {
                HStack(spacing: 9) {
                    if auth.isRefreshing {
                        ProgressView()
                            .tint(Palette.void)
                            .scaleEffect(0.85)
                    }
                    Text("Enter")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(auth.isRefreshing)

            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .semibold))
                Text("Reset thiết bị · 2 lần mỗi ngày")
            }
            .font(.caption)
            .foregroundStyle(Palette.textFaint)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 1)
        }
        .padding(18)
        .machined(radius: 18)
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textDim)
            content()
        }
    }

    private func eyeButton(isRevealed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isRevealed ? "eye.slash" : "eye")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textFaint)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    // MARK: - footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                language.hasChosen = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .semibold))
                    Text(language.selected.displayName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(Palette.textDim)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text("VORTEX © 2026")
                .font(.caption2.monospaced())
                .foregroundStyle(Palette.textFaint)
        }
        .padding(.top, 2)
    }

    // MARK: - action

    private func submit() {
        focus = nil
        formError = nil
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            formError = "Nhập key trước."
            return
        }
        guard !trimmedHost.isEmpty else {
            formError = "Nhập máy chủ relay (ví dụ: relay.example.com)."
            return
        }
        guard !password.isEmpty else {
            formError = "Nhập mật khẩu đi kèm key."
            return
        }

        UserDefaults.standard.set(trimmedHost, forKey: "relay.host")
        Task { await auth.submit(key: trimmedKey, password: password) }
    }
}

// MARK: - shared field chrome

private extension View {
    /// The recessed field surface used by the activation form, with the accent
    /// edge only on the field that currently owns the keyboard.
    func fieldWell(focused: Bool) -> some View {
        self
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .insetWell(radius: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        focused ? Palette.accent.opacity(0.7) : Color.clear,
                        lineWidth: 1
                    )
            )
            .shadow(color: focused ? Palette.accent.opacity(0.16) : .clear, radius: 10)
            .animation(.easeInOut(duration: 0.18), value: focused)
    }
}
