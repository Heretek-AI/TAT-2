# T12-VFX — Niagara / visual effects remediation

Team: T12-VFX (wave 5). Branch `rem/T12-vfx`, worktree
`<worktree>/T12-vfx`, base `fb93f84`. Never pushed, merged,
rebased or cherry-picked. No producer was run and `game/data/generated/` was not
written: all new runtime data comes from files that already existed
(`systems.json`, `materials.json`, `levels/**`, `extracted/json/**`).

Scope owned and touched: the VFX functions of `game/src/core/level_loader.gd`
(`_spawn_level_niagara`, `_niagara_param_colour`, `_authored_flame_near`, the
candle wick branch of `_parse_sublevel_file`, the four Niagara result keys in
`_finalize`), `game/src/core/level_niagara.gdshader`, `game/tests/probe_niagara.gd`,
new files under `game/src/core/vfx/`, the four QA-only builders and the footstep
decal in `game/src/core/vfx_manager.gd`, the two E2E guards that named
`VectorVM`, and the two review-baker lines that equated systems with nodes.

Note: the brief names `game/src/core/shaders/level_niagara.gdshader`; the file
actually lives at `game/src/core/level_niagara.gdshader` (no `shaders/` dir).
No file was moved.

## Team summary

| verdict | count | findings |
|---|---|---|
| FIXED | 8 | RE-E-02 (sprite/composer consumer), RE-E-03 (activation), RE-E-04 (parameter decode), RE-E-05 (probe + E2E guard), RE-E-09 (candle double spawn), RE-E-10 (placement scale), RE-E-11 (footprint decal), RE-E-14 (culling) |
| FIXED (relabel) | 1 | RE-E-08 (four QA-only builders: labelled probe-only, not wired) |
| CORRECTED (doc/data claim) | 3 | RE-E-01 (name join, `NE_*` uncatalogued), RE-E-04's "1,044 self-describing", RE-E-15 |
| NOT REPRODUCED | 0 | — |
| BLOCKED-ON T01 | 2 | `systems.json.parameter_defaults` note and the activation/parameter fields need a producer run (`parse_vfx.py`); consumer is committed and ready |
| DEFERRED | 2 | RE-E-06 (VM bytecode interpreter), RE-E-12 (puddle look), RE-E-13 (emission values) — out of VFX-file scope or a genuine research project |

## Red-proof commands (all run on this tree, headless, no GPU)

```
tools/godot --headless --path game --script "$PWD/tools/check_scripts_compile.gd"
tools/godot --headless --path game --script res://tests/probe_niagara.gd
tools/godot --headless --path game --script res://tests/probe_niagara.gd -- --verify-activation
make test
tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd
```

---

## RE-E-02 — the catalogue and the resolved sprite had zero runtime readers

- severity: P0
- S1 investigate: `level_loader.gd:5135-5199` built `QuadMesh` → `MultiMesh` →
  `ShaderMaterial(level_niagara.gdshader)` with two uniforms (`tint`, `base_size`)
  picked by substring-matching the asset name (`_niagara_tint`,
  `_niagara_size`). `grep -rn "systems.json" game/src/` → 0 hits. The shader
  (`level_niagara.gdshader:1-32`) had no `sampler2D`: `ALBEDO` came from a
  radial `core*core` gradient.
- S2 research: `game/data/generated/vfx/systems.json` (tools/parse_vfx.py)
  already resolves each renderer to a material and, for 270 of 456 renderer
  entries across 85 systems, to a sprite PNG. `materials.json` carries the
  authored material vectors. Both are generated and present.
- S3 confirm (red): before this change the probe printed only counts, and a
  `node.material_override` inspection had nothing to inspect — every material
  had exactly `tint` + `base_size` and no `sprite_tex`:
  `NIAGARA_PROBE files=107 authored=3695 active=3308 skipped=387 systems=36 nodes=36`
  with 0 sampler bindings.
- S4 fix:
  - new `game/src/core/vfx/niagara_library.gd` — loads `systems.json` once,
    keys systems by a case/underscore-insensitive name (fixes the
    `NS_Fireplace`/`NS_FirePlace` join), and returns per system the resolved
    sprite path, sprite/texture counts, authored material colour and a base size
    band by authored complexity class.
  - new `game/src/core/vfx/sprite_masks.gd` — the measured soft-mask table (see
    "Sprite mask measurement") so only a texture that is actually a sprite is
    sampled; an opaque atlas page stays on the gradient.
  - `level_niagara.gdshader` — real `sampler2D sprite_tex`, `use_sprite`,
    `INSTANCE_CUSTOM` per-instance tint, per-instance XY scale from the instance
    basis, one global `hdr_gain`; the gradient is the documented fallback.
  - `_spawn_level_niagara` sets `sprite_tex`/`use_sprite` from the library and
    records `niagara_sprites`.
- S5 test: `probe_niagara.gd` asserts every system whose measured mask is usable
  binds a non-null `sprite_tex` with `use_sprite == true`, that no other system
  binds one, and that the count equals 5. E2E T2-06-A/T4-12 now assert the
  consumer and the shader sampler exist (see RE-E-05).
- S6 confirm (green): `NIAGARA_PROBE ... sprites=5 ... PASS`;
  `NIAGARA_CHECK` rows for `use_sprite`/`sprite_tex` all pass.
- verdict: **FIXED (renderer data consumed); sprite coverage is 5 k of 16 live systems — the other 11 resolve to opaque atlas/albedo pages and deliberately stay on the procedural falloff.**

### Sprite mask measurement (why only 5 systems sample art)

Every sprite texture referenced by a *placed* system was measured headless
(`Image.load_from_file`, `detect_alpha()`, sampled alpha coverage, border
coverage). A texture is used only when it has alpha, border coverage ≤ 0.20
(an atlas page is opaque to its edges) and 0.005 ≤ coverage ≤ 0.85.

| texture | alpha | coverage | border | verdict |
|---|---|---|---|---|
| `T_LootAttract_Shine.png` | yes | 0.019 | 0.000 | mask |
| `Smoke32.png` | yes | 0.072 | 0.006 | mask |
| `TX_Splash_Big_01a_ALB.png` | yes | 0.148 | 0.000 | mask |
| `T_LeafWillowGlow_D.png` | yes | 0.218 | 0.034 | mask |
| `T_BushesLeaves_DA.png` | yes | 0.338 | 0.016 | mask (mesh system, not bound) |
| `T_LightGlowsA_D.png` | yes | 0.413 | 0.105 | mask |
| `T_TrashDebris_DA.png` | yes | 0.765 | 0.752 | reject (page) |
| `T_Bomb_Liquid_DA.png` | yes | 0.837 | 0.861 | reject (page) |
| `T_SlimeBomb_DA.png` | yes | 1.000 | 1.000 | reject (page) |
| `T_Atlas_B_01_BC.png` | **no** | 1.000 | 1.000 | reject (opaque 2048² atlas — the candle's "resolved" sprite) |
| 19 further `_D`/`_BC`/`_N` maps | no | 1.000 | 1.000 | reject (albedo, not a mask) |

24 of 29 measured textures are opaque albedo/atlas pages. That is a
material-resolution defect (the material resolves to the wrong texture token —
`T_Dart_Electric_D` for the turret, `T_Atlas_B_01_BC` for the candle,
`T_Bomb_Liquid_DA` for rain), **not** something the renderer may paper over by
binding an opaque page as a billboard. Handed to T01/T08 via Doc corrections.

## RE-E-04 — 1,044 parameter buffers, decoded

- severity: P0
- S1 investigate: `tools/parse_vfx.py:371-375` writes
  `parameter_defaults: "unknown (ParameterData bytes not decoded)"` and never
  opens `OverrideParameters.ParameterData`. `grep -rl '"ParameterData"'
  extracted/json | wc -l` → 203 files. Nothing consumed it.
- S2 research: the buffer is self-describing for the components that carry the
  schema: `SortedParameterOffsets[{Name, TypeDef, Offset}]` + little-endian
  `ParameterData`. Verified against the hand-decoded values in RE-E-04
  (candle, rain, beam, goo) — all four reproduce exactly.
- S3 confirm (red): before the change the loader had no decoder and no
  parameter-derived uniform; the candle tint was the hard-coded
  `Color(2.2, 1.0, 0.30)`/`Color(1.0,0.55,0.18)` name-regex pair.
- S4 fix: new `game/src/core/vfx/niagara_params.gd`:
  - `decode_override()` — schema-driven struct read (Vector4f/LinearColor 16 B,
    Vector/Vector3f 12 B, Vector2f 8 B, Float/Int32/Bool 4 B; unknown/data-
    interface types are skipped, never guessed);
  - `prepare()` — opens only the Blueprints the map's placements name (77 files
    for the whole extraction, 17 for Guildhall_Gameplay), caches them per
    process;
  - `resolve()` — returns `{matched, auto, params}` for one placement;
  - `_spawn_level_niagara` applies the first authored colour
    (`Color1`/`EffectColor`/`ParticleColor`/`EmberColor`/`PuddleColor`/`BeamColor`/
    `Tint`/`Color`) and the authored `Scale` (cm → m) to the instance.
- S5 test: `probe_niagara.gd` asserts the decoded literals listed in the schema
  table below and that the authored candle instance tint/scale reached the
  instance (1.0, 0.30173, 0.0, α 0.85 and 0.065 × 0.13 m).
- S6 confirm (green):
  `params=810 tint(param/material/fallback)=743/12/293` and every
  `NIAGARA_CHECK` row passes.
- verdict: **FIXED. Doc correction: only 76 of the 1,044 non-empty buffers are self-describing (968 carry bytes with no `SortedParameterOffsets`); the 76 cover every placed system that overrides a look parameter, so the practical ceiling is what was claimed, the count is not.**

### Parameter schema (measured; 77 schema rows, 46 distinct (system, schema) pairs)

Type sizes are confirmed by the offsets themselves (e.g. `Lightning_Enabled:Bool@12`
followed by `LightningColor:LinearColor@16`). Names as authored (leading `User.` stripped).

| system | parameters (type@offset) | decoded values used |
|---|---|---|
| `NS_Candelabras_Flame` | Color1:Vector4f@0, Color2:Vector4f@16, EmberColor:LinearColor@32, Scale:Vector2f@48, TimeOffset:Float@56 | Color1 (1.0, 0.30173, 0.0), Color2 (1.0, 0.1231, 0.0), EmberColor (1.0, 0.33953, 0.01481), Scale (5, 10), TimeOffset 1.0 |
| `NS_SecurityTurret_Desactivated` | EffectColor:LinearColor@0 | (1.0, 0.0, 0.66981) — magenta, not the port's red |
| `NS_SecurityTurret_Destruction` | EffectColor:LinearColor@0 | (1.0, 0.0, 0.66981) |
| `NS_Detector_LightBeam` | Alpha:Float@0, BeamLength:Float@4, BoxSize:Vector3f@8, EffectColor:LinearColor@20, RandomHue:Float@36 | Alpha 1.0, BeamLength 10.0, BoxSize (1,1,5), EffectColor white |
| `NS_Rain_WeatherSystem` | CPU_RainSpawnRate@0, GPU_RainSpawnRateMultiplier@4, Lightning_Delay@8, Lightning_Enabled:Bool@12, LightningColor@16, Close/Far Brightness Min/Max @32-44, SizeMin/Max@52/48, SizeRatio:Vector2f@56 | CPU 100, GPU ×350, SizeMin 0.6, SizeMax 1.6, SizeRatio (1.5, 55), Lightning_Enabled false |
| `NS_RainStorm_Debris` | Leaves/Papers SpawnRate Min/Max, rain brightness/size block | (decoded; not placed in a level) |
| `NS_GooPipe_Enabled` | MinVelocity@0, MaxVelocity@4, PuddleColor:LinearColor@8, SplashOffset:Vector3f@24, SplashSpawnRate@36 | 100 / 400, white, 1.0 |
| `NS_GooTrails` | ParticleColor:LinearColor@0, ParticlesCount:Int32@16 | white, 0 |
| `NS_AntiStealth_Laser` | Alpha@0, BeamLength@4, BoxSize@8, EffectColor@20, IsSneaking@36, RandomHue@40 | (same look family as the detector beam) |
| `NS_AntiStealth_TripwireEffect` | BeamBrightness@0, BeamEnd:Vector3f@4, BeamLength@16, BeamRadius@20, Lifetime@24 | — |
| `NS_Chimney_Plane` | ColorCurve:DataInterface@0, Drag@0, Scale:Vector3f@4, SpawnRate@16, TrailLength@20 | Scale applied as instance size |
| `NS_WardZone_Shards` | Alpha@0, BoxSize:Vector3f@4, EffectColor@16, RandomHue@32, ShardSpawnRate@36 | — |
| `NS_LootAura` / `_Major` | Max/MinColor, Min/MaxGravity, ScaleSpriteSize / Color01,Color02,LootDamage | — |
| `NS_LootGlint` | GlintColor:LinearColor@0, GlintDuration@16, LoopDurationRandomRange:Vector2f@20, SpriteScaleMultiply@28, VelocitySpeedScale@32 | — |
| `NS_MagicMarker_Footstep` | ColorMultiplier@0, Fade@4, Fade Duration@8, FootStep_Color:LinearColor@12, FootStep_Lifetime@28, HasMajorLoot:Bool@32, IsLeft:Bool@36, TimeOffset@40 | authored footstep colour/lifetime (mechanic still thief-vision — T10) |
| `NS_EscapePoint` / `NE_RespawnRitual` | Closing:Bool, CustomTime, PlayAnimation:Bool, UseCustomTime:Bool / PrimaryColor, SecondaryColor, X/Y_Bounds | — |
| `NS_Water_Leakage_02a` | Drop Color:LinearColor@0, Drop Gravity:Vector3f@16, Drop Lifetime@28, Drop SpawnRate@32, Speed@36, Water Color:LinearColor@40, Water Scale@56 | tint from Drop Color |
| `NS_Ripple_02a` | LifeTIme@0, Ripples Size Min/Max@4/8, SpawnRate@12, Spawnrate_02@16, Color:LinearColor@20 | — |
| `NS_TutorialFairy_Spawn`, `NS_Pickpocket_Spawn`, `NS_Cuckoo_Spawn` | Hover*/SpriteSize floats | — |
| `NS_Train_Sparks(Engine)`, `NS_WireSpline_Electrify_Idle` | LoopDuration / Duration floats | — |
| `NE_RespawnRitual` | Closing, CustomTime, PlayAnimation, PrimaryColor, SecondaryColor, UseCustomTime, X_Bounds, Y_Bounds | — |
| data-interface carries | `NiagaraDataInterfaceColorCurve`, `…StaticMesh`, `…Spline`, `…SkeletalMesh`, `…ArrayPosition`, `…ArrayFloat3`, `Object`, `Texture` | skipped by design — object refs, not scalars |

Known schema hazard: data-interface rows can share offset 0 with the first
scalar row (`NS_Chimney_Plane`, `NS_LootAura_Major`, `NS_GooTrails`). The decoder
skips the data-interface type and reads the scalar at its own offset, which is
correct for those three, but a future overlapping scalar pair would silently
read the wrong bytes. Recorded as an open risk.

## RE-E-03 — authored activation is now honoured (3,308 → 1,048)

- severity: P1
- S1 investigate: `parse_tables.py:2384-2412` wrote only
  `asset/source_actor/source/pos/basis/scale/rotation`; `bAutoActivate` was
  dropped. `level_loader.gd:5147-5153` substituted a one-entry global blacklist
  (`NS_Candelabras_Flame_Out`).
- S2 research: 1,044 extracted `NiagaraComponent` exports carry
  `bAutoActivate`; **30 distinct systems** have at least one explicit `False`
  (full list in `niagara_params.gd::EVENT_GATED_SYSTEMS`). Two systems carry an
  explicit `True` (`NS_Rain_WeatherSystem` in the example preset). The flag is
  per component, so a placement whose own Blueprint states a flag wins.
- S3 confirm (red): `NIAGARA_PROBE ... active=3308 skipped=387 systems=36` —
  every turret showed both a "destroyed" and a "deactivated" puff, every eye
  all three states, every unbroken door break dust.
- S4 fix: `niagara_params.gd` decodes the flag and exposes
  `is_event_gated()`; `_spawn_level_niagara` resolves
  `placement flag → event-gated set → on`, and `ctx["niagara_inactive_skipped"]`
  now counts the whole authored-off set, not just the blacklist. The old
  `NIAGARA_INACTIVE_ASSETS` constant is reduced to a comment that points at the
  generic rule (the flame-out system remains off because its own components say
  so).
- S5 test: `probe_niagara.gd` pins the active set per system (16 systems,
  below) and `--verify-activation` re-derives the event-gated set from every
  extracted JSON.
- S6 confirm (green):
  `NIAGARA_PROBE ... active=1048 skipped=2647 systems=16` and
  `NIAGARA_ACTIVATION scanned=12541 negatives=30 expected=30 missing=[] stale=[]`.
- verdict: **FIXED for the load-time state and the switch API. `level_niagara_culler.set_system_active(asset, on)` is the Blueprint-switch counterpart and is proven by the probe (`NIAGARA_SWITCH NS_Ripple_02a off_changed=1 restored=true`). Wiring it to `device_layer`/`security_turret` is a device-state contract, reported for T10.**

### Authored active set (per system, whole extraction)

| system | authored | active | system | authored | active |
|---|---|---|---|---|---|
| NS_SecurityTurret_Desactivated | 478 | 0 | NS_LootStash | 57 | 57 |
| NS_SecurityTurret_Destruction | 478 | 0 | NS_Moth | 30 | 30 |
| NS_Candelabras_Flame | 413 | 413 | NS_FirePlace | 10 | 10 |
| NS_Candelabras_Flame_Out | 387 | 0 | NS_Chimney_Plane | 6 | 6 |
| NS_Detector_LightBeam | 330 | 330 | NS_LootAura_Major | 4 | 4 |
| NS_DoorBreakDust | 283 | 0 | NS_Train_Smoke | 4 | 4 |
| NS_SecurityEye_Alerted | 181 | 0 | NS_Train_SparksEngine | 4 | 4 |
| NS_SecurityEye_Neutral | 181 | 181 | NS_ChimneySmoke_Huge_BC_01 | 3 | 3 |
| NS_SecurityEye_Spotted | 181 | 0 | NS_Falling_Leaves | 2 | 2 |
| NS_NoiseAlarm_TargetEffect | 136 | 0 | NS_RainStorm_Debris_BC | 1 | 1 |
| NS_GooPipe_Enabled | 135 | 0 | NS_Rain_BC | 1 | 1 |
| NS_GooTrails | 135 | 0 | NS_Water_Leakage_02a | 1 | 1 |
| NS_ChestBreakDust | 93 | 0 | NS_Ripple_02a | 1 | 1 |
| NS_WardZone_Shards | 80 | 0 | NS_EscapePoint | 25 | 0 |
| NS_PowerSupplyWall_BrokenState | 15 | 0 | NS_PowerSupply_Electrify | 11 | 0 |
| NS_TutorialFairy_Spawn | 5 | 0 | NS_WireSpline_Electrify_Idle | 5 | 0 |
| NS_WaterSinking_Left / Right / Center | 9 | 0 | NS_LootGlint | 1 | 0 |
| **total** | **3,695** | **1,048** | | | |

(The 1,048 is exactly 3,308 − 2,260, the number RE-E-03 predicted for the
event-gated set; the 387 old blacklist entries are a subset.)

## RE-E-05 — the probe and the E2E guard now test behaviour

- severity: P1
- S1 investigate: `probe_niagara.gd:52-56` asserted five integers plus
  `host.get_child_count()`; `e2e_tier2_boundaries.gd:323-328` and
  `e2e_tier4_scenarios.gd:328-340` asserted
  `read_text("res://src/core/vfx_manager.gd").find("VectorVM") < 0`.
- S2 research: a string search is not a fidelity statement, and it *inverts* the
  quality signal: naming the VM or decoding the parameter buffers fails the
  suite. `run_tests.gd:4448-4460` separately pins the catalogue shape and the
  `ParameterData` note; that pin is left intact because the catalogue was not
  regenerated (see BLOCKED-ON T01).
- S3 confirm (red): old probe `NIAGARA_PROBE PASS` with 3308 instances and no
  material, texture or parameter inspection whatsoever.
- S4 fix: `probe_niagara.gd` rewritten. It now checks: authored census; active
  set per system; independent (system, 32 m cell) node recount; per-system
  instance counts read back out of the real nodes; sampler bound + non-null for
  every measured mask and *not* bound anywhere else; the decoded literals in the
  schema table; the authored candle tint and XY scale; sprite-mask table drift
  against the PNGs; candle de-duplication through the loader's own helper;
  whole-extraction and per-map distance culling; and, under
  `--verify-activation`, the event-gated set against 12,541 extracted files.
  The two E2E guards were replaced with structural assertions on
  `niagara_library.gd` (`SYSTEMS_PATH`), `niagara_params.gd`
  (`SortedParameterOffsets`, `EVENT_GATED_SYSTEMS`), the shader
  (`sampler2D sprite_tex`, `INSTANCE_CUSTOM`) and the loader
  (`NiagaraParams.prepare`, `niagara_sprites`).
- S5 test: the probe is the test; it exits non-zero unless every check passes.
- S6 confirm (green): `NIAGARA_PROBE PASS` (all rows), `grep -rn VectorVM game/tests/`
  → no hits, `make test` fails=0, E2E rows T2-06-A / T4-12 pass.
- verdict: **FIXED.**

## RE-E-09 — candle double-spawn is now map-global

- severity: P2
- S1 investigate: `level_loader.gd:2501-2513` set `authored_candle_vfx` only
  when the file path contained `thievesden`; `:2650-2651` spawned the procedural
  flame whenever that was false, so every Guildhall/OldManor candle got both a
  teardrop quad and an authored billboard at the same wick.
- S2 research: every map's candelabras carry authored
  `NS_Candelabras_Flame` placements (413 total, 121 candle meshes in Guildhall
  POI alone). The authored flame *is* the look; the procedural quad is the
  stand-in for candles with no authored placement.
- S3 confirm (red): the old rule suppresses 0 flames outside the Den;
  `NIAGARA_CANDLE Building_Guildhall_POI candles=121 flames=140 suppressed=79`
  measured with the new helper shows 79 of those 121 candles sat on top of an
  authored flame.
- S4 fix: collect the authored flame positions per sublevel and suppress the
  procedural flame only when one is within 0.75 m of the computed wick
  (`_authored_flame_near`). No map-name test remains; a counter
  (`result["candle_flames_suppressed"]`) records the suppression.
- S5 test: the probe exercises the loader's helper over Guildhall POI and the
  Den and requires a non-Den suppression.
- S6 confirm (green): `suppressed=79` (Guildhall POI), probe PASS.
- verdict: **FIXED. The 42 Guildhall candles with no authored placement keep their procedural flame (intended).**

## RE-E-10 — authored placement scale is applied

- severity: P2
- S1 investigate: `level_loader.gd:5172-5185` built
  `Transform3D(basis_from_9_floats, pos)` and never read `rec["scale"]`; the
  shader then overrode `MODELVIEW_MATRIX` and scaled `VERTEX.xy` by `base_size`,
  so even a set basis scale could not size the quad.
- S2 research: every placement record carries `scale` (e.g. 1.3 for a
  candelabra); the candle component carries `User.Scale (5, 10)`.
- S3 confirm (red): no code path read `rec.get("scale")` inside
  `_spawn_level_niagara` (`grep` shows the omission).
- S4 fix: instance basis = authored basis × (placement scale × authored
  `User.Scale` cm→m); the shader reads `length(MODEL_MATRIX[0].xyz)` /
  `[1]` before it installs the camera-facing basis and multiplies
  `VERTEX.xy`. Systems that carry `User.Scale` size absolutely (`base_size = 1.0`)
  and skip the class band.
- S5 test: the probe requires the authored candle instance at
  (2.6105, 36.5, −60.1648) to have X/Y scale 0.065/0.13 m = 1.3 × (5,10) cm.
- S6 confirm (green): that row passes; a 1.3× candelabra is now 1.3× the flame.
- verdict: **FIXED.**

## RE-E-14 — chunk + distance culling

- severity: P2
- S1 investigate: one MultiMeshInstance3D per system parented to the map root;
  no `custom_aabb`, no `visibility_range_*`; the 32 m partitioner never saw them,
  so a system's AABB spanned the whole map.
- S2 research: the loader already partitions geometry into 32 m XZ cells
  (`CHUNK_SIZE`) for exactly this reason.
- S3 confirm (red): 36 nodes, 3,308 quads, all in the frustum test from anywhere.
- S4 fix: `_spawn_level_niagara` emits one MultiMesh per (system, 32 m cell),
  positions the node at the cell centre, stores instance transforms relative to
  it, sets a tight `custom_aabb`, and registers every node with the new
  `game/src/core/vfx/level_niagara_culler.gd` (60 m radius + 10 m hysteresis,
  0.5 s tick, camera-driven with an explicit `update_for_position` for tests).
- S5 test: the probe calls `update_for_position` at the extraction's east end,
  5 km away, and on Guildhall_Gameplay alone.
- S6 confirm (green):
  `NIAGARA_CULL near(visible/total)=4/140 far=0/140`,
  `NIAGARA_CULL_MAP Guildhall_Gameplay active=219 nodes=39 visible=19`.
- verdict: **FIXED. Node count rises 36 → 140 (whole extraction) because a system now owns one node per 32 m cell; the visible set is what fell, which is the metric that matters for draw calls.**

## RE-E-11 — the footprint decal uses the authored decal, not a UI icon

- severity: P2
- S1 investigate: `vfx_manager.gd:411` bound
  `res://assets/ue/Raw/Art/UI/Icons/T_Decal_Footstep.png`; `grep` showed it was
  the only reference.
- S2 research: the authored carrier is `NS_MagicMarker_Footstep`
  (`Art/Effects/Thiefvision_Footprints`), mesh renderer, material
  `MI_FootSteps_ThievesTrail`, texture
  `res://assets/ue/Raw/Art/Environment/Props/Containers/Crates/T_Crate_Decal_D.png`
  (systems.json + materials.json). Measure of that PNG: 1024², RGBA, and it
  carries a **real authored alpha mask** (716,528 of 1,048,576 texels at alpha 0,
  195,944 partial); its RGB is mid-grey (luma 0.19–0.45). So the decal must take
  the authored alpha, not a luminance bake.
- S3 confirm (red): the constant pointed into `Art/UI/Icons/`, and the bake
  turned the UI icon's black background into the silhouette. (An intermediate
  attempt that kept the luminance bake on the authored texture would have turned
  it into a flat grey rectangle — worker evidence, caught before commit.)
- S4 fix: `vfx_manager.gd` binds the authored decal path; `_get_footstep_mask_tex`
  uses the source alpha when the image has one and keeps the luminance bake only
  as the fallback for an opaque source. 128 px downscale, cache, prewarm and the
  public API are unchanged.
- S5 test: suite 34c still asserts the baked mask (corner alpha < 0.05, max > 0.5,
  no emission) and now passes on the authored alpha; its stale
  `T_Decal_Footstep` comment/messages were corrected to name the authored decal
  (behavioural assertion untouched). The probe's sprite-mask table does not list
  this texture as a billboard mask (it is a mesh-renderer texture), so no sampler
  binds it.
- S6 confirm (green): `make test` → `PASS: 34c Footprint decal uses the authored
  decal alpha mask (NS_MagicMarker_Footstep) with emission_enabled=false`,
  `SUMMARY: fails=0`; `grep -rn "T_Decal_Footstep" game/src/` → no hits.
  `run_tests.gd:1886/1890` still pins `T_Decal_Footstep*.png` as the albedo of
  the *different* materials `MI_Decal_TrailMarker_Footstep` / `…_Disguise` in
  `materials.json`; that is a materials-data assertion, still true, left alone.
- verdict: **FIXED (texture source and mask source). Two honest caveats: the
  authored binding is a crate decal (`T_Crate_Decal_D`) used as a thief-vision
  trail mask, i.e. the material's texture token is still wrong (T08/T01 data
  issue); and showing the trail only under xray is gameplay, left to T10.**

## RE-E-08 — the four "REFERENCE_MATCHED" builders are probe-only

- severity: P2
- S1 investigate: `spawn_foyer_security_beam`, `spawn_arcane_ward`,
  `spawn_vine_lock`, `spawn_crimson_alarm` in `vfx_manager.gd` carry
  `REFERENCE_MATCHED (HL-1)` doc comments; their only callers are
  `build/qa/probe_vfx.gd` and `build/qa/capture_w1_trim_neon.gd`.
- S2 research: the in-game carriers are the authored detector cards +
  `security_beam.gd` (foyer beams), `ward_zone.gd` (ward), nothing (vine lock),
  `alarm_eye.gd` + `tat_alarm.gdshader` (crimson wash).
- S3 confirm (red): `grep -rn` → 0 game-side callers, yet the doc comments assert
  a reference match against S24–S26.
- S4 fix: relabelled `QA_ONLY (probe/capture)` with the in-game owner named and
  `RE-E-08` cited; bodies and signatures untouched. No gameplay wiring was
  invented, because the game-side events belong to devices/interactables owned
  by other lanes, and a wrong wiring would be a behaviour change. While
  relabelling, `tat_alarm.gdshader` was found to have **no game-side consumer**
  (the QA alarm builder is its only user) — recorded, not "fixed".
- S5 test: static comment review; compile gate unchanged.
- S6 confirm (green): no `REFERENCE_MATCHED` remains on the four builders.
- verdict: **FIXED (relabelled). Not wired — see Open risks.**

## RE-E-01 / RE-E-15 — docs and catalogue joins

- severity: P3
- S1 investigate: `systems.json` export name `NS_Fireplace` vs file
  `NS_FirePlace`; `NE_RespawnRitual` / `NE_Lightning_Projectile` un-catalogued;
  the HL-1 numbers in `REFERENCE_BASELINE.md:283` and `FIDELITY_GAPS.md:20,77,115`
  disagree with the data (see RE-E-15).
- S4 fix: `NiagaraLibrary.asset_key()` is case- and underscore-insensitive, so
  `NS_FirePlace` resolves to the `NS_Fireplace` record (10 placements now get the
  catalogue's base size and a correct folder family).
- S6 confirm: `NIAGARA_PROBE ... systems=16` includes `NS_FirePlace` with 10
  instances and no missing-catalogue warning.
- verdict: **FIXED for the join; the `NE_*` gap needs a producer change (BLOCKED-ON T01).**

---

## Gate evidence (all re-run on this tree after the last edit)

| gate | command | result |
|---|---|---|
| compile | `tools/godot --headless --path game --script tools/check_scripts_compile.gd` | `scripts checked: 124, broken: 0` |
| unit suites | `make test` | `SUMMARY: fails=0` (278 PASS) |
| player | `tools/godot … res://tests/test_m2_player.gd` | `M2_SUMMARY: fails=0` (11 PASS) |
| Niagara | `tools/godot … res://tests/probe_niagara.gd` | `NIAGARA_PROBE PASS` (all behaviour rows) |
| Niagara activation | `tools/godot … probe_niagara.gd -- --verify-activation` | `scanned=12541 negatives=30 expected=30 missing=[] stale=[]`, PASS |
| E2E | `tools/godot … res://tests/e2e/run_e2e_tests.gd` | `SUMMARY: fails=0 passed=278 total=278` |
| audit | `make audit` | `content niagara: OK records=3695`, `baseline: matches`, `AUDIT PASS` |
| ratchet | `make gate-ratchet` | `GATE_RATCHET: PASS` |
| perf wrapper | `build/qa/test_perf_guard.sh` | `PERF_GUARD_TEST PASS checks=78 fails=0` |
| leak | `TAT2_NO_DEN_PROBE=1 tools/godot … probe_leak.gd` | documented clean path, no warnings |
| doors | `tools/godot … probe_door_walk.gd` | `DOORWALK PASS` |
| viewmodel | `tools/godot … probe_viewmodel_truth.gd` | `VIEWMODEL_TRUTH PASS` |

The E2E exit still prints the same pre-existing `21 ObjectDB instances / 4
resources / 3 RendererSceneCull RIDs` lines as the committed
`docs/reports/logs/w7-merged/e2e.log`; they are not new.

## Before / after (measured)

| metric | before | after |
|---|---|---|
| live level-Niagara instances (whole extraction) | 3,308 | **1,048** |
| systems with a node | 36 | **16** |
| MultiMesh nodes | 36 | 140 (chunked) |
| nodes sampling an authored sprite | 0 (shader had no sampler) | **5 systems** |
| placements with a decoded authored parameter set | 0 | **810** |
| authored tint (params / material vector) | 0 (name regex on all 3,308) | **743 / 12** |
| counted family fallback tint | 3,308 | 293 |
| placements with authored scale applied | 0 | all |
| distance culling | none | 60 m + 10 m hysteresis; **4/140** visible from the map edge, **0/140** at 5 km |
| Blueprint switch (`bAutoActivate` counterpart) | none | `set_system_active(asset, on)` hides/shows a system's chunks; probe `off_changed=1 restored=true` |
| Guildhall_Gameplay | 1,134 authored / 1,134 drawn / 39 nodes | 1,134 authored / **219 drawn** / 39 nodes / 19 visible from the east end |
| Guildhall POI candle double spawns | 79 | **0** (79 suppressed, 42 deliberate stand-ins) |
| sprite textures measured / usable | 0 / 0 | **29 / 6** (5 active systems bound) |
| extracted parameter buffers decoded | 0 | **76 self-describing** of 1,044 non-empty |
| probe assertions | 6 (5 ints + child count) | ~65 executed behaviour checks (47 assertion sites + per-system/texture loops) |

## Doc corrections (for the integrator; not edited by this team)

1. `docs/REFERENCE_BASELINE.md:283` (HL-1): replace the row with
   "3,695 authored placements → **1,048 live instances** after authored
   `bAutoActivate` (2,647 event-gated); the 76 self-describing
   `NiagaraComponent.ParameterData` buffers are decoded (candle colour/scale,
   rain spawn rate 100 / ×350 / size 0.6–1.6, turret magenta, beam alpha/length),
   and the resolved sprite is sampled only when the measured mask table accepts
   it (6 of 29 textures). VectorVM bytecode and `loop_duration` remain
   unrecoverable."
2. `docs/FIDELITY_GAPS.md:20,77,115` and `docs/reports/vfx-catalogue.md:23-27,70-73`:
   numbers move to 1,048 live / 16 systems / 5 sprite-masked / 140 chunk nodes;
   `NE_Lightning_Projectile` and `NE_RespawnRitual` **do** exist in the manifest
   and the extraction.
3. `tools/parse_vfx.py:371-375`: `parameter_defaults` should say "decoded by the
   runtime from `SortedParameterOffsets`" and the catalogue should gain
   per-system `activation` (`bAutoActivate` summary) and `parameter_schema`
   fields; also add the two `NE_*` packages and fix the `NS_Fireplace` export
   name. **T01 owns the producer; the runtime consumer is committed.**
4. `docs/reports/visual-fidelity.md`: S24–S26 are scored against builders with no
   gameplay caller (`build/qa/probe_vfx.gd` only). Either score the in-game
   carriers (authored detector cards, `ward_zone.gd`) or restate those frames as
   absent.
5. `AGENTS.md` "Known traps": add "Level Niagara is one MultiMesh per (system,
   32 m cell) and is distance-culled by `level_niagara_culler.gd`; a system is
   no longer one node, and `niagara_systems` != node count."
6. `AGENTS.md`: the trap "Roughness bake…" is unrelated, but the line
   "`parse_materials.py` must read `BasePropertyOverrides`" should also record
   that **VFX sprite texture resolution is wrong-token for most systems**
   (`T_Dart_Electric_D` for the turret, `T_Atlas_B_01_BC` for the candle,
   `T_Bomb_Liquid_DA` for rain) — a material-lane fix, not a VFX one.
7. `docs/HANDOFF_NEXT_AGENT.md`: record that `device_layer`/`security_turret`
   must call the activation switch to show turret/eye/goo states that
   `bAutoActivate` now keeps off at load.

## Open risks

1. **The activation switch is not wired to devices.** Load-time state is
   authored and the switch API exists
   (`level_niagara_culler.set_system_active("NS_SecurityTurret_Destruction", true)`,
   proven by the probe), but nothing calls it yet: a turret that gets destroyed
   will not show its destruction puff until `device_layer`/`security_turret`
   does. That wiring is T10's contract.
2. **The runtime parameter decode reads the extraction.** `extracted/json/**`
   is a sibling of the `game/assets/ue/Raw → extracted/assets` link, so a dev
   tree always has it; a packaged build without `extracted/` falls back to
   `systems.json` colours only (and logs the missing root). The integrator may
   prefer a generated `vfx/parameters.json`; the decoder is already factored for
   that (swap `prepare()` for a table read), but that needs a T01 producer run.
3. **`systems.json.parameter_defaults` still says "not decoded".** The consumer
   does not read that field; suite 52 pins it. It becomes a false statement the
   day someone regenerates the catalogue — T01 must change it in the same commit
   that regenerates.
4. **968 of 1,044 parameter buffers are not self-describing.** Their
   `SortedParameterOffsets` is empty; the byte blobs are unreadable without the
   CDO. If a future lane needs one of those 968, it needs a different extractor
   (serialise the CDO's schema alongside the component).
5. **Sprite resolution is wrong-token for most systems.** The measured mask gate
   prevents visual damage, but only 6 of 29 textures are usable; fixing the
   resolution is `parse_vfx.py` + `parse_materials.py` work (T01/T08).
6. **140 nodes is more draw calls than 36 when everything is visible.** The
   culler bounds it; a dense interior view still draws every chunk in range.
   If the perf wrapper ever measures VFX, compare visible-node counts, not total.
7. **`--verify-activation` is opt-in** (12.5k files, ~2 min headless). Routine
   probe runs do not re-derive the event-gated set; the wave gate should run it.
8. **Chunk node names encode the cell** (`LevelNiagara_<system>_<cx>_<cz>`), and
   `probe_niagara.gd` parses them. Renaming the pattern silently breaks the
   per-system assertions — the probe fails loudly, but the pattern is now a
   contract worth an AGENTS line (see Doc corrections 5).
```
