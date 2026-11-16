extends CanvasLayer
## Dark-steampunk Settings UI: Controls / Audio / Graphics.
## Reads/writes SaveSystem.data['settings'] and persists via SaveSystem.write_save().

signal closed()

const SENS_MIN: float = 0.0005
const SENS_MAX: float = 0.008
const SENS_STEP: float = 0.0002
const FOV_MIN: float = 60.0
const FOV_MAX: float = 105.0
const VOL_MIN: float = 0.0
const VOL_MAX: float = 1.0
const VOL_STEP: float = 0.05
const SCALE_MIN: float = 0.6
const SCALE_MAX: float = 1.0
const SCALE_STEP: float = 0.05

var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _sens_slider: HSlider
var _sens_val: Label
var _invert_check: CheckBox
var _sprint_check: CheckBox
var _fov_slider: HSlider
var _fov_val: Label
var _vol_slider: HSlider
var _vol_val: Label
var _fullscreen_check: CheckBox
var _scale_slider: HSlider
var _scale_val: Label


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prev_mouse_mode = Input.mouse_mode
	_ensure_settings()
	_build_ui()
	_load_from_save()
	_apply_live(false)


func open_settings() -> void:
	visible = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_settings() -> void:
	_apply_live(true)
	closed.emit()
	Input.mouse_mode = _prev_mouse_mode
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_settings()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo and kev.keycode == KEY_ESCAPE:
			close_settings()
			get_viewport().set_input_as_handled()


func _settings() -> Dictionary:
	var data: Dictionary = SaveSystem.data
	if not data.has("settings") or not (data["settings"] is Dictionary):
		data["settings"] = {}
	var s: Dictionary = data["settings"]
	return s


func _ensure_settings() -> void:
	var s: Dictionary = _settings()
	if not s.has("mouse_sensitivity"):
		s["mouse_sensitivity"] = 0.0025
	if not s.has("invert_y"):
		s["invert_y"] = false
	if not s.has("sprint_toggle"):
		s["sprint_toggle"] = false
	if not s.has("fov"):
		s["fov"] = 75.0
	if not s.has("master_volume"):
		s["master_volume"] = 0.8
	if not s.has("fullscreen"):
		s["fullscreen"] = false
	if not s.has("render_scale"):
		s["render_scale"] = 1.0


func _load_from_save() -> void:
	var s: Dictionary = _settings()
	_sens_slider.value = clampf(float(s.get("mouse_sensitivity", 0.0025)), SENS_MIN, SENS_MAX)
	_invert_check.button_pressed = bool(s.get("invert_y", false))
	_sprint_check.button_pressed = bool(s.get("sprint_toggle", false))
	_fov_slider.value = clampf(float(s.get("fov", 75.0)), FOV_MIN, FOV_MAX)
	_vol_slider.value = clampf(float(s.get("master_volume", 0.8)), VOL_MIN, VOL_MAX)
	_fullscreen_check.button_pressed = bool(s.get("fullscreen", false))
	_scale_slider.value = clampf(float(s.get("render_scale", 1.0)), SCALE_MIN, SCALE_MAX)
	_refresh_value_labels()


func _apply_live(persist: bool) -> void:
	var sens: float = float(_sens_slider.value)
	var invert_y: bool = _invert_check.button_pressed
	var sprint_toggle: bool = _sprint_check.button_pressed
	var fov: float = float(_fov_slider.value)
	var vol: float = float(_vol_slider.value)
	var fullscreen: bool = _fullscreen_check.button_pressed
	var render_scale: float = float(_scale_slider.value)
	var s: Dictionary = _settings()
	s["mouse_sensitivity"] = sens
	s["invert_y"] = invert_y
	s["sprint_toggle"] = sprint_toggle
	s["fov"] = fov
	s["master_volume"] = vol
	s["fullscreen"] = fullscreen
	s["render_scale"] = render_scale
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.001)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	get_viewport().scaling_3d_scale = render_scale
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		cam.fov = fov
	if persist:
		SaveSystem.write_save()


func _refresh_value_labels() -> void:
	_sens_val.text = "%.4f" % float(_sens_slider.value)
	_fov_val.text = "%d" % int(_fov_slider.value)
	_vol_val.text = "%d%%" % int(round(float(_vol_slider.value) * 100.0))
	_scale_val.text = "%d%%" % int(round(float(_scale_slider.value) * 100.0))


func _build_ui() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.008, 0.02, 0.82)
	root.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.08, 0.97)
	style.border_color = Color(0.72, 0.55, 0.25, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var main_v: VBoxContainer = VBoxContainer.new()
	main_v.add_theme_constant_override("separation", 14)
	panel.add_child(main_v)

	var hdr: HBoxContainer = HBoxContainer.new()
	main_v.add_child(hdr)
	var title: Label = Label.new()
	title.text = "SETTINGS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	hdr.add_child(title)
	var close_btn: Button = Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close_settings)
	hdr.add_child(close_btn)

	main_v.add_child(_make_section_label("CONTROLS"))
	main_v.add_child(_make_slider_row("Mouse Sensitivity", SENS_MIN, SENS_MAX, SENS_STEP, true))
	main_v.add_child(_make_check_row("Invert Y", true))
	main_v.add_child(_make_check_row("Sprint Toggle", false))
	main_v.add_child(_make_slider_row("Field of View", FOV_MIN, FOV_MAX, 1.0, false))

	main_v.add_child(_make_section_label("AUDIO"))
	main_v.add_child(_make_slider_row("Master Volume", VOL_MIN, VOL_MAX, VOL_STEP, false))

	main_v.add_child(_make_section_label("GRAPHICS"))
	main_v.add_child(_make_check_row("Fullscreen", false))
	main_v.add_child(_make_slider_row("3D Render Scale", SCALE_MIN, SCALE_MAX, SCALE_STEP, false))

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	main_v.add_child(btn_row)
	var apply_btn: Button = Button.new()
	apply_btn.text = "APPLY"
	apply_btn.custom_minimum_size = Vector2(140, 40)
	apply_btn.pressed.connect(func() -> void: _apply_live(true))
	btn_row.add_child(apply_btn)
	var done_btn: Button = Button.new()
	done_btn.text = "CLOSE"
	done_btn.custom_minimum_size = Vector2(140, 40)
	done_btn.pressed.connect(close_settings)
	btn_row.add_child(done_btn)


func _make_section_label(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.85, 0.68, 0.35))
	return l


func _make_slider_row(label_text: String, min_v: float, max_v: float, step_v: float, is_sens: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lab: Label = Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(190, 0)
	lab.add_theme_font_size_override("font_size", 16)
	lab.add_theme_color_override("font_color", Color(0.90, 0.87, 0.80))
	row.add_child(lab)
	var slider: HSlider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var val: Label = Label.new()
	val.custom_minimum_size = Vector2(70, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 16)
	val.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	row.add_child(val)
	slider.value_changed.connect(func(_v: float) -> void: _refresh_value_labels())
	if label_text == "Mouse Sensitivity":
		_sens_slider = slider
		_sens_val = val
	elif label_text == "Field of View" and not is_sens:
		_fov_slider = slider
		_fov_val = val
	elif label_text == "Master Volume":
		_vol_slider = slider
		_vol_val = val
	elif label_text == "3D Render Scale":
		_scale_slider = slider
		_scale_val = val
	return row


func _make_check_row(label_text: String, is_invert: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var check: CheckBox = CheckBox.new()
	check.text = label_text
	check.add_theme_font_size_override("font_size", 16)
	check.add_theme_color_override("font_color", Color(0.90, 0.87, 0.80))
	row.add_child(check)
	if label_text == "Invert Y" and is_invert:
		_invert_check = check
	elif label_text == "Sprint Toggle" and not is_invert:
		_sprint_check = check
	elif label_text == "Fullscreen":
		_fullscreen_check = check
	return row
