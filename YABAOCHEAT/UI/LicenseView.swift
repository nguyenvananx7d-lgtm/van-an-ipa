import SwiftUI

/// Full-screen license gate from the mockup: brand, hint, key field, submit,
/// language chip. Shown whenever there is no valid session.
struct LicenseView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @EnvironmentObject var language: LanguageStore

    @State private var key: String = ""
    @State private var reveal: Bool = false

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
                }
                Button {
                    reveal.toggle()
                } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 14)
        }
    }

    private var submit: some View {
        Button {
            Task { await auth.submit(key: key) }
        } label: {
            Text("gate_submit")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
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
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
