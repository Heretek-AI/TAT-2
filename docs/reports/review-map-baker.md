# Review-map baker and in-game review mode (2026-11-24)

Status: **pipeline implemented and verified on `thieves_den` + `mission_lobby`**.
The full Guildhall bake is deliberately deferred to a quiet machine (the
measurement worker owned the GPU this hour); the integrator runs it next.

## What it is

Three ways to look at the same real, static `LevelLoader` world without
starting a mission, a player, guards, loot or gameplay:

| Surface | Entry point | What it loads |
|---|---|---|
| Headless baker | `make bake-review MAP=guildhall` → `game/scenes/review/guildhall/` | One `LevelLoader.load_sublevels_async()` call per `.tatlevel.json`, tagged and packed |
| Editor | `make editor`, then the **TAT-2 Review** dock | The baked per-sublevel scenes, instanced by `review.tscn` |
| In-game free camera | `make review MAP=guildhall` | The real sublevels again, loaded live through `LevelLoader` (never the baked scenes) |

All three share `game/addons/tat2_review/`:

- `review_map_data.gd` — map → sublevel resolution + bookmark table.
- `review_tagger.gd` — the tagging vocabulary and stats collector.
- `review_filters.gd` — visibility predicates for the dock and review mode.
- `review_baker.gd` — the bake itself. `tools/bake_review_map.gd` is a thin
  `SceneTree` CLI wrapper so the same class is callable from tests/dock.

### Why one load per sublevel

`LevelLoader` builds every sublevel into the same flat parent and records no
source-sublevel metadata on the nodes (loader bookkeeping names counts, not
ancestry). The bake therefore calls the loader once per sublevel into a
container named after the `.tatlevel.json` stem. That container **is** the
sublevel identity (`review_sublevel`), and no loader edit was needed — the
loader file is owned by another worker this wave.

Contract-specific sublevels come from the mission controller's own
`_map_id_to_sublevels()`. The review passes `contract_order = 0`, which resolves
to the first authored contract whose `map_id` matches (Den → 1, Guildhall → 2,
Old Manor → 3) instead of duplicating a map→order table. `mission_lobby` has no
mission row, so a directory-scan fallback finds
`res://data/generated/levels/MissionLobby/`; the manifest records
`resolution.source = "directory-discovery"`.

## Commands

```bash
# Bake one map (default OUT = res://scenes/review/<map>)
make bake-review MAP=guildhall
make bake-review MAP=thieves_den
make bake-review MAP=mission_lobby

# Exact CLI (note: --script must be an absolute path; see "API friction")
tools/godot --headless --path game --script "$PWD/tools/bake_review_map.gd" \
    -- --map=guildhall --out=res://scenes/review/guildhall

# Editor with the dock
make editor

# In-game free camera (no mission/player)
make review MAP=guildhall
```

The baker exits non-zero on a resolution, pack, save or loader/tag consistency
failure and prints one machine-readable summary:

```
REVIEW_BAKE summary map=thieves_den status=ok sublevels=3 scenes=5 bytes=28208855 beams=0 labels=0 emissive=14 bake_ms=4083 out=res://scenes/review/thieves_den
```

## Outputs

Under `--out` (git-ignored, because they embed extracted meshes/materials):

| File | Meaning |
|---|---|
| `<Sublevel>.scn` | Binary `PackedScene` for one sublevel, built and tagged by the real loader |
| `world.scn` | Assembly of the per-sublevel scenes (instances, no editor extras) |
| `review.tscn` | Master: per-sublevel scene **instances** + bookmarks + review `WorldEnvironment`/moon/camera |
| `review_manifest.json` | Git SHA, map, seed, resolution source, loader counts, tag counts, per-sublevel AABB, issues, bookmarks, sizes, checks |

`world.scn`/`review.tscn` are **instancing** masters (a few KB), not a second
copy of the geometry. A single combined-loader world bake would duplicate every
mesh resource into one file; it is intentionally not the default. Per-sublevel
scenes are the required path and the only scenes that own geometry.

### Measured — `thieves_den` (285 mesh instances, 3 sublevels)

Run: `make bake-review MAP=thieves_den` on 2026-11-24, HEAD `8eb19ca`,
Godot 4.7.2 headless, `XDG_DATA_HOME=/tmp/opencode/r1-data`.

| Metric | Value |
|---|---|
| Bake wall time (3 loads + pack/save/assembly) | **4.08 s** (test harness 5.3 s including engine start) |
| Loader mesh instances / chunks / surfaces | 285 / 180 / 321 |
| Nodes in baked scenes / draw instances | 437 / 296 |
| Lights (loader budget + 1 GI fill) | 8 + 1 |
| Collision bodies / shapes | 33 / 207 |
| Decals | 3 |
| Niagara systems / placements | 2 / 11 |
| Issue tags | `emissive_plate` 14 · `collision_only` 33 · `beam_lines` 0 · `world_label` 0 |
| Roles | door 2 · loot 14 · device 1 |
| `ThievesDen_Geo.scn` | **17,498,460 B** (16.7 MiB) |
| `ThievesDenTest_P.scn` | **6,290,966 B** (6.0 MiB) |
| `ThievesDenTest_Periphery.scn` | **4,414,565 B** (4.2 MiB) |
| `world.scn` / `review.tscn` | 1,389 B / 3,475 B |
| Total output | 28,208,855 B (26.9 MiB) |
| Manifest consistency checks | all pass (lights, occluders, decals, Niagara systems exact; collision/mesh counts ≥ loader) |

### Measured — `mission_lobby` (menu map, discovery fallback)

3 sublevels, **4.21 s**, **66.3 MB** total: `MissionLobby_Geo3.scn` 25.8 MB,
`MissionLobby_Periphery.scn` 40.5 MB, empty `MissionLobby_P.scn` 718 B.
2,105 mesh instances, 969 occluders, 22 lights, 2,093 collision shapes,
15 emissive plates. In-game review mode loaded it headless in 20 frames with
3,560 nodes.

### Guildhall expectation (not run)

The thirteen Guildhall sublevels are built from the same loader; unique-mesh
counts are 57 (Geometry), 59 (Gameplay), 162 (SkyboxGeo), 194 (POI 3rd floor),
487 (POI), 560 (PeripheryA), so scenes are expected in the tens of MB each and
the sum will be large but the instancing masters stay tiny. `PeripheryA`
(12,461 instances) and `SkyboxGeo` (33,547) are mostly MultiMesh batches; the
packed size scales with unique meshes, not instances. The full bake and the
Guildhall visual checks are the integrator's step.

## Tagging vocabulary

Every baked node carries `metadata/review_sublevel` and
`metadata/review_kind`; optional keys only exist when applicable.

| Key | Values |
|---|---|
| `review_sublevel` | `.tatlevel.json` stem (`ThievesDen_Geo`, `Guildhall_PeripheryA`, …) |
| `review_kind` | `mesh`, `multimesh`, `landscape`, `light`, `decal`, `niagara`, `collision`, `occluder`, `fog`, `bookmark`, `environment`, `group` |
| `review_issue` | `beam_lines`, `world_label`, `emissive_plate`, `collision_only` |
| `review_role` | `door`, `loot`, `device` (dock convenience filters) |

- `beam_lines` — the authored `ue_mesh` path contains `LightBeam`, or any
  surface/override material is the loader's `tat_beam.gdshader`. This is the
  long thin white/gold line class in the review screenshots.
- `world_label` — `Label3D`, or a billboard `Sprite3D` (the loader does not
  currently build floating labels; the tagger is ready for them).
- `emissive_plate` — `StandardMaterial3D.emission_enabled` with energy > 0.5, or
  an emissive/HDR shader (`tat_hdr_emissive`, `tat_emissive_cpd`) or a shader
  `energy`/`intensity` parameter > 0.5. Cyan plates are the main hit.
- `collision_only` — a `StaticBody3D` (invisible collision, no visual).
- `fog` extends the requested vocabulary: `Guildhall_LocalVolumetric` builds
  `FogVolume`s that the Lighting toggle must be able to hide.

Nodes are renamed from the authored mesh stem (e.g. `SM_Zipwire_1`) so the
editor tree is readable; names are cosmetic.

## Editor dock

`game/addons/tat2_review/` is enabled by the checked-in
`[editor_plugins]` entry in `game/project.godot` (Project > Plugins can also
toggle it).

- Map dropdown (`guildhall`, `thieves_den`, `mission_lobby`, `old_manor`).
- **Bake / Refresh** runs the same headless CLI through `OS.execute`
  (blocking; the log tail is shown in the dock), then opens the new
  `review.tscn`.
- **Open review scene**.
- Checkboxes: Periphery / POI / Gameplay / Lighting / Decals / Collision /
  Niagara / Beams / World labels / Emissive plates / Doors / Loot / Devices.
- Six bookmark buttons (F1–F6). Each selects the `Marker3D`; if the running
  editor exposes a viewport `focus_selected`, that is called, otherwise the
  dock says "press F to frame it". No fake camera control.
- Count label: sublevels, nodes, meshes, lights, decals, collision, issue counts.
- Toggle state lives in the scene root's `review_toggles` metadata and is
  re-applied when the edited scene changes. Nothing is written into the baked
  per-sublevel scenes.

**Verification:** the plugin and dock parsed with the project-wide compile gate,
and a headless editor run (`--editor --headless --quit-after 400`) initialised
the plugin, built the dock and ran its `_process` with **no script/format
errors**. Manual clicking in a visible editor was not verified this wave
(GUI/Xvfb is deferred to the integrator). Nodes inside instanced sub-scenes are
set through `Node3D.visible`, which the editor accepts as an instance override
in a normal session; this is called out as unverified rather than claimed.

## In-game review mode (`game/scenes/review_mode.tscn`)

Loads the selected map with the real `LevelLoader` (one call per sublevel, no
mission, player, AI or gameplay), then:

| Input | Action |
|---|---|
| WASD + LMB | Move / toggle mouse capture |
| Shift | 4× speed |
| Q / E | Down / up |
| 1–9, 0 | Toggle Periphery, POI, Gameplay, Lighting, Decals, Collision, Niagara, Beams, World labels, Emissive plates |
| F1–F6 | Bookmarks (KF16 gate, foyer, library, POI lounge, safe room, vault on Guildhall) |
| P | PNG to `user://review_captures/` |
| Esc | Quit |

The HUD is built in `review_mode.gd` (never `hud.gd`) and shows counts, active
toggles and the last action. Per-sublevel loads each get the loader's 160-light
budget; the shipped game loads all sublevels in one call with a single budget,
so the review harness can show more lights than a real run. This is a review
convenience, not gameplay authority.

## Honest limits

- **Snapshot, no gameplay authority.** Baked scenes contain static loader
  output only: no player, AI, guards, loot items, doors, devices, missions,
  save state, weather or streaming. Doors/loot/device toggles filter authored
  sublevel geometry by path/role, not live spawned actors.
- **Per-sublevel lights are independent.** The editor master instances every
  sublevel, so combined lights can exceed the game's 160-light budget; the
  Lighting toggle hides all of them.
- **Cross-sublevel duplicates reappear in the editor assembly.** The single-call
  loader dedupes repeated meshes across sublevels; separate scenes cannot see
  each other. Review mode (live, one call per sublevel) has the same split.
- **The full Guildhall bake and all rendered/visual checks are deferred.** This
  report claims only the measured Den/lobby numbers above.
- **Manual dock interaction and the in-game window are not verified** on this
  shared-machine hour (no Xvfb, no windowed Godot, no GPU capture).
- **`world.scn` is an assembly of per-sublevel scenes**, not a second
  single-call bake (the per-sublevel scenes are the required, geometry-owning
  output). A >150 MB master or any pack failure is removed and recorded; none
  occurred here.

## API friction found

- `--script tools/…` with `--path game` resolves under `res://tools/…` and
  fails; the CLI must be passed as an absolute path (`$PWD/tools/…`). The
  Makefile and dock do this.
- `MissionController._map_id_to_sublevels()` mixes map base sublevels with the
  *active* contract's sublevels. Passing it the wrong order produced a stray
  `Guildhall_Contract_02` in the Den bake; passing `0` and resolving the map's
  own first contract fixes it without a second table.
- `LevelLoader` has no per-node source-sublevel bookkeeping and no public hook
  to observe it, hence one load per sublevel (documented above).
- Editor camera focus has no stable public API across 4.x builds; the dock
  selects the marker and documents `F` instead of driving a viewport camera.
- Saving runtime-built scenes needs an explicit `owner` walk; unnamed loader
  nodes otherwise pack as `@MeshInstance3D@N` and fill the editor tree with
  unreadable names.
