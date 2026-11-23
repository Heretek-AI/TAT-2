extends RefCounted
## Shared opaque-box E2E helpers for Thick As Thieves (TAT-2) headless test suite.
## Follows Godot 4.7 --script rules:
## - Runtime load() only (zero top-level preload() of autoload-referencing scripts)
## - Explicit types on Variant/Dictionary lookups (no := on untyped values)
## - No bool(obj.get(...)) casts; use is_true(v)

var tree: SceneTree
var root: Window
var fails: int = 0
var passed: int = 0
var total: int = 0

var _script_cache: Dictionary = {}
var _scene_cache: Dictionary = {}
var _saved_gs: Dictionary = {}
var _saved_settings: Dictionary = {}


func _init(p_tree: SceneTree) -> void:
	tree = p_tree
	root = p_tree.get_root() if p_tree != null else null


## One-shot environment guard. The suite reads the extracted UE capture and the
## generated tables from read-only roots; when they are missing every data
## check would fail for the same reason. Detect that once at startup so the
## report is a single [BOOT] cause line instead of a wall of per-check fails.
## Returns the missing roots (empty == bootable).
func boot_problems() -> Array[String]:
	var missing: Array[String] = []
	var checks: Array[Dictionary] = [
		{"label": "generated data", "path": "res://data/generated", "need_file": "res://data/generated/materials.json"},
		{"label": "UE raw/content assets", "path": "res://assets/ue", "need_file": ""},
		{"label": "extracted capture", "path": repo_path("extracted"), "need_file": repo_path("extracted/json")},
	]
	for c: Dictionary in checks:
		var p: String = str(c.get("path", ""))
		var ok_dir: bool = false
		if p.begins_with("res://"):
			ok_dir = DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(p))
		else:
			ok_dir = DirAccess.dir_exists_absolute(p)
		if not ok_dir:
			missing.append("%s: %s" % [str(c.get("label", "root")), p])
			continue
		var nf: String = str(c.get("need_file", ""))
		if nf != "" and not FileAccess.file_exists(nf) and not DirAccess.dir_exists_absolute(nf):
			missing.append("%s: %s" % [str(c.get("label", "root")), nf])
	return missing


## Force the authored 1280x720 target canvas for layout checks. Headless Godot
## otherwise leaves the root window at a 64x64 window size while the visible
## rect reports 1280x1280, which made every "fits in 720p" measurement test the
## wrong height.
func force_authored_viewport() -> void:
	if root == null:
		return
	if root.size != Vector2i(1280, 720):
		root.size = Vector2i(1280, 720)


func require(cond: bool, id: String, detail: String = "") -> bool:
	total += 1
	if cond:
		passed += 1
		if detail != "":
			print("PASS: [", id, "] ", detail)
		else:
			print("PASS: [", id, "]")
		return true
	fails += 1
	if detail != "":
		printerr("FAIL: [", id, "] ", detail)
	else:
		printerr("FAIL: [", id, "]")
	return false


func is_true(v: Variant) -> bool:
	return v is bool and v == true


func has_m(obj: Object, method_name: String) -> bool:
	return obj != null and is_instance_valid(obj) and obj.has_method(method_name)


func has_s(obj: Object, signal_name: String) -> bool:
	return obj != null and is_instance_valid(obj) and obj.has_signal(signal_name)


func has_prop(obj: Object, prop_name: String) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	for p: Dictionary in obj.get_property_list():
		if str(p.get("name", "")) == prop_name:
			return true
	return false


func get_prop(obj: Object, prop_name: String, default_val: Variant = null) -> Variant:
	if not has_prop(obj, prop_name):
		return default_val
	return obj.get(prop_name)


func has_action(action_name: String) -> bool:
	return InputMap.has_action(action_name)


func game_data() -> Node:
	return root.get_node_or_null("GameData") if root != null else null


func game_state() -> Node:
	return root.get_node_or_null("GameState") if root != null else null


func noise_bus() -> Node:
	return root.get_node_or_null("NoiseBus") if root != null else null


func audio_manager() -> Node:
	return root.get_node_or_null("AudioManager") if root != null else null


func net_manager() -> Node:
	return root.get_node_or_null("NetManager") if root != null else null


func save_system() -> Node:
	return root.get_node_or_null("SaveSystem") if root != null else null


func load_script(res_path: String) -> GDScript:
	if _script_cache.has(res_path):
		return _script_cache[res_path] as GDScript
	if not ResourceLoader.exists(res_path):
		return null
	var scr: GDScript = load(res_path) as GDScript
	_script_cache[res_path] = scr
	return scr


func load_scene(res_path: String) -> PackedScene:
	if _scene_cache.has(res_path):
		return _scene_cache[res_path] as PackedScene
	if not ResourceLoader.exists(res_path):
		return null
	var sc: PackedScene = load(res_path) as PackedScene
	_scene_cache[res_path] = sc
	return sc


func new_script_node(res_path: String) -> Node:
	var scr: GDScript = load_script(res_path)
	if scr == null:
		return null
	return scr.new() as Node


func read_text(res_path: String) -> String:
	if not FileAccess.file_exists(res_path):
		return ""
	var f: FileAccess = FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func read_json(res_path: String) -> Variant:
	var txt: String = read_text(res_path)
	if txt == "":
		return null
	return JSON.parse_string(txt)


func repo_path(rel_path: String) -> String:
	var p1: String = ProjectSettings.globalize_path("res://../" + rel_path)
	if FileAccess.file_exists(p1) or DirAccess.dir_exists_absolute(p1):
		return p1
	var p2: String = "/home/john/Projects/TAT-2/" + rel_path
	if FileAccess.file_exists(p2) or DirAccess.dir_exists_absolute(p2):
		return p2
	return p1


func repo_file_exists(rel_path: String) -> bool:
	return FileAccess.file_exists(repo_path(rel_path))


func repo_read_text(rel_path: String) -> String:
	var p: String = repo_path(rel_path)
	if not FileAccess.file_exists(p):
		return ""
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func repo_read_json(rel_path: String) -> Variant:
	var txt: String = repo_read_text(rel_path)
	if txt == "":
		return null
	return JSON.parse_string(txt)


func snapshot_state() -> void:
	var gs: Node = game_state()
	if gs != null:
		_saved_gs = {
			"thief_id": str(gs.get("thief_id")),
			"outfit_body": str(gs.get("outfit_body")),
			"outfit_head": str(gs.get("outfit_head")),
			"calling_card": str(gs.get("calling_card")),
			"difficulty": int(gs.get("difficulty")),
			"active_contract_order": int(gs.get("active_contract_order")),
			"active_map_id": str(gs.get("active_map_id")),
			"state": str(gs.get("state")),
			"elapsed_sec": float(gs.get("elapsed_sec")),
			"run_time_limit": float(gs.get("run_time_limit")),
			"loot_collected": int(gs.get("loot_collected")),
			"loot_needed": int(gs.get("loot_needed")),
			"loot_value": int(gs.get("loot_value")),
			"quest_item_acquired": is_true(gs.get("quest_item_acquired")),
			"ever_spotted": is_true(gs.get("ever_spotted")),
			"ever_chased": is_true(gs.get("ever_chased")),
			"takedowns": int(gs.get("takedowns")),
			"player_light_visibility": float(gs.get("player_light_visibility")),
		}
	var ss: Node = save_system()
	if ss != null and has_m(ss, "get_settings"):
		var s_raw: Variant = ss.call("get_settings")
		if s_raw is Dictionary:
			_saved_settings = (s_raw as Dictionary).duplicate(true)


func restore_state() -> void:
	var gs: Node = game_state()
	if gs != null and not _saved_gs.is_empty():
		for k: Variant in _saved_gs.keys():
			gs.set(str(k), _saved_gs[k])
	var ss: Node = save_system()
	if ss != null and not _saved_settings.is_empty():
		var data_v: Variant = ss.get("data")
		if data_v is Dictionary:
			(data_v as Dictionary)["settings"] = _saved_settings.duplicate(true)
		if has_m(ss, "apply_saved_settings"):
			ss.call("apply_saved_settings")


func step_process(frames: int = 1) -> void:
	for _i: int in range(frames):
		await tree.process_frame


func step_physics(frames: int = 1) -> void:
	for _i: int in range(frames):
		await tree.physics_frame


func free_node(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()
	await step_process(2)


func instantiate_mission(contract_order: int, max_frames: int = 240, difficulty: int = 1) -> Dictionary:
	var gs: Node = game_state()
	if gs != null:
		gs.set("difficulty", difficulty)
		gs.set("active_contract_order", contract_order)
	var sc: PackedScene = load_scene("res://scenes/mission.tscn")
	if sc == null or root == null:
		return {"mission": null, "player": null, "hud": null, "timed_out": true}
	var m: Node = sc.instantiate()
	root.add_child(m)
	var wait_f: int = 0
	var timed_out: bool = false
	while wait_f < max_frames:
		var has_player: bool = not tree.get_nodes_in_group("player").is_empty() and m.get("player") != null
		var doors_ok: bool = (contract_order <= 1) or (not tree.get_nodes_in_group("swinging_doors").is_empty())
		if has_player and doors_ok:
			break
		await tree.process_frame
		wait_f += 1
	if wait_f >= max_frames:
		timed_out = true
	await step_process(2)
	var p: Node = m.get("player") as Node
	var h: Node = m.get("hud") as Node
	return {"mission": m, "player": p, "hud": h, "timed_out": timed_out}


func make_arena(origin: Vector3 = Vector3(9500.0, 500.0, 9500.0)) -> Dictionary:
	var arena: Node3D = Node3D.new()
	arena.name = "E2EArena"
	arena.position = origin
	root.add_child(arena)

	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "ArenaFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	cs.shape = box
	cs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(cs)
	arena.add_child(floor_body)

	var lp: Node = new_script_node("res://src/stealth/light_probe.gd")
	if lp != null:
		arena.add_child(lp)
	await step_physics(2)
	return {"arena": arena, "floor": floor_body, "light_probe": lp, "origin": origin}


func add_wall_box(parent: Node3D, local_pos: Vector3, size: Vector3, node_name: String = "ArenaWall", surface_type: String = "") -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.name = node_name
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = local_pos
	if surface_type != "":
		sb.set_meta("surface_type", surface_type)
		sb.add_to_group(surface_type)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bx: BoxShape3D = BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	sb.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	sb.add_child(mi)
	parent.add_child(sb)
	return sb


func spawn_test_player(arena: Node3D, local_pos: Vector3, light_probe: Node = null, level_ctrl: Node = null) -> Node:
	var gs: Node = game_state()
	if gs != null:
		gs.set("state", "playing")
	var p: Node = new_script_node("res://src/player/thief_character.gd")
	if p == null:
		return null
	p.set("light_probe", light_probe)
	p.set("level_ctrl", level_ctrl if level_ctrl != null else arena)
	arena.add_child(p)
	if p is Node3D:
		(p as Node3D).position = local_pos
	await step_physics(3)
	return p


func spawn_test_guard(arena: Node3D, local_pos: Vector3) -> Node:
	var g: Node = new_script_node("res://src/ai/guard_ai.gd")
	if g == null:
		return null
	arena.add_child(g)
	if g is Node3D:
		(g as Node3D).position = local_pos
	await step_physics(2)
	return g


func tap_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	var ev_down: InputEventAction = InputEventAction.new()
	ev_down.action = action_name
	ev_down.pressed = true
	Input.parse_input_event(ev_down)
	Input.action_press(action_name)
	await step_process(1)
	var ev_up: InputEventAction = InputEventAction.new()
	ev_up.action = action_name
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	Input.action_release(action_name)
	await step_process(1)


func press_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action_name
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.action_press(action_name)


func release_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action_name
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.action_release(action_name)


func tap_key(keycode: Key) -> void:
	var ev_down: InputEventKey = InputEventKey.new()
	ev_down.keycode = keycode
	ev_down.physical_keycode = keycode
	ev_down.pressed = true
	Input.parse_input_event(ev_down)
	await step_process(1)
	var ev_up: InputEventKey = InputEventKey.new()
	ev_up.keycode = keycode
	ev_up.physical_keycode = keycode
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	await step_process(1)


func find_first_mesh_instance(n: Node) -> MeshInstance3D:
	if n == null:
		return null
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for ch: Node in n.get_children():
		var found: MeshInstance3D = find_first_mesh_instance(ch)
		if found != null:
			return found
	return null


func find_all_of_class(n: Node, cls_name: String) -> Array[Node]:
	var out: Array[Node] = []
	if n == null:
		return out
	if n.is_class(cls_name):
		out.append(n)
	for ch: Node in n.get_children():
		out.append_array(find_all_of_class(ch, cls_name))
	return out


func find_world_environment(n: Node) -> WorldEnvironment:
	var list: Array[Node] = find_all_of_class(n, "WorldEnvironment")
	if list.is_empty():
		return null
	return list[0] as WorldEnvironment


## Environment discovery for the startscreen. Since the env refactor the
## BeautifulCorner backdrop binds its Environment directly to the CineCamera
## (Camera3D.environment) inside an own-world SubViewport; a WorldEnvironment
## inside that SubViewport registers on the parent world and is not what the
## camera renders. Prefer the camera-bound Environment anywhere in the subtree
## (SubViewports included), then fall back to WorldEnvironment.
func find_camera_env(n: Node) -> Environment:
	if n == null:
		return null
	var hit: Environment = _find_camera_env_rec(n)
	if hit != null:
		return hit
	return _find_world_env(n)


func _find_camera_env_rec(n: Node) -> Environment:
	if n is Camera3D:
		var cen: Environment = (n as Camera3D).environment
		if cen != null:
			return cen
	for ch: Node in n.get_children():
		var found: Environment = _find_camera_env_rec(ch)
		if found != null:
			return found
	return null


func _find_world_env(n: Node) -> Environment:
	var we: WorldEnvironment = find_world_environment(n)
	if we != null:
		return we.environment
	return null


## Kept for existing callers: startscreen checks now read the camera-bound
## Environment first (T1/T2/T3/T4 startscreen checks share this helper).
func find_env(n: Node) -> Environment:
	return find_camera_env(n)


## First-person viewmodel isolation contract (no SubViewport):
## - the FP rig lives under the active camera,
## - there is exactly one render path (no per-player SubViewport),
## - every viewmodel surface resolves to the VM ShaderMaterial carrying the
##   authored vm_fov_deg projection lock (the view-space isolation seam),
## - viewmodel meshes cast no shadows (they are not visible to shadow/
##   reflection/other viewports).
## Returns a detail dictionary so callers can log the sub-values.
func viewmodel_contract(p: Node) -> Dictionary:
	var out: Dictionary = {
		"cam": null, "fp_rig": null, "under_cam": false, "sub_viewports": 0,
		"mesh_count": 0, "shader_surfaces": 0, "total_surfaces": 0,
		"fov_values": [], "fov": -1.0, "shadows_on": 0,
		"arm_skel": null, "ok": false,
	}
	if p == null:
		return out
	var cam: Camera3D = p.get("cam") as Camera3D
	var fp_rig: Node = p.get("fp_rig") as Node
	out["cam"] = cam
	out["fp_rig"] = fp_rig
	out["under_cam"] = cam != null and fp_rig != null and fp_rig.get_parent() == cam
	out["sub_viewports"] = find_all_of_class(p, "SubViewport").size()
	out["arm_skel"] = p.get("_fp_arm_skel")
	var roots: Array[Node] = []
	if fp_rig != null:
		roots.append(fp_rig)
	if roots.is_empty():
		return out
	var fov_values: Array[float] = []
	var shader_surfaces: int = 0
	var total_surfaces: int = 0
	var mesh_count: int = 0
	var shadows_on: int = 0
	for r: Node in roots:
		for n: Node in find_all_of_class(r, "MeshInstance3D"):
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			mesh_count += 1
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadows_on += 1
			for s: int in range(mi.mesh.get_surface_count()):
				total_surfaces += 1
				var mat: Material = mi.get_active_material(s)
				if mat is ShaderMaterial:
					var sm: ShaderMaterial = mat as ShaderMaterial
					var fv: Variant = sm.get_shader_parameter("vm_fov_deg")
					if fv is float or fv is int:
						shader_surfaces += 1
						var f: float = float(fv)
						if not fov_values.has(f):
							fov_values.append(f)
	out["mesh_count"] = mesh_count
	out["total_surfaces"] = total_surfaces
	out["shader_surfaces"] = shader_surfaces
	out["fov_values"] = fov_values
	out["fov"] = fov_values[0] if fov_values.size() == 1 else -1.0
	out["shadows_on"] = shadows_on
	out["ok"] = bool(out["under_cam"]) and int(out["sub_viewports"]) == 0 \
		and mesh_count > 0 and shader_surfaces > 0 and shader_surfaces == total_surfaces \
		and shadows_on == 0 and fov_values.size() == 1
	return out


## Level-controller stand-in for stealth tests: exposes the same documented
## contract the mission controller gives guards (light_probe, smoke AABB).
func make_level_host(light_probe: Node = null) -> Node3D:
	var scr: GDScript = GDScript.new()
	scr.source_code = """extends Node3D
var light_probe: Node = null
var smokes: Array[Dictionary] = []
func spawn_smoke(pos: Vector3, ttl: float = 25.0) -> void:
	smokes.append({"min": pos - Vector3(2.5, 2.0, 2.5), "max": pos + Vector3(2.5, 2.0, 2.5), "ttl": ttl})
func is_blocked_by_smoke(a: Vector3, b: Vector3) -> bool:
	for s in smokes:
		if _segment_hits_aabb(a, b, s["min"], s["max"]):
			return true
	return false
func _segment_hits_aabb(a: Vector3, b: Vector3, mn: Vector3, mx: Vector3) -> bool:
	var t_min: float = 0.0
	var t_max: float = 1.0
	var origins: Array[float] = [a.x, a.y, a.z]
	var ends: Array[float] = [b.x, b.y, b.z]
	var mins: Array[float] = [mn.x, mn.y, mn.z]
	var maxs: Array[float] = [mx.x, mx.y, mx.z]
	for i in range(3):
		var d: float = ends[i] - origins[i]
		if absf(d) < 0.000001:
			if origins[i] < mins[i] or origins[i] > maxs[i]:
				return false
		else:
			var t0: float = (mins[i] - origins[i]) / d
			var t1: float = (maxs[i] - origins[i]) / d
			if t0 > t1:
				var tmp: float = t0
				t0 = t1
				t1 = tmp
			t_min = maxf(t_min, t0)
			t_max = minf(t_max, t1)
			if t_min > t_max:
				return false
	return true
"""
	scr.reload()
	var host: Node3D = scr.new() as Node3D
	host.set("light_probe", light_probe)
	return host


func is_teal_style(box: StyleBoxFlat) -> bool:
	if box == null:
		return false
	return box.border_color.b > box.border_color.r and box.border_color.g > box.border_color.r
