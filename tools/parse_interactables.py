#!/usr/bin/env python3
"""
Parse real UE5 TAT interactable/loot/lockpick data into Godot-friendly JSON.

Reads the extracted UE5 dumps (plus the already-normalized CT_LockpickDamage
curve table) and writes one normalized file to
`game/data/generated/gameplay/interactables.json` with:
  - loot tables by tier (minor / major / quest): names, values, quest flags,
    steal times, tags, counts and min/max summaries (over rows with Value > 1;
    Value 0 rows are currency placeholders and Value 1 is a renown test item),
  - lockpick data: per-lock-level jam damage from CT_LockpickDamage
    (DamageByLockLevel row: 5/10/20/40), GA_Lockpick ability defaults
    (jam delay, early-unlock threshold, cancel distance, required section tag)
    and DA_LockpickMinigameVariations track params per difficulty level,
  - escape point: open duration (240 s) + reusable flag,
  - doors: MaxLockLevel (4) + shake timeline; open/close durations are NOT
    present in the extracted data and are reported as null (Godot side keeps
    its existing tween).

No numbers are invented: fields absent from the source JSON become null.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX = ROOT / "extracted" / "json"
GEN_TABLES = ROOT / "game" / "data" / "generated" / "tables"
OUT = ROOT / "game" / "data" / "generated" / "gameplay" / "interactables.json"

SRC_MINOR = "extracted/json/Gameplay/Loot/Data/DT_LootInfo_Minor.json"
SRC_MAJOR = "extracted/json/Gameplay/Loot/Data/DT_LootInfo_Major.json"
SRC_QUEST = "extracted/json/Gameplay/Loot/Data/DT_LootInfo_Quest.json"
SRC_LOCK_DMG = "game/data/generated/tables/Gameplay/Tuning/CT_LockpickDamage.json"
SRC_LOCK_DMG_RAW = "extracted/json/Gameplay/Tuning/CT_LockpickDamage.json"
SRC_VARIATIONS = (
    "extracted/json/Gameplay/Interactables/Locks/DA_LockpickMinigameVariations.json"
)
SRC_GA_LOCKPICK = "extracted/json/Gameplay/Interactables/Locks/GA_Lockpick.json"
SRC_GE_LOCKPICKING = "extracted/json/Gameplay/Interactables/Locks/GE_Lockpicking.json"
SRC_ESCAPE = "extracted/json/Gameplay/Interactables/EscapePoints/BP_EscapePoint.json"
SRC_DOOR = "extracted/json/Gameplay/Interactables/Doors/BP_SwingingDoor.json"


def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def unwrap_rows(doc, table_name: str) -> dict:
    """Extracted DataTables are JSON arrays whose element holds .Rows."""
    if isinstance(doc, list):
        for el in doc:
            if isinstance(el, dict) and el.get("Name") == table_name and "Rows" in el:
                return el["Rows"]
        for el in doc:
            if isinstance(el, dict) and "Rows" in el:
                return el["Rows"]
        return {}
    if isinstance(doc, dict):
        if "Rows" in doc and isinstance(doc["Rows"], dict):
            return doc["Rows"]
        if "rows" in doc and isinstance(doc["rows"], dict):
            return doc["rows"]
    return {}


def display_name(row: dict) -> str:
    dn = row.get("DisplayName") or {}
    for key in ("SourceString", "LocalizedString", "CultureInvariantString"):
        val = dn.get(key)
        if val:
            return str(val)
    return ""


def loot_tag(row: dict) -> str:
    li = row.get("LootIdentifier") or {}
    tag = li.get("LootTag") or {}
    return str(tag.get("TagName", ""))


def norm_loot_entry(key: str, row: dict) -> dict:
    return {
        "key": key,
        "name": display_name(row),
        "value": row.get("Value"),
        "is_quest_related": bool(row.get("IsQuestRelated", False)),
        "steal_time_s": row.get("TimeTakenToSteal"),
        "loot_tag": loot_tag(row),
        "loot_type": str(row.get("lootType", "")),
    }


def parse_loot_table(path: Path, table_name: str) -> tuple[list, dict]:
    rows = unwrap_rows(load_json(path), table_name)
    entries = [norm_loot_entry(k, v) for k, v in rows.items() if isinstance(v, dict)]
    entries.sort(key=lambda e: e["key"])
    return entries, rows


# Rows never spawned: Value 0 rows are currency placeholders. Value 1 is the
# renown test item JEWELKNIFERENOWN ('jewellknife') — excluded by KEY, not by
# value, so a future real Value-1 loot item still spawns (P2-3). Any other
# Value-1 row reaching the pool is warned about in main().
KNOWN_TEST_KEYS = {"JEWELKNIFERENOWN"}


def spawn_pool(entries: list) -> list:
    """Rows actually worth spawning: skips currency placeholders (Value 0)
    and known test items by key (Value 1 renown test item)."""
    pool = []
    for e in entries:
        v = e["value"]
        if not isinstance(v, (int, float)):
            continue
        if v <= 0:
            continue
        if v == 1 and e["key"] in KNOWN_TEST_KEYS:
            continue
        pool.append(e)
    return pool


def minmax(pool: list) -> tuple:
    vals = [e["value"] for e in pool]
    if not vals:
        return None, None
    return min(vals), max(vals)


def parse_lockpick_damage() -> tuple[dict, str]:
    """Prefer the normalized generated curve table; fall back to extracted."""
    for src in (
        GEN_TABLES / "Gameplay" / "Tuning" / "CT_LockpickDamage.json",
        EX / "Gameplay" / "Tuning" / "CT_LockpickDamage.json",
    ):
        if src.exists():
            rows = unwrap_rows(load_json(src), "CT_LockpickDamage")
            row = rows.get("DamageByLockLevel") or {}
            keys = row.get("Keys") or []
            dmg = {
                str(int(float(k["Time"]))): k["Value"]
                for k in keys
                if "Time" in k and "Value" in k
            }
            if dmg:
                rel = str(src.relative_to(ROOT))
                return dmg, rel
    return {}, ""


def find_default_object(doc, type_name: str, name_prefix: str) -> dict:
    items = doc if isinstance(doc, list) else [doc]
    for el in items:
        if not isinstance(el, dict):
            continue
        if el.get("Type") == type_name and str(el.get("Name", "")).startswith(
            name_prefix
        ):
            return el.get("Properties", {})
    return {}


def parse_ga_lockpick() -> dict:
    doc = load_json(EX / "Gameplay" / "Interactables" / "Locks" / "GA_Lockpick.json")
    props = find_default_object(doc, "GA_Lockpick_C", "Default__")
    jam = ((props.get("JamDamage") or {}).get("DamageAmount")) or {}
    curve = jam.get("Curve") or {}
    table = curve.get("CurveTable") or {}
    return {
        "distance_before_cancel": props.get("DistanceBeforeCancel"),
        "early_unlock_threshold_s": props.get("EarlyUnlockThresholdSeconds"),
        "jam_damage_delay_s": props.get("JamDamageDelay"),
        "jam_damage_curve_table": str(table.get("ObjectName", ""))
        .replace("CurveTable'", "")
        .rstrip("'"),
        "jam_damage_row": str((curve.get("RowName") or "")),
        "jam_damage_type": str(
            ((props.get("JamDamage") or {}).get("DamageType") or {}).get("TagName", "")
        ),
        "required_section_tag": str(
            ((props.get("RequiredSectionTag") or {}).get("TagName", ""))
        ),
    }


def parse_variations() -> dict:
    doc = load_json(
        EX
        / "Gameplay"
        / "Interactables"
        / "Locks"
        / "DA_LockpickMinigameVariations.json"
    )
    items = doc if isinstance(doc, list) else [doc]
    props: dict = {}
    for el in items:
        if (
            isinstance(el, dict)
            and isinstance(el.get("Properties"), dict)
            and "Variations" in el["Properties"]
        ):
            props = el["Properties"]
            break
    by_diff: dict[str, list] = {}
    for var in props.get("Variations", []):
        diff = str(var.get("DifficultyLevel"))
        tracks = []
        for t in var.get("Tracks", []):
            sections = []
            for s in t.get("DefinedSections", []):
                sections.append(
                    {
                        "section_type": str(
                            (s.get("SectionType") or {}).get("TagName", "")
                        ),
                        "start_s": s.get("StartTimeSeconds"),
                        "end_s": s.get("EndTimeSeconds"),
                    }
                )
            var_dur = t.get("durationSeconds")
            var_arc = t.get("TrackArcAngle")
            tracks.append(
                {
                    "duration_s": var_dur,
                    # Authored value plus the harness alias, emitted at source so
                    # a later normalizer cannot drop it.
                    "arc_angle_deg": var_arc,
                    "arc_deg": var_arc,
                    "default_section_type": str(
                        (t.get("DefaultSectionType") or {}).get("TagName", "")
                    ),
                    "defined_sections": sections,
                }
            )
        by_diff.setdefault(diff, []).append({"tracks": tracks})
    return by_diff


def parse_escape() -> dict:
    doc = load_json(
        EX / "Gameplay" / "Interactables" / "EscapePoints" / "BP_EscapePoint.json"
    )
    props = find_default_object(doc, "BP_EscapePoint_C", "Default__")
    return {
        "escape_open_duration_s": props.get("_escapeOpenDuration"),
        "can_be_used_multiple_times": props.get("_canBeUsedMultipleTimes"),
        "door_travel_distance": props.get("DoorTravelDistance"),
    }


def parse_door() -> dict:
    doc = load_json(
        EX / "Gameplay" / "Interactables" / "Doors" / "BP_SwingingDoor.json"
    )
    props = find_default_object(doc, "BP_SwingingDoor_C", "Default__")
    lock_cfg = props.get("_lockConfig") or {}
    shake_s = None
    items = doc if isinstance(doc, list) else [doc]
    for el in items:
        if isinstance(el, dict) and el.get("Type") == "TimelineTemplate":
            tl = (el.get("Properties") or {}).get("TimelineLength")
            if tl is not None:
                shake_s = tl
    return {
        "max_lock_level": lock_cfg.get("MaxLockLevel"),
        "shake_timeline_s": shake_s,
        # The extracted door dump exposes no open/close/lock durations.
        "open_duration_s": None,
        "close_duration_s": None,
    }


def main() -> None:
    minor, _ = parse_loot_table(
        EX / "Gameplay" / "Loot" / "Data" / "DT_LootInfo_Minor.json",
        "DT_LootInfo_Minor",
    )
    major, _ = parse_loot_table(
        EX / "Gameplay" / "Loot" / "Data" / "DT_LootInfo_Major.json",
        "DT_LootInfo_Major",
    )
    quest, _ = parse_loot_table(
        EX / "Gameplay" / "Loot" / "Data" / "DT_LootInfo_Quest.json",
        "DT_LootInfo_Quest",
    )

    minor_pool = spawn_pool(minor)
    major_pool = spawn_pool(major)
    quest_pool = spawn_pool(quest)
    # P2-3: a real Value-1 loot item must never vanish silently. Anything at
    # Value 1 that is not a known test key now enters the pool — warn loudly.
    for tier_name, tier_entries in (
        ("minor", minor),
        ("major", major),
        ("quest", quest),
    ):
        for e in tier_entries:
            if e["value"] == 1 and e["key"] not in KNOWN_TEST_KEYS:
                print(
                    f"WARN: {tier_name} {e['key']} has Value 1 and is NOT a known test item; kept in spawn pool"
                )
    minor_min, minor_max = minmax(minor_pool)
    major_min, major_max = minmax(major_pool)
    flagship_vals = [e["value"] for e in quest_pool if e["is_quest_related"]]
    flagship_value = max(flagship_vals) if flagship_vals else None

    jam_damage, jam_src = parse_lockpick_damage()
    ga = parse_ga_lockpick()
    variations = parse_variations()
    escape = parse_escape()
    door = parse_door()

    data = {
        "sources": {
            "loot_minor": SRC_MINOR,
            "loot_major": SRC_MAJOR,
            "loot_quest": SRC_QUEST,
            "lockpick_damage": jam_src or SRC_LOCK_DMG,
            "lockpick_variations": SRC_VARIATIONS,
            "lockpick_ability": SRC_GA_LOCKPICK,
            "lockpick_effect": SRC_GE_LOCKPICKING,
            "escape_point": SRC_ESCAPE,
            "door": SRC_DOOR,
        },
        "loot": {
            "minor": {
                "source": SRC_MINOR,
                "count": len(minor),
                "spawn_pool_count": len(minor_pool),
                "min_value": minor_min,
                "max_value": minor_max,
                "entries": minor,
            },
            "major": {
                "source": SRC_MAJOR,
                "count": len(major),
                "spawn_pool_count": len(major_pool),
                "min_value": major_min,
                "max_value": major_max,
                "entries": major,
            },
            "quest": {
                "source": SRC_QUEST,
                "count": len(quest),
                "spawn_pool_count": len(quest_pool),
                "flagship_value": flagship_value,
                "entries": quest,
            },
        },
        "lockpick": {
            "sources": [
                jam_src or SRC_LOCK_DMG,
                SRC_VARIATIONS,
                SRC_GA_LOCKPICK,
                SRC_GE_LOCKPICKING,
            ],
            "curve_table": "CT_LockpickDamage",
            "damage_row": "DamageByLockLevel",
            "jam_damage_by_lock_level": jam_damage,
            "jam_damage_delay_s": ga["jam_damage_delay_s"],
            "early_unlock_threshold_s": ga["early_unlock_threshold_s"],
            "distance_before_cancel": ga["distance_before_cancel"],
            "required_section_tag": ga["required_section_tag"],
            "jam_damage_type": ga["jam_damage_type"],
            "variations_by_difficulty": variations,
            "variation_difficulty_levels": sorted(variations.keys(), key=int),
            "pick_duration_s": None,
        },
        "escape": {
            "source": SRC_ESCAPE,
            "open_duration_s": escape["escape_open_duration_s"],
            "can_be_used_multiple_times": escape["can_be_used_multiple_times"],
            "door_travel_distance": escape["door_travel_distance"],
        },
        "doors": {
            "source": SRC_DOOR,
            "max_lock_level": door["max_lock_level"],
            "shake_timeline_s": door["shake_timeline_s"],
            "open_duration_s": door["open_duration_s"],
            "close_duration_s": door["close_duration_s"],
        },
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"wrote {OUT}")
    print(
        f"loot minor n={len(minor)} pool={len(minor_pool)} min={minor_min} max={minor_max}"
    )
    print(
        f"loot major n={len(major)} pool={len(major_pool)} min={major_min} max={major_max}"
    )
    print(f"loot quest n={len(quest)} pool={len(quest_pool)} flagship={flagship_value}")
    print(f"jam damage by level: {jam_damage}")
    print(f"variation difficulties: {sorted(variations.keys(), key=int)}")
    print(
        f"escape open={escape['escape_open_duration_s']} reusable={escape['can_be_used_multiple_times']}"
    )
    print(f"door max_lock={door['max_lock_level']} shake={door['shake_timeline_s']}")


if __name__ == "__main__":
    main()
