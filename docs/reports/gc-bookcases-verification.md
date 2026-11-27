# GC / bookcases lane — independent verification

**Lane:** Phase 2 GC / bookcases (plan §5, G-1..G-3)
**Worktree:** `/home/john/.local/share/opencode/worktree/318f41/phase2-gc`
**Branch:** `phase2-gc-bookcases`
**Commit:** `7dbb78c` `feat(gc): bookcase/safe containers + static-batch bookcase leaves (G-1..G-3)`
**Base:** `79d8b8a` (one commit; `git rev-list --count 79d8b8a..7dbb78c` = 1)
**Verdict: PASS** for the lane's code, data and structural claims. Runtime gate numbers
are consistent with the code/data and the lane's retained logs, but the final
A2/GC/lock/smoke runs were **not independently re-executed** here: this verification
was read-only and forbidden from running Godot. See “Residual evidence gap”.

Method: read the plan §5, `docs/reports/lane-gc-bookcases-20261127.md`, the full
`79d8b8a..7dbb78c` diff and the generated payload; reproduce the producer, the p2
checks, the lock probe and the GC census in Python; run the non-Godot gates
(`make test-producers`, `check_gate_ratchet.py`, `manifest_audit.py`). No GPU,
Steam or Godot was run; the only file written is this report.

---

## 1. Scope, commit and push state — PASS

`git show --name-status 7dbb78c`:

```
A  docs/reports/lane-gc-bookcases-20261127.md
M  game/src/core/level_loader.gd
M  game/src/interact/loot_container.gd
M  game/src/missions/mission_controller.gd
M  game/tests/e2e/e2e_a2_playtest.gd
M  game/tests/e2e/e2e_p2_parity.gd
M  game/tests/probe_gc_destruction.gd
M  tools/parse_containers.py
```

* No file under `extracted/`, `game/assets/ue/` or `game/data/generated/` is touched.
* No `docs/FIDELITY_GAPS.md`, `HANDOFF_NEXT_AGENT.md`, ratchet or gate-log edit — the
  lane report correctly hands those to the integrator.
* **No push:** `git branch -vv` shows no upstream for `phase2-gc-bookcases`;
  `git branch -r --contains 7dbb78c` is empty; `origin/main` is `7de2f0c` and
  `git log origin/main..HEAD` contains only `7dbb78c`.
* Worktree was clean before this report (`git status --short` empty).

## 2. G-1 — three classes, rows and primary spawner — PASS

`tools/parse_containers.py` `CLASSES` and `level_loader.LOOT_CONTAINER_CLASSES`
both contain exactly the same three new classes:

| class | kind | bucket | slots | extra spawners | breakable_source | health row | class lock cap |
|---|---|---|---:|---:|---|---|---:|
| `BP_Manor_Bookcase_Cabinet_MinorLoot_C` | minor | `DA_SpawnBucket_MinorLoot` | 4 | 0 | `authored_breakable` (`BP_Manor_Bookcase_Cabinet_C`) | `DisplayCase` | 2 |
| `BP_Manor_Bookcase_Cabinet_MajorLoot_C` | major | `DA_SpawnBucket_MajorLoot` | 1 | 1 (`TATLootContainerSpawnerMinor_GEN_VARIABLE`, 3 slots) | `authored_breakable` (`BP_Manor_Bookcase_Cabinet_C`) | `DisplayCase` | 3 |
| `BP_SmallSafe_MajorLoot_C` | major | `DA_SpawnBucket_MajorLoot` | 1 | 1 (`TATLootContainerSpawnerMinor_GEN_VARIABLE`, 1 slot) | `disabled_component` | — | 3 (`_locked=false` CDO) |

The committed producer was run into the private root
`/tmp/opencode/gc-producer` (script sha256 is identical to the committed file:
`1d191cfb0f3925154ae75a6dda830ccbe61a73bbe4c4ab5ef98c8f5004261aec`); it emits
**8 classes**, 10,594 bytes, sha256
`d37ccd83a87f79ab3fc0954af2037916ccf7c4de61be5475f27e82b3050c53d5`. A rerun
reproduces that hash byte-for-byte.

Primary-spawner preference is implemented in `pick_primary_spawner()` in the
order the report gives: `_primarySpawnerForActor == true`, then the kind's bucket
tier, then non-clue-mode, then authored order. `extra_spawners` are preserved.
Measured nuance: **no shipped spawner authors `_primarySpawnerForActor: true`**
(they are `None`/`False` in all eight Blueprints), so today the bucket tier is
the deciding rule. The major spawners of chest/display case/bookcase/safe carry
`_clueMode = ETATSpawnerClueMode::FromSpawnedActor`; the producer correctly does
not treat that as a disqualifier. This matches the report's table; only the
prose “the authored primary first” could be read as implying the flag was used.

## 3. G-1 — 107 → 125 and locks 154 → 162 — PASS

Loading the 11 Guildhall sublevels the free-play/A2 path actually loads:

| class | old allowlist | new allowlist |
|---|---:|---:|
| `BP_ChestTrunk_MajorLoot_C` | 48 | 48 |
| `BP_DisplayCaseA_MajorLoot_C` | 31 | 31 |
| `BP_LootStashInteractable_Secret_ThinWall_C` | 24 | 24 |
| `BP_Storefront_DisplayCaseB_MinorLoot_C` | 2 | 2 |
| `BP_Storefront_DisplayCaseD_MinorLoot_C` | 2 | 2 |
| `BP_Manor_Bookcase_Cabinet_MinorLoot_C` | 0 | 8 |
| `BP_Manor_Bookcase_Cabinet_MajorLoot_C` (POI) | 0 | 2 |
| `BP_SmallSafe_MajorLoot_C` | 0 | 8 |
| **total** | **107** | **125** |

`+18 = 8 minor bookcases + 2 POI major bookcases + 8 safes`. The four other
Guildhall base files (Contracts, SetSpawners, MissionClues, Contract_02) carry
0 container markers, so the 15-file base and the 11-file loaded set are both
125. The runtime `TAT-2 loot containers:` line therefore prints 125.

All-level marker count moves 254 → 273 (+19): the extra +1 is the one
`BP_Manor_Bookcase_Cabinet_MinorLoot_C` in `OldManor_Geo` (recorded in the
producer docstring). The integrator's audit refresh must account for that +19
when it re-stamps the `containers` metric; it is not a lane defect.

Lock inventory, scanned over all 107 `.tatlevel.json` files with the probe's
`(class, rounded pos)` dedupe and its window/`can_lockpick` door filter:

| allowlist | locked containers | door nodes | applied | raw locked |
|---|---:|---:|---:|---:|
| old (5 classes) | 144 | 10 | 154 | 363 |
| new (8 classes) | 152 | 10 | **162** | 363 |

Only the 8 safes author `locked: true` and `max_lock_level == 2`; the 10
bookcase markers author `max_lock_level`/`min_lock_level` deltas but **no
`locked`**, so they do not reach `set_locked`. `162 = 152 + 10` exactly. The
report's numbers are correct.

## 4. G-2 — static glass, distances and leaf census — PASS

Payload measurements (raw `.tatlevel.json` positions; same coordinates the
loader uses):

| level | glass panes | bookcase GC records | one-to-one matches | max pair distance | nearest other pane |
|---|---:|---:|---:|---:|---:|
| `Guildhall_Loot` | 16 | 16 | 16 | 0.472 m | 0.838 m |
| `Building_Guildhall_POI` | 4 | 4 | 4 | 0.472 m | 1.226 m |
| A2 11-sublevel load (POI + Loot + others) | 20 | 20 | 20 | 0.472 m | — |

The Guildhall_Loot second-nearest set is `0.838 / 0.934 / 1.018 / 1.226 /
1.619 / 6.605 / 67.515 m` after earlier matches consume the paired panes; the
minimum is 0.838 m. The 0.60 m `GC_STATIC_LEAF_MATCH_M` bound is therefore a
unique match, and the loader's 0.472 m measurement is reproduced exactly.

Loader implementation (read, not run): `GC_BOOKCASE_GLASS_MESH` joins the
per-instance split (`per_instance = true`), each pane becomes a `MeshInstance3D`
with `count == 1`, `_gc_static_glass` collects the nodes, and
`_build_gc_layers()` matches each authored bookcase broken record to the nearest
unused pane in the **same `source_sublevel`** within 0.60 m. The panes are not
added to the `gc_leaves` group; they are bound as the owner's leaves. The
`gc_static_leaves_bound` / `gc_static_leaves_unmatched` / `gc_static_leaf_multi`
keys are copied through `_finalize()`. A2 uses `load_sublevels_async`, which
calls `_finalize()`, so the key is visible to the A2 check.

Leaf census is unchanged:

* 107 generated level files: `components=336`, `hidden=336`,
  `visible_emitted=0`, `unresolved=0`, `fallback_broken=93`, `sibling_smc=5`,
  `leaves=166`; placement leaves 168 (probe constants unchanged).
* `Guildhall_Loot`: `components=95`, `leaves=79` (48 chest + 31 display-case;
  bookcases emit 0 leaves).
* The static binding adds 16 (Loot) + 4 (POI) = 20 nodes and **0** emitted
  leaves. `gc_leaves_built` stays 79 in the probe and 80 in A2.

## 5. G-2 — owner index arrays — PASS

`level_loader.gd` now stores `_gc_owner_index[owner] =
{"leaves": Array[Node3D], "broken": Array[Node3D]}`; `gc_visuals_for()`
returns the same shape (empty arrays for an unknown owner), `_gc_owner_slot()`
preserves both arrays, and bookcase static panes are appended to `leaves`.
`loot_container.bind_gc_visuals(leaves, broken)` accepts arrays and still
normalises a single `Node3D`; `_gc_leaf`/`_gc_broken` remain first-of aliases
for A2. `mission_controller` passes both arrays. `has_broken_overlay()` and
`_apply_gc_visuals()` iterate the arrays. `test_gc_break_trigger.gd` still calls
`bind_gc_visuals(leaf, broken)` with single nodes and remains compatible.

Probe consequences (data-verified): 95 broken layers = 48 chest + 31 display +
16 bookcase; 87 owners = 79 emitted-leaf containers + 8 bookcase owners now
paired with 16 static panes; 0 broken-only owners; `gc_owner_count=87`.

## 6. G-3 — break labels; G-4 not claimed; utility box — PASS

Produced rows:

| class | breakable_source | owner | health row |
|---|---|---|---|
| `BP_ChestTrunk_MajorLoot_C` | `authored_breakable` | `BP_ChestTrunk_C` | `Chest_Basic` |
| `BP_DisplayCaseA_MajorLoot_C` | `authored_breakable` | `BP_DisplayCaseA_C` | `DisplayCase` |
| bookcase minor/major | `authored_breakable` | `BP_Manor_Bookcase_Cabinet_C` | `DisplayCase` |
| `BP_LootStashInteractable_Secret_ThinWall_C` | `disabled_component` | — | — |
| `BP_Storefront_DisplayCaseB/D_MinorLoot_C` | `disabled_component` | — | — |
| `BP_SmallSafe_MajorLoot_C` | `disabled_component` | — | — |

The labels follow the authored `Super` chain (`_isBreakable: true` required);
hold-F `break_container()` is unchanged and remains the labelled
`PORT_DECISION`; no health/damage path was added.

**G-4 is not claimed:** the lane report says the extractor `json` stage and
`Destructibles/` are absent, confirms nothing and predicts
`fallback_broken=93` becoming mesh-resolved later. The payload still reports
93, and neither the commit nor the report claims a G-4 result.

**Utility box:** `BP_UtilityBoxA_MinorLoot_C` has one marker in
`Building_Guildhall_POI_3rdFloor` and carries a
`TATContainerSpawnerComponent` (minor bucket, 2 slots), but it is still outside
`CLASSES`/`LOOT_CONTAINER_CLASSES`/`containers.json`. The report records it as
one authored container remaining unopenable and out of G-1 scope. Correct.

## 7. Gate evidence

| Gate | Verdict | Evidence |
|---|---|---|
| compile 217/0 | PASS (structural) | `find game -name '*.gd' \| wc -l` = 217; commit adds no `.gd`; base gate is 217/0. Not re-run (no Godot). `gdparse` (gdtoolkit, not Godot) parses the five other modified `.gd` cleanly; it rejects `level_loader.gd` at the pre-existing `set` identifier (`var set` / `set.get`, lines 2995-2996), so the Godot compile gate remains the authority for that file. |
| `run_tests` 324/0 | PASS (retained log) | `/tmp/opencode/gc-run_tests.log`: 324 `PASS:` lines, `SUMMARY: fails=0`; no suite registration changed. Log predates the final commit. |
| E2E `all` 300/300 | PASS (retained log) | `/tmp/opencode/gc-e2e.log`: `SUMMARY: fails=0 passed=300 total=300`; A2 counted 22 `PASS: [A2…]`. Log predates the final A2 assertion. |
| A2 22/22 + static 20 | PASS (count + data) | 23 `h.require` sites base and head, 22 executed; only the existing `A2-GC-STATS` check changed. A2 11-sublevel set has 20 glass and 20 bookcase GC, matched 20 at 0.472 m. Final A2 log not retained. |
| p2 17 (regen) / 16 (stale) | PASS (reproduced) | `h.require` sites 14 → 17. With shared 5-class `containers.json`: only `P2-CENSUS-CONTAINERS` fails → 16/17. With the private 8-class output: all three new checks pass → 17/17. |
| GC probe 52/0 | PASS (count + data) | 45 `_check` sites base (one loader-null conditional unexecuted → 44), 53 head (same conditional → 52), +8 new checks; all 8 are reachable with the measured data (bookcase found, 2 leaves + 2 broken, 16 static panes, binding exact, break hides both, signals, no duplicate). Final log not retained. |
| lock 162/152/10 | PASS (reproduced) | Exact all-level scan: old 144+10=154; new 152+10=162; raw 363 unchanged. |
| runtime smoke | PASS (data; exit/errors reported) | 125 container markers in the loaded Guildhall set; report says exit 124, errors=0. Final log not retained. |
| `make test-producers` | PASS (ran) | Exit 0; 8 `tools/test_*.py` scripts; final suite `Ran 9 tests … OK`. |
| `make gate-ratchet` | PASS (ran) | `check_gate_ratchet.py`: `GATE_RATCHET: PASS (baseline and committed evidence agree; Godot gates run locally)`. |
| `make audit` | EXPECTED RED (matches report) | `AUDIT FAILED: 1 failure(s)`: `baseline: producer tools/parse_containers.py changed since the baseline (sha256 e8013b9ac24e -> 1d191cfb0f39); regenerate … then run --refresh-stamps`. This is the documented integrator step, not a lane failure. |

## 8. Worktree traps and shared data — PASS

* `game/data/generated` is a symlink to `/home/john/Projects/TAT-2/game/data/generated`; the shared
  `containers.json` is still the old 4,224-byte 5-class file, mtime
  `2026-11-26 22:16:58` — before the lane. The shared `game/data` was **not**
  regenerated.
* The producer was run from `/tmp/opencode/gc-producer` (script hash identical to
  the commit) into a private `containers.json` (10,594 bytes, 8 classes,
  sha256 `d37ccd83…`). This is the regenerated output the p2 17/17 claim uses.
* `tools/bin` is symlinked (gitignored) and `game/.godot` exists, so the
  worktree can run the audit/vgmstream path. `git status --short` is clean
  except this new report.
* The audit failure is exactly the producer-hash drift the report predicts;
  no other audit failure appeared.

## 9. Findings and caveats (non-blocking)

1. **Residual evidence gap (not a contradiction).** The retained
   `/tmp/opencode/gc-e2e.log` was written before the final A2 assertion and
   shows the old `A2_MEASURE gc layers=174 leaves=80` line without
   `static_bookcase_leaves`. No retained final logs exist for A2 static 20,
   GC 52, lock 162, p2 17 or the 125-container smoke. The claim is still
   exact from code/payload (and p2 17/16 is reproducible), but the integrator
   should record the final 45-gate logs in `docs/reports/logs/final/` when it
   runs the merged tree.
2. **Producer wording.** `tools/parse_containers.py` now says it emits “every
   placed loot-container Blueprint that carries a
   `TATContainerSpawnerComponent`”. That is not literally true:
   `BP_UtilityBoxA_MinorLoot_C` has one and is deliberately outside `CLASSES`;
   the lane report correctly records it. The `# P2-4: … a 6th container
   Blueprint` comment is stale now that the allowlist has 8 classes, and the
   `WARN: container-shaped Blueprint outside CLASSES` scan's token list
   (`Container/Stash/DisplayCase/Chest/LootStash`) does not match
   `UtilityBox`, so it does not print that gap. Prefer “every allowlisted
   Blueprint” and either add `UtilityBox` to the warning tokens or drop the
   “every” claim.
3. **Primary-flag nuance.** The `_primarySpawnerForActor` preference is
   implemented but not exercised by shipped data (all values are `None`/`False`);
   the bucket tier decides. The report's table is correct; the prose could say
   this explicitly.
4. **A2 layers detail.** `gc layers=174` is the raw `gc` record count over the 11
   loaded sublevels (POI 30 + Loot 95 + others), not the sum of
   `gc_stats.hidden_emitted` (157). This is the pre-existing A2 measurement and
   does not affect the static 20 or leaf 80 figures.

No functional defect was found. The lane is accepted; the integrator still owns
the data regeneration, audit re-stamp, ratchet raise (lock
`applied 162 / containers 152 / door_nodes 10`, GC `checks 52`, p2 `17`,
A2 `static_bookcases ≥ 20`) and the merged 45-gate run.

**Report path:** `docs/reports/gc-bookcases-verification.md`
