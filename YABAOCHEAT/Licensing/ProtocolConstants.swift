import Foundation

/// Protocol constants exchanged with the licensing server.
///
/// These keys are the wire contract. The server is free to omit any of them; the
/// defaults here are what the app assumes when a field is absent.
public enum ProtocolConstants {
    public static let endpoint = "https://crackbomaydi.dev/api"

    /// Sent with every request so the server can refuse clients it no longer
    /// supports.
    public static let protocolVersion = 3

    /// Product identifier and the value the server binds a device to.
    public static let productId = "pkg_40921350d3307e51491f27cb"
    public static let requestTag = "FFXC-V4|pkg_40921350d3307e51491f27cb"

    public enum Key {
        public static let protocolVersion = "protocol_version"
        public static let secureTransportRequired = "secure_transport_required"
        public static let heartbeatSeconds = "heartbeat_seconds"
        public static let maxNetworkErrors = "max_network_errors"
        public static let receiptTimeout = "receipt_timeout_seconds"
        public static let receiptRetention = "receipt_retention_seconds"
        public static let patchOpenMonitorMs = "patch_open_monitor_ms"
        public static let clientPublicKey = "client_public_key"
        public static let devicePublicKey = "device_public_key"

        // authorization payload
        public static let status = "status"
        public static let message = "message"
        public static let plan = "plan"
        public static let expiresAt = "expiresAt"
        public static let metadata = "metadata"
        public static let session = "session"
        public static let sessionTtl = "session_ttl"
        public static let sessionExpiresAt = "session_expiresAt"
        public static let catalog = "catalog"
        public static let deployment = "deployment"
        public static let command = "command"
        public static let credential = "credential"
        public static let licenseLabel = "license_label"
        public static let artifact = "artifact"
        public static let unitMask = "unit_mask"
        public static let disableSequence = "disable_sequence"
        public static let disableMac = "disable_mac"
        public static let sequence = "sequence"
        public static let leaseSeconds = "lease_seconds"
        public static let state = "state"
        public static let aux = "aux"
        public static let mac = "mac"
        public static let data = "data"
        public static let ts = "ts"
        public static let sig = "sig"
    }

    /// Server-supplied policy with conservative fallbacks.
    public struct Policy: Sendable {
        public let protocolVersion: Int
        public let heartbeatSeconds: Int
        public let maxNetworkErrors: Int
        public let receiptTimeout: Int
        public let receiptRetention: Int
        public let patchOpenMonitorMs: Int
        public let secureTransportRequired: Bool
        public let clientPublicKey: Data?

        public static let fallback = Policy(
            protocolVersion: ProtocolConstants.protocolVersion,
            heartbeatSeconds: 90,
            maxNetworkErrors: 3,
            receiptTimeout: 10,
            receiptRetention: 30 * 24 * 60 * 60,
            patchOpenMonitorMs: 2_000,
            secureTransportRequired: true,
            clientPublicKey: nil
        )

        public init(
            protocolVersion: Int,
            heartbeatSeconds: Int,
            maxNetworkErrors: Int,
            receiptTimeout: Int,
            receiptRetention: Int,
            patchOpenMonitorMs: Int,
            secureTransportRequired: Bool,
            clientPublicKey: Data?
        ) {
            self.protocolVersion = protocolVersion
            self.heartbeatSeconds = heartbeatSeconds
            self.maxNetworkErrors = maxNetworkErrors
            self.receiptTimeout = receiptTimeout
            self.receiptRetention = receiptRetention
            self.patchOpenMonitorMs = patchOpenMonitorMs
            self.secureTransportRequired = secureTransportRequired
            self.clientPublicKey = clientPublicKey
        }

        /// Parse the policy block the server sends alongside the first response.
        public init(from json: [String: Any]) {
            func int(_ k: String, _ fallback: Int) -> Int {
                (json[k] as? NSNumber)?.intValue ?? fallback
            }
            protocolVersion = int(Key.protocolVersion, ProtocolConstants.protocolVersion)
            heartbeatSeconds = int(Key.heartbeatSeconds, 90)
            maxNetworkErrors = int(Key.maxNetworkErrors, 3)
            receiptTimeout = int(Key.receiptTimeout, 10)
            receiptRetention = int(Key.receiptRetention, 30 * 24 * 60 * 60)
            patchOpenMonitorMs = int(Key.patchOpenMonitorMs, 2_000)
            secureTransportRequired = (json[Key.secureTransportRequired] as? NSNumber)?.boolValue ?? true
            if let b64 = json[Key.clientPublicKey] as? String {
                clientPublicKey = Data(base64Encoded: b64)
            } else {
                clientPublicKey = nil
            }
        }
    }
}

/// Notification names the app posts for cross-component state changes.
public enum Notifications {
    public static let runtimeCommandUpdated = Notification.Name("FFXCAuthorizationRefreshed")
    public static let authorizationRevoked  = Notification.Name("FFXCAuthorizationRevoked")
    public static let integrityFailed        = Notification.Name("FFXCIntegrityFailed")
    public static let integrityRestored      = Notification.Name("FFXCIntegrityRestored")
    public static let languageSelected       = Notification.Name("ffxc.langSelected")
}
