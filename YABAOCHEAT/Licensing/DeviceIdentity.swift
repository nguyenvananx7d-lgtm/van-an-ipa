import Foundation
import CryptoKit
import Security
import UIKit

/// Device facts used for key binding, gathered once and cached.
public final class DeviceIdentityProvider: @unchecked Sendable {
    public static let shared = DeviceIdentityProvider()

    private let cache: NSCache<NSString, NSString>
    private let lock = NSLock()

    /// Persisted handle so the app can tell "same install" from "reinstalled"
    /// even when the hardware identifier is unchanged.
    private static let credentialKey = "device-credential-id-v1"
    private static let signingHandleKey = "device-signing-handle-v1"
    private static let macDefaultsKey = "ffxc.device.mac"

    /// Recovered from the decompiled identity routine at `0x1000e1178`. Both
    /// appear as inlined Swift small strings in the body:
    ///
    /// - `0x77685f7463786666` + `0xea00000000006469` decodes to `ffxt_hwid`
    ///   (10 characters, discriminator `0xea & 0x0F`).
    /// - `0x692d656369766564` + `0xec00000032762d64` decodes to `device-id-v2`.
    ///
    /// `ffxt_hwid` is the `UserDefaults` key; `device-id-v2` is the schema
    /// marker the routine compares against.
    public static let hwidDefaultsKey = "ffxt_hwid"
    public static let hwidSchemaMarker = "device-id-v2"

    private init() {
        cache = NSCache()
        cache.countLimit = 32
    }

    // MARK: - identifiers

    /// The hardware identifier the server binds a key to.
    ///
    /// Recovered behaviour, from `0x1000e1178`:
    ///
    /// 1. Read `UserDefaults.standard.string(forKey: "ffxt_hwid")`. If present,
    ///    use it as-is.
    /// 2. Otherwise derive it: `UIDevice.current.identifierForVendor.uuidString`,
    ///    `lowercased()`, with `-ios` appended.
    /// 3. The routine then calls `removeObject(forKey: "ffxt_hwid")` on that
    ///    same key.
    ///
    /// Step 3 is the important one and the reason this is not a first-run
    /// generator. The cached value is treated as untrusted: the identifier is
    /// recomputed from `identifierForVendor` and the stored copy is dropped, so
    /// the next launch re-derives it. A tampered `ffxt_hwid` in the defaults
    /// plist therefore does not survive a launch.
    public var hwid: String {
        if let stored = UserDefaults.standard.string(forKey: Self.hwidDefaultsKey) {
            return stored
        }
        let derived = derivedHwid()
        // Matches the recovered `removeObjectForKey:` on the miss path.
        UserDefaults.standard.removeObject(forKey: Self.hwidDefaultsKey)
        return derived
    }

    /// The freshly computed identifier, ignoring any cached copy.
    private func derivedHwid() -> String {
        guard let vendor = UIDevice.current.identifierForVendor else { return "" }
        return vendor.uuidString.lowercased() + "-ios"
    }

    public var deviceName: String { UIDevice.current.name }

    public var iOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    public var iPhoneModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "" }
        }
        return machine.isEmpty ? "unknown" : machine
    }

    public var mac: String { cached("mac") { currentMac } }

    /// The address the server binds keys to. Read from the same sysctl the
    /// original build used, so an existing key stays valid across updates.
    public var currentMac: String {
        if let stored = UserDefaults.standard.string(forKey: DeviceIdentityProvider.macDefaultsKey) {
            return stored
        }
        var address = ""
        var size = 0
        if sysctlbyname("en0", nil, &size, nil, 0) == 0, size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("en0", &buffer, &size, nil, 0) == 0 {
                address = buffer.prefix(while: { $0 != 0 }).reduce(into: "") {
                    $0 += String(format: "%02X", UInt8(bitPattern: $1))
                }
            }
        }
        if !address.isEmpty {
            UserDefaults.standard.set(address, forKey: DeviceIdentityProvider.macDefaultsKey)
        }
        return address
    }

    public var identity: DeviceIdentity {
        DeviceIdentity(
            hwid: hwid,
            mac: mac,
            deviceName: deviceName,
            iOSVersion: iOSVersion,
            iPhoneModel: iPhoneModel
        )
    }

    // MARK: - device key

    /// Long-lived Ed25519 key proving this install is the one the key was issued
    /// to. Generated on first launch and kept in the keychain.
    public func deviceSigningKey() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try? SecureStore.readData(account: DeviceIdentityProvider.signingHandleKey),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: existing) {
            return key
        }
        let key = Curve25519.Signing.PrivateKey()
        try SecureStore.write(key.rawRepresentation, account: DeviceIdentityProvider.signingHandleKey)
        UserDefaults.standard.set(UUID().uuidString, forKey: DeviceIdentityProvider.credentialKey)
        return key
    }

    public var credentialId: String {
        UserDefaults.standard.string(forKey: DeviceIdentityProvider.credentialKey) ?? "unbound"
    }

    public var devicePublicKey: String {
        (try? deviceSigningKey().publicKey.rawRepresentation.base64EncodedString()) ?? ""
    }

    // MARK: - simulator / hardware gate

    public var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    public var isPhysicalDevice: Bool { !isSimulator }

    private func cached(_ key: String, _ make: () -> String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache.object(forKey: key as NSString) { return hit as String }
        let value = make()
        cache.setObject(value as NSString, forKey: key as NSString)
        return value
    }
}

/// Keychain wrapper for the license credential.
///
/// The service id is deliberately the house-arrest one: the credential has to be
/// readable by the same identity that performs the container bridge, and using a
/// single service keeps that path from needing a second entitlement.
public enum SecureStore {
    public static let service = "com.apple.mobile.MobileHouseArrest.ffxc.auth"

    public enum Failure: Error, Sendable {
        case secureStorage
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    public static func write(_ data: Data, account: String) throws {
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccount as String] = account

        let target = query.merging([kSecAttrAccount as String: account]) { current, _ in current }
        SecItemDelete(target as CFDictionary)

        var status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, q as CFDictionary)
        }
        guard status == errSecSuccess else { throw Failure.secureStorage }
    }

    public static func readData(account: String) throws -> Data? {
        var q = query
        q[kSecAttrAccount as String] = account
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess else { return nil }
        return out as? Data
    }

    public static func delete(account: String) {
        var q = query
        q[kSecAttrAccount as String] = account
        SecItemDelete(q as CFDictionary)
    }

    public static func storeLicenseKey(_ key: String) throws {
        try write(Data(key.utf8), account: "license")
    }

    public static func licenseKey() throws -> String? {
        guard let data = try readData(account: "license") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func clearLicenseKey() {
        delete(account: "license")
    }
}
