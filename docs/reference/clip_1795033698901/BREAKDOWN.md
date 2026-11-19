# Exhaustive Timestamped Breakdown - `clip_1,795,033,698,901.mp4`

Continuous account from `00:00.00` to `03:45.64` with no gaps, built on the 27
segments `S01`-`S27` in `KEYFRAME_INDEX.md` section 2 (same ids and boundaries).
Every claim below is visible in a frame or audible in the clip; the video wins
over any doc where they disagree.

## Clip metadata (from KEYFRAME_INDEX section 1)

| Property | Value |
|---|---|
| Source | `/home/john/Videos/clip_1,795,033,698,901.mp4` |
| Duration | `225.642333 s` (`03:45.64`) |
| Video | `3840x2160` H.264 High, `29.672 fps` avg, `6,696` frames |
| Audio | AAC LC `48 kHz` stereo, stream starts at `0.277 s` |
| Loudness | Integrated `-43.9 LUFS`, LRA `16.7 LU` |
| Game build | `1.5.148559` (`Novice`, seed `1025051536`, KF30 footer) |
| Keyframes | 30 clean `1920x1080` JPEGs in `clean/`, 30 annotated in `annotated/` |

## Contents

- S01 Startscreen through S11 Briefing letter (menus, Den hub, prep, loading)
- S12 Safe-room spawn through S19 Vistara Diamond (Guildhall approach)
- S20 Side wing through S27 Pause menu (infiltration, wards, alarm, quit)

```mermaid
flowchart LR
    S01["S01 Startscreen"] --> S02["S02 Loading 1"]
    S02 --> S03["S03 Den entry"]
    S03 --> S04["S04 (Wardrobe)"]
    S04 --> S05["S05 (Telescope / Wanted)"]
    S05 --> S06["S06 (Journal / Black Market)"]
    S06 --> S07["S07 (Gramophone)"]
    S07 --> S08["S08 Map Table"]
    S08 --> S09["S09 Mission Prep"]
    S09 --> S10["S10 Loading 2"]
    S10 --> S11["S11 Briefing letter"]
    S11 --> S12["S12 Safe room"]
    S12 --> S13["S13 Alley / car"]
    S13 --> S14["S14 1st zipwire"]
    S14 --> S15["S15 2nd zipwire"]
    S15 --> S16["S16 Roofline"]
    S16 --> S17["S17 Gate pillar"]
    S17 --> S18["S18 Smoke bomb"]
    S18 --> S19["S19 Vistara Diamond"]
    S19 --> S20["S20 Side wing"]
    S20 --> S21["S21 Blue doors"]
    S21 --> S22["S22 Pickpocket"]
    S22 --> S23["S23 Takedown"]
    S23 --> S24["S24 Foyer beams"]
    S24 --> S25["S25 Wards"]
    S25 --> S26["S26 Alarm stairs"]
    S26 --> S27["S27 Pause menu"]
```

Audio method: no listening was possible, so every audio claim below is phrased
from evidence - per-segment `astats` peak/RMS re-measured for this baseline
plus the verified KEYFRAME_INDEX section 4 cue table (bandpass-resolved VO,
dBFS peaks). Broadband noise bed = rain/wind; harmonic sustained bands =
music; sharp transients = clicks/footsteps/impacts (see spectrograms in
verification log). `UNCERTAIN:` marks anything not directly evidenced.

HUD glossary (used throughout): the bottom-center **Light Gem** (UI3) shows how
much light is on the player and from which direction (lit sector size = light
amount, position = direction; bright = exposed, dark = concealed); the **red
player-noise arcs** (UI5) flanking it show the player's own noise level
(size/brightness = loudness, absent = quiet). Neither element reflects guard
awareness - guard perception is shown separately (e.g. guard-alert direction pips).

Id namespaces: `S01`-`S27` are always clip-timeline segments (`KEYFRAME_INDEX.md`
section 2, the boundary authority). `S03`/`S04`/`S06a`/`S06b`/`S11`/`S14`/`S15b`
labels under `PG-2` (map_table, wardrobe, mission_prep, zipwire_crank,
guard_lantern_alert, lockpick) are port E2E test-scenario ids, never clip
segments; every `PG-n` in the parity columns is a parity-gap id (`PG-2` HUD
cards, `PG-5` tint/exposure, `PG-6` audio), not a test scenario.

## S01 - Startscreen (`MainMenu`) (`00:00.00`-`00:02.15`, `2.15 s`)

**Keyframes:** KF01 (`00:01.00`) [clean](clean/KF01_00m01s_startscreen.jpg) · [annotated](annotated/KF01_00m01s_startscreen.jpg) - see CALLOUT_LEGENDS.md#kf01

### Narrative
Static night street frames the main menu (`00:00.0`). The magenta `Mac Neish` / `Jeweller` neon flickers (dim at `00:00.10`, full-lit at `00:01.00`, left half off at `00:02.05`). The cursor drifts toward `PLAY` and clicks at `00:02.0`; the screen cuts to loading at `00:02.15`.

### Visual
- **Environment / geometry (V4):** Wet cobblestone street, storefront with Art Nouveau gold scrollwork, vintage car rear fender left, wooden crates right.
- **Lighting (V1):** Magenta cursive neon plus warm amber window/awning bars; upper-right streetlamp; puddle reflections.
- **Sky / atmosphere / weather (V2):** Night rain streaks over reflective cobbles (KF01#5).
- **Materials / shaders (V3):** Wet-stone specular response, glowing purple egg/orb in upper display (KF01#2).
- **Characters / animation (V5):** Stationary idle guard in uniform, helmet, brown belt before the shopfront (KF01#4).
- **VFX (V6):** None observed.
- **Camera / post (V7):** Locked-off wide shot; `CineCameraActor_0` framing per port (`-12.7196, 0.4566, 14.6089`, vFOV `48.03`).

### HUD / UI
- **Layout and state (UI1-UI5):** Right-aligned `THICK AS THIEVES` logo above `PLAY`, `SETTINGS`, `CREDITS`, `QUIT` (KF01#3, UI1). No persistent HUD yet.

### Gameplay and interactions
- Menu navigation only: cursor travel to `PLAY`, single confirm click at `00:02.0` (G5 transition to loading).

### Audio
| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `00:00.0-00:00.28` | AU1 | Digital silence | AAC starts at `0.277 s`; re-measured seg peak `-35.6 dBFS` |
| `00:00.3-00:01.9` | AU1 | Steady night rain hiss + distant street air | `-53 to -49 dBFS` RMS; **No BGM (explicit absence)** |
| `00:01.9-00:02.1` | AU4 | Crisp UI click (`PLAY`) | `pk=-33.4 dBFS` |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Startscreen street geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Neon tint / exposure | #8 | `APPROX_SHADER` | `PG-5` | `docs/HANDOFF_NEXT_SESSION.md:115` |
| Menu stack (PLAY/SETTINGS/CREDITS/QUIT) | #15 | `1:1_MATCH` | - | `game/src/ui/main_menu.gd:314-332` |
| Rain bed, click, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |
| CineCamera framing | #9 | `1:1_MATCH` | - | `game/src/ui/main_menu.gd:12-19` |

### What to check in the port recording
- [V1] Magenta/amber neon legible with flicker states; `[UI1]` full 4-item menu stack right-aligned.
- [V2] Rain streaks and puddle reflections on cobbles.
- [AU1] Rain bed present with no BGM; `[AU4]` single click on PLAY.

## S02 - Loading Screen 1 (`00:02.15`-`00:02.60`, `0.45 s`)

**Keyframes:** none (see KF12 for identical layout) - [clean](clean/KF12_01m06s_loading_screen.jpg) · [annotated](annotated/KF12_01m06s_loading_screen.jpg)

### Narrative
Hard cut at `002.152s` to the illustrated Kilcairn skyline (`00:02.15`); the spinner turns over `LOADING...` until the Den fades in at `00:02.60`.

### Visual
- **Environment / geometry (V4):** Illustrated rooftop skyline, no 3D geometry.
- **Lighting (V1):** Twin yellow searchlight cones from dirigibles upper-left.
- **Sky / atmosphere / weather (V2):** Dark-indigo sky, textured pale full moon upper-right.
- **Materials / shaders (V3):** None observed (2D illustration).
- **Characters / animation (V5):** None observed.
- **VFX (V6):** Rotating cyan/white spinner ring.
- **Camera / post (V7):** Static full-screen illustration; gold `THICK AS THIEVES` emblem bottom-center.

### HUD / UI
- **Layout and state (UI1-UI5):** Centered spinner + `LOADING...` (UI4); emblem (UI4). No HUD.

### Gameplay and interactions
- Non-interactive transition (G5): rain ducks out, Den streams in.

### Audio
| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `00:02.2-00:02.4` | AU1 | Rain fades | to `-82.0 dBFS`; re-measured seg RMS `-63.2 dBFS` |
| `00:02.4-00:02.6` | AU1 | Digital zero | `-240.0 dBFS`; **no loading music (explicit absence)** |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Loading art + spinner | #15 | `1:1_MATCH` | - | `game/src/ui/loading_screen.gd:9-12` |
| Fade to digital zero, no music | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

### What to check in the port recording
- [UI4] Spinner ring + `LOADING...` + gold emblem layout.
- [AU1] Rain ducks to silence; no loading music.

## S03 - Thieves Den Initial Entry (`00:02.60`-`00:06.57`, `3.97 s`)

**Keyframes:** KF02 (`00:04.50`) [clean](clean/KF02_00m04s_den_entry.jpg) · [annotated](annotated/KF02_00m04s_den_entry.jpg) - see CALLOUT_LEGENDS.md#kf02

### Narrative
Dark fade-in at `002.604s` into the timber attic (`00:02.6`); player card and compass fade in by `002.703s`. The view pans low across floorboards and papers (`00:03.3-00:03.7`), rises past rafters to the candlelit desk (`00:04.50`), the open armoire (`00:05.55`), and stops at the mirror with `[F] CUSTOMIZE LOADOUT` (`00:06.05-00:06.53`).

### Visual
- **Environment / geometry (V4):** Timber attic, rafters, floorboards with scattered papers, candlelit rolltop desk, open armoire, `KILCAIRN` map table (KF02#5, KF02#6).
- **Lighting (V1):** Volumetric teal-cyan moonlight shaft through arched frosted window (KF02#1); warm candle points vs cool shaft.
- **Sky / atmosphere / weather (V2):** Interior haze in the shaft; night outside the glass.
- **Materials / shaders (V3):** Dark wood albedo, frosted-glass glow, paper decals.
- **Characters / animation (V5):** None observed (no NPC in frame).
- **VFX (V6):** Dust/shaft volumetrics.
- **Camera / post (V7):** Slow rising pan, low exposure adapting out of the fade.

### HUD / UI
- **Layout and state (UI1-UI5):** Top-right `Johnny Cipher` Spider card level `4` (KF02#2, UI3); subtle top-center compass `NW` (KF02#3, UI3); `[F] CUSTOMIZE LOADOUT` prompt at the mirror (UI2). Health Bar hidden (100% HP).

### Gameplay and interactions
- Free walk through the hub (G2): wooden-plank footsteps; approach Wardrobe station (G1, KF02#4).

### Audio
| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `00:02.60-00:04.20` | AU1 | Indoor room tone | `-76.3 to -73.1 dBFS` RMS; **no BGM** |
| `00:04.5-00:05.8` | AU3 | Hollow wooden-plank footsteps + cloth rustle | `pk=-27.9 dBFS`; re-measured seg peak `-28.4 dBFS` |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Den attic geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Moon shaft / bounce light | #6, #7 | `HARD_LIMIT (HL-7)` | `HL-7` | `docs/FIDELITY_GAPS.md:25` |
| Player card + compass | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Room tone, footsteps, no BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |
| Map table look-at card | #15, #17 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/HANDOFF_NEXT_SESSION.md:111` |

### What to check in the port recording
- [V1] Teal shaft vs warm candle pool; `[V4]` desk, armoire, map table readable in the dark.
- [UI3] Player card + compass fade in by `00:02.70`; `[UI2]` loadout prompt at mirror.
- [AU3] Wooden footsteps; `[AU1]` room tone, no BGM.

## S04 - Wardrobe UI (`00:06.57`-`00:18.24`, `11.67 s`)

**Keyframes:** KF03 (`00:07.00`) [clean](clean/KF03_00m07s_wardrobe_loadout.jpg) · [annotated](annotated/KF03_00m07s_wardrobe_loadout.jpg) - see CALLOUT_LEGENDS.md#kf03; KF04 (`00:16.50`) [clean](clean/KF04_00m16s_wardrobe_vistara_diamond.jpg) · [annotated](annotated/KF04_00m16s_wardrobe_vistara_diamond.jpg) - see CALLOUT_LEGENDS.md#kf04

### Narrative
The Wardrobe fades in (`006.574s`, full `006.644s`). The player browses the Zipwire tooltip (`00:07`), Head grid (`Bowler Hat`, `Cap`, `Bob Hair Style with Eyepatch`), Body (`Classic`), slots 1-4 with the `Signature Tools cannot be swapped out` notice, the expanded slot-3 tool row, the `Vistara Diamond` tooltip (`00:16.50`), and the `Pickpocket Fairy` (`AVAILABLE` at `00:17.40`), then closes (`018.203-018.269s`).

### Visual
- **Environment / geometry (V4):** Open wooden armoire interior with lamp, bottles, tools (KF03#5).
- **Lighting (V1):** Warm armoire lamp vs dark slate panel background.
- **Sky / atmosphere / weather (V2):** None observed (full-screen UI).
- **Materials / shaders (V3):** Tooltip card filigree, 3D item previews.
- **Characters / animation (V5):** 3D Spider turntable: bowler hat, yellow goggles, purple sweater (KF03#4); cap equipped by KF04 (KF04#4).
- **VFX (V6):** None observed.
- **Camera / post (V7):** Static panel; slow turntable rotation.

### HUD / UI
- **Layout and state (UI1-UI5):** `WARDROBE` header; `[Q]` `The Spider` (selected) vs `[E]` `The Chameleon` (`LOCKED`) (KF03#1, UI4); `Edit Loadout` slots 1-4 (KF03#2, UI4); tooltip card (KF03#3, UI4); `Head`/`Body`/`Calling Card` + `BACK [ESC]` (KF03#6, UI4); slot-3 drawer (KF04#1, UI4); `Vistara Diamond` card (KF04#3, UI4); synced Head preview (KF04#5, UI4). Verbatim tooltips per KEYFRAME_INDEX section 5.2.

### Gameplay and interactions
- Menu browsing (G5): hover ticks across slots/cosmetics; slot 1/4 locked (signature tools); slot 3 expands 4-tool row; no loadout change committed.

### Audio
| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `00:06.7` | AU4 | Wardrobe open latch/whoosh chime | `pk=-23.5 dBFS` |
| `00:08.9-00:16.2` | AU4 | Metallic hover and slot ticks (8 ticks) | `pk=-34.6 to -39.4 dBFS` |
| `00:17.9` | AU4 | Close tick/clack | `pk=-35.1 dBFS`; **no BGM throughout** |
| | | Re-measured seg peak `-23.7 dBFS`, RMS `-57.9 dBFS` (quiet panel) | |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Wardrobe panel + turntable | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Clipped controls (live parity fail) | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/HANDOFF_NEXT_SESSION.md:111` |
| Hover/slot ticks, no BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

### What to check in the port recording
- [UI4] Full panel: character switch, 4 slots, tooltip card, Head/Body/Calling Card, `BACK [ESC]`.
- [V5] Spider turntable with equipped cap synced to Head slot.
- [AU4] Open chime, browse ticks, close clack; no BGM.

## S05 - Thieves' Den Exploration (Telescope & Wanted Posters) (`00:18.24`-`00:26.58`, `8.34 s`)

**Keyframes:** KF05 (`00:20.80`) [clean](clean/KF05_00m20s_telescope_cheese_moon.jpg) · [annotated](annotated/KF05_00m20s_telescope_cheese_moon.jpg) - see CALLOUT_LEGENDS.md#kf05; KF06 (`00:24.60`) [clean](clean/KF06_00m24s_den_wanted_window.jpg) · [annotated](annotated/KF06_00m24s_den_wanted_window.jpg) - see CALLOUT_LEGENDS.md#kf06

### Narrative
Wardrobe closes back into the Den (`018.203-018.269s`); the player crosses the floorboards to the brass tripod telescope under the arched window (`[F] PONDER` at `00:19.5`). Activating it cuts (`00:20.23`) to the exterior rooftop view - dark Kilcairn chimney silhouettes, teal-blue night sky, bright full moon, and a giant rotating golden cheese wedge with three orbiting chunks (`[F] EXIT` centered, `00:20.23-00:21.74`; KF05 `00:20.80`). Cuts back at `00:21.77`; the player walks the right wall past the 5 framed `WANTED` posters (`00:21.8-00:25.2`; KF06 `00:24.60`), then turns to the candlelit rolltop desk (`[F] READ LEDGER` at `00:26.31-00:26.50`) as the Ledger opens into S06.

### Visual
- **Environment / geometry (V4):** Timber attic: brass tripod telescope, arched leaded-glass frosted window, wall fuse box with twin circular gauges, open armoire mirror, canvas-wrapped packages, 5 framed Wanted posters on the right wall, candlelit rolltop desk (KF05, KF06).
- **Lighting (V1):** Volumetric teal-cyan moonlight shaft through the frosted window (KF06#1) vs warm candle/desk lamp pools; dark adaptive exposure.
- **Sky / atmosphere / weather (V2):** Telescope view: cloudy teal-blue night sky, faint stars, crater-textured full moon upper-right (KF05#1).
- **Materials / shaders (V3):** Brass telescope specular, frosted leaded glass, aged parchment posters, dark wood albedo.
- **Characters / animation (V5):** None observed (no NPC in frame).
- **VFX (V6):** Giant rotating golden Pac-Man-shaped cheese wedge (`x=800..1154, y=342..689`) with 3 orbiting porous chunks (KF05#2, KF05#3) - sky easter-egg prop; no gameplay effect observed.
- **Camera / post (V7):** Free 1P pan; hard cut at `00:20.23` to the fixed telescope sky shot, cut back at `00:21.77`; exposure lifts in the sky view.

### HUD / UI
- **Layout and state (UI1-UI5):** UI3 top-right `Johnny Cipher` level `4` + top-center `NW` compass. UI2 `[F] PONDER` at the telescope station, centered `[F] EXIT` reticle in the sky view (KF05#4), `[F] READ LEDGER` at the desk (`00:26.31`). Wanted poster world text (V4) verbatim per KEYFRAME_INDEX 5.2 (KF06#5): `WANTED! / CAUTION / HIS HANDS ARE FAST`; `Have you seen this CHARMING MAN? / HE'S A THIEF`; `WANTED / See something suspicious? / TELL A CONSTABLE!`; `WANTED / £10000`; `REWARD / £5000`. No persistent mission HUD yet.

### Gameplay and interactions
- G1 telescope station (`[F] PONDER`, `00:19.5-00:20.2`) -> G5 scripted sky-view transition (`00:20.23-00:21.74`, `[F] EXIT`) -> hard cut back `00:21.77`.
- G2 Den walk across floorboards to the Wanted wall (`00:21.8-00:25.2`; wooden footsteps `00:23.1-00:23.9`).
- G1 candlelit desk station `[F] READ LEDGER` (`00:26.31-00:26.50`); Ledger open click `00:25.2` (`pk=-39.2 dBFS`), panel state from `00:26.58` (S06).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `00:18.24-00:19.5` | AU1 | Den room tone after the Wardrobe close | back to `-71.8 dBFS` room tone (KEYFRAME_INDEX §4); `astats.1s` window RMS `-69.69 dBFS` median |
| `00:19.6-00:21.9` | AU1 | Exterior rooftop wind whoosh swell (`[F] PONDER` telescope view) | rises to `-29.84 dBFS` peak in the `00:21.3` window (`astats.1s`); doc `pk=-29.8 dBFS` |
| `00:23.1-00:23.9` | AU3 | Wooden-plank footsteps (Wanted-wall approach) | `pk=-27.10 dBFS` at `00:23.74` (`astats.1s`); doc `pk=-27.1 dBFS` |
| `00:25.2` | AU4 | Ledger open click | `pk=-39.2 dBFS` (KEYFRAME_INDEX §4, `astats`) |
| `00:18.24-00:26.58` | AU1 | **Explicit BGM Absence:** zero background music score | room tone + wind + foley only (`showspectrumpic` shows no harmonic comb) |
|  |  | Re-measured segment peak / RMS | `-27.10 dBFS` / `-48.55 dBFS` (`astats`); `I=-44.0 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Den attic geometry (telescope, posters, desk) | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Moon shaft / bounce light | #6, #7 | `HARD_LIMIT (HL-7)` | `HL-7` | `docs/FIDELITY_GAPS.md:25` |
| Telescope scripted sky view (cut framing) | #9 | `1:1_MATCH` | - | `game/src/missions/mission_controller.gd:768-804` |
| Player card + compass | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Room tone, wind swell, no BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |

### What to check in the port recording
- [V1] Teal window shaft vs warm desk candles; `[V4]` fuse box, wrapped packages, poster wall readable in the dark.
- [V4] Cheese wedge + 3 orbiting chunks over the rooftops; `[V7]` hard cuts at `00:20.23` / `00:21.77`.
- [UI2] `[F] PONDER` -> `[F] EXIT` -> `[F] READ LEDGER` prompt chain; `[UI3]` `Johnny Cipher` `4` + `NW` compass.
- [AU1] Wind swell (`pk=-29.8 dBFS`) during the sky view only; `[AU3]` wooden footsteps; no BGM.
- [G1] Poster wall inspection then desk station entry at `00:26.31-00:26.50`.

## S06 - Ledger UI (`JOURNAL` & `BLACK MARKET`) (`00:26.58`-`00:38.17`, `11.59 s`)

**Keyframes:** KF07 (`00:27.00`) [clean](clean/KF07_00m27s_ledger_journal.jpg) · [annotated](annotated/KF07_00m27s_ledger_journal.jpg) - see CALLOUT_LEGENDS.md#kf07; KF08 (`00:28.50`) [clean](clean/KF08_00m28s_ledger_black_market.jpg) · [annotated](annotated/KF08_00m28s_ledger_black_market.jpg) - see CALLOUT_LEGENDS.md#kf08

### Narrative
The Ledger opens on `[Q] JOURNAL` (`00:26.58`): `Johnny Cipher`, `Level 4`, XP `94/500`, `Contract #1` (left-clipped, `Completed`), `Contract #2` (`Completed`, *Into the Lion’s Den*), `Contract #3` (`Active`, *In the Eye of the Beholder*) (KF07 `00:27.00`). Crossfades (`028.172-028.338s`) to `BLACK MARKET [E]` (`00:28.17-00:33.15`): `YOUR TOTAL ASSETS: (£) 26,275`, left preview card + `TOOLS` / `GUILD PERKS` / `SPIDER COSMETICS` / `CHAMELEON COSMETICS` tables (KF08 `00:28.50`); hovers `Zipwire`, `Master Thief Difficulty`, `Elway Manor`, `Mustache`, `Glasses`, `Thief Mask`, `Full Beard`, `Bowler Hat`, `Pickpocket Fairy`. Panel fades out at `00:33.10` (desk with `[F] READ LEDGER` visible by `00:33.15`), re-opens `JOURNAL` (`00:34.11-00:38.17`), browses, and closes.

### Visual
- **Environment / geometry (V4):** Full-screen panel over the Den; rolltop desk, open ledger and candelabra visible during the `00:33.15-00:34.10` gap.
- **Lighting (V1):** Dark slate UI backdrop with warm parchment glow; warm candle spill on the desk in the gap.
- **Sky / atmosphere / weather (V2):** None observed (full-screen UI).
- **Materials / shaders (V3):** Ornate card frames, teal XP bar `94/500`, gold `✓ PURCHASED` badge, pink padlock badges, scrollable table columns (KF07, KF08).
- **Characters / animation (V5):** 3D `Zipwire` grapple-gun and `Pickpocket Fairy` preview models in the left preview card (KF08#2); cosmetic face/hair thumbnails in the tables.
- **VFX (V6):** None observed.
- **Camera / post (V7):** Static full-screen panel; `028.172-028.338s` tab crossfade.

### HUD / UI
- **Layout and state (UI1-UI5):** UI4 verbatim per KEYFRAME_INDEX 5.2 (KF07, KF08): tabs `[Q] JOURNAL` / `BLACK MARKET [E]`; `Level 4`, `94/500`, `Johnny Cipher`; contracts `Completed`/`Active` - *Into the Lion’s Den*, *In the Eye of the Beholder* (full lore paragraphs per 5.2; Contract #1 left-clipped `...nd managed... The "Vistara... origins.`); `BACK [ESC]`. Black Market: `YOUR TOTAL ASSETS: (£) 26,275`; `TOOLS` (`Zipwire`, `Smoke Bomb`, `Pickpocket Fairy`, `Insult Fairy`, `Slither Sap`); `GUILD PERKS` (`Novice Difficulty`, `Thief Difficulty`, `Master Thief Difficulty`, `Constables' Guildhall`, `Elway Manor`, `The Spider`, `The Chameleon`); `SPIDER COSMETICS` / `CHAMELEON COSMETICS` with prices `7,500`, `5,000`, `2,500` and `🔒` badges; `✓ PURCHASED` on the `Zipwire` card; `Master Thief Difficulty` tooltip `Allows Missions to be taken at the hardest difficulty level. Provides a larger bonus to XP and monetary earnings. Unlocked in Contract 8.`; `Pickpocket Fairy` tooltip `People call any helpful magical tool a "fairy," but this one is more fae-like than some. Not strictly for picking pockets, it can also flip switches at a distance. Unlocked in Contract 3.`

### Gameplay and interactions
- G5 Ledger menu flow: open `00:26.58`, JOURNAL read (`00:26.58-00:28.15`), tab crossfade (`028.172-028.338s`), BLACK MARKET hover browsing (`00:28.17-00:33.15`, 9 item hovers), fade-out `00:33.10` (desk `[F] READ LEDGER` `00:33.15-00:34.10`), re-open `00:34.11`, close-prep clicks `00:37.3-00:37.4`, close `00:38.17`. No purchase or loadout change committed.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `00:26.6-00:27.1` | AU4 | Parchment page rustle + Journal open / tab-to-Black-Market clicks | `pk=-30.39 dBFS` at `00:26.88` (`astats.1s`); doc `pk=-30.4 dBFS` |
| `00:27.9-00:28.05` | AU4 | Black Market tab switch click | `pk=-34.5 dBFS` at `28.031 s` (KEYFRAME_INDEX §4, `astats`) |
| `00:28.3-00:34.0` | AU1 | Quiet `BLACK MARKET` reading (no cues) | 0.1 s window RMS `-64.41` to `-70.73 dBFS` (`astats.1s`); doc `-68 dBFS` room tone |
| `00:34.1-00:34.8` | AU4 | `JOURNAL` re-open & browse clicks | `pk=-33.65 dBFS` (`astats`); doc `pk=-33.7 dBFS` |
| `00:37.3-00:37.4` | AU4 | `JOURNAL` tab / close-prep clicks | `pk=-34.28 dBFS` at `00:37.38` (`astats.1s`); doc `pk=-34.3 dBFS` |
| `00:26.58-00:38.17` | AU1 | **Explicit BGM Absence:** zero background music score | no harmonic comb in `showspectrumpic`; flatness `0.611` (noise-like) |
|  |  | Re-measured segment peak / RMS | `-30.39 dBFS` / `-59.57 dBFS` (`astats`); `I=-52.5 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Ledger Journal / Black Market panel | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Contract lore cards + XP bar + market tables | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/HANDOFF_NEXT_SESSION.md:111` |
| Panel/tab ticks, no BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

### What to check in the port recording
- [UI4] `[Q] JOURNAL` / `BLACK MARKET [E]` tabs, XP `94/500`, contract cards (`Completed`/`Active`) and all 4 market tables.
- [UI4] `YOUR TOTAL ASSETS: (£) 26,275`, `✓ PURCHASED`, prices `7,500`/`5,000`/`2,500`, padlock badges verbatim.
- [V7] Crossfade `028.172-028.338s`; close-to-desk gap `00:33.15-00:34.10` with `[F] READ LEDGER`.
- [AU4] Parchment rustle + tab clicks (`pk=-30.4 / -34.5 dBFS`); no BGM.

## S07 - Thieves' Den Props, Decals & Gramophone (`00:38.17`-`00:51.08`, `12.91 s`)

**Keyframes:** KF09 (`00:46.25`) [clean](clean/KF09_00m46s_den_gramophone.jpg) · [annotated](annotated/KF09_00m46s_den_gramophone.jpg) - see CALLOUT_LEGENDS.md#kf09

### Narrative
Turns from the desk past the radiator and canvas-wrapped packages (`00:38.17-00:40.0`); at the round table, `[F] CHANGE DECORATION` swaps the golden owl statue for the blue/silver spider-emblem chest (`00:40.1-00:42.0`). Crosses floorboard boot/footstep trail decals (`00:43.75`) to the brass-horn Gramophone beside the 3-candle candelabra, glowing green floor diamond and iridescent white table diamond; `[F] TURN ON` flips to `[F] TURN OFF` (`00:44.4` click; KF09 `00:46.25` shows it playing). Cycles the stacked-trunk treasures (`00:47.6-00:50.0`: purple/gold Fabergé egg <-> golden chalice, pink gem <-> white diamond), then walks toward the Map Table.

### Visual
- **Environment / geometry (V4):** Radiator, canvas-wrapped package pile, round table (owl/chest), stacked trunks, brass-horn Gramophone, candelabra, Map Table ahead (KF09).
- **Lighting (V1):** Warm 3-candle candelabra amber pool on the horn and trunks (KF09#3) vs dark attic.
- **Sky / atmosphere / weather (V2):** None observed (interior).
- **Materials / shaders (V3):** Emissive faceted green floor diamond (KF09#6), iridescent white-blue table diamond (KF09#5), fluted brass horn, painted spider-emblem chest.
- **Characters / animation (V5):** None observed (no NPC in frame).
- **VFX (V6):** Decoration-swap intermediate state visible `~00:41.2` between owl and chest (contact sheet); UNCERTAIN: exact swap animation shape.
- **Camera / post (V7):** Free 1P pan left-to-right across the Den, ending framed on the Map Table.

### HUD / UI
- **Layout and state (UI1-UI5):** UI3 `Johnny Cipher` `4` + `SE` compass. UI2 prompts: `[F] CHANGE DECORATION` (round table + trunks), `[F] TURN ON` -> `[F] TURN OFF` (Gramophone, KF09#2).

### Gameplay and interactions
- G1 decoration station `[F] CHANGE DECORATION` (`00:40.1-00:42.0`): owl statue -> blue/silver spider-emblem chest; swap clinks `00:41.1-00:43.7`.
- G2 floorboard crossing over boot/footstep trail decals (`00:43.75`).
- G1 Gramophone toggle (`00:44.4` click): `[F] TURN ON` -> `[F] TURN OFF` (on-screen `00:45.5-00:47.4`); diegetic record plays `00:45.4-00:47.8`, attenuates `00:47.9-00:49.0` on walk-away.
- G1 trunk treasure cycle (`00:47.6-00:50.0`): egg <-> chalice, pink gem <-> white diamond; footsteps `00:49.3-00:49.9`.
- G2 walk toward Map Table (`00:50.0-00:51.08`) -> S08.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `00:40.3-00:40.5` | AU3 | Wooden footsteps | `pk=-34.68 dBFS` over `00:40.3-00:43.8` (`astats`); doc `pk=-34.7 dBFS` |
| `00:41.1-00:43.7` | AU5 | Metallic / glass prop-swap clinks (`[F] CHANGE DECORATION`) | 96 vertical transient columns in `showspectrumpic` (`00:40.3-00:43.8`) |
| `00:44.4-00:44.5` | AU5 | Gramophone switch click | `pk=-36.33 dBFS` over `00:44.4-00:45.4` (`astats`); doc `pk=-36.3 dBFS` |
| `00:45.4-00:47.8` | AU2 | **Diegetic Gramophone (ONLY music in the clip):** warped brassy wind-up + scratchy 1920s jazz/ragtime record with vinyl crackle | `pk=-24.92 dBFS` at `00:45.67` (`astats.1s`), block RMS `-42.33 dBFS` (`astats`); doc `pk=-24.9 dBFS` / `-40 to -45 dBFS` RMS |
| `00:47.9-00:49.0` | AU2 | Gramophone spatial attenuation (player walks away) | block RMS `-53.67 dBFS` (`astats`); doc `-51 to -60 dBFS` |
| `00:49.3-00:49.9` | AU3 | Wooden footsteps toward the Map Table | `pk=-34.4 dBFS` (KEYFRAME_INDEX §4, `astats`) |
| `00:38.17-00:51.08` | AU2 | **BGM PRESENT - diegetic only:** Gramophone record `00:45.4-00:47.8` | **no non-diegetic / background score** anywhere in `S05-S27` |
|  |  | Re-measured segment peak / RMS | `-24.92 dBFS` / `-48.84 dBFS` (`astats`); `I=-43.4 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Den props (radiator, packages, trunks, gramophone) | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Decoration-swap station + prompts | #15, #17 | `UNVERIFIED_LIVE` | - | `game/src/missions/mission_controller.gd:915-968` |
| Diamond emissives (green/white) | #8 | `APPROX_SHADER` | `PG-5` | `docs/HANDOFF_NEXT_SESSION.md:115` |
| Diegetic Gramophone jazz, swap clinks, no BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |

### What to check in the port recording
- [V4] Owl -> spider-emblem chest swap on the round table; trunk treasure cycle egg <-> chalice, gem <-> diamond.
- [V3] Green floor diamond emissive + iridescent table diamond; `[V1]` candelabra pool.
- [UI2] `[F] CHANGE DECORATION` and `[F] TURN ON` -> `[F] TURN OFF` prompt flips.
- [AU2] Diegetic jazz burst `00:45.4-00:47.8` (`pk=-24.9 dBFS`) with vinyl crackle, fading on walk-away; no BGM score.
- [G2] Boot/footstep trail decals visible at `00:43.75`.

## S08 - Map Table & Confirmation Modal (`00:51.08`-`00:56.08`, `5.00 s`)

**Keyframes:** KF10 (`00:52.35`) [clean](clean/KF10_00m52s_den_map_table.jpg) · [annotated](annotated/KF10_00m52s_den_map_table.jpg) - see CALLOUT_LEGENDS.md#kf10

### Narrative
Approaches the `KILCAIRN` parchment map (`BAY OF ORDENE`) under the brass banker's lamp beside the white marble bust (`00:51.08`). Inspects the 3D wooden tokens `ELWAY MANOR` and `CONSTABLES' GUILDHALL` (`00:51.5-00:55.1`): top-center card `[H] Difficulty: Novice`, `[R] Mode: Solo`, `[F] Prepare for Mission`, center reticle `[F] ENTER MATCH`, bottom-right legend (KF10 `00:52.35`). At `055.339s` the confirmation modal opens - `Join Mission with these settings? / Difficulty: Novice / Mode: Solo` + `[SPACE] PREPARE FOR MISSION` / `[ESC] CANCEL` - and the confirm chime fires at `00:55.4` before the cut to S09.

### Visual
- **Environment / geometry (V4):** `KILCAIRN` parchment map (`BAY OF ORDENE`), 3D wooden tokens `ELWAY MANOR` + `CONSTABLES' GUILDHALL`, brass banker's lamp, classical white marble bust, rolltop desk edge (KF10).
- **Lighting (V1):** Warm directional banker's-lamp pool across map and token (KF10#4) vs cool moonlit Den.
- **Sky / atmosphere / weather (V2):** None observed (interior, close framing).
- **Materials / shaders (V3):** Aged parchment albedo, carved wood tokens, brass specular, marble bust.
- **Characters / animation (V5):** None observed.
- **VFX (V6):** None observed (token highlight is UI emissive).
- **Camera / post (V7):** 1P look-down framing over the table; static while the modal is open.

### HUD / UI
- **Layout and state (UI1-UI5):** UI4 top-center settings card `CONSTABLES' GUILDHALL`, `[H] Difficulty: Novice`, `[R] Mode: Solo`, `[F] Prepare for Mission` (KF10#1); UI2 `[F] ENTER MATCH` reticle (KF10#3); UI3 bottom-right legend `JOIN GAME [F]`, `TOGGLE MODE [R]`, `TOGGLE DIFFICULTY [H]` (KF10#6) + `NE` compass + `Johnny Cipher` `4`. Confirmation modal (`055.339s`) verbatim per KEYFRAME_INDEX 5.2: `Join Mission with these settings? / Difficulty: Novice / Mode: Solo` with `[SPACE] PREPARE FOR MISSION` / `[ESC] CANCEL`.

### Gameplay and interactions
- G1 mission-select station: token inspection `ELWAY MANOR` -> `CONSTABLES' GUILDHALL` (`00:51.5-00:55.1`); difficulty/mode legend shows `[H]` / `[R]` toggles (no toggle change committed).
- G5 mission flow: confirmation modal `055.339s`, confirm chime `00:55.4` -> mission-prep load (S09).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `00:51.0-00:51.4` | AU3 | Wooden footsteps (Map Table approach) | `-35.92 dBFS` at `00:51.08`, `-38.26 dBFS` at `00:51.38` (`astats.1s`); doc `pk=-35.4 dBFS` |
| `00:52.2-00:55.1` | AU4 | Map Table selection / mode-toggle clicks | `pk=-38.27 dBFS` at `00:52.38` (`astats.1s`); doc `pk=-38.3 dBFS` |
| `00:55.4` | AU4 | Confirmation modal chime / click | `pk=-36.08 dBFS` at `00:55.38` (`astats.1s`); doc `pk=-36.1 dBFS` |
| `00:51.08-00:56.08` | AU1 | **Explicit BGM Absence:** zero background music score | broadband room tone + isolated UI transients only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-35.92 dBFS` / `-56.25 dBFS` (`astats`); `I=-51.1 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Map Table geometry + tokens + lamp/bust | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Mission-select card + look-at prompts | #15, #17 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/HANDOFF_NEXT_SESSION.md:111` |
| Confirmation modal | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Clicks + confirm chime, no BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

### What to check in the port recording
- [V4] `KILCAIRN` map with both wooden tokens, banker's lamp pool + marble bust framing.
- [UI4] Settings card `CONSTABLES' GUILDHALL` / `[H] Difficulty: Novice` / `[R] Mode: Solo` / `[F] Prepare for Mission`; `[UI2]` `[F] ENTER MATCH`; `[UI3]` `JOIN GAME [F]`, `TOGGLE MODE [R]`, `TOGGLE DIFFICULTY [H]`.
- [UI4] Modal `Join Mission with these settings?` + `[SPACE] PREPARE FOR MISSION` / `[ESC] CANCEL` at `055.339s`.
- [AU4] Selection clicks (`pk=-38.3 dBFS`) + confirm chime (`00:55.4`); no BGM.
- [G1] Token selection flow `ELWAY MANOR` -> `CONSTABLES' GUILDHALL`.

## S09 - Mission Preparation & 6s Countdown (`00:56.08`-`01:04.80`, `8.72 s`)

**Keyframes:** KF11 (`01:00.30`) [clean](clean/KF11_01m00s_mission_prep_countdown.jpg) · [annotated](annotated/KF11_01m00s_mission_prep_countdown.jpg) - see CALLOUT_LEGENDS.md#kf11

### Narrative
Brief loading flash (`056.077-056.309s`) cuts to `MISSION PREPARATION` (`Mode: Solo`, `Difficulty: Novice`). Left cards: `CONSTABLES' GUILDHALL` (gate preview shows `CONSTABLE'S GUILDHALL`), `Mission` (`Cleanout Heist`, `Time Limit: 55 minutes`), `Contract` (`Contract Inactive`) (KF11 `01:00.30`). Right: 3D Spider (`Johnny Cipher`) idle on the slate rooftop ridge under moon and angled searchlights. The player toggles `[F] READY` at `058.807s` (label `READY` + `[F] UNREADY` / `[ESC] BACK`), and the top-center countdown runs `MISSION STARTING IN 6...` -> `1...` (`058.914-064.775s`) to the S10 cut.

### Visual
- **Environment / geometry (V4):** Gothic Kilcairn rooftop stage - slate ridge, chimneys, dormers; stacked Art-Nouveau bordered cards (map/mission/contract) (KF11#2).
- **Lighting (V1):** Full moon upper-right cool rim light + twin angled volumetric searchlight beams across the ridge (KF11#4).
- **Sky / atmosphere / weather (V2):** Clear night sky with moon halo; faint haze inside the beams.
- **Materials / shaders (V3):** Card frame filigree, gate preview thumbnail, slate roof albedo.
- **Characters / animation (V5):** 3D Spider (`Johnny Cipher`) standing on the ridge wearing cap, goggles, belt pouches (KF11#5).
- **VFX (V6):** None observed.
- **Camera / post (V7):** Static wide beauty shot of the rooftop pose.

### HUD / UI
- **Layout and state (UI1-UI5):** UI4 left cards verbatim per KEYFRAME_INDEX 5.2 (KF11#2, KF11#3): `CONSTABLES' GUILDHALL` - `This is the headquarters and operational base for the Constables, Kilcairn's police force.`; `Mission` / `Cleanout Heist` / `Time Limit: 55 minutes` - `The Constables' Guildhall is full of confiscated treasures. Infiltrate the building and reacquire some of the riches they have just left lying around, then slip away before anyone notices.`; `Contract Inactive` - `Your active contract is not available for the currently selected map.`. UI5 countdown `MISSION STARTING IN 6...` -> `1...` with `Mode: Solo` / `Difficulty: Novice` (KF11#1). UI4 ready toggle: `[F] READY` -> `READY` + `[F] UNREADY` / `[ESC] BACK` at `058.807s` (KF11#6); `Johnny Cipher` nameplate.

### Gameplay and interactions
- G5 mission flow: loading flash `056.077-056.309s`; ready toggle `[F] READY` -> `READY` / `[F] UNREADY` at `058.807s`.
- G5 countdown (UI5): `MISSION STARTING IN 6...` -> `1...` at `058.914-064.775s` with 6 UI ticks at exact `1.00 s` intervals; hard cut to Loading Screen 2 at `064.803s`.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `00:56.0-00:58.9` | AU1 | Soft rooftop ambient wind bed (fades in after the loading-flash cut) | 0.1 s window RMS `-51.28` to `-56.34 dBFS` (`astats.1s`); exact-zero frame at `00:56.3`, fade-in from `-100.40 dBFS` peak at `00:56.2` |
| `00:59.0` | AU4 | Countdown tick `6` | `pk=-41.33 dBFS` in the `00:59.0` window (`astats.1s`); doc `pk=-41.3/-39.4 dBFS` |
| `01:00.0` | AU4 | Countdown tick `5` | `pk=-36.95 dBFS` in the `01:00.0` window (`astats.1s`); doc `pk=-36.9 dBFS` |
| `01:01.0` | AU4 | Countdown tick `4` | `pk=-37.43 dBFS` in the `01:01.0` window (`astats.1s`); doc `pk=-37.4 dBFS` |
| `01:02.0` | AU4 | Countdown tick `3` | `pk=-36.06 dBFS` in the `01:02.0` window (`astats.1s`); doc `pk=-36.1 dBFS` |
| `01:03.0` | AU4 | Countdown tick `2` | `pk=-37.04 dBFS` in the `01:03.0` window (`astats.1s`); doc `pk=-37.0 dBFS` |
| `01:04.0` | AU4 | Countdown tick `1` | `pk=-35.74 dBFS` in the `01:04.0` window (`astats.1s`); doc `pk=-35.7 dBFS` |
| `00:56.08-01:04.80` | AU1 | **Explicit BGM Absence:** zero background music score | wind bed + 6 ticks only; flattest spectrum in range (`flatness 0.540`) |
|  |  | Re-measured segment peak / RMS | `-35.74 dBFS` / `-53.48 dBFS` (`astats`); `I=-53.1 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Prep cards + countdown UI | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Mission flow (ready -> countdown -> load) | #15, #17 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/HANDOFF_NEXT_SESSION.md:111` |
| 3D Spider rooftop pose + rooftop set | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Rooftop wind bed + tick SFX, no BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

### What to check in the port recording
- [UI4] Card stack verbatim: `CONSTABLES' GUILDHALL` / `Cleanout Heist` / `Time Limit: 55 minutes` / `Contract Inactive`.
- [UI5] Countdown `MISSION STARTING IN 6...` -> `1...` with `Mode: Solo` / `Difficulty: Novice`.
- [V5] 3D Spider rooftop pose (cap, goggles, belt pouches); `[V1]` moon rim + angled searchlight beams.
- [AU4] 6 countdown ticks at `1.00 s` intervals (`pk=-41.3 to -35.7 dBFS`); `[AU1]` wind bed; no BGM.
- [G5] `[F] READY` -> `READY` / `[F] UNREADY` at `058.807s`; cut at `064.803s`.

## S10 - Loading Screen 2 (`01:04.80`-`01:09.44`, `4.64 s`)

**Keyframes:** KF12 (`01:06.50`) [clean](clean/KF12_01m06s_loading_screen.jpg) · [annotated](annotated/KF12_01m06s_loading_screen.jpg) - see CALLOUT_LEGENDS.md#kf12

### Narrative
Hard cut at `064.803s` to the Kilcairn night skyline illustration - twin searchlight dirigibles upper-left, pale full moon upper-right, centered spinner + `LOADING...`, gold `THICK AS THIEVES` emblem bottom-center (KF12 `01:06.50`) - ending `069.398s` at the Briefing Letter cut.

### Visual
- **Environment / geometry (V4):** 2D illustrated rooftop skyline (chimneys, circular fan facade left), no 3D geometry.
- **Lighting (V1):** Twin yellow searchlight cones from the dirigibles; moonlit ridge highlights.
- **Sky / atmosphere / weather (V2):** Dark-indigo/violet sky, textured pale full moon upper-right (KF12#2).
- **Materials / shaders (V3):** None observed (2D illustration).
- **Characters / animation (V5):** None observed.
- **VFX (V6):** Rotating cyan/white spinner ring (KF12#3).
- **Camera / post (V7):** Static full-screen illustration.

### HUD / UI
- **Layout and state (UI1-UI5):** UI4 centered spinner + `LOADING...` and gold `THICK AS THIEVES` emblem (KF12#3, KF12#4). No HUD.

### Gameplay and interactions
- G5 non-interactive transition (`064.803-069.398s`): mission confirm -> Guildhall level load; night rain fade-in begins `01:07.78` at the tail.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `01:04.80-01:04.99` | AU1 | Tail of Loading Screen 1 audio (last non-zero window) | `pk=-43.57 dBFS` at `01:04.80`, `-59.57 dBFS` at `01:04.90` (`astats.1s`) |
| `01:05.00-01:07.70` | AU1 | **True digital silence** - 27 consecutive 0.1 s windows | `astats.1s` peak/RMS = `-inf` (exact zero); direct PCM read = `100.000%` exactly-zero samples |
| `01:07.70-01:07.78` | AU1 | AAC decode artefact / rain onset edge | `pk=-119.92 dBFS`, RMS `-143.33 dBFS` (`astats.1s`); first non-zero sample at `t=67.7757 s` (`01:07.7757`) |
| `01:07.78-01:09.44` | AU1 | Night rain fade-in | `pk=-46.22 dBFS` at `01:09.10` (`astats.1s`); 0.1 s window RMS rises `-76.68` -> `-57.88 dBFS` (`astats.1s`) |
| `01:04.80-01:09.44` | AU1 | **Explicit BGM Absence:** no loading music | empty `showspectrumpic` (`flatness 1.000`, `0.0%` energy above 4 kHz) over the silence window |
|  |  | Re-measured segment peak / RMS | `-43.57 dBFS` / `-64.67 dBFS` (`astats`); `I=-61.3 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Loading art + spinner + emblem | #15 | `1:1_MATCH` | - | `game/src/ui/loading_screen.gd:9-12` |
| Fade to digital zero, no music | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

### What to check in the port recording
- [UI4] Spinner ring + `LOADING...` + gold `THICK AS THIEVES` emblem layout.
- [V2] Dirigible searchlights + pale moon illustration fidelity.
- [AU1] True digital silence `01:04.94-01:07.78`, rain fade-in at `01:07.78`; no loading music.

## S11 - Briefing Letter (`01:09.44`-`01:10.81`, `1.37 s`)

**Keyframes:** KF13 (`01:10.00`) [clean](clean/KF13_01m10s_briefing_letter.jpg) · [annotated](annotated/KF13_01m10s_briefing_letter.jpg) - see CALLOUT_LEGENDS.md#kf13

### Narrative
Cuts at `069.440s` to the centered 11-line parchment briefing over the blurred safe-room view (`069.440-070.766s`), dismissed with `[SPACE] CONTINUE` into the safe-room spawn (S12).

### Visual
- **Environment / geometry (V4):** Blurred Guildhall safe-room backdrop - dark brick wall + iron grate window behind the modal (KF13#1).
- **Lighting (V1):** Dim warm interior behind; the letter is evenly lit.
- **Sky / atmosphere / weather (V2):** None observed (blurred backdrop).
- **Materials / shaders (V3):** Folded cream parchment with horizontal crease shadow, typewriter print (KF13#2).
- **Characters / animation (V5):** None observed.
- **VFX (V6):** None observed.
- **Camera / post (V7):** Static modal over depth-of-field / Gaussian-blurred 3D backdrop (KF13#1).

### HUD / UI
- **Layout and state (UI1-UI5):** UI4 folded parchment sheet, 11 lines verbatim per KEYFRAME_INDEX 5.2 (KF13#2, KF13#3): `Esteemed Colleague - / The Constables' Guildhall is a / repository of countless treasures seized / over the years. Steal anything you come / across and put them to better use than / gathering dust in a collection case. / There is only a 55 minute window for the / job. Once you collect enough, a magic / door will be summoned for 20 minutes / before collapsing. / We'll be in touch.`; thin right scrollbar (KF13#4); `[SPACE] CONTINUE` button below (KF13#5).

### Gameplay and interactions
- G5 mission flow: letter modal `069.440-070.766s`; `[SPACE] CONTINUE` dismiss `~070.77` -> safe-room spawn at `01:10.81` (S12).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `01:09.44-01:09.5` | AU1 | Exterior night rain (continuing from Loading 2 fade-in) | 0.1 s window RMS `-57.36` to `-45.79 dBFS` (`astats.1s`) |
| `01:09.5-01:10.3` | AU4 | Parchment paper rustle (briefing letter open / dismiss) | `pk=-37.78 dBFS` at `01:10.24` (`astats.1s`); doc `pk=-37.8 dBFS` |
| `01:09.44-01:10.81` | AU1 | **Explicit BGM Absence:** no music and no VO narration | broadband rain bed only; `showspectrumpic` has no harmonic comb |
|  |  | Re-measured segment peak / RMS | `-37.78 dBFS` / `-50.83 dBFS` (`astats`); `I=-53.0 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Briefing letter modal + blur backdrop | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Rain bed + paper rustle, no BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |

### What to check in the port recording
- [UI4] All 11 letter lines verbatim incl. `55 minute window` and `20 minutes`; `[SPACE] CONTINUE` button + right scrollbar.
- [V7] Depth-of-field blur over the safe-room brick/grate backdrop.
- [AU3] Parchment rustle on open/dismiss (`pk=-37.8 dBFS`); `[AU1]` rain bed; no BGM/VO.

## S12 - Guildhall Safe-Room Overlook & Catwalk (`01:10.81`-`01:20.10`, `9.29 s`)

**Keyframes:** KF14 (`01:15.75`) [clean](clean/KF14_01m15s_saferoom_portal_hud.jpg) · [annotated](annotated/KF14_01m15s_saferoom_portal_hud.jpg) - see CALLOUT_LEGENDS.md#kf14

### Narrative
Spawns facing the industrial arched window over the city; HUD fades in (`071.011-071.308s`). ThiefNisha VO: *"Let the thieving begin."* (`01:11.6-01:13.1`). Turns left to the oil lantern on the crate table (`[F] TURN ON` -> flame + `[F] TURN OFF`, ignite `01:15.1`) beside the `"SPIDER"` flyer; the glowing green/purple Escape Portal wall outline shimmers (`01:15.2-01:16.2`; KF14 `01:15.75`), then exits onto the exterior metal grate catwalk (`01:17.3-01:20.1`) and vaults the railing (1P gloved arms).

### Visual
- **Environment / geometry (V4):** Brick safe room: arched window over the city, crate table with oil lantern + `"SPIDER"` flyer, iron grate catwalk and railing (KF14).
- **Lighting (V1):** Warm orange lantern bounce on brick after `01:15.1` (KF14#2) vs cool window light.
- **Sky / atmosphere / weather (V2):** Rainy night city beyond the window; wet grate/catwalk.
- **Materials / shaders (V3):** Dark brick albedo, iron grate, glass lantern chimney, emissive portal edges.
- **Characters / animation (V5):** 1P gloved arms during the railing vault (`01:19.6`).
- **VFX (V6):** Jagged glowing emerald-green + violet chromatic-edge Escape Portal wall outline shimmering (`01:15.2-01:16.2`) (KF14#1).
- **Camera / post (V7):** 1P spawn pan with HUD fade-in exposure; pitches down through the vault.

### HUD / UI
- **Layout and state (UI1-UI5):** UI3 fades in `071.011-071.308s`: top-left `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]` (Health Bar hidden at 100% HP), top-right `Johnny Cipher` `4`, compass `SE`, bottom-left `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond + `[TAB] MAP [MMB] [HOLD] PING MENU` (KF14#3-#5). Bottom-center UI3 **Light Gem** (warm cream lit sector upper-left = lantern side; lit sector size = light on the player, position = light direction; bright = exposed) flanked by UI5 **red player-noise arcs** (size/brightness = how much sound the player is making; absent = quiet) (KF14#6, KF14#7). UI2 `[F] TURN ON` -> `[F] TURN OFF` at the lantern. Per the HUD glossary, neither element is a detection meter.

### Gameplay and interactions
- G5 mission flow: safe-room spawn `01:10.81`; HUD fade-in `071.011-071.308s`; escape-door preview viewed `01:15.2-01:16.2`.
- G1 lantern station: `[F] TURN ON` click `01:15.1` -> flame + `[F] TURN OFF`; `"SPIDER"` flyer beside it.
- G2 traversal: walk to grate door, exterior catwalk `01:17.3-01:20.1`; grate footsteps `01:18.6` / `01:19.0`; vault/drop thud `01:19.6` (1P gloved arms) into the alley (S13).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `01:11.0-01:11.6` | AU1 | Steady exterior rain + attic / window ambience | block RMS `-48.83 dBFS` (`astats`); doc `-49 dBFS` RMS |
| `01:11.6-01:13.1` | AU6 | ThiefNisha: *"Let the thieving begin."* | `pk=-30.75 dBFS` (`astats`); doc `pk=-30.8 dBFS` |
| `01:15.1` | AU5 | Lantern toggle / ignite metallic click-whoosh | `pk=-28.08 dBFS` (`astats`); doc `pk=-28.1 dBFS` |
| `01:17.2-01:20.0` | AU3 | Hollow metal grate footsteps (`01:18.6`, `01:19.0`) | `pk=-27.26 dBFS` at `01:18.71` (`astats.1s`); doc `pk=-27.3 dBFS` |
| `01:19.6` | AU3 | Vault / drop landing thud | `pk=-30.55 dBFS` at `01:19.61` (`astats.1s`); doc `pk=-30.5 dBFS` |
| `01:10.81-01:20.10` | AU1 | **Explicit BGM Absence:** zero background music score | rain/attic bed + VO + SFX only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-27.26 dBFS` / `-48.36 dBFS` (`astats`); `I=-48.2 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Safe-room geometry + catwalk | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Lantern practical light | #6, #7 | `HARD_LIMIT (HL-7)` | `HL-7` | `docs/FIDELITY_GAPS.md:25` |
| Escape Portal emissive outline | #8 | `APPROX_SHADER` | `PG-5` | `docs/HANDOFF_NEXT_SESSION.md:115` |
| Stealth HUD + Light Gem + player-noise arcs | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Nisha VO + foley, no BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |

### What to check in the port recording
- [UI3] HUD fade-in `071.011-071.308s` with `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, hotbar `[1]`/`[2]`/`[4]`, `[TAB] MAP [MMB] [HOLD] PING MENU`; Health Bar hidden at 100% HP.
- [UI3] Light Gem lit sector pointing at the lantern side; `[UI5]` faint red player-noise arcs while moving.
- [V6] Green/purple Escape Portal outline shimmer `01:15.2-01:16.2`.
- [V1] Lantern ignite warm bounce on brick; `[V5]` 1P gloved arms at the vault.
- [AU6] *"Let the thieving begin."* (`pk=-30.8 dBFS`); `[AU5]` lantern click-whoosh; `[AU3]` grate footsteps + vault thud; no BGM.

## S13 - Street / Alley Approach, Vintage Car & Gate Alert (`01:20.10`-`01:39.30`, `19.20 s`)

**Keyframes:** KF15 (`01:21.38`) [clean](clean/KF15_01m21s_alley_barrons_demolition.jpg) · [annotated](annotated/KF15_01m21s_alley_barrons_demolition.jpg) - see CALLOUT_LEGENDS.md#kf15

### Narrative
Drops past the brick wall banner `BARRON'S DEMOLITION` / `EST. 1865` / `Out with the old, in with the new!` (`01:20.85-01:21.38`; KF15 `01:21.38`) with oil drums and steel ladder below (`01:24.2`). Sprints across wet cobbles (`01:24.8-01:33.5`): the Light Gem flares bright pale gold with red player-noise arcs during the sprint/puddle splash (`pk=-25.2 dBFS`). Guard 1 reacts *"What?"* (`01:34.1-01:34.6`). The player approaches the parked black vintage car (`[F] INTERACT` at `01:35.38`): double-honk `HONK—HONK!` (`01:35.68-01:36.45`, `pk=-20.2 dBFS`) + flashing headlights (`01:36.38+`); Guard 1: *"[Bit / You're] too loud, [thief?]."* (`01:37.2-01:38.5`), then *"What?!"* + alert sting (`01:38.8-01:39.2`) as the player moves toward the wrought-iron Guildhall gate (`01:38.5-01:39.30`). Health Bar remains hidden (100% HP).

### Visual
- **Environment / geometry (V4):** Weathered brick wall `BARRON'S DEMOLITION` banner (faint `EST. 1865`), crates, fallen steel oil drums, steel ladder, alley weeds, wet cobblestone street, wrought-iron fence/gate with `CONSTABLE'S GUILDHALL` arch beyond, black vintage car (KF15).
- **Lighting (V1):** Teal-cyan caged bulkhead light in the alley (KF15#2); green streetlamp pool during the sprint; car headlight flares (`01:36.38+`); wet-cobble speculars.
- **Sky / atmosphere / weather (V2):** Continuous night rain, ground mist, puddle reflections on the cobbles (KF15#6).
- **Materials / shaders (V3):** Wet-cobble specular response, painted brick banner, steel drums, glossy car body.
- **Characters / animation (V5):** 1P gloved hands/forearm during the alley drop (`01:20.1-01:21.4`, KF15#5); sprint/crouch locomotion.
- **VFX (V6):** Puddle splash spray during the sprint; headlight beam flares at `01:36.38+`.
- **Camera / post (V7):** 1P drop pitch-down then level street tracking; exposure lifts under the streetlamps.

### HUD / UI
- **Layout and state (UI1-UI5):** UI3 persists from S12: `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, `Johnny Cipher` `4`, `[TAB] MAP [MMB] [HOLD] PING MENU`, hotbar; Health Bar hidden (100% HP). UI3 Light Gem flares bright pale gold (exposed under the streetlamps) with UI5 **red player-noise arcs** large/bright during the sprint/puddle splash (`01:24.8-01:33.5`), absent while quiet (KF15#4 shows the deep indigo gem with no arcs at `01:21.38`). UI2 `[F] INTERACT` at the vintage car (`01:35.38`). World text verbatim per KEYFRAME_INDEX 5.2 (KF15#1): `BARRON'S DEMOLITION` (`EST. 1865` faint above), `Out with the old, in with the new!`.

### Gameplay and interactions
- G2 traversal: alley drop `01:20.1-01:21.4`, walk (`01:20-01:24`), sprint + puddle splash (`01:24.4-01:27.4`), crouch/walk (`01:28-01:33.8`).
- G1 interactable: vintage car `[F] INTERACT` (`01:35.38`) -> double-honk + flashing headlights (`01:35.68-01:36.45`, `01:36.38+`).
- G4 guard AI: Guard 1 vocal reactions - *"What?"* (`01:34.1-01:34.6`), *"[Bit / You're] too loud, [thief?]."* (`01:37.2-01:38.5`), *"What?!"* + alert sting (`01:38.8-01:39.2`) - alert escalation audible at segment end.
- G5 mission flow: approach to the wrought-iron Guildhall gate (`01:38.5-01:39.30`) -> S14.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `01:20.1-01:24.0` | AU3 | Wet cobblestone walk (alley drop, `BARRON'S DEMOLITION` banner) | broadband rain + footfall bed (`showspectrumpic`) |
| `01:24.4-01:27.4` | AU3 | Rapid sprint / puddle splash | `pk=-25.24 dBFS` (`astats`); doc `pk=-25.2 dBFS` |
| `01:28.0-01:33.8` | AU3 | Crouch / walk | 0.1 s window RMS median `-49.95 dBFS` (`astats.1s`) |
| `01:34.1-01:34.6` | AU6 | Guard 1: *"What?"* | `pk=-35.72 dBFS` (`astats`) |
| `01:35.68-01:36.45` | AU5 | Vintage Car Horn DOUBLE-HONK (`HONK-HONK!`) | `pk=-20.25 dBFS` at `01:35.7` (`astats.1s`); doc `pk=-20.2 dBFS`; tonal 317/356 Hz + 2537/2855/5392 Hz partials |
| `01:37.2-01:38.5` | AU6 | Guard 1: *"[Bit / You're] too loud, [thief?]."* | `pk=-25.90 dBFS` (`astats`) |
| `01:38.8-01:39.2` | AU6 | Guard: *"What?!"* + sharp metallic alert sting | inside the segment; below the segment peak of `-20.25 dBFS` (`astats`) |
| `01:20.10-01:39.30` | AU1 | **Explicit BGM Absence:** zero background music score | rain bed + foley + VO + horn only; no harmonic comb (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-20.25 dBFS` / `-45.99 dBFS` (`astats`); `I=-43.6 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Alley/street geometry + banner + car | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Streetlamp / headlight practicals | #6, #7 | `HARD_LIMIT (HL-7)` | `HL-7` | `docs/FIDELITY_GAPS.md:25` |
| HUD + Light Gem + player-noise arcs | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Vintage car interact (horn + headlights) | #15, #17 | `UNVERIFIED_LIVE` | - | `docs/HANDOFF_NEXT_SESSION.md:111` |
| Guard barks + alert sting + horn, no BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |

### What to check in the port recording
- [V4] Full unclipped `BARRON'S DEMOLITION` banner (`EST. 1865`), drums, ladder, wet cobbles, black vintage car, gate arch.
- [UI3] Light Gem flares pale gold under the streetlamps with `[UI5]` red player-noise arcs during the sprint (`01:24.8-01:33.5`), quiet/dark gem at the drop.
- [UI2] `[F] INTERACT` at the car `01:35.38`; `[V6]` headlight flares `01:36.38+`.
- [AU5] Double-honk (`pk=-20.2 dBFS`); `[AU6]` Guard 1 barks incl. `"[Bit / You're] too loud, [thief?]."` + `"What?!"` alert sting; no BGM.
- [G2] Drop -> walk -> sprint/puddle splash -> crouch cadence; `[G4]` guard alert escalation at the gate approach.

## S14 - 1st ZipWire, Gate & Ledge Chest (`01:39.30`-`01:49.50`, `10.20 s`)

**Keyframes:** KF16 (`01:40.20`) [clean](clean/KF16_01m40s_zipwire_gate_headlights.jpg) · [annotated](annotated/KF16_01m40s_zipwire_gate_headlights.jpg) - see CALLOUT_LEGENDS.md#kf16

### Narrative
The ZipWire `[1]` mechanical crank launcher swings into the right 1P hand (`01:39.30-01:39.50`), bottom-right prompts flipping to `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`. The frame is filled by the wrought-iron `CONSTABLE'S GUILDHALL` gate arch, flashing car headlights raking the wet cobbles, and a patrolling guard on the inner steps with glowing red eyes, hip flashlight and a vertical yellow overhead alert bar (`01:40.20`, KF16). The 1st ZipWire fires (`01:42.90-01:43.90`) and drops the player onto dark courtyard planter foliage beside an ornate wooden chest (`01:44.50-01:45.30`); a glowing cyan house-shaped icon is briefly visible (`01:45.50-01:45.90`, UNCERTAIN: what it marks; no interaction prompt captured). Pixel scan confirms `red_px=0` across `01:40-01:48` - the `01:44` foliage landing is non-damaging.

### Visual
- **Environment / geometry (V4):** Wrought-iron `CONSTABLE'S GUILDHALL` gate arch with gilded lettering and crowned stone pillars (KF16#1); inner steps; dark courtyard planter foliage; ornate wooden chest beside the landing (`01:44.50-01:45.30`).
- **Lighting (V1):** Flashing dual vintage-car headlights glaring across wet cobbles (KF16#3); pillar lanterns; guard's glowing red eyes and hip flashlight (`01:40.20`).
- **Sky / atmosphere / weather (V2):** Night rain over reflective cobbles; faint fog beyond the gate bars.
- **Materials / shaders (V3):** Wet-cobble specular streaks, polished launcher metal, gilded arch lettering.
- **Characters / animation (V5):** 1P gloved hands swing the mechanical ZipWire crank launcher into the right hand (`01:39.30-01:39.50`); patrolling constable with vertical yellow overhead alert bar (KF16#2).
- **VFX (V6):** Glowing cyan house-shaped icon flare (`01:45.50-01:45.90`; UNCERTAIN: meaning - no prompt verified).
- **Camera / post (V7):** 1P camera; aim raise at the arch, fast cable swing and drop onto foliage (`01:42.90-01:44.50`), settling low in the planter.

### HUD / UI
- **Layout and state (UI1-UI5):** Top-left `(£) 0` and `Mission: Steal 4,000 in loot value[0/4,000]` (no space before `[0/4,000]`); top-center compass `N`; top-right `Johnny Cipher` level `4` Spider card (KF16, UI3). Health Bar hidden (100% HP). Bottom-left `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond + `[TAB] MAP [MMB] [HOLD] PING MENU` (UI3); bottom-right `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]` from `01:39.5` (KF16, UI2). Light Gem (UI3) half-lit - cream lit sector left, indigo shadow right (partial headlight/streetlamp exposure) - with no red player-noise arcs at the equip/aim instant (KF16#5). Guard-side indicators at `01:40.20`: glowing red eyes + vertical yellow overhead alert bar (UI5, rendered above the guard).

### Gameplay and interactions
- **Interactables (G1):** Ornate wooden chest beside the planter landing (`01:44.50-01:45.30`); glowing cyan house-shaped icon briefly at `01:45.50-01:45.90` (UNCERTAIN: what it marks - no `[F]` prompt captured).
- **Traversal (G2):** 1P cable drop into dark courtyard planter foliage (`01:42.90-01:44.50`), landing upright (`01:44.50-01:45.30`).
- **Tools (G3):** ZipWire `[1]` equip swing (`01:39.30-01:39.50`); 1st launch fired `01:42.90-01:43.90` (snap/twang `01:43.5-01:43.8`).
- **AI (G4):** Alerted constable inside the gate (glowing red eyes, hip flashlight, vertical yellow alert bar) at `01:40.20`; guard VOs `01:39.3-01:42.2`.
- **Hazards / mission flow (G5):** No damage: `red_px=0` across `01:40-01:48`; first fall damage is at `02:23.30` (S17), not the `01:44` landing.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `01:39.3-01:40.6` | AU6 | Guard: *"I know someone's here!"* | `pk=-25.93 dBFS` (`astats`); doc `pk=-25.9 dBFS` at `99.308 s` |
| `01:40.6-01:42.2` | AU6 | Overlapping distant guard: *"[muffled: There's someone here...]"* | masked by the ZipWire equip clank (`astats`) |
| `01:41.8` | AU5 | ZipWire equip mechanical clank | `pk=-24.3 dBFS` (KEYFRAME_INDEX §4, `astats`) |
| `01:43.5-01:43.8` | AU5 | ZipWire launch snap / twang | `pk=-21.54 dBFS` at `01:43.6` (`astats.1s`); doc `pk=-21.5 dBFS` |
| `01:44.7-01:45.1` | AU3 | Foliage landing thud + non-damaging vocal grunt | `pk=-23.5 dBFS` (KEYFRAME_INDEX §4, `astats`) |
| `01:39.30-01:49.50` | AU1 | **Explicit BGM Absence:** zero background music score | rain bed + VO + tool foley only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-21.54 dBFS` / `-41.90 dBFS` (`astats`); `I=-39.5 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Gate arch + planter/chest geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Car-headlight glare / wet-cobble exposure | #8 | `APPROX_SHADER` | `PG-5` | `docs/HANDOFF_NEXT_SESSION.md:115` |
| ZipWire `[1]` equip + 1st launch (G3) | `UNCERTAIN:` subsystem # not in provided evidence | `UNVERIFIED_LIVE` | - | - |
| Guard alert bar + red eyes (G4/UI5) | `UNCERTAIN:` subsystem # not in provided evidence | `UNVERIFIED_LIVE` | - | - |
| Stealth HUD prompts + Light Gem (UI2/UI3) | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Guard VO + tool SFX + rain bed, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |

### What to check in the port recording
- [G3] ZipWire `[1]` equip swing + `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]` prompts in place by `01:39.5`.
- [V1] Car-headlight glare across wet cobbles; `[UI5]` guard's yellow alert bar + red eyes at `01:40.2`.
- [G2] Non-damaging foliage landing `01:44.5-01:45.3` - no Health Bar appears (`red_px=0`).
- [AU6] *"I know someone's here!"* + muffled overlap; `[AU5]` launch snap/twang; `[AU1]` rain bed, no BGM.

## S15 - 2nd ZipWire & Crank Ascent (`01:49.50`-`01:58.50`, `9.00 s`)

**Keyframes:** KF17 (`01:51.20`) [clean](clean/KF17_01m51s_zipwire_aim_roof.jpg) · [annotated](annotated/KF17_01m51s_zipwire_aim_roof.jpg) - see CALLOUT_LEGENDS.md#kf17

### Narrative
The player aims at the high brick roof ridge (`01:50.20-01:51.00`) and fires the 2nd ZipWire (`01:51.00-01:51.20`); a circular blue/white segmented progress reticle reading `CRANK [LMB]` appears center-screen (`01:51.20`, KF17) as the taut multi-strand cable anchors to the roof parapet. Rhythmic 1P crank-arm animation (`01:52.20-01:58.00`) hauls the player up the brick facade past a warm glowing wall lantern and onto the tiled roof ridge (`01:58.20-01:58.50`). A guard shouts throughout the shot.

### Visual
- **Environment / geometry (V4):** High brick roof ridge and parapet anchor; brick facade; tiled roof; warm wall lantern passed mid-climb.
- **Lighting (V1):** Warm glowing wall lantern mid-climb; scattered lit windows in the fog.
- **Sky / atmosphere / weather (V2):** Volumetric night mist; distant Guildhall spire/clocktower silhouette with tiny red window accents (KF17#2).
- **Materials / shaders (V3):** Taut multi-strand steel cable (KF17#1); brick and terracotta roof-tile materials.
- **Characters / animation (V5):** 1P crank-arm hand-over-hand animation (`01:52.20-01:58.00`).
- **VFX (V6):** None observed.
- **Camera / post (V7):** Low-angle upward framing locked along the cable; arrival tilt onto the ridge (`01:58.20-01:58.50`).

### HUD / UI
- **Layout and state (UI1-UI5):** Persistent stealth HUD continues (KF17): `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, compass `N`, `Johnny Cipher` level `4`, bottom-left `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond + `[TAB] MAP [MMB] [HOLD] PING MENU` (UI3); bottom-right `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]` (UI2). Center-screen segmented progress reticle `CRANK [LMB]` from `01:51.20` (KF17#3, UI2). Three-dash crimson guard-alert direction pip mid-right (`x~1195, y~832`, KF17#4, UI5) during the guard shout - a guard-perception direction indicator, separate from the Light Gem's red player-noise arcs. Light Gem (UI3) fully dark indigo (concealed) with no red player-noise arcs at the aim/crank instant (KF17#6). Health Bar hidden (100% HP).

### Gameplay and interactions
- **Traversal (G2):** Powered crank ascent up the brick facade `01:52.20-01:58.00` past the warm wall lantern, arriving on the tiled roof ridge `01:58.20-01:58.50`.
- **Tools (G3):** Aim `01:50.20-01:51.00`; 2nd ZipWire fired `01:51.00-01:51.20` (spring launch `01:51.7-01:51.9`); `CRANK [LMB]` hold cycle `01:52.20-01:58.00`.
- **AI (G4):** Guard shout *"Oh, I will find you, thief!"* (`~01:49.6-01:53.0`) with the guard-alert direction pip on screen (KF17#4).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `~01:49.6-01:53.0` | AU6 | Guard: *"Oh, I will find you, thief!"* | overlaps the 2nd ZipWire shot (`astats`) |
| `01:51.7-01:51.9` | AU5 | ZipWire spring / pneumatic launch | `pk=-24.79 dBFS` over `01:51.6-01:53.2` (`astats`); doc `pk=-24.8 dBFS` |
| `01:52.2-01:53.2` | AU5 | Metallic cable zip whine | part of the `01:51.6-01:53.2` block (`astats`) |
| `01:56.1-01:58.9` | AU5 | Rhythmic ratchet hand-cranking (17 click transients) | `pk=-22.16 dBFS` at `01:57.8` (`astats.1s`); doc `pk=-22.2 dBFS` |
| `01:49.50-01:58.50` | AU1 | **Explicit BGM Absence:** zero background music score | broadband + click train; flattest segment spectrum in range (`flatness 0.784`) |
|  |  | Re-measured segment peak / RMS | `-22.16 dBFS` / `-43.24 dBFS` (`astats`); `I=-40.4 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Brick facade / roof parapet geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Night mist + clocktower depth (V2) | #6, #7 | `HARD_LIMIT (HL-7)` | `HL-7` | `docs/FIDELITY_GAPS.md:25` |
| ZipWire cable anchor + crank ascent (G2/G3) | `UNCERTAIN:` subsystem # not in provided evidence | `UNVERIFIED_LIVE` | - | - |
| `CRANK [LMB]` reticle + guard-alert pip (UI2/UI5) | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/HANDOFF_NEXT_SESSION.md:111` |
| Launch/crank SFX + guard VO, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

### What to check in the port recording
- [G3] 2nd ZipWire shot + `CRANK [LMB]` segmented progress ring at `01:51.2`.
- [UI5] Guard-alert direction pip mid-right during *"Oh, I will find you, thief!"* - distinct from the Light Gem's player-noise arcs.
- [G2] Crank ascent animation `01:52.2-01:58.0` past the wall lantern onto the roof ridge.
- [AU5] Spring launch + ratchet cranking (`pk=-22.2 dBFS`); `[AU1]` rain bed, no BGM.

## S16 - Roofline Traversal & 3rd ZipWire (`01:58.50`-`02:11.00`, `12.50 s`)

**Keyframes:** none (no keyframe falls in this segment; frame evidence via clip extraction)

### Narrative
The player works along the slate roof edge (`01:58.50-02:00.50`), the lit `CONSTABLE'S GUILDHALL` gate and steps visible below at `02:00.50`, then grapples/cranks up onto a higher chimney/roof block (`02:01.00-02:08.50`, crank-release/roof clack at `02:07.6-02:07.8`). Climbing past the mechanical winch/gear housing (`02:09.00-02:10.40`), the player positions over the wrought-iron perimeter gate (`02:10.60-02:11.00`) and fires the 3rd ZipWire toward the gate pillar (`02:10.5-02:10.6`).

### Visual
- **Environment / geometry (V4):** Slate roof edge and tiles; reddish-brown cupola dome with warm point light; higher chimney/roof block; copper/rust mechanical winch/gear housing with spring assembly; wrought-iron perimeter gate and steps below (`02:00.50`).
- **Lighting (V1):** Warm point light on the cupola dome; warm-lit gate/steps pool seen from above (`02:00.50`); dim roofline exposure.
- **Sky / atmosphere / weather (V2):** Volumetric night mist over the rooftops; grey pre-dawn sky; distant lit-window city silhouettes.
- **Materials / shaders (V3):** Copper/brass winch housing with embossed plate; wet slate tiles.
- **Characters / animation (V5):** 1P crank/climb poses past the winch housing (`02:09.00-02:10.40`).
- **VFX (V6):** None observed.
- **Camera / post (V7):** Camera hugs the roof surfaces, tilts up the facade during the climb, then swings over the gate for the 3rd launch.

### HUD / UI
- **Layout and state (UI1-UI5):** Persistent stealth HUD continues (no keyframe in segment; strings per KEYFRAME_INDEX 5.2 constant HUD): `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, compass `N`, `Johnny Cipher` level `4`, bottom-left `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond + `[TAB] MAP [MMB] [HOLD] PING MENU` (UI3); bottom-right `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]` (UI2). Health Bar hidden (100% HP). Light Gem (UI3) stays dark on the unlit roofline; red player-noise arcs track the crank/climb foley (UNCERTAIN: exact per-frame arc states - no keyframe).

### Gameplay and interactions
- **Traversal (G2):** Slate roof-edge traverse `01:58.50-02:00.50` (gate/steps overlook `02:00.50`); grapple/crank onto the higher chimney/roof block `02:01.00-02:08.50` (crank-release/roof clack `02:07.6-02:07.8`); climbs past the mechanical winch/gear housing `02:09.00-02:10.40`.
- **Tools (G3):** Positioning over the perimeter gate `02:10.60-02:11.00`; 3rd ZipWire launch toward the gate pillar `02:10.5-02:10.6`.
- **AI (G4):** *"Who's there?"* (`02:02.4-02:03.6`); patrol mutter *"Captain said to look around for signs of trouble. Thieves, eh?"* (`02:06.8-02:11.0`).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `02:02.4-02:03.6` | AU6 | Guard: *"Who's there?"* over roof slate / stone footsteps | `pk=-21.66 dBFS` (`astats`); doc `pk=-21.7 dBFS` |
| `02:06.8-02:11.0` | AU6 | Guard (patrol mutter): *"Captain said to look around for signs of trouble. Thieves, eh?"* | block peak `-21.22 dBFS` (`astats`) |
| `02:07.6-02:07.8` | AU5 | ZipWire crank-release / roof clack (loudest SFX in the segment) | `pk=-21.22 dBFS` at `02:07.6` (`astats.1s`); doc `pk=-21.2 dBFS` at `127.686 s` |
| `02:10.5-02:10.6` | AU5 | 3rd ZipWire launch toward the wrought-iron gate pillar | `pk=-27.34 dBFS` over `02:10.5-02:10.7` (`astats`); doc `pk=-27.3 dBFS` |
| `01:58.50-02:11.00` | AU1 | **Explicit BGM Absence:** zero background music score | roofline wind/stone bed + VO + tool SFX only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-21.22 dBFS` / `-43.77 dBFS` (`astats`); `I=-41.0 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Roofline + winch/gear housing geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Rooftop mist / moon haze (V2) | #6, #7 | `HARD_LIMIT (HL-7)` | `HL-7` | `docs/FIDELITY_GAPS.md:25` |
| 3rd ZipWire launch + roof climb (G2/G3) | `UNCERTAIN:` subsystem # not in provided evidence | `UNVERIFIED_LIVE` | - | - |
| Patrol VO + roof clack, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |

### What to check in the port recording
- [G2] Roof-edge traverse -> crank onto chimney/roof block (clack `02:07.6-02:07.8`) -> winch-housing pass `02:09.0-02:10.4`.
- [G3] 3rd ZipWire launch at `02:10.5` from the gate-overlook position.
- [V4] Lit `CONSTABLE'S GUILDHALL` gate/steps view at `02:00.5`; copper winch/gear housing geometry.
- [AU6] *"Who's there?"* + patrol mutter *"Captain said to look around for signs of trouble. Thieves, eh?"*; no BGM.

## S17 - Gate Pillar & Courtyard Descent (`02:11.00`-`02:23.30`, `12.30 s`)

**Keyframes:** KF18 (`02:14.80`) [clean](clean/KF18_02m14s_guildhall_arch_overlook.jpg) · [annotated](annotated/KF18_02m14s_guildhall_arch_overlook.jpg) - see CALLOUT_LEGENDS.md#kf18

### Narrative
The cable crossing (`02:11.00-02:17.00`) looks down over the `CONSTABLE'S GUILDHALL` arch, crowned iron pillars and twin stone griffin statues flanking the grand stairs, with a distant green-highlighted guard silhouette on the portico at `02:14.80` (KF18). The player lands face-on beside a circular weathered white 10-bolt metal gear plate with red downward lightning-arrow (`⚡`) (`02:17.60-02:18.80`) and drops onto wet courtyard flagstones beside wooden crates (`02:19.00-02:23.20`). At `02:23.30` the drop registers as actual fall damage (`red_px: 0 -> 27,560`), revealing the ornate top-left Health Bar draining to ~75% fill.

### Visual
- **Environment / geometry (V4):** Crowned star-topped wrought-iron gate pillars (KF18#2); twin stone griffin statues on brick pedestals flanking the grand stairs (KF18#4); partial `CONSTABL...` arch lettering at the right edge (KF18#5); circular weathered white 10-bolt metal gear plate with red downward lightning-arrow (`⚡`); wooden crates; wet courtyard flagstones.
- **Lighting (V1):** Warm portico/lantern pools below; strong foreground contrast on the high cable angle; distant lit arch.
- **Sky / atmosphere / weather (V2):** Courtyard fog; rain-slick flagstones with reflected light patches.
- **Materials / shaders (V3):** Weathered white painted metal plate; wet stone; brick pedestals.
- **Characters / animation (V5):** Distant green-highlighted constable under the portico (KF18#3); 1P cable-crank pose and face-on landing.
- **VFX (V6):** None observed.
- **Camera / post (V7):** Elevated cable angle looking down over the courtyard (KF18 framing); face-on landing at the plate; vertical drop to flagstones (`02:19.00-02:23.20`).

### HUD / UI
- **Layout and state (UI1-UI5):** Persistent stealth HUD (KF18): `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, compass `N`, `Johnny Cipher` level `4`, bottom-left `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond + `[TAB] MAP [MMB] [HOLD] PING MENU` (UI3); bottom-right `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]` (UI2). Light Gem (UI3) mostly dark indigo with a small cream lit sector upper-left during the cable crossing (KF18#6); twin bright-red player-noise arcs (UI5) bracket the gem mid-cable (KF18#7) - size/brightness = how much sound the player makes (ratchet clicks `02:13.4-02:15.1`). Health Bar hidden (100% HP) until `02:23.30`, when the ornate top-left Health Bar is revealed and settles at ~75% fill (UI3).

### Gameplay and interactions
- **Traversal (G2):** ZipWire cable crossing `02:11.00-02:17.00` (mid-cable at `02:14.80`, KF18); face-on landing at the gear plate `02:17.60-02:18.80`; drop onto wet courtyard flagstones beside wooden crates `02:19.00-02:23.20`.
- **Tools (G3):** Mid-cable crank/ratchet control `02:13.4-02:15.1`.
- **AI (G4):** Distant green-highlighted constable on the portico `02:14.80`; distant guard VO *"Guess I'll search over here."* (`02:20.1-02:21.7`).
- **Hazards / mission flow (G5):** First fall damage at `02:23.30` (`red_px: 0 -> 27,560`): Health Bar reveals and settles at ~75% HP.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `02:13.4-02:15.1` | AU5 | ZipWire crank / ratchet clicks (mid-cable traversal) | `pk=-31.32 dBFS` (`astats`); doc `pk=-31.3 dBFS` |
| `02:19.0` | AU3 | Landing onto wet courtyard flagstones | `pk=-25.03 dBFS` at `02:19.4` (`astats.1s`) - segment maximum |
| `02:20.1-02:21.7` | AU6 | Distant Guard: *"Guess I'll search over here."* | `pk=-30.91 dBFS` (`astats`); ~20 dB below the segment peak |
| `02:23.30` | AU3 | Courtyard flagstone drop impact (first fall damage) | peak window `02:23.30-02:23.40` = `-25.82 dBFS` (`astats.1s`) - this window starts exactly at the `S17`/`S18` boundary, so the peak is reported under `S18` |
| `02:11.00-02:23.30` | AU1 | **Explicit BGM Absence:** zero background music score | broadband courtyard bed + cable clicks + VO only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-25.03 dBFS` / `-46.53 dBFS` (`astats`); `I=-45.9 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Gate pillars, griffins, gear plate geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Courtyard fog + wet-flagstone reflections (V2) | #6, #7 | `HARD_LIMIT (HL-7)` | `HL-7` | `docs/FIDELITY_GAPS.md:25` |
| Fall damage + Health Bar reveal (G5/UI3) | `UNCERTAIN:` subsystem # not in provided evidence | `UNVERIFIED_LIVE` | - | - |
| Health Bar + Light Gem + player-noise arcs (UI3/UI5) | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Cable clicks + impact foley, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

### What to check in the port recording
- [G2] Cable crossing over the arch/griffin stairs; face-on gear-plate landing `02:17.6-02:18.8`; crate-side drop `02:19.0-02:23.2`.
- [UI3] Fall damage at `02:23.30` (`red_px: 0 -> 27,560`): Health Bar reveals and drains to ~75% fill.
- [UI5] Twin red player-noise arcs mid-cable (player noise level), gem mostly dark.
- [V4] 10-bolt weathered white gear plate with red downward `⚡` arrow.
- [AU3] Flagstone drop impact at `02:23.30`; `[AU1]` rain bed, no BGM.

## S18 - Smoke Bomb Equip, Throw & Plume (`02:23.30`-`02:30.70`, `7.40 s`)

**Keyframes:** KF19 (`02:25.40`) [clean](clean/KF19_02m25s_smoke_bomb_equip.jpg) · [annotated](annotated/KF19_02m25s_smoke_bomb_equip.jpg) - see CALLOUT_LEGENDS.md#kf19; KF20 (`02:29.20`) [clean](clean/KF20_02m29s_smoke_bomb_plume.jpg) · [annotated](annotated/KF20_02m29s_smoke_bomb_plume.jpg) - see CALLOUT_LEGENDS.md#kf20

### Narrative
With the Health Bar's trailing bright-red drain segment settling to ~75% (`02:23.30-02:24.10`), the player equips the dark cylindrical Smoke Bomb canister (`[2]`, bottom-right `THROW [LMB]`) and walks past crates and griffin statues (`02:24.50-02:26.60`, KF19). The canister is thrown onto the grand stairs (`02:26.80-02:27.40`); an orange-white ignition flash (`02:28.20`) spawns billowing opaque grey-white volumetric smoke puffs across the steps (`02:28.40-02:29.80`, KF20) while red player-noise arcs flare with the detonation and dissipate (`02:30.20-02:30.70`).

### Visual
- **Environment / geometry (V4):** Grand courtyard steps; twin wet sculpted stone griffin statues on brick plinths (KF19#2); wooden crates; rain-slick flagstones; overhead iron bridge silhouette in fog; distant `MACL...` (`MACLEOD`) sign on the right facade (KF19#3).
- **Lighting (V1):** Warm cream-gold Light Gem exposure on the flagstones (KF19#6); orange-white ignition flash at `02:28.20`.
- **Sky / atmosphere / weather (V2):** Steady rain over flagstones; low haze swallowed by the smoke plume.
- **Materials / shaders (V3):** Dark cylindrical metal Smoke Bomb canister with lever (KF19#4).
- **Characters / animation (V5):** 1P gloved right hand grips the canister (KF19#4); throw arm swing `02:26.80-02:27.40`.
- **VFX (V6):** Billowing opaque grey-white volumetric smoke puffs expanding horizontally across the grand steps to block sight lines (`02:28.40-02:29.80`, KF20#1).
- **Camera / post (V7):** 1P courtyard-floor view; stairs framed center as the plume blooms.

### HUD / UI
- **Layout and state (UI1-UI5):** Top-left ornate Health Bar visible (~75% fill) with trailing bright-red drain segment settling `02:23.30-02:24.10` (KF19#1, UI3); `(£) 0` and `Mission: Steal 4,000 in loot value[0/4,000]` below it; `Johnny Cipher` level `4`; compass `NE` (KF19) then `N` (KF20). Slot `[2]` Smoke Bomb active bottom-left (KF19); bottom-right `THROW [LMB]` (KF19#5, UI2); `[TAB] MAP [MMB] [HOLD] PING MENU`. Light Gem (UI3) warm cream-gold lit at equip (KF19#6), lit cream-white at detonation (KF20#4); wide twin bright-red player-noise arcs (UI5) flare with the detonation pop + pressurized hiss and dissipate `02:30.20-02:30.70` (KF20#5).

### Gameplay and interactions
- **Traversal (G2):** Courtyard-floor walk past crates and griffin statues `02:24.50-02:26.60`.
- **Tools (G3):** Smoke Bomb `[2]` equipped (`THROW [LMB]`); throw `02:26.80-02:27.40` (canister clink `02:27.3-02:27.4`); ignition flash `02:28.20`; plume `02:28.40-02:29.80`.
- **AI (G4):** *"Hey! Show yourself!"* (`02:24.8-02:26.0`); faint guard cough (`02:29.5`); *"You stop making noise, you dog!"* (`02:30.3-02:32.2`, trails into S19).
- **Hazards / mission flow (G5):** Smoke screen covers the stair sight lines `02:28.40-02:29.80`; HP steady at ~75% through the segment.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `02:23.30` | AU3 | Courtyard flagstone drop impact (peak window, carries over from `S17`) | `pk=-25.82 dBFS` in the `02:23.3` window (`astats.1s`) |
| `02:24.8-02:26.0` | AU6 | Guard: *"Hey! Show yourself!"* | `pk=-33.35 dBFS` (`astats`); doc `pk=-33.3 dBFS` |
| `02:27.3-02:27.4` | AU5 | Smoke Bomb throw + metallic canister clink | `pk=-27.99 dBFS` at `02:27.4` (`astats.1s`); doc `pk=-28.0 dBFS` |
| `02:28.3-02:29.8` | AU5 | Detonation pop + sustained pressurised hiss / whoosh | `pk=-20.46 dBFS` at `02:28.3` (`astats.1s`); doc `pk=-20.5 dBFS` |
| `02:29.5` | AU6 | Faint guard cough | inside the `02:28.3-02:29.8` block (`astats`) |
| `02:30.3-02:32.2` | AU6 | Guard: *"You stop making noise, you dog!"* (runs on into `S19`) | starts inside `S18` (`astats`) |
| `02:23.30-02:30.70` | AU1 | **Explicit BGM Absence:** zero background music score | guard VO + smoke-bomb SFX only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-20.46 dBFS` / `-46.81 dBFS` (`astats`); `I=-43.8 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Courtyard steps + griffin/crate geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Volumetric smoke plume VFX (V6) | `UNCERTAIN:` subsystem # not in provided evidence | `UNVERIFIED_LIVE` | - | - |
| Smoke Bomb equip/throw/detonation (G3) | `UNCERTAIN:` subsystem # not in provided evidence | `UNVERIFIED_LIVE` | - | - |
| Health Bar ~75% state + noise-arc flare (UI3/UI5) | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Detonation pop + hiss + guard VO, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |

### What to check in the port recording
- [G3] Smoke Bomb `[2]` equip -> throw `02:26.80-02:27.40` -> ignition flash `02:28.20` -> plume `02:28.40-02:29.80`.
- [UI3] Health Bar ~75% with trailing red drain segment settling `02:23.30-02:24.10`.
- [UI5] Red player-noise arcs flare with the detonation and dissipate `02:30.20-02:30.70`.
- [V6] Opaque grey-white volumetric smoke spreading horizontally across the steps (blocks stair sight lines).
- [AU5] Detonation pop + pressurized hiss (`pk=-20.5 dBFS`); `[AU6]` guard shout; no BGM.

## S19 - Vistara Diamond Scan Pulse (`02:30.70`-`02:33.00`, `2.30 s`)

**Keyframes:** KF21 (`02:32.20`) [clean](clean/KF21_02m32s_vistara_diamond_red_guard.jpg) · [annotated](annotated/KF21_02m32s_vistara_diamond_red_guard.jpg) - see CALLOUT_LEGENDS.md#kf21; KF22 (`02:33.00`) [clean](clean/KF22_02m33s_vistara_diamond_green_guard.jpg) · [annotated](annotated/KF22_02m33s_vistara_diamond_green_guard.jpg) - see CALLOUT_LEGENDS.md#kf22

### Narrative
The faceted iridescent Vistara Diamond (`[4]`) is equipped in its brass-and-leather caliper holder (`THROW [LMB]`). Its scan pulse highlights the patrolling constable on the portico steps as a RED silhouette (`02:31.40-02:32.60`, clearest at `02:32.20`, KF21) while a bright warm golden glint flares center-courtyard (`02:32.60-02:33.00`). The player switches back to ZipWire `[1]` (`02:32.80-02:33.00`) as the highlighted guard transitions from RED to bright GREEN at `02:33.00` (KF22, exactly on the S19/S20 boundary).

### Visual
- **Environment / geometry (V4):** Multi-tier tubular metal and timber scaffolding against the wet stone left courtyard wing (KF21#2); portico steps and facade; rain-wet flagstones.
- **Lighting (V1):** Bright warm golden glint/flare off the rain-wet flagstones center-frame (`02:32.60-02:33.00`, KF22#2).
- **Sky / atmosphere / weather (V2):** Light courtyard mist; steady rain.
- **Materials / shaders (V3):** Faceted iridescent Vistara Diamond in brass-and-leather caliper mount (KF21#4).
- **Characters / animation (V5):** Guard silhouette flips RED (`02:31.40-02:32.60`, KF21#3) to bright GREEN at `02:33.00` (KF22#1); 1P tool swap raises the ZipWire launcher (`02:32.80-02:33.00`, KF22#3).
- **VFX (V6):** Diamond scan shimmer/pulse effect across the courtyard.
- **Camera / post (V7):** Static aim toward the portico; tool swap tilts the launcher into the right frame edge.

### HUD / UI
- **Layout and state (UI1-UI5):** Health Bar ~75% fill (KF21#1, UI3); `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`; compass `N`; `Johnny Cipher` level `4`. Slot `[4]` Vistara Diamond highlighted white (KF21#5, UI3) with bottom-right `THROW [LMB]` (KF21#6, UI2); at the swap (`02:32.80-02:33.00`) the highlight returns to `[1]` (KF22#4) and the prompts flip to `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]` (KF22#5). Light Gem (UI3) dark indigo (concealed; small white highlight upper-left) with no red player-noise arcs during the quiet scan (KF21#7, KF22#6).

### Gameplay and interactions
- **Tools (G3):** Vistara Diamond `[4]` equipped (brass-and-leather caliper holder, `THROW [LMB]`); scan pulse `02:31.40-02:32.60`; switch back to ZipWire `[1]` `02:32.80-02:33.00`.
- **AI (G4):** Scan pulse highlights the patrolling constable on the portico steps RED (`02:31.40-02:32.60`, clearest `02:32.20`, KF21), transitioning to bright GREEN at `02:33.00` (KF22).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `02:30.3-02:32.2` | AU6 | Guard (trailing): *"You stop making noise, you dog!"* | `pk=-31.11 dBFS` at `02:30.8` (`astats.1s`) - segment maximum |
| `02:32.8-02:33.0` | AU5 | Vistara Diamond equip + crystalline shimmer / chime pulse (onset only) | `pk=-34.45 dBFS` (`astats`); the doc's `-28.0 dBFS` peak is at `02:33.5`, i.e. in `S20` |
| `02:30.70-02:33.00` | AU1 | **Explicit BGM Absence:** zero background music score | quietest 0.1 s window peak median in range (`-36.58 dBFS`, `astats.1s`) |
|  |  | Re-measured segment peak / RMS | `-31.11 dBFS` / `-47.32 dBFS` (`astats`); `I=-44.3 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Scaffolding + portico geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Vistara scan RED->GREEN highlight (G4/V5) | `UNCERTAIN:` subsystem # not in provided evidence | `UNVERIFIED_LIVE` | - | - |
| Vistara Diamond equip/scan mechanics (G3) | `UNCERTAIN:` subsystem # not in provided evidence | `UNVERIFIED_LIVE` | - | - |
| Tool hotbar highlight + prompts (UI2/UI3) | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/HANDOFF_NEXT_SESSION.md:111` |
| Shimmer/chime SFX, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

### What to check in the port recording
- [G3] Vistara Diamond `[4]` equip + scan pulse `02:31.40-02:32.60`; switch back to `[1]` at `02:32.80-02:33.00`.
- [G4] Guard silhouette RED (`02:32.20` clearest) -> bright GREEN at `02:33.00`.
- [V1] Warm golden courtyard glint `02:32.60-02:33.00`.
- [UI3] `[4]` hotbar highlight then `[1]`; `[UI2]` `THROW [LMB]` -> `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`.
- [AU5] Crystalline shimmer/chime (`pk=-28.0 dBFS`); no BGM.

## S20 - Side Wing & MACLEOD Sign (`02:33.00`-`02:54.50`, `21.50 s`)

**Keyframes:** KF23 (`02:41.00`) [clean](clean/KF23_02m41s_side_wing_macleod_sign.jpg) · [annotated](annotated/KF23_02m41s_side_wing_macleod_sign.jpg) - see CALLOUT_LEGENDS.md#kf23

### Narrative
The player traverses the left courtyard wall and rain-slick stone balcony with iron balustrade and a barred red-lit window (`02:33.00-02:47.50`); the vertical illuminated gold serif `MACLEOD` sign is visible on the distant facade (`02:35.00-02:41.50`, again `02:48.50-02:49.00`, KF23). After gear/vault clacks (`02:47.9-02:49.2`) the player reaches the wet grass/cobble garden terrace (`02:49.50-02:54.50`), where a sound-ripple ring and red player-noise arcs fire as the ZipWire gleams white (`02:50.00-02:50.50`); a patrolling guard is spotted ahead (`02:53.00-02:54.50`).

### Visual
- **Environment / geometry (V4):** Stone side-wing facade with ornate diamond iron window grilles glowing warm red from an interior source (KF23#2); rain-slick stone balcony pavers and carved stone balustrade (KF23#3); vertical illuminated gold serif `MACLEOD` sign on the distant right facade (KF23#5); wet grass/cobble garden terrace.
- **Lighting (V1):** Illuminated `MACLEOD` signage; warm red interior glow through the window bars; cool moonlight sheen on wet stone.
- **Sky / atmosphere / weather (V2):** Elevated steel railway/bridge arch and distant Kilcairn rooflines receding into volumetric night fog (KF23#4); steady rain.
- **Materials / shaders (V3):** Wet-stone speculars; iron balustrade; glowing sign glass; red-lit diamond grilles.
- **Characters / animation (V5):** 1P traversal/vault poses (`02:47.9-02:49.2`); distant patrolling guard ahead (`02:53.00-02:54.50`).
- **VFX (V6):** Sound-ripple ring + ZipWire white gleam (`02:50.00-02:50.50`).
- **Camera / post (V7):** Forward-tracking 1P camera along the balcony; swings wide onto the garden terrace.

### HUD / UI
- **Layout and state (UI1-UI5):** Health Bar ~75% fill (KF23, UI3); `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`; compass `NE` (KF23#1); `Johnny Cipher` level `4`; bottom-left `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond + `[TAB] MAP [MMB] [HOLD] PING MENU` (UI3); bottom-right `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]` (UI2). Light Gem (UI3) dark indigo (concealed) on the balcony with no red player-noise arcs during the quiet traversal (KF23#7); at `02:50.00-02:50.50` a sound-ripple ring + red player-noise arcs (UI5) fire as the ZipWire gleams white. The `MACLEOD` sign is in-world signage (V4), not HUD.

### Gameplay and interactions
- **Traversal (G2):** Left courtyard wall + rain-slick stone balcony traverse `02:33.00-02:47.50`; gear/vault clacks `02:47.9-02:49.2`; wet grass/cobble garden terrace `02:49.50-02:54.50`.
- **Tools (G3):** ZipWire `[1]` re-equip click `02:34.0`; white gleam + sound-ripple ring `02:50.00-02:50.50` with red player-noise arcs.
- **AI (G4):** Distant guard throat-clear/cough (*"Ahem-hem"*) `02:41.5-02:42.2`; *"Hey!"* (`02:46.2`); patrolling guard spotted ahead `02:53.00-02:54.50`.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `02:34.0` | AU5 | ZipWire re-equip click | `pk=-28.19 dBFS` over `02:34.0-02:41.0` (`astats`); doc `pk=-28.2 dBFS` |
| `02:34.0-02:41.0` | AU3 | Rapid wet stone / balcony footsteps + steady rain | broadband bed (`showspectrumpic`) |
| `02:41.5-02:42.2` | AU6 | Distant guard throat-clear / cough (*"Ahem-hem"*) | `pk=-35.49 dBFS` (`astats`); 0 transient columns - smooth bark spectrum |
| `02:46.2` | AU6 | Guard: *"Hey!"* | inside the `02:46.2-02:56.0` block (`astats`) |
| `02:47.9-02:49.2` | AU5 | Gear / vault clacks | `pk=-25.47 dBFS` at `02:48.1` (`astats.1s`); doc `pk=-25.5 dBFS` - segment maximum |
| `02:33.00-02:54.50` | AU1 | **Explicit BGM Absence:** zero background music score | rain + wet-stone foley + guard barks only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-25.47 dBFS` / `-48.37 dBFS` (`astats`); `I=-47.4 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Side-wing balcony / terrace geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| `MACLEOD` sign emissive tint/exposure | #8 | `APPROX_SHADER` | `PG-5` | `docs/HANDOFF_NEXT_SESSION.md:115` |
| Viaduct fog depth (V2) | #6, #7 | `HARD_LIMIT (HL-7)` | `HL-7` | `docs/FIDELITY_GAPS.md:25` |
| ZipWire re-equip + gleam/ripple (G3) | `UNCERTAIN:` subsystem # not in provided evidence | `UNVERIFIED_LIVE` | - | - |
| HUD prompts + noise-arc event (UI2/UI3/UI5) | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Rain/footsteps + guard barks, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |

### What to check in the port recording
- [V4] Vertical `MACLEOD` sign legible `02:35.00-02:41.50` (again `02:48.50-02:49.00`); barred red-lit window; carved iron balustrade.
- [G2] Balcony traverse `02:33.00-02:47.50`, vault clacks `02:47.9-02:49.2`, garden terrace `02:49.50-02:54.50`.
- [UI5] Sound-ripple ring + red player-noise arcs at `02:50.00-02:50.50` (ZipWire white gleam).
- [G4] Distant cough *"Ahem-hem"* `02:41.5`, *"Hey!"* `02:46.2`; guard spotted ahead `02:53.00-02:54.50`.
- [AU1] Steady rain + wet stone footsteps; `[AU5]` re-equip click; no BGM.

## S21 - Arched Portico, Blue Double Doors & Scaffolding (`02:54.50`-`03:04.50`, `10.00 s`)

**Keyframes:** KF24 (`03:00.60`) [clean](clean/KF24_03m00s_locked_blue_double_doors.jpg) · [annotated](annotated/KF24_03m00s_locked_blue_double_doors.jpg) - see CALLOUT_LEGENDS.md#kf24

### Narrative
Leaving the garden terrace, the player enters the arched stone side portico (`02:55.00-02:59.00`, brief purple-outlined 1P hand flash at `02:55.50`) and closes on the blue-painted diamond-mullion glass double doors (`02:59.40-03:00.40`). The reticle stacks `[F] OPEN` over `[F] [HOLD] LOCK` (`03:00.60-03:01.00`), then flips to `[F] CLOSE` (`03:01.20`) as the door swings inward (`03:01.0-03:02.2`). The player inspects the wooden scaffolding inside (`03:01.80-03:03.20`) and walks through the doorway (`03:04.00-03:04.50`).

### Visual
- **Environment / geometry (V4):** Arched stone side portico; blue-painted wooden double doors with diamond-mullion glass panes and twin vertical brass pull handles (KF24#1); ashlar block wall right; wooden scaffolding inside (`03:01.80-03:03.20`).
- **Lighting (V1):** Dim night ambience over the terrace; sheltered portico reduces the exterior rain wash (KF24#4); warm interior spill through the open doorway.
- **Sky / atmosphere / weather (V2):** Rain-wet garden cobbles and night sky behind (`02:55.00-02:59.00`); rain streaks give way to shelter at the doors.
- **Materials / shaders (V3):** Blue-painted wood with white/cream mullion grid over dark glass panes (KF24#1); brass pull handles; dressed stone blocks.
- **Characters / animation (V5):** 1P gloved hands grip the ZipWire `[1]` launcher (KF24#4); brief purple-outlined 1P hand flash at `02:55.50` (`UNCERTAIN:` trigger - observed as a purple rim outline on the glove only).
- **VFX (V6):** None observed.
- **Camera / post (V7):** 1P gameplay camera; slow door approach, swing-in reveal at `03:01.20`, walk-through at `03:04.00-03:04.50`.

### HUD / UI
- **Layout and state (UI1-UI5):** Persistent stealth HUD: top-left `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, Health Bar visible (~75% fill since `02:23.30`); top-right `Johnny Cipher`, level `4`; bottom-left `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond, `[TAB] MAP [MMB] [HOLD] PING MENU`; bottom-right `LAUNCH [LMB]`, `[HOLD] CRANK [RMB]`. Center reticle (UI2): `[F] OPEN` above `[F] [HOLD] LOCK` (`03:00.60-03:01.00`, KF24#2, KF24#3), flipping to `[F] CLOSE` (`03:01.20`). Bottom-center Light Gem fully lit cream-white (KF24#5, UI3 - fully exposed) with faint red player-noise arcs (KF24#6, UI5 - the player's own noise level).

### Gameplay and interactions
- Threshold traversal (G2): heavy landing/vault thud at `02:55.8`, then a walk across the sheltered portico.
- Door interactable (G1): `[F] OPEN` swings the blue double doors inward (`03:01.0-03:02.2`) with `[F] [HOLD] LOCK` stacked as the secondary action and `[F] CLOSE` replacing the prompt at `03:01.20`; `UNCERTAIN:` whether `[HOLD] LOCK` was ever completed - no lock interaction is shown.
- ZipWire `[1]` stays equipped in the 1P right hand (G3) throughout.
- Inspects the wooden scaffolding (`03:01.80-03:03.20`), then enters the interior doorway (`03:04.00-03:04.50`).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `02:55.8` | AU3 | Heavy landing / vault thud (arriving at the arched portico) | `pk=-25.67 dBFS` at `02:55.9` (`astats.1s`); doc `pk=-25.7 dBFS` (listed under `S20` in KEYFRAME_INDEX §4, but inside `S21`'s window) |
| `03:00.6-03:01.2` | AU5 | Door reticle / handle latch click | inside the `03:01.0-03:02.2` block (`astats`) |
| `03:01.0-03:02.2` | AU5 | Wooden door creak open | `pk=-29.80 dBFS` (`astats`); doc `pk=-29.8 dBFS`; pitched wooden resonance 60/120/236/308/530 Hz |
| `03:03.0-03:04.5` | AU3 | Quiet parquet footsteps (interior) | 20 vertical transient columns in `showspectrumpic` |
| `02:54.50-03:04.50` | AU1 | **Explicit BGM Absence:** zero background music score | thud + door SFX + parquet foley only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-25.67 dBFS` / `-47.94 dBFS` (`astats`); `I=-47.7 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Portico + blue double door geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| `[F] OPEN` / `[F] [HOLD] LOCK` / `[F] CLOSE` door swing | #17 | `UNVERIFIED_LIVE` | `PG-4` | `docs/HANDOFF_NEXT_SESSION.md:112` |
| 1P hands + ZipWire `[1]` viewmodel | #11, #12 | `KNOWN_GAP (PG-7)` | `PG-7` | `docs/reports/player-1p.md:99-104` |
| Exterior-to-sheltered light shift | #6, #7 | `HARD_LIMIT (HL-7)` | `HL-7` | `docs/FIDELITY_GAPS.md:25` |
| Interaction prompts + persistent HUD | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Latch/creak, footsteps, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

*PG-2's `S03`/`S04`/`S06a`/`S06b`/`S11`/`S14`/`S15b` labels are port E2E test-scenario IDs (map_table, wardrobe, mission_prep, zipwire_crank, guard_lantern_alert, lockpick), not clip timeline segments.*

### What to check in the port recording
- [V4] Blue diamond-mullion double doors with twin brass pulls under the stone portico arch; wooden scaffolding inside.
- [UI2] `[F] OPEN` over `[F] [HOLD] LOCK` (`03:00.60-03:01.00`), flipping to `[F] CLOSE` (`03:01.20`) on open.
- [UI3] HUD at ~75% Health Bar; fully lit Light Gem with faint red player-noise arcs (the player's own noise level).
- [AU5] Latch click + wooden creak (`03:01.0-03:02.2`); `[AU1]` rain-to-interior room tone; no BGM.

## S22 - Fireplace Parlor Stealth & Pickpocket (`03:04.50`-`03:17.10`, `12.60 s`)

**Keyframes:** KF25 (`03:16.80`) [clean](clean/KF25_03m16s_parlor_pickpocket_takedown.jpg) · [annotated](annotated/KF25_03m16s_parlor_pickpocket_takedown.jpg) - see CALLOUT_LEGENDS.md#kf25

### Narrative
The player walks the warm amber-lit hallway (`03:04.50-03:05.50`) into the wood-parquet Fireplace Parlor (`03:05.80`) - chandelier, armchairs, roaring hearth - and crouches behind a standing constable whose hands are clasped behind his back, with a glowing blue baton on his left hip. The reticle stacks `[F] PICK POCKET` over `[F] [HOLD] TAKEDOWN` (`03:15.00-03:17.00`). At `03:17.10` the pickpocket completes: the `Guildhall Key` icon + label appear bottom-left above `[1]` Zipwire alongside a brief glowing 3D golden ornate key pickup shimmer (`03:17.10` only - verified NOT a yellow `!` alert icon).

### Visual
- **Environment / geometry (V4):** Warm hallway into the wood-parquet Fireplace Parlor; carved mantel and hearth, chandelier, armchairs and side tables (KF25).
- **Lighting (V1):** Roaring hearth casts warm amber radial light across the parquet (KF25#1); chandelier points overhead.
- **Sky / atmosphere / weather (V2):** Interior; none observed.
- **Materials / shaders (V3):** Herringbone wood parquet, carved wood mantel and panelling, dark padded uniform cloth; glowing blue baton tip (KF25#2).
- **Characters / animation (V5):** Standing constable before the fireplace, hands clasped behind back, unaware of the crouched approach (KF25#3); glowing blue-tip baton holstered on his left belt hip (KF25#2); player crouched directly behind him (1P).
- **VFX (V6):** Brief glowing 3D golden ornate key pickup shimmer at `03:17.10`.
- **Camera / post (V7):** 1P crouch-height approach behind the constable's back; warm hearth exposure.

### HUD / UI
- **Layout and state (UI1-UI5):** Persistent HUD (Health Bar ~75%, `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, `Johnny Cipher` level `4`, `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond, `[TAB] MAP [MMB] [HOLD] PING MENU`, `LAUNCH [LMB]`, `[HOLD] CRANK [RMB]`) with compass `SE` (KF25). Center reticle (UI2): `[F] PICK POCKET` above `[F] [HOLD] TAKEDOWN` (`03:15.00-03:17.00`, KF25#4, KF25#5). Light Gem bright white-gold (KF25#6, UI3 - fully lit by nearby hearth firelight) with no red player-noise arcs at `03:16.80` (quiet crouch; UI5 arcs read the player's own noise level). At `03:17.10` the `Guildhall Key` icon + label join the bottom-left HUD directly above `[1]` Zipwire.

### Gameplay and interactions
- Crouch stealth approach (G2): the player closes from the parlor doorway to directly behind the constable (`03:10.5-03:17.0`) without being noticed (G4).
- Pickpocket (G1): `[F] PICK POCKET` completes at `03:17.10`, acquiring the `Guildhall Key` (golden ornate key shimmer + HUD label, not a `!` marker).
- The stacked `[F] [HOLD] TAKEDOWN` option is offered (`03:15.00-03:17.00`) but not pulled in this segment (consumed in S23).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `03:03.0-03:07.3` | AU3 | Parquet footsteps & upright doorway walk | `pk=-28.82 dBFS` (`astats`); doc `pk=-28.8 dBFS` at `187.290 s` |
| `03:09.0-03:10.2` | AU3 | Upright walk through the parlor doorway | `pk=-31.7 dBFS` at `189.759 s` (KEYFRAME_INDEX §4, `astats`) |
| `03:10.5-03:17.0` | AU1 | Quiet crouch approach + roaring hearth crackle bed | 0.1 s window RMS `-68.76` to `-52.59 dBFS` (`astats.1s`); doc `-67.5 to -54.0 dBFS` |
| `03:17.1-03:18.2` | AU5 | Pickpocket `Guildhall Key`: metallic key jingle + acquisition chime | `pk=-23.56 dBFS` (`astats`); doc `pk=-23.6 dBFS` at `03:17.3` |
| `03:04.50-03:17.10` | AU1 | **Explicit BGM Absence:** zero background music score | hearth bed + parquet foley only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-28.82 dBFS` / `-51.67 dBFS` (`astats`); `I=-49.2 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Parlor geometry + hearth dressing | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Hearth fire light + flame VFX | #6, #14 | `HARD_LIMIT (HL-1)` | `HL-1` | `docs/HANDOFF_NEXT_SESSION.md:99, 113` |
| Constable clasped-hands idle + blue baton | #13 | `KNOWN_GAP (PG-7)` | `PG-7` | `docs/reports/guard-animations.md:131-143` |
| Pickpocket `Guildhall Key` off the guard | #13, #17 | `1:1_MATCH` | - | `game/src/ai/guard_ai.gd:5-160` |
| `[F]` prompts + `Guildhall Key` HUD row | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Hearth crackle, footsteps, key chime, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

*PG-2's `S03`/`S04`/`S06a`/`S06b`/`S11`/`S14`/`S15b` labels are port E2E test-scenario IDs (map_table, wardrobe, mission_prep, zipwire_crank, guard_lantern_alert, lockpick), not clip timeline segments.*

### What to check in the port recording
- [V1] Warm amber hearth pool on the herringbone parquet against the dark parlor corners.
- [V5] Constable at the hearth - clasped hands, glowing blue hip baton - unaware of the crouched approach.
- [UI2] `[F] PICK POCKET` over `[F] [HOLD] TAKEDOWN` (`03:15.00-03:17.00`); `[UI3]` `Guildhall Key` label appears above `[1]` at `03:17.10` (golden key shimmer, not `!`).
- [AU1] Hearth crackle bed with no BGM; `[AU5]` key jingle + acquisition chime at `03:17.10`.

## S23 - Guard Takedown (`03:17.10`-`03:22.00`, `4.90 s`)

**Keyframes:** KF26 (`03:20.20`) [clean](clean/KF26_03m20s_parlor_guard_takedown.jpg) · [annotated](annotated/KF26_03m20s_parlor_guard_takedown.jpg) - see CALLOUT_LEGENDS.md#kf26

### Narrative
Immediately after the pickup the constable begins turning (`03:17.40-03:17.60`) and the player holds `[F]` on `[HOLD] TAKEDOWN`: the 1P camera lunges and tilts close over the guard's helmet and armored shoulder (`03:17.80-03:20.60`), knocks him onto the parquet floor (KO `03:20.6-03:21.5`), then pulls back (`03:20.80-03:22.00`) leaving `[1]` Zipwire equipped.

### Visual
- **Environment / geometry (V4):** Fireplace Parlor; carved mantel with the classical bust on its shelf behind the grapple (KF26#1); herringbone wood parquet.
- **Lighting (V1):** Warm fireplace light illuminates the carved mantel and bust behind the tilted 1P takedown camera (KF26#1).
- **Sky / atmosphere / weather (V2):** Interior; none observed.
- **Materials / shaders (V3):** Dark padded uniform cloth, helmet shell, corded shoulder strap.
- **Characters / animation (V5):** 1P Guard Takedown grapple - camera tilts closely over the constable's helmet and corded shoulder (KF26#2, `03:17.80-03:20.60`); 1P gloved hands + ZipWire `[1]` lunge forward (KF26#4); the guard is knocked onto the parquet (`03:20.6-03:21.5`); camera pulls back (`03:20.80-03:22.00`).
- **VFX (V6):** None observed.
- **Camera / post (V7):** Scripted 1P lunge/tilt into the grapple and a pull-back to standing eye height; hearth-lit exposure.

### HUD / UI
- **Layout and state (UI1-UI5):** Persistent HUD with compass `SE`, Health Bar (~75% fill), `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, `Johnny Cipher` level `4`, `Guildhall Key` above `[1]` Zipwire (KF26), `[TAB] MAP [MMB] [HOLD] PING MENU`, `LAUNCH [LMB]`, `[HOLD] CRANK [RMB]`. Center reticle (UI2): `[F] [HOLD] TAKEDOWN` with its active circular hold-progress arc (KF26#3, UI5) through `03:20.60`. Light Gem stays bright pale-gold (KF26#5, UI3 - exposed by hearth firelight); no red player-noise arcs visible at `03:20.20` (UI5 arcs read the player's own noise level).

### Gameplay and interactions
- Guard takedown (G4): hold `[F]` `[HOLD] TAKEDOWN` from directly behind the constable as he starts turning (`03:17.40-03:17.60`); the grapple lunge spans `03:17.80-03:20.60` and the guard lands knocked out on the parquet (`03:20.6-03:21.5`).
- The trailing `Guildhall Key` acquisition from the `03:17.10` boundary completes over the first second of this segment.
- Camera pull-back (`03:20.80-03:22.00`) returns free control with `[1]` Zipwire still equipped (G3).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `03:18.8-03:19.7` | AU6 | Non-verbal melee grapple / exertion grunts (*"Ugh! / Ha!"*) | `pk=-23.73 dBFS` (`astats`); doc `pk=-23.7 dBFS` |
| `03:20.6-03:21.5` | AU5 | Melee Takedown: heavy blunt impact thud + guard pain / KO groan | `pk=-22.12 dBFS` at `03:20.9` (`astats.1s`); doc `pk=-22.1 dBFS` |
| `03:17.10-03:22.00` | AU1 | **Explicit BGM Absence:** zero background music score | 99 vertical transient columns at segment level; purely broadband melee SFX (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-22.12 dBFS` / `-43.44 dBFS` (`astats`); `I=-40.4 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| 1P takedown grapple animation | #11, #13 | `KNOWN_GAP (PG-7)` | `PG-7` | `docs/reports/guard-animations.md:131-143` |
| Guard knocked-out state | #13 | `1:1_MATCH` | - | `game/src/ai/guard_ai.gd:5-160` |
| Missing 1P idle/blend transitions around the grapple | #11 | `HARD_LIMIT (HL-4)` | `HL-4` | `docs/FIDELITY_GAPS.md:18, 55-59` |
| `[F] [HOLD] TAKEDOWN` hold-progress arc | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Grunts, impact thud, KO groan, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

*PG-2's `S03`/`S04`/`S06a`/`S06b`/`S11`/`S14`/`S15b` labels are port E2E test-scenario IDs (map_table, wardrobe, mission_prep, zipwire_crank, guard_lantern_alert, lockpick), not clip timeline segments.*

### What to check in the port recording
- [V5] 1P lunge/tilt over helmet and corded shoulder (`03:17.80-03:20.60`); guard down on parquet (`03:20.6-03:21.5`); pull-back (`03:20.80-03:22.00`).
- [UI5] Active circular hold-progress arc around the `[F] [HOLD] TAKEDOWN` reticle while the hold runs.
- [UI3] `Guildhall Key` HUD row persists above `[1]` Zipwire through the whole sequence.
- [AU6] Non-verbal grunts then blunt thud + KO groan (`pk=-22.1 dBFS`); no BGM.

## S24 - Foyer Approach & Sweeping Security Beams (`03:22.00`-`03:29.00`, `7.00 s`)

**Keyframes:** KF27 (`03:27.60`) [clean](clean/KF27_03m27s_foyer_security_beam.jpg) · [annotated](annotated/KF27_03m27s_foyer_security_beam.jpg) - see CALLOUT_LEGENDS.md#kf27

### Narrative
Over the downed constable, ThiefNisha says *"And stay down."* (`03:22.4-03:23.6`). The player crosses the parlor (`03:22.00-03:23.80`) into the checkered marble foyer (`03:24.00-03:28.90`): tall internally lit glass statue display case, velvet armchair with ottoman, square metallic floor plate, and a glowing cyan ceiling diamond node above the far double doors, while two horizontal white volumetric beams span wall-to-wall from a mid-height circular glowing white beam emitter on the left wall (`x~17%, y~40%`) and an overhead rotating security camera/spotlight is mounted high on the right wall above the `Basement Stairs` doorway. The beam is not crossed in this segment.

### Visual
- **Environment / geometry (V4):** Checkered marble foyer with dark carpet runner; tall glass display vitrine housing a bust beside a velvet armchair and ottoman; flush square metallic floor plate (KF27#2); far double doors; framed wall plaques.
- **Lighting (V1):** Dim foyer; glowing white wall emitter (KF27#1), cyan ceiling node glow (KF27#3), warm spill from the parlor behind.
- **Sky / atmosphere / weather (V2):** Interior; none observed.
- **Materials / shaders (V3):** Checker marble tiles, glass vitrine, metal floor plate, painted wood doors.
- **Characters / animation (V5):** None observed (no NPC in frame; 1P traversal only).
- **VFX (V6):** Two crisp horizontal white volumetric security beams from the left-wall emitter (KF27#1); glowing cyan diamond security/junction node above the far doors (KF27#3).
- **Camera / post (V7):** 1P walking camera with hard-sole gait across the marble; low-key interior exposure.

### HUD / UI
- **Layout and state (UI1-UI5):** Persistent HUD (Health Bar ~75%, `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, `Johnny Cipher` level `4`, `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond, `Guildhall Key` above `[1]` (KF27#5), `[TAB] MAP [MMB] [HOLD] PING MENU`, `LAUNCH [LMB]`, `[HOLD] CRANK [RMB]`) with compass `N` (KF27). Light Gem half-lit cream upper-left (KF27#6, UI3 - partially exposed) flanked by bright twin red player-noise arcs (KF27#7, UI5 - the player's own noise level, flaring with the marble footsteps). No new prompts; the beam tripwire lands exactly at `03:29.00` (S25).

### Gameplay and interactions
- Foyer traversal (G2): hard-sole walk from parquet onto checkered marble (`03:22.00-03:28.90`), passing the display case and floor plate toward the beams.
- Security system observed (G5): two horizontal beams scan wall-to-wall ahead of the far doors from the left-wall emitter; the crossing that trips the ward happens at `03:29.00` (S25).
- Overhead rotating security camera/spotlight (G5) sweeps from the right wall above the `Basement Stairs` doorway.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `03:22.4-03:23.6` | AU6 | ThiefNisha: *"And stay down."* | `pk=-32.61 dBFS` (`astats`); doc `pk=-32.6 dBFS` |
| `03:23.8-03:24.0` | AU3 | First crisp hard-sole marble footstep | `pk=-30.93 dBFS` at `03:23.8` (`astats.1s`); doc `-30.9 dBFS` |
| `03:23.8-03:28.9` | AU3 | Crisp hard-sole footsteps on the checkered marble floor | `pk=-28.91 dBFS` (`astats`); doc `pk=-28.9 dBFS` |
| `03:22.00-03:29.00` | AU1 | **Explicit BGM Absence:** zero background music score | marble foley + VO only; 138 transient columns in the footstep window (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-28.91 dBFS` / `-49.52 dBFS` (`astats`); `I=-47.6 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Foyer geometry + dressing | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Volumetric beams + emitter + cyan node VFX | #14, #17 | `HARD_LIMIT (HL-1)` | `HL-1` | `docs/HANDOFF_NEXT_SESSION.md:99, 113` |
| Security camera/spotlight sweep logic | #4, #17 | `HARD_LIMIT (HL-3)` | `HL-3` | `docs/HANDOFF_NEXT_SESSION.md:102` |
| *"And stay down."* VO + marble-surface footsteps | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |
| Persistent HUD + `Guildhall Key` row | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |

*PG-2's `S03`/`S04`/`S06a`/`S06b`/`S11`/`S14`/`S15b` labels are port E2E test-scenario IDs (map_table, wardrobe, mission_prep, zipwire_crank, guard_lantern_alert, lockpick), not clip timeline segments.*

### What to check in the port recording
- [V6] Two horizontal white volumetric beams from the left-wall emitter; glowing cyan ceiling diamond node above the far doors.
- [V4] Glass statue vitrine, velvet armchair + ottoman, square metallic floor plate on the checkered marble.
- [UI3] `Guildhall Key` HUD row above `[1]`; half-lit Light Gem with bright red player-noise arcs tracking the marble footsteps (the player's own noise level).
- [AU6] *"And stay down."* (`03:22.4-03:23.6`); `[AU3]` hard-sole marble footsteps (`pk=-28.9 dBFS`); no BGM.

## S25 - Beam Trigger, Purple Ward, Green Arcane Lock & Status Icons (`03:29.00`-`03:37.40`, `8.40 s`)

**Keyframes:** KF28 (`03:35.00`) [clean](clean/KF28_03m35s_foyer_arcane_barriers.jpg) · [annotated](annotated/KF28_03m35s_foyer_arcane_barriers.jpg) - see CALLOUT_LEGENDS.md#kf28

### Narrative
Crossing the foreground beam at `03:29.00` trips the foyer lockdown: (1) a bright purple crystalline arcane ward seals the forward foyer archway (in view `03:29.00-03:36.20`, KF28); (2) glowing green thorny/arcane vines erupt across the right `Basement Stairs` doorway (named on its framed wall plaque beside the doorway); (3) a white mechanical jaw/bear-trap circular icon appears above the Light Gem (`03:29.00+`), joined at `03:31.20+` by an orange-arc unconscious-head circular icon (`xx` eyes + `zz` + `>>`). The player turns left past the `WC` wall plaque on the far/back wall (visible far-left behind the purple ward at `03:29.00` and left of the player facing `NE` at `03:36.60-03:37.40`) toward the adjacent stairwell beam emitter (second emitter on the stairwell wall at `03:36.50`) as a cyan chest/safe icon appears through the wall.

### Visual
- **Environment / geometry (V4):** Checkered marble foyer; framed `Basement Stairs` plaque immediately left of the vine-sealed side doorway (KF28#3); `WC` plaque on the far/back wall; second beam emitter on the stairwell wall (`03:36.50`); plain dark grey/slate stair treads beyond (verified at `03:26.00`, `03:38.00`).
- **Lighting (V1):** Purple ward glow washes the marble and walls; green vine glow marks the side doorway.
- **Sky / atmosphere / weather (V2):** Interior; none observed.
- **Materials / shaders (V3):** Faceted purple crystalline barrier shards (KF28#2); emissive green thorny vines (KF28#5).
- **Characters / animation (V5):** None observed (the downed constable lies behind, out of frame).
- **VFX (V6):** Purple crystalline arcane ward sealing the main archway (KF28#2); green arcane vine lock across the `Basement Stairs` doorway (KF28#5); the white security beam continues projecting into the triggered ward (KF28#1).
- **Camera / post (V7):** 1P turn left along the foyer wall toward the stairwell emitter.

### HUD / UI
- **Layout and state (UI1-UI5):** Persistent HUD (compass `SE` at KF28, Health Bar ~75%, `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, `Johnny Cipher` level `4`, `Guildhall Key` above `[1]` Zipwire, `[TAB] MAP [MMB] [HOLD] PING MENU`, `LAUNCH [LMB]`, `[HOLD] CRANK [RMB]`). Status icons above the Light Gem (UI5): white mechanical jaw/bear-trap circular icon with countdown ring (`03:29.00+`) plus orange-arc unconscious-head circular icon (`xx` eyes + `zz` + `>>`) from `03:31.20+` (KF28#6). Light Gem half-lit cream upper-left (KF28#7, UI3), no red player-noise arcs visible at `03:35.00` (UI5 arcs read the player's own noise level). A cyan chest/safe icon becomes visible through the wall near the stairwell emitter (`UNCERTAIN:` exact marker semantics - observed only as a world-projected cyan chest/safe glyph).

### Gameplay and interactions
- Beam tripwire (G5): crossing the foreground beam at `03:29.00` triggers the ward lockdown - purple archway seal + `Basement Stairs` vine lock + jaw-trap status icon (`03:29.00+`); the unconscious-head icon follows at `03:31.20+` (second status-icon event).
- Perimeter move (G2): turns left past the `WC` plaque toward the stairwell beam emitter, sprinting `03:35.4-03:36.8`.
- Trap/status semantics of the jaw-trap icon stay `UNCERTAIN:` - it is displayed as a countdown-ringed status icon and no trap interaction occurs in the clip.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `03:29.1-03:29.6` | AU5 | Arcane Ward / tripwire trigger: resonant two-note metallic chime | `pk=-30.42 dBFS` (`astats`); doc `pk=-30.4 dBFS`; 74.7 / 332.5 / 254.9 / 435.1 Hz partials |
| `03:31.4-03:31.7` | AU5 | Crystalline barrier / sweeping beam activation: shimmering whoosh + electric pulse | `pk=-32.27 dBFS` over `03:31.3-03:35.3` (`astats`); doc `pk=-32.3 dBFS` |
| `03:33.5-03:35.3` | AU5 | Sustained low-frequency ward hum | 0.1 s window RMS `-62.68` to `-58.28 dBFS` (`astats.1s`); doc `-59 dBFS` |
| `03:35.4-03:36.8` | AU3 | Beam pulse + sprinting footsteps | inside the `03:31.3-03:35.3` + sprint span (`astats.1s`) |
| `03:29.00-03:37.40` | AU1 | **Explicit BGM Absence:** zero background music score | ward SFX + hum + footsteps only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-30.42 dBFS` / `-51.73 dBFS` (`astats`); `I=-49.7 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Purple ward + green vine barrier VFX | #14, #17 | `HARD_LIMIT (HL-1)` | `HL-1` | `docs/HANDOFF_NEXT_SESSION.md:99, 113` |
| Beam tripwire -> ward lockdown trigger | #17 | `HARD_LIMIT (HL-3)` | `HL-3` | `docs/HANDOFF_NEXT_SESSION.md:102` |
| Jaw-trap + unconscious-head status icons | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Tripwire chime, crystalline whoosh, ward hum | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |
| Foyer wall/plaque geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |

*PG-2's `S03`/`S04`/`S06a`/`S06b`/`S11`/`S14`/`S15b` labels are port E2E test-scenario IDs (map_table, wardrobe, mission_prep, zipwire_crank, guard_lantern_alert, lockpick), not clip timeline segments.*

### What to check in the port recording
- [V6] Purple crystalline ward seals the forward archway from `03:29.00`; glowing green thorny vines lock the `Basement Stairs` doorway.
- [UI5] Jaw/bear-trap icon (`03:29.00+`) plus orange-arc unconscious-head icon (`xx` + `zz` + `>>`, `03:31.20+`) stacked above the Light Gem.
- [V4] Framed `Basement Stairs` plaque beside the right doorway; `WC` plaque on the far/back wall.
- [AU5] Two-note tripwire chime (`pk=-30.4 dBFS`), crystalline whoosh, ward hum (`-59 dBFS`); no BGM.

## S26 - Crimson Alarm Spotlight & Slate Staircase Ascent (`03:37.40`-`03:41.90`, `4.50 s`)

**Keyframes:** KF29 (`03:39.40`) [clean](clean/KF29_03m39s_stairs_crimson_alarm.jpg) · [annotated](annotated/KF29_03m39s_stairs_crimson_alarm.jpg) - see CALLOUT_LEGENDS.md#kf29

### Narrative
The wall security spotlight bathes the 1P arms/ZipWire and the dark grey/slate staircase treads (verified plain dark grey/slate at `03:26.00`, `03:38.00`, and `03:40.50-03:41.00`) in intense crimson alarm light (`03:38.20-03:39.60`, with brief blue/purple 1P glove highlights at `03:37.60` and `03:39.40-03:39.60`), creating a temporary red cast across the lower steps at `03:39.40-03:39.60`. The player ascends (`03:39.60-03:41.20`) with the `CRANK [LMB]` center reticle and `[HOLD] CRANK [RMB]` bottom-right, red player-noise arcs (`03:38.00`, `03:40.50`), and a re-triggered white mechanical jaw-trap status icon (3rd status-icon event, same curved jaw/claw graphic inside a partial countdown ring) above the Light Gem (`03:38.07-03:41.87`, until the Pause Menu hides the HUD at `03:41.89`; absent at `03:37.95-03:38.04`), reaching the upper landing gallery (`03:41.40-03:41.85`).

### Visual
- **Environment / geometry (V4):** Plain dark grey/slate staircase treads (KF29#1), handrails, upper landing gallery with framed pictures; unlit slate remains visible outside the alarm cone.
- **Lighting (V1):** Intense crimson alarm spotlight from the wall security fixture washes the lower steps (`03:38.20-03:39.60`, KF29#2); brief blue/purple glove highlights (`03:37.60`, `03:39.40-03:39.60`).
- **Sky / atmosphere / weather (V2):** Interior; none observed.
- **Materials / shaders (V3):** Plain dark grey/slate treads with worn nosings; metal/wood handrail; dark stairwell walls.
- **Characters / animation (V5):** 1P gloved hands + ZipWire `[1]` launcher lit crimson (KF29#5) during the rapid ascent (`03:39.60-03:41.20`).
- **VFX (V6):** None observed (the crimson cast is spotlight lighting, not a particle effect).
- **Camera / post (V7):** 1P ascent camera tilting up the stair run to the landing gallery (`03:41.40-03:41.85`); exposure under the crimson wash.

### HUD / UI
- **Layout and state (UI1-UI5):** Persistent HUD (compass `E` at KF29, Health Bar ~75%, `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]`, `Johnny Cipher` level `4`, `Guildhall Key` above `[1]` Zipwire, `[TAB] MAP [MMB] [HOLD] PING MENU`, `LAUNCH [LMB]`, `[HOLD] CRANK [RMB]`). Center reticle (UI2): six-tick circular `CRANK [LMB]` prompt (KF29#3) through the ascent. Re-triggered white mechanical jaw-trap status icon with partial countdown ring above the Light Gem (KF29#4, UI5) at `03:38.07-03:41.87` (3rd status-icon event). Light Gem fully lit cream-white (KF29#6, UI3 - exposed under the alarm light); red player-noise arcs flare at `03:38.00` and `03:40.50` (UI5 - the player's own noise level, tracking the stair run and ZipWire clack). The whole HUD is hidden at `03:41.89` by the Pause Menu.

### Gameplay and interactions
- Staircase ascent (G2) with `[1]` Zipwire held ready (G3): rapid steps up the slate run `03:39.60-03:41.20`, landing gallery reached `03:41.40-03:41.85`.
- The `CRANK [LMB]` center reticle reflects the equipped ZipWire `[1]` (KF29#3, KF29#5) - no crank action is completed before the Pause Menu.
- Jaw-trap status icon re-trigger (G5): third status-icon event (`03:38.07-03:41.87`, absent `03:37.95-03:38.04`).

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `03:37.7-03:38.2` | AU5 | Loud crystalline barrier impact / shatter + sharp alert sting | `pk=-23.54 dBFS` (`astats`); doc `pk=-23.5 dBFS` - segment maximum |
| `03:38.3-03:41.8` | AU3 | Rapid footsteps up the dark grey / slate grand stairs + ZipWire clack | `pk=-24.46 dBFS` (`astats`); doc `pk=-24.5 dBFS` |
| `03:40.1-03:41.8` | AU1 | Quieting at the upper landing gallery | 0.1 s window RMS falls to `-60.88 dBFS` minimum (`astats.1s`) |
| `03:37.40-03:41.90` | AU1 | **Explicit BGM Absence:** zero background music score | barrier shatter + stair foley only (`showspectrumpic`) |
|  |  | Re-measured segment peak / RMS | `-23.54 dBFS` / `-43.64 dBFS` (`astats`); `I=-38.1 LUFS` (`ebur128`) - loudest segment in range |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Slate stair treads + handrail geometry | #3, #4 | `1:1_MATCH` | - | `docs/FIDELITY_GAPS.md:38` |
| Crimson alarm spotlight lighting | #6 | `1:1_MATCH` | - | `game/src/core/level_loader.gd:68-112, 2133-2185` |
| Stairs traversal fix (`50°` / `0.3` snap) | #10 | `UNVERIFIED_LIVE` | `PG-4` | `docs/HANDOFF_NEXT_SESSION.md:112` |
| ZipWire `[1]` + `CRANK [LMB]` reticle (`S11 zipwire_crank` PG-2 scenario id) | #11, #12, #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/HANDOFF_NEXT_SESSION.md:111` |
| Re-triggered jaw-trap status icon | #15 | `KNOWN_GAP (PG-2)` | `PG-2` | `docs/FIDELITY_GAPS.md:198` |
| Shatter sting, slate footsteps, clack, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |

*PG-2's `S03`/`S04`/`S06a`/`S06b`/`S11`/`S14`/`S15b` labels are port E2E test-scenario IDs (map_table, wardrobe, mission_prep, zipwire_crank, guard_lantern_alert, lockpick), not clip timeline segments.*

### What to check in the port recording
- [V1] Intense crimson alarm wash (`03:38.20-03:39.60`) over plain dark grey/slate treads (unlit slate above); brief blue/purple glove highlights (`03:37.60`, `03:39.40-03:39.60`).
- [UI2] `CRANK [LMB]` six-tick center reticle during the ascent; `[UI5]` re-triggered jaw-trap icon (`03:38.07-03:41.87`) above the Light Gem.
- [V5] 1P ZipWire `[1]` + gloved hands in the crimson spotlight during the rapid stair run (`03:39.60-03:41.20`).
- [AU5] Barrier shatter + alert sting (`pk=-23.5 dBFS`); `[AU3]` slate footfalls + ZipWire clack (`03:39.8`); no BGM.

## S27 - Pause Menu & Quit (`03:41.90`-`03:45.64`, `3.74 s`)

**Keyframes:** KF30 (`03:43.20`) [clean](clean/KF30_03m43s_pause_menu.jpg) · [annotated](annotated/KF30_03m43s_pause_menu.jpg) - see CALLOUT_LEGENDS.md#kf30

### Narrative
Exact Pause Menu entry at `03:41.90`: darkened blurred gameplay backdrop with a centered teal/copper Art-Nouveau bordered modal containing `RESUME`, `SETTINGS`, `RETURN TO THIEF'S DEN` (straight apostrophe), and `QUIT TO DESKTOP`; bottom-left footer `1.5.148559   Novice   1025051536`. A single cursor hovers `QUIT TO DESKTOP` cleanly (`03:43.10-03:43.30`), followed by a frozen multi-cursor capture trail (`03:43.70-03:45.64`) as the recording ends.

### Visual
- **Environment / geometry (V4):** None observed (full-screen modal over the blurred level).
- **Lighting (V1):** Darkened, blurred gameplay backdrop (KF30#1); modal area lit for legibility.
- **Sky / atmosphere / weather (V2):** None observed.
- **Materials / shaders (V3):** Teal/copper Art-Nouveau corner filigree on the modal border (KF30#1).
- **Characters / animation (V5):** None observed.
- **VFX (V6):** None observed (the trailing cursor smear at `03:43.70+` is a capture artifact).
- **Camera / post (V7):** Darkened blurred gameplay backdrop (KF30#1) behind the static modal.

### HUD / UI
- **Layout and state (UI1-UI5):** Pause modal (UI1): four centered vertical items `RESUME`, `SETTINGS`, `RETURN TO THIEF'S DEN` (straight apostrophe), `QUIT TO DESKTOP` (KF30#2); bottom-left footer `1.5.148559   Novice   1025051536` (KF30#5). Single cursor hovers `QUIT TO DESKTOP` at `03:43.10-03:43.30` (KF30#3, clean at `03:43.20` before the `03:43.70+` multi-cursor trail). The gameplay HUD is hidden from `03:41.89` (Light Gem faintly visible blurred in the backdrop).

### Gameplay and interactions
- Pause entry (G5): game suspends at `03:41.90` on the upper landing gallery reached at the end of S26.
- Menu navigation (G5): cursor travels to `QUIT TO DESKTOP`, hovering cleanly (`03:43.10-03:43.30`) and selecting (`03:43.2-03:43.6`); the recording does not show a return to gameplay.

### Audio

| Time | Layer (AU1-AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| `03:41.8` | AU4 | Pause modal click | `pk=-35.63 dBFS` over `03:41.8-03:42.8` (`astats`); doc `pk=-35.6 dBFS` |
| `03:41.9-03:42.7` | AU1 | Gameplay ambience ducking under the pause modal | 0.1 s window RMS `-54.90` -> `-72.44 dBFS` = `-17.5 dB` (`astats.1s`); doc `-19 dB`, `-53` -> `-72.4 dBFS` |
| `03:43.2-03:43.6` | AU4 | UI hover + selection click on `QUIT TO DESKTOP` | `pk=-34.21 dBFS` at `03:43.5` (`astats.1s`); doc `pk=-34.2 dBFS` |
| `03:43.80-03:45.64` | AU1 | **Complete digital silence** (recording tail after Quit) | `astats.1s` peak/RMS = `-inf` for all 19 windows; direct PCM read = `100.000%` exactly-zero samples |
| `03:41.90-03:45.64` | AU1 | **Explicit BGM Absence:** zero background music score | pause click + duck + quit click, then digital zero (`showspectrumpic` empty over the tail) |
|  |  | Re-measured segment peak / RMS | `-34.21 dBFS` / `-58.70 dBFS` (`astats`); `I=-52.1 LUFS` (`ebur128`) |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| Pause modal + 4-button stack | #15 | `1:1_MATCH` | - | `game/src/ui/hud.gd:1513-1580` |
| Build/difficulty/seed footer `1.5.148559   Novice   1025051536` | #15 | `NOT_IMPLEMENTED` | - | `game/src/ui/hud.gd:23, 1595-1603` |
| Ambience duck + UI hover/click audio | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:29-37` |
| Quit-to-desktop teardown | #1 | `UNVERIFIED_LIVE` | `PG-1` | `docs/HANDOFF_NEXT_SESSION.md:21, 112` |

*PG-2's `S03`/`S04`/`S06a`/`S06b`/`S11`/`S14`/`S15b` labels are port E2E test-scenario IDs (map_table, wardrobe, mission_prep, zipwire_crank, guard_lantern_alert, lockpick), not clip timeline segments.*

### What to check in the port recording
- [UI1] Pause modal: `RESUME`, `SETTINGS`, `RETURN TO THIEF'S DEN` (straight apostrophe), `QUIT TO DESKTOP`; footer `1.5.148559   Novice   1025051536`.
- [V7] Darkened blurred gameplay backdrop with the teal/copper Art-Nouveau modal frame.
- [UI1] Clean single-cursor hover on `QUIT TO DESKTOP` (`03:43.10-03:43.30`) before the frozen multi-cursor trail (`03:43.70+`).
- [AU4] Pause click + `-19 dB` ambience duck (`-53 -> -72.4 dBFS`); `[AU1]` digital silence `-240.0 dBFS` from `03:43.80` to `03:45.64`; no BGM.
