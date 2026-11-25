#!/usr/bin/env python3
"""Negative-control tests for tools/check_consumers.py (stdlib only).

Run with: ``python3 tools/test_check_consumers.py``

Every case builds a tiny ``game/data/generated`` + ``game/src`` + allowlist in a
temporary directory and asserts the *reason* the checker fails or passes, so a
silently weakened consumer audit (e.g. one that treats an allowlist rule with no
reason as acceptable) cannot go green.

``tools/check_consumers.py`` resolves ``ROOT`` from its own location, so the
fixture cannot be passed through the CLI (``--generated`` etc. are absolute-path
friendly but ``consumer`` claims are repo-relative). The suite therefore imports
the module and monkeypatches its ``ROOT`` to the fixture, which also exercises
the same functions the gate runs.
"""

from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHECKER = ROOT / "tools" / "check_consumers.py"

failures: list[str] = []
checks = 0


def check(name: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if condition:
        print(f"ok {name}")
    else:
        failures.append(f"{name}: {detail}" if detail else name)
        print(f"FAIL {name} {detail}")


def load_checker():
    spec = importlib.util.spec_from_file_location("check_consumers_under_test", CHECKER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


GAME_DATA_GD = """
func _load_curves() -> void:
\t_load_tables_from_dir("res://data/generated/tables/AI/Data", false)
\tfor dir_path: String in [
\t\t"res://data/generated/tables/Gameplay/Carry",
\t\t"res://data/generated/tables/AI/Alertness",
\t]:
\t\t_load_tables_from_dir(dir_path, true)


func _load_tables_from_dir(base_dir: String, recursive: bool) -> void:
\tvar dir: DirAccess = DirAccess.open(base_dir)
\tif recursive:
\t\t_load_tables_from_dir(base_dir + "/" + "x", recursive)
"""


def build(base: Path) -> dict:
    generated = base / "game" / "data" / "generated"
    src = base / "game" / "src"
    tests = base / "game" / "tests"
    # A table inside a non-recursive root: consumed.
    write(generated / "tables/AI/Data/DT_Inside.json", "{}")
    # A table two levels under a recursive root: consumed.
    write(generated / "tables/Gameplay/Carry/Deep/DT_Deep.json", "{}")
    # A table under a non-recursive root but in a subdirectory: NOT consumed.
    write(generated / "tables/AI/Data/Sub/DT_Buried.json", "{}")
    # A table named by a literal in game/src: consumed.
    write(generated / "tables/Elsewhere/DT_Named.json", "{}")
    # A table with no reader at all: must fail.
    write(generated / "tables/Elsewhere/DT_Orphan.json", "{}")
    # A manifest JSON named by a literal: consumed.
    write(generated / "gameplay/quests.json", "{}")
    # A manifest JSON only read by tests: needs a tests_only rule.
    write(generated / "gameplay/state_speeds.json", "{}")
    write(src / "core/game_data.gd", GAME_DATA_GD)
    write(
        src / "core/quests.gd",
        'const PATH := "res://data/generated/gameplay/quests.json"\n',
    )
    write(
        src / "core/tables_user.gd",
        'const P := "res://data/generated/tables/Elsewhere/DT_Named.json"\n',
    )
    write(tests / "run_tests.gd", 'const P := "state_speeds.json"\n')
    allowlist = base / "tools" / "consumer_allowlist.json"
    consumer = base / "tools" / "reader.py"
    write(consumer, "STATE_SPEEDS = 'state_speeds.json'\n")
    return {
        "generated": generated,
        "src": src,
        "tests": tests,
        "allowlist": allowlist,
        "consumer": consumer,
        "base": base,
    }


def run_checker(module, fixture: dict, allowlist_rules: list[dict]) -> tuple[int, str]:
    write(
        fixture["allowlist"],
        json.dumps({"schema": "tat2.consumer_allowlist/1", "rules": allowlist_rules}),
    )
    module.ROOT = fixture["base"]
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        status = module.audit(
            fixture["generated"],
            fixture["src"],
            fixture["tests"],
            fixture["allowlist"],
            False,
        )
    return status, buffer.getvalue()


def main() -> int:
    module = load_checker()
    with tempfile.TemporaryDirectory(prefix="tat2-consumers-test-") as td:
        base = Path(td)
        fixture = build(base)

        # --- Baseline: the orphan and the buried table must fail. ------------
        status, out = run_checker(module, fixture, [])
        check("unconsumed table fails the audit", status == 1, out)
        check("orphan is named", "DT_Orphan.json" in out, out)
        check(
            "a non-recursive root does not cover subdirectories",
            "DT_Buried.json" in out,
            out,
        )
        check(
            "recursive root covers deep tables",
            "DT_Deep.json" not in out.split("FAIL")[0],
            out,
        )
        check(
            "literal reader counts as consumed",
            "DT_Named.json" not in out.split("FAIL")[0],
            out,
        )
        check(
            "tests-only reader is classified, not silently passed",
            "tests_only" in out,
            out,
        )

        # --- A complete allowlist passes. ------------------------------------
        rules = [
            {
                "glob": "tables/Elsewhere/DT_Orphan.json",
                "kind": "blocked_on_team",
                "owner": "T99",
                "reason": "test rule",
            },
            {
                "glob": "tables/AI/Data/Sub/**",
                "kind": "producer_intermediate",
                "reason": "test rule",
            },
            {
                "glob": "gameplay/state_speeds.json",
                "kind": "tests_only",
                "reason": "test rule",
                "consumer": "tools/reader.py",
                "claim_token": "STATE_SPEEDS",
            },
        ]
        status, out = run_checker(module, fixture, rules)
        check("complete allowlist passes", status == 0, out)
        check("blocked owner is reported", "T99 1" in out, out)

        # --- Reasons are mandatory. -----------------------------------------
        status, out = run_checker(
            module,
            fixture,
            rules[:2] + [dict(rules[2], reason="")],
        )
        check("a rule without a reason fails", status == 1 and "no reason" in out, out)

        # --- blocked_on_team must name an owner. -----------------------------
        status, out = run_checker(
            module,
            fixture,
            [dict(rules[0], owner="")] + rules[1:],
        )
        check(
            "blocked_on_team without owner fails",
            status == 1 and "no owner" in out,
            out,
        )

        # --- Stale rules fail, optional stale rules do not. ------------------
        status, out = run_checker(
            module,
            fixture,
            rules
            + [{"glob": "tables/Nope/**", "kind": "provenance", "reason": "gone"}],
        )
        check(
            "a rule that matches nothing fails",
            status == 1 and "STALE RULE" in out,
            out,
        )
        status, out = run_checker(
            module,
            fixture,
            rules
            + [
                {
                    "glob": "tables/Nope/**",
                    "kind": "provenance",
                    "reason": "staged producer",
                    "optional": True,
                }
            ],
        )
        check("an optional stale rule is a note, not a failure", status == 0, out)

        # --- Consumer claims must be falsifiable. ---------------------------
        status, out = run_checker(
            module,
            fixture,
            rules[:2]
            + [
                {
                    "glob": "gameplay/state_speeds.json",
                    "kind": "tests_only",
                    "reason": "claims a consumer",
                    "consumer": "tools/reader.py",
                }
            ],
        )
        check(
            "a consumer claim without claim_token fails",
            status == 1 and "claim_token" in out,
            out,
        )
        status, out = run_checker(
            module,
            fixture,
            rules[:2]
            + [
                {
                    "glob": "gameplay/state_speeds.json",
                    "kind": "tests_only",
                    "reason": "claims a consumer",
                    "consumer": "tools/reader.py",
                    "claim_token": "NOT_IN_THE_FILE",
                }
            ],
        )
        check(
            "a false claim_token fails", status == 1 and "does not appear" in out, out
        )
        status, out = run_checker(
            module,
            fixture,
            rules[:2]
            + [
                {
                    "glob": "gameplay/state_speeds.json",
                    "kind": "tests_only",
                    "reason": "claims a missing consumer",
                    "consumer": "tools/absent.py",
                    "claim_token": "x",
                }
            ],
        )
        check(
            "a missing consumer file fails",
            status == 1 and "does not exist" in out,
            out,
        )

        # --- Unknown kind fails. --------------------------------------------
        status, out = run_checker(
            module,
            fixture,
            rules[:2] + [dict(rules[2], kind="handwave")],
        )
        check("an unknown kind fails", status == 1 and "unknown kind" in out, out)

        # --- Empty roots: a note before the curve producer ran, a failure after.
        status, out = run_checker(module, fixture, rules)
        check(
            "an empty root is reported",
            "EMPTY table roots" in out and "tables/AI/Alertness" in out,
            out,
        )
        check("an empty root alone does not fail before regeneration", status == 0, out)
        write(fixture["generated"] / "curves.json", "{}")
        status, out = run_checker(module, fixture, rules)
        check(
            "an empty root fails once curves.json exists",
            status == 1 and "EMPTY ROOT tables/AI/Alertness" in out,
            out,
        )
        (fixture["generated"] / "curves.json").unlink()
        write(fixture["generated"] / "tables/AI/Alertness/C_Test.json", "{}")
        status, out = run_checker(module, fixture, rules)
        check(
            "a filled root passes", status == 0 and "EMPTY table roots" not in out, out
        )

        # --- ** glob spans directories. -------------------------------------
        check(
            "** spans directories",
            module.rule_matches(
                "tables/AI/Data/**", "tables/AI/Data/Sub/DT_Buried.json"
            ),
        )
        check(
            "* does not span directories",
            not module.rule_matches(
                "tables/AI/Data/*", "tables/AI/Data/Sub/DT_Buried.json"
            ),
        )

        # --- The GDScript root parser is fail-closed. -----------------------
        roots = module.parse_table_roots(GAME_DATA_GD)
        check(
            "parser reads literal roots and loop roots",
            ("tables/AI/Data", False) in roots
            and ("tables/Gameplay/Carry", True) in roots
            and ("tables/AI/Alertness", True) in roots,
            str(roots),
        )
        try:
            module.parse_table_roots(
                GAME_DATA_GD.replace(
                    "func _load_tables_from_dir",
                    "\t_load_tables_from_dir(some_variable, true)\n\nfunc _load_tables_from_dir",
                )
            )
            unparseable_failed = False
        except ValueError:
            unparseable_failed = True
        check("an unparseable root argument fails closed", unparseable_failed)

    if failures:
        print(f"FAIL: {len(failures)} failure(s)")
        for item in failures:
            print(f"  {item}")
        return 1
    print(f"PASS: {checks} checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
