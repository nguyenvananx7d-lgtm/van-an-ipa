#!/usr/bin/env python3
"""Discover game bindings from a dump and generate version-specific patch sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass, field
from pathlib import Path


BASE_MATCH = "COW.GamePlay.EMKJHAJNPDH"
BASE_MATCH_METHOD = "GEPFGOHGOJI"
BASE_AIM_INFO = "COW.GamePlay.GMPGMPFNMFP"
BASE_AIM_TYPE = "COW.GamePlay.JKCLPFEFMNG"
BASE_SPEED_TYPE = "COW.GamePlay.PlayerAttributes+BDACINNPFDD"

TYPE_RE = re.compile(
    r"^(?:public|private|protected|internal)\s+"
    r"(?:(?:abstract|sealed|static|partial|unsafe|readonly|ref|new)\s+)*"
    r"(class|struct|interface|enum)\s+([^\s:{]+)"
)
ENUM_VALUE_RE = re.compile(
    r"^(?:public|private|protected|internal)\s+const\s+\S+\s+"
    r"([^\s=;]+)\s*=\s*([^;]+);"
)
OFFSET_RE = re.compile(r"//\s*0x([0-9a-fA-F]+)\s*$")
PLACEHOLDER_RE = re.compile(r"\{\{([A-Z0-9_]+)\}\}")


@dataclass
class FieldDecl:
    name: str
    type_name: str
    offset: int | None
    is_static: bool
    line: int


@dataclass
class MethodDecl:
    name: str
    return_type: str
    parameter_types: list[str]
    is_static: bool
    line: int


@dataclass
class TypeDecl:
    full_name: str
    kind: str
    fields: list[FieldDecl] = field(default_factory=list)
    methods: list[MethodDecl] = field(default_factory=list)
    constants: dict[str, str] = field(default_factory=dict)


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


def declaration_name(namespace: str, raw_name: str) -> str:
    raw_name = raw_name.replace("/", ".").replace("+", ".")
    if namespace:
        return f"{namespace}.{raw_name}"
    if raw_name.startswith(("Player.", "PlayerAttributes.")):
        return f"COW.GamePlay.{raw_name}"
    return raw_name


def normalize_type(value: str) -> str:
    value = value.strip().replace("/", ".").replace("+", ".")
    value = re.sub(r"^(?:ref|out|in|params)\s+", "", value)
    return value.rstrip("&*").strip()


def qualify_gameplay(value: str) -> str:
    value = normalize_type(value)
    if value.startswith("PlayerAttributes."):
        return f"COW.GamePlay.{value}"
    if "." not in value and "<" not in value:
        return f"COW.GamePlay.{value}"
    return value


def short_name(value: str) -> str:
    return normalize_type(value).rsplit(".", 1)[-1]


def type_kind(value: str) -> str:
    value = normalize_type(value)
    aliases = {
        "bool": "Boolean",
        "System.Boolean": "Boolean",
        "int": "Int32",
        "System.Int32": "Int32",
        "short": "Int16",
        "System.Int16": "Int16",
        "float": "Single",
        "System.Single": "Single",
        "Vector2": "Vector2",
        "UnityEngine.Vector2": "Vector2",
        "Vector3": "Vector3",
        "UnityEngine.Vector3": "Vector3",
        "GameObject": "GameObject",
        "UnityEngine.GameObject": "GameObject",
        "Collider": "Collider",
        "UnityEngine.Collider": "Collider",
        "PhysicMaterial": "PhysicMaterial",
        "UnityEngine.PhysicMaterial": "PhysicMaterial",
    }
    return aliases.get(value, value)


def parse_parameter_type(value: str) -> str:
    value = value.partition("=")[0].strip()
    value = re.sub(r"^(?:ref|out|in|params)\s+", "", value)
    depth = 0
    split_at = -1
    for index, char in enumerate(value):
        if char in "<[":
            depth += 1
        elif char in ">]":
            depth = max(0, depth - 1)
        elif char.isspace() and depth == 0:
            split_at = index
    type_part = value[:split_at].strip() if split_at >= 0 else value
    return normalize_type(type_part)


def parse_field_line(line: str, line_number: int) -> FieldDecl | None:
    stripped = line.strip()
    if not re.match(r"^(?:public|private|protected|internal)\b", stripped):
        return None
    declaration = stripped.partition("//")[0].strip()
    if not declaration.endswith(";") or "(" in declaration or "=" in declaration:
        return None
    tokens = declaration[:-1].split()
    modifiers = {
        "public", "private", "protected", "internal", "static", "readonly",
        "const", "volatile", "new", "unsafe",
    }
    is_static = "static" in tokens or "const" in tokens
    tokens = [token for token in tokens if token not in modifiers]
    if len(tokens) < 2:
        return None
    offset_match = OFFSET_RE.search(stripped)
    offset = int(offset_match.group(1), 16) if offset_match else None
    return FieldDecl(tokens[-1], normalize_type(tokens[-2]), offset, is_static, line_number)


def parse_method_line(line: str, line_number: int) -> MethodDecl | None:
    stripped = line.strip()
    if not re.match(r"^(?:public|private|protected|internal)\b", stripped):
        return None
    signature = stripped.partition("//")[0].strip()
    open_paren = signature.find("(")
    close_paren = signature.rfind(")")
    if open_paren < 0 or close_paren < open_paren:
        return None
    left = signature[:open_paren].strip()
    if " " not in left:
        return None
    prefix, name = left.rsplit(None, 1)
    tokens = prefix.split()
    if len(tokens) < 2:
        return None
    parameters = [
        parse_parameter_type(item)
        for item in split_parameters(signature[open_paren + 1:close_paren])
    ]
    return MethodDecl(
        name=name,
        return_type=normalize_type(tokens[-1]),
        parameter_types=parameters,
        is_static="static" in tokens,
        line=line_number,
    )


def parse_dump(
    path: Path,
    wanted_types: set[str],
    collect_enums: bool = False,
) -> dict[str, TypeDecl]:
    result: dict[str, TypeDecl] = {}
    namespace = ""
    current: TypeDecl | None = None
    section = ""
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        for line_number, line in enumerate(stream, 1):
            stripped = line.strip()
            if stripped.startswith("// Namespace:"):
                namespace = stripped.partition(":")[2].strip()
                current = None
                section = ""
                continue
            match = TYPE_RE.match(stripped)
            if match:
                kind, raw_name = match.groups()
                full_name = declaration_name(namespace, raw_name)
                keep = full_name in wanted_types or (collect_enums and kind == "enum")
                current = TypeDecl(full_name, kind) if keep else None
                if current is not None:
                    result[full_name] = current
                section = ""
                continue
            if current is None:
                continue
            if stripped == "// Fields":
                section = "fields"
                continue
            if stripped == "// Methods":
                section = "methods"
                continue
            if section == "fields":
                enum_match = ENUM_VALUE_RE.match(stripped)
                if enum_match:
                    current.constants[enum_match.group(1)] = enum_match.group(2).strip()
                    continue
                parsed_field = parse_field_line(stripped, line_number)
                if parsed_field is not None:
                    current.fields.append(parsed_field)
            elif section == "methods":
                parsed_method = parse_method_line(stripped, line_number)
                if parsed_method is not None:
                    current.methods.append(parsed_method)
    return result


def require_type(types: dict[str, TypeDecl], full_name: str) -> TypeDecl:
    try:
        return types[full_name]
    except KeyError as exc:
        raise ValueError(f"dump does not declare required type {full_name}") from exc


def require_method(type_decl: TypeDecl, name: str, parameter_count: int) -> MethodDecl:
    matches = [
        method for method in type_decl.methods
        if method.name == name and len(method.parameter_types) == parameter_count
    ]
    if len(matches) != 1:
        raise ValueError(
            f"expected one {type_decl.full_name}.{name}/{parameter_count}, found {len(matches)}"
        )
    return matches[0]


def find_sequence(fields: list[FieldDecl], kinds: list[str]) -> list[FieldDecl]:
    instance = [item for item in fields if not item.is_static]
    matches: list[list[FieldDecl]] = []
    for index in range(len(instance) - len(kinds) + 1):
        candidate = instance[index:index + len(kinds)]
        if [type_kind(item.type_name) for item in candidate] == kinds:
            matches.append(candidate)
    if len(matches) != 1:
        raise ValueError(f"expected one field layout {kinds}, found {len(matches)}")
    return matches[0]


def is_player_container(return_type: str, container: str) -> bool:
    compact = normalize_type(return_type).replace(" ", "")
    return bool(re.search(
        rf"(?:System\.Collections\.Generic\.)?{container}<"
        rf"(?:COW\.GamePlay\.)?Player>",
        compact,
    ))


def discover_bindings(dump_path: Path) -> tuple[dict[str, str], list[list[str]], dict]:
    stable_names = {
        "COW.GameFacade",
        "COW.GamePlay.Player",
        "COW.GamePlay.PlayerNetwork",
        "COW.GamePlay.PlayerAttributes",
        "COW.GamePlay.SceneEditBoxSelectTool",
        "IFix.Core.Code",
    }
    first = parse_dump(dump_path, stable_names, collect_enums=True)
    facade = require_type(first, "COW.GameFacade")
    player = require_type(first, "COW.GamePlay.Player")
    player_network = require_type(first, "COW.GamePlay.PlayerNetwork")
    attributes = require_type(first, "COW.GamePlay.PlayerAttributes")
    scene = require_type(first, "COW.GamePlay.SceneEditBoxSelectTool")

    match_type = qualify_gameplay(require_method(facade, "CurrentMatch", 0).return_type)
    aim_info_type = qualify_gameplay(
        require_method(player, "get_LastAimingInfoFromWeapon", 0).return_type
    )
    speed_method = require_method(attributes, "SetSpecialRunSpeedScaleByKeyAndValue", 3)
    speed_type = qualify_gameplay(speed_method.parameter_types[0])

    second = parse_dump(dump_path, {match_type, aim_info_type})
    match_decl = require_type(second, match_type)
    aim_decl = require_type(second, aim_info_type)

    player_methods: list[tuple[int, MethodDecl]] = []
    for index, method in enumerate(match_decl.methods):
        if is_player_container(method.return_type, "List"):
            score = 0
            if index > 0 and "Dictionary<" in match_decl.methods[index - 1].return_type:
                score += 1
            if (index + 1 < len(match_decl.methods)
                    and is_player_container(match_decl.methods[index + 1].return_type, "HashSet")):
                score += 1
            player_methods.append((score, method))
    if not player_methods:
        raise ValueError(f"{match_type} has no List<Player> method")
    best_score = max(score for score, _ in player_methods)
    best_methods = [method for score, method in player_methods if score == best_score]
    if len(best_methods) != 1 or best_score < 1:
        names = ", ".join(method.name for _, method in player_methods)
        raise ValueError(f"List<Player> method is ambiguous in {match_type}: {names}")
    match_players_method = best_methods[0].name

    scene_fields = find_sequence(scene.fields, ["Boolean", "Vector2", "Vector2"])
    scene_menu, scene_position, scene_state = scene_fields

    normalized_aim = normalize_type(aim_info_type)
    player_instances = [item for item in player.fields if not item.is_static]
    player_aim_field: FieldDecl | None = None
    for index in range(len(player_instances) - 2):
        if (qualify_gameplay(player_instances[index].type_name) == normalized_aim
                and qualify_gameplay(player_instances[index + 1].type_name) == normalized_aim
                and player_instances[index + 2].name == "LastAimingInfoFromWeaponAdjusted"):
            player_aim_field = player_instances[index]
            break
    if player_aim_field is None:
        raise ValueError("could not identify Player's current aiming-info field")

    expected_aim_kinds: list[str | None] = [
        "GameObject", "Collider", "Vector3", "Vector3", "Vector3", "Vector3",
        "Int32", "Single", "Int32", None, "PhysicMaterial", "Boolean", "Boolean",
        "Vector3", "Int16",
    ]
    aim_instances = [item for item in aim_decl.fields if not item.is_static]
    aim_matches: list[list[FieldDecl]] = []
    for index in range(len(aim_instances) - len(expected_aim_kinds) + 1):
        candidate = aim_instances[index:index + len(expected_aim_kinds)]
        if any(
            expected is not None and type_kind(item.type_name) != expected
            for item, expected in zip(candidate, expected_aim_kinds)
        ):
            continue
        candidate_enum_name = qualify_gameplay(candidate[9].type_name)
        candidate_enum = first.get(candidate_enum_name)
        if candidate_enum is not None and all(
            candidate_enum.constants.get(name) == value
            for name, value in (("Default", "0"), ("Head", "1"), ("Body", "2"))
        ):
            aim_matches.append(candidate)
    if len(aim_matches) != 1:
        raise ValueError(f"expected one aiming-info field layout, found {len(aim_matches)}")
    aim_layout = aim_matches[0]
    aim_type = qualify_gameplay(aim_layout[9].type_name)
    aim_enum = require_type(first, aim_type)
    for name, expected in (("Default", "0"), ("Head", "1"), ("Body", "2")):
        actual = aim_enum.constants.get(name)
        if actual != expected:
            raise ValueError(f"{aim_type}.{name} expected {expected}, found {actual}")
    speed_enum = require_type(first, speed_type)
    if speed_enum.constants.get("BuffSystem") != "500":
        raise ValueError(f"{speed_type}.BuffSystem is not 500")

    required_methods = (
        (player, "IsReallyInStealth", 0),
        (player, "get_IsMovableEntity", 0),
        (player_network, "OnUpdate", 2),
        (attributes, "GetScatterRate", 0),
        (scene, "OnGUI", 0),
    )
    for type_decl, name, count in required_methods:
        require_method(type_decl, name, count)

    placeholders = {
        "MATCH_TYPE": short_name(match_type),
        "MATCH_PLAYERS_METHOD": match_players_method,
        "AIM_INFO_TYPE": short_name(aim_info_type),
        "PLAYER_AIM_INFO_FIELD": player_aim_field.name,
        "SCENE_MENU_FIELD": scene_menu.name,
        "SCENE_POSITION_FIELD": scene_position.name,
        "SCENE_STATE_FIELD": scene_state.name,
        "AIM_GAME_OBJECT_FIELD": aim_layout[0].name,
        "AIM_COLLIDER_FIELD": aim_layout[1].name,
        "AIM_HIT_POSITION_FIELD": aim_layout[2].name,
        "AIM_TRACE_POSITION_FIELD": aim_layout[3].name,
        "AIM_DIRECTION_FIELD": aim_layout[4].name,
        "AIM_ORIGIN_FIELD": aim_layout[5].name,
        "AIM_HIT_TYPE": short_name(aim_type),
        "AIM_HIT_TYPE_FIELD": aim_layout[9].name,
        "AIM_FLAG_A_FIELD": aim_layout[11].name,
        "AIM_FLAG_B_FIELD": aim_layout[12].name,
        "AIM_SECONDARY_ORIGIN_FIELD": aim_layout[13].name,
        "AIM_SHORT_FIELD": aim_layout[14].name,
        "SPEED_TYPE": short_name(speed_type),
    }

    type_rows = [
        ["TYPE", BASE_MATCH, match_type],
        ["TYPE", BASE_AIM_INFO, aim_info_type],
        ["TYPE", BASE_AIM_TYPE, aim_type],
        ["TYPE", BASE_SPEED_TYPE, speed_type.replace(
            "COW.GamePlay.PlayerAttributes.",
            "COW.GamePlay.PlayerAttributes+",
            1,
        )],
    ]
    member_rows = [
        ["METHOD", BASE_MATCH, BASE_MATCH_METHOD, match_players_method],
        ["FIELD", "COW.GamePlay.Player", "AKFLHNOIHED", player_aim_field.name],
        ["FIELD", "COW.GamePlay.SceneEditBoxSelectTool", "DKNELPFOCHG", scene_menu.name],
        ["FIELD", "COW.GamePlay.SceneEditBoxSelectTool", "FMMMAPKGAAJ", scene_position.name],
        ["FIELD", "COW.GamePlay.SceneEditBoxSelectTool", "EEKIAPPAGCL", scene_state.name],
    ]
    base_aim_fields = [
        "HLIJMDODPIM", "OCEBCHENIOK", "MBGBCLNJOMK", "DGFLGBEOGPG",
        "IKDEGKIICJP", "LMAEGPEAECO", None, None, None, "FLCLOHCBJEI",
        None, "DEDOKPCAHAC", "GGJOADOBLID", "KPEICEMCHIF", "LNOIFBAFGOK",
    ]
    for old_name, current in zip(base_aim_fields, aim_layout):
        if old_name is not None:
            member_rows.append(["FIELD", BASE_AIM_INFO, old_name, current.name])
    rows = type_rows + member_rows

    details = {
        "match_type": match_type,
        "match_players_method": match_players_method,
        "aim_info_type": aim_info_type,
        "aim_hit_type": aim_type,
        "speed_type": speed_type,
        "source_lines": {
            "match_method": best_methods[0].line,
            "player_aim_field": player_aim_field.line,
            "scene_fields": [item.line for item in scene_fields],
            "aim_layout": [item.line for item in aim_layout],
        },
    }
    return placeholders, rows, details


def infer_version(path: Path) -> str:
    matches = re.findall(r"\d+\.\d+\.\d+", path.name)
    return matches[-1] if matches else path.stem


def select_dump(explicit: Path | None, dumps_dir: Path) -> Path:
    if explicit is not None:
        if not explicit.is_file():
            raise FileNotFoundError(f"dump not found: {explicit}")
        return explicit.resolve()

    candidates = sorted(
        dumps_dir.glob("*.cs"),
        key=lambda item: (item.stat().st_mtime_ns, item.name),
        reverse=True,
    )
    if not candidates:
        root_dir = dumps_dir.parent
        root_candidates = sorted(
            root_dir.glob("*.cs"),
            key=lambda item: (item.stat().st_mtime_ns, item.name),
            reverse=True,
        )
        if root_candidates:
            return root_candidates[0].resolve()
        raise FileNotFoundError(f"no .cs dump found in {dumps_dir} or {root_dir}")
    return candidates[0].resolve()


def update_readme(readme: Path, status: str) -> None:
    if not readme.is_file():
        return
    text = readme.read_text(encoding="utf-8")
    start = "<!-- AUTO_STATUS_START -->"
    end = "<!-- AUTO_STATUS_END -->"
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.DOTALL)
    replacement = f"{start}\n{status.rstrip()}\n{end}"
    if not pattern.search(text):
        return
    readme.write_text(pattern.sub(replacement, text, count=1), encoding="utf-8")


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dump", type=Path)
    parser.add_argument("--dumps-dir", type=Path, default=root / "dumps")
    parser.add_argument("--template", type=Path, default=root / "src" / "ESPLogic.template.cs")
    parser.add_argument("--generated", type=Path, default=root / "generated")
    parser.add_argument("--readme", type=Path, default=root / "README.md")
    parser.add_argument("--readme-en", type=Path, default=root / "README_EN.md")
    parser.add_argument("--no-readme", action="store_true")
    args = parser.parse_args()

    dump_path = select_dump(args.dump, args.dumps_dir)
    placeholders, rows, details = discover_bindings(dump_path)
    template = args.template.read_text(encoding="utf-8")
    template_keys = set(PLACEHOLDER_RE.findall(template))
    missing = sorted(template_keys - placeholders.keys())
    if missing:
        raise ValueError(f"template binding mismatch: missing={missing}")
    generated_source = PLACEHOLDER_RE.sub(
        lambda match: placeholders[match.group(1)], template
    )
    if PLACEHOLDER_RE.search(generated_source):
        raise ValueError("generated source still contains placeholders")

    args.generated.mkdir(parents=True, exist_ok=True)
    source_path = args.generated / "ESPLogic.cs"
    binding_path = args.generated / "bindings.tsv"
    report_path = args.generated / "bindings.json"
    source_path.write_text(generated_source, encoding="utf-8", newline="\n")
    binding_path.write_text(
        "# kind\tdeclaring-type-or-old-type\told-name-or-new-type\tnew-name\n"
        + "".join("\t".join(row) + "\n" for row in rows),
        encoding="ascii",
        newline="\n",
    )
    dump_hash = hashlib.sha256(dump_path.read_bytes()).hexdigest().upper()
    try:
        dump_rel = str(dump_path.relative_to(root)).replace("\\", "/")
    except ValueError:
        dump_rel = str(dump_path).replace("\\", "/")
    report = {
        "dump": dump_rel,
        "version": infer_version(dump_path),
        "dump_sha256": dump_hash,
        "placeholders": placeholders,
        "bindings": rows,
        "details": details,
    }
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    if not args.no_readme:
        status = (
            f"- Active dump: `{dump_path.name}`\n"
            f"- Detected version: `{report['version']}`\n"
            f"- Dump SHA-256: `{dump_hash}`\n"
            f"- Match binding: `{details['match_type']}.{details['match_players_method']}()`\n"
            f"- Aiming-info binding: `{details['aim_info_type']}`\n"
            f"- Generated source: `generated/ESPLogic.cs`"
        )
        update_readme(args.readme, status)
        update_readme(args.readme_en, status)

    print(f"dump={dump_path}")
    print(f"version={report['version']}")
    print(f"bindings={binding_path}")
    print(f"source={source_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
