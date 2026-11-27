# Phase 0b — clean route2 and the 45-gate set at 912a481 (2026-11-27)

| | |
|---|---|
| wave | Phase 0b of [`next-phases-plan-20261127.md`](next-phases-plan-20261127.md) §3 |
| ratchet file | `tools/gate_ratchet.json` (schema `tat2.gate_ratchet/1`) |
| evidence directory | `docs/reports/logs/final/` |
| **measured_on** | **`912a481`** |
| HEAD measured | `912a481d42611cb0de77f31d4e01e63029b68190` (`main`; Phase 0a HEAD; tracked tree clean at start) |
| runner | `build/qa/run_final_gates.sh` (one serial run, one Godot at a time, no outer flock) |
| engine | `4.7.2.stable.official.ed1daf0bf` via native `tools/godot` |
| host | Linux 7.4.0 x86_64, 32 CPUs, headless |
| run wall | **19 m 49 s** (2026-11-27T10:35:15-05:00 → 10:55:04-05:00) |
| gates | **45 / 45 exit 0** |
| route2-clean | `docs/reports/logs/p0b-route/route2-clean/` (`status=captured`, `git.dirty=false`) |
| report role | this is the `report` the ratchet checker parses |

This is the Phase 0b measurement: the clean route2 capture (GPU, Xvfb Vulkan,
port build only, no Steam) followed by the full 45-gate serial set on the same
clean tree. It is one gate command:

```bash
build/qa/run_final_gates.sh
```

The final line was:

```
FINAL_GATES PASS head=912a481d42611cb0de77f31d4e01e63029b68190 gates=45
```

`uncommitted_entries_at_start: 1` — the untracked route2-clean evidence
directory only (the tracked tree was clean; the runner writes its logs during
the run). Every Godot invocation takes `flock /tmp/opencode/tat2-godot.lock`;
`runtime_smoke.sh` and the two `p0b_*` wrappers are invoked **without** an outer
flock because they take the lock themselves.

**The old `5135f53` logs were replaced in place by this run.** They are not
lost: they remain in git history at commit `5135f53` and are described by
[`docs/reports/final-20261127.md`](final-20261127.md) (the W10 FINAL 44-gate
report). This report is the current measured set; the old report is kept as
history and cross-references this one.

## 1. Route2-clean (GPU, clean tree)

Command, run before the gate set while the tracked tree was clean:

```bash
build/qa/p0b_route.sh --tag=route2-clean
```

Exact result (also in `docs/reports/logs/p0b-route/route2-clean/capture.log`):

```
P0B_ROUTE_CAPTURE_DONE status=captured beats=27 captured=13 deferred=14 partial=0 staged_failed=0 frame_errors=0 frames=17 errors=0 exit_ok=true manifest=<repo>/docs/reports/logs/p0b-route/route2-clean/manifest.json out=<repo>/build/qa/p0b_route/route2-clean
P0B_ROUTE_WALL mode=capture run=route2-clean exit=0 wall=207s
```

Manifest (`tat2.p0b_route/1`) counts and provenance:

| Field | Value |
|---|---|
| `status` | `captured` |
| `counts` | `beats=27 captured=13 deferred=14 partial=0 frame_errors=0 frames=17 plan_staged=13 planned=0 extras=1` |
| `git.sha` | `912a481d42611cb0de77f31d4e01e63029b68190` |
| `git.branch` / `git.dirty` | `main` / **`false`** |
| `mode` / `route_claim` | `staged` / `none` |
| lens | 54.54 vertical, 1920×1080, `KEEP_HEIGHT` |
| `level` | `free_play_substitute=true`, `official_free_play=false`, historical `Mission.Guildhall.LootTheRoom`, canonical `Mission.Guildhall.VaultHeist` |
| audio | enabled, 186.259 s, 19 marks, WAV+PCM+JSON, `rms=-30.32 dBFS`, `peak=-0.76 dBFS` |
| window | `2026-11-27T15:31:32Z` to `15:34:53Z` (201 s) |
| frames | **18 PNGs**, all 1920×1080 (17 beat frames + 1 Lounge extra) |

Captured beats: S01, S02, S03, S04, S05, S06 (2 frames), S08 (2), S09, S10,
S11, S12, S24 (3), S27; the Lounge `beam_close` is the `extras[]` pose. S24
reports `beam_visible=true` at the authored `C_107` card
`(23.27, 29.76, -57.4)` and `camera_source=player`. The log has no
`SCRIPT ERROR`, `SHADER ERROR` or `Parse Error`; it ends with the known
teardown warning (`7 RIDs of type "Texture" were leaked`) and the wrapper's
`exit=0` line. Media stays under the git-ignored
`build/qa/p0b_route/route2-clean/`; the manifest, capture log and GPU samples
are tracked in `docs/reports/logs/p0b-route/route2-clean/`.

The stale route1 (`status=partial`) and route2 (`git.dirty=true`, S06 fix
uncommitted) evidence is preserved unchanged. Route anatomy, the staged claim
boundary and the free-play substitute caveat are in
[`docs/reports/p0b-route.md`](p0b-route.md).

## 2. Floors parsed by the checker

`python3 tools/check_gate_ratchet.py` builds its report regexes from the JSON
and requires these literal lines (`compile | checked / broken`,
`run_tests | passes`, `M2 | passes`, `E2E | passed / total`,
`coverage_num / coverage_den`, plus `measured_on`):

```
compile | 217 / 0
run_tests | 324
M2 | 12
E2E | 300 / 300
12660 / 12703
measured_on 912a481
```

## 3. Measured gates — 45/45 exit 0

| Gate | Exact measured line | Log |
|---|---|---|
| compile | `scripts checked: 217, broken: 0` | `compile.log` |
| `run_tests` | `SUMMARY: fails=0` (324 `PASS` lines; suites 119 and 121 registered) | `run_tests.log` |
| M2 | `M2_SUMMARY: fails=0` (12 PASS) | `m2.log` |
| P1 safe | `P1_SAFE PASS checks=86 fails=0 skips=0` | `probe_p1_safe.log` |
| P1 doors | `P1_DOORS checks=47 fails=0` / `P1_DOORS PASS` | `probe_p1_doors.log` |
| P1 beams | `P1_BEAMS PASS checks=7 fails=0` | `probe_p1_beams.log` |
| P1 ward | `P1_WARD PASS checks=44` | `probe_p1_ward.log` |
| P1 street | `P1_STREET SUMMARY checks=31 fails=0 hard_limits=2` / `P1_STREET PASS` | `probe_p1_street.log` |
| guard, Guildhall | `GUARD_CHECK PASS map=guildhall order=2 guards=4 buckets=4/4 lounge=1 lounge_marker=C_20 selection=parity_approx_layer_bucket difficulty=1` | `probe_guard_positions_guildhall.log` |
| guard, Old Manor | `GUARD_CHECK PASS map=old_manor order=3 guards=4 buckets=4/4 lounge=0 lounge_marker=- selection=parity_approx_layer_bucket difficulty=1` | `probe_guard_positions_old_manor.log` |
| collision | `COL_MAPS PASS maps=3 min_coverage=0.869 dropped=0 planar_skipped=2 coverage_ppm=868852` (Guildhall 0.910, Old Manor 0.912, FTUE 0.869, `no_record=0`) | `probe_collision_authored.log` |
| locks | `LOCK_INVENTORY runtime: authored=173 raw=363 applied=154 containers=144 door_nodes=10 discarded=209 state=APPLIED` | `probe_lock_inventory.log` |
| Niagara | `NIAGARA_PROBE PASS` | `probe_niagara.log` |
| door walk | `DOORWALK PASS` | `probe_door_walk.log` |
| viewmodel | `VIEWMODEL_TRUTH PASS zip_emissive=off top_emissive=off crank_bone=crank_arm posed=true reset=true` | `probe_viewmodel_truth.log` |
| geometry | `GEOM_PROBE PASS` | `probe_geometry_placement.log` |
| blackjack | `BLACKJACK_PROBE PASS fails=0` | `probe_blackjack_race.log` |
| turret | `TURRET_PROBE PASS checks=11 actors=229 visible_parts=1145 hidden_parts=0` | `probe_device_meshes.log` |
| GC | `GC_PROBE checks=44 fails=0` / `GC_PROBE PASS` | `probe_gc_destruction.log` |
| GC trigger | `GC_TRIGGER checks=21 fails=0` / `GC_TRIGGER PASS` | `test_gc_break_trigger.log` |
| civilian | `W10A2_CIV_SUMMARY: fails=0 passed=23 total=23` | `test_w10a2_civilian.log` |
| guard placement | `GUARD_PLACEMENT_SUMMARY: fails=0` | `test_w10a2_guard_placement.log` |
| beam geometry | `BEAM_AXIS_TOTAL cards=330 max_axis_err_deg=0.000006 clamped=0` / `BEAM_GEOMETRY_SUMMARY: fails=0` | `test_beam_geometry.log` |
| leak | `PROBE start players=0`; no `leaked at exit` or `SCRIPT ERROR` | `probe_leak.log` |
| E2E `all` | `SUMMARY: fails=0 passed=300 total=300` (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22) | `e2e.log` |
| E2E `a2` | `SUMMARY: fails=0 passed=22 total=22` | `e2e_a2.log` |
| E2E `p2` | `P2_SUMMARY: expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0` / `SUMMARY: fails=0 passed=14 total=14` | `e2e_p2.log` |
| parity-only | `PARITY_ONLY_SUMMARY: fails=0 passed=60 rules=11 restoration=11 expansion=0` | `parity_only.log` |
| cream suite 119 | `CREAM_PROOF: GREEN passes=5 expected_fail=0` | `test_w10a2_cream.log` |
| audio control suite 121 | `AUDIO_CONTROL_SUMMARY: fails=0 checks=71` / `AUDIO_CONTROL counts: switch=14/23 values=84 state=4/8 values=10 rtpcs=16/50 curves=142 containers=185` | `test_audio_control.log` |
| P5 UI | `P5_UI PASS checks=44` | `probe_p5_ui.log` |
| Den spawn | `DEN_SPAWN PASS checks=9 fails=0` (`source=authored`, 2434 meshes) | `probe_den_spawn.log` |
| capture dry-run | `P0B_DRY_RUN ... poses=6 schema=tat2.p0b_capture/1` | `p0b_capture_dry_run.log` |
| capture self-test | `P0B_SELFTEST PASS checks=21 fails=0` | `p0b_capture_self_test.log` |
| capture manifest | `P0B_MANIFEST_OK ... poses=6 dry_run=true` | `p0b_manifest_validate.log` |
| KF27 reference | `P0B_KF27_REF pose=upper_foyer met=7/7` | `p0b_kf27_reference.log` |
| route self-test | `P0B_ROUTE_SELFTEST PASS checks=62 fails=0` (after both wrapper `bash -n` checks) | `p0b_route_self_test.log` |
| runtime smoke | `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok` / `RUNTIME_SMOKE PASS` | `runtime_smoke.log` |
| smoke scan self-test | `RUNTIME_SMOKE_SCAN_TEST PASS checks=29 fails=0` | `runtime_smoke_scan.log` |
| string audit | `UI_STRINGS total=311 routed=311 authored=199 routed_authored=199 invented=112` | `string_audit.log` |
| literal greps | `LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files=106` | `literal_greps.log` |
| audit | `Disk-backed content coverage: 12660/12703 (99.7%) ... unexpected 0` / `AUDIT PASS` | `audit.log` |
| texture cap | `capped: 796` / `alpha-critical (kept full-res): 1` / `offenders: 0` / `texture cap check: OK` | `texture_cap.log` |
| perf guard | `PERF_GUARD_TEST PASS checks=78 fails=0` | `perf_guard.log` |
| gate ratchet | `GATE_RATCHET: PASS` (against the `5135f53` baseline during the serial run, then against the re-stamped `912a481` baseline; see §5) | `gate_ratchet.log` |

The run summary is `final-summary.txt`; the master log with HEAD, branch,
Godot, host, nproc and every command line is `final-run.log`.

## 4. Ratchet diff (5135f53 → 912a481)

No gate count moved. The measured set is identical to the `5135f53` baseline
because Phase 0a was docs/QA/provenance only and Phase 0b added no `game/` code
or generated data.

| Field | Old (`5135f53`) | New (`912a481`) | Why |
|---|---|---|---|
| `measured_on` | `5135f53` | **`912a481`** | this measured tree |
| `report` | `docs/reports/final-20261127.md` | **`docs/reports/final-20261127-phase0b.md`** | this report |
| `evidence.dir` | `docs/reports/logs/final` | `docs/reports/logs/final` | unchanged; logs re-measured in place |
| `compile` | 217/0 | 217/0 | unchanged |
| `run_tests` | 324/0 | 324/0 | unchanged |
| `m2` | 12/0 | 12/0 | unchanged |
| `e2e` | 300/300 | 300/300 | unchanged |
| `e2e_a2` | 22/22 | 22/22 | unchanged |
| `e2e_p2` | 0/0/0/0 | 0/0/0/0 | unchanged |
| `parity_only` | 60/60 | 60/60 | unchanged |
| `probe_collision` | 868852, dropped 0, planar 2 | same | unchanged |
| `lock_inventory` | 154/144/10 | 154/144/10 | unchanged |
| `string_audit` | 311/199/112 | 311/199/112 | unchanged |
| `audit` | 12660/12703 | 12660/12703 | unchanged |
| `texture_cap` | 796/1/0 | 796/1/0 | unchanged |
| `perf_guard` | 78/0 | 78/0 | unchanged |
| P1 probes | 86/47/7/44/31 | 86/47/7/44/31 | unchanged |
| `test_w10a2_cream` | 5/0 | 5/0 | unchanged |
| `test_audio_control` | 71/0 | 71/0 | unchanged |
| `probe_p5_ui` | 44 | 44 | unchanged |
| `probe_den_spawn` | 9/0 | 9/0 | unchanged |
| **new** `p0b_route_self_test` | — | **62 checks, 0 fails** | the Phase 0a gate is now measured in the serial set |

No floor was lowered. The new checker entry reads the route self-test's own
summary line (`P0B_ROUTE_SELFTEST PASS checks=62 fails=0`), so a probe that
silently loses checks fails the ratchet, not just the gate.

## 5. Ratchet re-stamp and audit after the measurement

After the 45-gate run, `tools/gate_ratchet.json` was updated **only from the
committed logs** (`measured_on=912a481`, report = this file, new
`p0b_route_self_test.checks=62`, evidence entry for
`p0b_route_self_test.log`). Then:

```bash
make gate-ratchet   # GATE_RATCHET: PASS against the 912a481 baseline
make audit          # AUDIT PASS; coverage 12660/12703; unexpected 0
```

The serial run's own `gate_ratchet` gate executed against the then-current
`5135f53` baseline and passed (`gate_ratchet.log`); the post-stamp re-run is the
second PASS, recorded in `gate_ratchet_poststamp.log`
(`GATE_RATCHET: PASS`, exit 0). The post-stamp `make audit` is
`audit_poststamp.log` (`AUDIT PASS`, exit 0). Both checks parse the same
committed logs; the second is the one that proves the new floor and report
agree.

## 6. Not verified / boundaries

- **No `game/` code or generated-data change.** Phase 0b is route evidence,
  gate logs, docs and the ratchet only. No `make normalize`, producer or
  extractor ran.
- **The perf matrix is not run** (thermal gate waived; one Godot at a time).
  Do not quote frame rates from this gate run.
- **The route is still staged, not played.** `route_claim=none`; the 13
  captured / 14 deferred split and the free-play substitute are unchanged. The
  120-row re-score and the live Cleanout reference (#13) remain Phase 2/3.
- **No visual/parity score** is claimed from route2-clean; it is a clean-tree
  provenance capture, not a scorecard row.
- **GPU temperature:** the capture ran one Godot at a time under Xvfb; GPU
  before `47.13 °C / 1914 MiB / 22 %`, after `58.28 °C / 1914 MiB / 10 %`,
  `207 s` wall including launch. No Steam or shipped game was launched.

## 7. Reproduce

```bash
# clean route evidence (GPU, Xvfb, one Godot, ~200 s; tracked tree must be clean)
build/qa/p0b_route.sh --tag=route2-clean

# the full serial 45-gate set (no outer flock)
build/qa/run_final_gates.sh

# the checker over the committed logs
make gate-ratchet
make audit
```
