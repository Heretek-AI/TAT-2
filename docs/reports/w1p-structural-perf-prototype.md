# W1p — structural perf prototype (census, PeripheryA range, cell merge)

Status: **prototype, off by default**. No FPS claim: the integrator measures on
the GPU harness. Everything here is headless-verified only.

## Why

Guildhall at 1080p/high is ~37 FPS: ~13 ms resolution-independent + ~14 ms
pixel. `Guildhall_PeripheryA` carries ~5,940 potential surface draws (53 % of
the map), ~2,336 plain `MeshInstance3D`, 160 lights and 6 hero shadows. The
quality ladder was invalid, so this wave builds the structural levers behind
env flags and a census that measures what the loader actually emits.

## What changed

- `game/src/core/level_loader.gd`
  - Every draw item built by `_make_draw_items`/`_build_one_draw_item` now
    carries `source_sublevel`, `source_sublevels[]` and per-source
    `source_counts{}`; the node gets the same metadata.
  - `PERF_CENSUS` prints once per Guildhall load (or any load with
    `TAT2_PERF_CENSUS=1`): meshes, instances, chunk nodes, plain
    `MeshInstance3D`, `MultiMeshInstance3D`, approximate surface draws, lights,
    shadow-casting lights, occluders, collision bodies/shapes, PeripheryA
    columns and per-sublevel instance totals.
  - `TAT2_PERIPH_RANGE=100|120|150` sets `visibility_range_end` on pure
    PeripheryA chunks only (fade disabled, +16 m cell-centre pad). SkyboxGeo,
    interior sublevels and mixed-source batches are skipped and counted.
  - `TAT2_SHADOW_HEROES` / `TAT2_LIGHT_BUDGET` are read by
    `MobileProfile.hero_shadows()` and the loader budget; defaults stay 6/160.
  - `TAT2_MERGE_CELLS=plain` folds eligible single-instance plain meshes per
    32 m cell into one `ArrayMesh` (one surface per material) and one
    `MeshInstance3D` with a tight `custom_aabb`. Collision/occluders are still
    emitted per original item. Any unsupported surface rejects its cell; the
    originals stay visible.
- `game/src/core/mobile_profile.gd` — env override parsing, defaults unchanged.
- `game/tests/test_perf_structural.gd` — focused headless test:
  real PeripheryA draw items tagged, range only on PeripheryA, light/shadow
  override counts, one-material and two-material synthetic merges with
  collision preserved, transparent fail-closed case.
- `game/tests/run_tests.gd` — 11b asserts the Guildhall census/source metadata.
- `game/tests/probe_perf_census.gd` — headless full-Guildhall probe for the
  counts below.

## Merge eligibility (fail closed)

Only when all of these hold:

- one instance (`trs.size() == 1`), no CPD, not hidden, not a far/skybox item;
- every surface is `StandardMaterial3D` with transparency disabled, blend
  `MIX`, emission off (a `ShaderMaterial` needs an explicit opaque-shader
  allowlist, currently empty), no bones/weights/custom channels, triangles;
- material identity is exact, so a merged surface keeps its own material and
  authored surface order is first-seen order;
- culling policy is "structural/default" (shadow on, no distance fade), so the
  cell node cannot change a per-source fade/shadow decision;
- the UE path is not gameplay-addressed: door/gate/loot/chest/device/landmark/
  interactable/spawner/marker/portal/switch/lever and the known mission meshes
  (sign, ThievesDen map, car lenses, grenade/truncheon) are excluded.

## Evidence

### Headless focused test

`tools/godot --headless --path game --script res://tests/test_perf_structural.gd`

```
PASS: Guildhall PeripheryA draw items carry source_sublevel (3105 items, missing=0 wrong=0)
PASS: PERIPH_RANGE=100 sets PeripheryA range 116.0 with fade disabled
PASS: range stays off for interior, SkyboxGeo and mixed batches
PASS: range counters applied=1 skipped_mixed=1
PASS: TAT2_SHADOW_HEROES=2 / TAT2_LIGHT_BUDGET=64 select 64 lights with 2 hero shadows
PASS: defaults restore hero_shadows=6 and light_budget=160
PERF_MERGE mode=plain candidates=2 cells=1 nodes=1 surfaces_before=2 surfaces_after=1 skipped=2 reasons={  }
PASS: plain merge: one node, one surface, 48 verts, tight AABB over both boxes (total=2 surfaces=1 verts=48)
PASS: plain merge keeps collision (bodies=1 shapes=2)
PASS: plain merge accounting candidates=2 cells=1 surfaces 2->1
PERF_MERGE mode=plain candidates=2 cells=1 nodes=1 surfaces_before=4 surfaces_after=2 skipped=2 reasons={  }
PASS: multi-material merge: one node, two surfaces, authored material order preserved
PASS: multi-material accounting surfaces 4->2, collision shapes=2
PERF_MERGE mode=plain candidates=0 cells=0 nodes=0 surfaces_before=0 surfaces_after=0 skipped=0 reasons={ "transparent": 2 }
PASS: transparent surfaces fail closed (candidates=0 reason=transparent, both originals kept)
PERF_STRUCTURAL_SUMMARY: fails=0
```

### Full-Guildhall headless census (default, all levers off)

Command: `tools/godot --headless --path game --script res://tests/probe_perf_census.gd`
(contract 4 load, 2026-11-24, 16.4 s headless build):

```
PERF_CENSUS meshes=5782 instances=64547 chunk_nodes=5735 plain=2271 multimesh=3511
surface_draws=10642 lights=171 shadow_lights=7 occluders=768
collision_bodies=225 collision_shapes=24311
periph_nodes=3104 periph_instances=13325 periph_surface_draws=5945
periph_plain=1439 periph_multimesh=1665 periph_range=0 merge_mode=off
merge_candidates=0 merge_nodes=0 merge_surfaces_before=0 merge_surfaces_after=0
light_budget=160 hero_shadows=6
source_sublevels={ Building_Guildhall_POI: 9771, Guildhall_PeripheryA: 12251,
  Guildhall_SkyboxGeo: 33547, Guildhall_Geometry: 567, Building_Guildhall_POI_3rdFloor: 3613,
  Guildhall_Vault_CeremonialChambers: 743, Guildhall_Gameplay: 1361, Guildhall_P: 80,
  Guildhall_LightingNoGameplay: 172, Guildhall_Loot: 143, Guildhall_Landscape: 675,
  Guildhall_Contract_04: 1, Guildhall_Contract_Teleporters: 2 }
```

PeripheryA's measured share is 5,945 of 10,642 surface draws (55.9 %), 13,325
of 64,547 instances, 3,104 draw nodes (1,439 plain + 1,665 MultiMesh).

### Full-Guildhall merge probe (`TAT2_MERGE_CELLS=plain`)

Command: `TAT2_MERGE_CELLS=plain tools/godot --headless --path game --script res://tests/probe_perf_census.gd`

```
PERF_MERGE mode=plain candidates=639 cells=47 nodes=47 surfaces_before=1370 surfaces_after=722 skipped=637 reasons={ "not_plain": 3421, "culling_small": 654, "culling_tiny": 251, "emission": 180, "gameplay_addressed": 179, "transparent": 127, "culling_clutter": 110, "degenerate_transform": 87, "cpd": 67, "shader_not_allowlisted": 36, "hidden": 8, "single_cell": 2, "far": 1 }
PERF_CENSUS meshes=5192 instances=63957 chunk_nodes=5145 plain=1681 multimesh=3511
surface_draws=9994 lights=171 shadow_lights=7 occluders=768
collision_bodies=225 collision_shapes=24311
periph_nodes=2705 periph_instances=12926 periph_surface_draws=5625
periph_plain=1040 periph_multimesh=1665 periph_range=0 merge_mode=plain
merge_candidates=639 merge_nodes=47 merge_surfaces_before=1370 merge_surfaces_after=722
light_budget=160 hero_shadows=6
```

Delta: surface draws 10,642 -> 9,994 (-648, -6.1 %); plain
`MeshInstance3D` 2,271 -> 1,681 (-590); draw nodes 5,735 -> 5,145 (-590).
Collision bodies/shapes (225/24,311) and occluders (768) are unchanged, which
is the "collision/occluders untouched" proof. This is a draw-count reduction,
not an FPS claim.

### Full-Guildhall PeripheryA range probe (`TAT2_PERIPH_RANGE=100`)

```
PERF_PERIPH_RANGE requested=100 applied=1462 kept_smaller=1540 skipped_mixed=102 skipped_other=2631 pad=16.0
```

Of 3,104 PeripheryA draw nodes, 1,462 took the 116 m end (the +16 m cell-centre
pad), 1,540 already had a shorter prop fade and kept it, and 102 pure
PeripheryA-adjacent chunks were mixed with interior sources and were skipped.
2,631 non-PeripheryA draw items were untouched. This is the cheapest HLOD test:
it removes step-in draws only; colliders remain, and popping is unverified
because no GPU capture was run.



## Gates

- compile: 71 checked, 0 broken (new test + probe included)
- `make test`: `SUMMARY: fails=0` (suite 11b asserts the Guildhall census and
  source metadata; 11b measured 5,737 source-tagged draw nodes with 0 missing)
- M2: `M2_SUMMARY: fails=0`
- door walk: `DOORWALK PASS`
- viewmodel truth: `VIEWMODEL_TRUTH PASS`
- Niagara: `NIAGARA_PROBE PASS` (107 files, 3,695 authored, 3,308 active)
- `make audit`: exit 0 (`AUDIT PASS`, baseline matches; this worktree symlinked
  the ignored `tools/bin/vgmstream` from the main checkout for the tool-version
  gate)
- E2E: `SUMMARY: fails=0 passed=264 total=264`
  (`run_e2e_tests.gd`, full tier 1-4; 3 scene-Instance RIDs warn at exit as on
  the existing baseline, no FAIL/Script error)

## Risks / unknowns

- **No FPS measurement.** The census counts draw nodes/surfaces, not GPU time.
  Surface draws can fall while vertex/index work or one large cell AABB rises.
- **Merged cells lose per-item frustum culling granularity.** One cell AABB is
  tighter than a global batch but coarser than per-item nodes; a cell spanning
  a long block may stay visible longer. `custom_aabb` is exact for the merged
  geometry, so only the cell granularity changes.
- **Mixed-source batches are not faded.** PeripheryA shares mesh paths with the
  POI; per-cell mixed batches are skipped for the range lever (counted in
  `PERF_PERIPH_RANGE skipped_mixed`). This is fail-safe, not maximal coverage.
- **PeripheryA collision is unchanged** by the range lever: colliders still
  exist beyond the cull distance, so gameplay can reach geometry that is not
  drawn. This prototype is a draw-distance test, not a streaming/LOD solution.
- **Merge only handles plain single instances**; MultiMesh chunks are not
  merged, and shader materials are currently all excluded.
- **Merged `ue_mesh` identity is a cell id.** Gameplay lookups by individual
  mesh path are excluded by token, but a future consumer that walks
  `ue_mesh` must understand `MERGED_CELL_*`.
- **Per-source metadata is per draw item**, deduped across sublevels: a
  duplicate instance is owned by the first sublevel that produced it.
- `visibility_range_end` is measured from the chunk AABB centre; the +16 m
  pad only reduces edge popping, it does not make the cull plane exact.
