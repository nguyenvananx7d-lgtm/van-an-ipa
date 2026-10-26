import Foundation

/// The one inject matrix. Everything in the app that decides *how* the cheat
/// reaches the game goes through here.
///
/// - `.nativeHook` — iOS 17.0–18.7.1: the kernel chain wins, `task_for_pid`
///   answers, and a branch stub + trampoline are planted straight into the
///   game's address space. Nothing on disk, nothing in IFix's registry.
/// - `.hotfix` — every other iOS (18.8 through 27): the relay rewrites
///   `GameVarDef.CodePatchUrl` and the game downloads and applies the patch
///   through its own `LoadIFix`. A MITM does not care about iOS versions.
///
/// The container-staging route is deliberately not a row in this table: it is
/// the route that was detected, and it exists only as a legacy fallback behind
/// `FeatureControls.preferModernInjection`.
public enum InjectRoute: String, Sendable {
    case nativeHook
    case hotfix

    public var displayName: String {
        switch self {
        case .nativeHook: return "Native hook (kernel)"
        case .hotfix: return "Hotfix channel (relay)"
        }
    }
}

public struct InjectPlan: Sendable {
    /// The route this device takes, from the OS version alone.
    public static func route(for os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> InjectRoute {
        if os.majorVersion == 17 {
            return .nativeHook
        }
        if os.majorVersion == 18 {
            return os.minorVersion <= 7 ? .nativeHook : .hotfix
        }
        return .hotfix
    }

    /// One line for the log screen: what was picked and why.
    public static func decision(for os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> String {
        "inject route: \(route(for: os).displayName) (iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion))"
    }

    /// Whether the picked route is usable right now, without device passes.
    /// `.nativeHook` needs the kernel chain to have won; `.hotfix` needs a
    /// relay host and a codepatch-armed relay.
    public static func readiness(for route: InjectRoute) -> String {
        switch route {
        case .nativeHook:
            return KernelExploit.kernelRWReady
                ? "ready — kernel r/w established"
                : "not ready — run the exploit stage first"
        case .hotfix:
            let host = (UserDefaults.standard.string(forKey: "relay.host") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return host.isEmpty
                ? "not ready — set the relay host in Settings"
                : "relay \(host) configured — press Check in Settings"
        }
    }
}
