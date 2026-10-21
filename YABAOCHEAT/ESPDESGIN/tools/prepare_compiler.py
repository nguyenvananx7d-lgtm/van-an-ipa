#!/usr/bin/env python3
"""Generate target-specific InjectFix compiler sources from project metadata."""

from __future__ import annotations

import argparse
import re
import struct
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dump", required=True, type=Path)
    parser.add_argument("--neutral-patch", required=True, type=Path)
    parser.add_argument("--instruction-source", required=True, type=Path)
    parser.add_argument("--translator-source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    dump_text = args.dump.read_text(encoding="utf-8", errors="replace")
    pairs = [
        (name, int(value))
        for name, value in re.findall(
            r"public const (?:IFix\.Core\.)?Code ([A-Za-z0-9_]+) = ([0-9]+);",
            dump_text,
        )
    ]
    by_value = {value: name for name, value in pairs}
    if len(by_value) != 181 or sorted(by_value) != list(range(181)):
        raise ValueError("dump does not contain one contiguous 181-opcode Code table")
    opcode_names = [by_value[index] for index in range(181)]

    neutral = args.neutral_patch.read_bytes()
    if len(neutral) < 8:
        raise ValueError("Neutral patch is truncated")
    magic = struct.unpack_from("<Q", neutral)[0]

    instruction_text = args.instruction_source.read_text(encoding="utf-8")
    enum_body = "public enum Code\n    {\n" + "".join(
        f"        {name},\n" for name in opcode_names
    ) + "    }"
    instruction_text, enum_replacements = re.subn(
        r"public enum Code\s*\{.*?^    \}",
        enum_body,
        instruction_text,
        count=1,
        flags=re.MULTILINE | re.DOTALL,
    )
    instruction_text, magic_replacements = re.subn(
        r"public const ulong INSTRUCTION_FORMAT_MAGIC = [0-9]+;",
        f"public const ulong INSTRUCTION_FORMAT_MAGIC = {magic};",
        instruction_text,
        count=1,
    )
    if enum_replacements != 1 or magic_replacements != 1:
        raise ValueError("InjectFix Instruction.cs template did not match")

    translator_text = args.translator_source.read_text(encoding="utf-8")
    version_line = "                writer.Write((byte)0); // target patch format version"
    if version_line not in translator_text:
        needle = (
            '                writer.Write(idMap0Name.Substring("IFix.IDMAP0".Length));'
        )
        if translator_text.count(needle) != 1:
            raise ValueError("InjectFix CodeTranslator.cs template did not match")
        translator_text = translator_text.replace(needle, needle + "\n" + version_line)

    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "Instruction.cs").write_text(instruction_text, encoding="utf-8")
    (args.output / "CodeTranslator.cs").write_text(translator_text, encoding="utf-8")
    (args.output / "opcode-map.txt").write_text(
        "".join(f"{index:3d} {name}\n" for index, name in enumerate(opcode_names)),
        encoding="ascii",
    )
    print(f"magic=0x{magic:016X}")
    print(f"opcodes={len(opcode_names)}")
    print(f"output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
