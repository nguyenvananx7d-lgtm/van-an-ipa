import Foundation

/// The one inject matrix. Everything in the app that decides *how* the cheat
/// reaches the game goes through here.
///
/// - `.ghost` — the default on any install whose entitlements are honoured:
///   SpringBoard opens the game, the app takes its task port while it is still
///   inside `UIApplicationMain`, and a thread is pointed at `dlopen` so
///   `GhostPayload.dylib` is inside the process before IL2CPP has a domain.
///   Nothing is written into the game's container, nothing is registered in
///   IFix, no certificate is installed, and the payload resolves every symbol
///   by name instead of by dump offset.
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
    case ghost
    case nativeHook
    case hotfix

    public var displayName: String {
        switch self {
        case .ghost: return "Ghost — launch-time native map"
        case .nativeHook: return "Native hook (kernel)"
        case .hotfix: return "Hotfix channel — ESP + aim"
        }
    }
}

public struct InjectPlan: Sendable {
    /// The route this device takes. Ghost wins whenever its payload is in the
    /// bundle and the process can actually take a foreign task port; the
    /// kernel route is the fallback on 17.0–18.7.1, the relay on everything
    /// else.
    public static func route(for os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> InjectRoute {
        if GhostInjector.payloadAvailable() && GhostInjector.taskPortAllowed() {
            return .ghost
        }
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
    /// `.ghost` needs the payload in the bundle and a foreign task port;
    /// `.nativeHook` needs the kernel chain to have won; `.hotfix` needs a
    /// relay host and one capture-pinned rule on the relay.
    public static func readiness(for route: InjectRoute) -> String {
        switch route {
        case .ghost:
            guard GhostInjector.payloadAvailable() else {
                return "not ready — GhostPayload.dylib is missing from the bundle"
            }
            return GhostInjector.taskPortAllowed()
                ? "ready — launch-time map, no container, no IFix"
                : "not ready — task port denied (entitlements not honoured)"
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
