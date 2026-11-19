# Survey Handoff Report — Official Gameplay Clip & Tooling/Docs Baseline

**Core Summary:** `/home/john/Videos/clip_1,795,033,698,901.mp4` is a `225.64 s` (`03:45.64`) 4K (`3840x2160`, ~29.67 fps, H.264 + AAC 48 kHz stereo) capture of *Thick As Thieves* spanning Startscreen, Thieves' Den (Wardrobe, Journal/Black Market, Map Table), Mission Preparation, Loading, and a Constables' Guildhall Solo Novice infiltration ending at the Pause Menu. `/usr/bin/python3` (`Pillow 13.0.0`, `matplotlib 3.11.1`, `numpy 2.5.4`), `ffmpeg`/`ffprobe`, and `ImageMagick 7.1.2-35` are installed (avoiding the default `linuxbrew` `python3` in `$PATH` which lacks `PIL`), and a 2-milestone decomposition is recommended to avoid single-worker context dilution across 14+ timeline segments, ~24–28 keyframe pairs, and `docs/reports/*.md` cross-referencing.

---

## 1. Observation

### 1.1 Video & Audio Stream Metadata (`ffprobe` / `ffmpeg`)
Executed `ffprobe -v quiet -print_format json -show_format -show_streams "/home/john/Videos/clip_1,795,033,698,901.mp4"`:
- **Format**: `mov,mp4,m4a,3gp,3g2,mj2` (`isom`), size `265,161,125` bytes (`252.9 MiB`), duration `225.642333 s` (`03:45.64`), overall bitrate `9,401,112 bps` (`9.40 Mbps`), `encoder: Lavf62.12.102`.
- **Video stream (`index 0`)**: `h264` (`High`, `avc1`, level `52`), `3840x2160` (`16:9`, `1:1` SAR), `yuvj420p` (`color_range: pc`, `bt709`), `r_frame_rate: 179/6` (`29.833 fps`), `avg_frame_rate: 2110119665/71113994` (`29.672 fps`), `6,696` frames, `duration: 225.529000 s`, `bit_rate: 9,231,599 bps`.
- **Audio stream (`index 1`)**: `aac` (`LC`, `mp4a`), `48000 Hz`, `2` channels (`stereo`, `fltp`), `start_time: 0.277000 s`, `duration: 225.365333 s`, `10,564` frames, `bit_rate: 161,467 bps`.

### 1.2 Audio Loudness, Silence & Energy Profile
Executed `ffmpeg -hide_banner -nostats -i "/home/john/Videos/clip_1,795,033,698,901.mp4" -vn -af "ebur128" -f null -`:
- **Integrated loudness (`I`)**: `-43.9 LUFS` (Threshold `-54.7 LUFS`)
- **Loudness range (`LRA`)**: `16.7 LU` (`LRA low: -55.8 LUFS`, `LRA high: -39.0 LUFS`, Threshold `-65.0 LUFS`)

Executed `silencedetect=noise=-40dB:d=0.5` and 2-second RMS profiling on extracted mono 16 kHz audio (`audio_mono.wav`):
- **Quiet / intermittent menu & Den sections (`00:00–01:10`)**: `rms` ranges from `-74.4 dBFS` to `-43.5 dBFS`; 36 of 48 silence intervals occur between `2.07 s` and `70.96 s` (notable long gaps: `28.04–34.19 s` [6.16 s], `55.50–59.99 s` [4.49 s], `64.05–69.78 s` [5.73 s]).
- **Active Guildhall gameplay (`01:10–03:09`)**: Continuous audio between `-53.4 dBFS` and `-40.3 dBFS` RMS (peaks up to `-22.7 dBFS` at `02:28` and `-23.1 dBFS` at `02:02`), with only 4 brief `0.5–0.8 s` dips below `-40 dB` (`74.2 s`, `75.6 s`, `76.9 s`, `81.0 s`, `94.5 s`, `142.3 s`, `157.3 s`, `160.1 s`).
- **Takedown & post-takedown (`03:06–03:40`)**: Brief quiet/low-RMS pause (`186.5–197.1 s`, including a `6.83 s` interval `< -40 dB` at `190.29–197.12 s` while crouching behind the fireplace guard), followed by takedown/barrier/pursuit peaks (`-42.7 dBFS` RMS / `-23.8 dBFS` peak around `03:20`, `-43.5 dBFS` RMS around `03:38`).
- **Pause Menu (`03:40–03:45.64`)**: Drops to `-55.6` / `-57.2 dBFS` then `-120 dBFS` after `03:44`.

### 1.3 Scene-Change Detection (`gt(scene,0.15)`)
Executed `ffmpeg -hide_banner -i "/home/john/Videos/clip_1,795,033,698,901.mp4" -vf "select='gt(scene,0.15)',showinfo" -f null -`:
- Detected 44 scene-change timestamps (seconds): `2.15`, `2.60`, `6.00`, `6.57`, `18.24`, `18.27`, `18.30`, `18.54`, `18.90`, `20.23`, `25.44`, `33.47`, `33.50`, `34.07`, `38.41`, `38.92`, `39.01`, `42.64`, `51.94`, `51.97`, `52.74`, `54.78`, `54.87`, `56.08`, `56.38`, `64.80`, `69.44`, `70.81`, `149.89`, `166.52`, `173.53`, `175.65`, `197.60`, `203.17`, `214.40`, `217.67`, `218.24`, `218.42`, `218.56`, `218.63`, `218.73`, `218.83`, `218.95`, `221.89`.

### 1.4 Full Timeline Map (`00:00` to `03:45.64`)
Observed directly via `read_file` on 113 sampled frames (`0.5 fps` across 6 contact sheets), 21 targeted transition frames, and 4 segmented WAV audio clips (`0–60 s`, `60–120 s`, `120–180 s`, `180–226 s`):

| Segment | Time Range | Location / UI State | Visual Observations (Environment, Lighting, HUD/UI, Interactions) | Audio Observations (Directly Heard) |
|---|---|---|---|---|
| **S1** | `00:00–00:02.3` | **Startscreen / Main Menu** | Wet cobblestone street at night with rain streaks, purple/pink neon *"MacNeish's"* & *"Traveller"* signs on storefront, lamppost glow; right-side *"THICK AS THIEVES"* title logo + menu (`PLAY`, `SETTINGS`, `CREDITS`, `QUIT`), mouse cursor over `PLAY`. | Steady night rain ambience + low muted street/music undertone, menu click at transition (~`00:02`). |
| **S2** | `00:02.3–00:06.2` | **Thieves' Den (Initial Entry)** | Attic/hideout interior with wooden rafters, warm desk lamps, moonlight through arched windows, teal/green atmospheric glow on right. Top-right shows player tag *"Johnny Cipher"* + ThiefNisha portrait. Walks toward wardrobe/armoire. | Soft wood footsteps, quiet room tone, UI open swoosh/chime around `00:06`. |
| **S3** | `00:06.2–00:18.4` | **Wardrobe UI** | Full-screen dark-slate Wardrobe overlay: tabs `WARDROBE`, character switcher `[Q] The Spider` / `[E] The Chameleon`, `Edit Loadout` slots `1–4` (`Zipwire`, `Smoke Bomb`, empty, `Vistara Diamond`), 3D character turntable center, `Head`/`Body`/`Calling Card` right slots, grid of hats/masks/outfits (e.g., `Bowler Hat`, `Bob Hair Style with Eyepatch [LOCKED]`, `Classic` outfit), bottom-left item tooltip (`Vistara Diamond`: *"A mysterious gem that allows the holder to see traps and treasures"*), `BACK [ESC]`. | Distinct metallic/mechanical UI hover ticks and selection clacks as player browses loadout slots, cosmetics, and Vistara Diamond; UI close sound around `00:18`. |
| **S4** | `00:18.4–00:25.6` | **Thieves' Den Exploration** | Looks around Den (`[F] EXIT` prompt on double doors beneath bright full moon through upper arched window at `~00:21`), walks past telescope and framed `"WANTED"` poster (`~00:25`), inspecting Den lighting/props. | Footsteps on wooden floorboards, subtle cloth/gear rustle, deep resonant UI open thump/chime at `~00:25`. |
| **S5** | `00:25.6–00:38.6` | **Journal & Black Market UI** | `JOURNAL` / `BLACK MARKET [E]` tabbed screen. At `~00:27`: `Level 4` (`94/500`), `Johnny Cipher`, `Completed Contract #2: Into the Lion's Den`, `Active Contract #3: In the Eye of the Beholder` (story text referencing Vistara Diamond, Mary Elway, Hugh Montgomery). Switches via `[E]` (`~00:29–00:34`) to `BLACK MARKET`: `YOUR TOTAL ASSETS: 26,275`, 3-column store (`SPIDER COSMETICS`, `CHAMELEON COSMETICS`, `TOOLS`, `GUILD PERKS`), previews `Zipwire` (`PURCHASED`), `Thief Mask` (`LOCKED`), `Pickpocket Fairy` (`LOCKED`), then returns to `JOURNAL` (`~00:35–00:38`) before closing. | Crisp parchment/tab-switch clicks, metallic purchase/hover ticks, low ambient drone; near-silence (`~6.16 s`) while reading Black Market before closing at `~00:38–00:39`. |
| **S6** | `00:38.6–00:52.1` | **Thieves' Den Props & Gramophone** | Walks past roaring fireplace (`~00:39`), approaches table (`[F] CHANGE DECORATION` on chalice/goblet at `~00:41`, cycles/views green/red jewel & chest `[F] CHANGE DECORATION` at `~00:49`), interacts with brass-horn gramophone (`[F] TURN ON` at `~00:47`), then walks to illuminated Map Table (`~00:51`). | Wooden footsteps, bright brass/mechanical gramophone wind-up & brief ragtime/vintage record burst (~`00:44–00:48` in `aud_0_60.wav`), prop swap clink, footsteps to table. |
| **S7** | `00:52.1–00:55.0` | **Map Table Interaction** | Overhead/angled view of Kilcairn map with 3D building tokens (`CONSTABLES' GUILDHALL`, `KILCAIRN` label), top-left info box (`Difficulty: Novice`, `Mode: Solo`, `[F] Prepare for Mission`), `[F] ENTER` prompt, compass strip (`N`) at top. | Map table selection clicks and subtle UI transitions. |
| **S8** | `00:55.0–01:04.9` | **Mission Preparation UI** | `MISSION PREPARATION` -> countdown `MISSION STARTING IN 6.. 4.. 2..` (`Mode: Solo`, `Difficulty: Novice`). Left panel: Guildhall preview image, `Mission: Cleanout Heist` (`Time Limit: 15 minutes`), `Contract Inactive`. Right side: ThiefNisha 3D character stand-in lit by blue/gold spotlights against night skyline; `Johnny Cipher READY`; bottom-right `[F] READY` / `UNREADY`, `[ESC] BACK`. | Subtle UI ready chime, then `~4.5 s` silence/low room hum during countdown before load transition. |
| **S9** | `01:04.9–01:10.9` | **Loading Screen** | Stylized night cityscape illustration with glowing full moon, silhouettes of rooftops/spires, centered `LOADING...` with spinning ring, bottom `THICK AS THIEVES` logo. | Quiet transition (`~5.7 s` silence interval `64.05–69.78 s`), then rain ambience fades in at `~01:09–01:10` just as level spawns. |
| **S10** | `01:10.9–01:20.0` | **Guildhall Spawn — Safe-Room Overlook & Catwalk** | Spawns in elevated attic/warehouse overlook looking out arched industrial window at misty street & spires; turns to reveal safe-room interior (crate/table with lit lantern, wooden barricades, barred gate); exits onto metal grate catwalk and descends stairs. **HUD active**: Top-left ornate health bar, `£ 0`, `Mission: Steal 4,000 in loot value [0/4,000]`; top-center compass; top-right `Johnny Cipher` + portrait `4`; bottom-left hotbar `[1]` Zipwire, `[2]` Smoke Bomb, `[4]` Vistara Diamond, `[TAB] MAP`, `[RMB] [HOLD] PING MENU`; bottom-center blue-gold Stealth/Light Gem flanked by red directional arcs when landing/making noise (`~01:19`). | ThiefNisha spoken intro line (~`01:11–01:13`): *"Let the thieving begin."*; steady rain/wind ambience; footsteps shifting from wood to metallic grate stairs. |
| **S11** | `01:20.0–01:39.0` | **Street / Alley Approach to Guildhall Gate** | Emerges into rainy cobbled alley past `"ARRON'S DEMOLITION"` brick wall sign (`~01:21`, green-lit doorway), descends alley stairs, traverses wet reflective cobblestones past green wooden hoarding, brick walls, iron railings, parked black carriage (`~01:35–01:37`), and reaches the wrought-iron Guildhall front fence/gate (`~01:39`) where a patrolling constable guard is visible walking inside the lit courtyard. Red noise arcs flare around stealth gem during sprinting/jumping (`~01:29`, `01:33`). | Steady outdoor rain + puddles/cobblestone footsteps (walking & faster sprint cadences); distant guard footsteps/muffled ambience. |
| **S12** | `01:39.0–02:11.0` | **Zipwire Ascent & Roof Infiltration** | Equips Zipwire (`[1]`: 1P mechanical crank launcher in right hand, HUD bottom-right `LAUNCH [LMB]` / `[HOLD] CRANK [RMB]`), climbs/checks rooftop edge by chest (`~01:45`), fires zipwire anchor (`~01:49–01:53`) up onto high brick facade/lamp (`~01:55–02:05`, `[HOLD] CRANK` reticle & cranking 1P arms animation), ascends over the Guildhall wall (`~02:07`), walks along upper stonework/roof overlooking courtyard and `CONSTABLES' GUILDHALL` wrought-iron archway (`~02:11–02:15`). | Distinct pneumatic/spring **zipwire launch** + metallic cable zip (~`01:48–01:55` in `aud_60_120.wav`), rhythmic **ratchet cranking** sounds, **guard alert whistle/horn** + guard bark (*"Huh? ... Pretty like..." / "I know someone's here!" / "I will find you!"* around `01:43–02:00`), rain & footsteps on brick/slate. |
| **S13** | `02:11.0–02:32.0` | **Courtyard Descent, Smoke Bomb & Vistara Diamond** | Traverses upper balcony/railing (`~02:15–02:19`), drops onto wet courtyard flagstones past crates (`~02:21–02:23`) and stone lion statue (`~02:25`), equips Smoke Bomb (`[2]`, bottom-right `THROW`), throws smoke canister onto steps (`~02:27–02:29` producing billowing white/grey volumetric smoke cloud with red stealth-gem arcs), then equips Vistara Diamond (`[4]`, glowing faceted cyan crystal held in 1P hand at `~02:31`). | Guard chatter/barks (*"Who's there?"*, *"Captain said to look around..."*, *"Just a shadow..."*, *"Show yourself!"*), metallic clink + **hissing smoke bomb detonation** (~`02:28`), crystalline shimmer/equip cue for Vistara Diamond. |
| **S14** | `02:32.0–03:05.0` | **Side Wing, Scaffolding & Locked Double Door** | Fires/re-equips Zipwire (`~02:33–02:35`), moves past vertical illuminated `"MACLEOD"` sign (`~02:41`, `~02:49`), walks along grass/cobble garden terrace spotting patrolling guard ahead (`~02:53`), enters arched side portico (`~02:55–02:57`), approaches locked blue double doors (`~02:59–03:01`: `[F] OPEN`, `[F] [HOLD] LOCK` / lockpick prompt), checks nearby scaffolding (`~03:03`), and enters interior wing (`~03:05`). | Guard dialogue/mutterings, footsteps transitioning from wet grass/cobbles to stone portico, door/lock interaction clicks and creaking door open (`~03:01–03:04`). |
| **S15** | `03:05.0–03:22.0` | **Fireplace Parlor — Pickpocket Key & Guard Takedown** | Enters warm firelit parlor (wood parquet floor, chandelier, leather armchairs, roaring hearth). Stalks patrolling guard from behind (`~03:07–03:17`), sees `[F] PICK POCKET` and `[F] [HOLD] TAKEDOWN` prompts (`~03:15–03:17`), pickpockets **`Guildhall Key`** (appears above hotbar bottom-left at `~03:19`), then performs **`[HOLD] TAKEDOWN`** (`~03:19–03:22`, camera tilts downward over guard body with yellow exclamation mark briefly). | Quiet crouch footsteps (~`6.8 s` low-volume stealth stretch `190.3–197.1 s`), key jingle/pickup chime, ThiefNisha takedown lines (~`03:18–03:22` in `aud_180_226.wav`): *"Let's get this done."* -> heavy melee thud + guard groan -> *"And stay down."* |
| **S16** | `03:22.0–03:41.5` | **Foyer Tripwire Laser, Arcane Barrier & Pursuit** | Exits parlor into checkered marble foyer (`~03:27`: statue display case on left, horizontal glowing laser/tripwire beam across corridor from wall emitter, blue security diamond icon above doorway). Crosses beam (`~03:29–03:35`), triggering a **bright purple crystalline arcane barrier** sealing the corridor + **green glowing thorny/arcane lock effect** over side door (`~03:35`, `t_214.5.jpg`), while ear/sound icon and sleeping/alert status badges appear above the stealth gem (`~03:29–03:35`). Runs left up staircase (`~03:37–03:41`) with Zipwire in hand (`[HOLD] CRANK`) as red directional alert arcs flare around the stealth gem. | Heavy footsteps on marble, **electronic/arcane tripwire trigger + crystalline barrier shatter/hum** (~`03:29–03:35` in `aud_180_226.wav`), alarm/whistle audio, sprinting footsteps up stairs. |
| **S17** | `03:41.5–03:45.64` | **Pause Menu** | Darkened translucent Art-Nouveau bordered pause box centered (`RESUME`, `SETTINGS`, `RETURN TO THIEF'S DEN`, `QUIT TO DESKTOP`), version/mode footer bottom-left (`1.5.146159  Novice  1012591506`), cursor moves onto `QUIT TO DESKTOP` (`~03:45`). | Gameplay/rain audio abruptly muted/attenuated (`-55.6 dBFS` -> `-120 dBFS`), soft UI hover tick. |

### 1.5 Available CLI/Python Media & Annotation Tooling
Checked via `which`, `/usr/bin/python3`, `/home/linuxbrew/.linuxbrew/bin/python3`, `magick -version`, and `fc-list`:
- **CLI binaries**: `/usr/bin/ffmpeg`, `/usr/bin/ffprobe`, `/usr/bin/magick` & `/usr/bin/convert` (`ImageMagick 7.1.2-35 Q16-HDRI`, delegates include `cairo`, `fontconfig`, `freetype`, `pangocairo`, `rsvg`, `png`, `jpeg`, `webp`).
- **Python trap**: Default `python3` in `$PATH` resolves to `/home/linuxbrew/.linuxbrew/bin/python3`, which reports `PIL MISSING`, `matplotlib MISSING`, `cv2 MISSING`, `numpy MISSING`.
- **Working Python**: `/usr/bin/python3` (`Python 3.15.2`) has `PIL 13.0.0` (Pillow), `matplotlib 3.11.1`, `numpy 2.5.4`, `cairo` installed (`cv2` missing).
- **Fonts**: System fonts include `Noto Sans` (`/usr/share/fonts/google-noto/NotoSans-Regular.ttf`), `Inter Display`, `Source Code Pro`, `FreeSansBold`, `Liberation Sans`, `Montserrat`, `Red Hat Display`.
- **Missing**: `rsvg-convert`, `inkscape`, `gimp`, `cv2` (none needed given `ffmpeg` + `/usr/bin/python3` Pillow + `ImageMagick`).

### 1.6 `docs/` Layout, `git status`, and `.gitignore`
- **`docs/` files**: 6 top-level markdown files (`ANDROID.md`, `ARCHITECTURE.md`, `FIDELITY_GAPS.md`, `HANDOFF_NEXT_SESSION.md`, `HANDOFF_OPENCODE.md`, `PERFORMANCE.md`) and 33 reports under `docs/reports/*.md` (including `visual-fidelity.md`, `visual-polish.md`, `fidelity-mechanics-wave.md`, `audio-wwise.md`, `gameplay-constants.md`, `hud-hotbar-icons.md`, `tool-mechanics.md`, `combat-health.md`, `lighting-intensity.md`, `sky-moon.md`, `sky-rain.md`, `vfx-catalogue.md`, `player-1p.md`, `guard-animations.md`, `doors-attachparent.md`, `swinging-doors.md`, `interactables-implementation.md`). No image files currently exist under `docs/`.
- **`git status`**: Branch `main`, 1 pre-existing unstaged modification: `modified: game/src/missions/mission_controller.gd` (the uncommitted `--env-strip=0-8` debug hook explicitly documented in `docs/HANDOFF_NEXT_SESSION.md:21,112,119`).
- **`.gitignore`**: Ignores `extracted/`, `game/assets/ue/`, `game/data/generated/`, `game/i18n/generated/`, `game/.godot/`, `*.import.bak`, `tools/**/bin/`, `tools/**/obj/`, `tools/bin/`, `*.usmap`, `__pycache__/`, `tools/ue4ss/cache/`, `tools/ue4ss/output/`, `build/`. Everything under `docs/` is tracked in git.

### 1.7 Cleanup Verification
Temporary workspace `/tmp/tat2_survey_yKkYlZ` was deleted (`rm -rf /tmp/tat2_survey_yKkYlZ`). (Note: an unrelated directory `/tmp/tat2_survey_4Rf8cV` created by a parallel process was left untouched.)

---

## 2. Logic Chain

1. **Why `/usr/bin/python3` + `ffmpeg` is the required pipeline**: Observation 1.5 shows default `python3` in `$PATH` (`linuxbrew`) fails to import `PIL`/`numpy`, whereas `/usr/bin/python3` has `Pillow 13.0.0`, `matplotlib 3.11.1`, and `numpy 2.5.4`, paired with `ffmpeg` and `ImageMagick 7.1.2-35`. Therefore, all extraction/annotation scripts must explicitly invoke `/usr/bin/python3` (never bare `python3`).
2. **Why `03:45.64` 4K footage requires milestone decomposition rather than a single monolithic E->W->R pass**: Observation 1.4 reveals 17 distinct visual/UI/gameplay phases (Startscreen, Den, Wardrobe, Journal/Black Market, Props/Gramophone, Map Table, Mission Prep, Loading, Safe-Room/Catwalk, Alley/Street, Zipwire Ascent, Smoke/Vistara Diamond, Portico/Locked Door, Fireplace Pickpocket/Takedown, Tripwire Laser/Arcane Barrier/Pursuit, Pause Menu) plus dense spoken dialogue, Wwise SFX, and subtle UI details (e.g., `Vistara Diamond`, `Guildhall Key`, `1.5.146159` footer, tripwire crystalline barrier vs. TAT-2 documented gaps). Observation 1.6 shows 33+ subsystem reports in `docs/reports/` to cross-reference against `HANDOFF_NEXT_SESSION.md` and `FIDELITY_GAPS.md`. Forcing a single Explorer->Worker->Reviewer cycle to simultaneously inspect every 1s window, author 25+ annotated images, cross-reference 15+ reports, and write an exhaustive breakdown risks context saturation, missed audio cues, or annotation/text mismatches.
3. **Why image format/resolution sizing matters for `docs/`**: Observation 1.1 shows native frames are `3840x2160`, and Observation 1.6 confirms `docs/` is git-tracked. Uncompressed 4K PNGs (~12–18 MB each x 50 images) would add ~600–900 MB to git history, whereas `1920x1080` high-quality JPEG (`q=92`, ~350–500 KB each) or `1920x1080` PNG (~2–3 MB) keeps total repo growth reasonable while preserving crisp UI text and HUD readability (especially when zoomed/cropped callouts are added where needed, e.g., Wardrobe/Journal/Black Market/HUD).

---

## 3. Caveats

- Exact single-frame timestamps (`±0.5 s`) for minor mid-segment actions (e.g., exact frame of smoke canister throw vs. detonation, exact frame of lockpick prompt vs. door open, exact word-for-word transcription of faint background guard barks at `02:35–02:55`) were surveyed at `0.5 fps` + 21 transition frames + 1-minute WAV segments and should be refined at `1–2 fps` / 5–10 s audio clips during Milestone 1 deep-dive investigation.
- Audio loudness is `-43.9 LUFS` integrated (`silencedetect` threshold `-40 dB` flagged soft ambient stretches like `190.3–197.1 s` as "silence" even though quiet crouch footsteps/ambience exist); Milestone 1 audio analysis should inspect waveform/normalized previews in `/tmp` so low-level ambience is never misreported as true silence.
- An unrelated `/tmp/tat2_survey_4Rf8cV` folder existed in `/tmp` during our final check; we did not inspect or remove it since it was not created by us.

---

## 4. Conclusion & Execution Strategy

### 4.1 Cycle Assessment: Recommend 2-Milestone Decomposition
Do **NOT** run as a single monolithic E->W->R pass. Execute in **2 Milestones**:

- **Milestone 1 — Deep-Dive Modality Analysis & Scripted Keyframe/Annotation Generation**
  - **Parallel Explorers (Read-Only)**:
    1. *Explorer A (Timeline 00:00–01:40 — Menus, Hub, Prep, Street)*: Inspect `0.5–1 s` slices & normalized audio segments in `/tmp` for `S1–S11` (exact timestamps, verbatim UI strings in Wardrobe/Journal/Black Market/Mission Prep, gramophone music/SFX, ThiefNisha intro line).
    2. *Explorer B (Timeline 01:40–03:45.64 — Guildhall Mechanics, AI, Combat, Traps)*: Inspect `0.5–1 s` slices & normalized audio segments in `/tmp` for `S12–S17` (zipwire launch/crank, guard barks/whistle, smoke bomb, Vistara Diamond, lockpick prompt, pickpocket `Guildhall Key`, takedown lines, tripwire laser -> purple crystalline barrier + green door barrier, pause menu footer).
    3. *Explorer C (TAT-2 Subsystem Cross-Reference Audit)*: Read `docs/FIDELITY_GAPS.md` and targeted `docs/reports/*.md` (`visual-fidelity.md`, `visual-polish.md`, `fidelity-mechanics-wave.md`, `audio-wwise.md`, `hud-hotbar-icons.md`, `tool-mechanics.md`, `combat-health.md`, `player-1p.md`, `guard-animations.md`, `doors-attachparent.md`, `vfx-catalogue.md`, `gameplay-constants.md`) to map every observed official feature to TAT-2 status (`1:1`, `partial`, `missing/unimplemented` — e.g., **Black Market / Journal UI**, **Vistara Diamond**, **Tripwire Laser + Purple Crystalline Barrier / Arcane Door Lock**, **Active Pickpocket/Takedown 1P animations**, **Gramophone/Decoration swap**, **Smoke VFX vs Niagara VM limit**).
  - **Worker 1 (Image Extraction & Annotation Script + Assets)**:
    - Run a deterministic `/usr/bin/python3` + `ffmpeg` script (temporary probe files in `/tmp` via `mktemp -d`, cleaned up afterward) to extract clean keyframes and programmatically render numbered callout boxes, leader lines, bounding boxes, and timestamp/segment header banners using `Pillow 13.0.0` + `/usr/share/fonts/google-noto/NotoSans-Regular.ttf` (or `FreeSansBold.ttf`).
    - Inspect generated annotated images via `read_file` to verify legibility and zero overlapping/misplaced callouts.

- **Milestone 2 — Breakdown Authoring, Comparison Framework & Independent Review**
  - **Worker 2 (Documentation Authoring)**:
    - Write the exhaustive timestamped breakdown document, subsystem cross-reference matrix, and 1:1 side-by-side Godot comparison protocol/checklist under `docs/`.
  - **Reviewer (Independent Verification)**:
    - Spot-check timestamps, verbatim UI text, audio quotes, annotated callout coordinates, and image file existence directly against `/home/john/Videos/clip_1,795,033,698,901.mp4` and `docs/HANDOFF_NEXT_SESSION.md`.
    - Verify `git status` shows ONLY additions under `docs/` (plus the pre-existing untouched `game/src/missions/mission_controller.gd`).

### 4.2 Concrete Target Paths, Naming & Keyframe Plan

- **Documentation & Asset Directory Layout**:
  - Main breakdown document: `docs/OFFICIAL_CLIP_BASELINE.md` (or `docs/reports/official-clip-baseline.md` + linked from `docs/OFFICIAL_CLIP_BASELINE.md`; recommend `docs/OFFICIAL_CLIP_BASELINE.md` as the primary baseline alongside `FIDELITY_GAPS.md` and `HANDOFF_NEXT_SESSION.md`, or `docs/reports/official-clip-baseline.md` if keeping top-level `docs/` minimal — **recommended**: `docs/reports/official-clip-baseline.md` + `docs/reports/official-clip-frames/` so all report-wave artifacts stay cleanly organized under `docs/reports/`).
  - Clean frames: `docs/reports/official-clip-frames/clean/kf_01_startscreen_0001.jpg` ... `kf_24_pause_0344.jpg`
  - Annotated frames: `docs/reports/official-clip-frames/annotated/kf_01_startscreen_0001_annotated.jpg` ... `kf_24_pause_0344_annotated.jpg`
  - Format & Resolution: `1920x1080` JPEG (`-q:v 2` / `quality=92`, ~300–500 KB/image; ~24 pairs = ~15–20 MB total git footprint, crisp 1080p UI legibility without bloating git with 4K PNGs). Use `1920x1080` PNG only if lossless pixel-UI crops are needed for small HUD elements, or include inset zoom crops inside the annotated JPEGs.

- **Recommended Keyframe Extraction Timestamps (~24 Keyframes Covering All 17 Segments)**:
  1. `00:01.0` (`1.0 s`) — `kf_01_startscreen_0001`: Title logo, menu buttons, MacNeish's neon, wet cobbles/rain.
  2. `00:04.5` (`4.5 s`) — `kf_02_den_entry_0004`: Thieves' Den interior rafters, desk lamp, Johnny Cipher badge.
  3. `00:08.5` (`8.5 s`) — `kf_03_wardrobe_loadout_0008`: Wardrobe UI (`The Spider`/`The Chameleon`, Loadout 1–4, Zipwire).
  4. `00:17.0` (`17.0 s`) — `kf_04_wardrobe_diamond_0017`: Wardrobe UI showing `Vistara Diamond` tooltip & full gear grid.
  5. `00:21.0` (`21.0 s`) — `kf_05_den_window_moon_0021`: Thieves' Den arched window, full moon, `[F] EXIT` doors.
  6. `00:27.0` (`27.0 s`) — `kf_06_journal_contracts_0027`: Journal UI (`Level 4 94/500`, Contracts #2 & #3).
  7. `00:31.0` (`31.0 s`) — `kf_07_black_market_0031`: Black Market UI (`26,275` assets, Cosmetics/Tools/Guild Perks).
  8. `00:47.0` (`47.0 s`) — `kf_08_den_gramophone_0047`: Den `[F] TURN ON` Gramophone & table/lighting.
  9. `00:54.5` (`54.5 s`) — `kf_09_den_map_table_0054`: Map Table (`CONSTABLES' GUILDHALL`, `KILCAIRN`, tokens, `[F] Prepare for Mission`).
  10. `01:01.0` (`61.0 s`) — `kf_10_mission_prep_0101`: Mission Preparation UI (`Cleanout Heist`, `15 minutes`, ThiefNisha 3D preview, countdown).
  11. `01:07.0` (`67.0 s`) — `kf_11_loading_screen_0107`: Loading screen cityscape, moon, spinner, logo.
  12. `01:13.0` (`73.0 s`) — `kf_12_guildhall_saferoom_0113`: Safe-room overlook interior (lantern, bars, HUD layout).
  13. `01:21.0` (`81.0 s`) — `kf_13_alley_demolition_0121`: `"ARRON'S DEMOLITION"` brick alley, green light, 1P arms.
  14. `01:39.0` (`99.0 s`) — `kf_14_guildhall_front_gate_0139`: Wet cobbled street, iron fence/gate, patrolling guard, reflections.
  15. `01:51.0` (`111.0 s`) — `kf_15_zipwire_aim_0151`: 1P Zipwire launcher, `[HOLD] CRANK`, HUD prompts, courtyard skyline.
  16. `02:05.0` (`125.0 s`) — `kf_16_zipwire_crank_0205`: Zipwire cranking mid-ascent on brick wall.
  17. `02:15.0` (`135.0 s`) — `kf_17_courtyard_overlook_0215`: Upper vantage over `CONSTABLES' GUILDHALL` arch & lit courtyard.
  18. `02:29.0` (`149.0 s`) — `kf_18_smoke_bomb_0229`: Smoke Bomb white volumetric cloud + red stealth-gem arcs.
  19. `02:31.0` (`151.0 s`) — `kf_19_vistara_diamond_0231`: 1P Vistara Diamond crystal held in hand.
  20. `02:41.0` (`161.0 s`) — `kf_20_side_wing_macleod_0241`: Side wing `"MACLEOD"` neon sign, lamps, rain reflections.
  21. `03:01.0` (`181.0 s`) — `kf_21_locked_double_door_0301`: Blue double doors `[F] OPEN` / `[F] [HOLD] LOCK` prompt.
  22. `03:17.0` (`197.0 s`) — `kf_22_parlor_pickpocket_0317`: Fireplace parlor, `[F] PICK POCKET` / `[F] [HOLD] TAKEDOWN` on guard.
  23. `03:29.0` (`209.0 s`) — `kf_23_tripwire_barrier_0329`: Marble foyer, statue case, triggered purple crystalline barrier & alert icon.
  24. `03:35.0` (`215.0 s`) — `kf_24_arcane_door_escape_0335`: Purple barrier + green glowing arcane door lock + status icons.
  25. `03:44.0` (`224.0 s`) — `kf_25_pause_menu_0344`: Pause menu (`RESUME / SETTINGS / RETURN TO THIEF'S DEN / QUIT TO DESKTOP` + build/seed footer).

- **Annotation Method**:
  - Use `/usr/bin/python3` + `Pillow 13.0.0` (`ImageDraw`, `ImageFont` with `NotoSans-Regular.ttf` / `FreeSansBold.ttf`) driven by a declarative JSON/Python spec per keyframe (`bboxes`, `arrows/leaders`, `numbered callouts [1]..[N]`, high-contrast dark semi-transparent pill labels + top metadata bar showing `Timestamp | Segment | Location/UI`).
  - Maintain strict parity between callout numbers `[1]..[N]` drawn on `*_annotated.jpg` and the markdown table beneath each embedded image in the report.

---

## 5. Verification Method

1. **Video & Tooling Verification Commands**:
   ```bash
   ffprobe -v quiet -print_format json -show_format -show_streams "/home/john/Videos/clip_1,795,033,698,901.mp4"
   /usr/bin/python3 -c "import PIL, matplotlib, numpy; print(PIL.__version__, matplotlib.__version__, numpy.__version__)"
   magick -version
   ```
2. **Repo Hygiene & Layout Inspection**:
   ```bash
   find /home/john/Projects/TAT-2/docs -maxdepth 3 -type f | sort
   git -C /home/john/Projects/TAT-2 status
   ```
3. **Invalidation Conditions**:
   - Any script or agent invoking bare `python3` instead of `/usr/bin/python3` will fail `import PIL`.
   - Any cleanup of `/tmp` must target only the agent's own `mktemp -d` folder, and `git status` after completion must show zero edits outside `docs/` (preserving pre-existing `game/src/missions/mission_controller.gd`).
