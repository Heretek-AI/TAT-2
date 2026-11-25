# W9-P2 B1 — independent audit (foyer fills, room-grade candidate, revert)

Auditor: independent B1 subagent, not the implementer. Worktree
`/home/john/Projects/TAT-2-rem-w9-p2`, HEAD `b13260b` (P1 tip), P2 work
uncommitted in the tree. Read-only: the only file written is this one. No
commit, no producer, no `make normalize`.

Method: source reads, `git diff`/`git show`, `git status` before and after,
one full headless `res://tests/run_tests.gd` run, one GPU recapture of
`upper_foyer` under `flock /tmp/opencode/tat2-godot.lock` + `xvfb-run -a`
alone (wrapper `build/qa/w9_capture.sh`, its concurrent-process guard passed),
re-measurement with `python3 build/qa/w9_frame_stats.py`, `magick compare`,
parse of `build/qa/w9/logs/b1_sweep1.log`, and spot-checks of the cited
extracted JSON. The working tree did not change during the audit (same
`git status` list at 14:20 and 14:29; HEAD stayed `b13260b`).

Measured lines reproduced verbatim below.

---

## A. Final state is the fill removal only — AUDIT: PASS

1. `_add_guildhall_foyer_fills()` (`game/src/missions/mission_controller.gd:574-589`,
   called from `_setup_environment` at `:287`) has one spec:

   ```
   for spec: Array in [
       [Vector3(27.0, 31.0, -64.0), 1.3],
   ]:
   ```
   energy `1.3`, `omni_range 16.0`, attenuation 1.2, shadows off, registered
   with `light_probe`. The near `(27, 31, -53)` / 1.6 spec is absent; there is
   no other `GuildhallFoyerFill` creation site in `game/src` or `game/scenes`.

2. The room-grade code is gone from the game tree:

   ```
   $ grep -rn "FOYER_GRADE\|_tick_room_grade\|TAT2_ROOM_GRADE" game/src
   (no output)
   ```
   The only textual survivors are `build/qa/` harness/log files, the report,
   the fact sheet and the comment in `mission_controller.gd:570` that records
   the revert. A second sweep for `exposure_multiplier|CameraAttributes` in
   `game/src` and `game/scenes` is empty: no camera attribute resource is
   created or assigned anywhere in the game, so there is no dormant lever.
   `probe_room_grade.gd` is absent and nothing in `game/`, `Makefile` or
   `tools/` references it.

3. `weather_profile.gd` is byte-identical to `c2a1cd8`:

   ```
   $ git diff c2a1cd8 -- game/src/core/weather_profile.gd | wc -l
   0
   $ git diff b13260b -- game/src/core/weather_profile.gd | wc -l
   0
   ```

4. P2-only source diff (`git diff b13260b --stat -- game/src`) touches
   `level_loader.gd`, `lockable_door.gd`, `loot_container.gd`,
   `swinging_door.gd`, `mission_controller.gd`, `thief_character.gd`,
   `hud.gd`. The only line in that diff matching
   `light_energy|omni_range|ambient|tonemap|exposure` is the new B1 comment;
   no other lighting, preset or authored light value moved. B1 is the fill
   removal and nothing else.

Runtime confirmation of the removal: the auditor's capture logs
`PERF_CENSUS … lights=170` (the report's pre-change value was 171 — one fill
fewer) and the recapture reproduces the fill-only frame exactly (item B).

## B. Final captures — AUDIT: PASS (reproduced)

Command (alone; flock held by `w9_capture.sh`, `xvfb-run -a`, 1920×1080,
`TAT2_AO=on`):

```
$ TAT2_AO=on build/qa/w9_capture.sh upper_foyer audit_b1_upper 1920x1080
W9_CAPTURE_WALL mode=upper_foyer tag=audit_b1_upper ao=on exit=0 wall=37s
W9_ENV scene=upper_foyer ssao=true ssil=true tonemap=4 exposure=1.150 glow=true
W9_STAGE camera pos=(27.0, 29.67, -50.0) target=(27.0, 29.67, -60.0) fov=54.54
W9_CAPTURE file=audit_b1_upper size=1920x1080 err=0 mean601=45.99 pct_lt8=1.8 peak=255.0 nonblack=true ao=on
```

`python3 build/qa/w9_frame_stats.py` (L1 pipeline):

```
audit_b1_upper.png       129600px mean=45.7 p50=29 p95=182 lt8=1.1% lt16=6.7%
p2_fillonly_upper.png    129600px mean=45.7 p50=29 p95=182 lt8=1.1% lt16=6.7%
```

| metric | report | auditor recapture | tolerance | verdict |
|---|---:|---:|---|---|
| mean | 45.7 | **45.7** | ±1 | PASS |
| p50 | 29 | **29** | ±2 | PASS |
| p95 | 182 | **182** | (not specified) | PASS |
| %<8 | 1.1 | **1.1** | ±1 pt | PASS |

Frame-to-frame determinism is tight: `magick compare` between the report's
`p2_fillonly_upper.png` and the recapture is `RMSE 0.00100958` (0.101 %) /
`AE 481.9 px` (0.023 %). The report's other final rows are also true to the
stored PNGs, re-measured here:

```
p2_fillonly_foyer_sweep_yaw180.png  mean=38.9 p50=31 p95=99  lt8=2.5%
p2_fillonly_gate_gate_e115_a100_l100.png mean=23.2 p50=10 p95=66 lt8=23.9%
```

and the "before" row is the P1 capture, re-measured:
`b1bracket1_upper_foyer_e115_a100_l100.png` = **50.5 / 34 / 180 / 0.8**,
`b1bracket1_yaw180_…` = **40.5 / 31 / 105 / 2.3**. The gate row equals the P1
baseline `23.2 / 10 / 66 / 23.9` (`build/qa/w9/p1-report.md:51`).

**The band is not claimed and not met.** §0.1 says so in bold, §B1-1 is
verdict **PARTIAL** with the remaining gap, §"Open risks" item 1 repeats it,
and the integrator step 4/5 repeats it again. The slight black-floor
regression it implies (upper %<8 0.8 → 1.1, yaw180 2.3 → 2.5) is printed raw,
not hidden. The only numeric slip is the stated gap size (item G1).

## C. Candidate, pre-registered sweep, revert — AUDIT: PASS

**The candidate is evidenced, not asserted.** `build/qa/w9/logs/b1_sweep1.log`
line 118 contains the live camera multiplier it applied:

```
W9_SWEEP_CONTROL gate_on=23.86 gate_off=23.87 gate_ratio=0.9997 upper_on=32.96 upper_off=45.83 upper_ratio=0.7191 gate_mult=1.0000 upper_mult=0.4900
```

The reverted candidate's frames still exist and re-measure to the report's
numbers: `p2_after_upper_foyer.png` **33.0 / 14 / 178 / 15.3**,
`p2_after_foyer_sweep_yaw180.png` **27.1 / 15 / 91 / 17.7** — both inside the
13–15 / 9–24 reference band, as claimed. `room_grade_probe{,2}.log` record
`ROOM_GRADE PASS checks=17 fills=1 exposure=1.150 mult=0.452|0.490`; `fills=1`
shows the candidate sat on top of the fill removal.

**The sweep verdict is exactly what the report prints** (`b1_sweep1.log:283-292`):

```
W9_SWEEP_CRITERIA C1_ratio_step<=0.030 C2_grade_step<=2.0 C3_4_dir_tol=0.005 C5_rev_ratio<=0.03 C5_rev_scene<=0.03 C7_rmse<=1.00 C7_ae<=0.10 C8_upper=0.490 C8_mid=[0.70,0.79]
W9_SWEEP_CHECK C1 max_ratio_step=0.0323 FAIL
W9_SWEEP_CHECK C2 max_grade_step=1.2873 PASS
W9_SWEEP_CHECK C3 in_monotone=false at z=-43.50 d=+0.0063
W9_SWEEP_CHECK C4 out_monotone=false at z=-40.75 d=-0.0070
W9_SWEEP_CHECK C5 reversibility_ratio=0.0007 PASS scene_drift=0.0020 PASS
W9_SWEEP_CHECK C6 gate_mult=1.000000 PASS
W9_SWEEP_CHECK C7 bleed_rmse=0.1483 PASS bleed_ae=4.7577 FAIL
W9_SWEEP_CHECK C8 upper_mult=0.4900 mid_mult(z=-32)=0.7450 PASS
W9_SWEEP_VERDICT FAIL
```

The criteria constants in `build/qa/w9_room_grade_sweep.gd:44-52` are exactly
the §0.3 table (`0.030`, `2.0`, `0.005`, `0.03`, `0.03`, `1.0`, `0.1`,
`0.49`, `[0.70,0.79]`); the runtime `W9_SWEEP_CRITERIA` line is printed from
those same constants, so the log and the current harness cannot disagree. The
sweep ran once (`b1_sweep1`, 13:53:35 → 13:55:43 = **128 s**, 81 samples/leg
at 0.25 m, `_wait(3)` per on/off pair); there is no second sweep log or second
criteria line. The report states the criteria were written before the run and
that none was revised (§0.3 opening and closing paragraphs), and the failing
criteria are left failing.

**The feather derivation checks out arithmetically.** For
`w = 1 − smoothstep(0,4,d)`, `m = 1 − 0.51w`: the analytic table 0.490 / 0.570
/ 0.745 / 0.920 / 1.000 at d = 0/1/2/3/4 m is correct, the steepest slope
`1.5·t(1−t)` gives 0.375/m, and `0.375 × 0.25 × 0.51 = 0.0478` is right.

**The revert is real and complete**: the mission code, the suite-100 guard and
`probe_room_grade.gd` are gone (item A), the harness is kept with an explicit
`STATUS: … REVERTED …` header (`build/qa/w9_room_grade_sweep.gd:4-9`, mtime
13:59, i.e. after the 13:55 log), and the only B1 code left in the game is the
fill removal.

**Caveat (unavoidable):** pre-registration *timing* is self-attested — the
report is a gitignored `build/qa` file with no commit history, so the only
independent evidence is that the log's criteria line matches the table and
that no criterion was relaxed to turn the FAIL into a PASS. I found nothing
inconsistent with the claim, but I cannot prove the wall-clock order.

## D. Authored counterpart (RE) — AUDIT: PASS

Spot-checked against the extract, not just against the RE:

- `extracted/json/Art/Environment/Weather/BP_WeatherPreset_Base_Skybox.json:1367-1372`
  is exactly `AutoExposureBias 0.0`, `AutoExposureBiasCurve =
  Curve_Exposure_Compensation_Float_V3`, `AutoExposureMinBrightness -10.0`.
  `BP_WeatherPreset_Base.json:2050-2102` holds
  `AutoExposureMethod = AEM_Basic`, `MaxBrightness 1.0`, `SpeedUp 0.2`,
  `SpeedDown 2.0`, `Bias 0.5`, `Min -3.5`, V1. `BP_WeatherPreset_Gloomy.json:326-337`
  templates Base_Skybox's `PostProcessComponent` and overrides none of the
  auto-exposure fields (0 `AutoExposure` hits in the file), so the shipped
  Guildhall chain **is** Base_Skybox's −10.0 / 0.0 / 0.2 / 2.0 / V3 +
  Base's AEM_Basic / Max 1.0.
- `Curve_Exposure_Compensation_Float_V3.json:15-93` is the 8-key linear curve
  −12.1 → −0.5, −11.1 → −1.5, −10.1 → −2.0, −9.1 → −2.25, −8.1 → −2.5,
  −6.1 → −3.0, −3.0 → −4.0, +0.2 → −4.0. The direction is stated correctly in
  both the report and the RE: **the pull-down grows as the scene brightens**
  (−0.5 EV at the dark end, −4.0 EV at the bright end). The "pulls down as the
  scene darkens" wording is correctly identified as a stale comment in
  `weather_profile.gd:122-126`.
- `DefaultEngine.ini:527` is
  `r.DefaultFeature.AutoExposure.ExtendDefaultLuminanceRange=True` (EV100
  space) as cited.
- No authored room split: all **34** generated Guildhall level JSONs carry
  `post_process: []` (key present, empty), the whole extract has exactly two
  placed `PostProcessVolume`s (`MainMenu/BeautifulCorner_Startscreen_Lighting.json`,
  `ThievesDenTest/ThievesDenTest_P.json`), and no file under
  `extracted/json/Maps/Guildhall/` contains `PostProcessComponent` or
  `PostProcessSettings`.
- `0.49` is a linear **log2(0.49) = −1.03 EV**, not the authored V3 −4.0 EV
  at the port's assumed night EV100 (−3.0). The report and RE both say this
  and both label the candidate "APPROXIMATION / NOT AUTHORED".
- The "moving player" limitations are stated (report §0.4; RE §4), including
  the ~1.1 s traversal of the 4 m feather at 3.6 m/s versus the authored
  0.2 f-stops/s (~20 s for 4 EV) and the fact that the port does not keep
  adapting after stopping.

## E. Gate control and the C7 domain — AUDIT: PASS (lead summary imprecise)

Log values: gate ratio **0.9997** (23.86 / 23.87), upper ratio **0.7191**
(32.96 / 45.83) at multiplier 0.4900 — exactly as claimed.

The C7 blow-up value is not the gate pose. The harness (`_verdict`, C7) takes
the max over the gate **and every sample with `mult >= 0.999`**, i.e. the
z = −30 endpoints; that is where `bleed_rmse=0.1483` / `bleed_ae=4.7577`
come from. The gate sample itself is `rmse=0.0313 ae=0.6350`. §0.3 defines
the domain correctly ("gate pose and every sweep sample at d ≥ 4 m") and the
report attributes the numbers to that domain, so the report is accurate. The
lead's one-line summary ("gate on/off … RMSE 0.148 %, AE 4.76 %") conflates
the gate with the d = 4 endpoint; the correct split is gate 0.031 % / 0.635 %
and worst-in-domain 0.148 % / 4.76 %.

The separate candidate gate pair is also true: `magick compare` on
`p2_gate_on…` vs `p2_gate_off…` gives `RMSE 240.5/65535 = 0.367 %` and
`AE 77 px`, matching report §0.1/§B1-2.

## F. Tests and the deleted suite 100 — AUDIT: PASS

Full `run_tests.gd` on this tree, headless, under the flock:

```
$ flock /tmp/opencode/tat2-godot.lock -c "tools/godot --headless --path game --script res://tests/run_tests.gd"
PASS: 98 W9-P1-A4 night-grade guard (guildhall keeps AGX 1.15 / ambient 0.16, lobby floor held, Den bias+floor held, old_manor ungraded, gloomy preset is one-map scoped)
PASS: 99 W9-P1 authored progression (…)
PASS: 101 W9-P2 B2 authored locks (…)
PASS: 102 … 105 …
SUMMARY: fails=0
```

- `^PASS: ` count = **308**, `^FAIL` count = **0**, `SUMMARY: fails=0`.
- Suite **98 passes** and its assertions are untouched: `git diff b13260b --
  game/tests/run_tests.gd` is a single hunk at `@@ -7520,6 +7520,34 @@`
  adding the 101–105 driver only.
- Suite **100 does not exist**: the run goes 99 → 101, `# 100.` has no match
  in `run_tests.gd`, and the only mentions of "suite 100" in the tree are
  explicit history (`p2-report.md:351` "the suite-100 guard … removed",
  `facts-b1.md`, `b2-impl.md`) — not a silent dangling reference. No test,
  Makefile target or gate-ratchet entry names it.

## G. Minor findings (non-blocking, do not change the verdict)

1. **Gap arithmetic in §B1-1.** "remaining gap −14 p50 / −8.9 points on
   upper_foyer, −16 / −6.5 on yaw180": against the stated band `%<8` 9–24 the
   upper gap is 9 − 1.1 = **7.9**, not 8.9. 8.9 is 10 − 1.1, i.e. T07's
   "~10-25" lower bound (`docs/reports/remediation-20261125/T07-render.md:555-556`);
   `facts-b1.md:499-501` already notes that 9–24 comes from P0/P1, not T07.
   The sentence mixes the two sources. The error is **conservative** (it
   overstates the shortfall) and the band is stated as unmet three times.
2. **§B1-3 GPU range.** "GPU during the captures: 57–67 °C, 5.3–6.0 GiB,
   8–49 % util" does not match the `.gpu_*` files: the range across the B1
   captures is **58.5–67.3 °C, 4.42–5.58 GiB, 7–56 % util** (the fill-only
   runs sit at 4.4–4.85 GiB; only the candidate runs are 5.3–5.6 GiB).
   Provenance colour only; the frames are still one-Godot-at-a-time.
3. **"every 1-LSB rain pixel"** (§0.3 after the run): with RMSE 0.1483 % and
   AE 4.7577 % the differing pixels average ≈1.7 luma, not 1 LSB. The point
   (sub-perceptual rain noise inflates AE) stands.
4. **C1 derivation rounding.** The text's own sum `0.0262 + 0.004 = 0.0302`
   is 0.0002 above the pre-registered `0.030`; immaterial, and the measured
   0.0323 fails either way.
5. **Stale comments left behind (documented as integrator work, worth adding
   to the list):** `game/tests/run_tests.gd:7423` still says "the two
   shadowless foyer fills (… 1.6 at 3.3 m and 1.3 at 14.1 m)" although one
   fill now exists — comment only, suite 98 still passes; and
   `build/qa/w9_grade_probe.gd:35` still says "Run with TAT2_ROOM_GRADE=off so
   the mission does not also apply it", which is now a no-op env var (harness
   only, no game code reads it).

## H. Limitations

- Pre-registration wall-clock order is not independently provable (gitignored
  report, untracked harness). Verified instead: the log's criteria line is
  generated from the checked-in constants, matches §0.3 exactly, and the FAIL
  was not revised away.
- I did not re-run the 128 s sweep (the brief did not ask for it and the
  capture GPU is serialised across auditors). The post-revert behaviour of the
  harness is inferred from code: the mission no longer reads
  `TAT2_ROOM_GRADE` and the probe camera has no `CameraAttributes`, so every
  on/off pair collapses to ratio 1.0 — which is what its status note says.
- I did not re-run the door/viewmodel/Niagara probes or E2E (not part of the
  B1 claim set). The B1 gate claims I checked are the compile-relevant tree
  state, `run_tests` and the pixels.

---

## Verdict

The revert is **real and complete**: no room-grade symbol, camera attribute,
suite or probe survives in `game/`; the only B1 change in the game is the
single far fill at `(27, 31, −64)`, energy 1.3. `weather_profile.gd` is
byte-identical to `c2a1cd8`. The report **tells the truth about the unmet
band**: the interior band is explicitly NOT met (upper 29 / 1.1 %,
yaw180 31 / 2.5 %), the candidate's in-band result is kept as a reverted
artefact, the pre-registered sweep FAIL (C1 0.0323, C3/C4 0.0063/0.0070,
C7 AE 4.7577 %) is printed in full with the passing criteria alongside, and
no criterion was relaxed. My independent recapture reproduces the final frame
**exactly** (45.7 / 29 / 182 / 1.1 %), and `run_tests` is **308 PASS / 0 FAIL**
with suite 98 green and suite 100 absent.

**AUDIT: PASS**
