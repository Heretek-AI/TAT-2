# W10 guard check — independent reproduction

Independent checker run. Worktree `/home/john/Projects/TAT-2-rem-w10-guards`
(main checkout untouched). Godot `4.7.2.stable.official.ed1daf0bf`, headless,
every run under `flock /tmp/opencode/tat2-godot.lock`. No GPU capture, no
gameplay/data edits, and `TAT2_GUARD_DIAG` was **not** set: the probe does not
read or depend on the existing diagnostic or its log.

Probe added: `game/tests/probe_guard_positions.gd` (extends `SceneTree`, house
style after `game/tests/probe_door_walk.gd`).

## Commands and gate

```bash
flock /tmp/opencode/tat2-godot.lock -c \
  'cd /home/john/Projects/TAT-2-rem-w10-guards && \
   tools/godot --headless --path game \
   --script /home/john/Projects/TAT-2-rem-w10-guards/tools/check_scripts_compile.gd'
# exit=0
# scripts checked: 190, broken: 0

flock /tmp/opencode/tat2-godot.lock -c \
  'cd /home/john/Projects/TAT-2-rem-w10-guards && timeout 120 \
   tools/godot --headless --path game \
   --script res://tests/probe_guard_positions.gd' \
  > build/qa/w10/guard-check.log 2>&1
# exit=0 (no timeout; boot took 123 process frames)
```

No `--fixed-fps` was needed. The log has no `SCRIPT ERROR`, `ERROR:` or
`GUARD_DIAG` line. The compile count is 190 because the new probe is one more
script than the 189 baseline.

Run history: the first attempt exited 124 before boot with
`Identifier not found: GameData` (the probe referenced `GameState` statically,
which compiles `game_state.gd` before the `GameData` autoload exists in a
`--script` run). The probe now reaches the autoload through
`/root/GameState` and sets `difficulty = 1`
(`# GameState.Difficulty.NOVICE = 1`, `game/src/core/game_state.gd:19`). The
successful run above is the final instrument.

## Claim 1 — Contract 2 spawns exactly 4 guards on Novice

Raw lines:

```
GUARD_CHECK boot contract=2 difficulty=1
GUARD_CHECK anchor=(127.275,23.159,-5.330) boot_frames=123
GUARD_CHECK SUMMARY guards_t1=4 guards_t2=4 visible=4 with_meshes=4
```

**Verdict: CONFIRMED.** Exactly 4 guards at spawn (t1) and 4 after 600 physics
frames (t2). Contract 2 is `Mission.Guildhall.VaultHeist` / `map_id=guildhall`
(`game/data/generated/gameplay/contracts.json`), and the player anchor is
127.275/23.159/-5.330.

## Claim 2 — the four reported positions

Live t1 positions (30 physics frames after the guard group appeared, sorted by
node name):

```
GUARD_CHECK id=Guard_1 pos=(34.780,44.053,-5.366) visible_in_tree=true meshes=3 meshes_visible=3 lantern=no floor=hit=1 pos=(34.780,44.052,-5.366) collider=LevelCollision_1_-1_3 ceil=hit=0 dist_to_anchor=94.8 feet=44.053 surface_below=44.052 ceiling_above=none
GUARD_CHECK id=Guard_3 pos=(49.225,45.053,-35.570) visible_in_tree=true meshes=2 meshes_visible=2 lantern=no floor=hit=1 pos=(49.225,45.052,-35.570) collider=LevelCollision_1_-2_3 ceil=hit=0 dist_to_anchor=86.5 feet=45.053 surface_below=45.052 ceiling_above=none
GUARD_CHECK id=Guard_ClubLantern_0 pos=(39.773,44.053,-14.314) visible_in_tree=true meshes=4 meshes_visible=4 lantern=yes floor=hit=1 pos=(39.773,44.052,-14.314) collider=LevelCollision_1_-1_3 ceil=hit=0 dist_to_anchor=90.4 feet=44.053 surface_below=44.052 ceiling_above=none
GUARD_CHECK id=Guard_ClubLantern_2 pos=(9.449,36.500,-10.980) visible_in_tree=true meshes=4 meshes_visible=4 lantern=yes floor=hit=1 pos=(9.449,36.500,-10.980) collider=LevelCollision_0_-1_2 ceil=hit=0 dist_to_anchor=118.7 feet=36.500 surface_below=36.500 ceiling_above=none
```

The prior coordinates are **spawn placements**, not live positions. The probe
reproduces the spawn placement from authored data with its own
marker + 8 m-up / 30 m-down ray + 0.15 m clearance:

```
GUARD_CHECK marker id=Guard_1 src=BP_MissionSpawner_Character_C_101 marker=(34.299,36.650,-4.980) marker_xz_dist=0.616 marker_floor=35.533 guard_y=44.053 delta_guard_minus_marker_floor=8.520 ... spawn_pred=(34.299,44.202,-4.980) ... live_y_minus_spawn_pred_y=-0.149
GUARD_CHECK marker id=Guard_3 src=BP_MissionSpawner_Character_C_114 marker=(49.249,46.315,-35.930) marker_xz_dist=0.361 marker_floor=45.052 guard_y=45.053 delta_guard_minus_marker_floor=0.001 ... spawn_pred=(49.249,45.202,-35.930) ... live_y_minus_spawn_pred_y=-0.149
GUARD_CHECK marker id=Guard_ClubLantern_0 src=BP_MissionSpawner_Character_C_100 marker=(39.599,36.500,-13.880) marker_xz_dist=0.467 marker_floor=35.533 guard_y=44.053 delta_guard_minus_marker_floor=8.520 ... spawn_pred=(39.599,44.202,-13.880) ... live_y_minus_spawn_pred_y=-0.149
GUARD_CHECK marker id=Guard_ClubLantern_2 src=BP_MissionSpawner_Character_C_102 marker=(9.449,37.850,-10.980) marker_xz_dist=0.000 marker_floor=36.500 guard_y=36.500 delta_guard_minus_marker_floor=0.000 ... spawn_pred=(9.449,36.650,-10.980) ... live_y_minus_spawn_pred_y=-0.150
```

Comparison with the prior run's four coordinates:

| prior order | prior coordinate | probe `spawn_pred` | delta at spawn | live t1 delta | live dy |
|---|---|---|---|---|---|
| 1 `Guard_ClubLantern_0` | (39.599, 44.202, -13.880) | (39.599, 44.202, -13.880) | 0.000 m | 0.491 m | -0.149 |
| 2 `Guard_1` | (34.299, 44.202, -4.980) | (34.299, 44.202, -4.980) | 0.000 m | 0.634 m | -0.149 |
| 3 `Guard_ClubLantern_2` | (9.449, 36.650, -10.980) | (9.449, 36.650, -10.980) | 0.000 m | 0.150 m | -0.150 |
| 4 `Guard_3` | (49.249, 45.202, -35.930) | (49.249, 45.202, -35.930) | 0.000 m | 0.390 m | -0.149 |

**Verdict: CONFIRMED as spawn placements; NOT reproducible as live positions
within 0.10 m.** Each of the four prior XZ values is the authored marker XZ, and
each prior Y is the 8 m-up ground-ray hit + 0.15 m clearance. All four reproduce
to 0.000 m (four decimal places). But 0.5 s later the guards have settled
0.149–0.150 m onto the floor and patrolled 0.15–0.63 m in XZ, so comparing the
prior numbers to live t1 positions fails a strict 0.10 m test. The prior log
therefore recorded placements at `add_child`, not the state a player sees
seconds later.

## Claim 3 — the guards survive ~10 s

After 600 physics frames:

```
GUARD_CHECK t2 count=4
GUARD_CHECK t2 id=Guard_1 pos=(35.177,44.053,-5.685) visible_in_tree=true
GUARD_CHECK t2 id=Guard_3 pos=(49.225,45.053,-35.570) visible_in_tree=true
GUARD_CHECK t2 id=Guard_ClubLantern_0 pos=(39.773,44.053,-14.314) visible_in_tree=true
GUARD_CHECK t2 id=Guard_ClubLantern_2 pos=(9.449,36.500,-10.980) visible_in_tree=true
GUARD_CHECK persistence disappeared=[] moved_over_0.5m=["Guard_1(0.51)"] hidden_or_meshless=[]
```

**Verdict: CONFIRMED.** None disappeared; all four remain at t2 and all remain
visible in tree. `Guard_1` moved 0.51 m during the 10 s window (patrol, just
over the 0.5 m report threshold); its Y and its surface are unchanged
(44.053 on 44.052), so this is movement, not despawn or a fall. The other three
moved 0.00 m between t1 and t2.

## Claim 4 — visuals exist and are visible in tree

| guard | visible_in_tree | meshes | meshes_visible | lantern | dist_to_anchor |
|---|---|---|---|---|---|
| `Guard_1` | true | 3 | 3 | no | 94.8 m |
| `Guard_3` | true | 2 | 2 | no | 86.5 m |
| `Guard_ClubLantern_0` | true | 4 | 4 | yes | 90.4 m |
| `Guard_ClubLantern_2` | true | 4 | 4 | yes | 118.7 m |

`lantern=yes` means a child named `LanternLight` or `GuardLantern` exists
anywhere under the guard; 2/4 have it, matching the two `Guard_ClubLantern_*`
nodes.

**Verdict: CONFIRMED.** Every guard has a visual tree, every `MeshInstance3D`
passes `is_visible_in_tree()`, and none is hidden. Caveat: this is a headless
scene-tree check, not a rendered pixel check; it proves the visuals exist and
are not hidden, not that lighting/occlusion makes them readable on screen.

## Claim 5 — guards 0/1 are above their marker's room floor (roof/ceiling)

Independent marker rays from the authored `markers` list (spawner class
`BP_MissionSpawner_Character_C` only; 116 such markers found). `marker_floor`
is a ray from marker.y+0.05 down 4 m on mask 1; `feet` is the live guard Y.

| guard (prior order) | authored marker | marker_floor | feet | feet − marker_floor | ceiling ray 1→7 m above guard |
|---|---|---|---|---|---|
| `Guard_ClubLantern_0` (1) | (39.599, 36.500, -13.880) | 35.533 | 44.053 | **+8.520 m** | no hit |
| `Guard_1` (2) | (34.299, 36.650, -4.980) | 35.533 | 44.053 | **+8.520 m** | no hit |
| `Guard_ClubLantern_2` (3) | (9.449, 37.850, -10.980) | 36.500 | 36.500 | 0.000 m | no hit |
| `Guard_3` (4) | (49.249, 46.315, -35.930) | 45.052 | 45.053 | +0.001 m | no hit |

For guards 1/2 the guard's floor ray hits a surface at 44.052
(`LevelCollision_1_-1_3`), 1 mm below its feet, while the marker's room floor is
35.533 (`LevelCollision_1_-1_2`). The spawn origin was 44.202, i.e. 8.669 m
above the room floor (the 8.67 m previously reported); the settled feet are
8.520 m above it. The ceiling ray from guard +1 m to +7 m hits nothing, so the
surface has open space above it, not a room ceiling.

**Verdict: CONFIRMED.** The first two guards are standing on an open, walkable
surface (roof/upper floor) **8.52 m above the room floor beneath their
markers** (8.67 m at the spawn origin). They are not inside the room whose
markers authored them. Guards 3/4 sit within 0.001 m of their marker floor and
are not affected by this failure mode.

## Bottom line

- Guard count: **4 at t1, 4 at t2**.
- Prior four positions: reproduce to **0.000 m as spawn placements**; as live
  positions 30 frames later they differ by 0.15–0.63 m because the guards settle
  and patrol.
- All four survive ≥10 s, all visible, meshes 2–4 each, lantern children on the
  two `ClubLantern` guards.
- Guards 1/2 (prior order) are on a **solid open surface 8.52 m above the room
  floor below their markers**, with no ceiling within 6 m above them. That is
  the roof/ceiling placement, independently reproduced; it is not a diagnostic
  artifact and not a rendering-visibility artifact.
