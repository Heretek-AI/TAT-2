# P1 integration gate run — 2026-11-26

| | |
|---|---|
| wave | P1 (route content S12–S26: safe room, blue doors, beams/foyer, ward/alarm, street/car/gate/MACLEOD) |
| ratchet file | `tools/gate_ratchet.json` |
| evidence directory | `docs/reports/logs/p1/full/` |
| **measured_on** | `78884fe` |
| HEAD measured | `78884fe7d19d43a51e6c7a35d5f886401ffda869` (`w10/p1-evidence`) |
| base tip | `3998761` — the five P1 lane commits (safe `5075283`, doors `4b1576a`, beams `08a1cfa`, ward `9b0c47a`, street `3998761`) plus the p2 re-stamp `f420b17` |
| integration fix | `78884fe` — portal shader bound on the QuadMesh surface for `A2-WHITE` (see §1) |
| runner | `build/qa/run_p0b_gates.sh` (tracked; one serial run, one Godot at a time) |
| engine | `4.7.2.stable.official.ed1daf0bf` via native `tools/godot` |
| host | Linux 7.4.0 x86_64, 32 CPUs, headless |
| run wall | **19 m 31 s** (2026-11-26T20:05:04-05:00 → 20:24:35-05:00); E2E 446 s |
| report role | this is the `report` the ratchet checker parses |

This is the P1 evidence run. It is one command:

```bash
build/qa/run_p0b_gates.sh
```

The runner is the P0b runner extended for P1: every P0b gate body is unchanged,
the five P1 lane probes are spliced in as section 1b, and the run writes
`docs/reports/logs/p1/full/` instead of the P0b directory. The final line was:

```
P1_GATES PASS head=78884fe7d19d43a51e6c7a35d5f886401ffda869 gates=40 expected_gates=1
```

40 passing gates plus the cream proof, which is expected to fail (exit 1).
Every Godot invocation takes `flock /tmp/opencode/tat2-godot.lock`;
`runtime_smoke.sh` and `p0b_capture.sh` are invoked **without** an outer flock
because they take the lock themselves. The tree at start carried the new runner,
the capture-evidence override, this wave's log directory and 7 local `.uid`
sidecars (`uncommitted_entries_at_start: 10` in `p1-run.log`).

## 1. Gate failure found at the merged tip — fixed, not waived

The first serial run at `3998761` (preserved under
[`logs/p1/pre-fix/`](logs/p1/pre-fix/)) stopped at E2E:

```
A2_WHITE unexplained key=<no ue_mesh> MeshInstance3D count=1
  sample=/root/Mission/SafeRoomDressing/SafeRoomPortalOutline detail=[0]null(glTF-default)
FAIL: [A2-WHITE] no unexplained near-white visible mesh
  (visible=6746 shader_surfaces=397 unexplained=1 allowlisted=3)
SUMMARY: fails=1 passed=299 total=300
```

Cause: P1-SAFE built the safe-room portal outline with `material_override`
only. The `A2-WHITE` audit samples **surface** materials
(`get_surface_override_material` → `mesh.surface_get_material`), so a mesh with
only an instance override reads as glTF-default white and is (correctly) flagged
as an unexplained near-white node. Nothing was weakened: `escape_gate.gd` now
binds the same `ShaderMaterial` on the QuadMesh surface
(`quad.surface_set_material(0, mat)`) and keeps the override for the render path
and the probes. Rendering is unchanged; the audit can now classify the surface
as a `ShaderMaterial`.

After the fix (measured in this run):

```
A2_MEASURE near_white visible_nodes=6746 shader_surfaces=398 unexplained=0 allowed=3
SUMMARY: fails=0 passed=300 total=300
P1_SAFE PASS checks=86 fails=0
scripts checked: 213, broken: 0
```

The red proof stays in the tree as
`docs/reports/logs/p1/pre-fix/{e2e.log,p1-run.log,p1-summary.txt}`.

**`measured_on` deviation:** the task plan named `3998761`, but that tip is red
(`E2E 299/300`). The floors below were measured on `78884fe`
(`3998761` + this one integration fix), so `measured_on` names the tree that was
actually measured. The five lane commits are unchanged.

## 2. Floors parsed by the checker

`python3 tools/check_gate_ratchet.py` builds its report regexes from the JSON and
requires these literal lines (parsed as `compile | checked / broken`,
`run_tests | passes`, `M2 | passes`, `E2E | passed / total`,
`coverage_num / coverage_den`, plus the `measured_on` SHA):

```
compile | 213 / 0
run_tests | 322
M2 | 12
E2E | 300 / 300
12660 / 12703
measured_on 78884fe
```

## 3. Source state and preflight

`tools/godot --headless --path game --import` was run once after checkout; it
generated the seven missing `.uid` sidecars for P1 files (`vine_lock.gd`,
`street_car.gd`, `status_icon.gd`, the two new shaders and
`probe_p1_{street,ward}.gd`) and refreshed only gitignored `.godot/` state. No
global class registration was missing and the compile was clean at 213/0. The
measured run is the post-import run. No producer was run; `game/data/generated/`
and `extracted/` stayed read-only.

The runner changes for this wave:

- log directory `docs/reports/logs/p1/full/`, master `p1-run.log`, summary
  `p1-summary.txt`;
- five P1 probe gates in section 1b with their measured check counts pinned in
  the marker;
- the compile marker is a regex (`scripts checked: N, broken: 0`) because the
  checked count grows every wave; the ratchet pins the floor;
- `P0B_EVIDENCE_DIR` makes the headless capture dry-run/self-test record under
  this wave's directory (default unchanged), so the committed P0b evidence is
  not rewritten;
- the p2 marker stays `expected_fail=1 expected_delta=0 fixed=0
  unexpected_fail=0` (P1-BEAMS promoted the beam).

## 4. Measured gates

| gate | result | measured line(s), quoted from `docs/reports/logs/p1/full/` |
|---|---|---|
| compile | **PASS** 213 / 0 | `scripts checked: 213, broken: 0` |
| `run_tests.gd` | **PASS** 322 / 0 | `SUMMARY: fails=0` (322 `PASS` lines; suites numbered to 120, 119 deliberately unregistered) |
| `test_m2_player.gd` | **PASS** 12 / 0 | `M2_SUMMARY: fails=0` (12 `PASS` lines) |
| **P1-SAFE probe** | **PASS** 86 checks | `P1_SAFE PASS checks=86 fails=0 skips=0` |
| **P1-DOORS probe** | **PASS** 47 checks | `P1_DOORS checks=47 fails=0` / `P1_DOORS PASS` |
| **P1-BEAMS probe** | **PASS** 7 checks | `P1_BEAMS PASS checks=7 fails=0 last=dressing bulb=true node=true … plaques=2 plate=1` |
| **P1-WARD probe** | **PASS** 44 checks | `P1_WARD PASS checks=44` |
| **P1-STREET probe** | **PASS** 31 checks, 2 HARD_LIMITs | `P1_STREET SUMMARY checks=31 fails=0 hard_limits=2` / `P1_STREET PASS` |
| guard, Guildhall C2 | **PASS** | `GUARD_CHECK PASS map=guildhall order=2 guards=4 buckets=4/4 lounge=1 lounge_marker=C_20 selection=parity_approx_layer_bucket difficulty=1` |
| guard, Old Manor order 3 | **PASS** | `GUARD_CHECK PASS map=old_manor order=3 guards=4 buckets=4/4 lounge=0 lounge_marker=- selection=parity_approx_layer_bucket difficulty=1` |
| beam geometry | **PASS** | `BEAM_AXIS_TOTAL cards=330 max_axis_err_deg=0.000006 max_len_err=0.000406 glb_len_err=0.020006 clamped=0 old40_clipped=322 old200_clipped=5` / `BEAM_GEOMETRY_SUMMARY: fails=0` |
| GC destruction probe | **PASS** 44 checks | `GC_PROBE checks=44 fails=0` / `GC_PROBE PASS` |
| GC break trigger | **PASS** 21 checks | `GC_TRIGGER checks=21 fails=0` / `GC_TRIGGER PASS` |
| civilian (W10-A2) | **PASS** 22 / 0 | `W10A2_CIV_SUMMARY: fails=0 passed=22 total=22` |
| guard placement (pure) | **PASS** 35 checks | `GUARD_PLACEMENT_SUMMARY: fails=0` (35 `PASS` lines) |
| turret / device meshes | **PASS** 11 checks | `TURRET_PROBE PASS checks=11 actors=229 visible_parts=1145 hidden_parts=0` |
| authored collision | **PASS** 3 maps | `COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0 planar_skipped=2 coverage_ppm=976321` |
| lock inventory | **PASS** | `LOCK_INVENTORY runtime: authored=173 raw=363 applied=154 containers=144 door_nodes=10 discarded=209 state=APPLIED` |
| door walk | **PASS** | `DOORWALK PASS` |
| viewmodel truth | **PASS** | `VIEWMODEL_TRUTH PASS zip_emissive=off top_emissive=off crank_bone=crank_arm posed=true reset=true` |
| Niagara | **PASS** | `NIAGARA_PROBE PASS` |
| geometry placement | **PASS** 7 checks | `GEOM_PROBE checks=7 fails=0 pending_regeneration=0` / `GEOM_PROBE PASS` |
| blackjack race | **PASS** | `BLACKJACK_PROBE PASS fails=0` |
| leak probe | **PASS** clean | `PROBE start players=0` … `PROBE after gh free players=0`; 0 `leaked at exit` / `SCRIPT ERROR` |
| E2E (all tiers) | **PASS** 300 / 300 | `SUMMARY: fails=0 passed=300 total=300`; T1=117 T2=110 T3=25 T4=14 S2=12 A2=22 |
| E2E tier a2 (standalone) | **PASS** 22 / 22 | `SUMMARY: fails=0 passed=22 total=22` |
| E2E tier p2 | **PASS** 13 / 13 | `P2_SUMMARY: expected_fail=1 expected_delta=0 fixed=0 unexpected_fail=0`; `P2_EXPECTED_FAIL: [P2-CIV-PANTS-ALBEDO] …`; beam check `P2-BEAM-AUTHORED-PORT` passes |
| parity-only governance | **PASS** 60 / 0 | `PARITY_ONLY_SUMMARY: fails=0 passed=60 rules=11 restoration=11 expansion=0` |
| cream RED proof | **EXPECTED FAIL** exit 1 | `CREAM_PROOF: RED passes=2 expected_fail=2` (not a gate; suite 119 unregistered) |
| capture dry-run | **PASS** | `P0B_DRY_RUN manifest=…/docs/reports/logs/p1/full/dry-run/manifest.json poses=6 schema=tat2.p0b_capture/1 audio=disabled reason=dry_run` |
| capture self-test | **PASS** 21 / 0 | `P0B_SELFTEST PASS checks=21 fails=0` |
| manifest validation | **PASS** | `P0B_MANIFEST_OK path=…/docs/reports/logs/p1/full/dry-run/manifest.json poses=6 dry_run=true run_id=20261127T012247Z_78884fe7d19d_on` |
| KF27 reference calibration | **PASS** 7 / 7 | `P0B_KF27_REF pose=upper_foyer met=7/7 emitter_box=true beam_row_band=true row_excess_ge_2=true glow_falloff=true core_neutral=true no_cream_slab_10pct=true cream_reference_like_2pct=true` |
| runtime smoke | **PASS** exit 124 | `RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok` |
| runtime-smoke scan self-test | **PASS** 29 / 0 | `RUNTIME_SMOKE_SCAN_TEST PASS checks=29 fails=0` |
| string audit | **PASS** | `UI_STRINGS total=307 routed=307 authored=196 routed_authored=196 invented=111` / `UI_STRINGS GATE PASS` |
| literal greps | **PASS** | `LITERAL_GREPS PASS code_hits=0 ui_rating_literals=0 files=105` (99 → 105 with the P1 scripts) |
| `make audit` | **PASS** | `Disk-backed content coverage: 12660/12703 (99.7%), resolved by exported-name rename 3, allowlisted missing 43, unexpected 0` / `AUDIT PASS` |
| texture cap | **PASS** 797 / 1 / 0 | `capped: 797` / `alpha-critical (kept full-res): 1` / `offenders: 0` |
| perf guard | **PASS** 78 / 78 | `PERF_GUARD_TEST PASS checks=78 fails=0` |
| `make gate-ratchet` | **PASS** | pre-update run in `gate_ratchet.log`; the post-update rerun is `gate_ratchet_post_update.log` |

The two P1 probes that load a map (`probe_p1_doors`, `probe_p1_ward`) print the
same Godot exit-order `ObjectDB instances were leaked at exit` warning as the
committed `probe_blackjack_race` / `test_gc_break_trigger` logs. No
`SCRIPT ERROR` appears in any P1 log; the warning is engine teardown noise, not a
new leak (the `probe_leak` gate is clean).

## 5. What the P1 probes measured

| probe | rows | key measured facts |
|---|---|---|
| `probe_p1_safe` | V6-01, G1-05, V1-04 | portal `(1.840736, 2.386822)` on the authored safe-room wall, `core=(0.2078,1.0,0.3294)` / `edge=(0.5614,0.0831,1.0)`, gate light `(0.749,0,1.0)` → 1.3783 energy, 4.50 m; lantern spot `(1.0,0.5395,0.1845)` energy 0.5877 (authored 5.0), 4.50 m, 80°, no shadow; prompts `[F] TURN ON` → `[F] TURN OFF` → `[F] TURN ON`; flyer UV `umax=0.3242 dv=0.4507` = the `"SPIDER"` atlas cell |
| `probe_p1_doors` | V3-03, UI2-05, PG-2 | 4 S21 pivots spawn; leaf 1.51×4.00 m, 2 GLB surfaces in order (`MI_TrimMetalA_brass` slot 0 = diamond mullions + twin pulls, `MI_ManorTrim` slot 1 = slab); `[F] OPEN` over `[F] [HOLD] LOCK` with two keycaps, `[F] CLOSE` while swinging, swing 90°, re-lock inside the authored 2..3 band, pick unlocks; HUD secondary row stacks below the primary on the reticle axis |
| `probe_p1_beams` | V6-03, V4-07, V1-04/AU3-04 (material) | `tat_beam` unshaded+additive+cull-disabled; loader material color `(5.0,4.3813,3.5156,0.5)` emissive 3.0, line 0.015 m, opacity 0.5, glow 0.06/0.085 m, fade 25 m; 330 cards col2 axis `max_axis_err_deg=0.000005`; profile center 0.560 / 1 cm 0.052 / 25 cm 0.0000 (no full tube); foyer emitter 15 parts, vitrine 5 + statue 1, armchair/ottoman, 2 plaques, cyan node at `(28.8973,30.4025,-58.002)` |
| `probe_p1_ward` | V6-04, G5-03, G5-04, V1-07, UI5-06 | foyer ward zone `0.30×3.936×1.653 m`, authored 7-shard cluster hidden → 7 visible on `activate()` → 7 hidden on `shatter()`; `Guildhall_Gameplay` 233 `SM_BlockerWard_*` paired 233/233 (6 m cap); beam 117 keeps 9.7177 m and fires `beam_triggered` once; green door ward 2.6×3.4 m with `0.16×2.56×3.36 m` BlockerBox and tint `(0.1334,1.0,0.0)`; alarm eye cone 15°, range 15.32772 m, forward `(0,-1,0)`; HUD icon `jaw_trap` + 8 s ring |
| `probe_p1_street` | V4-04 (partial), V4-05, V4-06, V1-05, V3-01, G1-04, AU5-01 | real Contract 02 boot; 19 crates / 2 ladders / 15 weeds / 1 wall light near the KF15 alley (779/4/22/164 map-wide); `SM_Guildhall_Sign` 4 surfaces, 2 griffins at x 5.65/14.55 z 24.75, transformer plate `T_ElectricalTransformer_D.png`; car prompt `[F] INTERACT`, authored horn clip, flash curve 0→1→0, flash energy 1.722, headlight 4.500→6.222, stim range 50 m; MACLEOD at `(116.6284,53.2895,22.6352)` tint `(1.0,0.361,0.078)` energy 4.00; gloomy `ground_wetness=1.0`, 9 Puddle bindings, 18 landscape instances |

## 6. Rows now scoreable

“Scoreable” means the subject is present, loaded and probe-measured against
authored values; the **visual score still requires a port capture**, which this
wave did not run (no GPU job, per the evidence-lane brief).

| row | status after P1 | approximation still attached |
|---|---|---|
| V6-01 escape portal wall outline | present in the safe room and on every endgame gate; authored colours/size/light | `APPROX_SHADER` contour (Niagara emitter + ember/crack renderers HL-1) |
| G1-05 safe-room lantern toggle | present; prompt/light/emissive state machine measured | flame VFX HL-1 (authored emissive-shape stand-in) |
| V1-04 lantern bounce / streetlamp exposure | direct warm practical authored 1:1 | indirect bounce HL-7 |
| V1-05 flashing car-headlight glare | authored flash curve/levels on the two KF16 beams | wet-cobble exposure check |
| V3-01 wet-cobble specular | existing authored gloomy preset + 9 Puddle bindings + `tat_landscape` | decal graphs HL-2 |
| V3-03 blue door paint/mullions/brass | 4 pivots spawn; 2 authored slots bound in GLB order | the “blue paint”/“dark glass” read is lighting, not an authored slot |
| UI2-05 blue door prompts | `[F] OPEN` over `[F] [HOLD] LOCK` with two keycaps, `[F] CLOSE` flip; copy unchanged | — |
| V4-05 gate arch, griffins & gear plate | sign (4 surfaces), 2 griffins, 10-bolt plate | — |
| V4-06 `MACLEOD` sign | authored placement + tint, emission at the 4.0 cap (authored 5.0) | `APPROX_SHADER` exposure |
| V4-07 foyer dressing | vitrine/statue, armchair/ottoman/rug, 2 plaque labels, floor plate, cyan node | floor-plate placement + cyan node `PORT_APPROX`; plaque font |
| V6-03 security beams, emitter & node | 330 authored-parameter cards (1.5 cm line, opacity 0.5, 6 % glow, 25 m fade, HDR ×3), emitter bulb | pixel falloff `PORT_APPROX`; exact shipped cyan node HARD_LIMIT |
| V6-04 purple ward + green vine lock | authored 7-shard cluster (233/233 paired), green door ward 2.6×3.4 m | active colour `APPROX_COLOR`; ward/vine shaders `APPROX_SHADER`; vine placement `APPROX_PLACEMENT` |
| G5-03 beam tripwire → lockdown | beam 117 trip → ward + vine seal + jaw-trap icon | shatter trigger `PORT_DECISION` (cooked Kismet unrecoverable) |
| G5-04 ward shatter → crimson alarm | contact-dwell shatter → collapse + crimson spot + sting | trigger `HARD_LIMIT (HL-3)`; light colour/energy `APPROX_LIGHT`; sting `APPROX_CUE` |
| V1-07 crimson alarm spotlight | authored pose/cone 15°/range 15.32772 m | colour (1.0,0.07,0.05) energy 4.5 `APPROX_LIGHT` |
| UI5-06 status icons above the Light Gem | jaw-trap icon + 8 s ring raises/clears | icon render `PORT_DECISION` (no 2D jaw-trap texture) |
| G1-04 vintage car interact | `[F] INTERACT`, authored honk + `AI.Stim.Hearing.CarAlarm` (50 m) | — |
| AU5-01 vintage car double-honk | authored `Play_Obj_Vehicle_Car_Horn_OneOff` resolves as a real clip | — |

## 7. HARD_LIMITs and open items (not invented)

| item | label | evidence |
|---|---|---|
| `BARRON'S DEMOLITION` banner | **HARD_LIMIT** | 0 `barron`/`demolition` name hits in `extracted/json`, `game/data/generated`, `extracted/assets` and the nine Guildhall level JSONs; the only banners are `SM_BannerB`/`SM_BannerWall_IronBeam` + `T_BannerSet_D` (blue `KILCAIRN` heraldry) |
| KF15 fallen steel drums | **HARD_LIMIT (placement)** | `SM_Metal_BarrelA/B/C` exist (60 instances map-wide) but no barrel/cask placement within 12 m of the KF15 alley |
| exact shipped cyan ceiling node | **HARD_LIMIT** | the POI record `SM_Sphere2Count` is `hidden_in_game: true` with `MI_EmissiveShape`; the visible KF27 node is a Blueprint/Niagara overlay the extraction does not expose; the port creates a `PORT_APPROX` lozenge at the authored light position |
| circular lockpick minigame art | **HARD_LIMIT + PORT_DECISION** | the dial exists and runs authored arc parameters (80°, 3.0 s, jam 5/10/20/40, cancel 200 cm); the authored UMG widget tree is absent from the dump (port-rendered look); PG-2's `LockpickWheel`/`LockpickArc` names have no authored counterpart |
| beam pixel falloff | **PORT_APPROX** | params are authored 1:1; `EdgeFadePower`/sphere-mask terms are not decompiled |
| vine lock interaction | **HARD_LIMIT (HL-3)** | the shipped actor is a magic seal, not a lockable door; no lockpick prompt added |
| live reference / 120-row baseline | **PENDING** | the port capture and the live reference were **not run** in this wave; rows above are scoreable, not scored |
| `T1-22-A` evidence path | note | the E2E check resolves `evidence.dir` from the ratchet JSON, so during this run it validated the then-current P0b baseline (322 PASS); the post-update ratchet points it at `docs/reports/logs/p1/full/` |

No producer or generated-data file was modified. The headless capture
instrument refreshed no tracked P0b artefact: `P0B_EVIDENCE_DIR` keeps its
evidence under `p1/full/`, so the committed `docs/reports/logs/p0b/dry-run/`
and `p0b/self-test/` files are untouched.

## 8. Ratchet diff

- `measured_on`: `dfa8c7e` → `78884fe`
- `evidence.dir`: `docs/reports/logs/p0b/full` → `docs/reports/logs/p1/full`
- `report`: `docs/reports/p0b-20261126.md` → this report
- floors raised: `compile.checked` 202 → **213**
- new gates (measured check counts): `probe_p1_safe` **86**, `probe_p1_doors`
  **47**, `probe_p1_beams` **7**, `probe_p1_ward` **44**, `probe_p1_street`
  **31**
- unchanged floors (measured at or above): `run_tests` 322, `m2` 12, `e2e`
  300/300, `e2e_a2` 22/22, `e2e_p2` `expected_fail=1 expected_delta=0 fixed=0
  unexpected_fail=0`, `parity_only` 60, `audit` 12,660/12,703, `texture_cap`
  797/1/0, `perf_guard` 78, collision 976,321 ppm, locks 154/144/10, string
  audit 307/196/111, runtime smoke 0 errors
- no floor was lowered
