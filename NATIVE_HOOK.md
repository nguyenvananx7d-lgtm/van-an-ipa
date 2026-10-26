# Native hook route — research & design (NATIVE_HOOK)

Why the IFix route is detectable, what replaces it, and what the code in
`YABAOCHEAT/Injection/kexploit/taskport.{h,m}` + `NativeHookInstaller.swift`
implements. Everything below is grounded in the 1.132.1 dump and in the
primitives already in this repo — no guessed APIs.

## 1. What exposes the current route

The shipped patch is an InjectFix (IFix) patch. IFix itself is the signature:

| Surface | Evidence (dump) | Why it matters |
| --- | --- | --- |
| Patch registry is public | `IFix.ILFixDynamicMethodWrapper.wrapperArray` — `public static` array of every patch wrapper (dump 858330) | One read of one static field enumerates every patched method. No filesystem work needed; the AC sees the cheat the moment the VM loads it. |
| Per-id lookup is public | `IFix.WrappersManagerImpl.GetPatch(System.Int32)` — `public static` (dump 874775) | The AC can probe whether any game method id carries a patch, one call each. |
| Synthetic scene object | The patch creates `GameObject("uievent_relay")` + adds `SceneEditBoxSelectTool` (template Bootstrap) | A scene walk finds a component the game never creates, under a name the game never uses. |
| On-disk artifacts | `Assembly-CSharp-patch.bytes`, `localConfig.json` (with `SilentAim`/`AimHumanize` keys), `ffxc_debug.log` in the game's Data container | A "files the game never wrote" scan catches all of them; that is the reason for the anti-ban routine's whole existence. |
| Marker strings | `uievent_relay`, `FFXC-MACHO-PREFIX-v2`, menu labels in the blob | String scans. |

The decisive one is the registry: **any** IFix patch is enumerable, so no amount
of delivery stealth (container vs baked-in IPA vs relay-served) removes the
signature — the VM itself is the billboard. The new route must not use IFix at
all.

## 2. The new route: task-port + native hook

The repo already owns the two hard prerequisites:

- **Kernel R/W** (`kexploit_opa334`, verified iOS 17.0–18.7.1) with a
  **sandbox escape** that patches the process label (`off_label_l_perpolicy_amfi`,
  `off_label_l_perpolicy_sandbox` in offsets.h). A label-patched process is what
  makes `task_for_pid()` answer.
- **The exc-guard kill switch**: `disable_excguard_kill(task)` (kutils.h). iOS
  kills a process whose task port gets manipulated; this turns that off. Its
  presence in the chain is the author's own signal that task-port work was the
  intended next step.

The injection then uses **Mach VM APIs, nothing else**:

1. Exploit chain runs (existing). Game is launched normally.
2. `task_for_pid(mach_task_self(), game_pid)` → the game's task port.
3. `task_info(TASK_DYLD_INFO)` → `dyld_all_image_infos` inside the game;
   walk `infoArray` with `mach_vm_read` → main image load address → slide.
4. Target VA = slide + RVA from the dump. Stage-1 target table:
   - `COW.GamePlay.Player.IsReallyInStealth` — RVA `0x573eff8`
   - `COW.GamePlay.CameraControllerBase.LateUpdate` — RVA `0x58dd374`
5. `mach_vm_allocate` + `mach_vm_write` a page in the game carrying a
   **position-independent ARM64 trampoline** + a parameter block; mark it
   `VM_PROT_READ|VM_PROT_EXECUTE`.
6. `mach_vm_protect` the target's `__TEXT` page RW, write a 16-byte branch stub
   (`ldr x16, #8; br x16; .quad trampoline`), restore R-X. The original 16
   bytes are kept in the parameter block so the trampoline can re-run them and
   jump back — the hook is invisible in the control flow.
7. Nothing is written to disk, no new file exists in the game's sandbox, no
   GameObject is created, IFix is never touched, and the patch registry stays
   empty because there is no patch.

**Why code-page writes should survive**: IFix itself rewrites method entry
points at runtime (that is its mechanism), so the game cannot hash `__TEXT`
without false-positiving on its own legitimate hotfixes. A data-only
alternative exists too (patch `MethodInfo->methodPointer` in
`global-metadata.dat`, no code write at all) and is noted as fallback if
`mach_vm_protect` on `__TEXT` is refused.

## 3. Stage plan

**Stage 1 (this commit):** prove the channel. The trampoline writes a marker
word into its parameter block and re-enters the original function. The
installer reads the marker back with `mach_vm_read`: 1 → armed, 0 → the hook
fired inside the game. Full ESP/aim is *not* reimplemented yet — the point is
to validate task-port + slide + stub on a device before porting 3000 lines of
logic into native C.

**Stage 2:** native-C port of the ESP/aim core. The C blob resolves
`il2cpp_*` exports through the game's own symbol table (base + offset, computed
at install time from the on-disk binary, which the sandbox escape lets us
read), renders via `Camera` hooks (e.g. `CameraControllerBase.LateUpdate` for
aim, the render pipeline for ESP), and reads its settings from the parameter
block — which the app refreshes through `mach_vm_write`, no files, no IFix,
no synthetic objects.

**Stage 3:** behavioural envelope (already designed in `Logic.Aim.cs`:
engagement length, turn-rate cap, `SetAimRotation` rate) ported to the C core.

## 4. Device pass 1 checklist

Order matters; each line gates the next:

1. Exploit chain → `kernelRWReady` (already shipped, already used for the ctime
   forge).
2. `task_for_pid(game)` returns a port. If `KERN_FAILURE`, the label patch
   needs the platform/amfi slot set too — one kernel write.
3. `TASK_DYLD_INFO` read works; slide matches `base - 0x100000000`.
4. Marker flips 1 → 0 after hooking `IsReallyInStealth` (it runs constantly).
5. `disable_excguard_kill` before any write — without it the game dies the
   moment the task port is touched.

## 5. Ceiling and fallbacks

- The kernel chain (`kexploit_opa334`) is verified **iOS 17.0–18.7.1 only**
  (`KernelExploit.kernelStageSupported`). On 18.8+ the chain cannot win, so the
  task-port route does not exist there — the UI gates the button on the same
  check, and the log says so instead of failing silently.
- On unsupported iOS the only remaining channels are the relay-served IFix
  route (section "cách tiêm cũ", still registry-visible) and pure behaviour —
  until the exploit table grows a post-18.7 primitive, there is no file-free
  route on those versions.

## 6. What still looks like a cheat

Nothing in this document hides *behaviour*. The aim envelope, the ESP visuals
and the killguard design in `Logic.Aim.cs` remain the actual anti-ban layer;
the route only removes the forensic billboard.
