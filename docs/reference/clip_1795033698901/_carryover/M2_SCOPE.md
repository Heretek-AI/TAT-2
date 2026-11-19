# Scope: Milestone 2 — Deterministic Annotated Keyframes & Callout Legends

## Architecture
- Input: `docs/reference/clip_1795033698901/clean/KF01..KF30` (`1920x1080` RGB JPEGs) + `docs/reference/clip_1795033698901/KEYFRAME_INDEX.md`.
- Output 1: `docs/reference/clip_1795033698901/annotated/KF01..KF30` (30 `1920x1080` RGB JPEGs, `quality=90`, `<750 KB` each, filenames identical to `clean/`).
- Output 2: `docs/reference/clip_1795033698901/CALLOUT_LEGENDS.md` (30 numbered legend tables matching badges `[1]..[N]` 1:1).
- Total footprint of `docs/reference/clip_1795033698901/` MUST remain `<= 25 MiB`.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---|---|---|---|
| 5 | Deterministic Keyframe Annotation (`annotated/KFxx_*.jpg`) | Programmatically render color-coded numbered circular badges (`#FFB300` Visual `V*`, `#00E5FF` HUD/UI `UI*`, `#FF4081` Gameplay/Audio `G*`/`AU*`), `2.5px` leader lines with `1px` black casing + arrowhead/6px dot on `(tx, ty)`, optional dashed bounding boxes, and compact short labels (`<= 4` words, dark semi-transparent pill) on all 30 keyframes via `/usr/bin/python3` + Pillow `13.0.0`, visually verified for zero overlap and zero HUD occlusion. | M2 | `PROJECT.md` |
| 6 | Callout Legend Spec (`CALLOUT_LEGENDS.md`) | Numbered per-keyframe legend tables (`| # | Category | Code | Label | Target (x, y) | Observed UE5 Detail |`) matching badge IDs `[1]..[N]` on each `annotated/KFxx_*.jpg` 1:1, grounded strictly in `KEYFRAME_INDEX.md` and directly visible pixels. | M2 | `PROJECT.md` |
| 10 | Output Hygiene & Repository Integrity | Only `annotated/*.jpg` and `CALLOUT_LEGENDS.md` written in repo; zero modifications to `clean/`, `KEYFRAME_INDEX.md`, `game/`, `tools/`, `build/`, `extracted/`, or `game/src/missions/mission_controller.gd`; zero leftover `/tmp` staging files. | M2 | `PROJECT.md` |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| M2 | Deterministic Annotated Keyframes & Callout Legends | `KF01–KF30` pixel coordinate spec, Pillow rendering, visual inspection of all 30 annotated frames, `CALLOUT_LEGENDS.md`, verification wave & gate | M1 | IN_PROGRESS |

## Interface Contracts
- **Annotation Color & Code Contract**:
  - `Amber #FFB300`: Visual / Lighting / Material / Shader / VFX (`V1–V7` / `V*`)
  - `Cyan #00E5FF`: HUD / UI / Prompts (`UI1–UI5` / `UI*`)
  - `Magenta #FF4081`: Gameplay Interaction / AI / Audio-linked Cue (`G1–G5` / `AU1–AU6` / `G*` / `AU*`)
- **Badge & Label Contract**:
  - Circular badge `28px` diameter, bold white sans-serif numeral `1, 2, 3...`, `2px` dark outer stroke.
  - `2.5px` solid colored leader line with `1px` black casing terminating in clear arrowhead or `6px` dot at `(tx, ty)`.
  - Optional thin dashed bounding box for grouped UI/HUD regions or portals/barriers.
  - Compact label `<= 4` words next to badge on high-contrast dark semi-transparent pill, placed in uncluttered margins; must not obscure target feature, overlap other labels/boxes, cover HUD elements, or clip past `1920x1080` borders.
- **Legend Contract**:
  - `CALLOUT_LEGENDS.md` tables (`| # | Category | Code | Label | Target (x, y) | Observed UE5 Detail |`) match `[1]..[N]` 1:1 per keyframe.
