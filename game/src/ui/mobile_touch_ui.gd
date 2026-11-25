extends CanvasLayer
## Android touch controls: floating left move stick, right-side drag look,
## and a multi-touch action cluster. Desktop is untouched (only instantiated
## when MobileProfile.is_mobile()).
##
## All gameplay actions are dispatched through the existing input actions
## (InputEventAction / Input.action_press), so thief_character.gd remains the
## single source of truth. Look is delivered through add_look_pixel_delta().

const MobileProfile := preload("res://src/core/mobile_profile.gd")
const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")
const UIStringsScript := preload("res://src/ui/ui_strings.gd")

# P1 theme routing (audit-ui P1-3): every fill/border/label below references a
# ThemeScript.TOUCH_* token (the teal/gold/ivory aliases in
# res://src/ui/art_nouveau_theme.gd). Zero inline Color( in screen code.

const STICK_ZONE_WIDTH_FRACTION: float = 0.42
const STICK_ZONE_TOP_FRACTION: float = 0.28
const STICK_RADIUS_FRACTION: float = 0.15
const STICK_DEADZONE: float = 0.15
const LOOK_ZONE_START_FRACTION: float = 0.45
const AUTO_SPRINT_MAG: float = 0.9
const AUTO_SPRINT_DELAY: float = 0.35
const DEFAULT_TOUCH_SENSITIVITY: float = 2.5

var hud: Node = null

var _root: Control
var _stick_base: Panel
var _stick_knob: Panel
var _stick_touch: int = -1
var _stick_vector: Vector2 = Vector2.ZERO
var _stick_radius: float = 90.0
var _stick_center: Vector2 = Vector2.ZERO
var _look_touch: int = -1
var _look_last: Vector2 = Vector2.ZERO
var _button_touches: Dictionary = {} # touch index -> button id
var _buttons: Dictionary = {} # id -> { control, center, radius, action, hold, label }
var _button_order: Array[String] = []
var _held_actions: Dictionary = {}
var _auto_sprint_time: float = 0.0
var _tool_badges: Dictionary = {}
var _prompt_label: Label
var _interact_btn_id: String = "interact"
var _refresh_accum: float = 0.0
var _player: Node = null
var _safe: Rect2 = Rect2()


func _ready() -> void:
	# Sentinel: theme is the single source — log it, refuse silent drift.
	print("TAT-2 UI touch: theme=res://src/ui/art_nouveau_theme.gd (TOUCH_* tokens)")
	assert(ThemeScript != null, "MobileTouchUI requires res://src/ui/art_nouveau_theme.gd")
	add_to_group("mobile_touch_ui")
	layer = 6
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _exit_tree() -> void:
	clear_input()


func clear_input() -> void:
	for action: Variant in _held_actions.keys():
		Input.action_release(str(action))
	_held_actions.clear()
	_set_move_actions(Vector2.ZERO)
	_stick_touch = -1
	_look_touch = -1
	_stick_vector = Vector2.ZERO
	_button_touches.clear()
	_auto_sprint_time = 0.0
	if _stick_base != null:
		_stick_base.visible = false
	if _stick_knob != null:
		_stick_knob.visible = false


func get_button_count() -> int:
	return _button_order.size()


func get_button_center(id: String) -> Vector2:
	var entry: Dictionary = _buttons.get(id, {})
	return entry.get("center", Vector2.ZERO)


func get_button_ids() -> Array[String]:
	return _button_order.duplicate()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_stick_base = _make_circle(ThemeScript.TOUCH_STICK_FILL, ThemeScript.TOUCH_STICK_RING, 3.0)
	_stick_knob = _make_circle(ThemeScript.TOUCH_KNOB_FILL, ThemeScript.TOUCH_KNOB_RING, 2.0)
	_stick_base.visible = false
	_stick_knob.visible = false

	# Primary / jump (right edge). Authored ST_Settings_Input/Tools verbs where a
	# row exists; the rest are the port's short touch captions.
	_add_button("primary", "primary_action", false, 54.0, UIStringsScript.loc("HIT").to_upper(), "") ## PORT COPY (no authored row)
	_add_button("jump", "jump", false, 34.0, UIStringsScript.st_upper("ST_Settings", "Settings.Controls.Jump", "Jump"), "")
	# Interact / ability
	_add_button(_interact_btn_id, "interact", false, 40.0, UIStringsScript.st_upper("ST_Tools", "Tools_Deploy_Generic_Use", "Use"), "")
	_add_button("ability", "ability", false, 36.0, UIStringsScript.loc("SKILL").to_upper(), "") ## PORT COPY (no authored row)
	# Tools
	_add_button("tool_1", "tool_1", false, 28.0, UIStringsScript.loc("SAP").to_upper(), "") ## PORT COPY (no authored row)
	_add_button("tool_2", "tool_2", false, 28.0, UIStringsScript.loc("SMOKE").to_upper(), "") ## PORT COPY (no authored row)
	_add_button("tool_3", "tool_3", false, 28.0, UIStringsScript.loc("FAIRY").to_upper(), "") ## PORT COPY (no authored row)
	_add_button("vision", "thief_vision", false, 26.0, UIStringsScript.loc("EYE").to_upper(), "") ## PORT COPY (no authored row)
	# Utility row (bottom centre)
	_add_button("crouch", "crouch", false, 28.0, UIStringsScript.st_upper("ST_Settings_Input", "InputSetting.Movement.Crouch", "Crouch"), "")
	_add_button("sprint", "sprint", true, 28.0, UIStringsScript.st_upper("ST_Settings", "Settings.Controls.KBM.Sprint", "Sprint"), "")
	_add_button("lean_left", "lean_left", true, 26.0, UIStringsScript.loc("LEAN L").to_upper(), "") ## PORT COPY (no authored row)
	_add_button("lean_right", "lean_right", true, 26.0, UIStringsScript.loc("LEAN R").to_upper(), "") ## PORT COPY (no authored row)
	# Pause
	_add_button("pause", "", false, 24.0, "II", "")

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 14)
	_prompt_label.add_theme_color_override("font_color", ThemeScript.TOUCH_PROMPT)
	_prompt_label.add_theme_color_override("font_shadow_color", ThemeScript.TOUCH_SHADOW)
	_prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	_prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_prompt_label)

	_layout()


func _make_circle(fill: Color, border: Color, border_px: float) -> Panel:
	var panel: Panel = Panel.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(int(border_px))
	style.set_corner_radius_all(999)
	style.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	return panel


func _add_button(id: String, action: String, hold: bool, radius: float, text: String, icon_path: String) -> void:
	var panel: Panel = _make_circle(ThemeScript.TOUCH_BTN_FILL, ThemeScript.TOUCH_BTN_BORDER, 2.0)
	panel.name = "Touch_" + id
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", ThemeScript.TOUCH_BTN_LABEL)
	label.add_theme_color_override("font_shadow_color", ThemeScript.TOUCH_SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon: TextureRect = TextureRect.new()
		icon.texture = ResourceLoader.load(icon_path) as Texture2D
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = ThemeScript.TOUCH_ICON_MODULATE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.name = "Icon"
		panel.add_child(icon)
	_buttons[id] = {
		"control": panel,
		"label": label,
		"center": Vector2.ZERO,
		"radius": radius,
		"action": action,
		"hold": hold,
		"text": text,
	}
	_button_order.append(id)


func _layout() -> void:
	if _root == null:
		return
	var size: Vector2 = _root.size
	if size.x < 2.0 or size.y < 2.0:
		size = get_viewport().get_visible_rect().size
	var h: float = maxf(size.y, 1.0)
	var s: float = h / 720.0
	_safe = _safe_insets(size)
	var margin: float = 22.0 * s

	_stick_radius = clampf(h * STICK_RADIUS_FRACTION, 70.0, 190.0)
	_stick_base.size = Vector2(_stick_radius * 2.0, _stick_radius * 2.0)
	_stick_base.pivot_offset = _stick_base.size * 0.5
	_stick_knob.size = Vector2(_stick_radius * 0.9, _stick_radius * 0.9)
	_stick_knob.pivot_offset = _stick_knob.size * 0.5

	var br: Vector2 = Vector2(size.x - _safe.size.x - margin, size.y - _safe.size.y - margin)
	_place("primary", Vector2(br.x - 62.0 * s, br.y - 62.0 * s), 54.0 * s, s)
	_place("jump", Vector2(br.x - 62.0 * s, br.y - 182.0 * s), 34.0 * s, s)
	_place("interact", Vector2(br.x - 178.0 * s, br.y - 62.0 * s), 40.0 * s, s)
	_place("ability", Vector2(br.x - 178.0 * s, br.y - 166.0 * s), 36.0 * s, s)
	_place("tool_1", Vector2(br.x - 296.0 * s, br.y - 40.0 * s), 28.0 * s, s)
	_place("tool_2", Vector2(br.x - 296.0 * s, br.y - 108.0 * s), 28.0 * s, s)
	_place("tool_3", Vector2(br.x - 296.0 * s, br.y - 176.0 * s), 28.0 * s, s)
	_place("vision", Vector2(br.x - 296.0 * s, br.y - 244.0 * s), 26.0 * s, s)
	_place("pause", Vector2(br.x - 178.0 * s, br.y - 256.0 * s), 24.0 * s, s)

	var util_y: float = size.y - _safe.size.y - margin - 30.0 * s
	var util_x: float = size.x * 0.5 - 120.0 * s
	_place("crouch", Vector2(util_x, util_y), 28.0 * s, s)
	_place("sprint", Vector2(util_x + 76.0 * s, util_y), 28.0 * s, s)
	_place("lean_left", Vector2(util_x + 152.0 * s, util_y), 26.0 * s, s)
	_place("lean_right", Vector2(util_x + 224.0 * s, util_y), 26.0 * s, s)

	var interact_center: Vector2 = get_button_center("interact")
	_prompt_label.size = Vector2(320.0 * s, 40.0 * s)
	_prompt_label.position = interact_center + Vector2(-160.0 * s, -92.0 * s)
	_prompt_label.add_theme_font_size_override("font_size", int(14.0 * s))


func _safe_insets(size: Vector2) -> Rect2:
	_safe = Rect2()
	if not MobileProfile.is_mobile():
		return _safe
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return _safe
	var area: Rect2i = DisplayServer.get_display_safe_area()
	var sx: float = size.x / float(win.x)
	var sy: float = size.y / float(win.y)
	var left: float = maxf(0.0, float(area.position.x) * sx)
	var top: float = maxf(0.0, float(area.position.y) * sy)
	var right: float = maxf(0.0, size.x - float(area.position.x + area.size.x) * sx)
	var bottom: float = maxf(0.0, size.y - float(area.position.y + area.size.y) * sy)
	_safe = Rect2(left, top, right, bottom)
	return _safe


func _place(id: String, center: Vector2, radius: float, s: float) -> void:
	var entry: Dictionary = _buttons.get(id, {})
	if entry.is_empty():
		return
	entry["center"] = center
	entry["radius"] = radius
	var panel: Panel = entry["control"] as Panel
	panel.size = Vector2(radius * 2.0, radius * 2.0)
	panel.pivot_offset = panel.size * 0.5
	panel.position = center - panel.size * 0.5
	var label: Label = entry["label"] as Label
	label.size = panel.size
	if label.get_theme_font_size("font_size") > 0:
		label.add_theme_font_size_override("font_size", maxi(10, int(13.0 * s)))
	var icon: Node = panel.get_node_or_null("Icon")
	if icon is TextureRect:
		var tr: TextureRect = icon as TextureRect
		tr.size = panel.size * 0.62
		tr.position = panel.size * 0.19
		tr.size = panel.size * 0.5
		tr.position = Vector2(panel.size.x * 0.25, panel.size.y * 0.12)


func _input(event: InputEvent) -> void:
	if GameState.state != "playing" or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_handle_touch_down(touch.index, touch.position)
		else:
			_handle_touch_up(touch.index)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_handle_drag(drag.index, drag.position)


func _handle_touch_down(index: int, pos: Vector2) -> void:
	if _button_touches.has(index) or index == _stick_touch or index == _look_touch:
		return
	var hit: String = _hit_button(pos)
	if hit != "":
		_button_touches[index] = hit
		_press_button(hit)
		return
	var size: Vector2 = _root.size
	if pos.x <= size.x * STICK_ZONE_WIDTH_FRACTION and pos.y >= size.y * STICK_ZONE_TOP_FRACTION and _stick_touch < 0:
		_stick_touch = index
		_stick_center = pos
		_stick_base.position = pos - _stick_base.size * 0.5
		_stick_knob.position = pos - _stick_knob.size * 0.5
		_stick_base.visible = true
		_stick_knob.visible = true
		_stick_vector = Vector2.ZERO
		return
	if pos.x >= size.x * LOOK_ZONE_START_FRACTION and _look_touch < 0:
		_look_touch = index
		_look_last = pos


func _handle_touch_up(index: int) -> void:
	if index == _stick_touch:
		_stick_touch = -1
		_stick_vector = Vector2.ZERO
		_stick_base.visible = false
		_stick_knob.visible = false
		_set_move_actions(Vector2.ZERO)
		_release_auto_sprint()
		return
	if index == _look_touch:
		_look_touch = -1
		return
	if _button_touches.has(index):
		var id: String = str(_button_touches[index])
		_button_touches.erase(index)
		_release_button(id)


func _handle_drag(index: int, pos: Vector2) -> void:
	if index == _stick_touch:
		var offset: Vector2 = pos - _stick_center
		var limit: float = maxf(_stick_radius, 1.0)
		offset = offset.limit_length(limit)
		_stick_knob.position = _stick_center + offset - _stick_knob.size * 0.5
		_stick_vector = offset / limit
		_apply_stick()
		return
	if index == _look_touch:
		var delta: Vector2 = pos - _look_last
		_look_last = pos
		_apply_look(delta)


func _hit_button(pos: Vector2) -> String:
	for i in range(_button_order.size() - 1, -1, -1):
		var id: String = _button_order[i]
		var entry: Dictionary = _buttons[id]
		var center: Vector2 = entry["center"]
		var radius: float = float(entry["radius"])
		if pos.distance_to(center) <= radius + 10.0:
			return id
	return ""


func _press_button(id: String) -> void:
	var entry: Dictionary = _buttons.get(id, {})
	if entry.is_empty():
		return
	var action: String = str(entry["action"])
	if id == "pause":
		if hud != null and hud.has_method("toggle_pause"):
			hud.call("toggle_pause")
		return
	if action == "":
		return
	var hold: bool = bool(entry["hold"])
	if hold:
		if not _held_actions.has(action):
			Input.action_press(action)
			_held_actions[action] = true
	else:
		_dispatch_action(action)
	_flash(id, true)


func _release_button(id: String) -> void:
	var entry: Dictionary = _buttons.get(id, {})
	if entry.is_empty():
		return
	var action: String = str(entry["action"])
	if bool(entry["hold"]) and _held_actions.has(action):
		Input.action_release(action)
		_held_actions.erase(action)
	_flash(id, false)


func _dispatch_action(action: String) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventAction = InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _flash(id: String, down: bool) -> void:
	var entry: Dictionary = _buttons.get(id, {})
	if entry.is_empty():
		return
	var panel: Panel = entry["control"] as Panel
	if panel == null:
		return
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		style.bg_color = ThemeScript.TOUCH_FLASH_DOWN if down else ThemeScript.TOUCH_BTN_FILL


func _apply_stick() -> void:
	var vec: Vector2 = _stick_vector
	var mag: float = vec.length()
	if mag < STICK_DEADZONE:
		vec = Vector2.ZERO
		_auto_sprint_time = 0.0
		_release_auto_sprint()
	else:
		var scaled: float = (mag - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
		vec = vec.normalized() * minf(scaled, 1.0)
		if scaled >= AUTO_SPRINT_MAG:
			_auto_sprint_time += 1.0 / 60.0
		else:
			_auto_sprint_time = 0.0
	if vec == Vector2.ZERO:
		_set_move_actions(Vector2.ZERO)
		return
	Input.action_press("move_left", maxf(-vec.x, 0.0))
	Input.action_press("move_right", maxf(vec.x, 0.0))
	Input.action_press("move_forward", maxf(-vec.y, 0.0))
	Input.action_press("move_backward", maxf(vec.y, 0.0))
	# Sprint comes from the dedicated hold button or the auto full-deflection.
	var sprint_held: bool = _held_actions.has("sprint")
	if sprint_held:
		Input.action_press("sprint")
	elif _auto_sprint_time >= AUTO_SPRINT_DELAY:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")


func _release_auto_sprint() -> void:
	if not _held_actions.has("sprint"):
		Input.action_release("sprint")


func _set_move_actions(vec: Vector2) -> void:
	if vec == Vector2.ZERO:
		for action: String in ["move_left", "move_right", "move_forward", "move_backward"]:
			Input.action_release(action)
		return


func _apply_look(delta: Vector2) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null or not _player.has_method("add_look_pixel_delta"):
		return
	var settings: Dictionary = _settings()
	var sens: float = float(settings.get("touch_sensitivity", DEFAULT_TOUCH_SENSITIVITY))
	var invert: bool = bool(settings.get("invert_y", false))
	var px: Vector2 = delta * maxf(sens, 0.2)
	if invert:
		px.y = -px.y
	_player.call("add_look_pixel_delta", px)


func _settings() -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return {}
	var save_system: Node = tree.root.get_node_or_null("SaveSystem")
	if save_system == null:
		return {}
	var data_variant: Variant = save_system.get("data")
	if not (data_variant is Dictionary):
		return {}
	var data: Dictionary = data_variant
	var settings: Variant = data.get("settings", {})
	return settings if settings is Dictionary else {}


func _process(delta: float) -> void:
	if GameState.state != "playing" or get_tree().paused:
		return
	_refresh_accum += delta
	if _refresh_accum < 0.2:
		return
	_refresh_accum = 0.0
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_refresh_prompt()
	_refresh_charges()
	_refresh_ability_label()


func _refresh_prompt() -> void:
	var prompt: String = ""
	if hud != null:
		var value: Variant = hud.get("current_prompt")
		if value is String:
			prompt = str(value).strip_edges()
	if prompt.begins_with("["):
		var end: int = prompt.find("]")
		if end > 1:
			prompt = prompt.substr(end + 1).strip_edges()
	var entry: Dictionary = _buttons.get(_interact_btn_id, {})
	if entry.is_empty():
		return
	var panel: Panel = entry["control"] as Panel
	var available: bool = prompt != ""
	if panel != null and not bool(_button_touches.has(_interact_btn_id)):
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = ThemeScript.TOUCH_GLOW_ACTIVE if available else ThemeScript.TOUCH_GLOW_IDLE
	_prompt_label.text = prompt
	_prompt_label.visible = available


func _refresh_charges() -> void:
	if _player == null:
		return
	var charges_variant: Variant = _player.get("charges")
	if not (charges_variant is Dictionary):
		return
	var charges: Dictionary = charges_variant
	_set_badge("tool_1", int(charges.get("slithersap", 0)))
	_set_badge("tool_2", int(charges.get("smoke_bomb", 0)))
	_set_badge("tool_3", int(charges.get("pickpocket_fairy", 0)))


func _set_badge(id: String, count: int) -> void:
	var entry: Dictionary = _buttons.get(id, {})
	if entry.is_empty():
		return
	var panel: Panel = entry["control"] as Panel
	var label: Label = entry["label"] as Label
	if panel == null or label == null:
		return
	# Badge = label + charge count; the newline is layout, not copy.
	label.text = str(entry["text"]) + "\n" + str(count) if count > 0 else str(entry["text"])
	label.modulate = ThemeScript.TOUCH_BADGE_FULL if count > 0 else ThemeScript.TOUCH_BADGE_EMPTY


func _refresh_ability_label() -> void:
	if _player == null:
		return
	var entry: Dictionary = _buttons.get("ability", {})
	if entry.is_empty():
		return
	var label: Label = entry["label"] as Label
	if label == null:
		return
	match str(GameState.thief_id):
		"spider":
			label.text = UIStringsScript.loc("Wire").to_upper() ## PORT COPY (no authored row)
		"chameleon":
			label.text = UIStringsScript.loc("Mask").to_upper() ## PORT COPY (no authored row)
		"moth":
			label.text = UIStringsScript.loc("Astral").to_upper() ## PORT COPY (no authored row)
		_:
			label.text = UIStringsScript.loc("Skill").to_upper() ## PORT COPY (no authored row)
