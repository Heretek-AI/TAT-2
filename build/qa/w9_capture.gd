extends SceneTree
## W9-P0 confirmation captures (tracked source; PNG output is gitignored).
##
## Usage:
##   tools/godot --path game --rendering-driver vulkan \
##     --script build/qa/w9_capture.gd -- --mode=prep --tag=prep_ao_on
##
## Modes: prep | prep_nosky | prep_noui | prep_noperiph | prep_ledge | prep_report
##        | upper_foyer | foyer | saferoom | foyer_sweep
## Diagnostics (prep_nosky/prep_noui/prep_noperiph/prep_ledge/prep_report) are
## not required captures: they attribute a composition defect to one layer.
## TAT2_PREP_STAGE=legacy|authored selects the stage composition rule
## (mission_prep_ui.gd) and is echoed in W9_CAPTURE_START.
##
## The output directory comes from W9_QA_OUT (set by build/qa/w9_capture.sh),
## defaulting to <repo>/build/qa/w9/captures so a git worktree never writes
## into the main checkout. Every shot prints W9_CAPTURE with a sampled luma
## statistic so a black frame cannot be mistaken for a capture; the
## authoritative statistics are build/qa/w9_frame_stats.py (Pillow, ITU-R 601).

const DEFAULT_SIZE := Vector2i(1920, 1080)
const EYE_OFFSET := 1.67
const SHIPPED_FOV := 54.54

var _size: Vector2i = DEFAULT_SIZE
var _mode: String = ""
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


func _out_dir() -> String:
	var env: String = OS.get_environment("W9_QA_OUT").strip_edges()
	if env != "":
		return env
	var root_dir: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return root_dir.path_join("build/qa/w9/captures")


func _wait(n: int) -> void:
	for _i: int in range(maxi(n, 1)):
		await process_frame


func _all_nodes(node: Node) -> Array:
	var out: Array = []
	for c: Node in node.get_children():
		out.append(c)
		out.append_array(_all_nodes(c))
	return out


## Projected screen box (0..1, top-left) of a world AABB through the authored
## stage camera. Corners behind the eye are dropped; returns x0/y0/x1/y1 with
## x0>x1 when nothing projects.
func _screen_box(cam: Camera3D, box: AABB) -> Array:
	var mn: Vector2 = Vector2(9.0, 9.0)
	var mx: Vector2 = Vector2(-9.0, -9.0)
	var vp: Vector2 = Vector2(cam.get_viewport().size) if cam.get_viewport() != null else Vector2(1920, 1080)
	for i: int in 8:
		var p: Vector3 = box.get_endpoint(i)
		if (-cam.global_transform.basis.z).dot(p - cam.global_position) <= 0.01:
			continue
		var s: Vector2 = cam.unproject_position(p) / vp
		mn = Vector2(minf(mn.x, s.x), minf(mn.y, s.y))
		mx = Vector2(maxf(mx.x, s.x), maxf(mx.y, s.y))
	return [mn.x, mn.y, mx.x, mx.y]


## Read-only census for authoring the prep stage composition rule: every draw
## node's distance to the thief anchor, world AABB, projected screen box, and
## every skyline piece's mesh AABB. Writes nothing; the frame is not saved.
func _prep_report(cam: Camera3D) -> void:
	var anchor: Node3D = root.find_child("MissionLobbyThiefAnchor", true, false) as Node3D
	var feet: Vector3 = anchor.global_position if anchor != null else Vector3.ZERO
	print("W9_REPORT anchor=%s cam=%s" % [str(feet), str(cam.global_position) if cam != null else "missing"])
	if cam == null:
		return
	var cb: Basis = cam.global_transform.basis
	var vps: Vector2 = Vector2(cam.get_viewport().size) if cam.get_viewport() != null else Vector2(1920, 1080)
	print("W9_REPORT cam_basis x=%s y=%s z=%s vp=%s tanh=%.6f tanv=%.6f" % [
		str(cb.x), str(cb.y), str(cb.z), str(vps),
		tan(deg_to_rad(cam.fov * 0.5)),
		tan(atan(tan(deg_to_rad(cam.fov * 0.5)) / (vps.x / vps.y))),
	])
	var rows: Array = []
	var hidden: int = 0
	for n: Node in _all_nodes(root):
		if not (n is GeometryInstance3D):
			continue
		var gi: GeometryInstance3D = n as GeometryInstance3D
		var w: AABB = gi.global_transform * gi.get_aabb()
		var nearest: Vector3 = w.get_center().clamp(w.position, w.end)
		var d: float = feet.distance_to(nearest)
		var sb: Array = _screen_box(cam, w)
		var on_screen: bool = float(sb[2]) > 0.0 and float(sb[0]) < 1.0 \
			and float(sb[3]) > 0.0 and float(sb[1]) < 1.0
		if gi.is_visible_in_tree() and not on_screen:
			continue
		if not gi.is_visible_in_tree():
			hidden += 1
		rows.append([d, n, w, sb, on_screen])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for r: Array in rows:
		var n: Node = r[1] as Node
		var w: AABB = r[2] as AABB
		var sb: Array = r[3] as Array
		var gi: GeometryInstance3D = n as GeometryInstance3D
		print("W9_GEO node=%s cls=%s dist=%.2f pos=%s size=%s screen=(%.3f,%.3f)..(%.3f,%.3f) on=%s vis=%s sky=%s src=%s" % [
			n.name, n.get_class(), float(r[0]), str(w.position), str(w.size),
			float(sb[0]), float(sb[1]), float(sb[2]), float(sb[3]),
			str(bool(r[4])), str(gi.is_visible_in_tree()), str(n.is_in_group("prep_skyline")),
			str(n.get_meta("source_sublevel", "")),
		])
	print("W9_REPORT rows=%d hidden_of_total=%d" % [rows.size(), hidden])
	for n: Node in get_nodes_in_group("prep_skyline"):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local: AABB = mi.mesh.get_aabb()
		var world: AABB = mi.global_transform * local
		var sb2: Array = _screen_box(cam, world)
		print("W9_SKY node=%s local_pos=%s local_size=%s world_pos=%s screen=(%.3f,%.3f)..(%.3f,%.3f)" % [
			mi.name, str(local.position), str(local.size), str(world.position),
			float(sb2[0]), float(sb2[1]), float(sb2[2]), float(sb2[3]),
		])


func _find_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child: Node in node.get_children():
		var found: WorldEnvironment = _find_env(child)
		if found != null:
			return found
	return null


## Sampled ITU-R 601 luma (the same weights Pillow's convert("L") uses) on the
## sRGB framebuffer values, every 4th pixel in both axes.
func _sampled_stats(img: Image) -> Dictionary:
	var total: int = 0
	var sum: float = 0.0
	var below8: int = 0
	var peak: float = 0.0
	var step: int = 4
	for y: int in range(0, img.get_height(), step):
		for x: int in range(0, img.get_width(), step):
			var c: Color = img.get_pixel(x, y)
			var l: float = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255.0
			sum += l
			total += 1
			if l < 8.0:
				below8 += 1
			peak = maxf(peak, l)
	if total == 0:
		return {"mean": 0.0, "pct_lt8": 100.0, "peak": 0.0, "samples": 0}
	return {
		"mean": sum / float(total),
		"pct_lt8": 100.0 * float(below8) / float(total),
		"peak": peak,
		"samples": total,
	}


func _save(name: String) -> bool:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		printerr("W9_CAPTURE FAILED empty image name=", name)
		return false
	var path: String = _out_dir().path_join(name + ".png")
	var err: int = img.save_png(path)
	var st: Dictionary = _sampled_stats(img)
	var nonblack: bool = err == OK and float(st.get("peak", 0.0)) > 8.0 and float(st.get("mean", 0.0)) > 1.0
	print("W9_CAPTURE file=%s size=%dx%d err=%d mean601=%.2f pct_lt8=%.1f peak=%.1f nonblack=%s ao=%s" % [
		name, img.get_width(), img.get_height(), err,
		float(st.get("mean", 0.0)), float(st.get("pct_lt8", 100.0)),
		float(st.get("peak", 0.0)), str(nonblack),
		OS.get_environment("TAT2_AO").strip_edges().to_lower() if OS.get_environment("TAT2_AO") != "" else "on",
	])
	return nonblack


func _prep() -> bool:
	root.size = _size
	await _wait(3)
	var mp: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	mp.size = Vector2(_size)
	root.add_child(mp)
	await _wait(4)
	mp.call("open_prep", "guildhall", 1, "Solo", 0)
	# The stage loads MissionLobby sublevels asynchronously and then places the
	# expansion skyline into the prep_skyline group; wait for it so a shot is
	# never taken against a half-built stage.
	var waited: int = 0
	while get_nodes_in_group("prep_skyline").is_empty() and waited < 900:
		await process_frame
		waited += 1
	await _wait(90)
	var cam: Camera3D = root.find_child("MissionLobbyCamera", true, false) as Camera3D
	if cam != null:
		print("W9_STAGE camera pos=%s rot_deg=%s fov=%.2f current=%s" % [
			str(cam.global_position), str(cam.global_rotation_degrees), cam.fov, str(cam.current),
		])
	else:
		printerr("W9_STAGE camera missing")
	# Diagnostics (not part of the three required captures): separate the
	# expansion skyline from the level geometry, and the stage from the UI, so
	# a composition defect can be attributed to the right layer.
	if _mode == "prep_nosky":
		var freed: int = 0
		for node: Node in get_nodes_in_group("prep_skyline"):
			node.queue_free()
			freed += 1
		await _wait(12)
		print("W9_DIAG prep_nosky freed=%d remaining=%d" % [freed, get_nodes_in_group("prep_skyline").size()])
	elif _mode == "prep_noui":
		for child: Node in mp.get_children():
			if child is CanvasItem and not (child is SubViewportContainer):
				(child as CanvasItem).visible = false
		await _wait(6)
		print("W9_DIAG prep_noui hid_ui=1")
	elif _mode == "prep_report":
		# Read-only census for the composition rule (see _prep_report).
		_prep_report(cam)
	elif _mode == "prep_noperiph":
		# A/B for the composition question: is the frame's background the
		# authored Periphery sublevel (31-42 m courtyard) or Geo3 (14-22 m)?
		# Frees the nodes the loader tagged with that source sublevel.
		var freed: int = 0
		for n: Node in _all_nodes(root):
			var src: Variant = n.get_meta("source_sublevel", "")
			if str(src).to_lower().find("periph") >= 0:
				n.queue_free()
				freed += 1
		await _wait(12)
		print("W9_DIAG prep_noperiph freed=%d" % freed)
	elif _mode == "prep_ledge":
		# Diagnostic: keep only the geometry within 8 m of the thief's feet
		# (the slate ledge) plus the expansion skyline ring. Tests whether the
		# shipped KF11 composition (ledge + city + sky) is reachable at the
		# authored camera without moving it.
		var anchor: Node3D = root.find_child("MissionLobbyThiefAnchor", true, false) as Node3D
		var feet: Vector3 = anchor.global_position if anchor != null else Vector3.ZERO
		var kept: int = 0
		var dropped: int = 0
		for n2: Node in _all_nodes(root):
			if not (n2 is GeometryInstance3D):
				continue
			if n2.is_in_group("prep_skyline"):
				continue
			var gi := n2 as GeometryInstance3D
			var ab: AABB = gi.get_aabb()
			var world: AABB = gi.global_transform * ab
			var nearest: Vector3 = world.get_center().clamp(world.position, world.end)
			if feet.distance_to(nearest) <= 9.0:
				kept += 1
			else:
				gi.visible = false
				dropped += 1
		await _wait(12)
		print("W9_DIAG prep_ledge kept=%d hid=%d" % [kept, dropped])
	print("W9_STAGE skyline=%d thief_anchor=%s waited=%d" % [
		get_nodes_in_group("prep_skyline").size(),
		str(root.find_child("MissionLobbyThiefAnchor", true, false) != null),
		waited,
	])
	var wenv: WorldEnvironment = _find_env(root)
	if wenv != null and wenv.environment != null:
		var env: Environment = wenv.environment
		print("W9_ENV scene=prep ssao=%s ssil=%s tonemap=%d exposure=%.3f glow=%s" % [
			str(env.ssao_enabled), str(env.ssil_enabled), env.tonemap_mode,
			env.tonemap_exposure, str(env.glow_enabled),
		])
	return await _save(_tag)


func _mission_interior() -> bool:
	root.size = _size
	await _wait(3)
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("state", "playing")
		gs.set("thief_id", "spider")
		gs.set("active_contract_order", 4)
		gs.set("active_map_id", "guildhall")
	var mission: Node3D = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(mission)
	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and waited < 1800:
		await process_frame
		waited += 1
	await _wait(40)
	var hud: Node = mission.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(10)
	var wenv: WorldEnvironment = _find_env(mission)
	if wenv != null and wenv.environment != null:
		var env: Environment = wenv.environment
		print("W9_ENV scene=%s ssao=%s ssil=%s tonemap=%d exposure=%.3f glow=%s" % [
			_mode, str(env.ssao_enabled), str(env.ssil_enabled), env.tonemap_mode,
			env.tonemap_exposure, str(env.glow_enabled),
		])
	else:
		printerr("W9_ENV scene=%s missing WorldEnvironment" % _mode)
	print("W9_STAGE mission_ready waited=%d player=%s doors=%d" % [
		waited, str(mission.get("player") != null), get_nodes_in_group("swinging_doors").size(),
	])
	# Perf-matrix pose ids: upper_foyer = player feet (27,28,-50) -> (27,29.67,-60);
	# foyer = eye (22,22.17,125.3) -> (22,22.17,115.3). A standalone camera at
	# the shipped lens makes the capture and the perf pose the same frame.
	var eye: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3.ZERO
	if _mode == "upper_foyer":
		eye = Vector3(27.0, 28.0 + EYE_OFFSET, -50.0)
		target = Vector3(27.0, 29.67, -60.0)
	elif _mode == "foyer":
		eye = Vector3(22.0, 22.17, 125.3)
		target = Vector3(22.0, 22.17, 115.3)
	elif _mode == "saferoom":
		eye = Vector3(22.0, 20.5 + EYE_OFFSET, 128.4)
		target = Vector3(22.0, 22.17, 118.4)
	elif _mode == "foyer_sweep":
		pass
	else:
		printerr("W9_CAPTURE unknown mode=", _mode)
		return false
	var cam: Camera3D = Camera3D.new()
	cam.name = "W9CaptureCamera"
	cam.fov = SHIPPED_FOV
	cam.far = 4000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	mission.add_child(cam)
	if _mode == "foyer_sweep":
		# Four yaw views from the authored upper-foyer slot. KF27 is the marble
		# hall with the security beam; the recorded run's f_0267 is another
		# corner of the same hall, so the best-matching frame is chosen from
		# the sweep rather than assumed from one pose.
		var origin: Vector3 = Vector3(27.0, 28.0 + EYE_OFFSET, -50.0)
		var ok_all: bool = true
		for i: int in range(4):
			var yaw: float = deg_to_rad(float(i) * 90.0)
			var aim: Vector3 = origin + Vector3(sin(yaw), 0.0, -cos(yaw)) * 10.0
			cam.global_position = origin
			cam.look_at(aim, Vector3.UP)
			cam.current = true
			await _wait(12)
			print("W9_STAGE camera pos=%s target=%s fov=%.2f yaw=%d" % [str(origin), str(aim), cam.fov, i * 90])
			ok_all = await _save("%s_yaw%03d" % [_tag, i * 90]) and ok_all
		return ok_all
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.current = true
	await _wait(15)
	print("W9_STAGE camera pos=%s target=%s fov=%.2f" % [str(eye), str(target), cam.fov])
	return await _save(_tag)


func _run() -> void:
	_mode = _arg("--mode=", "prep")
	_tag = _arg("--tag=", _mode)
	_size = _parse_size(_arg("--size=", "1920x1080"))
	DirAccess.make_dir_recursive_absolute(_out_dir())
	print("W9_CAPTURE_START mode=%s tag=%s size=%s ao=%s prep_stage=%s out=%s" % [
		_mode, _tag, str(_size), OS.get_environment("TAT2_AO"),
		OS.get_environment("TAT2_PREP_STAGE").strip_edges() if OS.get_environment("TAT2_PREP_STAGE") != "" else "authored",
		_out_dir(),
	])
	var ok: bool = false
	if _mode in ["prep", "prep_nosky", "prep_noui", "prep_noperiph", "prep_ledge", "prep_report"]:
		ok = await _prep()
	elif _mode in ["upper_foyer", "foyer", "saferoom", "foyer_sweep"]:
		ok = await _mission_interior()
	else:
		printerr("W9_CAPTURE unknown mode=", _mode)
		quit(2)
		return
	print("W9_CAPTURE_DONE mode=%s tag=%s ok=%s" % [_mode, _tag, str(ok)])
	quit(0 if ok else 1)
