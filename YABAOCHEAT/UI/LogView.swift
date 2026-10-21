import SwiftUI

/// Diagnostic log. Filterable by subsystem, shareable, and copyable — the whole
/// point of the subsystem tags is that a user can hand back just the failing one.
struct LogView: View {
    @StateObject private var log = AppLog.shared
    @State private var filter: AppLog.Entry.Subsystem?
    @State private var copied = false
    @State private var showShare = false

    private var entries: [AppLog.Entry] {
        guard let filter else { return log.entries }
        return log.entries.filter { $0.subsystem == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            bar

            if entries.isEmpty {
                Spacer()
<<<<<<< HEAD
                VStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .font(.title3)
                        .foregroundStyle(Palette.textFaint)
                    Text("log_empty")
                        .font(.footnote)
                        .foregroundStyle(Palette.textDim)
                }
                .frame(maxWidth: .infinity)
=======
                Text("log_empty")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
                Spacer()
            } else {
                List(entries) { entry in
                    row(entry)
<<<<<<< HEAD
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .background(Palette.base)
=======
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemGroupedBackground))
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
        .onChange(of: log.entries.count) { _ in log.flush() }
    }

    private var bar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("all") { filter = nil }
                Divider()
                ForEach(AppLog.Entry.Subsystem.allCases, id: \.self) { sub in
                    Button(sub.rawValue) { filter = sub }
                }
            } label: {
                Label(filter?.rawValue ?? "all", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.semibold))
            }

            Spacer()

            if copied {
                Label("copied", systemImage: "checkmark")
                    .font(.caption)
<<<<<<< HEAD
                    .foregroundStyle(Palette.good)
=======
                    .foregroundStyle(.green)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
            }

            Button {
                UIPasteboard.general.string = log.plainText
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .disabled(entries.isEmpty)

            Button {
                showShare = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(entries.isEmpty)

            Button {
                log.clear()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
<<<<<<< HEAD
        .background(Palette.surface)
=======
        .background(Color(.secondarySystemBackground))
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [log.plainText])
        }
    }

    private func row(_ entry: AppLog.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.date, style: .time)
                .font(.caption2.monospacedDigit())
<<<<<<< HEAD
                .foregroundStyle(Palette.textFaint)
=======
                .foregroundStyle(.secondary)
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
                .frame(width: 58, alignment: .leading)

            Text(entry.subsystem.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tone(entry.subsystem))
                .frame(width: 66, alignment: .leading)

            Text(entry.message)
                .font(.caption)
<<<<<<< HEAD
                .foregroundStyle(Palette.text)
=======
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func tone(_ sub: AppLog.Entry.Subsystem) -> Color {
        switch sub {
<<<<<<< HEAD
        case .auth:      return Palette.info
        case .kernelRW:  return Palette.accent
        case .sandbox:   return Palette.info
        case .mcm:       return Palette.good
        case .integrity: return Palette.warn
        case .wipe:      return Palette.bad
        case .antiBan:   return Palette.good
        case .live:      return Palette.good
        case .runtime:   return Palette.accentHi
        case .launch:    return Palette.textDim
=======
        case .auth:      return .blue
        case .kernelRW:  return .purple
        case .sandbox:   return .indigo
        case .mcm:       return .teal
        case .integrity: return .orange
        case .wipe:      return .red
        case .live:      return .green
        case .runtime:   return .mint
        case .launch:    return .pink
>>>>>>> b0d56334c5649e0874daa34370ceed5e421e6210
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension AppLog {
    static let shared = AppLog()
}
