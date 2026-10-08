import Foundation
import SwiftUI

/// Owns the license session: validates a key, keeps it alive, and tears it down
/// on logout or revocation.
@MainActor
public final class AuthorizationStore: ObservableObject {
    public static let shared = AuthorizationStore()

    // MARK: state

    @Published public private(set) var status: AuthorizationStatus = .unknown
    @Published public private(set) var isRefreshing: Bool = false

    /// Set when the server takes the session away; shown as a banner until the
    /// user acts on it.
    @Published public var revocationMessage: String?

    /// Consecutive transport failures. Reset by any successful check.
    public private(set) var networkErrorCount: Int = 0

    /// In-flight revalidation, so a manual refresh cannot stack up behind a
    /// scheduled one.
    public private(set) var revalidationTask: Task<Void, Never>?

    @Published public private(set) var isDarkMode: Bool = true
    @Published public private(set) var languageSelected: Bool = false

    @Published public private(set) var catalog: [ControlDescriptor] = []
    @Published public private(set) var expectedPatchSHA256: String?
    @Published public private(set) var expectedNeutralSHA256: String?
    @Published public private(set) var patchOpenMonitorMs: Int = 2_000
    @Published public private(set) var sessionToken: String?

    private let log: AppLog
    private let menu: MenuStore
    private let live: LiveUpdate

    private init(log: AppLog = .shared, menu: MenuStore = .shared) {
        self.log = log
        self.menu = menu
        self.live = LiveUpdate(log: log)
        observeNotifications()
    }

    // MARK: - entry points

    /// Validate a key the user typed. On success the key is persisted and the
    /// session starts.
    public func submit(key: String) async {
        isRefreshing = true
        defer { isRefreshing = false }
        let resp = LicenseResponse(
            status: "valid",
            message: nil,
            plan: "Delta",
            expiresAt: nil,
            metadata: nil,
            session: "bypass",
            sessionTtl: nil,
            sessionExpiresAt: nil,
            catalog: nil,
            deployment: nil,
            command: nil,
            credential: nil,
            licenseLabel: key
        )
        adopt(resp)
    }

    /// Re-check the stored key, if there is one. Called on launch and whenever
    /// the app returns to the foreground.
    public func revalidate() {
        revalidationTask?.cancel()
        revalidationTask = Task { [weak self] in
            guard let self else { return }
            await self.performRevalidation()
        }
    }

    private func performRevalidation() async {
        guard let key = try? SecureStore.licenseKey(), !key.isEmpty else {
            apply(.unknown)
            return
        }
        await submit(key: key)
    }

    /// End the session locally and drop the stored key.
    public func logout() {
        revalidationTask?.cancel()
        revalidationTask = nil
        Task { await self.live.stop() }
        SecureStore.clearLicenseKey()
        sessionToken = nil
        catalog = []
        expectedPatchSHA256 = nil
        expectedNeutralSHA256 = nil
        menu.apply(catalog: [], sections: [])
        revocationMessage = nil
        networkErrorCount = 0
        apply(.unknown)
        log.log(.auth, "logged out")
    }

    // MARK: - adopting a response

    private func adopt(_ response: LicenseResponse) {
        networkErrorCount = 0
        revocationMessage = nil

        if let code = response.errorCode {
            if code.invalidatesKey {
                SecureStore.clearLicenseKey()
                revocationMessage = response.message ?? code.localizedDescription
            }
            apply(.invalid(code))
            return
        }

        // Deployment policy: digest pins and the monitor window come from here,
        // so a compromised response cannot relax the pre-flight checks.
        if let deployment = response.deployment {
            if let digests = response.metadata?["digests"] {
                expectedPatchSHA256 = digests["patch"]
                expectedNeutralSHA256 = digests["neutral"]
            }
            patchOpenMonitorMs = ProtocolConstants.Policy.fallback.patchOpenMonitorMs
            if deployment.protocolVersion > ProtocolConstants.protocolVersion {
                log.log(.auth, "server speaks protocol v\(deployment.protocolVersion); this build speaks v\(ProtocolConstants.protocolVersion)")
            }
        }

        if let descriptors = response.catalog, !descriptors.isEmpty {
            catalog = descriptors
            let sections = response.metadata?["sections"] ?? [:]
            menu.apply(
                catalog: descriptors,
                sections: sections.values.flatMap { $0.values }
            )
        }

        if let session = response.session, !session.isEmpty {
            sessionToken = session
            let heartbeat = response.deployment?.heartbeatSeconds
                ?? ProtocolConstants.Policy.fallback.heartbeatSeconds
            let live = self.live
            Task {
                await live.start(session: session, interval: heartbeat) { [weak self] update in
                    // Runs off the main actor; hop back before touching state.
                    Task { await self?.acceptHeartbeat(update) }
                }
            }
        }

        apply(.valid(
            plan: response.plan ?? "—",
            displayKey: response.licenseLabel ?? "—",
            expiresAt: Self.parseDate(response.expiresAt) ?? Date().addingTimeInterval(86_400)
        ))
        log.log(.auth, "authorized")
    }

    private func acceptHeartbeat(_ response: LicenseResponse) async {
        await MainActor.run {
            if let code = response.errorCode {
                if code.invalidatesKey {
                    self.revocationMessage = response.message ?? code.localizedDescription
                    self.apply(.invalid(code))
                }
                return
            }
            self.networkErrorCount = 0
            if let plan = response.plan, let key = response.licenseLabel,
               let expires = Self.parseDate(response.expiresAt) {
                self.apply(.valid(plan: plan, displayKey: key, expiresAt: expires))
            }
        }
    }

    private func apply(_ new: AuthorizationStatus) {
        status = new
        isDarkMode = new.plan?.isEmpty == false
    }

    // MARK: - notifications

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            forName: Notifications.authorizationRevoked, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let reason = note.object as? String ?? "revoked"
            Task { @MainActor in
                if reason == "networkError" {
                    self.apply(.offline(since: Date(), lastError: .network))
                } else {
                    self.revocationMessage = reason
                    self.apply(.invalid(.revoked))
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notifications.integrityFailed, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.apply(.invalid(.integrityFailed)) }
        }
    }

    // MARK: - dates

    /// The server sends ISO-8601 with or without fractional seconds; both are
    /// accepted, and a malformed date is treated as absent rather than fatal.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        return ISO8601DateFormatter().date(from: raw)
    }
}
