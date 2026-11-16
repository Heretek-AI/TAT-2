# Level Runtime Wiring — Implementation Report

Stage: consume the extracted level-component arrays in the runtime with strict
data validation (no wrong-texture decals, no fabricated lights).
Date: 2026-11-16. Worktree scope: `game/src/core/level_loader.gd`,
`game/src/missions/mission_controller.gd`, `docs/reports/level-runtime.md`.

## What was wired

`game/src/core/level_loader.gd`
- `_new_accumulator` / `_new_build_ctx` / `_finalize`: new accumulator arrays
  (`decals`, `rect_lights`, `volumes`, `sky_lights`, `fog_volumes`,
  `post_process`, `niagara`, `splines`) and new result stats
  (`decal_count`, `decal_skipped`, `decal_unresolved_material`,
  `rect_light_count`, `rect_light_skipped`, `blocking_volume_count`,
  `volume_skipped`, `niagara_placements`, `spline_count`, plus
  `sky_light` / `fog_volume` / `post_process` first-present entries).
- `_parse_sublevel_file`: collects the eight new arrays verbatim; mesh/light/
  marker/landscape parsing untouched.
- `_is_decal_material_usable` (strict validation): a decal material is usable
  only if the `materials.json` albedo stem shares a meaningful token
  (len>=4, not in {m, mi, t, d, da, a, inst, decal, decals}) with the material
  basename — tokens split on non-alphanumerics AND camelCase humps, matched
  exact or substring either direction. The only exception is an explicitly
  authored `tint` colour (max channel >= 0.05), which yields a texture-less
  flat-colour decal (the MagicSlime-puddle rule). Everything else is skipped
  and counted as `decal_unresolved_material`; substitute art is never bound.
- `_build_decals`: Godot `Decal` nodes for validated materials only, cap 256
  per map. Size: authored `size` when present (only 2 of 667 entries have
  one), else component scale x UE default decal box (1 m per axis, documented
  assumption). UE->Godot axis mapping: authored UE size is (X=depth, Y=width,
  Z=height); Godot size is (X=width, Y=depth, Z=height), so Y/X are swapped.
  Orientation: UE decals project along local +X (DecalActor arrow axis);
  Godot projects along local -Y, so the basis is post-rotated +90° about Z
  (maps -Y onto +X). `distance_fade_enabled` with begin 45 m / length 15 m
  (end 60 m). Albedo (+normal when present) bound from the validated entry;
  `modulate` from `tint` when authored.
- `_build_rect_lights`: entries with `intensity <= 0.01` skipped (authored
  off, animated at runtime). Active ones claim light-budget slots FIRST (they
  are rare and authored area lights), then standard lights fill the remainder;
  both paths cap the total at `max_lights`. Each active rect becomes an
  `OmniLight3D` (range = `radius` m x2.2 clamped [5, 20], colour 0-255 -> 0-1,
  energy = same UE-unit convention as `_build_light`: raw<20 -> x0.95 else
  x0.08, clamped [1, 4.2]; shadows off — an omni shadow would shade the wrong
  hemisphere for an area light) plus an unshaded/emissive `QuadMesh` sized
  `width x height` (raw UU centimetres x0.01, clamped [0.1, 30] m),
  double-sided because the UE emission axis is not recorded. Registered with
  the light probe and folded into `light_count`.
- `_build_volumes`: class containing "blocking"/"block" (case-insensitive)
  becomes a `StaticBody3D` (layer 1, mask 0) with a `BoxShape3D` of
  `extent*2` at `pos` (extent is already a half-extent in metres), so designer
  blocking volumes actually block. Built regardless of the mesh-collision
  flag — they are gameplay-critical, not mesh dressing. NavMesh/NavModifier/
  Trigger/Tutorial volumes are skipped and counted. Volumes increment
  `collision_bodies`/`collision_shapes` honestly.
- `_store_level_extras`: niagara placements and spline counts recorded;
  landscape splines always skipped (mesh is the editor-only
  `SplineEditorMesh` and/or material is empty — not usable, counted not
  hidden). First sky/fog/post-process entries forwarded for the mission
  controller. Niagara is NOT spawned in this wave (count only, for the VFX
  wave).

`game/src/missions/mission_controller.gd`
- After loading, `_apply_level_atmosphere(stats)` applies the forwarded
  entries when present and meaningful, most-specific-last (fallback ->
  weather preset -> mobile overrides ordering untouched):
  sky light (intensity > 0) -> `AMBIENT_SOURCE_COLOR`, colour (0-255 or 0-1
  auto-detected), energy = intensity x0.2 clamped [0.02, 1.0];
  fog (density > 0) -> `fog_enabled`, density x0.01 (same UE->Godot scale as
  `weather_profile`), inscattering colour;
  post-process -> only Godot-supported fields (`BloomIntensity` -> glow x0.08,
  `Saturation` -> adjustment saturation). Lumen/UE-only fields
  (`LumenSkylightLeaking`, `LumenFullSkylightLeakingDistance`,
  `LocalExposure*`, …) are logged as unmappable, environment unchanged.

## Spawn/skip counts per mission map

Loader-level numbers (temporary SceneTree check through `load_sublevels`,
`generate_collision=false`, budget 96; meshes/chunks unaffected by the new
nodes apart from the additions below):

| Map | Decals spawned / skipped | Rect on / off | Blocking vol / skipped vol | Niagara | Splines |
|---|---|---|---|---|---|
| OldManor (7 files) | 203 / 89 | 0 / 10 | 36 / 0 | 1809 | 0 |
| Guildhall (11 files) | 135 / 23 | 1 / 16 | 102 / 16 (15 NavModifier + 1 NavMeshBounds) | 1694 | 2 (skipped, counted) |
| ThievesDen (3 files) | 9 / 0 | 0 / 0 | 0 / 0 | 21 | 0 |

- OldManor skipped (89): `M_Decal_Puddle` 44 (cooked graph, generic
  `T_DecalPostersA_DA` fallback), `MI_DecalPaperA` 37 (placeholder swap to
  `T_GroundStoneA_D`), `MI_RustDrip` 8 (no shared token with
  `T_GroundDirtA_D`). Spawned: all `MI_DirtDecal*` via "dirt",
  `MI_DecalGrime` via "grime", `MI_Decal_Moss` via "moss",
  `*_Light` variants via "light", plus 1 `M_Decal_Posters_A` via the explicit
  tint exception (flat crate-brown, texture-less — no wrong art bound).
- Guildhall skipped (23): `M_Decal_Puddle` 20, `M_Puddle_Inst`/`M_Puddle_Inst2`
  (no albedo at all), `MI_DecalOddfellow` 1 (`T_MixedAds_D` shares no token —
  cooked-graph limitation, documented). Spawned includes `MI_Dragmarks`
  ("dragmarks"), posters/paper-scraps/moss-light/mundiad via shared tokens.
- Guildhall active rect (1): `BP_SignKelvin` PeripheryA, intensity 5.0, red
  [255,25,63] -> energy 4.2, range 11 m, 9 m x 0.1 m emissive quad. All other
  26 mission-map rects are 0.0/0.001 (authored off).
- Sky/fog: the single `sky_lights`/`fog_volumes` entries live in
  `BeautifulCorner_Startscreen_Lighting` (MainMenu, loaded by no mission map),
  so `_apply_level_atmosphere` is a no-op for all four mission maps except the
  ThievesDen post-process log line below.
- ThievesDen post-process (`ThievesDenTest_P` PostProcessVolume_1): settings
  are `LumenSkylightLeaking`, `LumenFullSkylightLeakingDistance`,
  `LocalExposureHighlightContrastScale`, `LocalExposureShadowContrastScale`,
  `LocalExposureMiddleGreyBias` — all Lumen/UE-only, unmappable in Godot;
  logged, environment unchanged (visible in `make test` output as the
  `TAT-2 post_process 'PostProcessVolume_1' ...` line).
- Contract sublevel files add nothing except one Niagara placement in
  `OldManor_Contract10` (counted when that contract loads).

## Conversions (documented in code)

- UU->m x0.01 for positions (extractor), radii already metres, rect
  width/height raw UU centimetres x0.01 (only radius is stored converted).
- UE decal +X projection -> Godot -Y via Basis(Vector3.FORWARD, PI/2).
- Rect energy: raw<20 -> x0.95 else x0.08, clamp [1,4.2] (same as
  `_build_light`); colour /255; sky ambient energy = intensity x0.2;
  fog density x0.01; bloom x0.08 (same as `weather_profile`).

## The material-graph hard limit

Cooked UE `Material` assets have no expression graph. Decal/VFX textures that
live only in the graph (e.g. `M_Decal_Puddle`) are NOT recoverable, and the
generic `T_DecalPostersA_DA` fallback must never stand in for them — the
token rule rejects exactly these (verified: no `Decal` node in any mission
map binds a `*decalpostersa_da*` texture). Skipped decals are counted
(`decal_unresolved_material`), never hidden.

## Verification

- Temporary `game/tests/_tmp_levelcomp_check.gd` (SceneTree, 21 asserts):
  validation unit probes (smokebomb pass / puddle, glyph, unknown reject /
  tint-colour pass), per-map decal accounting (spawned+skipped == JSON
  totals), decals > 0 for OldManor, blocking > 0 for OldManor (36),
  rect on/off == JSON (0/10, 1/16, 0/0), rect omni present in tree,
  niagara/spline counts == JSON, no fallback-poster texture on any Decal,
  ThievesDen pp entry exposed. Result: `SUMMARY: fails=0`, exit 0. File
  deleted afterwards (never touched `run_tests.gd`).
- `make test`: `SUMMARY: fails=0`, zero `SCRIPT ERROR` (see Commands).
- Perf spot numbers from the loader-level check (collision off, so shapes
  only from blocking volumes): OldManor meshes=7143 chunks=2619,
  Guildhall meshes=16229 chunks=4703, ThievesDen meshes=286 chunks=169.
  Chunking/occluder invariants are asserted by `run_tests.gd` step 11 and
  still pass — the new nodes add no chunks and only real blocking boxes.

## Needs a visual (headless cannot check)

- Decal projection orientation (+X assumption) and Y/X size-axis swap on real
  walls/floors; dirt/moss/grime read at 45-60 m fade.
- The Kelvin-sign red glow quad (9 m strip, double-sided) sitting correctly
  on the sign face in Guildhall PeripheryA.
- Blocking volumes matching designer intent (no invisible walls in doorways).
- `M_Decal_Posters_A` flat-tint decal (1, OldManor) — confirm it reads as
  crate grime, else force-skip that material.

## Commands

- `flatpak run org.godotengine.Godot --headless --path game --script res://tests/_tmp_levelcomp_check.gd` -> exit 0, `SUMMARY: fails=0`, no SCRIPT ERROR (temp file, since deleted)
- `make test` -> exit 0, `SUMMARY: fails=0`, `grep -c "SCRIPT ERROR"` -> 0

## Self-audit

- Touched only `game/src/core/level_loader.gd`,
  `game/src/missions/mission_controller.gd`, the temp check (deleted), and
  this report. Parsers, extractor C#, Makefile, Android files,
  `thief_character.gd`, `guard_ai.gd`, interact scripts, `run_tests.gd`
  untouched. (Pre-existing worktree changes to `guard_ai.gd` /
  `_tmp_guard_anim.gd` / `animation_library.gd` belong to another stage and
  were not staged or committed here.)
- No stubs/TODOs; unresolved materials counted, never guessed; no fabricated
  lights (off rects skipped, active ones converted 1:1 from extracted values).
- One wart: `_is_decal_material_usable` also consults `info["tint"]` for the
  colour exception, so `M_Decal_Posters_A` spawns texture-less on tint alone —
  honest per the stated rule, flagged above for visual review.
