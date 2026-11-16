# Swinging Doors — implementation report

## Summary
Real swinging doors end-to-end: `tools/parse_tables.py` resolves every
`TATSwingingDoorPivotComponent` (pivot → parent actor → actor world × pivot
relative, plus SCS leaf meshes), excludes the dynamic leaves from the static
batches, and emits them in each `.tatlevel.json`; `level_loader.gd` passes
them through; new `game/src/interact/swinging_door.gd` builds one openable
door per pivot; `mission_controller.gd` spawns the wave after level load.

- **281** pivot stubs in normalized levels → **170 resolved doors**,
  **262 resolved leaves** (all with existence-checked `.glb`s), **111
  unresolved pivots** (counted, no placeholders).
- Static meshes **55698 → 55452 (Δ −246)**; lights unchanged (**3479**).
  Δ = −(262 excluded − 16 newly-recovered leaves that the old static path
  never emitted — see §4).
- `make test`: **EXIT 0, 20/20 PASS, `SUMMARY: fails=0`**, zero SCRIPT ERROR.
- Bounded door probe (lead): opens to exactly π/2 — PASS.

## 1. Pivot → actor → leaf resolution (`tools/parse_tables.py`)

Per level file, before the main export loop, a door pre-pass runs with the
existing SCS/template machinery (`_stub_actor`, `load_bp_exports`,
`_resolve_template_in_bp`, `resolve_bp_component`, `_merge_template_parent`):

1. **Pivot stub** (`Type == TATSwingingDoorPivotComponent`, one per `Pivot` /
   `SecondPivot`): parent actor instance from `Outer`
   (`…:PersistentLevel.<Actor>`), actor root world via the actor's
   `RootComponent` + `AttachParent` chain (`get_world_mat`).
2. **Pivot relative TRS**: the stub's own `RelativeLocation/Rotation`
   (e.g. `Facade_Storefront_Cluster.StaticMeshActor_10.Pivot` =
   `(-500,-70,10)` cm, yaw −90°); when the stub is identity (PackedLevel
   sublevels such as `Building_Guildhall_POI`), the authored transform is
   taken from the BP template via the stub's `Template` archetype ref
   (`Default__` CDO prefix tolerated, inheritance followed), e.g.
   `BP_Manor_Doorway_Shutterdoor_Single_C:Pivot` → Z = 181.68 cm.
3. **Pivot world** = actor-root-world × pivot-relative (× sublevel
   `LevelTransform`), converted with `ue_mat4_to_godot_trs` → `pos`/`basis`.
4. **Leaves**: level `StaticMeshComponent` stubs in the same actor whose
   `AttachParent` tail is the pivot's component name. Mesh in priority
   order: stub `StaticMesh` → `Template`-ref BP export → `bp_templates` →
   `.glb` stem fallback; every mesh is **existence-checked**
   (`game/assets/ue/Content/…​.glb`). Leaf relative transform: stub
   relative if present, else template relative, else identity; converted to
   Godot `rel_pos`/`rel_basis`/`rel_scale_v`, with raw UE `rel_loc`/
   `rel_rot`/`rel_scale` and the SCS `ParentComponentOrVariableName`
   (`scs_parent`) kept for traceability.
5. **Dedup** by `(actor, pivot)`; one door per pivot (double doors = two
   doors, e.g. `Pivot` → `…Glass1`, `SecondPivot` → `…Glass`).

New per-file keys: `swinging_doors: [{name, actor, class, pos, basis,
leaves: [{mesh, res, rel_loc, rel_rot, rel_scale, rel_pos, rel_basis,
rel_scale_v, scs_parent}], source}]`, `door_leaves_excluded` (count),
`swinging_doors_unresolved: [{pivot, actor, class, reason, source}]`.
Resolved leaf stub indices are skipped in the StaticMesh/Spline/Instanced
branches so dynamic doors never duplicate static batches; doorways frames
(parented to `RootSceneComponent`) are untouched.

## 2. Per-map counts

| file | doors | leaves | excluded | unresolved | meshΔ |
|---|---|---|---|---|---|
| Buildings/Guildhall/Building_Guildhall_POI | 78 | 114 | 114 | 43 | −114 |
| Buildings/Guildhall/Building_Guildhall_POI_3rdFloor | 4 | 4 | 4 | 2 | −4 |
| Buildings/Guildhall/Guildhall_Vault_CeremonialChambers | 0 | 0 | 0 | 8 | 0 |
| FTUE/FTUE_Building_JewelryStore | 2 | 2 | 2 | 2 | −2 |
| FTUE/FTUE_Building_SpawnArea | 2 | 2 | 2 | 0 | −2 |
| Guildhall/Facade_Storefront_Cluster | 2 | 2 | 2 | 0 | −2 |
| Guildhall/Guildhall_Geometry | 4 | 4 | 4 | 0 | −4 |
| Guildhall/Guildhall_PeripheryA | 14 | 14 | 14 | 0 | −14 |
| OldManor/OldManor_Geo | 64 | 120 | 120 | 56 | −104 |
| **TOTAL** | **170** | **262** | **262** | **111** | **−246** |

Spawned in-game: **100 doors on guildhall** (`swinging_door_count`), **64 on
old_manor**. Markers/lights and all other arrays are untouched.

## 3. Unresolved pivots (111, all `no_resolved_leaves`, counted not guessed)

These actors expose pivots whose leaves are not static meshes in the level:
no `StaticMeshComponent` is attached to the pivot (their motion is
spawner/visual-script driven, e.g. shutterdoors, or they are open doorway
frames). No placeholder geometry is spawned for them.

| class | count |
|---|---|
| BP_OldManor_Doorway_4x650_C | 32 |
| BP_Prison_WallA_DoorwayB2_6x6_C | 22 |
| BP_Civic_Doorway_6x8_C | 18 |
| BP_Manor_Doorway_4x8_C | 16 |
| BP_Prison_WallA_DoorwayB_6x6_C | 8 |
| BP_Manor_Doorway_Shutterdoor_Single_C | 5 |
| BP_Manor_Doorway_4x8_Shutterdoors_C | 4 |
| BP_Prison_WallA_DoorwayA_6x6_C | 2 |
| BP_GB_DoorSolo_C | 2 |
| BP_OldManor_Doorway_6x850_C | 2 |

## 4. Static-batch exclusion audit

- Meshes Δ per file equals `−door_leaves_excluded` everywhere **except**
  `OldManor_Geo` (−104 vs 120): 16 window-glass leaves
  (`SM_Manor_WindowB_1x3_Glass[1]`, actors of class
  `BP_Manor_WindowB_4x650_C` whose `Template` ref points at parent
  `BP_Manor_WindowB_4x6_C`) were **never emitted** by the old name-based
  static path — the `Template`-ref resolution recovers them, so they only
  ever exist as dynamic door leaves. −246 = −(262 − 16). Lights Δ = 0.
- No leaf mesh survives in any **playable-map** static batch. The only two
  remaining `SM_Urban_Ext_FrontDoorA_Glass` instances sit in
  `Menus/MainMenu/{MainMenu,BeautifulCorner_Startscreen_P}` — menu
  backdrop dressing with no door actors (0 doors in those files), i.e.
  legitimate static usage, not duplicates.
- Scene check (temp, since deleted): 136 door-leaf `MeshInstance3D` ==
  136 guildhall leaves; no leaf mesh present in the map's static batches.

## 5. Runtime behaviour

- `level_loader.gd`: `swinging_doors` collected in `_parse_sublevel_file`,
  passed through `result` with `swinging_door_count`; leaves resolve
  `Mesh` (+bound materials) through the existing `_get_mesh_and_shape` —
  no duplicated resolver.
- `game/src/interact/swinging_door.gd` (new, `Node3D`): door root at pivot
  `pos`/`basis`; child `DoorPivot` carries one `MeshInstance3D` per leaf at
  its relative transform and one `StaticBody3D` + `BoxShape3D` (layer 1)
  per leaf, so collision rotates with the door. Group `interactables`
  (+`swinging_doors`); `get_interact_prompt()` → `[F] OPEN` / `[F] CLOSE`;
  `interact()` toggles a 90° swing about pivot-local +Y over 0.4 s (Tween,
  `TRANS_SINE`); closing returns to 0; repeated toggles ignored while
  tweening; unresolvable leaves skipped fail-closed, never placeholders.
- `mission_controller.gd`: `_spawn_swinging_doors()` after the level load
  (skips when none); logs `TAT-2 swinging doors: N`.

## 6. Verification

- Bounded headless probe (guildhall, waits for **both** `guards` and
  `swinging_doors` groups before touching a door — indexing a door after
  only the guard wait races the spawn wave and hangs the tree):
  `PROBE frames=114 doors=100 guards=6`,
  `PROBE door=@Node3D@16310 pivot=DoorPivot:<Node3D#…> in_tree=true`,
  `PROBE rot before=0.0 after=1.57079637050629 open=true tweening=false`,
  `PASS: swinging door opens`.
- Temp `_tmp_doors_check.gd` (deleted after the run, per constraints):
  `swinging_door_count=100` == spawned nodes; `door_leaves_excluded=136`
  == leaf total; no leaf mesh in static batches; scene leaf MIs == 136;
  open moves leaf + body with root fixed, close restores within tolerance,
  prompts `OPEN`/`CLOSE`, rapid double-toggle collapses to one open.
- `make test`: EXIT 0 — 20/20 PASS, `SUMMARY: fails=0`, zero SCRIPT ERROR.
  Full log: `/tmp/opencode/make_test_final.log`.
