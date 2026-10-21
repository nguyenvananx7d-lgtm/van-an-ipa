#!/usr/bin/env python3
"""Inspect an InjectFix/IFix patch without loading the target assembly."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


# This title shuffles InjectFix's opcode enum. The order below is recovered from
# the target metadata and maps the serialized integer back to the IL-like name.
OPCODE_NAMES = (
    "Ldelem_U2", "Endfinally", "Cpobj", "Ldc_R4", "Stfld", "Bge_Un",
    "Conv_Ovf_I2_Un", "Volatile", "Stelem_Ref", "Callvirt", "Tail",
    "Stind_Ref", "Ldind_I1", "Newarr", "Clt_Un", "Clt", "Ldstr",
    "Ldnull", "Ldobj", "Conv_Ovf_U4_Un", "Ldloc", "Ldelem_I2",
    "Conv_U", "Ldarga", "No", "Ldelema", "Newanon",
    "Conv_Ovf_U8_Un", "Ldarg", "Conv_Ovf_I1_Un", "Leave", "Div",
    "Cgt", "Ldelem_R4", "And", "Not", "Unbox_Any", "Stind_I",
    "Ldfld", "Stelem_R8", "Mul", "Conv_Ovf_I4", "Br", "Conv_I8",
    "Stind_R8", "Shr_Un", "Bgt", "Add_Ovf", "Stelem_Any",
    "Conv_Ovf_U2", "Refanyval", "Ldc_I8", "Conv_R4", "Starg",
    "Stelem_I8", "Stind_I1", "Ldind_R8", "StackSpace", "Conv_U8",
    "Jmp", "Ldsflda", "Stelem_I", "Brfalse", "Stelem_I2",
    "Localloc", "Unaligned", "Rem_Un", "Ceq", "Ldind_U2", "Ldftn",
    "Ldind_Ref", "Conv_Ovf_U", "Stind_I8", "Initblk", "Dup",
    "Conv_Ovf_U2_Un", "Conv_Ovf_U4", "Conv_Ovf_I", "Ble_Un",
    "Ldvirtftn2", "Conv_Ovf_I4_Un", "Ldind_I4", "Mkrefany",
    "Ldelem_U1", "Conv_I1", "Stind_R4", "Break", "Ldflda", "Rem",
    "Nop", "Ldelem_Ref", "Conv_Ovf_I8", "Sub_Ovf_Un", "Add_Ovf_Un",
    "Ldvirtftn", "Ldloca", "Sub", "Ldind_U1", "Cpblk", "Neg",
    "Conv_U1", "Ldelem_I8", "Switch", "Ldc_R8", "Conv_Ovf_U1_Un",
    "Newobj", "Conv_R_Un", "Readonly", "Conv_U2", "Ldind_I2",
    "Stobj", "Stelem_R4", "Ldind_R4", "Ldelem_I4", "Brtrue",
    "Constrained", "Unbox", "Ldlen", "Ldind_U4", "Castclass",
    "Conv_Ovf_I_Un", "Or", "Ldelem_U4", "Ldelem_I1", "Ldtype",
    "Conv_R8", "Ckfinite", "Sizeof", "Bgt_Un", "Ldtoken", "Blt",
    "Refanytype", "Ble", "Box", "Conv_Ovf_I1", "Ldelem_R8", "Ret",
    "Blt_Un", "Stind_I4", "Ldind_I8", "Stelem_I4", "Beq", "Isinst",
    "Ldelem_Any", "Ldsfld", "Mul_Ovf_Un", "Conv_Ovf_I2", "Xor",
    "Throw", "Rethrow", "Initobj", "Call", "Conv_I4", "Conv_I2",
    "Stsfld", "Cgt_Un", "Conv_U4", "Div_Un", "Stind_I2", "Conv_I",
    "Pop", "Shr", "Sub_Ovf", "Endfilter", "Stelem_I1",
    "Conv_Ovf_U8", "Bne_Un", "Mul_Ovf", "Conv_Ovf_U_Un", "Ldind_I",
    "Conv_Ovf_U1", "Ldelem_I", "Callvirtvirt", "Bge", "Add",
    "CallExtern", "Stloc", "Shl", "Conv_Ovf_I8_Un", "Arglist",
    "Ldc_I4",
)

BRANCH_OPCODES = {
    "Bge_Un", "Leave", "Br", "Bgt", "Brfalse", "Ble_Un", "Brtrue",
    "Bgt_Un", "Blt", "Ble", "Blt_Un", "Beq", "Bne_Un", "Bge",
}


class PatchReader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.offset = 0

    def read(self, size: int) -> bytes:
        end = self.offset + size
        if end > len(self.data):
            raise ValueError(
                f"Unexpected end of patch at 0x{self.offset:X}; requested {size} bytes"
            )
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def u8(self) -> int:
        return self.read(1)[0]

    def i32(self) -> int:
        return struct.unpack("<i", self.read(4))[0]

    def u64(self) -> int:
        return struct.unpack("<Q", self.read(8))[0]

    def string(self) -> str:
        length = 0
        shift = 0
        while True:
            byte = self.u8()
            length |= (byte & 0x7F) << shift
            if not byte & 0x80:
                break
            shift += 7
            if shift >= 35:
                raise ValueError(f"Invalid 7-bit string length at 0x{self.offset:X}")
        return self.read(length).decode("utf-8", errors="replace")


def type_name(types: list[str], index: int) -> str:
    if 0 <= index < len(types):
        return types[index]
    return f"<type-index:{index}>"


def read_method(reader: PatchReader, types: list[str]) -> dict[str, object]:
    generic_instance = bool(reader.u8())
    declaring_type = reader.i32()
    name = reader.string()

    generic_args: list[str] = []
    parameters: list[str] = []
    if generic_instance:
        generic_args = [type_name(types, reader.i32()) for _ in range(reader.i32())]
        for _ in range(reader.i32()):
            if reader.u8():
                parameters.append(reader.string())
            else:
                parameters.append(type_name(types, reader.i32()))
    else:
        parameters = [type_name(types, reader.i32()) for _ in range(reader.i32())]

    return {
        "declaring_type": type_name(types, declaring_type),
        "name": name,
        "generic_instance": generic_instance,
        "generic_args": generic_args,
        "parameters": parameters,
    }


def parse_patch(path: Path, include_instructions: bool = False) -> dict[str, object]:
    reader = PatchReader(path.read_bytes())
    result: dict[str, object] = {
        "file": str(path),
        "size": path.stat().st_size,
        "magic": f"0x{reader.u64():016X}",
        "interface_bridge": reader.string(),
    }

    types = [reader.string() for _ in range(reader.i32())]
    result["external_types"] = types

    code_summary: list[dict[str, object]] = []
    for method_id in range(reader.i32()):
        instruction_count = reader.i32()
        instructions: list[dict[str, object]] = []
        for index in range(instruction_count):
            opcode = reader.i32()
            operand = reader.i32()
            name = OPCODE_NAMES[opcode] if 0 <= opcode < len(OPCODE_NAMES) else f"Code_{opcode}"
            instruction: dict[str, object] = {
                "index": index,
                "opcode": opcode,
                "name": name,
                "operand": operand,
            }
            if name in BRANCH_OPCODES:
                instruction["target"] = index + operand
            instructions.append(instruction)
        exception_count = reader.i32()
        reader.read(exception_count * 24)
        if instruction_count or exception_count:
            method_summary: dict[str, object] = {
                "method_id": method_id,
                "instructions": instruction_count,
                "exceptions": exception_count,
            }
            if include_instructions:
                method_summary["code"] = instructions
            code_summary.append(method_summary)
    result["patched_code"] = code_summary

    result["external_methods"] = [
        read_method(reader, types) for _ in range(reader.i32())
    ]
    result["strings"] = [reader.string() for _ in range(reader.i32())]

    fields: list[dict[str, object]] = []
    for _ in range(reader.i32()):
        new_field = bool(reader.u8())
        declaring_type = reader.i32()
        field: dict[str, object] = {
            "new": new_field,
            "declaring_type": type_name(types, declaring_type),
            "name": reader.string(),
        }
        if new_field:
            field["field_type"] = type_name(types, reader.i32())
            field["constructor_method_id"] = reader.i32()
        fields.append(field)
    result["fields"] = fields

    static_field_types: list[dict[str, object]] = []
    for _ in range(reader.i32()):
        static_field_types.append(
            {
                "type": type_name(types, reader.i32()),
                "static_constructor_method_id": reader.i32(),
            }
        )
    result["static_field_types"] = static_field_types

    anonymous_type_count = reader.i32()
    result["anonymous_type_count"] = anonymous_type_count
    if anonymous_type_count:
        raise ValueError(
            "Anonymous IFix types require target interface metadata to parse; "
            f"stopped at 0x{reader.offset:X}"
        )

    result["wrapper_manager"] = reader.string()
    result["id_map_assembly_suffix"] = reader.string()
    # This game's IFix fork adds a one-byte flag before the redirect table.
    result["redirect_table_flag"] = reader.u8()

    redirects: list[dict[str, object]] = []
    for _ in range(reader.i32()):
        method = read_method(reader, types)
        method["vm_method_id"] = reader.i32()
        redirects.append(method)
    result["redirects"] = redirects
    result["new_classes"] = [reader.string() for _ in range(reader.i32())]
    result["parsed_through_offset"] = f"0x{reader.offset:X}"
    result["remaining_bytes"] = len(reader.data) - reader.offset
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("patch", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    parser.add_argument(
        "--include-instructions",
        action="store_true",
        help="Include decoded target VM instructions in the JSON output",
    )
    args = parser.parse_args()

    report = parse_patch(args.patch, include_instructions=args.include_instructions)
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
        print(args.output)
    else:
        print(rendered)


if __name__ == "__main__":
    main()
