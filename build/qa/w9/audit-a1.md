# W9-P1 A1 — independent audit of the authored UE `AggGeom` collision commit

**Auditor:** A1 (independent, read-only). I did not write this code.
**Commit under audit:** `ff0f21d` "feat(collision): consume the authored UE AggGeom for every mesh (W9-P1 A1)".
**Worktree:** `/home/john/Projects/TAT-2-rem-w9-p1`. The commit under audit is `ff0f21d`; the
four files in scope are **byte-identical** from `ff0f21d` through the final HEAD at the end of
this audit (`ce80ade`) — `git diff ff0f21d..HEAD -- <the four files>` is empty. HEAD during my
runs was `5a516f9` plus in-progress edits from other lanes (committed as `8a3c113` at 11:45),
which touched the harness but never the collision code.
**Date:** 2026-11-25.
**Scope:** `game/src/core/collision/authored_collision.gd` (new), `game/tests/probe_collision_authored.gd` (new),
`build/qa/w9_collision_ab.sh` (new), and the collision hunks of `game/src/core/level_loader.gd`.
**Method:** read the code, then try to falsify each numeric claim against the data
(`game/data/generated/mesh_collision.json`) and against the exported GLBs (glTF JSON chunk
parsed with `struct`/`json` in stdlib Python — no packages installed). Runtime numbers are
from my own headless Godot runs in this worktree.

**Milestone status:** all nine items were run to completion. Two runtime legs (the A/B
control and the traversal set) had to be re-run outside `w9_collision_ab.sh` because other
lanes held the shared Godot lock / were editing shared files mid-run; every number quoted
below is from a real run in this worktree, and the affected rows say exactly what happened.

---

## VERDICT (summary)

**ACCEPT, with 3 findings and 2 open risks.** No numeric claim in the commit is falsified.
The unit trap (`half_extent` = full extent, no ×2), the capsule Z-axis/`L+2R` rule, and the
convex bake are all independently reproduced against the GLB geometry, and the
NoCollision/absent/complex-default census reconciles exactly. The findings are: a degenerate
coverage assertion in the new probe, a new 95,293-line/77 MB Jolt "unsupported non-uniform
scale" error flood that the heuristic path did not have, and three wording overstatements in
the commit message. The Jolt flood is the only behavioural regression found; it degrades log
hygiene and slightly shrinks colliders on non-uniformly scaled instances, but it does not
break the shape budget, the A/B or traversal.

| # | Item | Verdict |
|---|---|---|
| 1 | box unit trap (full extent, no ×2) | **AUDIT: PASS** |
| 2 | sphyl height/axis | **AUDIT: PASS** |
| 3 | convex bake order + scale | **AUDIT: PASS** (rotation half untestable on this payload) |
| 4 | A/B numbers + coverage | **AUDIT: PASS** on the claim; **probe coverage assertion is degenerate** (F1) |
| 5 | shape budget / partition | **AUDIT: PASS** (30,905 < 32,000; building 30,877/31,400 → 523 headroom) |
| 6 | traversal probes, both modes | **AUDIT: PASS** (M2, door walk, geometry all pass in both modes) |
| 7 | no test weakened | **AUDIT: PASS** |
| 8 | 0.45 gate / name tokens / NoCollision / QueryOnly | **AUDIT: PASS with caveat** (F3.1: spline path keeps its own 0.45 gate) |
| 9 | async `_fill_col_path_counts` fix | **AUDIT: PASS** (both call sites; 2,411 not reproduced exactly — 2,934 independent estimate) |

---

## 1. The unit trap — `AUDIT: PASS`

**Code.** `authored_collision.gd:282-287`:

```gdscript
var ext: Vector3 = _p3(el.get("half_extent"))          # _p3 = Vector3(a[0], a[2], a[1]) * 0.01
var size := Vector3(maxf(absf(ext.x), MIN_HALF_EXTENT_M*2.0), ...)
```

`_p3` (`:357-363`) is `Vector3(x, z, y) * 0.01`. So the produced `BoxShape3D.size` is
`(X, Z, Y) * 0.01` **with no factor of two** — the code matches the claim. The only
multiplier is the 0.02 m minimum *size* floor, which is a Jolt non-degeneracy clamp, not a
scale factor.

**Independent data check.** I rebuilt the code's box (AABB of the rotated box, element
`xf` applied) and compared it with the GLB world AABB (POSITION accessor `min/max` with
node transforms):

| mesh | rot | authored size (m) | GLB size (m) | max abs err |
|---|---|---|---|---|
| `SM_Urban_Ext_Wall_4x6` | identity | (4.001, 6.500, 0.300) | (4.001, 6.500, 0.300) | **0.000** |
| `SM_Civic_RailA_1x1` | identity | (2.000, 1.000, 0.338) | (2.000, 1.000, 0.302) | 0.036 |
| `SM_Floor_4x4` | identity | (4.000, 0.100, 4.000) | (4.000, 0.100, 4.000) | **0.000** |
| `SM_IronBeam_6m` | identity | (6.005, 0.244, 0.376) | (6.009, 0.244, 0.376) | 0.005 |
| `SM_DisplayCaseADoor` | roll 30° | (0.850, 0.433, 0.670) | (0.850, 0.433, 0.728) | 0.058 |

For the rotated door, ignoring the authored rotation raises the error to **0.353 m**, so the
rotation (and therefore the `P·M·P` basis) is doing real work.

Population check, all 466 identity-rotation single-box meshes that have a GLB:
**median |size error| = 0.0045 m** for the code's full-extent reading, versus
**median 3.37 m** if the value were a half-extent (×2). The full-extent reading wins on
**465/466** meshes (the single exception is `SM_FixtureWallB`, a wall sconce whose authored
box is deliberately smaller than its render backplate, so ×2 lands closer by accident). A ×2
error would show up as exactly this ~2× ratio — it does not. The producer's `notes`
("FKBoxElem X/Y/Z are HALF-extents") is indeed wrong, and the commit's correction is right.

## 2. sphyl / capsule — `AUDIT: PASS`

**Code.** `authored_collision.gd:290-300`: `rad = Radius*0.01`, `height = length*0.01 + 2*rad`
(= `(Length + 2R)*0.01`), `xf` from the same `P·M·P` basis, capsule axis = local Y after the
Y/Z swap. The comment's claim that UE's capsule axis is element-local Z and that `Length`
excludes the caps is what the numbers confirm.

| mesh | L (m) | R (m) | authored AABB (m) | GLB AABB (m) | max err |
|---|---|---|---|---|---|
| `SM_StreetSignageA` | 4.680 | 0.318 | (0.636, **5.316**, 0.636) | (0.636, **5.354**, 0.640) | 0.038 |
| `SM_LightSmA_Brass` | 0.408 | 0.107 | (0.214, **0.621**, 0.214) | (0.197, **0.621**, 0.194) | 0.020 |
| `SM_LightLrgC` | 0.175 | 0.336 | (0.673, **0.848**, 0.673) | (0.670, **0.832**, 0.669) | 0.016 |
| `SM_ClayJarPaintD1` | 0.379 | 0.159 | (0.318, **0.697**, 0.318) | (0.317, **0.626**, 0.319) | 0.071 |
| `SM_PillarBasementA_12m` | 11.868 | 0.663 | (1.326, **13.194**, 1.326) | (1.338, **12.005**, 1.353) | 1.189 |

The three near-exact matches are decisive: if `Length` were the total height, the collision
would be short by exactly `2R` (0.636 m on the street sign, 0.673 m on the lamp, 0.214 m on
the brass light). Across all 43 single-sphyl meshes, `L+2R` beats `L`-only on **37/43**
(median error 0.273 m vs 0.408 m). The six exceptions are not trees: they are the three
basement/civic pillars (`SM_PillarBasementA_12m`, `_6m`, `SM_Civic_Pillar_6`) and three
scrolls (`SM_ScrollA/B/C`), i.e. exactly the props whose authored capsule is meant to
penetrate the floor/ceiling or wrap the rolled paper — each is off by ~`2R` in one axis, the
same signature as the correct semantics plus authored overshoot. The pillar's collision is
therefore 13.19 m for a 12.005 m mesh **by authoring**, not by conversion.

## 3. Convex bake — `AUDIT: PASS` (rotation half not exercisable)

**Code.** `_baked_points` (`:308-326`): `v' = q * (scale3d ⊙ v) + translation` in UE space,
then `P(v') = (x, z, y) * 0.01`. This is UE `FTransform::TransformPosition` order (scale,
then rotate, then translate) and the code applies `scale3d` exactly where it is non-unit.

| mesh | elements | scale3d | authored AABB (m) | GLB AABB (m) | max err |
|---|---|---|---|---|---|
| `SM_CivMale_Hat_01` | 1 | identity | (0.191, 0.106, 0.243) | (0.191, 0.106, 0.243) | **0.000** |
| `SM_GlyphTrap` | 1 | identity | (1.002, 1.002, 1.002) | (0.998, 1.000, 0.998) | 0.004 |
| `SM_StatueGriffonA` | 4 | (4.752, 4.752, 4.752) | (5.861, 5.427, 4.407) | (5.992, 5.524, 4.419) | 0.131 |
| `SM_StairsCity4x2m` | 1 | (1.0, 1.189, 1.0) | (4.000, 2.000, 4.041) | (4.127, 2.054, 3.581) | 0.460 |
| `SM_CivMale_Hat_02` | 1 | identity | (0.222, 0.164, 0.260) | (0.222, 0.164, 0.260) | **0.000** |

**Scale is genuinely applied and it matters.** `SM_StatueGriffonA` is a 4.752× hull: with
the scale the AABB is 5.861 m and the centre is 0.047 m from the render centre; without it
the collision would be 1.233 m (off by 3.3 m in Y). `SM_ChimneyExtB` shows the opposite
direction (the authored hull is narrower than its flue), which is legal authored data.

**The "19 load-set hulls with non-unit scale" claim is exact:** of the hull elements on the
1,018 mesh paths placed by the 15 Guildhall files, exactly **19** have a non-unit `scale3d`
(the statues, the chimneys, the stairs, the pipes, the shelf, the window).

**What I could not falsify because the payload cannot exercise it:** all **5,922** convex
hull elements in the entire payload have an *identity* rotation, so `R·(S·v)` and `S·(R·v)`
are numerically identical here. The scale-before-rotate *order* is therefore untested by
data (it matches UE by construction, and no asset can currently disagree). Likewise
`aabb_min/max` was verified to be the pre-transform vertex AABB on **5,922/5,922** hulls
(worst deviation 0.000000), so "never used as the placed bound" is safe.

## 4. The A/B — `AUDIT: PASS` on the numbers, **gate-strength finding F1**

`bash build/qa/w9_collision_ab.sh` — my run:

```
COL_AUDIT mode=authored placed_meshes=947 placed_instances=27222 authored_hull=937 authored_prims=599 absent=10 no_collision=7 query_only=7 reduced=16 shapes=30901 bodies=243 dropped=0 load_ms=21933 fps_pose=n/a
COL_DETAIL payload_meshes=1992 payload_elements=8601 payload_convex=5922 payload_load_ms=314 authored_instances=24404 authored_shape_demand=27767 heuristic_shapes=3511 mode_requested=authored elements_on_placed=2184 convex_on_placed=899 complex_default_paths=70 placed_paths_payload=947
COL_WALL total_ms=22082 (probe must stay well under 60 s)
```

* `dropped=0` in the authored leg; `authored_hull + absent = 937 + 10 = 947 = placed_meshes`.
* Coverage `937/947 = 0.9894 = 98.9 %` — arithmetic confirmed, ≥ 95 % DoD.
* `reduced=16` matches the 16 coalesced meshes; `no_collision=7` / `query_only=7` match the
  payload's 7 QueryOnly records and the 7 post-gate NoCollision paths (reconciled exactly in
  §8). `+27` curb shapes and `+1` landscape were also re-derived from the level JSON
  (2 curb splines / 9 segments × 3 boxes = 27).

**Control leg.** The first `w9_collision_ab.sh` invocation did **not** complete its control
leg: the script's internal `flock -w 300` expired while other lanes held the shared Godot
lock, so the `aabb` leg logged nothing and the script exited non-zero
(`COL_AUDIT FAIL aabb run exited 1`). That is lock contention, not a code failure. I re-ran
the identical control command under a longer lock wait:

```
COL_AUDIT mode=aabb placed_meshes=835 placed_instances=24344 authored_hull=0 authored_prims=0 absent=835 no_collision=0 query_only=0 reduced=0 shapes=24465 bodies=225 dropped=0 load_ms=26944 fps_pose=n/a
```

| stat | authored | aabb | delta (authored − aabb) |
|---|---|---|---|
| placed_meshes | 947 | 835 | **+112** |
| placed_instances | 27,222 | 24,344 | **+2,878** |
| shapes | 30,901 | 24,465 | **+6,436** |
| bodies | 243 | 225 | **+18** |
| dropped | **0** | **0** | 0 |
| load_ms | 21,933 | 26,944 | **−5,011** |

The shape / instance / body deltas match the commit exactly (`+6,436`, `+2,878`, `+18`) and
both runs report `dropped=0`. **The load-time sign does not reproduce:** the commit reports
authored is 2.5–3.7 s *slower*; in my run authored loaded 5.0 s *faster*. The host was
under heavy multi-lane contention throughout, `load_ms` covers the whole 15-file load
(parse + materials + lights + 30 k shape creations), and the `aabb` path pays
`create_trimesh_shape()` on ~835 paths while the authored path shares ~1.3 k cheap
primitives. I therefore report my numbers but do not treat the load-cost claim as verified
either way; it needs an idle-host measurement.

The `aabb` line's `absent=835` is a control-mode artifact: in `aabb` mode `_fill_authored_shape`
never runs, so `info["col"]` is absent and `_count_collision_path` labels every path
"absent". The probe doc's definition of `absent` ("no authored answer") only holds in
authored mode; the A/B script only reads `shapes`/`dropped`/`placed*` from it, so this does
not affect the delta.

**F1 (finding, not a falsification).** The probe's coverage gate is degenerate:

```gdscript
var placed_meshes: int = int(res.get("col_authored_hull", 0)) + int(res.get("col_absent", 0))
...
if authored_hull + absent != placed_meshes: _fail(...)            # tautology, cannot fail
var coverage: float = float(authored_hull + authored_prims) / float(placed_meshes)
if coverage < MIN_AUTHORED_COVERAGE: _fail(...)                   # 0.85, and >1 by construction
```

`authored_prims` is a **subset** of `authored_hull`, so the coverage expression evaluates to
`(937 + 599) / 947 = 162 %` on this load — it can never fall below the 85 % threshold. The
commit's 98.9 % is the correct `hull/placed` ratio, but the probe does not enforce the DoD's
95 % (or anything else). A future regression from 98.9 % to, say, 80 % would still print
`COL_AUDIT ... PASS`. The classification check is likewise a tautology because
`placed_meshes` is *defined* as `hull + absent`. Recommend `coverage = hull/placed` and a
`placed_meshes` from an independent counter. This does not affect any measured number in
the commit.

Minor census note: the two diagnostic counters sum to 31,278 (`authored_shape_demand` +
`heuristic_shapes`) while the emitted total is 30,901 (a 377-shape gap). They are
diagnostics only and do not gate; the emitted `collision_shapes` is the number to trust.

## 5. Shape budget — `AUDIT: PASS`

Static checks confirmed:

* `MAX_BUILDING_SHAPES 28000 -> 31400`, `MAX_CURB_SHAPES 4000 -> 600`, and
  `31400 + 600 = 32000 = MAX_TOTAL_SHAPES` (unchanged).
* `MAX_TOTAL_SHAPES_FTUE 44000` / `MAX_BUILDING_SHAPES_FTUE 40000` untouched; the FTUE
  branch still overrides per map.
* The `run_tests` invariant is unchanged: `col_shapes >= 32000` fails (ditto `<= 0`,
  `bodies < 4`, `chunks < 500`, ...).

Measured headroom from my own `run_tests` (authored default):

```
PASS: Perf chunking (chunks=6018, multimeshes=3554, collision_bodies=243, shapes=30905, occluders=768, max_chunk_span=90.0m, distance-culled=1746, material_fallbacks=0, downscaled=0, prebake_pending=[])
SUMMARY: fails=0
```

* Total headroom `32,000 - 30,905 = 1,095` shapes.
* Building `31,400 - (30,905 - 27 curb - 1 landscape) = 31,400 - 30,877 = 523` — exactly
  the commit's "523".
* Curb `600 - 27 = 573`.
* `chunks=6018`, `multimeshes=3554` and `occluders=768` are identical to the pre-W9
  `build/qa/w9/logs/p1_baseline_run_tests.log` (6018 / 3554 / 768, shapes=24,466); only the
  shape/body counts moved (24,466 → 30,905 and 225 → 243).
* My run took 203 s (11:33:24 → 11:36:47), inside the 300 s cap.
* **Caveat:** at run time HEAD was `5a516f9` and other lanes were editing
  `game_state.gd`, `progression.gd`, `run_tests.gd` etc. in the shared working tree (those
  edits became `8a3c113` at 11:45). The four collision files are byte-identical from
  `ff0f21d` to the final HEAD (`ce80ade`) — verified with an empty `git diff` — so the
  collision numbers are valid for `ff0f21d`; the harness around them was moving. One
  aabb-mode probe pass later hit a *transient* parse error from an in-progress edit
  (`Identifier "Progression" not declared`) — see §6.
* Cross-check inside `run_tests`: the Guildhall load prints the same census as the A/B probe
  (`hull=937 prims=599 absent=10 no_collision=7 query_only=7 reduced=16`), and the FTUE load
  prints `meshes=692 hull=687 prims=384 convex=2726 absent=5 no_collision=8 query_only=5
  reduced=36`, i.e. the authored path is live on every map that loads, not just the A/B set.

## 6. Traversal, flag on and off — `AUDIT: PASS`

All runs below are headless in this worktree, each bounded at 300 s, one at a time under the
shared Godot lock. Same script, same tree, only `TAT2_COLLISION` differs.

| probe | authored (default) | aabb (control) | difference |
|---|---|---|---|
| `test_m2_player.gd` | `M2_SUMMARY: fails=0` (2 s) | `M2_SUMMARY: fails=0` (3 s) | none |
| `probe_door_walk.gd` | `DOORWALK PASS` (38 s) | `DOORWALK PASS` (31 s) | none in verdict; +7 s wall |
| `probe_geometry_placement.gd` | `GEOM_PROBE PASS`, `checks=7 fails=0` (4 s) | `GEOM_PROBE PASS`, `checks=7 fails=0` (9 s) | none; identical counters (`records=49335 clamped=136 mirrored=2629`) |

Authored-mode door detail (the assertion that matters): `DOORWALK closed hits=2 door=1`,
`DOORWALK open angle=90.0000025044782 hits=1 door=0`,
`DOORWALK open collider=/root/Mission/SwingingDoor_146/DoorPivot/@AnimatableBody3D@40293`,
`DOORWALK PASS`. The door is found, the leaf collider is the `AnimatableBody3D` and the open
aperture is clear in authored mode.

**One apparent mode difference, investigated and dismissed.** An earlier aabb pass of M2 and
door_walk failed (`FAIL: M2.7 Smoke Bomb ... traj=false/false`, `DOORWALK FAIL no door`), but
both logs begin with `SCRIPT ERROR: Parse Error: Identifier "Progression" not declared` and
`Failed to instantiate an autoload ... game_state.gd`. Another lane was editing
`game_state.gd`/`progression.gd` in this shared worktree at 11:37–11:38 (`git status` shows
both modified; `progression.gd` has no `class_name`, so `game_state.gd`'s reference was
mid-edit). The clean re-run above passes in both modes, so the failure was a transient
shared-tree edit, **not** a collision-mode difference. I am recording it because on a live
worktree a probe can fail for reasons unrelated to the code under test, and the first
attribution was wrong.

Timing note: the door probe loads the Guildhall, so its wall time is dominated by the level
load plus 67 MB of Jolt error output (F2); 38 s vs 31 s is consistent with the commit's
"authored costs a few seconds more", but the A/B load numbers below show the opposite sign,
so I do not treat the load-cost direction as settled on this contended host.

## 7. Was any test weakened? — `AUDIT: PASS`

* Within `ff0f21d`, `game/tests` has **one** new file and zero modifications:
  `A game/tests/probe_collision_authored.gd` (the A/B script lives under `build/qa/`).
* `git diff c2a1cd8..HEAD -- game/tests/test_roof_collision.gd` is **empty** — the roof probe
  was not edited. (The wider `c2a1cd8..HEAD` range has ten test files because it also
  contains the A2/A3a/A4 lanes and an e2e fix; none of the changed lines is a collision,
  collider, shape, trimesh or `0.45` assertion — verified with a filtered diff.)
* `test_roof_collision.gd` is in **no** gate: no reference in `Makefile`, `run_tests.gd`
  (only a comment), `game/tests/e2e/**`, or `build/qa/*.sh`. So its 9 authored-mode failures
  are a real standalone-probe regression but not a gate regression, which is exactly how the
  commit records it. The probe encodes the heuristic it replaced (one mesh-wide
  `create_convex_shape()`), so the failure is expected under per-element authored hulls.
* No existing assertion was relaxed: the `col_shapes < 32000` invariant, the door-walk,
  geometry-placement, M2 and E2E assertions are untouched in this commit.

## 8. The 0.45 gate and the name tokens — `AUDIT: PASS with caveat`

**Code placement.** Both live only in `_heuristic_shape()` (`level_loader.gd:1930-1963`),
which is called from exactly two places: the whole `TAT2_COLLISION=aabb` branch, and the
authored path when `_fill_authored_shape` produced no `shapes` key (i.e. `source ==
"absent"`). `no_collision` sets `shapes = []` (present, empty) so the heuristic is never
reached; `complex_default` sets a render trimesh. So in authored mode the 0.45 gate and the
`is_nonblocking` tokens affect only the 10 no-dump `/Game/Test/` graybox paths.

**F3.1 (caveat).** The claim "the 0.45 m AABB gate ... only on the heuristic path" is not
literally true: `spline_shape_for()` (`level_loader.gd:2549-2556`) keeps its **own**
`aabb.size.length() <= 0.45` gate, and it runs in every mode because a lofted spline piece
cannot share a rigid authored hull. It only affects curb/landscape spline lofts, and the
spline branch keeps a trimesh (never a box), so this is a design carve-out, not a hidden
reintroduction of the heuristic — but the comment/commit wording overstates the isolation.

**NoCollision / QueryOnly.** `resolve()` returns `source = "no_collision"` and an empty shape
list for `ECollisionEnabled::NoCollision`; `QueryOnly` keeps its shapes and is counted in
`col_query_only`. The probe reports `no_collision=7`, `query_only=7`.

Spot checks against `mesh_collision.json`:

| path | JSON flag | placed in the 15 files | outcome |
|---|---|---|---|
| `/Game/Art/Effects/LightBeam/SM_LightBeam` | NoCollision (1 box el.) | ×134 | no shape |
| `/Game/Art/Environment/Props/Posters/SM_PosterWantedA` | NoCollision (1 box el.) | ×10 | no shape |
| `/Game/Art/Environment/Props/Posters/SM_PosterWantedD` | NoCollision (1 box el.) | ×8 | no shape |
| `/Game/Art/Environment/Nature/Bushes/Assets/SM_sf2_bush_03` | QueryOnly (1 box el.) | ×1 | shape kept |
| `/Game/Art/Environment/Props/Leisure/SM_Basketball` | QueryOnly (3 els.) | ×1 | shape kept |

All 7 QueryOnly records are placed in the 15 files — exactly the probe's `query_only=7`.

**The whole census reconciles exactly.** The payload has **31** NoCollision meshes; **12**
are placed in the 15 files; the loader's clutter gate removes the **5** cobweb paths
(`cobweb` token) but *keeps* `SM_LeavesPileC` (`sm_leaf` is not a substring of
`sm_leavespilec`), leaving **7** = LightBeam + LeavesPileC + 5 posters — exactly the probe's
`no_collision=7`. `absent=10` also reconciles: 13 `/Game/Test/` paths have no record at all,
but 3 of them (`SM_Shape_Plane/Sphere/NarrowCapsule`, 6+35+14 = **55** instances) are
filtered by the collider gate, so 10 paths and `27,222 - 24,404 = 2,818` absent instances
remain. `complex_default=70` = 69 no-record Guildhall paths (of 71 pre-gate candidates,
2 filtered) + 1 explicit `CTF_UseComplexAsSimple` path (`SM_sphere_50segments`). The
"69/94" in the source comment is the 15-file vs all-level-JSON census; both are consistent
with the data. No finding here.

**Behaviour change worth recording (authored-correct):** the 7 NoCollision paths include
`SM_LightBeam` ×134. In `aabb` mode those 134 instance-scale box colliders existed (the
beam card's local AABB is > 0.45 m); in authored mode they are gone. Same for the 5 poster
paths (34 instances). This is the authored intent and part of the 2,878-instance delta.

## 9. The async bug fix — `AUDIT: PASS`

* Sync path: `_build_draw_items()` calls `_fill_col_path_counts(items, ctx)` before
  `_prepare_merge_plan` (`level_loader.gd:5053`).
* Async path: `load_sublevels_async()` calls it directly after `_collect_draw_items` and
  before `_prepare_merge_plan` (`:6729`), because this path never calls `_build_draw_items`.
  Both are before any `_get_mesh_and_shape` that could resolve a shape.
* Reverting it: `_fill_col_path_counts` writes `_col_path_counts` (read by
  `_fill_authored_shape` as `n = maxi(_col_path_counts.get(path, 1), 1)`). Without it every
  path gets `n = 1`, so the per-mesh cap `(elements - 1) * n > 250` almost never fires and the
  over-element meshes stay per-element. My independent census over the 15 files predicts
  **+2,934 shapes** (7 paths drive it) and a demand of **34,758**, which exceeds both the
  31,400 building cap and the 32,000 total cap → at least ~2,758 dropped colliders. The
  commit's measured **2,411** is therefore the right order of magnitude and plausible; the
  exact figure cannot be reproduced without instrumenting the loader.
* The commit message's "load_sublevels_async never called `_build_draw_items`" phrasing
  reads as a pre-existing bug in `main`. It is not: `_build_draw_items` and this cost cap are
  introduced by this same commit. The omission was a bug in the W9 work-in-progress, now
  fixed. Wording only.

---

## Findings / open items

**F1 (test strength).** `probe_collision_authored.gd` coverage check is degenerate:
`(authored_hull + authored_prims) / placed_meshes` double-counts the prims subset (162 % on
this load) and the `hull + absent == placed_meshes` classification check is a tautology
because `placed_meshes` is defined as that sum. The probe therefore cannot fail on a coverage
regression and does not enforce the DoD's 95 % (its threshold is 85 %). No measured number in
the commit is wrong; the gate is simply weaker than it looks.

**F2 (new regression, should own).** Authored mode floods the engine error log: **95,293**
`ERROR: Failed to correctly scale shape at index N for body 'LevelCollision_…' … A scale of
(1.000000, 1.059800, 1.000000) is not supported by Jolt Physics for this shape/body. The
scale will instead be treated as (1.019933, 1.019933, 1.019933)` lines, **77 MB** of log for
one 15-file Guildhall load. A full `run_tests` writes **123,335** such lines / 84 MB. The
**aabb control emits 0**. The backtrace pins it to the new path (`_add_collider` ←
`_add_collider_shapes` ← `_build_one_draw_item:4573`);
the first instance is `SM_PillarBasementA_12m` (a **capsule** on an instance scaled
(1, 1.0598, 1), so a capsule is confirmed). The other 26 affected bodies are where the
authored encoding replaced a heuristic box with a shape type that Jolt will not scale
non-uniformly — the candidates on this load are 182 non-uniformly scaled sphyl placements,
1,653 convex ones and 787 trimesh `complex_default` ones; I did not isolate the type of each
body. The errors are emitted per compound rebuild, so 27 affected bodies
produce ~95 k lines (shape index up to 382). Two consequences: (a) every affected collider is
built at the Jolt-averaged **uniform** scale instead of the authored non-uniform one (the
12 m pillar's 13.19 m capsule becomes ~13.46 m in Y instead of 13.98 m — a real, if small,
fidelity gap), and (b) 77–84 MB of engine errors per load in every build, headless or
shipped. This is not mentioned in the commit and is the only behavioural regression I found.
Suggested owner action: bake the instance's non-uniform scale into the element geometry (or
into `BoxShape3D.size`/capsule params) instead of relying on `CollisionShape3D.scale`, or
split the unscaled shape per (scale) bucket; at minimum, coalesce the warning.

**F3 (wording / commit message).** Three overstatements, no functional impact:
1. "the 0.45 m AABB gate ... only on the heuristic path" — `spline_shape_for()`
   (`level_loader.gd:2549-2556`) keeps its own `aabb.size.length() <= 0.45` gate and runs in
   authored mode too (spline lofts only; it emits a trimesh, never a box).
2. "+2,878 instances are the ones the 0.45 m gate used to drop" — my independent census
   splits the 2,878 as **2,706 from the 0.45 m gate and 184 from the `is_nonblocking` token
   list** (rugs, posters, cable clusters). The commit body does mention both mechanisms; the
   delta sentence attributes them all to 0.45.
3. "load_sublevels_async never called `_build_draw_items`" reads as a pre-existing `main`
   bug; `_build_draw_items` and the cost cap are introduced by this same commit, so it was a
   W9 work-in-progress bug (now fixed), not a shipped regression.

**Verified, kept for the record:** the NoCollision/absent/complex-default census initially
looked ±1 off; the loader's token gate explains every number exactly (§8). No action.

## Open risks (not failures)

* **R1 — per-process cache vs per-load placement counts.** `_col_path_counts` is a loader
  instance variable and `_mesh_res_cache` caches the resolved `shapes` per UE path. A second
  map load in the same process reuses the first load's encoding decision (the
  `AuthoredCollision` resolve cache is keyed by instances, but the loader's mesh cache is
  not). One load per process is the current usage; a map switch in one process would keep
  the old cost-cap choice.
* **R2 — the curb partition is untested.** Lowering `MAX_CURB_SHAPES` 4,000 → 600 is not
  pinned by any test (`grep` of `game/tests/` finds no reference to the caps). The measured
  Guildhall curb peak is 27 (2 splines / 9 segments × 3 boxes — I re-derived it from the
  level JSON) and the FTUE map has **0** curb splines, so 600 is safe today; a future
  city-scale map with > 200 curb segments would silently drop curbs (600/3).

## What I could not verify

* **fps / frame time** (`fps_pose=n/a` in the probe): no GPU pose was taken here; the
  commit also records this as unverified. Nothing in my run contradicts it, but I cannot
  confirm the +2.5–3.7 s load cost's in-game effect.
* The exact **2,411** dropped colliders from reverting the async pre-pass (see §9).
* The 4-shape difference between the A/B total (30,901) and the `run_tests` total (30,905):
  each matches its own stated building count (30,873 / 30,877) and both are far under the
  caps; the 4 shapes are likely the Guildhall safe-room floor or a graph-added always-loaded
  sublevel, but I did not isolate them.
* Whether every one of the 31 NoCollision records in the payload is correctly authored in
  UE (I only verified the consumer's behaviour against the JSON).

---

## Runtime evidence

### A/B (my run)

```
# authored (build/qa/w9_collision_ab.sh)
COL_AUDIT mode=authored placed_meshes=947 placed_instances=27222 authored_hull=937 authored_prims=599 absent=10 no_collision=7 query_only=7 reduced=16 shapes=30901 bodies=243 dropped=0 load_ms=21933 fps_pose=n/a
COL_WALL total_ms=22082 (probe must stay well under 60 s)

# aabb control (re-run; the script's own attempt died on its internal flock -w 300,
# other lanes held the lock, empty log)
COL_AUDIT mode=aabb placed_meshes=835 placed_instances=24344 authored_hull=0 authored_prims=0 absent=835 no_collision=0 query_only=0 reduced=0 shapes=24465 bodies=225 dropped=0 load_ms=26944 fps_pose=n/a
```

### run_tests / traversal

```
# run_tests.gd, authored (the default), 11:33:24 -> 11:36:47 = 203 s, rc=0
PASS: Perf chunking (chunks=6018, multimeshes=3554, collision_bodies=243, shapes=30905, occluders=768, max_chunk_span=90.0m, distance-culled=1746, material_fallbacks=0, downscaled=0, prebake_pending=[])
SUMMARY: fails=0
# 0 lines matching ^FAIL; 123,335 "Failed to correctly scale shape" error lines (84 MB log)

# clean same-tree pair (11:42:05 -> 11:43:19)
test_m2_player.gd        authored  M2_SUMMARY: fails=0                     (2 s)
test_m2_player.gd        aabb      M2_SUMMARY: fails=0                     (3 s)
probe_door_walk.gd       aabb      DOORWALK PASS                           (31 s)
probe_door_walk.gd       authored  DOORWALK PASS                           (38 s)
probe_geometry_placement authored  GEOM_PROBE PASS checks=7 fails=0        (4 s)
probe_geometry_placement aabb      GEOM_PROBE PASS checks=7 fails=0        (9 s)
```

**First aabb attempt (invalid, kept so the record is honest).** An earlier aabb pass of M2
and door_walk failed (`FAIL: M2.7 Smoke Bomb ... traj=false/false`, `DOORWALK FAIL no door`),
but both logs open with `SCRIPT ERROR: Parse Error: Identifier "Progression" not declared` /
`Failed to instantiate an autoload ... game_state.gd`. Another lane was editing
`game_state.gd`/`progression.gd` in this shared worktree at 11:37–11:38. The clean re-run
above passes in both modes.
