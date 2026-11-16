# Old Manor marker-fallback spawn

Stage: spawn fallback (Old Manor). Date: 2026-11-16.

## Problem (verified in-engine, headless diagnostic)

- The task brief claimed all 21 `OldManor/*.tatlevel.json` files yield
  `player_spawns = 0`. That is stale: `OldManor_Gameplay.tatlevel.json`
  contains 6 `TATPlayerStart_*` markers and the loader does match them
  (`"PlayerStart" in "TATPlayerStart"` is true; diagnostic showed
  `player_spawns=6 transforms=6` for Contract 3).
- The real defect is worse: all 6 authored starts float **outside the
  playable space** (e.g. `(5.95, 8.53, 126.03)`), with no floor within the
  authored ±6 m raycast. The old code then used `ue_spawns[0]` blindly and
  `_snap_player_to_ground()` teleported the player onto the **safety net**
  at `y ≈ -14.4` (`above_safety=false`, not on any real floor).
- Old Manor does have real mission markers in the loaded set (Contract 3):
  `minor_loot_spawns=293`, `loot_spawns=293`, `guard_spawns=992`,
  `escape_points=10`, `major_loot_spawns=0` (the 78 MajorLoot-class actors
  are chest/display-case meshes, not `MissionSpawner_MajorLoot`).

## Fix (`game/src/missions/mission_controller.gd` only)

- Authored-spawn path (Guildhall/Thieves' Den) and yaw math untouched:
  transform loop, `_spawn_yaw_from_basis`, and position+1.0 placement are
  byte-identical in behavior. The only change there: an authored entry now
  only wins when its floor raycast **hits** (previously a missed raycast
  still fell back to the blind `ue_spawns[0]`).
- New `fallback_spawn_source` member (`"authored"` default), printed as
  `TAT-2 player spawn: source=... pos=... yaw=...` for QA.
- New `_marker_fallback_spawn(stats, w3d)`: candidates in priority order
  `(a)` first `major_loot_spawns` pos, else `loot_spawns[0]` → `major_loot`;
  `(b)` centroid of `minor_loot_spawns` → `minor_centroid`; `(c)`
  `guard_spawns[0]` → `guard`; `(d)` `escape_points[0]` → `escape`.
  Each is raycast `candidate + (0,30,0)` → `candidate - (0,120,0)` on
  layer 1; first floor hit wins at `hit + (0,0.2,0)`. Returns `{}` when
  nothing hits (caller keeps the legacy mesh fallback → `mesh`).
- New `_loot_centroid(stats)`: mean of major + minor + loot_spawns
  positions. The fallback spawn faces it (yaw only,
  `atan2(-dx, -dz)`); legacy orientation when no centroid exists.

## Chosen source / position per map (`make test` output)

| Map (contract) | Source | Position | Yaw |
|---|---|---|---|
| Old Manor (3) | `major_loot` (`loot_spawns[0]`, no major dict entries) | `(17.53, 23.49, 58.39)` | 0.84 (toward loot centroid) |
| Thieves' Den (1) | `authored` (3 PlayerStarts, no loot/guard/escape markers) | `(5.67, 42.16, 270.69)` | 3.06 |
| Guildhall (4) | `authored` (21 PlayerStarts) | `(127.27, 26.47, -5.33)` | -3.05 |

Static census (base + contract sublevels): thieves_den PS=3/major_sp=0/
minor_sp=0; guildhall PS=21/major_sp=3/minor_sp=250; old_manor PS=6 (all
floorless)/major_sp=0/minor_sp=293. Only Old Manor takes the fallback.

## Temp verification output (deleted `game/tests/_tmp_om_spawn.gd` after use)

```
OM_SPAWN pos=(17.5346, 23.28737, 58.3921) source=major_loot
PASS: player above safety plane y=23.28737449646
PASS: player is_on_floor
PASS: spawn capsule clear of layer-1 geometry
PASS: fallback source inside mission space: major_loot
SUMMARY: fails=0
```

Asserts: `y > 0` and `is_on_floor()` after physics frames; spawn capsule
(r 0.32, h 1.7 at +0.9) does not overlap layer-1 geometry; source is
`major_loot` or `minor_centroid`. `run_tests.gd` was not touched.

## Full suite

- `make test` → `SUMMARY: fails=0`, `SCRIPT ERROR` count 0 (two runs:
  with temp file present, and final without). Exit-cleanup
  `ObjectDB/RID leaked at exit` warnings are pre-existing harness noise,
  unrelated to this change (no nodes added/removed).

## QuestGraph note

The real game spawns via QuestGraph logic, which is **not in the cooked
data**: `contracts.json` → `mission_durations` carries only
`quest_graph_ue_path` strings (e.g.
`/Game/Maps/OldManor/QuestGraphs/QG_OldManor.QG_OldManor`) plus match
durations. The cooked marker data offers only the (unusable, staging-area)
`TATPlayerStart` actors, hence the marker-fallback approach: spawn on a
floor-verified real mission marker inside the mission space.
