# W6M — movement truth (blocker-safe step-up, traversal coverage, capsule contract)

Branch worktree `/tmp/opencode/tat2-w6m-move`, cut from `f803c3b`
(W5 integration docs). Movement-only wave: `game/src/player/thief_character.gd`,
`game/tests/test_stair_walk.gd`, new `game/tests/test_traversal_routes.gd`,
suite 45 in `game/tests/run_tests.gd`. `level_loader.gd`, weather, UI, save and
guard code are untouched — the roof `EndA`/`EndB` classifier is W6L and every
roof-dependent assertion stays deferred here.

Commit: `fix(player): blocker-safe step-up, traversal coverage and capsule contract`.

## What changed

| # | Defect | Fix |
|---|---|---|
| 1 | A designer `blocking_volume` inside `MaxStepHeight` was a legal tread: the 0.40 m blocker's top was found by the step probe and stepped onto. | `_try_step_up()` rejects a `blocking_volume` collider on the blocked sweep **and** on the floor probe, via the existing `_is_blocking_volume_hit()` contract plus a collider-only `_is_blocking_volume_collider()` form. Headroom is not exempt (a blocker at head height is solid). |
| 2 | Headroom was tested at the **origin** (a `MaxStepHeight + skin` lift in place), which both rejected legal landings under a high soffit and accepted a soffit only the landing would hit. | Headroom is a vertical clearance ray **at the landing**: feet at the destination floor, up the built body height (1.82 m standing / 1.0 m crouched). |
| 3 | A long flight stalled mid-climb: the rounded capsule bottom catches the next tread's **top** (near-up normal), the "walkable normal" ramp guard read it as a slope and refused the lift. Measured stalls: Old Manor tower 2.39 m, 3x850 POI 5.74 m. | The walkable-normal guard only applies when the body is **not** actually walled (`is_on_wall()`). Ramps stay untouched; the stair nosing catch now steps. |
| 4 | Walking down a flight free-fell: Godot's floor snap runs **before** `move_and_slide`, so the rounded nosing contact drops `is_on_floor()` and the body falls until it clears the tread. | Added `_try_step_down()` (UE `FindFloor` shape): post-move re-seat onto the tread under the axis within `FLOOR_SNAP_LENGTH`, gated to a just-started fall (0 s..0.2 s grounded grace, `-0.8 m/s` max downward speed) and to a **free destination capsule pose** (shape query) so the rear of the capsule can never be shoved into the step behind. |
| 5 | `body_height_m()` reported the port's 1.78 m while the built capsule was 1.82 m, so device detectors/beams tested a body 4 cm shorter than the collision. | `BODY_HEIGHT_STANDING` = 1.82 m (the built capsule). `device_geometry.gd`'s fallback constant and the W3 beam **mock** fixture remain 1.78 m (see residual). |
| 6 | 0.50 m ledges could not mantle at all: the wall probes sampled 0.5/1.1/1.7 m, i.e. at or above a 0.50 m top. | Added a 0.3 m wall sample so the jump-gated `(0.45, 0.50]` band mantles (`mantle_050`). |

## Measured gates (serial, one Godot at a time, `XDG_DATA_HOME=/tmp/opencode/w6m-data`)

| Gate | Result |
|---|---|
| compile (`tools/check_scripts_compile.gd`) | **102 checked, 0 broken** (101 + `test_traversal_routes.gd`) |
| `tests/run_tests.gd` (full) | **`SUMMARY: fails=0`**, 261 PASS; suite 45 passes with the 1.82 m fixtures and the blocker control |
| `tests/test_stair_walk.gd` | **`W6M_STAIR_SUMMARY: fails=0`** (7 routes + descent + 2 prompt/LOS negatives + 35° ramp) |
| `tests/test_traversal_routes.gd` (new) | **`W6M_TRAVERSAL_SUMMARY: fails=0`** |
| `tests/test_m2_player.gd` | **`M2_SUMMARY: fails=0`** |
| E2E | not run in this worktree (out of scope for the wave; parent runs the 264/264 gate after cherry-pick) |

## Shipped-layout routes (real loader trimesh, shipped instance basis/scale)

The fixture reproduces `level_loader._get_mesh_and_shape()` + `_add_collider()`
(orthonormal basis, non-uniform `cs.scale`) and walks the real collider with the
real `move_forward` action through `_physics_process`.

| Route (level, world pos) | Pose | Frames | Measured | Notes |
|---|---|---|---|---|
| civic `SM_Stairs_Civic_3x150cm`, Guildhall POI 24.95/26.47/-27.10 | identity | 180 | **1.54 m** (authored 1.56 m / 1.99 m run) | target at frame 54, camera settle 1 frame, prompt resolves on the landing |
| industrial `SM_Stairs_Industrial_3x150cm`, POI 3rdFloor 12.40/64.00/-46.35 | identity, y-scale 1.0454 | 180 | **1.55 m** (1.57 m) | target 37 frames |
| city `SM_StairsCity6x2m` | identity | 180 | **1.97 m** (1.99 m) | target 48 frames |
| POI `SM_Stairs_Civic_3x850cm`, Guildhall POI 36.65/36.51/-37.50 | identity, rising −Z | 260 | **8.47 m** (authored 8.49 m / 9.85 m run) | target 233 frames, 84 step commits, camera settle 8 frames (0.13 s) |
| civic 3x150, PeripheryA 47.58/12.48/-4.18 | yaw `[0,0,1;0,1,0;-1,0,0]`, **rising −X** | 100 | **descent 1.58 m**, ends grounded | see descent gap below |
| industrial 3x150, PeripheryA 54.14/20.07/69.42 | yaw `[-1,0,0;0,1,0;0,0,-1]`, **rising +Z** | 180 | **1.55 m** | target 37 frames |
| Old Manor `SM_OldManor_Tower_Stairs_4x850`, OldManor_Geo −53.00/33.23/16.50 | identity, scale `[1, 1.02, 0.9503]` | 280 | **8.78 m** of walkable treads | mesh AABB is 10.29 m; the 9–10 m faces are the stair-side posts/parapets, not treads. Target 255 frames, ends grounded |

Every ascent asserts: ascent ≥ per-route minimum, ≤ 2 zero-progress frames, no
auto-mantle, < 0.15 m lateral drift, camera lag ≤ 0.25 m, **camera settle
< 0.02 m within ≤ 24 frames (0.4 s)**, and `is_on_floor` at the end. Every
descent asserts it reaches the bottom and ends grounded.

The civic ascent also spawns a real `Area3D` interactable on the landing with
the Den-style authored `floor + UP*1.2` point; `get_nearest_interactable()` and
`get_look_interact_prompt()` resolve there after the climb. The W5A wardrobe
positive/negative controls stay in the file unchanged (`0.48 m`-deep cabinet
resolves; a real 0.63 m-thick wall still blocks). A per-prop standoff was **not**
needed: no 0.50 m wall was ignored in any fixture, so the global 0.6 m standoff
is unchanged.

## Controller fixtures (`test_traversal_routes.gd`)

| Fixture | Measured |
|---|---|
| step band 0.44 / 0.45 m | commits **0.440 / 0.450 m** frame-local rise |
| step band 0.46 / 0.50 m | **no** step, and 45 held frames climb **0.001 m** |
| 0.50 m + `jump` press | auto-mantle **true**, clip `mantle_050` |
| 0.40 m visible ledge control | steps **0.40 m** |
| 0.40 m `blocking_volume` | step **0.000 m**, walked **0.001 m**, jump-mantle **false** |
| 2.25 m soffit over a 0.45 m landing | refused (1.80 m clearance < 1.82 m) |
| 2.35 m soffit over a 0.45 m landing | commits 0.450 m (1.90 m clearance ≥ 1.82 m) |
| 45° / 55° / 59° slopes | ascend **1.90 / 1.90 / 1.87 m**, step-up rise 0.000 m, no mantle |
| 61° / 70° slopes | **−0.18 / −0.18 m** (slide back), step-up rise 0.000 m, no mantle |
| 0.45 m ledge walk-off | **exactly 1** airborne interval, 16 frames, lands y=0.001, end grounded |
| deep-tread descent (4 × 0.28 m risers, 0.60 m treads) | descends **1.40 m**, 5 airborne intervals, max **11 frames**, ends grounded |
| capsule contract | built **1.82 m** capsule, r 0.32, centre 0.91; `body_height_m()` **1.82**; `BODY_HEIGHT_STANDING` **1.82** |

## Residuals / remaining dependencies

1. **Roof hull (W6L) — deferred.** This wave adds no `EndA`/`EndB` classifier and
   no roof-hull assertions. `test_roof_collision.gd` is untouched. Any route
   assertion that needs the fixed roof is deferred to the loader worker.
2. **Descent is re-seated, not glued.** On the shipped 0.33 m treads with the
   authored 0.32 m capsule, the descent still reports short airborne intervals
   (the civic descent: 33 airborne frames over 100 frames, ending grounded). The
   step-down shape re-seats whenever the destination capsule pose is free; on a
   tread only ~1.07× the capsule radius wide there are frames where it is not, so
   the body takes a one-riser fall first. Recorded in `docs/FIDELITY_GAPS.md`.
3. **1.78 m detector mocks.** `device_geometry.gd`'s fallback constant and the W3
   beam mock in suite 70.3 still use 1.78 m. Real players now report 1.82 m; the
   mock fixtures were left untouched to keep the device suites' authored-fixture
   intent. Follow-up owner: devices.
4. **Rotated-parent input.** The controller evaluates `move_forward` in
   `transform.basis` (parent-local) but feeds `velocity` to `move_and_slide` in
   global space. Production keeps the player under an unrotated root, so the
   shipped game is unaffected; the stair fixture compensates by parenting the
   walker under the identity rig and yawing it. Worth a defensive global-basis
   change if the player is ever parented under a rotated node.
5. **E2E not run** in the worker worktree; the parent re-runs the full gate set
   after cherry-picking onto `main`.
