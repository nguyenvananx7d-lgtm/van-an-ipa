# YABAOCHEAT — kernel exploit runner

iOS app that runs the ported 3105 kernel chain and nothing else:

| Stage | File | Scope |
| --- | --- | --- |
| 1 | `kexploit_opa334` | kernel read/write, iOS 17.0–18.7.1 and 26.0.x |
| 2 | `sandbox_escape` | ucred/ext_set walk, required on iOS 26+ |

`KernelExploit.run()` is the only entry point. The UI is a run button and the
live log. The chain's own `printf` output is captured as `CHAIN` alongside the
Swift `KRW`/`SANDBOX` stage lines, and every line is appended to
`Documents/kexploit.log` immediately, so a panic keeps the tail of the log.

## Layout

```
project.yml                       XcodeGen spec
YABAOCHEAT/
  App/YABAOCHEATApp.swift         entry point
  UI/ExploitView.swift            run button + stage log
  Injection/
    KernelExploit.swift           chain runner (background thread)
    kexploit/                     kernel r/w, sandbox escape, offsets, taskport
    AppLog.swift                  ring buffer + on-disk log
    StdioCapture.swift            captures the chain's printf into the log
    SupportPolicy.swift           iOS support table
YABAOCHEAT.entitlements           private entitlements (task_for_pid, IOKit, no-sandbox)
.github/workflows/build.yml       unsigned IPA build
```

## Build

Local (macOS):

```bash
brew install xcodegen
xcodegen generate --spec project.yml --project .
xcodebuild -project VortexArena.xcodeproj -scheme YABAOCHEAT \
  -configuration Release -sdk iphoneos \
  -archivePath build/VortexArena.xcarchive archive \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

CI: push to `main` or run **Actions → Build YABAOCHEAT**; download the
`YABAOCHEAT-unsigned` artifact.

## Install

Unsigned IPA with private entitlements. TrollStore opens it directly; other
installers must preserve the embedded entitlements or the kernel stage reports
unsupported. Signed installs strip them.

## Run

Open the app on a physical device, tap **RUN EXPLOIT**. The chain takes 10–30 s
off the main thread and the device may freeze briefly. It returns an error code
instead of killing the app when it fails.

Read the log in order:

- `policy:` — version, SoC family, whether the build is on the support table.
- `[CHAIN]` — `offsets_init` gate and the race progress from the C code.
- `kexploit_opa334 returned N` — `0` means kernel R/W is up; anything else
  names the failure stage.
- `sanity:` — a real `kread64` through the primitives after stage 1.
- `sandbox_escape returned N` — stage 2 result and the outside-sandbox probe.
