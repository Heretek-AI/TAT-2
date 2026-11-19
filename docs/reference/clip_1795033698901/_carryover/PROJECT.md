# Project: TAT-2 Official Gameplay Clip Visual & Audio Reference Baseline

## Architecture
- **Source Video**: `/home/john/Videos/clip_1,795,033,698,901.mp4` (`225.642333 s` / `03:45.64`, `3840x2160` H.264 High ~29.672 fps, 6,696 frames, 48 kHz stereo AAC, `-43.9 LUFS`).
- **Repository Target**: Tracked deliverables strictly under `/home/john/Projects/TAT-2/docs/`:
  - `docs/REFERENCE_BASELINE.md` — Master index, methodology, TAT-2 subsystem (`#1–#18`), parity gap (`PG-1..PG-8`), and hard-limit (`HL-1..HL-9`) cross-reference matrices, plus the repeatable 4-pillar (`V1–V7`, `AU1–AU6`, `UI1–UI5`, `G1–G5`) 1:1 comparison checklist.
  - `docs/reference/clip_1795033698901/BREAKDOWN.md` — Continuous `00:00.00–03:45.64` timestamped visual + audio breakdown, embedded clean/annotated pairs, numbered callout legends, and inline TAT-2 subsystem/gap cross-references.
  - `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` — Canonical segment timeline & keyframe catalog (`00:00.00–03:45.64`), resolving all exact timestamps, verbatim UI text, and dialogue/audio events.
  - `docs/reference/clip_1795033698901/CALLOUT_LEGENDS.md` — Deterministic callout coordinate spec and numbered legend tables for every annotated keyframe.
  - `docs/reference/clip_1795033698901/clean/KFxx_*.jpg` — Clean `1920x1080` JPEGs (`quality=90`, `<750 KB` each).
  - `docs/reference/clip_1795033698901/annotated/KFxx_*.jpg` — Annotated `1920x1080` JPEGs (`quality=90`) with color-coded numeric badges (`Amber #FFB300` Visual/Shader/VFX, `Cyan #00E5FF` HUD/UI, `Magenta #FF4081` Gameplay/AI/Audio), leader lines, and compact short tags.
- **Tooling Note**: Use `/usr/bin/python3` (`Python 3.15.2`, `Pillow 13.0.0`, `matplotlib 3.11.1`, `numpy 2.5.4`), `/usr/bin/ffmpeg`, `/usr/bin/ffprobe`, and `/usr/bin/magick` (`ImageMagick 7.1.2-35`). Never use bare `python3` (resolves to `linuxbrew` without `PIL`).
- **Output Hygiene**: Leave `game/`, `tools/`, `build/`, `extracted/`, `game/.godot/`, `game/data/generated/`, and the pre-existing uncommitted `game/src/missions/mission_controller.gd` (`--env-strip=0-8`) completely untouched. Stage any temporary `/tmp` video/audio slices in a dedicated `mktemp -d` directory and remove it before completion.

## Feature Inventory
Every Survey feature assigned a milestone (none unassigned):
| # | Feature | Description | Milestone | Source |
|---|---|---|---|---|
| 1 | Continuous Timeline Segmentation (`00:00–03:45.64`) | Dense frame & audio inspection resolving exact boundaries across all 8 Acts / 17+ segments (Startscreen, Loading 1, Thieves' Den + Wardrobe/Telescope/Wanted/Ledger/Black Market/Decorations/Gramophone/Map Table, Mission Prep + 6s countdown, Loading 2, Briefing Note, Constables' Guildhall infiltration, Pause Menu) with zero unexplained gaps | M1 (catalog), M3 (full prose) | survey_1 §1.4, survey_3 §1.2 |
| 2 | Verbatim UI Text & Dialogue Resolution | Resolve all exact on-screen strings & audio quotes from 4K frames/audio (e.g., `ARRON'S` vs `SIMON'S DEMOLITION`, `1.5.148559` vs `1.5.146159`, `15` vs `55` min timer, exact ThiefNisha & guard VO lines, exact Wardrobe/Journal/Black Market/Briefing text) | M1 | survey_1 vs survey_3 cross-check |
| 3 | Clean Keyframe Extraction (`KF01–KF28` `1920x1080` JPG) | Extract 25–30 clean `1920x1080` JPEGs (`quality=90`, `<750 KB` each) covering every act, UI overlay, lighting condition, VFX, tool, and AI/trap event | M1 | survey_1 §4.2, survey_3 §3.1 |
| 4 | Audio Layer Profiling (SFX, VO, UI, Ambience, Music/Absences) | Document exact timestamps for rain/wind/room tone, surface-specific footsteps, UI clicks/countdown ticks, Gramophone 1920s jazz (`00:44–00:50`), car horn, ZipWire/Smoke/Diamond/Takedown/Barrier SFX, VO, and explicit absence of BGM in Startscreen, pre-gramophone Den, Loading, and Guildhall stealth | M1 (cue timestamps), M3 (full narrative) | survey_1 §1.2/1.4, survey_3 §1.2 |
| 5 | Deterministic Keyframe Annotation (`annotated/KFxx_*.jpg`) | Programmatically render color-coded numbered circular badges (`#FFB300` Visual, `#00E5FF` HUD/UI, `#FF4081` Gameplay/Audio), leader lines, optional dashed regions, and compact short labels (`<=4` words) on all keyframes via `/usr/bin/python3` + Pillow, visually verified for zero overlap | M2 | survey_3 §3.3, survey_1 §4.2 |
| 6 | Callout Legend Spec (`CALLOUT_LEGENDS.md`) | Numbered per-keyframe legend tables matching badge IDs `[1]..[N]` on each `annotated/KFxx_*.jpg` | M2 | survey_3 §3.3 |
| 7 | TAT-2 Subsystem Inventory & Cross-References (`#1–#18`) | Cross-reference observed footage elements against all 18 TAT-2 port subsystems grounded in `docs/HANDOFF_NEXT_SESSION.md`, `docs/FIDELITY_GAPS.md`, `docs/ARCHITECTURE.md`, and `docs/reports/*.md` | M3 | survey_2 §1.2 |
| 8 | Hard Limits (`HL-1..HL-9`) & Parity Gaps (`PG-1..PG-8`) Mapping | Tag every observed UE5 feature with parity status (`1:1_MATCH`, `APPROX_SHADER`, `KNOWN_GAP (PG-*)`, `HARD_LIMIT (HL-*)`, `UNVERIFIED_LIVE`, `NOT_IMPLEMENTED`), explicitly separating cooked limits (Niagara VM, material graphs, BP/patrol splines, 1P idle/blendspaces, PLUG IRs, Lumen GI) from open port gaps (AudioManager missing BGM/UI/surface footsteps `PG-6`, `S03/S04/S06/S11/S14/S15b` `PG-2`, etc.) | M3 | survey_2 §1.3 |
| 9 | Repeatable 1:1 Port Comparison Framework (`V1–V7`, `AU1–AU6`, `UI1–UI5`, `G1–G5`) | Standardized 4-pillar scoring rubric (`PASS | DELTA | MISSING | HARD_LIMIT`), comparison instructions for `1280x720` / `1920x1080` Godot captures, and per-segment checklist tables | M3 | survey_3 §3.2, survey_2 §4.1 |
| 10 | Output Hygiene & Repository Integrity | All outputs strictly under `docs/`, total reference image footprint `<=25 MiB`, zero changes to `game/`, `build/`, `game/.godot/`, `game/data/generated/`, pre-existing `game/src/missions/mission_controller.gd` preserved untouched, zero leftover `/tmp` files | M1, M2, M3 | survey_1 §1.6, survey_3 §3.1 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| 1 | Dense Timeline Analysis & Clean Keyframe Extraction | Resolve sub-second timeline (`00:00.00–03:45.64`), exact verbatim UI/VO text, audio cue timings & absences; extract 25–30 clean `1920x1080` JPGs under `docs/reference/clip_1795033698901/clean/`; author `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md` | none | DONE (`30` clean JPGs `5.90 MiB`, `27` segments, `64` audio rows — M1 Iteration 4 PASS) |
| 2 | Deterministic Annotated Keyframes & Callout Legends | Inspect clean keyframes, specify pixel coordinates & color-coded callouts (`#FFB300` / `#00E5FF` / `#FF4081`), render `docs/reference/clip_1795033698901/annotated/KFxx_*.jpg` via `/usr/bin/python3` + Pillow, inspect every annotated image, author `docs/reference/clip_1795033698901/CALLOUT_LEGENDS.md` | M1 | IN_PROGRESS (`sub_orch_m2`: `58f0b97a-3b61-49f8-99db-2d5213eac763`) |
| 3 | Master Reference Baseline, Exhaustive Breakdown & TAT-2 Cross-Reference | Author `docs/REFERENCE_BASELINE.md` and `docs/reference/clip_1795033698901/BREAKDOWN.md` uniting continuous `00:00.00–03:45.64` visual+audio descriptions, paired clean/annotated images + legends, TAT-2 subsystem/gap/hard-limit cross-references (`HANDOFF_NEXT_SESSION.md` + `FIDELITY_GAPS.md` + `docs/reports/*.md`), and 4-pillar 1:1 comparison checklist; run full cross-deliverable verification | M1, M2 | PLANNED |

## Interface Contracts
### M1 (`KEYFRAME_INDEX.md` + `clean/`) ↔ M2 (`CALLOUT_LEGENDS.md` + `annotated/`)
- **Keyframe Filename Convention**: `KF<01..NN>_<MM>m<SS>s_<slug>.jpg` (`1920x1080`, JPEG `quality=90`, `<750 KB` per file). Both `clean/` and `annotated/` MUST use identical filenames.
- **`KEYFRAME_INDEX.md` Schema**:
  1. Clip metadata header (`ffprobe` verified).
  2. Complete continuous segment table (`SegID`, `Start`, `End`, `Duration`, `Scene/UI State`, `Visual Summary`, `Audio Summary & Explicit Absences`, `Linked Keyframes`).
  3. Keyframe extraction table (`KF_ID`, `Timestamp_Exact`, `Segment`, `Filename`, `Resolution`, `Size_KB`, `Verified_OnScreen_Text`, `Key_Observed_Elements`).
  4. Exact audio/VO transcription table (`Timestamp`, `Layer`, `Verbatim_Quote_or_Cue`, `Notes`).

### M1 + M2 ↔ M3 (`REFERENCE_BASELINE.md` + `BREAKDOWN.md`)
- **Annotation Color & Legend Contract**:
  - `Amber #FFB300`: Visual / Lighting / Material / Shader / VFX (`V1–V7`)
  - `Cyan #00E5FF`: HUD / UI / Prompts (`UI1–UI5`)
  - `Magenta #FF4081`: Gameplay Interaction / AI / Audio-linked Cue (`G1–G5` / `AU1–AU6`)
  - Every `[1]..[N]` badge rendered on `annotated/KFxx_*.jpg` MUST match row `1..N` in `CALLOUT_LEGENDS.md` and in `BREAKDOWN.md`.
- **Cross-Reference Tagging Contract**:
  - Subsystems `#1–#18`, Hard Limits `HL-1..HL-9`, Parity Gaps `PG-1..PG-8` with exact repo file/section/line citations from `docs/HANDOFF_NEXT_SESSION.md`, `docs/FIDELITY_GAPS.md`, `docs/ARCHITECTURE.md`, `docs/PERFORMANCE.md`, `docs/ANDROID.md`, and `docs/reports/*.md`.
  - Parity status enum: `1:1_MATCH` | `APPROX_SHADER` | `KNOWN_GAP (PG-*)` | `HARD_LIMIT (HL-*)` | `UNVERIFIED_LIVE` | `NOT_IMPLEMENTED`.

### Repo Hygiene Contract (All Milestones)
- Writable paths in `/home/john/Projects/TAT-2`: ONLY `docs/REFERENCE_BASELINE.md` and `docs/reference/clip_1795033698901/**`.
- Pre-existing diff `game/src/missions/mission_controller.gd` MUST remain untouched.
- Total size of `docs/reference/clip_1795033698901/` MUST stay `<= 25 MiB`.
- All `/tmp` temporary artifacts MUST be inside agent-owned `mktemp -d` dirs and deleted before reporting.
