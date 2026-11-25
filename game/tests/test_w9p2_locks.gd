extends SceneTree
## W9-P2 B2: authored locks only — the consumer rule, proven on synthetic records
## because the committed generated data carries no lock keys yet (the producer
## contract in build/qa/w9/b2-producer-contract.md is applied by the integrator
## with a regeneration).
##
## RULE (port decision, labelled):
##   * a record is locked iff the authored record says `locked == true`;
##   * its level = the authored `_lockConfig.MaxLockLevel` cap, clamped by the
##     consumer (containers 1..6, doors 1..4 from interactables.json). The dump
##     contains no per-instance `LockLevel` anywhere, so there is nothing else to
##     copy; `locked` with no authored cap locks at 1 (the minimum);
##   * key-only records (`can_lockpick == false`) are excluded (no key inventory
##     in the port) and counted per class instead of silently dropped;
##   * absence of `locked` is unlocked, and the old non-authored
##     `entry.lock_level` field is gone.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/test_w9p2_locks.gd"

const CONTAINER_SCRIPT := "res://src/interact/loot_container.gd"
const DOOR_SCRIPT := "res://src/interact/swinging_door.gd"
const LOCKABLE_SCRIPT := "res://src/interact/lockable_door.gd"
const LOADER_SCRIPT := "res://src/core/level_loader.gd"

const CLS := "BP_ChestTrunk_MajorLoot_C"

var fails: int = 0
var checks: int = 0


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		fails += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _container(entry: Dictionary) -> Area3D:
	var c: Area3D = (load(CONTAINER_SCRIPT) as GDScript).new() as Area3D
	c.call("configure", CLS, entry, 0)
	return c


func _door(entry: Dictionary) -> Node3D:
	var d: Node3D = (load(DOOR_SCRIPT) as GDScript).new() as Node3D
	var full := entry.duplicate()
	if not full.has("pos"):
		full["pos"] = [0.0, 0.0, 0.0]
	if not full.has("basis"):
		full["basis"] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
	d.call("configure", full, null)
	return d


func _container_state(c: Node) -> String:
	return "locked=%s level=%d" % [str(c.get("locked")), int(c.get("lock_level"))]


func _run() -> void:
	var container_script: GDScript = load(CONTAINER_SCRIPT) as GDScript
	var door_script: GDScript = load(DOOR_SCRIPT) as GDScript
	var lockable_script: GDScript = load(LOCKABLE_SCRIPT) as GDScript
	var loader_script: GDScript = load(LOADER_SCRIPT) as GDScript
	_check(container_script != null and door_script != null and lockable_script != null,
		"loot_container / swinging_door / lockable_door load")

	# --- The authored cap is the table cap --------------------------------
	var table_cap: int = int(lockable_script.table_max_lock_level())
	_check(table_cap == 4, "authored door cap from interactables.json is 4 (got %d)" % table_cap)

	# --- Containers: locked only from an authored record ------------------
	var c_locked := _container({"locked": true, "max_lock_level": 2, "can_lockpick": true})
	_check(bool(c_locked.get("locked")) and int(c_locked.get("lock_level")) == 2,
		"container locked=true + max=2 locks at 2 (%s)" % _container_state(c_locked))
	var c_one := _container({"locked": true, "max_lock_level": 1})
	_check(bool(c_one.get("locked")) and int(c_one.get("lock_level")) == 1,
		"container max=1 (authored FTUE chest max) locks at 1 (%s)" % _container_state(c_one))
	var c_no_max := _container({"locked": true})
	_check(bool(c_no_max.get("locked")) and int(c_no_max.get("lock_level")) == 1,
		"locked with no authored cap locks at the 1 minimum (%s)" % _container_state(c_no_max))
	var c_clamp := _container({"locked": true, "max_lock_level": 9})
	_check(bool(c_clamp.get("locked")) and int(c_clamp.get("lock_level")) == 6,
		"container cap clamps to the consumer range 1..6 (%s)" % _container_state(c_clamp))
	var c_false := _container({"locked": false, "max_lock_level": 2})
	_check(not bool(c_false.get("locked")) and int(c_false.get("lock_level")) == 0,
		"container locked=false stays unlocked (%s)" % _container_state(c_false))
	var c_absent := _container({})
	_check(not bool(c_absent.get("locked")) and int(c_absent.get("lock_level")) == 0,
		"container with no authored lock keys stays unlocked (%s)" % _container_state(c_absent))
	var c_old_lvl := _container({"lock_level": 3})
	_check(not bool(c_old_lvl.get("locked")),
		"the removed non-authored entry.lock_level no longer locks a container (%s)"
		% _container_state(c_old_lvl))

	# --- Key-only containers: excluded, counted, never silently dropped ---
	var excl_before: Dictionary = container_script.call("key_only_exclusions")
	var c_key := _container({"locked": true, "max_lock_level": 2, "can_lockpick": false,
		"key_tag": "Item.Key.Buildings.Guildhall"})
	var excl_after: Dictionary = container_script.call("key_only_exclusions")
	_check(not bool(c_key.get("locked")),
		"key-only container (can_lockpick=false) stays unlocked (%s)" % _container_state(c_key))
	_check(int(excl_after.get(CLS, 0)) == int(excl_before.get(CLS, 0)) + 1,
		"key-only container exclusion is counted per class (%d -> %d)"
		% [int(excl_before.get(CLS, 0)), int(excl_after.get(CLS, 0))])

	# --- Doors: same rule, clamped to the authored door cap ---------------
	var d_two := _door({"class": "BP_OldManor_Doorway_4x650_C", "locked": true,
		"max_lock_level": 2, "key_tag": "Item.Key.Buildings.OldManor"})
	_check(bool(d_two.get("locked")) and int(d_two.get("lock_level")) == 2,
		"door locked=true + max=2 locks at 2 (%s)" % _container_state(d_two))
	var d_clamp := _door({"class": "BP_SwingingDoor_C", "locked": true, "max_lock_level": 9})
	_check(bool(d_clamp.get("locked")) and int(d_clamp.get("lock_level")) == table_cap,
		"door cap clamps to the authored table max %d (%s)" % [table_cap, _container_state(d_clamp)])
	var d_no_max := _door({"class": "BP_Prison_WallA_DoorwayB2_6x6_C", "locked": true,
		"key_tag": "Item.Key.Buildings.Guildhall"})
	_check(bool(d_no_max.get("locked")) and int(d_no_max.get("lock_level")) == 1,
		"door locked with a KeyTag but no CanBeLockpicked locks at the 1 fallback (%s)"
		% _container_state(d_no_max))
	var d_excl_before: Dictionary = door_script.call("key_only_exclusions")
	var d_key := _door({"class": "BP_VaultDoor_Sliding_C", "locked": true,
		"can_lockpick": false, "key_tag": "Item.Key.Vault.VaultA"})
	var d_excl_after: Dictionary = door_script.call("key_only_exclusions")
	_check(not bool(d_key.get("locked")),
		"key-only door (can_lockpick=false) stays unlocked (%s)" % _container_state(d_key))
	_check(int(d_excl_after.get("BP_VaultDoor_Sliding_C", 0))
			== int(d_excl_before.get("BP_VaultDoor_Sliding_C", 0)) + 1,
		"key-only door exclusion is counted per class")
	var d_scene_only := _door({"scene_locked": true})
	_check(not bool(d_scene_only.get("locked")),
		"scene_locked alone does not lock in configure (mission_controller supplies it)")
	var d_win := _door({"class": "BP_SM_OldManor_WindowB_4x850_C", "locked": true})
	_check(not bool(d_win.get("locked")),
		"authored-locked window stays unlocked (no window interaction in the port) (%s)"
		% _container_state(d_win))
	var d_excl_all: Dictionary = door_script.call("lock_exclusions")
	_check(int(d_excl_all.get("window|BP_SM_OldManor_WindowB_4x850_C", 0)) == 1,
		"window exclusion is counted under its own reason (%s)" % str(d_excl_all))
	var d_absent := _door({})
	_check(not bool(d_absent.get("locked")) and int(d_absent.get("lock_level")) == 0,
		"door with no authored lock keys stays unlocked (%s)" % _container_state(d_absent))

	# --- The SceneVariant default is the authored class cap, not literal 3 --
	var d_scene := _door({})
	d_scene.call("set_locked", true, int(lockable_script.table_max_lock_level()))
	_check(bool(d_scene.get("locked")) and int(d_scene.get("lock_level")) == 4,
		"a scene-locked door locks at the authored class cap 4 (%s)" % _container_state(d_scene))

	# --- Level loader carries the authored keys 1:1, invents nothing ------
	var full_marker := {
		"class": CLS, "pos": Vector3.ZERO,
		"locked": true, "max_lock_level": 2, "min_lock_level": 1,
		"can_lockpick": true, "key_tag": "Item.Key.Buildings.OldManor",
	}
	var carried: Dictionary = loader_script.marker_lock_fields(full_marker)
	_check(carried.size() == 5 and carried.get("locked") == true
			and int(carried.get("max_lock_level", 0)) == 2
			and int(carried.get("min_lock_level", 0)) == 1
			and carried.get("can_lockpick") == true
			and str(carried.get("key_tag", "")) == "Item.Key.Buildings.OldManor",
		"marker_lock_fields carries all five authored keys (%s)" % str(carried))
	var partial: Dictionary = loader_script.marker_lock_fields({"locked": true})
	_check(partial.size() == 1 and partial.get("locked") == true,
		"marker_lock_fields invents no level when the source has none (%s)" % str(partial))
	var empty_fields: Dictionary = loader_script.marker_lock_fields({"class": CLS})
	_check(empty_fields.is_empty(),
		"marker_lock_fields keeps absent keys absent (%s)" % str(empty_fields))

	# --- Source pins: no invented literal/entry field may come back --------
	var mc_src: String = FileAccess.get_file_as_string("res://src/missions/mission_controller.gd")
	_check(mc_src.find("set_locked(true, 3)") < 0,
		"mission_controller no longer hardcodes the invented SceneVariant level 3")
	_check(mc_src.find("DoorScript.table_max_lock_level()") >= 0,
		"mission_controller locks scene-locked doors at the authored class cap")
	var lc_src: String = FileAccess.get_file_as_string(CONTAINER_SCRIPT)
	var sd_src: String = FileAccess.get_file_as_string(DOOR_SCRIPT)
	_check(lc_src.find("entry.get(\"lock_level\"") < 0 and sd_src.find("entry.get(\"lock_level\"") < 0,
		"no consumer reads the non-authored entry.lock_level field")
	_check(lc_src.find("count % 12") < 0 and lc_src.find("% 2") < 0,
		"no spawn-index lock formula remains in loot_container")

	if fails == 0:
		print("LOCKS PASS checks=%d" % checks)
	else:
		print("LOCKS FAIL checks=%d fails=%d" % [checks, fails])
	quit(0 if fails == 0 else 1)
