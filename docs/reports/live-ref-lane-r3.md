# Live-reference lane R3 — shipped-game footage, part 3, 0–542 s

**Status:** presence review only. Prepared 2026-11-27 by lane R3 of the
live-reference footage review. Read-only: no game, build, scorecard, matrix,
keyframe index or test file was edited, and nothing was committed.

**Claim boundary.** The footage is the **shipped UE5.5 build** (`1.5.148559`) on
the owner's machine, captured at 2560×1440/60 into
`~/Videos/tat2_ref_20261127/route_lossless_part3.mkv` (part 3). It is *not* the
port. It is the third ten-minute file of one continuous session, and it plays a
**different mission** from the official clip (see §2.2). This report records only
**what is visible in part 3**. No `PASS` / `DELTA` / `MISSING` / `HARD_LIMIT` /
`N/A-route` token is assigned, no row is scored, and no claim is made about part
1 beyond the boundary cross-check in §6 or about the missing part 2.

---

## 1. Method

### 1.1 Inputs read

| Input | Use |
|---|---|
| `~/Videos/tat2_ref_20261127/review/route_lossless_part3_1fps.mp4` (542 s, 480×270, 1 fps) | the scanned proxy; every evidence frame comes from it |
| `~/Videos/tat2_ref_20261127/review/route_lossless_part3_contact_5s.png` (3200×2160, 10×12 tiles) | first-pass overview at 5 s steps |
| `~/Videos/tat2_ref_20261127/route_lossless_part3.mkv` (nominally 600 s, 2560×1440, 60 fps) | full-res reads at candidate times only; seven kept as `r3_full_*` (t = 53, 141, 155, 179, 369, 378, 391) |
| `~/Videos/tat2_ref_20261127/review/route_lossless_1fps.mp4` (part 1 proxy) | only the 585–599 s tail and t = 570, for the §6 boundary check |
| `docs/reference/clip_1795033698901/clean/*.jpg` (30 keyframes) | official comparison frames (KF01, KF02, KF12, KF24, KF27, KF28, KF30 opened directly) |
| `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` | beat boundaries, keyframe mapping, official observations |
| `docs/reference/clip_1795033698901/BREAKDOWN.md` | S01–S27 narratives and per-beat subjects |
| `build/qa/review_20261124/row_route_matrix.md` | 120 row ids and their short criteria |
| `docs/reports/p0b-live-capture.md` §5 | the seven pose ids and their reference keyframes |
| `docs/reports/live-ref-review-plan.md` | lane assignment, verdict vocabulary, gap rule |
| `docs/reports/p0b-route-rescore.md` | claim-boundary precedent (frame captured ≠ beat played) |

### 1.2 What was done

- The proxy was decoded to 542 PNGs at 1 fps (`ffmpeg -i … -fps_mode
  passthrough frames/f_%04d.png`) and inspected as labelled 3×3 / 4×4 montages
  at 1 s and 2 s steps; ambiguous spans were re-read frame by frame and, for
  text, at full resolution.
- Motion was indexed numerically: `tblend=all_mode=difference` +
  `signalstats` over all 542 one-second samples. Two near-static runs were
  found — **0–13 s** (mean frame delta 1.3–2.2) and **244–256 s** (0.25–1.5) —
  and the long static tail **392–536 s** (≤ 1.0).
- Scene cuts were cross-checked with
  `ffmpeg -vf "select='gt(scene,0.12)',showinfo"` on the proxy (39 cut points,
  mostly 14 s, 39–55 s, 112–130 s, 174–176 s, 197–201 s, 228–232 s, 275 s,
  301 s, 334–346 s, 370–374 s, 386–388 s).
- Every beat/pose claim below was re-extracted from the proxy with
  `ffmpeg -ss <t> -i route_lossless_part3_1fps.mp4 -frames:v 1` into
  `~/Videos/tat2_ref_20261127/review/r3_*.png` (all 480×270) and viewed. Seven
  candidates were additionally extracted from the original at 2560×1440 to read
  UI copy (`r3_full_*.png`).
- Extraction was verified against the decoded frame set: `md5sum` of
  `-ss 391`, `-ss 179` and `-ss 246` equals the corresponding `f_0392`,
  `f_0180`, `f_0247`, so the cited timestamps are the proxy frame's own PTS, not
  frame-index arithmetic.
- No GPU, Vulkan, Xvfb, Steam, Godot or game process was started. No audio
  analysis was performed (visual lane; AU rows excluded in §5).

### 1.3 Time convention

All times are **seconds on the part-3 proxy timeline**, equal to the source
container PTS (the proxy is `fps=1` with no trim). A still shows the frame at
that instant; at 1 fps a transient prompt between samples can be missed (§8).

**Coverage caveat (measured).** The part-3 file is nominally 600 s but its last
video packet is at **541.700 s** and the recorder log records a −44.506 s
backward timestamp jump near the end (`recorder_part3.log`). The proxy therefore
has **542 one-second samples, 0–541 s**; **542–599 s do not exist**. The tail is
the static main menu, so no content is lost for this review, but the window is
542 s, not 600 s.

### 1.4 Verdict vocabulary

| Verdict | Meaning |
|---|---|
| `present` | the beat's defining subject is visible and identifiable in a frame |
| `partial` | the subject class is visible, but a defining element, composition, state, prompt or copy differs, or the beat's transition is unseen |
| `absent` | the segment is visibly not this beat at any sampled point in part 3 |
| `unseen-gap?` | not found in part 3, and its route position could fall in the 226.5 s unrecorded hole — *not* a verdict |

`absent` here always means **absent from part 3**, not from the recording. The
plan (§2.4, §8) forbids a lane calling a beat absent from its own window alone;
§6 records the gap shadow and the beats that R1/R2 own.

---

## 2. What part 3 actually contains

### 2.1 Content index

Times are **seconds** on the part-3 proxy timeline.

| Proxy span | What is on screen |
|---|---|
| 0–13 | **Upper-landing doorway view**, near-static: wooden balustrade, long console table with a vase and a book, white marble statue below, white spherical pendant, gilt-framed paintings, candle sconces, a purple spotlight cone, cream checkered tile. HUD `Mission: Steal the components of the Staff of Edinburgh[0/3]`, `(£) 0`, hotbar `1/2/4`, **no `Guildhall Key` row**. |
| 14–38 | Looks up at the ceiling (purple fixture, a red glowing sigil at 25), walks out past green thorny vine panels over windows (27–31); health bar showing damage, red noise arcs. |
| 39–55 | A grey-white smoke plume fills a bedroom (39–52); a constable at close quarters with `[F] [HOLD] TAKEDOWN` (45–49); the **`Guildhall Key` HUD row appears at 53** and a gold key pickup icon at 54. |
| 56–140 | Looting desks and drawers (`Nabber's Ivory Comb` 67, `Gold Table Clock` 71, "Subset objective is complete"), ground-floor lounge with sofas/tables/purple rugs (91–111), more vine panels, a service stair (133), `(£) 280 → 325 → 370`. |
| 141–158 | **Checkered marble foyer**: glass vitrine with a mannequin in white clothes, dark chair, blue/gold rug, `[F] TURN ON` standing lamp (143), a stairwell down (149–151), a thin white beam from a round wall emitter (153–157). |
| 159–191 | Bathroom with sinks (161), corridor, **`Basement Stairs` plaque (173)**, green vine-covered door (175), **purple crystalline ward** across the arch with a jaw-trap status icon above the gem (177–191). |
| 192–232 | Library with stacked books and a guard at a counter (201–203), bedroom with a lit fireplace (209), green key waypoints ("3 m", "17 m", "19 m"), a thin white beam across a corridor (217–219), **stash-room portal** `Cash-in-Hand: 370 / Stashed Cash: 0 / [F] TO DEPOSIT ALL LOOT` (229–231). |
| 233–300 | Lounge doorway hold 244–256, candle snuffing (269–275), bust close-up (283), lounge from above (285–295), `[F] [HOLD] UNLOCK WITH KEY` door (300). |
| 301–345 | Greenhouse/vine room (311–325), "Dear Captain Crowe…" parchment note with `CONTINUE` (336–337), key-locked door (343), **caught**: `Time Until Respawn 0:04 → 0:00` (345–349). |
| 351–367 | `Recover the items` (353–359), respawn ("Johnny Cipher has respawned", 361–363), back at the ward from the stair side (367). |
| 368–369 | **Pause menu** `RESUME / SETTINGS / RETURN TO THIEF'S DEN / QUIT TO DESKTOP`, cursor on `RETURN TO THIEF'S DEN`, footer `1.5.148559   Novice   701694559`. |
| 370–373 | **Loading screen** (KF12 art): indigo skyline, two dirigibles, moon, spinner ring, `LOADING...`, gold `THICK AS THIEVES`. |
| 374–385 | **Thieves' Den** return: teal moon shaft through the leaded window, telescope on its tripod, wanted posters, rolltop desk with candles, `KILCAIRN` parchment on the map table, armoire. |
| 386–387 | Den **pause menu**, second form: `RESUME / SETTINGS / RETURN TO MAIN MENU / QUIT TO DESKTOP`. |
| 388 | Loading screen again (Den → menu). |
| 389–541 | **Startscreen** (fade-in at 389, full menu from 390): rainy `Mac Neish / Jeweller` shopfront, neon, idle guard at the door, crates, wet cobbles, right-aligned `THICK AS THIEVES` + `PLAY / SETTINGS / CREDITS / QUIT`, cursor. Live but near-static to the end of the file. |

### 2.2 This is not the official mission

The HUD reads **`Mission: Steal the components of the Staff of Edinburgh[0/3]`**
with sub-objectives `Steal Gem of Arcana` / `Gem of Strength` / `Gem of Fire`
(visible 0–359 s) and `(£) 0 → 370`. The official clip plays the same map on
`Cleanout Heist` with `Steal 4,000 in loot value[0/4,000]`. Lane R1 measured the
selection screen for this session as **`Item Collection Heist`, 120 minutes,
`Contract Inactive`**; part 3 is a continuation of that run. The pause footer
seed `701694559` is the same seed R1 recorded in part 1, which is the strongest
in-band evidence that part 1 and part 3 are one session.

Consequences for this lane: the **map and the HUD frame** are the shipped
Guildhall and the shipped HUD, but beat copy that names the mission (`S11`'s
briefing, `S12`'s tracker, `S24`'s objective line) cannot match the official
words, and guard/loot placement may follow the different contract.

---

## 3. Beat table (S01–S27)

Official times are the S01–S27 boundaries in `KEYFRAME_INDEX.md` §2. Proxy times
are the span in which the subject is visible in part 3; `—` means not reached.

| Sxx | official t | p3 t | verdict | evidence frame | subject / what differs |
|---|---|---|---|---|---|
| **S01** Startscreen | 00:00.00 | 390–541 | **present** | `r3_S01_startscreen_391.png` (`r3_S01_startscreen_540.png`) | Rainy `Mac Neish / Jeweller` shopfront, magenta script + amber tubes, right-aligned `THICK AS THIEVES` + `PLAY/SETTINGS/CREDITS/QUIT`, cursor, idle guard in the doorway, crates at the right, wet cobbles with leaf litter, purple orb in the upper window. The menu is **live**: 0.7 % of pixels (mostly rain streaks and the neon) differ between t=401 and t=501. Framing differs from KF01 — closer to the shop, two out-of-focus foreground occluders, the car fender is not identifiable. Reached as the **end** of the session, not the boot. |
| **S02** Loading 1 | 00:02.15 | 370–373 | **partial** | `r3_S02_loading_371.png` | Exact KF12 art (skyline, two dirigibles with yellow cones, crater moon upper-right, cyan spinner ring, `LOADING...`, gold emblem, progress bar lower-left). But the flow position is a **return** load (capture → Den), not the menu → Den load that S02 defines. Shared art with S10 cannot be disambiguated by flow here. |
| **S03** Den entry | 00:02.60 | 374–385 | **partial** | `r3_S03_den_378.png` | Den interior matches KF02's content: teal moon shaft through the leaded window, telescope + tripod, a cluster of wanted posters (not countable at this angle), rolltop desk with candles, `KILCAIRN` parchment and a wooden token on the map table, armoire, floorboards. The **entry** (fade-in + rising pan + player-card fade-in) is not played; this is the post-capture return, and the camera is a wider/different angle from KF02. |
| **S04** Wardrobe | 00:06.57 | — | **absent** | `r3_S03_den_378.png` | No `WARDROBE` overlay anywhere in part 3; the Den visit is 12 s and no station is used. |
| **S05** Telescope & posters | 00:18.24 | — | **absent** | `r3_S03_den_378.png` | Telescope prop and the poster wall are visible in the Den frame, but there is no `[F] PONDER`, no sky cut, no cheese moon, no `[F] EXIT`. |
| **S06** Ledger | 00:26.58 | — | **absent** | `r3_S03_den_378.png` | No `JOURNAL` or `BLACK MARKET` overlay. |
| **S07** Props & Gramophone | 00:38.17 | — | **absent** | `r3_S03_den_378.png` | No gramophone corner, `[F] CHANGE DECORATION`, boot-trail decals or trunk cycle in the 12 s Den visit. |
| **S08** Map table | 00:51.08 | 378 | **partial** | `r3_S03_den_378.png` | `KILCAIRN` parchment and a wooden token are in frame at the right edge; no banker's lamp in frame, no `[F] ENTER MATCH` reticle, no `[H] Difficulty` card, no confirmation modal. |
| **S09** Mission prep | 00:56.08 | — | **absent** | `r3_S02_loading_371.png` | No `MISSION PREPARATION` screen, cards or countdown. |
| **S10** Loading 2 | 01:04.80 | 388 | **partial** | `r3_S02_loading_388.png` | Same KF12 art, but the flow position is Den → main menu, not post-prep → mission. Same shared-art caveat as S02. |
| **S11** Briefing letter | 01:09.44 | — | **absent** | `r3_note_337.png` | No briefing letter over a blurred safe room. A **different** parchment note ("Dear Captain Crowe… second floor west wing… With admiration, Margery") with a `CONTINUE` button appears at 336–337 over live gameplay. |
| **S12** Safe room | 01:10.81 | — | **absent** | `r3_S24_foyer_141.png` | No brick safe room, green/violet Escape Portal outline, oil lantern, `SPIDER` flyer or catwalk. |
| **S13** Street/alley/car | 01:20.10 | — | **absent** | `r3_pose_lounge_5.png` | Part 3 is interior (Guildhall) until the menu backdrop; no street, `BARRON'S DEMOLITION`, car, honk or gate. |
| **S14** 1st ZipWire & gate | 01:39.30 | — | **absent** | `r3_pose_lounge_5.png` | No `CONSTABLE'S GUILDHALL` arch, guard with red eyes/alert bar, car headlights or launch. The ZipWire stays in the hotbar and is never raised for a street shot. |
| **S15** 2nd ZipWire & crank | 01:49.50 | — | **absent** | `r3_S24_foyer_141.png` | No cable, crank ring or roof parapet. |
| **S16** Roofline & 3rd ZipWire | 01:58.50 | — | **absent** | `r3_S24_foyer_141.png` | Not reached. |
| **S17** Gate pillar & descent | 02:11.00 | — | **absent** | `r3_S24_foyer_141.png` | No cable crossing, gear plate, griffins or courtyard drop. |
| **S18** Smoke bomb | 02:23.30 | 39–52 | **partial** | `r3_S18_smoke_41.png` | A dense grey-white volumetric plume fills a **bedroom**, with a guard inside it and red alert chevrons; the player is then at close quarters with him. The `[2]` equip/throw is not visible at 1 fps and this is not the courtyard stairs. **Plume presence only.** |
| **S19** Vistara scan | 02:30.70 | — | **absent** | `r3_S24_beam_157.png` | The diamond is held in slot `[4]` (HUD icon) but is never equipped and no scan pulse/RED→GREEN silhouette appears. |
| **S20** Side wing & `MACLEOD` | 02:33.00 | — | **absent** | `r3_S24_foyer_141.png` | No exterior side wing, balcony, barred window, `MACLEOD` sign or terrace. |
| **S21** Blue double doors | 02:54.50 | 300 | **partial** | `r3_S21_door_300.png` | A pale blue-grey glazed door with a painted frame and `[F] [HOLD] UNLOCK WITH KEY`. Not KF24's diamond-mullion double doors, no `[F] OPEN` / `[F] [HOLD] LOCK` → `[F] CLOSE` flip, no portico or scaffolding. |
| **S22** Parlor & pickpocket | 03:04.50 | 45–55 | **partial** | `r3_S22_key_53.png` (`r3_S22_key_54.png`) | A constable at close quarters (47) under `[F] [HOLD] TAKEDOWN`; the **`Guildhall Key` HUD row appears between 52 and 53** (verified absent at 5, 50, 51, 52 and present at 53) and a gold key pickup icon shows at 54. The `[F] PICK POCKET` label is **not** visible in any sampled frame, and there is no hearth/chandelier parlor in that shot. |
| **S23** Takedown | 03:17.10 | 45–53 | **present** | `r3_S23_takedown_47.png` (`r3_S23_takedown_49.png`) | `[F] [HOLD] TAKEDOWN` over a constable's helmet/shoulder at point-blank range with a 1P lunge (the guard fills the frame at 47–49). The KO/pull-back is not sampled at 1 fps; a downed constable is visible later at 111 (`r3_S23_down_111.png`). |
| **S24** Foyer & beams | 03:22.00 | 139–158 | **present** | `r3_S24_foyer_141.png`, `r3_S24_beam_157.png` | The KF27 room is confirmed: same checkered marble floor, same blue/gold rug, same glass vitrine with the white-clothed mannequin, dark chair, and a thin white beam leaving a round wall emitter (two parallel lines at 153/155). **Not in frame:** the cyan ceiling diamond (checked in a 40-frame ceiling-strip sweep, 136–175), the square metal floor plate, the overhead security camera; the two beams are never wall-to-wall in one frame. |
| **S25** Ward lockdown | 03:29.00 | 173–191, 367 | **partial** | `r3_S25_ward_179.png`, `r3_S25_vines_175.png`, `r3_S25_basement_stairs_173.png` | Post-trigger **state** is fully present: purple crystalline ward sealing the arch, green thorny vines on the `Basement Stairs` door (plaque legible at 173), jaw-trap status icon inside a partial ring above the Light Gem (175/179). The **trigger** (beam crossed, ward erupting, vines growing) is not visible — the ward is already up in part 1 at 587–591 and still up at 367. One of KF28's two status icons (the unconscious head) is not seen. |
| **S26** Crimson alarm & stairs | 03:37.40 | — | **absent** | `r3_S25_ward_367.png` | No crimson alarm wash and no red-lit slate stairwell. The barrier is **intact** at 367, so the KF29 barrier impact/shatter did not happen; the run is knocked out at 345, respawns at 361, and the player leaves for the Den through the pause menu at 368. |
| **S27** Pause & quit | 03:41.90 | 368–369, 386–387 | **present** | `r3_S27_pause_369.png` (`r3_S27_pause_387.png`) | Modal `RESUME / SETTINGS / RETURN TO THIEF'S DEN / QUIT TO DESKTOP` in the teal/copper Art-Nouveau border, footer `1.5.148559   Novice   701694559` (matches KF30's layout; the seed differs from the official `1025051536`). Cursor is on `RETURN TO THIEF'S DEN` — the route ends by returning to the Den, then a second pause offers `RETURN TO MAIN MENU` and the main menu follows at 389. No `QUIT TO DESKTOP` selection. |

**Counts (presence only, no scoring):** `present` **4** — S01, S23, S24, S27;
`partial` **8** — S02, S03, S08, S10, S18, S21, S22, S25; `absent` **15** —
S04, S05, S06, S07, S09, S11–S17, S19, S20, S26. (4 + 8 + 15 = 27.)

---

## 4. Pose table

Pose ids and reference cues are the p0b capture poses
(`docs/reports/p0b-live-capture.md` §5; `docs/reports/live-ref-review-plan.md` §4).

| Pose | ref | p3 t | verdict | evidence frame | subject / what differs |
|---|---|---|---|---|---|
| `gate` | KF16 01:40.20 | — | **absent** | `r3_pose_lounge_5.png` | No exterior, gate arch, car, red-eyed guard or ZipWire launch anywhere in part 3. |
| `kf18_overlook` | KF18 02:14.80 | — | **absent** | `r3_S24_foyer_141.png` | No cable/roof overlook of the gate pillars, griffins or courtyard. |
| `upper_foyer` | KF27 03:27.60 | 141–157 | **partial** | `r3_S24_foyer_141.png`, `r3_S24_beam_157.png` | The KF27 **room** is confirmed at 141 (same vitrine, mannequin, rug, checkered marble, beam) and 157 (threshold view down the hall with the beam band at mid-frame). No single frame reproduces KF27's composition (vitrine at left + far double doors + cyan ceiling node in one shot); the node is not in any part-3 frame. |
| `yaw180` | KF27 +0.5 s | — | **absent** | `r3_S24_foyer_147.png` | The player turns through several walls of the foyer between 141 and 157, but there is no controlled 180° reverse pair (same spot, 3 s apart, opposite headings). No matched pair exists to cite. |
| `lounge` | none (port pose) | 5, 244–256 | **partial** | `r3_pose_lounge_5.png`, `r3_pose_lounge_246.png` | Two long near-static doorway holds (0–13 s and 244–256 s) looking into a tiled/checkered hall with a balustrade, console table, statue, white spherical pendant, paintings and a purple spotlight cone; a ground-floor lounge with sofas, tables and purple rugs is walked at 91–111. **No NPC/bouncer is visible in either hold**, and neither hold proves the port's Lounge coordinates (east doorway → west). |
| `lounge_beam` | none | — | **absent** | `r3_pose_lounge_246.png` | No white security beam in either lounge hold — only a purple spotlight cone from the ceiling. |
| `beam_close` | KF27 beam | 153–157 | **partial** | `r3_S24_beam_155.png` | Round wall emitter with a bright bulb and a thin white beam leaving to the left, seen obliquely at ~2–3 m; two parallel light lines at 153/155. The emitter is **not** the port's gold disc with a cyan cross, and the KF27 two-beam wall-to-wall band + cyan node is not reproduced. |

**Pose summary:** 0 present, 3 partial (`upper_foyer`, `lounge`, `beam_close`),
4 absent (`gate`, `kf18_overlook`, `yaw180`, `lounge_beam`) in part 3. No pose is
matched 1:1.

**Emitter-position note (side observation, not a row).** The plan (§4) records an
unsettled figure: `p0b_live_capture.md` and `p0b_roi_stats.py` put the KF27
left-wall emitter at `y ≈ 40 %`, while the scorecard text says `y ≈ 56 %`.
Measured on the official keyframe (brightest pixel in the left-wall region):
**`KF27_03m27s_foyer_security_beam.jpg`, pixel (341, 432) of 1920×1080 =
x 17.8 %, y 40.0 %**, which supports the 40 % figure. This is a measurement of
the **official** keyframe; the live part-3 beam frames are not KF27-framed, so no
live percentage is claimed here.

---

## 5. Row ids whose subject is visible

Row ids are from `build/qa/review_20261124/row_route_matrix.md`. A row is listed
only because its **subject** is in a cited frame. This is not a score and says
nothing about how well the port reproduces it. Rows supported only by a
`partial` beat would be `partial-subject` under the plan's rules (plan §6.2).

Audio rows (**AU1-01 … AU6-06, 31 rows**) are **excluded**: this lane did no
audio analysis and a still cannot show a sound. Motion-only rows (`V7-02`,
`G2-01`) are also excluded — a 1 fps still cannot evidence a pan or a walk.

| Evidence frame | p3 t | Row ids with subject visible | Caveat |
|---|---|---|---|
| `r3_S01_startscreen_391.png` | 390 | V1-01, V2-01, V3-01, V3-04, V4-01, V5-01, V7-01, UI1-01 | **Main-menu backdrop only** — no gameplay street in part 3. Neon + amber tubes, rain streaks and wet cobbles, purple window orb, idle guard at the door, crates, scrollwork, right-aligned logo + `PLAY/SETTINGS/CREDITS/QUIT`. Framing ≠ KF01; car fender not identifiable. |
| `r3_S02_loading_388.png`, `r3_S02_loading_371.png` | 371, 388 | V2-03, UI4-05 | KF12 art with spinner ring, `LOADING...`, gold emblem. |
| `r3_S03_den_378.png` | 378 | V1-02, V4-02, V4-03, UI3-01 | Teal moon shaft + candle pools; desk/armoire/telescope/rafters; wanted-poster cluster; player card + compass. The `KILCAIRN` parchment at the right edge also carries S08's prop but not its UI. |
| `r3_S24_foyer_141.png` | 141 | V4-07, V5-03, V6-03, UI2-03, UI3-01, UI3-04, UI3-05, UI5-01 | Checkered marble + glass vitrine + chair (no floor plate, no `Basement Stairs`/`WC` plaque in this frame — see 173); beam + emitter (no cyan node); `LAUNCH LMB` / `[HOLD] CRANK RMB` and the ZipWire viewmodel in hand; `Guildhall Key` row; dark gem with red arcs. |
| `r3_S24_beam_157.png` | 157 | V6-03 | Threshold view down the hall with the beam at mid-frame and the emitter visible. No cyan node. |
| `r3_S25_ward_179.png` | 179 | V6-04, G5-03, UI5-06, UI3-05 | Purple crystalline ward in the arch with a statue beyond; jaw-trap status icon above a bright gem. `G5-03` is the **locked-down state only** — the beam trip that caused it is not in part 3. |
| `r3_S25_vines_175.png` | 175 | V6-04 | Green thorny vines filling the `Basement Stairs` doorway. |
| `r3_S25_basement_stairs_173.png` | 173 | V4-07 | Legible `Basement Stairs` wall plaque (the foyer dressing row names the plaques). |
| `r3_S23_takedown_47.png` | 47 | V5-05, V7-04, UI2-06, G4-04 | Takedown prompt + 1P lunge over a constable's helmet/shoulder. `UI2-06` is supported only by its takedown half (`[F] [HOLD] TAKEDOWN`); no `[F] PICK POCKET` label. |
| `r3_S22_key_53.png`, `r3_S22_key_54.png` | 53, 54 | UI3-04, G1-06 | `Guildhall Key` HUD row first appears at 53 and a gold key icon at 54; the pickpocket action itself is not visible. |
| `r3_S23_down_111.png` | 111 | G4-04 | A downed constable face-down in a doorway (KO result). |
| `r3_S18_smoke_41.png` | 41 | V6-02, G3-02 | Volumetric plume only; location is a bedroom, not the courtyard stairs; the throw is not sampled. |
| `r3_S21_door_300.png` | 300 | V3-03 | Pale blue-grey glazed door, `[F] [HOLD] UNLOCK WITH KEY`. No diamond mullion, no brass plates, no OPEN/LOCK→CLOSE flip. |
| `r3_fireplace_209.png` | 209 | V1-06 | Lit fireplace with a warm amber pool in a sitting room (not KF25's parlor). |
| `r3_UI3_bar_41.png` | 41 | UI3-03 | Health bar visible with a drained red segment during the takedown/alert; the reveal trigger is not a fall. |
| `r3_pose_lounge_246.png` | 246 | UI3-01, UI3-02, UI3-05 | Player card, tracker/hotbar (different objective text; health bar is **not** hidden), dark gem. |
| `r3_S27_pause_369.png` | 369 | V7-05, UI1-02, G5-05 | Pause modal + footer; darkened blurred backdrop; the flow continues to the Den and the main menu (no `QUIT TO DESKTOP`). |

**Tally:** 38 rows are listed above (21 visual, 12 HUD/UI, 5 gameplay), 51
visual/UI/gameplay rows are not listed, and the 31 AU rows are out of scope —
38 + 51 + 31 = 120.

Rows **not** claimed (subject not visible in any part-3 frame): V1-03, V1-04,
V1-05, V1-07, V2-02, V2-04, V2-05, V3-02, V4-04, V4-05, V4-06, V5-02, V5-04,
V6-01, V7-02, V7-03; UI2-01, UI2-02, UI2-04, UI2-05, UI2-07, UI3-06, UI4-01,
UI4-02, UI4-03, UI4-04, UI5-02, UI5-03, UI5-04, UI5-05, UI5-07; G1-01…G1-05,
G2-01…G2-05, G3-01, G3-03, G3-04, G4-01…G4-03, G4-05, G5-01, G5-02, G5-04.

---

## 6. Part-1 boundary and the part-2 gap

### 6.1 Where part 3 starts

The plan measured the hole from the two x11grab start epochs: part 1 ends at
wall-clock 600.0 s, part 3 starts at 826.5 s, so **226.5 s (3:46.5) are
unrecorded**. Part 3 does **not** resume at part 1's last frame:

| Part | t | What is on screen |
|---|---|---|
| p1 | 570 | Climbing a wooden stair, `Guildhall Key` row present, `[1/3]`. |
| p1 | 585–586 | Checkered foyer with the vitrine and a white beam; the purple ward appears at the right. |
| p1 | 587–589 | Purple ward up close, green vines on the `Basement Stairs` door. |
| p1 | 590–592 | `Time Until Respawn 0:04 → 0:00` — **caught**. |
| p1 | 593–599 | "Recover the items" over a dark view with purple sparkles. |
| p3 | 0–13 | A **different** room (upper-landing doorway over a tiled hall), near-static; `[0/3]`, `(£) 0`, **no `Guildhall Key` row**. |
| p3 | 53 | `Guildhall Key` row reappears (re-acquired). |

So the session is continuous in *state* (same mission, same `[0/3]` after losing
the key on capture, same pause footer seed `701694559`) but not frame-to-frame.
The key row is present at p1 570/585 and absent at p3 5, which is direct evidence
that the p1 capture cost the key and that part 3 re-earns it at 53.

### 6.2 Gap shadow (which "absent" verdicts are safe)

- **S01–S21** sit at or before the p1 tail; their absence from part 3 is a
  *window* fact only, and lanes R1/R2 own their route positions.
- **S24** and **S25** are found in part 3 (§3); **S25's trigger** is not, and it
  cannot be placed: the ward is already up at p1 587 and still up at p3 367.
  `partial` is therefore the only defensible verdict — the trigger happened
  before p1 587 or inside the gap.
- **S26** is the one beat with a plausible gap shadow, and it is ruled out by
  state: the ward barrier is still **intact** at p3 367, so the KF29 barrier
  impact/shatter never occurred in the recorded session, and no crimson alarm
  appears after the p1 capture either.
- **S27** is found twice (p3 369 and 387), so the pause modal is not lost.

---

## 7. What this lane adds beyond the plan's expectations

1. **The endgame state is present but the endgame *trigger* is not.** The purple
   ward, the green vine lock, the `Basement Stairs` plaque and the jaw-trap
   status icon are all visible (173–191), but the beam-tripwire eruption is
   not; the lockdown predates part 3.
2. **S22/S23 are played in part 3**, not in the gap: a constable takedown at
   45–53 with the `Guildhall Key` HUD row appearing at 53 and a key pickup icon
   at 54.
3. **The main menu is reached by Den → `RETURN TO MAIN MENU`**, not by
   `QUIT TO DESKTOP`, and the shipped menu camera framing differs from KF01
   (closer, two foreground occluders) while the scene content is identical.
4. **A stash-room deposit portal** (`Cash-in-Hand / Stashed Cash /
   [F] TO DEPOSIT ALL LOOT`) is visible at 229–231. It is not one of the 120
   rows and is recorded here only as a content observation.
5. **The part-3 file is 541.7 s of content, not 600 s** (§1.3), because of a
   recorder timestamp jump; the missing tail is all static main menu.

---

## 8. Limitations

- **Presence only.** No PASS/DELTA, no row score, no pixel/ROI verdict. The one
  numeric measurement (§4) is on the official keyframe, not on a port frame.
- **1 fps proxy.** Transient prompts and sub-second actions are under-sampled:
  the smoke-bomb throw (S18), the takedown pull-back (S23) and the ward eruption
  (S25) can be missed even though their states/results are visible.
- **Motion blur is ON** in this capture (settings still), so moving frames are
  soft; detail judgements were taken from holds (0–13, 244–256, 374–385, 390–541)
  wherever possible.
- **Part 3's cadence is poor** (`32,503 packets over the nominal 600 s`,
  `dup=996 drop=992`); no timing claim is made from it.
- **Different mission.** `Item Collection Heist` / 120 min / Staff of Edinburgh
  gems, not `Cleanout Heist` / 55 min / 4,000 loot. Mission-text rows must carry
  that caveat; the map and HUD frame are the shipped ones.
- **No audio.** All 31 AU rows are outside this lane's evidence. The plan also
  forbids level/loudness/silence claims from this capture (part-1 max 0.0 dBFS).
- **Full-res candidates are stills** (7 files) used to read UI copy; all
  *evidence* frames are the 480p proxy as instructed.
- **No claim** is made about part 1 outside §6, about the missing part 2, or
  about whether a beat is absent from the recording as a whole.

---

## 9. Evidence frames

Directory: `~/Videos/tat2_ref_20261127/review/` (outside git; not committed).
Proxy frames are **480×270**; the `r3_full_*` frames are **2560×1440**.

| File | p3 t | Backs |
|---|---|---|
| `r3_S01_startscreen_391.png` | 391 | S01 (menu stack, guard, neon, crates) |
| `r3_S01_startscreen_540.png` | 540 | S01 still live 149 s later |
| `r3_S01_menu_fade_389.png` | 389 | menu fade-in after the second pause |
| `r3_S02_loading_371.png` | 371 | S02/S10 art (return-to-Den load) |
| `r3_S02_loading_388.png` | 388 | S02/S10 art (Den → menu load) |
| `r3_S03_den_378.png` | 378 | S03 partial, S08 prop, S04–S07 absence |
| `r3_S18_smoke_41.png` | 41 | S18 plume |
| `r3_S18_smoke_49.png` | 49 | S18 plume + constable |
| `r3_S23_takedown_47.png` | 47 | S23 takedown prompt/lunge |
| `r3_S23_takedown_49.png` | 49 | S23 lunge |
| `r3_S22_key_53.png` | 53 | S22 key row appears |
| `r3_S22_key_54.png` | 54 | S22 gold key pickup icon |
| `r3_S23_down_111.png` | 111 | S23/G4-04 downed constable |
| `r3_S24_foyer_141.png` | 141 | S24 foyer/vitrine, `upper_foyer` |
| `r3_S24_foyer_147.png` | 147 | S24 chair/rug; `yaw180` absence |
| `r3_S24_beam_157.png` | 157 | S24 beam/emitter, `upper_foyer` |
| `r3_S24_beam_155.png` | 155 | `beam_close` |
| `r3_S24_corridor_beam_217.png` | 217 | S19 absence / corridor beam + loot marker |
| `r3_pose_lounge_5.png` | 5 | `lounge` hold 1, `gate`/`kf18_overlook` absence |
| `r3_pose_lounge_246.png` | 246 | `lounge` hold 2 (`lounge_beam` absence) |
| `r3_S25_basement_stairs_173.png` | 173 | S25 plaque |
| `r3_S25_vines_175.png` | 175 | S25 green vines |
| `r3_S25_ward_179.png` | 179 | S25 ward + jaw-trap icon |
| `r3_S25_ward_367.png` | 367 | S26 absence (ward intact after respawn) |
| `r3_S21_door_300.png` | 300 | S21 partial (key-locked door) |
| `r3_note_337.png` | 337 | S11 absence (different note) |
| `r3_fireplace_209.png` | 209 | V1-06 hearth pool |
| `r3_UI3_bar_41.png` | 41 | UI3-03 health bar |
| `r3_stash_229.png` | 229 | stash-room portal (non-row observation) |
| `r3_S27_pause_369.png` | 369 | S27 (RETURN TO THIEF'S DEN) |
| `r3_S27_pause_387.png` | 387 | S27 variant (RETURN TO MAIN MENU) |
| `r3_p1end_590.png` | p1 590 | part-1 boundary (ward + `Time Until Respawn`) |
| `r3_full_pause_369.png` | 369 | footer `1.5.148559 Novice 701694559` |
| `r3_full_key_53.png` | 53 | `Guildhall Key` row at 1440p |
| `r3_full_beam_155.png` | 155 | emitter + beam at 1440p |
| `r3_full_ward_179.png` | 179 | ward + jaw-trap icon at 1440p |
| `r3_full_foyer_141.png` | 141 | vitrine + checkered marble at 1440p |
| `r3_full_den_378.png` | 378 | Den at 1440p |
| `r3_full_menu_391.png` | 391 | startscreen copy at 1440p |

Proxy extraction used for every evidence frame:

```bash
ffmpeg -hide_banner -loglevel error -y -ss <t> \
  -i ~/Videos/tat2_ref_20261127/review/route_lossless_part3_1fps.mp4 \
  -frames:v 1 ~/Videos/tat2_ref_20261127/review/r3_<id>_<t>.png
```

Full-res candidates (seven kept as `r3_full_*`; no other original frame is cited):

```bash
ffmpeg -hide_banner -loglevel error -y -ss <t> \
  -i ~/Videos/tat2_ref_20261127/route_lossless_part3.mkv \
  -frames:v 1 /tmp/opencode/r3/full/t<t>.png
# then copied as review/r3_full_<id>_<t>.png
```

Part-1 boundary frames (part-1 proxy, for §6 only):

```bash
ffmpeg -hide_banner -loglevel error -y -ss 590 \
  -i ~/Videos/tat2_ref_20261127/review/route_lossless_1fps.mp4 \
  -frames:v 1 ~/Videos/tat2_ref_20261127/review/r3_p1end_590.png
```
