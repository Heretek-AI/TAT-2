# Phase 2 lane — GC / bookcases (G-1..G-3)

Worktree `phase2-gc`, branch `phase2-gc-bookcases`, based on `79d8b8a`
(main's `a1c3597` is a docs-only commit on top, no code conflict).
Headless only: no GPU capture, no Steam, **no regeneration of the shared
`game/data`** (the producer was run into a private `/tmp` root; the worktree's
`game/data/generated` symlink was restored afterwards).

## G-4 first (measurement only, not claimed)

`make extract` still has no `json` stage and `Destructibles/` is absent from the
dump, so the 93-chest `_Broken` fallback cannot be re-derived here. The current
payload still reports `fallback_broken=93` (probe G-4 evidence line unchanged);
this lane **confirms nothing** about the post-extraction count and claims none.
The prediction to check after the extractor `json` pass is `fallback_broken=93`
becoming mesh-resolved (census `components=336` must not move).

## Static-batch finding (G-2 decision)

The bookcase door meshes are **already** in the static batch; emitting leaves
would duplicate them.

| level | bookcase owners | frame doors `…Door_2x8` | glass panes `…Door_Glass_2x8` | bookcase GC (`hidden`) |
|---|---:|---:|---:|---:|
| `Guildhall_Loot` | 8 minor | 16 | 16 | 16 |
| `Building_Guildhall_POI` | 2 major | 4 | 4 | 4 |
| `FTUE_Geometry` | 6 | 12 | 12 | 12 |
| `FTUE_Building_JewelryStore` | 6 | 12 | 12 | 12 |
| `BeautifulCorner_Startscreen_P` (menu) | 2 | 0 | 0 | 4 |

Every authored broken overlay (`SM_BookcaseB_GlassBrokenDoor`, glass only) has
exactly one intact glass pane in the same sublevel at **0.472 m**; the nearest
other pane is **≥ 0.838 m** (0.838 / 0.934 / 1.018 / 1.226 in the two clusters).
The frame door is *not* part of the authored broken mesh, so only the glass
pane is a leaf.

**Decision:** bind the existing pane nodes (split to one `MeshInstance3D` per
pane), never emit a leaf. Emitted-leaf census is unchanged: `gc_stats.leaves`
stays 166 authored / 168 placements / 79 in `Guildhall_Loot`; the binding adds
16 + 4 nodes and 0 new meshes in Guildhall. The menu level has no glass pane and
binds 0 (no container is spawned there).

## G-1 — containers

`tools/parse_containers.py` CLASSES + `level_loader.LOOT_CONTAINER_CLASSES`:

| class | kind | bucket | slots | extra spawners | lock (CDO) | breakable |
|---|---|---|---:|---:|---|---|
| `BP_Manor_Bookcase_Cabinet_MinorLoot_C` | minor | MinorLoot | 4 | 0 | cap 2 | `authored_breakable` / DisplayCase |
| `BP_Manor_Bookcase_Cabinet_MajorLoot_C` | major | MajorLoot | 1 | 1 (minor, 3 slots) | cap 3 | `authored_breakable` / DisplayCase |
| `BP_SmallSafe_MajorLoot_C` | major | MajorLoot | 1 | 1 (minor, 1 slot) | cap 3, `_locked=false` CDO | `disabled_component` |

Spawner choice is the authored `_primarySpawnerForActor` first, then the bucket
tier, then non-clue-mode as a tie-break. Measured nuance: no shipped spawner
authors `_primarySpawnerForActor: true` (all are `None`/`False`), so today the
bucket tier is the deciding rule; the flag preference is there for future data.
`_clueMode` is `ETATSpawnerClueMode::FromSpawnedActor` on the major spawner of
chest, display case, bookcase **and** safe, so it is provenance, not a
disqualifier. Extra spawners are preserved verbatim.

Measured container records (same 11-sublevel Guildhall set the free-play smoke
loads): **107 → 125 (+18)** = 8 minor bookcases + 2 POI major bookcases + 8
safes. The old 107 matches the RE-K-06 baseline exactly, and the runtime
`TAT-2 loot containers:` line prints 125.

Locks: only the 8 safes author `locked: true` (cap 2); the 10 bookcase markers
carry `max_lock_level` / `min_lock_level` deltas but **no `locked`** (the
bookcase `_locked` CDO default is false), so they stay unlocked and keep their
authored cap in the record. **Lock gate: applied 154 → 162 (containers 144 →
152, door_nodes 10).**

## G-2 — leaves / owner index

`level_loader.gd`:
* `SM_Manor_Bookcase_Cabinet_Door_Glass_2x8` joins the per-instance split so a
  single owner's pane can be hidden (same culling/shadow outcome as before).
* `_gc_static_glass` collects the pane nodes; `_build_gc_layers` matches each
  authored broken record to the nearest unused pane in the same sublevel within
  `GC_STATIC_LEAF_MATCH_M = 0.60` m (measured 0.472 vs ≥ 0.838).
* Owner index is now `{"leaves": [...], "broken": [...]}`;
  `gc_visuals_for()` returns the same shape and `bind_gc_visuals(leaves,
  broken)` takes arrays (single nodes are still normalised). `mission_controller`
  passes the arrays. `_gc_leaf` / `_gc_broken` remain first-of aliases for the
  A2 playtest.
* New measured result keys: `gc_static_leaves_bound`,
  `gc_static_leaves_unmatched`, `gc_static_leaf_multi`.

Measured: Guildhall_Loot probe load binds **16/16, 0 unmatched, 0 batched
panes**; a real Contract 02 mission (Loot + POI) binds **20**, `gc_layers=174`,
`leaves=80`, `visible_broken=0`, `missing=0`. A bookcase break hides both panes
and shows both authored broken overlays; the static pane count is unchanged
(no duplicate node).

## G-3 — break labels

`containers.json` rows now carry `breakable_source` resolved along the authored
`Super` chain (`BlueprintGeneratedClass.Super.ObjectPath`):

| class | source | owner | health row |
|---|---|---|---|
| ChestTrunk_MajorLoot | `authored_breakable` | BP_ChestTrunk_C | Chest_Basic |
| DisplayCaseA_MajorLoot | `authored_breakable` | BP_DisplayCaseA_C | DisplayCase |
| LootStash (secret) | `disabled_component` | — | — |
| Storefront_DisplayCaseB/D | `disabled_component` | — | — |
| Bookcase minor/major | `authored_breakable` | BP_Manor_Bookcase_Cabinet_C | DisplayCase |
| SmallSafe_MajorLoot | `disabled_component` | — | — |

`disabled_component` means no explicit `_isBreakable: true` exists in the chain
(the shared `BP_BreakableComponent_DisabledToggle` CDO default is false); the
safe also authors no GC overlay. Hold-F `break_container` stays the existing
labelled `PORT_DECISION`; no damage/health path was added.

## Gates run in the worktree (serial, headless)

| gate | result |
|---|---|
| compile | `scripts checked: 217, broken: 0` |
| `run_tests.gd` | `SUMMARY: fails=0` (324 PASS) |
| E2E `all` | `fails=0 passed=300 total=300` |
| E2E tier a2 | `fails=0 passed=22 total=22`; `gc layers=174 leaves=80 static_bookcase_leaves=20 visible_broken=0 missing=0` |
| E2E tier p2, regenerated data (private copy) | `fails=0 passed=17 total=17`, `unexpected_fail=0` |
| E2E tier p2, current shared data | 16/17 — only `P2-CENSUS-CONTAINERS` (5 classes, wants 8) until regen |
| `probe_gc_destruction.gd` | `GC_PROBE checks=52 fails=0` (was 44) |
| `probe_lock_inventory.gd` | `applied=162 containers=152 door_nodes=10` PASS |
| `test_gc_break_trigger.gd` | `GC_TRIGGER checks=21 fails=0` |
| `runtime_smoke.sh 90` | PASS, exit 124, `errors=0`, `mission_ready=1` (125 containers) |
| `make test-producers` | PASS (all `tools/test_*.py`) |
| `make gate-ratchet` | PASS (committed evidence untouched) |
| `make audit` | **expected red**: `producer tools/parse_containers.py changed since the baseline` — needs the integrator regen + `--refresh-stamps`. (A worktree also needs `tools/bin` symlinked for the vgmstream check; gitignored.) |

## Integrator must do

1. `python3 tools/parse_containers.py` (or `make normalize`) → `containers.json`
   becomes 8 classes; the three K-06 rows carry 4/1/1 slots, one extra spawner
   for each major row, `breakable_source`, `lock_config`.
2. `make audit-refresh-stamps REASON='parse_containers emits the K-06 bookcase/safe rows (Phase 2 G-1)'`
   (new producer hash + containers record/class counts), then `make audit`.
3. Re-run the 45-gate set; raise (never lower) the ratchet floors:
   * `lock_inventory`: `applied 154 → 162`, `containers 144 → 152`,
     `door_nodes 10` (unchanged);
   * `probe_gc_destruction` log line: `checks 44 → 52`;
   * `e2e_a2`: `A2-GC-STATS` now also requires `static_bookcase_leaves ≥ 20`;
   * `e2e_p2`: 14 → 17 checks (three new: `P2-CENSUS-CONTAINERS`,
     `P2-CENSUS-CONTAINER-MARKERS`, `P2-CENSUS-BOOKCASE-STATIC`), zero groups
     unchanged.
4. Update `docs/FIDELITY_GAPS.md`, `HANDOFF_NEXT_AGENT.md` and the wave report
   with the 107→125 container jump, the 154→162 lock jump, and the “bind, never
   duplicate” bookcase rule.

## Remaining gaps (recorded, not invented)

* `BP_UtilityBoxA_MinorLoot_C` (1 marker, POI 3rd floor) still has no
  `containers.json` row / allowlist entry; 1 authored container remains
  unopenable. Out of G-1 scope.
* Multi-slot containers still spawn **one** loot item (pre-existing container
  behaviour; the record carries all authored slots). Not changed here.
* A bookcase owner with broken overlays but no static glass pane would bind 0
  leaves (`gc_static_leaves_unmatched`); the menu level is the only such case
  and spawns no container.
