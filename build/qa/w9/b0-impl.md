# W9-P2 / B0 — rebase `test_roof_collision.gd` onto the authored per-element hull union

Worktree: `/home/john/Projects/TAT-2-rem-w9-p2` (branch `rem/w9-p2`)
Base HEAD: `b13260b3da78273edc98e54a1ae5d167c5ad431b`
Lane: B0 (standalone probe rebase; no gate, no `level_loader.gd` change)

## Files changed

| File | Change |
|---|---|
| `game/tests/test_roof_collision.gd` | Rebased all collision-shape assertions from the loader's `info["shape"]` / `shapes[0]` compatibility field (called with `n=1`) onto `AuthoredCollision.resolve(path, load_count)`. Added `_authored_union()`, `_shape_points()`, `_points_aabb()`, `_roof_counts()`, `OLDMANOR_ENCODINGS`. |
| `build/qa/w9/b0-impl.md` | This report (git-ignored by the repo's `build/qa/*.md` rule; force-add if the lead wants it committed). |

No other file was edited. `game/src/**`, `run_tests.gd`, `game/data/generated/`,
`extracted/` and all captures were untouched.

## Method — `_authored_union(ue_path, instances)`

Precedent: `game/tests/probe_collision_authored.gd:42` preloads the same module.

```gdscript
const AuthoredCollision: GDScript = preload("res://src/core/collision/authored_collision.gd")
var res: Dictionary = AuthoredCollision.resolve(ue_path, maxi(instances, 1))
```

* `instances` is the **load-truth placement count** for the path, counted from the
  shipped `*.tatlevel.json` (`_roof_counts()`). This is the input the loader's
  per-path cost cap uses (`_fill_col_path_counts` → `resolve(path, n)`), and it
  is why `SM_RoofUrban_Ext_Corner_4x4x4` is 13 hulls at `n=1` but one coalesced
  trimesh at `n=38` (`(13 - 1) * 38 = 456 > MAX_ELEMENT_SHAPE_COST = 250`).
  `SkyboxGeo` is a decorative sublevel (`DECORATIVE_SUBLEVEL_TOKENS`) and its
  5,166 roof instances do not collide, so the PeripheryA counts are the load
  truth for this probe.
* For every returned shape, its authored points are transformed by its own
  `offsets[i]` (convex hulls bake their element `FTransform` into the points and
  keep `Transform3D.IDENTITY`). The union point set and union AABB are built
  from that.
* `_shape_points()` uses convex points, concave faces, box corners, sphere
  support points and capsule support points, so the union AABB is exact for
  every element type.
* The loader's `info["mesh"]` (or `_get_mesh_and_shape`) is used **only** for the
  render-mesh AABB / `_measure_roof_top_coverage`. No collision assertion reads
  `info["shape"]` any more except the Old Manor complex-default case, where the
  render trimesh is itself the authored answer.
* The probe is therefore mode-independent and passes under both
  `TAT2_COLLISION=authored` and `TAT2_COLLISION=aabb`. Loader-integration truth
  (the loader really emits `shapes`/`shape_offsets`) is owned by
  `probe_collision_authored.gd`, whose `COL_AUDIT` line is quoted below.

## The 9 RED assertions, old first-element value vs authored union

The old probe called `_get_mesh_and_shape()` without `_col_path_counts`, so
`_fill_authored_shape()` used `n=1` and `info["shape"]` was `shapes[0]` only.

### 1. `check_policy_shapes` — convex-policy (`:225` old)

Old: every convex-policy mesh must be `ConvexPolygonShape3D` with zero offset and
more than 8 points.

RED: `SM_RoofUrban_Ext_BayWindowA_6x4 (ConcavePolygonShape3D)`.
Reason: 27 convex elements > `MAX_CONVEX_ELEMENTS_PER_MESH = 16`, so the authored
encoding is **reduced** — exactly one coalesced `ConcavePolygonShape3D`. The old
assertion demanded a hull and failed on the authored truth.

New: `source != "absent"`; if `reduced` → exactly one `ConcavePolygonShape3D`;
else (`source == "hull"`) `shapes.size() == elements` and every shape is a
`ConvexPolygonShape3D` with an identity offset; `source == "prims"` is accepted
as the one exact tessellation. Non-reduced unions keep the
`_hull_top_span_fraction(...) < 0.20` contract, measured against the **union**
AABB footprint (see `SM_RoofUrban_Ext_Mid_4x4`: 0.019;
`SM_RoofUrbanB_Ext_Mid_6x8`: 0.144).

### 2. `check_policy_shapes` — box-policy (`:228` old)

Old: every box-policy mesh must be a `BoxShape3D` with a centre offset.

RED: 11 meshes failed — 10 authored multi-element sets
(`ChimneyExtG/M/H/J/D`, `RoofUrban_Corner_Trim`, `PipeD`, `WaterTowerA/F/G`)
and `ChimneyCityLrgA_Top` (3 convex hulls). All 27 box-policy meshes measured:

| Authored encoding | Meshes | Shapes |
|---|---|---|
| 1 authored box element | 13: `Mid_Trim_1m/2m/4m/6m`, `Ext_Side_1x4/2x4/4x4/6x4`, `RoofUrbanB_Ext_Side_1x8/2x8/4x8/6x8`, `GB_RoofFloor_6x6` | the authored `BoxShape3D` (still a box), centre offset non-zero, box size == union AABB |
| primitive-only, >1 element | 10: `PipeD` (2), `WaterTowerA` (4), `WaterTowerF` (3), `WaterTowerG` (2), `ChimneyExtD` (2), `ChimneyExtG` (7), `ChimneyExtH` (5), `ChimneyExtJ` (10), `ChimneyExtM` (4), `Corner_Trim` (2) | one exact tessellated `ConcavePolygonShape3D` |
| hull/mixed set | 4: `ChimneyCityLrgA_Top` (3 convex), `ChimneyExtB/I/K` (2 elements: box + convex) | one shape per element |

`ChimneyExtB/I/K` passed the old box test **by accident**: their first element is
a box, so `shapes[0]` was a `BoxShape3D`; the authored set has a second convex
element the old assertion never saw. The new assertion checks `shapes.size()`.

New: `source != "absent"`; single-element primitive → the authored primitive
(a box stays a `BoxShape3D`, with non-zero authored centre and matching size);
multi-element `prims` → one tessellated trimesh; multi-element `hull` →
`shapes.size() == elements`, every shape a convex hull or authored primitive;
`reduced` → one coalesced trimesh. The old "one render-AABB box" encoding is
now a failure.

### 3. `check_end_shells` — union top (`:343` old)

Old: the first hull's bbox must reproduce the render AABB top and z span within
0.01 m.

RED (old first hull `top` vs render `top`, first-hull `z span` vs render `z span`):

| Shell | first-hull top | render top | first-hull z | render z |
|---|---:|---:|---:|---:|
| `Ext_EndA_2x4x4` | 3.171 | 4.316 | 4.482 | 5.126 |
| `Ext_EndB_2x4x4` | 2.989 | 4.316 | 4.384 | 5.110 |
| `Ext_EndB_2x4x4_Mirror` | 2.945 | 4.316 | 4.410 | 5.110 |
| `RoofUrbanB_Ext_EndA_2x2x8` | 7.484 | 8.474 | 4.030 | 5.039 |
| `RoofUrbanB_Ext_EndB_2x2x8` | 8.310 | 8.474 | 3.796 | 5.094 |
| `RoofUrbanB_Ext_EndA_2x2x8_Mirror` | 8.430 | 8.474 | 2.334 | 5.039 |

Union truth (4 hulls each): tops 4.264 / 4.391 / 4.365 / 8.420 / 8.392 / 8.435
(max delta to render top 0.082 m); union z spans 5.133 / 5.136 / 5.131 / 5.237 /
5.232 / 5.202. The first hull is one gable cheek, not the shell.

New: union top within **0.10 m** of the render AABB top. The z-span equality is
**removed** (union z spans can overshoot the render AABB by 0.198 m; it carries
no meaning for the eave contract).

### 4. `check_end_shells` — eave gap (`:346` old)

Old: first-hull eave band gap `2.68 m < 3.0 m`.
Union truth: 3.50 / 3.57 / 3.57 / 7.08 / 7.53 / 7.63 m (min 3.50 m).
New: `min_eave_gap >= MIN_EAVE_GAP_M` (3.0 m), measured from the union points and
union z ends. Pass message now reports `3.50 m`.

### 5. `check_old_manor_census` — census (`:508` old)

Old: 6 unique tower-roof meshes, **all** `ConcavePolygonShape3D` (`trimesh=6`).
RED: `unique=6 trimesh=4` — the authored truth is

| Mesh | Elements | Authored encoding |
|---|---:|---|
| `SM_OldManor_TowerRoof_Combo_01` | 419 (413 convex) | reduced → 1 coalesced trimesh |
| `SM_OldManor_TowerRoof_Int_Combo_01` | 62 convex | reduced → 1 coalesced trimesh |
| `SM_OldManor_TowerRoof_Int_Combo_02` | 95 convex | reduced → 1 coalesced trimesh |
| `SM_OldManor_TowerRoof_Combo_02` | 10 convex | 10 `ConvexPolygonShape3D` |
| `SM_OldManor_TowerRoof_Fence` | 1 box | 1 authored `BoxShape3D` |
| `SM_OldManor_TowerRoof_Combo_Glass` | no AggGeom record | `complex_default` render trimesh |

New: per-mesh encoding table (`OLDMANOR_ENCODINGS`), census assertion
`6 = 3 reduced + 1 hull set + 1 box + 1 complex`, and the encoded shapes are
checked individually. The "no box plateau" intent is preserved: the Fence box is
the authored 18.5 x 7.9 m fence slab, not a rendered-AABB plateau, and all six
remain non-occluders.

### 6. `check_old_manor_census` — shape classes (`:514` old)

RED: `SM_OldManor_TowerRoof_Combo_02 (ConvexPolygonShape3D)` and
`SM_OldManor_TowerRoof_Fence (BoxShape3D)` were reported as problems because the
old check demanded `ConcavePolygonShape3D` for every mesh. Those two classes are
the authored answers (10 convex hulls; 1 authored box). New: `bad_shape` is the
per-mesh encoding check above; `Combo_Glass` is the only render-trimesh case and
is asserted as `source == "complex_default"` plus loader `ConcavePolygonShape3D`.

### 7. `check_real_roof_heights` — shallow pitch (`:698` old)

Old: first hull z run 2.332 m against the render rise 4.22 m → **61.1°**.
Union: 3 hulls, 48 hull points, union AABB
`(-4.142, -0.058, -3.129) -> (0.199, 4.179, 1.043)`, y span 4.236 m, z span
4.172 m → **45.4°** (expected 45 ± 2).
New: pitch from the union AABB (`rise = u.aabb.size.y`, `run = u.aabb.size.z`).

### 8. `check_real_roof_heights` — shallow eave (`:706` old)

Old: first-hull eave band **2.51 m** below the render AABB top.
Union: **3.55 m** (facts table: 3.51 m with the 0.15-run band at the union's own
z end; the probe's exact run gives 3.55 m).
New: `gap >= 3.0 m` from the union points / render AABB top.

### 9. `check_real_roof_heights` — steep pitch (`:698` old)

Old: first hull z run 2.008 m → **76.4°** (RED line).
Union: 4 hulls, 58 hull points, union AABB
`(-6.070, -0.086, -2.464) -> (0.074, 8.281, 1.085)`, y span 8.367 m, z span
3.548 m → **67.0°** (expected 68 ± 2). Steep union eave gap 7.09 m.

### Additional (new) checks — load-truth census

* `19 convex meshes / 426 instances drive the union` — the same 426/19 the policy
  census asserts, counted from the shipped level JSON.
* `load-truth instance counts coalesce exactly the 2 over-cap convex roofs
  (27 els / 13x38)` — `BayWindowA_6x4` (27 > 16) and `Corner_4x4x4`
  (`(13-1)*38 = 456 > 250`). Every other convex roof stays per-element
  (e.g. `MidWindowA_4x4`: 6 hulls × 45 instances = 225 ≤ 250).

## Proof

Every Godot invocation was headless and wrapped:

```
flock /tmp/opencode/tat2-godot.lock -c \
  "timeout 900 tools/godot --headless --path game --script <res://...>"
```

### 1. RED (before the edit), authored

```bash
flock /tmp/opencode/tat2-godot.lock -c "timeout 900 tools/godot --headless --path game --script res://tests/test_roof_collision.gd"
```

`42 PASS / 9 FAIL`, exit 1:

```
FAIL: convex roof shape problems: ["/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_BayWindowA_6x4 (ConcavePolygonShape3D)"]
FAIL: box roof shape problems: [".../SM_ChimneyExtG (ConcavePolygonShape3D)", ".../SM_ChimneyExtM (ConcavePolygonShape3D)", ".../SM_RoofUrban_Corner_Trim (ConcavePolygonShape3D)", ".../SM_PipeD (ConcavePolygonShape3D)", ".../SM_WaterTowerA (ConcavePolygonShape3D)", ".../SM_WaterTowerG (ConcavePolygonShape3D)", ".../SM_WaterTowerF (ConcavePolygonShape3D)", ".../SM_ChimneyExtH (ConcavePolygonShape3D)", ".../SM_ChimneyExtJ (ConcavePolygonShape3D)", ".../SM_ChimneyCityLrgA_Top (ConvexPolygonShape3D)", ".../SM_ChimneyExtD (ConcavePolygonShape3D)"]
FAIL: End hull does not match the visual: ["SM_RoofUrban_Ext_EndA_2x4x4 (top 3.171 vs 4.316, z 4.482 vs 5.126)", "SM_RoofUrban_Ext_EndB_2x4x4 (top 2.989 vs 4.316, z 4.384 vs 5.110)", "SM_RoofUrban_Ext_EndB_2x4x4_Mirror (top 2.945 vs 4.316, z 4.410 vs 5.110)", "SM_RoofUrbanB_Ext_EndA_2x2x8 (top 7.484 vs 8.474, z 4.030 vs 5.039)", "SM_RoofUrbanB_Ext_EndB_2x2x8 (top 8.310 vs 8.474, z 3.796 vs 5.094)", "SM_RoofUrbanB_Ext_EndA_2x2x8_Mirror (top 8.430 vs 8.474, z 2.334 vs 5.039)"]
FAIL: End hull eave gap 2.68 m < 3.0 m
FAIL: Old Manor roof census changed: unique=6 trimesh=4
FAIL: Old Manor roof shape problems: ["SM_OldManor_TowerRoof_Combo_02 (ConvexPolygonShape3D)", "SM_OldManor_TowerRoof_Fence (BoxShape3D)"]
FAIL: shallow roof pitch 61.1 deg outside 45.0 +/- 2.0
FAIL: shallow roof hull eave band only 2.51 m below the AABB top (want >= 3.0 m)
FAIL: steep roof pitch 76.4 deg outside 68.0 +/- 2.0
ROOF_COLLISION_SUMMARY: fails=9
```

Full log: `/tmp/opencode/b0-red-authored.log`.

### 2. RED aabb control (before the edit)

```bash
flock /tmp/opencode/tat2-godot.lock -c "TAT2_COLLISION=aabb timeout 900 tools/godot --headless --path game --script res://tests/test_roof_collision.gd"
```

`51 PASS / 0 FAIL`, exit 0:

```
ROOF_COLLISION_SUMMARY: fails=0
```

Full log: `/tmp/opencode/b0-red-aabb.log`.

### 3. GREEN after the edit — both modes

```bash
flock /tmp/opencode/tat2-godot.lock -c "timeout 900 tools/godot --headless --path game --script res://tests/test_roof_collision.gd"
flock /tmp/opencode/tat2-godot.lock -c "TAT2_COLLISION=aabb timeout 900 tools/godot --headless --path game --script res://tests/test_roof_collision.gd"
```

Both: `53 PASS / 0 FAIL`, exit 0.

```
ROOF_COLLISION_SUMMARY: fails=0
```

Re-run on the final bytes (a trailing-blank-line-only edit followed the first
green pair) at 13:22:31 / 13:22:37: same `53 PASS / 0 FAIL`, byte-identical logs
`/tmp/opencode/b0-final-authored.log` and `/tmp/opencode/b0-final-aabb.log`.
The earlier pair is `/tmp/opencode/b0-green-authored-1.log` /
`/tmp/opencode/b0-green-aabb-1.log`.

(53 = the original 51 checks, all nine failures rebased onto authored truth with
no check deleted, plus the two new load-truth census checks. Every old
assertion's intent survives; only the wrong measurement was replaced.)

Key GREEN lines:

```
PASS: 19 convex roofs: authored per-element union (min 10 hull points), top span < 0.20
PASS: 27 flat/prop roofs: authored primitive/hull sets; single boxes keep the authored box
PASS: load-truth census: 19 convex meshes / 426 instances drive the union
PASS: load-truth instance counts coalesce exactly the 2 over-cap convex roofs (27 els / 13x38)
PASS: End shell union top matches the visual AABB within 0.10 m
PASS: End union eave band sits 3.50 m below the AABB top the box floated
PASS: Old Manor tower roofs: 6 meshes = 3 reduced trimeshes + 1 ten-hull set + 1 box + 1 complex trimesh
PASS: Old Manor tower roofs match their authored per-mesh encoding
PASS: shallow roof authored union pitch 45.4 deg (rise 4.24 m / run 4.17 m)
PASS: shallow roof union eave band sits 3.55 m below the AABB top the box used
PASS: steep roof authored union pitch 67.0 deg (rise 8.37 m / run 3.55 m)
PASS: steep roof union eave band sits 7.09 m below the AABB top the box used
```

Full logs: `/tmp/opencode/b0-final-authored.log`,
`/tmp/opencode/b0-final-aabb.log` (and the identical earlier pair
`/tmp/opencode/b0-green-authored-1.log` / `/tmp/opencode/b0-green-aabb-1.log`).

### 4. Loader-integration probe unchanged

```bash
flock /tmp/opencode/tat2-godot.lock -c "timeout 900 tools/godot --headless --path game --script res://tests/probe_collision_authored.gd"
```

```
COL_AUDIT mode=authored placed_meshes=947 placed_meshes_seen=947 placed_instances=27222 authored_hull=937 authored_prims=599 absent=10 no_collision=7 query_only=7 reduced=16 shapes=30901 bodies=243 dropped=0 load_ms=19992 coverage=0.989 fps_pose=n/a
```

`dropped=0`, `coverage=0.989`, `reduced=16` unchanged. Full log:
`/tmp/opencode/b0-col-audit.log`.

## Residual caveats

1. **Mode independence is intentional.** The rebased assertions read
   `AuthoredCollision.resolve()` directly, not `info["shape"]`, so they assert
   the data the loader consumes in authored mode and still pass in `aabb` mode.
   The probe no longer proves that the *active* loader emitted those shapes;
   `probe_collision_authored.gd` owns that integration proof (`dropped=0`,
   `coverage=0.989` above). This is the trade the brief asked for.
2. **Reduced roofs lose per-element pitch by design.** `BayWindowA_6x4` and
   `Corner_4x4x4` are coalesced element-AABB trimeshes under the load-truth
   instance counts (the documented `reduced=16` set). The probe names exactly
   those two and does not pretend their cover is a pitched hull; the eave/pitch
   contracts are asserted on the non-reduced roofs that still carry authored
   hulls.
3. **Top span uses the union AABB footprint**, matching the W9-P2 facts
   (Mid_4x4 0.019, Mid_6x8 0.144, End shells 0.000–0.105). The old helper used
   the render AABB; the union footprint is the collision surface's own bound and
   is what the facts were measured against.
4. **POI 3rd-floor and occluder checks are unchanged.** They still exercise the
   loader path (`_get_mesh_and_shape`, `_qualifies_as_occluder`) and passed in
   both modes; only the nine authored-truth failures plus the ridge union were
   rebased.
5. **Shared worktree:** other W9-P2 lanes were editing the same checkout while
   this lane ran (e.g. `game/src/core/level_loader.gd` mtime 13:04, lock-key
   plumbing only; the collision code was unchanged). The RED logs were captured
   at 13:00:45/13:00:51, before those writes; the first GREEN pair at
   13:06:45/13:06:56, and the final byte-for-byte re-run at 13:22:31/13:22:37,
   after them. The loader diff touches marker lock fields and not
   `_fill_authored_shape`/`_collision_mode`; all four runs quoted above are real
   outputs, not reconstructed.
6. **No full gate was run from this lane** (compile/`make test`/E2E/audit belong
   to the integrator at the merged HEAD). `--check-only` on the edited script
   passed, and the probe itself ran green twice.

## Summary

```
RED   authored: ROOF_COLLISION_SUMMARY: fails=9   (42 PASS)
RED   aabb    : ROOF_COLLISION_SUMMARY: fails=0   (51 PASS)
GREEN authored: ROOF_COLLISION_SUMMARY: fails=0   (53 PASS)
GREEN aabb    : ROOF_COLLISION_SUMMARY: fails=0   (53 PASS)
COL_AUDIT: ... dropped=0 ... coverage=0.989 fps_pose=n/a
```
