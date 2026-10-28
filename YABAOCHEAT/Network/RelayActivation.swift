import Foundation

/// Activation through the relay's web portal.
///
/// The relay usage has no injector step: the device installs the profile, the
/// tunnel carries the game's traffic, and the menu key is exchanged at
/// `<relay>/menu/login`. That endpoint forwards to the licensing backend and
/// answers with the same signed envelope the desktop client uses, so the inner
/// payload is the `LicenseResponse` this app already knows.
///
/// Signature policy: the envelope is verified against the Ed25519 public key
/// bundled as `client_public_key.der`. The relay signs with the matching
/// private key, so a relay that cannot produce that signature is refused rather
/// than trusted for its payload alone.
public struct RelayActivation: Sendable, Equatable {
    public let key: String
    public let plan: String
    public let session: String
    public let expiresAt: Date?
    public let deviceKey: String
    /// Server wording for a non-`valid` verdict, if it sent one.
    public let message: String?
}

public enum RelayActivationError: LocalizedError {
    case missingHost
    case badHost
    case unreachable(String)
    case rejected(LicenseErrorCode, String)
    case verification(String)
    case malformed

    public var errorDescription: String? {
        switch self {
        case .missingHost:
            return "Chưa nhập máy chủ relay."
        case .badHost:
            return "Địa chỉ máy chủ không hợp lệ."
        case .unreachable(let detail):
            return "Không kết nối được máy chủ: \(detail)"
        case .rejected(_, let detail):
            return detail.isEmpty ? "Key không hợp lệ." : detail
        case .verification(let detail):
            return detail
        case .malformed:
            return "Máy chủ trả về dữ liệu không đọc được."
        }
    }
}

public enum RelayActivationClient {

    // MARK: - host

    /// The relay host this build should talk to before the user types one.
    /// A value in `UserDefaults` wins; otherwise the optional
    /// `FFXCRelayHost` Info.plist entry baked in at build time is used.
    public static var configuredHost: String {
        let stored = (UserDefaults.standard.string(forKey: "relay.host") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }
        if let baked = Bundle.main.object(forInfoDictionaryKey: "FFXCRelayHost") as? String {
            return baked.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// Accepts what a person actually types: `host`, `host:port`,
    /// `https://host` or `https://host/relay` when Caddy fronts the relay.
    public static func baseURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var text = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The value a proxy app (Super Proxy, Shadowrocket, the profile's manual
    /// entry) wants: `host:port`. The relay's proxy listener defaults to 1299
    /// and the URL rarely carries a port, so fall back to that.
    public static func proxyEndpoint(from raw: String) -> String? {
        guard let url = baseURL(from: raw), let host = url.host else { return nil }
        let port = url.port ?? 1299
        return "\(host):\(port)"
    }

    public static func menuURL(
        host raw: String,
        key: String,
        deviceKey: String,
        session: String? = nil
    ) -> URL? {
        guard let base = baseURL(from: raw) else { return nil }
        var components = URLComponents(url: base.appendingPathComponent("menu"), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = []
        if !deviceKey.isEmpty { items.append(URLQueryItem(name: "k", value: deviceKey)) }
        if !key.isEmpty { items.append(URLQueryItem(name: "key", value: key)) }
        if let session, !session.isEmpty { items.append(URLQueryItem(name: "session", value: session)) }
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url
    }

    /// The MIZZE-style portal page: key, password, ID máy, Enter, reset note.
    public static func loginURL(host raw: String, key: String, deviceKey: String) -> URL? {
        guard let base = baseURL(from: raw) else { return nil }
        var components = URLComponents(url: base.appendingPathComponent("login"), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = []
        if !deviceKey.isEmpty { items.append(URLQueryItem(name: "k", value: deviceKey)) }
        if !key.isEmpty { items.append(URLQueryItem(name: "key", value: key)) }
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url
    }

    public static func profileURL(host raw: String) -> URL? {
        guard let base = baseURL(from: raw) else { return nil }
        return base.appendingPathComponent("profile.mobileconfig")
    }

    public static func certificateURL(host raw: String) -> URL? {
        guard let base = baseURL(from: raw) else { return nil }
        return base.appendingPathComponent("ca.cer")
    }

    // MARK: - calls

    /// Exchange a key for a relay session. `password` is the second factor the
    /// portal asks for; a key minted without one accepts an empty string.
    public static func activate(
        host rawHost: String,
        key: String,
        password: String,
        deviceKey: String
    ) async throws -> RelayActivation {
        guard !rawHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayActivationError.missingHost
        }
        guard let base = baseURL(from: rawHost) else { throw RelayActivationError.badHost }

        let identity = DeviceIdentityProvider.shared
        let body: [String: Any] = [
            "product": ProtocolConstants.productId,
            "key": key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            "password": password,
            "hwid": deviceKey,
            "mac": identity.mac,
            "device_name": identity.deviceName,
            "ios_version": identity.iOSVersion,
            "model": identity.iPhoneModel,
            "device_credential_id": deviceKey,
            "protocol_version": ProtocolConstants.protocolVersion,
        ]

        let envelope = try await post(base.appendingPathComponent("menu/login"), body: body)
        let payload = try decode(envelope)

        if payload.status != "valid" {
            let message = payload.message
                ?? payload.errorCode?.localizedDescription
                ?? "Key hoặc mật khẩu không hợp lệ."
            throw RelayActivationError.rejected(payload.errorCode ?? .invalid, message)
        }
        guard let session = payload.session, !session.isEmpty else {
            throw RelayActivationError.malformed
        }

        return RelayActivation(
            key: payload.licenseLabel ?? key,
            plan: payload.plan ?? "PRO",
            session: session,
            expiresAt: AuthorizationStore.parseDate(payload.expiresAt),
            deviceKey: deviceKey,
            message: payload.message
        )
    }

    /// Release this device from the key. The relay counts the calls, so the
    /// portal is the authority on the two-per-day limit; an error here means
    /// the limit is spent or the session died.
    @discardableResult
    public static func resetDevice(host rawHost: String, session: String) async throws -> String {
        guard let base = baseURL(from: rawHost) else { throw RelayActivationError.badHost }
        let body: [String: Any] = ["session": session, "action": "resetDevice"]
        let envelope = try await post(base.appendingPathComponent("menu/reset"), body: body)
        let payload = try decode(envelope)
        if payload.status != "valid" {
            let message = payload.message
                ?? payload.errorCode?.localizedDescription
                ?? "Không reset được thiết bị."
            throw RelayActivationError.rejected(payload.errorCode ?? .invalid, message)
        }
        return payload.message ?? "Đã reset thiết bị."
    }

    // MARK: - transport

    private static func post(_ url: URL, body: [String: Any]) async throws -> SignedEnvelope {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ProtocolConstants.requestTag, forHTTPHeaderField: "X-FFXC-Client")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RelayActivationError.unreachable("không có phản hồi HTTP")
            }
            guard http.statusCode == 200 else {
                // The relay answers 4xx/5xx for transport problems; verdicts
                // travel inside a 200 envelope, so this is not a key verdict.
                throw RelayActivationError.unreachable("HTTP \(http.statusCode)")
            }
            return try JSONDecoder().decode(SignedEnvelope.self, from: data)
        } catch let error as RelayActivationError {
            throw error
        } catch is DecodingError {
            throw RelayActivationError.malformed
        } catch {
            // Carry the exact URL in the message: "could not connect" without
            // the scheme and port has cost more debugging time than any other
            // error in this flow.
            throw RelayActivationError.unreachable(
                "\(url.absoluteString) — \(error.localizedDescription)"
            )
        }
    }

    private static func decode(_ envelope: SignedEnvelope) throws -> LicenseResponse {
        do {
            return try LicenseVerifier.pinned().verify(envelope)
        } catch LicenseVerifier.Failure.replayDetected {
            throw RelayActivationError.verification(
                "Phản hồi của relay đã cũ. Kiểm tra đồng hồ máy rồi thử lại."
            )
        } catch {
            throw RelayActivationError.verification(
                "Chữ ký của relay không hợp lệ. Kiểm tra lại máy chủ."
            )
        }
    }
}
