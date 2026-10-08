import Foundation
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
    public static let mcmMetadataPlist = ".com.apple.mobile_container_manager.metadata.plist"
    public static let mcmIdentifierKey = "MCMMetadataIdentifier"

    /// Dropped into the target container to prove the path is genuinely writable
    /// before the payload is installed.
    public static let accessProbe = ".ffxc_access_probe"

    /// Staged patch filename, inside whichever payload directory is resolved.
    public static let patchName = "Assembly-CSharp-patch.bytes"

    private let log: AppLog
    private let fm = FileManager.default

    public init(log: AppLog) {
        self.log = log
    }

    // MARK: - discovery

    /// Every installed container on the device, keyed by bundle id.
    public func installedContainers() -> [String: URL] {
        guard let containers = dataContainersRoot() else {
            log.log(.mcm, "no data-containers root reachable from \(NSHomeDirectory())")
            return [:]
        }

        var out: [String: URL] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let entries = try? fm.contentsOfDirectory(
            at: containers,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            log.log(.mcm, "cannot list \(containers.path)")
            return out
        }

        for entry in entries {
            guard let id = containerIdentifier(at: entry) else { continue }
            out[id] = entry
        }
        log.log(.mcm, "found \(out.count) container(s) under \(containers.path)")
        return out
    }

    /// `/var/mobile/Containers/Data/Application`, walked up to rather than
    /// assumed: `Documents` sits inside the app's own container, which is one
    /// level below the shared `Application` directory, so a single
    /// `deletingLastPathComponent` lands on our own container and enumerates
    /// nothing useful. Each component is matched so an unexpected depth fails
    /// loudly instead of silently listing the wrong directory.
    private func dataContainersRoot() -> URL? {
        guard var url = fm.urls(for: .documentDirectory, in: .userDomainMask).first?
            .deletingLastPathComponent() else { return nil }

        for _ in 0..<8 {
            let parent = url.deletingLastPathComponent()
            if url.lastPathComponent == "Application",
               parent.lastPathComponent == "Data",
               parent.deletingLastPathComponent().lastPathComponent == "Containers" {
                return url
            }
            url = parent
        }
        return nil
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
        let plist = container.appendingPathComponent(ContainerBridge.mcmMetadataPlist)
        guard let data = try? Data(contentsOf: plist) else { return nil }
        guard let object = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else { return nil }

        if let ident = object[ContainerBridge.mcmIdentifierKey] as? String { return ident }
        // Some builds nest it under "Metadata".
        if let nested = object["Metadata"] as? [String: Any],
           let ident = nested[ContainerBridge.mcmIdentifierKey] as? String {
            return ident
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
    public func resolve(game: Game) -> Resolution {
        #if targetEnvironment(simulator)
        log.log(.mcm, "simulator detected; container bridge unavailable")
        return .bridgeUnavailable
        #else
        guard let container = installedContainers()[game.bundleIdentifier] else {
            log.log(.mcm, "no container for \(game.bundleIdentifier)")
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

