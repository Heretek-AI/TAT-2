extends SceneTree
## W9-P4 S1 — shadow trace evidence probe (not a gate).
##
## Boots a minimal headless arena (a live guard on a live floor, no player, no
## mission), runs the shadow interpreter for N frames and prints:
##   * the FSM's own waypoint sequence (what the hand-written patrol actually did);
##   * the authored tree's selected-state sequence from the trace;
##   * the coverage table for all 21 trees.
## The report quotes this side by side; the parity claim is "the authored patrol
## order is reproduced", not "the FSM was replaced". Payload /2 carries the
## authored node parameters and bindings; B2 is the lane that reads them, so this
## probe still measures the name-driven shadow runtime (0/21 fully evaluable).
##
## Run: TAT2_STATETREE=shadow tools/godot --headless --path game \
##        --script res://tests/probe_statetree_shadow.gd
## Optional: -- --frames=600 --joystick

const GUARD_SCRIPT := "res://src/ai/guard_ai.gd"
const Trace = preload("res://src/ai/statetree/trace.gd")
const ShadowRunner = preload("res://src/ai/statetree/shadow_runner.gd")
const Coverage = preload("res://src/ai/statetree/coverage.gd")

var fails: int = 0


func _initialize() -> void:
	await process_frame
	var frames: int = 300
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames = int(arg.substr("--frames=".length()))
	ShadowRunner.set_mode_for_test("")  # honour TAT2_STATETREE
	if not ShadowRunner.enabled():
		printerr("PROBE FAIL: set TAT2_STATETREE=shadow (or pass it in the env)")
		quit(1)
		return
	Trace.reset_shared()
	var root: Window = get_root()
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("PROBE FAIL: GameState autoload missing")
		quit(1)
		return
	gs.set("state", "playing")
	gs.set("ever_spotted", false)
	_build_floor(root, Vector3(0, -0.55, 0))
	await physics_frame
	var guard: CharacterBody3D = (load(GUARD_SCRIPT) as GDScript).new() as CharacterBody3D
	guard.name = "ProbeShadowGuard"
	guard.position = Vector3(0, 0, 0)
	var pts: Array[Vector3] = [Vector3(0, 0, 0), Vector3(0, 0, 4), Vector3(4, 0, 4), Vector3(4, 0, 0)]
	var waits: Array[float] = [0.0, 0.5, 0.0, 0.5]
	var facing: Array[bool] = [false, true, false, true]
	var yaws: Array[float] = [0.0, 90.0, 0.0, 180.0]
	guard.set("patrol_points", pts)
	guard.set("patrol_waits", waits)
	guard.set("patrol_facing", facing)
	guard.set("patrol_yaws", yaws)
	guard.set("patrol_loop_mode", "Loop")
	root.add_child(guard)
	var runner: RefCounted = guard.get("_st_shadow")
	await physics_frame
	var last_wp: int = -1
	var fsm_events: PackedStringArray = []
	for frame: int in range(frames):
		await physics_frame
		var wp: int = int(guard.get("wp_index"))
		if wp != last_wp:
			last_wp = wp
			fsm_events.append("FSM_WP frame=%d wp=%d wait_left=%.2f pos=%.2f,%.2f"
				% [frame, wp, float(guard.call("patrol_wait_remaining")),
					(guard as Node3D).global_position.x, (guard as Node3D).global_position.z])
	var traced: RefCounted = Trace.shared()
	print("P4TRACE mode=%s frames=%d rows=%d" % [str(ShadowRunner.mode()), frames, traced.count()])
	for row: Dictionary in traced.rows:
		var kind: String = str(row.get("kind", ""))
		if kind == "transition_unmet":
			print("TREE_UNMET tick=%d candidates=%s unavailable=%s"
				% [int(row.get("tick", 0)), str(row.get("candidates", [])), str(row.get("unavailable", []))])
			continue
		if kind == "fallback":
			print("TREE_FALLBACK tick=%d parent=%d status=%s advanced=%s cursor=%d"
				% [int(row.get("tick", 0)), int(row.get("parent", -1)), str(row.get("status", "")),
					str(row.get("advanced", "")), int(row.get("cursor", -1))])
			continue
		if kind != "enter" and kind != "transition" and kind != "stall" and kind != "task_block":
			continue
		if kind == "enter":
			print("TREE_ENTER tick=%d tree=%s state=%s path=%s"
				% [int(row.get("tick", 0)), str(row.get("tree", "")), str(row.get("name", "")), str(row.get("path", ""))])
		elif kind == "transition":
			var chosen: Dictionary = row.get("chosen", {})
			print("TREE_TRANSITION tick=%d from=%s trigger=%s priority=%s to=%s kind=%s"
				% [int(row.get("tick", 0)), str(chosen.get("from_state", "")), str(chosen.get("trigger", "")),
					str(chosen.get("priority", "")), str(chosen.get("to_state", chosen.get("to_kind", ""))),
					str(chosen.get("to_kind", ""))])
		elif kind == "stall":
			print("TREE_STALL tick=%d state=%s seconds=%.1f path=%s"
				% [int(row.get("tick", 0)), str(row.get("name", "")), float(row.get("seconds", 0.0)), str(row.get("path", ""))])
		else:
			print("TREE_TASK_BLOCK tick=%d task=%s state=%s"
				% [int(row.get("tick", 0)), str(row.get("task", "")), str(row.get("name", ""))])
	for line: String in fsm_events:
		print(line)
	if runner != null:
		var summary: Dictionary = runner.summary()
		print("P4SHADOW guard=%s ticks=%d visited=%d transitions=%d blocks=%d unknown=%d stalls=%d path=%s"
			% [str(summary.get("guard", "")), int(summary.get("ticks", 0)), int(summary.get("visited", 0)),
				int(summary.get("transitions_fired", 0)), (summary.get("blocks", []) as Array).size(),
				(summary.get("unknown_conditions", {}) as Dictionary).size(), int(summary.get("stalls", 0)),
				str(summary.get("path", ""))])
	else:
		fails += 1
		printerr("PROBE FAIL: the guard has no shadow runner")
	var structural: Dictionary = ShadowRunner.trace_all_trees(4)
	print("P4ALL_TREES started=%d blocked=%d rows=%d" % [int(structural["started"]), int(structural["blocked"]), int(structural["rows"])])
	var coverage: Dictionary = ShadowRunner.coverage(null)
	print(Coverage.summary_line(coverage))
	print("PROBE ", "PASS" if fails == 0 else "FAIL", " fails=", fails)
	quit(0 if fails == 0 else 1)


func _build_floor(root: Node, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	body.add_child(shape)
	body.position = at
	root.add_child(body)
