# Track C — materials, NPR/SNN, X-ray, weather

Date: 2026-11-21
Repo: `<repo>` (`main`)
Engine: Godot `4.7.2.stable.flathub` — Forward+ / Jolt 60 Hz
Commits: `2d86930` (C5 + teardown), `79820d6` (#11), `b9ad345` (C1/C2/C3), `e7390d2` (M2 harness)

## Gate summary

| Gate | Result |
|---|---|
| `make audit` | exit 0 — all 7 groups fresh, `errors.log` clean |
| `check_uid_duplicates.py game --json` | 0 errors / 0 warnings |
| `check_scripts_compile.gd` | 55 checked / 0 broken |
| `run_tests.gd` | `SUMMARY: fails=0`, 0 material fallbacks, 0 leaks |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0`, 0 leaks |
| `probe_leak.gd` | 0 ObjectDB / 0 resources |
| `probe_ftue.gd` | 10 sublevels, 35,397 shapes, 0 dropped, PASS |
| `probe_scene_variants.gd` | 104 selected, stable, varies by seed, PASS |
| `probe_niagara.gd` | 3,695 / 3,695 placements, 37 systems, PASS |
| `probe_scene_variant_apply.gd` | Never/Always, deterministic chance, quest tag, per-source building selection PASS |
| `probe_xray.gd` | authored colours, depth-disabled shader, toggle PASS |
| `probe_npr.gd` | camera quad, authored-default off, NPR/SNN toggles PASS |
| `probe_weather.gd` | 16 rain columns, 16 hidden under roof, lens on/clear off, fog volume PASS |
| E2E unmasked | 212 passed / 44 failed / 0 BOOT / 0 SCRIPT ERROR (baseline 210/46) |
| Vulkan captures | `build/qa/c1_post_*.png`, `c2_xray_*.png`, `c3_*.png`; 0 SHADER ERROR |

## C5 — material fallback warnings to zero

`run_tests` baseline: 37 `[level_loader] material fallback` warnings across 19 paths.
Final: **0 warnings**, and Guildhall `fallback_material_count == 0` is asserted in suite 11.

Root causes fixed:

1. **Base `UMaterial` defaults only in `CachedExpressionData`.** `M_DarkGrey`,
   `Chrome`, `M_DefaultEmissive_Blinking` had no `ScalarParameterValues` /
   `VectorParameterValues`. `parse_materials.py` now pairs RuntimeEntries groups
   0/1/3/8 with `ScalarValues`, `VectorValues`, `TextureValues`,
   `StaticSwitchValues`. Only mapped PBR/emissive/colour names are admitted;
   master-material `Overlay`/`Multiply` defaults are excluded so authored HDR
   tints (MI_JeweledKnife x2.0) do not get halved.
2. **Tint name normalization.** `"Base Color"` / `DefaultBaseColor` now normalize
   to a base-colour vector; `MI_Solid_Blue`, `MI_DefaultRig_DarkGrey`,
   `Chrome`, `M_DarkGrey`, `M_Solid`, `M_BasicGrey` bind authored values.
3. **Explicit texture parameters.** An authored `Albedo`/`Diffuse`/`Base Color`
   parameter wins over stem suffix heuristics, fixing `T_TeleScope_A` (was
   rejected as a `_a` mask) and `Web_Fogy_diff`.
4. **Material extraction was name-filtered.** The extractor now queues
   case-insensitive `MI_`/`M_`/`Mi_`, every `/Materials/` and `/MaterialLibrary/`
   package, `/Developers/`, EngineMaterials/BasicShapes, and every material
   referenced by a mesh sidecar. `meshes` now runs before `materials`;
   `materials --overwrite` keeps filter changes effective; `materials_index.json`
   is authoritative for the parser. This brought in `Mi_Blackjack`,
   `T_LightSm_SconceA_Brass`, CobwebFogy/BaseMaterial and 100+ referenced
   textures such as `WoodBoardsOld_D`.
5. **Texture extraction gap.** `Textures()` now reads `materials_index.json`,
   explicit texture parameters, `CachedExpressionData.ReferencedTextures` and
   `TextureStreamingData` names. 104 previously missed textures were extracted
   and reimported.
6. **Authored emissive-only is not a fallback.** `MI_PowerLight_On`,
   `M_DefaultEmissive_Blinking`, `MI_PowerLight_Off` bind their emissive colour
   and a near-black base; no warning.
7. **Curb splines.** `_build_one_curb_ribbon` resolves the spline mesh's authored
   slot 0 from `mesh_materials.json` instead of passing the mesh path as a
   material.
8. **Engine carriers.** `BasicShapeMaterial` is dumped and parsed (Color .9,
   Roughness .6407); `WorldGridMaterial` binds the authored
   `T_Default_Material_Grid_M/N`. Per the user decision the grid is reproduced
   exactly, so the eight Engine actor overrides render as the shipped grid, not
   as a fallback.

Parser safety: a fallback-ranked albedo is dropped when a tint is the only
authored signal and there is no texture stream/parameter (flat PBR). The
category-fallback cap remains 0.

## #11 — SceneVariant overrides

Implemented:

- `parse_tables` emits `spawn_elements` (`kind`, `pos`, `element_tag`,
  `spawn_group`, `source`) and `swinging_doors[].element_tag` from the authored
  `_sceneRequirement` / `SceneRequirement`.
- `LevelLoader.apply_scene_variant_overrides`: global map variants plus
  per-source (LevelInstance building) variants selected with the run seed.
  Exact authored tags win; untagged spawners are class-mapped and counted as
  `class_mapped`. `Locks.Doors` becomes a deterministic `scene_locked` state
  (`Always`/`Never`/`OverrideChance`); presence categories suppress matching
  spawns. `Lights`/`Windows` remain unmapped because no per-spawn tag index
  exists.
- `GameState.active_map_seed` is initialized from map+contract and
  `active_scene_variants` is populated in `mission_controller.start_contract`.

Evidence: `probe_scene_variant_apply` (40 doors deterministic 32/40 for seed
4242, different for 9999; Never=0 locked; Quest `Always` keeps the spawn;
per-source Apartment_Balcony variant locks 8/20 with no global IDs).

Limit: the shipped Guildhall/OldManor sublevels carry authored tags only on
quest/vault spawners (6 quest, 2 door records), and the apartment/building SV
overrides live on maps not loaded as missions. The mechanism is therefore
mostly a no-op on the current map set; it is not silently guessing. Chance
semantics that cannot be recovered from cooked data are documented
`APPROXIMATE`.

## C1 — OSE.NPR / OSE.SNN

Files: `game/src/core/ose_renderer.gd`, `game/src/core/tat_npr.gdshader`.

- Camera-child quad at the near plane, invisible by default; no shadow/GI.
- Ink: depth + normal relative edge term (raw depth; Godot 4.7 spatial
  fragment does not expose `INV_PROJECTION_MATRIX` in this path).
- SNN: depth-aware joint blur + HSV shift + 7-band value quantization.
- Authored MPC_Painterly defaults: HSV .65, Depth 1.25, Hue .55,
  Effect Intensity **0.0 (off)**, thresholds 12.5/35 m.
- Toggles: `F6` NPR, `F7` SNN; settings not persisted yet (M6 UI work).
- Captures: `build/qa/c1_post_off.png`, `c1_post_npr.png`, `c1_post_snn.png`.
- The shipped painterly path is a material-layer brush mask; the screen-space
  pass is an explicit approximation, documented in the shader header.

## C2 — OSEXray

Files: `game/src/core/xray_overlay.gd`, `game/src/core/tat_xray.gdshader`.

- `render_mode depth_test_disabled`, unshaded, category colour + Fresnel
  highlight; `material_overlay` keeps the real PBR pass intact.
- Authored `TATXrayComponent` values:
  guard `(0.1094,0,0.0044)` + highlight `(5,0,0)`, 25 m;
  loot `(1,.4514,0)` + highlight `(1,.5775,0)`, 20 m;
  clue `(0,.9583,.0319)` + highlight `(.0076,1,.1571)`, 15 m;
  player grey `.5677`, no limit.
- Guard/loot/clue/world-pickup expose `set_xray_highlight`; thief vision drives
  the group. `xray_target` marks the supported nodes.
- Captures: `build/qa/c2_xray_off.png`, `c2_xray_loot.png`, `c2_xray_guard.png`
  (opaque wall in front; silhouette visible only when enabled).

## C3 — weather

- **Roof rain:** `WeatherVisuals.make_rain` is now a 4x4 grid of 15 m rain
  columns; `update_rain_occlusion` casts one upward ray per column every 250 ms
  and hides columns under a roof. `mission_controller._process` calls it.
  Probe: 16/16 columns hidden under a 70 m roof, 16/16 shown after removal.
  Captures: `c3_rain_roof_inside.png`, `c3_rain_outside.png`.
- **Lens drops:** `tat_lens_rain.gdshader` + `make_lens_rain`, using
  `T_RainDropsPacked.png` and authored `PPMI_RainDropsOnLens` values
  (tiling 2.0, speed .25, mask edge .2, falloff .1, normal strength .05).
  Gated by the same rain preset; clear presets return null.
- **Local volumetric:** `Guildhall_LocalVolumetric` is now a Guildhall sublevel.
  `_build_fog_volumes` turns its authored cubes into `FogVolume` +
  `FogMaterial` (Color .5, EdgeFalloff .75, emissive (.427,.354,.5)).
  UE's `Global Multiplier .05` is a material multiplier, not extinction; ×20 is
  calibrated from the capture so density = 1.0 reads visibly.
  Capture: `c3_fog_volume.png`.
- **Clouds:** `Guildhall_Clouds` is a `/Volumetrics/Tools/CloudCompositing`
  authoring layer: 4 `BP_CloudMask_Object_C` with only a SceneRoot + MID, no
  meshes; the generator writes `TextureRenderTarget2D`s. It is intentionally not
  loaded as world geometry. The visible cloud look remains the procedural
  `tat_sky.gdshader` layer driven by `MI_VolumetricCloud_*` coverage/colour.

## Residuals

- 44 E2E failures remain, all in the documented milestone buckets (M2/M3/M4/M6);
  T3-19 and T4-09 now pass vs the baseline. No new failure IDs.
- #11 chance semantics and the Lights/Windows mapping are not recoverable from
  cooked data; exact-tag application is implemented and tested.
- Fog density ×20 is a calibrated approximation; tune with a Guildhall capture.
- NPR raw-depth edge scale and the screen-space SNN are approximations of the
  authored material-layer painterly path.
- `Guildhall_Clouds` is tool-only; do not add it as a sublevel.
