class_name SettingsUI
extends CanvasLayer
## Art Nouveau Settings UI: GENERAL / VIDEO / AUDIO / CONTROLS tabs (Q/E to switch).
## Reads/writes SaveSystem.data['settings'] and persists via SaveSystem.write_save().

signal closed()

const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")

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

const TABS: Array[String] = ["GENERAL", "VIDEO", "AUDIO", "CONTROLS"]

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
var _touch_slider: HSlider
var _touch_val: Label
var _quality_btn: Button
var _tab_idx: int = 0
var _tab_btns: Array[Button] = []
var _pages: Array[Control] = []


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prev_mouse_mode = Input.mouse_mode
	_ensure_settings()
	_build_ui()
	_load_from_save()
	_apply_live(false)
	switch_tab(0)


func open_settings() -> void:
	visible = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_settings() -> void:
	_apply_live(true)
	closed.emit()
	Input.mouse_mode = _prev_mouse_mode
	queue_free()


func switch_tab(idx: int) -> void:
	_tab_idx = clampi(idx, 0, TABS.size() - 1)
	_refresh_tabs()


func _refresh_tabs() -> void:
	for i: int in range(_tab_btns.size()):
		var b: Button = _tab_btns[i]
		if b != null:
			b.button_pressed = (i == _tab_idx)
	for j: int in range(_pages.size()):
		var p: Control = _pages[j]
		if p != null:
			p.visible = (j == _tab_idx)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_settings()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if not kev.pressed or kev.echo:
			return
		if kev.keycode == KEY_ESCAPE:
			close_settings()
			get_viewport().set_input_as_handled()
			return
		if kev.keycode == KEY_Q:
			switch_tab((_tab_idx - 1 + TABS.size()) % TABS.size())
			get_viewport().set_input_as_handled()
			return
		if kev.keycode == KEY_E:
			switch_tab((_tab_idx + 1) % TABS.size())
			get_viewport().set_input_as_handled()
			return


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
	if not s.has("touch_sensitivity"):
		s["touch_sensitivity"] = 2.5
	if not s.has("mobile_quality"):
		s["mobile_quality"] = "balanced"


func reset_defaults() -> void:
	var s: Dictionary = _settings()
	s["mouse_sensitivity"] = 0.0025
	s["invert_y"] = false
	s["sprint_toggle"] = false
	s["fov"] = 75.0
	s["master_volume"] = 0.8
	s["fullscreen"] = false
	s["render_scale"] = 1.0
	s["touch_sensitivity"] = 2.5
	s["mobile_quality"] = "balanced"
	_load_from_save()
	_apply_live(true)


func _load_from_save() -> void:
	var s: Dictionary = _settings()
	if _sens_slider != null:
		_sens_slider.value = clampf(float(s.get("mouse_sensitivity", 0.0025)), SENS_MIN, SENS_MAX)
	if _invert_check != null:
		_invert_check.button_pressed = bool(s.get("invert_y", false))
	if _sprint_check != null:
		_sprint_check.button_pressed = bool(s.get("sprint_toggle", false))
	if _fov_slider != null:
		_fov_slider.value = clampf(float(s.get("fov", 75.0)), FOV_MIN, FOV_MAX)
	if _vol_slider != null:
		_vol_slider.value = clampf(float(s.get("master_volume", 0.8)), VOL_MIN, VOL_MAX)
	if _fullscreen_check != null:
		_fullscreen_check.button_pressed = bool(s.get("fullscreen", false))
	if _scale_slider != null:
		_scale_slider.value = clampf(float(s.get("render_scale", 1.0)), SCALE_MIN, SCALE_MAX)
	if _touch_slider != null:
		_touch_slider.value = clampf(float(s.get("touch_sensitivity", 2.5)), 0.5, 5.0)
	if _quality_btn != null:
		_quality_btn.text = "MOBILE QUALITY: " + MobileProfile.tier_label(MobileProfile.current_tier()).to_upper()
	_refresh_value_labels()


func _apply_live(persist: bool) -> void:
	if _sens_slider == null or _fov_slider == null or _vol_slider == null:
		return
	var sens: float = float(_sens_slider.value)
	var invert_y: bool = _invert_check.button_pressed if _invert_check != null else false
	var sprint_toggle: bool = _sprint_check.button_pressed if _sprint_check != null else false
	var fov: float = float(_fov_slider.value)
	var vol: float = float(_vol_slider.value)
	var fullscreen: bool = _fullscreen_check.button_pressed if _fullscreen_check != null else false
	var render_scale: float = float(_scale_slider.value)
	var s: Dictionary = _settings()
	s["mouse_sensitivity"] = sens
	s["invert_y"] = invert_y
	s["sprint_toggle"] = sprint_toggle
	s["fov"] = fov
	s["master_volume"] = vol
	s["fullscreen"] = fullscreen
	s["render_scale"] = render_scale
	if _touch_slider != null:
		s["touch_sensitivity"] = float(_touch_slider.value)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.001)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		get_viewport().scaling_3d_scale = render_scale
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		cam.fov = fov
	if persist:
		SaveSystem.write_save()


func _refresh_value_labels() -> void:
	if _sens_val != null and _sens_slider != null:
		_sens_val.text = "%.4f" % float(_sens_slider.value)
	if _fov_val != null and _fov_slider != null:
		_fov_val.text = "%d" % int(_fov_slider.value)
	if _vol_val != null and _vol_slider != null:
		_vol_val.text = "%d%%" % int(round(float(_vol_slider.value) * 100.0))
	if _scale_val != null and _scale_slider != null:
		_scale_val.text = "%d%%" % int(round(float(_scale_slider.value) * 100.0))
	if _touch_val != null and _touch_slider != null:
		_touch_val.text = "x%.1f" % float(_touch_slider.value)


func _build_ui() -> void:
	var modal: Dictionary = ThemeScript.make_modal(self, Vector2(640, 0), "SETTINGS", "[Q] / [E] SWITCH TAB   ·   [ESC] BACK")
	var vbox: VBoxContainer = modal["vbox"] as VBoxContainer
	var tab_row: HBoxContainer = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(tab_row)
	_tab_btns.clear()
	for i: int in range(TABS.size()):
		var tb: Button = Button.new()
		tb.text = TABS[i]
		tb.toggle_mode = true
		tb.custom_minimum_size = Vector2(132, 36)
		ThemeScript.style_button(tb, i == 0)
		var tab_idx: int = i
		tb.pressed.connect(func() -> void: switch_tab(tab_idx))
		tab_row.add_child(tb)
		_tab_btns.append(tb)
	var hint: HBoxContainer = HBoxContainer.new()
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_theme_constant_override("separation", 6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint)
	var qk: PanelContainer = ThemeScript.keycap("[Q]", 12)
	hint.add_child(qk)
	var ql: Label = Label.new()
	ql.text = "PREV"
	ql.add_theme_font_size_override("font_size", 12)
	ql.add_theme_color_override("font_color", Color(0.65, 0.75, 0.78))
	hint.add_child(ql)
	var ek: PanelContainer = ThemeScript.keycap("[E]", 12)
	hint.add_child(ek)
	var el: Label = Label.new()
	el.text = "NEXT"
	el.add_theme_font_size_override("font_size", 12)
	el.add_theme_color_override("font_color", Color(0.65, 0.75, 0.78))
	hint.add_child(el)

	_pages.clear()
	for t: int in range(TABS.size()):
		var page: VBoxContainer = VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(page)
		_pages.append(page)

	# GENERAL tab.
	var general: VBoxContainer = _pages[0] as VBoxContainer
	general.add_child(ThemeScript.section_header("GENERAL"))
	general.add_child(_make_slider_row("Mouse Sensitivity", SENS_MIN, SENS_MAX, SENS_STEP, true))
	general.add_child(_make_check_row("Invert Y", true))
	general.add_child(_make_check_row("Sprint Toggle", false))

	# VIDEO tab.
	var video: VBoxContainer = _pages[1] as VBoxContainer
	video.add_child(ThemeScript.section_header("VIDEO"))
	video.add_child(_make_slider_row("Field of View", FOV_MIN, FOV_MAX, 1.0, false))
	video.add_child(_make_check_row("Fullscreen", false))
	video.add_child(_make_slider_row("Resolution Scale", SCALE_MIN, SCALE_MAX, SCALE_STEP, false))

	# AUDIO tab.
	var audio: VBoxContainer = _pages[2] as VBoxContainer
	audio.add_child(ThemeScript.section_header("AUDIO"))
	audio.add_child(_make_slider_row("Master Volume", VOL_MIN, VOL_MAX, VOL_STEP, false))

	# CONTROLS tab (read-only reference + sprint toggle lives in GENERAL).
	var controls: VBoxContainer = _pages[3] as VBoxContainer
	controls.add_child(ThemeScript.section_header("CONTROLS"))
	var rows: Array[Array] = [
		["W A S D", "MOVE"],
		["MOUSE", "LOOK"],
		["F", "INTERACT / STEAL"],
		["Q", "PREV TAB"],
		["E", "NEXT TAB / INTERACT"],
		["H", "THIEF VISION"],
		["R", "RESTART CHECKPOINT"],
		["SPACE", "JUMP / VAULT"],
		["ESC", "BACK / PAUSE"],
	]
	if MobileProfile.is_mobile():
		rows = [
			["STICK", "MOVE"],
			["DRAG", "LOOK"],
			["USE", "INTERACT / STEAL"],
			["HIT / WIRE", "ATTACK / ABILITY"],
			["1 2 3", "TOOLS"],
			["EYE", "THIEF VISION"],
			["II / BACK", "PAUSE"],
		]
	for entry: Array in rows:
		controls.add_child(_make_binding_row(str(entry[0]), str(entry[1])))
	if MobileProfile.is_mobile():
		controls.add_child(_make_slider_row("Touch Look", 0.5, 5.0, 0.1, false))
		var qrow: HBoxContainer = HBoxContainer.new()
		_quality_btn = Button.new()
		_quality_btn.text = "MOBILE QUALITY: " + MobileProfile.tier_label(MobileProfile.current_tier()).to_upper()
		_quality_btn.custom_minimum_size = Vector2(300, 42)
		ThemeScript.style_button(_quality_btn, false)
		_quality_btn.pressed.connect(_cycle_quality)
		qrow.add_child(_quality_btn)
		controls.add_child(qrow)

	vbox.add_child(ThemeScript.divider())
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)
	var reset_btn: Button = Button.new()
	reset_btn.text = "RESET DEFAULTS"
	reset_btn.custom_minimum_size = Vector2(190, 42)
	ThemeScript.style_button(reset_btn, false)
	reset_btn.pressed.connect(reset_defaults)
	btn_row.add_child(reset_btn)
	var back_row: HBoxContainer = HBoxContainer.new()
	back_row.add_theme_constant_override("separation", 6)
	btn_row.add_child(back_row)
	var back_btn: Button = Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(130, 42)
	ThemeScript.style_button(back_btn, true)
	back_btn.pressed.connect(close_settings)
	back_row.add_child(back_btn)
	var esc: PanelContainer = ThemeScript.keycap("[ESC]", 12)
	back_row.add_child(esc)


func _cycle_quality() -> void:
	var next_tier: int = (MobileProfile.current_tier() + 1) % MobileProfile.TIER_LABELS.size()
	MobileProfile.set_tier(next_tier, SaveSystem)
	MobileProfile.apply_runtime(get_tree())
	if _quality_btn != null:
		_quality_btn.text = "MOBILE QUALITY: " + MobileProfile.tier_label(next_tier).to_upper()


func _make_binding_row(key_text: String, action_text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var badge: PanelContainer = ThemeScript.keycap("[" + key_text + "]", 13)
	row.add_child(badge)
	var lab: Label = Label.new()
	lab.text = action_text.to_upper()
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color(0.55, 0.92, 0.95))
	row.add_child(lab)
	return row


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
	elif label_text == "Resolution Scale" or label_text == "3D Render Scale":
		_scale_slider = slider
		_scale_val = val
	elif label_text == "Touch Look":
		_touch_slider = slider
		_touch_val = val
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
