# Weather implementation report

Stage: real TAT weather data (lighting/fog) replacing hand-tuned values.
Date: 2026-11-16. Repo: `<repo>` (Godot 4.7.2 flatpak).

## Deliverables

1. **`tools/parse_weather.py`** (new) — parses all 16
   `extracted/json/Art/Environment/Weather/BP_WeatherPreset_*.json`
   into `game/data/generated/weather/<preset>.json` (stable schema:
   preset/source/weather_tag + moon, sky, fog, moon_light, postprocess,
   rain sections; colours 0-1 floats; absent fields null) plus
   `game/data/generated/weather/map_weather.json`.
2. **`game/src/core/weather_profile.gd`** (new, RefCounted, static helpers,
   no autoload) — loads map table + preset on demand, typed getters,
   `apply_environment(env, moon, preset)` and `apply_for_map(env, moon, map_id)`.
3. **Wired into `game/src/missions/mission_controller.gd::_setup_environment()`** —
   weather first, hand-tuned values kept as fallback base, mobile glow
   override still applied last.
4. **Test suite section 17 in `game/tests/run_tests.gd`** — loads real
   `dense_fog.json` via `JSON.parse_string`, applies to fresh
   Environment/DirectionalLight3D, asserts JSON-derived values; checks
   map table, unknown-map fallback (returns false, env untouched), and
   empty-preset rejection.

## Files changed (mine only)

- `tools/parse_weather.py` (new)
- `game/src/core/weather_profile.gd` (new)
- `game/src/missions/mission_controller.gd` (modified: `_setup_environment`
  split into fallback helpers + weather attempt)
- `game/tests/run_tests.gd` (modified: +section 17)
- `game/data/generated/weather/**` (16 presets + `map_weather.json`;
  gitignored like other generated data, present on disk)
- `docs/reports/weather-implementation.md` (this file)

Untracked/modified files belonging to other waves
(`game/src/core/level_loader.gd`, `tools/parse_materials.py`,
`tools/tat-extract/Exporter.cs`, `docs/FIDELITY_GAPS.md`, etc.) were not touched.

## Commands run (exit codes)

- `python3 tools/parse_weather.py` → exit 0. Parsed 16 presets; mapping log:
  old_manor→dense_fog_old_manor, guildhall→midnight_clear,
  thieves_den→midnight_clear_thieves_den, jaspering_hall→heavy_rain,
  main_menu→midnight_clear_mission_lobby.
- `make test` (twice) → exit 0, `SUMMARY: fails=0`, `SCRIPT ERROR` count 0.
  New line: `PASS: Real weather DenseFog applied (fog=0.004 moon_energy=0.25
  rot=(-90.0, 263.0, -54.52945))`.
- `cat game/data/generated/weather/map_weather.json` + preset JSONs — verified.

## Preset/map mapping table

| map id         | preset                       | weather tag              | provenance |
|----------------|------------------------------|--------------------------|------------|
| old_manor      | dense_fog_old_manor          | Weather.Type.DenseFog    | OldManor_P PresetOverrides DenseFog entry; preset named for OldManor |
| guildhall      | midnight_clear               | Weather.Type.MidnightClear | Guildhall_P manager has NO PresetOverrides → class default; MidnightClear is canonical night-clear |
| thieves_den    | midnight_clear_thieves_den   | Weather.Type.MidnightClear | ThievesDenTest_P routes all 5 types to this one preset |
| jaspering_hall | heavy_rain                   | Weather.Type.HeavyRain   | FTUE_P routes all 4 types to this one preset |
| main_menu      | midnight_clear_mission_lobby | Weather.Type.MidnightClear | MissionLobby_P routes all 5 types to this one preset |

## Conversion factors (all documented in `weather_profile.gd` header)

- **Fog density ×0.01** — UE centimetres → Godot metres (same convention as
  `tools/parse_tables.py`). DenseFog 0.4 → 0.004.
- **Moon energy = clamp(UE_intensity × 10, 0.05, 1.0)** — UE night lux
  (0.01–0.05) is ~2 orders below a Godot energy unit; ×10 preserves
  inter-preset ratios (Gloomy 0.1 dimmest … Stormy/HeavyRain 0.5 brightest).
  Presets with no Intensity key (ThievesDen, MissionLobby) skip the override.
- **Rotation copied pitch/yaw/roll → rotation_degrees** — UE pitch −90
  (straight down) equals Godot rotation.x = −90 (−Z maps to −Y); verified.
- **Ambient = SkyLight colour + clamp(intensity, 0.02, 1.0)** — direct units;
  only MissionLobby (5.0) hits the cap.
- **Saturation = ColorSaturation.X (else Midtones.X); brightness =
  clamp(GainMidtones.X − 1, ±1); tonemap_exposure = 1 + AutoExposureBias;
  glow_intensity = clamp(Bloom × 0.08, ≤0.8)** — DenseFog 8.0 → 0.64,
  reproducing the old hand-tuned 0.65 from real data.
- **fog_sun_scatter** = luminance of DirectionalInscattering, clamped 0–1.
- **Vignette / white-temp / film curves / sky & cloud materials / moon params**
  parsed and exposed via getters; Godot Environment has no slots for them.
- **Rain**: `enabled = EnableRain` if the key exists, else
  `intensity >= 0.5` (covers Gloomy: intensity 1.0, no flag); intensity ≈ 1e-6
  (DenseFog) treated as ~dry but flag preserved. No particles spawned.

## Self-audit / unfinished

- Rain wiring intentionally not implemented (per spec; getters ready).
- Guildhall choice is an assumption (no overrides in data; quest-graph tag
  queries only gate path blockers, not the active weather). Flagged in the
  `reason` field of `map_weather.json`.
- `apply_environment` returns false only for empty/missing presets; missing
  individual fields are skipped (env keeps fallback) — stricter than the
  letter of the spec but preserves the fallback guarantee.
- Pre-existing exit-time leak warnings (`ObjectDB instances leaked`) remain;
  they come from the test harness teardown, not this change.
