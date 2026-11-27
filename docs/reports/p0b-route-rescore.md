# P0b route2 staged capture — re-score preparation (evidence index)

**Status:** preparation / evidence index only. **Not** a 120-row re-score. **Route claim:** `none`
(staged/mixed). **Prepared:** 2026-11-27. **Capture:** route2 — 13 of 27 beats captured, 14 deferred,
17 beat frames + 1 Lounge extra (18 PNGs, all 1920x1080). **Manifest:**
`docs/reports/logs/p0b-route/route2/manifest.json`
(`status=captured`, `mode=staged`, `route_claim=none`, `counts={captured:13, deferred:14, partial:0,
frames:17, frame_errors:0, extras:1}`, `git.sha=434143970f43`, `git.dirty=true`). The dirty flag is
the S06 ledger-tab fix that was uncommitted at capture time; it is commit `f44bc23` in the current
tree, so a **clean re-run is Phase 0b** (GPU).

**Provenance (Phase 0a, 2026-11-27):** `row_route_matrix.md` and `ADJUDICATIONS.md` moved out of the
git-ignored `build/qa/review_20261124/` and are now tracked under
`docs/reference/clip_1795033698901/`. The 2026-11-24 recording and its 281 frames remain **outside
git** (capture media is not committed). The scorecard's **official V6-03 cell** now carries a dated
erratum: emitter **17.8 %/40.0 %**, **one** band at **40.0–40.5 %**, cyan node **above the doors**;
the old 56 %/two-beam/ceiling text was a transcription error. The port-side cell and the 120 tally
are untouched.

**What this report is not.** It does not play a route, does not align a staged frame to an official
beat, and does not add or change a `PASS` / `DELTA` / `MISSING` / `HARD_LIMIT` / `N/A-route` token.
`docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` and
`docs/reference/clip_1795033698901/row_route_matrix.md` are unchanged by this report. No Godot,
Vulkan, Xvfb, Steam or game
build was launched for this report; the capture itself is the earlier owner run recorded in the
manifest, and this report only reads it plus the reference keyframes and the CPU scorer.

---

## 1. Method and claim boundary

### 1.1 Inputs read

| Input | Use |
|---|---|
| `docs/reports/logs/p0b-route/route2/manifest.json` | beat/frame provenance, per-frame median luma, audio marks, free-play disclosure |
| `build/qa/p0b_route/route2/*.png` (18 files) | the captured frames; all were opened and inspected with the image reader |
| `docs/reference/clip_1795033698901/clean/*.jpg` (30 files) | the official keyframes; KF01, KF12, KF14, KF27 and KF30 were opened directly for the comparisons below, the others are read through `KEYFRAME_INDEX.md` and the scorecard |
| `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` | the 120 rows and their existing observations/tally |
| `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` | official beat/keyframe mapping and the official observations |
| `docs/reference/clip_1795033698901/row_route_matrix.md` | row-to-beat observability (formerly `build/qa/review_20261124/`, moved in Phase 0a) |
| `docs/reports/p0b-route.md` | the runner's claim boundary and the scorer gap |
| `build/qa/p0b_roi_stats.py` | the luma / beam / cream / KF27-criteria scorer |

### 1.2 Claim boundary

- The capture is **staged/mixed**: live UI/API hooks on real scenes, fixed camera poses, and the
  audio tap's generic `mark()` only. `mark_beat` is never called (the manifest records
  `mark_kind=mark` on every beat and the runner's self-test rejects the other entry point), so a
  staged frame cannot claim a played-beat alignment. The official S01–S27 times are provenance
  anchors, not wall-clock alignment targets.
- **13 of 27 beats captured; 14 deferred.** A captured frame proves the scene/UI state at that pose.
  It does not prove a transition, an input, a duration, an NPC state, a played traversal or an audio
  event.
- **`route_claim=none`.** Nothing below is a played route.
- **No new row score.** A row is mentioned only because a captured frame shows its subject. Where a
  frame is not directly comparable, the row is left as `needs human visual review`,
  `not scorable from a staged frame`, or `frame captured, not scored` — never guessed.
- The existing 120-row tally is **not re-derived**. The 2026-11-24 tokens stay where they are; this
  report is an index of new visual evidence that a later scored wave may adjudicate.

### 1.3 Free-play substitute (staged, not the official selection)

The Guildhall stage is free play `Mission.Guildhall.LootTheRoom` on contract 2, used only to show
the KF13 letter over the live safe room. It is **not the official mission selection**. The canonical
contract-2 Guildhall row is `Mission.Guildhall.VaultHeist`; the 2026-11-24 port baseline ran
`LootTheRoom` on `Contract.Main.2` with `free_play=false`. The manifest records
`level.free_play_substitute=true`, `level.official_free_play=false`,
`level.historical_mission_id=Mission.Guildhall.LootTheRoom`,
`level.canonical_mission_id=Mission.Guildhall.VaultHeist`.

Consequences for this report:

- the S09 prep cards show the free-play form (`Cleanout Heist`, `Contract Inactive`);
- the S11 letter is over the free-play safe room;
- the S12 HUD tracker is the free-play loot counter (`Steal 4,000 in loot value[0/4,000]`), not the
  2026-11-24 contract form (`Into the Lion's Den [0/1]`).

Rows UI3-02, UI4-03 and G5-01 therefore carry a staged-substitute caveat wherever they appear below.
The staged combination must not be read as the official mission selection.

### 1.4 Status vocabulary used below

| Status | Meaning |
|---|---|
| `frame captured` | a real PNG exists, was non-black and 1920x1080; no row-level comparison is made |
| `quantified below` | the frame has a number in §3 that bears on the row's subject; still not a score |
| `needs human visual review` | the subject is visible and a human can compare it with the stated keyframe; no verdict is issued here |
| `not scorable from a staged frame` | the row needs a played transition, input, duration, NPC state or audio measurement that a fixed still cannot supply |

No `PASS` / `DELTA` token is assigned anywhere in this report.

---

## 2. Covered frames table

Frame files are under `build/qa/p0b_route/route2/` (git-ignored media). The row ids are the
scorecard's ids, not new rows. A row id is listed only where that frame shows the row's subject; it
does **not** mean the row is scored.

| Beat / frame | PNG | What the captured frame shows (viewed directly) | Official KF | Row ids with visible subject | Status |
|---|---|---|---|---|---|
| S01 startscreen | `S01_startscreen.png` | 3D startscreen backdrop only: close crop of the fully lit `Mac Neish / Jeweller` neon, amber awning tubes, purple faceted orb, gold scrollwork, rain streaks, a dark guard silhouette at the door. **No logo and no `PLAY/SETTINGS/CREDITS/QUIT` stack**; the wide street and crates of KF01 are not in this crop, and the bottom-left dark shape is not identifiable as the car fender. | KF01 | V1-01, V2-01, V3-04, V4-01, V5-01 | frame captured; needs human visual review. UI1-01 and V7-01 are **not scorable from this frame** (menu stack absent). |
| S02 loading 1 | `S02_loading_1.png` | KF12 art: indigo skyline, two dirigibles with yellow search cones, moon upper-right, `LOADING...`, **62% progress bar**, gold `THICK AS THIEVES` emblem. **No cyan spinner ring** (KF12 has one). | KF12 | V2-03, UI4-05 | frame captured; needs human visual review. UI4-05 is partial (emblem/LOADING present, spinner absent). |
| S03 Den entry | `S03_den_entry.png` | Synthetic Den-wide view: teal moon shaft through the leaded window, rolltop desk with a warm globe lamp, armoire, telescope at the window, wanted posters on the right wall, rafters, floorboards. A `CONSTABLES' GUILDHALL / Difficulty / Mode / Prepare` **map-table card overlays the centre-top**; `The Spider` level 1 card and the compass are visible. | KF02 | V1-02, V4-02, V4-03, G1-01, UI3-01 | frame captured; needs human visual review. The card is not in KF02; no `[F] PONDER` prompt is visible. |
| S04 wardrobe | `S04_wardrobe.png` | Full `WARDROBE` overlay: `[Q] The Spider` selected, `The Chameleon LOCKED`, `Edit Loadout` slots 1–4 (slot 3 pink padlock), `Zipwire` tooltip/description, 3D Spider turntable in a bowler hat, `Customizations` Head/Body/Calling Card, `BACK [ESC]`. No cap state, no slot-3 expanded 4-tool row, no Vistara Diamond tooltip. | KF03/KF04 | V5-02, UI2-02 | frame captured; needs human visual review. This is the KF03 state, not KF04's cap/slot-3 state. |
| S05 telescope sky | `S05_telescope_sky.png` | `KILCAIRN SKYLINE` card with `[F] EXIT`; marbled full moon upper-right, large pale-gold cheese wedge with 3 chunks over dark rooftop silhouettes, teal sky, faint stars. The **bottom ~19% of the frame is black** (the sky view does not fill the 1080-px height). | KF05/KF06 | V2-02, UI2-01, G1-01 | frame captured; needs human visual review. V7-02's cut timing is **not scorable from stills**. |
| S06 journal | `S06_journal.png` | `[Q] JOURNAL` selected, `BLACK MARKET [E]`, `BACK [ESC]`; The Spider level 1, `0/500` XP; three contract cards all marked `Active` (Contract #1, #2 *Into the Lion's Den*, #3 *Mary Elway's Papers*). | KF07 | UI4-01 | frame captured; needs human visual review. |
| S06 black market | `S06_black_market.png` | `BLACK MARKET [E]` selected; `YOUR TOTAL ASSETS: (£) 5,000`; Zipwire preview with `✓ PURCHASED`; four columns TOOLS / GUILD PERKS / SPIDER COSMETICS / CHAMELEON COSMETICS with ✓/padlock rows. The reference's visible `7,500 / 5,000 / 2,500` price rows are not visible in this crop. | KF08 | UI4-02 | frame captured; needs human visual review. |
| S08 map table | `S08_map_table.png` | `MAP TABLE — CONTRACT SELECTOR`: a 2D list of 16 contracts (`#01 Contract 1 (THIEVES' DEN)` … `#16`), Contract #1 selected, `Difficulty: Novice (1)`, Host/Join Co-op `127.0.0.1`, `Solo Mode`, `FREE PLAY: GUILDHALL CLEANOUT [G]`, `DEPLOY CONTRACT`, `CLOSE [ESC]`. **No 3D map table, tokens, banker's lamp or parchment** in this frame. | KF10 | G1-03 | frame captured; needs human visual review. UI3-06 and V1-03 are **not visible** here. |
| S08 confirm | `S08_confirm.png` | `Join Mission with these settings? / Difficulty: Novice / Mode: Solo`; `[H] Difficulty toggle · [R] Mode toggle · [SPACE/F] PREPARE`; `[SPACE] PREPARE FOR MISSION` / `[ESC] CANCEL`. The backdrop is the 2D selector, not the 3D table. | KF10 | G1-03 | frame captured; needs human visual review. The modal strings match the official observation; the 3D-token half of the row is absent. |
| S09 mission prep | `S09_mission_prep.png` | `MISSION STARTING IN 6...`, `Mode: Solo`, `Difficulty: Novice`; cards `CONSTABLES' GUILDHALL` / `Cleanout Heist` / `Time Limit: 55 minutes` / `Contract Inactive`; 3D Spider on a dark roof block under a moon; `READY`, `The Spider`, `[F] READY`, `[ESC] BACK`. | KF11 | UI4-03, UI5-05, G5-01 | frame captured; needs human visual review. Free-play form (`Contract Inactive`); G5-01's flow is a staged set of steps, not a played flow. |
| S10 loading 2 | `S10_loading_2.png` | Same KF12 art as S02 at **31%**; `LOADING...`, progress bar, gold emblem; no spinner ring. | KF12 | V2-03, UI4-05 | frame captured; needs human visual review. |
| S11 briefing letter | `S11_briefing_letter.png` | Parchment with a ~10-line body: `Esteemed Colleague – … 55 minute window … magic door will be summoned for 20 minutes before collapsing … We'll be in touch.`; right scrollbar; `[SPACE] CONTINUE`; a **live brick safe-room backdrop** with a `SPIDER` flyer and the green/violet portal edge at the right. | KF13 | UI4-04, V7-03, V6-01 | frame captured; needs human visual review. The body now contains the 55/20-minute copy the 2026-11-24 baseline lacked; the blur is not established; the body is ~10 lines vs the 11-line reference. |
| S12 safe room | `S12_safe_room.png` | Brick safe-room wall: large **green rectangular portal outline with a wavy violet inner edge**, a caged lantern (lit) and a `SPIDER` flyer; strong white bloom ellipses at the left; HUD `(£) 0`, `Mission: Steal 4,000 in loot val…[0/4,000]` (overprinted), `The Spider`, `[1][2][4]`, `TAB MAP/MMB/[HOLD] PING MENU`; ZipWire viewmodel lower-right. No `[F] TURN ON`/`[F] TURN OFF` prompt is visible. | KF14 | V6-01, V1-04, V5-03, UI3-02, UI3-05 | frame captured; needs human visual review. G1-05 is **not scorable** (no prompt/toggle shown). |
| S24 upper foyer | `S24_upper_foyer.png` | Forward foyer view: **one thick white beam band** across the doorway at ~49% frame height (occluded by the door jamb); gold wall emitter discs left/right (the right/beam disc has a cyan cross), checkered marble floor, dark panelled walls, `LAUNCH LMB` / `[HOLD] CRANK RMB`, ZipWire viewmodel. No cyan ceiling diamond. | KF27 | V6-03, UI2-03, V5-03 | frame captured; **quantified below**. |
| S24 yaw180 | `S24_yaw180.png` | Reverse foyer view: tufted armchair with a red ottoman, white marble-topped vitrine/console with a framed picture, bust on a plinth, archway down the hall; a large **magenta/pink thorny crystalline wall effect** on the left; one beam segment from a gold emitter on the right; `LAUNCH`/`CRANK` prompts. No two wall-to-wall beams. | KF27 | V4-07, V6-04, V6-03, UI2-03, V5-03 | frame captured; **quantified below**. The pink effect is not the reference's green vine lock and no beam-trigger lockdown occurred. |
| S24 foyer beam | `S24_foyer_beam.png` | Close oblique view of the left wall emitter (gold disc with a cyan four-point cross) and the beam leaving to the right at ~49% height; dark panelled wall, doorway to a lit room on the right; HUD. No cyan ceiling node. | KF27 | V6-03, UI2-03, V5-03 | frame captured; **quantified below (manifest stats only; no pose id)**. |
| S27 pause | `S27_pause.png` | `RESUME / SETTINGS / RETURN TO THIEF'S DEN / QUIT TO DESKTOP`, `[ESC] RESUME`, footer `1.5.148559   Novice   275275524`; a very dark backdrop with a faint blurred bright streak upper-right; no HUD widgets are legible behind the modal in this frame. | KF30 | UI1-02, V7-05 | frame captured; needs human visual review. G5-05's quit/teardown is **not scorable** (no selection, no silence tail). |
| Lounge extra | `extra_lounge_beam_close_pose.png` | Dark panelled interior/door with the HUD; **no C_57 beam is visible**. The pose looks along the beam's axis. The manifest labels it `Lounge C_57 beam`, `ref_keyframe=null`, `beat=""`; it is not S24/KF27. | none | none | frame captured; **not scorable from a staged frame**. |

All 18 PNGs are 1920x1080. The manifest's `png_size` is `[1920,1080]` for every one of the 17 beat
frames; the Lounge extra is in `extras[]` (which has no `png_size` field) and was confirmed 1920x1080
when viewed. The extra is not one of the 17 beat frames.

---

## 3. Quantitative look

### 3.1 Commands actually run

```bash
python3 build/qa/p0b_roi_stats.py --port build/qa/p0b_route/route2/S24_upper_foyer.png --pose upper_foyer
python3 build/qa/p0b_roi_stats.py --port build/qa/p0b_route/route2/S24_yaw180.png --pose yaw180
python3 build/qa/p0b_roi_stats.py --port build/qa/p0b_route/route2/extra_lounge_beam_close_pose.png --pose beam_close
```

The script and `w9_frame_stats` use ImageMagick (CPU) only. No GPU, Vulkan, Xvfb or Steam process
was started. `--all` / `--validate-manifest` were **not** used: the route manifest is
`tat2.p0b_route/1`, which the scorer rejects by design (`docs/reports/p0b-route.md` §3).

`S24_foyer_beam.png` has **no pose id** in the scorer's set, and no pose was invented for it. Its
only numbers are the manifest's `median_mean`, `median_lt8`, `median_peak`, compared below to the
published KF27 criteria. The Lounge extra uses `beam_close` because the manifest's note calls it the
p0b `beam_close` pose; its KF27 reference is nominal (the scorer's `beam_close` entry points at KF27)
and the manifest explicitly says the Lounge C_57 beam is not the S24/KF27 beam.

### 3.2 Exact stdout

<details>
<summary><code>upper_foyer</code> — full stdout</summary>

```
P0B_STATS kind=reference pose=upper_foyer file=/home/john/Projects/TAT-2/docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg mean=16.7 p50=15 p95=34 lt8=16.7 lt16=53.8 gt200=0.03
P0B_STATS kind=port pose=upper_foyer file=build/qa/p0b_route/route2/S24_upper_foyer.png mean=40.8 p50=29 p95=99 lt8=1.5 lt16=6.8 gt200=1.46
P0B_DELTA pose=upper_foyer d_mean=+24.1 d_p50=+14 d_p95=+65 d_lt8=-15.2 d_gt200=+1.43
P0B_BEAM pose=upper_foyer emitter_pct=(29.9,49.1) peak_row=49.07% excess=131.15 peaks=(49.1@131.2,43.5@5.1,38.8@1.4) core_px=61 glow_1pct=(+93.16,+88.57) core_sat_p95=0 cream_outside_band=1.39% cyan=(found=False,pct=0.000)
P0B_BEAM_REF pose=upper_foyer emitter_pct=(17.7,40.2) peak_row=40.19% excess=10.51 peaks=(40.2@10.5,35.7@2.1,34.8@2.0) core_px=19 glow_1pct=(+1.86,+2.57) core_sat_p95=35 cream_outside_band=0.12%
P0B_KF27 pose=upper_foyer met=4/7 emitter_box=false beam_row_band=false row_excess_ge_2=true glow_falloff=false core_neutral=true no_cream_slab_10pct=true cream_reference_like_2pct=true
P0B_CELLMAP pose=upper_foyer grid=16x9 cream=luma>=170,sat<=46 stride=2 unexplained=12
P0B_CELLMAP_LEGEND . ok  B brighter  D darker  c cream-in-both  C cream-unexplained  A allowed
P0B_CELLMAP_ROW row=0 . . . . . . . . . B B . B C C .
P0B_CELLMAP_ROW row=1 . . . . . . . . D . . . B C B . .
P0B_CELLMAP_ROW row=2 B B B B . . . B . . . . . . . .
P0B_CELLMAP_ROW row=3 B B B B . . . B . . . . . . . .
P0B_CELLMAP_ROW row=4 B B B B C C C C C C C C . . . .
P0B_CELLMAP_ROW row=5 B B B B . . B B . D . . . B B .
P0B_CELLMAP_ROW row=6 B . B B B B B B B B B B B B B B
P0B_CELLMAP_ROW row=7 . . B B B B B B B B B B B B B B
P0B_CELLMAP_ROW row=8 c c B B B B B . B B B B B B B C
P0B_CELLMAP_COUNTS brighter=68 cream_match=2 cream_unexplained=12 darker=2 ok=60 unexplained_cells=13,0,14,0,12,1,4,4,5,4,6,4,7,4,8,4,9,4,10,4,11,4,15,8
```

</details>

<details>
<summary><code>yaw180</code> — full stdout</summary>

```
P0B_STATS kind=reference pose=yaw180 file=/home/john/Projects/TAT-2/docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg mean=16.7 p50=15 p95=34 lt8=16.7 lt16=53.8 gt200=0.03
P0B_STATS kind=port pose=yaw180 file=build/qa/p0b_route/route2/S24_yaw180.png mean=43.9 p50=34 p95=131 lt8=2.7 lt16=12.2 gt200=0.76
P0B_DELTA pose=yaw180 d_mean=+27.2 d_p50=+19 d_p95=+97 d_lt8=-14.0 d_gt200=+0.73
P0B_BEAM pose=yaw180 emitter_pct=(23.9,42.1) peak_row=49.07% excess=25.24 peaks=(49.1@25.2,47.2@10.7,46.5@9.5) core_px=56 glow_1pct=(+13.64,+14.73) core_sat_p95=7 cream_outside_band=1.28% cyan=(found=True,pct=0.003)
P0B_BEAM_REF pose=yaw180 emitter_pct=(17.7,40.2) peak_row=40.19% excess=10.51 peaks=(40.2@10.5,35.7@2.1,34.8@2.0) core_px=19 glow_1pct=(+1.86,+2.57) core_sat_p95=35 cream_outside_band=0.12%
P0B_KF27 pose=yaw180 met=6/7 emitter_box=true beam_row_band=false row_excess_ge_2=true glow_falloff=true core_neutral=true no_cream_slab_10pct=true cream_reference_like_2pct=true
P0B_CELLMAP pose=yaw180 grid=16x9 cream=luma>=170,sat<=46 stride=2 unexplained=12
P0B_CELLMAP_LEGEND . ok  B brighter  D darker  c cream-in-both  C cream-unexplained  A allowed
P0B_CELLMAP_ROW row=0 . . . . . . . . . . . . B C C B
P0B_CELLMAP_ROW row=1 . . . . . . . D D . . C C B B B
P0B_CELLMAP_ROW row=2 B . . C B . . . . . C C B B B B
P0B_CELLMAP_ROW row=3 . . B C B . . D . . . B B B B B
P0B_CELLMAP_ROW row=4 . B . C C B . . . B C B B B B B
P0B_CELLMAP_ROW row=5 . . . B C . B B . . . . B B B B
P0B_CELLMAP_ROW row=6 . . . B B B B B B B B . B B B B
P0B_CELLMAP_ROW row=7 . . B B B B B B B B B B B B B B
P0B_CELLMAP_ROW row=8 c c B B B B B B B B B . B B B B
P0B_CELLMAP_COUNTS brighter=72 cream_match=2 cream_unexplained=12 darker=3 ok=55 unexplained_cells=13,0,14,0,11,1,12,1,3,2,10,2,11,2,3,3,3,4,4,4,10,4,4,5
```

</details>

<details>
<summary><code>beam_close</code> (Lounge extra) — full stdout</summary>

```
P0B_STATS kind=reference pose=beam_close file=/home/john/Projects/TAT-2/docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg mean=16.7 p50=15 p95=34 lt8=16.7 lt16=53.8 gt200=0.03
P0B_STATS kind=port pose=beam_close file=build/qa/p0b_route/route2/extra_lounge_beam_close_pose.png mean=20.2 p50=20 p95=29 lt8=1.1 lt16=24.5 gt200=0.15
P0B_DELTA pose=beam_close d_mean=+3.5 d_p50=+5 d_p95=-5 d_lt8=-15.5 d_gt200=+0.12
P0B_BEAM pose=beam_close emitter_pct=(0.0,0.0) peak_row=28.06% excess=0.47 peaks=(none) core_px=1 glow_1pct=(+0.46,+0.41) core_sat_p95=11 cream_outside_band=0.28% cyan=(found=False,pct=0.000)
P0B_BEAM_REF pose=beam_close emitter_pct=(17.7,40.2) peak_row=40.19% excess=10.51 peaks=(40.2@10.5,35.7@2.1,34.8@2.0) core_px=19 glow_1pct=(+1.86,+2.57) core_sat_p95=35 cream_outside_band=0.12%
P0B_KF27 pose=beam_close met=3/7 emitter_box=false beam_row_band=false row_excess_ge_2=false glow_falloff=false core_neutral=true no_cream_slab_10pct=true cream_reference_like_2pct=true
P0B_CELLMAP pose=beam_close grid=16x9 cream=luma>=170,sat<=46 stride=2 unexplained=0
P0B_CELLMAP_LEGEND . ok  B brighter  D darker  c cream-in-both  C cream-unexplained  A allowed
P0B_CELLMAP_ROW row=0 . . . . . B . . . . . . . . . .
P0B_CELLMAP_ROW row=1 . . . . . . . . . . . . . . . .
P0B_CELLMAP_ROW row=2 . . . . . . . . . . . . . . . .
P0B_CELLMAP_ROW row=3 . . . . . . . . . . . . . . . .
P0B_CELLMAP_ROW row=4 . . . . . B . . . . . . . . . .
P0B_CELLMAP_ROW row=5 . . . . . . . . . D . . . B B .
P0B_CELLMAP_ROW row=6 . . . . . . . . . . . . . . . .
P0B_CELLMAP_ROW row=7 . . . . . . . . . . . . . . . .
P0B_CELLMAP_ROW row=8 c c B . . . . . . . . . . . B B
P0B_CELLMAP_COUNTS brighter=7 cream_match=2 darker=1 ok=134 unexplained_cells=none
```

</details>

### 3.3 Frame-level results

| Frame (pose) | Port mean / p50 / p95 / %<8 / %>200 | KF27 reference (same method) | Δ mean / Δ %<8 | Beam peak row / excess | Emitter (x%, y%) | Cream outside band | KF27 criteria | 16x9 cream-unexplained |
|---|---|---|---|---|---|---|---|---|
| `S24_upper_foyer.png` (`upper_foyer`) | 40.8 / 29 / 99 / 1.5 / 1.46 | 16.7 / 15 / 34 / 16.7 / 0.03 | +24.1 / −15.2 | 49.07% / 131.15 | (29.9, 49.1) | 1.39% | 4/7 | 12 cells (row 4 cols 4–11 = 8, plus 4 scattered) |
| `S24_yaw180.png` (`yaw180`) | 43.9 / 34 / 131 / 2.7 / 0.76 | 16.7 / 15 / 34 / 16.7 / 0.03 | +27.2 / −14.0 | 49.07% / 25.24 | (23.9, 42.1) | 1.28% | 6/7 | 12 cells (scattered) |
| `extra_lounge_beam_close_pose.png` (`beam_close`) | 20.2 / 20 / 29 / 1.1 / 0.15 | 16.7 / 15 / 34 / 16.7 / 0.03 | +3.5 / −15.5 | 28.06% / 0.47 (no peaks) | not found | 0.28% | 3/7 | 0 |

The KF27 reference side, measured by the same scorer on
`clean/KF27_03m27s_foyer_security_beam.jpg`, reproduces the published reference numbers:
emitter (17.7%, 40.2%) vs the RE's (17.8%, 40.0%); beam row 40.19% with excess 10.51; core
saturation p95 35; cream outside the beam band 0.12% vs the published ~0.10%. The script's luma
columns use the W9 method (ImageMagick gray, ITU-R 601, 480-px resize); the cell/beam/cream columns
use full-resolution 16x9 cells sampled every 2nd pixel.

**Official V6-03 erratum (Phase 0a):** the scorecard's official cell is corrected to these
measurements — emitter **17.8 %/40.0 %**, **one** band at **40.0–40.5 %**, cyan node **above the
doors**; the old `y~56 %`/two-beam/ceiling-diamond text is a transcription error. This report's
port-side numbers are evidence for a later `V6-03` review, not a row score, and no tally token
changed.

### 3.4 `S24_foyer_beam.png` (no pose id)

The manifest's median frame stats are:

```
median_mean  = 34.3635589771756
median_lt8   =  2.26234567901235
median_peak  = 255.0
```

Published KF27 reference/criteria for comparison (no pose was invented for this frame):

| Quantity | KF27 published / measured | `S24_foyer_beam.png` |
|---|---|---|
| Frame mean | 16.7 (measured by the same scorer) | 34.36 (manifest; ~2.1x) |
| % pixels < 8 | 16.7 (measured) | 2.26 (manifest) |
| Peak row | 40.19% (scorer); criteria band 36–44% | visually ~49% (not scorer-measured) |
| Emitter position | (17.8, 40.0) RE; (17.7, 40.2) scorer | visually ~22%, ~49.5% (gold disc with a cyan cross) |
| Core saturation p95 | ~35 | not measured for this frame |
| Cream outside beam band | ~0.1% (0.12% measured) | not measured for this frame |
| Cyan ceiling node | present in KF27 | not visible in this frame |

The frame is a close, oblique view of the emitter and one beam. Its beam is visibly at the same
~49% height as the `upper_foyer` frame, i.e. below the published 39–40% beam rows, and the cyan
ceiling node is absent. Those are visual observations; no scorer number is claimed for this PNG
because it has no pose id.

### 3.5 What the numbers mean — and do not mean

- **Exposure / level.** The two foyer frames are much brighter than KF27: mean 40.8 and 43.9 vs 16.7
  (+24.1 / +27.2), and %<8 1.5 / 2.7 vs 16.7. The reference is a dark room; the port frames are
  lifted. This is a frame measurement, not a grade and not a diagnosis.
- **Beam geometry.** Both foyer frames put the beam peak at **49.07%** frame height, with excess
  131.15 (`upper_foyer`) and 25.24 (`yaw180`), against KF27's 40.19% / 10.51. The port shows one
  thick band with a 61-row core and a ±1% glow of +93/+89 in `upper_foyer` — i.e. no
  falloff, not two thin beams. The `upper_foyer` cell map flags 12 cream-unexplained cells, 8 of them
  on that band (row 4, cols 4–11); that is the measured "cream bar" signature of the port beam. This is a
  frame measurement; it is **not** an invented-white fallback claim and it is not a `V6-03` score.
- **Emitter / cyan node.** `upper_foyer`'s emitter is (29.9, 49.1), outside the published KF27 box
  (x 10–26, y 33–47) → `emitter_box=false`. `yaw180`'s (23.9, 42.1) is inside the box, but that
  frame is the reverse view. The cyan ceiling node is not found in `upper_foyer` (0.000%) and is
  negligible in `yaw180` (0.003%, a handful of pixels) — neither is the reference's glowing ceiling
  diamond.
- **The 4/7 and 6/7 are not row scores.** The seven criteria are frame-level KF27 tests. `upper_foyer`
  fails the emitter box, the 36–44% beam band and the glow falloff; `yaw180` fails the beam band. The
  `beam_close` 3/7 is not a KF27 comparison at all: that frame is the Lounge, the pose looks along
  the beam axis, and no beam row is detected (excess 0.47, no peaks; 0 cream-unexplained cells).
- **No score.** The numbers support a later `V6-03` review (beam position, thickness, brightness,
  cyan node) and a later `V4-07` review (the `yaw180` frame shows the armchair/ottoman/vitrine), but
  they do not assign a token.

---

## 4. Not scorable / deferred

### 4.1 The 14 deferred beats

| Beat | Official span | Ref KF | Why it is deferred (manifest reason, condensed) |
|---|---|---|---|
| S07 | 38.17–51.08 | KF09 | Multi-subject beat: decoration swap, boot-trail decals, gramophone ON, trunk cycle, then a walk to the map table. The interact hooks exist, but there is no camera/pan driver; a single prop frame would misrepresent the beat. |
| S13 | 80.10–99.30 | KF15 | Needs a continuous catwalk→alley vault/sprint/crouch and the car `[F] INTERACT` at the gate; no multi-beat input driver. The authored `BARRON'S DEMOLITION` banner asset is also absent (HARD_LIMIT). |
| S14 | 99.30–109.50 | KF16 | `[1]` equip, gate aim, 1st zipwire launch and planter landing; no stable still-stage hook without an input driver. |
| S15 | 109.50–118.50 | KF17 | 2nd zipwire plus ~7 s of crank input; depends on S14 state. |
| S16 | 118.50–131.00 | none | Roofline/chimney traversal and 3rd zipwire; depends on S14/S15; the reference table links no keyframe. |
| S17 | 131.00–143.30 | KF18 | Cable crossing, gear-plate landing and the courtyard drop with authored fall damage; needs the prior zipwire state and physics-driven traversal. |
| S18 | 143.30–150.70 | KF19/KF20 | Throw input and plume VFX (Niagara is a labelled procedural stand-in, HL-1); no input driver. |
| S19 | 150.70–153.00 | KF21/KF22 | Needs a live guard at the portico and the `[4]` scan; the staged route has no NPC in view (4 guards + 3 civilians spawn at 48–151 m, C4-08/L4-08). |
| S20 | 153.00–174.50 | KF23 | ~21 s balcony/terrace traversal with a patrol guard; no continuous driver and no NPC on the staged route. |
| S21 | 174.50–184.50 | KF24 | Approach, `[F] OPEN`/`[HOLD] LOCK` on the blue double doors and a walk-through; content is proven by the P1 probes, but the staged runner cannot drive the approach. |
| S22 | 184.50–197.10 | KF25 | Live constable, crouch approach and `[F] PICK POCKET`; no NPC and no input driver. |
| S23 | 197.10–202.00 | KF26 | `[HOLD] TAKEDOWN` lunge camera; needs the S22 guard and input; not stageable as a still. |
| S25 | 209.00–217.40 | KF28 | Requires the player to cross the foreground beam so the authored signal seals the ward/vine lock; firing `_spawn_foyer_lockdown` directly would label a staged lockdown as the played beat. |
| S26 | 217.40–221.90 | KF29 | Depends on S25 (breaking a barrier triggers the crimson alarm) and a stair traversal; no input driver. |

### 4.2 The staged audio windows are silent by stage

The audio tap is a real-device Master capture (PulseAudio, 44.1 kHz, 2 ch, 187.42 s, 19 marks,
`enabled=true`, `dropped_frames=0`), but it is **recorded, not scored**. The menu and loading stages do
not carry the authored bed:

| Mark | Window | Peak / RMS | Zero fraction | Reading |
|---|---|---|---|---|
| `S01_startscreen` | 11.111 s | −180.0 / −180.0 dBFS | 1.0000 | **exact digital silence** |
| `S10_loading_2` | 39.973 s | −24.254 / −62.092 dBFS | 0.9369 | **93.7% zero; near-silence**, not the authored bed |
| `S02_loading_1` | 17.125 s | −61.366 / −80.680 dBFS | 0.7948 | near-silence |

The total tap peak is −0.326 dBFS in the `S24_upper_foyer` window and the total zero fraction is
0.384 — the later UI/world stages do carry some energy — but without a played-beat alignment and an
in-engine per-bus measurement, no AU row can be scored from it. In particular:

- the `UNVERIFIED` audio rows stay `UNVERIFIED`: AU1-01, AU1-02, AU1-04, AU1-05, AU3-01, AU3-02,
  AU3-04, AU3-05, AU4-01, AU4-04, AU4-05, AU5-02, AU5-05, AU5-07 (14 rows), plus the audio-owned
  visual row V2-05 and UI5-01's named capture experiment;
- AU1-03's existing `DELTA` (the control-plane loading silence in `test_audio_mix.gd`) and AU6-01's
  existing `MISSING` (no `VO_PINS` player line) are untouched; this capture neither confirms nor
  refutes them;
- the S01 and S10 windows cannot stand in for the official startscreen rain bed (`AU1-01`) or the
  loading-silence transition (`AU1-03`).

### 4.3 Rows a staged capture cannot settle

| Class | Rows | Why this staged set cannot settle them |
|---|---|---|
| Audio | All 31 AU rows; V2-05 | No played alignment and no in-engine Master-bus measurement; the tap is a device capture; the S01/S10 windows are silence/near-silence. This capture cannot settle any AU row; AU1-03 and AU6-01 stand on their earlier control-plane/authored-data evidence (§4.2). |
| Timing / transition | V7-02, UI4-05, G5-01, AU4-04, AU1-04, AU4-05, G2-03, G3-01, V7-04 | A still cannot measure a cut, a hold, a 1.00 s tick train, a duck, a crank duration or a lunge. |
| NPC-dependent | V5-04, V5-05, UI2-06, UI3-04, UI5-02, UI5-03, UI5-04, UI5-06, G1-06, G4-01…G4-05, AU6-02…AU6-06 | No NPC is in view on the staged route (4 guards + 3 civilians at 48–151 m, C4-08/L4-08). |
| Traversal / interaction | V1-05, V3-03, V4-05, V4-06, UI2-05, V6-02, G1-04, G2-02…G2-05, G3-01…G3-04, G5-03, G5-04, AU5-01…AU5-08 | These need S13–S26, which are deferred for the input/traversal reasons in §4.1. |
| Mission binding | UI3-02, UI4-03, G5-01 (and the S11 letter) | The Guildhall stage is free play `LootTheRoom` on contract 2, not the official selection (`VaultHeist`); the prep/HUD forms are the free-play forms. |
| Beam trigger / lockdown | G5-03, V6-04's green-vine half, UI5-06 | The S24 frames show an **untriggered** beam; no crossing, no lockdown, no vines, no jaw-trap icons. |
| Lounge beam | — (extra, not a row) | The `beam_close` frame does not show the C_57 beam; the pose looks along its axis. It cannot be an S24/KF27 substitute. |

### 4.4 What would settle the open items

- A played route or a real input/traversal driver for S13–S26 (not a staged hook).
- An in-engine `AudioEffectCapture` on the Master bus per audio row (the W9-P0 instrument named in
  the scorecard), with the surface key / event logged.
- A translated scorer or pose ids for the route-only frames (`foyer_beam`, the UI beats, S03, S05,
  S12), or a written visual adjudication that keeps them out of the numeric path.
- A live guard/civilian population for S19/S22/S23 and the NPC rows.
- No new GPU/Steam run is needed to re-read these PNGs; a **played** capture is needed for the
  transitions, NPC states and audio.

---

## 5. Summary

| Item | Count |
|---|---|
| Frames in the staged set | **18** (17 beat frames + 1 Lounge extra) |
| Captured beats / deferred beats | **13 / 14** |
| Rows with at least part of their subject visible in a captured frame | **35** (26 with the row's main subject; 9 fragment-only) |
| Rows with a numeric measurement bearing on the row | **1** (`V6-03`; frame-level beam/emitter/cream only) |
| Rows scored by this report | **0** |
| Rows still needing human visual review | **35** (including `V6-03`; the number is not a verdict) |
| Rows not covered by this staged set | **85** = 51 `N/A-route` + 16 `UNVERIFIED` + 18 previously scored rows not re-covered |
| Existing 120-row tally | **unchanged**: 48 scored / 56 `N/A-route` / 16 `UNVERIFIED`; no token added or changed |

The 35 subject-visible rows, by pillar:

- **Visual (19):** V1-01, V1-02, V1-04, V2-01, V2-02, V2-03, V3-04, V4-01, V4-02, V4-03, V4-07,
  V5-01, V5-02, V5-03, V6-01, V6-03, V6-04, V7-03, V7-05.
- **HUD/UI (13):** UI1-02, UI2-01, UI2-02, UI2-03, UI3-01, UI3-02, UI3-05, UI4-01, UI4-02, UI4-03,
  UI4-04, UI4-05, UI5-05.
- **Gameplay (3):** G1-01, G1-03, G5-01.

Of the 35, **five were `N/A-route` in the 2026-11-24 scorecard** and now have a captured frame:
`V5-02` (wardrobe turntable), `V6-01` (escape portal), `UI2-02` (wardrobe slots/tooltips), `UI4-01`
(journal), `UI4-02` (black market). The other 30 already had a 2026-11-24 token — 6 `PASS`, 20
`DELTA`, 2 `HARD_LIMIT`, 2 `MISSING` — and none of those tokens is re-derived or overwritten here.
Several rows now have materially different evidence from the
2026-11-24 baseline (the S11 letter now carries the 55/20-minute copy; the S12 tracker is the
free-play form; the S24 frames show the beam and the reversed foyer dressing), so a later scored wave
must adjudicate them against these frames, not against this index.

The 9 fragment-only rows are: V1-04 (lit lantern but no ignite prompt/streetlamp), V2-01 (rain but no
puddle), V4-03 (2–3 of 5 posters), V5-01 (silhouette, no helmet/belt), V6-04 (pink thorny effect, not
the reference's green vine lock and no beam trigger), V7-03 (letter/backdrop but blur not
established), UI2-01 (`[F] EXIT` only, no `[F] PONDER`), UI4-05 (emblem/`LOADING...` but no spinner
ring), G5-01 (staged prep step, not a played flow).

**The full 120-row tally is not re-scored.** `COMPARISON_PORT_20261124.md` is unchanged; no row has
gained or lost a `PASS` / `DELTA` / `MISSING` / `HARD_LIMIT` / `N/A-route` token. The main remaining
visual gaps in this staged set are the absent startscreen menu stack, the missing loading spinner
ring, the S03 map-table card overlay, the S05 black band, the S24 beam position/brightness/cyan node,
and the invisible Lounge beam. The audio, timing, NPC and traversal rows listed in §4 remain
unsettled by design.

---

*Evidence paths: `docs/reports/logs/p0b-route/route2/manifest.json`,
`build/qa/p0b_route/route2/*.png` (18 files, git-ignored),
`docs/reference/clip_1795033698901/clean/*.jpg` (30 files, read-only),
`docs/reference/clip_1795033698901/row_route_matrix.md` (tracked from Phase 0a),
`build/qa/p0b_roi_stats.py`. This file was committed in Phase 0a; the 2026-11-24 media is not.*
