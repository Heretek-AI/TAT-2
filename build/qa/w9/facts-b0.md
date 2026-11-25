# W9-P2 B0 — collision close-out fact sheet

Read-only investigation (no edits, no Godot). Key facts and `file:line`; the
implementation and proof are in `b0-impl.md` and p2-report §B0.

## Roof probe

- `game/tests/test_roof_collision.gd` executed **51 assertions: 42 PASS / 9
  FAIL** in `authored` mode, 51/0 in `aabb`. It reads only
  `info.get("shape")` (the loader's `shapes[0]` compatibility field) and calls
  `_get_mesh_and_shape` without `_col_path_counts`, so `n=1` and the per-path
  cost cap never applies.
- Not in any gate: no reference in `Makefile`, `run_tests.gd`, `game/tests/e2e`,
  `build/qa/*.sh` or `tools`.
- The 9 failures (first-element artefacts): `BayWindowA_6x4` reduced trimesh
  (27 elements > 16); box-policy multi-element sets and one convex
  (`ChimneyCityLrgA_Top`); End shell first-hull top 2.945–8.430 vs render
  4.316/8.474; End first-hull eave 2.68 m; Old Manor 4 trimeshes not 6
  (`Combo_02` 10 hulls, `Fence` 1 box); shallow 61.1° vs union 45.4°; shallow
  eave 2.51 m vs union 3.55 m; steep 76.4° vs union 67.0°.
- Union truth (`mesh_collision.json`, loader conversion `P(v)=(x,z,y)·0.01`):
  `SM_RoofUrban_Ext_Mid_4x4` 3 hulls, AABB `(-4.142,-0.058,-3.129)->(0.199,
  4.179,1.043)`, pitch 45.4°, eave 3.51 m, top span 0.019, 67 instances,
  3 shapes/inst; `SM_RoofUrbanB_Ext_Mid_6x8` 4 hulls, AABB
  `(-6.070,-0.086,-2.464)->(0.074,8.281,1.085)`, pitch 67.0°, eave 7.06,
  top span 0.144, 47 inst, 4 shapes/inst; End shells 4 hulls each, union top
  within 0.082 m, eave 3.50–7.63.
- Reduction: `SM_RoofUrban_Ext_Corner_4x4x4` 13 convex × 38 inst ⇒ 1 coalesced
  trimesh (`(13−1)·38=456 > 250`); `BayWindowA_6x4` 27 ⇒ reduced;
  `MidWindowA_4x4` 6 × 45 = 225 ⇒ per-element; OldManor `Combo_01` 419 ⇒
  reduced, `Combo_02` 10 hulls, `Fence` 1 box, `Combo_Glass` complex-default.

## Harness and attribution

- `build/qa/w9_perf.gd` has no load timer, no `TAT2_COLLISION` print, and
  includes the presentation-bound prep scene; `build/qa/w9_perf_ab.gd/.sh`
  fixes that (mission only, 3 poses, `W9_LOAD`, `TAT_LOAD_TIMING=1`, one
  process per mode).
- `LoadTiming` is printed only by `load_sublevels_async` (`level_loader.gd:6798`
  in the current tree; 6775 at b13260b): parse 6727, lights 6763, terrain
  6778, draw with mesh/build/glb/mat/shape. The sync path prints only parse
  (6664).
  `_prof_shape_ms` is never incremented (always 0).
- The authored payload loads in `_get_mesh_and_shape` → `_fill_authored_shape`
  (`level_loader.gd:2000`, call site 1910); the aabb control loads the same payload in
  `_finalize` after `draw_ms` (stats reporting), so the phase counters are not
  mode-symmetric.
- Per-instance `CollisionShape3D` emission is inside `draw_ms` after
  `perf_build_ms` closes (`level_loader.gd:4225-4245`, close at 4593-4596); not
  separable without editing the P1-owned loader.
- Gates that must not move: `run_tests` `col_shapes < 32000`
  (`run_tests.gd:501`), CPD `collision_shapes == 0`, Den split +4, E2E
  `MAX_TOTAL_SHAPES == 32000`/`MAX_SHAPES_PER_BODY == 384`, `dropped==0` in
  the A/B/FTUE probes.

## Current evidence (at the time of the investigation)

- P1 report: authored 23,544 ms / aabb 19,891 ms / +3,653 ms, shapes 30,901 vs
  24,465, dropped 0, coverage 0.989.
- A1 audit re-run: authored 21,933 / aabb 26,944 / **−5,011 ms**, same counts.
- Both on a contended host; no FPS pose (`fps_pose=n/a`).
- The W9-P2 A/B (4 runs, ABBA) is in p2-report §B0-2: load mean −1,250 ms with
  3,910 ms peak-to-peak drift, FPS p50 +0.9/+1.3/+3.8 %, p95 +1.25/+11.7/+14.1 %.
