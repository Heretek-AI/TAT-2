# Live-reference lane R1 — shipped-game footage, part 1, 0–300 s

**Status:** presence review only. Prepared 2026-11-27 by lane R1 of the
live-reference footage review. Read-only: no game, build, scorecard, matrix,
keyframe-index or test file was edited, and nothing was committed.

**Claim boundary.** The footage is the **shipped UE5.5 build** (`1.5.148559`) on
the owner's machine, captured at 2560×1440/60 into
`~/Videos/tat2_ref_20261127/route_lossless.mkv` (part 1, 600 s). It is *not* the
port. The owner's route is a normal mission session: it does not follow the
official clip's order, it starts mid-Den, and it selects a **different mission**
(see §2). This report records only **what is visible in 0–300 s** of part 1. No
`PASS`/`DELTA`/`MISSING`/`HARD_LIMIT`/`N/A-route` token is assigned, no row is
scored, and no claim is made about 300–600 s, part 2 (not present) or part 3.

---

## 1. Method

### 1.1 Inputs read

| Input | Use |
|---|---|
| `~/Videos/tat2_ref_20261127/review/route_lossless_1fps.mp4` (600 s, 480×270, 1 fps) | the scanned proxy for part 1 |
| `~/Videos/tat2_ref_20261127/review/route_lossless_contact_5s.png` (3200×2160, 8×15 tiles) | first-pass overview at 5 s steps |
| `~/Videos/tat2_ref_20261127/route_lossless.mkv` (600 s, 2560×1440, 60 fps) | four full-res candidate frames only (t=210, 235, 247, 254) |
| `docs/reference/clip_1795033698901/clean/*.jpg` (30 keyframes) | official comparison frames (KF02, KF05–KF11, KF13–KF16, KF30 opened directly) |
| `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` | beat boundaries, keyframe mapping, official observations |
| `docs/reference/clip_1795033698901/BREAKDOWN.md` | S01–S27 narratives and per-beat subjects |
| `docs/reference/clip_1795033698901/row_route_matrix.md` | 120 row ids and their short criteria |
| `docs/reports/p0b-route-rescore.md` | claim-boundary precedent (frame captured ≠ beat played) |
| `docs/reports/p0b-live-capture.md` §5 | the six/seven pose ids and their reference keyframes |

### 1.2 What was done

- The proxy was decoded to 600 PNGs at 1 fps (`ffmpeg -i … -fps_mode passthrough
  full/%04d.png`, 69 MB) and inspected as labelled 4×5 / 5×4 montages at 1 s and
  5 s steps; ambiguous spans were re-read frame by frame.
- Scene cuts were cross-checked with
  `ffmpeg -vf "select='gt(scene,0.12)',showinfo"` on the proxy (46 cut points).
- Every beat/pose claim below was re-extracted from the proxy with
  `ffmpeg -ss <t> -i route_lossless_1fps.mp4 -frames:v 1` into
  `~/Videos/tat2_ref_20261127/review/r1_*.png` (all 480×270) and viewed. The
  four candidate comparisons were also extracted from the original
  (`r1_full_*.png`, 2560×1440).
- No GPU, Vulkan, Xvfb, Steam, Godot or game process was started. No audio
  analysis was performed (visual lane).

### 1.3 Time convention

All times are on the **proxy timeline**, written `mm:ss`, and were taken by
direct `-ss` extraction, not by frame-index arithmetic. At 1 fps a still shows
the frame at that instant; transient prompts between samples can be missed
(see §7).

### 1.4 Verdict vocabulary

| Verdict | Meaning |
|---|---|
| `present` | the official beat's defining subject is visible and identifiable in the frame |
| `partial` | the subject class is visible, but a defining element, composition, state or copy differs, or the beat occurs in a different context/order |
| `absent` | not visible anywhere in 0–300 s; the cited frame shows what the route was doing instead |

A verdict is about **visual presence**, not parity. A `present` verdict does not
mean the port matches, and an `absent` verdict does not mean the port is wrong —
the owner simply did not play that beat in this segment.

---

## 2. What the owner actually played (0–300 s)

The recording **starts inside the Thieves' Den**, already in first person with
the HUD up (`Johnny Cipher`, level 4) — there is no main menu and no Den entry
sequence. The session is a Den hub visit, then a mission deployment, then an
exterior approach to the Constables' Guildhall.

| Proxy span | What is on screen |
|---|---|
| 00:00–00:09 | Den desk: iridescent faceted diamond, `[F] CHANGE DECORATION`; at 00:05 the rolltop desk with `[F] READ LEDGER` |
| 00:10–00:46 | **JOURNAL** tab (00:10–00:19) → **BLACK MARKET** tab (00:20–00:46), browsing tool/cosmetic previews |
| 00:48–01:02 | Den pan, then the brass telescope station (00:50–00:54) and the scripted rooftop sky view (00:55–01:02) |
| 01:03–02:37 | Walk to the armoire, `[F] CUSTOMIZE LOADOUT` (01:24), then the **WARDROBE** UI (01:25–02:37) with loadout slots, calling cards and tool previews |
| 02:38–02:51 | Wardrobe closes; free pan/walk across the Den |
| 02:52–03:05 | Den prop corner: trunks, gramophone (02:55–03:02), golden statue |
| 03:05–03:10 | Wanted-poster wall (five framed posters) beside the leaded window |
| 03:11–03:15 | Map table: 3D `KILCAIRN` parchment, wooden `CONSTABLES' GUILDHALL` token, confirm modal at 03:15 |
| 03:16 | Loading screen (KF12 art; S02-art occurrence before prep) |
| 03:17–03:38 | **MISSION PREPARATION** — map `CONSTABLES' GUILDHALL`, mission **`Item Collection Heist`**, **`Time Limit: 120 minutes`**, `Contract Inactive`, Mode Solo, Difficulty Novice; countdown `6…1` at 03:33–03:38 |
| 03:39–03:50 | Loading screen 2 (KF12 art) |
| 03:51–03:58 | Briefing letter: **Staff of Edinburgh** gem heist, 120 minutes, `[SPACE] CONTINUE` |
| 03:59–04:12 | Spawn on an **outdoor canal-side street**; walk past industrial pipework; the Guildhall is seen across a perimeter fence (04:07–04:09), `MACLEOD` sign in the distance |
| 04:13–04:42 | Pause menu → **SETTINGS** (General / Video / Audio / Controls), ~30 s detour; resume at 04:42 |
| 04:43–04:59 | Red player-noise arcs, canal walkway, then looking up at a wall/lamp outside the building |

**This is not the official mission.** The official clip plays `Cleanout Heist`
on the same map with `Time Limit: 55 minutes` and a `Steal 4,000 in loot value
[0/4,000]` tracker; the recorded session plays `Item Collection Heist`
(120 minutes) with `Steal the components of the Staff of Edinburgh[0/3]`
(Gem of Arcana / Strength / Fire). The letter copy, the spawn, the HUD objective
and the pause-footer seed (`701694559`, not `1025051536`) all follow from that
choice. The Den save state, by contrast, matches the reference exactly
(Level 4, 94/500, Contracts #1–#2 completed, #3 active).

---

## 3. Beat table (S01–S27)

Official times are the S01–S27 boundaries in `KEYFRAME_INDEX.md` §2 /
`BREAKDOWN.md`. Proxy times are the span in which the subject is visible in
part 1 (0–300 s); `—` means the beat is not reached in this segment.

| Sxx | official t | proxy t | verdict | evidence frame | subject / what differs |
|---|---|---|---|---|---|
| **S01** Startscreen | 00:00.00–00:02.15 | — | **absent** | `r1_start_den_000.png` | Recording begins inside the Den with the HUD up; no menu stack, no `PLAY/SETTINGS/CREDITS/QUIT`, no street backdrop. |
| **S02** Loading 1 | 00:02.15–00:02.60 | 03:16 | **partial** | `r1_s10_mapload_196.png` | There is **no main-menu → Den load** (the recording starts in the Den). A KF12-art loading screen does appear at 03:16 on the way into Mission Prep; by the plan's S02/S10 flow-position rule that places it before prep (S02-like), but it is a map load, not the Den-entry load, so it is recorded as partial, not present. |
| **S03** Den entry | 00:02.60–00:06.57 | 00:00, 01:24 | **partial** | `r1_start_den_000.png`, `r1_s04_loadout_prompt_084.png` | Den interior, rafters, desk and armoire are present, but the scripted fade-in/rising pan is absent (the session is already standing at the decoration table). The KF02 station prompt `[F] CUSTOMIZE LOADOUT` appears at 01:24, not at 00:06. |
| **S04** Wardrobe | 00:06.57–00:18.24 | 01:25–02:37 | **present** | `r1_s04_wardrobe_kf03_086.png`, `r1_s04_wardrobe_kf04_122.png` | `WARDROBE` overlay with Spider/Chameleon, `Edit Loadout` slots, tooltips, Head/Body/Calling Card, 3D Spider. KF03 state at 01:26 (Zipwire tooltip; the Head slot card shows the **cap**, not KF03's bowler) and KF04 state at 02:02 (slot 3 expanded 4-tool row + Vistara Diamond tooltip). |
| **S05** Telescope & posters | 00:18.24–00:26.58 | 00:50–01:02, 03:05–03:10 | **present** | `r1_s05_telescope_057.png`, `r1_s05_posters_189.png` | Crater moon + golden cheese wedge + orbiting chunks + `[F] EXIT` (KF05); five framed `WANTED` posters beside the leaded window (KF06). Cheese chunks read as four vs the reference's three; poster text is not legible at this distance. |
| **S06** Ledger (Journal/Black Market) | 00:26.58–00:38.17 | 00:10–00:46 | **present** | `r1_s06_journal_010.png`, `r1_s06_blackmarket_026.png` | `JOURNAL` tab: Level 4, 94/500, Contract #2 *Into the Lion's Den* (Completed), #3 *In the Eye of the Beholder* (Active) — text matches KF07. `BLACK MARKET`: `YOUR TOTAL ASSETS: (£) 26,275`, TOOLS/GUILD PERKS/SPIDER/CHAMELEON columns, ✓ and padlocks (KF08). The preview pane at 00:26 shows `Bowler Hat with Mustache` (LOCKED); KF08 shows `Zipwire ✓ PURCHASED`. |
| **S07** Props & Gramophone | 00:38.17–00:51.08 | 00:00–00:05, 02:52–03:02 | **partial** | `r1_start_den_000.png`, `r1_s07_gramophone_180.png` | Iridescent table diamond + `[F] CHANGE DECORATION` at the decoration station (00:00); the trunks/chests and the gramophone are visible at 02:52–03:02. KF09's composition — lit 3-candle candelabra, `[F] TURN OFF` (ON/playing), green floor diamond and table diamond in one frame — is not reproduced; the gramophone corner is dark and its prompt text is not legible at 480p. No trunk treasure cycle seen. |
| **S08** Map table & confirm | 00:51.08–00:56.08 | 03:11–03:15 | **present** | `r1_s08_maptable_194.png`, `r1_s08_confirm_195.png` | 3D map table with `KILCAIRN` parchment, wooden `CONSTABLES' GUILDHALL` token, brass banker's lamp, marble bust, `[F] ENTER MATCH` and the card overlay; then `Join Mission with these settings? / Difficulty: Novice / Mode: Solo` with `PREPARE FOR MISSION` / `CANCEL`. Matches KF10 subject. |
| **S09** Mission prep & countdown | 00:56.08–01:04.80 | 03:17–03:38 | **present (different mission)** | `r1_s09_prep_210.png`, `r1_s09_countdown_213.png` | Full `MISSION PREPARATION` screen: map card `CONSTABLES' GUILDHALL`, `Item Collection Heist`, `Time Limit: 120 minutes`, `Contract Inactive`, Mode Solo / Difficulty Novice, `READY`, 3D Spider on a rooftop under the moon; `MISSION STARTING IN 6…1` at 03:33–03:38. **Mission name and time limit differ from KF11 (`Cleanout Heist`, 55 minutes).** The KF16 gate arch is visible only as the small map-card thumbnail. |
| **S10** Loading 2 | 01:04.80–01:09.44 | 03:39–03:50 | **present** | `r1_s10_loading2_225.png` | KF12 art: indigo skyline, dirigibles, moon, `LOADING...`, gold `THICK AS THIEVES` emblem. The central cyan/white spinner ring is not visible in the sampled frame. The same art also appears at 03:16 on the way into prep (recorded under S02 as partial). |
| **S11** Briefing letter | 01:09.44–01:10.81 | 03:51–03:58 | **partial** | `r1_s11_letter_235.png` | Parchment letter with `[SPACE] CONTINUE` and a right scrollbar, but the copy is the **Staff of Edinburgh** job (`Find the set of gems… 120 minutes… 20 minutes before collapsing`), ~10 lines, and the backdrop is a blurred **outdoor street**, not KF13's blurred Guildhall safe room. |
| **S12** Safe room & catwalk | 01:10.81–01:20.10 | — | **absent** | `r1_s12_spawn_241.png` | Mission spawn is an outdoor canal-side street (paving, barrels, pipework, iron fence). No brick safe room, no green/violet Escape Portal outline, no oil lantern, no `SPIDER` flyer, no metal grate catwalk, no railing vault. |
| **S13** Street/alley approach | 01:20.10–01:39.30 | 03:59–04:12 | **partial** | `r1_s13_street_242.png`, `r1_s13_guildhall_side_247.png`, `r1_s13_barrels_251.png` | A wet night street, barrels/crates, industrial pipework, iron fences and the Guildhall across a perimeter fence are present (and the `MACLEOD` sign at 04:07–04:11). **Absent:** `BARRON'S DEMOLITION` banner, oil drums/ladder alley drop, vintage car and its headlights, gate guard, guard barks. The street is a different approach from a different spawn. |
| **S14** 1st ZipWire & gate | 01:39.30–01:49.50 | — | **absent** | `r1_s13_guildhall_side_247.png` | The Guildhall is viewed from outside its side fence: no `CONSTABLE'S GUILDHALL` arch lettering, no griffin steps, no patrolling guard, no car headlights, and no ZipWire launch/crank (the launcher is in the hotbar but never raised). |
| **S15** 2nd ZipWire & crank | 01:49.50–01:58.50 | — | **absent** | `r1_end_outside_299.png` | Not reached; at 04:59 the player is still outside the building. |
| **S16** Roofline & 3rd ZipWire | 01:58.50–02:11.00 | — | **absent** | `r1_end_outside_299.png` | Not reached. |
| **S17** Gate pillar & descent | 02:11.00–02:23.30 | — | **absent** | `r1_end_outside_299.png` | Not reached; no courtyard drop, no griffin overlook. |
| **S18** Smoke bomb | 02:23.30–02:30.70 | — | **absent** | `r1_end_outside_299.png` | Not reached; no canister, plume or courtyard. |
| **S19** Vistara scan | 02:30.70–02:33.00 | — | **absent** | `r1_end_outside_299.png` | Not reached; no diamond equip or scan pulse. |
| **S20** Side wing & `MACLEOD` | 02:33.00–02:54.50 | — | **absent** (subject only distant) | `r1_s13_guildhall_side_247.png` | The `MACLEOD` sign is visible in the distance at 04:07–04:11, but the side-wing balcony, iron balustrade, barred red-lit window and terrace patrol are not visited in 0–300 s. |
| **S21** Blue double doors | 02:54.50–03:04.50 | — | **absent** | `r1_end_outside_299.png` | Not reached; no portico or blue doors. |
| **S22** Parlor & pickpocket | 03:04.50–03:17.10 | — | **absent** | `r1_end_outside_299.png` | Not reached; no interior, NPC or pickpocket. |
| **S23** Takedown | 03:17.10–03:22.00 | — | **absent** | `r1_end_outside_299.png` | Not reached. |
| **S24** Foyer & beams | 03:22.00–03:29.00 | — | **absent** | `r1_end_outside_299.png` | Not reached; no checkered foyer, statue case, floor plate or beam. |
| **S25** Ward lockdown | 03:29.00–03:37.40 | — | **absent** | `r1_end_outside_299.png` | Not reached; no beam trigger, purple ward or green vines. |
| **S26** Crimson alarm & stairs | 03:37.40–03:41.90 | — | **absent** | `r1_end_outside_299.png` | Not reached; no alarm, no slate stairwell. |
| **S27** Pause & quit | 03:41.90–03:45.64 | 04:13–04:14, 04:41–04:42 | **partial** | `r1_s27_pause_254.png` | The pause modal itself is present and matches KF30's layout (`RESUME / SETTINGS / RETURN TO THIEF'S DEN / QUIT TO DESKTOP`, teal/copper Art-Nouveau border, footer `1.5.148559   Novice   701694559`). It is opened **mid-route to change settings**, not at the end of a run: no `QUIT TO DESKTOP` selection, no teardown, no digital-silence tail, and the footer seed differs from the reference (`1025051536`). |

**Counts (presence only, no scoring):** present 6 — S04, S05, S06, S08, S09,
S10; partial 6 — S02, S03, S07, S11, S13, S27; absent 15 — S01, S12, S14–S26.

---

## 4. Pose table

Pose ids and reference keyframes are the p0b capture poses
(`docs/reports/p0b-live-capture.md` §5; `docs/reports/logs/p0b/dry-run/manifest.json`).

| Pose | ref | proxy t | verdict | evidence frame | subject / what differs |
|---|---|---|---|---|---|
| `gate` | KF16 (01:40.20) | 04:07 | **partial** | `r1_s13_guildhall_side_247.png`, `r1_full_guildhall_247.png` | Street-side approach to the Guildhall is present, with iron fence, stone piers, moon and a red-lit lifting gate/lock structure, and the `MACLEOD` sign behind. **Not KF16's gate:** no `CONSTABLE'S GUILDHALL` arch lettering, no steps, no patrolling guard with red eyes, no vintage car or headlight glare, no ZipWire viewmodel. The arch appears only as the prep-card thumbnail at 03:30 (`r1_s09_prep_210.png`). |
| `kf18_overlook` | KF18 (02:14.80) | — | **absent** | `r1_end_outside_299.png` | No elevated cable/roof overlook of the gate pillars and griffin steps in 0–300 s. The only elevated view (04:50, `r1_s13_walkway_290.png`) is a canal walkway with an iron fence; no crowned pillars, griffins or ZipWire cable. |
| `upper_foyer` | KF27 (03:27.60) | — | **absent** | `r1_end_outside_299.png` | No foyer interior in this segment. |
| `yaw180` | KF27 | — | **absent** | `r1_end_outside_299.png` | No foyer interior. |
| `lounge` | none (p0b pose; not in the official clip) | — | **absent** | `r1_end_outside_299.png` | No lounge/guard-marker view. |
| `lounge_beam` | none (p0b pose; not in the official clip) | — | **absent** | `r1_end_outside_299.png` | No C_57 beam view. |
| `beam_close` | KF27 | — | **absent** | `r1_end_outside_299.png` | No beam card view. |

Pose summary: 0 present, 1 partial (`gate`), 6 absent **within 0–300 s**. The
interior poses are not claimed absent from the recording — only from this
segment (see §6).

---

## 5. Row ids whose subject is visible

Row ids are from `docs/reference/clip_1795033698901/row_route_matrix.md`; a row is listed
only because its **subject** is in the frame. This is not a score and says
nothing about how well the port reproduces it. Audio rows (AU*) are excluded:
this lane did no audio analysis, and their subject is not visible.

| Evidence frame | Proxy t | Row ids with subject visible | Note |
|---|---|---|---|
| `r1_start_den_000.png` | 00:00 | V3-02, V4-02, G1-02, UI3-01 | Iridescent faceted diamond on the decoration table, `[F] CHANGE DECORATION`, radiator/desk/rafters, `Johnny Cipher` level 4 card + compass. The green floor diamond is not in this frame; the swap animation is not seen. |
| `r1_s06_journal_010.png` | 00:10 | UI4-01 | `JOURNAL` tab, Level 4 94/500, Contract #2/#3 cards (text matches KF07). |
| `r1_s06_ledger_prompt_005.png` | 00:05 | UI2-01 | `[F] READ LEDGER` on the open ledger at the rolltop desk (the S05→S06 station). |
| `r1_s06_blackmarket_026.png` | 00:26 | UI4-02 | `BLACK MARKET`, `YOUR TOTAL ASSETS: (£) 26,275`, four columns, ✓/padlocks. Preview selection differs from KF08. |
| `r1_s05_telescope_057.png` | 00:57 | V2-02, G1-01, UI2-01 | Moon + cheese wedge + chunks + `[F] EXIT`; telescope station prompt chain. |
| `r1_s04_loadout_prompt_084.png` | 01:24 | V4-02 | Armoire/mirror with `[F] CUSTOMIZE LOADOUT`; Den dressing. |
| `r1_s04_wardrobe_kf03_086.png` | 01:26 | UI2-02, V5-02 | Wardrobe slots, tooltips, 3D Spider turntable (KF03 state). |
| `r1_s04_wardrobe_kf04_122.png` | 02:02 | UI2-02, V5-02 | Slot 3 expanded 4-tool row + Vistara Diamond tooltip (KF04 state). |
| `r1_s07_gramophone_180.png` | 03:00 | V4-02 | Gramophone horn visible in the dark prop corner; `[F] TURN ON/OFF` prompt is not legible, so UI2-07 is not claimed. |
| `r1_s05_posters_189.png` | 03:09 | V4-03, V4-02, V1-02 (partial) | Five framed `WANTED` posters + leaded teal window; poster text not legible at this distance, and the volumetric shaft is not clearly separable from the window glow in this frame. |
| `r1_s08_maptable_194.png` | 03:14 | G1-03, UI3-06, V1-03, UI2-01 | 3D `KILCAIRN` map, wooden token, banker's-lamp pool, bust, `[F] ENTER MATCH`, keybind card. |
| `r1_s08_confirm_195.png` | 03:15 | G1-03 | `Join Mission with these settings?` modal with Difficulty/Mode and PREPARE/CANCEL. |
| `r1_s10_mapload_196.png` | 03:16 | UI4-05, V2-03 | KF12 loading art before prep (S02-art occurrence; see S02 note). |
| `r1_s09_prep_210.png` | 03:30 | UI4-03, G5-01 | Prep cards + READY; **mission is Item Collection Heist / 120 minutes** (official is Cleanout Heist / 55). Map-card thumbnail shows the KF16 gate arch. |
| `r1_s09_countdown_213.png` | 03:33 | UI5-05, UI4-03 | `MISSION STARTING IN 6...`, `UNREADY`, Mode Solo / Difficulty Novice. |
| `r1_s10_loading2_225.png` | 03:45 | UI4-05, V2-03 | KF12 art with `LOADING...` and gold emblem; spinner ring not visible. |
| `r1_s11_letter_235.png` | 03:55 | UI4-04, V7-03 | Parchment letter + `[SPACE] CONTINUE` + blurred street backdrop; copy is the Staff of Edinburgh job, not KF13's. |
| `r1_s12_spawn_241.png` | 04:01 | UI3-02 (partial), V3-01 (partial) | Outdoor spawn; HUD tracker `Steal the components of the Staff of Edinburgh[0/3]` (not `Steal 4,000…`), hotbar, Light Gem; damp paving with a reflecting puddle. |
| `r1_s13_street_242.png` | 04:02 | UI3-02 (partial), V3-01 (partial) | Wet night street, industrial pipework, distant Guildhall; same tracker caveat. |
| `r1_s13_guildhall_side_247.png` | 04:07 | V4-06, V2-01 (partial) | `MACLEOD` vertical sign in the distance; Guildhall across the fence; no rain streaks visible, puddle reflections only. |
| `r1_s13_barrels_251.png` | 04:11 | V4-06 | Barrels/green tarp/grating corner; `MACLEOD` sign at right edge. |
| `r1_s27_pause_254.png` | 04:14 | UI1-02, V7-05, G5-05 (partial) | Pause modal + build/difficulty/seed footer; blurred dark backdrop; no quit selection. |
| `r1_ui5_noise_arcs_284.png` | 04:44 | UI5-01, UI3-05 | Twin red player-noise arcs around the Light Gem while walking. |
| `r1_s13_walkway_290.png` | 04:50 | UI3-02 (partial) | Canal walkway under the Guildhall wall; hotbar/tracker visible. |

Rows whose subject is **not** visible anywhere in 0–300 s are not enumerated
exhaustively above; they include the guard/NPC, vintage-car, gate-arch, smoke,
Vistara-scan, ward, alarm, parlor, blue-door and foyer rows, plus every AU row
(not assessed) and the motion-only rows G2-01 and V7-02, which a 1 fps still
cannot evidence. UI4-03 is present but carries the different-mission copy noted
above.

---

## 6. Part-2 gap risk and ambiguities

### 6.1 Part-2 gap

The review directory contains **part 1** (`route_lossless.mkv`, 600 s) and
**part 3** (`route_lossless_part3.mkv`, 600 s wall clock; its 1 fps proxy holds
542 frames) but **no part-2 file** (`route_lossless_part2*` is absent; only the
two proxies and two contact sheets exist). The review plan measures the
unrecorded gap between the two parts at **226.5 s** (part 1 ends at wall clock
≈600.0 s, part 3 starts at ≈826.5 s — `live-ref-review-plan.md` §1.2), which is
long enough to hold an entire interior sequence. Part 2 was killed at start, so
the gap is content-ordered, not clock-ordered: nobody knows which beat the run
had reached at t = 600.

Two consequences matter here:

- part 1 continues past this lane's 300 s boundary and, in a coarse 10 s sample
  of 300–600 s, shows a building entry around 05:00–05:40 and a guard-spot /
  `Time Until Respawn` capture cycle around 06:00–06:30, ending inside the
  Guildhall at a purple ward/lock view;
- part 3 opens **already inside the foyer** (checkered marble, purple ward,
  green vines, beams) and ends on the main menu.

So the continuity between part 1's last frame and part 3's first frame is not
covered if part 2 is genuinely missing. Any row that depends on the transition
(S13 approach → S14 zipwire → S17 overlook → S21 doors → S24 foyer) must be
checked against part 1's second half and part 3 before being called reachable.
This lane does **not** claim those beats are absent from the recording — only
from 0–300 s.

### 6.2 Ambiguities recorded

1. **Different mission.** `Item Collection Heist` / 120 minutes / Staff of
   Edinburgh gems, not `Cleanout Heist` / 55 minutes / 4,000 loot. The spawn,
   letter, HUD tracker, pause-footer seed (`701694559`) and probably guard/loot
   placement follow from the choice. A row scored against the official
   safe-room alley or the official briefing copy must carry this caveat; the
   Den-side rows are unaffected (the save state matches KF07 exactly).
2. **No main menu / Den entry.** S01–S03 are absent because the recording starts
   mid-Den, not because the shipped game lacks them.
3. **Order differs.** S07's decoration station is played before S06, and S04 is
   played after S06/S05 — the same stations, a different order.
4. **The `gate` pose is a judgement call.** The 04:07 view is a street-side
   approach to a Guildhall perimeter gate, which is why it is `partial` rather
   than `absent`; the KF16 arch, car, guard and ZipWire are all missing.
5. **Prompt legibility.** The proxy is 480×270 and 1 fps. Small prompts
   (`[F] TURN ON` at the gramophone, the loading spinner ring) cannot be read or
   may fall between samples; those details are marked unverified rather than
   guessed.
6. **Timing tolerance.** The 60 fps recorder log reports `dup=1961 drop=1955`
   over 36,000 frames, and the 1 fps proxy samples one frame per second, so
   proxy times are ±1 s and transient events can be missed.
7. **Pause menu is not the route's end.** KF30's modal is present at 04:14 as a
   settings detour; its seed and backdrop differ, and no quit occurs.
8. **No audio.** AU rows are outside this lane's evidence; nothing here should
   be read as an audio-presence claim (e.g. the gramophone's music is unverified).
9. **Full-res candidates are stills.** `r1_full_*` frames were extracted from the
   26 GB original only at t=210, 235, 247, 254; all other evidence is the 480p
   proxy as instructed.

---

## 7. Limitations

- Visual presence only; no PASS/DELTA, no row score, no pixel/ROI measurement.
- One 300 s window of one owner session; not a route run and not reproducible
  from the port.
- The mission is not the official one, so several "absent" verdicts describe a
  **route choice**, not a shipped-game or port defect.
- The 1 fps proxy cannot show motion-dependent subjects (walk cadence,
  zipwire travel, scripted pans, hard cuts) — those rows are excluded rather
  than inferred.
- Motion Blur is **ON** in the capture (`live-ref-review-plan.md` §1.3), so
  moving frames are blurred; every legibility claim here comes from a hold or a
  near-still frame.
- Keyframes were compared at 480p (proxy) and 2560×1440 (four candidates);
  JPEG keyframes are 1920×1080. Composition differences smaller than that are
  not claimed.
- No claim is made about 300–600 s, the missing part 2, or part 3.

---

## 8. Evidence frames

Directory: `~/Videos/tat2_ref_20261127/review/` (outside git; not committed).
All proxy frames are **480×270**; the four `r1_full_*` are **2560×1440**.
Filenames follow this lane's `r1_<id>_<t>.png` convention; the review plan's
`r1_Sxx_p1_ssss.png` form maps directly (e.g. `r1_s05_telescope_057.png` is
p1 00:57).

| File | Proxy t | Backs |
|---|---|---|
| `r1_start_den_000.png` | 00:00 | S01/S02 absence, S03 partial, S07 station |
| `r1_s06_journal_010.png` | 00:10 | S06 journal |
| `r1_s06_ledger_prompt_005.png` | 00:05 | S05→S06 desk station (`[F] READ LEDGER`) |
| `r1_s06_blackmarket_026.png` | 00:26 | S06 black market |
| `r1_s05_telescope_057.png` | 00:57 | S05 telescope (KF05) |
| `r1_s04_loadout_prompt_084.png` | 01:24 | S03 station prompt / S04 approach |
| `r1_s04_wardrobe_kf03_086.png` | 01:26 | S04 (KF03 state) |
| `r1_s04_wardrobe_kf04_122.png` | 02:02 | S04 (KF04 state) |
| `r1_s07_gramophone_180.png` | 03:00 | S07 gramophone |
| `r1_s05_posters_189.png` | 03:09 | S05 posters (KF06) |
| `r1_s08_maptable_194.png` | 03:14 | S08 map table (KF10) |
| `r1_s08_confirm_195.png` | 03:15 | S08 confirm modal |
| `r1_s10_mapload_196.png` | 03:16 | S02-art loading before prep |
| `r1_s09_prep_210.png` | 03:30 | S09 prep (different mission) |
| `r1_s09_countdown_213.png` | 03:33 | S09 countdown |
| `r1_s10_loading2_225.png` | 03:45 | S10 loading (KF12) |
| `r1_s11_letter_235.png` | 03:55 | S11 letter (different copy) |
| `r1_s12_spawn_241.png` | 04:01 | S12 absence / outdoor spawn |
| `r1_s13_street_242.png` | 04:02 | S13 street |
| `r1_s13_guildhall_side_247.png` | 04:07 | S13 / `gate` pose |
| `r1_s13_barrels_251.png` | 04:11 | S13 corner / `MACLEOD` |
| `r1_s27_pause_254.png` | 04:14 | S27 modal (mid-route) |
| `r1_ui5_noise_arcs_284.png` | 04:44 | UI5-01 / UI3-05 |
| `r1_s13_walkway_290.png` | 04:50 | S13 walkway |
| `r1_end_outside_299.png` | 04:59 | segment boundary (still outside) |
| `r1_full_prep_210.png` | 03:30 | full-res prep text |
| `r1_full_letter_235.png` | 03:55 | full-res letter text |
| `r1_full_guildhall_247.png` | 04:07 | full-res gate/side view |
| `r1_full_pause_254.png` | 04:14 | full-res pause footer |

Extraction command used for every proxy frame:

```bash
ffmpeg -ss <t> -i ~/Videos/tat2_ref_20261127/review/route_lossless_1fps.mp4 \
  -frames:v 1 -y ~/Videos/tat2_ref_20261127/review/r1_<id>_<t>.png
```

Full-res candidates:

```bash
ffmpeg -ss <t> -i ~/Videos/tat2_ref_20261127/route_lossless.mkv \
  -frames:v 1 -y ~/Videos/tat2_ref_20261127/review/r1_full_<id>_<t>.png
```
