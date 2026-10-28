# Ghost — the route after the container patch

This document is the analysis of what the current delivery does wrong, and the
design of the route that replaces it. It is written against the code in this
repo, not against a guess: every claim below points at a file, a dump line, or a
field the game ships.

---

## 1. What the developer actually sees

The three shipped routes leak in three different places. They are independent,
so closing one does not close the others.

### 1.1 The container route — dead

`RuntimeInstaller.install` writes two files into the game's Data container:
`Assembly-CSharp-patch.bytes` and `localConfig.json`
(`YABAOCHEAT/Injection/RuntimeInstaller.swift`, `ContainerBridge.patchURLs`).
Both are files the game never wrote. `AntiBanRoutine` exists only to backdate,
re-stamp and hide them — which is an admission that the primitive is visible.

Even with perfect file hygiene the route dies one layer deeper: the patch is an
InjectFix patch, and IFix publishes its own registry as a **public static
array** (`IFix.ILFixDynamicMethodWrapper.wrapperArray`, dump line 858330). One
read of one field enumerates every patched method. The anti-cheat does not need
to look at the filesystem at all.

### 1.2 The relay route — still IFix, still enumerable

`TrafficHotfixInstaller` + the relay rewrite `GameVarDef.CodePatchUrl`, so the
game downloads the patch itself through its own `LoadIFix`. No foreign file, no
second process writing into the container — but the patch still lands in
`wrapperArray`, and `WrappersManagerImpl.GetPatch(int)` is public static too
(dump line 874775). The delivery is clean; the payload is not.

### 1.3 The proxy / CA route — correct, and crowded

`ffxc-auth/src/proxy/*` terminates TLS with a per-host leaf signed by a CA the
device is told to trust. This removes the client patch entirely: it edits the
report instead of the program. It is the best route in the repo today, and it
has three properties that will get it killed:

1. **It requires a trusted root.** `PROXY.md` §"Limits" already says it: a
   pinned host defeats it outright, and the relay reports it as an upstream
   error. One pinned security host is enough to break the whole channel.
2. **It is measurable from inside the app.** A device with an extra trusted
   anchor is a fingerprint. So is a `utun`/`ppp` interface the game did not
   create, and so is a profile named `Vortex Arena`.
3. **It is the route everyone is using.** Every MIZZE-style build ships the
   same Super Proxy + `ca.cer` instructions. When a detection ships, it ships
   against all of them at once.

### 1.4 The kernel hook — right idea, wrong dependency

`NativeHookInstaller` is the only route that leaves nothing on disk and nothing
in IFix. But it depends on three fragile things:

- `kexploit_opa334` — verified **iOS 17.0–18.7.1 only**
  (`KernelExploit.kernelStageSupported`).
- `task_for_pid` on a *running*, already-initialised process — which is exactly
  the event `disable_excguard_kill` exists to survive. Needing that call is the
  tell.
- A write into `__TEXT` to plant the stub. The design argues it survives
  because IFix also rewrites entry points — true, but it means the route is
  only safe *while IFix is also in use*, which is a contradiction.

---

## 2. The property the next route must have

Write it as a single sentence and check every design against it:

> **Nothing is written into the game's container, nothing is registered in a
> process-wide table the game can enumerate, no certificate is installed, and
> the game is never joined after it has started.**

The last clause is the one nobody in this space does. Every injector attaches
to a live process. Attaching is an event: a task port appears, `excguard` fires,
and the anti-cheat has had its first frame by then.

---

## 3. Ghost

```
            launch                     attach (t ≈ 0 ms)              first frame
 SpringBoard ─────▶ Free Fire ────────────────┬──────────────────────────▶
                                             │
                              task_for_pid, task_suspend,
                              dlopen(GhostPayload.dylib),
                              task_resume, detach
                                             │
        ┌────────────────────────────────────┴───────────────────────┐
        │  GhostPayload.dylib — inside the game, from before frame 0  │
        │    • inline hooks on Player.LateUpdate / OnGUI              │
        │    • resolves every symbol by name through il2cpp_*         │
        │    • settings arrive over 127.0.0.1, never from a file      │
        └────────────────────────────────────────────────────────────┘
```

Four things make it different from every route already in this repo:

| Property | How |
| --- | --- |
| No kernel exploit | `task_for_pid` answers because the app already carries `platform-application` + `get-task-allow` (`YABAOCHEAT.entitlements`). No kexploit, no `disable_excguard_kill`, works on every iOS the entitlement is honoured on. |
| No hot attach | The pid is polled the moment SpringBoard forks it and the task is suspended before IL2CPP initialises. The payload's constructor runs before the game's first managed call. |
| No file in the game | The dylib lives in **our** bundle. The game's Data container is never opened. |
| No IFix, no proxy, no CA | The payload hooks two methods natively. There is no `wrapperArray` entry to find, no root certificate to trust, no proxy interface to fingerprint. |
| No fixed offsets | Classes and methods are resolved with `il2cpp_class_from_name` / `il2cpp_class_get_method_from_name`. A game update that keeps the C# names keeps the route working — the failure mode of `ESPDESGIN` (re-dump, re-bind, rebuild) disappears. |

### 3.1 Why the hooks are inline and not `methodPointer` swaps

`MethodInfo->methodPointer` is the obvious data-only patch, and it is what
`NATIVE_HOOK.md` §2 proposes as a fallback. It does not work after first call:
IL2CPP's generated code caches the resolved pointer in a per-method static the
first time `il2cpp_codegen_initialize_method` runs, and later calls go through
that cache. `Player.LateUpdate` and `OnGUI` have both been called long before a
patch could land.

So the payload installs a 16-byte ARM64 branch stub
(`ldr x16, #8; br x16; .quad replacement`) with a trampoline that replays the
saved prologue and jumps back. That is the same stub shape as
`taskport_build_trampoline`, minus the task port: we are already inside the
process, so `mprotect` on our own `__TEXT` is a local call.

The `methodPointer` swap is still used as a **fallback** for methods that have
not been called yet, and as the mechanism for methods whose first 16 bytes
contain a PC-relative instruction (the trampoline cannot relocate those).

### 3.2 Settings without a file

The old route's whole config story is `localConfig.json` — a file, in the
container, named after the cheat. Ghost opens a TCP socket to `127.0.0.1` and
reads a packed struct. The app is the server; the payload is the client.

```
struct ghost_settings_t {
    uint32_t magic;      // 'GHST'
    uint16_t version;    // 4
    uint32_t flags;      // same bit positions as the managed mask
    float    esp_max_distance, esp_box_scale, esp_text_scale, esp_fill_alpha;
    float    aim_fov, aim_smooth, aim_max_distance;
    float    aim_hit_chance, aim_reaction, aim_max_turn;
    uint8_t  palette, box_style, aim_bone, reserved;
    uint32_t seq;        // payload applies only when this changes
    uint32_t crc;        // CRC-32 of everything above
};
```

Live changes are a single 62-byte write on a loopback socket. Nothing is
created in the game's sandbox, so there is nothing to sweep, backdate or hide.

The channel also carries one image frame (`'GHIM'`: width, height, size, then
RGBA8 bytes) — the floating-icon logo, decoded in the app and rebuilt inside
the game as a `Texture2D`, because the game's sandbox cannot read the app
bundle. The icon opens an in-game toggle panel (one row per feature flag) that
flips the live settings in place; the next app push replaces them wholesale.

### 3.3 What Ghost does *not* do

It does not rewrite the report, block a host, or sit between the game and its
backend. Those remain the relay's job (`ffxc-auth`), and the two layers are
independent: Ghost removes the client-side evidence, the relay removes the
server-side evidence. Running only one of them is a choice, not a requirement.

---

## 4. Build and wiring

`GhostPayload` is a second target in `project.yml` (`library.dynamic`). It is
built unsigned and copied into the app bundle by a post-build script, so the
same CI that produces `VortexArena-unsigned.ipa` produces it.

`InjectPlan` gains a third case:

| Route | When it is chosen | Needs |
| --- | --- | --- |
| `.ghost` | entitlements present and the payload is in the bundle | TrollStore install |
| `.nativeHook` | kernel chain won | iOS 17.0–18.7.1 |
| `.hotfix` | everything else | relay host |

The legacy container route stays behind `Settings → Modern injection = off`,
exactly as before.

---

## 5. Device pass

Order matters, each line gates the next:

1. `ghost_probe()` reports `entitled=1` — `task_for_pid` on a process we do not
   own must return `KERN_SUCCESS` for a throwaway pid.
2. `SBSLaunchApplicationWithIdentifier` returns 0 and the pid appears within
   1.5 s.
3. `task_suspend` succeeds before `TASK_DYLD_INFO` reports more than a handful
   of images — that is the proof the attach beat IL2CPP.
4. `GhostPayload.dylib` appears in the child's image list after the hijack.
5. The log line `ghost: il2cpp ready` appears — the payload resolved
   `il2cpp_domain_get` and found `COW.GamePlay.Player`.
6. The first ESP box draws, then the aim tick logs one solve per frame.

If step 1 fails the install is not entitled (a plain free-developer sideload
strips the entitlements) and the app must fall back to `.hotfix`.
