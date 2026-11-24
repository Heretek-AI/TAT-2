#!/usr/bin/env python3
"""Emit the authored hearing + perception tables for TAT-2.

Reads the shipped cooked dumps

    extracted/json/AI/Data/DT_HearingStimProperties.json        54 stim rows
    extracted/json/AI/Data/DA_LoudnessModifiers.json            22 surfaces
    extracted/json/AI/Data/DT_StimProperties.json               8 vision stim rows
    extracted/json/AI/Perception/DA_PerceptionSharedConfig_*.json
    extracted/json/Gameplay/Weather/DT_WeatherTypes.json        11 weather rows
    extracted/json/Audio/Audio_BPs/BP_TATAcousticPortal.json    portal box default
    extracted/json/Maps/**/*.json                               285 portal actors

and writes

    game/data/generated/gameplay/hearing.json
    game/data/generated/gameplay/perception.json

hearing.json is the auditory layer: every ``TATHearingEventStimSettings`` row
(tag, severity, propagation method, heard-by flags, max/inner/outer range,
behaviours, stimulus query bitmask), the physical-material loudness
multipliers, the weather sound-carry tags per weather type, the hearing range
modifiers from the shared perception config, and the full acoustic-portal list
with Godot-space transforms.

perception.json is the shared sensory layer: both ``DA_PerceptionSharedConfig``
files (hearing and vision range modifiers), the weather gameplay metadata
(visibility + sound carry per weather type) and the non-audio stim severities
from ``DT_StimProperties``.

Source fidelity rules:

* Ranges stay in the authored centimetres under the original property names,
  with a ``metric`` mirror in metres (the same convention as
  ``devices_runtime.json``). Nothing is rescaled in place and nothing is
  invented: a property absent from the cooked row is emitted as null.
* ``Authored`` tags keep their UE spelling, including the shipped typo
  ``PropogateThroughOpenPortals``.
* The weather -> sound-carry multipliers are a join, not a guess: each weather
  row names a ``Weather.SoundCarry.*`` tag, and the hearing shared config gives
  that tag's range modifier (High 1.0 / Mid 0.9 / Low 0.8 / High_Extra 1.25).
  The joined value is emitted as ``range_multiplier`` next to the raw tag.
* Portal transforms are converted with the same UE->Godot math as
  ``parse_tables.py`` (x = ue.x/100, y = ue.z/100, z = ue.y/100, column-major
  basis). The authored portal-box scale lives on the portal root component, so
  the emitted ``scale`` is the box size, not a unit vector; the box is the
  default 100 cm cube from the Blueprint CDO unless overridden per instance.

No runtime wiring: ``game/src/ai/guard_ai.gd`` still uses its own constants and
``game/data/generated/gameplay/guard_ai.json`` (from ``parse_gameplay.py``)
keeps the short surface-name loudness form for the current code path.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import parse_tables as pt

ROOT = Path(__file__).resolve().parent.parent
JSON_ROOT = ROOT / "extracted" / "json"
OUT_DIR = ROOT / "game" / "data" / "generated" / "gameplay"
HEARING_OUT = OUT_DIR / "hearing.json"
PERCEPTION_OUT = OUT_DIR / "perception.json"
DEVICES_RUNTIME = OUT_DIR / "devices_runtime.json"

SCHEMA_HEARING = "tat2.hearing/1"
SCHEMA_PERCEPTION = "tat2.perception/1"
GAME_VERSION = "Steam 1.5.193.148559"

HEARING_DT = JSON_ROOT / "AI" / "Data" / "DT_HearingStimProperties.json"
VISION_DT = JSON_ROOT / "AI" / "Data" / "DT_StimProperties.json"
LOUDNESS_DA = JSON_ROOT / "AI" / "Data" / "DA_LoudnessModifiers.json"
PERCEPTION_DIR = JSON_ROOT / "AI" / "Perception"
WEATHER_DT = JSON_ROOT / "Gameplay" / "Weather" / "DT_WeatherTypes.json"
PORTAL_BP = JSON_ROOT / "Audio" / "Audio_BPs" / "BP_TATAcousticPortal.json"
MAPS_DIR = JSON_ROOT / "Maps"

EXPECTED_HEARING_ROWS = 54
EXPECTED_LOUDNESS_SURFACES = 22
EXPECTED_WEATHER_ROWS = 11
EXPECTED_VISION_ROWS = 8
EXPECTED_PORTALS = 285
PORTAL_CLASS = "BP_TATAcousticPortal_C"
PORTAL_BOX_EXTENT_CM = 100.0

SEVERITIES = {"Light", "Heavy"}
HEARD_BY_FIELDS = ("DetectHostiles", "DetectNeutrals", "DetectFriendlies")
WEATHER_CARRY_TAGS = {
    "Weather.SoundCarry.High",
    "Weather.SoundCarry.Mid",
    "Weather.SoundCarry.Low",
    "Weather.SoundCarry.High_Extra",
}
WEATHER_VISIBILITY_TAGS = {
    "Weather.Visibility.High",
    "Weather.Visibility.Mid",
    "Weather.Visibility.Low",
}


class Fail(RuntimeError):
    pass


def load_json(path: Path):
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def one_asset(path: Path, name: str | None = None) -> dict:
    data = load_json(path)
    if not isinstance(data, list) or not data:
        raise Fail(f"{path.name}: expected a non-empty export list")
    if name is None:
        for item in data:
            if isinstance(item.get("Properties"), dict):
                return item
        raise Fail(f"{path.name}: no export with Properties")
    for item in data:
        if item.get("Name") == name:
            return item
    raise Fail(f"{path.name}: no export named {name!r}")


def tag_name(value) -> str:
    return str(value.get("TagName", "")) if isinstance(value, dict) else ""


def enum_tail(value, label: str) -> str:
    text = str(value or "")
    if "::" not in text:
        raise Fail(f"{label}: expected an E* enum value, got {text!r}")
    return text.split("::")[-1]


def m(value_cm: float) -> float:
    return round(value_cm / 100.0, 4)


def rows_of(path: Path) -> dict:
    asset = one_asset(path)
    rows = asset.get("Rows")
    if not isinstance(rows, dict):
        raise Fail(f"{path.name}: no Rows")
    return asset, rows


# ---------------------------------------------------------------------------
# Hearing stimuli
# ---------------------------------------------------------------------------
def hearing_stimuli(rows: dict) -> tuple[list[dict], list[str]]:
    seen: set[str] = set()
    out: list[dict] = []
    anomalies: list[str] = []
    for row_name, row in rows.items():
        label = f"hearing row {row_name}"
        tag = tag_name(row.get("Tag"))
        if not tag:
            raise Fail(f"{label}: no AI.Stim.Hearing tag")
        if tag in seen:
            raise Fail(f"{label}: duplicate tag {tag}")
        seen.add(tag)

        severity = enum_tail(row.get("Severity"), f"{label} Severity")
        if severity not in SEVERITIES:
            raise Fail(f"{label}: unknown severity {severity!r}")
        propagation = enum_tail(row.get("VolumeLevel"), f"{label} VolumeLevel")

        heard_by_raw = row.get("HeardBy") or {}
        for field in HEARD_BY_FIELDS:
            if not isinstance(heard_by_raw.get(field), bool):
                raise Fail(f"{label}: HeardBy.{field} is not a bool")

        ranges = {
            "max_range_cm": row.get("MaxRange"),
            "inner_investigation_range_cm": row.get("InnerInvestigationRange"),
            "outer_investigation_range_cm": row.get("OuterInvestigationRange"),
        }
        for key, value in ranges.items():
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                raise Fail(f"{label}: {key} is not numeric ({value!r})")

        behaviours = row.get("Behaviors")
        if not isinstance(behaviours, list) or not behaviours:
            raise Fail(f"{label}: Behaviors is empty")
        query_bitmask = row.get("QueryBitmask")
        if not isinstance(query_bitmask, int) or isinstance(query_bitmask, bool):
            raise Fail(f"{label}: QueryBitmask is not an int")
        if not 0 <= query_bitmask <= 255:
            raise Fail(f"{label}: QueryBitmask {query_bitmask} outside 0..255")

        if (
            ranges["inner_investigation_range_cm"]
            > ranges["outer_investigation_range_cm"]
        ):
            anomalies.append(
                f"{row_name}: inner {ranges['inner_investigation_range_cm']} cm > "
                f"outer {ranges['outer_investigation_range_cm']} cm (authored)"
            )
        if ranges["outer_investigation_range_cm"] > ranges["max_range_cm"]:
            anomalies.append(
                f"{row_name}: outer {ranges['outer_investigation_range_cm']} cm > "
                f"max {ranges['max_range_cm']} cm (authored)"
            )

        out.append(
            {
                "row": row_name,
                "tag": tag,
                "severity": severity,
                "propagation": propagation,
                "heard_by": {
                    "hostiles": heard_by_raw["DetectHostiles"],
                    "neutrals": heard_by_raw["DetectNeutrals"],
                    "friendlies": heard_by_raw["DetectFriendlies"],
                },
                **ranges,
                "behaviors": [str(b) for b in behaviours],
                "query_bitmask": query_bitmask,
                "metric": {
                    "max_range_m": m(ranges["max_range_cm"]),
                    "inner_investigation_range_m": m(
                        ranges["inner_investigation_range_cm"]
                    ),
                    "outer_investigation_range_m": m(
                        ranges["outer_investigation_range_cm"]
                    ),
                },
            }
        )
    return out, anomalies


# ---------------------------------------------------------------------------
# Loudness + shared perception config
# ---------------------------------------------------------------------------
def loudness_modifiers(asset: dict) -> dict:
    props = asset.get("Properties") or {}
    rows = props.get("_PhysicalMaterialToLoudnessModifier")
    if not isinstance(rows, list):
        raise Fail("DA_LoudnessModifiers: no _PhysicalMaterialToLoudnessModifier")
    if len(rows) != EXPECTED_LOUDNESS_SURFACES:
        raise Fail(
            f"DA_LoudnessModifiers has {len(rows)} surfaces, "
            f"expected {EXPECTED_LOUDNESS_SURFACES}"
        )
    surfaces: dict[str, dict] = {}
    for entry in rows:
        package = str(entry.get("Key", ""))
        if not package:
            raise Fail("DA_LoudnessModifiers: row without a Key")
        name = package.split(".")[-1]
        if name in surfaces:
            raise Fail(f"DA_LoudnessModifiers: duplicate surface {name}")
        value = entry.get("Value") or {}
        multiplier = value.get("Multiplier")
        if not isinstance(multiplier, (int, float)) or isinstance(multiplier, bool):
            raise Fail(f"DA_LoudnessModifiers: {name} has no numeric Multiplier")
        surfaces[name] = {
            "package": package,
            "multiplier": float(multiplier),
        }
    anchors = {"Carpet": 0.0, "Stone": 1.5, "Lattice": 1.0, "Glass": 1.5}
    for name, want in anchors.items():
        have = surfaces.get(name, {}).get("multiplier")
        if have != want:
            raise Fail(f"DA_LoudnessModifiers anchor {name}: have {have}, want {want}")
    return {
        "asset": "/Game/AI/Data/DA_LoudnessModifiers",
        "surfaces": len(surfaces),
        "by_surface": surfaces,
        "notes": (
            "Multiplier scales the loudness of a hearing stimulus emitted on that "
            "physical material: 0.0 silences it (carpet, grass, foliage, dirt, ivy), "
            "1.0 is neutral, 1.5 amplifies. Authored per surface, keyed by the "
            "UE physical-material package."
        ),
    }


def perception_config(path: Path) -> dict:
    asset = one_asset(path)
    name = str(asset.get("Name", path.stem))
    props = asset.get("Properties") or {}
    modifiers = props.get("RangePerceptionModifiers")
    if not isinstance(modifiers, list):
        raise Fail(f"{path.name}: no RangePerceptionModifiers")
    rows = []
    seen: set[str] = set()
    for raw in modifiers:
        tag = tag_name(raw.get("GameplayTag"))
        if not tag:
            raise Fail(f"{path.name}: modifier without a GameplayTag")
        if tag in seen:
            raise Fail(f"{path.name}: duplicate modifier tag {tag}")
        seen.add(tag)
        value = raw.get("ModifierIfGameplayTagPresent")
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            raise Fail(f"{path.name}: {tag} has no numeric modifier")
        rows.append({"tag": tag, "range_multiplier": float(value)})
    return {
        "asset": f"/Game/AI/Perception/{name}",
        "class": str(asset.get("Type", "")),
        "range_modifier_semantics": (
            "multiplicative range modifier applied while the gameplay tag is "
            "present (inferred from RangePerceptionModifiers/"
            "ModifierIfGameplayTagPresent; not runtime-verified in this port)"
        ),
        "range_modifiers": rows,
    }


# ---------------------------------------------------------------------------
# Weather gameplay metadata
# ---------------------------------------------------------------------------
def weather_rows(
    rows: dict, carry_multipliers: dict[str, float]
) -> tuple[dict, list[str]]:
    out: dict[str, dict] = {}
    problems: list[str] = []
    for row_name, row in rows.items():
        tag = tag_name(row.get("WeatherType"))
        if not tag:
            raise Fail(f"weather row {row_name}: no WeatherType tag")
        if tag != row_name:
            raise Fail(f"weather row {row_name}: WeatherType {tag} disagrees")
        metadata = row.get("GameplayMetadata")
        if not isinstance(metadata, dict):
            raise Fail(f"weather row {row_name}: no GameplayMetadata")

        carry = {}
        visibility = {}
        for context in ("Indoors", "Outdoors"):
            key = context.lower()
            carry_tag = tag_name(metadata.get(f"SoundCarry{context}"))
            vis_tag = tag_name(metadata.get(f"Visibility{context}"))
            if carry_tag not in WEATHER_CARRY_TAGS:
                raise Fail(f"weather row {row_name}: bad SoundCarry{context}")
            if vis_tag not in WEATHER_VISIBILITY_TAGS:
                raise Fail(f"weather row {row_name}: bad Visibility{context}")
            carry[key] = {
                "tag": carry_tag,
                "level": carry_tag.split(".")[-1],
                "range_multiplier": carry_multipliers.get(carry_tag),
            }
            if carry_multipliers.get(carry_tag) is None:
                problems.append(
                    f"{row_name}/{key}: {carry_tag} has no hearing range modifier"
                )
            visibility[key] = {
                "tag": vis_tag,
                "level": vis_tag.split(".")[-1],
            }

        label_ref = row.get("Label") or {}
        label = str(
            label_ref.get("CultureInvariantString")
            or label_ref.get("LocalizedString")
            or label_ref.get("SourceString")
            or ""
        )
        level_filter = str(row.get("LevelFilterMode", ""))
        filter_list = row.get("LevelFilterList") or []
        out[tag] = {
            "tag": tag,
            "label": label,
            "default_preset": str(
                (row.get("DefaultPreset") or {}).get("AssetPathName", "")
            ),
            "visibility": visibility,
            "sound_carry": carry,
            "level_filter_mode": enum_tail(level_filter, f"{row_name} LevelFilterMode"),
            "level_filter_list": [
                str(item.get("AssetPathName", "")) for item in filter_list
            ],
        }
    return out, problems


# ---------------------------------------------------------------------------
# Acoustic portals (all 285 authored placements, not only the loaded 14)
# ---------------------------------------------------------------------------
def load_portal_box() -> dict:
    exports = load_json(PORTAL_BP)
    box = None
    audio = None
    for export in exports:
        name = str(export.get("Name", ""))
        props = export.get("Properties") or {}
        if name.startswith("Portal Box Trigger"):
            box = props
        elif name.startswith("TATAudioPortal"):
            audio = props
    if box is None:
        raise Fail("BP_TATAcousticPortal: no Portal Box Trigger component")
    extent = box.get("BoxExtent")
    if not isinstance(extent, dict):
        raise Fail("BP_TATAcousticPortal: Portal Box Trigger has no BoxExtent")
    return {
        "box_extent_cm": [
            float(extent.get("X", 0.0)),
            float(extent.get("Y", 0.0)),
            float(extent.get("Z", 0.0)),
        ],
        "hidden_in_game": bool((audio or {}).get("bHiddenInGame", False)),
    }


def _split_owner(text: str) -> tuple[str, str]:
    """Split a UE object path into (owning_actor, component).

    ``"...:PersistentLevel.Actor_1.DefaultSceneRoot"`` becomes
    ``("Actor_1", "DefaultSceneRoot")``; a Blueprint-expanded sublevel writes
    the owner alone (``"...:PersistentLevel.Actor_1"``), so the component name
    then comes from the export's own ``Name``. Component names repeat in every
    actor of a level, so they are only addressable with their owner.
    """
    if "'" in text:
        text = text.split("'", 2)[1]
    if "PersistentLevel" in text:
        text = text.split("PersistentLevel", 1)[1].lstrip(".")
    text = text.strip("'")
    if not text:
        return "", ""
    if "." in text:
        owner, _, name = text.rpartition(".")
        return owner, name
    return text, ""


def portal_actors() -> list[dict]:
    portals: list[dict] = []
    for path in sorted(MAPS_DIR.rglob("*.json")):
        try:
            data = load_json(path)
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(data, list) or not data:
            continue
        if not any(str(e.get("Type", "")) == PORTAL_CLASS for e in data):
            continue
        rel = path.relative_to(MAPS_DIR).with_suffix("").as_posix()
        components: dict[tuple[str, str], dict] = {}
        for export in data:
            owner, name = _split_owner(
                str((export.get("Outer") or {}).get("ObjectName", ""))
            )
            name = name or str(export.get("Name", ""))
            if owner:
                components[(owner, name)] = export
        for actor in data:
            if str(actor.get("Type", "")) != PORTAL_CLASS:
                continue
            actor_name = str(actor.get("Name", ""))
            label = str(actor.get("ActorLabel", "") or "")
            actor_props = actor.get("Properties") or {}
            root_ref = actor_props.get("RootComponent") or {}
            owner, root_name = _split_owner(str(root_ref.get("ObjectName", "")))
            if owner and owner != actor_name:
                raise Fail(
                    f"{rel}:{actor_name}: root reference owner {owner!r} disagrees"
                )
            root = components.get((actor_name, root_name))
            if root is None:
                raise Fail(f"{rel}:{actor_name}: root component {root_name!r} missing")
            props = root.get("Properties") or {}
            loc = props.get("RelativeLocation")
            rot = props.get("RelativeRotation")
            scale = props.get("RelativeScale3D")
            authored = isinstance(loc, dict) and isinstance(scale, dict)
            trs = pt.ue_mat4_to_godot_trs(pt.ue_trs_to_mat4(loc, rot, scale))
            portals.append(
                {
                    "id": f"{rel}:{actor_name}",
                    "level_dir": rel.split("/")[0],
                    "sublevel": rel,
                    "sublevel_stem": rel.split("/")[-1],
                    "actor": actor_name,
                    "label": label,
                    "pos": trs["pos"],
                    "basis": trs["basis"],
                    "scale": trs["scale"],
                    "transform_authored": authored,
                }
            )
    return portals


def cross_check_runtime(portals: list[dict]) -> dict:
    if not DEVICES_RUNTIME.is_file():
        return {"available": False, "reason": "devices_runtime.json not generated"}
    runtime = load_json(DEVICES_RUNTIME)
    index: dict[tuple[str, str], dict] = {}
    total = 0
    for map_id, payload in (runtime.get("maps") or {}).items():
        for device in payload.get("devices") or []:
            if device.get("family") != "acoustic_portal":
                continue
            total += 1
            index[(str(device.get("sublevel")), str(device.get("actor")))] = {
                "map": map_id,
                "runtime_id": device.get("id"),
                "pos": device.get("pos"),
                "authored_scale": (device.get("params") or {}).get("authored_scale"),
            }
    matched = 0
    mismatched: list[str] = []
    used: set[tuple[str, str]] = set()
    for portal in portals:
        key = (portal["sublevel_stem"], portal["actor"])
        hit = index.get(key)
        if not hit:
            continue
        used.add(key)
        matched += 1
        portal["runtime_id"] = hit["runtime_id"]
        portal["runtime_map"] = hit["map"]
        if hit.get("pos") and any(
            abs(a - b) > 1e-3 for a, b in zip(portal["pos"], hit["pos"])
        ):
            mismatched.append(f"{portal['id']}: pos {portal['pos']} vs {hit['pos']}")
        if hit.get("authored_scale") and any(
            abs(a - b) > 1e-3 for a, b in zip(portal["scale"], hit["authored_scale"])
        ):
            mismatched.append(
                f"{portal['id']}: scale {portal['scale']} vs {hit['authored_scale']}"
            )
    return {
        "available": True,
        "runtime_portals": total,
        "matched": matched,
        "unmatched_source": len(portals) - matched,
        "runtime_unmatched": sorted(f"{key[0]}:{key[1]}" for key in set(index) - used),
        "mismatched": mismatched,
        "notes": (
            "devices_runtime.json only carries the portals in the maps it loads "
            "(the other placements live in sublevels it never expands, and its "
            "level-instance expansion can add placements the raw dumps do not "
            "carry twice); the authored positions/scales must agree where both "
            "files cover a portal."
        ),
    }


def main() -> int:
    try:
        hearing_asset, hearing_rows = rows_of(HEARING_DT)
        if len(hearing_rows) != EXPECTED_HEARING_ROWS:
            raise Fail(
                f"DT_HearingStimProperties has {len(hearing_rows)} rows, "
                f"expected {EXPECTED_HEARING_ROWS}"
            )
        stimuli, anomalies = hearing_stimuli(hearing_rows)
        loudness = loudness_modifiers(one_asset(LOUDNESS_DA))

        hearing_config = perception_config(
            PERCEPTION_DIR / "DA_PerceptionSharedConfig_Hearing.json"
        )
        vision_config = perception_config(
            PERCEPTION_DIR / "DA_PerceptionSharedConfig_Vision_Guard.json"
        )
        carry_multipliers = {
            row["tag"]: row["range_multiplier"]
            for row in hearing_config["range_modifiers"]
            if row["tag"].startswith("Weather.SoundCarry.")
        }
        if not carry_multipliers:
            raise Fail("hearing shared config has no Weather.SoundCarry modifiers")

        _weather_asset, weather_source = rows_of(WEATHER_DT)
        if len(weather_source) != EXPECTED_WEATHER_ROWS:
            raise Fail(
                f"DT_WeatherTypes has {len(weather_source)} rows, "
                f"expected {EXPECTED_WEATHER_ROWS}"
            )
        weather, weather_problems = weather_rows(weather_source, carry_multipliers)

        _vision_asset, vision_rows = rows_of(VISION_DT)
        if len(vision_rows) != EXPECTED_VISION_ROWS:
            raise Fail(
                f"DT_StimProperties has {len(vision_rows)} rows, "
                f"expected {EXPECTED_VISION_ROWS}"
            )
        vision_stimuli = {}
        for row_name, row in vision_rows.items():
            severity = enum_tail(row.get("Severity"), f"vision row {row_name}")
            if severity not in SEVERITIES:
                raise Fail(f"vision row {row_name}: unknown severity {severity!r}")
            vision_stimuli[row_name] = {"severity": severity}

        box = load_portal_box()
        portals = portal_actors()
        if len(portals) != EXPECTED_PORTALS:
            raise Fail(
                f"found {len(portals)} {PORTAL_CLASS} actors, "
                f"expected {EXPECTED_PORTALS}"
            )
        ids = [portal["id"] for portal in portals]
        if len(set(ids)) != len(ids):
            raise Fail("duplicate acoustic-portal ids")
        portal_xcheck = cross_check_runtime(portals)

        sublevels = Counter(portal["sublevel"] for portal in portals)
        by_severity = Counter(row["severity"] for row in stimuli)
        by_propagation = Counter(row["propagation"] for row in stimuli)
        by_behaviour = Counter(
            behaviour for row in stimuli for behaviour in row["behaviors"]
        )
        by_bitmask = Counter(row["query_bitmask"] for row in stimuli)
        restricted = [
            row["row"]
            for row in stimuli
            if not (
                row["heard_by"]["hostiles"]
                and row["heard_by"]["neutrals"]
                and row["heard_by"]["friendlies"]
            )
        ]

        hearing_payload = {
            "schema": SCHEMA_HEARING,
            "game_version": GAME_VERSION,
            "source": {
                "stimuli": "extracted/json/AI/Data/DT_HearingStimProperties.json",
                "stimuli_row_struct": (
                    (hearing_asset.get("Properties") or {})
                    .get("RowStruct", {})
                    .get("ObjectName", "")
                ),
                "loudness": "extracted/json/AI/Data/DA_LoudnessModifiers.json",
                "perception": "extracted/json/AI/Perception/DA_PerceptionSharedConfig_Hearing.json",
                "weather": "extracted/json/Gameplay/Weather/DT_WeatherTypes.json",
                "portal_blueprint": "extracted/json/Audio/Audio_BPs/BP_TATAcousticPortal.json",
                "portal_levels": "extracted/json/Maps/**/*.json",
                "devices": "game/data/generated/gameplay/devices_runtime.json",
            },
            "units": {
                "authored": (
                    "UE centimetres for MaxRange / InnerInvestigationRange / "
                    "OuterInvestigationRange (original property names kept)"
                ),
                "metric": "metres, rounded to 4 dp, under each row's metric block",
                "portal": "Godot metres + column-major basis + authored box scale",
            },
            "stimuli": stimuli,
            "loudness_modifiers": loudness,
            "weather_sound_carry": {
                tag: {
                    "label": row["label"],
                    "indoors": row["sound_carry"]["indoors"],
                    "outdoors": row["sound_carry"]["outdoors"],
                }
                for tag, row in weather.items()
            },
            "perception_modifiers": {
                "hearing": hearing_config["range_modifiers"],
                "semantics": hearing_config["range_modifier_semantics"],
            },
            "acoustic_portals": {
                "class": PORTAL_CLASS,
                "asset": "/Game/Audio/Audio_BPs/BP_TATAcousticPortal",
                "box_extent_cm": box["box_extent_cm"],
                "hidden_in_game": box["hidden_in_game"],
                "count": len(portals),
                "by_sublevel": dict(sorted(sublevels.items())),
                "cross_check": portal_xcheck,
                "portals": portals,
            },
            "stats": {
                "stimuli": len(stimuli),
                "by_severity": dict(sorted(by_severity.items())),
                "by_propagation": dict(sorted(by_propagation.items())),
                "by_behaviour": dict(sorted(by_behaviour.items())),
                "by_query_bitmask": {str(k): v for k, v in sorted(by_bitmask.items())},
                "restricted_heard_by": restricted,
                "max_range_cm": {
                    "min": min(row["max_range_cm"] for row in stimuli),
                    "max": max(row["max_range_cm"] for row in stimuli),
                },
                "loudness_surfaces": loudness["surfaces"],
                "weather_types": len(weather),
                "portals": len(portals),
                "portal_sublevels": len(sublevels),
                "anomalies": anomalies,
                "weather_join_problems": weather_problems,
            },
        }

        perception_payload = {
            "schema": SCHEMA_PERCEPTION,
            "game_version": GAME_VERSION,
            "source": {
                "hearing_config": "extracted/json/AI/Perception/DA_PerceptionSharedConfig_Hearing.json",
                "vision_config": "extracted/json/AI/Perception/DA_PerceptionSharedConfig_Vision_Guard.json",
                "weather": "extracted/json/Gameplay/Weather/DT_WeatherTypes.json",
                "vision_stimuli": "extracted/json/AI/Data/DT_StimProperties.json",
            },
            "senses": {
                "hearing": hearing_config,
                "vision_guard": vision_config,
            },
            "weather": {
                "rows": len(weather),
                "by_type": weather,
                "notes": (
                    "Visibility tags describe sight range while a weather type is "
                    "active; sound-carry tags describe hearing propagation. The "
                    "shared vision config currently carries no non-neutral "
                    "Weather.Visibility modifier, so the vision tags are labels "
                    "until a config maps them."
                ),
            },
            "vision_stimuli": {
                "rows": len(vision_stimuli),
                "by_row": vision_stimuli,
                "notes": (
                    "DT_StimProperties rows only carry a severity in the cooked "
                    "dump; the vision sense ranges live on the AI perception "
                    "components, not this table."
                ),
            },
            "cross_reference": {
                "hearing": "game/data/generated/gameplay/hearing.json",
                "guard_runtime": "game/data/generated/gameplay/guard_ai.json",
            },
            "stats": {
                "senses": 2,
                "hearing_modifiers": len(hearing_config["range_modifiers"]),
                "vision_modifiers": len(vision_config["range_modifiers"]),
                "weather_types": len(weather),
                "vision_stimuli": len(vision_stimuli),
            },
        }

        OUT_DIR.mkdir(parents=True, exist_ok=True)
        HEARING_OUT.write_text(
            json.dumps(hearing_payload, indent=2) + "\n", encoding="utf-8"
        )
        PERCEPTION_OUT.write_text(
            json.dumps(perception_payload, indent=2) + "\n", encoding="utf-8"
        )
    except Fail as exc:
        print(f"parse_hearing: FAIL: {exc}", file=sys.stderr)
        return 1

    stats = hearing_payload["stats"]
    print(
        "Parsed {} hearing stimuli, {} loudness surfaces, {} weather types, "
        "{} acoustic portals -> {}".format(
            stats["stimuli"],
            stats["loudness_surfaces"],
            stats["weather_types"],
            stats["portals"],
            HEARING_OUT.relative_to(ROOT),
        )
    )
    print(
        "  severity: "
        + ", ".join(f"{k}={v}" for k, v in stats["by_severity"].items())
        + " | behaviours: "
        + ", ".join(f"{k.split('.')[-1]}={v}" for k, v in stats["by_behaviour"].items())
    )
    print(
        "  query bitmasks: "
        + ", ".join(f"{k}={v}" for k, v in stats["by_query_bitmask"].items())
    )
    print(
        "  portals per sublevel: "
        + ", ".join(
            f"{k.split('/')[-1]}={v}"
            for k, v in hearing_payload["acoustic_portals"]["by_sublevel"].items()
        )
    )
    print(f"  runtime portal cross-check: {portal_xcheck}")
    print(
        "Wrote {} ({}/{} modifiers)".format(
            PERCEPTION_OUT.relative_to(ROOT),
            perception_payload["stats"]["hearing_modifiers"],
            perception_payload["stats"]["vision_modifiers"],
        )
    )
    if anomalies:
        print(f"  authored anomalies: {anomalies}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
