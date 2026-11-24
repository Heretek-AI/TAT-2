extends SceneTree
## PG-1 live Vulkan teardown + frame-time probe (Wave 1).
##
## Loads one contract at a fixed framebuffer size, measures frame time over a
## bounded warm sample, prints PERF_RESULT/PERF_VRAM, frees the mission, and
## then calls quit() on every path so the engine runs its REAL teardown and the
## exit-time RID/ObjectDB report is produced (a SIGTERM probe proves nothing:
## the process dies before it can leak).
##
## Usage (script args after `--`):
##   --contract=1 --res=1280x720 --frames=120 --tag=den720
##   --contract=4 --res=1920x1080 --frames=60 --tag=gh1080
##   --cycles=2           repeat load+free twice (proves whether exit-time
##                        Texture RID leaks scale per load or stay constant)
##   --no-free            keep the mission mounted (isolation runs only)
##   --menu               measure the Startscreen/backdrop instead of a mission
##   --free-only          skip the measurement, only load + free + quit
##
## Every path ends in quit(0)/quit(1); the wrapper adds timeout + file redirect.

const MAX_LOAD_FRAMES: int = 1800
const WARM_FRAMES: int = 20

var _res: Vector2i = Vector2i(1280, 720)
var _contract: int = 1
var _frames: int = 120
var _tag: String = "probe"
var _no_free: bool = false
var _free_only: bool = false
var _menu: bool = false
## Load/free cycles in one process, used to prove whether exit-time RID/
## Texture leaks scale per load (a real per-load leak) or stay constant
## (a process-level/static cache).
var _cycles: int = 1


func _init() -> void:
	_parse_args()
	call_deferred("_run")


func _parse_args() -> void:
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
		elif arg == "--no-free":
			_no_free = true
		elif arg == "--free-only":
			_free_only = true
		elif arg.begins_with("--cycles="):
			_cycles = maxi(1, int(arg.substr(9)))
		elif arg == "--menu":
			_menu = true


func _wait_frames(n: int) -> void:
	for _i: int in range(maxi(n, 1)):
		await process_frame


func _vram_line(label: String) -> void:
	var tex: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576
	var vid: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576
	print("PERF_VRAM %s %s texture_mb=%d video_mb=%d" % [_tag, label, tex, vid])


func _measure(label: String, frames: int) -> void:
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
	var mean_ms: float = total / float(dts.size())
	var p50: float = dts[int(float(dts.size()) * 0.5)]
	var p95: float = dts[mini(int(float(dts.size()) * 0.95), dts.size() - 1)]
	var draws: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	var prims: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	print("PERF_RESULT %s %s res=%dx%d mean_ms=%.2f p50_ms=%.2f p95_ms=%.2f fps=%.1f draws=%d objects=%d prims=%d" % [
		_tag, label, _res.x, _res.y, mean_ms, p50, p95, 1000.0 / maxf(mean_ms, 0.001), draws, objs, prims])


func _wait_mission_ready(mission: Node) -> bool:
	var waited: int = 0
	while waited < MAX_LOAD_FRAMES:
		var p_var: Variant = mission.get("player")
		if p_var != null:
			if _contract <= 1:
				return true
			if not get_nodes_in_group("swinging_doors").is_empty():
				return true
		await process_frame
		waited += 1
	return mission.get("player") != null


func _load_menu_backdrop() -> Node:
	var sc: PackedScene = load("res://scenes/main_menu.tscn") as PackedScene
	if sc == null:
		return null
	var mm: Node = sc.instantiate()
	root.add_child(mm)
	return mm


func _run() -> void:
	print("PG1_PROBE tag=%s res=%dx%d contract=%d frames=%d menu=%s cycles=%d" % [_tag, _res.x, _res.y, _contract, _frames, str(_menu), _cycles])
	root.size = _res
	DisplayServer.window_set_size(_res)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait_frames(5)

	if _menu:
		var menu: Node = _load_menu_backdrop()
		if menu == null:
			printerr("PG1_PROBE_FAIL menu scene missing")
			quit(1)
			return
		await _wait_frames(40)
		_vram_line("loaded")
		if not _free_only:
			await _measure("run", _frames)
		menu.queue_free()
		await _wait_frames(10)
		print("PG1_PROBE_FREED tag=%s cycle=0 players=0 doors=0" % _tag)
		_vram_line("freed")
		await _wait_frames(30)
		print("PG1_PROBE_QUIT tag=%s cycles=1" % _tag)
		quit(0)
		return

	for cycle: int in range(_cycles):
		var node: Node = await _load_mission_cycle(cycle)
		if node == null:
			quit(1)
			return
		if not _free_only:
			await _measure("run%d" % cycle, _frames)
			_vram_line("measured")
		if _no_free:
			print("PG1_PROBE_KEEP tag=%s cycle=%d (mission left mounted)" % [_tag, cycle])
			break
		node.queue_free()
		await _wait_frames(10)
		print("PG1_PROBE_FREED tag=%s cycle=%d players=%d doors=%d" % [
			_tag, cycle, get_nodes_in_group("player").size(), get_nodes_in_group("swinging_doors").size()])
		_vram_line("freed")
	# Let deferred frees and the render thread drain before the engine teardown.
	await _wait_frames(30)
	print("PG1_PROBE_QUIT tag=%s cycles=%d" % [_tag, _cycles])
	quit(0)


## Loads one mission instance and waits for its player (and, for missions with
## doors, the first swinging door) so measurements only cover a ready scene.
func _load_mission_cycle(cycle: int) -> Node:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("active_contract_order", _contract)
	var mission_scene: PackedScene = load("res://scenes/mission.tscn") as PackedScene
	if mission_scene == null:
		printerr("PG1_PROBE_FAIL mission scene missing")
		return null
	var node: Node = mission_scene.instantiate()
	root.add_child(node)
	if not await _wait_mission_ready(node):
		printerr("PG1_PROBE_FAIL load timeout contract=%d cycle=%d" % [_contract, cycle])
		# Still free + quit so the teardown report is captured on this path.
		node.queue_free()
		await _wait_frames(10)
		return null
	print("PG1_PROBE_READY tag=%s cycle=%d players=%d doors=%d" % [
		_tag, cycle, get_nodes_in_group("player").size(), get_nodes_in_group("swinging_doors").size()])
	_print_loader(node)
	_tex_census(node)
	_vram_line("loaded")
	return node


## RGBA8 bytes of the textures the loaded scene actually binds, and where they
## come from (named = imported GLB material, anon = loader-built material).
## This separates textures that went through level_loader._load_tex (and its
## budget) from textures that ride in with the .glb import.
func _tex_census(mission: Node) -> void:
	var meshes: Dictionary = {}
	_collect_meshes(mission, meshes)
	var texs: Dictionary = {}
	var surfaces: int = 0
	var named_mats: int = 0
	var anon_mats: int = 0
	for key: Variant in meshes.keys():
		var mesh: Mesh = meshes[key] as Mesh
		for s: int in range(mesh.get_surface_count()):
			surfaces += 1
			var mat: Material = mesh.surface_get_material(s)
			if mat == null:
				continue
			if str(mat.resource_name) != "":
				named_mats += 1
			else:
				anon_mats += 1
			var named: bool = str(mat.resource_name) != ""
			if mat is BaseMaterial3D:
				var bm: BaseMaterial3D = mat
				var slots: Array = [bm.albedo_texture, bm.normal_texture, bm.ao_texture,
					bm.roughness_texture, bm.metallic_texture, bm.emission_texture]
				for t_var: Variant in slots:
					if not (t_var is Texture2D):
						continue
					var t: Texture2D = t_var as Texture2D
					var id: int = t.get_instance_id()
					if texs.has(id):
						continue
					texs[id] = [t.get_width(), t.get_height(), t.resource_path, named]
	var total_bytes: int = 0
	var named_bytes: int = 0
	var anon_bytes: int = 0
	var over1k: int = 0
	var over2k: int = 0
	var over4k: int = 0
	var top: Array = []
	for id2: Variant in texs.keys():
		var rec: Array = texs[id2]
		var w: int = int(rec[0])
		var h: int = int(rec[1])
		var bytes: int = w * h * 4
		total_bytes += bytes
		if rec[3] == true:
			named_bytes += bytes
		else:
			anon_bytes += bytes
		var long_edge: int = maxi(w, h)
		if long_edge > 1024:
			over1k += 1
		if long_edge > 2048:
			over2k += 1
		if long_edge > 4096:
			over4k += 1
		top.append([w * h, str(rec[2]), w, h])
	print("PERF_TEXCENSUS meshes=%d surfaces=%d textures=%d rgba8_mb=%d over1k=%d over2k=%d over4k=%d named_mats=%d anon_mats=%d named_mb=%d anon_mb=%d" % [
		meshes.size(), surfaces, texs.size(), total_bytes / 1048576, over1k, over2k, over4k, named_mats, anon_mats, named_bytes / 1048576, anon_bytes / 1048576])
	top.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	for i: int in range(mini(8, top.size())):
		print("PERF_TEXTOP rank=%d size=%dx%d path=%s" % [i, int(top[i][2]), int(top[i][3]), str(top[i][1])])


func _collect_meshes(node: Node, out: Dictionary) -> void:
	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = node as MultiMeshInstance3D
		if mmi.multimesh != null:
			mesh = mmi.multimesh.mesh
	if mesh != null:
		out[mesh.get_instance_id()] = mesh
	for c: Node in node.get_children():
		_collect_meshes(c, out)


func _print_loader(mission: Node) -> void:
	var ll: Variant = mission.get("level_loader")
	if ll == null:
		print("PERF_LOADER none")
		return
	print("PERF_LOADER budget=%d downscaled=%d skipped_tiny=%d" % [
		int(ll.get("texture_budget_max_dim")), int(ll.get("downscaled_count")), int(ll.get("skipped_tiny_count"))])
