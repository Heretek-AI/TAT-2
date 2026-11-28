# Phase 2.5 baseline — 2026-11-27 (58/58 gates green)

**Status: PASS.** One serial run of `build/qa/run_final_gates.sh` at
`5857589853e43a30339ccc3e2d8cba26c1dde281` completed **58/58 gates exit 0**
in **23m19s** (1399 s), from a clean worktree
(`uncommitted_entries_at_start: 0`). This is the Phase 2.5 gate-integrity
baseline: the three previously carried-forward suites are now real runner
gates, the test manifest and engine-error scan are gates, and the four
restored orphans run in the gun. No GPU/Vulkan/Xvfb step was run, no producer
or `make normalize` was run, and no gate log or ratchet floor was lowered.
The 58/58 measurement remains at `5857589`; the later round-3 commits are
tooling/evidence only (errscan footer + minimum totals, the ratchet
timestamp self-check, and a mechanically captured poststamp log).

| Item | Value |
|---|---|
| run head / measured_on | `5857589` (`5857589853e43a30339ccc3e2d8cba26c1dde281`) |
| branch | `teamwork/20261127-1810-phase3-baseline-run` |
| Godot | `4.7.2.stable.official.ed1daf0bf` |
| host | Linux x86_64, 32 cores (fixed 2026-11-27 host; see §7) |
| wall time | **23m19s** |
| gates | **58/58 exit 0** |
| `make audit` | **PASS** (exit 0, no stamp refresh) |
| `make gate-ratchet` | **PASS** in-run at the old stamp, and **PASS** post-stamp at `measured_on=5857589` |

## 1. Worktree setup

```bash
ln -s /home/john/Projects/TAT-2/extracted extracted
ln -s /home/john/Projects/TAT-2/game/data/generated game/data/generated
ln -s /home/john/Projects/TAT-2/game/assets/ue game/assets/ue
ln -s /home/john/Projects/TAT-2/tools/bin tools/bin   # NEW: git-ignored tool dir
tools/godot --headless --path game --import           # 8m32s
```

**Setup gap (new, recorded for future workers):** the three data symlinks are
not sufficient. `make audit` fails with
`tool version drift: vgmstream: 'vgmstream CLI decoder r2168 (Oct 25 2026)'
-> 'missing'` because `tools/bin/vgmstream/vgmstream-cli` is git-ignored and a
fresh worktree has no `tools/bin/`. Symlinking the shared read-only tool tree
(no write) makes the audit pass. This is recorded in
`.opencode/teamwork/20261127-1810-phase3/OPEN_ISSUES.md`.

## 2. Commands

```bash
bash build/qa/e2e_errscan.sh --logdir docs/reports/logs/final   # pre-full-run check
bash build/qa/run_final_gates.sh                                # 58/58, 23m19s, exit 0
make audit                                                      # exit 0, 8.7 s, no refresh
make gate-ratchet                                               # PASS (post-stamp)
```

The full run wrote `docs/reports/logs/final/` (`final-run.log`,
`final-summary.txt`, one log per gate). The in-run `gate_ratchet.log` is kept
intact; the post-stamp ratchet output is in `gate_ratchet_poststamp.log`.

## 3. Every gate summary (58/58, exit 0)

| Gate | Measured summary |
|---|---|
| gate_manifest | `GATE_MANIFEST: tracked=109 reachable=70 retired=39 orphans=0` |
| compile | 229 / 0 |
| run_tests | 328 PASS / fails=0 (suite 125 contract holes registered) |
| M2 | 12 / 0 |
| P1 safe | `P1_SAFE PASS checks=86 fails=0 skips=0` |
| P1 doors | `P1_DOORS checks=49 fails=0` |
| P1 beams | `P1_BEAMS PASS checks=9 fails=0` |
| landscape mask | `LANDSCAPE_MASK_SUMMARY: PASS fails=0 checks=7` |
| P1 ward | `P1_WARD PASS checks=44` |
| P1 street | `P1_STREET SUMMARY checks=31 fails=0 hard_limits=2` |
| guard Guildhall | `GUARD_CHECK PASS … guards=4 buckets=4/4 lounge=1 lounge_marker=C_20` |
| guard Old Manor | `GUARD_CHECK PASS map=old_manor order=3 guards=4 buckets=4/4` |
| collision | `COL_MAPS PASS maps=3 min_coverage=0.869 dropped=0 planar_skipped=2 coverage_ppm=868852` |
| locks | `applied=162 containers=152 door_nodes=10 state=APPLIED` |
| nav runtime | `NAV_RUNTIME_PROBE checks=70 fails=0` |
| Niagara | `NIAGARA_PROBE PASS` (Guildhall scope: active=219, 39 nodes) |
| StateTree shadow | `PROBE PASS fails=0` (`TAT2_STATETREE=shadow`) |
| door walk | `DOORWALK PASS` |
| viewmodel truth | `VIEWMODEL_TRUTH PASS` |
| geometry placement | `GEOM_PROBE PASS` |
| mirror split | `MIRROR_DATA_SUMMARY: fails=0 checks=39 mode=geometry` |
| blackjack | `BLACKJACK_PROBE PASS fails=0` |
| turret | `TURRET_PROBE PASS checks=11 actors=229 visible_parts=1145 hidden_parts=0` |
| GC | `GC_PROBE checks=52 fails=0` (87 paired owners; 16 static leaves) |
| GC trigger | `GC_TRIGGER checks=21 fails=0` |
| civilian | `W10A2_CIV_SUMMARY: fails=0 passed=23 total=23` |
| guard placement | `GUARD_PLACEMENT_SUMMARY: fails=0` |
| beam geometry | `BEAM_AXIS_TOTAL cards=330 max_axis_err_deg=0.000006 clamped=0`; `fails=0` |
| roof collision | `ROOF_COLLISION_MODES PASS authored=0 aabb=0` (106 checks, both modes) |
| leak | `PROBE start players=0` (clean) |
| E2E | 300 / 300 |
| E2E a2 | `SUMMARY: fails=0 passed=22 total=22` (`static_bookcase_leaves=20`) |
| E2E p2 | `P2_SUMMARY: expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0` (17/17) |
| e2e_errscan | `E2E_ERRSCAN PASS e2e=31/33 e2e_a2=0/2 run_tests=482/482 new=0` |
| parity-only | `PARITY_ONLY_SUMMARY: fails=0 passed=60 rules=11 restoration=11 expansion=0` |
| cream 119 | `CREAM_PROOF: GREEN passes=5 expected_fail=0` |
| audio control 121 | `AUDIO_CONTROL_SUMMARY: fails=0 checks=123` |
| VO director 122 | `VO_DIRECTOR_SUMMARY: fails=0 checks=53` |
| auto-exposure 123 | `AEM_PROBE: fails=0 passed=77` |
| cubemap 124 | `CUBEMAP_PROBE: fails=0 passed=37` |
| P5 UI | `P5_UI PASS checks=54`; `GEM_PAYLOAD present=true: layers=21` |
| capture filter | `CAPTURE_P5_FILTER_TEST PASS checks=5` |
| Den spawn | `DEN_SPAWN PASS checks=9 fails=0` |
| Den window | `DEN_WINDOW PASS checks=34` |
| capture dry-run | `P0B_DRY_RUN … poses=7 schema=tat2.p0b_capture/1` |
| capture self-test | `P0B_SELFTEST PASS checks=23 fails=0` |
| capture manifest | `P0B_MANIFEST_OK poses=7 dry_run=true` |
| KF27 reference | `P0B_KF27_REF pose=upper_foyer met=9/9` (reference-only) |
| route self-test | `P0B_ROUTE_SELFTEST PASS checks=62 fails=0` |
| runtime smoke | `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 mission_ready=1` |
| smoke scan self-test | `RUNTIME_SMOKE_SCAN_TEST PASS checks=29 fails=0` |
| producer tests | `PRODUCER_TESTS PASS` (stealthball 22, UI pixel 15, parse_nav 7) |
| string audit | `UI_STRINGS GATE PASS routed=311 authored=199 invented=112` |
| literal greps | `LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0` |
| audit | `AUDIT PASS` |
| texture cap | `capped: 796` / `texture cap check: OK` (1567 targets, 1 alpha, 0 offenders) |
| perf guard | `PERF_GUARD_TEST PASS checks=78 fails=0` |
| gate ratchet | `GATE_RATCHET: PASS` |

`make audit` independently exits 0 with the baseline unchanged
(`AUDIT PASS`, disk-backed coverage `12660/12703`, 0 unexpected, 13/13 content
groups). `make audit-refresh-stamps` was **not** run.

## 4. Counts that moved because the tree moved (old → new)

Base = the 49-gate / `37bb69e` baseline. Every delta is from the Phase 2.5
test-manifest / contract-test lanes, not a game change:

| Count | Old | Measured | Proof line |
|---|---|---|---|
| runner gates | 49 | **58** | `FINAL_GATES PASS … gates=58`; runner `EXPECTED_GATES=58` |
| compile | 228 | **229** | `compile.log`: `scripts checked: 229, broken: 0` |
| run_tests | 327 | **328** | `run_tests.log`: 328 `PASS:` lines; suite 125 added |
| P1 doors | 47 | **49** | `probe_p1_doors.log`: `P1_DOORS checks=49 fails=0` |
| gate_manifest tracked | 108 (floor) | **109** measured | `GATE_MANIFEST: tracked=109` |
| e2e / e2e_a2 / run_tests ERROR | 31 / 1 / 482 | **31 / 0 / 482** | `e2e_errscan.log` |

The ratchet floors for compile (228→229), run_tests (327→328),
probe_p1_doors (47→49) and gate_manifest.tracked (108→109) are raised to the
measured values; no other floor changes and no floor is lowered.

## 5. The `e2e_errscan` fix and its evidence

Round 1 was blocked here: the old script treated a log with zero `ERROR:` lines
as truncated and pinned the nondeterministic `N resources still in use at exit`
teardown warning at exactly 1 for `e2e_a2` only.

**Semantics now:**
- A log is complete only if it is non-empty, carries its tier's completion
  marker (`e2e` 300/300, `e2e_a2` 22/22, `run_tests` `fails=0`) **and** the
  runner footer (`FINISHED:` and `EXIT: 0` in the last lines). A missing
  marker, a missing footer, or an empty file fails as truncated. `grep`'s
  no-match exit (1) is accepted by the per-line scan.
- Per-log tamper minimum totals: **e2e 31**, **e2e_a2 0**, **run_tests 482**.
  Deleting every `ERROR:` line fails for e2e and run_tests; a legitimate class
  disappearance is a reviewed minimum change, never a silent pass. A2 may be
  legitimately zero because the teardown warning is intermittent.
- The per-pattern max + `sum == ceiling` rule is unchanged: e2e
  `13+10+7+1+2 = 33`, e2e_a2 `2`, run_tests `482`.
- Reviewed raise: e2e ceiling **31→33**, e2e_a2 **1→2**, adding the teardown
  class at max 2 per tier. The teardown line is **observed 0–1** per process
  (at most one summary line per process), so ceiling 2 is **one-slot
  headroom**, not a measured maximum. This is not a lowered quality floor: a
  new/unmatched `ERROR:` class still fails, each class keeps its own maximum,
  and the minimum totals reject wholesale deletion.
- The ceilings **33 / 2 / 482** and the minima **31 / 0 / 482** are pinned in
  `tools/gate_ratchet.json` (`gates.e2e_errscan`) and re-checked by
  `tools/check_gate_ratchet.py` against the log's PASS line.

**Evidence — committed standalone A2 logs** at
`docs/reports/logs/errscan-a2/a2-standalone-{1,2,3}.log` (measured at
`5857589`; see the directory README): `ERROR:` lines **0 / 0 / 1**, teardown
**0 / 0 / 1**, all `fails=0 passed=22 total=22`. Together with the full-run
`e2e_a2=0/2` and `e2e=31/33`, the teardown class is observed at 0 or 1.

**Negative controls** (scratch copies under `/tmp/opencode/errscan-controls3/`
and the round-2 set; committed logs untouched):

| Control | Result |
|---|---|
| truncation right after `SUMMARY:` (no footer) | **FAIL** `missing the FINISHED footer` |
| delete every `ERROR:` from e2e (0 < min 31) | **FAIL** `below the minimum total 31` |
| delete every `ERROR:` from run_tests (0 < min 482) | **FAIL** `below the minimum total 482` |
| A2 teardown deleted (0, min 0) | **PASS** `E2E_ERRSCAN PASS e2e=31/33 e2e_a2=0/2 run_tests=482/482 new=0` |
| empty file | **FAIL** `is empty; a truncated log cannot prove the gate` |
| marker removed (valid size) | **FAIL** `missing its completion marker` |
| new ERROR class | **FAIL** `new=1` |
| e2e teardown count 3 (total 33) | **FAIL** `pattern 4 matched 3 times, above its pinned maximum 2` |
| e2e total 34 | **FAIL** `has 34 ERROR: line(s), above the pinned ceiling 33` |

## 6. Ratchet and evidence chain

- **In-run:** `docs/reports/logs/final/gate_ratchet.log` — PASS with the
  historical `measured_on=37bb69e` (kept intact; the floors are minimums and
  the fresh logs satisfy them).
- **Post-stamp:** `tools/gate_ratchet.json` is advanced to
  `measured_on=5857589`, `source` records run head / code head / wall time /
  host context / count deltas, and `report` points at this file.
  `make gate-ratchet` exits 0.
- **Mechanical capture (A1):** `build/qa/poststamp_gate_ratchet.sh` regenerates
  `docs/reports/logs/final/gate_ratchet_poststamp.log` in one pass — `STARTED:`
  before `python3 -B tools/check_gate_ratchet.py --generating-poststamp` (the
  flag skips only the self-referential poststamp entry while generating), the
  checker's real output and exit code, then `EXIT:` and `FINISHED:`. No line is
  hand-assembled. A plain `python3 -B tools/check_gate_ratchet.py` afterwards
  validates the finished artefact end to end. Measured for this artifact:
  `STARTED: 2026-11-27T22:53:58-05:00`, `EXIT: 0`,
  `FINISHED: 2026-11-27T22:53:58-05:00`, mtime `22:53:58.693`.
- **Timestamp self-check (A1):** `tools/check_gate_ratchet.py` now rejects an
  evidence log whose `FINISHED:` predates its `STARTED:`, whose mtime predates
  `STARTED:`, or that carries only one of the pair. Controls in an isolated
  scratch ROOT: `STARTED=2099…` → **FAIL**
  `STARTED … is after FINISHED … — the artifact was assembled, not measured`;
  mtime `2000-01-01` → **FAIL** `mtime … predates STARTED …`; restored artifact
  → **PASS**. This is the check that rejects the previous hand-assembled file
  (`STARTED 22:16:00` > `FINISHED 22:15:28`).
- A plain (non-generating) `python3 -B tools/check_gate_ratchet.py` after the
  capture re-validates the new poststamp log end to end (content + stamps) and
  exits 0.

## 7. Host performance and the `/tmp` reference loss

The earlier 22m24s / 49-gate run and all earlier headless/GPU slowness were
measured on a host limited to **80 W GPU / 23–30 W CPU (0.8–1.5 GHz)**. The
2026-11-27 fixes are active for this run (`nvidia-powerd` 140 W,
gaming-desktop profile, `split_lock_mitigate=0`, vents cleaned, `/tmp`
reclaimed). This run is **23m19s for 58 gates**; it does not reinterpret any
older pixel or timing number and no GPU benchmark was run.

The 2026-11-27 system cleanup deleted `/tmp/opencode/tat2-ref-prefix`,
including the 774-file Proton prefix, its `TAT_ETS.sav` (previously recorded
md5 `976f8730eac989bab1c6c792343b7c00`) and
`SaveGames.pre-p0b-20261126-230522`. **Verified now:** the directory is absent,
no `TAT_ETS.sav` exists under `/tmp/opencode` or `/home/john/tat2-ref-build`,
and `/home/john/tat2-ref-build` itself survives. The save md5 is a historical
record, **not re-verified** in this wave. Issue **#13** (Cleanout live capture)
therefore needs a fresh Proton prefix and a fresh save before the live capture.

## 8. Caveats

- `e2e_errscan` pins the teardown class at max 2 per tier with **one-slot
  headroom** over the observed 0–1, plus tamper minima (e2e 31, run_tests 482;
  A2 0). A future 3+ run fails by design (raise only with a new measurement and
  a note). The standalone A2 evidence is committed under
  `docs/reports/logs/errscan-a2/`.
- The Niagara probe's 58-gate gate is Guildhall-scoped (`active=219`); the
  payload-wide census (3,308 active / 36 systems) is not re-derived by this
  gate.
- `P5_UI` and `KF27` remain headless/reference-only; no pixel score is claimed.
- No GPU/Vulkan/Xvfb capture was run.
