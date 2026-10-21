#!/usr/bin/env python3
"""Statically verify this title's serialized InjectFix/IFix VM patch."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from parse_ifix_patch import OPCODE_NAMES


TARGET_MAGIC = 0x66A319B20DB4A2CB
TARGET_DIALECT = "target-flag-v1"

REL_BRANCHES = {
    "Br", "Brfalse", "Brtrue", "Beq", "Bge", "Bgt", "Ble", "Blt",
    "Bne_Un", "Bge_Un", "Bgt_Un", "Ble_Un", "Blt_Un",
}
COND_ONE_BRANCHES = {"Brfalse", "Brtrue"}
COND_TWO_BRANCHES = REL_BRANCHES - COND_ONE_BRANCHES - {"Br"}
LITERAL_PAYLOADS = {"Ldc_I8": 1, "Ldc_R8": 1}

DIRECT_TYPE_REFS = {
    "Newarr", "Ldelema", "Initobj", "Ldobj", "Stobj", "Constrained",
    "Ldtoken", "Ldtype",
}
TYPE_OR_ANON_REFS = {"Box", "Unbox", "Unbox_Any", "Castclass", "Isinst"}
INSTANCE_FIELD_REFS = {"Ldfld", "Ldflda", "Stfld"}
STATIC_FIELD_REFS = {"Ldsfld", "Ldsflda", "Stsfld"}
INTERNAL_CALLS = {"Call", "Callvirt"}
EXTERNAL_CALLS = {"CallExtern", "Newobj"}
EXTERNAL_METHOD_REFS = {"Ldftn", "Ldvirtftn"}
VTABLE_REFS = {"Callvirtvirt", "Ldvirtftn2"}

PUSH_ONE = {
    "Ldarg", "Ldloc", "Ldarga", "Ldloca", "Ldnull", "Ldc_I4", "Ldc_I8",
    "Ldc_R4", "Ldc_R8", "Ldstr", "Ldsfld", "Ldsflda", "Ldftn", "Ldtype",
    "Ldtoken", "Arglist", "Sizeof",
}
UNARY_SAME = {
    "Ldind_I1", "Ldind_U1", "Ldind_I2", "Ldind_U2", "Ldind_I4",
    "Ldind_U4", "Ldind_I8", "Ldind_I", "Ldind_R4", "Ldind_R8",
    "Ldind_Ref", "Ldobj", "Ldfld", "Ldflda", "Newarr", "Ldlen", "Box",
    "Unbox", "Unbox_Any", "Castclass", "Isinst", "Neg", "Not", "Conv_I1",
    "Conv_I2", "Conv_I4", "Conv_I8", "Conv_R4", "Conv_R8", "Conv_U4",
    "Conv_U8", "Conv_R_Un", "Conv_Ovf_I1_Un", "Conv_Ovf_I2_Un",
    "Conv_Ovf_I4_Un", "Conv_Ovf_I8_Un", "Conv_Ovf_U1_Un",
    "Conv_Ovf_U2_Un", "Conv_Ovf_U4_Un", "Conv_Ovf_U8_Un",
    "Conv_Ovf_I_Un", "Conv_Ovf_U_Un", "Conv_Ovf_I1", "Conv_Ovf_U1",
    "Conv_Ovf_I2", "Conv_Ovf_U2", "Conv_Ovf_I4", "Conv_Ovf_U4",
    "Conv_Ovf_I8", "Conv_Ovf_U8", "Conv_U2", "Conv_U1", "Conv_I",
    "Conv_Ovf_I", "Conv_Ovf_U", "Conv_U", "Ckfinite", "Refanyval",
    "Mkrefany", "Refanytype",
}
BINARY_TO_ONE = {
    "Add", "Sub", "Mul", "Div", "Div_Un", "Rem", "Rem_Un", "And", "Or",
    "Xor", "Shl", "Shr", "Shr_Un", "Add_Ovf", "Add_Ovf_Un", "Mul_Ovf",
    "Mul_Ovf_Un", "Sub_Ovf", "Sub_Ovf_Un", "Ceq", "Cgt", "Cgt_Un", "Clt",
    "Clt_Un",
}
POP_ONE = {"Pop", "Stloc", "Starg", "Stsfld", "Initobj"}
POP_TWO = {
    "Stind_Ref", "Stind_I1", "Stind_I2", "Stind_I4", "Stind_I8", "Stind_R4",
    "Stind_R8", "Stind_I", "Stobj", "Stfld", "Cpobj",
}
ARRAY_LOADS = {
    "Ldelema", "Ldelem_I1", "Ldelem_U1", "Ldelem_I2", "Ldelem_U2",
    "Ldelem_I4", "Ldelem_U4", "Ldelem_I8", "Ldelem_I", "Ldelem_R4",
    "Ldelem_R8", "Ldelem_Ref", "Ldelem_Any",
}
ARRAY_STORES = {
    "Stelem_I", "Stelem_I1", "Stelem_I2", "Stelem_I4", "Stelem_I8",
    "Stelem_R4", "Stelem_R8", "Stelem_Ref", "Stelem_Any",
}
NO_STACK_CHANGE = {
    "Nop", "Break", "Br", "Leave", "Volatile", "Unaligned", "Tail", "No",
    "Readonly", "Constrained",
}

# These enum members exist upstream but have no dispatch case in the VM source.
UNSUPPORTED_BY_VM_SOURCE = {
    "Break", "Jmp", "Cpobj", "Refanyval", "Ckfinite", "Mkrefany", "Localloc",
    "Endfilter", "Unaligned", "Tail", "Cpblk", "Initblk", "No", "Sizeof",
    "Refanytype", "Readonly", "Arglist",
}


class PatchError(ValueError):
    pass


@dataclass
class Issue:
    severity: str
    code: str
    where: str
    message: str

    def as_dict(self) -> dict[str, str]:
        return {
            "severity": self.severity,
            "code": self.code,
            "where": self.where,
            "message": self.message,
        }


@dataclass
class MethodRef:
    declaring_type_index: int
    declaring_type: str
    name: str
    generic_instance: bool
    generic_argument_indices: list[int]
    generic_arguments: list[str]
    parameter_type_indices: list[int | None]
    parameters: list[str]

    def as_dict(self) -> dict[str, object]:
        return {
            "declaring_type_index": self.declaring_type_index,
            "declaring_type": self.declaring_type,
            "name": self.name,
            "generic_instance": self.generic_instance,
            "generic_argument_indices": self.generic_argument_indices,
            "generic_arguments": self.generic_arguments,
            "parameter_type_indices": self.parameter_type_indices,
            "parameters": self.parameters,
        }


@dataclass
class ExceptionRecord:
    handler_type: int
    catch_type_id: int
    try_start: int
    try_end: int
    handler_start: int
    handler_end: int


@dataclass
class VmMethod:
    method_id: int
    slots: list[tuple[int, int]]
    exceptions: list[ExceptionRecord]
    executable: list[int] = field(default_factory=list)
    data_slots: set[int] = field(default_factory=set)
    switch_targets: dict[int, list[int]] = field(default_factory=dict)
    next_slot: dict[int, int] = field(default_factory=dict)
    locals_count: int | None = None
    declared_max_stack: int | None = None
    return_arity: int | None = None
    observed_max_stack: int | None = None
    reachable_slots: int = 0
    stack_verified: bool = False


@dataclass
class DumpMethod:
    name: str
    parameter_count: int
    return_arity: int
    is_static: bool
    return_type: str
    line_number: int


class Reader:
    def __init__(self, data: bytes, offset: int = 0) -> None:
        self.data = data
        self.offset = offset

    def read(self, size: int, label: str = "data") -> bytes:
        if size < 0:
            raise PatchError(f"negative size for {label}: {size}")
        end = self.offset + size
        if end > len(self.data):
            raise PatchError(
                f"truncated {label} at 0x{self.offset:X}: need {size}, "
                f"have {len(self.data) - self.offset}"
            )
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def u8(self, label: str = "byte") -> int:
        return self.read(1, label)[0]

    def i32(self, label: str = "int32") -> int:
        return struct.unpack("<i", self.read(4, label))[0]

    def u64(self, label: str = "uint64") -> int:
        return struct.unpack("<Q", self.read(8, label))[0]

    def count(self, label: str, limit: int = 10_000_000) -> int:
        value = self.i32(label)
        if value < 0 or value > limit:
            raise PatchError(f"invalid {label} at 0x{self.offset - 4:X}: {value}")
        return value

    def string(self, label: str = "string") -> str:
        length = 0
        shift = 0
        while True:
            byte = self.u8(f"{label} length")
            length |= (byte & 0x7F) << shift
            if not byte & 0x80:
                break
            shift += 7
            if shift >= 35:
                raise PatchError(f"invalid 7-bit length for {label}")
        raw = self.read(length, label)
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise PatchError(f"invalid UTF-8 in {label} at 0x{self.offset - length:X}") from exc


def leading_aqn_type(value: str) -> str:
    depth = 0
    for index, char in enumerate(value):
        if char == "[":
            depth += 1
        elif char == "]":
            depth = max(0, depth - 1)
        elif char == "," and depth == 0:
            return value[:index].strip()
    return value.strip()


def leading_aqn_assembly(value: str) -> str | None:
    depth = 0
    comma_positions: list[int] = []
    for index, char in enumerate(value):
        if char == "[":
            depth += 1
        elif char == "]":
            depth = max(0, depth - 1)
        elif char == "," and depth == 0:
            comma_positions.append(index)
            if len(comma_positions) == 2:
                break
    if not comma_positions:
        return None
    start = comma_positions[0] + 1
    end = comma_positions[1] if len(comma_positions) > 1 else len(value)
    return value[start:end].strip()


def normalize_type(value: str) -> str:
    value = leading_aqn_type(value).replace("+", ".").replace("/", ".")
    value = re.sub(r"`\d+", "", value)
    value = re.sub(r"<.*>", "", value)
    return value.rstrip("&*").strip()


def normalize_method(value: str) -> str:
    return re.sub(r"<.*>$", "", value.strip())


def split_parameters(value: str) -> list[str]:
    value = value.strip()
    if not value:
        return []
    result: list[str] = []
    start = 0
    angle = square = paren = 0
    for index, char in enumerate(value):
        if char == "<":
            angle += 1
        elif char == ">":
            angle = max(0, angle - 1)
        elif char == "[":
            square += 1
        elif char == "]":
            square = max(0, square - 1)
        elif char == "(":
            paren += 1
        elif char == ")":
            paren = max(0, paren - 1)
        elif char == "," and angle == square == paren == 0:
            result.append(value[start:index].strip())
            start = index + 1
    result.append(value[start:].strip())
    return result


class DumpIndex:
    TYPE_RE = re.compile(
        r"^(?:public|private|protected|internal)\s+"
        r"(?:(?:abstract|sealed|static|partial|unsafe|readonly|ref|new)\s+)*"
        r"(?:class|struct|interface|enum)\s+([^\s:<]+(?:<[^>]+>)?)"
    )

    def __init__(self) -> None:
        self.loaded = False
        self.types: set[str] = set()
        self.fields: dict[str, set[str]] = {}
        self.methods: dict[str, list[DumpMethod]] = {}

    @classmethod
    def load(cls, path: Path | None, wanted_types: Iterable[str]) -> "DumpIndex":
        index = cls()
        if path is None:
            return index
        index.loaded = True
        wanted = {normalize_type(value) for value in wanted_types}
        namespace = ""
        current_type: str | None = None
        in_fields = False
        in_methods = False
        with path.open("r", encoding="utf-8", errors="replace") as stream:
            for line_number, line in enumerate(stream, 1):
                stripped = line.strip()
                if stripped.startswith("// Namespace:"):
                    namespace = stripped.partition(":")[2].strip()
                    current_type = None
                    in_fields = False
                    in_methods = False
                    continue
                type_match = cls.TYPE_RE.match(stripped)
                if type_match:
                    raw_name = type_match.group(1)
                    full_name = f"{namespace}.{raw_name}" if namespace else raw_name
                    normalized = normalize_type(full_name)
                    index.types.add(normalized)
                    current_type = normalized if normalized in wanted else None
                    in_fields = False
                    in_methods = False
                    if current_type is not None:
                        index.fields.setdefault(current_type, set())
                        index.methods.setdefault(current_type, [])
                    continue
                if current_type is None:
                    continue
                if stripped == "// Fields":
                    in_fields = True
                    in_methods = False
                    continue
                if stripped == "// Methods":
                    in_fields = False
                    in_methods = True
                    continue
                if in_fields:
                    parsed_field = cls._parse_field_line(stripped)
                    if parsed_field is not None:
                        index.fields[current_type].add(parsed_field)
                    continue
                if not in_methods or "(" not in stripped or ")" not in stripped:
                    continue
                parsed = cls._parse_method_line(stripped, line_number)
                if parsed is not None:
                    index.methods[current_type].append(parsed)
        return index

    @staticmethod
    def _parse_field_line(line: str) -> str | None:
        if not re.match(r"^(?:public|private|protected|internal)\b", line):
            return None
        declaration = line.partition("//")[0].strip()
        if not declaration.endswith(";") or "(" in declaration:
            return None
        declaration = declaration[:-1].partition("=")[0].strip()
        tokens = declaration.split()
        modifiers = {
            "public", "private", "protected", "internal", "static", "readonly",
            "const", "volatile", "new", "unsafe",
        }
        tokens = [token for token in tokens if token not in modifiers]
        return tokens[-1] if len(tokens) >= 2 else None

    @staticmethod
    def _parse_method_line(line: str, line_number: int) -> DumpMethod | None:
        if not re.match(r"^(?:public|private|protected|internal)\b", line):
            return None
        open_paren = line.find("(")
        close_paren = line.rfind(")")
        if open_paren < 0 or close_paren < open_paren:
            return None
        left = line[:open_paren].strip()
        if " " not in left:
            return None
        prefix, name = left.rsplit(None, 1)
        prefix_tokens = prefix.split()
        if len(prefix_tokens) < 2:
            return None
        return_type = prefix_tokens[-1]
        parameters = split_parameters(line[open_paren + 1:close_paren])
        return DumpMethod(
            name=normalize_method(name),
            parameter_count=len(parameters),
            return_arity=0 if return_type in ("void", "System.Void") else 1,
            is_static="static" in prefix_tokens,
            return_type=return_type,
            line_number=line_number,
        )

    def lookup(self, method: MethodRef) -> list[DumpMethod]:
        candidates = self.methods.get(normalize_type(method.declaring_type), [])
        name = normalize_method(method.name)
        return [
            item for item in candidates
            if item.name == name and item.parameter_count == len(method.parameters)
        ]

    def declared_method_count(self, type_name: str) -> int | None:
        methods = self.methods.get(normalize_type(type_name))
        return None if methods is None else len(methods)

    def has_type(self, type_name: str) -> bool:
        return normalize_type(type_name) in self.types

    def has_field(self, type_name: str, field_name: str) -> bool:
        return field_name in self.fields.get(normalize_type(type_name), set())


def type_at(types: list[str], index: int) -> str:
    return types[index] if 0 <= index < len(types) else f"<invalid-type:{index}>"


def read_method_ref(
    reader: Reader,
    types: list[str],
    issues: list[Issue],
    where: str,
) -> MethodRef:
    flag = reader.u8(f"{where} generic flag")
    if flag not in (0, 1):
        issues.append(Issue("error", "BOOL_ENCODING", where, f"generic flag is {flag}"))
    declaring_index = reader.i32(f"{where} declaring type")
    if not 0 <= declaring_index < len(types):
        issues.append(Issue(
            "error", "TYPE_REF_RANGE", where,
            f"declaring type index {declaring_index} outside [0, {len(types)})",
        ))
    name = reader.string(f"{where} method name")
    generic_indices: list[int] = []
    generic_arguments: list[str] = []
    parameter_indices: list[int | None] = []
    parameters: list[str] = []
    if flag:
        count = reader.count(f"{where} generic argument count", 65_535)
        for item in range(count):
            type_index = reader.i32(f"{where} generic argument {item}")
            generic_indices.append(type_index)
            generic_arguments.append(type_at(types, type_index))
            if not 0 <= type_index < len(types):
                issues.append(Issue(
                    "error", "TYPE_REF_RANGE", where,
                    f"generic argument {item} type index {type_index} is invalid",
                ))
        count = reader.count(f"{where} parameter count", 65_535)
        for item in range(count):
            generic_flag = reader.u8(f"{where} parameter {item} generic flag")
            if generic_flag not in (0, 1):
                issues.append(Issue(
                    "error", "BOOL_ENCODING", where,
                    f"parameter {item} generic flag is {generic_flag}",
                ))
            if generic_flag:
                parameter_indices.append(None)
                parameters.append(reader.string(f"{where} parameter {item} generic name"))
            else:
                type_index = reader.i32(f"{where} parameter {item} type")
                parameter_indices.append(type_index)
                parameters.append(type_at(types, type_index))
                if not 0 <= type_index < len(types):
                    issues.append(Issue(
                        "error", "TYPE_REF_RANGE", where,
                        f"parameter {item} type index {type_index} is invalid",
                    ))
    else:
        count = reader.count(f"{where} parameter count", 65_535)
        for item in range(count):
            type_index = reader.i32(f"{where} parameter {item} type")
            parameter_indices.append(type_index)
            parameters.append(type_at(types, type_index))
            if not 0 <= type_index < len(types):
                issues.append(Issue(
                    "error", "TYPE_REF_RANGE", where,
                    f"parameter {item} type index {type_index} is invalid",
                ))
    return MethodRef(
        declaring_type_index=declaring_index,
        declaring_type=type_at(types, declaring_index),
        name=name,
        generic_instance=bool(flag),
        generic_argument_indices=generic_indices,
        generic_arguments=generic_arguments,
        parameter_type_indices=parameter_indices,
        parameters=parameters,
    )


def parse_patch(
    path: Path,
    dump_path: Path | None,
    dialect: str,
) -> tuple[dict[str, object], DumpIndex, list[Issue]]:
    data = path.read_bytes()
    if not data:
        raise PatchError("patch is empty")
    reader = Reader(data)
    issues: list[Issue] = []
    magic = reader.u64("magic")
    bridge = reader.string("interface bridge")
    type_count = reader.count("external type count", 1_000_000)
    types = [reader.string(f"external type {i}") for i in range(type_count)]
    dump_index = DumpIndex.load(dump_path, types)

    method_count = reader.count("VM method count", 1_000_000)
    methods: list[VmMethod] = []
    for method_id in range(method_count):
        slot_count = reader.count(f"method {method_id} code slot count", 10_000_000)
        slots = [
            (
                reader.i32(f"method {method_id} slot {slot} opcode"),
                reader.i32(f"method {method_id} slot {slot} operand"),
            )
            for slot in range(slot_count)
        ]
        exception_count = reader.count(f"method {method_id} exception count", 1_000_000)
        exceptions = [
            ExceptionRecord(
                reader.i32(f"method {method_id} exception {item} type"),
                reader.i32(f"method {method_id} exception {item} catch type"),
                reader.i32(f"method {method_id} exception {item} try start"),
                reader.i32(f"method {method_id} exception {item} try end"),
                reader.i32(f"method {method_id} exception {item} handler start"),
                reader.i32(f"method {method_id} exception {item} handler end"),
            )
            for item in range(exception_count)
        ]
        methods.append(VmMethod(method_id, slots, exceptions))

    external_method_count = reader.count("external method count", 1_000_000)
    external_methods = [
        read_method_ref(reader, types, issues, f"external method {item}")
        for item in range(external_method_count)
    ]
    string_count = reader.count("interned string count", 1_000_000)
    strings = [reader.string(f"interned string {item}") for item in range(string_count)]

    field_count = reader.count("field count", 1_000_000)
    fields: list[dict[str, object]] = []
    for item in range(field_count):
        where = f"field {item}"
        new_flag = reader.u8(f"{where} new flag")
        if new_flag not in (0, 1):
            issues.append(Issue("error", "BOOL_ENCODING", where, f"new flag is {new_flag}"))
        declaring_index = reader.i32(f"{where} declaring type")
        if not 0 <= declaring_index < len(types):
            issues.append(Issue(
                "error", "TYPE_REF_RANGE", where,
                f"declaring type index {declaring_index} is invalid",
            ))
        record: dict[str, object] = {
            "new": bool(new_flag),
            "declaring_type_index": declaring_index,
            "declaring_type": type_at(types, declaring_index),
            "name": reader.string(f"{where} name"),
        }
        if new_flag:
            field_type = reader.i32(f"{where} type")
            constructor = reader.i32(f"{where} constructor")
            record.update({
                "field_type_index": field_type,
                "field_type": type_at(types, field_type),
                "constructor_method_id": constructor,
            })
            if not 0 <= field_type < len(types):
                issues.append(Issue(
                    "error", "TYPE_REF_RANGE", where,
                    f"field type index {field_type} is invalid",
                ))
        fields.append(record)

    static_count = reader.count("static field count", 1_000_000)
    static_fields: list[dict[str, int | str]] = []
    for item in range(static_count):
        type_index = reader.i32(f"static field {item} type")
        cctor = reader.i32(f"static field {item} cctor")
        if not 0 <= type_index < len(types):
            issues.append(Issue(
                "error", "TYPE_REF_RANGE", f"static field {item}",
                f"type index {type_index} is invalid",
            ))
        static_fields.append({
            "type_index": type_index,
            "type": type_at(types, type_index),
            "cctor_method_id": cctor,
        })

    anonymous_count = reader.count("anonymous type count", 1_000_000)
    anonymous_types: list[dict[str, object]] = []
    for item in range(anonymous_count):
        where = f"anonymous type {item}"
        anonymous_field_count = reader.count(f"{where} field count", 1_000_000)
        field_types = [reader.i32(f"{where} field {i} kind") for i in range(anonymous_field_count)]
        ctor_id = reader.i32(f"{where} constructor")
        ctor_params = reader.count(f"{where} constructor parameter count", 65_535)
        interface_count = reader.count(f"{where} interface count", 65_535)
        interfaces: list[dict[str, object]] = []
        for interface_index in range(interface_count):
            type_index = reader.i32(f"{where} interface {interface_index} type")
            interface_type = type_at(types, type_index)
            if not 0 <= type_index < len(types):
                raise PatchError(f"{where} interface type index {type_index} is invalid")
            declared_count = dump_index.declared_method_count(interface_type)
            if declared_count is None:
                raise PatchError(
                    f"{where} needs the declared method count for interface "
                    f"{interface_type!r}; provide a matching --dump"
                )
            slots = [
                reader.i32(f"{where} interface {interface_index} method slot {slot}")
                for slot in range(declared_count)
            ]
            interfaces.append({
                "type_index": type_index,
                "type": interface_type,
                "method_ids": slots,
            })
        vtable_count = reader.count(f"{where} vtable count", 1_000_000)
        vtable = [reader.i32(f"{where} vtable slot {slot}") for slot in range(vtable_count)]
        anonymous_types.append({
            "field_types": field_types,
            "constructor_method_id": ctor_id,
            "constructor_parameter_count": ctor_params,
            "interfaces": interfaces,
            "vtable": vtable,
        })

    wrapper_manager = reader.string("wrapper manager")
    assembly_suffix = reader.string("ID map assembly suffix")
    if dialect == "target":
        redirect_flag = reader.u8("target redirect table flag")
        if redirect_flag not in (0, 1):
            issues.append(Issue(
                "error", "BOOL_ENCODING", "redirect table",
                f"target flag is {redirect_flag}",
            ))
    else:
        redirect_flag = None
    redirect_count = reader.count("redirect count", 1_000_000)
    redirects: list[dict[str, object]] = []
    for item in range(redirect_count):
        method_ref = read_method_ref(reader, types, issues, f"redirect {item}")
        vm_method_id = reader.i32(f"redirect {item} VM method id")
        redirects.append({"method": method_ref, "vm_method_id": vm_method_id})
    new_class_count = reader.count("new class count", 1_000_000)
    new_classes = [reader.string(f"new class {item}") for item in range(new_class_count)]
    if reader.offset != len(data):
        issues.append(Issue(
            "error", "TRAILING_BYTES", "patch tail",
            f"{len(data) - reader.offset} unparsed byte(s) at 0x{reader.offset:X}",
        ))

    patch: dict[str, object] = {
        "path": str(path),
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "magic": magic,
        "interface_bridge": bridge,
        "external_types": types,
        "methods": methods,
        "external_methods": external_methods,
        "strings": strings,
        "fields": fields,
        "static_fields": static_fields,
        "anonymous_types": anonymous_types,
        "wrapper_manager": wrapper_manager,
        "assembly_suffix": assembly_suffix,
        "redirect_table_flag": redirect_flag,
        "redirects": redirects,
        "new_classes": new_classes,
        "parsed_bytes": reader.offset,
    }
    return patch, dump_index, issues


class Verifier:
    def __init__(self, patch: dict[str, object], dump_index: DumpIndex) -> None:
        self.patch = patch
        self.dump_index = dump_index
        self.issues: list[Issue] = []
        self.external_return: dict[int, int | None] = {}
        self.external_static: dict[int, bool | None] = {}
        self.vm_argument_counts: dict[int, set[int]] = {}

    @property
    def methods(self) -> list[VmMethod]:
        return self.patch["methods"]  # type: ignore[return-value]

    def add(self, severity: str, code: str, where: str, message: str) -> None:
        self.issues.append(Issue(severity, code, where, message))

    def verify(self) -> None:
        self._verify_header()
        for method in self.methods:
            self._decode_method(method)
        self._verify_dump_symbols()
        self._resolve_method_signatures()
        self._verify_global_records()
        for method in self.methods:
            self._verify_method_structure(method)
        for method in self.methods:
            self._verify_stack(method)

    def _verify_header(self) -> None:
        magic = self.patch["magic"]
        if magic != TARGET_MAGIC:
            self.add(
                "error", "MAGIC_MISMATCH", "header",
                f"expected 0x{TARGET_MAGIC:016X}, got 0x{int(magic):016X}",
            )
        if not str(self.patch["interface_bridge"]).startswith("IFix.ILFixInterfaceBridge,"):
            self.add("error", "BRIDGE_NAME", "header", "unexpected interface bridge type")
        if not str(self.patch["wrapper_manager"]).startswith("IFix.WrappersManagerImpl,"):
            self.add("error", "WRAPPER_NAME", "patch tail", "unexpected wrapper manager type")

    def _decode_method(self, method: VmMethod) -> None:
        if not method.slots:
            return
        index = 0
        while index < len(method.slots):
            opcode, operand = method.slots[index]
            if not 0 <= opcode < len(OPCODE_NAMES):
                self.add(
                    "error", "OPCODE_RANGE", f"method {method.method_id} slot {index}",
                    f"opcode {opcode} outside [0, {len(OPCODE_NAMES)})",
                )
                method.executable.append(index)
                method.next_slot[index] = index + 1
                index += 1
                continue
            name = OPCODE_NAMES[opcode]
            method.executable.append(index)
            payload_count = LITERAL_PAYLOADS.get(name, 0)
            if name == "Switch":
                if operand < 0:
                    self.add(
                        "error", "SWITCH_COUNT", f"method {method.method_id} slot {index}",
                        f"negative switch case count {operand}",
                    )
                    operand = 0
                payload_count = (operand + 1) // 2
            end = index + 1 + payload_count
            if end > len(method.slots):
                self.add(
                    "error", "PAYLOAD_TRUNCATED", f"method {method.method_id} slot {index}",
                    f"{name} needs {payload_count} payload slot(s)",
                )
                end = len(method.slots)
            for payload_slot in range(index + 1, end):
                method.data_slots.add(payload_slot)
            method.next_slot[index] = end
            if name == "Switch" and payload_count and end == index + 1 + payload_count:
                offsets: list[int] = []
                for payload_slot in range(index + 1, end):
                    low, high = method.slots[payload_slot]
                    offsets.extend((low, high))
                method.switch_targets[index] = [index + offset for offset in offsets[:operand]]
            elif name == "Switch":
                method.switch_targets[index] = []
            index = end

        first_opcode = method.slots[0][0]
        first_name = OPCODE_NAMES[first_opcode] if 0 <= first_opcode < len(OPCODE_NAMES) else None
        if first_name != "StackSpace":
            self.add(
                "error", "STACKSPACE_MISSING", f"method {method.method_id}",
                "first code slot is not StackSpace",
            )
        else:
            operand = method.slots[0][1]
            if operand < 0:
                self.add(
                    "error", "STACKSPACE_ENCODING", f"method {method.method_id} slot 0",
                    f"negative StackSpace operand {operand}",
                )
            method.locals_count = (operand & 0xFFFFFFFF) >> 16
            method.declared_max_stack = operand & 0xFFFF
        for slot in method.executable[1:]:
            opcode = method.slots[slot][0]
            if 0 <= opcode < len(OPCODE_NAMES) and OPCODE_NAMES[opcode] == "StackSpace":
                self.add(
                    "error", "STACKSPACE_POSITION", f"method {method.method_id} slot {slot}",
                    "StackSpace is only valid at slot 0",
                )
        returns = {
            operand for slot, (opcode, operand) in enumerate(method.slots)
            if slot in method.executable and 0 <= opcode < len(OPCODE_NAMES)
            and OPCODE_NAMES[opcode] == "Ret"
        }
        if any(value not in (0, 1) for value in returns):
            self.add(
                "error", "RET_OPERAND", f"method {method.method_id}",
                f"Ret operands must be 0 or 1, found {sorted(returns)}",
            )
        valid_returns = {value for value in returns if value in (0, 1)}
        if len(valid_returns) > 1:
            self.add(
                "error", "RET_ARITY_MIXED", f"method {method.method_id}",
                f"mixed Ret arities {sorted(valid_returns)}",
            )
        elif valid_returns:
            method.return_arity = next(iter(valid_returns))

    def _resolve_method_signatures(self) -> None:
        external_methods: list[MethodRef] = self.patch["external_methods"]  # type: ignore[assignment]
        for index, method_ref in enumerate(external_methods):
            candidates = self.dump_index.lookup(method_ref)
            arities = {item.return_arity for item in candidates}
            static_values = {item.is_static for item in candidates}
            if len(arities) == 1:
                self.external_return[index] = next(iter(arities))
            elif method_ref.name in (".ctor", ".cctor"):
                self.external_return[index] = 0
            else:
                self.external_return[index] = None
                self.add(
                    "warning", "DUMP_METHOD_UNRESOLVED", f"external method {index}",
                    f"dump.cs did not uniquely resolve {method_ref.declaring_type}.{method_ref.name}/"
                    f"{len(method_ref.parameters)}",
                )
            self.external_static[index] = next(iter(static_values)) if len(static_values) == 1 else None

    def _verify_dump_symbols(self) -> None:
        if not self.dump_index.loaded:
            return
        external_types: list[str] = self.patch["external_types"]  # type: ignore[assignment]
        for index, type_name in enumerate(external_types):
            if (leading_aqn_assembly(type_name) == "Assembly-CSharp"
                    and not self.dump_index.has_type(type_name)):
                self.add(
                    "error", "DUMP_TYPE_MISSING", f"external type {index}",
                    f"target dump does not declare {normalize_type(type_name)}",
                )

        fields: list[dict[str, object]] = self.patch["fields"]  # type: ignore[assignment]
        for index, record in enumerate(fields):
            if record.get("new"):
                continue
            declaring_type = str(record["declaring_type"])
            field_name = str(record["name"])
            if (leading_aqn_assembly(declaring_type) == "Assembly-CSharp"
                    and not self.dump_index.has_field(declaring_type, field_name)):
                self.add(
                    "error", "DUMP_FIELD_MISSING", f"field {index}",
                    f"target dump does not declare {normalize_type(declaring_type)}.{field_name}",
                )

    def _valid_vm_id(self, value: int, where: str, allow_minus_one: bool = False) -> bool:
        if allow_minus_one and value == -1:
            return True
        if not 0 <= value < len(self.methods):
            self.add(
                "error", "VM_METHOD_REF_RANGE", where,
                f"VM method id {value} outside [0, {len(self.methods)})",
            )
            return False
        if not self.methods[value].slots:
            self.add("error", "VM_METHOD_EMPTY", where, f"VM method {value} has no code")
            return False
        return True

    def _verify_global_records(self) -> None:
        fields: list[dict[str, object]] = self.patch["fields"]  # type: ignore[assignment]
        for index, record in enumerate(fields):
            if record.get("new"):
                constructor_id = int(record["constructor_method_id"])
                self._valid_vm_id(
                    constructor_id,
                    f"field {index} constructor",
                    allow_minus_one=True,
                )
                if constructor_id >= 0:
                    self.vm_argument_counts.setdefault(constructor_id, set()).add(0)
        static_fields: list[dict[str, object]] = self.patch["static_fields"]  # type: ignore[assignment]
        for index, record in enumerate(static_fields):
            cctor_id = int(record["cctor_method_id"])
            self._valid_vm_id(
                cctor_id,
                f"static field {index} cctor",
                allow_minus_one=True,
            )
            if cctor_id >= 0:
                self.vm_argument_counts.setdefault(cctor_id, set()).add(0)
        anonymous_types: list[dict[str, object]] = self.patch["anonymous_types"]  # type: ignore[assignment]
        for index, record in enumerate(anonymous_types):
            constructor_id = int(record["constructor_method_id"])
            self._valid_vm_id(constructor_id, f"anonymous type {index} constructor")
            self.vm_argument_counts.setdefault(constructor_id, set()).add(
                int(record["constructor_parameter_count"]) + 1
            )
            for interface_index, interface in enumerate(record["interfaces"]):
                for slot, method_id in enumerate(interface["method_ids"]):
                    self._valid_vm_id(
                        int(method_id), f"anonymous type {index} interface {interface_index} slot {slot}",
                    )
            for slot, method_id in enumerate(record["vtable"]):
                self._valid_vm_id(int(method_id), f"anonymous type {index} vtable slot {slot}")
        redirects: list[dict[str, object]] = self.patch["redirects"]  # type: ignore[assignment]
        seen_redirects: set[tuple[str, str, tuple[str, ...]]] = set()
        for index, redirect in enumerate(redirects):
            vm_id = int(redirect["vm_method_id"])
            self._valid_vm_id(vm_id, f"redirect {index}")
            method_ref: MethodRef = redirect["method"]  # type: ignore[assignment]
            key = (
                method_ref.declaring_type,
                method_ref.name,
                tuple(method_ref.parameters),
            )
            if key in seen_redirects:
                self.add("error", "REDIRECT_DUPLICATE", f"redirect {index}", "duplicate method signature")
            seen_redirects.add(key)
            candidates = self.dump_index.lookup(method_ref)
            arities = {item.return_arity for item in candidates}
            static_values = {item.is_static for item in candidates}
            if len(static_values) == 1:
                argument_count = len(method_ref.parameters) + (
                    0 if next(iter(static_values)) else 1
                )
                self.vm_argument_counts.setdefault(vm_id, set()).add(argument_count)
            if 0 <= vm_id < len(self.methods) and len(arities) == 1:
                expected = next(iter(arities))
                actual = self.methods[vm_id].return_arity
                if actual is not None and actual != expected:
                    self.add(
                        "error", "REDIRECT_RETURN_ARITY", f"redirect {index}",
                        f"dump return arity {expected}, VM method {vm_id} uses Ret {actual}",
                    )
        for caller in self.methods:
            for slot in caller.executable:
                name, operand = self._opcode(caller, slot)
                if name in INTERNAL_CALLS:
                    encoded = operand & 0xFFFFFFFF
                    self.vm_argument_counts.setdefault(encoded & 0xFFFF, set()).add(encoded >> 16)
                elif name == "Callvirtvirt":
                    encoded = operand & 0xFFFFFFFF
                    vtable_slot = encoded & 0xFFFF
                    argument_count = encoded >> 16
                    for record in anonymous_types:
                        vtable: list[int] = record["vtable"]  # type: ignore[assignment]
                        if vtable_slot < len(vtable):
                            self.vm_argument_counts.setdefault(vtable[vtable_slot], set()).add(argument_count)
        for method_id, counts in self.vm_argument_counts.items():
            if 0 <= method_id < len(self.methods) and len(counts) > 1:
                self.add(
                    "error", "VM_ARGUMENT_COUNT_CONFLICT", f"VM method {method_id}",
                    f"call/redirect sites disagree on argument count: {sorted(counts)}",
                )

    def _opcode(self, method: VmMethod, slot: int) -> tuple[str | None, int]:
        opcode, operand = method.slots[slot]
        name = OPCODE_NAMES[opcode] if 0 <= opcode < len(OPCODE_NAMES) else None
        return name, operand

    def _target(self, method: VmMethod, target: int, where: str, allow_end: bool = False) -> bool:
        upper_ok = target <= len(method.slots) if allow_end else target < len(method.slots)
        if target < 0 or not upper_ok:
            bracket = "]" if allow_end else ")"
            self.add(
                "error", "BRANCH_TARGET_RANGE", where,
                f"target {target} outside [0, {len(method.slots)}{bracket}",
            )
            return False
        if allow_end and target == len(method.slots):
            return True
        if target in method.data_slots:
            self.add("error", "TARGET_IN_PAYLOAD", where, f"target {target} is a payload slot")
            return False
        if target not in method.executable:
            self.add("error", "TARGET_NOT_INSTRUCTION", where, f"target {target} is not executable")
            return False
        if target == 0:
            self.add("error", "TARGET_STACKSPACE", where, "control flow targets StackSpace")
            return False
        return True

    def _verify_type_or_anon(self, operand: int, where: str) -> None:
        types: list[str] = self.patch["external_types"]  # type: ignore[assignment]
        anonymous: list[dict[str, object]] = self.patch["anonymous_types"]  # type: ignore[assignment]
        if operand >= 0:
            if operand >= len(types):
                self.add("error", "TYPE_REF_RANGE", where, f"type index {operand} is invalid")
        else:
            anonymous_id = -operand - 1
            if not 0 <= anonymous_id < len(anonymous):
                self.add(
                    "error", "ANON_TYPE_REF_RANGE", where,
                    f"anonymous type id {anonymous_id} is invalid",
                )

    def _verify_method_structure(self, method: VmMethod) -> None:
        if not method.slots:
            return
        types: list[str] = self.patch["external_types"]  # type: ignore[assignment]
        strings: list[str] = self.patch["strings"]  # type: ignore[assignment]
        fields: list[dict[str, object]] = self.patch["fields"]  # type: ignore[assignment]
        static_fields: list[dict[str, object]] = self.patch["static_fields"]  # type: ignore[assignment]
        anonymous: list[dict[str, object]] = self.patch["anonymous_types"]  # type: ignore[assignment]
        external_methods: list[MethodRef] = self.patch["external_methods"]  # type: ignore[assignment]
        executable_set = set(method.executable)
        for slot in method.executable:
            name, operand = self._opcode(method, slot)
            if name is None:
                continue
            where = f"method {method.method_id} slot {slot} ({name})"
            if name in UNSUPPORTED_BY_VM_SOURCE:
                self.add("error", "VM_OPCODE_UNSUPPORTED", where, "no dispatch case in VirtualMachine.cs")
            if name in REL_BRANCHES:
                self._target(method, slot + operand, where)
            elif name == "Switch":
                for case, target in enumerate(method.switch_targets.get(slot, [])):
                    self._target(method, target, f"{where} case {case}")
                self._target(method, method.next_slot[slot], f"{where} fallthrough")
            elif name == "Leave":
                self._target(method, operand, f"{where} continuation")
                if method.next_slot[slot] >= len(method.slots):
                    self.add("error", "LEAVE_TRUNCATED", where, "missing synthetic branch after Leave")
            if name in DIRECT_TYPE_REFS and not 0 <= operand < len(types):
                self.add("error", "TYPE_REF_RANGE", where, f"type index {operand} is invalid")
            elif name in TYPE_OR_ANON_REFS:
                self._verify_type_or_anon(operand, where)
            elif name == "Ldstr" and not 0 <= operand < len(strings):
                self.add("error", "STRING_REF_RANGE", where, f"string index {operand} is invalid")
            elif name in INSTANCE_FIELD_REFS:
                field_id = operand if operand >= 0 else -operand - 1
                limit = len(fields) if operand >= 0 else max(
                    (len(item["field_types"]) for item in anonymous), default=0
                )
                if not 0 <= field_id < limit:
                    self.add("error", "FIELD_REF_RANGE", where, f"field index {operand} is invalid")
            elif name in STATIC_FIELD_REFS:
                field_id = operand if operand >= 0 else -operand - 1
                limit = len(fields) if operand >= 0 else len(static_fields)
                if not 0 <= field_id < limit:
                    self.add("error", "FIELD_REF_RANGE", where, f"static field index {operand} is invalid")
            elif name in INTERNAL_CALLS:
                encoded = operand & 0xFFFFFFFF
                method_id = encoded & 0xFFFF
                self._valid_vm_id(method_id, where)
            elif name in EXTERNAL_CALLS:
                encoded = operand & 0xFFFFFFFF
                method_id = encoded & 0xFFFF
                if not 0 <= method_id < len(external_methods):
                    self.add(
                        "error", "EXTERNAL_METHOD_REF_RANGE", where,
                        f"external method index {method_id} is invalid",
                    )
                elif self.external_static.get(method_id) is not None:
                    formal = len(external_methods[method_id].parameters)
                    is_static = bool(self.external_static[method_id])
                    expected = formal if name == "Newobj" or is_static else formal + 1
                    actual = encoded >> 16
                    if actual != expected:
                        self.add(
                            "error", "CALL_ARGUMENT_COUNT", where,
                            f"encoded argument count {actual}, dump signature expects {expected}",
                        )
            elif name in EXTERNAL_METHOD_REFS:
                if not 0 <= operand < len(external_methods):
                    self.add(
                        "error", "EXTERNAL_METHOD_REF_RANGE", where,
                        f"external method index {operand} is invalid",
                    )
            elif name == "Newanon" and not 0 <= operand < len(anonymous):
                self.add("error", "ANON_TYPE_REF_RANGE", where, f"anonymous type id {operand} is invalid")
            elif name in VTABLE_REFS:
                slot_id = (operand & 0xFFFF) if name == "Callvirtvirt" else operand
                if slot_id < 0 or not anonymous or all(
                    slot_id >= len(item["vtable"]) for item in anonymous
                ):
                    self.add("error", "VTABLE_REF_RANGE", where, f"vtable slot {slot_id} is invalid")
            if name in {"Ldloc", "Ldloca", "Stloc"}:
                if method.locals_count is not None and not 0 <= operand < method.locals_count:
                    self.add(
                        "error", "LOCAL_REF_RANGE", where,
                        f"local index {operand} outside [0, {method.locals_count})",
                    )
            if name in {"Ldarg", "Ldarga", "Starg"} and operand < 0:
                self.add("error", "ARG_REF_RANGE", where, f"negative argument index {operand}")
            elif name in {"Ldarg", "Ldarga", "Starg"}:
                argument_counts = self.vm_argument_counts.get(method.method_id, set())
                if len(argument_counts) == 1:
                    argument_count = next(iter(argument_counts))
                    if operand >= argument_count:
                        self.add(
                            "error", "ARG_REF_RANGE", where,
                            f"argument index {operand} outside [0, {argument_count})",
                        )
            if name == "Constrained":
                previous = max((value for value in method.executable if value < slot), default=-1)
                previous_name, previous_operand = self._opcode(method, previous) if previous >= 0 else (None, 0)
                if previous_name != "Nop" or previous_operand < 0:
                    self.add(
                        "error", "CONSTRAINED_PREFIX", where,
                        "Constrained must follow the translator's Nop(parameter-count) prefix",
                    )

        for exception_index, record in enumerate(method.exceptions):
            where = f"method {method.method_id} exception {exception_index}"
            if record.handler_type not in (0, 1, 2, 4):
                self.add("error", "EH_TYPE", where, f"invalid handler type {record.handler_type}")
            if record.handler_type == 0:
                if record.catch_type_id != -1 and not 0 <= record.catch_type_id < len(types):
                    self.add(
                        "error", "TYPE_REF_RANGE", where,
                        f"catch type index {record.catch_type_id} is invalid",
                    )
            elif record.catch_type_id != -1:
                self.add(
                    "warning", "EH_CATCH_TYPE_UNUSED", where,
                    f"non-catch handler carries catch type {record.catch_type_id}",
                )
            if record.try_start >= record.try_end:
                self.add(
                    "error", "EH_TRY_RANGE", where,
                    f"empty/reversed try range [{record.try_start}, {record.try_end})",
                )
            self._target(method, record.try_start, f"{where} try start")
            self._target(method, record.try_end, f"{where} try end", allow_end=True)
            self._target(method, record.handler_start, f"{where} handler start")
            if record.handler_end != -1:
                self._target(method, record.handler_end, f"{where} handler end", allow_end=True)
                if record.handler_end <= record.handler_start:
                    self.add(
                        "error", "EH_HANDLER_RANGE", where,
                        f"empty/reversed handler range [{record.handler_start}, {record.handler_end})",
                    )
        for slot in method.executable:
            name, operand = self._opcode(method, slot)
            if name == "Endfinally" and not (
                operand == -1 or 0 <= operand < len(method.exceptions)
            ):
                self.add(
                    "error", "EH_REF_RANGE", f"method {method.method_id} slot {slot} (Endfinally)",
                    f"exception handler index {operand} is invalid",
                )
        if 0 not in executable_set:
            self.add("error", "METHOD_LAYOUT", f"method {method.method_id}", "slot 0 is not executable")

    def _vtable_return(self, slot_id: int) -> int | None:
        anonymous: list[dict[str, object]] = self.patch["anonymous_types"]  # type: ignore[assignment]
        returns: set[int] = set()
        for record in anonymous:
            vtable: list[int] = record["vtable"]  # type: ignore[assignment]
            if slot_id < len(vtable) and 0 <= vtable[slot_id] < len(self.methods):
                arity = self.methods[vtable[slot_id]].return_arity
                if arity is not None:
                    returns.add(arity)
        return next(iter(returns)) if len(returns) == 1 else None

    def _effect(self, method: VmMethod, slot: int) -> tuple[int, int] | None:
        name, operand = self._opcode(method, slot)
        if name is None:
            return None
        if name in PUSH_ONE:
            return 0, 1
        if name in UNARY_SAME:
            return 1, 1
        if name in BINARY_TO_ONE:
            return 2, 1
        if name in POP_ONE:
            return 1, 0
        if name in POP_TWO:
            return 2, 0
        if name in ARRAY_LOADS:
            return 2, 1
        if name in ARRAY_STORES:
            return 3, 0
        if name in COND_ONE_BRANCHES:
            return 1, 0
        if name in COND_TWO_BRANCHES:
            return 2, 0
        if name in NO_STACK_CHANGE or name == "StackSpace":
            return 0, 0
        if name == "Dup":
            return 1, 2
        if name == "Switch":
            # CodeTranslator emits CLR switch semantics. The checked-in old VM source
            # omits this pop, but accepting that leak masks invalid joins/maxstack.
            return 1, 0
        if name in INTERNAL_CALLS:
            encoded = operand & 0xFFFFFFFF
            args = encoded >> 16
            target = encoded & 0xFFFF
            if 0 <= target < len(self.methods) and self.methods[target].return_arity is not None:
                return args, int(self.methods[target].return_arity)
            return None
        if name in EXTERNAL_CALLS:
            encoded = operand & 0xFFFFFFFF
            args = encoded >> 16
            target = encoded & 0xFFFF
            if name == "Newobj":
                return args, 1
            return_arity = self.external_return.get(target)
            return (args, return_arity) if return_arity is not None else None
        if name == "Callvirtvirt":
            encoded = operand & 0xFFFFFFFF
            args = encoded >> 16
            return_arity = self._vtable_return(encoded & 0xFFFF)
            return (args, return_arity) if return_arity is not None else None
        if name == "Ldvirtftn":
            return 1, 1
        if name == "Ldvirtftn2":
            return 2, 2
        if name == "Newanon":
            anonymous: list[dict[str, object]] = self.patch["anonymous_types"]  # type: ignore[assignment]
            if 0 <= operand < len(anonymous):
                count = int(anonymous[operand]["constructor_parameter_count"])
                return count, 1
            return None
        if name == "Throw":
            return 1, 0
        if name == "Rethrow":
            return 0, 0
        if name == "Ret":
            return 0, 0
        if name == "Endfinally":
            return 0, 0
        if name in {"Cpblk", "Initblk"}:
            return 3, 0
        return None

    def _successors(self, method: VmMethod, slot: int) -> list[int]:
        name, operand = self._opcode(method, slot)
        if name is None:
            return []
        next_slot = method.next_slot.get(slot, slot + 1)
        if name == "Br":
            return [slot + operand]
        if name in COND_ONE_BRANCHES or name in COND_TWO_BRANCHES:
            return [slot + operand, next_slot]
        if name == "Switch":
            return method.switch_targets.get(slot, []) + [next_slot]
        if name in {"Ret", "Throw", "Rethrow", "Endfinally", "Jmp"}:
            return []
        return [next_slot]

    def _verify_stack(self, method: VmMethod) -> None:
        if not method.slots or len(method.executable) < 2:
            return
        entry = method.next_slot.get(0, 1)
        incoming: dict[int, int] = {}
        queue: deque[tuple[int, int, str]] = deque([(entry, 0, "entry")])
        for exception_index, record in enumerate(method.exceptions):
            # The runtime clears the evaluation stack and pushes the exception object.
            queue.append((record.handler_start, 1, f"exception {exception_index}"))
        unresolved = False
        max_depth = 0
        merge_reported: set[int] = set()
        while queue:
            slot, depth, source = queue.popleft()
            if slot not in method.executable or slot == 0:
                continue
            previous = incoming.get(slot)
            if previous is not None:
                if previous != depth and slot not in merge_reported:
                    self.add(
                        "error", "STACK_MERGE", f"method {method.method_id} slot {slot}",
                        f"incoming depths disagree: {previous} vs {depth} ({source})",
                    )
                    merge_reported.add(slot)
                continue
            incoming[slot] = depth
            max_depth = max(max_depth, depth)
            name, operand = self._opcode(method, slot)
            if name == "Ret":
                expected = 1 if operand else 0
                if depth != expected:
                    self.add(
                        "error", "STACK_AT_RET", f"method {method.method_id} slot {slot}",
                        f"depth {depth}, Ret operand requires {expected}",
                    )
                continue
            if name == "Leave" and depth != 0:
                self.add(
                    "error", "STACK_AT_LEAVE", f"method {method.method_id} slot {slot}",
                    f"Leave requires an empty evaluation stack, found depth {depth}",
                )
            effect = self._effect(method, slot)
            if effect is None:
                unresolved = True
                self.add(
                    "warning", "STACK_EFFECT_UNRESOLVED", f"method {method.method_id} slot {slot}",
                    f"could not resolve stack effect for {name}",
                )
                continue
            pops, pushes = effect
            if name == "Constrained":
                previous_slot = max((value for value in method.executable if value < slot), default=-1)
                if previous_slot >= 0:
                    _, previous_operand = self._opcode(method, previous_slot)
                    pops = max(pops, previous_operand + 1)
                    pushes = pops
            if depth < pops:
                self.add(
                    "error", "STACK_UNDERFLOW", f"method {method.method_id} slot {slot}",
                    f"{name} needs {pops} value(s), depth is {depth}",
                )
                continue
            outgoing = depth - pops + pushes
            max_depth = max(max_depth, outgoing)
            for successor in self._successors(method, slot):
                if successor == len(method.slots):
                    self.add(
                        "error", "CONTROL_FALLTHROUGH", f"method {method.method_id} slot {slot}",
                        "reachable control flow falls past the code array",
                    )
                elif successor in method.executable and successor != 0:
                    queue.append((successor, outgoing, f"slot {slot}"))
        method.observed_max_stack = max_depth
        method.reachable_slots = len(incoming)
        method.stack_verified = not unresolved
        if method.declared_max_stack is not None and max_depth > method.declared_max_stack:
            self.add(
                "error", "MAXSTACK_EXCEEDED", f"method {method.method_id}",
                f"observed depth {max_depth} exceeds declared maxstack {method.declared_max_stack}",
            )


def method_summary(method: VmMethod) -> dict[str, object]:
    return {
        "method_id": method.method_id,
        "code_slots": len(method.slots),
        "executable_instructions": len(method.executable),
        "payload_slots": len(method.data_slots),
        "exceptions": [
            {
                "handler_type": record.handler_type,
                "catch_type_id": record.catch_type_id,
                "try_start": record.try_start,
                "try_end": record.try_end,
                "handler_start": record.handler_start,
                "handler_end": record.handler_end,
            }
            for record in method.exceptions
        ],
        "locals": method.locals_count,
        "declared_max_stack": method.declared_max_stack,
        "observed_max_stack": method.observed_max_stack,
        "return_arity": method.return_arity,
        "reachable_instructions": method.reachable_slots,
        "stack_verified": method.stack_verified,
    }


def build_report(
    patch: dict[str, object],
    verifier: Verifier,
    parse_issues: list[Issue],
    dump_path: Path | None,
    dialect: str,
) -> dict[str, object]:
    issues = parse_issues + verifier.issues
    errors = [issue for issue in issues if issue.severity == "error"]
    warnings = [issue for issue in issues if issue.severity == "warning"]
    methods: list[VmMethod] = patch["methods"]  # type: ignore[assignment]
    return {
        "valid": not errors,
        "file": patch["path"],
        "size": patch["size"],
        "sha256": patch["sha256"],
        "format": {
            "magic": f"0x{int(patch['magic']):016X}",
            "expected_magic": f"0x{TARGET_MAGIC:016X}",
            "opcode_count": len(OPCODE_NAMES),
            "dialect": TARGET_DIALECT if dialect == "target" else "upstream",
            "redirect_table_flag": patch["redirect_table_flag"],
            "parsed_bytes": patch["parsed_bytes"],
        },
        "counts": {
            "external_types": len(patch["external_types"]),
            "vm_methods": len(methods),
            "external_methods": len(patch["external_methods"]),
            "strings": len(patch["strings"]),
            "fields": len(patch["fields"]),
            "static_fields": len(patch["static_fields"]),
            "anonymous_types": len(patch["anonymous_types"]),
            "redirects": len(patch["redirects"]),
            "new_classes": len(patch["new_classes"]),
        },
        "dump": str(dump_path) if dump_path is not None else None,
        "methods": [method_summary(method) for method in methods],
        "errors": [issue.as_dict() for issue in errors],
        "warnings": [issue.as_dict() for issue in warnings],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("patch", type=Path, help="IFix patch bytes")
    parser.add_argument(
        "--dump",
        type=Path,
        default=Path("dump.cs"),
        help="Il2CppDumper dump used to resolve external return/static signatures",
    )
    parser.add_argument(
        "--dialect",
        choices=("target", "upstream"),
        default="target",
        help="target includes the one-byte redirect-table flag",
    )
    parser.add_argument("--json", type=Path, help="write the full verification report")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    dump_path: Path | None = args.dump
    if dump_path is not None and not dump_path.is_file():
        print(f"error: dump file not found: {dump_path}", file=sys.stderr)
        return 2
    try:
        patch, dump_index, parse_issues = parse_patch(args.patch, dump_path, args.dialect)
        verifier = Verifier(patch, dump_index)
        verifier.verify()
        report = build_report(patch, verifier, parse_issues, dump_path, args.dialect)
    except (OSError, PatchError) as exc:
        report = {
            "valid": False,
            "file": str(args.patch),
            "errors": [{
                "severity": "error",
                "code": "PARSE_ERROR",
                "where": "patch",
                "message": str(exc),
            }],
            "warnings": [],
        }
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0 if report.get("valid") else 1


if __name__ == "__main__":
    raise SystemExit(main())
