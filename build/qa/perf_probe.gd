extends SceneTree
## Temporary Wave 3 performance probe (gitignored build/qa).
## Loads Startscreen, Thieves' Den, then Guildhall at the requested window
## resolution and reports frame-time percentiles under effect toggles.
## Vsync is disabled so the numbers are raw render cost; normal quit(0) at end.

const WARM_FRAMES: int = 15
const MEASURE_FRAMES: int = 90
const MAX_WAIT_FRAMES: int = 1200

var _env: Environment = null
var _ssil: bool = true
var _ssr: bool = true
var _vol: bool = true
var _glow: bool = true
var _scale: float = 1.0


func _init() -> void:
	call_deferred("_run")


func _wait_frames(n: int) -> void:
	for _i: int in range(clampi(n, 1, 4000)):
		await process_frame


func _measure(label: String, frames: int = MEASURE_FRAMES) -> void:
	await _wait_frames(WARM_FRAMES)
	var dts: Array[float] = []
	var prev: int = Time.get_ticks_usec()
	for _i: int in range(frames):
		await process_frame
		var now: int = Time.get_ticks_usec()
		dts.append(float(now - prev) / 1000.0)
		prev = now
	dts.sort()
	var total: float = 0.0
	for d: float in dts:
		total += d
	var mean: float = total / float(dts.size())
	var p50: float = dts[int(float(dts.size()) * 0.5)]
	var idx95: int = mini(int(float(dts.size()) * 0.95), dts.size() - 1)
	var p95: float = dts[idx95]
	var fps: float = 1000.0 / maxf(mean, 0.001)
	print("PERF_RESULT %s mean_ms=%.2f p50_ms=%.2f p95_ms=%.2f fps=%.1f frames=%d" % [label, mean, p50, p95, fps, dts.size()])


func _reset_cfg() -> void:
	_env.ssil_enabled = _ssil
	_env.ssr_enabled = _ssr
	_env.volumetric_fog_enabled = _vol
	_env.glow_enabled = _glow
	root.scaling_3d_scale = _scale


func _apply_cfg(cfg: String) -> void:
	_reset_cfg()
	match cfg:
		"no_ssil":
			_env.ssil_enabled = false
		"no_ssr":
			_env.ssr_enabled = false
		"no_vol":
			_env.volumetric_fog_enabled = false
		"no_glow":
			_env.glow_enabled = false
		"no_ssil_ssr":
			_env.ssil_enabled = false
			_env.ssr_enabled = false
		"lean":
			_env.ssil_enabled = false
			_env.ssr_enabled = false
			_env.volumetric_fog_enabled = false
		"scale75":
			root.scaling_3d_scale = 0.75
		"scale667":
			root.scaling_3d_scale = 0.667
		"scale75_lean":
			root.scaling_3d_scale = 0.75
			_env.ssil_enabled = false
			_env.ssr_enabled = false
			_env.volumetric_fog_enabled = false
		_:
			pass


func _find_first_world_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for c: Node in node.get_children():
		var found: WorldEnvironment = _find_first_world_env(c)
		if found != null:
			return found
	return null


func _wait_for_mission_ready(mission: Node) -> bool:
	var waited: int = 0
	while waited < MAX_WAIT_FRAMES:
		var p_var: Variant = mission.get("player")
		var doors: Array[Node] = get_nodes_in_group("swinging_doors")
		if p_var != null and not doors.is_empty():
			return true
		await process_frame
		waited += 1
	return mission.get("player") != null


func _free_clean(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()
	await _wait_frames(10)


func _bench_env(tag: String, cfgs: Array[String]) -> void:
	_env = null
	var wenv: WorldEnvironment = _find_first_world_env(root)
	if wenv != null:
		_env = wenv.environment
	if _env == null:
		print("PERF_ERROR no WorldEnvironment for ", tag)
		return
	_ssil = _env.ssil_enabled
	_ssr = _env.ssr_enabled
	_vol = _env.volumetric_fog_enabled
	_glow = _env.glow_enabled
	_scale = root.scaling_3d_scale
	for cfg: String in cfgs:
		_apply_cfg(cfg)
		await _measure(tag + "/" + cfg)
	_reset_cfg()
	print("PERF_ENV %s ssil=%s ssr=%s vol=%s glow=%s scale=%.2f" % [tag, _ssil, _ssr, _vol, _glow, _scale])


func _run() -> void:
	var res: Vector2i = Vector2i(1920, 1080)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("--res="):
			var parts: PackedStringArray = a.substr(6).split("x")
			if parts.size() == 2:
				res = Vector2i(int(parts[0]), int(parts[1]))
	root.size = res
	DisplayServer.window_set_size(res)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait_frames(5)
	print("PERF_START res=", res, " window=", DisplayServer.window_get_size(), " vsync=", DisplayServer.window_get_vsync_mode())

	# Startscreen
	var mm_script: GDScript = load("res://src/ui/main_menu.gd") as GDScript
	if mm_script != null:
		var mm: Control = mm_script.new() as Control
		mm.size = Vector2(res)
		root.add_child(mm)
		await _wait_frames(20)
		await _bench_env("startscreen", ["baseline", "no_ssil", "no_ssr", "no_vol", "lean", "scale667"])
		await _free_clean(mm)

	# Thieves' Den
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("active_contract_order", 1)
		gs.set("active_map_id", "thieves_den")
	var mission_scene: PackedScene = load("res://scenes/mission.tscn") as PackedScene
	if mission_scene == null:
		printerr("PERF_FATAL missing mission scene")
		quit(1)
		return
	var den: Node3D = mission_scene.instantiate() as Node3D
	root.add_child(den)
	if not await _wait_for_mission_ready(den):
		printerr("PERF_FATAL den timeout")
		quit(1)
		return
	await _wait_frames(30)
	await _bench_env("den", ["baseline", "no_ssil", "no_ssr", "no_vol", "no_glow", "no_ssil_ssr", "lean", "scale75", "scale667", "scale75_lean"])
	await _free_clean(den)

	# Guildhall
	if gs != null:
		gs.set("active_contract_order", 4)
		gs.set("active_map_id", "guildhall")
	var gh: Node3D = mission_scene.instantiate() as Node3D
	root.add_child(gh)
	if not await _wait_for_mission_ready(gh):
		printerr("PERF_FATAL guildhall timeout")
		quit(1)
		return
	await _wait_frames(30)
	await _bench_env("guildhall", ["baseline", "lean", "scale667", "scale75_lean"])
	await _free_clean(gh)

	print("PERF_DONE")
	quit(0)
