# W5C — rainy Guildhall, horizon haze and west Den window staging

Wave: W5C (weather/backdrop). Worktree: `/tmp/opencode/tat2-w5c-weather`.
Date: 2026-11-24. Base: `950f7ca` (docs) on `main`.

Scope: the Guildhall weather mapping, the near-field fog calibration, the
black-horizon sky term and the weather shader's cloud tint, plus the Thieves'
Den backdrop staging (anchored to the framed west window the telescope faces).
`level_loader.gd`, masked opacity and WorldGrid are untouched (W5B owns them).
No shared docs are edited; this is the wave's own report.

## 1. Guildhall weather mapping (producer, evidenced)

`Guildhall_P` authors a `TATWeatherManager` with **no `PresetOverrides`**, so the
old producer fell back to a hard-coded "guildhall → midnight_clear" guess. The
preset is now chosen from what the hub level actually builds:

| evidence key | dump | actor | count |
|---|---|---|---|
| `wet_ground` | `Guildhall_PeripheryA` | `BP_Puddle_C` (+ `Puddle` landscape layer) | 5 |
| `haze_volumes` | `Guildhall_LocalVolumetric` | `BP_LocalFog_Volume_C` (main entrance, parade square, roofs, periphery) | 27 |
| `cloud_masks` | `Guildhall_Clouds` | `BP_CloudMask_Object_C` | 4 |
| `moon_actors` | `Guildhall_LightingNoGameplay` | `BP_MoonShape_C` (+ `BP_Light_SpotFakeMoonFills`) | 8 |

`tools/parse_weather.py` counts those exports (`authored_evidence()`) and picks
**`gloomy`**: `RainIntensity 1.0`, `GroundWetness 1.0`, `FogDensity 0.16`,
`Stars 0`, `MI_Sky_HeavyRain` dome, `Moon visibility True`. HeavyRain is
excluded by its own authored `Moon visibility = False` (the hub authors moon
shapes and moon fill spots); Stormy by its near-black zenith (0.068) and
`GroundWetness 0.5`. The counts and the resulting reason are written into
`map_weather.json` (git-ignored), so the choice is auditable at runtime.

## 2. Near-field fog calibration (`FOG_DENSITY_SCALE`)

`0.01` (plain cm→m) gave the authored 0.06 Guildhall fog **1.8 % obscuration at
30 m**; the rainy streets read like a clear night. The scale is now **0.03**,
documented as a readability calibration rather than a unit conversion:

| preset | FogDensity | density/m | 20 m | 30 m | 60 m | 120 m |
|---|---|---|---|---|---|---|
| gloomy (guildhall) | 0.16 | 0.0048 | 9 % | 13 % | 25 % | 44 % |
| midnight_clear | 0.06 | 0.0018 | 4 % | 5 % | 10 % | 19 % |
| dense_fog (Old Manor) | 0.40 | 0.0120 | 21 % | 30 % | 51 % | 76 % |

The sky veil is deliberately **not** part of this factor (see §3), so the
density change cannot darken the horizon.

## 3. Horizon haze floor / sky term

Both `fog_sky_affect` and `volumetric_fog_sky_affect` were pinned to `0.0`, and
the height fog's authored inscattering is pre-exposed (0.0003–0.001 per
channel), so any veil over the sky rendered black. Changes, no exposure change:

- `weather_profile.gd`
  - `FOG_SKY_AFFECT_FLOOR = 0.80`, `VOLUMETRIC_FOG_SKY_AFFECT_FLOOR = 0.15` for
    outdoor presets; the indoor Den keeps `0.0` (its sky is a window pane).
  - `fog_haze_color()`: the authored overcast-dome hue (`sky.cloud_color`,
    falling back to the fog inscattering hue) rescaled to
    `FOG_HAZE_LUMA_FLOOR = 0.05` linear luminance. The scene fog therefore has a
    real haze colour instead of a pre-exposed near-black; the Den keeps its
    exact authored value and the old energy/aerial-perspective path.
  - `gloomy` joins `midnight_clear` on the AGX tone path (the hub's night was
    the ACES-clipping case); the 1.15 exposure lift stays midnight_clear-only.
- `weather_visuals.gd` / `tat_sky.gdshader`
  - new `horizon_haze` (0.55 outdoor, 0 indoor) + `horizon_haze_color`
    uniforms: a horizon-weighted (|up|⁴) mix that cannot touch the zenith or
    the exposure. The colour starts from the KF16/KF17-calibrated neutral
    (0.12/0.13/0.15) tinted 35 % by the authored cloud colour and rescaled back
    to the neutral luminance (0.129), so a saturated cloud tint cannot glow.
- One moonlit cloud tint in the shader: `cloud_tint = cloud_color *
  (1 + moon_color * moon_scatter)` now feeds both the FBM wisps and the horizon
  band (raw `cloud_color` is no longer mixed, `lit_cloud` is gone). Coverage
  moves only the FBM threshold (`smoothstep(lo, hi, n)`); opacity
  (`cloud_haze`) scales only alpha (`cloud_alpha = coverage * cloud_opacity`).

## 4. Den backdrop: west window staging

Measured with the real `LevelLoader` on the three Den sublevels (ray scan
through the actual colliders, headless):

- `window_positions` parsed = **1** entry: `SM_ThievesDen_WindowBorder` at
  `(5.2374, 40.6471, 266.6629)` — the 0.87 × 1.15 m hatch on the south wall.
  The loader's old hard-coded `win_pos` was exactly that hatch.
- The authored telescope rig (`BP_HidingSpot_Telescope_C_1`,
  `CameraComponent` rel `(0.1, 0, 1.7)` m, **yaw 148° pitch 0**) looks
  **west-north** at the authored `BP_CoolThing_C_1` cheese/moon kit
  (UE `(-1668.9495, 27900.438, 5110.168)` cm → `(-16.69, 51.10, 279.00)` m).
- The framed west opening in the Den shell: `z 270.4..272.4`, `y 41.0..45.1`
  (with a horizontal mullion at `y ≈ 43.6`), wall plane `x = -6.06` — a
  2.0 × 4.1 m arch, not the hatch.

`mission_controller.gd` now:

- consumes `ue_level_data["window_positions"]` through a pure
  `select_den_window_anchor(eye, windows, facing)` (within 55° of the authored
  axis and 2.5 m lateral, smallest lateral offset wins) and falls back to the
  measured `DEN_WEST_WINDOW_ANCHOR = (-6.06, 43.05, 271.4)` with
  `den_telescope_facing()` (yaw 148°);
- stages the moonbeam, god-ray, window backlight and world vista on the west
  opening, with the shaft landing mid-room along the same axis;
- softens the replica into a haze silhouette: `den_vista_silhouette_color()`
  uses the Den preset's authored sky cloud hue at 0.065 linear luminance
  (measured runtime colour `(0.02, 0.076, 0.105)`), moon emission 1.6 → 1.15,
  cheese emission 0.9 → 0.55;
- aims the ponder camera's fallback focus 20 m down the authored axis (the
  camera-space KF05 diorama is unchanged and supplies the framed composition).

Runtime probe (headless Den mission load, `TAT2_NO_DEN_PROBE=1`):

```
TAT-2 Den window staging: source=authored-west-opening anchor=(-6.06, 43.05, 271.4) parsed_windows=1 facing=(-0.848048, 0.0, 0.529919)
W5C-DEN beam=(-6.06, 43.05, 271.4)
W5C-DEN vista=(-6.356817, 43.05, 271.5855) focus=(-35.19045, 43.7, 289.6027)
W5C-DEN backlight=(-6.568829, 43.05, 271.718)
W5C-DEN silhouette=(0.02, 0.0762, 0.1053, 1.0)
W5C-DEN windows=[(5.2374, 40.6471, 266.6629)]  den_splits=0
```

(The parsed hatch is correctly rejected; `den_splits=0` is the loader's
window-wall split, untouched by this wave.)

## 5. Tests

Suite 10/17 additions (all in `run_tests.gd`), `test_review_visibility` 5.1 and
the tier-4 comment assertion were adjusted where they encoded the old mapping
(`guildhall → midnight_clear`, `density × 0.01`, `fog_sky_affect == 0`); no
assertion was weakened — each now derives its expectation from the producer
output, `FOG_DENSITY_SCALE`, the floor constants or the map table.

New suite-17 checks:

- `W5C Guildhall weather = authored gloomy` (preset fields + evidence counts);
- `W5C near-field fog calibrated` (transmittance 0.91/0.87/0.56 at 20/30/120 m);
- `W5C horizon haze floor` (outdoor 0.55 @ lum 0.129, Den 0, exposure
  untouched);
- `W5C sky shader one moonlit cloud tint + coverage/opacity split`
  (structural shader invariants);
- `W5C Den window staging anchors the west framed window` (facing, parsed
  selection, hatch rejection, west anchor, silhouette luminance).

Gate results on the final tree are listed in §7.

## 6. Producer / audit diff

- `tools/parse_weather.py`: sha256 `21bf74b51093…` → `fb6dfecec7ba…`.
- `gen:weather`: 17 files, 38,494 → 38,638 bytes (only `map_weather.json`
  changed: new `reason`, `authored_evidence`; the 16 preset files are
  byte-identical, so no preset drift).
- `tools/audit_baseline.json`: only the `tools/parse_weather.py` entry was
  refreshed. `make audit-refresh-stamps` also offered to bless unrelated
  pre-existing drift (`parse_tables.py` / `parse_gameplay.py` gen:gameplay
  17 → 21 files, and the missing `vgmstream` CLI); those hunks were reverted so
  the baseline change stays scoped to this wave.

`make audit` on this tree still fails on exactly those three pre-existing
items and no weather item:

```
FAIL: baseline: producer tools/parse_tables.py   output gen:gameplay content differs from the baseline …
FAIL: baseline: producer tools/parse_gameplay.py output gen:gameplay content differs from the baseline …
FAIL: tool version drift: vgmstream: '… r2168 …' -> 'missing'
```

## 7. Gates

| gate | result |
|---|---|
| compile (`check_scripts_compile.gd`) | 96 checked, 0 broken |
| focused W5C check (mapping/fog/haze/tint/Den) | `W5C_SUMMARY: fails=0` |
| `run_tests.gd` (full) | `SUMMARY: fails=0` (SCRIPT ERROR 0, SHADER ERROR 0) |
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` |
| Den runtime probe | staging at the west opening (see §4) |
| `make audit` | weather pins refreshed; 3 pre-existing unrelated failures (§6) |

**A colour capture is deferred.** This host has no GPU run in this wave: no
`Xvfb`/Vulkan capture was taken, so the Guildhall rainy look, the haze gradient
and the Den window backdrop are **not visually verified**; only the structural,
numeric and runtime-placement evidence above exists.

## 8. What still needs a capture (and what to look at)

1. Guildhall gate/parade square at the authored framing: near haze at ~30 m,
   ~44 % veil at 120 m, lamps still warm (AGX, no exposure lift), horizon not
   black and not blue-glowing.
2. Guildhall sky at the zenith vs horizon: the authored gradient must survive
   above the horizon band (`horizon_haze` is |up|⁴ weighted).
3. Den [F] ponder: the KF05 diorama should still frame moon/rooftops/cheese,
   and the *room-side* west window should show a soft moonlit silhouette (not
   the hard cut-out) when the telescope is not raised.
4. Den west window: confirm the moonbeam/god-ray lands mid-room through the
   framed opening and not through the south hatch.
5. Old Manor dense fog after the 0.03 scale (0.012/m) — confirm the manor is
   foggy but not milk-flat, since the same scale now drives it.
