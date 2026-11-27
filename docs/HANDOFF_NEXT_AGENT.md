# Handoff — Thick As Thieves Godot 4.7.2 port (next session)

**Repo:** `/home/john/Projects/TAT-2`
**Code/data tip:** `8a3ad62` (P1) + the W10-P2 data-wave commit on
`w10/data-wave` (cream emission, pants albedo, collision truth,
`GC_ChestTrunkALid` measurement). This branch is **not** merged; the integrator
merges it and re-stamps the two data baselines listed in
[`reports/w10p2-20261126.md`](reports/w10p2-20261126.md).
**Working tree:** clean apart from private/derived data; the W10-P2 lane logs are
in `docs/reports/logs/w10p2/`.
**Godot:** `4.7.2.stable` via native `tools/godot` (`godot` is **not** on `$PATH`).
**Renderer:** Forward+ · Jolt 60 Hz · 1280×720 reference · Linux x86_64.
**Steam reference:** `/home/john/.steam/steam/steamapps/common/Thick As Thieves/`.
**Single-Godot lock:** `/tmp/opencode/tat2-godot.lock` (never wrap
`build/qa/runtime_smoke.sh` or `build/qa/p0b_capture.sh` in an outer `flock`;
they take the lock themselves).

## 1. State in one paragraph

P1 restored the S12–S26 route subjects in five lanes (safe room/portal/lantern,
blue double doors/prompts, security beams/foyer, ward/lockdown/alarm,
street/car/gate/MACLEOD) and measured them at `78884fe` in one serial
`build/qa/run_p0b_gates.sh` run — **40 gates** plus the cream expected failure,
logs in `docs/reports/logs/p1/full/`. `compile` is **213/0**, `run_tests` **322**,
E2E **300/300**, p2 `expected_fail=1 expected_delta=0`, and the five new probes
are **86 / 47 / 7 / 44 / 31** checks. The five lane commits are `5075283`
(safe), `4b1576a` (doors), `08a1cfa` (beams), `9b0c47a` (ward), `3998761`
(street); `78884fe` fixes a merge-only failure where the new
`SafeRoomPortalOutline` bound its shader only through `material_override` and
the `A2-WHITE` audit (which samples surface materials) read it as glTF-default
white. Rows now **scoreable** (subject present and probe-measured): V6-01,
G1-05, V1-04, V1-05, V3-01, V3-03, UI2-05, V4-05, V4-06, V4-07, V6-03, V6-04,
G5-03, G5-04, V1-07, UI5-06, G1-04, AU5-01. Remaining gaps are labelled:
`BARRON'S DEMOLITION` banner and KF15 drum placement are HARD_LIMIT (no asset /
no placement), the exact cyan KF27 node is a hidden BP/Niagara overlay, and the
authored circular-lockpick widget art is absent. The P1 port capture ran at
`fafb78f` (`logs/p0b/20261127T015115Z_...`): gate 23.85, upper_foyer 40.88,
yaw180 39.47, Lounge 28.37, lounge_beam 24.52, beam_close 21.02; audio 92.8 s,
0 dropped. The frames show the authored thin beam line, no cream bars, and the
P1 foyer dressing. A P1 HUD `SubViewport` had shared the gameplay `World3D`
(its `DirectionalLight3D` lit the level; yaw180 84 → 39 after the fix). The
live-reference 120-row baseline is still unscored; **no visual parity PASS is
claimed**.

## 2. Gates at this HEAD (all measured, logs in `docs/reports/logs/p1/full/`)

**W10-P2 lane (unmerged branch `w10/data-wave`, base `8a3ad62`), measured
serially on 2026-11-27 with logs in [`reports/logs/w10p2/`](reports/logs/w10p2/):**
`compile` **213/0**; `run_tests` **323/0** (suite **119** registered);
E2E **300/300**; p2 `expected_fail=0 expected_delta=0 fixed=0
unexpected_fail=0` (14/14); collision
`COL_MAPS PASS min_coverage=0.869 coverage_ppm=868852 dropped=0`; GC
`GC_PROBE checks=44 fails=0`; roof `ROOF_COLLISION_SUMMARY: fails=0`; parser
tests `PASS: 28 checks`. `make audit` is **expected red** until the integrator
re-stamps `tools/audit_baseline.json` (three producer hashes, two payloads, the
`texture_refs` metric); `tools/gate_ratchet.json` `probe_collision.coverage_ppm`
must be re-based to 868852. Details:
[`reports/w10p2-20261126.md`](reports/w10p2-20261126.md).

The P1 gate set below is still the last **fully green** 40-gate run and remains
the reference until the merge re-runs it.

Run: `build/qa/run_p0b_gates.sh` on
`78884fe7d19d43a51e6c7a35d5f886401ffda869` (Godot
`4.7.2.stable.official.ed1daf0bf`), 19 m 31 s wall. Every gate exited 0 except
the cream proof, which is expected to exit 1; the runner stops on the first
unexpected non-zero exit.

| Gate | Value |
|---|---|
| compile | **213 checked, 0 broken** |
| `run_tests.gd` | **322 PASS, fails=0** (suites 117/118/120; 119 deliberately not registered) |
| `test_m2_player.gd` | **12 PASS, fails=0** |
| P1 probes | `P1_SAFE PASS checks=86` · `P1_DOORS checks=47 fails=0` · `P1_BEAMS PASS checks=7` · `P1_WARD PASS checks=44` · `P1_STREET PASS checks=31 hard_limits=2` |
| guard, Guildhall Contract 2 | `GUARD_CHECK PASS ... guards=4 buckets=4/4 lounge=1 lounge_marker=C_20 selection=parity_approx_layer_bucket` |
| guard, Old Manor `--order=3` | `GUARD_CHECK PASS ... guards=4 buckets=4/4 lounge=0` (Novice-labelled) |
| beams | `BEAM_GEOMETRY_SUMMARY: fails=0` — `cards=330 max_axis_err_deg=0.000006 clamped=0` |
| GC / turret / civilian | `GC_PROBE PASS` (44) · `GC_TRIGGER PASS` (21) · `TURRET_PROBE PASS` (229 actors, 1,145 parts, 0 hidden) · `W10A2_CIV_SUMMARY: fails=0 passed=22` |
| probes | doorwalk · viewmodel truth · Niagara · blackjack · geometry (7/7) |
| collision | `COL_MAPS PASS maps=3 min_coverage=0.976 dropped=0 coverage_ppm=976321` |
| lock inventory | `applied=154 containers=144 door_nodes=10 state=APPLIED` |
| `probe_leak` | clean (`TAT2_NO_DEN_PROBE=1`, `res://probe_leak.gd`) |
| E2E | **300/300**, `fails=0 passed=300 total=300` (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22) |
| E2E tier `a2` | **22/22** standalone |
| E2E tier `p2` | **13/13**, `expected_fail=1 expected_delta=0 fixed=0 unexpected_fail=0` (pants only; beam promoted) |
| parity-only | **60/60**, 11 rules all `parity_restoration`, 0 unclassified |
| cream RED proof | **expected exit 1**, `CREAM_PROOF: RED passes=2 expected_fail=2` |
| capture harness | dry-run `poses=6` manifest valid under `p1/full/dry-run` · self-test **21/21** · KF27 reference **7/7** |
| `make runtime-smoke` | **PASS** (`RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 mission_ready=1`) |
| `make audit` | PASS — 12,660/12,703, 0 unexpected |
| texture cap | 797 capped / 1 alpha-critical kept / 0 offenders |
| perf guard | 78/78 |
| `make gate-ratchet` | PASS (`measured_on=78884fe`; floors raised, never lowered) |

**Caveat:** no live reference capture. The P1 port capture exists (above), but
the P1 rows are scoreable, not scored; the 120-row baseline still needs the
shipped reference. The W9 interior numbers were measured on a frame with a
light-card slab covering half the screen and are **not** a valid
interior baseline.

## 3. Closed by P0a (previously the top defects)

- **Guards on the floor above** — `_ground_position` now rejects hits above the
  marker (2 m skip/back-fill); selection is layer/bucket-first. Guildhall
  Contract 2 has a ground-floor Lounge guard at `C_20`, all guards within 2 m of
  their own marker and ≤0.5 m off its floor ray (`marker_floor_within_0.5m=4/4`).
- **Beams 90° wrong** — `beam_card_transform()` scales the authored column 2 with
  the authored length; 330/330 cards, `clamped=0`.
- **Turrets invisible / civilian untextured and blind** — 229 turret actors now
  emit 1,145 parts (0 hidden); the civilian body/head is dressed and sight casts
  from the head (22/22).
- **W10-A2 deadlocked evidence batch** — the tracked runner keeps every Godot
  call under one lock, runs `runtime_smoke.sh` without an outer flock, uses the
  correct leak path, and covers audit/texture/perf/ratchet.

**Closed by P1 (route content S12–S26)**

- **Safe room/portal/lantern** — authored portal contour + violet door light,
  `[F] TURN ON/OFF` lantern, `"SPIDER"` flyer (V6-01 / G1-05 / V1-04 scoreable).
- **Blue doors/prompts** — the four S21 pivots spawn with two authored material
  slots; `[F] OPEN` over `[F] [HOLD] LOCK` with two keycaps, `[F] CLOSE` flip,
  authored 2..3 lock band (V3-03 / UI2-05 scoreable).
- **Beams/foyer** — the full-tube stand-in is replaced by the authored
  centre-line/fade material (1.5 cm line, opacity 0.5, 6 % glow, 25 m fade, HDR
  ×3), and the foyer dressing is built (V6-03 / V4-07 scoreable).
- **Ward/lockdown/alarm** — the flat violet pane is replaced by the authored
  233/233 ward shards and the green `BP_OneWayBarrier` door ward; beam trip →
  seal + icon, shatter → crimson spot + sting (V6-04 / G5-03 / G5-04 / V1-07 /
  UI5-06 scoreable).
- **Street/car/gate/MACLEOD** — `[F] INTERACT` car + authored horn/alarm/stim,
  MACLEOD emission, gate sign/griffins/plate, wet path (V4-05 / V4-06 / V1-05 /
  V3-01 / G1-04 / AU5-01 scoreable; V4-04 partial).
- **Merge-only `A2-WHITE` regression** — `78884fe` binds the portal shader on the
  mesh surface; red proof under `logs/p1/pre-fix/`.

## 4. Open work (measured/recorded, not hidden)

| Defect / item | Evidence | Next step |
|---|---|---|
| **Port capture (P1 tree)** | corrected six-pose run at `fafb78f` (`logs/p0b/20261127T015115Z_...`): gate 23.85, upper_foyer 40.88, yaw180 39.47, Lounge 28.37; thin beam line, no cream bars; audio 92.8 s/0 dropped | inspect KF14/15/16/23/24/27/28/29, then score the rows with the live reference |
| **120-row baseline unscored** | instruments ready; live reference prepared, nothing launched (`reports/p0b-live-capture.md`) | score the 120 rows on the parity-only build with recorded evidence |
| **Cream / invented white** | W10-P2 **closed**: `_apply_ue_emissive()` needs an authored colour or map; `tat_invented_white` census; suite **119** green (`passes=5`). The remaining cream bars in old captures are the `SM_LightBeam` cards | beam full-tube material is P4 |
| **Civilian pants albedo** | W10-P2 **closed**: `BaseColorOpacity` → albedo, `Source Color Texture` fallback; p2 `expected_fail=0` (14/14), 19 albedo bindings corrected, 75 bogus opacity binds removed | keep an eye on the audit `texture_refs 1523 → 1522` drop (the wrong male top) when re-stamping |
| **Collision coverage metric** | W10-P2: `no_simple_collision` map (334 packages), true element coverage 0.910/0.912/0.869; `coverage_ppm=868852` | re-stamp `tools/gate_ratchet.json` `probe_collision.coverage_ppm` (the old 976321 measured a fallback-inflated ratio) |
| **`GC_ChestTrunkALid`** | not in `extracted/json`; private dump shows `AutoInstanceMeshes = SM_ChestTrunkALid` (**intact** lid, 51 instances), so the labelled `_Broken` fallback stays (`fallback_broken=93`); producer guard skips an intact auto-instance | land `extracted/json/Destructibles/**` (one filtered `json` pass) + `normalize`; expected census unchanged, **not yet measured** |
| **`BARRON'S DEMOLITION` banner** | P1-STREET `HARD_LIMIT`: 0 name hits in the extraction; only the blue `KILCAIRN` banner set exists | no authored asset; do not invent a decal |
| **KF15 fallen drums** | P1-STREET `HARD_LIMIT (placement)`: `SM_Metal_BarrelA/B/C` exist but no placement within 12 m of the alley | needs a producer/placement source before it can be scored |
| **Cyan KF27 node** | POI `SM_Sphere2Count` is `hidden_in_game: true`; the visible node is a BP/Niagara overlay; port uses `PORT_APPROX` | exact node is HARD_LIMIT unless a Niagara/BP payload is exported |
| **Circular lockpick art** | PG-2: dial exists with authored arc parameters; authored UMG widget tree absent from the dump | HARD_LIMIT art; node-name mapping is `PORT_DECISION` |
| **3,288 mirrored instances, winding unverified** | 1,601 floors/roofs; `MESH_RECON ... mirrored=` | one `CULL_DISABLED` capture, then compensate |
| **Landscape visibility may be inverted** | `tat_landscape.gdshader` discards `vis > 0.5`; UE convention is 1 = visible | one reference sample; do not "fix" blind |
| **Sky contributes no light** | `sky_contribution=0`, `IBL available=false` | cubemap export + consumer (W10-C) |
| **Authored −4.00 EV bias not applied** | emissives hot against a zero floor | apply the AEM curve (W10-C) |
| **Guard count** | 4/6/8 is a labelled `PORT_DECISION`; selection is `PARITY_APPROX` | live Contract 02 capture before any parity claim |
| **Beam pixel falloff** | authored params 1:1; `EdgeFadePower`/sphere-mask terms not decompiled | `PORT_APPROX`; compare in the capture, never invent the graph |
| **Ward active colour** | saved per-instance MID is green `#7DFFB2`; KF28 reads purple; port uses base `WardColor #FF4DFD` | `APPROX_COLOR`; cooked activation colour not in the dump |
| **GC hold-smash** | temporary `PORT_DECISION`; 95 broken layers / 79 leaves measured | authored damage path before Parity Complete |
| **Prison-door lock level** | authored `MaxLockLevel` 4, port locks at 1 (producer emits instance deltas) | producer chain resolution + regeneration on the integrator |
| **StateTree** | payload v2 emits parameters (497/566 nodes, 676 bindings, 139 templates) but the runtime still flattens nodes to names; shadow `0/21` fully evaluable | consume v2 in `tree_model`/`coverage`; never invent parameters |
| **Perf matrix** | thermal gate waived; headless only | no parallel Godot; do not claim 60 fps |

## 5. Wave plan for the next session

**P1 remainder — live reference + score the route rows (do this first).** The
corrected P1 six-pose capture is measured
(`logs/p0b/20261127T015115Z_...`). Follow `docs/reports/p0b-live-capture.md` for
the shipped reference and score the 120 rows from
`docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` on the
parity-only build, publishing an honest per-row PASS/PARTIAL/FAIL with recorded
evidence. Do not re-grade on frame `215507`.

**W10-B — behaviour.** StateTree payload-v2 consumer (parameters/bindings →
interpreter) then navmesh/EQS; Niagara activation bridge. Audio direction if B
finishes early.

**W10-C — look.** AEM/IBL/EV bias, mirrored winding and the landscape docs/A-B;
the beam material has moved to the authored centre-line model but its pixel
falloff is still `PORT_APPROX`.

## 6. How to run everything

```bash
build/qa/run_p0b_gates.sh    # 40 gates + cream RED -> docs/reports/logs/p1/full/ (no outer flock)
make run                     # native client
make test                    # run_tests (322)
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"  # 213
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://tests/probe_p1_safe.gd
tools/godot --headless --path game --script res://tests/probe_p1_doors.gd
tools/godot --headless --path game --script res://tests/probe_p1_beams.gd
tools/godot --headless --path game --script res://tests/probe_p1_ward.gd
tools/godot --headless --path game --script res://tests/probe_p1_street.gd
tools/godot --headless --path game --script res://tests/probe_guard_positions.gd
tools/godot --headless --path game --script res://tests/probe_guard_positions.gd -- --map=old_manor --order=3
tools/godot --headless --path game --script res://tests/test_beam_geometry.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd          # 300
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=a2
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=p2
tools/godot --headless --path game --script res://tests/test_parity_only.gd            # 60/60
tools/godot --headless --path game --script res://tests/test_w10a2_cream.gd            # expected exit 1
build/qa/p0b_capture.sh --dry-run && build/qa/p0b_capture.sh --self-test
build/qa/p0b_capture.sh       # real Vulkan capture, one GPU job, after the gates
make runtime-smoke           # exit 124 only, ERROR: scan
make audit && make gate-ratchet
TAT2_GUARD_DIAG=1 tools/godot --headless --path game -- --qa-free-play   # guard spawn diagnostics
```

## 7. Invariants and hazards

- **Single Godot at a time.** Use `flock /tmp/opencode/tat2-godot.lock` for every
  invocation; never wrap `runtime_smoke.sh` or `p0b_capture.sh` (they take the
  lock themselves) and never run two GPUs/captures in parallel. Never edit
  `game/` while a run is live.
- **A fresh worktree needs `--import` once.** A copied `game/.godot` does not
  know a new global `class_name`: compile fails with `Identifier
  "ParityGovernance" not declared` and `test_parity_only.gd` says `GameState
  autoload missing`. Run `tools/godot --headless --path game --import`; it writes
  only gitignored state and local `.uid` sidecars.
- **Generated data is produced, not edited.** `game/data/generated/` and `extracted/`
  are read-only; regenerate only at merged HEAD (`make normalize`, `make anims`), then
  `make audit-refresh-stamps REASON=…`.
- **Workers do not push.** Treat any worker push as a contract violation and
  verify `origin/main` after each merge.
- **Do not weaken a test.** Changing an expectation needs evidence the assertion
  was wrong. The ratchet floors in `tools/gate_ratchet.json` are
  minimums; raise them only from a committed log and never lower one.
- **Parity-only is a governance flag, not a fork.** `TAT2_PARITY_ONLY=1` may only
  drop `tat2_expansion` classes; the 11 content-override rules are all
  `parity_restoration` and an unclassified rule must fail closed. `a2`/`p2` and
  the 120-row baseline must state which build they used.
- **Collision is authored `AggGeom`** (`TAT2_COLLISION=authored|aabb`); planar
  convexes are skipped; stairs are exempt from the hull cap. Do not "fix" a
  floating surface by moving the loader's grounding offsets — check the ray first.
- **Guard selection is `PARITY_APPROX`.** Bucket/layer selection is authored;
  the 4/6/8 count is a `PORT_DECISION`. Keep the `spawn_marker`, `grounded_spawn`,
  `spawn_bucket` and `spawn_layers` metas and the
  `selection=parity_approx_layer_bucket` diagnostic.
- **Beam axis is the device column 2.** `beam_card_transform()` must keep the
  0.102 m authored mesh length in the calculation, apply the authored length
  without a ceiling, and keep `BEAM_AXIS ... clamped=0`. The `MESH_RECON`
  `mirrored=` count is the winding follow-up, not a beam bug.
- **A2-WHITE samples surface materials, not `material_override`.** A port-built
  `MeshInstance3D` with only an instance override reads as glTF-default white in
  the acceptance audit. Bind the material on the mesh surface
  (`surface_set_material`) as well; `SafeRoomPortalOutline` at `3998761` is the
  measured regression (fixed in `78884fe`).
- **The StateTree runs in shadow** (`TAT2_STATETREE=off|shadow`): the FSM still
  drives. Payload v2 has the parameters/bindings; the runtime still flattens
  nodes to names, so `0/21` trees are fully evaluable. Do not invent parameters.
- **GC smash is a labelled port decision.** 336 hidden components / 264 actors,
  95 hidden Guildhall_Loot layers, 79 intact leaves. Tap keeps the lockpick path;
  the deliberate held-secondary break is temporary until the authored damage path.

## 8. Where the evidence lives

- `docs/reports/p1-integration-20261126.md` — the P1 measured table and exact lines (current).
- `docs/reports/logs/p1/full/` — the 40 gate logs + the cream expected failure;
  `docs/reports/logs/p1/pre-fix/` holds the merged-tip `A2-WHITE` red proof.
- `docs/reports/p1-safe-lane.md`, `p1-doors.md`, `p1-beams.md`, `p1-ward.md`,
  `p1-street-20261126.md` — the five lane reports.
- `docs/reports/p0b-20261126.md` + `docs/reports/logs/p0b/full/` — the preceding P0b run.
- `docs/reports/p0b-harness.md` — the Lane H acceptance-harness report.
- `docs/reports/p0b-live-capture.md` — live-reference prep and blockers (no launch).
- `docs/reports/p0a-20261126.md` + `docs/reports/logs/p0a/` — the preceding P0a run.
- `docs/reports/logs/w10/` — the W10-A run (historical).
- `docs/reports/r8-remediation-20261125.md`, `w9-remediation-20261125.md`.
- `build/qa/w10/` — W10-A report/audits and the guard investigation.
- `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` — 120-row scorecard.

## 9. Definition of done for the next run

```bash
git status --short                    # clean, or only intentional evidence
build/qa/run_p0b_gates.sh             # 40 gates + cream RED, stops on first unexpected failure
make gate-ratchet                     # PASS against the committed p1/full logs
git push origin main
```

When a gate value moves, update `tools/gate_ratchet.json`, the report it names
(`docs/reports/p1-integration-20261126.md` or its successor) and this file in the
same wave. Never fabricate a capture, ROI or timing: say "not verified" instead.
