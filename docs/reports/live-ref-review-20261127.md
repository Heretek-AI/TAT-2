# Live-reference synthesis — shipped-game capture, 2026-11-27

**Status:** synthesis of lanes R1, R2 and R3. Presence and coverage only. This report does **not**
re-score the port, does **not** edit `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`
or `docs/reference/clip_1795033698901/row_route_matrix.md`, and assigns no
`PASS` / `DELTA` / `MISSING` / `HARD_LIMIT` / `N/A-route` token to any row. No game, Godot, Vulkan,
Steam or GPU process was started for this synthesis; nothing was committed.

**Synthesis path.** The plan's §7.1 wave-report path is
`docs/reports/live-ref-review-20261127.md`; that is this file. The plan's four companion artifacts
(`docs/reports/logs/live-ref-20261127/beat_presence.md`, `beat_presence.json`, `row_coverage.md`,
`poses.md`) are folded into §3, §4 and §6 here rather than written as separate files, because this
task specified one synthesis report. No separate logs directory was created.

**Inputs used.** `docs/reports/live-ref-review-plan.md`; `docs/reports/live-ref-lane-r1.md` (part 1,
0–300 s); `docs/reports/live-ref-lane-r2.md` (part 1, 300–600 s); `docs/reports/live-ref-lane-r3.md`
(part 3, 0–542 s); `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md`,
`COMPARISON_PORT_20261124.md` and `clean/*.jpg`; `docs/reference/clip_1795033698901/row_route_matrix.md`;
`docs/reports/p0b-live-capture.md` §5 Steps 11–12; `docs/reports/p0b-route-rescore.md`. The lane
evidence frames are in `~/Videos/tat2_ref_20261127/review/` (outside git); all are 480×270 proxy PNGs
except the `r1_full_*` and `r3_full_*` frames, which are 2560×1440.

**Claim boundary.** The footage is the **shipped UE5.5 build** (`1.5.148559`) on the owner's machine,
not the port. The official `clip_1,795,033,698,901.mp4` and its 30 keyframes remain the official
reference. This capture is a matched-settings second ground truth for what the shipped build renders,
not a replacement for the official route.

**Answer in one paragraph.** Of the 27 official beats, **10 are `present`, 12 `partial`, 2
`wrong mission`, 3 `absent`, and 0 `unseen-gap`**. Of the seven poses, **0 are present, 3 `partial`
(`upper_foyer`, `lounge`, `beam_close`) and 4 `absent`**; there is no 1:1 pose match. The capture is
the **Staff of Edinburgh Item Collection Heist** (120-minute limit, outdoor canal-side spawn), not the
official **Cleanout Heist** (55-minute limit, brick safe-room spawn). The Den save state matches the
reference; the startscreen subject is present at the end of the session (framing differs); the official
mission flow, safe room, gate/gear-plate sequence, Vistara scan, crimson alarm and quit flow do not. **64 distinct rows have a lane-listed subject; 55
support a look/geometry or HUD/UI judgement and 9 do not; the other 56 rows have no lane-listed
subject.** The 120-row tally is unchanged at **48 scored / 56 N/A / 16 UNVERIFIED**.

---

## 1. Capture inventory and provenance

### 1.1 The two files and the missing part

| | Part 1 | Part 3 |
|---|---|---|
| Path | `~/Videos/tat2_ref_20261127/route_lossless.mkv` | `~/Videos/tat2_ref_20261127/route_lossless_part3.mkv` |
| Size | `27,158,471,556` B (25.29 GiB) | `27,781,290,849` B (25.87 GiB) |
| Container duration | `600.000 s` | `600.000 s` nominal |
| **Video content end** | **600.000 s** | **541.700 s** (last video packet) |
| Video | `h264`, 2560×1440, `gbrp`, `60/1`, **36,000 packets** | `h264`, 2560×1440, `gbrp`, `60/1`, **32,503 packets** |
| Average over nominal 600 s | 60.0 fps | **54.2 fps** |
| Audio | `flac`, 48 kHz, 2 ch, `s16` | same |
| SHA-256 | `7f26edb0b420e40ab56fe98ba5f8c7cddd1dedd4ce6c79ab868797fcf9d91089` | `41a86f18e3562ec9a8b268f90f0e742590777097a9603f516b821cf541e339d6` |
| Recorder log | `frame=36000 fps=60 dup=1961 drop=1955 time=00:10:00.00` | `frame=32503 fps=54 dup=996 drop=992 time=00:10:00.00`; backward timestamp jump `540950 ms` vs cluster `585456 ms`, delta **−44,506 ms** |

Both hashes match the plan §1.1. The two proxies in `review/` are 480×270, 1 fps:
`route_lossless_1fps.mp4` has **600** packets / 600.000 s; `route_lossless_part3_1fps.mp4` has
**542** packets / 542.000 s. Part 3 therefore has **541.7 s of video content, not 600 s**. The last
~150 s of the file is the static main-menu tail, so no reviewed beat is in the missing 58.3 s, but
the file cannot supply a 600 s timeline. (The plan §1.1 prints `27,772,583,936` B for part 3; `stat`
and `ffprobe` on the file with the recorded SHA-256 read `27,781,290,849` B. The hash identifies the
bytes; the plan's size is a transcription slip.)

**Part 2 is missing.** There is no `route_lossless_part2*` file. The recorder was killed at start and
restarted as part 3. The gap measured from the two x11grab start epochs is:

```
part 1 start = 1795761485.677568   part 1 end = start + 600.000 = 1795762085.678
part 3 start = 1795762312.214556
gap          = 1795762312.215 - 1795762085.678 = 226.537 s  (3:46.5)
```

So wall-clock `t ≈ 600.0 s → 826.5 s` of the session is **unrecorded**. This is long enough to hold
the whole portico→foyer sequence or all seven pose holds; it is content-ordered, not clock-ordered,
because nobody knows which beat the run had reached at `t = 600`.

### 1.2 Settings (measured from the two stills, not the ini)

Both settings stills are 3840×2160 full-desktop screenshots showing the game window titled **`TAT`**
inside the desktop. The capture itself is the 2560×1440 client.

| Screen | Value |
|---|---|
| Window Mode | `Windowed` |
| Resolution | `2560 × 1440` |
| V-Sync | **unchecked (off)** |
| FPS Limit | `60` |
| Motion Blur | **checked (ON)** |
| Field of View | `85` horizontal → ≈54.5° vertical at 16:9 (the authored lens) |
| Quality Preset | **`Custom`** |
| Resolution Scale | `100` |
| View Distance / Shadows / Textures | `High` / `High` / `High` |
| Master / Music / SFX / Dialogue | `100` / `100` / `100` / `100` |

The `Custom` label is expected, not a deviation: the High preset sets `ResolutionQuality=71`, and
re-setting the scale to 100 afterwards leaves the preset label at `Custom` while every quality group
stays High. Quote it as **"High groups at 100 % scale, preset label Custom"**, never as "High preset".
Motion Blur is ON, so moving 60 fps frames are blurred; detail and edge judgements come only from
holds, menus, poses or near-still frames.

### 1.3 Audio caveat

The capture taps the Pulse sink monitor, i.e. the game's actual mixed output. Master/Music/SFX/Dialogue
are all at 100. The owner's `volumedetect` on full part 1 reports **max 0.0 dBFS**, while the 10 s
test reports mean −18.1 dBFS / max −5.6 dBFS. A full-scale peak means **clipping cannot be excluded**
on loud cues. Therefore:

- no level, loudness, headroom, duck-depth or "digital silence" claim may come from this capture;
- cue identity and ordering may be logged as `cue-heard` / `cue-not-heard` notes with a timestamp,
  and those notes never change a row token;
- the official clip's own levels remain the reference.

No lane performed audio analysis, so this synthesis makes no audio claim at all.

### 1.4 Provenance gaps

- **There is no `manifest.json` and no `poses.tsv`** in the capture directory. `build/qa/p0b_live_capture.sh verify`
  was never run on these files.
- That helper is hard-wired to `$CAPDIR/route_lossless.mkv` and a single capture, so it cannot verify
  a two-part session as-is. Provenance here is the recorded SHA-256 + `ffprobe` lines above plus the
  recorder logs — enough to identify the bytes, **not** a `P0B_LIVE_VERIFY PASS`.
- The install reports buildid `25076818` with StateFlags `4`, and `TAT-Win64-Shipping.exe` is present,
  but no build hash was taken at record time. The settings still and the pause footer
  (`1.5.148559   Novice   701694559`) are the in-band build evidence. Do not claim a byte-verified
  build.

---

## 2. The mission mismatch (headline)

**Both parts are the Staff of Edinburgh Item Collection Heist, not the official Cleanout Heist.**

| | Recorded session | Official clip |
|---|---|---|
| Mission | **`Item Collection Heist`** | **`Cleanout Heist`** |
| Time limit | **120 minutes** | **55 minutes** |
| Objective | **`Steal the components of the Staff of Edinburgh [0/3]`** — Gem of Arcana / Strength / Fire | **`Steal 4,000 in loot value [0/4,000]`** |
| Spawn | **Outdoor canal-side street** (paving, barrels, pipework, iron fence) | **Brick safe room** (KF14: industrial arched window, lantern, `SPIDER` flyer, green/violet portal, catwalk) |
| Briefing | Staff of Edinburgh letter, 120 minutes, blurred outdoor street | 55-minute window / 20-minute magic door, blurred brick safe room (KF13) |
| Pause footer seed | `701694559` | `1025051536` |

The prep screen is measured, not inferred: `r1_s09_prep_210.png` reads
`CONSTABLES' GUILDHALL` / **`Item Collection Heist`** / **`Time Limit: 120 minutes`** /
`Contract Inactive`, with `Mode: Solo` / `Difficulty: Novice`, and `MISSION STARTING IN 6...` follows at
`r1_s09_countdown_213.png`. The HUD tracker is **`Mission: Steal the components of the Staff of
Edinburgh [0/3]`** with the three gem sub-lines, not `Steal 4,000 in loot value`. Part 3 continues the
same run: same mission line, same seed `701694559`, and the same `(£) 0 → 370` purse.

**The Den save state matches the reference exactly.** `r1_s06_journal_010.png` shows `Level 4`,
`94/500`, Contract #1 (left-clipped, Completed), #2 *Into the Lion's Den* (Completed) and #3 *In the
Eye of the Beholder* (Active), matching KF07. The Black Market total is `£26,275`, matching KF08. The
Den front end is therefore directly comparable; the mission-selection and everything downstream is
not.

**Label used below.** Where the official beat's subject is a screen or copy that names the mission,
the union status is **`wrong mission`**, with the exact phrase **`wrong mission — subject present, not
the official beat`**. Where the subject is geometry or HUD that exists on both contracts, the status
stands and the note carries a **†**, shorthand for the same phrase: **`wrong mission — subject
present, not the official beat`**, i.e. the surrounding mission context is the Staff contract, not
the official Cleanout beat. The `†` is a caveat, not a status change.

**Consequences carried through this report.** The map, the Guildhall rooms, the HUD frame and the Den
are the shipped assets and are usable for look/geometry evidence. Mission copy, objective strings,
spawn, letter, guard/loot placement, route order and the 120-minute pacing are not the official run.
A row scored against the official safe-room alley, Cleanout objectives or 55-minute briefing cannot be
settled from this capture.

---

## 3. S01–S27 merged presence table

### 3.1 Time conventions and reconciliation

- **R1** times are proxy `mm:ss` on the 600 s part-1 proxy, sampled at 1 fps; ±1 s. R1's full-res
  candidates are from the original at t = 210, 235, 247 and 254 s.
- **R2** times are **proxy seconds** on the same part-1 proxy. Measured mapping: **proxy frame N ≈
  source t = N + 0.4 s** (best RMSE 0.0081 at source 583.4 s for proxy 583; a one-frame input seek on
  the 27 GB original stops about 0.4 s early because of the ~250-frame GOP). R2 source times are
  therefore ≈ +0.4 s; the table keeps R2's proxy seconds, so add ~0.4 s for source time.
- **R3** times are **part-3 proxy seconds = source container PTS**, verified by `md5sum` of `-ss 391`,
  `-ss 179` and `-ss 246` against the decoded frame set. Part 3 is 541.7 s of content, not 600 s.
- The official route clock (S01 = 00:00, S27 = 03:41.90) does **not** apply to either part. Part 1's
  clock is the recorder clock; the live run reaches the foyer at p1 ≈ 582 s, far from the official
  03:22. Use the official times only to identify the beat, never as a schedule.

### 3.2 Lane counts before the union (window-only, not additive)

| Lane | `present` | `partial` | `absent` | `unseen-gap` | Window |
|---|---|---|---|---|---|
| R1 | 6 (S04, S05, S06, S08, S09, S10) | 6 (S02, S03, S07, S11, S13, S27) | 15 (S01, S12, S14–S26) | 0 | p1 0–300 s |
| R2 | 2 (S24, S25) | 10 (S12–S16, S18, S20–S23) | 13 (S01–S11, S17, S19) | 2 (S26, S27) | p1 300–600 s |
| R3 | 4 (S01, S23, S24, S27) | 8 (S02, S03, S08, S10, S18, S21, S22, S25) | 15 (S04–S07, S09, S11–S17, S19, S20, S26) | 0 | p3 0–541 s |

These are window verdicts, not route verdicts. The merged table below is the union; it is not a sum
of the three rows. In particular R1's S09 is "present (different mission)" and R1's S11 is `partial`;
the merged status for both is `wrong mission`.

### 3.3 The 27 beats

| ID | Official t / KF | Union status | Part / time(s) | Evidence frame(s) | Note |
|---|---|---|---|---|---|
| **S01** | 00:00.00 / KF01 | **present** | p3 390–541 (late) | `r3_S01_startscreen_391.png`, `r3_S01_startscreen_540.png` | Rainy `Mac Neish / Jeweller` street, right-aligned `THICK AS THIEVES` + `PLAY/SETTINGS/CREDITS/QUIT`, cursor, idle guard, crates. Reached as the **end** of the session, not the route start; framing is closer than KF01, with two out-of-focus foreground occluders and no identifiable car fender. R1/R2 are absent only because their windows are mid-Den/mid-mission. |
| **S02** | 00:02.15 / (KF12 art) | **partial** | p1 03:16; p3 370–373 | `r1_s10_mapload_196.png`, `r3_S02_loading_371.png` | KF12 art appears twice, but neither is the menu → Den load S02 defines: p1 03:16 is a map load on the way into prep; p3 370–373 is a capture → Den return load. R2 absent. |
| **S03** | 00:02.60 / KF02 | **partial** | p1 00:00, 01:24; p3 374–385 | `r1_start_den_000.png`, `r1_s04_loadout_prompt_084.png`, `r3_S03_den_378.png` | Den interior, rafters, rolltop desk, armoire and telescope are present, but the scripted fade-in/rising pan/entry is not: p1 starts already standing at the decoration table; p3 is a post-capture return at a wider angle. |
| **S04** | 00:06.57 / KF03, KF04 | **present** | p1 01:25–02:37 | `r1_s04_wardrobe_kf03_086.png`, `r1_s04_wardrobe_kf04_122.png` | Full `WARDROBE` overlay: Spider/Chameleon, `Edit Loadout`, tooltips, 3D Spider. KF03 state at 01:26 (Zipwire tooltip; Head shows the cap, not KF03's bowler) and KF04 state at 02:02 (slot-3 drawer + Vistara Diamond tooltip). R2/R3 absent. |
| **S05** | 00:18.24 / KF05, KF06 | **present** | p1 00:50–01:02, 03:05–03:10 | `r1_s05_telescope_057.png`, `r1_s05_posters_189.png` | Crater moon + golden cheese wedge + orbiting chunks + `[F] EXIT`; five framed `WANTED` posters beside the leaded window. Cheese chunks read as four vs the reference's three; poster text is not legible at 480p. R2/R3 absent (R3 sees the telescope prop only, no `[F] PONDER`). |
| **S06** | 00:26.58 / KF07, KF08 | **present** | p1 00:10–00:46 | `r1_s06_journal_010.png`, `r1_s06_blackmarket_026.png` | `JOURNAL`: Level 4, 94/500, Contract #2 Completed / #3 Active — matches KF07. `BLACK MARKET`: `YOUR TOTAL ASSETS: (£) 26,275`, four columns, ✓/padlocks — matches KF08. The preview selection differs from KF08's `Zipwire ✓ PURCHASED`; record, do not score. |
| **S07** | 00:38.17 / KF09 | **partial** | p1 00:00–00:05, 02:52–03:02 | `r1_start_den_000.png`, `r1_s07_gramophone_180.png` | Table diamond + `[F] CHANGE DECORATION` at the decoration station; trunks and gramophone visible in the dark prop corner. KF09's composition (lit three-candle candelabra, `[F] TURN OFF`, green floor diamond and table diamond in one frame) is not reproduced; the gramophone prompt is not legible at 480p; no trunk treasure cycle seen. |
| **S08** | 00:51.08 / KF10 | **present** | p1 03:11–03:15; p3 378 | `r1_s08_maptable_194.png`, `r1_s08_confirm_195.png`, `r3_S03_den_378.png` | 3D `KILCAIRN` table, wooden `CONSTABLES' GUILDHALL` token, banker's lamp, bust, `[F] ENTER MATCH`, then the `Join Mission with these settings?` modal. p3 378 shows the parchment/token only. The table/modal subject is present; the mission selected is the Staff contract (†). |
| **S09** | 00:56.08 / KF11 | **wrong mission** | p1 03:17–03:38 | `r1_s09_prep_210.png`, `r1_s09_countdown_213.png` | Full `MISSION PREPARATION` screen and `MISSION STARTING IN 6…1`, but the card reads **`Item Collection Heist` / `Time Limit: 120 minutes` / `Contract Inactive`**. Official is `Cleanout Heist` / `55 minutes`. **wrong mission — subject present, not the official beat.** |
| **S10** | 01:04.80 / KF12 | **present** | p1 03:39–03:50; p3 388 | `r1_s10_loading2_225.png`, `r3_S02_loading_388.png` | KF12 art after prep, which is the correct flow position for S10; gold emblem and `LOADING...` present. The spinner ring is visible in both R1's and R3's sampled frames. p3 388 is a Den → menu load (second occurrence). |
| **S11** | 01:09.44 / KF13 | **wrong mission** | p1 03:51–03:58 | `r1_s11_letter_235.png` | Parchment, `[SPACE] CONTINUE` and right scrollbar are present, but the copy is the **Staff of Edinburgh** 120-minute letter and the backdrop is a blurred **outdoor street**, not KF13's blurred brick safe room with the 55/20-minute copy. **wrong mission — subject present, not the official beat.** |
| **S12** | 01:10.81 / KF14 | **partial** | p1 300–306 | `r2_S12_catwalk_304.png` | Exterior metal-grate catwalk with iron railings (the beat's exit half) is present. Missing: the brick safe-room interior, the jagged green/violet Escape Portal, the lit lantern + `[F] TURN ON`, and the `SPIDER` flyer. The spawn is the outdoor canal street (`r1_s12_spawn_241.png`), not the brick safe room (†). R1/R3 absent. |
| **S13** | 01:20.10 / KF15 | **partial** | p1 03:59–04:12 (R1); p1 311–322, 336–341 (R2) | `r1_s13_street_242.png`, `r1_s13_barrels_251.png`, `r2_S13_banner_316.png`, `r2_S13_street_340.png` | Two street fragments: R1's wet canal-side approach with barrels, pipework, iron fence and a distant Guildhall; R2's brick alley with the **clipped `…'S DEMOLITI[ON]`** banner, oil drums, hand cart, streetlamp and wet cobbles. Missing: the full `BARRON'S DEMOLITION` / `EST. 1865` / tagline, the car `[F] INTERACT` + double-honk + headlights, and the gate approach (†). R3 absent. |
| **S14** | 01:39.30 / KF16 | **partial** | p1 400–423, 482–501 | `r2_S14_zipwire_411.png` | ZipWire `[1]` in hand with a multi-strand cable, `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`, rooftop launch and flight. Missing: the wrought-iron `CONSTABLE'S GUILDHALL` arch, the red-eyed guard with a yellow alert bar, the car headlights, and the planter landing (†). R1/R3 absent. |
| **S15** | 01:49.50 / KF17 | **partial** | p1 490–495 | `r2_S15_crank_495.png` | `CRANK` circular gauge at centre and the cable reel in hand during a zipwire flight. Missing: the roof-parapet anchor, the ~7 s 1P crank ascent, and the clocktower in mist (†). R1/R3 absent. |
| **S16** | 01:58.50 / — | **partial** | p1 390–440 | `r2_S16_roofline_397.png` | Slate/roof ridge walking, skylights, chimneys, parapets and a boiler/tank with `[F] TURN OFF`. Missing: the winch/gear housing and the 3rd zipwire to a gate pillar; no crowned pillar is reached (†). R1/R3 absent. |
| **S17** | 02:11.00 / KF18 | **absent** | — | `r2_S16_roofline_397.png` (nearest) | No crowned star-topped pillars, twin stone griffins, white 10-bolt gear plate with a red `⚡`, or courtyard descent. The 10-bolt **pipe flange** on the boiler at 424–439 is a different object. R1/R2/R3 absent, and S18 is present after it, so it is outside the gap shadow. |
| **S18** | 02:23.30 / KF19, KF20 | **partial** | p1 546–557; p3 39–52 | `r2_S18_canister_546.png`, `r2_S18_smoke_552.png`, `r3_S18_smoke_41.png` | The cylindrical `[2]` canister in the 1P hand and a dense opaque grey-white plume in two different interiors (Lounge at p1 546–557; bedroom at p3 39–52). Missing: the courtyard grand-stair throw, the orange-white ignition flash, and the horizontal stair-spanning plume (†). Plume presence only. |
| **S19** | 02:30.70 / KF21, KF22 | **absent** | — | `r3_S24_corridor_beam_217.png` (nearest) | The Vistara Diamond stays in hotbar slot `[4]` and is never equipped: no caliper mount, no scan pulse, no RED → GREEN silhouette. The blue-white arc at p1 549 is an electric baton discharge, not a scan. R1/R2/R3 absent; outside the gap. |
| **S20** | 02:33.00 / KF23 | **partial** | p1 440–470; R1 04:07–04:11 distant | `r2_S20_balcony_452.png`, `r1_s13_guildhall_side_247.png` | Rain-wet stone balcony, stone balustrade, iron fence and a patrolling lantern constable are present. Missing: the crisp vertical gold `MACLEOD` sign. R1 reports a distant `MACLEOD` from the street; R2's only large neon at p1 411 is red and *MELVIN*-like, cut by the frame edge, not `MACLEOD`. **Conflict:** see §3.4; safer reading is that the KF23 side-wing/sign composition is not reproduced (†). R3 absent. |
| **S21** | 02:54.50 / KF24 | **partial** | p1 495–529; p3 300 | `r2_S21_doors_506.png`, `r2_S21_lockpick_511.png`, `r3_S21_door_300.png` | R2: arched stone portico, blue-grey diamond-mullion double doors, twin brass pulls, blue glass sconces, doors opened and walked through. Missing/different: the door is locked, so the reticle is `[F] PICK LOCK` / `Lock Level 2` with a lockpick widget, not the KF24 `[F] OPEN` above `[F] [HOLD] LOCK` → `[F] CLOSE` pair; no scaffolding. R3: a pale blue-grey key-locked door (`[F] [HOLD] UNLOCK WITH KEY`), not the double doors (†). R1 absent. |
| **S22** | 03:04.50 / KF25 | **partial** | p1 544–548, 558–563; p3 45–55 | `r2_S18_canister_546.png`, `r2_S23_guard_down_560.png`, `r3_S22_key_53.png`, `r3_S22_key_54.png` | A constable in blue with red eyes, belt and baton at close quarters, grabbed at a window; the **`Guildhall Key` HUD row first appears at p3 53** (absent at 5, 50–52; present at 53) with a gold key pickup icon at 54. Missing: the hearth/chandelier Fireplace Parlor and the `[F] PICK POCKET` label/action itself; the key icon is visible, the pickpocket is not (†). R1 absent. |
| **S23** | 03:17.10 / KF26 | **present** | p3 45–53; p1 544–563 (second occurrence) | `r3_S23_takedown_47.png`, `r3_S23_takedown_49.png`, `r3_S23_down_111.png`; `r2_S23_guard_down_560.png` | `[F] [HOLD] TAKEDOWN` over a constable's helmet/shoulder at point-blank range with a 1P lunge; a downed constable is visible later at p3 111. The KO/pull-back is not sampled at 1 fps. R2's grapple/prone at p1 544–563 is a second occurrence from a different angle (†). R1 absent. |
| **S24** | 03:22.00 / KF27 | **present** | p1 582–585; p3 139–158 | `r2_upper_foyer_583.png`, `r2_S24_beam_582.png`, `r3_S24_foyer_141.png`, `r3_S24_beam_157.png` | Checkered marble floor, tall glass vitrine, red armchair + ottoman, square floor plate, a horizontal white beam from a left-wall emitter, cyan diamond sconce above the far doors, `WC` plaque. R2 measures **one band**; R3 sees two parallel light lines from the emitter but never two wall-to-wall beams in one frame. KF27 has **one beam band at 40.0–40.5 %**; the live single band matches the count, but the live row is 47.4–51.7 % and the camera pitch is unknown. The cyan above-door node is present (live 53.3 %/27.8 %; KF27 53.5 %/23.3 %); R3's 40-frame ceiling strip sweep (136–175) finds no separate ceiling diamond. R3 confirms the same room/vitrine/mannequin/rug. † |
| **S25** | 03:29.00 / KF28 | **present** | p1 586–591; p3 173–191, 367 | `r2_S25_ward_spawn_586.png`, `r2_S25_vines_587.png`, `r2_S25_ward_590.png`, `r3_S25_ward_179.png`, `r3_S25_vines_175.png` | The purple faceted ward and green thorny vines are both present: R2 sees the ward appear **after** the beam is crossed (585 → 586) with vines on the adjacent doorway; R3 sees the ward across the arch and vines on the `Basement Stairs` door, gold plaque legible, jaw-trap status icon. R2 and R3 **disagree on which doorway carries the ward vs the vines**; both subjects are present, so the union stands. The eruption itself is between 1 fps samples; only one of the two KF28 status icons (jaw-trap) is seen. † |
| **S26** | 03:37.40 / KF29 | **absent** | — | `r3_S25_ward_179.png`; `r3_S25_ward_367.png` (pause) | **Conflict:** R2 marks `unseen-gap?` because p1 ends mid-respawn at 599; R3 rules it out by state — the ward barrier is still **intact** at p3 366, the pause overlay begins at 367, the player respawns at 361 and leaves for the Den at 368, and no crimson alarm or slate-stair ascent occurs. A barrier shatter that never happened cannot be hidden by the gap. Safer reading: **absent**, not `unseen-gap`. |
| **S27** | 03:41.90 / KF30 | **present** | p1 04:13–04:14; p3 367–369, 386–387 | `r1_s27_pause_254.png`, `r3_S27_pause_369.png`, `r3_S27_pause_387.png` | Pause modal layout and footer match (`RESUME / SETTINGS / RETURN TO THIEF'S DEN / QUIT TO DESKTOP`, `1.5.148559   Novice   701694559`). R1 is a mid-route settings detour; R3 is the route end via `RETURN TO THIEF'S DEN`, then a second pause with `RETURN TO MAIN MENU`. No `QUIT TO DESKTOP` selection, no teardown, no digital-silence tail; the seed differs from the official `1025051536`. † |

**Merged counts:** **10 `present`** (S01, S04, S05, S06, S08, S10, S23, S24, S25, S27), **12
`partial`** (S02, S03, S07, S12, S13, S14, S15, S16, S18, S20, S21, S22), **2 `wrong mission`**
(S09, S11), **3 `absent`** (S17, S19, S26), **0 `unseen-gap`**. 10 + 12 + 2 + 3 = 27.

### 3.4 Conflicts and the safer reading

1. **S26 — R2 `unseen-gap?` vs R3 `absent`.** R2 could only see p1 end mid-respawn; R3 saw the later
   state. The barrier is intact at p3 366 (pause 367) and the run leaves for the Den at 368, so the KF29 shatter
   and crimson alarm never happened. Safer: `absent`. Keep R2's `unseen-gap?` as the window verdict;
   the union is state-based.
2. **`gate` pose — R1 `partial` vs R2/R3 `absent`.** R1's 04:07 frame is a street-side perimeter gate
   with an iron fence, stone piers and a red-lit lifting gate, but it has **none** of KF16's defining
   elements: no `CONSTABLE'S GUILDHALL` arch lettering, no red-eyed guard/yellow alert bar, no vintage
   car/headlights, no ZipWire viewmodel. R1 itself calls it "not KF16's gate" and a judgement call.
   Safer for a 1:1 pose table: `absent`; retain the frame as the nearest-subject evidence.
3. **S20 `MACLEOD` — R1 distant vs R2 absent/red sign.** R1 sees a vertical sign in the distance from
   the canal-side approach at p1 04:07–04:11; R2's KF23-side wing at p1 440–470 has no crisp gold sign,
   and the only large neon at 411 is red and *MELVIN*-like. Safer: the `MACLEOD` sign is at most a
   distant, unconfirmed subject; the KF23 side-wing composition is not reproduced. Do not use R1's
   distant frame as a KF23 match.
4. **S25 trigger — R2 `present` vs R3 `partial`.** R2 sees the ward appear after the beam is crossed
   (585 → 586), so the order is visible; R3 sees the already-up state and cannot see the eruption.
   Union `present` because the ward/vines and the order are both on screen; note that the exact
   crossing is between 1 fps samples, so the trip itself is inferred, not sampled.
5. **S25 doorway assignment — R2 vs R3 vs KF28.** R2 reads the ward on the `Basement Stairs` side and
   the vines on the adjacent doorway; R3 reads the ward across the arch and the vines on `Basement
   Stairs`; KF28 puts the ward on the forward arch and the vines on `Basement Stairs`. Both subjects
   are present in both lanes, but the assignment is not consistent. Safer: count the ward + vines as
   present, do not use either doorway assignment as a row finding.
6. **S02/S10 shared art.** R1's p1 03:16 load and R3's p3 370–373 load are both `partial` because they
   are in the wrong flow position (map load into prep; capture → Den return). R1's p1 03:39–03:50 load
   is `present` as S10 because it follows Mission Prep, which is S10's defining flow position. Do not
   upgrade the two partials.
7. **S01 — R1/R2 absent vs R3 present.** The windows differ, not the build. Union `present` (late):
   the official startscreen subject is visible at p3 390–541, but it is the end of the session, not
   the boot. Do not call S01 absent from the recording.

---

## 4. Pose table

Pose ids and anchors are the P0b contract (`docs/reports/p0b-live-capture.md` §5 Step 12): six 3 s
holds plus the KF18 still. The port's six-pose capture remains the **pose reference**; this live
capture did not execute the holds, and the near-static runs it does contain (p3 0–13, 244–256,
390–541) are incidental menu/landing holds, not pose holds.

| Pose | Official cue | Union status | Part / time(s) | Evidence frame(s) | Note |
|---|---|---|---|---|---|
| `gate` | KF16 01:40.20 | **absent** | — (nearest p1 04:07) | `r1_s13_guildhall_side_247.png` | Street-side perimeter gate/fence only. No `CONSTABLE'S GUILDHALL` arch, red-eyed guard + yellow alert bar, vintage car/headlights, or ZipWire `[1]`. R1's `partial` is a judgement call; R2/R3 absent. Safer: absent for the pose. |
| `kf18_overlook` | KF18 02:14.80 | **absent** | — | `r2_S16_roofline_397.png` (nearest) | No crowned star-topped pillars, twin griffins, gear plate or cable crossing over the arch. The window has roof ridges, skylights and a boiler instead. |
| `upper_foyer` | KF27 03:27.60 | **partial** | p1 582–584; p3 141–157 | `r2_upper_foyer_583.png`, `r2_S24_beam_582.png`, `r3_S24_foyer_141.png`, `r3_S24_beam_157.png` | The KF27 room is confirmed (checkered marble, vitrine, armchair + ottoman, floor plate, beam, cyan node), but R2's 582–584 is **motion, not a 3 s hold** (no run of two identical samples). R2 measures one band; R3 sees two parallel lines but not two wall-to-wall beams in one frame. R3 has no single frame with vitrine + far doors + cyan above-door node. Partial, not 1:1. |
| `yaw180` | KF27 +0.5 s | **absent** | — | `r3_S24_foyer_147.png` (nearest) | No controlled 180° reverse pair at the same spot, 3 s apart. R2's 585 → 587 turn is toward the ward/vines, not a reverse view of the vitrine/armchair archway; R3's foyer turns are not a matched pair. |
| `lounge` | none (port-only pose) | **partial** | p1 549, 574–577; p3 5, 244–256 | `r2_lounge_577.png`, `r3_pose_lounge_5.png`, `r3_pose_lounge_246.png` | R2's Lounge is a billiard room with green baize, chandelier, tufted armchairs and tea table; the bouncer is present earlier at 544–563 but not in the 577 frame. R3's two long doorway holds look into a tiled hall with a balustrade, console table, statue and pendant, with **no NPC/bouncer**, and neither proves the port's east-doorway → west framing. Partial in two different rooms/angles. |
| `lounge_beam` | none | **absent** | — | `r3_pose_lounge_246.png` (nearest) | No white security beam or emitter in either Lounge hold; only a purple spotlight cone from the ceiling. |
| `beam_close` | KF27 beam | **partial** | p3 153–157 | `r3_S24_beam_155.png`, `r3_S24_beam_157.png` | Round wall emitter with a bright bulb and a thin white beam leaving to the left, seen obliquely at ~2–3 m; two parallel light lines at 153/155. It is **not** the port's gold disc with a cyan cross, and the KF27 one-band 40.0–40.5 % plus above-door cyan node is not reproduced in the same framing. R2 only sees the emitter from ~8 m across the hall. |

**Pose counts:** **0 present, 3 partial (`upper_foyer`, `lounge`, `beam_close`), 4 absent
(`gate`, `kf18_overlook`, `yaw180`, `lounge_beam`). No 1:1 match.**

---

## 5. KF27 correction: the emitter is at 40 %, not 56 %

The plan §4 left one measured question open: `KEYFRAME_INDEX.md` and
`build/qa/p0b_roi_stats.py` put the KF27 left-wall emitter at **y ≈ 40 %**, while the scorecard's
V6-03 reference text says **y ≈ 56 %**. The official keyframe settles it.

**Measurement.** File `docs/reference/clip_1795033698901/clean/KF27_03m27s_foyer_security_beam.jpg`,
1920×1080. The brightest pixel of the left-wall emitter disc is at **(341, 432)**:
pixel value `srgb(247,240,212)`; neighbouring (340,432) = `srgb(244,237,209)`, (342,432) =
`srgb(238,231,203)`. Converting:

```
x = 341 / 1920 = 17.76 %   y = 432 / 1080 = 40.00 %
```

This **supports 40.0 %, not 56 %**. The V6-03 text is the outlier; the keyframe index and the scorer's
40.0 % criterion agree with the image. That official cell also says "two ... beams" and "cyan ceiling
diamond"; the measured KF27 is **one** band and the above-door node, so the whole cell needed the
correction — not only `y %`. **Phase 0a (2026-11-27)** recorded it as a dated erratum in the
scorecard's **official** V6-03 cell (17.8 %/40.0 %, one band at 40.0–40.5 %, above-door node); the
port-side cell and the 120 tally remain Phase 3. No row token changed.

**No live percentage is claimed.** The live part-3 beam frames are **not KF27-framed**: the camera is
at a different distance/heading, and part 3 has no controlled 3 s hold at the KF27 pose. A percentage
measured there would not transfer to KF27. The R2 part-1 foyer frame is the only live frame with a
measured emitter, and it is a different framing again:

| R2 frame (part 1) | Brightest beam row | Beam count | Emitter core (threshold 55 %, trimmed bbox centre) |
|---|---|---|---|
| p1 582 | 49.9 % | 1 | (14.7 %, 50.1 %) — 32×16 px bbox |
| p1 583 | 47.4 % | 1 | off-frame left |
| p1 584 | 51.7 % | 1 | off-frame left |

So under the Staff mission the live foyer beam is a **single band at 47.4–51.7 %** with a left-wall
emitter at **x ≈ 15 %, y ≈ 50 %** at the one frame where it is measurable. The row moves 47.4 → 51.7 %
within three seconds because the camera pitches and steps; camera pitch is not recorded, so the y %
is not comparable to the official keyframe or to the port pose. **Do not average these into a live
KF27 claim.**

**The cyan node is the same above-door fixture, not a ceiling diamond.** R2 sees a cyan diamond
node above the far double doors at ≈(53.3 %, 27.8 %); the official KF27's node measures
≈(53.5 %, 23.3 %) at the same above-door position. R3's 40-frame ceiling strip sweep (136–175)
found no separate ceiling diamond, and the official KF27 has none separate either. This is a
shipped-build observation under this room state; re-check under the Cleanout room state before any
port conclusion.

**One beam band, not two.** R2 measures a single band in the foyer; R3 sees two parallel light
lines leaving the emitter but never two wall-to-wall beams in one frame. The official KF27 has
**one beam band at 40.0–40.5 %**, so the live single band matches the count; the live row is
47.4–51.7 % and the camera pitch is unknown, so the position is not a KF27 claim. This is not a
row delta and must be re-measured on the corrected capture.

---

## 6. 120-row coverage (coverage only, never a score)

### 6.1 Boundary

- The scorecard is **not edited**. The 120-row tally is unchanged:
  **48 scored / 56 N/A / 16 UNVERIFIED (48 + 56 + 16 = 120)**. This live capture is **not** a
  120-row re-score.
- No `PASS` / `DELTA` / `MISSING` token is assigned. A row below is only **supportable** (the subject is
  visible enough for a later human look/HUD comparison) or **not supportable** (the defining subject
  is absent, wrong-mission, wrong-route, timing-only, or audio-only).
- "Supportable" does not mean the port matches. It means the live frame can carry a look/geometry or
  HUD/UI observation into a later adjudication. The official keyframes still win any disagreement;
  the live frame is a second ground truth for the shipped build, not a row verdict.
- Audio rows are out of scope: the capture is clipped at 0.0 dBFS and no lane did audio analysis.
  `cue-heard` notes would not change a token even if they existed.
- Motion-only rows (`V7-02`, `G2-01`) are out of scope for a 1 fps still unless a lane listed a
  visible subject; neither did.

### 6.2 The union in one line

**64 distinct rows** have a lane-listed subject. **55 are supportable** (32 look/geometry + 23
HUD/UI) and **9 are not** (mission/route/timing/action; all 31 audio rows are separately out of
scope in the 56). The other **56 rows** have no lane-listed subject: 31 audio, 7 visual, 4 HUD/UI,
14 gameplay. Overall: **55 of 120 rows supportable; 65 not supportable**.

### 6.3 Look/geometry subject supportable — 32 rows

These are visual rows plus the visible gameplay/look rows. Carrier is the beat and one evidence frame;
the caveat is what the frame does **not** settle.

| Row | Carrier (beat / frame) | Caveat |
|---|---|---|
| V1-01 | S01 / `r3_S01_startscreen_391.png` | Late startscreen; live rain/neon; flicker not assessed from a still. |
| V1-02 | S03 / `r1_start_den_000.png`, `r3_S03_den_378.png` | Moon shaft + candle pools present; R1's poster frame does not separate the shaft, R3's Den frame does. |
| V1-03 | S08 / `r1_s08_maptable_194.png` | Banker's-lamp pool on `KILCAIRN`; the selected mission is the Staff contract. |
| V1-06 | S22 / `r3_fireplace_209.png` (different room) | Hearth amber pool in a sitting room, not the KF25 Fireplace Parlor. |
| V2-01 | S01 / `r3_S01_startscreen_391.png`; S13 / `r2_S13_street_340.png` | Startscreen rain and wet street; no gameplay street in part 3. |
| V2-02 | S05 / `r1_s05_telescope_057.png` | Moon + cheese wedge + chunks + `[F] EXIT`; 4 chunks vs 3. |
| V2-03 | S02/S10 / `r1_s10_mapload_196.png`, `r3_S02_loading_371.png` | KF12 art; flow position is a map/return load, not the menu → Den load. |
| V3-01 | S13 / `r2_S13_street_340.png`; S01 / `r3_S01_startscreen_391.png` | Wet-cobble specular; startscreen only at the late menu. |
| V3-02 | S07 / `r1_start_den_000.png` | Iridescent table diamond; the green floor diamond is not in frame. |
| V3-03 | S21 / `r2_S21_doors_506.png`; `r3_S21_door_300.png` | Blue-grey diamond-mullion doors in R2; R3's is a key-locked door, not the double doors. |
| V3-04 | S01 / `r3_S01_startscreen_391.png` | Purple shopfront orb; late menu. |
| V4-01 | S01 / `r3_S01_startscreen_391.png` | Guard, crates, scrollwork; car fender not identifiable. |
| V4-02 | S03/S07 / `r1_start_den_000.png`, `r1_s07_gramophone_180.png`, `r3_S03_den_378.png` | Den dressing; the gramophone corner is dark and its prompt is not legible. |
| V4-03 | S05 / `r1_s05_posters_189.png`, `r3_S03_den_378.png` | Five-poster wall; text not legible at 480p. |
| V4-04 | S13 / `r2_S13_banner_316.png` | Clipped `…'S DEMOLITI[ON]` banner + oil drums/cart; full lettering/EST. 1865/tagline absent. |
| V4-06 | S20 / `r1_s13_guildhall_side_247.png` | Distant sign only; R2's red *MELVIN*-like sign is not `MACLEOD`; KF23 framing absent. |
| V4-07 | S24 / `r2_upper_foyer_583.png`, `r2_S25_ward_590.png`, `r3_S24_foyer_141.png` | Vitrine, armchair + ottoman, floor plate, plaques; one beam; cyan above-door node present. |
| V5-01 | S01 / `r3_S01_startscreen_391.png` | Idle guard at the shopfront; late menu. |
| V5-02 | S04 / `r1_s04_wardrobe_kf03_086.png`, `r1_s04_wardrobe_kf04_122.png` | 3D Spider/cap/KF03/KF04 states; R1's Head card shows cap, not the bowler. |
| V5-03 | S14/S24 / `r2_S14_zipwire_411.png`, `r3_S24_foyer_141.png` | 1P hands + ZipWire launcher; equip swing not sampled. |
| V5-04 | S22 / `r2_S18_canister_546.png`, `r3_S23_takedown_47.png` | Constable in blue with belt/baton/red eyes; alerted/hostile, not idle with clasped hands. |
| V5-05 | S23 / `r2_S23_guard_down_560.png`, `r3_S23_takedown_47.png` | Grapple over a constable; no KF26 prompt arc/helmet framing in R2, R3 has the prompt. |
| V6-02 | S18 / `r2_S18_smoke_552.png`, `r3_S18_smoke_41.png` | Dense grey-white plume; indoor throw, not the courtyard stairs; no ignition flash. |
| V6-03 | S24 / `r2_S24_beam_582.png`, `r3_S24_beam_155.png` | R2 measures one band; KF27 has one band at 40.0–40.5 %; the live single band matches the count; emitter at 14.7 %/50.1 % under the Staff mission; cyan above-door node present (53.3 %/27.8 %; KF27 53.5 %/23.3 %). |
| V6-04 | S25 / `r2_S25_vines_587.png`, `r2_S25_ward_590.png`, `r3_S25_ward_179.png` | Ward + vines; R2 reverses the KF28 ward/vine doorway assignment, R3 matches KF28; both subjects present; trigger between samples. |
| V7-01 | S01 / `r3_S01_startscreen_391.png` | Startscreen camera framing; closer than KF01, two foreground occluders. |
| V7-04 | S23 / `r3_S23_takedown_47.png`, `r3_S23_takedown_49.png` | 1P lunge; pull-back not sampled. |
| V7-05 | S27 / `r1_s27_pause_254.png`, `r3_S27_pause_369.png` | Pause modal + blurred backdrop; R1 is a settings detour, R3 the route end. |
| G1-01 | S05 / `r1_s05_telescope_057.png` | `[F] PONDER` → sky cut → `[F] EXIT`; the cut timing is not re-measured. |
| G2-03 | S15/S16 / `r2_S16_roofline_397.png`, `r2_S15_crank_495.png` | Roofline + crank gauge; no anchored multi-strand cable, winch/gear housing or roof-ridge arrival beat. |
| G3-01 | S14 / `r2_S14_zipwire_411.png` | ZipWire equipped + launch; no gate arch, foliage landing or non-damaging-landing proof. |
| G4-04 | S23 / `r3_S23_takedown_47.png`, `r3_S23_down_111.png` | Takedown prompt/lunge + downed constable; the KO frame itself is between samples. |

### 6.4 HUD/UI subject supportable — 23 rows

All are shipping HUD/UI frames. The **mission caveat** applies where the live copy is the Staff
contract: UI3-02, UI4-03, UI4-04, G1-03 and the pause-footer seed in UI1-02. The widget is
supportable; the Cleanout copy is not.

| Row | Carrier (beat / frame) | Caveat |
|---|---|---|
| UI1-01 | S01 / `r3_S01_startscreen_391.png`, `r3_S01_startscreen_540.png` | Menu stack present at the late startscreen; cursor visible. |
| UI1-02 | S27 / `r1_s27_pause_254.png`, `r3_S27_pause_369.png` | Four items + footer; seed `701694559`, not `1025051536`; no quit selection. |
| UI2-01 | S03/S05/S08 / `r1_s06_ledger_prompt_005.png`, `r1_s05_telescope_057.png`, `r1_s08_maptable_194.png` | `[F] READ LEDGER`, `[F] PONDER`, `[F] ENTER MATCH` chain; order differs from the official route. |
| UI2-02 | S04 / `r1_s04_wardrobe_kf03_086.png`, `r1_s04_wardrobe_kf04_122.png` | Slots, drawer, tooltips, 3D Spider; KF03/KF04 states present. |
| UI2-03 | S14/S24 / `r2_S14_zipwire_411.png`, `r3_S24_foyer_141.png` | `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`, `[1]` highlighted. |
| UI2-04 | S15 / `r2_S15_crank_495.png` | Circular crank gauge; needle gauge, not the KF17 segmented progress ring. |
| UI2-06 | S23 / `r3_S23_takedown_47.png` | `[F] [HOLD] TAKEDOWN` only; no `[F] PICK POCKET` label. |
| UI3-01 | S01/S03/S24 / `r1_start_den_000.png`, `r3_S03_den_378.png`, `r3_S24_foyer_141.png` | `Johnny Cipher` level 4 + compass; matches the Den save. |
| UI3-02 | S12/S24 / `r1_s12_spawn_241.png`, `r2_S13_alley_311.png`, `r3_pose_lounge_246.png` | **Mission caveat:** tracker is `Steal the components of the Staff of Edinburgh [0/3]`, not `Steal 4,000 in loot value [0/4,000]`; health is not hidden in the damaged part-3 frames. |
| UI3-03 | S22 / `r2_S18_canister_546.png`, `r3_UI3_bar_41.png` | Ornate health bar, red/drained; reveal trigger is combat/damage, not the KF19 fall. |
| UI3-04 | S22/S24 / `r2_upper_foyer_583.png`, `r3_S22_key_53.png`, `r3_S22_key_54.png` | `Guildhall Key` HUD row + pickup icon; pickpocket action not visible. |
| UI3-05 | S24/S25 / `r1_ui5_noise_arcs_284.png`, `r2_S24_beam_582.png`, `r3_S25_ward_179.png` | Light Gem lit/dark states; no state-by-state sector comparison. |
| UI3-06 | S08 / `r1_s08_maptable_194.png` | Keybind legend; wording/order differs from KF10's `JOIN GAME [F]` set. |
| UI4-01 | S06 / `r1_s06_journal_010.png` | `JOURNAL`, Level 4, 94/500, Contract #2/#3 — matches KF07. |
| UI4-02 | S06 / `r1_s06_blackmarket_026.png` | `BLACK MARKET`, `£26,275`, four columns; preview selection differs from KF08. |
| UI4-03 | S09 / `r1_s09_prep_210.png`, `r1_s09_countdown_213.png` | **Mission caveat:** cards read `Item Collection Heist` / `120 minutes`, not `Cleanout Heist` / `55 minutes`; READY/countdown mechanics present. |
| UI4-04 | S11 / `r1_s11_letter_235.png` | **Mission caveat:** parchment + `[SPACE] CONTINUE` + scrollbar; body is the Staff/120 letter, backdrop is a blurred street, not the KF13 safe room. |
| UI4-05 | S02/S10 / `r1_s10_loading2_225.png`, `r3_S02_loading_371.png` | Spinner + `LOADING...` + gold emblem; the spinner is visible in both R1 and R3. |
| UI5-01 | S24 / `r1_ui5_noise_arcs_284.png`, `r2_S24_beam_582.png`, `r3_S24_foyer_141.png` | Red player-noise arcs around the gem; wide crimson arcs. |
| UI5-03 | S22 / `r2_S18_canister_546.png` | Red eyes + vertical red alert bar; the bar is red, not KF16's yellow. |
| UI5-05 | S09 / `r1_s09_countdown_213.png` | `MISSION STARTING IN 6...`, `Mode: Solo`, `Difficulty: Novice`; mission caveat. |
| UI5-06 | S25 / `r2_S25_vines_587.png`, `r3_S25_ward_179.png` | Jaw-trap icon in a partial ring above the gem; the `xx` unconscious-head icon is not seen. |
| G1-03 | S08 / `r1_s08_maptable_194.png`, `r1_s08_confirm_195.png` | **Mission caveat:** map table + confirmation modal; the selected mission is Item Collection, not Cleanout. |

### 6.5 Not supportable — 9 lane-listed rows

| Row | Why not supportable |
|---|---|
| V1-04 | No lantern ignite/toggle anywhere; only a streetlamp/warm wall-lamp pool. The row's lantern bounce is absent (route). |
| V7-03 | The letter's DOF blur is present, but the backdrop is a blurred outdoor street, not the official blurred brick safe room (mission/route). |
| UI5-02 | The crimson three-dash pip at p1 582 is visible, but its identity (guard-direction vs noise/health) is not established; a still cannot settle it (timing/subject). |
| G1-02 | The decoration station prompt is visible, but the owl → spider-chest swap and the trunk treasure cycle are not seen (timing/action). |
| G1-06 | The `Guildhall Key` HUD row is visible, but the `[F] PICK POCKET` action itself is not in any sampled frame (timing/action). |
| G3-02 | The canister and plume are visible, but the throw, ignition flash and stair-covering plume are not sampled (timing/action). |
| G5-01 | The select → ready → countdown → load flow occurs, but for `Item Collection Heist` / 120 minutes, not `Cleanout Heist` / 55 minutes (mission). |
| G5-03 | The locked-down state is visible, but the beam tripwire itself is between 1 fps samples (585 → 586); the row is the tripwire → lockdown (timing). |
| G5-05 | The pause modal is visible, but there is no `QUIT TO DESKTOP` selection, teardown or silence tail; the row is pause → quit (timing). |

### 6.6 Rows with no lane-listed subject — 56

These rows were never carried by a lane's positive coverage table. They are **not supportable** from
this capture. The list is the negative space, not a verdict on the port.

- **Visual (7):** V1-05, V1-07, V2-04, V2-05, V4-05, V6-01, V7-02.
- **HUD/UI (4):** UI2-05, UI2-07, UI5-04, UI5-07.
- **Gameplay (14):** G1-04, G1-05, G2-01, G2-02, G2-04, G2-05, G3-03, G3-04, G4-01, G4-02, G4-03,
  G4-05, G5-02, G5-04.
- **Audio (31):** AU1-01–AU1-06, AU2-01, AU3-01–AU3-05, AU4-01–AU4-05, AU5-01–AU5-08, AU6-01–AU6-06
  (all; out of scope under the 0.0 dBFS caveat and the no-audio lane boundary).

**Accounting:** 32 look/geometry + 23 HUD/UI + 9 not supportable + 56 never listed = 120. The
existing score tally (48 / 56 / 16) is unchanged and is not derived from this table.

---

## 7. What the capture can and cannot support

### 7.1 Can support

- **Den UI and front end, strongly.** S04 wardrobe (KF03/KF04 states), S05 telescope/posters, S06
  Journal/Black Market, S08 map table/confirm. The Den save state (Level 4, 94/500, Contracts #1–#2
  completed, #3 active) matches KF07 exactly; the Black Market total matches KF08. These are the
  cleanest live frames in the capture.
- **Startscreen, late but usable.** S01 at p3 390–541: menu stack, neon, rain, idle guard, crates,
  cursor. Use it for menu/backdrop look, not for the boot sequence or the route start.
- **Guildhall look/geometry.** S24 foyer (vitrine, armchair + ottoman, floor plate, beam, emitter,
  plaques), S25 ward/vines, and partial S13 street/alley, S20 balcony, S21 blue doors, S22 constable/
  key, S23 takedown. The capture is 1440p; the cited proxy frames are 480p and the `_full_` frames are
  1440p, so a later look adjudication should re-extract from the original at the chosen timestamps.
- **HUD frame.** Player card + compass, hotbar, Light Gem, red noise arcs, health bar, key row,
  loading art, pause modal/footer. The HUD is the shipped HUD; the mission strings are the Staff
  contract.
- **One measured official fact.** The KF27 emitter is at 17.8 % / 40.0 % on the official keyframe,
  supporting 40 %, not the V6-03 text's 56 %. This is a measured correction, not a row score.

### 7.2 Cannot support

- **The official mission flow.** No Cleanout Heist, no 55-minute prep card, no `Steal 4,000 in loot
  value`, no brick safe-room spawn, no KF13 briefing letter, no Cleanout objective flow.
- **The safe room as a set.** Only the exterior catwalk half of S12 appears; the brick interior,
  green/violet portal, lantern and `SPIDER` flyer do not.
- **The official exterior sequence.** No `CONSTABLE'S GUILDHALL` arch with the red-eyed guard and car
  headlights, no gear plate/griffins, no Vistara scan, no crimson alarm/slate stair ascent, no
  `QUIT TO DESKTOP` teardown.
- **Timing and cadence.** Part 1 has `dup=1961 drop=1955` over 36,000 frames (~3 %); part 3 is 32,503
  packets over the nominal 600 s (54.2 fps) and only 541.7 s of content; both proxies are 1 fps.
  Content identification is valid; motion/timing claims are not.
- **Audio levels.** Max 0.0 dBFS; clipping cannot be excluded. No loudness, duck, headroom or digital-
  silence claim.
- **The seven poses.** No 1:1 match; 3 partial, 4 absent; no 3 s holds. The port's six-pose capture
  remains the pose reference.
- **A live 120-row reference.** The capture can support 55 row subjects, but it cannot add or change a
  120-row token. The official clip/keyframes remain the official reference.

---

## 8. Corrected-capture checklist

The next capture must be the official route, not another manual session. Minimum contract:

| # | Check | Why |
|---|---|---|
| 1 | **Mission: `CONSTABLES' GUILDHALL — Cleanout Heist`, `Novice`, `Solo`.** | The recorded run is `Item Collection Heist` / 120 minutes; that is the root cause of the mission mismatch. |
| 2 | **Pre-start check: the map-table token is `CONSTABLES' GUILDHALL`, the prep card reads `Cleanout Heist` and `Time Limit: 55 minutes`, and the HUD will read `Steal 4,000 in loot value`.** | Do not start a 15-minute recording on the Staff side mission. If the prep card says `Item Collection Heist` / 120, back out and reselect. |
| 3 | **Spawn in the brick safe room** (KF14: industrial arched window, brick wall, green/violet Escape Portal, `[F] TURN ON` lantern, `SPIDER` flyer, metal-grate catwalk). | The recorded spawn is the outdoor canal street; the safe-room look is the official S12 subject. |
| 4 | **HUD `Steal 4,000 in loot value [0/4,000]`**, health hidden at 100 % HP, hotbar `[1]`/`[2]`/`[4]` + `[TAB] MAP [MMB] [HOLD] PING MENU`. | Confirms the Cleanout contract in-band, not just on the prep card. |
| 5 | **Start the recorder at the main menu** so S01 is captured from the boot, with the `PLAY/SETTINGS/CREDITS/QUIT` stack and cursor. | The current S01 is only the late end-of-session menu; the route start is missing. |
| 6 | **900 s single file**, not a 600 s cap. | The official route is 225.6 s plus six 3 s holds and pauses; 900 s covers retries without a part-2 gap. |
| 7 | **Window title `TAT`**, 2560×1440, `gbrp`, 60/1, FLAC 48 kHz. | Provenance and matched format; verify with `ffprobe`, not by eye. |
| 8 | **Lower Master; 10 s test max < −1 dBFS.** | The current part 1 peaks at 0.0 dBFS, so clipping cannot be excluded. Record the test file and its `volumedetect` line. |
| 9 | **High groups at 100 % scale; preset label `Custom`; FOV 85; V-Sync off; FPS limit 60; Motion Blur ON** for the matched-settings pass. | Keeps the capture comparable to the P0b/port reference settings (the official clip remains 4K/29.833). If crisp look frames are needed, add a separate short pass with Motion Blur OFF and label it. |
| 10 | **Play the 27 beats in the official order** (Steps 11), no mission/settings changes mid-run; if a retry happens, log it and keep recording. | The current run is a manual roam with deaths at p1 376/592 and no official completion. |
| 11 | **Hold the six poses for 3 s each + the KF18 still**, and write `poses.tsv` (`name<TAB>seconds<TAB>note`). | The current capture has no pose holds; near-static menu/landing runs are not the contract. |
| 12 | **Provenance:** `manifest.json`, SHA-256, build id/exe hash, Proton version, footer crop; run the single-file `p0b_live_capture.sh verify` (or a new multi-part verifier). | No `P0B_LIVE_VERIFY PASS` exists for the current files. |

Also: stop before `QUIT TO DESKTOP`; record the pause modal, do not select quit. The official S27
teardown/digital-silence tail is an audio-only claim the current capture cannot make, and the
corrected capture should not fake it by quitting.

---

## 9. Limitations and verdict

**The capture is not the official route.** It is a manual, two-part, wrong-mission session on the
right map with the right Den save. It shows the shipped build's Den and Guildhall look at 1440p60
High/100 %, which is genuinely useful, but it does not show the Cleanout Heist, the 55-minute window,
the brick safe room, the `Steal 4,000` objective, the official gate/gear-plate sequence, the Vistara
scan, the crimson alarm or the quit flow. The two `wrong mission` beats (S09 prep, S11 letter) and
the 12 `partial` beats are the direct evidence of that.

**There is no live 120-row reference.** The official `clip_1,795,033,698,901.mp4` and its 30 keyframes
remain the official reference. This capture supports 55 row subjects for a later look/HUD
adjudication, but it cannot add a token, cannot replace the official clip and cannot overrule a scored
row. The 120-row tally stays **48 scored / 56 N/A / 16 UNVERIFIED**.

**The Den and Guildhall look evidence is usable.** The Den UI cluster (S04–S06, S08) is the strongest
part of the capture; the late startscreen (S01) is usable for the menu/backdrop; the foyer/ward
(S24/S25) and the partial street/portico/balcony/takedown frames are usable for geometry and
materials. The foyer's single measured band (R2) and the cyan wall sconce are shipped-build
observations that need re-checking under the Cleanout room state.

**The defects are route selection and recorder fragmentation, not a build regression.** The wrong
mission is the primary defect: it removed the safe room, the Cleanout objectives, the briefing copy and
the official pacing in one choice. The recorder added a missing part 2, a **226.5 s** unrecorded gap,
a 541.7 s part 3 (not 600 s), ~2,000 duplicated/dropped slots in part 1 and ~1,000 in part 3, and no
manifest. None of that is
evidence that the shipped build lacks a beat.

**Measured correction on the record.** The official KF27 emitter dot is at **(341, 432) of 1920×1080 =
17.8 % / 40.0 %**, supporting **40 %**, not the **56 %** in the V6-03 text. The live part-3 beam frames
are not KF27-framed, so no live percentage is claimed; R2's foyer beam is a single band at
47.4–51.7 % with the emitter at (14.7 %, 50.1 %) at p1 582. The scorecard is not edited; this finding
belongs to the adjudication wave.

**Next step.** Re-capture per §8, starting at the main menu on the Cleanout contract, then run a
separate adjudication wave over the 55 supportable rows. Until then, the official clip remains the
only official 120-row reference, and this report remains a coverage and provenance record, not a
score.
