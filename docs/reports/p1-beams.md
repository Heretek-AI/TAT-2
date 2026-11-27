# P1 lane B — security beams / foyer dressing (S24, KF27)

Branch `w10/p1-beams`, base `9cba135` (merged P1 tip; the lane's original
commit is `372bf74`, merged as `08a1cfa`). Scope: V6-03, V4-07, V1-04/AU3-04
marble (material only). A follow-up Xvfb/Vulkan A/B for the post-P1 capture
brightness regression is recorded below.

## What changed

| Subject | Before | After |
|---|---|---|
| `SM_LightBeam` cards (330) | full-tube `tat_beam` stand-in: `beam_color a=0.55`, energy 1.7, view-facing core over the whole 1 m shell | authored `MI_LightBeam_SM` centre-line model: 1.5 cm line at opacity 0.5, 6 % fake glow (8.5 cm), 25 m fade, HDR `(5.0, 4.3813, 3.5156)` × 3.0, additive/unlit/two-sided |
| Loader material | hard-coded stand-in params | `_build_beam_material()` reads `materials.json` (`BaseColor`, `EmissiveMultiplier`, `Center Line *`, `Fake Glow *`, `FadeDistance`) |
| Fallback cylinder (`security_beam.gd`) | 2.4 cm radius, warm alpha 0.55, energy 2.0 | 1.5 cm diameter, authored HDR/glow/fade, radial axis Y |
| Foyer emitter bulb | authored `MI_LightBeam` glass path (no emission) | unshaded authored `Emissive Color (1.0, 0.6892, 0.2661)` × `Brightness 2.0` |
| Cyan node | `SM_Sphere2Count` record is `hidden_in_game: true` (authored BP/Niagara overlay) | visible cyan stand-in from the authored mesh at the authored light position, KF27 size, `PORT_APPROX` |
| Plaques | wooden plates, no text (Text3D not exported) | authored strings `Basement\nStairs` and `WC` as `Label3D`s at the authored plate transforms |
| Floor plate | no authored placement in the POI export | authored `SM_FloorPlate` mesh + `MI_TrimMetalSurfaceA_Light`, `PORT_APPROX` placement from KF27 |

The P0a axis/length fix is untouched: `beam_card_transform()` is byte-identical
and the probe asserts local X → record col2 plus slot-2 length over all 330
cards.

## Authored values used (measured from the shipped data)

`extracted/json/Gameplay/Traps/Detectors/LightBeam/MI_LightBeam_SM.json`:

```
BaseColor             (5.0, 4.3813, 3.5156, 0.5)   linear
EmissiveMultiplier    3.0
Center Line Thickness 0.015 m
Center Line Opacity   0.5
Center Line Falloff   0.25
Fake Glow Opacity     0.06
Fake Glow Center W.   0.085 m
Fake Glow Power       1.1
FadeDistance          25.0 m
render                BLEND_Additive, two_sided, MSM_Unlit
```

The mesh (`SM_LightBeam.glb`) is a 0.102 m × 1.002 m × 1.002 m crossed-card
volume with a 14 mm octagonal core on local X; the 1.5 cm authored line is the
core, and the 1 m shell is now transparent outside the 8.5 cm glow.

`BP_Detector_LightBeam.json`: PointLight intensity **0.01 lm**, radius
**0.35 m**, temperature 5500 K, cast shadows off. That is a sub-centimetre
glow at foyer distances; it is not reproduced as a real light (see below).

`Building_Guildhall_POI.json` Text3DComponents:
`BP_SignPlate3D_C_5` = `"Basement\r\n Stairs"` on `SM_InteriorSign_WealthyA`;
`BP_SignPlate3D_C_0` = `"WC"` on `SM_InteriorSign_CommonC`.

## Probe

`game/tests/probe_p1_beams.gd` (headless, no map load):

```
tools/godot --headless --path game --script res://tests/probe_p1_beams.gd
```

Checks: shader render_mode/uniforms; loader material vs the authored row; the
330-card col2/slot-2 transform; the card AABB; the line/glow/fade profile at
r = 0, 0.75 cm, 1 cm, 25 cm, 50 cm and distance 8/20/25 m; the authored foyer
records (15 emitter parts, 5 vitrine cases + statue, armchair/ottoman, 2
plaques, cyan node); and the dressing module on a synthetic scene.

Measured output (2026-11-26, worktree `w10/p1-beams`):

```
P1_BEAMS OK shader render_mode=unshaded+blend_add+cull_disabled authored_defaults=true radial=true
P1_BEAMS OK loader MI_LightBeam_SM shader=tat_beam.gdshader color=(5.0000,4.3813,3.5156,0.50) emissive=3.0 line=0.015m a=0.50 falloff=0.25 glow=0.06/0.085m p=1.1 fade=25m axis=0
P1_BEAMS OK authored MI_LightBeam_SM row matches the port params (BaseColor=[5.0, 4.3813, 3.5156, 0.5], line=0.015, glow=0.06, fade=25, additive/two-sided/unlit)
P1_BEAMS OK geometry col2 axis=(-0.0, 0.0, 1.0) len=42.0m cards=330 max_axis_err_deg=0.000005 max_len_err=0.0000057 card_aabb=(0.100,1.000,1.000)
P1_BEAMS OK profile center=0.560 half=0.304 1cm=0.052 25cm=0.0000 shell=0.0000 fade@8=0.560 @20=0.502 @25=0.0000 (no full-tube)
P1_BEAMS OK foyer records emitter_instances=15 (5 base+bulb+lens x3) vitrine=5 statue=1 armchair=1 ottoman=1 rug=2 plaques=2 cyan_node=true at (28.8973, 30.4025, -58.002)
P1_BEAMS OK dressing bulb=true node=true stats={ "emitter_bulbs": 1, "node_items": 1, "node_created": 0, "plaque_labels": 2, "floor_plate": 1, "floor_plate_approx": 1 } labels=["Basement\nStairs", "WC"] plate=true approx=true
P1_BEAMS PASS checks=7 fails=0
```

Compile: `scripts checked: 204, broken: 0`.

`run_tests.gd`: `SUMMARY: fails=0`; suite 29b PASS with the authored values.

`e2e_p2`:
`P2_SUMMARY: expected_fail=1 expected_delta=0 fixed=0 unexpected_fail=0`;
`P2-BEAM-AUTHORED-PORT` PASS with port == authored
`((5.0, 4.3813, 3.5156, 0.5)) emissive=3.00 line=0.015m a=0.50 glow=0.06
fade=25m`.

Real free-play boot (`build/qa/runtime_smoke.sh 90`):
`RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 ... mission_ready=1`, and the
dressing ran once:
`P1_FOYER_DRESSING bulb_items=11 cyan_node_items=0 cyan_node_created=1
plaque_labels=2 floor_plate=1 floor_plate_approx=1`.
`bulb_items=11` is all chunked MultiMesh items carrying the 134 emitter bulbs
(the probe's synthetic scene reports 1 because it has one item).
`cyan_node_items=0` is the authored record's `hidden_in_game: true` proxy:
the module correctly does not use the hidden proxy and creates the visible
PORT_APPROX node instead.

## PORT_APPROX / HARD_LIMIT

- **Beam falloff shape** is an authored-parameter match, not the decompiled UE
  material graph: the params are exact and the model (line + glow + fade) is
  authored, but the edge/fresnel terms (`EdgeFadePower`, sphere mask) are not
  reproduced. Label `PORT_APPROX` for the exact pixel falloff.
- **Cyan node geometry** is `HARD_LIMIT` for the exact shipped node: the POI
  record (`SM_Sphere2Count` at 28.8973, 30.4025, -58.002) is
  `hidden_in_game: true` with `MI_EmissiveShape` + per-instance custom data —
  the visible KF27 node is a Blueprint/Niagara overlay that the extraction
  does not expose. The port creates a visible `PORT_APPROX` lozenge from the
  authored mesh (0.12 × 0.35 × 0.10 m at the authored light position) using
  the authored cool light colour `82A7FF` (130,167,255).
- **Floor plate placement** is `PORT_APPROX`: the mesh and material are
  authored, but the POI export has no `SM_FloorPlate` record. Placement is read
  from KF27 (foyer centre, in front of the vitrine).
- **Plaque font** is Godot's default `Label3D` font, not the UE Text3D font;
  the strings and plate transforms are authored. `PORT_APPROX` (legibility,
  not typeface).
- **Emitter point light** is not spawned: the authored intensity (0.01 lm) and
  radius (0.35 m) are invisible at foyer distances. The bulb emission carries
  the read.

## Post-P1 capture brightness A/B (2026-11-26 follow-up)

The merged P1 capture (`9cba135`) was much brighter than the pre-P1 capture
(`5301fc6`). A controlled A/B with the diagnostic
`TAT2_P1_FOYER_DRESSING` switch (values: unset/`all` = all parts, `off` = no
dressing, or a comma list of `bulbs,node,plaques,plate`) was run on the merged
tree, one Godot at a time under the shared flock, Xvfb Vulkan, three poses.
Means are the capture harness `median_mean` (ITU-R 601 luma, 5-frame median).

Pre-fix (9cba135 + the switch only):

| run | upper_foyer | yaw180 | lounge |
|---|---:|---:|---:|
| dressing `off` | 70.96 | 84.42 | 53.07 |
| dressing `on` (all) | 71.02 | 84.43 | 53.08 |

The dressing changes the mean by **≤0.06**; the regression is **not** the
foyer dressing. The switch was proven live in the log
(`P1_FOYER_DRESSING skipped env=off`).

**Root cause:** `game/src/ui/status_icon.gd` (P1-W/UI5-06) built its HUD
jaw-trap `SubViewport` without `own_world_3d`, so it shared the gameplay
`World3D`. Its `DirectionalLight3D` (`light_energy = 1.6`) and the 0.8 fill
then lit the whole level. Every other UI SubViewport
(`wardrobe_ui`, `mission_prep_ui`, `ledger_ui`, `main_menu`) already sets
`own_world_3d = true`; the status icon was the only exception. Headless
probes/runtime smoke cannot see it because `_build_mesh_icon()` is skipped
when `DisplayServer.get_name() == "headless"`.

**Fix:** `vp.own_world_3d = true` in `status_icon.gd`.

Post-fix A/B (same three poses):

| run | upper_foyer | yaw180 | lounge |
|---|---:|---:|---:|
| dressing `on` (all, default) | 40.88 | 39.47 | 28.38 |
| dressing `off` | 40.80 | 39.46 | 28.36 |
| bulbs only | 40.82 | 39.47 | 28.37 |
| node only | 40.86 | 39.46 | 28.36 |
| plaques only | 40.80 | 39.46 | 28.38 |
| plate only | 40.80 | 39.46 | 28.37 |

Pre-P1 reference (`5301fc6`): 45.8 / 39.0 / 28.6. The post-fix yaw180 and
lounge match pre-P1 within 0.5; upper_foyer is 4.9 lower (the authored beam
material removed the cream bars, which is the intended fix, not a
regression). The largest single dressing contribution is the cyan node at
**+0.06** mean (upper_foyer), within frame noise; the authored HDR bulb
(`2.0, 1.38, 0.53`) and node (`1.53, 1.97, 3.0`) values are therefore kept
as authored — no clamp/PORT_APPROX tradeoff is needed at the port's 1.6 glow
threshold. Final default: **`TAT2_P1_FOYER_DRESSING` unset = all four parts**.

Evidence: `docs/reports/logs/p0b/p1_beams_ab_{off,on}/`,
`p1_beams_fix_{on,off}/`, `p1_beams_part_{bulbs,node,plaques,plate}/`
(manifests + capture logs; PNGs are gitignored).

## Integration note (p2)

The `e2e_p2_parity` beam DELTA was promoted to `P2-BEAM-AUTHORED-PORT`
(`P2_SUMMARY ... expected_delta=0 fixed=0`). The P1 integration tip already
re-stamped `build/qa/run_p0b_gates.sh:353` and `tools/gate_ratchet.json` to
`expected_delta=0`; no further action.
