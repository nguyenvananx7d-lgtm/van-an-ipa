# van-an-ipa — Vortex Arena IPA

SwiftUI iOS app (`YABAOCHEAT`) built from `project.yml` with XcodeGen and packaged as an unsigned IPA by GitHub Actions. No Mac needed locally: push, wait for the runner, download the artifact.

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
4. Unzip → `VortexArena-unsigned.ipa`.

Every push to `main` builds automatically. The workflow also rejects source trees that still contain merge-conflict markers, so a broken merge fails fast instead of producing a half-built app.

## Install

The IPA is unsigned and carries the entitlements the app needs (`no-sandbox`, `container-manager`, SpringBoard/FrontBoard launch, `get-task-allow`). Install it with a signer that honours entitlements:

- **TrollStore** — open the `.ipa` directly on device.
- **ESign / Feather / SideStore / Sideloadly** — import the IPA, keep the embedded entitlements.

A plain free-developer sideload will strip the private entitlements; the app will install and launch but container access and the kernel stage will report unavailable.

## Layout

```
project.yml                       XcodeGen spec (single source of truth)
YABAOCHEAT.entitlements           private entitlements, embedded at sign time
.github/workflows/build.yml       CI: generate → archive → sign → IPA
YABAOCHEAT/
  App/                            entry point, root view, environment
  UI/                             panel (inject, aimbot, visual, misc, settings, log)
  Store/                          observable state (auth, inject, menu, language)
  Model/                          feature controls, game, license, recovered vocab
  Injection/                      installer, launcher, probe, wipe, anti-ban
    kexploit/                     kernel R/W chain (opa334 port)
    MCM/                          container-manager bridge
  Licensing/                      protocol constants, client, verifier, device id
  Resources/                      patch blob, localConfig.json, strings, icons
ESPDESGIN/                        separate InjectFix tooling — not part of the IPA
ffxc-auth/                        separate licence server — not part of the IPA
```

## Notes

- `YABAOCHEAT/Resources/Assembly-CSharp-patch.bytes` is the payload staged into the game container. Its length and SHA-256 are pinned in `PatchPayload.swift`; change the blob and update both constants or injection refuses with `integrityMismatch`.
- `ESPDESGIN/` and `ffxc-auth/` are not referenced by `project.yml` and are not bundled.
- Bundle id `com.apple.mobile.MobileHouseArrest` and display name `Vortex Arena` live in `YABAOCHEAT/Info.plist` and `project.yml`.
