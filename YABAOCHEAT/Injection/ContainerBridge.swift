import Foundation
import Security
import os

/// Locates and opens another app's data container.
///
/// The bundle ships with `CFBundleIdentifier` set to
/// `com.apple.mobile.MobileHouseArrest` — the system house-arrest daemon's
/// identifier. That is what lets a single installed binary speak the
/// `MobileHouseArrest` service on both sides of the connection: the identity the
/// platform presents is the one the daemon already trusts for file transfer, so
/// no additional entitlement is needed to reach a sibling container.
public final class ContainerBridge: @unchecked Sendable {
    public static let shared = ContainerBridge(log: AppLog.shared)

    /// `mobile_container_manager` metadata, read to turn a bundle id into a path.
    /// iOS alternates between a leading dot and a leading underscore depending
    /// on version, so both forms are probed and the first one that parses wins.
    public static let mcmMetadataPlist = ".com.apple.mobile_container_manager.metadata.plist"
    public static let mcmMetadataPlistWithUnderscore = "_com.apple.mobile_container_manager.metadata.plist"
    public static let mcmIdentifierKey = "MCMMetadataIdentifier"

    /// Dropped into the target container to prove the path is genuinely writable
    /// before the payload is installed.
    public static let accessProbe = ".ffxc_access_probe"

    /// Staged patch filename, inside whichever payload directory is resolved.
    public static let patchName = "Assembly-CSharp-patch.bytes"

    private let log: AppLog
    private let fm = FileManager.default

    /// Last concrete reason a resolution failed, surfaced in the UI so a red
    /// banner says *why* (sandbox denied vs game absent) instead of a generic
    /// message. MainActor-facing reads; mutations happen on any thread.
    public private(set) var lastAccessError: String?

    public init(log: AppLog) {
        self.log = log
    }

    // MARK: - entitlement introspection

    /// True when this process currently holds an entitlement, read from the
    /// *running* code signature via `SecTask`. Entitlements listed in
    /// `YABAOCHEAT.entitlements` are only honoured if the install actually
    /// signed for them (ldid / jailbroken signer / a profile that grants them);
    /// a plain free-Apple-ID sideload silently drops them. This distinguishes
    /// "the install kept no-sandbox" from "the entitlement is missing".
    public static func hasEntitlement(_ name: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, name as CFString, nil)
        if let bool = value as? Bool { return bool }
        if let num = value as? NSNumber { return num.boolValue }
        return false
    }

    /// The two entitlements that decide whether sibling containers are readable:
    /// `no-sandbox` lifts the sandbox entirely; `container-manager` is the
    /// narrower key that permits the MCM directory itself.
    public var sandboxDiagnosis: String {
        let noSandbox = Self.hasEntitlement("com.apple.private.security.no-sandbox")
        let containerManager = Self.hasEntitlement("com.apple.private.security.container-manager")
        return "no-sandbox=\(noSandbox) container-manager=\(containerManager)"
    }

    // MARK: - discovery

    /// Every installed container on the device, keyed by bundle id.
    ///
    /// The underlying `/var/mobile/Containers/Data/Application` directory is
    /// where every app's data container lives, regardless of which app we are.
    /// A caller needs read access there (a sandbox exemption ran through the
    /// `com.apple.private.security.container-manager` entitlement, or root) for
    /// this to return anything; failures are logged with the concrete POSIX
    /// error so a `notFound` result is distinguishable from "no permission".
    public func installedContainers() -> [String: URL] {
        guard let containers = dataContainersRoot() else {
            log.log(.mcm, "no data-containers root reachable from \(NSHomeDirectory())")
            return [:]
        }

        var out: [String: URL] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        do {
            let entries = try fm.contentsOfDirectory(
                at: containers,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
            lastAccessError = nil
            for entry in entries {
                guard let id = containerIdentifier(at: entry) else { continue }
                out[id] = entry
            }
            log.log(.mcm, "found \(out.count) container(s) under \(containers.path)")
        } catch {
            let ns = error as NSError
            let diag = sandboxDiagnosis
            lastAccessError = ns.localizedDescription
            log.log(.mcm, "cannot list \(containers.path) (\(ns.code) \(ns.localizedDescription)); \(diag)")
        }
        return out
    }

    /// `/var/mobile/Containers/Data/Application`, located by walking up from
    /// our own `Documents` until the `Containers/Data/Application` chain is
    /// found, with the canonical absolute path as a fallback for non-standard
    /// container roots. Each component is matched so an unexpected depth fails
    /// loudly instead of silently enumerating the wrong directory.
    private func dataContainersRoot() -> URL? {
        let candidates = canonicalRoots() + walkedUpRoots()
        for url in candidates {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }
        return nil
    }

    /// The well-known container root, in the two spellings the filesystem
    /// accepts (`/var` is a symlink to `/private/var`).
    private func canonicalRoots() -> [URL] {
        [
            URL(fileURLWithPath: "/var/mobile/Containers/Data/Application", isDirectory: true),
            URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application", isDirectory: true),
        ]
    }

    /// Walk up from `Documents`, matching each path component so the loop stops
    /// exactly on the shared `Application` directory and never one level early
    /// (which lands on our own container and enumerates nothing useful).
    private func walkedUpRoots() -> [URL] {
        guard var url = fm.urls(for: .documentDirectory, in: .userDomainMask).first?
            .deletingLastPathComponent() else { return [] }

        var matches: [URL] = []
        for _ in 0..<8 {
            let parent = url.deletingLastPathComponent()
            if url.lastPathComponent == "Application",
               parent.lastPathComponent == "Data",
               parent.deletingLastPathComponent().lastPathComponent == "Containers" {
                matches.append(url)
            }
            url = parent
        }
        return matches
    }

    /// The directory the target's writable files live in. The container root is
    /// the data directory itself; a nested `data` folder is only present in
    /// layouts that keep one, so it wins when it exists.
    private func dataDirectory(in container: URL) -> URL {
        let nested = container.appendingPathComponent("data")
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: nested.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return nested
        }
        return container
    }

    /// Read the `MCMMetadataIdentifier` out of a container's metadata plist.
    public func containerIdentifier(at container: URL) -> String? {
        for name in [ContainerBridge.mcmMetadataPlist, ContainerBridge.mcmMetadataPlistWithUnderscore] {
            let plist = container.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: plist) else { continue }
            guard let object = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any] else { continue }

            if let ident = object[ContainerBridge.mcmIdentifierKey] as? String { return ident }
            // Some builds nest it under "Metadata".
            if let nested = object["Metadata"] as? [String: Any],
               let ident = nested[ContainerBridge.mcmIdentifierKey] as? String {
                return ident
            }
        }
        return nil
    }

    // MARK: - resolution

    public enum Resolution: Sendable {
        case resolved(URL)
        case notFound
        case accessDenied
        case bridgeUnavailable
    }

    /// Resolve the live container for a game, and confirm we can write to it.
    ///
    /// The probe file is the only reliable way to distinguish "container exists
    /// but is sealed" from "container exists": both report success from the
    /// metadata lookup alone.
    ///
    /// A `notFound` result is only produced when the container root was readable
    /// and the bundle id was genuinely absent from it. If the root itself cannot
    /// be listed — e.g. the sandbox exemption was not honoured — we return
    /// `accessDenied`, logged with the underlying error, rather than lying about
    /// the game's install state.
    public func resolve(game: Game) -> Resolution {
        #if targetEnvironment(simulator)
        log.log(.mcm, "simulator detected; container bridge unavailable")
        return .bridgeUnavailable
        #else
        guard let containers = dataContainersRoot() else {
            log.log(.mcm, "no data-containers root from \(NSHomeDirectory())")
            return .bridgeUnavailable
        }

        var found: URL?
        let keys: [URLResourceKey] = [.isDirectoryKey]
        do {
            let entries = try fm.contentsOfDirectory(
                at: containers,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
            for entry in entries {
                guard containerIdentifier(at: entry) == game.bundleIdentifier else { continue }
                found = entry
                break
            }
        } catch {
            let ns = error as NSError
            lastAccessError = ns.localizedDescription
            log.log(.mcm, "cannot list \(containers.path) (\(ns.code) \(ns.localizedDescription)); container lookup for \(game.bundleIdentifier) failed - access denied, not absent (\(sandboxDiagnosis))")
            return .accessDenied
        }

        guard let container = found else {
            lastAccessError = nil
            log.log(.mcm, "no container for \(game.bundleIdentifier) under \(containers.path)")
            return .notFound
        }

        let data = dataDirectory(in: container)
        guard fm.fileExists(atPath: data.path) else {
            log.log(.mcm, "container \(game.bundleIdentifier) has no data directory")
            return .accessDenied
        }

        let probe = data.appendingPathComponent(ContainerBridge.accessProbe)
        do {
            try Data("ffxc".utf8).write(to: probe)
            try fm.removeItem(at: probe)
            log.log(.mcm, "container for \(game.bundleIdentifier) writable at \(data.path)")
            return .resolved(data)
        } catch {
            lastAccessError = error.localizedDescription
            log.log(.mcm, "container for \(game.bundleIdentifier) not writable at \(data.path): \(error.localizedDescription)")
            return .accessDenied
        }
        #endif
    }

    // MARK: - paths inside a resolved container

    /// Every directory the target may read a staged file from: the resolved
    /// data directory plus its `Documents` child, which is where
    /// `persistentDataPath` points. A target reads whichever it was built
    /// against, so both are staged rather than guessing.
    public func payloadDirectories(in data: URL) -> [URL] {
        var dirs = [data]
        let documents = data.appendingPathComponent("Documents")
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: documents.path, isDirectory: &isDirectory), isDirectory.boolValue {
            dirs.append(documents)
        }
        return dirs
    }

    /// Where the IL2CPP metadata patch is written. First entry is the primary.
    public func patchURLs(in data: URL, game: Game) -> [URL] {
        payloadDirectories(in: data).map { $0.appendingPathComponent(ContainerBridge.patchName) }
    }

    /// Where the runtime config the payload reads at startup is written.
    public func configURLs(in data: URL, game: Game) -> [URL] {
        payloadDirectories(in: data).map { $0.appendingPathComponent(game.configFileName) }
    }
}