> **SUPERSEDED — see [docs/HANDOFF_NEXT_AGENT.md](HANDOFF_NEXT_AGENT.md).**

# OpenCode Task Prompt: Finish the Official-Footage Reference Baseline (M2 + M3)

> Paste this whole file into OpenCode as the task prompt, or tell OpenCode:
> "Read and execute `docs/HANDOFF_OPENCODE_REFERENCE_BASELINE.md` end to end."

---

## 0. Who you are and what this is

You are finishing a documentation and analysis job in the repo `<repo>`. This repo is a
**Godot 4.7 port of the UE5 game *Thick As Thieves***. The user recorded gameplay footage of the **official**
game and wants a frame-accurate, timestamped **reference baseline**. They will later record the same slice in
the Godot port and compare the two side by side, so everything you write must be **comparison-ready**.

A previous multi-agent team ran out of quota partway through. It finished Milestone 1 and half of Milestone 2.
**You are doing the rest of Milestone 2 and all of Milestone 3, then a final verification pass.** Do not
redo finished work unless the verification steps below find it is wrong.

This is a **docs-only task**. You will write no game code.

---

## 1. Inputs (read these first, in this order)

| # | Path | What it is |
|---|---|---|
| 1 | `docs/HANDOFF_NEXT_SESSION.md` | Current state of the port: subsystems, gaps, hard limits. **Ground truth for cross-refs.** |
| 2 | `docs/reference/clip_1795033698901/_carryover/ORIGINAL_REQUEST.md` | The user's approved requirements (R1–R4) and acceptance criteria. |
| 3 | `docs/reference/clip_1795033698901/_carryover/PROJECT.md` | The team's plan: architecture, feature inventory, milestones, interface contracts. **Follow its contracts.** |
| 4 | `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` | **DONE, verified (M1 gate PASS).** Clip metadata, 27 contiguous segments `S01–S27`, the `KF01–KF30` table, ~64-row audio/VO table, verbatim UI text, and discrepancy resolutions. **Your factual backbone.** |
| 5 | `docs/reference/clip_1795033698901/clean/KF01..KF30_*.jpg` | **DONE, verified.** 30 clean 1920×1080 JPEG keyframes. |
| 6 | `docs/reference/clip_1795033698901/_carryover/M2_SCOPE.md` | M2 scope and contracts (annotation style, legend schema). |
| 7 | `_carryover/callout_spec_kf01_10.json`, `callout_spec_kf11_20.json`, `callout_spec_kf21_30.json` | **Draft pixel-coordinate callout specs for all 30 keyframes (unverified).** 58 + 56 + N callouts. |
| 8 | `_carryover/m2_explorer_{1,2,3}_handoff.md` | Notes from the agents that wrote those specs: tables, reasoning, caveats. |
| 9 | `_carryover/survey2_subsystems_gaps_limits.md` | **Catalog of TAT-2 Subsystems `#1–#18`, Hard Limits `HL-1..HL-9`, Parity Gaps `PG-1..PG-8`**, with exact repo citations, plus a recommended cross-reference schema (§4.1). |
| 10 | `_carryover/survey1_visual_audio.md`, `survey3_visual_audio.md` | Two independent first-pass surveys of the video (visual + audio). Useful but **superseded by KEYFRAME_INDEX.md wherever they disagree.** |
| 11 | `docs/FIDELITY_GAPS.md`, `docs/ARCHITECTURE.md`, `docs/PERFORMANCE.md`, `docs/ANDROID.md`, `docs/HANDOFF_OPENCODE.md`, `docs/reports/*.md` | Repo docs. Use them to confirm cross-reference citations. |
| 12 | `$HOME/Videos/clip_1,795,033,698,901.mp4` | **The source video.** 3840×2160 H.264, ~29.67 fps, 6,696 frames, 225.642 s (`03:45.64`), 48 kHz stereo AAC, about −43.9 LUFS. Note the commas in the filename: **always quote the path.** |

`_carryover/` = `docs/reference/clip_1795033698901/_carryover/`.

---

## 2. Hard rules (do not break these)

1. **Write only to these paths:**
   - `docs/REFERENCE_BASELINE.md` (new)
   - `docs/reference/clip_1795033698901/**` (new files, plus edits listed below)
   - You may append one short "Reference baseline" pointer section to `docs/HANDOFF_NEXT_SESSION.md` at the very end (optional, at most 10 lines).
2. **Never touch** `game/`, `tools/`, `build/`, `extracted/`, `game/.godot/`, or `game/data/generated/`.
   **In particular, `game/src/missions/mission_controller.gd` has a pre-existing uncommitted change
   (`--env-strip=0-8`) that belongs to the user. Leave it exactly as it is.** Do not `git checkout`, `git stash`,
   `git restore`, or reformat it.
3. **Do not change `clean/*.jpg`.** Edit `KEYFRAME_INDEX.md` only to fix a factual error you have
   **proven** against the video. Log every such fix in an `## Errata` section at the bottom of that file
   (timestamp, old text, new text, how you verified it).
4. **Python:** always call **`/usr/bin/python3`** (it has Pillow 13 and numpy). Bare `python3` resolves to Linuxbrew,
   which has **no PIL**. Other tools: `/usr/bin/ffmpeg`, `/usr/bin/ffprobe`, `/usr/bin/magick`.
5. **Fonts:** `/usr/share/fonts/google-noto/NotoSans-{Bold,SemiBold,Regular}.ttf` (confirmed to exist).
6. **Temporary files:** create one directory with `T=$(mktemp -d)` and keep all scratch frames, audio slices, and
   spectrograms in it. Delete it with `rm -rf "$T"` before you finish. Leave nothing in `/tmp`, and
   never write scratch files into the repo.
7. **Size budget:** `docs/reference/clip_1795033698901/` must stay **at or under 25 MiB** (it is about 6.4 MiB now). Annotated
   JPEGs: 1920×1080, quality 90, **under 750 KB each**.
8. **Report only what you can observe.** Every claim must be visible in a frame or audible in the clip.
   Do not invent engine parameters, off-screen content, or mechanics. If you are unsure, write
   `UNCERTAIN:` and the reason. When the video and an existing doc disagree, **the video wins.**
9. **No git commits or pushes** unless the user asks. Leave the work as uncommitted changes for the user to review.
10. **Do not delete `_carryover/` until the very last step**, and then only after the merged spec described below exists.

---

## 3. Status: what is done and what is left

| Milestone | Deliverable | Status |
|---|---|---|
| M1 | `KEYFRAME_INDEX.md` + `clean/KF01–KF30` | ✅ **DONE.** Passed the gate after 4 verify/fix iterations. |
| M2a | Callout coordinate specs (3 JSON drafts) | 🟡 **Drafted, unverified.** Schemas are inconsistent (see §4.1). |
| M2b | Render `annotated/KF01–KF30_*.jpg` | ❌ Not started |
| M2c | `CALLOUT_LEGENDS.md` | ❌ Not started |
| M2d | Visual QA of every annotated image | ❌ Not started |
| M3a | `BREAKDOWN.md` (exhaustive timestamped prose) | ❌ Not started |
| M3b | `docs/REFERENCE_BASELINE.md` (master index, cross-ref matrices, comparison checklist) | ❌ Not started |
| M3c | Comparison scorecard template for the port recording | ❌ Not started |
| M4 | Final adversarial verification and hygiene | ❌ Not started |

---

## 4. Milestone 2: annotated keyframes and callout legends

### 4.1 Merge and normalize the three spec files

- `callout_spec_kf01_10.json` and `callout_spec_kf11_20.json` store `"keyframes"` as a **dict** keyed by `"KF01"`, and so on.
- `callout_spec_kf21_30.json` stores `"keyframes"` as a **list**. Read the top of each file before you write a loader.
- Each keyframe has: `filename`, `segment`, `timestamp`, `hud_exclusions` (list of `[x0,y0,x1,y1]`), and `callouts[]`.
  Each callout has: `id`, `category` (`Visual` | `HUD/UI` | `Gameplay/Audio`), `code`, `label` (4 words or fewer),
  `target [x,y]`, `anchor [x,y]`, `placement` (`pill_left` | `pill_right`, plus any others you find), `bbox` (null or `[x0,y0,x1,y1]`),
  and `observed_ue5_detail`.
- Write **one** normalized file: `docs/reference/clip_1795033698901/callout_spec.json`. It is tracked and is the
  single source of truth. Use dict-keyed `KF01..KF30`, the same top-level `palette`, `fonts`, and `geometry` blocks, and `schema_version: "1.1"`.
- Validate it with a script. Fail loudly if any of these hold:
  - a filename does not exist in `clean/`
  - ids are not exactly `1..N`
  - a target or anchor is outside `safe_bounds [16,16,1904,1064]`
  - a label is longer than 4 words
  - a category is not in the palette
  - a timestamp/segment pair does not match `KEYFRAME_INDEX.md` §3
- Target **4–8 callouts per keyframe**. Each frame must have at least one `HUD/UI` callout **if any HUD is visible**, and
  every frame must have at least one `Gameplay/Audio` callout naming the audio state at that moment (including
  "No BGM" when there is none).

### 4.2 Normalize the `code` field to this taxonomy (the drafts reuse `V1`/`UI1`/`G1` loosely)

The 4-pillar comparison checklist uses these codes. **Every callout and checklist row must use them consistently.**

| Code | Pillar | Meaning |
|---|---|---|
| `V1` | Visual | Lighting: key/fill, practical lights, neon, volumetrics/god-rays, shadows |
| `V2` | Visual | Sky, atmosphere, fog, weather (rain, wetness, puddles), time of day |
| `V3` | Visual | Materials and shaders: albedo, roughness/specular, glass, emissive, decals |
| `V4` | Visual | Geometry and level dressing: architecture, props, set layout, LOD/pop-in |
| `V5` | Visual | Characters and animation: player 1P hands/tools, NPCs/guards, locomotion, takedowns |
| `V6` | Visual | VFX and particles: smoke, sparks, barriers, beams, tool effects |
| `V7` | Visual | Camera and post: FOV, framing, motion, exposure, colour grade, bloom, vignette, DOF |
| `UI1` | HUD/UI | Front-end menus (Startscreen, Pause, Settings) |
| `UI2` | HUD/UI | In-world interaction prompts (`[F] ...`, key glyphs) |
| `UI3` | HUD/UI | Persistent HUD: player card, compass, tools/ammo, health, objective, timer |
| `UI4` | HUD/UI | Full-screen or diegetic panels (Wardrobe, Journal/Ledger, Black Market, Map Table, Briefing letter, Loading) |
| `UI5` | HUD/UI | Alerts and feedback: detection pips, threat arcs, alarm states, toasts, countdowns |
| `G1` | Gameplay | Interactables and stations (den stations, doors, loot, telescope) |
| `G2` | Gameplay | Traversal and movement (zipwire, climbing, stairs, crouch/sprint) |
| `G3` | Gameplay | Tools and abilities (smoke bomb, zipwire gun, etc.) |
| `G4` | Gameplay | AI and guards: patrol, perception (red/green states), alert, takedown reactions |
| `G5` | Gameplay | Hazards, security, and mission flow: beams, arcane barriers, traps, objectives, loading/transition |
| `AU1` | Audio | Ambience and room tone (rain, wind, interior tone) and **explicit BGM absence** |
| `AU2` | Audio | Music (e.g. the gramophone jazz around `00:44–00:50`) |
| `AU3` | Audio | Footsteps and foley (surface-specific) |
| `AU4` | Audio | UI audio (clicks, hovers, countdown ticks, confirms) |
| `AU5` | Audio | Gameplay SFX (tools, zipwire, smoke, diamond, takedown, barrier, alarm, vehicles/horn) |
| `AU6` | Audio | Voice: VO, barks, dialogue (verbatim quotes) |

The badge **colour** follows `category` (Amber `#FFB300` = Visual `V*`; Cyan `#00E5FF` = HUD/UI `UI*`;
Magenta `#FF4081` = Gameplay/Audio `G*`/`AU*`). Keep the category and code prefix consistent.

### 4.3 Verify every coordinate before rendering (required)

For each keyframe, **open the clean JPEG and look at it** (OpenCode can read images). Confirm that every `target` sits
on the thing its label names, then fix any coordinates that miss. To read small text or confirm detail, re-extract the 4K
source frame at that timestamp:

```bash
T=$(mktemp -d)
ffmpeg -v error -ss 00:01.000 -i "$HOME/Videos/clip_1,795,033,698,901.mp4" -frames:v 1 "$T/kf01_4k.png"
# crop to zoom (4K coords = 2x the 1080p coords):
magick "$T/kf01_4k.png" -crop 1000x600+2590+560 +repage "$T/kf01_zoom.png"
```

Also cross-check each `observed_ue5_detail` against `KEYFRAME_INDEX.md`. If a detail is not in the index and is
not visible in the frame, cut it.

### 4.4 Renderer: `docs/reference/clip_1795033698901/tools/render_annotations.py`

This script is tracked so the output can be rebuilt. It must be **deterministic**: the same input gives byte-identical output, with no randomness or timestamps.

- CLI: `/usr/bin/python3 docs/reference/clip_1795033698901/tools/render_annotations.py [--only KF07] [--check]`.
  Paths are relative to the script's own location.
- Input: `callout_spec.json` + `clean/`. Output: `annotated/<same filename>`.
- Drawing per callout, in this order:
  1. Optional `bbox`: dashed rectangle, 2 px, in the category colour, with a 1 px black outline.
  2. Leader line from badge edge to `target`: 2.5 px category colour on a 1 px black casing (draw the casing first, wider).
  3. Target marker: a 6 px filled dot in the category colour with a black ring.
  4. Badge: a 28 px circle at `anchor`, category-colour fill, 2 px black stroke, centred `id` numeral in Noto Sans Bold
     16 px. Use black text on Amber and Cyan, white text on Magenta, or whichever gives better contrast.
  5. Label pill: 32 px tall, rounded, about 70% opaque black (`#000000B3`), 12 px horizontal padding, Noto Sans
     SemiBold 17 px white text. Place it left or right of the badge with a 6 px gap, according to `placement`.
- Composite with `Image.alpha_composite` on RGBA, then convert to RGB and save as JPEG `quality=90, optimize=True,
  subsampling=0`. If a file comes out at 750 KB or more, retry with `subsampling=2`, then `quality=88`.
- Add a small **legend strip** in a corner that does not cover HUD, about 14 px text: `KF07 · 00:27.xx · S06 · Amber=Visual Cyan=UI Magenta=Gameplay/Audio`. Leave it out if it would cover anything important.
- **Collision checks (in code):** treat badge circles, pills, and the legend strip as rectangles. Fail if any two overlap, if any
  fall outside `safe_bounds`, or if any overlap a rectangle in `hud_exclusions` (leader lines **may** cross into
  exclusions to reach a target there). Print a per-frame report. `--check` runs only the validation.

### 4.5 Look at every rendered image yourself (required)

Open **all 30** `annotated/*.jpg` and check:

- Each leader line ends on the correct object.
- No label is cut off.
- No callout covers the thing it describes, or any important HUD text.
- Numbers are readable.

Fix the spec, re-render, and look again until all 30 are clean. Keep a list of the frames you re-did.

### 4.6 `docs/reference/clip_1795033698901/CALLOUT_LEGENDS.md`

- Header: the purpose, the colour key, the code taxonomy table from §4.2, and how to regenerate the images (the exact command).
- For each `KF01..KF30`, a `### KFnn — <slug> (`MM:SS.ss`, Snn)` section with:
  - `![clean](clean/<file>)` and `![annotated](annotated/<file>)`, side by side or one after the other
  - a table `| # | Category | Code | Label | Target (x, y) | Observed UE5 Detail | TAT-2 Ref |`
  - rows `1..N` that **match the badges exactly**
  - `TAT-2 Ref` holding subsystem / PG / HL tags (fill these during M3)
- Generate this file **from `callout_spec.json` with a script**, not by hand, so the two cannot drift apart. Either extend the
  renderer with `--emit-legends` or write a sibling script in `tools/`.

**M2 done when:** 30 annotated JPEGs exist, the renderer `--check` passes, you have looked at all 30, `CALLOUT_LEGENDS.md` has 30 sections whose
row counts equal the badge counts, and the folder is 25 MiB or less.

---

## 5. Milestone 3: exhaustive breakdown and master baseline

### 5.1 `docs/reference/clip_1795033698901/BREAKDOWN.md`: the exhaustive timestamped description

This is the heart of the deliverable. It is a **continuous** account from `00:00.00` to `03:45.64` with **no gaps**, built on
the 27 segments `S01–S27` in `KEYFRAME_INDEX.md` §2. Use exactly the same segment ids and boundaries.

Top of file:

- clip metadata (copy it from KEYFRAME_INDEX §1)
- a table of contents
- a **Mermaid `flowchart LR`** of the act/segment flow: Startscreen → Loading 1 → Thieves' Den (Wardrobe, Telescope,
  Wanted window, Ledger/Journal, Black Market, Gramophone, Map Table) → Mission Prep countdown → Loading 2 →
  Briefing letter → Constables' Guildhall infiltration (safe room, alley, zipwire, overlook, smoke bomb, Vistara
  Diamond guard states, side wing, locked doors, parlor takedowns, foyer beam, arcane barriers, stairs alarm) → Pause menu.
  Use the real labels from the index. Quote any label that contains parentheses.

Per segment, use this exact template (all subsections are required; write `None observed.` rather than skipping one):

```markdown
## Snn — <Scene/UI State> (`MM:SS.ss`–`MM:SS.ss`, `d.dd s`)

**Keyframes:** KFxx (`MM:SS.ss`) [clean](clean/...) · [annotated](annotated/...) — see CALLOUT_LEGENDS.md#kfxx

### Narrative
2–6 sentences of plain-language "what happens", in time order, with sub-timestamps (`00:23.1`).

### Visual
- **Environment / geometry (V4):** …
- **Lighting (V1):** …
- **Sky / atmosphere / weather (V2):** …
- **Materials / shaders (V3):** …
- **Characters / animation (V5):** player 1P hands/tool pose, NPC/guard poses, locomotion …
- **VFX (V6):** …
- **Camera / post (V7):** FOV feel, motion, exposure, bloom, grade …

### HUD / UI
- **Layout and state (UI1–UI5):** every on-screen element and where it sits (e.g. "top-right player card"), with
  **verbatim text in backticks** exactly as in KEYFRAME_INDEX §5.2, including key glyphs like `[F]`, `[Q]`, `[E]`.

### Gameplay and interactions
- Player inputs you can infer from what is on screen, interactions, AI behaviour and state changes, mission-flow events, with
  timings (G1–G5).

### Audio
| Time | Layer (AU1–AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| … | … | … | e.g. `pk -27.1 dBFS`; or **"No BGM (explicit absence)"** |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| … | #x | `1:1_MATCH` / `APPROX_SHADER` / `KNOWN_GAP (PG-n)` / `HARD_LIMIT (HL-n)` / `UNVERIFIED_LIVE` / `NOT_IMPLEMENTED` | … | `docs/…md:Lx-Ly` or `game/src/…gd:Lx-Ly` |

### What to check in the port recording
- 3–8 bullet checks specific to this segment, each tagged with a pillar code (e.g. `[AU1]` rain bed present and no BGM;
  `[UI3]` player card top-right with level badge).
```

Sourcing rules for the breakdown:

- Pull from `KEYFRAME_INDEX.md` first, then the callout spec, then the surveys. **Before writing each segment, scrub
  the video for that segment** so you cover what happens *between* keyframes. Contact sheets help:
  ```bash
  ffmpeg -v error -ss <start> -to <end> -i "$HOME/Videos/clip_1,795,033,698,901.mp4" \
    -vf "fps=2,scale=480:-1,tile=6x5" -frames:v 1 "$T/S07_sheet.png"
  ```
  Then look at the sheet. For fast action (zipwire, takedowns, alarm), use `fps=6` on a shorter window.
- **Audio checks:** for every segment, confirm that each audio claim is backed by a measurement.
  ```bash
  ffmpeg -v error -ss <s> -to <e> -i "<clip>" -vn -ac 1 -ar 48000 "$T/seg.wav"
  ffmpeg -v error -i "$T/seg.wav" -lavfi showspectrumpic=s=1600x600:legend=1:scale=log "$T/seg_spec.png"   # look at it
  ffmpeg -i "$T/seg.wav" -af "astats=metadata=1:reset=0.1,ametadata=print:key=lavfi.astats.Overall.Peak_level" -f null - 2>&1 | tail
  ffmpeg -i "$T/seg.wav" -af ebur128 -f null - 2>&1 | tail -12
  ```
  Use spectrograms to tell music (harmonic, sustained bands) from rain (broadband noise) and to find transients
  (footsteps, clicks, impacts). You cannot hear the clip, so **phrase audio from evidence**: "broadband noise bed consistent
  with rain, −53 to −49 dBFS". Keep the existing verbatim VO quotes from KEYFRAME_INDEX §4. Do not invent new
  ones. If a VO line is unclear, mark it `UNCERTAIN`.
- **Cross-reference rules:** every subsystem, PG, and HL tag needs a real citation that you have **opened and confirmed**
  (file plus line range) in `docs/HANDOFF_NEXT_SESSION.md`, `docs/FIDELITY_GAPS.md`, `docs/reports/*.md`, or `game/src/**`
  (**read-only**). survey2 gives candidate citations, but line numbers may have shifted, so re-check them. Key mappings to get right:
  - All BGM, ambience, UI clicks, surface footsteps, and guard VO heard in the clip → **`PG-6`** (AudioManager wires only 9 static tags; no
    music, ambience, UI audio, surface footsteps, or barks; no bus routing). Room reverb character → **`HL-6`** (PLUG IRs undecodable).
  - Smoke plume, arcane barriers, sparks, and other particle look/rates → **`HL-1`** (Niagara VM) plus **`PG-7`** (smoke = box + particles).
  - Exact shader looks (neon, glass, wet cobbles) → **`HL-2`**-style material-graph limit and/or `APPROX_SHADER`; Startscreen exposure and
    neon saturation → **`PG-5`**.
  - Interior bounce light and exposure adaptation → **`HL-7`** (Lumen / Local Exposure).
  - Guard patrol paths → `HL-3`; guard locomotion foot-slide, takedown montage reuse, missing 1P body → **`PG-7`**.
  - Wardrobe, Map Table, Mission Prep FOV, Zipwire crank, guard alert pips/arcs, lockpick UI → **`PG-2`** live E2E fails (`S03/S04/S06/S11/S14/S15b`
    are **port test-scenario ids**, not clip segments; say so in the doc to avoid confusion).
  - Zipwire crank, stairs, and doors behaviour → **`PG-4`** (headless-green, not live-confirmed).
  - Read HL-1..HL-9 and PG-1..PG-8 in full in survey2 §1.3 and use the exact ids.

### 5.2 `docs/REFERENCE_BASELINE.md`: the master index and comparison framework

Sections, in order:

1. **Purpose and how to use it.** Two or three paragraphs: this is the target; the next step is recording the port and scoring it.
2. **Deliverable map.** Links to `KEYFRAME_INDEX.md`, `BREAKDOWN.md`, `CALLOUT_LEGENDS.md`, `callout_spec.json`, `clean/`,
   `annotated/`, `tools/`, `COMPARISON_TEMPLATE.md`.
3. **Clip facts.** Duration, resolution, fps, audio format, loudness, game build string if visible (use the value resolved in KEYFRAME_INDEX §5).
4. **Timeline at a glance.** A table of S01–S27 (id, start, end, duration, scene, keyframes) plus the Mermaid flow.
5. **Methodology.** How frames were picked, the annotation colour/code system, and how audio was analysed (spectrogram/astats/ebur128 with
   no listening). Name the known blind spots honestly.
6. **TAT-2 Subsystem matrix.** One row per subsystem `#1–#18` (name, key files, where it appears in the clip by segment and keyframe,
   overall parity status, notes).
7. **Parity-gap matrix** `PG-1..PG-8` and **Hard-limit matrix** `HL-1..HL-9`. For each: description, citation, every clip segment where it
   shows, and what a viewer of the port will notice.
8. **4-pillar comparison checklist.** Tables for Visual `V1–V7`, Audio `AU1–AU6`, UI `UI1–UI5`, Gameplay `G1–G5`. Each row is one concrete,
   checkable criterion with a reference (segment, keyframe, callout #). Columns:
   `| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |`.
   Leave the port columns blank. Score enum: `PASS | DELTA | MISSING | HARD_LIMIT | N/A`, with a definition of each.
   Aim for **at least 60 rows total**, with every segment represented at least once.
9. **Port capture protocol.** Exact instructions for recording comparable footage:
   - Play the **same route and actions in the same order**, using the segment list as a script.
   - Capture at 1920×1080 or higher, 30 or 60 fps, with audio on. The port renders at 1280×720 with stretch, so note that.
   - Name the file `docs/reference/port_<date>/…` (create it only when the user records).
   - How to align the two clips: per-segment start events (e.g. first frame of the Den, countdown "6", loading-screen cut). List
     an **alignment anchor event per segment**.
   - How to extract matching frames: `ffmpeg -ss <aligned ts> ... -frames:v 1` and a side-by-side command, e.g.
     `magick official.jpg port.jpg +append side_by_side.jpg`, or ffmpeg `hstack`.
10. **Comparison workflow.** Step-by-step for the next session: align → extract → hstack → score checklist → summarize deltas →
    file follow-ups against PG/HL.

### 5.3 `docs/reference/clip_1795033698901/COMPARISON_TEMPLATE.md`

A copy of the checklist from §5.2 item 8, formatted as a blank, fill-in scorecard. Add:

- a per-segment section with slots `![official](clean/KFnn...) | ![port](../port_<date>/KFnn...)`
- an alignment-offset table (`Snn | official anchor ts | port anchor ts | offset`)
- a summary table at the bottom: counts per score per pillar

Optional but encouraged: `tools/make_side_by_side.sh <port_clip> <offsets.csv>`, which extracts frames from the port clip at aligned
timestamps and builds `hstack` comparison images with the same filenames. Make it a plain bash script, never run it on
nonexistent input, and make it print usage when given no arguments.

**M3 done when:** BREAKDOWN.md covers S01–S27 continuously with every template subsection present; every keyframe and callout is
referenced; REFERENCE_BASELINE.md and COMPARISON_TEMPLATE.md are complete; and every citation has been opened and confirmed.

---

## 6. Milestone 4: final verification (run all of it, and fix anything that fails)

Write one script, `docs/reference/clip_1795033698901/tools/verify_baseline.py` (run it with `/usr/bin/python3`, tracked). It must check:

1. **Timeline continuity:** the S01–S27 boundaries in BREAKDOWN.md exactly match KEYFRAME_INDEX §2; `S01.start == 00:00.00`;
   `S27.end == 03:45.64`; `Seg[n].end == Seg[n+1].start`.
2. **Template completeness:** every segment section contains `### Narrative`, `### Visual`, `### HUD / UI`,
   `### Gameplay and interactions`, `### Audio`, `### TAT-2 cross-reference`, and `### What to check in the port recording`.
3. **Images:** every image path linked from any `.md` under `docs/reference/clip_1795033698901/` and from `docs/REFERENCE_BASELINE.md`
   exists, opens with PIL, is 1920×1080, and is non-empty. `clean/` and `annotated/` hold identical filename sets (30 each).
   Annotated files are under 750 KB. The folder total is 25 MiB or less.
4. **Callout parity:** for each KF, the number of `callout_spec.json` callouts equals the `CALLOUT_LEGENDS.md` row count, and ids are `1..N`.
5. **Timestamp parity:** each KF timestamp is identical across KEYFRAME_INDEX §3, `callout_spec.json`, CALLOUT_LEGENDS, and BREAKDOWN.
6. **Code taxonomy:** every code used is in the §4.2 set, and the category matches the code prefix.
7. **Cross-ref ids:** every `PG-n` used satisfies 1 ≤ n ≤ 8, every `HL-n` satisfies 1 ≤ n ≤ 9, every subsystem `#n` satisfies 1 ≤ n ≤ 18, and every parity status is in the enum.
8. **Determinism:** re-run the renderer into a temp dir and confirm the output is byte-identical to `annotated/`.

Then do these **manual adversarial spot checks**, and record the results in a `## Verification log` section at the end of
`REFERENCE_BASELINE.md`:

- Pick **at least 12 random claims** across BREAKDOWN.md (at least 4 visual, 3 HUD verbatim text, 3 audio, 2 gameplay timings). Extract the
  4K frame or audio slice for each and confirm or refute it. Fix everything you refute. Log each one as claim → evidence command → verdict.
- Re-open **at least 6 annotated images** chosen at random and confirm that their callouts are correct.
- Re-open **at least 8 cross-reference citations** at random and confirm that the line ranges still say what you claim.

**Hygiene, last:**

```bash
cd <repo>
git status --short          # expect ONLY: " M game/src/missions/mission_controller.gd" (pre-existing),
                            # "?? docs/REFERENCE_BASELINE.md", "?? docs/reference/", and optionally
                            # " M docs/HANDOFF_NEXT_SESSION.md" and this handoff file.
git diff --stat -- game tools build extracted   # must show nothing new beyond mission_controller.gd
du -sh docs/reference/clip_1795033698901        # <= 25 MiB
rm -rf "$T"                                     # your temp dir
```

Only after `verify_baseline.py` passes and `callout_spec.json` exists: **delete
`docs/reference/clip_1795033698901/_carryover/`**. Before you delete it, make sure anything still useful from it has been folded into the final
docs. The survey files are scratch and should not be shipped.

---

## 7. Final report to the user (when everything is green)

Reply with a short summary:

- the files you created and changed, with links
- callout and keyframe counts, and the folder size
- the `verify_baseline.py` output
- spot-check results: how many claims checked and refuted/fixed, with a list of any KEYFRAME_INDEX errata
- any remaining `UNCERTAIN:` items
- the exact next step for the user: record the port slice following the "Port capture protocol" in `docs/REFERENCE_BASELINE.md` §9,
  then ask for the comparison

---

## 8. Practical tips

- **Quote the video path every time.** The commas in the filename break unquoted shells.
- Seeking: put `-ss` **before** `-i` for fast seeks. For frame-exact checks, put it after `-i`, which is slower but exact. The frame rate is about 29.67
  (variable-ish), so give timestamps to 2 decimal places as the index does.
- 4K coordinates are 2× the 1080p coordinates in the spec.
- Work in small steps: get `--only KF01` rendering perfectly before you batch all 30.
- If you run low on context, stop at a clean checkpoint (after a whole milestone). Append a `## Progress` section to the
  end of **this file** saying exactly what is done and what is next, so the following session can resume.
