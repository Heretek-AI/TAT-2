#!/usr/bin/env python3
"""Tests for tools/parse_project_ini.py (stdlib only).

Run with: ``python3 tools/test_parse_project_ini.py``

The parser cases are hand-built fixtures; the end-to-end cases run the real
producer against the read-only ``extracted/`` tree into a temporary directory
and assert measured authored values. Every hardcoded number below was measured
with the commands recorded in the T01-PIPELINE worker-A evidence file
(``wc -l``/``sha256sum``/``grep -n`` on DefaultGame.ini and a section key
scanner), not copied from the producer's output.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRODUCER = ROOT / "tools" / "parse_project_ini.py"
EXTRACTED = ROOT / "extracted"
INI = EXTRACTED / "raw" / "TAT" / "Config" / "DefaultGame.ini"

sys.path.insert(0, str(ROOT / "tools"))
sys.dont_write_bytecode = True
import parse_project_ini as ppi  # noqa: E402

# Measured on the shipped ini (2026-11-25): 898 CRLF lines, this digest.
MEASURED_SHA256 = "8d01268989eff43caa3df22d2d01ddfe85833e85ff8be9519a76bd7a2232c751"
# Distinct authored keys per covered section (grep -o ... | sort -u | wc -l).
MEASURED_RAW_KEYS = {
    "/Script/TAT.TATProgressionSettings": 25,
    "/Script/TAT.TATProjectSettings": 158,
    "/Script/TAT.TATScoringSettings": 5,
    "/Script/EngineSettings.GeneralProjectSettings": 11,
    "/Script/Engine.GameSession": 1,
}

PASSED = 0


def check(condition: bool, name: str, detail: str = "") -> None:
    global PASSED
    if not condition:
        message = f"FAIL: {name}"
        if detail:
            message += f" ({detail})"
        print(message)
        raise SystemExit(1)
    print(f"ok {name}")
    PASSED += 1


def scan_raw(text: str, section: str) -> dict[str, str | list[str]]:
    """Independent re-scan: exact authored text per key in one section.

    Deliberately does not use the producer's parser. Repeated keys become
    ordered lists, matching the documented ``raw`` contract.
    """
    grouped: dict[str, list[str]] = {}
    inside = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            inside = stripped == f"[{section}]"
            continue
        if not inside or not stripped or stripped.startswith(";"):
            continue
        key, sep, value = line.partition("=")
        if not sep:
            continue
        key = re.sub(r"^[+\-.!]", "", key.strip())
        grouped.setdefault(key, []).append(value)
    return {
        key: values[0] if len(values) == 1 else values
        for key, values in grouped.items()
    }


def run_producer(extracted: Path, out_dir: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            sys.executable,
            str(PRODUCER),
            "--extracted",
            str(extracted),
            "--out-dir",
            str(out_dir),
            "--quiet",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def main() -> int:
    text = INI.read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory(prefix="test_project_ini_") as tmp:
        tmpdir = Path(tmp)

        # -- parser unit cases (hand-built, CRLF like the real file) ------
        fixture = (
            "[Fixture]\r\n"
            "Nested=(A=1,B=(C=2),D=((E=1),(E=2)))\r\n"
            "Key[0]=1200.000000\r\n"
            "Key[1]=600.000000\r\n"
            "+Arr=(X=1)\r\n"
            "+Arr=(X=2)\r\n"
            "+Arr=(X=3)\r\n"
            "-Arr=(X=2)\r\n"
            'Msg=LOCTABLE("/Game/StringTables/ST_Test.ST_Test", "Key")\r\n'
            'Inv=INVTEXT("Hello {Name}")\r\n'
            'Nsl=NSLOCTEXT("ns", "k", "Some text")\r\n'
            "Flag=True\r\n"
            "Enum=RCIM_Linear\r\n"
            "Bare=Some Bare Token\r\n"
            'Quoted="a,b=c"\r\n'
            "Empty=()\r\n"
            'Tuple=((TagName="Tag.One"), Complete)\r\n'
        )
        sections = ppi.parse_ini_text(fixture)
        sec = sections["Fixture"]
        nested = ppi._entry(sec, "Nested").value
        check(
            nested == {"A": 1, "B": {"C": 2}, "D": [{"E": 1}, {"E": 2}]},
            "parser nested structs",
            repr(nested),
        )
        indexed = ppi.indexed_values(sec, "Key")
        check(
            indexed == [(0, 1200.0), (1, 600.0)],
            "parser indexed properties",
            repr(indexed),
        )
        appended = ppi.effective_array(sec, "Arr")
        check(
            appended == [{"X": 1}, {"X": 3}],
            "parser +/- array ops",
            repr(appended),
        )
        check(
            ppi._entry(sec, "Msg").value
            == 'LOCTABLE("/Game/StringTables/ST_Test.ST_Test", "Key")'
            and ppi._entry(sec, "Inv").value == 'INVTEXT("Hello {Name}")'
            and ppi._entry(sec, "Nsl").value == 'NSLOCTEXT("ns", "k", "Some text")',
            "parser LOCTABLE/INVTEXT/NSLOCTEXT kept raw",
        )
        check(
            ppi._entry(sec, "Flag").value is True
            and ppi._entry(sec, "Enum").value == "RCIM_Linear"
            and ppi._entry(sec, "Bare").value == "Some Bare Token"
            and ppi._entry(sec, "Quoted").value == "a,b=c"
            and ppi._entry(sec, "Empty").value == []
            and ppi._entry(sec, "Tuple").value == [{"TagName": "Tag.One"}, "Complete"],
            "parser scalars, empty list, tag tuple",
        )

        # -- fail-loud paths ---------------------------------------------
        missing = run_producer(tmpdir / "does-not-exist", tmpdir / "out-missing")
        check(
            missing.returncode != 0 and "missing source file" in missing.stderr,
            "producer fails on missing source",
            missing.stderr.strip(),
        )

        fixture_extracted = tmpdir / "fixture-extracted"
        fixture_ini = fixture_extracted / "raw" / "TAT" / "Config" / "DefaultGame.ini"
        fixture_ini.parent.mkdir(parents=True)
        fixture_ini.write_text(
            "[/Script/TAT.TATProgressionSettings]\r\nMaximumLevel=25\r\n"
            "[/Script/TAT.TATProjectSettings]\r\nHubMapName=MissionLobby_P\r\n"
            "[/Script/TAT.TATScoringSettings]\r\nMissionCompleteBonus=1.0\r\n"
            "[/Script/Engine.GameSession]\r\nMaxPlayers=2\r\n"
            "[/Script/EngineSettings.GeneralProjectSettings]\r\n"
            "ProjectName=Fixture\r\n",
            encoding="utf-8",
        )
        incomplete = run_producer(fixture_extracted, tmpdir / "out-incomplete")
        check(
            incomplete.returncode != 0 and "missing authored key" in incomplete.stderr,
            "producer fails on an incomplete ini",
            incomplete.stderr.strip(),
        )

        # -- end-to-end against the shipped tree -------------------------
        out1 = tmpdir / "out1"
        run = run_producer(EXTRACTED, out1)
        check(
            run.returncode == 0 and (out1 / "project_settings.json").is_file(),
            "producer real run exits 0",
            run.stderr.strip(),
        )
        payload = json.loads((out1 / "project_settings.json").read_text())

        check(
            payload["schema"] == "tat2.project_settings/1"
            and payload["generated_by"] == "tools/parse_project_ini.py"
            and payload["source"] == "extracted/raw/TAT/Config/DefaultGame.ini",
            "schema and provenance metadata",
        )
        check(
            payload["source_sha256"]
            == hashlib.sha256(INI.read_bytes()).hexdigest()
            == MEASURED_SHA256,
            "source sha256 matches the measured ini",
            payload["source_sha256"],
        )
        check(
            "generated_at" not in payload
            and not any("timestamp" in key for key in payload),
            "no timestamps in the payload",
        )

        prog = payload["progression"]
        check(
            prog["maximum_level"] == 25
            and prog["level_up_xp"] == 500
            and prog["xp_per_minute"] == 0.6
            and prog["maximum_time_in_game_xp"] == 25.0,
            "progression level/XP scalars",
        )
        check(
            prog["difficulty_xp_multipliers"]
            == {"Easy": 1.0, "Normal": 2.0, "Hard": 3.0},
            "difficulty XP multipliers",
            repr(prog["difficulty_xp_multipliers"]),
        )
        check(
            prog["ftue_level_up_xp_categories"]
            == ["XP.ReachExitInTime", "XP.CompleteMission", "XP.CompleteContracts"]
            and prog["ftue_level_up_xp_is_on_top_of_regular_xp"] is True
            and len(prog["upgrade_editor_progression_node_styles"]) == 4
            and prog["upgrade_editor_progression_node_styles"][0]["style"]
            == "BorderDark",
            "progression FTUE list and editor styles",
        )
        check(
            prog["xp_to_level"]
            == {
                "table": "/Game/Gameplay/Tuning/CT_XPToLevel.CT_XPToLevel",
                "row": "XPToLevel",
                "value": 1.0,
                "registry_type": "None",
            }
            and prog["xp_to_level_table"]
            == "/Game/Gameplay/Tuning/DT_XPToLevel.DT_XPToLevel",
            "progression XP-to-level curve reference",
            repr(prog["xp_to_level"]),
        )

        proj = payload["project"]
        check(
            proj["hub_map_name"] == "MissionLobby_P"
            and proj["thieves_den_map_name"] == "ThievesDenTest_P"
            and proj["enable_thieves_den"] is True
            and proj["show_tutorial_map_after_complete"] is False
            and proj["show_normal_play_if_tutorial_unstarted"] is False
            and proj["ftue_min_thieves_den_money"] == 5000,
            "project map flags and FTUE money",
        )
        check(
            proj["post_ftue_contracts"]
            == [
                {"tag": "Contract.Main.1", "requirement": "Complete"},
                {"tag": "Contract.Main.2", "requirement": "Objective"},
            ],
            "post-FTUE contracts",
            repr(proj["post_ftue_contracts"]),
        )

        maps = proj["maps"]
        guildhall = next(m for m in maps if m["tag"] == "Map.Guildhall")
        old_manor = next(m for m in maps if m["tag"] == "Map.OldManor")
        check(
            len(maps) == 2
            and guildhall["missions"]
            == [
                "Mission.Guildhall.VaultHeist",
                "Mission.Guildhall.Set",
                "Mission.Guildhall.LootTheRoom",
            ]
            and old_manor["missions"]
            == [
                "Mission.OldManor.Set",
                "Mission.OldManor.Vault",
                "Mission.OldManor.LootTheRoom",
            ],
            "maps: 2 entries, authored mission order",
            repr([m["missions"] for m in maps]),
        )
        check(
            guildhall["map"] == "/Game/Maps/Guildhall/Guildhall_P.Guildhall_P"
            and guildhall["game_mode"]
            == "/Game/Core/BP_TATPvEGameMode.BP_TATPvEGameMode_C"
            and guildhall["map_name"] == "Guildhall"
            and guildhall["mesh_scaling"] == {"X": 0.5, "Y": 0.5, "Z": 0.5}
            and guildhall["coordinates_on_city_map"] == {"X": 65.0, "Y": 10.0}
            and guildhall["map_display_name"].startswith("LOCTABLE("),
            "Guildhall map fields",
            repr(guildhall),
        )
        check(
            len(proj["map_type_settings"]) == 8
            and proj["map_type_settings"][0]["allow_default_player_tools"] is False
            and proj["map_type_settings"][3]["allow_default_player_tools"] is True
            and proj["map_type_settings"][3]["index"] == 3,
            "map type settings (8 authored indices)",
        )
        check(
            proj["endgame_durations_by_difficulty"] == [1200.0, 600.0, 300.0]
            and proj["endgame_duration_seconds_by_difficulty_index"]
            == {"0": 1200.0, "1": 600.0, "2": 300.0}
            and proj["difficulty_index_source"] == "unproven: index order only",
            "endgame durations and difficulty-index provenance",
            repr(proj["endgame_durations_by_difficulty"]),
        )
        check(
            proj["stashed_loot_value_to_trigger_endgame"] == 99999
            and proj["match_essentially_complete_threshold"] == 30.0
            and proj["difficulty_property_name"] == "Difficulty",
            "endgame trigger scalars",
        )
        check(
            proj["initial_unlocked_content"]
            == [
                "Difficulty.Novice",
                "Thief.Spider",
                "Outfit.Spider.Head.Default",
                "Outfit.Spider.Body.Default",
                "Outfit.Spider.CallingCard.Default",
                "Outfit.Chameleon.Body.Default",
                "Outfit.Chameleon.CallingCard.Default",
                "Outfit.Chameleon.Head.Default",
            ]
            and proj["post_ftue_unlocked_content"]
            == ["Map.Guildhall", "Tool.Type.Zipwire", "Tool.Type.SmokeBomb"],
            "initial and post-FTUE unlocked content",
        )

        scoring = payload["scoring"]
        check(
            scoring["mission_complete_bonus"] == 300.0
            and scoring["contract_complete_bonus"] == 100.0
            and scoring["stashed_loot_value_multiplier_bonus"] == 0.1
            and scoring["carried_loot_value_multiplier_bonus"] == 0.1
            and scoring["escape_order_bonus_curve"]
            == "/Game/Matchmaking/Ranking/C_Ranking_EscapeOrderBonus."
            "C_Ranking_EscapeOrderBonus",
            "scoring weights",
            repr({k: v for k, v in scoring.items() if k != "raw"}),
        )

        general = payload["general"]
        check(
            general["max_players"] == 2
            and general["project_name"] == "Thick As Thieves"
            and general["project_version"] == "0.0.0.1"
            and general["company_name"] == "OtherSide Entertainment",
            "general session/project provenance",
        )

        # -- raw fidelity: exact text, every key, independent scan ---------
        raw_cases = [
            ("progression", "/Script/TAT.TATProgressionSettings"),
            ("project", "/Script/TAT.TATProjectSettings"),
            ("scoring", "/Script/TAT.TATScoringSettings"),
            ("general", "/Script/EngineSettings.GeneralProjectSettings"),
        ]
        raw_ok = all(
            payload[block]["raw"] == scan_raw(text, section)
            for block, section in raw_cases
        ) and general["max_players_raw"] == scan_raw(text, "/Script/Engine.GameSession")
        check(raw_ok, "raw map is byte-exact for every covered key")
        check(
            len(payload["progression"]["raw"])
            == MEASURED_RAW_KEYS["/Script/TAT.TATProgressionSettings"]
            and len(payload["project"]["raw"])
            == MEASURED_RAW_KEYS["/Script/TAT.TATProjectSettings"]
            and len(payload["scoring"]["raw"])
            == MEASURED_RAW_KEYS["/Script/TAT.TATScoringSettings"]
            and len(general["raw"])
            == MEASURED_RAW_KEYS["/Script/EngineSettings.GeneralProjectSettings"]
            and len(general["max_players_raw"])
            == MEASURED_RAW_KEYS["/Script/Engine.GameSession"],
            "raw key counts match the measured section scans",
        )
        check(
            prog["raw"]["LevelUpXP"] == "500"
            and prog["raw"]["XPPerMinute"] == "0.600000"
            and isinstance(proj["raw"]["Maps"], list)
            and len(proj["raw"]["Maps"]) == 2
            and proj["raw"]["MapTypeSettings[0]"].startswith(
                "(AllowDefaultPlayerTools=False"
            )
            and scoring["raw"]["MissionCompleteBonus"] == "300.000000"
            and general["raw"]["ProjectName"] == "Thick As Thieves",
            "raw values are the exact authored strings",
        )
        check(payload["unmapped_keys"] == [], "unmapped_keys is empty")

        # -- idempotency ---------------------------------------------------
        out2 = tmpdir / "out2"
        run2 = run_producer(EXTRACTED, out2)
        check(
            run2.returncode == 0
            and (out1 / "project_settings.json").read_bytes()
            == (out2 / "project_settings.json").read_bytes(),
            "two runs are byte-identical",
        )

    print(f"PASS: {PASSED} checks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
