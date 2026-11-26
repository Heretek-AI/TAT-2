# Guard spawn — static reproduction and visual-path audit (Contract 02, Guildhall)

Lane: **static** worker, guard-spawn investigation (`rem/w10-guards`).
No Godot process was started in this lane; every number below is either
computed from the extracted payloads by
`build/qa/w10/guard_static_pred.py`, read from the GDScript, or copied from the
independent runtime diagnostic recorded by another lane in
`build/qa/w10/guard-diag.log` (explicitly attributed where used).

| | |
|---|---|
| worktree | `/home/john/Projects/TAT-2-rem-w10-guards` |
| HEAD | `04d2e15` (plus the uncommitted `TAT2_GUARD_DIAG` block in `mission_controller.gd`) |
| mission | `Mission.Guildhall.VaultHeist` hosted on Contract 2, `map_id = guildhall` |
| difficulty | Novice (`limit = 4`) |
| prediction script | `build/qa/w10/guard_static_pred.py` |
| full-model log | `build/qa/w10/guard-static-pred.log` |
| authored-only log | `build/qa/w10/guard-static-authored.txt` |

## Verdict summary

| | hypothesis | verdict |
|---|---|---|
| **H1** | the single ingest ray hits a ceiling / upper slab, so the guard is grounded above the marker | **CONFIRMED for 2 of 4** (`_100`, `_101`): first hit `44.052`, grounded `44.202`, **+7.70 / +7.55 m** above the marker, on the storey above. `_102` / `_114` reach the real floor (`+0.15`). The guard lands **on top of** the slab, not inside it. |
| **H2** | the guard body is missing, white, transparent or otherwise invisible | **REJECTED**. All 5 guard GLBs exist; all bound textures exist; every material path is opaque; the navy fallback is opaque; the runtime AABB is human-scale (`2.319 m`) with 2–4 mesh children. |
| **H3** | spawned guards are freed, hidden, culled or moved away after spawn | **REJECTED at spawn; UNDETERMINED long-run.** No `queue_free` / `visible=false` / distance cull on a guard node exists. All four spawned. The 45 s runtime window ends ~7 lines after `mission_ready`, so steady state is unmeasured. The two displaced guards do immediately patrol a **2nd-floor** path from the 3rd floor, so they are not where the marker's room is. |
| **H4** | the capsule is embedded in the slab so the visuals are occluded | **REJECTED**. Capsule `r=0.45, h=2.36` at `+1.18` matches the GLB body (feet `y≈0.001`, head top `2.32`); the runtime down ray hits `grounded − 0.15` and the up ray is clear for 6 m. |

## 1. Loader file order (quoted from the loader, not guessed)

`_map_id_to_sublevels("guildhall", 2)` owns the base order
(`game/src/missions/mission_controller.gd:978-1032`). The Guildhall branch,
verbatim:

```gdscript
"guildhall":
    base = [
        "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json",
        "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI_3rdFloor.tatlevel.json",
        "res://data/generated/levels/Buildings/Guildhall/Guildhall_Vault_CeremonialChambers.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_P.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_Geometry.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_LightingNoGameplay.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_LocalVolumetric.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_Loot.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_Contracts.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_SetSpawners.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_MissionClues.tatlevel.json",
        "res://data/generated/levels/Guildhall/Guildhall_SkyboxGeo.tatlevel.json",
    ]
...
for sub: String in GameData.get_contract_sublevels(order):
    if not base.has(sub):
        base.append(sub)
```

`GameData.get_contract_sublevels(2)` reads `SublevelsToLoad` from Contract 2
and appends `Guildhall/Guildhall_Contract_02.tatlevel.json`
(`game/data/generated/gameplay/contracts.json`, `order: 2`).

Parse order is the array order, with two filters
(`game/src/core/level_loader.gd:6661-6678`):

```gdscript
func _parse_sublevels_with_graph(json_paths: Array, acc: Dictionary, parent: Node3D, on_file: Callable = Callable()) -> void:
    var merged: Dictionary = _prescan_merged_sublevels(json_paths)
    for jp_var: Variant in json_paths:
        var jp: String = str(jp_var)
        var key: String = _level_key_from_res(jp)
        if key != "" and merged.has(key):
            ...
            continue
        _parse_sublevel_file(jp, acc, parent)
    for extra: String in _resolve_authored_streaming(acc):
        _parse_sublevel_file(extra, acc, parent)
```

`_prescan_merged_sublevels` collects every `level_instances` entry of the
supplied files; `_resolve_authored_streaming` appends `streaming_levels` rows
whose `type == "always"` that are neither supplied nor merged. The script
replays both.

**Actual parse order for this load (19 files):**

| # | file | `meshes` entries | note |
|---|---|---|---|
| 1 | `Buildings/Guildhall/Building_Guildhall_POI` | 9,842 | |
| 2 | `Buildings/Guildhall/Building_Guildhall_POI_3rdFloor` | 3,629 | |
| 3 | `Buildings/Guildhall/Guildhall_Vault_CeremonialChambers` | 772 | |
| 4 | `Guildhall/Guildhall_Gameplay` | 1,647 | **all 116 guard markers + 20 player starts** |
| 5 | `Guildhall/Guildhall_P` | 80 | one extra `TATSafeRoomPlayerStart` |
| 6 | `Guildhall/Guildhall_Geometry` | 571 | |
| 7 | `Guildhall/Guildhall_Landscape` | 675 | |
| 8 | `Guildhall/Guildhall_LightingNoGameplay` | 184 | |
| 9 | `Guildhall/Guildhall_LocalVolumetric` | 27 | all 27 are `MI_LocalVolumetricFog` → no draw, no collision |
| 10 | `Guildhall/Guildhall_PeripheryA` | 12,461 | not decorative (contains the safe-room block) |
| 11 | `Guildhall/Guildhall_Loot` | 143 | |
| 12 | `Guildhall/Guildhall_Contracts` | 0 | |
| 13 | `Guildhall/Guildhall_SetSpawners` | 0 | |
| 14 | `Guildhall/Guildhall_MissionClues` | 0 | |
| 15 | `Guildhall/Guildhall_SkyboxGeo` | 33,547 | decorative → `batches_far`, `collide=false` |
| 16 | `Guildhall/Guildhall_Contract_02` | 0 | appended by the contract row |
| 17 | `Guildhall/Guildhall_Audio` | 0 | `streaming_levels` always, added after |
| 18 | `Guildhall/Guildhall_Clouds` | 0 | `streaming_levels` always |
| 19 | `Buildings/Guildhall/Building_Guildhall_POI_Audio` | 0 | `streaming_levels` always |

`merged_skip = []` (none of the 19 is merged as a LevelInstance by another
supplied file), `streaming_added = [Guildhall_Audio, Guildhall_Clouds,
Building_Guildhall_POI_Audio]`.

**File-set sanity check against a real run:** the model counts **63,578**
instanced meshes across the loaded files. The independent run's
`MESH_RECON authored=63578 applied=63100 duplicate=124 name_skipped=243
wardbox=41 moonshape=70 clamp=206` (`build/qa/w10/guard-diag.log`) has the same
63,578. That is an exact match on the authored instance population, so the file
set and order are right.

### Marker branch order that matters

`_parse_sublevel_file` has `SmartObject` **before** `Guard`
(`game/src/core/level_loader.gd:3410-3453`):

```gdscript
if "PlayerStart" in cls: ...
elif "MissionSpawner_Throwable" in cls: ...
...
elif "SmartObject" in cls:
    # 1,707 BP_SmartObject_GuardDefensiveLocation_C markers are posts a
    # guard can occupy, not guard spawns.
    ...
elif "MissionSpawner_Character" in cls or "Guard" in cls:
    var gs: Array = result["guard_spawns"]
    gs.append(p)
```

So the raw 800 `BP_SmartObject_GuardDefensiveLocation_C` markers in
`Guildhall_Gameplay` are **not** guard spawns. Replaying the exact branch order
gives:

- **119** `guard_spawns`: 116 `BP_MissionSpawner_Character_C` in
  `Guildhall_Gameplay` (file 4) + 3 `BP_AirshipGuard_*` in `SkyboxGeo`
  (`(±1000, 120..394, ±800)`, far outside 120 m);
- **21** `player_spawn_transforms`: 20 `TATPlayerStart` in `Guildhall_Gameplay`
  (file 4, in file order) + 1 `TATSafeRoomPlayerStart` in `Guildhall_P`
  (file 5, after all 20);
- 800 SmartObjects excluded.

## 2. Player anchor and the selected four

`_spawn_player` (`mission_controller.gd:3397-3495`) picks the **first**
authored transform whose ray `pos + (0,1,0) → pos + (0,-6,0)` hits layer 1,
places the player at `pos + (0,1,0)`, then `_snap_player_to_ground()`
(`mission_controller.gd:3644`) casts from `player.position + (0,0.5,0)` down
32 m and sets `player.position = hit + (0,0.15,0)`. `anchor` is
`player.global_position` after that.

The first candidate `TATSafeRoomPlayerStart_0` at
`(127.2747, 25.4694, -5.3296)` hits a graybox `GB_Floor_6x6` at `23.159`
(authored-only model: a `SM_CrossBeam_3x3` at `23.108`), so it is chosen.
The independent run confirms the authored spawn line:
`TAT-2 player spawn: source=authored pos=(127.2747, 26.4694, -5.3296)`.
The model's post-snap anchor is `(127.2747, 23.3085, -5.3296)`; the snap y is
not printed by the run, but it only changes the 3D distances by <0.05 m.
Ranks are insensitive: with anchor y 23.31 / 25.55 / 26.60 the first six are
the same and `_102` stays inside the 120 m bound.

`_spawn_guards` then keeps markers with `10 < distance_to(anchor) < 120` in
array order and takes the first 4 (`mission_controller.gd:3738-3755`):

```gdscript
for p in ue_spawns:
    if p is Vector3 and p.distance_to(anchor) > 10.0 and p.distance_to(anchor) < 120.0:
        chosen.append(p)
        if chosen.size() >= limit:
            break
```

**Selection table (46 eligible; ranks 1–14 shown, 15–46 omitted).** The distances
are from the full-loader anchor `(127.2747, 23.3085, -5.3296)`; the
authored-only anchor is 0.05 m lower and moves each distance by <0.02 m, with no
rank change in the first six:

| rank | marker | authored pos | distance (m) |
|---:|---|---|---:|
| 1 | `BP_MissionSpawner_Character_C_100` | `(39.5989, 36.5000, -13.8801)` | 89.07 |
| 2 | `BP_MissionSpawner_Character_C_101` | `(34.2989, 36.6500, -4.9801)` | 93.93 |
| 3 | `BP_MissionSpawner_Character_C_102` | `(9.4489, 37.8500, -10.9801)` | 118.85 |
| 4 | `BP_MissionSpawner_Character_C_114` | `(49.2489, 46.3155, -35.9301)` | 86.91 |
| 5 | `BP_MissionSpawner_Character_C_115` | `(28.4489, 45.0155, -17.0301)` | 101.86 |
| 6 | `BP_MissionSpawner_Character_C_116` | `(35.8489, 45.2155, -5.7301)` | 94.01 |
| 7 | `BP_MissionSpawner_Character_C_118` | `(28.8113, 54.7000, -44.5222)` | 110.53 |
| 8 | `BP_MissionSpawner_Character_C_119` | `(23.1489, 46.1155, -41.4301)` | 112.54 |
| 9 | `BP_MissionSpawner_Character_C_12` | `(20.8918, 6.1755, 32.9051)` | 114.34 |
| 10 | `BP_MissionSpawner_Character_C_120` | `(14.5489, 45.9655, -39.4301)` | 119.93 |
| 11 | `BP_MissionSpawner_Character_C_16` | `(38.1349, 27.0491, -20.8681)` | 90.56 |
| 12 | `BP_MissionSpawner_Character_C_17` | `(34.2828, 36.6859, -19.2358)` | 94.97 |
| 13 | `BP_MissionSpawner_Character_C_18` | `(30.9197, 12.4488, -31.5598)` | 100.45 |
| **14** | **`BP_MissionSpawner_Character_C_20`** | `(43.7149, 27.0500, -26.2188)` | **86.21** |

**Cross-check against the prior probe:** it matches.

- The four Novice markers are `_100` (`y=36.50`), `_101` (`36.65`), `_102`
  (`37.85`), `_114` (`46.3155`) — all at authored `y >= 36.5`, as the prior
  probe said.
- The ground-floor Lounge civilian-adjacent marker
  `BP_MissionSpawner_Character_C_20` is **eligible at rank 14** and is skipped
  by the `limit = 4` break, exactly as the prior probe concluded.
- Candidate order is the Gameplay marker order, which is name-lexicographic in
  the producer (`_0`, `_1`, `_10`, `_100`, `_101`, `_102`, `_114`, ...), not
  numeric. Any reproduction that sorts numerically will not match.

## 3. Ingest prediction from geometry

### Method and the one schema trap

`build/qa/w10/guard_static_pred.py` decodes
`game/data/generated/mesh_collision.json` exactly as
`game/src/core/collision/authored_collision.gd` does and casts the same
vertical ray (`marker + (0,8,0) → marker + (0,-30,0)`, layer 1, first hit).

Transform chain:

- level `basis` → columns `(b0,b3,b6), (b1,b4,b7), (b2,b5,b8)` and
  `basis.scaled_local(scale)` (`_dict_to_transform`, `level_loader.gd:6894`);
- element-local → mesh-local is `_rotator_basis(rotation)` + `center`
  (`_decode_element`);
- UE cm → Godot metres with the `(x, z, y) * 0.01` swap (`_p3`,
  `_baked_points`);
- instance scale is clamped to `[0.05, 40]`; `CollisionShape3D.scale` uses
  `max(abs(scale), 0.05)`.

**Box `half_extent` is the FULL UE extent, not a half-extent.** The
`mesh_collision.json` `notes` string says "HALF-extents", but the loader's
measured contract is the opposite:
`authored_collision.gd:471` says "`half_extent` holds the FULL UE extent", and
the data proves it — `/Engine/BasicShapes/Cube` is `100` on a 1 m GLB and
`SM_Floor_4x4` is `400` on a 4 m floor. The script uses full extent
(`BoxShape3D.size = ext`, slab half = `ext/2`). Using the stale notes as half
would double every slab.

Exact tests used:

- **box** — OBB slab test after transforming the ray into element space
  (rotation + centre), exact;
- **sphere / sphyl** — analytic ray–sphere and ray–capsule in mesh space,
  exact (capsule axis is element-local Y after `_rotator_basis`);
- **convex** — exact vertical upper surface: the LP
  `max y s.t. Σλᵢpᵢ=(x,y,z), Σλ=1, λ≥0` has three equality constraints, so its
  optimum uses at most three non-zero weights; the script takes the max over
  vertex triples whose XZ projection contains the column, with descending-y
  branch-and-bound. No AABB approximation is used for convex hits;
- **coalesced meshes** — when `elements > 16` and the path is not a stair (or
  `(elements-1)·instances > 250`), the loader replaces the set with element
  AABBs; the script does the same and tags those hits `coalesced_aabb`;
- **planar convex skip** — a convex whose baked point AABB is flatter than
  `1e-4 m` is skipped, as in `resolve()`.

`absent` paths (no `mesh_collision.json` entry): the loader does **not** treat
them as no-hit; it falls back to `_heuristic_shape()` — a `BoxShape3D` from
`Mesh.get_aabb()` for props/floors (<12 m diagonal), a trimesh for doors,
stairs, sidewalks and large surfaces (`level_loader.gd:1938-1985`). The default
run of the script reproduces the task's rule (**missing collision = no hit**)
and reports the count; `--heuristic-aabb` additionally decodes the GLB POSITION
accessor bounds and models that fallback (a trimesh is modelled as its AABB
box, i.e. its top surface for a flat walk surface).

Counts: **3,705 of 27,240** collide-true instances have **no**
`mesh_collision.json` entry (79 UE paths: 59 get a heuristic shape, 15 are
name-nonblocking, 5 are tiny). The remaining unmodelled class is one
`complex_as_simple` path (`SM_sphere_50segments`, 3–4 instances near the
columns, a FluidNinja tutorial sphere).

### Prediction table — full-loader model (`--heuristic-aabb`)

| # | marker | authored pos | predicted first hit y | mesh that produced it | predicted grounded y | real floor y | floor mesh | class |
|---:|---|---|---:|---|---:|---:|---|---|
| 1 | `_100` | `(39.5989, 36.5000, -13.8801)` | **44.0518** | `SM_FloorConcreteB_4x4` (box, `Building_Guildhall_POI_3rdFloor`) | **44.2018** | 35.5327 | `SM_Manor_RugA` (convex) → structural floor `SM_Floor_4x4` at 35.5000 | **CEILING** |
| 2 | `_101` | `(34.2989, 36.6500, -4.9801)` | **44.0518** | `SM_FloorConcreteB_4x4` (box) | **44.2018** | 35.5327 | `SM_Manor_RugA` → `SM_Floor_4x4` 35.5000 | **CEILING** |
| 3 | `_102` | `(9.4489, 37.8500, -10.9801)` | 36.5000 | `GB_Floor_4x4` (`absent_box`, graybox) | 36.6500 | 36.5000 | same | FLOOR |
| 4 | `_114` | `(49.2489, 46.3155, -35.9301)` | 45.0518 | `SM_FloorConcreteB_4x4` (box) | 45.2018 | 45.0518 | same | FLOOR |

`CEILING` is the task's rule: first-hit `y > marker.y + 1.0`.

### Prediction table — authored-only model (the task's "missing = no hit")

| # | marker | first hit y | mesh | grounded y | real floor y | class |
|---:|---|---:|---|---:|---:|---|
| 1 | `_100` | 44.0518 | `SM_FloorConcreteB_4x4` | 44.2018 | 35.5327 | CEILING |
| 2 | `_101` | 44.0518 | `SM_FloorConcreteB_4x4` | 44.2018 | 35.5327 | CEILING |
| 3 | `_102` | 28.0307 | `SM_FloorConcreteB_4x2` | 28.1807 | 28.0307 | FLOOR (9.67 m below the marker) |
| 4 | `_114` | 45.0518 | `SM_FloorConcreteB_4x4` | 45.2018 | 45.0518 | FLOOR |

The authored-only `_102` answer is the known blind spot: the actual 36.50 m
surface under that marker is the deferred-content graybox `GB_Floor_4x4`,
which has no `mesh_collision.json` record and is collided by the loader's AABB
fallback. The full-loader column is the engine-true one.

### Cross-check against the independent runtime diagnostic

The other lane's `TAT2_GUARD_DIAG=1` run
(`build/qa/w10/guard-diag.log`: a candidates line, four guard lines and a total)
recorded exactly these four positions. Static prediction vs measured:

| # | marker | predicted first hit | measured ingest result | predicted grounded | measured grounded | predicted floor | measured 4 m floor probe |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `_100` | 44.0518 | `44.052` | 44.2018 | `44.202` | 35.5327 | `35.533` |
| 2 | `_101` | 44.0518 | `44.052` | 44.2018 | `44.202` | 35.5327 | `35.533` |
| 3 | `_102` | 36.5000 | `36.500` | 36.6500 | `36.650` | 36.5000 | `36.500` |
| 4 | `_114` | 45.0518 | `45.052` | 45.2018 | `45.202` | 45.0518 | `45.052` |

All 12 values agree to 1 mm. This is the acceptance gate for the static model.

## 4. H1 — ceiling/upper-slab ingest: confirmed for 2 of 4

**Claim.** `_ground_position(pos, 8.0, 30.0, 0.15)`
(`mission_controller.gd:3662-3680`) starts 8 m above the marker and returns
the **first** hit; the marker's room ceiling is in that column, so the guard is
placed one storey up.

```gdscript
var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
    pos + Vector3(0.0, up_m, 0), pos + Vector3(0.0, -down_m, 0), 1)
var hit: Dictionary = phys.intersect_ray(q)     # FIRST hit only
if not hit.is_empty():
    return (hit.position as Vector3) + Vector3(0.0, offset_y, 0)
```

**Output.** For `_100` the ray starts at `y=44.500`; the first hit is the
`SM_FloorConcreteB_4x4` top at `44.0518` (0.448 m below the start). That slab
is the 3rd-floor construction: the 2nd-floor room below it is 8.5 m tall
(the next surfaces down are the rug/floor at 35.53/35.50 and the 1st-floor
ceiling at 34.40). The guard is grounded at `44.2018`, **+7.702 m** above its
marker and **+8.669 m** above the floor under that marker. `_101` is the same
slab, `+7.552 m`.

For `_102` / `_114` the column is clear between the marker and its floor, so
the first hit is the floor: grounded `+0.15 m` (the runtime's `floor_y` and
`grounded_y` agree).

**Verdict: H1 mechanism confirmed for 2/4, and it is a *storey displacement*,
not an embedded guard.** The runtime down ray hits `grounded − 0.15` and the
up ray is clear for 6 m, so the guard stands **on top of** the slab in the
space above it, not inside the slab. Which room that is, is visible in the
geometry: the slab is the 3rd-floor floor at 44.05, and the 3rd-floor sublevel
has 22 authored markers (doors, ladder climb-downs, a loot box) but **zero
guard spawners** — the two guards land on a storey the mission never authored a
guard post for.

**Follow-on consequence (not H1 itself):** the two displaced guards are
assigned authored patrol paths from the floor below. `_authored_patrol_index_for`
matched path #4 for `_100` (nearest point `(39.86, 35.55, -14.53)`) and path #5
for `_101` (`(35.36, 35.55, -5.83)`) — all waypoints at `y=35.55`, i.e. 8.65 m
below the guard. `_move_ai` is planar (`velocity.y` is gravity only) and
"authored y kept; the guard's movement is planar and floor contact owns y", so
the guard walks the **2nd-floor XZ route while standing on the 3rd floor**. A
player following the marker's room / the authored patrol route on the 2nd floor
will not see it.

## 5. H2 — visual path audit: rejected

### GLB existence and sizes

`_resolve_guard_glb_path` (`guard_ai.gd:940-965`) returns one of three bodies;
`GUARD_HEAD_GLB` (`guard_ai.gd:370-373`) adds two heads for the body-only SKs.
`_spawn_guards` never sets `roster_bucket`, so `roster_source() == "unbound"`
and the roster model override is not consulted. For these four guards
(`Guard_ClubLantern_0`, `Guard_1`, `Guard_ClubLantern_2`, `Guard_3`) no name
matches `haunt`/`security`/`enforcer`, so Novice resolves the **Dyn** body.

| referenced file | bytes | result |
|---|---:|---|
| `Skin/Base/Dyn/SK_GuardEnforcer_Dyn__Body.glb` | 1,506,376 | exists |
| `Skin/Base/Heads/SK_Guard_Head01__Helm.glb` | 1,355,672 | exists (Dyn head) |
| `Skin/Hauntstable/SK_Hauntstable__Body.glb` | 1,282,196 | exists |
| `Skin/Hauntstable/SK_Hauntstable__Head.glb` | 1,500,552 | exists |
| `Skin/Security/SK_GuardSecurity_01_Body.glb` | 1,245,968 | exists |
| `Lanterns/SM_LanternGuardA.glb` (primary lantern) | 184,628 | exists |
| `Gear/Lantern/SK_Lantern.glb` (fallback) | 4,831,568 | exists |

No referenced path is missing. (Also present but **not referenced**:
`SK_Guard_Invisible.glb`, 23,484 B — an authored asset with no code path to it;
it is not the guard model.)

Rest-pose AABB from the GLB POSITION accessors:

| GLB | min | max | size |
|---|---|---|---|
| Dyn body | `(-0.940, 0.001, -0.290)` | `(0.940, 2.045, 0.372)` | `1.881 × 2.044 × 0.662` |
| Head01 Helm | `(-0.130, 1.857, -0.132)` | `(0.130, 2.320, 0.166)` | `0.260 × 0.463 × 0.297` |

Union height 2.319 m. The runtime's measured union is exactly
`2.319 m` with bottom `grounded + 0.001`, so the imported visual is the
authored size and its feet are at the guard origin.

### Materials: every failure is opaque navy, never transparent/white

`_bind_guard_glb_materials` (`guard_ai.gd:1140-1158`) looks up
`mesh_materials.json` for the body key; the Dyn body has three slots
(`MI_GuardEnforcer_Top`, `_Bottom`, `_BodyA`). The head has six slots. Every
albedo/normal/ORM texture those materials name exists on disk (checked above).

- `_guard_navy_fallback` (`guard_ai.gd:1007`) returns
  `albedo_color = GUARD_NAVY`, `roughness = 0.78`, **alpha 1.0, no
  transparency mode**. Missing texture → navy; missing material → navy;
  missing slot → navy. No path returns white or alpha 0.
- `get_guard_material_for_ue` (`guard_ai.gd:1019-1087`) never reads the
  authored `opacity` texture and never sets `transparency`, so the authored
  `opacity` slot on the Top/Bottom materials cannot make the body transparent.
- `_bind_guard_glb_materials`' only early return is when
  `_guard_slots_for_ue_key` is empty; it leaves the GLB import materials and
  logs a white-risk warning. That is not the case for any of the 5 guard keys
  (all present in `mesh_materials.json`).
- `_attach_guard_head` early-returns on a missing head GLB / missing body
  Skeleton3D / failed instantiate, each with a warning; the body keeps its
  torso-only meshes. The Dyn path is complete (head key present, body has a
  Skeleton3D, 4 mesh children at runtime).

**Verdict: H2 rejected.** The guard is not white, not transparent and not
meshless. Caveat: the runtime AABB is the rest-pose AABB; this proves the
meshes exist at human scale, not that a particular pixel was on screen.

## 6. H3 — free / hide / cull / re-parent after spawn: rejected at spawn

Search of `game/src` for anything that hides, frees or culls a spawned guard:

- `guard_ai.gd` frees only `head_inst` (the spare head instance after
  reparenting its meshes, line 1212) and `_carried_node` (item rebuild, lines
  2420/2439). The guard node itself is never freed.
- The only `visible` writes in `guard_ai.gd` are the lantern `OmniLight3D`
  (`2084`, `2123`) — the body is untouched.
- No `visibility_range*` is set on guards or `visual_root`. The only
  `visibility_range` uses in `game/src` are `world_pickup.gd` and the level
  loader's own mesh nodes.
- `get_nodes_in_group("guards")` consumers are read-only: ally revive scan
  (`guard_ai.gd:2167`), HUD pips (`hud.gd:3430`), world map (`hud.gd:3726`),
  thief pickpocket/takedown scans. None toggles visibility or frees.
- `xray_target` / `thief_vision_highlight` consumers only set
  `material_overlay` (`xray_overlay.gd:59-85`), never `visible`.
- `_spawn_guards` runs on the `MissionController` node (`mission_controller.gd:729`)
  and adds each guard as its child. The controller is only torn down with the
  mission (return to menu / reload), which is expected; the prep screen does
  not hide or re-parent it.
- The runtime diagnostic confirms all four selected markers produced a guard
  (`GUARD_DIAG total=4`), with distinct names, and no
  `SCRIPT ERROR`/`ERROR:` line mentions a guard.

**Verdict: H3 rejected at spawn; long-run UNDETERMINED.** The 45 s run spends
all but ~7 log lines in level load; nothing samples the guards after they start
patrolling. What is known statically: the two displaced guards immediately walk
the 2nd-floor authored route from the 3rd floor (see H1), so a player checking
the marker's room will not find them. A longer runtime sample (60–120 s after
`mission_ready`, with guard positions at t+5/t+30/t+60) would settle whether
they stay on a walkable floor or press into a wall; it is not decidable from
code alone.

## 7. H4 — capsule vs grounded y: rejected

`_build_visuals` (`guard_ai.gd:588-601`) builds the capsule:

```gdscript
var cap := CapsuleShape3D.new()
cap.radius = 0.45
cap.height = 2.36
col.shape = cap
col.position = Vector3(0, 1.18, 0)
```

A Godot `CapsuleShape3D` height includes both caps, so the capsule spans
`0.00..2.36` in guard-local space. The GLB body spans `0.001..2.045` and the
attached head reaches `2.320`; the capsule encloses the visual with ~0.04 m of
headroom and a 0.45 m radius (the 1.881 m x extent is the T-pose arm span, not
the torso). If the guard were inside a 0.15 m slab, its capsule and visual
would be embedded and the camera-facing surfaces would be clipped by the slab.

It is not: the prediction puts the guard on the slab **top** (`first_hit + 0.15`),
and the independent runtime's own down/up pair says the same:
`down={hit=1 pos=(39.599,44.052,-13.880) ... dy=-0.15}` and `up={hit=0}`;
`aabb_min.y = grounded + 0.001`, `aabb_max.y = grounded + 2.319`. The 3rd-floor
space above 44.05 is open for at least 6 m at both columns.

**Verdict: H4 rejected.** The capsule is correctly sized and the guard is not
embedded; the failure mode is "one storey too high", not "inside the ceiling".

## 8. Exact commands and reproducibility

Full-loader model (the engine-true one, uses the GLB AABB fallback for the
graybox floors; writes `build/qa/w10/guard-static-pred.log`):

```bash
cd /home/john/Projects/TAT-2-rem-w10-guards
python3 build/qa/w10/guard_static_pred.py --heuristic-aabb \
  > build/qa/w10/guard-static-pred.log 2>&1
```

Authored-only model (the task's "missing collision = no hit" rule; writes
`build/qa/w10/guard-static-authored.txt`):

```bash
python3 build/qa/w10/guard_static_pred.py \
  > build/qa/w10/guard-static-authored.txt 2>&1
```

Selection-only / file-order-only:

```bash
python3 build/qa/w10/guard_static_pred.py --files
python3 build/qa/w10/guard_static_pred.py --select
```

The script is pure Python 3 (no numpy/scipy). `--json out.json` emits the four
prediction rows. It reads:

- `game/src/missions/mission_controller.gd` (hard-coded `guildhall` base list,
  quoted above);
- `game/data/generated/gameplay/contracts.json` (Contract 2 sublevels);
- `game/data/generated/levels/**/*.tatlevel.json` (meshes + markers);
- `game/data/generated/mesh_collision.json` (authored AggGeom);
- `game/assets/ue/Content/**/*.glb` (only with `--heuristic-aabb`, POSITION
  accessor bounds for the loader's `absent` fallback).

## 9. Limitations

- The runtime corroboration is another lane's run (`build/qa/w10/guard-diag.log`,
  `build/qa/w10/guard-runtime.md`), not this lane's measurement. It is used
  only as the acceptance check for the static model; no Godot process was
  started here.
- The static model covers authored AggGeom exactly, the `absent` AABB fallback
  approximately (a trimesh is modelled as its AABB box), and one
  `complex_as_simple` FluidNinja sphere only as an "unmodelled" count. Neither
  approximation affects the four columns (the nearest `complex_default`
  instance is a tutorial sphere, and the four first hits/floor hits are
  authored or graybox boxes).
- The player anchor's post-snap `y` is modelled (`23.3085`) but not printed by
  the runtime. Rank order for the first four is insensitive to it
  (verified at `y = 23.31 / 25.55 / 26.60`).
- The long-run behaviour of the two displaced guards (do they stay on the 3rd
  floor, walk into a wall, or leave the room entirely?) is not decidable from
  code; it needs a timed runtime sample.
