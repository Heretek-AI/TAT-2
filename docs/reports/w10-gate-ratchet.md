# W10-A gate ratchet (evidence ledger)

| | |
|---|---|
| wave | W10-A (D6 trace budget, D7 coplanar convex, D8 lock resolution, D9 runtime-smoke scan, D10 traversal fixtures + the evidence hardening) |
| ratchet file | `tools/gate_ratchet.json` |
| evidence directory | `docs/reports/logs/w10/` |
| **measured_on** `29046c8` | **placeholder.** `29046c8` is the W9 tip the wave branched from; the lead re-stamps `measured_on` with the W10-A wave commit after the full serial gate run. |
| checker | `python3 tools/check_gate_ratchet.py` (`make gate-ratchet`) |

This report is the one the checker reads (`tools/gate_ratchet.json:report`). The
exact floor lines below are parsed from the JSON, so the numbers here and in the
ratchet must move together.

## Floors read by the checker (unchanged this wave)

The checker builds its report regexes from the JSON and requires these literal
lines (parsed as `compile | checked / broken`, `run_tests | passes`,
`M2 | passes`, `E2E | passed / total`, `coverage_num / coverage_den`, plus the
`measured_on` SHA):

```
compile | 186 / 0
run_tests | 314
M2 | 12
E2E | 278 / 278
12660 / 12703
measured_on 29046c8
```

These are the W9 tip floors: W10-A adds suites and probes but does not re-baseline
the W9 gate counts. The lead raises them only after the full serial run records
higher numbers (never lowers them). The audit line must match
`Disk-backed content coverage: <num>/<den> … unexpected 0`.

`measured_on` is `29046c8` until the lead re-stamps the wave commit; the checker
requires that exact string in this report.

## Placeholder logs (the lead must overwrite)

`docs/reports/logs/w10/` was seeded with copies of the 13 unchanged-gate logs
from `docs/reports/logs/w9/` (`compile`, `run_tests`, `m2`, `e2e`, `audit`,
`texture_cap`, `perf_guard`, `probe_leak` and the five W9 probes). They are
**placeholders only**: they prove the wiring, not this wave. The lead overwrites
each one with the W10-A run of the same command before pushing. The five
W10-A-owned logs in the same directory were produced by this lane (see
`build/qa/w10/evidence.md`).

## W10-A gates added

| gate | kind | log | floor(s) |
|---|---|---|---|
| `probe_collision` | LOG_GATES | `probe_collision_authored.log` | maps >= 3, coverage_ppm >= 950000, dropped = 0 (recorded; the `COL_MAPS PASS` literal only prints when every map passed) |
| `probe_collision_maps` | PROBE_GATES | `probe_collision_authored.log` | marker `COL_MAPS PASS` |
| `lock_inventory` | LOG_GATES | `probe_lock_inventory.log` | applied >= 154, containers >= 144, door_nodes >= 10 (`state=APPLIED` required) |
| `string_audit` | LOG_GATES | `string_audit.log` | routed >= 306, authored >= 195 |
| `literal_greps` | PROBE_GATES | `literal_greps.log` | marker `LITERAL_GREPS PASS` |
| `runtime_smoke` | LOG_GATES | `runtime_smoke.log` | errors = 0, mission_ready >= 1 (`exit=124`, `reason=ok` required) |

Measured lines this wave:

```
COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0 planar_skipped=2 coverage_ppm=976277
LOCK_INVENTORY runtime: authored=173 raw=363 applied=154 containers=144 door_nodes=10 discarded=209 state=APPLIED
UI_STRINGS total=306 routed=306 authored=195 routed_authored=195 invented=111
LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files=96
RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok
```

Notes on the two shapes the checker cannot express as ">= floor":

* `probe_collision.dropped` is a failure count, but the gate is expressed through
  the `COL_MAPS PASS` literal: the probe prints `PASS` only after every map's
  `COL_MAP_ASSERT` (coverage >= 95 %, dropped == 0, non-zero shapes and placed
  meshes) passed, and exits 1 otherwise. `planar_skipped` is informational (a
  higher count means more coplanar surfaces correctly skipped) and its recorded
  floor is 0 so a data change never reds the ratchet.
* `runtime_smoke.exit` is pinned in the regex (`exit=124`), `errors` is recorded
  as floor 0 and `mission_ready` as floor 1; the `PASS`/`reason=ok` literals are
  the actual enforcement.
* `string_audit.invented = 111` is a **ceiling**, not a floor: the checker only
  supports minimums, so the Makefile's `string-audit` target enforces
  `--max-invented 111`; the ratchet records the number so a change is visible.

## Commands that regenerate each log

```bash
tools/godot --headless --path game --script res://tests/probe_collision_authored.gd
tools/godot --headless --path game --script res://tests/probe_lock_inventory.gd
tools/godot --headless --path game --script res://tests/test_w9p4_statetree.gd
python3 build/qa/w9/p3_string_audit.py --min-routed 306 --min-authored 195 --max-invented 111
python3 tools/check_literal_greps.py
build/qa/runtime_smoke.sh 90
```

`make audit` now includes `string-audit` and `check-greps`; `runtime-smoke` remains
a separate local target (it needs the private extract and an engine run) but its
log is a ratchet gate.
