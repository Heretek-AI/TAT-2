# Handoff — Thick As Thieves Godot 4.7.2 port (next run)

**Repo:** `/home/john/Projects/TAT-2`
**HEAD at handoff:** the W0a identity commit — `fix(identity): remove Steam persona, use shipped key names, gate texture cap` (run `git log -1 --oneline`; it sits on top of `3202283`)
**Working tree:** clean; `main` in sync with `origin/main`
**Godot:** `4.7.2.stable` via **native `tools/godot`** (Flatpak fallback inside the
wrapper). `godot` is **not** on `$PATH`.
**Renderer:** Forward+ · Jolt Physics 60 Hz · 1280×720 reference
**Steam reference:** `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/`
(`1.5.193.148559`, UE 5.5+, Win64 Shipping)
**Platform scope:** Linux desktop `x86_64`. Android internal builds are in
[`docs/ANDROID.md`](ANDROID.md); mobile gameplay is out of scope (issue #2).
**Standing user directive:** every item listed in this handoff is valid and should
be pursued.

> There is **no swarm plugin** in this environment. Do not look for `save_plan`,
> `declare_scope`, coder lanes or `update_task_status`. Implement directly with
> `read`/`edit`/`write`/`shell`, verify with real commands, and commit. Git history
> is the record.
>
> **Read first:** [`AGENTS.md`](../AGENTS.md) (operating rules and traps),
> [`docs/FIDELITY_GAPS.md`](FIDELITY_GAPS.md) (live coverage + every residual),
> [`docs/reports/gameplay-truth-wave.md`](reports/gameplay-truth-wave.md)
> (latest wave evidence).

---

## 1. TL;DR state

| Area | State |
|---|---|
| Extraction pipeline | reproducible from a wiped tree; `make extract` + `make normalize` + `make anims` exit 0 |
| Asset integrity | 0 duplicate UIDs, 0 missing/corrupt meshes, `MESH HOLES=0`, 0 missing textures |
| Scripts | **69/69 compile**, 0 broken |
| Unit suite (`run_tests.gd`) | **59 suites, fails=0**, 0 `SCRIPT ERROR` |
| M2 player suite | **fails=0** |
| Probes | door walk **PASS**, viewmodel truth **PASS**, Niagara **PASS** |
| E2E (unmasked) | **264/264**, 0 BOOT, 0 `SCRIPT ERROR` (tier 1: 115) |
| World data | 107/107 maps, 16 contracts, 210 patrols / 673 waypoints, 222 scene variants, 4,118 devices, 3,695 Niagara placements (3,308 active) / 36 systems |
| Materials | 1,629 resolved; two-sided and paint-stroke albedo read from `BasePropertyOverrides` and child `_D` companions |
| Runtime | startscreen → Den → prep → Guildhall → scoring, free-play cleanout, authored devices/clues/patrols; co-op player pose + host-validated door events (loot/AI not replicated) |
| Captures | serialized Vulkan under Xvfb; sources tracked in `build/qa/` |

The port is past M1, M2 and Track C. Gameplay milestones M3–M6 are implemented
in slices (see the 2026-11-24 wave); the residuals in §7 are the remaining work.

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

# Desktop texture pre-bake (~1-2 min): 1024 px long-edge cap + mipmaps in the
# loader-managed PNG .import sidecars, then reimport. Preview with:
#   python3 tools/prebake_texture_cap.py --dry-run
make desktop-texture-cap

# Freshness + coverage + error gates (must exit 0)
make audit

# UID health (vendored; the .agents copy is gitignored)
python3 tools/check_uid_duplicates.py game --json     # error_count 0, warning_count 0

# GDScript compile gate
tools/godot --headless --path game \
  --script /home/john/Projects/TAT-2/tools/check_scripts_compile.gd

# Unit/integration suite (~2-4 min, 59 suites)
make test
# or: tools/godot --headless --path game --script res://tests/run_tests.gd

# M2 traversal/tools suite (~1-2 min)
tools/godot --headless --path game --script res://tests/test_m2_player.gd

# Leak verifier
tools/godot --headless --path game --script res://probe_leak.gd

# Unmasked E2E baseline (~10-15 min, 264 checks)
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=1

# Targeted probes
tools/godot --headless --path game --script res://tests/probe_door_walk.gd
tools/godot --headless --path game --script res://tests/probe_viewmodel_truth.gd
tools/godot --headless --path game --script res://tests/probe_niagara.gd
tools/godot --headless --path game --script res://tests/probe_ftue.gd
tools/godot --headless --path game --script res://tests/probe_scene_variants.gd

# Linux export
make linux-build     # -> build/tat2-linux-x86_64
```

### Live Vulkan captures (serialize: one Godot at a time)

`build/qa/` sources are tracked; PNG output is gitignored. Every capture must run
with a real display; on this machine that is Xvfb + native Vulkan:

```bash
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp -ac &
DISPLAY=:99 TAT2_TEX_CAP=1024 tools/godot --path game --rendering-driver vulkan \
  --script build/qa/capture_zipwire_hang.gd        # KF16/KF17: sign, gate, door, beams
DISPLAY=:99 tools/godot --path game --rendering-driver vulkan \
  --script build/qa/capture_ui.gd                  # startscreen / prep / wardrobe
DISPLAY=:99 tools/godot --path game --rendering-driver vulkan \
  --script build/qa/capture_freeplay.gd            # free-play prep + HUD
DISPLAY=:99 TAT2_DEN_CAPTURE_DIR=/tmp/den \
  tools/godot --path game --rendering-driver vulkan \
  --script build/qa/denfix_capture.gd              # KF02/KF06/KF09/KF10
```

Free-play QA without the menu: `tools/godot --path game -- --qa-free-play`
(autostart now runs clean; the old `main_menu.gd:303` `SCRIPT ERROR` is fixed).

**Do not edit `game/` scripts while a Godot test run is in progress.** Godot loads
scripts lazily; editing mid-run produced an invalid 12-minute verbose run earlier.
Edit between runs only.

---

## 3. Architecture map (where things live)

```
tools/
  tat-extract/Exporter.cs        CUE4Parse extractor (list/raw/tables/levels/materials/audio/meshes/textures/anims)
  parse_tables.py                levels, actors, markers, patrols, volumes, scene variants, devices, tables, fonts
  parse_materials.py             materials.json + mesh_materials.json (slot order, BasePropertyOverrides, albedo companions)
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
  godot                          native 4.7.2 launcher (Flatpak fallback)

game/src/core/                   game_data, game_state, save_system, audio_manager, net_manager,
                                 level_loader, vfx_manager, weather_profile, weather_visuals,
                                 animation_library, level_niagara.gdshader, tat_beam.gdshader, *.gdshader
game/src/player/                 thief_character, smoke_projectile
game/src/ai/                     guard_ai, civilian_npc
game/src/stealth/                light_probe, noise_bus
game/src/interact/               doors, loot, clues, escape gates, puddles, bottles
game/src/missions/               mission_controller (spawns, fills, sign, free play, extraction)
game/src/ui/                     hud, main_menu, wardrobe, mission_prep, contract_table, ledger, settings, theme
game/tests/                      run_tests.gd (59 suites), test_m2_player.gd, probe_*.gd
game/tests/e2e/                  run_e2e_tests.gd + tiers 1-4 + helpers (264 checks)
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
build/qa/                        tracked capture/probe sources; captures, logs and exports ignored
docs/reports/                    per-area findings + one report per wave; e2e-baseline.md; track-c.md
docs/HANDOFF_NEXT_AGENT.md       this file
```

**Gitignored:** `extracted/`, `game/assets/ue/`, `game/data/generated/`,
`game/.godot/`, `build/` (except `build/qa/**/*.{gd,sh,py}`), `.agents/`.

A fresh clone must run `make extract && make normalize && make anims &&
tools/reimport_assets.sh && make desktop-texture-cap` before the game/tests work.

---

## 4. What changed recently (waves, newest last)

| Commit | Wave / change |
|---|---|
| W0a HEAD | **Identity / keys / texture-cap correction** — removed the capture Steam persona (`player_display_name()` → The Spider/The Chameleon, one-shot migration); shipped key names (`Guildhall Key`, `Elway Manor Key`, `Vault Key`); `--check` + `make texture-cap-check` in `make audit`; restored both SafeBlackFaction caps. Evidence: [`reports/gameplay-truth-wave.md`](reports/gameplay-truth-wave.md) §“Corrections (W0a)” |
| `3202283` | **Gameplay truth wave** — hard audit gate; guard sight/save/mirror/FOV blockers; authored devices, patrols, loudness, clues/quests, animation notifies; UI/locales/countdown; co-op transport. Evidence: [`reports/gameplay-truth-wave.md`](reports/gameplay-truth-wave.md) |
| `a410adc` | Track `build/qa` capture/probe **sources** so the E2E harness checks are reproducible from a clone |
| `1373bb9` | Docs: record the review remediation wave |
| `e7fcb7d` | T2-04-C accepts the intentional beam shader (3 `StandardMaterial3D` negative controls kept) |
| `0e89d2c` | Ground loot/civilians by AABB + floor ray; ornate gate fill; sign letter emission; free-play crash/currency/entry |
| `4b9fa03` | Additive beams, `BasePropertyOverrides.TwoSided`, paint-stroke albedo recovery, mirrored leaves, WorldGrid doors, blocker tag |
| `3ed80c0` | Mantle/climb/zipwire reject `blocking_volume`; T1-10-J; schema-v2 FOV 75→54.54 migration |
| `6fb3475` | Free-play Contract Inactive Guildhall Cleanout run with reference HUD |
| `f5b90ff` | Reverse landscape heightfield winding so terrain tops render (startscreen floor) |
| `3d010f7` / `c7735e5` | Den parchment emission 0.20 + shade fill; Guildhall road fills; probe exit |
| `e5e31f7` | Landscape normals, startscreen road bricks, Guildhall fallback normal, sign letter split |
| `665246a` | KF16 gate fill/headlights, KF17 skyline tower, Den map-table bounce |
| earlier | Startscreen decal/neon tuning, sky veil, KF16/KF17 follow-ups, Track C, world/free-play wave |

Per-wave evidence: `docs/reports/` (latest:
[`gameplay-truth-wave.md`](reports/gameplay-truth-wave.md)).

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
- **Texture pre-bake is not preserved by extraction.** `make desktop-texture-cap` edits the loader-managed `.png.import` sidecars that live under `extracted/`, so a clean extraction (which replaces `extracted/`) drops the `mipmaps/generate=true` + `process/size_limit=1024` edits. Rerun `make desktop-texture-cap` after every clean extraction and after `make normalize`; it is idempotent, `--dry-run` previews the capped textures, and `--revert` restores the originals from `build/texture_cap_manifest.json`. `python3 tools/prebake_texture_cap.py --check` (or `make texture-cap-check`, a prerequisite of `make audit`) fails on a stale target with “run make desktop-texture-cap”; `size_limit=0` counts as uncapped, and the alpha-critical storefront decal is exempt. The checked-in gate caught a real regression on 2026-11-24: both `T_SafeBlackFaction_*_D.png` (2048 px) had reverted to `size_limit=0` / no mips.
- `Exporter.Tables()` has an explicit root allowlist. It now includes `WwiseAudio/` and `MaterialLibrary/`. Engine materials (`WorldGridMaterial`, `BasicShapeMaterial`) are still **not** dumped because only `Engine/Content/BasicShapes|EngineMaterials|EngineMeshes|MapTemplates|EngineSky` are mounted.
- `extracted/errors.log` is truncated each run. It holds 14 `UBlendSpace*` converter failures. `manifest_audit --fail-on-errors` classifies them as **known-unsupported** (exact path list in the tool); any other line fails the audit.
- The extractor writes two output shapes: meshes keep `assets/TAT/Content/...`; textures strip to `assets/Art/...`. This is why both `Content` and `Raw` symlinks exist.

### Normalization
- `make normalize` runs exactly: `parse_tables parse_materials parse_gameplay parse_contracts parse_clues parse_quests parse_devices parse_containers parse_interactables parse_loot parse_spawners parse_vfx parse_weather extract_audio convert_wwise parse_locres convert_videos parse_anim_meta`.
- New producers (2026-11-24): `parse_clues.py` -> `gameplay/clues.json`, `parse_quests.py` -> `gameplay/quests.json`, `parse_devices.py` -> `gameplay/devices_runtime.json`, `parse_anim_meta.py` -> `anims_meta.json`. Each has a checker (`tools/check_*.py`) and a census assertion.
- **Audit is fail-closed and baseline-driven.** `make audit` compares against the tracked `tools/audit_baseline.json` (18 producers + infrastructure hashes + output digests). After intentionally changing a producer and regenerating, run `make audit-refresh-stamps` and commit the baseline. A normal first run without a baseline fails; `make audit-bootstrap` is the explicit initialisation path. Do not `touch extracted/errors.log`; the extractor now writes a run-marked log.
- **Exported-build localization**: Godot remaps imported `.csv` translation sources, so `FileAccess` cannot open `en.csv` inside a PCK. `Loc` falls back to the tracked `en.en.translation` resource. Keep `export_presets.cfg` `include_filter` for the CSV and verify the export log has no `missing English source table` warning.
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
- Niagara: `_spawn_level_niagara()` groups records by `asset` and creates one `MultiMeshInstance3D` per active NS_* system (3,695 authored -> 3,308 active / 36 nodes; 387 `NS_Candelabras_Flame_Out` skipped globally via `NIAGARA_INACTIVE_ASSETS`). The shader is `game/src/core/level_niagara.gdshader`; Godot 4 has **no `billboard` render mode** — the shader builds the billboard basis manually from `INV_VIEW_MATRIX`.
- Scene variants: `LevelLoader.select_scene_variants(map_id, seed, requested)` picks one record per state group with a version-stable FNV-1a hash. Overrides are **not** applied yet (#11).

### Audio
- Audio teardown: `AudioManager.cleanup_on_exit()` stops/detaches/frees every voice, bed and gramophone playback and clears caches. It is called from `mission_controller._exit_tree`, `run_tests` before exit, and `probe_leak`.
- Static caches with `cleanup_static_caches()`: `VfxManager`, `GuardAnimationLibrary`, `ArtNouveauTheme`, `weather_profile.gd`, `weather_visuals.gd`, `guard_ai.gd`.
- Result: 0 leaked resources/RIDs (was 11 resources / 6 RIDs, plus audio playbacks earlier).

---

## 6. Test harness and probes (what each name means)

| File | Purpose | Expected |
|---|---|---|
| `game/tests/run_tests.gd` | **59 suites** — data, loader, materials, doors, FOV schema, audio, VFX, UI, identity/cap | `SUMMARY: fails=0`, 0 `SCRIPT ERROR` |
| `game/tests/test_m2_player.gd` | traversal/tools checks | `M2_SUMMARY: fails=0` |
| `game/tests/probe_door_walk.gd` | closed blocks / 70° gate / re-toggle / F-spam / occupied close / lockpick | `DOORWALK PASS` |
| `game/tests/probe_viewmodel_truth.gd` | 1P viewmodel pose/reset, crank bone | `VIEWMODEL_TRUTH PASS` |
| `game/tests/probe_niagara.gd` | absolute Niagara coverage (authored/active/skipped/systems/nodes) | `NIAGARA_PROBE PASS` |
| `game/tests/probe_ftue.gd` | FTUE collider budget + safe room | player=1, dropped=0, budget_ok |
| `game/tests/probe_scene_variants.gd` | seeded SV selection | 104 Guildhall, stable, varies |
| `game/probe_leak.gd` | Den + Guildhall load/free leak check | 0/0/0; 7 texture RIDs warn unless `TAT2_NO_DEN_PROBE=1` |
| `game/tests/e2e/run_e2e_tests.gd` | Tiers 1–4 unmasked | **264/264** |

The E2E runner no longer patches expectations. All alignments live in the tier
files (`T1-10-J` blocking volumes, `T4-13` free-play no-currency). If you add an
expectation, edit the tier file — never reintroduce `_load_patched`, and never
delete an assertion to go green.

Recent additions to know about:

- **T1-10-J** — tall and low `blocking_volume` bodies reject climb/mantle; real
  walls still climb; 4 m mantles, 5 m refuses; no soft-lock. Tier 1 is now 115.
- **T4-13** — free-play extraction writes no contract and banks no currency.
- **T2-04-C** — `MI_LightBeam_SM` is an intentional `tat_beam.gdshader` exception;
  the three other textured materials must stay `StandardMaterial3D`.

---

## 7. Open work — prioritized

### 7.1 Functional gaps (the honest list)

1. **Co-op is transport-only.** `broadcast_player_state` is wired and host-validated
   world events work for doors, but loot, containers, AI/guards, mission state and
   devices remain client-authoritative/unsynced. No live two-process ENet gate
   (tier 5). Host-as-server is the planned path; no rollback.
2. **Devices are five families.** Beams, plates, noise alarms, power, turrets,
   cameras and wards run from `devices_runtime.json`. Breakables/shards, goo
   pipes, vault doors, sliding windows, magnetic locks, acoustic portals and
   junctions are authored data-only markers.
3. **Clues/quests are authored; the NPC quest is the next wave.** 96 facts /
   90 reachable / 6 dead are wired, readable spawners and quest items spawn at
   authored transforms, and the journal is live. Two orphaned Spider personal
   lines remain (`DT_ClueFacts_Personal_Spider_01:Intro`,
   `DT_ClueFacts_Personal_Spider_04:Renegade`; no consumers, `reachable=false`);
   the quest using them is planned for the next wave (W2). Spawner interaction
   radii are absent; do not invent dialogue or radii.
4. **Performance:** current export is ~39 FPS median at 1080p/high (post-load
   p10 36 / p90 41, mspf 25.6) and needs the quality-ladder + merge/HLOD
   experiments in `reports/ecosystem-reuse-review.md` to reach 60.
5. **Den GI:** still a Lumen/real-GI gap. VoxelGI was reverted for room spill;
   run the VoxelGI-vs-SSRT bake-off before adding another approximation.
6. **UI localization is partial:** `Loc.t()` works over the 8 shipped
   `.translation` files and the export fallback is fixed, but only the main
   menu/pause/prep labels were converted; the rest of the UI is still literal
   English.
7. **Animation notifies are data-only:** `anims_meta.json` and `notify_at()` are
   available; footstep/Ak/hit-window consumers are not wired yet. 1,734
   name-only notifies have no class payload.

### 7.2 Fidelity residuals (visible, bounded)

1. **Guildhall POI graybox floors + floating furniture** — 1,637 `GB_Floor_2x2`
   at mismatched heights. Content project, not a loader tweak.
2. **KF16 sign legibility at 27 m** — letters are gold, front-facing, emission
   `(1.0, 0.62, 0.20) × 0.10`; still low-contrast in the frame.
3. **White glass/emissive plates** and the mirrored `PICK LOCK` reflection — repro
   under Vulkan first; no guessed material change.
4. **Den brightness** — my parchment-region measurement is p50 62.9 vs the UE
   reference 110.3 (whole-crop), so the gap is larger than the 43.5/52.6 ROI
   figure suggests. Lumen/GI, not tonemapping.
5. **Shipped sliding gate** — capture-only closed leaves remain correct until a
   route crosses it.
6. **Probe exit warning** — `probe_leak` is now clean under
   `TAT2_NO_DEN_PROBE=1`; without it the Den RID warning can still appear.
7. **Startscreen/menu** — rain and neon are present; the reference's exact
   exposure and the gold-mask G/R ratio remain approximations.
8. **Reflection/probe state** — 7 texture RIDs may warn at finalization on the
   Den probe; not a script error.

### 7.3 Product/UX

- **Free-play entry** is a real Den map-table entry; no longer a debug button.
- **Settings**: 54.54 is authored; `fov_migrated` is only set on a real slider
  change; locale is persisted and applied. New settings keys must join the
  schema-v2 path.
- **Co-op**: add a scripted two-client E2E (tier 5) and host authority for
  loot/AI/mission before claiming co-op parity.

### 7.4 Milestone record (corrected)

- **M3**: Chameleon/Cotter binding, cosmetics, revive, blackjack, traversal
  (dodge/slide/mantle/climb), 3P locomotion, tools/potions, thiefsign.
- **M4 (substantially, not fully)**: AI sensing, authored patrols and waits,
  surface loudness, interaction LOS, 96 clue facts / quest graphs, detector
  spine/power/turrets/cameras/wards. **Not implemented:** navmesh, guard/civilian
  archetypes, breakables, vault doors/windows, full power grid.
- **M5 (partial)**: Wwise media (5,018 Ogg), event map, beds/footsteps/VO,
  host-validated co-op transport, joypad. **Not implemented:** RTPCs,
  switches/states, full authority/replication.
- **M6 (partial)**: mission/Den/FTUE runner, UI defects, CJK fonts, 8 translations
  registered, gamepad focus, countdown, HUD identity. **Not fully:** all UI
  strings through `tr()` and full layout parity.
- **Track C**: materials fallback → 0, NPR/SNN, X-ray, weather/roof occlusion,
  lens drops, volumetric/clouds — done; `reports/track-c.md`.
- **E2E backlog**: 264/264 unmasked.

---

## 8. Known data deltas and how to treat them

| Delta | Evidence | Treatment |
|---|---|---|
| breakables 1,563 vs audit 1,897 | 4 breakable component classes; self-destruct components (342) are a different mechanic | issue #3; revisit in M4 |
| secret switches 12 vs "9+" | toggle-switch components + secret-labelled switches | accepted, recorded in devices.json |
| Niagara 3,695 vs earlier 3,699 | pre-wipe data had 4 extra records; clean extraction is exactly 3,695 authored across 37 asset paths, of which 387 `NS_Candelabras_Flame_Out` are inactive (bAutoActivate=false), leaving 3,308 active across 36 spawned systems | resolved |
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
git status --short                                  # clean
make audit                                          # exit 0, all groups fresh, 0 unexpected errors
python3 tools/check_uid_duplicates.py game --json   # 0/0
tools/godot --headless --path game --script tools/check_scripts_compile.gd   # 69/0
tools/godot --headless --path game --script res://tests/run_tests.gd         # fails=0 (59 suites)
tools/godot --headless --path game --script res://tests/test_m2_player.gd    # fails=0
tools/godot --headless --path game --script res://tests/probe_door_walk.gd   # PASS
tools/godot --headless --path game --script res://tests/probe_viewmodel_truth.gd  # PASS
tools/godot --headless --path game --script res://tests/probe_niagara.gd     # PASS
tools/godot --headless --path game --script res://probe_leak.gd              # as documented
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd # 264/264
git push origin main
```

Any wave that changes rendering, materials, traversal or mission flow also needs:

- a serialized Vulkan capture proving the visual change (startscreen, Guildhall
  KF16/KF17, Den KF10, free play);
- a `docs/reports/<wave>.md` with measured evidence (ROI stats, logs, gates);
- `docs/FIDELITY_GAPS.md` updated with what remains;
- this handoff refreshed (HEAD, gates, open work).

If a gate fails, find the cause. Do not lower the expectation, skip the test or
re-baseline the numbers without recording the defect and its owner.
