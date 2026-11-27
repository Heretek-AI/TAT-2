# P2-NAV navmesh spike — 2026-11-26

| | |
|---|---|
| lane | P2-NAV / B2.2a (spike only; no runtime navigation change) |
| base | `8a3ad62` (`main`; P1 complete, corrected capture at `fafb78f`) |
| worktree | `/home/john/.local/share/opencode/worktree/318f41/p2-navmesh` |
| branch | `w10/p2-navmesh` |
| extractor | CUE4Parse `1.2.2.202611`, `EGame.GAME_UE5_5`, Oodle cache payloads |
| engine | Godot `4.7.2.stable.official.ed1daf0bf`, headless, one Godot under `flock` |
| **verdict** | **`NAV_TILE_BYTES_PRESENT`** — the payload was never missing from the cooked archive; the JSON dump dropped it |
| extraction | `NAV_DETOUR_TILES tiles=2958 polys=14930 verts=40126 offmesh=221` |
| consumer spike | `NAV_SPIKE_SUMMARY checks=16 fails=0`; doorway `waypoints=3` |
| runtime | `game/src/ai/nav_steering.gd`, the guard/civilian FSM and every `NavigationRegion3D` in the game are untouched |

## 1. Verdict

The cooked `ARecastNavMesh` in `Maps/Guildhall/Guildhall_P.umap` carries the full
tile data. CUE4Parse already decodes it; the property dump did not show it because
two fields are explicitly excluded from JSON:

| CUE4Parse type | Field | Why the dump is empty |
|---|---|---|
| `CUE4Parse.UE4.Objects.NavigationSystem.NavMesh.FRecastTileData` | `DetourMeshTile? Tile` | `[JsonIgnore]` — the decoded Detour tile (vertices, convex polys, BV tree, off-mesh links) is parsed but never serialised |
| `CUE4Parse.UE4.Assets.Exports.NavigationSystem.FCompressedTileCacheData` | `byte[] CompressedData` | `[JsonIgnore]` — the exact Oodle-compressed Recast layer payload is read but never serialised |

`FPImplRecastNavMesh` and `FRecastTileData` constructors read the bytes from the
archive; the existing JSON kept only `TileDataSize`, `SizeInfo` and the Recast
layer header. There is **no extraction API gap**. The only gap was in the
property-dump serialisation, and the new `nav` command bypasses it.

There is no `NAV_TILE_BYTES_UNAVAILABLE` finding and **no bake is required or
run**. The P3 bake path is not the right answer: the authored navmesh already
contains the tile borders, areas, off-mesh links and agent parameters a bake from
collision would have to approximate.

## 2. What the extractor now emits

`tools/tat-extract/Exporter.cs` gained one command, `nav` (`Program.cs` dispatch
and usage updated). It loads the `.umap`, finds `ARecastNavMesh`, and writes:

- `<out>/nav/<map>.json` — schema `tat2.nav_tiles/1`:
  - `DetourNavMeshParams` (tile 988 x 988 cm, `WalkableHeight 240`,
    `WalkableRadius 45`, `WalkableClimb 45`, `BvQuantFactor` table);
  - per tile: `tx/ty/layer/version/resolution`, `bmin/bmax`, `SizeInfo`,
    decoded `verts` (nav-space cm), ground `polys` (convex index arrays),
    `poly_flags`, `poly_areas`, `poly_types`, `offmesh` connections, and the
    Recast cache header + compressed/raw SHA-256;
  - map totals: tile/poly/vert/off-mesh counts, area/flag histograms, cache
    byte totals and Oodle decompress success/failure.
- `<out>/nav/<map>.cache.bin` — the concatenated exact `CompressedData`
  payloads (indexed by each tile's `cache.offset`/`cache.compressed_size`).

The JSON's own `SizeInfo` already matched the shipped actor (2,958 tiles), which
is why the spike could state the expected totals before extracting the payload.

### Measured extraction

| metric | value |
|---|---|
| tiles | **2,958** (all `IsValid`) |
| polys | **14,930** = 14,709 walkable + **221 off-mesh** (stripped from `polys`, emitted as `offmesh`) |
| vertices | **40,126** authored; **30,918** after exact-cm dedupe across tile borders |
| off-mesh connections | **221**, spread over **103** tiles |
| tile-data bytes | 3,974,656 (`TileDataSize` sum; decoded structure) |
| Recast layer cache | **2,302,750** compressed → **31,993,728** uncompressed; **2,958/2,958** Oodle decompressions OK, **0** failures |
| extraction time | **144.7 ms** inside `NavDoc` (package load excluded); the per-file wall including load was **0.5 s** |
| artifacts | JSON 3.2 MB, `cache.bin` 2.2 MB (both under `/tmp`, **not** committed) |
| JSON sha256 | `33d6594fb09ad250170abb47e8ed4a009f5f0c6be01361ab0b64a5fbd2bd13b8` (re-extracted twice; timings are stderr-only so the file is deterministic) |
| cache sha256 | `a4f67e9a5462d66f99687ffb67b7f975b2e0d894ec04cbc81bfcb288aab74bfb` |

Authored parameters recovered from `DetourNavMeshParams` (cm):

```
WalkableHeight=240  WalkableRadius=45  WalkableClimb=45
TileWidth=988  TileHeight=988  MaxTiles=13448
BvQuantFactor = 0.02631579 / 0.05263158 / 0.05263158
NavMeshVersion = NAVMESHVER_TILE_RESOLUTIONS_AGENTMAXSTEPHEIGHT
```

Polygon areas (authored `SupportedAreas`): **63 `NavArea_Default` = 14,558**,
**3 `NavArea_Bushes_C` = 144**, **1 `NavArea_Obstacle` = 7**. Every poly has
flag `1` (`DT_POLYFLAGS_WALK`). Note that UE maps **`NavArea_Default` to 63**
while `NavArea_Null` is 0; area 63 is Recast's `RC_WALKABLE_AREA` (the default
poly area), not `RC_NULL_AREA` (0), so refusing area 0 is correct and never
drops default polys.

> Producer caveat: `ARecastNavMesh.AgentHeight`/`AgentRadius` read as `0.0` in
> the output because CUE4Parse's `GetOrDefault` does not resolve the nested
> `NavDataConfig` in this actor. The authored values are present as
> `NavDataConfig.AgentRadius 45 / AgentHeight 240 / AgentStepHeight 45` and as
> `DetourNavMeshParams` above. Use the Detour params; do not report 0 as
> authored. This is a small producer gap, not a data gap.

## 3. Consumer spike — `build/qa/navmesh_spike.gd`

The probe reads the extracted JSON, builds a Godot `NavigationMesh` from the
**authored** Detour polys, adds one `NavigationRegion3D` to the default world
map and measures parse/build/map-sync/path. It never bakes, never edits
`nav_steering.gd`, never registers a region in the game's runtime (the only
region is the probe's own headless `SceneTree`) and writes no file.

- Coordinate conversion: nav-space Recast is Y-up centimetres; the port's
  `parse_tables.ue_mat4_to_godot_trs` places Godot as `(x, z, y) * 0.01`. The
  probe uses the inverse: `Vector3(nav.x * 0.01, nav.y * 0.01, -nav.z * 0.01)`.
  This is measured, not assumed: the authored doorless doorway at Godot
  `(12.5, 11.5, -45.0)` projects onto the navmesh within **0.05 m**; an inverted
  Z or a missing Y/Z swap would miss by metres.
- Exact-cm dedupe merges tile-border vertices (40,126 → 30,918).
- Ground polys only: every polygon with index `< OffMeshBase`; the 221
  off-mesh polys are emitted separately and are **not yet consumed** by the
  probe.
- Map settings for the authored cm mesh: `cell_size=0.01`,
  `edge_connection_margin=0.05` (consumer settings; the authored data is not
  changed).
- The server needs **~67–92 physics frames / 1.0–1.4 s** to commit 14,709 polys;
  the probe waits until a probe point is queryable instead of trusting the
  first iteration id (querying too early returns the empty-map origin).

### Measured consumer run (representative)

```
NAV_BUILD verts=30918 polys=14709 skipped=0 max_poly_verts=6 read_ms=7 parse_ms=93 build_ms=54
NAV_MAP synced=true frames=77 iteration=3 regions=1 cell=0.010 margin=0.050 sync_ms=1148
NAV_DOOR_PATH actor=BP_Doorless_Civic_DoorA_Wall_Int_6x6_C_281 ...
  door=(12.5, 11.5, -45.0) normal=(0.0, 0.0, -1.0)
  snapped_a=(12.5, 11.55, -47.2) snapped_b=(13.3, 11.55, -43.13)
  snap_dist=(0.05,0.87) waypoints=3 length_m=4.15 straight_m=4.15
NAV_LOAD_MS read=7 parse=93 build=54 sync=1148 total=1370 mem_mb=61.8
NAV_SPIKE_SUMMARY checks=16 fails=0
```

Runs measured `sync_ms` **1,009–1,265** and total **1,194–1,492 ms** (this run
1,148 / 1,370 ms), and 59.3–61.8 MB static memory, so treat **1.0–1.5 s** as the
headless single-map load budget. This is the critical follow-up number: do not
commit a 14.7k-poly region on the main thread at mission start without a
prebuilt/asynchronous path.

### Known doorway path

The committed probe uses the authored **doorless** interior doorway
`BP_Doorless_Civic_DoorA_Wall_Int_6x6_C_281` in
`Building_Guildhall_POI.tatlevel.json`. A doorway is emitted as one record per
leaf (`Pivot` + `SecondPivot`); the probe uses their midpoint and the aligned
local +Z (record basis column 2), then places points ±2.2 m either side. Result:
**3 waypoints, 4.15 m path, 4.15 m straight**, both endpoints project onto the
navmesh (0.05 m / 0.87 m), and the path reaches the far side exactly.

The **prison door** is the useful negative control, not a defect:

```
--door=BP_Prison_WallA_DoorwayB_6x6_C_0   (same level)
NAV_DOOR_PATH ... door=(1.0, 36.5, -64.0) normal=(1.0, 0.0, 0.0)
  snapped_a=(3.2, 36.6, -64.0) snapped_b=(-1.71, 36.6, -64.0)
  waypoints=4 length_m=3.58 straight_m=4.91
  FAIL path reaches the far side ... last waypoint 1.33 m from target
  FAIL path is not a partial/short path (3.58 >= 4.91 - 0.5)
```

The baked navmesh **cuts the closed prison doorway**; `map_get_path` returns a
partial path that stops 1.33 m short of the far side. That is the authored door
model, and the link is in the extracted payload: the off-mesh data carries
endpoints at Godot `(0.5, 36.5, -63.6)` and `(-2.5, 36.5, -63.6)` across the
doorway (radius 100 cm, raw flags 64; the adjacent tile carries the same link,
so a consumer must dedupe endpoints). The probe does not yet consume it, which
is why the path stops short. A consumer must add the **80 logical links** from
the 221 raw off-mesh records (35 bidirectional; 123 exact unordered pairs
before the parallel-copy merge) as `NavigationLink3D` (and honour
`GA_NavLink_SwingingDoor` / `ST_OffNavLink`) rather than patch the mesh or bake
around it.


## 4. Authored vs port decision

| item | status |
|---|---|
| tile grid, borders, 14,930 polys, 221 off-mesh records (80 logical links), areas | **authored**, decoded losslessly from the cooked navmesh (CUE4Parse typed reader); the exact compressed cache payload is emitted separately |
| `WalkableHeight/Radius/Climb 240/45/45` | **authored** (`DetourNavMeshParams`; matches `NavDataConfig` 240/45/45) |
| tile width/height 988 cm, `MaxTiles 13448` | **authored** |
| area IDs `63/3/1` (Guildhall) | **authored**, via `SupportedAreas` (`NavArea_Default/Bushes/Obstacle`); Old Manor uses `Door=3/Bushes=4`, so the table is per-map, never a global `63/62/1/3/4` list |
| nav→Godot `(x, y, -z) * 0.01` | **port mapping** matching `parse_tables.ue_mat4_to_godot_trs`; not an authored field |
| `cell_size=0.01`, `edge_connection_margin=0.05` | **PORT_DECISION** for this consumer spike; the authored edges are cm-scale and the default 0.25 m map cell would quantise them away |
| one `NavigationRegion3D` for the whole map | **spike decision**; runtime region ownership is not claimed |
| doorway ±2.2 m sample distance | **probe decision**; the doorway centre/normal are authored |
| no off-mesh/door-link consumer | **not implemented**; measured gap, see §3 |

**Not parity.** The spike proves the authored tile set is extractable and
consumable. It does not claim a `NavigationRegion3D` in the shipped game, a guard
path, or a parity score. `nav_steering.gd` still degrades to straight lines when
no region exists; that is unchanged.

## 5. Next decision — **P1 Detour consumer**

1. **P2 decode: done.** CUE4Parse already decodes the tile; `nav` emits it. Do
   not write a Detour decoder.
2. **P3 bake: not taken.** It would replace authored data (tile borders, areas,
   off-mesh links, agent parameters) with a collision approximation and add a
   bake pass per map. The measured authored set is complete and cheaper.
3. **P1 consumer (landed N-P0/P1/P2, 2026-11-27):**
   - `tools/parse_nav.py` converts the `tat2.nav_tiles/1` dump into a compact,
     versioned runtime asset under the gitignored generated tree (`nav/<map>.nav.bin`
     + manifest); the JSON parse is 68–93 ms, the binary load is ~30-40 ms;
   - `game/src/ai/nav_runtime.gd` builds one `NavigationMesh`/`NavigationRegion3D`
     per map with **cell 0.01 / margin 0.05 / link radius 1.0**, behind
     `TAT2_NAV=off|on` (default off), and waits for the map commit before guards
     spawn (budget 1.0–1.5 s headless);
   - the **80 logical links** (221 raw records) are `NavigationLink3D`s; door
     links come from the leaf midpoint + normal, enabled at `open_angle_deg() >
     70`, and the co-located `NavLinkFront/Back` actors are not used;
   - area ids are read per map from `SupportedAreas`; never treat 63 as Recast's
     null area and never hard-code `63/62/1/3/4`;
   - the runtime probe (`build/qa/nav_runtime_probe.gd`) proves the 3-waypoint
     doorway, the prison link on/off path and the off/missing-asset controls.
4. Re-measure on the real client, not only headless, before calling it parity.

## 6. Gate evidence and integration note

| gate | result |
|---|---|
| `tools/check_scripts_compile.gd` | **213 checked, 0 broken** |
| `build/qa/navmesh_spike.sh` | **`NAV_SPIKE_SUMMARY checks=16 fails=0`** (exit 0) |
| `make audit` | **expected fail-closed**: `infrastructure root:tools/tat-extract/Exporter.cs` and `Program.cs` changed since the committed baseline. The shared `tools/audit_baseline.json` is integrator-owned; **this lane must not refresh it**. The integrator rebuilds the extractor and runs `make audit-refresh-stamps` at the merged HEAD. The same run also reports `vgmstream` missing in this checkout (environment, unrelated to nav). |

No `game/tests/` suite was registered: this is a spike probe under `build/qa/`,
not a runtime feature. The runtime gate set (`run_tests`, E2E, probes) is
unchanged by this lane.

## 7. Reproduction

```bash
# 1. one-time extractor build (CUE4Parse binaries are gitignored)
make build-extractor

# 2. extract the Guildhall navmesh tiles to a throwaway tree
tools/tat-extract/bin/Release/net10.0/tat-extract nav \
  --game "$HOME/.local/share/Steam/steamapps/common/Thick As Thieves" \
  --usmap "$PWD/tools/ue4ss/output/TAT-5.5.4-148559+++TAT+tat_release_nosrc-30afe5ff.usmap" \
  --filter 'Maps/Guildhall/Guildhall_P\.umap$' \
  --out /tmp/opencode/nav-spike

# 3. headless consumer + doorway probe
flock /tmp/opencode/tat2-godot.lock -c \
  "tools/godot --headless --path game --script $PWD/build/qa/navmesh_spike.gd \
   -- --nav=/tmp/opencode/nav-spike/nav/Maps/Guildhall/Guildhall_P.json"

# or the wrapper (extracts if missing, then probes; writes only under /tmp)
build/qa/navmesh_spike.sh
```

The wrapper auto-finds the main checkout's `tools/ue4ss/output/*.usmap` when
run from a worktree, and reads `TAT_GAME`, `TAT_USMAP`, `TAT2_NAV_OUT` and
`TAT2_NAV_JSON`. The probe also accepts `--door=<actor>` and `--level=<res path>`
for the negative-control run above.

## 8. Files

- `tools/tat-extract/Exporter.cs` — `nav` command + `NavDoc` (decoded tile,
  Recast cache payload, hashes, counts)
- `tools/tat-extract/Program.cs` — `nav` dispatch/usage
- `build/qa/navmesh_spike.gd` — headless Detour-tile consumer probe
- `build/qa/navmesh_spike.sh` — extract-if-missing + probe wrapper
- this report

No generated navmesh data, no change to `game/src/ai/nav_steering.gd`, the FSM,
`level_loader.gd`, `mission_controller.gd` or any game asset.

## 9. Update — the N-P0/N-P1/N-P2 consumer (2026-11-27)

The spike's forward-looking "221 links" phrasing is superseded by the measured
merge: 221 raw off-mesh records -> 123 exact unordered pairs -> **80 logical
links** for Guildhall (35 bidirectional, 45 one-way). The same producer gives
Old Manor 216 -> 113 -> **64** (15 bidirectional) and FTUE 11 -> 8 -> **4**.
Only Guildhall was extracted for this spike; the three-map numbers were
measured by the N-P0 extractor run and are recorded in
[`navmesh-p0-p2-20261127.md`](navmesh-p0-p2-20261127.md).

The consumer now exists: `tools/parse_nav.py` writes `nav/<map>.nav.bin` +
`manifest.json`, `game/src/ai/nav_runtime.gd` builds one region per map behind
`TAT2_NAV=off|on` (default off), and `build/qa/nav_runtime_probe.gd` proves the
doorway, the 80 links and the prison door link on/off. Area ids stay per-map:
Guildhall/FTUE `Door=4/Bushes=3`, Old Manor `Door=3/Bushes=4`; 63 is
`NavArea_Default` and is walkable. Do not create one link per raw record.
