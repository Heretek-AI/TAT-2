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
| Menu stack (PLAY/SETTINGS/CREDITS/QUIT) | #15 | `1:1_MATCH` | - | `docs/HANDOFF_NEXT_SESSION.md:47` |
| Rain bed, click, zero BGM | #16 | `KNOWN_GAP (PG-6)` | `PG-6` | `game/src/core/audio_manager.gd:6-14` |
| CineCamera framing | #9 | `1:1_MATCH` | - | `docs/HANDOFF_NEXT_SESSION.md:47` |

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
| Loading art + spinner | #15 | `1:1_MATCH` | - | `docs/HANDOFF_NEXT_SESSION.md:47` |
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
