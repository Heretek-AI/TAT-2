# W9-P2 — behaviour close-out, foyer fills, collision risks (report)

Phase lead: W9-P2. Worktree `/home/john/Projects/TAT-2-rem-w9-p2`, branch
`rem/w9-p2`, base `b13260b` (W9-P1 tip = P0 + P1). **Nothing pushed, merged or
rebased.** Every Godot invocation ran under
`flock /tmp/opencode/tat2-godot.lock`; every capture ran **alone** under
`xvfb-run` with `nvidia-smi` before/after and wall time recorded; no producer
was run and `game/data/generated/` / `extracted/` were never written.

## 0. Capture outcomes — read this first

All frames 1920×1080 Vulkan, `TAT2_AO=on`, measured with the L1 pipeline
(`python3 build/qa/w9_frame_stats.py`), not the in-engine non-black guard.

### 0.1 Final B1 state: fill removal only; the room-grade candidate was reverted

**One table, one statistic per cell.** Every capture is 1920×1080 Vulkan,
`TAT2_AO=on`, L1 pipeline (`w9_frame_stats.py`), and the **same camera pose**
for the pre-P2 and final columns (`upper_foyer` eye `(27, 29.67, −50)` →
`(27, 29.67, −60)`; `yaw180` eye `(27, 29.67, −50)` → `(27, 29.67, −40)`;
gate eye `(10, 24, 66)` → `(10, 25, 48)`). The pre-P2 and final numbers are
therefore comparable; the "both fills gone" and "grade 0.49" rows are
**diagnostics at the same pose**, not shipped states.

| pose | statistic | pre-P2 (both fills) | fill-only final (far fill only) | target | gap (same statistic) |
|---|---|---:|---:|---|---|
| `upper_foyer` | mean (601 luma/255) | 50.5 | 45.7 | KF27 same-room **reference** mean 16.7 (not a band bound) | mean not in the band; 45.7 vs 16.7 is an open tonal gap (highlights) |
| `upper_foyer` | **p50** | 34 | **29** | **13–15** (T07/L1 interior band) | **16 to the 13 floor** (14 to 15) |
| `upper_foyer` | p95 | 182 | 182 | no band bound | — |
| `upper_foyer` | **%<8** | 0.8 | **1.1** | **9–24** | **7.9 to the 9 % floor** |
| `yaw180` (KF27) | mean | 40.5 | 38.9 | KF27 16.7 (reference) | open tonal gap (highlights) |
| `yaw180` (KF27) | **p50** | 31 | **31** | **15** (KF27; band 13–15) | **16 to 15** (18 to the 13 floor) |
| `yaw180` (KF27) | p95 | 105 | 99 | KF27 34 (reference) | — |
| `yaw180` (KF27) | **%<8** | 2.3 | **2.5** | **16.7** (KF27; band 9–24) | **14.2 to KF27 16.7** (6.5 to the 9 % floor) |
| `gate_app` (KF16/18) | mean | 23.2 | 23.2 | KF16/18 reference | unchanged |
| `gate_app` (KF16/18) | p50 | 10 | 10 | 26–28 (reference) | already **below** the reference (darker); not a gap to close |
| `gate_app` (KF16/18) | p95 | 66 | 66 | — | — |
| `gate_app` (KF16/18) | %<8 | 23.9 | 23.9 | **≤ 24 bound** | **0** (within) |
| *diagnostic* `upper_foyer` | p50 / %<8 | both fills gone: 25 / 1.2 | grade 0.49: 14 / 15.3 | (reverted) | not a shipped state |
| *diagnostic* `yaw180` | p50 / %<8 | both fills gone: 31 / 2.5 | grade 0.49: 15 / 17.7 | (reverted) | not a shipped state |

**Definitions.** The interior band is a **distribution** contract: p50 13–15
and `%<8` 9–24. A "gap" is `band floor − measured`, so:
- **p50 = 29** and **%<8 gap = 7.9** are consistent because they are different
  statistics: 29 is the final median; 7.9 = 9.0 − 1.1 is the percentage-point
  shortfall of the black floor to the band's **9 %** floor. The p50 gap is
  **16** (29 → 13) or 14 to 15; the 7.9 does **not** apply to the 29.
- The earlier "band gap 8.9" used T07's ~10 % lower bound (10 − 1.1); against
  the report's 9–24 band it is **7.9**. The 7.9 is the number in this table;
  the measurement is unchanged.
- **KF11 is the mission-prep keyframe (mean 37.2 / p50 28 / %<8 22.9) and is
  not a foyer target**; it is not used in this table. KF27 (16.7 / 15 / 34 /
  16.7) is the same marble-hall room's keyframe.
- The mean/p95 are **not** part of the band. The final mean (45.7) is still
  2.7× KF27's 16.7 while p50 29 vs 15: the highlights (p95 182 vs 34) are the
  open tonal gap, not the midtone/black floor. Do not quote the mean as a pass.

- **The fills are not the main cause, and the band is NOT met.** Fill removal
  recovered **5 of the ~19 p50 points** to KF27's 15 (upper foyer 34 → **29**,
  14 remain; `%<8` 0.8 → **1.1 %**), while `yaw180` did not move at all
  (p50 **31 → 31**, `%<8` 2.3 → **2.5 %**). The remainder is **authored-light/
  ambient level and absent local exposure, not a fill**: freeing both fills
  still leaves p50 25. The open gap is dominated by **highlights** (p95 **182**
  vs KF27's **34**; mean **45.7** vs **16.7**), not the midtone/black floor.
- The room-grade candidate reached the band (upper 14 / 15.3, KF27 15 / 17.7)
  but **failed its pre-registered threshold sweep** and was reverted before
  commit (§0.3). Its frames are kept only as the reverted candidate.
- The gate is unchanged by the fill removal: the fills are >100 m away; the
  final gate frame is statistically identical to the P1 baseline
  (23.2 / 10 / 66 / 23.9) and within its `%<8` ≤ 24 bound.
- `weather_profile.gd` is **byte-identical to `c2a1cd8`**
  (`git diff c2a1cd8 -- game/src/core/weather_profile.gd | wc -l` = 0): the
  Environment preset stays AGX 1.15 / ambient 0.16 and suite 98 (the
  global-cut guard) stays green.
- `foyer` (lower approach, z=125) is unchanged: its overshoot has a different
  cause (road/gate fills, not the two foyer fills) and remains an open risk.

### 0.2 Why fill removal alone cannot reach the band

Measured this session at the shipped exposure 1.15:

| setting | upper_foyer p50 / %<8 | yaw180 p50 / %<8 |
|---|---|---|
| both fills (HEAD) | 34 / 0.8 | 31 / 2.3 |
| **both fills freed** (`W9_GRADE_FILLS=off`) | **25 / 1.2** | **31 / 2.5** |
| near fill freed (the shipped change) | 29 / 1.1 | 31 / 2.5 |
| near fill freed + camera grade 0.49 (reverted) | 14 / 15.3 | 15 / 17.7 |

Freeing **both** fills still leaves p50 25 and 1.2 % < 8: the remaining floor is
the authored light plan + the 0.16 ambient, not the fills. A spatial fix that
reaches 15 would therefore have to cut the room's authored light energy or the
ambient. The ambient is global (the P1 gate ladder: 1.00 → 38.0 % < 8,
0.85 → 51.8 %, 0.75 → 59.6 % — a global cut is the W7 defect and fails the gate
bound), and a per-room light-energy scale would change `light_probe`/guard
detection, i.e. gameplay, which the camera-only candidate did not. The
candidate's 0.49 reached the histogram band but is an **invented spatial
approximation** of UE `AEM_Basic` (the authored counterpart: EV100 −10…+1,
0.2/2.0 f-stops/s, V3 curve, no Guildhall PP volume — `re-b1-exposure.md`),
and it failed the pre-registered continuity/bleed test below. **B1 therefore
ships the fill removal only and records the remaining 14–16 point p50 gap.**

### 0.3 Pre-registered pass criteria for the room-grade threshold sweep

**Written before the sweep capture runs** (the sweep is the next Godot launch
after this paragraph; no criterion below was chosen from a sweep observation).
The sweep walks z = −30 → −50 at x = 27, y = 29.67, looking north, at 0.25 m
per sample (~16 samples across the 4 m feather), then back, and captures each
sample **twice** — grade ON and grade OFF at the same position — so the grade
is isolated from geometry, lights and rain.

Derivation of the numbers: the feather is `w = 1 − smoothstep(0, 4, d)` and the
multiplier is `m = 1 + (0.49 − 1)·w`. The steepest smoothstep slope is
`1.5/4 = 0.375` weight per metre, so the largest multiplier step at 0.25 m is
`0.375 × 0.25 × 0.51 = 0.0478`. The measured tonemap maps the full 0.49→1.0
multiplier span to a mean-luma ratio span of 0.72→1.0 (the AGX curve
compresses), i.e. 0.28 ratio units per 0.51 multiplier units. Therefore the
worst-case per-sample ratio step is `0.0478 × (0.28/0.51) = 0.0262`, and at the
hall's ~46-luma off frame that is ~1.2 luma. The criteria add a noise margin,
not a data fit (its own sum is 0.0302, marginally above the 0.030 bound; the
observed 0.0323 fails under either).

| # | criterion | bound | why this number |
|---|---|---|---|
| C1 | adjacent-step of the on/off **ratio** (0.25 m) | ≤ **0.030** | 0.0262 worst case + 0.004 sampling/rain noise |
| C2 | adjacent-step of the **grade-only delta** `on_mean − off_mean` | ≤ **2.0 luma** | 1.2 worst case + 0.8 noise; isolates the grade from scene parallax |
| C3 | **direction** (ratio, in leg z −30→−50) | **non-increasing**, every Δ ≤ +0.005 | the grade may only darken toward the hall; a reversal > 0.005 fails |
| C4 | **direction** (ratio, out leg z −50→−30) | **non-decreasing**, every Δ ≥ −0.005 | reversible; the same rule mirrored |
| C5 | **reversibility** at matched z (in vs out) | \|Δratio\| ≤ **0.03**; \|Δoff_mean\|/max ≤ **3 %** | the scene must not drift between passes; only the grade may change |
| C6 | **gate/outside bleed**: multiplier at the fixed gate pose | exactly **1.0** | the gate is outside the AABB+feather by 100 m |
| C7 | gate/outside bleed: on/off frame **RMSE** where multiplier = 1.0 (gate pose and every sweep sample at d ≥ 4 m) | ≤ **1.0 %** (65535 scale) and AE ≤ **0.1 %** of pixels | the gate on/off control measured 0.37 % / 0.004 %; 1 % allows rain |
| C8 | analytic scope values from the running code | upper eye **0.49**, gate **1.0**, threshold midpoint (z=−32, d=2) in **[0.70, 0.79]** | the analytic feather table: 0.490 at d=0, 0.570 at 1 m, 0.745 at 2 m, 0.920 at 3 m, 1.000 at 4 m |

A failure of **any** of C1–C8 means the room grade does **not** land: B1 ships
as fill-removal only, with the remaining delta (upper_foyer p50 29 / 1.1 % < 8,
yaw180 31 / 2.5 %) recorded as the open gap. The sweep is run once; the criteria
are not adjusted after the data.

**Result — one run, `b1_sweep1`** (`build/qa/w9/logs/b1_sweep1.log`, 128 s
wall, Xvfb, one Godot, 81 samples per leg, 0.25 m, 3 settle frames per on/off
pair):

```
W9_SWEEP_CONTROL gate_on=23.86 gate_off=23.87 gate_ratio=0.9997
                  upper_on=32.96 upper_off=45.83 upper_ratio=0.7191
                  gate_mult=1.0000 upper_mult=0.4900
W9_SWEEP_CHECK C1 max_ratio_step=0.0323 FAIL      (bound 0.030)
W9_SWEEP_CHECK C2 max_grade_step=1.2873 PASS      (bound 2.0)
W9_SWEEP_CHECK C3 in_monotone=false at z=-43.50 d=+0.0063
W9_SWEEP_CHECK C4 out_monotone=false at z=-40.75 d=-0.0070
W9_SWEEP_CHECK C5 reversibility_ratio=0.0007 PASS scene_drift=0.0020 PASS
W9_SWEEP_CHECK C6 gate_mult=1.000000 PASS
W9_SWEEP_CHECK C7 bleed_rmse=0.1483 PASS bleed_ae=4.7577 FAIL (bound 0.1)
W9_SWEEP_CHECK C8 upper_mult=0.4900 mid_mult(z=-32)=0.7450 PASS
W9_SWEEP_VERDICT FAIL
```

- **The grade did not land.** The multiplier is exactly 0.49 at the upper eye,
  1.0 at the gate, and 0.745 at the analytic midpoint; the ramp's grade-only
  delta is smooth (C2 1.29 luma) and reversible (C5 0.0007 / 0.0020). But the
  pre-registered criteria C1, C3/C4 and C7 fail. The candidate code was
  reverted in the same pass; only the fill removal ships.
- **Why the failures are honest, not a data fit.** C1's 0.030 bound was
  derived from the upper-eye ratio span (0.72); at the threshold the same scene
  measures a ratio span of 0.674 (the on/off ratio at full weight is 0.6737,
  not 0.7191), so the same smoothstep slope produces 0.0323 — 7.7 % over the
  pre-registered bound. C3/C4 reverse on the **plateau** (z −40.75 / −43.50,
  multiplier constant 0.49): the on/off ratio wobbles by 0.006–0.007 with the
  scene/rain, i.e. it is not an exposure pump, but a sign reversal was
  pre-registered as a failure. C7's RMSE passes at 0.148 %, while the AE share counts
  differing pixels with a ~1.7-luma mean (rain, 4.76 %) against a 0.1 % bound. These are
  methodological observations **after** the run; the criteria are not
  revised, and the grade stays reverted. A future attempt must pre-register a
  scene-derived C1 bound (the threshold scene's span, measured before the
  ramp run) and a rain-robust bleed criterion (RMSE only, or a masked AE)
  **before** a new capture.
- The endpoint control is unchanged by the candidate: the separate **gate
  pair** is RMSE 0.367 % / AE 77 px (magick, §0.1), while the sweep's own
  gate sample reads ratio 0.9997, RMSE 0.0313 %, AE 0.635 %. The 0.148 % /
  4.76 % values are the **worst sample in the C7 domain** (the z=-30
  multiplier-1.0 endpoint), not the gate pose. Upper on/off 0.7191 at 0.49.

### 0.4 Why an AABB + feather, and what it is not

**Status: REVERTED — not shipped** (pre-registered FAIL, §0.3). The label, the
authored counterpart and the moving-player analysis below are the record of
what any future room-grade attempt must be called and must not claim; the final
B1 code is the fill removal only.

**APPROXIMATION / NOT AUTHORED.** The authored counterpart (RE:
`build/qa/w9/re-b1-exposure.md`) is a **global, per-view, temporal**
auto-exposure: `AEM_Basic`, EV100 clamp **−10.0…+1.0**, SpeedUp **0.2** /
SpeedDown **2.0 f-stops/s**, `AutoExposureBias 0.0`, and
`Curve_Exposure_Compensation_Float_V3` (EV compensation vs average scene
EV100: −0.5 EV at the dark end, −4.0 EV at the bright end). Citations:
`BP_WeatherPreset_Base.json:2050-2102`,
`BP_WeatherPreset_Base_Skybox.json:1367-1372`,
`BP_WeatherPreset_Gloomy.json:326-337`, `DefaultEngine.ini:527`,
`Curve_Exposure_Compensation_Float_V3.json:15-93`. The Guildhall has **no
placed post-process volume and no authored foyer/gate split**: all 34 generated
Guildhall levels carry `post_process: []`, and no Guildhall camera authors
`PostProcessSettings`. The port's 0.49 is a **linear −1.03 EV** multiplier, not
the authored V3 value (−4.0 EV at the port's assumed night EV100); it is
calibrated to the port's KF27 histogram, not copied from UE.

UE's `AEM_Basic` adapts exposure **per view over time**: the eye brightens and
darkens with the authored speeds, so the whole image (including what is behind
the player) converges to the view's luminance. The room grade approximates only
the **spatial** part (one stable exposure per room) and **not** the temporal
part. Concretely, a moving player sees what the authored game would not:

- at the authored 0.2 f-stops/s, a 4 EV change into a bright view takes ~20 s
  (the RE's derivation; the exact authored foyer/gate EV delta is UNKNOWN — the
  dump has no UE eye-adaptation readout). The port's change is compressed into
  the 4 m feather: **~1.1 s at 3.6 m/s**;
- stopping at the threshold, the port frame does not keep adapting; the
  authored image would continue converging;
- looking from the darker hall into the bright foyer, the port keeps the hall's
  exposure (the foyer is rendered at 0.49 in that view), whereas `AEM_Basic`
  would adapt toward the bright view at 0.2 f-stops/s;
- a lamp switching on or a muzzle flash in the hall does not change the port's
  exposure, while the authored adaptation would respond to it.

It is nevertheless closer to the authored behaviour than a **scene-wide**
multiplier, which is exactly the W7 global cut: that would darken the gate and
every other map. The AABB confines the change to the room where a UE
post-process volume/eye adaptation would act. It does not change
`light_probe`/guard detection (the authored light energies stay authored),
which a per-room light-energy scale would.

**Stale `weather_profile.gd` comments (not edited here, byte-identity is the
control):** `weather_profile.gd:122-126` says the V3 curve pulls the image down
"as the scene darkens"; the keys pull down as the scene **brightens** (−0.5 EV
at ≤−12.1, −4.0 EV at ≥−3.0). `:129-132` says the curve is "consumed ... for
the exposure decision only" and "Godot has no auto exposure at all"; the curve
is diagnostic-only (`:1007-1008`) and Godot 4.7 exposes auto-exposure on
`CameraAttributes`, not `Environment`. Recorded as an integrator doc/comment
fix, not a B1 change.

## Commits on `rem/w9-p2`

| commit | content |
|---|---|---|
| `8d88d12` | B1: near foyer fill removed; room-grade candidate reverted after the pre-registered FAIL; grade probe + sweep harness + RE + fact sheet |
| `f087497` | B0: roof probe rebased onto the authored union; `w9_perf_ab` A/B (load claim retracted, FPS unresolved) + fact sheet |
| `814527f` | B2: authored-lock rule + producer contract, ESC pause guard, labelled lockpick stand-in, tests 101-103 + inventory + fact sheet |
| `a67c724` | B3: Den west-window guard, jam-damage decision, magic-door continuity, tests 104-105 + fact sheet |
| this commit | `p2-report.md`, the four lane audits, suites 101-105 wiring and the corrected suite-98 comment |

## B0 — COLLISION CLOSE-OUT (P1's open risks)

### W9-P2-B0-1 — `test_roof_collision.gd` rebased onto the authored per-element union
- **investigate:** the probe read only `info["shape"]` (the loader's
  `shapes[0]` compatibility field) and called `_get_mesh_and_shape` without
  `_col_path_counts`, so `n=1` and the per-path cost cap never applied. It
  encoded the pre-W9 one-mesh-wide heuristic: 42 PASS / **9 FAIL** in authored
  mode, 51 / 0 in `aabb`. The 9 failures were first-element artefacts (e.g.
  `BayWindowA_6x4` is a reduced trimesh because 27 > 16 elements; End shells
  are 4 hulls, first-hull top 2.945–8.430 vs render 4.316/8.474; shallow pitch
  61.1° vs the union's 45.4°). Not in any gate.
- **research / union truth:** `authored_collision.gd` conversion replayed
  against `mesh_collision.json`; the load-truth instance counts come from the
  shipped PeripheryA JSON (SkyboxGeo is decorative/no-collide). `Mid_4x4`:
  3 hulls, union AABB `(-4.142,-0.058,-3.129)->(0.199,4.179,1.043)`, pitch
  45.4°, eave 3.51 m; `Mid_6x8`: 4 hulls, pitch 67.0°, eave 7.06 m; End shells
  4 hulls each, union top within 0.082 m, eave 3.50–7.63 m.
- **fix:** new `_authored_union(ue_path, instances)` uses
  `AuthoredCollision.resolve(path, n)` with `n` counted from the level JSON and
  transforms every shape by its offset; the loader is used only for the render
  AABB. The 9 assertions were re-based with the same intent (authored source,
  per-element count/reduction, union top within 0.10 m, eave ≥ 3.0 m, union
  pitch 45.4/67.0, Old Manor 3 reduced + 1 ten-hull + 1 box + 1 complex), plus
  two load-truth census checks. No check was deleted to go green. Three
  conditions changed shape and are disclosed: the End z-span equality was
  removed (the union span can overshoot the render AABB by 0.198 m and carries
  no eave meaning), the End top tolerance widened 0.01 → 0.10 m (the union is
  exact to 0.082 m; the old 0.01 m was first-hull-only), and the convex
  ">8 hull points" condition is replaced by the authored encoding check
  (reduced trimesh / per-element hulls / one exact primitive) so an authored
  primitive is not misjudged as a hull.
- **confirm (red → green):**
  - RED authored `ROOF_COLLISION_SUMMARY: fails=9` (42 PASS); RED aabb
    `fails=0` (51 PASS).
  - GREEN authored **`fails=0` (53 PASS)**; GREEN aabb **`fails=0` (53 PASS)**.
  - `probe_collision_authored.gd`: `COL_AUDIT ... shapes=30901 bodies=243
    dropped=0 load_ms=19992 coverage=0.989` (unchanged).
- **verdict: FIXED** (probe now measures the authored truth in both modes; the
  loader-integration proof stays with `probe_collision_authored.gd`).

### W9-P2-B0-2 — collision A/B: FPS p50/p95 and load on the same poses
- **method:** new `build/qa/w9_perf_ab.gd` + `.sh`; one process per mode
  (`AuthoredCollision` is process-static), same Guildhall order 4, same 3
  poses, vsync off, 1920×1080, 240 measured frames after 60 warm, host
  compositor, `TAT_LOAD_TIMING=1`, ABBA order (authored, aabb, aabb, authored)
  so linear host drift cancels. `TAT2_COLLISION` is printed in every line.
- **census:** authored `shapes=30905 bodies=243 dropped=0`; aabb
  `shapes=24466 bodies=225 dropped=0`; `+6,436` authored shapes reproduce P1.

| mode / run | load_ms | upper p50 / p95 | yaw180 p50 / p95 | gate p50 / p95 |
|---|---:|---|---|---|
| authored r1 | 24,230 | 15.01 / 18.27 | 23.75 / 30.42 | 22.70 / 30.54 |
| aabb r1 | 27,435 | 15.15 / 19.46 | 24.43 / 30.33 | 22.73 / 28.45 |
| aabb r2 | 27,729 | 14.90 / 18.14 | 24.46 / 30.44 | 22.68 / 30.75 |
| authored r2 | 28,434 | 15.31 / 19.80 | 25.77 / 37.47 | 24.43 / 37.03 |
| **ABBA mean, authored − aabb** | **−1,250 ms** (r1 −3,205; r2 +705) | **+0.13 ms (+0.9 %)** p50; **+0.24 ms (+1.25 %)** p95 | **+0.31 ms (+1.3 %)** p50; **+3.56 ms (+11.7 %)** p95 | **+0.86 ms (+3.8 %)** p50; **+4.19 ms (+14.1 %)** p95 |

- **FPS — not resolvable from two runs; do not claim "no regression".** The
  p50 deltas are +0.9 / +1.3 / +3.8 %, but the p95 deltas are +1.25 / +11.7 /
  +14.1 %, and both p95 outliers are the authored **r2** run, which is also
  the slowest p50 and the hotter round. Two runs per mode cannot separate an
  authored-collision p95 cost from thermal drift. The ABBA-mean deltas are
  p50 +0.9 / +1.3 / +3.8 % and p95 +1.25 / +11.7 / +14.1 %; the **per-round**
  p50 deltas are −0.9 / −2.8 / −0.1 % (r1) and +2.8 / +5.4 / +7.7 % (r2), and
  the per-round p95 deltas are −6.1 / +0.3 / +7.4 % (r1) and +9.2 / +23.1 /
  +20.4 % (r2). A cool-host 3-repeat run is needed before any conclusion. The absolute FPS
  in the yaw180/gate views (37–44) is host-bound on this laptop (P0 measured
  43.6–46.7 with the same method); it is **not** a 60 FPS pass and is not
  quoted as one.
- **Load — the P1 "+2.5–3.7 s" is retracted, but the direction is not
  resolvable either.** Authored is 3,205 ms faster in round 1 and 705 ms
  slower in round 2; the ABBA mean is −1,250 ms (authored faster); the
  observed round deltas are −3,205 and +705 ms (a **3,910 ms peak-to-peak
  span**, half-width ±1,955), which swamps the mean. The honest result: **no
  stable multi-second authored load penalty is reproducible on this host**;
  P1's +3.65 s and the A1 audit's −5.0 s lie outside the observed round-delta
  range [−3,205, +705] and neither direction should be quoted. A cool-host
  3-repeat run is owed.
- **Attribution (measured, no loader edit):** `LoadTiming` per run — parse
  4,706/5,727 authored vs 5,944/6,400 aabb; lights +47/+52 vs +61/+68;
  terrain 0.59/0.81 vs 0.77/0.78 s; draw 21.3/25.0 vs 23.8/24.0 s
  (`mesh_ms` 7.60/8.87 vs 8.24/8.34; `build_ms` 11.80/13.54 vs 12.90/12.99;
  `glb_ms` 1.24/1.55 vs 1.54/1.40; `mat_ms` 4.12/4.94 vs 4.57/4.53;
  `shape_ms` is dead/0). The
  authored payload is **258–386 ms** (r1/r2; aabb loads it in `_finalize`,
  299–311 ms). The raw ABBA `mesh_ms` delta is **−54 ms** (aabb is +54 ms);
  adjusting for the payload that authored pays inside `mesh_ms` and aabb pays
  after `draw_ms`, the aabb trimesh cost is **≈ +376 ms** — still well below
  the 1.25 s mean and inside the drift, so it is **not** the larger term and
  cannot explain a 1.25 s delta. The per-instance
  `CollisionShape3D` emission is inside `draw_ms` (after `perf_build_ms`
  closes) and is not separable without editing P1's loader; its contribution
  is bounded by the draw delta (−727 ms ABBA mean), itself inside the drift.
  **No phase attributes the end-to-end delta; the payload (≤0.39 s) is the
  only fixed authored cost.**
- **verdict: MEASURED — load claim retracted (no stable penalty; direction
  unresolved), FPS ABBA-mean p50 +0.9/+1.3/+3.8 % but per-round up to +7.7 %,
  p95 up to +23.1 % in r2; unresolved from two runs.** **Open:** cool-host 3-repeat run; the absolute
  FPS in the yaw/gate views is laptop-thermal (unchanged from P0/P1);
  `probe_leak`/M2/E2E etc. are in the gate table below.

## B1 — FOYER FILLS

### W9-P2-B1-1 — the two foyer fills: attribution and removal
- **investigate:** `mission_controller.gd:560-580` (`_add_guildhall_foyer_fills`)
  created two shadowless warm omnis at `(27,31,−53)` energy 1.6 and
  `(27,31,−64)` energy 1.3, range 16 m, both registered with `light_probe`;
  created in `_setup_environment()` **before** the sublevel load, so they are
  outside the 160-slot authored light budget (`PERF_CENSUS lights=171` vs
  `Loaded guildhall lights=160`). Distances to the eyes: upper_foyer/yaw180
  3.28 m / 14.06 m; gate 120.4 m / 131.3 m; lower foyer 178.6 m / 189.6 m; a
  16 m omni cannot reach any pose but the upper foyer.
- **research:** P1 §0.2 (the 1.15/0.44 table, the 1.00→0.85→0.75 gate ladder,
  the fills-off A/B at 0.44) and `T07-render.md` (interior band p50 13–15,
  %<8 9–24; KF27 16.7/15/34/16.7). **P1's fills-off A/B was at 0.44 only**; at
  the shipped 1.15 the fills are a smaller contributor (this report §0.2).
- **confirm (red):** `build/qa/w9_grade_probe.gd` bracket at exposure 1.15,
  poses `upper_foyer,yaw180`, fill energy scales `1.0,0.0,0.2,0.35,0.5`:
  `b1bracket1_upper_foyer_e115_a100_l100` = 50.5 / 34 / 180 / 0.8;
  fill 0.0 = 41.5 / 25 / 180 / 1.2; yaw180 40.5 / 31 / 105 / 2.3 → 38.9 / 31 /
  99 / 2.5. **At 1.15 neither pose can be brought into band by fill energy
  alone** (p50 25 with both fills gone, target 15).
- **fix:** `_add_guildhall_foyer_fills()` keeps only the far
  `(27,31,−64, 1.3)` fill; the near fill is removed with the measured
  rationale in the comment (it dates from the pre-R8 crushed exposure and
  double-lit the pose; the far fill is the room's practical for gameplay
  light detection). No preset, ambient or authored light energy changed.
- **test / confirm (final):**
  - `p2_fillonly_upper.png` **45.7 / 29 / 182 / 1.1** (was 50.5 / 34 / 180 /
    0.8); `p2_fillonly_foyer_sweep_yaw180.png` **38.9 / 31 / 99 / 2.5** (was
    40.5 / 31 / 105 / 2.3); `p2_fillonly_gate_*` **23.2 / 10 / 66 / 23.9**
    (unchanged; the fills are >100 m away).
  - `weather_profile.gd` byte-identical to `c2a1cd8`; suite 98 green.
- **verdict: PARTIAL — fill removal recovered 5 of the ~19 p50 points; the
  remainder is authored-light/ambient level and absent local exposure, not a
  fill.** Upper foyer 34 → 29 p50 (14 to KF27's 15; 16 to the 13 floor),
  `%<8` 0.8 → 1.1 (7.9 to the 9 % floor); `yaw180` unmoved at 31 (16 to 15,
  18 to 13; `%<8` 2.5, 6.5 to the floor). The open gap is dominated by
  highlights (p95 182 vs 34; mean 45.7 vs 16.7), not the midtones. The cause
  is measured: both fills gone still leaves p50 25 (authored light plan + 0.16
  ambient); a fill-only spatial fix cannot close it, and the remaining levers
  are a global cut (rejected: gate ladder), a per-room light-energy scale
  (changes gameplay `light_probe`), or the authored **temporal** AEM model
  (open risk 1). **Open.**

### W9-P2-B1-2 — the room-grade candidate: implemented, measured, **reverted**
- **research (lever + authored truth):** `CameraAttributes.exposure_multiplier`
  (Godot 4.7, per camera, auto-exposure off) is a camera-scoped exposure that
  leaves `weather_profile.gd`/the Environment byte-identical. The authored
  counterpart is a **global-per-view temporal** `AEM_Basic` (EV100 −10…+1,
  SpeedUp 0.2 / SpeedDown 2.0 f-stops/s, bias 0, V3 curve) with **no Guildhall
  PP volume and no foyer/gate split** (all 34 Guildhall levels
  `post_process: []`). The candidate's 0.49 is a linear −1.03 EV, not the
  authored V3 −4.0 EV. Full RE: `build/qa/w9/re-b1-exposure.md`; the label
  "APPROXIMATION / NOT AUTHORED" is in the code history and §0.4.
- **candidate (green on the two poses):** AABB `(10,27,−76)…(44,35,−34)` +
  4 m feather, multiplier 0.49; bracket on the real lever 0.47/0.49/0.51 →
  upper 13–14 / 14–17.0, yaw180 14–15 / 16.0–19.7. Captures
  `p2_after_upper_foyer` 33.0 / 14 / 178 / **15.3** and
  `p2_after_foyer_sweep_yaw180` 27.1 / 15 / 91 / **17.7** (both in the
  reference band); gate pair RMSE 0.37 % / AE 77 px.
- **pre-registered sweep (one run, `b1_sweep1`):** criteria C1–C8 written into
  §0.3 **before** the capture. Result: **FAIL** — C1 0.0323 > 0.030,
  C3/C4 plateau reversals 0.0063/0.0070 > 0.005, C7 AE 4.7577 % > 0.1 %
  (RMSE 0.148 % passed). C2 (1.287 ≤ 2.0), C5 (0.0007/0.0020), C6 (gate 1.0)
  and C8 (0.49 / 0.745) passed. The failures are honest (the C1 bound was 7.7 %
  tight for the threshold scene's larger ratio span; C3/C4 are plateau
  scene/rain noise, not a pump; C7 AE counts 1-LSB rain pixels), but the
  criteria were not revised and the grade does not land.
- **fix (revert):** the room-grade constants/functions/`_tick_room_grade`,
  the suite-100 guard and `probe_room_grade.gd` were removed in the same pass;
  the sweep harness is kept as the reproducible instrument with a header note.
  The final code has the fill removal only. The reverted candidate's frames
  and the sweep log are the evidence that a room grade can reach the band but
  did not pass its own continuity/bleed bar.
- **verdict: REVERTED** (not shipped). A future attempt must pre-register a
  scene-derived C1 bound and a rain-robust bleed criterion before a new run;
  the labels and RE are already in place.

### W9-P2-B1-3 — capture provenance (one Godot at a time)
- Every capture: `xvfb-run -a`, `flock`, `timeout 1800`, GPU before/after and
  wall time in `build/qa/w9/logs/<tag>.log.gpu_before|_after`.
  `p2_fillonly_upper`, `p2_fillonly_foyer_sweep` and `p2_fillonly_gate` ran
  serially after the revert; the candidate frames (`p2_after_*`,
  `p2_gate_on/off`) and the sweep (`b1_sweep1`, 128 s) ran before it. No
  capture overlapped another Godot (`w9_capture.sh` aborts on a concurrent
  process; every run held the flock).
- GPU during the captures: 57–67 °C, 4.42–5.58 GiB, 7–56 % util; wall 45–128 s
  per launch (see the `.gpu_*` files). CPU package 80–96 °C: these are laptop
  stills, not a perf gate; every number is a histogram, not a timing.

## B2 — LOCKS + LOCKPICK

### W9-P2-B2-1 — authored locks only: the consumer rule and the inventory
- **investigate:** the dump authors `_locked` on **173 placed actors** (157
  containers, 8 doors, 8 windows) with `_lockConfig.MaxLockLevel` (155 × 2,
  3 × 1; 15 absent) and `CanBeLockpicked`/`KeyTag`; there is **no per-instance
  level** (`LockLevel`/`lock_level` = 0 occurrences in 12,541 JSONs).
  `tools/parse_tables.py` dropped every lock field, and all 107 generated
  levels carry zero lock keys; the runtime spawned **0 locked containers and
  0 locked doors**. The deleted `3 + count % 2` / `count % 12 == 5` /
  container-index formulas had not returned; the only level left was the
  SceneVariant door default **3** (invented).
- **research:** `build/qa/w9/facts-b2.md` §1–3 (full inventory, the 4 key-only
  doors, the 8 windows resolved as door pivots); `b2-producer-contract.md`
  (the exact producer keys and a `git apply`-able patch).
- **fix:**
  - `level_loader.marker_lock_fields()` carries `locked`, `max_lock_level`,
    `min_lock_level`, `can_lockpick`, `key_tag` 1:1; absent keys stay absent.
  - `loot_container.configure` / `swinging_door.configure`: locked iff
    `locked == true`; level = the authored cap (clamped 1..6 containers / 1..4
    doors) — a **labelled port decision** (no authored level exists); a locked
    record with no cap locks at 1; key-only (`CanBeLockpicked == false`) and
    window actors are excluded with counters (no key inventory / no window
    interaction); `entry.lock_level` is no longer read.
  - `mission_controller._spawn_swinging_doors`: SceneVariant `scene_locked`
    now uses `DoorScript.table_max_lock_level()` (authored 4), removing the
    invented 3.
- **test:** `run_tests` suite **101** (`test_w9p2_locks.gd`, 28 checks) and
  `probe_lock_inventory.gd`:
  `LOCK_INVENTORY PASS authored_containers=157 authored_doors=8
  authored_windows=8 locked_now=0`.
- **verdict: PARTIAL / BLOCKED-ON-INTEGRATOR-REGENERATION.** The consumer,
  the rule and "zero invented levels" are **FIXED** and proven; the **runtime
  application** needs the producer contract + a regeneration at merged HEAD
  (forbidden here: shared read-only data). Expected after regeneration:
  **144 locked container markers + 10 locked door nodes** in gameplay (18
  door nodes excluded: 16 window + 2 key-only). The inventory probe reports
  the **raw** join (`locked_now=362` = markers 161 + actors 173 + door records
  28, because the producer emits each authored actor into both `markers` and
  `actors`; `marker_locked=334 / door_locked=12 / window_locked=16`). The 144/
  10 is the de-duplicated spawn result; both are expected and the probe's
  exit code is unaffected. The 3 vault and 2 doorway key-only locks
  stay unlocked by design (no key inventory; honouring them would soft-lock
  content). The prison doorway authors a KeyTag but **no**
  `CanBeLockpicked`, so by the authored flag it is pickable and locks at the
  1 fallback — flagged, not silently re-classified.

### W9-P2-B2-2 — the LV4 `[ESC] CANCEL` double-handling
- **investigate:** `hud.gd:2407-2411` (`_input` ESC → `_finish_lockpick(false)`)
  runs before `_process:2517`; `set_input_as_handled()` does not clear
  `Input.is_action_just_pressed("pause")`, so the same frame's `_process` saw
  `_lockpick_active == false` and called `_toggle_pause()` — the lock was
  cancelled **and** the pause menu opened. Level-independent (the "LV4" is
  only the HUD title suffix).
- **fix:** `_pause_consumed_frame` stamped in the `_input` cancel branch,
  checked in the `_process` pause branch (the existing `_npc_dialogue_closed_frame`
  pattern). No other HUD code touched.
- **confirm (red → green):** RED `LOCKPICK_CANCEL FAIL checks=18 fails=2`
  (both `paused=true`); GREEN **`LOCKPICK_CANCEL PASS checks=18`** (paused
  false, callback false, door still locked, a later ESC still opens pause).
- **verdict: FIXED**, suite **102**.

### W9-P2-B2-3 — lockpick hands: the labelled stand-in
- **investigate:** 41 lockpick filelist entries (36 `.uasset` + 5 `.ubulk`),
  **0 animations, 0 `.glb`**, no lockpick tool mesh; `anims_manifest.json` has
  0 lockpick clips. `set_lockpicking_active()` only flipped a bool.
- **fix:** a labelled **PORT STAND-IN** in `thief_character.gd`: a procedural
  pick (shaft + hook + grip) on the 1P rig at a fixed right-hand offset, plus a
  small static rig pose offset while picking; freed and the base pose restored
  on exit. Code and meta say `authored=false`,
  `port_standin=no authored lockpick mesh/animation exists`. Null-safe with no
  1P rig.
- **test:** `LOCKPICK_HANDS PASS checks=20` (absent by default, present +
  visible while picking, restored after, base transform unchanged), suite 103.
- **verdict: FIXED** (labelled stand-in; no authored animation is claimed).

## B3 — REMAINING BEHAVIOUR

### W9-P2-B3-1 — telescope `[F] EXIT` / Den roof (L4-13)
- **investigate:** the ponder toggle is camera-only (no player write); the Den
  telescope is at (-4.9202, 40.255, 270.734), 1.14 m inside the measured west
  opening (wall plane x=-6.06, z 270.4–272.4, sill y=41.0, top y=45.1). The
  0.745 m sill is inside `try_auto_mantle`'s 0.45–4.0 m band, so the recorded
  run's walk out of the opening is the mechanism.
- **confirm (red):** on this HEAD the RED **did not reproduce**: P1's authored
  `SM_ThievesDen_Glass`/`SM_ThievesDen` concave collision (`7939a61`) now stops
  the walk at x≈-5.26, and the stronger forward+sprint attempt only
  wall-climbs to y≈43.15 (below 45.1). Disabling the glass shape at runtime
  still does not reopen it (shell collision). The probe logs
  `pre_fix_escape_reproduced=false`.
- **fix:** a **defense-in-depth** invisible `StaticBody3D`
  (`DenWestWindowBlocker`) at the authored opening plane: layer 1 / mask 0,
  0.12 × 4.883 × 2.00 m (inner face x=-6.06, top y=45.10, z 270.4–272.4,
  down to the floor so the 0.30 m mantle wall probe hits it), group
  `blocking_volume` (solid to walk into, never a mantle/ledge/climb anchor),
  no mesh. It stays 1.14 m inboard of the telescope area and 1.24 m from the
  ponder camera (audit-measured).
- **test:** `DEN_WINDOW PASS checks=34` — 4/4 layer-1 rays on the blocker,
  `blocking_volume`, no mesh, ponder enter/exit camera + vista, player
  position unchanged by the toggle, the walk/sprint attempts stay inside, and
  the KF05 ponder view is a PASS.
- **verdict: NOT REPRODUCED on this HEAD** (already stopped by the authored
  glass collision) + **GUARD ADDED** and probed. **Open:** only a GPU capture
  can settle the ponder view's pixels; the blocker has no mesh.

### W9-P2-B3-2 — jam damage on `LOCK JAMMED!` (L4-01): decision
- **research:** `CT_LockpickDamage.DamageByLockLevel` = 5/10/20/40 authored 1:1
  into `interactables.json`; the only production applier is
  `hud.gd:3252-3267` (`take_damage`), the door/container false callbacks and
  the no-HUD timed fallback deal **no** damage; player max_health 300, bar
  reveals at <0.999. Four LV3 jams = 80 → 220/300 = 73.3 %, the record's
  ~75 % first reveal (shaped-fill read).
- **decision: INTENDED / AUTHORED, no balance change.** Levels 5/6 use the
  labelled 80/160 fallback (no authored row; not reachable today: doors cap at
  4, containers have no authored level).
- **test:** `JAM_DAMAGE PASS checks=29` — exact per-level values, HUD single
  application (280 after one LV3 jam), no second hit inside the 0.5 s window,
  no damage from door/container false callbacks or the no-HUD fallback, bar
  hidden at 300/300 and visible at 299/300, fill ratio after four jams
  220/300 ± 0.01. Suite 104.
- **verdict: DECIDED + TESTED** (no production change).

### W9-P2-B3-3 — magic-door continuity during the endgame: decision
- **research:** `escape_gate.gd` extracts only on `is_available()` +
  `phase == endgame` + all objectives complete; `_rearm_escape_gates()` runs
  every endgame tick; collapse is terminal; a dormant gate never extracts.
  The 240 s authored open cycle is reinterpreted as a **re-armable cycle**
  inside the 1200 s endgame (labelled port decision in T10/R10).
- **decision: KEEP CONTINUOUS** (the current behaviour; at most a one-frame
  boundary gap). No production change.
- **test:** `ENDGAME_CONTINUITY PASS checks=23` — dormant/incomplete/resolved
  emit nothing; one activated endgame entry → exactly one `extracted`;
  `expire()` + `_rearm_escape_gates()` restores availability in the same tick
  (`rearm_count` 0→1, `active_escape_count()` 1→1); collapse is terminal.
  Suite 105.
- **verdict: DECIDED + TESTED** (documented; dormant-gate rule preserved).

### W9-P2-B3-4 — pre-existing headless warning (not B3)
- The Den walk logs `audio_manager.gd:712 _occluded` (`Array[PhysicsBody3D]`
  assigned to `Array[RID]` from `play_footstep`). It is present in the RED log
  before any B3 edit; reported only, not changed.

## Golden gate set on the merged tree

All runs on this tree (`rem/w9-p2` + the W9-P2 working tree), serially, under
`flock /tmp/opencode/tat2-godot.lock`; no capture overlapped another Godot.

| gate | result |
|---|---|
| `tools/check_scripts_compile.gd` | **164 checked, 0 broken** (R8/P1 floor 152/157) |
| `tests/run_tests.gd` | **SUMMARY: fails=0**, **308 `^PASS`** (303 + suites 101–105; R8 floor 301) |
| `tests/test_m2_player.gd` | **M2_SUMMARY: fails=0** (12) |
| `tests/e2e/run_e2e_tests.gd --tier=1` | **fails=0 passed=117 total=117** |
| `tests/e2e/run_e2e_tests.gd` | **fails=0 passed=278 total=278** |
| `tests/probe_door_walk.gd` | **DOORWALK PASS** |
| `tests/probe_viewmodel_truth.gd` | **VIEWMODEL_TRUTH PASS** |
| `tests/probe_niagara.gd` | **NIAGARA_PROBE PASS** |
| `tests/probe_blackjack_race.gd` | **BLACKJACK_PROBE PASS fails=0** |
| `tests/probe_geometry_placement.gd` | **GEOM_PROBE PASS** |
| `tests/probe_collision_authored.gd` | **COL_AUDIT ... dropped=0 coverage=0.989 shapes=30901 bodies=243** |
| `tests/test_roof_collision.gd` | **53 PASS / 0 FAIL** authored **and** aabb |
| `tests/probe_den_window.gd` | **DEN_WINDOW PASS checks=34** |
| `tests/probe_lock_inventory.gd` | **LOCK_INVENTORY PASS authored_containers=157 authored_doors=8 authored_windows=8 locked_now=0** |
| `tests/test_w9p2_locks.gd` (suite 101) | **LOCKS PASS checks=28** |
| `tests/test_lockpick_cancel.gd` (suite 102) | **LOCKPICK_CANCEL PASS checks=18** |
| `tests/test_lockpick_hands.gd` (suite 103) | **LOCKPICK_HANDS PASS checks=20** |
| `tests/test_jam_damage.gd` (suite 104) | **JAM_DAMAGE PASS checks=29** |
| `tests/test_w9p2_endgame_continuity.gd` (suite 105) | **ENDGAME_CONTINUITY PASS checks=23** |
| `probe_leak.gd` (`TAT2_NO_DEN_PROBE=1`) | clean: `PROBE after gh free players=0` |
| `make audit` | **AUDIT PASS** — 12,660/12,703 coverage, 0 unexpected, baseline matches |
| `make texture-cap-check` | **OK** — 797 capped, 1 alpha-critical, 0 offenders |
| `build/qa/test_perf_guard.sh` | **PERF_GUARD_TEST PASS checks=78 fails=0** |
| `make gate-ratchet` | **GATE_RATCHET: PASS** (R8 logs, floors as minimums) |

No floor was lowered: compile 152 → 164, run_tests 301 → 308, E2E 278 → 278,
audit 12,660 → 12,660, texture cap 797 → 797, perf guard 78 → 78.

B0 A/B (the new numbers, above): the ABBA load mean is −1.25 s (authored
faster) but the 3,910 ms peak-to-peak spread swamps it, so **no stable load
penalty is reproduced**; the P1 "+2.5–3.7 s" claim is retracted and the
direction is not claimed. FPS p50 +0.9/+1.3/+3.8 %, but p95 +1.25/+11.7/+14.1 %
(unresolved against thermal drift); the absolute yaw/gate FPS (37–44) is
host-thermal and is not quoted as a 60 FPS pass.

## Independent audits

One auditor per lane, each a separate agent that did not write the code; all
read-only apart from their own report. They re-ran the lane proofs themselves,
not just the lead's logs.

| lane | report | verdict | independent evidence |
|---|---|---|---|
| B0 collision | `build/qa/w9/audit-b0.md` | **PASS** (after two re-audits of the load attribution) | roof probe 53/0 both modes; `COL_AUDIT ... dropped=0 coverage=0.989`; union replay Mid_4x4 45.44°, Mid_6x8 67.02°, End top ≤0.082 m; ABBA numbers recomputed; the first FAIL was a report overstatement (not code) and was corrected to per-round ranges / 3,910 ms peak-to-peak / payload-adjusted +376 ms |
| B1 foyer/grade | `build/qa/w9/audit-b1.md` | **PASS** | recapture identical to 45.7 / 29 / 182 / 1.1 (frame RMSE 0.101 %); no grade symbol/attribute/test/probe left; `weather_profile.gd` byte-identical; sweep log FAIL with the exact criteria; `run_tests` 308/0, no suite 100; only imprecision was the gate/C7 domain split (fixed) |
| B2 locks/ESC/hands | `build/qa/w9/audit-b2.md` | **PASS** | rebuilt the HUD with the three B2 hunks removed → byte-identical to HEAD; real engine loop RED `paused=true`, live `paused=false`, later ESC still pauses; 173 = 157/8/8, caps 155×2/3×1/15; `git apply --check` 5 hunks; `test_t10_gameplay` change justified; one docs-only finding (post-regen probe raw count 362, not 154) fixed |
| B3 behaviour | `build/qa/w9/audit-b3.md` | **PASS** | DEN_WINDOW 34 / JAM 29 / ENDGAME 23 reproduced; blocker-on/off identical and the live stop is the authored glass plane (−5.71 vs the guard's −6.06); jam values authored; endgame dormant/re-arm/collapse pinned; doc nits fixed (1.24 m, jam header, probe comment) |

No lane's audit found a weakened test, a fabricated measurement or a gate
relaxation. The two FAIL verdicts during the process were both report-language
overstatements (B0 load attribution) and were corrected before commit; the
underlying measurements never changed.

## Open risks / blocked / deferred

1. **Interior band is NOT met by the shipped B1 change** (upper_foyer 29 /
   1.1 %, yaw180 31 / 2.5 % vs 13–15 / 9–24). Fill removal recovered 5 of the
   ~19 p50 points; the gap is authored-light/ambient + highlights. **Follow-up
   design (inherited by the next wave): implement the authored temporal
   eye-adaptation, not a spatial gain.** The authored path is `AEM_Basic`:
   EV100 clamp −10…+1, `SpeedUp` **0.2 f-stops/s** (dark→bright) and
   `SpeedDown` 2.0 f-stops/s, bias 0 and `Curve_Exposure_Compensation_Float_V3`;
   at 0.2 f-stops/s a ~4 EV move takes **~20 s to equilibrium** (`re-b1-
   exposure.md`). A future lane should implement that **temporal** model (or a
   bounded analytic approximation of it: an exposure state per view that
   converges at the authored rate and clamps to the authored EV range) rather
   than a spatial multiplier. It must be validated against **both foyer poses
   and the gate approach** — the gate's `%<8` ≤ 24 bound is what killed the
   spatial version (the gate is already below its KF16/18 p50 reference at
   1.15; any added exposure must not move it) — with a pre-registered
   continuity/bleed sweep like §0.3. Do not resurrect the 0.49 constant; do not
   substitute a scene-wide cut. The prerequisite is the T01 producer/
   consumer gap: `parse_weather.py` must emit the AEM method/min/max/speeds/
   curve, and a consumer must apply the EV100 curve (the V3 transcription
   exists at `weather_profile.gd:133-140` but is diagnostic only).
2. **B2 runtime locks are BLOCKED-ON-INTEGRATOR-REGENERATION.** Apply
   `build/qa/w9/parse_tables-lock-fields.patch`, regenerate, refresh stamps,
   re-run `probe_lock_inventory.gd` (expect the raw `locked_now=362`, i.e.
   markers 161 + actors 173 + door records 28; gameplay de-duplicates to 144
   containers + 10 door nodes). After
   regeneration **144 major containers + 10 door nodes lock at LV2** (authored
   `_locked`); that is a large, authored-but-unplayed gameplay change — playtest
   it and watch `test_t10_gameplay`/E2E. Key-only doors (3 vault + 2 doorway)
   and the 16 window nodes stay unlocked by design (no key inventory/window
   interaction); the prison doorway authors a KeyTag but no
   `CanBeLockpicked`, so it locks at the 1 fallback — flag, do not silently
   reclassify.
3. **L4-13 is not reproducible on this HEAD** (authored glass/shell collision
   stops the walk); the new blocker is defense-in-depth and has no mesh. A GPU
   capture of the KF05 ponder view is owed to confirm the blocker does not
   intrude visually; the probe only proves LOS/camera state.
4. **Jam damage is a decision, not a fix:** 5/10/20/40 authored, applied once
   by the HUD; no balance change. The record's 75→38 % end state needs ~8–9
   jams and is not fully closed by the available logs.
5. **Magic door is kept continuous** (re-armable 240 s cycle inside the 1200 s
   endgame); the authored 240 s single-window reading is deliberately not
   adopted; at most a one-frame boundary gap.
6. **B0 absolute FPS is host-bound** (the CPU package measured **92 °C after**
   the runs, not during them; the recorded GPU is 67.9–74.8 °C; yaw/gate 37–44
   vs P0's 43.6–46.7). A cool-host `run_perf_matrix.sh` re-run is still owed before
   any 60 FPS parity claim. The load-delay claim is retracted (authored is
   faster); the shape budget is unchanged (30,905 < 32,000, 0 dropped).
7. **`test_roof_collision.gd` is mode-independent by design** (reads
   `AuthoredCollision.resolve` with load-truth counts); the loader-integration
   proof is `probe_collision_authored.gd`. Do not treat the roof probe as a
   loader gate.
8. **`weather_profile.gd` stale comments** (V3 direction inverted; "Godot has
   no auto exposure" false) are documented in §0.4 but not edited: byte-identity
   is the B1 control. Fix them in a docs-only commit.
9. **Pre-existing** `audio_manager.gd:712 _occluded` warning in the Den probe
   (present before any B3 edit); reported only.
10. **Producer gaps for the integrator:** B2 lock fields (above) and P1's
    `parse_collision.py` `half_extent` rename/record gap; the roof-probe entry
    in `docs/FIDELITY_GAPS.md` is still owed.
11. **`build/qa/*.md` and the patch are gitignored**; force-add the reports,
    audits, fact sheets, RE and the patch with `git add -f`.

## Integrator steps

1. **Cherry-pick the commits in order; do not squash** (the red proofs and the
   measured tables are in the messages). Nothing was pushed, merged or rebased.
2. **B2 producer + regeneration (only at merged HEAD):** apply
   `build/qa/w9/parse_tables-lock-fields.patch`
   (`git apply --check` passes), run `make normalize`, then
   `make audit-refresh-stamps` with the written reason (the producer changed by
   design). Re-run `probe_lock_inventory.gd`; it must flip from
   `applied=0 state=BLOCKED-ON-INTEGRATOR-REGENERATION` to the raw
   `locked_now=362` (gameplay: 144 container markers + 10 door nodes). Then re-run `run_tests`, E2E and
   `make audit`/`gate-ratchet`. Do **not** regenerate in a worker worktree.
3. **Expect the authored locks to change play:** 144 major containers at LV2
   plus the lockpickable doors. Playtest the Guildhall/OldManor route; the
   key-only vault/apartment doors and windows remain open by design (see
   §B2-1).
4. **Do not resurrect the reverted 0.49 room grade.** The B1 code ships fill
   removal only; `weather_profile.gd` must stay byte-identical. A future room
   grade needs a new, separately pre-registered sweep with a scene-derived C1
   bound and a rain-robust bleed criterion; the failed run is in
   `build/qa/w9/logs/b1_sweep1.log` and the harness is kept with a status note.
5. **Docs owed at integration (not P2-owned files):** `docs/FIDELITY_GAPS.md`
   — interior band remains open (upper 29/1.1, yaw 31/2.5; B1 partial), the
   B2 authored-lock block + regeneration, L4-13 not reproducible + the
   defense-in-depth blocker, jam-damage intended, magic-door continuous, the
   B0 load-claim retraction/FPS host caveat, the roof-probe rebase, and the
   stale `weather_profile.gd` comments. `docs/HANDOFF_NEXT_AGENT.md` — the new
   HEAD, the gate numbers and the open list. `README.md` only if a user-facing
   command/status changed (none did).
6. **Re-run the complete gate set serially at merged HEAD.** The floors for
   this wave: compile 164/0, `run_tests` 308/0, M2 12/0, E2E 278/278 (tier 1
   117/117), the five probes + `probe_collision_authored` + `test_roof_collision`
   (53/0 both modes) + the five W9-P2 suites (101–105), clean `probe_leak`,
   `make audit`, `make texture-cap-check`, `test_perf_guard.sh`, `make
   gate-ratchet`. A silent drop is a regression.
7. **`make gate-ratchet` passes on the R8 logs** (P0's floors). Raising it to
   the new counts (164/308) is P0's job and needs re-stamped logs; do not lower
   a floor.
8. **Force-add the evidence** (`build/qa/*.md` and the patch are gitignored):
   `p2-report.md`, `audit-b0..b3.md`, `re-b1-exposure.md`, `facts-b0..b3.md`,
   `b0-impl.md`, `b2-impl.md`, `b3-impl.md`, `b2-producer-contract.md`,
   `parse_tables-lock-fields.patch`. The PNGs/logs stay ignored; copy them out
   of the worktree if the pixels are wanted.
9. **Nothing here changes a preset, ambient, authored light energy or combat
   balance.** The only shipped visual change is the removed near foyer fill;
   the only shipped behaviour changes are the ESC guard, the lock rule, the
   labelled lockpick stand-in and the Den blocker. `weather_profile.gd` is
   byte-identical to `c2a1cd8`.
