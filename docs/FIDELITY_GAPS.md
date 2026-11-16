# TAT-2 Fidelity Coverage (1:1 rebuild tracker)

Source of truth: `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/`
extracted through `tools/tat-extract` (CUE4Parse, `EGame.GAME_UE5_5`).

Generated from `extracted/filelist.txt` (22,005 entries) and the current `extracted/` tree.
Re-run the census with the commands at the bottom.

## Summary

| Area | In install | Extracted / parsed | Status |
|---|---|---|---|
| Packages (`.uasset` + `.umap`) | 13,162 | 5,805 JSON dumps (44 %) | partial |
| Static/skeletal meshes | 1,852 `SM_` + 156 `SK_` | 2,045 GLB | good |
| Textures | 2,211 `T_` packages | 2,227 PNG | good (all material textures) |
| Levels | 107 `.umap` | 107 JSON dumps, 77 shipped `.tatlevel.json` | good |
| DataTables / CurveTables / StringTables | 58 `DT_` / 79 `ST_` / curves | 141 normalized tables | good |
| **Animations** | **879 `AN_`** | **995 USD exported** (incl. 357 ACL-decoded), GLB batch converting; 14 failures are blend spaces | **wave A2 (in progress)** |
| **Weather / atmosphere** | 16 presets + `TATWeatherManager` in 103 levels | **applied** (`tools/parse_weather.py` -> `game/data/generated/weather/`, `weather_profile.gd`, mission wiring, suite 17) | **done (7aa34db)** |
| **Niagara VFX** | 120 `NS_` systems + 3,692 level placements | catalogue: 29 sprite-only / 70 mesh-ribbon / 21 graph-heavy; 139/148 materials resolved, 129/456 renderer textures | **catalogue done (26f9838); runtime blocked by compiled graphs** |
| **Materials** | 1,247 `MI_` + 386 `M_` + 167 `MF_` + 289 material layers | 1,552 resolved: textures + scalar/vector/switch params + render flags + phys material | **done (ec9f700)** |
| **Decals** | 16 `DecalComponent` files + 10 `DecalActor` | level JSON only | **wave A5** (BP template resolution needed) |
| **Rect / sky lights** | 7 `RectLightComponent`, 1 `SkyLight`, 1 `SkyAtmosphere` | level JSON only | **wave A5** |
| **Post-process / fog** | 2 `PostProcessVolume`, 1 `ExponentialHeightFog` | level JSON only | **wave A1/A5** |
| **Landscape** | 128 `LandscapeComponent`, 128 heightfield collisions, splines, Nanite components | heightmaps + collision | splines/grass/layers **wave A5** |
| **Audio** | 3,425 raw Wwise WAVs + `.bnk` | 9 synthesized SFX | **blocked**: 0xFFFF Vorbis, no decoder (wave A6) |
| **Blueprints (logic)** | 981 `BP_` + 225 `BPUI_` | all 1,437 BP/material-graph packages dumped; movement/detection/state-speed constants located | **wave A6 (in progress)** |
| Skeletal meshes / skins | 156 `SK_` | 156 GLB | good (no animations yet) |

## What is already 1:1 (or close)

- **Geometry**: every shipped mesh is a real GLB exported from the install. Guildhall 15,871 instances / Old Manor 6,461 / Thieves' Den 272, with 32 m chunks, real material slots and landscape heightmaps.
- **Materials (albedo/normal/ORM)**: `materials.json` maps 1,272 UE material instances to real textures; glass, wallpaper, wood, brick and stone overrides were derived from those assets.
- **Tuning data**: 141 DataTables/CurveTables/StringTables drive contracts, difficulty, tools, stamina, AI and progression.
- **Lighting positions/colours**: 3,479 extracted lights (96 loaded per map, brightest 4 shadowed).
- **Level layout**: 77 normalized `.tatlevel.json` files feed the loader (meshes, landscapes, lights, markers).

## Gaps and the plan

### A1 — Weather / atmosphere (in progress)
`TATWorldSettings` → `TATWeatherManager.PresetOverrides` → `BP_WeatherPreset_*`.
Presets carry moon brightness/colour/size, sun brightness, cloud colour/opacity,
`ExponentialHeightFog` density/falloff/inscattering, `SkyLight` intensity/colour/cubemap,
`SkyAtmosphere`, post-process colour grading, rain/wind flag and intensity.
Plan: `tools/parse_weather.py` → `game/data/generated/weather/*.json`; apply to
Godot `Environment`, moon `DirectionalLight3D`, fog and glow. Replaces hand-tuned values.

### A2 — Animations (in progress)
`anims` exports 0/1,002 because `AnimationExporter` only supports ActorX/UEFormat/USD.
Plan: export a supported format, convert to GLB (Blender headless if USD), manifest,
Godot `AnimationPlayer` wiring.

### A3 — Material fidelity
`MI_`/`M_` JSON contains scalar/vector/texture parameters, blend mode, two-sided,
opacity mask and emissive values. Currently only albedo/normal/ORM/tint are used.
Plan: parse parameters into `material_params.json`; build `ShaderMaterial` or
`StandardMaterial3D` values from them; keep per-material overrides.

### Hard limit — cooked material graphs
Cooked UE `Material` exports contain **no expression graph and no texture references** (verified: `M_Decal_Puddle` has only BlendMode/flag properties). Textures that live in a material graph are not recoverable from the install; only exposed `TextureParameterValues` on MaterialInstances resolve. Consequence: 667 level decals and some Niagara sprite materials have no trustworthy texture. The runtime must validate material->texture stem matches and skip the rest rather than bind generic fallbacks. A true 1:1 look for those assets would require recreating graphs from reference, which is not in the cooked data.

### A4 — Niagara VFX (catalogue done, runtime constrained)
120 systems catalogued (`tools/parse_vfx.py`, 26f9838): 29 sprite-only, 70 mesh/ribbon, 21 graph-heavy; 139 of 148 renderer materials resolve, but only 129 of 456 renderer entries have a real texture. Loop duration is null for all systems; spawn rate, lifetime, velocity and colour curves are computed inside **Niagara VM bytecode**, not stored as values. A 1:1 particle conversion would require decompiling the Niagara VM; the runtime therefore must not invent rates. Level placements (3,692) are extracted so effects can be anchored/activated once a specific system is hand-matched or its bytecode is analysed.

### A4b — Niagara VFX (original)
120 systems dumped (curves/LUTs included). A faithful Niagara graph translation is a
separate project; first extract emitter material, spawn/lifetime/colour parameters, then
drive GPUParticles3D from those values. No fabricated effects.

### A5 — Level component fidelity
The level JSONs contain the missing actors; components from Blueprint actors are
`SimpleConstructionScript` stubs whose templates live in the `BP_*` class JSON.
Plan: resolve BP SCS templates (as already done for `BPP_*_PLA`) and emit
`rect_lights`, `sky_lights`, `decals`, `niagara`, `postprocess`, `volumes`, plus
landscape spline/grass data.

### A6 — Gameplay constants (in progress)
BP defaults carry the real movement and perception values: player 360/180 cm/s walk/crouch, +90 sprint increment, 550 jump, 91 cm capsule half height, 79.625 cm eye offset; guard 250 cm/s, 25 m sight, 30 m lose-sight, 40° half-FOV, 25 m hearing; `DA_AIStatesToSpeed_Guard` 1.5/1.7 m/s; `DA_DetectionSettings` 0.4 s/m (0.2 alerted) with crouch multiplier. Plan: parse into `game/data/generated/gameplay/`, update player/guard constants and the detection ramp.

### A7 — Audio
Wwise files are RIFF with codec tag `0xFFFF` (Wwise Vorbis); FFmpeg reports
"no decoder found". `vgmstream`/`ww2ogg` are not installed. Blocked until a decoder
is available; the 9 synthesized SFX remain as placeholders.

### A7 — Blueprint gameplay logic
981 `BP_` packages exist. DataTables/CurveTables already drive most tuning; BP graphs
(visual scripting) are not machine-translated. Further gains: dump all `BP_` JSON,
extract component defaults (AI perception, interactables, doors), and port state logic
from those defaults rather than guessing.

## Reproduce the census

```bash
# package inventory
awk -F'\t' '{print $1}' extracted/filelist.txt | grep -E '\.(uasset|umap)$' | wc -l
# JSON dump coverage per class
find extracted/json -name '*.json' | wc -l
# assets
find extracted/assets -name '*.glb' | wc -l
find extracted/assets -name '*.png' | wc -l
# animations (currently 0)
find extracted/assets -name '*.ueanim' -o -name '*.anim.glb' | wc -l
# weather
find extracted/json/Art/Environment/Weather -name '*.json' | wc -l
# niagara
find extracted/json -name 'NS_*.json' | wc -l
```

## Update log

- 2026-11-16: census created; Niagara systems (120) dumped; animation export failure isolated (`Gltf2` unsupported); audio codec limitation confirmed.
- 2026-11-16: level components shipped (`e17beae`): 667 decals, 3,692 Niagara placements (0 unresolved), 31 rect lights, 288 volumes, 52 splines, 1 sky/fog/atmosphere; material-graph limit documented. A1 weather shipped (`7aa34db`): 16 presets parsed, map mapping with provenance, fog 0.4 -> 0.004, moon energy/rotation, sky-light ambient, post-process saturation/bloom; suite 17 asserts real preset values. A3 materials shipped (`ec9f700`): 1,552 materials with real roughness/metallic/emissive/static-switch/render flags. A2 animations and A5 level components running.
