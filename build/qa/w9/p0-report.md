# W9-P0 — verification and gate hygiene (report)

Phase lead: W9-P0. Worktree `/home/john/Projects/TAT-2-rem-w9-p0`, branch `rem/w9-p0`,
base `e3678be` (R8 merged). Nothing pushed, merged or rebased. **No `game/` file changed**
(`git diff --stat e3678be..HEAD -- game/` is empty at every commit in this branch).

## Capture outcomes — read this first

The three captures are real Vulkan frames, verified non-black by both the in-game
sampler and `build/qa/w9_frame_stats.py`. The pixels do **not** fully match the
references, and the two mismatches are composition/grade, not exposure:

1. **Mission prep is composed but not KF11.** The authored `CameraActor_0` is
   restored (position, pitch/yaw/roll, FOV 20° horizontal; 387/2,107 mesh pivots in
   the 10° cone, reproduced headlessly by the research lane). But the frame behind
   the thief is a **near `MissionLobby` facade**, not KF11's city roofline: no sky,
   no moon, no distant chimneys. The 8 `prep_skyline` expansion pieces contribute
   **zero visible pixels** — `prep_nosky` (group freed) has identical statistics to
   `prep_ao_on` — and their authored band (tops sy 0.75–0.95) is where KF11 puts the
   *near roof*, not the city (KF11 silhouette tops: p50 sy 0.372). Global mean
   matches KF11 by coincidence (37.0 vs 37.2) while the distribution does not
   (p50 25 vs 28, %<8 7.1 vs 22.9, p95 126 vs 85). **P1 should not move the camera
   again**; the fix is the level/periphery placement behind the subject (and the
   still-unlanded stage grade: ACES 2.6 / ambient 1.8 at HEAD). Retire or re-author
   `prep_skyline` — it is measurably invisible at the authored pose.
2. **Guildhall interiors are no longer crushed, but overshot.** Pre-R8 was p50 2–4
   with 52–78 % of pixels < 8; the target was p50 13–15 with 9–24 % < 8. Measured
   now: upper foyer **p50 34, 0.8 % < 8**; the marble-hall view **p50 31, 2.3 % < 8**.
   The room is ~2× brighter than the reference and has almost no black floor. The
   light plan is doing work; the energy/exposure wants a downward retune, not a
   global cut (the W7 defect).
3. **KF27's room is reachable and closer than the scorecard says.** The best port
   frame is `foyer_sweep_yaw180` (checkered marble, leather armchair + ottoman,
   white vitrine, busts, archway, beam top-right). It is **2.4× brighter and much
   flatter** than KF27 (40.5/31/105/2.3 % vs 16.7/15/34/16.7 %). Two scorecard rows
   outside the 17 `UNVERIFIED` are factually stale and should be re-scored in a
   later pass: **V4-07** ("no velvet armchair/ottoman" — the armchair + ottoman are
   present at this pose) and **V6-03** ("no beam, wall emitter" — a
   `security_beam.gd` `BP_Detector_LightBeam_C` from an authored `light_beam`
   device is in view at the upper-foyer pose). They were left untouched because
   P0's scope is the 17 `UNVERIFIED` rows only.
4. **SSAO has no measurable cost at 1080p** in these views (see §B); the AO on/off
   frames are statistically identical. The heavier view is the marble hall at
   43.6–46.7 FPS (below the 60 FPS desktop gate); the upper foyer is 69.1–73.7 FPS.

## A. Three confirmation captures

Harness: `build/qa/w9_capture.gd` + `build/qa/w9_capture.sh` (tracked). Every run
holds `/tmp/opencode/tat2-godot.lock`, uses `xvfb-run -a -s '-screen 0 1920x1080x24'`,
one Godot at a time, and records `nvidia-smi` before/after plus wall time. Output
PNGs are gitignored under `build/qa/w9/captures/`; logs in `build/qa/w9/logs/`.
Stats use the exact L1 pipeline (`magick -colorspace gray -resize 480x`, 256-bin
histogram, `%<8` = luma ≤ 7/255).

### W9-P0-1 — Mission prep: authored camera + `prep_skyline`
- **investigate:** `game/src/ui/mission_prep_ui.gd:63-124` (authored camera, subject
  slot, skyline contract); `build/qa/vf_mission_prep.png` is the pre-R8 reference
  and is itself 50.9 % black (`/tmp/opencode/w9-p0-research.md` §5.3), so it cannot
  be the target.
- **research:** KF11 official 37.2 / 28 / 85 / 22.9 % < 8; the city silhouette top
  is p50 sy 0.372 (97.9 % of columns above sy 0.65); `prep_skyline` tops are
  authored to 0.746–0.954 by contract (`T05-ui.md:79-81`).
- **confirm (red):** pre-R8 `vf_mission_prep.png` 17.7 / 7 / 69 / 50.9 %; run frame
  `f_0072` 31.3 / 17 / 83 / 26.5 %.
- **fix:** none — P0 is verification. Harness only.
- **test:** `TAT2_AO=on build/qa/w9_capture.sh prep prep_ao_on 1920x1080`
  (13 s wall; GPU 60.1 → 59.6 °C, 4407 → 4379 MiB, 8 → 18 %). Stage log:
  `camera pos=(12.6065,-0.16698,-1.05384) rot=(6.685,96.814,14.780) fov=20.00`,
  `skyline=8`, `thief_anchor=true`, `ssao=true ssil=false exposure=2.600`.
- **confirm (green):** `prep_ao_on.png` 1920×1080, **mean 37.0, p50 25, p95 126,
  %<8 7.1**, peak 251.7, `nonblack=true`. Diagnostic `prep_nosky` (skyline freed):
  **identical 37.0 / 25 / 126 / 7.1** — the expansion layer is invisible at the
  authored pose. Diagnostic `prep_noui` (stage only): 30.5 / 23 / 80 / 12.1.
- **verdict:** **PARTIAL** — camera restored and verified, composition still not
  KF11; `prep_skyline` does no visible work. Owner: W9-P1/P3 (level/periphery and
  stage grade), not the camera.

### W9-P0-2 — Guildhall interiors: light plan + SSIL/SSAO A/B
- **investigate:** `game/src/core/weather_profile.gd:341-378` (`TAT2_AO=off` removes
  SSAO only; SSIL stays), `T07-render.md:52,97-113` (154/189 bubbles), target
  p50 13–15 / %<8 9–24 (`T07-render.md:555-560`).
- **research:** pre-R8 L1-01: p50 2–4, 52–78 % < 8; reference KF27 16.7 / 15 / 34 /
  16.7 %.
- **confirm (red):** pre-R8 port frames `t=241` 2 / 43 / 78.4 %, `t=110` 4 / 42 /
  51.9 % (`L1-render.md:154-194`).
- **fix:** none — P0 is verification.
- **test:** `TAT2_AO=on|off build/qa/w9_capture.sh upper_foyer <tag> 1920x1080`
  (45 s each; GPU 57.8 → 58.5 °C / 58.5 → 58.7 °C). `W9_ENV` proves the lever:
  `ssao=true ssil=true` vs `ssao=false ssil=true`, exposure 1.150 both.
- **confirm (green):** AO on **50.5 / 34 / 182 / 0.8 %**; AO off **50.6 / 34 / 181 /
  0.8 %**. The crush is gone; the target band was overshot by ~2× and the black
  floor (9–24 %) is now 0.8 %. The AO A/B is statistically identical.
- **verdict:** **DELTA / overshoot** — retune energy/exposure down; do not
  reintroduce a global cut. Owner: W9-P1 (lighting) with P2 for the room pass.

### W9-P0-3 — KF11 / KF27 comparison
- **investigate:** KF11 is the only prep keyframe; KF27's foyer is the marble hall
  at the upper-foyer pose (the recorded run's `f_0267` is another corner of it).
- **research:** KF27 official 16.7 / 15 / 34 / 16.7 %; its beam is a 3-px row band
  at sy 0.40 (research lane §1.2).
- **confirm (red):** `f_0267` 15.6 / 9 / 52 / 36.7 % (too black); `f_0072` prep
  31.3 / 17 / 83 / 26.5 %.
- **fix:** none — P0 is verification.
- **test:** `TAT2_AO=on build/qa/w9_capture.sh foyer_sweep foyer_sweep 1920x1080`
  (49 s; GPU 58.4 → 59.1 °C). Four yaw views from the upper-foyer slot; the marble
  hall is `yaw180`.
- **confirm (green):** best KF27 match `foyer_sweep_yaw180.png` **40.5 / 31 / 105 /
  2.3 %** vs KF27 16.7 / 15 / 34 / 16.7 %; best KF11 match `prep_ao_on.png`
  37.0 / 25 / 126 / 7.1 % vs KF11 37.2 / 28 / 85 / 22.9 %.
- **verdict:** **DELTA** — the subjects are present (marble, armchair + ottoman,
  vitrine, busts, a security beam and wall emitter); the grade is 2–2.4× brighter
  and flatter. V4-07/V6-03 are stale (see top); not edited in this wave.

### Capture statistics table (all 1920×1080, L1 pipeline)

| capture | AO | mean | p50 | p95 | %<8 | %<16 | % >200 | non-black | wall |
|---|---|---|---|---|---|---|---|---|---|
| `prep_ao_on` | on | 37.0 | 25 | 126 | 7.1 | 34.0 | 1.13 | yes | 13 s |
| `prep_nosky` (skyline freed) | on | 37.0 | 25 | 126 | 7.1 | 34.0 | 1.13 | yes | 12 s |
| `prep_noui` (stage only) | on | 30.5 | 23 | 80 | 12.1 | 30.0 | 0.29 | yes | 12 s |
| `upper_foyer_ao_on` | on | 50.5 | 34 | 182 | 0.8 | 2.2 | 3.80 | yes | 45 s |
| `upper_foyer_ao_off` | off | 50.6 | 34 | 181 | 0.8 | 2.2 | 3.70 | yes | 45 s |
| `foyer_ao_on` (lower approach) | on | 31.5 | 32 | 58 | 1.3 | 21.4 | 0.22 | yes | 45 s |
| `foyer_sweep_yaw000` | on | 50.5 | 34 | 182 | 0.8 | 2.2 | 3.81 | yes | 49 s |
| `foyer_sweep_yaw090` | on | 31.4 | 28 | 53 | 1.4 | 3.9 | 0.22 | yes | 49 s |
| `foyer_sweep_yaw180` (KF27 match) | on | 40.5 | 31 | 105 | 2.3 | 10.5 | 0.24 | yes | 49 s |
| `foyer_sweep_yaw270` | on | 49.7 | 42 | 110 | 0.5 | 1.3 | 0.23 | yes | 49 s |
| **KF11 official** | — | 37.2 | 28 | 85 | 22.9 | — | — | — | — |
| **KF27 official** | — | 16.7 | 15 | 34 | 16.7 | — | — | — | — |
| pre-R8 `vf_mission_prep.png` | — | 17.7 | 7 | 69 | 50.9 | — | — | — | — |
| pre-R8 `f_0072` | — | 31.3 | 17 | 83 | 26.5 | — | — | — | — |
| pre-R8 `f_0267` | — | 15.6 | 9 | 52 | 36.7 | — | — | — | — |

No **capture** exceeded 60 °C on the GPU (the perf runs reached 66.7–68.5 °C); the
CPU package was 80–96 °C across the session (see §B).

Per-run GPU samples for every capture (the `.gpu_before` / `.gpu_after` files
next to each log in `build/qa/w9/logs/`):

| capture | GPU before (°C / MiB / util / MHz) | GPU after (°C / MiB / util / MHz) |
|---|---|---|
| `prep_ao_on` | 60.1 / 4407 / 8 % / 1215 | 59.6 / 4379 / 18 % / 900 |
| `prep_nosky` | 59.3 / 4403 / 19 % / 420 | 59.5 / 4377 / 28 % / 1245 |
| `prep_noui` | 59.2 / 4399 / 34 % / 645 | 59.5 / 4375 / 33 % / 1215 |
| `upper_foyer_ao_on` | 57.8 / 4403 / 49 % / 450 | 58.5 / 4377 / 13 % / 1425 |
| `upper_foyer_ao_off` | 58.5 / 4407 / 11 % / 1185 | 58.7 / 4381 / 12 % / 1335 |
| `foyer_ao_on` | 58.3 / 4407 / 46 % / 1155 | 59.0 / 4381 / 34 % / 1380 |
| `foyer_sweep` | 58.4 / 4407 / 29 % / 480 | 59.1 / 4379 / 3 % / 2220 |

## B. Perf matrix (three scenes, AO on/off)

Method: `build/qa/w9_perf.gd` + `build/qa/w9_perf.sh` (tracked). Vsync disabled,
1920×1080, one process per `TAT2_AO` setting, 60 warm + 240 measured frames,
wall-clock frame deltas, p50/p95/p99 from the same percentile helper as
`game/tests/perf/perf_matrix_runner.gd`; the prep pose and the two interior poses
are the perf-runner poses (`upper_foyer` = (27,28,-50) → (27,29.67,-60); the
marble-hall yaw is the same slot turned 180°). Two repeats per setting. The host
compositor is used, not Xvfb: the repo's own wrapper says Xvfb adds ~25 ms/frame
at 720p and would swamp the AO delta.

| scene | AO | run | mean ms | p50 | p95 | p99 | FPS | 1 % low FPS |
|---|---|---|---|---|---|---|---|---|
| prep | on | 1 | 6.90 | 6.90 | 7.01 | 7.09 | 144.9 | 141.1 |
| prep | on | 2 | 6.90 | 6.90 | 7.01 | 7.08 | 144.9 | 141.3 |
| prep | off | 1 | 6.90 | 6.90 | 7.01 | 7.04 | 144.9 | 142.0 |
| prep | off | 2 | 6.90 | 6.90 | 7.05 | 7.15 | 144.9 | 139.8 |
| upper_foyer | on | 1 | 13.69 | 13.60 | 16.55 | 17.32 | 73.0 | 57.7 |
| upper_foyer | on | 2 | 13.93 | 13.95 | 16.99 | 18.23 | 71.8 | 54.9 |
| upper_foyer | off | 1 | 13.76 | 13.79 | 16.88 | 17.81 | 72.7 | 56.1 |
| upper_foyer | off | 2 | 13.56 | 13.34 | 17.09 | 18.07 | 73.7 | 55.3 |
| foyer_yaw180 | on | 1 | 21.83 | 21.88 | 25.78 | 26.91 | 45.8 | 37.2 |
| foyer_yaw180 | on | 2 | 21.71 | 21.70 | 25.49 | 27.29 | 46.1 | 36.6 |
| foyer_yaw180 | off | 1 | 21.92 | 21.92 | 25.83 | 27.47 | 45.6 | 36.4 |
| foyer_yaw180 | off | 2 | 21.42 | 21.39 | 24.73 | 26.06 | 46.7 | 38.4 |

- **AO cost:** upper foyer mean 13.81 ms (on) vs 13.66 ms (off), **+0.15 ms / ~1 %**;
  marble hall 21.77 vs 21.67 ms, **+0.10 ms / ~0.5 %**. Both are smaller than the
  run-to-run spread (on runs differ by 0.24 ms, off by 0.20 ms): **SSAO has no
  measurable cost at 1080p in these views**. The independent audit re-ran both
  settings on the same tree and measured the same sign and magnitude (upper foyer
  +0.17 ms, marble hall −0.16 ms), so the AO conclusion is robust even though the
  absolute FPS is not: the audit's absolute numbers are **3–7 % below the table**
  (upper foyer 69.1–69.9 FPS, marble hall 43.6–43.9 FPS) with the host at 83–92 °C.
  **Quote the absolute FPS as a host-thermal range:** upper foyer **69.1–73.7 FPS**
  (60 FPS gate met), marble hall **43.6–46.7 FPS** (60 FPS gate missed in that view).
- **Prep is presentation-bound at ~6.9 ms (144.9 FPS)**, above the 119.86 Hz panel,
  so this is not a display/vsync cap; 6.9 ms is an upper bound on the prep cost and
  the AO delta there is unmeasurable at 1080p. Reported as a bound, not a scene cost.
- **The repo's own wrapper was attempted and refused.** `build/qa/run_perf_matrix.sh
  --pose=upper_foyer --quality=high --scale=1.0 --scaling=bilinear --frames=180
  --warmup=60 --start-temp=92 --max-temp=95 --tag=w9_cross_ao_on` aborted in its
  pre-warm at **98 °C** (`FAIL: pre-warm thermal abort (temp at 98C, max 95C)`), so
  no wrapper numbers exist. The transcript is
  `build/qa/w9/logs/perf_matrix_attempt.log`; the pre-warm log is
  `build/qa/perf/prewarm_w9_cross_ao_on.log`. The short probe above ran with the CPU
  package at 80–96 °C and the audit's repeat at 83–92 °C was 3–7 % slower; both are
  laptop measurements, not a publishable gate. A cool-host re-run of
  `run_perf_matrix.sh` is required before quoting 60 FPS parity.

## C. Scorecard closure (17 `UNVERIFIED` rows)

- **Moved:** `AU1-03` (loading digital silence) `UNVERIFIED` → **`DELTA`**, on an
  existing control-plane measurement: `game/tests/test_audio_mix.gd:126-147` drives
  `begin_loading_silence()` and asserts every emitter, bed and music player stops
  and the Ambience/SFX buses mute (Music mute in `audio_manager.gd:1514-1535`), then
  restore. It is not a master-bus sample (UI bus unmuted, no `AudioEffectCapture`),
  and the test is not wired into `run_tests.gd`; the audit ran it explicitly
  (`fails=0 passed=49`). The delta is the transition: a 0 s hard mute vs the
  official 2.84 s fade, and a ~18.8 s hold vs 4.64 s (L4-12).
- **Re-declared:** the other **16** rows stay `UNVERIFIED`, each with a precise
  `Missing evidence (W9-P0):` sentence naming the instrument (an in-engine
  master-bus capture via `AudioEffectCapture` on Master, 48 kHz, over the named
  window; `UI5-01` a 0.2 s quiet-vs-sprint HUD capture with the noise level
  logged). No control-plane test is treated as a substitute for the audible row.
- **Tally:** `DELTA` 31 → **32**, `UNVERIFIED` 17 → **16**, scored 46 → **47**,
  `N/A-route` 57 unchanged; coverage line **47 + 57 + 16 = 120**. All 120 rows and
  the template order are preserved; no row was added, dropped or merged.
- **New, outside the 17 (not edited):** V4-07's "no velvet armchair/ottoman" and
  V6-03's "no beam, wall emitter" are falsified by `foyer_sweep_yaw180` /
  `upper_foyer_ao_on`; both need a re-score in the next scorecard pass.

## D. Gate hygiene (ratchet raised to R8, floors as minimums)

- `tools/gate_ratchet.json`: `measured_on` **e3678be**, evidence dir
  `docs/reports/logs/r8/`, report `docs/reports/r8-gate-ratchet.md`. Floors:
  compile **152/0**, run_tests **301/0**, M2 **12/0**, E2E **278/278**, audit
  **12,660/12,703**, texture cap **797/1/0**, perf guard **78/0**, plus the five
  probe markers and a clean `probe_leak`.
- `tools/check_gate_ratchet.py`: counts are compared with `>=` against the log
  (a lower count fails; a higher one passes), failure counts are exact zeros,
  `e2e.passed == e2e.total`, coverage `num <= den`; the report path comes from the
  JSON; the audit pattern now matches the producer's
  `Disk-backed content coverage:`; the five probes and the perf guard are
  first-class log gates.
- **Red → green:** `make audit` failed with `CONSUMER AUDIT FAILED: 2 failure(s)`
  on `STALE RULE tables/Art/UI/Icons/**` and `STALE RULE vfx/*.json`; both files
  are read at runtime now (`game/src/ui/input_glyphs.gd:19`,
  `game/src/core/vfx/niagara_library.gd:19`), so the two stale allowlist entries
  were removed (the fix the audit prescribes). `make audit` → **AUDIT PASS**
  (12,660/12,703, unexpected 0); `make gate-ratchet` → **GATE_RATCHET: PASS**.
- **Measured deltas vs R8's report:** coverage 12,657 → 12,660 (three files now
  resolve by exported-name rename; `audit_baseline.json` records
  `disk_missing_allowlisted: 43`), texture `capped` 773 → 797 (R8 material
  producers added 24 over-cap textures; offenders 0, out-of-scope 261 unchanged).
  Both are increases; no floor was lowered.
- Full gate set re-run on this tree: compile 152/0 (4.2 s), run_tests 301/0
  (103.7 s), M2 12/0 (2.0 s), E2E 278/278 (301.2 s), tier 1 117/117 (96.5 s),
  door walk / viewmodel / Niagara (1,048 active, 810 params) / blackjack /
  geometry PASS, `probe_leak` clean, audit PASS (5.1 s), texture cap 0 offenders,
  perf guard 78/78, ratchet PASS. Logs are the 14 files under
  `docs/reports/logs/r8/`; `docs/reports/logs/w7-merged/` and `w7g-*` are left
  untouched as history.

## Independent audit

A separate agent re-ran every proof on this tree. Its full report is archived at
[`build/qa/w9/audit-report.md`](audit-report.md) (force-added, like this report):

- **A. Captures — PASS.** Its own `audit_` tags reproduced prep 36.9/25/126/7.1
  (report 37.0/25/126/7.1), upper on 50.5/34/179/0.8, upper off 50.6/34/180/0.8,
  yaw180 40.5/31/105/2.3; every shot `nonblack=true`; the `W9_ENV` AO flags
  matched; `prep_nosky` matched prep within 0.1/0/0/0, so "skyline contributes
  nothing" holds; the images match the visual verdict.
- **B. Perf — the audit's verdict was FAIL on the absolute FPS band.** Its two runs
  were 3–7 % below the lead's table (upper 69.1/69.9, marble hall 43.9/43.6 FPS)
  with the host at 83–92 °C; the method, the 240-frame counts, the AO flags and the
  AO delta all passed (same sign and magnitude). Resolved by re-quoting the absolute
  FPS as the observed range (upper 69.1–73.7, marble hall 43.6–46.7) and correcting
  the prep label from "display-capped" to "presentation-bound at ~6.9 ms" (the panel
  is 119.86 Hz; 144.9 FPS is not a display cap). The matrix and the AO conclusion
  stand; a cool-host re-run is still owed for publishable numbers.
- **C. Scorecard — PASS, one wording fix.** 120 rows, template order, tally
  9/32/4/2/16/57 = 120; exactly one row moved; all 16 others carry precise missing
  evidence. It flagged the AU1-03 wording ("Music bus muted / digital zero" was an
  inference); the row now says "control plane", cites the Music mute line, and
  names the test's non-gated status. Score unchanged.
- **D. Gate hygiene — PASS.** It re-ran compile 152/0, run_tests 301/0, M2 12/0,
  E2E 278/278, the five probes, clean `probe_leak`, audit 12,660/12,703, texture
  cap 0 offenders, perf guard 78/78 and `make gate-ratchet`; it proved the `>=`
  floor by raising `compile.checked`/`run_tests.passes` in a `/tmp` copy (both
  exit 1), and confirmed `git diff HEAD~2 -- game/` is empty and only the two
  genuinely consumed allowlist rules were removed.
- **Pre-existing, not W9-P0:** `run_tests` logs two `SCRIPT ERROR`s at
  `audio_manager.gd:712`; the same lines are in the committed R8 log.

## Integrator steps

1. Cherry-pick `e3678be..rem/w9-p0` (three commits: gate hygiene, harness, report)
   onto `main` in order. Do not squash: the red proofs are in the messages.
2. **Keep** `docs/reports/logs/r8/**` (14 logs) and
   `docs/reports/r8-gate-ratchet.md`. They are the files `make gate-ratchet`
   reads; deleting or editing them makes the ratchet fail closed.
3. The report `build/qa/w9/p0-report.md` is force-added (`git add -f`): `build/qa/*.md`
   is gitignored, the same precedent as `build/qa/review_20261124/remediation/*.md`.
   The PNGs and perf logs under `build/qa/w9/` are **not** committed; copy them
   out of the worktree if you want the pixels.
4. **No `game/` file changed** by this branch (`git diff --stat e3678be..HEAD --
   game/` empty). If the cherry-pick touches `game/`, stop and investigate.
5. Re-run `make gate-ratchet` after the cherry-pick; it should pass unchanged.
   Then re-run the golden gate set serially (AGENTS.md) — the numbers above are
   the floors.
6. Do **not** regenerate data for this wave. The only data-adjacent change is the
   consumer allowlist (a tools file), not a producer output.
7. The perf numbers are a laptop measurement at 80–96 °C CPU package with a 3–7 %
   run-to-run spread (the audit's repeat at 83–92 °C was 3–7 % slower); quote the
   ranges, not a single FPS. The repo's `run_perf_matrix.sh` refused at 98 °C in
   pre-warm. Re-run it on a cool host before quoting 60 FPS parity in any
   publishable document.
8. W9-P1 should read the four capture outcomes at the top before touching
   collision/progression: the prep composition needs the level/periphery fix and
   the stage grade (not another camera move), the interior needs a downward
   energy retune, and `prep_skyline` is measurably invisible.
