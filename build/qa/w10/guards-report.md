# Guard visibility investigation — Contract 02 (Guildhall VaultHeist)

**Question.** The user played `Mission.Guildhall.VaultHeist` (Contract 02) on
`guildhall`, walked the ground floor and the upper levels, and saw no guards.

**Answer in one line.** At Novice exactly 4 guards spawn; **two of the four are
grounded on a floor slab 8.67 m above the room their marker sits in** (the
`+8 m` ingest ray hits the storey above), the other two are real floors but
13–23 m above the player's start and 87–119 m away, so a ground-floor walk
cannot meet one and the two floor-placed guards are far from the start. All four markers are authored
`BP_MissionSpawner_Character_C` — none is a defensive post; the runtime pool is
119 spawners, not the 916 mixed rows in `spawn_elements`.

Headless reproduction (Contract 02 boots from the QA hook):

```
flock /tmp/opencode/tat2-godot.lock -c 'TAT2_GUARD_DIAG=1 timeout 45 tools/godot --headless --path game -- --qa-mission=Mission.Guildhall.VaultHeist' > build/qa/w10/guard-diag.log 2>&1
EXIT=124  (timeout kill, mission stayed up)
```

---

## 1. What the runtime actually spawned

Command: `grep GUARD_DIAG build/qa/w10/guard-diag.log`
Output (verbatim, 6 lines):

```
GUARD_DIAG candidates=119 guard_scene_elements=119 smart_objects=800
GUARD_DIAG idx=0 name=Guard_ClubLantern_0 marker=(39.599,36.500,-13.880) grounded=(39.599,44.202,-13.880) delta=7.70 moved=true meshes=4 aabb_min=(38.659,44.203,-14.371) aabb_max=(40.539,46.522,-13.590) down={hit=1 pos=(39.599,44.052,-13.880) collider=LevelCollision_1_-1_3 parent=Mission meta_ue_mesh=- meta_key=- dy=-0.15} up={hit=0} floor_hit=1 floor=(39.599,35.533,-13.880) src_name=BP_MissionSpawner_Character_C_100 src_class=BP_MissionSpawner_Character_C
GUARD_DIAG idx=1 name=Guard_1 marker=(34.299,36.650,-4.980) grounded=(34.299,44.202,-4.980) delta=7.55 moved=true meshes=3 aabb_min=(33.359,44.203,-5.352) aabb_max=(35.239,46.522,-4.690) down={hit=1 pos=(34.299,44.052,-4.980) collider=LevelCollision_1_-1_3 parent=Mission meta_ue_mesh=- meta_key=- dy=-0.15} up={hit=0} floor_hit=1 floor=(34.299,35.533,-4.980) src_name=BP_MissionSpawner_Character_C_101 src_class=BP_MissionSpawner_Character_C
GUARD_DIAG idx=2 name=Guard_ClubLantern_2 marker=(9.449,37.850,-10.980) grounded=(9.449,36.650,-10.980) delta=1.20 moved=true meshes=4 aabb_min=(8.509,36.651,-11.471) aabb_max=(10.389,38.970,-10.690) down={hit=1 pos=(9.449,36.500,-10.980) collider=LevelCollision_0_-1_2 parent=Mission meta_ue_mesh=- meta_key=- dy=-0.15} up={hit=0} floor_hit=1 floor=(9.449,36.500,-10.980) src_name=BP_MissionSpawner_Character_C_102 src_class=BP_MissionSpawner_Character_C
GUARD_DIAG idx=3 name=Guard_3 marker=(49.249,46.315,-35.930) grounded=(49.249,45.202,-35.930) delta=1.11 moved=true meshes=2 aabb_min=(48.309,45.203,-36.302) aabb_max=(50.189,47.522,-35.640) down={hit=1 pos=(49.249,45.052,-35.930) collider=LevelCollision_1_-2_3 parent=Mission meta_ue_mesh=- meta_key=- dy=-0.15} up={hit=0} floor_hit=1 floor=(49.249,45.052,-35.930) src_name=BP_MissionSpawner_Character_C_114 src_class=BP_MissionSpawner_Character_C
GUARD_DIAG total=4
```

| idx | src marker | authored marker | grounded | Δ | marker's own floor | guard − own floor | class |
|---|---|---|---|---|---|---|---|
| 0 | `_100` | 36.500 | **44.202** | +7.70 | 35.533 | **+8.669** | CEILING |
| 1 | `_101` | 36.650 | **44.202** | +7.55 | 35.533 | **+8.669** | CEILING |
| 2 | `_102` | 37.850 | 36.650 | −1.20 | 36.500 | +0.150 | FLOOR |
| 3 | `_114` | 46.315 | 45.202 | −1.11 | 45.052 | +0.150 | FLOOR |

The marker floor is the diagnostic's independent 4 m ray under the **marker**;
the "guard − own floor" column is `grounded − (floor_hit + 0.15)`. For idx 0/1
that is **8.669 m** — the guard is on the storey above, not in the marker's room.

`up={hit=0}` for all four: nothing collidable within 6 m above any guard. For
idx 0/1 that is consistent with standing on an exposed top surface; the collider
is the merged chunk `LevelCollision_1_-1_3`, so `ue_mesh` is on the child
`CollisionShape3D` and the body-level meta lookup reports `-` (documented
limitation, resolved by §2).

---

## 2. Independent static prediction (no engine)

Script: `build/qa/w10/guard_static_pred.py`. It replays the loader's real file
order for `guildhall` order 2, the `markers` `elif` chain (SmartObject before
Guard), `_spawn_player`'s first-hit choice and the 10–120 m annulus, then casts
the same vertical ray against the authored collision elements decoded the way
`authored_collision.gd` decodes them (box/sphyl/sphere exact, convex = max-y
over vertex triples containing the column, planar convex skip, element-AABB
coalescing, `absent` = loader AABB heuristic).

Command:
`python3 build/qa/w10/guard_static_pred.py > build/qa/w10/guard-static-pred.log`

Prediction (verbatim tail):

```
   1 BP_MissionSpawner_Character_C_100  authored (39.5989, 36.5000, -13.8801)  d=89.07
   first hit: yes  y=44.0518  mesh=/Game/Art/Environment/Common/Floors/SM_FloorConcreteB_4x4  (box, prims)
   grounded = hit + 0.15 = 44.2018   (+7.702 vs marker)  CEILING
   highest hit below marker (y <= 36.55): y=35.5327 mesh=/Game/Art/Environment/Props/Furniture/Carpets/SM_Manor_RugA (convex)
   2 BP_MissionSpawner_Character_C_101 ... y=44.0518  mesh=SM_FloorConcreteB_4x4  grounded 44.2018 (+7.552) CEILING
   highest hit below marker: y=35.5327 SM_Manor_RugA
   3 BP_MissionSpawner_Character_C_102 ... y=36.5000  mesh=/Game/Test/LevelKits/Graybox/GB_Floor_4x4 (absent_box)  grounded 36.6500 (-1.200) FLOOR
   4 BP_MissionSpawner_Character_C_114 ... y=45.0518  mesh=SM_FloorConcreteB_4x4  grounded 45.2018 (-1.114) FLOOR
```

Predicted grounded y vs runtime grounded y:

| idx | predicted | runtime | difference |
|---|---|---|---|
| 0 | 44.2018 | 44.202 | 0.000 |
| 1 | 44.2018 | 44.202 | 0.000 |
| 2 | 36.6500 | 36.650 | 0.000 |
| 3 | 45.2018 | 45.202 | 0.000 |

The "ceiling" for idx 0/1 is literally another `SM_FloorConcreteB_4x4` — the
floor of the storey above the marker's room. That is why the guard is invisible
from the marker's room: it is standing on that upper floor, 8.67 m up.

Selection reproduced: anchor = `TATSafeRoomPlayerStart_0` (127.2747, 23.3085,
-5.3296); 46 of 119 markers fall inside the annulus; ranks 1–4 are `_100`,
`_101`, `_102`, `_114`; `_20` is rank 14. This matches the previously
established facts exactly.

The file order that produces this selection was read from the loader, not
guessed: `_map_id_to_sublevels("guildhall", 2)` base list +
`GameData.get_contract_sublevels(2)` (`Guildhall_Contract_02`) + the three
always-streamed audio/cloud sublevels, with the loader's `merged_skip` empty.
That is 19 files; `guard_spawns=119`, `smart_objects=800`, `player starts=21`.
`Guildhall_Gameplay` alone holds 116 of the 119; `Guildhall_SkyboxGeo`
contributes 3 (see §4).

---

## 3. Independent runtime check (separate probe, no diagnostic)

Command:

```
flock /tmp/opencode/tat2-godot.lock -c 'timeout 120 tools/godot --headless --path game --script res://tests/probe_guard_positions.gd' > build/qa/w10/guard-check.log 2>&1
```

The probe boots `res://scenes/mission.tscn` itself (contract order 2,
difficulty Novice), waits for the player + guard group, samples after 30
physics frames (settle), then after 600 more. It never sets
`TAT2_GUARD_DIAG` and never reads the diag log.

Output (verbatim, 125-line log, `SCRIPT ERROR`/`ERROR:` = 0):

```
GUARD_CHECK boot contract=2 difficulty=1
GUARD_CHECK anchor=(127.275,23.159,-5.330) boot_frames=123
GUARD_CHECK id=Guard_1 pos=(34.780,44.053,-5.366) visible_in_tree=true meshes=3 meshes_visible=3 lantern=no floor=hit=1 pos=(34.780,44.052,-5.366) collider=LevelCollision_1_-1_3 ceil=hit=0 dist_to_anchor=94.8 feet=44.053 surface_below=44.052 ceiling_above=none
GUARD_CHECK id=Guard_3 pos=(49.225,45.053,-35.570) visible_in_tree=true meshes=2 meshes_visible=2 lantern=no floor=hit=1 pos=(49.225,45.052,-35.570) collider=LevelCollision_1_-2_3 ceil=hit=0 dist_to_anchor=86.5 feet=45.053 surface_below=45.052 ceiling_above=none
GUARD_CHECK id=Guard_ClubLantern_0 pos=(39.773,44.053,-14.314) visible_in_tree=true meshes=4 meshes_visible=4 lantern=yes floor=hit=1 pos=(39.773,44.052,-14.314) collider=LevelCollision_1_-1_3 ceil=hit=0 dist_to_anchor=90.4 feet=44.053 surface_below=44.052 ceiling_above=none
GUARD_CHECK id=Guard_ClubLantern_2 pos=(9.449,36.500,-10.980) visible_in_tree=true meshes=4 meshes_visible=4 lantern=yes floor=hit=1 pos=(9.449,36.500,-10.980) collider=LevelCollision_0_-1_2 ceil=hit=0 dist_to_anchor=118.7 feet=36.500 surface_below=36.500 ceiling_above=none
GUARD_CHECK marker id=Guard_1 src=BP_MissionSpawner_Character_C_101 marker=(34.299,36.650,-4.980) marker_xz_dist=0.616 marker_floor=35.533 guard_y=44.053 delta_guard_minus_marker_floor=8.520
GUARD_CHECK marker id=Guard_3 src=BP_MissionSpawner_Character_C_114 marker=(49.249,46.315,-35.930) marker_xz_dist=0.361 marker_floor=45.052 guard_y=45.053 delta_guard_minus_marker_floor=0.001
GUARD_CHECK marker id=Guard_ClubLantern_0 src=BP_MissionSpawner_Character_C_100 marker=(39.599,36.500,-13.880) marker_xz_dist=0.467 marker_floor=35.533 guard_y=44.053 delta_guard_minus_marker_floor=8.520
GUARD_CHECK marker id=Guard_ClubLantern_2 src=BP_MissionSpawner_Character_C_102 marker=(9.449,37.850,-10.980) marker_xz_dist=0.000 marker_floor=36.500 guard_y=36.500 delta_guard_minus_marker_floor=0.000
GUARD_CHECK t2 count=4
GUARD_CHECK persistence disappeared=[] moved_over_0.5m=["Guard_1(0.51)"] hidden_or_meshless=[]
GUARD_CHECK detail lanterns_t1=2
GUARD_CHECK SUMMARY guards_t1=4 guards_t2=4 visible=4 with_meshes=4
```

| check | independent result |
|---|---|
| guard count at spawn | **4** |
| guard count after 600 physics frames | **4** (none freed) |
| `visible_in_tree` / visible meshes | 4/4 true, 2–4 meshes, all visible |
| lantern children | 2 (`ClubLantern_0`, `ClubLantern_2`) |
| spacing to the marker floor | **8.520 m / 8.520 m / 0.000 m / 0.001 m** |
| ceiling within 7 m above | none for any guard |
| anchor | (127.275, 23.159, −5.330) |

The probe samples after 30 physics frames, so the displaced guards have already
fallen the diagnostic's 0.15 m and patrolled up to 0.6 m; `feet=44.053`
matches the ingest value `44.202` minus the 0.149 m drop onto the same slab
(`surface_below=44.052`). The checker also recomputed the four **spawn**
placements independently (marker + the same `+8 m` first-hit ray + 0.15) and
got `(39.599,44.202,-13.880)`, `(34.299,44.202,-4.980)`,
`(9.449,36.650,-10.980)`, `(49.249,45.202,-35.930)` — a 0.000 m match with the
diagnostic. The live positions differ only because the guards settle 0.15 m and
patrol; the diagnostic sampled the placement, not the state a player sees
seconds later.

The two guards keep patrolling while displaced: `_authored_patrol_index_for`
matched paths whose nearest waypoints are at `y=35.55`, i.e. 8.5 m *below*
the guards, and `_move_ai` is planar. The guards therefore walk the 2nd-floor
XZ route while standing on the 3rd floor — a player following the authored
patrol route on the 2nd floor is under them.

---

## 4. Candidate pool: the "87 % junk" claim is a producer-array artefact

The note that prompted this section counted `spawn_elements` in
`Guildhall_Gameplay.tatlevel.json`:

```
916  kind=guard   =  800 BP_SmartObject_GuardDefensiveLocation_C
                  +  116 BP_MissionSpawner_Character_C
```

That array is **not** what `_spawn_guards` receives. `level_loader.gd` classifies
`markers` with `SmartObject` first (line 3436) and only then
`MissionSpawner_Character`/`Guard` (line 3448); the posts go to
`result["smart_objects"]`, which no consumer reads. Runtime proof:

```
GUARD_DIAG candidates=119 guard_scene_elements=119 smart_objects=800
```

| claim | measured | verdict |
|---|---|---|
| `_spawn_guards` pool contains 800 posts | `candidates=119`, `smart_objects=800` | **REFUTED for the loader path** |
| the four chosen are posts | all four `src_class=BP_MissionSpawner_Character_C` (`_100`, `_101`, `_102`, `_114`) | **REFUTED** |
| `spawn_elements` is the guard pool | 916 rows vs the loader's 119-position pool | **the 916 is a producer output, unconsumed today** |

Two real residues:

1. **119 ≠ 116.** `Guildhall_SkyboxGeo` contributes 3 `BP_AirshipGuard_*`
   markers (2 `Patrol`, 1 `Swarm`) at y = 122/394/178, x/z ≥ 300 m from the
   anchor. They fail the 10–120 m annulus here, but they are horizon actors,
   not guards, and would be selectable on a map where the anchor/annulus
   includes them.
2. **The producer still emits `kind=guard` for both populations.** Today only
   the loader path matters; a future consumer of `spawn_elements` inherits the
   800 posts. Split the kind (`guard` / `guard_post`) in the producer before
   any nearest-first selection is built on that array.

Because the runtime pool is already clean, a nearest-first selection over
`guard_spawns` would **not** scatter guards over the 800 posts; it would still
pick from the same 119 spawners.

---

## 5. Verdict per hypothesis

| # | hypothesis | verdict | evidence |
|---|---|---|---|
| **H1** | the grounding ray lands on the ceiling/floor above the marker | **CONFIRMED for 2 of 4** (`_100`, `_101`) | Runtime: grounded 44.202 vs marker 36.500/36.650, **+8.669 m above the marker's own floor** (35.533); down ray hits the same surface at −0.15; up ray clear 6 m. Static: first hit 44.0518 `SM_FloorConcreteB_4x4` (the 3rd-floor slab), real floor 35.5327 `SM_Manor_RugA`. Independent probe: +8.520 m after settling. The guard is **on top of** the slab, not inside it. |
| **H2** | guards are placed but invisible (GLB/material/scale/orientation) | **REFUTED** | All 5 guard GLBs + all bound textures exist (1.24–1.51 MB bodies, 1.36/1.50 MB heads); every material failure path is opaque navy (alpha 1.0, no transparency slot read); runtime meshes 2–4, **all `is_visible_in_tree()`**, union AABB `1.881 × 2.319 × 0.662 m` with bottom at `grounded + 0.001` (the GLB rest bounds exactly). |
| **H3** | guards are culled/freed after spawn | **REFUTED (spawn + 10 s)** | `total=4`; independent probe `guards_t1=4 guards_t2=4`, `disappeared=[]`, `hidden_or_meshless=[]`; only `head_inst` (spare head) and `_carried_node` are freed in `guard_ai.gd`; no distance culler sets guard visibility; `xray_target`/`thief_vision_highlight` only add a material overlay. The 0.51 m move is patrol. Long-run (minutes) still unmeasured. |
| **H4** | the room is too dark to see them | **REFUTED as primary cause; not photometrically measured** | Two guards (`ClubLantern_0`, `ClubLantern_2`) build an `OmniLight3D` lantern (`range 8.5 m`, `energy 1.4`) unconditionally; guard 2 — one of the two on a real floor — is self-lit. The two displaced guards are not in the room at all, so darkness cannot explain them. No light-meter capture was taken; the "two unlit guards in a dark room" sub-case is **UNTESTED**. |
| H4′ | capsule embedded in the slab / occluded by it | **REFUTED** | Capsule `r=0.45 h=2.36` at `+1.18` spans `0.00..2.36`, matching the GLB `0.001..2.320`; the down ray hits `grounded − 0.15`, the up ray is clear, so the guard stands *on* the surface. |

**Why the user saw no guard at all.** At Novice only four guards exist, and the
first four eligible markers in file order are all 13–23 m above the player's
start (y 36.5–46.3 vs anchor y 23.16). Of those four, two are grounded one
storey too high (44.05), one is 118.7 m away on a graybox floor, and one is
86.5 m away on the 45.05 m level, one storey above the marker rooms. The
ground floor is empty **by selection**, and half of the upper-floor spawns are
on the wrong storey. The mission never put a guard in the rooms the user
walked.

---

## 6. Minimal fix proposal (not implemented here)

**F1 — ground guards at the marker's own storey (root cause). Confidence: high.**
`_ground_position` returns the first hit from `marker + 8 m`; the marker floats
0.97–1.35 m above its floor (`_100` 36.500 → floor 35.533), so +8 m is above
the storey ceiling. Accept only a hit at or below the marker, stepping past
ceilings, and fail closed if none:

```gdscript
var from: Vector3 = pos + Vector3(0.0, up_m, 0.0)
var to: Vector3 = pos + Vector3(0.0, -down_m, 0.0)
for _i: int in range(6):
    var hit: Dictionary = phys.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
    if hit.is_empty():
        break
    var hp: Vector3 = hit["position"] as Vector3
    if hp.y <= pos.y + 0.05:                 # marker's own floor/shelf
        return hp + Vector3(0.0, offset_y, 0.0)
    from = hp - Vector3(0.0, 0.02, 0.0)       # step below the ceiling, keep going
return pos + Vector3(0.0, 0.5, 0.0)          # no surface: caller must reject
```

Scope is small: `_ground_position` is called only from `_spawn_guards`
(main + the three synthetic patrol corners), so no loot/civilian path changes.
Expected result: `_100`/`_101` at 35.683 (marker floor 35.533 + 0.15), the
same rooms the markers were authored in; all four guards on real floors.

**F2 — fail loud on a displaced guard. Confidence: high.**
In `_spawn_guards`, reject `absf(grounded_pos.y - pos.y) > 2.0` (valid markers
produce 0.8–1.2 m because they float above the floor) with one
`push_warning("[mission_controller] guard %d grounded %.2f m from marker ...")`,
and skip the spawn instead of placing it. This is the regression detector that
would have made this bug visible in every run.

**F3 — close the test gap. Confidence: high.**
`run_tests.gd` §10 only asserts `guards.size() != 0` (lines 351/450). Add:
for each guard, nearest `level_stats.guard_spawns` position in XZ, then
`absf(guard.global_position.y - marker.y) <= 2.0`. Two of these four fail that
assertion today.

**F4 — selection coverage (experience fix, not the visibility bug). Confidence: medium.**
At Novice the four selected markers are all 13–23 m above the player start;
after F1 the ground floor is still empty. `_20` (ground floor, y 27.05,
0.70 m from the civilian) is rank 14 and skipped by `limit=4`. Options: raise
the Novice count, or select one marker per storey band instead of first-in-file
order. This is a tuning decision and should be a separate change with a
playtest, not bundled with F1.

**F5 — housekeeping. Confidence: high, no runtime effect today.**
Exclude `BP_AirshipGuard_*` from `guard_spawns` (3 skybox markers), and split
`spawn_elements` `kind=guard` into `guard`/`guard_post` in the producer so the
800 posts cannot leak into a future consumer. Do not build nearest-first on
`spawn_elements` as-is.

---

## 7. Reproduce

```bash
# diagnostic (code: TAT2_GUARD_DIAG=1 block in mission_controller.gd)
flock /tmp/opencode/tat2-godot.lock -c 'TAT2_GUARD_DIAG=1 timeout 45 tools/godot --headless --path game -- --qa-mission=Mission.Guildhall.VaultHeist' > build/qa/w10/guard-diag.log 2>&1

# independent runtime probe (no diagnostic)
flock /tmp/opencode/tat2-godot.lock -c 'timeout 120 tools/godot --headless --path game --script res://tests/probe_guard_positions.gd' > build/qa/w10/guard-check.log 2>&1

# static prediction (no engine)
python3 build/qa/w10/guard_static_pred.py > build/qa/w10/guard-static-pred.log
```

| artefact | content |
|---|---|
| `game/src/missions/mission_controller.gd` | `TAT2_GUARD_DIAG` block + `_diag_ray` (inert when unset) |
| `game/tests/probe_guard_positions.gd` | independent guard probe |
| `build/qa/w10/guard-diag.log` | 45 s Contract 02 run, 6 `GUARD_DIAG` lines |
| `build/qa/w10/guard-check.log` | independent probe, 4/4 guards, 0 errors |
| `build/qa/w10/guard-static-pred.log` | static selection + collision prediction |
| `build/qa/w10/guard_static_pred.py` | static model (re-runnable) |
| `build/qa/w10/guard-runtime.md` | runtime lane write-up |
| `build/qa/w10/guard-static.md` | static lane write-up |
| `build/qa/w10/guard-check.md` | checker lane write-up |

No gameplay change was made; the diagnostic is the only code change and it is
inert unless `TAT2_GUARD_DIAG=1` is set.

