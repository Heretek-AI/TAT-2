# Task-1 evidence — mesh-export filter repair + dropped-mesh re-extraction

Date (UTC): 2026-11-20. Ground truth: `.omo/waves/tat2-ground-truth/backlog.md`.
Build pin: see `task-0.md` (HEAD `ca7e8ed` + round-1 worktree; this task adds one
tracked edit below — no test/run edits, no `make test` per task rule).

## 1. Code fix (only tracked edit by this task)

`tools/tat-extract/Exporter.cs` — two hunks, both commented `task-1 (round-2 mesh repair)`:

- `Packages()`: kept the `TAT/` gate for everything else, added one explicit
  exception — `|| f.Path.StartsWith("Engine/Content/BasicShapes/")` — because the
  Den/Guildhall levels reference Engine primitives that live outside `TAT/`.
- `Meshes()`: widened the name allowlist (`SM_/SK_/SKM_/GB_` chain) with
  `Path.GetFileName(p).StartsWith("VFX_")`, `StartsWith("Coin_")`, and
  `p.Contains("/BasicShapes/")`. No conversion settings touched; no other
  exporter, `game/src`, `game/tests`, or UI/data file touched.

Build: `dotnet build tools/tat-extract -c Release` → `0 Error(s)` (binary
`tools/tat-extract/bin/Release/net10.0/tat-extract` newer than the edit).

## 2. Export runs

- Full unfiltered `tat-extract meshes` run queued the newly-allowed packages
  (proven by freshly written sidecars `Coin_Bronze.materials.json`,
  `VFX_SkySearchLight_Mesh.materials.json`, `Engine/Content/BasicShapes/*.materials.json`
  during that run), then was stopped for time: the pre-existing overwrite-skip
  check looks at `extracted/assets/<rel>.glb` while the exporter writes GLBs to
  `extracted/assets/TAT/Content/<rel>.glb`, so every unfiltered run re-exports
  all ~2000 packages.
- Targeted `tat-extract meshes --filter '(Coin_|VFX_SkySearchLight_Mesh|BasicShapes)'`
  (same fixed binary): `queuing 10 mesh packages... [meshes] ok=9 fail=0`
  (10 = 3 coins + VFX mesh + 5 shapes + 1 material-only package, which yields
  no mesh; exit 0).
- `python3 tools/parse_materials.py` → exit 0:
  `Resolved 1571 materials (1223 with real params)` and
  `Mapped 2054 mesh material slot lists (2031 GLB-ordered, 23 sidecar-fallback)`.

`game/assets` visibility is via symlinks (`game/assets/ue/Content ->
extracted/assets/TAT/Content`, `game/assets/ue/Raw -> extracted/assets`), so the
GLBs below are loadable at `res://assets/ue/Content/...` and `res://assets/ue/Raw/...`.
`extracted/` and `game/data/generated/` are gitignored; revert path is
`git checkout tools/tat-extract/Exporter.cs` + delete/re-export generated files.

## 3. Before/after per-mesh diff counts

BEFORE (snapshot pre-fix): `find extracted/assets -name '*.glb' | wc -l` = **2045**;
`mesh_materials.json` keys = **2045**; per-target GLB and bind counts all **0**
(`Coin_Bronze/Silver/Platinum`, `SkySearch`, `BasicShapes` greps empty; the
`Cylinder`/`Plane` pre-hits were unrelated assets sharing the words).
AFTER: GLBs = **2054** (+9); binds = **2054** (+9).

| Mesh (UE path suffix) | GLB before | GLB after | mesh_materials key before | mesh_materials key after | Bound slot(s) after |
|---|---|---|---|---|---|
| `.../LootMinor/Coins/Coin_Bronze` | 0 | 1 (`extracted/assets/TAT/Content/Art/Gameplay/Loot/LootMinor/Coins/Coin_Bronze.glb`) | 0 | 1 | `['/Game/Art/Gameplay/Loot/LootMinor/Coins/MI_Coins']` |
| `.../LootMinor/Coins/Coin_Silver` | 0 | 1 (`.../Coins/Coin_Silver.glb`) | 0 | 1 | `['/Game/Art/Gameplay/Loot/LootMinor/Coins/MI_Coins']` |
| `.../LootMinor/Coins/Coin_Platinum` | 0 | 1 (`.../Coins/Coin_Platinum.glb`) | 0 | 1 | `['/Game/Art/Gameplay/Loot/LootMinor/Coins/MI_Coins']` |
| `.../Lights/Searchlight/VFX_SkySearchLight_Mesh` | 0 | 1 (`extracted/assets/TAT/Content/Art/Environment/Lights/Searchlight/VFX_SkySearchLight_Mesh.glb`) | 0 | 1 | `['/Engine/EngineMaterials/WorldGridMaterial']` |
| `/Engine/BasicShapes/Cylinder` | 0 | 1 (`extracted/assets/Engine/Content/BasicShapes/Cylinder.glb`) | 0 | 1 exact (`/Game/Engine/Content/BasicShapes/Cylinder`) | `['/Engine/EngineMaterials/DefaultMaterial']` |
| `/Engine/BasicShapes/Plane` | 0 | 1 (`extracted/assets/Engine/Content/BasicShapes/Plane.glb`) | 0 | 1 exact (`/Game/Engine/Content/BasicShapes/Plane`) | `['/Engine/EngineMaterials/WorldGridMaterial']` |
| `/Engine/BasicShapes/Cube` | 0 | 1 (`extracted/assets/Engine/Content/BasicShapes/Cube.glb`) | 0 | 1 exact (`/Game/Engine/Content/BasicShapes/Cube`) | `['/Engine/EngineMaterials/WorldGridMaterial']` |
| `/Engine/BasicShapes/Sphere` | 0 | 1 (`extracted/assets/Engine/Content/BasicShapes/Sphere.glb`) | 0 | 1 exact (`/Game/Engine/Content/BasicShapes/Sphere`) | `['/Engine/EngineMaterials/DefaultMaterial']` (GLB-ordered; substring matches on unrelated Sphere assets also present) |
| `/Engine/BasicShapes/Cone` | 0 | 1 (`extracted/assets/Engine/Content/BasicShapes/Cone.glb`) | 0 | 1 exact (`/Game/Engine/Content/BasicShapes/Cone`) | `['/Engine/EngineMaterials/DefaultMaterial']` |

Note: `parse_materials.py` (unmodified, read-only per scope) keys Engine sidecars as
`/Game/Engine/Content/BasicShapes/<Name>` (it prefixes `/Game/` to the extracted
relative path). The substring greps `BasicShapes/Cylinder|Plane|Cube|Sphere|Cone`
each hit their exact key; stale `missing mesh` warnings for
`/Engine/BasicShapes/Cylinder|Plane` and `/Game/.../VFX_SkySearchLight_Mesh`
(task-0 §2) now have GLBs + binds behind them. Loader-side path mapping
(`level_loader.gd::_ue_mesh_to_res`) is out of scope and untouched.

## 4. Verification (re-run at write time)

- `find extracted/assets -name '*.glb' | wc -l` → `2054`.
- `ls game/assets/ue/Content/Art/Gameplay/Loot/LootMinor/Coins/` →
  `Coin_Bronze.glb Coin_Platinum.glb Coin_Silver.glb SM_CoinPileA.glb`.
- `ls game/assets/ue/Raw/Engine/Content/BasicShapes/` →
  `Cone.glb Cube.glb Cylinder.glb Plane.glb Sphere.glb` (+ sidecars).
- `VFX_SkySearchLight_Mesh.glb` present under
  `game/assets/ue/Content/Art/Environment/Lights/Searchlight/`.
- `python3 -c` key check: all 9 UE paths resolve to exact `mesh_materials.json`
  keys with non-empty slot lists (table above).
- This file re-read from disk after writing (done).
