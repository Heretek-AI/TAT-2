# W9-P2 B2 — authored locks, `[ESC] CANCEL`, lockpick hands: implementation report

Worktree: `/home/john/Projects/TAT-2-rem-w9-p2` (branch `rem/w9-p2`).
Base HEAD: `b13260b` (`docs(w9): P1 report — ratchet target and the docs owed at
integration`). No commit, push or rebase was made (lane rule).

**Other lanes share this checkout.** `mission_controller.gd` also carries B1's
uncommitted room-grade work, and `run_tests.gd` / `test_roof_collision.gd` /
`test_jam_damage.gd` / `test_w9p2_endgame_continuity.gd` changed on disk while
this lane ran. The diffstat at the end lists only B2's files; anything else in
`git status` is not mine.

**Headline:** the consumer half is FIXED and proven; the producer half is a
contract only, so the runtime application is **BLOCKED-ON-INTEGRATOR-
REGENERATION** (0 authored locks reach `.tatlevel.json` until then). The
`[ESC] CANCEL` double-handling bug and the lockpick hands stand-in are FIXED.

---

## 1. Files changed

| File | Change |
|---|---|
| `game/src/core/level_loader.gd` | `MARKER_LOCK_KEYS` + `marker_lock_fields()`; the loot-container marker branch carries the five authored lock keys 1:1 |
| `game/src/interact/loot_container.gd` | `configure` authored-lock rule (cap-as-level, key-only exclusion), exclusion counter, `entry.lock_level` read removed |
| `game/src/interact/swinging_door.gd` | `configure` authored-lock rule, key-only + window exclusion counters, `entry.lock_level` read removed |
| `game/src/interact/lockable_door.gd` | port-decision + key-only-exclusion comment on the authored cap |
| `game/src/missions/mission_controller.gd` | `_spawn_swinging_doors`: `scene_locked` level 3 → `DoorScript.table_max_lock_level()` (authored cap 4) |
| `game/src/ui/hud.gd` | ESC double-handling guard: `_pause_consumed_frame` member + `_input` stamp + `_process` pause-branch check (no other HUD code touched) |
| `game/src/player/thief_character.gd` | labelled lockpick-hands **PORT STAND-IN** (`set_lockpicking_active` + `_set_lockpick_standin`) |
| `game/tests/test_t10_gameplay.gd` | suite 91.3c fixture uses the authored key `max_lock_level` instead of the removed non-authored `lock_level` |
| `game/tests/test_w9p2_locks.gd` | **new** consumer rule proof (synthetic records) |
| `game/tests/test_lockpick_cancel.gd` | **new** ESC-CANCEL regression |
| `game/tests/test_lockpick_hands.gd` | **new** stand-in proof |
| `game/tests/probe_lock_inventory.gd` | **new** authored-vs-runtime inventory probe |
| `build/qa/w9/b2-producer-contract.md` | **new** producer contract (sites, fields, keys, diff, regen step) |
| `build/qa/w9/parse_tables-lock-fields.patch` | **new** the same diff as a `git apply`-able patch (`--check` passes) |

`git diff -- tools/parse_tables.py` is empty; `make audit` re-verified
`baseline: matches tools/audit_baseline.json`.

## 2. The lock rule (final code)

Authored data: the dump authors **`_locked`** per placed actor and
`_lockConfig.MaxLockLevel` / `MinLockLevel` / `CanBeLockpicked` / `KeyTag`.
There is **no per-instance level** (`LockLevel`/`lock_level` = 0 occurrences in
12,541 JSONs). Port decision, labelled in every consumer: **a record's level is
its authored `MaxLockLevel` cap**, clamped by the consumer; `locked` with no cap
locks at 1; absence of `locked` is unlocked.

`loot_container.gd` (`configure`, verbatim):

```gdscript
	if entry.get("locked") == true:
		var can_pick: Variant = entry.get("can_lockpick", null)
		if can_pick is bool and not bool(can_pick):
			_note_key_only_exclusion(p_class)
		else:
			var cap_lvl: int = int(entry.get("max_lock_level", 1))
			set_locked(true, clampi(cap_lvl, 1, 6))
```

`swinging_door.gd` (`configure`, verbatim):

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

`level_loader.gd` marker branch carries the keys without inventing any:

```gdscript
const MARKER_LOCK_KEYS: Array[String] = [
	"locked", "max_lock_level", "min_lock_level", "can_lockpick", "key_tag",
]

static func marker_lock_fields(mk: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in MARKER_LOCK_KEYS:
		if mk.has(k):
			out[k] = mk[k]
	return out
```

```gdscript
			var lc_rec := {
				"class": cls,
				"pos": p,
				"basis": (mk.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]) as Array).duplicate(),
				"scale": sc,
			}
			lc_rec.merge(marker_lock_fields(mk))
			lc_arr.append(lc_rec)
```

`mission_controller.gd` (`_spawn_swinging_doors`, the SceneVariant branch):

```gdscript
		var sv_locked: Variant = dd.get("scene_locked", null)
		if sv_locked is bool and bool(sv_locked):
			door.set_locked(true, DoorScript.table_max_lock_level())
```

(the old invented literal was `door.set_locked(true, 3)`; the authored
`BP_SwingingDoor._lockConfig.MaxLockLevel` = 4 is what
`interactables.json:1944` carries and what `set_locked` clamps to).

Exclusion counters are static and printed once per class, never per instance:
`loot_container.key_only_exclusions()`, `swinging_door.lock_exclusions()`,
`swinging_door.key_only_exclusions()`.

## 3. Producer half — contract, not a tree edit

`tools/parse_tables.py` is **not modified** (the audit baseline pins the
producer sha256; regeneration is forbidden on this branch because
`game/data/generated` is the main checkout's shared directory). The full time
contract — emission sites, source fields → emitted keys, absence rule, verified
unified diff, verification output and the integrator's regen+refresh commands —
is in **`build/qa/w9/b2-producer-contract.md`**; the apply-able diff is
`build/qa/w9/parse_tables-lock-fields.patch`.

Summary of the contract:

| Source (`Properties` on the placed actor) | Target key |
|---|---|
| `_locked` (bool) | `locked` |
| `_lockConfig.MaxLockLevel` (int, a **cap**) | `max_lock_level` |
| `_lockConfig.MinLockLevel` (int) | `min_lock_level` |
| `_lockConfig.CanBeLockpicked` (bool) | `can_lockpick` |
| `_lockConfig.KeyTag.TagName` (string) | `key_tag` |

Emission sites: door pre-pass `swinging_doors.append` `tools/parse_tables.py:2026`
(owning actor `exps[aidx]`, `aidx` at `:1812`), marker `marker_rec` `:2314`,
generic actor `actors.append` `:2369`. **Absent when the source has no data** —
never defaulted, so class-default `_locked` cannot leak into a placed record.

Read-only verification of the patched helper against the real dump (helper
imported from `/tmp`, no producer run): placed locks **173 = 157 containers +
8 doors + 8 windows**, caps **155×2, 3×1, 15 none**; the two OldManor door owner
actors resolve to `{locked: True, max_lock_level: 2, key_tag:
Item.Key.Buildings.OldManor}`. Full output in the contract doc §4.

### Excluded authored locks (with counts)

| Exclusion | Authored actors | Runtime nodes after regen | Reason |
|---|---:|---:|---|
| Key-only doors (`can_lockpick == false`) | 4 (3 `BP_VaultDoor_Sliding_C`, 1 `BP_Res_Int_Doorway_C`) | 2 (only the Res doorway has pivots; vault doors are deferred devices) | no key inventory in the port → a key-only lock would soft-lock content |
| Windows (all 8 authored-locked) | 8 | 16 pivot nodes | no window interaction; **the door pre-pass resolves pivots on window actors too**, so the consumer excludes them |
| Unsupported container classes | 13 (8 `BP_SmallSafe_MajorLoot_C`, 3 `BP_ChestTrunk_C`, 2 `BP_BookcaseB_C`) | 0 | not in `LOOT_CONTAINER_CLASSES`, never spawned as containers |

**Discrepancy flagged against the lane brief:** the brief listed the prison
doorway (`BP_Prison_WallA_DoorwayB2_6x6_C`, `Building_Guildhall_POI.json`,
actor `StaticMeshActor_528`) among the key-only doors, but its authored
`_lockConfig` is `{KeyTag: Item.Key.Buildings.Guildhall}` with **no
`CanBeLockpicked`**. The decided mechanical rule (`can_lockpick == false` →
exclude) therefore treats it as pickable: it will lock at the 1 fallback (2
pivot nodes). If the lead wants it excluded it needs an explicit rule
("KeyTag without CanBeLockpicked is key-only"); I did not invent one.

Expected runtime application after regeneration (join of the generated records
against the authored actors): **144 locked container markers** (Guildhall_Loot
48 chests + 31 display cases, OldManor_Loot 41 + 24, all level 2) and **10
locked door nodes** (POI prison doorway ×2 @1; FTUE JewelryStore ×2 and
FTUE_Geometry ×2 @2; OldManor_Geo doorway ×4 @2); 18 excluded door nodes
(16 window + 2 key-only).

## 4. The LV4 `[ESC] CANCEL` bug (FIXED)

Root cause (unchanged from `facts-b2.md` §6): `hud._input` consumes ESC for the
pick and clears `_lockpick_active`; the same frame's `hud._process` still sees
`Input.is_action_just_pressed("pause")`, finds the lockpick branch false, and
calls `_toggle_pause()` — one ESC press cancelled the pick **and** opened the
pause menu.

Guard (the existing NPC-dialogue pattern: `_npc_dialogue_closed_frame` is
stamped in the dialogue's `_input` path and checked in the HUD `_process` pause
branch, so the same action cannot be consumed twice in one frame):

```gdscript
# member
var _pause_consumed_frame: int = -1

# _input, lockpick-cancel branch
if kev.keycode == KEY_ESCAPE:
	_pause_consumed_frame = Engine.get_process_frames()
	_finish_lockpick(false)
	_mark_input_handled()
	return

# _process, pause branch
if InputMap.has_action("pause") and Input.is_action_just_pressed("pause"):
	if Engine.get_process_frames() == _pause_consumed_frame:
		pass
	elif Engine.get_process_frames() == _npc_dialogue_closed_frame:
		...
```

The stamp is monotonic, so a stale value cannot match a later frame; a normal
ESC on any later frame still pauses (asserted).

Red → green, `game/tests/test_lockpick_cancel.gd`:

```text
# RED (before the guard)
FAIL: ESC while lockpicking must not pause the tree (got paused=true)
FAIL: ESC during a container pick must not pause the tree (got paused=true)
LOCKPICK_CANCEL FAIL checks=18 fails=2

# GREEN (after the guard)
PASS: ESC while lockpicking must not pause the tree (got paused=false)
PASS: ESC cancels the lockpick (is_lockpicking false)
PASS: cancel callback received false (got [false])
PASS: ESC during a container pick must not pause the tree (got paused=false)
PASS: the container stays locked after the cancel
PASS: the container keeps its authored level 2 after the cancel
PASS: a later ESC with no lockpick still opens the pause menu
LOCKPICK_CANCEL PASS checks=18
```

The suite drives the real HUD `_input`/`_process` pair for one idle frame (the
play order), then a real locked `loot_container` through `interact()` so the
assertion "the door/container stays locked and the callback gets `false`" is on
the owner's own `_on_lockpick_finished`, not a mock. The last case proves the
guard is not a blanket pause disable.

## 5. Lockpick hands — labelled PORT STAND-IN

Declaration (verbatim from `thief_character.gd`):

```gdscript
## W9-P2 D1 — PORT STAND-IN, NOT AUTHORED CONTENT. The extraction ships no
## lockpick tool mesh and no lockpick animation (41 `lockpick` filelist entries =
## 36 `.uasset` + 5 `.ubulk`, 0 animation assets, 0 `.glb`; anims_manifest.json
## has 0 lockpick clips). So the "pick in hand" is a small procedural prop
## (thin shaft + bent tip + grip) at a fixed right-hand offset on the 1P rig,
## plus a modest static rig pose offset while picking. Replace it only if an
## authored mesh/animation ever lands.
var _lockpick_standin: Node3D = null
```

* two-material procedural prop under `FirstPersonRig/LockpickStandIn`
  (`PickShaft` CylinderMesh 11 cm, `PickTip` BoxMesh hook, `PickHandle`
  CylinderMesh), node meta `authored=false` and
  `port_standin="lockpick hands: no authored lockpick mesh/animation exists in the extraction"`;
* pose = `fp_base_rig_pos + Vector3(0.0, -0.012, 0.02)` while active, restored
  on false. `_update_first_person` composes `fp_base_rig_pos + bob`
  (`thief_character.gd:4571`), so the bob/crank code is never fought;
* null-safe: no `fp_rig` (third person, headless rig failure) → no-op; a second
  cycle leaves no node and no base drift.

```text
PASS: no 1P rig: activating lockpicking is a safe no-op (no stand-in, flag set)
PASS: stand-in is meta-labelled authored=false (port stand-in)
PASS: stand-in carries the shaft + bent tip + grip meshes (["PickShaft", "PickTip", "PickHandle"])
PASS: a modest static rig pose offset is applied while picking ((0.0, -0.012, 0.02))
PASS: rig base transform restored after the cycle ((0.0, 0.0, 0.0))
PASS: second cycle leaves no stand-in node behind
LOCKPICK_HANDS PASS checks=20
```

## 6. Test gates run in this lane (headless, one Godot at a time under the GPU lock)

| Gate | Command | Result |
|---|---|---|
| compile | `tools/check_scripts_compile.gd` | `scripts checked: 165, broken: 0` (count grows as the other lanes add scripts) |
| consumer rule | `game/tests/test_w9p2_locks.gd` | `LOCKS PASS checks=28` |
| ESC cancel | `game/tests/test_lockpick_cancel.gd` | `LOCKPICK_CANCEL PASS checks=18` (RED captured first: `FAIL checks=18 fails=2`, both `paused=true`) |
| hands stand-in | `game/tests/test_lockpick_hands.gd` | `LOCKPICK_HANDS PASS checks=20` |
| inventory probe | `game/tests/probe_lock_inventory.gd` | `LOCK_INVENTORY PASS authored_containers=157 authored_doors=8 authored_windows=8 locked_now=0` |

The probe asserts the **authored** counts only. The runtime split is derived from
the measured records (`applied == 0` → `state=BLOCKED-ON-INTEGRATOR-
REGENERATION`, else `state=APPLIED`), so the same probe stays green on the
integrator's regenerated tree and simply reports `locked_now=154`.
| unit suite | `make test` (`run_tests.gd`) | `SUMMARY: fails=1` — **not mine**: suite 100 "W9-P2 B1 room grade: feather not monotone: edge=0.570 far=1.000" (B1's uncommitted suite in this worktree). All other suites pass, including 91.3c after the fixture fix and the HUD pause suites (60b) |
| M2 player | `game/tests/test_m2_player.gd` | `M2_SUMMARY: fails=0` |
| E2E tier 1 | `run_e2e_tests.gd -- --tier=1` | `SUMMARY: fails=0 passed=117 total=117` |
| E2E S2 loot | `run_e2e_tests.gd -- --tier=s2` | `SUMMARY: fails=0 passed=12 total=12` |
| audit | `make audit` | `AUDIT PASS`, `baseline: matches tools/audit_baseline.json` (producer untouched) |

`91.3c` (`test_t10_gameplay.gd`) pinned the deleted non-authored field
`{"locked": true, "lock_level": 2}`. The assertion's intent (an authored lock
record is honoured at its level) is unchanged; the fixture now authors
`max_lock_level: 2`, the field the dump actually carries. This is the one
expectation change in the lane.

Not run here (integrator/GPU): captures, `make texture-cap-check` (audit
includes none of it — the audit target covers content-only, no GPU),
`test_perf_guard.sh`, `make gate-ratchet` (needs the committed logs of a
completed wave).

## 7. Integrator step (exact)

1. Apply `build/qa/w9/parse_tables-lock-fields.patch` (or paste §3 of
   `b2-producer-contract.md`) at merged HEAD, then `python3 -m py_compile
   tools/parse_tables.py`.
2. `make normalize` (or `python3 tools/parse_tables.py`) on a **writable**
   generated tree — never from a worker symlink.
3. Confirm the generated counts (`144` locked container markers, `10` locked
   door nodes, `0` locked window nodes; snippet in the contract §6).
4. `make audit-refresh-stamps REASON='parse_tables emits authored lock fields
   (_locked/_lockConfig); regenerated after make normalize'` then `make audit`.
5. Re-run `probe_lock_inventory.gd` (expect `locked_now=154`) and
   `test_w9p2_locks.gd` on the integrated tree.
6. The runtime state line printed by the probe is
   `LOCK_INVENTORY runtime: authored=173 applied=0
   state=BLOCKED-ON-INTEGRATOR-REGENERATION` today and is expected to flip to
   `applied=154` only after step 2.

## 8. git diff --stat (B2 files only)

```text
# B2-owned files (git diff --stat, excludes mission_controller.gd which also
# carries B1's uncommitted room-grade work):
 game/src/core/level_loader.gd       |  29 +++++++++--
 game/src/interact/lockable_door.gd  |   8 +++
 game/src/interact/loot_container.gd |  49 ++++++++++++++----
 game/src/interact/swinging_door.gd  |  56 ++++++++++++++++++--
 game/src/player/thief_character.gd  | 100 ++++++++++++++++++++++++++++++++++++
 game/src/ui/hud.gd                  |  18 ++++++-
 game/tests/test_t10_gameplay.gd     |   9 ++--
 7 files changed, 250 insertions(+), 19 deletions(-)

# mission_controller.gd: file total 167 insertions / 14 deletions (numstat),
# of which B2 is the `_spawn_swinging_doors` hunk only:
#   @@ -4124,11 +4276,9 @@  (-11/+9)  and  @@ -4137 +4287 @@ (-1/+1)

new files (untracked):
 game/tests/test_w9p2_locks.gd                    193 lines
 game/tests/test_lockpick_cancel.gd               170 lines
 game/tests/test_lockpick_hands.gd                141 lines
 game/tests/probe_lock_inventory.gd               231 lines
 build/qa/w9/b2-producer-contract.md              273 lines
 build/qa/w9/parse_tables-lock-fields.patch        74 lines
```
