# Review-map baker and in-game review mode (2026-11-24)

Status: **pipeline implemented; the in-game review and offscreen captures are
verified on the full Guildhall.** The baked editor master could not create a
Vulkan device in a visible editor session on the reference 8 GB laptop GPU
(full master: 562 lights, 33k nodes, 3.4 GB headless RSS); opening an
87 MB per-sublevel POI scene was still on the splash after 2.5 min and was
aborted. Treat the baked scenes as an editor archive on a larger GPU, and use
the in-game capture sweep for review on this machine.

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
| Manifest consistency checks | lights/occluders/decals/Niagara exact; collision ≥ loader; mesh counts informational (fog extras vs loader-added doors/loot make both directions legal) |

### Measured — `mission_lobby` (menu map, discovery fallback)

3 sublevels, **4.21 s**, **66.3 MB** total: `MissionLobby_Geo3.scn` 25.8 MB,
`MissionLobby_Periphery.scn` 40.5 MB, empty `MissionLobby_P.scn` 718 B.
2,105 mesh instances, 969 occluders, 22 lights, 2,093 collision shapes,
15 emissive plates. In-game review mode loaded it headless in 20 frames with
3,560 nodes.

### Measured — `guildhall` (full bake)

**18.76 s**, **371 MB** across 18 scenes (16 sublevels + `world.scn` +
`review.tscn`). Loader: 62,952 mesh instances, 64,748 draw instances, 11,350
surfaces, 6,076 chunks, 330 collision bodies, 24,326 shapes, 1,479 occluders,
1,599 Niagara placements. Tagged: 33,356 nodes, 312 `beam_lines`, 481
`emissive_plate`, 330 `collision_only`, 0 `world_label`.

Largest scenes: `Building_Guildhall_POI.scn` 87 MB, `Guildhall_PeripheryA.scn`
130 MB, `Guildhall_SkyboxGeo.scn` 46 MB, `Building_Guildhall_POI_3rdFloor.scn`
40 MB. `world.scn` (4 KB) instances the per-sublevel scenes; `review.tscn`
(9 KB) adds the environment, 562 lights and six bookmarks. Headless master
load: **9.1 s**, **3.4 GB RSS**, 0 script errors with `--quit-after 5`.

`Guildhall_LocalVolumetric` exposed a false consistency failure: its 27 loader
`mesh_instances` are fog/extras without a `ue_mesh`, and the tagger correctly
records 0 draw instances. The mesh-instance check is now informational in both
directions; exact lights/decals/Niagara and ≥ collision checks still gate the
bake. After that fix the bake exits 0 with `status=ok`.

### Guildhall review caveats

The master instances every sublevel, so it carries **562 lights** and **1,479
occluders** versus the shipped single-call 160/768. That is a review
convenience, not a performance measurement. The Lighting toggle hides them.
`Guildhall_SkyboxGeo` is 33,547 MultiMesh instances (208 batch nodes), so the
node count stays at 33k; the editor can open the master but will be sluggish
on a cold cache. Prefer toggling whole sublevels off rather than editing
individual chunk nodes.

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

Loads the selected map with the real `LevelLoader` in **one call** (the shipped
path: all sublevels, one 160-light budget, cross-sublevel dedupe), then tags
draw nodes from the loader's `source_sublevel` provenance. No mission, player,
AI or gameplay. Measured: 31,734 tagged nodes, 5,923 draw nodes, 160 lights,
10,826 surfaces; `REVIEW ready` after ~30 s on a warm cache. An earlier
per-sublevel loop multiplied the budget to 562 lights and shader variants and
never left the splash; the single call is the only supported path.

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
toggles and the last action. The review harness now matches the shipped single
budget, so it no longer over-lights the world.

**Capture without window presentation:** `make review-capture MAP=guildhall`
runs the same scene offscreen in six bookmark steps and writes PNGs to
`build/qa/review/guildhall/`. This is also the fix for a black-looking window:
the viewport is rendering (verified captures show the night exterior, library
and vault), but an occluded/minimized Wayland window can present black. Click
the window or use the capture target. The `Foyer` bookmark currently renders
black (camera inside the dark shell); the Library and Vault bookmarks are
usable.

### First Guildhall captures (2026-11-24)

Six bookmark captures at 1280×720 (`make review-capture MAP=guildhall`):
`KF16_Gate` (night exterior, HUD), `Foyer` (black — camera inside the dark
shell), `Library` (dark interior, staircase), `POI_Lounge`, `Safe_Room`,
`Vault` (vault geometry plus floating cyan/blue billboard sprites). The world
renders; the window presentation is the only black-window failure mode.

A paired sweep with `--hide=Beams` isolates the long thin lines:

| View | Cropped RMSE (normal vs no beams) | Reading |
|---|---:|---|
| Vault | 3.20 % | beam cards clearly visible |
| Library | 0.90 % | beams in view |
| KF16 gate | 0.64 % | distant beams |
| Foyer / POI lounge | 0.00 % | no beams in frame |

This confirms the long white/gold dashed lines are the 312 beam-tagged meshes
(authored security/device beams plus the `tat_beam` shader), not a loader
artifact. The cyan/blue blobs remain with beams hidden; they are Niagara or
billboard props and belong to a separate rendering/placement fix. The beam
orientation/placement fix is **not** part of this tool.

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
- **The full Guildhall bake is verified; rendered/visual checks are not.** The
  master loads headless at 9.1 s / 3.4 GB; opening it in a visible editor and
  toggling layers is the remaining manual step.
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
