# P4.4/P4.5 — landscape visibility mask + authored beam terms (2026-11-27)

**Status: headless only.** No GPU / Vulkan / Xvfb / Steam, no data regeneration,
no `make normalize`. The GPU raw-mask A/B and the KF27-framed capture are the
integrator's steps and have **not** been run here. This report carries no pixel
or visual-parity claim.

- **Branch:** `p4-landscape-beam` (worktree
  `/home/john/.local/share/opencode/worktree/318f41/phase1-p4-landscape-beam`),
  based on `main` `a1c3597`; not pushed.
- **Scope:** `game/src/core/tat_landscape.gdshader`,
  `game/src/core/tat_beam.gdshader`, `game/src/core/level_loader.gd`,
  `game/tests/probe_p1_beams.gd`, new `game/tests/probe_landscape_mask.gd`,
  `build/qa/p0b_capture.gd`, `build/qa/p0b_roi_stats.py`,
  `build/qa/p0b_live_capture.sh`, new `build/qa/kf27_beam_reference.json`,
  `docs/FIDELITY_GAPS.md`, `docs/HANDOFF_NEXT_AGENT.md`, this report.
- **Untouched by design:** exposure/IBL, mirrors, audio, GC, navmesh, UI, the
  scorecard, the extractor and every generated file under `game/data/`.

---

## 1. P4.4 — landscape visibility mask

### 1.1 What changed

| Item | Before | After |
|---|---|---|
| Mask rule | `vis > 0.5` discard, `discard_holes=1.0` always | same rule, now selected by `TAT2_LANDSCAPE_MASK` |
| Diagnostics | none | `TAT2_LANDSCAPE_MASK=discard\|raw\|off`; one `LANDSCAPE_MASK` line per landscape component |
| `raw` | n/a | samples the mask, **no discard**, and renders the raw mask red (hole, `vis>0.5`) / green (visible) for the A/B |
| `off` | n/a | `sample_mask=0`, `discard_holes=0`: the mask is not read at all (control) |
| Data assertion | prose only | `game/tests/probe_landscape_mask.gd` (7 checks): safe-room gap + synthetic 50/50 + loader binding |
| Docs | stale `discard_holes=0` Guildhall rule | corrected to the shipped discard rule + the data assertion; **`vis > 0.5` is not flipped** |

An unknown/empty `TAT2_LANDSCAPE_MASK` value falls back to `discard` (with a
warning), so a typo can never turn authored holes into solid terrain. The shader
defaults are the shipped `discard` path, so a material built without the loader
(tests, VFX) keeps the authored behaviour.

Per-component log (printed for every weighted landscape component, 18 Guildhall
/ 128 OldManor / 64 startscreen):

```
LANDSCAPE_MASK src=Guildhall/Guildhall_Landscape comp=(105.10,10.70,-31.10) wm=Weightmap_20.png mode=discard mask=absent tex=-1 ch=-1 sample=1 discard=1 raw=0
LANDSCAPE_MASK src=Guildhall/Guildhall_Landscape comp=(19.10,27.00,-88.60) wm=Weightmap_6.png mode=discard mask=present tex=0 ch=1 sample=1 discard=1 raw=0
```

`TAT2_LANDSCAPE_MASK_STATS=1` additionally appends a stride-16
`samples/hole_frac/min/max/mean`; it is opt-in because a per-texel scan on
every one of the 128 OldManor components would tax the load path. The probe
does the precise scan for the components it asserts.

### 1.2 The safe-room data assertion (the important number)

The old doc claim was “Guildhall sets `discard_holes=0` because the safe-room
gap has no lower-floor mesh”. That is stale: the loader has discarded authored
holes for every component since the 27 m elevated-shell fix. The question the
data must answer is **why the gap is still visible**.

`probe_landscape_mask` resolves the gap world points `(126.0, -10.43)` and
`(114.5, -3.2)` against the authored landscape tiles (quads=63, scale=100 →
63 m per tile, the same maths as `_build_one_landscape`, not the generic 40 m
clamp):

```
LANDSCAPE_MASK OK safe-room gap comp=12 (105.1,10.7,-31.1) wm=Weightmap_20.png mask=absent resolved=0.0 <0.5 visible=true (points (126.0, 18.56, -10.43) / (114.5, 18.56, -3.2))
```

- Both points are on Guildhall landscape component **12** (`Weightmap_20`).
- That component has **no** `LandscapeVisibilityLayerInfo` layer, so the shader
  fail-safe `vis = 0.0` applies and `0.0 < 0.5` → **visible**, no discard.
- Control component **0** (`Weightmap_6`, visibility channel 1) has real 1.0
  holes: **58 / 64** sampled at stride 8, max 1.000. The discard rule is not
  vacuous and the mask data is real.
- Guildhall has **10 masked / 8 unmasked** components; the gap is on an
  unmasked one.

The synthetic 50/50 negative control (left half `vis=1` hole, right half `vis=0`
visible) counts exactly:

```
LANDSCAPE_MASK OK synthetic 50/50 mask samples=4096 holes=2048 frac=0.500 stride2=512/1024 channel0_holes=0
```

The colour channel (0) is the negative control: 0 holes. This proves the
channel -> `vis > 0.5` decision, not a renderer.

**What this does and does not prove.** It proves the *data* is consistent with
the shipped rule at the safe-room gap and that the rule has real authored holes
to act on. It does **not** prove the pixel convention matches UE (that needs
the GPU raw-mask A/B) and it does not flip anything.

### 1.3 Docs corrected

- `docs/FIDELITY_GAPS.md`: the beam status, the “Mirrors / landscape carried”
  bullet (split into mirrors + landscape), the W10 “no change” note, and the A5
  `discard_holes=0` sentence now state the shipped discard rule and the data
  assertion; the raw-mask pixel A/B is still marked pending.
- `docs/HANDOFF_NEXT_AGENT.md` §4.2: landscape and beam bullets updated to the
  P4.4/P4.5 state.
- The historical 2026-11-16 entries are left as recorded history.

---

## 2. P4.5 — authored beam terms

### 2.1 Term-by-term status

Source row: `materials.json` `/Game/Gameplay/Traps/Detectors/LightBeam/MI_LightBeam_SM`
(`params`), itself from `MI_LightBeam_SM.json`. Every value below is read from
the row; the loader fallbacks are the same authored values and the shader
defaults are the authored values. **No literal drives a visible term.**

| Authored term | Value | Status | Where / why |
|---|---:|---|---|
| `EmissiveMultiplier` | 3.0 | consumed (unchanged) | HDR multiplier |
| `Center Line Thickness` | 0.015 m | consumed (unchanged) | 1.5 cm centre line |
| `Center Line Opacity` | 0.5 | consumed (unchanged) | line alpha |
| `Center Line Falloff` | 0.25 | consumed (unchanged) | line edge |
| `Fake Glow Opacity` | 0.06 | consumed (unchanged) | glow peak |
| `Fake Glow Center Width` | 0.085 m | consumed (unchanged) | 8.5 cm glow radius |
| **`Fake Glow Center Power`** | **2.0** | **implemented (new)** | exponent of the tight 2 cm core |
| **`Fake Glow Thickness`** | **0.02 m** | **implemented (new)** | core full thickness (1 cm radius) |
| `Fake Glow Power` | 1.1 | consumed (unchanged) | 8.5 cm glow falloff |
| `Fake Glow Side Width` | 1.0 m | **exposed, inert (documented)** | wide side lobe; the authored material masks it with `T_Noise2`/`T_Noise_01`, which the port does not sample. A bare 1 m lobe at 6 % is the broad cream slab P1 removed, so it waits for a noise-mask lane. |
| `Center Line Sphere Mask Radius` | 1.0 m | **exposed, inert (documented)** | no authored sphere centre/space is serialized; a camera/emitter/midpoint choice would be invented |
| `Sphere Mask Opacity` | 0.25 | **exposed, inert (documented)** | same reason |
| `Sphere Mask Power` | 2.0 | **exposed, inert (documented)** | same reason |
| `EdgeFadePower` | 0.5 | **exposed, inert (documented)** | the centre-line model has no visible card silhouette; a radial edge term would double-count `Fake Glow Power` |
| `FadeDistance` | 25.0 m | consumed (unchanged) | last-quarter fade |

**Why the 2 cm core, not a wider glow.** The authored core is 2 cm
(`Fake Glow Thickness`), the centre glow is 8.5 cm, and the KF27 reference glow
is ~1.86 %/2.57 % of frame at ±1 % — the existing 8.5 cm falloff already matches
it. Replacing that falloff with the 2.0 centre power would shrink the visible
glow to ~3.4 cm and likely make the port too thin against KF27. The implemented
model keeps the authored 8.5 cm profile and adds the authored 2 cm core:

```glsl
core_radius    = fake_glow_thickness * 0.5;
center_radius  = fake_glow_center_width;
body           = pow(clamp(1 - r / center_radius, 0, 1), fake_glow_power);
core           = pow(clamp(1 - r / core_radius,   0, 1), fake_glow_center_power);
glow           = fake_glow_opacity * min(body + core, 1.0);
```

The `min(..., 1.0)` preserves the authored peak opacity (the core can never
exceed `Fake Glow Opacity`). This is a `PORT_APPROX` reconstruction: the exact
UE graph is not in the dump, so the report labels the combination rule, not the
authored parameters (which are exact).

### 2.2 Probe output

`game/tests/probe_p1_beams.gd` now has 9 checks (was 7):

- every one of the **15** authored scalars is consumed from `materials.json`
  (`consumed=15/15`, no missing/mismatched; fails if the producer drops one or
  the loader stops reading it);
- the new uniforms exist and match the authored row;
- the ambiguous side/sphere/edge groups are documented as exposed-but-inert and
  are **not** used in the fragment math;
- the profile evaluates the same maths as the shader, including the glow-only
  core checks (the 1.5 cm centre line would mask the core in the full-alpha
  profile);
- the corrected KF27 contract and the capture/ROI wiring.

Measured on this tree:

```
P1_BEAMS OK shader render_mode=unshaded+blend_add+cull_disabled authored_defaults=true radial=true ambiguous_documented=true inert=true
P1_BEAMS OK loader MI_LightBeam_SM shader=tat_beam.gdshader color=(5.0000,4.3813,3.5156,0.50) emissive=3.0 line=0.015m a=0.50 falloff=0.25 glow=0.06/0.085m core=0.020m cp=2.0 p=1.1 side=1.00m sphere=1.0/0.25/2.0 edge=0.50 fade=25m axis=0
P1_BEAMS OK authored MI_LightBeam_SM row matches the port params (BaseColor=[5.0, 4.3813, 3.5156, 0.5], line=0.015, glow=0.06, fade=25, additive/two-sided/unlit)
P1_BEAMS OK authored beam terms consumed=15/15 missing=[] mismatched=[]
P1_BEAMS OK geometry col2 axis=(-0.0, 0.0, 1.0) len=42.0m cards=330 max_axis_err_deg=0.000005 max_len_err=0.0000057 card_aabb=(0.100,1.000,1.000)
P1_BEAMS OK profile center=0.560 half=0.308 1cm=0.052 25cm=0.0000 shell=0.0000 fade@8=0.560 @20=0.502 @25=0.0000 core=(0=0.060 plateau=0.060 edge=0.052 cp4=0.054 thick2x=0.060)
P1_BEAMS OK KF27 contract emitter=(17.8,40.0) bands=1 row=(40.0,40.5) foyer_beam=[27.0, 29.67, -55.0] lounge_extra=beam_close ref=true capture=true roi=true
P1_BEAMS OK foyer records emitter_instances=15 (5 base+bulb+lens x3) vitrine=5 statue=1 armchair=1 ottoman=1 rug=2 plaques=2 cyan_node=true at (28.8973, 30.4025, -58.002)
P1_BEAMS OK dressing bulb=true node=true stats={ "emitter_bulbs": 1, "node_items": 1, "node_created": 0, "plaque_labels": 2, "floor_plate": 1, "floor_plate_approx": 1 } labels=["Basement\nStairs", "WC"] plate=true approx=true
P1_BEAMS PASS checks=9 fails=0
```

### 2.3 KF27 contract and pose table

New tracked reference: `build/qa/kf27_beam_reference.json` — the single
measured contract consumed by the ROI scorer and asserted by the headless
probe:

```json
"emitter_pct": {"x": 17.8, "y": 40.0},
"beam_bands": 1,
"beam_band_row_pct": [40.0, 40.5],
"core_sat_p95": 35,
"cream_outside_band_pct": 0.12
```

with tolerances emitter ±2 %, row band [40.0, 40.5], core sat p95 ≤ 60,
cream outside band ≤ 2 %. The reference image itself scores **9/9** under the
new criteria:

```
P0B_KF27_REF pose=foyer_beam met=9/9 emitter_box=true emitter_at_kf27=true beam_row_band=true one_band=true row_excess_ge_2=true glow_falloff=true core_neutral=true no_cream_slab_10pct=true cream_reference_like_2pct=true
```

Changes:

- `build/qa/p0b_capture.gd`: added the KF27 `foyer_beam` cue
  `(27,29.67,-55) → (23.27,29.76,-57.4)`, beat `S24`, ref `KF27`; `beam_close`
  is now `ref=EXTRA`, `beat=""`, note “Lounge C_57 extra (not KF27/S24)”. The
  self-test is now 23 checks (7 pose ids + the cue/extra assertions).
- `build/qa/p0b_roi_stats.py`: `POSE_IDS`/`POSE_REFS` include `foyer_beam`;
  `POSE_EXTRAS={"beam_close"}`; `kf27_applies` excludes extras and prints
  `P0B_EXTRA pose=beam_close extra=true kf27_applies=false`; the criteria use
  the JSON and add `emitter_at_kf27` + `one_band`; `beam_rows` reports
  `bands`. The stale “two crisp beams / 39-40 %” comments are corrected.
- `build/qa/p0b_live_capture.sh`: the scrub template now has `foyer_beam` and
  labels `beam_close` as the Lounge C_57 extra, not the foyer beam.
- The scorecard and the 120-row tally are **not** edited.

The old `upper_foyer` numbers (peak row 49.07 %, excess 131.15, 12
cream-unexplained cells) remain the last measured port frame; this lane did not
re-score them because no GPU capture was run.

---

## 3. Headless gates run

| Gate | Command | Result |
|---|---|---|
| compile | `tools/godot --headless --path game --script tools/check_scripts_compile.gd` | **218 checked, 0 broken** (217 + the new probe) |
| unit suites | `make test` | `SUMMARY: fails=0` |
| M2 player | `res://tests/test_m2_player.gd` | `M2_SUMMARY: fails=0` (12) |
| leak | `TAT2_NO_DEN_PROBE=1 res://probe_leak.gd` | exit 0 (documented 7-texture warning path) |
| E2E p2 | `res://tests/e2e/run_e2e_tests.gd -- --tier=p2` | `P2_SUMMARY: expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0` |
| beam probe | `res://tests/probe_p1_beams.gd` | `P1_BEAMS PASS checks=9 fails=0` |
| landscape probe | `res://tests/probe_landscape_mask.gd` | `LANDSCAPE_MASK_SUMMARY: PASS fails=0 checks=7` |
| capture self-test | `P0B_EVIDENCE_DIR=/tmp/opencode/p4-selftest build/qa/p0b_capture.sh --self-test` | `P0B_SELFTEST PASS checks=23 fails=0` |
| ROI script | `python3 build/qa/p0b_roi_stats.py --reference-only --pose foyer_beam` | 9/9; `beam_close` prints `P0B_EXTRA` |
| manifest validator | `python3 build/qa/p0b_roi_stats.py --validate-manifest docs/reports/logs/p0b/dry-run/manifest.json` | exit 0 (6-pose historical manifest still valid) |

Blocked / not run in this lane:

- `make audit` reaches the content gates cleanly but fails on **tool version
  drift**: `vgmstream: 'vgmstream CLI decoder r2168 (Oct 25 2026)' -> 'missing'`
  in this worktree. That is an environment stamp issue, not a content or code
  finding; the integrator must re-run it on the main checkout.
- `build/qa/runtime_smoke.sh` was **not run**: the shared Godot lock was held by
  sibling Phase-2 lanes for the whole window (one Godot at a time rule). The
  integrator's full gate set covers it.
- The full 45-gate runner is the integrator's; it must add
  `probe_landscape_mask` (and will see compile 217 → 218).

---

## 4. GPU commands for the integrator (not run here)

All commands are one Godot at a time under the shared lock / Xvfb Vulkan; the
lane ran none of them.

```bash
# 1. Landscape raw-mask A/B at the safe-room gap (the A/B the docs still owe).
TAT2_LANDSCAPE_MASK=discard build/qa/p0b_capture.sh --poses=upper_foyer --tag=landscape_discard
TAT2_LANDSCAPE_MASK=raw     build/qa/p0b_capture.sh --poses=upper_foyer --tag=landscape_raw
TAT2_LANDSCAPE_MASK=off     build/qa/p0b_capture.sh --poses=upper_foyer --tag=landscape_off
# Compare the three frames at the same pose; raw shows red=hole, green=visible.
# A safe-room-gap close pose is not in the current table; add one only with an
# authored eye/target and record it as a new cue.

# 2. The KF27-framed beam capture (the pose this lane added).
build/qa/p0b_capture.sh --poses=foyer_beam --tag=kf27_foyer_beam
build/qa/p0b_roi_stats.py --port build/qa/p0b/captures/kf27_foyer_beam/foyer_beam.png --pose foyer_beam
# Acceptance: one_band=true, beam_row_band=true (40.0-40.5), emitter_at_kf27=true,
# cream_reference_like_2pct=true; record the peaks/row and the 16x9 cell map.

# 3. Beam card on/off A/B at the same foyer_beam pose (optional but useful).
build/qa/p0b_capture.sh --poses=foyer_beam --beam-card=off --tag=kf27_foyer_beam_nobeam
build/qa/p0b_roi_stats.py --port build/qa/p0b/captures/kf27_foyer_beam_nobeam/foyer_beam.png --pose foyer_beam

# 4. Lounge extra, luma only (never KF27 criteria).
build/qa/p0b_capture.sh --poses=beam_close --tag=lounge_extra
build/qa/p0b_roi_stats.py --port build/qa/p0b/captures/lounge_extra/beam_close.png --pose beam_close
# Expect P0B_EXTRA pose=beam_close ... kf27_applies=false.
```

The raw-mask A/B should be compared with the **same camera pose and exposure**;
the `raw` mode is a debug albedo, not a grading target.

---

## 5. Risks / open items

1. **UV / mask resolution.** The Guildhall weightmaps are 64×64 (native, not an
   import cap). The probe's control scan is stride 8 (64 samples); the
   production `LANDSCAPE_MASK_STATS` path is stride 16 and opt-in. A future
   weightmap-resolution change moves the coverage numbers but not the
   `vis > 0.5` rule.
2. **The `raw` A/B is a debug view.** It overrides `ALBEDO` with red/green; it
   is not an authored material and must not be left on in a scored capture.
3. **Beam term ambiguity is real and documented.** `Fake Glow Side Width`, the
   sphere-mask trio and `EdgeFadePower` are exposed uniforms with the authored
   values but no shader effect: the UE material graph is not in the export, no
   sphere centre is serialized, and the 1 m side lobe without its authored noise
   mask is the cream slab P1 fixed. Do **not** “finish” them with invented maths;
   the next step is a producer/graph recovery or a noise-mask lane.
4. **The fake-glow core is subtle by design.** It is a 2 cm plateau under the
   1.5 cm centre line; the visual delta at KF27 is expected to be small. The
   large gap (49 % row, 131 excess, 12 cream cells) is not claimed fixed.
5. **Pose identity.** `foyer_beam` is a fixed camera pose at the KF27 cue
   `(27,29.67,-55) → (23.27,29.76,-57.4)`; the KF27 reference is a hand-held
   frame, so the scoring is approximate framing, not pixel registration.
   `beam_close` is the Lounge C_57 extra (3.4 m from the card), never a
   KF27/S24 frame.
6. **The old 6-pose manifests** remain valid; new captures produce 7 poses
   (plus the artifact `_nobeam` naming when the card is hidden). The validator
   accepts both.

---

## 6. Files changed

```
build/qa/kf27_beam_reference.json      (new)  one measured KF27 contract
build/qa/p0b_capture.gd                      foyer_beam cue; beam_close = EXTRA; self-test 23
build/qa/p0b_live_capture.sh                 scrub template: foyer_beam + Lounge extra label
build/qa/p0b_roi_stats.py                    JSON criteria, one_band/emitter_at_kf27, POSE_EXTRAS
game/src/core/level_loader.gd                landscape mask modes/log/stats; 7 beam terms
game/src/core/tat_beam.gdshader              core + exposed/inert terms
game/src/core/tat_landscape.gdshader         sample_mask/mask_raw_view
game/tests/probe_p1_beams.gd                 9 checks: consumption, core, KF27 contract
game/tests/probe_landscape_mask.gd     (new) 7 checks: modes, 50/50, gap data, binding
docs/FIDELITY_GAPS.md                        landscape data assertion; beam P4.5 status
docs/HANDOFF_NEXT_AGENT.md §4.2              landscape/beam handoff
docs/reports/p4-landscape-beam-20261127.md   this report
```

Commit message:

```
feat(p4): landscape mask A/B + authored beam core (P4.4/P4.5)

- TAT2_LANDSCAPE_MASK=discard|raw|off + per-component LANDSCAPE_MASK log;
  probe_landscape_mask proves the safe-room gap is on Weightmap_20 with no
  visibility layer (mask 0.0 < 0.5 -> visible) and a synthetic 50/50 mask.
- Beam: consume all 15 authored scalars (probe fails on drift), implement the
  2 cm fake-glow core (Fake Glow Thickness + Center Power); expose the side /
  sphere-mask / EdgeFadePower terms as authored-but-inert (no serialized
  centre, no noise mask).
- KF27 contract: one band 40.0-40.5 %, emitter 17.8 %/40.0 %; add the
  foyer_beam cue; beam_close is the Lounge C_57 extra. Headless only; GPU
  raw-mask A/B and KF27 capture pending.
```
