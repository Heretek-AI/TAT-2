# R8 — the recorded run (2026-11-24), reviewed against the official clip

**Date:** 2026-11-25 · **Capture:** `/home/john/Videos/2026-11-24 22-47-16.mp4` — 281.333 s,
3840×2160 @ 30 fps, 8 440 frames, h264 8.08 Mbit/s, AAC 48 kHz. Session log
`godot2026-11-24T22.47.10.log` (168 lines, ends `TAT-2 mission_ready map=guildhall meshes=62950`).
**Reference:** `docs/reference/clip_1795033698901/` (30 keyframes), `docs/REFERENCE_BASELINE.md` §8–§10.
**Inputs:** `ADJUDICATIONS.md` (binding), the two F1 adjudications, `kf_presence.md`, `row_route_matrix.md`,
the five L lanes and the five C lanes. **Companion:** `docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md`
— the filled 120-row scorecard; every tally here is derivable from its §2 and §5.

It adds no measurement except where it says so; it states what this run proves, what it
cannot, and which review claims survived adjudication. (Chain re-audit: `re-audit-20261124.md`.)

---

## 1. What was captured

One Novice, solo deployment of `Mission.Guildhall.LootTheRoom` hosting `Contract.Main.2`, *Into the
Lion's Den*, `free_play=false`. The player starts at the front end, visits the Den, uses the telescope,
ends up on the Den roof, recovers the hub through the startscreen, re-enters, selects the contract,
prepares, loads into the Guildhall, crosses a street and a roofline, picks a door, opens a display safe,
takes a `Cat Statue`, picks two more locks (the last aborted), crosses ten near-black seconds, and stops
in the pause menu. The objective is never completed and nothing is banked.

The first segment map was wrong in ways that change scoring. The corrected map (W0b, cross-checked with
L1/L3/L4) is:

| Port time | What is actually on screen | Proof |
|---|---|---|
| 00:00–00:01 | Godot boot splash, not the startscreen | f_0001 |
| 00:01–00:08 | startscreen, `Mac Neish` neon, `PLAY/SETTINGS/CREDITS/QUIT` | f_0002 |
| 00:08–00:13 | loading #1 | f_0009 |
| 00:13–00:24 | Den: map card 00:13, armoire 00:16–18, telescope 00:19–21, sky cut 00:22.1–23.2 | f_0014, f_0018, f_0020, f_0023 |
| 00:24–00:41 | **outside on the Den's plank roof** (the hub escape) | f_0026, f_0036 |
| 00:41–00:48 | pause over the roof; `RETURN TO THIEF'S DEN` selected at 00:48.6 | f_0043 |
| 00:49–00:51 | startscreen — the return lands here, not in the Den | f_0050 |
| 00:51–00:56 | loading #2 | f_0052 |
| 00:56–01:02 | 3D map table + `CONSTABLES' GUILDHALL` card | f_0060 |
| 01:02–01:10 | 2D `MAP TABLE — CONTRACT SELECTOR` + confirm modal | f_0063, f_0067 |
| 01:10–01:20 | `MISSION PREPARATION`, countdown 6→1 | f_0072, f_0076, f_0079 |
| 01:21–01:39 | loading #4 — **18.8 s** | f_0082…f_0099 |
| 01:39–01:41 | briefing letter (5-line override, no backdrop) | f_0100, f_0101 |
| 01:41–01:43 | safe-room spawn facing a brick wall | f_0102 |
| 01:43–01:59 | street + perimeter wall/fence; blank white sign at 01:59 | f_0106, f_0110, f_0121 |
| 02:00–02:41 | rooftops: zipwire launch 02:01, crank 02:12–02:19; exterior stairs down 02:36–02:41 | f_0122, f_0136, f_0159 |
| 02:42–02:51 | timber door + `DOOR LOCK (LV 3)`; the dialog closes, then the door beat follows | f_0163, f_0166, f_0170 |
| 02:51–03:08 | checkered marble hall; `[F] OPEN`/`[F] [HOLD] LOCK` → `[F] CLOSE` 02:51–02:53 | f_0172, f_0174 |
| 03:09–03:20 | library/study; ward pane 03:10–03:13 | f_0190, f_0192 |
| 03:21–03:41 | `DISPLAY SAFE (LV 2)`, `Cat Statue`, `£0→£225` at 03:40.8–03:41.4 | f_0202, f_0204, f_0221 |
| 03:42–03:50 | `DOOR LOCK (LV 3)` #2 | f_0222, f_0226 |
| 03:51–04:14 | white cabinets; `DOOR LOCK (LV 4)` at 04:12, aborted by `[ESC]` | f_0235, f_0253 |
| 04:20–04:26 | ward pane #2; statuary, busts, backlit glass case | f_0260, f_0265, f_0267 |
| 04:27–04:37 | **near-black render with a fully lit HUD**, not a fade | f_0270…f_0277 |
| 04:38–04:41 | pause modal; run ends, no quit | f_0279 |

Two corrections are load-bearing. The Den is eleven seconds of interior, not thirty-four: the player
leaves through the ceiling at 00:26, which is why the wardrobe, ledger, black-market and gramophone
keyframes (KF03/04/07/08/09) are unreachable. And 00:41–00:48 is the pause modal, not a loading screen;
the mapped "45–48 s loading" does not exist.

**Absent.** No NPC of any kind — guard, constable, civilian, patrol, turret, camera or beam — in 281 s.
No smoke bomb, no vintage car, no Vistara Diamond, no escape portal, no endgame, no payout, no
hearth/parlor, no foyer beam, no crimson alarm, no wardrobe/ledger overlay.

**Present, against the brief.** A ZipWire: equipped by 01:45, fired at 02:01 (f_0122: 1P arm raised,
roofs below), cranked 02:12–02:19 (f_0136: segmented ring, `[RMB] CRANK`, hand on the line). L5's
reconstruction says "no zipwire"; the frames and three lanes disagree. What is missing is the
*traversal* — no taut cable, no cable crossing, no courtyard descent — which moves two audio rows
(AU3-05, AU5-02) from "unreachable" to "unverified".

---

## 2. Method, and its honesty

**The pipeline is validated, not assumed.** The 2D loading illustration is the same art on both sides, so
it controls the whole path: port mean 20.6/20.6/20.5 at t=11/54/90, `p50 14`, `p95 73`; official `KF12`
mean 20.1, `p50 14`, `p95 71` — within 3 %. The black crush in 3D scenes is therefore the renderer, not
the recording. A second control is the Den: `p50 17` matches `KF02`'s 18, so the renderer *can* hit the
authored level and does not in the Guildhall.

**Text only from native crops.** A contact-sheet cell is 640×360 — a 6× downscale of a 4–5 px font —
evidence for layout, never for text. Every string here was read at 1:1 from a `frames_client`/master
crop, by this review or by an adjudicator who quoted the crop. Sheet labels carry a measured +0.9 s
offset (`S+HH:MM:SS` shows master `S+HH:MM:SS+0.9`).

**Audio verdicts are gain-invariant.** The capture is 27.4 dB hot against the official (−16.5 vs
−43.9 LUFS) with compressed dynamics (LRA 5.5 vs 16.7 LU), so no absolute dB comparison is a mix verdict.
Spectral content, silence, harmonic structure, transient census and within-file contrast carry the scores;
level deltas are provisional. That is why no audio row is scored `MISSING` on level alone.

**Three false readings this review carried and retracted.**

1. **The frozen clock.** It ticks 1:1: Δ42 s over 42 s (f_0168→f_0210), Δ30 s over 30 s
   (f_0210→f_0240), 50 s over 50 s (L4-04). The digits only *look* frozen because a second draw
   overprints the row; the reading came from an italic 14 px glyph sampled at 1 fps.
2. **`UNADVY`.** Does not exist. The prep label is clean `UNREADY` at 1:1 (f_0076/f_0077), the string
   occurs zero times in the tree, and the code emits `UNREADY` while the countdown runs
   (`mission_prep_ui.gd:1312`). It was a 4 px sheet mis-read.
3. **The missing-texture magenta.** The violet doorway plane was attributed in turn to a missing texture,
   to `SM_WardBox` with `WorldGridMaterial`, and to a fallback crate-stencil albedo. All three are wrong:
   it is `tat_ward.gdshader` on the ward-zone device's `WardVisual` box, `unshaded + blend_mix`, at both
   sites (F1a C-2). Evidence: constant G/R 0.766 across a 1.4× brightness range; a 24.5 px facet pitch
   converting to 0.12–0.18 m against the shader's `1/5.5 = 0.182 m` cell and the authored 3.5 m box; and
   the elimination of `SM_WardBox` (skipped at `level_loader.gd:2577` since `32fe554`) and of the
   WorldGrid albedo (red/cyan 2×2 checker, sd 0.393).

Two more corrections shaped the verdicts. **The contact sheets are not another build** (F1a C-1): a
label-free re-extraction reproduces them at 0.55–0.81 % RMSE against a 0.28–0.61 % resampler floor, while
the only other recording on disk scores 24.5 %. L4's "different build" finding is `NOT REPRODUCED`; the
real defect behind it — two door classes printing `[E]` and `[F]` — is authored (`lockable_door.gd:316`,
`swinging_door.gd:250`). And **the HUD bracket is `[0/1]`** (F1b C-1): contract 2 authors one objective
row, the header prints `done/rows`, a localised NCC ranks `[0/1]` first (0.6145) and `[0/11]` last
(0.5164), and my own crop of f_0250 shows `[0/` + a smeared `1]`. Three lanes read three different digits.

**What the method cannot do.** A 1 fps set cannot exclude sub-second flicker (V1-01), resolve a
1.000 s tick train against a loud bed (AU4-04), or demonstrate an arc-size change (UI5-01): those are
`UNVERIFIED`, with the experiment named. Frame rate is not measurable from a CFR capture.

---

## 3. The five findings that matter

### 3.1 The Guildhall is lit by 16 % of its authored lights, at a fixed exposure, with no GI or IBL

The load set authors **976** point/spot records across the eight sublevels C1 counted, plus 17 RectLights;
my own count over every `Guildhall*` level file is 982 + 17 = **999**, the six extra sitting in two facade
sublevels outside the load set. The runtime instantiates `total=160 (generic=159 rect=1) budget=159` —
**159 of 976 = 16.3 %**. Selection is by authored energy then spawn proximity, never by room: rank 159 is
authored energy 25.0 (138 brighter, 50 at exactly 25.0 with 29 losing the tie-break; 659 below 20 lumens,
138 below 1.0). Every sub-25-lumen practical dies unless it is within 25 m of a player spawn
(`level_loader.gd:4445-4478`, `:5460-5469`).

The exposure lift written for this map never runs. `weather_profile.gd:768-772` applies
`NIGHT_EXPOSURE = 1.15` only for `midnight_clear`; `map_weather.json` resolves `guildhall → gloomy`, so
the map runs AGX at `tonemap_exposure = 1.0` — the configuration its own comment calls crushed black.
The Guildhall also has **zero** authored PostProcessVolumes in its 16-file load set, so the stand-ins for
UE's local exposure and skylight leak (`level_loader.gd:5233-5286`) never execute; there is no SSAO,
SDFGI or VoxelGI, only SSIL, which cannot bounce radiance that is not in frame. Ambient is a constant
0.16 white with `ambient_light_sky_contribution = 0.0`, while the shipped `gloomy` preset lights from a
specified cubemap at intensity 2.0 (C5-01) — the authored IBL is unused.

Measured: interiors at `p50 2–8` with **47.7–78.4 %** of pixels below 8/255, against 9.4–23.5 % in
official frames of the same room kinds; the darkest second (t=123) has 91.8 % of 8.03 M pixels at or below
7/255. The Den, with hand fills and its own practicals, reaches the official median, so this is not a
global exposure constant. One correction: L1-13 read a logged `ambient_energy=0.08` as the Guildhall
inheriting the Den preset, but C1 §0(a) shows that line is a Den load; the Guildhall is `0.16 / fog
0.0048`, i.e. `gloomy`. The preset is right; the exposure and the budget are not. **Owner: T07-RENDER**
(C1-01/02 P0; C1-03/05 P1). Budget and exposure come before any material or grade work.

### 3.2 The prep regression is one camera value

The stage is the run's most visible regression: the thief stands against a flat blue-violet field with
her soles cropped by the frame bottom, and one near-black mass fills the left two-thirds where the
official shows a lit roof, a balustrade, a chimney jumble and a clocktower.

The authored `CameraActor_0` (`MissionLobby_Geo3`) is at `(12.6065, −0.16698, −1.05384)` m with pitch
6.685°, yaw 173.186°, roll −14.780°, FOV 20.0 **horizontal** (11.33° vertical at 16:9). The port uses
`LOBBY_CAM_POS = (4.0, 1.0, 10.0)` and a forward vector rotated 55.5° from the authored one — **14.06 m
away and 69.06° off**. `7128d43` is primary; `6760dd0` then moved the thief 1.26 m, perpendicular to the
new view axis (≈0.32 m of screen drop at the roll), which is real but secondary. L3's "camera is
byte-identical" is a diff-range artefact: the range starts after the change, and `git log -S` shows the
new vector only in `7128d43`.

The expansion skyline does not rescue it. All eight pieces are placed (`placed 8/8`), but every azimuth
lies within ±11° of the lens centre (the frame is ±10°), their 310–500 m standoff and 1.0–1.7 scale make
`mid_roofline_a` span ≈67 % of the frame height, and `_grade_skyline_material` sets
`disable_ambient_light = true`, `emission_enabled = false` and a dark albedo while the only light that
reaches them is aimed from behind.
They can only render as black silhouettes against a black mass. The sky compounds it: `cloud_color
(0.1277, 0.4162, 1.0)` at `cloud_opacity 3.299` gives the azure, `moon.color (0.2604, 0.4038, 1.0)` the
violet disc, and the warm counter-term is gated on `_is_midnight_clear`, which no map resolves to.
**Owner: T05-UI** for camera and placement, then **T07-RENDER** for the grade (F1b C-3's order).
`build/qa/vf_mission_prep.png` is the pre-regression frame.

### 3.3 The HUD health bar is the wrong composition, and something draws it twice

The framed top-left element is the health bar. The authored
`T_healthBar_straight_frame.png` is exactly **1024×256**, and `hud.gd:1019` stretches it to `256×62` over
a flat `204×20` `ColorRect` (`0.64,0.12,0.12,0.96`) with `T_healthBar_splatter_red.png` bound
**permanently** (`hud.gd:1005`, no fade logic). The authored shaped fill, `T_healthBar_straight_RGB.png`,
is never loaded. The widget renders at ~30 native px — **37 %** of the authored height (10 px at 720p vs
26.7 px in KF19) — so the filigree reads as a smear. The mission text below has no frame — C5 was right
about that — and the two were never the same element.

The duplication is real: a horizontally compressed second copy of the frame sits left of the pointed
right cap, the objective line is overprinted with itself, and `[HOLD] PIN MENU` has `MMB` through it. My
own crop of f_0270 shows both. There is exactly one `HudScript` and one `hp_frame`
(`mission_controller.gd:155-156`, `hud.gd:1023`), so this is a second *draw*, not a second HUD; the
drawing node is unidentified. **Owner: T05-UI.** Composition is local (`hud.gd:997-1023`); the
duplication needs F1a C-4's experiment — instrument `_ready`/`add_child` counts, plus a lossless
in-engine crop so the 2.9× canvas upscale can be excluded.

### 3.4 The blackjack/detection race (a chain finding this run cannot show)

No NPC appears, so none of this is in the recording. It matters because it makes the stealth loop
unwinnable, and a run that never meets a guard cannot refute it.

The shipped `AIC_GuardBase` authors `MinimumSightRadius 1.0 m`: a guard sees a target inside 1 m
regardless of facing. The port sees it inside **3.5 m** (`guard_ai.gd:1479`) and its ramp returns `INF`
at ≤2.0 m (`guard_ai.gd:1095-1096`); the light curve floors effective range at `0.15 × sight`, so even on
the harshest difficulty it sees ≈2.55 m. The blackjack reach is **2.4 m** (`thief_character.gd:2733`).
At 2.4 m the ramp runs ≈**104 points/s**: SUSPICIOUS in ~0.14 s, ALERTED in ~0.43 s — while the takedown
needs a **0.45 s hold** (`HOLD_INTERACT_SEC`). The ramp wins, and `GameState.ever_spotted` is set at the
45-point step, forfeiting the GHOST bonus. Inside 2 m, `INF` goes straight to COMBAT. Derived from data
and code, not runtime-verified (RE-I-02, P2). It is in the five because it is the largest gap between
"systems exist" and "loop is playable", and no gate sees it: the takedown suite freezes physics and calls
`_try_blackjack` directly. **Owner: T11-AI**, with T04-ANIM for the rig and T10-GAMEPLAY for the hold.
Experiment: a live-physics takedown at 2.0–2.4 m behind a guard, with the ramp logged.

### 3.5 What is not broken: the loot and objective core

The run's most important negative result is that the suspected parts are correct.

- **`[0/1]` is right.** `Contract.Main.2` authors `kind: single` with one item;
  `mission_controller.gd:2665-2667` builds one row; `hud.gd:2488` prints `done/size` plus a `❧` sub-line.
  The free-play `[0/4,000]` counter is real but belongs to the other branch (`hud.gd:2453-2467`).
  `[0/11]`, `[0/9]`, `[0/4]` are misreads. T10 must not "fix" it.
- **The clock is 1:1 on the mission row.** 3300 s at Novice, measured 42 s/42 s and 30 s/30 s. The endgame
  window is **1200 s at every difficulty** by the KF13 override (authored QG 480 s); the shipped ini
  ladder 1200/600/300 is real but unread. The 1200 is correct; the ladder is inert.
- **The pickup works.** `DISPLAY SAFE (LV 2)` opens, the case reads `OPENED`, the statue carries
  `[F] STEAL CAT STATUE`, and `(£)` goes **0 → 225** at 220.5–221.5 s. 225 is authored; the 3-slot cost
  is the documented port decision (authored rows cost 1).
- **The counter not moving is correct.** The objective is the Vistara Files, 90.7 m away on
  `Guildhall_Contract_02`; the Cat Statue only feeds `loot_value`, and this contract path returns an empty
  plan so `loot_goal` is 0.
- **Endgame, `TIME EXPIRED` and payout are `N/A-route`**, not broken: a run that never completes the
  objective never leaves `phase = main`.

**Owner: none.**

---

## 4. Every P0/P1 across L1–L5 and C1–C5

Duplicates are merged, ids listed. Status is the review's adjudicated state, not a team's later fix
status.

| ID | Sev | Finding | Evidence pointer | Team | Status |
|---|---|---|---|---|---|
| C1-01 | P0 | 159 of 976 lights instantiated; rank-159 cut at authored energy 25.0; selection by energy + spawn proximity, not room | log `total=160 budget=159`; C1-01 | T07-RENDER | CONFIRMED |
| C1-02 | P0 | AGX `NIGHT_EXPOSURE 1.15` scoped to `midnight_clear`, which no map resolves to; Guildhall runs `gloomy` at exposure 1.0 | `weather_profile.gd:768-772`; `map_weather.json` | T07-RENDER | CONFIRMED |
| L3-01 / C3-01 | P0 | Prep thief floats, soles cropped, no rooftop | f_0072/f_0078; `vf_mission_prep.png` | T05-UI | MERGED, CONFIRMED |
| L3-02 | P0 | Prep backdrop is one near-black mass + one spire; skyline cannot read | f_0072; C1-08 | T05-UI (+T07) | CONFIRMED |
| L1-01 | P1 | Mission-wide underexposure: 47.7–78.4 % of pixels < 8/255 vs 9.4–23.5 % | L1 §2; f_0111/f_0242/f_0256 | T07-RENDER | CONFIRMED |
| C1-03 | P1 | No GI; zero authored PP volumes in the load set, so no leak fill or exposure LUT | `level_loader.gd:5233-5286`; 16 files `post_process: []` | T07-RENDER | CONFIRMED |
| C1-04 | P1 | `_is_midnight_clear` exact-matches an id no map resolves to; documented sky/fog calibration dead | `weather_visuals.gd:249-250, 403-423` | T07-RENDER | CONFIRMED |
| C1-05 | P1 | Ambient is the only fill, at an outdoor-calibrated 0.16 with sky contribution 0 | `weather_profile.gd:723-735`; L1 §1 | T07-RENDER | CONFIRMED constant; P0 if probe |
| C1-08 | P1 | Skyline placed 8/8 but fills two-thirds of an 11.33° frame, graded to black | `mission_prep_ui.gd:886-910`; C1-08 | T05-UI | CONFIRMED |
| L1-02 | P1 | Violet doorway plane | F1a C-2: `tat_ward.gdshader` on the ward-zone box | T08-MATERIAL | RECLASSIFIED |
| L3-03 | P1 | Prep sky azure, moon violet; cloud layer floods at >1 opacity | f_0072 vs KF11; `midnight_clear_mission_lobby.json` | T07-RENDER | CONFIRMED |
| L3-04 / C3-04 | P1 | No warm rim: 1.8 blue ambient against a 0.32 warm fill | `mission_prep_ui.gd:683-687, 767` | T05-UI | MERGED, CONFIRMED |
| L3-13 / C3-08 | P1 | HP bar: rect fill under slanted 1024×256 frame, permanent splatter, 37 % height, drawn twice | `hud.gd:997-1023`; f_0195/f_0250/f_0270 | T05-UI | MERGED, CONFIRMED (cause undetermined) |
| L2-08 | P1 | Prep avatar red-coral head, near-white trousers; HUD portrait and 1P forearm share the tone | f_0074; head/body atlas means | T08-MATERIAL | CONFIRMED (visual) |
| C2-01 | P1 | Loot/quest props never enter the material pipeline — raw GLB, white default | `loot_item.gd:159-177`; f_0207 probe | T10-GAMEPLAY (+T08) | CONFIRMED |
| C2-02 | P1 | HDR emissive `Color` accepted as albedo tint (`MI_CatStatueA` 600/98.98/0) | `materials.json`; `parse_materials.py:731-764` | T08-MATERIAL | CONFIRMED |
| C2-03 | P1 | Ward family mis-bound; 82 `SM_SlowWardZone_Quad` bind a 0.176-alpha crate stencil | C2-03; F1a C-2 | T08-MATERIAL | RECLASSIFIED (P2 remains) |
| L4-01 | P1 | Health drains inside a lockpick with no damage source; first reveal ≈75 %, down to 38 % | f_0165/f_0166; L4-01 | T10-GAMEPLAY | CONFIRMED (timing) |
| L4-03 | P1 | `[ESC]` in the LV4 lock opens pause and loses the lock; door stays locked | master 253.4–254.6; L4-03 | T05-UI + T06-INPUT | CONFIRMED |
| L4-08 | P1 cand. | No guard, civilian, turret, camera or beam visible in 6 min (4 guards, 3 civilians, nearest 48 m) | all frames; C4-08 | T10-GAMEPLAY + T11-AI | CONFIRMED visible; spawn open |
| L4-13 | P1 | After `[F] EXIT` the player is outside on the Den roof; hub recovered only via the startscreen | master 26.0–38.5; f_0026/f_0036 | T10-GAMEPLAY | CONFIRMED (position) |
| C3-10 | P1 | `RETURN TO THIEF'S DEN` is wired to `main_menu.tscn`; bypasses the payout | `hud.gd:1839-1846`; master 48.6→49.0 | T05-UI | CONFIRMED |
| L5-01 | P1 | Startscreen bed is music-like, ≈+30 dB over the project's own rain target | L5-01; 69 % harmonic frames | T03-AUDIO | CONFIRMED (content) |
| L5-02 | P1 | Loading has no digital silence: 0 exact-zero samples in 19 s | L5-02; `silencedetect` | T03-AUDIO | CONFIRMED |
| L3-05 | P1 | Regression proof: the 11-23 capture shows the thief on a lit ledge | `vf_mission_prep.png` vs f_0072 | T05-UI | MERGED into L3-01 |

Twenty-five P0/P1 rows, twenty-one distinct defects: four are duplicates (L3-01≡C3-01, L3-04≡C3-04,
L3-13≡C3-08, L3-05≡L3-01) and two are reclassifications where adjudication changed the object, not the
severity (L1-02, C2-03). Nothing P0/P1 was dropped; the closed "sheets from another build" claim was P2
(`NOT REPRODUCED`, §2).

---

## 5. What this route cannot answer, and the second capture

**57 of 120 rows are `N/A-route`** — not failures, not scored. The absence is structural:

- **No NPC (19 rows).** Every guard, pickpocket, takedown, alert, bark and scan row needs the populated
  route (S13–S26 / KF16, KF18–KF26). The port spawned 4 guards and 3 civilians at 48–151 m (C4-08); the
  route never crosses them.
- **No endgame (4 rows).** No portal, ward shatter, crimson alarm, `TIME EXPIRED` or payout; the run never
  completes `[0/1]`.
- **No hub content (10 rows).** The Den roof escape at 00:26 costs the wardrobe, ledger, black market and
  gramophone — unreachable *because of a P1 defect*, not player choice.
- **Other unreached rooms and beats (24 rows).** Car, gate arch, `MACLEOD` facade, blue doors, hearth,
  slate stairs, smoke bomb, Vistara, beams, takedown camera.

The scorecard records each absence with the `Snn`/`KFnn` needed, so a future scorer sees which keyframe
makes the row live. The total is 57, not the matrix's 56: four rows it calls partly observable never show
their subject (V3-02, AU3-03, G2-02, G2-05) while three it calls unreachable are reachable (V6-04, AU5-05,
AU5-07). The reconciliation is in the scorecard's §5.

**The second capture.** One run on the same build that (a) stays inside the Den until the wardrobe, ledger
and gramophone are opened, (b) follows the official gate/courtyard route rather than the rooftop cut,
(c) meets a guard and performs one rear takedown with physics live, (d) throws the smoke bomb and uses the
Vistara scan, (e) crosses the foyer beam to trigger the ward lockdown, and (f) completes the Vistara Files
objective and escapes through a summoned door — with the clock allowed past 240 s in the endgame so
C4-03's portal trap is confirmed or retired. Method: OBS audio filters off, fixed in-game master (L5-03);
0.2 s or lossless HUD sampling (C3-15, C4-15); F3 plus a 5 s position log (C4-10, L2); one Vulkan run at
a time under Xvfb. A capture at mission start would also settle whether the main window is 3300 s (mission
row) or 1320 s (quest-graph `MatchMainPhaseDuration`) — the authored values disagree.

---

## 6. The one-paragraph version

The port got the *systems* right and the *light* wrong. The loot pickup and its authored value, the
`[0/1]` counter, the 1:1 clock, the 3300 s main window, the 1200 s endgame override, the telescope, the
ZipWire and the front-end flow all behaved as authored; the counter that looked broken was a misread, the
clock that looked frozen was not, and the violet panel that looked like a missing texture is the ward
shader doing what it was told. What the run proves is narrower and more serious: the Guildhall is lit by
16 % of its authored lights at a fixed exposure with no GI or IBL, so half of every interior frame sits on
the black floor; the prep stage lost its rooftop to a camera 14 m and 69° from the authored slot; and the
health bar is the wrong composition and is drawn twice by an unidentified node. The rest is a route that
never meets a guard, never completes the objective and never escapes — 57 of 120 official rows are
unanswerable here, not failed. The next capture should reach the rows this one cannot, with clean audio
and faster HUD sampling.
