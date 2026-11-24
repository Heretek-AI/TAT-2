# W5B loader/render: roof collision, masked opacity, mountain + poster materials

Wave: W5B (loader/render truth). Worktree `/tmp/opencode/tat2-w5b-loader`, base
`950f7ca` (`docs: record the Spider chain, guard fixes and deferred full gates`).
Commit: `fix(loader): roof collision, masked opacity, mountain and poster materials`.

Scope: `game/src/core/level_loader.gd` plus two new standalone headless tests.
No change to `thief_character.gd`, `weather_*`, `mission_controller.gd`,
`audio_manager.gd`, `hud.gd`, to global exposure/glow, or to generated data.

## 1. Roof collision: AABB box -> authored-pitch convex hull

**Defect (measured).** `Guildhall_PeripheryA` packs **733 `/roofs/` instances in
46 unique meshes**. Every one of them took a `BoxShape3D`, because no roof
module exceeds the loader's 12 m "props get a box" ceiling (largest AABB
diagonal 11.24 m). The audit's "637" did not reproduce as an instance count on
the current generated data: the measured number of roof-path instances that
received a `BoxShape3D` is **733 / 733**. A roof module's AABB is not its shape:

| mesh | footprint (x/z) | rise (y) | chord pitch | box top above the eave band |
|---|---|---|---|---|
| `SM_RoofUrban_Ext_Mid_4x4` | 4.07 x 4.18 m | 4.22 m | 45.2 deg | **3.62 m** |
| `SM_RoofUrbanB_Ext_Mid_6x8` | 6.01 x 3.43 m | 8.30 m | 67.6 deg | **7.69 m** |

So the box presented a flat, invisible walking surface 3.6-7.7 m above the eave
and the authored slope was never walkable - on a game whose core verb is
rooftop traversal. The audit's 44 deg figure is this family (45.2 deg measured
from the GLB); the pitch of every module is authored and intact.

**Fix.** `roof_collision_kind()` / `ROOF_BOX_TOKENS`: pitched `/roofs/` meshes
inside the box ceiling now use `Mesh.create_convex_shape()` (mesh-local points,
zero centre offset; one hull per unique mesh, cached in `_mesh_res_cache`).
Flat pieces keep the exact box by name: `trim`, `side`, `end`, `floor` (roof
decks), and the roof props `chimney`, `vent`, `pipe`, `gutter`, `rail`,
`watertower`/`tank`. Side/fascia/trim panels are 0.35 m thick boxes - a hull
would only cost memory and would not change the surface.

PeripheryA census after the change (real build: a throwaway probe loaded the
sublevel through `load_sublevels_async()` and walked the scene tree, grouping
`CollisionShape3D` by `ue_mesh` meta and shape class; the probe is not
committed, its numbers are reproduced by `test_roof_collision.gd`'s census and
policy checks):

| bucket | before | after |
|---|---|---|
| roof `BoxShape3D` | 733 | **399** (flat/prop pieces by name) |
| roof `ConvexPolygonShape3D` | 0 | **334** (13 unique meshes) |
| roof `ConcavePolygonShape3D` | 0 | 0 |
| all shapes in the level | 10,713 | 10,713 |

## 2. Roof occluders: 398 candidates -> 0 boxes

A hip roof fills a small fraction of its AABB: measured from the GLB triangles,
`SM_RoofUrban_Ext_Mid_4x4` covers **12.9 %** of its box, so a
`BoxOccluder3D` culls the city behind a solid volume that does not exist.
`roof` is removed from `OCCLUDER_INCLUDE_TOKENS` and added to
`OCCLUDER_EXCLUDE_TOKENS` (the flat `GB_RoofFloor_*` decks are horizontal slabs
a camera never looks past). Walls, floors and ceilings keep their boxes.

Measured on a PeripheryA build, counting emitted `BoxOccluder3D` sizes that
match a `/roofs/` mesh's inset AABB (the occluder count itself is capped at 768
in both runs, so the delta is measured by identity, not by total):

| | before | after |
|---|---|---|
| roof occluder **candidates** (old name+dims policy, no cap) | **398** | not applicable |
| roof `BoxOccluder3D` actually emitted (768 cap) | **111** | **0** |
| total occluders | 768 (cap) | 768 (cap) |
| collision shapes / bodies / meshes | 10,713 / 107 / 12,252 | 10,713 / 107 / 12,252 |

The 398 candidate figure reproduces the audit exactly (67 `Mid_4x4`, 52
`EndA_2x4x4`, 47 `RoofUrbanB_Mid_6x8`, 38 `Corner_4x4x4`, ... 56 chimney and 23
`GB_RoofFloor_6x6` instances). In a PeripheryA-only build the global 768 cap
only let 111 of them through; a full Guildhall load interleaves them with the
wall occluders, which is why the audit counted the candidate set.

## 3. Masked materials bind their authored opacity map

`_apply_ue_render_flags()` only ever set `TRANSPARENCY_ALPHA_SCISSOR`, and Godot
reads that mask from the **albedo texture's alpha**. `MI_HorizonA` - the
558 x 140 m SkyboxGeo horizon card, `BLEND_Masked`, `BaseColorTint` black - has
its skyline in `T_HorizonA_BCO.png` (alpha 0 = sky: 21.8 % of texels below 0.5)
but bound `T_TrimMetalB_DA`, whose alpha is 255 everywhere (measured 0.000
below 0.5). The card therefore rendered as one solid black wall.

`get_material_for_ue()` now composes the authored mask into the albedo alpha for
masked materials that carry `texs.opacity`:

* `*_BCO` (BaseColor+Opacity, alpha = mask) is used verbatim - RGB is already
  the authored base colour, so no resample and no per-pixel copy;
* grayscale `*_O` masks (mask in R, alpha 255 - `T_GooBubble01`,
  `T_Hauntstable_*_O`) are copied into the albedo alpha at the mask's own
  resolution;
* the channel convention is detected with a 64x64 probe (`_mask_uses_alpha`),
  not by scanning millions of texels.

Scope is the authored masked blend only (`blend_mode` contains `Masked`): 7
materials in `materials.json`. Measured material-build cost: `MI_Hauntstable_Top`
69 ms (1024^2 grayscale compose), `MI_MagicSlime_Bubble` 52 ms, `MI_HorizonA`
4 ms (BCO used verbatim), all cached per material.

Visual consequence to review (authored, not a regression): the Den Hauntstable
bust and the MagicSlime bubbles now take their authored `_O` cut-outs instead of
their albedo alpha.

## 4. Skybox mountains: WorldGrid -> MI_Mountain17

`SkyboxGeo` binds the engine placeholder `WorldGridMaterial` on
`SM_Mountain02/07/16/18_Grass` (4 of the skybox mountain cards), so the horizon
rendered as the grey checkerboard; only `SM_Mountain17_Grass` had the authored
`MI_Mountain17`. `_fix_worldgrid_mountain_surfaces()` substitutes it, scoped by
name: the path must contain `/skybox/mountains/` **and** the stem must start
with `sm_mountain`.

Verified: `SM_Mountain02_Grass` now carries `T_Mountain_16_Grass_BaseColor.png`
(MI_Mountain17) on every surface; the negative controls keep the placeholder -
`SM_Sphere_100cm` (intentional WorldGrid sphere) and
`SM_RoofUrbanB_Ext_BayWindowA_6x8` (a roof surface with a WorldGrid panel) each
still report one WorldGrid surface.

## 5. DiffuseMaskTint is gated on `DiffuseColorMask?`

`M_Env*` masters multiply the diffuse by `DiffuseMaskTint` only when the
`DiffuseColorMask?` switch is on. 43 generated materials carry the inherited
vector (`MI_PosterWanted`: `[0.5331,0.5645,0.6979]`) and **0** have the switch
on. Applying the vector unconditionally turns the sepia `T_PosterWanted_DA`
albedo (mean RGB 112,100,77) into a cold cyan-grey (mean ~59,56,54) - the
"cyan WANTED poster" symptom.

`_apply_diffuse_mask_tint()` reads the switch first, then multiplies the
authored **linear** vector through `linear_to_srgb()` exactly once (Godot treats
`albedo_color` as sRGB). Measured at this HEAD the tint was not applied at all,
so `MI_PosterWanted.albedo_color` is and stays white; the change is the guard
that makes the switch authoritative and the conversion explicit.

## 6. Deferred: exact-material white-clip caps

The optional Den white-clip work (pane / brass horn / parchment / lantern glass)
is **deferred, not done**. It needs Den captures with per-ROI clipping counts
before/after and exact-material scoping on the emission path; guessing caps
without those captures would raise clip elsewhere. No global exposure or glow
was touched in this wave.

## Tests

Two new standalone headless tests (SceneTree, no map mission, no E2E):

```bash
XDG_DATA_HOME=/tmp/opencode/w5b-data tools/godot --headless --path game \
  --script res://tests/test_roof_collision.gd
XDG_DATA_HOME=/tmp/opencode/w5b-data tools/godot --headless --path game \
  --script res://tests/test_w5b_materials.gd
```

* `test_roof_collision.gd` - census (733/46, 334 convex in 13, 399 box in 33);
  every convex-policy mesh returns `ConvexPolygonShape3D` with a zero offset and
  a hull of more than a box's 8 points (min 25); no pitched roof mesh returns a
  `BoxShape3D`; flat pieces keep centred boxes; 0 roof occluders across all 46
  meshes while the 4x6 wall stays an occluder; a 44 deg and a 62 deg synthetic
  hip reproduce `half_span * tan(pitch)` (apex 1.9314 / 3.7615 m, ratio 1.9475 =
  tan(62)/tan(44)) with no eave plateau; the real 45.2 deg and 67.6 deg modules
  keep their pitch and their hull eave band sits 3.62 m / 7.69 m below the AABB
  top the box used.
* `test_w5b_materials.gd` - masked opacity: the masked material with
  `texs.opacity` binds the authored mask (21.8 % cut-out) and not albedo alpha
  (control: the old metal albedo has 0.000 cut-out), the grayscale `_O` path
  composes (34.0 % cut-out), a masked material without an opacity map keeps its
  albedo alpha; mountain substitution plus exact-name negative controls; poster
  material dump (albedo/tint/clip/two-sided) and the switch gate (off: untouched;
  on: `linear_to_srgb` 0.7568/0.7763/0.8532, not the raw 0.5331).

Both tests print `*_SUMMARY: fails=0`. They are standalone SceneTree runners
(like `test_beam_geometry.gd`); registering them as suites 89/90 in
`run_tests.gd` would require the `RefCounted` + `run(host)` refactor used by
suites 87/88 and is left as a follow-on.

## Gates run for this wave

| gate | result |
|---|---|
| `tools/check_scripts_compile.gd` | **98 checked, 0 broken** (96 at HEAD + the 2 new tests) |
| `test_roof_collision.gd` | **fails=0** (27 PASS) |
| `test_w5b_materials.gd` | **fails=0** (27 PASS) |
| `test_m2_player.gd` | **M2_SUMMARY: fails=0** |
| `make audit` | **FAILED, not caused by this wave**: `parse_tables.py` / `parse_gameplay.py` / `parse_weather.py` output differ from the tracked baseline and `vgmstream` is missing on this host. The generated data under `game/data/generated` is the shared main-checkout tree (symlinked, never touched here); no producer or data file was edited. Re-run on the main checkout after the other waves' `make normalize`. |
| full `make test` / E2E / Vulkan captures | **not run** - wave rule is focused tests only |

## Risks

1. **Convex vs concave roof shells.** A convex hull spans concavities: on a
   curved shingle slope the collider can sit a few cm above the visual valley
   (never below, so the player never sinks through). A trimesh would be exact
   but costs 13 ~13k-vertex shapes instead of 13 hulls; hulls were chosen for
   cost and tunnelling safety. Revisit if rooftop landings look floaty.
2. **Roof walkability.** Removing 4-8 m AABB plateaus means routes that used to
   "work" by standing in the air above a roof now land on the real slope.
   Slopes above the character's floor angle block movement, which is correct
   behaviour but changes rooftop traversal feel; verify in `make run`.
3. **Occluder budget.** 768 - roof occluder slots now go to walls/floors in the
   same capped build, so occlusion coverage shifts rather than shrinks; F9
   wall-flicker guard is untouched. Watch for new pops in PeripheryA captures.
4. **Hauntstable / slime cut-outs** now use their authored `_O` masks (see §3);
   if the Den bust reads too skeletal, the mask is authored and the fix belongs
   in the mask scope, not in the loader switch.
5. **HorizonA albedo** now comes from `T_HorizonA_BCO` (authored BaseColor +
   Opacity) instead of the mis-bound `T_TrimMetalB_DA`; the tint is black, so
   the visible result is the silhouette only.
6. **Not re-measured**: full `run_tests.gd`, E2E and Vulkan captures. No
   exposure/glow/tonemap change was made, so no image-stat baseline should
   move, but nothing here was captured on the GPU.
