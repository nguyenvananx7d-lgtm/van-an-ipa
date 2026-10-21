# Free Fire IFix patch project (C#)

Project độc lập để sinh `Assembly-CSharp-patch.bytes` từ dump C# mới. Pipeline tự:

1. chọn dump mới nhất trong `dumps/`;
2. dò các tên class/method/field bị obfuscate;
3. sinh `generated/ESPLogic.cs` và bảng binding;
4. retarget dummy assembly bằng Mono.Cecil;
5. biên dịch IFix patch;
6. parse, verify CFG/stack, kiểm tra symbol và xuất artifact vào `dist/`.

## Trạng thái hiện tại

<!-- AUTO_STATUS_START -->
- Active dump: `unknown_package_name_1.132.1.cs`
- Detected version: `1.132.1`
- Dump SHA-256: `483EBC2C6A245A5EE32844D996F16E5B614C1105EE363EE575ABE01652CCFEC2`
- Match binding: `COW.GamePlay.JMAGGLCNGIG.ILPNGCMEFFI()`
- Aiming-info binding: `COW.GamePlay.CGKJLKPMGDJ`
- Generated source: `generated/ESPLogic.cs`
<!-- AUTO_STATUS_END -->

## Chức năng

- ESP box, tracer, health bar, tên và khoảng cách.
- Lọc local player, đồng đội, chết/knock, visibility và khoảng cách.
- Giao diện menu ESP kéo thả trực quan (bật/tắt bằng 3 ngón tay gõ 5 lần).
- Đã loại bỏ hoàn toàn 100% logic can thiệp mạng/chuyển động/vũ khí: không còn Fake lag (fire), Fast reload, Silent aim, Aim system, No recoil, Fast parachute, Speed running. Patch chỉ gồm 2 redirect an toàn: Bootstrap và OnGUI.

## Yêu cầu

- Windows PowerShell 5.1 hoặc PowerShell 7.
- Python 3.10 có thể gọi bằng `py -3.10`.
- .NET Framework C# compiler tại:
  `C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe`.

Dependency Mono.Cecil, InjectFix source, dummy DLL và neutral IFix seed đã nằm trong project.

## Build nhanh

Từ thư mục `project-freefire_c#`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

Lệnh trên tự chọn file `.cs` mới nhất theo thời gian sửa trong `dumps/`, cập nhật binding/source rồi build.

Artifact:

```text
dist/Assembly-CSharp-patch.bytes
dist/Assembly-CSharp-patch.report.json
dist/Assembly-CSharp-patch.verify.json
dist/Assembly-CSharp-patch.manifest.json
```

## Khi game update

### Cách đơn giản

1. Chép dump mới vào `dumps/`, ví dụ:

   ```text
   dumps/unknown_package_name_1.133.1.cs
   ```

2. Chạy:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\update.ps1
   ```

3. Kiểm tra cuối log phải có `BUILT`, version, SHA-256, redirect count và instruction count.

4. Dùng file mới tại `dist/Assembly-CSharp-patch.bytes`.

### Chỉ định dump cụ thể

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\update.ps1 `
  -DumpPath .\dumps\unknown_package_name_1.133.1.cs
```

`DumpPath` có thể là relative path hoặc absolute path.

### Build lại không dò binding

Sau khi `generated/` đã đúng:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -NoUpdate
```

Giữ compiler artifact để debug:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 `
  -KeepBuildArtifacts
```

## Tool tự dò những gì

`tools/update_from_dump.py` không dựa vào tên obfuscate của version hiện tại. Nó dùng các anchor có tên ổn định và layout:

- return type của `COW.GameFacade.CurrentMatch()` để tìm match container;
- chuỗi `Dictionary<Player> -> List<Player> -> HashSet<Player>` để tìm method lấy danh sách player;
- return type của `Player.get_LastAimingInfoFromWeapon()` để tìm aiming-info class;
- layout field aiming-info (`GameObject`, `Collider`, các `Vector3`, hit enum, flags, `Int16`);
- enum có `Default=0`, `Head=1`, `Body=2` để xác nhận hit type;
- cặp field aiming-info đứng trước `LastAimingInfoFromWeaponAdjusted` để tìm backing field trong `Player`;
- ba field đầu `Boolean, Vector2, Vector2` của `SceneEditBoxSelectTool` cho trạng thái menu;
- parameter đầu của `SetSpecialRunSpeedScaleByKeyAndValue` và `BuffSystem=500` cho speed enum;
- bảng 181 opcode `IFix.Core.Code` trong dump.

Nếu layout không còn duy nhất hoặc anchor bị đổi, updater dừng với lỗi cụ thể. Nó không chọn ngẫu nhiên một symbol gần giống.

Kết quả dò được ghi tại:

```text
generated/bindings.tsv
generated/bindings.json
generated/ESPLogic.cs
```

Không sửa trực tiếp `generated/ESPLogic.cs`, vì lần update sau sẽ ghi đè. Sửa logic chung trong `src/ESPLogic.template.cs`.

## UI menu

- Menu khởi động ở trạng thái ẩn.
- Chạm ba ngón 5 lần liên tiếp để mở.
- Khoảng nghỉ trên 3 giây reset chuỗi tap.
- Kéo header để di chuyển panel; vị trí được clamp trong màn hình.
- Nút `X` đóng panel.

Tab `ESP`:

- Enable ESP
- Player box
- Top tracer
- Health bar
- Player name
- Distance

Tab `AIM`:

- Silent aim
- Aim system
- Silent target mode / headshot rate / FOV theo context
- Native target `HEAD/NECK` theo context
- No recoil

Tab `SETTINGS`:

- Fast parachute
- Speed running x3
- Reset defaults
- Hide menu

## Verify thủ công

```powershell
py -3.10 .\tools\parse_ifix_patch.py `
  .\dist\Assembly-CSharp-patch.bytes `
  -o .\dist\Assembly-CSharp-patch.report.json

py -3.10 .\tools\verify_ifix_patch.py `
  .\dist\Assembly-CSharp-patch.bytes `
  --dump .\dumps\unknown_package_name_1.132.1.cs `
  --json .\dist\Assembly-CSharp-patch.verify.json
```

Kết quả hợp lệ phải có:

- `valid: true`;
- `errors: []`;
- `warnings: []`;
- 6 redirects;
- không có `Fast reload x3` hoặc `Fake lag (fire)`;
- hash trong manifest trùng hash của file bytes.

## Cấu trúc thư mục

```text
project-freefire_c#/
|-- build.ps1                   # update + compile + verify + install vào dist
|-- update.ps1                  # entry point khi thêm dump mới
|-- dumps/                      # đặt dump game ở đây
|-- src/
|   |-- ESPLogic.template.cs    # logic/menu với placeholder binding
|   `-- WeaveEsp.cs             # Cecil retarget + method-body weaving
|-- tools/
|   |-- update_from_dump.py     # tự dò binding và sinh source
|   |-- prepare_compiler.py     # opcode/magic-specific compiler source
|   |-- parse_ifix_patch.py     # parser container IFix
|   `-- verify_ifix_patch.py    # verifier reference/CFG/stack
|-- baseline/
|   |-- DummyDll/               # reference assembly baseline
|   `-- Assembly-CSharp-patch-neutral.bytes
|-- vendor/InjectFix/           # source/compiler dependency tối thiểu
|-- generated/                  # file sinh tự động
|-- build/                      # file tạm compiler
`-- dist/                       # output dùng thực tế
```

## Giới hạn của dump-only update

Dump C# cung cấp tên, signature, field layout và opcode, nhưng không chứa đầy đủ MVID/assembly identity của binary gốc. Pipeline giữ assembly identity từ baseline dummy và magic/dialect từ neutral seed, đồng thời verify toàn bộ reference có trong patch với dump mới.

Khi update chỉ đổi obfuscation/layout theo dạng hiện tại, chỉ cần thêm dump mới. Nếu game đổi hẳn IFix container magic/dialect hoặc assembly identity, cần thay baseline tương ứng trước khi build tiếp.

## Xử lý lỗi

`List<Player> method is ambiguous`:

- match container đã đổi cấu trúc;
- xem các candidate được báo và cập nhật rule trong `update_from_dump.py`.

`expected one aiming-info field layout`:

- aiming-info class đã thêm/xóa/đổi thứ tự field;
- đối chiếu `get_LastAimingInfoFromWeapon` và cập nhật layout detector.

`DUMP_METHOD_UNRESOLVED`, `DUMP_TYPE_MISSING`, `DUMP_FIELD_MISSING`:

- source/binding không khớp dump đang verify;
- chạy lại `update.ps1 -DumpPath <dump>` và không dùng file cũ trong `generated/`.

Lỗi opcode table:

- dump thiếu `IFix.Core.Code` hoặc enum không còn đủ 181 giá trị liên tục;
- dùng dump đầy đủ từ đúng build game.
