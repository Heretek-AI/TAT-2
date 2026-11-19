# Handoff Report — Independent Visual + Audio Survey & Comparison Framework

**Summary:** `/home/john/Videos/clip_1,795,033,698,901.mp4` is a continuous `225.642s` (`00:03:45.64`) 4K H.264/AAC capture spanning 8 sequential acts from Startscreen through Thieves' Den, Mission Prep, and Constables' Guildhall infiltration to Pause/Quit. Zero images are currently tracked in git under `/home/john/Projects/TAT-2` (all prior QA captures live in gitignored `build/qa/`), and `game/src/missions/mission_controller.gd` carries a pre-existing uncommitted diff (`--env-strip=0-8`) that must be preserved untouched; accordingly, we define a tracked `1920x1080` JPEG (`clean/` + `annotated/`) norm under `docs/reference/clip_1795033698901/`, a 4-pillar 1:1 comparison checklist with color-coded numeric callouts, and a 3-milestone Worker execution plan.

---

## 1. Observation

### 1.1 Source Video Metadata (`/home/john/Videos/clip_1,795,033,698,901.mp4`)
Verified via `ls -lh` and `ffprobe -v quiet -print_format json -show_format -show_streams`:
- **File size**: `265,161,125` bytes (`253M`).
- **Container**: QuickTime/MOV (`isom`), `format.duration = "225.642333"` (`00:03:45.64`), `bit_rate = "9401112"` bps.
- **Video stream (`index 0`)**: `h264` (High@L5.2), `3840x2160` (`16:9`, SAR `1:1`), `yuvj420p` (`bt709`, `pc` range), `r_frame_rate = "179/6"` (`avg_frame_rate = "2110119665/71113994"` ≈ `29.672 fps`), `nb_frames = "6696"`, `duration = "225.529000"`.
- **Audio stream (`index 1`)**: `aac` (LC), `48000 Hz`, `stereo`, `start_time = "0.277000"`, `duration = "225.365333"`, `bit_rate = "161467"` bps.

### 1.2 Continuous Timeline & Visual/Audio Survey (`00:00` – `03:45.64`)
Directly observed across 4 staged 720p MP4+audio segments (`0–60s`, `60–120s`, `120–180s`, `180–225.6s`), `audio_full.mp3`, and `1920x1080` still frames (all staged in `/tmp/tat2_survey_4Rf8cV` and deleted prior to reporting):

| Segment | Timeline | Scene / Phase | Key Visual Observations | Key Audio Observations (incl. Explicit Absences) |
|---|---|---|---|---|
| **A1** | `00:00–00:01` | **Startscreen** (`MainMenu`) | Rainy night cobblestone street; *Mac Neish Jeweller* storefront with magenta/pink script neon + warm amber outer neon arches + horizontal awning neon bars; static guard before window; vintage car fender (bottom-left); crates (bottom-right); streetlamp (upper-right); wet puddle magenta reflection; right-aligned `THICK AS THIEVES` logo + `PLAY / SETTINGS / CREDITS / QUIT`. | Steady rain hiss + distant city ambience; crisp UI hover/click SFX on `PLAY`. **Absence:** no main-menu music score playing. |
| **A2** | `00:01–00:03` | **Loading Screen 1** | Stylized dark-indigo illustrated Kilcairn skyline; large pale full moon (upper-right); two silhouetted dirigibles/airships; central rotating ring + `LOADING...`; bottom-center gold `THICK AS THIEVES` emblem. | Rain fades cleanly into quiet transition/silence (~1.9s–4.0s low-level fade detected by `silencedetect`). **Absence:** no loading music or narration. |
| **A3** | `00:03–00:56` | **Thieves' Den Hub** | **00:03–00:05:** Spawn looking at plank floorboards & scattered papers; pans up/left to arched frosted blue-lit window casting crisp mullion shadows across floor, tripod telescope, rolltop desk with 3-candle candelabra + open ledger, map table, open wardrobe. Subtle top-center compass (`NW`); top-right player card (`Johnny Cipher`, Spider portrait, level `4`).<br>**00:06–00:18:** `[F] CUSTOMIZE LOADOUT` opens **Wardrobe UI** (`[Q]/[E]`, `WARDROBE`, `The Spider` active / `The Chameleon LOCKED`, `Edit Loadout` slots `1` ZipWire, `2` Smoke Bomb, `3` locked, `4` Vistara Diamond; right slots `Head / Body / Calling Card` + grid with padlocks and bottom-left preview cards).<br>**00:19–00:22:** Telescope `[F] PONDER` cuts to rooftop night sky showing giant rotating golden **cheese wedge** + orbiting chunks before full moon (`[F] EXIT`).<br>**00:22–00:25:** `WANTED` posters on wall beside frosted window.<br>**00:26–00:38:** `[F] READ LEDGER` opens **Ledger UI** (`[Q] JOURNAL` / `BLACK MARKET [E]`): `Level 4`, `94/500` XP bar, Contracts #1–#2 `Completed`, #3 `Active` (*In the Eye of the Beholder*); Black Market shows `YOUR TOTAL ASSETS: £ 26,275`, `TOOLS`, `GUILD PERKS`, `SPIDER COSMETICS`, `CHAMELEON COSMETICS`.<br>**00:39–00:49:** Radiator, rotary wall phone, crate props `[F] CHANGE DECORATION` (diamond, owl statue, goblet), glowing silver-white **footstep trail decals** on floorboards, **Gramophone** (`[F] TURN OFF` at `00:45`).<br>**00:50–00:56:** **Map Table** over *KILCAIRN* parchment with 3D building tokens (`ELWAY MANOR`, `CONSTABLES' GUILDHALL`), `[F] ENTER MATCH` (`Novice / Solo`), `[F] JOIN GAME / [R] TOGGLE MODE / [H] TOGGLE DIFFICULTY`, confirmation modal (`PREPARE FOR MISSION / CANCEL`). | Hollow wooden-floor footstep foley during movement; wardrobe wooden creak/latch & crisp UI selection ticks; strong outdoor wind/whoosh ambience during `00:20–00:21` telescope view; paper/page rustle & metallic UI clicks in Ledger; **Gramophone (`00:45–00:50`) introduces scratchy 1920s vinyl jazz/ragtime music** with audible record crackle, fading as player moves to Map Table; subtle map/modal confirmation chime (`00:55`). **Absence:** no background music prior to `00:45`. |
| **A4** | `00:56–01:04` | **Mission Preparation** | Left cards: `CONSTABLES' GUILDHALL`, `Mission: Cleanout Heist` (`Time Limit: 55 minutes`), `Contract Inactive` notice. Background: ThiefNisha in classic Spider pose atop slate roof ridge against blue-indigo skyline & large full moon. Bottom-right `READY` / `[F] UNREADY` / `[ESC] BACK`. Top-center `MISSION STARTING IN 6... 5... 4... 3... 2... 1...`. | Soft ambient wind bed; distinct rhythmic countdown tick/chime SFX once per second from `6` down to `1` (`00:59–01:04`). **Absence:** no music loop. |
| **A5** | `01:05–01:08` | **Loading Screen 2** | Same Kilcairn rooftop night illustration, moon, airships, central spinner `LOADING...`, gold logo. | Quiet transition / subtle ambient tail. |
| **A6** | `01:09–01:11` | **Briefing Letter** | Centered parchment note (`Esteemed Colleague - The Constables' Guildhall is a repository of countless treasures... 55 minute window... magic door will be summoned for 20 minutes before collapsing.`), `[SPACE] CONTINUE`. | Paper rustle on open/dismiss + faint exterior rain ambience beginning underneath. |
| **A7** | `01:11–03:41` | **Constables' Guildhall Gameplay** (`Steal 4,000 in loot value [0/4,000]`) | **01:11–01:17:** Safe-room alley spawn; lantern on crate (`[F] TURN ON` / `TURN OFF` warm flickering point light); animated jagged **green/purple Escape Portal** outline on wooden wall; HUD visible: top-left Health Bar + `£ 0` + mission objective, top-center compass, top-right player card, bottom-left hotbar (`[1]` ZipWire, `[2]` Smoke Bomb, `[4]` Vistara Diamond, `[TAB] MAP`, `[MMB] [HOLD] PING MENU`), bottom-center **Light Gem** (dark in shadow).<br>**01:17–01:25:** Metal catwalk traversal (`1P` gloved arms animate on vault/drop) down to wet cobblestone street (`SIMON'S DEMOLITION` wall sign, puddle specular reflections, falling rain streaks).<br>**01:25–01:38:** Courtyard gate approach; **guard detection** triggers red radial threat arcs around Light Gem + red directional pips (`01:27`, `01:41`); interacts with parked vintage car (`[F] INTERACT` at `01:35`) flashing headlights.<br>**01:39–02:23:** Equips **ZipWire** (`[1]`); aims reticle (`CRANK`), fires (`01:43`), drops into courtyard foliage/wall taking damage (top-left red health bar drops to ~65% at `01:44+`); fires ZipWire at roof beam (`01:51–01:57`) and holds crank (`[RMB]` `[HOLD] CRANK`) hoisting onto roofline (`01:58`); surveys `CONSTABLES' GUILDHALL` arched gate & twin griffin statues flanking stairs; zips onto central gate pillar (`02:09–02:18`, showing circular metal gear plate on pillar), drops to crates (`02:22`).<br>**02:24–02:32:** Equips **Smoke Bomb** (`[2]`), throws onto grand stairs (`02:27`), producing expanding volumetric grey-white smoke plume (`02:28–02:30`); equips **Vistara Diamond** (`[4]`, faceted glowing gem in 1P hand) pulsing to reveal **green guard silhouette** (`02:32`) and distant glints.<br>**02:33–03:01:** Re-equips ZipWire, sprints along upper balcony (sound-ripple ring pulses around Light Gem), vaults railing, opens double glass-and-wood doors (`[F] CLOSE`, `03:00`).<br>**03:02–03:20:** Interior warm fireplace room; approaches guard with hands clasped behind back (`[F] PICK POCKET` + `[F] [HOLD] TAKEDOWN` at `03:15`); acquires `Guildhall Key` (bottom-left above hotbar) and performs 1P takedown.<br>**03:21–03:41:** Checkered foyer: **purple crystalline ward barrier** across doorway (`03:29–03:35`), **wall-mounted sweeping security spotlight/eye** projecting narrow horizontal volumetric white beam (`03:31–03:37`), dual circular status icons above Light Gem (alert ring + sleeping-skull `zz` timer at `03:34`), red-carpeted grand staircase ascent (`03:38–03:41`). | **01:12:** ThiefNisha VO *"Let the thieving begin."*<br>**01:13–01:14:** Lantern click/ignite SFX.<br>**01:17–01:25:** Metallic grate footsteps -> drop thud -> wet stone footsteps + continuous rain patter.<br>**01:34–01:41:** Guard barks (*"What?"*, *"Who's too loud?"* / *"Get too loud..."*, *"I know someone's here"*, *"I will find you, thief"*) + loud double **vintage car horn** (`HONK-HONK!` at `01:35–01:36`) + alert sting.<br>**01:43–02:20:** ZipWire mechanical latch, launch twang, cable zip, ratcheting hand-crank SFX (`01:55–01:58`, `02:13–02:17`), impact grunt.<br>**02:27–02:32:** Smoke bomb clink + pressurized hiss/whoosh; Vistara Diamond crystalline chime pulse.<br>**02:33–03:01:** Crisp sprint footsteps, cloth rustle, heavy door latch/creak (`03:00`).<br>**03:15–03:20:** Pickpocket key jingle + melee takedown thud/guard groan + ThiefNisha VO (*"Let's get this done"*, *"And stay down"*).<br>**03:29–03:41:** Crystalline/arcane ward hum/chime + security beam sweep hum + carpeted stair footsteps.<br>**Absence:** **Zero continuous background music** during the entire Guildhall heist; audio relies strictly on rain/interior ambience, foley, spatialized barks, tool SFX, and UI stings. Also absent from clip: Settings menu, lockpick minigame, Slither Sap, Pickpocket Fairy, and actual loot pickup (`0/4,000` unchanged). |
| **A8** | `03:42–03:45.6` | **Pause Menu & Quit** | Blurred gameplay backdrop; teal Art Nouveau bordered modal (`RESUME / SETTINGS / RETURN TO THIEF'S DEN / QUIT TO DESKTOP`); bottom-left build stamp `1.5.148559  Novice  1025051536`. Cursor clicks `QUIT TO DESKTOP` (`03:44–03:45`). | Gameplay ambience ducks sharply; crisp menu open chime and click SFX on `QUIT TO DESKTOP`. |

### 1.3 Repository `.gitignore`, `git status`, `docs/`, and Tracked Asset Norms
- **`.gitignore` (`18` lines)**: Ignores `extracted/`, `game/assets/ue/`, `game/data/generated/`, `game/i18n/generated/`, `game/.godot/`, `*.import.bak`, `tools/**/bin/`, `tools/**/obj/`, `tools/bin/`, `*.usmap`, `__pycache__/`, `tools/ue4ss/cache/`, `tools/ue4ss/output/`, and `build/`. `docs/` is **not** ignored and is fully tracked.
- **`git status -sb`**: `## main...origin/main` with `M game/src/missions/mission_controller.gd` (`65 insertions/deletions` — `52(+), 13(-)`), which `docs/HANDOFF_NEXT_SESSION.md:112` identifies as the uncommitted `TEMP --env-strip=0-8` debug hook.
- **`docs/` contents**: 6 top-level markdown docs (`ANDROID.md`, `ARCHITECTURE.md`, `FIDELITY_GAPS.md`, `HANDOFF_NEXT_SESSION.md`, `HANDOFF_OPENCODE.md`, `PERFORMANCE.md`) + 34 markdown wave reports under `docs/reports/*.md`.
- **Tracked image/media norms**: `git ls-files '*.png' '*.jpg' '*.jpeg' '*.webp' '*.svg'` returns **empty**, and `git log --all --name-only` shows **zero** image or media files have ever been committed to git. Existing QA captures (`vf_*.png`, `e2e_parity/*.png`) reside in gitignored `build/qa/` as `1280x720` PNGs ranging from `164 KB` to `1.4 MB`.
- **Existing cross-reference baseline**: `docs/HANDOFF_NEXT_SESSION.md` (lines 29–116), `docs/FIDELITY_GAPS.md` (lines 11–127), `docs/reports/visual-fidelity.md` (lines 88–115), `docs/reports/fidelity-mechanics-wave.md` (§5.3 S01–S16 parity table: 14 pass / 7 fail including `S03 map_table_look_at_card`, `S04 clipped_controls`, `S06a/b mission_lobby_fov_20`, `S11 equipped_tool!=zipwire`, `S14 guard_pips_and_offscreen_arcs`, `S15b circular_lockpick_minigame_ui`), and `docs/reports/audio-wwise.md` (5,018/5,018 Ogg clips decoded, 9 tags wired, 6 convolution-reverb IR PLUG entries unresolved).

---

## 2. Logic Chain

1. **Image Asset Hygiene Norm**: Because zero images are currently tracked in git and `ORIGINAL_REQUEST.md` R4 mandates committing extracted/annotated reference images under `docs/`, committing raw `3840x2160` PNGs (~5–10 MB each × ~50–60 files = 250–600 MB) would severely bloat the repository. Downscaling extracted frames to **`1920x1080` JPEG (quality `90`, `~150–450 KB` per file)** preserves crisp readability for small UI text (e.g., `1.5.148559`, `94/500`, `[F] PICK POCKET`) while keeping a 25-keyframe clean+annotated set (50 images) under `~15–20 MiB` total.
2. **Comparison Structure**: The official clip exercises **4 distinct parity axes** simultaneously (Visual/Shaders/Lighting, Audio/VO/Absence-of-Music, HUD/UI states, and Gameplay/Interaction timings), and `docs/reports/fidelity-mechanics-wave.md` §5.3 already tracks S01–S16 parity shots. A 1:1 comparison matrix tied to segment IDs (`A1–A8`) and keyframe IDs (`KF01–KF26`) ensures future Godot recordings can be scored deterministically item-by-item against exact UE5 timestamps.
3. **Annotation Style**: Since `1920x1080` images will be viewed alongside Markdown tables, placing verbose paragraphs on the image itself obscures gameplay detail. Using **numbered circular badges (`1, 2, 3...`) + thin leader arrows + compact short-label callout tags** color-coded by domain (Visual/Lighting vs HUD/UI vs Gameplay/Audio) and linked to a numbered legend table in Markdown keeps both the image and the cross-reference clean and machine-auditable.
4. **Complexity & Strategy**: Producing an exhaustive second-by-second breakdown of a `225.64s` multi-scene clip, extracting and validating ~26 clean frames, scripting deterministic annotated overlays, and cross-referencing 10+ subsystem docs (`FIDELITY_GAPS.md`, `HANDOFF_NEXT_SESSION.md`, `visual-fidelity.md`, `audio-wwise.md`, `vfx-catalogue.md`, `gameplay-constants.md`, etc.) in a single monolithic Worker pass risks context saturation, skipped audio details, or drifted image-to-text paths. Splitting into **3 focused milestones** (Extraction & Timeline -> Annotation & Cross-Referenced Authoring -> Independent Spot-Check QA) directly enforces every Acceptance Criterion.

---

## 3. Recommended Design (Deliverables for Tasks 2–4)

### 3.1 `docs/` Directory Layout & Output Hygiene Rules
- **Directory structure** (all tracked in git under `docs/`):
  ```text
  docs/
  ├── reports/
  │   └── official-baseline-clip-1795033698901.md   # Main timestamped breakdown, checklists, legends & cross-refs
  └── reference/
      └── clip_1795033698901/
          ├── clean/                                # KF01..KF26 clean 1920x1080 JPGs
          │   ├── KF01_00m00s_startscreen.jpg
          │   └── ...
          └── annotated/                            # 1:1 matching annotated 1920x1080 JPGs
              ├── KF01_00m00s_startscreen.jpg
              └── ...
  ```
- **Hygiene rules for all Workers**:
  1. **Strict path fence**: Write ONLY under `docs/reports/official-baseline-clip-1795033698901.md` and `docs/reference/clip_1795033698901/`.
  2. **Preserve existing repo state**: Do NOT touch `game/`, `tools/`, `build/`, `extracted/`, `game/.godot/`, `game/data/generated/`, and do NOT revert or stage the existing uncommitted `game/src/missions/mission_controller.gd` diff.
  3. **Image format & budget**: `1920x1080` `.jpg` (quality 90, `yuvj420p` / RGB) for all frames (`150–450 KB` typical; hard cap `< 750 KB` per image; total `docs/reference/clip_1795033698901/` <= `25 MiB`). No raw 4K PNGs, no `.mp4`/`.wav`/`.mp3` files committed under `docs/`.
  4. **Zero leftover temp files**: Stage video/audio splits and intermediate PNGs only inside `mktemp -d /tmp/tat2_XXXXX` and `rm -rf` before completion.

### 3.2 Repeatable 1:1 Comparison Framework & Checklist
Every future TAT-2 Godot port recording compared against this baseline must be evaluated across **4 standardized tables** per scene/segment (`A1–A8`), scored as `PASS` | `DELTA` | `MISSING` | `HARD_LIMIT`:

1. **Visual & Rendering Parity (`V1–V7`)**:
   - `V1` Geometry & Set Dressing (architecture, props, decals, silhouettes)
   - `V2` Lighting & Exposure (key/fill balance, shadow crispness, bloom intensity)
   - `V3` Sky, Moon, Fog & Weather (sky dome/tint, moon angular size/phase, rain streaks, wet puddle SSR)
   - `V4` Materials & Shaders (`tat_glass`, `tat_hdr_emissive`, `tat_landscape`, PBR roughness/metallic)
   - `V5` VFX & Outlines (Escape Portal green/purple shimmer, Smoke Bomb volume, Vistara Diamond scan/highlight, crystal ward barrier, sweeping security beam)
   - `V6` Camera, Framing & 1P Viewmodel (FOV, 1P hands/tools pose, vault/takedown/crank animations)
   - `V7` Character/NPC Models & Animations (guard lantern/truncheon, patrol/alert/KO poses)
2. **Audio Parity (`AU1–AU6`)**:
   - `AU1` Environmental Ambience (rain hiss, rooftop wind, interior room tone)
   - `AU2` Player Foley & Movement (wood vs metal grate vs wet stone vs carpet footsteps, cloth, vault/land)
   - `AU3` Tool & Interactable SFX (Wardrobe latch, Ledger rustle, Gramophone 1920s jazz + crackle, Telescope whoosh, Car horn, ZipWire launch/zip/crank, Smoke Bomb hiss, Diamond chime, Door swing)
   - `AU4` Guard & Player VO (ThiefNisha lines, guard detection/search barks, pain/KO grunts)
   - `AU5` UI Audio (menu hover/click, countdown ticks, pickpocket/key chime, pause ducking)
   - `AU6` Music / Explicit Absence check (verify *no* continuous BGM in Den pre-gramophone, Loading, or Guildhall stealth)
3. **HUD & UI Parity (`UI1–UI5`)**:
   - `UI1` Persistent HUD Layout (Health bar top-left, Loot `£ 0` + Objective, Compass top-center, Player Card top-right, Hotbar + Key + `[TAB]/[MMB]` bottom-left, Light Gem bottom-center, Tool Prompts bottom-right)
   - `UI2` Dynamic HUD Indicators (Light Gem luminance response, radial red threat arcs, sound-ripple rings, status debuff rings above Light Gem, contextual `[F]`/`[LMB]`/`[RMB]` prompts)
   - `UI3` Hub Menus (Wardrobe tabs/slots/locks, Ledger Journal/XP/Black Market, Map Table floating card + modal)
   - `UI4` Pre-Mission & Transition UI (Mission Prep layout + 6s countdown, Loading screen art/spinner, Briefing parchment note)
   - `UI5` Pause Menu & Build Metadata (teal Art Nouveau border, 4 buttons, bottom-left build/difficulty/seed footer)
4. **Gameplay & Timing Metrics (`G1–G5`)**:
   - `G1` Interaction & Transition Timings (e.g., 6s Mission Prep countdown cadence, ZipWire fire-to-latch & crank hoist rate, Smoke Bomb expansion/linger, Door open speed)
   - `G2` Detection & Stealth Feedback (shadow vs lit Light Gem response, threat arc ramp, guard bark escalation)
   - `G3` Traversal & Physics (catwalk vault/drop, fall damage threshold, ZipWire grapple points, railing vault)
   - `G4` AI & Interactable Mechanics (car horn distraction, pickpocket vs `[HOLD] TAKEDOWN` dual prompt, key acquisition, sweeping security beam)
   - `G5` Cross-Reference Status against `docs/FIDELITY_GAPS.md` & `docs/HANDOFF_NEXT_SESSION.md` (explicitly tagging `Hard Limit` items such as Niagara VectorVM VFX and Blueprint logic graphs).

### 3.3 Annotation Style Specification
Generate `annotated/KFxx_*.jpg` deterministically (e.g. via Python `Pillow`/`cairosvg` or ImageMagick `magick` script) from `clean/KFxx_*.jpg` with consistent styling:
- **Color-coded numbered circles** (`28px` diameter, bold white sans-serif numeral `1, 2, 3...`, `2px` dark outer stroke):
  - **Amber `#FFB300`**: Visual / Lighting / Material / Shader / VFX (`V*`)
  - **Cyan `#00E5FF`**: HUD / UI / Prompts (`UI*`)
  - **Magenta `#FF4081`**: Gameplay Interaction / AI / Audio-linked Cue (`G*` / `AU*`)
- **Leader lines & targets**: `2.5px` solid colored line with `1px` black casing for legibility over dark or bright regions, terminating in an arrowhead or `6px` dot on the target feature, plus an optional dashed callout box (`rgba(14, 16, 22, 0.78)`) for bounding regions (e.g., HUD clusters or portal outlines).
- **Compact short tag next to badge** (`[1] Neon HDR Arch`, `[2] Light Gem`, etc., max 3–4 words) placed in uncluttered image margins or dark areas — full explanations live in the Markdown **Numeric Legend Table** under each keyframe (`| # | Category | Label | Observed UE5 Detail | TAT-2 Subsystem / Gap Ref |`), never paragraphs inside the image.

### 3.4 Complexity Assessment & Worker Strategy
- **Complexity**: **High (multi-modal, artifact-heavy, cross-doc synthesis)** — 225.64s continuous 4K clip with 8 distinct scenes, ~26 keyframe pairs (~52 images), continuous visual + audio logging, and cross-referencing against `HANDOFF_NEXT_SESSION.md` + `FIDELITY_GAPS.md` + wave reports (`visual-fidelity.md`, `visual-polish.md`, `fidelity-mechanics-wave.md`, `audio-wwise.md`, `vfx-catalogue.md`, `gameplay-constants.md`, `doors-attachparent.md`, `sky-moon.md`, `lighting-intensity.md`, `player-1p.md`).
- **Recommendation**: **3-Milestone Sequential Pipeline** (not a single-shot monolithic Worker):
  1. **Milestone 1 — Canonical Timeline & Clean Keyframe Extraction (1 Worker / Analyst)**:
     - Produce exact second-accurate segment boundaries (`00:00`–`03:45.64`), extract 24–28 clean `1920x1080` JPGs (`KF01..KF26`) into `docs/reference/clip_1795033698901/clean/`, log exact visual & audio observations per timestamp, clean up `/tmp`.
  2. **Milestone 2 — Deterministic Annotation & Cross-Referenced Baseline Report (1 Worker)**:
     - Inspect every clean keyframe to record exact callout pixel coordinates, run deterministic `magick`/`python3` annotation script to generate `docs/reference/clip_1795033698901/annotated/KF*.jpg` (cleaning up script/temp files afterward), and write `docs/reports/official-baseline-clip-1795033698901.md` containing: (a) continuous timestamped visual+audio log, (b) embedded clean vs annotated references + numeric legends, (c) TAT-2 subsystem & hard-limit cross-references grounded in `docs/`, and (d) the 4-pillar 1:1 comparison checklist.
  3. **Milestone 3 — Independent QA & Output Hygiene Verification (1 Fresh Reviewer/QA Agent)**:
     - Independently spot-check timestamps, audio cues (including absences), callout accuracy, and cross-reference citations against `/home/john/Videos/clip_1,795,033,698,901.mp4` and `docs/`. Verify all image links resolve and are non-empty, total media size stays within budget, `git status` shows new files ONLY under `docs/` (leaving `game/src/missions/mission_controller.gd` untouched), and `/tmp` has zero leftover survey folders.

---

## 4. Caveats
- **Audio exact cue timings**: This survey reviewed the full `audio_full.mp3` and all 4 video+audio segments (`0–225.6s`) plus `silencedetect`, which established every major audio category, VO line, and absence-of-BGM pattern; Milestone 1 should log frame-accurate sub-second timestamps for every individual UI tick and footstep transition.
- **Uninspected individual wave reports**: Only `HANDOFF_NEXT_SESSION.md`, `FIDELITY_GAPS.md`, `ARCHITECTURE.md`, `visual-fidelity.md`, `fidelity-mechanics-wave.md`, and `audio-wwise.md` were read directly in this survey; Milestone 2 should also read `vfx-catalogue.md`, `gameplay-constants.md`, `player-1p.md`, `tool-mechanics.md`, and `hud-hotbar-icons.md` before finalizing subsystem cross-reference citations.
- **Uncommitted file in working tree**: `game/src/missions/mission_controller.gd` already has local uncommitted modifications (`--env-strip=0-8` debug hook); workers must use `git add docs/...` (never `git add -A`) and avoid modifying `game/`.

---

## 5. Conclusion
`/home/john/Videos/clip_1,795,033,698,901.mp4` is a complete 8-act (`00:00`–`03:45.64`) official UE5 reference spanning Startscreen, Thieves' Den (all major hub stations + Gramophone music + Telescope cheese-moon easter egg), Mission Prep, Loading/Briefing, Constables' Guildhall infiltration (ZipWire/Crank, Smoke Bomb, Vistara Diamond, car horn, pickpocket/takedown, purple crystal ward barrier, sweeping security beam), and Pause Menu. Because `docs/` currently contains zero tracked images, adopting `1920x1080` JPEG (`clean/` + `annotated/`) under `docs/reference/clip_1795033698901/`, a color-coded numeric callout style, a 4-pillar 1:1 comparison matrix, and a 3-milestone Worker pipeline directly satisfies Requirements R1–R4 and all Acceptance Criteria cleanly.

---

## 6. Verification Method
- **Source clip metadata**: `ffprobe -v quiet -print_format json -show_format -show_streams "/home/john/Videos/clip_1,795,033,698,901.mp4"` (confirms `3840x2160`, `225.642333s`, 2 streams).
- **Repo & git hygiene check**:
  ```bash
  git -C /home/john/Projects/TAT-2 status -sb
  git -C /home/john/Projects/TAT-2 ls-files '*.png' '*.jpg' '*.jpeg' '*.webp' '*.svg'
  ```
- **Cleanup check**: `ls -d /tmp/tat2_survey_* 2>/dev/null || echo CLEANED` (verified `CLEANED`).
- **Invalidation condition**: Any new commits on `main` touching `docs/` or `game/`, or replacement of `/home/john/Videos/clip_1,795,033,698,901.mp4`, invalidates the repo baseline / timeline snapshot.
