import Foundation
import UIKit

/// The app half of the Ghost route: start the loopback channel, launch the
/// game, map `GhostPayload.dylib` before its first frame, then keep the payload
/// in sync with the panel.
///
/// Nothing here touches the game's container. The only inputs are the payload
/// already inside this app bundle and a TCP socket on `127.0.0.1`.
public enum GhostRuntime {

    public enum Failure: LocalizedError {
        case payloadMissing
        case injectFailed(Int)

        public var errorDescription: String? {
            switch self {
            case .payloadMissing:
                return "GhostPayload.dylib is not in the app bundle"
            case .injectFailed(let code):
                return "Ghost map failed (code \(code)) — see the log"
            }
        }
    }

    private static let sequenceLock = NSLock()
    private static var sequence: UInt32 = 0

    public static var isAvailable: Bool {
        GhostInjector.payloadAvailable()
    }

    /// Map the payload and bring the target up. Blocking work runs on a global
    /// queue; the caller only awaits the result.
    public static func install(game: Game,
                               controls: FeatureControls,
                               log: @escaping (String) -> Void) async -> Result<Void, Error> {
        guard let payload = GhostInjector.payloadPath() else {
            return .failure(Failure.payloadMissing)
        }

        GhostChannel.shared.start()
        push(controls)
        sendIcon()

        // Cold start matters: a warm process keeps the old runtime, so the new
        // payload would never be mapped.
        GhostInjector.terminateBundle(game.bundleIdentifier)

        let code: Int = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = GhostInjector.launchBundle(game.bundleIdentifier,
                                                        payload: payload) { line in
                    log(line)
                }
                continuation.resume(returning: result)
            }
        }

        guard code == 0 else {
            return .failure(Failure.injectFailed(code))
        }

        // The payload waits for IL2CPP, then opens the channel. Replaying the
        // latest frame after a short delay covers that startup window.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        push(controls)
        sendIcon()
        return .success(())
    }

    /// Kill the target (which unmaps the payload) and close the channel.
    public static func detach(game: Game) {
        GhostInjector.terminateBundle(game.bundleIdentifier)
        GhostChannel.shared.stop()
    }

    /// Push the current panel values. Safe to call on every slider change.
    public static func push(_ controls: FeatureControls) {
        var settings = settings(from: controls)
        sequenceLock.lock()
        sequence &+= 1
        let seq = sequence
        sequenceLock.unlock()
        GhostChannel.shared.send(settings.encoded(seq: seq))
    }

    public static func settings(from controls: FeatureControls) -> GhostSettings {
        var settings = GhostSettings()

        var flags: UInt32 = 0
        if controls.masterEsp { flags |= GhostFlag.esp }
        if controls.boxEsp { flags |= GhostFlag.box }
        if controls.nameEsp { flags |= GhostFlag.name }
        if controls.distanceEsp { flags |= GhostFlag.distance }
        if controls.healthEsp { flags |= GhostFlag.health }
        if controls.tracerEsp { flags |= GhostFlag.tracer }
        if controls.aimEnabled || controls.silentAim || controls.isEnabled {
            flags |= GhostFlag.aim
            // Managed draws the cone whenever the assist is armed (EspFov
            // defaults on); Ghost mirrors that on the same bit position.
            flags |= GhostFlag.fovRing
        }
        if controls.aimVisibleOnly { flags |= GhostFlag.aimVisible }
        if controls.ignoreKnocked { flags |= GhostFlag.aimKnocked }
        if controls.aimTouchGate { flags |= GhostFlag.aimTouch }
        settings.flags = flags

        settings.espMaxDistance = Float(max(10, controls.espMaxDistance))
        settings.espBoxScale = Float(max(50, controls.espBoxScalePercent)) / 100.0
        settings.espTextScale = Float(max(0.5, controls.espTextScale))
        settings.espFillAlpha = Float(max(0, min(1, controls.espBoxFillAlpha)))

        // The panel's FOV is a pixel radius; the payload wants a full cone in
        // degrees. 0.30 keeps the default 220 px near 66°, which frames the
        // same area without turning the assist into a 150° vacuum.
        settings.aimFov = Float(max(20, min(170, controls.aimbotRadiusValue * 0.30)))
        settings.aimSmooth = Float(max(0.05, min(1, controls.aimSmooth)))
        settings.aimMaxDistance = Float(max(10, controls.aimDistance))
        settings.aimHitChance = Float(max(0, min(100, controls.hitChance))) / 100.0
        settings.aimReaction = Float(max(0, min(1500, controls.aimReactionMs))) / 1000.0
        settings.aimMaxTurn = Float(max(30, controls.aimMaxTurn)) * 6.0

        settings.palette = paletteIndex(controls.espPalette)
        settings.boxStyle = controls.boxType == "edge" ? 1 : 0

        let bone = controls.silentAim ? controls.silentAimTarget : controls.aimTarget
        switch bone {
        case "head": settings.aimBone = 0
        case "neck": settings.aimBone = 2
        default:     settings.aimBone = 1
        }

        return settings
    }

    private static func paletteIndex(_ name: String) -> UInt8 {
        switch name.lowercased() {
        case "emerald", "mint":  return 0
        case "cyan", "ice":      return 1
        case "pink", "rose":     return 2
        case "orange", "yellow", "amber": return 3
        case "purple", "violet": return 4
        case "red":              return 5
        case "white", "default": return 6
        case "green", "lime":    return 7
        default:                 return 0
        }
    }

    // MARK: - Floating icon

    /// The in-game icon cannot be read from the app bundle by the game (its
    /// sandbox has no access), so the logo is decoded here, cropped to a
    /// circle, rasterised to 96x96 RGBA8 and shipped as a 'GHIM' frame.
    private static func sendIcon() {
        guard let data = iconRGBA() else { return }
        GhostChannel.shared.sendImage(data, width: 96, height: 96)
    }

    private static func iconRGBA() -> Data? {
        let name = "vortex-icon-128"
        let url = Bundle.main.url(forResource: name, withExtension: "png",
                                  subdirectory: "icons")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        guard let url, let image = UIImage(contentsOfFile: url.path) else { return nil }

        let size = 96
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let rendered = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            // The PNG already carries rounded corners and transparency; keep
            // them instead of clipping to a circle, so the wings/keys survive.
            image.draw(in: rect)
        }

        guard let cg = rendered.cgImage,
              let context = CGContext(
                  data: nil, width: size, height: size,
                  bitsPerComponent: 8, bytesPerRow: size * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        /* CG draws bottom-up; flip so the payload gets top-left origin. */
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let bytes = context.data else { return nil }
        return Data(bytes: bytes, count: size * size * 4)
    }
}
