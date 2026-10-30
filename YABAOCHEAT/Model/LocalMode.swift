import Foundation

/// Delivery policy for this build.
///
/// `enabled` is the temporary switch: the app runs without a licence key,
/// without the relay and without a trusted CA. Every route below is local to
/// the device. Flip it to `false` to bring the key gate and the relay flow
/// back; no other file has to change.
enum LocalMode {
    /// Read from `Info.plist` so the switch can be flipped without touching
    /// Swift. A missing key means local (the shipped default for this build).
    static let enabled: Bool = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "FFXCLocalMode") as? Bool {
            return value
        }
        return true
    }()
}
