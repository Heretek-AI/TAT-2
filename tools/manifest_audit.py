#!/usr/bin/env python3
"""Fail-closed audit of the extracted snapshot and generated content tree.

Requires Python 3.10+.

The gate has five independent layers:

1. **Mount / path consistency** -- manifest paths are compared to
   ``extracted/filelist.txt`` case-insensitively, the pak container is excluded,
   case-sensitive parity is gated with ``tools/audit_allowlists.json`` (73 known
   case normalizations), and 33 case-only ``.ubulk`` companion differences are
   allowlisted separately. Every manifest payload path must also resolve to a
   physical extraction artifact (46 known-undumped paths are allowlisted).
2. **Content assertions** -- levels, contracts, tables, materials, textures,
   containers, decals, devices, animation GLBs, audio OGGs, localisation CSVs,
   videos, scene variants and Niagara placements are measured from the files on
   disk, not just from metadata.
3. **Stage floors** -- payload file counts per stage exclude Godot importer
   artifacts (``.import``, ``.uid``, hidden files). Godot imports are a separate
   opt-in gate (``--require-imports``), never part of "assets extracted".
4. **errors.log** -- must exist, must carry the extractor's run marker
   ``# run <utc> filelist <sha256> errors <n>`` matching the current
   ``filelist.txt`` and body count. A missing, zero-byte, stale or mismatched
   log fails. Whitespace-only legacy logs are accepted as clean.
5. **Producer baseline** -- the tracked ``tools/audit_baseline.json`` records
   producer sha256s, infrastructure hashes, external tool versions, and a
   content hash/count for every producer output path. Normal runs compare all of
   them. A missing baseline fails; ``--bootstrap-stamps`` creates it explicitly.
   ``--refresh-stamps`` refuses missing/empty/decreased outputs and only accepts
   a changed producer when every output is newer than the producer or its
   hash/count changed.

Fail-closed by default. Debug opt-outs are explicit: ``--allow-stale`` and
``--allow-unexpected-errors``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BASELINE = ROOT / "tools" / "audit_baseline.json"
DEFAULT_ALLOWLISTS = ROOT / "tools" / "audit_allowlists.json"
STEAM_MANIFEST = (
    Path.home()
    / ".local/share/Steam/steamapps/common/Thick As Thieves/Manifest_UFSFiles_Win64.txt"
)
DEFAULT_STEAM = Path.home() / ".local/share/Steam/steamapps/common/Thick As Thieves"

# P1-1: Engine carriers referenced by shipped levels must be mounted.
REQUIRED_ENGINE_DEPS = [
    "Engine/Content/EngineMaterials/WorldGridMaterial.uasset",
    "Engine/Content/BasicShapes/Cube.uasset",
    "Engine/Content/BasicShapes/Plane.uasset",
    "Engine/Content/BasicShapes/Sphere.uasset",
    "Engine/Content/BasicShapes/Cone.uasset",
    "Engine/Content/BasicShapes/Cylinder.uasset",
]

# CUE4Parse's AnimationExporter has no BlendSpace support. The list is exact:
# any new or differently-shaped error still fails the gate.
KNOWN_UNSUPPORTED_ANIM = frozenset(
    {
        "TAT/Content/Art/Animation/Base/Anim/Damage/BS_Crawl",
        "TAT/Content/Art/Animation/Base/Anim/Damage/BS_HitReactAdd",
        "TAT/Content/Art/Animation/Base/Anim/Lyra/AimOffset",
        "TAT/Content/Art/Animation/Base/Anim/Lyra/BS_Lean",
        "TAT/Content/Art/Animation/Base/Anim/Traversal/BS_Slide_In",
        "TAT/Content/Art/Animation/Base/Anim/Traversal/BS_Slide_Out",
        "TAT/Content/Art/Animation/Base/Anim/Traversal/BS_Slide_Loop",
        "TAT/Content/Art/Animation/Base/Anim/Traversal/Ladder/BS_Ladder",
        "TAT/Content/Art/Animation/Base/Anim/Traversal/Pipe/BS_Pipe",
        "TAT/Content/Art/Animation/Thief/Anim/Gear/Zipwire/BS_Zipwire_Travel",
        "TAT/Content/Art/Animation/Thief/Anim/Gear/Zipwire/BS_Zipwire_Travel_Start",
        "TAT/Content/Art/Animation/Thief/Anim/Gear/Zipwire/BS_Zipwire_Cast",
        "TAT/Content/Art/Animation/Thief/Anim/Gear/Zipwire/BS_Zipwire_WalkJog",
        "TAT/Content/Art/Animation/ThiefNisha/Anim/Zipwire/Dangle/BS_Zipwire_Dangle",
    }
)
UNSUPPORTED_ANIM_MARKER = "is not supported for conversion"

EXPECTED_LOOT_GOALS = {
    "Mission.Guildhall.LootTheRoom": [4000, 6000, 8000],
}

DUMP_STAGES = ("raw", "json", "assets", "audio", "audio-meta")

# Godot importer artifacts are never extraction payload. .translation is a
# Godot import of the CSV and is gated separately, never counted as producer
# output in a normalize-only tree.
IMPORTER_SUFFIXES = frozenset({".import", ".uid", ".translation", ".md5"})

# Measured 2026-11-24 payload floors (hidden/importer files excluded):
# raw 141, json 12541, assets 6659, audio 5019, audio-meta 1441.
STAGE_MIN_FILES = {
    "raw": 120,
    "json": 12000,
    "assets": 6500,
    "audio": 5000,
    "audio-meta": 1200,
}

ERRORS_HEADER_RE = re.compile(
    r"^# run (?P<utc>\S+) filelist (?P<sha>[0-9a-f]{64}|none) errors (?P<n>\d+)$"
)


@dataclass(frozen=True)
class Producer:
    """A pipeline producer and the output paths that must match its baseline."""

    script: str
    command: str
    outputs: tuple[str, ...]
    metrics: tuple[str, ...] = ()


# Output tokens: gen: -> --generated, assets: -> --assets, root: -> repo root.
PRODUCERS = (
    Producer(
        "tools/parse_tables.py",
        "python3 tools/parse_tables.py",
        (
            "gen:levels",
            "gen:tables",
            "gen:gameplay",
            "gen:scene_variants.json",
        ),
        ("levels", "tables", "scene_variants", "devices_total", "devices_families"),
    ),
    Producer(
        "tools/parse_gameplay.py",
        "python3 tools/parse_gameplay.py",
        ("gen:gameplay",),
    ),
    Producer(
        "tools/parse_materials.py",
        "python3 tools/parse_materials.py",
        (
            "gen:materials.json",
            "gen:mesh_materials.json",
            "gen:mesh_materials_provenance.json",
        ),
        ("materials_entries", "materials_albedo", "texture_refs"),
    ),
    Producer(
        "tools/parse_contracts.py",
        "python3 tools/parse_contracts.py",
        ("gen:gameplay/contracts.json",),
        ("contracts", "contracts_loot_goals"),
    ),
    Producer(
        "tools/parse_clues.py",
        "python3 tools/parse_clues.py",
        ("gen:gameplay/clues.json",),
    ),
    Producer(
        "tools/parse_quests.py",
        "python3 tools/parse_quests.py",
        ("gen:gameplay/quests.json",),
    ),
    Producer(
        "tools/parse_devices.py",
        "python3 tools/parse_devices.py",
        ("gen:gameplay/devices_runtime.json",),
    ),
    Producer(
        "tools/parse_loot.py",
        "python3 tools/parse_loot.py",
        ("gen:gameplay/loot_actors.json",),
    ),
    Producer(
        "tools/parse_spawners.py",
        "python3 tools/parse_spawners.py",
        ("gen:gameplay/spawners.json",),
    ),
    Producer(
        "tools/parse_containers.py",
        "python3 tools/parse_containers.py",
        ("gen:gameplay/containers.json",),
        ("containers",),
    ),
    Producer(
        "tools/parse_interactables.py",
        "python3 tools/parse_interactables.py",
        ("gen:gameplay/interactables.json",),
    ),
    Producer(
        "tools/parse_unlocks.py",
        "python3 tools/parse_unlocks.py",
        ("gen:gameplay/unlocks.json",),
    ),
    Producer(
        "tools/parse_hearing.py",
        "python3 tools/parse_hearing.py",
        ("gen:gameplay/hearing.json", "gen:gameplay/perception.json"),
    ),
    Producer(
        "tools/parse_state_tree.py",
        "python3 tools/parse_state_tree.py",
        (
            "gen:gameplay/guard_behavior.json",
            "root:docs/reports/w5e-guard-state-tree.md",
        ),
    ),
    Producer(
        "tools/parse_weather.py",
        "python3 tools/parse_weather.py",
        ("gen:weather",),
    ),
    Producer(
        "tools/parse_vfx.py",
        "python3 tools/parse_vfx.py",
        ("gen:vfx",),
    ),
    Producer(
        "tools/extract_audio.py",
        "python3 tools/extract_audio.py",
        ("assets:ue/audio",),
    ),
    Producer(
        "tools/convert_wwise.py",
        "python3 tools/convert_wwise.py",
        (
            "assets:ue/audio/wwise",
            "gen:audio_library.json",
            "gen:audio_events.json",
        ),
        ("audio_clips", "audio_failed", "audio_ogg"),
    ),
    Producer(
        "tools/parse_locres.py",
        "python3 tools/parse_locres.py",
        ("gen:localization",),
        ("loc_csv",),
    ),
    Producer(
        "tools/convert_videos.py",
        "python3 tools/convert_videos.py",
        ("assets:ue/videos", "gen:videos.json"),
        ("videos_ogv", "videos_manifest"),
    ),
    Producer(
        "tools/usd_to_gltf.py",
        "make anims  # blender --background --python tools/usd_to_gltf.py ...",
        ("assets:ue/Anims", "gen:anims_manifest.json"),
        ("anims_ok", "anims_fail", "anims_entries", "anims_total", "anims_glb"),
    ),
    Producer(
        "tools/parse_anim_meta.py",
        "python3 tools/parse_anim_meta.py",
        ("gen:anims_meta.json",),
    ),
)

# Pipeline infrastructure that changes extraction semantics even though it is
# not a NORMALIZERS entry.
INFRASTRUCTURE = (
    ("root:Makefile", "make extract / make normalize"),
    ("root:tools/tat-extract/tat-extract.csproj", "make build-extractor"),
    ("root:tools/tat-extract/Exporter.cs", "make build-extractor"),
    ("root:tools/tat-extract/Program.cs", "make build-extractor"),
    (
        "root:tools/tat-extract/native/linux-x64/CUE4Parse-Natives.so",
        "make build-extractor",
    ),
    ("root:tools/audit_allowlists.json", "reviewed coverage allowlist"),
    ("root:tools/reimport_assets.sh", "tools/reimport_assets.sh"),
    ("root:tools/prebake_texture_cap.py", "make desktop-texture-cap"),
    ("root:tools/fetch_vgmstream.sh", "make audio-tools"),
    ("root:tools/godot", "native engine wrapper"),
)

# External tools whose version change invalidates generated binary outputs.
TOOL_COMMANDS = (
    ("blender", ("blender", "--version"), re.compile(r"^Blender\s+\S+")),
    ("ffmpeg", ("ffmpeg", "-version"), re.compile(r"^ffmpeg version \S+")),
    (
        "vgmstream",
        ("tools/bin/vgmstream/vgmstream-cli", "-h"),
        re.compile(r"^vgmstream CLI decoder [^\r\n]+"),
    ),
    (
        "dotnet",
        (str(Path.home() / ".dotnet10" / "dotnet"), "--version"),
        re.compile(r"^\d+\.\d+\.\d+\S*"),
    ),
)

# Freshness groups use the same path tokens as producers. The producer baseline
# compares content hashes; these mtime groups are a second, domain-level signal.
FRESHNESS_GROUPS = (
    ("levels", ("extracted:json/Maps",), ("gen:levels",)),
    (
        "gameplay",
        (
            "extracted:json/Missions",
            "extracted:json/Gameplay",
            "extracted:json/AI",
            "extracted:json/Character",
        ),
        ("gen:gameplay",),
    ),
    (
        "tables",
        (
            "extracted:json/Gameplay",
            "extracted:json/AI",
            "extracted:json/Missions",
            "extracted:json/Character",
            "extracted:json/Core",
            "extracted:json/StringTables",
            "extracted:json/UI",
            "extracted:json/Audio",
        ),
        ("gen:tables",),
    ),
    (
        "materials",
        ("extracted:assets",),
        (
            "gen:materials.json",
            "gen:mesh_materials.json",
            "gen:mesh_materials_provenance.json",
        ),
    ),
    (
        "audio",
        ("extracted:audio", "extracted:audio-meta"),
        ("gen:audio_events.json", "gen:audio_library.json"),
    ),
    ("weather", ("extracted:json",), ("gen:weather",)),
    ("vfx", ("extracted:json",), ("gen:vfx",)),
    ("anims", ("extracted:anims/usd",), ("gen:anims_manifest.json", "assets:ue/Anims")),
    (
        "localization",
        ("extracted:raw/TAT/Content/Localization/Game",),
        ("gen:localization",),
    ),
    ("scene_variants", ("extracted:json/Maps",), ("gen:scene_variants.json",)),
    (
        "videos",
        ("steam:TAT/Content/Movies",),
        ("gen:videos.json", "assets:ue/videos"),
    ),
)


@dataclass(frozen=True)
class Paths:
    extracted: Path
    generated: Path
    assets: Path
    steam: Path
    manifest: Path
    baseline: Path
    allowlists: Path


@dataclass
class ContentCheck:
    name: str
    ok: bool
    measured: dict
    problems: list[str]

    def line(self) -> str:
        fields = ", ".join(f"{k}={v}" for k, v in self.measured.items())
        status = "OK  " if self.ok else "FAIL"
        return f"content {self.name}: {status} {fields}"


def _is_payload_file(path: Path) -> bool:
    return (
        path.is_file()
        and not path.name.startswith(".")
        and path.suffix.lower() not in IMPORTER_SUFFIXES
    )


def _payload_files(path: Path) -> list[Path]:
    if path.is_file():
        return [path] if _is_payload_file(path) else []
    if not path.is_dir():
        return []
    return [p for p in path.rglob("*") if _is_payload_file(p)]


def _count_files(path: Path, pattern: str = "*") -> int:
    if path.is_file():
        return 1
    return len([p for p in path.rglob(pattern) if _is_payload_file(p)])


def _load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _digest_path(path: Path) -> dict:
    """Count/byte/hash digest of a producer output path (payload files only)."""
    exists = path.exists()
    files = _payload_files(path)
    digest = hashlib.sha256()
    total = 0
    newest = 0.0
    for file in sorted(files):
        try:
            stat = file.stat()
        except OSError:
            continue
        rel = str(file.relative_to(path)) if path.is_dir() else file.name
        digest.update(rel.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(stat.st_size).encode("ascii"))
        digest.update(b"\0")
        total += stat.st_size
        newest = max(newest, stat.st_mtime)
        try:
            with file.open("rb") as fh:
                for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                    digest.update(chunk)
        except OSError:
            digest.update(b"<unreadable>")
    return {
        "exists": exists,
        "files": len(files),
        "bytes": total,
        "sha256": digest.hexdigest() if files else "",
        "newest_mtime": newest,
    }


def _resolve_token(token: str, paths: Paths) -> Path:
    kind, rel = token.split(":", 1)
    roots = {
        "extracted": paths.extracted,
        "gen": paths.generated,
        "assets": paths.assets,
        "steam": paths.steam,
        "root": ROOT,
    }
    return roots[kind] / rel


def _stem(path: str) -> str:
    text = path.replace("\\", "/").removeprefix("TAT/Content/")
    return str(PurePosixPath(text).with_suffix("")).lower()


def _build_disk_index(extracted: Path) -> set[str]:
    index: set[str] = set()
    for stage in DUMP_STAGES:
        root = extracted / stage
        if not root.is_dir():
            continue
        for file in _payload_files(root):
            index.add(_stem(str(file.relative_to(root))))
    return index


def _newest_mtime(root: Path) -> float:
    latest = 0.0
    for path in _payload_files(root):
        try:
            latest = max(latest, path.stat().st_mtime)
        except OSError:
            continue
    return latest


def _albedo_texture(entry) -> str:
    if not isinstance(entry, dict):
        return ""
    texs = entry.get("texs")
    if isinstance(texs, dict):
        albedo = texs.get("albedo")
        if isinstance(albedo, str) and albedo.strip():
            return albedo.strip()
    albedo = entry.get("albedo")
    if isinstance(albedo, str) and albedo.strip():
        return albedo.strip()
    return ""


def _texture_path(res_path: str, assets: Path) -> Path | None:
    if not isinstance(res_path, str) or not res_path.startswith("res://"):
        return None
    rel = res_path[len("res://") :].removeprefix("assets/")
    return assets / rel


_LEVEL_CACHE: dict[str, list] = {}


def _levels(levels_dir: Path) -> list:
    key = str(levels_dir.resolve())
    if key not in _LEVEL_CACHE:
        rows = []
        for path in sorted(levels_dir.rglob("*.tatlevel.json")):
            rows.append((path, _load_json(path)))
        _LEVEL_CACHE[key] = rows
    return _LEVEL_CACHE[key]


def _check_levels(gen: Path, metrics: dict) -> ContentCheck:
    files = sorted((gen / "levels").rglob("*.tatlevel.json"))
    invalid: list[str] = []
    for path, data in _levels(gen / "levels"):
        if not isinstance(data, dict) or not data:
            invalid.append(str(path.relative_to(gen / "levels")))
    metrics["levels"] = len(files)
    metrics["levels_invalid"] = len(invalid)
    problems = []
    if len(files) < 107:
        problems.append(
            f"levels: expected >= 107 .tatlevel.json under {gen / 'levels'}, "
            f"found {len(files)}; regenerate with python3 tools/parse_tables.py"
        )
    if invalid:
        problems.append(
            f"levels: {len(invalid)} level JSON files are empty or not objects: "
            f"{invalid[:5]}; regenerate with python3 tools/parse_tables.py"
        )
    return ContentCheck(
        "levels",
        not problems,
        {"files": len(files), "min": 107, "invalid": len(invalid)},
        problems,
    )


def _check_contracts(gen: Path, metrics: dict) -> ContentCheck:
    path = gen / "gameplay" / "contracts.json"
    data = _load_json(path)
    contracts = data.get("contracts") if isinstance(data, dict) else None
    count = len(contracts) if isinstance(contracts, list) else -1
    goals = data.get("mission_loot_goals") if isinstance(data, dict) else None
    goals_ok = isinstance(goals, dict) and goals == EXPECTED_LOOT_GOALS
    metrics["contracts"] = count
    metrics["contracts_loot_goals"] = 1 if goals_ok else 0
    problems = []
    if count != 16:
        problems.append(
            f"contracts: expected exactly 16 entries in {path}['contracts'], "
            f"found {count}; regenerate with python3 tools/parse_contracts.py"
        )
    if not goals_ok:
        problems.append(
            f"contracts: expected mission_loot_goals == {EXPECTED_LOOT_GOALS!r} "
            f"in {path}, found {goals!r}; run python3 tools/parse_contracts.py"
        )
    return ContentCheck(
        "contracts",
        not problems,
        {"entries": count, "expected": 16, "loot_goals": goals_ok},
        problems,
    )


def _table_nonempty(data) -> bool:
    if isinstance(data, list):
        return bool(data)
    if not isinstance(data, dict) or not data:
        return False
    rows = data.get("rows")
    entries = data.get("entries")
    return bool(
        (isinstance(rows, dict) and rows)
        or (isinstance(entries, dict) and entries)
        or (isinstance(rows, list) and rows)
        or (isinstance(entries, list) and entries)
    )


def _check_tables(gen: Path, metrics: dict) -> ContentCheck:
    root = gen / "tables"
    files = sorted(root.rglob("*.json"))
    invalid: list[str] = []
    for path in files:
        try:
            data = _load_json(path)
        except Exception as exc:  # noqa: BLE001 - report per file
            invalid.append(f"{path.relative_to(root)}: {type(exc).__name__}")
            continue
        if not _table_nonempty(data):
            invalid.append(f"{path.relative_to(root)}: empty schema")
    metrics["tables"] = len(files)
    metrics["tables_invalid"] = len(invalid)
    problems = []
    if len(files) < 144:
        problems.append(
            f"tables: expected >= 144 JSON files under {root}, found {len(files)}; "
            "regenerate with python3 tools/parse_tables.py"
        )
    if invalid:
        problems.append(
            f"tables: {len(invalid)} JSON files have no rows/entries: "
            f"{invalid[:5]}; regenerate with python3 tools/parse_tables.py"
        )
    return ContentCheck(
        "tables",
        not problems,
        {"files": len(files), "min": 144, "invalid": len(invalid)},
        problems,
    )


def _check_materials(gen: Path, assets: Path, metrics: dict) -> ContentCheck:
    path = gen / "materials.json"
    data = _load_json(path)
    entries = data if isinstance(data, dict) else {}
    with_albedo = 0
    texture_refs: set[str] = set()
    for value in entries.values():
        if _albedo_texture(value):
            with_albedo += 1
        if isinstance(value, dict):
            for tex in (value.get("texs") or {}).values():
                if isinstance(tex, str) and tex.strip():
                    texture_refs.add(tex.strip())
    missing_textures = []
    zero_textures = []
    for res_path in sorted(texture_refs):
        disk = _texture_path(res_path, assets)
        if disk is None or not disk.is_file():
            missing_textures.append(res_path)
        elif disk.stat().st_size == 0:
            zero_textures.append(res_path)
    metrics["materials_entries"] = len(entries)
    metrics["materials_albedo"] = with_albedo
    metrics["texture_refs"] = len(texture_refs)
    problems = []
    if len(entries) < 1620:
        problems.append(
            f"materials: expected >= 1620 entries in {path}, found {len(entries)}; "
            "regenerate with python3 tools/parse_materials.py"
        )
    if with_albedo < 1370:
        problems.append(
            f"materials: expected >= 1370 entries with a non-empty albedo texture "
            f"in {path}, found {with_albedo}; regenerate with "
            "python3 tools/parse_materials.py"
        )
    if missing_textures:
        problems.append(
            f"materials: {len(missing_textures)} referenced textures are missing, "
            f"e.g. {missing_textures[:3]}; re-run the texture extraction"
        )
    if zero_textures:
        problems.append(
            f"materials: {len(zero_textures)} referenced textures are zero bytes, "
            f"e.g. {zero_textures[:3]}; re-run the texture extraction"
        )
    return ContentCheck(
        "materials",
        not problems,
        {
            "entries": len(entries),
            "min_entries": 1620,
            "with_albedo": with_albedo,
            "min_albedo": 1370,
            "texture_refs": len(texture_refs),
            "missing_textures": len(missing_textures),
        },
        problems,
    )


def _check_containers(gen: Path, metrics: dict) -> ContentCheck:
    path = gen / "gameplay" / "containers.json"
    data = _load_json(path)
    classes = data.get("classes") if isinstance(data, dict) else None
    class_names = set(classes) if isinstance(classes, dict) else set()
    found = 0
    for _level_path, level in _levels(gen / "levels"):
        for actor in level.get("actors") or []:
            if isinstance(actor, dict) and actor.get("class") in class_names:
                found += 1
    metrics["containers"] = found
    metrics["container_classes"] = len(class_names)
    problems = []
    if len(class_names) < 5:
        problems.append(
            f"containers: expected 5 container Blueprint classes in "
            f"{path}['classes'], found {len(class_names)}; regenerate with "
            "python3 tools/parse_containers.py"
        )
    if found < 250:
        problems.append(
            f"containers: expected >= 250 placed container records summed across "
            f"{gen / 'levels'}, found {found} (classes={len(class_names)}); "
            "regenerate levels then python3 tools/parse_containers.py"
        )
    return ContentCheck(
        "containers",
        not problems,
        {"records": found, "min": 250, "classes": len(class_names)},
        problems,
    )


def _check_decals(gen: Path, metrics: dict) -> ContentCheck:
    found = sum(len(level.get("decals") or []) for _p, level in _levels(gen / "levels"))
    metrics["decals"] = found
    problems = []
    if found < 670:
        problems.append(
            f"decals: expected >= 670 decal records summed across "
            f"{gen / 'levels'}, found {found}; regenerate python3 tools/parse_tables.py"
        )
    return ContentCheck(
        "decals", not problems, {"records": found, "min": 670}, problems
    )


def _check_devices(gen: Path, metrics: dict) -> ContentCheck:
    path = gen / "gameplay" / "devices.json"
    data = _load_json(path)
    total = data.get("total")
    families = data.get("families")
    family_count = len(families) if isinstance(families, dict) else -1
    summed = (
        sum(
            int(family.get("count", 0))
            for family in families.values()
            if isinstance(family, dict)
        )
        if isinstance(families, dict)
        else -1
    )
    metrics["devices_total"] = total
    metrics["devices_families"] = family_count
    metrics["devices_family_sum"] = summed
    problems = []
    if total != 4118:
        problems.append(
            f"devices: expected total == 4118 in {path}, found {total!r}; "
            "regenerate python3 tools/parse_tables.py"
        )
    if family_count != 21:
        problems.append(
            f"devices: expected exactly 21 families in {path}, found "
            f"{family_count}; regenerate python3 tools/parse_tables.py"
        )
    if summed != total:
        problems.append(
            f"devices: family counts sum to {summed}, total field says {total!r}; "
            "regenerate python3 tools/parse_tables.py"
        )
    return ContentCheck(
        "devices",
        not problems,
        {
            "total": total,
            "expected": 4118,
            "families": family_count,
            "expected_families": 21,
            "family_sum": summed,
        },
        problems,
    )


def _count_nonzero(root: Path, pattern: str) -> tuple[int, list[str]]:
    files = sorted(root.rglob(pattern)) if root.is_dir() else []
    zero = []
    for path in files:
        try:
            if path.stat().st_size == 0:
                zero.append(str(path.relative_to(root)))
        except OSError:
            zero.append(str(path.relative_to(root)))
    return len(files), zero


def _check_animations(gen: Path, assets: Path, metrics: dict) -> ContentCheck:
    path = gen / "anims_manifest.json"
    data = _load_json(path)
    ok = data.get("ok")
    fail = data.get("fail")
    total = data.get("total")
    entries = data.get("entries")
    n_entries = len(entries) if isinstance(entries, list) else -1
    glb, zero_glb = _count_nonzero(assets / "ue" / "Anims", "*.glb")
    metrics["anims_ok"] = ok
    metrics["anims_fail"] = fail
    metrics["anims_total"] = total
    metrics["anims_entries"] = n_entries
    metrics["anims_glb"] = glb
    problems = []
    if not isinstance(ok, int) or ok < 995:
        problems.append(
            f"animations: expected ok >= 995 in {path}, found {ok!r}; "
            "regenerate with make anims"
        )
    if fail != 0:
        problems.append(
            f"animations: expected fail == 0 in {path}, found {fail!r}; "
            "inspect the converter log and regenerate with make anims"
        )
    if n_entries != total:
        problems.append(
            f"animations: expected entries == total in {path}, found "
            f"entries={n_entries} total={total!r}; regenerate with make anims"
        )
    if glb < 995:
        problems.append(
            f"animations: expected >= 995 .glb under {assets / 'ue' / 'Anims'}, "
            f"found {glb}; regenerate with make anims"
        )
    if zero_glb:
        problems.append(
            f"animations: {len(zero_glb)} zero-byte .glb files, e.g. "
            f"{zero_glb[:3]}; regenerate with make anims"
        )
    return ContentCheck(
        "animations",
        not problems,
        {
            "ok": ok,
            "min_ok": 995,
            "fail": fail,
            "entries": n_entries,
            "total": total,
            "glb": glb,
            "zero_glb": len(zero_glb),
        },
        problems,
    )


def _check_audio(gen: Path, assets: Path, metrics: dict) -> ContentCheck:
    path = gen / "audio_library.json"
    data = _load_json(path)
    counts = data.get("counts") if isinstance(data, dict) else None
    counts = counts if isinstance(counts, dict) else {}
    clips = counts.get("clips")
    failed = counts.get("failed")
    failures = data.get("failures") if isinstance(data, dict) else None
    n_failures = len(failures) if isinstance(failures, list) else -1
    ogg, zero_ogg = _count_nonzero(assets / "ue" / "audio", "*.ogg")
    metrics["audio_clips"] = clips
    metrics["audio_failed"] = failed
    metrics["audio_failure_records"] = n_failures
    metrics["audio_ogg"] = ogg
    problems = []
    if not isinstance(clips, int) or clips < 5018:
        problems.append(
            f"audio: expected counts.clips >= 5018 in {path}, found {clips!r}; "
            "regenerate python3 tools/extract_audio.py && "
            "python3 tools/convert_wwise.py"
        )
    if failed != 0:
        problems.append(
            f"audio: expected counts.failed == 0 in {path}, found {failed!r}; "
            "inspect failures and regenerate python3 tools/convert_wwise.py"
        )
    if n_failures != 0:
        problems.append(
            f"audio: expected an empty failures list in {path}, found "
            f"{n_failures} records; regenerate python3 tools/convert_wwise.py"
        )
    if ogg < 5018:
        problems.append(
            f"audio: expected >= 5018 .ogg under {assets / 'ue' / 'audio'}, "
            f"found {ogg}; regenerate python3 tools/convert_wwise.py"
        )
    if zero_ogg:
        problems.append(
            f"audio: {len(zero_ogg)} zero-byte .ogg files, e.g. {zero_ogg[:3]}; "
            "regenerate python3 tools/convert_wwise.py"
        )
    return ContentCheck(
        "audio",
        not problems,
        {
            "clips": clips,
            "min_clips": 5018,
            "failed": failed,
            "failure_records": n_failures,
            "ogg": ogg,
            "zero_ogg": len(zero_ogg),
        },
        problems,
    )


def _check_localization(gen: Path, metrics: dict) -> ContentCheck:
    root = gen / "localization"
    csv_files = sorted(root.glob("*.csv")) if root.is_dir() else []
    empty: list[str] = []
    for path in csv_files:
        try:
            if (
                path.stat().st_size == 0
                or not path.read_text(encoding="utf-8", errors="replace").strip()
            ):
                empty.append(path.name)
        except OSError:
            empty.append(path.name)
    metrics["loc_csv"] = len(csv_files)
    problems = []
    if len(csv_files) != 8:
        problems.append(
            f"localization: expected exactly 8 .csv files under {root}, found "
            f"{len(csv_files)}; regenerate python3 tools/parse_locres.py"
        )
    if empty:
        problems.append(
            f"localization: {len(empty)} empty .csv files, e.g. {empty[:3]}; "
            "regenerate python3 tools/parse_locres.py"
        )
    return ContentCheck(
        "localization",
        not problems,
        {"csv": len(csv_files), "expected": 8, "empty": len(empty)},
        problems,
    )


def _check_videos(gen: Path, assets: Path, metrics: dict) -> ContentCheck:
    video_dir = assets / "ue" / "videos"
    ogv, zero_ogv = _count_nonzero(video_dir, "*.ogv")
    manifest = _load_json(gen / "videos.json")
    entries = len(manifest) if isinstance(manifest, list) else -1
    metrics["videos_ogv"] = ogv
    metrics["videos_manifest"] = entries
    problems = []
    if ogv != 15:
        problems.append(
            f"videos: expected exactly 15 .ogv files under {video_dir}, found "
            f"{ogv}; regenerate python3 tools/convert_videos.py"
        )
    if entries != 15:
        problems.append(
            f"videos: expected exactly 15 entries in {gen / 'videos.json'}, found "
            f"{entries}; regenerate python3 tools/convert_videos.py"
        )
    if zero_ogv:
        problems.append(
            f"videos: {len(zero_ogv)} zero-byte .ogv files, e.g. {zero_ogv[:3]}; "
            "regenerate python3 tools/convert_videos.py"
        )
    return ContentCheck(
        "videos",
        not problems,
        {"ogv": ogv, "manifest": entries, "expected": 15, "zero_ogv": len(zero_ogv)},
        problems,
    )


def _check_scene_variants(gen: Path, metrics: dict) -> ContentCheck:
    path = gen / "scene_variants.json"
    data = _load_json(path)
    count = data.get("count") if isinstance(data, dict) else None
    variants = data.get("variants") if isinstance(data, dict) else None
    n_variants = len(variants) if isinstance(variants, list) else -1
    metrics["scene_variants"] = count
    metrics["scene_variants_records"] = n_variants
    problems = []
    if count != 222:
        problems.append(
            f"scene variants: expected count == 222 in {path}, found {count!r}; "
            "regenerate python3 tools/parse_tables.py"
        )
    if n_variants != 222 or n_variants != count:
        problems.append(
            f"scene variants: expected 222 records in {path}['variants'], found "
            f"{n_variants} (count field {count!r}); regenerate with "
            "python3 tools/parse_tables.py"
        )
    return ContentCheck(
        "scene_variants",
        not problems,
        {"count": count, "records": n_variants, "expected": 222},
        problems,
    )


def _check_niagara(gen: Path, metrics: dict) -> ContentCheck:
    found = sum(
        len(level.get("niagara") or []) for _p, level in _levels(gen / "levels")
    )
    metrics["niagara"] = found
    problems = []
    if found < 3695:
        problems.append(
            f"niagara: expected >= 3695 placement records summed across "
            f"{gen / 'levels'}, found {found}; regenerate python3 tools/parse_tables.py"
        )
    return ContentCheck(
        "niagara", not problems, {"records": found, "min": 3695}, problems
    )


def _run_check(fn, *args) -> ContentCheck:
    name = fn.__name__.removeprefix("_check_")
    try:
        return fn(*args)
    except Exception as exc:  # noqa: BLE001 - the message is the diagnostic
        return ContentCheck(name, False, {}, [f"{name}: {type(exc).__name__}: {exc}"])


def _load_allowlists(path: Path) -> dict:
    data = _load_json(path)
    if not isinstance(data, dict):
        raise TypeError(f"{path} is not an object")
    case_only = data.get("case_only")
    case_ubulk = data.get("case_only_ubulk")
    disk_missing = data.get("disk_missing")
    if not isinstance(case_only, list) or not isinstance(case_ubulk, list):
        raise TypeError(f"{path} needs case_only and case_only_ubulk lists")
    if not isinstance(disk_missing, list):
        raise TypeError(f"{path} needs a disk_missing list")
    return {
        "case_only": {str(x) for x in case_only},
        "case_only_ubulk": {str(x) for x in case_ubulk},
        "disk_missing": {str(x) for x in disk_missing},
    }


def _normalizers_from_makefile() -> list[str]:
    text = (ROOT / "Makefile").read_text(encoding="utf-8")
    match = re.search(
        r"^NORMALIZERS\s*:=\s*(.*?)(?=^\S|\Z)", text, re.MULTILINE | re.DOTALL
    )
    if not match:
        raise ValueError("Makefile has no NORMALIZERS assignment")
    names = re.findall(r"[A-Za-z0-9_]+", match.group(1).replace("\\\n", " "))
    return names


def _producer_coverage_failures() -> list[str]:
    failures = []
    scripts = {p.script for p in PRODUCERS}
    try:
        normalizers = _normalizers_from_makefile()
    except Exception as exc:  # noqa: BLE001
        return [f"producer coverage: cannot parse Makefile NORMALIZERS: {exc}"]
    for name in normalizers:
        script = f"tools/{name}.py"
        if script not in scripts:
            failures.append(
                f"producer coverage: Makefile NORMALIZERS entry {name!r} has no "
                f"baseline stamp ({script} missing from PRODUCERS)"
            )
    for script in sorted(ROOT.glob("tools/parse_*.py")):
        rel = str(script.relative_to(ROOT))
        if rel not in scripts:
            failures.append(
                f"producer coverage: {rel} exists but has no baseline stamp"
            )
    return failures


def _resolve_executable(command: str) -> str | None:
    """Resolve a PATH name or repo-relative binary without invoking it."""
    found = shutil.which(command)
    if found:
        return found
    candidate = Path(command)
    if not candidate.is_absolute():
        candidate = ROOT / candidate
    if candidate.is_file() and os.access(candidate, os.X_OK):
        return str(candidate)
    return None


def _probe_tool_versions() -> dict:
    versions = {}
    for name, command, pattern in TOOL_COMMANDS:
        resolved = _resolve_executable(command[0])
        if resolved is None:
            # Never invoke a missing tool: some binaries print usage text for
            # unknown flags, which made the recorded version unstable.
            versions[name] = "missing"
            continue
        try:
            result = subprocess.run(
                [resolved, *command[1:]],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            text = "\n".join(part for part in (result.stdout, result.stderr) if part)
            match = pattern.search(text)
            if match:
                versions[name] = match.group(0).strip()
            else:
                versions[name] = f"unparsed (exit {result.returncode})"
        except FileNotFoundError:
            versions[name] = "missing"
        except subprocess.TimeoutExpired:
            versions[name] = "timeout"
        except Exception as exc:  # noqa: BLE001
            versions[name] = f"error: {type(exc).__name__}: {exc}"
    return versions


def _load_baseline(path: Path) -> tuple[dict | None, str]:
    if not path.exists():
        return None, f"baseline {path} is missing"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 - corruption is a gate failure
        return None, f"baseline {path} is corrupt: {type(exc).__name__}: {exc}"
    if not isinstance(data, dict) or data.get("version") != 2:
        return None, f"baseline {path} has an unknown schema (expected version 2)"
    if not isinstance(data.get("producers"), dict):
        return None, f"baseline {path} has no producers object"
    return data, ""


def _collect_outputs(producer: Producer, paths: Paths) -> tuple[dict, list[str]]:
    outputs = {}
    failures = []
    for token in producer.outputs:
        path = _resolve_token(token, paths)
        digest = _digest_path(path)
        outputs[token] = digest
        if not digest["exists"]:
            failures.append(
                f"producer {producer.script}: output {token} is missing ({path}); "
                f"regenerate with `{producer.command}`"
            )
        elif digest["files"] == 0 or digest["bytes"] == 0:
            failures.append(
                f"producer {producer.script}: output {token} is empty ({path}); "
                f"regenerate with `{producer.command}`"
            )
    return outputs, failures


def _compare_baseline(
    paths: Paths,
    metrics: dict,
    bootstrap: bool,
    refresh: bool,
    allow_tool_drift: bool,
) -> tuple[dict | None, list[str], list[str]]:
    """Return (new_baseline, failures, notes)."""
    failures: list[str] = []
    notes: list[str] = []
    previous, load_error = _load_baseline(paths.baseline)
    was_corrupt = bool(load_error and paths.baseline.exists())
    if load_error:
        if bootstrap or refresh:
            notes.append(
                f"baseline: {load_error}; rebuilding because "
                f"{'--bootstrap-stamps' if bootstrap else '--refresh-stamps'} is set"
            )
            previous = None
        else:
            failures.append(
                f"baseline: {load_error}; a normal audit requires the tracked "
                "baseline (--bootstrap-stamps creates it explicitly)"
            )
            return None, failures, notes
    if previous is None and not bootstrap and not (refresh and was_corrupt):
        failures.append(
            f"baseline: {paths.baseline} does not exist; first runs fail closed. "
            "Use --bootstrap-stamps to create the tracked baseline explicitly."
        )
        return None, failures, notes

    previous_producers = (previous or {}).get("producers", {})
    previous_infra = (previous or {}).get("infrastructure", {})
    previous_tools = (previous or {}).get("tool_versions", {})
    current_producers: dict = {}
    current_infra: dict = {}
    script_set = set()

    for producer in PRODUCERS:
        script = ROOT / producer.script
        script_set.add(producer.script)
        if not script.is_file():
            failures.append(f"producer {producer.script}: source missing at {script}")
            continue
        sha = _sha256_file(script)
        outputs, output_failures = _collect_outputs(producer, paths)
        failures.extend(output_failures)
        producer_metrics = {
            key: metrics[key] for key in producer.metrics if key in metrics
        }
        current_producers[producer.script] = {
            "sha256": sha,
            "command": producer.command,
            "outputs": outputs,
            "metrics": producer_metrics,
        }
        if previous is None:
            continue
        old = previous_producers.get(producer.script)
        if not isinstance(old, dict):
            if refresh:
                notes.append(
                    f"baseline: new producer {producer.script} accepted by refresh"
                )
            else:
                failures.append(
                    f"baseline: no entry for producer {producer.script}; regenerate "
                    f"with `{producer.command}` then run --refresh-stamps"
                )
            continue
        sha_changed = old.get("sha256") != sha
        old_outputs = old.get("outputs")
        if not isinstance(old_outputs, dict):
            failures.append(
                f"baseline: producer {producer.script} has malformed outputs in "
                f"{paths.baseline}"
            )
            continue
        changed_outputs = []
        for token, digest in outputs.items():
            old_digest = old_outputs.get(token)
            if not isinstance(old_digest, dict):
                if refresh:
                    notes.append(
                        f"baseline: new output {producer.script}:{token} accepted"
                    )
                else:
                    failures.append(
                        f"baseline: producer {producer.script} has no baseline for "
                        f"output {token}; run --refresh-stamps after regeneration"
                    )
                continue
            if digest["files"] < int(old_digest.get("files", 0)):
                failures.append(
                    f"baseline: producer {producer.script} output {token} decreased "
                    f"from {old_digest.get('files')} to {digest['files']} files; "
                    "missing outputs are never accepted"
                )
            elif digest["sha256"] != old_digest.get("sha256"):
                changed_outputs.append(token)
        for token in old_outputs:
            if token not in outputs:
                failures.append(
                    f"baseline: producer {producer.script} no longer declares "
                    f"output {token}; update the producer list deliberately"
                )
        old_metrics = old.get("metrics") if isinstance(old.get("metrics"), dict) else {}
        for key, value in producer_metrics.items():
            old_value = old_metrics.get(key)
            if (
                isinstance(value, int)
                and not isinstance(value, bool)
                and isinstance(old_value, int)
                and value < old_value
            ):
                failures.append(
                    f"baseline: producer {producer.script} metric {key} decreased "
                    f"from {old_value} to {value}"
                )
        if sha_changed or changed_outputs:
            if refresh:
                evidence = []
                newest_all = max(
                    (d["newest_mtime"] for d in outputs.values()), default=0.0
                )
                producer_mtime = script.stat().st_mtime
                for token, digest in outputs.items():
                    old_digest = (
                        old_outputs.get(token) if isinstance(old_outputs, dict) else {}
                    )
                    hash_changed = isinstance(old_digest, dict) and digest[
                        "sha256"
                    ] != old_digest.get("sha256")
                    evidence.append(
                        hash_changed or digest["newest_mtime"] > producer_mtime
                    )
                if sha_changed and not all(evidence):
                    failures.append(
                        f"baseline: {producer.script} changed but its outputs were "
                        "not regenerated (neither newer than the producer nor hash/"
                        "count changed); --refresh-stamps refused"
                    )
                elif sha_changed:
                    notes.append(
                        f"baseline: {producer.script} source drift accepted by "
                        f"refresh (newest output {time.strftime('%Y-%m-%d %H:%M', time.localtime(newest_all))})"
                    )
                if changed_outputs:
                    notes.append(
                        f"baseline: output content changed for {producer.script}: "
                        f"{', '.join(changed_outputs)} (refresh accepted)"
                    )
            else:
                if sha_changed:
                    failures.append(
                        f"baseline: producer {producer.script} changed since the "
                        f"baseline (sha256 {str(old.get('sha256'))[:12]} -> "
                        f"{sha[:12]}); regenerate with `{producer.command}` (or "
                        "make normalize) then run --refresh-stamps"
                    )
                for token in changed_outputs:
                    failures.append(
                        f"baseline: producer {producer.script} output {token} content "
                        "differs from the baseline; regenerate it and run "
                        "--refresh-stamps"
                    )

    for script in sorted(set(previous_producers) - script_set):
        if refresh:
            notes.append(f"baseline: removed producer {script} dropped by refresh")
        else:
            failures.append(
                f"baseline: producer {script} disappeared from PRODUCERS; update the "
                "baseline deliberately with --refresh-stamps"
            )

    for token, command in INFRASTRUCTURE:
        path = _resolve_token(token, paths)
        if not path.is_file():
            failures.append(f"infrastructure: {token} missing ({path})")
            continue
        sha = _sha256_file(path)
        current_infra[token] = {"sha256": sha, "command": command}
        if previous is None:
            continue
        old = previous_infra.get(token)
        if not isinstance(old, dict):
            if refresh:
                notes.append(f"baseline: new infrastructure {token} accepted")
            else:
                failures.append(
                    f"baseline: no infrastructure stamp for {token}; run "
                    "--refresh-stamps"
                )
        elif old.get("sha256") != sha:
            if refresh:
                notes.append(f"baseline: infrastructure change accepted: {token}")
            else:
                failures.append(
                    f"baseline: infrastructure {token} changed since the baseline; "
                    f"regenerate with `{command}` then run --refresh-stamps"
                )
    for token in sorted(set(previous_infra) - {t for t, _ in INFRASTRUCTURE}):
        if refresh:
            notes.append(f"baseline: removed infrastructure {token} dropped by refresh")
        else:
            failures.append(
                f"baseline: infrastructure {token} disappeared from the audit; "
                "update the baseline deliberately"
            )

    current_tools = _probe_tool_versions()
    if previous is not None:
        for name, version in current_tools.items():
            old_version = previous_tools.get(name)
            if old_version != version:
                message = (
                    f"tool version drift: {name}: {old_version!r} -> {version!r}; "
                    "regenerate affected outputs and run --refresh-stamps"
                )
                if allow_tool_drift:
                    notes.append(f"allowed: {message}")
                elif refresh:
                    notes.append(f"baseline: {message} (refresh accepted)")
                else:
                    failures.append(message)
        for name in sorted(set(previous_tools) - set(current_tools)):
            failures.append(f"tool version: {name} disappeared from TOOL_COMMANDS")

    payload = {
        "version": 2,
        "generator": "tools/manifest_audit.py",
        "python": "3.10+",
        "written_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "producers": current_producers,
        "infrastructure": current_infra,
        "tool_versions": current_tools,
        "content": metrics,
    }
    return payload, failures, notes


def _write_json_atomic(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    tmp.replace(path)


def _check_errors_log(
    paths: Paths,
    allow_unexpected: bool,
) -> tuple[list[str], dict]:
    failures: list[str] = []
    summary: dict = {}
    errors_log = paths.extracted / "errors.log"
    if not errors_log.exists():
        failures.append(
            f"errors.log: MISSING at {errors_log}: extracted files exist but the "
            "extractor left no run log; an absent log is not a clean run"
        )
        return failures, summary
    try:
        raw = errors_log.read_bytes()
    except OSError as exc:
        return [f"errors.log: unreadable at {errors_log}: {exc}"], summary
    text = raw.decode("utf-8", errors="replace")
    summary["bytes"] = len(raw)
    filelist = paths.extracted / "filelist.txt"
    filelist_sha = _sha256_file(filelist) if filelist.exists() else "none"
    summary["filelist_sha"] = filelist_sha
    if errors_log.stat().st_mtime < filelist.stat().st_mtime:
        failures.append(
            f"errors.log: STALE at {errors_log} "
            f"({time.strftime('%Y-%m-%d %H:%M', time.localtime(errors_log.stat().st_mtime))}) "
            f"predates filelist.txt "
            f"({time.strftime('%Y-%m-%d %H:%M', time.localtime(filelist.stat().st_mtime))}); "
            "re-run the extractor"
        )
    if len(raw) == 0:
        failures.append(
            f"errors.log: zero-byte log at {errors_log} has no run marker; a bare "
            "empty file is not proof of a clean run. Re-run the extractor."
        )
        return failures, summary
    if not text.strip():
        summary["marker"] = "legacy-whitespace"
        print(
            f"errors.log: whitespace-only legacy log at {errors_log} treated as "
            "clean (next extractor run writes the # run marker)"
        )
        return failures, summary
    lines = text.splitlines()
    header = ERRORS_HEADER_RE.match(lines[0].strip())
    if not header:
        failures.append(
            f"errors.log: missing run marker in {errors_log}; expected "
            "'# run <utc> filelist <sha256> errors <n>'. Re-run the extractor."
        )
        return failures, summary
    marker_sha = header.group("sha")
    marker_n = int(header.group("n"))
    summary["marker"] = "ok"
    summary["marker_filelist_sha"] = marker_sha
    summary["marker_errors"] = marker_n
    if marker_sha != filelist_sha:
        failures.append(
            f"errors.log: run marker filelist sha {marker_sha[:12]} does not match "
            f"current filelist.txt {filelist_sha[:12]}; the log is stale"
        )
    body = [line for line in lines[1:] if line.strip()]
    summary["body_lines"] = len(body)
    if len(body) != marker_n:
        failures.append(
            f"errors.log: run marker says {marker_n} error(s) but body has "
            f"{len(body)} line(s); the log is inconsistent"
        )
    known: list[str] = []
    unexpected: list[str] = []
    for line in body:
        parts = line.split(": ")
        asset = parts[1].split(".")[0] if len(parts) > 1 else ""
        if (
            UNSUPPORTED_ANIM_MARKER in line
            and any(
                t in line
                for t in ("UBlendSpace", "UBlendSpace1D", "UAimOffsetBlendSpace")
            )
            and asset in KNOWN_UNSUPPORTED_ANIM
        ):
            known.append(asset)
        else:
            unexpected.append(line)
    summary["known_unsupported"] = len(known)
    summary["unexpected"] = len(unexpected)
    print(
        f"errors.log: {len(known)} known-unsupported BlendSpace, "
        f"{len(unexpected)} unexpected"
    )
    for line in unexpected[:20]:
        print(line)
    if unexpected and not allow_unexpected:
        failures.append(
            f"errors.log: {len(unexpected)} unexpected failure line(s) in {errors_log}"
        )
    elif not known and marker_n > 0 and not allow_unexpected:
        failures.append(
            f"errors.log: {marker_n} failure(s) but none match the known-unsupported "
            "BlendSpace allowlist"
        )
    return failures, summary


def _print_freshness(paths: Paths, allow_stale: bool) -> list[str]:
    failures: list[str] = []
    for name, src_tokens, out_tokens in FRESHNESS_GROUPS:
        newest_src = 0.0
        for token in src_tokens:
            newest_src = max(newest_src, _newest_mtime(_resolve_token(token, paths)))
        oldest_out: float | None = None
        n_out = 0
        for token in out_tokens:
            root = _resolve_token(token, paths)
            files = _payload_files(root)
            for path in files:
                try:
                    mtime = path.stat().st_mtime
                except OSError:
                    continue
                n_out += 1
                if oldest_out is None or mtime < oldest_out:
                    oldest_out = mtime
        if n_out == 0 or oldest_out is None:
            print(f"freshness {name}: NO GENERATED OUTPUTS (stale by absence)")
            if not allow_stale:
                failures.append(f"stale generated group {name}: no outputs")
            continue
        stale = oldest_out < newest_src
        fmt = lambda t: time.strftime("%Y-%m-%d %H:%M", time.localtime(t)) if t else "-"
        print(
            f"freshness {name}: {'STALE' if stale else 'fresh'} "
            f"(newest src {fmt(newest_src)}, oldest out {fmt(oldest_out)}, "
            f"{n_out} outputs)"
        )
        if stale and not allow_stale:
            failures.append(
                f"stale generated group {name}: oldest output predates newest source"
            )
    return failures


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--extracted", default="extracted")
    ap.add_argument("--generated", default=str(ROOT / "game" / "data" / "generated"))
    ap.add_argument("--assets", default=str(ROOT / "game" / "assets"))
    ap.add_argument("--steam", default=str(DEFAULT_STEAM))
    ap.add_argument("--manifest", default=str(STEAM_MANIFEST))
    ap.add_argument(
        "--baseline",
        "--stamps",
        dest="baseline",
        default=str(DEFAULT_BASELINE),
        help="Tracked producer/output baseline (default tools/audit_baseline.json).",
    )
    ap.add_argument(
        "--allowlists",
        default=str(DEFAULT_ALLOWLISTS),
        help="Known case-normalization and undumped-path allowlists.",
    )
    ap.add_argument(
        "--bootstrap-stamps",
        action="store_true",
        help="Explicit first run: create the baseline after all gates pass.",
    )
    ap.add_argument(
        "--refresh-stamps",
        action="store_true",
        help="Explicit maintenance: accept regenerated producer/output drift.",
    )
    ap.add_argument("--min-coverage", type=float, default=0.99)
    ap.add_argument("--min-exact-coverage", type=float, default=0.99)
    ap.add_argument("--min-dumped", type=int, default=0)
    ap.add_argument(
        "--stage-min",
        action="append",
        default=[],
        metavar="STAGE=COUNT",
        help="Override a stage floor, e.g. --stage-min raw=120. Repeatable.",
    )
    ap.add_argument(
        "--require-imports",
        action="store_true",
        help="Separate Godot import gate: require .import sidecars + .translation.",
    )
    ap.add_argument("--min-imports", type=int, default=4000)
    ap.add_argument(
        "--allow-stale",
        action="store_true",
        help="Explicit debug opt-out: do not fail mtime-stale groups.",
    )
    ap.add_argument(
        "--allow-unexpected-errors",
        action="store_true",
        help="Explicit debug opt-out: do not fail unexpected errors.log lines.",
    )
    ap.add_argument(
        "--allow-tool-drift",
        action="store_true",
        help="Explicit debug opt-out: do not fail external tool version drift.",
    )
    args = ap.parse_args()
    if args.bootstrap_stamps and args.refresh_stamps:
        raise SystemExit(
            "--bootstrap-stamps and --refresh-stamps are mutually exclusive"
        )

    paths = Paths(
        extracted=Path(args.extracted),
        generated=Path(args.generated),
        assets=Path(args.assets),
        steam=Path(args.steam),
        manifest=Path(args.manifest),
        baseline=Path(args.baseline),
        allowlists=Path(args.allowlists),
    )
    failures: list[str] = []
    metrics: dict = {}

    filelist = paths.extracted / "filelist.txt"
    if not filelist.exists():
        raise SystemExit(f"missing {filelist}")
    try:
        allowlists = _load_allowlists(paths.allowlists)
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"cannot load allowlists {paths.allowlists}: {exc}")

    mounted_exact = set()
    for line in filelist.read_text().splitlines():
        if line:
            mounted_exact.add(line.split("\t")[0])
    mounted_ci = {p.lower() for p in mounted_exact}

    manifest_lines = [
        line.split("\t")[0].strip()
        for line in paths.manifest.read_text(errors="replace").splitlines()
    ]
    all_tat = [p for p in manifest_lines if p.startswith("TAT/")]
    ubulk_entries = [p for p in all_tat if p.endswith(".ubulk")]
    pak_containers = [p for p in all_tat if p.lower().endswith(".pak")]
    covered = [
        p
        for p in all_tat
        if not p.lower().endswith(".pak")
        and not p.endswith((".ubulk", ".uexp", ".uptnl"))
    ]

    missing_ci = [p for p in covered if p.lower() not in mounted_ci]
    resolved = len(covered) - len(missing_ci)
    missing_exact = [p for p in covered if p not in mounted_exact]
    allowlisted_case = [p for p in missing_exact if p in allowlists["case_only"]]
    unexpected_case = [p for p in missing_exact if p not in allowlists["case_only"]]
    exact_effective = (resolved - len(unexpected_case)) / max(1, len(covered))
    raw_exact = (len(covered) - len(missing_exact)) / max(1, len(covered))
    cov = resolved / max(1, len(covered))

    missing_ubulk_ci = [p for p in ubulk_entries if p.lower() not in mounted_ci]
    missing_ubulk_exact = [p for p in ubulk_entries if p not in mounted_exact]
    unexpected_ubulk = [
        p for p in missing_ubulk_exact if p not in allowlists["case_only_ubulk"]
    ]

    disk_index = _build_disk_index(paths.extracted)
    disk_missing = [p for p in covered if _stem(p) not in disk_index]
    unexpected_disk = [p for p in disk_missing if p not in allowlists["disk_missing"]]

    print(
        f"Manifest TAT entries: {len(all_tat)} ({len(covered)} payload, "
        f"{len(ubulk_entries)} .ubulk, {len(pak_containers)} pak)"
    )
    print(
        f"Pak containers excluded: {len(pak_containers)} "
        f"({', '.join(pak_containers) or '-'})"
    )
    print(
        f"Mount/path consistency (case-insensitive, pak excluded): "
        f"{resolved}/{len(covered)} ({cov:.1%})"
    )
    print(
        f"Case-sensitive parity: raw {len(covered) - len(missing_exact)}/"
        f"{len(covered)} ({raw_exact:.1%}), allowlisted {len(allowlisted_case)}/"
        f"{len(allowlists['case_only'])}, unexpected {len(unexpected_case)}; "
        f"effective {exact_effective:.1%}"
    )
    print(
        f"Disk-backed coverage: {len(covered) - len(disk_missing)}/{len(covered)} "
        f"({(len(covered) - len(disk_missing)) / max(1, len(covered)):.1%}), "
        f"allowlisted missing {len(allowlists['disk_missing'])}, "
        f"unexpected {len(unexpected_disk)}"
    )
    print(
        f"UBULK companions: {len(ubulk_entries)} manifest, "
        f"{len(missing_ubulk_ci)} case-insensitive missing, "
        f"{len(unexpected_ubulk)} unexpected exact-case missing"
    )
    for label, rows in (
        ("MISSING (case-insensitive)", missing_ci),
        ("UNEXPECTED CASE-ONLY", unexpected_case),
        ("UNEXPECTED DISK MISSING", unexpected_disk),
        ("UNEXPECTED UBULK", unexpected_ubulk),
    ):
        for path in rows[:10]:
            print(f"{label}: {path}")

    if cov < args.min_coverage:
        failures.append(
            f"coverage: mount/path consistency {cov:.1%} < "
            f"{args.min_coverage:.1%} ({resolved}/{len(covered)})"
        )
    if exact_effective < args.min_exact_coverage:
        failures.append(
            f"coverage: case-sensitive effective parity {exact_effective:.1%} < "
            f"{args.min_exact_coverage:.1%}; add evidence to "
            f"{paths.allowlists} only for known normalizations"
        )
    if unexpected_case:
        failures.append(
            f"coverage: {len(unexpected_case)} exact-case misses are not in the "
            f"allowlist, e.g. {unexpected_case[:3]}"
        )
    if unexpected_disk:
        failures.append(
            f"coverage: {len(unexpected_disk)} manifest paths have no disk artifact "
            f"and are not allowlisted, e.g. {unexpected_disk[:3]}"
        )
    if missing_ubulk_ci:
        failures.append(
            f"coverage: {len(missing_ubulk_ci)} .ubulk companions missing from "
            f"filelist, e.g. {missing_ubulk_ci[:3]}"
        )
    if unexpected_ubulk:
        failures.append(
            f"coverage: {len(unexpected_ubulk)} .ubulk companions have unexpected "
            f"case mismatches, e.g. {unexpected_ubulk[:3]}"
        )

    stage_overrides = {}
    for item in args.stage_min:
        if "=" not in item:
            raise SystemExit(f"--stage-min wants STAGE=COUNT, got {item!r}")
        key, value = item.split("=", 1)
        if key not in DUMP_STAGES:
            raise SystemExit(f"--stage-min unknown stage {key!r}")
        stage_overrides[key] = int(value)
    stage_counts = {}
    sidecar_counts = {}
    for stage in DUMP_STAGES:
        root = paths.extracted / stage
        payload = _payload_files(root)
        sidecars = (
            sum(1 for p in root.rglob("*") if p.is_file()) - len(payload)
            if root.is_dir()
            else 0
        )
        stage_counts[stage] = len(payload)
        sidecar_counts[stage] = sidecars
        minimum = stage_overrides.get(stage, STAGE_MIN_FILES[stage])
        print(
            f"stage {stage}: {len(payload)} payload files (min {minimum}, "
            f"{sidecars} importer/sidecar files excluded)"
        )
        if len(payload) < minimum:
            failures.append(
                f"stage {stage}: expected >= {minimum} payload files under {root}, "
                f"found {len(payload)} (import .sidecars={sidecars} do not count)"
            )
    dumped = sum(stage_counts.values())
    print(f"Payload files written to {paths.extracted}: {dumped}")
    if dumped < args.min_dumped:
        failures.append(
            f"dumped: {dumped} payload files < --min-dumped {args.min_dumped}"
        )

    imports = sum(
        1
        for root in (paths.extracted / "assets", paths.assets / "ue")
        if root.is_dir()
        for p in root.rglob("*.import")
        if p.is_file()
    )
    translations = (
        sum(1 for p in (paths.generated / "localization").rglob("*.translation"))
        if (paths.generated / "localization").is_dir()
        else 0
    )
    print(
        f"godot-import (separate gate): {imports} .import sidecars, "
        f"{translations} .translation files; run tools/reimport_assets.sh"
    )
    if args.require_imports:
        if imports < args.min_imports:
            failures.append(
                f"godot-import: expected >= {args.min_imports} .import sidecars under "
                f"{paths.extracted / 'assets'} and {paths.assets / 'ue'}, found "
                f"{imports}; run tools/reimport_assets.sh"
            )
        if translations < 8:
            failures.append(
                f"godot-import: expected >= 8 .translation files under "
                f"{paths.generated / 'localization'}, found {translations}; run "
                "tools/reimport_assets.sh"
            )

    missing_engine = [p for p in REQUIRED_ENGINE_DEPS if p not in mounted_exact]
    n_engine = sum(1 for p in mounted_exact if p.startswith("Engine/Content/"))
    print(f"Engine/Content files mounted: {n_engine}")
    for path in REQUIRED_ENGINE_DEPS:
        print(f"engine-dep {'OK' if path not in missing_engine else 'MISSING'}: {path}")
    if missing_engine:
        failures.append(f"required Engine deps not mounted: {missing_engine}")

    error_failures, errors_summary = _check_errors_log(
        paths, args.allow_unexpected_errors
    )
    failures.extend(error_failures)

    failures.extend(_print_freshness(paths, args.allow_stale))

    checks = [
        _run_check(_check_levels, paths.generated, metrics),
        _run_check(_check_contracts, paths.generated, metrics),
        _run_check(_check_tables, paths.generated, metrics),
        _run_check(_check_materials, paths.generated, paths.assets, metrics),
        _run_check(_check_containers, paths.generated, metrics),
        _run_check(_check_decals, paths.generated, metrics),
        _run_check(_check_devices, paths.generated, metrics),
        _run_check(_check_animations, paths.generated, paths.assets, metrics),
        _run_check(_check_audio, paths.generated, paths.assets, metrics),
        _run_check(_check_localization, paths.generated, metrics),
        _run_check(_check_videos, paths.generated, paths.assets, metrics),
        _run_check(_check_scene_variants, paths.generated, metrics),
        _run_check(_check_niagara, paths.generated, metrics),
    ]
    for check in checks:
        print(check.line())
        failures.extend(check.problems)

    failures.extend(_producer_coverage_failures())

    baseline_payload, baseline_failures, baseline_notes = _compare_baseline(
        paths,
        metrics,
        args.bootstrap_stamps,
        args.refresh_stamps,
        args.allow_tool_drift,
    )
    for note in baseline_notes:
        print(note)
    failures.extend(baseline_failures)

    if failures:
        print(f"AUDIT FAILED: {len(failures)} failure(s)")
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1

    if baseline_payload is not None and (args.bootstrap_stamps or args.refresh_stamps):
        baseline_payload["coverage"] = {
            "manifest_tat": len(all_tat),
            "covered": len(covered),
            "resolved": resolved,
            "exact_raw": len(covered) - len(missing_exact),
            "case_allowlisted": len(allowlisted_case),
            "disk_missing_allowlisted": len(disk_missing),
            "ubulk": len(ubulk_entries),
        }
        _write_json_atomic(paths.baseline, baseline_payload)
        print(f"baseline -> {paths.baseline}")
    elif args.bootstrap_stamps or args.refresh_stamps:
        print("baseline: not written because the audit failed")
    else:
        print(f"baseline: matches {paths.baseline}")

    _ = errors_summary
    print("AUDIT PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
