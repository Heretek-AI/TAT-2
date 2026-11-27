# Handoff — Thick As Thieves Godot 4.7.2 port (next session)

**Repo:** `/home/john/Projects/TAT-2`
**Code/data tip:** `5135f53` (W10 FINAL: P2-ST StateTree B2.1, P2-NAV Detour
spike, P3 Wwise control plane, P5 UI, W10-P2 data, Den restore; regenerated
`game/data/generated` and re-stamped audit baseline). Branch measured:
`w10/final-evidence`; the integrator merges it.
**Working tree:** clean apart from private/derived data; the FINAL gate logs are
in `docs/reports/logs/final/`.
**Godot:** `4.7.2.stable` via native `tools/godot` (`godot` is **not** on `$PATH`).
**Renderer:** Forward+ · Jolt 60 Hz · 1280×720 reference · Linux x86_64.
**Steam reference:** `/home/john/.steam/steam/steamapps/common/Thick As Thieves/`.
**Single-Godot lock:** `/tmp/opencode/tat2-godot.lock` (never wrap
`build/qa/runtime_smoke.sh`, `build/qa/p0b_capture.sh` or
`build/qa/navmesh_spike.sh` in an outer `flock`; they take the lock themselves).

## 1. State in one paragraph

W10 FINAL merged five lanes and measured them at `5135f53` in one serial
`build/qa/run_final_gates.sh` run — **44 gates, all exit 0**, logs in
`docs/reports/logs/final/`, report
[`reports/final-20261127.md`](reports/final-20261127.md). `compile` is **217/0**,
`run_tests` **324/0** (suites **119** cream and **121** audio registered), M2
**12/0**, E2E **300/300** (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22), p2 **14/14**
with `expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0`, parity-only
**60/60**, cream **GREEN** `passes=5`, audio **71**, P5 UI **44**, Den spawn
**9**, P1 probes **86/47/7/44/31**, audit **12,660/12,703**, string audit
**311/311/199/199/112**, perf guard **78/78**. Collision is re-based to authored
**element** coverage (`868852` ppm; Guildhall 0.910, Old Manor 0.912, FTUE 0.869,
`no_record=0`): the old `976321` counted invented render-trimesh fallbacks, a
deliberate truth correction, not a regression. Cream/invented white and the
civilian pants albedo are **closed** (suite 119 green; p2 has no expected
failure). P2-ST B2.1 reads payload-v2 node parameters (566/566 keys, 676
bindings) and measures one structurally covered tree
(`ST_Subtree_IntruderNoLongerSuspicious`), zero parity-covered; `TAT2_STATETREE`
stays `off` and the FSM still drives — **no cutover**. P2-NAV proved the cooked
Guildhall Detour tiles (2,958 tiles / 14,930 polys) and a Godot consumer
(**16/0**, 3-waypoint doorway, sync 975 ms, total 1,172 ms); the **P1 Detour
consumer is the next navmesh lane**, and no runtime region exists yet. P3 audio
is a **partial** control plane (14/23 switch groups, 4/8 states, 16/50 RTPCs);
P5 UI is **headless-verified, not visually scored** (Light Gem `PORT_APPROX`,
one documented `Thieves' Den` port copy). The Den shell/floor are restored
(`source=authored`). The live-reference/120-row baseline and a GPU capture are
still **pending** — no visual parity PASS is claimed.

## 2. Gates at this HEAD (all measured, logs in `docs/reports/logs/final/`)

Run: `build/qa/run_final_gates.sh` on
`5135f53dfff8a9b268576f7731588ab7a0be3494` (Godot
`4.7.2.stable.official.ed1daf0bf`), **19 m 32 s** wall. Every gate exited 0;
there is no expected failure any more. The runner stops on the first unexpected
non-zero exit and writes every command line, start/finish and exit code under
`docs/reports/logs/final/`. Two supplemental one-Godot detail runs (suite 110
and the navmesh spike) are in the same directory.

| Gate | Value |
|---|---|
| compile | **217 checked, 0 broken** |
| `run_tests.gd` | **324 PASS, fails=0** (suites 119 cream + 121 audio registered) |
| `test_m2_player.gd` | **12 PASS, fails=0** |
| P1 probes | `P1_SAFE PASS checks=86` · `P1_DOORS checks=47 fails=0` · `P1_BEAMS PASS checks=7` · `P1_WARD PASS checks=44` · `P1_STREET PASS checks=31 hard_limits=2` |
| guard, Guildhall Contract 2 | `GUARD_CHECK PASS ... guards=4 buckets=4/4 lounge=1 lounge_marker=C_20 selection=parity_approx_layer_bucket` |
| guard, Old Manor `--order=3` | `GUARD_CHECK PASS ... guards=4 buckets=4/4 lounge=0` (Novice-labelled) |
| beams | `BEAM_GEOMETRY_SUMMARY: fails=0` — `cards=330 max_axis_err_deg=0.000006 clamped=0` |
| GC / turret / civilian | `GC_PROBE PASS` (44) · `GC_TRIGGER PASS` (21) · `TURRET_PROBE PASS` (229 actors, 1,145 parts, 0 hidden) · `W10A2_CIV_SUMMARY: fails=0 passed=23` |
| probes | doorwalk · viewmodel truth · Niagara (3695 authored / 1048 active / 16 systems in probe scope) · blackjack · geometry (7/7) |
| collision | `COL_MAPS PASS maps=3 min_coverage=0.869 dropped=0 planar_skipped=2 coverage_ppm=868852` (element coverage; `no_record=0`) |
| lock inventory | `applied=154 containers=144 door_nodes=10 state=APPLIED` |
| `probe_leak` | clean (`TAT2_NO_DEN_PROBE=1`, `res://probe_leak.gd`) |
| E2E | **300/300**, `fails=0 passed=300 total=300` (T1=117 T2=110 T3=25 T4=14 S2=12 A2=22) |
| E2E tier `a2` | **22/22** standalone |
| E2E tier `p2` | **14/14**, `expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0` |
| parity-only | **60/60**, 11 rules all `parity_restoration`, 0 unclassified |
| cream suite 119 | `CREAM_PROOF: GREEN passes=5 expected_fail=0`, exit 0 (no RED proof) |
| audio suite 121 | `AUDIO_CONTROL_SUMMARY: fails=0 checks=71` |
| P5 UI probe | `P5_UI PASS checks=44` (headless; not visually scored) |
| Den spawn | `DEN_SPAWN PASS checks=9 fails=0` (`source=authored`, 2434 meshes) |
| capture harness | dry-run `poses=6` manifest valid under `final/dry-run` · self-test **21/21** · KF27 reference **7/7** |
| `make runtime-smoke` | **PASS** (`RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 mission_ready=1`) |
| `make audit` | PASS — 12,660/12,703, 0 unexpected, baseline matches |
| texture cap | 796 capped / 1 alpha-critical kept / 0 offenders (target set 1567) |
| perf guard | 78/78 |
| `make gate-ratchet` | PASS (`measured_on=5135f53`; floors raised, never lowered) |

**Caveat:** no live reference capture and no GPU capture in this wave. The P1
port capture exists (`logs/p0b/20261127T015115Z_...`), but the 120-row baseline
still needs the shipped reference and the P5 rows are not visually scored. The W9
interior numbers were measured on a frame with a light-card slab covering half
the screen and are **not** a valid interior baseline.

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

**Closed by W10 FINAL (`5135f53`)**

- **Cream / invented white** — `_apply_ue_emissive()` requires an authored
  `EmissiveColor` or emissive map; the suppression is counted
  (`tat_invented_white`), and an authored colour still emits. Suite **119** is a
  green gate. The cream bars in old captures are the `SM_LightBeam` cards.
- **Civilian pants albedo** — `BaseColorOpacity` is the authored base colour
  (alpha = mask), `Source Color Texture` is a fallback; 19 albedo bindings
  corrected, 75 bogus opacity binds removed, p2 **14/14** with no expected
  failure.
- **Collision truth** — authored element coverage replaces the fallback-inflated
  ratio: `COL_MAPS PASS min_coverage=0.869 coverage_ppm=868852 dropped=0
  planar_skipped=2`, `no_record=0`; 334 BodySetups with no `AggGeom` are
  classified (`293 complex_as_simple`, `41 no_collision`). The ratchet floor is
  re-based, not lowered for the same metric.
- **Den shell/floor** — the narrowed developer-mesh skip restores the authored
  hub; `DEN_SPAWN PASS checks=9` pins `source=authored`.
- **StateTree node identity** — payload-v2 parameters/bindings are consumed by
  `(tree,node_index)` (566/566 keys); one structural tree is covered; the
  runtime is still shadow-only.
- **Navmesh data** — the cooked Detour tiles are extractable and consumable
  (2,958 tiles / 14,930 polys; 16/0 spike). The runtime consumer is not built.

## 4. Open work (measured/recorded, not hidden)

| Defect / item | Evidence | Next step |
|---|---|---|
| **Port capture (P1 tree)** | corrected six-pose run at `fafb78f` (`logs/p0b/20261127T015115Z_...`): gate 23.85, upper_foyer 40.88, yaw180 39.47, Lounge 28.37; thin beam line, no cream bars; audio 92.8 s/0 dropped. W10 FINAL ran **no GPU capture** | inspect KF14/15/16/23/24/27/28/29, then score the rows with the live reference |
| **120-row baseline unscored** | instruments ready; live reference prepared, nothing launched (`reports/p0b-live-capture.md`) | score the 120 rows on the parity-only build with recorded evidence |
| **Cream / invented white** | W10-P2 **closed at `5135f53`**: suite **119** green (`passes=5`), `tat_invented_white` census, authored-colour control; the cream bars in old captures are the `SM_LightBeam` cards | beam full-tube pixel falloff is P4 |
| **Civilian pants albedo** | W10-P2 **closed**: `BaseColorOpacity` → albedo, `Source Color Texture` fallback; p2 `expected_fail=0` (14/14), 19 albedo bindings corrected, 75 bogus opacity binds removed | none; the audit `texture_refs 1523 → 1522` drop is accepted |
| **Collision coverage metric** | W10-P2 **re-stamped**: `no_simple_collision` (334 packages), authored element coverage 0.910/0.912/0.869, `coverage_ppm=868852`, `no_record=0`; the old 976321 counted invented fallback collision | playtest the class that is now non-solid (skybox buildings, tarps, cobwebs, street-lamp glass, turret bulb, donut shell — all authored `NoCollision`); no floor/stair/wall/door/container is in it |
| **Texture cap target set** | 796 capped / 1 alpha-critical / 0 offenders; targets 1567 after the accepted `texture_refs 1523 → 1522` drop | none; the count follows the target set |
| **P3 audio control plane (partial)** | `audio_control.json`: 14/23 switch groups, 4/8 states, 16/50 RTPCs, 142 curves; 71/71 checks. Wired: footstep surface/gait, interior/exterior, modal, detection RTPC→music gain/pitch | state property rows (per-node overrides), music switch `DecisionTree` keys, `FS_Layers`, named-RTPC low-pass; no full mix/music/VO claim |
| **P5 UI (headless-only)** | `P5_UI PASS checks=44`: gem lit cap/direction, card/compass, loadout hotbar, pause blur/dim, 11-line briefing, `CRANK [LMB]`, authored map names; Light Gem `PORT_APPROX` (21-slice array absent) | GPU capture KF17/KF16/KF25 (gem), KF30 (pause), KF13 (briefing), then score the rows |
| **P2-NAV Detour** | spike `16/0`: 2,958 tiles / 14,930 polys / 221 off-mesh; doorway 3 waypoints 4.15 m; sync 975 ms, total 1,172 ms, 61.8 MB; no runtime region | **P1 Detour consumer** next: compact asset, async/prebuilt region, 221 `NavigationLink3D`, authored areas 63/3/1, then wire `nav_steering` in a separate lane |
| **Den shell/floor** | narrowed `/Game/Developers/` skip restores `gjasp/SM_ThievesDen` + `_Floor`; `DEN_SPAWN PASS checks=9` (`source=authored`, 2434 meshes, floor+shell shapes) | none; keep the probe fail-closed |
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
| **StateTree** | B2.1 merged: node-aware payload v2 (566/566 keys, 497 parameter nodes, 676 bindings), suite 110 191 checks; `fully_covered_trees=1` (`ST_Subtree_IntruderNoLongerSuspicious`), `fully_parity_covered_trees=0`; `TAT2_STATETREE` default `off`, `patrol` not enabled | producer contract for the remaining task/condition parameters; a cutover only after parity coverage — never invent values |
| **Perf matrix** | thermal gate waived; headless only | no parallel Godot; do not claim 60 fps |

## 5. Wave plan for the next session

**1 — live reference + score the 120 rows (do this first).** The corrected P1
six-pose capture exists (`logs/p0b/20261127T015115Z_...`). Follow
`docs/reports/p0b-live-capture.md` for the shipped reference and score the 120
rows from
`docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` on the
parity-only build, publishing an honest per-row PASS/PARTIAL/FAIL with recorded
evidence. Do not re-grade on frame `215507`.

**2 — P1 Detour consumer (navmesh).** Convert `tat2.nav_tiles/1` to a compact
versioned runtime asset, build one `NavigationMesh` per map with an
async/prebuilt commit (budget 1.0–1.5 s headless; the spike measured 975 ms
sync), consume the 221 off-mesh connections as `NavigationLink3D` (authored
radius/height/flags, dedupe tile-border endpoints), map authored areas 63/62/1/3/4
to navigation layers/costs (never treat 63 as Recast null), and only then wire
`nav_steering` in a separate lane. Keep the no-map straight-line fallback.

**3 — P5 UI capture + audio second slice.** Capture KF17/KF16/KF25 (gem),
KF30 (pause), KF13 (briefing) and the prep/map screens, then score UI3-05,
UI3-01, UI3-02, UI1-02, UI4-04, UI4-03, UI2-04, UI3-06. In parallel, add the
audio state *property* rows, resolve the music `DecisionTree` keys, wire
`FS_Layers`, and decide whether a named RTPC low-pass curve exists.

**4 — StateTree data.** The remaining 56 blind task instances and 20 blind
condition instances need authored parameters from a producer contract; a cutover
waits for a parity-covered tree. Do not invent EAlertnessLevel/Delay/MoveTo/Bool
Compare operands.

**5 — look.** AEM/IBL/EV bias, mirrored winding and the landscape docs/A-B; the
beam material is authored but its pixel falloff is still `PORT_APPROX`.

## 6. How to run everything

```bash
build/qa/run_final_gates.sh  # 44 gates -> docs/reports/logs/final/ (no outer flock)
make run                     # native client
make test                    # run_tests (324)
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"  # 217
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
tools/godot --headless --path game --script res://tests/test_w10a2_cream.gd            # GREEN passes=5
tools/godot --headless --path game --script res://tests/test_audio_control.gd          # 71
tools/godot --headless --path game --script res://tests/probe_p5_ui.gd                 # 44
tools/godot --headless --path game --script res://tests/probe_den_spawn.gd             # 9
tools/godot --headless --path game --script res://tests/test_w9p4_statetree.gd         # 191 detail
TAT2_NAV_JSON=/tmp/opencode/nav-spike/nav/Maps/Guildhall/Guildhall_P.json build/qa/navmesh_spike.sh  # 16
build/qa/p0b_capture.sh --dry-run && build/qa/p0b_capture.sh --self-test
build/qa/p0b_capture.sh       # real Vulkan capture, one GPU job, after the gates
make runtime-smoke           # exit 124 only, ERROR: scan
make audit && make gate-ratchet
TAT2_GUARD_DIAG=1 tools/godot --headless --path game -- --qa-free-play   # guard spawn diagnostics
```

## 7. Invariants and hazards

- **Single Godot at a time.** Use `flock /tmp/opencode/tat2-godot.lock` for every
  invocation; never wrap `runtime_smoke.sh`, `p0b_capture.sh` or
  `navmesh_spike.sh` (they take the lock themselves) and never run two
  GPUs/captures in parallel. Never edit `game/` while a run is live.
- **A fresh worktree needs `--import` once.** A copied `game/.godot` does not
  know a new global `class_name`: compile fails with `Identifier
  "AudioControl"`/`"ParityGovernance" not declared` and `test_parity_only.gd`
  says `GameState autoload missing`. Run `tools/godot --headless --path game
  --import`; it writes only gitignored state and local `.uid` sidecars.
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
  convexes are skipped; stairs are exempt from the hull cap. The gate is authored
  **element** coverage (`COL_MAPS PASS min_coverage=0.869 coverage_ppm=868852
  dropped=0`), never the old fallback-inflated `0.989`/`976321`. Do not "fix" a
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
- **The StateTree runs in shadow and is node-aware** (`TAT2_STATETREE=off|shadow`;
  default `off`; `patrol` is not enabled and warns that it runs shadow): the FSM
  still drives. B2.1 reads payload-v2 parameters/bindings by
  `(tree,node_index)` (566/566 keys), but only `fully_covered_trees=1`
  (`ST_Subtree_IntruderNoLongerSuspicious`) and
  `fully_parity_covered_trees=0`; 56 task and 20 condition instances are blind.
  Do not invent parameters and do not claim a cutover.
- **GC smash is a labelled port decision.** 336 hidden components / 264 actors,
  95 hidden Guildhall_Loot layers, 79 intact leaves. Tap keeps the lockpick path;
  the deliberate held-secondary break is temporary until the authored damage path.

## 8. Where the evidence lives

- `docs/reports/final-20261127.md` — the W10 FINAL measured table and exact lines
  (current; `measured_on=5135f53`).
- `docs/reports/logs/final/` — the 44 gate logs, the two supplemental detail logs
  and the capture dry-run manifest. This is the current ratchet evidence.
- `docs/reports/logs/p1/full/` — the prior P1 40-gate logs + the cream expected
  failure; `docs/reports/logs/p1/pre-fix/` holds the merged-tip `A2-WHITE` red proof.
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
build/qa/run_final_gates.sh           # 44 gates, stops on the first unexpected failure
make gate-ratchet                     # PASS against the committed final/ logs
git push origin main
```

When a gate value moves, update `tools/gate_ratchet.json`, the report it names
(`docs/reports/final-20261127.md` or its successor) and this file in the same
wave. Never fabricate a capture, ROI or timing: say "not verified" instead.
