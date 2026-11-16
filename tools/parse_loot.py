#!/usr/bin/env python3
"""
Parse the minor/major loot spawn buckets plus their referenced loot-actor
Blueprints into game/data/generated/gameplay/loot_actors.json.

Buckets (extracted/json/Missions/Spawners/Buckets/):
  DA_SpawnBucket_MinorLoot -> 20 weighted entries (7 unique classes)
  DA_SpawnBucket_MajorLoot -> 60 weighted entries (13 unique classes)

For every referenced actor Blueprint the CDO LootRowHandle
(DataTable DT_LootInfo_Minor|Major|Quest + RowName) and the SCS mesh are
resolved:
  - mesh choice: the StaticMeshComponent tagged `Interact` when present,
    else the primary mesh (the component named StaticMesh_GEN_VARIABLE,
    else the first StaticMeshComponent). The glass display-cover dressing
    (Glass_GEN_VARIABLE) is never the loot itself and loses to the primary
    rule. InstancedStaticMeshComponent `Interact` proxies are recorded for
    transparency but are not the visible loot.
  - names/values come from game/data/generated/gameplay/interactables.json
    (A7), keyed by RowName, so the Godot runtime reads the same numbers.

Quest side: every BP_LootActor_Quest_* / BP_QuestLootActor_* Blueprint with a
LootRowHandle is recorded, and loot_tag -> class is mapped wherever the
RowName matches an interactables.json row. Shipped contracts whose tag has
no dedicated actor fall back to the generic quest actor (documented).

Resolved meshes are existence-checked against
game/assets/ue/Content/*.glb. Bucket actors MUST all resolve (assert);
quest actors with a missing mesh keep mesh_res "" and are served the
box fallback in loot_item.gd (labelled, never invented).
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX = ROOT / "extracted" / "json"
OUT = ROOT / "game" / "data" / "generated" / "gameplay" / "loot_actors.json"
INTERACTABLES = ROOT / "game" / "data" / "generated" / "gameplay" / "interactables.json"

BUCKET_DIR = EX / "Missions" / "Spawners" / "Buckets"
BUCKETS = {
    "minor": "DA_SpawnBucket_MinorLoot",
    "major": "DA_SpawnBucket_MajorLoot",
}

TABLE_TO_TIER = {
    "DT_LootInfo_Minor": "minor",
    "DT_LootInfo_Major": "major",
    "DT_LootInfo_Quest": "quest",
}


def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def find_bp_file(asset_path_name: str) -> Path | None:
    """'/Game/Gameplay/.../BP_Foo.BP_Foo_C' -> extracted/json/.../BP_Foo.json."""
    pkg = asset_path_name.split(".")[0]
    if pkg.startswith("/Game/"):
        pkg = pkg[len("/Game/") :]
    stem = pkg.split("/")[-1]
    matches = sorted(EX.rglob(stem + ".json"))
    return matches[0] if matches else None


def short_class(asset_path_name: str) -> str:
    return asset_path_name.split(".")[-1]


def ue_pkg_to_res(asset_object_path: str) -> tuple[str, bool]:
    """'/Game/Art/.../SM_Foo.N' -> ('res://assets/ue/Content/Art/.../SM_Foo.glb', exists)."""
    inner = (
        asset_object_path.split("'")[1]
        if "'" in asset_object_path
        else asset_object_path
    )
    pkg = inner.split(".")[0]
    if pkg.startswith("/Game/"):
        pkg = pkg[len("/Game/") :]
    res = f"res://assets/ue/Content/{pkg}.glb"
    disk = ROOT / "game" / res[len("res://") :]
    return res, disk.is_file()


def cdo_row_handle(bp_data) -> tuple[str, str]:
    """(table_object_name, row_name) from the ClassDefaultObject LootRowHandle."""
    for entry in bp_data:
        if not isinstance(entry, dict):
            continue
        props = entry.get("Properties")
        if not isinstance(props, dict):
            continue
        lr = props.get("LootRowHandle")
        if isinstance(lr, dict):
            dt = lr.get("DataTable") or {}
            table = str(dt.get("ObjectName", ""))
            if table.startswith("DataTable'"):
                table = table[len("DataTable'") :].rstrip("'")
            return table, str(lr.get("RowName", ""))
    return "", ""


def choose_mesh(bp_data) -> tuple[dict | None, str, list[str]]:
    """Pick the visible loot mesh. Returns (chosen_props, reason, all_objpaths).

    Rule: StaticMeshComponent tagged `Interact` wins; else the component
    named StaticMesh_GEN_VARIABLE (the loot itself, not dressing like
    Glass_GEN_VARIABLE); else the first StaticMeshComponent.
    """
    statics: list[dict] = []
    for entry in bp_data:
        if not isinstance(entry, dict):
            continue
        if entry.get("Type") != "StaticMeshComponent":
            continue
        props = entry.get("Properties")
        if not isinstance(props, dict):
            continue
        sm = props.get("StaticMesh")
        if isinstance(sm, dict) and isinstance(sm.get("ObjectPath"), str):
            statics.append(entry)
    if not statics:
        return None, "no_static_mesh", []
    all_paths = [str(e["Properties"]["StaticMesh"]["ObjectPath"]) for e in statics]
    tagged = [
        e for e in statics if "Interact" in (e["Properties"].get("ComponentTags") or [])
    ]
    if tagged:
        return tagged[0]["Properties"], "interact_tagged", all_paths
    primary = [e for e in statics if e.get("Name") == "StaticMesh_GEN_VARIABLE"]
    if primary:
        return primary[0]["Properties"], "primary", all_paths
    return statics[0]["Properties"], "first", all_paths


def instanced_interact_proxy(bp_data) -> str:
    """ObjectPath of the InstancedStaticMeshComponent tagged Interact, if any."""
    for entry in bp_data:
        if not isinstance(entry, dict):
            continue
        if entry.get("Type") != "InstancedStaticMeshComponent":
            continue
        props = entry.get("Properties")
        if not isinstance(props, dict):
            continue
        if "Interact" not in (props.get("ComponentTags") or []):
            continue
        sm = props.get("StaticMesh")
        if isinstance(sm, dict) and isinstance(sm.get("ObjectPath"), str):
            return str(sm["ObjectPath"])
    return ""


def main() -> None:
    inter = load_json(INTERACTABLES)
    by_tier_row: dict[str, dict[str, dict]] = {}
    for tier in ("minor", "major", "quest"):
        by_tier_row[tier] = {}
        for e in inter["loot"][tier]["entries"]:
            by_tier_row[tier][str(e["key"])] = e

    buckets_out: dict[str, dict] = {}
    actors: dict[str, dict] = {}
    for tier, bucket_name in BUCKETS.items():
        bucket_file = BUCKET_DIR / (bucket_name + ".json")
        if not bucket_file.is_file():
            raise SystemExit(f"missing bucket file: {bucket_file}")
        data = load_json(bucket_file)
        classes: list[str] = []
        for asset in data:
            for e in asset.get("Properties", {}).get("Entries", []) or []:
                apn = str((e.get("ClassToSpawn") or {}).get("AssetPathName", ""))
                if apn:
                    classes.append(short_class(apn))
        buckets_out[tier] = {
            "source": str(bucket_file.relative_to(ROOT)),
            "classes": classes,
        }
        for cls in sorted(set(classes)):
            apn = next(
                c
                for c in [
                    str((e.get("ClassToSpawn") or {}).get("AssetPathName", ""))
                    for asset in data
                    for e in asset.get("Properties", {}).get("Entries", []) or []
                ]
                if short_class(c) == cls
            )
            bp_file = find_bp_file(apn)
            if bp_file is None:
                raise SystemExit(f"no Blueprint JSON for bucket class {cls}")
            bp = load_json(bp_file)
            table, row = cdo_row_handle(bp)
            if not row:
                raise SystemExit(f"{cls}: no LootRowHandle")
            tier_of = TABLE_TO_TIER.get(table, "")
            row_entry = by_tier_row.get(tier_of, {}).get(row)
            if row_entry is None:
                raise SystemExit(f"{cls}: row {row!r} not in interactables {tier_of}")
            chosen, reason, all_paths = choose_mesh(bp)
            if chosen is None:
                raise SystemExit(f"{cls}: no StaticMeshComponent")
            obj_path = str(chosen["StaticMesh"]["ObjectPath"])
            mesh_stem = obj_path.split("/")[-1]
            if "'" in mesh_stem:
                mesh_stem = mesh_stem.split("'")[1]
            mesh_stem = mesh_stem.split(".")[0]
            res, exists = ue_pkg_to_res(obj_path)
            if not exists:
                raise SystemExit(f"{cls}: mesh missing on disk: {obj_path}")
            proxy = instanced_interact_proxy(bp)
            actors[cls] = {
                "mesh_res": res,
                "mesh_exists": True,
                "mesh_ue_path": obj_path,
                "mesh_name": mesh_stem,
                "mesh_choice": reason,
                "interact_proxy_ue_path": proxy,
                "table": table,
                "row": row,
                "name": row_entry["name"],
                "value": row_entry["value"],
                "tier": tier_of,
                "bp_source": str(bp_file.relative_to(ROOT)),
                "bucket_source": str(bucket_file.relative_to(ROOT)),
            }

    # Quest actors: every Quest-named loot Blueprint carrying a LootRowHandle.
    quest_files = sorted(EX.rglob("BP_LootActor_Quest*.json")) + sorted(
        EX.rglob("BP_QuestLootActor_*.json")
    )
    quest_actors: dict[str, dict] = {}
    skipped: list[str] = []
    for bp_file in quest_files:
        stem = bp_file.stem
        cls = stem + "_C"
        if cls in quest_actors:
            continue
        bp = load_json(bp_file)
        table, row = cdo_row_handle(bp)
        if not row:
            skipped.append(f"{stem} (base class, no LootRowHandle)")
            continue
        tier_of = TABLE_TO_TIER.get(table, "")
        row_entry = by_tier_row.get(tier_of, {}).get(row, {})
        chosen, reason, _all = choose_mesh(bp)
        mesh_ue = str(chosen["StaticMesh"]["ObjectPath"]) if chosen is not None else ""
        if mesh_ue:
            res, exists = ue_pkg_to_res(mesh_ue)
        else:
            res, exists = "", False
        quest_actors[cls] = {
            "row": row,
            "table": table,
            "tier": tier_of,
            "mesh_res": res if exists else "",
            "mesh_exists": exists,
            "mesh_ue_path": mesh_ue,
            "mesh_choice": reason,
            "name": row_entry.get("name", ""),
            "value": row_entry.get("value", 0),
            "bp_source": str(bp_file.relative_to(ROOT)),
        }

    # loot_tag -> class wherever the RowName matches an interactables row.
    tag_to_row: dict[str, tuple[str, str]] = {}
    for tier in ("minor", "major", "quest"):
        for key, e in by_tier_row[tier].items():
            tag_to_row[str(e["loot_tag"])] = (tier, key)
    row_to_class: dict[str, str] = {}
    for cls, a in quest_actors.items():
        if a["row"]:
            row_to_class.setdefault(str(a["row"]), cls)
    tag_to_actor: dict[str, str] = {}
    for tag, (_tier, key) in sorted(tag_to_row.items()):
        if key in row_to_class:
            tag_to_actor[tag] = row_to_class[key]

    # Contract tags with no dedicated actor -> generic fallback (labelled).
    contracts = load_json(
        ROOT / "game" / "data" / "generated" / "gameplay" / "contracts.json"
    )
    contract_list = contracts.get(
        "contracts", contracts if isinstance(contracts, list) else []
    )
    unmapped_contract_tags = sorted(
        {
            str(c.get("loot_tag", ""))
            for c in contract_list
            if isinstance(c, dict)
            and str(c.get("loot_tag", ""))
            and str(c.get("loot_tag", "")) not in tag_to_actor
        }
    )
    unmapped_quest_tags = sorted(
        tag
        for tag, (tier, _key) in tag_to_row.items()
        if tier == "quest" and tag not in tag_to_actor
    )
    generic = next(
        (
            c
            for c in sorted(quest_actors)
            if quest_actors[c]["mesh_exists"] and quest_actors[c]["tier"] == "quest"
        ),
        "",
    )
    if generic == "":
        generic = next(
            (c for c in sorted(quest_actors) if quest_actors[c]["mesh_exists"]), ""
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(
            {
                "sources": {
                    "buckets": [
                        str((BUCKET_DIR / (n + ".json")).relative_to(ROOT))
                        for n in BUCKETS.values()
                    ],
                    "interactables": str(INTERACTABLES.relative_to(ROOT)),
                    "loot_actor_glob": [
                        "extracted/json/Gameplay/Loot/Actors/**/*.json",
                        "extracted/json/Gameplay/Loot/Actors/*.json",
                    ],
                },
                "buckets": buckets_out,
                "actors": actors,
                "quest_actors": quest_actors,
                "tag_to_actor": tag_to_actor,
                "fallback": {
                    "generic_quest_actor": generic,
                    "generic_quest_actor_note": (
                        "First alphabetically-sorted quest actor whose mesh "
                        "exists on disk; used only when a contract loot_tag "
                        "has no dedicated actor."
                    ),
                    "unmapped_contract_tags": unmapped_contract_tags,
                    "unmapped_quest_tags": unmapped_quest_tags,
                    "skipped_blueprints": sorted(skipped),
                    "missing_mesh_quest_actors": sorted(
                        c for c, a in quest_actors.items() if not a["mesh_exists"]
                    ),
                    "quest_fallback_note": (
                        "All 16 shipped contract loot_tags resolve to a "
                        "dedicated actor (VistaraFiles included), so the "
                        "fallback never fires on shipped content; it exists "
                        "for future/unmapped tags. Actors whose mesh is "
                        "missing on disk (coins, ReliquaryLoot glass set) "
                        "keep mesh_res '' and get the labelled box fallback "
                        "in loot_item.gd."
                    ),
                },
            },
            f,
            indent=2,
        )
        f.write("\n")
    print(
        f"wrote {OUT} ({len(actors)} bucket actors, "
        f"{len(quest_actors)} quest actors, {len(tag_to_actor)} tag mappings, "
        f"generic={generic or 'NONE'})"
    )
    print(f"unmapped contract tags: {unmapped_contract_tags}")
    print(f"unmapped quest tags: {unmapped_quest_tags}")


if __name__ == "__main__":
    main()
