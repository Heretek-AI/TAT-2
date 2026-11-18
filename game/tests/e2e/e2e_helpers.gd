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


func find_env(n: Node) -> Environment:
	var we: WorldEnvironment = find_world_environment(n)
	if we != null:
		return we.environment
	return null


func is_teal_style(box: StyleBoxFlat) -> bool:
	if box == null:
		return false
	return box.border_color.b > box.border_color.r and box.border_color.g > box.border_color.r
