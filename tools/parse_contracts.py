#!/usr/bin/env python3
"""Build game/data/generated/gameplay/contracts.json from extracted UE tables.

Reads DT_Contracts_1_to_16.json (16 rows keyed Contract.Main.N) and the four
DT_Missions_*.json tables, and emits resolved contract -> map -> sublevel
data plus per-map match durations. No invented values: every entry carries
its source table path, and the Contract.Main.15 ContractOrder=0 bug in the
shipped table is repaired from the row key (documented below).

UE -> res:// mapping (same rule as tools/parse_tables.py: the `Maps/` prefix
is stripped):
    /Game/Maps/Guildhall/Guildhall_Contract_02.Guildhall_Contract_02
    -> res://data/generated/levels/Guildhall/Guildhall_Contract_02.tatlevel.json
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLES = ROOT / "game" / "data" / "generated" / "tables" / "Gameplay" / "Quests"
OUT = ROOT / "game" / "data" / "generated" / "gameplay" / "contracts.json"

CONTRACTS_TABLE = TABLES / "DT_Contracts_1_to_16.json"
CONTRACTS_FALLBACK = TABLES / "CDT_Contracts.json"

# Free-play Cleanout Heist loot thresholds: the QG authors one objective node
# per difficulty (TATQuestGraphObjectiveNode_21/22/23, Properties.objective
# .amount = 4000/6000/8000). Parsed into "mission_loot_goals" so the runtime
# accessor (GameData.get_mission_loot_goal) is data-driven; the loader keeps a
# documented static fallback for generated data that predates this key.
LOOT_GOAL_QUESTS = {
    "Mission.Guildhall.LootTheRoom": (
        ROOT
        / "extracted"
        / "json"
        / "Maps"
        / "Guildhall"
        / "QG_Guildhall_LootTheRoom.json"
    ),
}

# Canonical mission row per map: the Vault rows carry the shipped
# 7200/2700/1800 limits; the LootTheRoom rows are side-mission variants and
# are intentionally NOT used here.
MISSIONS = {
    "guildhall": (
        TABLES / "DT_Missions_Guildhall.json",
        "Mission.Guildhall.VaultHeist",
    ),
    "old_manor": (TABLES / "DT_Missions_OldManor.json", "Mission.OldManor.Vault"),
    "thieves_den": (
        TABLES / "DT_Missions_ThievesDen_Tutorial.json",
        "Mission.Tutorial.ThievesDen",
    ),
    "ftue": (TABLES / "DT_Missions_Tutorial.json", "Mission.Tutorial.Single"),
}


def ue_asset_to_res(asset_path: str) -> str:
    """Map a UE sublevel/persistent-map asset path to its .tatlevel.json."""
    p = (asset_path or "").strip()
    if not p:
        return ""
    # Keep the asset name before the '.' separator: '.../Foo.Foo' -> '.../Foo'.
    base = p.split(".")[0]
    prefix = "/Game/Maps/"
    if base.startswith(prefix):
        base = base[len(prefix) :]
    elif base.startswith("/Game/"):
        base = base[len("/Game/") :]
    return f"res://data/generated/levels/{base}.tatlevel.json"


def map_id_from_ue(map_path: str) -> str:
    mp = map_path or ""
    if "Guildhall" in mp:
        return "guildhall"
    if "OldManor" in mp:
        return "old_manor"
    if "ThievesDen" in mp:
        return "thieves_den"
    if "FTUE" in mp or "Tutorial" in mp:
        return "ftue"
    # P2-2: Contract 1 (Thieves' Den hub tutorial) ships with an empty Map
    # path; the runtime default for an empty path is the thieves_den hub.
    # Any other contract landing here is a data gap, not a hub — the caller
    # collects defaulted orders and warns so a future empty path cannot
    # silently become thieves_den.
    return "thieves_den"


def text_of(node) -> str:
    if isinstance(node, dict):
        for k in ("SourceString", "LocalizedString"):
            v = node.get(k)
            if isinstance(v, str) and v:
                return v
    return ""


def load_contract_rows() -> tuple[dict, str]:
    for cand in (CONTRACTS_TABLE, CONTRACTS_FALLBACK):
        if cand.exists():
            data = json.loads(cand.read_text())
            if isinstance(data, dict) and isinstance(data.get("rows"), dict):
                rel = str(cand.relative_to(ROOT))
                return data["rows"], rel
    raise FileNotFoundError("no contract table found")


def qg_loot_goals(path: Path) -> list[int]:
    """Difficulty ladder from a quest graph's objective node amounts.

    Nodes carry Properties.objective.amount; sort by the numeric N in
    TATQuestGraphObjectiveNode_N so the ladder follows authored node order
    (21/22/23 -> 4000/6000/8000) instead of JSON traversal order. Returns []
    when the capture is absent so `make normalize` still runs on a machine
    without extracted/ (the runtime fallback table covers it).
    """
    if not path.exists():
        print(f"WARN: quest graph missing, loot goals fall back at runtime: {path}")
        return []
    data = json.loads(path.read_text())
    found: list[tuple[int, int]] = []

    def walk(node) -> None:
        if isinstance(node, dict):
            if str(node.get("Type", "")) == "TATQuestGraphObjectiveNode":
                name = str(node.get("Name", ""))
                props = node.get("Properties") or {}
                objective = props.get("objective") if isinstance(props, dict) else {}
                amount = (
                    objective.get("amount") if isinstance(objective, dict) else None
                )
                m = re.search(r"_(\d+)$", name)
                if m and isinstance(amount, (int, float)) and int(amount) > 0:
                    found.append((int(m.group(1)), int(amount)))
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(data)
    return [amount for _, amount in sorted(set(found))]


def main() -> None:
    rows, source_rel = load_contract_rows()
    contracts = []
    defaulted_maps: list[str] = []
    for key, row in rows.items():
        if not isinstance(row, dict):
            continue
        m = re.fullmatch(r"Contract\.Main\.(\d+)", str(key))
        if not m:
            continue
        key_order = int(m.group(1))
        order = row.get("ContractOrder", 0)
        try:
            order = int(order)
        except (TypeError, ValueError):
            order = 0
        if order <= 0:
            # Shipped data bug: Contract.Main.15 carries ContractOrder 0.
            # Repair from the row key, which is authoritative (Contract.Main.N).
            order = key_order
        map_raw = row.get("Map") or {}
        map_ue = (
            str(map_raw.get("AssetPathName", "")) if isinstance(map_raw, dict) else ""
        )
        obj = row.get("objective") or {}
        loot_tag = ""
        loot_tags: list[str] = []
        if isinstance(obj, dict):
            item = obj.get("Item") or {}
            lt = item.get("LootTag") or {} if isinstance(item, dict) else {}
            loot_tag = str(lt.get("TagName", "")) if isinstance(lt, dict) else ""
            for entry in obj.get("ItemsToSteal") or []:
                if not isinstance(entry, dict):
                    continue
                it = entry.get("Item") or {}
                tag = (it.get("LootTag") or {}) if isinstance(it, dict) else {}
                name = str(tag.get("TagName", "")) if isinstance(tag, dict) else ""
                if name:
                    loot_tags.append(name)
            if not loot_tag and loot_tags:
                loot_tag = loot_tags[0]
        subs = []
        for entry in row.get("SublevelsToLoad") or []:
            if isinstance(entry, dict):
                ap = str(entry.get("AssetPathName", ""))
                if ap:
                    subs.append(ap)
        clues_raw = row.get("Clues") or {}
        clues_ue = (
            str(clues_raw.get("AssetPathName", ""))
            if isinstance(clues_raw, dict)
            else ""
        )
        title_raw = row.get("Title") or {}
        desc_raw = row.get("Description") or {}
        map_id = map_id_from_ue(map_ue)
        if not map_ue or (
            map_id == "thieves_den"
            and not any(s in map_ue for s in ("ThievesDen", "FTUE", "Tutorial"))
        ):
            defaulted_maps.append(f"{key} (order {order})")
        contracts.append(
            {
                "order": order,
                "id": str(key),
                "map_id": map_id,
                "map_ue_path": map_ue,
                "sublevels_ue_paths": subs,
                "sublevels_res_paths": [ue_asset_to_res(s) for s in subs],
                "loot_tag": loot_tag,
                "loot_tags": loot_tags,
                "clues_ue_path": clues_ue,
                "outro_flow": str(row.get("OutroFlow", "")),
                "intro_text": text_of(row.get("IntroEncounterText")),
                "outro_text": text_of(row.get("OutroEncounterText")),
                "title_text": text_of(title_raw),
                "description_text": text_of(desc_raw),
            }
        )
    contracts.sort(key=lambda c: c["order"])

    mission_durations: dict = {}
    for map_id, (path, row_key) in MISSIONS.items():
        data = json.loads(path.read_text())
        row = (data.get("rows") or {}).get(row_key, {})
        durations = [
            float(row.get("MatchDurationsByDifficulty", 0.0)),
            float(row.get("MatchDurationsByDifficulty[1]", 0.0)),
            float(row.get("MatchDurationsByDifficulty[2]", 0.0)),
        ]
        qg = row.get("QuestGraph") or {}
        mission_durations[map_id] = {
            "durations": durations,
            "quest_graph_ue_path": str(qg.get("AssetPathName", ""))
            if isinstance(qg, dict)
            else "",
            "title_text": text_of(row.get("Title")),
            "description_text": text_of(row.get("Description")),
            "source_table": str(path.relative_to(ROOT)),
            "source_row": row_key,
        }
    # TAT-2 expansion maps reuse the FTUE (zero-limit) timing: 0 = unlimited.
    for alias in ("jaspering", "jaspering_hall"):
        mission_durations[alias] = dict(mission_durations["ftue"])
        mission_durations[alias]["alias_of"] = "ftue"

    mission_loot_goals: dict = {}
    for mission_id, qg_path in LOOT_GOAL_QUESTS.items():
        goals = qg_loot_goals(qg_path)
        if len(goals) >= 3:
            mission_loot_goals[mission_id] = goals
        else:
            print(
                f"WARN: {mission_id} loot goal ladder incomplete ({goals}); runtime fallback applies"
            )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(
            {
                "source_table": source_rel,
                "contracts": contracts,
                "mission_durations": mission_durations,
                "mission_loot_goals": mission_loot_goals,
            },
            indent=2,
        )
        + "\n"
    )
    print(
        f"Wrote {len(contracts)} contracts + {len(mission_durations)} mission durations"
        f" + {len(mission_loot_goals)} loot goal ladders -> {OUT}"
    )
    # P2-2: every thieves_den default must be explainable. Today only
    # Contract.Main.1 (empty hub path) is expected; anything else is a gap.
    if defaulted_maps:
        print(
            f"WARN: {len(defaulted_maps)} contract(s) defaulted to thieves_den: "
            + ", ".join(defaulted_maps)
        )


if __name__ == "__main__":
    main()
