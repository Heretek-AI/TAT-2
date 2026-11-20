# Wave 1 · w1-pg3-pg5-vfx — T1-03-E, T1-18-E, Startscreen neon (PG-5), reference-matched VFX (HL-1/HL-2/HL-7)

Date: 2026-11-19
Scope: `game/src/core/vfx_manager.gd`, `game/src/core/tat_alarm.gdshader`, plus the already-present `tat_smoke`/`tat_beam`/`tat_ward` shaders (wired, not edited). No edit was needed in `game/src/ui/main_menu.gd`, `game/src/core/level_loader.gd` or `game/src/interact/escape_gate.gd`; the reason is recorded below.

Result summary:

- **T1-03-E**: PASS — `PASS: [T1-03-E] left_corner_trim_fix code=true mat=false`
- **T1-18-E**: PASS — `PASS: [T1-18-E] Escape multipliers ghost=1.25 shadow=1.10 loud=1.00 escapes=1`
- **PG-5 Startscreen neon**: reference-matched HDR/flicker shader already in the tree (`tat_hdr_emissive.gdshader`, commit `5093dc8`); re-verified, no new edit required.
- **HL-1 VFX**: KF20 smoke is now three layered `GPUParticles3D`; KF27 beam, KF28 ward/vine, KF29 alarm are shader-backed and reference-matched.
- **`make test`**: `SUMMARY: fails=0`, `EXIT:0`.
- **Vulkan shader proof**: all four shaders compile and render under `--rendering-driver vulkan` (0 `SHADER ERROR`).

Status labels used below: `APPROX_SHADER` = procedural stand-in written from the published reference frames; `REFERENCE_MATCHED` = tuned against the KF frame. **Nothing here was decompiled from UE VM/bytecode**; the cooked Niagara/shader graphs remain unread.

---

## 1. T1-03-E — left-corner trim specular (PG-3)

The brief's "code exists yet the check fails" premise does **not reproduce** on this tree. The measured tier-1 line is a PASS:

```
PASS: [T1-03-E] left_corner_trim_fix code=true mat=false
```

Why the check now sees it:

- `game/src/ui/main_menu.gd:84` calls `_apply_startscreen_trim_specular(scene_root)` immediately after `load_sublevels(...)`.
- The path and constants are at `main_menu.gd:199-267`: `STARTSCREEN_TRIM_SPECULAR_MAX := 0.30`, `STARTSCREEN_TRIM_ROUGHNESS_MIN := 0.55`; `_clamp_trim_node_materials` sets per-surface `MeshInstance3D` overrides and, for `MultiMeshInstance3D`, duplicates the shared trim mesh before clamping (so cached meshes/materials are never mutated).
- The loader tags every built node with its UE mesh path (`level_loader.gd`, `_build_one_draw_item`: `node.set_meta("ue_mesh", mp)`), which is what the post-pass matches on.
- The suite reads the source (`e2e_tier1_features.gd:262-277`): `trim_fixed = mm_src.find("trim") >= 0 ...`. Before commit `5093dc8` the file carried no trim path, which is the actual cause recorded in `docs/reports/fidelity-mechanics-wave.md:153`; the commit added it.
- `mat=false` is expected by construction, not a second bug: `e2e_helpers.find_all_of_class` uses `is_class("MeshInstance3D")`, while the loader's trim batches are unnamed `MultiMeshInstance3D` chunk nodes (`level_loader.gd`, `_build_one_draw_item`). Only single-instance trim meshes are `MeshInstance3D`, and they do not carry a node name containing "trim". The source branch is therefore the valid signal, and the clamp implementation is present and real.

No edit was made in `main_menu.gd`: the trim path was already correct, and the task scope allows only that path.

## 2. T1-18-E — escape points on Contract 2 (PG-3)

Measured tier-1 line:

```
PASS: [T1-18-E] Escape multipliers ghost=1.25 shadow=1.10 loud=1.00 escapes=1
```

The "empty default vs group registration" disconnect is already closed, and the empty default is intentional:

- `level_loader.gd` defaults `"escape_points": [] as Array[Vector3]` in `_new_accumulator()` — correct for maps (e.g. Thieves' Den) with no authored escape.
- The `elif "Escape" in cls:` branch in `_parse_sublevel_file` fills it (`es.append(p)`).
- `mission_controller.gd`, `start_contract()` calls `_spawn_escape(ue_level_data.get("escape_points", []), anchor)`; `_spawn_escape` (`:1639-1647`) always spawns one gate and uses `ue_escapes[0]` when authored data exists.
- `game/src/interact/escape_gate.gd:39` registers the gate in group `escape_points` in `_ready()`. This one line was the actual disconnect fixed by commit `5093dc8` (the `escapes=0` report in `docs/reports/fidelity-mechanics-wave.md:166` predates it).

Data-path proof from the loader itself (headless probe, Guildhall_P only):

```
ESCAPE_COUNT 4
ESCAPE (31.327, 12.6169, -10.2132)
ESCAPE (-7.6154, 27.0633, -11.8019)
ESCAPE (19.4444, 26.0408, -18.2264)
ESCAPE (44.4686, 28.0349, -53.4204)
```

Those four are the `BP_EscapePoint_C_*` markers in `Guildhall_P.tatlevel.json` (Contract 2 base map). No edit was made in `level_loader.gd` or `escape_gate.gd`: both sides are correct; the group registration already exists.

## 3. PG-5 Startscreen neon (KF01 / S01)

Already implemented by commit `5093dc8`, re-verified here; no new edit (scope for `main_menu.gd` is the trim path only, and the neon lives in the shader/material mapping):

- `game/src/core/tat_hdr_emissive.gdshader` carries the authored linear HDR color and scale so ACES compresses it as UE does.
- KF01 cadence: slow envelope at ~2.99 rad/s (≈2.1 s) plus a fast authored-rate term; spatial phase (`NODE_POSITION_WORLD.x/z`) lets tube sections dip at different times, matching dim `00:00.10` → full `00:01.00` → left half off `00:02.05`.
- Core desaturation toward pale gold (`mix(col, pale_gold, core_mask * 0.55)`) fixes the over-saturated red-orange core residual.
- Only materials with authored `FlickerSpeed`/`FlickeringIntensity` (`MI_Neon_MacNeish`) flicker; steady `MI_Neon` keeps `flick=1`.
- `level_loader.gd`'s `plain_hdr_tint` branch (the `MI_Neon` path) still passes the unchanged `hdr_color`/`hdr_scale` values required by suite 37.

Residual, labelled not hidden: the cooked UE graph textures are unrecoverable (HL-2), so this remains `APPROX_SHADER / REFERENCE_MATCHED`, not a 1:1 shader port. Startscreen moon shaft/bounce-light matching is HL-7 (outside this lane).

## 4. HL-1 reference-matched VFX (KF20, KF27-KF29)

### KF20 — smoke bomb plume (S18)

`vfx_manager.gd:613-730`. The old single `GPUParticles3D` burst plus `InnerPuff` box stand-in is gone. `spawn_smoke_plume` now builds three layered `GPUParticles3D` under one root:

| Layer | Amount | Lifetime | Role |
|---|---|---|---|
| `PlumeCore` | 40 | 3.2 s | fast dense core thrown out at the ignition instant |
| `PlumeBillow` | 64 | 5.5 s | slower, larger puffs expanding horizontally across the steps |
| `PlumeHaze` | 26 | 6.5 s | low drift haze; `density` tweened to 0 over the 25 s ttl |

- All three use `tat_smoke.gdshader` (`APPROX_SHADER / REFERENCE_MATCHED`): view-facing body mask + procedural lump noise, so overlapping spheres read as one plume rather than hard balls.
- Per-particle growth uses a `CurveTexture` (0.28 → 0.85 → 1.55) and alpha uses a `GradientTexture1D` (0 → peak → 0).
- `spawn_smoke_cloud` (the gameplay entry used by `smoke_projectile.gd` and `mission_controller.gd`) now delegates to the same layered plume, so the throwable and mission code path share one look; the authored 5×5×4 m volume and 25 s life defaults are unchanged.
- The ignition flash remains (orange-white, 3.0 energy, 1.2 s fade).

### KF27 — foyer security beam (S24)

`spawn_foyer_security_beam` / `_add_beam_mesh`:

- Two parallel horizontal beams from the wall emitter, each a `CylinderMesh` with `tat_beam.gdshader` (`APPROX_SHADER / REFERENCE_MATCHED`): view-facing core + feathered silhouette + slow axial energy flow.
- Circular white `BeamEmitter` housing + 5 m white `EmitterGlow`.
- Cyan diamond `CeilingNode` above the far doors (KF27#3).
- Flush square `FloorPlate` between the beams (KF27#2), metallic with a low cyan emissive lift.

### KF28 — arcane barriers (S25)

- `spawn_arcane_ward`: `PlaneMesh` veil + six crystal shards use `tat_ward.gdshader` (`APPROX_SHADER / REFERENCE_MATCHED`) — procedural hash facets, rim vein, shimmer; `edge_fade=1` feathers the archway veil while shards keep full coverage.
- Purple `WardWash` omni light + 28 GPU motes retained.
- Green thorny `spawn_vine_lock` remains emissive `StandardMaterial3D` (8 strands + green glow). No vine texture is invented (HL-2); no authorized vine shader existed, so this look is unchanged.

### KF29 — crimson alarm (S26)

`spawn_crimson_alarm`:

- Foreground `SpotLight3D` (crimson, 32° cone) aimed at the stair target.
- New `AlarmCone` volume using `tat_alarm.gdshader` (`APPROX_SHADER / REFERENCE_MATCHED`): view-facing body, axial falloff from fixture to floor, 2.2 Hz strobe.
- Spot energy strobes 5.4 → 2.2 with the same cadence, then fades; cone energy fades in the last 0.8 s. Bulb keeps the authored crimson emissive.
- The shader is `APPROX_SHADER`; the UE fixture graph was not decompiled.

HL mapping: **HL-1** is the procedural VFX above (approximated). **HL-2** (graph-only textures) remains a hard limit — no texture is fabricated; shaders are procedural. **HL-7** (moon shaft/bounce light matching) is a hard limit owned by the lighting lane and was not attempted here.

---

## 5. Verification

### 5.1 Vulkan shader proof (required: headless does not compile GLSL)

A temporary probe project under `build/qa/shader_probe/` loaded the four shader sources into `ShaderMaterial`s on visible meshes and rendered them with `--rendering-driver vulkan` under Xvfb:

```
Vulkan 1.4.357 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4070 Laptop GPU
PROBE_PNG err=0 size=960x540
SHADER_PROBE_DONE shaders=4
EXIT:0
```

`grep -c 'SHADER ERROR'` → `0`. Screenshot: `build/qa/shader_probe/probe.png` (smoke grey sphere, white beam cone, purple faceted ward quad, crimson alarm cone).

Then the real VFX functions were spawned in a live tree under the same Vulkan renderer (`build/qa/probe_vfx.gd`): `spawn_smoke_plume` (three layers), `spawn_foyer_security_beam`, `spawn_arcane_ward`, `spawn_crimson_alarm`. Result: 0 `SHADER ERROR`, 0 `SCRIPT ERROR`, 0 runtime `ERROR` lines, `EXIT:0`. Screenshot: `build/qa/probe_vfx.png` — grey-white layered plume on the left, twin white beams + cyan node + floor plate, faceted purple ward on the right, crimson alarm cone. This exercises the actual `global_position`/`get_tree()` paths in the spawn functions, not just shader source loading.

The real Startscreen was then run under Vulkan for 180 frames:

```
SHADER ERROR count: 0
SCRIPT ERROR count: 0
EXIT:0
```

This exercises the actual `tat_hdr_emissive` neon materials and the startscreen scene, not just the standalone shader source.

### 5.2 `make test` (required gate)

Command: `cd /home/john/Projects/TAT-2 && make test`
Result: `SUMMARY: fails=0`, `EXIT:0`.

Tail (final run):

```
PASS: 44 triage locks (outline/reticle/lockpick/arms/vm/loco/crank/toggle/lantern/steal/stealth/visreg)
PASS: 45 stairs snap (max_angle 50 deg, snap 0.3 m, wall-block/constant-speed kept, stair slope 32.7 deg walkable, 55 deg blocked, no new mantle)
PASS: 46 Den doors leaf disabled past 70 deg (layer 0 + disabled, re-enabled on close) & window wall split gap=0.95m + sill + lintel (2m marker gate kept)
SUMMARY: fails=0
WARNING: 28 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
ERROR: 7 resources still in use at exit (run with `--verbose` for details).
   at: clear (core/io/resource.cpp:822)
ERROR: 6 RID allocations of type 'N17RendererSceneCull8InstanceE' were leaked at exit.
EXIT:0
```

`grep -c 'SCRIPT ERROR'` → `0`. Exit-time ObjectDB/resource/RID warnings are pre-existing teardown noise (the Wave 0 baseline records the same class of warning) and do not fail the gate.

### 5.3 Tier-1 E2E lines (target IDs)

Run: `flatpak run org.godotengine.Godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=1`

```
PASS: [T1-03-E] left_corner_trim_fix code=true mat=false
PASS: [T1-18-E] Escape multipliers ghost=1.25 shadow=1.10 loud=1.00 escapes=1
```

Note: this first tier-1 rerun reported `fails=1 passed=109 total=110`; the single failure was `T1-08-A` (1P arms PBR) and it is outside this lane: `thief_character.gd` was rewritten by the concurrent w1-pg2-pg7 lane at 17:15:36 while this run was in flight. Both target IDs passed. A second rerun after the edit is recorded in §5.4.

### 5.4 Tier-1 reruns (two consecutive)

Both reruns after the VFX change produced `SUMMARY: fails=1 passed=109 total=110`, and both times the only failure was `T1-08-A` (1P arms PBR):

```
FAIL: [T1-08-A] 1P arms SK_ThiefNisha__BodyUpper PBR bound (false)
```

The concurrent w1-pg2-pg7 lane's own tier-1 log (`/tmp/w1-pg2-tier1-final.log`) shows the same `T1-08-A` failure at the same time. Its `thief_character.gd` edit landed at 17:15:36 while the first rerun was in flight; this lane does not touch that file or the arm/viewmodel material path (`vfx_manager.gd` is not loaded by T1-08-A). Both target IDs passed in every run:

```
PASS: [T1-03-E] left_corner_trim_fix code=true mat=false
PASS: [T1-18-E] Escape multipliers ghost=1.25 shadow=1.10 loud=1.00 escapes=1
```

---

## 6. Files changed in this pass (with reasons)

1. **`game/src/core/vfx_manager.gd`** (modified)
   - `spawn_smoke_cloud` delegates to the layered plume; `spawn_smoke_plume` rebuilt as `PlumeCore`/`PlumeBillow`/`PlumeHaze` layered `GPUParticles3D` (KF20) with growth/alpha curves and ttl haze fade.
   - Added shader preloads (`tat_smoke`, `tat_beam`, `tat_ward`, `tat_alarm`) and replaced the beam/ward StandardMaterials with `ShaderMaterial`s.
   - Added the KF27 `FloorPlate`, KF29 `AlarmCone` + strobe tween, and the shared smoke-layer helpers.

2. **`game/src/core/tat_alarm.gdshader`** (new)
   - `APPROX_SHADER / REFERENCE_MATCHED` crimson alarm volume for KF29 (strobe + axial falloff); no UE graph decompiled.

Consumed but **not edited** in this pass (present in the working tree):

3. `game/src/core/tat_smoke.gdshader` — KF20 smoke material, now wired by `vfx_manager.gd`.
4. `game/src/core/tat_beam.gdshader` — KF27 beam material, now wired.
5. `game/src/core/tat_ward.gdshader` — KF28 ward material, now wired.

Deliberately **not changed**:

6. `game/src/ui/main_menu.gd` — trim path already complete (`:84`, `:199-267`); T1-03-E passes.
7. `game/src/core/level_loader.gd` — escape default/fill site already correct (`_new_accumulator()` default, `_parse_sublevel_file` `Escape` branch); only a read probe was used.
8. `game/src/interact/escape_gate.gd` — `add_to_group("escape_points")` already present (`:39`); T1-18-E passes.

Working-tree note: `git status` also lists concurrent wave edits outside this lane (`project.godot`, `guard_ai.gd`, `audio_manager.gd`, `level_loader.gd` far-batching, `mobile_profile.gd`, `smoke_projectile.gd`, `thief_character.gd`, `hud.gd`, `ledger_ui.gd`, `loading_screen.gd`, `main_menu.gd`, `settings_ui.gd`, `mission_prep_ui.gd`) plus the four VFX shaders. Only the two files above were written by this pass.

---

## 7. Residuals / hard limits

- **HL-2**: graph-only textures remain unrecoverable. The VFX use procedural shading only; no texture was invented.
- **HL-7**: moon shaft / bounce-light matching is a hard limit owned by the lighting lane; not attempted here.
- **KF28 vine lock**: left as the existing emissive strand material; no authorized vine shader existed and no texture was fabricated.
- **T1-08-A**: unrelated concurrent-lane failure in both tier-1 reruns (see §5.3-5.4); not caused by this change (`vfx_manager.gd` is not loaded by that check).
- Exit-time ObjectDB/RID leak warnings in `make test` are pre-existing teardown noise (same as Wave 0 baseline) and do not fail the gate.
