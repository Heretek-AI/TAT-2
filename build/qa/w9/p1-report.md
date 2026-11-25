# W9-P1 — data consumption and visual truth (report)

Phase lead: W9-P1. Worktree `/home/john/Projects/TAT-2-rem-w9-p1`, branch `rem/w9-p1`,
base `c2a1cd8` (W9-P0). **Nothing pushed, merged or rebased.**
Every Godot invocation ran under `flock /tmp/opencode/tat2-godot.lock`; every
capture ran alone under `xvfb-run`; no producer, `make normalize` or
`make audit-refresh-stamps` was run (the data tree is read-only for this phase).

## 0. Capture outcomes — read this first

All frames are 1920×1080 Vulkan, `TAT2_AO=on`, measured with the L1 pipeline
(`python3 build/qa/w9_frame_stats.py`), not with the in-engine non-black guard.

### 0.1 Mission prep now reads as KF11 at the authored camera

| frame | mean | p50 | p95 | %<8 | %<16 |
|---|---|---|---|---|---|
| **before** `p1_before_prep.png` (2.6 exposure, lobby composition) | 37.2 | 25 | 128 | 7.1 | 34.1 |
| legacy composition + authored grade `p1_after_legacy.png` | 27.2 | 12 | 117 | 16.6 | 64.3 |
| **after** `p1_after_prep.png` (authored composition + authored grade) | **37.1** | **19** | 125 | **18.8** | 43.7 |
| after, `prep_skyline` freed `p1_after_nosky.png` | 43.9 | 29 | 126 | 8.8 | 33.4 |
| **KF11 official** | 37.2 | 28 | 85 | 22.9 | — |

- The mean matches KF11 exactly (37.1 vs 37.2) and the black floor moved
  7.1 % → **18.8 %** toward KF11's 22.9 %. `p50` is *lower* than KF11 (19 vs 28)
  because the sky is now a large dark area; that is composition, not exposure.
- **`prep_skyline` is now provably visible**: freeing the 8 expansion pieces
  moves the frame by 6.8 mean / 10 p50 / +10.0 points `%<8`, RMSE **5977 (9.1 %)** — against the P0 result of 959 (1.5 %), i.e. indistinguishable from
  noise. The pieces are the mid-ground silhouette, not the near roof.
- **Stage area only** (crop x ≥ 0.55, where the 3D stage is not under the cards):
  before 37.6 / 31 / 80 / 2.3; after **36.8 / 28 / 73 / 28.0**; nosky 51.8 / 66 /
  74 / 5.3; legacy 18.3 / 12 / 57 / 16.2; KF11 44.7 / 33 / 91 / 15.1. The
  whole-frame p50 (19 vs 28) is therefore a **UI-layout difference**: the port's
  card stack covers ~55 % of the width where KF11 covers ~36 %, so the stage is
  correct at p50 28 (KF11 33) while the frame is pulled dark by the cards.
- The composition fix is a **cull rule, not a camera move**: `kept=19 hid=397
  radius=9.0` around the authored thief slot, camera/thief/expansion ring
  untouched (`TAT2_PREP_STAGE=legacy` reproduces the old frame: `kept=422
  hid=0`).
- The stage grade landed: `TAT-2 prep grade: tonemap=4 exposure=1.150
  ambient=0.350 glow=0.1267 sky=1.000` (was 2.6 / 1.8 / 1.0 / 0.18; the "ACES"
  label was stale — the preset apply already forced AGX).

### 0.2 Guildhall interiors: the band is NOT met, and a global cut is proven wrong

Measured with `build/qa/w9_grade_probe.gd` (one launch, timed A/B `grade8`,
wall 97 s, GPU 60.67 → 65.83 °C, 5454 → 5779 MiB):

| pose | exposure 1.15 (today) mean/p50/p95/%<8 | exposure 0.44 mean/p50/p95/%<8 |
|---|---|---|
| KF16/KF18 gate approach | 23.2 / 10 / 66 / **23.9** | 12.5 / 3 / 40 / **72.0** |
| `upper_foyer` | 50.4 / 34 / 182 / **0.8** | 28.8 / 15 / 130 / **8.0** |
| `foyer_sweep_yaw180` (KF27) | 40.5 / 31 / 105 / **2.3** | 21.5 / 13 / 73 / **22.4** |
| `foyer` (lower approach) | 31.5 / 32 / 58 / **1.3** | 15.0 / 13 / 34 / **36.1** |

Gate ladder at one launch (`grade7`, wall 283 s): 1.00 → 21.3 / 9 / **38.0 %**;
0.85 → 19.3 / 7 / **51.8 %**; 0.75 → 17.9 / 6 / **59.6 %**.

**The interior target (p50 13-15, `%<8` 9-24) is reachable — at ≈0.44 — but only
by crushing the same preset's gate view**, which is *already* below its own
KF16/KF18 reference at 1.15 (p50 10 against a p50 26-28 target) and loses black
floor for every step removed. One `gloomy` Environment cannot move in both
directions, so **no global exposure/ambient change shipped** and
`weather_profile.gd` is byte-identical to `c2a1cd8`.

The room-local cause is measured: the two shadowless foyer fills
(`mission_controller.gd:564-580`, energy 1.6 at 3.3 m and 1.3 at 14.1 m from the
upper-foyer eye) own that pose's overshoot. Freeing them at one exposure moves
`upper_foyer` 28.8 → 22.7 mean, p50 15 → 9, `%<8` 8.0 → 32.2, while `yaw180`
barely moves (21.5 → 20.3). **Verdict: BLOCKED-ON P2** (per-room grade), with a
guard suite (98) that fails if anyone lands a global cut without the room scope.

### 0.3 Two stale scorecard rows corrected (V4-07, V6-03)

- **V4-07** "no velvet armchair/ottoman" is **false**: `p1_before_foyer_sweep_yaw180.png`
  shows a tufted armchair, a red ottoman, the marble-topped vitrine, columns, an
  archway and a bust on a plinth. The row stays `DELTA` (no flush floor plate,
  no `Basement Stairs`/`WC` plaques).
- **V6-03** "no beam, wall emitter" is **false for the beam**: a live
  `BP_Detector_LightBeam_C` from an authored `light_beam` device crosses the hall
  in `p1_before_upper_foyer.png` / `..._yaw180.png`. The circular wall emitter and
  the cyan ceiling diamond are still absent → `N/A-route` → `DELTA`.
- Tally re-counted over all 120 rows with a script: `PASS 9, DELTA 33, MISSING 4,
  HARD_LIMIT 2, UNVERIFIED 16, N/A-route 56 = 120`; coverage `48 + 56 + 16 = 120`.
  No other row, and no template order, changed.

## Commits on `rem/w9-p1`

| commit | content |
|---|---|
| `ccd24d9` | scorecard V4-07/V6-03 + §5 tally |
| `d30fe5b` | interior grade bracket probe (A4 evidence harness) |
| `9c33541` | sprite token re-resolution (A3b) |
| `5b112b1` | generated input table + curves consumers (A3a) |
| `bb37003` | authored progression: XP/25/endgame/FTUE (A2) |
| `b57bbf7` | prep composition + authored stage grade (A4) |
| `ff0f21d` | authored AggGeom collision behind `TAT2_COLLISION` (A1) |
| `5a516f9` | E2E T1-16-D expects the authored sensitivity curve |
| `d7085f5` | prep call-site evidence (comments only) |
| `8a3c113` | audit findings: suite-98 literal floor, ladder constant + W9.7d, port-decision labels, sprite `changed>=2`, allowlist rules removed |

## A1 — COLLISION-WHOLE (user decision: every mesh at once)

### W9-P1-A1-1 — authored `AggGeom` replaces the AABB heuristic
- **investigate:** `level_loader.gd:1811-1905` (`_get_mesh_and_shape`): the shape
  was a `BoxShape3D` of the render AABB when `sz.length() > 0.45` and the name
  was not in the `is_nonblocking` token list, a door trimesh, a roof convex or a
  large-mesh trimesh; the cache is per UE path (`:1904`), one
  `CollisionShape3D` per placed instance (`:4029-4070`). `mesh_collision.json`
  had **no consumer** (`grep` = 0 in `game/src`).
- **research:** `build/qa/w9/re-a1.md` resolved the semantics from the UE dump:
  cm mesh-local; `P(v)=(x,z,y)·0.01`; basis `P·M·P`; **`half_extent` is the FULL
  extent (the producer's name and NOTES are wrong by 2×; 453 meshes measure
  `2X/mesh = 1.9997`)**; `sphyl` is Z-aligned and `Length` excludes the caps
  (`height=(L+2R)·0.01`); `convex` bakes `quat·(scale3d⊙v)+t` and its
  `aabb_min/max` is the pre-transform AABB; `NoCollision` → no shape,
  `QueryOnly` → shape kept; a BodySetup with no `AggGeom` is complex-as-simple
  (the render trimesh *is* authored).
- **confirm (red):** `COL_AUDIT mode=aabb ... shapes=24465 bodies=225` — and the
  0.45 m gate dropped 2,878 instances (24,344 collided of 27,222 placed).
- **fix:** new `game/src/core/collision/authored_collision.gd` (load once, index
  by package path, build shared `Shape3D` sets), `level_loader.gd` collision
  hunks (mode flag, `_heuristic_shape`, `_add_collider_shapes`, counters,
  wall-clock guard), `TAT2_COLLISION=authored|aabb` (default authored).
- **test / confirm (green):** `bash build/qa/w9_collision_ab.sh`:

  ```
  COL_AUDIT mode=authored placed_meshes=947 placed_instances=27222
    authored_hull=937 authored_prims=599 absent=10 no_collision=7 query_only=7
    reduced=16 shapes=30901 bodies=243 dropped=0 load_ms=23544
  COL_AUDIT mode=aabb     placed_meshes=835 placed_instances=24344
    authored_hull=0 absent=835 shapes=24465 bodies=225 dropped=0 load_ms=19891
  delta: shapes +6436 | bodies +18 | placed_instances +2878 | dropped 0 -> 0 | load_ms +3653
  ```

  **Authored-derived coverage 937/947 = 98.9 %** (DoD ≥95 %): 868 element hulls +
  69 complex-as-simple tri meshes; the 10 `absent` paths are all `/Game/Test/`
  graybox with no dump at all, named and counted. `run_tests` census:
  `shapes=30905, collision_bodies=243, PASS: Perf chunking (... shapes=30905 ...)`.
- **verdict:** **FIXED**, with one open item: `test_roof_collision.gd` (a
  standalone probe, **not in any gate**) encodes the one-mesh-wide-convex
  heuristic and fails 9 assertions in authored mode (`aabb` mode `fails=0`).
  The authored roofs are 3-13 per-element hulls; the probe must measure the union
  of `shapes` (owner action, recorded in `docs/FIDELITY_GAPS.md`).

### W9-P1-A1-2 — the conversion is measured against the render mesh
| type | mesh | authored AABB vs GLB AABB | max axis error |
|---|---|---|---|
| box | `SM_Urban_Ext_Wall_4x6` | exact | **0.000 m** |
| box | `SM_Urban_Ext_Wall_2x6` | exact | **0.000 m** |
| box | `SM_Civic_RailA_1x1` | trim not in the box | 0.036 m |
| sphyl | `SM_PillarBasementA_12m` | `L+2R`=13.19 vs 12.0 mesh | 1.189 m (authored overshoot) |
| sphyl | `SM_CandleA` | — | 0.039 m |
| convex | `SM_Civic_GuildhallOfficeFloor` | — | **0.002 m** |
| convex | `SM_Stairs_Civic_GuildhallEntrance` (5 hulls) | — | 0.236 m (hull fit) |
| convex | `SM_Urban_ext_Door_4x6` (6 boxes) | frame trim not authored | 0.230 m |

- **Budget:** the measured building demand is 30,877 shapes, so the partition
  moved `28,000/4,000` → **`31,400/600`** (523 headroom, 22× the measured curb
  peak); `MAX_TOTAL_SHAPES` stays 32,000 and the `col_shapes < 32000` gate is
  unchanged. 16 meshes (bay windows, roof corners, bookcases) are coalesced to
  one shape, named in `reduced=16`.
- **Traversal, flag on (the default):** `M2_SUMMARY: fails=0`, `DOORWALK PASS`,
  `VIEWMODEL_TRUTH PASS`, `GEOM_PROBE PASS`, `BLACKJACK_PROBE PASS`,
  `NIAGARA_PROBE PASS`, `run_tests fails=0`, `probe_door_aperture PASS`. **No
  physics constant was tuned and `thief_character.gd` is untouched.**
- **Cost:** +2.5-3.7 s level load (+13-18 %); JSON parse 0.25 s, the rest is 30k
  shape creations. `fps_pose` **not verified** (no GPU pose taken).
- **Fix found on the way:** `load_sublevels_async` never called
  `_build_draw_items`, so the cost cap saw `instances=1` and dropped 2,411
  colliders; `_fill_col_path_counts()` now runs on both paths.

### W9-P1-A1-3 — audit findings closed
- **F1 (degenerate gate):** `placed_meshes_seen` is now the draw-item census taken
  before classification, so the probe asserts a **falsifiable** identity
  (`hull + absent == seen`), `prims <= hull`, and **coverage >= 0.95**:
  `COL_ASSERT coverage=0.989 (937/947) prims_subset=true classification=937+10==947
  mode=authored dropped=0`.
- **F2 (77 MB of Jolt errors):** the instance's non-uniform scale is now baked
  into each shape's own axes (`scaled_variant`, cached by path+scale) instead of
  `CollisionShape3D.scale`, which Jolt refuses for capsule/convex/trimesh. Before
  `grep -c "not supported by Jolt Physics"` = **95,293** / 77 MB; after **0** /
  **7,290 B** (whole probe log); `run_tests` 0 / 251,947 B. Shapes unchanged
  (30,901 / 30,905, dropped 0). Residual: a non-uniformly scaled capsule/sphere
  cannot represent an ellipsoid, so its radius takes the mean lateral factor.

## A2 — PROGRESSION (user decision: adopt authored)

### W9-P1-A2-1 — the authored trajectory, a save migration, and the market gates
- **investigate:** `save_system.gd:1091` awarded `maxi(100, score/2)`; the level
  cap was the defensive 200 (`level_for_xp` at 1,000,000 XP → 200); the endgame
  window came from the quest graph (480/300) with the KF13 1200 override; a fresh
  profile had 0 currency; `project_settings.json` had **no consumer**.
- **research:** `CT_XPToLevel` is a 7-key `RCIM_Linear` curve → 500×4, 1000×5,
  2500×15 (levels 1-24), cumulative 44,500 to level 25; `MaximumLevel=25`;
  `EndgameDurationsByDifficulty [1200,600,300]` (index order labelled unproven by
  the producer); `FtueMinThievesDenMoney 5000`; 11 `XP.*` weights; the scoring
  bonuses; `maps[].missions`.
- **fix:** new `game/src/core/progression.gd`; `save_system.gd` (cap 25 with XP
  kept, authored award, FTUE 5,000 + one-shot `_migrate_progression`),
  `game_data.gd` (KF13 → ladder → QG → 480), `game_state.gd` (publish the
  difficulty index), new `game/tests/test_w9_progression.gd` (35 checks).
- **before/after table** (the DoD table):

| level | XP to leave | cumulative | before (no cap) | after |
|---:|---:|---:|---|---|
| 1-4 | 500 | 0 / 500 / 1000 / 1500 | same curve, but level 200 reachable | **cap 25** |
| 5-9 | 1000 | 2000 … 6000 | " | " |
| 10-24 | 2500 | 7000 / 9500 … 42000 | " | " |
| 25 | 2500 | **44500** | — | level 25; 500,000 XP keeps 500,000 XP |
| 26+ | — | 44500 | level 26+ up to 200 | clamped at 25, cumulative stays 44,500 |

| gated item class | authored level | cumulative XP | before | after |
|---|---:|---:|---|---|
| 48 cosmetic rows | 2-23, 25 (no 1, no 24) | 500 … 44,500 | same levels, no cap so the tail was unreachable-by-design | identical levels, level 25 reachable at 44,500; ModelShip ×2 locked at 44,499 |

| mission class | Novice | Thief | Master Thief | source |
|---|---:|---:|---:|---|
| LootTheRoom | 1200 | 1200 | 1200 | KF13 override (first branch, unchanged) |
| VaultHeist | 300 → **1200** | 300 → **600** | 300 → **300** | project_settings ladder |
| OldManor Vault | 480 → **1200** | 480 → **600** | 480 → **300** | project_settings ladder |
| any mission, no index | 480 | 480 | 480 | quest graph / fallback (unchanged) |
| Thieves' Den hub | 0 | 0 | 0 | hub (unchanged) |

| FTUE money | before | after |
|---|---|---|
| fresh save | 0 | **5,000** |
| empty profile at 123 | 123 | **5,000 once** (never re-granted after spending) |
| any completed contract | unchanged | **unchanged** |

- **confirm (green):** `W9_PROGRESSION SUMMARY: fails=0` (35 checks, W9.0-W9.7);
  `test_w7e_endgame` `fails=0`; `test_w6u2_catalog` `fails=0`; the 48 rows
  verified at their authored levels.
- **Expectations changed** (each with the reason in the test): `test_w7e_endgame`
  S5.1c/d/S5.2d (the runtime window now comes from the authored ladder; the QG
  plan assertions stay), `test_t02_save_integrity` T02-01/05/06 and
  `test_w7s_loot_save` 90.30/90.33 (the documented defaults now include the
  5,000 FTUE floor / the progression stamp).
- **verdict:** **FIXED**. **BLOCKED-ON P2:** the scoring bonuses (contract 100 /
  mission 300 / 0.1 loot multipliers) are exposed by `Progression` but the payout
  is composed in `loot_inventory.gd:392`. **DEFERRED:** adopting the authored
  initial/post-FTUE unlock lists at runtime (the FTUE flow does not exist yet).

## A3 — PLUMBING

### W9-P1-A3-1 — the generated input table is what loads; the transcription is gone
- **investigate:** `input_actions.gd:29` named `res://data/generated/input/`
  (does not exist); the producer writes `gameplay/input_actions.json`.
- **confirm (red):** `INPUT_TABLE source=authored rows=56 actions=52 ids=40`;
  `GENERATED_EXISTS res://data/generated/input/input_actions.json = false`.
- **fix:** path + a producer→port adapter (shipping contexts only, 146 dev
  mappings skipped and named), `AUTHORED_ROWS` **deleted** (0 occurrences), the
  only remaining table is 6 `PORT_DECISIONS` entries (port contracts, each with a
  `file:line` consumer).
- **confirm (green):** `INPUT_TABLE source=generated rows=91 shipping=91
  actions=52`; `INPUT_SUMMARY: fails=0 checks=174`.
- **verdict:** **FIXED**.
- **User-visible side effect:** the sensitivity ladders now sample the authored
  `MouseLookSensitivityCurve`/`GamepadLookSensitivityCurve`, so Normal is 1.125×
  (was 1.0) and pad Fast/VeryFast are 1.5625/2.0 (was 1.25/1.5). The ini ladder
  is the documented fallback. `e2e_tier1_features.gd` T1-16-D was updated for it
  (commit `5a516f9`).

### W9-P1-A3-2 — `curves.json` has readers
- **investigate:** the index had 0 readers; its 16 standalone table files loaded
  into `GameData.curves` but `eval_curve` was only ever called with 8 `CT_*`
  names.
- **fix:** `game_data.gd` loads the index once (`standalone_curves`,
  `eval_standalone_curve/range/names`), `eval_curve` honours `RCIM_Constant`.
  Readers wired in P1-owned files: the two look-sensitivity curves and the edge
  boost threshold (`input_actions.gd`), the two light-detection endpoints
  (`light_probe.gd`). The other 11 names are exposed with their owner phase in
  §"Blocked".
- **confirm (green):** `Curve_AI_HeightDifferenceToStrengthMultiplier` at x=2.5
  → 1.0, x=3.0 → 0.0 (Constant interp); all 16 names resolve to a table with
  keys; the light endpoints equal the authored keys.
- **verdict:** **FIXED** for the accessor + 5 readers; 11 readers
  **BLOCKED-ON** their gameplay/AI/UI phases (list in §Blocked).

### W9-P1-A3-3 — sprite token resolution: measured, and the 23/29 target is NOT MET
- **investigate:** `tools/parse_vfx.py::_resolve_sprite_texture` prefers
  albedo/emissive/normal/orm and never opacity; `SpriteMasks.acceptable` then
  rejects 23 of the 29 measured pages, so the sampler stays procedural.
- **fix:** new `game/src/core/vfx/sprite_tokens.gd` re-resolves the authored slot
  from `materials.json` (`opacity → albedo → emissive`, normal/orm only when
  nothing else, first acceptable wins, SubUV atlases recorded and never bound);
  `niagara_library.gd` uses it per sprite renderer. **`sprite_masks.gd` has zero
  diff lines** — the band was not widened.
- **confirm (green):** `NIAGARA_SPRITE_TOKENS bound=5 total=39 legacy=5
  renderers=82 changed=2 slots=opacity:2,albedo:23,emissive:0,normal:0,orm:0,
  none:11,subuv:3 additive_opaque=9 additive_total=16 masks=6/29 ms=41`;
  `NIAGARA_PROBE PASS`.
- **Why 23/29 is not reachable (measured, not excused):** the "29" is a *texture*
  count; only **12** of those 29 are referenced by a *placed* sprite renderer (14 across all 120 systems);
  **20 of the 23 rejected pages carry `alpha_min = alpha_max = 255`** (no
  authored transparency), and only the 2 rain materials even have an `opacity`
  slot. Reaching 23 would need a black-is-transparent additive sampler (+7
  materials / +5 systems), SubUV slicing (+3) and a packed-channel mask reader
  (+2) — a measured ceiling of **15 of 39** placed materials, still far below
  23/29. The probe therefore asserts non-regression and prints the shortfall.
- **verdict:** **PARTIAL** — token resolution fixed and measured (2 rain
  materials now resolve to their authored mask (the packed mask is alpha-less, so the sampler still rejects it — `bound` stays 5), 3 SubUV atlases labelled instead of
  silently claimed); **the DoD number is not met and the report says so**.

## A4 — VISUAL TRUTH

### W9-P1-A4-1 — prep composition and stage grade
- **investigate:** the frame behind the thief is `MissionLobby_Geo3` at 14-22 m;
  the Periphery (306 nodes) is not the occluder (`prep_noperiph` = 37.21 vs
  36.91); `prep_skyline`'s 8 pieces at 310-500 m/`base_y 0` project to sy
  0.746-0.954 — the *near roof* band, and contribute zero pixels.
- **research:** KF11's city silhouette tops are p50 sy 0.372; the authored camera
  (12.6065, -0.16698, -1.05384, fov 20, roll -14.78) sees 387/2,107 pivots.
- **fix:** `_apply_stage_composition` keeps every draw node within
  `LOBBY_STAGE_KEEP_RADIUS_M = 9 m` of the authored thief slot, hides the rest
  (counted, `TAT2_PREP_STAGE=legacy` for the A/B), never moves the camera;
  `prep_skyline.json` re-authored to 260-400 m with `base_y` 18-36 so the tops
  land 0.300-0.440; the stage grade is `WeatherProfile.stage_grade_values()`.
- **test:** `test_t05_ui_contract` P14 prints every piece's measured band and
  asserts `[0.28, 0.46]` (the old `[0.65, 0.98]` encoded the invisible
  standoff); `test_w7v_ui_acceptance` unchanged and PASS.
- **confirm (green):** §0.1 table; `kept=19 hid=397 radius=9.0`;
  `TAT-2 prep grade: ... exposure=1.150 ambient=0.350 glow=0.1267 sky=1.000`.
- **verdict:** **FIXED** (composition + grade), `prep_skyline` **visible and
  proven** (RMSE 5977 / 9.1 %).

### W9-P1-A4-2 — the interior band
- **investigate + research:** see §0.2. One `gloomy` preset grades a too-bright
  interior (p50 34 vs 13-15) and a too-dark gate (p50 10 vs 26-28).
- **fix:** **none** — a global number is proven wrong; the interior branch was
  implemented, measured, and reverted (`weather_profile.gd` byte-identical to
  `c2a1cd8`); no dead `INTERIOR_*` lever ships.
- **test:** suite 98 (`run_tests.gd`) pins AGX 1.15 / ambient 0.16 for the
  Guildhall, the Den's bias+floor, and the one-map `gloomy` scope, so a future
  global cut fails by design.
- **confirm (green):** `PASS: 98 W9-P1-A4 night-grade guard (...)`.
- **verdict:** **BLOCKED-ON P2** with a measured contract: the two foyer fills at
  `mission_controller.gd:564-580` must be scaled per room, or a zone/camera-scoped
  exposure must exist. The target and the attribution are in §0.2.

### W9-P1-A4-3 — scorecard rows
- **verdict:** **FIXED** (§0.3); `ccd24d9`.

## Golden gate set on the merged tree

| gate | result |
|---|---|
| `check_scripts_compile.gd` | **157 checked, 0 broken** (was 152) |
| `run_tests.gd` | **fails=0**, 339 `^PASS` / 0 `^FAIL` (R8 log: 301; +suites 98/99 and their child-engine output) |
| `test_m2_player.gd` | **M2_SUMMARY: fails=0** (12) |
| `probe_door_walk.gd` | **DOORWALK PASS** |
| `probe_viewmodel_truth.gd` | **VIEWMODEL_TRUTH PASS** |
| `probe_niagara.gd` | **NIAGARA_PROBE PASS** |
| `probe_blackjack_race.gd` | **BLACKJACK_PROBE PASS fails=0** |
| `probe_geometry_placement.gd` | **GEOM_PROBE PASS checks=7 fails=0** |
| `probe_collision_authored.gd` | **COL_AUDIT ... dropped=0**, 937/947 = 98.9 % |
| `run_e2e_tests.gd --tier=1` | **fails=0 passed=117 total=117** |
| `run_e2e_tests.gd` | **fails=0 passed=278 total=278** |
| `probe_leak.gd` | clean (`PROBE after gh free players=0`, no leaks) |
| `make audit` | **AUDIT PASS** (12,660/12,703, unexpected 0) + `CONSUMER AUDIT PASS` |
| `make texture-cap-check` | **OK** (797 capped, 1 alpha-critical, 0 offenders) |
| `build/qa/test_perf_guard.sh` | **PERF_GUARD_TEST PASS checks=78 fails=0** |
| `make gate-ratchet` | **GATE_RATCHET: PASS** |

Runtime census with the authored collision on: `PERF_CENSUS ... instances=63547
collision_bodies=243 collision_shapes=30901`, `PASS: Perf chunking`.
No floor was lowered: compile 152 → 157, run_tests 301 → 303, E2E 278 → 278,
audit 12,660 → 12,660. The ratchet file itself is P0's; P1 did not raise it.

## Independent audits

| lane | report | verdict |
|---|---|---|
| A1 collision | `audit-a1.md` | **ACCEPT with 3 findings**: every numeric claim reproduced against the GLBs (unit trap, capsule Z/`L+2R`, convex bake, A/B, budget, traversal in both modes, no test weakened). **F1** the new probe's coverage assertion was degenerate (double-count + tautology) and **F2** authored mode emitted 95,293 Jolt "unsupported non-uniform scale" errors (77 MB/load) and lost the authored non-uniform scale — **both fixed in `6b5b875`** (real census denominator + `>= 0.95`, and the instance scale baked into the shape: 0 errors, 7,290 B log, shapes unchanged); **F3** three commit-message overstatements (the spline path keeps its own 0.45 gate; the +2,878 instances split 2,706 gate / 184 token-list; the async cost-cap bug was introduced by the same commit) |
| A2 progression | `audit-a2.md` | **PASS** on all 8 items, no test weakened; corrections: the suite has **35** checks (the commit said 36), the ladder-outranks-quest-graph rule needed a port-decision label (added), and four doc nits (fixed) |
| A3 input/curves/sprites | `audit-a3.md` | **6/7 PASS**; item 5 FAIL on a *report* number ("12 of 29 referenced at all" — 12 is the placed count, 14 across all systems; corrected). It also found `5b112b1` does not compile alone (see integrator step 1) and that the two rain materials *resolve to* the mask without binding it (corrected) |
| A4 prep/interior | `audit-a4.md` | **FAIL on item 7**: suite 98 compared the applied exposure to the same constant it read, so a 13 % global cut to 1.00 would have passed. **Fixed**: the guard now compares against the measured literal 1.15 and fails if `NIGHT_EXPOSURE` drops below it. Every other item reproduced exactly (camera unchanged, 4/4 prep stats, P14 band, grade log, interior table, scorecard 120 rows) |

Each auditor re-ran the lane's proofs and was not the author. Their per-item
verdicts and any failure are in the named files; a FAIL is carried into the
integrator steps rather than fixed here.

## Blocked / deferred (with owner)

- **BLOCKED-ON P2**: interior exposure band (the two foyer fills, §0.2).
- **BLOCKED-ON P2**: scoring bonuses in the payout (`loot_inventory.gd:392`).
- **BLOCKED-ON player/input-feel**: `Curve_GamepadLookEdgeBoost` application,
  `Curve_GamepadMoveThumbstickResponse`.
- **BLOCKED-ON AI**: `Curve_AI_HeightDifferenceToStrengthMultiplier`,
  `C_WaitingAIToNavLinkAcceptanceRadius`, `C_EyeGlow`.
- **BLOCKED-ON weather/sky**: `Curve_Exposure_Compensation_Float(_V3)`,
  `C_Sky_Gradient`.
- **BLOCKED-ON player/gameplay**: `Curve_FallingDamage` (already consumed via
  `fall_damage.json`), `Curve_CarryTargetThrowStrengthVsDirection`,
  `Curve_Dodge`.
- **BLOCKED-ON UI**: `C_GlyphIndicator_MajorLoot`.
- **DEFERRED**: authored `initial_unlocked_content` / `post_ftue_unlocked_content`
  at runtime (no FTUE flow yet).
- **Producer gap** (integrator): `parse_collision.py` should rename
  `half_extent` → `extent` and fix its NOTES (2× trap), and emit a record (or
  `has_dump: false`) for every placed BodySetup so the 10 `/Game/Test/` paths are
  not resolved by a prefix rule.
- **Producer gap**: `parse_vfx.py` `TEX_PREFERENCE` cannot fix the sprite
  shortfall (the materials carry no alpha); the ceiling is 15/39 without a
  shader mode.

## Open risks

1. **Collision load time** +2.5-3.7 s (+13-18 %) is now the default; the FPS cost
   is **not verified** (`fps_pose=n/a`). The shape budget has 527 building shapes
   of headroom on non-FTUE maps, and the per-path encoding decision is cached for
   the process (a second map load reuses the first load's cost-cap choice).
   Non-uniformly scaled capsules/spheres are approximated by a mean radius.
2. **`test_roof_collision.gd`** fails 9 assertions in authored mode (not a gate);
   the probe measures one mesh-wide hull, not the authored per-element set.
3. **`QueryOnly`** colliders answer physics as well as queries (Godot has no
   per-shape flag); 152 HidingSpot bush instances are solid where UE had query-only.
4. **16 reduced meshes** lose per-element pitch (roof corner / bay window first).
5. **Sensitivity is user-visible** (Normal 1.125×, pad Fast 1.5625×); if that is
   unwanted, revert `input_actions.gd`'s curve sampling and restore the ini ladder.
6. **Sprite sprites still show the procedural fallback** for 34 of 39 placed
   materials; the additive sampler is the next lever (+7 materials / +5 systems).
7. **`prep` p50 19 vs KF11 28** — the sky is a large dark area; if the target
   becomes the p50 rather than the mean/black floor, the sky needs re-grading.
8. **The R8 gate logs are unchanged**; the new counts (157/303/30,901) are in
   this report and the audit logs, not in `docs/reports/logs/`. P0/integrator
   should re-stamp the ratchet at the merged HEAD.

## Integrator steps

1. Cherry-pick `c2a1cd8..rem/w9-p1` in order. Do not squash: the red proofs and
   the measured tables are in the messages. **`5b112b1` does not compile on its
   own** (its `game_data.gd` preloads `progression.gd`, which lands in the next
   commit `bb37003`) — apply the pair together; every commit from `bb37003`
   onward is self-consistent and the tip is green.
2. **`extracted/`, `game/assets/` and `game/data/generated/` are read-only
   symlinks** — do not commit them, do not regenerate data for this wave.
3. This report is force-added (`git add -f build/qa/w9/p1-report.md`): `build/qa/*.md`
   is gitignored. The PNGs are not committed; they stay in
   `build/qa/w9/captures/` with the logs in `build/qa/w9/logs/`.
4. **Re-run the complete gate set serially** at the merged HEAD. The numbers in
   §"Golden gate set" are the floors for this wave; `run_tests` grew 301 → 339 `^PASS`
   (suites 98/99 + child-engine output) and compile 152 → 157, so a silent drop is a regression.
5. **`make gate-ratchet` passes on the R8 logs**; raising it to 157/339/30,905 is
   P0's job and needs the re-stamped logs. Do not lower a floor.
6. Expect **~30 s of extra level load** in every perf run (authored collision) and
   re-measure the 60 FPS gate on a cool host before quoting any FPS.
7. The two stale consumer-allowlist rules (`project_settings.json`,
   `mesh_collision.json`) are removed in this branch; `make audit` passes with 22
   rules and both files counted as runtime-read.
8. **Repo docs owed at integration (not P1-owned):** `docs/FIDELITY_GAPS.md`
   needs the four one-line entries (authored collision + its load cost and the
   `test_roof_collision` owner action; authored progression with the ladder
   override; the input/curves consumers with the sensitivity change; prep
   composition/grade and the interior BLOCKED-ON P2), and
   `docs/HANDOFF_NEXT_AGENT.md` needs the new HEAD, the gate numbers and the
   blocked list from §"Blocked / deferred". Those files are outside P1's file
   ownership (P0 owns the reports), so this branch does not touch them.
