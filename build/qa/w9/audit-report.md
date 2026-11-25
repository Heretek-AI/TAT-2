# W9-P0 independent audit — `rem/w9-p0`

Audit lane (independent; did not write this code). Worktree:
`/home/john/Projects/TAT-2-rem-w9-p0`, branch `rem/w9-p0`, HEAD `9448dae`
(`feat(qa): W9-P0 capture and perf harness`). No tracked file in the worktree was
edited by this lane; the only file written is this report. Every Godot call was
serialised with
`flock /tmp/opencode/tat2-godot.lock -c 'cd <worktree> && timeout 1800 tools/godot …'`;
captures used `build/qa/w9_capture.sh` (which takes the same lock and xvfb itself).
No producer, `make normalize`, `make audit-refresh-stamps` or `tools/parse_*.py`
was run.

Host state during the audit: CPU package 83–92 °C (idle 85 °C), GPU 59–69 °C,
load average ~1.6–2.1, one 3840×2160 @ 119.86 Hz output (HDMI-A-1).

---

## A. CAPTURES — AUDIT: PASS

Commands (all exit 0; `build/qa/w9/logs/cap_audit_*.log`):

```
TAT2_AO=on  build/qa/w9_capture.sh prep        audit_prep      1920x1080   # wall 12 s
TAT2_AO=on  build/qa/w9_capture.sh upper_foyer audit_upper_on  1920x1080   # wall 36 s
TAT2_AO=off build/qa/w9_capture.sh upper_foyer audit_upper_off 1920x1080   # wall 36 s
TAT2_AO=on  build/qa/w9_capture.sh foyer_sweep audit_sweep     1920x1080   # wall 40 s (4 PNGs)
TAT2_AO=on  build/qa/w9_capture.sh prep_nosky  audit_nosky     1920x1080   # wall 13 s
/usr/bin/python3 build/qa/w9_frame_stats.py <png>   # method=magick-gray-resize480
```

### A.1 Statistics, my PNGs vs the reported values

| Shot | mine (mean / p50 / p95 / %<8) | reported | Δ | tolerance |
|---|---|---|---|---|
| prep (AO on) | 36.9 / 25 / 126 / 7.1 % | 37.0 / 25 / 126 / 7.1 % | 0.1 / 0 / 0 / 0 | PASS |
| upper_foyer AO on | 50.5 / 34 / 179 / 0.8 % | 50.5 / 34 / 182 / 0.8 % | 0 / 0 / **3** / 0 | PASS (p95 at the ±3 edge) |
| upper_foyer AO off | 50.6 / 34 / 180 / 0.8 % | 50.6 / 34 / 181 / 0.8 % | 0 / 0 / 1 / 0 | PASS |
| foyer_sweep yaw180 | 40.5 / 31 / 105 / 2.3 % | 40.5 / 31 / 105 / 2.3 % | 0 / 0 / 0 / 0 | PASS |
| prep_nosky (skyline removed) | 37.0 / 25 / 126 / 7.1 % | — (compare to my prep) | 0.1 / 0 / 0 / 0 vs prep | PASS |

I also ran the same script over the lead's committed PNGs and got exactly the
reported figures (`prep_ao_on` 37.0/25/126/7.1, `upper_foyer_ao_on`
50.5/34/182/0.8, `upper_foyer_ao_off` 50.6/34/181/0.8, `foyer_sweep_yaw180`
40.5/31/105/2.3, `prep_nosky` 37.0/25/126/7.1), so the reported table is the
measurement of the PNGs it names, not a hand-typed figure.

`w9_frame_stats.py` does **not** emit a `nonblack` field (it emits mean / p50 /
p95 / %<8 / %<16 / %>200 only). The `nonblack=true` guard is printed by
`w9_capture.gd`'s `W9_CAPTURE` line, and every one of my shots has it:

```
W9_CAPTURE file=audit_prep      … mean601=36.66 pct_lt8=4.0 peak=251.7 nonblack=true ao=on
W9_CAPTURE file=audit_upper_on  … mean601=50.85 pct_lt8=1.4 peak=255.0 nonblack=true ao=on
W9_CAPTURE file=audit_upper_off … mean601=50.93 pct_lt8=1.4 peak=255.0 nonblack=true ao=off
W9_CAPTURE file=audit_sweep_yaw180 … mean601=40.71 pct_lt8=3.3 peak=254.7 nonblack=true ao=on
W9_CAPTURE file=audit_nosky     … mean601=36.72 pct_lt8=4.0 peak=251.7 nonblack=true ao=on
```

So mean > 1 and peak > 8 hold for every frame, with the engine-side sampled
luma agreeing with the histogram script to ≤0.4.

### A.2 The AO A/B was applied

`W9_ENV` lines from my logs (`build/qa/w9/logs/cap_audit_*.log`):

```
cap_audit_upper_on : W9_ENV scene=upper_foyer ssao=true  ssil=true tonemap=4 exposure=1.150 glow=true
cap_audit_upper_off: W9_ENV scene=upper_foyer ssao=false ssil=true tonemap=4 exposure=1.150 glow=true
cap_audit_prep     : W9_ENV scene=prep        ssao=true  ssil=false tonemap=4 exposure=2.600 glow=true
cap_audit_sweep    : W9_ENV scene=foyer_sweep ssao=true  ssil=true tonemap=4 exposure=1.150 glow=true
```

The flag really changed (`TAT2_AO=off` → `ssao=false`), and the frames differ:

```
magick compare -metric RMSE audit_upper_on.png audit_upper_off.png  -> 243.871 (0.00372)
```

Caveat (not a failure of the stated criterion): that AO delta is **smaller than
the same-config repeat-run noise** at the same pose — my `audit_upper_on` vs the
lead's `upper_foyer_ao_on` is `410.017 (0.00626)` RMSE. SSAO's visible effect at
this pose is therefore below run-to-run noise (rain/particles); the A/B is
applied at the flag level but is not visually separable. This is consistent with
the perf delta (≤0.8 FPS).

### A.3 "The prep stage has no visible skyline contribution" — holds

`prep_nosky` really removed the group: `W9_DIAG prep_nosky freed=0` means 0
skyline nodes remained, `W9_STAGE skyline=0` vs `skyline=8` for prep. My
`audit_prep` vs `audit_nosky`: mean 36.9 vs 37.0, p50 25/25, p95 126/126,
%<8 7.1/7.1 — all inside tolerance. The full-frame RMSE between them is
`959.386 (0.01464)`, the same magnitude as my `audit_prep` vs the lead's
`prep_ao_on` (`965.272 (0.01473)`), i.e. the skyline removal is indistinguishable
from run-to-run noise at this pose. **The claim is supported.**

### A.4 Visual verdict vs the PNGs (read)

- `audit_prep.png`: the Spider stands on a ledge in front of a near facade with a
  diagonal beam, dark night, rain streaks, prep cards over the left half — **no
  moon and no sky**. Matches the reported "thief on a ledge against a near
  facade, no moon/sky".
- `audit_upper_on.png` / `audit_upper_off.png`: checkered marble floor, dark
  panelled hall, doorway, and a bright **horizontal beam** across the middle.
  Matches "marble hall with a horizontal beam".
- `audit_sweep_yaw180.png`: the same marble hall with a tufted **armchair**, a
  red **ottoman**, and a white marble-topped **vitrine** on the right. Matches.

**A: PASS.** All four reported statistics reproduce inside tolerance (one p95 at
the ±3 edge, 182→179, explained by particle timing), the AO flag really flips,
the skyline claim is numerically and visually supported, and the three visual
verdicts match the images.

---

## B. PERF MATRIX — AUDIT: FAIL (absolute FPS did not reproduce; AO conclusion holds)

Commands:

```
TAT2_AO=on  build/qa/w9_perf.sh audit_ao_on  1920x1080 240 60   # exit 0, wall 44 s, cpu 83→92 C
TAT2_AO=off build/qa/w9_perf.sh audit_ao_off 1920x1080 240 60   # exit 0, wall 44 s, cpu 92→85 C
```

My `W9_PERF` lines (all `frames=240`; logs `build/qa/w9/logs/perf_audit_*.log`):

```
ao=on   prep         mean_ms=6.90  p50=6.90 p95=7.02  fps=144.9
ao=on   upper_foyer  mean_ms=14.47 p50=14.29 p95=17.64 fps=69.1   low1=51.3
ao=on   foyer_yaw180 mean_ms=22.79 p50=22.89 p95=27.38 fps=43.9   low1=34.0
ao=off  prep         mean_ms=6.90  p50=6.90 p95=7.01  fps=144.9
ao=off  upper_foyer  mean_ms=14.30 p50=13.99 p95=17.57 fps=69.9   low1=52.9
ao=off  foyer_yaw180 mean_ms=22.95 p50=22.92 p95=27.21 fps=43.6   low1=35.0
```

`W9_PERF_ENV` matches the tag in both runs: `ssao=true` for `audit_ao_on`
(prep and interior), `ssao=false` for `audit_ao_off`; `ssil=true` in both
interior runs, so only AO moved.

### B.1 What reproduced

- `frames=240` on all six lines; `W9_PERF_START … frames=240 warmup=60`;
  `W9_PERF_DONE` present in both runs; no `SCRIPT ERROR` from the runner.
- **AO delta within run noise**: upper_foyer 69.1 vs 69.9 = **0.8 FPS / 0.17 ms**;
  foyer_yaw180 43.9 vs 43.6 = **0.3 FPS / −0.16 ms** (AO "faster", i.e. noise).
  Both inside the ≤1.5 FPS / ≤0.5 ms bound. The W9-P0 question ("does AO cost
  frame time?") is answered: no measurable cost on either interior scene.
- **prep = 144.9 FPS exactly**, and `mean_ms=6.90`, `p50=6.90` in all six runs
  (mine and the lead's). But see B.3: "display-capped" is the wrong label.

### B.2 What did NOT reproduce (the FAIL)

| Scene | reported range | mine | below the range by |
|---|---|---|---|
| prep | 144.9 | 144.9 / 144.9 | — |
| upper_foyer | 71.8–73.7 | **69.1 / 69.9** | 1.9–4.6 FPS (2.6–6.2 %) |
| foyer_yaw180 | 45.6–46.7 | **43.9 / 43.6** | 1.7–3.1 FPS (3.7–6.6 %) |

Both of my runs are self-consistent and both are 3–7 % below the reported range
on both interiors, while prep is bit-identical. No `game/` file differs
(`git diff HEAD~2 -- game/` is empty), so this is not a code regression; the
likely cause is host state (CPU 83–92 °C during my runs, load ~2.0, and the
lead's own prewarm aborted at 98 °C on this host ~15 min earlier). The package
throttle counters are non-zero, but they are cumulative since boot and do not by
themselves prove throttling inside my window. Either way the reported absolute
FPS range is **not reproducible as stated**, and a range that only holds at one
thermal state should be labelled as such (e.g. "hot-host run, ±5 %") rather than
quoted as a tight band.

### B.3 Claim-level note: "prep 144.9 FPS (display-capped)"

The only output is 3840×2160 **@ 119.86 Hz** (`xrandr`), and the run measures
144.9 FPS. It cannot be display-capped at 144.9 on a 119.86 Hz panel. The
6.90 ms mean is identical to 0.01 ms in six independent runs, which is a fixed
present/loop limit, not a GPU-throughput measurement. The number reproduces, the
explanation does not.

### B.4 The pre-warm thermal abort is real

Read-only (not re-run): `build/qa/perf/prewarm_w9_cross_ao_on.log`

```
PERF_THERMAL start=91 start_max=92 max=95 …
PERF_THERMAL_SAMPLE phase=prewarm … t=91 … elapsed=12s
PERF_THERMAL_SAMPLE phase=prewarm … t=98 … elapsed=13s
PERF_THERMAL_ABORT phase=prewarm reason=temp peak_c=98 max_c=95
PERF_THERMAL_KILL reason=temp pid=1940932 unit=tat2-perf-w9_cross_ao_on-prewarm
PERF_THERMAL_PREWARM_PEAK peak_c=98 peak_rss_mb=1413 vmhwm_mb=1449 max_c=95 abort=temp
PERF_WARNING pre-warm did not reach PERF_DONE …
PERF_THERMAL_FAIL reason=temp phase=prewarm peak_c=98
```

and the wrapper log `build/qa/perf/perf_w9_cross_ao_on.log` carries the same
`PERF_THERMAL_ABORT … peak_c=98 max_c=95` / `PERF_THERMAL_FAIL`, with
`.thermal_prewarm_w9_cross_ao_on.summary` = `peak_temp=98 … abort=temp`. The
abort is genuine (the sampler killed the launch at 98 °C against
`--max-temp=95`), and I did not re-run it.

**B: FAIL.** frames/AO-state/`W9_PERF_DONE` are correct and the AO-cost
conclusion is reproduced, but two of the three absolute FPS figures fall outside
the reported ranges by 1.7–4.6 FPS (2.6–6.6 %), so the reported matrix does not
reproduce on this host. The "display-capped" explanation for prep is also wrong.

---

## C. SCORECARD — AUDIT: PASS (one wording overclaim flagged)

Command: `git diff HEAD~2 -- docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`
(plus `git diff` — the whole scorecard edit is uncommitted; no commit in
`HEAD~2..HEAD` touches it).

### C.1 Structure

Recount with a small python script over §2 (`## 2.` … `## 3.`):

- **120 rows**, 120 unique ids, first `V1-01`, last `G5-05`,
  `template order: True` (V1…V7, AU1…AU6, UI1…UI5, G1…G5, numeric within).
- Per-pillar counts: V 37, AU 31, UI 27, G 25 (sum 120).
- Totals: `PASS 9, DELTA 32, MISSING 4, HARD_LIMIT 2, UNVERIFIED 16, N/A-route 57`
  = 120; scored 47.

### C.2 §5 tally matches the recount

| §5 cell | V | AU | UI | G | total | recount |
|---|---|---|---|---|---|---|
| PASS | 6 | 0 | 2 | 1 | 9 | 9 ✓ |
| DELTA | 13 | 1 | 12 | 6 | 32 | 32 ✓ |
| MISSING | 1 | 1 | 1 | 1 | 4 | 4 ✓ |
| HARD_LIMIT | 2 | 0 | 0 | 0 | 2 | 2 ✓ |
| UNVERIFIED | 1 | 14 | 1 | 0 | 16 | 16 ✓ |
| N/A-route | 14 | 15 | 11 | 17 | 57 | 57 ✓ |
| rows | 37 | 31 | 27 | 25 | 120 | 120 ✓ |

Coverage line `scored 47 / N/A-route 57 / UNVERIFIED 16 (47 + 57 + 16 = 120)` and
`9 + 32 + 4 + 2 = 47` both check out. The reconciliation arithmetic
(56 NO + 4 → N/A, − 3 reachable = 57) is also consistent.

### C.3 Exactly one row moved, and only with evidence

Diffing per-row scores between `git show HEAD:…` and the working tree:

```
rows head/wt: 120 120
moved rows: [('AU1-03', 'UNVERIFIED', 'DELTA')]
HEAD tally: {'DELTA': 31, 'HARD_LIMIT': 2, 'N/A-route': 57, 'PASS': 9, 'UNVERIFIED': 17, 'MISSING': 4}
WT   tally: {'DELTA': 32, 'HARD_LIMIT': 2, 'N/A-route': 57, 'PASS': 9, 'UNVERIFIED': 16, 'MISSING': 4}
```

No other row moved. The other **16** `UNVERIFIED` rows each carry a
`Missing evidence (W9-P0):` sentence, and no scored row does
(`UNVERIFIED without Missing-evidence: []`, `Missing-evidence on non-UNVERIFIED: []`).
The sentences are specific (an in-engine master-bus `AudioEffectCapture` at
48 kHz, an RMS/peak window, a soloed bus, a logged surface key, a 0.2 s
quiet-vs-sprint HUD capture with the noise level logged), not "TBD".

### C.4 AU1-03's evidence is real — with one overclaim

`game/tests/test_audio_mix.gd:126-147` is exactly `_test_loading_silence`. It
asserts, after `begin_loading_silence()`: loading active; `active_emitters()==0`
("loading stops every authored emitter"); `active_bed_levels().is_empty()`
("loading stops every bed"); `not is_music_playing()`; Ambience bus muted; SFX
bus muted; then after `end_loading_silence()`: loading cleared, Ambience
unmuted, emitters still stopped. So it does assert every bed/emitter/music
stopped, and the Ambience and SFX bus mutes with the Ambience restore.

Two precision problems, both in the *explanatory* sentence, not in the score:

1. The test asserts the **Ambience and SFX** bus mutes; the **Music** bus mute
   (and its restore) is in `audio_manager.gd:1514-1535` (`for bus_name in
   [BUS_AMBIENCE, BUS_SFX, BUS_MUSIC]`) but is **not asserted** by lines
   126-147. The row says "the Ambience/SFX/Music buses are muted", which is true
   of the code, not of the cited test.
2. "so the device output is digital zero" is an **inference** from the mutes,
   not a measurement: nothing in the test captures the device/master output, and
   the UI bus is not muted. A `AudioEffectCapture` on Master would be needed to
   claim zero at the device. The row's own `Missing evidence` convention asks for
   exactly that instrument elsewhere (AU1-01, V2-05).

Neither changes the DELTA verdict: stopping every bed/emitter/music and muting
the three gameplay buses does reach the row's silence, and the 0 s hard mute vs
the official 2.84 s fade is a genuine delta. Also worth recording: this test is
**not wired into any gate** (`run_tests.gd`, `make test`, E2E and the Makefile do
not reference it; it is a standalone `--script res://tests/test_audio_mix.gd`).
I ran it manually (see D) — it passes — but the scorecard should not imply it is
gated.

**C: PASS**, with the AU1-03 wording flagged as above: the one score move is
evidence-backed, the tally and the 120-row template order recount exactly, and
the 16 remaining UNVERIFIED rows all name their missing instrument.

---

## D. GATE HYGIENE — AUDIT: PASS

Re-run serially under the shared lock (`/tmp/opencode/w9_audit_logs/*.log`),
one Godot at a time; CPU/GPU-only gates run in the same sequence.

### D.1 My re-run vs the floors

| Gate | Command | My output | Floor | Verdict |
|---|---|---|---|---|
| compile | `tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"` | `scripts checked: 152, broken: 0` | 152 / 0 | PASS |
| run_tests | `… --script res://tests/run_tests.gd` | 301 `^PASS` lines, `SUMMARY: fails=0`, 0 `^FAIL` | 301 / fails 0 | PASS |
| M2 | `… --script res://tests/test_m2_player.gd` | 12 `^PASS`, `M2_SUMMARY: fails=0` | 12 | PASS |
| E2E | `… --script res://tests/e2e/run_e2e_tests.gd` | 278 `^PASS: [`, 0 `^FAIL: [`, `SUMMARY: fails=0 passed=278 total=278` | 278 / 278 | PASS |
| door walk | `… --script res://tests/probe_door_walk.gd` | `DOORWALK PASS` | `DOORWALK PASS` | PASS |
| viewmodel | `… --script res://tests/probe_viewmodel_truth.gd` | `VIEWMODEL_TRUTH PASS zip_emissive=off top_emissive=off crank_bone=crank_arm posed=true reset=true` | `VIEWMODEL_TRUTH PASS` | PASS |
| Niagara | `… --script res://tests/probe_niagara.gd` | `NIAGARA_PROBE PASS` | `NIAGARA_PROBE PASS` | PASS |
| blackjack | `… --script res://tests/probe_blackjack_race.gd` | `BLACKJACK_PROBE PASS fails=0` | `BLACKJACK_PROBE PASS` | PASS |
| geometry | `… --script res://tests/probe_geometry_placement.gd` | `GEOM_PROBE PASS`, `checks=7 fails=0` | `GEOM_PROBE PASS` | PASS |
| probe_leak | `TAT2_NO_DEN_PROBE=1 … --script res://probe_leak.gd` | `PROBE start players=0`, `PROBE after gh free players=0`, 0 `leaked at exit`/`SCRIPT ERROR` | `PROBE start`, clean | PASS |
| audit | `make audit` | `AUDIT PASS`, `12660/12703 (99.7%)`, unexpected 0, `CONSUMER AUDIT PASS`, baseline matches | ≥12657/12703, unexpected 0 | PASS |
| texture cap | `make texture-cap-check` | `capped: 797`, `alpha-critical …: 1`, `offenders: 0`, `texture cap check: OK` | 0 offenders | PASS |
| perf guard | `build/qa/test_perf_guard.sh` | `PERF_GUARD_TEST PASS checks=78 fails=0` | 78 | PASS |
| ratchet | `make gate-ratchet` | `GATE_RATCHET: PASS`, exit 0 | PASS | PASS |

Note on `run_tests.log`: it contains two pre-existing
`SCRIPT ERROR: Trying to assign an array of type "Array[PhysicsBody3D]" to a
variable of type "Array[RID]"` at `audio_manager.gd:712` (`_occluded`), triggered
by `security_beam._fire`. The committed `docs/reports/logs/r8/run_tests.log` has
the same two, so this is baseline noise, not a W9-P0 regression; the gate's
`SUMMARY: fails=0` is unaffected. It is still a real runtime type error that
makes the audio-occlusion path return early — worth an owner, outside this wave.

### D.2 Raw summaries from my run (`/tmp/opencode/w9_audit_logs/`)

```
compile            scripts checked: 152, broken: 0
run_tests          301 ^PASS, 0 ^FAIL, SUMMARY: fails=0
m2                 12 ^PASS, M2_SUMMARY: fails=0
e2e                278 ^PASS: [, 0 ^FAIL: [, SUMMARY: fails=0 passed=278 total=278
probe_door_walk    DOORWALK PASS
probe_viewmodel_truth  VIEWMODEL_TRUTH PASS zip_emissive=off top_emissive=off crank_bone=crank_arm posed=true reset=true
probe_niagara      NIAGARA_PROBE PASS
probe_blackjack_race   BLACKJACK_PROBE PASS fails=0
probe_geometry_placement  GEOM_PROBE PASS checks=7 fails=0
probe_leak         PROBE start players=0 / PROBE after gh free players=0; 0 "leaked at exit", 0 "SCRIPT ERROR"
```

Extra (C evidence, not a W9-P0 gate): `… --script res://tests/test_audio_mix.gd` →
`AUDIO_MIX_SUMMARY: fails=0 passed=49`, including the nine `T03.2` loading-silence
assertions (active / emitters 0 / beds empty / music stopped / Ambience muted /
SFX muted / clears / Ambience unmuted / emitters stay stopped). This confirms the
AU1-03 evidence is live — and confirms it does **not** assert a Music-bus mute.

### D.3 Ratchet evidence and the `>=` proof

- Every log named in `tools/gate_ratchet.json` exists under
  `docs/reports/logs/r8/` (13/13: compile, run_tests, m2, e2e, probe_leak, audit,
  texture_cap, perf_guard, probe_door_walk, probe_viewmodel_truth, probe_niagara,
  probe_blackjack_race, probe_geometry_placement) and contains the summary the
  checker matches — `make gate-ratchet` PASSes on them.
- The checker compares counts with `>=` (`minimums` + `passes_key`), and a lower
  count cannot pass. Proven against a copy in `/tmp/opencode/ratchet_probe`
  (repo untouched):
  - `compile.checked` 152 → **153**: `FAIL: compile.log records compile.checked=152, below the floor 153` (exit 1).
  - `run_tests.passes` 301 → **302**: `FAIL: run_tests.log records 301 PASS, below the run_tests floor 302` (exit 1).
  - lowering `compile.checked` to 151 passes the log check (`152 >= 151`), so the
    comparison is a floor, not a hidden equality.
  `broken/fails/unexpected/offenders` remain literal zeros, `e2e.passed` must
  equal `e2e.total`, and the report must quote the ratchet values (the negative
  test also trips the report check).

### D.4 No floor lowered

`git diff HEAD~2 -- tools/gate_ratchet.json`: compile 120→152, run_tests 278→301,
M2 11→12, E2E 278→278 (unchanged), audit 12657→12660, texture capped 773→797,
perf_guard added at 78. Nothing is lower than the brief's floors
(152 / 301 / 12 / 278-278 / ≥12657-12703 / 0 offenders / 78).

### D.5 No `game/` change, no test weakened

`git diff HEAD~2 -- game/ | wc -c` → `0`; `git diff --name-only -- game/` → empty;
`git status --porcelain` shows only the scorecard modification plus the three
read-only data symlinks (`extracted`, `game/assets`, `game/data/generated`). No
test file was added, skipped, weakened or deleted.

### D.6 Consumer allowlist

`tools/consumer_allowlist.json`: 28 → 26 `"glob"` entries, exactly two removed
and none added or otherwise edited:

- `tables/Art/UI/Icons/**` — consumed at runtime:
  `game/src/ui/input_glyphs.gd:19` `GLYPHS_PATH =
  "res://data/generated/tables/Art/UI/Icons/DT_InputKeysToGlyphs.json"`, used by
  `input_context.gd`, `input_rebinder.gd`, `settings_ui.gd`.
- `vfx/*.json` — consumed at runtime: `game/src/core/vfx/niagara_library.gd:19`
  `SYSTEMS_PATH = "res://data/generated/vfx/systems.json"`, read in
  `ensure_loaded()` and called from `level_loader.gd:5906/5968/5973/6014`
  (plus `probe_niagara.gd`).

Removing two stale exemptions is the audit-prescribed fix; `make audit` prints
`CONSUMER AUDIT PASS` with no `STALE RULE`.

---

## Verdicts

- **A. CAPTURES — PASS**
- **B. PERF MATRIX — FAIL** (absolute interior FPS 69.1/69.9 and 43.9/43.6 vs
  reported 71.8–73.7 and 45.6–46.7; AO delta, frames=240, AO flags and the
  98 °C pre-warm abort all verified; "display-capped" is mislabelled)
- **C. SCORECARD — PASS** (AU1-03 wording overclaims the Music-bus mute and
  "device output is digital zero"; the test is ungated)
- **D. GATE HYGIENE — PASS**
