import Foundation

/// The one inject matrix. Everything in the app that decides *how* the cheat
/// reaches the game goes through here.
///
/// - `.nativeHook` — iOS 17.0–18.7.1: the kernel chain wins, `task_for_pid`
///   answers, and a branch stub + trampoline are planted straight into the
///   game's address space. Nothing on disk, nothing in IFix's registry.
/// - `.hotfix` — every other iOS (18.8 through 27): the relay points the
///   game's own `CodePatchUrl` at its copy of the patch, so the game downloads
///   and applies it through its own loader — ESP *and* aim live, with no
///   second process ever writing into the container. The relay's
///   `native-assist` feature rides alongside: the game's own aim assist is
///   forced on as a no-patch second layer.
///
/// The container-staging route (the one that was detected) is not in this
/// table; it exists only as a legacy fallback.
public enum InjectRoute: String, Sendable {
    case nativeHook
    case hotfix

    public var displayName: String {
        switch self {
        case .nativeHook: return "Native hook (kernel)"
        case .hotfix: return "Hotfix channel — ESP + aim"
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
    /// `.nativeHook` needs the kernel chain to have won; `.nativeAssist` needs
    /// a relay host and one capture-pinned rule on the relay.
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
