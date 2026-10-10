import SwiftUI

// Reusable pieces the rest of the UI is built from. Restyled on the theme:
// opaque machined surfaces instead of ultra-thin material, hairline edges,
// brass accents held back to where they mean something. Public shapes are
// unchanged so the panel tabs keep compiling against the same API.

// MARK: - motion (re-exported here for callers that still import it)

// `SweepGradient` lives in Theme.swift.

// MARK: - surfaces

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .machined(radius: radius)
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
            case .neutral: return Palette.textDim
            case .good:    return Palette.good
            case .busy:    return Palette.warn
            case .bad:     return Palette.bad
            }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if tone == .good {
                    PulseRing(color: tone.color, size: 20)
                }
                Circle()
                    .fill(tone.color)
                    .frame(width: 6, height: 6)
                    .shadow(color: tone.color.opacity(0.8), radius: 4)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tone.color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(tone.color.opacity(0.10)))
        .overlay(Capsule().strokeBorder(tone.color.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - banner

struct Banner: View {
    enum Kind {
        case info, warning, error

        var color: Color {
            switch self {
            case .info:    return Palette.info
            case .warning: return Palette.warn
            case .error:   return Palette.bad
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
                .padding(.top, 1)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(kind.color.opacity(0.08))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(kind.color)
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 1)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(kind.color.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - panel rows

/// Titled group the panel tabs are built from: a brass-ticked caption over one
/// machined card.
struct SectionGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Palette.accent)
                    .frame(width: 3, height: 11)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.textDim)
                    .textCase(.uppercase)
            }
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
                    .foregroundStyle(Palette.text)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.textDim)
                }
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .rowDivider()
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var step: Double = 1
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                Text("\(Int(value.rounded()))\(unit)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.accent.opacity(0.12)))
            }
            Slider(value: $value, in: range, step: step)
                .tint(Palette.accent)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .rowDivider()
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
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.text)
            SegmentedControl(
                selection: $selection,
                items: options.map { SegItem(value: $0.value, title: $0.title) }
            )
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .rowDivider()
    }
}

// MARK: - colour

extension Color {
    /// Packed `0xAARRGGBB`, the same form `FeatureControls.espColor` uses.
    init(argb: Int) {
        self.init(
            .sRGB,
            red:   Double((argb >> 16) & 0xFF) / 255.0,
            green: Double((argb >> 8) & 0xFF) / 255.0,
            blue:  Double(argb & 0xFF) / 255.0,
            opacity: Double((argb >> 24) & 0xFF) / 255.0
        )
    }
}

/// Horizontal swatch picker bound to a packed `0xAARRGGBB` value. The selected
/// swatch gets a brass ring and a held bloom.
struct SwatchRow: View {
    let label: String
    @Binding var argb: Int
    var swatches: [ColorSwatch] = ColorSwatch.defaults

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.text)
            HStack(spacing: 12) {
                ForEach(swatches) { swatch in
                    let selected = argb == swatch.argb
                    Button {
                        argb = swatch.argb
                    } label: {
                        Circle()
                            .fill(Color(argb: swatch.argb))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().strokeBorder(
                                    selected ? Palette.accent : Color.white.opacity(0.12),
                                    lineWidth: selected ? 2.5 : 1
                                )
                            )
                            .shadow(color: selected ? Palette.accent.opacity(0.5) : .clear, radius: 8)
                            .scaleEffect(selected ? 1.08 : 1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .rowDivider()
    }
}

// MARK: - logo

/// The mark: a milled graphite tile with an engraved brass glyph and a small
/// live pip. Replaces the blue/purple/cyan gradient, which was the single most
/// generic element in the app.
struct Mark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Palette.surfaceHi, Palette.void],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            Image(systemName: "lock.shield.fill")
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Palette.accentHi, Palette.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Palette.accent.opacity(0.55), radius: size * 0.14)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(Palette.edgeTop, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Palette.accent)
                .frame(width: size * 0.11, height: size * 0.11)
                .shadow(color: Palette.accent.opacity(0.9), radius: 4)
                .offset(x: size * 0.015, y: -size * 0.015)
        }
        .accessibilityHidden(true)
    }
}
