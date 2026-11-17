# Guildhall safe-room overhang & wall spotlight fidelity (2026-11-17)

The solid black rectangle visible below the Guildhall safe-room walkway and alley was **not** a landscape visibility hole (`Weightmap_20.png` has no `Visibility` layer) and **not** an unlit shadow or black mesh — `_dict_to_transform()` (`game/src/core/level_loader.gd`) clamped `LandscapeComponent` `scale = [100.0, 100.0, 100.0]` down to `40.0` (`0.4×`), shrinking every `63.0 m` terrain tile to `25.2 m` and leaving a `37.8 m` void gap (`z = -5.9 .. +31.9`) beneath the alley and dumpster. In addition, `tools/parse_tables.py` omitted Blueprint `Template` chain transforms and properties for lights, leaving `BP_WallLightB_C_5` aimed sideways along the wall and `+10°` upward instead of outward into the safe room, while `_build_light()` capped `spot_angle` at `78.0°` instead of the authored `88.0°`.

## Root cause (R1 evidence)

### 1. Landscape scale clamp & alley geometry (`(126.0, 18.56..25, -10.43)` and `(114.5, 18.56, -3.2)`)

- **Landscape Component 12 (`Guildhall_Landscape.tatlevel.json[12]`)**:
  - Authored placement: `pos = [105.1, 10.7, -31.1]`, `quads = 63`, `scale = [100.0, 100.0, 100.0]`, `scale_bias = [0.015625, 0.015625, 0.0, 0.0]`.
  - Weightmap (`Weightmap_20.png`): `GroundA` (`ch 0`), `CobbleA` (`ch 1`), `GrassA` (`ch 2`), `Puddle` (`ch 3`) — **zero `LandscapeVisibilityLayerInfo` layer**.
  - Heightmap (`Heightmap_6.png`): true ground elevation across `z = -12 .. +28` at `x = 114.5 .. 126.0` is `18.559 m` (`10.7 + 7.859`).
  - `_build_one_landscape()` (`game/src/core/level_loader.gd:1618-1623`) called `_dict_to_transform(lc)`, whose `clampf(..., 0.05, 40.0)` truncated `100.0` to `40.0`, yielding `step_x = step_y = step_z = 0.40` instead of `1.00`.
  - Result: Component 12 shrank from `63.0 m × 63.0 m` (`x = 105.1..168.1, z = -31.1..+31.9`, `y = 18.56 m`) to `25.2 m × 25.2 m` (`z = -31.1..-5.9`, `y = 13.84 m`), leaving a `37.8 m` void gap (`z = -5.9..+31.9`) directly under the alley and `SM_GarbageDumpster_garbageDumpster` (`[114.4712, 18.6, -3.1929]`), framed by brick foundation walls (`y = 12.0`) over `tat_sky.gdshader`'s dark nadir (`horizon_color * 0.12`). All `210 / 210` landscape components across `Guildhall_Landscape` (18), `OldManor_P` (128), and `BeautifulCorner_Startscreen_P` (64) share `scale = [100.0, 100.0, 100.0]`.
- **Meshes and decals near `(126.0, 18.56..25, -10.43)`**:
  - The coordinates `(126.0, 18.56..25, -10.43)` lie inside the North building (`x = 111.95..129.95, z = -8.52..-22.52`), where stacked `GB_Floor_6x6` slabs sit at `y = 18.0, 24.5, 31.0, 44.5` (`MI_WoodVarnishAAlignXYZ_Manor` / `T_ManorMarble_D.png`, `tex=true`) along with `SM_Urban_Ext_Wall_*` (`T_WallStoneBlockD_D.png`) and `SM_CrossBeam_3x3` catwalk beams (`y = 22.85`, `z = -8.22` and `-5.22`).
  - No black floor plate, missing-material mesh, or dark decal exists at `(126.0, 18.56..25, -10.43)` or under the dumpster; the single-shot ray in `run_tests.gd:273` from `y = 30.0` stopped on the `GB_Floor_6x6` ceiling/floor slab at `y = 25.00` without reaching the landscape below.

### 2. Source UE wall spotlight vs generated JSON & runtime `SpotLight3D` (`BP_WallLightB_C_5`)

In `extracted/json/Maps/Guildhall/Guildhall_PeripheryA.json` (actor `BP_WallLightB_C_5`, export `[973]`) and `extracted/json/Art/Environment/Lights/Wall/BP_WallLightB.json`:

- `[3220] SceneComponent Default`: `RelativeLocation = (12629.478, -228.0045, 2714.2593)`, `RelativeRotation = (Pitch: 0, Yaw: 174.38843, Roll: 0)`.
- `[3222] SceneComponent LightBaseRoot` (level stub omits transform; template `BP_WallLightB_C:LightBaseRoot_GEN_VARIABLE` -> `BP_Light_Base_C`): `RelativeLocation = (0.0, 19.453066, -1e-6)`, `RelativeRotation = (Pitch: 0, Yaw: 90.0, Roll: 6.46e-14)`.
- `[3223] SceneComponent LightRoot`: level instance overrides `RelativeRotation = (Pitch: 10.0, Yaw: 6.7e-15, Roll: 3.8e-15)` (replacing template `Pitch: -10.0`).
- `[6123] TATShadowFadeSpotLightComponent TATShadowFadeSpotLight` (template): `RelativeRotation = (Pitch: -10.0, ...)`, `Intensity = 5.0`, `InnerConeAngle = 0.0`, `OuterConeAngle = 88.0`, `AttenuationRadius = 900.0`, `LightColor = {R: 177, G: 255, B: 229, Hex: "B1FFE5"}`, `MinDrawDistance = 2500.0..4000.0`, `bUseInverseSquaredFalloff = true`, `IntensityUnits = "ELightUnits::Lumens"`.
- `[3581] SpotLightComponent TATShadowSpotLight`: `OuterConeAngle = 88.0`, `AttenuationRadius = 900.0`, `Intensity = 5.0`, `LightColor = {R: 177, G: 255, B: 229, Hex: "B1FFE5"}`, `bUseInverseSquaredFalloff = true`, `SourceRadius = 20.0`, `SoftSourceRadius = 5.0`, `IntensityUnits = "ELightUnits::Lumens"`. `CastShadows` is omitted on both stub and templates (UE default `true`).

> **Superseded mapping note (light-intensity wave):** the `light_energy` and
> `spot_range` values in this table describe the mapping as it stood during the
> overhang wave. They were superseded by the linear authored-intensity mapping in
> `level_loader.gd` (`LIGHT_INTENSITY_SCALE`, median `15.0` -> energy `1.0`) and
> 1:1 authored metres for range; see `docs/reports/lighting-intensity.md`. The
> evidence below is left as recorded for that wave.

| Property | UE Source (`[3581]`) | Pre-fix `.tatlevel.json` (`[149]`) & Runtime | Post-fix `.tatlevel.json` & Runtime |
|---|---|---|---|
| Position (`m`) | `(126.2758, 27.1426, -2.4736)` (with `LightBaseRoot` `19.45 cm` offset) | `(126.2948, 27.1426, -2.28)` | `(126.2758, 27.1426, -2.4736)` |
| Aim (`UE +X` / Godot `-basis.z`) | `(-0.09778, 0.0, -0.99521)` (outward into safe room) | `(-0.98009, +0.17365, +0.0963)` (sideways & `+10°` up) | `(-0.09778, 0.0, -0.99521)` |
| `Intensity` / `light_energy` | `5.0` Lumens | `5.0` -> `4.20` | `5.0` -> `4.20` |
| `OuterConeAngle` / `spot_angle` | `88.0°` (`InnerConeAngle = 0.0°`) | `88.0°` -> clamped to `78.0°` | `88.0°` -> `88.0°` |
| `AttenuationRadius` / `spot_range` | `900.0 cm` (`9.0 m`) | `9.0 m` -> `22.5 m` | `9.0 m` -> `22.5 m` |
| `LightColor` / `light_color` | `#B1FFE5` (`177, 255, 229`) | `(0.6941, 1.0, 0.898)` | `(0.6941, 1.0, 0.898)` |
| `CastShadows` / `shadow_enabled` | UE default `true` | `false` (`MobileProfile.hero_shadows()=4`, `distance_fade=28..40 m`) | `false` (`hero_shadows=4`, `distance_fade=28..40 m`) |
| `TATShadowFade*` twin | `[6123]` at same pos (default `10.0` in old JSON) | Emitted `[249]`, dropped by `seen_lights` | Filtered at parse & load time (`0` emitted in PeripheryA) |

## Fix (R2)

1. **`game/src/core/level_loader.gd`**:
   - `_build_one_landscape()`: reads raw unclamped `lc.get("scale", [100.0, 100.0, 100.0])` directly to compute `step_x`, `step_y`, `step_z` (`absf(...) * 0.01`, fallback `1.0` if `< 0.05`), while leaving `_dict_to_transform()`'s `clampf(..., 0.05, 40.0)` untouched for non-landscape meshes/decals/lights.
   - `_parse_sublevel_file()`: filters `"TATShadowFade"` crossfade duplicates, `_to_float(l_dict.get("intensity"), 10.0) <= 0.0`, and `l_dict.get("visible") == false` before `seen_lights` deduplication so off lights (`0.0`-intensity car alarms/lamps) cannot steal `seen_lights` or `max_lights` slots.
   - `_build_light()`: raises `spot_angle` upper clamp from `78.0` to `89.0` (`clampf(_to_float(info.get("outer_cone"), 50.0), 18.0, 89.0)`), preserving `88.0°` without allowing `203.68°` outliers to wrap behind a hemisphere.
2. **`tools/parse_tables.py`**:
   - Added cached `Template`-chain property resolution (`_bp_by_type_name`, `_resolve_tpl_chain_props`, `_merged_comp_props`) and `use_templates: bool = False` on `get_world_mat()` (keyed on `(idx, use_templates)` in `world_cache`, default `False` so meshes/markers/doors are untouched).
   - Updated light extraction (branch 3): skips `"TATShadowFade"` crossfade components, merges each export's `Template` chain under level instance overrides (`_merged_comp_props(e)`), skips authored-off lights (`intensity <= 0.0`, `bVisible is False`, `bHiddenInGame is True`), and computes `get_world_mat(idx, use_templates=True)` (plus `level_mat` when present).
3. **Regenerated normalized levels (`make normalize`)**:
   - `Normalized 77 level JSONs -> 137086 mesh instances, 2154 lights` (`138 loaded (32166 meshes), 0 unresolved`).

## Verified counts & measurements

| Check | Before (commit `f1b054f`) | After (R2) |
|---|---|---|
| `LandscapeCollision_12` XZ span | `25.2 m × 25.2 m` (`0.4×`) | `63.0 m × 63.0 m` (`1.0×`) |
| Alley raycast `(114.5, 22 -> 5, -3.2)` on `LandscapeCollision_12` | Missed (`void`, `z = -5.9..+31.9`) | Hit at `y = 18.5594 m` |
| Multi-hit raycast `(126.0, 35 -> 5, -10.43)` on `LandscapeCollision_12` | `y = 13.84 m` (beneath slabs) | Hit at `y = 18.5594 m` |
| `BP_WallLightB_C_5` aim (`-basis.z`) | `(-0.98009, +0.17365, +0.0963)` | `(-0.09778, 0.0, -0.995208)` |
| `BP_WallLightB_C_5` `spot_angle` | `78.0°` | `88.0°` |
| `Guildhall_PeripheryA.tatlevel.json` lights | `TATShadowFade*` + off lights present | `67` active primary lights (`0` `TATShadowFade*`) |
| Total normalized lights (77 `.tatlevel.json`) | `3,479` | `2,154` |

## Automated verification & Visual QA (R5)

### Automated tests (`game/tests/run_tests.gd`, Suite 10)

Added explicit Suite 10 assertions for:
- `LandscapeCollision_12` `ConcavePolygonShape3D` XZ face span (`is_equal_approx(..., 63.0)`),
- multi-hit vertical raycast at `(114.5, 22.0 -> 5.0, -3.2)` hitting `LandscapeCollision_12` at `absf(y - 18.56) < 0.2`,
- multi-hit vertical raycast at `(126.0, 35.0 -> 5.0, -10.43)` hitting `LandscapeCollision_12` at `absf(y - 18.56) < 0.2`, and
- `BP_WallLightB_C_5` `SpotLight3D` aim (`aim.z < -0.9`, `absf(aim.y) < 0.05`) and `is_equal_approx(sl.spot_angle, 88.0)`.

`make test` output:
```text
PASS: Guildhall terrain, floor collision & spawn ground raycast verified (gap_hit_y=25.0, lc12_span=(63.0,63.0), alley_y=18.5593757629395, overhang_y=18.5593738555908, spawn_lights=1, safe_aim=(-0.09778, 0.0, -0.995208), safe_angle=88.0, light=SpotLight3D pos=(126.2758, 27.1426, -2.4736) energy=4.20)
...
SUMMARY: fails=0
```
Zero `SCRIPT ERROR` lines.

`make audit` output:
```text
Manifest TAT entries: 12704
Resolved in CUE4Parse: 12630 (99.4%)
Files written to extracted: 28157
```

### Visual QA screenshots (`/tmp/opencode/`)

- **Before**: `/tmp/opencode/overhang_before.png` (captured before code edits under isolated `Xvfb :99`, `debug_autostart_contract=4`, `W` compass heading from the safe-room catwalk/stairs overlook; reference prior capture `/tmp/opencode/qa_final_light_gap.png`). Shows the shrunk `0.4×` landscape tile cutting off at `z = -5.9` with a large solid black void gap under the stairs, cobblestone plates, and street.
- **After**: `/tmp/opencode/overhang_after.png` (captured with the identical `Xvfb :99` + `xdotool` script after applying R2 and `make normalize`). Confirms the black rectangle is completely gone and continuous `GroundA`/`GrassA`/`CobbleA` landscape terrain (`y = 18.56 m`) renders cleanly across the alley and street.
- `game/project.godot` was restored from `HEAD` (`git diff game/project.godot` empty).

## Caveats & reproduce

- `OldManor_P.tatlevel.json` contains `128` landscape components fixed by the `_build_one_landscape` change, though `mission_controller.gd` currently lists `OldManor_Landscape` (`0` landscapes) rather than `OldManor_P` (out of scope for M1).
- `FTUE_Geometry.tatlevel.json` still retains `12` `TATShadowFadePointLightComponent` entries from a `LevelInstance` merged before its referenced sublevel regenerated in single-pass alphabetical order; `level_loader.gd` skips `"TATShadowFade"` at load time regardless.
- Untracked `extension_api.json` remains in the workspace root (pre-existing, outside M1).

Reproduce:
```bash
make normalize
make test
make audit
```
