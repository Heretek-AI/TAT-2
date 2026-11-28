#!/usr/bin/env python3
"""Tests for tools/parse_contracts.py (stdlib only).

Run with: ``python3 tools/test_parse_contracts.py``

The Phase 3B.5 contract under test: ``Mission.Guildhall.LootTheRoom`` is a real
authored mission row (3300/1200/1200 s) and must be emitted as its own
``mission_durations`` entry, while the Guildhall map row keeps its shipped
7200/2700/1800 s contract window. A missing side row must not fabricate a
duration, and a missing canonical row must not inherit the side row.
"""

from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRODUCER = ROOT / "tools" / "parse_contracts.py"
REAL_GUILDHALL = (
    ROOT
    / "game"
    / "data"
    / "generated"
    / "tables"
    / "Gameplay"
    / "Quests"
    / "DT_Missions_Guildhall.json"
)

PASSED = 0


def check(condition: bool, name: str, detail: str = "") -> None:
    global PASSED
    if not condition:
        message = f"FAIL: {name}"
        if detail:
            message += f" ({detail})"
        print(message)
        raise SystemExit(1)
    PASSED += 1
    print(f"PASS: {name}")


def load_producer():
    spec = importlib.util.spec_from_file_location("parse_contracts_test", PRODUCER)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def mission_table(path: Path, rows: dict) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"rows": rows}))
    return path


def row(durations: list[float], qg: str = "") -> dict:
    return {
        "MatchDurationsByDifficulty": durations[0],
        "MatchDurationsByDifficulty[1]": durations[1],
        "MatchDurationsByDifficulty[2]": durations[2],
        "QuestGraph": {"AssetPathName": qg} if qg else {},
        "Title": {"SourceString": "fixture"},
        "Description": {"SourceString": "fixture"},
    }


def main() -> None:
    mod = load_producer()
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        tables = tmp_path / "tables"
        guildhall = mission_table(
            tables / "DT_Missions_Guildhall.json",
            {
                "Mission.Guildhall.VaultHeist": row(
                    [7200.0, 2700.0, 1800.0],
                    "/Game/Maps/Guildhall/QG_Guildhall.QG_Guildhall",
                ),
                "Mission.Guildhall.LootTheRoom": row(
                    [3300.0, 1200.0, 1200.0],
                    "/Game/Maps/Guildhall/QG_Guildhall_LootTheRoom.QG_Guildhall_LootTheRoom",
                ),
            },
        )
        tutorial = mission_table(
            tables / "DT_Missions_Tutorial.json",
            {"Mission.Tutorial.Single": row([0.0, 0.0, 0.0])},
        )

        # 1. Positive: the authored side row is parsed with its real ladder.
        side = mod.mission_row_entry(guildhall, "Mission.Guildhall.LootTheRoom")
        check(
            side["durations"] == [3300.0, 1200.0, 1200.0],
            "LootTheRoom row carries the authored 3300/1200/1200 s",
            str(side["durations"]),
        )
        check(
            side["quest_graph_ue_path"].endswith("QG_Guildhall_LootTheRoom"),
            "LootTheRoom row keeps its own quest graph",
            side["quest_graph_ue_path"],
        )

        # 2. Positive: the canonical map row is unchanged.
        canon = mod.mission_row_entry(guildhall, "Mission.Guildhall.VaultHeist")
        check(
            canon["durations"] == [7200.0, 2700.0, 1800.0],
            "Guildhall map row keeps the shipped 7200/2700/1800 s",
            str(canon["durations"]),
        )

        # 3. Negative: a missing row is a visible zero limit, never invented.
        missing = mod.mission_row_entry(guildhall, "Mission.Guildhall.Nope")
        check(
            missing["durations"] == [0.0, 0.0, 0.0],
            "a missing mission row produces no invented duration",
            str(missing["durations"]),
        )

        # 4. End-to-end main(): both rows land under distinct keys.
        mod.ROOT = tmp_path
        mod.TABLES = tables
        mod.CONTRACTS_TABLE = mission_table(
            tmp_path / "DT_Contracts_1_to_16.json",
            {
                "Contract.Main.2": {
                    "ContractOrder": 2,
                    "Map": {
                        "AssetPathName": "/Game/Maps/Guildhall/Guildhall_Contract_02.Guildhall_Contract_02"
                    },
                }
            },
        )
        mod.CONTRACTS_FALLBACK = tmp_path / "CDT_Contracts.json"
        mod.MISSIONS = {
            "guildhall": (guildhall, "Mission.Guildhall.VaultHeist"),
            "ftue": (tutorial, "Mission.Tutorial.Single"),
        }
        mod.SIDE_MISSIONS = {
            "Mission.Guildhall.LootTheRoom": (
                guildhall,
                "Mission.Guildhall.LootTheRoom",
            )
        }
        mod.LOOT_GOAL_QUESTS = {}
        mod.OUT = tmp_path / "out" / "contracts.json"
        mod.main()
        doc = json.loads(mod.OUT.read_text())
        durations = doc["mission_durations"]
        check(
            durations["guildhall"]["durations"] == [7200.0, 2700.0, 1800.0],
            "main keeps the Guildhall map window separate from the Cleanout row",
        )
        side_rec = durations["Mission.Guildhall.LootTheRoom"]
        check(
            side_rec["durations"] == [3300.0, 1200.0, 1200.0],
            "main includes Mission.Guildhall.LootTheRoom in mission_durations",
            str(side_rec["durations"]),
        )
        check(
            side_rec["kind"] == "side_mission"
            and side_rec["mission_id"] == "Mission.Guildhall.LootTheRoom",
            "the Cleanout row is labelled as a side mission",
        )
        check(
            doc["mission_rewards"]["guildhall"]["source_row"]
            == "Mission.Guildhall.VaultHeist",
            "Cleanout does not overwrite the map reward row",
        )

    # 5. Positive against the real extracted table when it is available.
    if REAL_GUILDHALL.is_file():
        side = mod.mission_row_entry(REAL_GUILDHALL, "Mission.Guildhall.LootTheRoom")
        check(
            side["durations"] == [3300.0, 1200.0, 1200.0],
            "real extracted LootTheRoom row is 3300/1200/1200",
            str(side["durations"]),
        )
    else:
        print("SKIP: real DT_Missions_Guildhall.json absent (no extracted tree)")

    print(f"PARSE_CONTRACTS_TEST: PASS checks={PASSED}")


if __name__ == "__main__":
    main()
