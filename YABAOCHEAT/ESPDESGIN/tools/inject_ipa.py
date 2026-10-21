#!/usr/bin/env python3
"""Inject ESP patch into an original Free Fire iOS IPA file."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import zipfile
from pathlib import Path


def select_ipa_dialog() -> Path | None:
    """Prompt user with Windows file picker dialog if available."""
    try:
        import tkinter as tk
        from tkinter import filedialog

        root = tk.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        file_path = filedialog.askopenfilename(
            title="Chọn file IPA Free Fire gốc của bạn",
            filetypes=[("iOS App Archive (*.ipa)", "*.ipa"), ("All Files (*.*)", "*.*")],
        )
        root.destroy()
        if file_path:
            return Path(file_path).resolve()
    except Exception:
        pass

    # Console fallback
    print("Vui lòng nhập đường dẫn đến file .ipa gốc:")
    user_input = input("> ").strip().strip('"').strip("'")
    if user_input and Path(user_input).is_file():
        return Path(user_input).resolve()
    return None


def inject_patch(ipa_path: Path, patch_path: Path, manifest_path: Path | None, output_path: Path | None = None) -> Path:
    if not ipa_path.is_file():
        raise FileNotFoundError(f"File IPA không tồn tại: {ipa_path}")
    if not patch_path.is_file():
        raise FileNotFoundError(f"File patch không tồn tại: {patch_path}")

    if output_path is None:
        output_path = ipa_path.parent / f"{ipa_path.stem}_ESP_Injected.ipa"

    patch_bytes = patch_path.read_bytes()
    manifest_bytes = manifest_path.read_bytes() if manifest_path and manifest_path.is_file() else None

    print(f"\n[1/3] Đang phân tích file IPA: {ipa_path.name} ({ipa_path.stat().st_size / (1024*1024):.1f} MB)...")

    with zipfile.ZipFile(ipa_path, "r") as zin:
        namelist = zin.namelist()
        app_dirs = [n for n in namelist if n.startswith("Payload/") and n.rstrip("/").endswith(".app") and (n.endswith("/") or "/" not in n[8:])]
        if not app_dirs:
            # Fallback search for any .app in Payload
            app_dirs = list({n[: n.index(".app/") + 5] for n in namelist if "Payload/" in n and ".app/" in n})

        if not app_dirs:
            raise ValueError("Không tìm thấy thư mục Payload/*.app hợp lệ trong file IPA!")

        app_dir = app_dirs[0]
        if not app_dir.endswith("/"):
            app_dir += "/"

        print(f"[*] Đã nhận diện ứng dụng: {app_dir}")
        target_patch_entry = f"{app_dir}Data/Managed/Assembly-CSharp-patch.bytes"
        target_manifest_entry = f"{app_dir}Data/Managed/patch-manifest.json"

        total_files = len(zin.infolist())
        print(f"[2/3] Đang sao chép tài nguyên và nhúng patch vào {target_patch_entry}...")

        # Temporary output file to ensure atomic write
        temp_out = output_path.with_suffix(".tmp.ipa")
        if temp_out.is_file():
            temp_out.unlink()

        try:
            with zipfile.ZipFile(temp_out, "w", compression=zipfile.ZIP_DEFLATED) as zout:
                for idx, item in enumerate(zin.infolist()):
                    if item.filename in (target_patch_entry, target_manifest_entry):
                        continue

                    # Stream file to avoid high memory consumption
                    with zin.open(item) as src, zout.open(item, "w") as dst:
                        shutil.copyfileobj(src, dst)

                    if idx % 100 == 0 or idx == total_files - 1:
                        percent = (idx + 1) / total_files * 100
                        print(f"\r    Tiến trình: {percent:.1f}% ({idx + 1}/{total_files} tệp)", end="", flush=True)

                print()
                # Write patch bytes
                print(f"[*] Đang ghi đè file patch: Assembly-CSharp-patch.bytes ({len(patch_bytes)} bytes)...")
                zout.writestr(target_patch_entry, patch_bytes)
                if manifest_bytes:
                    zout.writestr(target_manifest_entry, manifest_bytes)

            if output_path.is_file():
                output_path.unlink()
            temp_out.rename(output_path)
        except Exception:
            if temp_out.is_file():
                temp_out.unlink()
            raise

    print(f"\n[3/3] HOÀN TẤT THÀNH CÔNG! 🎉")
    print(f"==================================================")
    print(f"File IPA đã inject: {output_path}")
    print(f"Kích thước file:    {output_path.stat().st_size / (1024*1024):.1f} MB")
    print(f"==================================================")
    print(f"👉 Bây giờ bạn có thể nhập file này vào ESign, bấm KÝ và CÀI ĐẶT bình thường!")
    return output_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", nargs="?", type=Path, help="Đường dẫn file IPA Free Fire gốc")
    parser.add_argument("--patch", type=Path, help="Đường dẫn file patch .bytes")
    parser.add_argument("--output", type=Path, help="Đường dẫn file IPA xuất ra")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[1]
    patch_path = args.patch or (project_root / "dist" / "Assembly-CSharp-patch.bytes")
    manifest_path = project_root / "dist" / "Assembly-CSharp-patch.manifest.json"

    if not patch_path.is_file():
        print(f"Lỗi: Không tìm thấy file patch tại {patch_path}")
        print("Vui lòng chạy build.ps1 trước để tạo file patch!")
        return 1

    ipa_path = args.ipa
    if not ipa_path:
        # Check current working directory for any .ipa
        candidates = [p for p in Path.cwd().glob("*.ipa") if not p.name.endswith("_injected.ipa")]
        if len(candidates) == 1:
            ipa_path = candidates[0]
            print(f"[*] Tự động phát hiện file IPA: {ipa_path.name}")
        else:
            ipa_path = select_ipa_dialog()

    if not ipa_path or not ipa_path.is_file():
        print("Lỗi: Không có file IPA nào được chọn!")
        return 1

    try:
        inject_patch(ipa_path, patch_path, manifest_path, args.output)
        return 0
    except Exception as exc:
        print(f"\n[X] Lỗi trong quá trình inject: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
