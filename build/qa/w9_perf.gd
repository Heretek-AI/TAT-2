extends SceneTree
## W9-P0 perf matrix: prep stage + two Guildhall interiors, AO on/off.
##
## One process per TAT2_AO setting (the lever is read from the environment by
## WeatherProfile.ao_enabled(), weather_profile.gd:341). Vsync is disabled and
## frame times are wall-clock deltas, the same method as build/qa/perf_probe.gd
## (`_measure`, warm 15 / measure 90) and game/tests/perf/perf_matrix_runner.gd
## (`_pct`, p50/p95/p99). 240 measured frames after 60 warm frames per scene.
##
## Usage:
##   TAT2_AO=on tools/godot --path game --rendering-driver vulkan \
##     --script build/qa/w9_perf.gd -- --tag=ao_on --frames=240 --warmup=60
##
## Prints one W9_PERF line per scene plus W9_PERF_ENV with the live Environment
## flags, so a log can never claim an A/B it did not apply.

const DEFAULT_SIZE := Vector2i(1920, 1080)
const EYE_OFFSET := 1.67
const SHIPPED_FOV := 54.54
const MAX_WAIT_FRAMES := 1800

var _size: Vector2i = DEFAULT_SIZE
var _frames: int = 240
var _warmup: int = 60
var _tag: String = ""


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
	print("W9_PERF scene=%s tag=%s ao=%s frames=%d mean_ms=%.2f p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f fps=%.1f low1_fps=%.1f min_ms=%.2f max_ms=%.2f" % [
		scene, _tag,
		OS.get_environment("TAT2_AO").strip_edges().to_lower() if OS.get_environment("TAT2_AO") != "" else "on",
		dts.size(), mean, p50, p95, p99, 1000.0 / maxf(mean, 0.001),
		1000.0 / maxf(p99, 0.001), sorted[0], sorted[sorted.size() - 1],
	])


func _report_env(scene: String, node: Node) -> void:
	var wenv: WorldEnvironment = _find_env(node)
	if wenv == null or wenv.environment == null:
		printerr("W9_PERF_ENV scene=%s missing WorldEnvironment" % scene)
		return
	var env: Environment = wenv.environment
	print("W9_PERF_ENV scene=%s tag=%s ssao=%s ssil=%s ssr=%s vol=%s tonemap=%d exposure=%.3f glow=%s" % [
		scene, _tag, str(env.ssao_enabled), str(env.ssil_enabled), str(env.ssr_enabled),
		str(env.volumetric_fog_enabled), env.tonemap_mode, env.tonemap_exposure,
		str(env.glow_enabled),
	])


func _prep_scene() -> void:
	var mp: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	mp.size = Vector2(_size)
	root.add_child(mp)
	await _wait(4)
	mp.call("open_prep", "guildhall", 1, "Solo", 0)
	var waited: int = 0
	while get_nodes_in_group("prep_skyline").is_empty() and waited < 900:
		await process_frame
		waited += 1
	await _wait(30)
	_report_env("prep", mp)
	await _measure("prep")
	mp.queue_free()
	await _wait(10)


func _interior_scene() -> bool:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("state", "playing")
		gs.set("thief_id", "spider")
		gs.set("active_contract_order", 4)
		gs.set("active_map_id", "guildhall")
	var mission: Node3D = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(mission)
	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and waited < MAX_WAIT_FRAMES:
		await process_frame
		waited += 1
	if mission.get("player") == null:
		printerr("W9_PERF mission timeout")
		return false
	await _wait(40)
	var hud: Node = mission.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(10)
	var player: Node3D = mission.get("player") as Node3D
	if player != null:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.velocity = Vector3.ZERO
	_report_env("interior", mission)
	var cam: Camera3D = Camera3D.new()
	cam.name = "W9PerfCamera"
	cam.fov = SHIPPED_FOV
	cam.far = 4000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	mission.add_child(cam)
	var poses: Array[Dictionary] = [
		{"id": "upper_foyer", "eye": Vector3(27.0, 28.0 + EYE_OFFSET, -50.0), "target": Vector3(27.0, 29.67, -60.0)},
		{"id": "foyer_yaw180", "eye": Vector3(27.0, 28.0 + EYE_OFFSET, -50.0), "target": Vector3(27.0, 29.67, -40.0)},
	]
	for pose: Dictionary in poses:
		cam.global_position = pose["eye"] as Vector3
		cam.look_at(pose["target"] as Vector3, Vector3.UP)
		cam.current = true
		await _wait(20)
		await _measure(str(pose["id"]))
	mission.queue_free()
	await _wait(10)
	return true


func _run() -> void:
	_tag = _arg("--tag=", "run")
	_size = _parse_size(_arg("--size=", "1920x1080"))
	_frames = maxi(30, int(_arg("--frames=", "240")))
	_warmup = maxi(10, int(_arg("--warmup=", "60")))
	root.size = _size
	DisplayServer.window_set_size(_size)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait(5)
	print("W9_PERF_START tag=%s ao=%s size=%s window=%s vsync=%d frames=%d warmup=%d" % [
		_tag, OS.get_environment("TAT2_AO"), str(_size), str(DisplayServer.window_get_size()),
		DisplayServer.window_get_vsync_mode(), _frames, _warmup,
	])
	await _prep_scene()
	if not await _interior_scene():
		quit(1)
		return
	print("W9_PERF_DONE tag=%s" % _tag)
	quit(0)
