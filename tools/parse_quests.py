#!/usr/bin/env python3
"""Build game/data/generated/gameplay/quests.json from the shipped quest data.

Sources (all under extracted/json):
  Gameplay/Quests/CDT_Contracts.json       16 contract rows (TATContractInfo)
  Gameplay/Quests/CDT_Missions.json        11 mission rows (TATMissionInfo)
  Gameplay/Loot/Data/DT_LootInfo_Quest.json
  Gameplay/Loot/Actors/**/*.json           quest loot actor classes
  Gameplay/Clues/ClueSets/St_Clues_TextReplacement.json
  Maps/**/QG_*.json                        TATQuestGraph / TATQuestGraphModule
  Maps/**/*.json                           TATQuestActorSpawnerComponent and
                                           TATReadableClueSpawner components
  Developers/JCamera/QG_Localization_Map.json

Reachability follows the authored graph from TATQuestGraphRootNode nodes only.
Several shipped graphs also list objective/clue nodes in RootNodes; those are
not execution roots (they have no incoming root path) and are reported as
declared roots that are not reachable, e.g. TATQuestGraphObjectiveNode_2 in
QG_Guildhall_Set and TATQuestGraphObjectiveNode_20 plus the isolated
TATQuestGraphClueSetNode_15 in QG_Guildhall_LootTheRoom.

Validation is fail-closed:
  * every ItemsToSteal / Item LootTag has a DT_LootInfo_Quest row;
  * every objective/contract quest location tag has >= 1 spawner on its map;
  * every enabled CLS placement tag has enough readable spawners in the
    mission's loaded levels (parent/namespace tag canonicalisation is used
    where the shipped tag hierarchy is inconsistent; each use is reported);
  * every referenced CLS, QG module and mission QG exists.
A hard validation failure writes the JSON for inspection and exits 1.
"""

from __future__ import annotations

import csv
import glob
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EX = ROOT / "extracted" / "json"
MAPS = EX / "Maps"
OUT = ROOT / "game" / "data" / "generated" / "gameplay" / "quests.json"
LOC_CSV = ROOT / "game" / "data" / "generated" / "localization" / "en.csv"

CONTRACTS_TABLE = EX / "Gameplay" / "Quests" / "CDT_Contracts.json"
MISSIONS_TABLE = EX / "Gameplay" / "Quests" / "CDT_Missions.json"
LOOT_TABLE = EX / "Gameplay" / "Loot" / "Data" / "DT_LootInfo_Quest.json"
TEXT_REPLACEMENT = (
    EX / "Gameplay" / "Clues" / "ClueSets" / "St_Clues_TextReplacement.json"
)

OBJECTIVE_KEYS = {
    "Item",
    "ItemsToSteal",
    "NumberToSteal",
    "NumberToSpawn",
    "ObjectiveText",
    "OverrideObjectiveText",
    "QuestSpawnLocation",
    "ShouldOverrideQuestSpawnLocation",
    "MinNumberToSteal",
    "OverrideMinNumberToSteal",
    "amount",
}

MAP_FOLDER_IDS = {
    "Guildhall": "guildhall",
    "OldManor": "old_manor",
    "FTUE": "ftue",
    "ThievesDenTest": "thieves_den",
    "ThievesDen": "thieves_den",
    "Developers": "developers",
    "Buildings": "buildings",
    "Menus": "menus",
    "Cinematics": "cinematics",
}


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
        t = value.get("TagName")
        if isinstance(t, str):
            return t
    return ""


def inside_quotes(value) -> str:
    s = value if isinstance(value, str) else ""
    if "'" in s:
        parts = s.split("'")
        return parts[1] if len(parts) >= 3 else parts[-1]
    return s


def asset_stem(value) -> str:
    iq = inside_quotes(value)
    return iq.rsplit("/", 1)[-1].split(".", 1)[0]


def asset_pkg(value) -> str:
    return inside_quotes(value).split(".", 1)[0]


def class_name(value) -> str:
    iq = inside_quotes(value)
    return iq.rsplit("/", 1)[-1].split(".", 1)[-1]


def ue_asset_to_json(ue_path: str) -> Path | None:
    """'/Game/Maps/Guildhall/QG_Foo.QG_Foo' -> extracted/json/Maps/.../QG_Foo.json."""
    pkg = asset_pkg(ue_path)
    if not pkg.startswith("/Game/"):
        return None
    cand = EX / (pkg[len("/Game/") :] + ".json")
    return cand if cand.is_file() else None


def json_to_ue_asset(path: Path) -> str:
    r = path.relative_to(EX).with_suffix("")
    return "/Game/" + r.as_posix()


def level_rel(path: Path) -> str:
    return str(path.relative_to(MAPS).with_suffix("")).replace("\\", "/")


def map_id_for_folder(folder: str) -> str:
    return MAP_FOLDER_IDS.get(folder, folder.lower())


def map_id_for_ue(ue_path: str) -> str:
    pkg = asset_pkg(ue_path)
    if "/Maps/" in pkg:
        rest = pkg.split("/Maps/", 1)[1]
        return map_id_for_folder(rest.split("/", 1)[0])
    if "/Developers/" in pkg:
        return "developers"
    return ""


class LocTable:
    def __init__(self) -> None:
        self.rows: dict[str, str] = {}
        if LOC_CSV.is_file():
            with open(LOC_CSV, "r", encoding="utf-8", newline="") as f:
                reader = csv.reader(f)
                next(reader, None)
                for row in reader:
                    if len(row) >= 2 and row[0]:
                        self.rows[row[0]] = row[1]

    def lookup(self, table: str, namespace: str, key: str) -> tuple[str, str]:
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
                return self.rows[cand], cand
        return "", ""


def text_record(value, loc: LocTable) -> dict:
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


def ref_name(value) -> str:
    """'TATQuestGraphNode'QG:Node' -> 'Node'."""
    iq = inside_quotes(
        (value or {}).get("ObjectName", "") if isinstance(value, dict) else value
    )
    return iq.rsplit(":", 1)[-1] if iq else ""


def rewards(value) -> list[dict]:
    out: list[dict] = []
    for reward in value or []:
        if not isinstance(reward, dict):
            continue
        rt = (reward.get("RewardType") or {}).get("ObjectName", "")
        out.append(
            {
                "reward_type": class_name(rt),
                "reward_type_ue": inside_quotes(rt),
                "quantity": int(reward.get("Quantity") or 0),
            }
        )
    return out


def is_set_objective(tags: list[str]) -> bool:
    if len(tags) < 2:
        return False
    prefixes = {t.rsplit(".", 1)[0] for t in tags if "." in t}
    if len(prefixes) != 1:
        return False
    prefix = next(iter(prefixes))
    return ".Set" in prefix or "Set." in prefix or "UrnSet" in prefix


def item_record(item, loc: LocTable) -> dict:
    if not isinstance(item, dict):
        item = {}
    loot_tag = tag_of((item.get("Item") or {}).get("LootTag"))
    return {
        "loot_tag": loot_tag,
        "number_to_steal": item.get("NumberToSteal"),
        "number_to_spawn": item.get("NumberToSpawn"),
        "quest_spawn_location": tag_of(item.get("QuestSpawnLocation")),
        "should_override_quest_spawn_location": (
            item.get("ShouldOverrideQuestSpawnLocation")
            if "ShouldOverrideQuestSpawnLocation" in item
            else None
        ),
    }


def objective_record(obj, loc: LocTable) -> dict:
    if not isinstance(obj, dict):
        return {
            "kind": "none",
            "items": [],
            "objective_text": "",
            "objective_text_present": False,
            "unknown_fields": [],
        }
    items: list[dict] = []
    kind = "none"
    raw_items = obj.get("ItemsToSteal")
    if isinstance(raw_items, list) and raw_items:
        items = [item_record(x, loc) for x in raw_items if isinstance(x, dict)]
        tags = [i["loot_tag"] for i in items if i["loot_tag"]]
        kind = "set" if is_set_objective(tags) else "multiple"
    elif isinstance(obj.get("Item"), dict):
        items = [item_record(obj, loc)]
        kind = "single"
    elif "amount" in obj:
        kind = "loot_amount"
    text = text_record(obj.get("ObjectiveText"), loc)
    unknown = sorted(set(obj.keys()) - OBJECTIVE_KEYS)
    return {
        "kind": kind,
        "items": items,
        "number_to_steal": obj.get("NumberToSteal"),
        "number_to_spawn": obj.get("NumberToSpawn"),
        "quest_spawn_location": tag_of(obj.get("QuestSpawnLocation")),
        "should_override_quest_spawn_location": (
            obj.get("ShouldOverrideQuestSpawnLocation")
            if "ShouldOverrideQuestSpawnLocation" in obj
            else None
        ),
        "min_number_to_steal": obj.get("MinNumberToSteal"),
        "override_min_number_to_steal": (
            obj.get("OverrideMinNumberToSteal")
            if "OverrideMinNumberToSteal" in obj
            else None
        ),
        "amount": obj.get("amount"),
        "objective_text": text["text"],
        "objective_text_key": text["key"],
        "objective_text_table": text["table"],
        "objective_text_namespace": text["namespace"],
        "objective_text_present": text["present"],
        "override_objective_text": (
            obj.get("OverrideObjectiveText") if "OverrideObjectiveText" in obj else None
        ),
        "unknown_fields": unknown,
    }


def durations(row: dict) -> list[float]:
    base = row.get("MatchDurationsByDifficulty")
    return [
        float(base if base is not None else 0.0),
        float(row.get("MatchDurationsByDifficulty[1]", 0.0) or 0.0),
        float(row.get("MatchDurationsByDifficulty[2]", 0.0) or 0.0),
    ]


def contract_order(contract_id: str, serialized: int) -> tuple[int, bool]:
    m = re.match(r"^Contract\.Main\.(\d+)$", contract_id)
    if m and (serialized == 0 or serialized != int(m.group(1))):
        return int(m.group(1)), True
    return serialized, False


def sublevel_record(ue_path: str) -> dict:
    pkg = asset_pkg(ue_path)
    level = pkg.removeprefix("/Game/Maps/")
    res = f"res://data/generated/levels/{level}.tatlevel.json" if level else ""
    tat = ROOT / "game" / "data" / "generated" / "levels" / (level + ".tatlevel.json")
    return {
        "ue": ue_path,
        "level": level,
        "res": res,
        "exists": bool(level)
        and (ROOT / "extracted" / "json" / "Maps" / (level + ".json")).is_file(),
        "tatlevel_exists": tat.is_file(),
    }


def load_contracts(loc: LocTable, warnings: list[str]):
    if not CONTRACTS_TABLE.is_file():
        raise SystemExit(f"missing {rel(CONTRACTS_TABLE)}")
    data = load_json(CONTRACTS_TABLE)
    if not isinstance(data, list) or not data:
        raise SystemExit(f"{rel(CONTRACTS_TABLE)} is not a UE export list")
    rows = data[0].get("Rows") or {}
    out: dict[str, dict] = {}
    for contract_id, row in rows.items():
        row = row or {}
        serialized_order = int(row.get("ContractOrder") or 0)
        order, repaired = contract_order(contract_id, serialized_order)
        if repaired:
            warnings.append(
                f"{contract_id} has serialized ContractOrder {serialized_order}; "
                f"order repaired to {order} from the row key"
            )
        map_ue = str((row.get("Map") or {}).get("AssetPathName") or "")
        map_id = map_id_for_ue(map_ue) if map_ue else ""
        if not map_ue:
            warnings.append(
                f"{contract_id} has no Map; the tutorial map is selected by the runtime flow"
            )
        sublevels = [
            sublevel_record(str((s or {}).get("AssetPathName") or ""))
            for s in row.get("SublevelsToLoad") or []
        ]
        clues_ue = str((row.get("Clues") or {}).get("AssetPathName") or "")
        clues_json = ue_asset_to_json(clues_ue) if clues_ue else None
        intro = text_record(row.get("IntroEncounterText"), loc)
        outro = text_record(row.get("OutroEncounterText"), loc)
        out[contract_id] = {
            "id": contract_id,
            "order": order,
            "order_serialized": serialized_order,
            "map_id": map_id,
            "map_ue": map_ue,
            "map_level": (
                asset_pkg(map_ue)[len("/Game/Maps/") :]
                if map_ue.startswith("/Game/Maps/")
                else ""
            ),
            "sublevels": sublevels,
            "clues_ue": clues_ue,
            "clues_name": asset_stem(clues_ue) if clues_ue else "",
            "clues_exists": clues_json is not None,
            "objective": objective_record(row.get("objective"), loc),
            "title": ttext(row.get("Title"), loc),
            "description": ttext(row.get("Description"), loc),
            "intro_text": intro["text"],
            "outro_text": outro["text"],
            "next_contract_in_chain": tag_of(row.get("NextContractInChain")),
            "outro_flow": str(row.get("OutroFlow") or ""),
            "rewards": rewards(row.get("Rewards")),
            "source_table": rel(CONTRACTS_TABLE),
            "source_row": contract_id,
        }
    return dict(sorted(out.items(), key=lambda kv: (kv[1]["order"], kv[0])))


def load_missions(loc: LocTable, warnings: list[str]):
    if not MISSIONS_TABLE.is_file():
        raise SystemExit(f"missing {rel(MISSIONS_TABLE)}")
    data = load_json(MISSIONS_TABLE)
    if not isinstance(data, list) or not data:
        raise SystemExit(f"{rel(MISSIONS_TABLE)} is not a UE export list")
    rows = data[0].get("Rows") or {}
    out: dict[str, dict] = {}
    for mission_id, row in rows.items():
        row = row or {}
        graph_ue = str((row.get("QuestGraph") or {}).get("AssetPathName") or "")
        graph_json = ue_asset_to_json(graph_ue) if graph_ue else None
        map_id = map_id_for_ue(graph_ue) if graph_ue else ""
        if not graph_ue:
            warnings.append(f"{mission_id} has no QuestGraph (example/template row)")
        success = text_record(row.get("PostMatchSuccessText"), loc)
        failure = text_record(row.get("PostMatchFailureText"), loc)
        out[mission_id] = {
            "id": mission_id,
            "map_id": map_id,
            "quest_graph_ue": graph_ue,
            "quest_graph": asset_stem(graph_ue) if graph_ue else "",
            "quest_graph_exists": graph_json is not None,
            "durations": durations(row),
            "title": ttext(row.get("Title"), loc),
            "description": ttext(row.get("Description"), loc),
            "post_match_success": success["text"],
            "post_match_failure": failure["text"],
            "rewards": rewards(row.get("Rewards")),
            "bonus_rewards": row.get("BonusRewards") or [],
            "source_table": rel(MISSIONS_TABLE),
            "source_row": mission_id,
        }
    return out


def load_loot_quest(loc: LocTable, warnings: list[str]):
    if not LOOT_TABLE.is_file():
        raise SystemExit(f"missing {rel(LOOT_TABLE)}")
    data = load_json(LOOT_TABLE)
    if not isinstance(data, list) or not data:
        raise SystemExit(f"{rel(LOOT_TABLE)} is not a UE export list")
    rows = data[0].get("Rows") or {}
    out: dict[str, dict] = {}
    by_tag: dict[str, list[str]] = defaultdict(list)
    for row, spec in rows.items():
        spec = spec or {}
        loot_tag = tag_of((spec.get("LootIdentifier") or {}).get("LootTag"))
        display = text_record(spec.get("DisplayName"), loc)
        actor_ue = str((spec.get("ActorClass") or {}).get("AssetPathName") or "")
        actor_json = ue_asset_to_json(actor_ue) if actor_ue else None
        rec = {
            "row": row,
            "loot_tag": loot_tag,
            "display_name": display["text"],
            "display_name_key": display["key"],
            "display_name_table": display["table"],
            "display_name_namespace": display["namespace"],
            "display_name_present": display["present"],
            "value": int(spec.get("Value") or 0),
            "quest_location_tag": tag_of(spec.get("QuestLocationTag")),
            "loot_type": str(spec.get("lootType") or ""),
            "is_quest_related": spec.get("IsQuestRelated"),
            "auto_convert_to_money": spec.get("AutoConvertToMoney"),
            "is_large_carry": spec.get("IsLargeCarry"),
            "clue_set_ue": str((spec.get("ClueSet") or {}).get("AssetPathName") or ""),
            "actor_class": class_name(actor_ue),
            "actor_class_ue": actor_ue,
            "actor_class_json": rel(actor_json) if actor_json else "",
            "actor_class_exists": actor_json is not None,
            "source_table": rel(LOOT_TABLE),
            "source_row": row,
        }
        out[row] = rec
        if loot_tag:
            by_tag[loot_tag].append(row)
    for loot_tag, row_names in sorted(by_tag.items()):
        if len(row_names) > 1:
            warnings.append(
                f"DT_LootInfo_Quest has {len(row_names)} rows for loot tag {loot_tag}: "
                + ", ".join(row_names)
            )
    return dict(sorted(out.items())), by_tag


def map_items(value):
    """Yield (key, value) from a serialized TMap (dict or [{Key,Value}])."""
    if isinstance(value, dict):
        yield from value.items()
    elif isinstance(value, list):
        for entry in value:
            if isinstance(entry, dict):
                yield entry.get("Key"), entry.get("Value")
            elif isinstance(entry, (list, tuple)) and len(entry) == 2:
                yield entry[0], entry[1]


def parse_edge_map(records: list[dict]) -> dict[str, dict]:
    return {
        str(o.get("Name") or ""): o
        for o in records
        if o.get("Type") == "TATQuestGraphEdge" and o.get("Name")
    }


def graph_name_for_file(path: Path, records: list[dict]) -> str:
    for obj in records:
        if obj.get("Type") in ("TATQuestGraph", "TATQuestGraphModule"):
            name = obj.get("Name")
            if isinstance(name, str) and name:
                return name
    for obj in records:
        props = obj.get("Properties") or {}
        graph_ref = (props.get("Graph") or {}).get("ObjectName", "")
        iq = inside_quotes(graph_ref)
        if iq:
            return iq.rsplit(".", 1)[-1]
    return path.stem


def node_edges(props: dict, edge_by_name: dict[str, dict]) -> list[dict]:
    out: list[dict] = []
    raw = props.get("Edges") or []
    items = raw.items() if isinstance(raw, dict) else enumerate(raw)
    for _, item in items:
        if not isinstance(item, dict):
            continue
        key = item.get("Key")
        edge_name = ref_name(item.get("Value") or {})
        edge_obj = edge_by_name.get(edge_name) or {}
        edge_props = edge_obj.get("Properties") or {}
        source = ref_name(edge_props.get("StartNode") or {})
        target = ref_name(edge_props.get("EndNode") or {})
        if not target and isinstance(key, str):
            target = ref_name({"ObjectName": key})
        out.append(
            {
                "name": edge_name,
                "source": source,
                "target": target,
                "always_take_path_if_conditions_match": (
                    edge_props.get("AlwaysTakePathIfConditionsMatch")
                    if "AlwaysTakePathIfConditionsMatch" in edge_props
                    else None
                ),
                "chance_to_take_path": (
                    edge_props.get("ChanceToTakePath")
                    if "ChanceToTakePath" in edge_props
                    else None
                ),
                "quest_tag_query": edge_props.get("QuestTagQuery"),
                "world_tag_query": edge_props.get("WorldTagQuery"),
            }
        )
    return out


def parse_graph(path: Path, loc: LocTable, warnings: list[str]) -> dict:
    records = list_records(load_json(path))
    graph_obj = next(
        (
            o
            for o in records
            if o.get("Type") in ("TATQuestGraph", "TATQuestGraphModule")
        ),
        None,
    )
    name = graph_name_for_file(path, records)
    edge_by_name = parse_edge_map(records)
    node_objs = [
        o
        for o in records
        if str(o.get("Type") or "").startswith("TATQuestGraph")
        and o.get("Type")
        not in ("TATQuestGraph", "TATQuestGraphModule", "TATQuestGraphEdge")
    ]
    nodes: dict[str, dict] = {}
    for obj in node_objs:
        props = obj.get("Properties") or {}
        node = {
            "name": str(obj.get("Name") or ""),
            "type": str(obj.get("Type") or ""),
            "node_id": str(props.get("NodeId") or ""),
            "parents": [ref_name(x) for x in props.get("ParentNodes") or []],
            "children": [ref_name(x) for x in props.get("ChildrenNodes") or []],
            "edges": node_edges(props, edge_by_name),
        }
        ntype = node["type"]
        if ntype == "TATQuestGraphObjectiveNode":
            node["objective"] = objective_record(props.get("objective"), loc)
            display = (props.get("DisplayImage") or {}).get("AssetPathName", "")
            node["display_image_ue"] = str(display)
            for field in node["objective"]["unknown_fields"]:
                warnings.append(
                    f"{name}:{node['name']} has unknown objective field {field}"
                )
        elif ntype == "TATQuestGraphPropertyNode":
            ptype = str(props.get("PropertyType") or "")
            node["property_type"] = ptype.split("::")[-1] if ptype else ""
            node["endgame_duration"] = (
                float(props.get("EndgameDuration"))
                if props.get("EndgameDuration") is not None
                else None
            )
            node["duration"] = (
                float(props.get("duration"))
                if props.get("duration") is not None
                else None
            )
        elif ntype == "TATQuestGraphSceneVariantNode":
            variants = []
            for entry in props.get("SceneVariants") or []:
                if not isinstance(entry, dict):
                    continue
                sv = entry.get("SceneVariant") or {}
                variants.append(
                    {
                        "scene_variant": asset_stem(sv.get("ObjectName", "")),
                        "scene_variant_ue": inside_quotes(sv.get("ObjectName", "")),
                        "weight": entry.get("Weight"),
                    }
                )
            node["scene_variants"] = variants
        elif ntype == "TATQuestGraphClueSetNode":
            cs = props.get("ClueSet") or {}
            cs_ue = str(cs.get("AssetPathName") or "")
            node["clue_set_ue"] = cs_ue
            node["clue_set"] = asset_stem(cs_ue) if cs_ue else ""
            node["clue_set_exists"] = (
                ue_asset_to_json(cs_ue) is not None if cs_ue else False
            )
        elif ntype == "TATQuestGraphClueSetForSpawnNode":
            cs = props.get("ClueSet") or {}
            cs_ue = str(cs.get("AssetPathName") or "")
            node["loot_tag"] = tag_of(props.get("LootTag"))
            node["clue_set_ue"] = cs_ue
            node["clue_set"] = asset_stem(cs_ue) if cs_ue else ""
            node["clue_set_exists"] = (
                ue_asset_to_json(cs_ue) is not None if cs_ue else False
            )
        elif ntype == "TATQuestGraphSubgraphNode":
            module_ref = props.get("Module") or {}
            module_ue = asset_pkg(
                module_ref.get("ObjectPath") or module_ref.get("ObjectName") or ""
            )
            if not module_ue:
                module_ue = inside_quotes(module_ref.get("ObjectName", ""))
            node["module_ue"] = module_ue
            node["module"] = asset_stem(module_ue) if module_ue else ""
            node["module_exists"] = (
                ue_asset_to_json(module_ue) is not None if module_ue else False
            )
        elif ntype == "TATQuestGraphTextReplacementNode":
            params = {}
            for key, value in map_items(props.get("FormatParams")):
                if isinstance(key, str):
                    params[key] = ttext(value, loc)
            node["format_params"] = params
        elif ntype == "TATQuestGraphTagNode":
            node["tag_weights"] = [
                {"tag": tag_of(x.get("Tag")), "weight": x.get("Weight")}
                for x in props.get("TagWeights") or []
                if isinstance(x, dict)
            ]
        elif ntype == "TATQuestGraphLockCombinationNode":
            node["lock_combinations"] = sorted(
                str(k)
                for k, _ in map_items(props.get("LockCombinations"))
                if k is not None
            )
            node["lock_combination_count"] = len(node["lock_combinations"])
        elif ntype == "TATQuestGraphRootNode":
            node["enabled"] = props.get("Enabled") if "Enabled" in props else None
        if props.get("SelectCount") is not None:
            node["select_count"] = props.get("SelectCount")
        nodes[node["name"]] = node

    declared_roots: list[str] = []
    if graph_obj is not None and graph_obj.get("Type") == "TATQuestGraph":
        declared_roots = [
            ref_name(x)
            for x in (graph_obj.get("Properties") or {}).get("RootNodes") or []
        ]
    roots = [n["name"] for n in nodes.values() if n["type"] == "TATQuestGraphRootNode"]
    root_source = "TATQuestGraphRootNode"
    if not roots:
        roots = [n["name"] for n in nodes.values() if not n["parents"]]
        root_source = "nodes_without_parents"
        warnings.append(
            f"{name} has no TATQuestGraphRootNode; using parentless nodes as roots"
        )

    seen: set[str] = set()
    stack = list(roots)
    while stack:
        node_name = stack.pop()
        if node_name in seen or node_name not in nodes:
            continue
        seen.add(node_name)
        node = nodes[node_name]
        stack.extend(node["children"])
        stack.extend(edge["target"] for edge in node["edges"] if edge["target"])

    for node_name, node in nodes.items():
        node["reachable"] = node_name in seen

    reachable = [n for n in nodes if nodes[n]["reachable"]]
    dead = [n for n in nodes if not nodes[n]["reachable"]]

    not_roots = [n for n in declared_roots if n not in roots and n in nodes]
    if not_roots:
        warnings.append(
            f"{name}: RootNodes contains non-root nodes that are not execution roots: "
            + ", ".join(not_roots)
        )

    return {
        "name": name,
        "asset": json_to_ue_asset(path),
        "kind": (
            "quest_graph"
            if (graph_obj or {}).get("Type") == "TATQuestGraph"
            else "module"
        ),
        "source_file": rel(path),
        "roots": roots,
        "root_source": root_source,
        "declared_roots": declared_roots,
        "nodes": nodes,
        "reachable_nodes": reachable,
        "dead_nodes": dead,
        "counts": {"nodes": len(nodes), "reachable": len(reachable), "dead": len(dead)},
        "missions": [],
        "durations": [],
    }


def load_quest_graphs(loc: LocTable, warnings: list[str]) -> dict[str, dict]:
    paths = sorted(
        Path(p) for p in glob.glob(str(EX / "**" / "QG_*.json"), recursive=True)
    )
    graphs: dict[str, dict] = {}
    for path in paths:
        entry = parse_graph(path, loc, warnings)
        if entry["name"] in graphs:
            warnings.append(
                f"duplicate quest graph name {entry['name']}: {rel(path)} and {graphs[entry['name']]['source_file']}"
            )
            continue
        graphs[entry["name"]] = entry
    return dict(sorted(graphs.items()))


def link_missions_and_graphs(
    missions: dict[str, dict], graphs: dict[str, dict]
) -> None:
    for mission_id, mission in missions.items():
        graph_name = mission["quest_graph"]
        if not graph_name or graph_name not in graphs:
            continue
        graphs[graph_name]["missions"].append(mission_id)
        if not graphs[graph_name]["durations"]:
            graphs[graph_name]["durations"] = mission["durations"]
    for entry in graphs.values():
        entry["missions"].sort()


def load_text_replacement() -> dict[str, dict]:
    if not TEXT_REPLACEMENT.is_file():
        return {}
    data = load_json(TEXT_REPLACEMENT)
    if not isinstance(data, list) or not data:
        return {}
    table = data[0].get("StringTable") or {}
    out = {}
    for key, value in (table.get("KeysToEntries") or {}).items():
        out[key] = {
            "key": key,
            "text": value,
            "table_name": "St_Clues_TextReplacement",
            "source_file": rel(TEXT_REPLACEMENT),
        }
    return dict(sorted(out.items()))


def load_quest_spawners(loc: LocTable) -> tuple[list[dict], dict]:
    """Return spawner records, {map_id: {tag: [records]}} and level info."""
    records: list[dict] = []
    for path in sorted(
        Path(p) for p in glob.glob(str(MAPS / "**" / "*.json"), recursive=True)
    ):
        if path.name.startswith("QG_"):
            continue
        data = load_json(path)
        rows = list_records(data)
        if not rows:
            continue
        by_name = {o.get("Name"): o for o in rows if isinstance(o.get("Name"), str)}
        level = level_rel(path)
        map_id = map_id_for_folder(level.split("/", 1)[0])
        for obj in rows:
            if obj.get("Type") != "TATQuestActorSpawnerComponent":
                continue
            props = obj.get("Properties") or {}
            outer = inside_quotes((obj.get("Outer") or {}).get("ObjectName", ""))
            actor_name = outer.rsplit(".", 1)[-1] if outer else ""
            owner = by_name.get(actor_name) or {}
            actions = []
            for action in props.get("_spawnActions") or []:
                if not isinstance(action, dict):
                    continue
                actions.append(
                    {
                        "clue_fact_tag": tag_of(action.get("ClueFactTag")),
                        "indicator_class": class_name(
                            (action.get("SpawnIndicatorClass") or {}).get(
                                "ObjectName", ""
                            )
                        ),
                        "optional_location_proxy": str(
                            (action.get("OptionalLocationProxy") or {}).get(
                                "AssetPathName"
                            )
                            or ""
                        ),
                    }
                )
            rec = {
                "map_id": map_id,
                "level": level,
                "actor": actor_name,
                "actor_class": str(owner.get("Type") or ""),
                "actor_label": str(owner.get("ActorLabel") or ""),
                "component": str(obj.get("Name") or ""),
                "quest_location_tag": tag_of(props.get("_questLocationTag")),
                "clue_location_tag": tag_of(props.get("_clueLocationTag")),
                "clue_location_text": ttext(props.get("_clueLocationText"), loc),
                "spawn_actions": actions,
                "spawn_action_tags": [
                    a["clue_fact_tag"] for a in actions if a["clue_fact_tag"]
                ],
                "source_file": rel(path),
            }
            records.append(rec)
    records.sort(key=lambda r: (r["map_id"], r["level"], r["actor"], r["component"]))
    by_map_tag: dict[str, dict[str, list[dict]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for rec in records:
        if rec["quest_location_tag"]:
            by_map_tag[rec["map_id"]][rec["quest_location_tag"]].append(
                {
                    "level": rec["level"],
                    "actor": rec["actor"],
                    "component": rec["component"],
                    "clue_location_text": rec["clue_location_text"],
                    "spawn_action_tags": rec["spawn_action_tags"],
                }
            )
    nested = {
        map_id: {
            tag: sorted(items, key=lambda x: (x["level"], x["actor"]))
            for tag, items in sorted(tags.items())
        }
        for map_id, tags in sorted(by_map_tag.items())
    }
    return records, nested


def load_readable_by_level() -> dict[str, Counter]:
    """level -> Counter(placement_tag) for every TATReadableClueSpawner."""
    out: dict[str, Counter] = defaultdict(Counter)
    for path in sorted(
        Path(p) for p in glob.glob(str(MAPS / "**" / "*.json"), recursive=True)
    ):
        if path.name.startswith("QG_"):
            continue
        data = load_json(path)
        rows = list_records(data)
        if not rows:
            continue
        level = level_rel(path)
        for obj in rows:
            if obj.get("Type") != "TATReadableClueSpawner":
                continue
            tag = tag_of((obj.get("Properties") or {}).get("PlacementTag"))
            if tag:
                out[level][tag] += 1
    return out


def persistent_map_path(map_id: str) -> Path | None:
    folder = {
        "guildhall": "Guildhall/Guildhall_P",
        "old_manor": "OldManor/OldManor_P",
        "ftue": "FTUE/FTUE_P",
        "thieves_den": "ThievesDenTest/ThievesDenTest_P",
    }.get(map_id)
    if folder:
        p = MAPS / (folder + ".json")
        return p if p.is_file() else None
    return None


def always_loaded_levels(map_path: Path | None) -> set[str]:
    if map_path is None:
        return set()
    data = load_json(map_path)
    levels = {level_rel(map_path)}
    for obj in list_records(data):
        if obj.get("Type") != "LevelStreamingAlwaysLoaded":
            continue
        world = (obj.get("Properties") or {}).get("WorldAsset") or {}
        pkg = asset_pkg(world.get("AssetPathName", ""))
        if pkg.startswith("/Game/Maps/"):
            levels.add(pkg[len("/Game/Maps/") :])
    return levels


def contract_levels(contract: dict) -> set[str]:
    map_ue = contract["map_ue"]
    if not map_ue:
        return set()
    map_path = ue_asset_to_json(map_ue)
    levels = always_loaded_levels(map_path)
    if map_path is not None:
        levels.add(level_rel(map_path))
    for sub in contract["sublevels"]:
        if sub["level"]:
            levels.add(sub["level"])
    return levels


def mission_levels(map_id: str) -> set[str]:
    return always_loaded_levels(persistent_map_path(map_id))


def normalize_tag(tag: str) -> list[str]:
    return [p for p in tag.split(".") if p not in ("Common", "Locations")]


def resolve_demand(demand: str, available: Counter, needed: int):
    """Resolve a placement tag against available spawner tags.

    Rules, in order: exact, normalised equal (Locations/Common removed),
    namespace alias (one differing map token), then parent prefix.  Returns
    (matched_tags, count, rule) or (None, 0, "").
    """
    if available.get(demand, 0) >= needed:
        return [demand], available[demand], "exact"
    nd = normalize_tag(demand)
    same: list[str] = []
    alias: list[str] = []
    prefix: list[str] = []
    for tag in available:
        nt = normalize_tag(tag)
        if nt == nd:
            same.append(tag)
        elif (
            len(nt) == len(nd)
            and len(nt) >= 2
            and nt[0] == nd[0]
            and nt[1] != nd[1]
            and nt[2:] == nd[2:]
        ):
            # Same tag path under a different map namespace: the shipped
            # Contract 10 clue names Guildhall but lives in OldManor.
            alias.append(tag)
        elif len(nd) < len(nt) and nt[: len(nd)] == nd:
            prefix.append(tag)
    for rule, tags in (
        ("normalized", same),
        ("namespace_alias", alias),
        ("parent_prefix", prefix),
    ):
        total = sum(available[t] for t in tags)
        if total >= needed:
            return sorted(tags), total, rule
    return None, 0, ""


def graph_reachable_clue_sets(graph_name: str, graphs: dict[str, dict]) -> list[dict]:
    """Reachable clue-set references, following subgraph modules recursively."""
    out: list[dict] = []
    visited_graphs: set[str] = set()

    def walk(name: str) -> None:
        if name in visited_graphs:
            return
        visited_graphs.add(name)
        entry = graphs.get(name)
        if entry is None:
            return
        for node_name in entry["reachable_nodes"]:
            node = entry["nodes"][node_name]
            if node.get("clue_set"):
                out.append(
                    {
                        "graph": name,
                        "node": node_name,
                        "clue_set": node["clue_set"],
                        "clue_set_ue": node.get("clue_set_ue", ""),
                    }
                )
            if node.get("module"):
                walk(node["module"])

    walk(graph_name)
    return out


def load_clue_sets_for_validation() -> dict[str, dict]:
    sets: dict[str, dict] = {}
    for path in sorted(
        Path(p) for p in glob.glob(str(EX / "**" / "CLS_*.json"), recursive=True)
    ):
        data = load_json(path)
        rows = list_records(data)
        if not rows:
            continue
        obj = rows[0]
        if obj.get("Type") not in ("TATClueSet", "TATCompoundClueSet"):
            continue
        name = obj.get("Name")
        if not isinstance(name, str):
            continue
        demand: Counter = Counter()
        for entry in (obj.get("Properties") or {}).get("Clues") or []:
            if not entry.get("Enabled"):
                continue
            clue = entry.get("Clue") or {}
            tag = tag_of(clue.get("PlacementTag"))
            if tag:
                demand[tag] += 1
        sets[name] = {"name": name, "source_file": rel(path), "demand": demand}
    return sets


def validate(
    contracts: dict[str, dict],
    missions: dict[str, dict],
    graphs: dict[str, dict],
    loot_rows: dict[str, dict],
    loot_by_tag: dict[str, list[str]],
    spawn_locations: dict,
    readable_by_level: dict[str, Counter],
    clue_sets: dict[str, dict],
    warnings: list[str],
) -> dict:
    checks: list[dict] = []

    # 1. Contract / mission / module / clue-set references exist.
    failures: list[str] = []
    checked = 0
    for contract in contracts.values():
        if not contract["clues_ue"]:
            continue
        checked += 1
        if not contract["clues_exists"]:
            failures.append(
                f"{contract['id']} references missing CLS {contract['clues_ue']}"
            )
    for graph in graphs.values():
        for node in graph["nodes"].values():
            if node.get("clue_set_ue"):
                checked += 1
                if not node.get("clue_set_exists"):
                    failures.append(
                        f"{graph['name']}:{node['name']} references missing CLS {node['clue_set_ue']}"
                    )
            if node.get("module_ue"):
                checked += 1
                if not node.get("module_exists"):
                    failures.append(
                        f"{graph['name']}:{node['name']} references missing QG {node['module_ue']}"
                    )
    for mission in missions.values():
        if not mission["quest_graph_ue"]:
            continue
        checked += 1
        if not mission["quest_graph_exists"]:
            failures.append(
                f"{mission['id']} references missing QG {mission['quest_graph_ue']}"
            )
    checks.append(
        {
            "name": "referenced_cls_qg_exist",
            "ok": not failures,
            "checked": checked,
            "failures": failures,
        }
    )

    # 2. Every objective Item / ItemsToSteal LootTag has a loot row.
    failures = []
    checked = 0
    missing_tags: Counter = Counter()
    for contract in contracts.values():
        for item in contract["objective"]["items"]:
            checked += 1
            if item["loot_tag"] not in loot_by_tag:
                missing_tags[item["loot_tag"]] += 1
                failures.append(
                    f"{contract['id']} objective loot tag {item['loot_tag']} has no DT_LootInfo_Quest row"
                )
    for graph in graphs.values():
        for node in graph["nodes"].values():
            if node["type"] != "TATQuestGraphObjectiveNode":
                continue
            for item in node["objective"]["items"]:
                checked += 1
                if item["loot_tag"] not in loot_by_tag:
                    missing_tags[item["loot_tag"]] += 1
                    failures.append(
                        f"{graph['name']}:{node['name']} loot tag {item['loot_tag']} has no DT_LootInfo_Quest row"
                    )
    checks.append(
        {
            "name": "objective_loot_tags_have_rows",
            "ok": not failures,
            "checked": checked,
            "failures": failures,
        }
    )

    # 3. Every quest location tag has >= 1 spawner on its map.
    failures = []
    checked = 0
    missing_locations: Counter = Counter()
    for contract in contracts.values():
        tags = []
        objective = contract["objective"]
        tags.extend(item["quest_spawn_location"] for item in objective["items"])
        if objective.get("quest_spawn_location"):
            tags.append(objective["quest_spawn_location"])
        for tag in tags:
            if not tag or tag == "None":
                continue
            checked += 1
            map_id = contract["map_id"]
            if not map_id:
                warnings.append(
                    f"{contract['id']} quest location {tag} cannot be map-scoped (contract has no Map)"
                )
                continue
            if not spawn_locations.get(map_id, {}).get(tag):
                missing_locations[(map_id, tag)] += 1
                failures.append(
                    f"{contract['id']} quest location {tag} has no quest spawner on {map_id}"
                )
    for graph in graphs.values():
        map_id = map_id_for_ue(graph["asset"])
        for node in graph["nodes"].values():
            if node["type"] != "TATQuestGraphObjectiveNode":
                continue
            objective = node["objective"]
            tags = [item["quest_spawn_location"] for item in objective["items"]]
            if objective.get("quest_spawn_location"):
                tags.append(objective["quest_spawn_location"])
            for tag in tags:
                if not tag or tag == "None":
                    continue
                checked += 1
                if not map_id:
                    warnings.append(
                        f"{graph['name']}:{node['name']} quest location {tag} cannot be map-scoped"
                    )
                    continue
                if not spawn_locations.get(map_id, {}).get(tag):
                    missing_locations[(map_id, tag)] += 1
                    failures.append(
                        f"{graph['name']}:{node['name']} quest location {tag} has no quest spawner on {map_id}"
                    )
    checks.append(
        {
            "name": "quest_location_tags_have_spawners",
            "ok": not failures,
            "checked": checked,
            "failures": failures,
        }
    )

    # 4. Every enabled CLS placement tag has enough readable spawners in the
    #    mission's loaded levels.
    failures = []
    checked = 0
    aliases: list[str] = []
    for contract in contracts.values():
        if not contract["clues_ue"] or not contract["clues_exists"]:
            continue
        set_name = contract["clues_name"]
        entry = clue_sets.get(set_name)
        if entry is None:
            continue
        levels = contract_levels(contract)
        available = Counter()
        for level in levels:
            available.update(readable_by_level.get(level, Counter()))
        for demand_tag, needed in sorted(entry["demand"].items()):
            checked += 1
            matched, total, rule = resolve_demand(demand_tag, available, needed)
            if not matched:
                failures.append(
                    f"{contract['id']} / {set_name}: {demand_tag} needs {needed} spawner(s), none in "
                    + ", ".join(sorted(levels))
                )
            elif rule != "exact":
                aliases.append(
                    f"{contract['id']} / {set_name}: {demand_tag} -> {', '.join(matched)} ({rule}, {total} available)"
                )
    for mission in missions.values():
        graph_name = mission["quest_graph"]
        if not graph_name or graph_name not in graphs:
            continue
        levels = mission_levels(mission["map_id"])
        if not levels:
            warnings.append(
                f"{mission['id']} ({mission['map_id']}) has no loaded map levels; "
                "CLS placement validation skipped"
            )
            continue
        available = Counter()
        for level in levels:
            available.update(readable_by_level.get(level, Counter()))
        for ref in graph_reachable_clue_sets(graph_name, graphs):
            set_name = ref["clue_set"]
            entry = clue_sets.get(set_name)
            if entry is None:
                failures.append(
                    f"{mission['id']} / {ref['graph']}:{ref['node']} references unknown CLS {set_name}"
                )
                continue
            for demand_tag, needed in sorted(entry["demand"].items()):
                checked += 1
                matched, total, rule = resolve_demand(demand_tag, available, needed)
                if not matched:
                    failures.append(
                        f"{mission['id']} / {set_name}: {demand_tag} needs {needed} spawner(s), none in "
                        + ", ".join(sorted(levels))
                    )
                elif rule != "exact":
                    aliases.append(
                        f"{mission['id']} / {set_name}: {demand_tag} -> {', '.join(matched)} ({rule}, {total} available)"
                    )
    for alias in sorted(set(aliases)):
        warnings.append("placement tag canonicalised: " + alias)
    checks.append(
        {
            "name": "cls_placement_tags_have_spawners",
            "ok": not failures,
            "checked": checked,
            "failures": failures,
        }
    )

    all_failures = [f for check in checks for f in check["failures"]]
    return {
        "ok": not all_failures,
        "checks": checks,
        "failures": all_failures,
    }


def main() -> None:
    warnings: list[str] = []
    loc = LocTable()
    contracts = load_contracts(loc, warnings)
    missions = load_missions(loc, warnings)
    graphs = load_quest_graphs(loc, warnings)
    link_missions_and_graphs(missions, graphs)
    loot_rows, loot_by_tag = load_loot_quest(loc, warnings)
    text_replacement = load_text_replacement()
    quest_spawners, spawn_locations = load_quest_spawners(loc)
    readable_by_level = load_readable_by_level()
    clue_sets = load_clue_sets_for_validation()
    validation = validate(
        contracts,
        missions,
        graphs,
        loot_rows,
        loot_by_tag,
        spawn_locations,
        readable_by_level,
        clue_sets,
        warnings,
    )

    # Diagnostic: loot rows whose QuestLocationTag has no quest spawner.  These
    # are ambient loot locations (Shop/HighStreet/...) and free-play drop tags,
    # not objective spawn requests, so they are reported, not failed.
    for row in loot_rows.values():
        tag = row["quest_location_tag"]
        if not tag or tag == "None":
            continue
        if not any(tag in tags for tags in spawn_locations.values()):
            warnings.append(
                f"loot row {row['row']} QuestLocationTag {tag} has no quest spawner "
                "(ambient/free-play loot location)"
            )

    # Unknown/placeholder rows are authored test data; keep them visible.
    example_rows = sorted(r for r in loot_rows if r.startswith(("Example", "TEST")))
    if example_rows:
        warnings.append(
            "DT_LootInfo_Quest contains example/test rows: " + ", ".join(example_rows)
        )

    stats = {
        "contracts": len(contracts),
        "missions": len(missions),
        "quest_graphs": len(graphs),
        "quest_graph_nodes": sum(len(g["nodes"]) for g in graphs.values()),
        "reachable_quest_nodes": sum(
            len(g["reachable_nodes"]) for g in graphs.values()
        ),
        "dead_quest_nodes": sum(len(g["dead_nodes"]) for g in graphs.values()),
        "loot_quest_rows": len(loot_rows),
        "quest_spawners": len(quest_spawners),
        "quest_spawn_locations": sum(len(tags) for tags in spawn_locations.values()),
        "text_replacement_keys": len(text_replacement),
    }

    output = {
        "generated_by": "tools/parse_quests.py",
        "sources": {
            "contracts": rel(CONTRACTS_TABLE),
            "missions": rel(MISSIONS_TABLE),
            "loot": rel(LOOT_TABLE),
            "text_replacement": rel(TEXT_REPLACEMENT),
            "quest_graphs": sorted({g["source_file"] for g in graphs.values()}),
            "localization": rel(LOC_CSV),
        },
        "stats": stats,
        "contracts": contracts,
        "missions": missions,
        "quest_graphs": graphs,
        "loot_quest": loot_rows,
        "quest_spawn_locations": spawn_locations,
        "quest_spawners": quest_spawners,
        "text_replacement": text_replacement,
        "validation": validation,
        "warnings": sorted(set(warnings)),
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False, sort_keys=False)
        f.write("\n")

    print(
        "quests: "
        + ", ".join(f"{k}={v}" for k, v in stats.items())
        + f"; validation={'PASS' if validation['ok'] else 'FAIL'}"
        + f" -> {rel(OUT)}"
    )
    for check in validation["checks"]:
        print(
            f"  check {check['name']}: {'PASS' if check['ok'] else 'FAIL'}"
            f" ({check['checked']} checked, {len(check['failures'])} failure(s))"
        )
    for warning in sorted(set(warnings)):
        print(f"WARN: {warning}")
    for failure in validation["failures"]:
        print(f"FAIL: {failure}")
    if not validation["ok"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
