# van-an-ipa — Nimbus IPA

SwiftUI iOS app (`YABAOCHEAT`) built from `project.yml` with XcodeGen and packaged as an unsigned IPA by GitHub Actions. No Mac needed locally: push, wait for the runner, download the artifact.

## The cheat reaches the game one of two ways — never through the container

The legacy route (writing an IFix patch + `localConfig.json` into the game's
Data container from a second process) was detected and is retired from the
default flow. It survives only behind **Settings → Modern injection = off**.

| Route | iOS | Mechanism | Artifacts |
| --- | --- | --- | --- |
| **Native hook** | 17.0–18.7.1 | Kernel chain wins → label patch → `task_for_pid(game)` → dyld image walk → 16-byte branch stub over `Player.IsReallyInStealth` + PIC trampoline on a fresh R+W+X page | none on disk; 16 bytes in RAM |
| **Hotfix channel** | all (18.8–27 included) | The relay rewrites `GameVarDef.CodePatchUrl` in the var-table response; the game downloads and applies the patch through its own `LoadIFix` | the game's own files, written by the game |

The route is chosen by `InjectPlan` from the OS version alone; the inject
button logs which one it picked and why.

## Toolchain

| Piece | Version |
| --- | --- |
| Xcode | latest stable on `macos-latest` |
| XcodeGen | `brew install xcodegen` |
| iOS deployment target | 16.0 |
| Swift | 5.9 |

## Build (local, macOS)

```bash
brew install xcodegen
xcodegen generate --spec project.yml --project .
xcodebuild -project VortexArena.xcodeproj -scheme YABAOCHEAT \
  -configuration Release -sdk iphoneos \
  -archivePath build/VortexArena.xcarchive archive \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Build (CI, no Mac)

1. Push to `main`, open a PR, or run **Actions → Build VortexArena IPA → Run workflow**.
2. Wait for the green check (~4–6 min).
3. Open the run, scroll to **Artifacts**, download `VortexArena-unsigned`.

## Install

Unsigned IPA carrying private entitlements. TrollStore opens it directly;
ESign / Feather / SideStore / Sideloadly import it and must keep the embedded
entitlements. A plain free-developer sideload strips them and the kernel stage
reports unavailable.

## Layout

```
project.yml                       XcodeGen spec (single source of truth)
YABAOCHEAT/
  App/                            entry point, root view, environment
  UI/                             panel (inject, aimbot, visual, misc, settings, log)
  Store/                          observable state (auth, inject, menu, language)
  Model/                          feature controls, game, license
  Injection/
    InjectPlan.swift              the one inject matrix (route by iOS)
    NativeHookInstaller.swift     stage-1 native hook, marker-verified
    TrafficHotfixInstaller.swift  relay readiness for the hotfix channel
    kexploit/                     kernel R/W chain (17.0–18.7.1), sandbox escape
    taskport.{h,m}                task-port + trampoline assembly primitives
    MCM/                          container-manager bridge (legacy fallback only)
    AntiBanRoutine.swift          legacy container sweep (legacy fallback only)
  Licensing/                      protocol constants, client, verifier, device id
  Network/                        DoH profile, loopback server, tunnel probe
  Resources/                      patch blob, localConfig.json, strings, icons
    panel/                        web control panel (HTML/CSS/JS) + bridge host
ESPDESGIN/                        patch build tooling — not part of the IPA
ffxc-auth/                        licence server + MITM relay — not part of the IPA
NATIVE_HOOK.md                    the injection research: why IFix is enumerable, the new routes
```

## Usage

1. Settings → run the exploit stage (iOS 17.0–18.7.1) — the native hook row
   lights up when the kernel chain has won.
2. Settings → relay host → **Check** — the hotfix row reports whether the
   relay is reachable, capturing, or codepatch-armed.
3. Hit **Inject**. The log names the route and every stage it reached.
4. In the game: ESP on by default; aim is off by default — turn it on in the
   Aimbot tab, start from the **Balanced** stealth tier.

The hotfix channel needs one capture session to pin its three relay env vars
(`RELAY_PATCH_HOST`, `RELAY_VARCONFIG_PATH`, `RELAY_PATCH_FILE`) — see
[NATIVE_HOOK.md](NATIVE_HOOK.md) §4–5.

## Notes

- `ESPDESGIN/` and `ffxc-auth/` are not referenced by `project.yml` and are not bundled.
- The IFix registry (`ILFixDynamicMethodWrapper.wrapperArray`) is public static:
  any IFix patch is enumerable regardless of delivery. That is why the native
  hook route exists, and why it is the primary on the iOS range it supports.
