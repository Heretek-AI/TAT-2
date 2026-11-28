# T09-GEOMETRY — world geometry, placement & meshing remediation

Worktree: `<worktree>/T09-geometry`, branch `rem/T09-geometry`.
Base: `fb93f84` (W7 merged tree + docs). **Local commits only — not pushed, not merged.**

Scope owned and touched: the geometry/placement functions of
`game/src/core/level_loader.gd`, `tools/parse_tables.py::extract_levels()` (the
level/placement producer — `tools/parse_levels.py` / `tools/parse_placement.py`
named in the plan do not exist; `extract_levels()` **is** the level/placement
pair, and T01's committed work does not touch this file), the movement half of
`tools/parse_tables.py`'s consumer contract, `game/src/player/thief_character.gd`
mantle section, `game/tests/`, and this report.

Not touched (other lanes): `mission_controller.gd` (T10/T02), `hud.gd` (T05),
`guard_ai.gd` (T11), env/light/weather functions (T07), material binding (T08),
VFX (T12), `tools/tat-extract/**`, every other `tools/parse_*.py`.

**Regeneration boundary.** `game/data/generated/` is a read-only symlink to the
main checkout, so this lane may not and did not write it. Findings that need new
payload fields are delivered as producer + consumer **together**, proved by
driving the real producer into `/tmp` and the real consumer against that output
(`TAT2_LEVELS_DIR=/tmp/t09_proof/out/levels`). The integrator's single
`python3 tools/parse_tables.py` makes them live. Every such finding says so.

New/changed artefacts:

| file | change |
|---|---|
| `tools/parse_tables.py` | `extract_levels()`: `spline` payload for `SplineMeshComponent`, LevelInstance key normalisation (was `/Game/Maps/`-only), `streaming_levels` graph, marker parent-transform fallback, spline/streaming/marker/level-instance summary prints |
| `tools/test_parse_level_splines.py` (new) | 10 stdlib unit tests for the two new conversion helpers |
| `game/src/core/level_loader.gd` | spline loft (`normalize_spline`, `spline_point`, `spline_tangent`, `spline_frame`, `spline_deform_mesh`, `_get_spline_mesh`, `spline_shape_for`), authored streaming-graph resolver, LevelInstance double-load guard, `MESH_RECON` accounting, origin door-marker refusal |
| `game/src/player/thief_character.gd` | mantle movement duration follows the authored clip (RE-F-16) |
| `game/tests/probe_geometry_placement.gd` (new) | before/after counter probe (no map load by default; `--load-map` for the behavioural section) |
| `game/tests/run_tests.gd` | suite 91 (T09 geometry/placement contract) |
| `game/tests/e2e/e2e_tier1_features.gd` | T1-10-D advanced to the authored mantle clip length |

---

## RE-B-04 — `SplineMeshComponent.SplineParams` is never read (489 components → 1,080 stacked duplicates)

- **severity:** P1
- **S1 investigate:** `tools/parse_tables.py:1931` handles
  `et in ("StaticMeshComponent", "SplineMeshComponent")` in one branch: it reads
  `RelativeLocation/Rotation/Scale3D` + `AttachParent` and **never**
  `SplineParams`. 361 of the spline exports carry no `RelativeLocation` at all,
  so each piece resolves to its parent-root transform and the loader's
  exact-duplicate guard (`level_loader.gd:2606` pre-fix) drops the copies.
- **S2 research (authored truth):** the params **are** in the dump —
  `Properties.SplineParams` = `{StartPos, StartTangent, StartScale(2D),
  StartRoll, StartOffset(2D), EndPos, EndTangent, EndScale, EndRoll,
  EndOffset}`, UE component-local centimetres and radians. Example
  (`extracted/json/Maps/Guildhall/Guildhall_Landscape.json`,
  `SplineMeshComponent_0`):
  `StartPos (-134.47995, -178.81181, 4.4e-06)`, `StartTangent (240.46698,
  395.16928, -1.15e-05)`, `StartScale (0.7330429, 0.7330429)`,
  `StartOffset (-3.3904352, -7.9e-09)`. UE builds the piece by lofting the mesh's
  local X axis across the cubic Hermite spline (`USplineMeshComponent`), stamping
  the cross-section (local Y = height, local Z = width) with the lerped 2D
  scale/offset and roll. Re-counted: **469** spline components carry a real
  `StaticMesh`; **20** are `SplineEditorMesh` (landscape-spline editor visuals,
  already skipped). The lane's 489 mixes both.
- **S3 confirm (red):**
  ```
  tools/godot --headless --path game --script res://tests/probe_geometry_placement.gd
  GEOM_PROBE splines authored_records=0 files=0 rigid_dupes_of_spline_families=216
    spline_family SM_OldManor_GardenWall_Fence_6x4 records=89 distinct=25 collapsed=64
    spline_family SM_MonorailTrack records=54 distinct=1 collapsed=53
    spline_family SM_OldManor_Railing_2 records=256 distinct=205 collapsed=51
    spline_family SM_Chain_2m records=153 distinct=124 collapsed=29
    spline_family SM_OldManor_DrivewayA_x6 records=91 distinct=72 collapsed=19
  FAIL: RE-B-04 payload carries SplineParams records=0
  FAIL: RE-B-04 spline loft endpoints p0=(0.0, 0.0, 0.0) mid=(0.0, 0.0, 0.0) p1=(0.0, 0.0, 0.0)
  ```
  `SM_MonorailTrack`: 54 authored pieces at **one** distinct position.
- **S4 fix:**
  - producer `ue_spline_params_to_godot()` → `"spline": {p0,t0,p1,t1 (Godot
    local metres, UE (x,z,y)×0.01), scale0/scale1 [width, height],
    offset0/offset1 (Godot Y from UE Offset.Y, Godot Z from UE Offset.X),
    roll0/roll1 (negated: the axis permutation has det = −1)}` on every
    `SplineMeshComponent` mesh entry with both `StartPos` and `EndPos`.
  - loader: the loft (`spline_point/spline_tangent/spline_frame/
    spline_deform_mesh`), a per-`(mesh, override variant, params)` mesh cache,
    the spline signature in the batch key so distinct lofts never share a
    MultiMesh, and a lofted trimesh collider instead of the rigid AABB.
    Rebuilt through `SurfaceTool` because the imported GLB surfaces carry a
    compressed/custom attribute format that `ArrayMesh.add_surface_from_arrays`
    rejects (measured: `ERROR: Invalid array format for surface.` for
    `SM_OldManor_DrivewayA_x6`).
- **S5 test:** `python3 tools/test_parse_level_splines.py -v` → `Ran 10 tests … OK`
  (the conversion helper against a verbatim real `SplineParams`, a synthetic
  rolled/scaled case, and the level-key normaliser). `run_tests.gd` suite 91
  91a–91d assert the loft endpoints, the bent midpoint and the cross-section
  offset on a synthetic record.
- **S6 confirm (green):**
  ```
  TAT2_LEVELS_DIR=/tmp/t09_proof/out/levels tools/godot --headless --path game \
      --script res://tests/probe_geometry_placement.gd
  PASS: RE-B-04 payload carries SplineParams records=432
  PASS: RE-B-04 spline loft endpoints p0=(-2.0, 0.0, 0.0) mid=(0.0, 0.5, 0.0) p1=(2.0, 1.0, 0.0)
  GEOM_PROBE real_spline mesh=SM_OldManor_DrivewayA_x6 chord=6.00m loft_reaches_p0=true p1=true rigid_reaches_p1=false
  PASS: RE-B-04 real authored spline lofted
  GEOM_PROBE spline_map meshes=772 spline_records=29 spline_instances=40 nodes=22 missing=0 shapes=547 ok=true
  PASS: RE-B-04 spline pieces keep their own placement
  GEOM_PROBE checks=10 fails=0 pending_regeneration=0
  ```
  (`spline_map` = the real `Guildhall_Vault_CeremonialChambers` regeneration
  payload loaded through `load_sublevels`: 29 authored spline records, 40
  instances of those mesh paths, 22 draw nodes, 0 missing meshes, 547 colliders.)
  Producer run (real `extract_levels()` into `/tmp/t09_proof/out`):
  `Spline meshes: emitted=432 rigid_no_params=37`; whole-payload exact
  duplicates **1,049 → 747**; `OldManor_Geo` duplicates **126 → 0**
  (fence 63, railing 48, driveway 15).
- **verdict:** **FIXED** (producer + consumer). Runtime effect requires the
  integrator's `python3 tools/parse_tables.py`; the probe reports the payload
  half as `PENDING_REGENERATION`, never as a pass.
- **residual:** 37 spline components have `SplineParams` without `StartPos`
  (13 OldManor_Geo, 9 PeripheryA, 11 Vault, 3 POI, 1 SkyboxGeo) and stay rigid —
  they are authored with no spline, not dropped silently, and are counted by
  `Spline meshes: … rigid_no_params=37`.

## RE-B-02 — LevelInstance references outside `/Game/Maps/` silently dropped (52 actors)

- **severity:** P1
- **S1 investigate:** `tools/parse_tables.py:2864-2870` — `prefix =
  "/Game/Maps/"`, `if not rel_asset.startswith(prefix): continue`, with **no**
  counter increment.
- **S2 research:** 190 authored `LevelInstance` actors; the dropped 52 are
  37×`FacadeB` + 9×`FacadeA` under
  `Art/Environment/City/Facades/Level_Instances/` and 5×`ApartmentE` under
  `Developers/gjasp/Maps/Apartments/`. `rel_key` for those dumps is built from
  the path below `Content/` (`Art/…`, `Developers/…`), so a `/Game/`-prefix
  normaliser is the correct match — the payloads already exist (FacadeB 50,
  FacadeA 28, ApartmentE 54 meshes).
- **S3 confirm (red):** producer baseline run:
  `Level instances: 138 loaded (32036 meshes), 0 unresolved` — the `0` is the
  bug (unresolved was never incremented on this path).
- **S4 fix:** `_level_asset_rel_key()` normalises both `/Game/Maps/<rel>` and
  `/Game/<rel>`; self-reference, empty and non-`/Game/` paths return `None` and
  **every** skip increments `total_level_instances_unresolved`.
- **S5/S6 confirm (green):** patched producer run:
  `Level instances: actors=190 merged=190 meshes=34436 unresolved=0`.
  Mesh instances **134,768 → 137,168** (+2,400 = 2,102 + 270 + 28 exactly):
  `ThievesDenTest_Periphery 100 → 2,202`, `FTUE_Geometry 34,201 → 34,471`,
  `ThievesDenTest_P 60 → 88`. A structural diff of all 107 payloads shows 21
  changed files, all explained by these three gains plus the spline/marker keys;
  no other field drifts.
- **verdict:** **FIXED** (producer). Requires regeneration.

## RE-B-03 — `FTUE_Building_JewelryStore` loaded twice (1,693 duplicate meshes ~220 m off)

- **severity:** P1
- **S1 investigate:** the producer correctly merges the level once
  (1,693 meshes tagged `level_instance: FTUE/FTUE_Geometry.json::LevelInstance_35`
  at the authored instance transform); the port additionally loads it
  standalone from the hardcoded FTUE list (`game_data.gd:377-390`), at the
  level's own origin `(4.4, 9.32, −30.0)`. `mesh_dedupe` cannot collapse them —
  the transforms differ, so `(pos, mesh)` sets have **0** overlap.
- **S2 research:** `FTUE_P` streams 8 sublevels; `FTUE_Building_JewelryStore` is
  **not** one of them (RE-O-03). The LevelInstance is the only authored placement.
  Measured: standalone payload 1,693 meshes; `FTUE_Geometry` lists
  `"level_instances": ["FTUE/FTUE_Building_JewelryStore", …]`.
- **S3 confirm (red):**
  ```
  GEOM_PROBE ftue_jewelry_store merged=true standalone_listed=true standalone_meshes=1693
  ```
  i.e. the same level is a merge target **and** a list entry.
- **S4 fix (consumer only, no list edit):** `_prescan_merged_sublevels()` reads
  the supplied payloads' `level_instances` and `_parse_sublevels_with_graph()`
  skips a supplied sublevel that another supplied payload already merged
  (`sublevels_skipped_merged`), before any geometry is built. This keeps
  `game_data.gd`/`mission_controller.gd` untouched (other lanes) and fixes the
  class, not the instance: any future list that names a merged level is safe.
- **S5/S6 confirm (green):** probe PASS
  `RE-B-03 double-load detected and skippable merged=true standalone=true
  standalone_meshes=1693`; suite 91 91g asserts
  `_prescan_merged_sublevels(["FTUE_Geometry"])` contains
  `FTUE/FTUE_Building_JewelryStore`. Effect on the FTUE load: −1,693 meshes,
  −1,693 draw instances, no z-fighting.
- **verdict:** **FIXED** (consumer). No regeneration needed.

## RE-B-01 — the authored `LevelStreamingAlwaysLoaded` graph is discarded

- **severity:** P1
- **S1 investigate:** `rg "LevelStreaming" game/src/` → no match before this
  change. `tools/parse_tables.py:242-268` reads only the `LevelTransform` of the
  same entries; `tools/parse_quests.py:1004` reads the graph for quest
  availability only. World loading is the hardcoded
  `mission_controller.gd:894-948` list.
- **S2 research:** shipped `LevelStreamingAlwaysLoaded`/`Dynamic` per persistent
  map: Guildhall_P 16+12, OldManor_P 11+9, FTUE_P 8+1, ThievesDenTest_P 5+1,
  MissionLobby_P 2+0, `Menus/MainMenu` 2+0 = **67 records over 6 maps**.
  `OldManor_PathBlockers` (156 meshes / 38 actors) and
  `ThievesDenTest_Contracts` (17 meshes + 1 rect light + 2 Niagara) are
  always-loaded and carry visible geometry; `Guildhall_Sequencer` is dynamic and
  genuinely empty.
- **S3 confirm (red):** probe on the committed payload
  `GEOM_PROBE streaming always_loaded total=0` — the payload has no graph field
  at all, and `PENDING_REGENERATION: RE-B-01 graph counts always-loaded
  entries=0`.
- **S4 fix:**
  - producer emits `streaming_levels: [{level, type}]` on every payload
    (`always`/`dynamic`, keys via the same `_level_asset_rel_key`
    normalisation; unresolved entries counted).
  - loader `_resolve_authored_streaming()` adds only `always` entries that are
    (a) not already supplied, (b) not already merged as a LevelInstance,
    (c) present on disk; `_parse_sublevels_with_graph()` runs the same path for
    the sync and async loaders, and the counts are exported
    (`sublevels_from_graph`, `sublevels_skipped_merged`,
    `sublevels_graph_missing`).
- **S5/S6 confirm (green):**
  ```
  Producer: Streaming levels: maps=6 records=67 unresolved=0
  Probe:    PASS: RE-B-01 authored always-loaded graph consumed added=2
            ["…/OldManor/OldManor_PathBlockers.tatlevel.json",
             "…/ThievesDenTest/ThievesDenTest_Contracts.tatlevel.json"]
  End-to-end load (Den payload only supplied; the loader adds the rest):
    MESH_RECON authored=338 applied=332 duplicate=5 ... from_graph=5 graph_missing=0
    GEOM_PROBE graph_map payload_streaming=6 from_graph=5 graph_missing=0 meshes=332
    PASS: RE-B-01 loader pulls the authored always-loaded set
  ```
  The Den's authored 5 always-loaded sublevels (`Contracts`, `ThievesDen_Audio`,
  `Periphery`, `LoadoutCapture`, `ThievesDen_Geo`) are pulled from the graph
  alone, and the define-side `+17` contract/journal meshes are in the 332.
  Suite 91 91f also asserts a **dynamic** level is never added and that an
  already-supplied level is not duplicated.
- **verdict:** **FIXED** (producer + consumer). Requires regeneration.
- **deliberate non-consumption:** `Guildhall_Sequencer` (dynamic, 0 meshes) and
  the 5 audio sublevels are *not* forced in by geometry code. The graph now makes
  them a one-line decision for T03/T10 instead of an invisible omission; the
  loader adds them when the graph lists them as always-loaded (they contribute
  0 meshes today, so this is free).

## RE-P-05 — 309 authored markers stored at the world origin (`door_spawns` is a live trap)

- **severity:** P1 (as a trap) / P3 (inert today)
- **S1 investigate:** the marker loop wrote `pos` from the component's own
  `RelativeLocation`; with no `RootComponent` and no relative TRS the world
  matrix was the identity, so 309 of 4,516 records landed at exactly `(0,0,0)`.
  `level_loader.gd` funnels every `"Door" in class` marker into
  `result["door_spawns"]`.
- **S2 research:** those components' transforms live on `AttachParent` or on the
  owning actor's root (`SwingingDoorNavLinkComponent` 144,
  `TATSwingingDoorPivotComponent` 144, `TATCupboardDoorComponent` 15,
  `TATSecretDoorNavLinkComponent` 4, `Guildhall_Loot_C` 2).
- **S3 confirm (red):** probe over the 15 loaded Guildhall sublevels:
  `GEOM_PROBE origin_markers door_markers=67 at_origin=45`; corpus-wide the lane
  measured 309/4,516.
- **S4 fix:**
  - producer: when a marker export has no `RootComponent`, compose its **own**
    world matrix (`get_world_mat(idx)`, walking `AttachParent`), then the owning
    actor's root, and apply the sublevel `LevelTransform` exactly as the mesh
    branch does. Genuinely origin-authored records are left alone.
  - loader (defence in depth): a door marker at exactly `Vector3.ZERO` is refused
    and counted in `origin_markers_skipped`.
- **S5/S6 confirm (green):** producer run
  `Marker transforms: origin_fixed=586`; origin records **309 → 2** (307 fixed;
  the 2 survivors are `Guildhall_Loot_C` with no transform anywhere in the dump,
  left at the origin as authored). Loaded proof on the **committed** payload
  (`Guildhall_Geometry`, 8 of its 9 door markers authored at the origin):
  ```
  MESH_RECON authored=571 applied=567 duplicate=0 name_skipped=1 wardbox=0 moonshape=3 clamp=0 clamp_worst=1.00x mirrored=61 origin_markers_skipped=8 skipped_merged=0 from_graph=0 graph_missing=0
  GEOM_PROBE origin_guard geometry: door_spawns=1 at_origin=0 skipped=8 payload_origin=8 recon=true
  PASS: RE-P-05 origin door markers refused skipped=8 payload_origin=8 at_origin_spawned=0
  ```
- **verdict:** **FIXED** (producer) + defended at the consumer. Requires
  regeneration for the 307; the consumer guard is live now.
- **open risk:** the producer move also shifts **291** markers that had been
  collapsed onto a non-zero `LevelTransform` origin (e.g.
  `Building_Guildhall_POI` at `[10, 21.5, −28]`). Any consumer that had learnt
  the wrong position will move; no runtime consumer reads `door_spawns` today,
  and `scene_element_spawns` (the door/guard/loot SceneElement index) now carries
  the corrected positions.

## RE-P-08 / RE-P-09 / RE-P-10 — silent mirror, duplicate and scale-clamp rewrites

- **severity:** P1 (reporting) / P2 (mirror winding, unverified)
- **S1 investigate:** `_dict_to_transform` (`level_loader.gd:5494-5516`) clamped
  every axis to `[0.05, 40]` with no counter; the dedupe
  (`:2606`) counted `duplicate_meshes` but nothing printed it; a
  negative-determinant basis got no diagnostic at all.
- **S2 research:** `tools/parse_tables.py:96-160` writes positive column norms as
  `scale` and folds a reflection into the basis; Godot keeps the mirror in the
  instance transform.
- **S3 confirm (red):** re-derived independently in the probe from the flat
  basis/scale payload of the 15 loaded Guildhall sublevels: **265** records
  outside `[0.05, 40]`, **2,629** mirrored (`det < 0`), **210** exact-duplicate
  surplus records on a `(mesh, pos, basis, scale)` key. No counter existed, no
  run log could show any of them.
- **S4 fix:** `_scale_clamp_count` / `_scale_clamp_worst` /
  `_mirrored_basis_count` members, reset per load, exported as
  `clamped_scales`, `scale_clamp_worst_ratio`, `mirrored_bases`, plus one
  always-on `MESH_RECON authored=… applied=… duplicate=… name_skipped=…
  wardbox=… moonshape=… clamp=… clamp_worst=… mirrored=…
  origin_markers_skipped=… skipped_merged=… from_graph=… graph_missing=…` line
  per load. `name_skipped` (392 `SM_BlockerWard_*`/`SM_FogSphere`/`SM_SkySphere`)
  and `ward_box_hidden` are now in the same line.
- **S5/S6 confirm (green):**
  ```
  GEOM_PROBE placement records=49335 clamped=136 clamp_worst=500.00x mirrored=2629 duplicate=210
  PASS: RE-P-10 scale clamp counted loader=136 payload=136
  PASS: RE-P-08 mirrored bases counted loader=2629 payload=2629
  PASS: RE-P-10 clamp worst ratio loader=500.00 payload=500.00
  ```
  The 136/265 difference is exact and explained: **129** `SM_LightBeam` cards are
  diverted to `beam_card_transform()` (`BEAM_SCALE_CEIL = 200`) before the
  `[0.05, 40]` clamp, so the probe excludes them on purpose.
- **verdict:** **PARTIAL** —
  - duplicates/clamp/mirror **are now counted and printed** (`FIXED` for the
    reporting half);
  - the clamp *values* are unchanged by design: 0.0021 m slabs degenerate the
    collider, and raising the ceiling re-opens the 40 m fog/beam budget;
  - the reflected-basis **winding consequence is NOT VERIFIED**. This lane may
    not take captures, and Godot's front-face handling for a negative
    determinant is engine behaviour, not measured here. The probe described by
    the lane (`SM_Urban_Ext_Corner_2x6` at `(463.05, 20.87, −136.84)` with
    `CULL_BACK` vs `CULL_DISABLED`) is the acceptance test.

## RE-P-07 — 183 pickups still use the blanket +0.35 m offset → **BLOCKED-ON T10**

- **severity:** P1
- **S1 investigate:** `game/src/missions/mission_controller.gd:4175-4181`
  (`_spawn_pickups`): `p.position = marker + Vector3(0, 0.35, 0)`, no raycast, no
  AABB. **That file belongs to T10/T02 in this wave and was not edited here.**
- **S2 research:** the pickup meshes' AABB bottoms are at y ≈ 0
  (`SM_BottleWineA −0.001`, `SM_BottleWineB 0.000`, `SM_Toolbox −0.000`,
  `SM_HealthPackA −0.000`, glTF POSITION accessors), so every pickup floats
  350 mm over its authored marker. The loot/civilian path right beside it is
  floor-exact (`_spawned_mesh_bottom()` + `SPAWN_GROUND_CLEARANCE = 0.03`).
- **S3 confirm (red):** counts reproduce exactly from the payloads — 133
  throwable + 45 ammo + 5 health = **183** (Guildhall); Old Manor adds
  385 + 97 + 7 and FTUE 11 + 1.
- **S4 fix (handed over, 3 lines at the owning layer):** in `_spawn_pickups`,
  after instantiating the pickup mesh, use the existing helper exactly as the
  loot path does —
  `_ground_spawn_node(node, marker + Vector3(0.0, 2.0, 0.0), Vector3(0.0, -6.0, 0.0))`
  (or `_spawned_mesh_bottom()` + `SPAWN_GROUND_CLEARANCE`), and keep the authored
  marker as the fallback with a `push_warning`, mirroring `_spawn_escape`.
- **S5/S6:** **not run** — the call site is outside this lane. Acceptance:
  after the change, a pickup's AABB bottom sits 0.03 m over the floor hit and
  the `PQ_PLACE`-style line reports `pin_y − floor_y ≈ 0.03` for pickups too.
- **verdict:** **BLOCKED-ON T10** (contract above; no data dependency).

## RE-P-15 — unlabelled invented placements → **partly BLOCKED-ON T10, partly FIXED**

- **severity:** P1
- **S1 investigate:** `mission_controller.gd:466-487` (KF17 clocktower),
  `:2003+` (PonderVista sky quad/moon/cheese), `:253/266/280/499` (Guildhall
  fill lights), `:3137-3146` (`_add_safety_floor`, a 600×600 m slab at y = −15) —
  all in T10/T02's file. `level_loader.gd:2635-2651` (procedural candle flames
  with hardcoded wick offsets) is this lane's.
- **S2 research:** AGENTS rule 7 requires TAT-2 expansion content to be
  machine-identifiable (`expansion` meta + group + runtime constant), which
  `prep_skyline` already does (`mission_prep_ui.gd:869-871`). The clocktower,
  vista, fills, safety floor and candle quads carry none.
- **S3 confirm (red):** `rg -n 'expansion' game/src/missions/mission_controller.gd`
  → only the prep-skyline handoff; the candle path has no group/meta.
- **S4 fix:** candle flames now get `set_meta("expansion", true)` +
  `add_to_group("expansion_placements")` + a `TAT2_CANDLE_FLAMES` constant naming
  the invention (see the `_note_expansion_placement` helper). The four
  `mission_controller.gd` inventions are handed over with the exact contract:
  `node.set_meta("expansion", true)`, `add_to_group("expansion_placements")`, and
  a `TAT2_<NAME>` constant in a comment; the KF17 clocktower code already carries
  a comment, so the meta+group is the whole change.
- **verdict:** **PARTIAL** — candles labelled here; clocktower / vista / fills /
  safety floor **BLOCKED-ON T10**.

## RE-F-16 — mantle movement runs 0.30 s against 0.73–2.57 s authored clips

- **severity:** P1 — **BLOCKED-ON-T09 from T04-ANIM, implemented here**
- **S1 investigate:** `thief_character.gd:1221`
  `_mantle_t = minf(1.0, _mantle_t + delta / 0.3)`; the movement curve lives in
  `_physics_process`, i.e. the movement contract this lane owns.
- **S2 research:** T04 measured the authored clip lengths from
  `anims_meta.json` — `AN_Mantle_050CM` 0.75, `_100` 1.0, `_150` 1.166667,
  `_200` 1.75, `_250` 2.25, `_300` 2.583333 s (re-read here; the 0.733–2.567
  range in the T04 report is the *legacy* `(N−1)/N` GLB duration, which T04's
  producer fix re-times to these values).
- **S3 confirm (red):** `delta / 0.3` with a 1.75 s authored clip on a 2.0 m
  ledge → the body arrives 5.8× early; at 0.75 s the old code was already at the
  top while the arms were 43 % through the reach.
- **S4 fix:** `MANTLE_MOVE_SEC_BY_BAND` (the authored lengths, plus
  `climb_to_mantle` 2.066667 and `vault` 0.9 for the two traversal roles T04
  wired) and `_mantle_move_duration(role)`, which prefers the **live**
  `AnimationPlayer` clip length of the clip the FP layer just started, then the
  table, then `MANTLE_MOVE_SEC_LEGACY` (0.3) for the headless/no-arms path. The
  movement therefore tracks the animation automatically, including after
  `make anims` re-times the GLBs.
- **S5 test:** `run_tests.gd` suite 91 91i asserts `delta / 0.3` is gone, the
  table exists, and **every band equals the `anims_meta.json` `length`** for its
  `AN_Mantle_0XXCM` clip (tolerance 10 ms). E2E `T1-10-D` now steps 45 frames
  (asserts the body is still below the ledge: < 1.8 m) and then 75 more
  (2.0 s > 1.75 s clip) before asserting `y >= 1.8`.
- **S6 confirm (green):** suite 91 PASS; E2E tier 1 PASS (see §Gate evidence).
- **verdict:** **FIXED**.
- **residual:** the mantle path is still a straight `start → end` lerp with a
  smoothstep; the authored clip's hand-plant arc (root motion) is T04's RE-F-08
  follow-up.

## RE-O-10 — `TATWorldMapBoundary` ×13 unextracted, KillZ absent, invented safety floor

- **severity:** P2
- **S1 investigate:** `grep -rn 'WorldMapBoundary|MapLabel|MapTextureAnchor|MapTool'
  tools/` → 0 hits; `grep -rl TATWorldMapBoundary game/data/generated/` → 0 files.
  The `[TAB]` map (`hud.gd:3125-3164`) is a hand-drawn schematic with a hardcoded
  title ternary. `KillZ` appears nowhere in `extracted/json/` (also
  case-insensitive), so UE's default (−10,485.75 m) was authored; the port
  substitutes `_add_safety_floor()` (`mission_controller.gd:3137-3146`).
- **S2 research (extraction contract, measured):** 13 actors in 4 maps —
  Guildhall_P 5, OldManor_P 6, FTUE_P 1, ThievesDenTest_P 1. Per actor:
  `MapLabel` (FText: `TableId`/`Key`/`SourceString`/`LocalizedString`),
  `MapMaterial` (FSoftObjectPath, 12 distinct `MI_*Map*` assets, **all 12
  textures present**), `mapTexture` (6 on Old Manor), `MapTextureAnchorTopLeft/
  BottomRight` (FVector2D), `MapType` (`Primary`/`Secondary`; each floor is its
  own actor, there is **no** `Secondary[]` array), `MapRenderTextureHeightOffset`
  (3: 7500 / −350 / 1000), `UseAutoGeneratedMapAnchors` +
  `AutoGeneratedMapAnchorTopLeft/BottomRight` (2 actors, both `false`), plus the
  root `BoxComponent` transform (**no** `RelativeRotation` on any of the 13;
  Guildhall `_0` is a 235×235 m plane at z = 67.3 m). Only **2 of 13** labels
  resolve in `tables/StringTables/*.json` (`Guildhall.MapName` → "Constables'
  Guildhall", `OldManor.MapName` → "Elway Manor"); the other 10 use GUID keys
  present only in `localization/en.csv`, and ThievesDenTest_P has no `MapLabel`
  at all.
- **S3 confirm (red):** the actors are absent from every generated file, so a
  consumer has nothing to read.
- **S4 fix:** **none in this lane.** The producer is a new `tools/parse_*.py`
  (T01's file set) that must run after `parse_tables.py`; the consumer is
  `hud.gd` (T05). The contract above is complete enough to implement without
  another survey.
- **verdict:** **BLOCKED-ON T01** (producer) **+ T05** (map UI). The invented
  safety floor is **BLOCKED-ON T10**; it must either be labelled
  `expansion_placements` or replaced by the authored kill plane (UE default
  −10,485.75 m, since no `KillZ` is serialised).

## RE-Q-02/03/11 — meshing: LOD chains, nanite density, dead UV payload

- **severity:** P2
- **S1/S2 (re-measured from the GLB binaries and the package dumps):**
  - **LOD:** 1,983 StaticMesh dumps → LOD counts `{1: 1,856, 2: 1, 3: 2, 4: 123,
    6: 1}` = **127 real chains**; 152 SkeletalMesh dumps → `{1: 22, 2: 2, 4: 128}`.
    Summed `Sections[].NumTriangles` over the 127 chains:
    **372,113 / 185,900 / 92,919 / 46,372** = 49.96 / 24.97 / 12.46 % of LOD0
    (the lane's 50.0/25.0/12.5 is rounding). Every GLB carries exactly **one**
    mesh (`{1: 2,065}`); all 2,065 `.glb.import` files say
    `meshes/generate_lods=true`, so Godot invents the chain.
  - **Nanite:** 1,657/1,983 meshes cook nanite; GLB triangles equal LOD0 on
    **1,863 / 1,864** comparable meshes (1 differs: `SM_DistortionCylinderA`
    144 vs 576; 119 dumps have no GLB). Placed Guildhall (30 `levels/Guildhall`
    payloads): **52,123 instances, 59,200,833 LOD0 tris vs 512,745,529 nanite
    input tris = 8.66×**; adding the POI/3rd-floor/Vault payloads gives
    **8.75×**. The lane's 9.1× divides a numerator from one set by a denominator
    from another (recorded as a doc correction).
  - **UV payload:** `TEXCOORD_4..7` = **139,497,792 B = 139.50 MB**, and
    **16,772/16,772** accessors are all-zero (checked against the BIN chunk, not
    min/max). All-zero UV across every channel = **216.81 MB = 40.0 %** of the
    541.76 MB GLB library (43.5 % of the 498.08 MB attribute payload).
- **S3 confirm (red):** the cost is measured, not a defect in a code path:
  `find extracted/assets -name '*.glb' | wc -l` → 2,065;
  `sum(bufferView.byteLength)` → 529.59 MB; live import `.scn` = 2,065 files /
  190.09 MB (the other 995 `.scn` / 94.71 MB are stale).
- **S4 fix:** **none.** The only real fix is a re-export
  (`tools/tat-extract/Exporter.cs`, T01) that drops the all-zero channels and,
  separately, a decision that authored LODs/nanite are a hard limit. Both are
  outside this lane and the export is not "safe and additive" from here.
- **S5/S6:** the probe reports the payload counts only; nothing in the runtime
  changed.
- **verdict:** **DEFERRED** (T01 for the re-export; nanite = documented hard
  limit). What a fix would buy: **139.50 MB (25.75 %) off the GLB library** for
  the four dead UV sets, plus 77.41 MB for the dead `TEXCOORD_1/2/3` sharing,
  i.e. up to **216.81 MB (40.0 %)**. Import-cache and GPU savings are **not
  measured** (the live `.scn` set averages 43.6 B/vertex, so the importer already
  compresses; do **not** quote 139.5 MB as VRAM).

## C-5 / RE-B-09 — the graybox floors: 15 genuine cases, not 1,622

- **severity:** P2
- **S1 investigate:** 1,637 `GB_Floor_2x2` in `Building_Guildhall_POI`
  (20,555 across 13 levels). **1,622** carry an authored `override_materials`
  list; **15** have `override_materials: null`.
- **S2 research:** the bound material for the unmaterialed 15 is
  `MI_WoodVarnishAAlignXYZ_Red` → albedo `Planks_D.png`, **no albedo tint
  serialised** (`tint: null`, no `VectorParameterValues` in the MI dump, the only
  red-ish value is `Vertex Dirt Color` with its switch **off**). Measured mean
  albedo = srgba(24.5 %, 21.5 %, 18.6 %) = **(62, 55, 47)** — a dark brown plank,
  **not grey** and **not a red varnish**. Adjudication C-5 is right that the
  visible checker is authored granite; the 15 are the only genuine gap and they
  are *not* grey.
- **S3 confirm (red):** all 15 are **outside** both authored coverage boxes
  (`poi-lounge-floor-tile` 20…52 × 24…32 × −46…−5,
  `poi-entrance-hall-floor-tile` 0…19.5 × 26…32 × −33…−19); both P0 rooms are
  fully covered (130/130 and 26/26) and of the 156 instances inside the boxes
  only 6 were rewritten by the table — the other 150 already carried authored
  overrides. A **four-box, mutually disjoint** extension was measured against
  the live payload (no pair overlaps, so the checker's overlap rule still holds):

  | box (x0,y0,z0 → x1,y1,z1) | matched | unmaterialed (= `expect_changed`) |
  |---|---:|---:|
  | `(0, 24, −70 → 25, 32, −46)` | 21 | **3** |
  | `(0, 35, −70 → 57, 36.5, −17)` | 38 | **8** |
  | `(−37, 24, −31 → −11, 32, −21)` | 3 | **3** |
  | `(0, 25, −33 → 19.5, 26, −19)` | 1 | **1** |
  | **total** | **63** | **15** |

  Because every rule is `only_unmaterialed: true`, a rule can only change an
  instance that has no authored override, so the 1,622 authored floors are
  untouched by construction. A single-axis extension is cheaper but partial:
  lounge `z_min` −46 → −70 gives matched 130 → 158 / changed 2; entrance
  `y_min` 26 → 25.5 gives 26 → 27 / changed 1.
- **S4 fix — turnkey patch, NOT committed (see verdict):** add four rules to
  `game/data/expansion/content_overrides.json` (`op: "set_material"`,
  `material: "/Game/MaterialLibrary/Environment/Tiles/MI_FloorTileA_AlignXYZ"`,
  `levels: ["Buildings/Guildhall/Building_Guildhall_POI"]`,
  `only_unmaterialed: true`, `expect_count`/`expect_changed` exactly as the table
  above). Then `python3 tools/parse_tables.py && python3
  tools/check_content_overrides.py` must report `matched/changed` equal to
  21/3, 38/8, 3/3, 1/1 and zero unmaterialed `GB_Floor_2x2` in the POI.
- **S4 fix:** **not committed** — it is a table change
  (`game/data/expansion/content_overrides.json`) plus `make normalize`, and
  `make audit` → `check_content_overrides.py` validates `expect_count` against
  the generated `content_overrides_applied.json`. Committing the table alone
  would turn `make audit` red until regeneration, which the programme's rule 1
  forbids a lane from doing. The patch is handed over below.
- **verdict:** **BLOCKED-ON regeneration** (integrator). The authored granite is
  untouched, per C-5.

---

## Team summary

| verdict | count | findings |
|---|---|---|
| **FIXED** | 8 | RE-B-04 (spline loft), RE-B-02 (LevelInstance, 138→190), RE-B-03 (FTUE double load), RE-B-01 (authored streaming graph), RE-P-05 (origin markers, 309→2), RE-P-09 (duplicate reporting), RE-F-16 (mantle duration) — plus RE-B-14's uncounted 392-instance name filter folded into `MESH_RECON` |
| **PARTIAL** | 3 | RE-P-08 (mirror counted, winding unverified), RE-P-10 (clamp counted, values deliberately kept), RE-P-15 (candle flames labelled; four `mission_controller` inventions blocked) |
| **BLOCKED-ON T10** | 2 | RE-P-07 (pickups +0.35 m; 3-line call-site contract given), RE-P-15's clocktower / ponder vista / fill lights / invented safety floor |
| **BLOCKED-ON T01** | 1 | RE-O-10 `TATWorldMapBoundary` ×13 + KillZ (producer + T05 map UI; full extraction contract below) |
| **BLOCKED-ON regeneration** | 1 | C-5/RE-B-09 graybox 15 (four-box table patch measured, 63 matched / 15 changed) |
| **DEFERRED** | 1 | RE-Q-02/03/11 meshing (LOD/nanite/UV; needs a T01 re-export + a hard-limit decision) |
| **NOT TAKEN** | 5 | RE-B-05 (7 unproduced component classes — T01 extractor), RE-B-07 (MultiMesh per-instance losses — documented, no code change), RE-B-08 (cell merge — measured regression, stays off), RE-B-13 (decal cap 256 vs Old Manor's 292 — decal lane), RE-B-15 (census 47-node accounting) |

Three of the four P1s needed the producer as well as the consumer (splines,
LevelInstance coverage, the streaming graph), and the fourth (FTUE double load)
was consumer-only; all four have a red proof and a green re-run.
Total measured deltas: **+2,400 LevelInstance meshes**, **5 always-loaded
sublevels pulled from the authored graph**, **432 lofted spline
records replacing 1,049 collapsed duplicates (→ 747)**, **307 markers off the
world origin**, **1,693 duplicate meshes removed from FTUE**, and **0** silent
filters left in the mesh path.

---

## Integrator steps (in order)

1. `python3 tools/parse_tables.py` (or `make normalize`) at the merged HEAD —
   this is the only step this lane cannot run. It writes `spline`,
   `streaming_levels`, `level_instances` targets outside `/Game/Maps/`, the
   corrected marker transforms and `markers_origin_fixed`.
2. `make audit-refresh-stamps` (the `parse_tables.py` producer hash changed).
3. Re-run the probe: it must print
   `GEOM_PROBE checks=8 fails=0 pending_regeneration=0` (or
   `pending_regeneration=2` if step 1 was skipped — that is the explicit signal).
4. Re-read the E2E and perf floors: Old Manor gains 156 meshes and ~156 colliders
   (`OldManor_PathBlockers`), the Den gains 19 meshes, FTUE loses 1,693. The W7
   floors in `AGENTS.md` are unchanged for the gates this lane measured, but the
   per-map `PERF_CENSUS` numbers will move (already one wave stale in
   `docs/PERFORMANCE.md`).
5. Optional P2: apply the four-box graybox patch (C-5 section) and regenerate.
6. `tools/bin/` must exist (git-ignored binaries) or `make audit` adds a
   `vgmstream ... missing` drift line; it was symlinked from the main checkout
   for these runs.

---

## Gate evidence

All headless, serial, no GPU, no capture. `game/data/generated/` untouched.

| gate | command | result |
|---|---|---|
| compile | `tools/godot --headless --path game --script $PWD/tools/check_scripts_compile.gd` | `scripts checked: 121, broken: 0` (baseline 120 + `probe_geometry_placement.gd`) |
| producer unit | `python3 tools/test_parse_level_splines.py -v` | `Ran 10 tests … OK` |
| producer compile | `python3 -m py_compile tools/parse_tables.py` | exit 0 |
| red/green probe | `tools/godot … res://tests/probe_geometry_placement.gd` | `GEOM_PROBE checks=6 fails=0 pending_regeneration=2` |
| probe, regenerated payload | `TAT2_LEVELS_DIR=/tmp/t09_proof/out/levels …` | `GEOM_PROBE checks=8 fails=0 pending_regeneration=0`; `streaming always_loaded total=42 {16, 11, 8, 5, 2}` |
| probe, + real map loads | `… -- --load-spline-map --load-map` | `checks=10 fails=0` |
| probe, graph end-to-end | `TAT2_LEVELS_DIR=… … -- --load-graph-map` | `GEOM_PROBE graph_map payload_streaming=6 from_graph=5 graph_missing=0 meshes=332`; `PASS: RE-B-01 loader pulls the authored always-loaded set`; `checks=8 fails=0 pending_regeneration=0` |
| `make test` | `make test` | `SUMMARY: fails=0` (suite 91 included) |
| `test_m2_player.gd` | `tools/godot … res://tests/test_m2_player.gd` | `M2_SUMMARY: fails=0` |
| E2E full | `run_e2e_tests.gd` | `SUMMARY: fails=0 passed=278 total=278` (W7 floor) |
| E2E tier 1 (incl. `T1-10-D`) | `run_e2e_tests.gd -- --tier=1` | `SUMMARY: fails=0 passed=117 total=117`; `PASS: [T1-10-D] auto-mantle logic=true y=1.73 at 0.75s / 2.00 at 2.0s` |
| `make audit` | `make audit` | **one intentional failure**: `baseline: producer tools/parse_tables.py changed since the baseline (sha256 fe2f6a64dbd6 -> 4ea9ee439ca2); regenerate with python3 tools/parse_tables.py (or make normalize) then run --refresh-stamps`. Every content check is OK (`content levels files=107`, materials 1629, decals 675, niagara 3695). This is the same integrator-only step T04 hit; nothing else fails. `tools/bin/` (git-ignored binaries) was symlinked from the main checkout so the vgmstream drift line is gone. |

Regression check against the W7 floors: compile 121/0 vs 120/0 (new file only),
`run_tests` `fails=0`, E2E unchanged or better — nothing below floor. The only
gate that cannot be green in a lane is the producer baseline, by design.

1. **`AGENTS.md` "Known traps" — Guildhall POI graybox floors.** Replace
   "Guildhall POI graybox floors (1,637 `GB_Floor_2x2`) are a deferred content
   project, not a loader defect. Do not 'fix' them by nudging the loader." with:
   "Guildhall POI graybox floors: 1,637 `GB_Floor_2x2`, **1,622 of which carry an
   authored override material**; the other 15 are the only genuine gap and they
   render a dark brown plank (`MI_WoodVarnishAAlignXYZ_Red` →
   `Planks_D.png`, mean RGB (62,55,47), no serialised tint) — not grey. The
   visible checker floor is authored granite (`SM_Floor_2x2A` →
   `MI_GraniteFloorA`). Do not 'fix' the granite and do not nudge the loader."
2. **`AGENTS.md` gates table — compile floor.** `120 checked` → **121**
   (`game/tests/probe_geometry_placement.gd`).
3. **`AGENTS.md` gates table — suite count.** "suites numbered to 90" →
   **91** (`run_tests.gd` suite 91, T09 geometry/placement contract).
4. **`AGENTS.md` gates table — `run_tests.gd` count.** 278 PASS → **+·** one
   suite (update from the integrator's merged run; this lane's suite adds one
   PASS line).
5. **`docs/FIDELITY_GAPS.md` — spline meshes.** The 489 "`SplineMeshComponent`"
   figure is **469 with a real `StaticMesh` + 20 `SplineEditorMesh`** editor
   meshes; the producer emits authored `spline` params for **432** of them (37
   have no `StartPos` and stay rigid). Update the count and drop the
   "never read" wording once `make normalize` has run.
6. **`docs/FIDELITY_GAPS.md` / RE-B-02 — LevelInstance coverage.** "138 of 190
   merged" → **190 of 190** after the key-normalisation fix (+2,400 mesh
   instances).
7. **`docs/FIDELITY_GAPS.md` / streaming.** "the authored `LevelStreamingAlwaysLoaded`
   graph is not consumed" → the payload now carries `streaming_levels` (67
   records over 6 maps) and `level_loader` adds the always-loaded levels that
   the hardcoded lists omit (`OldManor_PathBlockers`, `ThievesDenTest_Contracts`,
   `ThievesDen_LoadoutCapture`), skips those already merged as a `LevelInstance`,
   and never adds a dynamic level.
8. **`docs/FIDELITY_GAPS.md` — mirrored instances.** Replace the 3,290 figure
   with **2,629 mirrored rendered mesh records in the 15 loaded Guildhall
   sublevels** (re-derived here from the payloads); the higher number counts
   every record type. The winding consequence remains unverified.
9. **RE-P-07 wording.** "AGENTS forbids a blanket offset" — the surviving
   `+0.35 m` is a T10 call-site defect, not a loader one; record the owner.
10. **RE-Q corrections (from the re-measurement):**
    - dead UV payload is **216.81 MB / 40.0 %** of the GLB library, not "≈209 MB
      (38 %)"; the `TEXCOORD_4..7` component is 139.50 MB / 25.75 %;
    - the 2.70 GB `game/.godot/imported` is **not** mesh cost: only 2,065 `.scn`
      (190.09 MB) are live; 1,629.4 MB is `.ctex`, 604.6 MB audio, 182.6 MB fonts,
      and 995 `.scn` (94.71 MB) are stale;
    - GLB-vs-LOD0 is **1,864 comparable / 1,863 equal / 1 differs / 119 dumps
      without a GLB**, not 1,979/1,840/138;
    - the nanite ratio is **8.66×** (30 `levels/Guildhall` payloads) or **8.75×**
      (with POI/3rd/Vault), never 9.1× — that number divides two different sets;
    - LOD1/2/3 percentages are 49.96 / 24.97 / 12.46.
11. **RE-O-10 corrections.** `TATWorldSettings` does **not** serialise
    `MapType`/`DefaultGameMode`/`DevelopmentMissions` on `Guildhall_P` or
    `OldManor_P` (only FTUE_P and ThievesDenTest_P carry them); only **2 of 13**
    `MapLabel`s resolve in `StringTables`, the other 10 are GUID keys present only
    in `localization/en.csv`, and `ThievesDenTest_P` has no `MapLabel`/`MapMaterial`
    at all. There is no `Secondary[]` array — each floor is its own actor with
    `MapType = Secondary`.
12. **`docs/PERFORMANCE.md`** — already stale per RE-Q-13; the W7 census remains
    authoritative (`Guildhall chunks=5863, collision_shapes=24310`).

## Open risks

1. **The payload half of RE-B-01/02/04 and RE-P-05 is inert until the integrator
   runs `python3 tools/parse_tables.py`.** The producer and the consumer were
   proved together against a `/tmp` regeneration
   (`TAT2_LEVELS_DIR=/tmp/t09_proof/out/levels`), but the committed
   `game/data/generated/` still has the old payload. The probe prints those four
   checks as `PENDING_REGENERATION`, never as a pass.
2. **The producer run also moves 291 marker positions** that had been collapsed
   onto a non-zero `LevelTransform` origin, and 307 door/loot markers off the
   world origin. `door_spawns` has no runtime consumer today, but
   `scene_element_spawns` does: any SceneElement override that had been matched
   by the wrong position could change its match. `run_tests` suite 31/11b cover
   the SceneElement counts.
3. **Loading the authored always-loaded graph adds sublevels to every map load.**
   Old Manor gains `OldManor_PathBlockers` (156 meshes) and the Den gains
   `ThievesDenTest_Contracts` (17 meshes) + `ThievesDen_LoadoutCapture` (2).
   Guildhall gains 3 audio/cloud sublevels with 0 meshes but real marker/actor
   payloads (they cost JSON parse time only). Expected: +~180 collision shapes
   and +~180 draw instances on Old Manor; the E2E/perf floors must be re-read
   after regeneration, and `docs/PERFORMANCE.md` is already a wave behind.
4. **Mirrored bases remain unproven visually.** The count is now in every run
   log; the winding question needs a one-object capture (`CULL_BACK` vs
   `CULL_DISABLED`) that this lane is not allowed to take.
5. **The spline loft is only as good as the authored frame convention.** The
   loader assumes UE's cross-section axes (Godot Y = height from `StartScale.Y`,
   Godot Z = width from `StartScale.X`) and a negated roll; the 6 m fence chord
   and the driveway endpoint checks agree, but no capture compares a curved run
   against the shipped frame. A single `SM_OldManor_GardenWall_Fence_6x4` run is
   the acceptance shot.
6. **`spline_deform_mesh` de-indexes through `SurfaceTool`.** Spline meshes are
   small (a fence panel is a few hundred triangles), so vertex duplication is
   bounded; a future spline mesh with >20 k triangles would want an
   `add_surface_from_arrays` path with the custom-format flags resolved instead.
7. **Mantle duration now depends on the live clip length.** With the legacy
   (un-retimed) GLBs on disk the movement is 0.73–2.57 s, after `make anims` it
   is 0.75–2.58 s; `test_anim_gates.gd` accepts the legacy state exactly once.
   Any future clip replacement changes traversal pacing — that is the intent,
   but it is a gameplay-visible coupling.
8. **Producer statistics with no runtime consumer.** `markers_origin_fixed` is a
   per-map producer counter (the loader does not read it), like
   `content_overrides` and the `*_unresolved` counters. T01's
   `check_consumers.py` (on `rem/T01-pipeline`) enforces "every generated key has
   a consumer"; it needs an allowlist entry for `markers_origin_fixed`, exactly
   as it already has for the other producer statistics. `spline`,
   `streaming_levels` and `level_instances` **are** consumed by
   `level_loader.gd`.
9. **The merged-sublevel pre-scan parses the level-instance-bearing payloads
   twice** (once to collect `level_instances`, once to build). On Guildhall that
   is one extra parse of `Guildhall_PeripheryA` (~3 MB, tens of ms against a 16 s
   load); payloads with `"level_instances": []` are rejected by a byte scan and
   cost nothing. If that ever matters, cache the scan result by path+mtime.
