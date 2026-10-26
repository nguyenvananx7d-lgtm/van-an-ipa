import Foundation

/// iOS-version-agnostic delivery check for the hotfix channel — see
/// `NATIVE_HOOK.md` §5.
///
/// The kernel chain only exists on 17.0–18.7.1. On every other iOS — 18.8
/// through 27 — the cheat reaches the game through the game's own loader: the
/// relay rewrites `GameVarDef.CodePatchUrl` in the var-table response, the game
/// downloads and applies the patch itself, and nothing is written into the
/// container by a second process. A MITM does not care which iOS it fronts, so
/// this route is the version-independent one.
///
/// This check only reports readiness — it never mutates the relay:
///
/// - reachable: the configured host answers `/state` over HTTPS;
/// - codepatch: the `codepatch` feature is switched on (i.e. the operator set
///   `RELAY_PATCH_HOST` / `RELAY_VARCONFIG_PATH` / `RELAY_PATCH_FILE` on the
///   VPS and toggled the feature);
/// - capture mode: no rules at all — the relay is recording, which is exactly
///   the state needed to pin those three variables from a real session.
public struct TrafficHotfixInstaller: Sendable {
    private let log: AppLog

    public init(log: AppLog) {
        self.log = log
    }

    public struct Report: Sendable {
        public let reachable: Bool
        public let codepatchEnabled: Bool
        public let captureMode: Bool
        public let ruleCount: Int
        public let detail: String
    }

    public func check(relayHost: String) async -> Report {
        let host = relayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            log.log(.network, "hotfix channel: no relay host configured")
            return Report(reachable: false, codepatchEnabled: false,
                          captureMode: false, ruleCount: 0,
                          detail: "Set the relay host in Settings first")
        }
        // The relay dashboard (proxy server) lives on the admin port; the host
        // field in Settings carries the bare LAN IP.
        let urlString = "http://\(host):8080/state"
        guard let url = URL(string: urlString) else {
            return Report(reachable: false, codepatchEnabled: false,
                          captureMode: false, ruleCount: 0,
                          detail: "bad relay host")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Report(reachable: false, codepatchEnabled: false,
                              captureMode: false, ruleCount: 0,
                              detail: "not an HTTP answer")
            }
            guard http.statusCode == 200 else {
                log.log(.network, "hotfix channel: /state -> HTTP \(http.statusCode)")
                return Report(reachable: false, codepatchEnabled: false,
                              captureMode: false, ruleCount: 0,
                              detail: "relay answered HTTP \(http.statusCode)")
            }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let features = object?["features"] as? [String: Any]
            let codepatch = features?["codepatch"] as? [String: Any]
            let enabled = (codepatch?["enabled"] as? Bool) ?? false
            let rules = (object?["rules"] as? [Any]) ?? []
            let captureMode = rules.isEmpty

            let detail: String
            if enabled {
                detail = "codepatch armed — the game will fetch and apply the patch itself"
            } else if captureMode {
                detail = "relay is capturing (no rules): play one match, then pin "
                    + "RELAY_PATCH_HOST / RELAY_VARCONFIG_PATH / RELAY_PATCH_FILE "
                    + "from capture.jsonl and enable the codepatch feature"
            } else {
                detail = "relay reachable with \(rules.count) rule(s), codepatch off"
            }
            log.log(.network, "hotfix channel: \(detail)")
            return Report(reachable: true, codepatchEnabled: enabled,
                          captureMode: captureMode, ruleCount: rules.count,
                          detail: detail)
        } catch {
            log.log(.network, "hotfix channel: \(error.localizedDescription)")
            return Report(reachable: false, codepatchEnabled: false,
                          captureMode: false, ruleCount: 0,
                          detail: error.localizedDescription)
        }
    }
}
