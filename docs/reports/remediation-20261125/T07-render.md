# T07 — RENDER (lighting / exposure / GI / sky / weather)

Team: T07-RENDER. Worktree `<worktree>/T07-render`, branch
`rem/T07-render`, base `38e7b03` (W7 merged). Nothing pushed, merged or rebased.
Every number below is from a run on this tree; anything that could not be
measured headlessly is marked **not verified** and carries the capture that
would settle it.

Files owned and touched:

| file | change |
|---|---|
| `game/src/core/level_loader.gd` | fair per-room light allocation (`plan_light_selection`, `light_room_cell`, `light_record_accepted/key`, protected-light list), allocation stats in `result`/`PERF_CENSUS` |
| `game/src/core/weather_profile.gd` | night-preset exposure anchor, authored EV curve, moon `LightSourceAngle`, authored fog height falloff, GI/AO lever, SkyLight-cubemap/IBL state, prep-stage grade hand-off |
| `game/src/core/weather_visuals.gd` | night-sky calibration scoped to the presets maps actually use (dead `_is_midnight_clear` mapped), authored volumetric-cloud visibility |
| `game/tests/probe_render_t07.gd` | **new** headless red/green probe (also the regression guard) |

Not touched: material binding, geometry/placement, VFX, `mission_controller.gd`,
`hud.gd`, `mission_prep_ui.gd`, `tools/**`, `mobile_profile.gd`, any shader.

---

## C1-01 — 84 % of the Guildhall's authored lights were never instantiated (light budget)

- **severity: P0**
- **S1 investigate.** `_select_lights(ordered, max_lights, map_hint)` in
  `game/src/core/level_loader.gd` took the *global* head of a list ranked by
  `_light_score()` (= authored lumens through the tanh mapping) and stopped at
  `max_lights` (`MobileProfile.DESKTOP_MAX_LIGHTS = 160`,
  `game/src/core/mobile_profile.gd:14`), after a 25 m spawn-promotion sort
  (`_prioritize_lights`) and a map-hinted force list. Selection was therefore by
  brightness, never by room.
- **S2 research (authored truth).** The Guildhall load set is
  `mission_controller._map_id_to_sublevels("guildhall")` = 15 sublevels
  (`game/src/missions/mission_controller.gd:913-930`) plus the contract sublevel.
  Their `lights[]` arrays sum to **976** authored records; the loader's own
  integer-metre dedupe (first record wins on `round(pos)` keys, across the whole
  load set) leaves **914**. Measured distribution of the 914: 135 lights below
  1.0 authored lm, 645 below 20.0, 137 above 25.0, 48 exactly 25.0. The old cut
  landed at rank 159 = energy 1.2689 = **authored 25.0 lm**, so it kept the map's
  bright fixtures and evicted every ordinary room lamp.
  (Correction to RE-D-02 and to the F1b adjudication: see
  [Doc corrections](#doc-corrections).)
- **S3 confirm (red).** `game/tests/probe_render_t07.gd` re-derives the list with
  the loader's own acceptance/dedupe rule and runs the pre-T07 rule
  (`_legacy_global_cut`, the old `_select_lights` quoted below) beside the new
  one. Pre-T07 output:

  ```
  == guildhall ==
  authored_records=914 (after acceptance+integer-position dedupe) instanced=159 (17.4 %) spawn_points=21
  rooms 16 m: authored=189 | fair covered=154 (81.5 %) | pre-T07 covered=95 (50.3 %)
  rooms 8 m: authored=511 | fair covered=155 (30.3 %) | pre-T07 covered=137 (26.8 %)
  kept: shadows=6 forced=7 | authored intensity p10/p50/p90=15.00/30.00/300.00 | kept radius>=6m=105
  ```

  The defect is in the **pre-T07 column**: 50.3 % of 16 m room bubbles had no
  light at all, and 77 % of those bubbles author a 6-12 m practical (measured in
  §Before/after). This is not a scarcity of lights: it is a ranking that spends
  the budget on 50-2500 lm fixtures wherever they are.

  The old function no longer exists on the tree, so the red measurement is
  **reproduced inside the probe**: `_legacy_global_cut()` is the pre-T07
  `_select_lights`, verified line for line against
  `git show 38e7b03:game/src/core/level_loader.gd` (`budget = min(size,
  max_lights)`, gate heroes pulled out, `head[:budget - forced]` kept, heroes
  appended shadowless). It shares today's protected-light list, which if anything
  *flatters* the old rule by one light (6 → 7 forced), so the comparison is
  conservative. Every probe run therefore regenerates the red number, and the
  assertions `fair > pre-T07` plus `coverage >= 75 %` are the regression guard.
  The probe also prints the kept-intensity distribution (`p10/p50/p90 =
  15.00/30.00/300.00`), so "an ordinary room lamp now gets a slot" is checkable
  without a frame: the old cut was *at* 25.0 authored lm.
- **S4 fix.** `plan_light_selection()` water-fills the budget per room bubble:
  1. gate/safe-room protected lights are force-included (shadowless) as before;
  2. every occupied `LIGHT_ROOM_CELL_M = 16 m` cell gets **its own** best authored
     light before any cell gets a second, cells served densest-first with a
     stable `(count, best-score, cell-key)` order inside a round;
  3. shadows go to the first `hero_shadows` selected lights in global preference
     order, so the 6-shadow contract is untouched.

  `_select_lights` is now a thin wrapper over it (one implementation), the rule is
  documented in the constant block, and every load where the cap bites prints one
  line: `TAT-2 light allocation: map=guildhall authored=914 kept=159 budget=159
  forced=7 rooms=154/189 cell_m=16.0`.
- **S5 test.** `probe_render_t07.gd` asserts authored=914, budget fully spent
  (159 + 1 rect = 160), 16 m coverage ≥ 75 %, fair > pre-T07 on both grids, the
  POI keeps ≥ 40 authored interior lamps, the six KF16 gate lights and the
  contract-2 safe-room wall spot survive, and 6 hero shadows. `make test`
  (which loads the Guildhall and pins the safe-room spot, the gate lights and
  `light_budget == 160`) passes — see §Gates.
- **S6 confirm (green).** Same probe, `T07_SUMMARY: fails=0`.
- **verdict: FIXED** (P0).

### Before / after (same tree, same authored list, same budget)

| metric | authored | pre-T07 (global cut) | T07 (per-room) |
|---|---:|---:|---:|
| lights instantiated | 914 | 159 (17.4 %) | **159 (17.4 %)** |
| 16 m room bubbles (all 189: 187 non-protected + 2 protected-only) | 189 | 95 covered (50.3 %) | **154 covered (81.5 %)** |
| 16 m non-protected bubbles (the loader's own `stats`) | 187 | — | **152 covered (81.3 %)** |
| 8 m room bubbles covered (≥1 light) | 511 | 137 (26.8 %) | **155 (30.3 %)** |
| POI building lights kept | 273 | 56 | 44 |
| POI 16 m bubbles containing ≥1 POI light | 64 | 19 | 21 |
| light nodes in the mission tree | — | 160 budgeted + 11 non-budgeted | **160 + 11 (unchanged)** |
| shadow casters | — | 6 hero (+1 moon) | **6 hero (+1 moon) (unchanged)** |

Runtime evidence (real `load_sublevels_async` of the 15-file load set, headless):

```
TAT-2 light allocation: map=guildhall authored=914 kept=159 budget=159 forced=7 rooms=152/187 cell_m=16.0
TAT-2 gate lights: total=160 (generic=159 rect=1) budget=159 forced=7 hero_shadows=6
PERF_CENSUS … lights=160 shadow_lights=6 … light_budget=160 hero_shadows=6
```

(`rooms=152/187` counts only the *non-protected* bubbles the budget allocates;
the probe's 154/189 adds the two bubbles whose only light is in the protected
list. The two tallies are the same selection.)

Coverage uses **N = 1** (`ROOM_MIN_LIGHTS` in the probe): a room bubble is
covered when at least one authored light from it is instantiated. N = 2 would
report 0 % for every bubble that has only one authored light, so the probe also
reports the kept-per-bubble distribution in its 8 m row.

**Candles — measured, and the claim is narrower than the brief assumed.** A
sub-1-lumen authored light is a sconce glow (0.01-0.9 lm, 0.35-1.5 m radius), and
the fair share keeps **0 of the 135** of them — exactly as the old rule did. A
bubble's one slot goes to its brightest fixture, and a 0.3 lm / 0.8 m light
contributes no room light, so spending a slot on it would take a room's practical
away. What survives is every room's *practical* (6-12 m reach). The candle
meshes and their flames are unaffected (emissive material + `VfxManager` candle
flame), only the `Light3D` node is skipped. If the capture shows unlit sconces,
the remedy is a separately capped candle tier (135 authored, ~96 slots, no
shadows, radius ≤ 2 m bounds the cluster cost) — proposed in the capture plan,
**not** landed: it is ~+96 light nodes on a build already at ~37 FPS and the perf
matrix is waived, so it needs a measurement first.

Per sublevel (`rooms` = 16 m bubbles that contain one of that sublevel's lights;
`lit` = those bubbles where at least one **of that sublevel's** lights survived;
a bubble shared with another sublevel can be lit by that neighbour, so this column
is a lower bound, not a room-darkness count):

| sublevel | authored | pre-T07 kept | T07 kept | rooms | pre-T07 lit | T07 lit |
|---|---:|---:|---:|---:|---:|---:|
| `Building_Guildhall_POI` | 179 | 37 | 21 | 64 | 19 | 21 |
| `Building_Guildhall_POI_3rdFloor` | 94 | 19 | 23 | 31 | 14 | **23** |
| `Guildhall_Gameplay` | 497 | 43 | **64** | 122 | 31 | **63** |
| `Guildhall_Vault_CeremonialChambers` | 25 | 7 | 2 | 7 | 5 | 6 (any light) |
| `Guildhall_PeripheryA` | 62 | 30 | 25 | 48 | 25 | 25 |
| `Guildhall_LightingNoGameplay` | 43 | 21 | 19 | 29 | 17 | 16 |
| `Guildhall_Geometry` | 7 | 2 | 4 | 4 | 2 | 4 |
| `Guildhall_SkyboxGeo` | 7 | 0 | 1 | 6 | 0 | 1 |

Reading: the mission **Gameplay** interiors (the recorded black rooms) double
their lit bubbles (31 → 63) and keep 50 % more lights (43 → 64); the POI shell
keeps fewer lights but lights **more** bubbles, i.e. the old rule was stacking up
to six lights in single POI cells. `PeripheryA` and `LightingNoGameplay` are flat
(one bubble each), `Geometry` gains two bubbles, `SkyboxGeo` gains its one. The
Vault's own count drops (7 → 2) but six of its seven bubbles are still lit because
its cells are shared with brighter POI lights — that sublevel is the one place the
trade is visible, and it is recorded in Open risks.

**Why the cap was not raised.** `docs/reports/w1p-structural-perf-prototype.md`
records the Guildhall at ~37 FPS at 1080p/high with 160 lights; the perf matrix is
waived this wave and no GPU timing was taken. Raising the node count would be an
unmeasured perf claim, so the fix spends the same 160 slots differently.

## C1-02 — the AGX night exposure lift was scoped to a preset no map resolves to

- **severity: P0**
- **S1.** `weather_profile.gd` applied `NIGHT_EXPOSURE = 1.15` only when
  `str(preset["preset"]) == "midnight_clear"` (`apply_environment`, tonemap
  block). `map_weather.json` maps `guildhall → gloomy` and the Den/lobby to
  `midnight_clear_*`, so the lift ran for **no** shipped map.
- **S2.** The constant's own comment says it was calibrated on the Guildhall gate
  (“the old ACES 1.0 path left the gate at p50 0.04-0.06 against the reference
  0.10-0.11”), and KF16/KF17/KF18 are Guildhall frames (`docs/FIDELITY_GAPS.md`,
  `docs/reports/w5c-weather-backdrop.md`). C5-01 adds the authored exposure chain:
  `AEM_Basic`, `AutoExposureBias 0.0`, `AutoExposureBiasCurve =
  Curve_Exposure_Compensation_Float_V3`, EV100 range −10.0…1.0,
  `r.DefaultFeature.AutoExposure.ExtendDefaultLuminanceRange=True`.
- **S3 (red).** Probe, pre-fix: `preset=gloomy … tonemap=AGX exposure=1.000`.
- **S4.** `is_night_preset()` (gloomy or `midnight_clear*`, or the authored
  weather tag) gates the AGX path and the 1.15 anchor, so the Guildhall takes the
  calibration that was measured on it. The authored EV curve is transcribed
  (`EV_CURVE_POINTS`, 8 keys, `ev_curve_bias()`) and **consumed for the exposure
  decision, not multiplied into `tonemap_exposure`**: UE's EV100 space is
  luminance-calibrated and Godot's exposure is a linear multiplier, so applying
  the curve's −4 EV literally would divide the frame by 16. That reasoning is in
  the code, the probe asserts the curve values, and the producer gap is filed
  (see BLOCKED-ON T01).
- **S5.** Probe asserts AGX + `tonemap_exposure >= NIGHT_EXPOSURE` for the
  Guildhall, AGX for the Den, and that `dense_fog_old_manor` is **not** re-graded.
- **S6.** `TAT-2 exposure: preset=gloomy mode=AGX exposure=1.150 authored_bias=0.0
  ev100_night=-3.0 authored_curve_bias=-4.00 (curve recorded, not applied)`,
  probe PASS.
- **verdict: FIXED** (the scoping bug). The authored **EV range/curve application**
  is **BLOCKED-ON T01** — see the contract below.

## C1-04 — the documented KF16/KF17/KF18 sky calibration was dead code

- **severity: P1**
- **S1.** `weather_visuals.gd:_is_midnight_clear()` was an exact string match on
  `"midnight_clear"`. Three blocks were gated on it: the star scale, the warm
  SkyAtmosphere veil (`haze_amount`), and `apply_sky`'s fog/background lift
  (`fog_sky_affect 0.80`, `background_energy_multiplier 2.0`,
  `fog_light_color (0.12,0.13,0.15) @ energy 1.0`).
- **S2.** No map resolves to that id (C1-04, confirmed from
  `game/data/generated/weather/map_weather.json`). The constants were calibrated
  on Guildhall frames, so the calibration was scoped away from its own subject.
- **S3 (red).** Probe pre-fix: `sky(gloomy) haze_amount=0.00`.
- **S4.** `_uses_night_sky_calibration(preset)` = authored night preset **and not**
  indoor (`WeatherProfile.is_indoor_preset`). The Den keeps its window-pane
  treatment; `midnight_clear_*` rows keep it too (the prep stage overrides
  `background_energy_multiplier` afterwards, so T05's stage is unchanged).
- **S5/S6.** Probe: `sky(gloomy) haze_amount=1.00 cloud_haze=0.540 … den
  haze_amount=0.00`, PASS on both.
- **verdict: FIXED** (mapped, not deleted).

## C1-03 / RE-D-12 / RE-D-14 — no GI, no IBL

- **severity: P1**
- **S1/S2.** The build is pure Lumen (`r.DynamicGlobalIlluminationMethod=1`,
  `r.Lumen.HardwareRayTracing=True`) with `r.AllowStaticLighting=False`, so there
  is **no bake to import**. The authored SkyLight is a *specified cubemap*
  (`SLS_SpecifiedCubemap`, `/Game/MaterialLibrary/Utility/Cubemap_GroundFloor_01`,
  intensity 2.0 on the gloomy chain), extracted as `sky.cubemap` in every
  generated preset and read by nobody (RE-D-14/-18/-21).
- **S3 (red).** `extracted/json/MaterialLibrary/Utility/Cubemap_GroundFloor_01.json`
  is a `TextureCube`, 512×512, `PF_FloatRGBA`, `TC_HDR`,
  `SizeOnDisk 12,582,912 B` (= 6 × 512² × 8 — six faces). The extractor writes
  only `.png`/`.glb`/`.json` (`find extracted/assets -name '*.exr' -o -name '*.hdr'
  -o -name '*.ktx*'` → nothing), so the authored cubemap **cannot be loaded**:
  `sky_ibl_state()` reports `available=false` and `sky_contribution` stays 0 with
  the documented reason (mixing the display-space sky shader into ambient would
  *reduce* it — that is why it was forced to 0 in the first place).
- **S4.** Landed:
  * `sky.cubemap` is resolved (`sky_cubemap_path`, `sky_cubemap_res_path`) and the
    environment flips `ambient_light_sky_contribution` to 1.0 **automatically**
    when the converted panorama exists at
    `res://assets/ue/Raw/MaterialLibrary/Utility/Cubemap_GroundFloor_01.exr`;
  * one loud line per session records the state:
    `TAT-2 IBL: skylight_cubemap=/Game/…/Cubemap_GroundFloor_01 converted=…exr
    available=false sky_contribution=0.0 gi=ssil ao=true`;
  * **GI stand-ins**: SSIL stays the desktop-high default (unchanged values);
    **SSAO added** at desktop high (`ssao_radius 1.5 / intensity 1.2 / power 1.5
    / detail 0.5 / horizon 0.06 / sharpness 0.98 / light_affect 0.0`) as an
    APPROXIMATE contact-shadow term; **SDFGI is an opt-in capture lever**
    (`TAT2_GI=sdfgi`, 3 cascades / 0.5 m cells / 200 m) because it re-voxelises
    the 63 k-instance map every frame and has not been measured on the 60 FPS
    desktop gate. `TAT2_GI=off` and `TAT2_AO=off` exist for A/B captures.
  * the authored `LumenDiffuseColorBoost 2.0` is documented as the SDFGI/SSIL
    energy target; the field is not in the generated JSON (T01 contract below).
- **S5/S6.** Probe asserts SSIL on, SDFGI off, and the cubemap path non-empty with
  `sky_contribution == 0` while `available == false`.
- **verdict: PARTIAL** — the consumer and the state contract are in place; the
  authored asset is **BLOCKED-ON T01**. SSIL/SSAO are approximations, Lumen is the
  authored truth, SDFGI is unmeasured (open risk).

## C1-06 / P1 — emissive white point (facets and candles blown to white)

- **severity: P1**
- **S1.** `EMISSIVE_ENERGY_CEIL 4.0`, `LARGE_LAMP 2.5`, `GLASS 3.0`
  (`game/src/core/level_loader.gd:265-268`) sit above `GLOW_HDR_THRESHOLD_NON_DEN
  1.6` (`weather_profile.gd`), with `glow_intensity 0.1267` and no white point.
- **S2.** Authored: `BloomIntensity 6.336 @ BloomThreshold 0.05` for every shipped
  preset — i.e. UE blooms *everything* softly, and the threshold is in a
  pre-exposed space, so the port's 1.6 is a calibration, not the authored value.
  `tonemap_agx_white` (Godot default 16.29) is the only white point Godot exposes
  and nothing authored maps onto it.
- **S3.** Not reproducible as a *code* defect without a pixel comparison: the
  blown surfaces could be emissive, white-albedo or bloom (C1-06's own falsifier).
- **S4.** **No constant changed.** Any value here is a look change I cannot
  verify (no Vulkan capture in this team), and the emissive ceilings live inside
  the material-binding function set that belongs to T08.
- **S5/S6.** none (no change).
- **verdict: DEFERRED (needs one capture)** — see the capture plan: A/B
  `glow_hdr_threshold ∈ {1.6, 2.8}` at the f_0176 pose with `TAT2_AO=off`, and
  hand the emissive-ceiling half to T08.

## RE-D-16 / -18 / -21 — the 13 dead weather fields

- **severity: P1**
- **S1.** `grep`-verified consumers for all 50 extracted preset fields; 13 had
  none (`weather_profile.gd` getters only).
- **S2.** Authored values per preset (generated JSON + C5-01):
  `gloomy` authors `fog.height_falloff 1.070813`, `moon_light.source_angle 25.0`,
  `sky.volumetric_cloud_visible true`, `sky.cubemap`, `postprocess.white_temp
  5820`, `vignette_intensity 0.5152`, `film_slope 0.9784`, `film_toe 0.372003`,
  `rain.ground_wetness 1.0`.
- **S3 (red).** Probe pre-fix: `fog_height_density=0.00000`,
  `moon_angle=0.0`, `den cloud_coverage=0.618`.
- **S4 — consumed (4 fields + the cubemap path resolved):**
  * `fog.height_falloff` → `Environment.fog_height_density` (outdoor presets only:
    a room has no height gradient), same 0.03 cm→m calibration as the density
    (`gloomy 1.070813 → 0.0321 /m`: ~55 % of the authored density at the y=18.5
    street floor, ~6 % at the y=87 tower top). APPROXIMATE: the fog base is
    assumed y=0; UE's exact height integral is not recovered.
  * `moon_light.source_angle` → `DirectionalLight3D.light_angular_distance`
    (1:1 degrees: gloomy 25°, midnight_clear 15°, Den 5°).
  * `sky.volumetric_cloud_visible` → `cloud_haze`/`cloud_coverage` forced to 0
    when authored false (the Den and midnight_clear were drawing FBM clouds).
  * `sky.cubemap` → resolved + IBL state (BLOCKED-ON T01 for the asset).
  **Recorded, deliberately not applied (reasons in code):**
  * `postprocess.white_temp 5820` — a white-balance *gain*, but the sign
    convention (assumed illuminant vs corrected white) decides whether the frame
    warms or cools; the repo has no frame to settle it and both readings are
    defensible. Needs one capture (two candidate gains are in the capture plan).
  * `postprocess.vignette_intensity 0.5152` — no `Environment` slot in Godot 4.7;
    needs a full-screen pass on a node this team does not own.
  * `postprocess.film_slope 0.9784` / `film_toe 0.372003` — parameters of UE's
    *filmic tonemapper*, not a display-space grade: applying `toe` in display
    space maps everything below 0.372 to black (verified by arithmetic) and Godot's
    AGX has no slope/toe slot (it has `tonemap_agx_white/contrast`).
  * `postprocess.gain` / `gain_highlights` / `gamma_highlights` — `gloomy` authors
    none of the three (`gain_midtones` and `gain_shadows` already drive
    `adjustment_brightness` and the shadow-toe LUT). Applying them for other
    presets would change the Old Manor / Jaspering look unmeasured.
  * `sky.local_volumetric_fog_density` (0.5-8.0) is on a different scale from the
    port's calibrated `volumetric_fog_density` (0.001-0.012); applying it literally
    makes the fog opaque. Not applied.
  * `rain.ground_wetness` — **BLOCKED-ON T09**: needs a `ground_wetness` uniform
    in `game/src/core/tat_landscape.gdshader`; the value is already exposed by
    `WeatherProfile.ground_wetness(preset)` (gloomy 1.0).
  * `rain.niagara_asset` — **BLOCKED-ON T12** (Niagara systems consumer).
- **S5/S6.** Probe asserts `fog_height_density=0.03212` for the Guildhall, 0.0 for
  the Den, `angular_distance 25.0 / 5.0`, `den cloud_coverage=0.00`, and the
  cubemap path non-empty; all PASS.
- **verdict: PARTIAL** — 5 of 13 consumed, 5 recorded with reasons (2 need a
  capture), 3 handed to other owners.

## RE-D-20 — the 17 hand-placed lights that bypass the budget

- **severity: P2**
- **S1.** 10 Guildhall fills + 7 Den fills are created in
  `mission_controller.gd` **after** the budget, so they occupy nodes 161-177.
  Five of the ten Guildhall ones are not registered with `light_probe`
  (`GuildhallOrnateGateFill`, `GuildhallRoadFillL/R`, `GuildhallCarHeadlightL/R`).
- **S2.** Nothing authored: they are port inventions, documented as such in code.
- **S3.** Not a renderer defect; the documented risk is asymmetric stealth.
- **S4.** **No change** — the owning file (`mission_controller.gd`) is outside this
  team's writable set. The counts and the five invisible-to-stealth nodes are
  listed here for the owner.
- **verdict: BLOCKED-ON owner (`mission_controller.gd` gravity: T10/integrator).**
  Recommendation: register the five with `light_probe` (or document the exemption
  in their own comments) and add them to the allocation report so the node count
  `160 + 11` is never a surprise.
  The ten Guildhall nodes and their stealth state:

  | node | position | energy | in `light_probe` |
  |---|---|---:|---|
  | `GuildhallGateLampFill` | (11.5, 23, 92) | 2.2 | yes |
  | `GuildhallFenceLampFill` | (10, 27, 46) | 3.5 | yes |
  | `GuildhallOrnateGateFill` | (80, 20, 18) | 1.5 | **no** |
  | `GuildhallRoadFillL/R` | (8.6/11.4, 21.2, 52) | 0.7 | **no** |
  | `GuildhallCarHeadlightL/R` | (17.8, 19.96, 65.8/67.0) | 4.5 | **no** |
  | `GuildhallFoyerFill_*` | (27, 31, −53/−64) | 1.6 / 1.3 | yes |
  | `GuildhallSafeRoomFill` | (127, 29, −5) | 1.1 | yes |

  (Den: 7 `den_hand_fills`, sum 2.00, 6 of 7 registered — the wisp light is not.)

## C1-09 — prep-stage grade (T05 hand-off)

- **severity: P2**
- **S1.** `mission_prep_ui.gd` hard-codes `STAGE_EXPOSURE 2.6` (ACES),
  `STAGE_AMBIENT_ENERGY 1.8`, `STAGE_GLOW_INTENSITY 1.0`, `STAGE_SKY_ENERGY 0.18`
  against gameplay's AGX / 1.15 / 0.16 / 0.1267.
- **S2/S3.** C1-09: 2.6× exposure and 11× ambient gap. Authored gameplay values
  are the ones this team now applies.
- **S4.** No edit to `mission_prep_ui.gd` (out of scope). `WeatherProfile.
  stage_grade_values(preset)` returns the gameplay numbers for the stage
  (`tonemap_mode AGX`, `tonemap_exposure 1.15`, `ambient_light_energy 0.16`,
  `glow_intensity 0.12672`, `background_energy_multiplier 1.0`) so T05 can replace
  its four constants with one call and keep one grade across the product.
- **S5/S6.** Probe asserts the hand-off values; PASS.
- **verdict: DEFERRED → T05** (call `stage_grade_values`, drop the four constants).

---

## Team summary

| finding | severity | verdict |
|---|---|---|
| C1-01 light budget | P0 | **FIXED** |
| C1-02 exposure scoping | P0 | **FIXED** (curve application BLOCKED-ON T01) |
| C1-04 dead `_is_midnight_clear` | P1 | **FIXED** (mapped) |
| C1-03 / RE-D-12 / -14 GI + IBL | P1 | **PARTIAL** (asset BLOCKED-ON T01; SDFGI unmeasured) |
| C1-06 emissive white point | P1 | **DEFERRED** (needs 1 capture; T08 owns the ceilings) |
| RE-D-16/-18/-21 dead weather fields | P1 | **PARTIAL** (5 consumed, 5 recorded, 3 handed off) |
| RE-D-20 bypass lights | P2 | **BLOCKED-ON owner** |
| C1-09 prep grade | P2 | **DEFERRED → T05** (API provided) |

Counts: 3 FIXED, 2 PARTIAL, 2 DEFERRED, 1 BLOCKED-ON.

## Gates (this tree, serial)

| gate | result |
|---|---|
| `tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"` | `scripts checked: 121, broken: 0` (120 before the new probe) |
| `make test` | `SUMMARY: fails=0` (exit 0; log `t07-make-test-final.log`) |
| `tools/godot --headless --path game --script res://tests/probe_render_t07.gd` | `T07_SUMMARY: fails=0` (exit 0; log `t07-probe.log`) |
| `tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=1` | `SUMMARY: fails=0 passed=117 total=117` (exit 0; log `t07-e2e-tier1.log`) |
| `git status --short` | only the three owned sources + the new probe (data trees are symlinked/ignored) |

Run order on the committed tree: compile → `make test` → probe → E2E tier 1 (all
serial, no Vulkan, one Godot at a time from this team).

Commits on `rem/T07-render` (not pushed, not merged):

```
6fcfaa7 fix(render): fair per-room light allocation replaces the global 160-light cut
563f991 fix(render): authored exposure, IBL state and weather consumers for night presets
```

Regression evidence from `make test` (the two suites that touch this work):

```
PASS: Guildhall map preset wins over stale default map (preset=gloomy fog_density=0.00480000022799)
PASS: Guildhall terrain, floor collision & spawn ground raycast verified (… safe_aim=(-0.09778, 0.0, -0.995208), safe_angle=88.0, light=OmniLight3D pos=(127.0, 29.0, -5.0) energy=1.10)
TAT-2 exposure: preset=gloomy mode=AGX exposure=1.150 authored_bias=0.0 ev100_night=-3.0 authored_curve_bias=-4.00 (curve recorded, not applied)
PASS: 83 review baker (tagger + thieves_den bake, exit=0, 7291 ms)
```

One earlier `make test` run (`t07-make-test.log`) failed twice, both explained and
closed: the safe-room wall spot was evicted by the first version of the fair
share (fixed by adding it to the protected list — that failure was the reason the
list exists), and the review baker hit a `user://` write race with another team's
concurrent `run_tests.gd` (it passes alone and in the final serial run).

## Doc corrections

1. **RE-D-02 / F1b adjudication — the authored Guildhall light count.** Replace
   “976 light records, 915 after the loader's integer-position dedupe … the
   undeduped sum is 999” with:
   > The Guildhall load set (15 sublevels) authors **976** light records and the
   > loader's integer-position dedupe (first record wins on `round(pos)` metre
   > keys, in load order) leaves **914**, not 915. The whole `Guildhall*` +
   > `Buildings/Guildhall/*` family is 982 records; adding the 17 RectLight
   > components gives 999, which is where the adjudication's number comes from —
   > but the two `Facade_*` sublevels (6 records) are not in the load set, so
   > 999 is not the authored count of the map. Rule: `light_record_accepted()`
   > then `light_record_key()` (`level_loader.gd`).
2. **RE-D-02 severity/reporting.** “160 of 915 (82.6 %)” → “160 of 914 (82.5 %)”,
   and add: the *selection rule* was a global authored-energy cut at rank 159
   (**25.0 authored lm**), not a room budget.
3. **`docs/reports/lighting-intensity.md`** (“96-light budget, 982 lights before
   loader dedup”): 982 is every Guildhall-family level file including the two
   Facade sublevels; the load set is 976 and the budget has been 160 since W1p.
4. **AGENTS.md / `FIDELITY_GAPS.md` “forced=6”**: the protected-light list is now
   **7** on the Guildhall (six KF16 gate lights + the contract-2 safe-room 88°
   wall spot at `(126.2758, 27.1426, -2.4736)`). The new log line is
   `TAT-2 light allocation: … forced=7 rooms=154/189`.
5. **AGENTS.md “160-light budget”** stays true as a *cap*; add that it is spent
   per 16 m room bubble (`plan_light_selection`) and that node/shadow counts are
   unchanged by that change.
6. **`FIDELITY_GAPS.md`** KF16 row (“the remaining authored gate spots are still
   dropped by the position-only light dedupe and the 160-light budget”): the six
   KF16 lights are force-included; what remains dropped are *other* gate spots
   that now lose their room bubble to a brighter neighbour.
7. **`FIDELITY_GAPS.md` KF17/KF18 sky rows**: those measurements were taken with
   the preset pinned to the bare id `midnight_clear`, which no map resolves to.
   Since this wave the calibration applies to `gloomy` as well, so the rows should
   say which preset each number came from.
8. **`docs/FIDELITY_GAPS.md:45`** “authored intensity maps linearly (`1/15`)” is
   stale (RE-D-05 already flagged it): the code is the tanh curve anchored at 15
   lm → 1.0 energy with a 3.5 shoulder.
9. **`weather_profile.gd` header mapping block** claimed “BloomIntensity × 0.08”
   while the constant has been 0.02 — fixed in this wave (the header now states
   0.02 and lists the new authored consumers).

## Open risks

1. **The light allocation changes which lights exist, not how many.** Node and
   shadow counts are byte-identical (160 + 11, 6 hero + moon), but a room that
   used to have six lights may now have one, and 59 previously dark bubbles now
   have one. **This is a gameplay-visible change**: `light_probe` registers every
   spawned light, so stealth exposure changes with it. First capture must include
   a stealth readout, and T10 should re-check the light-detection balance.
2. **PeripheryA loses 5 lights (30 → 25)** while keeping the same bubble count
   (25). The street dressing is dimmer in exchange for lit interiors. If the
   capture shows the courtyard too dark, the lever is the cell size
   (`LIGHT_ROOM_CELL_M`) or a per-sublevel weight, not the cap.
3. **The Vault keeps 2 of 25 authored lights** (its bubbles are shared with
   brighter POI lights; 6 of its 7 bubbles remain lit by *some* light). Verify in
   the statuary/ceremonial-chambers capture.
4. **Candles: 0 of 135 sub-1-lumen lights are instantiated** (0 before this wave
   too). They are 0.01-0.9 lm sconce glows with 0.35-1.5 m radius; their meshes
   and flames are still there. If a capture shows sconces reading unlit, the
   remedy is a separately capped candle tier and it costs ~+96 light nodes —
   unmeasured on the 60 FPS desktop gate, so it is an A/B in the capture plan.
5. **SSAO is new and unmeasured.** It is a full-screen pass at 4K on a build that
   was already ~37 FPS at 1080p. `TAT2_AO=off` removes it; the capture plan asks
   for one with and one without.
6. **Height fog changes every outdoor map** (density now attenuates with height
   from y=0). If a street reads too clear, the falloff calibration
   (`fog_height_density`) is one constant.
7. **`moon.light_angular_distance = 25°`** is 1:1 authored and makes the only
   shadow-casting directional very soft; Godot's PCF cost grows with the angle.
   Unmeasured; the capture plan includes a shadow-quality check.
8. **The IsNight classification changes the lobby's preset exposure** from 0.5 to
   1.15. `mission_prep_ui` still overrides to 2.6, so the stage is unchanged
   today, but T05 must know that `max(...)` will keep 2.6 until it adopts
   `stage_grade_values`.
9. **`EV_CURVE_POINTS` is transcribed from the extractor dump**, not from the
   generated JSON; if T01's producer emits a different curve the constant must be
   replaced by a read.

## BLOCKED-ON contracts

### T01-PIPELINE — authored SkyLight cubemap (`sky.cubemap`)
The preset JSON already carries the UE path. Needed: the six TextureCube faces as
a Godot-loadable panorama **without tone-mapping** (the source is
`TC_HDR`/`PF_FloatRGBA`, so 8-bit sRGB PNG is lossy):
```json
// game/data/generated/weather/<preset>.json  (existing fields, no change)
"sky": { "cubemap": "/Game/MaterialLibrary/Utility/Cubemap_GroundFloor_01" }
```
New output the consumer already looks for:
`res://assets/ue/Raw/MaterialLibrary/Utility/Cubemap_GroundFloor_01.exr`
(6 × 512², linear, +X/-X/+Y/-Y/+Z/-Z in UE order, or an equirectangular HDR with
the mapping documented in the extractor). `WeatherProfile.sky_ibl_state()` flips
`ambient_light_sky_contribution` to 1.0 the moment `ResourceLoader.exists()` is
true. **W10-A correction: that is a state consumer, not a texture consumer.** The helper
*is* called in the render path (`weather_profile.gd:959`, inside
`apply_environment`, which `apply_for_map` calls), and its `available`/
`sky_contribution` are consumed at `:960-964`: when the `.exr` exists,
`ambient_light_sky_contribution` rises to 1.0. That does change the image (Godot blends
the **default sky** into ambient at that factor), so "the export alone changes no pixel"
would be wrong too. What is still missing is the texture side: nothing loads
`cubemap_res_path` into a material (no `PanoramaSkyMaterial`, no reflection/ambient
texture path), so the *authored cubemap* is never used even when the file exists. W10-C
therefore needs a **consumer that binds the panorama** as well as the export; "no further
code change is needed" was the wrong claim.

### T01-PIPELINE — authored exposure range + EV curve
`tools/parse_weather.py` drops these from the `PostProcessComponent`:
```json
"postprocess": {
  "auto_exposure_method": "AEM_Basic",
  "auto_exposure_min_brightness": -10.0,
  "auto_exposure_max_brightness": 1.0,
  "auto_exposure_speed_up": 0.2,
  "auto_exposure_speed_down": 2.0,
  "auto_exposure_bias_curve": [[-12.1,-0.5],[-11.1,-1.5],[-10.1,-2.0],[-9.1,-2.25],
                               [-8.1,-2.5],[-6.1,-3.0],[-3.0,-4.0],[0.2,-4.0]],
  "lumen_diffuse_color_boost": 2.0,
  "lumen_skylight_leaking": 0.2
}
```
`EV_CURVE_POINTS` and the GI energy target in `weather_profile.gd` become reads.

### T09-GEOMETRY — `rain.ground_wetness`
`game/src/core/tat_landscape.gdshader` needs `uniform float ground_wetness = 0.5`
multiplied into the wet-layer blend; `WeatherProfile.ground_wetness(preset)`
already returns the authored value (gloomy 1.0, midnight_clear 0.5).

### T12-VFX — `rain.niagara_asset`
The asset path is extracted per preset and unused; the Niagara consumer owns it.

## Capture plan (integrator, one Vulkan run at a time)

Everything below is **not verified** by this team. Suggested order, one capture
per bullet, all at the recorded review poses and with the same session settings:

1. **Baseline regression, Guildhall foyer/interior** (f_0242 pose): expect p50 to
   move from 2 toward the reference 13-15 and `%<8` from 78 % down to ~10-25 %.
   Compare against `docs/reference/clip_1795033698901/clean/KF27`/`KF25`.
   Read the log lines `TAT-2 light allocation: … rooms=152/187 cell_m=16.0`,
   `TAT-2 exposure: preset=gloomy … exposure=1.150`,
   `TAT-2 IBL: … available=false sky_contribution=0.0 gi=ssil ao=true`.
2. **A/B SSAO**: `TAT2_AO=off` vs default at the same pose. Decides whether the new
   contact-shadow pass stays on by default.
3. **A/B GI**: `TAT2_GI=sdfgi` vs `ssil` at the Den map table (KF10 pose) and the
   Guildhall foyer. If SDFGI lifts the core without a frame-time regression on the
   reference host, it becomes the desktop-high default; otherwise it stays a lever.
4. **Glow/white point (P1-4)**: f_0176 pose, `glow_hdr_threshold ∈ {1.6, 2.8}`.
   If the cream facets stop clipping at 2.8 without killing the warm lamp halos,
   the threshold moves; if not, the emissive ceilings are the culprit and go to T08.
5. **White temp (P1-5)**: foyer pose, two candidate gains for `white_temp 5820`
   (cooling `RGB ≈ (0.94, 1.00, 1.07)` vs warming `(1.06, 1.00, 0.93)`). The one
   that matches KF27's wall hue is the convention to implement in a screen pass.
6. **Height fog**: courtyard/alley pose (f_0110/f_0112) — the street should keep
   its ground haze while the tower tops clear; compare the fog gradient with KF15.
7. **Moon shadows**: any pose with a strong moon shadow; 25° angular distance is
   soft by design — check it does not read as a milky smear, and record the frame
   time delta against the pre-wave tree.
8. **Stealth readout**: same pose with the stealth meter visible; more lit rooms
   means more player-visible light. Hand the numbers to T10.
9. **Den control**: KF10/KF02 poses must be unchanged apart from clouds (authored
   `volumetric_cloud_visible: false`) — the Den is the "renderer can hit the
   authored level" control and must not regress.

## Gates evidence

See `build/qa/review_20261124/remediation/logs/` in the worktree for the raw logs
(`t07-make-test*.log`, `t07-probe.log`, `t07-e2e-tier1.log`).
