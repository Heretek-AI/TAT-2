#!/usr/bin/env python3
"""Build game/data/generated/gameplay/clues.json from the shipped clue data.

Sources (all under extracted/json, the read-only UE dump):
  Gameplay/Clues/**/DT_*Fact*.json          clue fact tables (row struct
                                            TATClueFactSpec)
  Gameplay/Clues/**/CLS_*.json              TATClueSet / TATCompoundClueSet
  Gameplay/Clues/ClueSets/St_Clues_TextReplacement.json
  Gameplay/Clues/Readable/*.json            TATReadableClueVisuals data assets
  Gameplay/Clues/Spawners/*.json            readable clue spawner Blueprints
  Gameplay/Loot/Actors/**/*.json            _pickupClue payloads
  Gameplay/Tutorial/DA_Tutorial_Test.json   tutorial-spawned readable clues
  Maps/**/*.json                            map actors + TATReadableClueSpawner,
                                            TATNPCClueSpawnerComponent and
                                            TATQuestActorSpawnerComponent
                                            components
  game/data/generated/levels/**/*.tatlevel.json
                                            converted actor pos/basis.  Map
                                            actor names match the .tatlevel
                                            actor names exactly (verified).

Runtime duplicates are deliberately NOT read: every fact, clue set, readable
spawner, NPC clue component and quest spawner below is emitted from the
shipped table/asset, never from the port's earlier invented text.

Text resolution: FText.LocalizedString, then SourceString, then
CultureInvariantString, then a key lookup in en.csv (the locres export).
No namespace is ever synthesised: FText.Namespace is copied verbatim (or ""
when absent).

Output is deterministic: tables/clue sets/spawners are sorted by path/name,
dicts are written sorted where ordering carries no meaning.
"""

from __future__ import annotations

import csv
import glob
import json
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX = ROOT / "extracted" / "json"
MAPS = EX / "Maps"
OUT = ROOT / "game" / "data" / "generated" / "gameplay" / "clues.json"
LOC_CSV = ROOT / "game" / "data" / "generated" / "localization" / "en.csv"

STAT_KEYS = (
    "fact_tables",
    "fact_rows",
    "reachable_facts",
    "dead_facts",
    "suppressed_facts",
    "facts_without_text",
    "fact_tags",
    "clue_sets",
    "clue_entries",
    "enabled_clues",
    "disabled_clues",
    "clues_with_follow_up_dialogue",
    "clues_with_override_interaction_prompt",
    "readable_visuals",
    "readable_spawners",
    "readable_spawners_tagged",
    "npc_spawners",
    "quest_spawners",
    "quest_spawners_with_actions",
    "pickup_clues",
    "tutorial_clues",
    "text_replacement_keys",
)


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def load_json(path: Path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def list_records(data) -> list[dict]:
    return [o for o in data if isinstance(o, dict)] if isinstance(data, list) else []


def tag_of(value) -> str:
    if isinstance(value, dict):
        tag = value.get("TagName")
        if isinstance(tag, str):
            return tag
    return ""


def inside_quotes(value) -> str:
    """'Class'Foo' -> Foo; '/Game/X/Y.Y' -> /Game/X/Y.Y when unquoted."""
    s = value if isinstance(value, str) else ""
    if "'" in s:
        parts = s.split("'")
        if len(parts) >= 3:
            return parts[1]
        return parts[-1]
    return s


def asset_stem(value) -> str:
    """'/Game/Maps/Guildhall/Guildhall_P.Guildhall_P' -> 'Guildhall_P'."""
    iq = inside_quotes(value)
    return iq.rsplit("/", 1)[-1].split(".", 1)[0]


def asset_pkg(value) -> str:
    """'/Game/.../Foo.Foo' -> '/Game/.../Foo' (quotes stripped)."""
    iq = inside_quotes(value)
    return iq.split(".", 1)[0]


def class_name(value) -> str:
    """BlueprintGeneratedClass'/Game/.../BP_Foo.BP_Foo_C' -> BP_Foo_C."""
    iq = inside_quotes(value)
    return iq.rsplit("/", 1)[-1].split(".", 1)[-1]


def level_rel(path: Path) -> str:
    p = path.relative_to(MAPS).with_suffix("")
    return str(p).replace("\\", "/")


def map_id_for_level(level: str) -> str:
    folder = level.split("/", 1)[0]
    return {
        "Guildhall": "guildhall",
        "OldManor": "old_manor",
        "FTUE": "ftue",
        "ThievesDenTest": "thieves_den",
        "ThievesDen": "thieves_den",
        "Developers": "developers",
        "Buildings": "buildings",
        "Cinematics": "cinematics",
        "Menus": "menus",
    }.get(folder, folder.lower())


class LocTable:
    def __init__(self) -> None:
        self.rows: dict[str, str] = {}
        self.uses = 0
        if LOC_CSV.is_file():
            with open(LOC_CSV, "r", encoding="utf-8", newline="") as f:
                reader = csv.reader(f)
                next(reader, None)
                for row in reader:
                    if len(row) >= 2 and row[0]:
                        self.rows[row[0]] = row[1]

    def lookup(self, table: str, namespace: str, key: str) -> tuple[str, str]:
        """Return (text, lookup key used) or ("", "")."""
        if not key:
            return "", ""
        cands: list[str] = []
        if table:
            cands.append(asset_stem(table) + "." + key)
        if namespace:
            cands.append(namespace + "." + key)
        cands.append(key)
        for cand in cands:
            if cand in self.rows:
                self.uses += 1
                return self.rows[cand], cand
        return "", ""


def text_record(value, loc: LocTable, include_culture: bool = True) -> dict:
    """Resolve an FText dict + keep its authored metadata.

    Fact text follows the required LocalizedString -> SourceString -> en.csv
    order (include_culture=False).  Other authored FText fields (loot names,
    objectives) may legitimately be CultureInvariantString, so the default
    accepts it before the loc-table fallback.
    """
    rec = {
        "text": "",
        "key": "",
        "table": "",
        "namespace": "",
        "present": False,
        "resolved_from": "",
    }
    if not isinstance(value, dict):
        return rec
    rec["key"] = str(value.get("Key") or "")
    rec["table"] = str(value.get("TableId") or "")
    ns = value.get("Namespace")
    rec["namespace"] = str(ns) if isinstance(ns, str) else ""
    for field in ("LocalizedString", "SourceString", "CultureInvariantString"):
        if field == "CultureInvariantString" and not include_culture:
            continue
        v = value.get(field)
        if isinstance(v, str) and v != "":
            rec["text"] = v
            rec["present"] = True
            rec["resolved_from"] = field
            return rec
    fallback, used = loc.lookup(rec["table"], rec["namespace"], rec["key"])
    if fallback != "":
        rec["text"] = fallback
        rec["present"] = True
        rec["resolved_from"] = "en.csv:" + used
    return rec


def ttext(value, loc: LocTable) -> str:
    return text_record(value, loc)["text"]


def owner_actor_name(obj: dict) -> str:
    outer = inside_quotes((obj.get("Outer") or {}).get("ObjectName", ""))
    return outer.rsplit(".", 1)[-1] if outer else ""


def objects_by_name(records: list[dict]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for obj in records:
        name = obj.get("Name")
        if isinstance(name, str) and name not in out:
            out[name] = obj
    return out


def actor_class(obj: dict) -> str:
    t = obj.get("Type")
    if isinstance(t, str) and t:
        return t
    return class_name(obj.get("Class"))


def actor_label(obj: dict) -> str:
    label = obj.get("ActorLabel")
    return label if isinstance(label, str) else ""


def ue_point_cm_to_m(value) -> list[float]:
    if not isinstance(value, dict):
        return [0.0, 0.0, 0.0]
    x = float(value.get("X", 0.0))
    y = float(value.get("Y", 0.0))
    z = float(value.get("Z", 0.0))
    # UE x/y/z (cm) -> Godot x/z/-y (m), the same swap used by .tatlevel.
    return [round(x / 100.0, 6), round(z / 100.0, 6), round(-y / 100.0, 6)]


class TatLevelCache:
    def __init__(self) -> None:
        self.cache: dict[str, dict[str, dict]] = {}
        self.missing: list[str] = []

    def actors(self, level: str) -> dict[str, dict]:
        if level in self.cache:
            return self.cache[level]
        path = (
            ROOT / "game" / "data" / "generated" / "levels" / (level + ".tatlevel.json")
        )
        actors: dict[str, dict] = {}
        if path.is_file():
            data = load_json(path)
            for actor in data.get("actors", []) or []:
                name = actor.get("name")
                if isinstance(name, str):
                    actors.setdefault(name, actor)
        else:
            self.missing.append(level)
        self.cache[level] = actors
        return actors


def load_facts(loc: LocTable, warnings: list[str], failures: list[str]):
    paths = sorted(
        Path(p) for p in glob.glob(str(EX / "**" / "DT_*Fact*.json"), recursive=True)
    )
    facts: dict[str, dict] = {}
    table_rows: dict[str, int] = {}
    fact_tags: dict[str, list[str]] = defaultdict(list)
    for path in paths:
        data = load_json(path)
        if not isinstance(data, list) or not data:
            failures.append(f"fact table {rel(path)} is not a UE export list")
            continue
        table_obj = data[0]
        table = table_obj.get("Name")
        if not isinstance(table, str) or not table:
            failures.append(f"fact table {rel(path)} has no asset name")
            continue
        row_struct = inside_quotes(
            ((table_obj.get("Properties") or {}).get("RowStruct") or {}).get(
                "ObjectName", ""
            )
        )
        if row_struct and row_struct != "TATClueFactSpec":
            warnings.append(
                f"skipping {rel(path)}: row struct is {row_struct}, not TATClueFactSpec"
            )
            continue
        rows = table_obj.get("Rows") or {}
        table_rows[table] = len(rows)
        for row_index, (row, spec) in enumerate(rows.items()):
            fid = f"{table}:{row}"
            if fid in facts:
                failures.append(f"duplicate fact id {fid}")
                continue
            if not isinstance(spec, dict):
                failures.append(f"fact {fid} is not a struct")
                continue
            text = text_record(spec.get("JournalText"), loc, include_culture=False)
            fact = {
                "id": fid,
                "table": table,
                "row": row,
                "row_index": row_index,
                "fact_tag": tag_of(spec.get("factTag")),
                "journal_text": text["text"],
                "journal_text_key": text["key"],
                "journal_text_table": text["table"],
                "journal_text_namespace": text["namespace"],
                "journal_text_source": text["resolved_from"],
                "text_present": text["present"],
                "display_priority": int(spec.get("DisplayPriority") or 0),
                "category": tag_of(spec.get("Category")),
                "suppressed_by": [
                    tag_of(t)
                    for t in (spec.get("SuppressedByFacts") or [])
                    if tag_of(t)
                ],
                "source_file": rel(path),
                "consumers": [],
                "reachable": False,
            }
            facts[fid] = fact
            if fact["fact_tag"]:
                fact_tags[fact["fact_tag"]].append(fid)
            else:
                warnings.append(f"fact {fid} has no factTag")
            if not fact["text_present"]:
                warnings.append(f"fact {fid} has no authored journal text")
    return facts, fact_tags, table_rows, paths


def load_clue_sets(loc: LocTable, facts: dict[str, dict], failures: list[str]):
    paths = sorted(
        Path(p) for p in glob.glob(str(EX / "**" / "CLS_*.json"), recursive=True)
    )
    sets: dict[str, dict] = {}
    for path in paths:
        data = load_json(path)
        if not isinstance(data, list) or not data:
            failures.append(f"clue set {rel(path)} is not a UE export list")
            continue
        obj = data[0]
        ctype = obj.get("Type") or ""
        if ctype not in ("TATClueSet", "TATCompoundClueSet"):
            continue
        name = obj.get("Name")
        if not isinstance(name, str) or not name:
            failures.append(f"clue set {rel(path)} has no asset name")
            continue
        if name in sets:
            failures.append(f"duplicate clue set name {name}")
            continue
        props = obj.get("Properties") or {}
        clues: list[dict] = []
        for index, entry in enumerate(props.get("Clues") or []):
            clue = entry.get("Clue") if isinstance(entry, dict) else None
            if not isinstance(clue, dict):
                failures.append(f"{name}[{index}] has no clue struct")
                continue
            text = text_record(clue.get("ClueText"), loc)
            fact_refs: list[dict] = []
            fact_ids: list[str] = []
            fact_tags: list[str] = []
            for handle in clue.get("Facts") or []:
                if not isinstance(handle, dict):
                    continue
                table = asset_stem(
                    (handle.get("DataTable") or {}).get("ObjectName", "")
                )
                row = str(handle.get("RowName") or "")
                fid = f"{table}:{row}"
                if fid not in facts:
                    failures.append(f"{name}[{index}] references missing fact {fid}")
                    continue
                fact_refs.append({"id": fid, "tag": facts[fid]["fact_tag"]})
                fact_ids.append(fid)
                if facts[fid]["fact_tag"]:
                    fact_tags.append(facts[fid]["fact_tag"])
            visuals = inside_quotes((clue.get("Visuals") or {}).get("ObjectName", ""))
            alt_texts = [
                ttext(t, loc)
                for t in (clue.get("AlternateClueText") or [])
                if isinstance(t, dict)
            ]
            follow_up = text_record(clue.get("FollowUpDialogue"), loc)
            override_prompt = text_record(clue.get("OverrideInteractionPrompt"), loc)
            clues.append(
                {
                    "index": index,
                    "enabled": bool(entry.get("Enabled", True)),
                    "visuals": visuals,
                    "placement_tag": tag_of(clue.get("PlacementTag")),
                    "distribution": str(clue.get("Distribution") or ""),
                    "text": text["text"],
                    "text_key": text["key"],
                    "text_table": text["table"],
                    "text_namespace": text["namespace"],
                    "text_present": text["present"],
                    "alternate_texts": alt_texts,
                    "allow_text_replacement": bool(
                        clue.get("AllowTextReplacement", False)
                    ),
                    "allow_follow_up_dialogue": bool(
                        clue.get("AllowFollowUpDialogue", False)
                    ),
                    "follow_up_dialogue": follow_up,
                    "use_override_interaction_prompt": bool(
                        clue.get("UseOverrideInteractionPrompt", False)
                    ),
                    "override_interaction_prompt": override_prompt,
                    "facts": fact_refs,
                    "fact_ids": fact_ids,
                    "fact_tags": fact_tags,
                }
            )
        enabled = [c for c in clues if c["enabled"]]
        disabled = [c for c in clues if not c["enabled"]]
        placement_demand = Counter(
            c["placement_tag"] for c in enabled if c["placement_tag"]
        )
        all_fact_ids = sorted({fid for c in clues for fid in c["fact_ids"]})
        all_fact_tags = sorted({t for c in clues for t in c["fact_tags"]})
        sets[name] = {
            "name": name,
            "type": ctype,
            "source_file": rel(path),
            "clue_source_tag": tag_of(props.get("ClueSource")),
            "counts": {
                "total": len(clues),
                "enabled": len(enabled),
                "disabled": len(disabled),
            },
            "placement_demand": dict(sorted(placement_demand.items())),
            "fact_ids": all_fact_ids,
            "fact_tags": all_fact_tags,
            "consumers": [],
            "clues": clues,
        }
    return sets, paths


def clue_set_consumers(sets: dict[str, dict], warnings: list[str]) -> None:
    # Quest graph references (full graphs and module fragments).
    for path in sorted(
        Path(p) for p in glob.glob(str(EX / "**" / "QG_*.json"), recursive=True)
    ):
        data = load_json(path)
        records = list_records(data)
        if not records:
            continue
        graph_name = ""
        for obj in records:
            if obj.get("Type") in ("TATQuestGraph", "TATQuestGraphModule"):
                graph_name = str(obj.get("Name") or "")
                break
        if not graph_name:
            graph_obj = next(
                (
                    o
                    for o in records
                    if (o.get("Type") or "").startswith("TATQuestGraph")
                ),
                None,
            )
            outer = inside_quotes(
                (graph_obj or {}).get("Outer", {}).get("ObjectName", "")
            )
            graph_name = outer.rsplit(".", 1)[-1] if outer else path.stem
        for obj in records:
            props = obj.get("Properties") or {}
            clue_set = props.get("ClueSet")
            if not isinstance(clue_set, dict):
                continue
            set_name = asset_stem(clue_set.get("AssetPathName", ""))
            if not set_name:
                continue
            if set_name not in sets:
                warnings.append(
                    f"quest graph {graph_name} node {obj.get('Name')} references unknown clue set {set_name}"
                )
                continue
            consumer = {
                "kind": "quest_graph",
                "graph": graph_name,
                "node": str(obj.get("Name") or ""),
                "node_type": str(obj.get("Type") or ""),
                "source_file": rel(path),
            }
            if consumer not in sets[set_name]["consumers"]:
                sets[set_name]["consumers"].append(consumer)

    # Contract table references.
    contract_path = EX / "Gameplay" / "Quests" / "CDT_Contracts.json"
    if contract_path.is_file():
        data = load_json(contract_path)
        if isinstance(data, list) and data:
            for contract_id, row in (data[0].get("Rows") or {}).items():
                cs = (row or {}).get("Clues") or {}
                set_name = asset_stem(cs.get("AssetPathName", ""))
                if not set_name:
                    continue
                if set_name not in sets:
                    warnings.append(
                        f"contract {contract_id} references unknown clue set {set_name}"
                    )
                    continue
                consumer = {"kind": "contract", "id": contract_id}
                if consumer not in sets[set_name]["consumers"]:
                    sets[set_name]["consumers"].append(consumer)
    for entry in sets.values():
        entry["consumers"].sort(key=lambda c: json.dumps(c, sort_keys=True))
        # Mirror the set consumers onto each authored clue entry: consumers are
        # a property of the set asset, not of an individual clue, but consumers
        # of the JSON read either level.
        for clue in entry["clues"]:
            clue["consumers"] = entry["consumers"]


def add_fact_consumer(facts: dict[str, dict], fid: str, consumer: dict) -> None:
    fact = facts.get(fid)
    if fact is None:
        return
    if consumer not in fact["consumers"]:
        fact["consumers"].append(consumer)


def load_tutorial_clues(
    loc: LocTable, facts: dict[str, dict], warnings: list[str]
) -> list[dict]:
    path = EX / "Gameplay" / "Tutorial" / "DA_Tutorial_Test.json"
    out: list[dict] = []
    if not path.is_file():
        warnings.append(
            "DA_Tutorial_Test.json missing; tutorial-spawned clue facts cannot be marked reachable"
        )
        return out
    for obj in list_records(load_json(path)):
        if obj.get("Type") != "TATTutorialAction_SpawnReadableClue":
            continue
        props = obj.get("Properties") or {}
        clue = props.get("Clue") or {}
        if not isinstance(clue, dict):
            continue
        text = text_record(clue.get("ClueText"), loc)
        fact_refs = []
        for handle in clue.get("Facts") or []:
            table = asset_stem(
                ((handle or {}).get("DataTable") or {}).get("ObjectName", "")
            )
            row = str((handle or {}).get("RowName") or "")
            fid = f"{table}:{row}"
            if fid not in facts:
                warnings.append(
                    f"tutorial clue {obj.get('Name')} references missing fact {fid}"
                )
                continue
            fact_refs.append({"id": fid, "tag": facts[fid]["fact_tag"]})
            add_fact_consumer(
                facts,
                fid,
                {
                    "kind": "tutorial_clue",
                    "asset": "DA_Tutorial_Test",
                    "action": str(obj.get("Name") or ""),
                },
            )
        record = {
            "asset": "DA_Tutorial_Test",
            "action": str(obj.get("Name") or ""),
            "source_file": rel(path),
            "spawner_ue": str(
                (props.get("clueSpawner") or {}).get("AssetPathName") or ""
            ),
            "spawner_actor": str(
                (props.get("clueSpawner") or {}).get("SubPathString") or ""
            ),
            "visuals": inside_quotes((clue.get("Visuals") or {}).get("ObjectName", "")),
            "text": text["text"],
            "text_key": text["key"],
            "text_table": text["table"],
            "text_namespace": text["namespace"],
            "text_present": text["present"],
            "facts": fact_refs,
            "fact_ids": [f["id"] for f in fact_refs],
        }
        out.append(record)
    out.sort(key=lambda r: r["action"])
    return out


def load_pickup_clues(
    loc: LocTable, facts: dict[str, dict], warnings: list[str]
) -> list[dict]:
    loot_rows = {}
    loot_path = EX / "Gameplay" / "Loot" / "Data" / "DT_LootInfo_Quest.json"
    if loot_path.is_file():
        data = load_json(loot_path)
        if isinstance(data, list) and data:
            loot_rows = data[0].get("Rows") or {}
    out: list[dict] = []
    paths = sorted(
        Path(p)
        for p in glob.glob(
            str(EX / "Gameplay" / "Loot" / "Actors" / "**" / "*.json"), recursive=True
        )
    )
    for path in paths:
        for obj in list_records(load_json(path)):
            props = obj.get("Properties") or {}
            clue = props.get("_pickupClue")
            if not isinstance(clue, dict):
                continue
            row = str((props.get("LootRowHandle") or {}).get("RowName") or "")
            loot = loot_rows.get(row) or {}
            text = text_record(clue.get("ClueText"), loc)
            fact_refs = []
            for handle in clue.get("Facts") or []:
                table = asset_stem(
                    ((handle or {}).get("DataTable") or {}).get("ObjectName", "")
                )
                fact_row = str((handle or {}).get("RowName") or "")
                fid = f"{table}:{fact_row}"
                if fid not in facts:
                    warnings.append(
                        f"pickup clue {obj.get('Name')} references missing fact {fid}"
                    )
                    continue
                fact_refs.append({"id": fid, "tag": facts[fid]["fact_tag"]})
                add_fact_consumer(
                    facts,
                    fid,
                    {
                        "kind": "pickup_clue",
                        "actor_class": actor_class(obj),
                        "loot_row": row,
                    },
                )
            if row and row not in loot_rows:
                warnings.append(
                    f"pickup clue {obj.get('Name')} has unknown loot row {row}"
                )
            record = {
                "blueprint": str(obj.get("Name") or "")
                .removeprefix("Default__")
                .removesuffix("_C"),
                "cdo": str(obj.get("Name") or ""),
                "actor_class": actor_class(obj),
                "source_file": rel(path),
                "loot_row": row,
                "loot_tag": tag_of((loot.get("LootIdentifier") or {}).get("LootTag")),
                "display_name": ttext(loot.get("DisplayName"), loc),
                "value": int(loot.get("Value") or 0),
                "text": text["text"],
                "text_key": text["key"],
                "text_table": text["table"],
                "text_namespace": text["namespace"],
                "text_present": text["present"],
                "facts": fact_refs,
                "fact_ids": [f["id"] for f in fact_refs],
            }
            out.append(record)
    out.sort(key=lambda r: (r["loot_row"], r["blueprint"]))
    return out


def load_readable_visuals(loc: LocTable, warnings: list[str]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    paths = sorted(
        Path(p)
        for p in glob.glob(
            str(EX / "Gameplay" / "Clues" / "Readable" / "DA_ReadableVisuals_*.json"),
            recursive=True,
        )
    )
    for path in paths:
        data = load_json(path)
        if not isinstance(data, list) or not data:
            continue
        obj = data[0]
        name = str(obj.get("Name") or "")
        props = obj.get("Properties") or {}
        actor = (props.get("ReadableActorClass") or {}).get("AssetPathName", "")
        out[name] = {
            "asset": "/Game/Gameplay/Clues/Readable/" + name,
            "actor_class": str(actor),
            "actor_class_name": class_name(actor),
            "type": class_name(actor)
            .removeprefix("BP_ReadableClueActor_")
            .removesuffix("_C"),
            "source_file": rel(path),
        }
    if out:
        warnings.append(
            "UTATReadableClueVisuals.ReadableType is not serialized in the data assets; "
            "readable_visuals.type is derived from the actor class name"
        )
    return dict(sorted(out.items()))


def level_actor(level: str, actor: str, tat: TatLevelCache, warnings: list[str]):
    actors = tat.actors(level)
    entry = actors.get(actor)
    if entry is None:
        warnings.append(f"no .tatlevel actor {actor!r} for level {level}")
    return entry


def fallback_transform(
    owner: dict | None,
    records: dict[str, dict],
    tat: TatLevelCache,
    level: str,
    actor: str,
):
    """Last-resort pos from the owner's root SceneComponent (UE cm -> m)."""
    if not owner:
        return None
    root_ref = (owner.get("Properties") or {}).get("RootComponent") or {}
    root_name = inside_quotes(root_ref.get("ObjectName", "")).rsplit(".", 1)[-1]
    root = records.get(root_name) or {}
    loc = (root.get("Properties") or {}).get("RelativeLocation")
    pos = ue_point_cm_to_m(loc)
    return pos


def load_map_spawners(loc: LocTable, facts: dict[str, dict], warnings: list[str]):
    tat = TatLevelCache()
    readable: list[dict] = []
    npc: list[dict] = []
    quest: list[dict] = []
    map_paths = sorted(
        Path(p) for p in glob.glob(str(MAPS / "**" / "*.json"), recursive=True)
    )
    qg_paths = set(glob.glob(str(MAPS / "**" / "QG_*.json"), recursive=True))
    for path in map_paths:
        if str(path) in qg_paths:
            continue
        data = load_json(path)
        records = list_records(data)
        if not records:
            continue
        by_name = objects_by_name(records)
        level = level_rel(path)
        map_id = map_id_for_level(level)
        for obj in records:
            otype = obj.get("Type") or ""
            if otype not in (
                "TATReadableClueSpawner",
                "TATNPCClueSpawnerComponent",
                "TATQuestActorSpawnerComponent",
            ):
                continue
            props = obj.get("Properties") or {}
            actor_name = owner_actor_name(obj)
            owner = by_name.get(actor_name) or {}
            actor_entry = level_actor(level, actor_name, tat, warnings)
            if actor_entry is not None:
                pos = [float(v) for v in actor_entry.get("pos", [0.0, 0.0, 0.0])]
                basis = [
                    float(v)
                    for v in actor_entry.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
                ]
                scale = [float(v) for v in actor_entry.get("scale", [1.0, 1.0, 1.0])]
                transform_source = "tatlevel"
            else:
                pos = fallback_transform(owner, by_name, tat, level, actor_name) or [
                    0.0,
                    0.0,
                    0.0,
                ]
                basis = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
                scale = [1.0, 1.0, 1.0]
                transform_source = "fallback_root_component"

            if otype == "TATReadableClueSpawner":
                readable.append(
                    {
                        "map_id": map_id,
                        "level": level,
                        "actor": actor_name,
                        "actor_class": actor_class(owner),
                        "actor_label": actor_label(owner),
                        "component": str(obj.get("Name") or ""),
                        "placement_tag": tag_of(props.get("PlacementTag")),
                        "pos": pos,
                        "basis": basis,
                        "scale": scale,
                        "transform_source": transform_source,
                        "source_file": rel(path),
                    }
                )
            elif otype == "TATNPCClueSpawnerComponent":
                npc.append(
                    {
                        "map_id": map_id,
                        "level": level,
                        "actor": actor_name,
                        "actor_class": actor_class(owner),
                        "actor_label": actor_label(owner),
                        "component": str(obj.get("Name") or ""),
                        "pos": pos,
                        "presence_only": True,
                        "source_file": rel(path),
                    }
                )
            else:
                actions = []
                for action in props.get("_spawnActions") or []:
                    if not isinstance(action, dict):
                        continue
                    indicator = (action.get("SpawnIndicatorClass") or {}).get(
                        "ObjectName", ""
                    )
                    actions.append(
                        {
                            "clue_fact_tag": tag_of(action.get("ClueFactTag")),
                            "indicator_class": class_name(indicator),
                            "indicator_ue": inside_quotes(indicator),
                            "optional_location_proxy": str(
                                (action.get("OptionalLocationProxy") or {}).get(
                                    "AssetPathName"
                                )
                                or ""
                            ),
                        }
                    )
                scene = props.get("_sceneRequirement")
                quest.append(
                    {
                        "map_id": map_id,
                        "level": level,
                        "actor": actor_name,
                        "actor_class": actor_class(owner),
                        "actor_label": actor_label(owner),
                        "component": str(obj.get("Name") or ""),
                        "quest_location_tag": tag_of(props.get("_questLocationTag")),
                        "clue_location_tag": tag_of(props.get("_clueLocationTag")),
                        "clue_location_text": ttext(
                            props.get("_clueLocationText"), loc
                        ),
                        "spawn_actions": actions,
                        "scene_requirement": scene if isinstance(scene, dict) else {},
                        "relative_location_cm": props.get("RelativeLocation") or {},
                        "pos": pos,
                        "basis": basis,
                        "transform_source": transform_source,
                        "source_file": rel(path),
                    }
                )
    readable.sort(key=lambda r: (r["level"], r["actor"]))
    npc.sort(key=lambda r: (r["level"], r["actor"], r["component"]))
    quest.sort(key=lambda r: (r["level"], r["actor"], r["component"]))
    if tat.missing:
        for level in sorted(set(tat.missing)):
            warnings.append(f"no generated .tatlevel for level {level}")
    return readable, npc, quest


def load_text_replacement(loc: LocTable) -> dict[str, dict]:
    path = EX / "Gameplay" / "Clues" / "ClueSets" / "St_Clues_TextReplacement.json"
    out: dict[str, dict] = {}
    if not path.is_file():
        return out
    data = load_json(path)
    if not isinstance(data, list) or not data:
        return out
    table = data[0].get("StringTable") or {}
    for key, value in (table.get("KeysToEntries") or {}).items():
        out[key] = {
            "key": key,
            "text": value,
            "table": "/Game/Gameplay/Clues/ClueSets/St_Clues_TextReplacement",
            "table_name": "St_Clues_TextReplacement",
            "source_file": rel(path),
        }
    return dict(sorted(out.items()))


def main() -> None:
    warnings: list[str] = []
    failures: list[str] = []
    loc = LocTable()

    facts, fact_tags, table_rows, fact_paths = load_facts(loc, warnings, failures)
    clue_sets, clue_paths = load_clue_sets(loc, facts, failures)
    clue_set_consumers(clue_sets, warnings)
    empty_sets = sorted(
        name for name, entry in clue_sets.items() if entry["counts"]["total"] == 0
    )
    if empty_sets:
        warnings.append(
            "clue set assets with no authored clue entries (placeholder/compound): "
            + ", ".join(empty_sets)
        )
    tutorial_clues = load_tutorial_clues(loc, facts, warnings)
    pickup_clues = load_pickup_clues(loc, facts, warnings)
    readable_visuals = load_readable_visuals(loc, warnings)
    readable_spawners, npc_spawners, quest_spawners = load_map_spawners(
        loc, facts, warnings
    )
    text_replacement = load_text_replacement(loc)

    scene_only = [
        q
        for q in quest_spawners
        if not q["spawn_actions"] and isinstance(q.get("scene_requirement"), dict)
    ]
    if scene_only:
        warnings.append(
            f"{len(scene_only)} quest spawner components have no _spawnActions; "
            "they are scene-requirement spawners and are kept with an empty action list ("
            + ", ".join(f"{q['level']}:{q['actor']}" for q in scene_only)
            + ")"
        )
    if quest_spawners and not any(q["clue_location_tag"] for q in quest_spawners):
        warnings.append(
            "UTATQuestActorSpawnerComponent._clueLocationTag is not serialized on any "
            "authored instance; clue_location_tag is empty (not synthesised)"
        )

    # Quest-spawner action tags are tag-level consumers of facts.  They do not
    # make a fact journal-reachable on their own (the row still needs an enabled
    # readable clue / tutorial clue / pickup clue), but they explain the tag.
    action_tags: dict[str, list[dict]] = defaultdict(list)
    for qs in quest_spawners:
        for action in qs["spawn_actions"]:
            tag = action["clue_fact_tag"]
            if not tag:
                continue
            action_tags[tag].append(
                {
                    "kind": "quest_spawn_action",
                    "level": qs["level"],
                    "actor": qs["actor"],
                    "tag": tag,
                }
            )
    for tag, consumers in action_tags.items():
        for fid in fact_tags.get(tag, []):
            for consumer in consumers:
                add_fact_consumer(facts, fid, consumer)

    # Attach per-entry clue-set consumer records (the set-level list already
    # exists; this makes a fact's provenance explicit).
    for set_name, entry in clue_sets.items():
        for clue in entry["clues"]:
            for fid in clue["fact_ids"]:
                add_fact_consumer(
                    facts,
                    fid,
                    {
                        "kind": "clue_set",
                        "clue_set": set_name,
                        "clue_index": clue["index"],
                        "enabled": clue["enabled"],
                    },
                )

    for fact in facts.values():
        reachable = False
        for consumer in fact["consumers"]:
            if consumer.get("kind") == "clue_set":
                if consumer.get("enabled", False):
                    reachable = True
                    break
            elif consumer.get("kind") in ("tutorial_clue", "pickup_clue"):
                reachable = True
                break
        fact["reachable"] = reachable
        fact["consumers"].sort(key=lambda c: json.dumps(c, sort_keys=True))

    dead_ids = sorted(fid for fid, fact in facts.items() if not fact["reachable"])
    suppressed = sorted(fact["id"] for fact in facts.values() if fact["suppressed_by"])
    if dead_ids:
        warnings.append(
            f"{len(dead_ids)} clue facts are unreachable (no enabled clue, tutorial clue "
            "or pickup-clue consumer); they are kept in facts with reachable=false: "
            + ", ".join(dead_ids)
        )

    # Placement coverage diagnostics (informational; parse_quests performs the
    # strict mission-scoped check).
    spawner_tags = Counter(
        r["placement_tag"] for r in readable_spawners if r["placement_tag"]
    )
    unplaced = sorted(
        {
            clue["placement_tag"]
            for entry in clue_sets.values()
            if any(
                c["kind"] in ("contract", "quest_graph")
                and not str(c.get("source_file", "")).startswith(
                    "extracted/json/Developers/"
                )
                for c in entry["consumers"]
            )
            for clue in entry["clues"]
            if clue["enabled"]
            and clue["placement_tag"]
            and clue["placement_tag"] not in spawner_tags
        }
    )
    for tag in unplaced:
        warnings.append(
            f"no readable spawner carries placement tag {tag} (exact match, all levels)"
        )

    if len(table_rows) != len(fact_paths):
        failures.append(
            f"loaded {len(table_rows)} fact tables from {len(fact_paths)} files (duplicate table names?)"
        )

    stats = {
        "fact_tables": len(table_rows),
        "fact_rows": len(facts),
        "reachable_facts": len(facts) - len(dead_ids),
        "dead_facts": len(dead_ids),
        "suppressed_facts": len(suppressed),
        "facts_without_text": sum(1 for f in facts.values() if not f["text_present"]),
        "fact_tags": len(fact_tags),
        "clue_sets": len(clue_sets),
        "clue_entries": sum(e["counts"]["total"] for e in clue_sets.values()),
        "enabled_clues": sum(e["counts"]["enabled"] for e in clue_sets.values()),
        "disabled_clues": sum(e["counts"]["disabled"] for e in clue_sets.values()),
        "clues_with_follow_up_dialogue": sum(
            1
            for e in clue_sets.values()
            for c in e["clues"]
            if c["allow_follow_up_dialogue"]
        ),
        "clues_with_override_interaction_prompt": sum(
            1
            for e in clue_sets.values()
            for c in e["clues"]
            if c["use_override_interaction_prompt"]
        ),
        "readable_visuals": len(readable_visuals),
        "readable_spawners": len(readable_spawners),
        "readable_spawners_tagged": sum(
            1 for r in readable_spawners if r["placement_tag"]
        ),
        "npc_spawners": len(npc_spawners),
        "quest_spawners": len(quest_spawners),
        "quest_spawners_with_actions": sum(
            1 for r in quest_spawners if r["spawn_actions"]
        ),
        "pickup_clues": len(pickup_clues),
        "tutorial_clues": len(tutorial_clues),
        "text_replacement_keys": len(text_replacement),
    }

    output = {
        "generated_by": "tools/parse_clues.py",
        "sources": {
            "fact_tables": [rel(p) for p in fact_paths],
            "clue_sets": [rel(p) for p in clue_paths],
            "localization": rel(LOC_CSV),
            "tatlevels": "game/data/generated/levels/**/*.tatlevel.json",
        },
        "stats": stats,
        "facts": dict(sorted(facts.items())),
        "fact_tags": {k: v for k, v in sorted(fact_tags.items())},
        "clue_sets": dict(sorted(clue_sets.items())),
        "readable_visuals": readable_visuals,
        "readable_spawners": readable_spawners,
        "npc_spawners": npc_spawners,
        "quest_spawners": quest_spawners,
        "pickup_clues": pickup_clues,
        "tutorial_clues": tutorial_clues,
        "text_replacement": text_replacement,
        "dead_fact_ids": dead_ids,
        "suppressed_fact_ids": suppressed,
        "validation": {
            "ok": not failures,
            "failures": sorted(failures),
            "warnings": sorted(warnings),
        },
        "warnings": sorted(warnings),
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False, sort_keys=False)
        f.write("\n")

    print(
        "clues: " + ", ".join(f"{k}={stats[k]}" for k in STAT_KEYS) + f" -> {rel(OUT)}"
    )
    for warning in sorted(warnings):
        print(f"WARN: {warning}")
    if failures:
        for failure in sorted(failures):
            print(f"FAIL: {failure}")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
