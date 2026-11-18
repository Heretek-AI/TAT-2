# Guildhall light intensity, range & attenuation fidelity (2026-11-17)

Guildhall lighting did not use the authored UE values. `game/src/core/level_loader.gd` forced every authored light `Intensity` through a two-branch heuristic (`raw * 0.95` below 20, otherwise `raw * 0.08`, both clamped to `[1.0, 4.2]`), which pinned 468 of the 682 lights in `game/data/generated/levels/Guildhall/*.tatlevel.json` (68.6%) to a constant: 142 at `1.0` and 326 at `4.2`. The branch was also discontinuous at 20 (authored `19.9` -> `4.2`, authored `20.0` -> `1.6`). Range was invented on top of already-converted metres (`spot_range = clampf(radius * 2.5, 6, 26)`, `omni_range = clampf(radius * 2.2, 5, 20)`), turning the safe-room wall spot's authored `9.0 m` radius into `22.5 m`, and attenuation was hand-picked (`0.85` spot / `0.9` omni). The fix replaces both branches with one linear scale anchored at the authored median (`15.0` -> energy `1.0`), keeps authored radius 1:1, and uses Godot's default attenuation `1.0`.

## Root cause (R1 evidence)

### 1. Authored intensity was collapsed by a discontinuous two-branch clamp

`_build_light()` and `_build_rect_lights()` both used:

```gdscript
if raw < 20.0:
    light_energy = clampf(raw * 0.95, 1.0, 4.2)
else:
    light_energy = clampf(raw * 0.08, 1.0, 4.2)
```

Across the 682 lights in `game/data/generated/levels/Guildhall/*.tatlevel.json`:

- **468 of 682 (68.6%) were pinned to an endpoint**: `142` at the `1.0` floor and `326` at the `4.2` ceiling.
- **A further `159` lights authored `20–52.5` escaped clamping** through the `* 0.08` branch (`20.0` -> `1.6`; `52.5` -> `4.2`), so an "in band" count that includes them overstates how much of the authored ratio the old mapping preserved.
- **The mapping jumped at 20**: authored `19.9` -> `19.9 * 0.95 = 18.905` -> clamped `4.2`, while authored `20.0` -> `20.0 * 0.08 = 1.6`. A 0.1-unit change in authored intensity produced a 2.6-unit change in energy.
- **Authored intensity range**: min `0.01`, median `15`, p75 `20`, p90 `45`, p95 `300`, max `2500`.

Illustrative mapping (old vs new):

| Authored `Intensity` | Old `light_energy` | New `light_energy` |
|---:|---:|---:|
| `0.01` | `1.0` (floor) | `0.01` (floor) |
| `5.0` | `4.2` (ceiling) | `0.333` |
| `15.0` | `4.2` (ceiling) | `1.0` |
| `19.9` | `4.2` (ceiling) | `1.327` |
| `20.0` | `1.6` | `1.333` |
| `45.0` | `3.6` | `3.0` |
| `50.0` | `4.0` | `3.333` |
| `52.5` | `4.2` (ceiling) | `3.5` |
| `300.0` | `4.2` (ceiling) | `4.0` (ceiling) |
| `2500.0` | `4.2` (ceiling) | `4.0` (ceiling) |

### 2. Range was multiplied a second time after the extractor had already converted it

`tools/parse_tables.py` already converts UE `AttenuationRadius` from centimetres to metres. The loader then treated the result as if it were still in UE units:

```gdscript
spot_range = clampf(radius * 2.5, 6.0, 26.0)
omni_range = clampf(radius * 2.2, 5.0, 20.0)
```

- Authored radii span `0.35–30 m`.
- The Guildhall safe-room wall spot (`BP_WallLightB_C_5`) has an authored radius of `9.0 m` and was given a `22.5 m` spot range.
- The `26 m` clamp was clipping `24` legitimate lights authored in the `20–30 m` band.

### 3. Attenuation was hand-picked

`spot_attenuation = 0.85` and `omni_attenuation = 0.9` were arbitrary values, not derived from the authored UE falloff.

### 4. The 96-light budget ranking reused the same non-monotonic heuristic

`_light_score()` ranked lights with the unclamped two-branch value plus a flat type bonus:

```gdscript
var energy: float = raw * 0.95 if raw < 20.0 else raw * 0.08
if "Directional" in ltype:
    energy += 10.0
elif "Spot" in ltype:
    energy += 2.0
```

A light authored `15` scored `14.25 + 2.0 = 16.25` (spot), while a light authored `50` scored `4.0 + 2.0 = 6.0`, so the budget could rank the dimmer authored light above the brighter one.

## Fix (R2)

### 1. One linear intensity scale in both light builders

`game/src/core/level_loader.gd` now defines:

```gdscript
const LIGHT_INTENSITY_SCALE: float = 0.0666667 # 1/15: median authored intensity -> energy 1.0
const LIGHT_ENERGY_FLOOR: float = 0.01
const LIGHT_ENERGY_CEIL: float = 4.0
```

and both `_build_light()` and `_build_rect_lights()` use:

```gdscript
light_energy = clampf(raw * LIGHT_INTENSITY_SCALE, LIGHT_ENERGY_FLOOR, LIGHT_ENERGY_CEIL)
```

This is **an approximation, not a photometric conversion**. There is no faithful lumen/candela -> Godot `light_energy` conversion for these stylized authored values (the map spans `0.01–2500` with a median of `15`). The single linear scale preserves the authored **ratio** inside the band and compresses only at the extremes; the anchor is the median (`15.0` -> `1.0`).

### 2. Range kept 1:1 in authored metres

```gdscript
spot_range = clampf(maxf(radius, 1.0), 1.0, LIGHT_RANGE_CEIL)
omni_range = clampf(maxf(radius, 1.0), 1.0, LIGHT_RANGE_CEIL)
```

with `LIGHT_RANGE_CEIL = 200.0` as a defensive guard only. It is not a gameplay tuning knob: authored radii top out at `30 m`, so no legitimate Guildhall light reaches it. The safe-room wall spot now uses its authored `9.0 m` range.

### 3. Attenuation set to Godot's default `1.0`

`spot_attenuation` and `omni_attenuation` are now `1.0`. Godot's physically accurate inverse-square value is `2.0`, and the authored UE lights use inverse-squared falloff with lumen units, so `1.0` is an **art default**, not a physical match. Direction matters: raising `0.85` (spot) and `0.9` (omni) to `1.0` makes falloff **faster**, not slower.

### 4. Budget ranking uses the same energy mapping

`_light_score()` now uses the same clamped energy and expresses type bonuses relative to the ceiling:

```gdscript
var energy: float = clampf(raw * LIGHT_INTENSITY_SCALE, LIGHT_ENERGY_FLOOR, LIGHT_ENERGY_CEIL)
if "Directional" in ltype:
    energy += LIGHT_ENERGY_CEIL * 2.5
elif "Spot" in ltype:
    energy += LIGHT_ENERGY_CEIL * 0.5
```

The bonuses keep their previous weight (`Directional 10.0`, `Spot 2.0` against the old `~4.2` maximum), but the energy term is now monotonic in authored intensity.

## Verified counts & measurements

### Mapping distribution

| Set | New: in band | New: at `4.0` ceiling | New: at `0.01` floor | Old: pinned |
|---|---:|---:|---:|---:|
| `game/data/generated/levels/Guildhall/*.tatlevel.json` (`682` lights) | `486` | `62` | `134` | `468` (`142` at `1.0` + `326` at `4.2`) |
| `Guildhall/*` + `Buildings/Guildhall/*` (`982` lights before loader dedup) | `778` | `70` | `134` | — |

The old mapping pinned `468 / 682 = 68.6%`. The new mapping leaves `486 / 682` inside the band, with compression limited to the authored extremes at `0.01` or `4.0`.

### Budget effect

Of the `96` selected lights, `87` slots change between the old and new ranking.

| Selection | Old ranking | New ranking |
|---|---:|---:|
| Lights authored `15` | `50` | `0` |
| Lights authored `20–50` | `0` | `62` |

The old ranking filled half the budget with median-intensity lights because their unclamped score (`14.25`) dominated, while the new ranking selects the authored `20–50` band that the old score had pushed down.

## Runtime & visual QA (R5)

### Screenshots

All captures use the game viewport under isolated `Xvfb :99`, `debug_autostart_contract=4`, and `game/project.godot` restored from `HEAD` afterwards.

| Screenshot | Viewpoint | Same viewpoint as |
|---|---|---|
| `build/qa/lighting_after_safe.png` | Guildhall safe-room spawn; authored wall spotlight now energy `0.333` at range `9.0 m` | — |
| `build/qa/lighting_after_sky.png` | Balcony / overlook | `build/qa/sky_moon_after_sky_final.png` |
| `build/qa/lighting_after_moon.png` | Pitched-up moon view | `build/qa/sky_moon_after_moon_final.png` |

### Measured pixel luminance

ImageMagick Gray `0–255`, game viewport (`1280x720+160+140`), before -> after:

| Crop | Mean | Pixels `>= 96` |
|---|---:|---:|
| Safe room, whole viewport | `94.1` -> `84.4` (`−10%`) | `41.0%` -> `21.5%` |
| Safe room, wall-spotlight crop | `147.0` -> `142.9` | `77.4%` -> `70.6%` |
| Sky / balcony, whole viewport | `64.9` -> `63.3` | — |
| Sky / balcony, sky crop | `23.6` -> `23.9` (unchanged) | — |
| Moon view, wall crop | `88.5` -> `81.5` | `26.2%` -> `14.7%` |

The wall-spotlight crop is still clipping at the core (its mean barely moves), but the surrounding wash is tighter: the share of pixels `>= 96` drops from `77.4%` to `70.6%`. The sky crop is effectively unchanged (`23.6` -> `23.9`), which is consistent with a localized interior-light change rather than a global exposure shift.

### Run log

```text
TAT-2 Loaded guildhall: meshes=63210 lights=96
TAT-2 environment: bg=2 ambient_src=2 ambient_energy=1.0 ambient_color=(0.8745, 0.9137, 1.0, 1.0) sky=true fog=true fog_density=0.0006000000285
```

Zero `SCRIPT ERROR` lines in the capture logs.

## Consequences & follow-ups (not fixed in this wave)

### Overall spawned-set brightness and range drop

- Summed energy over the spawned set drops about `41%`: `392.0` -> `232.6`.
- Mean authored range drops about `57%`: `15.7` -> `6.8 m`.

The old mapping saturated median lights at `4.2`; the new values are dimmer but preserve the authored ordering. Any further exposure or ambient compensation is a separate art decision, not part of this change.

### Stealth detection is now mis-tuned

**Retuned 2026-11-18 (`277baba`) — the numbers below describe the pre-retune state; see "Stealth retune (2026-11-18)" at the end of this report.**

`game/src/stealth/light_probe.gd` was tuned against the old inflated energies. It contributes:

```gdscript
total += falloff * falloff * clampf(l.light_energy * 0.35, 0.15, 0.9)
```

and skips lights with `light_energy <= 0.01`. Under the old mapping, a light authored `15` saturated at `4.2`, so `4.2 * 0.35 = 1.47` clamped to `0.9`. Under the new mapping the same light is `1.0`, so it contributes `0.35` — roughly half the previous visibility weight. With `guard_ai.gd`'s `vis_mult = 0.35 + visibility * 1.15`, detection near those lights roughly halves. **This is a stealth-balance change that was not retuned in this wave.**

### Implicit threshold coupling

`LIGHT_ENERGY_FLOOR = 0.01` coincides with the light probe's skip threshold (`<= 0.01`) and `RECT_LIGHT_OFF_THRESHOLD = 0.01`. The three values are currently independent literals; changing one without the others would silently change which lights count as "off" for rendering versus stealth. Worth revisiting as a shared constant or an explicit policy.

## Stealth retune (2026-11-18)

Shipped as `277baba fix(stealth): retune light probe weights for linear light energies`. Scope is `game/src/stealth/light_probe.gd` and `game/tests/run_tests.gd` only; no level data, loader, guard AI, or mission changes.

### Root cause

The probe's old `energy * 0.35` weight was calibrated against the old saturated energies. Under the new linear scale (`LIGHT_INTENSITY_SCALE = 1/15`: median authored `Intensity 15` -> energy `1.0`, floor `0.01`, ceiling `4.0`) the authored median fell from `0.90` to `0.35` visibility weight, roughly halving detection. Pre-retune the median light contributed `0.35`; the pre-lighting-wave probe contributed `0.90` because median lights saturated at the old `4.2` energy ceiling.

### Fix

One call-site change in `game/src/stealth/light_probe.gd`. Local (omni/spot) lights now use:

```gdscript
const LIGHT_ENERGY_TO_VISIBILITY: float = 0.9
const LIGHT_VISIBILITY_MIN: float = 0.15
const LIGHT_VISIBILITY_MAX: float = 0.9

static func light_visibility_weight(energy: float) -> float:
    return clampf(energy * 0.9, 0.15, 0.9)
```

Directional lights keep their separate `clampf(energy * 0.25, 0.0, 0.35)` branch, and ambient stays `0.08`.

### Mapping (authored intensity -> energy -> probe weight)

| Authored Intensity | Old energy | Old weight | New energy | New weight |
|---:|---:|---:|---:|---:|
| 0.15 | 1.0 | 0.35 | 0.01 | 0.15 |
| 2.5 | 2.375 | 0.83 | 0.1667 | 0.15 |
| 5 | 4.2 | 0.90 | 0.3333 | 0.30 |
| 15 | 4.2 | 0.90 | 1.0 | 0.90 |
| 19.9 | 4.2 | 0.90 | 1.3267 | 0.90 |
| 20 | 1.6 | 0.56 | 1.3333 | 0.90 |
| 30 | 2.4 | 0.84 | 2.0 | 0.90 |
| 45 | 3.6 | 0.90 | 3.0 | 0.90 |
| 52.5 | 4.2 | 0.90 | 3.5 | 0.90 |
| 300 | 4.2 | 0.90 | 4.0 | 0.90 |
| 2500 | 4.2 | 0.90 | 4.0 | 0.90 |

This is a rebalance, not a revert: authored `2.5` goes `0.83 -> 0.15`, authored `5` goes `0.90 -> 0.30`, so sub-median lights intentionally sit below the old collapsed values; authored `>= 15` saturates at `0.90`. The old non-monotonic `19.9 (0.90)` / `20.0 (0.56)` branch jump is gone.

### Guard detection effect

`game/src/ai/guard_ai.gd` uses `vis_mult = clampf(0.35 + visibility * 1.15, 0.35, 1.5)`. At zero distance: under the authored median light `vis_mult` is restored from `0.845` (pre-retune) to `1.477` (pre-wave `1.477`); under an authored-5 light it is `0.787` (pre-wave `1.477`, pre-retune `0.615`).

### Den hand fills / HUD

Den hand fills (`mission_controller.gd` energies `0.25 / 0.30 / 0.35 / 0.65`) now weigh `0.225 / 0.27 / 0.315 / 0.585` instead of the old `0.15` floor (the `0.65` light was `0.2275`). The Den has `0` hostile guards (suite 7), so there is no AI detection impact; the HUD light meter reads brighter in the hub.

### Verification

Suites 36 (helper mapping) and 36b (`sample_visibility` integration: one energy-`1.0` omni at `2 m` with a `10 m` range far from level geometry samples `0.656 = 0.08 + 0.64*0.9`). `make test`: `36` suites, `SUMMARY: fails=0`, exit `0`, zero `FAIL:`/`SCRIPT ERROR`/`SHADER ERROR`; `make audit` `12,630 / 12,704 (99.4%)`. Exit-time `ObjectDB`/`RID ... leaked` warnings are pre-existing harness noise.

### Residual coupling (unchanged)

The probe skip threshold (`<= 0.01`) still equals `LIGHT_ENERGY_FLOOR` as an independent literal. The retune does not change that coupling.

## Caveats & reproduce

- The scale is an **art anchor** (median `15.0` -> `1.0`), not a physical conversion. Do not treat it as 1:1 photometry or compare it to UE lumen values directly.
- `docs/reports/lighting-overhang.md` documents the superseded mapping and now carries a note pointing here. Its `light_energy` and `spot_range` table entries are historical, not current.
- The `Directional` branch of `_build_light()` still hardcodes `light_energy = 0.45`. No generated map currently contains directional lights, so this is latent rather than active.
- The `982`-light figure is the merged directory set **before** loader deduplication; the loader's position-key dedup and the `96`-light budget mean the runtime scene contains fewer lights than that.

Reproduce:

```bash
python3 tools/parse_tables.py     # if level JSON is stale
make test                          # SUMMARY: fails=0
make audit                         # 99.4%
```

QA capture (temporary edits to `game/project.godot`, restored on exit):

```bash
bash build/qa/capture_lighting.sh safe   # Xvfb :99, debug_autostart_contract=4
bash build/qa/capture_lighting.sh sky    # balcony/overlook viewpoint
bash build/qa/capture_lighting.sh moon   # pitched-up moon viewpoint
bash build/qa/pixel_stats.sh             # ImageMagick Gray luminance table
```
