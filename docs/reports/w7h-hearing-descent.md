# W7H — surface-resolved hearing, swing-door creak, indoor weather scope, stair descent and roof routes

Lane: `tat2-w7h-hearing` (worktree off `74a43b8`). Owner files:
`game/src/stealth/surface_resolver.gd` (new), `game/src/player/thief_character.gd`
(surface resolver + descent only), `game/src/interact/swinging_door.gd`,
`game/src/core/weather_profile.gd` (indoor scope only),
`game/src/ai/hearing_data.gd` + `game/src/ai/guard_ai.gd` (SEARCH timer,
Picked/Jammed split, listener weather scope), `game/tests/` (new
`test_w7h_surface_hearing.gd`, `test_traversal_routes.gd` additions,
`e2e_tier1_features.gd` T1-23).

No loader, UI, save, S2/S5 or visual code was touched. **No producer, no
`make normalize`, no audit baseline change, no generated data write**: the
resolver reads the authored `surface_loudness` table (`guard_ai.json`, 22 rows)
and the loader's existing node/shape metadata.

---

## 1. Surface resolver (what replaced the map rule)

Before W7H the footstep surface was a two-line map rule: contract 1 → `wood`,
everything else → `stone`. 20 of the 22 authored `DA_LoudnessModifiers` rows
were unreachable, so carpet/grass/dirt/foliage never silenced a footstep and
glass/metal never amplified one.

`SurfaceResolver` answers with one downward ray and one decision:

1. explicit author/test override on the collider or on the `CollisionShape3D`
   that owns the hit shape — meta `surface_type` (the E2E helper's existing
   contract), `ue_surface`, `surface`, `surface_name`;
2. that `CollisionShape3D`'s `ue_mesh` meta, which `level_loader._add_collider`
   and `_get_mesh_and_shape` already stamp with the authored UE mesh path
   (resolved through `shape_find_owner` → `shape_owner_get_owner`, so the
   batched `LevelCollision_*` bodies resolve **per shape**);
3. the collider node itself: `ue_mesh`, `merged_ue_meshes`,
   `override_materials`, and the surface materials of a `MeshInstance3D`
   visual it carries;
4. the documented fallback: **stone** (authored 1.5). Never a crash, never a
   silent 1.0.

Name matching runs on the **file name first** and only then the full path. That
matters: UE paths carry folder words that are not surface evidence
(`/Game/Art/Environment/...` contains `iron`, which made every environment mesh
read as `MetalThick` in the first pass). The greedy tokens `iron`, `steel`,
`brass`, `car` and `pane` were removed for the same reason.

The 22 authored names are all reachable by name, and each maps onto one of the
seven AudioManager pool tokens (`wood` ← WoodFloor/WoodBeam/WoodObject,
`stone` ← Stone/Tile/Lattice, `metal` ← the five metal rows + ElectricalWire,
`wet` ← Puddle/GroundWet, `earth` ← Dirt/Grass/Foliage/Ivy, `glass` ← Glass/
GlassHorizontal/BrokenGlass, `carpet` ← Carpet). Both the loudness multiplier
(`NoiseBus` → `GameData.get_surface_loudness`) and the audio pool
(`AudioManager.play_footstep`) therefore come from the same ray and cannot
disagree.

## 2. Hearing matrix (measured)

`game/tests/test_w7h_surface_hearing.gd` — **108 checks, 198 matrix cases**.

* 22 authored surfaces × {crouch (1.5 m), walk (3.5 m), run (8.0 m)} × weather
  {clear 1.0 (guildhall), dense fog 0.9 (old_manor), heavy rain 0.8 (jaspering)}
  = **198 cases**. Each asserts
  `radius = min(stim_max × surface, 25 m × weather)` exactly, heard at
  `radius - 0.02` and silent at `radius + 0.01`.
* Silent faces (radius 0, not heard at 0.5 m): `Carpet`, `Foliage`, `Ivy`,
  `Grass`, `Dirt`.
* Hard faces (×1.5, 15 rows): Stone, Glass, GlassHorizontal, BrokenGlass,
  MetalThick, MetalPipe, MetalSheet, MetalGrate, MetalVehicle, WoodFloor,
  WoodBeam, WoodObject, Puddle, GroundWet, ElectricalWire.
* Medium faces (×1.0): `Lattice`, `Tile`.
* Sample radii at clear weather: walk on stone 6.00 m, run on stone 25.00 m
  (clipped by the authored 25 m HearingRange), walk on tile 4.00 m, run on tile
  20.00 m, run on carpet 0 m.
* Weather scaling: run on stone 25.00 / 22.50 / 20.00 m at 1.0 / 0.9 / 0.8.
* Unknown/empty surface: the empty-surface sprint keeps the authored 20 m
  radius (×1.0, **not** 0).

Boundaries and distance:

* `dist == radius` is heard (tile walk at exactly 4.00 m); `radius + 0.01` is
  silent.
* The 25 m authored sense ceiling clips a 30 m stone sprint (radius 25.00 m) and
  25.01 m is silent.
* 3D distance, no invented floor occlusion: a sprint 15 m below a guard through
  a roof collider is heard (3D 15.8 m ≤ 20 m radius); the same sprint at
  21.2 m 3D / 15 m planar is silent, so the distance is the 3D one, not a planar
  sum and not a head-height band.

Negative controls: an astral source is not heard (and the same source is heard
once astral is off), a knocked-out guard is not heard.

SEARCH timer: a footstep 2 m away promotes NEUTRAL → SUSPICIOUS → SEARCH with the
authored 4 s window; after burning the timer down to 1.5 s a repeated noise
refreshes it to **4.00 s** (before W7H it kept decaying and the search expired
mid-investigation). A repeated long-behaviour stim (`Combat.Block`) refreshes to
**8.00 s**. Detection stays 0 in both cases.

Lockpick split: `lockpick` → `LockPicking.Picked` heard at 2.9 m and silent at
3.2 m; `lockpick_jammed` → `LockPicking.Jammed` heard at 9.9 m and silent at
10.2 m.

Swing door: **one** authored `OpeningCreak` (5 m, `stim.max_range_m` 5.0) per
toggle — open = 1 record, close = 2 total. The lock path does not double-fire:
a successful pick on a closed door emits exactly **1** (the swing), and
hold-to-lock emits **0** `door`-tag records (its `lock` stimulus is separate).

Indoor weather scope: ceiling probe says indoors under a roof and outdoors in the
open; `sound_carry_multiplier_at()` gives Old Manor interior **1.0** / exterior
**0.9**, Jaspering interior **1.0** / exterior **0.8**, and the Den **1.0**
everywhere. A real guard consumes it: indoor multiplier 1.00, after walking out
0.90.

## 3. Descent (D1 + D5 shipped, D2 measured)

`thief_character.gd`:

* **D1**: the step-down ray casts `STEP_DOWN_CAST_M = 0.40 m` and accepts a floor
  at most `STEP_DOWN_ACCEPT_M = 0.30 m` below the origin. Reach is not
  permission, so a 0.45 m ledge still produces one real airborne interval.
* **D5**: an air→floor transition with a drop ≤ `LANDING_COALESCE_M = 0.30 m` no
  longer plays `jump_land` or the airborne viewmodel state, and does not run the
  fall-damage path. `landing_events` / `last_landing_drop_m` count only real
  landings, so a hop and a walked riser are distinguishable.
* **D2** (default off, `STEP_DOWN_QUERY_SHRINK_M = 0.0`): optionally shrink the
  destination query capsule by `STEP_DOWN_QUERY_SHRINK_EXPERIMENT_M = 0.06 m`,
  gated to the first 0.06 s of a drop and to `STEP_UP_GUARD_SEC = 0.25 s` after a
  step-up so a descent can never undo a climb.

`game/tests/test_traversal_routes.gd` fixture T1–T6 (risers 0.06, 0.12, 0.18,
0.24, 0.28, 0.30 m) on the shipped path, plus T7 (0.45 m control):

| fixture | riser | descended | intervals | air frames (shipped) | air frames (D2 opt-in) | landing events |
|---|---|---|---|---|---|---|
| T1 | 0.06 | 0.06 | 0 | 0 | 0 | 0 |
| T2 | 0.12 | 0.12 | 0 | 0 | 0 | 0 |
| T3 | 0.18 | 0.18 | 1 | 4 | 1 | 0 |
| T4 | 0.24 | 0.24 | 1 | 9 | 2 | 0 |
| T5 | 0.28 | 0.28 | 1 | 11 | 2 | 0 |
| T6 | 0.30 | 0.30 | 1 | 12 | 2 | 0 |
| T7 | 0.45 | 0.45 | 1 | 16 | 16 | **1** (drop 0.33 m) |

Every T1–T6 case ends grounded with **0 landing events**; T7 is the one real
fall. The 0.45 m control is unchanged by D2, so the accept band is still a band.

D2 A/B (offline probe over 0.06–0.45 m risers, shrink 0.0/0.06/0.12/0.20/0.28,
plus the in-test A/B):

* destination-capsule shove-back: **0.000 m** at shrink 0.0, **0.001 m** at
  0.06 (limit 0.05 m);
* authored stair ascent (3 × 0.25 m risers on 0.33 m treads, and the real civic
  flight through `test_stair_walk`): **0.75 m / 7 routes fails=0** with the
  `STEP_UP_GUARD_SEC` guard — 0.32 m stall without it, which is why the guard
  exists;
* the opt-in reaches the ≤2 air-frame target where the shipped path measures
  4–12.

**Decision (owner): D2 stays default-off.** D1 + D5 deliver the shipped
contract; the experiment and both numbers stay in the tree behind one named
constant, and `test_traversal_routes` asserts the default-off state plus an
explicit opt-in run.

## 4. Roof routes (W6L deferred these; now asserted)

Against the real shipped modules (`test_traversal_routes.gd`):

| route | measured |
|---|---|
| `SM_RoofUrban_Ext_Mid_4x4` (45.2° hip) | walked up **3.37 m** in 120 frames, step-up 0.000 m, no mantle |
| `SM_RoofUrbanB_Ext_Mid_6x8` (67.6°) | refused: ascent −24.86 m (it slides off the shell), no mantle |
| EndA/EndB gable caps (3 meshes) | eave band **3.40 m / 3.38 m** below the AABB top the old box floated; a dropped body falls to 1.04–1.07 m |
| hip faces | four quarter-footprint samples sit **2.70 m** below the 4.13 m ridge (no plateau) |
| non-uniform POI instance (`Mid_4x4`, scale [1,1,0.8]) | measured **51.1°** vs the expected `atan(tan 45.2°/0.8) = 51.5°`, still walkable (3.15 m ascent) |

No loader edit was needed; the tests consume `roof_collision_kind` /
`_get_mesh_and_shape` exactly as the loader ships them.

## 5. Gates (serial, one Godot at a time)

All on this worktree (`74a43b8` + the W7H tree), `XDG_DATA_HOME=/tmp/opencode/w7h-data`:

| gate | measured |
|---|---|
| `tools/check_scripts_compile.gd` | **112 checked, 0 broken** |
| `tests/run_tests.gd` | **`SUMMARY: fails=0`** |
| `tests/test_m2_player.gd` | **`M2_SUMMARY: fails=0`** (11) |
| `probe_leak.gd` (`TAT2_NO_DEN_PROBE=1`) | exit 0, **0 ERROR lines** |
| `tests/test_w7h_surface_hearing.gd` | **fails=0, 108 checks, 198 matrix cases** |
| `tests/test_traversal_routes.gd` | **fails=0** (T1–T7, D2 A/B + opt-in, 5 roof routes) |
| `tests/test_stair_walk.gd` | **fails=0** (7 shipped routes incl. rotated/non-uniform + descent) |
| `tests/test_hearing_ranges.gd` | **fails=0** |
| `tests/test_roof_collision.gd` | **fails=0** |
| E2E `run_e2e_tests.gd` | **fails=0, 266/266** (tier 1: 117 = 115 + T1-23-A/B) |
| `make gate-ratchet` | **PASS** (baseline intact, floors exceeded) |
| `build/qa/test_perf_guard.sh` | **PASS, 42/42 checks, fails=0** (base-count script; no GPU) |
| `make audit` | **FAILED: 6** — **not W7H** (see below) |

`make audit`, verbatim:

```
AUDIT FAILED: 6 failure(s)
FAIL: baseline: producer tools/parse_tables.py output gen:gameplay content differs from the baseline; regenerate it and run --refresh-stamps
FAIL: baseline: producer tools/parse_gameplay.py output gen:gameplay content differs from the baseline; regenerate it and run --refresh-stamps
FAIL: baseline: producer tools/parse_contracts.py output gen:gameplay/contracts.json content differs from the baseline; regenerate it and run --refresh-stamps
FAIL: baseline: producer tools/parse_loot.py output gen:gameplay/loot_actors.json content differs from the baseline; regenerate it and run --refresh-stamps
FAIL: baseline: producer tools/parse_containers.py output gen:gameplay/containers.json content differs from the baseline; regenerate it and run --refresh-stamps
FAIL: tool version drift: vgmstream: 'vgmstream CLI decoder r2168 (Oct 25 2026)' -> 'missing'; regenerate affected outputs and run --refresh-stamps
```

That is the W7S lane's uncommitted loot-producer output in the shared
`game/data` symlink (plus the vgmstream tool-version stamp). W7H wrote no
generated data, ran no producer, ran no `--refresh-stamps`, and did not touch
`tools/audit_baseline.json`; integration regenerates and re-stamps at the merged
HEAD. Every `content *` line above the failures was OK (containers 254,
contracts 16, tables 144, materials 1629, devices 4118, animations 995, audio
5018, niagara 3695).

### Environment note (E2E deltas seen and fixed in this lane, not code defects)

Two separate first-run deltas, both explained and closed:

* `T1-01-C` failed in the first tier-1 run because the worktree's copied
  `game/.godot` import cache had no `T_Moon_D.png` `.ctex`, so
  `_moon_panorama()` returned null and `moon_visible` was set to 0.0.
  `tools/godot --headless --path game --import` rebuilt the cache (derived,
  gitignored) and `game/project.godot` was left untouched; tier 1 then passed
  117/117.
* `T2-12-A` / `T3-04` failed only in the **full** run and passed in isolation.
  Cause: the new T1-23 feature spawned its guard/player/arena and never freed
  them, and every E2E arena shares the origin `(9500, 500, 9500)`, so a leaked
  second player and guard sat on top of the next tiers' arena. T1-23 now calls
  `h.free_node(arena)` like the other features, and the full run is
  **266/266**.

## 6. Needs a live playtest

* **25 m sprint indoors**: the matrix proves the authored radius arithmetic and
  the indoor 1.0 side, but only a playthrough shows whether a 25 m sprint through
  a Guildhall hall reads as fair (guards reacting through a floor above is by
  design: 3D distance, no floor occlusion).
* **Silent-surface feel**: carpet/grass/dirt now emit a *zero* radius footstep
  (authored 0.0). Confirm the silent surfaces are discoverable and that the
  audible feedback (footstep SFX pool) still plays, so silence is not mistaken
  for broken audio.
* **0.33 m civic descent camera**: T1–T6 are 0.06–0.30 m; the shipped civic
  flight uses 0.25 m risers on 0.33 m treads and still takes 4–12 airborne
  frames with D2 off. A played descent on that flight (third-person + first-person
  viewmodel) needs eyes on the camera to confirm no visible hitch and that
  `jump_land` no longer flashes.
* **Swing-door creak audibility**: one 5 m creak per swing is correct on paper;
  confirm in a corridor that a door opened by a guard or a peer does not feel
  silent (peer `apply_remote_toggle` deliberately does not re-emit).
* **Indoor/outdoor seam**: the ceiling probe treats any overhead geometry as
  "indoors" (15 m reach). Play the Old Manor courtyard arches and the Jaspering
  colonnade to confirm the 1.0/0.9 (0.8) switch is not audible as a step.
