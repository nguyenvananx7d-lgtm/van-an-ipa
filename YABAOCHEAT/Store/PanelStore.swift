import Foundation
import SwiftUI
import Combine
import UIKit
import WebKit

/// Drives the web control panel: hands the page the session + the current
/// control set, takes edits back, and stages them only when the panel asks.
///
/// The page owns the draft. Nothing reaches the runtime until "Áp dụng cấu
/// hình" comes back over the bridge; the commit goes through `MenuStore`,
/// which persists the profile and lets `InjectStore` restage the live config
/// while a session is up.
@MainActor
public final class PanelStore: ObservableObject {
    public static let shared = PanelStore()

    /// State of the key-injector modal. The panel renders it; the store only
    /// says what happened.
    public enum InjectorPhase: Equatable {
        case hidden
        case busy(String)
        case done(String)
        case failed(String)
    }

    @Published public var isOpen: Bool = false {
        didSet {
            guard isOpen != oldValue else { return }
            guard isOpen else {
                // A finished run should not pop the modal again on reopen.
                injectorPhase = .hidden
                return
            }
            pushState()
            pushInjector()
        }
    }

    @Published public var injectorPhase: InjectorPhase = .hidden

    /// Wired by `WebPanelView` once the web view exists.
    weak var webView: WKWebView?

    private let menu = MenuStore.shared
    private let authorization = AuthorizationStore.shared
    private let injector = InjectStore.shared
    private let log = AppLog.shared

    private var cancellables: Set<AnyCancellable> = []
    private var sessionStart: Date

    private static let sessionStartDefaults = "ffxc.panel.sessionStart"
    private static let sessionKeyDefaults = "ffxc.panel.sessionKey"
    private static let sessionSeconds = 24 * 60 * 60

    private init() {
        sessionStart = PanelStore.loadSessionStart()
        observe()
    }

    // MARK: - lifecycle

    private static func loadSessionStart() -> Date {
        let stored = UserDefaults.standard.double(forKey: sessionStartDefaults)
        if stored > 0 { return Date(timeIntervalSince1970: stored) }
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: sessionStartDefaults)
        return now
    }

    /// A new key starts a new 24 h window; a re-launch keeps the running one,
    /// so the timer in the header is a property of the licence, not the view.
    private func restartSession(for key: String) {
        let stored = UserDefaults.standard.string(forKey: Self.sessionKeyDefaults)
        guard stored != key else { return }
        UserDefaults.standard.set(key, forKey: Self.sessionKeyDefaults)
        sessionStart = Date()
        UserDefaults.standard.set(sessionStart.timeIntervalSince1970, forKey: Self.sessionStartDefaults)
    }

    private func observe() {
        authorization.$status
            .sink { [weak self] status in
                guard let self else { return }
                if let key = status.displayKey, !key.isEmpty { self.restartSession(for: key) }
                self.pushStateIfOpen()
            }
            .store(in: &cancellables)

        menu.$configurations
            .dropFirst()
            .sink { [weak self] _ in self?.pushStateIfOpen() }
            .store(in: &cancellables)

        injector.$isActive
            .sink { [weak self] _ in self?.pushStateIfOpen() }
            .store(in: &cancellables)

        injector.$status
            .compactMap { $0 }
            .sink { [weak self] text in
                guard let self, case .busy = self.injectorPhase else { return }
                self.injectorPhase = .busy(text)
                self.pushInjector()
            }
            .store(in: &cancellables)
    }

    // MARK: - messages from the page

    func handle(_ body: Any) async {
        guard let message = body as? [String: Any],
              let type = message["type"] as? String
        else { return }

        switch type {
        case "ready":
            pushState()
            pushInjector()

        case "apply":
            if let values = message["values"] as? [String: Any] { await apply(values) }

        case "inject":
            if let values = message["values"] as? [String: Any] { await apply(values) }
            Task { await runInjector() }

        case "close":
            isOpen = false

        case "injector-dismiss":
            injectorPhase = .hidden
            pushInjector()

        case "copy":
            if let text = message["text"] as? String, !text.isEmpty {
                UIPasteboard.general.string = text
            }

        default:
            log.log(.runtime, "panel: unknown message \(type)")
        }
    }

    // MARK: - apply

    /// Merge the page's draft over the stored profile and commit. Unknown keys
    /// are ignored; a value of the wrong type fails the whole decode and the
    /// profile is left exactly as it was.
    private func apply(_ values: [String: Any]) async {
        var merged = encode(menu.controls)
        for (key, value) in values where merged[key] != nil {
            merged[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let controls = try? JSONDecoder().decode(FeatureControls.self, from: data)
        else {
            log.log(.runtime, "panel apply rejected: draft did not decode")
            toast("Cấu hình không hợp lệ — giữ nguyên bản cũ")
            return
        }
        menu.controls = controls
        // Persisted in `MenuStore`, but that alone only reaches the game on the
        // next inject. Push it into the container now so the file the patch
        // reads is the profile the user just confirmed.
        let written = await injector.stageProfile(controls)
        log.log(.runtime, "panel applied profile for \(menu.selectedGame.rawValue) — \(written.map { "\($0) file(s)" } ?? "container unavailable")")
        pushState()
        if written == nil {
            toast("Đã lưu — container chưa mở được, sẽ ghi khi inject")
        } else {
            toast("Đã áp dụng cấu hình")
        }
    }

    // MARK: - injector

    private func runInjector() async {
        guard authorization.status.isOnline else {
            injectorPhase = .failed("Phiên key chưa hợp lệ")
            pushInjector()
            return
        }
        guard menu.injectStates[menu.selectedGame] != .injecting else { return }
        injectorPhase = .busy("Đang ghi patch vào container…")
        pushInjector()

        await injector.install(
            expectedDigest: authorization.expectedPatchSHA256,
            monitorMs: authorization.patchOpenMonitorMs
        )

        if injector.isActive {
            injectorPhase = .done("Đã nạp — mở game để dùng menu trong game")
        } else {
            injectorPhase = .failed(injector.status ?? "Injector thất bại")
        }
        pushInjector()
        pushState()
    }

    // MARK: - state pushed to the page

    private func pushStateIfOpen() {
        guard isOpen else { return }
        pushState()
    }

    func pushState() {
        guard let json = jsonString(statePayload()) else { return }
        webView?.evaluateJavaScript("window.panelAPI.setState(\(json));", completionHandler: nil)
    }

    func pushInjector() {
        guard let json = jsonString(injectorPayload()) else { return }
        webView?.evaluateJavaScript("window.panelAPI.setInjector(\(json));", completionHandler: nil)
    }

    private func toast(_ text: String) {
        // A bare string is not a valid top-level JSON object for
        // `JSONSerialization`, so quote it through the encoder instead.
        guard let data = try? JSONEncoder().encode(text),
              let literal = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript("window.panelAPI.toast(\(literal));", completionHandler: nil)
    }

    private func statePayload() -> [String: Any] {
        let status = authorization.status
        let key = status.displayKey ?? ""
        let hwid = DeviceIdentityProvider.shared.hwid
        let elapsed = Int(Date().timeIntervalSince(sessionStart))
        let remaining = max(0, Self.sessionSeconds - elapsed)

        return [
            "session": [
                "brand": "VORTEX ARENA",
                "plan": (status.plan ?? "PRO").uppercased(),
                "connected": status.isOnline,
                "daysLeft": daysLeft(until: status.expiresAt),
                "expiry": expiryText(status.expiresAt),
                "key": key,
                "deviceId": hwid,
                "game": menu.selectedGame.displayName,
                "injectActive": injector.isActive,
                "injectState": injectorStateLabel,
                "elapsedSeconds": elapsed,
                "remainingSeconds": remaining,
                "injectUrl": injectURLString(key: key, deviceId: hwid),
            ],
            "values": encode(menu.controls),
            "defaults": encode(FeatureControls()),
        ]
    }

    private func injectorPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "visible": false,
            "state": "idle",
            "title": "ĐANG TẢI KEY INJECTOR...",
            "url": injectURLString(
                key: authorization.status.displayKey ?? "",
                deviceId: DeviceIdentityProvider.shared.hwid
            ),
            "status": "",
        ]
        switch injectorPhase {
        case .hidden:
            break
        case .busy(let text):
            payload["visible"] = true
            payload["state"] = "busy"
            payload["status"] = text
        case .done(let text):
            payload["visible"] = true
            payload["state"] = "done"
            payload["status"] = text
        case .failed(let text):
            payload["visible"] = true
            payload["state"] = "fail"
            payload["status"] = text
        }
        return payload
    }

    private var injectorStateLabel: String {
        switch injectorPhase {
        case .hidden:           return injector.isActive ? "active" : "ready"
        case .busy:             return "injecting"
        case .done:             return "active"
        case .failed:           return "failed"
        }
    }

    // MARK: - helpers

    private func encode(_ controls: FeatureControls) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(controls),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    private func daysLeft(until date: Date?) -> Int {
        guard let date else { return 0 }
        let days = Int(ceil(date.timeIntervalSinceNow / 86_400))
        return max(0, days)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private func expiryText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return PanelStore.dayFormatter.string(from: date)
    }

    /// The line the injector modal shows. The host comes from `FFXCMenuHost`
    /// in Info.plist when the build points at an owned domain; with no host
    /// configured it degrades to the bare query, never to somebody else's
    /// domain.
    private func injectURLString(key: String, deviceId: String) -> String {
        var query = "key=\(key)&deviceId=\(deviceId)"
        if let raw = Bundle.main.object(forInfoDictionaryKey: "FFXCMenuHost") as? String {
            let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !host.isEmpty {
                let trimmed = host.hasSuffix("/") ? String(host.dropLast()) : host
                query = "\(trimmed)/menu?\(query)"
            }
        }
        return query
    }
}
