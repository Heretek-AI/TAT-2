# DeepSeek Engineering Handoff — TAT-2 (Thick As Thieves Godot 4.7 Port)

This document is a complete technical handoff for **DeepSeek** to optimize performance and finish visual/gameplay/UI refinement in `<repo>`.

> **Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full pipeline and module map.**

---

## 1. Environment & Verification Commands

- **Project Path**: `<repo>` (Godot project at `<repo>/game`)
- **Original Game**: `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/`
- **Engine**: Godot `4.7.2.stable.flathub` (`Forward+` renderer, `Jolt Physics`)
- **Commands**:
  - `make test` — Runs `res://tests/run_tests.gd` (15 headless integration/verification tests; must stay `SUMMARY: fails=0` with zero `SCRIPT ERROR`s).
  - `make audit` — Runs `tools/manifest_audit.py --min-coverage 0.90`.
  - `make normalize` — Re-runs `python3 tools/parse_tables.py` after editing extraction/parsing.
  - `make run` — Launches the game client (`flatpak run org.godotengine.Godot --path game`).

---

## 2. Critical Godot 4.7.2 Rules (Do Not Violate)

1. **NEVER use `:=` on untyped `Dictionary` or `Variant` values** (e.g., `var x := dict.get("k")` or `var x := arr[i]` fails to parse in Godot 4.7). Always use explicit types (`var x: String = str(dict.get("k", ""))`) or `=`.
2. **`Line2D` is `Node2D`, NOT `Control`**: Never set `mouse_filter` or `set_anchors_preset()` on `Line2D`.
3. **Case-sensitive Linux paths vs UE5 `/Game/...` casing**: Always use lowercase fallback maps (`_materials_db_lower`, `_mesh_mats_db_lower`) when resolving UE5 material/mesh paths.
4. **Never bind `T_MapBuilding_*` to glass**: `glasspanels` / `windowglass` materials must stay translucent glass without map-building textures.

---

## 3. Verified Performance Bottlenecks (Priority Order)

Even on an **NVIDIA GeForce RTX 4070 Laptop GPU**, large maps (`Guildhall`: `15,871` meshes, `96` lights; `OldManor`: `5,129` meshes, `96` lights) suffer severe frame-time drops due to these exact root causes:

### P1 — Un-cullable Map-Wide `MultiMeshInstance3D` Batches (`game/src/core/level_loader.gd`)
- **Root Cause**: `load_sublevels()` and `load_sublevels_async()` group every instance of a given `.glb` across the entire map into **one single `MultiMeshInstance3D`**. Because the resulting AABB spans the entire city (`200m+`), Godot's frustum culling can never cull it, and `visibility_range_end = 85.0` is only applied when `aabb_len < 1.5` (and even then checks the giant merged AABB center!).
- **Fix**:
  1. Partition `batches[mp]` into **spatial grid chunks** (e.g., `32m × 32m` XZ cells: `key = "%s|%d|%d" % [mp, floori(pos.x / 32.0), floori(pos.z / 32.0)]`) before creating `MultiMeshInstance3D`s.
  2. Set `visibility_range_end` per chunk by mesh size (e.g., `< 1.2m` props -> `45m`; `1.2m–4.0m` -> `95m`; structural/skybox -> `0` or `240m`), with `SHADOW_CASTING_SETTING_OFF` on small clutter/foliage/debris.
  3. Enable Godot **Occlusion Culling** (`rendering/occlusion_culling/use_occlusion_culling=true` in `game/project.godot`) and generate simple `OccluderInstance3D` boxes (`BoxOccluder3D`) for large structural building walls/floors (`aabb_len > 6.0` and opaque).

### P2 — Nanite LOD0 Polycounts in Extracted `.glb`s (`tools/tat-extract/Exporter.cs`)
- **Root Cause**: `Exporter.cs` exported meshes with `EMeshQuality.Highest` and `ENaniteMeshFormat.NaniteFirst`, producing ultra-dense Nanite/LOD0 meshes (`SM_LeafB2`, `SM_NewspaperNanite*`, etc.) with zero LODs.
- **Fix**:
  - In `level_loader.gd`, skip or aggressively cull `SM_Leaf*`, `SM_Newspaper*`, `SM_Grass*`, `SM_Pebble*` (`visibility_range_end = 22.0`, `cast_shadow = OFF`, `generate_collision = false`).
  - Optionally enable Godot mesh LOD generation on import or re-export foliage/clutter at `EMeshQuality.Lowest` / lowest LOD.

### P3 — Lighting & Shadow Cost (`game/src/core/level_loader.gd`, `game/src/stealth/light_probe.gd`)
- **Root Cause**: Up to `96` dynamic lights (`OmniLight3D`/`SpotLight3D`) + `4` shadow-casting lights + `attic_fill` / `moon_beam` are active simultaneously in Forward+ Clustered.
- **Fix**:
  - Set `distance_fade_enabled = true`, `distance_fade_begin = 28.0`, `distance_fade_length = 12.0` on non-hero `OmniLight3D`/`SpotLight3D` nodes.
  - Ensure `LightProbe` (`game/src/stealth/light_probe.gd`) only evaluates lights within `25m` of the player (spatial hash or squared-distance early-out) and throttles/caches light checks instead of scanning all 96 lights every frame.
  - Lower `shadow_bias` / `directional_shadow` & shadow atlas resolution defaults in `project.godot` if needed (`rendering/lights_and_shadows/positional_shadow/atlas_size=2048`).

### P4 — Per-Frame Physics & Scene-Tree Scans (`game/src/player/thief_character.gd`, `game/src/core/vfx_manager.gd`)
- **Root Cause**:
  - `_update_prop_highlight()` in `thief_character.gd` runs every `_physics_process` tick and calls `VfxManager.set_prop_highlight()`, which calls `target.find_children("*", "MeshInstance3D")` when toggling. Cache the mesh list per target or only run at `10 Hz` / when target changes.
  - `LevelCollision` puts `13,830` `CollisionShape3D` children onto a single `StaticBody3D` (`Guildhall`), causing huge single-body BVH rebuilds and slow physics queries. Split `LevelCollision` per spatial chunk (matching the `32m × 32m` grid) or skip colliders on `Guildhall_SkyboxGeo` / `PeripheryA` distant exterior props!
  - In `mission_controller.gd`, pass `generate_collision = false` for `*_SkyboxGeo.tatlevel.json` and `*_Periphery*.tatlevel.json` (skybox and distant background geometry never need physics colliders!).

---

## 4. Visual, UI & Gameplay Refinement Gaps

1. **Thieves' Den Visual Polish (`game/src/missions/mission_controller.gd`, `game/src/core/level_loader.gd`)**:
   - Verify rolltop desk (`SM_DeskModular` + `SM_DeskVariant_F1`), frosted leaded arched window (`SM_ThievesDen_Glass`), wallpaper tone, and `SM_MetalPipeModule*` materials in live `make run` visually match the Steam screenshots.
   - Ensure `WardrobeUI` 3D thief lighting & `MissionPrepUI` moonlit rooftop framing match the Art Nouveau aesthetic.
2. **Gameplay & AI Completeness (`game/src/player/thief_character.gd`, `game/src/ai/guard_ai.gd`)**:
   - Complete **The Moth** astral projection / Thief Vision nuances and **The Chameleon** disguise edge cases.
   - Polish **Zipwire** grapple physics (smooth winch pull, release momentum, and line-of-sight surface check), **Insult Fairy**, and **Guard AI** search/investigation/revival behavior.
   - Add an in-game FPS/frame-time counter (`F3` debug overlay in `hud.gd`) to verify target `60+ FPS` in `Guildhall` and `OldManor`.
3. **Sublevel Loading Stutter**:
   - Yield (`await get_tree().process_frame`) periodically inside `_build_landscape_terrain()` and collider creation in `load_sublevels_async()` so `LoadingScreen` progress bar animates smoothly without freezing the main thread.

---

## 5. Ready-to-Use Prompt for DeepSeek

```text
You are taking over optimization and final refinement of TAT-2 in `<repo>` (Godot 4.7.2, Forward+, Jolt Physics).
First read `HANDOFF_DEEPSEEK.md` and `docs/ARCHITECTURE.md` in full.

Your primary goals:
1. **Fix Performance (Target 60+ FPS in Guildhall & OldManor)**:
   - Implement 32m x 32m spatial chunking for `MultiMeshInstance3D` batches and `LevelCollision` bodies in `game/src/core/level_loader.gd` so Godot frustum culling actually works.
   - Disable collision generation for `*_SkyboxGeo.tatlevel.json` and distant `*_Periphery*.tatlevel.json` sublevels in `game/src/missions/mission_controller.gd` / `level_loader.gd`.
   - Apply tiered `visibility_range_end` culling, `SHADOW_CASTING_SETTING_OFF` on foliage/debris (`SM_Leaf*`, `SM_Newspaper*`, small props), and `distance_fade_enabled = true` on non-hero lights.
   - Enable occlusion culling (`BoxOccluder3D` on large opaque walls/buildings + `use_occlusion_culling=true`).
   - Add an `F3` FPS/draw-call/frametime overlay in `game/src/ui/hud.gd` and profile `OldManor` and `Guildhall`.
2. **Polish Gameplay, UI & Visuals**:
   - Yield frames inside `load_sublevels_async()` collider/terrain loops so `LoadingScreen` stays responsive.
   - Refine Zipwire grappling, Chameleon disguise, Moth Thief Vision/astral form, and Guard AI search/revival.
   - Respect all Godot 4.7 rules (NEVER use `:=` on untyped `Dictionary`/`Variant`; no `mouse_filter` on `Line2D`).
3. **Verify**:
   - Run `make test` (`SUMMARY: fails=0`, zero `SCRIPT ERROR`s) and `make audit` after every milestone.
```

---

## 6. Status — 2026-11-16 (DeepSeek pass)

Verification: `make test` → 15/15 PASS, `SUMMARY: fails=0`, zero `SCRIPT ERROR`s; `make audit` → 99.4% coverage (unchanged).

### Done

- **P1 chunking** — `level_loader.gd` now partitions every mesh path into 32 m XZ cells, emits one `MultiMeshInstance3D` (or a plain `MeshInstance3D` for single-instance cells) per chunk and sets an explicit tight `MultiMesh.custom_aabb`. Guildhall: 4,517 chunks, 2,030 MultiMeshes, max chunk span **95.2 m** (was map-wide).
- **P2 clutter** — `SM_Leaf*`/`SM_Newspaper*`/`SM_Grass*`/`SM_Pebble*`/foliage/debris culled at 22 m, shadows off, no colliders. Props < 1.2 m → 45 m + no shadows; < 4 m → 95 m.
- **P3 lights** — non-hero omni/spot lights fade 28 m → 40 m; `light_probe.gd` samples at ~12.5 Hz with a 25 m squared-distance early-out and per-position cache.
- **P4 physics/scans** — skybox/periphery sublevels generate no colliders; remaining colliders are bucketed per 32 m cell, 384 shapes per `StaticBody3D` (Guildhall: 68 bodies / 8,268 shapes, was 1 / 13,830). Prop highlight scan throttled to 10 Hz; `VfxManager.set_prop_highlight` caches the mesh list per target.
- **Occlusion culling** — `rendering/occlusion_culling/use_occlusion_culling=true`; opt-in `BoxOccluder3D` for 6–48 m wall/floor/roof/pillar meshes (max 768, Guildhall hits the cap).
- **Loading** — async path yields per sublevel, per landscape and every 64 draw items; collider/terrain loops no longer block. Cold Guildhall load: **53.3 s → 16.2 s**.
- **F3 overlay** — `hud.gd` `toggle_fps_overlay()` shows FPS, frame ms, draw calls, objects, primitives, node count, VRAM, player position and contract title (4 Hz).
- **Gameplay** — Moth astral projection now has a real 8 s TTL (invisible to guards, silent), Thief Vision silhouettes render through walls (x-ray overlay); Chameleon disguise is seen through by alerted/searching guards and once integrity < 35%; Zipwire validates its anchor surface (no floor/point-blank/downward anchors), winches up over 0.35 s and keeps release momentum; Insult Fairy taunts the nearest guard when no loot is in range; guard SEARCH fans out around the last known position and ally revival takes a sustained 1.6 s.
- **Material rule** — albedo paths containing `mapbuilding` are now rejected for all 3D materials (defends rule 4).

Measured before/after numbers, tuning knobs and caveats: `docs/PERFORMANCE.md`.

### Android (internal sideload)

Full game + touch UI + arm64 release APK: `make android-release` → `build/tat2-mobile-release.apk` (~914 MB, ETC2 @1024, `com.heretek.tat2`, signed with `~/.config/tat2/tat2-internal.jks`). Desktop stays Forward+/lossless; the mobile project is generated under `build/mobile_game/`. Touch controls, quality tiers, signing/backup and the emulator Vulkan caveat are documented in `docs/ANDROID.md`. Phone FPS/thermals still need a hardware pass.

### Still needs a human / GPU pass

- **Live FPS measurement** with the F3 overlay in Guildhall and Old Manor (`make run`). The 60+ FPS target is not yet verified on hardware; only load time, node counts and culling coverage are measured.
- **Visual check of occlusion culling** for popping/holes on Guildhall and Old Manor (occluder boxes are mesh-AABB approximations; doors/windows/arches/rails are excluded).
- **Thieves' Den art comparison** against the Steam screenshots (rolltop desk, frosted leaded arched window, wallpaper tone, pipe materials) — the material bindings resolve correctly, but no live visual comparison was made in this pass.
