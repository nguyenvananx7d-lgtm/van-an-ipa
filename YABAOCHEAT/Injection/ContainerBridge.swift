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

    private let log: AppLog
    private let fm = FileManager.default

    public init(log: AppLog) {
        self.log = log
    }

    // MARK: - discovery

    /// Every installed container on the device, keyed by bundle id.
    public func installedContainers() -> [String: URL] {
        let root = fm.urls(for: .documentDirectory, in: .userDomainMask).first?
            .deletingLastPathComponent()   // .../Documents/../Containers
        guard let containers = root else { return [:] }

        var out: [String: URL] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let entries = try? fm.contentsOfDirectory(
            at: containers,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return out }

        for entry in entries {
            guard let id = containerIdentifier(at: entry) else { continue }
            out[id] = entry
        }
        return out
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

        let data = container.appendingPathComponent("data")
        guard fm.fileExists(atPath: data.path) else {
            log.log(.mcm, "container \(game.bundleIdentifier) has no data directory")
            return .accessDenied
        }

        let probe = data.appendingPathComponent(ContainerBridge.accessProbe)
        do {
            try Data("ffxc".utf8).write(to: probe)
            try fm.removeItem(at: probe)
            log.log(.mcm, "container for \(game.bundleIdentifier) writable")
            return .resolved(data)
        } catch {
            log.log(.mcm, "container for \(game.bundleIdentifier) not writable: \(error.localizedDescription)")
            return .accessDenied
        }
        #endif
    }

    // MARK: - paths inside a resolved container

    /// Where the IL2CPP metadata patch is written.
    public func patchURL(in data: URL, game: Game) -> URL {
        data
            .appendingPathComponent("Assembly-CSharp-patch.bytes")
    }

    /// Where the runtime config the payload reads at startup is written.
    public func configURL(in data: URL, game: Game) -> URL {
        data.appendingPathComponent(game.configFileName)
    }
}

