#!/usr/bin/env python3
"""Non-Sonar GDScript gate ratchet.

SonarCloud has no GDScript analyzer, so the game code (the largest part of the
repo) is invisible to it. This checker pins the gate numbers that *do* cover
GDScript and fails when the tracked baseline is weakened.

Everything numeric comes from `tools/gate_ratchet.json`; there is no second
copy of a count in this file, so raising the ratchet after a real run never
leaves a checker that forces the old figure.

Evidence layout
---------------
`gate_ratchet.evidence` names the directory and one log per gate:

    docs/reports/logs/<log>          # committed by the wave that measured it

For each gate with an evidence log this checker asserts the log contains the
summary built from the ratchet values, and — for `run_tests`/`m2` — at least
`passes` lines starting with `PASS`. `probe_leak` must contain `PROBE start` and
no leak/script-error markers. A missing log, a stale/mismatched summary or too
few PASS lines is a hard failure with the exact command to re-run and commit.

`audit` and `texture_cap` have no log in the W7G wave: the worktree cannot run
`make audit` while another lane's producers are uncommitted (the private
data tree is shared). Their base floors remain in the JSON and integration must
attach a log when it re-measures; this checker prints a notice rather than
pretending it verified them.

The hosted CI job runs this plus the Python/tooling checks. The Godot gates
themselves need the private extract (`extracted/`, `game/assets/`) and run
locally.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RATCHET = ROOT / "tools" / "gate_ratchet.json"
REPORT = ROOT / "docs" / "reports" / "w7-integration.md"

# Non-numeric wiring only: which values form each log's summary and the exact
# command that regenerates the log. All numbers come from the ratchet JSON.
LOG_GATES = {
    "compile": {
        "command": 'tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"',
        "summary": lambda g: rf"scripts checked: {g['checked']}, broken: {g['broken']}",
        "passes_key": None,
    },
    "run_tests": {
        "command": "make test",
        "summary": lambda g: rf"SUMMARY: fails={g['fails']}",
        "passes_key": "passes",
    },
    "m2": {
        "command": "tools/godot --headless --path game --script res://tests/test_m2_player.gd",
        "summary": lambda g: rf"M2_SUMMARY: fails={g['fails']}",
        "passes_key": "passes",
    },
    "e2e": {
        "command": "tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd",
        "summary": lambda g: (
            rf"SUMMARY: fails={g['fails']} passed={g['passed']} total={g['total']}"
        ),
        "passes_key": None,
    },
    "audit": {
        "command": "make audit",
        # The coverage floor and the unexpected count share one summary line.
        "summary": lambda g: (
            rf"Disk-backed coverage: {g['coverage_num']}/{g['coverage_den']}"
            rf"[^\n]*unexpected {g['unexpected']}"
        ),
        "passes_key": None,
    },
    "texture_cap": {
        "command": "make texture-cap-check",
        # Three values on separate lines; the file is scanned as a whole.
        "summary": lambda g: (
            rf"capped: {g['capped']}[\s\S]*"
            rf"alpha-critical \(kept full-res\): {g['alpha_kept']}[\s\S]*"
            rf"offenders: {g['offenders']}"
        ),
        "passes_key": None,
    },
}
# Gates without an evidence log. Empty now that integration committed audit and
# texture-cap logs; keep the mechanism so a future wave can declare a gap
# explicitly instead of silently leaving a floor unverified.
NO_LOG_GATES: set[str] = set()

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
    measured_on = str(data.get("measured_on") or "")
    if not re.fullmatch(r"[0-9a-f]{7,40}", measured_on):
        fail(f"measured_on is {measured_on!r}, expected a commit SHA")
    else:
        print(f"PASS: measured_on={measured_on}")

    gates = data.get("gates") or {}
    if not isinstance(gates, dict) or not gates:
        fail("gates is missing or empty")
        return 1

    # Every gate value must be a non-negative int; no silent strings/bools.
    for gate, values in sorted(gates.items()):
        if not isinstance(values, dict):
            fail(f"gate {gate!r} is not an object")
            continue
        for key, value in sorted(values.items()):
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                fail(f"{gate}.{key} is {value!r}, expected a non-negative int")
            else:
                print(f"PASS: {gate}.{key}={value}")
    if fails:
        print("\nGATE_RATCHET: FAIL (unusable baseline)")
        return 1

    # Structural invariants, derived from the gate names (not from counts).
    def get(gate: str, key: str) -> int:
        return int((gates.get(gate) or {}).get(key, -1))

    for gate in ("compile", "run_tests", "m2", "e2e"):
        if get(gate, "broken" if gate == "compile" else "fails") != 0:
            fail(f"{gate} records a non-zero failure/broken count")
    if get("e2e", "passed") != get("e2e", "total"):
        fail(f"e2e passed {get('e2e', 'passed')} != total {get('e2e', 'total')}")
    if get("audit", "unexpected") != 0 or get("texture_cap", "offenders") != 0:
        fail("audit.unexpected/texture_cap.offenders must be 0")
    den = get("audit", "coverage_den")
    num = get("audit", "coverage_num")
    if den <= 0 or num > den:
        fail(f"audit coverage {num}/{den} is impossible (num > den or den <= 0)")
    else:
        print(f"PASS: audit coverage {num}/{den} ({100.0 * num / den:.1f} %)")

    # Committed log evidence, one log per entry in `evidence`.
    evidence = data.get("evidence") or {}
    log_dir = ROOT / str(evidence.get("dir") or "docs/reports/logs")
    for gate, spec in LOG_GATES.items():
        log_name = evidence.get(gate)
        command = spec["command"]
        if not log_name:
            fail(
                f"no evidence log named for {gate!r} in gate_ratchet.json "
                f"(add evidence.{gate}); run `{command}` and commit its log"
            )
            continue
        path = log_dir / str(log_name)
        if not path.exists():
            fail(
                f"missing gate log {path.relative_to(ROOT)} for {gate!r} — "
                f"run `{command}` and commit the log"
            )
            continue
        text = path.read_text(errors="replace")
        pattern = spec["summary"](gates[gate])
        if re.search(pattern, text):
            print(f"PASS: {log_name} proves {gate} ({pattern!r})")
        else:
            fail(
                f"{log_name} is stale or mismatched for {gate!r}: no /{pattern}/ — "
                f"run `{command}` and commit the fresh log"
            )
            continue
        passes_key = spec["passes_key"]
        if passes_key:
            floor = int(gates[gate][passes_key])
            passes = len(re.findall(r"^PASS\b", text, flags=re.MULTILINE))
            if passes >= floor:
                print(f"PASS: {log_name} records {passes} PASS >= {floor}")
            else:
                fail(
                    f"{log_name} records {passes} PASS, below the {gate} floor {floor} — "
                    f"run `{command}` and commit the fresh log"
                )

    # Probe clean-ness (no count in the ratchet; a clean marker + no leaks).
    leak_name = evidence.get("probe_leak")
    if leak_name:
        path = log_dir / str(leak_name)
        if not path.exists():
            fail(
                f"missing gate log {path.relative_to(ROOT)} for probe_leak — run "
                "`TAT2_NO_DEN_PROBE=1 tools/godot --headless --path game --script res://probe_leak.gd` "
                "and commit the log"
            )
        else:
            text = path.read_text(errors="replace")
            if "PROBE start" not in text:
                fail(f"{leak_name} is not a probe_leak run (no 'PROBE start')")
            elif re.search(r"leaked at exit|SCRIPT ERROR", text):
                fail(
                    f"{leak_name} contains a leak or script error; the probe must be clean"
                )
            else:
                print(f"PASS: {leak_name} clean")

    for gate in sorted(NO_LOG_GATES & set(gates)):
        print(
            f"NOTICE: {gate} has no committed log in this wave; its base floor is "
            "kept but NOT verified here — integration must re-measure and attach a log"
        )

    # The report must quote the ratchet values, so a stale report cannot claim a
    # green gate. Regexes are built from the JSON numbers.
    if not REPORT.exists():
        fail(f"missing {REPORT.relative_to(ROOT)}")
    else:
        text = REPORT.read_text()
        report_checks = {
            "compile": rf"compile\s*\|\s*{get('compile', 'checked')}\s*/\s*{get('compile', 'broken')}",
            "run_tests": rf"run_tests\s*\|\s*{get('run_tests', 'passes')}",
            "M2": rf"M2\s*\|\s*{get('m2', 'passes')}",
            "E2E": rf"E2E\s*\|\s*{get('e2e', 'passed')}\s*/\s*{get('e2e', 'total')}",
            "coverage": rf"{num}\s*/\s*{den}",
        }
        for label, pattern in report_checks.items():
            if re.search(pattern, text):
                print(f"PASS: report records {label} ({pattern!r})")
            else:
                fail(
                    f"report does not record {label}: no /{pattern}/ — update "
                    f"{REPORT.relative_to(ROOT)} from the ratchet JSON"
                )
        if measured_on and measured_on in text:
            print(f"PASS: report names measured_on={measured_on}")
        else:
            fail(f"report does not name measured_on={measured_on}")

    if fails:
        print(f"\nGATE_RATCHET: FAIL ({len(fails)} problem(s))")
        return 1
    print(
        "\nGATE_RATCHET: PASS (baseline and committed evidence agree; Godot gates run locally)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
