extends SceneTree
## Temporary Guildhall cost-isolation probe (gitignored build/qa).
## Toggles geometry, lights, and shadows to attribute the frame time.

const WARM_FRAMES: int = 10
const MEASURE_FRAMES: int = 60
const MAX_WAIT_FRAMES: int = 1200

var _meshes: Array[GeometryInstance3D] = []
var _lights: Array[Light3D] = []
var _shapes: Array[CollisionShape3D] = []
var _particles: Array[Node3D] = []


func _init() -> void:
	call_deferred("_run")


func _wait_frames(n: int) -> void:
	for _i: int in range(clampi(n, 1, 4000)):
		await process_frame


func _measure(label: String) -> void:
	await _wait_frames(WARM_FRAMES)
	var dts: Array[float] = []
	var prev: int = Time.get_ticks_usec()
	for _i: int in range(MEASURE_FRAMES):
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
	var draws: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	var prims: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	print("PERF_RESULT %s mean_ms=%.2f p50_ms=%.2f p95_ms=%.2f fps=%.1f draws=%d objects=%d prims=%d" % [label, mean, p50, dts[idx95], 1000.0 / maxf(mean, 0.001), draws, objs, prims])


func _collect(node: Node) -> void:
	if node is GeometryInstance3D:
		_meshes.append(node as GeometryInstance3D)
	if node is Light3D:
		_lights.append(node as Light3D)
	if node is CollisionShape3D:
		_shapes.append(node as CollisionShape3D)
	if node is GPUParticles3D or node is CPUParticles3D:
		_particles.append(node as Node3D)
	for c: Node in node.get_children():
		_collect(c)


func _set_meshes(v: bool) -> void:
	for m: GeometryInstance3D in _meshes:
		m.visible = v


func _set_lights(v: bool) -> void:
	for l: Light3D in _lights:
		l.visible = v


func _set_shadows(v: bool) -> void:
	for l: Light3D in _lights:
		l.shadow_enabled = v


func _set_particles(v: bool) -> void:
	for p: Node3D in _particles:
		p.visible = v


func _wait_ready(mission: Node) -> bool:
	var waited: int = 0
	while waited < MAX_WAIT_FRAMES:
		var p_var: Variant = mission.get("player")
		var doors: Array[Node] = get_nodes_in_group("swinging_doors")
		if p_var != null and not doors.is_empty():
			return true
		await process_frame
		waited += 1
	return mission.get("player") != null


func _vram_line(tag: String) -> void:
	var tex: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576
	var vid: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576
	var buf: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)) / 1048576
	print("PERF_VRAM %s texture_mb=%d video_mb=%d buffer_mb=%d" % [tag, tex, vid, buf])


func _run() -> void:
	var res: Vector2i = Vector2i(1920, 1080)
	var contract: int = 4
	var map_id: String = "guildhall"
	var quick: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a == "--quick":
			quick = true
		if a.begins_with("--res="):
			var parts: PackedStringArray = a.substr(6).split("x")
			if parts.size() == 2:
				res = Vector2i(int(parts[0]), int(parts[1]))
		if a.begins_with("--contract="):
			contract = int(a.substr(11))
		if a.begins_with("--map="):
			map_id = a.substr(6)
	root.size = res
	DisplayServer.window_set_size(res)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait_frames(5)

	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("active_contract_order", contract)
		gs.set("active_map_id", map_id)
	var mission_scene: PackedScene = load("res://scenes/mission.tscn") as PackedScene
	var mission: Node3D = mission_scene.instantiate() as Node3D
	root.add_child(mission)
	if not await _wait_ready(mission):
		printerr("PERF_FATAL timeout")
		quit(1)
		return
	await _wait_frames(30)
	_collect(mission)
	var multi: int = 0
	for m: GeometryInstance3D in _meshes:
		if m is MultiMeshInstance3D:
			multi += 1
	print("PERF_COUNTS map=", map_id, " meshes=", _meshes.size(), " multimesh=", multi, " lights=", _lights.size(), " shapes=", _shapes.size(), " particles=", _particles.size(), " res=", res)
	_vram_line("loaded")
	if quick:
		print("PERF_DONE")
		quit(0)
		return

	await _measure("baseline")
	_set_shadows(false)
	await _measure("no_shadows")
	_set_shadows(true)
	_set_lights(false)
	await _measure("no_lights")
	_set_lights(true)
	_set_particles(false)
	await _measure("no_particles")
	_set_particles(true)
	paused = true
	await _measure("paused")
	paused = false
	_set_meshes(false)
	await _measure("no_meshes")
	_set_particles(false)
	await _measure("no_meshes_no_particles")
	paused = true
	await _measure("no_meshes_paused")
	paused = false
	_set_particles(true)
	_set_meshes(true)
	await _measure("restored")

	print("PERF_DONE")
	quit(0)
