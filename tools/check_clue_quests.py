#!/usr/bin/env python3
"""Acceptance checks for the authored clue/quest data producers.

Reads the generated JSON only (no UE files) and asserts the facts that the
port's invented clue/quest text was replaced with shipped data.  Every check
is data-backed; failures exit 1.

Usage:
    python3 tools/check_clue_quests.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLUES = ROOT / "game" / "data" / "generated" / "gameplay" / "clues.json"
QUESTS = ROOT / "game" / "data" / "generated" / "gameplay" / "quests.json"

CONTRACT2_TABLE = "DT_ClueFacts_Contracts_02"
CONTRACT2_TEXTS = [
    "The files are somewhere on the second floor",
    "The files are on a desk in the bullpen",
    "The officer named Sgt. Campbell has a desk in the middle of the bullpen",
    "The Chief Constable has taken a personal interest in the theft of the Vistara Diamond.",
    "The Vistara Diamond was brought to Kilkairn by Mr. Hugh Montogomery, by irregular means.",
    "The files are on a constable's desk",
    "The Vistara files are being processed on the second floor.",
]
DEAD_FACTS = {
    "DT_ClueFacts_Contracts_10:Clue03",
    "DT_ClueFacts_Personal_Spider_01:Intro",
    "DT_ClueFacts_Personal_Spider_04:Renegade",
    "DT_ClueFacts_Quest_Guildhall:Chambers.Vault.Security",
    "DT_ClueFacts_Quest_Guildhall:Tower.VarA.Vault.Security",
    "DT_ClueFacts_Quest_Guildhall:Tower.VarB.Key",
}
FORBIDDEN_STRINGS = [
    "Sapphire of Edinburgh",
    "Ruby of Edinburgh",
    "Emerald of Edinburgh",
    "Relic Piece I",
    "Relic Piece II",
    "Relic Piece III",
    "Claymur Urn \u2014 North Wing",
    "Claymur Urn \u2014 Gallery",
    "Claymur Urn \u2014 Cellar",
    "Steal \u00a3",
]
SET_ITEMS = {
    "Loot.Quest.Set.GreenGem",
    "Loot.Quest.Set.OrangeGem",
    "Loot.Quest.Set.RedGem",
}
GEM_NAMES = {
    "GreenGem": "Gem of Arcana",
    "OrangeGem": "Gem of Strength",
    "RedGem": "Gem of Fire",
}


class Checker:
    def __init__(self) -> None:
        self.passed = 0
        self.failed: list[str] = []

    def check(self, name: str, condition: bool, detail: str = "") -> None:
        if condition:
            self.passed += 1
            print(f"PASS {name}")
        else:
            self.failed.append(name + (f": {detail}" if detail else ""))
            print(f"FAIL {name}" + (f": {detail}" if detail else ""))

    def equal(self, name: str, actual, expected) -> None:
        self.check(name, actual == expected, f"expected {expected!r}, got {actual!r}")


def walk_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from walk_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk_strings(item)


def reachable(graph: dict, node_name: str) -> bool:
    return node_name in graph.get("reachable_nodes", [])


def main() -> int:
    checker = Checker()
    if not CLUES.is_file() or not QUESTS.is_file():
        print(f"FAIL missing generated data: {CLUES} / {QUESTS}")
        return 1

    clues = json.loads(CLUES.read_text(encoding="utf-8"))
    quests = json.loads(QUESTS.read_text(encoding="utf-8"))
    facts = clues["facts"]
    stats = clues["stats"]
    qstats = quests["stats"]

    # ---------------------------------------------------------------- census
    checker.equal("clue fact tables == 22", stats["fact_tables"], 22)
    checker.equal("clue fact rows == 96", stats["fact_rows"], 96)
    checker.equal("reachable clue facts == 90", stats["reachable_facts"], 90)
    checker.equal("dead clue facts == 6", stats["dead_facts"], 6)
    checker.check(
        "exactly the six audited dead facts",
        set(clues.get("dead_fact_ids", [])) == DEAD_FACTS,
        f"extra={sorted(set(clues.get('dead_fact_ids', [])) - DEAD_FACTS)}, "
        f"missing={sorted(DEAD_FACTS - set(clues.get('dead_fact_ids', [])))}",
    )
    checker.check(
        "fact.reachable agrees with dead_fact_ids",
        all(f["reachable"] == (fid not in DEAD_FACTS) for fid, f in facts.items()),
    )
    checker.equal("suppressed clue facts == 0", stats["suppressed_facts"], 0)
    checker.equal("clue sets == 44", stats["clue_sets"], 44)
    checker.equal("readable clue spawners == 172", stats["readable_spawners"], 172)
    checker.equal("NPC clue components == 208", stats["npc_spawners"], 208)
    checker.equal("quest spawner components == 38", stats["quest_spawners"], 38)

    # ------------------------------------------------- Contract 2 clue facts
    contract2 = [f for f in facts.values() if f["table"] == CONTRACT2_TABLE]
    contract2.sort(key=lambda f: (f["display_priority"], f["row_index"]))
    checker.equal("Contract 2 has exactly 7 facts", len(contract2), 7)
    checker.equal(
        "Contract 2 priorities are three 1s and four 2s",
        [f["display_priority"] for f in contract2],
        [1, 1, 1, 2, 2, 2, 2],
    )
    checker.check(
        "Contract 2 facts are all category ClueFactCategory.Contract",
        all(f["category"] == "ClueFactCategory.Contract" for f in contract2),
    )
    checker.check(
        "Contract 2 facts have no suppressed_by",
        all(f["suppressed_by"] == [] for f in contract2),
    )
    checker.equal(
        "Contract 2 fact strings",
        [f["journal_text"] for f in contract2],
        CONTRACT2_TEXTS,
    )
    checker.check(
        "Contract 2 facts all have authored text",
        all(f["text_present"] for f in contract2),
    )

    # ------------------------------------------------------- CLS_Contract_02
    cls02 = clues["clue_sets"]["CLS_Contract_02"]
    checker.equal("CLS_Contract_02 enabled clues", cls02["counts"]["enabled"], 6)
    checker.equal("CLS_Contract_02 disabled clues", cls02["counts"]["disabled"], 0)
    checker.equal(
        "CLS_Contract_02 placement demand",
        cls02["placement_demand"],
        {
            "CluePlacement.Common.Guildhall.Contracts.Entrance": 1,
            "CluePlacement.Common.Guildhall.Contracts.FirstFloor": 3,
            "CluePlacement.Common.Guildhall.Contracts.SecondFloor": 2,
        },
    )
    checker.check(
        "CLS_Contract_02 is consumed by Contract.Main.2",
        {"kind": "contract", "id": "Contract.Main.2"} in cls02["consumers"],
    )
    guildhall_contracts = [
        r
        for r in clues["readable_spawners"]
        if r["level"] == "Guildhall/Guildhall_Contracts"
    ]
    checker.equal("Guildhall_Contracts readable spawners", len(guildhall_contracts), 28)

    # --------------------------------------------------- QG_Guildhall_Set
    graphs = quests["quest_graphs"]
    guildhall_set = graphs.get("QG_Guildhall_Set")
    checker.check("QG_Guildhall_Set exists", guildhall_set is not None)
    if guildhall_set:
        reachable_objectives = [
            n
            for n in guildhall_set["reachable_nodes"]
            if guildhall_set["nodes"][n]["type"] == "TATQuestGraphObjectiveNode"
        ]
        checker.equal(
            "Guildhall Set has exactly one reachable objective node",
            reachable_objectives,
            ["TATQuestGraphObjectiveNode_3"],
        )
        objective_node = guildhall_set["nodes"].get("TATQuestGraphObjectiveNode_3", {})
        objective = objective_node.get("objective", {})
        checker.equal(
            "Guildhall Set objective text",
            objective.get("objective_text"),
            "Steal the components of the Staff of Edinburgh",
        )
        items = {item["loot_tag"]: item for item in objective.get("items", [])}
        checker.equal("Guildhall Set loot tags", set(items), SET_ITEMS)
        checker.check(
            "Guildhall Set each item NumberToSpawn == 1",
            all(item.get("number_to_spawn") == 1 for item in items.values()),
        )
        checker.check(
            "Guildhall Set each item spawns at QuestLocation.Office",
            all(
                item.get("quest_spawn_location") == "QuestLocation.Office"
                for item in items.values()
            ),
        )
        checker.equal(
            "Guildhall Set MinNumberToSteal", objective.get("min_number_to_steal"), 1
        )
        checker.equal(
            "Guildhall Set OverrideMinNumberToSteal",
            objective.get("override_min_number_to_steal"),
            False,
        )
        endgame = [
            guildhall_set["nodes"][n].get("endgame_duration")
            for n in guildhall_set["reachable_nodes"]
            if guildhall_set["nodes"][n].get("property_type") == "EndgameDuration"
        ]
        checker.equal("Guildhall Set EndgameDuration", endgame, [480.0])
        checker.check(
            "Guildhall Set dead ObjectiveNode_2 is not reachable",
            not reachable(guildhall_set, "TATQuestGraphObjectiveNode_2")
            and "TATQuestGraphObjectiveNode_2" in guildhall_set["dead_nodes"],
        )

    # -------------------------------------------------------- gem loot names
    loot = quests["loot_quest"]
    for row, expected in GEM_NAMES.items():
        checker.equal(
            f"loot row {row} display name",
            loot.get(row, {}).get("display_name"),
            expected,
        )
    for loot_tag in SET_ITEMS:
        rows = [r for r in loot.values() if r.get("loot_tag") == loot_tag]
        checker.check(f"loot tag {loot_tag} has a quest loot row", len(rows) == 1)

    # --------------------------------------------- QG_Guildhall_LootTheRoom
    loot_room = graphs.get("QG_Guildhall_LootTheRoom")
    checker.check("QG_Guildhall_LootTheRoom exists", loot_room is not None)
    if loot_room:
        checker.equal(
            "LootTheRoom mission durations",
            loot_room.get("durations"),
            [3300.0, 1200.0, 1200.0],
        )
        amounts = sorted(
            loot_room["nodes"][n]["objective"].get("amount")
            for n in loot_room["reachable_nodes"]
            if loot_room["nodes"][n]["type"] == "TATQuestGraphObjectiveNode"
            and loot_room["nodes"][n]["objective"].get("amount") is not None
        )
        checker.equal(
            "LootTheRoom reachable loot thresholds", amounts, [4000, 6000, 8000]
        )
        main_phase = [
            loot_room["nodes"][n].get("duration")
            for n in loot_room["reachable_nodes"]
            if loot_room["nodes"][n].get("property_type") == "MatchMainPhaseDuration"
        ]
        checker.check(
            "LootTheRoom MatchMainPhaseDuration is 1320.0",
            bool(main_phase) and all(v == 1320.0 for v in main_phase),
            f"got {main_phase}",
        )
        endgame = [
            loot_room["nodes"][n].get("endgame_duration")
            for n in loot_room["reachable_nodes"]
            if loot_room["nodes"][n].get("property_type") == "EndgameDuration"
        ]
        checker.equal("LootTheRoom EndgameDuration", endgame, [480.0])
        checker.check(
            "LootTheRoom dead ObjectiveNode_20 and ClueSetNode_15 are not reachable",
            not reachable(loot_room, "TATQuestGraphObjectiveNode_20")
            and "TATQuestGraphObjectiveNode_20" in loot_room["dead_nodes"]
            and not reachable(loot_room, "TATQuestGraphClueSetNode_15")
            and "TATQuestGraphClueSetNode_15" in loot_room["dead_nodes"],
        )

    # ------------------------------------------------ producer validation
    checker.check(
        "clues.json validation ok",
        clues.get("validation", {}).get("ok") is True,
        str(clues.get("validation", {}).get("failures")),
    )
    checker.check(
        "quests.json validation ok",
        quests.get("validation", {}).get("ok") is True,
        str(quests.get("validation", {}).get("failures")),
    )
    checker.check(
        "quest validation checks all passed",
        all(c["ok"] for c in quests.get("validation", {}).get("checks", [])),
    )
    checker.equal("quest graphs == 18", qstats["quest_graphs"], 18)
    checker.equal("quest loot rows == 45", qstats["loot_quest_rows"], 45)
    checker.equal("quest spawners == 38", qstats["quest_spawners"], 38)

    # ------------------------------------------------- forbidden invented text
    forbidden_hits: list[str] = []
    for doc_name, doc in (("clues.json", clues), ("quests.json", quests)):
        for text in walk_strings(doc):
            for needle in FORBIDDEN_STRINGS:
                if needle in text:
                    forbidden_hits.append(f"{doc_name}: {needle!r} in {text[:120]!r}")
    checker.check(
        "no invented clue/quest strings remain",
        not forbidden_hits,
        "; ".join(forbidden_hits[:3]),
    )

    # ------------------------------------------------------------- summary
    print()
    if checker.failed:
        print(
            f"CLUE-QUEST CHECKER: FAIL ({checker.passed} passed, {len(checker.failed)} failed)"
        )
        for failure in checker.failed:
            print(f"  - {failure}")
        return 1
    print(f"CLUE-QUEST CHECKER: PASS ({checker.passed} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
