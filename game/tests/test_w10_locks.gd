extends SceneTree
## W10-A defect 8 gate: the authored `CanBeLockpicked` resolution, proven on the
## real consumers (`swinging_door.configure` / `loot_container.configure`).
##
## VERDICT (build/qa/w10/re-1-locks.md): defect 8 is NOT REPRODUCED. The prison
## door `StaticMeshActor_528` (BP_Prison_WallA_DoorwayB2_6x6_C) is authored as
## pickable: `CanBeLockpicked` is absent on the instance and its whole chain, and
## absence means "inherit" in the dump's delta serialisation, whose resolved
## value is `true` (re-1-locks.md §2-§3.2). So the port must keep locking it as
## pickable at the 1 fallback; this suite exists so nobody "fixes" it to
## key-only, and so the exclusion label cannot drift back to `key_only`.
##
## Branches under test (swinging_door.gd `AUTHORED_CAN_BE_LOCKPICKED_DEFAULT`):
##   1. explicit `can_lockpick: false` (+ a KeyTag)   -> excluded, counted
##   2. explicit `can_lockpick: false` (no KeyTag)    -> excluded, counted
##      (2 is why the label is `unpickable`, not `key_only`: 26 of the 33 placed
##       explicit-false actors carry no KeyTag — re-1-locks.md §3.3)
##   3. absent flag + KeyTag (the prison-door shape)  -> LOCKED, pickable, Lv1
##   4. absent flag, no KeyTag, `locked: true`        -> LOCKED, pickable, Lv1
##   5. explicit `can_lockpick: true`                 -> LOCKED (a bool is literal)
##
## It then reads the *generated* record for the prison actor and asserts the
## authored keys it carries (`locked` + `key_tag`, no `can_lockpick`, no
## `max_lock_level`). The authored cap 4 is PRINTED, not asserted: the producer
## emits instance deltas only, so the inherited cap never reaches the record
## (re-1-locks.md §7.2 — adjacent incomplete-input defect, documented not fixed).
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/test_w10_locks.gd"

const DOOR_SCRIPT := "res://src/interact/swinging_door.gd"
const CONTAINER_SCRIPT := "res://src/interact/loot_container.gd"
const LOCKABLE_SCRIPT := "res://src/interact/lockable_door.gd"
const POI_LEVEL := "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json"
const INTERACTABLES := "res://data/generated/gameplay/interactables.json"

const PRISON_ACTOR := "StaticMeshActor_528"
const PRISON_CLASS := "BP_Prison_WallA_DoorwayB2_6x6_C"
const PRISON_KEY := "Item.Key.Buildings.Guildhall"
## Classes used by the exclusion branches, both real: BP_VaultDoor_Sliding_C is
## the authored key-only vault door (re-1-locks.md §4.2) and the StartsOpen
## variant is a placed explicit-false actor with NO KeyTag (§3.3).
const CLS_FALSE_WITH_KEY := "BP_VaultDoor_Sliding_C"
const CLS_FALSE_NO_KEY := "BP_VaultDoor_Sliding_StartsOpen_C"
const CLS_CONTROL := "BP_OldManor_Doorway_4x650_C"
## Container fixtures use classes that DO exist in containers.json (no
## missing-row warning); the branch under test is driven by the record, not by
## the class row.
const CLS_CONTAINER_FALSE := "BP_ChestTrunk_MajorLoot_C"
const CLS_CONTAINER_OPEN := "BP_Storefront_DisplayCaseB_MinorLoot_C"

var fails: int = 0
var checks: int = 0
## Every fixture node is created outside the tree, so it must be freed by hand.
var _spawned: Array[Node] = []


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", ok_msg)
	else:
		fails += 1
		printerr("FAIL: ", fail_msg)


func _initialize() -> void:
	call_deferred("_run")


func _door(entry: Dictionary) -> Node3D:
	var d: Node3D = (load(DOOR_SCRIPT) as GDScript).new() as Node3D
	var full: Dictionary = entry.duplicate()
	if not full.has("pos"):
		full["pos"] = [0.0, 0.0, 0.0]
	if not full.has("basis"):
		full["basis"] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
	d.call("configure", full, null)
	_spawned.append(d)
	return d


func _container(p_class: String, entry: Dictionary) -> Area3D:
	var c: Area3D = (load(CONTAINER_SCRIPT) as GDScript).new() as Area3D
	var full: Dictionary = entry.duplicate()
	if not full.has("pos"):
		full["pos"] = Vector3.ZERO
	c.call("configure", p_class, full, 0)
	_spawned.append(c)
	return c


func _state(n: Node) -> String:
	return "locked=%s level=%d" % [str(n.get("locked")), int(n.get("lock_level"))]


func _run() -> void:
	await process_frame
	var door_script: GDScript = load(DOOR_SCRIPT) as GDScript
	var container_script: GDScript = load(CONTAINER_SCRIPT) as GDScript
	var lockable_script: GDScript = load(LOCKABLE_SCRIPT) as GDScript
	_check(door_script != null and container_script != null and lockable_script != null,
		"swinging_door / loot_container / lockable_door load",
		"a consumer script failed to load")
	if door_script == null or container_script == null or lockable_script == null:
		_finish()
		return
	var table_cap: int = int(lockable_script.table_max_lock_level())
	_check(table_cap == 4,
		"authored door cap from interactables.json is 4",
		"authored door cap changed to %d" % table_cap)

	# The authored default is a named constant, not an `else` accident.
	var door_consts: Dictionary = door_script.get_script_constant_map()
	var authored_default: Variant = door_consts.get("AUTHORED_CAN_BE_LOCKPICKED_DEFAULT", null)
	_check(authored_default is bool and bool(authored_default) == true,
		"swinging_door states AUTHORED_CAN_BE_LOCKPICKED_DEFAULT = true (re-1-locks.md §3.2)",
		"AUTHORED_CAN_BE_LOCKPICKED_DEFAULT is missing or not true (%s)" % str(authored_default))

	# --- 1. explicit can_lockpick=false (+ KeyTag): excluded, counted --------
	var excl_before: Dictionary = door_script.call("unpickable_exclusions") as Dictionary
	var d_false_key := _door({"class": CLS_FALSE_WITH_KEY, "locked": true,
		"can_lockpick": false, "key_tag": "Item.Key.Vault.VaultA"})
	var excl_after: Dictionary = door_script.call("unpickable_exclusions") as Dictionary
	_check(not bool(d_false_key.get("locked")) and int(d_false_key.get("lock_level")) == 0,
		"explicit can_lockpick=false + KeyTag stays unlocked (%s)" % _state(d_false_key),
		"explicit can_lockpick=false + KeyTag LOCKED (%s)" % _state(d_false_key))
	_check(int(excl_after.get(CLS_FALSE_WITH_KEY, 0)) == int(excl_before.get(CLS_FALSE_WITH_KEY, 0)) + 1,
		"the exclusion is counted per class under the `unpickable` label (%d -> %d)"
		% [int(excl_before.get(CLS_FALSE_WITH_KEY, 0)), int(excl_after.get(CLS_FALSE_WITH_KEY, 0))],
		"exclusion counter did not increment for %s (%s)" % [CLS_FALSE_WITH_KEY, str(excl_after)])

	# --- 2. explicit can_lockpick=false with NO KeyTag: same rule -----------
	var excl2_before: Dictionary = door_script.call("unpickable_exclusions") as Dictionary
	var d_false_no_key := _door({"class": CLS_FALSE_NO_KEY, "locked": true, "can_lockpick": false})
	var excl2_after: Dictionary = door_script.call("unpickable_exclusions") as Dictionary
	_check(not bool(d_false_no_key.get("locked")) and int(d_false_no_key.get("lock_level")) == 0,
		"explicit can_lockpick=false with no KeyTag stays unlocked (%s)" % _state(d_false_no_key),
		"explicit can_lockpick=false with no KeyTag LOCKED (%s)" % _state(d_false_no_key))
	_check(int(excl2_after.get(CLS_FALSE_NO_KEY, 0)) == int(excl2_before.get(CLS_FALSE_NO_KEY, 0)) + 1,
		"an unpickable door with no KeyTag is counted like any other (%d -> %d)"
		% [int(excl2_before.get(CLS_FALSE_NO_KEY, 0)), int(excl2_after.get(CLS_FALSE_NO_KEY, 0))],
		"exclusion counter did not increment for %s (%s)" % [CLS_FALSE_NO_KEY, str(excl2_after)])

	# --- Label rename: `unpickable` key, deprecated alias still answers -----
	var excl_all: Dictionary = door_script.call("lock_exclusions") as Dictionary
	_check(excl_all.has("unpickable|" + CLS_FALSE_WITH_KEY)
			and not excl_all.has("key_only|" + CLS_FALSE_WITH_KEY),
		"lock_exclusions() carries the reason key `unpickable` (not `key_only`)",
		"lock_exclusions() reason key is wrong: %s" % str(excl_all))
	var alias: Dictionary = door_script.call("key_only_exclusions") as Dictionary
	var canonical: Dictionary = door_script.call("unpickable_exclusions") as Dictionary
	_check(alias.size() == canonical.size()
			and int(alias.get(CLS_FALSE_WITH_KEY, 0)) == int(canonical.get(CLS_FALSE_WITH_KEY, 0))
			and int(alias.get(CLS_FALSE_NO_KEY, 0)) == int(canonical.get(CLS_FALSE_NO_KEY, 0))
			and int(alias.get(CLS_FALSE_NO_KEY, 0)) == int(excl2_after.get(CLS_FALSE_NO_KEY, 0)),
		"key_only_exclusions() (deprecated alias, read by test_w9p2_locks.gd) returns the same per-class tally",
		"key_only_exclusions() and unpickable_exclusions() disagree (alias=%s canonical=%s)"
		% [str(alias), str(canonical)])

	# --- 3. absent flag + KeyTag (the prison shape): locked, pickable, Lv1 ---
	var excl3_before: Dictionary = door_script.call("unpickable_exclusions") as Dictionary
	var d_prison := _door({"class": PRISON_CLASS, "locked": true, "key_tag": PRISON_KEY})
	var excl3_after: Dictionary = door_script.call("unpickable_exclusions") as Dictionary
	_check(bool(d_prison.get("locked")) and int(d_prison.get("lock_level")) == 1,
		"absent CanBeLockpicked + KeyTag (prison shape) locks as pickable at the 1 fallback (%s)"
		% _state(d_prison),
		"prison-shaped record was EXCLUDED or mis-levelled (%s)" % _state(d_prison))
	_check(int(excl3_after.get(PRISON_CLASS, 0)) == int(excl3_before.get(PRISON_CLASS, 0)),
		"the prison-shaped record is NOT counted as excluded",
		"the prison-shaped record was counted as an exclusion (%s)" % str(excl3_after))

	# --- 4. absent flag, no KeyTag, locked:true: control --------------------
	var d_control := _door({"class": CLS_CONTROL, "locked": true})
	_check(bool(d_control.get("locked")) and int(d_control.get("lock_level")) == 1,
		"absent CanBeLockpicked with no KeyTag still locks as pickable at Lv1 (%s)" % _state(d_control),
		"the no-flag control did NOT lock (%s)" % _state(d_control))

	# --- 5. explicit can_lockpick=true: taken literally ---------------------
	# BP_Dumbwaiter_C is one of the three CDOs that author `CanBeLockpicked:
	# true` (re-1-locks.md §3.1); a non-window name so the window branch cannot
	# claim it.
	var d_true := _door({"class": "BP_Dumbwaiter_C", "locked": true,
		"can_lockpick": true, "max_lock_level": 3})
	_check(bool(d_true.get("locked")) and int(d_true.get("lock_level")) == 3,
		"explicit can_lockpick=true locks at the authored cap 3 (%s)" % _state(d_true),
		"explicit can_lockpick=true did not lock at its cap (%s)" % _state(d_true))

	# --- Containers: the same rule on the other consumer --------------------
	var c_before: Dictionary = container_script.call("unpickable_exclusions") as Dictionary
	var c_false := _container(CLS_CONTAINER_FALSE, {"locked": true, "can_lockpick": false,
		"key_tag": "Item.Key.Buildings.Guildhall"})
	var c_after: Dictionary = container_script.call("unpickable_exclusions") as Dictionary
	_check(not bool(c_false.get("locked")) and int(c_false.get("lock_level")) == 0,
		"explicit can_lockpick=false container stays unlocked (%s)" % _state(c_false),
		"explicit can_lockpick=false container LOCKED (%s)" % _state(c_false))
	_check(int(c_after.get(CLS_CONTAINER_FALSE, 0)) == int(c_before.get(CLS_CONTAINER_FALSE, 0)) + 1,
		"the container exclusion is counted under `unpickable` (%d -> %d)"
		% [int(c_before.get(CLS_CONTAINER_FALSE, 0)), int(c_after.get(CLS_CONTAINER_FALSE, 0))],
		"container exclusion counter did not increment (%s)" % str(c_after))
	var c_alias: Dictionary = container_script.call("key_only_exclusions") as Dictionary
	_check(int(c_alias.get(CLS_CONTAINER_FALSE, 0)) == int(c_after.get(CLS_CONTAINER_FALSE, 0)),
		"loot_container.key_only_exclusions() alias returns the same tally (test_w9p2_locks.gd reads it)",
		"loot_container alias disagrees (alias=%s canonical=%s)" % [str(c_alias), str(c_after)])
	var c_open := _container(CLS_CONTAINER_OPEN, {"locked": true})
	_check(bool(c_open.get("locked")) and int(c_open.get("lock_level")) == 1,
		"container with no lockpick flag still locks at the 1 minimum (%s)" % _state(c_open),
		"container with no lockpick flag did NOT lock (%s)" % _state(c_open))

	# --- The generated record for the prison door --------------------------
	_check_poi_record()

	_finish()


## The shipped `.tatlevel.json` record the runtime actually consumes.
func _check_poi_record() -> void:
	var txt: String = FileAccess.get_file_as_string(POI_LEVEL)
	var parsed: Variant = JSON.parse_string(txt)
	_check(parsed is Dictionary,
		"the POI generated record parses",
		"cannot read/parse %s" % POI_LEVEL)
	if not (parsed is Dictionary):
		return
	var level: Dictionary = parsed as Dictionary
	var actor: Dictionary = {}
	for a_v: Variant in (level.get("actors", []) as Array):
		if a_v is Dictionary and str((a_v as Dictionary).get("name", "")) == PRISON_ACTOR:
			actor = a_v as Dictionary
			break
	_check(not actor.is_empty(),
		"the generated level carries the prison actor %s" % PRISON_ACTOR,
		"actor %s is missing from %s" % [PRISON_ACTOR, POI_LEVEL])
	if actor.is_empty():
		return
	_check(actor.get("locked") == true and str(actor.get("key_tag", "")) == PRISON_KEY,
		"the generated actor record carries locked=true + key_tag=%s" % PRISON_KEY,
		"the generated actor record lost locked/key_tag: %s" % str(actor))
	_check(not actor.has("can_lockpick") and not actor.has("max_lock_level"),
		"the generated actor record carries NO can_lockpick and NO max_lock_level (instance delta only)",
		"the generated actor record invented a lock field: %s" % str(actor))

	var doors: Array = []
	for s_v: Variant in (level.get("swinging_doors", []) as Array):
		if s_v is Dictionary and str((s_v as Dictionary).get("actor", "")) == PRISON_ACTOR:
			doors.append(s_v)
	_check(doors.size() == 2,
		"exactly two swinging_door nodes carry actor=%s (double doorway)" % PRISON_ACTOR,
		"expected 2 swinging_door nodes for %s, got %d" % [PRISON_ACTOR, doors.size()])
	var real_level: int = -1
	var fed_real_entry: bool = false
	for d_v: Variant in doors:
		var rec: Dictionary = d_v as Dictionary
		var ok: bool = rec.get("locked") == true \
			and str(rec.get("key_tag", "")) == PRISON_KEY \
			and str(rec.get("class", "")) == PRISON_CLASS \
			and not rec.has("can_lockpick") \
			and not rec.has("max_lock_level")
		_check(ok,
			"swinging_door node %s: locked=true, key_tag=%s, class=%s, no can_lockpick, no max_lock_level"
			% [str(rec.get("name", "?")), PRISON_KEY, PRISON_CLASS],
			"swinging_door node %s has unexpected lock fields: %s" % [str(rec.get("name", "?")), str(rec)])
		# Feed the REAL generated entry through the REAL consumer once.
		if not fed_real_entry:
			fed_real_entry = true
			var runtime_door := _door(rec)
			real_level = int(runtime_door.get("lock_level"))
			_check(bool(runtime_door.get("locked")),
				"the real generated prison entry configures as LOCKED (%s)" % _state(runtime_door),
				"the real generated prison entry configured as UNLOCKED (%s)" % _state(runtime_door))

	# Printed, NOT asserted: the authored cap and the port's level are two
	# different questions (re-1-locks.md §7.2). Producer emits instance deltas
	# only, so the inherited `MaxLockLevel: 4` from BP_SwingingDoor_C never
	# reaches the record and the runtime locks at the 1 fallback.
	var authored_cap: Variant = _authored_door_cap()
	print("W10_LOCKS: authored doors.max_lock_level = ", str(authored_cap),
		" (interactables.json; = BP_SwingingDoor_C._lockConfig.MaxLockLevel); generated record carries no cap, ",
		"so the port locks ", PRISON_ACTOR, " at Lv", real_level,
		" — adjacent incomplete-input defect (producer emits instance deltas only, ",
		"build/qa/w10/re-1-locks.md §7.2), documented not fixed; not asserted")


func _authored_door_cap() -> Variant:
	var txt: String = FileAccess.get_file_as_string(INTERACTABLES)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return "unreadable"
	var doors: Variant = (parsed as Dictionary).get("doors", null)
	if not (doors is Dictionary):
		return "missing"
	return (doors as Dictionary).get("max_lock_level", "missing")


func _finish() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	print("W10_LOCKS_SUMMARY: fails=", fails, " checks=", checks)
	quit(0 if fails == 0 else 1)
