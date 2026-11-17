# TAT-2 — Next Session Handoff (2026-11-16)

Repo: `/home/john/Projects/TAT-2` · Godot `4.7.2.stable.flathub` (Forward+/Jolt) · game project in `game/`.
Source of truth: `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/` (extracted to `extracted/`, 4.7 GB).

## Read first

1. `docs/FIDELITY_GAPS.md` — live coverage tracker + hard limits (start here).
2. `docs/ARCHITECTURE.md` — pipeline/module map; `docs/PERFORMANCE.md` — batching/culling numbers.
3. `docs/reports/*.md` — one report per wave (weather, materials, anims, doors, spawns, audio, …).
4. `HANDOFF_DEEPSEEK.md` — original brief (historical; superseded by this file).

## Verification (run these first)

```bash
make test     # 20 suites, must be SUMMARY: fails=0, zero SCRIPT ERROR
make audit    # manifest coverage, currently 99.4%
make run      # desktop client; F3 overlay for FPS/draws/nodes
```

Last verified: **20/20 PASS, fails=0, zero SCRIPT ERROR**. Engine exit-time `ObjectDB/RID leaked` warnings after `SUMMARY` are pre-existing harness noise, not script errors.

## Repo / branch state

- Branch `main`; remote `origin` configured. `build/` is gitignored; `extension_api.json` is a pre-existing untracked dump — leave it.
- Do not commit `build/`, `game/.godot/`, or generated data under `game/data/generated/` (gitignored by convention but present on disk).
- Android internal build pipeline is separate: `docs/ANDROID.md` (`make android-release`), keystore at `~/.config/tat2/` (never commit).

## What is done (verified)

### Extraction / asset pipeline
- CUE4Parse extractor (`tools/tat-extract`) over `TAT/Content`: 13,162 packages, 2,045 GLB meshes, 2,227 PNG textures, 107 level dumps, 141 tables, 1,437 Blueprint/material-graph dumps.
- **995 animation GLBs** (`game/assets/ue/Anims/...`, `game/data/generated/anims_manifest.json`) via USD + headless Blender (`tools/usd_to_gltf.py`); ACL natives built for Linux (`tools/tat-extract/native/linux-x64/`). 14 `UBlendSpace` graphs unsupported (parametric, not keyframed).
- **Weather**: 16 `BP_WeatherPreset_*` -> `game/data/generated/weather/` with map provenance; applied to Environment/moon/fog/post-process; real 4096x2048 moon panorama `T_Moon_D.png` drives the sky shader; weather rain.
- **Materials**: 1,552 materials with real scalar/vector/static-switch/blend/two-sided/phys material (`tools/parse_materials.py`); art-direction overrides preserved.
- **Audio**: **5,018 Wwise media chunks** decoded to `game/assets/ue/audio/wwise/<ubulk-offset>.ogg` (vgmstream r2168, 39,222.2 s, 581,494,198 bytes); `audio_library.json` + `audio_events.json`. The strict unpadded ubulk walk (`5,018` RIFF + `32` PLUG) plus an order join validated at `4,155/4,160` `InMemoryMediaSize` matches (`99.88%`) resolves `5,862/5,868` event media entries, and all nine gameplay tags are wired to verified event/media pairs. Report: `docs/reports/audio-wwise.md`.

### Runtime
- Level loader: 32 m XZ chunking with tight custom AABB, tiered distance culling/shadows, occlusion boxes, per-cell collision bodies, skybox-only decorative exclusion (packed-city PeripheryA is collidable).
- **Packed Level Actors + LevelInstances**: 39 `BPP_PL_*` classes / 3,210 instanced components / 30,127 `PerInstanceSMData` transforms expanded; 138 LevelInstance sublevels / 32,166 meshes merged at authored transforms. Guildhall PeripheryA 12,594 meshes; runtime 63,210 meshes / 25,074 collision shapes. Guildhall landscape uses `tat_landscape.gdshader` to blend the real weightmap layers (GroundA/GrassA/CobbleA/CobbleB/RockTileA + Visibility, Puddle normal/opacity, GroundWet darkening); Guildhall sets `discard_holes=0` because the safe-room gap has no lower-floor mesh. Spawn-area lights within 25 m are prioritized over the global brightest-96 budget; the safe-room wall `SpotLight3D` at `(126.2948, 27.1426, -2.28)` is loaded (energy 4.20). Report: `docs/reports/packed-level-instances.md`.
- Level content: 347 validated decals, 138 blocking-volume colliders, 1 active rect light, 1 sky/fog/atmosphere, 3,692 Niagara placements counted (not spawned), 52 splines skipped (editor mesh).
- Spawns: all 689 throwable/ammo/health/civilian markers with real meshes/pickups/civilians; 546 loot actors with real meshes/table values; 234 openable containers (real loot on open); **170 swinging doors / 262 leaves** (90° open/close, rotating collision; 111 unresolved window/doorway hinges counted).
- Characters: guards play 10 retargeted real clips (95/97 bones, rest-delta + unit correction); player uses real ThiefNisha 3P body and 1P arms with real Walk/Sprint/Crouch clips (procedural fallback).
- Gameplay data: real movement (3.6 walk / 1.8 crouch / 5.4 sprint / 5.5 jump, 1.66875/0.88875 m eyes, FOV 85, gravity 9.8), guard speeds 1.5/1.7/2.5, 20 m sight / 80° FOV / 25 m hearing, distance detection ramp, MagicSlime puddle (2 m/30 s/10 s slip/inhibitor 1.5 m/30 s), 5x5x4 smoke box, pickpocket cone, fall damage 6.5→23.25 m, 10 s downed, 5 s revive, 15/s regen, contract sublevels + difficulty timers (7200/2700/1800, Den 5400/3600/2700, FTUE 0).
- Spawn quality: authored PlayerStart yaw applied; floor-grounded fallback across markers with headroom + forward-clearance checks; `TAT-2 player spawn: source=... headroom_clear=... forward_clear=...` log.
- HUD: real tool icons (StyleBox slots), F3 overlay, timer countdown, downed countdown, mobile touch layer (`docs/ANDROID.md`).
- Contract titles: missing string-table titles fall back to `Contract N — <quest item>` (e.g. `Contract 3 — Mary Elway's Papers`).
- Guildhall safe-room overhang: closed in `badf7d5`. Landscape component scale is no longer clamped to `0.4x` (63 m tiles stay 63 m, closing the 37.8 m void gap under the alley), wall lights resolve their Blueprint `Template` chain transforms so `BP_WallLightB_C_5` aims into the safe room, and the authored `88` degree spot cone is preserved. Report: `docs/reports/lighting-overhang.md`.

## Key commits (most recent first)

```
badf7d5 fix(landscape,lighting): restore 1:1 landscape scale and BP light SCS transforms
d802c25 feat(level): expand packed Level Actor instances and real street surface
33fd935 feat(doors): resolve 111 doorway pivots from their own leaf mesh
0729e90 fix(gameplay): contract title fallback and forward-clear spawn selection
caec0d4 feat(doors): real swinging doors end-to-end from authored pivots
e2a61aa fix(hud): render tool hotbar icons over translucent panel slots
05f8657 fix(spawn): score all fallback markers with headroom and capsule checks
b06cf8b fix(spawn): fall back to mission markers when authored starts have no floor
90486ef fix(spawn): honour authored PlayerStart orientation on mission spawn
cba4cf2 fix(weather): map gain_midtones to adjustment_brightness multiplier (0..2)
a801e79 feat(sky): real night sky from weather presets plus weather-driven rain
5bc2d83 feat(loot): openable loot containers grant real loot from mapped buckets
1c5225f feat(loot): spawn real loot actors at mission loot-spawner markers
7172096 feat(spawners): spawn real map pickup, bottle and civilian content
1b8db68 feat(contracts): resolve sublevel lists and match timers from extracted tables
16edb4e feat(combat): real fall damage, downed state, revive timing and guard regen
50252b5 feat(tools): real MagicSlime, smoke and pickpocket mechanics
acd368a feat(anims): USD animation export with ACL natives, Blender GLB pipeline
a29a06f feat(anims): retarget real guard clips
9ef3bdc feat(player): real 1P arms and ThiefNisha body
...
```
(`git log --oneline` for the full list.)

## Hard limits (cooked data — do not fake)

1. **Niagara VFX**: 120 systems catalogued (`tools/parse_vfx.py`); spawn rate/lifetime/velocity live in Niagara VM bytecode, loop duration null. No particle rates can be extracted without VM decompilation — do not invent them.
2. **Wwise audio (partial limit)**: the event↔media mapping is recovered (order join, `99.88%` size-validated); `5,018` clips decode and all nine tags are wired. Remaining limit: `6` convolution-reverb IRs are PLUG media that vgmstream cannot decode, and the join is proven by size statistics rather than content hashing (equal-size permutations remain theoretically invisible). See `docs/reports/audio-wwise.md`.
3. **Material graphs**: cooked `Material` assets have no expressions/textures. Only exposed MaterialInstance parameters/textures resolve. 667 decals -> 347 validated (112 skipped); some VFX materials have no texture. A true 1:1 look for graph-only textures requires reference recreation, not extraction.
4. **Blueprint / QuestGraph / patrol**: cooked behaviour graphs are not translated. DataTables/CurveTables and BP defaults are used; patrol spline points don't exist in `BP_AIPatrolPath`.
5. **Doors**: 111 pivots are window/doorway hinges with no SCS leaf child; counted, not faked.
6. **Guildhall periphery** shows authored floating building fragments; **Old Manor** fallback spawn is a covered porch (forward clearance passes but the view is a roof; walking out is required).

## Next steps (priority)

1. **Landscape layers**: the weightmap shader now covers GroundA/GrassA/CobbleA/CobbleB/RockTileA, Puddle normal/opacity and GroundWet; remaining work is layers on a second weightmap texture and the fifth color slot. Verify the blend on Guildhall/Old Manor/Den.
2. **Visual QA pass** in `make run` on Guildhall/Old Manor/Den: sky/moon scale, light beam overbright, Old Manor porch spawn and door visibility. The Guildhall safe-room overhang is closed — see `docs/reports/lighting-overhang.md`.
3. **VFX (optional)**: only if a specific system is hand-matched or Niagara bytecode analysis is undertaken; placements are already extracted. Do not fabricate rates.
4. **Audio (optional)**: mapping recovered and tags wired (`docs/reports/audio-wwise.md`); optional follow-ups are the `6` PLUG convolution-reverb IRs and any additional event/media pins. Never assign unnamed clips to gameplay tags.
5. **Spawn quality**: prefer interior markers with 2–3 m forward clearance; consider QuestGraph/contract spawn tags if discovered.
6. **UI**: remaining title/edge cases, minimap/ledger polish.
7. **Mobile**: rebuild APK after runtime changes (`make android-release`), then measure FPS/thermals on the phone (still unverified on hardware).

## Resume point (2026-11-17)

Sky/moon (M2) research is complete but uncommitted. Five verified defects: (1) `tools/parse_weather.py` never walks Blueprint `Super`/`Template`, so `midnight_clear` (Guildhall's preset per `game/data/generated/weather/map_weather.json`) has `moon.visible`, `moon.size`, `moon.emissive`, `sky.horizon_color` and `sky.cloud_*` null; (2) `_norm_color()` divides the authored HDR `LinearColor` horizon `[1.979559, 2.586644, 3.0]` by 255; (3) `weather_visuals.gd` treats `moon.size` as degrees (`6.0` default) instead of deriving `2*asin(10771.60558231864 * size / 1469413.0)`, which is `8.272` degrees for `midnight_clear`; (4) `weather_profile.gd` copies UE `FRotator` into Godot `rotation_degrees` with no basis conversion; (5) `mission_controller.gd` builds the environment before `active_map_id` is set, so a menu launch applies the Old Manor preset. Baseline before-shot: `/tmp/opencode/sky_moon_before.png` (captured at `badf7d5`).

## QA recipes / gotchas

- **Autostart a contract on desktop**: append to `game/project.godot`:
  ```ini
  [tat2]
  debug_autostart_contract=4
  ```
  run `make run`, wait 40–75 s (Guildhall), screenshot with
  `WID=$(xdotool search --name "Thick As Thieves" | tail -1); xdotool windowactivate --sync $WID; spectacle -b -n -a -o shot.png`,
  then **restore project.godot** (keep a backup). Contract ids: 1 Den, 3 Old Manor, 4 Guildhall, 17/18 expansion.
- **Headless scripts**: `--script` cannot `preload` autoload-referencing scripts (autoloads register after main script compile) — use runtime `load()`.
- Godot 4.7 GDScript: no `:=` on untyped Dictionary/Variant; **never** `bool(Object.get(...))` (throws `Nonexistent 'bool' constructor`) — use `value == true`; `or`/`and` return bool.
- Headless probes: wait for the **doors/guards groups**, not just guards (doors spawn after guards); always `quit()` on every path, redirect output to a file (pipes through `head` lose buffered output), and use a hard `timeout`; otherwise the SceneTree spins.
- Desktop screenshots: `spectacle -b -n -a` captures the active window; activate with `xdotool` first. Avoid full-screen grabs (private content).
- Do not run two mission-load probes concurrently; each Godot load is CPU-heavy.

## Key paths

- `game/src/core/level_loader.gd` — streaming/batching/culling/decals/volumes/doors/loot spawn arrays.
- `game/src/missions/mission_controller.gd` — mission flow, spawns, weather/sky/rain, timers, spawn fallback.
- `game/src/core/weather_profile.gd`, `weather_visuals.gd`, `src/core/tat_sky.gdshader` — atmosphere.
- `game/src/player/thief_character.gd`, `src/ai/guard_ai.gd`, `src/ai/civilian_npc.gd` — actors.
- `game/src/core/animation_library.gd` — GLB animation retargeting.
- `game/src/interact/{world_pickup,loot_item,loot_container,swinging_door,lockable_door}.gd`.
- `tools/parse_{tables,materials,weather,gameplay,interactables,loot,containers,spawners,vfx}.py`, `tools/tat-extract/`, `tools/convert_wwise.py`, `tools/usd_to_gltf.py`.
- `game/tests/run_tests.gd` (20 suites), `docs/reports/`, `docs/FIDELITY_GAPS.md`.

## Engineering conventions

- Never fake assets/parameters: if the cooked data lacks it, count/skip and document.
- Every wave: implement + test + report; run `make test` (`fails=0`, zero SCRIPT ERROR) before commit.
- Use `agency-programmer` for code, `agency-qa` for red-proofs, `agency-drift-guard` for independent verdicts if using the fleet workflow.
- Commit messages follow Conventional Commits; keep generated data out of git.


## Caveats from the title/spawn wave (2026-11-16)

1. **Full suite confirmed**: `make test` was re-run after the change; `/tmp/opencode/final_title_spawn_test.log` shows `SUMMARY: fails=0` and zero `SCRIPT ERROR`. (The subagent's own wait was interrupted by a server restart, so this log is the authoritative run.)
2. **Comment-only edit after the green probe**: a misleading comment in `_fallback_spawn_has_forward_clearance` was corrected after the temp check ran; it is comment-only and behaviorally identical, but strictly the committed file differs from the probe by that comment.
3. **Old Manor spawn is legitimately unchanged**: contract 3 still picks the first major-loot candidate `(17.5346, 23.4871, 58.3921)` because it passes floor + 2.2 m headroom + 1.5 m forward clearance (forward ray: no hit in 3 m). No `fallback_no_forward_clearance` fired — evidence, not a forced relocation.
4. **Forward check is vacuously true with no centroid**: `_fallback_spawn_has_forward_clearance` returns true when `_loot_centroid` is null or the direction is degenerate (nothing to face). By design; not a gap.
5. **Contract 1 titles as `Contract 1`**: it has no contract string table, so the fallback's last branch fires. Expected; visible only if the HUD lists it as a contract (the Den HUD shows `Contract #1`).
6. **Never commit `extension_api.json`**: it is a pre-existing untracked Godot API dump; only source/docs belong in commits.
