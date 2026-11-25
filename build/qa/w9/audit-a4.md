# W9-P1 A4 — independent audit (camera, composition, stage grade, interior bracket, guard, scorecard)

Auditor: independent A4 subagent. Worktree `/home/john/Projects/TAT-2-rem-w9-p1`
(`rem/w9-p1`), HEAD `5a516f9`. Read-only: no edits, no git writes, no producers.
The one file written is this one.

Method: source reads, `git show`/`git diff`, `python3 build/qa/w9_frame_stats.py`
re-measurement of the committed PNGs, `magick compare -metric RMSE`, one
headless `res://tests/test_t05_ui_contract.gd` run. **No GPU capture was run**
(not needed: the evidence PNGs are present and are re-measured below).

Working tree at audit **start** (≈11:18) was dirty with three tracked files
(`M build/qa/w9_capture.gd`, `M game/data/expansion/prep_skyline.json`,
`M game/src/ui/mission_prep_ui.gd`). At that moment the `mission_prep_ui.gd`
diff was comment-only, the JSON added one `notes` string with `pieces`
byte-identical, and the capture script relabelled a `freed=` print.

**The tree then changed under me during the audit.** By 11:26
`mission_prep_ui.gd` had gained an uncommitted `if preset.is_empty(): return`
guard in `_apply_stage_grade` (HEAD `b57bbf7` has **no** such guard — verified
with `git show HEAD:…`), and four other files became modified by other lanes
(`game_data.gd`, `e2e_tier1_features.gd`, `probe_niagara.gd`,
`consumer_allowlist.json`). HEAD stayed `5a516f9`, so the committed code and the
captures I audited are unchanged; the uncommitted guard is inert in the captures
(the preset loads, and the guard prints only on a missing preset). All source
line citations below are **HEAD** line numbers.

---

## 1. The camera did not move — AUDIT: PASS

`git diff c2a1cd8..HEAD -U0 -- game/src/ui/mission_prep_ui.gd | grep -E '^[+-]const LOBBY_'`
prints **nothing** (`NO CAMERA/THIEF CONST LINE CHANGED`). The constants are
identical at both revisions:

```
LOBBY_CAM_POS      = Vector3(12.6065, -0.16698, -1.05384)
LOBBY_CAM_FWD      = Vector3(-0.986184, 0.116419, 0.117848)
LOBBY_CAM_FOV      = 20.0
LOBBY_CAM_ROLL_DEG = -14.780165
LOBBY_THIEF_POS    = Vector3(-1.5871, 0.82, -0.7868)
LOBBY_THIEF_YAW_DEG= 45.0
```

The only added reference to `LOBBY_THIEF_POS` is the composition distance test
(`mission_prep_ui.gd:828` at HEAD), not a value change. The camera setup block
(`cam.position = LOBBY_CAM_POS`, `fov`, `look_at_from_position`, roll) is
untouched; the camera setup line numbers moved only because the grade block was
replaced. The diff contains only the grade/composition constants, the two new
functions, the band constants and the call sites.

---

## 2. The composition rule — AUDIT: PASS

`_apply_stage_composition()` is `mission_prep_ui.gd:805-836` (HEAD), called from
`_build_stage` after `_add_prep_skyline` and **before** the thief anchor,
`_add_thief` and `_build_stage_character_lights` are created.

(a) **Never touches the camera.** The function body contains no `cam`/`camera`
reference at all (`sed -n '/func _apply_stage_composition/,/^func _stage_draw_nodes/p' | grep -niE 'cam|camera'`
→ no match). This is structural, not a comment.

(b) **Skips `prep_skyline` by group.**
```gdscript
if gi.is_in_group(PREP_SKYLINE_GROUP):
    continue
```

(c) **Distance rule, named radius.**
```gdscript
const LOBBY_STAGE_KEEP_RADIUS_M: float = 9.0          # mission_prep_ui.gd:153
...
var world: AABB = gi.global_transform * gi.get_aabb()
var nearest: Vector3 = world.get_center().clamp(world.position, world.end)
if LOBBY_THIEF_POS.distance_to(nearest) <= LOBBY_STAGE_KEEP_RADIUS_M:
    kept += 1
else:
    gi.visible = false
    hid += 1
```
It is the nearest point of the world AABB to the authored thief slot, i.e. a
mesh survives if any part of its AABB is within 9.0 m. Only
`GeometryInstance3D` draw nodes are touched; lights/particles are not hidden,
which is consistent with "the lobby geometry" wording.

(d) **Honours `TAT2_PREP_STAGE=legacy`.**
```gdscript
var mode: String = OS.get_environment(LOBBY_STAGE_ENV).strip_edges().to_lower()
if mode == "legacy":
    ...
    print("TAT-2 prep stage: kept=%d hid=0 radius=%.1f legacy=1" % [all_n, LOBBY_STAGE_KEEP_RADIUS_M])
    return
```

(e) **Counts and prints.** Authored run, `build/qa/w9/logs/cap_p1_after_prep.log:66`:
```
TAT-2 prep stage: kept=19 hid=397 radius=9.0
```
Legacy run, `/tmp/opencode/p1cap_legacy.log:66` (also copied at
`build/qa/w9/logs/cap_p1_after_legacy.log:66`):
```
TAT-2 prep stage: kept=422 hid=0 radius=9.0 legacy=1
```
`kept=19 + hid=397 = 416` non-skyline draw nodes; the 8 skyline nodes are
skipped (the same log prints `TAT-2 prep skyline: placed 8/8 expansion pieces
(group=prep_skyline)` at line 65). The legacy branch counts only
`is_visible_in_tree()` nodes (422), so it is not a like-for-like total with the
authored branch's 416 + 8 skipped; the marker that matters is `hid=0 legacy=1`,
which proves the authored rule was bypassed.

Caveat (not a failure): the earlier `prep_ledge` diagnostic reported
`kept=21`, 2 more than the shipped rule's 19. The diagnostic ran *after* the
stage was fully built and therefore also saw the thief's own mesh nodes near
the anchor; the shipped rule runs before the thief exists, so it cannot hide the
subject. This is the correct ordering, not a discrepancy in the rule.

---

## 3. The statistics — AUDIT: PASS (one 0.02 % RMSE transcription note)

Re-measured with `python3 build/qa/w9_frame_stats.py` (L1 pipeline: magick
grayscale, 480 px, `%<8` = `hist[:8]`), all 1920×1080 sRGB:

| PNG | mean | p50 | p95 | %<8 | %<16 | commit claim |
|---|---:|---:|---:|---:|---:|---|
| `p1_before_prep.png` | 37.2 | 25 | 128 | 7.1 | 34.1 | 37.2 / 25 / 128 / 7.1 ✔ |
| `p1_after_prep.png` | 37.1 | 19 | 125 | 18.8 | 43.7 | 37.1 / 19 / 125 / 18.8 ✔ |
| `p1_after_legacy.png` | 27.2 | 12 | 117 | 16.6 | 64.3 | 27.2 / 12 / 117 / 16.6 ✔ |
| `p1_after_nosky.png` | 43.9 | 29 | 126 | 8.8 | 33.4 | 43.9 / 29 / 126 / 8.8 ✔ |

The deltas also reproduce: after − nosky = **+6.8 mean / +10 p50 / +10.0 points
%<8** (the skyline darkens the mid-ground), and after − legacy = **+9.9 mean /
+7 p50** with the sky present only in the authored-composition frame.

Skyline visibility:
```
magick compare -metric RMSE p1_after_prep.png p1_after_nosky.png null:
5975.58 (0.0911815)      # 9.118 %
```
The claim is "5977 (9.1 %)"; my exact value is **5975.58**, i.e. 1.42/65535 =
0.002 % below the stated integer. The percentage and the materiality claim are
exact; the 5977 is a rounding/transcription slip (5975.58 rounds to 5976, not
5977). `-alpha off` and `-colorspace sRGB` give the same 5975.58.

The P0 comparison is documented in the committed audit report:
`build/qa/w9/audit-report.md:91-92` — `959.386 (0.01464)` for prep vs
prep_nosky. 1.5 % vs 9.1 % supports "freeing the group now moves the frame
materially". The P0 wording "zero visible pixels" is an overstatement in the
strict sense (959 RMSE is not zero), but the P0 report and the audit both call
it "statistically identical", so the material comparison stands.

Capture provenance check: `cap_p1_after_prep.log` has `W9_ENV scene=prep …
tonemap=4 exposure=1.150`; `cap_p1_before_prep.log` has `exposure=2.600` and no
`prep grade`/`prep stage` line (pre-change build). `cap_p1_after_nosky.log`
prints `placed 8/8` at line 65 and `W9_DIAG prep_nosky freed=0` at line 68.
In the committed script, that print is the **remaining** count after
`queue_free()`, so `freed=0` means all 8 were removed; the dirty working-tree
fix relabels it (`freed=8 remaining=0`). The 9.1 % RMSE independently proves
the group removal changed the frame.

---

## 4. The band contract — AUDIT: PASS

`prep_skyline.json` (committed at `b57bbf7`) has 8 pieces, all with
`base_y` 18.36–35.06, distances 260–400 m; the composition band is
`[0.28, 0.46]`, width ≤ 0.60.

I ran the real test headless under the flock:
```
tools/godot --headless --path game --script res://tests/test_t05_ui_contract.gd
```
T05.P14 lines (verbatim, in spawn order):
```
T05.P14 PrepSkyline_mid_roofline_a x=0.468..0.962 top=0.420 bottom=0.937 w=0.493 overlap=0.493 ok=true
T05.P14 PrepSkyline_mid_roofline_b x=0.622..1.202 top=0.380 bottom=0.924 w=0.580 overlap=0.378 ok=true
T05.P14 PrepSkyline_far_row_west x=0.329..0.799 top=0.440 bottom=0.935 w=0.471 overlap=0.471 ok=true
T05.P14 PrepSkyline_far_row_east x=0.777..1.084 top=0.400 bottom=0.808 w=0.307 overlap=0.223 ok=true
T05.P14 PrepSkyline_clocktower_west x=0.690..0.801 top=0.300 bottom=0.845 w=0.112 overlap=0.112 ok=true
T05.P14 PrepSkyline_clocktower_east x=0.894..0.984 top=0.330 bottom=0.736 w=0.090 overlap=0.090 ok=true
T05.P14 PrepSkyline_smokestack_row x=0.831..0.928 top=0.340 bottom=0.739 w=0.097 overlap=0.097 ok=true
T05.P14 PrepSkyline_urban_tower_east x=0.954..1.051 top=0.360 bottom=0.765 w=0.097 overlap=0.046 ok=true
PASS: T05.P14 every skyline piece is inside the tracked band (w <= 0.60, top in [0.28, 0.46])
...
T05_SUMMARY: fails=0 checks=56
```
All tops are inside [0.28, 0.46]; max width 0.580 ≤ 0.60; every overlap > 0.
The measured set is exactly the commit's set (0.300/0.330/0.340/0.360/0.380/
0.400/0.420/0.440). The commit's "p50 0.380" is the **upper** median; the
arithmetic median of the 8 tops is 0.370 and the mean is 0.37125 (closer to
KF11's 0.372), so the claim is a defensible order-statistic label, not a
mistake that affects the band.

The assertion was **changed with evidence, not deleted**. `git show b57bbf7 --
game/tests/test_t05_ui_contract.gd` shows only comment lines plus the added
`print(...)`; the `_check(bad.is_empty(), "T05.P14 every skyline piece is inside
the tracked band …")` line is unchanged. The new comment names KF11's
`p50 sy 0.372` and states the old band `[0.65, 0.98]` "rendered zero visible
pixels (prep vs prep_nosky identical: build/qa/w9/p0-report.md §A1)". The
bounds themselves moved in `mission_prep_ui.gd`
(`PREP_SKYLINE_TOP_MIN/MAX 0.65/0.98 → 0.28/0.46`), which the test reads from
the script, so the P14 numbers above are the real assertion, not a loosened
one. (P13 still requires exactly 8 pieces.)

---

## 5. The stage grade — AUDIT: PASS (with a false comment / undisclosed colour change)

`stage_grade_values()` **is used**, not four constants:
`mission_prep_ui.gd:775-797` (HEAD) calls
`var grade: Dictionary = WeatherProfile.stage_grade_values(preset)` and applies
`tonemap_mode`, `tonemap_exposure`, `ambient_light_color`, `ambient_light_energy`,
`glow_intensity`, `background_energy_multiplier`. The four old constants
(`STAGE_EXPOSURE`, `STAGE_AMBIENT_ENERGY`, `STAGE_GLOW_INTENSITY`, and the old
`STAGE_SKY_ENERGY = 0.18`) are gone (`git diff … | grep -c '^-const STAGE_…'` = 4);
the remaining `STAGE_AMBIENT_COLOR / STAGE_GLOW_BLOOM / STAGE_GLOW_HDR_THRESHOLD /
STAGE_SKY_ENERGY = 1.0` are fallback/refinement constants, not the four-value
grade.

Live log (identical in `cap_p1_after_prep.log:34`,
`cap_p1_after_nosky.log:34`, `cap_p1_after_legacy.log:34`,
`/tmp/opencode/p1cap_legacy.log:34`):
```
TAT-2 prep grade: tonemap=4 exposure=1.150 ambient=0.350 glow=0.1267 sky=1.000
```
Those are the authored values: `NIGHT_EXPOSURE = 1.15`, `sky.intensity 5.0 ×
0.08 = 0.40` clamped to `AMBIENT_ENERGY_MAX 0.35`, `bloom_intensity 6.336 ×
0.02 = 0.12672`, `background_energy_multiplier 1.0 × STAGE_SKY_ENERGY 1.0`.

`weather_profile.gd` has **zero diff** vs `c2a1cd8`
(`git diff --stat c2a1cd8..HEAD -- game/src/core/weather_profile.gd` → empty,
0 lines). `rg -n "INTERIOR_" game/src` → **no matches**; no dead `INTERIOR_*`
constant or env var. The interior branch is gone.

**Finding F5 (non-blocking, documentation/behaviour):** the new code comment at
`mission_prep_ui.gd:781-782` (HEAD) says "The preset authors no sky.light_color, so the
dictionary's ambient colour is null there; the stage keeps the moonlit blue it
has always used." This is **false** for `midnight_clear_mission_lobby`: its JSON
has `sky.light_color = [0.4431, 0.498, 1.0]`; `ambient_color()` returns that
`Color`, so `_apply_stage_grade` sets `env.ambient_light_color =
(0.4431, 0.498, 1.0)`, replacing the old hardcoded `(0.42, 0.50, 0.72)`. This is
the *authored* colour (defensible, arguably more authored than before) and does
not affect the printed numeric grade, but the comment claims the opposite and
the colour change is not named in the commit/report. Also, the
`stage_grade_values()` doc block at `weather_profile.gd:573-576` still says the
stage "hard-codes ACES 2.6 / ambient 1.8" — stale now that it is adopted; it
could not be fixed without breaking the intended byte-identical revert.

---

## 6. The interior BLOCKED claim — AUDIT: PASS

Re-measured all required PNGs (L1 pipeline, 1920×1080) against the A4 report
table `build/qa/w9/p1-report.md` §0.2:

| pose | report 1.15 | re-measured 1.15 | report 0.44 | re-measured 0.44 |
|---|---|---|---|---|
| gate | 23.2 / 10 / 66 / 23.9 | **23.2 / 10 / 66 / 23.9** | 12.5 / 3 / 40 / 72.0 | **12.5 / 3 / 40 / 72.0** |
| upper_foyer | 50.4 / 34 / 182 / 0.8 | **50.4 / 34 / 182 / 0.8** | 28.8 / 15 / 130 / 8.0 | **28.8 / 15 / 130 / 8.0** |
| yaw180 | 40.5 / 31 / 105 / 2.3 | **40.5 / 31 / 105 / 2.3** | 21.5 / 13 / 73 / 22.4 | **21.5 / 13 / 73 / 22.4** |
| foyer | 31.5 / 32 / 58 / 1.3 | **31.5 / 32 / 58 / 1.3** | 15.0 / 13 / 34 / 36.1 | **15.0 / 13 / 34 / 36.1** |

All four numbers in each cell reproduce exactly, including the gate's 23.9 →
72.0 %<8 and yaw180's 22.4 %<8. The `grade4_upper_foyer_e044_a100_nofill.png`
photo also reproduces the report's fill A/B exactly: **22.7 / 9 / 131 / 32.2**
(report 22.7 / 9 / 32.2), vs 28.8 / 15 / 8.0 with fills on. I also measured
`grade4_yaw180_e044_a100_nofill.png` = 20.3 / 12 / 70 / 24.5, matching the
report's "21.5 → 20.3", and `grade4_upper_foyer_e050_a100_nofill.png` =
24.7 / 10 / 136 / 22.0.

**Fill attribution is supported.** `mission_controller.gd:564-580`
(`_add_guildhall_foyer_fills`) creates exactly two shadowless omnis at
`(27,31,-53)` energy 1.6 and `(27,31,-64)` energy 1.3, range 16, attenuation
1.2, registered with `light_probe` — 3.3 m and 14.1 m from the upper-foyer eye
`(27, 29.67, -50)`. `w9_grade_probe.gd:136-147` frees every node named
`GuildhallFoyerFill_*`; `grade4.log` records `fills=off` and `W9_GRADE fills
freed=2`. The A/B changes only those two nodes at a constant exposure and moves
`upper_foyer` 28.8 → 22.7 mean / 15 → 9 p50 / 8.0 → 32.2 %<8, while yaw180
(looking the other way) moves only 21.5 → 20.3 / 22.4 → 24.5. The room-local
attribution is sound.

**"No preset-wide exposure can satisfy both rooms" is supported.** At 1.15 the
upper_foyer is too bright (p50 34 vs the 13-15 target) while the gate is too
dark (p50 10 vs the KF16/KF18 26-28 target, i.e. the T07 report's 0.10-0.11
normalized reference at `docs/reports/remediation-20261125/T07-render.md:176-177`);
lowering exposure to 0.44 lands the upper_foyer at p50 15 but crushes the gate
to p50 3 / 72.0 %<8. Both rooms respond monotonically in the same direction to a
single preset-wide exposure, so no scalar can move one down and the other up.
The report's "the interior band is BLOCKED-ON P2" conclusion follows. One honest
bound: at 0.44 with the fills freed, upper_foyer overshoots the other way
(p50 9 / %<8 32.2, outside the 13-15 / 9-24 band), so the fills are a necessary
part of the fix, not a complete one; the report says the fills "own that pose's
overshoot", which is exactly what the A/B shows.

---

## 7. Suite 98 — AUDIT: FAIL

**Content/attribution is correct.** Suite 98 is `run_tests.gd:7414-7489`,
added by `bb37003` (A2's commit, which names it as "A4a's suite 98" in its
message). Its comment is the W9-P1-A4 investigation outcome: "NO code change
made", the 2× interior overshoot, the gate ladder 23.9 → 38.0 → 51.9 → 62.2
%<8, the two fills, and the BLOCKED-ON P2 conclusion. The assertions are the
described ones: AGX, `tonemap_exposure == NIGHT_EXPOSURE`, ambient `0.16`
(literal), Den `max(1.0+bias, floor)`, old_manor not a night preset, and
exactly one map (`guildhall`) resolving to `gloomy`. The pass line in the
lead's final log is `/tmp/opencode/p1_final_suite.log:846186`
(`PASS: 98 W9-P1-A4 night-grade guard (guildhall keeps AGX 1.15 / ambient 0.16, …)`)
with `SUMMARY: fails=0` at 846188. There is no drift after `bb37003`
(`git diff bb37003..HEAD -- game/tests/run_tests.gd` has no suite-98 lines).

**It is not vacuous.** If `preset_for_map()` returned `{}` for every map,
`apply_for_map()` returns false (the weather apply refuses an empty preset), so
check (a) fails with "guildhall not graded AGX"; a missing
`map_weather.json`/empty `maps` fails (e) because `w9_gloomy.size() != 1`. A
null `weather_profile.gd` fails. The ambient pin is a literal `0.16`, so a
global ambient cut is caught.

**But it does not fail for a global exposure cut made at the constant.** The
assertions are self-referential:

```gdscript
var w9_floor: float = float(w9_wp.NIGHT_EXPOSURE)          # 1.15
var ok_gh := w9_wp.apply_for_map(e_gh, m_gh, "guildhall")  # exposure = max(1.0+0.0, floor)
if not is_equal_approx(e_gh.tonemap_exposure, w9_floor): …  # (a)
…
if not is_equal_approx(e_lob.tonemap_exposure, w9_floor): … # (b) lobby bias -0.5 → max(0.5, floor)
var w9_den_expected := maxf(1.0 + w9_den_bias, w9_floor)    # (c) bias 0.5 → both sides 1.5
if not is_equal_approx(e_den.tonemap_exposure, w9_den_expected): …
```

With `NIGHT_EXPOSURE = 1.00` (a 13 % global cut):
- (a) guildhall = `max(1.0, 1.00)` = **1.00** == `w9_floor` → PASS;
- (b) lobby = `max(0.5, 1.00)` = **1.00** == `w9_floor` → PASS;
- (c) Den = `max(1.5, 1.00)` = **1.50** == `w9_den_expected` → PASS;
- (d)/(e) unaffected; AGX and ambient 0.16 unchanged; → **suite 98 PASSES**
  (the PASS line would print "AGX 1.00" and still be green).

The same holds for any `NIGHT_EXPOSURE` in **[1.0, 1.15]**: guildhall's own
`1.0 + 0` and the lobby's `1.0 − 0.5` are both ≤ the floor, so
`max(preset, floor) == floor` for the first two, and the Den check is
tautological for every floor (both sides read the same preset bias and floor).
The guard only fails for a floor **below 1.0** (the guildhall preset's own 1.0
then exceeds it), for a change to the *applied* value after the `maxf` (e.g. a
multiplier in `apply_environment`), or for an ambient change. The other existing
R07 checks are equally relative to `NIGHT_EXPOSURE` (`probe_render_t07.gd:361`
`>= NIGHT_EXPOSURE`, `:393` `== NIGHT_EXPOSURE`), so nothing else catches a
constant cut.

The report's claim at `p1-report.md:315` — "so a future global cut fails by
design" — and the suite's own "fails if the night grade is lowered globally"
are therefore **false for the most natural implementation of a global cut**
(changing the authored anchor). The guard needs a literal pin (e.g. an
independent `1.15`/`0.16` assertion or a prep-stage value check) before that
claim is true; I did not change it.

---

## 8. The scorecard — AUDIT: PASS

Scripted recount over `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`
(§2 rows only, ID `^(V|AU|UI|G)\d+-\d+$`):

- rows **before** `ccd24d9` = 120, **after** = 120; unique IDs 120/120;
- the only score that changed is **V6-03 `N/A-route` → `DELTA`**; V4-07 stayed
  `DELTA` and only its Port observation text changed (the diff also updates the
  §5 tally and coverage prose, as expected);
- tally: `PASS 9, DELTA 33, MISSING 4, HARD_LIMIT 2, UNVERIFIED 16, N/A-route 56`
  = **120**; per pillar visual 6/14/1/2/1/13, audio 0/1/1/0/14/15,
  UI 2/12/1/0/1/11, gameplay 1/6/1/0/0/17 — all match the table;
- coverage `48 + 56 + 16 = 120`, scored `9+33+4+2 = 48`.

**The two rows' claims hold against the captures I opened.**
`p1_before_foyer_sweep_yaw180.png` (1920×1080) shows the tufted brown armchair
with the red/burgundy tufted ottoman in front of it, the white vitrine/cabinet
on the right with a framed portrait on its top, the white bust on a dark plinth
left of centre, the archway and the columns/pilasters. The armchair + ottoman
clause (V4-07) is true; the "white marble-topped" wording is a little generous
(the visible counter reads dark), and the flush floor plate / `Basement Stairs`
/ `WC` plaques are indeed not in the frame, so the row correctly stays DELTA.
`p1_before_upper_foyer.png` shows a bright horizontal beam band across the hall
at mid-height, passing through the doorway, with lit wall/ceiling practicals;
`p1_before_foyer_sweep_yaw180.png` shows the same beam as a diagonal volumetric
shaft from the ceiling. The V6-03 beam clause is true; the circular white wall
emitter at `x~17%, y~56%` and the cyan ceiling diamond are absent (the cyan
crosshair in the frame is the player reticle, not a ceiling node), so
N/A-route → DELTA is the right score.

---

## Per-item verdict

| # | item | verdict |
|---|---|---|
| 1 | camera/thief constants unmoved vs `c2a1cd8` | **PASS** |
| 2 | composition rule (no camera, skips skyline, 9 m rule, legacy, counted) | **PASS** |
| 3 | prep statistics + skyline materiality | **PASS** (RMSE 5975.58 vs claimed 5977; 9.1 % exact) |
| 4 | `[0.28, 0.46]` band, widths ≤ 0.60, P14 evidence | **PASS** |
| 5 | `stage_grade_values()` + authored live values; no `INTERIOR_*` | **PASS** (F5: false ambient-colour comment / undisclosed authored colour change) |
| 6 | interior bracket table + fill attribution + BLOCKED logic | **PASS** |
| 7 | suite 98 fails on a global exposure cut | **FAIL** (self-referential floor pin; 1.15 → 1.00 passes) |
| 8 | scorecard V4-07/V6-03, 120 rows, tally/coverage | **PASS** |

## Final verdict

**AUDIT: FAIL (1 of 8 items).** Seven items pass with every substantive numeric
claim reproducing: the camera is byte-identical to `c2a1cd8`, the 9 m cull is
a composition rule and not a reframe, the four prep PNGs match the commit to the
displayed precision, the skyline is now materially visible (9.1 % RMSE vs the
P0 1.5 %), P14 passes the re-authored band and widths on the real spawned
meshes, the stage grade is `stage_grade_values()` at the authored 1.15/0.35/
0.12672/1.0, the interior table and the fill A/B reproduce exactly, and the
scorecard is 120 rows / 9-33-4-2-16-56 / 48+56+16. The two numeric deviations
found are immaterial: RMSE 5975.58 vs the transcribed 5977, and "p50 0.380" is
the upper median of the 8 tops (arithmetic median 0.370).

The single failure is material to the guard claim: **suite 98 cannot fail for a
global exposure cut implemented at `NIGHT_EXPOSURE`** because every exposure
assertion compares the applied value to the same constant (the Den check is
fully tautological). Lowering the anchor from 1.15 to 1.00 — a 13 % global cut
that also lowers the prep stage — leaves the suite green. The report's
"a future global cut fails by design" needs an independent literal pin or a
narrower claim.

## Not verified / limits

- No fresh GPU capture was run; all frame statistics are re-measurements of the
  committed PNGs, and the 97 s one-launch grade8 claim was read from the log,
  not re-timed.
- The P0 `959.386` pair was not re-measured (the P0 pair is not in this
  worktree); it is quoted from `build/qa/w9/audit-report.md:91-92`.
- The suite-98 PASS/`SUMMARY: fails=0` line is from the lead's
  `/tmp/opencode/p1_final_suite.log`; I read the assertions and ran only the T05
  contract suite (56 checks, fails=0), not the full `run_tests.gd`.
- The prep stage's live ambient *colour* is inferred from
  `stage_grade_values()`/`ambient_color()` code (the preset's
  `sky.light_color`), not printed in any capture log, so F5's colour change
  (0.42,0.50,0.72 → 0.4431,0.498,1.0) is a code-path finding, not a pixel
  measurement.
- The capture logs do not stamp a commit hash. The captures predate `b57bbf7`
  (`p1_after_prep.png` 11:00:46, `p1_after_nosky.png` 11:10:57, commit
  11:11:32); correspondence is inferred from the log lines matching the
  committed print formats and from the dirty diff being comment/notes-only, not
  from a build stamp.
- The working tree was live during the audit: the prep file gained an
  uncommitted empty-preset early return at 11:26 (HEAD has none) and four other
  lanes' files became dirty; HEAD stayed `5a516f9`. The captures predate these
  edits; correspondence to HEAD is inferred from the committed print formats,
  not from a build stamp.
