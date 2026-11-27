# P4.4/P4.5 lane verification — independent read-only audit (2026-11-27)

**Verdict: PASS (substance).** The landscape mask modes + safe-room data
assertion, the 15/15 authored beam terms, the 2 cm fake-glow core, the inert
side/sphere/edge terms, the KF27 9/9 contract, the `foyer_beam` cue and the
`beam_close` extra all hold under independent re-derivation. The final gate
runner will **not** go green on a merge without the four wiring edits in §4
below (three stale markers + the new landscape gate); those are integration
work the lane defers, not code defects. Non-blocking report corrections are in
§5.

- **Subject:** worktree
  `/home/john/.local/share/opencode/worktree/318f41/phase1-p4-landscape-beam`,
  branch `p4-landscape-beam`, commit `821a0ce` (base `a1c3597`, one commit,
  clean tree before this file). `main` has since moved to `7de2f0c`
  (license/org-only commits); no code conflict with this branch.
- **Plan read:** `docs/reports/next-phases-plan-20261127.md` §4 (P4.4/P4.5,
  lines 157–165). **Lane report read:**
  `docs/reports/p4-landscape-beam-20261127.md`.
- **Method:** read-only. Code/diff/doc review, data re-derivation in Python,
  the real ROI scorer (`p0b_roi_stats.py`) and manifest validator,
  `make audit`, `make gate-ratchet`, `gdparse` 4.5.0, and the lane's preserved
  run artifacts. **No Godot, no GPU/Xvfb, no Steam, no data regeneration.**
  The lane's instruction forbade running Godot, so the three gates with no
  preserved log (M2, leak, p2) and the "0 broken" half of compile are
  lane-reported only — see §3.4. No file other than this one was written.

---

## 1. P4.4 — landscape visibility mask

### 1.1 Modes (verified in code + the probe log)

`game/src/core/level_loader.gd:7538-7568` (`landscape_mask_mode`,
`landscape_mask_params`, `landscape_mask_hole`) and
`game/src/core/tat_landscape.gdshader:41-43,95,127-128,170-177`.

| Mode | sample_mask | discard_holes | mask_raw_view | Shader effect | Verified |
|---|---:|---:|---:|---|---|
| `discard` (default) | 1 | 1 | 0 | samples, `discard` when `vis > 0.5` | code + log |
| `raw` | 1 | 0 | 1 | samples, paints red `>=0.5` / green | code + log |
| `off` | 0 | 0 | 0 | no mask read, no discard | code + log |
| unknown/empty | — | — | — | falls back to `discard` (warning on unknown) | code + log `WARNING: LANDSCAPE_MASK unknown mode 'bogus'` |

The authored rule is unchanged (`vis > 0.5` = hole; the old loader also set
`discard_holes=1`, so the docs' old "Guildhall sets 0" claim was stale —
confirmed in the parent commit's source). The shader defaults
(`sample_mask=1`, `discard_holes=1`, `mask_raw_view=0`) reproduce the shipped
path for a material built without the loader.

Probe evidence (`/tmp/opencode/p4_landscape_probe.log`, 11:50):

```
LANDSCAPE_MASK OK modes default=discard ... raw={sample_mask:1, discard_holes:0, mask_raw_view:1} off={0,0,0} rule=vis>0.5
LANDSCAPE_MASK OK synthetic 50/50 mask samples=4096 holes=2048 frac=0.500 stride2=512/1024 channel0_holes=0
LANDSCAPE_MASK OK safe-room gap comp=12 (105.1,10.7,-31.1) wm=Weightmap_20.png mask=absent resolved=0.0 <0.5 visible=true
LANDSCAPE_MASK OK control comp=0 (19.1,27.0,-88.6) mask present ch=1 samples=64 holes=58 frac=0.906 max=1.000
LANDSCAPE_MASK OK Guildhall components=18 masked=10 unmasked=8
LANDSCAPE_MASK OK loader binding masked[discard=true, raw=true, off=true] gap_comp12=true
LANDSCAPE_MASK_SUMMARY: PASS fails=0 checks=7
```

The probe's 7 checks are exactly the 7 successful `_check()` calls
(`probe_landscape_mask.gd:150,162,182,217,249,254,306`); the other two
`_check(false, ...)` calls are missing-JSON error paths, not extra checks.

### 1.2 Safe-room data assertion — independently re-derived

I re-ran the geometry/JSON test in Python against
`game/data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json`
(same `quads * |scale| * 0.01` maths as `_build_one_landscape`, not the 40 m
clamp):

- components containing **both** points `(126.0, -10.43)` and `(114.5, -3.2)`:
  **exactly 1** — index **12**, origin `(105.1, 10.7, -31.1)`,
  `Weightmap_20.png`.
- component 12's layers: `GroundA/CobbleA/GrassA/Puddle` — **no**
  `LandscapeVisibilityLayerInfo`; so the shader's fail-safe `vis=0.0` applies,
  `0.0 < 0.5` → **visible**, no discard. The gap is therefore not hidden by
  the mask; the authored surface fills it.
- census: **18 components, 10 masked, 8 unmasked** (matches the report).
- control component 0: `Weightmap_6.png`, visibility **channel 1**, real
  1.0 holes. The probe's 58/64 (stride 8) is measured on Godot's imported
  **BC-compressed** texture (`.import` `compress/mode=2`), which is the runtime
  truth. A source-PNG scan gives 57/64 — a one-sample block-decode difference;
  the conclusion (real authored holes, ~90 %, max 1.0) is unaffected.

Caveats: the assertion is an XZ-AABB + layer-presence test (it does not sample
the UV at the gap), and it pins component index 12. Both are honest as a data
assertion; the report's "What this does and does not prove" already says the
pixel convention still needs the GPU A/B.

### 1.3 Component-index pinning / log volume (notes, not defects)

- `comp_idx == 12` (`probe_landscape_mask.gd:215`) would fail if a future data
  regen reorders components. That is a re-measure signal, not silent drift.
- `_landscape_weighted_material` now `print()`s one `LANDSCAPE_MASK` line per
  weighted component unconditionally. The 12:04 `run_tests` log contains
  **279** such lines; no gate scans stdout prints, but it is new log volume.
- `raw` uses `step(0.5, vis)` (red at exactly 0.5) while the rule is
  `vis > 0.5`; an 8-bit mask cannot encode exactly 0.5, so no practical
  divergence.

---

## 2. P4.5 — authored beam terms

### 2.1 15/15 terms — re-derived from `materials.json`

Row `/Game/Gameplay/Traps/Detectors/LightBeam/MI_LightBeam_SM` `.params`
(16 entries; `RefractionDepthBias` is the only non-beam scalar and is
correctly excluded). Every one of the 15 is bound by
`level_loader.gd:1502-1517` from the row with the same authored fallback:

| Term | Row | Loader/material | Result |
|---|---:|---:|---|
| EmissiveMultiplier | 3.0 | 3.0 | match |
| Center Line Thickness | 0.015 | 0.015 | match |
| Center Line Opacity | 0.5 | 0.5 | match |
| Center Line Falloff | 0.25 | 0.25 | match |
| Fake Glow Opacity | 0.06 | 0.06 | match |
| Fake Glow Thickness | 0.02 | 0.02 | match |
| Fake Glow Center Width | 0.085 | 0.085 | match |
| Fake Glow Center Power | 2.0 | 2.0 | match |
| Fake Glow Power | 1.1 | 1.1 | match |
| Fake Glow Side Width | 1.0 | 1.0 | bound, inert |
| Center Line Sphere Mask Radius | 1.0 | 1.0 | bound, inert |
| Sphere Mask Opacity | 0.25 | 0.25 | bound, inert |
| Sphere Mask Power | 2.0 | 2.0 | bound, inert |
| EdgeFadePower | 0.5 | 0.5 | bound, inert |
| FadeDistance | 25.0 | 25.0 | match |

The probe maps each term to the material value and fails on a missing or
mismatched one (`probe_p1_beams.gd:237-280`); its log says
`consumed=15/15 missing=[] mismatched=[]`. `BaseColor` is read from
`vectors.BaseColor` (`5.0, 4.381316, 3.515625, 0.5`) and asserted to 1e-4.

### 2.2 2 cm core — implemented, with an honest approximation

`tat_beam.gdshader:93-99`:

```glsl
core_radius = max(fake_glow_thickness * 0.5, 0.0001);   // 0.01 m
body        = pow(clamp(1 - r / 0.085, 0, 1), 1.1);
core        = pow(clamp(1 - r / core_radius, 0, 1), 2.0);
glow        = 0.06 * min(body + core, 1.0);
```

Independent recomputation from the row: `glow(0)=0.060`, `glow(5 mm)=0.060`,
`glow(10 mm)=0.05228`, `glow(20 mm)=0.04467`, `glow(85 mm)=0`. The clamp keeps
the authored 6 % peak (the core cannot brighten past it). Consequence to note:
the **additive saturation plateau is ~1.40 cm full width** (radius ~0.0070 m),
not 2 cm — the authored 2 cm is the *thickness parameter*; the extra core only
lifts a thin shell below the 1.5 cm centre line. The report calls it a
"2 cm plateau" in §5.4; that wording is imprecise, the implementation is
correct and labelled `PORT_APPROX`. The probe pins the core: without it the
plateau sample would be 0.0561, failing the `0.060 ± 0.0001` check.

### 2.3 Side / sphere / edge terms are genuinely inert

- The four uniforms are declared in `tat_beam.gdshader:53,58-61` and the
  header explains each (lines 14-29). There is **no** arithmetic use anywhere
  in the file (I read the whole 111-line shader; the probe's
  `fake_glow_side_width *` / `center_line_sphere_mask_radius *` /
  `sphere_mask_opacity *` / `sphere_mask_power *` / `edge_fade_power *` greps
  are a subset guard, not the proof).
- The rationale checks out against the export: the MI dump has only scalar
  parameter values (no sphere centre), the parent `M_LightBeam_SM.json` has no
  `MaterialExpression` nodes (6.9 KB, graph absent), and the MI's
  `TextureStreamingData` names **T_Noise2 / T_Noise_01**, i.e. the side lobe
  really is noise-masked in the authored material. Leaving the 1 m lobe off
  avoids restoring the P1 cream slab.
- This is a **documented deviation from the plan's literal "implement the
  authored sphere-mask/edge terms"**: the lane implemented the fake-glow core
  and exposed the other two groups inert. Given AGENTS rule 10 (no invented
  maths) and the missing graph, the call is defensible and the report says so;
  it should be accepted or spun into a producer/noise-mask follow-up.

### 2.4 KF27 contract — independently reproduced (9/9)

`build/qa/kf27_beam_reference.json`: emitter **17.8/40.0**, **1** band,
**40.0–40.5 %**, core sat p95 ≤ 60, cream outside band ≤ 2 %. I ran the real
scorer on the tracked reference:

```
$ python3 build/qa/p0b_roi_stats.py --reference-only --pose foyer_beam \
    --port docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg --json
emitter x=17.670 y=40.168 found=True
peak_y_pct=40.185  bands=1  band_floor=4.0  excess=10.51
core_sat_p95=35  cream_outside_band=0.115 %
P0B_KF27_REF pose=foyer_beam met=9/9 emitter_box=true emitter_at_kf27=true
  beam_row_band=true one_band=true row_excess_ge_2=true glow_falloff=true
  core_neutral=true no_cream_slab_10pct=true cream_reference_like_2pct=true
```

The 9 criteria are exactly the 9 keys in `kf27_criteria`
(`p0b_roi_stats.py:435-450`). `upper_foyer` (the ratchet's pose) also prints
`met=9/9`. `beam_close` prints
`P0B_EXTRA pose=beam_close extra=true kf27_applies=false` and is excluded by
`POSE_EXTRAS` (`p0b_roi_stats.py:103,546-547`). The old "two crisp beams /
39–40 %" comments are gone; the new band is measured, not guessed.

Caveat: the probe asserts the measured *values* but **not** the `tolerance`
block; a JSON tolerance edit (e.g. cream 2.0 → 100) would loosen the scorer
without failing `probe_p1_beams`. Pinning 2.0/0.5/60/2.0 in
`_check_kf27_contract` would harden the gate. The unused
`tolerance.beam_row_pct` is dead config.

### 2.5 Cue and extra

- `foyer_beam` cue: eye `(27, 29.67, -55)` → target `(23.27, 29.76, -57.4)`,
  beat `S24`, ref `KF27` — present in `p0b_capture.gd:45,78-86`, the JSON, the
  live-capture template, and the 7-pose self-test manifest (`git.sha
  a1c3597…`, `dirty=true`, pre-commit; 7 poses, `foyer_beam S24/KF27`,
  `beam_close ""/EXTRA`).
- `beam_close` is `ref=EXTRA`, `beat=""`, note "Lounge C_57 extra (not
  KF27/S24)" (`p0b_capture.gd:102-110`); the self-test says so explicitly.
- `build/qa/p0b_capture.sh`'s header still says "all six poses" (7 now). The
  lane did not touch that file; stale comment only.

---

## 3. Gates — what is actually evidenced

### 3.1 Reproduced by me (no Godot)

| Gate | Evidence | Result |
|---|---|---|
| KF27 reference | `p0b_roi_stats.py --reference-only --pose foyer_beam --port <KF27.jpg>` | **9/9**, peak 40.185, bands 1, cream 0.115 % |
| KF27 reference, ratchet pose | same, `--pose upper_foyer` | **9/9** |
| `beam_close` extra | same, `--pose beam_close` | `P0B_EXTRA … kf27_applies=false` |
| manifest validator | `--validate-manifest docs/reports/logs/p0b/dry-run/manifest.json` | `P0B_MANIFEST_OK poses=6`, exit 0 |
| manifest validator (new shape) | `--validate-manifest build/qa/p0b/selftest/manifest.json` | `poses=7`, exit 0 |
| `make audit` | this worktree | **1 failure only**: vgmstream drift; all content gates OK; exit 2 |
| `make gate-ratchet` | this worktree (old committed logs) | PASS — but see §4.3 |
| `git diff --check` | `a1c3597..821a0ce` | clean |

The two `/tmp/opencode/p4_audit*.log` files showing **7** failures are **not**
from this worktree: they reference `tools/parse_cubemap.py` (absent here) and
`…/phase1-p4-exposure/game/data/generated/ibl`. This worktree's audit has
exactly the one vgmstream failure the report claims.

### 3.2 Preserved lane logs (real Godot runs, pre-commit)

| Gate | Log | Result |
|---|---|---|
| landscape probe | `/tmp/opencode/p4_landscape_probe.log` (11:50) | `checks=7 fails=0`, 7 OK lines |
| beam probe | `/tmp/opencode/p4_beams_probe.log` (11:50) | `checks=9 fails=0`, 9 OK lines |
| `make test` | `/tmp/opencode/p4_run_tests2.log` (12:04) | 324 PASS, `SUMMARY: fails=0`; 279 `LANDSCAPE_MASK` lines; all four landscape/guildhall PASS lines |
| capture self-test | `/tmp/opencode/p4-selftest/self-test/self-test.log` (11:43) | `checks=23 fails=0`, 23 `ok` lines |
| runtime smoke | `/tmp/opencode/p4_runtime_smoke.log` | **0 bytes** — consistent with "not run" |

Timing caveat: `probe_p1_beams.gd` was last edited 12:05 (after its 11:50 log)
and `level_loader.gd` 11:55 (after the landscape probe's 11:50 log). The logs'
9/7 labels and every printed value match the committed assertions, the final
`probe_p1_beams.gd` parses under `gdparse 4.5.0`, and the 12:04 `run_tests`
exercises the committed loader (post-11:55) including the mask prints and all
landscape assertions. This is strong, but it is not a byte-identical re-run of
the final probe files.

### 3.3 Compile count

- `check_scripts_compile.gd` counts every `.gd` under `res://` minus itself.
  This worktree has **218** `game/**/*.gd`; `main` at `a1c3597` has **217**;
  the delta is exactly `game/tests/probe_landscape_mask.gd`. So
  **"218 checked" is arithmetically verified**.
- **"0 broken" was not reproduced** (Godot forbidden). Evidence toward it:
  the new probe ran at 11:50; the probe p1 file parses (`gdparse`); the capture
  script parses (`gdparse`); the loader is loaded and exercised by the 12:04
  `run_tests` (324/0). No evidence contradicts "0 broken", but a fresh
  `compile.log` is owed by the integrator.

### 3.4 Lane-reported only (no preserved log; not re-run here)

| Gate | Report claim | Why I could not verify | Risk read |
|---|---|---|---|
| M2 player | `M2_SUMMARY: fails=0` (12) | no log; no Godot | no changed file on the player path — low |
| leak | exit 0, "7-texture warning path" | no log; no Godot | no new textures; masks stats `get_image()` is env-gated off — low. The parenthetical is confusing: with `TAT2_NO_DEN_PROBE=1` the 7-RID warning path should *not* run |
| E2E p2 | `expected_fail=0 expected_delta=0 fixed=0 unexpected_fail=0` | no log; no Godot | p2 checks only unchanged beam fields (BaseColor, EmissiveMultiplier, additive/two-sided/unlit, thickness/opacity/glow/fade) — low |

Full E2E (300) was not run by the lane either; a static scan of T1/T2/T3/T4
found no assertion the change invalidates (`T2-04-E` still expects
`discard_holes=1.0`; T1/T3/T4 still find the `0.04` puddle roughness;
`T2-04-C` still gets `tat_beam.gdshader`). The integrator's full run proves it.

---

## 4. Required integrator wiring (the branch breaks the current runner as-is)

### 4.1 Hard marker failures in the final runner

1. `build/qa/run_final_gates.sh:201-204` —
   `"P1_BEAMS PASS checks=7 fails=0"` → **`checks=9 fails=0`**.
2. `build/qa/run_final_gates.sh:342-344` —
   `"P0B_SELFTEST PASS checks=21 fails=0"` → **`checks=23 fails=0`**.
3. `build/qa/run_final_gates.sh:353-356` —
   `"P0B_KF27_REF pose=upper_foyer met=7/7"` → **`met=9/9`** (verified: the
   current scorer prints 9/9 for `upper_foyer`).
4. `tools/check_gate_ratchet.py:372-375` — the ratchet's committed-log marker
   is the same hard-coded **`met=7/7`**; it will fail once the final log is
   replaced. Update to `met=9/9`.

These four are mandatory; otherwise `run_final_gates.sh` stops at the beams
gate (after paying for the run) and `make gate-ratchet` fails on the KF27 log.

### 4.2 The new gate (46 total)

Add after the beams probe (with the existing style):

```bash
gate_marker probe_landscape_mask "$OUT/probe_landscape_mask.log" \
	"LANDSCAPE_MASK_SUMMARY: PASS fails=0 checks=7" \
	flock "$LOCK" tools/godot --headless --path game \
	--script res://tests/probe_landscape_mask.gd
```

and change the header's "45 gates" (`run_final_gates.sh:17`) to **46**.

### 4.3 Ratchet / docs re-stamp (after a real merged-HEAD run)

- `tools/gate_ratchet.json` — `compile.checked 217 → 218`,
  `run_tests.passes 324 → 326` (measure after the P4.1 exposure/IBL lane's
  suites 122/123 merge, on the merged HEAD — the 326 in `/tmp/opencode` came
  from that worktree, not this lane), `probe_p1_beams.checks 7 → 9`,
  `p0b_capture.poses 6 → 7`,
  add `probe_landscape_mask` to `evidence` + `gates` (**7**), and re-stamp
  `measured_on` / `report` / `source` from a real run.
- The report named by `gate_ratchet.json`
  (`docs/reports/final-20261127-phase0b.md`, lines 117/145 quote beams 7 and
  self-test 21) must quote the new compile/run_tests/M2/E2E/coverage numbers
  and `measured_on`, or point the JSON at the new wave report.
- `AGENTS.md` — lines 64/69 (324 checks, 45 gates), 85 (45-gate header),
  87 (217 compile), 88 (324), 90 (beams 7), 105 (poses 6, self-test 21,
  KF27 7/7), 490 (beams 7), 496 (45 gates). Add the landscape probe to the
  definition-of-done list.
- `docs/HANDOFF_NEXT_AGENT.md:116-117,355` and `README.md:19-20,59` —
  217/324 → 218/326 (user-facing status).
- Optional/historical: `build/qa/run_p0b_gates.sh:249,376,387` carry the same
  three stale markers; only update if that historical runner must stay
  runnable.

---

## 5. Non-blocking findings to fix in the integration commit

1. **Report §3 ROI command is not runnable as written.**
   `python3 build/qa/p0b_roi_stats.py --reference-only --pose foyer_beam` exits
   2 with `need --port and --pose` — the `--port` guard precedes the
   `--reference-only` branch (`p0b_roi_stats.py:893-898`). This is pre-existing
   tool behaviour, but the new report documents the failing form. Add
   `--port docs/reference/.../KF27_…jpg`; with it, 9/9 is correct.
2. **Report §4 item 3 points at the wrong PNG.** A `--beam-card=off` capture
   writes `<pose>_nobeam.png` (`p0b_capture.gd:778`), so the command must use
   `.../kf27_foyer_beam_nobeam/foyer_beam_nobeam.png`. The report's §5.6 knows
   about the suffix; §4 forgot it.
3. **Report §6 file list omits `.gitignore`** (4-line exception for the
   tracked `kf27_beam_reference.json`). The exception itself is correct and
   the file is tracked (`git check-ignore` exit 1).
4. **"2 cm plateau"** in §5.4 is imprecise: the *parameter* is 2 cm; the
   clamped additive plateau is ~1.40 cm full width (§2.2 above).
5. Probe header comment (`probe_landscape_mask.gd:24`) advertises
   `LANDSCAPE_MASK_SUMMARY: fails=0 checks=N components=18 …`; the code prints
   `…: PASS fails=0 checks=7 last=…`. A gate marker copied from the header
   would never match; use the actual line (as in §4.2).

### Gate-strength notes (no change required now)

- Probe pins the measured KF27 values, not the acceptance tolerances (§2.4).
- `one_band` uses `max(4.0, 25 % of peak)` as the band floor; a secondary band
  under 25 % of the main peak is not counted (`p0b_roi_stats.py:336-339`).
- The control scan is on the BC-imported weightmap (58/64) vs the source PNG
  (57/64); the gap assertion is mask-absent and unaffected.
- The `inert` grep only checks `uniform *`; today's shader has no use at all.
- The unconditional per-component print is ~210 lines per map load.

---

## 6. Scope, data, no-push, no-GPU

- **Scope:** 14 files — the three core sources, the two probes (+`.uid`),
  four `build/qa` files (three scripts + the new JSON), three docs, this lane's
  report, and `.gitignore`. No `game/data/`, `extracted/`, `game/assets/` or
  capture PNGs.
  `find game/data/generated -newermt 2026-11-27` = **0 files** — no data regen.
- **No push:** `p4-landscape-beam` has no upstream; no remote `p4*` ref exists.
  One commit on `a1c3597`; `git diff --check` clean.
- **No GPU/Steam:** no capture PNGs, no Xvfb/Steam processes; only the
  headless self-test artifacts (`build/qa/p0b/selftest`, gitignored) and
  `/tmp/opencode/…` logs.
- **Docs:** FIDELITY_GAPS/HANDOFF corrections are accurate (the old
  `discard_holes=0` A5 sentence is gone; the raw-mask A/B stays "pending"; no
  pixel/visual claim).

---

## 7. Verdict

**PASS** on P4.4/P4.5 substance:

- the three mask modes, the `vis > 0.5` rule, the unique component-12
  no-visibility-layer data assertion and the real 1.0-hole control all hold;
- all 15 authored beam scalars are consumed exactly; the 2 cm core is
  implemented and probe-sensitive; the side/sphere/edge terms are provably
  inert and honestly labelled;
- the KF27 contract is reproducible **9/9** (one band 40.0–40.5, emitter
  17.8/40.0 within tolerance), `foyer_beam` is the S24 cue, `beam_close` is the
  Lounge extra with no KF27 criteria;
- the probes are 7 and 9 checks, the self-test is 23, `make test` is 324/0 on
  the committed code, and `make audit` fails only on the vgmstream environment
  stamp — exactly as the report says.

**Do not merge-and-run without §4.1–4.2.** The four stale markers (three in
the final runner, one in the ratchet) and the missing landscape gate are the
only things between this branch and a green final set; §4.3 is the ratchet/docs
re-stamp the integrator owes anyway. The M2/leak/p2 and compile "0 broken"
claims are lane-reported only and should be re-proved by the integrator's full
run.
