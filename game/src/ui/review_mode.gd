extends Node3D
## In-game free-camera review of the static world, built through the real
## LevelLoader and nothing else (no mission, player, AI, HUD or gameplay).
##
##   tools/godot --path game res://scenes/review_mode.tscn -- --map=guildhall
##   make review MAP=guildhall
##
## Controls
##   WASD        move, mouse look (LMB captures / releases the pointer)
##   Shift       fast, Q/E down/up
##   1..9, 0     Periphery / POI / Gameplay / Lighting / Decals / Collision /
##               Niagara / Beams / World labels / Emissive plates
##   F1..F6      bookmarks (KF16 gate, foyer, library, POI lounge, safe room, ..)
##   P           save a PNG to user://review_captures/
##   Esc         quit
##
## Sublevel membership is the load-container ancestry (one Loader call per
## .tatlevel.json) so the number-key filters can hide whole sublevels. The
## shipped game loads all sublevels in one call with one 160-light budget;
## here each sublevel gets its own budget so its authored lights survive the
## split. Documented in docs/reports/review-map-baker.md.

const LevelLoaderScript: GDScript = preload("res://src/core/level_loader.gd")
const MapData: GDScript = preload("res://addons/tat2_review/review_map_data.gd")
const Tagger: GDScript = preload("res://addons/tat2_review/review_tagger.gd")
const Filters: GDScript = preload("res://addons/tat2_review/review_filters.gd")

const MOVE_SPEED: float = 12.0
const FAST_MULT: float = 4.0
const LOOK_SENSITIVITY: float = 0.0022
const MAX_LIGHTS_PER_SUBLEVEL: int = 160
const CAPTURE_DIR: String = "user://review_captures"
const NUMBER_TOGGLES: Array[String] = [
	"Periphery", "POI", "Gameplay", "Lighting", "Decals",
	"Collision", "Niagara", "Beams", "World labels", "Emissive plates",
]

var map_id: String = "guildhall"
var _world_root: Node3D
var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _mouse_captured: bool = false
var _toggles: Dictionary = {}
var _containers: Array[Node3D] = []
var _bookmarks: Array = []
var _hud_title: Label
var _hud_counts: Label
var _hud_toggles: Label
var _hud_hint: Label
var _hud_status: Label
var _loading: bool = true
var _stats: Dictionary = {}


func _ready() -> void:
	_parse_args()
	for t: String in NUMBER_TOGGLES:
		_toggles[t] = true
	_build_hud()
	call_deferred("_load_world")


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			map_id = arg.substr("--map=".length())


func _load_world() -> void:
	var resolved: Dictionary = MapData.resolve_sublevels(map_id)
	var paths: Array = resolved.get("paths", [])
	if paths.is_empty():
		_loading = false
		_status("No sublevels resolved for map '%s'." % map_id)
		_update_hud()
		return
	_status("Loading %d sublevels through LevelLoader..." % paths.size())
	_update_hud()

	_world_root = Node3D.new()
	_world_root.name = "ReviewWorld"
	add_child(_world_root)
	var loader: Node = LevelLoaderScript.new()
	loader.name = "ReviewLevelLoader"
	add_child(loader)
	await get_tree().process_frame

	var index: int = 0
	for path_v: Variant in paths:
		var json_path: String = str(path_v)
		index += 1
		if not FileAccess.file_exists(json_path):
			_status("Missing sublevel: %s" % json_path)
			continue
		var stem: String = json_path.get_file().trim_suffix(".tatlevel.json")
		var container: Node3D = Node3D.new()
		container.name = stem
		_world_root.add_child(container)
		_status("Loading %d/%d %s" % [index, paths.size(), stem])
		_update_hud()
		await loader.call("load_sublevels_async", [json_path], container, null, MAX_LIGHTS_PER_SUBLEVEL, true)
		Tagger.apply_tags(container, stem)
		_containers.append(container)
		await get_tree().process_frame

	_stats = Tagger.collect_stats(_world_root)
	_bookmarks = MapData.bookmarks_for(map_id)
	_spawn_camera()
	_loading = false
	_apply_toggles()
	_update_hud()


func _spawn_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ReviewCamera"
	_camera.fov = 54.54
	_camera.near = 0.05
	_camera.far = 2000.0
	add_child(_camera)
	_camera.current = true
	if _bookmarks.is_empty():
		_camera.position = Vector3(0.0, 5.0, 10.0)
	else:
		_go_bookmark(0)


func _go_bookmark(i: int) -> void:
	if _camera == null or i < 0 or i >= _bookmarks.size():
		return
	var b: Dictionary = _bookmarks[i]
	var pos: Vector3 = b.get("pos", Vector3.ZERO)
	var target: Vector3 = b.get("target", pos + Vector3(0, 0, -5))
	_camera.global_position = pos
	var dir: Vector3 = (target - pos).normalized()
	_yaw = atan2(-dir.x, -dir.z)
	_pitch = asin(clampf(dir.y, -1.0, 1.0))
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)
	_status("Bookmark F%d: %s" % [i + 1, str(b.get("name", ""))])


func _process(delta: float) -> void:
	if _camera == null or _loading:
		return
	var dir: Vector3 = Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir -= _camera.global_basis.z
	if Input.is_physical_key_pressed(KEY_S):
		dir += _camera.global_basis.z
	if Input.is_physical_key_pressed(KEY_A):
		dir -= _camera.global_basis.x
	if Input.is_physical_key_pressed(KEY_D):
		dir += _camera.global_basis.x
	if Input.is_physical_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if dir.length_squared() > 0.0:
		var speed: float = MOVE_SPEED
		if Input.is_physical_key_pressed(KEY_SHIFT):
			speed *= FAST_MULT
		_camera.global_position += dir.normalized() * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_mouse_captured = not _mouse_captured
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseMotion and _mouse_captured and _camera != null:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= mm.relative.x * LOOK_SENSITIVITY
		_pitch = clampf(_pitch - mm.relative.y * LOOK_SENSITIVITY, -1.5, 1.5)
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)
		return
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code == KEY_ESCAPE:
		get_tree().quit()
		return
	if code == KEY_P:
		_save_capture()
		return
	if code >= KEY_F1 and code <= KEY_F6:
		_go_bookmark(int(code - KEY_F1))
		_update_hud()
		return
	var idx: int = _number_toggle_index(code)
	if idx >= 0:
		var name: String = NUMBER_TOGGLES[idx]
		_toggles[name] = not bool(_toggles.get(name, true))
		_apply_toggles()
		_update_hud()


func _number_toggle_index(code: Key) -> int:
	if code >= KEY_1 and code <= KEY_9:
		return int(code - KEY_1)
	if code == KEY_0:
		return 9
	return -1


func _save_capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_status("Capture failed (empty image).")
		return
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = CAPTURE_DIR.path_join("review_%s_%s.png" % [map_id, stamp])
	var err: int = img.save_png(path)
	_status("Saved %s (err=%d)" % [path, err])


func _apply_toggles() -> void:
	if _world_root == null:
		return
	for node: Node in _iter_nodes(_world_root):
		if not (node is Node3D) or node == _world_root:
			continue
		var n3: Node3D = node as Node3D
		var hidden: bool = false
		for toggle: String in NUMBER_TOGGLES:
			if bool(_toggles.get(toggle, true)):
				continue
			if Filters.matches(node, toggle):
				hidden = true
				break
		n3.visible = not hidden


func _iter_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c: Node in n.get_children():
			stack.push_back(c)
	return out


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "ReviewHUD"
	layer.layer = 100
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(520, 0)
	layer.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	_hud_title = _label(box, 18, Color(1.0, 0.86, 0.55))
	_hud_counts = _label(box, 13, Color(0.85, 0.92, 1.0))
	_hud_toggles = _label(box, 12, Color(0.7, 0.85, 0.75))
	_hud_hint = _label(box, 12, Color(0.72, 0.72, 0.78))
	_hud_status = _label(box, 12, Color(0.95, 0.75, 0.45))
	_hud_hint.text = "WASD move  LMB mouse  Shift fast  Q/E down/up  1-0 toggles  F1-F6 bookmarks  P capture  Esc quit"
	_update_hud()


func _label(parent: Node, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _status(text: String) -> void:
	if _hud_status != null:
		_hud_status.text = text


func _update_hud() -> void:
	if _hud_title == null:
		return
	_hud_title.text = "TAT-2 review  |  map=%s  |  %s" % [map_id, "loading..." if _loading else "ready"]
	if _stats.is_empty():
		_hud_counts.text = ""
		_hud_toggles.text = ""
		return
	var kinds: Dictionary = _stats.get("kinds", {})
	var issues: Dictionary = _stats.get("issues", {})
	_hud_counts.text = "sublevels=%d  nodes=%d  draws=%d  instances=%d  lights=%d  surfaces=%d\nissues: beams=%d labels=%d emissive=%d collision-only=%d" % [
		_containers.size(),
		int(_stats.get("nodes", 0)),
		int((kinds as Dictionary).get("mesh", 0)) + int((kinds as Dictionary).get("multimesh", 0)),
		int(_stats.get("instances", 0)),
		int(_stats.get("lights", 0)),
		int(_stats.get("surfaces", 0)),
		int((issues as Dictionary).get("beam_lines", 0)),
		int((issues as Dictionary).get("world_label", 0)),
		int((issues as Dictionary).get("emissive_plate", 0)),
		int((issues as Dictionary).get("collision_only", 0)),
	]
	var active: Array[String] = []
	var hidden: Array[String] = []
	for i: int in range(NUMBER_TOGGLES.size()):
		var t: String = NUMBER_TOGGLES[i]
		var key: String = "0" if i == 9 else str(i + 1)
		var line: String = "%s %s" % [key, t]
		if bool(_toggles.get(t, true)):
			active.append(line)
		else:
			hidden.append(line)
	_hud_toggles.text = "on:  %s\noff: %s" % [", ".join(active), ", ".join(hidden) if not hidden.is_empty() else "(none)"]
