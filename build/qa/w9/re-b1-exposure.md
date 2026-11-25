# W9-P2 B1 — authored auto-exposure / post-process truth (RE)

Read-only research lane (no code changes, no Godot). Method: parsed all 12,541
`extracted/json/**/*.json` dumps, `extracted/raw/TAT/Config/DefaultEngine.ini`,
`game/data/generated/curves.json`, the standalone curve tables and every
Guildhall `.tatlevel.json`. This file archives the facts the p2 report cites.

## 1. Authored AEM — the shipped Guildhall chain

The authored auto-exposure is on the **weather-preset Blueprint CDO**
(`PostProcessComponent`), inherited by Gloomy — not on a placed volume and not
per room.

| Field | Base CDO | Base_Skybox | Gloomy (Guildhall) | Shipped |
|---|---:|---:|---:|---:|
| Method | `AEM_Basic` | inherited | inherited | **AEM_Basic** |
| Min EV100 | −3.5 | **−10.0** | inherited | **−10.0** |
| Max EV100 | 1.0 | inherited | inherited | **1.0** |
| SpeedUp (f-stops/s) | 0.2 | inherited | inherited | **0.2** |
| SpeedDown (f-stops/s) | 2.0 | inherited | inherited | **2.0** |
| Bias (EV) | 0.5 | **0.0** | inherited | **0.0** |
| Bias curve | V1 | **V3** | inherited | **V3** |

Citations:
- `extracted/json/Art/Environment/Weather/BP_WeatherPreset_Base.json:2050-2102`
  (AEM_Basic, overrides, Min −3.5, Max 1.0, speeds 0.2/2.0, Bias 0.5, V1)
- `extracted/json/Art/Environment/Weather/BP_WeatherPreset_Base_Skybox.json:1367-1372`
  (Bias 0.0, V3, Min −10.0; inherits the rest)
- `extracted/json/Art/Environment/Weather/BP_WeatherPreset_Gloomy.json:326-337`
  (parent Base_Skybox; no AutoExposure override ⇒ shipped chain)
- `extracted/raw/TAT/Config/DefaultEngine.ini:527`
  (`r.DefaultFeature.AutoExposure.ExtendDefaultLuminanceRange=True` ⇒ EV100)
- `ExposureCompensation` has **0 hits**; the authored field is
  `AutoExposureBias` + `AutoExposureBiasCurve`.

**Trap:** do not cite Base's −3.5 / 0.5 / V1 as the Guildhall values. The
shipped Gloomy chain is Base_Skybox's −10.0 / 0.0 / V3.

Other presets: HeavyRain bias −0.5, MissionLobby −0.5, ThievesDen +0.5;
Example presets use the Base (V1) chain. `AutoExposureMethod` has 1 hit;
Min/Max 3/3; speeds 2/2; Bias 5; curves 2.

## 2. The authored EV curve

`Curve_Exposure_Compensation_Float_V3.json:15-93` (same keys in
`game/data/generated/curves.json:1628-1730` and
`game/data/generated/tables/Art/Environment/Weather/Curve_Exposure_Compensation_Float_V3.json:19-97`),
8 keys, linear:

| X: average scene EV100 | Y: EV compensation |
|---:|---:|
| −12.1 | −0.5 |
| −11.1 | −1.5 |
| −10.1 | −2.0 |
| −9.1 | −2.25 |
| −8.1 | −2.5 |
| −6.1 | −3.0 |
| −3.0 | −4.0 |
| +0.2 | −4.0 |

V1 (`Curve_Exposure_Compensation_Float.json:15-82`) is the Base/Example curve
(+2.0 EV at −13, 0 at ≥−9) and is **not** the Guildhall curve. The Y is EV
(additive with Bias), not a linear multiplier.

The port has a hand transcription and a diagnostic reader only:
`weather_profile.gd:133-137` (`EV_CURVE_POINTS`), `:488-500`
(`ev_curve_bias`), `:1007-1008` (printed "recorded, not applied"). The
production path uses only `auto_exposure_bias` (`:796-800`) and the
`NIGHT_EXPOSURE` floor (`:990-1000`). `tools/parse_weather.py:397-413` emits
only `auto_exposure_bias`; `game/data/generated/weather/gloomy.json:90-107`
has no AEM method/min/max/speeds/curve. P1's "BLOCKED-ON weather/sky" is more
precisely **BLOCKED-ON T01 producer + consumer** (T07-render.md:385 says the
same).

Stale comments in `weather_profile.gd` (not edited: byte-identity is the B1
control): `:122-126` says the curve pulls down "as the scene darkens" — the
keys pull down as the scene **brightens**; `:129-132` says it is "consumed ...
for the exposure decision only" (diagnostic only) and "Godot has no auto
exposure at all" (false: Godot 4.7 exposes it on `CameraAttributes`).

## 3. Cameras and placed volumes

- **0 placed `PostProcessVolume` in the loaded Guildhall set** (15 sublevels,
  `mission_controller.gd:1069-1086`); all 34 generated Guildhall levels
  (including contracts) have `post_process: []`. The port's loader would
  consume them at `level_loader.gd:3515`; there is nothing to consume.
- The whole extract has exactly 2 placed PP volumes: the main-menu startscreen
  and ThievesDenTest_P; neither is Guildhall.
- No Guildhall/prep/player camera authors `PostProcessSettings` or exposure.
  The Guildhall `CameraActor_0` is an orthographic map camera
  (`Guildhall_P.json:8056-8099`); the player camera is
  `BP_Player_Base.json:9826-9847`; the prep camera is
  `MissionLobby_Geo3.json:2491-2535`. The only serialized camera PP settings
  are the MainMenu and OldManor cine cameras, and neither touches exposure
  (`MainMenu.json:398-402`, `OldManor_Geo.json:253923-253944`).
- The Guildhall weather selection is an inference: `Guildhall_P.json` has a
  `TATWeatherManager_1` with no `PresetOverrides`;
  `game/data/generated/weather/map_weather.json:15-27` records
  `manager_overrides: {}` and the port infers `gloomy` from level dressing.
  `DT_WeatherTypes.json:239-249` maps `Weather.Type.Gloomy` → Gloomy.

## 4. What the authored pipeline implies

The foyer and gate do **not** get different authored constants. The same
AEM_Basic settings apply to the whole view; the difference comes from the
view's measured luminance and the V3 curve. The exact converged EV100 for the
two poses is **UNKNOWN** (no UE eye-adaptation readout in the dump). The
authored clamp is −10…+1 EV100, bias 0, curve −0.5 EV at the dark end to
−4.0 EV at the bright end; speeds 0.2/2.0 f-stops/s. At 0.2 f-stops/s a 4 EV
transition into the bright foyer is ~20 s (linear phase; UE then blends
exponentially within ~1.5 f-stops). The port's 0.49 is a linear **−1.03 EV**,
not the authored V3 −4.0 EV.

## 5. Godot 4.7 truth

- `Environment` has **no** `auto_exposure_*` property; auto-exposure is on
  `CameraAttributes`: `auto_exposure_enabled` (false), `auto_exposure_scale`
  (0.4), `auto_exposure_speed` (0.5), `exposure_multiplier` (1.0),
  `exposure_sensitivity` (100). `CameraAttributesPractical` adds ISO
  min/max sensitivity (0/800). Sources: Godot 4.7 `doc/classes/CameraAttributes.xml`
  and `CameraAttributesPractical.xml`; local 4.8-dev checkout
  `doc/classes/*.xml`.
- Godot's auto-exposure averages the **max RGB channel** per frame
  (`luminance_reduce.glsl`) and adapts with a per-frame linear blend factor
  (`renderer_scene_render_rd.cpp:567-570`), not UE's log-luminance AEM_Basic
  and f-stops/s. It has no EV100 clamp, no V3 curve, no meter mask. It is a
  coarse analogue, Forward+ only. Enabling it would make the gate's fixed
  AGX 1.15 calibration scene-dependent (very likely brighter; **not measured**
  and not claimed) and would pump with rain/practicals/flashes.

## 6. Verdict / label

**PARTIAL.** The authored data exists in the extract and the V3 curve is
transcribed, but the production generated table drops it and no production
consumer applies it. There is no authored room/volume split, so the port's
0.49 camera multiplier is an **invented spatial approximation** of the
authored temporal AEM_Basic — not authored data. The p2 report labels it as
such and cites the block above.
