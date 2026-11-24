@tool
extends VBoxContainer
## TAT-2 review dock. Bakes the review scenes with the same headless CLI the
## Makefile uses, opens them, and toggles the baked sublevel/kind/issue
## metadata. It never edits the baked scenes: visibility + toggle state are
## editor-only overrides remembered in the scene root's `review_toggles`
## metadata.
##
## Manual interaction is not automated (see docs/reports/review-map-baker.md).
## What is verified: the scripts parse with the rest of the project and the
## dock builds its control tree when the editor loads the plugin.

const Filters: GDScript = preload("res://addons/tat2_review/review_filters.gd")
const MAPS: Array[String] = ["guildhall", "thieves_den", "mission_lobby", "old_manor"]

var plugin: EditorPlugin

var _map_opt: OptionButton
var _status: Label
var _counts: Label
var _log: TextEdit
var _checks: Dictionary = {}
var _last_scene_root: Node = null
var _poll_frames: int = 0


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	name = "TAT-2 Review"
	custom_minimum_size = Vector2(300, 0)
	add_theme_constant_override("separation", 6)
	_build_ui()
	_sync_from_scene(false)
	set_process(true)


func _process(_delta: float) -> void:
	_poll_frames += 1
	if _poll_frames % 20 != 0:
		return
	var root: Node = _edited_root()
	if root != _last_scene_root:
		_last_scene_root = root
		_sync_from_scene(true)

func _build_ui() -> void:
	var title: Label = Label.new()
	title.text = "TAT-2 map review"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var map_row: HBoxContainer = HBoxContainer.new()
	add_child(map_row)
	_map_opt = OptionButton.new()
	_map_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m: String in MAPS:
		_map_opt.add_item(m)
	map_row.add_child(_map_opt)
	var open_btn: Button = Button.new()
	open_btn.text = "Open review scene"
	open_btn.pressed.connect(_on_open_pressed)
	map_row.add_child(open_btn)

	var bake_row: HBoxContainer = HBoxContainer.new()
	add_child(bake_row)
	var bake_btn: Button = Button.new()
	bake_btn.text = "Bake / Refresh (headless)"
	bake_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bake_btn.pressed.connect(_on_bake_pressed)
	bake_row.add_child(bake_btn)

	var toggles_label: Label = Label.new()
	toggles_label.text = "Show:"
	toggles_label.add_theme_font_size_override("font_size", 12)
	add_child(toggles_label)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	add_child(grid)
	for toggle: String in Filters.all_toggles():
		var cb: CheckBox = CheckBox.new()
		cb.text = toggle
		cb.button_pressed = true
		cb.toggled.connect(_on_toggle.bind(toggle))
		grid.add_child(cb)
		_checks[toggle] = cb

	var marks_label: Label = Label.new()
	marks_label.text = "Bookmarks (selects marker; press F to frame):"
	marks_label.add_theme_font_size_override("font_size", 12)
	add_child(marks_label)
	var mark_row: HBoxContainer = HBoxContainer.new()
	add_child(mark_row)
	for i: int in range(6):
		var b: Button = Button.new()
		b.text = "F%d" % [i + 1]
		b.tooltip_text = "Select review bookmark %d" % [i + 1]
		b.pressed.connect(_on_bookmark.bind(i))
		mark_row.add_child(b)

	_counts = Label.new()
	_counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_counts.add_theme_font_size_override("font_size", 12)
	add_child(_counts)

	_log = TextEdit.new()
	_log.editable = false
	_log.custom_minimum_size = Vector2(0, 90)
	_log.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log.add_theme_font_size_override("font_size", 11)
	add_child(_log)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.text = "Open a baked review.tscn, then use the toggles."
	add_child(_status)


func _ei() -> Object:
	return Engine.get_singleton("EditorInterface")


func _edited_root() -> Node:
	var ei: Object = _ei()
	if ei == null or not ei.has_method("get_edited_scene_root"):
		return null
	return ei.call("get_edited_scene_root") as Node


func _on_open_pressed() -> void:
	var path: String = _review_path()
	var ei: Object = _ei()
	if ei == null:
		return
	if not ResourceLoader.exists(path):
		_set_status("No baked scene at %s. Press Bake first." % path)
		return
	ei.call("open_scene_from_path", path)
	_set_status("Opened %s" % path)


func _on_bake_pressed() -> void:
	var map_id: String = _selected_map()
	var project_dir: String = ProjectSettings.globalize_path("res://")
	var repo_dir: String = project_dir.path_join("..").simplify_path()
	var script_path: String = repo_dir.path_join("tools/bake_review_map.gd")
	if not FileAccess.file_exists(script_path):
		_set_status("Baker not found at %s" % script_path)
		return
	var args: PackedStringArray = [
		"--headless",
		"--path", project_dir,
		"--script", script_path,
		"--",
		"--map=" + map_id,
		"--out=res://scenes/review/" + map_id,
	]
	_set_status("Baking %s (headless; the editor waits for the process)..." % map_id)
	var output: Array = []
	var started: int = Time.get_ticks_msec()
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var elapsed: float = (Time.get_ticks_msec() - started) / 1000.0
	var text: String = "\n".join(PackedStringArray(output))
	if text.length() > 3000:
		text = text.substr(text.length() - 3000)
	if _log != null:
		_log.text = text
	_set_status("Bake %s exit=%d in %.1fs" % [map_id, code, elapsed])
	var review_path: String = "res://scenes/review/%s/review.tscn" % map_id
	if code == 0 and ResourceLoader.exists(review_path):
		var ei: Object = _ei()
		if ei != null:
			ei.call("open_scene_from_path", review_path)
		_set_status("Baked and opened %s (%.1fs)." % [review_path, elapsed])
		_sync_from_scene(true)
	else:
		_set_status("Bake failed (exit=%d); see log. Output stays under %s." % [code, review_path.get_base_dir()])


func _on_toggle(pressed: bool, toggle: String) -> void:
	var root: Node = _edited_root()
	if root == null:
		return
	var state: Dictionary = _read_state(root)
	state[toggle] = pressed
	root.set_meta("review_toggles", state)
	_apply_to_scene(root)
	_update_counts(root)


func _on_bookmark(i: int) -> void:
	var root: Node = _edited_root()
	if root == null:
		_set_status("No scene is open.")
		return
	var marks: Array[Node3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Marker3D and n.has_meta("review_bookmark"):
			marks.append(n as Node3D)
		for c: Node in n.get_children():
			stack.push_back(c)
	marks.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.name < b.name)
	if i < 0 or i >= marks.size():
		_set_status("Bookmark F%d not present in this scene." % [i + 1])
		return
	var marker: Node3D = marks[i]
	var ei: Object = _ei()
	if ei == null:
		return
	var sel: Object = ei.call("get_selection")
	if sel != null:
		sel.call("clear")
		sel.call("add_node", marker)
	# Focus-selected is an editor action, not a public API on every 4.x build.
	# Try it when exposed; otherwise select the marker and say so (never fake
	# camera control).
	var focused: bool = _try_focus_selected()
	if focused:
		_set_status("Selected + framed %s." % str(marker.get_meta("review_bookmark", marker.name)))
	else:
		_set_status("Selected %s — press F in the 3D viewport to frame it." % str(marker.get_meta("review_bookmark", marker.name)))


func _try_focus_selected() -> bool:
	var ei: Object = _ei()
	if ei == null or not ei.has_method("get_editor_viewport_3d"):
		return false
	for idx: int in range(4):
		var vp: Object = ei.call("get_editor_viewport_3d", idx)
		if vp == null:
			continue
		for method: String in ["focus_selected", "focus_on_selection"]:
			if vp.has_method(method):
				vp.call(method)
				return true
	return false


func _sync_from_scene(apply_state: bool) -> void:
	var root: Node = _edited_root()
	if root == null:
		_counts.text = ""
		return
	var state: Dictionary = _read_state(root)
	for toggle: String in _checks.keys():
		var cb: CheckBox = _checks[toggle] as CheckBox
		cb.set_block_signals(true)
		cb.button_pressed = bool(state.get(toggle, true))
		cb.set_block_signals(false)
	if apply_state:
		_apply_to_scene(root)
	_update_counts(root)


func _read_state(root: Node) -> Dictionary:
	var state: Dictionary = {}
	if root.has_meta("review_toggles") and root.get_meta("review_toggles") is Dictionary:
		state = (root.get_meta("review_toggles") as Dictionary).duplicate()
	for toggle: String in _checks.keys():
		if not state.has(toggle):
			state[toggle] = true
	return state


func _apply_to_scene(root: Node) -> void:
	var state: Dictionary = _read_state(root)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.push_back(c)
		if not (n is Node3D) or n == root:
			continue
		var hidden: bool = false
		for toggle: String in state.keys():
			if bool(state[toggle]):
				continue
			if Filters.matches(n, toggle):
				hidden = true
				break
		(n as Node3D).visible = not hidden


func _update_counts(root: Node) -> void:
	var nodes: int = 0
	var kinds: Dictionary = {}
	var issues: Dictionary = {}
	var subs: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		for c: Node in n.get_children():
			stack.push_back(c)
		if n.has_meta("review_kind"):
			var k: String = str(n.get_meta("review_kind"))
			kinds[k] = int(kinds.get(k, 0)) + 1
		if n.has_meta("review_issue"):
			var i: String = str(n.get_meta("review_issue"))
			issues[i] = int(issues.get(i, 0)) + 1
		var sub: String = str(n.get_meta("review_sublevel", ""))
		if sub != "":
			subs[sub] = true
	_counts.text = "sublevels=%d nodes=%d mesh=%d multimesh=%d lights=%d decals=%d collision=%d\nbeams=%d labels=%d emissive=%d" % [
		subs.size(), nodes,
		int(kinds.get("mesh", 0)), int(kinds.get("multimesh", 0)),
		int(kinds.get("light", 0)), int(kinds.get("decal", 0)),
		int(kinds.get("collision", 0)),
		int(issues.get("beam_lines", 0)), int(issues.get("world_label", 0)),
		int(issues.get("emissive_plate", 0)),
	]


func _selected_map() -> String:
	if _map_opt == null or _map_opt.selected < 0:
		return "guildhall"
	return MAPS[mini(_map_opt.selected, MAPS.size() - 1)]


func _review_path() -> String:
	return "res://scenes/review/%s/review.tscn" % _selected_map()


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text
	print("TAT2_REVIEW: ", text)
