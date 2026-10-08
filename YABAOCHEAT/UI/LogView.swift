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
                Text("log_empty")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(entries) { entry in
                    row(entry)
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemGroupedBackground))
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
                    .foregroundStyle(.green)
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
        .background(Color(.secondarySystemBackground))
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [log.plainText])
        }
    }

    private func row(_ entry: AppLog.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.date, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            Text(entry.subsystem.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tone(entry.subsystem))
                .frame(width: 66, alignment: .leading)

            Text(entry.message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func tone(_ sub: AppLog.Entry.Subsystem) -> Color {
        switch sub {
        case .auth:      return .blue
        case .kernelRW:  return .purple
        case .sandbox:   return .indigo
        case .mcm:       return .teal
        case .integrity: return .orange
        case .wipe:      return .red
        case .live:      return .green
        case .runtime:   return .mint
        case .launch:    return .pink
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
