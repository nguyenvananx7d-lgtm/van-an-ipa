import SwiftUI
import UIKit

// MARK: - design tokens
//
// One palette, one accent. The restraint is the point: near-black graphite
// surfaces, hairline "machined" edges, a single muted brass accent, and a fine
// grain over the whole plate. Nothing rainbow, nothing glass. Effects are
// instruments — a pulse on a live state, a sheen on the primary action — not
// decoration layered on top of every control.

enum Palette {
    // plate
    static let void      = Color(hex: 0x06070A)   // deepest well
    static let base      = Color(hex: 0x0A0C10)   // background
    static let surface   = Color(hex: 0x111318)   // cards
    static let surfaceHi = Color(hex: 0x171A21)   // raised / active
    static let well      = Color(hex: 0x08090C)   // inset fields, tracks

    // machined edge
    static let hairline   = Color.white.opacity(0.06)
    static let edgeTop    = Color.white.opacity(0.10)
    static let edgeBottom = Color.black.opacity(0.50)

    // type
    static let text      = Color(hex: 0xE7E9ED)
    static let textDim   = Color(hex: 0x8C93A0)
    static let textFaint = Color(hex: 0x596170)

    // signature
    static let accent     = Color(hex: 0xD8A24E)
    static let accentHi   = Color(hex: 0xF3C877)
    static let accentDeep = Color(hex: 0x7C5A24)

    // states
    static let good = Color(hex: 0x54C08A)
    static let warn = Color(hex: 0xE0A458)
    static let bad  = Color(hex: 0xE4655F)
    static let info = Color(hex: 0x6FA8CB)
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

// MARK: - plate

/// The background every screen sits on: a near-black base, a faint accent bloom
/// behind the header, a vertical shroud into the void, and a fine grain that
/// keeps the flat fills from reading as plastic.
struct ThemeBackground: View {
    var bloom: Double = 0.10

    var body: some View {
        ZStack {
            Palette.base
            RadialGradient(
                colors: [Palette.accent.opacity(bloom), .clear],
                center: UnitPoint(x: 0.5, y: -0.08),
                startRadius: 0,
                endRadius: 460
            )
            LinearGradient(
                colors: [Color.white.opacity(0.015), .clear, Palette.void.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            HackPlate()
            EdgeBeam()
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 96)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// A single 128pt noise tile, built once and repeated. Premultiplied white on
/// clear; overlay-blended at low opacity it reads as film grain, not dirt.
struct GrainTexture: View {
    var body: some View {
        Image(uiImage: GrainTexture.tile)
            .resizable(resizingMode: .tile)
    }

    static let tile: UIImage = makeTile()

    private static func makeTile() -> UIImage {
        let size = 128
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return UIImage() }

        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        for _ in 0..<5200 {
            let x = Int.random(in: 0..<size)
            let y = Int.random(in: 0..<size)
            let a = CGFloat.random(in: 0.04...0.45)
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: a)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }

        guard let image = ctx.makeImage() else { return UIImage() }
        return UIImage(cgImage: image)
    }
}

// MARK: - machined surface

/// The house surface: opaque fill, a top-lit hairline border, a soft drop
/// shadow for depth, optional accent bloom. `elevated` picks the raised fill.
struct MachinedSurface: ViewModifier {
    var radius: CGFloat = 18
    var elevated: Bool = false
    var glow: Color?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(elevated ? Palette.surfaceHi : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Palette.edgeTop, Palette.edgeBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(
                color: (glow ?? .black).opacity(glow == nil ? 0.45 : 0.28),
                radius: glow == nil ? 14 : 18,
                y: glow == nil ? 8 : 0
            )
    }
}

extension View {
    func machined(radius: CGFloat = 18, elevated: Bool = false, glow: Color? = nil) -> some View {
        modifier(MachinedSurface(radius: radius, elevated: elevated, glow: glow))
    }

    /// Inset hairline under a list-style row.
    func rowDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .padding(.leading, 12)
        }
    }
}

// MARK: - buttons

/// Primary = brass plate with dark ink and a held bloom. Secondary = raised
/// graphite with a hairline edge. Press state compresses slightly; disabled
/// dims without redrawing.
struct AccentButtonStyle: ButtonStyle {
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        AccentButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct AccentButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(prominent ? Palette.void : Palette.text)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Palette.accentHi, Palette.accent],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .shadow(color: Palette.accent.opacity(isEnabled ? 0.32 : 0), radius: 14, y: 5)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.surfaceHi)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Palette.edgeTop, lineWidth: 1)
                        )
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Small inline action: a capsule chip, brass ink on a faint brass wash, or
/// solid brass when it is the primary affordance in a row.
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
            .padding(.vertical, 6)
            .background(Capsule().fill(filled ? Palette.accent : Palette.accent.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Palette.accent.opacity(filled ? 0 : 0.35), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - toggle

/// Capsule track, brass when armed, graphite when not, with a knob that carries
/// the whole animation. Reads like a physical switch rather than the iOS pill.
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
                            configuration.isOn ? Palette.accentHi.opacity(0.55) : Palette.hairline,
                            lineWidth: 1
                        )
                    )
                Circle()
                    .fill(configuration.isOn ? Palette.void : Palette.textDim)
                    .padding(3)
                    .offset(x: configuration.isOn ? 9 : -9)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            }
            .frame(width: 46, height: 28)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: configuration.isOn)
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

/// A sliding brass-free segmented control: the selected segment is a raised
/// graphite plate that travels under a matched-geometry spring. Replaces every
/// stock `.segmented` picker in the app.
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.well))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(active ? Palette.text : Palette.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Palette.surfaceHi)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Palette.edgeTop, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                            .matchedGeometryEffect(id: "segSelection", in: ns)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - motion

/// Slow travelling sheen. Masked to whatever it decorates; used sparingly — the
/// primary action and a busy state, never a whole screen.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color = .white
    var period: Double = 2.8
    @State private var travel: CGFloat = -1.2

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, tint.opacity(0.22), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: travel * geo.size.width)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                    travel = 1.3
                }
            }
    }
}

extension View {
    func shimmer(_ tint: Color = .white, period: Double = 2.8) -> some View {
        modifier(Shimmer(tint: tint, period: period))
    }
}

/// Ambient sweep kept from the original build; still available for accent fills.
struct SweepGradient: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let colors: [Color]
    var period: Double = 6

    @State private var phase: Double = 0

    var body: some View {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            .offset(x: reduceMotion ? 0 : phase)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: period).repeatForever(autoreverses: true)) {
                    phase = 240
                }
            }
    }
}

// MARK: - cheat-plate FX
//
// The hack-menu layer, kept restrained: thin CRT scanlines, a slow-drifting
// accent band, a faint dot matrix, and a top edge beam. Enough to read
// "instrument", never enough to read "decoration parade".

/// Faint dot matrix across the plate.
struct HackGrid: View {
    var spacing: CGFloat = 26

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                        with: .color(Color.white.opacity(0.05))
                    )
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// CRT scanlines plus a soft accent band that rolls top to bottom.
struct Scanlines: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var band: CGFloat = -0.2

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var y: CGFloat = 0
            let spacing: CGFloat = 4
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            ctx.stroke(path, with: .color(Color.black.opacity(0.09)), lineWidth: 1)
        }
        .overlay {
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Palette.accent.opacity(0.06), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 130)
                .position(x: geo.size.width / 2, y: band * geo.size.height)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                band = 1.3
            }
        }
        .allowsHitTesting(false)
    }
}

/// Grid + scanlines + grain, composited over the base in one pass.
struct HackPlate: View {
    var body: some View {
        ZStack {
            HackGrid()
            Scanlines()
            GrainTexture()
                .opacity(0.05)
                .blendMode(.overlay)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Thin brass beam drawn along the top edge; breathes in width.
struct EdgeBeam: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, Palette.accent.opacity(0.55), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(60, geo.size.width * (on ? 1 : 0.35)), height: 1.2)
                .opacity(0.65)
                .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: on)
        }
        .frame(height: 1)
        .onAppear {
            guard !reduceMotion else { return }
            on = true
        }
    }
}

/// Expanding, fading ring — the "live" signature for a mark or a status dot.
struct PulseRing: View {
    var color: Color = Palette.accent
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let c = phase + CGFloat(i) * 0.45
                Circle()
                    .stroke(color.opacity(0.5 * (1 - phase)), lineWidth: 1.2)
                    .frame(width: size + size * c, height: size + size * c)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - glitch

/// Periodic brand glitch: jitter, a quick RGB-split sheen (brass + steel), then
/// it settles. Run on a task that is cancelled on disappear; fully inert under
/// reduce-motion.
struct GlitchModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false
    @State private var jitter: CGFloat = 0
    @State private var task: Task<Void, Never>?

    var minInterval: Double = 2.8
    var maxInterval: Double = 6.5

    func body(content: Content) -> some View {
        content
            .overlay {
                if phase {
                    ZStack {
                        content
                            .foregroundStyle(Palette.accent)
                            .blendMode(.plusLighter)
                            .offset(x: -3)
                            .opacity(0.5)
                        content
                            .foregroundStyle(Palette.info)
                            .blendMode(.plusLighter)
                            .offset(x: 3)
                            .opacity(0.45)
                    }
                    .allowsHitTesting(false)
                }
            }
            .offset(x: phase ? jitter : 0)
            .onAppear { start() }
            .onDisappear { task?.cancel() }
    }

    private func start() {
        guard !reduceMotion else { return }
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: minInterval...maxInterval) * 1e9))
                guard !Task.isCancelled else { break }
                await MainActor.run { trigger() }
            }
        }
    }

    private func trigger() {
        jitter = CGFloat.random(in: -2.2...2.2)
        withAnimation(.easeOut(duration: 0.12)) { phase = true }
        let hold = Double.random(in: 0.10...0.32)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(hold * 1e9))
            withAnimation(.easeIn(duration: 0.15)) { phase = false; jitter = 0 }
        }
    }
}

extension View {
    func glitch(minInterval: Double = 2.8, maxInterval: Double = 6.5) -> some View {
        modifier(GlitchModifier(minInterval: minInterval, maxInterval: maxInterval))
    }
}
