#!/usr/bin/env python3
"""Non-Sonar GDScript gate ratchet.

SonarCloud has no GDScript analyzer, so the game code (the largest part of the
repo) is invisible to it. This checker pins the gate numbers that *do* cover
GDScript and fails when the tracked baseline is weakened:

* compile / run_tests / M2 / E2E / audit / texture-cap floors in
  `tools/gate_ratchet.json`;
* zero failures/broken/offenders everywhere;
* the counts quoted in `docs/reports/w6t-graybox-sonar.md` agree with the
  baseline (so a stale report cannot claim a green gate).

The hosted CI job runs this plus the Python/tooling checks. The Godot gates
themselves need the private extract (`extracted/`, `game/assets/`) and run
locally; this checker never claims to have run them.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RATCHET = ROOT / "tools" / "gate_ratchet.json"
REPORT = ROOT / "docs" / "reports" / "w6t-graybox-sonar.md"

FLOORS = {
    ("compile", "checked"): 101,
    ("run_tests", "passes"): 261,
    ("m2", "passes"): 11,
    ("e2e", "passed"): 264,
    ("audit", "coverage_num"): 12657,
    ("texture_cap", "capped"): 773,
}
ZERO = [
    ("compile", "broken"),
    ("run_tests", "fails"),
    ("m2", "fails"),
    ("e2e", "fails"),
    ("audit", "unexpected"),
    ("texture_cap", "offenders"),
]

fails: list[str] = []


def fail(msg: str) -> None:
    fails.append(msg)
    print(f"FAIL: {msg}")


def main() -> int:
    if not RATCHET.exists():
        print(f"FAIL: missing {RATCHET.relative_to(ROOT)}")
        return 1
    data = json.loads(RATCHET.read_text())
    if data.get("schema") != "tat2.gate_ratchet/1":
        fail(f"schema is {data.get('schema')!r}, expected tat2.gate_ratchet/1")
    gates = data.get("gates") or {}
    for (gate, key), floor in FLOORS.items():
        value = (gates.get(gate) or {}).get(key)
        if not isinstance(value, int):
            fail(f"{gate}.{key} is missing or not an int")
        elif value < floor:
            fail(f"{gate}.{key}={value} is below the floor {floor}")
        else:
            print(f"PASS: {gate}.{key}={value} >= floor {floor}")
    for gate, key in ZERO:
        value = (gates.get(gate) or {}).get(key)
        if value != 0:
            fail(f"{gate}.{key}={value!r}, expected 0")
        else:
            print(f"PASS: {gate}.{key}=0")
    e2e = gates.get("e2e") or {}
    if isinstance(e2e.get("passed"), int) and isinstance(e2e.get("total"), int):
        if e2e["passed"] != e2e["total"]:
            fail(f"e2e passed {e2e['passed']} != total {e2e['total']}")

    if not REPORT.exists():
        fail(f"missing {REPORT.relative_to(ROOT)}")
    else:
        text = REPORT.read_text()
        checks = {
            "compile 101/0": r"compile\s*\|\s*101\s*/\s*0",
            "run_tests 261": r"run_tests\s*\|\s*261",
            "E2E 264/264": r"E2E\s*\|\s*264\s*/\s*264",
        }
        for label, pattern in checks.items():
            if re.search(pattern, text):
                print(f"PASS: report records {label}")
            else:
                fail(f"report does not record the measured {label}")

    if fails:
        print(f"\nGATE_RATCHET: FAIL ({len(fails)} problem(s))")
        return 1
    print("\nGATE_RATCHET: PASS (baseline intact; Godot gates run locally)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
