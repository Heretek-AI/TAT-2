extends SceneTree
## W9-P4 S1 — shadow-mode side-effect proof (suite 111), extended by Phase 3B.1.
##
## Runs the SAME arena in one process under three arms:
##   off     - no runner; the FSM drives;
##   shadow  - a runner observes and traces, and writes nothing;
##   patrol  - the EXPERIMENTAL writer spike (`TAT2_STATETREE_WRITER=on`) owns
##             the NEUTRAL patrol movement (`writer_spike.gd`), so the trajectory
##             is expected to differ from the FSM's.
## Each arm ticks a live guard on a live physics floor for 240 frames and records
## every frame's planar position. The A/B metric is the MAX PER-FRAME PLANAR
## DEVIATION from the `off` trajectory (metres):
##   * off vs shadow  must be 0.000 m (identical, <= 1e-9 m);
##   * patrol vs off  must be >= 0.05 m (different) and <= 6.0 m (bounded; the
##     6x6 m waypoint square means a divergent writer would exceed it), and the
##     writer's own max planar step must be <= patrol_speed/60 * 1.5 + 0.01 m
##     (one bounded `move_and_slide`, no teleport).
##
## One process, three arms, rather than four child engines: a child boot is
## ~150 s on this host, so the arms cannot each pay it and stay in the gate
## budget. The shipping switch is still proven — `_check_env_flag` drives
## `OS.set_environment(...)` and re-parses it, which is exactly what
## `guard_ai.gd` reads.
##
## Run: tools/godot --headless --path game --script res://tests/test_w9p4_shadow.gd
## Marker: W9P4_SHADOW_SUMMARY: fails=0 checks=N

const GUARD_SCRIPT := "res://src/ai/guard_ai.gd"
const Trace = preload("res://src/ai/statetree/trace.gd")
const ShadowRunner = preload("res://src/ai/statetree/shadow_runner.gd")
const GuardBindings = preload("res://src/ai/statetree/guard_bindings.gd")
const WriterSpike = preload("res://src/ai/statetree/writer_spike.gd")

const FRAMES: int = 240
## A/B tolerances (documented in the header and the 3B.1 report).
const IDENTICAL_TOLERANCE_M: float = 1e-9
const DIFFERENT_MIN_M: float = 0.05
const BOUNDED_MAX_M: float = 6.0
const STEP_SLACK_M: float = 0.01
const STEP_FACTOR: float = 1.5

var fails: int = 0
var checks: int = 0


func _initialize() -> void:
	await process_frame
	_check_env_flag()
	await _check_live_event()
	var off: Dictionary = await _phase("off")
	var shadow: Dictionary = await _phase("shadow")
	var patrol: Dictionary = await _phase("patrol", true)
	_ok(bool(off.get("started", false)), "off phase ran the arena")
	_ok(bool(shadow.get("started", false)), "shadow phase ran the arena")
	_ok(bool(patrol.get("started", false)), "patrol+writer phase ran the arena")
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
	_check_ab(off, shadow, patrol)
	print("W9P4_SHADOW off_sig=%s shadow_sig=%s patrol_sig=%s shadow_rows=%s shadow_ticks=%s transitions=%s visited=%s reached_patrol=%s trees=%s"
		% [str(off.get("sig")), str(shadow.get("sig")), str(patrol.get("sig")), str(shadow.get("rows")),
			str(shadow.get("ticks")), str(shadow.get("transitions")), str(shadow.get("visited")),
			str(shadow.get("reached_patrol")), str(shadow.get("trees"))])
	print("W9P4_AB metric=max_per_frame_planar_deviation_m identical_tolerance=%s different_min=%.2f bounded_max=%.1f dev_off_shadow=%.9f dev_patrol=%.3f writer_moves=%d writer_advances=%d writer_holds=%d writer_step_max=%.4f step_tolerance=%.4f"
		% [str(IDENTICAL_TOLERANCE_M), DIFFERENT_MIN_M, BOUNDED_MAX_M,
			float(patrol.get("dev_off_shadow", -1.0)), float(patrol.get("dev_from_off", -1.0)),
			int(patrol.get("writer_moves", 0)), int(patrol.get("writer_advances", 0)),
			int(patrol.get("writer_holds", 0)), float(patrol.get("writer_step_max", 0.0)),
			float(patrol.get("step_tolerance", 0.0))])
	print("W9P4_SHADOW_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(0 if fails == 0 else 1)


## Phase 3B.1 mode contract: default off, unknown fails closed, and `patrol`
## refuses to attach unless the explicit experimental writer flag is on.
func _check_env_flag() -> void:
	var previous_mode: String = OS.get_environment(ShadowRunner.MODE_ENV)
	var previous_writer: String = OS.get_environment(WriterSpike.WRITER_ENV)
	# 1. Unset -> the resolver's default, which must be `off`.
	OS.unset_environment(ShadowRunner.MODE_ENV)
	WriterSpike.set_for_test("off")
	ShadowRunner.set_mode_for_test("")
	_ok(str(ShadowRunner.DEFAULT_MODE) == "off",
		"the resolver default mode is off (got %s)" % ShadowRunner.DEFAULT_MODE)
	_ok(str(ShadowRunner.parse_mode("")) == "off", "parse_mode(\"\") is off")
	_ok(str(ShadowRunner.mode()) == "off", "an unset TAT2_STATETREE resolves to off")
	_ok(not ShadowRunner.enabled(), "an unset TAT2_STATETREE attaches no runner")
	# 2. shadow.
	OS.set_environment(ShadowRunner.MODE_ENV, "shadow")
	ShadowRunner.set_mode_for_test("")
	_ok(str(ShadowRunner.mode()) == "shadow", "TAT2_STATETREE=shadow selects shadow")
	_ok(ShadowRunner.enabled(), "shadow is enabled")
	# 3. An unknown value fails closed to off.
	OS.set_environment(ShadowRunner.MODE_ENV, "nonsense")
	ShadowRunner.set_mode_for_test("")
	_ok(str(ShadowRunner.mode()) == "off", "an unknown TAT2_STATETREE value fails closed to off")
	_ok(not ShadowRunner.enabled(), "an unknown TAT2_STATETREE attaches no runner")
	# 4. `patrol` alone is REFUSED (not a warning-only shadow alias).
	OS.set_environment(ShadowRunner.MODE_ENV, "patrol")
	WriterSpike.set_for_test("off")
	ShadowRunner.set_mode_for_test("")
	_ok(str(ShadowRunner.mode()) == "patrol", "TAT2_STATETREE=patrol is recognised")
	_ok(not ShadowRunner.enabled(), "patrol without the writer flag is not enabled")
	_ok(GuardBindings.new().mutates() == false,
		"guard bindings do not mutate (that is why patrol must refuse)")
	var refused_attach: RefCounted = ShadowRunner.attach(null)
	_ok(refused_attach == null,
		"TAT2_STATETREE=patrol refuses to attach when TAT2_STATETREE_WRITER is off")
	var refusal: Dictionary = ShadowRunner.patrol_refusal()
	_ok(bool(refusal.get("refused", false)), "the patrol refusal is recorded")
	_ok(str(refusal.get("reason", "")).find("mutates()") >= 0,
		"the refusal names mutates() (got %s)" % str(refusal.get("reason", "")))
	# 5. The writer flag is explicit and itself fails closed on an unknown value.
	_ok(not WriterSpike.enabled(), "the writer is off by default")
	_ok(str(WriterSpike._parse("nonsense")) == "off", "an unknown writer value fails closed to off")
	WriterSpike.set_for_test("on")
	_ok(WriterSpike.enabled(), "TAT2_STATETREE_WRITER=on enables the experimental spike")
	_ok(ShadowRunner.enabled(), "patrol + writer is enabled")
	var opened_attach: RefCounted = ShadowRunner.attach(null)
	_ok(opened_attach != null and opened_attach.writer != null,
		"patrol + writer attaches a runner with a writer spike")
	# 6. Restore the environment exactly.
	if previous_mode == "":
		OS.unset_environment(ShadowRunner.MODE_ENV)
	else:
		OS.set_environment(ShadowRunner.MODE_ENV, previous_mode)
	if previous_writer == "":
		OS.unset_environment(WriterSpike.WRITER_ENV)
	else:
		OS.set_environment(WriterSpike.WRITER_ENV, previous_writer)
	WriterSpike.set_for_test("off")
	ShadowRunner.set_mode_for_test("")


func _ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		fails += 1
		printerr("FAIL: ", label)


# ---------------------------------------------------------------------------
# A/B: trajectory comparison
# ---------------------------------------------------------------------------


func _check_ab(off: Dictionary, shadow: Dictionary, patrol: Dictionary) -> void:
	var off_track: Array = off.get("track", [])
	var shadow_track: Array = shadow.get("track", [])
	var patrol_track: Array = patrol.get("track", [])
	_ok(off_track.size() == FRAMES and shadow_track.size() == FRAMES and patrol_track.size() == FRAMES,
		"every arm recorded %d frames (off=%d shadow=%d patrol=%d)"
			% [FRAMES, off_track.size(), shadow_track.size(), patrol_track.size()])
	var dev_shadow: float = _max_deviation(off_track, shadow_track)
	var dev_patrol: float = _max_deviation(off_track, patrol_track)
	patrol["dev_off_shadow"] = dev_shadow
	patrol["dev_from_off"] = dev_patrol
	_ok(dev_shadow <= IDENTICAL_TOLERANCE_M,
		"off and shadow trajectories are identical (max deviation %.9f m <= %s m)"
			% [dev_shadow, str(IDENTICAL_TOLERANCE_M)])
	_ok(dev_patrol >= DIFFERENT_MIN_M,
		"the writer trajectory differs from the FSM (max deviation %.3f m >= %.2f m)"
			% [dev_patrol, DIFFERENT_MIN_M])
	_ok(dev_patrol <= BOUNDED_MAX_M,
		"the writer trajectory is bounded (max deviation %.3f m <= %.1f m)"
			% [dev_patrol, BOUNDED_MAX_M])
	# The writer actually drove the guard, and its steps stayed bounded.
	_ok(int(patrol.get("writer_moves", 0)) > 0,
		"the writer moved the guard (moves=%d)" % int(patrol.get("writer_moves", 0)))
	_ok(int(patrol.get("writer_advances", 0)) > 0,
		"the writer completed authored patrol segments (advances=%d)" % int(patrol.get("writer_advances", 0)))
	_ok(int(patrol.get("writer_holds", 0)) > 0,
		"the writer held on non-move leaves (holds=%d)" % int(patrol.get("writer_holds", 0)))
	var speed: float = float(patrol.get("patrol_speed", 0.0))
	var step_tolerance: float = speed / 60.0 * STEP_FACTOR + STEP_SLACK_M
	patrol["step_tolerance"] = step_tolerance
	_ok(float(patrol.get("writer_step_max", 999.0)) <= step_tolerance,
		"the writer step is bounded (max step %.4f m <= %.4f m)"
			% [float(patrol.get("writer_step_max", 999.0)), step_tolerance])
	# No teleport: every recorded writer position is inside the 6x6 m arena + 1 m.
	var inside: bool = true
	for p: Variant in patrol_track:
		var v: Vector2 = p
		if absf(v.x) > 5.0 or absf(v.y) > 5.0:
			inside = false
			break
	_ok(inside, "the writer stayed inside the synthetic arena")
	# The writer arm still runs the authored tree.
	_ok(bool(patrol.get("reached_patrol", false)), "the writer arm reached ST_Patrol")
	_ok(int(patrol.get("rows", 0)) > 0, "the writer arm records trace rows (got %s)" % str(patrol.get("rows")))


func _max_deviation(a: Array, b: Array) -> float:
	var count: int = mini(a.size(), b.size())
	var worst: float = 0.0
	for i: int in range(count):
		var pa: Vector2 = a[i]
		var pb: Vector2 = b[i]
		worst = maxf(worst, pa.distance_to(pb))
	return worst


# ---------------------------------------------------------------------------
# Phase 3B.1 live event: the existing hearing path emits StateTreeEvent.StimChange
# ---------------------------------------------------------------------------


func _check_live_event() -> void:
	ShadowRunner.set_mode_for_test("shadow")
	WriterSpike.set_for_test("off")
	Trace.reset_shared()
	var root: Window = get_root()
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("FAIL: GameState autoload missing")
		fails += 1
		return
	gs.set("state", "playing")
	var floor_body: StaticBody3D = _build_floor(root, Vector3(0, -0.55, 0))
	await physics_frame
	var guard: CharacterBody3D = (load(GUARD_SCRIPT) as GDScript).new() as CharacterBody3D
	guard.name = "EventGuard"
	guard.position = Vector3(0, 0, 0)
	guard.set("patrol_points", [Vector3(0, 0, 0), Vector3(0, 0, 4)] as Array[Vector3])
	root.add_child(guard)
	var runner: RefCounted = guard.get("_st_shadow")
	await physics_frame
	await physics_frame
	_ok(runner != null, "the live-event guard has a shadow runner")
	if runner == null:
		guard.queue_free()
		floor_body.queue_free()
		return
	_ok((runner.events_emitted as Array).is_empty(), "no StateTreeEvent is emitted before any stimulus")
	# A real NoiseBus record through the real signal: the guard must pass the
	# authored heard-by/query/range filters and then push the authored tag. The
	# autoload global is not registered when a `--script` SceneTree compiles, so
	# the node is looked up by name (same pattern as the hearing suites).
	var noise_bus: Node = root.get_node_or_null("NoiseBus")
	_ok(noise_bus != null, "NoiseBus autoload present")
	if noise_bus == null:
		guard.queue_free()
		floor_body.queue_free()
		return
	noise_bus.call("emit_noise", (guard as Node3D).global_position + Vector3(1.0, 0, 0), 3.0, null, "footstep")
	await physics_frame
	await physics_frame
	var emitted: Array = runner.events_emitted
	_ok(emitted.size() == 1, "one live StateTreeEvent was pushed (got %d)" % emitted.size())
	if not emitted.is_empty():
		_ok(str((emitted[0] as Dictionary).get("tag", "")) == "StateTreeEvent.StimChange",
			"the live tag is StateTreeEvent.StimChange (got %s)"
				% str((emitted[0] as Dictionary).get("tag", "")))
	_ok(int(runner.interpreter.stats.get("events", 0)) >= 1,
		"the interpreter received the live event (stats.events=%d)"
			% int(runner.interpreter.stats.get("events", 0)))
	_ok(str(guard.get("last_heard_tag")) == "footstep",
		"the hearing path accepted the record (last_heard_tag=%s)" % str(guard.get("last_heard_tag")))
	print("W9P4_EVENT tag=%s count=%d last_heard=%s stats_events=%d"
		% ["StateTreeEvent.StimChange", emitted.size(), str(guard.get("last_heard_tag")),
			int(runner.interpreter.stats.get("events", 0))])
	guard.queue_free()
	floor_body.queue_free()
	for _i: int in range(3):
		await process_frame


# ---------------------------------------------------------------------------
# One arena phase
# ---------------------------------------------------------------------------


func _phase(mode: String, with_writer: bool = false) -> Dictionary:
	ShadowRunner.set_mode_for_test(mode)
	WriterSpike.set_for_test("on" if with_writer else "off")
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
	var writer_ref: RefCounted = guard.get("_st_writer")
	if with_writer:
		_ok(shadow_ref != null and writer_ref != null,
			"patrol+writer attaches both a runner and the writer spike")
	await physics_frame
	var digest: int = 1469598103934665603  # FNV-1a offset basis (int64 wraps)
	var samples: PackedStringArray = []
	var track: Array = []
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
		track.append(Vector2(node.global_position.x, node.global_position.z))
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
	var writer_summary: Dictionary = writer_ref.summary() if writer_ref != null else {}
	var result: Dictionary = {
		"started": true,
		"mode": mode,
		"writer": with_writer,
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
		"track": track,
		"patrol_speed": float(guard.get("patrol_speed")),
		"writer_moves": int(writer_summary.get("moves", 0)),
		"writer_advances": int(writer_summary.get("advances", 0)),
		"writer_holds": int(writer_summary.get("holds", 0)),
		"writer_step_max": float(writer_summary.get("max_planar_step_m", 0.0)),
		"writer_path_m": float(writer_summary.get("path_m", 0.0)),
	}
	print("SHADOW_PHASE mode=%s writer=%s sig=%s pos=%s state=%s detection=%s wp=%s ever=%s rows=%d ticks=%d transitions=%d trees=%s reached_patrol=%s samples=%s"
		% [mode, "true" if with_writer else "false", str(digest), str(result["pos"]), str(result["state"]),
			str(result["detection"]), str(result["wp"]), str(result["ever"]), rows, int(result["ticks"]),
			int(result["transitions"]), str(result["trees"]), "true" if reached_patrol else "false",
			str(result["samples"])])
	print("SHADOW_WRITER mode=%s moves=%d advances=%d holds=%d step_max=%.4f path_m=%.3f"
		% [mode, int(result["writer_moves"]), int(result["writer_advances"]),
			int(result["writer_holds"]), float(result["writer_step_max"]), float(result["writer_path_m"])])
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
