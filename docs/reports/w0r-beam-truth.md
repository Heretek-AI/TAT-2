# W0R — security beam geometry truth (authored length axis, clamp exemption, runtime direction)

Date: 2026-11-24 · Tree: worktree `tat2-ns-render` · Headless only (no GPU capture).

Scope: `SM_LightBeam` security detectors, Guildhall. Files changed:

| File | Change |
|---|---|
| `game/src/core/level_loader.gd` | exact-path beam transform (`beam_card_transform`), 200 m beam ceiling, one `BEAM_FIX` line, per-card `MeshInstance3D` + `lightbeam_cards` group |
| `game/src/devices/security_beam.gd` | runtime axis moved to authored actor-local **+Z**, capsule/stand-in aligned, powered visibility, authored-card adoption (one visual) |
| `game/src/devices/device_layer.gd` | pairs each beam detector with its authored card, releases it on respawn |
| `game/tests/test_beam_geometry.gd` | new standalone headless truth test (18 checks) |
| `docs/reports/w0r-beam-truth.md` | this report |

## Evidence: the record is authored, the loader was not

* `Guildhall_Gameplay.tatlevel.json`: **134** meshes with path `/Game/Art/Effects/LightBeam/SM_LightBeam`; `devices_runtime.json` Guildhall: **134** `light_beam` records. All 134 pair 1:1 by authored position (0 unmatched).
* UE source (`extracted/json/Art/Effects/LightBeam/SM_LightBeam.json`): StaticMesh bounds `X -0.1..10.1 cm` (**0.102 m long axis = local X**), `Y/Z ±50.04 cm` (1 m cross width). Blueprint `BP_Detector_LightBeam`: `LightBeam_Root.RelativeScale3D.X = 42.5468` for `C_0`, i.e. the length scale is authored on **X**.
* `.tatlevel` record: `scale = [1, 1, s]` where `s = 24.5 … 195.5291`, and `basis col0` is the **actor-local Z** direction. `0.102 · s` equals `BeamLength_cm / 100` for **134/134** (max error **0.041 %**; the one record without `BeamLength` — `C_72` — lands on the 10 m family default).
* The old generic path applied `s` to basis **col2** (a 1 m width axis), so the card rendered as a `s`-metre ribbon 90° off the beam, and `_dict_to_transform`'s per-axis 40 m clamp then clipped **129/134** cards. `col0` (the 0.102 m axis) was never scaled.

Before/after (world length is the scaled card axis; direction is the world vector it runs along):

| Actor | Authored `BeamLength` | Record scale | Before: axis / run / clamped | After: axis / length | After dir error |
|---|---|---|---|---|---|
| `…LightBeam_C_0` | 4.3415 m | 42.5468 | col2 `(1,0,0)`, 40.00 m, clamped | col0 `(0,0,-1)`, **4.3398 m** | 0.020° |
| `…LightBeam_C_1` | 7.7482 m | 75.9327 | col2 `(-1,0,0)`, 40.00 m, clamped | col0 `(0,0,1)`, **7.7451 m** | 0.020° |
| `…LightBeam_C_134` | 19.9519 m | 195.5291 | col2 `(0.819,0,0.574)`, 40.00 m, clamped | col0 `(0.574,0,-0.819)`, **19.9440 m** | 0.020° |

Old ribbon run = `min(s, 40)` (s = 42.5 … 195.5 for 129 of 134), i.e. 5.2× to 10.0× the authored span, pointing along the card's width axis. After the fix the length axis is the authored col0 and no scale is clipped (max 195.5291 < 200).

## Duplicate visual: both layers drew a beam — now exactly one

Finding: the loader spawned the 134 additive `SM_LightBeam` cards (batched into ~11 MultiMeshes) **and** `security_beam.gd` built its own `CylinderMesh` + `tat_beam.gdshader` stand-in per detector, so every detector had two beams. Power state was also wrong: the stand-in's visibility followed only `awake`, and the batched card could not be hidden per instance.

Resolution (no `mission_controller.gd` edit):

1. The loader now spawns each authored card as its own `MeshInstance3D` (group `lightbeam_cards`, meta `beam_card=true`). They are additive and shadowless.
2. `device_layer._adopt_beam_cards()` pairs a card to its detector by authored position (`<= 0.02 m`; positions are identical in both records) and calls `security_beam.adopt_beam_card()`. The card becomes the only visual; the stand-in cylinder is hidden. `release_beam_card()` restores the card on respawn.
3. Card visibility = `alive && (not power_required || powered)`; the stand-in additionally follows `awake` (distance cull). An unpowered detector is now dark in both layers.
4. The card is rotated by the per-instance `BaseRotation` around the detector origin, matching the runtime beam (`actor · BaseRotation · mesh · actor⁻¹`), so the 44 detectors with `BaseRotation` no longer show an unrotated card.

Measured on a real `Guildhall_Gameplay` load + `device_layer.spawn_for_map("guildhall")` (headless probe, not committed):

```
BEAM_FIX SM_LightBeam cards=134 axis=col0 scale_slot=2 clamp=200.0 max_scale=195.5292 max_length_m=19.944
PROBE stats meshes=1361 chunks=343 beam_fixed=134
PROBE cards_group=134 mm=142 mi=218
PROBE devices=903 adopted=134
PROBE beam_card_bound=true
PROBE powered   card_vis=true  cyl_vis=false
PROBE unpowered card_vis=false cyl_vis=false
PROBE repowered card_vis=true  cyl_vis=false
PROBE pivot_z=(0.0, 0.0, -1.0)      # C_0 actor-local Z = record col0
```

No hook in `mission_controller.gd` is required. If the per-card split were reverted, the minimum hook would be: after `DeviceLayerScript.spawn_for_map(...)`, hide the loader's beam MultiMesh for detectors the layer owns — but that cannot express per-detector power, which is why the card was split instead.

## Test

`game/tests/test_beam_geometry.gd` (standalone; `run_tests.gd` untouched):

```
PASS: W0R.1 Guildhall_Gameplay has 134 /Game/Art/Effects/LightBeam/SM_LightBeam cards
PASS: W0R.1b devices_runtime has 134 light_beam records
PASS: W0R.2 level_loader.beam_card_transform() returns a Transform3D
PASS: W0R.3 134/134 cards pair with their detector record by authored position
PASS: W0R.4 134/134 world lengths match BeamLength_m within 2% (max err 0.041%)
PASS: W0R.5 134/134 directions equal the record col0 / actor-local Z within 1 deg (max 0.0198 deg)
PASS: W0R.6 134/134 applied scales are unclamped; max authored scale 195.5291 (ceiling 200)
PASS: W0R.7 134/134 cards keep the authored 1 m cross width (Y/Z scale 1)
PASS: W0R.8 authored max scale is 195.5291 (19.55 m), above the old 40 m clamp
PASS: W0R.9 _dict_to_transform delegates the exact SM_LightBeam path to beam_card_transform()
PASS: W0R.10 loader applied the beam fix 134 times (BEAM_FIX count)
PASS: W0R.10b loader BEAM_FIX max scale 195.5291
PASS: W0R.11 negative control: old col2+40 m transform fails length for 134/134 cards
PASS: W0R.12 negative control: old transform axis is 90 deg off col0 for 134/134 cards
PASS: W0R.13 negative control: the old 40 m clamp clipped exactly 129/134 cards
PASS: W0R.14 runtime beam pivot +Z equals the authored actor-local Z (0.000 deg)
PASS: W0R.15 runtime capsule runs along +Z (centre 2.171, rot X 1.571)
PASS: W0R.16 stand-in visual fallback also runs along +Z
PASS: W0R.17 adopted card is the single visual: unpowered both dark, powered card on and cylinder off
PASS: W0R.18 adopted card keeps the authored col0 direction after adoption
BEAM_GEOMETRY_SUMMARY: fails=0
```

The negative control rebuilds the exact old transform (`scaled_local(1,1,clamp(s,40))`), so the assertion is not vacuous: every card fails the old length check (ribbon `min(s,40)`), every old axis is 90° off col0, and exactly 129 are clamped.

Gates run in this worktree:

* `tools/check_scripts_compile.gd` — **82 checked, 0 broken** (baseline in `AGENTS.md` was 69 on an older tree).
* `test_beam_geometry.gd` — `fails=0`.
* `test_m2_player.gd` — `M2_SUMMARY: fails=0`.
* Full `make test` and E2E were **not** run (shared CPU; not in this wave's gate set).

## Risks / follow-ups (owner: next wave)

1. **`run_tests.gd` suite 70.3 encodes the old +X runtime axis.** It asserts the capsule at `position.x`, `rotation.z = -π/2`, and fires for players at `(7.9,0,0)` / `(7.5,0,0)` / `(1.5,0,0)`. With the authored axis those become `position.z`, `rotation.x = +π/2`, and players at `(0,0,7.9)` / `(0,0,7.5)` / `(0,0,1.5)`. That file is owned elsewhere this wave, so suite 70.3 will fail until updated. No other suite asserts the beam axis.
2. **GLB import is 2 % short**: the UE mesh long axis is 0.102 m but the imported `SM_LightBeam.glb` AABB is 0.100 m, so in-engine cards render 2.0 % short of `BeamLength` (4.2547 vs 4.3415 m for `C_0`). The transform itself is exact (0.04 %); fixing the import is an asset-pipeline task, not a loader change.
3. **Draw-call granularity**: beams went from ~11 `MultiMeshInstance3D` (134 instances) to 134 `MeshInstance3D` nodes — required for per-detector power visibility. `chunk_count` for `Guildhall_Gameplay` rose to 343 (+~123); full-scene `chunk_count >= 500` / `multi_nodes >= 200` in suite 11 should still hold, but `culled_nodes >= 300` loses the ~11 beam MultiMeshes and should be re-measured when `make test` runs.
4. Cards in a map with no mounted `device_layer` (or a detector that fails to pair) stay visible — authored behaviour, never dark.
5. Loader applies the fix only to the exact `SM_LightBeam` path; `SM_LightBeam_Base/Bulb/Lens` and every other mesh keep the generic 40 m clamp.
