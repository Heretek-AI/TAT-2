# TAT-2 — Next Session Handoff (2026-11-17)

Repo: `/home/john/Projects/TAT-2` · Godot `4.7.2.stable.flathub` (Forward+/Jolt) · game project in `game/`.
Source of truth: `/home/john/.local/share/Steam/steamapps/common/Thick As Thieves/` (extracted to `extracted/`, 4.7 GB).

## Read first

1. `docs/FIDELITY_GAPS.md` — live coverage tracker + hard limits (start here).
2. `docs/ARCHITECTURE.md` — pipeline/module map; `docs/PERFORMANCE.md` — batching/culling numbers.
3. `docs/reports/*.md` — one report per wave (weather, materials, anims, doors, spawns, audio, …).
4. `HANDOFF_DEEPSEEK.md` — original brief (historical; superseded by this file).

## Verification (run these first)

```bash
make test     # 26 numbered suites, must be SUMMARY: fails=0, zero SCRIPT ERROR
make audit    # manifest coverage, currently 99.4%
make run      # desktop client; F3 overlay for FPS/draws/nodes
```

Last verified (2026-11-17, HEAD `3e0817f`): **26 numbered suites, fails=0, zero SCRIPT ERROR** (`/tmp/opencode/final_test.log`); `make audit` **12,630 / 12,704 (99.4%)**. Engine exit-time `ObjectDB/RID leaked` warnings after `SUMMARY` are pre-existing harness noise, not script errors.

## Repo / branch state

- Branch `main`; remote `origin` configured. `build/` is gitignored; `extension_api.json` is a pre-existing untracked dump — leave it.
- Do not commit `build/`, `game/.godot/`, or generated data under `game/data/generated/` (gitignored by convention but present on disk).
- Android internal build pipeline is separate: `docs/ANDROID.md` (`make android-release`), keystore at `~/.config/tat2/` (never commit).

## What is done (verified)

### Extraction / asset pipeline
- CUE4Parse extractor (`tools/tat-extract`) over `TAT/Content`: 13,162 packages, 2,045 GLB meshes, 2,227 PNG textures, 107 level dumps, 141 tables, 1,437 Blueprint/material-graph dumps.
- **995 animation GLBs** (`game/assets/ue/Anims/...`, `game/data/generated/anims_manifest.json`) via USD + headless Blender (`tools/usd_to_gltf.py`); ACL natives built for Linux (`tools/tat-extract/native/linux-x64/`). 14 `UBlendSpace` graphs unsupported (parametric, not keyframed).
- **Weather / sky / moon**: 16 `BP_WeatherPreset_*` -> `game/data/generated/weather/` with map provenance; the parser walks the Blueprint `Super`/`Template` chain so child presets inherit authored values, and HDR `LinearColor` is preserved. Applied to Environment/moon/fog/post-process; `T_Moon_D.png` is hemisphere-projected by `tat_sky.gdshader`; `midnight_clear` moon diameter is `8.2718°` from `SM_Moon` geometry (`10771.60558231864 cm` at `1469413 cm`); `sky.overall_color` (`0.001`) multiplies the gradient; `fog_sky_affect = 0`; the disc uses the authored emissive tint. Report: `docs/reports/sky-moon.md`.
- **Materials**: 1,552 materials with real scalar/vector/static-switch/blend/two-sided/phys material (`tools/parse_materials.py`); art-direction overrides preserved.
- **Audio**: **5,018 Wwise media chunks** decoded to `game/assets/ue/audio/wwise/<ubulk-offset>.ogg` (vgmstream r2168, 39,222.2 s, 581,494,198 bytes); `audio_library.json` + `audio_events.json`. The strict unpadded ubulk walk (`5,018` RIFF + `32` PLUG) plus an order join validated at `4,155/4,160` `InMemoryMediaSize` matches (`99.88%`) resolves `5,862/5,868` event media entries, and all nine gameplay tags are wired to verified event/media pairs. Report: `docs/reports/audio-wwise.md`.

### Runtime
- Level loader: 32 m XZ chunking with tight custom AABB, tiered distance culling/shadows, occlusion boxes, per-cell collision bodies, skybox-only decorative exclusion (packed-city PeripheryA is collidable).
- **Packed Level Actors + LevelInstances**: 39 `BPP_PL_*` classes / 3,210 instanced components / 30,127 `PerInstanceSMData` transforms expanded; 138 LevelInstance sublevels / 32,166 meshes merged at authored transforms. Guildhall PeripheryA 12,594 meshes; runtime 63,210 meshes / 25,074 collision shapes. Guildhall landscape uses `tat_landscape.gdshader` to blend the real weightmap layers across two weightmaps and five colour slots (GroundA/GrassA/CobbleA/CobbleB/RockTileA + Visibility, Puddle normal/opacity, GroundWet darkening); 210/210 components emit `weightmaps`, 15 have two, Guildhall 8/18; Guildhall sets `discard_holes=0` because the safe-room gap has no lower-floor mesh. Spawn-area lights within 25 m are prioritized over the global brightest-96 budget; the safe-room wall `SpotLight3D` at `(126.2948, 27.1426, -2.28)` is loaded (energy `0.333`, authored range `9.0 m`). Reports: `docs/reports/packed-level-instances.md`, `docs/reports/landscape-weightmaps.md`.
- **Lighting intensity/range**: authored `Intensity` maps linearly (`1/15`; median `15` -> energy `1.0`, floor `0.01`, ceiling `4.0`) instead of the old two-branch clamp that pinned 468/682 Guildhall lights (68.6%); attenuation radius is 1:1 in metres with a 200 m defensive ceiling, attenuation `1.0`, and the 96-light budget ranking uses the same scale. Spawned-set energy is ~41% lower and ranges ~57% shorter; the light-probe stealth weights are still tuned to the old values (parked follow-up). Report: `docs/reports/lighting-intensity.md`.
- Level content: 347 validated decals, 138 blocking-volume colliders, 1 active rect light, 1 sky/fog/atmosphere, 3,692 Niagara placements counted (not spawned), 52 splines skipped (editor mesh).
- Spawns: all 689 throwable/ammo/health/civilian markers with real meshes/pickups/civilians; 546 loot actors with real meshes/table values; 234 openable containers (real loot on open); **281 swinging doors / 373 leaves** (90° open/close, rotating collision; 111 doorway-BP pivots counted, 0 unresolved). Report: `docs/reports/doors-attachparent.md`.
- Characters: guards play 10 retargeted real clips (95/97 bones, rest-delta + unit correction); player uses real ThiefNisha 3P body and 1P arms with real Walk/Sprint/Crouch clips (procedural fallback).
- Gameplay data: real movement (3.6 walk / 1.8 crouch / 5.4 sprint / 5.5 jump, 1.66875/0.88875 m eyes, FOV 85, gravity 9.8), guard speeds 1.5/1.7/2.5, 20 m sight / 80° FOV / 25 m hearing, distance detection ramp, authored disguise integrity (`1.0/s` timer + `40/s` sprint + `5/s` within 1 m; `40` on damage), XP curve (`CT_XPToLevel`: 500/1000/2500 per level band), detection decay (`100/20/10/10` per s behind 6 s/4 s gates; Godot-only `SEARCH` at the 7 s fallback; downward transitions clamp to the 15/45/100 entry ceilings), `Status.Sprinting` x8 ramp, light/speed/height curves, MagicSlime puddle (2 m/30 s/10 s slip/inhibitor 1.5 m/30 s), 5x5x4 smoke box, pickpocket cone, fall damage 6.5→23.25 m, 10 s downed, 5 s revive, 15/s regen, contract sublevels + difficulty timers (7200/2700/1800, Den 5400/3600/2700, FTUE 0). Report: `docs/reports/gameplay-constants.md`.
- Spawn quality: authored PlayerStart yaw applied; floor-grounded fallback across markers with headroom + forward-clearance checks; `TAT-2 player spawn: source=... headroom_clear=... forward_clear=...` log.
- HUD: real tool icons (StyleBox slots), F3 overlay, timer countdown, downed countdown, mobile touch layer (`docs/ANDROID.md`).
- Contract titles: missing string-table titles fall back to `Contract N — <quest item>` (e.g. `Contract 3 — Mary Elway's Papers`).
- Guildhall safe-room overhang: closed in `badf7d5`. Landscape component scale is no longer clamped to `0.4x` (63 m tiles stay 63 m, closing the 37.8 m void gap under the alley), wall lights resolve their Blueprint `Template` chain transforms so `BP_WallLightB_C_5` aims into the safe room, and the authored `88` degree spot cone is preserved. Report: `docs/reports/lighting-overhang.md`.

## Key commits (most recent first)

```
3e0817f feat(ai): port authored detection decay, sprint ramp and light curves
f567d23 feat(gameplay): port authored disguise integrity and XP curve
637da18 docs(audio): record wwise recovery and correct stale limits
2ec9138 feat(audio): wire verified event clips to gameplay tags
1b78590 feat(audio): recover wwise event to media mapping from unpadded ubulk
2a8f3d5 feat(landscape): bind second weightmap and fifth colour slot
fadefa5 feat(landscape): emit all weightmap textures per component
cd3590a fix(lighting): preserve authored intensity ratios and attenuation radii
dba6988 fix(sky): restore authored night sky visibility and moon tint
7e240bb test(sky): assert inherited presets, moon geometry and map resolution
156999e fix(sky): project the moon panorama onto the visible hemisphere
7ea5d59 fix(sky): derive moon diameter from SM_Moon geometry and tone-map HDR horizon
48e67c6 fix(weather): resolve map id before building the environment
cfd9771 fix(weather): convert UE moon-light rotator to a Godot basis
9f337cf fix(weather): inherit blueprint preset chain and preserve HDR colours
f831e17 docs: record overhang wave and resume point
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

1. **Niagara VFX (blocked)**: 120/120 systems catalogued (`tools/parse_vfx.py`), but spawn rate/lifetime/velocity live in compiled VectorVM bytecode and loop duration is null for all of them; 91 of the 139 resolved renderer materials carry no texture. No particle rates can be extracted without VM decompilation — do not invent them, and do not claim the runtime VFX wave is done.
2. **Wwise audio (partial limit)**: the event↔media mapping is recovered (order join, `99.88%` size-validated); `5,018` clips decode and all nine tags are wired. Remaining limit: `6` convolution-reverb IRs are PLUG media that vgmstream cannot decode, and the join is proven by size statistics rather than content hashing (equal-size permutations remain theoretically invisible). See `docs/reports/audio-wwise.md`.
3. **Material graphs**: cooked `Material` assets have no expressions/textures. Only exposed MaterialInstance parameters/textures resolve. 667 decals -> 347 validated (112 skipped); some VFX materials have no texture. A true 1:1 look for graph-only textures requires reference recreation, not extraction.
4. **Blueprint / QuestGraph / patrol**: cooked behaviour graphs are not translated. DataTables/CurveTables and BP defaults are used; patrol spline points don't exist in `BP_AIPatrolPath`.
5. **Doors**: 111 pivots are window/doorway hinges with no SCS leaf child; counted, not faked.
6. **Guildhall periphery** shows authored floating building fragments; **Old Manor** fallback spawn is a covered porch (forward clearance passes but the view is a roof; walking out is required).

## Next steps (priority)

1. **Retune the light-probe stealth weights** for the new lighting energies. `game/src/stealth/light_probe.gd` still contributes `falloff² * clamp(light_energy * 0.35, 0.15, 0.9)` and skips lights at `<= 0.01`; it was tuned when median lights saturated at `4.2`, but the median is now `1.0`, so visibility (and detection via `vis_mult`) near those lights is roughly halved. See the "Stealth detection is now mis-tuned" section of `docs/reports/lighting-intensity.md`.
2. **Fix the `tools/parse_tables.py:65` m12 shear** (4,444 mesh instances). The term is not the negated form used by `weather_profile.gd`; see the `docs/reports/sky-moon.md` caveat. This is a geometry-correctness bug, not a visual tweak.
3. **Extract the missing landscape PNGs for `OldManor_P` / `BeautifulCorner_Startscreen_P`**. `tools/tat-extract/Exporter.cs:166` only exports `.umap` textures whose package path contains `"Landscape"`, so 128 + 64 components have no heightmaps/weightmaps (263 + 128 referenced PNG paths missing) and are not built. Counted, not faked; see `docs/reports/landscape-weightmaps.md`.
4. **Niagara VFX remains blocked**. 120/120 systems use compiled VectorVM bytecode for spawn/lifetime/velocity and 91/139 resolved materials carry no texture. Only hand-match a specific system or decompile the VM; do not invent rates. Placements are already extracted.
5. **Visual QA pass** in `make run` on Guildhall/Old Manor/Den: confirm the implemented sky/moon (`8.2718°` disc, near-black gradient, stars, authored tint), the new lighting energies/ranges, the landscape blend, and door/spawn visibility. This is verification, not pending implementation.
6. **Spawn quality / UI / mobile**: prefer interior markers with 2–3 m forward clearance and consider QuestGraph/contract spawn tags; remaining title/edge cases and minimap/ledger polish; rebuild the APK after runtime changes (`make android-release`) and measure FPS/thermals on hardware.

## Resume point (2026-11-17, HEAD `3e0817f`)

All waves listed above are committed and green; there is no uncommitted source work to recover. Start with the light-probe retune (item 1), then the `parse_tables.py:65` m12 shear and the missing `OldManor_P` / `BeautifulCorner_Startscreen_P` landscape PNGs. Niagara VFX stays blocked. Re-run `make test` (26 numbered suites, `SUMMARY: fails=0`, zero `SCRIPT ERROR`) and `make audit` (99.4%) after each change.

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
- `game/src/stealth/light_probe.gd`, `game/src/core/save_system.gd` — authored light/speed curves and XP progression.
- `game/src/core/animation_library.gd` — GLB animation retargeting.
- `game/src/interact/{world_pickup,loot_item,loot_container,swinging_door,lockable_door}.gd`.
- `tools/parse_{tables,materials,weather,gameplay,interactables,loot,containers,spawners,vfx}.py`, `tools/tat-extract/`, `tools/convert_wwise.py`, `tools/usd_to_gltf.py`.
- `game/tests/run_tests.gd` (26 suites), `docs/reports/`, `docs/FIDELITY_GAPS.md`.

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

## Session log (2026-11-17) — post-overhang fidelity resume

Shipped 20 plan tasks in 17 commits, tree clean at `1a753da`. Each wave ran `make test` (fails=0, zero SCRIPT ERROR) and `make audit` (99.4%): sky/moon (`9f337cf`..`dba6988`), lighting (`cd3590a`), landscape (`fadefa5`, `2a8f3d5`), audio (`1b78590`, `2ec9138`), gameplay defaults (`f567d23`, `3e0817f`), docs (`1a753da`). One report per wave under `docs/reports/`.

### Operational caveats (read before starting work)

- The swarm plan tracker (`.swarm/plan.md`) shows every task as PENDING and is wrong: `update_task_status` needs a `pre_check` gate that only an accepted coder settlement can write. Git history is the accurate record.
- The swarm coder lane is unusable in this environment. `SCOPE_BINDING_EXPIRED` ("generation for this task expired while idle") fires before the coder's first write; the lease is hard-coded (~2 min) with no published schema key. A session restart and `worktree.policy: disabled` did not clear it. Workaround used and recommended: delegate implementation to general-purpose write agents, run Stage A yourself (`diff` + `pre_check_batch`), and require an independent fresh-context review per task plus real `make test`/`make audit` output before committing.
- Headless `make test` does NOT compile GLSL (Godot's dummy renderer). Shader changes need a real-renderer run (`--rendering-driver vulkan` under Xvfb) or a live capture; both were used this session and caught two defects the tests could not.
- Visual QA writes to `build/qa/` (gitignored), not `/tmp/opencode/` — that path was wiped mid-session.

### Parked follow-ups (priority order)

1. `tools/parse_tables.py:65` negates UE's `M[2][1]`, shearing 4,444 mesh instances. Fix + regenerate + re-verify positions in the suites.
2. Light-probe stealth weights were tuned against the old inflated light energies; retune after the lighting wave.
3. OldManor_P / BeautifulCorner_Startscreen_P landscape heightmaps and weightmaps were never extracted (`tools/tat-extract/Exporter.cs:166` filters on "Landscape").
4. Niagara VFX still blocked on compiled VectorVM bytecode (120/120 systems).
