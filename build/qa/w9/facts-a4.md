# W9-P1 / A4 — fact sheet: environment & grade, light plan, prep composition, stale scorecard rows, capture harness

Lane: A4 investigation (read-only). Worktree `/home/john/Projects/TAT-2-rem-w9-p1`,
branch HEAD `c2a1cd8` (`docs(w9): P0 capture evidence, perf matrix, scorecard closure`).
No file was written except this one. No Godot, no producer, no `parse_*.py`, no git write.
`game/data/generated` is a symlink to `/home/john/Projects/TAT-2/game/data/generated`
(read-only from here); `game/data/expansion/` is tracked.

**Working-tree state at read time (08:30):** `build/qa/w9_capture.gd` is modified but
uncommitted (`git status --short`: `M build/qa/w9_capture.gd`, +46 lines) — the lead added
`_all_nodes`, `prep_noperiph` and `prep_ledge` (§6.5) and has already run them
(`build/qa/w9/logs/cap_p1_diag_*.log`). Line numbers for that file below are the
**current 310-line working copy**; the committed `c2a1cd8` version is 265 lines and has
none of those three additions. `git diff --stat -- game/` is empty, so every `game/` line
number in this sheet is unaffected.

Measurements that this sheet explains (do not re-derive):
`build/qa/w9/p0-report.md:13-40` (capture outcomes), `:55-112` (per-shot S1–S6),
`build/qa/w9/audit-report.md:64-74` (`W9_ENV` lines), `:76-83` (AO A/B).

---

## 0. The levers in one screen

1. The **Environment is never created in `level_loader.gd`**. Mission: `mission_controller.gd:246-296`
   (`_setup_environment`). Prep: `mission_prep_ui.gd:656-739` (`_build_stage`). Gameplay grade:
   `weather_profile.gd:875-1061` (`apply_environment`). `level_loader.gd` only *finds* the
   `WorldEnvironment` to attach a LocalExposure LUT (`:6115-6169`) and builds `FogVolume`s (`:4104-4150`).
2. **Interior live grade (Guildhall = preset `gloomy`):** AGX, exposure **1.150**, ambient **0.16**,
   glow 0.12672, SSIL on + SSAO on, fog 0.0048/m + height 0.0321/m, background energy 2.0.
   Exposure: `weather_profile.gd:121,998-1000`; ambient: `:104-105,112,682-686,965-968`.
3. **Prep live grade:** AGX (not ACES), exposure **2.600**, ambient **1.800**, glow 1.0,
   sky background energy 0.18, SSIL forced off, SSAO on. `mission_prep_ui.gd:84-86,101,663,688,692,696-701`.
   The `2.6` and `1.8` are live; the "ACES" label is **stale** — `weather_profile.gd:999` overwrites the
   stage's ACES with AGX for the night preset (`midnight_clear_mission_lobby`), and the capture log
   confirms `tonemap=4` (= AGX).
4. **The room bubble plan is `level_loader.gd:5147-5223`** (`plan_light_selection`), 16 m cells
   (`:333`), budget `MobileProfile.DESKTOP_MAX_LIGHTS = 160` (`mobile_profile.gd:14`, applied at
   `level_loader.gd:6314-6315` / `:6380-6381`). Guildhall load: authored 914 → kept 159 generic +
   1 rect = 160, forced 7, hero shadows 6, rooms 152/187 (`docs/reports/remediation-20261125/T07-render.md:84,111`).
5. **Unselected lights get no node at all** — there is no dimming/clamp path. Selected energy is
   `light_energy_for_intensity(raw)` (`level_loader.gd:301-307`), assigned at `:6616` (spot) and
   `:6627` (omni); the *same* function feeds the ranking score (`:6456-6466`), so a naive per-node
   multiplier would desync selection from rendering.
6. **Prep stage geometry behind the frame = `MissionLobby_Geo3` (367 meshes, 12 lights) +
   `MissionLobby_Periphery` (1,740 meshes, 10 lights)** — `mission_prep_ui.gd:704-709`, loaded with
   `max_lights=64`, `generate_collision=false`. Sky *is* built (`:685`, `weather_visuals.gd:414-434`)
   but re-graded to `background_energy_multiplier 0.18` (`:701`); the "no sky" is occlusion, not absence.
7. **`prep_skyline.json` is consumed only by `mission_prep_ui.gd:926-946` / `:826-889` and two tests**
   (`game/tests/test_t05_ui_contract.gd:170-188`, `game/tests/test_w7v_ui_acceptance.gd:21,197,242-252`).
   Placement is data-only (azimuth/distance/base_y/yaw/scale) at `:853-877`; band `[0.65, 0.98]`
   (`:123-124`) is enforced only by test P14, measured 0.746–0.954 (`T05-ui.md:81`).
8. **The two stale scorecard rows** are `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md:84`
   (V4-07, `DELTA`) and `:92` (V6-03, `N/A-route`); row format and §5 are quoted verbatim in §5.
9. **The capture harness** supports 9 modes (`prep`, `prep_nosky`, `prep_noui`, `upper_foyer`, `foyer`, `saferoom`,
   `foyer_sweep`, plus the uncommitted `prep_noperiph` / `prep_ledge`); the only
   environment lever it exposes is `TAT2_AO` (plus inherited `TAT2_GI`, `TAT2_LIGHT_BUDGET`,
   `TAT2_SHADOW_HEROES`, `W9_QA_OUT`). There is **no exposure override** in the harness.
10. **Ownership fact (brief, `build/qa/w9/W9_BRIEF.md` §File ownership):** A4 = `level_loader.gd`
    environment/light/weather functions only, `mission_prep_ui.gd`, `prep_skyline.json`, V4-07/V6-03.
    `mission_controller.gd` is **P2**; `weather_profile.gd` is **not named in the table at all**.

---

## 1. Environment / exposure code

### 1.1 Who creates and grades the Environment

| site | lines | what it does |
|---|---|---|
| `game/src/missions/mission_controller.gd` `_setup_environment()` | **246-296** | `WorldEnvironment.new()` + `Environment.new()` at 247-248; `_apply_fallback_environment` (585-599); moon node; `WeatherProfile.apply_environment(e, moon, wpreset)` at 261; `WeatherVisuals.apply_sky(e, wpreset, moon)` at 262; `MobileProfile.apply_environment(e)` at 263; Guildhall-only volumetric fog 272-277; `add_child(env)` 278; moon 281; then 5 hand-fill passes 282-287 |
| `_apply_fallback_environment(e)` | **585-599** | ACES, background BG_COLOR, ambient 0.38, fog 0.008, glow 0.65/0.22 |
| `_apply_fallback_moon(moon)` | **601-605** | rotation, colour, energy 0.55, `shadow_enabled = true` |
| `_setup_thieves_den_env(map_id)` | **830-878** | Den only: ambient 0.12, AGX **1.9**, glow 0.45, shadow-toe LUT (+0.022/0.030) |
| `_apply_level_atmosphere(stats)` | **886-912** | level-authored `sky_light.intensity*0.2` → ambient (clamp 0.02..1.0), level fog, level post-process. **No-op on Guildhall** — see §1.5 |
| `_apply_level_post_process(env, pp)` | **930-964** | only `BloomIntensity` (×0.08, cap 0.32/0.8) and `Saturation` |
| `game/src/ui/mission_prep_ui.gd` `_build_stage(viewport)` | **656-739** | see §4.1 |
| `game/src/core/weather_profile.gd` `apply_environment(env, moon, preset)` | **875-1061** | the single weather apply (fields in §1.3) |
| `apply_for_map(env, moon, map_id)` | **1066-1070** | preset lookup then `apply_environment` |
| `game/src/core/weather_visuals.gd` `make_sky(preset, moon)` | **290-411** | Sky shader material (horizon/zenith/moon disc/stars/haze/clouds) |
| `apply_sky(env, preset, moon)` | **414-434** | `env.sky`, `BG_SKY`, reflection sky; for night presets also `fog_sky_affect = 0.80` (423), `background_energy_multiplier = max(..., 2.0)` (424), `fog_light_color = (0.12,0.13,0.15)`, `fog_light_energy = 1.0` (429-430) |
| `game/src/core/mobile_profile.gd` `apply_environment(env)` | **251-261** | mobile only: glow on/off, `glow_intensity <= 0.45`, `glow_bloom <= 0.12` |

`level_loader.gd` — the complete environment-facing surface (there is **no** `tonemap_*`,
`ambient_light_*`, `glow_*`, `ssao_*`, `ssil_*` or `sdfgi_*` assignment in the file):

| function | lines | what it does |
|---|---|---|
| `_build_fog_volumes(trs, ov_arr, parent, ctx)` | **4104-4150** (`_is_fog_volume_override` 4092-4097) | authored `LocalVolumetricFog` → `FogVolume` + `FogMaterial` (density = GlobalMultiplier×20 clamp [0.05,1.5], edge fade, emission ×0.08) |
| `_build_post_process_gi_fills(post_processes, parent, ctx)` | **6115-6169** | finds the first `WorldEnvironment` in children (6120-6126); spawns `SkylightLeakingFill_*` omnis — Den `0.10` (6155) / other `clamp(leak*0.9, 0.1, 0.45)` (6160); attaches `build_shadow_toe_lut(1.2, sc, mb)` to `wenv.environment.adjustment_color_correction` (6164-6168) |
| `light_energy_for_intensity(raw)` | **301-307** | the authored-intensity → `light_energy` curve |
| `plan_light_selection` / `_add_lights` / `_build_light` / `_build_rect_lights` | see §3 | all light energies |

### 1.2 `weather_profile.gd` class map (every profile field, where it is applied)

Constants (header unit conversions `:10-60`; clamps/tuning `:84-167`):

| constant | line | value | effect |
|---|---|---|---|
| `FOG_DENSITY_SCALE` | 86 | 0.03 | `fog.density * 0.03` (cm→m calibrated) |
| `FOG_SKY_AFFECT_FLOOR` | 92 | 0.80 | outdoor `fog_sky_affect` |
| `VOLUMETRIC_FOG_SKY_AFFECT_FLOOR` | 96 | 0.15 | outdoor volumetric sky term |
| `FOG_HAZE_LUMA_FLOOR` | 98 | 0.05 | outdoor fog-light luminance floor |
| `MOON_ENERGY_SCALE/MIN/MAX` | 100-102 | 10.0 / 0.05 / 1.0 | `moon_light.intensity` → `light_energy` |
| `AMBIENT_ENERGY_MIN/MAX` | 104-105 | 0.05 / 0.35 | ambient clamp |
| `AMBIENT_UE_TO_GODOT` | 112 | 0.08 | `sky.intensity * 0.08` → ambient |
| `NIGHT_EXPOSURE` | **121** | **1.15** | exposure floor/AGX anchor for night presets |
| `EV_CURVE_POINTS` | 133-137 | 8 points | recorded only (`ev_curve_bias`, 488-500), **never applied** |
| `EV_CURVE_NIGHT_EV100` | 140 | -3.0 | log only |
| `BLOOM_TO_GLOW` | 145 | 0.02 | `bloom_intensity * 0.02` → `glow_intensity` |
| `FOG_ENERGY_COMP_MAX` / `DEN_FOG_ENERGY_COMP_MAX` | 148 / 152 | 8.0 / 2.0 | Den fog compensation caps |
| `GLOW_LEVELS_NON_DEN` / `GLOW_HDR_SCALE_NON_DEN` / `GLOW_HDR_THRESHOLD_NON_DEN` / `GLOW_BLOOM_NON_DEN` | 161-167 | 3 / 0.9 / 1.6 / 0.015 | outdoor glow stack |
| `ENV_GI_MODE` / `ENV_AO_MODE` | 330-331 | `TAT2_GI` / `TAT2_AO` | QA levers |
| `INDOOR_CEILING_PROBE_M` | 405 | 15.0 | AI sound-carry only |

Getters (all read the preset JSON, no invention): `fog_density` 448-449, `fog_light_color` 452-456,
`fog_sun_scatter` 459-464, `is_indoor_preset` 470-471, `is_night_preset` 479-484, `ev_curve_bias` 488-500,
`moon_source_angle` 506-510, `fog_height_density` 522-526, `sky_clouds_visible` 532-533,
`sky_cubemap_path`/`_res_path`/`sky_ibl_state` 542-570, **`stage_grade_values` 579-590**,
`fog_haze_color` 600-618, `moon_energy` 621-625, `moon_color` 628-632, `moon_basis` 641-672,
`ambient_color` 675-679, `ambient_energy` 682-686, `background_color` 689-693, `saturation` 696-702,
`brightness` 705-709, `shadow_gain` 712-716, `build_shadow_toe_lut` 729-793, `tonemap_exposure` 796-800,
`glow_intensity` 803-807, rain getters 810-819, sky/moon disc getters 825-869.

`apply_environment` field-by-field (line → target):

| preset field | lines | assignment |
|---|---|---|
| `fog.density` | 879-882 | `env.fog_enabled = true`, `fog_density = density * 0.03` |
| `fog.inscattering` | 883-889 | outdoor: `fog_haze_color` (hue kept, luma floored 0.05); indoor: exact colour |
| indoor low-luma fog compensation | 895-901 | `fog_light_energy = 0.06/lum` (low density) or `0.025/lum`, clamped 8.0 / Den 2.0; `fog_aerial_perspective 0.65/0.25` |
| `fog.directional_inscattering` | 902-904 | `fog_sun_scatter` (luminance 0..1) |
| `fog.height_falloff` | 905-910 | outdoor `fog_height_density = falloff * 0.03`, `fog_height = 0` |
| (sky) | 916 | `fog_sky_affect = 0.0` indoor else 0.80 |
| `fog.volumetric_*` | 925-947 | `volumetric_fog_*`: density `clamp(0.0035*ext + low_density?0.002, 0.001, 0.012)`, length, albedo, emission |
| `sky.light_color` | 948-951 | `ambient_light_source = COLOR`, `ambient_light_color` |
| (IBL) | 952-964 | `ambient_light_sky_contribution = 0` (cubemap absent; one log line) |
| `sky.intensity` | 965-968 | `ambient_light_energy = clamp(intensity*0.08, 0.05, 0.35)` |
| `sky.overall_color` | 969-972 | `background_mode = BG_COLOR`, `background_color` (replaced later by `apply_sky`) |
| `postprocess.saturation` / `gain_midtones` | 973-980 | `adjustment_saturation`, `adjustment_brightness = clamp(gain.x, 0, 2)` |
| GI/AO + shadow LUT | 981-989 | `apply_gi_and_ao`; `adjustment_color_correction = build_shadow_toe_lut(gain_shadows)` when `> 1.02` |
| `postprocess.auto_exposure_bias` | 990-992 | `tonemap_exposure = 1.0 + bias` |
| night presets | 998-1009 | `tonemap_mode = TONE_MAPPER_AGX`; `tonemap_exposure = maxf(existing, 1.15)`; evidence print |
| `postprocess.bloom_intensity` | 1010-1031 | `glow_enabled`, `glow_intensity = clamp(bloom*0.02, 0, 0.8)`, Den ×0.6, HDR threshold/scale/bloom, mip levels 0-2 (0-1 Den) |
| (desktop) | 1032-1038 | SSR on, 48/24 steps, fade 0.15/2.0, depth tolerance 0.2 |
| mobile | 1044-1045 | `MobileProfile.apply_environment` |
| `moon_light.intensity/color/pitch-yaw-roll/source_angle` | 1046-1060 | `moon.light_energy/light_color/basis/light_angular_distance` |

Non-obvious: `apply_environment` returns **false only when the preset is empty** (876-877), so a
missing prefix JSON leaves whatever hand values exist (this is why the prep stage's ACES survives only
if `midnight_clear_mission_lobby.json` fails to load).

### 1.3 `TAT2_AO` exactly (the brief asks for ~341-378)

- `ENV_AO_MODE := "TAT2_AO"` — `weather_profile.gd:331`.
- `ao_enabled()` — **341-342**: `OS.get_environment("TAT2_AO").strip_edges().to_lower() != "off"`.
  Anything except the exact string `off` (after trim/lower) = on; unset = on.
- `apply_gi_and_ao(env, desktop_quality)` — **347-378**:
  - 348-349 early return when `env == null` **or `desktop_quality < 2`** → at graphics quality
    low/medium neither SSIL nor SSAO is applied at all.
  - `TAT2_GI` (`ENV_GI_MODE`, 330): `ssil` (default) → `ssil_enabled = true`, radius 4.5,
    intensity 0.8, sharpness 0.98, normal rejection 1.0 (351-356); `sdfgi` → 3 cascades,
    0.5 m cells, occlusion, read sky light, energy 1.0, max distance 200 (357-366); `off` → none.
  - SSAO (367-378): `ssao_enabled = true`, radius 1.5, intensity 1.2, power 1.5, detail 0.5,
    horizon 0.06, sharpness 0.98, `ssao_light_affect = 0.0`.
  - **`TAT2_AO=off` removes SSAO only; SSIL stays on** (P0 report `:88-90`, audit `:67-68`).
- Call site: inside `apply_environment` at **985**, inside the `is_desktop and desktop_quality >= 2` block (`:981`).
  Therefore the lever also affects the prep stage (called from `mission_prep_ui.gd:684`) and it is the
  only AO/SSIL switch in the tree.
- Prep overrides `ssil_enabled = false` **after** the apply (`mission_prep_ui.gd:688`), so prep is
  `ssao` only (matches `W9_ENV scene=prep ... ssil=false`).

### 1.4 Preset / grade tables

- Preset data: `res://data/generated/weather/<preset>.json` (16 presets + `map_weather.json`, incl.
  `midnight_clear_mission_lobby.json`), map routing `res://data/generated/weather/map_weather.json`.
  `guildhall → gloomy` (`map_weather.json`).
- Code grade table: **`stage_grade_values(preset)` — `weather_profile.gd:579-590`** returns
  `tonemap_mode` (AGX night / ACES day), `tonemap_exposure` (1.15 night / 1.0), `ambient_light_color`,
  `ambient_light_energy` (preset ambient or 0.05), `glow_intensity`, `background_energy_multiplier 1.0`.
  **It has exactly one consumer: `game/tests/probe_render_t07.gd:391-392`** (printed, not applied).
  `mission_prep_ui.gd` does not call it (this is the "unlanded" debt).
- EV curve table `EV_CURVE_POINTS` (133-137) is documentation + log only.
- Shadow-toe LUT table `build_shadow_toe_lut` (729-793), cached per (gain, contrast, bias, lift, toe).

### 1.5 Presets live per scene (with the line that sets the value)

| value | prep (`prep*`) | Guildhall interior (`upper_foyer`, `foyer_sweep`) | Den (not captured) |
|---|---|---|---|
| preset | `midnight_clear_mission_lobby` (`mission_prep_ui.gd:682`) | `gloomy` (map table) | `midnight_clear_thieves_den` |
| tonemap | **AGX** (`weather_profile.gd:999`; `tonemap=4` in `W9_ENV`) | **AGX** (`:999`) | AGX (`mission_controller.gd:849`) |
| exposure | **2.600** (`mission_prep_ui.gd:84,692`) | **1.150** (`weather_profile.gd:121,1000`) | **1.9** (`mission_controller.gd:850`) |
| ambient energy | **1.800** (`mission_prep_ui.gd:85,696`) | **0.16** (`sky.intensity 2.0 × 0.08`, `weather_profile.gd:686,968`) | **0.12** (`mission_controller.gd:840`) |
| ambient colour | (0.42,0.50,0.72) (`mission_prep_ui.gd:694`) | (1,1,1) (`gloomy.sky.light_color`) | (0.06,0.08,0.12) (`:839`) |
| glow | 1.0 / bloom 0.12 / hdr 0.95 (`mission_prep_ui.gd:698-700`); glow hdr scale 0.9 / levels 0-2 set by `weather_profile.gd:1021,1024` during the apply | 0.12672 / hdr 1.6 / scale 0.9 / bloom 0.015 (`weather_profile.gd:1018-1025`; `6.336*0.02`) | 0.45 / hdr 0.85 / scale 1.25 (`mission_controller.gd:872-878`) |
| sky | BG_SKY, `background_energy_multiplier 0.18` (`mission_prep_ui.gd:701`); disc at screen (0.76,0.09) (`:93-94,811-814`) | BG_SKY, `background_energy_multiplier 2.0`, `fog_sky_affect 0.80` (`weather_visuals.gd:423-424`) | sky pane, `fog_sky_affect 0` |
| SSIL / SSAO | false / on (`mission_prep_ui.gd:688`; `weather_profile.gd:351,371`) | **on / on** (`W9_ENV ssil=true`) | on / on |
| SSR | on (`weather_profile.gd:1034`, desktop) | on | on |
| fog | density 0.02×0.03 = 0.0006, luma-floored haze | density 0.16×0.03 = **0.0048**, height 1.070813×0.03 = **0.0321**, sun scatter lum 0.4235 | exact authored inscattering |
| adjustment | saturation 0.95, brightness 1.2, shadow LUT (gain_shadows 1.3) | saturation 0.9, brightness 1.06, shadow LUT | 0.95 / 1.0 + Den P1 LUT |
| volumetric | on, density `clamp(0.0035*0.6+0.002, ...)` = 0.0041 | on, density `clamp(0.0035*1.0, ...)` = 0.0035 | on, 0.002 emission, length 60 |

The interior ambient is **not** overridden by `_apply_level_atmosphere`: `_store_level_extras`
(`level_loader.gd:5846-5858`) only carries `sky_light`/`fog_volume`/`post_process` if the loaded
sublevels author them, and a scan of `game/data/generated/levels/**` finds them only in
`Developers/JCamera/Maos/CluesSpawner_Gym`, `Menus/MainMenu/BeautifulCorner_Startscreen_Lighting` and
`ThievesDenTest/ThievesDenTest_P` — **none in the Guildhall 15-file load set** (0 sky lights, 0
post-process, 0 fog volumes in `Guildhall_P`, `Building_Guildhall_POI`, `POI_3rdFloor`, `_Geometry`).

**Live confirmation (the lead's own 08:20-08:23 P1 captures in this worktree, read-only):**
`build/qa/w9/logs/cap_p1_before_upper_foyer.log` and `cap_p1_before_foyer_sweep.log` both print
```
TAT-2 exposure: preset=gloomy mode=AGX exposure=1.150 authored_bias=0.0 ev100_night=-3.0 authored_curve_bias=-4.00
TAT-2 environment: bg=2 ambient_src=2 ambient_energy=0.15999999642372 ambient_color=(1.0, 1.0, 1.0, 1.0) sky=true fog=true fog_density=0.00480000022799
TAT-2 light allocation: map=guildhall authored=914 kept=159 budget=159 forced=7 rooms=152/187 cell_m=16.0
W9_ENV scene=upper_foyer ssao=true ssil=true tonemap=4 exposure=1.150 glow=true
```
and `cap_p1_diag_noperiph.log` / `cap_p1_diag_ledge.log` print
```
TAT-2 exposure: preset=midnight_clear_mission_lobby mode=AGX exposure=1.150 authored_bias=-0.5 ...
W9_ENV scene=prep ssao=true ssil=false tonemap=4 exposure=2.600 glow=true
```
i.e. the prep preset itself resolves to AGX **1.150** before the stage's `max(..., 2.6)`; the
`2.600` is the stage constant, not the weather grade. `prep_noperiph` freed **306** nodes
(`W9_DIAG prep_noperiph freed=306`), so "Periphery" is 306 scene nodes after chunk merging
(not 1,740 meshes). `prep_ledge` reports `kept=21 hid=397` — i.e. only 21 of 418
`GeometryInstance3D`s lie within 9 m of the thief's feet in the authored frame
(`build/qa/w9/logs/cap_p1_diag_ledge.log`).

### 1.6 Functions a calibration pass would touch (ranges)

`level_loader.gd` (A4 subset): light curve & constants **236-311**; room-plan block **315-357**;
`_effective_light_budget` **536-543**; `_add_one_light` **5025-5036**; `_prioritize_lights` **5039-5073**;
`_add_lights` **5075-5098**; `_is_gate_hero_light` **5101-5119**; `light_room_cell` **5121-5135**;
`plan_light_selection` **5147-5223**; `_select_lights` **5228-5229**; `_report_light_allocation`
**5235-5241**; `_report_gate_lights` **5244-5250**; `_build_rect_lights` **5710-5771**;
`_build_post_process_gi_fills` **6115-6169**; `_light_score` **6456-6466**; `_sort_lights_desc`
**6468-6486**; `_build_light` **6581-6646**; `_build_fog_volumes` **4104-4150** (`_is_fog_volume_override` 4092-4097).

`weather_profile.gd`: constants **84-167**; `_clamped_fog_compensation` **173-189**;
`quality_level` **206-226**; GI/AO **317-378**; `stage_grade_values` **579-590**;
`apply_environment` **875-1061**; `apply_for_map` **1066-1070**.

`mission_prep_ui.gd`: constants **81-124**; `_build_stage` **656-739**; `_build_stage_character_lights`
**746-783**; `_aim_stage_moon_and_key` **791-814**; `_screen_dir` **817-819**; `_add_prep_skyline`
**826-889**; `_grade_skyline_material` **897-923**; `_load_prep_skyline` **926-946**.

`mission_controller.gd` (**P2-owned**): `_setup_environment` **246-296**; gate fills **299-338**
(energies 2.2 / 3.5 / 1.5); road fills **346-365** (0.7); car headlights **377-402** (4.5);
saferoom fill **545-557** (1.1); foyer fills **564-580** (**1.6 / 1.3**); fallbacks **585-605**;
Den env **830-878**; `_apply_level_atmosphere` **886-912**; `_apply_level_post_process` **930-964**.

---

## 2. The stage grade: every `2.6` / `1.8` / `1.15` / `ACES` literal

### 2.1 Grep results

`game/src/core/level_loader.gd`: **no** `2.6`, `1.8`, `1.15`, `TONEMAP_*`, or live `ACES` code.
Only two comments mention ACES (`:1530`, `:1538`, neon material tuning). The file sets no tone mapping.

`game/src/core/weather_profile.gd`:
- `:13` comment: "reached only ~1.8 % obscuration at 30 m" (unrelated)
- `:121` `const NIGHT_EXPOSURE := 1.15`
- `:574` comment: *"The stage still hard-codes ACES 2.6 / ambient 1.8 /"*
- `:576` comment: *"measurable 2.6x exposure and 11x ambient gap"*
- `:584` `Environment.TONE_MAPPER_AGX if night else Environment.TONE_MAPPER_ACES` (in
  `stage_grade_values`, the unwired hand-off table)
- `:993,996` comments about the old ACES 1.0 path / the 1.15 anchor
- `:998-1000` live `tonemap_mode = AGX` and `tonemap_exposure = maxf(..., 1.15)`

`game/data/expansion/**`: **no** `2.6`, `1.8`, `1.15`, `ACES`, `TONEMAP` literals. (`prep_skyline.json`
scales are 0.56-0.75; the only "1.8" substring in expansion data is unrelated text in `audio_mix.json:46`.)

`game/src/ui/mission_prep_ui.gd`:
- `:84` `const STAGE_EXPOSURE: float = 2.6`
- `:85` `const STAGE_AMBIENT_ENERGY: float = 1.8`
- `:86` `const STAGE_GLOW_INTENSITY: float = 1.0`
- `:101` `const STAGE_SKY_ENERGY: float = 0.18`
- `:663` `env.tonemap_mode = Environment.TONE_MAPPER_ACES` (before the preset apply)
- `:692` `env.tonemap_exposure = maxf(env.tonemap_exposure, STAGE_EXPOSURE)`
- `:696` `env.ambient_light_energy = STAGE_AMBIENT_ENERGY`

Docs / reports mentioning "ACES 2.6 / ambient 1.8":
- `build/qa/w9/p0-report.md:24` — *"the still-unlanded stage grade: ACES 2.6 / ambient 1.8 at HEAD"*
- `docs/reports/remediation-20261125/T05-ui.md:20,56` (BLOCKED-ON T07 row: "ACES 2.6 / ambient 1.8")
- `docs/reports/remediation-20261125/T05-ui.md:368` (open risk)
- `docs/reports/remediation-20261125/T07-render.md:365-366,503` (C1-09)
- `docs/reports/remediation-20261125/T07-render.md:500-505` (risk 8): *"The IsNight classification
  changes the lobby's preset exposure from 0.5 to 1.15. `mission_prep_ui` still overrides to 2.6, so
  the stage is unchanged today, but T05 must know that `max(...)` will keep 2.6 until it adopts
  `stage_grade_values`."*

### 2.2 What is actually live

- **Exposure 2.6 and ambient 1.8 are live on the prep stage** (`mission_prep_ui.gd:692,696`), and both
  are `maxf`/direct assignment **after** the weather apply, so they win over the preset.
- **`ACES` is not live.** The stage sets ACES at `:663`, then `WeatherProfile.apply_environment`
  (`:684`) sets **AGX** at `weather_profile.gd:999` because `midnight_clear_mission_lobby` matches
  `is_night_preset` (`pid.begins_with("midnight_clear")`, `:481`), and the stage never sets the mode
  again. The live `W9_ENV` log confirms it: `tonemap=4` (`Environment.TONE_MAPPER_AGX = 4`, the P0
  audit lines `audit-report.md:67-70`). ACES would only survive if
  `res://data/generated/weather/midnight_clear_mission_lobby.json` were missing/corrupt
  (`load_preset` → `{}` → `apply_environment` returns false at 876-877). The JSON exists and parses.
- **Interior is AGX / 1.15 / 0.16**, not ACES: `weather_profile.gd:998-1000`, `:686,968`; `gloomy`
  `auto_exposure_bias 0.0` → `tonemap_exposure 1.0` → floored to 1.15.
- The phrase "ACES 2.6" is inherited from `weather_profile.gd:574` and the T05/T07 rows. If the lead
  edits those docs, the code-accurate wording is **"AGX, exposure 2.6, ambient 1.8, glow 1.0,
  sky energy 0.18"**.

### 2.3 Target grade that a report specifies

- The only specified prep target is **the gameplay grade** — `docs/reports/remediation-20261125/T07-render.md:371-376`:
  > `WeatherProfile.stage_grade_values(preset)` returns the gameplay numbers for the stage
  > (`tonemap_mode AGX`, `tonemap_exposure 1.15`, `ambient_light_energy 0.16`,
  > `glow_intensity 0.12672`, `background_energy_multiplier 1.0`) so T05 can replace
  > its four constants with one call and keep one grade across the product.
  >
  > **verdict: DEFERRED → T05** (call `stage_grade_values`, drop the four constants).
  `T05-ui.md:56` states the authored truth as "gameplay AGX 1.0 / ambient 0.16" — **"1.0" disagrees
  with `stage_grade_values` (1.15, `NIGHT_EXPOSURE`) and with the live log (1.150)**; the 1.0 is the
  non-night branch of `:585`. Quote 1.15 if the row is edited.
- Interior target (metric, not grade): `T07-render.md:555-556`:
  > expect p50 to move from 2 toward the reference 13-15 and `%<8` from 78 % down to ~10-25 %.
- No report specifies a KF11 histogram target for prep; the P0 reference numbers are
  `p0-report.md:60-61` (KF11 37.2 / 28 / 85 / 22.9 %, silhouette top p50 sy 0.372) and `:108-109`.

---

## 3. Light plan

### 3.1 `plan_light_selection(ordered, max_lights, map_hint)` — `level_loader.gd:5147-5223`

Doc block **5138-5146**; rule block **315-333** ("fair per-room light allocation").

1. `budget = min(ordered.size(), max_lights)` — **5148**.
2. Walk `ordered` once: protected lights (`_is_gate_hero_light`, **5101-5119**) are pulled into
   `forced` and skipped; every other light is bucketed by `light_room_cell` into
   `cell_ranks[Vector3i]` with its index (so preference order survives inside a bubble) — **5149-5166**.
3. Sort cells **densest-first**; ties: highest first-member `_light_score`, then stable
   `(x,y,z)` cell key — **5168-5184**.
4. `keep_target = clamp(budget - forced.size(), 0, ordered.size())` — **5185**.
5. **Water-fill**: round-robin over the sorted cells, each round every cell takes its next light
   (depth counter) until `keep_target` or no progress — **5186-5202**. Consequence: an
   over-subscribed map gives every served bubble exactly one light before any bubble gets a second.
6. `picked.sort()` (ascending `ordered` index) — **5204**.
7. Hero shadows: `hero_shadows = min(MobileProfile.hero_shadows(), budget)`; the first
   `hero_shadows` picked entries get `shadow: true` — **5206-5209**.
8. Forced/protected entries are appended **shadowless**, up to `budget` — **5210-5213**.
9. Returns `{"selection": [{info, shadow, forced}], "stats": {authored, budget, kept, forced, cells,
   covered, cell_m, hero_shadows}}` — **5214-5223**.

Stats are logged by `_report_light_allocation` (**5235-5241**, only when `authored > budget`) and
`_report_gate_lights` (**5244-5250**, Guildhall only).

### 3.2 Constants

| name | line | value |
|---|---|---|
| `LIGHT_MEDIAN_INTENSITY` | 251 | 15.0 (authored lm anchored to energy 1.0) |
| `LIGHT_ENERGY_FLOOR` | 252 | 0.01 |
| `LIGHT_ENERGY_SOFT_CEIL` | 256 | 3.5 (tanh shoulder, **not** a clamp) |
| `DEN_SPOT_ENERGY_SCALE` / `DEN_SPOT_ATTENUATION` | 263-264 | 0.75 / 2.0 |
| `DEN_GI_FILL_ENERGY/RANGE/ATTENUATION/COLOR` | 267-270 | 0.10 / 10.0 / 1.5 / (0.55,0.70,0.92) |
| `LIGHT_RANGE_CEIL` | 311 | 200.0 m |
| `LIGHT_ROOM_CELL_M` | **333** | **16.0** |
| `PROTECTED_LIGHT_POINTS` | 350-353 | `(10.0, 26.0, 49.8)`, `(126.2758, 27.1426, -2.4736)` |
| `PROTECTED_LIGHT_RADII` | 354 | `[10.0, 2.0]` |
| `HERO_LIGHT_POINT` / `HERO_LIGHT_RADIUS_M` / `HERO_LIGHT_MAP_HINT` | 355-357 | gate point / 10.0 / `"guildhall"` |
| `LIGHT_DISTANCE_FADE_BEGIN/LENGTH` | 198-199 | 28.0 / 12.0 m (non-shadow lights only) |
| `DESKTOP_MAX_LIGHTS` / `DESKTOP_HERO_SHADOWS` | `mobile_profile.gd:14,15` | 160 / 6 |
| env overrides | `mobile_profile.gd:20-21,139-171` | `TAT2_LIGHT_BUDGET`, `TAT2_SHADOW_HEROES` |

The protected set's six KF16 gate lights are documented at **338-347** (two 20.0 uplights, two 4.1
omnis, two 20.0 gameplay lights, ranking ~243-702 on authored energy) and the contract-2 safe-room spot
at **348-349** (88° wall spot, intensity 5.0, radius 9 m, `(126.28, 27.14, -2.47)`).
Selection is `guildhall`-only (`_is_gate_hero_light` returns false for other hints, **5102-5103**).

Measured result (`T07-render.md:84,111`): 
`TAT-2 light allocation: map=guildhall authored=914 kept=159 budget=159 forced=7 rooms=152/187 cell_m=16.0`
and `TAT-2 gate lights: total=160 (generic=159 rect=1) budget=159 forced=7 hero_shadows=6`.
Pre-T07 (red, reproduced inside `probe_render_t07.gd`): 95/189 bubbles covered vs 154/189 now.

### 3.3 Energy applied to selected vs unselected

- **Selected** (`_add_one_light` **5025-5036** → `_build_light` **6581-6646**):
  `intensity = light_energy_for_intensity(raw_i)` (**6584**), assigned to
  `sl.light_energy` (**6616**) or `ol.light_energy` (**6627**); `DirectionalLight3D` is hard-coded
  **0.45** (**6601**); Den spots use `raw_i * 0.75` (**6589**); range clamp `[1, 200]`; attenuation
  1.0; non-hero lights fade 28→40 m (**6632-6638**); `shadow_enabled = cast_shadow` (**6630**).
- **Forced/protected**: same curve, **shadowless** (`plan` 5212), counted in `gate_light_count`.
- **Unselected**: **no node is created and nothing is dimmed** — the authored light is dropped from the
  scene (the JSON is untouched). There is no per-room energy clamp anywhere.
- **Rect lights** claim budget first (`_build_rect_lights` calls at **6320** sync / **6387** async), `omni.light_energy =
  light_energy_for_intensity(raw)` (**5733**), shadowless, plus an emissive quad
  `emission_energy_multiplier = 2.0` (**5758**).
- **Non-budgeted lights** (do not pass through the plan): 10 hand fills in `mission_controller.gd`
  (§1.6) + the moon = `160 + 11` (`T07-render.md:350-359`), plus the `LumenSkylightLeaking` fills
  (`level_loader.gd:6155,6160`), Den hand fills, guard lantern 1.4 (`guard_ai.gd:2350`) and the
  `vfx_manager.gd` lights (0.30-4.5; not part of the 160 budget).

### 3.4 Energy curve (the only global mapping)

`light_energy_for_intensity(raw)` — **301-307**:
`if raw <= 0: 0.01`; `x = raw/15.0`; `shaped = 3.5*tanh(sqrt(x)/3.5)`;
`median = 3.5*tanh(1/3.5)`; `return max(shaped/median, 0.01)`.
Anchors (doc `236-250`): 15 → 1.0; 3 → 0.46; 150 → 2.59; 300 → 3.07; 2500 → 3.56.

### 3.5 How a downward retune would be expressed (mechanical options, no preference implied)

| lever | file:line | size of the effect |
|---|---|---|
| raise `LIGHT_MEDIAN_INTENSITY` | `level_loader.gd:251` (used `:304`) | divides every mapped energy; **also re-ranks selection** (`_light_score` `:6458`) |
| lower `LIGHT_ENERGY_SOFT_CEIL` | `level_loader.gd:256` (`:305-306`) | compresses the top only; median stays 1.0 |
| per-light multiplier | would have to be added at **6616/6627** and **5733**, and in `_light_score` **6458** if ranking must track rendering | uniform scaling; not present today |
| exposure | `weather_profile.gd:121,1000` (interior), `mission_prep_ui.gd:84,692` (prep) | **global**; both sites use `maxf`, so a downward override must replace the `maxf`, not the preset |
| preset `auto_exposure_bias` | data `weather/<preset>.json`; applied `:990-992` | limited: `maxf(…, 1.15)` floors the night result |
| ambient scale | `AMBIENT_UE_TO_GODOT 0.08` (`:112`), clamp 0.05-0.35 (`:104-105`), applied `:686,968` | every preset's ambient, authored order preserved |
| post multiplier | `adjustment_brightness = gain_midtones` (`:705-709,973-980`), shadow-toe LUT (`:729-793,986-989`) | midtones/shadows, not highlights |
| hand fills | `mission_controller.gd:564-580` (foyer 1.6 / 1.3), others §1.6 | local, **P2-owned** |
| glow | `:1010-1031` (interior 0.12672 @ threshold 1.6), `mission_prep_ui.gd:698-700` (1.0 @ 0.95) | highlights above threshold only |

Concrete fact for the measured overshoot: the `upper_foyer` eye is `(27, 29.67, -50)`; the two
P2 foyer fills sit at `(27, 31, -53)` (**3.3 m** from the eye) and `(27, 31, -64)` (14.1 m), energy
**1.6 / 1.3**, range 16 m, attenuation 1.2, shadowless, registered with `light_probe`
(`mission_controller.gd:564-580`). Nothing in `level_loader` or `weather_profile` knows about them.

---

## 4. Prep composition

### 4.1 Stage build order (`mission_prep_ui.gd`)

| lines | action |
|---|---|
| 334-370 | `_build_all` (stage portion): `SubViewportContainer` `PrepBackdropContainer` (348-363), `SubViewport` (364-369), `_build_stage(viewport)` (370) |
| 656-659 | `MissionLobbyStage` root added to the SubViewport |
| 661-673 | `WorldEnvironment` + `Environment`: **ACES (663)**, glow 0.65/0.20, BG_COLOR, ambient 0.45 |
| 675-680 | `MissionLobbyMoonLight` (colour 0.6039/0.702/1.0, energy 0.35, shadows on) |
| 682-685 | `load_preset("midnight_clear_mission_lobby")` → `apply_environment` + `apply_sky` |
| 688 | `env.ssil_enabled = false` |
| 691-701 | stage grade: exposure `max(…, 2.6)`, ambient colour (0.42,0.50,0.72), ambient energy **1.8**, glow 1.0 / bloom 0.12 / hdr 0.95, `background_energy_multiplier 0.18` |
| 703-709 | `_get_preview_mat_loader()` (1077-1081, a `LevelLoader` child) then `load_sublevels([MissionLobby_Geo3, MissionLobby_Periphery], stage_root, null, 64, false)` |
| 711-724 | `MissionLobbyCamera`: position `LOBBY_CAM_POS`, `fov 20`, `KEEP_WIDTH`, far 2000, `cam.environment = env` |
| 725-729 | `look_at_from_position(pos, pos + LOBBY_CAM_FWD*15, UP)`, then roll −14.780165° about local Z |
| 730-731 | `_aim_stage_moon_and_key` (791-814), `_add_prep_skyline` (826-889) |
| 733-739 | `MissionLobbyThiefAnchor` at `LOBBY_THIEF_POS` / 45° yaw, `_add_thief`, `_build_stage_character_lights` |

### 4.2 Authored camera contract (`mission_prep_ui.gd:50-71`)

`LOBBY_CAM_POS = (12.6065, -0.16698, -1.05384)` (:68),
`LOBBY_CAM_FWD = (-0.986184, 0.116419, 0.117848)` (:69),
`LOBBY_CAM_FOV = 20.0` horizontal (`KEEP_WIDTH`, renders ~11.33° vertical at 16:9) (:70),
`LOBBY_CAM_ROLL_DEG = -14.780165` (:71). Source: `MissionLobby_Geo3.json CameraActor_0`
(:63-67). `cam.far = 2000.0` (:716). The header (:54-61) forbids a reframe ("Do not
re-introduce a stage reframe here: re-author the level or the expansion data instead").

### 4.3 Subject slot

`LOBBY_THIEF_POS = (-1.5871, 0.82, -0.7868)` (:79), `LOBBY_THIEF_YAW_DEG = 45.0` (:80);
authored dummy X/Z, feet kept 0.12 m above the pivot (`0.82` vs `0.9399`) because the GLB origin is
at the hips (:72-78). Chest screen x measured 0.785 (KF11 band 0.70-0.84) (`T05-ui.md:77`).

### 4.4 What is behind the frame

`MissionLobby_Geo3` (367 meshes, 12 authored lights) + `MissionLobby_Periphery` (**1,740 meshes**,
10 lights) = 2,107 meshes; 387 pivots inside the authored 10° cone (`mission_prep_ui.gd:54-61`,
`T05-ui.md:75-76`, test P12 asserts ≥380, `test_t05_ui_contract.gd:166-168`). The loader is called
with `max_lights=64, generate_collision=false` (`:704-709`), so the lobby's 22 authored lights all fit
(no eviction) and none of the lobby geometry collides. `map_hint` for these paths is `""`
(`_map_hint_from_paths` `level_loader.gd:6173-6192` matches only guildhall/old_manor/den/ftue), so the
protected set does not apply.

Sky: `apply_sky` **does** build a sky (`env.sky`, `BG_SKY`, `weather_visuals.gd:431-433`) and the stage
then sets `background_energy_multiplier = 0.18` (`:701`); the moon disc direction/energy are shader
params set by `_aim_stage_moon_and_key` at `MOON_DISC_SCREEN (0.76, 0.09)`, disc energy 2.4
(`:93-94,102,811-814`). The P0 frame has no visible sky because the near lobby geometry occupies the
framed sector — not because the sky is absent. The new `prep_noperiph` diagnostic (§6.5) exists to
separate Geo3 from Periphery for exactly this question.

### 4.5 `game/data/expansion/prep_skyline.json` (113 lines)

Top-level: `schema "tat2.prep_skyline/1"`, `expansion true`, `kind "prep_skyline"`,
`stage "MissionLobby"`, `source "TAT-2 expansion content built from the shipped Skybox
distant-building kit"`, `notes` (6 strings: 2,107/387 provenance; not extracted content; placement
contract azimuth **+ = left** / distance / `base_y` **absolute world Y** / yaw / uniform scale;
band contract width ≤0.60, top ∈ [0.65,0.98], overlap 0..1; retired pre-T05 standoff note;
`layer` is documentation only).

`pieces` — 8 entries, in file order:

| id | mesh | material | az° | dist m | base_y | yaw° | scale | layer | authored note (width/top) |
|---|---|---|---:|---:|---:|---:|---:|---|---|
| mid_roofline_a | SM_DistantBuildingC | M_DistantBuildingC | -2.5 | 310 | 0.0 | 123 | 0.56 | mid | 0.42 / 0.83 |
| mid_roofline_b | SM_DistantBuildingC | M_DistantBuildingC | -7.0 | 380 | 0.0 | 123 | 0.75 | mid | 0.49 / 0.90 |
| far_row_west | SM_DistantBuildingC | M_DistantBuildingC | 3.0 | 470 | -2.0 | 123 | 0.60 | far | 0.27 / 0.81 |
| far_row_east | SM_DistantBuildingC | M_DistantBuildingC | -11.0 | 480 | 18.0 | 156 | 0.72 | far | 0.43 / 0.92 |
| clocktower_west | SM_DistantTowerA | ML/MI_DistantBuidingA | -0.5 | 420 | -2.0 | 0 | 0.60 | mid | 0.08 / 0.75 |
| clocktower_east | SM_DistantTowerB | M_DistantTowerB | -6.2 | 430 | -2.0 | 0 | 0.60 | mid | 0.06 / 0.95 |
| smokestack_row | SM_SkyboxSmokestacksA | ML/MI_SkyboxSmokestacks | -3.2 | 500 | -2.0 | 18 | 0.72 | far | 0.07 / 0.87 |
| urban_tower_east | SM_Skybox_UrbanTowerB | /Game/MaterialLibrary/Utility/M_DarkGrey | -9.5 | 470 | 6.0 | -12 | 0.60 | far | 0.07 / 0.95 |

### 4.6 What positions them

`_add_prep_skyline(stage_root, cam)` — **826-889**:
1. `_load_prep_skyline()` (926-946) — fail-closed on missing file / bad schema / `expansion != true` /
   empty `pieces`.
2. Horizontal forward from the live camera: `fwd = -cam.basis.z; fwd.y = 0; normalize` (**833-837**).
3. Per piece: `dir = (fwd.x*cos(az) + fwd.z*sin(az), 0, -fwd.x*sin(az) + fwd.z*cos(az))` (**853-856**);
   `pos = cam.global_position + dir * distance` (**857-858**); **`pos.y = base_y`** (absolute, **859-862**);
   `mi.position = pos`, `rotation_degrees = (0, yaw, 0)`, uniform `scale` (**874-877**).
4. Mesh/material via the loader (`_get_mesh_and_shape`, `get_material_for_ue`), material re-graded by
   `_grade_skyline_material` (**897-923**: fresh `StandardMaterial3D`, albedo texture, albedo colour
   **0.11,0.14,0.21**, per-pixel, roughness 1, metallic 0, opaque, cull disabled,
   **`disable_fog = true`**, **`disable_ambient_light = true`**, **`emission_enabled = false`**).
5. `cast_shadow = OFF`, metas `ue_mesh` / `expansion` / `prep_skyline_layer`, group
   `prep_skyline`, `stage_root.add_child` (**878-883**); prints
   `TAT-2 prep skyline: placed N/8 expansion pieces` (**887-888**).

### 4.7 Band values and enforcement

Runtime constants `PREP_SKYLINE_MAX_WIDTH_FRAC 0.60`, `PREP_SKYLINE_TOP_MIN 0.65`,
`PREP_SKYLINE_TOP_MAX 0.98` (**122-124**). They are **not read by runtime placement** — only by
`game/tests/test_t05_ui_contract.gd:170-188` (P13: exactly 8 nodes; P14: projected AABB width ≤0.60,
top edge `mn.y ∈ [0.65,0.98]`, horizontal overlap >0). Measured: width max **0.54**, top
**0.746 … 0.954** (`T05-ui.md:80-81`). JSON self-reports 0.75-0.95 tops, so the band equals the
authored data.

How to make a piece visible in the roofline band (data-only, no code): increase its **projected**
height, i.e. `scale` (bigger), `distance_m` (closer), or `base_y` (higher) — `mission_prep_ui.gd:858-877`.
How to retire: the consumer treats `pieces: []` as "no layout" (`:943-945` → `{}` → `_add_prep_skyline`
returns 0 at 828-829 and prints `placed 0/0`); the two tests would then fail by design
(P13 expects 8 nodes, `test_w7v_ui_acceptance.gd:242-252` expects every piece in the group), so a
retire edit must also change those expectations with written evidence (AGENTS.md rule 3).

Consumers of the JSON (complete): `mission_prep_ui.gd:926-946` (runtime),
`game/tests/test_t05_ui_contract.gd:170-188`, `game/tests/test_w7v_ui_acceptance.gd:21,197,242-252`.
No other file opens it (grep over `game/ tools/ docs/ build/`). The `prep_skyline` group is also read
by the W9 capture harness (`w9_capture.gd:133,147-151,170-171`) and `w9_perf.gd:115`.

### 4.8 Doc-code mismatches worth knowing before editing

- `docs/FIDELITY_GAPS.md:702-703` says the thief is at screen x 0.77 "via a 1.26 m dummy offset" —
  the code now uses the authored dummy X/Z with a **0.12 m** foot delta (`mission_prep_ui.gd:72-80`;
  chest 0.785 per `T05-ui.md:77`). The 1.26 m offset was the pre-T05 reframe.
- `T05-ui.md:56` says the gameplay target is "AGX 1.0"; `stage_grade_values` and the live log say
  **1.15** (see §2.3).

---

## 5. The two stale scorecard rows (verbatim)

File: `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`
(row format, `:60`): `| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score |`
Score vocabulary is `PASS / DELTA / MISSING / HARD_LIMIT / N/A-route` + `UNVERIFIED` coverage marker
(`:27-30`). Sections: `§2` checklist `:54`, Visual `:58`, V4-07 `:84`, V6-03 `:92`, §5 `:261-303`.

### 5.1 V4-07 — line 84 (score `DELTA`)

```
| V4-07 | Foyer dressing | S24 / KF27 #2; S25 / KF28 #3 | Tall lit glass statue vitrine, velvet armchair + ottoman, flush square metallic floor plate; framed `Basement Stairs` and `WC` plaques. | Checkered black/white marble hall with columns, a shrine and white busts (f_0174), a glass-cased white `Cat Statue` on a blue cushion (f_0208), and later a backlit glass display case with a statue inside plus two busts on plinths (f_0267); no velvet armchair/ottoman, no flush floor plate and no `Basement Stairs`/`WC` plaques (`kf_presence.md` KF27 PARTIAL). L2 called it N/A-route ("never reaches the foyer"); the vitrine-and-marble dressing is present, so it is a delta. | DELTA |
```

### 5.2 V6-03 — line 92 (score `N/A-route`)

```
| V6-03 | Security beams, emitter & node | S24 / KF27 #1, #3 | Two crisp horizontal white volumetric beams wall-to-wall from the mid-height circular white emitter (`x~17%, y~56%`); glowing cyan ceiling diamond node above the far doors. | Not reached. No beam, wall emitter, ceiling node, camera or floor plate anywhere; KF27 is PARTIAL on the room furniture only (`kf_presence.md`). | N/A-route |
```

Data facts that falsify the two observations (the P0 pixels are the primary evidence;
`p0-report.md:30-40`, `audit-report.md:76-83`):

- **V6-03 beam:** Guildhall authors **134 `light_beam` devices** (`game/data/generated/gameplay/devices_runtime.json`,
  `maps.guildhall.devices`, family `light_beam`; class `BP_Detector_LightBeam_C`); **21 are within 25 m**
  of the upper-foyer eye `(27, 29.67, -50)`. In the `upper_foyer` view (−z) the nearest are
  `guildhall/Guildhall_Gameplay:BP_Detector_LightBeam_C_107` at `(23.27, 29.76, -57.4)` = **4.4 m**
  (26.7° off axis) and `_117` at `(30.86, 29.75, -58.74)` = 5.4 m (23.8°); the `foyer_sweep_yaw180`
  view (+z) instead contains `_118` `(23.27, 32.28, -45.63)` and `_106` `(23.25, 29.78, -39.81)`.
  Ceiling-mounted `_119` `(30.74, 32.28, -50.13)` is 6.7 m from the eye. The beam is implemented and
  drawn by `game/src/devices/security_beam.gd` (+ `tat_beam.gdshader`), and `run_tests.gd:5956,6013`
  and `test_beam_geometry.gd:42-44,122` pin `BP_Detector_LightBeam_C_1` and the 134-device count.
- **V4-07 armchair/ottoman:** no mesh path in the generated levels contains "armchair" or "velvet".
  In `Building_Guildhall_POI.tatlevel.json` (the POI foyer sublevel) the authored seating is
  `SM_ChairUpperA` ×18, `SM_OfficeChair` ×15, `SM_ChairFancyA` ×14, `SM_ChairFancyB` ×8,
  `SM_ChairA` ×2 and `SM_BenchOttomanA` ×1 (at `(38.55, 36.5, -46.05)`, an upper floor 6.8 m above the capture
  eye — presence, not a pose match); the only other
  ottoman assets in the tree are in `OldManor_Geo` (`SM_BenchOttomanA` ×6 +
  `SM_BenchOttomanA_Draped` ×1), which the Guildhall capture does not load. The "present at this
  pose" claim therefore rests on the capture, not on a mesh named armchair — word the re-score with
  the mesh names above or with the PNG.

### 5.3 §5 tally table — lines 261-303 (verbatim)

```
## 5. Summary score table

Tally of §2. `UNVERIFIED` is a coverage marker, not a score, and is shown separately so the scored
count cannot be read as a quality grade.

| Score | Visual (V1–V7) | Audio (AU1–AU6) | HUD/UI (UI1–UI5) | Gameplay (G1–G5) | Total |
|---|---|---|---|---|---|
| `PASS` | 6 | 0 | 2 | 1 | **9** |
| `DELTA` | 13 | 1 | 12 | 6 | **32** |
| `MISSING` | 1 | 1 | 1 | 1 | **4** |
| `HARD_LIMIT` | 2 | 0 | 0 | 0 | **2** |
| `UNVERIFIED` | 1 | 14 | 1 | 0 | **16** |
| `N/A-route` | 14 | 15 | 11 | 17 | **57** |
| **Checklist rows** | 37 | 31 | 27 | 25 | **120** |

**Coverage line: scored 47 / N/A-route 57 / UNVERIFIED 16 (47 + 57 + 16 = 120).** The 47 comprises
9 `PASS`, 32 `DELTA`, 4 `MISSING` and 2 `HARD_LIMIT`; it is not a quality grade, because 32 of the 47
are deltas and 4 are missing elements. The audio column is still mostly uncovered: 14 of its 31 rows
are `UNVERIFIED` after T03-AUDIO showed the captured bed is capture-borne, and the two scored audio
rows rest on in-engine evidence rather than the capture — `AU6-01` `MISSING` on `VO_PINS` authored
data, `AU1-03` `DELTA` on `test_audio_mix.gd`'s loading-silence state. One visual-pillar row
(`V2-05`) is audio-owned and moved with the audio column.

**Reconciliation with `row_route_matrix.md`'s tally (43 YES / 21 PARTIAL / 56 NO).** Re-scoring row by
row gives 57 N/A-route, not 56, because four rows the matrix calls partly observable never show their
subject — V3-02 (no diamond in any Den frame), AU3-03 (no grate/vault), G2-02 (no drop/sprint/crouch),
G2-05 (no ascent) — while three it calls unreachable are reachable — V6-04 (the ward visual is present;
`HARD_LIMIT`), AU5-05 (the ward audio window is present; `UNVERIFIED` for the capture reason), AU5-07 (a
loot acquisition exists, though the key does not; `UNVERIFIED`). Net +1. `V4-04` stays scored (`DELTA`)
because the alley and the banner surface are present even though the lettering is not.

**Three rows changed reachability because a lane's premise was refuted by the frames**, and are flagged
so no one "fixes" them back: AU1-04 (now `UNVERIFIED`, not N/A — the telescope cut is in the run, F1a
C-3), AU3-05 and AU5-02 (now `UNVERIFIED` — the ZipWire is used at 02:01/02:12, f_0122/f_0136). L5's
"no zipwire / no telescope" route reconstruction is not carried. Separately, **ten audio rows plus one
audio-owned visual row (V2-05) moved from `DELTA`/`MISSING` to `UNVERIFIED`** after T03-AUDIO proved the
capture bed is not in-engine: AU1-01, AU1-02, AU1-04, AU1-05, AU3-01, AU3-02, AU3-04, AU4-01, AU4-05,
AU5-05, and V2-05. **AU1-03 left that group in W9-P0**: `game/tests/test_audio_mix.gd:126-147` measures
the loading mix state (all beds/emitters/music stopped, Ambience/SFX muted, restored after; Music mute
in `audio_manager.gd:1514-1535`), so the digital silence is settled at the control plane and the row is
`DELTA` on the transition shape/duration — a master-bus capture would make it sample-level. The other
sixteen `UNVERIFIED` rows now name the exact missing instrument in their observations (an in-engine
master-bus capture; `UI5-01` a 0.2 s quiet-vs-sprint HUD capture). Only AU6-01 remains `MISSING`, on
`VO_PINS` authored data.
```

Arithmetic consequence (for exact editing, not a decision): V4-07 is `DELTA` today, so a re-score that
keeps `DELTA` changes only its Port observation (Visual DELTA stays 13). V6-03 is `N/A-route`; moving
it to `DELTA` changes the table to `DELTA` 33 / `N/A-route` 56 (Visual `DELTA` 14, `N/A-route` 13),
scored `47 → 48`, coverage `48 + 56 + 16 = 120`, and the prose "57 N/A-route, not 56" / "three it
calls unreachable" would need the matching edit.

---

## 6. Capture harness (`build/qa/w9_capture.gd` 310-line working copy, `.sh`, `w9_frame_stats.py`)

### 6.1 Scenes, poses, dispatch

Current file is **310 lines**. Functions: `_init` 25-27, `_arg` 29-35, `_parse_size` 37-42,
`_out_dir` 44-50, `_wait` 52-55, `_all_nodes` **57-63** (new), `_find_env` 65-75,
`_sampled_stats` 77-100, `_save` **102-118**, `_prep` **121-207**, `_mission_interior` **210-289**,
`_run` **292-310**.

Dispatch: `_run()` **301** `prep|prep_nosky|prep_noui|prep_noperiph|prep_ledge` → `_prep()`;
**303** `upper_foyer|foyer|saferoom|foyer_sweep` → `_mission_interior()`. Every pose is a standalone
`Camera3D` named `W9CaptureCamera`, `fov = SHIPPED_FOV = 54.54` (`:18,263`), `far 4000` (`:264`),
`KEEP_HEIGHT` (`:265`).

| scene | builder:lines | pose | env printed |
|---|---|---|---|
| `prep` | `_prep` 121-207 | **no new camera** — the stage's authored `MissionLobbyCamera` (`mission_prep_ui.gd:711-729`); waits for the `prep_skyline` group (133-135) + 90 frames (136) | `W9_ENV scene=prep` 200-206 |
| `prep_nosky` | 147-151 | same; frees every node in group `prep_skyline`, waits 12, prints `W9_DIAG prep_nosky freed=N` | same |
| `prep_noui` | 152-157 | same; hides every `CanvasItem` child of the prep Control except the `SubViewportContainer` | same |
| `prep_noperiph` | 158-169 (**uncommitted**) | same; frees every node whose `source_sublevel` meta contains `periph`, waits 12, prints `W9_DIAG prep_noperiph freed=N` | same |
| `prep_ledge` | 170-194 (**uncommitted**) | same; keeps visible only `GeometryInstance3D`s whose world AABB is within **9.0 m** of `MissionLobbyThiefAnchor` (skyline excluded), prints `W9_DIAG prep_ledge kept=N hid=M` | same |
| `upper_foyer` | `_mission_interior` 247-249 | eye `(27, 28+1.67, -50)`, target `(27, 29.67, -60)` | `W9_ENV scene=upper_foyer` 230-237 |
| `foyer` | 250-252 | eye `(22, 22.17, 125.3)`, target `(22, 22.17, 115.3)` | same |
| `saferoom` | 253-255 | eye `(22, 20.5+1.67, 128.4)`, target `(22, 22.17, 118.4)` | same |
| `foyer_sweep` | 267-283 | origin `(27, 29.67, -50)` (272), 4 shots yaw 0/90/180/270, aim 10 m, tags `<tag>_yaw000…270` | same |

Interior scene setup: sets `/root/GameState` `state=playing`, `thief_id=spider`,
`active_contract_order=4`, `active_map_id=guildhall` (213-218), instantiates
`res://scenes/mission.tscn` (219), waits for `player` and group `swinging_doors` (≤1800 frames,
222-224), `_wait(40)` (225), closes the mission letter (227-229). `EYE_OFFSET 1.67` (`:17`).

Prep scene setup: instantiates `mission_prep_ui.gd` as a Control at `root.size` (122-127), then
`open_prep("guildhall", 1, "Solo", 0)` (128) — **map id guildhall, difficulty 1, solo, contract
order 0**; the stage always loads MissionLobby regardless. Camera print 137-143.

### 6.2 Env overrides the harness honours

| var | read at | effect |
|---|---|---|
| `TAT2_AO=off` | `weather_profile.gd:331,341-342` via `apply_gi_and_ao:367-378` | removes SSAO only; SSIL stays. Printed in `W9_CAPTURE` (`w9_capture.gd:116`) and `W9_CAPTURE_START` (`:298`) |
| `TAT2_GI=off\|ssil\|sdfgi` | `weather_profile.gd:330,334-338,350-366` | indirect pass |
| `TAT2_LIGHT_BUDGET` | `mobile_profile.gd:20,139-141` | light cap (`0` = no override) |
| `TAT2_SHADOW_HEROES` | `mobile_profile.gd:21,150-153` | hero shadow count |
| `TAT2_PERIPH_RANGE`, `TAT2_MERGE_CELLS`, `TAT2_PERF_CENSUS` | `level_loader.gd:205-207,492-518` | structural perf levers |
| `W9_QA_OUT` | `w9_capture.gd:44-47`; exported by the wrapper `w9_capture.sh:35` | output dir (default `<repo>/build/qa/w9/captures`) |
| `W9_PERF_XVFB` | `w9_perf.sh` only | force Xvfb for the perf runner |

There is **no** exposure / ambient / glow / tonemap override. `W9_ENV` only *reports* the live values
(`w9_capture.gd:200-206`, `:230-237`).

### 6.3 Wrapper (`build/qa/w9_capture.sh`, 50 lines)

`set -u`; `ROOT` = worktree root (13); `MODE/TAG/SIZE` from args (14-16); `AO=${TAT2_AO:-on}` (17);
outputs to `build/qa/w9/{captures,logs}` (19-22); aborts if another Godot/game process is running
(27-30); records `nvidia-smi` before/after (32,44); `export TAT2_AO` and `W9_QA_OUT` (34-35);
`flock /tmp/opencode/tat2-godot.lock` + `timeout 1800 xvfb-run -a -s '-screen 0 1920x1080x24'` +
`tools/godot --path game --rendering-driver vulkan --script … -- --mode=… --tag=… --size=…` (37-41);
prints `W9_CAPTURE_WALL`, the GPU samples, and a grep tail of
`W9_CAPTURE|W9_STAGE|W9_ENV|SCRIPT ERROR|SHADER ERROR|Vulkan|Godot Engine` (46-49).
Usage string lists only `prep|upper_foyer|foyer|saferoom` (5,14) — **stale vs the `.gd` dispatch**
(`prep_nosky`, `prep_noui`, `prep_noperiph`, `foyer_sweep` are undocumented in the `.sh`).

### 6.4 Stats (`build/qa/w9_frame_stats.py`, 128 lines)

`magick <img> -colorspace gray -resize 480x -depth 8 gray:-` → 256-bin histogram (`:47-56`);
`mean`, `p50`, `p95`, `pct_lt8` (`hist[:8]`), `pct_lt16`, `pct_gt200` (`:89-103`). Pillow
`convert("L")` + LANCZOS fallback only when `magick` is absent (`:59-69`). It emits **no** `nonblack`
field — that guard is the engine-side `W9_CAPTURE` line (`w9_capture.gd:102-118`, peak > 8 and
mean > 1) as the audit notes at `audit-report.md:44-48`.

### 6.5 How to add a scene / an override (mechanics)

- **Scene:** (a) header comment `w9_capture.gd:8`; (b) `.sh` usage lines 5 and 14 if it should be
  documented; (c) the `_run()` dispatch lists at **301/303**; (d) either a new pose branch in
  `_mission_interior()` (**247-260**, `eye`/`target`) or a diagnostic branch in `_prep()`
  (**147-194**, pattern: mutate the stage, `await _wait(n)`, print `W9_DIAG …`), or a new builder
  function returning `bool` and `await _save(_tag)`. `foyer_sweep` shows the multi-shot variant
  (**267-283**; tags `<tag>_yaw%03d`).
- **Engine-side env override:** add `const ENV_* := "TAT2_…"` + a static reader next to
  `ENV_GI_MODE`/`ENV_AO_MODE` (`weather_profile.gd:330-342`) and apply it inside
  `apply_gi_and_ao`/`apply_environment`, so mission and prep both see it; then print it in the
  `W9_ENV` line (`w9_capture.gd:200-206` and `:230-237`) so a log cannot claim an A/B it did not
  apply (the reason the existing lines exist, `w9_perf.gd:95-106`).
- **Exposure override (does not exist):** a downward A/B must be applied **after**
  `mission_prep_ui.gd:692` and `weather_profile.gd:1000`, because both are `maxf` and will ignore a
  lower preset value. The wrapper inherits the parent environment, so exporting any new `TAT2_*`/`W9_*`
  var from the caller reaches the process without editing the `.sh`; only `TAT2_AO` is re-exported
  explicitly (`:34`).

---

## 7. Facts that will bite the implementer

1. **`ACES 2.6` is a doc phrase, not the render state.** Live = AGX + 2.6 (`W9_ENV tonemap=4`). Editing
   `mission_prep_ui.gd:663` alone changes nothing while the preset loads.
2. **Both exposure sites are `maxf`** (`mission_prep_ui.gd:692`, `weather_profile.gd:1000`); a downward
   retune has to change the constant or replace the `maxf`.
3. **`stage_grade_values()` is dead code today** (only `probe_render_t07.gd:391-392`), and it returns
   `tonemap_exposure 1.15` / `ambient 0.16` for `gloomy`; adopting it drops the stage from 2.6/1.8 to
   1.15/0.16 in one step.
4. **`level_loader.gd` cannot change exposure/ambient/glow/tonemap** — it has no such assignment.
   Exposure work belongs to `weather_profile.gd` or `mission_prep_ui.gd`.
5. **The interior overshoot has a P2-owned local cause**: two shadowless foyer fills of 1.6/1.3 at
   3.3 m and 14.1 m from the upper-foyer eye (`mission_controller.gd:564-580`). Any A4-only retune
   changes the whole map, not just that room.
6. **`_light_score` uses the render curve** (`level_loader.gd:6456-6466`); changing
   `light_energy_for_intensity` also changes which 159 lights are kept and which 6 get shadows.
   Changing only `_build_light` would desync ranking from rendering.
7. **Prep loads two lobby sublevels with `max_lights = 64` and no collision** (`mission_prep_ui.gd:704-709`);
   `map_hint` is `""`, so no protected lights apply. MissionLobby_Periphery is 1,740 of the 2,107
   meshes — the `prep_noperiph` diagnostic (uncommitted) is the A/B for the near-facade question.
8. **`prep_skyline` band constants are test-only** (`:122-124`); runtime placement never clamps them,
   so an out-of-band data edit renders silently and only P14 fails.
9. **Retiring `prep_skyline` breaks two tests by design** (`test_t05_ui_contract.gd` P13/P14 and
   `test_w7v_ui_acceptance.gd` W7V.31); the AGENTS.md rule requires documented evidence, not a
   weakened assertion.
10. **`_apply_level_atmosphere` is a no-op on the Guildhall load set** (no Guildhall sublevel authors
    `sky_lights`/`post_process`/`fog_volumes`) — so the interior ambient/exposure come from
    `weather_profile` only. Den does use a level post-process (`ThievesDenTest_P`).
11. **The `.sh` usage string is stale** (lists 4 scenes; the committed `.gd` supports 7, the working copy 9) and the harness has no
    exposure lever. `prep_nosky`/`prep_noui`/`prep_noperiph` are diagnostics, not required captures.
12. **`build/qa/w9_capture.gd` was being edited concurrently** (uncommitted `prep_noperiph` diff at
    08:22). Re-check `git diff -- build/qa/w9_capture.gd` before quoting line numbers from §6.

---

## 8. Citation index

- Measurements: `build/qa/w9/p0-report.md:13-40,55-112`; `build/qa/w9/audit-report.md:14-83`.
- Grade: `game/src/ui/mission_prep_ui.gd:81-108,656-739`; `game/src/core/weather_profile.gd:84-167,341-378,573-590,875-1061`;
  `game/src/core/weather_visuals.gd:414-434`; `game/src/missions/mission_controller.gd:246-296,830-878,886-912`.
- Light plan: `game/src/core/level_loader.gd:236-357,5025-5250,5710-5771,6115-6169,6456-6486,6581-6646`;
  `game/src/core/mobile_profile.gd:14-21,139-171`; `docs/reports/remediation-20261125/T07-render.md:40-126,350-376`.
- Prep: `game/src/ui/mission_prep_ui.gd:50-124,656-946`; `game/data/expansion/prep_skyline.json`;
  `game/tests/test_t05_ui_contract.gd:166-188`; `game/tests/test_w7v_ui_acceptance.gd:21,197,242-252`;
  `docs/reports/remediation-20261125/T05-ui.md:40-81,340-370`.
- Scorecard: `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md:27-30,54-60,84,92,261-303`.
- Harness: `build/qa/w9_capture.gd` (310-line working copy), `build/qa/w9_capture.sh`,
  `build/qa/w9_frame_stats.py`, `build/qa/w9_perf.gd:95-106`.
- Brief/ownership: `/home/john/Projects/TAT-2/build/qa/w9/W9_BRIEF.md` §File ownership.
