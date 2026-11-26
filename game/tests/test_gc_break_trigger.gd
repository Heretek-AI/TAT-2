extends SceneTree
## W10-A3-GC gameplay-trigger regression test.
##
## Proves the deliberate stacked secondary hold (F held over a container, the
## same input contract doors use for [HOLD] LOCK) is the only path that breaks a
## destructible container:
##   1. hold-interact in front of a locked chest -> leaf hidden, broken shown,
##      container opened once, signals fired;
##   2. a second interact is a no-op (one-shot break and one-shot loot);
##   3. hold-interact on a chest behind the player does not break it;
##   4. ordinary tap-interact on a locked chest starts the lockpick and leaves it
##      locked and intact (no silent lock bypass, no break).
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     'tools/godot --headless --path game --script res://tests/test_gc_break_trigger.gd'
##
## Prints GC_TRIGGER PASS/FAIL; exits 1 on failure, 2 without extracted assets.

const THIEF_SCRIPT := "res://src/player/thief_character.gd"
const CONTAINER_SCRIPT := "res://src/interact/loot_container.gd"

var _fails: int = 0
var _checks: int = 0
var _arena: Node3D = null
var _player: CharacterBody3D = null


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("GC_TRIGGER_CHECK PASS ", name, " ", detail)
	else:
		_fails += 1
		printerr("GC_TRIGGER_CHECK FAIL ", name, " ", detail)


func _add_floor(parent: Node3D) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(30.0, 1.0, 30.0)
	cs.shape = bx
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_position = Vector3(0.0, -0.5, 0.0)


## A destructible container with stand-in visual nodes. The trigger only needs
## the broken overlay to exist; the swap itself is what the test reads.
func _make_container(owner: String, at: Vector3, locked: bool) -> Node:
	var scr: GDScript = load(CONTAINER_SCRIPT) as GDScript
	var c: Node = scr.new() as Node
	var entry: Dictionary = {
		"owner": owner,
		"pos": at,
		"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
		"scale": [1.0, 1.0, 1.0],
	}
	if locked:
		entry["locked"] = true
		entry["max_lock_level"] = 2
	c.call("configure", "BP_ChestTrunk_MajorLoot_C", entry, 0)
	_arena.add_child(c)
	var leaf := MeshInstance3D.new()
	leaf.mesh = BoxMesh.new()
	leaf.name = "FakeLeaf"
	c.add_child(leaf)
	var broken := MeshInstance3D.new()
	broken.mesh = BoxMesh.new()
	broken.name = "FakeBroken"
	broken.visible = false
	c.add_child(broken)
	c.call("bind_gc_visuals", leaf, broken)
	return c


func _press(action: String) -> void:
	var down: InputEventAction = InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	Input.action_press(action)


func _release(action: String) -> void:
	var up: InputEventAction = InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	Input.action_release(action)
	await process_frame


func _tap(action: String) -> void:
	_press(action)
	await process_frame
	await process_frame
	await _release(action)


## The stacked secondary action is a hold: physics accumulates _interact_hold_sec
## for HOLD_INTERACT_SEC (0.45 s), and only the release above the floor breaks.
func _hold(action: String, seconds: float) -> void:
	_press(action)
	await create_timer(seconds).timeout
	await _release(action)
	await process_frame


func _run() -> void:
	await process_frame
	if DirAccess.open("res://assets/ue/Content") == null:
		printerr("GC_TRIGGER SKIP assets/ue/Content missing (extracted/ not present)")
		quit(2)
		return
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("state", "playing")
		gs.set("thief_id", "spider")
		gs.set("difficulty", 2)
	_check(InputMap.has_action("primary_action"), "input map exposes primary_action", "")
	_check(InputMap.has_action("interact"), "input map exposes interact", "")

	_arena = Node3D.new()
	_arena.name = "GCTriggerArena"
	root.add_child(_arena)
	_add_floor(_arena)
	var thief_scr: GDScript = load(THIEF_SCRIPT) as GDScript
	_player = thief_scr.new() as CharacterBody3D
	_arena.add_child(_player)
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	await process_frame
	await process_frame
	_check(_player.get("cam") != null, "player camera built", "")
	_check(bool(_player.call("can_act")), "player can act", "")

	# --- 1/2. Primary swing breaks the chest in front, exactly once ----------
	var chest: Node = _make_container("BP_ChestTrunk_MajorLoot_C_0", Vector3(0.0, 0.0, -1.2), true)
	var signals: Dictionary = {"n": 0}
	chest.connect("container_broken", func(_c: Node, _a: Node) -> void: signals["n"] = int(signals["n"]) + 10)
	chest.connect("broken_changed", func(_b: bool) -> void: signals["n"] = int(signals["n"]) + 1)
	var leaf: MeshInstance3D = chest.get_node("FakeLeaf") as MeshInstance3D
	var broken: MeshInstance3D = chest.get_node("FakeBroken") as MeshInstance3D
	var loot_before: int = get_nodes_in_group("loot").size()
	_check(leaf.visible and not broken.visible and bool(chest.get("locked")), "chest starts intact and locked", "")
	_check(bool(chest.call("has_broken_overlay")), "container reports a bound broken overlay", "")
	var smash_prompt: String = str(chest.call("get_interact_secondary_prompt"))
	_check(smash_prompt.find("HOLD") >= 0 and smash_prompt.find("DESTROY") >= 0,
		"stacked secondary prompt offers the smash", smash_prompt)

	await _hold("interact", 0.6)
	_check(bool(chest.get("broken")), "hold-interact smashed the chest", "broken=" + str(chest.get("broken")))
	_check(not leaf.visible and broken.visible, "intact -> broken visual swap", "leaf=" + str(leaf.visible) + " broken=" + str(broken.visible))
	_check(int(signals["n"]) == 11, "break signals fired once", "n=" + str(int(signals["n"])))
	_check(bool(chest.get("opened")), "break opened the container once", "opened=" + str(chest.get("opened")))
	var loot_after_first: int = get_nodes_in_group("loot").size()
	_check(loot_after_first == loot_before + 1, "break spawned exactly one loot item", "%d -> %d" % [loot_before, loot_after_first])

	_check(str(chest.call("get_interact_secondary_prompt")) == "",
		"broken chest no longer offers the smash prompt", "")
	await _tap("interact")
	var loot_after_second: int = get_nodes_in_group("loot").size()
	_check(int(signals["n"]) == 11 and loot_after_second == loot_after_first,
		"second interact is a one-shot no-op",
		"signals=%d loot=%d" % [int(signals["n"]), loot_after_second])

	# --- 3. A chest behind the player is not hit by the forward swing --------
	var behind: Node = _make_container("BP_ChestTrunk_MajorLoot_C_9", Vector3(0.0, 0.0, 1.2), true)
	await _hold("interact", 0.6)
	_check(not bool(behind.get("broken")), "hold-interact does not smash a chest behind the player", "")
	_check(bool(behind.get("locked")) and not bool(behind.get("opened")), "behind chest stays locked and closed", "")

	# --- 4. Ordinary interact on a locked chest locks, never breaks ----------
	chest.queue_free()
	behind.queue_free()
	await process_frame
	await process_frame
	var locked_chest: Node = _make_container("BP_ChestTrunk_MajorLoot_C_1", Vector3(0.0, 0.0, -1.2), true)
	var lock_signals: Dictionary = {"n": 0}
	locked_chest.connect("container_broken", func(_c: Node, _a: Node) -> void: lock_signals["n"] = int(lock_signals["n"]) + 1)
	await _tap("interact")
	_check(int(lock_signals["n"]) == 0, "interact never emits container_broken", "n=" + str(int(lock_signals["n"])))
	_check(not bool(locked_chest.get("broken")), "interact does not break a locked chest", "")
	_check(bool(locked_chest.get("locked")), "locked chest stays locked after interact", "")
	_check(bool(locked_chest.get("is_lockpicking")), "interact starts the lockpick minigame", "")
	_check(not bool(locked_chest.get("opened")), "locked chest is not opened by interact", "")

	print("GC_TRIGGER checks=%d fails=%d" % [_checks, _fails])
	print("GC_TRIGGER ", "PASS" if _fails == 0 else "FAIL")
	quit(0 if _fails == 0 else 1)
