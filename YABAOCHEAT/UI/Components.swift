import SwiftUI

// Reusable pieces the rest of the UI is built from. The public shapes are
// unchanged so every panel tab keeps compiling against the same API as before;
// the surfaces themselves are flat — one plate, one hairline edge, one soft
// shadow. Nothing glows except the thing you are meant to press.

// MARK: - surfaces

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = Metrics.cardRadius
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
            Circle()
                .fill(tone.color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.ui(11, weight: .semibold))
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
                .font(.ui(13))
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

/// Titled group the panel tabs are built from: a small-caps caption with a
/// line-art glyph over a flat string of rows, divided by hairlines. No
/// card-inside-a-card.
struct SectionGroup<Content: View>: View {
    let title: String
    var symbol: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.ui(12, weight: .semibold))
                        .foregroundStyle(Palette.accent.opacity(0.8))
                }
                Text(title)
                    .font(.ui(12, weight: .semibold))
                    .foregroundStyle(Palette.textDim)
                    .textCase(.uppercase)
                    .tracking(0.9)
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
            }
            .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
                        .strokeBorder(Palette.edgeTop.opacity(0.7), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous))
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
                    .font(.ui(15, weight: .medium))
                    .foregroundStyle(Palette.text)
                if let detail {
                    Text(detail)
                        .font(.ui(12))
                        .foregroundStyle(Palette.textFaint)
                }
            }
        }
        .padding(.vertical, Metrics.rowPaddingV)
        .padding(.horizontal, Metrics.rowPaddingH)
        .rowDivider()
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var step: Double = 1
    var unit: String = ""
    /// Show the low/high ends under the track. Off by default so a plain
    /// 0–100 row stays quiet; on for ranges where the ends are the point.
    var showRange: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.ui(15, weight: .medium))
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                Text("\(Int(value.rounded()))\(unit)")
                    .font(.ui(12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.accent.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Palette.accent.opacity(0.22), lineWidth: 1))
            }
            Slider(value: $value, in: range, step: step)
                .tint(Palette.accent)
            if showRange {
                HStack {
                    Text("\(Int(range.lowerBound))")
                    Spacer(minLength: 8)
                    Text("\(Int(range.upperBound))")
                }
                .font(.ui(11))
                .foregroundStyle(Palette.textFaint)
            }
        }
        .padding(.vertical, Metrics.rowPaddingV)
        .padding(.horizontal, Metrics.rowPaddingH)
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
                .font(.ui(15, weight: .medium))
                .foregroundStyle(Palette.text)
            SegmentedControl(
                selection: $selection,
                items: options.map { SegItem(value: $0.value, title: $0.title) }
            )
        }
        .padding(.vertical, Metrics.rowPaddingV)
        .padding(.horizontal, Metrics.rowPaddingH)
        .rowDivider()
    }
}
// MARK: - action / info rows
//
// The two plain shapes a settings list is made of: a tappable row that leads
// somewhere (chevron) and a read-only row that states a fact. Shared so the
// Inject and Setting tabs cannot drift apart.
struct ActionRow: View {
    var symbol: String? = nil
    let label: String
    var value: String?
    var tint: Color = Palette.text
    var showsChevron: Bool = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.9))
                        .frame(width: 20, alignment: .center)
                }
                Text(label)
                    .font(.ui(15, weight: .medium))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.ui(12))
                        .foregroundStyle(Palette.textDim)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.ui(11, weight: .bold))
                        .foregroundStyle(Palette.textFaint)
                }
            }
            .padding(.vertical, Metrics.rowPaddingV)
            .padding(.horizontal, Metrics.rowPaddingH)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.ui(15, weight: .medium))
                .foregroundStyle(Palette.text)
            Spacer(minLength: 8)
            Text(value)
                .font(.ui(12))
                .foregroundStyle(Palette.textDim)
                .lineLimit(1)
        }
        .padding(.vertical, Metrics.rowPaddingV)
        .padding(.horizontal, Metrics.rowPaddingH)
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
/// swatch gets an accent ring and a held bloom.
struct SwatchRow: View {
    let label: String
    @Binding var argb: Int
    var swatches: [ColorSwatch] = ColorSwatch.defaults

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.ui(15, weight: .medium))
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
        .padding(.vertical, Metrics.rowPaddingV)
        .padding(.horizontal, Metrics.rowPaddingH)
        .rowDivider()
    }
}
/// Named palette entry for `PaletteRow`. `argb` is nil for the "Default" slot,
/// which draws as an empty well rather than a colour.
struct PaletteOption: Identifiable, Hashable, Sendable {
    let value: String
    let title: String
    let argb: Int?
    var id: String { value }
    var color: Color { argb.map { Color(argb: $0) } ?? Palette.well }
    static let defaults: [PaletteOption] = [
        PaletteOption(value: "default", title: "Default", argb: nil),
        PaletteOption(value: "red",     title: "Red",     argb: 0xFFFF0000),
        PaletteOption(value: "green",   title: "Green",   argb: 0xFF00FF00),
        PaletteOption(value: "blue",    title: "Blue",    argb: 0xFF0000FF),
        PaletteOption(value: "yellow",  title: "Yellow",  argb: 0xFFFFFF00),
        PaletteOption(value: "cyan",    title: "Cyan",    argb: 0xFF00FFFF),
        PaletteOption(value: "pink",    title: "Pink",    argb: 0xFFFF69B4),
        PaletteOption(value: "orange",  title: "Orange",  argb: 0xFFFFA500),
        PaletteOption(value: "purple",  title: "Purple",  argb: 0xFF800080),
        PaletteOption(value: "white",   title: "White",   argb: 0xFFFFFFFF),
    ]
}
/// Wrapping palette picker. Ten chips never fit one segment row, so they lay
/// out five across with the name under each dot — the same shape as the
/// swatch ramp, just labelled.
struct PaletteRow: View {
    let label: String
    @Binding var selection: String
    var options: [PaletteOption] = PaletteOption.defaults
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(.ui(15, weight: .medium))
                .foregroundStyle(Palette.text)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(options) { option in
                    let active = option.value == selection
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selection = option.value
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(option.color)
                                if option.argb == nil {
                                    Image(systemName: "nosign")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Palette.textFaint)
                                }
                                Circle().strokeBorder(
                                    active ? Palette.accent : Color.white.opacity(0.14),
                                    lineWidth: active ? 2.5 : 1
                                )
                            }
                            .frame(width: 30, height: 30)
                            .shadow(color: active ? Palette.accent.opacity(0.45) : .clear, radius: 7)
                            .scaleEffect(active ? 1.06 : 1)
                            Text(option.title)
                                .font(.ui(11, weight: active ? .semibold : .regular))
                                .foregroundStyle(active ? Palette.text : Palette.textFaint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                }
            }
        }
        .padding(.vertical, Metrics.rowPaddingV)
        .padding(.horizontal, Metrics.rowPaddingH)
        .rowDivider()
    }
}
