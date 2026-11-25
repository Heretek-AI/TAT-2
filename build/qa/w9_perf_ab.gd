extends SceneTree
## W9-P2 B0 collision A/B: authored UE AggGeom vs the pre-W9 AABB heuristic.
##
## One process per mode (`AuthoredCollision` is a process-static cache, so a
## second mode in the same process would reuse the first payload). Loads the
## mission exactly like the game (async path), times the wall load, prints the
## loader's own `LoadTiming` phases (set TAT_LOAD_TIMING=1 in the wrapper), then
## measures the SAME three camera poses with vsync disabled:
##
##   upper_foyer    (27, 29.67, -50) -> (27, 29.67, -60)   interior, KF27
##   foyer_yaw180   (27, 29.67, -50) -> (27, 29.67, -40)   interior, KF27 hall
##   gate           (10, 24.00,  66) -> (10, 25.00,  48)   exterior, KF16/18
##
## Prep is deliberately excluded: it is presentation-bound (~6.9 ms) and has no
## world collision, so it cannot answer this question.
##
## Usage (one Godot at a time, under the shared flock):
##   TAT2_COLLISION=authored TAT_LOAD_TIMING=1 TAT2_AO=on \
##     build/qa/w9_perf_ab.sh authored 1920x1080 240 60
##   TAT2_COLLISION=aabb     TAT_LOAD_TIMING=1 TAT2_AO=on \
##     build/qa/w9_perf_ab.sh aabb 1920x1080 240 60
##
## Output:
##   W9_PERF_AB_START  tag/mode/display/size/frames/warmup
##   W9_LOAD           mode, load_ms (instantiate -> player), ready_ms (+doors)
##   W9_PERF_AB_STATS  mode, shapes/bodies/dropped/budget from level_stats
##   LoadTiming *      (loader, async path; TAT_LOAD_TIMING)
##   W9_PERF           per pose: mean/p50/p95/p99/fps/low1

const DEFAULT_SIZE := Vector2i(1920, 1080)
const EYE_OFFSET := 1.67
const SHIPPED_FOV := 54.54
const MAX_WAIT_FRAMES := 2400
const POSES: Array[Dictionary] = [
	{"id": "upper_foyer", "eye": Vector3(27.0, 28.0 + EYE_OFFSET, -50.0), "target": Vector3(27.0, 29.67, -60.0)},
	{"id": "foyer_yaw180", "eye": Vector3(27.0, 28.0 + EYE_OFFSET, -50.0), "target": Vector3(27.0, 29.67, -40.0)},
	{"id": "gate", "eye": Vector3(10.0, 24.0, 66.0), "target": Vector3(10.0, 25.0, 48.0)},
]

var _size: Vector2i = DEFAULT_SIZE
var _frames: int = 240
var _warmup: int = 60
var _tag: String = ""
var _mode: String = "authored"


func _init() -> void:
	call_deferred("_run")


func _arg(prefix: String, fallback: String) -> String:
	for list: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for arg: String in list:
			if arg.begins_with(prefix):
				return arg.substr(prefix.length()).strip_edges()
	return fallback


func _parse_size(raw: String) -> Vector2i:
	var parts: PackedStringArray = raw.to_lower().split("x", false)
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(maxi(320, int(parts[0])), maxi(180, int(parts[1])))
	return DEFAULT_SIZE


func _wait(n: int) -> void:
	for _i: int in range(maxi(n, 1)):
		await process_frame


func _find_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child: Node in node.get_children():
		var found: WorldEnvironment = _find_env(child)
		if found != null:
			return found
	return null


func _pct(sorted: Array[float], fraction: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx: int = clampi(int(ceil(float(sorted.size()) * fraction)) - 1, 0, sorted.size() - 1)
	return sorted[idx]


func _collision_mode() -> String:
	var raw: String = OS.get_environment("TAT2_COLLISION").strip_edges().to_lower()
	return raw if raw in ["authored", "aabb"] else "authored"


func _measure(scene: String) -> void:
	await _wait(_warmup)
	var dts: Array[float] = []
	var prev: int = Time.get_ticks_usec()
	for _i: int in range(_frames):
		await process_frame
		var now: int = Time.get_ticks_usec()
		dts.append(float(now - prev) / 1000.0)
		prev = now
	var sorted: Array[float] = dts.duplicate()
	sorted.sort()
	var total: float = 0.0
	for d: float in dts:
		total += d
	var mean: float = total / float(dts.size())
	var p50: float = _pct(sorted, 0.50)
	var p95: float = _pct(sorted, 0.95)
	var p99: float = _pct(sorted, 0.99)
	print("W9_PERF scene=%s tag=%s mode=%s ao=%s frames=%d mean_ms=%.2f p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f fps=%.1f low1_fps=%.1f min_ms=%.2f max_ms=%.2f" % [
		scene, _tag, _mode,
		OS.get_environment("TAT2_AO").strip_edges().to_lower() if OS.get_environment("TAT2_AO") != "" else "on",
		dts.size(), mean, p50, p95, p99, 1000.0 / maxf(mean, 0.001),
		1000.0 / maxf(p99, 0.001), sorted[0], sorted[sorted.size() - 1],
	])


func _report_env(scene: String, node: Node) -> void:
	var wenv: WorldEnvironment = _find_env(node)
	if wenv == null or wenv.environment == null:
		printerr("W9_PERF_AB_ENV scene=%s missing WorldEnvironment" % scene)
		return
	var env: Environment = wenv.environment
	print("W9_PERF_AB_ENV scene=%s tag=%s mode=%s ssao=%s ssil=%s tonemap=%d exposure=%.3f glow=%s" % [
		scene, _tag, _mode, str(env.ssao_enabled), str(env.ssil_enabled),
		env.tonemap_mode, env.tonemap_exposure, str(env.glow_enabled),
	])


func _interior_scene() -> bool:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("state", "playing")
		gs.set("thief_id", "spider")
		gs.set("active_contract_order", 4)
		gs.set("active_map_id", "guildhall")
	var t0: int = Time.get_ticks_msec()
	var mission: Node3D = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(mission)
	var waited: int = 0
	while mission.get("player") == null and waited < MAX_WAIT_FRAMES:
		await process_frame
		waited += 1
	var load_ms: int = Time.get_ticks_msec() - t0
	if mission.get("player") == null:
		printerr("W9_PERF_AB mission timeout mode=%s" % _mode)
		return false
	var ready_waited: int = 0
	while get_nodes_in_group("swinging_doors").is_empty() and ready_waited < MAX_WAIT_FRAMES:
		await process_frame
		ready_waited += 1
	var ready_ms: int = Time.get_ticks_msec() - t0
	await _wait(40)
	var hud: Node = mission.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(10)
	var stats: Dictionary = mission.get("level_stats") as Dictionary
	print("W9_LOAD mode=%s load_ms=%d ready_ms=%d waited=%d ready_waited=%d" % [
		_mode, load_ms, ready_ms, waited, ready_waited])
	print("W9_PERF_AB_STATS mode=%s shapes=%d bodies=%d dropped=%d budget_ok=%s" % [
		_mode, int(stats.get("collision_shapes", -1)), int(stats.get("collision_bodies", -1)),
		int(stats.get("collision_dropped", -1)), str(stats.get("collider_budget_ok", false)),
	])
	var player: Node3D = mission.get("player") as Node3D
	if player != null:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.velocity = Vector3.ZERO
	_report_env("interior", mission)
	var cam: Camera3D = Camera3D.new()
	cam.name = "W9PerfAbCamera"
	cam.fov = SHIPPED_FOV
	cam.far = 4000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	mission.add_child(cam)
	for pose: Dictionary in POSES:
		cam.global_position = pose["eye"] as Vector3
		cam.look_at(pose["target"] as Vector3, Vector3.UP)
		cam.current = true
		await _wait(20)
		await _measure(str(pose["id"]))
	mission.queue_free()
	await _wait(10)
	return true


func _run() -> void:
	_tag = _arg("--tag=", "ab")
	_mode = _collision_mode()
	_size = _parse_size(_arg("--size=", "1920x1080"))
	_frames = maxi(30, int(_arg("--frames=", "240")))
	_warmup = maxi(10, int(_arg("--warmup=", "60")))
	root.size = _size
	DisplayServer.window_set_size(_size)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(5)
	print("W9_PERF_AB_START tag=%s mode=%s display=%s size=%s window=%s vsync=%d frames=%d warmup=%d ao=%s" % [
		_tag, _mode, DisplayServer.get_name(), str(_size), str(DisplayServer.window_get_size()),
		DisplayServer.window_get_vsync_mode(), _frames, _warmup,
		OS.get_environment("TAT2_AO"),
	])
	if not await _interior_scene():
		quit(1)
		return
	print("W9_PERF_AB_DONE tag=%s mode=%s" % [_tag, _mode])
	quit(0)
