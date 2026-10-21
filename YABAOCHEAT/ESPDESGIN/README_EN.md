# Free Fire IFix Patch Project (C#)

This standalone project generates `Assembly-CSharp-patch.bytes` from a new C# dump. The pipeline automatically:

1. selects the newest dump in `dumps/`;
2. discovers obfuscated class, method, and field names;
3. generates `generated/ESPLogic.cs` and a binding table;
4. retargets the baseline dummy assembly with Mono.Cecil;
5. compiles the IFix patch;
6. parses and verifies references, CFG, and VM stack behavior before writing artifacts to `dist/`.

## Current status

<!-- AUTO_STATUS_START -->
- Active dump: `unknown_package_name_1.132.1.cs`
- Detected version: `1.132.1`
- Dump SHA-256: `483EBC2C6A245A5EE32844D996F16E5B614C1105EE363EE575ABE01652CCFEC2`
- Match binding: `COW.GamePlay.JMAGGLCNGIG.ILPNGCMEFFI()`
- Aiming-info binding: `COW.GamePlay.CGKJLKPMGDJ`
- Generated source: `generated/ESPLogic.cs`
<!-- AUTO_STATUS_END -->

## Features

- ESP box, tracer, health bar, player name, and distance.
- Local-player, teammate, dead/knocked, visibility, and range filters.
- Draggable ESP control menu UI (toggle with 3-finger 5-tap gesture).
- 100% removed all network, movement, and weapon modifications: No Fake lag (fire), Fast reload, Silent aim, Aim system, No recoil, Fast parachute, or Speed running. The patch strictly contains only 2 safe redirects: Bootstrap and OnGUI.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7.
- Python 3.10 available through `py -3.10`.
- The .NET Framework C# compiler at:
  `C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe`.

Mono.Cecil, the required InjectFix sources, dummy DLLs, and the neutral IFix seed are included in the project.

## Quick build

Run this from `project-freefire_c#`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

This selects the most recently modified `.cs` file in `dumps/`, refreshes bindings and generated source, and builds the patch.

Artifacts:

```text
dist/Assembly-CSharp-patch.bytes
dist/Assembly-CSharp-patch.report.json
dist/Assembly-CSharp-patch.verify.json
dist/Assembly-CSharp-patch.manifest.json
```

## Updating after a game release

### Standard workflow

1. Put the new dump in `dumps/`, for example:

   ```text
   dumps/unknown_package_name_1.133.1.cs
   ```

2. Run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\update.ps1
   ```

3. Confirm that the final log contains `BUILT`, the detected version, SHA-256, redirect count, and instruction count.

4. Use the new `dist/Assembly-CSharp-patch.bytes` file.

### Selecting a specific dump

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\update.ps1 `
  -DumpPath .\dumps\unknown_package_name_1.133.1.cs
```

`DumpPath` accepts relative and absolute paths.

### Rebuilding without rediscovering bindings

After `generated/` has been refreshed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -NoUpdate
```

Keep compiler artifacts for debugging:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 `
  -KeepBuildArtifacts
```

## Automatic binding discovery

`tools/update_from_dump.py` does not depend on the obfuscated names from the current version. It uses stable method anchors and structural evidence:

- the return type of `COW.GameFacade.CurrentMatch()` identifies the match container;
- the `Dictionary<Player> -> List<Player> -> HashSet<Player>` sequence identifies the player-list method;
- the return type of `Player.get_LastAimingInfoFromWeapon()` identifies the aiming-info class;
- the aiming-info field layout identifies its object, collider, vectors, hit enum, flags, and short field;
- enum values `Default=0`, `Head=1`, and `Body=2` validate the hit type;
- two adjacent aiming-info fields before `LastAimingInfoFromWeaponAdjusted` identify the active backing field in `Player`;
- the initial `Boolean, Vector2, Vector2` field sequence in `SceneEditBoxSelectTool` identifies menu state;
- the first parameter of `SetSpecialRunSpeedScaleByKeyAndValue`, plus `BuffSystem=500`, identifies the speed enum;
- the 181-entry `IFix.Core.Code` table determines the target opcode order.

If a layout becomes ambiguous or a stable anchor changes, the updater stops with a specific error instead of selecting an uncertain candidate.

Generated results:

```text
generated/bindings.tsv
generated/bindings.json
generated/ESPLogic.cs
```

Do not edit `generated/ESPLogic.cs` directly because the next update overwrites it. Edit shared behavior in `src/ESPLogic.template.cs`.

## Menu UI

- The menu starts hidden.
- Perform five consecutive three-finger taps to open it.
- A gap longer than three seconds resets the tap sequence.
- Drag the header to move the panel; its position remains clamped to the screen.
- Use the `X` button to hide it.

`ESP` tab:

- Enable ESP
- Player box
- Top tracer
- Health bar
- Player name
- Distance

`AIM` tab:

- Silent aim
- Aim system
- Context-sensitive silent target, headshot rate, and FOV controls
- Context-sensitive native `HEAD/NECK` target control
- No recoil

`SETTINGS` tab:

- Fast parachute
- Running speed x3
- Reset defaults
- Hide menu

## Manual verification

```powershell
py -3.10 .\tools\parse_ifix_patch.py `
  .\dist\Assembly-CSharp-patch.bytes `
  -o .\dist\Assembly-CSharp-patch.report.json

py -3.10 .\tools\verify_ifix_patch.py `
  .\dist\Assembly-CSharp-patch.bytes `
  --dump .\dumps\unknown_package_name_1.132.1.cs `
  --json .\dist\Assembly-CSharp-patch.verify.json
```

A valid result must contain:

- `valid: true`;
- `errors: []`;
- `warnings: []`;
- exactly 6 redirects;
- no `Fast reload x3` or `Fake lag (fire)` strings;
- a manifest hash matching the patch file.

Run the regression suite with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test.ps1
```

## Project layout

```text
project-freefire_c#/
|-- build.ps1                   # update, compile, verify, and install to dist
|-- update.ps1                  # entry point for a newly added dump
|-- test.ps1                    # regression suite
|-- dumps/                      # game dumps
|-- src/
|   |-- ESPLogic.template.cs    # shared logic/menu with binding placeholders
|   `-- WeaveEsp.cs             # Cecil retargeting and method-body weaving
|-- tools/
|   |-- update_from_dump.py     # binding discovery and source generation
|   |-- prepare_compiler.py     # target opcode/magic compiler source
|   |-- parse_ifix_patch.py     # IFix container parser
|   |-- verify_ifix_patch.py    # reference/CFG/stack verifier
|   `-- test_project.py         # project regression tests
|-- baseline/
|   |-- DummyDll/               # baseline reference assemblies
|   `-- Assembly-CSharp-patch-neutral.bytes
|-- vendor/InjectFix/           # minimum required compiler sources
|-- generated/                  # automatically generated files
|-- build/                      # temporary compiler files
`-- dist/                       # runtime artifacts
```

## Limits of dump-only updates

A C# dump provides names, signatures, field layouts, and opcode values, but it does not contain the complete original binary MVID or assembly identity. The pipeline retains the assembly identity from the baseline dummy and the IFix magic/dialect from the neutral seed while verifying every serialized patch reference against the new dump.

When an update only changes obfuscation and compatible layouts, adding the new dump is sufficient. If the game changes the IFix container magic/dialect or assembly identity, update the matching baseline inputs before building again.

## Troubleshooting

`List<Player> method is ambiguous`:

- The match container structure changed.
- Inspect the reported candidates and update the matching rule in `update_from_dump.py`.

`expected one aiming-info field layout`:

- The aiming-info class added, removed, or reordered fields.
- Inspect `get_LastAimingInfoFromWeapon` and update the layout detector.

`DUMP_METHOD_UNRESOLVED`, `DUMP_TYPE_MISSING`, or `DUMP_FIELD_MISSING`:

- The generated source or bindings do not match the selected dump.
- Rerun `update.ps1 -DumpPath <dump>` and do not reuse stale files from `generated/`.

Opcode table errors:

- The dump is missing `IFix.Core.Code`, or the enum no longer has 181 contiguous values.
- Use a complete dump from the matching game build.
