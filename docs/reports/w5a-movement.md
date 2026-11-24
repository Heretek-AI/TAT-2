# W5A — authored stair traversal, 60° floor and the Den wardrobe prompt

Worktree: `/tmp/opencode/tat2-w5a-move` (base `950f7ca`). Scope: one file of
game code (`game/src/player/thief_character.gd`), one new headless test, and
suite 45's stale constants. No loader, mission or shared-doc edits.

## What the geometry audit found

Every stair run in the shipped levels is a trimesh flight. The civic flight
(`SM_Stairs_Civic_3x150cm`) measures **0.25 m risers on ~0.33 m treads (37.1°)**;
the industrial (`SM_Stairs_Industrial_3x150cm`) and city
(`SM_StairsCity6x2m`) runs use the same riser. The port could not walk them:

- the step assist probed 0.35 m forward **from the capsule axis**, so on a
  0.33 m tread the probe landed on the next riser instead of a tread;
- it was also gated on `is_on_wall()` from the previous `move_and_slide`;
- auto-mantle ran on the same frame (0.3 s lock), so a 25 cm riser played a
  mantle animation and cancelled the step.

Authored UE values the port had drifted from: `WalkableFloorAngle` 60°,
`MaxStepHeight` 45 cm, capsule half-height 91 cm.

Measured with a downward-ray height map on the real collider (before the fix,
`level_loader._get_mesh_and_shape`):

```
civic   z=-0.28 y=0.330 | z=-0.56 0.589 | z=-0.87 0.847 | z=-1.23 1.101
        z=-1.55 1.316 | z=-1.91 1.562     (5 risers 0.25, treads 0.28-0.33)
industrial  z=-0.27 0.310 | z=-0.55 0.564 | z=-0.87 0.814 | z=-1.15 1.064
        z=-1.43 1.318 | z=-1.87 1.580      (same 0.25 riser)
city        z=-0.36 0.270 | z=-0.82 0.541 | z=-1.22 0.778 | z=-1.69 1.042
        z=-2.09 1.284 | z=-2.55 1.505 | z=-2.95 1.777 | z=-3.48 1.993
```

## Fixes (all in `game/src/player/thief_character.gd`)

1. **UE-shaped step-up before `move_and_slide`.** `_try_step_up(planar_velocity)`:
   frame-local blocked test (`test_move` + collision normal) → headroom test →
   probe `pos + dir*(radius + 0.20) + UP*0.45`, down-ray 0.55 m → accept a rise
   in `(0.02, 0.45]` → `global_position.y = floor_y`, `velocity.y = 0`, and the
   camera offset. No `is_on_wall()` dependency.
   - The probe is measured from the **capsule surface** (`radius + 0.20`):
     UCharacterMovementComponent sweeps the shape, so its 0.20 m of remaining
     travel starts at the surface. From the 0.32 m axis the ray lands on the
     tread the body already stands on — the audit bug.
   - A blocked horizontal sweep whose normal is **walkable** is a slope, not a
     riser: `KinematicCollision3D.get_normal().y >= cos(60°)` skips it, and the
     landed floor's normal must also be walkable. Without this a 35° ramp
     reports a blocked sweep every frame and the lift becomes an elevator.
   - The old post-slide `is_on_wall()` assist block is deleted.
2. **Authored constants.** `STEP_UP_MAX_M 0.45` (MaxStepHeight),
   `STEP_UP_FORWARD_M 0.20`, `FLOOR_MAX_ANGLE_DEG 60.0`
   (WalkableFloorAngle), `CAPSULE_HALF_HEIGHT_M 0.91` / `CAPSULE_RADIUS_M 0.32`
   → built capsule 1.82 m, centre 0.91 (crouch toggle rebuilds to the same
   values). Provenance comments on each. Origin stays at the feet, so the
   authored eye height (1.66875 m) and the device body-height contract
   (`BODY_HEIGHT_STANDING` 1.78 m, `device_geometry.gd`) are unchanged.
3. **Mantle gate.** A committed step-up suppresses `try_auto_mantle()` on that
   frame; `try_auto_mantle()` refuses a ledge in `(0.45, 0.50]` without a jump
   press; the wall must be within a quarter metre of the capsule surface
   (the 0.85 m probe was reaching the third riser while the body stood on the
   first); the ledge probe is half a radius past the wall face instead of
   0.45 m (which overshot a 0.33 m tread onto a 0.5–0.75 m "ledge"). Head
   clearance now uses the 1.82 m capsule.
4. **Camera rise smoothing.** Committed rises accumulate into
   `_step_camera_offset` (capped 0.20 m) and ease out at 9/s through the head
   height, so the body snaps and the eye follows. The base crouch/stand lerp is
   tracked separately (`_head_base_y`): feeding the offset back through the
   same lerped value compounded it into a view sink, and `SpringArm3D` rewrites
   the child camera's position, so the camera cannot carry it.
5. **Wardrobe LOS.** `INTERACT_LOS_STANDOFF_M 0.6` (the Den point sits 0.48 m
   behind the cabinet front face) and the `minf(standoff, distance * 0.5)` cap
   is gone — the cap, not the 0.25 constant alone, put the endpoint back inside
   the cabinet for a close player. Endpoint is now
   `minf(0.6, distance - 0.05)`. `INTERACT_RANGE` stays 1.75 m.

## New test: `game/tests/test_stair_walk.gd`

Builds the **real** colliders with `level_loader._get_mesh_and_shape()` (same
`ConcavePolygonShape3D` the loader drops into the level), adds an approach slab
and a top landing at the ray-measured top tread (the mesh AABB max-y is a
handrail on the industrial run: 1.675 vs a 1.58 tread), then drives the real
`_physics_process` with `Input.action_press("move_forward")` for 180 physics
frames. Also: the wardrobe prompt fixture (0.6 m deep cabinet whose interact
point is 0.48 m inside, player capsule 0.32 m in front, plus a wall negative
control), the unchanged `INTERACT_RANGE` check, and a 35° ramp regression that
the step-up must not fire on.

```
PASS: civic stair walk: ascent=1.54 m (authored flight 1.56 m over 1.99 m run), target in 53 frames, max zero-progress streak=0, step frames=7, lateral drift=0.000 m, camera lag=0.170 m, mantle=false
PASS: industrial stair walk: ascent=1.55 m (authored flight 1.57 m over 2.00 m run), target in 50 frames, max zero-progress streak=0, step frames=14, lateral drift=0.000 m, camera lag=0.170 m, mantle=false
PASS: city stair walk: ascent=1.97 m (authored flight 1.99 m over 3.59 m run), target in 50 frames, max zero-progress streak=0, step frames=15, lateral drift=0.001 m, camera lag=0.170 m, mantle=false
PASS: Den wardrobe prompt resolves through its own 0.48 m-deep cabinet (nearest=wardrobe, prompt='[F] CUSTOMIZE LOADOUT')
PASS: a wall 0.63 m in front of the wardrobe point still blocks the prompt
PASS: INTERACT_RANGE stays the authored 1.75 m (only the LOS standoff changed)
PASS: 35 deg ramp is walked, not stepped (ascent=1.56 m over 60 frames, max frame rise=0.035 m)
W5A_SUMMARY: fails=0
```

Assertions: ascent ≥ 1.4 m, no >2 consecutive zero-progress frames during the
climb, `is_mantling` never true, lateral drift < 0.15 m, camera lag ≤ 0.25 m.

## Suite 45 (`game/tests/run_tests.gd`)

Only the stale expectations changed, with the measured evidence in the comments:

- max angle 50° → **60°** (const and live `floor_max_angle`);
- stair slope `atan2(0.18, 0.28)` → `atan2(0.25, 0.33)` = 37.1°;
- the >angle negative control 55° → **70°** (55° is now legitimately walkable);
- added `ss_step_ok` (0.45 / 0.20 / 0.91 / 0.05) and `ss_capsule_ok`
  (1.82 m, radius 0.32, centre 0.91) — checks, not relaxations.

```
PASS: 45 stairs (max_angle 60.0 deg, snap 0.3 m, capsule 1.82 m, step 0.45 m + 0.2 m probe, civic flight 37.1 deg walkable, 70 deg blocked, wall-block/constant-speed kept, no new mantle)
```

## Gates run (serial, one Godot at a time, `XDG_DATA_HOME=/tmp/opencode/w5a-data`)

| Gate | Result |
|---|---|
| `tools/check_scripts_compile.gd` | **97 checked, 0 broken** (96 + the new test) |
| `res://tests/test_stair_walk.gd` | **W5A_SUMMARY: fails=0** (7/7) |
| `res://tests/run_tests.gd` | **254 PASS, fails=2** — both pre-existing weather (below); suite 45 and 55c pass |
| `res://tests/test_m2_player.gd` | **M2_SUMMARY: fails=0** |
| E2E `--tier=2` | **fails=0 passed=110 total=110** (includes T2-10-C mantle limits) |
| E2E `--tier=1` | **fails=0 passed=115 total=115** (includes the mantle/blocking-volume seams) |

Not run, per the wave brief: full E2E (tiers 3–4), screenshots/Vulkan captures,
and the perf matrix.

### Two pre-existing failures and one pre-existing audit failure (not W5A)

1. `run_tests` suite 10: *"Guildhall must use its map weather preset … expected
   guildhall/midnight_clear 0.0006"*. The generated
   `game/data/generated/weather/map_weather.json` maps `guildhall → gloomy`
   (fog 0.16); the assertion (written 2026-11-17, `7e240bb`) still expects the
   older `midnight_clear` mapping. Proof without editing anything:
   `WeatherProfile.preset_for_map("guildhall")` returns `gloomy`. The same
   drift fails suite 17's `wmap_ok`. Both run **before** suite 45 and touch no
   movement code.
2. `make audit` → `AUDIT FAILED: 4 failure(s)`: producer baselines for
   `parse_tables.py`, `parse_gameplay.py`, `parse_weather.py` differ from the
   recorded baseline (regenerate + `--refresh-stamps`), and
   `vgmstream: 'missing'` version drift. Generated content is not touched by
   this wave; content checks themselves are all OK (levels 107, tables 144,
   materials 1629, devices 4118, audio 5018, …). The AGENTS gate table already
   notes the full set was deferred after the Spider wave.

## Risks / what remains

- **Feel**: MaxStepHeight moves 0.30 → 0.45 and the floor angle 50° → 60°.
  45°–60° slopes and 0.45 m ledges are now walkable instead of walls; that is
  the authored contract but it changes routes. Feel was **not** verified by
  play — only by the headless walk above.
- **Step-up cost**: a blocked horizontal sweep + up to two `test_move` calls and
  one ray per frame only while blocked; flat ground exits after the first
  `test_move`. Not profiled.
- **Capsule +4 cm**: 1.82 m tall capsule needs 4 cm more head clearance under
  low geometry; the crouch path still uses the authored 1.0 m. Mantle head
  clearance now demands the same 1.82 m.
- **Camera smoothing** is a head-height offset, not a post-process; it lags the
  eye up to 0.20 m for ~0.2 s on a committed riser. Measured lag 0.170 m.
- **`INTERACT_LOS_STANDOFF_M 0.6`** is global for all interactables: geometry
  within 0.6 m *in front of* an interaction point no longer blocks that prompt.
  Suite 55c's wall (0.5 m from the point) still blocks, and the new fixture's
  negative control (0.63 m) still blocks, so the band is tight but it is a
  wider hole than before.
- **Not addressed here**: e.g. character-vs-stair sliding on the tread nose
  (`floor_constant_speed` unchanged), automatic mantle's own clip/feel, and the
  wardrobe prompt's *dressing* (only the LOS defect was in scope).
