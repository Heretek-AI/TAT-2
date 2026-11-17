# Packed Level Actor instances + Guildhall street surface (2026-11-16)

Follow-up to the 2026-11-16 handoff. Live QA of contract 4 showed the player
standing on a graybox pad surrounded by floating building fragments and black
void. The cause was not missing art: the packed city geometry was extracted but
collapsed to each actor's root.

## Root cause

Guildhall's city blocks are `BPP_PL_*` Packed Level Actors. Their geometry is
stored in `InstancedStaticMeshComponent` templates on the BPP class, with the
real placement transforms in a **top-level `PerInstanceSMData` array**:

```
extracted/json/Maps/Buildings/Periphery/PackedLevels/
  BPP_PL_Periph_Apartment_1400_6Story_Front.json
    InstancedStaticMesh10_GEN_VARIABLE
      StaticMesh = SM_Urban_Foundation_Wall_4x6
      PerInstanceSMData = [ ... 14 transforms ... ]
```

The level instance stub only has `Template` + `AttachParent`; it has no
`StaticMesh` and no `PerInstanceSMData`:

```
Guildhall_PeripheryA.json
  InstancedStaticMeshComponent'...BPP_PL_..._C_0.InstancedStaticMesh'
    Template -> BPP_PL_..._C:InstancedStaticMesh_GEN_VARIABLE
```

`tools/parse_tables.py` previously read `PerInstanceSMData` only from the level
stub. The mesh path fell back to the BPP template, but every instance was
emitted at the actor root. That is the “objects collided” / floating-fragment
look.

## Fix

`tools/parse_tables.py`:

- `build_bp_mesh_templates` now stores each template's `PerInstanceSMData` and
  local transform alongside its mesh.
- The instanced-component branch falls back to the template's mesh,
  `PerInstanceSMData`, and local transform when the level stub omits them.
- Instance transforms are composed as
  `level_transform × actor_root × component_local × instance_transform`.

`game/src/core/level_loader.gd`:

- `PeripheryA` is no longer treated as decorative horizon dressing. It contains
  the safe-room buildings and now generates collision; only `SkyboxGeo` remains
  non-colliding.
- Chunk nodes carry `ue_mesh` / `decorative` metadata for diagnostics.
- Guildhall's landscape material uses the real `T_RoadBricksA_D/N` textures
  named by `MI_Landscape.TextureStreamingData` (`T_RoadBricksA_H`). Other maps
  keep the cobble fallback.

## Verified counts

Before:

- `Guildhall_PeripheryA`: 3,587 mesh instances, all packed components collapsed
  at their actor roots.
- Guildhall runtime: 16,767 meshes.
- Safe-room spawn: 9 meshes within 18 m.

After `make normalize`:

- 39 `BPP_*` files expose **3,210 instanced components / 30,127 real
  instances**.
- `Guildhall_PeripheryA`: **10,590** mesh instances.
- Guildhall generated total: **55,234** mesh instances.
- Guildhall runtime load: **51,305** meshes, 7,866 chunks, 217 collision
  bodies, 23,125 collision shapes.
- Safe-room spawn at `(127.27, 25.47, -5.33)`: **630 meshes within 25 m**,
  including the apartment walls/floors/roofs, crates, barrels and debris.

The packed apartment actor's real instance AABB is
`x 111.9..131.8, y 12.0..61.4, z -25.7..-5.5`, which encloses the Guildhall
safe-room spawn. Previously every one of those pieces sat at
`(121.74, 12.00, -16.19)`.

## Runtime evidence

`make test` (`/tmp/opencode/final_packed_test.log`):

```
PASS: Perf chunking (chunks=7866, multimeshes=4829, collision_bodies=217,
      shapes=23125, occluders=768, max_chunk_span=96.7m, distance-culled=2149)
PASS: Skybox excluded from physics; packed-city PeripheryA is collidable
PASS: packed Level Actor instances expanded (PeripheryA meshes=10590,
      630 around safe-room spawn)
SUMMARY: fails=0
EXIT=0
```

`make audit`: 12,630 / 12,704 manifest entries resolved (99.4%), exit 0.

Desktop/Xvfb QA screenshots:

- `/tmp/opencode/qa_guildhall_packed2.png` — safe room now enclosed by brick
  walls, crates and a solid floor.
- `/tmp/opencode/qa_xvfb_look.png` — exit onto the metal walkway; brick
  buildings across the gap, no floating fragments.
- `/tmp/opencode/qa_xvfb_street.png` — road-brick street surface below the
  walkway (`T_RoadBricksA_D`).

## Landscape layer blend

The `LandscapeComponent` exports also carry `WeightmapTextures` and
`WeightmapLayerAllocations`, which map each authored layer to a weightmap
texture/channel. The parser now emits:

```
"weightmap": ".../Weightmap_6.png",
"layers": [
  {"layer": "GroundA", "channel": 0},
  {"layer": "LandscapeVisibilityLayerInfo", "channel": 1},
  {"layer": "GrassA", "channel": 2},
  {"layer": "CobbleA", "channel": 3}
]
```

`game/src/core/tat_landscape.gdshader` blends the extracted layer albedos by
channel, normalizes the used weights, and discards the authored
`LandscapeVisibilityLayerInfo` holes. Layer textures are mapped from the real
extracted files:

| Layer | Texture |
|---|---|
| `CobbleA` | `T_RoadBricksA_D.png` |
| `CobbleB` | `T_GroundCobbleA_D.png` |
| `GroundA` | `T_GroundDirtA_D.png` |
| `GrassA` | `T_GrassA_DA.png` |
| `RockTileA` | `T_RockTile_D.png` |
| `Puddle` | `T_Decal_Puddle_1_Normal.png` + `_Opacity.png` (normal/alpha, dark water tint) |
| `GroundWet` | weightmap darkening + roughness reduction |

`Puddle` uses the real extracted puddle normal/opacity maps and the authored
weightmap channel; the albedo is a labelled dark-water tint because the cooked
puddle material kept no albedo. `GroundWet` is a wetness modifier (darken +
lower roughness), not a separate albedo layer. Layers whose allocation lives on
a second weightmap texture (`tex != 0`) are still skipped because the shader
samples the first weightmap only.

Visual check: `/tmp/opencode/qa_weightmap_walk.png` shows the blended
road/cobble/dirt surface and the authored hole under the safe-room walkway.

## LevelInstance sublevels

`Guildhall_PeripheryA` also places separate maps as `LevelInstance` actors. These
are not in the `LevelStreamingAlwaysLoaded` list, so they were absent from the
runtime even though their source maps are extracted. The parser now reads each
`LevelInstance` actor's `CookedWorldAsset`, resolves its
`LevelInstanceComponent` transform, loads the generated sublevel, and merges its
meshes/lights/markers/decals/volumes/doors with that transform.

Across all maps: **138 LevelInstances loaded, 32,166 meshes, 0 unresolved**.
For Guildhall `PeripheryA`: 4 LevelInstances, including
`Facade_Apartment_CarUnderpass` at `(-67.1, 17.6, 61.9)`, with **697 meshes**
within 30 m of the authored transform.

Runtime effect:

- Guildhall: 51,305 -> **63,210 meshes**, 10,865 chunks, 222 collision bodies,
  **25,074 collision shapes** (cap raised from 24,000 to 32,000 after measuring
  the real count).
- Guildhall loot containers: 103 -> 107; swinging doors: 153 -> 155.
- `make test` suite 20 asserts the car-underpass LevelInstance is merged.

## Remaining gaps (not faked)

- The safe-room black rectangle is a landscape visibility gap between packed
  building floors; no matching underpass/lower-floor sublevel was found at that
  exact location in the extracted Guildhall maps. The `Facade_Apartment_CarUnderpass`
  LevelInstance is now loaded at its authored transform `(-67.1, 17.6, 61.9)`.
  If the safe-room gap still shows void, the next fix is either a missing floor
  mesh in the packed class or disabling visibility discard for that component
  so the landscape surface fills it.
- Layers allocated to a second weightmap texture (`tex != 0`) are skipped; the
  shader currently samples only the first weightmap. Components with more than
  four color allocations drop the fifth.
- `Puddle` albedo is a labelled dark-water tint (the cooked material kept only
  normal/opacity); `GroundWet` is a darken/roughness modifier.
- The safe-room catwalk has open gaps between its structural crossbeams; the
  street below is visible through them. No floor mesh exists at that exact
  spot in the extracted BPP class, so no floor was invented.
- Authored visibility holes discard correctly, but the underpass/lower floor
  below some holes is not present in the extracted BPP geometry; those holes
  still show void until the corresponding sublevel is loaded.
- Sky/moon scale, VFX rates and Wwise event naming remain as documented in
  `FIDELITY_GAPS.md`.

## Reproduce

```bash
make normalize
make test
make audit
```
