# Spawn Orientation — authored PlayerStart yaw now drives spawn facing

## Summary

`level_loader.gd` discarded the authored `PlayerStart` basis (positions only), and
`mission_controller._spawn_player` never set `player.rotation`, so every mission spawned
facing Godot `-Z` (yaw 0) regardless of the authored facing — e.g. the Guildhall spawn
stared into empty night. The loader now records `player_spawn_transforms`
(`{pos, basis, name, class}`) alongside the unchanged `player_spawns`, and the spawner
prefers the transform list: same first-with-floor selection rule, then yaw from the marker
basis (`forward = -basis.z`, `rotation.y = atan2(-forward.x, -forward.z)`), upright only.
`_snap_player_to_ground` still runs after rotation and only moves position.

## Files changed

- `game/src/core/level_loader.gd`
  - `_new_accumulator`: result gains `"player_spawn_transforms": []`.
  - `_parse_sublevel_file`: `PlayerStart` branch appends `{pos, basis, name, class}`
    (basis duplicated from the marker array); `player_spawns` append unchanged.
  - `_finalize`: exposes `player_spawn_transform_count`.
- `game/src/missions/mission_controller.gd`
  - `start_contract` passes `player_spawn_transforms` into `_spawn_player`.
  - New `_spawn_yaw_from_basis` (degenerate basis fails closed to 0).
  - `_spawn_player(ue_spawns, ue_spawn_transforms = [])`: when transforms are present,
    picks the first candidate whose `+1m → -6m` floor raycast hits (same rule as the
    legacy path), sets `position`, then `rotation = Vector3(0, yaw, 0)`. Falls back to
    the exact legacy position-only logic when transforms are absent (or no candidate
    has floor, or there is no physics world). Snap-to-ground unchanged and runs last.
- Temp check `game/tests/_tmp_spawn_rot.gd`: created, verified, **deleted** (no change
  to `game/tests/run_tests.gd`).

## Marker → chosen spawn → yaw (authored yaw = atan2 formulation above, degrees)

### guildhall (contract 4) — 21 markers, chosen = first with floor

| marker | pos | authored yaw | chosen? |
|---|---|---|---|
| TATSafeRoomPlayerStart_0 (TATPlayerStart, Gameplay) | (127.27, 25.47, -5.33) | -175.00° | **yes** |
| TATSafeRoomPlayerStart_1 | (106.87, 28.31, 64.29) | 90.00° | no |
| TATSafeRoomPlayerStart_10/11/2 | (-30.05..-31.95, 20.15, 87.55) | 90.00° | no |
| TATSafeRoomPlayerStart_12/13/3 | (53.76..55.86, 23.00, 83.46) | 90.00° | no |
| TATSafeRoomPlayerStart_14/15 | (105.87/107.97, 28.31, 64.29) | 90.00° | no |
| TATSafeRoomPlayerStart_16/17 | (127.27, 25.47, -4.33/-6.43) | -175.00° | no |
| TATSafeRoomPlayerStart_18/19 (Gameplay) + _0 (Guildhall_P) | (-15.11, 26.12, 81.77..83.57) | 5.00° | no |
| TATSafeRoomPlayerStart_4/6/7 | (-100.34, 18.93, 11.78..13.98) | 0.00° | no |
| TATSafeRoomPlayerStart_5/8/9 | (-79.88, 19.92, 33.31..35.51) | 10.00° | no |

Observed: `player_pos=(127.2747, 23.186, -5.3296)`, `rot_y=-175.00°`,
authored/player forward dot = **1.0**, floor gap 0.028 m, no layer-1 overlap at torso.
Previously `rot_y` was 0° (facing `-Z` while authored forward is `+Z`-ish) — the
"looks into empty night" bug.

### thieves_den (contract 1) — 3 markers, chosen = first with floor

| marker | pos | authored yaw | chosen? |
|---|---|---|---|
| TATPlayerStart_0 | (5.67, 41.16, 270.69) | 175.06° | **yes** |
| TATPlayerStart_1 | (5.18, 41.16, 271.74) | 163.29° | no |
| TATPlayerStart_2 | (5.55, 41.16, 273.01) | 159.18° | no |

Observed: `rot_y=+175.06°`, forward dot = **1.0**, floor gap 0.14–0.15 m,
no layer-1 overlap at torso.

### old_manor (contract 3) — 6 markers, selection remains first-with-floor (legacy identical)

| marker | pos | authored yaw |
|---|---|---|
| TATPlayerStart_0 | (5.95, 8.53, 126.03) | 90.00° |
| TATPlayerStart_1 | (6.82, 8.53, 125.81) | 90.00° |
| TATPlayerStart_2 | (34.92, 9.95, 123.47) | 130.00° |
| TATPlayerStart_4 | (-74.29, 9.19, 120.48) | 70.00° |
| TATPlayerStart_5 | (-73.34, 9.21, 120.54) | 60.00° |
| TATPlayerStart_7 | (35.59, 10.04, 122.92) | 135.00° |

Observed (post-fix): no candidate's floor ray hits, so the transform path declines and
the run falls through to the legacy position-only path — spawn `(5.95, -14.47, 126.03)`,
`rot_y=0°`. A control run with this change stashed produced the **identical** spawn, so
this is a pre-existing map condition (no level collision under the Old Manor starts;
the player lands on the `-15 m` safety plane), not a regression. Out of scope here.

### jaspering_hall (contract 17) — 0 markers in loaded sublevels

The mission's base sublevel list (`FTUE_Geometry`, `FTUE_Building_JewelryStore`,
`FTUE_Building_SpawnArea`, `FTUE_Gameplay`) contains no `PlayerStart` marker — the only
one (`TATSafeRoomPlayerStart_0` in `FTUE_Checkpoints`, yaw ≈ −155°) is never loaded, and
expansion contracts 17/18 add no contract sublevels. Spawn falls back to the
mesh-fallback position with `rot_y=0°`, unchanged by this fix. Wiring
`FTUE_Checkpoints` into the load list is a separate, pre-existing gap (out of scope).

## Multi-start note

Guildhall (21), Thieves' Den (3) and Old Manor (6) all have multiple starts; selection
is unchanged — first candidate whose floor raycast hits, in sublevel parse order
(Guildhall: `Guildhall_Gameplay` before `Guildhall_P`, so the Gameplay safe-room start
wins over the `Guildhall_P` 5°-yaw start). Only the facing is new.

## Temp verification output (deleted after the run)

```
SPAWN_ROT[guildhall order=4] player_spawns=21 transforms=21 player_pos=(127.2747, 23.186, -5.3296) rot_y_deg=-174.999732800617
SPAWN_ROT[guildhall order=4] chosen=TATSafeRoomPlayerStart_0 class=TATPlayerStart pos=(127.2747, 25.4694, -5.3296) ... dist_xz=0.0
SPAWN_ROT[guildhall order=4] authored_fwd=(0.08716, 0.0, 0.996194) player_fwd=(0.08716, 0.0, 0.996194) dot=1.0
SPAWN_ROT[guildhall order=4] PASS: faces authored forward (dot=1.0)
SPAWN_ROT[guildhall order=4] PASS: nonzero yaw (rot_y_deg=-174.999732800617)
SPAWN_ROT[guildhall order=4] floor_gap=0.02750015258789
SPAWN_ROT[guildhall order=4] PASS: on floor (gap=0.02750015258789)
SPAWN_ROT[guildhall order=4] PASS: no layer-1 overlap
SPAWN_ROT[thieves_den order=1] player_spawns=3 transforms=3 player_pos=(5.6692, 40.25239, 270.6863) rot_y_deg=175.055549106514
SPAWN_ROT[thieves_den order=1] chosen=TATPlayerStart_0 class=TATPlayerStart pos=(5.6692, 41.1592, 270.6863) ... dist_xz=0.0
SPAWN_ROT[thieves_den order=1] authored_fwd=(-0.08619, 0.0, 0.996279) player_fwd=(-0.08619, 0.0, 0.996279) dot=1.0
SPAWN_ROT[thieves_den order=1] PASS: faces authored forward (dot=1.0)
SPAWN_ROT[thieves_den order=1] floor_gap=0.14727783203125
SPAWN_ROT[thieves_den order=1] PASS: on floor (gap=0.14727783203125)
SPAWN_ROT[thieves_den order=1] PASS: no layer-1 overlap
SPAWN_ROT: ALL PASS
```

Checks per map: transform entry within 2 m XZ of the player; `dot(player_fwd,
authored_fwd) > 0.99`; Guildhall `abs(rot.y) > 0.001`; floor ray hits within
`[-0.05, 1.0] m`; torso-height (capsule centre) 0.3 m sphere reports no layer-1
overlap (feet-level spheres graze the correctly-stood-on floor, so the check uses
capsule-centre height). Zero `SCRIPT ERROR` lines in the temp run.

## Full suite

`make test` → `SUMMARY: fails=0`, zero `SCRIPT ERROR` (see command log below).
`game/tests/run_tests.gd` untouched.
