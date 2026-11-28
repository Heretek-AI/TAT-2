> **SUPERSEDED — see [docs/HANDOFF_NEXT_AGENT.md](HANDOFF_NEXT_AGENT.md).**

# `omo` (`ulw`) Master Handoff: Complete the Official-Footage Reference Baseline

> **How to launch this in standalone `omo` (pi coding agent):**
> Run `omo` inside `<repo>` and send:
> ```text
> ulw Read and execute docs/HANDOFF_OMO_ULW_REFERENCE_BASELINE.md end to end. Use mass-parallel background agents for independent waves, verify every deliverable deterministically and adversarially, and do not stop until every acceptance gate in §8 passes.
> ```

---

## 0. Mission & Orchestration Mode (`ulw` / Mass Parallel)

You are completing the **Official Gameplay Footage Reference Baseline** in `<repo>` (a Godot 4.7 Forward+ port of the UE5 game *Thick As Thieves*). The user recorded gameplay footage of the **official** UE5 build (`$HOME/Videos/clip_1,795,033,698,901.mp4`) and will later record the matching slice from their Godot port for a 1:1 side-by-side comparison.

### Execution Architecture (Standalone `omo` `ulw` Mode)
- **Do NOT use `opencode-teamwork-v2` (`teamwork_*` tools) or per-task git worktrees.** Work directly in `<repo>` using `omo` **ultrawork (`ulw`)** mass-parallel background agents and atomic file/Hashline edits.
- **No-collision rule for parallel writers:** When fanning out across segments or research tasks, each parallel agent MUST write to its own staging file under `docs/reference/clip_1795033698901/_build/` (e.g., `_build/seg_s05_s13.md`, `_build/audio_metrics.md`, `_build/citations_verified.md`), and the lead orchestrator merges them into `BREAKDOWN.md` / `REFERENCE_BASELINE.md` once all wave agents return.
- **This is a docs-only task.** You will write zero game code.
- **Never stop halfway:** Keep driving through Waves 0 → 4 until every check in §8 passes and you have run the adversarial spot checks.

---

## 1. Current State on Disk (Verified M1 + M2 — Do NOT Redo)

Prior work (M1 + M2, including `hud-semantics` and `m2-audit` fixes) has already been synced into `<repo>/docs/reference/clip_1795033698901/`.

| Artifact | Status | Details |
|---|---|---|
| `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` | ✅ **DONE (M1+M2)** | Clip metadata (`ffprobe`/`ebur128`), 27 contiguous segments `S01–S27` (`00:00.00–03:45.64`), `KF01–KF30` table, 64-row audio/VO table, §5 verbatim UI & discrepancy resolutions, `## Errata` (8 entries). |
| `docs/reference/clip_1795033698901/clean/KF01..KF30_*.jpg` | ✅ **DONE (M1)** | 30 clean `1920x1080` JPEGs. **Do not modify.** |
| `docs/reference/clip_1795033698901/callout_spec.json` | ✅ **DONE (M2)** | Normalized `schema_version: "1.1"`, `195` callouts across `KF01–KF30` (`4–8` per KF), corrected Light Gem & noise-arc HUD semantics, explicit BGM presence/absence on all 30 KFs. |
| `docs/reference/clip_1795033698901/annotated/KF01..KF30_*.jpg` | ✅ **DONE (M2)** | 30 deterministic `1920x1080` JPEGs (`<= 549 KB` each). |
| `docs/reference/clip_1795033698901/CALLOUT_LEGENDS.md` | ✅ **DONE (M2)** | Generated from `callout_spec.json` via `tools/render_annotations.py --emit-legends`; 30 sections / 195 rows. *(During M3, check whether the `TAT-2 Ref` column should be populated with subsystem/PG/HL tags via `callout_spec.json` + `--emit-legends`.)* |
| `docs/reference/clip_1795033698901/tools/render_annotations.py` & `merge_callout_specs.py` | ✅ **DONE (M2)** | Deterministic renderer (`--check` passes `30/30`), legend emitter, and guarded merger. |
| `docs/reference/clip_1795033698901/_build/m2_audit_validate.py` | ✅ **DONE (M2)** | Hardened schema/taxonomy/BGM validator (`ALL CHECKS PASSED`). |
| `docs/reference/clip_1795033698901/BREAKDOWN.md` | 🟡 **PARTIAL (`S01–S04` only)** | Header, clip metadata, TOC, Mermaid `flowchart LR`, and `S01–S04` are complete. **`S05–S27` are missing.** |
| `docs/REFERENCE_BASELINE.md` | ❌ **NOT STARTED (M3)** | Master index, methodology, `#1–#18` / `PG-1..PG-8` / `HL-1..HL-9` matrices, 60+ row 4-pillar comparison checklist, port capture protocol, `## Verification log`. |
| `docs/reference/clip_1795033698901/COMPARISON_TEMPLATE.md` | ❌ **NOT STARTED (M3)** | Blank 1:1 scorecard mirroring `REFERENCE_BASELINE.md` §8 + 27 segment image slots + 27 alignment rows + summary table (+ optional `tools/make_side_by_side.sh`). |
| `docs/reference/clip_1795033698901/tools/verify_baseline.py` | ❌ **NOT STARTED (M4)** | Deterministic 8-check verification script. |
| `docs/reference/clip_1795033698901/_carryover/` | 🧹 **SCRATCH (Delete in M4)** | Contains `PROJECT.md`, `ORIGINAL_REQUEST.md`, `survey1_visual_audio.md`, `survey2_subsystems_gaps_limits.md`, `survey3_visual_audio.md`, etc. **Keep until M4 passes, then delete.** |

---

## 2. Inputs & Ground-Truth Reference Files

Read/reference these in order of authority (when video and docs disagree, **the video wins**):

1. `$HOME/Videos/clip_1,795,033,698,901.mp4` — **Source video**: `225.642333 s` (`03:45.64`), `3840x2160` H.264 High, `~29.672 fps` (6,696 frames), `48 kHz` stereo AAC (`-43.9 LUFS`). **Always quote the path** because of the commas.
2. `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` — Factual spine for timestamps, segments `S01–S27`, verbatim UI text, and VO/audio cues.
3. `docs/reference/clip_1795033698901/callout_spec.json` & `CALLOUT_LEGENDS.md` — Verified 195 callouts across `KF01–KF30`.
4. `docs/HANDOFF_NEXT_SESSION.md` — Ground truth for TAT-2 port status, subsystems, parity gaps, and hard limits.
5. `docs/reference/clip_1795033698901/_carryover/survey2_subsystems_gaps_limits.md` — Pre-mined catalog of Subsystems `#1–#18`, Hard Limits `HL-1..HL-9`, and Parity Gaps `PG-1..PG-8` with candidate repo citations (you **must** re-open and confirm line numbers against live `docs/` and `game/src/**`).
6. `docs/FIDELITY_GAPS.md`, `docs/ARCHITECTURE.md`, `docs/PERFORMANCE.md`, `docs/ANDROID.md`, `docs/HANDOFF_OPENCODE.md`, `docs/reports/*.md` — Repo documentation for confirming citations.
7. `docs/reference/clip_1795033698901/_carryover/survey1_visual_audio.md` & `survey3_visual_audio.md` — First-pass surveys (superseded by `KEYFRAME_INDEX.md` wherever they conflict).

---

## 3. Hard Rules & Environment Invariants

1. **Allowed write paths ONLY:**
   - `docs/REFERENCE_BASELINE.md`
   - `docs/reference/clip_1795033698901/**`
   - Optional: append at most a 10-line pointer section at the end of `docs/HANDOFF_NEXT_SESSION.md` linking to `docs/REFERENCE_BASELINE.md`.
2. **NEVER touch** `game/`, `tools/`, `build/`, `extracted/`, `game/.godot/`, `game/data/generated/`, or `game/src/missions/mission_controller.gd`.
3. **NEVER modify `clean/*.jpg`.** Only edit `KEYFRAME_INDEX.md` if you prove a factual error directly against the 4K video/audio; log every fix in `KEYFRAME_INDEX.md` `## Errata`.
4. **Python executable:** Always use **`/usr/bin/python3`** (has `Pillow 13.0.0`, `numpy`, `matplotlib`). Never use bare `python3` (resolves to Linuxbrew without `PIL`).
5. **Media tools:** `/usr/bin/ffmpeg`, `/usr/bin/ffprobe`, `/usr/bin/magick`. Always quote `"$HOME/Videos/clip_1,795,033,698,901.mp4"`.
6. **Temp files:** Create one temp root `T=$(mktemp -d)` for scratch frames, contact sheets, `.wav` slices, and spectrograms; delete it with `rm -rf "$T"` before finishing. Leave nothing in `/tmp`.
7. **Folder size budget:** `docs/reference/clip_1795033698901/` MUST stay **`<= 25 MiB`** (currently `16 MiB`).
8. **Evidence-only rule:** Never invent mechanics, engine parameters, off-screen events, or VO lines. Use `UNCERTAIN:` if unclear. Because you cannot listen to audio directly, phrase every audio observation from measured `ffmpeg` evidence (`showspectrumpic`, `astats` peak/RMS dBFS, `ebur128`) plus verified `KEYFRAME_INDEX.md` §4 quotes.
9. **No git commits or pushes** unless the user asks. Leave finished files in the working tree for review.

---

## 4. Normative Domain Glossary & Taxonomy (Must Be Enforced Everywhere)

### 4.1 HUD Semantics (User-Corrected Ground Truth)
- **Light Gem (`UI3`)**: The bottom-center diamond/gem indicates **how much light is on the player and from what direction** (warm lit sector size = light exposure amount; sector position = light source direction; bright = exposed, dark = concealed).
- **Red Arcs (`UI5`)**: The concentric red arcs around/above the gem indicate the **player's own noise level** (large = loud, absent = quiet) — **NEVER** call them "enemy threat arcs" or "enemy detection".
- **Guard Alert Pips (`UI5`)**: Distinct directional/overhead indicators (e.g., `KF17` mid-right alert pip, `KF21` red alert, `KF22` green suspicion) represent NPC awareness.

### 4.2 Segment IDs vs. Port E2E Scenario IDs (Disambiguate Explicitly)
- `S01–S27` in `KEYFRAME_INDEX.md` / `BREAKDOWN.md` are **clip timeline segments**.
- `S03/S04/S06/S11/S14/S15b` in `PG-2` (`docs/HANDOFF_NEXT_SESSION.md`, `docs/reports/fidelity-mechanics-wave.md`) are **TAT-2 Godot port E2E test-scenario IDs**. Always clarify `(port test scenario ...)` when citing `PG-2` so readers never confuse `S14` (clip 1st zipwire) with `S14` (port `guard_lantern_alert` test).

### 4.3 4-Pillar Code Taxonomy (Used in Callouts, Breakdown, Baseline & Scorecard)
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
| `UI3` | HUD/UI | Persistent HUD: player card, compass, light gem, tools/ammo, health, objective, timer |
| `UI4` | HUD/UI | Full-screen or diegetic panels (Wardrobe, Journal/Ledger, Black Market, Map Table, Briefing letter, Loading) |
| `UI5` | HUD/UI | Alerts and feedback: player noise arcs, guard alert pips, alarm states, toasts, countdowns |
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

### 4.4 TAT-2 Cross-Reference IDs & Parity Enum
- **Subsystems:** `#1–#18` (from `_carryover/survey2_subsystems_gaps_limits.md` §1.2, re-verified against live repo).
- **Parity Gaps:** `PG-1..PG-8` (Den RD cascade/teardown `PG-1`; 7 live E2E fails `PG-2`; 2 Tier-1 headless fails `PG-3`; Phase 4 mechanics unconfirmed live `PG-4`; residual visual deltas `PG-5`; AudioManager missing BGM/ambience/UI/surface footsteps/barks/reverb `PG-6`; 3D gameplay/anim simplifications `PG-7`; OldManor/Steam-56/Android unverified `PG-8`).
- **Hard Limits:** `HL-1..HL-9` (Niagara VM `HL-1`; UE5 material graphs `HL-2`; BP/patrol splines `HL-3`; 1P idle/blendspaces `HL-4`; MagicSlime/bottle/pickup amounts `HL-5`; 6 Wwise PLUG IRs `HL-6`; Lumen GI/Local Exposure `HL-7`; 52 empty landscape splines & grass `HL-8`; doorway pivot/periphery/OldManor quirks `HL-9`).
- **Parity Status Enum:** `1:1_MATCH` | `APPROX_SHADER` | `KNOWN_GAP (PG-n)` | `HARD_LIMIT (HL-n)` | `UNVERIFIED_LIVE` | `NOT_IMPLEMENTED`.

---

## 5. Mass-Parallel Execution Plan (Waves 0 → 4)

### Wave 0: Preflight & Grounding (Lead Orchestrator)
1. Confirm baseline integrity before launching Wave 1:
   ```bash
   cd <repo>
   /usr/bin/python3 docs/reference/clip_1795033698901/tools/render_annotations.py --check
   /usr/bin/python3 docs/reference/clip_1795033698901/_build/m2_audit_validate.py
   ```
2. Read `docs/reference/clip_1795033698901/BREAKDOWN.md` (`S01–S04`) so all Wave 1–2 writers match its exact formatting, tone, and heading style.
3. Create `T=$(mktemp -d)` for temporary contact sheets and audio slices.

### Wave 1: Mass-Parallel Data Gathering & Segment Drafting (5 Concurrent Agents)
Launch **all 5 background agents simultaneously**, each writing ONLY to its own `_build/` file:

1. **Agent 1 — Audio Forensics (`S05–S27`) → `_build/audio_s05_s27.md`**
   - Run `ffmpeg` `astats` (0.1 s reset Peak/RMS), `ebur128`, and `showspectrumpic` on every segment `S05–S27` inside `"$T"`.
   - Record exact dBFS Peak/RMS ranges, broadband noise vs. harmonic bands (e.g. `S07` gramophone jazz `00:44–00:50`) vs. sharp transients (clicks, footsteps, zipwire, smoke, takedown, alarm), and explicit BGM absence for every segment, cross-checked against `KEYFRAME_INDEX.md` §4.

2. **Agent 2 — Citation Verification (`#1–#18`, `PG-1..PG-8`, `HL-1..HL-9`) → `_build/citations_verified.md`**
   - Start from `_carryover/survey2_subsystems_gaps_limits.md` and **actually open every cited file** in `docs/HANDOFF_NEXT_SESSION.md`, `docs/FIDELITY_GAPS.md`, `docs/ARCHITECTURE.md`, `docs/PERFORMANCE.md`, `docs/ANDROID.md`, `docs/reports/*.md`, and `game/src/**` (read-only).
   - Output verified `file:Lstart-Lend` citations for all 18 subsystems, `PG-1..PG-8`, and `HL-1..HL-9` so downstream writers never cite stale line numbers.

3. **Agent 3 — Visual/UI/Gameplay Scrub `S05–S13` → `_build/seg_s05_s13.md`**
   - Extract `fps=2` (and `fps=6` for transitions/countdown) contact sheets into `"$T"` for `S05–S13`, inspect them + clean/annotated `KF05–KF14`, and draft `S05–S13` following the exact §6.1 segment template (leaving audio dBFS / citation line numbers to be merged from Agents 1 & 2, or reading them if ready).

4. **Agent 4 — Visual/UI/Gameplay Scrub `S14–S20` → `_build/seg_s14_s20.md`**
   - Extract `fps=2` (`fps=6` for zipwire launches, roof fall, smoke bomb throw/plume) contact sheets into `"$T"` for `S14–S20`, inspect them + `KF15–KF23`, and draft `S14–S20` following §6.1.

5. **Agent 5 — Visual/UI/Gameplay Scrub `S21–S27` → `_build/seg_s21_s27.md`**
   - Extract `fps=2` (`fps=6` for `S22–S26` pickpocket, takedown, beam, arcane barriers, alarm stairs) contact sheets into `"$T"` for `S21–S27`, inspect them + `KF24–KF30`, and draft `S21–S27` following §6.1.

### Wave 2: Merge `BREAKDOWN.md` + Author `REFERENCE_BASELINE.md`
1. **Merge `_build/seg_*.md` + `_build/audio_s05_s27.md` + `_build/citations_verified.md` into `docs/reference/clip_1795033698901/BREAKDOWN.md`**:
   - Append `S05–S27` seamlessly after `S04` with exact `KEYFRAME_INDEX.md` §2 boundaries (`00:00.00–03:45.64`, zero gaps).
   - Enforce HUD glossary (`Light Gem = UI3`, `Red Arcs = UI5 player noise`, never "threat arcs").
2. **Author `docs/REFERENCE_BASELINE.md`** (all 10 sections from §6.2 below, using `_build/citations_verified.md` and `BREAKDOWN.md`).
3. **(Optional M3 enrichment)**: If `CALLOUT_LEGENDS.md` `TAT-2 Ref` column is empty/placeholder, populate `tat2_ref` in `callout_spec.json` and re-run `tools/render_annotations.py --emit-legends` (without changing rendered JPEG pixels).

### Wave 3: Parallel Scorecard + Deterministic Verifier
Dispatch **2 concurrent agents**:
1. **Agent 6 — `docs/reference/clip_1795033698901/COMPARISON_TEMPLATE.md` + `tools/make_side_by_side.sh`**:
   - Mirror `REFERENCE_BASELINE.md` §8 checklist 1:1, add 27 per-segment `![official](clean/KFnn...) | ![port](../port_<date>/KFnn...)` slots, 27 alignment rows, and summary score table.
   - Write `tools/make_side_by_side.sh <port_clip> <offsets.csv>` (plain bash, prints usage with 0 args, refuses missing files, `bash -n` clean).
2. **Agent 7 — `docs/reference/clip_1795033698901/tools/verify_baseline.py`**:
   - Implement all 8 deterministic checks in `/usr/bin/python3` (stdlib + Pillow only, path-relative, zero randomness/timestamps, Check 8 renders into a temp dir and compares SHA-256 against `annotated/` without touching `annotated/`).

### Wave 4: Adversarial Verification, Spot Checks & Hygiene Cleanup
1. Run:
   - `/usr/bin/python3 docs/reference/clip_1795033698901/tools/verify_baseline.py`
   - `/usr/bin/python3 docs/reference/clip_1795033698901/_build/m2_audit_validate.py`
   - `/usr/bin/python3 docs/reference/clip_1795033698901/tools/render_annotations.py --check`
2. **Parallel Adversarial Spot-Check Wave** (2–3 read-only verifier agents):
   - Spot-check **>= 12 random claims** in `BREAKDOWN.md` (at least 4 visual, 3 HUD verbatim text, 3 audio dBFS/spectrogram, 2 gameplay timings) against 4K frames and `.wav` slices. Fix any refuted claim (and log in `KEYFRAME_INDEX.md` `## Errata` if index-related).
   - Re-open **>= 6 annotated images** at random to confirm badge/label accuracy.
   - Re-open **>= 8 repo citations** at random to confirm exact file + line ranges.
   - Record all spot checks (`Claim -> Evidence Command -> Verdict`) in `docs/REFERENCE_BASELINE.md` `## Verification log`.
3. **Final Cleanup & Hygiene Gate**:
   - Delete `docs/reference/clip_1795033698901/_carryover/` and temporary `_build/` staging files (`_build/seg_*.md`, `_build/audio_*.md`, `_build/citations_*.md`; keep `_build/m2_audit_validate.py` or fold its checks into `verify_baseline.py` if cleaner).
   - Delete `"$T"` (`rm -rf "$T"`).
   - Re-run `verify_baseline.py` **after** final cleanup so the last run reflects the exact shipped tree.

---

## 6. Deliverable Specifications

### 6.1 `docs/reference/clip_1795033698901/BREAKDOWN.md` (`S05–S27` Segment Template)
Match `S01–S04` already in `BREAKDOWN.md`. Every segment `S05–S27` MUST include all 7 subsections (`None observed.` if empty, never omit):
```markdown
## Snn - <Scene/UI State> (`MM:SS.ss`-`MM:SS.ss`, `d.dd s`)

**Keyframes:** KFxx (`MM:SS.ss`) [clean](clean/...) · [annotated](annotated/...) - see CALLOUT_LEGENDS.md#kfxx

### Narrative
2–6 sentences of plain-language "what happens", in time order, with sub-timestamps.

### Visual
- **Environment / geometry (V4):** ...
- **Lighting (V1):** ...
- **Sky / atmosphere / weather (V2):** ...
- **Materials / shaders (V3):** ...
- **Characters / animation (V5):** ...
- **VFX (V6):** ...
- **Camera / post (V7):** ...

### HUD / UI
- **Layout and state (UI1–UI5):** every visible element, position, and **verbatim text in backticks** matching `KEYFRAME_INDEX.md` §5.2.

### Gameplay and interactions
- Player inputs inferred from screen, interactions, AI state changes, mission flow, with timings (`G1–G5`).

### Audio
| Time | Layer (AU1–AU6) | Cue / verbatim quote | Level / notes |
|---|---|---|---|
| ... | ... | ... | e.g. `pk -27.1 dBFS`; or **"No BGM (explicit absence)"** |

### TAT-2 cross-reference
| Observed element | Subsystem # | Parity status | PG / HL | Citation |
|---|---|---|---|---|
| ... | #x | `1:1_MATCH` / `APPROX_SHADER` / `KNOWN_GAP (PG-n)` / `HARD_LIMIT (HL-n)` / `UNVERIFIED_LIVE` / `NOT_IMPLEMENTED` | ... | `docs/...md:Lx-Ly` |

### What to check in the port recording
- 3–8 concrete bullet checks tagged `[V1]` / `[AU1]` / `[UI3]` / `[G4]`, etc.
```

### 6.2 `docs/REFERENCE_BASELINE.md` (10 Required Sections)
1. **Purpose and how to use it**
2. **Deliverable map** (clickable links to `KEYFRAME_INDEX.md`, `BREAKDOWN.md`, `CALLOUT_LEGENDS.md`, `callout_spec.json`, `clean/`, `annotated/`, `tools/`, `COMPARISON_TEMPLATE.md`)
3. **Clip facts** (matching `KEYFRAME_INDEX.md` §1; build `1.5.148559`, `Novice`, seed `1025051536`)
4. **Timeline at a glance** (27-row table `S01–S27` + Mermaid `flowchart LR`)
5. **Methodology** (keyframe selection, annotation color/code system, HUD semantics glossary, audio spectrogram/`astats`/`ebur128` method & honest blind-spot disclosure)
6. **TAT-2 Subsystem matrix** (`#1–#18`: name, key files, clip segments/keyframes where observed, overall parity status, notes)
7. **Parity-gap (`PG-1..PG-8`) & Hard-limit (`HL-1..HL-9`) matrices** (description, verified citation, clip segments where visible/audible, port viewer impact)
8. **4-pillar comparison checklist** (`V1–V7`, `AU1–AU6`, `UI1–UI5`, `G1–G5`; **>= 60 rows total**; every segment `S01–S27` represented >= 1x; columns `| ID | Criterion | Reference (Snn / KFnn #k) | Official observation | Port observation | Score | Notes |`; Port columns blank; Score enum `PASS | DELTA | MISSING | HARD_LIMIT | N/A`)
9. **Port capture protocol** (route script, `>= 1920x1080` capture noting Godot `1280x720` stretch, `docs/reference/port_<date>/...` naming, **27 alignment anchor events**, `ffmpeg` + `magick +append` / `hstack` commands)
10. **Comparison workflow** + **`## Verification log`** (populated in Wave 4).

### 6.3 `docs/reference/clip_1795033698901/tools/verify_baseline.py` (8 Mandatory Checks)
1. Timeline continuity (`BREAKDOWN.md` `S01–S27` == `KEYFRAME_INDEX.md` §2; `00:00.00` → `03:45.64`; `Seg[n].End == Seg[n+1].Start`).
2. Template completeness (all 27 segments have all 7 `###` subsections).
3. Image integrity (every linked `.jpg` exists, opens with PIL, `1920x1080`, non-empty; `clean/` and `annotated/` have identical 30 filenames; annotated `< 750 KB`; folder `<= 25 MiB`).
4. Callout parity (`callout_spec.json` counts == `CALLOUT_LEGENDS.md` row counts; IDs `1..N`).
5. Timestamp parity (identical KF timestamps across `KEYFRAME_INDEX.md` §3, `callout_spec.json`, `CALLOUT_LEGENDS.md`, `BREAKDOWN.md`).
6. Code taxonomy (every code in `V1–V7`, `UI1–UI5`, `G1–G5`, `AU1–AU6`; category matches prefix).
7. Cross-ref IDs (`1 <= PG <= 8`, `1 <= HL <= 9`, `1 <= Subsystem <= 18`, valid parity status enum).
8. Determinism (copies clip dir to temp dir, runs `render_annotations.py`, compares SHA-256 of all 30 JPEGs against `annotated/` without touching `annotated/`).

---

## 7. Quick Pitfall Reference
- **Never** run bare `python3` — always `/usr/bin/python3`.
- **Never** leave `threat arcs` / `enemy threat` outside `KEYFRAME_INDEX.md` `## Errata`.
- **Always** quote `"$HOME/Videos/clip_1,795,033,698,901.mp4"`.
- **Always** check `du -sh docs/reference/clip_1795033698901` (`<= 25 MiB`) and `git diff -- game/src/missions/mission_controller.gd` (must be empty).

---

## 8. `<promise>DONE</promise>` Acceptance Gate

Only declare completion when ALL of these exit `0` on the final cleaned tree:
- [ ] `/usr/bin/python3 docs/reference/clip_1795033698901/tools/verify_baseline.py` → all 8 checks `[PASS]`, exit `0`
- [ ] `/usr/bin/python3 docs/reference/clip_1795033698901/tools/render_annotations.py --check` → `30/30 OK`, exit `0`
- [ ] `bash -n docs/reference/clip_1795033698901/tools/make_side_by_side.sh` → exit `0` (if created)
- [ ] `grep -c '^## S' docs/reference/clip_1795033698901/BREAKDOWN.md` → `27`
- [ ] `du -sh docs/reference/clip_1795033698901` → `<= 25M`
- [ ] `docs/reference/clip_1795033698901/_carryover/` does not exist
- [ ] `git diff --stat -- game tools build extracted` → completely empty (your `mission_controller.gd` at `6d6b4ba` untouched)
- [ ] `docs/REFERENCE_BASELINE.md` `## Verification log` contains `>= 12` adversarial spot checks, `>= 6` image re-opens, and `>= 8` citation re-opens.
