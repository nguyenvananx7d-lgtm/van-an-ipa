import SwiftUI

// MARK: - design tokens
//
// Deep night: near-black canvas, warm graphite surfaces and one muted antique
// gold accent — the same metal as the in-game mark. Quiet, dense, deliberate.

enum Palette {
    static let void       = Color(hex: 0x030303)
    static let base       = Color(hex: 0x080807)
    static let surface    = Color(hex: 0x0F0E0B)
    static let surfaceHi  = Color(hex: 0x17150F)
    static let well       = Color(hex: 0x060605)

    // edges
    static let hairline   = Color.white.opacity(0.07)
    static let edgeTop    = Color.white.opacity(0.10)
    static let edgeBottom = Color.black.opacity(0.55)

    // type
    static let text      = Color(hex: 0xEAE6DC)
    static let textDim   = Color(hex: 0xA8A294)
    static let textFaint = Color(hex: 0x6C675B)

    // signal — antique gold, kept muted so it reads as metal, not neon
    static let accent     = Color(hex: 0xC9A54B)
    static let accentHi   = Color(hex: 0xE4C87E)
    static let accentDeep = Color(hex: 0x241C09)

    // states
    static let good = Color(hex: 0x4FBF8F)
    static let warn = Color(hex: 0xC99A5B)
    static let bad  = Color(hex: 0xC96A5E)
    static let info = Color(hex: 0x7E93C9)
}

// MARK: - metrics

enum Metrics {
    static let gutter: CGFloat       = 18
    static let stack: CGFloat        = 18
    static let cardRadius: CGFloat   = 14
    static let groupRadius: CGFloat  = 12
    static let controlRadius: CGFloat = 10
    static let rowPaddingH: CGFloat  = 15
    static let rowPaddingV: CGFloat  = 14
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue:  Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

// MARK: - fonts
//
// Rajdhani for everything functional — squared, condensed, nothing like the
// system font. Cinzel (engraved Roman capitals) for the brand line only.

extension Font {
    /// The brand face: engraved capitals, the logo's own letterform.
    static func brand(_ size: CGFloat) -> Font {
        .custom("Cinzel-Regular", size: size)
    }

    /// The UI face. Every weight maps to a real Rajdhani file, never a
    /// synthetic slant or stroke.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold, .heavy, .black:
            return .custom("Rajdhani-Bold", size: size)
        case .semibold:
            return .custom("Rajdhani-SemiBold", size: size)
        case .medium:
            return .custom("Rajdhani-Medium", size: size)
        default:
            return .custom("Rajdhani-Regular", size: size)
        }
    }
}

// MARK: - background

/// A black canvas with a faint gold ember rising from the bottom — the glow is
/// a texture, not a light source.
struct ThemeBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Palette.void,
                Palette.base,
                Palette.accentDeep.opacity(0.35),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - plate

struct PlateSurface: ViewModifier {
    var radius: CGFloat = Metrics.cardRadius
    var elevated: Bool = false
    var glow: Color?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(elevated ? Palette.surfaceHi : Palette.surface)
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.03), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(glow ?? Palette.edgeTop, lineWidth: glow == nil ? 1 : 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
    }
}

struct InsetSurface: ViewModifier {
    var radius: CGFloat = Metrics.controlRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.black.opacity(0.6), Palette.hairline],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func machined(radius: CGFloat = Metrics.cardRadius, elevated: Bool = false, glow: Color? = nil) -> some View {
        modifier(PlateSurface(radius: radius, elevated: elevated, glow: glow))
    }

    func insetWell(radius: CGFloat = Metrics.controlRadius) -> some View {
        modifier(InsetSurface(radius: radius))
    }

    func rowDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .padding(.leading, Metrics.rowPaddingH)
        }
    }
}

// MARK: - buttons

struct AccentButtonStyle: ButtonStyle {
    var prominent: Bool = true
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        AccentButtonBody(configuration: configuration, prominent: prominent, destructive: destructive)
    }
}

private struct AccentButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let destructive: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.ui(17, weight: .semibold))
            .foregroundStyle(prominent ? Palette.void : (destructive ? Palette.bad : Palette.text))
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.accent)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.accentHi.opacity(0.3), lineWidth: 0.5)
                        )
                        .shadow(color: Palette.accent.opacity(isEnabled ? 0.10 : 0), radius: 6, y: 2)
                } else if destructive {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.surfaceHi)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.bad.opacity(0.4), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.surfaceHi)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.edgeTop, lineWidth: 1)
                        )
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ChipButtonStyle: ButtonStyle {
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ChipButtonBody(configuration: configuration, filled: filled)
    }
}

private struct ChipButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let filled: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.ui(12, weight: .semibold))
            .foregroundStyle(filled ? Palette.void : Palette.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(filled ? Palette.accent : Palette.accent.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Palette.accent.opacity(filled ? 0 : 0.3), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - toggle

struct MachinedToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? Palette.accent : Palette.well)
                    .overlay(
                        Capsule().strokeBorder(
                            configuration.isOn ? Palette.accentHi.opacity(0.35) : Palette.hairline,
                            lineWidth: 1
                        )
                    )
                Circle()
                    .fill(configuration.isOn ? Palette.void : Palette.textDim)
                    .padding(3)
                    .offset(x: configuration.isOn ? 9 : -9)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
            .frame(width: 46, height: 28)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

// MARK: - segmented control

struct SegItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [SegItem<Value>]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items) { item in
                segment(item)
            }
        }
        .padding(3)
        .insetWell(radius: Metrics.controlRadius)
    }

    private func segment(_ item: SegItem<Value>) -> some View {
        let active = item.value == selection
        return Button {
            guard item.value != selection else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = item.value
            }
        } label: {
            Text(item.title)
                .font(.ui(13, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Palette.text : Palette.textFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.surfaceHi)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Palette.edgeTop, lineWidth: 1)
                            )
                            .matchedGeometryEffect(id: "segSelection", in: ns)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - mark

/// The mark: a dark tile with a reticle glyph — ring, centre pip, four ticks.
struct Mark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Palette.surfaceHi)
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(Palette.edgeTop, lineWidth: 1)
            ReticleGlyph(size: size * 0.54)
        }
        .frame(width: size, height: size)
    }
}

struct ReticleGlyph: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.accent.opacity(0.9), lineWidth: 1.5)
                .frame(width: size, height: size)
            Circle()
                .fill(Palette.accent)
                .frame(width: size * 0.12, height: size * 0.12)
            tick.rotationEffect(.degrees(0))
            tick.rotationEffect(.degrees(90))
            tick.rotationEffect(.degrees(180))
            tick.rotationEffect(.degrees(270))
        }
    }

    private var tick: some View {
        Capsule()
            .fill(Palette.accent)
            .frame(width: size * 0.30, height: 1.5)
            .offset(y: -(size / 2) + 5)
    }
}
