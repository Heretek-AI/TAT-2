# T0-6 (audit T6) — Collider budget partition evidence

Date (UTC): 2026-11-20. Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md`
T6 + `audit-core.md` P0-5 / P1-L4. Base: HEAD `b5f35b8` + committed round-1/round-2.

## Reproduced spans (verbatim, before change)

- `game/src/core/level_loader.gd:95`: `const MAX_TOTAL_SHAPES: int = 32000`
- `game/src/core/level_loader.gd:1695-1697` (HEAD numbering):
  `func _add_collider(ctx, cell, shape, tr, shape_offset) -> void:`
  `if int(ctx.get("collision_shapes", 0)) >= MAX_TOTAL_SHAPES: return`
  — no warning, no counter (the silent drop).
- Curb feed, `:2021-2024` region: 1 walk box + 2 lip boxes per ribbon segment
  via `_add_collider`, sharing the same 32k budget (P1-L4 starvation path).

## Partition numbers

- `MAX_TOTAL_SHAPES = 32000` (unchanged global backstop).
- `MAX_BUILDING_SHAPES = 28000` — walls/floors, Den window splits, grounded
  Den props, blocking volumes, landscape colliders (world integrity load).
- `MAX_CURB_SHAPES = 4000` — procedural curb ribbons, 3 boxes per segment,
  at most `CURB_MAX_SPLINES` (64) splines.
- 28000 + 4000 = 32000 exactly; the per-partition cap AND the global cap are
  both enforced in `_add_collider`, so neither class can starve the other and
  the old 32k ceiling still holds.

## Counted warning (emitted per dropped item, names the item)

```
[level_loader] collider budget overflow: dropped <building|curb> item '<label>'
(<partition> <used>/<cap>; total <used>/32000)
```

- Building labels carry the mesh path (`mp`); Den split pieces append
  `/pillar_L`, `/pillar_R`, `/sill`, `/lintel`.
- Curb labels carry `curb walk|lip seg <N> side <±1> (<sp_mesh>)`.
- Drops counted in `ctx["collision_dropped"]` + per-partition
  `building_dropped` / `curb_dropped`; item names kept (capped 128, unique)
  in `ctx["dropped_colliders"]`.

## Fail-loud export-time accounting hook

- `static func check_collider_budget(stats) -> bool` (level_loader.gd,
  adjacent to `_add_collider`): true when nothing dropped and total within
  cap; else `push_error` with full partition counts and returns false.
  Accepts the build ctx or the `_finalize` result dict (same keys).
- `_finalize` surfaces `building_shapes`, `curb_shapes`,
  `collision_dropped`, `building_dropped`, `curb_dropped`,
  `dropped_colliders`, and `collider_budget_ok = check_collider_budget(result)`
  — export gates on `collider_budget_ok`; any overflow `push_error`s at load.
- Blocking volumes and landscape colliders always emit (no cap check, so no
  silent drop there) but now increment `building_shapes`, keeping the
  partition accounting honest.

## Changed ranges (game/src/core/level_loader.gd)

- `:95-103` partition constants; `:1046-1051` ctx counters in `_new_build_ctx`;
  `:1603-1635` `_add_den_window_split` kind/label threading;
  `:1706-1751` `_add_collider` partition check + counted warning;
  `:1754-1769` `check_collider_budget` hook; `:1885-1890` building call sites;
  `:2067-2071` curb call sites; `:2180-2188` `_finalize` surfacing + gate;
  `:2478` blocking-volume accounting; `:2988` landscape accounting.

## Verify (this turn, no `make test` per task)

- Re-read every edited span: the bare `return` after the cap check is gone;
  every overflow path increments counters and `push_warning`s with the item
  name; partition constants sum exactly (28000 + 4000 = 32000, script-checked).
- Structural check passed: partition sum, no silent return, hook defined and
  wired, all 10 `_add_collider` call sites carry kind/label, all ctx keys
  present. No godot binary on this machine, so no parse run; full suite left
  to the orchestrator settle.
- Untouched: vista/prop/stair spans, missing-mesh path, occluder/decal/light
  budgets.
