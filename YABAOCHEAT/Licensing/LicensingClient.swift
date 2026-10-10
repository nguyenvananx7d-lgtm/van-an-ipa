import Foundation

/// Talks to the licensing server.
///
/// Everything is a single POST to `/api` with a JSON body; the server answers
/// with a signed envelope. Transient failures are retried up to the server's
/// `max_network_errors` before the app gives up and shows offline.
public actor LicensingClient {
    public static let shared = LicensingClient()

    /// Recovered from the decompiled session factory at `0x1000ea25c`, which
    /// passes these two doubles straight into
    /// `setTimeoutIntervalForRequest:` / `setTimeoutIntervalForResource:`:
    /// `0x402E000000000000` and `0x4034000000000000` respectively. They are
    /// hardcoded, not read from the server policy.
    public static let requestTimeout: TimeInterval = 15.0
    public static let resourceTimeout: TimeInterval = 20.0

    private let session: URLSession
    private let verifier: LicenseVerifier
    private var policy: ProtocolConstants.Policy = .fallback

    public init(session: URLSession? = nil, verifier: LicenseVerifier = .pinned()) {
        if let session {
            self.session = session
        } else {
            // Recovered verbatim. Ephemeral configuration, cache explicitly
            // nil'd, and `waitsForConnectivity = false` so a request fails fast
            // on a dead network instead of hanging until the resource timeout.
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = Self.requestTimeout
            config.timeoutIntervalForResource = Self.resourceTimeout
            config.waitsForConnectivity = false
            config.urlCache = nil
            self.session = URLSession(configuration: config)
        }
        self.verifier = verifier
    }

    public func currentPolicy() -> ProtocolConstants.Policy { policy }

    // MARK: - requests

    /// Validate a license key and, on success, establish a session.
    public func authorize(key: String) async throws -> LicenseResponse {
        let identity = DeviceIdentityProvider.shared.identity
        let body: [String: Any] = [
            "product": ProtocolConstants.productId,
            "key": key,
            "device_credential_id": DeviceIdentityProvider.shared.credentialId,
            "device_public_key": DeviceIdentityProvider.shared.devicePublicKey,
            "hwid": identity.hwid,
            "mac": identity.mac,
            "device_name": identity.deviceName,
            "ios_version": identity.iOSVersion,
            "model": identity.iPhoneModel,
            ProtocolConstants.Key.protocolVersion: policy.protocolVersion,
        ]

        let response = try await post(body)
        if let policyJSON = response.policy {
            policy = ProtocolConstants.Policy(from: policyJSON)
        }
        return try verifier.verify(response.envelope)
    }

    /// Refresh an established session. The session token doubles as the
    /// anti-replay nonce: the server refuses a sequence it has already seen.
    public func heartbeat(session: String, sequence: Int) async throws -> LicenseResponse {
        let body: [String: Any] = [
            "product": ProtocolConstants.productId,
            "session": session,
            "sequence": sequence,
            "mac": DeviceIdentityProvider.shared.mac,
            ProtocolConstants.Key.protocolVersion: policy.protocolVersion,
        ]
        let response = try await post(body)
        return try verifier.verify(response.envelope)
    }

    // MARK: - transport

    private struct Raw: Decodable {
        let data: String
        let ts: Int
        let sig: String
        let sequence: Int
        let aux: [String: String]?
        let leaseSeconds: Int
        let mac: String?
        let policy: [String: String]?
    }

    private func post(_ body: [String: Any]) async throws -> (envelope: SignedEnvelope, policy: [String: String]?) {
        var request: URLRequest
        if let url = URL(string: ProtocolConstants.endpoint) {
            request = URLRequest(url: url)
        } else {
            request = URLRequest(url: URL(fileURLWithPath: "/dev/null"))
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ProtocolConstants.requestTag, forHTTPHeaderField: "X-FFXC-Client")
        request.setValue(String(ProtocolConstants.protocolVersion), forHTTPHeaderField: "X-FFXC-Protocol")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var lastError: LicenseError = LicenseError(code: .network)
        for attempt in 0..<max(1, policy.maxNetworkErrors) {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = LicenseError(code: .network)
                    continue
                }
                guard http.statusCode == 200 else {
                    // 4xx is a verdict, not a transport problem: stop retrying.
                    let code: LicenseErrorCode = http.statusCode == 403 ? .revoked
                        : http.statusCode == 410 ? .deleted
                        : http.statusCode == 409 ? .deviceMismatch
                        : http.statusCode >= 500 ? .server
                        : .invalid
                    throw LicenseError(code: code)
                }
                let raw = try JSONDecoder().decode(Raw.self, from: data)
                let envelope = SignedEnvelope(
                    data: raw.data, ts: raw.ts, sig: raw.sig,
                    sequence: raw.sequence, aux: raw.aux,
                    leaseSeconds: raw.leaseSeconds, mac: raw.mac
                )
                return (envelope, raw.policy)
            } catch let error as LicenseError {
                throw error
            } catch is DecodingError {
                throw LicenseError(code: .malformedResponse)
            } catch {
                lastError = LicenseError(code: .network)
                if attempt + 1 < max(1, policy.maxNetworkErrors) {
                    try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 500_000_000)
                }
            }
        }
        throw lastError
    }
}

