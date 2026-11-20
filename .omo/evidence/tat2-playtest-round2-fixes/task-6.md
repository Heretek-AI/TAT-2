# Task 6 evidence — stairs climb + ground meshes seated

Date (UTC): 2026-11-20. Worktree: `/home/john/Projects/TAT-2` (Wave 1 in progress, uncommitted).
Method: file-level verification + targeted static probes only. No `make test`, no live-GPU run
(orchestrator runs the full suite at settle). Probe scripts are throwaway in `/tmp`
(`task6_probes.py`, `decode_heights.py`, `seat_probe.py`); product writes are the two
spans below plus this file.

## 1. Collider rule (level_loader.gd, `_get_mesh_and_shape` bucket)

Walkable surfaces take trimesh instead of a full-AABB box; everything else keeps the
old fast path (box for 0.45–12 m props, trimesh for >12 m, no shape for tiny/non-blocking).

- Stair runs: `"stair" in path` minus furniture (`rail`, `boundary`, `post`, `banister`,
  `balustrade`, `upstairs`). Trimesh presents tread faces; the old box was a flat-topped
  wall (GLB AABB: `SM_StairsCity4x2m` 4 m run x 2 m rise = 2 m wall;
  `SM_Stairs_Industrial_3x50cm` 3.35 m run x 0.69 m = 0.69 m wall at the low end).
- Sidewalk walk surfaces: `"sidewalk" in path`. Trimesh collides at the authored walk band
  instead of floating a flat box top at trim height (`SM_SidewalkCityStone_6m`: walk band
  ~0, box top +0.199; `SM_SidewalkCityStones_E`: box top +0.153).
- Cheek walls, rails, posts, banisters, upstairs masses keep boxes; rugs/cables/foliage
  keep no collision; tiny props (<0.45 m) keep the old path. No collision-semantics change
  beyond restoring authored walkability.
- Draw-item emission (`_build_one_draw_item`) needed no change: the shape flows through the
  existing `_add_collider` path (Den split and Den grounding gates are `is BoxShape3D`,
  so trimesh bypasses them to the plain collider).

Probe 1 — rule audit over every mesh name in `game/data/generated/levels/*/*.tatlevel.json`:

- stair corpus 32: 20 walkable runs take trimesh, 12 furniture pieces keep boxes;
  every excluded mesh is named furniture; no walkable run matches an exclusion.
- sidewalk corpus 12/12 genuine (audited: `street` and `road` rejected — they match lamp
  fixtures and `SM_PlanterBroadA`; `courtyard` rejected — it matches arches/pillars).
- rule text present verbatim in `level_loader.gd`.

## 2. Step-up rule (thief_character.gd, locomotion)

Bounded assist within the 0.3 m snap philosophy, after `move_and_slide()`:

- Constants: `STEP_UP_MAX_M = 0.3`, `STEP_UP_FORWARD_M = 0.35`, `STEP_UP_SKIN_M = 0.02`;
  `FLOOR_SNAP_LENGTH` unchanged at 0.3, `floor_block_on_wall` stays `true`.
- Gate: `not climbing_now and not is_mantling and is_on_floor() and is_on_wall()`, plus
  planar wish > 0.05 (no idle self-stepping; no fight with wire/ladder climb or mantle).
- Sequence: headroom `test_move(UP * (MAX + SKIN))` must be free, lifted pose must advance
  `FORWARD` freely, and `test_move(DOWN * (MAX + SNAP))` must catch a floor; only then
  commit `global_position`. One assist per physics frame; snap/gravity settle the rest.

Probe 2 — bound check against the constants parsed from the edited file:

- 0.18 m riser climbs, 0.20 m riser climbs, 0.30 m bound climbs,
  0.31 m above bound blocks, 0.60 m wall blocks (lift 0.3 < 0.6, forward probe collides).
- `floor_block_on_wall = true` present; gate and lift-forward-down sequence present verbatim.
- Probe 1 + Probe 2: 18/18 PASS (`python3 /tmp/task6_probes.py`, exit 0).

## 3. Ground-height verification against UE heightmap decode

Replicated `_build_one_landscape` decode (`((h16 - 32768) / 128) * step_y`, tile origin +
relief) over all 18 Guildhall tiles with an independent PNG reader:

- 27 m group surfaces 25.26–28.11; 10.7 m group 4.26–19.41 (plus deep ravine tiles to −60.85).
- Authored static ground meshes agree within centimeters: `SM_SidewalkCityStones_E`
  world-bottom 26.91 vs terrain 27.00 (gap −0.09); `SM_SidewalkCityA_6m` 18.52 vs 18.55
  (gap −0.03). The heightfield math is correct; the seating fix belongs to the colliders
  (§1), not the transforms. The 092850 slab reads as a correctly-placed tile whose
  neighbors are missing upstream (Wave 1 T1 territory), not a transform error.

## 4. Changed ranges and overlap check

- `game/src/core/level_loader.gd`: `_get_mesh_and_shape` bucket hunk
  (`@@ -793,11 +811,21 @@`, rule comment + `is_stair_run`/`is_walk_surface` + box condition).
- `game/src/player/thief_character.gd`: constants hunk (`@@ -35,6 +35,9 @@`, STEP_UP_* trio)
  and locomotion hunk (`@@ -917,6 +920,24 @@`, assist block after `move_and_slide()`).
- `_build_body` capsule/snap setup re-read: `floor_block_on_wall = true` kept, no edit needed.
- No vista-span overlap: neighboring hunks (`_is_den_window_wall`, `_add_den_window_split`,
  `den_window_gap_spec`, vista emission) are Wave 1 T2's and untouched by this task;
  `mission_controller.gd` untouched.
- Indentation verified byte-level (`cat -A`): wish gate nests the full test sequence
  (an under-indented first pass was caught on re-read and fixed before probing).

## 5. Assumptions and follow-ups

- Riser heights 0.18–0.20 m come from the existing `FLOOR_SNAP_LENGTH` comment, not a fresh
  cooked-data pull; tread depths (~0.25–0.35 m) are estimated from GLB AABBs.
- `test_move` is swept (`body_test_motion`) and headless-safe; live climb proof (092837
  stair run) and `make test` are left to the orchestrator settle run.
- Note: the standing read-only agreement for `/home/john/Projects/TAT-2` was overridden
  here because this task explicitly scopes and authorizes these spans.
