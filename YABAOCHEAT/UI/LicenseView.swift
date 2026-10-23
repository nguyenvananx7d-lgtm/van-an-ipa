import SwiftUI

/// Full-screen license gate: brand, hint, key field, submit, language chip.
/// Shown whenever there is no valid session.
struct LicenseView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore

    @State private var key: String = ""
    @State private var reveal: Bool = false
    @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            ThemeBackground()
            VStack(spacing: 20) {
                Spacer(minLength: 32)
                Mark(size: 92)
                VStack(spacing: 6) {
                    Text("app_title")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Palette.text)
                    Text("gate_hint")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textDim)
                }
                field
                    .padding(.top, 8)
                submit
                if let msg = auth.revocationMessage {
                    Banner(kind: .error, message: msg)
                }
                Spacer(minLength: 24)
                HStack {
                    Spacer()
                    languageChip
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if auth.status == .unknown {
                auth.revalidate()
            }
        }
        .onChange(of: auth.status.displayKey) { new in
            if auth.status.isOnline, let new {
                key = new
            }
        }
    }

    // MARK: - pieces

    private var field: some View {
        ZStack(alignment: .trailing) {
            Group {
                if reveal {
                    TextField("key_placeholder", text: $key)
                        .textInputAutocapitalization(.none)
                        .autocorrectionDisabled(true)
                } else {
                    SecureField("key_placeholder", text: $key)
                        .textInputAutocapitalization(.none)
                        .autocorrectionDisabled(true)
                }
            }
            .focused($focused)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .insetWell(radius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        focused ? Palette.accent.opacity(0.7) : Color.clear,
                        lineWidth: 1
                    )
            )
            .shadow(color: focused ? Palette.accent.opacity(0.16) : .clear, radius: 12)
            .animation(.easeInOut(duration: 0.2), value: focused)
            HStack(spacing: 12) {
                if auth.isRefreshing {
                    ProgressView().tint(Palette.accent)
                }
                Button {
                    reveal.toggle()
                } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .font(.body)
                        .foregroundStyle(Palette.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 16)
        }
    }

    private var submit: some View {
        Button {
            Task { await auth.submit(key: key) }
        } label: {
            Text("gate_submit")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(AccentButtonStyle())
        .disabled(auth.isRefreshing || key.isEmpty)
    }

    private var languageChip: some View {
        Button {
            language.hasChosen = false
        } label: {
            Text(String(language.selected.rawValue.prefix(3)).uppercased())
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                .foregroundStyle(Palette.textDim)
        }
        .buttonStyle(.plain)
    }
}
