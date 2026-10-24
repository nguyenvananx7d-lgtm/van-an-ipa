import Foundation

/// Builds a signed-free `.mobileconfig` carrying an encrypted-DNS payload.
///
/// iOS 14+ understands `com.apple.dnsSettings.managed`: after the profile is
/// installed, every resolver query on the device is sent as DNS over HTTPS to
/// the configured URL. There is no packet tunnel, so the game's traffic is not
/// re-routed — only its DNS lookups are encrypted and (with AdGuard/NextDNS)
/// filtered.
public enum DNSProfile {

    public static func make(
        provider: DNSProvider,
        nextDNSID: String,
        customURL: String,
        displayName: String = "Vortex Arena DNS Shield"
    ) -> Data? {
        guard let url = provider.dohURL(nextDNSID: nextDNSID, customURL: customURL) else {
            return nil
        }

        var settings: [String: Any] = [
            "DNSProtocol": "HTTPS",
            "ServerURL": url.absoluteString
        ]
        if !provider.bootstrap.isEmpty {
            settings["ServerAddresses"] = provider.bootstrap
        }

        let content: [String: Any] = [
            "PayloadType": "com.apple.dnsSettings.managed",
            "PayloadVersion": 1,
            "PayloadIdentifier": "com.vortexarena.dns.\(provider.rawValue).\(UUID().uuidString)",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "\(displayName) — \(provider.title)",
            "DNSSettings": settings
        ]

        let root: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": "com.vortexarena.dns.profile.\(UUID().uuidString)",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": displayName,
            "PayloadDescription": "Encrypted DNS (DNS over HTTPS). Installed by Vortex Arena.",
            "PayloadOrganization": "Vortex Arena",
            "PayloadScope": "System",
            "PayloadRemovalDisallowed": false,
            "PayloadContent": [content]
        ]

        return try? PropertyListSerialization.data(
            fromPropertyList: root,
            format: .xml,
            options: 0
        )
    }
}
