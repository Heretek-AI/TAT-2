# VFX catalogue — 120 Niagara systems as structured data

## Method

`tools/parse_vfx.py` reads every `extracted/json/**/NS_*.json` (120 files) plus
`game/data/generated/materials.json` and writes:

- `game/data/generated/vfx/systems.json` — one record per system (emitters,
  renderers, compiled variable names/types, exposed parameter names/types,
  curve LUT counts, dependency flags, complexity class).
- `game/data/generated/vfx/catalogue.md` — auto-generated per-system table
  (renderer kinds, material short names, resolved sprite texture, class) for
  art review. Do not hand-edit; regenerate.

Key extraction facts (verified against the dumps, e.g.
`NS_RespawnRitual_Particles.json`):

- Exports inside one file repeat with identical `Type`/`Name` but different
  `Outer` (one renderer instance per emitter). Dedupe key is
  `(Type, Name, Outer)`; deduping on `(Type, Name)` alone silently drops
  renderers and undercounts LUTs (first run: 103 materials; corrected: 148).
- `EmitterHandles[].VersionedInstance.Emitter` is always a same-package
  subobject (`<package>.<N>`) or `null` (disabled/unresolved handle). No
  handle points at an external emitter package — the 4 renderer-less systems
  reference `NE_*` emitter names with null emitters and `filelist.txt`
  contains no matching `NE_*.uasset` packages, so no further extractor dump
  was needed or possible.
- Curve LUTs = deduped `NiagaraDataInterfaceCurve` + `VectorCurve` +
  `Vector2DCurve` + `ColorCurve` exports. Counts, not resampled values.
- Sprite textures come from `materials.json` `texs`, preference
  albedo > emissive > normal > orm > first available slot.
- `DataInterfaces`/`UObjects` refs equal to the system's own package
  (embedded DI instances) are filtered out of `exposed_object_refs`.

## Counts

- Total systems: **120** across **59** folders.
- `sprite_only`: **29** (24.2%) — sprite renderer(s) only, no mesh/ribbon,
  no skeletal/vector-field deps. Includes 4 `empty_shell` placeholders
  (all emitters disabled, no renderer data):
  `NS_AntiStealth_TripwireEffect`, `NS_CarryingMajorLoot`,
  `NS_VrilWire_Launch`, `NS_WardZone_Shards`.
- `mesh_or_ribbon`: **70** (58.3%) — at least one non-sprite renderer
  (mesh, ribbon, light, decal or component). Light/decal/component-only
  systems land here too: they cannot go through a plain sprite pipeline.
- `graph_heavy`: **21** (17.5%) — sprite-rendered but ≥ 18 scripts or
  ≥ 72 curve LUTs (≈ top decile; scripts range 2–48, LUTs 0–586) or a
  skeletal-mesh / vector-field dependency. 16 of the 21 are vector-field
  systems sharing the `TilingCurl32` curl-noise field; pure count-based
  heavies are `NS_DoorWard_Explosion` (72 LUTs), `NS_Poison_Fume`
  (20 scripts, 84 LUTs, skeletal + vector-field), `NS_SecurityTurret_Destruction`
  (89 LUTs), `NS_SmokeBomb` (24 scripts, 172 LUTs), `NS_WeaponImpact_HeavyAttack`
  (29 scripts), `NS_Rain_WeatherSystem` (18 scripts + vector-field).

Per-folder counts are in `systems.json` → `by_folder` (largest:
`Art/VFX/Hauntstable` 7, `Art/VFX/NiagaraSystems` 9, `Art/VFX/Environment/RainStorm` 4).

## Material → texture resolution

- Distinct material paths referenced by sprite/ribbon/decal/mesh renderers: **148**.
- Resolved in `materials.json`: **139** (93.9%).
- Missing: **9** — 3 engine defaults (`/Niagara/DefaultAssets/`
  `DefaultSpriteMaterial`, `DefaultRIbbonMaterial`, `M_NiagaraUVDebug`) plus 6
  game paths with no materials dump:
  `BallisticsVFX/.../Explosion_Master2`, `BallisticsVFX/.../MuzzleFlash_Master_Inst`,
  and 4 `DEKO_VFX/VOL1_Water/Materials/MM_*` (Leak_02a, Ripple_Drop_Master_01a,
  Ripple_Master_01a, Splash_03a). The two `NS_Ripple_02a` /
  `NS_Water_Leakage_02a` DEKO water systems are `sprite_only` but their
  materials are unresolvable until those packages are dumped.
- Of the 139 resolved, **91 carry no textures** in `materials.json`
  (procedural/unlit particle materials whose look lives in the material
  graph, e.g. `MI_FireflyParticle`). End result: **129 of 456** renderer
  entries (28%) resolve to a real PNG, covering **58 of 120** systems.
  Examples: `MI_SmokeStack_Smoke` →
  `res://assets/ue/Raw/Art/Gameplay/Gear/SmokeBomb/T_SmokeBomb_D.png`;
  `M_AntiStealth_Sparks` → `.../AntiStealthDevice/T_AntiStealthDevice_D.png`;
  `MI_GooPipe` (mesh override) → `.../Goo/T_GooBubble01_nm.png`.

## Limits (what this data is NOT)

- Niagara compiled graphs are not translated — no spawn rates, lifetimes,
  sizes, velocities, or color curves are decoded into Godot parameters.
- `loop_duration` is null for all 120 systems: `SystemStateData` carries only
  an unbound `ParameterBinding` named `None`, so no duration is resolvable.
- Exposed parameters are names/types only (from `UserParameterRedirects` +
  `SortedParameterOffsets`); defaults live in raw `ParameterData` bytes and
  are not decoded.
- Curve LUTs are counted per type (`curve`/`vector`/`vector2d`/`color`) with
  export names in `curve_lut_names`; LUT sample values are not resampled.
- `sprite_only` does not mean "ready to auto-convert" — it means nothing in
  the data blocks a sprite-pipeline conversion. Empty shells need content
  before they need conversion.

## Verify

```
python3 tools/parse_vfx.py
# Parsed 120 Niagara systems / classes: graph_heavy=21, mesh_or_ribbon=70, sprite_only=29
# materials: 148 distinct, 139 resolved, 9 missing
python3 -c "import json; d=json.load(open('game/data/generated/vfx/systems.json')); assert d['system_count']==len(d['systems'])==120; assert sum(d['classes'].values())==120"
```

`systems.json` parses; all 120 names unique; every record has a complexity
class with reasons; every renderer record carries a `material` key
(null where the renderer type has none).
