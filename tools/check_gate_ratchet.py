#!/usr/bin/env python3
"""Non-Sonar GDScript gate ratchet.

SonarCloud has no GDScript analyzer, so the game code (the largest part of the
repo) is invisible to it. This checker pins the gate numbers that *do* cover
GDScript and fails when the tracked baseline is weakened.

Everything numeric comes from `tools/gate_ratchet.json`; there is no second
copy of a count in this file, so raising the ratchet after a real run never
leaves a checker that forces the old figure.

Floors are MINIMUMS
-------------------
A wave may add scripts or tests, so every count is read from the log and
compared with `>=` against the ratchet value: a log below a floor fails, a log
above it passes. Failure counts (`broken`, `fails`, `unexpected`, `offenders`)
are exact zeros, `e2e.passed` must equal `e2e.total`, and audit coverage must
satisfy `num <= den`. The ratchet value therefore never has to be bumped just
because a wave added a test.

Evidence layout
---------------
`gate_ratchet.evidence` names the directory and one log per gate:

    docs/reports/logs/<log>          # committed by the wave that measured it

For each gate with an evidence log this checker asserts the log matches the
summary pattern and that every captured count is at or above the floor; for
`run_tests`/`m2` it also requires at least `passes` lines starting with `PASS`.
`probe_leak` must contain `PROBE start` and no leak/script-error markers, and
the named probe logs must contain their PASS marker.

`report` names the report that must quote the floors, the coverage and the
`measured_on` commit, so a stale report cannot claim a green gate. It defaults
to the W7 report for older baselines.

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
DEFAULT_REPORT = "docs/reports/w7-integration.md"

# Non-numeric wiring only: the log pattern each gate writes and the exact
# command that regenerates the log. All numbers come from the ratchet JSON.
# `minimums` maps a regex group to the ratchet key it must be >=.
LOG_GATES = {
    "compile": {
        "command": 'tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"',
        "pattern": lambda g: r"scripts checked: (\d+), broken: 0",
        "minimums": [(1, "checked")],
        "passes_key": None,
    },
    "run_tests": {
        "command": "make test",
        "pattern": lambda g: r"SUMMARY: fails=0",
        "minimums": [],
        "passes_key": "passes",
    },
    "m2": {
        "command": "tools/godot --headless --path game --script res://tests/test_m2_player.gd",
        "pattern": lambda g: r"M2_SUMMARY: fails=0",
        "minimums": [],
        "passes_key": "passes",
    },
    "e2e": {
        "command": "tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd",
        "pattern": lambda g: r"SUMMARY: fails=0 passed=(\d+) total=(\d+)",
        "minimums": [(1, "passed"), (2, "total")],
        "equal_groups": (1, 2),
        "passes_key": None,
    },
    # P0b acceptance tier a2: one real Contract 02 Novice mission. Standalone
    # (`--tier=a2`) until the integrator merges it into `all`; the log is its
    # own evidence so the full `e2e` floor stays the P0a measurement.
    "e2e_a2": {
        "command": "tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=a2",
        "pattern": lambda g: r"SUMMARY: fails=0 passed=(\d+) total=(\d+)",
        "minimums": [(1, "passed"), (2, "total")],
        "equal_groups": (1, 2),
        "passes_key": None,
    },
    # P0b parity tier p2: authored-data provenance with recorded expected
    # FAIL/DELTA. `unexpected_fail=0` is the gate; expected_fail/expected_delta
    # are recorded measurements, not floors (a data wave may fix them).
    "e2e_p2": {
        "command": "tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=p2",
        "pattern": lambda g: (
            r"P2_SUMMARY: expected_fail=(\d+) expected_delta=(\d+) "
            r"fixed=(\d+) unexpected_fail=0"
        ),
        "minimums": [],
        "passes_key": None,
    },
    # P0b parity-only governance: every content-override rule is classified and
    # `TAT2_PARITY_ONLY=1` excludes expansion content while keeping every
    # shipped marker/guard/GC/loot record. The standalone contract test.
    "parity_only": {
        "command": (
            "tools/godot --headless --path game "
            "--script res://tests/test_parity_only.gd"
        ),
        "pattern": lambda g: r"PARITY_ONLY_SUMMARY: fails=0 passed=(\d+)",
        "minimums": [(1, "passes")],
        "passes_key": None,
    },
    # P0b port capture: the headless dry-run writes the six-pose manifest and
    # the ROI script validates its schema without a GPU. The validated manifest
    # is the same file the real capture run overwrites, so a schema regression
    # fails here before any capture time is spent. P1 records its dry-run under
    # its own evidence dir via P0B_EVIDENCE_DIR (default stays the P0b path).
    "p0b_capture": {
        "command": (
            "P0B_EVIDENCE_DIR=docs/reports/logs/p1/full "
            "build/qa/p0b_capture.sh --dry-run && "
            "build/qa/p0b_roi_stats.py --validate-manifest "
            "docs/reports/logs/p1/full/dry-run/manifest.json"
        ),
        "pattern": lambda g: r"P0B_MANIFEST_OK [^\n]*poses=(\d+) dry_run=true",
        "minimums": [(1, "poses")],
        "passes_key": None,
    },
    # P1 route-content probes: one per lane, each prints a stable PASS line with
    # its measured check count. The counts are floors (a probe may add checks,
    # never drop them); the PASS literal is part of the pattern so a probe that
    # exits 0 without its summary fails here.
    "probe_p1_safe": {
        "command": (
            "tools/godot --headless --path game --script res://tests/probe_p1_safe.gd"
        ),
        "pattern": lambda g: r"P1_SAFE PASS checks=(\d+) fails=0",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    "probe_p1_doors": {
        "command": (
            "tools/godot --headless --path game --script res://tests/probe_p1_doors.gd"
        ),
        "pattern": lambda g: r"P1_DOORS checks=(\d+) fails=0\s*\nP1_DOORS PASS",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    "probe_p1_beams": {
        "command": (
            "tools/godot --headless --path game --script res://tests/probe_p1_beams.gd"
        ),
        "pattern": lambda g: r"P1_BEAMS PASS checks=(\d+) fails=0",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    "probe_p1_ward": {
        "command": (
            "tools/godot --headless --path game --script res://tests/probe_p1_ward.gd"
        ),
        "pattern": lambda g: r"P1_WARD PASS checks=(\d+)",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    "probe_p1_street": {
        "command": (
            "tools/godot --headless --path game --script res://tests/probe_p1_street.gd"
        ),
        "pattern": lambda g: (
            r"P1_STREET SUMMARY checks=(\d+) fails=0 hard_limits=(\d+)"
            r"\s*\nP1_STREET PASS"
        ),
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    "audit": {
        "command": "make audit",
        # Coverage and the unexpected count share one summary line.
        "pattern": lambda g: (
            r"Disk-backed content coverage: (\d+)/(\d+)[^\n]*unexpected 0"
        ),
        "minimums": [(1, "coverage_num"), (2, "coverage_den")],
        "num_le_den": (1, 2),
        "passes_key": None,
    },
    "texture_cap": {
        "command": "make texture-cap-check",
        # Three values on separate lines; the file is scanned as a whole.
        "pattern": lambda g: (
            r"capped: (\d+)[\s\S]*"
            r"alpha-critical \(kept full-res\): (\d+)[\s\S]*"
            r"offenders: 0"
        ),
        "minimums": [(1, "capped"), (2, "alpha_kept")],
        "passes_key": None,
    },
    "perf_guard": {
        "command": "build/qa/test_perf_guard.sh",
        "pattern": lambda g: r"PERF_GUARD_TEST PASS checks=(\d+) fails=0",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    # W10-A: the three-map authored-collision gate. `COL_MAPS PASS` is printed
    # only when every map passed its own `COL_MAP_ASSERT` (coverage >= 95 %,
    # dropped == 0, non-zero shapes and placed meshes), so the PASS literal is
    # the real gate; the captured numbers are the ratchet's floors.
    "probe_collision": {
        "command": "tools/godot --headless --path game --script res://tests/probe_collision_authored.gd",
        "pattern": lambda g: (
            r"COL_MAPS PASS maps=(\d+) min_coverage=([0-9.]+) dropped=(\d+) "
            r"planar_skipped=(\d+) coverage_ppm=(\d+)"
        ),
        "minimums": [(1, "maps"), (3, "dropped"), (5, "coverage_ppm")],
        "passes_key": None,
    },
    # W10-A: the de-duplicated runtime lock count (raw record count is separate).
    "lock_inventory": {
        "command": "tools/godot --headless --path game --script res://tests/probe_lock_inventory.gd",
        "pattern": lambda g: (
            r"LOCK_INVENTORY runtime: .*applied=(\d+) containers=(\d+) "
            r"door_nodes=(\d+) .*state=APPLIED"
        ),
        "minimums": [(1, "applied"), (2, "containers"), (3, "door_nodes")],
        "passes_key": None,
    },
    "string_audit": {
        "command": "make string-audit",
        "pattern": lambda g: (
            r"UI_STRINGS total=(\d+) routed=(\d+) authored=(\d+) "
            r"routed_authored=(\d+) invented=(\d+)"
        ),
        "minimums": [(2, "routed"), (3, "authored")],
        "passes_key": None,
    },
    # W10-A D9: only exit 124 (the timeout kill) and a clean scan pass.
    "runtime_smoke": {
        "command": "build/qa/runtime_smoke.sh 90",
        "pattern": lambda g: (
            r"RUNTIME_SMOKE_SCAN PASS exit=124 errors=(\d+) .*mission_ready=(\d+) reason=ok"
        ),
        "minimums": [(1, "errors"), (2, "mission_ready")],
        "passes_key": None,
    },
}

# Probe logs have no numeric floor: a named marker and a clean run are the gate.
PROBE_GATES = {
    "probe_door_walk": (
        "DOORWALK PASS",
        "tools/godot --headless --path game --script res://tests/probe_door_walk.gd",
    ),
    "probe_viewmodel_truth": (
        "VIEWMODEL_TRUTH PASS",
        "tools/godot --headless --path game --script res://tests/probe_viewmodel_truth.gd",
    ),
    "probe_niagara": (
        "NIAGARA_PROBE PASS",
        "tools/godot --headless --path game --script res://tests/probe_niagara.gd",
    ),
    "probe_blackjack_race": (
        "BLACKJACK_PROBE PASS",
        "tools/godot --headless --path game --script res://tests/probe_blackjack_race.gd",
    ),
    "probe_geometry_placement": (
        "GEOM_PROBE PASS",
        "tools/godot --headless --path game --script res://tests/probe_geometry_placement.gd",
    ),
    # W10-A: per-map collision assertion + the literal-grep gate. The collision
    # probe's own exit code is the enforcement; this marker proves every map
    # printed its `COL_MAP_ASSERT … PASS` before the summary line.
    "probe_collision_maps": (
        "COL_MAPS PASS",
        "tools/godot --headless --path game --script res://tests/probe_collision_authored.gd",
    ),
    "literal_greps": (
        "LITERAL_GREPS PASS",
        "make check-greps",
    ),
    # P0a: guard bucket/layer selection, beam axis/length and the W10-A2/A3/B1
    # standalone gates. The full PASS lines are the marker on purpose: they pin
    # the authored Lounge C_20 / no-Hauntstable result and the Old Manor run,
    # not just "some guard probe passed".
    "probe_guard_positions_guildhall": (
        "GUARD_CHECK PASS map=guildhall order=2 guards=4 buckets=4/4 lounge=1 "
        "lounge_marker=C_20 selection=parity_approx_layer_bucket difficulty=1",
        "tools/godot --headless --path game --script res://tests/probe_guard_positions.gd",
    ),
    "probe_guard_positions_old_manor": (
        "GUARD_CHECK PASS map=old_manor order=3 guards=4 buckets=4/4 lounge=0 "
        "lounge_marker=- selection=parity_approx_layer_bucket difficulty=1",
        "tools/godot --headless --path game --script res://tests/probe_guard_positions.gd -- --map=old_manor --order=3",
    ),
    "beam_geometry": (
        "BEAM_GEOMETRY_SUMMARY: fails=0",
        "tools/godot --headless --path game --script res://tests/test_beam_geometry.gd",
    ),
    "probe_device_meshes": (
        "TURRET_PROBE PASS",
        "tools/godot --headless --path game --script res://tests/probe_device_meshes.gd",
    ),
    "probe_gc_destruction": (
        "GC_PROBE PASS",
        "tools/godot --headless --path game --script res://tests/probe_gc_destruction.gd",
    ),
    "test_gc_break_trigger": (
        "GC_TRIGGER PASS",
        "tools/godot --headless --path game --script res://tests/test_gc_break_trigger.gd",
    ),
    "test_w10a2_civilian": (
        "W10A2_CIV_SUMMARY: fails=0",
        "tools/godot --headless --path game --script res://tests/test_w10a2_civilian.gd",
    ),
    "test_w10a2_guard_placement": (
        "GUARD_PLACEMENT_SUMMARY: fails=0",
        "tools/godot --headless --path game --script res://tests/test_w10a2_guard_placement.gd",
    ),
    # P0b capture instruments: the headless self-test (audio tap fallback,
    # manifest round-trip, rejected FOV/settle) and the tracked KF27 reference
    # frame scored with the same criteria the port ROI script applies.
    "p0b_capture_self_test": (
        "P0B_SELFTEST PASS",
        "P0B_EVIDENCE_DIR=docs/reports/logs/p1/full build/qa/p0b_capture.sh --self-test",
    ),
    "p0b_kf27_reference": (
        "P0B_KF27_REF pose=upper_foyer met=7/7",
        "build/qa/p0b_roi_stats.py --port docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg --pose upper_foyer --reference-only",
    ),
}

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
    if get("perf_guard", "fails") != 0:
        fail("perf_guard.fails must be 0")
    den = get("audit", "coverage_den")
    num = get("audit", "coverage_num")
    if den <= 0 or num > den:
        fail(f"audit coverage {num}/{den} is impossible (num > den or den <= 0)")
    else:
        print(f"PASS: audit coverage {num}/{den} ({100.0 * num / den:.1f} %)")

    # Committed log evidence, one log per entry in `evidence`. A value with a
    # "/" is a repo-root-relative path (a later wave's own log directory); a
    # bare filename lives in `evidence.dir`, so older baselines are unchanged.
    evidence = data.get("evidence") or {}
    log_dir = ROOT / str(evidence.get("dir") or "docs/reports/logs")

    def evidence_path(log_name: str) -> Path:
        name = str(log_name)
        return ROOT / name if "/" in name else log_dir / name

    for gate, spec in LOG_GATES.items():
        log_name = evidence.get(gate)
        command = spec["command"]
        if not log_name:
            fail(
                f"no evidence log named for {gate!r} in gate_ratchet.json "
                f"(add evidence.{gate}); run `{command}` and commit its log"
            )
            continue
        path = evidence_path(log_name)
        if not path.exists():
            fail(
                f"missing gate log {path.relative_to(ROOT)} for {gate!r} — "
                f"run `{command}` and commit the log"
            )
            continue
        text = path.read_text(errors="replace")
        match = re.search(spec["pattern"](gates[gate]), text)
        if match is None:
            fail(
                f"{log_name} is stale or mismatched for {gate!r}: no "
                f"/{spec['pattern'](gates[gate])}/ — run `{command}` and commit the fresh log"
            )
            continue
        print(f"PASS: {log_name} proves {gate} ({spec['pattern'](gates[gate])!r})")
        for group, key in spec.get("minimums", []):
            captured = int(match.group(group))
            floor = get(gate, key)
            if captured < floor:
                fail(
                    f"{log_name} records {gate}.{key}={captured}, below the floor {floor} — "
                    f"run `{command}` and commit the fresh log"
                )
            else:
                print(f"PASS: {log_name} records {gate}.{key}={captured} >= {floor}")
        equal = spec.get("equal_groups")
        if equal:
            left, right = int(match.group(equal[0])), int(match.group(equal[1]))
            if left != right:
                fail(f"{log_name}: {gate} passed {left} != total {right}")
        num_le_den = spec.get("num_le_den")
        if num_le_den:
            left, right = (
                int(match.group(num_le_den[0])),
                int(match.group(num_le_den[1])),
            )
            if right <= 0 or left > right:
                fail(f"{log_name}: {gate} coverage {left}/{right} is impossible")
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

    for gate, (marker, command) in PROBE_GATES.items():
        log_name = evidence.get(gate)
        if not log_name:
            fail(
                f"no evidence log named for {gate!r} in gate_ratchet.json "
                f"(add evidence.{gate}); run `{command}` and commit its log"
            )
            continue
        path = evidence_path(log_name)
        if not path.exists():
            fail(
                f"missing gate log {path.relative_to(ROOT)} for {gate!r} — "
                f"run `{command}` and commit the log"
            )
            continue
        text = path.read_text(errors="replace")
        if marker not in text:
            fail(f"{log_name} does not contain {marker!r} — run `{command}`")
        elif re.search(r"SCRIPT ERROR", text):
            fail(f"{log_name} contains a SCRIPT ERROR; the probe must be clean")
        else:
            print(f"PASS: {log_name} records {marker}")

    # The report must quote the ratchet values, so a stale report cannot claim a
    # green gate. Regexes are built from the JSON numbers.
    report_name = str(data.get("report") or DEFAULT_REPORT)
    report = ROOT / report_name
    if not report.exists():
        fail(f"missing {report.relative_to(ROOT)}")
    else:
        text = report.read_text()
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
                    f"{report.relative_to(ROOT)} from the ratchet JSON"
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
