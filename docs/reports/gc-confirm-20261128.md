# Phase 3B.4 — Destructibles extraction and `fallback_broken=93` confirmation

Worker `gc-confirm`, branch `teamwork/20261127-1810-phase3-gc-confirm`, base
`0f90e87`. Headless only: no GPU, no extractor run, **no write to the shared
`game/data/generated`** (the producers were run into a private `/tmp` root and
the worktree's generated-data symlink was restored afterwards).

**Verdict: the 93-row chest fallback is CONFIRMED.** `GC_ChestTrunkALid` has
no separate fracture-piece mesh in the authored collection; its only
`AutoInstanceMeshes` entry is the intact lid itself, auto-instanced 51× over the
collection's 51 convex particles. The port must keep the labelled
`SM_ChestTrunkALid_Broken` fallback. The extraction did expose a real producer
regression: once the dump became visible, the producer painted the intact lid as
the "broken" overlay for all 93 chests (`fallback_broken` 93 → 0,
`auto_instance` 93). Fixed in `tools/parse_tables.py`; a private regeneration
restores 93 and changes nothing else.

## 1. Authored evidence — the dump

`extracted/json/Destructibles/GeometryCollections/GC_ChestTrunkALid.json`
(extractor `json` pass, 2026-11-28) — one `GeometryCollection` export:

| field | value |
|---|---|
| `AutoInstanceMeshes` | exactly **1** entry |
| `AutoInstanceMeshes[0].Mesh` | `StaticMesh'SM_ChestTrunkALid'` — the **intact lid** |
| `AutoInstanceMeshes[0].NumInstances` | **51** |
| any other mesh path in the export | **none** (`MeshResources: null`, `MeshDescription: null`; only `NaniteResources`) |
| `RenderData.bHasMeshData` | `false` |
| `NaniteResources.NumInputMeshes / NumInputVertices / NumInputTriangles` | 52 / 9403 / 7187 |
| `GeometryCollection.GroupInfo` | `Transform 52`, `Geometry 52`, `Convex 51`, `Vertices 9403`, `Faces 7733`, `RootIndex 0` |
| `DamageThreshold` (collection) | `[1.0, 1.0, 1.0]` |
| `SizeSpecificData[0].DamageThreshold` | `5000` (`MaxSize 99999.9`, Chaos Volumetric/Convex, 60 collision particles) |
| `Mass`, `RemovalDuration` | `200.0`, `0.2..0.4` (`bRemoveOnMaxSleep: true`, sleep `5..7`) |
| `Materials` | 2 (`MI_ChestTrunkMid`, `MI_WoodTrimBasicA`) |

The 52 transforms are 1 collection root + 51 convex particles; every particle
renders the one auto-instanced source mesh. **There is no distinct fracture
mesh in the JSON to emit.** The same species is confirmed on the sibling dumps:

| collection | `AutoInstanceMeshes` | `NumInstances` | transforms / convex |
|---|---|---:|---|
| `GC_AppleA` | `SM_AppleA` | 7 | 8 / 8 |
| `GC_BottleWineA` | `SM_BottleWineA` | 65 | 66 / 66 |
| `GC_ChestTrunkALid` | `SM_ChestTrunkALid` | 51 | 52 / 51 |

So the authored "broken" state is N copies of the source mesh, one per particle;
a single-overlay port cannot render that without exploding the collection, and
using it as one overlay would show an intact lid after the break. The shipped
`SM_ChestTrunkALid_Broken.glb` (present in `game/assets/ue/Content/.../Chest/`)
is the labelled broken sibling the producer already used.

## 2. The 93 rows

Across all 107 generated `.tatlevel.json` files there are exactly **93**
`GeometryCollectionComponent` overlays whose `RestCollection` is
`GC_ChestTrunkALid` (all `kind: chest`, owner classes `BP_ChestTrunk_C` /
`BP_ChestTrunk_MajorLoot_C`). Each owner's intact GC leaf is
`SM_ChestTrunkALid` (93/93), so the collection's only auto-instance source *is*
the owner's own visible lid.

At base `0f90e87` (the Sentinel's Phase 3B regeneration) those 93 rows read:

* `source: auto_instance`, `mesh: /Game/.../SM_ChestTrunkALid` (the intact lid)
* payload `gc_stats` totals `components=336 hidden=336 leaves=166
  fallback_broken=0 sibling_smc=5 unresolved=0`

That is a regression, not a newly authored state. Cause: the intact-stem skip
in `_gc_auto_instance_mesh()` only compared the `AttachParent` mesh. The real
chest GC component attaches to `DefaultSceneRoot` (the level dump shows
`GC_BrokenLid` with `AttachParent …BP_ChestTrunk_C_1.DefaultSceneRoot`), so
`attach_mesh` was `None`, the skip never fired, and the new dump's own intact
lid was returned as the broken overlay. Before the Destructibles dump existed
`_gc_collection_props()` returned `None`, so the labelled fallback masked the
bug.

## 3. Fix

`tools/parse_tables.py`:

* `_gc_auto_instance_mesh(rest_path, intact_stems)` now takes the set of the
  **owning actor's** static-mesh stems (every SMC on the actor, plus the
  AttachParent mesh when one exists) and skips any `AutoInstanceMeshes` entry
  whose stem is one of them. This is an authored-data rule ("never paint the
  prop's own intact mesh as its broken state"), not an asset-name special case.
* Header/failure comment updated with the measured dump shape (1 entry, 51
  instances, no fracture mesh) so the fallback's justification is in the code,
  not only in a report.

Private-root regeneration (`/tmp/opencode/gcverify`, full
`parse_tables.py`, `extracted/` + `assets/ue/Content` symlinked, shared
generated tree untouched):

```
GC layers: components=336 hidden=336 visible=0 visible_emitted=0
           hidden_emitted=336 leaves=166 unresolved=0 fallback_broken=93 sibling_smc=5
```

Diff of every `(level, owner, component) -> (source, mesh, collection)` GC row
against the shared payload: **93 rows changed, exactly the chests**, each
`auto_instance → fallback_broken` and `SM_ChestTrunkALid →
SM_ChestTrunkALid_Broken`; **0 other rows changed**. Whole-payload totals after
the fix: 336/336/166/93/5/0 (components/hidden/leaves/fallback/sibling/unresolved).
`GC_BookCaseUpperB_DoorWindow_01` (5 doors) stays `sibling_smc`: its dump has
one `AutoInstanceMeshes` entry with `Mesh: null` and `NumInstances: 1`, so the
sibling glass SMC is still the only mesh available.

No damage/health path was added. Hold-F `break_container` remains the existing
labelled **PORT_DECISION**; the authored `DamageThreshold` values are recorded
above but are not wired to any runtime health/damage system.

## 4. Probe changes (`game/tests/probe_gc_destruction.gd`)

Pins are unchanged numerically — `fallback_broken=93`, `sibling_smc=5`,
`unresolved=0` — because those are the confirmed authored values. Three checks
were added (52 → 55) so the pin fails *with the explanation* instead of a bare
count shift:

1. `GC_ChestTrunkALid overlay rows == 93` (collection census).
2. `chest broken overlay never reuses the intact lid mesh` — counts overlay rows
   whose `mesh` stem is `SM_ChestTrunkALid`; must be 0.
3. `fallback rows use the authored _Broken sibling mesh` — every
   `source=fallback_broken` row must use a `*_Broken` mesh, and the row count
   must equal the authored 93.

The stale-payload detector was exercised against the shared base data: 55
checks, **3 fails** (`fallback_broken 0`; `93 rows point at
SM_ChestTrunkALid`; `rows=0 … expected=93`), exit 1 — the intended fail-loud
behaviour. Against the fixed-complete copy (§5): `GC_PROBE checks=55 fails=0`,
exit 0.

## 5. Gates run (serial, headless, worktree)

| gate | tree / input | result |
|---|---|---|
| `check_scripts_compile.gd` | worktree sources (no generated-data read) | `scripts checked: 232, broken: 0` |
| `run_tests.gd` | worktree sources + shared generated tree (stale) | `SUMMARY: fails=0` (exit 0) |
| `probe_gc_destruction.gd` | shared tree (stale `fallback_broken=0`) | `checks=55 fails=3` — detector fires on the regression (expected) |
| `probe_gc_destruction.gd` | fixed-complete copy (shared generated tree + the private `parse_tables` `levels/`) | `GC_PROBE checks=55 fails=0` PASS |
| `test_gc_break_trigger.gd` | shared tree, and again on the fixed-complete copy | `GC_TRIGGER checks=21 fails=0` PASS in both. **Not** runnable on the bare `parse_tables`-only private root: that tree lacks the other producers' payload, and the test reports `checks=21 fails=1` (`interact starts the lockpick minigame`), so it is not a valid trigger environment |
| E2E tier `a2` | shared tree (stale) | `fails=0 passed=22 total=22` (GC-STATS layers=174 leaves=80 static=20) |
| E2E tier `p2` | fixed-complete copy | `fails=0 passed=17 total=17`, `P2-CENSUS-GC … fallback_broken=93 sibling_smc=5 leaves=166` |
| `python3 build/qa/test_parse_nav.py` | tooling only (no generated tree read) | all PASS (exit 0) |
| `python3 -m py_compile tools/parse_tables.py` | tooling only | OK |

Tree definitions used above:

* **shared tree** — the worktree's `game/data/generated` symlink to the main
  checkout (base regeneration, chest `fallback_broken=0`).
* **fixed-complete copy** — `/tmp/opencode/gcverify/full`: a full copy of the
  shared generated tree with only `levels/` replaced by the private
  `parse_tables` output (the fix in place).
* **bare `parse_tables`-only private root** — `/tmp/opencode/gcverify/game/data/generated`:
  sufficient for the GC payload probe, incomplete for tests that touch other
  producers (the trigger's lockpick check needs `gameplay/*`).

`make audit` will be **red in this branch** (`tools/parse_tables.py` changed
since the baseline) until the integrator regenerates and runs
`make audit-refresh-stamps`. This is the documented worker rule: generated data
and the audit baseline are integrator-owned.

## 6. Integrator must do

1. `python3 tools/parse_tables.py` (or `make normalize`) on the merged tree —
   otherwise the shared payload keeps the 93 intact-lid overlays and both
   `probe_gc_destruction` (new checks) and E2E `p2` `P2-CENSUS-GC` stay red.
2. `make audit-refresh-stamps REASON='parse_tables: chest GC keeps the labelled
   SM_ChestTrunkALid_Broken fallback (Phase 3B.4 Destructibles dump)'`, then
   `make audit`.
3. Re-run the GC probe/trigger and E2E `p2` at the merged HEAD; the probe floor
   may be raised 52 → 55 (never lowered).
4. Docs: the "no dump" wording for `GC_ChestTrunkALid` is superseded by this
   report; the 93 fallback is now dump-backed. Two tracked docs are falsified by
   this task and are **updated in this branch**:
   * `docs/HANDOFF_NEXT_AGENT.md` (the "GC/destructibles" bullet): no longer
     "`Destructibles/` is still absent … the 93-chest fallback is a prediction";
     it now states the dump is extracted and the 93 chests are confirmed with no
     separate fracture pieces.
   * `docs/FIDELITY_GAPS.md` (Destructibles / GC): `probe_gc_destruction`
     `44 checks` → `55 checks`.
   Any other doc still calling the 93 fallback a prediction (e.g. older wave
   reports) is historical and should be read through this report; do not
   re-assert the prediction in new docs.

## 7. Not claimed

* No GPU/Vulkan capture; no visual check of `SM_ChestTrunkALid_Broken` versus the
  authored 51-particle break.
* No runtime damage/health integration (deliberately out of scope).
* The 51 particles are not instantiated as separate Godot meshes; the port keeps
  its single hidden overlay design.
