import SwiftUI

// MARK: - design tokens
//
// Ink and signal. One cool cyan on a near-black base, flat fills, hairline
// borders. No noise, no glass, no rainbow, no glow piled on everything.
// Hierarchy comes from weight, spacing, and one accent that only exists where
// a control is live. The effect budget is deliberately small so the panel
// reads like a tool, not a demo.

enum Palette {
    // plate — cool ink, a touch lifted, hierarchy by value
    static let void       = Color(hex: 0x0D0F14)   // deepest well
    static let base       = Color(hex: 0x12151B)   // background
    static let surface    = Color(hex: 0x1A1E26)   // plates, rows
    static let surfaceHi  = Color(hex: 0x242A34)   // raised / active
    static let well       = Color(hex: 0x0E1117)   // inset fields, tracks

    // edges
    static let hairline   = Color.white.opacity(0.08)
    static let edgeTop    = Color.white.opacity(0.12)
    static let edgeBottom = Color.black.opacity(0.50)

    // type
    static let text      = Color(hex: 0xF1F2F5)
    static let textDim   = Color(hex: 0xA2A9B4)
    static let textFaint = Color(hex: 0x67707E)

    // signal
    static let accent     = Color(hex: 0x3FC9E6)
    static let accentHi   = Color(hex: 0x86E4F6)
    static let accentDeep = Color(hex: 0x0F4E5C)

    // states
    static let good = Color(hex: 0x4CC987)
    static let warn = Color(hex: 0xE2A85B)
    static let bad  = Color(hex: 0xED6A63)
    static let info = Color(hex: 0x8FA6F0)
}

// MARK: - metrics
//
// One spacing and radius scale, so padding does not drift row to row. The
// numbers are small on purpose: a panel that is dense reads as a tool.

enum Metrics {
    static let gutter: CGFloat       = 16    // screen horizontal margin
    static let stack: CGFloat        = 16    // gap between section groups
    static let cardRadius: CGFloat   = 16
    static let groupRadius: CGFloat  = 14
    static let controlRadius: CGFloat = 12
    static let rowPaddingH: CGFloat  = 14
    static let rowPaddingV: CGFloat  = 13
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

// MARK: - background

/// Flat ink with a barely-there cool tint high-right and a slow fall to void
/// at the bottom. Static, cheap, quiet.
struct ThemeBackground: View {
    var bloom: Double = 0.055

    var body: some View {
        ZStack {
            Palette.base
            RadialGradient(
                colors: [Palette.accent.opacity(bloom), .clear],
                center: UnitPoint(x: 0.92, y: 0.0),
                startRadius: 0,
                endRadius: 480
            )
            LinearGradient(
                colors: [Color.white.opacity(0.02), .clear, Palette.void.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - plate

/// The house surface: flat fill, one hairline border, one soft shadow. No
/// gradient, no bloom. `glow` tints the border for the selected state. The only
/// gradient allowed here is a 3.5%-white sheen on the top edge, which is what
/// makes a raised plate catch light without looking like frosted glass.
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
                            colors: [Color.white.opacity(0.035), .clear],
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
            .shadow(color: .black.opacity(0.32), radius: 10, y: 5)
    }
}

/// The recessed counterpart to `machined`: a dark well, a shadow under the top
/// edge and a hairline along the bottom, so tracks and text fields read as cut
/// into the plate rather than laid on top of it.
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
                            colors: [Color.black.opacity(0.55), Palette.hairline],
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

    /// Inset hairline under a list-style row.
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

/// Primary = flat accent with dark ink; the only glowing element in the app is
/// the one the user is meant to press. Secondary = raised ink plate.
/// Destructive = the same ink plate, but with a bad-tinted edge and ink so a
/// removal action is read before it is pressed.
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
            .foregroundStyle(prominent ? Palette.void : (destructive ? Palette.bad : Palette.text))
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.accent)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.accentHi.opacity(0.35), lineWidth: 0.5)
                        )
                        .shadow(color: Palette.accent.opacity(isEnabled ? 0.22 : 0), radius: 10, y: 4)
                } else if destructive {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.surfaceHi)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.bad.opacity(0.45), lineWidth: 1)
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

/// Small inline action: a capsule chip, accent ink on a faint accent wash, or
/// solid accent when it is the primary affordance in a row.
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? Palette.void : Palette.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(filled ? Palette.accent : Palette.accent.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Palette.accent.opacity(filled ? 0 : 0.35), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - toggle

/// Capsule track, accent when armed, graphite when not, with a knob that carries
/// the whole motion. Reads like a physical switch rather than the iOS pill.
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
                            configuration.isOn ? Palette.accentHi.opacity(0.45) : Palette.hairline,
                            lineWidth: 1
                        )
                    )
                Circle()
                    .fill(configuration.isOn ? Palette.void : Palette.textDim)
                    .padding(3)
                    .offset(x: configuration.isOn ? 9 : -9)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
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

/// Flat segmented control: a raised plate slides under the active segment. Used
/// for in-row choice groups; the screen-level navigation is `BottomTabBar`.
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
                .font(.footnote.weight(active ? .semibold : .medium))
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

// MARK: - screen-level tabs

/// One entry in the bottom bar: an index, a label, and a line-art glyph.
struct TabItem: Identifiable {
    let index: Int
    let title: String
    let symbol: String

    var id: Int { index }
}

/// Bottom navigation for the four screens. Flat ink bar with a single top
/// hairline; the active tab switches glyph and label to the accent and nothing
/// else moves. Reads as navigation chrome, not a widget.
struct BottomTabBar: View {
    @Binding var selection: Int
    let items: [TabItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                tab(item)
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
        // Solid, not translucent: the bar is chrome, and a hard edge keeps it
        // from blurring into the scrolling content above it. The fill bleeds
        // into the home-indicator strip so the bar reads full-height.
        .background(Palette.void.opacity(0.96), ignoresSafeAreaEdges: .bottom)
    }

    private func tab(_ item: TabItem) -> some View {
        let active = selection == item.index
        return Button {
            guard item.index != selection else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                selection = item.index
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: active ? .semibold : .regular))
                    .frame(height: 20)
                Text(item.title)
                    .font(.caption2.weight(active ? .semibold : .medium))
            }
            .foregroundStyle(active ? Palette.accent : Palette.textFaint)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

// MARK: - mark

/// The mark: a dark tile with a reticle glyph — ring, centre pip, four ticks.
/// Thematic without being decorative.
struct Mark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Palette.surfaceHi, Palette.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(Palette.edgeTop, lineWidth: 1)
            ReticleGlyph(size: size * 0.54)
        }
        .frame(width: size, height: size)
    }
}

/// Minimal reticle: outer ring, centre pip, four ticks.
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
            tick
                .rotationEffect(.degrees(0))
            tick
                .rotationEffect(.degrees(90))
            tick
                .rotationEffect(.degrees(180))
            tick
                .rotationEffect(.degrees(270))
        }
    }

    private var tick: some View {
        Capsule()
            .fill(Palette.accent)
            .frame(width: size * 0.30, height: 1.5)
            .offset(y: -(size / 2) + 5)
    }
}