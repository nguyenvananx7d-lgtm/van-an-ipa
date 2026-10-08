import Foundation
import Darwin
import os

/// Locates and opens another app's data container.
///
/// Primary mechanism — the MobileHouseArrest identity-trust route. The bundle
/// is signed as `com.apple.mobile.MobileHouseArrest` (which only works when the
/// install is signed with an enterprise certificate, not a free Apple ID), so
/// the ContainerManager daemon hands this process a *sandbox extension token*
/// for a sibling app's container when queried by bundle id
/// (`container_copy_sandbox_token` + `container_object_sandbox_extension_activate`,
/// see `Injection/MCM/mcm_bridge.m`). No `no-sandbox` entitlement is involved —
/// the token is a legitimate per-container grant, so it survives a normal
/// sandboxed install.
///
/// Fallbacks when the daemon refuses on a given build (e.g. iOS 18.1.x):
/// a filesystem scan of `/var/mobile/Containers/Data/Application` using the
/// Geod-MCM partDomain traversal (`bad_query`, iOS 26+) to get an extension
/// over the root when direct listing is denied, plus an inode walk
/// (`fsgetpath`, `bad_query_list`) to enumerate container UUIDs as a last
/// resort.
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

    /// MCM container class 2 = app data container.
    private let mcmDataClass: UInt64 = 2

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
    /// *running* code signature (SecTask, bridged from Objective-C — the SPI
    /// is ObjC-gated in the SDK). Entitlements listed in
    /// `YABAOCHEAT.entitlements` are only honoured if the install actually
    /// signed for them (ldid / jailbroken signer / a profile that grants them);
    /// a plain free-Apple-ID sideload silently drops them. This distinguishes
    /// "the install kept no-sandbox" from "the entitlement is missing".
    ///
    /// Note: the MCM token bridge does not rely on either entitlement — it is
    /// kept here as a diagnostic only.
    public static func hasEntitlement(_ name: String) -> Bool {
        name.withCString { MCMHasEntitlement($0) }
    }

    /// The two entitlements that decide whether sibling containers are readable:
    /// `no-sandbox` lifts the sandbox entirely; `container-manager` is the
    /// narrower key that permits the MCM directory itself. With the MCM token
    /// bridge both are typically absent, which is expected and fine.
    public var sandboxDiagnosis: String {
        let noSandbox = Self.hasEntitlement("com.apple.private.security.no-sandbox")
        let containerManager = Self.hasEntitlement("com.apple.private.security.container-manager")
        return "no-sandbox=\(noSandbox) container-manager=\(containerManager)"
    }

    // MARK: - discovery

    /// Every installed container on the device, keyed by bundle id.
    ///
    /// Resolution order:
    /// 1. MCM daemon — enumerate class-2 identifiers, then activate each
    ///    container to obtain a sandbox extension (identity-trust route).
    /// 2. Filesystem scan of `/var/mobile/Containers/Data/Application`, with a
    ///    `bad_query` traversal grant on the root when direct listing is denied.
    /// 3. Inode walk (`fsgetpath`) when `FileManager` cannot list the root at all.
    public func installedContainers() -> [String: URL] {
        var out: [String: URL] = [:]

        // 1) MCM daemon — the identity-trust token route.
        var enumerationError: NSString?
        let identifiers = MCMEnumerateIdentifiersForClass(mcmDataClass, 2_048, &enumerationError)
        if !identifiers.isEmpty {
            for bundleID in identifiers {
                var lookupError: NSString?
                guard let path = MCMActivateContainerPath(mcmDataClass, bundleID, false, &lookupError) else {
                    continue
                }
                out[bundleID] = URL(fileURLWithPath: path, isDirectory: true)
            }
            log.log(.mcm, "MCM resolved \(out.count)/\(identifiers.count) container(s)")
            if !out.isEmpty { return out }
        } else if let enumerationError {
            log.log(.mcm, "MCM enumeration unavailable: \(enumerationError)")
        }

        // 2) Filesystem scan fallback.
        guard let containers = dataContainersRoot() else {
            log.log(.mcm, "no data-containers root reachable from \(NSHomeDirectory())")
            return [:]
        }
        let rootPath = containers.path
        let handle = grantTraversal(rootPath)
        defer { releaseTraversal(handle) }

        let keys: [URLResourceKey] = [.isDirectoryKey]
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
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
            lastAccessError = ns.localizedDescription
            log.log(.mcm, "cannot list \(containers.path) (\(ns.code) \(ns.localizedDescription)); grant=\(handle); \(sandboxDiagnosis)")

            // 3) Inode walk last resort.
            for dir in inodeEnumeratedDirectories(rootPath) {
                let url = URL(fileURLWithPath: dir, isDirectory: true)
                guard let id = containerIdentifier(at: url) else { continue }
                out[id] = url
            }
            log.log(.mcm, "inode walk enumerated \(out.count) container(s) under \(containers.path)")
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

    private enum MCMOutcome {
        case resolved(URL)
        case denied(String)
        case bridgeUnavailable
    }

    /// Ask the ContainerManager daemon for the game's container and consume the
    /// returned sandbox token for this process (identity-trust route, mcm_bridge).
    private func mcmContainerPath(bundleID: String) -> MCMOutcome {
        guard MCMBridgeAvailable() else {
            log.log(.mcm, "MCM bridge unavailable (libsystem_containermanager symbols missing)")
            return .bridgeUnavailable
        }
        var lookupError: NSString?
        guard let path = MCMActivateContainerPath(mcmDataClass, bundleID, false, &lookupError) else {
            if let err = lookupError {
                log.log(.mcm, "MCM lookup for \(bundleID) denied: \(err)")
                return .denied(String(err))
            }
            return .bridgeUnavailable
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            log.log(.mcm, "MCM returned no readable container for \(bundleID) at \(path)")
            return .denied("MCM returned an unreachable container path")
        }
        return .resolved(url)
    }

    /// Resolve the live container for a game, and confirm we can write to it.
    ///
    /// Resolution order:
    /// 1. MCM daemon token (identity-trust). This is the route that works on a
    ///    stock, non-jailbroken device when the app is enterprise-signed as
    ///    `com.apple.mobile.MobileHouseArrest`.
    /// 2. Filesystem scan of the data-container root. The root only lists when a
    ///    `no-sandbox` exemption is honoured *or* a `bad_query` traversal grant
    ///    is accepted; otherwise the scan reports `.accessDenied` and the
    ///    concrete daemon error is kept in `lastAccessError`.
    ///
    /// The probe file is the only reliable way to distinguish "container exists
    /// but is sealed" from "container exists": both report success from the
    /// metadata lookup alone.
    public func resolve(game: Game) -> Resolution {
        #if targetEnvironment(simulator)
        log.log(.mcm, "simulator detected; container bridge unavailable")
        return .bridgeUnavailable
        #else
        // 1) MCM daemon — identity-trust token grant.
        switch mcmContainerPath(bundleID: game.bundleIdentifier) {
        case .resolved(let container):
            let data = dataDirectory(in: container)
            if probeWritable(data) {
                log.log(.mcm, "container for \(game.bundleIdentifier) writable at \(data.path) (MCM token)")
                return .resolved(data)
            }
            log.log(.mcm, "MCM resolved \(game.bundleIdentifier) but container not writable at \(data.path): \(lastAccessError ?? "unknown")")
            return .accessDenied
        case .denied(let detail):
            lastAccessError = detail
            log.log(.mcm, "MCM lookup for \(game.bundleIdentifier) denied: \(detail)")
        case .bridgeUnavailable:
            lastAccessError = "MCM bridge unavailable"
        }

        // 2) Filesystem scan fallback.
        guard let containers = dataContainersRoot() else {
            log.log(.mcm, "no data-containers root from \(NSHomeDirectory())")
            lastAccessError = lastAccessError ?? "no data-containers root"
            return .bridgeUnavailable
        }
        let handle = grantTraversal(containers.path)
        defer { releaseTraversal(handle) }

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
            log.log(.mcm, "cannot list \(containers.path) (\(ns.code) \(ns.localizedDescription)); grant=\(handle); container lookup for \(game.bundleIdentifier) failed - access denied, not absent (\(sandboxDiagnosis))")
            return .accessDenied
        }

        guard let container = found else {
            lastAccessError = nil
            log.log(.mcm, "no container for \(game.bundleIdentifier) under \(containers.path)")
            return .notFound
        }

        let data = dataDirectory(in: container)
        guard fm.fileExists(atPath: data.path) else {
            lastAccessError = "container has no data directory"
            log.log(.mcm, "container \(game.bundleIdentifier) has no data directory")
            return .accessDenied
        }

        return probeWritable(data) ? .resolved(data) : .accessDenied
        #endif
    }

    /// Write + delete a probe file. True when the granted sandbox extension (or
    /// an honoured entitlement) actually covers the container.
    private func probeWritable(_ data: URL) -> Bool {
        let probe = data.appendingPathComponent(ContainerBridge.accessProbe)
        do {
            try Data("ffxc".utf8).write(to: probe)
            try fm.removeItem(at: probe)
            lastAccessError = nil
            return true
        } catch {
            lastAccessError = error.localizedDescription
            log.log(.mcm, "probe write failed at \(data.path): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - sandbox extension grants

    /// Geod-MCM partDomain traversal: ask the daemon for a sandbox extension
    /// covering `containerPath` (iOS 26+). Returns a handle to release later, or
    /// a negative value when the daemon refused. After a successful grant the
    /// subtree becomes visible to `FileManager`.
    private func grantTraversal(_ containerPath: String) -> Int64 {
        let clean = containerPath.hasSuffix("/") ? String(containerPath.dropLast()) : containerPath
        guard clean.hasPrefix("/") else { return -1 }
        var pathC = clean.utf8CString.map { Int8($0) }
        return bad_query(&pathC, true, nil, false)
    }

    private func releaseTraversal(_ handle: Int64) {
        if handle >= 0 { bad_query_release(handle) }
    }

    /// Brute-force inode walk of the filesystem (`fsgetpath` + `statfs`) to list
    /// immediate children of `path` when directory listing is denied at the VFS
    /// level. Expensive (default 2M inodes); only used as a last resort.
    private func inodeEnumeratedDirectories(_ path: String) -> [String] {
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard clean.hasPrefix("/") else { return [] }
        var pathC = clean.utf8CString.map { Int8($0) }
        guard let result = bad_query_list(&pathC, 2_000_000) else {
            log.log(.mcm, "inode walk unavailable for \(clean)")
            return []
        }
        defer { free(result) }
        return String(cString: result).components(separatedBy: "\n").filter { !$0.isEmpty }
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