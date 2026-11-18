# TAT-2 Visual-Fidelity Wave Report (Phases 1–3)

- **Date**: 2026-11-18
- **Repo / Branch**: `/home/john/Projects/TAT-2` (`main`)
- **Engine / Renderer**: Godot `4.7.2.stable.flathub` — Forward+ / Jolt
- **Vulkan Live QA Hardware**: `Vulkan 1.4.357 - Forward+ - NVIDIA GeForce RTX 4070 Laptop GPU` (via `Xvfb :99`, `1280x720`)
- **Reference Screenshots**: `/home/john/Pictures/Screenshots/` (30 official UE5 3840x2160 captures)
- **Verification**:
  - `make test` (headless, 35 numbered suites): `SUMMARY: fails=0`, `SCRIPT ERROR = 0`
  - Real Vulkan Forward+ test run (`build/qa/make_test_vulkan_vf.log`): `SUMMARY: fails=0`, `SHADER ERROR = 0`, `SCRIPT ERROR = 0`
  - `make audit`: `12630 / 12704 (99.4%)`, `Files written to extracted: 29784`

---

## 1. Initial Audit of Prior Work

All committed claims prior to this wave were verified against disk and live runs:

| Commit | Claimed Scope | Verification Result |
|---|---|---|
| `7458198` | `ue_rotator_to_mat3` m12 sign shear fix + Gram-Schmidt orthonormalization | **PASS** — `tools/parse_tables.py:69` matches `weather_profile.gd:173`; Suite 27 verifies all `146,563` generated bases orthonormal across `73` clean `.tatlevel.json` files. |
| `8f07b7d` | Extractor startscreen landscape (20 PNGs) + `WindowPanels_Oldmanor_*` (4 PNGs) | **PASS** — `+24` PNGs verified in `extracted/assets` and `game/assets/ue/Raw` (`2,251` cumulative). |
| `754bbb6` *(note: cited `9d4e804` is absent from git; all cited material DB work is in `754bbb6`)* | Authored texture families, `1,571` materials / `1,367` albedo, `+10` PNGs, zero map/eye/glass leaks | **PASS** — `2,261` PNGs total, `1,571` materials / `1,367` albedo; Suite 28 passes with 0 leaks. |
| `7737ed1` | UE `Overlay`/`Multiply`/`Desaturation` vectors modulate albedo; `BlackUnlitMaterial` unshaded | **PASS** — Suite 29 passes (`MI_TrimMetalA_brass`, `MI_TrimMetalA_Iron`, `BlackUnlitMaterial`). |
| `6783c2d` | `mesh_materials.json` in GLB primitive order (`2,027` GLB + `18` sidecar = `2,045`); fixes `SM_ThievesDen` surface 7 & window frame/glass swap | **PASS** — `docs/reports/glb-material-slot-proof.md` (GO verdict) verified: `6/6` GLB byte sizes + SHA-256 (`615edd00...`), live `python3 build/qa/glb_slots.py` reports `27/27 MATCH`; Suite 30 passes. |

---

## 2. Phase 1 Implementation & Red-Proofs

### Phase 1(a) — Per-component `OverrideMaterials`, `bVisible:false`, `SplineEditorMesh` (`24cac7e`)
- **Parser (`tools/parse_tables.py`)**:
  - Preserves slot-indexed `override_materials` (retaining `""` for unoverridden `None` slots, remapping to GLB primitive order, trimming trailing `""`).
  - Resolves `MaterialInstanceDynamic` refs via `Properties.Parent.ObjectPath` (`2,038` refs).
  - Includes `/Maps/` in `build_bp_file_index()` so all `683` `BPP_*` Packed Level Actor template overrides resolve.
  - Filters `bVisible: false` and `SplineEditorMesh`, and deletes stale empty `.tatlevel.json` outputs (4 stale `*_Audio.tatlevel.json` removed; `73` clean levels regenerated).
- **Runtime (`game/src/core/level_loader.gd`)**:
  - Applies per-surface overrides via duplicated cached `Mesh.surface_set_material(s, mat)` instead of whole-mesh `material_override` (preserving multi-slot meshes and base cache immutability).
- **Tests & Red-Proof**: Suite `31a`–`31g` passes (`Box_83DC6DA6` slabs, `SM_LightSmC_Iron` None-slot preservation, 4-slot `SM_Storefront_Facade_1200`, MID Parent resolution, `BPP_*` overrides, hidden desk absent, `SplineEditorMesh=0`, runtime per-surface binding). Red-proof verified prior to commit `24cac7e`.

### Phase 1(b) — Emissive `CustomPrimitiveData` MultiMesh (`d0f895a`)
- **Parser (`tools/parse_tables.py`)**: Emits 5-float `cpd` (`[UseMoonlight, EmisMultiply, R, G, B]`) for `M_EmissiveBase` / `MI_EmissiveShape*` / `MI_MoonshapeEmissive` instances (`1,293` instances across regenerated levels; non-emissive `Firewood_01` and `SM_WardBox` excluded).
- **Shader & Runtime (`game/src/core/tat_emissive_cpd.gdshader`, `game/src/core/level_loader.gd`)**:
  - Packs `(R, G, B, EmisMultiply)` into `MultiMesh.use_custom_data = true` (`INSTANCE_CUSTOM`) with `unshaded, cull_back, depth_draw_opaque` and `discard` when `EmisMultiply <= 0.001`.
  - Respects `hidden_in_game` (`visible = false`, `GI_MODE_STATIC`) and zero collision for emissive shapes.
- **Tests & Red-Proof**: Suite `32a`–`32c` passes on both headless dummy and real Vulkan `RenderingDevice` (verifying `get_instance_custom_data()` readback on GPU). Red-proof verified prior to commit `d0f895a`.

### Phase 1(c) — `tat_glass.gdshader` Authored Albedo + Opacity Map (`32d6a52`)
- **Parser (`tools/parse_materials.py`)**: Resolves `"opacity"` from `TextureStreamingData` / `ReferencedTextures` (`_o`, `_opacity`), raising materials with opacity maps to `123` (including `M_GlassPanels` / `MI_GlassPanels` -> `WindowPanel_O.png`, `MI_GlassPanels_oldmanor` -> `WindowPanels_Oldmanor_O.png`, `M_Glass` -> `T_StorefrontGlass_O.png`).
- **Shader & Runtime (`game/src/core/tat_glass.gdshader`, `game/src/core/level_loader.gd`)**:
  - New Forward+ spatial glass shader (`blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx`) sampling authored `albedo_tex`, R-channel `opacity_tex` (verified grayscale RGB with `A=255` in UE exports; falls back to `alb.a` for `_DA` textures like `T_StainGlassC_DA.png`), optional `normal_tex`, `orm_tex`, `albedo_tint`, `opacity_scale`, `roughness_val`, `metallic_val`, `specular_val`, and authored emissive.
  - Added `Image.load_from_file` -> `ImageTexture` fallback in `_load_tex()` so newly extracted PNGs without `.import` sidecars (`WindowPanel_{D,N,O,ORM}.png`, `WindowPanels_Oldmanor_{D,N,O,ORM}.png`) load deterministically.
  - Removed both flat-blue hardcoded fallbacks in `get_material_for_ue()` (`-> Material`); opaque glass materials (`MI_GlassPanels_Opaque`, `MI_GlassPanels_PeriphBuilding`, `MI_WindowGlassOpaque`) remain opaque `StandardMaterial3D` with authored textures.
- **Tests & Red-Proof**:
  - Suite `33a`–`33c` passes.
  - **Red-proof**: Temporarily injected `op_scale = 0.0` in `_build_glass_material()`; `make test` failed with `FAIL: 33b tat_glass.gdshader bindings (MI_GlassPanels=false oldmanor=false M_EnvGlassUnlit=true)` (`SUMMARY: fails=1`, exit code 1). Restored line; `make test` returned `SUMMARY: fails=0`.

---

## 3. Phase 2 Scene & UI Implementation

### Phase 2A — Den Exit Door, Lighting, Footprints, Map Table (`0361577`, Suite 34)
1. **Den exit door**: Wired `BP_ThievesDenExitDoorInteractable_C` (`StaticMeshActor_243`, pivot `[1.8171, 38.8279, 276.4258]`) from `door_spawns` / `door_spawn_records` into `_spawn_swinging_doors()` (`SwingingDoorScript`), reusing `SM_DoorInaccessibleA` with authored leaf offset `[-1.22, 0, 0]`, yaw 180°, and scale `[1.0, 0.8925, 1.0]` (`rel_scale` support added to `swinging_door.gd`). Static duplicate `SM_DoorInaccessibleA` excluded (`0` static duplicates; Thieves' Den `meshes=283`, `swinging doors: 1`).
2. **Den lighting & props**:
   - Reduced hand fill lights from `7.7` total (`1.4 + 1.8 + 1.6 + 1.4 + 1.5`) to `1.90 <= 2.0` (`0.35 + 0.65 + 0.35 + 0.25 + 0.30`), with zero invented red.
   - Set dark ambient base (`ambient_light_color = Color(0.06, 0.08, 0.12)`, `ambient_light_energy = 0.12`).
   - Added one interior `ReflectionProbe` (`ThievesDenReflectionProbe`, `size = (20, 10, 16)`, `UPDATE_ONCE`, `AMBIENT_DISABLED`).
   - Fixed trunk decoration prop paths to real cooked GLBs (`Art/Gameplay/Loot/LootMajor/{FabergeEgg/SM_FabergeEggA,FigurineOwl/SM_StatueOwlA,HugeJewel/SM_HugeJewel}`) loaded via `level_loader` with authored PBR materials — zero purple/placeholder spheres.
3. **Footprints**: `VfxManager.spawn_footprint_decal()` loads authored `res://assets/ue/Raw/Art/UI/Icons/T_Decal_Footstep.png` (256x256 white-on-black mask with `A=255`), converts RGB luminance into alpha in a cached `ImageTexture`, and sets `emission_enabled = false`.
4. **Map table**: Removed `+0.75` Y offset from `desk_positions[0]` (`SM_Map_ThievesDen` is already at tabletop `Y = 41.1137`), exempted `M_MapBuilding_*` from the non-map 3D `mapbuilding` albedo strip in `level_loader.gd`, and bound `M_MapBuilding_OldManor` and `M_MapBuilding_GuildHall` onto `SM_MapBuilding_OldManor` / `SM_MapBuilding_GuildHall` seated at `Y = 41.134`.

### Phase 2B — Startscreen Camera, Settings UI, Mission Prep UI (`2da2ebe` + live QA polish, Suite 35)
1. **Startscreen camera (`game/src/ui/main_menu.gd`)**: Positioned `_menu_cam` at authored `CineCameraActor_0` (`MainMenu.json`) eye `(-12.7196, 0.4566, 14.6089)`, pitch `+13.8°`, yaw `-46.335075°`, `vFOV 48.03°` (derived from `FieldOfView 76.758446` at `16:9`). Also fixed missing `scene_root.add_child(loader)` so `LevelLoader._ready()` loads `materials.json` and `mesh_materials.json` for all `3,115` Startscreen meshes (and bumped `light_budget` to `32` for all `22` authored lights). Added `set_anchors_preset(Control.PRESET_FULL_RECT)` in `_ready()`.
2. **Settings (`settings_ui.gd`, `save_system.gd`, `thief_character.gd`)**:
   - Styled with teal Art Nouveau palette (`TEAL_PANEL_BG`, `TEAL_GROUP_BG`, `TEAL_BORDER`, `TEAL_ACCENT`), authored labels from `ST_Settings.json`, and 6 grouped cards (`Mouse`, `Gameplay`, `Display`, `Graphics Quality`, `Volume`, `Controls`).
   - Wired persisted `SaveSystem.data["settings"]` (`mouse_sensitivity`, `invert_y`, `sprint_toggle`, `reduced_camera_bounce`, `fov`, `vsync`, `master_volume`, `fullscreen`, `render_scale`) into `SaveSystem.apply_saved_settings()` on startup and `ThiefCharacter.apply_saved_settings()`.
3. **Mission Prep (`mission_prep_ui.gd`, `game_data.gd`)**:
   - Loaded all `11` authored `CDT_Missions` / `DT_Missions_*` rows (`GameData.get_all_missions()`), resolving titles, `{MatchDurationInMinutes}` descriptions, per-difficulty durations, and `ObjectiveDisplayImage` icons (7 authored icons; 4 rows without authored `ObjectiveDisplayImage` cleanly hide the icon slot rather than inventing one).
   - Wired authored location artwork (`T_Map_OldManor.png`, `MapSplash_Guildhall.png`, `T_loadingScreen_1.png`, `T_loadingScreen_2.png`).
   - Live Vulkan QA caught top-edge clipping on 720p and `SK_ThiefNisha__Head.glb` +1.45 m vertical double-offset; both fixed (`PRESET_TOP_LEFT` at `(36, 68)` and `head_node.position = Vector3.ZERO`) and re-captured.

---

## 4. Phase 3 Live Vulkan Visual QA vs Reference Screenshots

All captures rendered on real Vulkan Forward+ (`NVIDIA GeForce RTX 4070 Laptop GPU`, `1280x720`) via `build/qa/capture_vf.sh` (`SHADER ERROR = 0`, `SCRIPT ERROR = 0`).

| Scene | Live Vulkan Capture (`build/qa/`) | Official Reference (`/home/john/Pictures/Screenshots/`) | Visual Comparison & Observations |
|---|---|---|---|
| **Startscreen** | `vf_startscreen.png` | `Screenshot_20261118_002211.png` | **Close framing match**: CineCamera eye/pitch/vFOV matches car fender (bottom-left), MacNeish Jeweller sign, wooden scaffolding, crates/sacks, cobblestone magenta puddle reflection, and right-aligned logo/menu. Minor delta: upper neon arch CPD shapes bloom bright red-orange compared to UE's thinner orange-gold tube glow (UE `EmisMultiply` bloom curve). |
| **Settings UI** | `vf_settings.png` | `Screenshot_20261118_002236.png` | **Strong match**: Teal Art Nouveau frame, `[Q]/[E]` tabs (`GENERAL / VIDEO / AUDIO / CONTROLS`), grouped `MOUSE` + `GAMEPLAY` cards, teal slider/values, `[ESC]` back button over Startscreen backdrop. |
| **Mission Prep** | `vf_mission_prep.png` | `Screenshot_20261118_002356.png`, `Screenshot_20261118_002400.png` | **Strong layout & art match**: `MapSplash_Guildhall.png` in Location card, `T_missionIcon_WarburgEffigy.png` + `Vault Heist` + 120 min description + all 11 `CDT_Missions` rows in dropdown, Contract card, ThiefNisha head seated cleanly on shoulders. Noted gap: ThiefNisha preview stage uses untextured default GLB material (character texture binding on prep stage is a follow-up). |
| **Thieves' Den (Wide)** | `vf_thieves_den.png` | `Screenshot_20261118_002251.png`, `Screenshot_20261118_002257.png` | **Strong mood & material match**: Dark attic ambiance, frosted blue-lit arched window with `WindowPanel_D` + `WindowPanel_O` mullions casting window-frame shadows across floorboards, warm rolltop desk & map table on right, authored Fabergé egg (no purple sphere). |
| **Thieves' Den Map Table** | `vf_thieves_den_map_table.png` | `Screenshot_20261118_002339.png`, `Screenshot_20261118_002348.png` | **Seated & textured**: Both `SM_MapBuilding_OldManor` and `SM_MapBuilding_GuildHall` rest directly on the Kilcairn map (`Y = 41.134`, +0.75 offset removed) with authored `M_MapBuilding_*` textures. Minor delta: tokens at `scale = 0.08` are smaller than UE reference (`~0.22-0.25`); candle flame uses placeholder sphere particles (Niagara VM blocked). |
| **Thieves' Den Exit Door** | `vf_thieves_den_exit_door.png` | *None in `/home/john/Pictures/Screenshots/` (skipped comparison)* | Door wired as `SwingingDoorScript` reusing `SM_DoorInaccessibleA` with 0 static duplicates (verified in Suite 34a); corner is deeply shadowed under dark ambient + authored spot layout. |
| **Guildhall** | `vf_guildhall.png`, `vf_guildhall_street.png` | `Screenshot_20261118_002425.png`, `Screenshot_20261118_002445.png`, `Screenshot_20261118_002535.png` | **Verified PBR + shaders**: Safe-room stone slabs (`MI_FloorStoneBlockF` via OverrideMaterials), wooden crate/map, blue wall lantern (`MI_LightSmGlassA_Blue`), cobblestone/moss landscape blend, starry night sky, iron railings, and translucent glass doorway (`tat_glass.gdshader`) compile and render cleanly. |
| **Old Manor** | `vf_old_manor.png` | *None in `/home/john/Pictures/Screenshots/` (skipped comparison)* | **Capture verified; reference comparison skipped (0 Old Manor shots in `/home/john/Pictures/Screenshots/`)**: Slate roof normal/ORM shading, wood decking, and emissive green manor windows render with 0 shader errors. |

### Skipped / Missing Reference Count
- **Official screenshots inspected**: 30 PNGs in `/home/john/Pictures/Screenshots/` (covering Startscreen, Settings, Thieves' Den, Wardrobe, Map Table, Mission Prep, and Guildhall).
- **Scenes lacking official reference screenshots**: `2` (`Old Manor` and `Thieves' Den Exit Door` close-up) — live Vulkan renders were captured into `build/qa/` and verified shader-clean, while visual diff comparison against UE reference was skipped and documented above.
- **Unauthored `CDT_Missions` icons**: `4 / 11` rows (`Mission.Example.Multi`, `Mission.Example.Clue`, `Mission.Tutorial.ThievesDen` have empty `ObjectiveDisplayImage`, plus `0` invented icons).
