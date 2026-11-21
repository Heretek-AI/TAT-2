# Task P2-pipeline evidence — hygiene fixes with tool output

Date (UTC): 2026-11-21. Ground truth: `.omo/waves/codebase-gameplay-audit/AUDIT.md`
§4 (Pipeline 7) + lane report `audit-pipeline.md` §6 (P2-1..P2-7).
Working tree already carried phases 0-2 (P0/P1) edits; this task touched ONLY
`tools/tat-extract/Exporter.cs`, `tools/parse_contracts.py`,
`tools/parse_interactables.py`, `tools/parse_containers.py`,
`tools/parse_vfx.py`, `tools/manifest_audit.py`, `tools/reimport_assets.sh`
(new), `game/tests/run_tests.gd`. No `game/src/` edit. `make test` not run
per task rule (orchestrator runs the suite at settle); verify is per-tool runs
+ `dotnet build` + Godot `--check-only` (proven real with a bad-file probe).

Comment note: the headers added below are load-bearing pipeline provenance
(why a predicate drops, what a constant pins), matching the convention every
parser file already carries and the audit's explicit "documented deny-list"
demand — kept deliberately.

## P2-1 — Levels()/Anims()/Audio() predicates + uncounted continues (`Exporter.cs`)

`dotnet build tools/tat-extract -c Release` → `0 Error(s)` (15 warnings, all
pre-existing NU1902/NU1903 third-party package-vulnerability notices).

- `Levels()`: two domains named in the comment (`.umap` map files vs
  `BPP_/SV_/S_/SS_/QG_` blueprint dumps re-consumed by parse_tables as actor
  templates), plus a `levels domains: N umap + M blueprint` stderr line;
  accept set unchanged, `levels-filtered` counting kept.
- `Anims()`: same `AN_/A_/AS_//Animation/` predicate (deliberately NOT
  narrowed — narrowing could drop shipped clips), now with
  `anims-filtered` counting + a comment documenting the over-broad `A_`
  side and the unprefixed-montage miss side.
- `Audio()`: non-`Ak` exports inside audio packages now
  `CountSkip("audio-pkg-skipped")` instead of a bare `continue`.

No extractor run (needs game paks + slow full export); build is the targeted
check. First full `make extract` will print the new counters.

## P2-2 — empty-map → thieves_den default (`parse_contracts.py`)

`python3 tools/parse_contracts.py` (RC 0):

```text
Wrote 16 contracts + 6 mission durations -> /home/john/Projects/TAT-2/game/data/generated/gameplay/contracts.json
WARN: 1 contract(s) defaulted to thieves_den: Contract.Main.1 (order 1)
```

Only the known hub-tutorial empty path defaults; any future empty/unknown map
is a named line, not a silent hub. Output byte-identical to pre-change
(`cmp` clean vs backup).

## P2-3 — Value<=1 spawn-pool exclusion by key (`parse_interactables.py`)

Exclusion is now `v <= 0` (currency placeholders) plus
`KNOWN_TEST_KEYS = {"JEWELKNIFERENOWN"}` at `v == 1` — the single shipped
Value-1 row (`minor JEWELKNIFERENOWN 'jewellknife'`, confirmed in current
`interactables.json`). Any other Value-1 row now warns and stays in the pool.

`python3 tools/parse_interactables.py` (RC 0, no WARN — only the known test
key sits at Value 1):

```text
loot minor n=30 pool=18 min=45 max=180
loot major n=24 pool=18 min=225 max=1000
loot quest n=45 pool=38 flagship=2500
```

Pool counts identical to pre-change. Note: a fresh regenerate differs from the
checked-in file ONLY by the pre-existing parse_tables alias patch (`arc_deg`
lines; verified every non-`arc_deg` diff line is just the hunk `]` closer) —
backup restored, tree clean.

## P2-4 — closed 5-class container dict (`parse_containers.py`)

`python3 tools/parse_containers.py` (RC 0, same 5 classes emitted):

```text
WARN: container-shaped Blueprint outside CLASSES (not emitted): extracted/json/Art/Environment/Props/Furniture/Containers/Chest/BP_ChestTrunk.json
WARN: container-shaped Blueprint outside CLASSES (not emitted): extracted/json/Art/Environment/Props/Furniture/Displays/DisplayPlinth/DisplayCases/BP_Museum_DisplayCase_2x2_Tall.json
WARN: container-shaped Blueprint outside CLASSES (not emitted): extracted/json/Art/Environment/Storefront/Interior/BP_Storefront_DisplayCase.json
WARN: container-shaped Blueprint outside CLASSES (not emitted): extracted/json/Art/Gameplay/MajorLootSafe/BP_DisplayCaseA.json
WARN: container-shaped Blueprint outside CLASSES (not emitted): extracted/json/Art/Prototype/BP_DisplayCase.json
WARN: container-shaped Blueprint outside CLASSES (not emitted): extracted/json/Gameplay/Loot/Actors/Stash/BP_LootStashInteractable.json
wrote .../containers.json (5 container classes: {...unchanged...})
```

The 6 lines read as base/unplaced variants of the 5 shipped classes
(`BP_ChestTrunk` vs `BP_ChestTrunk_MajorLoot_C`, etc.) — surfaced for
orchestrator review, not auto-included. Output byte-identical (`cmp` clean).

## P2-5 — GRAPH_HEAVY constants + undecoded Niagara graphs (`parse_vfx.py`)

Constants kept (suite block #52 pins `graph_heavy=21/mesh_or_ribbon=70/
sprite_only=29`), plus per-run drift review and an explicit per-system
`parameter_defaults` record.

`python3 tools/parse_vfx.py` (RC 0):

```text
Parsed 120 Niagara systems
cutoff review: p90 scripts=18 (const 18), p90 LUTs=89 (const 72)
WARN: bulk distribution drifted past GRAPH_HEAVY constants; review cutoffs (suite pins 21/70/29 — update both together)
Wrote .../vfx/systems.json
classes: graph_heavy=21, mesh_or_ribbon=70, sprite_only=29
```

Every system now carries
`"parameter_defaults": "unknown (ParameterData bytes not decoded)"`
(verified on `systems[0]`). Class counts unchanged → block #52 safe.
`catalogue.md` byte-identical. `systems.json` backup restored after
verification (regenerate also picked up newer `materials.json` resolutions
in 64 systems — pre-existing mixed-vintage staleness, see follow-ups).

## P2-6 — wall-clock margins + shared-autoload fixtures (`run_tests.gd`)

- Door swing (block #4): `await create_timer(0.55).timeout` replaced with a
  poll-to-90° loop capped at 300 frames (fail-closed; same PASS/FAIL text).
- Light-probe throttle window (block #14): `await create_timer(0.15).timeout`
  replaced with a poll until `sample_compute_count` increments, capped at
  240 frames (fail-closed; same `v3 >= v1` assertion).
- Fixture: boot snapshot of `gs.thief_id/difficulty/active_contract_order/
  active_map_id` after the autoload check, restored just before `SUMMARY`
  (block #10's intentional stale-`active_map_id` regression test is
  unaffected — it asserts inline).

Godot `4.7.2.stable.flathub` `--check-only` on the edited script: clean, no
errors. The gate was proven real the same session with a deliberately broken
probe file (`Parse Error ... "!" instead`, then deleted).

## P2-7 — symlink/.import staleness + manifest (`manifest_audit.py`, `reimport_assets.sh`, `run_tests.gd`)

- `manifest_audit.py --min-coverage 0.90` (Makefile flags, RC 0):

```text
Manifest TAT entries: 12704
Resolved in CUE4Parse: 12630 (99.4%)
Dumped raw: 141
Dumped json: 12560
Dumped assets: 10994
Dumped audio: 5019
Dumped audio-meta: 1441
Files written to extracted: 30155
Engine/Content files mounted: 4639
engine-dep OK: Engine/Content/EngineMaterials/WorldGridMaterial.uasset
(+ 5 BasicShapes OK)
freshness levels: fresh (newest src 2026-11-16 11:24, oldest out 2026-11-20 18:42, 74 outputs)
freshness gameplay: fresh (... 13 outputs)
freshness tables: fresh (... 144 outputs)
freshness materials: fresh (... 3 outputs)
freshness audio: fresh (... 2 outputs)
freshness weather: fresh (... 17 outputs)
freshness vfx: fresh (... 2 outputs)
manifest -> extracted/_manifest.json
```

- Every run now writes `extracted/_manifest.json` (gitignored working file):
  filelist mtime, coverage, per-stage counts, engine-dep status, per-group
  `newest_extracted_src/oldest_generated_out/n_outputs/stale`.
- `--fail-on-stale` passes (no stale groups). `--fail-on-errors` FIRES on the
  known BlendSpace limitation (`Animation asset type 'UBlendSpace' is not
  supported for conversion`, errors.log 2026-11-16 newer than filelist.txt
  2026-11-15) — see follow-ups; default flags unchanged.
- `tools/reimport_assets.sh --check` (RC 0): `reimport check: all
  .glb.import sidecars fresh`. Full mode runs `godot --headless --import`
  (not executed here — import run belongs to the settle pipeline).
- `run_tests.gd` boot now fails closed when `res://assets/ue/Content` or
  `.../Raw` does not resolve (covers symlink orphaning at test boot).

## Follow-ups for the orchestrator (not HARD_LIMITs — all reversible)

1. `Makefile`: wire `audit` with `--fail-on-errors --fail-on-stale` and chain
   `tools/reimport_assets.sh` after `extract` (root file, out of this task's
   write scope). Decide whether the BlendSpace errors become an accepted
   exclusion list for `--fail-on-errors` or stay failing.
2. Container WARN review (§P2-4): confirm the 6 base/unplaced variants stay
   unemitted.
3. Mixed-vintage staleness observed: current `materials.json` (Nov 20)
   resolves textures for 64 VFX systems that the checked-in `systems.json`
   lacks — the next `normalize` will show this as a systems.json diff. The
   new `_manifest.json` exists precisely to make this visible.

## Standing items

HARD_LIMIT rows added by this task: none — every P2 item got a tool change
with quoted output above. `game/data/` tree left clean (backups restored);
only `tools/`, `game/tests/`, and this file changed.
