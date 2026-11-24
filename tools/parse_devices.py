#!/usr/bin/env python3
"""Emit the authored runtime device layer for TAT-2.

Reads the shipped cooked level dumps (extracted/json/Maps/**) and the Blueprint
CDO dumps (extracted/json/Gameplay/**/BP_*.json), then writes:

    game/data/generated/gameplay/devices_runtime.json

What this producer fixes versus the old device manifest (tools/parse_tables.py
write_device_manifest):

* Only real level actors are devices. A component export's Outer.ObjectName
  points at its owning actor, never at Level'...'; components are joined back
  to that owner instead of being emitted as actors.
* Ids are "<map_id>/<sublevel_stem>:<ActorName>", because actor names repeat
  across sublevels (e.g. BP_SecurityTurret_180_C_1 exists in several maps).
* The authored trigger graph is emitted: TATTrapDetectorComponent
  .TrapActionsToTrigger (deduped, nulls dropped, unresolved kept) and
  TATElectricalDeviceComponent._powerSource.
* Per-instance overrides are emitted only when serialized on the actor export
  (BeamLength, ZoneSize, cone angles, State, _swivel*, _lockConfig, ...). The
  runtime merges them over the family defaults recorded in stats.
* LevelInstance actors are expanded: a placed instance of a device-bearing
  sublevel contributes its devices at the instance transform (the generated
  .tatlevel.json carries the already-composed Godot transform).

Transforms: pos/basis/scale are taken from the generated .tatlevel.json actors
(matched by name), exactly as the level loader consumes them. When no
generated actor exists, the raw UE transform is converted with the same
UE->Godot math as parse_tables.py (x=ue.x/100, y=ue.z/100, z=ue.y/100,
column-major basis).

Units: pos/basis/scale are Godot metres / column-major. Authored per-instance
params keep the cooked UE units under the original property names (centimetres
for lengths, seconds, degrees) so nothing is silently rescaled;
stats.family_defaults.metric holds the converted Godot-metre fallbacks the
runtime merges them over. Device scale is always [1,1,1]; the 14 loaded
acoustic portals carry a non-unit authored box scale, preserved in
params.authored_scale and normalized on the device transform (data-only
family).

The JSON is data, not behaviour: this script never runs Godot and never edits
runtime code.
"""

from __future__ import annotations

import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import parse_tables as pt

ROOT = Path(__file__).resolve().parent.parent
EX = ROOT / "extracted"
JSON_ROOT = EX / "json"
MAPS_DIR = JSON_ROOT / "Maps"
GAMEPLAY_DIR = JSON_ROOT / "Gameplay"
LEVELS_DIR = ROOT / "game" / "data" / "generated" / "levels"
OUT_PATH = ROOT / "game" / "data" / "generated" / "gameplay" / "devices_runtime.json"
MISSION_CONTROLLER = ROOT / "game" / "src" / "missions" / "mission_controller.gd"
GAME_DATA = ROOT / "game" / "src" / "core" / "game_data.gd"
CONTRACTS_JSON = ROOT / "game" / "data" / "generated" / "gameplay" / "contracts.json"
HEARING_STIM_JSON = (
    ROOT
    / "game"
    / "data"
    / "generated"
    / "tables"
    / "AI"
    / "Data"
    / "DT_HearingStimProperties.json"
)
SCHEMA = "tat2.devices_runtime/1"
GAME_VERSION = "Steam 1.5.193.148559"

# Family order is also the census/report order.
FAMILY_ORDER = [
    "turret",
    "alarm_eye",
    "light_beam",
    "pressure_plate",
    "noise_alarm",
    "ward_slow",
    "ward_blocker",
    "goo_pipe",
    "vault_door",
    "power_wall",
    "power_switch",
    "junction",
    "acoustic_portal",
    "magnetic_lock",
]

# Device families that carry runtime behaviour. acoustic_portal / junction /
# magnetic_lock are data-only (params only, no behaviour in the runtime layer).
RUNTIME_FAMILIES = {
    "turret",
    "alarm_eye",
    "light_beam",
    "pressure_plate",
    "noise_alarm",
    "ward_slow",
    "ward_blocker",
    "goo_pipe",
    "vault_door",
    "power_wall",
    "power_switch",
}

# Whole-game expected counts (audit table). Used only for the census printout
# and by tools/check_devices_runtime.py; never used to filter devices.
EXPECTED_FAMILY_COUNTS = {
    "turret": 478,
    "alarm_eye": 181,
    "light_beam": 330,
    "pressure_plate": 581,
    "noise_alarm": 136,
    "ward_slow": 80,
    "ward_blocker": 63,
    "goo_pipe": 135,
    "vault_door": 12,
    "power_wall": 15,
    "junction": 11,
    "acoustic_portal": 285,
    "magnetic_lock": 12,
}
EXPECTED_TOTAL = 2095
EXPECTED_BY_MAP = {"guildhall": 903, "old_manor": 1164, "ftue": 26, "thieves_den": 2}


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
def load_json(path: Path):
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def clean_object_name(obj) -> str:
    if isinstance(obj, dict):
        return str(obj.get("ObjectName", ""))
    return str(obj or "")


def class_from_ref(obj) -> str:
    """Class name from `Class'Foo_C'` style references."""
    name = clean_object_name(obj)
    if "'" in name:
        return name.split("'")[0]
    return name


def ref_target_actor(obj) -> str | None:
    """Actor name from `Class'Map:PersistentLevel.Actor[.Comp]'`."""
    name = clean_object_name(obj)
    if "PersistentLevel." not in name:
        return None
    tail = name.split("PersistentLevel.")[-1].rstrip("'")
    return tail.split(".")[0]


def is_level_outer(obj) -> bool:
    return clean_object_name(obj).startswith("Level'")


def family_of(cls: str) -> str | None:
    if not cls or cls.startswith("BPP_"):
        # BPP_* are packed-level actors (ISMs only); their "Turret" basename
        # is a facade asset name, not a device. They carry no device
        # components. Excluding them is required for the authored census.
        return None
    if cls == "BP_Detector_LightBeam_C":
        return "light_beam"
    if cls == "BP_Detector_PressurePlate_C":
        return "pressure_plate"
    if cls.startswith("BP_SecurityTurret") and cls.endswith("_C"):
        return "turret"
    if cls.startswith("BP_MagicAlarm") and cls.endswith("_C"):
        return "alarm_eye"
    if cls == "BP_WardZone_Slow_C":
        return "ward_slow"
    if cls == "BP_WardZone_Blocker_C":
        return "ward_blocker"
    if cls == "BP_Trap_Action_NoiseAlarm_C":
        return "noise_alarm"
    if cls == "BP_GooPipe_C":
        return "goo_pipe"
    if cls.startswith("BP_VaultDoor") and cls.endswith("_C"):
        return "vault_door"
    if cls == "BP_PowerSupply_Wall_C":
        return "power_wall"
    if cls == "BP_PowerSupply_LightSwitch_C":
        return "power_switch"
    if cls.startswith("BP_PowerJunction") and cls.endswith("_C"):
        return "junction"
    if cls == "BP_TATAcousticPortal_C":
        return "acoustic_portal"
    return None


def res_to_rel(res_path: str) -> str | None:
    prefix = "res://data/generated/levels/"
    suffix = ".tatlevel.json"
    if not res_path.startswith(prefix) or not res_path.endswith(suffix):
        return None
    return res_path[len(prefix) : -len(suffix)]


def ue_path_to_rel(ue_path: str) -> str | None:
    prefix = "/Game/Maps/"
    if not ue_path.startswith(prefix):
        return None
    stem = ue_path[len(prefix) :].split(".")[0]
    return stem


def rel_file(rel: str) -> Path:
    return MAPS_DIR / (rel + ".json")


def generated_file(rel: str) -> Path:
    return LEVELS_DIR / (rel + ".tatlevel.json")


# ---------------------------------------------------------------------------
# Sublevel sets: read the same lists the port loads
# ---------------------------------------------------------------------------
def gdscript_function_body(path: Path, func_name: str) -> str:
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(
        rf"^func\s+{re.escape(func_name)}\s*\([^\n]*\)[^\n]*:\s*\n(.*?)(?=^func\s|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"[devices] cannot find {func_name}() in {path}")
    return match.group(1)


def parse_ftue_sublevels() -> list[str]:
    body = gdscript_function_body(GAME_DATA, "get_ftue_sublevels")
    names = re.findall(r'^\t\t"([^"]+)",\s*$', body, re.MULTILINE)
    if not names:
        raise SystemExit("[devices] get_ftue_sublevels() returned no names")
    return names


def parse_map_sublevels() -> dict[str, list[str]]:
    """Mirror mission_controller._map_id_to_sublevels's base lists."""
    body = gdscript_function_body(MISSION_CONTROLLER, "_map_id_to_sublevels")
    match_block = body.split("match map_id:", 1)
    if len(match_block) != 2:
        raise SystemExit("[devices] _map_id_to_sublevels has no match map_id block")
    body = match_block[1]
    branch_re = re.compile(
        r'^\t\t"([a-z_]+)":\s*\n(.*?)(?=^\t\t"[a-z_]+":\s*$|^\tif base\.is_empty)',
        re.MULTILINE | re.DOTALL,
    )
    branches = {}
    for m in branch_re.finditer(body):
        map_id, chunk = m.group(1), m.group(2)
        res_paths = re.findall(
            r'"(res://data/generated/levels/[^"]+\.tatlevel\.json)"', chunk
        )
        if "get_ftue_sublevels()" in chunk:
            # The tutorial branch builds its paths from GameData, e.g.
            # "res://data/generated/levels/FTUE/%s.tatlevel.json" % ftue_sub.
            branches[map_id] = [f"FTUE/{name}" for name in parse_ftue_sublevels()]
        elif res_paths:
            branches[map_id] = [res_to_rel(p) for p in res_paths]
        else:
            branches[map_id] = []
    if not branches:
        raise SystemExit("[devices] _map_id_to_sublevels match block parsed empty")
    missing = [m for m, v in branches.items() if not v]
    if missing:
        raise SystemExit(f"[devices] no base sublevels parsed for maps: {missing}")
    return branches


def contract_sublevels_for_map(map_id: str) -> list[str]:
    """Contract sublevels appended by _map_id_to_sublevels for this map.

    The function appends get_contract_sublevels(order) (order = the mission's
    authored contract order). Use the lowest authored order for the map: that
    is the order the map is first loaded with. Contract sublevels contain no
    device actors in the shipped data, but they are real loaded sublevels and
    belong in the sublevels list.
    """
    if not CONTRACTS_JSON.is_file():
        return []
    data = load_json(CONTRACTS_JSON)
    orders = sorted(
        (
            int(c.get("order", -1)),
            c,
        )
        for c in data.get("contracts", [])
        if isinstance(c, dict) and str(c.get("map_id", "")) == map_id
    )
    if not orders:
        return []
    out = []
    for ue_path in orders[0][1].get("sublevels_ue_paths", []) or []:
        rel = ue_path_to_rel(str(ue_path))
        if rel and generated_file(rel).is_file():
            out.append(rel)
    return out


# ---------------------------------------------------------------------------
# Raw map file: real actors, components joined via Outer, transforms
# ---------------------------------------------------------------------------
class RawMap:
    def __init__(self, rel: str):
        self.rel = rel
        self.path = rel_file(rel)
        self.stem = self.path.stem
        self.exports = load_json(self.path)
        if not isinstance(self.exports, list):
            raise SystemExit(f"[devices] {self.path} is not an export list")
        self.real: dict[str, int] = {}
        self.real_duplicates: Counter[str] = Counter()
        self.components_by_owner: dict[str, list[int]] = defaultdict(list)
        self.comp_index: dict[str, int] = {}
        self._world_cache: dict[int, list] = {}

        for idx, export in enumerate(self.exports):
            if not isinstance(export, dict):
                continue
            name = str(export.get("Name", ""))
            outer = export.get("Outer")
            outer_name = clean_object_name(outer)
            if is_level_outer(outer):
                if name in self.real:
                    self.real_duplicates[name] += 1
                else:
                    self.real[name] = idx
                continue
            if "PersistentLevel." not in outer_name:
                continue
            owner = outer_name.split("PersistentLevel.")[-1].rstrip("'").split(".")[0]
            self.components_by_owner[owner].append(idx)
            comp_name = str(export.get("Name", ""))
            full = (
                f"{export.get('Type')}'{self.stem}:PersistentLevel.{owner}.{comp_name}'"
            )
            self.comp_index[full] = idx
            self.comp_index[f"{owner}.{comp_name}"] = idx

    # -- components ---------------------------------------------------------
    def components(self, actor_name: str, comp_type: str | None = None) -> list[dict]:
        out = []
        for idx in self.components_by_owner.get(actor_name, []):
            export = self.exports[idx]
            if comp_type is not None and export.get("Type") != comp_type:
                continue
            out.append(export)
        return out

    def component_props(self, export: dict) -> dict:
        props = export.get("Properties")
        return props if isinstance(props, dict) else {}

    # -- transforms ---------------------------------------------------------
    def _resolve_component_idx(self, ref) -> int | None:
        name = clean_object_name(ref)
        if not name:
            return None
        idx = self.comp_index.get(name)
        if idx is not None:
            return idx
        if "PersistentLevel." in name:
            owner = name.split("PersistentLevel.")[-1].rstrip("'").split(".")[0]
            comp = name.rsplit(".", 1)[-1].rstrip("'")
            return self.comp_index.get(f"{owner}.{comp}")
        return None

    def world_matrix(self, idx: int, depth: int = 0) -> list:
        if idx in self._world_cache:
            return self._world_cache[idx]
        if depth > 12 or not (0 <= idx < len(self.exports)):
            return pt.mat4_identity()
        export = self.exports[idx]
        props = self.component_props(export)
        local = pt.ue_trs_to_mat4(
            props.get("RelativeLocation"),
            props.get("RelativeRotation"),
            props.get("RelativeScale3D"),
            is_quat=False,
        )
        parent_idx = self._resolve_component_idx(props.get("AttachParent"))
        if parent_idx is not None and parent_idx != idx:
            local = pt.mat4_mul(self.world_matrix(parent_idx, depth + 1), local)
        self._world_cache[idx] = local
        return local

    def actor_world_matrix(self, actor_name: str) -> list:
        idx = self.real.get(actor_name)
        if idx is None:
            return pt.mat4_identity()
        props = self.exports[idx].get("Properties") or {}
        root_idx = self._resolve_component_idx(props.get("RootComponent"))
        if root_idx is None:
            return pt.mat4_identity()
        return self.world_matrix(root_idx)

    # -- level instances ----------------------------------------------------
    def level_instances(self) -> list[tuple[str, str]]:
        """(instance actor name, source sublevel rel) for placed level instances."""
        out = []
        for name, idx in self.real.items():
            export = self.exports[idx]
            if export.get("Type") != "LevelInstance":
                continue
            props = export.get("Properties") or {}
            asset = props.get("CookedWorldAsset") or {}
            asset_path = (
                str(asset.get("AssetPathName", "")) if isinstance(asset, dict) else ""
            )
            rel = ue_path_to_rel(asset_path)
            if rel:
                out.append((name, rel))
        return out


_MAP_CACHE: dict[str, RawMap] = {}


def raw_map(rel: str) -> RawMap | None:
    if rel in _MAP_CACHE:
        return _MAP_CACHE[rel]
    if not rel_file(rel).is_file():
        return None
    try:
        rf = RawMap(rel)
    except Exception as exc:  # noqa: BLE001 - report and skip a corrupt dump
        print(f"[devices] WARNING cannot read {rel_file(rel)}: {exc}")
        return None
    _MAP_CACHE[rel] = rf
    return rf


# Component exports whose authored payload the producer reads. Keeping only
# these (instead of every export in every BP dump) keeps peak memory low even
# though the extraction has >1,000 BP JSON files.
BP_COMPONENT_TYPES = frozenset(
    {
        "TATAISenseConfig_Sight",
        "CapsuleComponent",
        "SphereComponent",
        "InteractionBoxTrigger",
        "TimelineTemplate",
        "BoxComponent",
        "ProjectileMovementComponent",
        "TATElectricalDeviceComponent",
    }
)


# ---------------------------------------------------------------------------
# Blueprint CDO index (class defaults + parent chain)
# ---------------------------------------------------------------------------
class BlueprintIndex:
    def __init__(self):
        self.by_class: dict[str, dict] = {}
        roots = [
            GAMEPLAY_DIR,
            JSON_ROOT / "Core",
            JSON_ROOT / "Audio",
            JSON_ROOT / "Art",
        ]
        for root in roots:
            if not root.is_dir():
                continue
            for path in root.rglob("BP_*.json"):
                if path.name.startswith("BPP_"):
                    continue
                try:
                    doc = load_json(path)
                except Exception:  # noqa: BLE001, S112
                    continue
                if not isinstance(doc, list):
                    continue
                cls = None
                cdo_props: dict = {}
                parent = None
                components: dict[str, list[dict]] = defaultdict(list)
                for export in doc:
                    if export.get("Type") == "BlueprintGeneratedClass":
                        cls = str(export.get("Name", ""))
                    elif str(export.get("Name", "")).startswith("Default__"):
                        props = export.get("Properties")
                        cdo_props = props if isinstance(props, dict) else {}
                        parent = class_from_ref(export.get("Template"))
                    elif export.get("Type") in BP_COMPONENT_TYPES:
                        props = export.get("Properties")
                        if isinstance(props, dict) and props:
                            components[str(export.get("Type"))].append(props)
                if not cls or cls in self.by_class:
                    continue
                self.by_class[cls] = {
                    "path": str(path),
                    "cdo_props": cdo_props,
                    "parent": parent,
                    "components": dict(components),
                }

    def cdo(self, cls: str) -> dict | None:
        entry = self.by_class.get(cls)
        if not entry:
            return None
        return {"props": entry["cdo_props"], "parent": entry["parent"]}

    def class_chain(self, cls: str) -> list[str]:
        """Base-first chain through CDO Template parent refs."""
        chain = []
        seen = set()
        cur = cls
        while cur and cur not in seen and len(chain) < 8:
            seen.add(cur)
            chain.append(cur)
            cdo = self.cdo(cur)
            cur = cdo.get("parent") if cdo else None
        chain.reverse()
        return chain

    def merged_cdo_props(self, cls: str) -> dict:
        merged = {}
        for c in self.class_chain(cls):
            cdo = self.cdo(c)
            if cdo:
                merged.update(cdo["props"])
        return merged

    def component_props(self, cls: str, comp_type: str) -> dict:
        """First serialized component of comp_type in the class chain."""
        for c in reversed(self.class_chain(cls)):
            entry = self.by_class.get(c)
            if not entry:
                continue
            for props in entry["components"].get(comp_type, []):
                if props:
                    return props
        return {}

    def first_component_props(self, cls: str, comp_type: str) -> dict:
        return self.component_props(cls, comp_type)


_BP_INDEX: BlueprintIndex | None = None


def bp_index() -> BlueprintIndex:
    global _BP_INDEX
    if _BP_INDEX is None:
        _BP_INDEX = BlueprintIndex()
    return _BP_INDEX


# ---------------------------------------------------------------------------
# Generated level actor index (transform source)
# ---------------------------------------------------------------------------
class GeneratedLevels:
    def __init__(self):
        self._cache: dict[str, dict] = {}

    def actors(self, rel: str) -> dict:
        if rel in self._cache:
            return self._cache[rel]
        path = generated_file(rel)
        index = {"by_name": defaultdict(list), "ok": False}
        if path.is_file():
            try:
                doc = load_json(path)
            except Exception as exc:  # noqa: BLE001
                print(f"[devices] WARNING cannot read {path}: {exc}")
                doc = None
            if isinstance(doc, dict):
                index["ok"] = True
                for actor in doc.get("actors", []):
                    if not isinstance(actor, dict):
                        continue
                    index["by_name"][str(actor.get("name", ""))].append(actor)
        self._cache[rel] = index
        return index

    def find(
        self, rel: str, actor_name: str, instance_label: str | None
    ) -> dict | None:
        index = self.actors(rel)
        entries = index["by_name"].get(actor_name, [])
        if instance_label:
            for entry in entries:
                if str(entry.get("level_instance", "")) == instance_label:
                    return entry
            return None
        for entry in entries:
            if "level_instance" not in entry:
                return entry
        # A level-instance child may be the only generated entry for a device
        # (source actor name collides). Do not silently take an instance.
        return None


# ---------------------------------------------------------------------------
# Device collection (raw actors + level-instance expansion)
# ---------------------------------------------------------------------------
class DeviceRecord:
    __slots__ = (
        "actor",
        "cls",
        "family",
        "instance",
        "instance_world",
        "map_id",
        "raw_actor",
        "raw_map",
        "source_rel",
    )

    def __init__(
        self,
        actor: str,
        cls: str,
        family: str,
        sublevel: str,
        raw_map: RawMap,
        raw_actor: str,
        instance: str | None = None,
        instance_world: list | None = None,
        source_rel: str | None = None,
    ):
        self.actor = actor
        self.cls = cls
        self.family = family
        self.raw_map = raw_map
        self.raw_actor = raw_actor
        self.instance = instance
        self.instance_world = instance_world
        self.source_rel = source_rel or sublevel
        self.map_id = None


def collect_devices(
    map_file: RawMap,
    sublevel: str,
    *,
    depth: int = 0,
    chain: tuple[str, ...] = (),
    warnings: list[str] | None = None,
) -> list[DeviceRecord]:
    warnings = warnings if warnings is not None else []
    records: list[DeviceRecord] = []
    for actor_name, idx in map_file.real.items():
        cls = str(map_file.exports[idx].get("Type", ""))
        family = family_of(cls)
        if family:
            records.append(
                DeviceRecord(
                    actor=actor_name,
                    cls=cls,
                    family=family,
                    sublevel=sublevel,
                    raw_map=map_file,
                    raw_actor=actor_name,
                )
            )
    # Expand placed level instances that carry devices (FTUE_Geometry places
    # FTUE_Building_JewelryStore). The generated level expands them too; this
    # keeps the authored list and the transform source in agreement.
    if depth < 3:
        for inst_name, source_rel in map_file.level_instances():
            if source_rel in chain:
                warnings.append(
                    f"level-instance cycle skipped: {sublevel}"
                    f"::{inst_name} -> {source_rel}"
                )
                continue
            source = raw_map(source_rel)
            if source is None:
                continue
            nested = collect_devices(
                source,
                sublevel,
                depth=depth + 1,
                chain=chain + (map_file.rel,),
                warnings=warnings,
            )
            instance_world = map_file.actor_world_matrix(inst_name)
            for rec in nested:
                world = instance_world
                if rec.instance_world is not None:
                    world = pt.mat4_mul(instance_world, rec.instance_world)
                records.append(
                    DeviceRecord(
                        actor=rec.actor,
                        cls=rec.cls,
                        family=rec.family,
                        sublevel=sublevel,
                        raw_map=rec.raw_map,
                        raw_actor=rec.raw_actor,
                        instance=inst_name,
                        instance_world=world,
                        source_rel=source_rel,
                    )
                )
                if rec.instance:
                    warnings.append(
                        f"nested level instance expanded: {rec.actor} in {rec.instance}"
                    )
    return records


# ---------------------------------------------------------------------------
# Family-specific authored params and defaults
# ---------------------------------------------------------------------------
def _round(value, digits=6):
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            return None
        return round(value, digits)
    return value


def _cm_to_m(value):
    if value is None:
        return None
    try:
        return _round(float(value) / 100.0, 6)
    except (TypeError, ValueError):
        return None


def _cm_list_to_m(value):
    if not isinstance(value, list):
        return None
    return [_cm_to_m(v) for v in value]


def _struct_xyz(value) -> list[float] | None:
    if not isinstance(value, dict):
        return None
    try:
        return [
            _round(float(value.get("X", 0.0))),
            _round(float(value.get("Y", 0.0))),
            _round(float(value.get("Z", 0.0))),
        ]
    except (TypeError, ValueError):
        return None


def _scalar_params(props: dict, keys: tuple[str, ...]) -> dict:
    return {
        k: _round(props[k]) if isinstance(props[k], float) else props[k]
        for k in keys
        if k in props
    }


def difficulty_map(prop) -> dict[str, dict]:
    """UE TMap<ETATDifficulty, struct> serialized as a list -> by difficulty."""
    out: dict[str, dict] = {}
    if not isinstance(prop, list):
        return out
    for entry in prop:
        if not isinstance(entry, dict):
            continue
        key = str(entry.get("Key", "")).split("::")[-1].lower()
        value = entry.get("Value")
        if key and isinstance(value, dict):
            out[key] = value
    return out


def _by_difficulty(entries: dict[str, dict], field: str) -> list:
    return [
        _round(entries[key].get(field)) if key in entries else None
        for key in ("easy", "normal", "hard")
    ]


def numeric_summary(values: list) -> dict | None:
    if not values:
        return None
    ordered = sorted(float(v) for v in values)
    count = len(ordered)
    middle = count // 2
    p50 = (
        ordered[middle] if count % 2 else (ordered[middle - 1] + ordered[middle]) / 2.0
    )
    return {
        "count": count,
        "min": _round(ordered[0]),
        "p50": _round(p50),
        "max": _round(ordered[-1]),
    }


def hearing_stim_table() -> dict[str, dict]:
    if not HEARING_STIM_JSON.is_file():
        return {}
    try:
        data = load_json(HEARING_STIM_JSON)
    except Exception:  # noqa: BLE001
        return {}
    rows = data.get("rows") if isinstance(data, dict) else None
    if not isinstance(rows, dict):
        return {}
    out = {}
    for row in rows.values():
        if not isinstance(row, dict):
            continue
        tag = str((row.get("Tag") or {}).get("TagName", ""))
        if not tag:
            continue
        out[tag] = {
            "severity": row.get("Severity"),
            "max_range_cm": _round(row.get("MaxRange")),
            "inner_investigation_range_cm": _round(row.get("InnerInvestigationRange")),
            "outer_investigation_range_cm": _round(row.get("OuterInvestigationRange")),
        }
    return out


def stim_ref(tag: str, table: dict[str, dict]) -> dict | None:
    if not tag:
        return None
    row = table.get(tag)
    if row is None:
        return {"tag": tag, "severity": None, "max_range_cm": None}
    return {"tag": tag, **row}


def turret_variant(cls: str) -> str:
    return {
        "BP_SecurityTurret_C": "base",
        "BP_SecurityTurret_90_C": "90",
        "BP_SecurityTurret_180_C": "180",
        "BP_SecurityTurret_360_C": "360",
        "BP_SecurityTurret_180_Triggered_C": "180_triggered",
    }.get(
        cls, cls.removeprefix("BP_SecurityTurret_").removesuffix("_C").lower() or "base"
    )


def alarm_variant(cls: str) -> str:
    return {
        "BP_MagicAlarm_C": "base",
        "BP_MagicAlarm_LongRange_Narrow_C": "long_narrow",
        "BP_MagicAlarm_LongRange_Wide_C": "long_wide",
        "BP_MagicAlarm_ShortRange_Narrow_C": "short_narrow",
        "BP_MagicAlarm_ShortRange_Wide_C": "short_wide",
        "BP_MagicAlarm_LongRange_FTUE_C": "long_ftue",
    }.get(cls, cls.removeprefix("BP_MagicAlarm_").removesuffix("_C").lower() or "base")


def vault_variant(cls: str) -> str:
    return {
        "BP_VaultDoor_Sliding_C": "single",
        "BP_VaultDoor_Sliding_StartsOpen_C": "single_starts_open",
        "BP_VaultDoor_SlidingDouble_C": "double",
        "BP_VaultDoor_SlidingDouble_AlwaysOpen_C": "double_always_open",
    }.get(cls, cls.removeprefix("BP_VaultDoor_").removesuffix("_C").lower())


def vault_starts_open(cls: str) -> bool:
    return "StartsOpen" in cls or "AlwaysOpen" in cls


def device_params(rec: DeviceRecord, overrides: dict) -> dict:
    """Per-instance authored overrides, keyed by the UE property names.

    Only properties serialized on the actor export are copied here; class /
    variant defaults live in stats.family_defaults and stats.variant_defaults.
    """
    family = rec.family
    props = overrides

    if family == "light_beam":
        return _scalar_params(
            props, ("BeamLength", "BaseRotation", "MaxDistanceToFireBeam")
        )

    if family == "pressure_plate":
        return {}

    if family == "turret":
        out = {"variant": turret_variant(rec.cls)}
        out.update(
            _scalar_params(
                props,
                (
                    "_swivelAngle",
                    "_swivelSeconds",
                    "_swivelPauseSeconds",
                    "_swivelResetTime",
                    "_swivelType",
                ),
            )
        )
        state = props.get("State")
        if isinstance(state, dict):
            out["State"] = state
            out["starts_on"] = bool(state.get("bIsOn", False))
        return out

    if family == "alarm_eye":
        out = {"variant": alarm_variant(rec.cls)}
        out.update(
            _scalar_params(
                props,
                (
                    "OuterConeAngle",
                    "InnerConeAngle",
                    "LightRange",
                    "AttenuationRadius",
                    "_swivelAngle",
                    "_swivelSeconds",
                    "_swivelPauseSeconds",
                    "_swivelType",
                    "_timeToFullyResetAfterTracking",
                    "_trackingAngleRestrictionPitch",
                    "_trackingAngleRestrictionYaw",
                    "_trackingAngleRestrictionRoll",
                ),
            )
        )
        state = props.get("State")
        if isinstance(state, dict):
            out["State"] = state
            out["starts_on"] = bool(state.get("bIsOn", False))
        return out

    if family in ("ward_slow", "ward_blocker"):
        return _scalar_params(props, ("ZoneSize",))

    if family == "noise_alarm":
        # 11 authored overrides are 0.5 s; the other 125 carry no serialized
        # trigger duration and must stay null for the runtime to use its
        # fallback.
        return (
            {"_triggeringDuration": _round(props["_triggeringDuration"])}
            if "_triggeringDuration" in props
            else {"_triggeringDuration": None}
        )

    if family == "goo_pipe":
        return {}

    if family == "vault_door":
        out = {"variant": vault_variant(rec.cls)}
        lock = props.get("_lockConfig")
        if isinstance(lock, dict):
            out["_lockConfig"] = lock
        magnet = rec.raw_map.components(rec.raw_actor, "BP_MagneticLockComponent_C")
        if magnet:
            magnet_props = magnet[0].get("Properties") or {}
            # Data-only attached family: no separate device record (the audit
            # device census excludes component-only locks); the door carries
            # the authored family/params for the runtime.
            out["magnetic_lock"] = {
                "family": "magnetic_lock",
                "params": {"_mode": magnet_props.get("_mode")},
            }
        return out

    if family in ("power_wall", "power_switch"):
        return _scalar_params(
            props, ("_state", "_shouldAutoReset", "_configTimeUntilAutoReset")
        )

    if family in ("junction", "acoustic_portal"):
        return {}

    return {}


# ---------------------------------------------------------------------------
# Per-family defaults (authored constants + variant tables) for stats
# ---------------------------------------------------------------------------
def family_defaults(bp: BlueprintIndex, table: dict[str, dict]) -> dict:
    defaults: dict[str, dict] = {}

    beam_cdo = bp.merged_cdo_props("BP_Detector_LightBeam_C")
    beam_capsule = bp.first_component_props(
        "BP_Detector_LightBeam_C", "CapsuleComponent"
    )
    defaults["light_beam"] = {
        "trigger_seconds": _round(beam_cdo.get("_triggeringDuration")),
        "reset_seconds": _round(beam_cdo.get("_resetDuration")),
        "radius_cm": _round(beam_capsule.get("CapsuleRadius")),
        "axis": "+X",
        "beam_length_default_cm": _round(beam_cdo.get("BeamLength")),
        "max_distance_to_fire_beam_default_cm": _round(
            beam_cdo.get("MaxDistanceToFireBeam")
        ),
        "require_power_to_trigger": beam_cdo.get("_requirePowerToTrigger"),
        "source": "extracted/json/Gameplay/Traps/Detectors/LightBeam/BP_Detector_LightBeam.json",
    }

    plate_cdo = bp.merged_cdo_props("BP_Detector_PressurePlate_C")
    plate_sphere = bp.first_component_props(
        "BP_Detector_PressurePlate_C", "SphereComponent"
    )
    plate_box = bp.first_component_props(
        "BP_Detector_PressurePlate_C", "InteractionBoxTrigger"
    )
    plate_timeline = bp.first_component_props(
        "BP_Detector_PressurePlate_C", "TimelineTemplate"
    )
    stim_tag = str((plate_cdo.get("_triggerHearingStim") or {}).get("TagName") or "")
    defaults["pressure_plate"] = {
        "trigger_seconds": _round(plate_cdo.get("_triggeringDuration")),
        "reset_seconds": _round(plate_cdo.get("_resetDuration")),
        "overlap_radius_cm": _round(plate_sphere.get("SphereRadius")),
        "plate_extent_cm": _struct_xyz(plate_box.get("BoxExtent")),
        "timeline_seconds": _round(plate_timeline.get("TimelineLength")),
        "damage": plate_cdo.get("Damage"),
        "hearing_stim": stim_ref(stim_tag, table),
        "require_power_to_trigger": plate_cdo.get("_requirePowerToTrigger"),
        "source": "extracted/json/Gameplay/Traps/Detectors/PressurePlate/BP_Detector_PressurePlate.json",
    }

    turret_base = bp.merged_cdo_props("BP_SecurityTurret_C")
    turret_sense = bp.first_component_props(
        "BP_SecurityTurret_C", "TATAISenseConfig_Sight"
    )
    turret_variants = {}
    for cls in (
        "BP_SecurityTurret_C",
        "BP_SecurityTurret_90_C",
        "BP_SecurityTurret_180_C",
        "BP_SecurityTurret_360_C",
        "BP_SecurityTurret_180_Triggered_C",
    ):
        merged = bp.merged_cdo_props(cls)
        sense = bp.first_component_props(cls, "TATAISenseConfig_Sight")
        escalation = (
            (sense.get("_EscalationStateToSettings") or [{}])[0].get("Value", {})
            if sense
            else {}
        )
        state = merged.get("State")
        turret_variants[cls] = {
            "variant": turret_variant(cls),
            "starts_on": bool(state.get("bIsOn", False))
            if isinstance(state, dict)
            else None,
            "_swivelAngle": _round(merged.get("_swivelAngle")),
            "_swivelSeconds": _round(merged.get("_swivelSeconds")),
            "_swivelPauseSeconds": _round(merged.get("_swivelPauseSeconds")),
            "_swivelResetTime": _round(merged.get("_swivelResetTime")),
            "_swivelType": merged.get("_swivelType"),
            "perception": {
                "SightRadius": _round(escalation.get("SightRadius")),
                "LoseSightRadius": _round(escalation.get("LoseSightRadius")),
                "PeripheralVisionAngleDegrees": _round(
                    escalation.get("PeripheralVisionAngleDegrees")
                ),
                "PointOfViewBackwardOffset": _round(
                    escalation.get("PointOfViewBackwardOffset")
                ),
                "NearClippingRadius": _round(escalation.get("NearClippingRadius")),
            },
            "MaxAge": _round(sense.get("MaxAge")),
        }
    projectile_props = bp.merged_cdo_props("BP_Projectile_SecurityTurret_C")
    projectile_move = bp.first_component_props(
        "BP_Projectile_SecurityTurret_C", "ProjectileMovementComponent"
    )
    turret_tuning = difficulty_map(turret_base.get("_difficultyToTuningMap"))
    turret_swivel = difficulty_map(turret_base.get("_difficultyToSwivelSettingsMap"))
    defaults["turret"] = {
        "variant": "base",
        "beam_distance_cm": _round(turret_base.get("BeamDistance")),
        "reset_seconds": _round(turret_base.get("TimeUntilResetAfterTriggering")),
        "_fireRate": _round(turret_base.get("_fireRate")),
        "fire_interval_seconds_by_difficulty": _by_difficulty(
            turret_tuning, "FireRate"
        ),
        "alarm_delay_seconds_by_difficulty": _by_difficulty(
            turret_swivel, "SecondsUntilAlarmTriggers"
        ),
        "_difficultyToTuningMap": turret_base.get("_difficultyToTuningMap"),
        "_difficultyToSwivelSettingsMap": turret_base.get(
            "_difficultyToSwivelSettingsMap"
        ),
        "perception": turret_variants["BP_SecurityTurret_C"]["perception"],
        "MaxAge": _round(turret_sense.get("MaxAge")),
        "projectile": {
            "max_speed_cm_s": _round(projectile_move.get("MaxSpeed")),
            "damage": projectile_props.get("Damage"),
            "life_span_seconds": _round(projectile_props.get("InitialLifeSpan")),
            "class": "BP_Projectile_SecurityTurret_C",
        },
        "source": "extracted/json/Gameplay/Traps/Turrets/BP_SecurityTurret*.json",
    }
    defaults["turret"]["variants"] = turret_variants

    alarm_base = bp.merged_cdo_props("BP_MagicAlarm_C")
    alarm_variants = {}
    for cls in (
        "BP_MagicAlarm_C",
        "BP_MagicAlarm_LongRange_Narrow_C",
        "BP_MagicAlarm_LongRange_Wide_C",
        "BP_MagicAlarm_ShortRange_Narrow_C",
        "BP_MagicAlarm_ShortRange_Wide_C",
        "BP_MagicAlarm_LongRange_FTUE_C",
    ):
        merged = bp.merged_cdo_props(cls)
        sense = bp.first_component_props(cls, "TATAISenseConfig_Sight")
        escalation = (
            (sense.get("_EscalationStateToSettings") or [{}])[0].get("Value", {})
            if sense
            else {}
        )
        alarm_variants[cls] = {
            "variant": alarm_variant(cls),
            "perception": {
                "SightRadius": _round(escalation.get("SightRadius")),
                "LoseSightRadius": _round(escalation.get("LoseSightRadius")),
                "PeripheralVisionAngleDegrees": _round(
                    escalation.get("PeripheralVisionAngleDegrees")
                ),
                "PointOfViewBackwardOffset": _round(
                    escalation.get("PointOfViewBackwardOffset")
                ),
                "NearClippingRadius": _round(escalation.get("NearClippingRadius")),
            },
            "MaxAge": _round(sense.get("MaxAge")),
            "LightRange": _round(merged.get("LightRange")),
            "OuterConeAngle": _round(merged.get("OuterConeAngle")),
            "InnerConeAngle": _round(merged.get("InnerConeAngle")),
            "AttenuationRadius": _round(merged.get("AttenuationRadius")),
            "_secondsUntilAlarmTriggers": _round(
                merged.get("_secondsUntilAlarmTriggers")
            ),
            "_swivelAngle": _round(merged.get("_swivelAngle")),
            "_swivelPauseSeconds": _round(merged.get("_swivelPauseSeconds")),
            "_difficultyToSwivelSettingsMap": merged.get(
                "_difficultyToSwivelSettingsMap"
            ),
        }
    alarm_swivel = difficulty_map(alarm_base.get("_difficultyToSwivelSettingsMap"))
    alarm_normal = alarm_swivel.get("normal", {})
    alarm_base_delay = float(alarm_base.get("_secondsUntilAlarmTriggers") or 2.0)
    alarm_multipliers = [
        alarm_swivel.get(key, {}).get("SecondsUntilAlarmTriggersMultiplier")
        for key in ("easy", "normal", "hard")
    ]
    defaults["alarm_eye"] = {
        "variant": "base",
        "stim": stim_ref("AI.Stim.Hearing.SecurityDevice.Alarm.Triggered", table),
        "_secondsUntilAlarmTriggers": _round(
            alarm_base.get("_secondsUntilAlarmTriggers")
        ),
        "alarm_delay_multipliers_by_difficulty": alarm_multipliers,
        "alarm_delay_seconds_by_difficulty": [
            _round(alarm_base_delay * float(m)) if m is not None else None
            for m in alarm_multipliers
        ],
        "swivel_angle_deg": _round(alarm_base.get("_swivelAngle")),
        "swivel_seconds": _round(alarm_normal.get("SwivelSeconds")),
        "swivel_pause_seconds": _round(alarm_normal.get("SwivelPauseSeconds")),
        "_difficultyToSwivelSettingsMap": alarm_base.get(
            "_difficultyToSwivelSettingsMap"
        ),
        "variants": alarm_variants,
        "source": "extracted/json/Gameplay/Traps/Detectors/SecurityCamera/BP_MagicAlarm*.json",
    }

    ward_slow_cdo = bp.merged_cdo_props("BP_WardZone_Slow_C")
    ward_effects = ward_slow_cdo.get("WardGameplayEffects") or []
    slow_seconds = None
    slow_multiplier = None
    magic_damage = None
    for effect in ward_effects:
        if not isinstance(effect, dict):
            continue
        ge_name = clean_object_name(effect.get("WardGameplayEffect"))
        set_by_caller = {
            str((p.get("Tag") or {}).get("TagName", "")): p.get("Value")
            for p in effect.get("SetByCallerParams") or []
            if isinstance(p, dict)
        }
        if "GE_GrantSlowedDuration" in ge_name:
            slow_seconds = set_by_caller.get("SetByCaller.Duration")
            slow_multiplier = set_by_caller.get("SetByCaller.Magnitude")
        elif "GE_DealHealthDamage_Magic" in ge_name:
            magic_damage = set_by_caller.get("SetByCaller.Damage")
    defaults["ward_slow"] = {
        "ZoneSize_cm_default": _struct_xyz(ward_slow_cdo.get("ZoneSize")),
        "WardInitiallyActive": ward_slow_cdo.get("WardInitiallyActive"),
        "WardImmunityDuration": _round(ward_slow_cdo.get("WardImmunityDuration")),
        "slow_seconds": _round(slow_seconds),
        "slow_multiplier": _round(slow_multiplier),
        "magic_damage": _round(magic_damage),
        "WardGameplayEffects": ward_effects,
        "activate_hold_seconds": _round(
            (ward_slow_cdo.get("WardActivatePrompt") or {}).get("holdDuration")
        ),
        "source": "extracted/json/Gameplay/MagicTraps/BP_WardZone_Slow.json",
    }
    ward_blocker_cdo = bp.merged_cdo_props("BP_WardZone_Blocker_C")
    blocker_collision = bp.first_component_props(
        "BP_WardZone_Blocker_C", "BoxComponent"
    )
    blocker_profile = (blocker_collision.get("BodyInstance") or {}).get(
        "CollisionProfileName"
    )
    defaults["ward_blocker"] = {
        "ZoneSize_cm_default": _struct_xyz(ward_blocker_cdo.get("ZoneSize")),
        "WardInitiallyActive": ward_blocker_cdo.get("WardInitiallyActive"),
        "ImpactFXCooldown": _round(ward_blocker_cdo.get("ImpactFXCooldown")),
        "collision_profile": blocker_profile,
        "blocks_player_only": blocker_profile == "BlockOnlyPlayerPawn",
        "source": "extracted/json/Gameplay/MagicTraps/BP_WardZone_Blocker.json",
    }

    noise_cdo = bp.merged_cdo_props("BP_Trap_Action_NoiseAlarm_C")
    defaults["noise_alarm"] = {
        "_triggeringDuration_default": (
            _round(noise_cdo["_triggeringDuration"])
            if "_triggeringDuration" in noise_cdo
            else None
        ),
        "stim": stim_ref("AI.Stim.Hearing.Trap.NoiseAlarm", table),
        "source": "extracted/json/Gameplay/Traps/Actions/BP_Trap_Action_NoiseAlarm.json",
    }

    goo_cdo = bp.merged_cdo_props("BP_GooPipe_C")
    defaults["goo_pipe"] = {
        "auto_off_seconds": _round(goo_cdo.get("AutoTurnOffAfterTimeSeconds")),
        "puddle_radius_cm": _round(goo_cdo.get("Puddle Radius")),
        "puddle_spawn_interval_seconds": _round(
            goo_cdo.get("Puddle Spawn Attempt Interval Seconds")
        ),
        "puddle_emitter_velocity_cm_s": goo_cdo.get("PuddleEmitterVelocityRange"),
        "puddle_emitter_particle_count": goo_cdo.get("PuddleEmitterParticleCountRange"),
        "puddle_trace_cone_deg": _round(
            (goo_cdo.get("PuddleTraceParams") or {}).get("TraceConeAngleDeg")
        ),
        "source": "extracted/json/Gameplay/Interactables/GooPipe/BP_GooPipe.json",
    }

    vault_variants = {}
    for cls, file_stem in (
        ("BP_VaultDoor_Sliding_C", "BP_VaultDoor_Sliding"),
        ("BP_VaultDoor_Sliding_StartsOpen_C", "BP_VaultDoor_Sliding_StartsOpen"),
        ("BP_VaultDoor_SlidingDouble_C", "BP_VaultDoor_SlidingDouble"),
        (
            "BP_VaultDoor_SlidingDouble_AlwaysOpen_C",
            "BP_VaultDoor_SlidingDouble_AlwaysOpen",
        ),
    ):
        merged = bp.merged_cdo_props(cls)
        timeline = bp.first_component_props(cls, "TimelineTemplate")
        vault_variants[cls] = {
            "variant": vault_variant(cls),
            "SlideDistance_cm": _round(merged.get("SlideDistance")),
            "slide_seconds": _round(timeline.get("TimelineLength")),
            "starts_open": vault_starts_open(cls),
        }
    defaults["vault_door"] = {
        "variant": "single",
        "slide_seconds": 8.0,
        "can_lockpick": False,
        "_lockConfig": {
            "MaxLockLevel": (
                (
                    bp.merged_cdo_props("BP_OSESimpleWindow_C").get("_lockConfig") or {}
                ).get("MaxLockLevel")
            ),
        },
        "variants": vault_variants,
        "magnetic_lock": {
            "family": "magnetic_lock",
            "data_only": True,
            "_mode_default": bp.merged_cdo_props("BP_MagneticLockComponent_C").get(
                "_mode"
            ),
        },
        "source": "extracted/json/Gameplay/Interactables/Doors/BP_VaultDoor*.json",
    }

    defaults["power_wall"] = {
        "starts_on": True,
        "auto_reset_seconds_options": [0, 10, 30],
        "_state_default": {"bIsOn": True},
        "source": "15 placed BP_PowerSupply_Wall_C instances (all serialize _state.bIsOn=true)",
    }
    switch_cdo = bp.merged_cdo_props("BP_PowerSupply_LightSwitch_C")
    defaults["power_switch"] = {
        "starts_on": bool((switch_cdo.get("Struct Ref") or {}).get("bIsOn", False)),
        "_state_default": switch_cdo.get("Struct Ref"),
        "source": "extracted/json/Gameplay/Interactables/ElectricPower/BP_PowerSupply_LightSwitch.json",
    }

    defaults["junction"] = {
        "data_only": True,
        "source": "extracted/json/Gameplay/Interactables/ElectricPower/BP_PowerJunction*.json",
    }
    defaults["acoustic_portal"] = {
        "data_only": True,
        "source": "extracted/json/Audio/Audio_BPs/BP_TATAcousticPortal.json",
    }
    defaults["magnetic_lock"] = {
        "data_only": True,
        "component_only": True,
        "source": "attached to BP_VaultDoor* actors",
    }

    # Runtime fallbacks in Godot metres. The authored UE values above stay in
    # centimetres so nothing is silently rescaled; this block is the exact
    # metric form the runtime layer consumes.
    defaults["light_beam"]["metric"] = {
        "trigger_seconds": defaults["light_beam"]["trigger_seconds"],
        "reset_seconds": defaults["light_beam"]["reset_seconds"],
        "radius_m": _cm_to_m(defaults["light_beam"]["radius_cm"]),
        "axis": defaults["light_beam"]["axis"],
        "beam_length_default_m": _cm_to_m(
            defaults["light_beam"]["beam_length_default_cm"]
        ),
        "max_distance_default_m": _cm_to_m(
            defaults["light_beam"]["max_distance_to_fire_beam_default_cm"]
        ),
    }

    plate_stim = defaults["pressure_plate"]["hearing_stim"] or {}
    plate_damage = defaults["pressure_plate"]["damage"] or {}
    defaults["pressure_plate"]["metric"] = {
        "trigger_seconds": defaults["pressure_plate"]["trigger_seconds"],
        "reset_seconds": defaults["pressure_plate"]["reset_seconds"],
        "overlap_radius_m": _cm_to_m(defaults["pressure_plate"]["overlap_radius_cm"]),
        "plate_extent_m": _cm_list_to_m(defaults["pressure_plate"]["plate_extent_cm"]),
        "timeline_seconds": defaults["pressure_plate"]["timeline_seconds"],
        "damage": {
            "amount": ((plate_damage.get("DamageAmount") or {}).get("Value")),
            "type": ((plate_damage.get("DamageType") or {}).get("TagName")),
        },
        "hearing_stim": {
            "tag": plate_stim.get("tag"),
            "range_m": _cm_to_m(plate_stim.get("max_range_cm")),
            "severity": plate_stim.get("severity"),
        },
    }

    turret_metric_base = turret_variants["BP_SecurityTurret_C"]
    turret_metric_perception = turret_metric_base["perception"]
    defaults["turret"]["metric"] = {
        "sight_m": _cm_to_m(turret_metric_perception.get("SightRadius")),
        "lose_sight_m": _cm_to_m(turret_metric_perception.get("LoseSightRadius")),
        "half_fov_deg": turret_metric_perception.get("PeripheralVisionAngleDegrees"),
        "pov_backward_m": _cm_to_m(
            turret_metric_perception.get("PointOfViewBackwardOffset")
        ),
        "near_clip_m": _cm_to_m(turret_metric_perception.get("NearClippingRadius")),
        "max_age_seconds": defaults["turret"]["MaxAge"],
        "fire_interval_seconds_by_difficulty": defaults["turret"][
            "fire_interval_seconds_by_difficulty"
        ],
        "alarm_delay_seconds_by_difficulty": defaults["turret"][
            "alarm_delay_seconds_by_difficulty"
        ],
        "reset_seconds": defaults["turret"]["reset_seconds"],
        "projectile": {
            "speed_m_s": _cm_to_m(defaults["turret"]["projectile"]["max_speed_cm_s"]),
            "damage": (
                (
                    defaults["turret"]["projectile"]
                    .get("damage", {})
                    .get("DamageAmount")
                    or {}
                ).get("Value")
            ),
            "life_seconds": defaults["turret"]["projectile"]["life_span_seconds"],
        },
    }
    for cls, variant in turret_variants.items():
        variant["metric"] = {
            "starts_on": variant["starts_on"],
            "swivel_angle_deg": variant["_swivelAngle"],
            "swivel_seconds": variant["_swivelSeconds"],
            "swivel_pause_seconds": variant["_swivelPauseSeconds"],
            "swivel_reset_seconds": variant["_swivelResetTime"],
            "swivel_type": variant["_swivelType"],
        }

    alarm_stim = defaults["alarm_eye"]["stim"] or {}
    defaults["alarm_eye"]["metric"] = {
        "alarm_delay_seconds_by_difficulty": defaults["alarm_eye"][
            "alarm_delay_seconds_by_difficulty"
        ],
        "swivel_angle_deg": defaults["alarm_eye"]["swivel_angle_deg"],
        "swivel_seconds": defaults["alarm_eye"]["swivel_seconds"],
        "swivel_pause_seconds": defaults["alarm_eye"]["swivel_pause_seconds"],
        "stim": {
            "tag": alarm_stim.get("tag"),
            "range_m": _cm_to_m(alarm_stim.get("max_range_cm")),
            "severity": alarm_stim.get("severity"),
        },
    }
    for cls, variant in alarm_variants.items():
        perception = variant["perception"]
        variant["metric"] = {
            "sight_m": _cm_to_m(perception.get("SightRadius")),
            "lose_sight_m": _cm_to_m(perception.get("LoseSightRadius")),
            "half_fov_deg": perception.get("PeripheralVisionAngleDegrees"),
            "pov_backward_m": _cm_to_m(perception.get("PointOfViewBackwardOffset")),
            "near_clip_m": _cm_to_m(perception.get("NearClippingRadius")),
            "light_range_m": _cm_to_m(variant.get("LightRange")),
            "outer_cone_deg": variant.get("OuterConeAngle"),
            "inner_cone_deg": variant.get("InnerConeAngle"),
            "attenuation_m": _cm_to_m(variant.get("AttenuationRadius")),
            "alarm_delay_seconds": variant.get("_secondsUntilAlarmTriggers"),
        }

    defaults["ward_slow"]["metric"] = {
        "zone_size_m_default": _cm_list_to_m(
            defaults["ward_slow"]["ZoneSize_cm_default"]
        ),
        "initially_active": defaults["ward_slow"]["WardInitiallyActive"],
        "immunity_seconds": defaults["ward_slow"]["WardImmunityDuration"],
        "slow_multiplier": defaults["ward_slow"]["slow_multiplier"],
        "slow_seconds": defaults["ward_slow"]["slow_seconds"],
        "magic_damage": defaults["ward_slow"]["magic_damage"],
        "activate_hold_seconds": defaults["ward_slow"]["activate_hold_seconds"],
    }
    defaults["ward_blocker"]["metric"] = {
        "zone_size_m_default": _cm_list_to_m(
            defaults["ward_blocker"]["ZoneSize_cm_default"]
        ),
        "initially_active": defaults["ward_blocker"]["WardInitiallyActive"],
        "blocks_player_only": defaults["ward_blocker"]["blocks_player_only"],
        "impact_cooldown_seconds": defaults["ward_blocker"]["ImpactFXCooldown"],
    }

    noise_stim = defaults["noise_alarm"]["stim"] or {}
    defaults["noise_alarm"]["metric"] = {
        "trigger_seconds": 0.5,
        "trigger_overrides": 11,
        "trigger_nulls": 125,
        "stim": {
            "tag": noise_stim.get("tag"),
            "range_m": _cm_to_m(noise_stim.get("max_range_cm")),
            "severity": noise_stim.get("severity"),
        },
    }

    goo_velocity = defaults["goo_pipe"]["puddle_emitter_velocity_cm_s"] or {}
    defaults["goo_pipe"]["metric"] = {
        "auto_off_seconds": defaults["goo_pipe"]["auto_off_seconds"],
        "puddle_radius_m": _cm_to_m(defaults["goo_pipe"]["puddle_radius_cm"]),
        "spawn_interval_seconds": defaults["goo_pipe"]["puddle_spawn_interval_seconds"],
        "velocity_m_s": {
            "min": _cm_to_m(goo_velocity.get("min")),
            "max": _cm_to_m(goo_velocity.get("max")),
        },
        "particle_count": defaults["goo_pipe"]["puddle_emitter_particle_count"],
        "trace_cone_deg": defaults["goo_pipe"]["puddle_trace_cone_deg"],
    }

    for cls, variant in vault_variants.items():
        variant["metric"] = {
            "slide_distance_m": _cm_to_m(variant.get("SlideDistance_cm")),
            "slide_seconds": variant.get("slide_seconds"),
            "starts_open": variant.get("starts_open"),
        }
    defaults["vault_door"]["metric"] = {
        "slide_seconds": defaults["vault_door"]["slide_seconds"],
        "starts_open": {
            cls: variant["starts_open"] for cls, variant in vault_variants.items()
        },
        "slide_distance_m": {
            cls: variant["metric"]["slide_distance_m"]
            for cls, variant in vault_variants.items()
        },
        "can_lockpick": False,
    }

    defaults["power_wall"]["metric"] = {
        "starts_on": defaults["power_wall"]["starts_on"],
        "auto_reset_seconds_options": defaults["power_wall"][
            "auto_reset_seconds_options"
        ],
    }
    defaults["power_switch"]["metric"] = {
        "starts_on": defaults["power_switch"]["starts_on"]
    }
    defaults["junction"]["metric"] = {"data_only": True}
    defaults["acoustic_portal"]["metric"] = {"data_only": True}
    defaults["magnetic_lock"]["metric"] = {"data_only": True}

    return defaults


# ---------------------------------------------------------------------------
# Power graph
# ---------------------------------------------------------------------------
def resolve_power_source(rec: DeviceRecord) -> tuple[dict | None, list[dict]]:
    """Return (first resolved source ref, all electrical component edges)."""
    edges = []
    first = None
    for comp in rec.raw_map.components(rec.raw_actor, "TATElectricalDeviceComponent"):
        props = comp.get("Properties") or {}
        ref = props.get("_powerSource")
        if not isinstance(ref, dict):
            continue
        target = ref_target_actor(ref)
        edge = {"target": target, "raw": ref}
        edges.append(edge)
        if first is None:
            first = edge
    return first, edges


def power_require(rec: DeviceRecord, bp: BlueprintIndex) -> bool | None:
    cdo = bp.merged_cdo_props(rec.cls)
    if "_requirePowerToTrigger" in cdo:
        return bool(cdo["_requirePowerToTrigger"])
    for comp_cls in ("TATElectricalDeviceComponent",):
        # component class defaults are on the BP dump's component export
        props = bp.first_component_props(rec.cls, comp_cls)
        if "_requirePowerSource" in props:
            return bool(props["_requirePowerSource"])
    return None


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
def resolve_actions(rec: DeviceRecord) -> tuple[list[str], dict]:
    """Resolve the authored trigger list for one device.

    Dedupes by target name, drops nulls and keeps unresolved targets as ids.
    The census separates nulls dropped from non-empty lists (the reference
    audit's 613) from null-only lists (authored empty detectors, recorded
    separately instead of pretending they resolved).
    """
    ids: list[str] = []
    seen: set[str] = set()
    counts = {
        "lists": 0,
        "entries": 0,
        "nulls_total": 0,
        "nulls_dropped": 0,
        "nulls_in_empty_lists": 0,
        "duplicates_dropped": 0,
        "unresolved": 0,
    }
    for comp in rec.raw_map.components(rec.raw_actor, "TATTrapDetectorComponent"):
        props = comp.get("Properties") or {}
        if "TrapActionsToTrigger" not in props:
            continue
        entries = props.get("TrapActionsToTrigger") or []
        if not isinstance(entries, list):
            continue
        counts["lists"] += 1
        counts["entries"] += len(entries)
        valid = [e for e in entries if isinstance(e, dict)]
        list_has_actions = bool(valid)
        for entry in entries:
            if not isinstance(entry, dict):
                counts["nulls_total"] += 1
                if list_has_actions:
                    counts["nulls_dropped"] += 1
                else:
                    counts["nulls_in_empty_lists"] += 1
                continue
            target = ref_target_actor(entry)
            if not target:
                counts["unresolved"] += 1
                continue
            if target in seen:
                counts["duplicates_dropped"] += 1
                continue
            seen.add(target)
            stem = Path(rec.source_rel).name
            ids.append(
                f"{rec.map_id}/{stem}:{target}" if rec.map_id else f"{stem}:{target}"
            )
    return ids, counts


# ---------------------------------------------------------------------------
# Transform checks
# ---------------------------------------------------------------------------
def basis_check(basis) -> tuple[bool, bool]:
    """Return (orthonormal, det_positive) for a column-major 9-float basis."""
    if not isinstance(basis, list) or len(basis) != 9:
        return False, False
    try:
        vals = [float(v) for v in basis]
    except (TypeError, ValueError):
        return False, False
    cols = [vals[0:3], vals[3:6], vals[6:9]]
    ortho = True
    for col in cols:
        if abs(math.sqrt(sum(v * v for v in col)) - 1.0) > 1e-3:
            ortho = False
    for i in range(3):
        for j in range(i + 1, 3):
            if abs(sum(cols[i][k] * cols[j][k] for k in range(3))) > 1e-3:
                ortho = False
    det = (
        cols[0][0] * (cols[1][1] * cols[2][2] - cols[1][2] * cols[2][1])
        - cols[0][1] * (cols[1][0] * cols[2][2] - cols[1][2] * cols[2][0])
        + cols[0][2] * (cols[1][0] * cols[2][1] - cols[1][1] * cols[2][0])
    )
    return ortho, det > 0.0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    warnings: list[str] = []
    bp = bp_index()
    if not bp.by_class:
        raise SystemExit("[devices] no Blueprint CDO dumps found under extracted/json")
    table = hearing_stim_table()
    if not table:
        warnings.append(
            "DT_HearingStimProperties rows unavailable; hearing stim ranges are null"
        )

    sublevels_by_map = parse_map_sublevels()
    for map_id in list(sublevels_by_map):
        for rel in contract_sublevels_for_map(map_id):
            if rel not in sublevels_by_map[map_id]:
                sublevels_by_map[map_id].append(rel)

    maps_out: dict[str, dict] = {}
    family_loaded: Counter[str] = Counter()
    by_map: dict[str, int] = {}
    action_counts: Counter[str] = Counter()
    gameplay_action_nulls = 0
    power_edge_count = 0
    transform_stats = Counter()
    loaded_magnetic = 0
    generated_levels = GeneratedLevels()

    # Whole-game family census (all cooked map dumps, real actors only).
    family_whole: Counter[str] = Counter()
    whole_by_class: dict[str, Counter[str]] = defaultdict(Counter)
    magnetic_whole = 0
    bpp_skipped = 0
    for path in sorted(MAPS_DIR.rglob("*.json")):
        if path.name.startswith("BPP_"):
            continue
        try:
            doc = load_json(path)
        except Exception:  # noqa: BLE001, S112
            continue
        if not isinstance(doc, list):
            continue
        for export in doc:
            if not isinstance(export, dict):
                continue
            cls = str(export.get("Type", ""))
            if cls.startswith("BPP_") and "Turret" in cls:
                bpp_skipped += 1
                continue
            outer = export.get("Outer")
            if not is_level_outer(outer):
                if cls == "BP_MagneticLockComponent_C":
                    magnetic_whole += 1
                continue
            family = family_of(cls)
            if family:
                family_whole[family] += 1
                whole_by_class[family][cls] += 1
    family_whole["magnetic_lock"] = magnetic_whole

    # ---- per map -----------------------------------------------------------
    map_order = ["guildhall", "old_manor", "ftue", "thieves_den"]
    for map_id in map_order:
        if map_id not in sublevels_by_map:
            warnings.append(f"sublevel map missing from _map_id_to_sublevels: {map_id}")
            continue
        map_devices: list[dict] = []
        map_sources: list[dict] = []
        sublevels = sublevels_by_map[map_id]
        seen_ids: set[str] = set()
        for rel in sublevels:
            rf = raw_map(rel)
            if rf is None:
                warnings.append(f"missing raw map dump: extracted/json/Maps/{rel}.json")
                continue
            if rf.real_duplicates:
                warnings.append(
                    f"{rel}: {sum(rf.real_duplicates.values())} duplicate real-actor names"
                )
            records = collect_devices(rf, rel, warnings=warnings)
            # Magnetic locks are components attached to vault doors, not real
            # actors: census them as a component-only data family and carry
            # their presence on the owning door's params.
            for owner in rf.real:
                loaded_magnetic += len(
                    rf.components(owner, "BP_MagneticLockComponent_C")
                )
            # Deduplicate identical (actor, instance) records within a sublevel.
            deduped: list[DeviceRecord] = []
            seen_local: set[tuple[str, str]] = set()
            for rec in records:
                key = (rec.actor, rec.instance or "")
                if key in seen_local:
                    warnings.append(
                        f"{rel}: duplicate device actor {rec.actor} skipped"
                    )
                    continue
                seen_local.add(key)
                deduped.append(rec)

            for rec in deduped:
                rec.map_id = map_id
                device_id = f"{map_id}/{Path(rel).name}:{rec.actor}"
                if device_id in seen_ids:
                    warnings.append(f"duplicate device id skipped: {device_id}")
                    continue
                seen_ids.add(device_id)

                instance_label = f"{rel}.json::{rec.instance}" if rec.instance else None
                generated = generated_levels.find(rel, rec.actor, instance_label)
                if generated is not None:
                    pos = list(generated.get("pos") or [])
                    basis = list(generated.get("basis") or [])
                    scale = list(generated.get("scale") or [1.0, 1.0, 1.0])
                    transform_stats["matched_generated"] += 1
                else:
                    # Fallback: raw UE transform with the shared UE->Godot math.
                    world = rec.raw_map.actor_world_matrix(rec.raw_actor)
                    if rec.instance_world is not None:
                        # Compose the containing level-instance transform
                        # (captured from the containing map, not the source).
                        world = pt.mat4_mul(rec.instance_world, world)
                    trs = pt.ue_mat4_to_godot_trs(world)
                    pos = trs["pos"]
                    basis = trs["basis"]
                    scale = [1.0, 1.0, 1.0]
                    transform_stats["fallback_raw"] += 1
                    warnings.append(
                        f"{device_id}: no generated actor; raw transform fallback"
                    )

                ortho, det_ok = basis_check(basis)
                if not ortho:
                    transform_stats["non_orthonormal_basis"] += 1
                    warnings.append(f"{device_id}: basis is not orthonormal")
                if not det_ok:
                    transform_stats["det_not_positive"] += 1
                    warnings.append(f"{device_id}: basis determinant is not +1")
                authored_scale = [float(v) for v in scale]
                scale_non_unit = any(abs(v - 1.0) > 1e-4 for v in authored_scale)
                if scale_non_unit:
                    transform_stats["non_unit_scale_any"] += 1

                overrides = (
                    rec.raw_map.exports[rec.raw_map.real[rec.raw_actor]].get(
                        "Properties"
                    )
                    or {}
                )
                params = device_params(rec, overrides)
                params = {
                    k: _round(v) if isinstance(v, float) else v
                    for k, v in params.items()
                }

                if scale_non_unit:
                    if rec.family == "acoustic_portal":
                        # Data-only family: the runtime never applies this
                        # transform (the level loader owns the portal box);
                        # keep the authored box scale in params and emit the
                        # unit device scale invariant.
                        params["authored_scale"] = [
                            _round(v, 4) for v in authored_scale
                        ]
                        scale = [1.0, 1.0, 1.0]
                    else:
                        transform_stats["non_unit_scale"] += 1
                        warnings.append(f"{device_id}: non-unit authored scale {scale}")

                # Powers: component instances joined via Outer within the file.
                source_ref, edges = resolve_power_source(rec)
                source_id = None
                if source_ref and source_ref.get("target"):
                    source_id = f"{map_id}/{Path(rel).name}:{source_ref['target']}"
                    if source_ref["target"] not in rec.raw_map.real:
                        warnings.append(
                            f"{device_id}: power source unresolved: {source_ref['target']}"
                        )
                        transform_stats["power_unresolved"] += 1
                power_edge_count += len(edges)

                actions, action_stats = resolve_actions(rec)
                for key in (
                    "lists",
                    "entries",
                    "nulls_total",
                    "nulls_dropped",
                    "nulls_in_empty_lists",
                    "duplicates_dropped",
                    "unresolved",
                ):
                    action_counts[key] += action_stats[key]
                # Reference-audit scope: the null census was taken over the
                # *_Gameplay sublevels. Keep that headline number and record
                # the all-loaded total separately.
                if str(rel).split("/")[-1].endswith("_Gameplay"):
                    gameplay_action_nulls += action_stats["nulls_total"]

                record = {
                    "id": device_id,
                    "map": map_id,
                    "sublevel": Path(rel).name,
                    "sublevel_path": rel,
                    "actor": rec.actor,
                    "class": rec.cls,
                    "family": rec.family,
                    "pos": [_round(float(v), 4) for v in pos],
                    "basis": [_round(float(v), 5) for v in basis],
                    "scale": [_round(float(v), 4) for v in scale],
                    "params": params,
                    "power": {
                        "source": source_id,
                        "require": power_require(rec, bp),
                        # Authored TATElectricalDeviceComponent instances that
                        # serialize a _powerSource (noise alarms carry two).
                        "edges": len(edges),
                    },
                    "actions": actions,
                    "breakable": None,
                }
                if rec.instance:
                    record["level_instance"] = rec.instance
                    record["source_sublevel"] = rec.source_rel
                map_devices.append(record)

                if rec.family == "power_wall":
                    map_sources.append(
                        {
                            "id": device_id,
                            "map": map_id,
                            "sublevel": Path(rel).name,
                            "sublevel_path": rel,
                            "actor": rec.actor,
                            "class": rec.cls,
                            "pos": record["pos"],
                            "params": params,
                        }
                    )

            # Raw exports are no longer needed once this sublevel's devices,
            # actions and power refs are resolved; release the cache so a map
            # with several 30 MB dumps does not hold all of them at once.
            _MAP_CACHE.pop(rel, None)

        # Sort for deterministic output (sublevel, actor).
        map_devices.sort(key=lambda d: (d["sublevel"], d["actor"], d["id"]))
        map_sources.sort(key=lambda d: (d["sublevel"], d["actor"], d["id"]))
        maps_out[map_id] = {
            "sublevels": sublevels,
            "devices": map_devices,
            "power_sources": map_sources,
        }
        by_map[map_id] = len(map_devices)
        family_loaded.update(d["family"] for d in map_devices)

        # Cross-check the authored device list against the generated level
        # actors the loader actually consumes (excluding BPP packed-level
        # wrappers). A mismatch means the join/filter is wrong.
        for rel in sublevels:
            idx = generated_levels.actors(rel)
            if not idx["ok"]:
                continue
            generated_names = {
                (str(a.get("name", "")), str(a.get("level_instance", "")))
                for entries in idx["by_name"].values()
                for a in entries
                if family_of(str(a.get("class", "")))
            }
            ours = {
                (
                    d["actor"],
                    f"{rel}.json::{d['level_instance']}"
                    if "level_instance" in d
                    else "",
                )
                for d in map_devices
                if d.get("sublevel_path") == rel
            }
            if generated_names != ours:
                transform_stats["generated_crosscheck_mismatches"] += 1
                missing = generated_names - ours
                extra = ours - generated_names
                if missing:
                    warnings.append(
                        f"{rel}: {len(missing)} generated device actors missing from producer"
                    )
                if extra:
                    warnings.append(
                        f"{rel}: {len(extra)} producer devices absent from generated level"
                    )

    # ---- power source feed counts -----------------------------------------
    all_sources = {
        src["id"]: src for m in maps_out.values() for src in m["power_sources"]
    }
    feed_counts: Counter[str] = Counter()
    for m in maps_out.values():
        for d in m["devices"]:
            src = d.get("power", {}).get("source")
            if src:
                feed_counts[src] += 1
    for src_id, src in all_sources.items():
        src["feeds_devices"] = feed_counts.get(src_id, 0)
    sources_feeding = sum(1 for v in feed_counts.values() if v > 0)
    source_names_feeding = len(
        {
            src["actor"]
            for src_id, src in all_sources.items()
            if feed_counts.get(src_id, 0) > 0
        }
    )

    # ---- stats -------------------------------------------------------------
    class_counts_loaded: dict[str, Counter[str]] = defaultdict(Counter)
    for m in maps_out.values():
        for d in m["devices"]:
            class_counts_loaded[d["family"]][d["class"]] += 1

    families_stats = {}
    for family in FAMILY_ORDER:
        entry = {
            "loaded": int(family_loaded.get(family, 0)),
            "whole_game": int(family_whole.get(family, 0)),
            "runtime": family in RUNTIME_FAMILIES,
            "by_class_whole_game": dict(sorted(whole_by_class.get(family, {}).items())),
            "by_class_loaded": dict(
                sorted(class_counts_loaded.get(family, {}).items())
            ),
        }
        if family == "magnetic_lock":
            entry["component_only"] = True
            entry["loaded"] = loaded_magnetic
            entry["whole_game"] = magnetic_whole
            entry["devices"] = 0
            entry["by_class_whole_game"] = {
                "BP_MagneticLockComponent_C": magnetic_whole
            }
            entry["by_class_loaded"] = {"BP_MagneticLockComponent_C": loaded_magnetic}
        families_stats[family] = entry

    all_devices = [d for m in maps_out.values() for d in m["devices"]]
    beam_lengths_all = [
        d["params"]["BeamLength"]
        for d in all_devices
        if d["family"] == "light_beam" and "BeamLength" in d["params"]
    ]
    beam_lengths_guildhall = [
        d["params"]["BeamLength"]
        for d in maps_out.get("guildhall", {}).get("devices", [])
        if d["family"] == "light_beam" and "BeamLength" in d["params"]
    ]
    beam_max_all = [
        d["params"]["MaxDistanceToFireBeam"]
        for d in all_devices
        if d["family"] == "light_beam" and "MaxDistanceToFireBeam" in d["params"]
    ]

    stats = {
        "devices_total": sum(by_map.values()),
        "by_map": by_map,
        "families": families_stats,
        "actions": {
            "edges": sum(
                len(d["actions"]) for m in maps_out.values() for d in m["devices"]
            ),
            "nulls_dropped": gameplay_action_nulls,
            "nulls_dropped_all_loaded": action_counts["nulls_total"],
            "nulls_in_empty_lists": action_counts["nulls_in_empty_lists"],
            "duplicates_dropped": action_counts["duplicates_dropped"],
            "unresolved": action_counts["unresolved"],
            "lists": action_counts["lists"],
            "entries": action_counts["entries"],
        },
        "power": {
            "edges": power_edge_count,
            "devices_with_source": sum(
                1
                for m in maps_out.values()
                for d in m["devices"]
                if d["power"]["source"]
            ),
            "sources": len(all_sources),
            "sources_feeding_devices": sources_feeding,
            "source_names_feeding_devices": source_names_feeding,
            "unresolved": transform_stats["power_unresolved"],
        },
        "transforms": {
            "matched_generated": transform_stats["matched_generated"],
            "fallback_raw": transform_stats["fallback_raw"],
            "level_instance_expanded": sum(
                1
                for m in maps_out.values()
                for d in m["devices"]
                if "level_instance" in d
            ),
            "non_unit_scale": transform_stats["non_unit_scale"],
            "non_unit_scale_any": transform_stats["non_unit_scale_any"],
            "non_orthonormal_basis": transform_stats["non_orthonormal_basis"],
            "det_not_positive": transform_stats["det_not_positive"],
            "generated_crosscheck_mismatches": transform_stats[
                "generated_crosscheck_mismatches"
            ],
            "bpp_packed_level_actors_skipped": bpp_skipped,
        },
        "param_units": {
            "per_instance_params": (
                "authored UE units under the original property names "
                "(lengths cm, angles deg, times s); emitted only when serialized"
            ),
            "family_defaults_metric": "Godot metric fallbacks (m, deg, s)",
            "pos_basis_scale": "Godot metres / column-major basis",
        },
        "param_stats": {
            "light_beam": {
                "BeamLength_cm_all_loaded": numeric_summary(beam_lengths_all),
                "BeamLength_cm_guildhall": numeric_summary(beam_lengths_guildhall),
                "MaxDistanceToFireBeam_cm_overrides": numeric_summary(beam_max_all),
            }
        },
        "family_defaults": family_defaults(bp, table),
        "expected": {
            "devices_total": EXPECTED_TOTAL,
            "by_map": EXPECTED_BY_MAP,
            "families": EXPECTED_FAMILY_COUNTS,
        },
    }

    # The reference audit's "nulls dropped" is 613: it scopes the action scan
    # to the *_Gameplay sublevels. OldManor_PickUps carries one null-only
    # pressure-plate list (5 nulls) outside that scope. Keep the audit number
    # as the headline and the all-loaded number explicit.
    stats["actions"]["nulls_dropped_gameplay_scope"] = gameplay_action_nulls
    stats["actions"]["nulls_outside_gameplay_scope"] = (
        action_counts["nulls_total"] - gameplay_action_nulls
    )

    # ---- explicit nulls / ambiguities -------------------------------------
    power_relevant = {
        "turret",
        "alarm_eye",
        "light_beam",
        "pressure_plate",
        "noise_alarm",
        "vault_door",
    }
    null_require = Counter(
        d["family"]
        for d in all_devices
        if d["family"] in power_relevant and d["power"]["require"] is None
    )
    if null_require:
        warnings.append(
            "power.require is null where the class CDO serializes neither "
            "_requirePowerToTrigger nor _requirePowerSource: "
            + ", ".join(f"{k}={v}" for k, v in sorted(null_require.items()))
        )
    noise_null = sum(
        1
        for d in all_devices
        if d["family"] == "noise_alarm"
        and d["params"].get("_triggeringDuration") is None
    )
    noise_set = sum(
        1
        for d in all_devices
        if d["family"] == "noise_alarm"
        and d["params"].get("_triggeringDuration") is not None
    )
    if noise_null:
        warnings.append(
            f"noise_alarm: {noise_set} placements serialize _triggeringDuration=0.5, "
            f"{noise_null} carry null and use the runtime fallback"
        )
    null_starts = [
        cls
        for cls, variant in stats["family_defaults"]["turret"]["variants"].items()
        if variant.get("starts_on") is None
    ]
    if null_starts:
        warnings.append(
            "turret variant starts_on is not serialized for "
            + ", ".join(null_starts)
            + "; params.starts_on stays null and the runtime fallback applies"
        )
    if transform_stats["non_unit_scale_any"]:
        warnings.append(
            f"{transform_stats['non_unit_scale_any']} acoustic_portal placements carry non-unit authored scale; "
            "the device transform is normalized to [1,1,1] and the authored box "
            "scale is preserved in params.authored_scale (data-only family)"
        )
    if bpp_skipped:
        warnings.append(
            f"{bpp_skipped} BPP_* packed-level wrapper named '*Turret*' skipped "
            "(ISMs only, no device components)"
        )
    warnings.append(
        f"magnetic_lock is component-only: {loaded_magnetic} BP_MagneticLockComponent_C "
        "instances attached to vault doors; emitted as vault params and stats, not as "
        "separate device records (keeps the authored device census at 2095)"
    )
    warnings.append(
        "action lists not serialized on 141 TATTrapDetectorComponent instances "
        "(5 alarm eyes, 136 noise alarms); actions=[] is the authored empty list"
    )
    warnings.append(
        "BP_MagicAlarm_ShortRange_Narrow_C ships the LongRange perception block "
        "(2500/3000/10); emitted exactly as authored"
    )
    warnings.append(
        "light_beam MaxDistanceToFireBeam default is 5000 cm (50 m) in the "
        "BP_Detector_LightBeam CDO; emitted as authored (the review note's "
        "'5 m' reads as a 10x typo, not a second authored value)"
    )

    payload = {
        "schema": SCHEMA,
        "source": (
            f"extracted/json/Maps/** + extracted/json/Gameplay/**/BP_*.json ({GAME_VERSION}); "
            "params keep authored UE units (cm/s/deg), pos/basis/scale are Godot "
            "metres/column-major from game/data/generated/levels/*.tatlevel.json"
        ),
        "maps": maps_out,
        "stats": stats,
        "warnings": warnings,
    }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")

    print_census(payload)
    return 0


def print_census(payload: dict) -> None:
    stats = payload["stats"]
    print(f"TAT-2 devices runtime -> {OUT_PATH.relative_to(ROOT)}")
    print(f"  schema: {payload['schema']}")
    total = stats["devices_total"]
    marker = "OK" if total == EXPECTED_TOTAL else "MISMATCH"
    print(f"  total devices: {total} (expected {EXPECTED_TOTAL}) [{marker}]")
    for map_id in ("guildhall", "old_manor", "ftue", "thieves_den"):
        have = stats["by_map"].get(map_id, 0)
        want = EXPECTED_BY_MAP.get(map_id)
        marker = "OK" if have == want else f"MISMATCH expected {want}"
        subs = len(payload["maps"].get(map_id, {}).get("sublevels", []))
        print(f"    {map_id:<12} {have:>5}  ({subs} sublevels) [{marker}]")

    act = stats["actions"]
    print(
        "  detector->action edges: "
        f"{act['edges']} edges, {act['nulls_dropped_gameplay_scope']} nulls dropped, "
        f"{act['duplicates_dropped']} duplicates dropped, {act['unresolved']} unresolved"
    )
    print(
        "    all loaded sublevels: "
        f"{act['nulls_dropped_all_loaded']} nulls ({act['nulls_outside_gameplay_scope']} "
        f"outside *_Gameplay, {act['nulls_in_empty_lists']} in null-only lists)"
    )
    pw = stats["power"]
    print(
        f"  power: {pw['edges']} device->power edges, {pw['sources']} power sources, "
        f"{pw['source_names_feeding_devices']} distinct supplies feed devices "
        f"({pw['sources_feeding_devices']} loaded source records), {pw['unresolved']} unresolved"
    )
    tr = stats["transforms"]
    print(
        "  transforms: "
        f"{tr['matched_generated']} generated, {tr['fallback_raw']} raw fallback, "
        f"{tr['level_instance_expanded']} level-instance expanded, "
        f"{tr['non_unit_scale']} non-unit behaviour scales, "
        f"{tr['non_orthonormal_basis']} non-orthonormal bases, "
        f"{tr['bpp_packed_level_actors_skipped']} BPP wrappers skipped"
    )
    beam = (
        stats.get("param_stats", {})
        .get("light_beam", {})
        .get("BeamLength_cm_guildhall")
        or {}
    )
    if beam:
        print(
            "  guildhall BeamLength (cm): "
            f"n={beam['count']} min={beam['min']} p50={beam['p50']} max={beam['max']}"
        )
    print("  families (loaded / whole game):")
    for family in FAMILY_ORDER:
        entry = stats["families"][family]
        want = EXPECTED_FAMILY_COUNTS.get(family)
        have = (
            entry["whole_game"]
            if family in ("acoustic_portal", "magnetic_lock")
            else entry["loaded"]
        )
        marker = ""
        if want is not None:
            marker = " [OK]" if have == want else f" [MISMATCH expected {want}]"
        extra = " data-only" if not entry.get("runtime") else ""
        print(
            f"    {family:<16} {entry['loaded']:>5} / {entry['whole_game']:>5}{extra}{marker}"
        )
    if payload["warnings"]:
        print(f"  warnings: {len(payload['warnings'])}")
        for warning in payload["warnings"][:12]:
            print(f"    - {warning}")
        if len(payload["warnings"]) > 12:
            print(f"    ... {len(payload['warnings']) - 12} more (see JSON warnings)")


if __name__ == "__main__":
    raise SystemExit(main())
