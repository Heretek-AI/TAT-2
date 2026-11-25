extends SceneTree
## W9-P2 D1: the labelled lockpick-hands PORT STAND-IN.
##
## The extraction ships no authored lockpick mesh and no lockpick animation
## (41 `lockpick` filelist entries = 36 `.uasset` + 5 `.ubulk`, 0 animation
## assets, 0 `.glb`; anims_manifest.json/anims_meta.json contain 0 lockpick
## clips). `thief_character.set_lockpicking_active()` therefore shows a small
## procedural pick prop (shaft + bent tip + grip) at a fixed 1P hand offset with
## a modest static rig pose, and frees it when picking ends.
##
## This suite proves: absent by default, present + visible + meta-labelled while
## picking, freed and base-transform-restored after, and null-safe with no rig.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/test_lockpick_hands.gd"

const THIEF_SCRIPT := "res://src/player/thief_character.gd"

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


func _add_floor(parent: Node) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(40.0, 1.0, 40.0)
	cs.shape = bx
	sb.add_child(cs)
	parent.add_child(sb)
	sb.position = Vector3(0.0, -0.5, 0.0)


func _run() -> void:
	var thief_script: GDScript = load(THIEF_SCRIPT) as GDScript
	_check(thief_script != null, "thief_character.gd loads")
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("state", "playing")
		gs.set("thief_id", "spider")

	# --- Null-safe with no 1P rig (third person / headless rig failure) -----
	var bare: Node = thief_script.new()
	bare.call("set_lockpicking_active", true)
	_check(bool(bare.get("is_lockpicking")) and bare.get("_lockpick_standin") == null,
		"no 1P rig: activating lockpicking is a safe no-op (no stand-in, flag set)")
	bare.call("set_lockpicking_active", false)
	_check(not bool(bare.get("is_lockpicking")), "no 1P rig: deactivating clears the flag")
	bare.free()

	# --- Player fixture (same arena pattern as test_m2_player.gd) -----------
	var arena := Node3D.new()
	arena.name = "LockpickHandsArena"
	root.add_child(arena)
	_add_floor(arena)
	var player: CharacterBody3D = thief_script.new() as CharacterBody3D
	arena.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 0.05, 0.0)
	await process_frame
	await process_frame
	var fp_rig: Node3D = player.get("fp_rig") as Node3D
	_check(fp_rig != null, "1P rig exists after _ready (real arms or procedural fallback)")

	# --- Absent by default --------------------------------------------------
	_check(player.get("_lockpick_standin") == null, "no stand-in before lockpicking")
	_check(fp_rig == null or fp_rig.get_node_or_null("LockpickStandIn") == null,
		"no LockpickStandIn node before lockpicking")
	var base_before: Vector3 = player.get("fp_base_rig_pos") as Vector3

	# --- Present + visible + labelled while picking -------------------------
	player.call("set_lockpicking_active", true)
	_check(bool(player.get("is_lockpicking")), "set_lockpicking_active(true) sets is_lockpicking")
	var standin: Node3D = player.get("_lockpick_standin") as Node3D
	_check(standin != null, "stand-in exists while lockpicking")
	_check(standin != null and is_instance_valid(fp_rig) and standin.get_parent() == fp_rig,
		"stand-in is parented to the 1P rig")
	_check(standin != null and standin.visible and standin.is_visible_in_tree(),
		"stand-in is visible while lockpicking")
	_check(standin != null and standin.has_meta("authored") and standin.get_meta("authored") == false,
		"stand-in is meta-labelled authored=false (port stand-in)")
	_check(standin != null and str(standin.get_meta("port_standin", "")).find("no authored lockpick") >= 0,
		"stand-in meta names the missing authored asset")
	var parts: Array = []
	if standin != null:
		for part: Node in standin.get_children():
			if part is MeshInstance3D:
				parts.append(str(part.name))
	_check(parts.has("PickShaft") and parts.has("PickTip") and parts.has("PickHandle"),
		"stand-in carries the shaft + bent tip + grip meshes (%s)" % str(parts))
	var pose_delta: Vector3 = (player.get("fp_base_rig_pos") as Vector3) - base_before
	_check(pose_delta.is_equal_approx(thief_script.LOCKPICK_POSE_RIG_OFFSET),
		"a modest static rig pose offset is applied while picking (%s)" % str(pose_delta))

	# --- Freed + restored after --------------------------------------------
	player.call("set_lockpicking_active", false)
	_check(not bool(player.get("is_lockpicking")), "set_lockpicking_active(false) clears is_lockpicking")
	_check(player.get("_lockpick_standin") == null, "stand-in reference cleared on deactivate")
	_check((player.get("fp_base_rig_pos") as Vector3).is_equal_approx(base_before),
		"rig base transform restored after the cycle (%s)" % str(player.get("fp_base_rig_pos")))
	await process_frame
	_check(fp_rig == null or fp_rig.get_node_or_null("LockpickStandIn") == null,
		"stand-in node freed on deactivate")

	# A second cycle must not accumulate nodes or drift the base transform.
	player.call("set_lockpicking_active", true)
	player.call("set_lockpicking_active", false)
	await process_frame
	var standin_nodes: int = 0
	if fp_rig != null:
		for ch: Node in fp_rig.get_children():
			if str(ch.name).begins_with("LockpickStandIn"):
				standin_nodes += 1
	_check(standin_nodes == 0, "second cycle leaves no stand-in node behind")
	_check((player.get("fp_base_rig_pos") as Vector3).is_equal_approx(base_before),
		"second cycle leaves the rig base transform unchanged")

	arena.queue_free()
	await process_frame

	if fails == 0:
		print("LOCKPICK_HANDS PASS checks=%d" % checks)
	else:
		print("LOCKPICK_HANDS FAIL checks=%d fails=%d" % [checks, fails])
	quit(0 if fails == 0 else 1)
