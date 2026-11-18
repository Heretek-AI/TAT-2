# GLB material-slot proof (plan task 1.1)

**Date:** 2026-11-17  
**Scope:** read-only proof. Created `build/qa/glb_slots.py`, `build/qa/glb_slots.txt`, `build/qa/glb_slots.json`, and this report. No source/runtime edits, no commit.  
**Verdict:** **GO** for task 1.6. All six GLBs preserve the exact material object names and expose an explicit material index per primitive. No mesh needs an index-binding fallback.

## Reproduce

```bash
python3 build/qa/glb_slots.py --out build/qa/glb_slots.json > build/qa/glb_slots.txt
```

The script is stdlib-only (`struct`, `json`, `pathlib`, `difflib`, `argparse`) and was run with Python 3.15.2. It parses the 12-byte GLB header, the JSON chunk (`0x4E4F534A`), the BIN chunk (`0x004E4942`), and decodes index accessors (`5121`/`5123`/`5125`) using accessor `byteOffset` plus bufferView `byteOffset`/`byteStride`. A primitive is flagged degenerate when it has `<3` distinct indices or `0` triangles. Full stdout is in `build/qa/glb_slots.txt` (256 lines); machine-readable results are in `build/qa/glb_slots.json`.

## Container / index validation

| GLB | bytes | JSON chunk | BIN chunk | meshes / primitives |
|---|---:|---:|---:|---|
| SM_ThievesDen | 982576 | 17532 | 965016 | 1 / 8 |
| SM_WindowStandardA | 25348 | 4716 | 20604 | 1 / 2 |
| SM_WindowStandardA_Open | 23792 | 4720 | 19044 | 1 / 2 |
| SM_FacadeLrgA_Base | 680740 | 13144 | 667568 | 1 / 6 |
| SM_FacadeLrgA_TopA | 538892 | 13148 | 525716 | 1 / 6 |
| SM_RoofCity_WindowA | 156024 | 6756 | 149240 | 1 / 3 |

All six: magic `glTF`, version 2, declared length equals file size. Every primitive is `mode=4` (`TRIANGLES`); every index accessor decodes within BIN. Repeated-index triangles and out-of-range indices are **0** for all 27 primitives, and every primitive has `>=3` distinct indices, so **no primitive is degenerate**.

## Per-primitive material mapping

`mat` is the GLB `primitives[].material` index; `material` is `materials[mat].name`. `distinct` is the number of unique decoded indices; `verts` is the `POSITION` accessor count.

| Mesh | prim | mat | material | mode | idx | distinct | verts | tris | degen |
|---|---:|---:|---|---|---:|---:|---:|---:|---|
| SM_ThievesDen | 0 | 0 | MI_OldManorWood | TRIANGLES | 1368 | 771 | 771 | 456 | no |
| SM_ThievesDen | 1 | 1 | MI_WoodFloorA | TRIANGLES | 1416 | 619 | 619 | 472 | no |
| SM_ThievesDen | 2 | 2 | MI_WallpaperFloralC_5 | TRIANGLES | 729 | 337 | 337 | 243 | no |
| SM_ThievesDen | 3 | 3 | MI_OldManorTrim | TRIANGLES | 2016 | 1202 | 1202 | 672 | no |
| SM_ThievesDen | 4 | 4 | MI_Manor_StoneTrim_Dark | TRIANGLES | 630 | 362 | 362 | 210 | no |
| SM_ThievesDen | 5 | 5 | MI_TrimMetalA_brass | TRIANGLES | 132 | 119 | 119 | 44 | no |
| SM_ThievesDen | 6 | 6 | WorldGridMaterial | TRIANGLES | 6 | 4 | 4 | 2 | no |
| SM_ThievesDen | 7 | 7 | MI_WoodBoardsOld | TRIANGLES | 8787 | 5242 | 5242 | 2929 | no |
| SM_WindowStandardA | 0 | 0 | MI_WoodBasicA | TRIANGLES | 624 | 171 | 171 | 208 | no |
| SM_WindowStandardA | 1 | 1 | M_EnvGlassUnlit | TRIANGLES | 12 | 8 | 8 | 4 | no |
| SM_WindowStandardA_Open | 0 | 0 | MI_WoodBasicA | TRIANGLES | 336 | 166 | 166 | 112 | no |
| SM_WindowStandardA_Open | 1 | 1 | M_EnvGlassUnlit | TRIANGLES | 6 | 4 | 4 | 2 | no |
| SM_FacadeLrgA_Base | 0 | 0 | MI_StoneTrimsheetB_Grey | TRIANGLES | 1728 | 482 | 482 | 576 | no |
| SM_FacadeLrgA_Base | 1 | 1 | MI_TrimOrnateWoodA_White | TRIANGLES | 777 | 369 | 369 | 259 | no |
| SM_FacadeLrgA_Base | 2 | 2 | MI_GlassFacadeA | TRIANGLES | 48 | 32 | 32 | 16 | no |
| SM_FacadeLrgA_Base | 3 | 3 | MI_TrimOrnateBronze | TRIANGLES | 384 | 149 | 149 | 128 | no |
| SM_FacadeLrgA_Base | 4 | 4 | MI_StoneStripA | TRIANGLES | 2508 | 571 | 571 | 836 | no |
| SM_FacadeLrgA_Base | 5 | 5 | MI_StoneWallA | TRIANGLES | 22914 | 4053 | 4053 | 7638 | no |
| SM_FacadeLrgA_TopA | 0 | 0 | MI_StoneTrimsheetB_Grey | TRIANGLES | 1452 | 364 | 364 | 484 | no |
| SM_FacadeLrgA_TopA | 1 | 1 | MI_RoofSlateC | TRIANGLES | 12558 | 2240 | 2240 | 4186 | no |
| SM_FacadeLrgA_TopA | 2 | 2 | MI_RoofBitumenA | TRIANGLES | 933 | 301 | 301 | 311 | no |
| SM_FacadeLrgA_TopA | 3 | 3 | MI_WindowDecoOpaque | TRIANGLES | 36 | 24 | 24 | 12 | no |
| SM_FacadeLrgA_TopA | 4 | 4 | MI_WindowDecoTrim | TRIANGLES | 1347 | 503 | 503 | 449 | no |
| SM_FacadeLrgA_TopA | 5 | 5 | MI_WallStoneBlockD | TRIANGLES | 5583 | 1030 | 1030 | 1861 | no |
| SM_RoofCity_WindowA | 0 | 0 | MI_TrimMetalA_Iron | TRIANGLES | 2745 | 850 | 850 | 915 | no |
| SM_RoofCity_WindowA | 1 | 1 | MI_CopperTile | TRIANGLES | 1068 | 259 | 259 | 356 | no |
| SM_RoofCity_WindowA | 2 | 2 | MI_GlassSkylightA | TRIANGLES | 444 | 194 | 194 | 148 | no |

In all six files, `materials[]` has no unused entry and `primitive.material == primitive index`. That equality is observed here, not assumed; task 1.6 should still read `primitives[].material`, which is the authoritative association. For SM_ThievesDen, the parsed `materials[]` order is exactly the eight-name order reported in the task's `strings` evidence; the trailing `M_ThievesDen` string is not a `materials[]` entry. `MI_OldManorPanels` and `MI_Pipes` occur in neither `materials[]` nor any primitive, confirming the two dropped source slots.

## Source sidecar slots (source order)

Sidecars are JSON arrays of `{"slot": "...", "material": "/Game/.../MI_Name.MI_Name"}`.

| Mesh | `slot` -> material object (sidecar order) |
|---|---|
| SM_ThievesDen | `Material__7880`=MI_OldManorWood, `Material__8461`=MI_WoodFloorA, `Material__4001`=MI_WallpaperFloralC_5, `Material__3099`=MI_OldManorTrim, `Material__9954`=MI_Manor_StoneTrim_Dark, `Material__9958`=MI_TrimMetalA_brass, `Material__3076`=MI_OldManorPanels, `Material__6947`=WorldGridMaterial, `Material__10572`=MI_WoodBoardsOld, `Material__10817`=MI_Pipes |
| SM_WindowStandardA | `GlassA`=M_EnvGlassUnlit, `WoodBasicA`=MI_WoodBasicA |
| SM_WindowStandardA_Open | `GlassA`=M_EnvGlassUnlit, `WoodBasicA`=MI_WoodBasicA |
| SM_FacadeLrgA_Base | `MI_StoneTrimsheetB`=MI_StoneTrimsheetB_Grey, `MI_StoneWallA`=MI_StoneWallA, `MI_GlassOpaque_Dark`=MI_GlassFacadeA, `MI_StoneStripA`=MI_StoneStripA, `MI_TrimOrnateWoodA`=MI_TrimOrnateBronze, `MI_TrimOrnateWoodA_ncl1_1`=MI_TrimOrnateWoodA_White |
| SM_FacadeLrgA_TopA | `MI_StoneTrimsheetB`=MI_StoneTrimsheetB_Grey, `MI_StoneWallA`=MI_StoneWallA, `MI_RoofSlateC`=MI_RoofSlateC, `Material #1834`=MI_WindowDecoTrim, `Material #1822`=MI_WindowDecoOpaque, `MI_TrimOrnateWoodA`=MI_RoofBitumenA, `Material #2366`=MI_WallStoneBlockD |
| SM_RoofCity_WindowA | `MI_TrimOrnateMetalA`=MI_CopperTile, `MI_GlassSkylightA`=MI_TrimMetalA_Iron, `MI_TrimMetalA_Iron`=MI_GlassSkylightA |

The `slot` label is a UE slot name, not a material object name. It sometimes differs from the material asset (for example RoofCity `MI_TrimOrnateMetalA` -> MI_CopperTile); this is pre-existing UE slot naming, not a GLB rename.

## Source vs GLB diff (material object names)

| Mesh | src / GLB | dropped by GLB | added by GLB | reordered | renamed |
|---|---:|---|---|---|---|
| SM_ThievesDen | 10 / 8 | MI_OldManorPanels, MI_Pipes | none | no (relative order preserved after drops) | none |
| SM_WindowStandardA | 2 / 2 | none | none | yes | none |
| SM_WindowStandardA_Open | 2 / 2 | none | none | yes | none |
| SM_FacadeLrgA_Base | 6 / 6 | none | none | yes | none |
| SM_FacadeLrgA_TopA | 7 / 6 | MI_StoneWallA | none | yes | none |
| SM_RoofCity_WindowA | 3 / 3 | none | none | yes | none |

Reorder details:
- Windows (both): source `[M_EnvGlassUnlit, MI_WoodBasicA]` -> GLB `[MI_WoodBasicA, M_EnvGlassUnlit]`.
- Facade Base: source `[StoneTrimsheetB_Grey, StoneWallA, GlassFacadeA, StoneStripA, TrimOrnateBronze, TrimOrnateWoodA_White]` -> GLB `[StoneTrimsheetB_Grey, TrimOrnateWoodA_White, GlassFacadeA, TrimOrnateBronze, StoneStripA, StoneWallA]`.
- Facade TopA: source `[StoneTrimsheetB_Grey, StoneWallA, RoofSlateC, WindowDecoTrim, WindowDecoOpaque, RoofBitumenA, WallStoneBlockD]` -> GLB `[StoneTrimsheetB_Grey, RoofSlateC, RoofBitumenA, WindowDecoOpaque, WindowDecoTrim, WallStoneBlockD]` (`StoneWallA` dropped).
- RoofCity: source `[MI_CopperTile, MI_TrimMetalA_Iron, MI_GlassSkylightA]` -> GLB `[MI_TrimMetalA_Iron, MI_CopperTile, MI_GlassSkylightA]`.
- ThievesDen: after dropping `MI_OldManorPanels` and `MI_Pipes`, the remaining source order equals the GLB order.

## Current binding vs GLB

Current code is index-based: `game/src/core/level_loader.gd:424-430` loops `s in range(mini(m.get_surface_count(), mat_slots.size()))` and binds `mat_slots[s]`. `mesh_materials.json` is generated from the sidecar slot order by `tools/parse_materials.py:465-480`.

| Mesh | current slot array (short names) |
|---|---|
| SM_ThievesDen | [MI_OldManorWood, MI_WoodFloorA, MI_WallpaperFloralC_5, MI_OldManorTrim, MI_Manor_StoneTrim_Dark, MI_TrimMetalA_brass, MI_OldManorPanels, WorldGridMaterial, MI_WoodBoardsOld, MI_Pipes] |
| SM_WindowStandardA | [M_EnvGlassUnlit, MI_WoodBasicA] |
| SM_WindowStandardA_Open | [M_EnvGlassUnlit, MI_WoodBasicA] |
| SM_FacadeLrgA_Base | [MI_StoneTrimsheetB_Grey, MI_StoneWallA, MI_GlassFacadeA, MI_StoneStripA, MI_TrimOrnateBronze, MI_TrimOrnateWoodA_White] |
| SM_FacadeLrgA_TopA | [MI_StoneTrimsheetB_Grey, MI_StoneWallA, MI_RoofSlateC, MI_WindowDecoTrim, MI_WindowDecoOpaque, MI_RoofBitumenA, MI_WallStoneBlockD] |
| SM_RoofCity_WindowA | [MI_CopperTile, MI_TrimMetalA_Iron, MI_GlassSkylightA] |

The stored arrays are full `/Game/...` material paths; `build/qa/glb_slots.json` contains them verbatim (for example `/Game/Developers/gjasp/SM_ThievesDen` -> its ten paths).

| Mesh | Wrong current surfaces (surface: current -> GLB) | Correct surfaces | Unused current slots |
|---|---|---|---|
| SM_ThievesDen | 6: MI_OldManorPanels -> WorldGridMaterial; 7: WorldGridMaterial -> MI_WoodBoardsOld | 0-5 | 8 (MI_WoodBoardsOld), 9 (MI_Pipes); surface_count=8 |
| SM_WindowStandardA | 0: M_EnvGlassUnlit -> MI_WoodBasicA; 1: MI_WoodBasicA -> M_EnvGlassUnlit | none | none |
| SM_WindowStandardA_Open | 0: M_EnvGlassUnlit -> MI_WoodBasicA; 1: MI_WoodBasicA -> M_EnvGlassUnlit | none | none |
| SM_FacadeLrgA_Base | 1: MI_StoneWallA -> MI_TrimOrnateWoodA_White; 3: MI_StoneStripA -> MI_TrimOrnateBronze; 4: MI_TrimOrnateBronze -> MI_StoneStripA; 5: MI_TrimOrnateWoodA_White -> MI_StoneWallA | 0, 2 | none |
| SM_FacadeLrgA_TopA | 1: MI_StoneWallA -> MI_RoofSlateC; 2: MI_RoofSlateC -> MI_RoofBitumenA; 3: MI_WindowDecoTrim -> MI_WindowDecoOpaque; 4: MI_WindowDecoOpaque -> MI_WindowDecoTrim; 5: MI_RoofBitumenA -> MI_WallStoneBlockD | 0 | 6 (MI_WallStoneBlockD); surface_count=6 |
| SM_RoofCity_WindowA | 0: MI_CopperTile -> MI_TrimMetalA_Iron; 1: MI_TrimMetalA_Iron -> MI_CopperTile | 2 | none |

Current binding is wrong on **17 of 27** GLB surfaces and correct on 10. The ThievesDen failure is exactly the reported one: surface 7 gets `WorldGridMaterial` instead of `MI_WoodBoardsOld` (and surface 6 gets `MI_OldManorPanels` instead of `WorldGridMaterial`).

The raw script compares the full source array, so it prints `surface 8`/`surface 9` for ThievesDen; the runtime loop stops at `surface_count` (8), so those two slots are never bound.

Verbatim stdout excerpt (`build/qa/glb_slots.txt`, SM_ThievesDen):

```text
GLB: game/assets/ue/Content/Developers/gjasp/SM_ThievesDen.glb
  version=2 declared=982576 actual=982576 chunks=[{'type': '0x4E4F534A', 'length': 17532}, {'type': '0x004E4942', 'length': 965016}]
  materials[8]:
    [0] MI_OldManorWood
    [1] MI_WoodFloorA
    [2] MI_WallpaperFloralC_5
    [3] MI_OldManorTrim
    [4] MI_Manor_StoneTrim_Dark
    [5] MI_TrimMetalA_brass
    [6] WorldGridMaterial
    [7] MI_WoodBoardsOld
  mesh[0] 'SM_ThievesDen' primitives=8
    prim  mat  material                    mode        idx  distinct  verts  tris  degT  range  degenerate
       0    0  MI_OldManorWood            TRIANGLES    1368      771    771   456    0      0  no
       1    1  MI_WoodFloorA              TRIANGLES    1416      619    619   472    0      0  no
       2    2  MI_WallpaperFloralC_5      TRIANGLES     729      337    337   243    0      0  no
       3    3  MI_OldManorTrim            TRIANGLES    2016     1202   1202   672    0      0  no
       4    4  MI_Manor_StoneTrim_Dark    TRIANGLES     630      362    362   210    0      0  no
       5    5  MI_TrimMetalA_brass        TRIANGLES     132      119    119    44    0      0  no
       6    6  WorldGridMaterial          TRIANGLES       6        4      4     2    0      0  no
       7    7  MI_WoodBoardsOld           TRIANGLES    8787     5242   5242  2929    0      0  no
  source-vs-GLB: dropped=['MI_OldManorPanels', 'MI_Pipes'] added=[] reordered=False
  current-vs-GLB: dropped=['/Game/MaterialLibrary/Environment/Wood/ML/MI_OldManorPanels', '/Game/Art/Environment/City/Architecture/BeautifulCorner/Materials/ML/MI_Pipes'] added=[] reordered=False
    surface 6: current=/Game/MaterialLibrary/Environment/Wood/ML/MI_OldManorPanels glb=WorldGridMaterial MISMATCH
    surface 7: current=/Engine/EngineMaterials/WorldGridMaterial glb=MI_WoodBoardsOld MISMATCH
    surface 8: current=/Game/MaterialLibrary/Environment/Wood/TrimInterior/ML/MI_WoodBoardsOld glb=None MISMATCH
    surface 9: current=/Game/Art/Environment/City/Architecture/BeautifulCorner/Materials/ML/MI_Pipes glb=None MISMATCH
```

## Name resolution and paths

All **27/27** GLB material names are exact source material object names (`exact=True` 27/27 in `build/qa/glb_slots.txt`): no `.001` suffixes, no case/normalisation changes, no renames. The per-mesh sidecar resolves every GLB name to exactly one full UE path. `materials.json` contains **26/27** of those paths; the exception is `WorldGridMaterial` (`/Engine/EngineMaterials/WorldGridMaterial`), which is an Engine material and is also absent today, so it falls back to `get_material_for_ue()`'s default material in both bindings. `MI_StoneWallA` is globally ambiguous in `materials.json` (two keys: `/Game/MaterialLibrary/Environment/Stone/Wall/ML/MI_StoneWallA` and `/Game/Maps/Prototype/TempAssets/MI_StoneWallA`); the per-mesh sidecar disambiguates it to the former for `SM_FacadeLrgA_Base`. Task 1.6 must resolve through the per-mesh sidecar, not a global basename dictionary.

| Mesh | GLB parsed | Sidecar | `mesh_materials.json` key |
|---|---|---|---|
| SM_ThievesDen | `game/assets/ue/Content/Developers/gjasp/SM_ThievesDen.glb` | `extracted/assets/Developers/gjasp/SM_ThievesDen.materials.json` | `/Game/Developers/gjasp/SM_ThievesDen` |
| SM_WindowStandardA | `extracted/assets/TAT/Content/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA.glb` | `extracted/assets/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA.materials.json` | `/Game/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA` |
| SM_WindowStandardA_Open | `extracted/assets/TAT/Content/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA_Open.glb` | `extracted/assets/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA_Open.materials.json` | `/Game/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA_Open` |
| SM_FacadeLrgA_Base | `extracted/assets/TAT/Content/Art/Environment/City/Facades/SM_FacadeLrgA_Base.glb` | `extracted/assets/Art/Environment/City/Facades/SM_FacadeLrgA_Base.materials.json` | `/Game/Art/Environment/City/Facades/SM_FacadeLrgA_Base` |
| SM_FacadeLrgA_TopA | `extracted/assets/TAT/Content/Art/Environment/City/Facades/SM_FacadeLrgA_TopA.glb` | `extracted/assets/Art/Environment/City/Facades/SM_FacadeLrgA_TopA.materials.json` | `/Game/Art/Environment/City/Facades/SM_FacadeLrgA_TopA` |
| SM_RoofCity_WindowA | `extracted/assets/TAT/Content/Art/Environment/City/Architecture/Roofs/RoofDetails/SM_RoofCity_WindowA.glb` | `extracted/assets/Art/Environment/City/Architecture/Roofs/RoofDetails/SM_RoofCity_WindowA.materials.json` | `/Game/Art/Environment/City/Architecture/Roofs/RoofDetails/SM_RoofCity_WindowA` |

All six paths and sidecars exist. The five `extracted/assets/TAT/...` GLBs are byte-identical (SHA-256) to the runtime copies under `game/assets/ue/Raw/TAT/...`; `SM_ThievesDen`'s runtime copy is byte-identical to its extracted copy (`615edd00d2c362a0029b212eb52f1be68a90beba1917bf62b6b68c09ad452112`). Parsing the extracted copies is therefore valid for the runtime assets.

Raw JSON keys used: GLB `materials[].name`, `meshes[].primitives[].material`, `primitives[].indices`, `accessors[].{bufferView,byteOffset,componentType,count}`, `bufferViews[].{byteOffset,byteStride}`; sidecar objects `slot` and `material`; `mesh_materials.json` is an object keyed by UE mesh path whose values are arrays of full UE material paths.

## Verdict: **GO**

- Material names are preserved exactly on all six assets (27/27 primitives), and every primitive carries an explicit material index. Primitive order and material association are readable for every mesh.
- All index buffers are valid; no primitive is degenerate.
- No mesh needs to fall back to index binding.

Implementation notes for task 1.6:
1. Resolve GLB short names to full UE paths via the per-mesh sidecar; do not use a global basename lookup (`MI_StoneWallA` is ambiguous).
2. Clamp to GLB primitive count, not source slot count: ThievesDen 10 source slots -> 8 surfaces, TopA 7 -> 6. Do not append the extra source slots.
3. `array_mesh/deduplicate_surfaces=true` in all six `.import` files; all 27 primitives have a unique material within their mesh, so no surface merge is expected. Assert the imported `ArrayMesh` surface count and order against the GLB primitive order, since this proof parses the raw GLB and did not run Godot.
4. `WorldGridMaterial` is not in `materials.json`; preserve the existing default-material fallback behavior.
5. Source slots absent from the GLB (OldManorPanels, Pipes, StoneWallA) are not referenced by any primitive; neither binding method can restore them. Treat that as an export/content question, not a binding blocker.

## Evidence

- Script: `build/qa/glb_slots.py`
- Full stdout: `build/qa/glb_slots.txt` (256 lines)
- Machine-readable: `build/qa/glb_slots.json`
- Command: `python3 build/qa/glb_slots.py --out build/qa/glb_slots.json > build/qa/glb_slots.txt`
