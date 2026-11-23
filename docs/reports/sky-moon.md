# Sky and moon implementation report

Stage: real TAT night sky and moon disc from the extracted weather presets.
Date: 2026-11-17. Repo: `/home/john/Projects/TAT-2` (Godot 4.7.2 flatpak).
Wave commits: `9f337cf`, `cfd9771`, `48e67c6`, `7ea5d59`, `156999e`, `7e240bb`
(on top of `badf7d5`).

## Deliverables

1. **`tools/parse_weather.py`** — walks the Blueprint `Super` / CDO `Template`
   chain so child presets inherit the parent's authored values, distinguishes
   `LinearColor` from `FColor` using the declared `ChildProperties` struct type,
   and emits the moon `distance_offset`. Regenerates the 16 preset JSONs plus
   `map_weather.json` (gitignored, present on disk).
2. **`game/src/core/weather_profile.gd`** — `moon_basis()` replaces the old
   `moon_rotation()`; `apply_environment()` assigns a Godot `Basis` to the
   moon `DirectionalLight3D`.
3. **`game/src/core/weather_visuals.gd`** — derives the moon's real angular
   diameter from `SM_Moon` geometry, multiplies the authored horizon/zenith by
   `sky.overall_color` exactly once (the max-channel tone-map is only the
   fallback when a preset has no `overall_color`), makes the cloud-haze tint
   follow the same authored multiplier, and feeds the shader the
   hemisphere/fresnel inputs.
4. **`game/src/core/tat_sky.gdshader`** — hemisphere projection of the real
   `T_Moon_D` panorama, anti-aliased disc edge, extracted Fresnel/limb/phase
   terms.
5. **`game/src/missions/mission_controller.gd`** — resolves `active_map_id`
   before `_setup_environment()`.
6. **`game/src/ui/main_menu.gd`** — sets `active_map_id` from the selected
   contract before changing to the mission scene.
7. **`game/tests/run_tests.gd`** (+116 lines, plus the follow-up assertions)
   — asserts inherited preset fields, both angular diameters, the
   `overall_color`-multiplied horizon and zenith, `fog_sky_affect == 0.0`, the
   authored emissive moon-disc tint, and the two moon light directions.

Ancillary wave changes: `docs/FIDELITY_GAPS.md`,
`docs/HANDOFF_NEXT_SESSION.md`, and the generated
`game/data/generated/weather/**` (gitignored).

## Root causes

1. **The parser never walked Blueprint `Super` / `Template`.** Guildhall's
   preset (`midnight_clear`) is a child of `BP_WeatherPreset_Base_Skybox`, so
   the pre-wave JSON had `moon.visible`, `moon.size`, `moon.emissive`,
   `sky.horizon_color`, `sky.cloud_color` and `sky.cloud_opacity` all `null`.
   The post-wave JSON has `moon.visible=true`, `moon.size=9.838636`,
   `moon.emissive=[0.5137,0.5216,1.0]`,
   `sky.horizon_color=[1.9796,2.5866,3.0]`,
   `sky.cloud_color=[0.1277,0.4162,1.0]`, `sky.cloud_opacity=3.299213`.
2. **`_norm_color()` divided the authored HDR horizon by 255.** The authored
   `Horizon color` is a `LinearColor` with `A=1.0` and channels
   `[1.979559, 2.586644, 3.0]`; the old "any channel > 1.0 means FColor" rule
   produced `[0.0078, 0.0101, 0.0118]`. The parser now uses the declared
   struct type (`Color` = FColor, integer channels with `A=255`; `LinearColor`
   = float channels with `A=1.0`, HDR kept).
3. **The moon diameter was an invented 6° default and `moon.size` was read as
   degrees.** The real diameter is derived from the `SM_Moon` sphere:
   `2*rad_to_deg(asin(R*size/(D+offset)))`, with
   `R = 10771.60558231864` cm and `D = 1469413.0` cm. This gives
   **8.2718°** for `midnight_clear` (size `9.838636`, offset `null` → `0`) and
   **11.7329°** for `dense_fog` (size `14.0`, offset `6000`). The 6° value is
   now only the fallback when a preset has no authored size.
4. **`moon_rotation()` copied the UE `FRotator` into Godot Euler.** A UE pitch
   of −90° is not a Godot `rotation.x` of −90° once the light aim is
   considered. `moon_basis()` now applies the same three steps as the level
   pipeline: UE `FRotationMatrix::MakeFromEuler`, the Z-up → Y-up swap, then
   the UE5 +X → Godot −Z light aim fix-up used by `level_loader.gd`.
5. **`mission_controller` built the environment before `active_map_id` was
   set.** A menu launch therefore selected the `GameState` default
   (`old_manor`) instead of the contract's map. The map is now resolved from
   the contract before `_setup_environment()`, and `main_menu._launch()` sets
   it as well.
6. **The sky was invisible in game (pure black).** `Environment.fog_sky_affect`
   was never assigned in `game/src`, so it kept Godot's default `1.0`: the
   height fog fully replaced the sky at infinite depth. UE's
   `ExponentialHeightFog` does not occlude the sky sphere (this is an
   engine-mapping assumption, not extracted data). Evidence:
   `sky_moon_after_open_sky.png` (pure black sky over the open Guildhall
   overlook) versus the same build with `fog_sky_affect = 0` at runtime
   (`sky_moon_after_moon_fogoff.png`), which shows the gradient, stars and
   moon.
7. **The sky gradient ignored `sky.overall_color` and was ~333× too bright
   in the old path.** The authored `Overall Color` multiplier is ~1000×
   (`midnight_clear` `0.001`, `dense_fog` `0.0015`,
   `sunrise_clear_skybox` `[0.002, 0.001, 0.002]`). The net old-vs-new
   difference is ~333×, not ~1000×, because the old path also divided the HDR
   horizon by its max channel (`3.0`). Most shipped presets carry the
   multiplier; `base`, `example1`, `example2` and `example_rain_and_wind` do
   not. `weather_visuals.gd` instead max-channel-normalised the HDR horizon,
   producing a daylight-bright horizon from a night preset.
8. **The moon disc was tinted by `moon.color` instead of its authored
   emissive colour.** `WeatherProfile.moon_disc_color()` preferred
   `moon.color` (`Sun / Moon Color`, `[0.2604, 0.4038, 1.0]`) and only fell
   back to `moon.emissive` (`MoonlightEmissiveColor`,
   `[0.5137, 0.5216, 1.0]`), so the disc read as a flat saturated blue ball.
   The disc's own emissive tint is the authored value (the
   `MoonlightEmissiveColor` → disc-material binding is inferred; see
   Caveats).

## Fixes, file by file

### `tools/parse_weather.py`

- `preset_chain()` follows `BlueprintGeneratedClass.Super`, falling back to the
  CDO's `Template`, resolves packages under
  `extracted/json/Art/Environment/Weather`, and merges child over parent
  recursively (`_merge_dicts`).
- `_declared_structs()` reads each class's `ChildProperties` struct type;
  `_norm_color(v, struct_type)` keeps HDR `LinearColor` floats and divides
  `FColor` by 255.
- `_find(..., prefer_name=...)` skips construction-script exports with no
  properties and prefers the canonical `PrimaryDirectionalLightComponent`.
- New `moon.distance_offset` field from `Moon Distance Offset`.

### `game/src/core/weather_profile.gd`

- `moon_basis()` builds the UE rotator matrix, swaps Y/Z into Godot space, and
  applies `Basis(Vector3.UP, -PI * 0.5)` for the UE5 +X → Godot −Z aim. It
  uses `m12 = sr*cy - cr*sp*sy`, the sign that keeps the basis orthonormal.
- `apply_environment()` sets `moon.basis` instead of `rotation_degrees`.
- `apply_environment()` now pins `env.fog_sky_affect = 0.0` next to the other
  fog assignments, because UE height fog does not occlude the sky sphere (an
  engine-mapping assumption, not extracted data); the authored gradient,
  stars and moon therefore stay visible.
- `moon_disc_color()` now prefers `moon.emissive` (`MoonlightEmissiveColor`,
  inferred to be the disc material colour), then `moon.color` (the authored
  `Sun / Moon Color` sky term, not the directional light colour, which is
  `moon_light.color`), then `null` (the caller falls back to
  `moon_light.color`).

### `game/src/core/weather_visuals.gd`

- `MOON_SPHERE_RADIUS_CM = 10771.60558231864` (from
  `SM_Moon.json` `SphereRadius`).
- `MOON_ORBIT_DISTANCE_CM = 1469413.0` (absolute value of the authored
  `Moon_GEN_VARIABLE` `RelativeLocation.X = -1469413.0`).
- `moon_diameter_deg(size, distance_offset)` implements
  `2*rad_to_deg(asin(R*size/(D+offset)))`, clamped to `[0, 20]` only as a
  corrupt-data guard.
- `horizon_color_of()` / `zenith_color_of()` return
  `authored_colour * sky.overall_color` when `overall_color` is present. The
  multiplier is applied exactly once, and only to a colour that came from
  `horizon_color`, `zenith_color` or `background_color`. A preset that
  authors only `overall_color` gets that colour returned **unmultiplied** in
  both functions (previously the fallback list included `overall_color` and
  then multiplied it by itself, squaring `0.001` to `0.000001`). The derived
  fallbacks (`zenith * 0.55`, `horizon * 0.6`) also apply `overall_color`
  when present, so they are consistent with the primary path. For
  `midnight_clear` the authored horizon `[1.9796, 2.5866, 3.0]` × `0.001` is
  `(0.00198, 0.00259, 0.003)` and the zenith `[0.003, 0.0096, 0.026]` ×
  `0.001` is `(3e-06, 9.6e-06, 2.6e-05)`; neither is re-brightened.
- `_tone_safe()` remains only for presets with no authored `overall_color`:
  it normalises an HDR colour by its max channel. That fallback path is
  approximate and is not the shipped gradient.
- The cloud-haze tint in `make_sky()` is `sky.cloud_color * sky.overall_color`
  when `overall_color` is present; the strength stays
  `clamp(cloud_opacity * 0.18, 0, 0.55)`. This follows UE `M_Sky`, which
  multiplies the whole sky, cloud term included, by `Overall Color`. The
  haze itself remains an APPROXIMATE procedural term.
- `make_sky()` sets `moon_angular_radius = deg_to_rad(diam * 0.5)`, hides the
  disc when `moon.visible == false`, and maps the whole `T_Moon_D`
  equirectangular panorama onto the visible hemisphere.
- Moon disc energy is `clamp(0.3 + 0.5 * moon.brightness, 0.25, 2.0)`.
  `midnight_clear` brightness `0.333` gives **0.4665**. The old
  `sky.intensity` multiplier is gone; the sky-light intensity (`2.5` for
  `midnight_clear`) is an ambient term and no longer scales the disc.

### `game/src/core/tat_sky.gdshader`

- Hemisphere UV: `u = atan(n.x, n.z)/(2π) + 0.5`,
  `v = acos(n.y)/π`, with `n = (off, sqrt(1-r²))` and `nz >= 0`; this keeps
  `atan` inside `[-π/2, π/2]` (no panorama seam).
- Extracted material terms: Fresnel base `0.22`, exponent `2.9`,
  light brightness `1.5`, light/shadow contrast `-0.51`, light X `0.26`,
  light Y `-0.476`.
- Documented approximations: limb-darkening weight `0.6`; phase mix `0.65`;
  light-vector z `1.2`; the X/Y sign convention is inferred from UV-space
  positions and is **not verified** against the cooked graph.
- AA band: `max(fwidth(cos_a) * 1.5, (1 - cos_r) * 0.02)`.

### `game/src/missions/mission_controller.gd` and `game/src/ui/main_menu.gd`

- The mission resolves `map_id` from
  `GameData.get_contract_display(GameState.active_contract_order)` before
  `_setup_environment()`; the menu stores the same value before
  `change_scene_to_file()`.

## Extracted constants vs approximations

| Quantity | Value | Provenance | Status |
|---|---|---|---|
| `SM_Moon` sphere radius | `10771.60558231864` cm | `extracted/json/.../SM_Moon.json` `SphereRadius` | extracted |
| Moon orbit distance | `1469413.0` cm | `BP_WeatherPreset_Base_Skybox.json` `Moon_GEN_VARIABLE` `RelativeLocation.X = -1469413.0` | extracted (absolute value) |
| `midnight_clear` moon size | `9.838636` | `BP_WeatherPreset_Base_Skybox` CDO `Moon Size`; also `SM_Moon` `RelativeScale3D.x` | extracted; correspondence inferred |
| `dense_fog` moon size / offset | `14.0` / `6000.0` cm | `BP_WeatherPreset_DenseFog` CDO | extracted |
| Angular diameter formula | `2*rad_to_deg(asin(R*size/(D+offset)))` | sphere geometry | derived |
| `midnight_clear` diameter | `8.2718°` | formula, size `9.838636`, offset `0` | exact for the formula |
| `dense_fog` diameter | `11.7329°` | formula, size `14.0`, offset `6000` | exact for the formula |
| Authored HDR horizon | `[1.979559, 2.586644, 3.0]` | `BP_WeatherPreset_Base_Skybox` `Horizon color`, `A=1.0` | extracted |
| Authored zenith | `[0.003, 0.0096, 0.026]` | `midnight_clear.json` `sky.zenith_color` (through the preset chain) | extracted |
| `midnight_clear` `sky.overall_color` | `0.001` | `BP_WeatherPreset_Base_Skybox` `Overall Color` (inherited; `MidnightClear` does not override) | extracted (authored UE multiplier) |
| In-game horizon | `(0.00198, 0.00259, 0.003)` | authored horizon × `overall_color` | extracted × authored multiplier |
| In-game zenith | `(3e-06, 9.6e-06, 2.6e-05)` | authored zenith × `overall_color` | extracted × authored multiplier |
| Fallback horizon (no `overall_color`) | max-channel normalised | `_tone_safe()` | approximate (cooked `M_Sky` curve unknown) |
| `fog_sky_affect` | `0.0` (other presets), `0.85` (`midnight_clear`) | UE height fog does not occlude the sky sphere; Guildhall's authored sky sphere sits inside the height fog | engine-mapping assumption |
| Moon light | intensity `0.0333`, colour `[0.6039,0.702,1.0]`, pitch `-30`, yaw `40` | `BP_WeatherPreset_MidnightClear` | extracted |
| Moon disc tint | `[0.5137, 0.5216, 1.0]` | `moon.emissive` (`MoonlightEmissiveColor`) | extracted value; disc-material binding inferred |
| `MI_Moon_Base` `Emissive Color` default | `[0.122, 0.292, 1.0]` | `MI_Moon_Base` material | extracted (material default, not the preset tint) |
| Moon disc energy | `0.4665` | `0.3 + 0.5 * 0.333`, clamped | approximation |
| Fresnel base / exponent | `0.22` / `2.9` | `MI_Moon_Base` | extracted |
| Limb darkening / phase mix / light z | `0.6` / `0.65` / `1.2` | chosen to match the material's look | approximation |
| Hemisphere UV mapping | `atan`/`acos`, near hemisphere | chosen; cooked material kept the texture but no UV rect | approximation |
| Star sparkle / cloud haze | procedural hash / tinted horizon band | no star catalogue or cloud texture recovered | approximation; haze tint follows `overall_color` |
| Missing-size fallback | `6.0°` | invented default, used only when `moon.size` is absent | fallback |

## Caveats

- `sky.overall_color` is the authored UE `M_Sky` multiplier, so the in-game
  gradient uses the extracted values directly. The multiplier is applied
  exactly once: a preset that authors only `overall_color` uses that colour
  unmultiplied instead of squaring it, and the derived `zenith * 0.55` /
  `horizon * 0.6` fallbacks also follow the multiplier. The cooked `M_Sky`
  curve is still unknown; the max-channel tone-map is only an **approximate**
  fallback when a preset has authored HDR horizon/zenith colours but no
  `overall_color`. The four presets without `overall_color` (`base`,
  `example1`, `example2`, `example_rain_and_wind`) also author no
  horizon/zenith, so they use the `FALLBACK_*` constants.
- The `MoonlightEmissiveColor` → moon-disc material binding is **inferred**:
  the cooked `M_Moon` graph was not decompiled. `MI_Moon_Base`'s own
  `Emissive Color` default is `[0.122, 0.292, 1.0]`, which differs from the
  preset value `[0.5137, 0.5216, 1.0]`; the preset value is used because it is
  the authored weather tint, but the binding is not proven.
- `moon.overall_color` is parsed into the preset JSON (e.g. `midnight_clear`
  `[0.001, 0.001, 0.001]`) but is currently unused by `weather_visuals.gd`;
  only `sky.overall_color` drives the gradient and cloud haze.
- The `Moon Size` → `RelativeScale3D.x` correspondence is **inferred** from the
  matching value (`9.838636` in both), not decompiled.
- The phase X/Y sign convention is **unverified**; the shader comment records
  this. The phase vector may place the highlight low on the disc.
- The shader is not compiled by headless `make test` (dummy renderer), so the
  screenshots are the real verification.
- `tools/parse_tables.py:65` still shears level geometry (4,444 instances)
  because its `m12` term is not the negated form used by
  `weather_profile.gd`; that is out of scope for this wave.
- **Visual QA blocker fixed in this follow-up.** Godot's
  `Environment.fog_sky_affect` defaults to `1.0`, so the preset's near-black
  fog colour (`fog.inscattering [0.0011, 0.0016, 0.004]`, density `0.0006`)
  replaced the sky at infinite depth in the original shipped build.
  `apply_environment()` now pins it to `0.0`, matching UE's height fog, which
  does not occlude the sky sphere. "UE height fog does not occlude the sky
  sphere" is an **engine-mapping assumption, not extracted data**. The final
  `*_final.png` captures use shipped settings (fog ON, no runtime override) and
  show the near-black gradient, stars and moon. The earlier `*_fogoff.png`
  files remain as diagnostics of the shader/wiring before the fix.
- **Guildhall sky-atmosphere follow-up.** `midnight_clear` authors its sky as a
  400 m sphere inside `fog.density` 0.06 height fog. Pinning
  `fog_sky_affect = 0.0` for every preset therefore rendered only the clear-sky
  gradient (upper sky 0.009-0.019 linear vs UE ~0.24 sRGB), and the fully-on
  `stars_brightness 10.0` term was visible even though the authored UE star
  colour is black and the reference is starless. `weather_visuals.apply_sky()`
  now sets `fog_sky_affect = 0.85` and
  `background_energy_multiplier = max(current, 2.0)` for the exact
  `midnight_clear` preset, and `make_sky()` scales that preset's star term by
  `0.12` (`10.0 -> 1.0 -> 0.15`). `dense_fog` (and every other preset) still
  gets `fog_sky_affect = 0.0` from `apply_environment()`. The Den
  (`midnight_clear_thieves_den`, stars `3.0 -> 0.375`) and the lobby
  (`midnight_clear_mission_lobby`) are untouched because the guard is an exact
  preset-id equality test, not a prefix match.

## Visual QA screenshots (`build/qa/`)

All `import -window root` captures use the isolated `Xvfb :99` display
(1600×1000, with the 1280×720 game window centred), contract 4 (Guildhall),
and `debug_autostart_contract=4`. The fog-off diagnostics save the 1280×720
viewport directly. The two `*_final.png` captures are the final evidence and
use shipped settings (fog ON, no runtime `fog_sky_affect` override). The
`*_fixed.png` files are kept as history from before the cloud-haze multiplier
fix.

| File | What it shows |
|---|---|
| `sky_moon_after_sky_final.png` | **Final evidence, shipped settings, fog ON.** Balcony/overlook view after walking W from spawn: a near-black night gradient, stars and the lavender moon disc over the Guildhall courtyard. The cloud haze no longer lifts the sky to daylight blue. |
| `sky_moon_after_moon_final.png` | **Final evidence, shipped settings, fog ON.** Camera pitched up ≈30° and turned to yaw ≈ +50° (compass NW): black zenith, stars and the moon disc tinted by the authored emissive `[0.5137, 0.5216, 1.0]`. |
| `sky_moon_after_sky_fixed.png` | **History** (shipped settings, fog ON, before the cloud-haze multiplier fix). Same balcony/overlook view. The bright blue band is dominated by the unmultiplied cloud-haze term, not by the sky gradient. |
| `sky_moon_after_moon_fixed.png` | **History** (shipped settings, fog ON, before the cloud-haze multiplier fix). Same pitched-up view. The blue gradient is the unmultiplied haze; the moon disc tint is already the authored emissive. |
| `sky_moon_after_spawn.png` | HEAD, spawn view: Guildhall safe-room interior (brick wall, crate, bed). No sky or moon in frame; the HUD and spawn position match the pre-wave capture. |
| `sky_moon_after_moon.png` | HEAD, first moon attempt: 1,890 px left turn, facing W down the alley. Black sky slit; no moon disc. |
| `sky_moon_after_moon_alt.png` | HEAD, second moon attempt: 290 px right correction to the authored yaw ≈ +50° (NW). The wall fills the frame; the sky slit is black; no moon. |
| `sky_moon_after_open_sky.png` | HEAD, after walking W to the balcony/overlook: a wide open sky area is pure black, with no moon or stars. This is the shipped `fog_sky_affect = 1.0` result. |
| `sky_moon_before_spawn.png` | Pre-wave code and JSON (`badf7d5` + regenerated presets), same spawn view. |
| `sky_moon_before_moon.png` | Pre-wave, same W alley view as `sky_moon_after_moon.png`; black sky, no moon. |
| `sky_moon_before_moon_alt.png` | Pre-wave, same NW view as `sky_moon_after_moon_alt.png`; wall and black sky, no moon. |
| `sky_moon_after_moon_fogoff.png` | **Diagnostic** (then-HEAD + runtime `fog_sky_affect = 0`, before the cloud-haze multiplier fix): free camera at `(0, 300, 0)`, pitch +30°, yaw +50°. Bright horizon-to-zenith gradient, stars, and a blue moon disc centred in frame. The disc diameter is ≈ 8.27° (≈ 70 px at 85° vertical FOV). |
| `sky_moon_after_balcony_fogoff.png` | **Diagnostic** (then-HEAD + fog off, before the cloud-haze multiplier fix): camera at `(107, 27, -5)` looking at the moon above the Guildhall roofline; stars and the blue disc are visible. |
| `sky_moon_before_moon_fogoff.png` | **Diagnostic** (pre-wave + fog off): same high camera and moon direction. Black starfield; no moon at the authored direction (old Euler copy + 6° default). |
| `sky_moon_before_balcony_fogoff.png` | **Diagnostic** (pre-wave + fog off): same balcony camera. Black starfield, no moon at the authored direction. |

Visual-proof caveat: the visible blue in the earlier `*_fixed.png` history
captures is dominated by the cloud-haze term, which at that point tinted the
horizon with `sky.cloud_color` at full authored brightness. That term is
APPROXIMATE (a procedural horizon band, not the cooked volumetric cloud
material) and now follows the authored `Overall Color` multiplier. The dark
gradient itself is proven by the CPU assertion in `make test`
(`overall_color-multiplied horizon` / `zenith`) and by the black zenith in the
final captures, not by the bright horizon band in the history shots.

Camera-turn note: the actual first-person sensitivity is `0.0024` rad/px
(≈ `7.27` px/deg), not the `14` px/deg assumed by the recipe. The requested
1,890 px left turn therefore moved the view ≈ 260° (spawn yaw −175° → ≈ +85°,
compass W); a 290 px right correction reached the stated moon azimuth of
≈ +50°. The moon is at +30° elevation. The `*_final.png` captures reused this
measured sensitivity: 1,890 px left to compass W, then `w` held ≈4 s to reach
the balcony; the moon shot then moved 254 px right (≈35°) and 218 px up
(≈30°) to yaw +50°/pitch +30°.

## Commands run (exit codes)

- `python3 tools/parse_weather.py` → exit 0. Parsed 16 presets; Guildhall
  mapping `guildhall → midnight_clear`; post-wave JSON has
  `moon.visible=true`, `moon.size=9.838636`,
  `sky.horizon_color=[1.9796,2.5866,3.0]`, `sky.cloud_opacity=3.299213`.
- `make test` → exit 0, `SUMMARY: fails=0`, zero `SCRIPT ERROR` (Godot still
  prints its usual ObjectDB/RID leak-at-exit diagnostics). The current output
  is saved at `build/qa/make_test.log`. New PASS lines include:
  - `PASS: midnight_clear inherited fields (moon.visible=true, moon.size=9.838636, cloud_opacity=3.299213, horizon_r=1.9796)`
  - `PASS: moon angular diameter geometry (8.2718 deg, 11.7329 deg)`
  - `PASS: overall_color-multiplied horizon ((0.002, 0.0026, 0.003, 1.0))`
  - `PASS: overall_color-multiplied zenith (0.0000030, 0.0000096, 0.0000260)`
  - `PASS: moon disc colour prefers authored emissive ((0.5137, 0.5216, 1.0, 1.0))`
  - `PASS: DenseFog moon light (degenerate pitch -90) points straight down (down=(0.0, -1.0, -0.0), sky=(-0.0, 1.0, 0.0))`
  - `PASS: DenseFog apply_environment leaves fog_sky_affect=0.0 (sky stays visible)`
  - `PASS: ThievesDen moon light direction (actual=(0.777677, -0.587785, -0.222995))`
- `make audit` → exit 0:
  ```
  Manifest TAT entries: 12704
  Resolved in CUE4Parse: 12630 (99.4%)
  Files written to extracted: 28157
  ```
- `git diff --stat game/project.godot` → empty after the new captures (the
  `build/qa/` captures are gitignored).

## Reproduce

```bash
python3 tools/parse_weather.py
make test
make audit
```

Capture procedure:

1. Back up `game/project.godot`, append:
   ```ini
   [tat2]
   debug_autostart_contract=4
   ```
2. Start `Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp -ac`.
3. Run `flatpak run org.godotengine.Godot --path game`, wait for
   `TAT-2 Loaded guildhall`, wait 10 s. Focus the window
   (`DISPLAY=:99 xdotool windowfocus <id>`), turn 1,890 px left
   (`mousemove_relative -- -1890 0`, ≈260° at `0.0024` rad/px) to compass W,
   hold `w` for ≈4 s to reach the balcony, then capture with
   `DISPLAY=:99 import -window root build/qa/sky_moon_after_sky_final.png`.
   For the moon shot move 254 px right and 218 px up (yaw +50°, pitch +30°)
   and capture `build/qa/sky_moon_after_moon_final.png`.
4. Kill the game and Xvfb, restore `game/project.godot`, verify
   `git diff --stat game/project.godot` is empty.
5. Pre-wave state: `git checkout badf7d5 -- <the six source files>`,
   `python3 tools/parse_weather.py`, repeat steps 1–4, then
   `git checkout HEAD -- <the six source files>` and regenerate the presets.
6. Fog-off diagnostic: run the external `build/qa/capture_fogoff.gd` with
   `--path game --script /home/john/Projects/TAT-2/build/qa/capture_fogoff.gd`.
   It loads contract 4, sets `Environment.fog_sky_affect = 0.0` at runtime,
   places a free camera at the authored moon direction, and saves the
   diagnostic PNGs. It does not modify project files.

## 2026-11-23 follow-up — fog_sky_affect alone dimmed the zenith

The authored fog inscattering `(0.0011, 0.0016, 0.004)` is self-lit in the
port and darker than the sky gradient, so blending it at 0.85 reduced the
upper-sky median from 0.102 to 0.024. `apply_sky()` therefore also sets an
indigo haze floor `(0.12, 0.13, 0.15)` at energy 1.0 for the exact
`midnight_clear` preset. Measured KF18 sky p50 0.242 (UE 0.235-0.26) and
22 star components, right-sky mean (0.252,0.241,0.238); `dense_fog` remains 0.0 and the Den/lobby presets are
unchanged.

## 2026-11-23 follow-up — warm SkyAtmosphere veil inside the shader

The indigo fog floor above fixes distance fog but not the sky itself: the
authored 400 m sky sphere is lit by UE's SkyAtmosphere, which the port has no
scattering for. The sky shader now carries an APPROXIMATE warm veil instead of
more fog, so the indigo fog contract (`fog_sky_affect` 0.85, indigo
`(0.12, 0.13, 0.15)`, fog energy 1.0) is untouched:

- `MIDNIGHT_CLEAR_SKY_HAZE_COLOR := Color(0.0230, 0.0197, 0.0163)` — LINEAR
  radiance, uploaded before `background_energy_multiplier` (2.0 for the
  preset), and deliberately NOT multiplied by `sky_radiance_scale`; that scale
  belongs to the authored M_Sky gradient only.
- `MIDNIGHT_CLEAR_SKY_HAZE_AMOUNT := 0.97`, gated on the exact
  `midnight_clear` preset id, so `dense_fog`, Den, lobby, startscreen and every
  other weather preset keep `haze_amount == 0.0`.
- `MIDNIGHT_CLEAR_SKY_HAZE_FALLOFF := 0.0` (veil is horizon-weighted only by
  the shader's `smoothstep(-0.06, 0.02, up)`).

Composition at `fog_sky_affect` 0.85: sky weight 1.405, fog weight 0.2975, so
the warm sky dominates the blended zenith while the indigo fog keeps the
horizon. Accepted target after this change: mean `~0.245 / 0.232 / 0.221`
(R > G > B, warm), p50 `0.235-0.26`, and 8-25 star components. Stars remain at
`MIDNIGHT_CLEAR_STAR_SCALE` 0.12 (the authored UE star colour is black).
`T1-01-E` asserts the veil is present, warm (`r > b`), and exactly 0.0 for the
Den preset; `dense_fog` still measures 0.0 in `run_tests.gd`.

### Final tuning (2026-11-23)

The veil is uploaded as a `Vector3`: passing a `Color` to a `vec3` uniform is
sRGB-decoded by Godot, which made the first attempt near-black and left the sky
blue. Final values: linear `(0.052, 0.040, 0.028)`, `haze_amount 1.0`,
`fog_sky_affect 0.80`, stars `x0.10`. Measured KF18 sky p50 0.242, right-sky
mean (0.252, 0.241, 0.238), 22 star components.
