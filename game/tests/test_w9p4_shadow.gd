extends SceneTree
## W9-P4 S1 — shadow-mode side-effect proof (suite 111).
##
## Runs the SAME arena twice in one process: once with `TAT2_STATETREE=off` and
## once with `=shadow`. Each phase ticks a live guard on a live physics floor for
## 240 frames and builds a signature over every per-frame observable the FSM owns
## (position, yaw, alertness, detection, patrol index, dwell timer). The two
## signatures must be identical: shadow mode provably mutates nothing.
##
## One process, two phases, rather than two child engines: a child boot is
## ~150 s on this host, so two children plus the parent exceeded the 420 s gate
## budget and the gate must stay runnable. The shipping switch is still proven —
## `_check_env_flag` drives `OS.set_environment("TAT2_STATETREE", ...)` and
## re-parses it, which is exactly what `guard_ai.gd` reads.
##
## Run: tools/godot --headless --path game --script res://tests/test_w9p4_shadow.gd
## Marker: W9P4_SHADOW_SUMMARY: fails=0 checks=N

const GUARD_SCRIPT := "res://src/ai/guard_ai.gd"
const Trace = preload("res://src/ai/statetree/trace.gd")
const ShadowRunner = preload("res://src/ai/statetree/shadow_runner.gd")

const FRAMES: int = 240

var fails: int = 0
var checks: int = 0


func _initialize() -> void:
	await process_frame
	_check_env_flag()
	var off: Dictionary = await _phase("off")
	var shadow: Dictionary = await _phase("shadow")
	_ok(bool(off.get("started", false)), "off phase ran the arena")
	_ok(bool(shadow.get("started", false)), "shadow phase ran the arena")
	# The side-effect proof: every FSM-owned observable is identical.
	_ok(str(off.get("sig", "off")) == str(shadow.get("sig", "shadow")),
		"signatures identical (off=%s shadow=%s)" % [str(off.get("sig")), str(shadow.get("sig"))])
	for field: String in ["pos", "yaw", "state", "detection", "wp", "wait", "ever"]:
		_ok(str(off.get(field, "")) == str(shadow.get(field, "")),
			"%s identical (off=%s shadow=%s)" % [field, str(off.get(field)), str(shadow.get(field))])
	# The shadow run really ran.
	_ok(int(off.get("rows", -1)) == 0, "off records no trace rows (got %s)" % str(off.get("rows")))
	_ok(int(shadow.get("rows", 0)) > 0, "shadow records trace rows (got %s)" % str(shadow.get("rows")))
	_ok(int(shadow.get("ticks", 0)) >= FRAMES - 5, "shadow ticked every frame (got %s)" % str(shadow.get("ticks")))
	_ok(bool(shadow.get("reached_patrol", false)), "the authored tree reached ST_Patrol")
	_ok(str(shadow.get("trees", "")) == "ST_Guard,ST_Patrol",
		"the live trace covers ST_Guard and ST_Patrol (got %s)" % str(shadow.get("trees")))
	_ok(str(shadow.get("ever", "true")) == "false", "ever_spotted stayed false in shadow")
	_ok(int(shadow.get("transitions", 0)) >= 6,
		"the interpreter fired the authored transitions (got %s)" % str(shadow.get("transitions")))
	print("W9P4_SHADOW off_sig=%s shadow_sig=%s shadow_rows=%s shadow_ticks=%s transitions=%s visited=%s reached_patrol=%s trees=%s"
		% [str(off.get("sig")), str(shadow.get("sig")), str(shadow.get("rows")),
			str(shadow.get("ticks")), str(shadow.get("transitions")), str(shadow.get("visited")),
			str(shadow.get("reached_patrol")), str(shadow.get("trees"))])
	print("W9P4_SHADOW_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(0 if fails == 0 else 1)


## Proves the shipping switch: the env var selects the mode and an unknown value
## degrades to off (with a warning), so `guard_ai.gd` never attaches a runner it
## was not asked to attach.
func _check_env_flag() -> void:
	var previous: String = OS.get_environment("TAT2_STATETREE")
	OS.set_environment("TAT2_STATETREE", "shadow")
	ShadowRunner.set_mode_for_test("")
	_ok(str(ShadowRunner.mode()) == "shadow", "TAT2_STATETREE=shadow selects shadow")
	OS.set_environment("TAT2_STATETREE", "patrol")
	ShadowRunner.set_mode_for_test("")
	_ok(str(ShadowRunner.mode()) == "patrol", "TAT2_STATETREE=patrol is recognised (S2 reserved)")
	OS.set_environment("TAT2_STATETREE", "nonsense")
	ShadowRunner.set_mode_for_test("")
	_ok(str(ShadowRunner.mode()) == "off", "an unknown TAT2_STATETREE value degrades to off")
	if previous == "":
		OS.unset_environment("TAT2_STATETREE")
	else:
		OS.set_environment("TAT2_STATETREE", previous)
	ShadowRunner.set_mode_for_test("")


func _ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		fails += 1
		printerr("FAIL: ", label)


# ---------------------------------------------------------------------------
# One arena phase
# ---------------------------------------------------------------------------


func _phase(mode: String) -> Dictionary:
	ShadowRunner.set_mode_for_test(mode)
	Trace.reset_shared()
	var root: Window = get_root()
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("FAIL: GameState autoload missing")
		return {}
	gs.set("state", "playing")
	gs.set("ever_spotted", false)
	var floor_body: StaticBody3D = _build_floor(root, Vector3(0, -0.55, 0))
	await physics_frame
	var guard: CharacterBody3D = (load(GUARD_SCRIPT) as GDScript).new() as CharacterBody3D
	guard.name = "SigGuard"
	guard.position = Vector3(0, 0, 0)
	guard.rotation = Vector3.ZERO
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
	var shadow_ref: RefCounted = guard.get("_st_shadow")
	await physics_frame
	var digest: int = 1469598103934665603  # FNV-1a offset basis (int64 wraps)
	var samples: PackedStringArray = []
	for frame: int in range(FRAMES):
		await physics_frame
		var node: Node3D = guard
		var line: String = "%.6f,%.6f,%.6f|%.6f|%d|%.6f|%d|%.6f" % [
			node.global_position.x, node.global_position.y, node.global_position.z,
			node.rotation.y,
			int(guard.get("state")),
			float(guard.get("detection")),
			int(guard.get("wp_index")),
			float(guard.call("patrol_wait_remaining")),
		]
		for byte: int in line.to_utf8_buffer():
			digest = (digest ^ byte) * 1099511628211
		if frame % 60 == 0:
			samples.append(line)
	var traced: RefCounted = Trace.shared()
	var rows: int = traced.count()
	var trees: Array = []
	var reached_patrol: bool = false
	for trace_row: Dictionary in traced.rows:
		var tree: String = str(trace_row.get("tree", ""))
		if tree != "" and not trees.has(tree):
			trees.append(tree)
		if tree == "ST_Patrol":
			reached_patrol = true
	trees.sort()
	var node: Node3D = guard
	var result: Dictionary = {
		"started": true,
		"mode": mode,
		"sig": str(digest),
		"pos": "%.6f,%.6f,%.6f" % [node.global_position.x, node.global_position.y, node.global_position.z],
		"yaw": "%.6f" % node.rotation.y,
		"state": str(int(guard.get("state"))),
		"detection": "%.6f" % float(guard.get("detection")),
		"wp": str(int(guard.get("wp_index"))),
		"wait": "%.6f" % float(guard.call("patrol_wait_remaining")),
		"ever": "true" if gs.get("ever_spotted") == true else "false",
		"rows": rows,
		"ticks": int(shadow_ref.ticks) if shadow_ref != null else 0,
		"transitions": int(shadow_ref.interpreter.transitions_fired.size()) if shadow_ref != null and shadow_ref.interpreter != null else 0,
		"visited": int(shadow_ref.interpreter.visited.size()) if shadow_ref != null and shadow_ref.interpreter != null else 0,
		"trees": ",".join(PackedStringArray(trees)),
		"reached_patrol": reached_patrol,
		"samples": " ".join(samples),
	}
	print("SHADOW_PHASE mode=%s sig=%s pos=%s state=%s detection=%s wp=%s ever=%s rows=%d ticks=%d transitions=%d trees=%s reached_patrol=%s samples=%s"
		% [mode, str(digest), str(result["pos"]), str(result["state"]), str(result["detection"]),
			str(result["wp"]), str(result["ever"]), rows, int(result["ticks"]), int(result["transitions"]),
			str(result["trees"]), "true" if reached_patrol else "false", str(result["samples"])])
	guard.queue_free()
	floor_body.queue_free()
	for _i: int in range(3):
		await process_frame
	return result


func _build_floor(root: Node, at: Vector3) -> StaticBody3D:
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
	return body
