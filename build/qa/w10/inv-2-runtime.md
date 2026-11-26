# INV-2 — runtime defects (D6, D7, D9, D10): measured fact sheet

**Supersedes the earlier unmeasured draft in this path** (its own header said
"D6/D7/D9/D10 NOT MEASURED — investigation stopped for the edit window"). Every
number below comes from a run in this worktree; nothing is inferred from prose.

| | |
|---|---|
| worktree | `/home/john/Projects/TAT-2-rem-w10-a` (branch `rem/w10-a`, brief said `w10/a`) |
| HEAD | `29046c8` |
| Godot | 4.7.2 headless, Jolt (`project.godot:40`), one process at a time under `flock /tmp/opencode/tat2-godot.lock` |
| new files | `game/tests/test_w10_runtime.gd`, `build/qa/runtime_smoke_scan.sh`, `build/qa/test_runtime_smoke_scan.sh`, this file |
| game source | **no edits by INV-2** (investigation only). The implementation lane edited `trace.gd` and `authored_collision.gd` in this worktree while the run was in progress; that is recorded, not claimed. |
| raw logs | `/tmp/opencode/w10a/` (worker cannot commit; every command below reproduces them) |

**Tree state (important).** While this investigation ran, the implementation
lane landed the **D6 and D7** corrections in this same worktree
(`game/src/ai/statetree/trace.gd`, `game/src/core/collision/authored_collision.gd`)
and extended `game/tests/test_w10_runtime.gd`. The suite is **green** there
(`W10_RUNTIME_SUMMARY: fails=0 checks=45`, log
`/tmp/opencode/w10a/inv2_verify3.log`). The red output quoted in D6/D7 below is
from `29046c8` **before** those edits (logs `inv2_final2.log`,
`inv2_test_v7.log`), so both the reproduction and the green state are preserved.
**D9 and D10 are not fixed in the tree.** *(Updated during the run: D9 was
then factored into `build/qa/runtime_smoke_scan.sh` and wired into
`runtime_smoke.sh`; D10 is still unfixed.)*


## Verdict

| defect | status | one-line red evidence |
|---|---|---|
| **D6** trace disk cap | **reproduced at `29046c8`; fixed in-tree by the implementation lane** | 9000 rows pushed → `file_lines=9000`, ring `8192`, `dropped=808`; after the fix `file_lines=8192`, `file_dropped=808` |
| **D7** flat authored geometry | **reproduced; fixed in-tree by the implementation lane; brief's mechanism wrong** | ward zone is a coplanar **convex** (8 pts), emitted as a zero-volume `ConvexPolygonShape3D`; the 2 cm box clamp never touches it. Exactly **1** box has a zero axis (`/Engine/BasicShapes/Plane`), and **3** convex elements are coplanar, placed **160 / 0 / 6**. |
| **D9** runtime-smoke blindness | **reproduced; fixed in-tree by the implementation lane** (scanner factored out + wired, log kept; allowlist embedded) | `PRE_FIX_BLIND_SPOT: ERROR: line -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL` (×4: `ERROR:`, `USER ERROR:`, signal 11, exit 0) |
| **D10** stale traversal tests | **reproduced** | `test_stair_walk` 13 fails (6 of 7 flights "no trimesh collider"); `test_traversal_routes` 4 fails (steep/hip/non-uniform roof) |

---

## D6 — `statetree/trace.gd` streams NDJSON past the ring cap

### Code

`game/src/ai/statetree/trace.gd:81-95`:

```gdscript
func push(row: Dictionary) -> void:
	if rows.size() >= MAX_ROWS:
		dropped += 1
		# Keep the first MAX_ROWS rows: the start of a run is the part that
		# explains the branch choice, and a wrapped buffer would hide it.
		if _file == null:
			return
	if rows.size() < MAX_ROWS:
		rows.append(row)
	if _file != null:
		_file.store_line(JSON.stringify(row))
		...
```

The only early return is guarded by `_file == null`, so with
`TAT2_STATETREE_TRACE` set (`trace.gd:41-43` → `configure` → `FileAccess.WRITE`,
`:60`) every post-8192 row is still written. `to_ndjson()` (`:160-168`) writes
only the ring and is already bounded.

### Red proof (measured)

`flock /tmp/opencode/tat2-godot.lock -c "timeout 900 tools/godot --headless --path game --script res://tests/test_w10_runtime.gd"`:

```
D6_TRACE ring=8192 dropped=808 pushed=9000 file_lines=9000 file_bytes=406234 path=user://w10_trace_cap.ndjson
PASS: trace ring holds the first 8192 rows (got 8192)
PASS: trace counts 808 rows dropped past the ring
FAIL: trace NDJSON file is unbounded: 9000 lines written for 9000 pushed rows (cap 8192); ring=8192 dropped=808
```

`user://w10_trace_cap.ndjson` was 406,234 bytes at 9000 rows (≈45 B/row) and the
suite removes it afterwards (verified: no `w10_*` file left in the project
user dir). At the trace module's own design figure ("~30,000 rows a second",
`trace.gd:4-6`) that is ≈1.35 MB/s behind a 8192-row bound that never applies.

### Recommended fix (smallest)

```gdscript
func push(row: Dictionary) -> void:
	if rows.size() >= MAX_ROWS:
		dropped += 1
		return                     # hard cap: ring AND stream stop together
	rows.append(row)
	if _file != null:
		_file.store_line(JSON.stringify(row))
		...
```

Optional but cheap: `flush()` once on the transition into the capped state, and
append one sentinel row `{"kind":"trace_truncated","dropped":N}` in `close()` so
the NDJSON is self-describing. The suite asserts `lines <= MAX_ROWS`; the
`degenerate`-style API is not involved. If the implementer chooses a separate
`MAX_FILE_ROWS` (> 8192), the suite's assertion must be changed to that constant
in the same commit — do not leave the test and the code disagreeing.

### What landed in this worktree

`trace.gd` now carries a **separate disk budget** — a superset of the minimal
fix: `MAX_FILE_ROWS = MAX_ROWS` (8192), `MAX_FILE_BYTES = 16 MiB` for
pathological rows, `file_rows` / `file_bytes` / `file_dropped`, a one-shot
`STATETREE_TRACE capped rows=… bytes=… dropped_file=… ring_dropped=… path=…`
line, and a hard stop (no `store_line` once capped). The suite's extended D6
checks all pass:

```
D6_TRACE ring=8192 dropped=808 pushed=9000 file_lines=8192 file_bytes=369466 path=user://w10_trace_cap.ndjson
D6_FILE pushed=9000 file_rows=8192 file_dropped=808 file_bytes=369466 disk_bytes=369466 lines=8192 cap_rows=8192 cap_bytes=16777216
D6_FILE_STOP pushed=15000 lines=8192 file_rows=8192 file_dropped=6808
D6_BYTES pushed=400 file_rows=255 file_dropped=145 file_bytes=16720750 disk_bytes=16720750 cap_bytes=16777216
```

---

## D7 — zero-thickness authored geometry: what the data actually says

### Brief vs measured

Brief: *"Zero-thickness authored boxes clamp to 2 cm solid slabs (`SM_SlowWardZone_Quad`
×82)"*. Measured against `game/data/generated/mesh_collision.json`
(`schema: tat2.mesh_collision/1`, 1,992 meshes / 8,601 elements):

| claim | measured |
|---|---|
| `SM_SlowWardZone_Quad` is a box | it is **one `convex` element**, 8 vertices, `aabb_min [-1,-1,-0]` / `aabb_max [1,1,0]` cm |
| it is clamped to 2 cm | `MIN_HALF_EXTENT_M` is applied **only in the box branch** (`authored_collision.gd:359-367`); `resolve()` emits the convex unchanged |
| exactly one zero box | yes, but it is `/Engine/BasicShapes/Plane` (`half_extent [100,100,0]`), **not** the ward zone |
| ×82 | **160** placements: 82 `Guildhall_Gameplay` + 78 `OldManor_Gameplay` |

### The three coplanar convex elements (the real D7 set)

| mesh | element | points | authored AABB (cm) | profile | placed |
|---|---|---:|---|---|---:|
| `/Game/Art/Effects/WardZones/SM_SlowWardZone_Quad` | convex | 8 | `[-1,-1,0] .. [1,1,0]`, z = ±1.2e-16 | `BlockAll` | **160** (82 GH / 78 OM) |
| `/Game/Art/VFX/Meshes/FXSHAPES_1_FXQuadPivotCenter` | convex | 8 | `[-1,-1,0] .. [1,1,0]` | `BlockAll` | **0** |
| `/Game/Art/VFX/Meshes/FXSHAPES_1_FXQuadPivotDownEdge` | convex | 4 | `[-1,-2,0] .. [1,0,0]` | `BlockAll` | **6** (Contract 16 ×2, Teleporters ×2, OldManor Contract10 ×2) |

The nearest non-degenerate convex is 2.0 mm thick
(`SM_OldManor_Window_LivingRoom_Glass`, `min_ext=0.002000786` m), so the
degenerate/thin boundary is four orders of magnitude wide. Threshold in the
suite: `FLAT_EPS_M = 1e-5` m.

### The one true zero box (and 14 near-zero boxes)

| mesh | min extent (m) | profile | placed | effect of the clamp |
|---|---:|---|---:|---|
| `/Engine/BasicShapes/Plane` | 0.0 (exactly) | `BlockAll` | 20 | `resolve()` → one `BoxShape3D` of **1.0 × 0.02 × 1.0 m** (the clamp fires) |
| 14 glass panes (Manor windows/doors/display cases, storefront windows, front door) | 1.6e-7 … 7.9e-7 | `BlockAll*` / `BlockAllExceptVision*` | see level JSON | same 2 cm clamp (authored float residue, not exactly zero) |

So the "solid slab" clamp is real — it just has **nothing to do with the ward
zone**. It is 1 true zero + 14 float-residue boxes; the ward zone is a convex.
At the largest Plane placement (`OldManor_Geo`, scale 54.45/16.93/31.44) the
2 cm local thickness becomes ≈0.34 m world. The clamp is deliberate
(`authored_collision.gd:86-87`: "Jolt rejects a zero-sized box").

### What `resolve()` emits, and what Jolt does with it (measured)

```
D7_WARD source=hull elements=1 convex=1 shapes=1 offsets=1 degenerate=1
  ward hull points=8 min_extent=0.000000000 aabb=[P: (-0.01, -0.0, -0.01), S: (0.02, 0.0, 0.02)]
  D7_MESH ward render_aabb=[P: (-0.01, -0.0, -0.01), S: (0.02, 0.00001, 0.02)] collision_points_aabb=[P: (-0.01, -0.0, -0.01), S: (0.02, 0.0, 0.02)]
  D7_PLACED guildhall_wards=82 pos=(-18.0061, 30.5294, -28.9636) authored_scale=[352.8921, 1.0, 220.5195] clamped_scale=(40.0, 1.0, 40.0) local_quad_m=(0.020, 0.020) placed_span_m=(0.80, 0.80)
  D7_PLACED world_basis_axes x=(0.0, 1.0, 0.0) y(normal)=(0.0, 0.0, 1.0) z=(1.0, 0.0, 0.0) ray_hits_centre/30m_x/30m_z=[true, false, false]
D7_FX FXSHAPES_1_FXQuadPivotCenter source=hull elements=1 shapes=1 degenerate=1
D7_FX FXSHAPES_1_FXQuadPivotDownEdge source=hull elements=1 shapes=1 degenerate=1
D7_PLANE source=prims elements=1 shapes=1 size=(1.0, 0.02, 1.0) (clamp fires: size.y == 0.020)
```

* The ward mesh is **2 cm** across locally (render AABB 0.02 × 0.00001 × 0.02 m);
  the authored instance scale is 352.89 / 1.0 / 220.52, which
  `level_loader._dict_to_transform` clamps to `[0.05, 40]` → **40 / 1 / 40**, so
  the placed sheet is **0.80 m × 0.80 m** and 0 m thick (160 placements, all of
  them clamp-touched). The earlier draft's 8.1 × 11.9 m figure is pre-clamp.
  Side note for the lead: the same clamp is used for the mesh *instance*
  (`level_loader.gd:3263`), so the ward contour **visual** is also 0.8 m where the
  authored placement is 7.06 m × 4.41 m — a separate scale-clamp fidelity item
  (RE-P-10), not this defect.
* **Jolt accepts the zero-volume hull without an error line, and it is solid but
  tiny.** With a 0.2 m shape query along each in-plane axis: hit at 0.00 m and
  0.25 m, miss at 0.50 / 1 / 2 / 5 / 20 / 39 / 41 m — for the 2 cm local hull and
  for the 0.8 m placed hull alike. A ray down the normal answers at y = 0.0 and a
  box query at the origin overlaps. So the emitted collider is **not** the
  authored square, **not** a 2 cm slab, and **not** an 80 m wall: it is a
  sub-metre invisible solid artefact at each placement origin.
* `world_basis_axes` shows the first Guildhall placement is vertical (local Y →
  world Z, the sheet spans world Y and X). Across all 160 placements the sheet
  normal is vertical for 115 (flat sheets lying at floor/ceiling height) and
  horizontal for 45 (vertical sheets inside walls), so the artefact sits on
  floors and in walls alike.

### Recommendation: skip coplanar convex, counted; keep the box clamp

**Skip** every convex element whose baked point set is coplanar within
`1e-5` m, in `resolve()`, and report it:

* `resolve()` gains `"degenerate": <int skipped>` and `stats()` a `degenerate`
  total; the loader's per-path accounting (`_count_collision_path`) adds
  `col_degenerate` and prints one `COL_DEGENERATE <ue_path> elements=<n>
  instances=<n> min_extent_m=<v>` line per path;
* the ward/FX shapes disappear (`shapes.size() == 0`), the loader emits no
  collider (it already handles `shapes == []` without falling back to the
  heuristic, `level_loader.gd:2014-2028`);
* this is safe for the ward because the ward **gameplay** is not this mesh:
  `game/src/devices/ward_zone.gd:111-137` builds its own `StaticBody3D`
  (blocker layer 4) and `Area3D` from the authored `zone_size_m`; the quad mesh
  is the visual contour (`M_WardZoneContourDecal`). The FX quads are VFX.

**Keep** the `MIN_HALF_EXTENT_M` box clamp, with the measured reason: exactly
1 truly-zero box (`/Engine/BasicShapes/Plane`, 20 placements, a floor/plane
primitive) plus 14 float-residue glass panes; a zero-size box is rejected by
Jolt, and the 2 cm thickening is harmless for glass. Do not extend the skip to
boxes — that would open the glass holes the earlier draft warned about.

Rejected alternative — "keep the hull with a documented reason": it is a solid
invisible body in 166 placements (160 ward + 6 FX) whose shape is an
implementation artefact of Jolt's degenerate-hull handling, so the "documented
reason" would have to be "we ship collision we cannot describe". There is no
authored gameplay behaviour that depends on it.

The suite encodes exactly this recommendation (see below), including the counted
report, so the fix is red → green without editing the test.

### What landed in this worktree, and one correction

`authored_collision.gd` now implements the rule above: `PLANAR_EPS_M = 1e-4`,
coplanar convex skipped before a shape is built, contract
`resolve()["planar_convex_skipped"]` (+ the `"degenerate"` alias the
investigation asked for), `stats()["planar_convex_skipped"]` /
`["box_clamped"]` / `["planar_skipped_paths"]`, and one
`COL_PLANAR <ue_path> instances=<n> skipped=<n>` line per path per process.
Boxes keep the 2 cm clamp and are counted as `box_clamped`. Suite output:

```
COL_PLANAR /Game/Art/Effects/WardZones/SM_SlowWardZone_Quad instances=82 skipped=1
D7_WARD source=hull elements=1 convex=1 shapes=0 offsets=0 degenerate_hulls=0
D7_PLANE source=prims elements=1 shapes=1 size=(1.0, 0.02, 1.0) (clamp fires: size.y == 0.020)
PASS: ward zone emits no zero-volume convex hull (0 shapes)
PASS: ward zone reports the skipped degenerate element (degenerate=1)
```

**Correction for the implementation comment** (`authored_collision.gd:96-104`):
it says a coplanar hull "is inflated by the physics engine into a ~2 cm-thick
slab" and the ward zone "became a room-sized invisible wall". Measured against
Jolt here: a shape query answers only at 0.00 m and 0.25 m along either in-plane
axis and misses at 0.50 m … 41 m (both the 2 cm local hull and the 0.8 m placed
hull), i.e. the outcome was a **sub-metre solid artefact at the placement
origin**, not a slab and not a room-sized wall. The "scales up to 399 cm" are
pre-clamp: `level_loader._dict_to_transform` caps the instance scale at 40, and
the same clamp applies to the visual (`level_loader.gd:3263`), so the placed
quad is 0.80 m, not 7 m. The **fix is right; the stated consequence is wrong** —
please reword the comment to the measured behaviour before this ships, because
W10's evidence rules apply to comments too.

---

## D9 — `make runtime-smoke` is blind to `ERROR:` and to the exit code

### Code (pre-fix, `29046c8`)

`build/qa/runtime_smoke.sh`:

* `:26-28` — only `SCRIPT ERROR`, `SHADER ERROR`, `TAT-2 mission_ready` are counted;
* `:33-45` — `$CODE` is assigned at `:24` and **never read**; `ERROR:` appears
  only in the diagnostic `grep` on the failure path (`:35`);
* `:48` — `rm -f "$LOG"`: a passing run deletes the only evidence.

`docs/reports/logs/w9/` contains **no** runtime-smoke log (checked: only
compile/e2e/m2/perf/audit/probe logs). The W9 reports quote `RUNTIME_SMOKE PASS`
lines (`build/qa/w9/p4-report.md:470-471`) but the artefact was deleted, so the
claim is not re-derivable from the tree. That is part of the defect.

### Red proof (deterministic, no boot)

New harness: `build/qa/runtime_smoke_scan.sh <log> <exit-code>` +
`build/qa/test_runtime_smoke_scan.sh`. The test builds ten fixture logs, runs
(a) a verbatim copy of the pre-fix decision block and (b) the scanner, and
prints the blind spots:

```
PRE_FIX_BLIND_SPOT: ERROR: line -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL
PRE_FIX_BLIND_SPOT: push_error line -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL
PRE_FIX_BLIND_SPOT: signal-11 crash -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL
PRE_FIX_BLIND_SPOT: premature exit 0 -> runtime_smoke.sh at 29046c8=PASS, scanned=FAIL
RUNTIME_SMOKE_SCAN_TEST: checks=29 fails=0
```

Fixtures: clean; `ERROR: Condition "!is_inside_tree()" …`; `USER ERROR: "…"`
(Godot's `push_error` line); `SCRIPT ERROR`; no `mission_ready`; a signal-11
log that did print `mission_ready`; a clean log with exit 0; an allowlisted
teardown error. The scanner rejects all four blind spots and still
passes the clean, warning-only and allowlisted logs.

### Real 90 s boot (one run, under flock)

`flock /tmp/opencode/tat2-godot.lock -c "timeout 90 tools/godot --headless --path game -- --qa-free-play" > /tmp/opencode/w10a/smoke-real.log 2>&1` → **exit 124**, 137 lines:

```
TAT-2 mission_ready map=guildhall meshes=63100 lights=160 chunks=6015
AUTHORED_COLLISION meshes=947 hull=937 prims=599 convex=899 absent=10 no_collision=7 query_only=7 reduced=16 shapes_per_instance_avg=1.14 elements=2184 load_ms=310
```

`ERROR:` / `USER ERROR:` / `SCRIPT ERROR` / `SHADER ERROR` lines: **0**. The 11
`WARNING:` lines a real placeholder-data boot legitimately prints (allowlist
material, all reproduced verbatim):

```
[civilian_npc] navmesh snap deferred: query landed before first map sync (deferred=1); target fails open until sync
[game_data] map fallback (unrecognized mission row routes to example) for row 'Mission.Example.Multi' (fallbacks=1, cap=64)
[game_data] map fallback … 'Mission.Example.Vault' (fallbacks=2, cap=64)
[game_data] map fallback … 'Mission.Example.Clue' (fallbacks=3, cap=64)
[hearing_data] 5 authored investigation-range anomalies clamped: AI.Stim.Hearing.LockPicking.Picked: outer 5.0 m > max 3.0 m (clamped); …
[level_loader] level Niagara: 5 placements across 3 systems in 4 chunk nodes (… files=0)
[level_loader] level Niagara: 452 placements across 8 systems in 66 chunk nodes (…; decode root=res://../extracted/json files=46)
[level_loader] material flat white: '/Engine/BasicShapes/BasicShapeMaterial' … (flat=2)
[level_loader] material flat white: '/Game/MaterialLibrary/Debug/MI_Default_White' … (flat=1/5)
[nav_steering] no synchronised navigation map (no NavigationRegion3D baked for this map); AI uses straight-line steering and will press into corners…
```

Scanning that log with the landed scanner:

```
RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok path=/tmp/opencode/w10a/smoke-real.log
```

`ERROR:` count 0 is the important part: **today the real boot needs an empty
error allowlist**; the allowlist exists so the gate can name the teardown noise
(`N resources still in use at exit`, `N RID allocations of type …`) that appears
when Godot exits normally, and the two documented placeholder warning families
(`Mission.Example.*`, `[hearing_data] … clamped`).

### Recommendation (smallest change, testable) — landed in this worktree

`runtime_smoke.sh` now delegates lines 26-45 to `runtime_smoke_scan.sh` and keeps
the log (`echo "log: $LOG"`, never `rm -f`). The scanner owns the decision:
**exit 124 only** (0 is a premature exit and fails), `mission_ready ≥ 1`, zero
`SCRIPT ERROR` / `SHADER ERROR` / `ERROR:` (`USER ERROR:` is covered by the
`ERROR:` match), minus the allowlist. It prints one machine line
`RUNTIME_SMOKE_SCAN PASS|FAIL exit=… errors=… raw=… allowed=… script_errors=…
shader_errors=… mission_ready=… reason=… path=…`, which is the line the gate log
and the ratchet should read.

Two follow-ups the wiring still owes:

1. **The allowlist must not be a sibling `.txt`**: `.gitignore:25` ignores
   `build/qa/*` except `.gd/.sh/.py`. The landed scanner already carries the
   teardown defaults **embedded in the script** (resources/RIDs still in use at
   exit, `PagedAllocator`), with an optional `runtime_smoke_allowlist.txt`
   appended for a local run. Keep it that way; an ignored file would be silently
   absent on every clean checkout.
2. **Commit the log.** The script prints its path but the evidence still lives in
   `/tmp`. Copy it to `docs/reports/logs/<wave>/runtime_smoke.log` and add the
   gate to `tools/gate_ratchet.json`
   (`RUNTIME_SMOKE_SCAN PASS … mission_ready=1 … reason=ok`), otherwise a green
   run is again only prose.

Exit-0 acceptance: the earlier draft suggested accepting `0` as well. Don't —
the smoke is a 90 s window that only ends by `timeout`, so exit 0 means the game
quit inside the window and the boot was not actually exercised. The landed
scanner enforces 124-only.

---

## D10 — two stale traversal tests

### A. `game/tests/test_stair_walk.gd:137-141`

```gdscript
var info: Dictionary = _ld.call("_get_mesh_and_shape", path) as Dictionary
var shape: Shape3D = info.get("shape") as Shape3D
if not (shape is ConcavePolygonShape3D):
	out["error"] = "no trimesh collider for " + path
	return out
```

`_get_mesh_and_shape` (`level_loader.gd:1910-1922`, `_fill_authored_shape`
`:2000-2043`) now returns `shape = shapes[0]` — the **first** authored element —
plus the full `shapes` / `shape_offsets` arrays. Six of the seven flights are a
single convex hull, so the old type check rejects them.

Measured (`-- d10` mode of the new suite):

| flight | authored elements | `resolve()` | `_get_mesh_and_shape` | union AABB vs render AABB (Δpos / Δsize, m) |
|---|---:|---|---|---|
| `SM_Stairs_Civic_3x150cm` | 1 convex | hull, 1 shape | `shape=ConvexPolygonShape3D`, `shapes=[convex]` | (−0.004, 0.005, 0.019) / (−0.007, 0.012, 0.157) |
| `SM_Stairs_Industrial_3x150cm` | 1 convex | hull, 1 | `shape=ConvexPolygonShape3D`, 1 | (0.209, 0.034, −0.011) / (−0.414, −0.125, 0.137) |
| `SM_StairsCity6x2m` | 1 convex | hull, 1 | `shape=ConvexPolygonShape3D`, 1 | (0.034, 0.032, 0.048) / (−0.079, −0.065, 0.311) |
| `SM_Stairs_Civic_3x850cm` | 1 convex | hull, 1 | `shape=ConvexPolygonShape3D`, 1 | (0.090, 0.011, 0.020) / (−0.183, −0.003, 0.198) |
| `SM_Stairs_Civic_3x150cm` (rotX, descent) | 1 convex | hull, 1 | `shape=ConvexPolygonShape3D`, 1 | same mesh |
| `SM_Stairs_Industrial_3x150cm` (rotZ) | 1 convex | hull, 1 | `shape=ConvexPolygonShape3D`, 1 | same mesh |
| `SM_OldManor_Tower_Stairs_4x850` | **36 convex** | **reduced**, 1 coalesced trimesh | `shape=ConcavePolygonShape3D`, 1 | (−0.020, −0.039, −0.019) / (0.040, 0.049, 0.084) |

Red output (`flock … test_stair_walk.gd`, exit 1):

```
FAIL: civic_3x150 stair fixture: no trimesh collider for /Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x150cm
FAIL: civic_3x150 ascent did NOT end on the floor: ?
FAIL: industrial_3x150 stair fixture: no trimesh collider for /Game/Art/Environment/Urban/Industrial/Stairs/SM_Stairs_Industrial_3x150cm
FAIL: industrial_3x150 ascent did NOT end on the floor: ?
FAIL: city_6x2m stair fixture: no trimesh collider for /Game/Art/Environment/City/Architecture/Stairs/2m/SM_StairsCity6x2m
FAIL: city_6x2m ascent did NOT end on the floor: ?
FAIL: poi_3x850 stair fixture: no trimesh collider for /Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x850cm
FAIL: poi_3x850 ascent did NOT end on the floor: ?
FAIL: civic_3x150_rotX stair fixture: no trimesh collider for /Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x150cm
FAIL: civic_3x150_rotX descent did NOT end on the floor: ?
FAIL: industrial_rotZ stair fixture: no trimesh collider for /Game/Art/Environment/Urban/Industrial/Stairs/SM_Stairs_Industrial_3x150cm
FAIL: industrial_rotZ ascent did NOT end on the floor: ?
FAIL: oldmanor_tower_4x850 ascent FAILED: moved=-0.02 m (< 8.40), zero streak=268 (> 2), max air streak=0, drift=0.000 m, camera lag=0.000 m, settle=1 frames, mantled=false, frames_to_target=-1, end=(22802.01, 0.000158, 20000.32)
PASS: oldmanor_tower_4x850 ascent ends grounded (is_on_floor=true)
W6M_STAIR_SUMMARY: fails=13
```

Note the second defect the type check hides: `oldmanor_tower_4x850` **passes** the
shape assertion (36 elements > `MAX_CONVEX_ELEMENTS_PER_MESH = 16`, so
`resolve()` coalesces the element AABBs into one `ConcavePolygonShape3D`) and
then fails the walk — the coalesced AABB boxes have no treads, so the body does
not climb (`moved=-0.02 m`, `zero streak=268`).

### B. `game/tests/test_traversal_routes.gd:592-598`

```gdscript
var info: Dictionary = _roof_loader().call("_get_mesh_and_shape", ue_path)
var mesh: Mesh = info.get("mesh") as Mesh
var shape: Shape3D = info.get("shape") as Shape3D
if mesh == null or shape == null:
	return {}
...
cs.shape = shape
cs.position = info.get("shape_offset", Vector3.ZERO)
```

Only `shapes[0]` of a 3-or-4-hull roof is placed. Measured element counts:
`SM_RoofUrban_Ext_Mid_4x4` (ROOF_SHALLOW / hip) = **3 convex**;
`SM_RoofUrbanB_Ext_Mid_6x8` (ROOF_STEEP) = **4 convex**; the EndA/EndB/Mirror
shells = **4 convex** each. Per-hull pitch of the hip mesh (from the authored
planes): hull 0 = 59.0°, hull 1 = 45.4°, hull 2 = 25.4°; scaled (1,1,0.8):
64.3° / 51.7° / 30.6°.

Red output (`flock … test_traversal_routes.gd`, exit 1):

```
FAIL: steep roof 74.0 deg FAILED: ascent 3.42 m (>= 0.30), mantle=true
FAIL: hip roof: quarter faces only 0.81 m below the ridge (4.06 m) - flat or missing faces
FAIL: non-uniform POI roof: measured 57.8 deg vs expected 51.5 deg
FAIL: non-uniform POI roof 57.8 deg: ascent 0.78 m, mantle=false
W6M_TRAVERSAL_SUMMARY: fails=4
```

Union-vs-first-hull probe (same suite's 5×5 height field, printed by `-- d10`):

```
SM_RoofUrban_Ext_Mid_4x4 scale=(1,1,1)   elements=3
    first_hull: samples=15 apex=4.06 eave=1.92 pitch=51.8
    all_hulls:  samples=25 apex=4.06 eave=0.72 pitch=51.8
SM_RoofUrban_Ext_Mid_4x4 scale=(1,1,0.8) elements=3
    first_hull: samples=15 apex=4.06 eave=1.92 pitch=57.9
    all_hulls:  samples=15 apex=4.06 eave=1.92 pitch=57.9
SM_RoofUrbanB_Ext_Mid_6x8 scale=(1,1,1)  elements=4
    first_hull: samples=15 apex=8.28 eave=4.37 pitch=74.0
    all_hulls:  samples=25 apex=8.28 eave=1.33 pitch=74.0
```

* **Hip**: the union covers all 25 samples and drops the eave to 0.72 m
  (apex 4.06 → 3.34 m below the ridge) — the 1.0 m "quarter faces" check then
  passes. This failure is purely the missing hulls.
* **Steep**: the union raises coverage 15 → 25 samples and moves the eave from
  4.37 m (a mid-shell sample) to 1.33 m; the refusal verdict must be re-measured
  on the corrected fixture — the 74° pitch and the `mantle=true` are unchanged
  by the union alone, so do not pre-declare it green.
* **Non-uniform POI**: the union does **not** change the measured 57.9° (both
  rows identical) because `_roof_field_pitch` takes the *steepest sampled pair*
  and hull 0 is the 59.0° face. The expected 51.5° is `atan(tan(45.2)/0.8)`,
  i.e. the **hip face** (hull 1, 45.4° → 51.7°). The assertion is measuring the
  wrong face; it cannot pass with any hull count.

### Corrected assertions (recommended)

Reuse the existing correct pattern — `game/tests/test_roof_collision.gd`
`_authored_union()` (`:171-194`) and `check_policy_shapes()` (`:313+`) already do
per-element unions.

**`test_stair_walk.gd`** — replace the single-shape gate with:

1. **Build** the fixture from `info["shapes"]` + `info["shape_offsets"]`, one
   `CollisionShape3D` per (shape, offset), with the non-uniform instance scale
   baked through `AuthoredCollision.scaled_variant` exactly as
   `_add_collider_shapes` does (`level_loader.gd:4249-4281`); `shape` is not the
   fixture any more.
2. **Assert the authored union** before walking: `shapes.size() ==
   resolve().elements` for a non-reduced mesh (1 for the six single-hull
   flights), every shape present, union AABB within **0.5 m** of the render mesh
   AABB in position and size (measured worst case 0.21 m / 0.42 m), and the walk
   grounded (`end_on_floor`).
3. **Old Manor**: 36 authored hulls are currently reduced by
   `MAX_CONVEX_ELEMENTS_PER_MESH = 16`, and the coalesced AABB trimesh cannot be
   walked. Choose one, in writing: (a) raise the per-mesh cap for stair meshes
   (35 extra shapes for one mesh; the Guildhall load measures
   `shapes_per_instance_avg=1.14`, so the 250-cost/32 k budget has room — verify
   `probe_collision_authored` coverage and the budget line after the change), or
   (b) keep the reduction and record `oldmanor_tower_4x850` as a known
   non-walkable flight in `docs/FIDELITY_GAPS.md` with the measured
   `moved=-0.02`. Do **not** weaken the assertion to "any shape is fine" and
   leave the walk failing silently.

**`test_traversal_routes.gd`** — `_make_roof()` must build every
`shapes[i]`/`shape_offsets[i]`; then:

1. assert `shapes.size() == elements` and all `ConvexPolygonShape3D` (or the
   reduced trimesh where `reduced`), as `test_roof_collision` does;
2. keep the hip "quarter faces" check (now reachable: 0.72 m vs apex 4.06 m);
3. re-measure the steep-roof refusal on the full shell;
4. replace the non-uniform pitch check with a **face-specific** one: identify the
   hip face (the hull whose authored plane is 45.4°) and assert its scaled pitch
   is 51.7° ± 2.5°, or drop the pitch assertion and gate on the walk. The
   current global-steepest metric returns 59°/64.3° by construction.

**Retirement?** No. The walk is the only end-to-end check that authored stair and
roof collision is traversable; the fixtures are wrong, not the intent. Retiring
them would remove the only coverage of `_get_mesh_and_shape`'s authored path at
the walking layer.

---

## The new suite

`game/tests/test_w10_runtime.gd` — standalone `extends SceneTree`, `_init` →
`call_deferred`, temp file under `user://` (removed), prints
`W10_RUNTIME_SUMMARY: fails=N checks=M`, exits 1 on fails.

Run:

```bash
flock /tmp/opencode/tat2-godot.lock -c \
  "timeout 900 tools/godot --headless --path game --script res://tests/test_w10_runtime.gd"
flock /tmp/opencode/tat2-godot.lock -c \
  "timeout 900 tools/godot --headless --path game --script res://tests/test_w10_runtime.gd -- d10"
```

Current result at HEAD (green; the D6/D7 fixes are in the tree):

```
W10_RUNTIME_SUMMARY: fails=0 checks=45
```

Pre-fix red (same file's first version, `29046c8`, log `inv2_final2.log`):

```
W10_RUNTIME_SUMMARY: fails=4 checks=9
FAIL: trace NDJSON file is unbounded: 9000 lines written for 9000 pushed rows (cap 8192); ring=8192 dropped=808
FAIL: ward zone emits a zero-volume convex hull: [{ "points": 8, "extent_m": 0.0, "aabb": [P: (-0.01, -0.0, -0.01), S: (0.02, 0.0, 0.02)] }]
FAIL: flat FX quads emitted as zero-volume hulls: ["FXSHAPES_1_FXQuadPivotCenter", "FXSHAPES_1_FXQuadPivotDownEdge"]
FAIL: ward zone does not report a counted degenerate skip (degenerate=<null>, expected >= 1)
```

The 45 checks now cover: D6 ring cap (3), D6 file budget — declared constants,
rows/bytes/dropped, exact on-disk length, stop-not-slow-down, independent byte
cap (10); D7 census (`zero_axis_boxes=1`, `flat_convex=3`, the 14 float-residue
glass boxes, 8 near-flat-but-real convex) and shape kinds (2 + 4); the planar
rule — `resolve()` shapes/offsets empty, `planar_convex_skipped==1`, the
cumulative counter increments once per fresh key and not on a cache hit, one
more for a second placement count, `planar_skipped_paths` contains the ward and
FX paths and is capped at 32 (12); and the negative controls — `/Engine/BasicShapes/Plane`
and `SM_Storefront_Facade_1200_Glass` still return one clamped box
(`box_clamped=1`, `planar=0`), the 14-element `SM_OldManor_Doorway_4x650` keeps
14 hulls at 1 placement and reduces to 1 at 37, no element of it is treated as
planar (10); plus the grounding check (1): the loader's ward set is empty, a
downward ray from y=2.0 reaches the floor at y≈0, and a horizontal control sheet
rebuilt from the authored points at y=1.0 answers the same ray at y=1.0 — the
control must use an **identity basis** (the hull already lies in local XZ, so
local +Y is its normal); a 90° X rotation stands it edge-on and the control
proves nothing (this was measured once: `hit=true y=0.000`).

Two implementation notes for whoever owns the file next:

* `_check_planar_rule()`'s "counter increments once for a fresh resolve" reads
  `AC.resolve(WARD_ZONE, 1)`. Do not call `_get_mesh_and_shape(WARD_ZONE)` (which
  resolves the same `path|1` key) earlier in the run, or the counter assertion
  sees a cache hit and fails. The first version of this suite did exactly that in
  the ward mesh-AABB probe; the probe was removed for this reason.
* `-- d10` is diagnostic only (it prints, it does not assert). Its output at HEAD
  is the D10 table in this report; 45 checks is the default run.

---

## Caveats / not verified

* The Jolt "solid region" measurement is a `PhysicsDirectSpaceState3D` shape
  query against a body built exactly like `_add_collider(..., bake_scale=true)`
  at the real authored placement; it is not a full-mission playthrough. The
  result was identical for the 2 cm local hull and the 0.8 m placed hull.
* I did not verify the 160 ward colliders in a live Guildhall load by name; the
  code path is proven (`collide=true` for a non-decorative sublevel,
  `_build_draw_items` → `_add_collider_shapes`) and the shape/placement facts are
  measured. The real boot's `AUTHORED_COLLISION … shapes_per_instance_avg=1.14`
  is consistent with them being emitted.
* `docs/reports/logs/w9/` has no runtime-smoke log; my 90 s boot log lives only
  in `/tmp/opencode/w10a/smoke-real.log`. Commit it (or a copy) with the D9 fix.
* This file is under `build/qa/w10/`, which `.gitignore:25` ignores (only
  `.gd/.sh/.py` are un-ignored). The lead must `git add -f` the `.md` files or
  add a `.gitignore` exception, or the evidence never lands.
