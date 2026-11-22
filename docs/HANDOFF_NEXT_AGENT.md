# Handoff — Thick As Thieves Godot 4.7.2 port (next run)

**Repo:** `/home/john/Projects/TAT-2`
**HEAD at handoff:** `ba020cf` — `feat(extract): dump TAT/Content/MaterialLibrary tables (C5 groundwork)`
**Working tree:** clean (`git status --short` empty)
**Godot:** `4.7.2.stable.flathub.ed1daf0bf` via Flatpak (`godot` is **not** on `$PATH`)
**Renderer:** Forward+ · Jolt Physics 60 Hz · 1280×720
**Steam reference:** `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/` (`1.5.193.148559`, UE 5.5+, Win64 Shipping)
**Platform scope:** Linux desktop `x86_64` only. Mobile is out of scope (issue #2).
**Standing user directive:** every item listed in this handoff is valid and should be pursued.

> There is **no swarm plugin** in this environment any more (it was removed). Do not look for `save_plan`, `declare_scope`, coder lanes, or `update_task_status`. Implement directly with `read`/`edit`/`write`/`shell`, verify with real commands, and commit. Git history is the record.
>
> **2026-11-21 update:** Track C (C1/C2/C3/C5) and #11 are complete. See
> `docs/reports/track-c.md` for the implementation evidence and residuals. The
> Track C subsections below are retained as the record; they are no longer open
> work. The next run starts at M3/M4/M6/E2E. Current HEAD includes `2d86930`,
> `79820d6`, `b9ad345`, `e7390d2`.

---

## 1. TL;DR state

| Area | State |
|---|---|
| Extraction pipeline | reproducible from a wiped tree; `make extract` + `make normalize` + `make anims` all exit 0 |
| Asset integrity | 0 duplicate UIDs, 0 missing/corrupt meshes, `MESH HOLES=0` |
| Unit suite (`run_tests.gd`) | **fails=0**, 0 `ERROR:`/`SCRIPT ERROR`, **0 leaks** |
| M2 player suite (`test_m2_player.gd`) | **9/9** |
| Scripts | **49/49 compile** (46 project scripts + 3 probes) |
| E2E (unmasked) | **212 pass / 44 fail / 0 BOOT / 0 SCRIPT ERROR** — no new failure IDs vs baseline |
| World data | **107/107 maps**, 16 contracts, 210 patrol paths / 673 waypoints, 222 scene variants, 4,118 device placements, **3,695 Niagara placements / 37 systems** |
| Materials | **0 fallback warnings** (Track C5 complete) |
| Audio | 1,296 events / 1,205 resolved; 5,018 clips |

The port is past M1, M2 and Track C. The next work is the milestone-owned gameplay work (M3/M4/M6) and the E2E backlog; Track C evidence and residuals are in `docs/reports/track-c.md`.

---

## 2. How to run everything (exact commands)

All commands run from `/home/john/Projects/TAT-2`.

```bash
# Build the C# extractor (needs ~/.dotnet10; the Makefile sets DOTNET_ROOT/PATH)
make build-extractor

# Full extraction (WEM/textures/meshes/levels/tables/anims USD; ~10-15 min)
make extract

# Normalize all generated data (14 producers; ~2 min)
make normalize

# Animation GLBs + manifest (Blender; ~30 min, 995/995)
make anims

# Reimport changed GLBs/textures into Godot (~1-2 min)
tools/reimport_assets.sh

# Freshness + coverage + error gates (must exit 0)
make audit

# UID health (vendored; the .agents copy is gitignored)
python3 tools/check_uid_duplicates.py game --json     # error_count 0, warning_count 0

# GDScript compile gate
flatpak run org.godotengine.Godot --headless --path game \
  --script /home/john/Projects/TAT-2/tools/check_scripts_compile.gd

# Unit/integration suite (~2-4 min)
flatpak run org.godotengine.Godot --headless --path game --script res://tests/run_tests.gd

# M2 traversal/tools suite (~1-2 min)
flatpak run org.godotengine.Godot --headless --path game --script res://tests/test_m2_player.gd

# Leak verifier
flatpak run org.godotengine.Godot --headless --path game --script res://probe_leak.gd

# Unmasked E2E baseline (~10-15 min)
flatpak run org.godotengine.Godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd

# Targeted probes added this run
flatpak run org.godotengine.Godot --headless --path game --script res://tests/probe_ftue.gd
flatpak run org.godotengine.Godot --headless --path game --script res://tests/probe_scene_variants.gd
flatpak run org.godotengine.Godot --headless --path game --script res://tests/probe_niagara.gd

# Linux export
make linux-build     # -> build/tat2-linux-x86_64
```

**Do not edit `game/` scripts while a Godot test run is in progress.** Godot loads scripts lazily; editing mid-run produced an invalid 12-minute verbose run earlier. Edit between runs only.

---

## 3. Architecture map (where things live)

```
tools/
  tat-extract/Exporter.cs        CUE4Parse extractor (list/raw/tables/levels/materials/audio/meshes/textures/anims)
  parse_tables.py                levels, actors, markers, patrols, volumes, scene variants, devices, tables, fonts
  parse_materials.py             materials.json + mesh_materials.json (slot order)
  parse_interactables.py         lockpick tracks (emits arc_deg + arc_angle_deg), doors/escapes
  parse_contracts.py             contracts.json (Contract.Main.1..16; repairs order 15)
  parse_gameplay.py / parse_weather.py / parse_vfx.py / parse_loot.py / parse_spawners.py / parse_containers.py
  extract_audio.py               Wwise RIFF chunks -> wwise_raw + fallback SFX
  convert_wwise.py               wwise_raw -> Ogg + audio_events.json + audio_library.json
  parse_locres.py                UE5 locres -> 8 Godot CSV translations
  convert_videos.py              15 Steam mp4 -> .ogv + videos.json
  manifest_audit.py              coverage, freshness, errors.log gate
  reimport_assets.sh             Godot --import; --check guards .gdignore + find -L
  check_uid_duplicates.py        vendored project health checker (UID graph)
  check_scripts_compile.gd       vendored compile gate

game/src/core/                   game_data, game_state, save_system, audio_manager, net_manager,
                                 level_loader, vfx_manager, weather_profile, weather_visuals,
                                 animation_library, level_niagara.gdshader, *.gdshader
game/src/player/                 thief_character, smoke_projectile
game/src/ai/                     guard_ai, civilian_npc
game/src/stealth/                light_probe, noise_bus
game/src/interact/               doors, loot, clues, escape gates, puddles, bottles
game/src/missions/               mission_controller
game/src/ui/                     hud, main_menu, wardrobe, mission_prep, contract_table, ledger, settings, theme
game/tests/                      run_tests.gd, test_m2_player.gd, probe_*.gd
game/tests/e2e/                  run_e2e_tests.gd + tiers 1-4 + helpers
game/probe_leak.gd               shutdown leak verifier
game/data/generated/             all generated JSON (gitignored): levels/, gameplay/, tables/, weather/, vfx/, localization/
game/assets/ue/
  Content -> extracted/assets/TAT/Content     (visible)
  Raw     -> extracted/assets                 (TAT subtree hidden by .gdignore)
  Anims/  real directory (995 GLBs, kept across extraction)
  audio/wwise/ 5,018 Ogg + 9 fallback WAVs
  fonts/ 64 TTF
  videos/ 15 OGV
extracted/                       7.3 GB, gitignored, regenerable
docs/reports/                    per-area findings; e2e-baseline.md; sprint-3.md; tables-coverage.md
docs/HANDOFF_NEXT_AGENT.md       this file
```

**Gitignored:** `extracted/`, `game/assets/ue/`, `game/data/generated/`, `game/.godot/`, `build/`, `.agents/`.
A fresh clone must run `make extract && make normalize && make anims && tools/reimport_assets.sh` before the game/tests work.

---

## 4. What changed in this run (commits, newest last)

| Commit | Change |
|---|---|
| `f00e835` | baseline ignore of agent dirs + skills lock |
| `ba76a31` | Raw/TAT `.gdignore` emitted by extractor + reimport; vendored UID and compile gates; `--check` guard + `find -L` |
| `3075b63` | removed 2,058 stale Raw-route `.scn`; retired 3 unreferenced UDS brushes; deleted `glb51_known` allowlist |
| `8d94145` | WwiseAudio tables; locres CSVs (8 locales); 15 OGV; audit ignores `.import`/`.uid`, splits Maps; Makefile normalizer chain + both gates |
| `dbad647` | 107/107 maps; generic actor capture; 673 patrol points; 222 SV configs; devices.json |
| `b0f5c29` | Engine map templates mounted; Suite 31f expectations (107 levels, authored Audio sublevels) |
| `d589169` | Phase 12: unmasked Suites 42/44 + `_load_patched`; AudioManager + static-cache teardown (0 leaks); 16 contracts; ftue route; all 31 CurveTables; GameState fields; SaveSystem schema + type-safe merge; wardrobe unify |
| `e7c01f3` | M2 test alignments (partial crank grants nothing; queued viewcone decay) 9/9 |
| `f18c3a2` | E2E baseline on disk: 24 patches ported, typed-array lambda fixed, fall damage exempt from disguise |
| `44cd21c` | clean-regeneration fixes (audio producers, arc_deg at source, `.gdignore` freshness, BlendSpace allowlist) + B1 smart objects + B5 mips/volume basis/MultiMesh windows |
| `c5649b8` | explicit FTUE collider budget (40k building / 44k total) + `probe_ftue` |
| `b2b0b3a` | deterministic SceneVariant selection + `probe_scene_variants` |
| `0c65ca6` | sprint-3 doc with Track B + Niagara evidence |
| `605de44` | all 3,695 Niagara placements spawned via 37 MultiMesh nodes + `probe_niagara` |
| `ba020cf` | MaterialLibrary added to extractor table roots (C5 groundwork) |

---

## 5. Data pipeline details and hard-won gotchas

### `.gdignore` / duplicate UIDs
- Godot scans `TAT/Content` twice: once via `res://assets/ue/Content/**` and once via `res://assets/ue/Raw/TAT/Content/**`, producing duplicate UIDs.
- The ignore **must** be the physical `extracted/assets/TAT/.gdignore` (which is `game/assets/ue/Raw/TAT/.gdignore` through the symlink). It hides only the `Raw/TAT/**` route; `Content/**` enters below `TAT/`, so it stays visible.
- **Never** place a `.gdignore` under `TAT/Content/` — it hides every mesh.
- `Exporter.Meshes()` and `tools/reimport_assets.sh` both create it; `make extract` and `reimport` keep it alive.
- Writing through `game/assets/ue/Raw` is blocked (symlink); write the physical path only.
- Canonical duplicate check (path-agnostic):
  ```bash
  ls game/.godot/imported | grep '\.scn$' | sed 's/-[0-9a-f]\{32\}\.scn$//' | sort | uniq -d
  strings game/.godot/uid_cache.bin | grep -c 'assets/ue/Raw/TAT'   # must be 0
  strings game/.godot/uid_cache.bin | grep -c 'assets/ue/Content/'  # must stay >= 2054
  ```
- Nine remaining same-basename `.scn` collisions are **distinct assets** with the same filename (e.g. two `SM_Radiator.glb` at different paths). They are not route duplicates; the authoritative UID check is 0/0.

### Extraction
- `make extract` runs `list raw tables levels materials audio meshes textures anims`. It does **not** produce the animation GLBs or `anims_manifest.json`; that is `make anims` (Blender, ~30 min, 995/995). A wipe of `game/data/generated` removes the manifest — always run `make anims` after a wipe.
- `Exporter.Tables()` has an explicit root allowlist. It now includes `WwiseAudio/` and `MaterialLibrary/`. Engine materials (`WorldGridMaterial`, `BasicShapeMaterial`) are still **not** dumped because only `Engine/Content/BasicShapes|EngineMaterials|EngineMeshes|MapTemplates|EngineSky` are mounted.
- `extracted/errors.log` is truncated each run. It holds 14 `UBlendSpace*` converter failures. `manifest_audit --fail-on-errors` classifies them as **known-unsupported** (exact path list in the tool); any other line fails the audit.
- The extractor writes two output shapes: meshes keep `assets/TAT/Content/...`; textures strip to `assets/Art/...`. This is why both `Content` and `Raw` symlinks exist.

### Normalization
- `make normalize` runs exactly: `parse_tables parse_materials parse_gameplay parse_contracts parse_containers parse_interactables parse_loot parse_spawners parse_vfx parse_weather extract_audio convert_wwise parse_locres convert_videos`.
- Order matters: `parse_tables` runs before `parse_interactables`; the latter overwrites `interactables.json`, so aliases must be emitted **in the producer**. `arc_deg` is now emitted by `parse_interactables.py`.
- `parse_tables.extract_levels()` is manifest-driven: it reads the Steam manifest's `.umap` list (env `TAT_MANIFEST` overrides) and maps each to `extracted/json/<rel>.json`. This is why maps outside `Content/Maps` (Art/Developer maps) are now emitted. If the manifest is absent, it falls back to scanning `json/Maps` for files containing `"Type": "World"`.
- Every valid map is emitted, including World-only maps. Never reintroduce the old non-empty payload gate; it silently dropped maps.
- `LevelInstance` merging runs recursively; 138 instances / 32,036 meshes resolved, 0 unresolved.
- `devices.json` is rule-based: 21 families, class counts + aggregation rules + audit-expected deltas. Two deltas are documented: breakables 1,563 vs 1,897 (issue #3) and secret switches 12 vs "9+".
- Freshness scans ignore `.import`, `.uid`, and dotfiles. Do not remove those exclusions.

### Contracts & FTUE
- Steam ships **exactly 16** contracts (`Contract.Main.1..16`). `Contract.Main.15` has `ContractOrder: 0` in the shipped table and is repaired from its key.
- `jaspering_hall` is **a cut location, not a shipped map**: Steam's manifest has only three legacy asset names (`DA_SpawnBucket_..._JasperingHall_Lantern`, two `BP_GuardSecurity_JasperingHall_ClubLantern*`). There is no `.umap`, no contract 17/18, no scene.
- The tutorial route is `"ftue"` with the 10 authored sublevels from `GameData.get_ftue_sublevels()`: `FTUE_P, FTUE_Checkpoints, FTUE_AI, FTUE_Fairy, FTUE_TutorialRunner, FTUE_Building_JewelryStore, FTUE_Building_SpawnArea, FTUE_Gameplay, FTUE_Geometry, FTUE_Audio`.
- FTUE is a whole-city map: 35,397 colliders. It has an explicit budget (`MAX_BUILDING_SHAPES_FTUE=40000`, `MAX_TOTAL_SHAPES_FTUE=44000`) applied only when a path contains `/FTUE/`, with a warning naming the raise. Every other map keeps 28,000/32,000.
- Den map token `MapTokenJasperingHall` was removed; the FTUE entry is `ftue`.

### Save / data schema
- `SaveSystem.data` is built from one `_defaults()` in `_ready()`; `currency` defaults to **0**.
- Canonical keys: `equipped_loadout` is a **Dictionary keyed by thief** (`spider`, `chameleon`), each with `head/body/calling_card/tools/perks/active_tool/active_tool_id`. Legacy array/flat/`loadout` shapes are migrated in `_ensure_defaults`.
- `load_save()` uses `_merge_validated()` (recursive, type-checked). Unknown keys are ignored; wrong-typed known keys keep the default.
- Wardrobe uses `SaveSystem.get_loadout/set_loadout`.
- `GameState.active_thief_id` is a computed property over `thief_id`; `active_map_seed`, `active_scene_variants`, `active_match_mode` exist.
- `GameData` loads all **31** CurveTables (four roots + nine extra directories) and exposes `get_player_stat_def`, `get_xp_def`, `get_upgrade_curve`, `get_contracts`, `get_ftue_sublevels`.

### Level loader
- `smart_objects` is a separate collection from `guard_spawns` (1,707 defensive posts).
- `_cap_image()` regenerates mipmaps after downscale for images ≥64 px; tiny UI icons stay mip-free.
- Volumes apply authored `basis`/`rotation` (emitted by `parse_tables`).
- Den window clipping handles `MeshInstance3D` and single-instance `MultiMeshInstance3D`; ambiguous multi-window batches are counted, never silently missed.
- Niagara: `_spawn_level_niagara()` groups records by `asset` and creates one `MultiMeshInstance3D` per NS_* system (3,695 instances / 37 nodes). The shader is `game/src/core/level_niagara.gdshader`; Godot 4 has **no `billboard` render mode** — the shader builds the billboard basis manually from `INV_VIEW_MATRIX`.
- Scene variants: `LevelLoader.select_scene_variants(map_id, seed, requested)` picks one record per state group with a version-stable FNV-1a hash. Overrides are **not** applied yet (#11).

### Audio
- Audio teardown: `AudioManager.cleanup_on_exit()` stops/detaches/frees every voice, bed and gramophone playback and clears caches. It is called from `mission_controller._exit_tree`, `run_tests` before exit, and `probe_leak`.
- Static caches with `cleanup_static_caches()`: `VfxManager`, `GuardAnimationLibrary`, `ArtNouveauTheme`, `weather_profile.gd`, `weather_visuals.gd`, `guard_ai.gd`.
- Result: 0 leaked resources/RIDs (was 11 resources / 6 RIDs, plus audio playbacks earlier).

---

## 6. Test harness and probes (what each name means)

| File | Purpose | Expected |
|---|---|---|
| `game/tests/run_tests.gd` | 36 suites (42/44 removed as masking) | fails=0, 0 `ERROR:`, 0 leaks |
| `game/tests/test_m2_player.gd` | 9 traversal/tool checks | 9/9 |
| `game/probe_leak.gd` | Den + Guildhall load/free leak check | 0/0/0 |
| `game/tests/e2e/run_e2e_tests.gd` | Tiers 1–4 unmasked | 210/256, 46 fail, 0 BOOT |
| `game/tests/probe_ftue.gd` | FTUE collider budget | player=1, dropped=0, budget_ok, safe room |
| `game/tests/probe_scene_variants.gd` | seeded SV selection | 104 Guildhall, stable, varies, requested |
| `game/tests/probe_niagara.gd` | absolute Niagara coverage | records=3695, spawned=3695, systems=37, nodes=37 |

The E2E runner no longer patches expectations. All 24 alignments live in the tier files. If you add a new expectation, edit the tier file — never reintroduce `_load_patched`.

`docs/reports/e2e-baseline.md` holds the 46 remaining failures with owner milestones. Issue #5 is the umbrella; #7 M2, #8 M3, #9 M6, #10 M4.

---

## 7. Open work — prioritized

### Track C5 — materials fallback → 0 (**done**)
37 warnings remain, 19 distinct UE paths:

```
8  /Engine/EngineMaterials/WorldGridMaterial
4  /Game/MaterialLibrary/Utility/M_DarkGrey
3  /Game/ThirdParty/PipePoleAnimationPack/Demo/LevelPrototyping/Materials/MI_Solid_Blue
2  /Game/ThirdParty/Stylized_Furniture/Materials/MI_TeleScope_Inst
2  /Game/ThirdParty/CobwebPack/Materials/CobwebFogy2sided
2  /Game/ThirdParty/CobwebPack/Materials/CobwebFogy
2  /Game/Gameplay/Interactables/ElectricPower/MI_PowerLight_On
2  /Game/Art/Gameplay/Gear/BlackJack/Mi_Blackjack
2  /Game/Art/Environment/Lights/LightModules/T_LightSm_SconceA_Brass
2  /Engine/BasicShapes/BasicShapeMaterial
1  /Game/ThirdParty/CobwebPack/Materials/SimpleCobweb2
1  /Game/ThirdParty/CobwebPack/Materials/BaseMaterial2Sided
1  /Game/ThirdParty/CobwebPack/Materials/BaseMaterial
1  /Game/MaterialLibrary/Debug/M_DefaultEmissive_Blinking
1  /Game/Developers/gjasp/Chrome
1  /Game/Art/Environment/OldManor/SM_OldManor_DrivewayA_x6
1  /Game/Art/Environment/City/Streets/Sidewalks/SM_SidewalkCityA_6m
1  /Game/Art/Environment/City/Architecture/BeautifulCorner/SM_SidewalkCityStone_6m
```

Facts:
- `MaterialLibrary/` is now dumped (`ba020cf`), but `M_DarkGrey` and `Mi_Blackjack` still do not appear in `materials.json` — `parse_materials.py` filters materials without a resolvable albedo texture. These are untextured (constant PBR) materials; the parser must emit them from their authored `BaseColor`/`Roughness`/`Metallic`.
- `MI_Solid_Blue` and `MI_PowerLight_On` **are** in `materials.json` yet still fall back at load. Check `LevelLoader.get_material_for_ue()` key normalization (`/Game/...` vs stripped path, case, `.MI_...` suffix).
- `WorldGridMaterial` and `BasicShapeMaterial` are Engine materials with no dump. Add an explicit authored system-material map (documented values, not a tier-3 guess) for at least these two; the checkerboard/debug look is wrong on shipped Engine primitives.
- Several `SM_*` names in the list are **mesh paths**, not materials (`SM_OldManor_DrivewayA_x6`, sidewalks). The level data points the material slot at a mesh; map those to the actual material or a documented default. Do not add fake materials with those names.
- Acceptance: `grep -c 'material fallback'` = 0 on a full `run_tests`; no visual regression in captures; `fallback_material_count` in loader stats is 0 on Guildhall/OldManor.

### #11 — apply SV spawner overrides (**done: exact tags + class map**)
Selection is done. Applying overrides needs a documented mapping because the vocabularies differ:
- SV overrides name `MapVariation.SceneElement.Locks.Doors`, `.Locks.Windows`, `.Lights`, `.Guards`, `.MajorLoot`, `.Quest`.
- Level spawners carry `SpawnGroup.TagName` = `MapVariation.SpawnGroup.*`; some actors carry `_sceneRequirement.ElementTag` = `MapVariation.SceneElement.*` (Vault, Quest).
- Raw maps contain 3,710 `NiagaraComponent`s, 819 actors with tags (mostly `WithSmartObject`).
- Suggested mapping: doors → `MissionSpawner_Door`/swinging doors; windows → window actors/`BP_Civic_*Window*`; lights → light markers; guards → `MissionSpawner_Character`; loot → `MissionSpawner_Major/MinorLoot`; quest → actors with `scene_requirement == SceneElement.Quest`. Roll per actor with `seed + fnv1a(actor_name)`, chance from the override. Assert fixed-seed reproducibility in a probe.
- Alternative: extend the extractor to dump the gameplay-tag registry that maps `SceneElement` to actor classes, if such an asset exists. Search `extracted/json` for `MapVariation.SceneElement` outside `SV_*` and `Guildhall_Gameplay` first.

### C1 — `OSERenderer` NPR + SNN (**done**)
- No post-process infrastructure exists yet. Godot 4.7 supports `CompositorEffect` (RenderingDevice) — that is the robust path for a screen-space pass; a camera-child full-screen quad is a simpler fallback.
- Proposed files: `game/src/core/ose_renderer.gd` (effect/node + toggles), `game/src/core/tat_npr.gdshader` (ink: depth/normal edge detection via `hint_depth_texture` / `hint_normal_roughness_texture`), `game/src/core/tat_snn.gdshader` (painterly: edge-preserving blur + quantization).
- Acceptance: 0 `SHADER ERROR` under Vulkan, toggles exposed, before/after captures under `build/qa/` + a short report.
- Source of truth: audit Cluster B §2.3 (`OSE.NPR` ink outline + `OSE.SNN` painterly + `T_PaintStroke*`). Steam assets are in the reference install; do not invent parameters without naming the approximation.

### C2 — `OSEXray` (**done**)
- Depth-ignoring silhouettes for guards/loot/clues/players. Two viable implementations: (a) clone target meshes with an unshaded `depth_test_disabled` override in category colours (cheap, works per-instance); (b) a CompositorEffect with an ID/stencil buffer (higher fidelity, more work).
- Acceptance: silhouette visible through a wall with X-ray on, absent with it off; category colours differ; capture pair.
- Interface already reserved in the plan: group `"xray_target"`, `set_xray_highlight(enabled, category)`.

### C3 — weather (**done**)
- **Roof rain occlusion:** the current rain is a global particle layer; it rains through ceilings. Approach: gate rain emitter positions by a downward raycast / roof volumes, or split rain into outdoor regions derived from level geometry. Acceptance: a roofed fixture shows no rain inside while outside rain renders.
- **`PPM_RainDropsOnLens`:** full-screen lens-drop overlay driven by the weather preset (intensity/speed). Acceptance: appears in a rain preset, absent otherwise.
- **`Guildhall_LocalVolumetric` + `Clouds`:** `Guildhall_LocalVolumetric.tatlevel.json` and `Guildhall_Clouds.tatlevel.json` now exist. Load/render them (fog volume + cloud meshes) and verify in a capture.
- Existing code: `weather_visuals.gd` (rain layer, pano cache), `weather_profile.gd` (presets, LUTs, `fog_sky_affect`).

### E2E backlog (46 failures)
Classified in `docs/reports/e2e-baseline.md`, tracked as #7 (M2), #8 (M3), #9 (M6), #10 (M4). Policy agreed with the user: fix harness/genuine-now; system-dependent failures close with their milestone. Re-run tiers after each milestone:
```bash
flatpak run org.godotengine.Godot --headless --path game \
  --script res://tests/e2e/run_e2e_tests.gd -- --tier=1   # or 2/3/4
```
Do not weaken assertions to go green; fix the game or classify with evidence.

### Then the milestone work
- **M3:** Chameleon/Cotter binding (28 GLBs), 54 cosmetics, revive (co-op/self/totem), combat (blackjack charge/cooldown/block/parry/takedowns/carry), traversal (dodge/slide/manual mantle/ladders), 5 ProceduralCamera configs, 3P locomotion, 28 tools + 6 potions, 3-mode 10-glyph Thiefsign, 1P anim fixes.
- **M4:** navmesh pathfinding + authored patrol playback (data ready), AI sensing fixes, archetypes, StateTree/escalation/lockdown, acoustic portals, power grid, security/turrets/traps, breakables, vault doors/windows/combo locks, stashes/electrotype/clues.
- **M5:** Wwise wiring expansion (events/VO/music/switches/RTPCs/reverbs/states), LAN ENet co-op (state/world/revive/Thiefsign), joypad bindings.
- **M6:** missions/Den hub/FTUE runner+videos+infographics, UI defects and missing screens, 64 fonts + CJK, 8 locales via `TranslationServer`, gamepad focus/glyphs.
- **E2E/final:** 350+ assertions, 2-instance ENet co-op, Tier 5 adversarial, Linux export + rubric.

---

## 8. Known data deltas and how to treat them

| Delta | Evidence | Treatment |
|---|---|---|
| breakables 1,563 vs audit 1,897 | 4 breakable component classes; self-destruct components (342) are a different mechanic | issue #3; revisit in M4 |
| secret switches 12 vs "9+" | toggle-switch components + secret-labelled switches | accepted, recorded in devices.json |
| Niagara 3,695 vs earlier 3,699 | pre-wipe data had 4 extra records; clean extraction is exactly 3,695 across 37 systems, matching the audit | resolved |
| 9 same-basename `.scn` | distinct assets sharing a name (e.g. two `SM_Radiator`) | not duplicates; ignore detector noise, rely on UID checker |
| 14 BlendSpace assets | CUE4Parse `AnimationExporter` limitation | enumerated known-unsupported in `manifest_audit`; do not silently allow other errors |

---

## 9. Operational hazards

1. **Never edit `game/` while Godot is running.** Lazy script loads make results meaningless.
2. **Wipe recovery.** A full regeneration takes ~45–60 min (`extract` + `normalize` + `anims`). Move trees to `.bak` (gitignored) instead of deleting, and only remove after all gates pass.
3. **Disk.** `extracted/` is 7.3 GB; `/home` had 117 GB free at handoff. A `.bak` copy doubles the footprint.
4. **Symlinks.** `game/assets/ue/Content` and `Raw` point into `extracted/`. Do not write through `Raw`; use `extracted/assets/...`.
5. **`.annotations`/`.agents` are gitignored.** All gates needed by CI are vendored under `tools/`; keep it that way.
6. **`make audit` is a real gate.** It fails on stale groups, coverage < 90 %, missing Engine deps, or unexpected `errors.log` lines.
7. **`make anims` is slow.** ~30 min for 995 clips and it writes the manifest only at the end.
8. **Audio pipeline needs `extract_audio` + `convert_wwise`.** They are normalizers now; skipping them makes `audio` freshness fail.
9. **Godot has no `billboard` spatial render mode** (4.x). Use the manual `INV_VIEW_MATRIX` basis as in `level_niagara.gdshader`.
10. **The swarm plan/ledger is gone.** Ignore `.swarm/` prose except the archived blocker file; the authoritative record is `git log` plus this handoff and `docs/reports/`.

---

## 10. Definition of done for the next run

```bash
git status --short                      # clean
make audit                              # exit 0, all groups fresh, 0 unexpected errors
python3 tools/check_uid_duplicates.py game --json   # 0/0
flatpak run ... --script tools/check_scripts_compile.gd   # 0 broken
flatpak run ... --script res://tests/run_tests.gd          # fails=0, 0 leaks
flatpak run ... --script res://tests/test_m2_player.gd     # 9/9
flatpak run ... --script res://probe_leak.gd               # 0/0/0
flatpak run ... --script res://tests/probe_ftue.gd         # PASS
flatpak run ... --script res://tests/probe_scene_variants.gd  # PASS
flatpak run ... --script res://tests/probe_niagara.gd      # PASS
flatpak run ... --script res://tests/e2e/run_e2e_tests.gd  # no new failures vs baseline
```

Track C is done when:
- material fallback warnings = 0;
- NPR/SNN and X-ray have captures + a report;
- rain does not fall through a roofed fixture, lens drops appear in rain, volumetric/Clouds render;
- no gate regresses.

Start with C5. It is bounded, data-driven, and removes noise from every later capture.
