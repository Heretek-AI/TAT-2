# TAT-2 Architecture & Asset Pipeline Reference

**TAT-2** is a Godot 4.7.2 (Forward+ / Jolt Physics) port of *Thick As Thieves* (`TAT`), sourced from the Steam installation at `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/`.

---

## 1. Repository Layout

```text
<repo>/
├── Makefile                  # build-extractor, extract, normalize, audit, test, run
├── extracted/                # Raw CUE4Parse dumps (assets/, json/, audio/, filelist.txt)
├── tools/
│   ├── tat-extract/          # .NET 10 CUE4Parse + Oodle extractor (Program.cs, Exporter.cs)
│   ├── parse_tables.py       # Normalizes UE5 .umap/.uasset JSONs -> .tatlevel.json + tables
│   ├── parse_materials.py    # Resolves MI_*/M_* materials -> materials.json & mesh_materials.json
│   ├── extract_audio.py      # Splits the cooked ubulk into raw RIFF/PLUG chunks under extracted/audio/wwise_raw/
│   ├── convert_wwise.py      # Decodes raw chunks (vgmstream) -> Ogg Vorbis in game/assets/ue/audio/wwise/
│   └── manifest_audit.py     # Audits extracted coverage against Steam pak filelist
└── game/                     # Godot 4.7.2 project root
    ├── project.godot
    ├── scenes/               # main_menu.tscn, mission.tscn
    ├── assets/ue/            # Content/ (.glb meshes), Raw/ (.png textures), audio/, fonts/
    ├── data/generated/       # levels/ (.tatlevel.json), tables/, materials.json, mesh_materials.json
    ├── src/
    │   ├── core/             # GameData, GameState, SaveSystem, LevelLoader, VfxManager, AudioManager, NetManager
    │   ├── missions/         # mission_controller.gd (hub, contract loading, spawns, objectives)
    │   ├── player/           # thief_character.gd (movement, stealth, tools, 1P viewmodel)
    │   ├── ai/               # guard_ai.gd (6-state FSM, vision, hearing, search, KO/revival)
    │   ├── stealth/          # light_probe.gd, noise_bus.gd
    │   ├── interact/         # loot_item.gd, lockable_door.gd, escape_gate.gd, clue_item.gd
    │   └── ui/               # main_menu.gd, hud.gd, art_nouveau_theme.gd, settings_ui.gd,
    │                         # wardrobe_ui.gd, contract_table_ui.gd, mission_prep_ui.gd,
    │                         # ledger_ui.gd, loading_screen.gd
    └── tests/
        └── run_tests.gd      # Headless 16-suite verification runner (`make test`)
```

---

## 2. UE5 -> Godot Extraction & Normalization Pipeline

1. **Extraction (`tools/tat-extract/Exporter.cs`)**
   - Uses `CUE4Parse` (`EGame.GAME_UE5_5`) with `.usmap` type mappings (`tools/ue4ss/output/*.usmap`).
   - Exports:
     - `levels` -> `extracted/json/Maps/**/*.json`
     - `tables` -> `extracted/json/{Gameplay,AI,Missions,Character,Core,StringTables,Maps,UI,Audio}/**/*.json`
     - `materials` -> `extracted/json/**/*.json`
     - `meshes` -> `extracted/assets/**/*.glb` (including `SM_*`, `SK_*`, `SKM_*`, `GB_*`, `/Test/LevelKits/`, `/GasLamps/`, `/Furniture/Tables/`, `/Levers/`, `/GeneratedMeshes/`, `/Developers/`)
     - `textures` -> `extracted/assets/**/*.png` (including `.umap`-embedded `Landscape` `Heightmap_*.png` textures)
2. **Table & Level Normalization (`tools/parse_tables.py`)**
   - Reads `extracted/json/Maps/**/*.json` and resolves:
     - `StaticMeshComponent`, `SplineMeshComponent`, `InstancedStaticMeshComponent`, `HierarchicalInstancedStaticMeshComponent`, `FoliageInstancedStaticMeshComponent`
     - `Blueprint` CDO/SCS templates (`BPP_*_PLA`) and `LevelTransform` offsets from `LevelStreamingAlwaysLoaded`
     - `LandscapeComponent` heightfields (`landscapes` array with `heightmap`, `quads`, `scale_bias`, world transform)
     - Lights (`PointLightComponent`, `SpotLightComponent`, `DirectionalLightComponent`) and gameplay markers (`PlayerStart`, `MissionSpawner*`, `Door`, `Escape`, `Guard`)
   - Outputs `game/data/generated/levels/**/*.tatlevel.json` (74 normalized level JSONs, 53,190 mesh instances, 3,479 lights) and 141 DataTable/CurveTable/StringTable JSONs under `game/data/generated/tables/`.
3. **Material Resolution (`tools/parse_materials.py`)**
   - Maps `MI_*` / `M_*` material instances to `albedo`, `normal`, `orm`, `emissive`, and `tint` in `game/data/generated/materials.json` (1,272 entries) and mesh slot bindings in `game/data/generated/mesh_materials.json`.

---

## 3. Godot Runtime Architecture

- **Autoloads (`game/project.godot`)**: `GameData`, `GameState`, `NoiseBus`, `AudioManager`, `NetManager`, `SaveSystem`.
- **Level Streaming (`game/src/core/level_loader.gd`)**:
  - `load_sublevels()` / `load_sublevels_async()` parse `.tatlevel.json` sublevels, batch repeated `.glb` meshes into `MultiMeshInstance3D`, bind PBR materials via `get_material_for_ue()` (with lowercase fallback `_materials_db_lower` / `_mesh_mats_db_lower`), build `LandscapeComponent` terrain meshes + `ConcavePolygonShape3D` colliders via `_build_one_landscape()`, and create `BoxShape3D`/`trimesh` colliders under per-cell `LevelCollision_<cx>_<cz>` `StaticBody3D`s.
- **Mission Flow (`game/src/missions/mission_controller.gd`)**:
  - `active_contract_order == 1` loads **Thieves' Den** (`thieves_den`: Map Table, Wardrobe, `[F] READ LEDGER`, `[F] CHANGE DECORATION`, `[F] TURN ON` Gramophone, `BlueWisp` VFX, arched window godray).
  - Contracts `2..18` load **Old Manor** (`old_manor`), **Constables' Guildhall** (`guildhall`), or **Jaspering Hall** (`jaspering_hall`), spawning grounded player (`_spawn_player()` + `_snap_player_to_ground()`), guards, loot, clues, lockable doors, and escape gates.
- **Android (internal sideload build)**: `tools/prepare_mobile_project.py` materialises `build/mobile_game/` (gitignored) with a pruned asset closure, ETC2/ASTC textures, Mobile renderer and landscape orientation. `src/core/mobile_profile.gd` supplies Performance/Balanced/Quality budgets (lights, shadow casters, render scale, LOD bias, glow, FPS cap) and `src/ui/mobile_touch_ui.gd` provides the 13-button touch layer + floating stick; both are gated on `OS.has_feature("mobile")` so desktop is unchanged. See `docs/ANDROID.md`.
- **Verification Commands**:
  - `make test` — runs `game/tests/run_tests.gd` headless (`SUMMARY: fails=0`).
  - `make audit` — runs `tools/manifest_audit.py` against Steam manifest.
  - `make run` — launches the Godot 4.7.2 client (`Vulkan Forward+`).
