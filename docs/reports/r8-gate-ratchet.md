# R8 gate ratchet — re-measured on `e3678be` (W9-P0, 2026-11-25)

The gate ratchet still pinned the W7 tree (`6760dd0`: 120 scripts, 278 tests, M2 11,
E2E 278). This is the R8 tree re-measured end to end, with the fresh logs committed
under [`docs/reports/logs/r8/`](logs/r8/) and the checker changed from exact
equality to **minimums** so a wave that adds scripts or tests raises the numbers
instead of breaking the gate.

- **Tree:** `e3678be` (R8 merged) + the W9-P0 tooling in this branch. **No `game/`
  file changed** by W9-P0; the only non-log edits are `tools/gate_ratchet.json`,
  `tools/check_gate_ratchet.py`, `tools/consumer_allowlist.json` and the tracked
  `build/qa/w9_*` harness.
- **Method:** every gate was run serially on this tree, one Godot at a time under
  `/tmp/opencode/tat2-godot.lock`. Commands are the ones in `tools/check_gate_ratchet.py`
  and `AGENTS.md`; each log is the whole stdout+stderr of that command.

## Floors (minimum) and the measurement that proves them

| Gate | Floor (ratchet) | Measured on `e3678be` | W7 floor it replaces |
|---|---|---|---|
| compile | 152 / 0 | 152 / 0 | 120 / 0 |
| run_tests | 301 | 301 PASS, `SUMMARY: fails=0` | 278 |
| M2 | 12 | 12 PASS, `M2_SUMMARY: fails=0` | 11 |
| E2E | 278 / 278 | `fails=0 passed=278 total=278` | 278 / 278 |
| E2E tier 1 | 117 (reference) | `fails=0 passed=117 total=117` | 117 |
| audit coverage | 12660 / 12703 | 12,660 / 12,703 (99.7 %), unexpected 0 | 12,657 / 12,703 |
| texture cap | 797 / 1 / 0 | capped 797, alpha-critical 1, offenders 0 | 773 / 1 / 0 |
| perf guard | 78 | `PERF_GUARD_TEST PASS checks=78 fails=0` | 78 |
| door walk | `DOORWALK PASS` | `DOORWALK PASS` | — |
| viewmodel truth | `VIEWMODEL_TRUTH PASS` | `VIEWMODEL_TRUTH PASS` | — |
| Niagara | `NIAGARA_PROBE PASS` | `NIAGARA_PROBE PASS` (1,048 active / 810 params) | — |
| blackjack | `BLACKJACK_PROBE PASS` | `BLACKJACK_PROBE PASS` | — |
| geometry | `GEOM_PROBE PASS` | `GEOM_PROBE PASS checks=7 fails=0` | — |
| probe_leak | `PROBE start`, clean | `PROBE start`, `players=0` after free, no leak | — |

The compile, `run_tests`, M2 and E2E summaries are compared with `>=`; `broken`,
`fails`, `unexpected` and `offenders` are exact zeros; `e2e.passed` must equal
`e2e.total`; audit coverage must satisfy `num <= den`.

## Two gate defects found and fixed

1. **The consumer allowlist had rotted.** `make audit` failed on this tree with
   `STALE RULE tables/Art/UI/Icons/**` and `STALE RULE vfx/*.json`: both files are
   now read at runtime (`game/src/ui/input_glyphs.gd:19` loads
   `DT_InputKeysToGlyphs.json`; `game/src/core/vfx/niagara_library.gd:19` loads
   `vfx/systems.json`), so the `blocked_on_team T06` and `tests_only` entries no
   longer had an unconsumed target. Removing the two entries is the fix the audit
   itself prescribes; no consumer check was weakened. Red: `CONSUMER AUDIT FAILED:
   2 failure(s)`. Green: `CONSUMER AUDIT PASS`, `AUDIT PASS`.
2. **The audit summary string drifted.** `tools/manifest_audit.py:2049` prints
   `Disk-backed content coverage:`; the checker still matched the older
   `Disk-backed coverage:`. The pattern now matches the producer.

The coverage moved 12,657 → 12,660 because three previously allowlisted missing
files now resolve through the exported-name rename path (`allowlisted missing 46 →
43`), which is exactly what `tools/audit_baseline.json` records
(`disk_missing_allowlisted: 43`). Texture `capped` moved 773 → 797 because R8's
material producers added 24 over-cap textures to `materials.json`; `offenders`
stayed 0 and the 261 out-of-scope over-cap count is unchanged.

## Logs committed (the files the checker reads)

```text
docs/reports/logs/r8/compile.log                   scripts checked: 152, broken: 0
docs/reports/logs/r8/run_tests.log                 301 PASS, SUMMARY: fails=0
docs/reports/logs/r8/m2.log                        12 PASS, M2_SUMMARY: fails=0
docs/reports/logs/r8/e2e.log                       SUMMARY: fails=0 passed=278 total=278
docs/reports/logs/r8/e2e_tier1.log                 SUMMARY: fails=0 passed=117 total=117
docs/reports/logs/r8/audit.log                     AUDIT PASS, 12,660/12,703
docs/reports/logs/r8/texture_cap.log               capped 797, alpha-critical 1, offenders 0
docs/reports/logs/r8/perf_guard.log                PERF_GUARD_TEST PASS checks=78 fails=0
docs/reports/logs/r8/probe_door_walk.log           DOORWALK PASS
docs/reports/logs/r8/probe_viewmodel_truth.log     VIEWMODEL_TRUTH PASS
docs/reports/logs/r8/probe_niagara.log             NIAGARA_PROBE PASS
docs/reports/logs/r8/probe_blackjack_race.log      BLACKJACK_PROBE PASS
docs/reports/logs/r8/probe_geometry_placement.log  GEOM_PROBE PASS
docs/reports/logs/r8/probe_leak.log                PROBE start, clean
```

`make gate-ratchet` reads this report (the JSON `report` key) and must find the
floors above and the commit `e3678be` in it; the previous hardcoded
`docs/reports/w7-integration.md` is no longer consulted for this baseline.
