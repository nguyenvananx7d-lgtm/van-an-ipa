import SwiftUI

// Reusable pieces the rest of the UI is built from. Each modifier here has a
// matching field in the reflection metadata, which is how the names were
// recovered: `_reduceMotion`, `_reduceTransparency`, `_sweep`, `padding`,
// `radius`, `compact`.

// MARK: - motion

/// Sweep gradient used as the app's accent. Animates slowly so it reads as
/// ambient rather than as a spinner.
struct SweepGradient: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let colors: [Color]
    var period: Double = 6

    @State private var phase: Double = 0

    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: reduceMotion ? 0 : phase)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: period).repeatForever(autoreverses: true)) {
                phase = 240
            }
        }
    }
}

// MARK: - surfaces

struct Card<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var padding: CGFloat = 16
    var radius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Compact variant used inside the controls list.
struct CompactRow<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content.padding(padding)
    }
}

// MARK: - badges

struct StateBadge: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case neutral, good, busy, bad

        var color: Color {
            switch self {
            case .neutral: return .secondary
            case .good:    return .green
            case .busy:    return .orange
            case .bad:     return .red
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tone.color.opacity(0.18)))
            .foregroundStyle(tone.color)
    }
}

// MARK: - banner

struct Banner: View {
    enum Kind {
        case info, warning, error

        var color: Color {
            switch self {
            case .info:    return .blue
            case .warning: return .orange
            case .error:   return .red
            }
        }

        var symbol: String {
            switch self {
            case .info:    return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error:   return "xmark.shield.fill"
            }
        }
    }

    let kind: Kind
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(kind.color.opacity(0.12)))
    }
}

// MARK: - panel rows

/// Titled group the panel tabs are built from: caption header over one card.
struct SectionGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
            Card(padding: 6, radius: 16) {
                VStack(alignment: .leading, spacing: 0) { content }
            }
        }
    }
}

struct ToggleRow: View {
    let label: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var step: Double = 1
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                Text("\(Int(value.rounded()))\(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

struct SegmentOption: Identifiable, Hashable, Sendable {
    let value: String
    let title: String
    var id: String { value }
}

struct SegmentRow: View {
    let label: String
    @Binding var selection: String
    let options: [SegmentOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.body.weight(.medium))
            Picker("", selection: $selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

// MARK: - logo

struct Mark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.purple, .blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "lock.shield.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
