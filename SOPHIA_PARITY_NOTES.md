# VortexArena — Sophia Parity Notes

> Ghi chú kỹ thuật về việc làm bản reskin **YABAOCHEAT / "Vortex Arena"** (cheat Free Fire iOS)
> hoạt động đúng trên máy thật, giống hệt bản tham chiếu **`Sophia299 [ MINI UPDATE ].ipa`** (vendor "Sophia Cheat").
> Mọi offset/blob/native hint giữ nguyên, chỉ sửa logic staging + launch + chẩn đoán.

---

## 1. Mục tiêu

- ESP/aim phải **ăn trên máy thật** (iOS 26.5.2, build 23F84).
- Tái tạo **chính xác cách bản tham chiếu (Sophia)** làm: file để đâu, config thế nào, game nạp ra sao.

---

## 2. Bản tham chiếu (Sophia) — thông tin đã khai thác

- File: `C:\Users\Administrator\Downloads\Sophia299 [ MINI UPDATE ].ipa` (4.37 MB)
- Extract: `C:\Users\Administrator\AppData\Local\Temp\opencode\sophia\Payload\YABAOCHEAT.app`
- Strings dump: `C:\Users\Administrator\AppData\Local\Temp\opencode\sophia_strings.txt` (11992 dòng)
- Cùng codebase (`YABAOCHEAT.app`, bundle id `com.apple.mobile.MobileHouseArrest`, Swift symbols `_TtC10YABAOCHEAT...`).
- Entitlements ≈ bản của ta (no-sandbox, container-manager, springboard/frontboard launch, canmaplsdatabase, IOKit user clients), Info.plist **không** có `LSApplicationQueriesSchemes`, MinOS 15.0.
- Chỉ link framework public + libSystem/libobjc, dùng `dlsym`/`dlopen` — **không** có SBS/workspace class private nào được link.

### Launch của Sophia

- Không link SpringBoardServices, không chứa "LSApplicationWorkspace" → không dùng workspace.
- `[LAUNCH] cold start requested` / `[LAUNCH] completed` / `Game launch request failed` — mở bằng `UIApplication.open`, scheme **không được "ghi cứng"** riêng trong strings (được dựng runtime).

### "KRW" là container metadata scan, không phải kernel exploit

- Ghi `Documents/ffxc_debug.log` vào container game.
- Signature: `FFXC-V4|pkg_40921350d3307e51491f27cb`.
- Probe marker: `{"testCodePatch":true}` (giống hệt bản của ta).

---

## 3. Blob patch — "patch vào đâu & patch như thế nào" (giải mã)

File `Assembly-CSharp-patch.bytes` (322 B) — **cùng SHA-256 ở cả 2 bản**:

```
sophia: 4c2c13744bc558fb16400aeaf0ef59c2b4c4b9cde41446ff0c6e51aa2f96c49e
ours:   4c2c13744bc558fb16400aeaf0ef59c2b4c4b9cde41446ff0c6e51aa2f96c49e
identical: True
```

Hexdump + printable:

```
0000  cb a2 b4 0d b2 19 a3 66 64 49 46 69 78 2e 49 4c  .......fdIFix.IL
0010  46 69 78 49 6e 74 65 72 66 61 63 65 42 72 69 64  FixInterfaceBrid
0020  67 65 2c 20 41 73 73 65 6d 62 6c 79 2d 43 53 68  ge, Assembly-CSh
0030  61 72 70 2c 20 56 65 72 73 69 6f 6e 3d 30 2e 38  arp, Version=0.8
0040  36 2e 30 2e 35 31 38 2c 20 43 75 6c 74 75 72 65  6.0.518, Culture
0050  3d 6e 65 75 74 72 61 6c 2c 20 50 75 62 6c 69 63  =neutral, Public
0060  4b 65 79 54 6f 6b 65 6e 3d 6e 75 6c 6c 00 ...     KeyToken=null...
...
   ... cIFix.WrappersManagerImpl, Assembly-CSharp, Version=0.86.0.518,
       Culture=neutral, PublicKeyToken=nullK, Assembly-CSharp, Version=0.86.0.518, ...
00.. cIFix.WrappersManagerImpl ...
```

**Kết luận:** blob là **IFix manifest** (Tencent Mono hotfix) trỏ vào 2 type:
- `IFix.ILFixInterfaceBridge, Assembly-CSharp, Version=0.86.0.518`
- `IFix.WrappersManagerImpl, Assembly-CSharp, Version=0.86.0.518`

→ **Patch chỉ ăn trên đúng game build có IFix runtime + `Assembly-CSharp` version 0.86.0.518.**
Blob khác version / bản game đổi → loader **im lặng từ chối**: game chạy bình thường, file vẫn nguyên, **không ESP**.

### Config phía game — `localConfig.json`

Keys flat (recovered `RecoveredVocabulary.RuntimeConfig`, lấy nguyên văn từ `__cstring` của Sophia):

```
aimbotRadius, h0, a0, fastReloadPercent, fastFireLevel, espColor, espThickness, aimFovMode
```

- `h0` / `a0` nằm giữa `aimbotRadius` và `fastReloadPercent` — màu + alpha (ta đang decompose từ `espColor`).
- Không có "Documents" đơn lẻ / Library/Preferences/tmp/Managed/dataPath trong strings → Sophia ghép đường theo kiểu
  `root + "/" + rel` với rel ∈ {`localConfig.json`, `Assembly-CSharp-patch.bytes`, `Documents/ffxc_debug.log`}.

### Chỗ ghi (staging của TA)

`ContainerBridge.payloadDirectories` = container root (data dir) + `Documents/`.
`patchURLs` = (root|Documents) × (`Assembly-CSharp-patch.bytes`, `Assembly-CSharp-patch`).
`configURLs` = (root|Documents) × `localConfig.json`.

---

## 4. Bug CHÍNH của bản cũ — process detection

Triệu chứng trên máy thật (bản trước):

```
[LAUNCH] workspace accepted the launch request for com.dts.freefireth
[RUNTIME] post-launch probe: target HAS EXITED (no fire-named process running)
```

Nhưng người dùng xác nhận: **game mở bình thường** (cả Inject lẫn mở tay), chỉ **thiếu ESP/aim**.

Nguyên nhân:

- `GameLauncher.wantedCommFragments = ["freefire", "free fire", "com.dts.freefire"]` — `p_comm` của game Unity
  có thể là `Unity-iPhone`/tên khác **không chứa "fire"** → mọi verdict "HAS EXITED" là SAI.
- Cùng blind spot đó làm bước **kill game cũ trước khi launch (`terminateFirst`)** im lặng không chạy
  → game còn sống từ lần trước → **warm start**, runtime cũ giữ nguyên → **patch không bao giờ được nạp**.

### Đã sửa

- `PostLaunchProbe` không còn báo "HAS EXITED": nếu không khớp tên → in **mẫu bảng process thật**
  (`pid:comm`) để lộ tên thật của process game.
- `GameLauncher.processTableSample(limit:)` + `diagnosticCommFragments` (`fire, freefire, garena, unity, dts, ff, game`) — chỉ để *báo cáo*, riêng `wantedCommFragments` (kill cold-start) giữ bộ hẹp để tránh kill nhầm.

---

## 5. Thay đổi đã làm (commits)

| Commit | Nội dung |
|---|---|
| `e444a18` | launch/exploit/probe: bỏ gate `canOpenURL`, luôn `UIApplication.open(scheme)`; `kernelStageSupported` 17.0–18.7.1; `ensureExploitBeforeInject` skip auto-run không hỗ trợ |
| `e56ed6e` | theme near-black |
| `8bb8e8d` | launch: candidate scheme `dtsgff://`, `freefire://` → SBS (`SBSLaunchApplicationWithIdentifier` qua `dlsym`) → workspace; early 1.5s/4s process checks |
| `afb03df` | **diagnostics**: `ContainerDump` (nút "Dump container (read-only)"), probe báo process thật, không còn "HAS EXITED" giả |

Build mới nhất: `VortexArena-unsigned.ipa` (1,308,737 B) đã ở `Downloads`.

---

## 6. Chẩn đoán đang treo — cần test trên máy

1. **Test cold start:** đóng hẳn Free Fire (vuốt khỏi App Switcher) → Inject → chờ ~10s → vào trận xem ESP → gửi log.
2. **Test so sánh (quyết định):** chạy SOPHIA → Inject trên Sophia → mở app của TA →
   bấm **"Dump container (read-only)"** → gửi log. Lấy đúng file Sophia để lại (file nào, đường nào,
   `localConfig.json` nguyên văn, digest, marker) → so từng byte với staging của ta.
3. **Xác nhận version game đang cài** (Esign/Scarlet): có phải bản `0.86.0` (mod có IFix runtime) hay bản mới hơn?
   Nếu không phải 0.86.0.518 → chính là lý do cheat không bao giờ ăn.

### Dữ kiện máy thật (vòng test mới nhất)

- Install qua **Esign / Scarlet** (không TrollStore) → `no-sandbox=false container-manager=false` (entitlement không được honor).
- MCM lookup `com.dts.freefiremax` **denied** (`message=unknown`) → chỉ **`com.dts.freefireth`** (Free Fire) có container.
- Container freefireth: `/private/var/mobile/Containers/Data/Application/36AB7E1F-4003-4347-8BAB-83A8EA066162`.
- Write qua **bad_query grant** giữ được (handle 2/3/4) — staging OK: patch 4 chỗ + config 2 chỗ, intact sau 10s, `testCodePatch=true` present.
- Game **MỞ BÌNH THƯỜNG** khi Inject và khi mở tay — **ESP/aim vẫn không chạy.**

---

## 7. Tài liệu tham chiếu (đường dẫn máy)

- Repo: `C:\Users\Administrator\Downloads\van-an-ipa-main` (nhánh `main`, ci build.yml → artifact `VortexArena-unsigned.ipa`)
- Sophia IPA: `C:\Users\Administrator\Downloads\Sophia299 [ MINI UPDATE ].ipa`
- Sophia extract: `C:\Users\Administrator\AppData\Local\Temp\opencode\sophia\Payload\YABAOCHEAT.app`
- Sophia strings: `C:\Users\Administrator\AppData\Local\Temp\opencode\sophia_strings.txt`
- File quan trọng:
  - `YABAOCHEAT/Injection/GameLauncher.swift`
  - `YABAOCHEAT/Injection/ContainerBridge.swift`
  - `YABAOCHEAT/Injection/RuntimeInstaller.swift`
  - `YABAOCHEAT/Injection/PatchPayload.swift`
  - `YABAOCHEAT/Injection/PostLaunchProbe.swift`
  - `YABAOCHEAT/Injection/ContainerDump.swift` (mới)
  - `YABAOCHEAT/Model/RecoveredVocabulary.swift`
  - `YABAOCHEAT/Model/FeatureControls.swift`
  - `YABAOCHEAT/Store/InjectStore.swift`
  - `YABAOCHEAT/UI/InjectView.swift`