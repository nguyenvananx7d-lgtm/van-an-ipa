import Foundation

/// Encrypted-DNS endpoints the shield can point the system resolver at.
///
/// The profile path needs no app extension and no entitlement: iOS accepts a
/// `com.apple.dnsSettings.managed` payload and mDNSResponder speaks DNS over
/// HTTPS to the chosen resolver for *every* app, the game included.
public enum DNSProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case adguard
    case nextdns
    case cloudflare
    case quad9
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cloudflare: return "Cloudflare"
        case .quad9:      return "Quad9"
        case .adguard:    return "AdGuard DNS"
        case .nextdns:    return "NextDNS"
        case .custom:     return "Custom DoH"
        }
    }

    public var detail: String {
        switch self {
        case .cloudflare: return "Fast, no filtering"
        case .quad9:      return "Blocks malware domains"
        case .adguard:    return "Recommended · blocks ads and trackers"
        case .nextdns:    return "Custom blocklist · needs a free ID"
        case .custom:     return "Any HTTPS DoH endpoint"
        }
    }

    /// Bootstrap addresses written into the profile. Empty for anycast
    /// resolvers (NextDNS / custom) so iOS uses the URL host directly.
    public var bootstrap: [String] {
        switch self {
        case .cloudflare: return ["1.1.1.1", "1.0.0.1"]
        case .quad9:      return ["9.9.9.9", "149.112.112.112"]
        case .adguard:    return ["94.140.14.14", "94.140.15.15"]
        case .nextdns, .custom: return []
        }
    }

    public var filtersTrackers: Bool {
        self == .adguard || self == .nextdns
    }

    /// Accepts a bare config ID or a pasted `https://dns.nextdns.io/<id>` URL.
    /// Returns lowercase hex only, so a stray path, query or punctuation in the
    /// clipboard cannot silently break the profile.
    public static func normalizeNextDNSID(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let marker = value.range(of: "dns.nextdns.io/") {
            value = String(value[marker.upperBound...])
        }
        for separator in ["/", "?", "#"] {
            value = value.split(separator: Character(separator)).first.map(String.init) ?? value
        }
        return value.filter { $0.isHexDigit }
    }

    /// `nil` when the provider needs input that is missing or malformed.
    public func dohURL(nextDNSID: String, customURL: String) -> URL? {
        switch self {
        case .cloudflare:
            return URL(string: "https://cloudflare-dns.com/dns-query")
        case .quad9:
            return URL(string: "https://dns.quad9.net/dns-query")
        case .adguard:
            return URL(string: "https://dns.adguard-dns.com/dns-query")
        case .nextdns:
            let id = Self.normalizeNextDNSID(nextDNSID)
            // Config IDs are six hex characters; accept a slightly wider band
            // so a future format does not silently break the field.
            guard (6...16).contains(id.count) else { return nil }
            return URL(string: "https://dns.nextdns.io/\(id)")
        case .custom:
            let raw = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw),
                  url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty else { return nil }
            return url
        }
    }
}
