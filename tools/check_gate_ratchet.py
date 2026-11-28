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
`measured_on` commit, so a stale report cannot claim a green gate. The default is
the W10 FINAL report; older baselines name their own report in the JSON.

The hosted CI job runs this plus the Python/tooling checks. The Godot gates
themselves need the private extract (`extracted/`, `game/assets/`) and run
locally.
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RATCHET = ROOT / "tools" / "gate_ratchet.json"
DEFAULT_REPORT = "docs/reports/final-20261127.md"

# Runner gate logs (and the mechanically captured poststamp log) open with
# `STARTED: <iso>` and close with `FINISHED: <iso>`. A committed artifact whose
# finish predates its start, or whose file mtime predates its start, was
# assembled by hand rather than measured; the evidence chain rejects it.
STARTED_RE = re.compile(r"^STARTED:\s*(\S+)\s*$", re.MULTILINE)
FINISHED_RE = re.compile(r"^FINISHED:\s*(\S+)\s*$", re.MULTILINE)

# The poststamp artifact is a static evidence log that asserts the ratchet PASS.
# A bare `GATE_RATCHET: PASS` line is not proof; require the checker's own real
# output, bound to the ratchet's measured_on, and a body long enough to be that
# output. The current real artifact is 375 lines / 364 PASS lines; a 122-line
# stub or a marker-only body must fail.
POSTSTAMP_MIN_LINES = 300
POSTSTAMP_MIN_PASS = 300

# The three large gate logs keep their summary/footer even when gutted. Pin a
# minimum size so a 10-line e2e stub cannot pass on a matching summary and an
# allowlisted ERROR count. Current sizes: e2e ~4.3k, run_tests ~3.6k, a2 ~250.
LARGE_LOG_MIN_LINES = {"e2e": 4000, "run_tests": 3000, "e2e_a2": 200}


class DuplicateKeyError(ValueError):
    """Raised when the ratchet JSON repeats a key (json's last-wins is unsafe)."""

    def __init__(self, key: str) -> None:
        self.key = key
        super().__init__(key)


def _no_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    out: dict = {}
    for key, value in pairs:
        if key in out:
            raise DuplicateKeyError(key)
        out[key] = value
    return out


def _path_is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except (ValueError, OSError):
        return False


def safe_join_under(root: Path, base: Path, name: str) -> Path | None:
    """Join `name` under `root`/`base`, rejecting absolute and `..` escapes."""
    raw = str(name)
    if raw.startswith(("/", "\\", "~")):
        return None
    if ".." in Path(raw).parts:
        return None
    candidate = root / raw if "/" in raw else base / raw
    if not _path_is_under(candidate, root):
        return None
    return candidate


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
    # P0b parity tier p2: authored-data provenance. The W10-P2 data wave fixed
    # the last expected failure (civilian pants albedo), so expected_fail,
    # expected_delta and fixed are now exact zeros (`zero_groups`), not recorded
    # measurements. `unexpected_fail=0` remains part of the pattern.
    "e2e_p2": {
        "command": "tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=p2",
        "pattern": lambda g: (
            r"P2_SUMMARY: expected_fail=(\d+) expected_delta=(\d+) "
            r"fixed=(\d+) unexpected_fail=0"
        ),
        "minimums": [],
        "zero_groups": (
            (1, "expected_fail"),
            (2, "expected_delta"),
            (3, "fixed"),
        ),
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
    # fails here before any capture time is spent. Each wave records its dry-run
    # under its own evidence dir via P0B_EVIDENCE_DIR (default stays the P0b path).
    "p0b_capture": {
        "command": (
            "P0B_EVIDENCE_DIR=docs/reports/logs/final "
            "build/qa/p0b_capture.sh --dry-run && "
            "build/qa/p0b_roi_stats.py --validate-manifest "
            "docs/reports/logs/final/dry-run/manifest.json"
        ),
        "pattern": lambda g: r"P0B_MANIFEST_OK [^\n]*poses=(\d+) dry_run=true",
        "minimums": [(1, "poses")],
        "passes_key": None,
    },
    # Phase 0a/0b port capture self-test: the four-pose audio-tap fallback,
    # manifest round-trip, FOV and settle-count rejection. Phase 1/2 adds the
    # seventh pose and raises the measured count 21 -> 23.
    "p0b_capture_self_test": {
        "command": "P0B_EVIDENCE_DIR=docs/reports/logs/final build/qa/p0b_capture.sh --self-test",
        "pattern": lambda g: r"P0B_SELFTEST PASS checks=(\d+) fails=0",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    # Phase 0a/0b route self-test: both QA wrappers must parse, then the
    # staged-route runner's headless table/schema/audio self-test must pass.
    # The floor is the measured check count (62); the PASS literal is part of
    # the pattern so a probe that silently drops checks cannot satisfy the gate.
    "p0b_route_self_test": {
        "command": (
            "bash -n build/qa/p0b_route.sh && "
            "bash -n build/qa/p0b_live_capture.sh && "
            "P0B_ROUTE_EVIDENCE_DIR=docs/reports/logs/final "
            "build/qa/p0b_route.sh --self-test"
        ),
        "pattern": lambda g: r"P0B_ROUTE_SELFTEST PASS checks=(\d+) fails=0",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    # W10-P2/P3/P5 suites and probes. Each prints a stable numeric summary, so
    # the measured count is a floor (a suite may add checks, never drop them).
    # Cream suite 119 is GREEN now; `expected_fail=0` is in the literal pattern
    # because the old RED proof is retired.
    "test_w10a2_cream": {
        "command": "tools/godot --headless --path game --script res://tests/test_w10a2_cream.gd",
        "pattern": lambda g: r"CREAM_PROOF: GREEN passes=(\d+) expected_fail=0",
        "minimums": [(1, "passes")],
        "passes_key": None,
    },
    "test_audio_control": {
        "command": "tools/godot --headless --path game --script res://tests/test_audio_control.gd",
        "pattern": lambda g: r"AUDIO_CONTROL_SUMMARY: fails=0 checks=(\d+)",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    # W11-A VO director (suite 122): the authored 645-line index, guard
    # transitions, cooldowns/priority and the zero-media refusal.
    "test_vo_director": {
        "command": "tools/godot --headless --path game --script res://tests/test_vo_director.gd",
        "pattern": lambda g: r"VO_DIRECTOR_SUMMARY: fails=0 checks=(\d+)",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    # P4.1a/b authored auto-exposure (suite 123): the model/meter data is pinned
    # by its own log; the AEM model block is no longer PENDING after the regen.
    "probe_auto_exposure": {
        "command": "tools/godot --headless --path game --script res://tests/probe_auto_exposure.gd",
        "pattern": lambda g: r"AEM_PROBE: fails=0 passed=(\d+)",
        "minimums": [(1, "passed")],
        "passes_key": None,
    },
    # P4.1 IBL cubemaps (suite 124): face mapping + CPU cosine irradiance with
    # the authored payload present (no PENDING block after the regen).
    "probe_cubemap": {
        "command": "tools/godot --headless --path game --script res://tests/probe_cubemap.gd",
        "pattern": lambda g: r"CUBEMAP_PROBE: fails=0 passed=(\d+)",
        "minimums": [(1, "passed")],
        "passes_key": None,
    },
    "probe_p5_ui": {
        "command": "tools/godot --headless --path game --script res://tests/probe_p5_ui.gd",
        "pattern": lambda g: r"P5_UI PASS checks=(\d+)",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    "probe_den_spawn": {
        "command": "tools/godot --headless --path game --script res://tests/probe_den_spawn.gd",
        "pattern": lambda g: r"DEN_SPAWN PASS checks=(\d+) fails=0",
        "minimums": [(1, "checks")],
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
    # P4.4 landscape mask A/B (7 checks): the shipped `vis > 0.5` discard,
    # the diagnostic switch and the safe-room gap data assertion.
    "probe_landscape_mask": {
        "command": (
            "tools/godot --headless --path game --script res://tests/probe_landscape_mask.gd"
        ),
        "pattern": lambda g: r"LANDSCAPE_MASK_SUMMARY: PASS fails=0 checks=(\d+)",
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
        "minimums": [(1, "maps"), (5, "coverage_ppm")],
        "zero_groups": ((3, "dropped"),),
        "exact_groups": ((4, "planar_skipped"),),
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
    # N-P1/N-P2 authored navmesh runtime: 80 links, door state rule and the
    # negative controls. The wrapper takes the Godot lock itself.
    "nav_runtime_probe": {
        "command": "build/qa/nav_runtime_probe.sh",
        "pattern": lambda g: r"NAV_RUNTIME_PROBE checks=(\d+) fails=0",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    "string_audit": {
        "command": "make string-audit",
        "pattern": lambda g: (
            r"UI_STRINGS total=(\d+) routed=(\d+) authored=(\d+) "
            r"routed_authored=(\d+) invented=(\d+)"
        ),
        "minimums": [(2, "routed"), (3, "authored")],
        # `invented` is a documented ceiling (112), not a floor: it may shrink
        # but a new invented string must be reviewed, not silently accepted.
        "maximums": [(5, "invented")],
        "passes_key": None,
    },
    # W10-A literal-grep gate: both hit counts are exact zeros. This binds the
    # numbers to the ratchet; the PROBE_GATES marker alone only proved the line.
    "literal_greps": {
        "command": "make check-greps",
        "pattern": lambda g: (
            r"LITERAL_GREPS PASS code_hits=(\d+) ui_rating_literals=(\d+)"
        ),
        "minimums": [],
        "zero_groups": ((1, "code_hits"), (2, "ui_rating_literals")),
        "passes_key": None,
    },
    # W10-A D9: only exit 124 (the timeout kill) and a clean scan pass.
    "runtime_smoke": {
        "command": "build/qa/runtime_smoke.sh 90",
        "pattern": lambda g: (
            r"RUNTIME_SMOKE_SCAN PASS exit=124 errors=(\d+) .*mission_ready=(\d+) reason=ok"
        ),
        "minimums": [(2, "mission_ready")],
        "zero_groups": ((1, "errors"),),
        "passes_key": None,
    },
    # Phase 3 §2.5.2: numeric floors for the gates that previously had only an
    # exit code or a bare marker. Every gate `build/qa/run_final_gates.sh`
    # invokes now has a bound floor here or a marker in PROBE_GATES.
    "probe_guard_positions_guildhall": {
        "command": "tools/godot --headless --path game --script res://tests/probe_guard_positions.gd",
        "pattern": lambda g: (
            r"GUARD_CHECK PASS map=guildhall order=2 guards=(\d+) "
            r"buckets=(\d+)/(\d+) lounge=(\d+) lounge_marker=C_20 "
        ),
        "minimums": [
            (1, "guards"),
            (2, "bucket_hit"),
            (3, "bucket_total"),
            (4, "lounge"),
        ],
        "passes_key": None,
    },
    "probe_guard_positions_old_manor": {
        "command": "tools/godot --headless --path game --script res://tests/probe_guard_positions.gd -- --map=old_manor --order=3",
        "pattern": lambda g: (
            r"GUARD_CHECK PASS map=old_manor order=3 guards=(\d+) "
            r"buckets=(\d+)/(\d+) lounge=(\d+) lounge_marker=- "
        ),
        "minimums": [
            (1, "guards"),
            (2, "bucket_hit"),
            (3, "bucket_total"),
        ],
        "zero_groups": ((4, "lounge"),),
        "passes_key": None,
    },
    "probe_niagara": {
        "command": "tools/godot --headless --path game --script res://tests/probe_niagara.gd",
        "pattern": lambda g: (
            r"NIAGARA_PROBE files=(\d+) authored=(\d+) active=(\d+) "
            r"skipped=(\d+) systems=(\d+) "
        ),
        "minimums": [
            (1, "files"),
            (2, "authored"),
            (3, "active"),
            (5, "systems"),
        ],
        "passes_key": None,
    },
    "beam_geometry": {
        "command": "tools/godot --headless --path game --script res://tests/test_beam_geometry.gd",
        "pattern": lambda g: r"loader applied the beam fix (\d+) times",
        "minimums": [(1, "cards")],
        "passes_key": None,
    },
    # `make test-producers` + the parse_nav fixture. Each producer suite has an
    # exact summary line, and the seven nav cases are bound to their exact case
    # names (not a bare `^PASS`, which an unrelated added line could inflate).
    "producer_tests": {
        "command": "make test-producers && python3 build/qa/test_parse_nav.py",
        "pattern": lambda g: (
            r"STEALTHBALL_ARRAY_TEST PASS checks=(\d+)[\s\S]*"
            r"UI_PIXEL_STATS_TEST PASS checks=(\d+)[\s\S]*"
            r"PRODUCER_TESTS PASS"
        ),
        "minimums": [(1, "stealthball_checks"), (2, "ui_pixel_checks")],
        "count_patterns": [
            (
                r"(?m)^PASS (?:positive merge \+ per-map areas|missing supported_areas|"
                r"area 63 is not Default|7-vertex poly|NavArea_Null poly|"
                r"missing nav_data_config|one-way direction)$",
                "nav_checks",
            )
        ],
        "passes_key": None,
    },
    "probe_device_meshes": {
        "command": "tools/godot --headless --path game --script res://tests/probe_device_meshes.gd",
        "pattern": lambda g: (
            r"TURRET_PROBE PASS checks=(\d+) actors=(\d+) "
            r"visible_parts=(\d+) hidden_parts=(\d+)"
        ),
        "minimums": [
            (1, "checks"),
            (2, "actors"),
            (3, "visible_parts"),
        ],
        # hidden_parts is an exact-zero pin, not a floor: one hidden part is a
        # regression even though 1 >= 0.
        "zero_groups": ((4, "hidden_parts"),),
        "passes_key": None,
    },
    "probe_gc_destruction": {
        "command": "tools/godot --headless --path game --script res://tests/probe_gc_destruction.gd",
        "pattern": lambda g: r"GC_PROBE checks=(\d+) fails=0",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    "test_gc_break_trigger": {
        "command": "tools/godot --headless --path game --script res://tests/test_gc_break_trigger.gd",
        "pattern": lambda g: r"GC_TRIGGER checks=(\d+) fails=0",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    "test_w10a2_civilian": {
        "command": "tools/godot --headless --path game --script res://tests/test_w10a2_civilian.gd",
        "pattern": lambda g: r"W10A2_CIV_SUMMARY: fails=0 passed=(\d+) total=(\d+)",
        "minimums": [(1, "passed"), (2, "total")],
        "equal_groups": (1, 2),
        "passes_key": None,
    },
    "test_w10a2_guard_placement": {
        "command": "tools/godot --headless --path game --script res://tests/test_w10a2_guard_placement.gd",
        "pattern": lambda g: r"GUARD_PLACEMENT_SUMMARY: fails=0",
        "minimums": [],
        "passes_key": "passes",
    },
    "probe_geometry_placement": {
        "command": "tools/godot --headless --path game --script res://tests/probe_geometry_placement.gd",
        "pattern": lambda g: (
            r"GEOM_PROBE checks=(\d+) fails=0 pending_regeneration=(\d+)"
        ),
        "minimums": [(1, "checks")],
        # pending_regeneration is an exact-zero pin: any positive value is a
        # regeneration backlog, not a floor to exceed.
        "zero_groups": ((2, "pending_regeneration"),),
        "passes_key": None,
    },
    "test_capture_p5_filter": {
        "command": "build/qa/test_capture_p5_ui_filter.sh",
        "pattern": lambda g: r"CAPTURE_P5_FILTER_TEST PASS checks=(\d+)",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    "p0b_capture_dry_run": {
        "command": "P0B_EVIDENCE_DIR=docs/reports/logs/final build/qa/p0b_capture.sh --dry-run",
        "pattern": lambda g: r"P0B_DRY_RUN [^\n]*poses=(\d+)",
        "minimums": [(1, "poses")],
        "passes_key": None,
    },
    "p0b_kf27_reference": {
        "command": "build/qa/p0b_roi_stats.py --port docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg --pose upper_foyer --reference-only",
        "pattern": lambda g: r"P0B_KF27_REF pose=upper_foyer met=(\d+)/(\d+)",
        "minimums": [(1, "met_num"), (2, "met_den")],
        "passes_key": None,
    },
    "runtime_smoke_scan": {
        "command": "build/qa/test_runtime_smoke_scan.sh",
        "pattern": lambda g: r"RUNTIME_SMOKE_SCAN_TEST PASS checks=(\d+) fails=0",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    # Phase 3 test-manifest: every game/tests/**/*.gd is reachable from
    # run_tests.gd, an E2E tier or the final runner, or is an explicit retired
    # entry. `tracked`/`retired` are floors (a new test must be classified;
    # dropping a retired entry must be reviewed); `orphans` is an exact zero.
    "gate_manifest": {
        "command": "python3 build/qa/gate_manifest.py",
        "pattern": lambda g: (
            r"GATE_MANIFEST: tracked=(\d+) reachable=(\d+) retired=(\d+) orphans=(\d+)"
        ),
        "minimums": [(1, "tracked"), (3, "retired")],
        "zero_groups": ((4, "orphans"),),
        "passes_key": None,
    },
    # Phase 3 engine-error ceiling scan. The allowlist and the 33/2/482
    # ceilings/minimum totals live in build/qa/e2e_errscan.sh + its allowlist;
    # the ceilings are pinned in gate_ratchet.json too, `new` (an unlisted
    # ERROR: message) is an exact zero, and the actual counts must stay at or
    # above the tamper minima (e2e 31, e2e_a2 0, run_tests 482).
    "e2e_errscan": {
        "command": "bash build/qa/e2e_errscan.sh --logdir docs/reports/logs/final",
        "pattern": lambda g: (
            r"E2E_ERRSCAN PASS e2e=(\d+)/(\d+) e2e_a2=(\d+)/(\d+) "
            r"run_tests=(\d+)/(\d+) new=(\d+)"
        ),
        "minimums": [(1, "e2e_min"), (3, "e2e_a2_min"), (5, "run_tests_min")],
        "exact_groups": [
            (2, "e2e_ceiling"),
            (4, "e2e_a2_ceiling"),
            (6, "run_tests_ceiling"),
        ],
        "zero_groups": ((7, "new"),),
        "passes_key": None,
    },
    # W5B/W6L roof collision policy, run under both loader modes. Each mode
    # prints its own `fails=0` summary; the wrapper marker proves both ran.
    "test_roof_collision": {
        "command": (
            "TAT2_COLLISION=authored tools/godot --headless --path game "
            "--script res://tests/test_roof_collision.gd && "
            "TAT2_COLLISION=aabb tools/godot --headless --path game "
            "--script res://tests/test_roof_collision.gd"
        ),
        "pattern": lambda g: (
            r"ROOF_COLLISION_SUMMARY: fails=0[\s\S]*"
            r"ROOF_COLLISION_SUMMARY: fails=0[\s\S]*"
            r"ROOF_COLLISION_MODES PASS authored=0 aabb=0"
        ),
        "minimums": [],
        "count_patterns": [(r"(?m)^PASS:", "checks")],
        "passes_key": None,
    },
    # W9-P2 B3 Den telescope/west-window probe.
    "probe_den_window": {
        "command": "tools/godot --headless --path game --script res://tests/probe_den_window.gd",
        "pattern": lambda g: r"(?m)^DEN_WINDOW PASS checks=(\d+)$",
        "minimums": [(1, "checks")],
        "passes_key": None,
    },
    # P4.2 mirror-split data test (default fast Guildhall_Geometry gate).
    "probe_mirror_split": {
        "command": "tools/godot --headless --path game --script res://tests/probe_mirror_split.gd",
        "pattern": lambda g: (
            r"(?m)^MIRROR_DATA_SUMMARY: fails=0 checks=(\d+) mode=geometry$"
        ),
        "minimums": [(1, "checks")],
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
    # W9-P4 S1 shadow trace: the probe refuses to run unless the interpreter is
    # enabled, so the command pins TAT2_STATETREE=shadow explicitly.
    "probe_statetree_shadow": (
        "PROBE PASS fails=0",
        "TAT2_STATETREE=shadow tools/godot --headless --path game --script res://tests/probe_statetree_shadow.gd",
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
    # Phase 1/2 integration: producer unit tests and the P5 capture filter.
    "producer_tests": (
        "PRODUCER_TESTS PASS",
        "make test-producers && python3 build/qa/test_parse_nav.py && echo PRODUCER_TESTS PASS",
    ),
    "test_capture_p5_filter": (
        "CAPTURE_P5_FILTER_TEST PASS checks=5",
        "build/qa/test_capture_p5_ui_filter.sh",
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
    # P0b capture instruments: the tracked KF27 reference frame is scored with
    # the same criteria the port ROI script applies. The headless self-test now
    # has a numeric floor in LOG_GATES (checks=23).
    "p0b_kf27_reference": (
        "P0B_KF27_REF pose=upper_foyer met=9/9",
        "build/qa/p0b_roi_stats.py --port docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg --pose upper_foyer --reference-only",
    ),
    # The ratchet gate itself. It cannot bind to the runner's in-run
    # `gate_ratchet.log`: the runner truncates that file while opening the gate,
    # *before* this checker runs, so a self-read would be circular. It binds to
    # the static tracked `gate_ratchet_poststamp.log` (a real `make gate-ratchet`
    # PASS output) instead. The in-run gate is enforced by its exit code.
    "gate_ratchet": (
        "GATE_RATCHET: PASS",
        "make gate-ratchet",
    ),
}

# --- runner <-> ratchet binding self-check --------------------------------
# Every gate `build/qa/run_final_gates.sh` invokes must be bound here to the
# ratchet key(s) that prove it. This is a committed assertion, not a count
# derived at runtime: deleting a runner gate, deleting a binding, pointing a
# binding at the wrong log, or adding an unbound gate fails before the full
# suite runs (the checker parses the runner; see `check_runner_bindings`).
#
# `gate_ratchet` maps to no in-run key because the runner truncates
# `$OUT/gate_ratchet.log` *before* this checker reads it; the ratchet binds the
# static tracked `gate_ratchet_poststamp.log` instead (STATIC_BINDINGS below),
# and the in-run gate is enforced by its exit code.
EXPECTED_RUNNER_GATE_COUNT = 58
RUNNER_PATH = ROOT / "build/qa" / "run_final_gates.sh"
RUNNER_GATE_BINDINGS: dict[str, tuple[str, ...]] = {
    "gate_manifest": ("gate_manifest",),
    "compile": ("compile",),
    "run_tests": ("run_tests",),
    "m2": ("m2",),
    "probe_p1_safe": ("probe_p1_safe",),
    "probe_p1_doors": ("probe_p1_doors",),
    "probe_p1_beams": ("probe_p1_beams",),
    "probe_landscape_mask": ("probe_landscape_mask",),
    "probe_p1_ward": ("probe_p1_ward",),
    "probe_p1_street": ("probe_p1_street",),
    "probe_guard_positions_guildhall": ("probe_guard_positions_guildhall",),
    "probe_guard_positions_old_manor": ("probe_guard_positions_old_manor",),
    "probe_collision_authored": ("probe_collision", "probe_collision_maps"),
    "probe_lock_inventory": ("lock_inventory",),
    "nav_runtime_probe": ("nav_runtime_probe",),
    "probe_niagara": ("probe_niagara",),
    "probe_statetree_shadow": ("probe_statetree_shadow",),
    "probe_door_walk": ("probe_door_walk",),
    "probe_viewmodel_truth": ("probe_viewmodel_truth",),
    "probe_geometry_placement": ("probe_geometry_placement",),
    "probe_mirror_split": ("probe_mirror_split",),
    "probe_blackjack_race": ("probe_blackjack_race",),
    "probe_device_meshes": ("probe_device_meshes",),
    "probe_gc_destruction": ("probe_gc_destruction",),
    "test_gc_break_trigger": ("test_gc_break_trigger",),
    "test_w10a2_civilian": ("test_w10a2_civilian",),
    "test_w10a2_guard_placement": ("test_w10a2_guard_placement",),
    "test_beam_geometry": ("beam_geometry",),
    "test_roof_collision": ("test_roof_collision",),
    "probe_leak": ("probe_leak",),
    "e2e": ("e2e",),
    "e2e_a2": ("e2e_a2",),
    "e2e_p2": ("e2e_p2",),
    "e2e_errscan": ("e2e_errscan",),
    "parity_only": ("parity_only",),
    "test_w10a2_cream": ("test_w10a2_cream",),
    "test_audio_control": ("test_audio_control",),
    "test_vo_director": ("test_vo_director",),
    "probe_auto_exposure": ("probe_auto_exposure",),
    "probe_cubemap": ("probe_cubemap",),
    "probe_p5_ui": ("probe_p5_ui",),
    "test_capture_p5_filter": ("test_capture_p5_filter",),
    "probe_den_spawn": ("probe_den_spawn",),
    "probe_den_window": ("probe_den_window",),
    "p0b_capture_dry_run": ("p0b_capture_dry_run",),
    "p0b_capture_self_test": ("p0b_capture_self_test",),
    "p0b_manifest_validate": ("p0b_capture",),
    "p0b_kf27_reference": ("p0b_kf27_reference",),
    "p0b_route_self_test": ("p0b_route_self_test",),
    "runtime_smoke": ("runtime_smoke",),
    "runtime_smoke_scan": ("runtime_smoke_scan",),
    "producer_tests": ("producer_tests",),
    "string_audit": ("string_audit",),
    "literal_greps": ("literal_greps",),
    "audit": ("audit",),
    "texture_cap": ("texture_cap",),
    "perf_guard": ("perf_guard",),
    "gate_ratchet": (),
}
# Ratchet keys that are deliberately bound to a static tracked log instead of a
# runner gate's `$OUT` log.
STATIC_BINDINGS: dict[str, str] = {
    "gate_ratchet": (
        "the runner truncates gate_ratchet.log before this checker reads it; "
        "bound to the static tracked gate_ratchet_poststamp.log run"
    ),
}

RUNNER_GATE_RE = re.compile(
    r'^\s*(?:gate|gate_marker|gate_marker_re)\s+([a-z0-9_]+)\s+"\$OUT/([A-Za-z0-9_.-]+)"',
    re.MULTILINE,
)


def check_runner_bindings(
    evidence: dict, binding_keys: set[str], log_dir: Path
) -> None:
    """Assert the runner gate set and the ratchet binding set agree."""
    if not RUNNER_PATH.is_file():
        fail(f"missing runner {RUNNER_PATH.relative_to(ROOT)}")
        return
    text = RUNNER_PATH.read_text()
    runner: dict[str, str] = {}
    for match in RUNNER_GATE_RE.finditer(text):
        name, log_name = match.group(1), match.group(2)
        if name in runner:
            fail(f"runner declares gate {name!r} more than once")
        runner[name] = log_name

    if len(runner) != EXPECTED_RUNNER_GATE_COUNT:
        fail(
            f"runner declares {len(runner)} gates, expected "
            f"{EXPECTED_RUNNER_GATE_COUNT}; a gate was deleted or added without "
            "updating check_gate_ratchet.py"
        )

    declared = set(RUNNER_GATE_BINDINGS)
    parsed = set(runner)
    for name in sorted(parsed - declared):
        fail(
            f"runner gate {name!r} has no binding in check_gate_ratchet.py "
            "(add it to RUNNER_GATE_BINDINGS with its ratchet key)"
        )
    for name in sorted(declared - parsed):
        fail(
            f"RUNNER_GATE_BINDINGS names {name!r} but the runner no longer "
            "declares that gate"
        )

    for name in sorted(parsed & declared):
        for key in RUNNER_GATE_BINDINGS[name]:
            if key not in binding_keys:
                fail(
                    f"runner gate {name!r} maps to unknown ratchet key {key!r} "
                    "(no LOG_GATES/PROBE_GATES binding)"
                )
                continue
            log_name = evidence.get(key)
            if not log_name:
                # The main loop already reports the missing evidence entry.
                continue
            expected_log = Path(str(log_name)).name
            if expected_log != runner[name]:
                fail(
                    f"runner gate {name!r} writes {runner[name]!r} but ratchet "
                    f"key {key!r} binds {expected_log!r}"
                )

    used = {key for keys in RUNNER_GATE_BINDINGS.values() for key in keys}
    for key in sorted(binding_keys - used - set(STATIC_BINDINGS)):
        fail(
            f"ratchet binding {key!r} is not bound to any runner gate "
            "and is not a declared static binding"
        )
    for key in sorted(set(STATIC_BINDINGS) - binding_keys):
        fail(f"static binding {key!r} is not a LOG_GATES/PROBE_GATES key")

    # The static bindings must still exist and be inside the evidence dir.
    for key in sorted(STATIC_BINDINGS):
        log_name = evidence.get(key)
        if not log_name:
            continue
        path = safe_join_under(ROOT, log_dir, str(log_name))
        if path is None:
            fail(f"static binding {key!r} path {log_name!r} escapes the repo root")
        elif not path.is_file():
            fail(f"static binding {key!r} points at a missing log {path}")

    print(
        f"PASS: runner/binding self-check {len(runner)} gates, "
        f"{len(binding_keys)} ratchet bindings"
    )


fails: list[str] = []


def fail(msg: str) -> None:
    fails.append(msg)
    print(f"FAIL: {msg}")


def main() -> int:
    generating_poststamp = "--generating-poststamp" in sys.argv[1:]
    unknown = [arg for arg in sys.argv[1:] if arg != "--generating-poststamp"]
    if unknown:
        print(f"FAIL: unknown argument(s) {unknown!r}")
        return 1
    if not RATCHET.exists():
        print(f"FAIL: missing {RATCHET.relative_to(ROOT)}")
        return 1
    try:
        data = json.loads(RATCHET.read_text(), object_pairs_hook=_no_duplicate_keys)
    except DuplicateKeyError as exc:
        print(
            f"FAIL: duplicate key {exc.key!r} in {RATCHET.relative_to(ROOT)} "
            "(last-wins would silently replace a pin)"
        )
        return 1
    except json.JSONDecodeError as exc:
        print(f"FAIL: {RATCHET.relative_to(ROOT)} is not valid JSON: {exc}")
        return 1
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
        group = gates.get(gate)
        if not isinstance(group, dict) or key not in group:
            # Fail closed: a deleted pinned key must never fall through to a
            # -1 default that makes every `captured >= floor` comparison pass.
            fail(
                f"missing pinned key {gate}.{key} in gate_ratchet.json "
                "(fail closed; restore the key or re-measure the gate)"
            )
            return 0
        return int(group[key])

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
    raw_dir = str(evidence.get("dir") or "docs/reports/logs")
    if raw_dir.startswith(("/", "\\", "~")) or ".." in Path(raw_dir).parts:
        fail(f"evidence.dir {raw_dir!r} escapes the repo root")
        log_dir = ROOT / "docs/reports/logs"
    else:
        log_dir = ROOT / raw_dir
        if not _path_is_under(log_dir, ROOT):
            fail(f"evidence.dir {raw_dir!r} escapes the repo root")
            log_dir = ROOT / "docs/reports/logs"

    def evidence_path(log_name: str) -> Path | None:
        return safe_join_under(ROOT, log_dir, str(log_name))

    # Evidence-log timestamp coherence. The runner writes STARTED: before a gate
    # and FINISHED: after it; the file mtime is the final write. EVERY bound log
    # must carry both stamps: a log without them (or whose FINISHED predates
    # STARTED, or whose mtime predates STARTED) is an assembled artifact, not a
    # measurement. When the poststamp log itself is being generated
    # (`--generating-poststamp`), it is skipped here because the checker is
    # reading the previous artifact; a plain run after the mechanical capture
    # validates the new one.
    poststamp_log = str(evidence.get("gate_ratchet") or "")

    def verify_stamps(path: Path, log_name: str) -> None:
        if generating_poststamp and log_name == poststamp_log:
            print(f"SKIP: {log_name} timestamp self-check (generating artifact)")
            return
        text = path.read_text(errors="replace")
        starts = STARTED_RE.findall(text)
        finishes = FINISHED_RE.findall(text)
        if not starts or not finishes:
            fail(
                f"{log_name}: missing stamp pair (both STARTED: and FINISHED: "
                "are required) — an assembled artifact cannot prove a measurement"
            )
            return
        try:
            t0 = datetime.fromisoformat(starts[0])
            t1 = datetime.fromisoformat(finishes[-1])
        except ValueError as exc:
            fail(f"{log_name}: unparseable STARTED/FINISHED stamp ({exc})")
            return
        if t0.timestamp() > t1.timestamp():
            fail(
                f"{log_name}: STARTED {starts[0]} is after FINISHED {finishes[-1]} "
                "— the artifact was assembled, not measured"
            )
            return
        mtime = path.stat().st_mtime
        if mtime < t0.timestamp():
            fail(
                f"{log_name}: mtime {datetime.fromtimestamp(mtime).isoformat()} "
                f"predates STARTED {starts[0]} — the artifact was assembled, not measured"
            )
            return
        print(
            f"PASS: {log_name} stamps coherent (STARTED <= FINISHED, mtime >= STARTED)"
        )

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
        if path is None:
            fail(
                f"evidence.{gate} path {log_name!r} is absolute or contains '..' "
                "(it must stay under the repo root)"
            )
            continue
        if not path.exists():
            fail(
                f"missing gate log {path.relative_to(ROOT)} for {gate!r} — "
                f"run `{command}` and commit the log"
            )
            continue
        text = path.read_text(errors="replace")
        verify_stamps(path, log_name)
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
        for group, key in spec.get("zero_groups", ()):
            captured = int(match.group(group))
            pinned = get(gate, key) if key else 0
            if captured != 0:
                fail(
                    f"{log_name} records {gate} group {group}={captured}, expected 0 — "
                    f"run `{command}` and commit the fresh log"
                )
            elif pinned != 0:
                fail(
                    f"{gate}.{key}={pinned} must be an exact zero, not a floor — "
                    "restore the 0 pin"
                )
            else:
                print(
                    f"PASS: {log_name} records {gate} group {group}=0 "
                    f"(pinned {gate}.{key}=0)"
                )
        # An exact pin: the log value must equal the ratchet value (not a floor).
        for group, key in spec.get("exact_groups", ()):
            captured = int(match.group(group))
            pinned = get(gate, key)
            if captured != pinned:
                fail(
                    f"{log_name} records {gate}.{key}={captured}, expected exactly "
                    f"{pinned} — run `{command}` and commit the fresh log"
                )
            else:
                print(f"PASS: {log_name} records {gate}.{key}={captured} == {pinned}")
        # A maximum pin: the log value may fall but not exceed the ceiling.
        for group, key in spec.get("maximums", ()):
            captured = int(match.group(group))
            ceiling = get(gate, key)
            if captured > ceiling:
                fail(
                    f"{log_name} records {gate}.{key}={captured}, above the ceiling "
                    f"{ceiling} — run `{command}` and commit the fresh log"
                )
            else:
                print(f"PASS: {log_name} records {gate}.{key}={captured} <= {ceiling}")
        # A gate whose log proves N separate cases by one PASS line each (rather
        # than one numeric summary) can bind the case count with a regex.
        for count_re, key in spec.get("count_patterns", ()):
            captured = len(re.findall(count_re, text))
            floor = get(gate, key)
            if captured < floor:
                fail(
                    f"{log_name} records {gate}.{key}={captured}, below the floor "
                    f"{floor} — run `{command}` and commit the fresh log"
                )
            else:
                print(f"PASS: {log_name} records {gate}.{key}={captured} >= {floor}")
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
            floor = get(gate, passes_key)
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
        path = evidence_path(leak_name)
        if path is None:
            fail(f"evidence.probe_leak path {leak_name!r} escapes the repo root")
        elif not path.exists():
            fail(
                f"missing gate log {path.relative_to(ROOT)} for probe_leak — run "
                "`TAT2_NO_DEN_PROBE=1 tools/godot --headless --path game --script res://probe_leak.gd` "
                "and commit the log"
            )
        else:
            text = path.read_text(errors="replace")
            verify_stamps(path, leak_name)
            if "PROBE start" not in text:
                fail(f"{leak_name} is not a probe_leak run (no 'PROBE start')")
            elif re.search(r"leaked at exit|SCRIPT ERROR", text):
                fail(
                    f"{leak_name} contains a leak or script error; the probe must be clean"
                )
            else:
                print(f"PASS: {leak_name} clean")

    for gate, (marker, command) in PROBE_GATES.items():
        if generating_poststamp and gate == "gate_ratchet":
            print("SKIP: gate_ratchet poststamp self-check (generating artifact)")
            continue
        log_name = evidence.get(gate)
        if not log_name:
            fail(
                f"no evidence log named for {gate!r} in gate_ratchet.json "
                f"(add evidence.{gate}); run `{command}` and commit its log"
            )
            continue
        path = evidence_path(log_name)
        if path is None:
            fail(
                f"evidence.{gate} path {log_name!r} is absolute or contains '..' "
                "(it must stay under the repo root)"
            )
            continue
        if not path.exists():
            fail(
                f"missing gate log {path.relative_to(ROOT)} for {gate!r} — "
                f"run `{command}` and commit the log"
            )
            continue
        text = path.read_text(errors="replace")
        verify_stamps(path, log_name)
        if marker not in text:
            fail(f"{log_name} does not contain {marker!r} — run `{command}`")
        elif re.search(r"SCRIPT ERROR", text):
            fail(f"{log_name} contains a SCRIPT ERROR; the probe must be clean")
        else:
            print(f"PASS: {log_name} records {marker}")

    # A gate log that keeps its summary/footer but is otherwise gutted is not a
    # measurement. Pin a minimum size for the three large logs; a 10-line e2e
    # stub fails even if its summary and ERROR count look right.
    for log_name, min_lines in sorted(LARGE_LOG_MIN_LINES.items()):
        filename = f"{log_name}.log"
        lpath = log_dir / filename
        if not lpath.is_file():
            continue  # the evidence loops already fail a missing bound log
        n = len(lpath.read_text(errors="replace").splitlines())
        if n < min_lines:
            fail(
                f"{filename} has {n} line(s), below the pinned {min_lines}-line "
                "minimum — a gutted gate log is not a measurement"
            )
        else:
            print(f"PASS: {filename} has {n} lines >= {min_lines}")

    # The poststamp artifact must carry the checker's real output, not a bare
    # marker, and it must be bound to THIS ratchet: the measured_on lines must
    # equal the ratchet's measured_on, the runner/binding line must name the
    # exact committed counts, and the body must have the structural size of a
    # real run. Skipped while generating (the file is then the previous
    # artifact); a plain run after capture enforces it.
    if not generating_poststamp:
        poststamp_name = evidence.get("gate_ratchet")
        if poststamp_name:
            path = evidence_path(str(poststamp_name))
            if path is not None and path.exists():
                text = path.read_text(errors="replace")
                lines = text.count("\n") + (0 if text.endswith("\n") else 1)
                pass_lines = len(re.findall(r"^PASS:", text, re.MULTILINE))
                measured_lines = re.findall(
                    r"^PASS: measured_on=(\S+)$", text, re.MULTILINE
                )
                report_lines = re.findall(
                    r"^PASS: report names measured_on=(\S+)$", text, re.MULTILINE
                )
                binding_count = len(set(LOG_GATES) | set(PROBE_GATES) | {"probe_leak"})
                expected_binding = (
                    f"PASS: runner/binding self-check "
                    f"{EXPECTED_RUNNER_GATE_COUNT} gates, "
                    f"{binding_count} ratchet bindings"
                )
                expected_coverage = (
                    f"PASS: audit coverage "
                    f"{get('audit', 'coverage_num')}/{get('audit', 'coverage_den')}"
                )
                problems = []
                if measured_lines != [measured_on]:
                    problems.append(
                        f"measured_on lines {measured_lines!r} != [{measured_on!r}]"
                    )
                if report_lines != [measured_on]:
                    problems.append(
                        f"report measured_on lines {report_lines!r} != "
                        f"[{measured_on!r}]"
                    )
                if expected_binding not in text.splitlines():
                    problems.append(f"missing exact line {expected_binding!r}")
                if expected_coverage not in text:
                    problems.append(f"missing {expected_coverage!r}")
                if lines < POSTSTAMP_MIN_LINES:
                    problems.append(f"{lines} line(s) < {POSTSTAMP_MIN_LINES} minimum")
                if pass_lines < POSTSTAMP_MIN_PASS:
                    problems.append(
                        f"{pass_lines} PASS line(s) < {POSTSTAMP_MIN_PASS} minimum"
                    )
                if problems:
                    fail(
                        f"{poststamp_name} is not real checker output bound to "
                        f"measured_on={measured_on}: " + "; ".join(problems)
                    )
                else:
                    print(
                        f"PASS: {poststamp_name} carries real checker output "
                        f"bound to measured_on={measured_on} "
                        f"({lines} lines, {pass_lines} PASS, exact bindings)"
                    )

    # Committed self-check: the runner gate set and the ratchet binding set must
    # agree. This runs before the report check and needs no Godot run, so a gate
    # or binding deleted on one side fails immediately.
    check_runner_bindings(
        evidence,
        set(LOG_GATES) | set(PROBE_GATES) | {"probe_leak"},
        log_dir,
    )

    # The report must quote the ratchet values, so a stale report cannot claim a
    # green gate. Regexes are built from the JSON numbers.
    report_name = str(data.get("report") or DEFAULT_REPORT)
    report = safe_join_under(ROOT, ROOT, report_name)
    if report is None:
        fail(f"report path {report_name!r} is absolute or escapes the repo root")
    elif not report.exists():
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
