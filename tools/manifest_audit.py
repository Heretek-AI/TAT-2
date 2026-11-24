#!/usr/bin/env python3
"""Hard content gate for the extracted snapshot and generated data tree.

Three independent layers, all fail-closed:

1. **Mount / path consistency** -- compare the Steam manifest against
   ``extracted/filelist.txt`` case-insensitively (the previous exact-case
   comparison counted case-only differences as missing) and exclude the pak
   container from the denominator. The historic 99.4 % figure is the exact-case
   parity diagnostic, not an extraction-completeness score.

2. **Content assertions** -- every generated domain (levels, contracts, tables,
   materials, containers, decals, devices, animations, audio, localisation,
   videos, scene variants, Niagara) must meet a measured minimum. A produced
   tree that silently lost a pipeline leg fails by name and count.

3. **Producer stamps** -- ``build/audit/producer_stamps.json`` records the
   sha256 of every producer plus the output counts observed on a successful
   audit. A producer whose source changed after its outputs were generated
   fails the gate even when a git checkout rewrote every mtime. Regenerate with
   ``make normalize`` (or the named ``tools/parse_*.py``) and then re-run with
   ``--refresh-stamps``.

``extracted/errors.log`` is mandatory whenever extraction produced output: an
absent log is no longer "clean", and a log older than ``filelist.txt`` fails.
The enumerated CUE4Parse BlendSpace conversion failures stay allowlisted; any
other current-run line fails when ``--fail-on-errors`` is set (the Makefile
sets it).

Run ``python3 tools/manifest_audit.py --help`` for the escape hatches.
"""

import argparse
import hashlib
import json
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

STEAM_MANIFEST = (
    Path.home()
    / ".local/share/Steam/steamapps/common/Thick As Thieves/Manifest_UFSFiles_Win64.txt"
)

GENERATED = ROOT / "game" / "data" / "generated"
ASSETS = ROOT / "game" / "assets"
DEFAULT_STAMPS = ROOT / "build" / "audit" / "producer_stamps.json"

# P1-1: Engine carriers referenced by shipped levels must be mounted.
# WorldGridMaterial is the proven dangling bind (VFX_SkySearchLight_Mesh);
# BasicShapes are the round-2 mesh repair set.
REQUIRED_ENGINE_DEPS = [
    "Engine/Content/EngineMaterials/WorldGridMaterial.uasset",
    "Engine/Content/BasicShapes/Cube.uasset",
    "Engine/Content/BasicShapes/Plane.uasset",
    "Engine/Content/BasicShapes/Sphere.uasset",
    "Engine/Content/BasicShapes/Cone.uasset",
    "Engine/Content/BasicShapes/Cylinder.uasset",
]

# CUE4Parse's AnimationExporter has no BlendSpace support
# (UBlendSpace / UBlendSpace1D / UAimOffsetBlendSpace). These 14 shipped assets
# are an enumerated converter limitation, not a pipeline failure. The list is
# exact: any new or differently-shaped error still fails --fail-on-errors.
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

DUMP_STAGES = ("raw", "json", "assets", "audio", "audio-meta")

# A stage that exported nothing was the old failure mode; a tree that lost 99 %
# of its files still passed. These floors are the measured 2026-11-24 snapshot
# (raw 141, json 12541, assets 11251, audio 5019, audio-meta 1441) with modest
# slack, so a partial or wiped extract cannot masquerade as healthy. Override a
# single stage with ``--stage-min raw=120`` when a smaller QA tree is intended.
STAGE_MIN_FILES = {
    "raw": 120,
    "json": 12000,
    "assets": 11000,
    "audio": 5000,
    "audio-meta": 1200,
}

# (group, source dirs under extracted/, generated outputs). A group is stale
# when its oldest generated output predates its newest extracted source.
FRESHNESS_GROUPS = (
    ("levels", ["json/Maps"], ["../game/data/generated/levels"]),
    (
        "gameplay",
        ["json/Missions", "json/Gameplay", "json/AI", "json/Character"],
        ["../game/data/generated/gameplay"],
    ),
    (
        "tables",
        [
            "json/Gameplay",
            "json/AI",
            "json/Missions",
            "json/Character",
            "json/Core",
            "json/StringTables",
            "json/UI",
            "json/Audio",
        ],
        ["../game/data/generated/tables"],
    ),
    (
        "materials",
        ["assets"],
        [
            "../game/data/generated/materials.json",
            "../game/data/generated/mesh_materials.json",
            "../game/data/generated/mesh_materials_provenance.json",
        ],
    ),
    (
        "audio",
        ["audio", "audio-meta"],
        [
            "../game/data/generated/audio_events.json",
            "../game/data/generated/audio_library.json",
        ],
    ),
    ("weather", ["json"], ["../game/data/generated/weather"]),
    ("vfx", ["json"], ["../game/data/generated/vfx"]),
)


@dataclass(frozen=True)
class Producer:
    """A pipeline producer whose source must not drift from its outputs."""

    script: str
    command: str
    outputs: tuple[str, ...]
    metrics: tuple[str, ...] = ()


# At least the producers named in the audit design; parse_gameplay is included
# because it is a NORMALIZERS entry and owns part of generated/gameplay.
PRODUCERS = (
    Producer(
        "tools/parse_tables.py",
        "python3 tools/parse_tables.py",
        (
            "game/data/generated/levels",
            "game/data/generated/tables",
            "game/data/generated/gameplay",
            "game/data/generated/gameplay/devices.json",
            "game/data/generated/scene_variants.json",
        ),
        ("levels", "tables", "scene_variants", "devices_total", "devices_families"),
    ),
    Producer(
        "tools/parse_gameplay.py",
        "python3 tools/parse_gameplay.py",
        ("game/data/generated/gameplay",),
    ),
    Producer(
        "tools/parse_materials.py",
        "python3 tools/parse_materials.py",
        (
            "game/data/generated/materials.json",
            "game/data/generated/mesh_materials.json",
            "game/data/generated/mesh_materials_provenance.json",
        ),
        ("materials_entries", "materials_albedo"),
    ),
    Producer(
        "tools/parse_contracts.py",
        "python3 tools/parse_contracts.py",
        ("game/data/generated/gameplay/contracts.json",),
        ("contracts", "contracts_has_loot_goals"),
    ),
    Producer(
        "tools/parse_loot.py",
        "python3 tools/parse_loot.py",
        ("game/data/generated/gameplay/loot_actors.json",),
    ),
    Producer(
        "tools/parse_spawners.py",
        "python3 tools/parse_spawners.py",
        ("game/data/generated/gameplay/spawners.json",),
    ),
    Producer(
        "tools/parse_containers.py",
        "python3 tools/parse_containers.py",
        ("game/data/generated/gameplay/containers.json",),
        ("containers",),
    ),
    Producer(
        "tools/parse_interactables.py",
        "python3 tools/parse_interactables.py",
        ("game/data/generated/gameplay/interactables.json",),
    ),
    Producer(
        "tools/parse_weather.py",
        "python3 tools/parse_weather.py",
        ("game/data/generated/weather",),
    ),
    Producer(
        "tools/parse_vfx.py",
        "python3 tools/parse_vfx.py",
        ("game/data/generated/vfx",),
    ),
    Producer(
        "tools/extract_audio.py",
        "python3 tools/extract_audio.py",
        ("game/assets/ue/audio",),
    ),
    Producer(
        "tools/convert_wwise.py",
        "python3 tools/convert_wwise.py",
        (
            "game/assets/ue/audio/wwise",
            "game/data/generated/audio_library.json",
            "game/data/generated/audio_events.json",
        ),
        ("audio_clips", "audio_failed"),
    ),
    Producer(
        "tools/parse_locres.py",
        "python3 tools/parse_locres.py",
        ("game/data/generated/localization",),
        ("loc_csv", "loc_translation"),
    ),
    Producer(
        "tools/convert_videos.py",
        "python3 tools/convert_videos.py",
        ("game/assets/ue/videos", "game/data/generated/videos.json"),
        ("videos_ogv", "videos_manifest"),
    ),
    Producer(
        "tools/usd_to_gltf.py",
        "make anims  # blender --background --python tools/usd_to_gltf.py ...",
        (
            "game/assets/ue/Anims",
            "game/data/generated/anims_manifest.json",
        ),
        ("anims_ok", "anims_fail", "anims_entries", "anims_total"),
    ),
)


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


def _count_files(root: Path, pattern: str = "*") -> int:
    if root.is_file():
        return 1
    if not root.is_dir():
        return 0
    return sum(1 for p in root.rglob(pattern) if p.is_file())


def _load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _albedo_texture(entry) -> str:
    """Return the non-empty albedo texture path for a material entry."""
    if not isinstance(entry, dict):
        return ""
    texs = entry.get("texs")
    if isinstance(texs, dict):
        albedo = texs.get("albedo")
        if isinstance(albedo, str) and albedo.strip():
            return albedo.strip()
    # Tolerate an older/flat schema, but materials.json today nests under texs.
    albedo = entry.get("albedo")
    if isinstance(albedo, str) and albedo.strip():
        return albedo.strip()
    return ""


_LEVEL_CACHE: dict[str, list] = {}


def _levels(levels_dir: Path) -> list:
    """Load every .tatlevel.json once (decals, Niagara and containers share it)."""
    key = str(levels_dir.resolve())
    if key not in _LEVEL_CACHE:
        rows = []
        for path in sorted(levels_dir.rglob("*.tatlevel.json")):
            rows.append((path, _load_json(path)))
        _LEVEL_CACHE[key] = rows
    return _LEVEL_CACHE[key]


def _check_levels(gen: Path, metrics: dict) -> ContentCheck:
    found = _count_files(gen / "levels", "*.tatlevel.json")
    metrics["levels"] = found
    problems = []
    if found < 107:
        problems.append(
            f"levels: expected >= 107 .tatlevel.json under {gen / 'levels'}, "
            f"found {found}; regenerate with python3 tools/parse_tables.py"
        )
    return ContentCheck("levels", not problems, {"files": found, "min": 107}, problems)


def _check_contracts(gen: Path, metrics: dict) -> ContentCheck:
    path = gen / "gameplay" / "contracts.json"
    data = _load_json(path)
    contracts = data.get("contracts") if isinstance(data, dict) else None
    count = len(contracts) if isinstance(contracts, list) else -1
    has_goals = isinstance(data, dict) and "mission_loot_goals" in data
    metrics["contracts"] = count
    metrics["contracts_has_loot_goals"] = 1 if has_goals else 0
    problems = []
    if count != 16:
        problems.append(
            f"contracts: expected exactly 16 entries in {path}['contracts'], "
            f"found {count}; regenerate with python3 tools/parse_contracts.py"
        )
    if not has_goals:
        problems.append(
            f"contracts: expected key 'mission_loot_goals' in {path}; "
            "the producer emits it but the output predates the change -- run "
            "python3 tools/parse_contracts.py"
        )
    return ContentCheck(
        "contracts",
        not problems,
        {"entries": count, "expected": 16, "mission_loot_goals": has_goals},
        problems,
    )


def _check_tables(gen: Path, metrics: dict) -> ContentCheck:
    found = _count_files(gen / "tables", "*.json")
    metrics["tables"] = found
    problems = []
    if found < 144:
        problems.append(
            f"tables: expected >= 144 JSON files under {gen / 'tables'}, "
            f"found {found}; regenerate with python3 tools/parse_tables.py"
        )
    return ContentCheck("tables", not problems, {"files": found, "min": 144}, problems)


def _check_materials(gen: Path, metrics: dict) -> ContentCheck:
    path = gen / "materials.json"
    data = _load_json(path)
    entries = data if isinstance(data, dict) else {}
    with_albedo = sum(1 for value in entries.values() if _albedo_texture(value))
    metrics["materials_entries"] = len(entries)
    metrics["materials_albedo"] = with_albedo
    problems = []
    if len(entries) < 1620:
        problems.append(
            f"materials: expected >= 1620 entries in {path}, "
            f"found {len(entries)}; regenerate with python3 tools/parse_materials.py"
        )
    if with_albedo < 1370:
        problems.append(
            f"materials: expected >= 1370 entries with a non-empty albedo texture "
            f"(texs.albedo) in {path}, found {with_albedo}; regenerate with "
            "python3 tools/parse_materials.py"
        )
    return ContentCheck(
        "materials",
        not problems,
        {
            "entries": len(entries),
            "min_entries": 1620,
            "with_albedo": with_albedo,
            "min_albedo": 1370,
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
            f"containers: expected 5 container Blueprint classes in {path}['classes'], "
            f"found {len(class_names)}; regenerate with python3 tools/parse_containers.py"
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
    found = sum(
        len(level.get("decals") or []) for _path, level in _levels(gen / "levels")
    )
    metrics["decals"] = found
    problems = []
    if found < 670:
        problems.append(
            f"decals: expected >= 670 decal records summed across "
            f"{gen / 'levels'}, found {found}; regenerate with "
            "python3 tools/parse_tables.py"
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
            "regenerate with python3 tools/parse_tables.py"
        )
    if family_count != 21:
        problems.append(
            f"devices: expected exactly 21 families in {path}, found {family_count}; "
            "regenerate with python3 tools/parse_tables.py"
        )
    if summed != total:
        problems.append(
            f"devices: family counts sum to {summed}, total field says {total!r} in "
            f"{path}; regenerate with python3 tools/parse_tables.py"
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


def _check_animations(gen: Path, metrics: dict) -> ContentCheck:
    path = gen / "anims_manifest.json"
    data = _load_json(path)
    ok = data.get("ok")
    fail = data.get("fail")
    total = data.get("total")
    entries = data.get("entries")
    n_entries = len(entries) if isinstance(entries, list) else -1
    metrics["anims_ok"] = ok
    metrics["anims_fail"] = fail
    metrics["anims_total"] = total
    metrics["anims_entries"] = n_entries
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
    return ContentCheck(
        "animations",
        not problems,
        {"ok": ok, "min_ok": 995, "fail": fail, "entries": n_entries, "total": total},
        problems,
    )


def _check_audio(gen: Path, metrics: dict) -> ContentCheck:
    path = gen / "audio_library.json"
    data = _load_json(path)
    counts = data.get("counts") if isinstance(data, dict) else None
    counts = counts if isinstance(counts, dict) else {}
    clips = counts.get("clips")
    failed = counts.get("failed")
    failures = data.get("failures") if isinstance(data, dict) else None
    n_failures = len(failures) if isinstance(failures, list) else -1
    metrics["audio_clips"] = clips
    metrics["audio_failed"] = failed
    metrics["audio_failure_records"] = n_failures
    problems = []
    if not isinstance(clips, int) or clips < 5018:
        problems.append(
            f"audio: expected counts.clips >= 5018 in {path}, found {clips!r}; "
            "regenerate with python3 tools/extract_audio.py && "
            "python3 tools/convert_wwise.py"
        )
    if failed != 0:
        problems.append(
            f"audio: expected counts.failed == 0 in {path}, found {failed!r}; "
            "inspect failures and regenerate python3 tools/convert_wwise.py"
        )
    if n_failures != 0:
        problems.append(
            f"audio: expected an empty failures list in {path}, "
            f"found {n_failures} records; regenerate python3 tools/convert_wwise.py"
        )
    return ContentCheck(
        "audio",
        not problems,
        {
            "clips": clips,
            "min_clips": 5018,
            "failed": failed,
            "failure_records": n_failures,
        },
        problems,
    )


def _check_localization(gen: Path, metrics: dict) -> ContentCheck:
    root = gen / "localization"
    csv_files = _count_files(root, "*.csv")
    translations = _count_files(root, "*.translation")
    metrics["loc_csv"] = csv_files
    metrics["loc_translation"] = translations
    problems = []
    if csv_files != 8:
        problems.append(
            f"localization: expected exactly 8 .csv files under {root}, "
            f"found {csv_files}; regenerate with python3 tools/parse_locres.py"
        )
    if translations != 8:
        problems.append(
            f"localization: expected exactly 8 .translation files under {root}, "
            f"found {translations}; reimport the CSVs or run "
            "python3 tools/parse_locres.py"
        )
    return ContentCheck(
        "localization",
        not problems,
        {"csv": csv_files, "translation": translations, "expected": 8},
        problems,
    )


def _check_videos(gen: Path, assets: Path, metrics: dict) -> ContentCheck:
    video_dir = assets / "ue" / "videos"
    ogv = _count_files(video_dir, "*.ogv")
    manifest = _load_json(gen / "videos.json")
    entries = len(manifest) if isinstance(manifest, list) else -1
    metrics["videos_ogv"] = ogv
    metrics["videos_manifest"] = entries
    problems = []
    if ogv != 15:
        problems.append(
            f"videos: expected exactly 15 .ogv files under {video_dir}, "
            f"found {ogv}; regenerate with python3 tools/convert_videos.py"
        )
    if entries != 15:
        problems.append(
            f"videos: expected exactly 15 entries in {gen / 'videos.json'}, "
            f"found {entries}; regenerate with python3 tools/convert_videos.py"
        )
    return ContentCheck(
        "videos",
        not problems,
        {"ogv": ogv, "manifest": entries, "expected": 15},
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
            "regenerate with python3 tools/parse_tables.py"
        )
    if n_variants != 222 or n_variants != count:
        problems.append(
            f"scene variants: expected 222 records in {path}['variants'], "
            f"found {n_variants} (count field {count!r}); regenerate with "
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
        len(level.get("niagara") or []) for _path, level in _levels(gen / "levels")
    )
    metrics["niagara"] = found
    problems = []
    if found < 3695:
        problems.append(
            f"niagara: expected >= 3695 placement records summed across "
            f"{gen / 'levels'}, found {found}; regenerate with "
            "python3 tools/parse_tables.py"
        )
    return ContentCheck(
        "niagara", not problems, {"records": found, "min": 3695}, problems
    )


def _run_check(fn, *args) -> ContentCheck:
    """Run one content assertion, turning a bad/missing output into a failure."""
    name = fn.__name__.removeprefix("_check_")
    try:
        return fn(*args)
    except Exception as exc:  # noqa: BLE001 - the message is the diagnostic
        return ContentCheck(
            name,
            False,
            {},
            [f"{name}: {type(exc).__name__}: {exc}"],
        )


def _newest_mtime(root: Path) -> float:
    latest = 0.0
    if not root.exists():
        return latest
    # Godot writes .import sidecars next to the extracted sources; they are
    # importer artefacts, not extraction output, and must not make the materials
    # group look stale every time the project is opened.
    ignored_suffixes = {".import", ".uid"}
    for p in root.rglob("*"):
        try:
            if (
                p.is_file()
                and p.suffix not in ignored_suffixes
                and not p.name.startswith(".")
            ):
                m = p.stat().st_mtime
                latest = max(latest, m)
        except OSError:
            continue
    return latest


def _producer_observed(producer: Producer, metrics: dict) -> dict:
    outputs = {}
    for rel in producer.outputs:
        path = ROOT / rel
        outputs[rel] = _count_files(path)
    observed = {key: metrics[key] for key in producer.metrics if key in metrics}
    return {"output_files": outputs, "metrics": observed}


def _load_stamps(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 - corrupt stamp must be explicit
        raise SystemExit(
            f"cannot read producer stamps {path}: {exc}; "
            "re-run with --refresh-stamps after verifying the tree"
        )
    if not isinstance(data, dict) or not isinstance(data.get("producers"), dict):
        raise SystemExit(
            f"producer stamps {path} have an unknown schema; "
            "re-run with --refresh-stamps after verifying the tree"
        )
    return data


def _write_json_atomic(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    tmp.replace(path)


def _check_stamps(
    stamp_path: Path, metrics: dict, refresh: bool
) -> tuple[list[str], dict, str]:
    """Compare producer sha256 stamps and return (failures, payload, status)."""
    failures: list[str] = []
    refreshed: list[str] = []
    previous = _load_stamps(stamp_path)
    previous_producers = (previous or {}).get("producers", {})
    current = {}
    for producer in PRODUCERS:
        script = ROOT / producer.script
        if not script.is_file():
            failures.append(
                f"producer stamps: {producer.script} is missing (expected {script}); "
                "restore it before auditing"
            )
            continue
        digest = _sha256(script)
        observed = _producer_observed(producer, metrics)
        current[producer.script] = {
            "sha256": digest,
            "command": producer.command,
            **observed,
        }
        if previous is None:
            continue
        old = previous_producers.get(producer.script)
        if not isinstance(old, dict):
            if refresh:
                refreshed.append(producer.script)
            else:
                failures.append(
                    f"producer stamps: no stamp for {producer.script}; regenerate "
                    f"with `{producer.command}` (or make normalize) then re-run the "
                    "audit with --refresh-stamps"
                )
            continue
        if old.get("sha256") != digest:
            message = (
                f"producer stamps: {producer.script} changed since its outputs were "
                f"stamped (sha256 {str(old.get('sha256'))[:12]} -> {digest[:12]}); "
                f"regenerate with `{producer.command}` (or make normalize) then "
                "re-run with --refresh-stamps"
            )
            if refresh:
                refreshed.append(producer.script)
            else:
                failures.append(message)
    if previous is None:
        status = "first run: no stamps, writing after a green audit"
    elif refresh:
        status = (
            "refreshed via --refresh-stamps (escape hatch)"
            if not refreshed
            else f"refreshed via --refresh-stamps: {', '.join(refreshed)}"
        )
    elif failures:
        status = f"producer drift: {len(failures)} failure(s)"
    else:
        status = f"{len(current)} producers match {stamp_path}"
    payload = {
        "version": 1,
        "generator": "tools/manifest_audit.py",
        "written_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "producers": current,
        "content": metrics,
    }
    return failures, payload, status


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--extracted", default="extracted")
    ap.add_argument("--manifest", default=str(STEAM_MANIFEST))
    ap.add_argument("--generated", default=str(GENERATED))
    ap.add_argument("--assets", default=str(ASSETS))
    ap.add_argument(
        "--stamps",
        default=str(DEFAULT_STAMPS),
        help="Producer sha256 stamp file (default: build/audit/producer_stamps.json).",
    )
    ap.add_argument(
        "--refresh-stamps",
        action="store_true",
        help="Explicit escape hatch: accept changed producer sources and rewrite "
        "the stamps after the content assertions pass.",
    )
    ap.add_argument("--min-coverage", type=float, default=0.0)
    ap.add_argument(
        "--min-dumped",
        type=int,
        default=0,
        help="Fail if total dumped files across all stages fall below this.",
    )
    ap.add_argument(
        "--stage-min",
        action="append",
        default=[],
        metavar="STAGE=COUNT",
        help="Override a stage floor, e.g. --stage-min raw=120. Repeatable.",
    )
    ap.add_argument(
        "--fail-on-errors",
        action="store_true",
        help="Fail if errors.log holds current-run failures (mtime >= filelist).",
    )
    ap.add_argument(
        "--fail-on-stale",
        action="store_true",
        help="Fail if any generated group is older than its extracted sources.",
    )
    ap.add_argument(
        "--write-manifest",
        default="",
        help="Write a freshness manifest JSON (extracted snapshot mtimes + "
        "per-group newest-src/oldest-out) to this path. Default location is "
        "<extracted>/_manifest.json; the file records which extracted/ "
        "snapshot produced the current generated/ tree (P2-7).",
    )
    args = ap.parse_args()

    failures: list[str] = []
    metrics: dict = {}
    ex = Path(args.extracted)
    gen = Path(args.generated)
    assets = Path(args.assets)
    filelist = ex / "filelist.txt"
    if not filelist.exists():
        raise SystemExit(f"missing {filelist}")

    mounted_exact = set()
    for line in filelist.read_text().splitlines():
        if line:
            mounted_exact.add(line.split("\t")[0])
    mounted_ci = {p.lower() for p in mounted_exact}

    manifest_tat = []
    for line in Path(args.manifest).read_text(errors="replace").splitlines():
        p = line.split("\t")[0].strip()
        if p.startswith("TAT/") and not p.endswith((".ubulk", ".uexp", ".uptnl")):
            manifest_tat.append(p)

    # The pak container is a container, not a payload path; it can never appear
    # in a dumped file list, so keeping it in the denominator understated
    # coverage by construction.
    pak_containers = [p for p in manifest_tat if p.lower().endswith(".pak")]
    covered = [p for p in manifest_tat if not p.lower().endswith(".pak")]

    missing_ci = [p for p in covered if p.lower() not in mounted_ci]
    resolved = len(covered) - len(missing_ci)
    exact = sum(1 for p in covered if p in mounted_exact)
    exact_only = len(covered) - exact
    cov = resolved / max(1, len(covered))
    exact_cov = exact / max(1, len(covered))

    print(f"Manifest TAT entries: {len(manifest_tat)}")
    print(
        f"Pak containers excluded: {len(pak_containers)} "
        f"({', '.join(pak_containers) or '-'})"
    )
    print(
        f"Mount/path consistency (case-insensitive, pak excluded): "
        f"{resolved}/{len(covered)} ({cov:.1%})"
    )
    print(
        f"Mount/path consistency (exact-case diagnostic, previously reported "
        f"as 99.4 %): {exact}/{len(covered)} ({exact_cov:.1%}), "
        f"{exact_only} case-only differences"
    )
    for p in missing_ci[:10]:
        print(f"MISSING: {p}")

    stage_counts = {}
    stage_overrides = {}
    for item in args.stage_min:
        if "=" not in item:
            raise SystemExit(f"--stage-min wants STAGE=COUNT, got {item!r}")
        key, value = item.split("=", 1)
        if key not in DUMP_STAGES:
            raise SystemExit(f"--stage-min unknown stage {key!r}")
        stage_overrides[key] = int(value)
    for sub in DUMP_STAGES:
        d = ex / sub
        n = sum(1 for _ in d.rglob("*") if _.is_file()) if d.exists() else 0
        stage_counts[sub] = n
        minimum = stage_overrides.get(sub, STAGE_MIN_FILES[sub])
        print(f"stage {sub}: {n} files (min {minimum})")
        if n < minimum:
            failures.append(
                f"stage {sub}: expected >= {minimum} files under {d}, found {n} "
                "(pipeline leg missing or a partial extract)"
            )
    dumped = sum(stage_counts.values())
    print(f"Files written to {ex}: {dumped}")
    if cov < args.min_coverage:
        failures.append(
            f"coverage: mount/path consistency {cov:.1%} < {args.min_coverage:.1%} "
            f"({resolved}/{len(covered)}, case-insensitive, pak excluded)"
        )
    if dumped < args.min_dumped:
        failures.append(f"dumped: {dumped} files < --min-dumped {args.min_dumped}")

    # P1-8 gate 2: Engine deps are outside the TAT manifest glob, so assert
    # them by name. A missing WorldGridMaterial re-creates the dangling bind.
    missing_engine = [p for p in REQUIRED_ENGINE_DEPS if p not in mounted_exact]
    n_engine = sum(1 for p in mounted_exact if p.startswith("Engine/Content/"))
    print(f"Engine/Content files mounted: {n_engine}")
    for p in REQUIRED_ENGINE_DEPS:
        print(f"engine-dep {'OK' if p not in missing_engine else 'MISSING'}: {p}")
    if missing_engine:
        failures.append(f"required Engine deps not mounted: {missing_engine}")

    # errors.log is the per-run failure signal (truncated on open by
    # Exporter.Report, deleted when the run is clean). Absence with extracted
    # outputs is a broken extractor contract, not "clean"; a stale log means the
    # log does not describe this snapshot.
    errors_log = ex / "errors.log"
    if not errors_log.exists():
        if dumped > 0:
            failures.append(
                f"errors.log: MISSING at {errors_log}: {dumped} extracted files "
                "exist but the extractor left no run log; an absent log is not a "
                "clean run. Re-run the extractor so it writes errors.log."
            )
        else:
            print("errors.log: absent (no extracted output either)")
    else:
        age = time.strftime(
            "%Y-%m-%d %H:%M", time.localtime(errors_log.stat().st_mtime)
        )
        if errors_log.stat().st_mtime < filelist.stat().st_mtime:
            failures.append(
                f"errors.log: STALE at {errors_log} ({age}, "
                f"{errors_log.stat().st_size} bytes) predates filelist.txt "
                f"({time.strftime('%Y-%m-%d %H:%M', time.localtime(filelist.stat().st_mtime))}); "
                "re-run the extractor to truncate it"
            )
        elif errors_log.stat().st_size == 0:
            print(f"errors.log: clean (empty, {age})")
        else:
            lines = [ln for ln in errors_log.read_text().splitlines() if ln.strip()]
            known: list[str] = []
            unexpected: list[str] = []
            for line in lines:
                parts = line.split(": ")
                asset = parts[1].split(".")[0] if len(parts) > 1 else ""
                if (
                    UNSUPPORTED_ANIM_MARKER in line
                    and any(
                        t in line
                        for t in (
                            "UBlendSpace",
                            "UBlendSpace1D",
                            "UAimOffsetBlendSpace",
                        )
                    )
                    and asset in KNOWN_UNSUPPORTED_ANIM
                ):
                    known.append(asset)
                else:
                    unexpected.append(line)
            print(
                f"errors.log ({age}): {len(known)} known-unsupported BlendSpace, "
                f"{len(unexpected)} unexpected"
            )
            for line in unexpected[:20]:
                print(line)
            if unexpected:
                if args.fail_on_errors:
                    failures.append(
                        f"errors.log: {len(unexpected)} unexpected failure line(s) "
                        f"in {errors_log}"
                    )
            elif not known and args.fail_on_errors:
                failures.append(
                    f"errors.log: holds current-run failures but none match the "
                    f"known-unsupported BlendSpace allowlist ({errors_log})"
                )

    # P1-8 gate 4: generated-vs-extracted freshness per domain group. This is a
    # secondary mtime signal: producer stamps below survive git checkouts.
    stale_groups = []
    group_rows: dict = {}
    for name, srcs, outs in FRESHNESS_GROUPS:
        src_roots = [ex / s for s in srcs]
        out_roots = [(ex / o) for o in outs]
        newest_src = 0.0
        for s in src_roots:
            m = _newest_mtime(s)
            newest_src = max(newest_src, m)
        oldest_out = 0.0
        n_out = 0
        for o in out_roots:
            files = (
                [o]
                if o.is_file()
                else ([p for p in o.rglob("*") if p.is_file()] if o.exists() else [])
            )
            for p in files:
                try:
                    m = p.stat().st_mtime
                except OSError:
                    continue
                n_out += 1
                if oldest_out == 0.0 or m < oldest_out:
                    oldest_out = m
        if n_out == 0:
            print(f"freshness {name}: NO GENERATED OUTPUTS (stale by absence)")
            stale_groups.append(name)
            group_rows[name] = {
                "newest_extracted_src": newest_src,
                "oldest_generated_out": 0.0,
                "n_outputs": 0,
                "stale": True,
            }
            continue
        stale = oldest_out < newest_src
        fmt = lambda t: time.strftime("%Y-%m-%d %H:%M", time.localtime(t)) if t else "-"
        print(
            f"freshness {name}: {'STALE' if stale else 'fresh'} "
            f"(newest src {fmt(newest_src)}, oldest out {fmt(oldest_out)}, {n_out} outputs)"
        )
        if stale:
            stale_groups.append(name)
        group_rows[name] = {
            "newest_extracted_src": newest_src,
            "oldest_generated_out": oldest_out,
            "n_outputs": n_out,
            "stale": stale,
        }
    if stale_groups and args.fail_on_stale:
        failures.append(f"stale generated groups: {stale_groups}")

    # Hard content assertions: measured counts, not "file exists".
    checks = [
        _run_check(_check_levels, gen, metrics),
        _run_check(_check_contracts, gen, metrics),
        _run_check(_check_tables, gen, metrics),
        _run_check(_check_materials, gen, metrics),
        _run_check(_check_containers, gen, metrics),
        _run_check(_check_decals, gen, metrics),
        _run_check(_check_devices, gen, metrics),
        _run_check(_check_animations, gen, metrics),
        _run_check(_check_audio, gen, metrics),
        _run_check(_check_localization, gen, metrics),
        _run_check(_check_videos, gen, assets, metrics),
        _run_check(_check_scene_variants, gen, metrics),
        _run_check(_check_niagara, gen, metrics),
    ]
    for check in checks:
        print(check.line())
        failures.extend(check.problems)

    stamp_path = Path(args.stamps)
    stamp_failures, stamp_payload, stamp_status = _check_stamps(
        stamp_path, metrics, args.refresh_stamps
    )
    if args.refresh_stamps:
        print(
            "stamps: --refresh-stamps is set; producer sha drift is accepted "
            "(escape hatch, not a normal gate run)"
        )
    print(f"stamps: {stamp_status}")
    failures.extend(stamp_failures)

    # P2-7: record which extracted/ snapshot the current generated/ tree was
    # built from. Written on every run so a failed audit is still diagnosable.
    manifest_path = (
        Path(args.write_manifest) if args.write_manifest else (ex / "_manifest.json")
    )
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(
            {
                "written_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "extracted": str(ex),
                "filelist_mtime": filelist.stat().st_mtime,
                "manifest_entries": len(manifest_tat),
                "pak_containers_excluded": pak_containers,
                "resolved": resolved,
                "coverage": cov,
                "exact_case_resolved": exact,
                "exact_case_coverage": exact_cov,
                "stage_counts": stage_counts,
                "required_engine_deps": REQUIRED_ENGINE_DEPS,
                "missing_engine_deps": missing_engine,
                "groups": group_rows,
                "content": metrics,
                "failures": failures,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"manifest -> {manifest_path}")

    if failures:
        print(f"AUDIT FAILED: {len(failures)} failure(s)")
        for failure in failures:
            print(f"FAIL: {failure}")
        raise SystemExit(1)

    _write_json_atomic(stamp_path, stamp_payload)
    print(f"stamps -> {stamp_path} ({len(stamp_payload['producers'])} producers)")
    print("AUDIT PASS")


if __name__ == "__main__":
    main()
