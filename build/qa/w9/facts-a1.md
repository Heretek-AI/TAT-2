# W9-P1 / A1 — authored collision: current runtime path + `mesh_collision.json` facts

Read-only investigation. Worktree: `/home/john/Projects/TAT-2-rem-w9-p1`
HEAD: `c2a1cd89e5e3859c590c408236929da65567cb74` (`docs(w9): P0 capture evidence, perf matrix, scorecard closure`).
`game/data/generated` is a symlink to `/home/john/Projects/TAT-2/game/data/generated`.
No Godot process was run; all counts below come from JSON/`grep` inspection.

---

## Counts (trust these first)

### 1. `game/data/generated/mesh_collision.json` (file identity)

| fact | value |
|---|---|
| size | 17,626,566 bytes (`ls -l`; also `tools/audit_baseline.json:191`) |
| mtime | 2026-11-25 04:48 |
| current sha256 | `deb3771ef701444b24947b2f37fc1a2b34759dec09dc00764368eea41101c8e6` |
| sha recorded in `tools/audit_baseline.json:195` | `2a6f95153c55bf651e04905f7cd61f8c26d2e901de573cb1ee5eba74339edc47` (observed mismatch with the symlinked file; not investigated here) |
| schema | `tat2.mesh_collision/1` (`tools/parse_collision.py:140`) |
| `index_data_included` | `false` |
| top-level keys (sorted) | `counts`, `generated_by`, `index_data_included`, `meshes`, `notes`, `schema`, `source`, `units` |

`counts` **verbatim** (same order as the file, which is `sort_keys=True`):

```json
{
  "body_setup_elements": 8382,
  "body_setups": 2935,
  "box": 2334,
  "convex": 5922,
  "elements": 8601,
  "empty_body_setup": 0,
  "files_scanned": 12541,
  "meshes": 1992,
  "multi_body_setup_packages": 40,
  "nav_collision_packages": 1977,
  "nav_collision_packages_with_area_data": 0,
  "nav_collision_packages_without_simple_collision": 330,
  "non_package_documents": 0,
  "packages_complex_as_simple": 14,
  "packages_with_uniform_collision_profile": 1921,
  "skeletal_body_setup_elements": 219,
  "skeletal_body_setups": 219,
  "sphere": 50,
  "sphyl": 295,
  "tapered_capsule": 0
}
```

Other exact top-level strings:

- `source`: `"extracted/json/**"`
- `generated_by`: `"tools/parse_collision.py"`
- `units`: `"centimetres, UE asset space (mesh local space)"`
- `notes`: `"FKBoxElem X/Y/Z are HALF-extents; FKSphereElem Radius; FKSphylElem Radius+Length as authored; FKConvexElem VertexData is flattened to vertices_flat in PackedVector3Array order; authored triangle indices are emitted only with --with-index-data (non-empty on 5919 of 5922 hulls); no rounding or unit conversion is applied."`

Arithmetic check: `body_setup_elements 8382 + skeletal_body_setup_elements 219 = elements 8601`;
`box 2334 + sphere 50 + sphyl 295 + convex 5922 = 8601`.

### 2. Key format and Guildhall placed-mesh intersection

| metric | value |
|---|---|
| mesh keys total | **1,992** |
| keys starting `/Game/` | **1,987** |
| keys starting `/Engine/` | **5** (`BasicShapes/Cone`, `Cube`, `Cylinder`, `Plane`, `Sphere`) |
| other prefixes | 0 |

Guildhall load set used for the intersection: `mission_controller._map_id_to_sublevels("guildhall", 2)` = the 15 base sublevels in `game/src/missions/mission_controller.gd:986-1021` plus `GameData.get_contract_sublevels(2)` (`game/src/core/game_data.gd:514-526`), which for order 2 is `Guildhall/Guildhall_Contract_02` only (`game/data/generated/tables/Gameplay/Quests/DT_Contracts_1_to_16.json:134-140`, `ContractOrder: 2`). `Guildhall_Contract_02.tatlevel.json` itself has **0** `meshes`, **0** `volumes`, **2** `actors`.

**DoD denominator (non-decorative Guildhall geometry: 14 base files + `Guildhall_Contract_02`; `Guildhall_SkyboxGeo` excluded because the loader marks it decorative):**

| metric | value |
|---|---|
| distinct placed mesh paths | **996** |
| distinct paths with authored collision data (`elements` non-empty) | **889** |
| distinct paths with no `mesh_collision` entry | **107** |
| total authored elements on those 889 paths | **2,205** |
| element breakdown | box **1,217**, convex **918**, sphyl **57**, sphere **13** |
| raw placed mesh records (instances) | **30,031** |
| raw instances whose path has authored data | **24,448** |
| exact-duplicate transforms removed by the loader (`MESH_RECON duplicate`) | **124** |
| deduped instances kept | **29,907** |
| deduped instances whose path has authored data | **24,406** |
| instances whose data says `NoCollision` | **337** across **12** paths |
| instances whose data says `QueryOnly` | **158** across **7** paths |
| instances whose data says physics-enabled (neither of the above) | **23,953** across **870** paths |

Including the decorative `Guildhall_SkyboxGeo` (33,547 records / 162 distinct paths) for completeness:
- distinct paths **1,006**, paths with data **891**, elements **2,207**, raw covered instances **56,472**, deduped covered instances **56,430**.
- 10 paths appear only in `SkyboxGeo`; two of them have data (`SM_RockC_low`, `SM_RockD_Low`).

The 107 paths without data account for **5,583** raw instances; top absent paths:
`GB_Floor_2x2` 2,125; `SM_LeafB2` 1,304; `GB_Floor_6x6` 950; `SM_DistantBuildingC` 555;
`SM_StonePilesA` 253; `GB_Ceiling_2x2` 186; `GB_Floor_4x4` 161; `SM_LightBeam_Lens` 134;
`GB_Cube_6m` 133; `1m_Plane_Reverse` 70.

### 3. Current runtime shape totals (Guildhall)

| metric | value / citation |
|---|---|
| `PERF_CENSUS` (W9 baseline, contract-4 run) | `meshes=6106 instances=63550 chunk_nodes=6018 ... collision_bodies=225 collision_shapes=24466` — `build/qa/w9/logs/p1_baseline_run_tests.log:236` |
| same run, summary line | `TAT-2 Perf: chunks=6018 collision_bodies=225 collision_shapes=24466 occluders=768` — `build/qa/w9/logs/p1_baseline_run_tests.log:241` |
| `MESH_RECON` same run | `authored=63581 applied=63103 duplicate=124 name_skipped=243 wardbox=41 moonshape=70 ...` — `build/qa/w9/logs/p1_baseline_run_tests.log:235` |
| 11b gate | `PASS: 11b W1p PERF_CENSUS` — `build/qa/w9/logs/p1_baseline_run_tests.log:255` |
| earlier R8 run | `instances=63550`, `collision_shapes=24466` — `docs/reports/logs/r8/probe_door_walk.log:63,68` |
| earlier W7 run | `instances=64544`, `collision_shapes=24310` — `docs/reports/logs/w7-merged/e2e.log:78,83` |
| `collision_shapes` gate in `run_tests` | `col_shapes <= 0` fails; `col_shapes >= 32000` fails — `game/tests/run_tests.gd:501` |
| census shape scan | every direct `StaticBody3D` child and its `CollisionShape3D` children — `game/src/core/level_loader.gd:5337-5343` |
| result keys | `collision_bodies`, `collision_shapes`, `building_shapes`, `curb_shapes`, `collision_dropped` — `game/src/core/level_loader.gd:5435-5441` |

Raw Guildhall records for contract 2 (no contract sublevel meshes) are **63,578** = **33,547** `SkyboxGeo` + **30,031** non-decorative. The W9 contract-4 run's `authored=63581` is exactly 3 more (`Guildhall_Contract_04` 1 + `Guildhall_Contract_Teleporters` 2, shown in the `source_sublevels` map on line 236). `MESH_RECON` reconciles: `63581 - 124 duplicate - 243 name_skipped - 41 wardbox - 70 moonshape = 63103 applied`.

Loader citations for those log lines: `authored_meshes` is accumulated at `game/src/core/level_loader.gd:2960`; `MESH_RECON` is printed at `5482-5496`; `result["mesh_instances"]` is set at `5409`; `PERF_CENSUS` is printed at `5369` (only for a `guildhall` map hint or `TAT2_PERF_CENSUS`, `5363-5366`; env constant at `207`). `MESH_RECON applied` is the loader's returned draw-item instance count; `PERF_CENSUS instances` is a separate node census that sums `MultiMesh.instance_count` over the surviving mesh children of the level parent (`game/src/core/level_loader.gd:5286-5310`). The two log values (`63,103` vs `63,550`) are different counters, not two measurements of the same thing.

There are also **102** authored blocking volumes across the Guildhall level JSONs (`TATBlockingVolume`): `Guildhall_Geometry` 23, `Guildhall_P` 6, `Guildhall_PeripheryA` 41, `Building_Guildhall_POI` 32; `Guildhall_Contract_02` has 0.

---

## 1. Current runtime collision path

### 1.1 `_get_mesh_and_shape(ue_path)` — `game/src/core/level_loader.gd:1811-1905`

Cache lookup and early exits:

- `_mesh_res_cache` hit returns the cached dict — `1812-1813`.
- Cache value shape: `{"mesh": Mesh|null, "shape": Shape3D|null}` plus optional `"shape_offset": Vector3` — `1814`; box branch adds `shape_offset` at `1897`, other branches set it to `Vector3.ZERO` (`1885`, `1892`, `1900`).
- Unresolvable res path: cached `{"mesh": null, "shape": null}` — `1815-1818`.
- `load(res_path)`; a non-`PackedScene` hit goes through `_note_corrupt_mesh()` and is still cached — `1820-1826`, `1911-1915`.
- Instantiate scene, `_find_first_mesh()`, duplicate the mesh — `1827-1832`.
- Additive light-shaft names: shape is explicitly `null` — `1834-1844`, predicate `_is_additive_light_shaft()` `1803-1808`.
- GLB material slots bound by index; WorldGrid door/mountain material fixes; `SM_Guildhall_Sign` mesh split — `1849-1858`.

Shape decision (all thresholds in metres; `sz = mesh.get_aabb().size`, `sz.length()` is the AABB diagonal):

```text
1859  is_nonblocking = rug|carpet|placemat|paper|poster|scroll|curtain|cloth|drape|sheet|cable|wire|rope|ivy|vine|foliage
1869  is_stair_run   = "stair" AND NOT (rail|boundary|post|banister|balustrade|upstairs)
1870  is_walk_surface= "sidewalk"
1875  is_door_aperture = "door" OR "archway"
1878  is_roof_surface = _is_roof_convex_surface(low_u, m)   # roof_collision_kind(...) == "convex"
1882  if not is_nonblocking and sz.length() > 0.45:
1883      if is_door_aperture:            shape = m.create_trimesh_shape(); offset = ZERO
1886      elif is_roof_surface and sz.length() < 12.0:
1887                                          shape = m.create_convex_shape();   offset = ZERO
1893      elif sz.length() < 12.0 and not is_stair_run and not is_walk_surface:
1894          box = BoxShape3D.new(); box.size = max(sz, 0.1) per axis; shape = box; offset = aabb.get_center()
1898      else:                            shape = m.create_trimesh_shape(); offset = ZERO
```

Exact line numbers for the four branches: door trimesh `1883-1885`; roof convex `1886-1892`; box `1893-1897`; fallback trimesh `1898-1900`. The **0.45 gate is line 1882**. A shape is not created when the name hits `is_nonblocking` or when the AABB diagonal is `<= 0.45` m. The mesh is still drawn in those cases.

After the branch:
- `inst.free()` — `1901`.
- Non-null shape gets resource meta `"ue_mesh" = ue_path` — `1902-1903`.
- Result cached under the exact `ue_path` string — `1904`.
- `_mesh_res_cache` declared `Dictionary` — `game/src/core/level_loader.gd:53`; cleared in `_exit_tree()` — `game/src/core/level_loader.gd:628`.

### 1.2 Cache keying: per UE path, not per instance

- `_mesh_res_cache[ue_path]` — key is the level JSON `mesh` string verbatim (case-sensitive), value is `{mesh, shape[, shape_offset]}` — `1812-1813`, `1904`.
- The same `Shape3D` resource is shared by every instance of that UE path. A new `CollisionShape3D` node is created per placed instance in `_add_collider()` — `4061-4068`, inside the per-instance loop `for i2 in range(count)` at `4340-4350`.
- Exceptions that create new shape resources per instance/item:
  - Den floor-prop grounding: `BoxShape3D.new()` per qualifying instance — `3868-3882`, call `4346-4348`.
  - Den window/wall split: four new `BoxShape3D` per qualifying wall — `3911-3922`, call `4344-4345`.
  - Spline-deformed pieces: `spline_shape_for()` creates a trimesh from the deformed mesh; one per spline item, reused for that item's instances — `2427-2436`, call `4332-4335`.

### 1.3 `spline_shape_for()` — `game/src/core/level_loader.gd:2427-2436`

- Returns `{"shape": null, "shape_offset": Vector3.ZERO}` for null mesh — `2429-2430`.
- Returns no shape when the deformed mesh AABB diagonal `<= 0.45` — `2432-2433`.
- Otherwise `shape = mesh.create_trimesh_shape()`, offset `ZERO` — `2434-2435`.
- The only runtime call site is `_build_one_draw_item()` at `4333` (inside `if not spline_item.is_empty()`), which replaces the cached rigid shape for that item.

### 1.4 Call sites of `_get_mesh_and_shape()`

`grep -n "_get_mesh_and_shape(" game/src/core/level_loader.gd`:

| line | caller | purpose |
|---|---|---|
| `1811` | definition | — |
| `4195` | `_build_one_draw_item()` | loads mesh + shape for every draw item |
| `4421` | `_merge_candidate()` | mesh only; shape is ignored, collision still emitted by `_build_one_draw_item()` |

There are no other `game/src` call sites. Tests/probes that call it directly: `game/tests/test_w6l_searchlight.gd:72,108,123`; `test_w5b_materials.gd:209,233`; `test_traversal_routes.gd:590`; `test_stair_walk.gd:137`; `probe_t08_red.gd:46`; `test_roof_collision.gd:198,244,253,275,294,399,456,499,551,589,677`; `probe_door_aperture.gd:19`; `probe_geometry_placement.gd:260`; `t08_material_checks.gd:128`; `run_tests.gd:3371,3973`.

Merged visuals: `_build_draw_items()` builds the merge plan first, then still calls `_build_one_draw_item()` for every item — `game/src/core/level_loader.gd:4787-4805`. The merge function's own header says collision/occluders are emitted per original item through the normal draw path — `4361-4364`.

### 1.5 How the shape is attached

All mesh-derived collision goes through `_add_collider(ctx, cell, shape, tr, shape_offset, kind, label)` — `game/src/core/level_loader.gd:4029-4070`.

- **Body**: `StaticBody3D`, name `LevelCollision_<cellx>_<celly>_<bucket>`, `collision_layer = 1`, added to `ctx["parent"]` (the scene/level root, not the visual MeshInstance3D) — `4051-4059`.
- Body bucket key = `"<cellx>_<celly>_<used/384>"`; `MAX_SHAPES_PER_BODY = 384` — `4047-4050`, const `183`.
- **Shape node**: new `CollisionShape3D`; `cs.shape = shape` — `4061-4062`.
- `cs.set_meta("ue_mesh", label)` only when `label != ""` — `4063-4064`.
- `cs.transform = Transform3D(tr.basis.orthonormalized(), tr * shape_offset)` — `4065-4066`.
- `cs.scale = (max(|scale.x|,0.05), max(|scale.y|,0.05), max(|scale.z|,0.05))` — `4067`.
- `body.add_child(cs)` — `4068`.
- Normal collision bodies are **not** added to a group. `grep add_to_group` in the loader finds only `level_loader` (`610`), `expansion_placements` (`2902`), `lightbeam_cards` (`4322`) and `blocking_volume` (`5829`).
- Visual node metadata (for reference): `ue_mesh`, `decorative` (= not `item.collide`), `source_sublevel`, `source_sublevels`, `source_counts`, optional `override_materials`, `beam_card`, `periph_range_end` — `4309-4323`, `4185`.
- `shape_offset` semantics: **box** = `aabb.get_center()` in mesh-local space (`1897`), transformed by the instance `tr` at attach time (`4066`); **trimesh/convex/spline** = `Vector3.ZERO` (`1885`, `1892`, `1900`, `2435`).

Collision is only emitted when all of these are true: `not use_cpd`, `not hidden_in_game`, `item.collide`, `ctx.generate_collision`, `not is_clutter`, and `shape != null` — `4330-4336`. `item.collide` is true only for normal `acc["batches"]`; `batches_nocol` and `batches_far` pass `collide=false` — `3649-3654`, `2977-2981`.

### 1.6 `_ue_mesh_to_res()` and how it maps to collision keys

`game/src/core/level_loader.gd:1703-1723`:

1. `clean = ue_path.split(".")[0]` (strips a `.Object` suffix).
2. If `clean` begins `/Game/`, strip that prefix.
3. Try `res://assets/ue/Content/<clean>.glb`, then `.gltf`.
4. If `clean` begins `/Engine/`, try `res://assets/ue/Raw/Engine/Content/<clean without /Engine/>.glb`, then `.gltf`.
5. Otherwise return `""`.

Examples:

- `/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_Wall_4x6` → `res://assets/ue/Content/Art/Environment/Urban/Walls/SM_Urban_Ext_Wall_4x6.glb`
- `/Engine/BasicShapes/Cube` → `res://assets/ue/Raw/Engine/Content/BasicShapes/Cube.glb`

`mesh_collision.json` keys are UE **package paths**: the producer takes the BodySetup export's `Outer.ObjectPath` and does `owner_path.rsplit(".", 1)[0]` — `tools/parse_collision.py:647-653`. Level JSON `mesh` values are the same package-path form (no `.Object` suffix). Exact string equality is therefore the join key: the 889/891 intersections above were computed with `mesh_json_key == collision_key`, no normalization. The reverse helper `glb_res_to_ue_path()` only handles `res://assets/ue/Content/` and `res://assets/ue/Raw/TAT/Content/`, not `Raw/Engine` — `1987-1999`.

### 1.7 Every name-token / structural heuristic that decides collision

| heuristic | lines | exact behaviour |
|---|---|---|
| `is_nonblocking` | `1859`, gate `1882` | Substring list `rug, carpet, placemat, paper, poster, scroll, curtain, cloth, drape, sheet, cable, wire, rope, ivy, vine, foliage`; suppresses shape creation (mesh still drawn). |
| `is_stair_run` | `1869`, branch `1893` | `"stair" in low_u` and none of `rail, boundary, post, banister, balustrade, upstairs`; prevents the box branch, so `<12 m` stair runs become trimesh. |
| `is_walk_surface` | `1870`, branch `1893` | `"sidewalk" in low_u`; prevents the box branch, so sidewalks become trimesh. |
| `is_door_aperture` | `1875`, branch `1883` | `"door"` or `"archway"` anywhere in the path; takes priority over roof/box and becomes trimesh. |
| `_is_roof_convex_surface` / `roof_collision_kind` | `3801-3802`, `3701-3717`, `3725-3760` | Only `/roofs/` paths. If `ROOF_BOX_TOKENS` (`trim, chimney, vent, pipe, gutter, rail, watertower, tank, roofdetails, spike`) → box. Else measure upward-facing area within `ROOF_TOP_BAND_M=0.10` of the AABB top; `>= ROOF_FLAT_TOP_FRAC=0.5` → box, otherwise convex. Roof convex branch additionally requires AABB diagonal `<12.0` (`1886`). |
| `_is_additive_light_shaft` | `1803-1808`, `1834-1844` | `lightshaft`, `godray`, `skysearchlight`, or `searchlight` on a `vfx_`/`/vfx/` path; sets `shape = null` (mesh rendered with additive card). |
| `CLUTTER_TOKENS` / `is_clutter` | const `388-391`, gate `4329-4330` | `sm_leaf, sm_grass, sm_newgrass, sm_newspaper, sm_pebble, sm_debris, foliage, ivy, vine, moss, cobweb, sm_dust`; suppresses collision entirely. |
| `_is_decorative_sublevel` | const `396`, func `2475-2476`, use `2977-2981` | Token `skyboxgeo`; all meshes in that sublevel go to `batches_far` and `collide=false`. |
| skip-by-name before batching | `3076-3081` | `fogsheet`, `fogsphere`, `volumetric`, `skysphere`, `blocker` → `name_skipped`, no geometry/collision. |
| `SM_WardBox` skip | `3088-3090` | exact suffix `/sm_wardbox` → hidden, no geometry/collision. |
| `_is_debug_shape_mesh` | `3383-3399`, call `3100-3102` | `/test/art/primitives/` + stem `sm_shape_` + no override + all slots `MI_Default_White` → skipped, no geometry/collision. |
| moon billboards | `3433-3455`, call `3072-3074` | materials containing `Moonshape` / `IsMoonshape`, or `1m_plane_reverse` with no albedo → hidden, no geometry/collision. |
| `_is_den_window_wall` | `3838-3842`, use `4339-4345` | Path must contain `thievesden`/`windowborder`/`thievesden_window` AND `window`/`glass`/`wall`; a `BoxShape3D` is split into 4 boxes (two pillars, sill, lintel) — `3888-3924`. |
| `_ground_den_prop_shape` | `3868-3882`, use `4346-4348` | `thievesden` + box height `<2.5 m` + floating `(0.02, 1.0] m`; grows the box down to the instance ground plane (new shape resource). |
| `_fix_worldgrid_door_surfaces` | `2101-2130`, call `1853` | **Material only.** Path contains `door`/`gate`/`fence`; replaces WorldGrid slots. Does not change the shape. |
| `_fix_worldgrid_mountain_surfaces` | `2143-2156`, call `1854` | **Material only.** Path under `/skybox/mountains/` and stem starts `sm_mountain`; replaces WorldGrid slots. Does not change the shape. |
| `blocking_volume` volumes | `5778-5839` | Separate path, not `_get_mesh_and_shape`. A volume whose `class` contains `block`/`blocking` becomes a `StaticBody3D` + `BoxShape3D` (`size = extent * 2`, min 0.1), `collision_layer=1`, `collision_mask=0`, group `blocking_volume`, name `BlockingVolume_<n>`. No cap check; counted as `collision_bodies`, `collision_shapes`, `building_shapes` (`5834-5839`). |

Related but **not** collision-deciding:
- `MERGE_EXCLUDE_TOKENS` (`218-224`) only prevents visual cell-merging; merged items still emit their normal collision (`4361-4364`, `4787-4805`).
- `OCCLUDER_INCLUDE_TOKENS` / `OCCLUDER_EXCLUDE_TOKENS` (`421-438`) feed `BoxOccluder3D` only (`3805-3824`), not physics.
- `STRUCTURAL_NO_FADE_TOKENS` (`404-406`) is culling only.

### 1.8 Other current collision sources (not via `_get_mesh_and_shape`)

| source | lines | shape |
|---|---|---|
| Blocking volumes | `5778-5839` | `BoxShape3D`, body per volume, group `blocking_volume` |
| Landscapes | `6977-6993` | `ConcavePolygonShape3D.backface_collision = true`, `StaticBody3D` named `LandscapeCollision_<n>`, 1 body + 1 shape per landscape |
| Guildhall safe-room floor | `6674-6701` | `BoxShape3D` 8 x 0.2 x 8 m at `(126.0, 18.52, -10.43)`, 1 body + 1 shape |
| Procedural curb ribbons | `4979-4989` | 3 `BoxShape3D` per segment (walk + two lips), `kind="curb"`, capped by `MAX_CURB_SHAPES=4000` |
| Den window split | `3888-3924` | 4 `BoxShape3D` per qualifying wall |
| Den floor-prop grounding | `3868-3882` | grown `BoxShape3D` per qualifying instance |

Budget constants: `MAX_SHAPES_PER_BODY=384`, `MAX_TOTAL_SHAPES=32000`, `MAX_BUILDING_SHAPES=28000`, `MAX_BUILDING_SHAPES_FTUE=40000`, `MAX_TOTAL_SHAPES_FTUE=44000`, `MAX_CURB_SHAPES=4000` — `game/src/core/level_loader.gd:183-197`. Overflow is counted and push_warned per partition — `4029-4047`; `check_collider_budget()` push_errors and returns false — `4079-4087`.

---

## 2. Authored data: `game/data/generated/mesh_collision.json`

### 2.1 Top-level contract

See the Counts section for the verbatim `counts`, `units`, `notes`, `schema`, `source`, `generated_by`, `index_data_included`.

`meshes` is a JSON object with 1,992 keys, sorted lexicographically (producer sorts keys — `tools/parse_collision.py:664-667`; test asserts sorted — `tools/test_parse_collision.py:414-418`).

### 2.2 Per-mesh record shape

A mesh record is a JSON object. Field presence across all 1,992 records:

| field | count | meaning |
|---|---:|---|
| `body_setups` | 1,992 | array of body records (always present) |
| `elements` | 1,992 | **flattened** element array for all bodies (always present; may be `[]`) |
| `owner_type` | 1,992 | `StaticMesh`, `PaperSprite`, `PhysicsAsset`, `BrushComponent`, `SplineMeshComponent`, or `mixed` |
| `owner_types` | 1,992 | sorted unique owner-type list |
| `body_setup` | 1,952 | body name, only when the package has exactly one body (`parse_collision.py:566-567`) |
| `object_type` | 1,926 | emitted only when every body's `DefaultInstance.ObjectType` is present and equal (`569-577`) |
| `collision_responses` | 1,924 | emitted only when uniform across bodies (`578-580`) |
| `collision_profile` | 1,921 | uniform across bodies (`569-571`) |
| `nav_collision` | 1,647 | `{present, has_area_data, cooked[]}` (`585-586`) |
| `collision_trace_flag` | 375 | uniform `CollisionTraceFlag` across bodies (`581-584`) |
| `complex_as_simple` | 375 | derived boolean, same condition (`581-584`) |
| `collision_enabled` | 38 | uniform `DefaultInstance.CollisionEnabled` (`575-577`) |

Owner-type distribution of the 1,992 packages: `StaticMesh` 1,647; `PaperSprite` 278; `PhysicsAsset` 34; `BrushComponent` 25; `SplineMeshComponent` 3; `mixed` 5.
Elements by owner type: `StaticMesh` 6,291; `mixed` 1,317; `BrushComponent` 431; `PaperSprite` 278; `PhysicsAsset` 219; `SplineMeshComponent` 65.
All **889 placed** Guildhall paths with data are `owner_type: "StaticMesh"` and have exactly **one** `body_setups[]` entry.

A `body_setups[]` record (`name`, `owner_type`, `owner_object`, `owner_path`, `element_start`, `element_count` always; 3,154 body records total = 2,935 `BodySetup` + 219 `SkeletalBodySetup`):

```json
{
  "name": "BodySetup_0",
  "owner_type": "StaticMesh",
  "owner_object": "StaticMesh'SM_Civic_GuildhallOfficeFloor'",
  "owner_path": "/Game/Art/Environment/Civic/Interior/SM_Civic_GuildhallOfficeFloor.2",
  "element_start": 0,
  "element_count": 1,
  "default_instance": { "...": "authored DefaultInstance struct (2,939 records)" },
  "default_instance_fields": { "collision_profile": "BlockAll", "collision_responses": [ ... ], "object_type": "ECollisionChannel::ECC_WorldStatic" },
  "collision_trace_flag": "ECollisionTraceFlag::...",        // 1,076 records
  "complex_as_simple": true,                                  // 1,076 records
  "bone_name": "...",                                         // 219
  "phys_material": "...",                                     // 66
  "physics_type": "...",                                      // 23
  "b_double_sided_geometry": false,                           // 12
  "physical_animation_data": { ... },                         // 2
  "b_generate_mirrored_collision": false                      // 541
}
```

### 2.3 Where the elements live + exact JSON path

**There is no top-level `elements` array and no `elements` key inside `body_setups[]`.** Verified: 0 of 3,154 body records contain `"elements"`.

- All bodies' elements are concatenated in source order into the mesh-level flat array.
- `body_setups[i].element_start` / `element_count` slice that flat array.
- Producer: `_body_json()` writes start/count (`tools/parse_collision.py:501-509`); `_package_json()` does `elements.extend(body.elements)` (`552-557`).

Exact path expressions (for a real mesh key `KEY`):

```text
all elements:           meshes[KEY].elements
one body's elements:    meshes[KEY].elements[ meshes[KEY].body_setups[i].element_start : meshes[KEY].body_setups[i].element_start + meshes[KEY].body_setups[i].element_count ]
```

Python: `data["meshes"][key]["elements"]`
jq: `.meshes[$key].elements`
Producer test proving the slice invariant for every package: `tools/test_parse_collision.py:419-445`.

Element field names by `type` (closed vocabulary; parser validates unknown keys/fields and fails closed — `tools/parse_collision.py:111-126`, `330-335`):

| `type` | fields (exact JSON names) |
|---|---|
| `box` | `type`, `center` `[x,y,z]`, `rotation` `{pitch,yaw,roll}`, `half_extent` `[x,y,z]`, `rest_offset`, `b_contribute_to_mass`, `collision_enabled`, `name` |
| `sphere` | `type`, `center` `[x,y,z]`, `radius`, `rest_offset`, `b_contribute_to_mass`, `collision_enabled`, `name` |
| `sphyl` | `type`, `center` `[x,y,z]`, `rotation` `{pitch,yaw,roll}`, `radius`, `length`, `rest_offset`, `b_contribute_to_mass`, `collision_enabled`, `name` |
| `convex` | `type`, `index`, `vertex_count`, `vertices_flat` `[x,y,z,...]`, `aabb_min`, `aabb_max`, `aabb_valid`, `transform` `{rotation:{X,Y,Z,W}, translation:[x,y,z], scale3d:[x,y,z]}`, `rest_offset`, `b_contribute_to_mass`, `collision_enabled`, `name`; plus `index_data`/`index_count` only with `--with-index-data` |
| `tapered_capsule` | 0 occurrences in the shipped data; mapping is `Radius0/Radius1/Length` per `FKTAperedCapsuleElem` (docs `tools/parse_collision.py:116-119`) |

Units are centimetres in mesh-local UE space; no rounding or conversion — top-level `units`/`notes`, parser `_num`/`_vec3` (`262-289`). Box `half_extent` is exactly `FKBoxElem.X/Y/Z`; `rotation` is the authored UE rotator, mapped `Pitch→pitch, Yaw→yaw, Roll→roll` with no conversion (`280-289`, `337-344`).

Real complete examples (one per type; long `vertices_flat` trimmed only):

```json
// box — /Game/Art/Environment/Urban/Walls/SM_Urban_Ext_Wall_4x6
{
  "b_contribute_to_mass": true,
  "center": [-199.97102, 15.012631, 325.00006],
  "collision_enabled": "ECollisionEnabled::QueryAndPhysics",
  "half_extent": [400.05795, 30.031782, 650.0001],
  "name": "None",
  "rest_offset": 0.0,
  "rotation": {"pitch": 0.0, "roll": 0.0, "yaw": 0.0},
  "type": "box"
}
```

```json
// sphere — /Game/Art/Environment/Lights/Candles/SM_CandleB (55 Guildhall instances)
{
  "b_contribute_to_mass": true,
  "center": [-0.10000894, 1.521851, 3.1702907],
  "collision_enabled": "ECollisionEnabled::QueryAndPhysics",
  "name": "None",
  "radius": 7.716017,
  "rest_offset": 0.0,
  "type": "sphere"
}
```

```json
// sphyl — /Game/Art/Environment/Basement/Pillars/SM_PillarBasementA_12m (26 Guildhall instances)
{
  "b_contribute_to_mass": true,
  "center": [0.0, 7.6293945e-06, 600.0001],
  "collision_enabled": "ECollisionEnabled::QueryAndPhysics",
  "length": 1186.7773,
  "name": "None",
  "radius": 66.29773,
  "rest_offset": 0.0,
  "rotation": {"pitch": 0.0, "roll": 0.0, "yaw": 0.0},
  "type": "sphyl"
}
```

```json
// convex — /Game/Art/Environment/Civic/Interior/SM_Civic_GuildhallOfficeFloor
{
  "aabb_max": [1109.422, 128.32433, 50.1],
  "aabb_min": [-1109.422, -260.28116, -0.1],
  "aabb_valid": true,
  "b_contribute_to_mass": true,
  "collision_enabled": "ECollisionEnabled::QueryAndPhysics",
  "index": 0,
  "name": "None",
  "rest_offset": 0.0,
  "transform": {
    "rotation": {"W": 1.0, "X": 0.0, "Y": 0.0, "Z": 0.0},
    "scale3d": [1.0, 1.0, 1.0],
    "translation": [0.0, 0.0, 0.0]
  },
  "type": "convex",
  "vertex_count": 18,
  "vertices_flat": [1109.422, 128.26575, 50.04142, "... 51 more floats ..."]
}
```

### 2.4 Key format

- Keys are UE package paths exactly as extracted from `BodySetup.Outer.ObjectPath` minus the `.Object` suffix: `/Game/.../SM_X` or `/Engine/...`.
- `1,987` start `/Game/`, `5` start `/Engine/`; zero other prefixes.
- 5 real Guildhall-relevant keys and their element counts:

| key | elements | types |
|---|---:|---|
| `/Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_GuildhallEntrance` | 5 | 5 convex |
| `/Game/Art/Environment/Civic/Fence/SM_Guildhall_Sign` | 3 | 2 sphyl + 1 box |
| `/Game/Art/Environment/Civic/Interior/SM_Civic_GuildhallOfficeFloor` | 1 | 1 convex |
| `/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_Wall_4x6` | 1 | 1 box |
| `/Game/Art/Environment/Civic/Exterior/SM_Civic_RailA_1x1` | 1 | 1 box |

(These five are all placed in the Guildhall load; `SM_Urban_Ext_Wall_4x6` alone has 1,125 Guildhall records.)

### 2.5 `CollisionTraceFlag` / `NoCollision` / `QueryOnly` presence and counts

There is no boolean field named `NoCollision` or `QueryOnly`; both appear as enum **values**.

`collision_trace_flag` + derived `complex_as_simple`:

| location | field | count/value |
|---|---|---|
| mesh record | `collision_trace_flag` | 375 records: `CTF_UseSimpleAsComplex` 359; `CTF_UseComplexAsSimple` 14; `CTF_UseSimpleAndComplex` 2 |
| mesh record | `complex_as_simple` | 375: `false` 361; `true` 14 |
| `body_setups[]` | `collision_trace_flag` | 1,076: `CTF_UseSimpleAsComplex` 1,060; `CTF_UseComplexAsSimple` 14; `CTF_UseSimpleAndComplex` 2 |
| `body_setups[]` | `complex_as_simple` | 1,076: `false` 1,062; `true` 14 |

Placed Guildhall paths: 873 have no trace flag; 14 `CTF_UseSimpleAsComplex`; 1 `CTF_UseComplexAsSimple`; 1 `CTF_UseSimpleAndComplex`.
`counts.packages_complex_as_simple` = **14**.

`collision_enabled`:

| location | values / counts |
|---|---|
| mesh record (uniform across bodies) | **38** records: `ECollisionEnabled::NoCollision` **31**, `ECollisionEnabled::QueryOnly` **7** |
| `body_setups[].default_instance_fields.collision_enabled` | same 38 bodies: `NoCollision` 31, `QueryOnly` 7 |
| `elements[].collision_enabled` | **8,601** elements: `QueryAndPhysics` 8,599, `PhysicsOnly` 2 |
| `collision_profile` (mesh, uniform) | `BlockAll` 1,383; `BlockAllDynamic` 279; `BlockAllExceptAOE` 163; `SemiSolidWall` 37; `NoCollision` 30; `BlockAllExceptVision` 12; `BlockAllExceptVisionDynamic` 9; `HidingSpot` 4; `BlockAllDynamicExceptProjectionPawn` 1; `BlockAllExceptPermeatingProjectile` 1; `SemiSolidWallDynamic` 1; `Projectile` 1 |

The 30 `NoCollision` profile packages are a subset of the 31 `NoCollision`-enabled packages; the extra enabled one is `/Game/Art/Environment/Nature/Trees/Willow/Materials/SM_WillowLeaves`.
On placed Guildhall paths: 12 paths / 337 instances are `NoCollision`; 7 paths / 158 instances are `QueryOnly` (same sets for profile and enabled).

### 2.6 Guildhall placed-mesh intersection — per sublevel

Raw level-JSON records (one record = one instance in these files; the loader later dedupes exact duplicates):

| sublevel | records | distinct paths | records on paths with data |
|---|---:|---:|---:|
| `Buildings/Guildhall/Building_Guildhall_POI` | 9,842 | 487 | 7,578 |
| `Buildings/Guildhall/Building_Guildhall_POI_3rdFloor` | 3,629 | 194 | 3,352 |
| `Buildings/Guildhall/Guildhall_Vault_CeremonialChambers` | 772 | 74 | 684 |
| `Guildhall/Guildhall_Gameplay` | 1,647 | 59 | 1,425 |
| `Guildhall/Guildhall_P` | 80 | 13 | 38 |
| `Guildhall/Guildhall_Geometry` | 571 | 57 | 426 |
| `Guildhall/Guildhall_Landscape` | 675 | 3 | 11 |
| `Guildhall/Guildhall_LightingNoGameplay` | 184 | 29 | 151 |
| `Guildhall/Guildhall_LocalVolumetric` | 27 | 1 | 27 |
| `Guildhall/Guildhall_PeripheryA` | 12,461 | 560 | 10,613 |
| `Guildhall/Guildhall_Loot` | 143 | 5 | 143 |
| `Guildhall/Guildhall_Contracts` | 0 | 0 | 0 |
| `Guildhall/Guildhall_SetSpawners` | 0 | 0 | 0 |
| `Guildhall/Guildhall_MissionClues` | 0 | 0 | 0 |
| `Guildhall/Guildhall_Contract_02` | 0 | 0 | 0 |
| **non-decorative total** | **30,031** | **996** | **24,448** |
| `Guildhall/Guildhall_SkyboxGeo` (decorative) | 33,547 | 162 | 32,024 |
| **all 16 files** | **63,578** | **1,006** | **56,472** |

Exact-duplicate accounting for the non-decorative set, using the loader's `mp + pos + basis + scale + spline + overrides + hidden` key: **124** duplicates (POI 19, POI 3rdFloor 7, Gameplay 12, PeripheryA 86), leaving **29,907** instances; **24,406** of those are on paths with data. 42 of the 124 duplicates are on paths with data; the other 82 are on paths without data. That gives 24,448 - 42 = 24,406 deduped covered instances.

`body_setups` per placed path: all 889 have exactly 1. Element-count distribution: 572 paths have 1 element; 222 have 2-4; 61 have 5-9; 34 have 10+. Median 1, mean 2.48, max 41 (`SM_Books_BookshelfA`).

Name-gate counts over the 24,448 raw covered instances (upper bounds; these are the loader's current suppression rules, independent of the authored data):
`nonblocking` names **172**; `CLUTTER_TOKENS` names **50**; `hidden_in_game` **552**; CPD **546**; spline **168**; override materials **5,305** (overrides do not suppress collision).

---

## 3. Existing producers, consumers, tests

### 3.1 Repo grep results

`grep -rIl` over the worktree (excluding `extracted/`, `.git`, `.godot`):

| token | files containing it | occurrences in `game/src` or `game/tests` |
|---|---|---|
| `mesh_collision` | `tools/parse_collision.py`, `tools/test_parse_collision.py`, `tools/manifest_audit.py`, `tools/audit_baseline.json`, `tools/consumer_allowlist.json`, `docs/reports/re-audit-20261124.md`, `docs/reports/remediation-20261125/T01-pipeline.md`, `docs/reports/logs/r8/audit.log` | **0** |
| `AggGeom` | `tools/parse_collision.py`, `tools/test_parse_collision.py`, `tools/consumer_allowlist.json`, `docs/FIDELITY_GAPS.md`, `docs/reports/re-audit-20261124.md`, `docs/reports/remediation-20261125/T01-pipeline.md` | **0** |
| `CollisionTraceFlag` | `tools/parse_collision.py`, `tools/test_parse_collision.py`, `docs/reports/re-audit-20261124.md` | **0** |
| `TAT2_COLLISION` | none | **0** (repo-wide: 0 matches) |

**No game code reads `mesh_collision.json`.** `game/src/core/level_loader.gd` contains zero occurrences of `mesh_collision`, `AggGeom` or `CollisionTraceFlag`. Current shape creation is entirely the render-mesh heuristic in §1.

### 3.2 `tools/parse_collision.py` output contract

- Docstring contract: `tools/parse_collision.py:2-127`; schema constant line `140`; output name line `143`.
- CLI: `python3 tools/parse_collision.py [--extracted DIR] [--out-dir DIR] [--with-index-data] [--quiet]` — `714-736`.
  - default `--extracted` = `<repo>/extracted` — `718-723`.
  - default `--out-dir` = `<repo>/game/data/generated` — `724-729`.
- Final write (the contract): `<out-dir>/mesh_collision.json`, `json.dumps(payload, indent=2, sort_keys=True) + "\n"`, UTF-8; `OSError` prints to stderr and returns 1 — `747-756`.
- Success returns 0 and prints `wrote ... (N packages, M elements: ...)` unless `--quiet` — `757-766`.
- Payload assembly: `{schema, generated_by, source, units, notes, index_data_included, counts, meshes}` — `702-711`.
- Keys sorted; elements source order; floats unrounded; no timestamps; two runs byte-identical — `18-19`, `664-667`.
- Default mode omits convex `index_data`/`index_count`; `index_data_included: false` — `78-83`, `373-375`; `--with-index-data` emits both — `300-315` test, `537-552` test.
- Fail-closed on missing dump tree, malformed BodySetup, unknown `AggGeom` key, unknown element field, unknown `CollisionTraceFlag` — `121-126`, `330-335`, `401-410`, `431-434`.
- Element vocabulary closed: `BoxElems`, `SphereElems`, `SphylElems`, `ConvexElems`, `TaperedCapsuleElems` — `113-119`.

### 3.3 Allowlist / audit wiring

`tools/consumer_allowlist.json:169-175`:

```json
{
  "glob": "mesh_collision.json",
  "kind": "blocked_on_team",
  "owner": "T09",
  "reason": "AggGeom simple-collision primitives per mesh. T09-GEOMETRY owns collision creation in the loader; T11 needs the hulls for nav.",
  "optional": true
}
```

Also:
- `tools/manifest_audit.py:187-191` registers producer `tools/parse_collision.py` → `gen:mesh_collision.json`.
- `tools/manifest_audit.py:423-427` registers content group `mesh_collision` with inputs `extracted:json` and output `gen:mesh_collision.json`.
- `tools/audit_baseline.json:186-198` records the producer command, output byte count 17,626,566, and sha256 `2a6f9515…`.
- `Makefile:44` includes `parse_collision` in the normalize target list.

### 3.4 Producer tests

`tools/test_parse_collision.py` (stdlib only):

- Pins the exact real-data counts in `MEASURED_COUNTS` — `27-48` (identical to the file's `counts` above).
- Real run over `extracted/` asserts `counts == MEASURED_COUNTS`, `index_data_included == false`, sorted mesh keys, body slice invariant, flat vertices — `399-445`.
- Asserts the `SM_CanA` box record (`body_setup`, profile, object type, responses) — `447-457`.
- Asserts `SM_PillarBasementA_12m` sphyl radius/length exactly — `511-520`.
- Asserts `SM_StreetLrgA` trace flag → `complex_as_simple is True` — `522-535`.
- Fixture tests cover all four element types, `--with-index-data`, empty `AggGeom` counted, unknown key failure, and deterministic byte-identical output — `239-397`, `537-593`.

### 3.5 Runtime tests/probes that assert collision shape counts/types

No test reads `mesh_collision.json`. Existing tests exercise the render-mesh heuristic:

| test | assertion |
|---|---|
| `game/tests/probe_door_aperture.gd:13-24` | both door-frame meshes must return `ConcavePolygonShape3D`; prints `DOOR_APERTURE PROBE PASS/FAIL` |
| `game/tests/test_stair_walk.gd:137-141` | each stair flight must return `ConcavePolygonShape3D`; walks the real collider |
| `game/tests/test_roof_collision.gd:184-219` | convex-policy roofs must return `ConvexPolygonShape3D` with offset `ZERO` and >8 points; box-policy roofs must return `BoxShape3D` |
| `game/tests/test_roof_collision.gd:286-309` | EndA/EndB shells are `convex` and `ConvexPolygonShape3D` |
| `game/tests/test_roof_collision.gd:250-281` | no roof or stair mesh may qualify as an occluder; walls still do |
| `game/tests/run_tests.gd:3961-3963` | `_add_den_window_split()` adds exactly 4 collision shapes |
| `game/tests/run_tests.gd:400-417` | Guildhall `LandscapeCollision_12` is a `ConcavePolygonShape3D` with 63 x 63 m span |
| `game/tests/run_tests.gd:461-505` | Guildhall `collision_bodies >= 4`, `collision_shapes > 0`, `collision_shapes < 32000`, occluders > 0 |
| `game/tests/run_tests.gd:509-518` | census `collision_shapes > 0` |
| `game/tests/test_perf_structural.gd:248-249,280-282` | merged cells keep 2 collision shapes / 1 body (and 2 shapes for multi-material) |
| `game/tests/test_review_baker.gd:125` | review bake reports exactly 1 collision body |
| `game/tests/probe_ftue.gd:28,37` | prints FTUE `collision_shapes` |
| `game/tests/probe_geometry_placement.gd:492` | prints map `missing_mesh_count` and `collision_shapes` |
| `game/tests/probe_perf_census.gd:46` | prints census `collision_bodies` / `collision_shapes` |

### 3.6 Docs claims vs current code (factual discrepancy)

- `docs/FIDELITY_GAPS.md:29-30` says: “the authored `AggGeom` is extracted (8,601 elements) and is the collision source instead of render-AABB heuristics.”
- `docs/reports/re-audit-20261124.md:178-180` says the 8,382 authored primitives are “read by nothing”, and `:572-575` describes the proposed producer as “consumed by `_get_mesh_and_shape()` with the heuristics as a counted fallback.”
- `docs/reports/remediation-20261125/T01-pipeline.md:53` marks P3 “**FIXED** (consumer `BLOCKED-ON T09`, data for T11)”; `:530` lists T09 as owner of “`mesh_collision.json` reader (simple collision creation in the loader)”.
- At HEAD `c2a1cd8`, `game/src/core/level_loader.gd` has **no** reference to `mesh_collision` / `AggGeom` / `CollisionTraceFlag`; `_get_mesh_and_shape()` still builds shapes from the render mesh (§1). The docs line `FIDELITY_GAPS.md:30` therefore does not match the checked-out code.

Also note the re-audit's element split at `docs/reports/re-audit-20261124.md:178-179` (“2,334 box, 81 capsule, 45 sphere”) does not match the shipped file's exact `counts` (295 sphyl, 50 sphere, 5,922 convex, 8,601 total; 8,382 BodySetup-only).

---

## Appendix A — exact 0.45 gate and branch lines

```text
game/src/core/level_loader.gd
1880    var aabb := m.get_aabb()
1881    var sz := aabb.size
1882    if not is_nonblocking and sz.length() > 0.45:
1883        if is_door_aperture:
1884            out["shape"] = m.create_trimesh_shape()
1885            out["shape_offset"] = Vector3.ZERO
1886        elif is_roof_surface and sz.length() < 12.0:
1887            ...
1891            out["shape"] = m.create_convex_shape()
1892            out["shape_offset"] = Vector3.ZERO
1893        elif sz.length() < 12.0 and not is_stair_run and not is_walk_surface:
1894            var bx := BoxShape3D.new()
1895            bx.size = Vector3(maxf(sz.x, 0.1), maxf(sz.y, 0.1), maxf(sz.z, 0.1))
1896            out["shape"] = bx
1897            out["shape_offset"] = aabb.get_center()
1898        else:
1899            out["shape"] = m.create_trimesh_shape()
1900            out["shape_offset"] = Vector3.ZERO
```

## Appendix B — JSON path cheat sheet

```text
collision_key_for_placed_mesh = level_json.meshes[i].mesh          # e.g. /Game/Art/.../SM_Wall
elements_for_key             = mesh_collision.meshes[collision_key_for_placed_mesh].elements
body_slice                   = elements[ body_setups[i].element_start : body_setups[i].element_start + body_setups[i].element_count ]
shape_type                   = elements[j].type                    # box | sphere | sphyl | convex
box_center_halfextent_rot    = elements[j].center / half_extent / rotation{pitch,yaw,roll}
convex_points                = elements[j].vertices_flat            # flat [x,y,z,...]; vertex_count = len/3
convex_transform             = elements[j].transform {rotation{X,Y,Z,W}, translation[x,y,z], scale3d[x,y,z]}
```
