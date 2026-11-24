# Review remediation wave (2026-11-23, fifth pass)

Screenshot/Steam-asset review of doors, gates, security beams, floating props,
broken floors and parkour, followed by a prioritized remediation wave.

- **Base:** `411b5f8`
- **Shipped:** `3ed80c0`, `4b9fa03`, `0e89d2c`, `e7fcb7d`, `1373bb9`, `a410adc`
- **Gates:** compile 58/0 · `run_tests` fails=0 (54 suites) · M2 fails=0 ·
  door-walk PASS · viewmodel PASS · Niagara PASS · **E2E 262/262**

## Why this wave

The review found that the remaining visual defects were loader/parser flags and
content placement, not missing assets. The asset audit confirmed 0 missing
textures, 0 missing mesh imports, 0 unresolved door materials, 287 door pivots /
373 leaves, and all door/gate materials present. Four systemic causes explained
most of the screenshots:

1. `MI_LightBeam_SM` is authored Additive + Unlit + translucent; the loader
   turned it into an opaque white lit material. 330 `SM_LightBeam` meshes
   (134 in Guildhall) rendered as solid white bars.
2. 21 materials carry `TwoSided` under `BasePropertyOverrides`; the parser read
   only the top-level field, so gates, fences, brass doors and vault panels
   vanished from one side.
3. 21 materials inherited the parent master's painterly `T_PaintStrokesD`
   instead of their own `_D` companion, flattening the gate frame and floor
   tile to brush strokes.
4. Invisible designer `TATBlockingVolume` bodies were untagged, so mantle,
   wall-climb and zipwire treated them as climbable geometry (102 in Guildhall).

## What changed

| Area | Change | Evidence |
|---|---|---|
| Security beams | Exact `mi_lightbeam_sm` branch returns `tat_beam.gdshader` with `beam_color (1.0, 0.93, 0.82, 0.55)`, `energy 1.7`; generic `BLEND_Additive` → alpha+add and textured `MSM_Unlit` → unshaded hardening | Suite 29b/29c; T2-04-C now accepts the intentional beam exception and keeps 3 `StandardMaterial3D` negative controls |
| Two-sided | Parser reads `BasePropertyOverrides.TwoSided`; inherited by children | 24 materials incl. `MI_TrimMetalC_Rusty`, `MI_TrimMetalA_brass`, `MI_TrimMetalSurfaceA`, `MI_TrimMetalA_brass_dark`; suite 28 assertion |
| Paint-stroke albedo | Child MI's matching `_D` companion beats the parent master; documented painterly allowlist (carpets, rugs, apple interior) | 15 materials recovered incl. `MI_BrickNewClean_XYZ` → `T_BrickNewClean_D`, `MI_FloorTileA_AlignXYZ` → `T_FloorTileA_D` |
| Mirrored leaves | Negative-determinant pivots duplicate each surface `BaseMaterial3D` with `CULL_DISABLED` (per-slot, not `material_override`) | 36 POI + 4 vault pivots; `swinging_door.gd::_build_leaf()` |
| WorldGrid doors | Fully-grid `SM_OldManor_Gate_FrontDoor` (4/4) and `SM_OldManor_Gallery_Door_Glass` (1/1) get referenced metal/glass; partial-grid `SM_Manor_Door_Single` and `SM_Store_Int_WallDoor_Closed_4x6` copy slot 0 | Headless probe: grid=0 on all four; WorldGrid elsewhere untouched |
| Blocking volumes | `_build_volumes()` tags `blocking_volume`; mantle wall/top probes, wall-climb and zipwire reject tagged hits. Bodies stay solid on layer 1 | New **T1-10-J**: tall blocker rejects climb, low blocker rejects mantle, real 4 m mantles / 5 m refuses / tall wall climbs, no soft-lock |
| FOV | Settings schema v2 migrates only the legacy `fov:75` to 54.54 once; explicit values (65, post-migration 75) untouched; capture pins 54.54 | Suite 54; `CAPTURE_FOV_PIN base_fov=54.54 cam_fov=54.54` |
| Loot grounding | `_ground_spawn_node()` raycasts the floor and rests the merged mesh AABB bottom 0.03 m above it; blanket `+0.5 m` removed | Headless Guildhall: 253 loot items, 0 floating, 0 sunk; 3 civilians grounded |
| Ornate gate fill | Unregistered shadowless warm omni `GuildhallOrnateGateFill` at `(80, 20, 18)`, `(1.0, 0.76, 0.52)`, energy 1.5, range 11 m | Not in `light_probe`; stealth weights unchanged |
| Sign letters | Per-instance surface-1 override: emission `(1.0, 0.62, 0.20)`, energy 0.10, no emission texture, `CULL_DISABLED`; shared/cached material untouched | `TAT-2 KF16 sign letters: node=… surface=1 emission=(1.0,0.62,0.2,1.0) energy=0.10` |
| Free play | `_bind_menu_env()` returns when detached (no autostart `SCRIPT ERROR`); `_on_extracted()` skips `record_contract_complete` **and** `add_currency` in free play; normal deploy clears pending state | T4-13 `no_contract_write=true no_currency_bank=true`; `--qa-free-play` clean |
| Free-play entry | Den map table button **FREE PLAY: GUILDHALL CLEANOUT [G]** / `G` → order 2, `guildhall`, `free_play=true`, `MissionPrepUI.open_prep(..., true)` → `Mission.Guildhall.LootTheRoom` | `build/qa/capture_freeplay.gd`; prep capture shows `CONSTABLES' GUILDHALL / Contract Inactive / Cleanout Heist / 55 minutes`; HUD `Mission: Steal 4,000 in loot value[0/4,000]`, `£ 0` |
| QA harnesses | `build/qa` capture/probe **sources** are now tracked (`gitignore` exceptions); captures stay ignored | `a410adc`; T1-22-D/E, T2-22, T4-22 now reproducible from a clone |

## Measured results

| Probe | Before | After |
|---|---|---|
| Guildhall KF16 FOV | 75 (saved) | 54.54 (pinned); gate/postbox ~1.5× larger |
| KF16 sign letter band luma | 47.0 (vs board 45.5) | letters gold/front-facing, emission 0.10; still low-contrast at 27 m |
| Startscreen ground ROI | SD 0.030 | SD 0.062 (cobbles/puddles) |
| Startscreen decal | masked/flat | ROI mean 0.281, gold coverage 29.4 %, G/R 0.507 |
| Den KF10 core p50 | 43.5 | 43.5 (material flags did not regress); hotspot 83.4, token 88.6 |
| Den KF02 / KF06 / KF09 | 10.3 / 8.2 / 30.5 | unchanged; zero clip |
| Guildhall loot | 763 items at `+0.5 m` | 253 items 0.03 m above floor, 0 floating / 0 sunk |
| Guildhall beams | opaque white | warm additive, `SHADER ERROR=0` |

## Residuals (documented, not fixed)

- **Guildhall POI graybox floors** — 1,637 `GB_Floor_2x2` at mismatched heights
  plus floating furniture. Content project, not a loader bug.
- **Sign legibility at 27 m** — letters are gold and front-facing at the authored
  lens; the capture distance keeps contrast low. A closer framing or a larger
  letter surface would change the reference composition.
- **White glass/emissive plates** and the mirrored `PICK LOCK` reflection — repro
  first; no guessed fix.
- **Den 43.5 vs UE 52.6** — Lumen/real-GI residual.
- **Free-play prep body text** clips at the card edge (minor UI polish).
- **7-texture RID warning** at probe exit; `TAT2_NO_DEN_PROBE=1` is the clean
  path. Not a script error.
- **`CivilianNPC`** still has no `CollisionShape3D`, so it drifts under gravity
  after spawn. Grounding fixes the spawn origin, not the missing body.
- **Shipped sliding gate** — capture-only closed leaves remain correct until a
  route crosses it.

## Reproduction

```bash
# Headless gates
tools/godot --headless --path game --script tools/check_scripts_compile.gd
tools/godot --headless --path game --script res://tests/run_tests.gd
tools/godot --headless --path game --script res://tests/test_m2_player.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd

# Serialized GPU captures (one Godot at a time; Xvfb, Vulkan)
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp -ac &
DISPLAY=:99 tools/godot --path game --rendering-driver vulkan \
  --script build/qa/capture_zipwire_hang.gd     # KF16/KF17 sign, door, gate, beam
DISPLAY=:99 tools/godot --path game --rendering-driver vulkan \
  --script build/qa/capture_ui.gd               # startscreen / prep / wardrobe
DISPLAY=:99 tools/godot --path game --rendering-driver vulkan \
  --script build/qa/capture_freeplay.gd         # free-play prep + HUD
DISPLAY=:99 TAT2_DEN_CAPTURE_DIR=/tmp/den \
  tools/godot --path game --rendering-driver vulkan \
  --script build/qa/denfix_capture.gd           # KF02/KF06/KF09/KF10
```

Captures land in `build/qa/` (ignored). Sources are tracked so the numbers above
can be reproduced.
