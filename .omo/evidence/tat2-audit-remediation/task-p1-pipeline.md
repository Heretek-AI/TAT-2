# P1 pipeline remediation — evidence ledger (task-p1-pipeline)

Date (UTC): 2026-11-20. Scope: audit-pipeline.md P1-1..P1-9 only.
Writes: `tools/tat-extract/Exporter.cs`, `tools/tat-extract/Program.cs`,
`tools/parse_materials.py`, `tools/parse_loot.py`, `tools/parse_spawners.py`,
`tools/parse_gameplay.py`, `tools/manifest_audit.py`, `game/tests/run_tests.gd`
(blocks 47–52 + 2 helpers). `game/src/` untouched. `make test` NOT run here
(orchestrator runs the full suite at settle); verification is per-tool output
plus headless Godot probes of the new blocks only.

Ground-truth probes done first (all quoted values below were measured, not assumed):
115253 tatlevel mesh refs → 105 raw-missing = 2 Engine-via-Raw-OK + 9
`_GENERATED/gjasp` dropped by the Meshes allowlist; WorldGridMaterial mounted
in the pak but unexported; `unmapped_contract_tags == []`; BP_Guard_Base
CharMoveComp MaxWalkSpeed 250.0 (unique); Value-1 loot row is
`JEWELKNIFERENOWN`.

## P1-1 Packages() gate + single-pak mount — FIXED

- `Packages()` now also passes `Engine/Content/EngineMaterials/` and
  `Engine/Content/EngineMeshes/` (the VFX_SkySearchLight_Mesh →
  WorldGridMaterial dangling bind). Everything else under `Engine/` is still
  excluded.
- `Materials()` explicitly queues `Engine/Content/EngineMaterials/` (the
  MI_/M_ prefixes never match `WorldGridMaterial`, so the Packages widening
  alone would still drop it there).
- `MeshQueued()` adds `/_GENERATED/`: the 9 OldManor baked merges
  (Box_*/Cylinder_*/Combined_*) are real mounted .uasset files cited by shipped
  tatlevels — verified present in `extracted/filelist.txt` (24 `_GENERATED`
  entries) with JSON dumps but no GLBs.
- `Program.cs` warns per unmounted sibling pak (`WARNING: sibling pak entry
  NOT mounted`), so the single-pak mount can never silently miss a chunk dir.

Tool output (fresh `dotnet build`, then filtered runs into scratch out-dirs so
`extracted/` is untouched):

```
Build succeeded. 0 Error(s)   (dotnet 10.0.404; one pre-existing CS8603 in FindUsmap)
```

```
$ tat-extract json --filter WorldGridMaterial --out /tmp/p1prove
mounted 22005 files
== json
  json finished 1 in 0s
[json] ok=1 skip=0 fail=0
/tmp/p1prove/json/Engine/Content/EngineMaterials/WorldGridMaterial.json
```

```
$ tat-extract materials --filter WorldGridMaterial --out /tmp/p1prove2
[materials] ok=1 skip=0 fail=0
/tmp/p1prove2/json/Engine/Content/EngineMaterials/WorldGridMaterial.json
```

(pre-fix both commands dropped the file: outside `TAT/` and no MI_/M_ prefix.)

```
$ tat-extract meshes --filter '_GENERATED' --out /tmp/p1prove3
  queuing 114 mesh packages...
[meshes] ok=114 skip=0 fail=0
.../OldManor/_GENERATED/gjasp/Box_42F388A7.glb
.../OldManor/_GENERATED/gjasp/Box_5C7B8085.glb
.../OldManor/_GENERATED/gjasp/Box_696059A2.glb
.../OldManor/_GENERATED/gjasp/Box_760A8A3A.glb
.../OldManor/_GENERATED/gjasp/Box_760A8A3A1.glb
.../OldManor/_GENERATED/gjasp/Box_ADE72DA6.glb
.../OldManor/_GENERATED/gjasp/Box_C9A6CCD3.glb
.../OldManor/_GENERATED/gjasp/Combined_3356956A.glb
.../OldManor/_GENERATED/gjasp/Cylinder_A665D774.glb
```

All 9 gap meshes export, ok=114 fail=0. (No sibling-pak WARNING printed:
no unmounted siblings exist, so the mount is complete.)

## P1-2 Tables() 9-root allowlist — FIXED

Roots widened 9 → 12 (`Art/`, `ThirdParty/`, `Developers/` added); skipped
candidates are counted (`tables-filtered`) AND the first 20 skipped paths are
printed per run (sentinel: UE path logged, never silent continue).

```
$ tat-extract tables --filter 'Developers/gjasp' --out /tmp/p1prove4
mounted 22005 files
== tables
  tables finished 27 in 0s
[tables] ok=27 skip=0 fail=0
```

Pre-fix these 27 dumps were dropped (outside the 9 roots).

## P1-3 Tier-2/3 albedo guesses unmarked — FIXED

`_stem_fallback_albedo` returns `(path, tier)`; every `materials.json` entry
now carries `albedo_source` (`authored | stream-ranked | stream-single |
fallback-stem-direct | fallback-ranked | reference-ranked |
fallback-category | none`), inherited with the bind through parent materials.
Tier-3 growth fails the parse (`MAX_CATEGORY_FALLBACK_ALBEDOS = 0`, pinned
2026-11-20 — no shipped material needs it).

```
$ python3 tools/parse_materials.py
Resolved 1571 materials (1223 with real params) -> .../materials.json
albedo_source counts: {'authored': 485, 'fallback-ranked': 471,
  'fallback-stem-direct': 26, 'none': 204, 'stream-ranked': 331,
  'stream-single': 54}
```

No `fallback-category` binds exist, so the cap gate passes (exit 0). Reader
safety: `level_loader.gd` reads `entry["texs"]`-family keys only; the new
field is additive.

## P1-4 GLB-missing sidecar fallback + degenerate filtering — FIXED

`_glb_primitive_material_names` returns `(names, detail)`; every
`mesh_materials.json` value stays a plain slot list (game/src binds them
positionally and cannot be touched), and the HOW lives in the new sidecar
`game/data/generated/mesh_materials_provenance.json`:
`slot_order_source` (`glb`|`sidecar`), `glb_found`,
`authored_primitives`, `degenerate_filtered`, `emitted_slots`
(+ `glb_parse_error` when present). Every sidecar-fallback UE path is printed;
degenerate drops are counted (currently 0). `_find_glb_for_ue_mesh` also
checks `extracted/assets/<rel>.glb`, so the 5 Engine BasicShapes now order by
their real GLBs.

```
Mapped 2054 mesh material slot lists (2036 GLB-ordered, 18 sidecar-fallback)
meshes with degenerate-filtered primitives: 0 (0 primitives)
[slot-order-sidecar] /Game/Art/... (18 lines, all Old/unused + Engine shapes)
wrote slot-order provenance (2054 entries) -> .../mesh_materials_provenance.json
```

(2031 → 2036 GLB-ordered; the 5 Engine shapes moved out of sidecar.)

## P1-5 quest-fallback invariant prose → SystemExit — FIXED

`parse_loot.py` now raises `SystemExit` when any shipped contract loot_tag is
unmapped, raises when the generic fallback is `NONE`, and prints one
`[quest-mesh-missing]` line per mesh-less quest actor (UE path logged).

```
$ python3 tools/parse_loot.py
[quest-mesh-missing] BP_LootActor_Quest_Abbessford_Northgate_60_CarrazReliquary_C: keeps mesh_res '' (labelled box fallback in loot_item.gd)
[quest-mesh-missing] BP_LootActor_Quest_Abbessford_Northgate_60_CarrazReliquaryNotQuest_C: keeps mesh_res '' (labelled box fallback in loot_item.gd)
wrote .../loot_actors.json (20 bucket actors, 44 quest actors, 43 tag mappings, generic=BP_LootActor_Quest_Abbessford_Northgate_60_Piety_C)
unmapped contract tags: []
unmapped quest tags: ['Loot.Quest.Diamond', 'Loot.Quest.Diamond_Temp', 'Loot.Quest.Example.Diamond', 'Loot.Quest.OrbOfScrying']
```

Exit 0: the invariant holds on current data (quest-row tags without actors
stay a printed warning — future quest content may use the generic by design).

## P1-6 hardcoded alerted_combat_fallback 2.5 — FIXED (derived)

`build_state_speeds()` reads `TATCharacterAIMovement/CharMoveComp MaxWalkSpeed`
from `BP_Guard_Base.json` and divides by 100; a missing property raises `Fail`.
The `sources.fallback` string now records the value actually read.

```
$ python3 tools/parse_gameplay.py
alerted_combat_fallback_m_s derived from BP_Guard_Base MaxWalkSpeed 250.0 -> 2.5
```

(CharMoveComp is unique in the file — verified — and 250.0/100 == the
`guard_ai.gd ALERTED_SPEED 2.5` the runtime already uses.)

## P1-7 spawner approximations unasserted + assert-under-O — FIXED

Both `assert`s replaced with `if ...: print per-mesh UE lines; raise
SystemExit(...)` (survives `python -O`). Runtime pins live in run_tests.gd
block 48 (see P1-9).

```
$ python3 tools/parse_spawners.py
wrote .../spawners.json (8 bucket entries, 4 civilian variants)
```

Exit 0, no missing meshes.

## P1-8 manifest_audit gates mount, not pipeline — FIXED

`tools/manifest_audit.py` gains `--min-dumped`, per-stage zero-output failure,
`--fail-on-errors` (errors.log non-empty AND mtime >= filelist ⇒ fail;
older ⇒ loud warning), required Engine-dep assertions (WorldGridMaterial +
5 BasicShapes), and `--fail-on-stale` freshness across 7 domain groups
(levels/gameplay/tables/materials/audio/weather/vfx: oldest output vs newest
source, absence counts as stale).

```
$ python3 tools/manifest_audit.py --min-coverage 0.90 --min-dumped 30000 --fail-on-stale
Manifest TAT entries: 12709
Resolved in CUE4Parse: 12630 (99.4%)
Dumped raw: 141 / json: 12560 / assets: 10994 / audio: 5019 / audio-meta: 1441
Files written to extracted: 30155
Engine/Content files mounted: 4639
engine-dep OK: .../WorldGridMaterial.uasset (+ 5/5 BasicShapes)
errors.log: ...stale warning text when older than filelist...
freshness levels: fresh ... (7/7 fresh)
exit=0
```

```
$ ... --fail-on-errors --fail-on-stale
errors.log holds current-run failures
exit=1
```

The gate fires on the real current-run `errors.log` (2124 bytes, Nov 16:
BlendSpace/BlendSpace1D/AimOffset anim conversions unsupported — a converter
limitation, listed per asset). NOTE for wiring (Makefile left untouched, out
of write scope): wire `--min-dumped 30000 --fail-on-stale` now; wire
`--fail-on-errors` after triaging that BlendSpace log, or the audit goes red
on a known converter limitation. Suggested line:

```
python3 tools/manifest_audit.py --min-coverage 0.90 --min-dumped 30000 --fail-on-errors --fail-on-stale
```

## P1-9 test blind spots — FIXED (6 new blocks, 47–52)

`godot --headless --check-only --script res://tests/run_tests.gd` → exit 0.
Targeted probes (temporary scripts running ONLY the new blocks, then deleted;
`make test` never run here):

- **47 all-contracts sweep**: 18/18 resolve title/map/loot_tag; orders
  contiguous after the documented Contract.Main.15→15 repair; loot via
  tag map or generic fallback.
  `PASS: 47 all 18 contracts resolve ... repairs: Contract.Main.15 -> 15 (raw ContractOrder 0)`
- **48 spawner+speed pins**: approximations keys present; doc numbers
  extracted by regex equal implementation consts (12.0/10.0/1.4); throwable
  +1 bottle, ammo refill-all 5 keys, health 20→100.0 full; BP 250.0/100 ==
  state_speeds 2.5. All 18 sub-probe lines pass, fails=0.
  (The guard-const half of block 48 could not execute here: `guard_ai.gd`
  has a sibling-node parse error in this tree — see caveat.)
- **49 save round-trip**: +7 persisted across write/reload, corrupt JSON
  loads fail-closed, backup restored, original restored.
  `PASS: 49 save round-trip (+7 persisted, corrupt load fail-closed, original restored)`
- **50 audio audibility**: counts floor (1205 ≥ 1200) + `has_real_clip` for
  footstep/blackjack/lockpick/grapple/smoke/fairy/alert/loot with on-disk
  clip files (all 8 verified: `.ogg` + `.import` present). Could not execute
  here: AudioManager autoload broken by the same sibling edit — see caveat.
- **51 GLB-for-every-mesh_res**: mirrors loader resolution (Content, Raw
  Engine mirror, .gltf second); dedupes to 1652 unique; 9 known
  `_GENERATED/gjasp` gap meshes allow-listed by exact UE path (shrink to
  zero on re-extract — the P1-1 fix queues them now).
  `PASS: 51 GLB-for-every-mesh_res (134620 refs, 1652 unique, 9 known _GENERATED gap)`
  (Probe sweep is deeper than my Python probe: recursive vs one-level glob.)
- **52 guard/VFX/export**: 4/4 detection ramps present; guard speed consts
  == state_speeds; vfx catalogue 120 (21/70/29) + ParameterData boundary
  note; `preset.0` platform Linux; mobile script has --texture-cap + ETC2.
  Sub-probe: fails=0. (Guard-const half pending tree settle — see caveat.)

Caveat (shared-tree state, not this node): at probe time `guard_ai.gd` and
`audio_manager.gd` fail to parse due to concurrent sibling-node edits
(`_countdown_running` undeclared, `AudioStreamLoop` undeclared), so blocks
48-guard-half, 50, 52-guard-half fail in the probe with `guard=-1.0` /
`AudioManager missing`. Their expressions mirror proven patterns (block 26
constant-map reads; on-disk clip verification above) and the underlying data
(BP 250.0, state_speeds 2.5, counts, ramps, catalogue, preset) is verified;
they pass once the tree parses. The orchestrator's settle run is the arbiter.

## Standing HARD_LIMITs (unfixable in scope, with search evidence)

1. **VFX authored look.** `parse_vfx.py` records names/types only:
  `notes: ["loop_duration is null ...", "Exposed parameters are names/types
  only; defaults live in raw ParameterData bytes and are not decoded.",
  "Niagara compiled graphs are not translated; ..."]`. No tool in scope can
  assert pixel look; blocks #8/#9 pin plumbing, block 52 pins the catalogue
  boundary (120/21/70/29 + ParameterData note). A pixel-diff harness needs
  decoded ParameterData — future work.
2. **Runtime boot of all 18 contracts.** Each mission boot costs a
  `wait_frames < 240` settle (blocks 4/7/10); ×18 in-suite is unbounded
  suite-time cost with no Godot run available here to size it. Block 47
  gates the wiring (data-level, all 18); runtime boot stays at 3/1/4.
3. **Actual export builds.** `game/export_presets.cfg` carries only the
  Linux preset (no Android preset in-tree); `prepare_mobile_project.py`
  markers verified present (--texture-cap ×3, ETC2 ×2). A real
  `linux-build`/APK run needs templates/devices outside this environment.
4. **Full `make test`.** Per instructions the orchestrator runs it at settle.

## Files changed (tracked-tree diff, this node only)

- tools/tat-extract/Exporter.cs, Program.cs
- tools/parse_materials.py (+ `mesh_materials_provenance.json` sidecar schema)
- tools/parse_loot.py, parse_spawners.py, tools/parse_gameplay.py
- tools/manifest_audit.py
- game/tests/run_tests.gd (blocks 47–52, `_p1_collect_json`, `P1MockActor`)

Regenerated (gitignored) outputs: `materials.json` (+`albedo_source`),
`mesh_materials.json` (Engine shapes now GLB-ordered),
`mesh_materials_provenance.json` (new, 2054 entries), `state_speeds.json`
(dynamic fallback source), `loot_actors.json`, `spawners.json`.
