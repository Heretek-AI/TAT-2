extends SceneTree
## PG-1 cost-isolation probe (Wave 1, gitignored build/qa).
##
## Loads one contract at a fixed framebuffer size and measures frame time with
## one cost class disabled at a time, so the remaining Guildhall/Den frame
## budget can be attributed to shadows, decorative (far-batched) geometry,
## all geometry, lights, or particles. Every phase restores the scene.
##
## Usage (script args after `--`):
##   --contract=4 --res=1920x1080 --frames=60 --tag=ghcost
##   --contract=1 --res=1280x720  --frames=120 --tag=dencost
##
## Always ends in quit(0)/quit(1) so the engine performs a real teardown.

const WARM_FRAMES: int = 20
const MAX_LOAD_FRAMES: int = 1800

var _res: Vector2i = Vector2i(1920, 1080)
var _contract: int = 4
var _frames: int = 60
var _tag: String = "cost"

var _meshes: Array[GeometryInstance3D] = []
var _decorative: Array[GeometryInstance3D] = []
var _lights: Array[Light3D] = []
var _shadowed: Array[Light3D] = []
var _particles: Array[Node3D] = []
var _canvases: Array[CanvasLayer] = []


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		var arg: String = str(a).strip_edges()
		if arg.begins_with("--contract="):
			_contract = int(arg.substr(11))
		elif arg.begins_with("--res="):
			var parts: PackedStringArray = arg.substr(6).split("x")
			if parts.size() == 2:
				_res = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--frames="):
			_frames = maxi(10, int(arg.substr(9)))
		elif arg.begins_with("--tag="):
			_tag = arg.substr(6)
	call_deferred("_run")


func _wait_frames(n: int) -> void:
	for _i: int in range(maxi(n, 1)):
		await process_frame


func _vram_line(label: String) -> void:
	var tex: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576
	var vid: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576
	print("PERF_VRAM %s %s texture_mb=%d video_mb=%d" % [_tag, label, tex, vid])


func _measure(label: String) -> void:
	await _wait_frames(WARM_FRAMES)
	var dts: Array[float] = []
	var prev: int = Time.get_ticks_usec()
	for _i: int in range(_frames):
		await process_frame
		var now: int = Time.get_ticks_usec()
		dts.append(float(now - prev) / 1000.0)
		prev = now
	dts.sort()
	var total: float = 0.0
	for d: float in dts:
		total += d
	var mean_ms: float = total / float(dts.size())
	var p50: float = dts[int(float(dts.size()) * 0.5)]
	var p95: float = dts[mini(int(float(dts.size()) * 0.95), dts.size() - 1)]
	var draws: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	print("PERF_RESULT %s %s res=%dx%d mean_ms=%.2f p50_ms=%.2f p95_ms=%.2f fps=%.1f draws=%d prims=%d" % [
		_tag, label, _res.x, _res.y, mean_ms, p50, p95, 1000.0 / maxf(mean_ms, 0.001), draws, prims])


func _collect(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi: GeometryInstance3D = node as GeometryInstance3D
		_meshes.append(gi)
		if gi.get_meta("decorative", false) == true:
			_decorative.append(gi)
	if node is Light3D:
		var l: Light3D = node as Light3D
		_lights.append(l)
		if l.shadow_enabled:
			_shadowed.append(l)
	if node is GPUParticles3D or node is CPUParticles3D:
		_particles.append(node as Node3D)
	if node is CanvasLayer:
		_canvases.append(node as CanvasLayer)
	for c: Node in node.get_children():
		_collect(c)


func _set_visible(nodes: Array, value: bool) -> void:
	for n_var: Variant in nodes:
		var n: Node3D = n_var as Node3D
		if is_instance_valid(n):
			n.visible = value


func _set_shadows(value: bool) -> void:
	for l_var: Variant in _shadowed:
		var l: Light3D = l_var as Light3D
		if is_instance_valid(l):
			l.shadow_enabled = value


func _wait_ready(mission: Node) -> bool:
	var waited: int = 0
	while waited < MAX_LOAD_FRAMES:
		if mission.get("player") != null:
			if _contract <= 1 or not get_nodes_in_group("swinging_doors").is_empty():
				return true
		await process_frame
		waited += 1
	return mission.get("player") != null


func _find_world_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for c: Node in node.get_children():
		var found: WorldEnvironment = _find_world_env(c)
		if found != null:
			return found
	return null


func _run() -> void:
	print("PG1_COST tag=%s res=%dx%d contract=%d frames=%d" % [_tag, _res.x, _res.y, _contract, _frames])
	root.size = _res
	DisplayServer.window_set_size(_res)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait_frames(5)

	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("active_contract_order", _contract)
	var mission_scene: PackedScene = load("res://scenes/mission.tscn") as PackedScene
	if mission_scene == null:
		printerr("PG1_COST_FAIL mission scene missing")
		quit(1)
		return
	var mission: Node = mission_scene.instantiate()
	root.add_child(mission)
	if not await _wait_ready(mission):
		printerr("PG1_COST_FAIL load timeout contract=%d" % _contract)
		mission.queue_free()
		await _wait_frames(10)
		quit(1)
		return
	await _wait_frames(30)
	_collect(mission)
	print("PG1_COST_COUNTS meshes=%d decorative=%d lights=%d shadowed=%d particles=%d" % [
		_meshes.size(), _decorative.size(), _lights.size(), _shadowed.size(), _particles.size()])
	_vram_line("loaded")

	await _measure("baseline")
	_set_shadows(false)
	await _measure("no_shadows")
	_set_shadows(true)
	_set_visible(_decorative, false)
	await _measure("no_decorative")
	_set_visible(_meshes, false)
	await _measure("no_meshes")
	_set_visible(_meshes, true)
	_set_visible(_lights, false)
	await _measure("no_lights")
	_set_visible(_lights, true)
	_set_visible(_particles, false)
	await _measure("no_particles")
	_set_visible(_particles, true)
	await _measure("restored")
	paused = true
	await _measure("paused")
	paused = false

	# Environment pass attribution: which full-screen effect owns the floor cost.
	var wenv: WorldEnvironment = _find_world_env(root)
	if wenv != null and wenv.environment != null:
		var env: Environment = wenv.environment
		var sky_keep: Sky = env.sky
		var bg_keep: int = env.background_mode
		var ssil_keep: bool = env.ssil_enabled
		var ssr_keep: bool = env.ssr_enabled
		var vol_keep: bool = env.volumetric_fog_enabled
		var glow_keep: bool = env.glow_enabled
		env.volumetric_fog_enabled = false
		await _measure("no_vol")
		env.volumetric_fog_enabled = vol_keep
		env.ssil_enabled = false
		env.ssr_enabled = false
		await _measure("no_ssil_ssr")
		env.ssil_enabled = ssil_keep
		env.ssr_enabled = ssr_keep
		env.glow_enabled = false
		await _measure("no_glow")
		env.glow_enabled = glow_keep
		env.ssil_enabled = false
		env.ssr_enabled = false
		env.volumetric_fog_enabled = false
		env.glow_enabled = false
		env.sky = null
		env.background_mode = Environment.BG_COLOR
		await _measure("no_env_fx_no_sky")
		env.sky = sky_keep
		env.background_mode = bg_keep
		env.ssil_enabled = ssil_keep
		env.ssr_enabled = ssr_keep
		env.volumetric_fog_enabled = vol_keep
		env.glow_enabled = glow_keep
		print("PG1_COST_ENV restored ssil=%s ssr=%s vol=%s glow=%s sky=%s" % [
			str(ssil_keep), str(ssr_keep), str(vol_keep), str(glow_keep), str(sky_keep != null)])
	# Floor measurement: everything off. Whatever remains is present/engine cost
	# for this framebuffer, not scene cost (Xvfb presentation is a known floor).
	_set_visible(_meshes, false)
	_set_visible(_lights, false)
	_set_visible(_canvases, false)
	if wenv != null and wenv.environment != null:
		wenv.environment.ssil_enabled = false
		wenv.environment.ssr_enabled = false
		wenv.environment.volumetric_fog_enabled = false
		wenv.environment.glow_enabled = false
		wenv.environment.sky = null
		wenv.environment.background_mode = Environment.BG_COLOR
	await _measure("empty_floor")

	mission.queue_free()
	await _wait_frames(30)
	print("PG1_COST_QUIT tag=%s" % _tag)
	quit(0)
