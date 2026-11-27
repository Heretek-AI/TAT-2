# Live-reference review — independent verification (2026-11-27)

**Scope.** Independent verification of `docs/reports/live-ref-review-20261127.md` (the synthesis),
`docs/reports/live-ref-review-plan.md`, and lanes R1/R2/R3. Read-only: the scorecard, lane reports,
synthesis, game and build files were not edited and nothing was committed; this file is the only
repo write. No Godot, Vulkan, Xvfb, Steam or GPU process was started. Methods: `ffprobe`,
`sha256sum`, frame re-extraction from the 480p proxies with `ffmpeg`, raw-RGB pixel measurement
with Python's standard library, visual inspection of the cited frames, and `git status` / `git diff`.

**Verdict: 8 PASS (check 5 resolved after the synthesis fixes).**

| # | Check | Verdict |
|---|---|---|
| 1 | Mission mismatch | **PASS** |
| 2 | 27-beat table (10 / 12 / 2 / 3 / 0) | **PASS** (note corrections applied) |
| 3 | Poses (0 present / 3 partial / 4 absent) | **PASS** |
| 4 | 120-row accounting (64 / 55 / 56) and tally | **PASS** |
| 5 | KF27 correction (40 % not 56 %; beam/node) | **PASS (resolved)** — emitter/56 % half and the corrected cyan-node / one-band text now match the keyframe measurements |
| 6 | Capture defects | **PASS** |
| 7 | Corrected-capture checklist | **PASS** |
| 8 | File hygiene | **PASS** |

The synthesis's headline answer is confirmed: **10 present, 12 partial, 2 wrong mission, 3 absent,
0 unseen-gap**, and the capture is the **Staff of Edinburgh `Item Collection Heist`**, not the
official **`Cleanout Heist`**.

---

## 1. Mission mismatch — PASS

All claims are frame-backed.

| Claim | Evidence | Result |
|---|---|---|
| Mission is `Item Collection Heist`, `120 minutes` | `~/Videos/tat2_ref_20261127/review/r1_full_prep_210.png` (2560×1440, from the original at p1 210): `MISSION PREPARATION`, `CONSTABLES' GUILDHALL`, **`Item Collection Heist`**, **`Time Limit: 120 minutes`**, `Contract Inactive`, `Mode: Solo`, `Difficulty: Novice`, `[F] READY` | Confirmed. Synthesis §2 line 143 matches |
| Not the Cleanout 55-minute briefing | `r1_s11_letter_235.png`: parchment reads *"Find the set of gems needed to complete the **Staff of Edinburgh** … **120 minutes** … remain for **20 minutes** before collapsing"*, with `CONTINUE`, over a blurred **outdoor street** | Confirmed; no `55 minute window`, no brick safe room |
| Outdoor canal-side spawn, Staff HUD | `r1_s12_spawn_241.png` and `r1_full_guildhall_247.png` (2560×1440): HUD `Mission: Steal the components of the Staff of Edinburgh[0/3]` with the three gem sub-lines; exterior paving, pipework, barrels, perimeter fence, moon | Confirmed. No `Steal 4,000 in loot value` in any frame |
| Den save state | `r1_s06_journal_010.png`: `JOURNAL` / `BLACK MARKET`, **Level 4**, **94/500**, `Contract #1` left-clipped **Completed**, `#2 Into the Lion's Den` **Completed**, `#3 In the Eye of the Beholder` **Active** | Confirmed; matches KF07. `r1_s06_blackmarket_026.png` shows `£26,275` |

Lane anchors: R1 `live-ref-lane-r1.md:88`, `:91`, `:95–102`, `:122`, `:124–125`; synthesis
`live-ref-review-20261127.md:131–153`. The `wrong mission` union label for S09/S11 is the correct
reading of these frames.

---

## 2. 27-beat table — PASS (note corrections applied)

Parsed from the §3.3 table (`live-ref-review-20261127.md:200–228`): **10 `present`** (S01, S04,
S05, S06, S08, S10, S23, S24, S25, S27), **12 `partial`** (S02, S03, S07, S12, S13, S14, S15,
S16, S18, S20, S21, S22), **2 `wrong mission`** (S09, S11), **3 `absent`** (S17, S19, S26),
**0 `unseen-gap`**. 10 + 12 + 2 + 3 = 27; matches the merged-counts paragraph at line 230–232.

Every `present` and every `partial` has at least one cited frame that exists and was inspected:

| Status | Beats and frames inspected | Outcome |
|---|---|---|
| present | S01 `r3_S01_startscreen_391/_540`; S04 `r1_s04_wardrobe_kf03_086/_kf04_122`; S05 `r1_s05_telescope_057`, `r1_s05_posters_189`; S06 `r1_s06_journal_010`, `r1_s06_blackmarket_026`; S08 `r1_s08_maptable_194`, `r1_s08_confirm_195`; S10 `r1_s10_loading2_225`; S23 `r3_S23_takedown_47/_49`, `r3_S23_down_111`; S24 `r2_upper_foyer_583`, `r2_S24_beam_582`, `r3_S24_foyer_141`, `r3_S24_beam_157`; S25 `r2_S25_ward_spawn_586`, `r2_S25_vines_587`, `r2_S25_ward_590`, `r3_S25_ward_179`; S27 `r1_s27_pause_254`, `r3_S27_pause_369` | All subjects present as stated |
| partial | S02 `r1_s10_mapload_196`, `r3_S02_loading_371`; S03 `r1_start_den_000`, `r3_S03_den_378`; S07 `r1_start_den_000`, `r1_s07_gramophone_180`; S12 `r2_S12_catwalk_304`; S13 `r1_s13_street_242`, `r1_s13_barrels_251`, `r2_S13_banner_316`, `r2_S13_street_340`; S14 `r2_S14_zipwire_411`; S15 `r2_S15_crank_495`; S16 `r2_S16_roofline_397`; S18 `r2_S18_canister_546`, `r2_S18_smoke_552`, `r3_S18_smoke_41`; S20 `r2_S20_balcony_452`, `r1_s13_guildhall_side_247`; S21 `r2_S21_doors_506`, `r2_S21_lockpick_511`, `r3_S21_door_300`; S22 `r2_S18_canister_546`, `r2_S23_guard_down_560`, `r3_S22_key_53/_54` | Each has the named subject and a named missing/different element |
| wrong mission | S09 `r1_s09_prep_210` (+`r1_s09_countdown_213`); S11 `r1_s11_letter_235` | `Item Collection Heist` / `120 minutes` and the Staff/120 letter over a blurred street — subject present, not the official beat |
| absent | S17 nearest `r2_S16_roofline_397`; S19 nearest `r3_S24_corridor_beam_217`; S26 `r3_S25_ward_179.png` (intact) + `r3_S25_ward_367.png` (pause) | No crowned pillars/griffins/gear plate; no caliper/scan pulse; no crimson alarm or stair ascent |

Specific confirmations:

- **S01 is the late live menu, not the route start.** `r3_S01_startscreen_391.png` and
  `r3_S01_startscreen_540.png` show the rainy `Mac Neish / Jeweller` shopfront, `THICK AS THIEVES`,
  `PLAY/SETTINGS/CREDITS/QUIT`, idle guard and crates. Part 3 has 541.7 s of content, so 390–541 is
  the end of the session. The two frames differ in **12.3 %** of pixels (>12 RGB sum), so the menu
  is animated, not a frozen image.
- **S23/S24/S25/S27 are as stated.** S23: `[F] [HOLD] TAKEDOWN` at p3 47 (zoom-verified at 8×),
  lunge, downed constable at p3 111. S24: checkered marble, vitrine, armchair + ottoman, floor
  plate, one white band from the left-wall emitter, cyan diamond above the far doors. S25: purple
  ward across the arch at p3 179 and p1 586/590; green vines with the `Basement Stairs` plaque at
  p3 175 and p1 587. S27: both pause variants at p1 254, p3 369 and p3 387, footer
  `1.5.148559   Novice   701694559`.
- **S26 is `absent` on state, not on the gap.** `r3_S25_ward_367.png` is in fact the pause overlay
  (the ward is visible only at the left edge); the unambiguous intact-ward frame is **p3 366**
  (`ffmpeg -ss 366`, checked in the 359–371 strip): the purple barrier fills the stair doorway and
  the health bar is still damaged. The run respawns at 361–363, pauses at **367** and loads the Den
  at 370; no crimson wash and no barrier shatter occur. The KF29 shatter cannot be hidden in the
  gap because the barrier it would have destroyed is still intact after the gap.
- **No false `absent` from the 226.5 s gap.** S17 and S19 precede the foyer, which is reached at
  p1 582 (before the gap), and the run never returns outside; S26 is ruled out by the intact ward
  after the gap. The three `absent` verdicts are safe.

### Note corrections — applied in the synthesis (no status change)

1. **S10 spinner note — resolved.** The synthesis line 211 now reads "visible in both R1's and R3's
   sampled frames", matching the frames: the cyan/white spinner ring is present in
   `r1_s10_loading2_225.png` and in `r1_s10_mapload_196.png` (8× crop unambiguous). S10 remains
   `present`. The former §6.4 UI4-05 "R1's sampled frame lacks the spinner" copy was aligned in the
   synthesis (`UI4-05` now says the spinner is visible in both); no count/status effect.
2. **S26/S27 frame and time — resolved.** The S26 row now cites
   `r3_S25_ward_179.png` (intact ward) plus `r3_S25_ward_367.png` (pause), states the barrier is
   **intact at p3 366** and the pause begins at **367**, and §3.4 repeats it. That matches the
   measured 359–371 strip. The S27 time column was aligned in the synthesis (pause begins at 367);
   no saved `r3_*_366.png` exists in `review/`, so the 366 statement is carried by the 179
   intact-ward frame + the 367 pause frame (sufficient for the `absent` verdict, since S26 is not a
   presence row).

---

## 3. Poses — PASS

Parsed from the pose table (`live-ref-review-20261127.md:276–287`): **0 present, 3 partial
(`upper_foyer`, `lounge`, `beam_close`), 4 absent (`gate`, `kf18_overlook`, `yaw180`,
`lounge_beam`)**. No 1:1 match.

- **`upper_foyer` (partial)** — `r2_upper_foyer_583.png`, `r2_S24_beam_582.png`,
  `r3_S24_foyer_141.png`, `r3_S24_beam_157.png`: the KF27 room is present, but the part-1 run
  582→584 is motion (band rows 49.6 / 47.4 / 51.5 % — three different pictures), not a 3 s hold;
  the part-3 views are a different heading/distance. Partial is right.
- **`lounge` (partial)** — `r2_lounge_577.png` is a billiard room (green baize, chandelier, tufted
  armchairs, tea table) with no bouncer in the frame; `r3_pose_lounge_5.png` and
  `r3_pose_lounge_246.png` are a different upper-hall/landing with a spherical pendant, balustrade,
  console and statue, and no NPC. Two rooms/angles, neither establishing the port's east→west
  framing. Partial is generous but supported.
- **`beam_close` (partial)** — `r3_S24_beam_155.png`: round wall emitter with a bright bulb and a
  thin beam leaving left, oblique at ~2–3 m; it is not the KF27 gold disc with a cyan cross, and the
  KF27 composition is not reproduced (see §5 for the node/beam caveat that must be reworded).
- **Absent** — `gate`: `r1_s13_guildhall_side_247.png` is a street-side perimeter gate only (no
  `CONSTABLE'S GUILDHALL` arch, no red-eyed guard, no car, no ZipWire). `kf18_overlook`:
  `r2_S16_roofline_397.png` is roof ridges/skylights/boiler, no crowned pillars/griffins/cable
  crossing. `yaw180`: `r3_S24_foyer_147.png` is a blurred sweep, with no matched reverse pair.
  `lounge_beam`: `r3_pose_lounge_246.png` shows the pendant, not a beam or emitter.
- **Residual limitation:** `yaw180` is a motion claim; a 1 fps proxy cannot prove a 180° turn was
  never performed. The evidence is the absence of any matched reverse framing in 141–157, which is
  weaker than the static-pose absences. This does not change the count.

---

## 4. 120-row accounting — PASS

Extracted the canonical 120 row ids from `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`
§2 and parsed the four §6 lists of the synthesis:

| Quantity | Value | Check |
|---|---|---|
| Look/geometry supportable (§6.3) | 32 rows | ✔ |
| HUD/UI supportable (§6.4) | 23 rows | ✔ |
| Not supportable (§6.5) | 9 rows | ✔ |
| Lane-listed distinct | **64** = 32 + 23 + 9 | ✔ no duplicates, no overlaps |
| Supportable | **55** = 32 + 23 | ✔ |
| No lane-listed subject (§6.6) | **56** = 31 AU + 7 V + 4 UI + 14 G | ✔ |
| Total | 64 + 56 = **120**; 55 + 65 = **120** | ✔ |
| Union covers the scorecard | all 120 ids, each exactly once | ✔ |

Set intersections between §6.3, §6.4, §6.5 and §6.6 are empty; every id exists in the scorecard
and no id is missing (the four lists partition all 120 rows).

- **Tally unchanged:** the scorecard says `PASS 9 / DELTA 33 / MISSING 4 / HARD_LIMIT 2 /
  UNVERIFIED 16 / N/A-route 56`, coverage line **48 scored / 56 N/A / 16 UNVERIFIED**
  (`COMPARISON_PORT_20261124.md:275–277`). The synthesis quotes the same at lines 36, 345, 546.
- **No row token assigned:** a grep for `PASS|DELTA|MISSING|HARD_LIMIT|N/A-route` finds only the
  disclaimers (lines 6, 347) and the quotes of the unchanged tally; the §6 tables use only
  supportable / not-supportable and caveats.
- **Scorecard unmodified by this review:** `git diff --stat --
  docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md` was empty and
  `git status --short docs/reference` clean at review time. Phase 0a later corrected **only** the
  official V6-03 cell with a dated erratum; the port-side cell and the 120 tally were not changed.
- **`row_route_matrix.md` provenance.** The matrix was git-ignored under
  `build/qa/review_20261124/` during this review; Phase 0a moved it (with `ADJUDICATIONS.md`) to
  `docs/reference/clip_1795033698901/` and tracked it. Its content still reads 43 YES / 21 PARTIAL /
  56 NO, which the scorecard reconciles to 48/56/16; the move changes provenance, not the tally.
  The 2026-11-24 capture media remains outside git.

---

## 5. KF27 correction — PASS (resolved)

**Emitter and the 56 % correction — confirmed.**

Re-measured the official keyframe `docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg`
(1920×1080, decoded to raw RGB): the brightest pixel of the left-wall emitter region is
**(341, 432)** = **17.76 % / 40.00 %**, RGB `(247,238,214)`; neighbours `(340,432)=(244,235,211)`
and `(342,432)=(238,230,203)`. The synthesis's position is exact; its RGB values differ by ≤2/255
from this decoder, which is immaterial. This confirms **40 %**, and the scorecard's V6-03 text
`x~17%, y~56%` (`COMPARISON_PORT_20261124.md:92`) is wrong. (The y≈56 % rows in KF27 are the bright
floor, rows 603–619 — a plausible row confusion.)

The live part-3 beam frames are not KF27-framed: `r3_S24_foyer_141.png`, `r3_S24_beam_155.png` and
`r3_S24_beam_157.png` are a different distance/heading, with the emitter at the right edge in
`beam_155`, not the left-wall 17.8 %. No live percentage is claimed, correctly.

The R2 part-1 numbers reproduce: on the 480p proxy the brightest band row is **49.6 %** (582),
**47.4 %** (583) and **51.5 %** (584), against the synthesis's 49.9 / 47.4 / 51.7 % on the 2560
frame; the emitter measures **14.6 % / 50.0 %** at 582 (synthesis 14.7 / 50.1). Single band in the
lane's y-band, confirmed.

**Original finding (now resolved): the cyan node and the two-beam premise.**

The first verification rejected two sentences of the first draft: "The cyan node is a wall sconce,
not the ceiling diamond" and "KF27 shows two wall-to-wall beams". The measurements behind that
rejection stand:

1. KF27's cyan pixels cluster at (1000, 270) = **52.1 % / 25.0 %**, brightest (1028, 252) =
   **53.5 % / 23.3 %** — above the far doors, not on the ceiling in pixel terms. The live foyer's
   cyan diamond is (256, 75) = **53.3 % / 27.8 %** (`r2_upper_foyer_583.png`). Node and beam shift
   together (23.3→27.8 %, 40.0→47.4 %), consistent with the same above-door fixture under a
   slightly different camera pitch.
2. KF27 has **one** band at rows **432–437 (40.0–40.5 %)**, about 6 px thick, spanning x≈341→1300;
   no second band appears in the row profiles over x 400–900, 900–1200 or 1200–1700.

**Resolution re-check (after the fixes).** The synthesis now matches these measurements:

- §5 now says "**The cyan node is the same above-door fixture, not a ceiling diamond**", with live
  **53.3 % / 27.8 %** and KF27 **53.5 % / 23.3 %** — verified against the pixel measurements.
- §5 now says "The official KF27 has **one beam band at 40.0–40.5 %**", that the live single band
  "matches the count", and that the live row 47.4–51.7 % is not a KF27 claim — verified.
- §5 now flags the whole official V6-03 cell ("two … beams", "cyan ceiling diamond") for the
  adjudication wave, not only `y %` — verified; the scorecard is still untouched (`git diff`
  empty, `git status` clean).
- The S24 row, `beam_close`, V4-07 and V6-03 coverage rows are reworded to the same numbers —
  verified at synthesis lines 225, 284, 392 and 399.
- S10 and S26 notes are corrected (see §2); the UI4-05 spinner copy and the S27 time were aligned in
  the synthesis, with no status or count effect.
- **Counts unchanged:** 27 beats still **10 / 12 / 2 / 3 / 0**; poses still **3 partial / 4
  absent / 0 present**; 120 rows still **32 + 23 + 9 + 56**, **64 lane-listed**, **55
  supportable**, all 120 covered once.

The original finding is closed. The only residual is the prose in `KEYFRAME_INDEX.md` / V6-03
itself ("two beams", `y~56%`), which the synthesis correctly defers to adjudication; the scorecard
must not be edited in this wave.

---

## 6. Capture defects — PASS

Re-measured on the originals (CPU container reads, one at a time):

| Claim | Measured | Verdict |
|---|---|---|
| Part 1 = 600.000 s content | `format duration 600.000000`, 36,000 video packets | ✔ |
| Part 3 = 541.7 s content | container 600.000 s, **last video packet PTS 541.700**, 32,503 packets | ✔ |
| 2560×1440 `gbrp` 60/1 + FLAC 48 kHz 2 ch `s16` | both files: `h264 2560x1440 gbrp 60/1`; `flac s16 48000 2ch` | ✔ |
| Part-1 dup/drop | recorder.log `frame=36000 fps=60 … dup=1961 drop=1955 time=00:10:00.00` | ✔ |
| Part-3 average 54.2 fps | 32,503 / 600 = 54.17; log `fps=54`, `dup=996 drop=992` | ✔ |
| −44.5 s jump | log `timestamp 540950 ms, current cluster 585456 ms, delta -44506 ms` | ✔ |
| 226.5 s gap | 1795762312.214556 − (1795761485.677568 + 600.000) = **226.536988 s** | ✔ |
| Audio max 0.0 dBFS | full part 1 `volumedetect`: mean −29.3 dB, **max −0.0 dB**, 34 samples at 0 dB | ✔ |
| No manifest / poses.tsv | neither file exists in `~/Videos/tat2_ref_20261127/` | ✔ |
| No `P0B_LIVE_VERIFY PASS` | only explicit denials (synthesis:121, 526; plan:132, 594) | ✔ |
| SHA-256 | `7f26edb0…d91089` (part 1), `41a86f18…e339d6` (part 3) — re-hashed, both match | ✔ |

Minor wording only: synthesis:58–59 says "the last ~150 s of the file is the static main-menu
tail". The menu content is 390–541.7 s (~151 s) and the missing timeline is 541.7–600 s (58.3 s);
the numbers are right, the sentence conflates the two. The plan's part-3 size `27,772,583,936` is a
transcription slip; the file is `27,781,290,849` B, as the synthesis says.

---

## 7. Corrected-capture checklist — PASS

`live-ref-review-20261127.md:513–526` names every required item:

| Required | Checklist row | Present |
|---|---|---|
| Cleanout Heist | 1 (`CONSTABLES' GUILDHALL — Cleanout Heist`, Novice, Solo) | ✔ |
| 55-minute prep | 2 (`Cleanout Heist` / `Time Limit: 55 minutes`) | ✔ |
| Pre-start mission check | 2 (explicit: "Do not start … If the prep card says `Item Collection Heist` / 120, back out and reselect") | ✔ — **no missing pre-start check** |
| Safe-room spawn | 3 (brick safe room, portal, lantern, `SPIDER`, catwalk) | ✔ |
| `Steal 4,000 in loot value` | 4 (in-band HUD confirmation, health hidden) | ✔ |
| Main-menu recorder start | 5 | ✔ |
| 900 s single file | 6 | ✔ |
| `TAT` window + format | 7 | ✔ |
| Lower Master / test | 8 (10 s test max < −1 dBFS) | ✔ |
| High groups at 100 % | 9 (with `Custom` label, FOV 85, V-Sync off, 60, Motion Blur ON) | ✔ |
| Pose holds + `poses.tsv` | 11 (six 3 s holds + KF18 still) | ✔ |
| Provenance | 12 (manifest, hashes, build, verify) | ✔ |

The settings still (`~/Videos/tat2_ref_20261127/settings_video.png`) independently confirms the
current capture's `TAT` window, `2560 × 1440`, V-Sync off, 60, Motion Blur on, FOV 85, `Custom`,
scale 100, High/High/High — matching §1.2.

---

## 8. File hygiene — PASS

```
git status --short
 M build/qa/p0b_live_capture.sh          # pre-existing, another lane; noted, not reverted
 M docs/reports/p0b-live-capture.md      # pre-existing, another lane; noted, not reverted
 M docs/HANDOFF_NEXT_AGENT.md            # modified 03:29 by the integrator, after this review; not by this verification
?? docs/reports/live-ref-lane-r1.md
?? docs/reports/live-ref-lane-r2.md
?? docs/reports/live-ref-lane-r3.md
?? docs/reports/live-ref-review-20261127.md   # fixed at 03:26 by the synthesis pass (untracked)
?? docs/reports/live-ref-review-plan.md
?? docs/reports/live-ref-review-verification.md   # this report
```

`git status --short docs/reference` is clean, `git status --short game` is clean, and
`git log --oneline -1` is still `4969d92` — no commit. The scorecard/game/build were not modified
by this review; the pre-existing helper/doc changes the brief identified were left alone, and the
handoff change (`docs/HANDOFF_NEXT_AGENT.md`, mtime 03:29) was made by the integrator after this
verification. Phase 0a (later, 2026-11-27) moved the two provenance documents and corrected only
the official V6-03 cell; the port-side cell and tally were not touched.

---

## 9. Corrections — status after the fixes

1. **§5 cyan node / two-beam — applied and verified.** The synthesis now states the same
   above-door fixture (live 53.3 %/27.8 %, KF27 53.5 %/23.3 %) and one KF27 band at 40.0–40.5 %;
   the S24, `beam_close`, V4-07 and V6-03 rows carry the same numbers. The official scorecard cell
   was corrected in Phase 0a with a dated erratum; the port-side cell stays Phase 3. Counts and
   statuses unchanged.
2. **S10 note — applied and verified.** Line 211 now says the spinner is visible in both R1's and
   R3's frames. The §6.4 UI4-05 copy was aligned in the synthesis; no count/status effect.
3. **S26 / S27 timing — applied.** S26 cites `r3_S25_ward_179.png` (intact) + the 367 pause frame
   and states 366 intact / 367 pause. The S27 time column was aligned in the synthesis; the 366
   statement has no saved 366 PNG in `review/` but is carried by the 179 intact frame and the 367
   pause, which suffices for an `absent` verdict.
4. **Optional wording — left as history.** §1.1's "~150 s" wording is unchanged; the
   `row_route_matrix.md` provenance was moved out of the git-ignored tree in Phase 0a (see §4).

---

## 10. Residual limitations (unchanged by this verification)

- **No audio analysis.** No lane did any; part 1 peaks at 0.0 dBFS (34 samples at full scale), so
  no level, loudness, duck, headroom or digital-silence claim can come from this capture. All 31 AU
  rows are out of scope.
- **The 226.5 s gap.** Part 2 is missing; the gap is content-ordered and could hide intermediate
  states. The synthesis handles this correctly for S17/S19 (before the foyer) and S26 (state-based).
- **The wrong mission.** The capture is `Item Collection Heist` / 120 minutes; it cannot settle any
  Cleanout-specific row (safe room, 55-minute briefing, `Steal 4,000`, official pacing).
- **1 fps, 480p proxies, motion blur, part-3 54.2 fps.** Content identification only; no motion,
  cadence or sub-second timing claims. `yaw180` is the weakest pose absence for this reason.
- **Provenance is not a `P0B_LIVE_VERIFY PASS`.** Hashes + ffprobe + recorder logs identify the
  bytes; there is no manifest, no `poses.tsv`, and no byte-verified build.
- **The official clip/keyframes remain the official reference.** This capture is coverage, not a
  score; the 120-row tally stays 48 / 56 / 16.
- **KF27 prose in `KEYFRAME_INDEX.md` still carries the old "two beams" / `y~56%` wording.** The
  official V6-03 cell was corrected in Phase 0a with a dated erratum; the keyframe index, port-side
  cell and 120 tally stay Phase 3.

---

## Appendix — reproduction

```bash
# capture identity (both files)
ffprobe -v error -count_packets -select_streams v:0 \
  -show_entries stream=codec_name,width,height,pix_fmt,r_frame_rate,nb_read_packets \
  -show_entries format=duration,size -of default=noprint_wrappers=1 route_lossless.mkv
sha256sum route_lossless.mkv route_lossless_part3.mkv
ffmpeg -hide_banner -nostats -i route_lossless.mkv -map 0:a:0 -af volumedetect -f null -

# frame provenance: 5/5 cited frames are byte-identical to a fresh proxy extraction
ffmpeg -ss <t> -i review/route_lossless_1fps.mp4 -frames:v 1 /tmp/chk.png
md5sum /tmp/chk.png review/<cited>.png      # MATCH at p1 210, 583; p3 47, 179, 391

# KF27 emitter (brightest in x<30 %, 25–55 % y) = (341,432) = 17.76 % / 40.00 %
ffmpeg -i clean/KF27_03m27s_foyer_security_beam.jpg -vf "crop=576:324:0:270" \
  -pix_fmt rgb24 -f rawvideo /tmp/kf27_left.raw

# live beam rows on the 480p proxy: 582=49.6 %, 583=47.4 %, 584=51.5 %; emitter 14.6 % / 50.0 %
```

**Verification report:** `docs/reports/live-ref-review-verification.md`.
**Verdict:** the synthesis's counts, mission mismatch, pose table, row accounting and capture
defects are confirmed, and the KF27 section is now **PASS (resolved)** — the emitter/40 %
measurement and the corrected cyan-node / one-band text match the official keyframe. The 27-beat,
pose and 120-row counts are unchanged. The UI4-05 and S27 notes were aligned in the synthesis and
are no longer residuals; the optional "~150 s" wording and the Phase 3 keyframe-index/port-side
corrections remain.
