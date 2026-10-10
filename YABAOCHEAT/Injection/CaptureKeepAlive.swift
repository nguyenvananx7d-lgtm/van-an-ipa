import Foundation
import AVFoundation
import CoreLocation
import UIKit

/// Keeps the process scheduled while the live capture loop runs.
///
/// The capture design is simple: this app sits in the background, the user
/// switches to the vendor build (`Sophia`) and injects, and this process is
/// supposed to still be awake at the instant the vendor stages its 76 KB patch
/// into the game container. A single `beginBackgroundTask` token lasts ~30 s,
/// which is not enough when the user has to walk through Sophia's menu first.
///
/// Two independent keep-alive mechanisms are armed instead:
///
///  * a silent `AVAudioEngine` loop under the `.playback` category, keyed on
///    the `audio` background mode, and
///  * continuous `CLLocationManager` updates under the `location` background
///    mode.
///
/// Either one alone usually keeps the app awake; together they cover the window.
/// Both are torn down the moment capture stops. Both are opt-in per session -
/// nothing here runs unless the user taps "Capture live".
public final class CaptureKeepAlive: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    public static let shared = CaptureKeepAlive()

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let location = CLLocationManager()
    private var running = false

    private override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        location.distanceFilter = 500
        location.pausesLocationUpdatesAutomatically = false
    }

    public func start() {
        guard !running else { return }
        running = true
        startAudio()
        startLocation()
    }

    public func stop() {
        guard running else { return }
        running = false
        stopAudio()
        location.stopUpdatingLocation()
    }

    // MARK: - audio

    private func startAudio() {
        guard engine == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)

            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
                ?? AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            // A one-second buffer of silence, looped forever. The audio session
            // being busy is what the `audio` background mode is keyed on; the
            // content itself is irrelevant.
            let frames = AVAudioFrameCount(format.sampleRate)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)

            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0
            try engine.start()
            player.play()

            self.engine = engine
            self.player = player
            AppLog.shared.log(.runtime, "CAPTURE: audio keep-alive armed")
        } catch {
            AppLog.shared.log(.runtime, "CAPTURE: audio keep-alive unavailable — \(error.localizedDescription)")
        }
    }

    private func stopAudio() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - location

    private func startLocation() {
        switch location.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            location.startUpdatingLocation()
            AppLog.shared.log(.runtime, "CAPTURE: location keep-alive armed (status \(location.authorizationStatus.rawValue))")
        default:
            location.requestAlwaysAuthorization()
            AppLog.shared.log(.runtime, "CAPTURE: requesting foreground location for keep-alive")
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            AppLog.shared.log(.runtime, "CAPTURE: location keep-alive armed (status \(manager.authorizationStatus.rawValue))")
        default:
            AppLog.shared.log(.runtime, "CAPTURE: location denied (status \(manager.authorizationStatus.rawValue)) — audio keep-alive only")
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.shared.log(.runtime, "CAPTURE: location keep-alive error — \(error.localizedDescription)")
    }
}
