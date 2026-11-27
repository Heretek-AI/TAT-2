# P1-W — ward / lockdown / alarm (S25–S26, KF28/KF29)

Lane W of the P1 route-content wave. Branch `w10/p1-ward`, base `27b4d5c`.
No producer was run and `game/data/generated/` was not written: the lane reads
the already-generated device/level/material payloads and the extracted BP dumps.

Rows owned: **V6-04** (purple ward + green vine lock), **G5-03** (beam
tripwire → ward lockdown), **G5-04** (ward shatter → crimson alarm),
**V1-07** (crimson alarm spotlight), **UI5-06** (status icons above the Light
Gem). No expansion content: every new node is `parity_restoration` (the vine
lock reproduces the shipped `BP_OneWayBarrier`).

## What was wrong (measured)

- The flat violet pane was the `ward_zone.gd` `BoxMesh` with
  `tat_ward.gdshader`. The authored ward geometry (`SM_BlockerWard_*`, the
  `BP_WardZone_Blocker_C` actor's seven `StaticMeshComponent` shards) was
  present in `Guildhall_Gameplay.tatlevel.json` but **never spawned**: the
  loader's `"blocker" in low_mp` filter dropped all 376 Guildhall instances
  (`RE-B-14`). The comparison's “near-opaque flat violet box” is that box.
- The green door ward had no carrier. `BP_OneWayBarrier` is a Kismet spawn
  (no placement in `levels/**`), and no vine/lock interactable exists.
- The beam trip activated the authored ward through the existing device graph
  (`BP_Detector_LightBeam_C_117.actions` includes `BP_WardZone_Blocker_C_31`)
  but raised no status icon and triggered no alarm.
- The alarm eye only had a small emissive flash; no crimson spotlight.

## What changed

| file | change |
|---|---|
| `game/src/core/level_loader.gd` | spawn `SM_BlockerWard_*` per instance into `ward_shards`, hidden + collision-free; keep fog/sky blockers dropped. `name_skipped` no longer counts ward shards. |
| `game/src/devices/device_layer.gd` | pair each authored shard with its nearest ward blocker (3 m, nearest-only, deterministic); expose `ward_shards_total/adopted`; release on clear. |
| `game/src/devices/ward_zone.gd` | adopt the authored shards as the ward's only visual, hidden until active; remove the flat pane; procedural 7-shard fallback for detached/synthetic wards; `shatter()` + `ward_shattered`; slow wards keep a low-alpha veil, not a solid box. |
| `game/src/core/tat_ward_shard.gdshader` | APPROX_SHADER: authored purple tint + emissive/fresnel, unlit translucent crystal surface. |
| `game/src/devices/vine_lock.gd` | new `BP_OneWayBarrier` reproduction: 2.6 × 3.4 m plane, authored green door-ward material, authored BlockerBox, seal/shatter state. |
| `game/src/core/tat_vine_lock.gdshader` | APPROX_SHADER: authored `T_DoorWard_Mask` × `_Glyph_Hand` × `_Lines` composition with the authored green tint. |
| `game/src/devices/alarm_eye.gd` | parse the authored visual cone/range; `trigger_alarm()` public; spawn the crimson `SpotLight3D` along the authored actor forward, free it on reset/death. |
| `game/src/missions/mission_controller.gd` | Guildhall foyer lockdown: add the green door ward to the authored beam's action list, raise the jaw-trap icon on `beam_triggered`, contact-dwell shatter → alarm + music sting; clear the icon at run end. |
| `game/src/ui/hud.gd`, `game/src/ui/status_icon.gd` | UI5-06 status icon above the Light Gem: authored jaw-trap GLBs in an orthographic SubViewport + procedural countdown ring. |
| `game/tests/probe_p1_ward.gd` | 44-check headless probe (see below). |

Existing contracts kept: `security_beam.beam_triggered(source)` is unchanged and
still fires once per trip; the ward's `activate_from`/`activate`, blocker
layer bit 4 (16), slow-ward timing/damage and `device_layer` groups/census are
unchanged.

## Measured evidence (this tree, headless, no GPU)

```
tools/godot … check_scripts_compile.gd
  scripts checked: 205, broken: 0

tools/godot … probe_p1_ward.gd
  P1_WARD PASS checks=44

make test
  SUMMARY: fails=0    (322 PASS, suites numbered to 120)

tools/godot … tests/e2e/run_e2e_tests.gd
  SUMMARY: fails=0 passed=300 total=300
```
The E2E run started before the last three lane tweaks (6 m shard pairing,
vine z -47.1, alarm hold 6 s) but with the loader/device/HUD/mission changes in
place; those tweaks do not change any E2E assertion. The final compile/probe/
`make test` re-run on the committed tree is recorded in the handoff return.

Probe facts (all measured on the loaded Guildhall_Gameplay payload):

- foyer ward `BP_WardZone_Blocker_C_31` zone = `0.30 × 3.936 × 1.653 m`
  (authored ZoneSize 30 / 165.26434 / 393.638 cm remapped X,Z,Y);
- the foyer ward owns its authored **7-shard** cluster; the shards are hidden
  before activation and all 7 visible after `activate()`; all 7 hidden again
  after `shatter()`;
- `Guildhall_Gameplay` loads **233** authored `SM_BlockerWard_*` instances (the
  count in that payload); `device_layer` pairs **233/233** with their nearest
  ward (the authored `AddMeshesAlongVolume` spread reaches 5.16 m, so the
  nearest-ward cap is 6 m). The foyer cluster is complete. Device census stays
  **903 devices / 36 ward blockers**;
- beam 117 keeps its authored **9.7177 m** length and fires `beam_triggered`
  once, activating the ward and sealing the green door ward;
- the green door ward is the authored **2.6 × 3.4 m** plane with the authored
  **0.16 × 2.56 × 3.36 m** BlockerBox (BoxExtent 4/128/168 cm) and the authored
  `MI_DoorWard_OneSided_Green` tint **(0.1334, 1.0, 0.0)**;
- the alarm eye keeps the authored `OuterConeAngle` **15°** and
  `AttenuationRadius` **15.32772 m**, and the spawned spot aims along the
  authored actor forward (straight down, `(0, -1, 0)`);
- HUD exposes `set_status_icon` / `clear_status_icon` / `status_icon_state`;
  the icon raises with kind `jaw_trap` and an 8 s ring and clears.

Ray measurements used for placement (scratch probe, loaded Guildhall shell,
`probe_p1_ward` no longer includes it):

- east-wall plane at **x ≈ 30.75**; the 4 m ward archway is the gap
  **z -43.0 … -41.0** between `SM_Civic_Doorway_Frame` jambs at **-44.02** and
  **-40.02**; the authored shard cluster sits at x 30.70-30.90, z -40.33 …
  -43.52, y 28.0;
- the `Basement Stairs` door cluster is the authored
  `SM_InteriorSign_WealthyA` plaque at **x 30.72, y 30.74, z -45.79** plus
  `SM_FixtureWallC` sconce (`z -45.78`) and `SM_LightSwitch_Main`
  (`z -45.51`); the green door ward is centred just south of it at
  **x 30.70, z -47.10**, facing west.

## Authored values vs approximations / HARD_LIMIT

**Authored, carried 1:1**

- ward zone box and inactive default from `devices_runtime.json` / the
  `BP_WardZone_Blocker` CDO (`WardInitiallyActive=false`);
- ward shard geometry, transforms and 7-component layout from the shipped
  `SM_BlockerWard_*` GLBs / level instances;
- ward active tint from `BP_WardZone_Base.WardColor` **#FF4DFD**; emissive
  energy from `MI_BlockerWard` **1.0**; fresnel base/exponent from
  `Fresnel_Parameter` **(0.04, 2.0)**; `MI_BlockerWard` EmissiveColor
  **(1.0, 0.1307, 0.7967)** is asserted in the probe;
- vine plane size/height, BlockerBox extents, green tint and the three
  `T_DoorWard_*` textures from `BP_OneWayBarrier` / `materials.json`;
- beam length, action edge, power edge, and the unchanged `beam_triggered`
  signal;
- alarm eye actor pose, basis (forward down), `OuterConeAngle` 15°,
  `AttenuationRadius` 15.32772 m;
- audio: `ward_activate`, `ward_end`; the alert uses the authored
  `guard_alerted` music event (`Play_Mus_GuardAlerted_Generic_01`).

**Approximations / HARD_LIMIT**

| item | label | why |
|---|---|---|
| `tat_ward_shard.gdshader` surface | `APPROX_SHADER` (HL-1) | `M_BlockerWard` graph not decompiled; colour/emissive/fresnel are authored, the normal-wave scroll is an object-space shimmer (no second sampler). |
| active ward colour | `APPROX_COLOR` (HL-1) | the saved per-instance MID is **#7DFFB2** (green); the reference KF28 ward is purple. Active uses the base `WardColor #FF4DFD`; the cooked activation colour change is not in the dump. |
| green door-ward material graph | `APPROX_SHADER` (HL-1) | `MI_DoorWard_OneSided_Green` graph not decompiled; the port composes the authored arch mask × hand glyph × line network (the lines PNG is opaque, so luminance is the mask). |
| green door-ward placement | `APPROX_PLACEMENT` (HL-3) | `BP_OneWayBarrier` is a Kismet spawn; no level transform. Anchored on the measured sign/sconce/switch door cluster beside the ward archway. |
| shatter trigger | `PORT_DECISION` (HL-3) | the cooked Kismet trigger is unrecoverable; the port uses a 0.35 s body-contact dwell on the active ward, matching the reference walk-up at 03:37.7–03:38.2. |
| crimson colour / energy | `APPROX_LIGHT` (HL-1) | the runtime alarm light is Kismet-set (no authored light record); colour (1.0, 0.07, 0.05) and energy 4.5 are the KF29-documented values already used by `vfx_manager.spawn_crimson_alarm`. |
| crimson wash angle 32° | `APPROX_LIGHT` (HL-1) | the authored camera cone is 15° (security cone); 32° is the KF29 capture-builder measurement for the wide stair wash. |
| alarm sting | `APPROX_CUE` (PG-6) | the distinct AU5-06 one-shot is not a separate extracted event; the authored `guard_alerted` music event is the closest extracted sting. |
| jaw-trap icon render | `PORT_DECISION` | no 2D jaw-trap UI texture exists in the extracted set; the icon renders the authored `SM_JawTrap*` GLBs in an orthographic SubViewport. The ring and the 8 s duration are HUD chrome (no authored duration recovered). |
| green vine lock interaction | `HARD_LIMIT` (HL-3) | the shipped actor is a magic seal, not a lockable door; the port does not add a lockpick prompt. |

## Rows now present

| row | state |
|---|---|
| V6-04 | authored faceted purple ward cluster on the foyer archway + green door ward on the `Basement Stairs` door; state-driven, no flat pane. Not visually scored in-lane (no GPU capture). |
| G5-03 | beam trip → ward seal + vine seal + jaw-trap status icon; existing beam contract kept. |
| G5-04 | contact shatter → ward/vine collapse + crimson alarm spotlight + `guard_alerted` sting. |
| V1-07 | crimson spotlight at the authored stairwell alarm eye, authored cone/range/pose, KF29 colour/energy. |
| UI5-06 | jaw-trap status icon above the Light Gem with a countdown ring. |

**Not claimed:** visual parity PASS. The lane has no GPU capture; the KF28/KF29
poses must be re-run by the integrator (`build/qa/p0b_capture.sh`) before the
rows are scored. The shatter trigger, vine placement, active colour, alarm
colour/energy and status-icon ring remain the documented approximations above.

## Open items for the integrator

- The nearest-ward pairing cap is 6 m because the authored
  `AddMeshesAlongVolume` spread reaches 5.16 m; a dense row of ward actors
  could in principle assign a far shard to an adjacent ward. The foyer cluster
  is exact (7/7 at ≤1.7 m) and no other ward shares its shards. If a visual
  audit finds a shard showing from the wrong ward, the fix is a producer field
  carrying the source actor id (data change, not this lane).
- The `Basement Stairs` plaque is the generic `SM_InteriorSign_WealthyA`; its
  text is not a `Basement Stairs` string. V4-07 (plaque text) stays Lane B /
  dressing.
- No door leaf opens at the `Basement Stairs` door. The ward archway is the
  blocking route; if the route requires passing the green door, a door leaf +
  open animation is a separate content task.
- `make audit` was attempted: the content/texture gates pass after dropping the
  over-cap `T_DoorWard_Mask.png` binding (texture-cap-check now OK), but the
  tool-version stamp gate fails in this worktree because
  `tools/bin/vgmstream/vgmstream-cli` is absent ("vgmstream: r2168 -> missing").
  That is an environment/tooling gap, not a code regression; re-run
  `make audio-tools` / the audit in the main checkout.
- `gate-ratchet` and the full P0b gate set were not run by this lane; run them
  at the merged HEAD.
