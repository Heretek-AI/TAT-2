# TAT-2 Reference Baseline — Official Footage `clip_1,795,033,698,901.mp4`

Master index and comparison framework for the **official UE5 gameplay footage** that serves as the
fidelity target for **TAT-2**, the Godot 4.7 Forward+ port of *Thick As Thieves*. The corpus lives under
`docs/reference/clip_1795033698901/`; the source recording is
`$HOME/Videos/clip_1,795,033,698,901.mp4` (always quote the path — it contains commas).

Authority order when sources disagree (highest wins): the 4K source video → `KEYFRAME_INDEX.md` →
`BREAKDOWN.md` → `callout_spec.json` / `CALLOUT_LEGENDS.md` → repo docs (`docs/HANDOFF_NEXT_SESSION.md`,
`docs/FIDELITY_GAPS.md`, `docs/reports/*.md`). Evidence rule: only what is visible in a frame or backed by
measured audio evidence is claimed; anything unclear is marked `UNCERTAIN:`.

> **Provenance note (W0a, 2026-11-24):** `Johnny Cipher`, wherever it appears in
> this corpus, is the Steam account persona of the machine that recorded the
> reference clip. It is not shipped game copy: the shipped card/ledger bind
> `PlayerState.GetPlayerName`, and the authored thief titles are `The Spider`
> and `The Chameleon`. The observed frame quotes in this file and its linked
> corpus are left unchanged; the port reads the live player handle and falls
> back to the authored title, never the capture persona.

---

## 1. Purpose and how to use it

This document is the master index of the official-footage reference baseline. It (a) inventories every
deliverable of the corpus, (b) states the clip's hard facts, (c) summarizes the 27-segment timeline,
(d) documents how the evidence was produced and what its blind spots are, and (e) provides the
cross-reference matrices (TAT-2 subsystems `#1–#18`, parity gaps `PG-1..PG-8`, hard limits `HL-1..HL-9`)
plus a comparison-ready 4-pillar checklist.

Use it like this:

- **Port developers** read §3–§7 to know what the official build does on this route and where the port
  is already known to differ (each expected difference carries a `PG-n` / `HL-n` tag with a verified citation).
- **The port recording session** follows the §9 route script and capture protocol to produce a port clip
  of the same 27-beat route, aligned by the 27 anchor events.
- **The comparison session** scores the §8 checklist row by row following the §10 workflow, filling the
  blank Port observation / Score columns and mirroring results into
  `reference/clip_1795033698901/COMPARISON_TEMPLATE.md`.
- **Verification** results land in the `## Verification log` at the end of this file (populated in Wave 4).

Per-segment ground truth (narrative, verbatim UI, audio dBFS, per-element parity tags, and
"what to check in the port recording" bullets) lives in `BREAKDOWN.md`, not here; this file indexes it.

## 2. Deliverable map

| Artifact | Link | Status | Contents |
|---|---|---|---|
| Keyframe index | [reference/clip_1795033698901/KEYFRAME_INDEX.md](reference/clip_1795033698901/KEYFRAME_INDEX.md) | Done (M1+M2) | `ffprobe`/`ebur128` clip metadata; contiguous segment table `S01–S27`; `KF01–KF30` extraction table; audio/VO cue table (§4); verbatim UI text + discrepancy resolutions (§5); `## Errata`. |
| Exhaustive breakdown | [reference/clip_1795033698901/BREAKDOWN.md](reference/clip_1795033698901/BREAKDOWN.md) | Done (Wave 1+2 merge) | Continuous `S01–S27` account: narrative, visual (V1–V7), HUD (UI1–UI5), gameplay (G1–G5), audio tables (AU1–AU6, `astats`-remeasured), TAT-2 cross-reference tables, per-segment port-recording checks. |
| Callout legends | [reference/clip_1795033698901/CALLOUT_LEGENDS.md](reference/clip_1795033698901/CALLOUT_LEGENDS.md) | Done (M2) | 30 sections / 195 rows: per-KF numbered legend tables matching the rendered badges; HUD semantics glossary; code taxonomy. |
| Callout spec (source of truth) | [reference/clip_1795033698901/callout_spec.json](reference/clip_1795033698901/callout_spec.json) | Done (schema `1.1`) | `195` callouts across `KF01–KF30` (`4–8` per KF): targets, anchors, labels, codes, `observed_ue5_detail`, `hud_exclusions`. |
| Clean keyframes | [reference/clip_1795033698901/clean/](reference/clip_1795033698901/clean/) | Done (M1, never modify) | 30 pristine `1920x1080` JPEGs (`KF01..KF30_*.jpg`) for side-by-side comparison. |
| Annotated keyframes | [reference/clip_1795033698901/annotated/](reference/clip_1795033698901/annotated/) | Done (M2) | 30 deterministic `1920x1080` JPEGs with numbered badges (Amber/Cyan/Magenta), leader lines, and label pills. |
| Tools | [reference/clip_1795033698901/tools/](reference/clip_1795033698901/tools/) | Partial | `render_annotations.py` (deterministic renderer; `--check`, `--emit-legends`) and `merge_callout_specs.py`. `verify_baseline.py` (M4) and `make_side_by_side.sh` (Wave 3) are planned additions in the same folder. |
| Comparison template | [reference/clip_1795033698901/COMPARISON_TEMPLATE.md](reference/clip_1795033698901/COMPARISON_TEMPLATE.md) | **Pending (Wave 3)** | Blank 1:1 scorecard mirroring §8, 27 per-segment official/port image slots, alignment-offset table, summary table. The link activates once the file is created. |
| Port state (related) | [docs/HANDOFF_NEXT_SESSION.md](HANDOFF_NEXT_SESSION.md) | Live doc | Ground truth for TAT-2 port status, subsystems, parity gaps, hard limits. |
| Fidelity tracker (related) | [docs/FIDELITY_GAPS.md](FIDELITY_GAPS.md) | Live doc | Coverage table and hard-limit notes backing the §6/§7 citations. |

## 3. Clip facts

All values verified from the native source (matching `KEYFRAME_INDEX.md` §1).

| Property | Verified value |
|---|---|
| Source file | `$HOME/Videos/clip_1,795,033,698,901.mp4` (265,161,125 bytes; 9.40 Mbps overall) |
| Duration | `225.642333 s` (`03:45.64`), `start_time: 0.000000` |
| Video | `3840x2160` H.264 High (`avc1.640034`, level 52), 16:9, `yuvj420p` / `bt709` |
| Frame rate | `r_frame_rate 179/6` (`29.833 fps`); **avg `29.672 fps`**; `nb_frames 6,696` |
| Audio | AAC LC (`mp4a.40.2`), `48 kHz` stereo (`fltp`), stream `start_time 0.277 s`, `duration 225.365 s` |
| Loudness (`ebur128`) | Integrated **`I: -43.9 LUFS`**; Loudness Range `LRA: 16.7 LU` |
| Game build (KF30 pause footer) | `1.5.148559`, difficulty `Novice`, seed `1025051536` |
| Mission on this route | `CONSTABLES' GUILDHALL` — `Cleanout Heist`, `Time Limit: 55 minutes`, Mode `Solo`, Difficulty `Novice` |
| Keyframes | 30 clean + 30 annotated `1920x1080` JPEGs; 195 verified callouts |
| Segments | `S01–S27`, strictly contiguous `00:00.00 → 03:45.64`, zero gaps or overlaps |

## 4. Timeline at a glance

| Seg | Start | End | Dur (s) | Scene / UI state | Keyframes |
|---|---|---|---|---|---|
| S01 | `00:00.00` | `00:02.15` | 2.15 | Startscreen (`MainMenu`): rainy neon street, menu stack | KF01 (`00:01.00`) |
| S02 | `00:02.15` | `00:02.60` | 0.45 | Loading Screen 1 (illustrated skyline) | — (layout identical to KF12) |
| S03 | `00:02.60` | `00:06.57` | 3.97 | Thieves' Den initial entry (timber attic) | KF02 (`00:04.50`) |
| S04 | `00:06.57` | `00:18.24` | 11.67 | Wardrobe UI (character + loadout + cosmetics) | KF03 (`00:07.00`), KF04 (`00:16.50`) |
| S05 | `00:18.24` | `00:26.58` | 8.34 | Den exploration: telescope view + Wanted posters | KF05 (`00:20.80`), KF06 (`00:24.60`) |
| S06 | `00:26.58` | `00:38.17` | 11.59 | Ledger UI (`JOURNAL` & `BLACK MARKET`) | KF07 (`00:27.00`), KF08 (`00:28.50`) |
| S07 | `00:38.17` | `00:51.08` | 12.91 | Den props, decals & Gramophone (only music in clip) | KF09 (`00:46.25`) |
| S08 | `00:51.08` | `00:56.08` | 5.00 | Map Table & confirmation modal | KF10 (`00:52.35`) |
| S09 | `00:56.08` | `01:04.80` | 8.72 | Mission Preparation & 6 s countdown | KF11 (`01:00.30`) |
| S10 | `01:04.80` | `01:09.44` | 4.64 | Loading Screen 2 (true digital silence) | KF12 (`01:06.50`) |
| S11 | `01:09.44` | `01:10.81` | 1.37 | Briefing Letter (11-line parchment) | KF13 (`01:10.00`) |
| S12 | `01:10.81` | `01:20.10` | 9.29 | Guildhall safe-room overlook & catwalk (HUD fade-in) | KF14 (`01:15.75`) |
| S13 | `01:20.10` | `01:39.30` | 19.20 | Street/alley approach, vintage car & gate alert | KF15 (`01:21.38`) |
| S14 | `01:39.30` | `01:49.50` | 10.20 | ZipWire `[1]` equip, gate headlights, 1st launch & ledge chest | KF16 (`01:40.20`) |
| S15 | `01:49.50` | `01:58.50` | 9.00 | 2nd ZipWire launch & crank ascent | KF17 (`01:51.20`) |
| S16 | `01:58.50` | `02:11.00` | 12.50 | Roofline traversal & 3rd ZipWire to gate pillar | — (no keyframe; clip-frame evidence) |
| S17 | `02:11.00` | `02:23.30` | 12.30 | Gate pillar gear plate & courtyard crate descent | KF18 (`02:14.80`) |
| S18 | `02:23.30` | `02:30.70` | 7.40 | Smoke Bomb `[2]` equip, throw & plume (first fall damage at `02:23.30`) | KF19 (`02:25.40`), KF20 (`02:29.20`) |
| S19 | `02:30.70` | `02:33.00` | 2.30 | Vistara Diamond `[4]` equip & scan pulse (RED→GREEN guard) | KF21 (`02:32.20`), KF22 (`02:33.00`) |
| S20 | `02:33.00` | `02:54.50` | 21.50 | Side wing, `MACLEOD` sign & terrace patrol | KF23 (`02:41.00`) |
| S21 | `02:54.50` | `03:04.50` | 10.00 | Arched portico, blue double doors & scaffolding | KF24 (`03:00.60`) |
| S22 | `03:04.50` | `03:17.10` | 12.60 | Fireplace parlor stealth & pickpocket (`Guildhall Key`) | KF25 (`03:16.80`) |
| S23 | `03:17.10` | `03:22.00` | 4.90 | Guard takedown (KO) | KF26 (`03:20.20`) |
| S24 | `03:22.00` | `03:29.00` | 7.00 | Foyer approach & sweeping security beams | KF27 (`03:27.60`) |
| S25 | `03:29.00` | `03:37.40` | 8.40 | Beam trigger, purple ward, green arcane lock & status icons | KF28 (`03:35.00`) |
| S26 | `03:37.40` | `03:41.90` | 4.50 | Crimson alarm spotlight & slate staircase ascent | KF29 (`03:39.40`) |
| S27 | `03:41.90` | `03:45.64` | 3.74 | Pause Menu & quit | KF30 (`03:43.20`) |

```mermaid
flowchart LR
    S01["S01 Startscreen"] --> S02["S02 Loading 1"]
    S02 --> S03["S03 Den entry"]
    S03 --> S04["S04 Wardrobe"]
    S04 --> S05["S05 Telescope / Wanted"]
    S05 --> S06["S06 Journal / Black Market"]
    S06 --> S07["S07 Gramophone"]
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

## 5. Methodology

### 5.1 Keyframe selection

`KF01–KF30` were picked at representative instants — one per major UI state, gameplay beat, or alert
moment — covering 25 of the 27 segments directly; `S02` shares `KF12`'s identical loading-art layout and
`S16` has no keyframe (covered by clip-frame extraction in `BREAKDOWN.md`). Frames were pulled from the
native `3840x2160` source as PNG, then downscaled with Pillow `13.0.0` `LANCZOS` to `1920x1080` JPEG
(`quality=90, optimize=True`) under `clean/` (30 files, 5.90 MiB total, every file `< 344 KB`).

### 5.2 Annotation colour and code system

Each keyframe was annotated with numbered badges (28 px circles), leader lines, and label pills:
**Amber `#FFB300` = Visual (`V*`)**, **Cyan `#00E5FF` = HUD/UI (`UI*`)**, **Magenta `#FF4081` =
Gameplay/Audio (`G*`/`AU*`)**. `callout_spec.json` (schema `1.1`) is the single source of truth —
`195` callouts across 30 keyframes, `4–8` per keyframe, every visible-HUD frame carrying at least one
`UI*` callout and every frame at least one `G*`/`AU*` callout naming its audio state (including explicit
"no BGM" rows). Code usage across the 195 callouts: `UI3` 30, `UI4` 24, `V4` 23, `UI2` 15, `V1` 14,
`UI5` 10, `AU5` 9, `V2` 8, `G4`/`AU4` 7, `V6`/`G1`/`G3`/`AU1` 6, `V5`/`AU3`/`V7`/`G5` 4–2, `V3` 1, …
Images and legends regenerate deterministically (byte-identical) with:

```bash
/usr/bin/python3 docs/reference/clip_1795033698901/tools/render_annotations.py            # render annotated/
/usr/bin/python3 docs/reference/clip_1795033698901/tools/render_annotations.py --check     # validate 30/30
/usr/bin/python3 docs/reference/clip_1795033698901/tools/render_annotations.py --emit-legends
```

| Code | Pillar | Meaning |
|---|---|---|
| `V1` | Visual | Lighting: key/fill, practicals, neon, volumetrics, shadows |
| `V2` | Visual | Sky, atmosphere, fog, weather (rain, wetness, puddles) |
| `V3` | Visual | Materials and shaders: albedo, roughness, glass, emissive |
| `V4` | Visual | Geometry and level dressing: architecture, props, layout |
| `V5` | Visual | Characters and animation: 1P hands/tools, NPCs, takedowns |
| `V6` | Visual | VFX and particles: smoke, sparks, barriers, beams |
| `V7` | Visual | Camera and post: FOV, framing, motion, exposure, grade |
| `UI1` | HUD/UI | Front-end menus (Startscreen, Pause, Settings) |
| `UI2` | HUD/UI | In-world interaction prompts |
| `UI3` | HUD/UI | Persistent HUD: player card, compass, tools, health, Light Gem |
| `UI4` | HUD/UI | Full-screen panels: Wardrobe, Journal, Market, Map, Briefing |
| `UI5` | HUD/UI | Alerts and feedback: player-noise arcs, guard-alert pips, status icons, alarms, countdowns |
| `G1` | Gameplay | Interactables and stations (den, doors, loot, scope) |
| `G2` | Gameplay | Traversal and movement (zipwire, climb, stairs) |
| `G3` | Gameplay | Tools and abilities (smoke bomb, zipwire gun) |
| `G4` | Gameplay | AI and guards: patrol, perception, alert, takedowns |
| `G5` | Gameplay | Hazards and mission flow: beams, barriers, traps |
| `AU1` | Audio | Ambience and room tone, plus explicit BGM absence |
| `AU2` | Audio | Music (gramophone jazz around `00:44–00:50`) |
| `AU3` | Audio | Footsteps and foley (surface-specific) |
| `AU4` | Audio | UI audio (clicks, hovers, countdown ticks, confirms) |
| `AU5` | Audio | Gameplay SFX (tools, smoke, diamond, alarm, horn) |
| `AU6` | Audio | Voice: VO, barks, dialogue (verbatim quotes) |

### 5.3 HUD semantics glossary (user-confirmed)

- **Light Gem (`UI3`, bottom-center):** shows how much light is on the player **and from which direction**.
  The warm lit sector's size = light amount; its position within the gem = the direction the light comes
  from. Bright = exposed, dark = concealed. It is not a detection meter.
- **Red player-noise arcs (`UI5`, flanking the gem):** show how much sound the player is making
  (large/bright = loud, absent = quiet). They track player movement noise only, not guard proximity.
- **Guard-alert direction pips (`UI5`, e.g. the three-dash crimson pip in `KF17` at `x~1195, y~832`):**
  distinct guard-perception indicators showing the direction of an alerted guard; separate from the
  player-noise arcs (no gem arcs are present in `KF17`).
- Guard awareness is therefore shown by its own elements (alert pips, guard-side yellow alert bars,
  Vistara RED→GREEN highlight states), never by the Light Gem or its arcs.

### 5.4 Audio method and blind-spot disclosure

**No direct listening was possible.** Every audio claim in this corpus is phrased from measured
`ffmpeg` evidence plus the verified `KEYFRAME_INDEX.md` §4 cue table:

- Per-segment `astats` peak/RMS re-measurement in `0.1 s` reset windows (dBFS values quoted per cue);
  `ebur128` integrated loudness per segment.
- `showspectrumpic` spectrograms classify beds: broadband noise = rain/wind; harmonic sustained bands =
  music; sharp transients = clicks/footsteps/impacts. Explicit BGM absence was verified this way for
  every segment (the only music in the clip is the diegetic Gramophone record in `S07`).
- Verbatim VO quotes were resolved through a `220–5000 Hz` bandpass; syllables masked by overlapping
  SFX are bracketed (e.g. *"[Bit / You're] too loud, [thief?]."*); anything not directly evidenced is
  marked `UNCERTAIN:`.

Known blind spots, stated honestly: reverb character is inferred from spectra, not audition; distant/overlapping
VO lines rely on the bandpass resolution recorded in `KEYFRAME_INDEX.md` §4; no claim anywhere in this corpus
rests on unaided listening.

### 5.5 ID namespaces (disambiguation)

`S01–S27` are **always clip-timeline segments** (`KEYFRAME_INDEX.md` §2 is the boundary authority).
The `S03/S04/S06a/S06b/S11/S14/S15b` labels appearing inside `PG-2` (map_table, wardrobe, mission_prep,
zipwire_crank, guard_lantern_alert, lockpick) are **TAT-2 port E2E test-scenario IDs** from
`build/qa/capture_e2e_parity.sh` — never clip segments; e.g. `S14` under `PG-2` is the port
`guard_lantern_alert` test, not clip segment `S14` (1st zipwire). `PG-n` are parity-gap IDs, `HL-n`
hard-limit IDs, `#n` subsystem IDs. Parity status enum: `1:1_MATCH` | `APPROX_SHADER` |
`KNOWN_GAP (PG-n)` | `HARD_LIMIT (HL-n)` | `UNVERIFIED_LIVE` | `NOT_IMPLEMENTED`.

## 6. TAT-2 Subsystem matrix (#1–#18)

Key-file citations were re-opened read-only and verified line-by-line
(`_build/citations_verified.md`, including corrections C1–C8). "Overall parity status" uses the §5.5
enum; `N/A` marks subsystems that cannot be observed in a PC gameplay capture (per the §8 Score enum).

| # | Subsystem | Key files (verified) | Clip segments / keyframes where observed | Overall parity status | Notes |
|---|---|---|---|---|---|
| 1 | Project Config & Autoloads | `game/project.godot:13-20` (6 autoloads), `:43-158` (input map) | S27 (quit-to-desktop teardown flow; engine config itself not clip-observable) | `UNVERIFIED_LIVE` | Quit-to-desktop teardown is the `PG-1` crash surface; `debug_autostart_contract` verified absent. |
| 2 | Asset Extraction & Normalization Pipeline | `docs/HANDOFF_NEXT_SESSION.md:31-36`; `docs/FIDELITY_GAPS.md:11-34`; `docs/ARCHITECTURE.md:41-60` | Not clip-observable (pipeline); outputs visible in every segment | `N/A` | 13,162 packages / 2,045 GLB / 2,416 PNG / 995 anims / 5,018 Wwise OGGs; manifest coverage 99.4%. |
| 3 | 32 m XZ Chunking, Batching, Culling & Collision | `game/src/core/level_loader.gd:51-67, 132-135`; `docs/PERFORMANCE.md:10-63` | S01, S03, S05, S07–S09, S12–S22, S24–S26 (all environment segments) | `1:1_MATCH` | 32 m cells; visibility 22/45/95 m; caps 768/384/32000; PeripheryA collidable, SkyboxGeo excluded. |
| 4 | Packed Level Actors & LevelInstances | `docs/HANDOFF_NEXT_SESSION.md:40`; `docs/reports/packed-level-instances.md:10-169` | Same geometry segments as #3; S24 security-camera rig (KF27 #4) | `1:1_MATCH` | 39 `BPP_PL_*` / 3,210 components / 30,127 `PerInstanceSMData` / 138 sublevels at authored transforms. |
| 5 | Landscape Heightmaps, Dual Weightmaps & Puddle/Wetness | `game/src/core/tat_landscape.gdshader:1-129`; `level_loader.gd:15-24`; `docs/reports/landscape-weightmaps.md:1-405` | S01 cobbles (KF01); S13–S20 exteriors (tagged #3/#4/#8 there) | `1:1_MATCH` | 5 colour slots + Puddle normal/opacity + `GroundWet` darkening; splines/grass remain (HL-8). |
| 6 | Linear Light Scale, Spawn Priority & Budget | `level_loader.gd:68-96, 2152`; `docs/reports/lighting-intensity.md:1-279` | S03, S05, S12–S13, S15–S17, S20–S22, S26 (KF29 alarm spotlight) | `1:1_MATCH` | Authored `Intensity` maps linearly `1/15` (floor 0.01, ceiling 4.0, range ceiling 200 m); spawn-area 25 m priority; indirect light governed by HL-7. |
| 7 | Sky, Moon Disc, Weather Presets & Post-Process | `game/src/core/tat_sky.gdshader:1-166`; `weather_profile.gd`; `weather_visuals.gd`; `docs/reports/sky-moon.md:1-361` | S03, S05 (KF05 sky/moon), S12–S13, S15–S17, S20–S21 (mist/fog depth) | `1:1_MATCH` | 16 presets with `Super`/`Template` inheritance; moon `8.2718°` from `SM_Moon` geometry; tuning residuals → PG-5. |
| 8 | PBR Materials, Overrides, CPD Emissives, Glass & Neon | `tat_glass.gdshader:1-54`; `tat_hdr_emissive.gdshader:1-29`; `tat_emissive_cpd.gdshader:1-21`; `docs/reports/visual-fidelity.md:31-56` | S01 neon (KF01), S07 diamonds (KF09), S12 portal (KF14), S14 headlight glare (KF16), S20 `MACLEOD` (KF23) | `APPROX_SHADER` | Authored HDR tints through unshaded pass retained; neon core saturation / Startscreen exposure residuals (PG-5); graph-only textures unrecoverable (HL-2). |
| 9 | 1P Camera, Menu CineCamera, MissionLobby & Ponder Cam | `thief_character.gd:21-40`; `main_menu.gd:12-19`; `mission_prep_ui.gd:49-56`; `mission_controller.gd:57-62` | S01 (KF01 framing), S05 (KF05–06 telescope cut), S09 (KF11 lobby) | `1:1_MATCH` | World vFOV 54.54 (UE 85° horizontal at 16:9); VM FOV 85; menu CineCamera vFOV 48.03; prep vFOV 11.33 / roll −14.78; `PG-2`'s lobby `fov_20` fail is a harness check, not framing. |
| 10 | Locomotion, Stairs, Mantle, Wall-Climb, Zipwire & Fall Damage | `thief_character.gd:32-136`; `docs/reports/gameplay-constants.md:9-42`; `docs/reports/combat-health.md:9-74` | S26 (KF29 stairs); traversal across S12–S26 | `UNVERIFIED_LIVE` | Speeds 3.6/1.8/5.4/5.5, zipwire 20 m/23 m/s, fall 6.5→23.25 m ported; stairs 50°/0.3 snap proven headless only (PG-4). |
| 11 | ThiefNisha 3P/1P Meshes & 1P Tool/Locomotion Clips | `animation_library.gd:68-120`; `thief_character.gd:13-21, 138-160`; `docs/reports/player-1p.md:1-123` | S21 (1P hands + `[1]` viewmodel, KF24 #4); S23 (takedown anim, KF26) | `KNOWN_GAP (PG-7)` | FP clips + `zipwire_crank` = `AN_ThiefNisha_Zipwire__Reload_Loop` wired; 1P idle/jump clips and 14 blendspace graphs missing (HL-4). |
| 12 | Equip Hotbar, Smoke Bomb, Slithersap, Fairy, Vistara, Blackjack & Disguise | `thief_character.gd:41-76`; `smoke_projectile.gd:1-60`; `slip_puddle.gd:1-60`; `light_probe.gd:1-159` | S14–S15 zipwire (KF16–17), S18 smoke (KF19–20), S19 Vistara (KF21–22), S21, S26 | `UNVERIFIED_LIVE` | Constants ported (smoke 5×5×4 m / 25 s; puddle 2 m/30 s); live tool visuals/mechanics unconfirmed; `PG-2` equip-toggle bug affects `[1]`. |
| 13 | Constabulary Guards & Ambient Civilians | `guard_ai.gd:5-160`; `civilian_npc.gd:1-80`; `docs/reports/guard-animations.md:1-146` | S22 constable (KF25), S23 KO (KF26); guards S13–S16, S21–S22 (KF15–18, 21–22) | `KNOWN_GAP (PG-7)` | 6-state AI, speeds 1.5/1.7/2.5, sight 20 m/80° FOV ported; foot-slide + HA club-montage reuse; civilians not shown in clip. |
| 14 | Niagara Catalogue (Blocked) & Procedural Stand-ins | `vfx_manager.gd:1-641`; `weather_visuals.gd:57-62, 87-94`; `docs/reports/vfx-catalogue.md:1-105` | S18 plume (KF20), S22 hearth, S24 beams (KF27), S25 wards (KF28); rain S01, S13–S21 | `HARD_LIMIT (HL-1)` | 120/120 systems VectorVM-blocked; CPUParticles3D stand-ins; rain 100–2700 drops, 30 m/s² fall. |
| 15 | In-Game HUD & Shell Screens | `hud.gd:1-160`; `art_nouveau_theme.gd:1-60`; plus `settings/wardrobe/contract_table/ledger/loading/mission_prep/main_menu` UI files | S01–S27 (menus S01–S11 incl. KF01/03/04/07/08/10/11/12/13; HUD S12–S26 incl. KF14–29; pause S27/KF30) | `KNOWN_GAP (PG-2)` | Layout contract (health blocks, compass, Stealth Ball + SoundWaves, hotbar, reticle, Guard Pips, lockpick); `PG-2` live fails: look-at card, clipped wardrobe controls, lobby FOV, pips/arcs, lockpick. |
| 16 | Wwise OGG Library, 9 Gameplay Tags & 3D Spatial Playback | `audio_manager.gd:1-136`; `save_system.gd:59-64`; `docs/reports/audio-wwise.md:1-135` | S01–S27 (rain beds; UI ticks S04/S08/S27; footsteps S03/S22/S24; barks S13–S16; gramophone S07) | `KNOWN_GAP (PG-6)` | 9 tags, one static clip each, 16 voices/60 m; no music/ambience/UI/per-surface footsteps/barks/reverb; reverb IRs HL-6. |
| 17 | Doors, Loot, Containers, Spawners, Clues, Escapes & Hub/Contract Flow | `mission_controller.gd:1-56`; `swinging_door.gd:1-30`; `net_manager.gd:1-90`; `docs/reports/doors-attachparent.md:8-46` | S03 map table, S07 decoration, S08 (KF10), S09 flow, S13 car interact, S21 doors (KF24), S22 pickpocket, S24–S25 security | `UNVERIFIED_LIVE` | 281 doors/373 leaves; 234 containers; 546 loot markers; 111 pivots resolved (HL-9); door leaf-disable past 70° + Den window split headless only (PG-4). |
| 18 | Internal Sideload APK & Mobile Profile | `docs/ANDROID.md:1-132`; `mobile_profile.gd:1-127` (C3) | Not clip-observable (official footage is a PC capture) | `N/A` | ETC2/arm64, `TEXTURE_CAP=1024`, ~914 MB APK; 3-tier mobile profile (12/24/32 lights, 0.7/0.85 scale, 30/60 fps); device profiling open (PG-8). |

## 7. Parity-gap (PG-1..PG-8) and Hard-limit (HL-1..HL-9) matrices

Reminder (see §5.5): every `Snn` below is a **clip segment**; the `S03/S04/S06a/S06b/S11/S14/S15b`
labels inside PG-2's fail list are **port E2E test-scenario IDs** (map_table, wardrobe, mission_prep,
zipwire_crank, guard_lantern_alert, lockpick), never clip segments.

### 7.1 Parity gaps PG-1..PG-8

| ID | Description | Verified citation | Clip segments where visible/audible | Port viewer impact |
|---|---|---|---|---|
| PG-1 | Live GPU Phase 4 blockers: Den RD cascade (`strip 0=591 / 1=17 / 2=569`), swapchain/`X connection :99 broken` teardown crash, no 60 FPS profile; TEMP `--env-strip=0-8` hook present and **committed** at `mission_controller.gd:65-67, 106-110, 143-160` (C2) | `docs/HANDOFF_NEXT_SESSION.md:21,112,119`; `docs/reports/fidelity-mechanics-wave.md:200-226` | S27 (quit-to-desktop teardown is the crashing flow, KF30); cascade/teardown are port-runtime issues, not clip content | Port recording of the Den may end in a teardown crash or ship RD-cascade corruption; no 60-FPS-profiled capture until live-verified |
| PG-2 | 7 live E2E parity content/harness fails (14/21): `map_table_look_at_card`, `clipped_controls`, `mission_lobby_fov_20` ×2, `equipped_tool!=zipwire` toggle bug, `guard_pips_and_offscreen_arcs` node-name mismatch, `circular_lockpick_minigame_ui` node-name mismatch | `docs/HANDOFF_NEXT_SESSION.md:21,111`; `docs/reports/fidelity-mechanics-wave.md:84-112, 139-147` | Clip S03/S08 (map table, KF10), S04 (wardrobe, KF03–04), S09 (mission prep, KF11), S15 (zipwire crank reticle, KF17), S14/S22 (guard pips + offscreen noise arcs), S21 (lockpick UI, KF24) | No map-table look-at card; clipped wardrobe controls; mis-framed mission lobby; `[1]` may equip the wrong tool; missing/misnamed guard pips and offscreen noise arcs; no circular lockpick minigame |
| PG-3 | 2 headless tier-1 game-side fails (108/110): `T1-03-E` trim specular path missing; `T1-18-E` Contract 2 level has `escape_points=0` | `docs/HANDOFF_NEXT_SESSION.md:21,111`; `docs/reports/fidelity-mechanics-wave.md:153, 166, 171` | S01 (storefront/cornice trim where the specular reads, KF01); escape flow never exercised in the clip | Building trim renders without the UE left-corner trim specular; a Contract 2 run cannot complete (no escape points) |
| PG-4 | Phase 4 mechanics live-unconfirmed: zipwire crank clip (`6ab91a3`), stairs stick 50°/0.3 (`2799c8e`), door leaf-disable past 70° + Den 0.95 m window split (`b58c69e`) — proven headless only | `docs/HANDOFF_NEXT_SESSION.md:21,112,119`; `docs/reports/fidelity-mechanics-wave.md:188-194, 205` | S15 (2nd zipwire crank, KF17), S21 (blue doors open/lock, KF24), S26 (stairs, KF29) | Crank playback may be missing on the real 1P rig; stairs may stick; open-door leaves may still collide |
| PG-5 | Residual visual parity deltas: Startscreen ambient/exposure; neon core more saturated than UE pale gold; MissionLobby roll sign, ThiefNisha foot contact (`y=0.82`), Constable facing; sky/neon/SSR/godray/glass tuning vs 56 Steam shots unchecked | `docs/HANDOFF_NEXT_SESSION.md:115,196`; `docs/reports/visual-polish.md:32, 72-73`; `docs/HANDOFF_OPENCODE.md:49`; `docs/reports/fidelity-mechanics-wave.md:55-61` | S01 (KF01), S07 (diamond emissives), S09 (KF11), S12 (portal), S14 (headlight glare/SSR on wet cobble), S20 (`MACLEOD`); exteriors S13–S20 (sky/godray/glass) | `APPROX_SHADER` deltas: over-saturated neon, different Startscreen exposure, possible lobby framing/foot-contact/facing differences |
| PG-6 | Audio runtime coverage gap: `AudioManager` wires only 9 one-shot tags; no music/ambience playback, no UI click/hover audio, no per-surface footsteps, no guard barks, no reverb/bus routing; `SaveSystem` applies only bus-0 `master_volume` | `audio_manager.gd:6-39, 117-136`; `save_system.gd:59-64`; `docs/reports/audio-wwise.md:95-112` | S01–S27 — audible everywhere: rain/wind beds (S01, S13–S21), diegetic gramophone jazz (S07), UI ticks (S04/S08/S27), wooden/marble footsteps (S03/S22/S24), guard barks + alert sting (S13–S16), interior room tone (S03–S12) | Port recording will be near-silent relative to the clip: only the 9 one-shot tags play; music/SFX/dialogue sliders do nothing |
| PG-7 | 3D gameplay/animation simplifications: guard locomotion in-place with foot-slide (worst: alert sprint ~3× chase speed), HA reuses club attack montage, no CivFemale clips, 3P body hidden in 1P, Godot-only `SEARCH` 7 s fallback, partial disguise drain rows, OldManor terrain walk unverified, smoke/fairy/puddle stand-ins | `docs/reports/guard-animations.md:131-143`; `docs/reports/spawners.md:74-75`; `docs/reports/player-1p.md:98-104`; `docs/reports/gameplay-constants.md:72-92`; `docs/reports/tool-mechanics.md:71-81`; `docs/reports/visual-polish.md:54`; `thief_character.gd:61-64` | S22 (guard idle/movement, KF25), S23 (takedown anim, KF26), S18 (smoke plume stand-in, KF20); civilians and OldManor terrain not shown (clip mission is Guildhall) | Sliding guard feet, simplified takedown motion, plain smoke box / sphere fairy / flat puddle visuals |
| PG-8 | Unverified / partial headless checks: OldManor forward-clearance spawn probe, 56 Steam-JPG side-by-side diffs, physical Android device profiling open | `docs/HANDOFF_OPENCODE.md:23,70`; `docs/reports/fidelity-mechanics-wave.md:55-61`; `docs/ANDROID.md:128-131` | S01–S08 (Den-hub/startscreen scenes subject to the 56-shot diff sweep); OldManor spawn and Android behaviour are not clip-observable | Comparison QA incomplete: port-vs-official deltas remain unadjudicated; OldManor fallback spawn framing may differ (not on this route) |

### 7.2 Hard limits HL-1..HL-9 (cooked UE5 data — do not fake)

| ID | Hard limit | Verified citation | Clip segments affected | Port viewer impact |
|---|---|---|---|---|
| HL-1 | Niagara VFX blocked: 120/120 systems have rates/lifetimes/velocities in compiled VectorVM bytecode; `loop_duration` null for all; 91/139 resolved renderer materials untextured; 3,692 placements counted, not spawned | `docs/HANDOFF_NEXT_SESSION.md:99,113,204`; `docs/FIDELITY_GAPS.md:20, 71-77`; `docs/reports/vfx-catalogue.md:58-92`; `build/handoff/teamwork_state/PROJECT.md:26-33` (C5) | S18 (smoke plume), S22 (hearth flame), S24 (volumetric beams), S25 (ward/barrier VFX); rain streaks S01/S13–S21 | Every particle effect renders as a labelled procedural stand-in with different density/motion; extracted Niagara rates do not exist |
| HL-2 | Expressionless cooked Material graphs: `M_Decal_Puddle`, `M_MagicSlime_Decal`, `M_Crystal_Glow_red`, `M_Sky`, `MI_VolumetricCloud_*` strip node graphs/textures; 667 decals → 347 spawned / 112 skipped | `docs/HANDOFF_NEXT_SESSION.md:101`; `docs/FIDELITY_GAPS.md:22, 68-69`; `docs/reports/level-runtime.md:88-98, 124-131` | S01 (wet-cobble puddle decals, KF01), S13–S14 (street puddles), S05/S16–S20 (cloud haze / sky terms rebuilt from scalars) | Puddle/sky/cloud looks rebuilt from scalar parameters; thinner decal coverage; graph-only textures absent |
| HL-3 | Unrecoverable Blueprint / QuestGraph / patrol: 981 `BP_` + 225 `BPUI_` graphs not machine-translated; `BP_AIPatrolPath` positions only (249 actors, no spline points); Kismet EventGraphs unrecoverable | `docs/HANDOFF_NEXT_SESSION.md:102`; `docs/FIDELITY_GAPS.md:31, 116, 122-126` | S13–S16 (guard patrol/alert reactions), S24 (security-camera sweep), S25 (tripwire→ward lockdown) | Patrol routes, alert scripting, camera sweep and trigger timing follow deterministic approximations that may differ from the authored Kismet behaviour |
| HL-4 | Missing 1P unarmed idle/jump clips & 14 `UBlendSpace`/`AimOffsetBlendSpace` graphs (995 clips exported, 14 parametric graphs genuinely non-convertible) | `docs/HANDOFF_NEXT_SESSION.md:33`; `docs/FIDELITY_GAPS.md:18, 55-59`; `docs/reports/anims-pipeline-implementation.md:37-41, 60-61`; `docs/reports/player-1p.md:99` | S21–S23 (1P hand sway/idle/jump-adjacent transitions around doors and the takedown, KF24–26) | 1:1 hand sway / idle blending cannot match; nearest-clip blending only around doors and the grapple |
| HL-5 | Missing `MagicSlime` `InitialSpeed` & bottle/pickup amounts: Slithersap aim-raycasted (no lobbed flight); bottle 12 m/s + 10 m noise, health full-heal, ammo full-refill are labelled approximations | `docs/reports/tool-mechanics.md:49-62`; `docs/reports/spawners.md:66-78` | Not exercised in the clip (only the Smoke Bomb appears, S18) | None for this recording; applies to any later footage showing Slithersap, thrown bottles, health/ammo pickups |
| HL-6 | Wwise partial limit: 6 convolution-reverb IRs are undecodable `PLUG` chunks; event↔media order join proven by size statistics only (51 equal-size RIFF pairs, `audio-wwise.md:118` per C4); 5 long weather/ambience loops (90–211 s) mismatched `InMemoryMediaSize` | `docs/HANDOFF_NEXT_SESSION.md:100`; `docs/reports/audio-wwise.md:56, 93, 118-125` | All interior acoustic spaces: S03–S12 (Den hub), S21–S27 (Guildhall rooms); exterior wet-street reflections S13–S20 | Room reverb heard in the clip has no decoded IRs (port acoustics flatter/drier); long ambience loop pairing may be wrong |
| HL-7 | Lumen GI & Local Exposure not in Godot Forward+: `LumenSkylightLeaking`/`LocalExposure*` map to bounded SSIL / shadow-toe LUT / shadowless-fill approximations (desktop only) | `docs/reports/level-runtime.md:72-74, 106-111`; `docs/HANDOFF_OPENCODE.md:44-45` | S03, S05 (moon shaft / bounce, KF02/KF05), S12 (lantern practical), S13 (streetlamp/headlights), S15–S17 (mist/fog depth), S20 (viaduct fog), S21 (exterior→sheltered shift) | Indirect bounce and auto-exposure differ: moonlit interiors, lantern spill and fog depth read flatter than UE |
| HL-8 | Landscape splines (`""` materials, 52, editor-only `SplineEditorMesh`) & grass/foliage runtime unparsed | `docs/HANDOFF_NEXT_SESSION.md:42, 110`; `docs/FIDELITY_GAPS.md:84, 100`; `docs/reports/level-components.md:66-67, 160-161`; `docs/reports/visual-polish.md:74` | S13–S20 exteriors (sidewalk/viaduct/terrain dressing where spline meshes and procedural grass would dress the ground) | Missing spline-mesh dressing and procedural grass on exterior ground along the street/terrace route |
| HL-9 | 111 doorway pivots without SCS leaf children (resolved via the pivot's own `StaticMesh`, 0 unresolved) + authored quirks: Guildhall floating periphery fragments; Old Manor 6 floorless `PlayerStart`s (covered-porch fallback) | `docs/HANDOFF_NEXT_SESSION.md:103-104` (C1); `docs/reports/doors-attachparent.md:8-46`; `docs/reports/oldmanor-spawn.md:12-20` | S21 (blue double doors & doorway pivots, KF24); door leaves across S21–S22; periphery fragments `UNCERTAIN:` in exterior silhouettes S15–S20; OldManor spawn never shown | Door leaves may pivot/sit oddly; floating building fragments possible in exterior silhouettes (`UNCERTAIN:`); OldManor spawn not on this route |

## 8. 4-pillar comparison checklist (V1–V7, AU1–AU6, UI1–UI5, G1–G5)

Scoring rules: fill **Port observation** from the aligned port recording, then set **Score** to exactly one of:

- `PASS` — port matches the official observation (within the tolerance noted in the row).
- `DELTA` — element present in both but visibly/audibly different.
- `MISSING` — element absent or non-functional in the port.
- `HARD_LIMIT` — difference caused by an unrecoverable cooked-data limit (cite the `HL-n`).
- `N/A` — not applicable or not observable on this route.

Port observation and Score are intentionally blank until the port recording exists. The **Notes** column
pre-states the expected port caveat (parity-gap / hard-limit tag with citation) so the scorer knows what
a legitimate delta looks like. `KFnn #k` refers to callout `#k` on keyframe `KFnn` in `CALLOUT_LEGENDS.md`.

### 8.1 Visual (V1–V7)

| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |
|---|---|---|---|---|---|---|
| V1-01 | Neon flicker + amber practicals | S01 / KF01 #1 | Magenta cursive `Mac Neish` / `Jeweller` flickers (dim `00:00.10`, full-lit `00:01.00`, left half off `00:02.05`) over warm amber window/awning bars. |  |  | Expect `APPROX_SHADER` (PG-5): authored HDR tint pass retained; core saturation/exposure residual vs UE pale gold. |
| V1-02 | Volumetric moon shaft vs candle pools | S03 / KF02 #1 | Teal-cyan moonlight shaft through arched frosted window casting mullion shadows across dark floorboards; warm candle pool at the desk contrasts. |  |  | `HARD_LIMIT (HL-7)`: Lumen bounce / auto-exposure approximated (SSIL / shadow-toe LUT). |
| V1-03 | Banker's-lamp pool on the map | S08 / KF10 #4 | Warm directional brass banker's-lamp pool across `KILCAIRN` parchment and wooden token vs cool moonlit Den. |  |  | Linear `1/15` intensity scale ported (`docs/reports/lighting-intensity.md`); check warm/cool contrast. |
| V1-04 | Lantern bounce & streetlamp exposure | S12 / KF14 #2; S13 / KF15 #2 | Caged wall lantern casts warm orange bounce on brick after ignite `01:15.1`; teal-cyan bulkhead + green streetlamp pools; gem flares pale gold under streetlamps. |  |  | Direct practicals `1:1_MATCH`; indirect bounce governed by HL-7. |
| V1-05 | Flashing car-headlight glare | S13–S14 / KF16 #3 | Dual vintage-car headlights flash across wet cobbles (`01:36.38+`) with specular streaks raking the gate. |  |  | `APPROX_SHADER` (PG-5): wet-cobble SSR tuning unchecked vs 56 Steam shots. |
| V1-06 | Hearth amber radial pool | S22 / KF25 #1 | Roaring parlor fireplace casts warm amber radial light across herringbone parquet; chandelier points overhead. |  |  | Flame VFX is a stand-in (HL-1); light pool approximation acceptable if warmth/shape read. |
| V1-07 | Crimson alarm spotlight wash | S26 / KF29 #2 | Wall security spotlight bathes slate treads + 1P arms in intense crimson (`03:38.20–03:39.60`); unlit slate stays plain outside the cone. |  |  | `1:1_MATCH` per BREAKDOWN S26 (`level_loader.gd:68-112`); check cone, colour, timing. |
| V2-01 | Night rain streaks + puddle reflections | S01 / KF01 #5; S13 / KF15 #6 | Diagonal rain streaks over rain-slick cobbles; foreground puddle reflects magenta/amber neon. |  |  | Rain is the labelled `WeatherVisuals` stand-in (100–2700 drops, 30 m/s²; HL-1 row). |
| V2-02 | Telescope sky, moon & cheese easter egg | S05 / KF05 #1–#3 | Cloudy teal-blue night sky, faint stars, crater-textured full moon; giant rotating golden cheese wedge with 3 orbiting chunks over rooftops. |  |  | Sky/moon authored (`docs/reports/sky-moon.md`); cheese prop is set dressing (#3/#4). |
| V2-03 | Loading illustration sky | S02; S10 / KF12 #1–#2 | Dark-indigo illustrated skyline, twin dirigibles with yellow searchlight cones, textured pale moon upper-right. |  |  | 2D illustration; check art fidelity and emblem placement (`UI4-05`). |
| V2-04 | Volumetric night-mist depth | S15 / KF17 #2; S20 / KF23 #4 | Clocktower silhouette with red window accents in mist; steel viaduct arch and rooflines receding into fog. |  |  | `HARD_LIMIT (HL-7)`: fog depth / exposure mapping differs. |
| V2-05 | Rain fade-in after digital silence | S10 / KF12 #5 | True digital silence `01:04.94–01:07.78`, then night rain fades in from `01:07.7757` (first non-zero sample). |  |  | Audio fade itself is PG-6 (no ambience bed); visual cut timing is G5-01. |
| V3-01 | Wet-cobble specular | S13 / KF15 #2 | Rain-wet cobbles with puddle speculars under the teal-cyan bulkhead light and streetlamps. |  |  | Puddle normal/opacity + `GroundWet` ported (`tat_landscape.gdshader`); decal graphs HL-2. |
| V3-02 | Emissive faceted diamonds | S07 / KF09 #5–#6 | Emissive green floor diamond + iridescent white-blue table diamond under the candelabra. |  |  | `APPROX_SHADER` (PG-5) emissive tuning; check facet shimmer. |
| V3-03 | Blue door paint, mullions & brass | S21 / KF24 #1 | Blue-painted wood, white/cream diamond-mullion grid over dark glass panes, twin vertical brass pull handles. |  |  | Material slots bound in GLB primitive order (#8); door leaf behaviour PG-4. |
| V3-04 | Purple shopfront orb | S01 / KF01 #2 | Glowing purple egg/orb in the upper Art Nouveau shop display beneath the warm streetlamp. |  |  | CPD emissive path ported (`tat_emissive_cpd.gdshader`). |
| V4-01 | Startscreen street dressing | S01 / KF01 #4–#5 | Stationary idle guard in uniform/helmet/brown belt; vintage car rear fender; wooden crates; Art Nouveau gold scrollwork storefront. |  |  | `1:1_MATCH` geometry (BREAKDOWN S01, `FIDELITY_GAPS.md:38`); trim specular PG-3. |
| V4-02 | Den attic dressing | S03 / KF02 #5–#6 | Candlelit rolltop desk, open armoire, `KILCAIRN` map table, scattered newspapers on floorboards, rafters. |  |  | `1:1_MATCH`; Den live capture blocked by RD cascade (PG-1). |
| V4-03 | Wanted poster wall | S05 / KF06 #5 | Five framed posters verbatim: `WANTED! / CAUTION / HIS HANDS ARE FAST`; `CHARMING MAN? / HE'S A THIEF`; `TELL A CONSTABLE!`; `WANTED £10000`; `REWARD £5000`. |  |  | World text via decals (#8); check all five legible. |
| V4-04 | `BARRON'S DEMOLITION` alley dressing | S13 / KF15 #1, #3 | Weathered brick banner + faint `EST. 1865` + `Out with the old, in with the new!`; crates, fallen steel drums, ladder, alley weeds. |  |  | `1:1_MATCH` geometry; banner full and unclipped at `01:21.38`. |
| V4-05 | Gate arch, griffins & gear plate | S14 / KF16 #1; S17 / KF18 #2, #4 | Wrought-iron `CONSTABLE'S GUILDHALL` arch with crowned star-topped pillars; twin stone griffins on brick pedestals; 10-bolt white gear plate with red downward `⚡` arrow. |  |  | `1:1_MATCH`; check gilded lettering and plate weathering. |
| V4-06 | `MACLEOD` vertical sign | S20 / KF23 #5 | Crisp illuminated vertical gold serif sign on the distant right facade (`02:35.00–02:41.50`, again `02:48.50–02:49.00`). |  |  | `APPROX_SHADER` (PG-5) emissive tint/exposure. |
| V4-07 | Foyer dressing | S24 / KF27 #2; S25 / KF28 #3 | Tall lit glass statue vitrine, velvet armchair + ottoman, flush square metallic floor plate; framed `Basement Stairs` and `WC` plaques. |  |  | `1:1_MATCH`; plaque text legibility check. |
| V5-01 | Idle guard at shopfront | S01 / KF01 #4 | Stationary guard in dark uniform, helmet, brown belt before the `Mac Neish` shopfront. |  |  | Guard mesh + retargeted idle clips (#11/#13); `1:1_MATCH` expected static pose. |
| V5-02 | 3D Spider turntable with cap sync | S04 / KF03 #4; KF04 #4 | Spider with bowler hat, yellow goggles, purple sweater on turntable before open armoire; `Cap` equipped by KF04, `Head` thumbnail synced. |  |  | PBR preview bound (visual-polish wave); wardrobe controls clipping is PG-2. |
| V5-03 | 1P gloved hands + ZipWire viewmodel | S12 / KF14 (vault); S21 / KF24 #4 | 1P gloved arms brace the railing vault (`01:19.6`); ZipWire `[1]` launcher gripped in right hand at the portico. |  |  | `1:1_MATCH` viewmodel (`player-1p.md`); idle/blendspace transitions HL-4. |
| V5-04 | Constable idle + blue hip baton | S22 / KF25 #2–#3 | Standing constable faces the fireplace, hands clasped behind back, glowing blue-tip baton on left hip; unaware of the crouched approach. |  |  | `KNOWN_GAP (PG-7)`: HA montage reuse / simplified idle; check pose + baton glow. |
| V5-05 | Takedown grapple pose | S23 / KF26 #2 | 1P camera lunges/tilts closely over the constable's helmet and corded shoulder; guard knocked onto the parquet; pull-back to eye height. |  |  | `KNOWN_GAP (PG-7)` simplified takedown motion; KO end state 1:1. |
| V6-01 | Escape portal wall outline | S12 / KF14 #1 | Jagged glowing emerald-green + violet chromatic-edge outline shimmering on the safe-room wall (`01:15.2–01:16.2`). |  |  | Emissive outline approximated (#8); shimmer/particle component HL-1. |
| V6-02 | Smoke bomb plume | S18 / KF20 #1 | Orange-white ignition flash (`02:28.20`) then opaque grey-white volumetric puffs expanding horizontally across the grand stairs (`02:28.40–02:29.80`). |  |  | `HARD_LIMIT (HL-1)` + 5×5×4 m / 25 s box stand-in (PG-7). |
| V6-03 | Security beams, emitter & node | S24 / KF27 #1, #3 | Two crisp horizontal white volumetric beams wall-to-wall from the mid-height circular white emitter (`x~17%, y~56%`); glowing cyan ceiling diamond node above the far doors. |  |  | `HARD_LIMIT (HL-1)` beam stand-in; emitter/camera geometry 1:1. |
| V6-04 | Purple ward + green vine lock | S25 / KF28 #2, #5 | Bright faceted purple crystalline ward seals the foyer archway; glowing green thorny vines erupt across the `Basement Stairs` doorway. |  |  | `HARD_LIMIT (HL-1)` VFX; lockdown trigger logic HL-3. |
| V7-01 | CineCamera startscreen framing | S01 / KF01 #3 | Locked-off wide shot of the street with right-aligned menu stack; port CineCamera at `(-12.7196, 0.4566, 14.6089)`, vFOV `48.03°`, pitch `+13.8°`, yaw `−46.335°`. |  |  | `1:1_MATCH` framing (`main_menu.gd:12-19`). |
| V7-02 | Telescope scripted hard cuts | S05 / KF05 #4 | Hard cut into the fixed sky view at `00:20.23`; centered `[F] EXIT`; hard cut back to the Den at `00:21.77`. |  |  | `_ponder_cam` scripted cut (`mission_controller.gd:57-62`); check cut timing ±0.2 s. |
| V7-03 | DOF blur behind briefing letter | S11 / KF13 #1 | Depth-of-field / Gaussian blur over the brick safe-room backdrop behind the parchment modal. |  |  | Post-process blur approximated (HL-7 mapping). |
| V7-04 | Takedown camera lunge & pull-back | S23 / KF26 | Scripted 1P lunge/tilt into the grapple (`03:17.80–03:20.60`), then pull-back to standing eye height (`03:20.80–03:22.00`). |  |  | `KNOWN_GAP (PG-7)` simplified camera motion. |
| V7-05 | Pause darkened blurred backdrop | S27 / KF30 #1 | Darkened blurred gameplay backdrop behind the teal/copper Art-Nouveau modal; frozen multi-cursor trail after `03:43.70` is a capture artifact. |  |  | Backdrop blur approximated; modal layout `1:1_MATCH` (UI1-02). |

### 8.2 Audio (AU1–AU6)

| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |
|---|---|---|---|---|---|---|
| AU1-01 | Startscreen rain bed, zero BGM | S01 / KF01 #6 | Steady night rain hiss + distant street air `-53 to -49 dBFS` RMS; explicit zero BGM score. |  |  | `KNOWN_GAP (PG-6)`: no ambience bed in port — silence will read as `MISSING`. |
| AU1-02 | Den room tone | S03 / KF02 #7 | Indoor room tone `-76.3 to -73.1 dBFS` RMS; no BGM. |  |  | PG-6. |
| AU1-03 | Loading digital silence | S02; S10 / KF12 #5 | S02: rain fades to `-82.0` then `-240.0 dBFS`; S10: true digital silence `01:04.94–01:07.78` (100.000% zero samples), rain fade-in from `01:07.7757`. |  |  | PG-6: port has no loading music either — verify the port is silent, not playing stray audio. |
| AU1-04 | Rooftop wind swell in telescope view | S05 / KF05 #5 | Exterior wind whoosh rises to `-39.5 dBFS` RMS / `-29.8 dBFS` pk during the sky cut only (`00:19.6–00:21.9`). |  |  | PG-6. |
| AU1-05 | Continuous rain bed across exteriors | S13–S21 | Rain bed under all alley/roofline/terrace foley; outdoor→sheltered shift at the door creak (`03:01.0–03:02.2`). |  |  | PG-6. |
| AU1-06 | Hearth crackle bed | S22 / KF25 #7 | Quiet crouch approach over hearth crackle `-67.5 to -54.0 dBFS`. |  |  | PG-6 (+ flame VFX HL-1). |
| AU2-01 | Diegetic gramophone jazz (only music in clip) | S07 / KF09 #1 | Switch click `pk=-36.3`; warped wind-up + scratchy 1920s jazz/ragtime with vinyl crackle `00:45.4–00:47.8` `pk=-24.9 dBFS`, attenuating on walk-away (`00:47.9–00:49.0`). |  |  | PG-6: no music playback path in port. |
| AU3-01 | Wooden-plank footsteps | S03 / KF02 #7; S05 | Hollow wooden footfalls `pk=-27.9` (S03) / `pk=-27.1 dBFS` (S05). |  |  | PG-6: no per-surface footsteps. |
| AU3-02 | Wet cobble walk → sprint → crouch | S13 | Walk `01:20–01:24`; rapid sprint/puddle splash `pk=-25.2 dBFS` (`01:24.4–01:27.4`); crouch cadence `01:28–01:33.8`. |  |  | PG-6. |
| AU3-03 | Metal grate steps + vault thud | S12 | Hollow grate footsteps `pk=-27.3` (`01:18.6`, `01:19.0`) + vault/drop thud `pk=-30.5 dBFS` (`01:19.6`). |  |  | PG-6. |
| AU3-04 | Hard-sole marble footsteps | S24 / KF27 #8 | Crisp hard-sole footfalls on checkered marble `pk=-28.9 dBFS` (`03:23.8–03:28.9`). |  |  | PG-6. |
| AU3-05 | Slate stair footfalls + ZipWire clack | S26 / KF29 #7 | Rapid steps up the slate stairs + clack `pk=-24.5 dBFS` (`03:39.8`), quieting at the landing. |  |  | PG-6. |
| AU4-01 | `PLAY` click | S01 / KF01 #3 | Crisp UI click `pk=-33.4 dBFS` at `00:02.0`. |  |  | PG-6: no UI audio in port. |
| AU4-02 | Wardrobe browse ticks | S04 / KF03 #7 | Open latch/whoosh chime `pk=-23.5` + 8 metallic hover/slot ticks `pk=-34.6 to -39.4 dBFS` + close clack `pk=-35.1`. |  |  | PG-6. |
| AU4-03 | Ledger parchment & tab clicks | S06 / KF07 #6; KF08 #6 | Parchment rustle + open/tab clicks `pk=-30.4` / `pk=-34.5 dBFS`; quiet `-68 dBFS` reading; re-open `pk=-33.7`; close-prep `pk=-34.3`. |  |  | PG-6. |
| AU4-04 | Six countdown ticks | S09 / KF11 #6 | `6..5..4..3..2..1` percussive ticks at exact `1.00 s` intervals, `pk=-41.3 to -35.7 dBFS` (`00:59.0–01:04.0`). |  |  | PG-6. |
| AU4-05 | Pause click, −19 dB duck, quit clicks | S27 / KF30 #4 | Pause click `pk=-35.6`; ambience ducks `-53 -> -72.4 dBFS`; hover+select `pk=-34.2 dBFS`; complete digital silence `03:43.80–03:45.64`. |  |  | PG-6; silence tail expected both sides. |
| AU5-01 | Vintage car double-honk | S13 / KF15 | `HONK—HONK!` short blast + sustained two-tone `pk=-20.2 dBFS` (`01:35.68–01:36.45`; highest peak of the act) with flashing headlights. |  |  | PG-6 (horn may map to a one-shot tag; verify). |
| AU5-02 | ZipWire launch + crank ratchet | S14 / KF16 #4; S15 / KF17 #5 | Equip clank `pk=-24.3`; launch snap/twang `pk=-21.5` (`01:43.5–01:43.8`); spring/pneumatic `pk=-24.8`; ratchet hand-cranking `pk=-22.2 dBFS`. |  |  | PG-6. |
| AU5-03 | Smoke detonation pop + hiss | S18 / KF20 #2 | Throw + metallic canister clink `pk=-28.0` (`02:27.3–02:27.4`); detonation pop + sustained pressurized hiss `pk=-20.5 dBFS` (`02:28.3–02:29.8`). |  |  | PG-6. |
| AU5-04 | Vistara shimmer/chime | S19 / KF21 #8 | Crystalline equip + scan shimmer/chime pulse `pk=-28.0 dBFS` (`02:32.8–02:33.6`). |  |  | PG-6. |
| AU5-05 | Ward tripwire chime, whoosh & hum | S25 / KF28 #8 | Two-note metallic chime `pk=-30.4` (`03:29.1–03:29.6`); crystalline whoosh `pk=-32.3`; sustained low ward hum `-59 dBFS` (`03:33.5–03:35.3`). |  |  | PG-6. |
| AU5-06 | Barrier shatter + alert sting | S26 / KF29 #7 | Loud crystalline impact/shatter + sharp sting `pk=-23.5 dBFS` (`03:37.7–03:38.2`); loudest segment in range. |  |  | PG-6. |
| AU5-07 | Key jingle + acquisition chime | S22 (03:17.1) | Metallic key jingle + acquisition chime `pk=-23.6 dBFS` at `03:17.3`. |  |  | PG-6. |
| AU5-08 | Takedown thud + KO groan | S23 / KF26 #4 | Non-verbal grapple grunts `pk=-23.7` (`03:18.8–03:19.7`); heavy blunt impact + guard pain/KO groan `pk=-22.1 dBFS` (`03:20.6–03:21.5`). |  |  | PG-6. |
| AU6-01 | ThiefNisha spawn VO | S12 / KF14 #8 | *"Let the thieving begin."* `pk=-30.8 dBFS` (`01:11.6–01:13.1`). |  |  | PG-6: no VO/bark playback in port. |
| AU6-02 | Gate guard barks | S13 | Guard 1: *"What?"* (`01:34.1`); *"[Bit / You're] too loud, [thief?]."* (`01:37.2–01:38.5`); *"What?!"* + alert sting (`01:38.8–01:39.2`). |  |  | PG-6. |
| AU6-03 | Alert & patrol shouts | S14–S16 / KF16 #7; KF17 #4 | *"I know someone's here!"* `pk=-25.9`; *"Oh, I will find you, thief!"* (`~01:49.6–01:53.0`); *"Who's there?"* (`02:02.4`); *"Captain said to look around for signs of trouble. Thieves, eh?"* (`02:06.8–02:11.0`). |  |  | PG-6. |
| AU6-04 | Smoke-reaction barks | S18 / KF19 #7 | *"Hey! Show yourself!"* `pk=-33.3` (`02:24.8–02:26.0`); faint cough (`02:29.5`); *"You stop making noise, you dog!"* (`02:30.3–02:32.2`). |  |  | PG-6. |
| AU6-05 | Post-KO line | S24 | ThiefNisha *"And stay down."* `pk=-32.6 dBFS` (`03:22.4–03:23.6`). |  |  | PG-6. |
| AU6-06 | Distant search & idle barks | S17; S20 | *"Guess I'll search over here."* (`02:20.1–02:21.7`); throat-clear *"Ahem-hem"* (`02:41.5–02:42.2`); *"Hey!"* (`02:46.2`). |  |  | PG-6 + patrol paths HL-3. |

### 8.3 HUD/UI (UI1–UI5)

| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |
|---|---|---|---|---|---|---|
| UI1-01 | Startscreen menu stack | S01 / KF01 #3 | Right-aligned `THICK AS THIEVES` logo above `PLAY` / `SETTINGS` / `CREDITS` / `QUIT`; cursor travels to `PLAY`. |  |  | `1:1_MATCH` menu stack (front-end menu, outside the PG-2 HUD fails). |
| UI1-02 | Pause modal + build footer | S27 / KF30 #2, #5 | `RESUME` / `SETTINGS` / `RETURN TO THIEF'S DEN` (straight apostrophe) / `QUIT TO DESKTOP`; footer `1.5.148559   Novice   1025051536`. |  |  | Modal `1:1_MATCH`; quit-to-desktop teardown is PG-1; port footer will show its own build string — note it. |
| UI2-01 | Den station prompt chain | S05 / KF05 #4; S08 / KF10 #3 | `[F] PONDER` → centered `[F] EXIT` in the sky view; `[F] READ LEDGER` at the desk; `[F] ENTER MATCH` reticle. |  |  | PG-2 (look-at card rendering on map table). |
| UI2-02 | Wardrobe slots, drawer & tooltips | S04 / KF03 #2, #3; KF04 #1 | `Edit Loadout` slots 1–4; `Signature Tools cannot be swapped out` notice; slot-3 expanded 4-tool row; `Vistara Diamond` tooltip card; `Zipwire` grapple-recoil description. |  |  | PG-2: `clipped_controls` live fail — check all controls visible. |
| UI2-03 | ZipWire action prompts | S14 / KF16 #6 | Bottom-right `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]` with `[1]` highlighted bottom-left from `01:39.5`. |  |  | PG-2 `equipped_tool!=zipwire` toggle bug; PG-4 crank clip playback. |
| UI2-04 | `CRANK [LMB]` progress ring | S15 / KF17 #3; S26 / KF29 #3 | Circular blue/white segmented progress ring `CRANK [LMB]` center-screen (`01:51.20`); six-tick circular reticle on the stairs (`03:39.40`). |  |  | PG-2 (port scenario `zipwire_crank` is the S15 fail id, not clip S15) + PG-4. |
| UI2-05 | Blue door prompts | S21 / KF24 #2, #3 | `[F] OPEN` stacked above `[F] [HOLD] LOCK` (`03:00.60–03:01.00`), flipping to `[F] CLOSE` (`03:01.20`) as the door swings inward. |  |  | PG-2 (`circular_lockpick_minigame_ui` fail at this door) + PG-4 door live-unconfirmed. |
| UI2-06 | Pickpocket/takedown prompts | S22 / KF25 #4, #5 | `[F] PICK POCKET` above `[F] [HOLD] TAKEDOWN` (`03:15.00–03:17.00`). |  |  | PG-2 HUD rows; pickpocket cone itself 1:1 (`guard_ai.gd`). |
| UI2-07 | Gramophone toggle flip | S07 / KF09 #2 | `[F] TURN ON` flips to `[F] TURN OFF` after the `00:44.4` click while the record plays. |  |  | Prompt flip 1:1 expected; record audio is PG-6 (AU2-01). |
| UI3-01 | Player card + compass fade-in | S03 / KF02 #2, #3 | Top-right `Johnny Cipher` Spider card level `4` + subtle top-center compass `NW` fade in by `002.703s`. |  |  | PG-2 HUD card rendering. |
| UI3-02 | Loot tracker, hotbar & hidden health | S12 / KF14 #3–#5 | `(£) 0` + `Mission: Steal 4,000 in loot value[0/4,000]` (no space before `[0/4,000]`); Health Bar hidden at 100% HP; `[1]`/`[2]`/`[4]` + `[TAB] MAP [MMB] [HOLD] PING MENU`. |  |  | PG-2; MMB binding verified in `project.godot` input map. |
| UI3-03 | Health Bar reveal at ~75% | S17 boundary / KF19 #1 | First fall damage `02:23.30` (`red_px: 0 -> 27,560`) reveals the ornate Health Bar draining to ~75% with a trailing bright-red segment. |  |  | Fall curve ported 6.5→23.25 m; reveal timing + fill level are the check. |
| UI3-04 | `Guildhall Key` HUD row | S22–S26 / KF27 #5 | Key icon + label persist bottom-left above `[1]` Zipwire after the `03:17.10` pickup (golden key shimmer, not `!`). |  |  | PG-2 HUD rows; pickup logic 1:1 (`world_pickup.gd`). |
| UI3-05 | Light Gem exposure states | S12 / KF14 #6; S15 / KF17 #6; S21 / KF24 #5; S22 / KF25 #6 | Lit sector size/position track light amount + direction: lit cream toward lantern (S12), fully dark concealed while cranking (S15), fully lit at the portico (S21), bright white-gold by the hearth (S22). |  |  | Gem semantics per §5.3; `PG-2` pips/arcs node-name fail affects rendering, not semantics. |
| UI3-06 | Map-table keybind legend | S08 / KF10 #6 | Bottom-right `JOIN GAME [F]` / `TOGGLE MODE [R]` / `TOGGLE DIFFICULTY [H]`. |  |  | PG-2 (map_table look-at card fail). |
| UI4-01 | `JOURNAL` tab | S06 / KF07 #1–#5 | `[Q] JOURNAL` + `BLACK MARKET [E]` tabs; `Level 4` XP bar `94/500`; `Contract #1/#2` `Completed`, `#3` `Active` (*Into the Lion's Den*, *In the Eye of the Beholder*) with full lore paragraphs. |  |  | PG-2; contract titles fall back to `Contract N — <quest item>` in port (#17) — expect title wording delta, note it. |
| UI4-02 | `BLACK MARKET` tab | S06 / KF08 #1–#5 | `YOUR TOTAL ASSETS: (£) 26,275`; `✓ PURCHASED` on `Zipwire`; `TOOLS` / `GUILD PERKS` / `SPIDER COSMETICS` / `CHAMELEON COSMETICS` with prices `7,500`/`5,000`/`2,500` and padlock badges. |  |  | PG-2. |
| UI4-03 | Mission prep cards + READY toggle | S09 / KF11 #2, #3, #6 | Cards: `CONSTABLES' GUILDHALL` / `Cleanout Heist` / `Time Limit: 55 minutes` / `Contract Inactive`; `[F] READY` → `READY` + `[F] UNREADY` / `[ESC] BACK` at `058.807s`; 3D Spider on the slate ridge. |  |  | PG-2 `mission_lobby_fov_20` ×2 live fails; ThiefNisha PBR preview bound. |
| UI4-04 | Briefing letter (11 lines) | S11 / KF13 #2, #3 | Typewriter letter verbatim incl. `55 minute window` and `magic door ... 20 minutes`; thin right scrollbar; `[SPACE] CONTINUE` below. |  |  | PG-2. |
| UI4-05 | Loading spinner + gold emblem | S02; S10 / KF12 #3, #4 | Centered rotating cyan/white ring over `LOADING...`; gold `THICK AS THIEVES` emblem bottom-center. |  |  | `1:1_MATCH` expected (2D screen); timing per G5-01. |
| UI5-01 | Red player-noise arcs | S13 / KF15 #4; S18 / KF20 #5; S24 / KF27 #7 | Absent when quiet (dark gem at the alley drop); wide/bright during the sprint (`pk=-25.2`) and smoke detonation; twin inner+outer arcs flare with marble footsteps. Arcs read the player's own noise level. |  |  | PG-2 `guard_pips_and_offscreen_arcs` node-name mismatch — arcs may be missing/misnamed. |
| UI5-02 | Guard-alert direction pip | S15 / KF17 #4 | Three-dash crimson directional pip mid-right (`x~1195, y~832`) during *"Oh, I will find you, thief!"*; distinct from the gem's player-noise arcs (no gem arcs present). |  |  | PG-2 pips fail; check direction + three-dash shape. |
| UI5-03 | Guard alert bar + red eyes | S14 / KF16 #2 | Alerted constable with vertical yellow overhead alert bar, glowing red eyes, hip flashlight at `01:40.20`. |  |  | `UNVERIFIED_LIVE` guard-side indicators (#13). |
| UI5-04 | Vistara RED→GREEN guard states | S19 / KF21 #3; KF22 #1 | Scan pulse highlights the patrolling constable RED (`02:31.40–02:32.60`, clearest `02:32.20`), flipping to bright GREEN at `02:33.00`. |  |  | `UNVERIFIED_LIVE` scan highlight (#12/#13). |
| UI5-05 | 6 s countdown banner | S09 / KF11 #1 | Top-center `MISSION STARTING IN 6...` → `1...` with `Mode: Solo` / `Difficulty: Novice` (`058.914–064.775s`). |  |  | PG-2; tick audio AU4-04. |
| UI5-06 | Status icons above the Light Gem | S25 / KF28 #6; S26 / KF29 #4 | White mechanical jaw/bear-trap icon with countdown ring (`03:29.00+`) + orange-arc unconscious-head icon `xx`+`zz`+`>>` (`03:31.20+`); re-triggered jaw-trap `03:38.07–03:41.87` until the Pause Menu hides the HUD. |  |  | PG-2. |
| UI5-07 | Sound-ripple + ZipWire gleam | S20 | Sound-ripple ring + red player-noise arcs as the ZipWire gleams white (`02:50.00–02:50.50`). |  |  | PG-2 arcs/pips fail. |

### 8.4 Gameplay (G1–G5)

| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |
|---|---|---|---|---|---|---|
| G1-01 | Telescope station | S05 / KF05 #4 | `[F] PONDER` at the brass telescope cuts to the exterior sky view; `[F] EXIT` returns (`00:20.23–00:21.74`). |  |  | `_ponder_cam` 1:1 (`mission_controller.gd:57-62`). |
| G1-02 | Decoration swap + trunk cycle | S07 / KF09 #2, #4 | `[F] CHANGE DECORATION` swaps golden owl → blue/silver spider-emblem chest (`00:40.1–00:42.0`); trunk cycle egg ↔ chalice, pink gem ↔ white diamond (`00:47.6–00:50.0`); clinks `pk=-34.7`. |  |  | Station logic 1:1 (#17); prompt card PG-2. |
| G1-03 | Mission select + confirmation modal | S08 / KF10 #1–#3 | Tokens `ELWAY MANOR` → `CONSTABLES' GUILDHALL`; card `[H] Difficulty: Novice` / `[R] Mode: Solo` / `[F] Prepare for Mission`; modal `Join Mission with these settings? / Difficulty: Novice / Mode: Solo` + `[SPACE] PREPARE FOR MISSION` / `[ESC] CANCEL` at `055.339s`. |  |  | PG-2 `map_table_look_at_card` live fail. |
| G1-04 | Vintage car interact | S13 / KF15 | `[F] INTERACT` (`01:35.38`) triggers the double-honk + flashing headlights (`01:35.68–01:36.45`, `01:36.38+`). |  |  | `UNVERIFIED_LIVE` interactable (#17). |
| G1-05 | Safe-room lantern toggle | S12 / KF14 #2 | `[F] TURN ON` click `01:15.1` → flame + `[F] TURN OFF` beside the `"SPIDER"` flyer. |  |  | Station 1:1; flame VFX HL-1. |
| G1-06 | Pickpocket `Guildhall Key` | S22 / KF25 #4 | `[F] PICK POCKET` completes `03:17.10`: golden key shimmer + HUD label appear (verified not a `!` marker). |  |  | Pickpocket cone 1:1 (`guard_ai.gd:5-160`); HUD row PG-2. |
| G2-01 | Den hub walk | S03 / KF02 #7 | Free walk across floorboards during the opening pan; wooden footsteps `00:04.5–00:05.8`. |  |  | Movement constants 1:1 (3.6/1.8/5.4/5.5, world vFOV 54.54 = UE 85 hFOV; #10). |
| G2-02 | Alley drop → sprint → crouch | S13 / KF15 #5–#6 | Drop past the banner, walk (`01:20–01:24`), sprint/puddle splash (`01:24.4–01:27.4`), crouch (`01:28–01:33.8`); noise arcs track the sprint. |  |  | Speeds 1:1; footsteps audio PG-6; arcs PG-2. |
| G2-03 | ZipWire crank ascent + roofline | S15–S16 / KF17 #1, #5 | 2nd shot anchors the roof parapet; rhythmic 1P crank hauls up the facade (`01:52.20–01:58.00`); roofline traverse + winch-housing pass (`02:01.00–02:10.40`). |  |  | PG-4: crank clip `AN_ThiefNisha_Zipwire__Reload_Loop` proven headless only. |
| G2-04 | Cable crossing + courtyard descent | S17 / KF18 #1 | Mid-cable crossing over the arch/griffins (`02:11.00–02:17.00`); face-on gear-plate landing (`02:17.60–02:18.80`); drop to flagstones beside crates (`02:19.00–02:23.20`). |  |  | PG-4 traversal chain; fall damage G5-02. |
| G2-05 | Slate staircase ascent | S26 / KF29 | Rapid ascent `03:39.60–03:41.20` up the plain dark grey/slate run to the upper landing gallery. |  |  | PG-4 stairs snap 50°/0.3 headless-only — watch for sticking. |
| G3-01 | ZipWire `[1]` equip + 1st launch | S14 / KF16 #4 | Launcher swings into the right hand (`01:39.30–01:39.50`); 1st launch `01:42.90–01:43.90`; non-damaging foliage landing beside the chest (`red_px=0` across `01:40–01:48`). |  |  | PG-2 equip-toggle bug + PG-4 crank playback; verify no damage on this landing. |
| G3-02 | Smoke bomb throw + plume cover | S18 / KF19 #4; KF20 #1 | `[2]` equip with `THROW [LMB]`; canister thrown onto the grand stairs (`02:26.80–02:27.40`); flash `02:28.20`; plume blocks stair sight lines (`02:28.40–02:29.80`). |  |  | 5×5×4 m / 25 s smoke box stand-in (PG-7); plume look HL-1. |
| G3-03 | Vistara Diamond scan pulse | S19 / KF21 #4 | `[4]` held in brass-and-leather caliper mount; scan pulse highlights the constable RED (`02:31.40–02:32.60`) with a warm golden courtyard glint (`02:32.60–02:33.00`). |  |  | `UNVERIFIED_LIVE` scan mechanics (#12). |
| G3-04 | Tool swap back to `[1]` | S19 / KF22 #3 | `[4]` → `[1]` swap (`02:32.80–02:33.00`); prompts flip to `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`; re-equip click `02:34.0` `pk=-28.2`. |  |  | PG-2 hotbar highlight + toggle bug. |
| G4-01 | Gate guard alert escalation | S13–S14 / KF16 #2, #7 | Barks escalate *"What?"* → *"[Bit / You're] too loud, [thief?]."* → *"What?!"* + alert sting as the gate is approached; red eyes + vertical yellow alert bar at `01:40.20`. |  |  | Detection ramp/decay 1:1 (`guard_ai.gd:39-64`); barks PG-6; foot-slide PG-7. |
| G4-02 | Roofline patrol mutter | S16 | *"Who's there?"* (`02:02.4–02:03.6`) + patrol mutter *"Captain said to look around for signs of trouble. Thieves, eh?"* (`02:06.8–02:11.0`). |  |  | Patrol paths positions-only (HL-3); barks PG-6. |
| G4-03 | Distant search & idle barks | S17; S20 | *"Guess I'll search over here."* (`02:20.1–02:21.7`); throat-clear (`02:41.5–02:42.2`); *"Hey!"* (`02:46.2`); patrolling guard spotted ahead (`02:53.00–02:54.50`). |  |  | HL-3 + PG-6. |
| G4-04 | Guard takedown + KO | S23 / KF26 #2 | Hold `[F]` on `[HOLD] TAKEDOWN` as the guard turns (`03:17.40`); lunge grapple `03:17.80–03:20.60`; KO onto the parquet `03:20.6–03:21.5`. |  |  | KO state 1:1 (`guard_ai.gd`); grapple anim PG-7; grunts PG-6. |
| G4-05 | Distant green guard silhouette | S17 / KF18 #3 | Distant constable under the portico highlighted bright green at `02:14.80` during the cable crossing. |  |  | `UNVERIFIED_LIVE` highlight rendering (#13/#14). |
| G5-01 | Mission flow: select → ready → countdown → load | S08–S10 / KF10, KF11, KF12 | Confirm chime `00:55.4` → Mission Prep → `[F] READY` (`058.807s`) → countdown `058.914–064.775s` → hard cut to loading `064.803s`. |  |  | Flow cards PG-2; sublevel + difficulty timers ported (7200/2700/1800 s; #17). |
| G5-02 | First fall damage | S17 boundary `02:23.30` | Courtyard drop registers damage (`red_px: 0 -> 27,560`); Health Bar reveals and settles at ~75% fill. |  |  | Fall curve 6.5→23.25 m + regen 15/s ported (`combat-health.md`). |
| G5-03 | Beam tripwire → ward lockdown | S25 / KF28 #1–#6 | Crossing the foreground beam at `03:29.00` seals the archway (purple ward), locks `Basement Stairs` (green vines), raises the jaw-trap icon; unconscious-head icon follows `03:31.20+`. |  |  | Tripwire→lockdown trigger approximated (HL-3); ward VFX HL-1. |
| G5-04 | Ward shatter → crimson alarm | S26 / KF29 | Loud crystalline barrier impact/shatter + alert sting (`03:37.7–03:38.2`) triggers the crimson alarm spotlight for the stair ascent. |  |  | Trigger logic HL-3; spotlight light 1:1 (#6). |
| G5-05 | Pause → quit flow | S27 / KF30 #3 | Pause entry exactly `03:41.90`; cursor hovers `QUIT TO DESKTOP` cleanly (`03:43.10–03:43.30`); selection `03:43.2–03:43.6`; digital silence tail. |  |  | PG-1: quit-to-desktop teardown unconfirmed live — stop the recorder before quitting if it crashes. |

## 9. Port capture protocol

### 9.1 Route script (play the same route and actions in the same order)

1. **(S01)** Launch to the Startscreen; let the neon flicker play; hover `PLAY`.
2. **(S02)** Click `PLAY`; record through the loading art.
3. **(S03)** Enter the Thieves' Den; walk the attic pan toward the mirror (`[F] CUSTOMIZE LOADOUT`).
4. **(S04)** Open the Wardrobe; browse the `Zipwire` tooltip, `Head` grid (`Bowler Hat` → `Cap`), `Body` (`Classic`), slots 1–4, the slot-3 tool drawer, the `Vistara Diamond` tooltip, `Pickpocket Fairy`; close.
5. **(S05)** Walk to the telescope; `[F] PONDER`; hold the sky view ~1.5 s; `[F] EXIT`; inspect the 5 Wanted posters; walk to the desk.
6. **(S06)** `[F] READ LEDGER`; read `JOURNAL`; tab to `BLACK MARKET` and hover `Zipwire`, `Master Thief Difficulty`, `Elway Manor`, `Mustache`, `Glasses`, `Thief Mask`, `Full Beard`, `Bowler Hat`, `Pickpocket Fairy`; re-open `JOURNAL`; close.
7. **(S07)** `[F] CHANGE DECORATION` (owl → spider chest); cross the boot-trail decals; `[F] TURN ON` the Gramophone; cycle the trunk treasures; walk to the Map Table.
8. **(S08)** Inspect `ELWAY MANOR` then `CONSTABLES' GUILDHALL` tokens; keep `Difficulty: Novice` / `Mode: Solo`; `[F] ENTER MATCH`; confirm with `[SPACE] PREPARE FOR MISSION`.
9. **(S09)** Mission Prep: toggle `[F] READY`; let the 6 s countdown run out without unreadying.
10. **(S10)** Record the loading screen.
11. **(S11)** Dismiss the Briefing Letter with `[SPACE] CONTINUE`.
12. **(S12)** Safe room: `[F] TURN ON` the lantern; view the Escape Portal outline; exit to the catwalk; vault into the alley.
13. **(S13)** Pass `BARRON'S DEMOLITION`; sprint the wet cobbles; crouch; `[F] INTERACT` the parked car (honk + headlights); approach the gate.
14. **(S14)** Equip ZipWire `[1]`; frame the gate; fire the 1st zipwire; land in the planter foliage beside the chest.
15. **(S15)** Aim at the roof ridge; fire the 2nd zipwire; crank up to the roof.
16. **(S16)** Traverse the roofline; crank onto the chimney block; pass the winch housing; fire the 3rd zipwire at the gate pillar.
17. **(S17)** Cross the cable; land by the gear plate; drop to the courtyard (take the fall damage — do not heal).
18. **(S18)** Equip Smoke Bomb `[2]`; walk past the crates/griffins; throw onto the grand stairs; watch the plume bloom.
19. **(S19)** Equip Vistara Diamond `[4]`; scan the patrolling constable (RED→GREEN); swap back to `[1]`.
20. **(S20)** Traverse the side wing past the `MACLEOD` sign to the garden terrace.
21. **(S21)** Enter the side portico; `[F] OPEN` the blue double doors (with `[F] [HOLD] LOCK` visible); inspect the scaffolding; walk through.
22. **(S22)** Cross to the Fireplace Parlor; crouch behind the constable; `[F] PICK POCKET` the `Guildhall Key`.
23. **(S23)** Immediately `[F] [HOLD] TAKEDOWN` the constable.
24. **(S24)** Cross the parlor into the marble foyer; approach the beams without crossing them.
25. **(S25)** Cross the foreground beam (ward lockdown); turn past the `WC` plaque toward the stairwell emitter.
26. **(S26)** Ascend the slate staircase under the crimson alarm to the upper landing.
27. **(S27)** Open the Pause Menu; hover `QUIT TO DESKTOP`. If the quit-to-desktop teardown crashes the recorder (PG-1), stop the recording first — the pause frame is the final comparison state.

### 9.2 Capture settings

- **Resolution:** capture the game window at **1920x1080 or higher**, 30 or 60 fps, system audio on.
  The port's base viewport is **1280x720 stretched to the window** (`game/project.godot:24-27`:
  `window/size/viewport_width=1280`, `viewport_height=720`, `stretch/mode="canvas_items"`,
  `aspect="expand"`), so a 1920x1080 window is a 1.5× upscale of the rendered frame. That is acceptable
  for layout, HUD, geometry, and lighting comparison; when scoring fine material detail (V3), remember the
  official reference frames are native 3840x2160 downscales — do not penalize upscale softness as a delta.
- **Windowed capture is fine**; keep the cursor visible (the official clip shows it).
- **Settings:** `Difficulty: Novice`, `Mode: Solo` at the Map Table (mirrors the official footer
  `1.5.148559   Novice   1025051536`); do not change in-game settings mid-run.
- **Known live blockers:** the Den render cascade and quit-to-desktop teardown crash are open (PG-1). Record
  the run as-is; if the picture corrupts in the Den, note it and record a second uncorrupted pass for
  S03–S09 only. The committed `--env-strip=0-8` debug hook in `mission_controller.gd:65-67, 106-110,
  143-160` is a diagnosis aid only — never score parity from a stripped run.

### 9.3 File naming

Create the folder only when recording (replace `<date>` with `YYYYMMDD`):

```text
docs/reference/port_<date>/
  port_clip.mp4            # the full port recording
  port_KF01_<mm_ss>.jpg …  # aligned port frames (one per keyframe)
  side_by_side_KFnn_*.jpg  # magick/ffmpeg composites
  offsets.csv              # Snn, official anchor ts, port anchor ts, offset s
```

### 9.4 Alignment anchor events (one per segment)

Align by event, not by absolute time: find each anchor's first frame in both recordings, note both
timestamps, and compute `offset = port_ts - official_ts` into `offsets.csv`.

| Seg | Anchor event | Official ts |
|---|---|---|
| S01 | First Startscreen frame (menu stack visible, cursor near `PLAY`) | `00:00.00` |
| S02 | Hard cut to loading art after the `PLAY` click | `00:02.15` |
| S03 | First Den fade-in frame (player card fading in) | `00:02.60` |
| S04 | Wardrobe fully faded in (`WARDROBE` header legible) | `00:06.57` |
| S05 | Telescope exterior cut (sky + moon visible; cut-back `00:21.77`) | `00:20.23` |
| S06 | `JOURNAL` panel open over the desk | `00:26.58` |
| S07 | Gramophone switch click (`[F] TURN ON`) | `00:44.40` |
| S08 | Map-table settings card visible (`[H] Difficulty: Novice`) | `00:51.50` (KF10 `00:52.35`) |
| S09 | `MISSION PREPARATION` cut (countdown starts `00:58.914`) | `00:56.08` |
| S10 | Hard cut to loading art (screen 2) | `01:04.80` |
| S11 | Briefing letter parchment fully visible | `01:09.44` |
| S12 | Safe-room spawn (HUD fade-in complete `01:11.31`) | `01:10.81` |
| S13 | Alley drop landing (`BARRON'S DEMOLITION` in view) | `01:20.10` |
| S14 | ZipWire `[1]` equip swing into the right hand | `01:39.30` |
| S15 | 2nd launch: `CRANK [LMB]` ring appears | `01:51.20` |
| S16 | Roof-ridge arrival after the crank | `01:58.50` |
| S17 | Cable crossing start over the arch | `02:11.00` |
| S18 | Courtyard flagstone landing (Health Bar appears) | `02:23.30` |
| S19 | Vistara `[4]` equip + scan pulse (guard turns RED) | `02:31.40` |
| S20 | Balcony traverse start (side wing visible) | `02:33.00` |
| S21 | Arched portico entry (blue doors in view) | `02:55.00` |
| S22 | Parlor hearth first in view (constable visible) | `03:05.80` |
| S23 | Guard begins turning (takedown hold starts) | `03:17.40` |
| S24 | Foyer marble + first beam in view | `03:24.00` |
| S25 | Beam-cross trigger (purple ward seals the archway) | `03:29.00` |
| S26 | Crimson alarm wash onset | `03:38.20` |
| S27 | Pause modal fully open | `03:41.90` |

### 9.5 Frame extraction and side-by-side commands

```bash
# Extract the aligned port frame for a keyframe (aligned ts = official KF ts + segment offset):
ffmpeg -v error -ss <aligned_ts> -i docs/reference/port_<date>/port_clip.mp4 \
  -frames:v 1 docs/reference/port_<date>/port_KF01_00m01s.jpg

# Side-by-side (horizontal) with ImageMagick:
magick docs/reference/clip_1795033698901/clean/KF01_00m01s_startscreen.jpg \
  docs/reference/port_<date>/port_KF01_00m01s.jpg +append side_by_side_KF01.jpg

# Vertical stack:
magick <official.jpg> <port.jpg> -append side_by_side_vertical.jpg

# ffmpeg alternative (equalizes nothing — pre-scale if heights differ):
ffmpeg -i official.jpg -i port.jpg -filter_complex hstack=inputs=2 side_by_side.jpg

# Same-height motion comparison of the two clips:
ffmpeg -i "$HOME/Videos/clip_1,795,033,698,901.mp4" -i docs/reference/port_<date>/port_clip.mp4 \
  -filter_complex "[0:v]scale=1920:1080[a];[1:v]scale=1920:1080[b];[a][b]hstack" comparison.mp4

# Segment contact sheet for scrubbing (per BREAKDOWN.md method):
ffmpeg -v error -ss <start> -to <end> -i <clip> -vf "fps=2,scale=480:-1,tile=6x5" -frames:v 1 sheet.png
```

Always quote the official clip path (it contains commas). If the port window letterboxes (aspect
`expand`), crop to the rendered rect before compositing: `magick port.jpg -crop 1920x1080+0+0 +repage`.

## 10. Comparison workflow

1. **Record** the port per §9 (route script + capture settings) into `docs/reference/port_<date>/`.
2. **Align** both recordings using the 27 anchor events; write `Snn, official ts, port ts, offset` to
   `offsets.csv`. One offset per segment is expected — drift inside a segment is itself a finding.
3. **Extract** the 30 aligned port frames (§9.5 ffmpeg command) and build the 30 side-by-sides
   (`magick +append`, or `ffmpeg hstack`).
4. **Score** the §8 checklist row by row against the side-by-sides and the recordings: fill
   `Port observation`, then `Score` (`PASS` / `DELTA` / `MISSING` / `HARD_LIMIT` / `N/A`). Score every
   audio row from a waveform/spectrogram comparison (`ffmpeg astats`/`showspectrumpic`), not by ear alone.
5. **Mirror** the results into `reference/clip_1795033698901/COMPARISON_TEMPLATE.md` (per-segment image
   slots, alignment table, and the summary score-per-pillar table).
6. **Map** every `DELTA` / `MISSING` / `HARD_LIMIT` to its pre-stated `PG-n` / `HL-n` (Notes column) and
   file a follow-up per gap; `PASS` rows need no action. A delta with no listed PG/HL is a new finding —
   triage it into the appropriate subsystem in §6.
7. **Re-run** the recording + scoring after each fix wave until each row is `PASS`, `N/A`, or a
   documented `HARD_LIMIT` with its citation.
8. **Record** adjudications, refuted claims, and spot-check results in the `## Verification log` below
   (Wave 4 populates it; do not pre-fill).

## Verification log

Adversarial spot-check wave (Wave 4), executed 2026-11-19 against the official source
`$HOME/Videos/clip_1,795,033,698,901.mp4` (4K, `3840x2160`, 6696 frames, 225.529 s) and against
the repo files this baseline cites. Every claim was attacked first with a concrete contradicting
measurement; `REFUTED` is recorded only where a measurement contradicts the cited bytes or pixels,
otherwise `PASS`. Each row below is reproduced from its source file in **Claim -> Evidence command
-> Verdict** form.

- `_build/adv_visual_hud.md` - 17 rows: visual claims V1-V7 on `BREAKDOWN.md` (rows 1-11) plus HUD
  verbatim-string claims (rows 12-17).
- `_build/adv_audio_time.md` - 10 rows: audio dBFS / spectrogram / EBU R128 claims (rows 1-7) plus
  gameplay-timing claims (rows 8-10).
- `_build/adv_cite_image.md` - 38 rows: 29 repo-citation re-opens (rows 1-29) plus 9 annotated-image
  re-opens (rows 30-38).

### Visual & HUD claims (`_build/adv_visual_hud.md`)

| # | Claim | Evidence command | Verdict |
|---|---|---|---|
| 1 | `BREAKDOWN.md:86` (V1) "Magenta cursive neon plus warm amber window/awning bars; upper-right streetlamp; puddle reflections." | `/usr/bin/ffmpeg -ss 1.00 -i "$HOME/Videos/clip_1,795,033,698,901.mp4" -frames:v 1` + `read annotated/KF01` (badges #1/#5 on neon and puddle) + `/usr/bin/magick %[pixel:p]`: neon stroke `srgb(132,0,124)` magenta (R≈B>>G), streetlamp brightest blob (71.4%, 19.1%) v=249 = upper-right, puddle probe `srgb(57,14,41)` magenta-tinted wet reflection; amber arcs/bars visible in 4K crop. Refutation attempt (neon not magenta / lamp not upper-right) failed. | PASS |
| 2 | `BREAKDOWN.md:85` (V4) "Wet cobblestone street, storefront with Art Nouveau gold scrollwork, vintage car rear fender left, wooden crates right." | 4K frame t=1.00 crops via `/usr/bin/magick -crop`: left margin = vintage car rear fender + wheel; right margin = stacked wooden crates; gold Art Nouveau scrollwork on both window frames; wet cobblestones with specular neon reflections across the street; `read annotated/KF01`. Left/right check: not swapped. | PASS |
| 3 | `BREAKDOWN.md:88` (V3) "Wet-stone specular response, glowing purple egg/orb in upper display (KF01#2)." | 4K t=1.00 crop of the upper display + `/usr/bin/magick %[pixel:p{1738,712}]` = `srgb(149,39,126)` purple glow on the egg/orb; wet-stone specular highlights on cobbles; `read annotated/KF01` badge #2 "Shopfront Orb & Lamp" points at the orb. | PASS |
| 4 | `BREAKDOWN.md:89` (V5) "Stationary idle guard in uniform, helmet, brown belt before the shopfront (KF01#4)." | 4K guard crop (560x900+1330+1050): uniform jacket with red piping, dark helmet, brown leather belt with buckle at waist, standing before the double doors; motion probe: guard-region SAD best offset between t=0.50 and t=2.00 = (dx,dy) (0,0), mean abs diff 4.8 (rain/flicker noise only) => stationary; `read annotated/KF01` badge #4 on the guard. | PASS |
| 5 | `BREAKDOWN.md:91` (V7) "Locked-off wide shot" | Column-edge profiles (`/usr/bin/magick -colorspace Gray` -> per-column means -> top gradient peaks) at t=0.50 vs t=2.00: shared structural edges at x=1912/2082/2621/2666 identical in both frames (0 px shift); the only differing peaks lie in the neon-sign band where the sign itself flickers (dim 00:00.10 / left-half off 00:02.05 per the same doc). No camera movement detectable. | PASS |
| 6 | `BREAKDOWN.md:130` (V2) "Dark-indigo sky, textured pale full moon upper-right." | `/usr/bin/ffmpeg -ss 2.30 -i "$HOME/Videos/clip_1,795,033,698,901.mp4" -frames:v 1` (inside S02 00:02.15-00:02.60); grey-pgm blob centroid of the moon = (75.7%, 22.0%) = upper-right, peak grey 91 (pale, mottled texture visible in crop); sky probe `srgb(13,11,32)` dark indigo; `read annotated/KF12` badge #2 "Illustrated Full Moon" on the disc. | PASS |
| 7 | `BREAKDOWN.md:167` (V1) "Volumetric teal-cyan moonlight shaft through arched frosted window (KF02#1); warm candle points vs cool shaft." | `/usr/bin/ffmpeg -ss 4.50 -i "$HOME/Videos/clip_1,795,033,698,901.mp4" -frames:v 1`; `/usr/bin/magick %[pixel:p]`: shaft `srgb(49,87,90)` teal-cyan (G≈B>R) through the arched leaded window, candle flame `srgb(64,34,32)` warm (R>G>B) on the rolltop desk; `read annotated/KF02` badges #1 "Volumetric Moon Shaft" and #5 "Candlelit Rolltop Desk" on target. | PASS |
| 8 | `BREAKDOWN.md:1217` (V6) "Two crisp horizontal white volumetric security beams from the left-wall emitter (KF27#1); glowing cyan diamond security/junction node above the far doors (KF27#3)." | `/usr/bin/ffmpeg -ss 207.60 -i "$HOME/Videos/clip_1,795,033,698,901.mp4" -frames:v 1`; grey-row profile finds two horizontal streaks y=868-871 (40.2%) and y=887 (41.1%) with leftmost bright pixel x≈670 (17.4%) = the wall emitter; cyan node visible above the far doors; `read annotated/KF27` badges #1/#3 on target. | PASS |
| 9 | `BREAKDOWN.md:1209` "a mid-height circular glowing white beam emitter on the left wall (`x~17%, y~56%`)" | Blob measurement (`/usr/bin/magick` grey pgm, max-bright cluster) on the segment's own keyframe: emitter centroid (17.8%, 40.3%) in the 4K extract at 03:27.60 and (17.8%, 40.0%) in `clean/KF27`; `read annotated/KF27` badge #1 leader dot also at y≈40%; S24 cross-check at 03:28.90 gives beam rows at 39-40%. `x~17%` matches (17.8%) but `y~56%` is contradicted by ~16 points of frame height (~350 px at 4K) - no sampled S24 moment puts the emitter at 56%. | REFUTED |
| 10 | `BREAKDOWN.md:1268` (V6) "Purple crystalline arcane ward sealing the main archway (KF28#2); green arcane vine lock across the `Basement Stairs` doorway (KF28#5); the white security beam continues projecting into the triggered ward (KF28#1)." | `/usr/bin/ffmpeg -ss 215.00 -i "$HOME/Videos/clip_1,795,033,698,901.mp4" -frames:v 1` (03:35.00): purple crystalline barrier seals the archway, green thorny vines lock the doorway beside the framed `Basement Stairs` plaque (badge #3), white beam streak entering the ward; `read annotated/KF28` badges #2/#5/#1 on target. | PASS |
| 11 | `BREAKDOWN.md:1315` (V4) "Plain dark grey/slate staircase treads (KF29#1), handrails, upper landing gallery with framed pictures; unlit slate remains visible outside the alarm cone." | Region averages (`/usr/bin/magick -crop ... -resize 1x1!`): unlit treads at 03:38.00 `srgb(7.0%,6.5%,7.5%)` neutral dark grey; at 03:39.40 (KF29) upper unlit treads `srgb(5.0%,4.6%,7.2%)` grey-blue vs lower treads `srgb(22.6%,6.8%,8.9%)` red-dominant only inside the 03:38.20-03:39.60 wash; `read annotated/KF29` badges #1 "Unlit Slate Stair Treads" vs #2 "Crimson Alarm Spotlight" separate material from light. Adversarial "red stairs" hypothesis refuted by the unlit samples. | PASS |
| 12 | `BREAKDOWN.md:704` "top-left `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]` (no space before `[0/4,000]`)" (HUD verbatim) | `read clean/KF14_01m15s_saferoom_portal_hud.jpg` + `KEYFRAME_INDEX.md:192` §5.2 "Top-left: `(£) 0`, `Mission: Steal 4,000 in loot value[0/4,000]` (no space before `[0/4,000]`)" + 4K crop `/usr/bin/ffmpeg -ss 75.75 ... -crop 1400x360+40+120`: rendered glyphs read `Mission: Steal 4,000 in loot value[0/4,000]` with zero gap before `[0/4,000]`, and the circled-£ coin + `0`. All three agree. | PASS |
| 13 | `BREAKDOWN.md:597` "`[TAB] MAP [MMB] [HOLD] PING MENU` (KF14#3-#5)" (HUD verbatim) | `read clean/KF14_...jpg` + §5.2 bottom-left bullet + §5.1 "HUD Ping Menu Binding" resolution (scroll-wheel highlighted white on mouse icon = `[MMB]`) + 4K crop `-crop 900x420+40+1720`: `TAB` keycap, `MAP`, mouse glyph with middle/scroll area highlighted, `[HOLD] PING MENU`. Mapping matches the doc's `[MMB]` rendering. | PASS |
| 14 | `BREAKDOWN.md:1376` "four centered vertical items `RESUME`, `SETTINGS`, `RETURN TO THIEF'S DEN` (straight apostrophe), `QUIT TO DESKTOP` (KF30#2)" (HUD verbatim) | `read clean/KF30_03m43s_pause_menu.jpg` + §5.2 "Pause Menu: `RESUME`, `SETTINGS`, `RETURN TO THIEF'S DEN`, `QUIT TO DESKTOP`" + 4K crop `/usr/bin/ffmpeg -ss 223.20 ... -crop 1700x1300+1050+350`: four items exactly as quoted; apostrophe in `THIEF'S` renders as a straight tick (not curly); single cursor on `QUIT TO DESKTOP` (matches the 03:43.10-03:43.30 clean-hover window). | PASS |
| 15 | `BREAKDOWN.md:1404` "footer `1.5.148559   Novice   1025051536`" (HUD verbatim) | `read clean/KF30_...jpg` (footer bottom-left reads `1.5.148559  Novice  1025051536`) + §5.2 footer string + 4K crop `-crop 1500x220+40+1930`: `1.5.148559   Novice   1025051536` digit-for-digit (crop's left edge clips the leading `1`, fully visible in clean KF30). | PASS |
| 16 | `BREAKDOWN.md:310` "Black Market: `YOUR TOTAL ASSETS: (£) 26,275`" (HUD verbatim) | `read clean/KF08_00m28s_ledger_black_market.jpg` + §5.2 "Header: `YOUR TOTAL ASSETS: (£) 26,275`" + 4K crop `/usr/bin/ffmpeg -ss 28.50 ... -crop 1500x300+1350+280`: `YOUR TOTAL ASSETS: (£-in-circle) 26,275` where the circled pound-coin glyph is what the doc renders as `(£)`; digits `26,275` verbatim. | PASS |
| 17 | `BREAKDOWN.md:1097` "`[F] OPEN` over `[F] [HOLD] LOCK` (`03:00.60-03:01.00`), flipping to `[F] CLOSE` (`03:01.20`) on open." (HUD verbatim) | `read clean/KF24_03m00s_locked_blue_double_doors.jpg` + §5.1 "Blue Double Doors Prompts" row + 4K crops `/usr/bin/ffmpeg -ss 180.60 ... -crop 1100x500+1380+850` shows `[F] OPEN` stacked above `[F] [HOLD] LOCK` at the reticle; `-ss 181.20` crop shows `[F] CLOSE` at the reticle after the swing. Both states match. | PASS |

### Audio & gameplay-timing claims (`_build/adv_audio_time.md`)

| # | Claim | Evidence command | Verdict |
|---|---|---|---|
| 1 | `BREAKDOWN.md:145` — S02: rain fades "to `-82.0 dBFS`" (`00:02.2-00:02.4`); "re-measured seg RMS `-63.2 dBFS`" | `/usr/bin/ffmpeg -ss 2.2 -to 2.4 -i "$W" -af astats=metadata=0:reset=0 -f null -` and `/usr/bin/ffmpeg -ss 2.15 -to 2.60 -i "$W" -af astats=metadata=0:reset=0 -f null -` (+ boundary variants `2.15/2.152 x 2.536/2.6/2.604/2.61/2.62/2.63/2.65`) | PASS |
| 2 | `BREAKDOWN.md:146` — S02 `00:02.4-00:02.6` "Digital zero `-240.0 dBFS`" | `/usr/bin/ffmpeg -ss 2.4 -to 2.6 -i "$W" -af astats=metadata=0:reset=0 -f null -` (plus onset probes `2.25-2.30`, `2.28-2.30`) | PASS |
| 3 | `BREAKDOWN.md:271` — S05 wind swell "rises to `-29.84 dBFS` peak in the `00:21.3` window (`astats.1s`); doc `pk=-29.8 dBFS`" | `/usr/bin/ffmpeg -ss 21.3 -to 21.4 -i "$W" -af astats=metadata=0:reset=0 -f null -` and `/usr/bin/ffmpeg -ss 19.6 -to 21.9 -i "$W" -af astats=metadata=0:reset=0 -f null -` | PASS |
| 4 | `BREAKDOWN.md:272` — S05 footsteps "`pk=-27.10 dBFS` at `00:23.74` (`astats.1s`); doc `pk=-27.1 dBFS`" | `/usr/bin/ffmpeg -ss 23.1 -to 23.9 -i "$W" -af astats=metadata=0:reset=0 -f null -` (+ peak-location probes `23.64-23.74` / `23.74-23.84` / `23.84-23.94`) | PASS |
| 5 | `BREAKDOWN.md:373` — S07 gramophone "`pk=-24.92 dBFS` at `00:45.67` (`astats.1s`), block RMS `-42.33 dBFS`" | `/usr/bin/ffmpeg -ss 45.4 -to 47.8 -i "$W" -af astats=metadata=0:reset=0 -f null -` (+ segment `/usr/bin/ffmpeg -ss 38.17 -to 51.08 ...`; peak-location probes `45.57-45.67` / `45.67-45.77` / `45.77-45.87`) | PASS |
| 6 | `_build/audio_s05_s27.md:141` — S05 `showspectrumpic` numbers: "Segment spectral flatness `0.5604`, `73.4%` of image energy above 4 kHz" | `/usr/bin/ffmpeg -ss 18.24 -to 26.58 -i "$W" -lavfi showspectrumpic=s=1000x500:legend=0:fscale=log:scale=log:color=fire -frames:v 1 s05.png` (+ `scale=lin`, `scale=sqrt` renders), `/usr/bin/ffmpeg -i s05.png -pix_fmt gray -f rawvideo s05.gray`, then `/usr/bin/python3` flatness/hi4k pixel stats with the doc's row→frequency calibration | PASS |
| 7 | `_build/audio_s05_s27.md:81` — clip `ebur128`: "Integrated `-43.9 LUFS`", "LRA `16.7 LU`", "true peak `-20.2 dBFS`" (LRA low `-55.7` / high `-39.0`) | `/usr/bin/ffmpeg -i "$W" -filter_complex ebur128=peak=true:framelog=quiet -f null -` | PASS |
| 8 | `BREAKDOWN.md:242` — S05 span `00:18.24`-`00:26.58`, `8.34 s` (gameplay-segment boundary claim) | `grep -n 'S05.*00:18.24.*00:26.58' KEYFRAME_INDEX.md BREAKDOWN.md` + duration arithmetic `26.58-18.24` | PASS |
| 9 | `BREAKDOWN.md:491` — "6 countdown ticks at `1.00 s` intervals (`pk=-41.3 to -35.7 dBFS`)" | `grep -n 'Exact .1.00 s. intervals' KEYFRAME_INDEX.md` + `/usr/bin/python3` parse of the six tick times on `KEYFRAME_INDEX.md:124` and inter-tick deltas | PASS |
| 10 | `BREAKDOWN.md:717` — S14 guard VO *"I know someone's here!"* cue window `01:39.3-01:40.6` | `grep -n "I know someone's here" KEYFRAME_INDEX.md BREAKDOWN.md` + `/usr/bin/python3` containment check of the cue in the §2 S14 span `01:39.30-01:49.50` (`KEYFRAME_INDEX.md:45`) | PASS |

### Repo citations & annotated images (`_build/adv_cite_image.md`)

| # | Claim | Evidence command | Verdict |
|---|---|---|---|
| 1 | `docs/FIDELITY_GAPS.md:38` (BREAKDOWN S01/S03/S05/S07/S10/S12/S13… "geometry → #3, #4 `1:1_MATCH`") | `sed -n '38p' docs/FIDELITY_GAPS.md` → line states every shipped mesh is a real GLB, Guildhall 63,210 instances, 32 m chunks, 30,127 `PerInstanceSMData` across 39 `BPP_*` classes, 138 LevelInstance, `PeripheryA` collidable — supports the 1:1_MATCH geometry attribution | PASS |
| 2 | `docs/FIDELITY_GAPS.md:25` (BREAKDOWN S03/S05/S12 "Moon shaft / bounce light → HARD_LIMIT (HL-7)") | `sed -n '25p' docs/FIDELITY_GAPS.md` → "Post-process / fog \\| 2 `PostProcessVolume`, 1 `ExponentialHeightFog` \\| fog + Godot-mappable post-process applied; **Lumen-only fields logged as unmappable**" — exactly the HL-7 basis | PASS |
| 3 | `docs/FIDELITY_GAPS.md:198` (BREAKDOWN PG-2 rows: S03/S04/S06/S08/S09/S11/S13/S14/S15/S17/S18/S20/S21/S22/S23/S24/S25/S26) | `sed -n '198p' docs/FIDELITY_GAPS.md` → "E2E 21 shots `parity 14/7` … 7 content fails (map look-at card, wardrobe clipped controls, lobby FOV-20 x2, zipwire equip, guard pips/arcs, circular lockpick)" — the named PG-2 fail set is present verbatim | PASS |
| 4 | `docs/FIDELITY_GAPS.md:18` and `:55-59` (BREAKDOWN S23 "Missing 1P idle/blend transitions → HARD_LIMIT (HL-4)") | `sed -n '18p;55,59p' docs/FIDELITY_GAPS.md` → ":18 **995 GLB clips** (357 ACL-decoded, exact durations, manifest); **14 blend-space graphs unsupported**"; ":58-59 (995 clips …); 14 blend-space graphs remain unsupported" — supports HL-4 | PASS |
| 5 | `docs/HANDOFF_NEXT_SESSION.md:115` (BREAKDOWN S01/S07/S12/S14/S20 "→ APPROX_SHADER (PG-5)") | `sed -n '115p' docs/HANDOFF_NEXT_SESSION.md` → "Optional residual parity (polish leftovers, low priority): Startscreen ambient/exposure match and neon core saturation vs UE's pale gold" — supports the PG-5 neon/exposure attribution | PASS |
| 6 | `docs/HANDOFF_NEXT_SESSION.md:99, 113` (BREAKDOWN S22/S24/S25 "VFX → HARD_LIMIT (HL-1)") | `sed -n '99p;113p' docs/HANDOFF_NEXT_SESSION.md` → both lines: "120/120 systems catalogued … spawn rate/lifetime/velocity live in compiled VectorVM bytecode and loop duration is null for all of them; 91 of the 139 resolved renderer materials carry no texture" | PASS |
| 7 | `docs/HANDOFF_NEXT_SESSION.md:111` (BREAKDOWN S04 "Clipped controls (live parity fail) → KNOWN_GAP (PG-2)") | `sed -n '111p' docs/HANDOFF_NEXT_SESSION.md` → "E2E 21 shots parity `14/7` … Remaining: … parity-harness aliases (S03/S04/S06a-b/S11/S14/S15b …)" — S04 is the clipped-controls scenario, so the line carries the cited gap | PASS |
| 8 | `docs/HANDOFF_NEXT_SESSION.md:111` (BREAKDOWN S07 "Decoration-swap station + prompts → KNOWN_GAP (PG-2)") | `sed -n '111p' docs/HANDOFF_NEXT_SESSION.md` → the line enumerates the remaining parity work as aliases for "S03/S04/S06a-b/S11/S14/S15b" — S07 is absent — and the 7 named content fails at `docs/FIDELITY_GAPS.md:198` (map look-at card, wardrobe clipped controls, lobby FOV-20 x2, zipwire equip, guard pips/arcs, circular lockpick) contain no decoration-swap item; the cited line therefore contradicts attaching a S07 PG-2 gap to it | REFUTED |
| 9 | `docs/HANDOFF_NEXT_SESSION.md:112` (BREAKDOWN S21 "`[F] OPEN` / `[F] [HOLD] LOCK` door swing" and S26 "Stairs traversal fix (50° / 0.3 snap)") | `sed -n '112p' docs/HANDOFF_NEXT_SESSION.md` → "`2799c8e` stairs snap/angle + suite 45 … `b58c69e` open-leaf disable 70° + Den window gap + suite 46 … Live blocked: … crank headless-only" — supports both UNVERIFIED_LIVE / PG-4 rows | PASS |
| 10 | `docs/HANDOFF_NEXT_SESSION.md:21, 112` (BREAKDOWN S27 "Quit-to-desktop teardown → UNVERIFIED_LIVE (PG-1)") | `sed -n '21p;112p' docs/HANDOFF_NEXT_SESSION.md` → ":21 … screenshot teardown breaks, no 60 FPS profile"; ":112 … screenshot swapchain/`X connection` teardown breaks, no 60 FPS profile" — supports PG-1 | PASS |
| 11 | `docs/HANDOFF_NEXT_SESSION.md:119, 170` (ledger PG-1: "each line verbatim-verified") | `sed -n '119p;170p' docs/HANDOFF_NEXT_SESSION.md` → :119 "Den RD cascade (reported `strip 0=591 / 1=17 / 2=569`), parity `14/21`, crank proven headless-only, screenshot swapchain/`X connection` teardown breaks, no 60 FPS profile. TEMP `--env-strip=0-8` hook"; :170 names the same Phase-4 commits incl. "stairs snap `0.3` / angle `50`" and "`OPEN_DISABLE_DEG 70.0`" | PASS |
| 12 | `docs/HANDOFF_NEXT_SESSION.md:47` (BREAKDOWN S01 "Menu stack (PLAY/SETTINGS/CREDITS/QUIT)", S01 "CineCamera framing", S05 "Telescope scripted sky view", S10 "Loading art + spinner", S27 "Pause modal + 4-button stack", S27 "Build/difficulty/seed footer" — all `1:1_MATCH`) | `sed -n '40,50p' docs/HANDOFF_NEXT_SESSION.md` → the whole cited line reads "- HUD: real tool icons (StyleBox slots), F3 overlay, timer countdown, downed countdown, mobile touch layer (`docs/ANDROID.md`)." It contains no menu stack, no CineCamera, no telescope, no loading art, no pause modal and no build/seed footer; neighbours :44-:46 are Characters / Gameplay data / Spawn quality and :48-:49 are Contract titles / safe-room overhang — no cited line in the file supports those six `1:1_MATCH` rows | REFUTED |
| 13 | `game/src/core/audio_manager.gd:6-14` (BREAKDOWN S01/S03/S05/S07/S11/S12/S13/S16/S17/S20 "rain bed / room tone / gramophone jazz / no BGM → KNOWN_GAP (PG-6)") | `sed -n '6,14p' game/src/core/audio_manager.gd` → exactly nine fallback preloads (`footstep`, `blackjack`, `lockpick`, `grapple`, `smoke`, `fairy`, `alert`, `loot`, `door` `.wav`), no music/ambience/UI-audio asset present — supports PG-6 | PASS |
| 14 | `game/src/core/audio_manager.gd:29-37` (BREAKDOWN S04/S06/S08/S09/S10/S15/S17/S18/S20/S21/S22/S23/S24/S25/S26/S27 "ticks / SFX / no BGM → KNOWN_GAP (PG-6)") | `sed -n '28,39p' game/src/core/audio_manager.gd` → `_ready()` assigns the same nine one-shot fallbacks and wires `NoiseBus.noise_emitted`; one static clip per tag, no music bus — supports PG-6 | PASS |
| 15 | `game/src/core/level_loader.gd:68-112` (BREAKDOWN S26 "Crimson alarm spotlight lighting → #6 `1:1_MATCH`", PG/HL column "-") | `sed -n '72,96p' game/src/core/level_loader.gd` → the range's own comment says the authored-intensity mapping is "a documented approximation: a single linear scale preserves the authored RATIO inside the band and only compresses at the extremes" (`LIGHT_INTENSITY_SCALE 0.0666667`, floor `0.01`, ceil `4.0`, range ceiling `200.0`); the range contains no crimson/alarm spotlight, and BREAKDOWN files the same subsystem #6 lighting under HARD_LIMIT (HL-7) at S13/S15/S17/S20/S21 — "1:1_MATCH" contradicts the cited text | REFUTED |
| 16 | `game/src/ai/guard_ai.gd:5-160` (BREAKDOWN S22/S23 guard rows; ledger subsystem #13) | `sed -n '5,8p;21,27p;49,64p;75,107p' game/src/ai/guard_ai.gd` → `enum Alertness { NEUTRAL, SUSPICIOUS, ALERTED, COMBAT, SEARCH, KNOCKED_OUT }` (:5), `signal carried_item_stolen` (:8), speeds 1.5/1.7/2.5 (:21-23), sight 20/30 (:24-25), FOV 80° (:27), decay base 7.0 s (:57-64), thresholds 15/45/100 (:80-82), `DEFAULT_KEY_GLB = SK_LootableKeys_LockedRoomKey.glb` (:14) — supports both the pickpocket 1:1_MATCH row and ledger #13 | PASS |
| 17 | `game/src/missions/mission_controller.gd:1-160` (BREAKDOWN S24 "Security camera/spotlight sweep logic → UNVERIFIED_LIVE") | `sed -n '1,160p' game/src/missions/mission_controller.gd` → range holds only preloads (:7-20), Den state vars (:55-67), environment setup (:100-115) and the TEMP `--env-strip` hook (:143-160); `grep -nEi 'lockdown\\|tripwire\\|security_cam\\|camera_sweep' game/src/missions/mission_controller.gd` → 0 hits in the whole 1925-line file; the only camera/beam code is `moon_beam` (:470-486), outside the cited range — the cited range cannot evidence a security-camera sweep | REFUTED |
| 18 | `game/src/missions/mission_controller.gd:1-160` (BREAKDOWN S25 "Beam tripwire → ward lockdown trigger → UNVERIFIED_LIVE") | same range read + `grep -nEi 'lockdown\\|tripwire' game/src/missions/mission_controller.gd` → 0 hits in the entire file; `grep -n 'ward' …` hits only Wardrobe UI (:23, :611-651) and the Den moon-beam godray (:470-486). No ward/lockdown/tripwire symbol exists, so the cited range cannot evidence a beam-tripwire → ward-lockdown trigger | REFUTED |
| 19 | `docs/reports/player-1p.md:1-123` (BREAKDOWN S21 "1P hands + ZipWire `[1]` viewmodel → `1:1_MATCH`") | `sed -n '98,104p' docs/reports/player-1p.md` → ":99 No 1P idle or jump clip exists in the install — stationary holds bind pose."; ":101-104 Disguise 1P clips … and zipwire 1P clips (`AN_Zipwire_{Walk,Run}_F_1P`, `AN_Zipwire_Travel[_Start]_1P`) exist in the manifest and parse through the same path — available for later (disguise/zipwire states), **not wired in this stage**." — the cited report states the zipwire 1P viewmodel is not wired, contradicting `1:1_MATCH` | REFUTED |
| 20 | `docs/reports/guard-animations.md:131-143` (BREAKDOWN S22 "Constable clasped-hands idle + blue baton" and S23 "1P takedown grapple animation" → KNOWN_GAP (PG-7); ledger #13) | `sed -n '131,143p' docs/reports/guard-animations.md` → "## Limits (stated plainly) … Locomotion is in-place; cadence vs scripted speed is approximate, so some foot slide remains (worst: alert sprint at ~3× chase speed)" (:135-136), "Hauntstable weapon set reuses the Club attack montage" (:139-142) — supports PG-7 and ledger #13 | PASS |
| 21 | `docs/reports/fidelity-mechanics-wave.md:84-112` (ledger PG-2 fail table + scenario-ID disambiguation) | `sed -n '84,112p' docs/reports/fidelity-mechanics-wave.md` → 21-shot table with FAILs exactly at S03 `map_table_look_at_card`, S04 `clipped_controls`, S06a/S06b `mission_lobby_fov_20`, S11 `equipped_tool!=zipwire`, S14 `guard_pips_and_offscreen_arcs`, S15b `circular_lockpick_minigame_ui` — matches the ledger's "port E2E scenario IDs, not clip segments" note | PASS |
| 22 | `docs/reports/fidelity-mechanics-wave.md:190` (ledger subsystem #10 "stairs fix `2799c8e`") | `sed -n '190p' docs/reports/fidelity-mechanics-wave.md` → "`2799c8e` \\| fix(movement): stairs snap `0.3` / angle `50` (`FLOOR_MAX_ANGLE_DEG 60 -> 50`, `FLOOR_SNAP_LENGTH 0.3` …)" — supports ledger #10 | PASS |
| 23 | `docs/reports/fidelity-mechanics-wave.md:200-226` (ledger PG-1) | `sed -n '200,226p' docs/reports/fidelity-mechanics-wave.md` → :202 Den RD cascade `strip 0=591 / 1=17 / 2=569`; :203 parity `14/21`; :206 teardown breaks; :207 no 60 FPS profile; :209-218 "### 6.4 TEMP debug hook (uncommitted — do NOT commit as-is)" — supports PG-1 | PASS |
| 24 | `docs/reports/audio-wwise.md:95-111` (ledger subsystem #16 and PG-6 "9-tag verification table") | `sed -n '95,111p' docs/reports/audio-wwise.md` → "### Tag wiring — All nine gameplay tags were verified against a real event dump and a resolved clip" plus the 9-row tag/event/EventId/media table — supports PG-6 | PASS |
| 25 | `docs/reports/audio-wwise.md:118-125` (ledger HL-6 + correction C4) | `sed -n '118p;120,125p' docs/reports/audio-wwise.md` → :118 "`51` adjacent equal-size RIFF pairs"; :122 "The order join is proven by size statistics, not by content hashing"; :123 "The `6` media entries remain unresolved: the convolution-reverb IRs in PLUG chunks" — confirms correction C4's `:118-125` | PASS |
| 26 | `docs/reports/audio-wwise.md:56` (ledger HL-6 "5 long weather/ambience loops (90–211 s)") | `sed -n '56p' docs/reports/audio-wwise.md` → "The five mismatches are long (`90–211 s`) weather/ambience loops. In every case the chunk is larger than `InMemoryMediaSize` … recorded as a hypothesis, not an established cause." — supports HL-6 | PASS |
| 27 | `game/src/core/save_system.gd:59-64` (ledger subsystem #16 and PG-6 "master-only") | `sed -n '59,64p' game/src/core/save_system.gd` → `apply_saved_settings()` reads `master_volume` and calls `AudioServer.set_bus_volume_db(0, …)` — bus 0 only, no music/SFX/dialogue bus — supports PG-6 | PASS |
| 28 | `docs/reports/level-components.md:160-161` (and `:66-67`) (ledger HL-8; ledger verification-record spot-check #3) | `sed -n '66,67p;160,161p' docs/reports/level-components.md` → ":66-67 landscape_splines 52 (3 files, all with mesh; 0 with authored material … field "")"; ":160-161 `landscape_splines[].material` is `\"\"` for all 52 (no material authored on SplineMeshComponents in dumps) — recorded, not fabricated." — supports HL-8 | PASS |
| 29 | `game/src/core/mobile_profile.gd:1-127` (ledger correction C3 for subsystem #18) | `sed -n '10p;58,67p;82,91p;112,115p' game/src/core/mobile_profile.gd` → `enum Tier { PERFORMANCE, BALANCED, QUALITY }` (:10), `max_lights()` 12 / 24 / 32 (:58-67), `render_scale()` 0.7 / 0.85 / 1.0 (:82-91), `target_fps()` 30 / 60 (:112-115) — confirms the C3 widened range `:1-127` | PASS |
| 30 | `annotated/KF01_00m01s_startscreen.jpg` | read + `render_annotations.py --check` → "KF01 KF01_00m01s_startscreen.jpg legend=BR OK"; badges read on the image: [1] Neon Sign & Flicker (amber), [2] Shopfront Orb & Lamp (amber), [3] Title & Menu Stack (cyan), [4] Idle Guard Patrol (magenta), [5] Puddle & Rain Streaks (amber), [6] Rain Ambience (No BGM) (magenta) = `CALLOUT_LEGENDS.md` KF01 rows 1-6, with corner legend "KF01 00:01.00 S01" | PASS |
| 31 | `annotated/KF05_00m20s_telescope_cheese_moon.jpg` | read + `--check` → "KF05 … legend=BR OK"; badges [1] Night Sky & Moon (amber), [2] Golden Cheese Wedge (amber), [3] Orbiting Cheese Chunks (amber), [4] Telescope [F] EXIT (cyan), [5] Rooftop Wind Swell (magenta) = KF05 rows 1-5; corner legend "KF05 00:20.80 S05" | PASS |
| 32 | `annotated/KF10_00m52s_den_map_table.jpg` | read + `--check` → "KF10 … legend=BL OK"; badges [1] Mission Settings Card (cyan), [2] 3D Map Token Selected (magenta), [3] Center [F] ENTER MATCH (cyan), [4] Brass Banker's Lamp (amber), [5] Marble Bust & Card (amber), [6] Bottom-Right Legend (cyan), [7] Map Toggle Clicks (magenta) = KF10 rows 1-7; corner legend "KF10 00:52.35 S08" | PASS |
| 33 | `annotated/KF14_01m15s_saferoom_portal_hud.jpg` | read + `--check` → "KF14 … legend=BR OK"; badges [1] Escape Portal Wall VFX (amber), [2] Warm Oil Lantern Glow (amber), [3] Loot Tracker (No HP) (cyan), [4] Player Card & Compass (cyan), [5] Hotbar & Ping Menu (cyan), [6] Lit Light Gem (cyan), [7] Faint Noise Arcs (cyan), [8] Nisha VO & Lantern (magenta) = KF14 rows 1-8; corner legend "KF14 01:15.75 S12" | PASS |
| 34 | `annotated/KF17_01m51s_zipwire_aim_roof.jpg` | read + `--check` → "KF17 … legend=TL OK"; badges [1] Anchored ZipWire Cable (magenta), [2] Clocktower Fog Silhouette (amber), [3] CRANK [LMB] Progress Ring (cyan), [4] Guard Alert Direction Pip (cyan), [5] Ratchet Crank Audio Cue (magenta), [6] Dark Concealed Light Gem (cyan) = KF17 rows 1-6; corner legend "KF17 01:51.20 S15" (guard-alert pip is drawn as its own crimson element, distinct from the gem arcs) | PASS |
| 35 | `annotated/KF19_02m25s_smoke_bomb_equip.jpg` | read + `--check` → "KF19 … legend=None OK" (the renderer omits the corner legend where it would overlap HUD; omission is allowed by the renderer, all badges still rendered); badges [1] Health Bar Revealed (~75%) (cyan), [2] Griffin Statue & Bridge (amber), [3] Distant MACLEOD Sign (amber), [4] Smoke Bomb [2] Canister (magenta), [5] THROW [LMB] Prompt (cyan), [6] Warm-Lit Light Gem (cyan), [7] Guard Shout VO (magenta) = KF19 rows 1-7 | PASS |
| 36 | `annotated/KF24_03m00s_locked_blue_double_doors.jpg` | read + `--check` → "KF24 … legend=None OK"; badges [1] Blue Diamond-Mullion Doors (amber), [2] [F] OPEN Prompt (cyan), [3] [F] [HOLD] LOCK Prompt (cyan), [4] ZipWire [1] Ready (magenta), [5] Fully Lit Light Gem (cyan), [6] Small Noise Arcs (cyan), [7] Door Latch & Creak (magenta) = KF24 rows 1-7 | PASS |
| 37 | `annotated/KF28_03m35s_foyer_arcane_barriers.jpg` | read + `--check` → "KF28 … legend=None OK"; badges [1] Sweeping Security Beam (amber), [2] Purple Crystalline Ward (amber), [3] Basement Stairs Plaque (magenta), [4] Overhead Security Camera (magenta), [5] Green Arcane Vine Lock (amber), [6] Status Icons Above Gem (cyan), [7] Half-Lit Light Gem (cyan), [8] Ward Tripwire Chime (magenta) = KF28 rows 1-8 | PASS |
| 38 | `annotated/KF30_03m43s_pause_menu.jpg` | read + `--check` → "KF30 … legend=BR OK"; badges [1] Teal/Copper Art-Nouveau Frame (amber), [2] Pause Action Buttons (cyan), [3] QUIT TO DESKTOP Hover (cyan), [4] -19 dB Ambience Ducking (magenta), [5] Build & Seed Footer (cyan) = KF30 rows 1-5; corner legend "KF30 03:43.20 S27". Note (not a badge mismatch): `magick annotated/KF30_03m43s_pause_menu.jpg -crop 460x70+0+1010 +repage -resize 200% png:-` shows the row-5 footer string clipped by the left frame edge (visible text ".5.148559   Novice   1025051536" — the leading "1" of "1.5.148559" is cut off in the frame) | PASS |

### Tally

| Class | Count | Threshold | Proven by |
|---|---|---|---|
| Claim checks (measured claims attacked against the 4K source / re-measured audio) | **27** | >= 12 | 17 rows from `_build/adv_visual_hud.md` (rows 1-11 visual V1-V7, rows 12-17 HUD verbatim strings) + 10 rows from `_build/adv_audio_time.md` (rows 1-7 `astats` / `showspectrumpic` / `ebur128`, rows 8-10 gameplay timing) |
| Image re-opens (annotated / clean keyframes opened and read back) | **21** | >= 6 | 9 from `_build/adv_cite_image.md` rows 30-38 (KF01, KF05, KF10, KF14, KF17, KF19, KF24, KF28, KF30) + 6 annotated badge re-opens (KF01, KF02, KF12, KF27, KF28, KF29) + 6 clean-keyframe HUD-verbatim re-opens (KF14 x2, KF30 x2, KF08, KF24) from `_build/adv_visual_hud.md`; 14 distinct keyframes |
| Citation re-opens (cited repo files re-read at the cited line range) | **34** | >= 8 | 29 from `_build/adv_cite_image.md` rows 1-29 + 5 from `_build/adv_audio_time.md` rows 6-10 (`_build/audio_s05_s27.md:141`, `:81`, `KEYFRAME_INDEX.md:124`, `:45`, `:36`) |

**65 verdict rows appended (17 + 10 + 38) - 58 PASS / 7 REFUTED.** Every threshold is met:
27 claim checks (>= 12), 21 image re-opens (>= 6), 34 citation re-opens (>= 8).

### Refuted rows and the fixes applied

All 7 REFUTED rows were repaired at their cited line; no other file outside this log was touched.

1. **`adv_visual_hud.md` row 9 - `BREAKDOWN.md:1209`** (S24 beam emitter at `x~17%, y~56%`): the
   vertical coordinate was contradicted - emitter centroid measured `(17.8%, 40.3%)` in the 4K extract of
   the segment's own keyframe KF27 and `(17.8%, 40.0%)` in `clean/KF27`, the `annotated/KF27` badge #1
   leader dot sits at `y≈40%`, and the S24 cross-check at `03:28.90` puts the beam rows at `39-40%`.
   **Fix:** `BREAKDOWN.md:1209` now reads `x~17%, y~40%`. The same fact is indexed three times, so
   `KEYFRAME_INDEX.md` §2 S24, §3 KF27 and §5.1 were corrected to `y~40%` and an `## Errata` entry was
   added per the index format (index fact -> errata required).
2. **`adv_cite_image.md` row 8 - `BREAKDOWN.md:383`** (`Decoration-swap station + prompts |
   KNOWN_GAP (PG-2) | docs/HANDOFF_NEXT_SESSION.md:111`): the cited line enumerates the
   parity-harness aliases and the 7 named content fails, none of which is a decoration-swap item, so the
   `PG-2` tag was unsupported. **Fix:** the row is now `UNVERIFIED_LIVE` with the port implementation
   cited instead - `game/src/missions/mission_controller.gd:915-968` (`DenDecorationPedestal`,
   `DECORATIONS`, the `[F] CHANGE DECORATION` prompt and the cycle).
3. **`adv_cite_image.md` row 12 - seven `1:1_MATCH` rows in `BREAKDOWN.md`** (`:111` menu stack,
   `:113` CineCamera framing, `:151` loading art + spinner, `:282` telescope scripted sky view, `:530`
   loading art + spinner + emblem, `:1396` pause modal + 4-button stack, `:1397` build/difficulty/seed
   footer) all cited `docs/HANDOFF_NEXT_SESSION.md:47`, whose whole content is the HUD bullet ("real
   tool icons (StyleBox slots), F3 overlay, timer countdown, downed countdown, mobile touch layer") and
   supports none of them. **Fix:** each row now cites the port code that implements it -
   `game/src/ui/main_menu.gd:314-332` (PLAY / SETTINGS / CREDITS / QUIT),
   `game/src/ui/main_menu.gd:12-19` (authored CineCamera eye / forward / vFOV / pitch),
   `game/src/ui/loading_screen.gd:9-12` (loading art + spinner atlas + gold logo),
   `game/src/missions/mission_controller.gd:768-804` (`toggle_telescope_ponder` -> `_ponder_cam` cut),
   `game/src/ui/loading_screen.gd:9-12`, `game/src/ui/hud.gd:1513-1580` (pause modal, RESUME / SETTINGS /
   RETURN TO MAIN MENU / QUIT TO DESKTOP) and `game/src/ui/hud.gd:23, 1595-1603` (`VERSION_STRING`
   footer). The footer row was additionally downgraded from `1:1_MATCH` to `NOT_IMPLEMENTED`: the port's
   pause footer carries only `v1.5.148559` - there is no difficulty and no seed anywhere in `game/src`
   (difficulty is a main-menu option at `game/src/ui/main_menu.gd:380-384`).
4. **`adv_cite_image.md` row 15 - `BREAKDOWN.md:1345`** (`Crimson alarm spotlight lighting | #6 |
   1:1_MATCH | game/src/core/level_loader.gd:68-112`): the cited range is the authored-intensity scale
   only and names no crimson light. **Fix:** the citation now also names the light-spawn range that
   carries the authored colour (`game/src/core/level_loader.gd:2133-2185`, `light.light_color = col` at
   `:2172`). The authored crimson spots are `SpotLightComponent` rgb(255, 0, 36) in
   `game/data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json` (`lights[300-307]`,
   intensity 20, radius 12-16 m), so the port spawns the alarm spot with its authored crimson and only
   the energy mapping is the documented linear approximation.
5. **`adv_cite_image.md` row 17 - `BREAKDOWN.md:1243`** (`Security camera/spotlight sweep logic | #4,
   #17 | UNVERIFIED_LIVE | game/src/missions/mission_controller.gd:1-160`): the cited range holds
   preloads, Den state vars, environment setup and the `--env-strip` hook; `grep -nEi
   'lockdown|tripwire|security_cam|camera_sweep'` over the whole 1925-line file returns 0 hits, and no
   camera/sweep symbol exists anywhere in `game/src`. **Fix:** the row is now `HARD_LIMIT (HL-3)` with
   `docs/HANDOFF_NEXT_SESSION.md:102` (cooked Blueprint / QuestGraph behaviour graphs are not
   translated) - the limit this file's §7.2 HL-3 already maps onto S24.
6. **`adv_cite_image.md` row 18 - `BREAKDOWN.md:1294`** (`Beam tripwire -> ward lockdown trigger | #17
   | UNVERIFIED_LIVE | game/src/missions/mission_controller.gd:1-160`): `grep -nEi 'lockdown|tripwire'`
   over `game/src/missions/mission_controller.gd` returns 0 hits, and `ward` hits only the Wardrobe UI
   and the Den moon-beam godray. **Fix:** the row is now `HARD_LIMIT (HL-3)` with the same
   `docs/HANDOFF_NEXT_SESSION.md:102` citation (§7.2 HL-3 maps onto S25).
7. **`adv_cite_image.md` row 19 - `BREAKDOWN.md:1088`** (`1P hands + ZipWire [1] viewmodel | #11, #12 |
   1:1_MATCH | docs/reports/player-1p.md:1-123`): the cited report states the zipwire 1P clips are
   "available for later (disguise/zipwire states), not wired in this stage" (`:101-104`), which
   contradicts `1:1_MATCH`. **Fix:** the row is now `KNOWN_GAP (PG-7)` - the status this file's §6
   already gives subsystem #11 - citing the exact lines `docs/reports/player-1p.md:99-104`.

Residual observations (found while repairing the refuted rows, not themselves refutations): the port's
pause-menu third button reads `RETURN TO MAIN MENU` where the clip reads `RETURN TO THIEF'S DEN`, and
the port's decoration set is `faberge_egg` / `owl_statue` / `emerald` where the clip shows an owl ->
blue/silver spider-emblem chest swap. The pause-modal row therefore stays `1:1_MATCH` for the 4-button
stack and both deltas are carried here for the port-recording scorer.

Sections 1-10 of this file were not modified by this wave; only this `## Verification log` was
populated.
