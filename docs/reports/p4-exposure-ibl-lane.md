# P4.1 exposure + IBL lane (2026-11-27)

**Status:** headless/codeable part **done and green**; the cubemap extractor is
**built and run against the real assets** (3 cubes / 18 faces); no GPU run, no
capture, no visual score. Worktree branch `p4-exposure` based on `a1c3597` (the
Phase 0b main tip). The integrator owns `make normalize`, the audit re-stamp and
the GPU calibration; the lane commit hash is reported in the handback, not here.

## What this lane ships

### 1. Authored auto-exposure data (`tools/parse_weather.py`)

The merged Base → Base_Skybox → Gloomy chain now reaches generated data in
`postprocess`:

| field | shipped Gloomy value | source |
|---|---|---|
| `auto_exposure_method` | `AEM_Basic` | `BP_WeatherPreset_Base` CDO |
| `min_brightness` | `-10.0` | `Base_Skybox` override (Base is `-3.5`) |
| `max_brightness` | `1.0` | Base, inherited |
| `speed_up` | `0.2` f-stops/s | Base, inherited |
| `speed_down` | `2.0` f-stops/s | Base, inherited |
| `auto_exposure_bias` | `0.0` | `Base_Skybox` override (Base is `0.5`) |
| `bias_curve` | `Curve_Exposure_Compensation_Float_V3` | `Base_Skybox` override (Base is V1) |

Producer dry-run (into `/tmp`, not the shared generated tree) prints exactly
those values for `gloomy`, `midnight_clear` and `dense_fog_old_manor`;
`base` still reads `-3.5 / 0.5 / Curve_Exposure_Compensation_Float` and
`base_skybox` reads `-10.0 / 0.0 / …V3`, which is the documented inheritance.

### 2. Pure model (`game/src/core/auto_exposure.gd`)

- `configure(preset)`, `step(dt, ev100)`, `reset(scene_ev100)`, `state()`;
  authored clamp/speeds/bias read from the preset, V3 via
  `GameData.eval_standalone_curve` with the transcribed 8-key table as the
  fallback.
- UE AEM_Basic semantics: `target = clamp(scene + bias + curve(scene), -10, +1)`;
  `delta = target - adapted`; a RISING target (dark -> bright) uses `speed_up`
  (0.2) and a FALLING target (bright -> dark) uses `speed_down` (2.0).
  `+4 EV100` takes 20 s at 0.2; `-4 EV100` takes 2 s at 2.0. The probe measures
  both settle times (20.00 s / 2.00 s) and asserts the rising ramp is strictly
  slower (`t_up > 5 * t_down`), which fails under an inverted mapping.
- ONE global calibration: `AEM_CALIBRATION = 0.008984375 = 1.15 * 2^-7`, i.e.
  the authored night anchor (scene `-3.0`, V3 `-4.0`, adapted `-7.0`) resolves
  to today's measured `NIGHT_EXPOSURE` 1.15 exactly. The GPU calibration run
  may re-pin this single constant; there is no per-room grade.
- `weather_profile.gd` delegates `ev_curve_bias()` to the model (the
  hard-coded `EV_CURVE_POINTS` table was removed from `weather_profile.gd`;
  it lives once in `auto_exposure.gd`).
- `TAT2_AEM=fixed` (default) is byte-for-byte today's path (1.15 for the
  shipped night). `model` replaces the night constant with the authored model
  at the documented anchor (same 1.15) and logs one `TAT-2 AEM:` line; a
  non-night preset keeps the fixed value because there is no measured scene
  EV100 without the meter. `meter` seeds the same anchor and attaches the live
  controller in `mission_controller._setup_environment()`.

### 3. IBL producer + consumer

- `tools/tat-extract/Exporter.cs` `cubemaps` command: decodes the authored
  `UTextureCube`s with the pinned API (`TextureDecoder.Decode(cube,
  opts.TexturePlatform)`; the 1.2.2.202611 `CTexture` has no `Crop`, so the
  command slices the six stacked faces itself by raw decoded rows), writes
  `OUT/assets/TAT/Content/Cubemaps/<id>/face_{px,nx,py,ny,pz,nz}.png` plus a
  `cubemap.json` sidecar (size, pixel format, SRGB, transfer, UE face order,
  a strided 8-bit face mean as an orientation gauge).
  Packages: `/Game/MaterialLibrary/Utility/Cubemap_GroundFloor_01`,
  `/Game/ThirdParty/FluidNinjaLive/UseCases/007_SmallWater/T_FakeSpecular1`,
  `/Engine/MapTemplates/daylight` (all confirmed in `extracted/filelist.txt`).
- `tools/parse_cubemap.py` → `game/data/generated/ibl/cubemaps.json`
  (`schema tat2.cubemaps/1`, explicit face order, `res://assets/ue/Content/...`
  face paths, `by_ue_path`). A clean tree without the extract pass writes an
  empty index (today's look); a missing face file fails the producer.
- `game/src/core/cubemap_loader.gd`: `TAT2_IBL=off|ambient` (default off),
  six explicit faces, exact per-cell solid-angle cosine irradiance (uniform
  cube returns exactly its radiance), ambient normal = world up, **no authored
  rotation**, and ambient energy is the raw irradiance luminance — **no
  `AMBIENT_ENERGY_MAX` clamp**. `weather_profile.apply_environment()` applies
  colour + energy only in `ambient` mode.

### 4. Meter (code + synthetic harness; GPU run is the integrator's)

- `game/src/core/auto_exposure_meter.gd` + `auto_exposure_meter.glsl`:
  `CompositorEffect` at POST_TRANSPARENT, one workgroup per 32×32 tile, 8×8
  threads, per-tile average of `log2(luminance*100)`, float storage buffer,
  `buffer_get_data_async` readback (never a blocking read). `TAT2_AEM=meter`
  drives `AutoExposure.step(dt, measured_ev100)` and
  `Environment.tonemap_exposure`.
- Headless: `RenderingServer.get_rendering_device()` is null, so the meter
  stays pending and the exposure keeps the calibration-identical anchor. The
  shader's SPIR-V is compiled at import time and the probe checks it
  (4,636 bytes, no compile error); the dispatch is not executed here.
- `AutoExposureMeter.reduce_log_luminance()` is the deterministic CPU mirror
  the synthetic harness asserts (uniform grey, +1 EV per luminance doubling,
  black EPS floor, group grid, brute-force gradient, determinism).

## Measured evidence (this worktree, no GPU)

| Gate | Result |
|---|---|
| `tools/check_scripts_compile.gd` | `scripts checked: 223, broken: 0` (was 217; +4 core, +2 probes) |
| `make test` | exit 0, `SUMMARY: fails=0`, 326 `PASS:` lines |
| suite 123 (`probe_auto_exposure.gd`) | `AEM_PROBE: fails=0 passed=70` (corrected SpeedUp/SpeedDown) |
| suite 124 (`probe_cubemap.gd`) | `CUBEMAP_PROBE: fails=0 passed=25` |
| meter GLSL | `RDShaderFile` loads, `compile_error_compute=''`, 4,636 SPIR-V bytes |
| `make build-extractor` | `Build succeeded. 15 Warning(s) 0 Error(s)` (14 NuGet advisory + 1 pre-existing `Program.cs:91 CS8603`) |
| `tat-extract cubemaps` (real run) | exit 0: `[cubemaps] ok=3 skip=0 fail=0`, `errors.log` 0 entries |
| `make gate-ratchet` | PASS (committed logs/floors untouched by this lane) |
| `probe_render_t07.gd` | `T07_SUMMARY: fails=0` (Guildhall exposure 1.150 / ambient 0.160 unchanged) |
| `build/qa/runtime_smoke.sh 90` | PASS, exit 124, errors=0, `mission_ready=1` for default/fixed, `TAT2_AEM=model TAT2_IBL=ambient`, and `TAT2_AEM=meter` (meter pending headless) |
| `make audit` | **expected red until regeneration** (see below) |

### Measured extractor build + real cubemap run

```
Build succeeded.
    15 Warning(s)
    0 Error(s)
Time Elapsed 00:00:01.65
cp tools/tat-extract/native/linux-x64/CUE4Parse-Natives.so tools/tat-extract/bin/Release/net10.0/
```

```
$ tat-extract cubemaps --usmap .../TAT-5.5.4-...usmap
mounted 22005 files
== cubemaps
  cubemap daylight: 256x256 PF_FloatRGBA srgb=False -> extracted/assets/TAT/Content/Cubemaps/daylight
  cubemap Cubemap_GroundFloor_01: 512x512 PF_FloatRGBA srgb=False -> extracted/assets/TAT/Content/Cubemaps/cubemap_ground_floor_01
  cubemap T_FakeSpecular1: 128x128 PF_FloatRGBA srgb=False -> extracted/assets/TAT/Content/Cubemaps/t_fake_specular1
[cubemaps] ok=3 skip=0 fail=0
[cubemaps-filtered] ok=0 skip=12559 fail=0
errors -> extracted/errors.log (0 entries, this run only)
```

Six named PNGs per cube are on disk (18 faces); `tools/parse_cubemap.py`
validates them into `tat2.cubemaps/1` in a /tmp run (3 converged, 0 rejected,
`by_ue_path` for all three). The faces live in the shared
`extracted/assets/TAT/Content/Cubemaps/` (they are extraction output; the
generated JSON is still the integrator's `make normalize`).

Real 8-bit face means (linear transfer) and the orientation observation:

| cube | bright faces | note |
|---|---|---|
| `cubemap_ground_floor_01` (Gloomy SkyLight) | all ~0.00006–0.00085 | authored cube is very dark; naive irradiance ambient is ~0.0001, not today's 0.16 — the A/B decides |
| `daylight` (DenseFog Old Manor) | px/nx/py/ny/pz 0.065–0.075 | `nz` is uniformly black under the UE ECubeFace order |
| `t_fake_specular1` (Base/Examples) | `pz` only ~0.0039 | five black faces, one highlight face |



`make audit` remaining failures in this worktree:

```
FAIL stale generated group materials: oldest output predates newest source  (new Cubemaps faces under extracted/assets; cleared by make normalize)
FAIL baseline: producer tools/parse_weather.py changed since the baseline
FAIL producer tools/parse_cubemap.py: output gen:ibl is missing
FAIL baseline: no entry for producer tools/parse_cubemap.py
FAIL baseline: infrastructure root:Makefile changed
FAIL baseline: infrastructure root:tools/tat-extract/Exporter.cs changed
FAIL baseline: infrastructure root:tools/tat-extract/Program.cs changed
FAIL tool version drift: vgmstream ... -> missing   (worktree-only: the untracked tools/bin/vgmstream lives in the main checkout; not this lane)
```

## What the integrator must do

1. The extractor is **already built and run** in this lane; the three cubes and
   their 18 faces are in the shared `extracted/assets/TAT/Content/Cubemaps/`.
   Re-run `$(EX) cubemaps` only if the private extract changes.
2. `make normalize` — regenerates `game/data/generated/weather/*.json` (new
   AEM fields) and creates `game/data/generated/ibl/cubemaps.json`.
3. `tools/godot --headless --path game --import` — imports the six face PNGs
   and the new `auto_exposure_meter.glsl`.
4. `make audit-refresh-stamps REASON='P4.1 AEM producer fields + cubemap producer; regenerated after make normalize'`,
   then `make audit` (expect exit 0).
5. Re-run suites 123/124: the generated-data block stops printing
   `PENDING` and asserts `-10/+1, 0.2/2.0, 0, V3`; the cubemap block asserts
   the index schema, six faces and the `by_ue_path` mapping.
6. Raise the ratchet floors after committing the gate logs: compile
   `217 → 223`, `run_tests` `324 → 326`.

## GPU probes / calibration to run (integrator)

All are Vulkan/Xvfb runs at one Godot at a time; none were run here.

1. **IBL A/B**: same commit, same pose (KF16 gate, KF17 upper foyer, KF18),
   `TAT2_IBL=off` vs `ambient`. Compare the `TAT-2 IBL ambient:` line, the
   environment `ambient_color/energy`, and the ROI stats. `off` must reproduce
   today byte-for-byte. Check the **face orientation**: `CUBEMAP_ORIENT:` should
   read `+Y >= -Y`; a wrong slice order would light the scene from below.
2. **Model no-op**: `TAT2_AEM=model` at the same poses. The `TAT-2 AEM:` line
   must read `exposure=1.1500` on gloomy and the frame must match `fixed`
   within capture noise (the authored anchor is a no-op by construction).
3. **Meter calibration** (the only new visual path): `TAT2_AEM=meter` at six
   poses (gate, foyer, lounge, ward, street, safe room), ≥25 s settle each.
   Record the `TAT-2 AEM meter:` lines (measured EV100, adapted EV100,
   exposure) and the residuals vs the reference. If the gate-pose residual is
   non-zero, re-pin the ONE constant `AEM_CALIBRATION` and re-run this probe,
   then re-run `probe_auto_exposure.gd` (its anchor identity uses the same
   constant). Do not add per-room grades.
4. Optional stage 2 (not in this lane): sky radiance/dome A/B, after the
   stage-1 ambient numbers are recorded.

## Risks / conflicts

- **Extractor API is now the measured one.** `make build-extractor` is green
  against CUE4Parse/CUE4Parse-Conversion 1.2.2.202611 (15 warnings, 0 errors;
  14 NuGet advisories + the pre-existing `Program.cs:91` nullable warning). The
  pinned `CTexture` has no `Crop`, so faces are sliced from the raw decoded
  bytes; `TextureDecoder.Decode(cube, opts.TexturePlatform)` is the real
  overload. The real run decoded 3/3 cubes and wrote 18 faces, so the
  six-stacked-face assumption is now measured, not inferred.
- **Face order is UE `ECubeFace`** (PosX, NegX, PosY, NegY, PosZ, NegZ). The
  extractor names the files, so the runtime never guesses; the orientation
  gauge + GPU A/B are the verification. Real data already shows two things the
  A/B must resolve: `daylight` has a uniformly black `nz` face under this
  order, and `cubemap_ground_floor_01` is near-black on every face (the
  authored SkyLight cube is not a bright sky dome, so raw irradiance ambient
  would be ~0.0001 vs today's 0.16). CUE4Parse's
  `CubemapConverter.ToPanorama` uses a different face order and is deliberately
  not used.
- **Generated-data baseline**: the weather files change shape (new fields), so
  `make audit` is red until step 4. `TAT2_AEM=fixed` means no visual delta.
- **Shared files**: `weather_profile.gd` and `mission_controller.gd` are edited
  (AEM/IBL hooks). Only the fixed/default paths have gate evidence; the
  `model`/`meter` paths are opt-in and unmeasured. Expect trivial merge
  conflicts if a loot/economy lane also touches `mission_controller.gd` near
  `_setup_environment`.
- **`parse_cubemap` is now in `manifest_audit.PRODUCERS`** and `NORMALIZERS`;
  the baseline stamp is the integrator's.
- **`AEM_CALIBRATION` is a port calibration, not authored data**: pinned to
  reproduce 1.15 at the authored anchor; the GPU run owns the final pin.
- The meter is a **mean of per-tile averages** (partial edge tiles carry one
  tile's weight); the residual is ≤ 6 % of a 1080p frame and constant per
  resolution, absorbed by the one calibration. Documented in the meter header.
- `load("res://src/core/auto_exposure_meter.glsl")` requires the normal import
  step (the probe prints `PENDING` if the cache lacks it).

## Non-claims

No Vulkan/Xvfb/Steam run, no capture, no visual/exposure score, no claim that
the real `Cubemap_GroundFloor_01` faces are correct until the GPU A/B and the
orientation gauge are read. `TAT2_AEM=model|meter` and `TAT2_IBL=ambient` are
opt-in and unmeasured; the default `fixed`/`off` paths are unchanged.
