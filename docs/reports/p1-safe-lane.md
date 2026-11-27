# P1-SAFE lane — safe room / portal / lantern (S12, KF14)

Lane S of the P1 content wave, branch `w10/p1-safe` (base `main` @ `27b4d5c`).
Parity target: shipped UE5.5 build (appid 3341000), S12 `01:10.81-01:20.10`,
KF14 `01:15.75`.

Reference: [`docs/reference/clip_1795033698901/clean/KF14_01m15s_saferoom_portal_hud.jpg`](../reference/clip_1795033698901/clean/KF14_01m15s_saferoom_portal_hud.jpg)
(annotated: `annotated/...`; BREAKDOWN §S12; baseline rows V6-01, G1-05, V1-04).

## What the frame needs, and what now exists

| KF14 subject | Port state | Authored source |
|---|---|---|
| Emerald/violet escape-portal wall outline on the safe-room brick wall | `SafeRoomPortalOutline` (QuadMesh + `tat_escape_portal.gdshader`), same visual as the endgame escape gates | `BP_EscapePoint.OpenColor` `#7EFF9B`, `ClosedColor` `#C651FF`, `SummonBox` Extent 92.07361 × 119.341095 cm, `Door_Light` `#BF00FF` 30 lm / 450 cm; `NS_EscapePoint` (`VFXSHAPES_BoxContourGlow` + `MI_RespawnPortal_LightBeam`) |
| Caged oil lantern, `[F] TURN ON` → flame, `[F] TURN OFF` | `SafeRoomLanternStation` (`toggleable_lantern.gd`), warm spot + emissive glass/flame, prompt flips | `BP_ToggleableLanternA` (`LightIntensity` 5.0, `LightColor` `#FFC277`, `AttenuationRadius` 450 cm, `OuterConeAngle` 80°, `EmissiveMaterialStrength` 6.0, `EmisShapeColor` `#FFD08E`, `LampCastShadow` false); `SM_LanternGuardA` + `GasLamp_A` + hidden `SM_Sphere2Count`; prompts `ST_Interactables.PromptTurnOn/Off` |
| `"SPIDER"` flyer beside the lantern | `SafeRoomSpiderFlyer` | `SM_PosterWantedA` + `MI_PosterWanted`; its UV window (U 0..0.324, V 0..0.451) is the top-left `WANTED £10000 … "SPIDER"` cell of `T_PosterWanted_DA.png` |
| Dark brick safe-room wall | authored level content (already loaded), pinned by the probe | `SM_Urban_Ext_Wall_4x6` + `MI_Urban_Ext_Stone` (`T_WallStoneBlockD`, tint 0.11/0.068/0.045) |
| Oval wall sconce | authored level content (already loaded), pinned by the probe | `SM_WallLightB` + instance override `MI_LightsSetD` at (126.29, 27.14, -2.28) |
| Briefing backdrop (KF13) | the live safe-room view, already implemented in `hud.gd` | — |

## Changes

| File | Change |
|---|---|
| `game/src/core/tat_escape_portal.gdshader` | Replaced the circular ring with the authored **jagged rectangular doorway contour**: emerald core lines (outer frame + inner door), violet chromatic fringe, green interior wash, noise-warped SDF plus a time shimmer. Colours default to `BP_EscapePoint` Open/Closed. |
| `game/src/interact/escape_gate.gd` | Added `make_portal_visual()` / `make_portal_light()` (shared builder), the authored 1.841 × 2.387 m portal size, the authored colours and the authored `Door_Light` (violet, 30 lm, 4.5 m, no shadow/fog, on only while active). Escape/extract contract, 3×3×3 trigger, 240 s cycle and group `escape_points` are unchanged. |
| `game/src/interact/toggleable_lantern.gd` | New `BP_ToggleableLanternA` port: cage + gas-lamp bracket, authored spot, hidden emissive flame shape, glass emission 6.0, `[F] TURN ON`/`[F] TURN OFF`, group `interactables`, `interact()`/`get_interact_prompt()`/`get_interact_point()`. |
| `game/src/missions/safe_room_dressing.gd` | New safe-room dressing builder: portal outline + lantern station + `"SPIDER"` flyer, anchored on the authored sconce wall. |
| `game/src/missions/mission_controller.gd` | `_add_guildhall_saferoom_dressing()` called from `_setup_environment()` for `guildhall`; prints a `P1-SAFE dressing:` report. |
| `game/tests/probe_p1_safe.gd` | New headless probe (see below). |

## Measured evidence

All runs serialized under `flock /tmp/opencode/tat2-godot.lock`; measured on the
lane tip, not inferred.

Compile (`tools/check_scripts_compile.gd`):

```
scripts checked: 205, broken: 0
```

(202 at the P0b tip + the three new GDScript files.)

Probe (`res://tests/probe_p1_safe.gd`, headless):

```
P1_SAFE probe: safe room / portal / lantern (S12, KF14)
  report: P1-SAFE dressing: anchor=(126.29, 25.0, -2.28) portal=portal lantern=lantern flyer=spider_flyer missing_meshes=0 missing_materials=0
  ok: portal base sits on the authored safe-room floor line (y=25.000)
P1_SAFE PASS checks=86 fails=0 skips=0
```

Key measured facts from that run:

- portal quad = `(1.840736, 2.386822)`, shader = `res://src/core/tat_escape_portal.gdshader`,
  `core_color=(0.2078, 1.0, 0.3294)`, `edge_color=(0.5614, 0.0831, 1.0)`;
- lantern cage = 2 authored surfaces with `MI_LanternGuardA` + yellow glass material;
  spot colour `(1.0, 0.5395, 0.1845)`, energy **0.5877** (authored 5.0 through the
  loader's monotonic curve), range 4.50 m, cone 80.0°, shadow off;
- prompts `[F] TURN ON` → `[F] TURN OFF` → `[F] TURN ON`, light/flame/glass emission
  all measured on then off, `toggled` = `[true, false]`;
- flyer UV `umax=0.3242`, `dv=0.4507` → the `"SPIDER"` atlas cell;
- gate light colour `(0.749, 0.0, 1.0)`, energy **1.3783** (authored 30 lm), 4.50 m;
  `activate()`/`expire()`/re-arm/`collapse()` measured; 3×3×3 trigger kept, no Label3D.

Runtime smoke (`build/qa/runtime_smoke.sh 90`, real `--qa-free-play` Guildhall
boot; log `/tmp/tat2-smoke-V9VOaz.log`):

```
RUNTIME_SMOKE_SCAN PASS exit=124 errors=0 raw=0 allowed=0 script_errors=0 shader_errors=0 mission_ready=1 reason=ok
RUNTIME_SMOKE PASS
```

The same log carries the integration evidence that the dressing is actually in
the loaded world (not only the probe):

```
TAT-2 P1-SAFE dressing: anchor=(126.29, 25.0, -2.28) portal=portal lantern=lantern flyer=spider_flyer missing_meshes=0 missing_materials=0
```

Vulkan shader render (real renderer under Xvfb, one Godot at a time, final
shader revision): compiled with no `SHADER ERROR`, frame 1280x720
(`/tmp/opencode/p1safe/portal_shader_probe.png`, outside the repo). Visual check
against KF14: jagged emerald outer frame + inner doorway, green field, saturated
violet chromatic fringe — matching the reference's composition; no shader errors
logged.

## Authored vs approximated

- **1:1 authored:** mesh/material paths, portal colours + portal size + door light,
  lantern spot colour/intensity/range/cone/shadow, emissive strength/colour,
  prompts, toggle behaviour, the `"SPIDER"` mesh/UV cell, the brick wall and oval
  sconce.
- **`PORT_DECISION` (placement):** the extract authors **no** `BP_EscapePoint`
  and **no** `BP_ToggleableLanternA` instance in this room. The 14 Guildhall
  escape markers are in the vault/basement (nearest 44.47, 28.03, -53.54) and the
  four PeripheryA lanterns are at x 55.22 / 54.79 / -24.80 / -13.02. The three
  props are anchored to authored landmarks — the sconce's wall face `z=-2.28`,
  the Contract-02 spawn (127.2747, 25.4694, -5.3296) and the floor top 25.0 —
  keeping KF14's arrangement (portal centred, lamp and flyer to its left).
  The props are 1-3 cm proud of the wall face to avoid z-fighting.
- **`APPROX_SHADER` (existing baseline label #8):** the contour is a shader
  reproduction of `VFXSHAPES_BoxContourGlow` + `MI_RespawnPortal_LightBeam`, not
  the authored Niagara system. Shimmer is a shader time function; the authored
  ember/crack particle renderers (`MI_BurstEmbers`, `Cracks`) are **HL-1** and are
  not reproduced.
- **`HL-1` (flame VFX):** the reference flame is a Niagara effect. The port uses
  the authored hidden `SM_Sphere2Count` emissive shape (the same stand-in the
  blueprint authors for non-Niagara instances). No flicker animation is invented.
- **`HL-7` (indirect bounce, V1-04):** the direct warm practical is authored 1:1;
  the orange bounce on the brick is the renderer's indirect/ambient response and
  is not measured here.
- **Reference wording vs this station:** BREAKDOWN §S12 describes the lamp "on the
  crate table"; the lane brief specifies a caged **wall** lantern station, so the
  station is wall-mounted at 1.6 m. The authored crate props in this room
  (`SM_CrateSetC`, y≈23.8) sit on the lower floor, not the spawn mezzanine.

## Row status after this lane

| Row | Status |
|---|---|
| V6-01 escape portal wall outline | Present in the safe room and on every endgame escape gate; authored colours/size/light. Shimmer + chromatic edge measured in a real render. Particle component remains HL-1. |
| G1-05 safe-room lantern toggle | Present; prompt/light/emissive state machine measured. Flame Niagara remains HL-1 (authored emissive-shape stand-in). |
| V1-04 lantern bounce | Direct practical authored 1:1; indirect bounce still governed by HL-7 (not measured). |
| Safe-room dressing / `"SPIDER"` flyer / escape portal | Present (brick wall + oval sconce pinned from authored rows; flyer UV-proven as the SPIDER cell; portal built from the escape-gate visual). |
