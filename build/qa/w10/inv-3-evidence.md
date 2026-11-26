# INV-3 — W10-A evidence baselines (fact sheet)

Scope: measure the CURRENT baselines that the W10-A evidence worker must extend.
Every number below comes from a real run or a real file read in this worktree.
No existing file was edited; no probe was modified; nothing was committed.

| | |
|---|---|
| worktree | `/home/john/Projects/TAT-2-rem-w10-a` |
| branch | `rem/w10-a` (the brief says `w10/a`; `git rev-parse --abbrev-ref HEAD` → `rem/w10-a`) |
| HEAD | `29046c8e41bb3766f745da32c0f4ab27c4a76582` |
| measured | 2026-11-25, this session |
| raw logs | `/tmp/opencode/w10-inv3/` (not committed; each section names its file) |
| Godot | `tools/godot` 4.7.2, every run under `flock /tmp/opencode/tat2-godot.lock`, one at a time, `pgrep -a -f "godot.*--path game"` empty before each |
| data | `game/assets`, `game/data/generated`, `extracted` are the shared read-only symlinks (untracked in this worktree) |

Note: the worktree also contains untracked `game/tests/test_w10_runtime.gd` and
`game/tests/test_w10_screens.gd` from other W10 lanes. They are unrelated to the
three probes measured here and were not touched.

Reproduce everything in this sheet with:

```bash
cd /home/john/Projects/TAT-2-rem-w10-a
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/probe_collision_authored.gd'
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/probe_lock_inventory.gd'
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/test_w9p4_statetree.gd'
python3 build/qa/w9/p3_string_audit.py
```

---

## 1. Collision probe baseline (Guildhall, 15 sublevels, unmodified probe)

Command (raw log: `/tmp/opencode/w10-inv3/collision-guildhall.log`, exit 0):

```bash
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/probe_collision_authored.gd'
```

Verbatim decisive lines:

```
COL_AUDIT mode=authored placed_meshes=947 placed_meshes_seen=947 placed_instances=27222 authored_hull=937 authored_prims=599 absent=10 no_collision=7 query_only=7 reduced=16 shapes=30901 bodies=243 dropped=0 load_ms=19748 coverage=0.989 fps_pose=n/a
COL_DETAIL payload_meshes=1992 payload_elements=8601 payload_convex=5922 payload_load_ms=300 authored_instances=24404 authored_shape_demand=27767 heuristic_shapes=3511 mode_requested=authored elements_on_placed=2184 convex_on_placed=899 complex_default_paths=70 placed_paths_payload=947 scale_baked_shapes=4008
COL_ASSERT coverage=0.989 (937/947) prims_subset=true classification=937+10==947 mode=authored dropped=0
COL_WALL total_ms=19889 (probe must stay well under 60 s)
AUTHORED_COLLISION meshes=947 hull=937 prims=599 convex=899 absent=10 no_collision=7 query_only=7 reduced=16 shapes_per_instance_avg=1.14 elements=2184 load_ms=300
```

Baseline numbers to keep: **947 placed paths, 27 222 placed instances, 937
authored hull paths, 10 absent, coverage 0.989, reduced=16, shapes 30 901,
bodies 243, dropped=0, load 19.7 s** (probe bugs the run at 60 s). No
`SCRIPT ERROR`/`SHADER ERROR` in the log (grep count 0).

What the probe does **not** have today (the W10-A gap):
- it never prints the **name** of a reduced mesh, and `AuthoredCollision.stats()`
  (`game/src/core/collision/authored_collision.gd:181-188`) only returns
  `meshes/elements/convex/load_ms` — there is no reduced-name list anywhere;
- it hard-codes the 15 Guildhall sublevels (`probe_collision_authored.gd:46-62`);
  OldManor and FTUE are not loaded;
- `MIN_AUTHORED_COVERAGE := 0.95` (`:63`) — the brief's "fails below 0.95" is
  already true for `dropped`/classification/coverage, but there is no
  OldManor/FTUE assertion at all.

The brief also cites "97.9 % emitted / 98.9 % probe". Only **98.9 %** is
reproduced here (`coverage=0.989 = 937/947`). The 97.9 % figure is NOT
MEASURED by this probe and I could not find a jq/report line that produces it
(`grep -rn "97.9\|0.979" docs/reports/*.md build/qa/w9/*.md` has no hit).

### 1b. OldManor and FTUE sublevel lists (resolved, all files exist)

`game/src/missions/mission_controller.gd:978-1032`, verbatim:

```gdscript
func _map_id_to_sublevels(map_id: String, order: int = 2) -> Array[String]:
	# Base map geometry/gameplay/loot lists (kept as extracted). The old
	# zero-padded Contract-number wildcard entry is gone: real per-contract
	# sublevels from the extracted tables (GameData.get_contract_sublevels)
	# are appended when present, never duplicating a path.
	var base: Array[String] = []
	match map_id:
		"old_manor":
			base = [
				"res://data/generated/levels/OldManor/OldManor_P.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Geo.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Landscape.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Gameplay.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Loot.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_PickUps.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Clues.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_Contracts.tatlevel.json",
				"res://data/generated/levels/OldManor/OldManor_SkyboxGeo.tatlevel.json",
			]
		"guildhall":
			base = [
				"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json",
				"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI_3rdFloor.tatlevel.json",
				"res://data/generated/levels/Buildings/Guildhall/Guildhall_Vault_CeremonialChambers.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_P.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Geometry.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_LightingNoGameplay.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_LocalVolumetric.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Loot.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_Contracts.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_SetSpawners.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_MissionClues.tatlevel.json",
				"res://data/generated/levels/Guildhall/Guildhall_SkyboxGeo.tatlevel.json",
			]
		"thieves_den":
			base = [
				"res://data/generated/levels/ThievesDen/ThievesDen_Geo.tatlevel.json",
				"res://data/generated/levels/ThievesDenTest/ThievesDenTest_P.tatlevel.json",
				"res://data/generated/levels/ThievesDenTest/ThievesDenTest_Periphery.tatlevel.json",
			]
		"ftue":
			# Steam's tutorial map set. The old key was "jaspering_hall", a scene
			# that does not exist in the shipped game, and it loaded only 4 of the
			# 10 authored FTUE sublevels.
			for ftue_sub: String in GameData.get_ftue_sublevels():
				base.append("res://data/generated/levels/FTUE/%s.tatlevel.json" % ftue_sub)
	if base.is_empty():
		return base
	for sub: String in GameData.get_contract_sublevels(order):
		if not base.has(sub):
			base.append(sub)
	return base
```

FTUE's list comes from `game/src/core/game_data.gd:511-523`, verbatim:

```gdscript
func get_ftue_sublevels() -> Array[String]:
	return [
		"FTUE_P",
		"FTUE_Checkpoints",
		"FTUE_AI",
		"FTUE_Fairy",
		"FTUE_TutorialRunner",
		"FTUE_Building_JewelryStore",
		"FTUE_Building_SpawnArea",
		"FTUE_Gameplay",
		"FTUE_Geometry",
		"FTUE_Audio",
	]
```

`get_contract_sublevels(order)` (`game_data.gd:648-660`) walks
`contracts[order-1].sublevels` (populated from `contracts.json`
`sublevels_ue_paths` by `_load_contracts_json`, `game_data.gd:604-612`),
converts with `_ue_sublevel_to_res` and keeps only files that exist. So the
contract append is **per contract order, not per map**.

OldManor — 9 base files, all exist:

| # | file | exists |
|---:|---|---|
| 1 | `OldManor/OldManor_P.tatlevel.json` | yes (976 744 B) |
| 2 | `OldManor/OldManor_Geo.tatlevel.json` | yes (5 686 492 B) |
| 3 | `OldManor/OldManor_Landscape.tatlevel.json` | yes |
| 4 | `OldManor/OldManor_Gameplay.tatlevel.json` | yes |
| 5 | `OldManor/OldManor_Loot.tatlevel.json` | yes |
| 6 | `OldManor/OldManor_PickUps.tatlevel.json` | yes |
| 7 | `OldManor/OldManor_Clues.tatlevel.json` | yes |
| 8 | `OldManor/OldManor_Contracts.tatlevel.json` | yes |
| 9 | `OldManor/OldManor_SkyboxGeo.tatlevel.json` | yes |

FTUE — 10 base files, all exist:

| # | file | exists |
|---:|---|---|
| 1 | `FTUE/FTUE_P.tatlevel.json` | yes |
| 2 | `FTUE/FTUE_Checkpoints.tatlevel.json` | yes |
| 3 | `FTUE/FTUE_AI.tatlevel.json` | yes |
| 4 | `FTUE/FTUE_Fairy.tatlevel.json` | yes |
| 5 | `FTUE/FTUE_TutorialRunner.tatlevel.json` | yes |
| 6 | `FTUE/FTUE_Building_JewelryStore.tatlevel.json` | yes |
| 7 | `FTUE/FTUE_Building_SpawnArea.tatlevel.json` | yes |
| 8 | `FTUE/FTUE_Gameplay.tatlevel.json` | yes |
| 9 | `FTUE/FTUE_Geometry.tatlevel.json` | yes (11 964 644 B) |
| 10 | `FTUE/FTUE_Audio.tatlevel.json` | yes |

**Contract-only sublevels** (`contracts.json` → `sublevels_res_paths`, file
exists check):

| order | map | contract-only file | exists | meshes in it |
|---:|---|---|---|---:|
| 1 | thieves_den | — (0 sublevels) | — | — |
| 2 | guildhall | `Guildhall/Guildhall_Contract_02.tatlevel.json` | yes | 0 (2 actors) |
| 3 | old_manor | `OldManor/OldManor_Contract03.tatlevel.json` | yes | 0 (2 actors) |
| 4 | guildhall | `Guildhall_Contract_04`, `Guildhall_Contract_Teleporters` | yes ×2 | 0 |
| 5 | old_manor | `OldManor_Contract05` | yes | 0 |
| 6 | guildhall | `Guildhall_Contract_06` | yes | 0 |
| 7 | old_manor | `OldManor_Contract07` | yes | 0 |
| 8 | old_manor | `OldManor_Contract08` | yes | 0 |
| 9 | guildhall | `Guildhall_Contract_09` | yes | 0 |
| 10 | old_manor | `OldManor_Contract10` | yes | **2** (`FXSHAPES_1_FXQuadPivotDownEdge` ×2) |
| 11 | guildhall | `Guildhall_Contract_11` | yes | 0 |
| 12 | old_manor | `OldManor_Contract12` | yes | 0 |
| 13 | guildhall | `Guildhall_Contract_13` | yes | 0 |
| 14 | old_manor | `OldManor_Contract14` | yes | 0 |
| 15 | guildhall | `Guildhall_Contract_15` | yes | 0 |
| 16 | guildhall | `Guildhall_Contract_16` | yes | 0 |

Therefore:

- **FTUE** (tutorial route sets `GameState.active_contract_order = 0`,
  `game/src/ui/main_menu.gd:720-725`) → `get_contract_sublevels(0)` is empty →
  loads exactly the **10 base files**, no contract-only file.
- **OldManor** is deployed by contracts 3, 5, 7, 8, 10, 12, 14 → loads the
  **9 base files + exactly one contract-only file** for that order. Only order
  10's contract file carries meshes (2 VFX quads, `mesh_collision.json` has no
  record for `FXSHAPES_1_FXQuadPivotDownEdge`, so they take the heuristic path).

Caveat for the probe author: calling `_map_id_to_sublevels("ftue")` with the
function's **default `order = 2` appends `Guildhall_Contract_02`** to an FTUE
load (the append is order-keyed, not map-keyed). A faithful probe should pass
`order = 0` for FTUE and the real contract order for OldManor, or use the base
lists explicitly and say so.

---

## 2. Reduced-mesh census — STATIC REPLAY (a prediction, not a probe run)

**This section is static analysis of `mesh_collision.json` + the level JSONs.
It is not a measurement of emitted colliders.** It is validated against the one
measured counter we have (§1, Guildhall `reduced=16`).

Rule, `game/src/core/collision/authored_collision.gd`:

```gdscript
# :69-72
## Per-mesh element cap: above this a convex set coalesces to one hull of
## element AABBs. 16 keeps every door frame / arch / stair flight / pitched roof
## in the load set per-element; the meshes it touches are 20+ hull detail props.
const MAX_CONVEX_ELEMENTS_PER_MESH: int = 16
# :73-77
## Extra-shape budget per mesh, `(elements - 1) * instances`. 250 was chosen
## from the measured curve: 150 -> 29.6 k shapes, 250 -> 30.9 k, 300 -> 31.2 k,
## 400 -> 32.2 k (over MAX_TOTAL_SHAPES). Single-element meshes cost 0 here, so
## a one-hull mesh with 1,000 instances is never degraded.
const MAX_ELEMENT_SHAPE_COST: int = 250
# :270-277
	var n: int = maxi(instances, 1)
	if els.size() > MAX_CONVEX_ELEMENTS_PER_MESH or (els.size() - 1) * n > MAX_ELEMENT_SHAPE_COST:
		shapes.append(_coalesce_element_aabbs(els))
		offsets.append(Transform3D.IDENTITY)
		out["reduced"] = true
		out["source"] = "hull"
```

Only meshes that reach this branch can reduce: record present, `collision_enabled
!= NoCollision`, `complex_as_simple != true`, non-empty elements, at least one
`convex` element. `instances` is the loader's **per-load placement count**
(`level_loader.gd:2000-2004`, `_col_path_counts`), not the raw JSON count.

### 2a. The four meshes the brief names

| mesh | elements (all convex) | instances in the level JSONs | rule that reduces it |
|---|---:|---:|---|
| `/Game/Art/Environment/OldManor/SM_OldManor_Doorway_4x650` | 14 | **37** (all in `OldManor_Geo`) | `(14-1)*37 = 481 > 250` (cost cap; 14 ≤ 16) |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Tower_VaultRoom` | **112** | 1 (`OldManor_Geo`) | `112 > 16` (element cap) |
| `/Game/Art/Environment/OldManor/SM_OldManor_Tower_Stairs_4x850` | **36** | 1 (`OldManor_Geo`) | `36 > 16` (element cap) |
| `/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_BayWindow_Open_6x6_4m` | **22** | 2 (`FTUE_Building_SpawnArea`) | `22 > 16` (and `(22-1)*2 = 42 ≤ 250`) |

All four are `collision_enabled` absent (physics default), `complex_as_simple`
absent, 100 % convex elements — so all four are genuinely reduce-eligible.

### 2b. Per map sublevel set

Model used (matches the loader's collidable census): one instance per
`(mesh, pos, basis, scale)` tuple (the loader dedupes exact duplicates,
`level_loader.gd:3302-3308`), minus the `skyboxgeo` sublevel (the only
`DECORATIVE_SUBLEVEL_TOKENS` entry, `level_loader.gd:434-438`, which the loader
puts in `batches_nocol`/`batches_far`, `level_loader.gd:3137-3141`), minus the
`CLUTTER_TOKENS` paths (`level_loader.gd:430-433`, `_fill_col_path_counts`
`:5101-5102`).

| set | raw mesh records | raw distinct paths | model instances | model paths | multi-element paths (>1) | their instances | **reduced paths (predicted)** | reduced instances |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| OldManor (9 base files) | 23 383 | 759 | 20 616 | 703 | 247 | 3 537 | **36** | 297 |
| FTUE (10 base files) | 37 426 | 582 | 36 504 | 560 | 174 | 6 249 | **20** | 1 788 |
| Guildhall (15 base files) | 63 578 | 1 006 | 28 042 | 964 | 317 | 4 772 | **16** | 962 |

Validation of the model: on Guildhall it predicts **16** reduced paths and the
real probe reports **`reduced=16`** (§1). That is the only coincidence that
matters, but it is exact. Residual: the model counts 28 042 collidable
instances vs the probe's 27 222 (−820, 2.9 %) because per-instance CPD/colour
batches are skipped from collision (`level_loader.gd:5098-5099`) and
`str(Transform3D)` dedupe differs slightly from exact JSON-tuple dedupe; this
does not change the reduced set on Guildhall.

So the brief's "~36 reduced meshes on OldManor including
`SM_OldManor_Doorway_4x650` (x37), `Tower_VaultRoom`, `Tower_Stairs_4x850`, and
FTUE `BayWindow_Open_6x6_4m`" is **reproduced** (36 / 20), but the probe must
print the names it actually reduces at load time — not this table — because
`instances` is the loader's count and the model can drift when generated data
changes.

### 2c. The full predicted lists (what the probe should print, for comparison)

See **Appendix A** for the 36 OldManor and 20 FTUE rows (mesh, elements,
instances, rule).

---

## 3. Lock probe baseline

Command (raw log: `/tmp/opencode/w10-inv3/lock-inventory.log`, exit 0):

```bash
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/probe_lock_inventory.gd'
```

Verbatim decisive lines:

```
  family totals: containers=157 doors=8 windows=8 total=173
  authored MaxLockLevel over the locked actors: nonex15, 1x3, 2x155
  ok: placed `_locked: true` total = 173 (got 173)
  ok: authored containers = 157 (got 157)
  ok: authored doors = 8 (got 8)
  ok: authored windows = 8 (got 8)
  ok: authored cap 2 count = 155 (got 155)
  ok: authored cap 1 count = 3 (got 3)
  ok: locked actors with no MaxLockLevel = 15 (got 15)
  authored-locked containers inside LOOT_CONTAINER_CLASSES: 144
  authored-locked containers outside the allowlist (never spawned): BP_BookcaseB_C(2), BP_ChestTrunk_C(3), BP_SmallSafe_MajorLoot_C(8)
  authored-locked windows: 8 (no window interaction in the port; not locked)
  authored-locked key-only doors excluded (no key inventory): 4 (3 BP_VaultDoor_Sliding_C + 1 BP_Res_Int_Doorway_C)
  runtime generated levels scanned: 108
  runtime level records (markers+actors+swinging_doors): 17744
  runtime loot-container-class markers: 508
  runtime swinging-door records: 287
  runtime records carrying an authored lock: 363
LOCK_INVENTORY runtime: authored=173 applied=363 state=APPLIED
LOCK_INVENTORY PASS authored_containers=157 authored_doors=8 authored_windows=8 locked_now=363
```

Note: 108 is the count `_collect_json` walks — 107 `.tatlevel.json` files plus
`game/data/generated/levels/_mid_unresolved.json` (not a level doc), which the
probe's `_collect_json` parses and then skips (`not Dictionary`/no matching
keys). Irrelevant to the lock arithmetic.

### 3a. Runtime sources that actually carry a lock

Containers — `game/src/interact/loot_container.gd:239-245`:

```gdscript
	if entry.get("locked") == true:
		var can_pick: Variant = entry.get("can_lockpick", null)
		if can_pick is bool and not bool(can_pick):
			_note_key_only_exclusion(p_class)
		else:
			var cap_lvl: int = int(entry.get("max_lock_level", 1))
			set_locked(true, clampi(cap_lvl, 1, 6))
```

Doors — `game/src/interact/swinging_door.gd:128-137`:

```gdscript
	if entry.get("locked") == true:
		var cls_name: String = str(entry.get("class", ""))
		var can_pick: Variant = entry.get("can_lockpick", null)
		if cls_name.to_lower().find("window") >= 0:
			_note_lock_exclusion("window", cls_name)
		elif can_pick is bool and not bool(can_pick):
			_note_lock_exclusion("key_only", cls_name)
		else:
			var cap_lvl: int = int(entry.get("max_lock_level", 1))
			set_locked(true, clampi(cap_lvl, 1, LockableDoorScript.table_max_lock_level()))
```

The lock keys travel from the marker/actor record through
`level_loader.MARKER_LOCK_KEYS` (`level_loader.gd:417-427`):
`locked, max_lock_level, min_lock_level, can_lockpick, key_tag`.

Where the runtime gets its records:

- **Containers**: only `markers` are spawned —
  `mission_controller._spawn_loot_containers` (`:4162-4172`) iterates
  `stats["loot_containers"]`, which the loader fills from
  `data_dict["markers"]` when `cls in LOOT_CONTAINER_CLASSES`
  (`level_loader.gd:3474-3492`). `actors` are *not* spawned as containers.
- **Doors**: `_spawn_swinging_doors` (`:4180-4234`) creates **one
  `SwingingDoorScript` node per `swinging_doors` record**, with no dedupe
  (`print("TAT-2 swinging doors: ", count, " locked=", locked_count)` at
  `:4231`).

### 3b. The arithmetic: 363 raw records → 154 applied locks (144 + 10)

Raw 363 (generated levels, `locked == true`), split by the key the probe counts:

| record list | count |
|---|---:|
| `markers` | 161 |
| `actors` | 174 |
| `swinging_doors` | 28 |
| **total** | **363** |

What actually reaches `set_locked(true, …)`:

| applied | count | evidence |
|---|---:|---|
| locked loot-container **markers** in `LOOT_CONTAINER_CLASSES` (all `max_lock_level=2`, `can_lockpick` absent) | **144** | 144 distinct container positions; every one appears twice in the data, once as a marker and once as an actor |
| locked **door** pivot records that pass the key-only filter (`8` at level 2 + `2` with no cap → level 1) | **10** | 12 locked door-class records − 2 `BP_Res_Int_Doorway_C` (`can_lockpick=false`) |
| **applied total** | **154** | = the brief's "144 containers + 10 door nodes" |

What is discarded (the other 209 records):

| discarded | count | why |
|---|---:|---|
| actor duplicates of the same containers (identical class + position) | 144 | only `markers` spawn containers |
| locked container records outside `LOOT_CONTAINER_CLASSES` (8 markers + 13 actors: 3 `BP_ChestTrunk_C`, 2 `BP_BookcaseB_C`, 8 `BP_SmallSafe_MajorLoot_C`) | 21 | filtered before spawn (`level_loader.LOOT_CONTAINER_CLASSES`) |
| door/window **marker+actor** records (9 markers + 17 actors) | 26 | doors spawn from `swinging_doors`, not from marker/actor records |
| key-only door records `BP_Res_Int_Doorway_C` (`can_lockpick=false`) | 2 | `swinging_door.gd:133-134` |
| window pivot records (class contains `Window`) | 16 | `swinging_door.gd:131-132` (`_note_lock_exclusion("window", …)`) |
| **discarded total** | **209** | 154 + 209 = 363 ✔ |

Per map (same data, restricted to `_map_id_to_sublevels` base sets):

| map set | locked container markers | applied door records | applied locks |
|---|---:|---:|---:|
| OldManor (9 files) | 65 | 4 (`BP_OldManor_Doorway_4x650_C` ×4) | **69** |
| FTUE (10 files) | 0 | 4 (2 distinct `BP_GB_Door3x5_C_1` pivots, each present in **both** `FTUE_Building_JewelryStore` and `FTUE_Geometry`) | **4** |
| Guildhall (15 files) | 79 | 2 (`StaticMeshActor_528` Pivot + SecondPivot) | **81** |
| Thieves Den (3 files) | 0 | 0 | **0** |
| **total** | **144** | **10** | **154** |

FTUE caveat worth a test: `BP_GB_Door3x5_C_1` is authored once but referenced by
two FTUE sublevels, so the runtime spawns **4 locked door nodes for 2 authored
pivots** (no dedupe in `_spawn_swinging_doors`). The global count above counts
those 4 records; the "10 door nodes" figure is 10 records, 8 distinct pivot
names.

Cross-check that the "one node per record" model is right (committed log, older
tree): `docs/reports/logs/r8/e2e.log:150` and `:544` record
`TAT-2 swinging doors: 155 locked=0` and `:134` `TAT-2 loot containers: 107` for
Guildhall — exactly the 155 `swinging_doors` records and 107
`LOOT_CONTAINER_CLASSES` markers in the current Guildhall 15-file set. The
OldManor figures (`120` doors, `110` containers) also match that log. That log
shows `locked=0` because it predates the lock fields being present in the
generated data; the current generated data carries them (§3b counts are from
the current files).

### 3c. What the probe does and does not assert today

`probe_lock_inventory.gd` asserts **only** the raw-dump totals
(`EXPECT_TOTAL 173`, containers 157, doors 8, windows 8, caps 155/3, no-cap 15,
`:33-38`, `:151-163`). The runtime half (`:181-231`) only prints; the PASS/FAIL
decision is `var ok: bool = fails == 0` (`:225`). So:

- `locked_now=363` is the raw record count, not the applied lock count;
- `applied==0` does **not** fail (it prints
  `state=BLOCKED-ON-INTEGRATOR-REGENERATION` and exits 0, `:218-223`);
- nothing prints 144 / 10 / 154.

---

## 4. String-audit baseline

Command (raw log: `/tmp/opencode/w10-inv3/string-audit.log`, exit 0):

```bash
python3 build/qa/w9/p3_string_audit.py
```

No arguments needed (`--tsv/--verbose/--rev/--same-files-as/--expressions` are
optional). Verbatim output:

```
UI_STRINGS total=306 routed=306 authored=195 routed_authored=195 invented=111
COVERAGE routed/total=1.0000
COVERAGE authored_routed/authored=1.0000
KINDS _loc=5 _loc_upper=5 loc=125 loc_template=4 st_template=9 st_text=83 st_upper=75
  game/src/ui/hud.gd: 69/69 routed
  ... (per-file block; 15 files)
```

| metric | value |
|---|---:|
| total visible string rows | 306 |
| routed | **306** |
| authored-mappable | **195** |
| routed ∧ authored | 195 |
| invented (no authored counterpart) | 111 |
| coverage routed/total | 1.0000 |

The brief's "306 routed / 195 authored" is exactly reproduced.

**It is not a gate today.** `main()` ends in `return 0` (line 453 is the only
`sys.exit`), there is no threshold flag and no comparison against a floor, so it
cannot fail on a regression. It is also not referenced by the Makefile, by
`tools/check_gate_ratchet.py`, or by `.github/workflows/sonar.yml`
(`grep -n "string_audit\|p3_string\|string-audit" Makefile tools/*.py
build/qa/*.sh` → no hits). The script's own docstring says "reproducible
measurement, not a gate".

---

## 5. Suite 110 coverage (`test_w9p4_statetree.gd`)

Command (raw log: `/tmp/opencode/w10-inv3/statetree-suite110.log`, exit 0):

```bash
flock /tmp/opencode/tat2-godot.lock -c 'timeout 900 tools/godot --headless --path game --script res://tests/test_w9p4_statetree.gd'
```

Verbatim decisive lines:

```
P4LIB trees=21 states=459 transitions=467 task_classes=77 condition_classes=36 linked_asset=45 local_links=2
STATETREE_COVERAGE trees=21 task_classes=77 task_instances=326 task_covered=113 task_blind=94 condition_classes=36 condition_instances=233 condition_covered=35 condition_blind=32 implemented=0 mapped=24 unsupported=89
P4COVERAGE fully_covered_trees=0 names=[]
P4TREES started=21 blocked=0 rows=140 trees=21
W9P4_STATETREE_SUMMARY: fails=0 checks=77
```

`P4ROW` totals: 113 rows = 77 `P4ROW TASK` + 36 `P4ROW COND`. `checks=77` in the
summary is the number of `_ok()` calls, **not** task_class=77 (coincidence).

### 5a. What `_check_coverage` actually asserts

`game/tests/test_w9p4_statetree.gd:407-442`, verbatim assertion block:

```gdscript
func _check_coverage() -> void:
	var coverage: Dictionary = ShadowRunner.coverage(null)
	var lib: Dictionary = TreeModel.load_library()
	var trees: Dictionary = lib["trees"]
	var tasks: Dictionary = TreeModel.task_inventory(trees)
	var conds: Dictionary = TreeModel.condition_inventory(trees)
	var totals: Dictionary = coverage["totals"]
	_ok(int(totals["task_classes"]) == tasks.size(), "coverage covers every task class")
	_ok(int(totals["condition_classes"]) == conds.size(), "coverage covers every condition class")
	_ok(int(totals["task_instances"]) == _sum_values(tasks), "coverage counts every task instance")
	_ok(int(totals["condition_instances"]) == _sum_values(conds),
		"coverage counts every condition instance (enter + transition)")
	_ok(int(totals["task_covered"]) <= int(totals["task_instances"]), "covered <= instances (tasks)")
	_ok(int(totals["condition_covered"]) <= int(totals["condition_instances"]), "covered <= instances (conditions)")
	var bad_status: Array = []
	for table: Dictionary in [coverage["tasks"], coverage["conditions"]]:
		for name: Variant in table.keys():
			var row: Dictionary = table[name]
			var status: String = str(row["status"])
			if status != "implemented" and status != "mapped-to-port" and status != "unsupported":
				bad_status.append("%s=%s" % [str(name), status])
			if str(row.get("note", "")).strip_edges() == "":
				bad_status.append("%s has no note" % str(name))
	_ok(bad_status.is_empty(), "every row has a valid status and a note (%s)" % str(bad_status.slice(0, 4)))
	# A tree is only "fully covered" if every task AND condition instance is
	# driven; the report quotes this count.
	var fully: Array = []
	for tree_name: Variant in coverage["per_tree"].keys():
		if bool((coverage["per_tree"][tree_name] as Dictionary)["fully_covered"]):
			fully.append(tree_name)
	print(Coverage.summary_line(coverage))
	print("P4COVERAGE fully_covered_trees=%d names=%s" % [fully.size(), str(fully)])
	for line: String in Coverage.table_lines(coverage, "tasks"):
		print("P4ROW ", line)
	for line: String in Coverage.table_lines(coverage, "conditions"):
		print("P4ROW ", line)
```

Every assertion is **relational** (equals a value derived from the payload, or
`<=`). No absolute coverage number is asserted. The only absolute numbers in the
file are `21` (trees, three times: `:65`, `:91`, `:448`), `459` states (`:79`,
`:92`) and `467` transitions (`:80`, `:93`) — and those are not the coverage
numbers the brief wants.

### 5b. Number → coverage key → asserted?

`Coverage.build` totals (`game/src/ai/statetree/coverage.gd:59-74`),
`ShadowRunner.coverage(null)` (`game/src/ai/statetree/shadow_runner.gd:270-274`):

| brief number | value today | key | asserted today? |
|---|---:|---|---|
| task classes | 77 | `totals.task_classes` | only `== tasks.size()` (derived), **not 77** |
| task instances | 326 | `totals.task_instances` | only `== _sum_values(tasks)` (derived), **not 326** |
| task covered | 113 | `totals.task_covered` | only `<= task_instances`, **not 113** |
| task parameter-blind | **94** | `totals.task_blind` | **not asserted at all** |
| condition classes | 36 | `totals.condition_classes` | only `== conds.size()`, **not 36** |
| condition instances | 233 | `totals.condition_instances` | only `== _sum_values(conds)`, **not 233** |
| condition covered | 35 | `totals.condition_covered` | only `<= condition_instances`, **not 35** |
| condition parameter-blind | 32 | `totals.condition_blind` | **not asserted at all** |
| fully evaluable trees | 0 / 21 | `per_tree[*].fully_covered` (built at `coverage.gd:50-51`) | count **printed only** (`P4COVERAGE`), never asserted |

Also unasserted: `by_status` (`implemented=0 mapped=24 unsupported=89`), the
per-row `instances/covered/blind` numbers, and `P4TREE` starting counts. The
`fully_covered` definition is
`tasks_instances == tasks_covered and conditions_instances == conditions_covered`
per tree (`coverage.gd:50-51`), so a literal `0` assertion is stable today but
would mask a genuine single-tree advance — W10-A should decide whether to pin
`== 0` or `<= 0` (same thing) and record the decision.

Brief self-inconsistency to fix while writing the assertions: the budget line in
`W10_BRIEF.md:66` says "77/326/113/**35** tasks" — 35 is the *condition* covered
count. The real task tuple is **77 / 326 / 113 / 94** (classes / instances /
covered / blind), conditions **36 / 233 / 35 / 32**, fully evaluable **0/21**.

---

## 6. Literal-grep census

Scope: repo root, excluding `build/`, `.godot/`, `extracted/`, `game/assets/`,
`game/data/generated/` (and `.git`). `grep -rnF`, case-sensitive.

### `maxi(100`

| file:line | context | live code? |
|---|---|---|
| `game/src/core/save_system.gd:1127` | comment documenting the removal: ``## W9-P1 replaces the port-invented `data["xp"] += maxi(100, score / 2)` (the`` | no (comment) |
| `.omo/waves/codebase-gameplay-audit/AUDIT.md:325` | audit prose | no |
| `.omo/waves/codebase-gameplay-audit/audit-gameplay.md:103,299` | audit prose | no |

**0 live occurrences.** A grep gate must allow the explanatory comment (or be
written as `maxi(100` outside a `##` line).

### `count % 12`

| file:line | context | live code? |
|---|---|---|
| `game/src/missions/mission_controller.gd:4202` | comment: `# \`count % 12 == 5\` spawn-index and leaf-filename formulas stay deleted.` | no |
| `game/tests/test_t10_gameplay.gd:219` | comment describing the old formula | no |
| `game/tests/test_w9p2_locks.gd:186` | negative assertion string: `_check(lc_src.find("count % 12") < 0 and lc_src.find("% 2") < 0,` | test guard |
| `docs/reports/remediation-20261125/T10-gameplay.md:135,445` | report prose | no |

**0 live formulas.** The existing guard is a *source-substring* check in
`test_w9p2_locks.gd:186` against `loot_container.gd` only (`% 2` as well — note
that `% 2` is a very broad substring; it currently passes).

### `3 + count % 2`

| file:line | context | live code? |
|---|---|---|
| `game/src/missions/mission_controller.gd:4201` | comment: `` # to) instead of the old invented literal 3. The old `3 + count % 2` /`` | no |

**0 live occurrences.**

### Invented result vocabulary in `game/src/ui/`

| word | file:line | count (occurrences) | live code? |
|---|---|---:|---|
| `GHOST` | `game/src/ui/hud.gd:2108` | 1 | comment documenting the removal |
| `BRAWLER` | `game/src/ui/hud.gd:2108` | 1 | same comment |
| `CONSTABULARY` | `game/src/ui/hud.gd:2108` | 1 | same comment |
| `SHADOW` | `game/src/ui/art_nouveau_theme.gd:58` (`TOUCH_SHADOW` colour const) | 1 | render constant |
| `SHADOW` | `game/src/ui/hud.gd:2108` | 1 | comment |
| `SHADOW` | `game/src/ui/main_menu.gd:193,265` (`SHADOW_CASTING_SETTING_OFF`) | 2 | render constant |
| `SHADOW` | `game/src/ui/mission_prep_ui.gd:1037` (`SHADOW_CASTING_SETTING_OFF`) | 1 | render constant |
| `SHADOW` | `game/src/ui/mobile_touch_ui.gd:130,162` (`font_shadow_color`, `TOUCH_SHADOW`) | 2 | render constant |

The whole block is the one comment at `hud.gd:2108`:

```
## Post-match rack-up, rebuilt from the authored ST_PostMatch (71 rows) and
## ST_Screens.PostMatch rows (T05). The old panel invented "CONTRACT COMPLETE /
## CAPTURED BY THE CONSTABULARY", "GHOST/SHADOW/BRAWLER" and a score line with
## no authored counterpart (RE-L-09).
```

No other invented rating word exists in `game/src/ui/` (checked
`GHOST|BRAWLER|SHADOW|CONSTABULARY`, plus a case-insensitive
`ghost|brawler|constabulary` sweep over `game/src/`: the only other hits are
legitimate — `civilian_npc.gd:130` "were ghosts", `game_state.gd:816`
`mult += 0.25 # Ghost` (the no-detection score modifier), `save_system.gd:1147`
`ghost: bool` run flag, and authored contract titles such as
`ledger_ui.gd:32` "The Constable's Due").

A grep gate on these words must therefore either ignore comment lines or pin
"only in `##` lines" — otherwise it would trip on the removal documentation
itself.

---

## 7. Audit / gate plumbing

### 7a. Makefile targets (verbatim)

```make
# Makefile:57-77
# The texture cap is derived from the extracted `.import` sidecars, so a stale
# cap must fail the content gate (see the check target below).
# check-logic validates the W5E payloads (unlocks/hearing/perception/StateTrees)
# with expectations kept outside the producers; check-consumers fails when a
# generated file has no game/src reader and no allowlisted reason.
audit: content-overrides texture-cap-check check-logic check-consumers
	python3 tools/manifest_audit.py --min-coverage 0.99 --min-exact-coverage 0.99

# Fail-closed validator for the logic-data payloads (was wired to no target).
check-logic:
	python3 tools/check_logic_data.py

# Every normalised output needs a reader or an allowlisted reason.
check-consumers:
	python3 tools/check_consumers.py

# Boot a real free-play mission headless and fail on any SCRIPT/SHADER ERROR.
# The unit suites and E2E cannot see this class: the 2026-11-25 footstep
# occlusion bug threw on every step while E2E still reported 278/278.
runtime-smoke:
	build/qa/runtime_smoke.sh 90
```

```make
# Makefile:88-91
gate-ratchet:
	python3 -m py_compile tools/*.py
	python3 tools/check_content_overrides.py --table-only
	python3 tools/check_gate_ratchet.py
```

`make audit` = content-overrides + texture-cap-check + check-logic +
check-consumers + `manifest_audit.py --min-coverage 0.99 --min-exact-coverage
0.99`. **It does not run `p3_string_audit.py`, the collision probe, the lock
probe, `runtime-smoke` or any Godot binary.**

### 7b. (a) How a new probe log gets into the ratchet

The checker does **not** enumerate `evidence.*` keys; it iterates its own
hard-coded `LOG_GATES` and `PROBE_GATES` dicts
(`tools/check_gate_ratchet.py:56-133`). Adding only an `evidence` key is
silently ignored. To gate a new log:

1. Run the gate command, commit the raw output as
   `docs/reports/logs/<wave>/<name>.log` (same directory as `evidence.dir`).
2. Register the gate **in code**, in one of:
   - `LOG_GATES[<gate>] = {command, pattern, minimums, passes_key}` — this is
     the only variant that supports **numeric floors** (`minimums` maps a regex
     group to a ratchet key; `equal_groups`, `num_le_den`, `passes_key` are the
     other supported shapes); or
   - `PROBE_GATES[<gate>] = (marker, command)` — pass-marker only, no numbers.
3. Add `gates.<gate>` numeric keys to `tools/gate_ratchet.json` (non-negative
   ints only; every value is validated) and `evidence.<gate>` = filename.
4. Update the report named by `gate_ratchet.json:report`
   (`docs/reports/w9-gate-ratchet.md` today): it must literally contain
   `compile | <checked> / <broken>`, `run_tests | <passes>`, `M2 | <passes>`,
   `E2E | <passed> / <total>`, `<num> / <den>` and the `measured_on` SHA
   (`check_gate_ratchet.py:304-328`).
5. Run `make gate-ratchet`.

For collision and lock probes the current shape is `PROBE_GATES` (marker only).
A numeric floor (e.g. collision `reduced`, coverage `937/947`; lock
`applied=154`) requires moving them to `LOG_GATES` with a regex.

### 7c. (b) Log layout/format `check_gate_ratchet.py` expects

- One **plain-text** file per gate, no header, no JSON, no timestamp
  requirement; the pattern is searched over the whole file
  (`re.search(spec["pattern"], text)`), and multi-line matches are allowed
  (`texture_cap` relies on `[\s\S]*`).
- `evidence.dir` is a **single** directory for every log
  (`docs/reports/logs/w9` today); `evidence.<gate>` is just the filename.
- `run_tests` / `m2`: the regex must contain `SUMMARY: fails=0` /
  `M2_SUMMARY: fails=0`, and at least `gates.<gate>.passes` lines must start
  with `PASS` (`^PASS\b`, `:249-251`).
- `compile`: `scripts checked: N, broken: 0`, `N >= gates.compile.checked`.
- `e2e`: `SUMMARY: fails=0 passed=P total=T`, `P >= passed`, `T >= total`,
  `P == T`.
- `audit`: `Disk-backed content coverage: N/D ... unexpected 0`, `N >=
  coverage_num`, `D >= coverage_den`, `N <= D`.
- `texture_cap`: `capped: N ... alpha-critical (kept full-res): K ...
  offenders: 0`.
- `perf_guard`: `PERF_GUARD_TEST PASS checks=N fails=0`.
- Probes: the marker must appear and `SCRIPT ERROR` must not.
- `probe_leak`: must contain `PROBE start`, and neither `leaked at exit` nor
  `SCRIPT ERROR`.
- **Freshness is not checked** — no hash, mtime or SHA comparison. A stale but
  pattern-matching log passes as long as its numbers are at/above the floor;
  the only guarantee is the wave discipline ("commit the log you just ran")
  and the `measured_on` SHA in the report.
- `make gate-ratchet` passes today:
  `GATE_RATCHET: PASS (baseline and committed evidence agree; Godot gates run
  locally)` with `measured_on=8a4b0dd`, `compile 186/0`, `run_tests 314`,
  `M2 12`, `E2E 278/278`, `audit 12660/12703`, `texture_cap 797/1/0`,
  `perf_guard 78/78`, five probe markers.

### 7d. (c) Where `make audit` runs the string audit — and what would gate it

Today: **nowhere**. `p3_string_audit.py` has no Makefile target, is not in
`audit:` or `gate-ratchet:`, and is not in CI — only `sonar.yml:79` runs
`check_gate_ratchet.py`. To turn it into a gate with a floor:

1. Teach the script to fail: add `--min-routed` / `--max-invented` (or a single
   `--floor`), compare after the totals print, and `return 1` (it currently
   `return 0` unconditionally). Floor from this baseline: `routed >= 306`,
   `authored >= 195`, `invented <= 111` (routed is currently 100 % of total, so
   `routed >= total` is equivalent and stricter against a regex regression that
   stops matching a helper).
2. Add `string-audit: python3 build/qa/w9/p3_string_audit.py --min-routed 306
   --max-invented 111` to the Makefile and add it to `audit:` (pure Python, no
   private extract, so it belongs in `make audit` rather than the local Godot
   set).
3. Commit the log to `docs/reports/logs/w10/string_audit.log`.
4. Register it in `LOG_GATES` with
   `pattern = r"UI_STRINGS total=(\d+) routed=(\d+) authored=(\d+) routed_authored=(\d+) invented=(\d+)"`
   and `minimums = [(2,"routed"),(3,"authored")]`; add
   `gates.string_audit = {"routed":306,"authored":195}` and
   `evidence.string_audit = "string_audit.log"`; point `evidence.dir` at the W10
   log directory (or copy the W9 logs alongside).
5. Extend the report regexes if the string audit is to be quoted there too
   (optional; the checker's report block is currently fixed to compile /
   run_tests / M2 / E2E / coverage).

### 7e. `runtime-smoke` observations (defect 9 context)

`build/qa/runtime_smoke.sh` prints
`RUNTIME_SMOKE seconds=N exit=C script_errors=N shader_errors=N mission_ready=N`,
fails only on `READY < 1`, `SCRIPT > 0`, `SHADER > 0` (`:41-58`), **deletes the
log on PASS** (`:60`), and never inspects `$CODE` (the `timeout` 124 vs a real
crash) nor `ERROR:` / `push_error` output. It is also not in the ratchet (no
`runtime_smoke` evidence key in `gate_ratchet.json`), so there is no committed
smoke log for W10-A to extend — the evidence worker must create the log and the
`LOG_GATES` entry.

---

## Gaps / NOT MEASURED

| item | status | reason |
|---|---|---|
| collision OldManor / FTUE **run** | NOT MEASURED | the probe hard-codes the 15 Guildhall sublevels; I was told not to run a modified probe. §2 is a static prediction validated only against Guildhall's measured `reduced=16`. |
| collision reduced **mesh names** from the probe | NOT MEASURED | the probe prints a count only; `AuthoredCollision.stats()` has no name list. §2c lists what the static replay predicts. |
| "97.9 % emitted" collision figure from the brief | NOT MEASURED / source not found | only `coverage=0.989 (937/947)` is emitted; no 97.9 % line exists in this tree's logs/reports. |
| lock count **observed at runtime** | NOT MEASURED (derived, not probed) | §3b is derived by reading `_spawn_loot_containers` / `_spawn_swinging_doors` and counting the generated JSON; no Godot run printed `locked=`. The r8 e2e log only proves the pre-lock node counts (155 doors / 107 containers). |
| string-audit regression exit | MEASURED = cannot fail | `main()` returns 0 unconditionally. |
| suite-110 absolute coverage assertions | MEASURED = absent | see §5a; only `21/459/467` are literal. |
| `make audit` string-audit wiring | MEASURED = absent | no Makefile/CI reference. |
| perf matrix / GPU captures | NOT MEASURED | out of scope for INV-3 and the host must not run parallel GPU jobs. |

---

## Appendix A — predicted reduced meshes (static replay, §2c)

Same model as §2b: exact `(mesh,pos,basis,scale)` dedupe, `skyboxgeo` excluded,
`CLUTTER_TOKENS` paths excluded, record present, not `NoCollision`, not
`complex_as_simple`, ≥1 convex element, then
`elements > 16 or (elements-1)*instances > 250`.

### OldManor (36 reduced paths, 297 instances)

| UE path | elements | instances | rule that reduces |
|---|---:|---:|---|
| `/Game/Art/Gameplay/LightBeam/SM_LightBeam_Bulb` | 4 | 196 | (elements-1)*instances = 588 > 250 |
| `/Game/Art/Environment/OldManor/SM_OldManor_Doorway_4x650` | 14 | 37 | (elements-1)*instances = 481 > 250 |
| `/Game/Art/Environment/OldManor/SM_OldManor_WallC_Window_Int_4x6` | 32 | 15 | elements 32 > 16 |
| `/Game/Art/Environment/OldManor/SM_OldManor_WallC_Window_Int_4x8` | 32 | 5 | elements 32 > 16 |
| `/Game/Art/Environment/OldManor/SM_OldManor_Gallery_Arch_Railing` | 18 | 4 | elements 18 > 16 |
| `/Game/Art/Environment/OldManor/SM_OldManor_Gallery_Doorway_4x12` | 28 | 4 | elements 28 > 16 |
| `/Game/Art/Environment/OldManor/SM_OldManor_Gate_Front` | 17 | 3 | elements 17 > 16 |
| `/Game/Art/Environment/Civic/Planters/SM_Civic_Planter_Round_2x50cm` | 33 | 2 | elements 33 > 16 |
| `/Game/Art/Environment/Lights/Ceiling/SM_MERGED_Chandelier` | 25 | 2 | elements 25 > 16 |
| `/Game/Art/Environment/Manor/Special/SM_Manor_Fireplace_x8` | 21 | 2 | elements 21 > 16 |
| `/Game/Art/Environment/OldManor/SM_OldManor_Gallery_Arch_NoRailing` | 17 | 2 | elements 17 > 16 |
| `/Game/Art/Environment/Lights/Ceiling/SM_CollapsedChandelier_B` | 18 | 1 | elements 18 > 16 |
| `/Game/Art/Environment/Manor/SM_Manor_Bookcase_Cabinet_2x8` | 17 | 1 | elements 17 > 16 |
| `/Game/Art/Environment/Manor/Special/SM_Manor_EntranceFoyer` | 24 | 1 | elements 24 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Front_Diing_Combo_01` | 62 | 1 | elements 62 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Front_Ext_Combo_01` | 165 | 1 | elements 165 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Front_Ext_Combo_02` | 28 | 1 | elements 28 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Front_Ext_Combo_03` | 23 | 1 | elements 23 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Front_Ext_Combo_04` | 24 | 1 | elements 24 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Front_Ext_Combo_05` | 18 | 1 | elements 18 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Front_Ext_Combo_06` | 40 | 1 | elements 40 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Front_Int_01` | 86 | 1 | elements 86 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Front_Int_Combo_02` | 86 | 1 | elements 86 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Front_Int_Combo_04` | 61 | 1 | elements 61 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Gallery_Ext_Combo_01` | 185 | 1 | elements 185 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Hall_Int_01` | 118 | 1 | elements 118 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Secret_Combo_02` | 24 | 1 | elements 24 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Secret_Combo_03` | 30 | 1 | elements 30 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_TowerRoof_Combo_01` | 419 | 1 | elements 419 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_TowerRoof_Int_Combo_01` | 62 | 1 | elements 62 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_TowerRoof_Int_Combo_02` | 95 | 1 | elements 95 > 16 |
| `/Game/Art/Environment/OldManor/Combo_Pieces/SM_OldManor_Tower_VaultRoom` | 112 | 1 | elements 112 > 16 |
| `/Game/Art/Environment/OldManor/SM_OldManor_Tower_Stairs_4x850` | 36 | 1 | elements 36 > 16 |
| `/Game/Art/Environment/OldManor/SM_OldManor_Window_LivingRoom` | 24 | 1 | elements 24 > 16 |
| `/Game/Art/Environment/Props/Books/SM_Books_BookshelfA` | 41 | 1 | elements 41 > 16 |
| `/Game/Maps/OldManor/_GENERATED/gjasp/Combined_3356956A` | 18 | 1 | elements 18 > 16 |

### FTUE (20 reduced paths, 1 788 instances)

| UE path | elements | instances | rule that reduces |
|---|---:|---:|---|
| `/Game/Art/Environment/Urban/Industrial/SM_WallPipe_4m` | 4 | 309 | (elements-1)*instances = 927 > 250 |
| `/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_BayWindow_Closed_6x6_4m` | 4 | 245 | (elements-1)*instances = 735 > 250 |
| `/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Mid_4x4` | 3 | 193 | (elements-1)*instances = 386 > 250 |
| `/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Corner_4x4x4` | 13 | 174 | (elements-1)*instances = 2088 > 250 |
| `/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_MidWindowA_4x4` | 6 | 172 | (elements-1)*instances = 860 > 250 |
| `/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Mid_1x4` | 4 | 162 | (elements-1)*instances = 486 > 250 |
| `/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_BayWindow_Closed_6x6` | 4 | 159 | (elements-1)*instances = 477 > 250 |
| `/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndA_2x4x4` | 4 | 156 | (elements-1)*instances = 468 > 250 |
| `/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_BayWindowA_6x4` | 27 | 97 | elements 27 > 16 |
| `/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Mid_2x4` | 4 | 87 | (elements-1)*instances = 261 > 250 |
| `/Game/Art/Environment/Manor/SM_Manor_Bookcase_Cabinet_2x8` | 17 | 12 | elements 17 > 16 |
| `/Game/Art/Environment/Props/Books/SM_Books_BookshelfA` | 41 | 6 | elements 41 > 16 |
| `/Game/Art/Environment/Storefront/Architecture/Facades/SM_Storefront_Facade_1200_Closed` | 20 | 4 | elements 20 > 16 |
| `/Game/Art/Environment/Civic/Planters/SM_Civic_Planter_Round_1x50cm` | 30 | 3 | elements 30 > 16 |
| `/Game/Art/Environment/Civic/Planters/SM_Civic_Planter_Round_2x50cm` | 33 | 2 | elements 33 > 16 |
| `/Game/Art/Environment/Props/Furniture/Exterior/BenchStone/SM_StoneBenchB` | 23 | 2 | elements 23 > 16 |
| `/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_BayWindow_Open_6x6_4m` | 22 | 2 | elements 22 > 16 |
| `/Game/Art/Environment/Nature/Trees/Dead/SM_WillowTrunk` | 22 | 1 | elements 22 > 16 |
| `/Game/Art/Environment/Props/Furniture/Exterior/BenchStone/SM_StoneBenchC` | 21 | 1 | elements 21 > 16 |
| `/Game/Art/Environment/Storefront/Architecture/Facades/SM_Storefront_Facade_900_Closed` | 21 | 1 | elements 21 > 16 |
