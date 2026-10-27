import Foundation

/// One normalization for the relay host field.
///
/// The field accepts a bare LAN address (`192.168.0.106`), a host with a port,
/// or a full URL (`https://relay.example.com/relay`). Everything that talks to
/// the relay — profile download, capture probe, `/state` readiness — goes
/// through this type, so the phone and the dashboard cannot disagree about the
/// scheme or the admin port.
///
/// Defaults:
/// - bare IPv4 / `localhost` / `*.local` → `http://host:8080` (LAN, no Caddy)
/// - bare domain → `https://domain` (reverse proxy in front)
/// - explicit scheme is honoured; `http://host` with no port gets `:8080`.
public struct RelayEndpoint: Sendable {
    public let base: URL

    public init?(host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var raw = trimmed
        if !raw.contains("://") {
            let hostPart = raw.split(separator: "/", maxSplits: 1).first.map(String.init) ?? raw
            let name = hostPart.split(separator: ":").first.map(String.init) ?? hostPart
            let octets = name.split(separator: ".")
            let isIPv4 = octets.count == 4 && octets.allSatisfy { Int($0) != nil }
            let isLocal = isIPv4
                || name == "localhost"
                || name.hasSuffix(".local")
                || name.hasPrefix("[")   // IPv6 literal
            if isLocal {
                raw = "http://\(raw)"
                if !hostPart.contains(":") { raw += ":8080" }
            } else {
                raw = "https://\(raw)"
            }
        }

        guard var components = URLComponents(string: raw), components.host != nil else { return nil }
        if components.scheme == "http", components.port == nil { components.port = 8080 }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let url = components.url else { return nil }
        self.base = url
    }

    /// Append a path or a path with a query without percent-encoding the `?`.
    public func url(_ suffix: String) -> URL {
        var text = base.absoluteString
        if !text.hasSuffix("/") { text += "/" }
        return URL(string: text + suffix) ?? base
    }
}
