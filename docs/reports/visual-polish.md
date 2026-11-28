# Visual-Polish Wave (2026-11-18)

- **Date**: 2026-11-18
- **Repo / Branch**: `<repo>` (`main`)
- **Engine / Renderer**: Godot `4.7.2.stable.flathub` — Forward+ / Jolt
- **Live Vulkan QA Hardware**: `Vulkan 1.4.357 - Forward+ - NVIDIA GeForce RTX 4070 Laptop GPU` (via `Xvfb :99`, `1280x720`)
- **Verification**:
  - `make test` (headless, 38 numbered suites): `SUMMARY: fails=0`, `SCRIPT ERROR = 0`, exit 0.
  - `make audit`: `Manifest TAT entries: 12704`, `Resolved in CUE4Parse: 12630 (99.4%)`, `Files written to extracted: 29939` (+155 from 29,784).
  - Live Vulkan Forward+ captures: `bash build/qa/capture_vf.sh` and `bash build/qa/capture_mp_only.sh`, `SHADER ERROR = 0`, `SCRIPT ERROR = 0`.

---

## P1 — Map table tokens to UE reference framing (`3448f82`)

- **Root cause**: `SM_MapBuilding_OldManor` / `SM_MapBuilding_GuildHall` miniature tokens in `game/src/missions/mission_controller.gd` were scaled at `0.08`, smaller than the UE reference framing (`~0.22–0.25` per `Screenshot_20261118_002339.png` / `Screenshot_20261118_002348.png`).
- **Fix**: tokens `0.08 -> 0.24` (uniform scale) in `mission_controller.gd`; seated Y and authored `M_MapBuilding_*` materials unchanged.
- **Tests**: suite `34d` asserts uniform scale `0.24`, seated Y, and authored materials.
- **Commit**: `3448f82 feat(den): scale map table tokens to UE reference framing`.
- **Live evidence**: `build/qa/vf_map_tokens_024.png` (verified present, `1280x720`) shows both miniatures as distinct buildings on the map at `0.24`; previous 0.08 frame is `build/qa/vf_thieves_den_map_table.png`.
- **Residual risk**: none noted beyond framing judgement; token scale is a visual match, not a parsed UE value.

## P2 — Authored HDR neon tints through an unshaded HDR pass (`63ea64c`)

- **Root cause**: untextured HDR neon tints (`MI_Neon`, `MI_Neon_MacNeish`) rendered as saturated red blobs under the lit PBR path instead of UE's thin orange-gold tubes.
- **Fix**: new `game/src/core/tat_hdr_emissive.gdshader`; `level_loader.get_material_for_ue()` returns a cached `ShaderMaterial` for untextured HDR tints:
  - `MI_Neon` = `50 / 4.109 / 0.521`, `MI_Neon_MacNeish` = `1.5 / 0.055 / 1.234`.
  - `hdr_scale = clampf(4.0 / peak, 0.02, 1.0)` (peak = max linear channel).
- **Tests**: suite `37` asserts exact vectors, `0.08` / `1.0` scales, cache identity, `SM_NeonB` binding, and negative controls (`MI_JeweledKnife`, `MI_CatStatueA`, `MI_LightBeam_SM` stay `StandardMaterial3D`).
- **Commit**: `63ea64c fix(materials): render authored HDR neon tints through an unshaded HDR pass`.
- **Live evidence**: after — arches are thin tubes with quantized colours `(255,183,101)` / `(255,157,84)` (retained `build/qa/vf_startscreen.png`); before — saturated red blobs `sRGB (254,78,77)` / `(254,57,67)` measured at the time in the discarded run, artifact not retained.
- **Residual risk**: neon core is slightly more saturated than UE's pale gold; Startscreen ambient/exposure still differs from the reference (see Limits).

### Discarded first attempt

- An earlier `StandardMaterial3D`-emission approach with HDR `Color` for the same tints was discarded before commit and no failed-run artifact was retained; the retained `build/qa/vf_startscreen.png` verifies only the final unshaded `tat_hdr_emissive.gdshader` pass.

## P3 — Authored ThiefNisha PBR on Mission Prep preview (`1912d04`)

- **Root cause**: the Mission Prep 3D preview stage bound the default untextured GLB surface, rendering ThiefNisha as a white silhouette instead of the authored character.
- **Fix**: `mission_prep_ui.gd` lazily creates one `LevelLoader` material resolver, maps each GLB to its UE key, and binds `mesh_materials.json` slots per surface.
- **Tests**: suite `35c` asserts body/head albedo textures and the head glass `ShaderMaterial`.
- **Commit**: `1912d04 feat(ui): bind authored ThiefNisha PBR materials on Mission Prep preview`.
- **Live evidence**: `build/qa/vf_mission_prep.png` now shows the authored blue top / dark trousers / skin / hair instead of a white silhouette.
- **Residual risk / cost**: preview-stage binding only, no gameplay material change. Each `MissionPrepUI` instance lazily parses `materials.json` + `mesh_materials.json` once (a synchronous JSON parse, not separately timed). The desktop preview loads ~28 unique lossless character textures (≈640 MiB transient VRAM at authored resolution); mobile is mitigated by `tools/prepare_mobile_project.py` (ETC2/compressed, 1024 cap). Acceptable for the desktop target; a shared material-DB cache or skipping normal/ORM for the preview would cut this if it matters later.

## P4 — OldManor_P landscape heightmaps + weightmaps (`24abf18`)

- **Root cause**: the `.umap` textures predicate did not match the exact `OldManor_P` basename, so its landscape PNGs were never exported and `_build_one_landscape()` hit its missing-heightmap guard (components not built at all).
- **Fix**: exact `OldManor_P` basename in the `.umap` textures predicate in `tools/tat-extract/Exporter.cs`.
- **Counts**: `155` PNGs written (`101` heightmaps + `54` weightmaps; `135` weightmap references, `7` components with two weightmaps).
- **Tests**: suite `38` asserts `128` components / `101` / `54` / `0` missing and a real `_build_one_landscape()` build.
- **Commit**: `24abf18 feat(extract): export OldManor_P landscape heightmaps and weightmaps`.
- **Live evidence**: Old Manor landscape builds (one component exercised by suite 38; all 128 heightmap paths present); `build/qa/vf_old_manor.png` renders cleanly. Terrain walk/collision was not verified.
- **Residual risk**: landscape splines/grass remain runtime-unparsed (see Limits).

---

## Reproduce

```bash
make test     # 38 numbered suites, SUMMARY: fails=0, zero SCRIPT ERROR
make audit    # 12704 entries, 12630 resolved (99.4%), files written 29939

# Live Vulkan Forward+ captures (Xvfb :99, 1280x720)
bash build/qa/capture_vf.sh        # SHADER ERROR = 0, SCRIPT ERROR = 0
bash build/qa/capture_mp_only.sh   # mission-prep capture -> build/qa/vf_mission_prep.png
```

## Remaining limits (not fixed this wave)

- Startscreen residual: ambient/exposure still differs from the UE reference.
- Neon core slightly more saturated than UE's pale gold.
- Landscape splines/grass data remains unparsed at runtime.
- Niagara VFX remains blocked on compiled VectorVM bytecode (120/120 systems); Wwise IR/join, material graphs, BP/patrol, doors, and periphery limits per `docs/FIDELITY_GAPS.md`.
