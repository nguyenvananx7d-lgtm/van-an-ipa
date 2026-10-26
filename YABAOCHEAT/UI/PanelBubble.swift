import SwiftUI

/// The draggable ball that opens the web panel — the same affordance the
/// in-game overlay uses: a small circle you park out of the way and tap when
/// you want the menu. Position is stored as a fraction of the screen so it
/// survives rotation and different device sizes.
struct PanelBubble: View {
    @ObservedObject private var panel = PanelStore.shared
    @AppStorage("ffxc.panel.bubble") private var storedPosition: String = "0.93,0.62"

    @State private var position: CGPoint?
    @State private var origin: CGPoint?

    private let diameter: CGFloat = 52

    var body: some View {
        GeometryReader { geo in
            let current = position ?? defaultPoint(in: geo.size)

            ZStack {
                // Soft halo so the orb reads as the one live thing on screen.
                Circle()
                    .fill(Palette.accent.opacity(0.16))
                    .frame(width: diameter + 18, height: diameter + 18)
                    .blur(radius: 9)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Palette.accentHi, Palette.accent, Palette.accentDeep],
                            center: .init(x: 0.35, y: 0.3),
                            startRadius: 2,
                            endRadius: diameter
                        )
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                Circle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.6)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: Palette.accent.opacity(0.45), radius: 14, y: 4)
            .contentShape(Circle())
            .position(clamped(current, in: geo.size))
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        let start = origin ?? clamped(current, in: geo.size)
                        if origin == nil { origin = start }
                        position = clamped(
                            CGPoint(x: start.x + value.translation.width,
                                    y: start.y + value.translation.height),
                            in: geo.size
                        )
                    }
                    .onEnded { _ in
                        if let position {
                            storedPosition = "\(position.x / max(1, geo.size.width)),\(position.y / max(1, geo.size.height))"
                        }
                        origin = nil
                    }
            )
            .onTapGesture { panel.isOpen = true }
            .accessibilityLabel("Mở bảng điều khiển")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func defaultPoint(in size: CGSize) -> CGPoint {
        let parts = storedPosition
            .split(separator: ",")
            .compactMap { Double(String($0).trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else {
            return CGPoint(x: size.width - diameter, y: size.height * 0.62)
        }
        return CGPoint(x: parts[0] * size.width, y: parts[1] * size.height)
    }

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let margin = diameter / 2 + 8
        return CGPoint(
            x: min(max(point.x, margin), max(margin, size.width - margin)),
            y: min(max(point.y, margin), max(margin, size.height - margin))
        )
    }
}
