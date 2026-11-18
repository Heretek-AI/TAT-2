# TAT-2 Fidelity Coverage (1:1 rebuild tracker)

Source of truth: `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/`
extracted through `tools/tat-extract` (CUE4Parse, `EGame.GAME_UE5_5`).

Generated from `extracted/filelist.txt` (22,005 entries) and the current `extracted/` tree.
Re-run the census with the commands at the bottom.

## Summary

| Area | In install | Extracted / parsed | Status |
|---|---|---|---|
| Packages (`.uasset` + `.umap`) | 13,162 | 5,805 JSON dumps (44 %) | partial |
| Static/skeletal meshes | 1,852 `SM_` + 156 `SK_` | 2,045 GLB (`2,027` GLB-ordered + `18` sidecar `mesh_materials.json`) | **done (`6783c2d`)** |
| Textures | 2,211 `T_` packages | 2,416 PNG (+24 startscreen landscape/OldManor window +10 WindowPanel/wood/fabric +155 OldManor_P landscape) | **done (`8f07b7d`, `754bbb6`, `24abf18`)** |
| Levels | 107 `.umap` | 107 JSON dumps, 73 clean `.tatlevel.json` (`146,563` orthonormal bases, `OverrideMaterials`, `bVisible:false`/`SplineEditorMesh` filtered, `1,293` emissive CPD shapes) | **done (`7458198`, `24cac7e`, `d0f895a`)** |
| DataTables / CurveTables / StringTables | 58 `DT_` / 79 `ST_` / curves | 141 normalized tables | good |
| **Animations** | **879 `AN_`** | **995 GLB clips** (357 ACL-decoded, exact durations, manifest); 14 blend-space graphs unsupported | **done (acd368a); runtime wiring in progress** |
| **Weather / atmosphere** | 16 presets + `TATWeatherManager` in 103 levels | **applied** (`tools/parse_weather.py` -> `game/data/generated/weather/`, `weather_profile.gd`, mission wiring, suite 17) | **done (7aa34db)** |
| **Niagara VFX** | 120 `NS_` systems + 3,692 level placements | catalogue: 29 sprite-only / 70 mesh-ribbon / 21 graph-heavy; 139/148 materials resolved but 91/139 carry no texture; 129/456 renderer entries textured | **catalogue done (26f9838); runtime blocked by compiled graphs** |
| **Materials** | 1,247 `MI_` + 386 `M_` + 167 `MF_` + 289 material layers | 1,571 resolved (`1,367` albedo, `123` opacity): authored families, Overlay/Multiply vectors, `BlackUnlitMaterial`, GLB primitive slot order, `tat_glass.gdshader` + `tat_emissive_cpd.gdshader` | **done (`754bbb6`..`32d6a52`)** |
| **Decals** | 667 placements (16 files) | **347 spawned / 112 skipped** after material validation (OldManor 203/89, Guildhall 135/23, Den 9/0) | **wired (9b1a22a)** |
| **Rect / sky lights** | 31 rect placements, 1 sky light, 1 atmosphere | 1 active rect light wired (26 authored off), sky/atmosphere applied | **wired (9b1a22a)** |
| **Light intensity / range** | 682 Guildhall lights, authored intensity `0.01–2500` (median `15`) | linear `1/15` scale (median -> `1.0`, floor `0.01`, ceiling `4.0`); radius 1:1 in metres (200 m guard); attenuation `1.0`; budget ranking uses the same scale | **done (cd3590a; `docs/reports/lighting-intensity.md`)** |
| **Post-process / fog** | 2 `PostProcessVolume`, 1 `ExponentialHeightFog` | fog + Godot-mappable post-process applied; Lumen-only fields logged as unmappable | **wired (9b1a22a)** |
| **Landscape** | 128 `LandscapeComponent`, 128 heightfield collisions, splines, Nanite components | heightmaps + collision + two-weightmap layer blend (`tat_landscape.gdshader`); 210 components across 3 maps (OldManor 128, Startscreen 64, Guildhall 18) now all have real heightmaps/weightmaps, including OldManor_P's 128 (155 PNGs: 101 heightmaps + 54 weightmaps) | **done (fadefa5, 2a8f3d5, 24abf18; `docs/reports/landscape-weightmaps.md`, `docs/reports/visual-polish.md`)** |
| **Packed Level Actors** | 39 `BPP_PL_*` classes, 3,210 instanced components, 30,127 instances | all instances expanded with real `PerInstanceSMData`; Guildhall PeripheryA 3,587 -> 12,594 meshes, collidable; **138 LevelInstances / 32,166 meshes** merged at authored transforms | **done (packed-level-instances)** |
| **Audio** | 5,018 Wwise media chunks + 1,296 event assets | **5,018/5,018 decoded to Ogg** (39,222.2 s, 581,494,198 bytes); 5,862/5,868 event media entries resolved; all 9 gameplay tags wired to verified event/media pairs (`docs/reports/audio-wwise.md`) | **done (2ec9138)** |
| **Tools** | MagicSlime 4 charges / 2 m puddle / 30 s / 10 s slip; smoke 1 ch / 5x5x4 m / 25 s; pickpocket 25 m/9°/0.5 s/4.5 m/s | **implemented** (`50252b5`); projectile flight and player-slip are documented simplifications | **done** |
| **Combat/health** | fall 6.5→23.25 m curve, 10 s downed, 5 s revive, 15/s guard regen | **implemented** (`16edb4e`) with curve-verified damage and a downed countdown | **done** |
| **Blueprints (logic)** | 981 `BP_` + 225 `BPUI_` | all 1,437 dumped; movement/detection/tools/fall/downed/contracts wired | BP graphs still not translatable; **contract sublevels + timers done (1b8db68)** |
| **Spawners** | 689 markers + 546 loot markers + 234 containers | all spawned: real meshes/pickups/civilians (7172096), real loot actors (1c5225f), openable containers (`5bc2d83`) | **done** |
| Skeletal meshes / skins | 156 `SK_` | 156 GLB | guards play 10 real retargeted clips (a29a06f); player uses real 1P arms (9ef3bdc) |
| Player model | `Mesh1P_UpperBody/LowerBody`, `Mesh3P_Body/Head` = ThiefNisha meshes | real ThiefNisha 3P body/head + 1P upper-body arms with Walk/Sprint/Crouch 1P clips | **done (9ef3bdc)** |

## What is already 1:1 (or close)

- **Geometry**: every shipped mesh is a real GLB exported from the install. Guildhall 63,210 runtime instances / Old Manor 19,503 / Thieves' Den 286, with 32 m chunks, real material slots and landscape heightmaps. Packed Level Actors expand their real `PerInstanceSMData` (30,127 instances across 39 `BPP_*` classes), 138 LevelInstance sublevels merge at authored transforms, and Guildhall's packed-city `PeripheryA` is collidable.
- **Materials (albedo/normal/ORM)**: `materials.json` maps 1,272 UE material instances to real textures; glass, wallpaper, wood, brick and stone overrides were derived from those assets.
- **Tuning data**: 141 DataTables/CurveTables/StringTables drive contracts, difficulty, tools, stamina, AI and progression.
- **Lighting positions/colours/intensity**: 3,479 extracted lights (96 loaded per map, brightest 4 shadowed); authored intensity maps linearly (`1/15`, median -> energy `1.0`) and radius is 1:1 in metres. Report: `docs/reports/lighting-intensity.md`; the stealth probe normalizes local lights to the authored median (energy 1.0 -> weight 0.90; suites 36/36b, 2026-11-18).
- **Level layout**: 77 normalized `.tatlevel.json` files feed the loader (meshes, landscapes, lights, markers).

## Gaps and the plan

### A1 — Weather / atmosphere (done)
`TATWorldSettings` → `TATWeatherManager.PresetOverrides` → `BP_WeatherPreset_*`.
Presets carry moon brightness/colour/size, sun brightness, cloud colour/opacity,
`ExponentialHeightFog` density/falloff/inscattering, `SkyLight` intensity/colour/cubemap,
`SkyAtmosphere`, post-process colour grading, rain/wind flag and intensity.
Implemented: `tools/parse_weather.py` → `game/data/generated/weather/*.json`;
applied to Godot `Environment`, moon `DirectionalLight3D`, fog and glow.
The sky/moon follow-up is `docs/reports/sky-moon.md`.

### A2 — Animations (export done; runtime wiring in progress)
`anims` exports 0/1,002 because `AnimationExporter` only supports ActorX/UEFormat/USD.
Implemented: USD export, headless Blender GLB conversion, ACL natives and a manifest
(995 clips, `docs/reports/anims-pipeline-implementation.md`); 14 blend-space graphs
remain unsupported. Runtime `AnimationPlayer` wiring continues.

### A3 — Material fidelity (done, ec9f700)
`MI_`/`M_` JSON contains scalar/vector/texture parameters, blend mode, two-sided,
opacity mask and emissive values. Implemented: `tools/parse_materials.py` resolves
1,552 materials with real scalar/vector/static-switch/blend/two-sided/phys
material values and keeps per-material overrides. Report:
`docs/reports/materials-implementation.md`.

### Hard limit — cooked material graphs
Cooked UE `Material` exports contain **no expression graph and no texture references** (verified: `M_Decal_Puddle` has only BlendMode/flag properties). Textures that live in a material graph are not recoverable from the install; only exposed `TextureParameterValues` on MaterialInstances resolve. Consequence: 667 level decals and some Niagara sprite materials have no trustworthy texture. The runtime must validate material->texture stem matches and skip the rest rather than bind generic fallbacks. A true 1:1 look for those assets would require recreating graphs from reference, which is not in the cooked data.

### A4 — Niagara VFX (catalogue done, runtime constrained)
120 systems catalogued (`tools/parse_vfx.py`, 26f9838): 29 sprite-only, 70 mesh/ribbon, 21 graph-heavy; 139 of 148 renderer materials resolve, but 91 of the 139 carry no texture and only 129 of 456 renderer entries have a real texture. Loop duration is null for all systems; spawn rate, lifetime, velocity and colour curves are computed inside **Niagara VM bytecode**, not stored as values. A 1:1 particle conversion would require decompiling the Niagara VM; the runtime therefore must not invent rates. Level placements (3,692) are extracted so effects can be anchored/activated once a specific system is hand-matched or its bytecode is analysed.

### A4b — Niagara VFX (original)
120 systems dumped (curves/LUTs included). A faithful Niagara graph translation is a
separate project; first extract emitter material, spawn/lifetime/colour parameters, then
drive GPUParticles3D from those values. No fabricated effects.

### A5 — Level component fidelity
The level JSONs contain the missing actors; components from Blueprint actors are
`SimpleConstructionScript` stubs whose templates live in the `BP_*` class JSON.
Resolved for the shipped level content (`e17beae`, `9b1a22a`): `rect_lights`,
`sky_lights`, `decals`, `niagara`, `postprocess` and `volumes` are emitted;
landscape spline/grass data remains unparsed.

**Packed Level Actors are now expanded** (`docs/reports/packed-level-instances.md`):
level stubs with a `Template` ref and no `PerInstanceSMData` resolve the BPP
class template's mesh + instance transforms, so the city blocks no longer
collapse at actor roots. Guildhall `PeripheryA` is collidable (25,074 shapes,
222 bodies) and its 4 `LevelInstance` actors merge the car-underpass /
apartment / storefront sublevels at authored transforms (138 LevelInstances /
32,166 meshes across all maps). Landscape layer weightmaps are also blended by
`tat_landscape.gdshader` (GroundA/GrassA/CobbleA/CobbleB/RockTileA +
Visibility, plus Puddle normal/opacity and GroundWet darkening). Guildhall sets
`discard_holes=0` because the safe-room gap has no lower-floor mesh; the
authored surface fills it. The second weightmap and fifth colour slot shipped
(`fadefa5`, `2a8f3d5`; `docs/reports/landscape-weightmaps.md`): 210/210
components emit `weightmaps`, 15 have two, 8/18 Guildhall components use
`weightmap_1`; the two captured viewpoints showed no measurable pixel delta
(within run-to-run jitter). OldManor_P extracted 2026-11-18 (155 files, suite 38; `docs/reports/visual-polish.md`); remaining A5 work is landscape splines/grass runtime.

### A6 — Gameplay constants (done, f567d23 + 3e0817f)
BP defaults carry the real movement and perception values: player 360/180 cm/s walk/crouch, +90 sprint increment, 550 jump, 91 cm capsule half height, 79.625 cm eye offset; guard 250 cm/s, 25 m sight, 30 m lose-sight, 40° half-FOV, 25 m hearing; `DA_AIStatesToSpeed_Guard` 1.5/1.7 m/s; `DA_DetectionSettings` 0.4 s/m (0.2 alerted) with crouch multiplier. Parsed into `game/data/generated/gameplay/` and wired into the player/guard.

Authored follow-up values (`docs/reports/gameplay-constants.md`): disguise integrity drains `1.0/s` on the timer, `+40.0/s` while sprinting and `+5.0/s` within 1 m of a guard, with `40.0` lost per damage event (`DT_DisguiseV3IntegrityReduction`); XP uses `CT_XPToLevel` (500/1000/2500 per level band) instead of a flat 500; detection decays at `100 / DecayTimeSeconds` (Neutral 1 s, Suspicious 5 s, Alerted/Combat 10 s) behind the authored 6 s in-level and 4 s unseen gates; `Status.Sprinting` x8 ramp; light/speed/height curves. The Godot-only `SEARCH` state decays unconditionally at the 7 s fallback and detection is clamped on downward transitions. Retained: difficulty scaling, `SEARCH` speed, 15/45/100 state thresholds, 3.5 m close-range bypass.

### A9 — Sky and rain (done, dba6988)
- **Real moon panorama**: `game/assets/ue/Raw/Art/Environment/City/Architecture/BeautifulCorner/Materials/T_Moon_D.png` is a 4096x2048 equirectangular lunar panorama (the weather sky material `M_Moon`/`MI_Moon_Base` uses it). `tat_sky.gdshader` now projects it onto the visible hemisphere. `tools/parse_weather.py` walks the Blueprint `Super`/`Template` chain, so `midnight_clear` inherits `moon.visible`, `moon.size`, `moon.emissive` and the HDR sky colours. The disc diameter comes from `SM_Moon` geometry (`2*asin(R*size/D)`): `8.2718°` for `midnight_clear` (`SphereRadius 10771.60558231864 cm` at `1469413 cm`). `sky.overall_color` (`0.001`) multiplies the gradient once, `Environment.fog_sky_affect = 0` keeps the sky visible through fog, and the disc uses the authored emissive tint `[0.5137, 0.5216, 1.0]`. Suite 22 asserts these. Commits: `9f337cf`, `cfd9771`, `48e67c6`, `7ea5d59`, `156999e`, `7e240bb`, `dba6988`; report `docs/reports/sky-moon.md`.
- **Moon planes**: 100 `1m_Plane_Reverse` instances use `MI_MoonshapeEmissive`, which is unlit with `IsMoonshape` but has no texture in the cooked graph; 25 duplicate planes are hidden in Old Manor where the panorama covers them.
- **Rain**: weather presets expose real `enable_rain`/`rain_intensity` and the Niagara asset name (`NS_Rain_WeatherSystem`), but spawn rate/speed live in Niagara VM bytecode. The Godot rain layer is driven by the real flag/intensity with labelled approximate particle parameters; no fake asset claim.

### A8 — Doors and containers
- **Doors done** (`caec0d4`, extended `doors-attachparent`): 281 pivots → 281 doors / 373 leaves / 0 unresolved. The first wave resolved 170 doors / 262 leaves through attached leaf stubs; the follow-up wave resolves the remaining 111 doorway-BP pivots through the pivot component's own template `StaticMesh` (the pivot is a `StaticMeshComponent` subclass), with identity leaf transforms and GLB existence checks. Static meshes stay at 55,452 (no duplicates). Runtime `[F] OPEN/CLOSE` 90°/0.4 s with per-leaf layer-1 collision. Desktop/headless probe: Old Manor 120 doors / 176 rendered leaves, `rot 0.0→1.571`, suite `fails=0`. Evidence: `docs/reports/doors-attachparent.md`, `/tmp/opencode/doors_test.log`.
- **Doors (old note)**: 281 pivots resolve through their parent Blueprint actor (e.g. `BP_Storefront_Facade_1200a_C` instance `StaticMeshActor_10`) to SCS leaf nodes whose `ParentComponentOrVariableName` is `Pivot`/`SecondPivot` (`SM_Urban_Ext_FrontDoorA_Glass`); the pivot carries the real relative transform (`(-500,-70,10)`, yaw -90). Static batches currently contain door leaves (26 `sm_urban_ext_frontdoora_glass`, 60 `sm_urban_ext_door_closed_4x6`, 3 `sm_doorcityexta`), so the door wave (A21) excludes the resolved leaves from `meshes` and spawns them as rotatable pivot nodes with collision.
- **Containers**: 89 `BP_ChestTrunk_MajorLoot`, 68 `BP_DisplayCaseA_MajorLoot`, 57 secret wall stashes, 20 storefront display cases. Each has real meshes (`SM_ChestTrunk`, lid, filler) and a `TATContainerSpawnerComponent` with `SpawnBucket` (major/minor). These are actor markers with real transforms and can be spawned with loot-on-open using A16's loot actor data.
- **Guard patrols**: not recoverable — `BP_AIPatrolPath` has no spline points in the cooked actor; 249 path actors give positions only.

### A7 — Audio
Wwise media are RIFF with codec tag `0xFFFF` (Wwise Vorbis); FFmpeg alone reports "no decoder found", but vgmstream r2168 decodes them. The `1,296` `AkAudioEvent` dumps carry `EventCookedData.EventLanguageMap[].Value.Media[]` with `MediaId`, `DebugName` and `PackagedFile.Hash`.
**Mapping recovered** (`docs/reports/audio-wwise.md`): `tools/extract_audio.py` walks the cooked ubulk with a strict unpadded chunk walk (`5,050` media chunks = `5,018` RIFF + `32` PLUG), and `tools/convert_wwise.py` joins the k-th non-plugin `IsWemFile` entry to the k-th RIFF chunk, validated against `4,160` `SoundSfxVoice` `InMemoryMediaSize` values (`4,155` exact = `99.88%`). All `5,018` clips decode to Ogg under `game/assets/ue/audio/wwise/`; `5,862` of `5,868` event media entries resolve, and all nine gameplay tags are wired to a verified event dump + resolved clip. The `6` unresolved entries are convolution-reverb IRs in PLUG chunks; `51` WEMs are `bStreaming: true` but their chunks are present and decode.

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
- 2026-11-16: loot containers shipped (`5bc2d83`): 234 containers spawn trigger-only Areas at real marker transforms; opening spawns one real loot actor from the mapped bucket; Guildhall 103/103, no duplicated meshes, tests green. Audio extracted (`4742103`): vgmstream r2168 decodes all 3,425 Wwise chunks to Ogg with a library manifest; `AkAudioEvent` event IDs/DebugNames preserved but no chunk↔media map was found at the time (verified 0 MediaId matches, no `.wem`/`.bnk`), so no guessed tag wiring. Spawners shipped (`7172096`): all 689 markers spawn real throwable/ammo/health/civilian content (SM_BottleWineA/B, SM_Toolbox, SM_HealthPackA, SK_CivMale/Female), pickup interactions, bottle distraction throw, civilian wander + MM_Unarmed clips. Contract flow shipped (`1b8db68`): real `SublevelsToLoad` per contract, difficulty match timers (7200/2700/1800, Den 5400/3600/2700, FTUE unlimited), HUD countdown and timeout failure. Loot actors mapped: each BP has a `LootRowHandle` + real mesh (e.g. `SM_PurseA`, `SM_FabergeEggA`) for the next wave. Tool mechanics (`50252b5`) and combat/health (`16edb4e`) shipped with real values; contract-driven sublevels + match timer shipped (`1b8db68`). Character animation shipped: guards retarget 95/97 bones with rest-delta + unit correction and 10 state clips (`a29a06f`); player uses the real ThiefNisha 3P body and 1P arms with Walk/Sprint/Crouch clips (`9ef3bdc`). Level runtime shipped (`9b1a22a`): 347 decals, 138 blocking-volume colliders, 1 active rect light, sky/fog/post-process; niagara placements counted for the VFX wave. Animations shipped (`acd368a`): 995 USD->GLB clips with ACL natives, exact durations, Godot 354-track load check; 14 blend spaces documented. Level components shipped (`e17beae`): 667 decals, 3,692 Niagara placements (0 unresolved), 31 rect lights, 288 volumes, 52 splines, 1 sky/fog/atmosphere; material-graph limit documented. A1 weather shipped (`7aa34db`): 16 presets parsed, map mapping with provenance, fog 0.4 -> 0.004, moon energy/rotation, sky-light ambient, post-process saturation/bloom; suite 17 asserts real preset values. A3 materials shipped (`ec9f700`): 1,552 materials with real roughness/metallic/emissive/static-switch/render flags. A2 animations and A5 level components running.

- 2026-11-16: packed Level Actor instances shipped (`docs/reports/packed-level-instances.md`): level stubs now resolve BPP template `PerInstanceSMData` (39 classes, 3,210 components, 30,127 instances); Guildhall PeripheryA 3,587 -> 10,590 meshes and is collidable; runtime 51,305 meshes / 23,125 shapes; safe-room spawn has 630 meshes within 25 m. Guildhall landscape uses the real `T_RoadBricksA_D/N` street surface named by `MI_Landscape.TextureStreamingData`; `make test` fails=0, `make audit` 99.4%.

- 2026-11-16: landscape layer blend shipped (`tat_landscape.gdshader`): parser emits `WeightmapTextures` + `WeightmapLayerAllocations`; shader blends GroundA/GrassA/CobbleA/CobbleB/RockTileA by channel and discards `LandscapeVisibilityLayerInfo` holes; `Puddle`/`GroundWet` remain skipped. Visual: `/tmp/opencode/qa_weightmap_walk.png`; `make test` fails=0, audit 99.4%.

- 2026-11-16: LevelInstance sublevels shipped: 138 instances / 32,166 meshes merged with `LevelInstanceComponent` transforms; Guildhall PeripheryA 12,594 meshes; car-underpass LevelInstance has 697 meshes near its authored transform; Guildhall runtime 63,210 meshes / 25,074 shapes. Tests suite 20; `make test` fails=0.

- 2026-11-16: Puddle/GroundWet landscape layers: `Puddle` uses the real `T_Decal_Puddle_1_Normal/Opacity` textures plus the authored weightmap channel with a labelled dark-water tint; `GroundWet` darkens albedo and lowers roughness. Shader compiles/renders (`/tmp/opencode/qa_puddle_spawn.png`); `make test` fails=0.

- 2026-11-16: Guildhall visibility-hole fallback: no floor-like mesh within 6 m of the safe-room gap (only foundation walls at y=12); vertical ray hits an overhang at y=25. `discard_holes=0` for Guildhall landscape components so the authored surface fills the gap; suite 21 asserts it. `make test` fails=0.

- 2026-11-16: spawn-area light priority: `_prioritize_lights` puts lights within 25 m of player spawns ahead of the global brightest-96 budget. Guildhall loads the authored safe-room wall `SpotLight3D` at `(126.2948, 27.1426, -2.28)` (energy 4.20 under the old clamp; `cd3590a` now gives `0.333` at the authored `9.0 m` range); suite 10 asserts the light is loaded. `make test` fails=0.

- 2026-11-17: Guildhall safe-room overhang closed (`badf7d5`, `docs/reports/lighting-overhang.md`): the black rectangle was not a visibility hole and not a black mesh — `_dict_to_transform()` clamped `LandscapeComponent` scale `[100,100,100]` to `40.0` (`0.4x`), shrinking `63 m` terrain tiles to `25.2 m` and leaving a `37.8 m` void gap under the alley; `tools/parse_tables.py` now resolves Blueprint `Template` chain transforms/properties for lights so `BP_WallLightB_C_5` aims into the safe room, and `_build_light()` keeps the authored `88` degree outer cone. `make test` fails=0, `make audit` 99.4%.

- 2026-11-17: Wwise audio recovered (`1b78590`, `2ec9138`, `637da18`, `docs/reports/audio-wwise.md`): the unpadded ubulk walk extracts all `5,050` media chunks (`5,018` RIFF + `32` PLUG); an order join validated at `4,155/4,160` `InMemoryMediaSize` matches (`99.88%`) resolves `5,862/5,868` event media entries; `5,018` clips decode and all nine gameplay tags are wired to verified event/media pairs. `make test` fails=0, `make audit` 99.4%.

- 2026-11-17: Overhang wave recorded with a resume point (`f831e17`, `docs/reports/lighting-overhang.md`); the `badf7d5` code fix is logged above.

- 2026-11-17: Sky/moon wave shipped (`9f337cf`, `cfd9771`, `48e67c6`, `7ea5d59`, `156999e`, `7e240bb`, `dba6988`; `docs/reports/sky-moon.md`): preset inheritance + HDR colours, UE rotator -> Godot basis, map resolved before environment, `SM_Moon` geometry gives `8.2718°` for `midnight_clear`, hemisphere panorama projection, `sky.overall_color` (`0.001`) multiplies the gradient, `fog_sky_affect = 0`, authored emissive moon tint; suite 22. `make test` fails=0, `make audit` 99.4%.

- 2026-11-17: Lighting intensity/range wave shipped (`cd3590a`; `docs/reports/lighting-intensity.md`): authored intensity now maps linearly (`1/15`, median -> energy `1.0`, floor `0.01`, ceiling `4.0`) instead of the two-branch clamp that pinned 468/682 Guildhall lights (68.6%); radius is 1:1 in metres (200 m defensive ceiling), attenuation `1.0`, and `_light_score` uses the same mapping. Spawned-set energy is ~41% lower and ranges ~57% shorter; light-probe stealth weights are a parked follow-up. `make test` fails=0, `make audit` 99.4%.

- 2026-11-17: Landscape second weightmap + fifth colour slot shipped (`fadefa5`, `2a8f3d5`; `docs/reports/landscape-weightmaps.md`): all 210 components emit `weightmaps`, 15 have two, Guildhall 8/18; loader binds `weightmap_1`, five colour slots and dedicated visibility/puddle/groundwet indices; shader `weight_at()` returns zero for unknown indices. No measurable pixel delta at the two captured viewpoints (within run-to-run jitter); `OldManor_P`/`BeautifulCorner_Startscreen_P` heightmaps/weightmaps still missing at that time (`OldManor_P` since extracted 2026-11-18 by `24abf18`; `BeautifulCorner_Startscreen_P` extracted 2026-11-17 by `8f07b7d`, 20 PNGs). `make test` fails=0, `make audit` 99.4%.

- 2026-11-17: Gameplay defaults follow-up shipped (`f567d23`, `3e0817f`; `docs/reports/gameplay-constants.md`): disguise integrity rows (`1.0/s` + `40/s` sprint + `5/s` within 1 m, `40` on damage), XP curve `CT_XPToLevel` (500/1000/2500), authored detection decay (`100/20/10/10` per s behind 6 s/4 s gates), `Status.Sprinting` x8 ramp, and the light/speed/height curves; `SEARCH` decays unconditionally at the 7 s fallback and detection is clamped on downward transitions. `make test` fails=0, `make audit` 99.4%.

- 2026-11-18: Visual-fidelity wave (Phases 1–3) shipped (`7458198`..`2da2ebe` + Phase 3 QA/docs; `docs/reports/visual-fidelity.md`):
  - **Phase 1**: `ue_rotator_to_mat3` m12 shear fix + Gram-Schmidt orthonormalization (`7458198`, `146,563` bases); startscreen landscape + `WindowPanels` PNGs (`8f07b7d`, `754bbb6`, `2,261` PNGs, `1,571` materials / `1,367` albedo, 0 map/eye/glass leaks); Overlay/Multiply + `BlackUnlitMaterial` (`7737ed1`); GLB primitive-order `mesh_materials.json` (`6783c2d`, `2,027+18`, `27/27 MATCH`); per-surface `OverrideMaterials` + MID Parent + `BPP_*` overrides + `bVisible:false`/`SplineEditorMesh` filtering (`24cac7e`, 73 clean levels); emissive `CustomPrimitiveData` MultiMesh + `tat_emissive_cpd.gdshader` (`d0f895a`, `1,293` shapes); `tat_glass.gdshader` with authored albedo + opacity map (`123` opacity bindings, `_load_tex` unimported PNG fallback, flat-blue fallback removed, opaque glass preserved; `32d6a52`). Suites 27–33 + red-proofs verified.
  - **Phase 2**: Thieves' Den exit door (`BP_ThievesDenExitDoorInteractable_C` wired into swinging-door path reusing `SM_DoorInaccessibleA`, 0 static duplicates), Den lighting (`7.7 -> 1.90 <= 2.0` hand fills, dark ambient `0.12`, 1 interior `ReflectionProbe`, real `SM_FabergeEggA`/`SM_StatueOwlA`/`SM_HugeJewel` GLBs), footprint decal (`T_Decal_Footstep.png` alpha mask, `emission_enabled=false`), map table (`+0.75` removed, `M_MapBuilding_*` tokens bound; `0361577`); Startscreen `CineCameraActor_0` (`(-12.7196, 0.4566, 14.6089)`, pitch `+13.8°`, vFOV `48.03°`, loader added to tree), Settings teal theme + 6 grouped cards (`ST_Settings.json`) + persisted values wired into `SaveSystem`/`ThiefCharacter`, Mission Prep real location art + `ObjectiveDisplayImage` icons + all 11 `CDT_Missions` rows (`2da2ebe`). Suites 34–35 verified.
  - **Phase 3**: Live Vulkan Forward+ test & visual QA on RTX 4070 (`build/qa/make_test_vulkan_vf.log`, 9 captures in `build/qa/vf_*.png`, `SHADER ERROR = 0`, `SCRIPT ERROR = 0`, `SUMMARY: fails=0` across 35 suites, `make audit` `99.4%`). Compared against 30 official captures in `/home/john/Pictures/Screenshots/` (2 scenes without official reference — Old Manor and Den exit door close-up — skipped comparison and documented). Fixed 720p Mission Prep anchor clipping and `SK_ThiefNisha__Head.glb` +1.45 m offset caught during live capture.

- 2026-11-18: Light-probe stealth retune (`277baba`; `docs/reports/lighting-intensity.md`): probe restores the authored median to weight 0.90 at energy 1.0 (pre-retune 0.35) via `energy * 0.9` clamped to `[0.15, 0.90]`; sub-median rebalance (authored 5 -> 0.30, authored 2.5 -> 0.15 floor); the old 19.9/20.0 dip is removed; suites 36/36b, `make test` fails=0, `make audit` 99.4%.

- 2026-11-18: Visual-polish wave (`3448f82`, `63ea64c`, `1912d04`, `24abf18`; `docs/reports/visual-polish.md`): map tokens `0.08 -> 0.24` (suite 34d), unshaded HDR neon pass (suite 37; retained capture thin tubes `(255,183,101)`/`(255,157,84)`, before red blobs `(254,78,77)`/`(254,57,67)` measured at the time in the discarded run with no artifact retained; earlier `StandardMaterial3D`-emission approach discarded before commit), Mission Prep ThiefNisha PBR (suite 35c), OldManor_P 155 landscape PNGs (suite 38). `make test` 38 suites `fails=0`, `make audit` 99.4% (`29,939` files written); live Vulkan Forward+ captures (`capture_vf.sh`, `capture_mp_only.sh`) `SHADER ERROR = 0`, `SCRIPT ERROR = 0`.

### Visual verification log (desktop, live GPU)

- **Weather blackout** (`cba4cf2`): `Environment.adjustment_brightness` was written as `gain−1` (−0.2) but is a multiplier (default 1.0). Fixed to the gain (0.8 den / 1.1 dense fog) with a suite-17 regression test. Evidence: black `/tmp/opencode/tat_den.png` → working `/tmp/opencode/tat_den_fixed.png`.
- **Spawn yaw** (`90486ef`): authored PlayerStart basis is now applied; Guildhall `rot_y=-175°`, forward dot 1.0. Evidence: `/tmp/opencode/tat_guildhall_yaw.png` (safe-room overlook + moon).
- **Old Manor spawn** (`b06cf8b`): 6 authored starts float outside the playable space; floor-grounded fallback picks `major_loot pos=(17.53,23.49,58.39)`. Evidence: `/tmp/opencode/tat_om_fixed.png`; a follow-up raycast showed the point sits under a low roof (headroom wave A23).
- **Doors** (`caec0d4`): 281 pivots → 170 doors / 262 leaves / 111 unresolved; static meshes −246; probe `rot 0.0→1.570796`; suite green. Evidence: `/tmp/opencode/make_test_final.log`.
- **HUD hotbar** (`e2a61aa`): opaque `T_Ability_Background/Border` mask textures covered the icons; now StyleBox slots + real icons. Evidence: `/tmp/opencode/tat_hotbar.png` shows `[1] Sap / [2] Smoke / [3] Fairy / [G] Ability` (counts 4/1/999/4).
- **Sky/rain** (`a801e79`): real gradient/moon shader from weather presets, 25 moonshape planes hidden in Old Manor, weather rain layer. Guildhall shows the moon and authored sky (`/tmp/opencode/tat_guildhall_yaw.png`).
- **Title + forward clearance** (`0729e90`): missing string-table titles render as `Contract N — <quest item>` (contract 3 = `Contract 3 — Mary Elway's Papers`); fallback spawns require floor + 2.2 m headroom + 1.5 m forward clearance. Verified: Old Manor `source=major_loot`, `headroom_clear=true forward_clear=true`, on floor, `fails=0`. Evidence: `/tmp/opencode/final_title_spawn_test.log`.
- **Open visual items**: Old Manor fallback headroom verified (`05f8657`: same marker, 2.2 m column clear); a forward ray still hits the porch 10–13 m ahead, so A24 adds forward-clearance scoring. The 111 doorway-BP pivots are resolved through their own template `StaticMesh` (`docs/reports/doors-attachparent.md`); Guildhall periphery building fragments (authored periphery geometry), `Contract.Main3` HUD title fallback, and the blank-free hotbar are confirmed.
- **Visual-fidelity wave live Vulkan QA (2026-11-18)**: Verified on `NVIDIA GeForce RTX 4070 Laptop GPU` (`Vulkan 1.4.357 - Forward+`, `SHADER ERROR = 0`, `SCRIPT ERROR = 0`, 35 suites `fails=0`). Captures in `build/qa/vf_*.png` (`vf_startscreen.png`, `vf_settings.png`, `vf_mission_prep.png`, `vf_thieves_den.png`, `vf_thieves_den_map_table.png`, `vf_thieves_den_exit_door.png`, `vf_guildhall.png`, `vf_guildhall_street.png`, `vf_old_manor.png`). The three follow-ups are now resolved by the polish wave (preview PBR, token scale `0.08 -> 0.24`, neon bloom via `tat_hdr_emissive.gdshader`); residual: Startscreen ambient/exposure difference and neon core slightly more saturated than UE's pale gold. See `docs/reports/visual-polish.md`.
- **Visual-polish wave (2026-11-18)**: `3448f82` (map tokens `0.08 -> 0.24`, suite 34d), `63ea64c` (unshaded HDR neon pass `tat_hdr_emissive.gdshader`, suite 37; retained capture thin tubes `(255,183,101)`/`(255,157,84)`, before red blobs `(254,78,77)`/`(254,57,67)` measured at the time in the discarded run with no artifact retained; earlier `StandardMaterial3D`-emission approach discarded before commit), `1912d04` (Mission Prep ThiefNisha PBR, suite 35c), `24abf18` (OldManor_P 155 landscape PNGs, suite 38). `make test` 38 suites `SUMMARY: fails=0`, zero `SCRIPT ERROR`; `make audit` `12,630/12,704 (99.4%)`, `29,939` files written. Live Vulkan Forward+ (`bash build/qa/capture_vf.sh`, `bash build/qa/capture_mp_only.sh`, `SHADER ERROR = 0`, `SCRIPT ERROR = 0`): `vf_mission_prep.png` (authored blue top/dark trousers/skin/hair), `vf_old_manor.png` (landscape builds, `runtime build=1`, renders cleanly; terrain walk/collision not verified), `vf_map_tokens_024.png` (0.24 tokens). Full report: `docs/reports/visual-polish.md`.
