import SwiftUI

<<<<<<< HEAD
/// Full-screen license gate: brand, hint, key field, submit, language chip.
/// Shown whenever there is no valid session.
=======
/// Full-screen license gate from the mockup: brand, hint, key field, submit,
/// language chip. Shown whenever there is no valid session.
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
struct LicenseView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore

    @State private var key: String = ""
    @State private var reveal: Bool = false
<<<<<<< HEAD
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
=======

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 32)

            Mark(size: 88)

            VStack(spacing: 6) {
                Text("app_title")
                    .font(.largeTitle.weight(.bold))
                Text("gate_hint")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            field
                .padding(.top, 6)

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
        .background(Color(.systemGroupedBackground))
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
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
<<<<<<< HEAD
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
=======
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
            )

            HStack(spacing: 10) {
                if auth.isRefreshing {
                    ProgressView()
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
                }
                Button {
                    reveal.toggle()
                } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .font(.body)
<<<<<<< HEAD
                        .foregroundStyle(Palette.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 16)
=======
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 14)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
        }
    }

    private var submit: some View {
        Button {
            Task { await auth.submit(key: key) }
        } label: {
            Text("gate_submit")
                .font(.headline)
                .frame(maxWidth: .infinity)
<<<<<<< HEAD
                .padding(.vertical, 16)
        }
        .buttonStyle(AccentButtonStyle())
=======
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
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
<<<<<<< HEAD
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                .foregroundStyle(Palette.textDim)
=======
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .foregroundStyle(.secondary)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
        }
        .buttonStyle(.plain)
    }
}
