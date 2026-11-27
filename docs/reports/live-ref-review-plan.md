# Live-reference review plan — shipped-game capture, 2026-11-27

**Status: plan only. The route is not reviewed.** Nothing in this file asserts that a beat,
keyframe or pose was seen. §3 and §4 are empty templates; the presence values are filled by
R1–R3 and adjudicated by the verifier (§7).

**Claim boundary.** This wave inventories a capture of the **shipped** game (Steam appid 3341000,
buildid `25076818`, StateFlags `4`) taken on this host on 2026-11-27, and asks three reviewers
whether the 27-beat route and the seven poses appear in it. It does **not** re-score the port, does
**not** edit `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`, and does **not**
replace the official clip. The official `clip_1,795,033,698,901.mp4` and its 30 keyframes stay the
official reference; this capture is a matched-settings P4/ROI reference and a *second ground truth*
for what the shipped build actually renders.

**What was done to write this plan.** Metadata only: `ffprobe` (duration/size/format/frame counts),
`sha256sum`, the two existing settings stills, and the recorder logs. No frame was extracted, no
proxy was decoded, no Godot/Steam/GPU process was started, and no file outside this one was written.
The originals were never decoded.

---

## 1. Capture inventory

### 1.1 The two parts

| | Part 1 | Part 3 |
|---|---|---|
| Path | `~/Videos/tat2_ref_20261127/route_lossless.mkv` | `~/Videos/tat2_ref_20261127/route_lossless_part3.mkv` |
| Size (bytes) | `27,158,471,556` (25.29 GiB) | `27,772,583,936` (25.87 GiB) |
| Container | Matroska (`matroska,webm`) | same |
| Duration | `600.000 s` | `600.000 s` |
| Video | `h264`, 2560×1440, `gbrp`, 60/1, **36,000 packets** | `h264`, 2560×1440, `gbrp`, 60/1, **32,503 packets** |
| Audio | `flac`, 48 kHz, 2 ch, `s16` | same |
| Bitrate | 362.1 Mb/s | 370.3 Mb/s |
| SHA-256 | `7f26edb0b420e40ab56fe98ba5f8c7cddd1dedd4ce6c79ab868797fcf9d91089` | `41a86f18e3562ec9a8b268f90f0e742590777097a9603f516b821cf541e339d6` |
| Wall clock (from x11grab start PTS) | `1795761485.68` ≈ 01:38:06 local, ends ≈ 01:48:06 | `1795762312.21` ≈ 01:51:52 local, ends ≈ 02:01:52 |

`gbrp` + `libx264rgb -qp 0` is the lossless RGB path the P0b runbook specifies, so pixel values are
trustworthy. **Neither part is a clean 60/1 capture, and part 3 is materially worse.** Part 1's log
records `frame=36000 fps=60 dup=1961 drop=1955 time=00:10:00.00` — a full 36,000-frame timeline with
~2,000 slots duplicated or dropped (~3 %); part 3's records `frame=32503 fps=54 dup=996 drop=992
time=00:10:00.00`, and the container holds 32,503 video packets over 600.000 s (54.2 fps average —
~3,500 frame slots short of 36,000). Timestamps stay wall-clock anchored in both, so a `-ss` seek
lands on the right moment, but the motion cadence does not: part 1 supports coarse timing (±3 % of
frame slots), part 3 supports none. Both are valid for *content identification*.

### 1.2 The missing part 2 and the measured gap

Part 2 was killed at start by a cleanup command, so the recorder restarted as part 3. The gap is
measurable from the two x11grab start epochs:

```
part1_start = 1795761485.677568   part1_end = start + 600.000 = 1795762085.678
part3_start = 1795762312.214556
gap         = 1795762312.215 - 1795762085.678 = 226.537 s  (3:46.5)
```

So wall-clock `t ≈ 600.0 s → 826.5 s` of the session is **unrecorded** (part 2's short life plus the
restart). That is not a "short" gap: it is long enough to contain the whole S21→S25 sequence
(official 174.5 → 217.4 s) or all seven pose holds, and it falls at a boundary this plan uses as a
lane split. The gap is **content-ordered, not clock-ordered**: nobody knows which beat the run had
reached at `t = 600`. A beat that is not found is marked `unseen-gap?` — never `absent` — when its
route position falls between the last beat identified at the end of part 1 and the first beat
identified at the start of part 3 (§3, §7).

### 1.3 Settings (measured from the two stills, not from the ini)

Both stills are 3840×2160 full-desktop screenshots (`settings_video.png`
`fe7b4d92…abca20`, `settings_audio.png` `282fda26…faf863`) showing the game window titled **`TAT`**
inside the desktop. The desktop view corroborates Windowed mode and a 16:9 client smaller than the
desktop; the authoritative resolution is the `2560 × 1440` field below.

| Screen | Value read from the still |
|---|---|
| Display Monitor | `Default_Monitor` |
| Window Mode | `Windowed` |
| Resolution | `2560 × 1440` |
| V-Sync | **unchecked (off)** |
| FPS Limit | `60` |
| Motion Blur | **checked (ON)** |
| Field of View | `85` (horizontal → ≈54.5° vertical at 16:9; matches the authored lens, AGENTS rule 6) |
| Quality Preset | `Custom` |
| Resolution Scale | `100` |
| View Distance / Shadows / Textures | `High` / `High` / `High` |
| Master / Music / SFX / Dialogue | `100` / `100` / `100` / `100` |

The `Custom` label is **expected, not a deviation**: the High preset sets `ResolutionQuality=71`,
and re-setting the scale to 100 afterwards leaves the preset label at `Custom` while every quality
group stays High (P0b runbook Step 8). Reviewers must quote it as *"High groups at 100 % scale,
preset label Custom"* and never as "High preset".

**Motion Blur is ON.** This is the single most consequential setting for this wave: individual
60 fps frames of moving gameplay will be blurred. Detail and edge judgements must be taken from
holds (menus, poses, stationary beats), and every evidence note must say whether the frame is a
hold or motion.

### 1.4 Audio caveat

The capture taps the Pulse sink monitor (`-f pulse -i "$SINK.monitor"`), i.e. the game's *actual
mixed output* — unlike the 2026-11-24 OBS-borne bed that voided that scorecard's audio column. But
Master/Music/SFX/Dialogue are all at 100 and the owner's `volumedetect` on the full part 1 reports
**max 0.0 dBFS**, while the 10 s test reports mean −18.1 dBFS / max −5.6 dBFS. A full-scale peak
means clipping cannot be excluded on loud cues.

Therefore:

- **No level, loudness, headroom, duck-depth or "digital silence" claim may come from this
  capture.** The official `−240.0 dBFS` silence and the −19 dB pause duck stay unmeasured.
- **Cue identity and ordering may be logged** (was the gramophone jazz audible, did the car
  honk fire, did the six ticks sound) as `cue-heard` / `cue-not-heard` notes with a timestamp.
  These notes are supplementary evidence and **never** change a 120-row token (§6).
- The official clip's own levels remain the reference; this capture cannot raise or lower them.

### 1.5 Other artifacts in the capture directory

| File | What it is | Use |
|---|---|---|
| `test10.mkv` (`7cb10c34…61d63`) | 10 s, 2560×1440 `gbrp` 60, FLAC 48k, mean −18.1 dBFS / max −5.6 dBFS | pipeline smoke test only — not evidence |
| `test10.png` (2560×1440) | one still from the test | framing sanity check |
| `contact_20s.png` (2400×1620) | 20 s contact sheet already built | shows the sheet format works |
| `recorder.log`, `recorder_part3.log` | ffmpeg stderr for both parts | provenance: frame counts, dup/drop, start PTS |
| `review/route_lossless_1fps.mp4` | **complete**: 480×270, 1 fps, 600 packets, 11.1 MB | R1/R2 proxy |
| `review/route_lossless_part3_1fps.mp4` | still encoding when this plan was written | R3 proxy (blocker §9) |

### 1.6 Provenance gaps (state them, do not paper over them)

- **There is no `manifest.json` and no `poses.tsv` in the capture directory**, so
  `build/qa/p0b_live_capture.sh verify` was never run on these files.
- That helper is hard-wired to `$CAPDIR/route_lossless.mkv` and a single capture, so it cannot
  verify a two-part session as-is. This wave's provenance is therefore the recorded `sha256sum`
  + `ffprobe` lines in §1.1 plus the recorder logs — enough to identify the bytes, **not** a
  `P0B_LIVE_VERIFY PASS`.
- The install still reports buildid `25076818` with StateFlags `4`, and
  `TAT-Win64-Shipping.exe` is present, but no build hash was taken at record time. Do not claim a
  byte-verified build; the settings still and the pause footer are the in-band evidence.

---

## 2. Segment assignments

Three reviewers, one segment each. **The split is labour, not beat prediction.** At 1,200 s the
capture is 5.3× the 225.6 s official route, so the owner's pacing, retries and dwell time are
unknown and no lane may assume the official cumulative times apply. Each lane's first duty is a
content index of its whole window; presence is decided by **content**, in whatever order it appears.

| Lane | Segment | Proxy | Duration | Duty |
|---|---|---|---|---|
| **R1** | part 1, `0 – 300 s` | `review/route_lossless_1fps.mp4` | 300 s | front end + first Guildhall act |
| **R2** | part 1, `300 – 600 s` | `review/route_lossless_1fps.mp4` | 300 s | mid/late act; ends at the split |
| **R3** | part 3, `0 – 600 s` | `review/route_lossless_part3_1fps.mp4` | 600 s | post-gap resume + poses |

No lane may read another lane's frames; overlap between lanes is resolved by the synthesizer (§7).

### 2.1 R1 — part 1, 0–300 s

**Why this window.** The P0b runbook has the owner start the recorder at the Startscreen ("start the
recorder at the Startscreen; every beat from S01 is evidence"), so part 1 *should* begin with the
front end — but the capture predates this plan and nobody recorded whether that happened. R1 checks
the first 10 s before assuming anything.

| Priority | Beats | KF | What to look for first |
|---|---|---|---|
| 1 | S01 | KF01 | wide street, `Mac Neish / Jeweller` neon, right-aligned `PLAY/SETTINGS/CREDITS/QUIT`, cursor |
| 2 | S02 → S03 → S04 | KF02–KF04 | loading art → Den attic → `WARDROBE` overlay |
| 3 | S05, S06, S07 | KF05–KF09 | telescope sky cut, `JOURNAL`/`BLACK MARKET`, gramophone corner |
| 4 | S08, S09, S10, S11 | KF10–KF13 | 3D map table, Mission Prep countdown, second loading art, briefing letter |
| 5 | S12, S13, S14 | KF14–KF16 | safe room + portal + lantern, street banner/car, gate + first zipwire |
| tail | S15, S16 | KF17, — | roofline, if the run is fast |

**Pose checks in window:** `gate` (KF16 01:40.20) only, and only if the run reaches the gate before
300 s. Do not hunt for the foyer or Lounge poses here.

**Split/gap risk: low.** R1 cannot lose anything to the 600 s split; its risk is the opposite — a
late recorder start could clip S01's menu stack while still showing the street (S01 `partial`).

### 2.2 R2 — part 1, 300–600 s

**Why this window.** If the run is slower than the official clip (the normal case for manual play
with 3 s pose holds and navigation), the courtyard/portico/parlor act lands here. If the run is
fast, this window is the second pass, a reload, or free roam.

| Priority | Beats | KF | What to look for first |
|---|---|---|---|
| 1 | S17, S18, S19 | KF18–KF22 | cable crossing, gear plate, courtyard drop, smoke plume, diamond scan |
| 2 | S20, S21 | KF23, KF24 | `MACLEOD` sign, portico, blue double doors + prompts |
| 3 | S22, S23 | KF25, KF26 | parlor, pickpocket, takedown |
| 4 | S24, S25 | KF27, KF28 | marble foyer, beams, ward + vine lockdown |
| 5 | S15, S16 (re-visit) | KF17 | roofline, if R1 did not reach it |
| re-visit | any S01–S14 | — | a restart can replay the front end here; log it as a second occurrence |

**Pose checks in window:** `kf18_overlook` (KF18 02:14.80) most likely; `upper_foyer` / `yaw180` /
`beam_close` if the run is fast; `gate` again on a retry.

**Split/gap risk: high.** This lane ends exactly at the part-2 gap (`600.0 → 826.5 s` unrecorded).
If the run reached the parlor or foyer near the end of part 1, the lockdown, the alarm stair and all
seven pose holds can be inside the gap. Any beat missing here must be cross-checked against R3
before it is called `absent`.

### 2.3 R3 — part 3, 0–600 s

**Why this window.** Part 3 begins 3 m 46 s after part 1 ends, so it most likely resumes **inside**
the Guildhall, mid-act. It is the only lane that can see the post-gap content, and it is the lane
most likely to hold the pose sequence (the poses are six 3 s holds + navigation in the foyer/Lounge).

| Priority | Beats | KF | What to look for first |
|---|---|---|---|
| 1 | S24, S25, S26, S27 | KF27–KF30 | marble foyer + beams, ward/vine lockdown, crimson alarm stairs, pause modal |
| 2 | S22, S23 | KF25, KF26 | parlor, constable, pickpocket, takedown (if part 3 starts before the foyer) |
| 3 | S20, S21 | KF23, KF24 | `MACLEOD`, portico, blue doors |
| 4 | S17, S18, S19 | KF18–KF22 | courtyard act, if part 3 starts earlier than assumed |
| poses | all seven | see §4 | the holds are stills: crisper than gameplay in a motion-blurred capture |
| re-visit | S01 start | KF01 | a late restart can put the startscreen at the end of part 3 |

**Pose checks in window:** `upper_foyer`, `yaw180`, `lounge`, `lounge_beam`, `beam_close` — plus
`gate` / `kf18_overlook` only if the run replays the exterior.

**Split/gap risk: highest, and it cuts both ways.** (a) Part 3 may start *after* the foyer and show
only the alarm stair and pause menu, leaving S22–S25 in the gap. (b) Part 3's frame cadence is
54.2 fps average (§1.1), so a 1 s proxy sample can land on a duplicated frame — do not judge motion
or timing here. (c) The owner may have stopped before the pause menu, so S27 can be genuinely
absent.

### 2.4 What no lane may do

- Assume the official cumulative times. They are anchors for *finding* a beat, not a schedule.
- Call a beat `absent` from its own window alone. `absent` requires the beat to be missing from
  **all three** lane reports and to sit outside the gap shadow (its route position must not fall
  between the part-1 tail and the part-3 head, §1.2).
- Score a row. Lanes report presence and cite frames; only §6/§7 turn that into coverage.

---

## 3. Beat presence template (S01–S27)

One row per official beat. `Official time` is the segment start from `KEYFRAME_INDEX.md`;
`KF` is the official keyframe id(s); `Present?` is the only column a lane fills with a verdict.

Vocabulary — exactly these four values:

| Value | Meaning |
|---|---|
| `present` | the beat's defining subject is visible and the beat is unambiguous |
| `partial` | the subject is visible but a defining element is missing/different, or the beat's transition is unseen |
| `absent` | the segment is visibly *not* this beat at any point in the window (e.g. a different room, a different act) |
| `unseen-gap?` | not found, and its route position falls between the last part-1 beat and the first part-3 beat — **not** a verdict |

`Present?` empty = not yet reviewed. Do not pre-fill.

| ID | Official time | KF | Expected subject (defining elements) | Part / time seen | Present? | Evidence frame | Notes |
|---|---|---|---|---|---|---|---|
| S01 | 00:00.00 | KF01 | Startscreen: rainy `Mac Neish / Jeweller` street, right-aligned `THICK AS THIEVES` + `PLAY/SETTINGS/CREDITS/QUIT`, cursor | | | | |
| S02 | 00:02.15 | (KF12 art) | Loading 1: indigo skyline, two dirigibles, moon, `LOADING...`, gold emblem — **before** Mission Prep | | | | shared art with S10: disambiguate by flow position |
| S03 | 00:02.60 | KF02 | Den entry: teal moon shaft through leaded window, rafters, rolltop desk, armoire, telescope | | | | player card + compass fade-in |
| S04 | 00:06.57 | KF03, KF04 | `WARDROBE` overlay: `The Spider`/`The Chameleon LOCKED`, `Edit Loadout` 1–4, 3D turntable, `Head/Body/Calling Card`, tooltip | | | | KF04 = cap + slot-3 drawer + `Vistara Diamond` tooltip |
| S05 | 00:18.24 | KF05, KF06 | Telescope `[F] PONDER` → sky cut (moon + cheese wedge + `[F] EXIT`) → 5 `WANTED` posters | | | | the sky cut is the unambiguous marker |
| S06 | 00:26.58 | KF07, KF08 | Ledger: `[Q] JOURNAL` XP bar + contract cards; `BLACK MARKET [E]` with `YOUR TOTAL ASSETS` | | | | save-dependent numbers; record, do not score |
| S07 | 00:38.17 | KF09 | Gramophone corner: `[F] CHANGE DECORATION`, boot-trail decals, `[F] TURN ON` + jazz, trunk cycle | | | | only diegetic music in the route |
| S08 | 00:51.08 | KF10 | Map table: `KILCAIRN` parchment, tokens, `[H] Difficulty: Novice` / `[R] Mode: Solo` card, `ENTER MATCH`, confirm modal | | | | |
| S09 | 00:56.08 | KF11 | `MISSION PREPARATION`: location/mission/contract cards, 3D Spider, `[F] READY`, `MISSION STARTING IN 6...` | | | | |
| S10 | 01:04.80 | KF12 | Loading 2: same art as S02 — **after** Mission Prep, with the countdown finished | | | | disambiguate from S02 by flow position |
| S11 | 01:09.44 | KF13 | Briefing letter: parchment over blurred safe room, `55 minute window` / `20 minutes`, `[SPACE] CONTINUE` | | | | |
| S12 | 01:10.81 | KF14 | Safe room: brick wall, green/violet portal outline, `[F] TURN ON` lantern, `SPIDER` flyer, HUD `(£) 0` + `Steal 4,000…` | | | | exit to catwalk + vault |
| S13 | 01:20.10 | KF15 | Alley: `BARRON'S DEMOLITION` banner, oil drums, ladder, wet cobbles, sprint, car `[F] INTERACT` + honk/headlights, gate | | | | the port has no banner asset, so this is the only place the shipped lettering can be read |
| S14 | 01:39.30 | KF16 | Gate: `CONSTABLE'S GUILDHALL` arch, red-eyed guard + yellow alert bar, car headlights, ZipWire `[1]`, 1st launch, planter landing | | | | |
| S15 | 01:49.50 | KF17 | 2nd zipwire: `CRANK [LMB]` ring, multi-strand cable to roof parapet, 1P crank, clocktower in mist | | | | |
| S16 | 01:58.50 | — | Roofline: slate ridge, chimney/roof block, winch/gear housing, 3rd zipwire to the gate pillar | | | | **no official keyframe** — cite a frame anyway |
| S17 | 02:11.00 | KF18 | Cable crossing over crowned pillars + twin griffins, gear plate with red `⚡`, courtyard drop, fall damage + health bar | | | | |
| S18 | 02:23.30 | KF19, KF20 | Smoke bomb: `[2]` canister, throw onto grand stairs, ignition flash, grey-white plume, red noise arcs | | | | |
| S19 | 02:30.70 | KF21, KF22 | Vistara Diamond `[4]` in caliper mount, scan pulse, guard RED → GREEN, swap back to `[1]` | | | | |
| S20 | 02:33.00 | KF23 | Side wing: rain-wet balcony, iron balustrade, barred red-lit window, vertical `MACLEOD` sign, garden terrace | | | | |
| S21 | 02:54.50 | KF24 | Portico: blue diamond-mullion double doors, `[F] OPEN` above `[F] [HOLD] LOCK` → `[F] CLOSE`, scaffolding, walk through | | | | |
| S22 | 03:04.50 | KF25 | Fireplace parlor: hearth, chandelier, constable with clasped hands + blue hip baton, `[F] PICK POCKET` / `[F] [HOLD] TAKEDOWN`, `Guildhall Key` | | | | |
| S23 | 03:17.10 | KF26 | Takedown: `[F] [HOLD] TAKEDOWN` progress arc, 1P lunge over helmet/shoulder, guard down on parquet, pull-back | | | | |
| S24 | 03:22.00 | KF27 | Marble foyer: checkered floor, glass vitrine, armchair + ottoman, floor plate, cyan ceiling diamond, two white beams + wall emitter, security camera | | | | |
| S25 | 03:29.00 | KF28 | Beam crossed: purple crystalline ward seals the arch, green vines on `Basement Stairs`, jaw-trap icon, then unconscious-head icon | | | | the ward/vine pair is the marker |
| S26 | 03:37.40 | KF29 | Crimson alarm on the slate stairwell, `CRANK [LMB]` reticle, jaw-trap icon re-triggered, upper landing | | | | |
| S27 | 03:41.90 | KF30 | Pause modal: `RESUME / SETTINGS / RETURN TO THIEF'S DEN / QUIT TO DESKTOP`, footer `1.5.148559 …` | | | | recording may stop before this |

Rules for filling a row:

1. `Part / time seen` is `p1 123` or `p3 0456` — part and whole seconds in that part's timeline.
2. `Evidence frame` is the basename from §5 (`r1_S01_p1_0001.png`). A row with `present` or
   `partial` and **no** frame is void (§7).
3. S02/S10 are the only two beats that share art (KF12). If flow position cannot settle which one
   it is, mark `partial` and say so.
4. S16 has no official keyframe. Use the roofline/winch/3rd-launch content and cite a frame.
5. S27 may legitimately be absent if the owner stopped the recorder before quitting. Absence of the
   pause menu is not evidence against the build.

---

## 4. Pose checklist

Seven entries: six 3 s holds plus the KF18 still (the runbook's "six fixed poses (plus the KF18
still)"; the KF18 frame is extracted from a moving shot, not held). Each is a **still** in a
motion-blurred capture, so a hold is the best-quality evidence this session can produce — extract
these at full resolution first.

| Pose | Official cue | How to find it in the proxy | Full-res target |
|---|---|---|---|
| `gate` | KF16 01:40.20 | wrought-iron arch reading `CONSTABLE'S GUILDHALL`; red-eyed guard with a vertical yellow alert bar inside; vintage car headlights at the right; ZipWire `[1]` in hand; HUD `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]` | alley side of the arch, car on the right, guard visible |
| `kf18_overlook` | KF18 02:14.80 | mid-cable view: crowned star-topped gate pillars, **twin stone griffins** on the grand stairs, distant guard highlighted green, mostly-shadowed Light Gem with wide red arcs | one frame from the moving crossing; pick the frame with both griffins |
| `upper_foyer` | KF27 03:27.60 | threshold looking down the hall: checkered marble, tall glass vitrine, velvet armchair + ottoman, two horizontal white beams, cyan ceiling diamond above the far doors | forward view, beam band near mid-frame |
| `yaw180` | KF27 +0.5 s (03:28.10) | same spot turned 180°: armchair/ottoman close, marble-topped vitrine with a framed picture, bust on a plinth, archway down the hall | reverse view of the same foyer |
| `lounge` | none (not in the official clip) | Guildhall **ground-floor Lounge**: stand at the east doorway and look west into the room; tiled floor, room dressing, the `C_20` bouncer | east doorway → west |
| `lounge_beam` | none | from the Lounge doorway, frame the Lounge beam/emitter; two crisp white beams if both are in view | beam + emitter, not along the beam axis |
| `beam_close` | KF27 beam | 2–3 m from the **left-wall** emitter: gold disc with a cyan four-point cross at ≈`x 17.8 %, y 40 %` of frame, two horizontal white beams wall-to-wall, cyan ceiling diamond above the far doors | close oblique, emitter and beam band both in frame |

Finding method (all on the proxy, no original decode):

1. Scan the lane's contact sheets (§5.2) at 10 s steps and mark every candidate for the pose's
   landmark text (`CONSTABLE'S GUILDHALL`, `MACLEOD`, `Basement Stairs`, `RESUME`, the checkered
   floor, the portal outline).
2. Confirm the 3 s hold: a hold is a run of ≥2 consecutive 1 fps samples with an identical HUD and
   nearly identical pixels (differ by a few hundred mean-luma units, not by a scene change).
3. Write the candidate time, then extract full-res **once** (§5.3). Record `name | part | t | note`
   exactly as a `poses.tsv` line for §7.

**A measured question this wave should settle.** `KEYFRAME_INDEX.md` (KF27) puts the wall emitter
at `x~17 %, y~40 %`, the scorecard's V6-03 reference text says `x~17 %, y~56 %`, and
`build/qa/p0b_roi_stats.py` hard-codes `y~40.0 %` as the KF27 criterion. The live `beam_close`
frame is 16:9 like the official 3840×2160, so percentages transfer directly. The verifier records
the measured emitter position in `verify.md`; the synthesis reports which figure the shipped build
supports. Do not silently "fix" either document — the finding goes to the wave report.

---

## 5. Frame-extraction recipe

All work is CPU-only, one ffmpeg at a time, on the proxy first. The originals are touched only for a
confirmed candidate time.

### 5.1 Locate a candidate on the 1 fps proxy

```bash
PROXY="$HOME/Videos/tat2_ref_20261127/review/route_lossless_1fps.mp4"      # R1/R2
# R3: PROXY="$HOME/Videos/tat2_ref_20261127/review/route_lossless_part3_1fps.mp4"

# one frame at proxy second 123 (fast input seek; the proxy is 1 fps)
ffmpeg -hide_banner -v error -ss 123 -i "$PROXY" -frames:v 1 /tmp/opencode/r1_probe_0123.png
```

Proxy time ≈ source time (the proxy is `fps=1` from the same timeline, no trim), with **±0.5 s
quantisation** — a 1 s sample cannot place a sub-second beat. That is enough to find the beat,
never to time it.

### 5.2 Contact sheets (optional but recommended)

One sheet per lane covers the whole window at 10 s steps:

```bash
# R1 — part 1, 0–300 s   (30 tiles at 10 s)
ffmpeg -hide_banner -v error -y -ss 0   -t 300 -i "$PROXY" \
  -vf "fps=1/10,scale=240:-1,tile=10x3" -frames:v 1 /tmp/opencode/sheet_r1_10s.png

# R2 — part 1, 300–600 s (same proxy, second half)
ffmpeg -hide_banner -v error -y -ss 300 -t 300 -i "$PROXY" \
  -vf "fps=1/10,scale=240:-1,tile=10x3" -frames:v 1 /tmp/opencode/sheet_r2_10s.png

# R3 — part 3, whole part  (60 tiles at 10 s)
ffmpeg -hide_banner -v error -y -i "$PROXY" \
  -vf "fps=1/10,scale=240:-1,tile=10x6" -frames:v 1 /tmp/opencode/sheet_r3_10s.png
```

Label tiles by eye (`t = offset + index × 10`, offset 0 for R1/R3 and 300 for R2). Do not commit
sheets.

### 5.3 Extract the original only at a candidate time

```bash
SRC="$HOME/Videos/tat2_ref_20261127/route_lossless.mkv"        # p1
# SRC="$HOME/Videos/tat2_ref_20261127/route_lossless_part3.mkv" # p3

OUT="$HOME/Videos/tat2_ref_20261127/review/frames"
mkdir -p "$OUT"

# -ss BEFORE -i = fast seek: ffmpeg lands on the preceding keyframe and decodes
# forward to the timestamp, so the frame at 123.4 s is exact
ffmpeg -hide_banner -v error -y -ss 123.4 -i "$SRC" -frames:v 1 \
  -pix_fmt rgb24 "$OUT/r1_S01_p1_0123.png"
```

- If the candidate is a fast-moving beat, extract a 3-frame burst
  (`-ss 122.9 -frames:v 3` and keep the sharpest) rather than guessing the sub-second.
- Re-extracting the same `-ss` from the same file yields the **same PNG**, so the verifier can
  re-run every command and compare SHA-256 (§7).
- One extraction at a time; each seek on a 27 GB file costs seconds. No parallel ffmpeg, no GPU.
- Never write into `game/`, `docs/reference/`, or the tracked tree.

### 5.4 Naming and record

```
r<lane>_<Sxx|pose>_<part>_<seconds>.png
 r1_S01_p1_0001.png        r2_S17_p1_0342.png       r3_upper_foyer_p3_0412.png
 r3_S24_p3_0288.png        r2_kf18_overlook_p1_0421.png
```

- `<lane>` ∈ `1|2|3`; `<part>` ∈ `p1|p3`; `<seconds>` = 4-digit whole seconds in that part's
  timeline (`0123`), with `.d` only when a sub-second was needed (`0123.4`).
- Frames live under `~/Videos/tat2_ref_20261127/review/frames/` (outside the repo, git-ignored by
  location). Refer to them by the path plus basename in every report.
- Every claim carries the exact command that produced the frame, in a `bash` block or a
  `command` field. A claim without a reproducible command is rejected (§7).
- Note in the same line: `hold` or `motion`, and whether the frame is from part 1 or 3.

### 5.5 Cheap numeric sanity (optional, CPU only)

If a lane wants a luma check on a pose, use the documented method rather than ad-hoc maths:

```bash
python3 build/qa/p0b_roi_stats.py --port "$OUT/r3_upper_foyer_p3_0412.png" --pose upper_foyer
```

It downsamples to 480 px like the W9/L1 baseline. Its `--pose` reference numbers are *port* pose
expectations, so treat the output as a comparison aid, not a verdict, and never let it replace the
human read of the frame.

---

## 6. 120-row mapping rules

The scorecard's 120 rows stay exactly as they are. This wave adds **coverage**, never a score.

1. **Visible subject only.** A row may be marked `confirmed-subject` only when the row's own subject
   is visible in a frame belonging to a `present` beat. Anything else is `not-reached` (beat absent
   or unseen) or `partial-subject` (beat present, subject only partly visible).
2. **A `partial` beat cannot support a PASS/DELTA.** Not now and not in a later wave without new
   evidence: if the beat is `partial`, the row is at most `partial-subject`. The synthesis must not
   upgrade a partial beat into a row verdict to make a tally look better.
3. **The official clip stays the official reference.** Row language, tolerances and reference
   observations come from `KEYFRAME_INDEX.md` / `COMPARISON_PORT_20261124.md`. Where the live frame
   and the official keyframe disagree, the official keyframe wins and the disagreement is recorded
   as a finding about the capture (resolution, motion blur, framing) or about the build/save — not
   as a row delta.
4. **The live capture is a matched-settings P4/ROI reference and a second ground truth.** It can
   confirm that a shipped subject exists, what it looks like at 1440p/60/High/100 %, and settle
   questions the 4K/29.833 fps official clip leaves ambiguous (e.g. the beam emitter position).
   It cannot add a row token, and it cannot contradict a scored row on its own.
5. **Do not edit `COMPARISON_PORT_20261124.md`** (or `row_route_matrix.md`, or the keyframe
   index). Every finding lands in this wave's own outputs (§7). A later adjudication wave may
   consume them.
6. **Audio rows are out of scope for row coverage** — the visible-subject rule (1) already excludes
   them, and §1.4 forbids level claims. `cue-heard` notes may be logged for the synthesis; they
   never change a token.
7. **A row reachable from several beats is confirmed by any one of them** (e.g. AU1-05 across
   S13–S21, V2-03 at S02 or S10). Cite the beat that supplied the frame.
8. **No numeric cross-resolution comparison.** The live capture is 2560×1440, the port baseline
   1920×1080, the official clip 3840×2160. Percentages and the 480 px method are comparable; raw
   pixel counts, edge sharpness and noise are not (and motion blur is ON, §1.3).

### 6.1 Beat → row reverse index (complete: all 120 rows)

Every scorecard row names at least one official beat; this index is the inverse, so a lane can list
"rows this beat unlocks" without re-reading 120 rows. Range references count at any beat in the
range.

| Beat | Span | KF | Rows whose reference names this beat |
|---|---|---|---|
| S01 | 00:00.00–00:02.15 | KF01 | V1-01 V2-01 V3-04 V4-01 V5-01 V7-01 UI1-01 AU1-01 AU4-01 |
| S02 | 00:02.15–00:02.60 | (KF12) | V2-03 UI4-05 AU1-03 |
| S03 | 00:02.60–00:06.57 | KF02 | V1-02 V4-02 UI3-01 AU1-02 AU3-01 G2-01 |
| S04 | 00:06.57–00:18.24 | KF03 KF04 | V5-02 UI2-02 AU4-02 |
| S05 | 00:18.24–00:26.58 | KF05 KF06 | V2-02 V4-03 V7-02 UI2-01 AU1-04 G1-01 |
| S06 | 00:26.58–00:38.17 | KF07 KF08 | UI4-01 UI4-02 AU4-03 |
| S07 | 00:38.17–00:51.08 | KF09 | V3-02 UI2-07 G1-02 AU2-01 |
| S08 | 00:51.08–00:56.08 | KF10 | V1-03 UI3-06 G1-03 |
| S09 | 00:56.08–01:04.80 | KF11 | UI4-03 UI5-05 AU4-04 G5-01 |
| S10 | 01:04.80–01:09.44 | KF12 | V2-03 V2-05 UI4-05 AU1-03 |
| S11 | 01:09.44–01:10.81 | KF13 | V7-03 UI4-04 |
| S12 | 01:10.81–01:20.10 | KF14 | V5-03 V6-01 UI3-02 UI3-05 AU3-03 AU6-01 G1-05 |
| S13 | 01:20.10–01:39.30 | KF15 | V1-04 V2-01 V3-01 V4-04 UI5-01 AU1-05 AU3-02 AU5-01 AU6-02 G1-04 G2-02 |
| S14 | 01:39.30–01:49.50 | KF16 | V1-05 V4-05 UI2-03 UI5-03 AU5-02 AU6-03 G3-01 G4-01 |
| S15 | 01:49.50–01:58.50 | KF17 | V2-04 UI2-04 UI5-02 AU5-02 G2-03 |
| S16 | 01:58.50–02:11.00 | — | AU6-03 G4-02 |
| S17 | 02:11.00–02:23.30 | KF18 | V4-05 UI3-03 AU6-06 G2-04 G4-05 G5-02 |
| S18 | 02:23.30–02:30.70 | KF19 KF20 | V6-02 UI5-01 AU5-03 AU6-04 G3-02 |
| S19 | 02:30.70–02:33.00 | KF21 KF22 | UI5-04 AU5-04 G3-03 G3-04 |
| S20 | 02:33.00–02:54.50 | KF23 | V2-04 V4-06 UI5-07 AU6-06 G4-03 |
| S21 | 02:54.50–03:04.50 | KF24 | V3-03 V5-03 UI2-05 UI3-05 AU1-05 |
| S22 | 03:04.50–03:17.10 | KF25 | V1-06 V5-04 UI2-06 UI3-04 UI3-05 AU1-06 AU5-07 G1-06 |
| S23 | 03:17.10–03:22.00 | KF26 | V5-05 V7-04 UI2-06 AU5-08 G4-04 |
| S24 | 03:22.00–03:29.00 | KF27 | V4-07 V6-03 UI3-05 UI5-01 AU3-04 AU6-05 G5-03 |
| S25 | 03:29.00–03:37.40 | KF28 | V4-07 V6-04 UI5-06 AU5-05 G5-03 |
| S26 | 03:37.40–03:41.90 | KF29 | V1-07 UI2-04 UI5-06 AU3-05 AU5-06 G2-05 G5-04 |
| S27 | 03:41.90–03:45.64 | KF30 | V7-05 UI1-02 AU4-05 G5-05 |

Counts: Visual 37, Audio 31, HUD/UI 27, Gameplay 25 = 120; no row is missing from the index.

---

## 7. Synthesis and verification

Two more roles after the three lanes. Neither may edit the scorecard.

### 7.1 Synthesizer (S)

Inputs: the three lane reports only (plus frames on disk). Outputs, in this order:

| Output | Path | Contents |
|---|---|---|
| Beat presence table | `docs/reports/logs/live-ref-20261127/beat_presence.md` | the §3 table, 27 rows filled, each `present`/`partial`/`absent`/`unseen-gap?` with part+time and frame basename |
| Machine-readable twin | `docs/reports/logs/live-ref-20261127/beat_presence.json` | `{beat, kf, status, part, t, frame, command_sha256, notes}` per beat |
| Row coverage | `docs/reports/logs/live-ref-20261127/row_coverage.md` | 120 rows × `confirmed-subject` / `partial-subject` / `not-reached` + the beat and frame that carry it |
| Pose table | `docs/reports/logs/live-ref-20261127/poses.md` | the seven poses, part/time, frame, hold-vs-motion, emitter-position measurement |
| Wave report | `docs/reports/live-ref-20261127.md` | what the capture is, what is present/absent, tally, the gap statement, open items |

Rules:

- **Reconcile before deciding.** A beat seen by two lanes is one beat; use the earlier complete
  occurrence as the primary citation and list the second in `notes`. A beat seen by no lane but
  whose route position falls in the gap (§1.2) is `unseen-gap?`, never `absent`.
- **No presence without a frame.** Every non-`absent` row must carry a frame basename that exists.
- **No row token.** `confirmed-subject` is coverage, not a score; the synthesis must say so in the
  report's own words, and must not print a PASS/DELTA/MISSING/HARD_LIMIT/N/A-route tally.
- **State the route outcome plainly**: "N of 27 beats present, M partial, K absent, J unseen-gap;
  120 rows with X confirmed subjects" — and nothing stronger.
- **Carry the caveats** from §1: motion blur, frame cadence (part 3 worst), the 226.5 s gap, the
  Custom label, clipped audio, 1 fps quantisation.

### 7.2 Independent verifier (V)

Fresh context, read-only on the frames, writes only its own report. It re-checks **every** claimed
`present` and `partial` beat:

| Check | Method | Reject if |
|---|---|---|
| Frame exists | `test -f` on the cited path | missing |
| Frame is reproducible | re-run the recorded `ffmpeg -ss … -i … -frames:v 1` and compare `sha256sum` with the lane's | hash differs (wrong time or edited command) |
| Time in range | part/time inside the lane's assigned window | outside the window, or part mismatch |
| Subject visible | open the frame and check the beat's defining elements from §3 | subject not visible, or a different beat |
| Ambiguity | S02 vs S10 by flow position | loading art with no flow context |
| No double count | one primary citation per beat | two lanes claim the same beat with incompatible frames |
| Partial honesty | `partial` names the missing element | a `partial` with no named gap |
| Row derivation | every `confirmed-subject` traces to a `present` beat and a real frame | derived from a `partial` beat, or from audio |

Outputs:

| Output | Path |
|---|---|
| Verification log | `docs/reports/logs/live-ref-20261127/verify.md` (per-beat PASS/REJECT + reasons) |
| Machine-readable | `docs/reports/logs/live-ref-20261127/verify.json` (`{beat, claimed, verdict, reextracted_sha256, reason}`) |
| Emitter measurement | the same `verify.md`, KF27 emitter `x%/y%` on the `beam_close` frame |

Verdict vocabulary: `CONFIRMED` / `REJECTED:no-frame` / `REJECTED:hash` / `REJECTED:subject` /
`REJECTED:range` / `REJECTED:partial-unqualified`. A rejected beat goes back to the synthesis as
`unconfirmed` and must not appear as `present` in the wave report. The wave can close with
rejections on the record — it cannot close with a `present` claim that V did not confirm.

### 7.3 Order of work

1. R1, R2, R3 in parallel (separate sessions; each writes only its lane report and its frames).
2. S merges → the five outputs in §7.1.
3. V audits → the three outputs in §7.2, then S applies the verdicts.
4. Integrator updates `docs/HANDOFF_NEXT_AGENT.md` and, if the capture changes a fidelity finding,
   `docs/FIDELITY_GAPS.md` — in the same wave, never inside the scorecard.

Lane report paths (assigned now, so nobody improvises):

```
docs/reports/logs/live-ref-20261127/lane-r1.md
docs/reports/logs/live-ref-20261127/lane-r2.md
docs/reports/logs/live-ref-20261127/lane-r3.md
```

---

## 8. Risks

| # | Risk | Evidence it is real | Impact | Mitigation |
|---|---|---|---|---|
| 1 | **Part 2 gap** | `Δstart = 826.54 s` vs a 600 s part 1 → 226.5 s unrecorded | the whole portico→foyer sequence or all pose holds can be missing | `unseen-gap?` when the beat's route position sits between the part-1 tail and the part-3 head; every `absent` requires cross-lane absence *and* a gap-shadow check |
| 2 | **Incomplete / out-of-order route** | owner does not know how many beats or poses were hit; 1,200 s capture vs 225.6 s route | presence is genuinely unknown; a neat 27/27 is unlikely | content-first index per lane; no order assumption; S reports the true count |
| 3 | **Owner uncertainty** | stated in the brief | risk of reviewers "finding" a beat that is not there | frame + reproducible command mandatory; V re-extracts everything |
| 4 | **Audio clipping** | part-1 max 0.0 dBFS at Master 100; test10 max −5.6 dBFS | no level/loudness/silence claim is possible | §1.4: `cue-heard` notes only; audio rows excluded from coverage |
| 5 | **`Custom` / High label** | stills read `Custom` + 100 % + all-High groups | mislabelling the capture as "High preset" would poison later comparisons | quote the exact strings from §1.3; note the preset's 71 % default |
| 6 | **Motion blur ON** | stills show Motion Blur checked | 60 fps gameplay frames are blurred; detail/edge judgements fail | prefer holds; label every frame `hold`/`motion`; no sharpness verdicts from motion frames |
| 7 | **10-minute split** | both files stop at exactly 600.000 s (a 600 s recorder cap) | a beat can straddle the boundary; part 1 ends mid-action | R2 must log the last 15 s and R3 the first 15 s explicitly; S joins at the boundary |
| 8 | **1 fps, 480p proxy** | proxy is `480×270`, `1 fps` | sub-second cues and small UI text are invisible; timings cannot be read | full-res only at candidates; ±0.5 s stated; UI strings verified at 1440p |
| 9 | **Frame cadence / dup-drop** | part 1 `dup=1961 drop=1955`; part 3 `32,503 packets / 600 s`, `dup=996 drop=992` | motion is uneven; part 3 cannot carry timing claims | R1/R2: coarse timing only; R3: no timing claims, flag every observation; both: content only |
| 10 | **No capture manifest** | directory has no `manifest.json` / `poses.tsv`; helper is single-file | provenance is weaker than a `P0B_LIVE_VERIFY PASS` | record hashes/ffprobe here (§1.1); do not claim a verified capture |
| 11 | **S01 clipped by a late start** | recorder started at 01:38:06; unknown whether the menu was up | `V7-01` / `UI1-01` could be `partial` for a capture reason | R1 checks the first 10 s; if the menu is absent, say "not in capture", not "absent in build" |
| 12 | **Shared loading art** | S02 and S10 both use KF12 art | false `present` for one of them | flow-position disambiguation; `partial` when it cannot be settled |

---

## 9. Blockers and preconditions

1. **R3's proxy was still encoding when this plan was written** (`review/route_lossless_part3_1fps.mp4`
   had no `moov` atom yet; part 1's proxy is complete at 600 packets). R3 must wait for
   `PROXIES_DONE` before starting. Nothing else in the plan depends on it.
2. **The P0b verify helper cannot verify a two-part capture** (`CAPFILE` is fixed to
   `$CAPDIR/route_lossless.mkv`, and `verify` expects one file plus `poses.tsv`). This wave does not
   edit it. Either the integrator adds a `--capfile` option later, or the wave closes on the
   recorded hashes + per-frame re-extraction (§7.2). Do not report `P0B_LIVE_VERIFY PASS`.
3. **No `poses.tsv` exists.** The pose times are an output of §4, not an input; V's re-extraction is
   the substitute for the helper's pose hash table.
4. **Disk**: originals 54.93 GB + proxies ~22 MB are already on disk; full-res candidate frames are
   ~2–5 MB each. Keep the frame set bounded (≤ 3 frames per beat/pose, ≤ ~120 PNGs) and never copy
   the originals.

---

## 10. One-line summary

A 1,200 s, two-part, lossless 1440p60 capture of the shipped build at High/100 %, with a measured
226.5 s hole between the parts; three lanes index their windows at 1 fps, cite a reproducible frame
for every beat they claim, and a verifier re-extracts every claim before the wave may say what the
route contains.
