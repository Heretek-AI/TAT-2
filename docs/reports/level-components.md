# Level Components Extraction — Implementation Report

Stage: extract ignored level components via real UE data (1:1 fidelity).
Date: 2026-11-16. Worktree branch scope: `tools/parse_tables.py`,
`game/data/generated/levels/**`, `docs/reports/level-components.md`.

## What was done

Extended `tools/parse_tables.py` with a Blueprint SCS template resolver and nine
new output arrays in every `.tatlevel.json`. No existing key/value was altered;
`game/src/**`, `game/tests/**`, `Makefile`, extractor C#, Android files untouched.

### Resolver (`resolve_bp_component` + `_resolve_template_in_bp` + `_merge_template_parent`)

Level actor exports for `BP_*_C` actors list components by `InternalVariableName`,
but the level component exports are stubs (`AttachParent` + `CreationMethod` only).
The authored payload lives in the BP class JSON (same basename, e.g.
`BP_Civic_WallA_IntVent_2x8.json` under `extracted/json/Art/...`):

1. Index all 6,071 non-Maps BP JSONs by basename (parsed lazily + cached).
2. Prefer the stub's own `Template` archetype ref
   (e.g. `DecalComponent'BP_AmmoRefill_Pickup_C:Decal_GEN_VARIABLE'`), which points
   at the parent BP that actually authors the component.
3. Otherwise match `SimpleConstructionScript.AllNodes[].InternalVariableName` to the
   stub name, resolve `ComponentTemplate` to the export in the same file, then
   follow `Template` inheritance refs (up to 6 levels, e.g. `BP_SecurityTurret_180`
   -> `BP_SecurityTurret` for Niagara assets, `BP_GB_DoorSolo` ->
   `BP_SwingingDoor_DoubleBase`).
4. Fall back to CDO/`Default__` exports (`PostProcessComponent` on weather presets).
5. World transform = level actor RootComponent world (placement, via existing
   `AttachParent` chain walker) x SCS ancestor template locals (root excluded —
   the level root instance carries placement) x component template local.
   Direct components (SkyLight/Fog/Atmosphere/PP actors) use their own authored
   `RelativeLocation/Rotation/Scale3D` when present.
6. Dedup per file on `(actor, component, type)`; unresolved assets are counted,
   never guessed.

### New arrays (all values 1:1 from UE dumps; UU->m x0.01, Y/Z swap like meshes)

- `rect_lights`: {pos, basis, scale, rotation(YXZ euler deg), color, intensity,
  width, height, radius(m), cast_shadows, source_actor, source}
- `sky_lights`: {pos, ..., intensity, color, cubemap, source_type, ...}
- `fog_volumes`: {pos, ..., density, height_falloff, inscattering[r,g,b],
  directional_inscattering, volumetric, ...}
- `post_process`: {pos, ..., settings (scalars + blendable material paths +
  unbound flag, `bOverride_*` stripped), ...} — covers `PostProcessVolume` actors
  and `VolumetricCloudComponent` (as `settings.volumetric_cloud_material`).
- `sky_atmospheres`: {pos, ..., source_actor, source}
- `decals`: {pos, ..., material (UE path), size (DecalSize, null when unauthored),
  ...} — scale in `scale` still carries the template RelativeScale3D.
- `niagara`: {pos, ..., asset (UE path), ...} — emitted ONLY with a resolved Asset.
- `volumes`: {class, actor, pos, extent} — `TATBlockingVolume` (brush: extent =
  |RelativeScale3D| = half-extent in m, default brush is 200^3 UU),
  `TriggerBox/TriggerVolume`, `NavModifierVolume`, `NavMeshBoundsVolume`,
  `BP_TutorialTriggerVolume_Box_C` (box: BoxExtent x0.01, Y/Z swapped).
- `landscape_splines`: {points (Godot m), width (mean |Left-Right| in m), mesh,
  material} — from `LandscapeSplineSegment.Points` + `LocalMeshComponents`
  StaticMesh refs. Segments without a resolvable mesh are skipped (none hit this).

## Counts

Global (77 level JSONs): meshes 55698, lights 3479 (both byte-identical to the
pre-change script on the same inputs), markers 4479, landscapes 210,
**rect_lights 31 (7 files), sky_lights 1, fog_volumes 1, post_process 2,
sky_atmospheres 1, decals 667 (16 files), niagara 3692 (29 files, 0 unresolved),
volumes 288 (12 files), landscape_splines 52 (3 files, all with mesh; 0 with
authored material — spline meshes in the dumps carry no material ref, field "")**.

| Map group | rect | sky/fog/pp/atmo | decals | niagara (unresolved) | volumes | splines |
|---|---|---|---|---|---|---|
| OldManor | 10 | – | 292 | 1812 (0) | 74 | 15 |
| Guildhall | 17 | – | 104 | 1275 (0) | 72 | 2 |
| FTUE | 1 | – | 141 | 45 (0) | 90 | – |
| ThievesDen (+Test) | 1 | pp 1 | 9 | 24 (0) | 4 | – |
| MainMenu | 2 | 1/1/1/1 | 60 | 5 (0) | 2 | 35 |
| Other (Buildings/MissionLobby/Prototype) | – | – | 61 | 531 (0) | 46 | – |

File-count census matches the source data: 16 level files with DecalComponent,
7 with RectLightComponent, 1 each SkyLight/HeightFog/SkyAtmosphere,
2 PostProcessVolume. (The raw stub census of "38 Niagara files" includes BP-class
asset files stored under `Maps/` — e.g. `BP_Key_Apartment_ItemActor.json` — whose
stubs are archetypes, not placements; all 3692 *placed* instances resolved.)

## Samples (verified against source dumps)

RectLight — `Gameplay/Interactables/EscapePoints/BP_EscapePoint.json::BP_EscapePoint_C_0`
(level stub `extracted/json/Maps/FTUE/FTUE_Geometry.json` idx 1586):
`{intensity 0.0 (authored; animated by timeline), color [149,52,226],
width 1.0, height 350.0, radius 6.0, pos [-128.689, 18.3002, 169.1569],
rotation [-0, 0, 0]}` — hand-check: actor root UU
(-12874.902, 16915.691, 1650.0) yaw -90° + template offset (0, 6, 180.015)
rotated to (6, 0, 180.015) -> (-128.689, 18.300, 169.157) ✓; yaw -90+90 -> 0 ✓.

Niagara — same actor: `{asset: "/Game/Art/Gameplay/EscapeRoutes/EscapeWall/NS_EscapePoint",
pos [-128.874, 17.85, 169.1569]}`; parent-BP inheritance case:
`BP_SecurityTurret_180` -> `BP_SecurityTurret.json` asset
`NiagaraSystem'NS_SecurityTurret_Desactivated'` (this pattern fixed 639
unresolved instances in Guildhall_Gameplay alone).

Decal — `Art/Environment/Civic/Interior/BP_Civic_WallB_IntVent_2x9.json::
BP_LineMesh_OldManor_Wall_4x1250_C_1873` (actor instance named LineMesh, class
Vent_2x9 — label vs class, not a mismatch):
`{material: "/Game/MaterialLibrary/Environment/Decals/MI_DirtDecalA3",
pos [6.0, 21.0123, 73.2486], rotation [-0, -180, 0], scale [0.0533, 0.3039, 0.489]}`.
Template-ref inheritance case: `FTUE_Fairy` pickup decals resolve via stub
Template `BP_AmmoRefill_Pickup_C:Decal_GEN_VARIABLE` to material
`/Game/Art/Gameplay/Glyphs/M_Decal_Glyph` (earlier run honestly emitted
`material: null` + unresolved count; now 0 nulls globally).

Direct actors — `extracted/json/Maps/Menus/MainMenu/BeautifulCorner_Startscreen_Lighting.json`:
SkyLight `{intensity 2.0, cubemap .../Cubemap_GroundFloor_01, SLS_SpecifiedCubemap,
pos [23.5, 12.3, 8.8]}` (no authored LightColor -> null, not guessed);
HeightFog `{density 0.0, height_falloff 1.152424, inscattering [0.00598, 0.00561, 0.01042],
directional 5.0, volumetric true}`; PostProcessVolume_0 settings
`{WhiteTemp 7364, BloomIntensity 6.336, BloomThreshold 0.05, ..., unbound true}`;
SkyAtmosphere `{pos [24.5, 13.1, 7.1]}`. Second PP:
`extracted/json/Maps/ThievesDenTest/ThievesDenTest_P.json` PostProcessVolume_1
(Lumen/LE settings).

Volume — OldManor_Geo `TATBlockingVolume/BlockingVolume_0`:
`{pos [9.806, 11.5334, 47.4323], extent [2.3014, 0.7206, 0.035]}`.
Classes: TATBlockingVolume 208, BP_TutorialTriggerVolume_Box_C 55,
NavModifierVolume 16, TriggerBox 4, NavMeshBoundsVolume 3, TriggerVolume 2.

Spline — Guildhall_Landscape segment 0:
`{points 5 (first [83.6472, 7.8594, 174.5989]), width 3.0,
mesh "/Game/Art/Environment/City/Streets/Sidewalks/SM_SidewalkCityA_6m", material ""}`.

## Before/after + verification

- `python3 tools/parse_tables.py` (== `make normalize`): exit 0.
- Existing arrays unchanged by this change: ran HEAD `parse_tables.py` vs patched
  on identical `extracted/` inputs — meshes 55698 and lights 3479 identical, and
  sample maps match exactly (Guildhall_Geometry 583/13/9, FTUE_Geometry
  16848/145/1, OldManor_Geo 5089/461/306). (Stale on-disk files previously showed
  578/16532 for the first two because `extracted/` was re-dumped after they were
  written — not caused by this change; HEAD script reproduces the new numbers.)
- Loader (`game/src/core/level_loader.gd`) reads `.get("meshes"/"lights"/
  "markers"/"landscapes", [])` and ignores unknown keys, so the nine new arrays
  are inert. One stale `ThievesDenTest_FTUE.tatlevel.json` previously contained an
  `actors` array from an unknown older pipeline (never read by the loader); it now
  carries the standard schema + 5 new entries. All other 26 stale `actors` files
  were left untouched (script only writes files that have content).
- `make test`: `SUMMARY: fails=0`, `SCRIPT ERROR` count 0 (two consecutive runs).
  Perf-sensitive assertions (chunk/collider/occluder counts, ground raycasts) pass
  unchanged, confirming behaviour neutrality.

## Commands

- `python3 tools/parse_tables.py` (exit 0)
- `make test` (exit 0; `SUMMARY: fails=0`; `grep -c "SCRIPT ERROR"` -> 0)
- `git show HEAD:tools/parse_tables.py > tools/parse_tables.py` + rerun (before/after
  control; working file restored afterwards, `exit=0` rerun)

## Self-audit

- No stubs/TODOs; no invented values — unresolved assets counted, not guessed
  (final: 0 unresolved Niagara, 0 material-less decals, 0 skipped splines... the
  skip counters exist and report 0 rather than hiding anything).
- `landscape_splines[].material` is `""` for all 52 (no material authored on
  SplineMeshComponents in dumps) — recorded, not fabricated.
- `_merge_template_parent` is defined after `resolve_bp_component` (runtime-safe,
  module import order irrelevant) — style wart, no behaviour impact.
- VolumetricCloud only appears inside weather-preset BPs (never placed in levels),
  so it surfaces via `post_process[].settings.volumetric_cloud_material` only if a
  placed actor ever references one; weather gameplay maps use `TATWeatherManager`
  preset overrides (out of scope, already covered by the weather stage).
- Generated `levels/**` are gitignored build outputs; the commit contains the
  script + this report only.
