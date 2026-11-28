# Phase 2.5 baseline attempt — 2026-11-27 (BLOCKED at `e2e_errscan`)

**Status: BLOCKED.** The complete committed gate set was launched twice from a
clean worktree at `25d9c94` and both runs stopped at gate **34 of 58**
(`e2e_errscan`), which fails non-deterministically on Godot's teardown
resource warning. Per the task rule ("if any gate is red, stop and report the
gate + log; do not re-baseline around it") **no baseline was stamped**: the
logs in `docs/reports/logs/final/` were restored to the committed state, the
ratchet was not advanced, and `README.md` / `AGENTS.md` /
`docs/HANDOFF_NEXT_AGENT.md` were **not** re-stamped. This file is the
evidence record for the two attempts and the exact blocker.

No GPU / Vulkan / Xvfb step was run. No producer, `make normalize`, or
generated-data write was performed.

---

## 1. Provenance and worktree setup

| Item | Value |
|---|---|
| branch | `teamwork/20261127-1810-phase3-baseline-run` |
| run head | `25d9c94713ea1edb4ac71618fb30727a3dc1c52b` |
| Godot | `4.7.2.stable.official.ed1daf0bf` |
| runner | `build/qa/run_final_gates.sh` (asserts `EXPECTED_GATES=58`) |
| uncommitted entries at run start | 0 (both attempts) |
| worktree | `/home/john/Projects/.teamwork-worktrees/20261127-1810-phase3/baseline-run` |

Fresh-worktree setup:

```bash
ln -s /home/john/Projects/TAT-2/extracted extracted
ln -s /home/john/Projects/TAT-2/game/data/generated game/data/generated
ln -s /home/john/Projects/TAT-2/game/assets/ue game/assets/ue
tools/godot --headless --path game --import      # 8m32s, 10,716 reimport steps
```

**Setup gap found:** the task's three symlinks are necessary but not
sufficient. `make audit` initially failed with
`tool version drift: vgmstream: 'vgmstream CLI decoder r2168 (Oct 25 2026)'
-> 'missing'` because `tools/bin/vgmstream/vgmstream-cli` is git-ignored and a
fresh worktree has no `tools/bin/`. Symlinking the shared read-only tool tree
(`ln -s /home/john/Projects/TAT-2/tools/bin tools/bin`) makes `make audit`
pass; it writes nothing. A future worker on a fresh worktree must add this
symlink (or the audit gate fails for an environmental reason).

## 2. Commands and wall time

```bash
bash build/qa/run_final_gates.sh     # attempt 1: exit 1, 1116 s (18m36s), stopped at gate 34/58
bash build/qa/run_final_gates.sh     # attempt 2: exit 1, 1126 s (18m46s), stopped at gate 34/58
make audit                           # exit 0 after the tools/bin symlink (8.5 s)
make gate-ratchet                     # base-state check at HEAD: PASS (see §6)
```

Neither wall time is a 58-gate wall time: the runner exits on the first red
gate, so both runs stopped after 34 gates. The attempt-1 evidence is preserved
at `/tmp/opencode/baseline-run-try1-20261127T212237/` and attempt 2 at
`/tmp/opencode/baseline-run-try2-20261127T214344/` (both ephemeral; §8 lists
what they contain).

## 3. Gates that ran (34/58, all exit 0 except `e2e_errscan`)

Measured from attempt 2; attempt 1 matched on every gate except the two
teardown-warning counts in `e2e_a2`/`e2e` (§5).

| Gate | Measured summary |
|---|---|
| compile | **229 checked / 0 broken** |
| run_tests | **328 PASS / fails=0** (328 `PASS:` lines; suite 125 contract probe registered) |
| M2 | **12 / 0** |
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
| Niagara | `NIAGARA_PROBE PASS` (Guildhall scope: active=219, 39 nodes; payload-wide census not re-measured separately) |
| StateTree shadow | `PROBE PASS fails=0` (`TAT2_STATETREE=shadow`) |
| door walk / viewmodel / geometry | `DOORWALK PASS` / `VIEWMODEL_TRUTH PASS` / `GEOM_PROBE PASS` |
| mirror split | `MIRROR_DATA_SUMMARY: fails=0 checks=39 mode=geometry` |
| blackjack | `BLACKJACK_PROBE PASS fails=0` |
| turret | `TURRET_PROBE PASS checks=11 actors=229 visible_parts=1145 hidden_parts=0` |
| GC | `GC_PROBE checks=52 fails=0`; owner index 87 paired, static leaves 16 |
| GC trigger | `GC_TRIGGER checks=21 fails=0` |
| civilian | `W10A2_CIV_SUMMARY: fails=0 passed=23 total=23` |
| guard placement | `GUARD_PLACEMENT_SUMMARY: fails=0` |
| beam geometry | `BEAM_AXIS_TOTAL cards=330 max_axis_err_deg=0.000006 clamped=0`; `fails=0` |
| roof collision | `ROOF_COLLISION_MODES PASS authored=0 aabb=0` |
| leak | `PROBE start players=0` (clean) |
| E2E all | `SUMMARY: fails=0 passed=300 total=300` |
| E2E a2 | `SUMMARY: fails=0 passed=22 total=22`, `static_bookcase_leaves=20` |
| E2E p2 | `P2_SUMMARY: expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0` (17/17) |
| manifest | `GATE_MANIFEST: tracked=109 reachable=70 retired=39 orphans=0` |
| **e2e_errscan** | **FAIL — see §5** |

Gates 35–58 were never reached: `parity_only`, `test_w10a2_cream`,
`test_audio_control`, `test_vo_director`, `probe_auto_exposure`,
`probe_cubemap`, `probe_p5_ui`, `test_capture_p5_filter`, `probe_den_spawn`,
`probe_den_window`, `p0b_capture_dry_run`, `p0b_capture_self_test`,
`p0b_manifest_validate`, `p0b_kf27_reference`, `p0b_route_self_test`,
`runtime_smoke`, `runtime_smoke_scan`, `producer_tests`, `string_audit`,
`literal_greps`, `audit`, `texture_cap`, `perf_guard`, `gate_ratchet`.

## 4. Counts that moved because the tree moved (old → new)

The base is the 49-gate / 37bb69e baseline. All deltas are explained by the
Phase 2.5 test-manifest/contract-test lanes, not by a game change:

| Count | Old (49-gate) | Measured | Proof line |
|---|---|---|---|
| compile | 228 | **229** | `compile.log`: `scripts checked: 229, broken: 0` |
| run_tests | 327 | **328** | `run_tests.log`: 328 `PASS:` lines, `SUMMARY: fails=0` |
| P1 doors | 47 | **49** | `probe_p1_doors.log`: `P1_DOORS checks=49 fails=0` (door-aperture fold) |
| runner gates | 49 | **58** | runner `EXPECTED_GATES=58`; 34 executed before the block |

No floor was lowered. `make gate-ratchet` was not run against the mixed log
set, so no `measured_on` stamp exists for this attempt.

## 5. The blocker: `e2e_errscan` fails on non-deterministic teardown noise

`build/qa/e2e_errscan.sh` pins `e2e=31`, `e2e_a2=1`, `run_tests=482` and
treats a log with **zero** `ERROR:` lines as truncated. The known
`N resources still in use at exit (run with --verbose for details).` warning is
emitted by Godot's teardown non-deterministically. Three identical standalone
A2 runs produced:

```
try1 rc=0 errors=0 warnings=9  tail=SUMMARY: fails=0 passed=22 total=22
try2 rc=0 errors=1 warnings=10 tail=SUMMARY: fails=0 passed=22 total=22
try3 rc=0 errors=1 warnings=10 tail=SUMMARY: fails=0 passed=22 total=22
```

Consequences for the two full runs (logs preserved in §8):

- **Attempt 1** (`docs/reports/logs/final/e2e_errscan.log`, preserved):
  `ERRSCAN FAIL: log …e2e_a2.log has zero ERROR: lines; empty/truncated log
  cannot pass` — `E2E_ERRSCAN FAIL fails=1 new=0`. `e2e` had the pinned 31 and
  `run_tests` the pinned 482; only `e2e_a2` lost its single teardown warning.
- **Attempt 2** (`docs/reports/logs/final/e2e_errscan.log`, preserved):
  `ERRSCAN FAIL: log e2e has 32 ERROR: line(s), above the pinned ceiling 31`
  and `ERRSCAN NEW e2e: 8 resources still in use at exit …` — the same
  warning moved into `e2e` (32 = 31 allowlisted + 1), while `e2e_a2` had its
  expected 1. Breakdown of the 32: 13 Lambda-capture, 10 `!is_inside_tree`,
  7 null `material`, 1 RID leak, 1 `resources still in use at exit`
  (the last is absent from `build/qa/e2e_errscan_allowlist.txt` for `e2e`).

Root cause: the allowlist/ceiling pair encodes one sampled occurrence
distribution of a timing-dependent teardown warning. The gate is neither a
game regression nor a data drift:
- `e2e.log` and `e2e_a2.log` both report `fails=0` (300/300 and 22/22) and
  complete `SUMMARY:` + `EXIT`/`FINISHED` records;
- the same binary produces 0 or 1 copies of the warning at random (0/1/1);
- `run_tests` is stable at exactly 482 in both runs.

A correct fix belongs to the gate-integrity lane (detect truncation from the
log's own completion record instead of `ERROR: count == 0`, and allowlist the
teardown warning for `e2e` with the ceiling raised to 32, or relax
`e2e_a2` to accept a complete zero-ERROR log). This task did **not** edit the
gate, the allowlist, or the ceilings.

## 6. `make audit` and `make gate-ratchet`

- `make audit` **exit 0** after the `tools/bin` symlink:
  `AUDIT PASS`, `CONSUMER AUDIT PASS`, baseline matches
  `tools/audit_baseline.json`, coverage unchanged (`12660/12703`, 0 unexpected,
  texture 1567/796/1/0). The first invocation (before the symlink) failed only
  on the missing `vgmstream` tool version; no baseline refresh was run.
- `make gate-ratchet` **PASS** at the restored HEAD state (`measured_on=37bb69e`
  against the committed 49-gate logs). This is a base-state consistency check,
  **not** a stamp for this attempt: the measured run did not complete, so the
  ratchet was deliberately left untouched. A post-stamp ratchet log was not
  written.

## 7. Host-performance context and the `/tmp` reference loss

The earlier 22m24s / 49-gate run and its 80 W GPU / 23–30 W CPU (0.8–1.5 GHz)
host were severely power-limited. The 2026-11-27 fixes are active in this run
(`nvidia-powerd` 140 W, gaming-desktop profile, `split_lock_mitigate=0`, vents
cleaned, `/tmp` reclaimed). This attempt's wall times (18m36s and 18m46s for
34 gates) are **not** comparable to the old full-run wall time and do not
reinterpret any prior pixel/timing number; no GPU benchmark was run.

The 2026-11-27 system cleanup deleted `/tmp/opencode/tat2-ref-prefix`,
including the 774-file Proton prefix, its `TAT_ETS.sav` (previously recorded
md5 `976f8730eac989bab1c6c792343b7c00`) and
`SaveGames.pre-p0b-20261126-230522`. **Verified now:** the directory is absent
and no `TAT_ETS.sav` exists under `/tmp/opencode` or
`/home/john/tat2-ref-build`; `/home/john/tat2-ref-build` itself survives.
The save's md5 is a historical record, **not re-verified** in this wave. Issue
#13 (Cleanout live capture) therefore needs a fresh Proton prefix and a fresh
save before the live capture can run.

## 8. Evidence locations

Attempt 1 `/tmp/opencode/baseline-run-try1-20261127T212237/` and attempt 2
`/tmp/opencode/baseline-run-try2-20261127T214344/` each contain the four
`final-*` files plus all 34 gate logs written before the stop; attempt 1 also
contains `a2-try1..3.log`, the three standalone A2 runs. `/tmp` is ephemeral —
if the Sentinel needs them after a reboot, they must be regenerated.

No gate was re-run selectively to produce a green log, and the committed
`docs/reports/logs/final/` was restored to HEAD, so the branch contains no
misleading mixed-sample baseline.
