# Task-5 evidence — Guildhall mini + highlight-path hardening

Date (UTC): 2026-11-20. File edited: `game/src/missions/mission_controller.gd`
(minis spans only). No `make test` run — orchestrator owns suites at settle;
VERIFY here is file-level re-read + targeted grep.

## 1. Spans touched (post-edit line numbers, `grep -n ^func`)

- `_spawn_map_table_miniatures`: **605–664** (func line 605; trailing
  `_update_map_token_highlights()` call at 664).
- `_update_map_token_highlights`: **667–~706** (func line 667). NOT edited —
  verified already first-call safe, defaults kept.
- Gaze selector (`_refresh_den_lookat_card` token loop): **~940–956**
  (highlight re-trigger at 956). NOT edited — verified already guarded.
- Telescope/vista spans and Den hub flow: untouched (Wave 1 owns them).
- Note: task brief cited gaze span ~883-900; on disk that range is the
  telescope ponder-focus block (Wave 1 — not touched). The actual token gaze
  selector is ~940-956 (shifted +4 by this edit).

## 2. Change (spawn loop, lines 639–644)

Sentinel lines:

```
642:			push_error("[mission_controller] missing mesh for UE path %s; skipping map token %s (%s)" % [ue_mesh, str(item["name"]), str(item["map_id"])])
643:			assert(false, "missing map token mesh: " + ue_mesh)
```

Before: bare `if mesh == null: continue` (line 639, unique site per
`grep -n "mesh == null"` = exactly one hit) — a missing GH mesh vanished
without a trace. After: the missing path logs the UE path + token
name/map_id via `push_error` and fires `assert(false, ...)` with the UE
path, then continues. `grep -n "push_error\|assert("` on the file returns
only these two lines inside the minis span — every mesh-missing path in
scope now logs its UE path.

## 3. Highlight first-call safety (verified, kept as-is)

Every meta/dict read in the minis spans carries a default:

- `678`: `_den_tokens.get(mid, null)` + `is` / `is_instance_valid` guard.
- `683`: `mi.get_meta("minis_base", mi.scale.x)` — pre-spawn/highlight
  first call falls back to live scale; spawn always sets `minis_base`
  (line 660) before the trailing highlight call (664).
- `687`: `mi.get_meta("minis_tween", null) as Tween` + `is_valid` kill.
- `638`: `info.get("mesh")` (implicit null default) feeds the now-logging
  639–644 path.
- Gaze `942`: `_den_tokens.get(mid, null)` + validity guard; empty dict
  (highlight before spawn) is a no-op loop.
- `mi.mesh` nullTernary at the surface loop (`get_surface_count() if
  mi.mesh != null else 0`) plus `if mat is StandardMaterial3D` before
  emissive writes — no unguarded dereference.

## 4. GH verdict: PRESENT-WITH-BASE (code level)

- `MapTokenGuildHall` entry is in the `miniatures` array with
  `"map_id": "guildhall"`, UE mesh `/Game/Art/UI/Map/SM_MapBuilding_GuildHall`,
  and `"scale": 0.24` — the UE-ratio anchor (GH SphereRadius 27.39531;
  OldManor entry uses `0.24 * (45.56192 / 27.39531)`). Settled values
  reused, not re-derived.
- Cooked-data cross-check (read-only): `extracted/json/Art/UI/Map/`
  `SM_MapBuilding_GuildHall.json` (3 exports) carries ExtendedBounds
  SphereRadius 27.39531; `SM_MapBuilding_OldManor.json` carries 45.56192 —
  matches the in-code ratio. `mesh_materials.json` binds both UE mesh
  paths to their `M_MapBuilding_*` materials.
- Caveats (not provable without the orchestrator suite): `ThievesDen_Geo`
  tatlevel holds no token actors (tokens are port-spawned, not level data),
  no `*MapBuilding*.glb` exists under `game/assets/` (geometry resolves via
  the loader fallback chain — outside this task's scope), and
  `prior task-10.log` named in the brief is absent on disk. If the loader
  ever yields a null GH mesh at runtime, the new 642–643 sentinel names
  the UE path instead of dropping the token silently.
- Tests untouched: `run_tests.gd:2676-2681` already expects the UE ratio
  (GH 0.24 anchor, OM ratio ±0.01); stale uniform-0.24 e2e rows left alone
  per scope.

## 5. Verify results

- Re-read 632–661 post-edit: log + assert + continue present, UE path in
  both lines.
- `grep -n "mesh == null"` → single site (639), now logging.
- `task-5.md` exists with this GH verdict.
- Changed range reported: mission_controller.gd 639–644 (+4-line shift to
  all following lines; highlight/gaze spans content-identical).
