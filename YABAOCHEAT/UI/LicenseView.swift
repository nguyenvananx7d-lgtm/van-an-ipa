import SwiftUI

struct LicenseView: View {
    @EnvironmentObject var auth: AuthorizationStore
    @State private var key: String = ""
    @State private var reveal: Bool = false

    var body: some View {
        Card(padding: 18, radius: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("license")
                    .font(.headline)

                if auth.status.isOnline {
                    online
                } else {
                    offline
                }
            }
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

    private var offline: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("enter_license_key")
                        .font(.subheadline.weight(.semibold))
                    Text("license_key_hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    reveal.toggle()
                } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .font(.body)
                }
                .buttonStyle(.plain)
            }

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
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                )

                if auth.isRefreshing {
                    ProgressView()
                        .padding(.trailing, 10)
                }
            }

            Button {
                Task { await auth.submit(key: key) }
            } label: {
                Text("activate")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(auth.isRefreshing || key.isEmpty)

            if let msg = auth.revocationMessage {
                Banner(kind: .error, message: msg)
            }
        }
    }

    private var online: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text("license_valid")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.status.plan ?? "—")
                        .font(.body.weight(.semibold))
                    Text(auth.status.displayKey ?? "—")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let exp = auth.status.expiresAt {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("expires_at")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(exp, style: .date)
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }
}

