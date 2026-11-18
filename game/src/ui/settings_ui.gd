class_name SettingsUI
extends CanvasLayer
## Art Nouveau Teal Settings UI: GENERAL / VIDEO / AUDIO / CONTROLS tabs (Q/E to switch).
## Loads authored labels from ST_Settings.json, groups rows into teal cards,
## reads/writes SaveSystem.data['settings'] live, and persists via SaveSystem.write_save().

signal closed()

const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")

const ST_SETTINGS_PATH: String = "res://data/generated/tables/StringTables/ST_Settings.json"

const TEAL_PANEL_BG: Color = Color(0.035, 0.085, 0.105, 0.96)
const TEAL_GROUP_BG: Color = Color(0.055, 0.130, 0.155, 0.90)
const TEAL_BORDER: Color = Color(0.24, 0.66, 0.68, 0.92)
const TEAL_ACCENT: Color = Color(0.45, 0.90, 0.90, 1.0)
const TEAL_TEXT: Color = Color(0.86, 0.94, 0.94, 1.0)

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

var _st: Dictionary = {}
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _sens_slider: HSlider
var _sens_val: Label
var _invert_check: CheckBox
var _sprint_check: CheckBox
var _bounce_check: CheckBox
var _fov_slider: HSlider
var _fov_val: Label
var _vsync_check: CheckBox
var _vol_slider: HSlider
var _vol_val: Label
var _music_slider: HSlider
var _music_val: Label
var _sfx_slider: HSlider
var _sfx_val: Label
var _dlg_slider: HSlider
var _dlg_val: Label
var _fullscreen_check: CheckBox
var _scale_slider: HSlider
var _scale_val: Label
var _touch_slider: HSlider
var _touch_val: Label
var _quality_btn: Button
var _tab_idx: int = 0
var _tab_btns: Array[Button] = []
var _pages: Array[Control] = []
var _group_cards: Array[PanelContainer] = []
var _modal_panel: PanelContainer = null
var _loading_ui: bool = false


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prev_mouse_mode = Input.mouse_mode
	_load_string_table()
	_ensure_settings()
	_build_ui()
	_load_from_save()
	_apply_live(false)
	switch_tab(0)


func _load_string_table() -> void:
	if not FileAccess.file_exists(ST_SETTINGS_PATH):
		return
	var f: FileAccess = FileAccess.open(ST_SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and (parsed as Dictionary).has("entries"):
		var ent: Variant = (parsed as Dictionary)["entries"]
		if ent is Dictionary:
			_st = ent as Dictionary


func _label(key: String, fallback: String) -> String:
	if _st.has(key):
		var v: String = str(_st[key]).strip_edges()
		if v != "":
			return v
	return fallback


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
			_style_teal_tab(b, i == _tab_idx)
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
	if not s.has("reduced_camera_bounce"):
		s["reduced_camera_bounce"] = false
	if not s.has("fov"):
		s["fov"] = 75.0
	if not s.has("vsync"):
		s["vsync"] = true
	if not s.has("master_volume"):
		s["master_volume"] = 0.8
	if not s.has("music_volume"):
		s["music_volume"] = 0.8
	if not s.has("sfx_volume"):
		s["sfx_volume"] = 0.8
	if not s.has("dialogue_volume"):
		s["dialogue_volume"] = 0.8
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
	s["reduced_camera_bounce"] = false
	s["fov"] = 75.0
	s["vsync"] = true
	s["master_volume"] = 0.8
	s["music_volume"] = 0.8
	s["sfx_volume"] = 0.8
	s["dialogue_volume"] = 0.8
	s["fullscreen"] = false
	s["render_scale"] = 1.0
	s["touch_sensitivity"] = 2.5
	s["mobile_quality"] = "balanced"
	_load_from_save()
	_apply_live(true)


func _load_from_save() -> void:
	_loading_ui = true
	var s: Dictionary = _settings()
	if _sens_slider != null:
		_sens_slider.value = clampf(float(s.get("mouse_sensitivity", 0.0025)), SENS_MIN, SENS_MAX)
	if _invert_check != null:
		_invert_check.button_pressed = bool(s.get("invert_y", false))
	if _sprint_check != null:
		_sprint_check.button_pressed = bool(s.get("sprint_toggle", false))
	if _bounce_check != null:
		_bounce_check.button_pressed = bool(s.get("reduced_camera_bounce", false))
	if _fov_slider != null:
		_fov_slider.value = clampf(float(s.get("fov", 75.0)), FOV_MIN, FOV_MAX)
	if _vsync_check != null:
		_vsync_check.button_pressed = bool(s.get("vsync", true))
	if _vol_slider != null:
		_vol_slider.value = clampf(float(s.get("master_volume", 0.8)), VOL_MIN, VOL_MAX)
	if _music_slider != null:
		_music_slider.value = clampf(float(s.get("music_volume", 0.8)), VOL_MIN, VOL_MAX)
	if _sfx_slider != null:
		_sfx_slider.value = clampf(float(s.get("sfx_volume", 0.8)), VOL_MIN, VOL_MAX)
	if _dlg_slider != null:
		_dlg_slider.value = clampf(float(s.get("dialogue_volume", 0.8)), VOL_MIN, VOL_MAX)
	if _fullscreen_check != null:
		_fullscreen_check.button_pressed = bool(s.get("fullscreen", false))
	if _scale_slider != null:
		_scale_slider.value = clampf(float(s.get("render_scale", 1.0)), SCALE_MIN, SCALE_MAX)
	if _touch_slider != null:
		_touch_slider.value = clampf(float(s.get("touch_sensitivity", 2.5)), 0.5, 5.0)
	if _quality_btn != null:
		_quality_btn.text = "MOBILE QUALITY: " + MobileProfile.tier_label(MobileProfile.current_tier()).to_upper()
	_loading_ui = false
	_refresh_value_labels()


func _apply_live(persist: bool) -> void:
	if _loading_ui or _sens_slider == null or _fov_slider == null or _vol_slider == null:
		return
	var s: Dictionary = _settings()
	s["mouse_sensitivity"] = float(_sens_slider.value)
	s["invert_y"] = _invert_check.button_pressed if _invert_check != null else false
	s["sprint_toggle"] = _sprint_check.button_pressed if _sprint_check != null else false
	s["reduced_camera_bounce"] = _bounce_check.button_pressed if _bounce_check != null else false
	s["fov"] = float(_fov_slider.value)
	s["vsync"] = _vsync_check.button_pressed if _vsync_check != null else true
	s["master_volume"] = float(_vol_slider.value)
	if _music_slider != null:
		s["music_volume"] = float(_music_slider.value)
	if _sfx_slider != null:
		s["sfx_volume"] = float(_sfx_slider.value)
	if _dlg_slider != null:
		s["dialogue_volume"] = float(_dlg_slider.value)
	s["fullscreen"] = _fullscreen_check.button_pressed if _fullscreen_check != null else false
	s["render_scale"] = float(_scale_slider.value)
	if _touch_slider != null:
		s["touch_sensitivity"] = float(_touch_slider.value)
	if SaveSystem.has_method("apply_saved_settings"):
		SaveSystem.call("apply_saved_settings")
	else:
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(s["master_volume"]), 0.001)))
	var vp: Viewport = get_viewport()
	if vp != null:
		var cam: Camera3D = vp.get_camera_3d()
		if cam != null:
			cam.fov = float(s["fov"])
	if get_tree() != null:
		for pnode: Node in get_tree().get_nodes_in_group("player"):
			if pnode.has_method("apply_saved_settings"):
				pnode.call("apply_saved_settings", true)
	if persist:
		SaveSystem.write_save()


func _refresh_value_labels() -> void:
	if _sens_val != null and _sens_slider != null:
		_sens_val.text = "%.4f" % float(_sens_slider.value)
	if _fov_val != null and _fov_slider != null:
		_fov_val.text = "%d" % int(_fov_slider.value)
	if _vol_val != null and _vol_slider != null:
		_vol_val.text = "%d%%" % int(round(float(_vol_slider.value) * 100.0))
	if _music_val != null and _music_slider != null:
		_music_val.text = "%d%%" % int(round(float(_music_slider.value) * 100.0))
	if _sfx_val != null and _sfx_slider != null:
		_sfx_val.text = "%d%%" % int(round(float(_sfx_slider.value) * 100.0))
	if _dlg_val != null and _dlg_slider != null:
		_dlg_val.text = "%d%%" % int(round(float(_dlg_slider.value) * 100.0))
	if _scale_val != null and _scale_slider != null:
		_scale_val.text = "%d%%" % int(round(float(_scale_slider.value) * 100.0))
	if _touch_val != null and _touch_slider != null:
		_touch_val.text = "x%.1f" % float(_touch_slider.value)


func _style_teal_tab(btn: Button, active: bool) -> void:
	var st_box: StyleBoxFlat = StyleBoxFlat.new()
	st_box.set_border_width_all(1)
	st_box.set_corner_radius_all(5)
	st_box.set_content_margin_all(10)
	if active:
		st_box.bg_color = Color(0.14, 0.42, 0.44, 0.98)
		st_box.border_color = TEAL_ACCENT
		btn.add_theme_color_override("font_color", Color(0.96, 1.0, 0.99))
	else:
		st_box.bg_color = Color(0.05, 0.12, 0.14, 0.94)
		st_box.border_color = Color(TEAL_BORDER.r, TEAL_BORDER.g, TEAL_BORDER.b, 0.55)
		btn.add_theme_color_override("font_color", TEAL_TEXT)
	btn.add_theme_stylebox_override("normal", st_box)
	btn.add_theme_stylebox_override("pressed", st_box)
	var hov: StyleBoxFlat = st_box.duplicate() as StyleBoxFlat
	hov.border_color = TEAL_ACCENT
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_font_size_override("font_size", 15)


func _make_group_card(group_title: String) -> Dictionary:
	var card: PanelContainer = PanelContainer.new()
	card.name = "Group_" + group_title.replace(" ", "")
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = TEAL_GROUP_BG
	style.border_color = TEAL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	var hdr: Label = Label.new()
	hdr.text = group_title.to_upper()
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", TEAL_ACCENT)
	vb.add_child(hdr)
	var sep: ColorRect = ColorRect.new()
	sep.color = Color(TEAL_BORDER.r, TEAL_BORDER.g, TEAL_BORDER.b, 0.45)
	sep.custom_minimum_size = Vector2(0, 1)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(sep)
	_group_cards.append(card)
	return {"card": card, "vbox": vb}


func _build_ui() -> void:
	var modal: Dictionary = ThemeScript.make_modal(self, Vector2(680, 0), "SETTINGS", "[Q] / [E] SWITCH TAB   ·   [ESC] BACK")
	_modal_panel = modal["panel"] as PanelContainer
	if _modal_panel != null:
		var teal_panel: StyleBoxFlat = ThemeScript.panel_style(2, 8, TEAL_PANEL_BG)
		teal_panel.border_color = TEAL_BORDER
		_modal_panel.add_theme_stylebox_override("panel", teal_panel)
	var title_lbl: Label = modal["title"] as Label
	if title_lbl != null:
		title_lbl.add_theme_color_override("font_color", TEAL_ACCENT)
	var vbox: VBoxContainer = modal["vbox"] as VBoxContainer

	var tab_labels: Array[String] = [
		_label("Settings.General", "GENERAL").to_upper(),
		_label("Settings.Display.Header", "VIDEO").to_upper(),
		_label("Settings.Audio.Header", "AUDIO").to_upper(),
		_label("Settings.Controls.Header", "CONTROLS").to_upper(),
	]
	var tab_row: HBoxContainer = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(tab_row)
	_tab_btns.clear()
	for i: int in range(TABS.size()):
		var tb: Button = Button.new()
		tb.text = tab_labels[i]
		tb.toggle_mode = true
		tb.custom_minimum_size = Vector2(142, 36)
		_style_teal_tab(tb, i == 0)
		var tab_idx: int = i
		tb.pressed.connect(func() -> void: switch_tab(tab_idx))
		tab_row.add_child(tb)
		_tab_btns.append(tb)

	_pages.clear()
	_group_cards.clear()
	for _t: int in range(TABS.size()):
		var page: VBoxContainer = VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(page)
		_pages.append(page)

	# GENERAL tab: grouped into Mouse + Gameplay cards.
	var general: VBoxContainer = _pages[0] as VBoxContainer
	var grp_mouse: Dictionary = _make_group_card(_label("Settings.Mouse", "Mouse"))
	general.add_child(grp_mouse["card"] as PanelContainer)
	var mouse_vb: VBoxContainer = grp_mouse["vbox"] as VBoxContainer
	mouse_vb.add_child(_make_slider_row("mouse_sensitivity", _label("Settings.Mouse.MouseSensitivity", "Mouse Sensitivity"), SENS_MIN, SENS_MAX, SENS_STEP))
	mouse_vb.add_child(_make_check_row("invert_y", _label("Settings.Mouse.MouseInvertYAxis", "Mouse Invert Y-Axis")))

	var grp_gameplay: Dictionary = _make_group_card(_label("Settings.Gameplay", "Gameplay"))
	general.add_child(grp_gameplay["card"] as PanelContainer)
	var gp_vb: VBoxContainer = grp_gameplay["vbox"] as VBoxContainer
	gp_vb.add_child(_make_check_row("sprint_toggle", _label("Settings.Gameplay.SprintToggle", "Sprint Toggle")))
	gp_vb.add_child(_make_check_row("reduced_camera_bounce", _label("Settings.Gameplay.ReducedCameraBounce", "Reduced Camera Bounce")))

	# VIDEO tab: grouped into Display + Graphics Quality cards.
	var video: VBoxContainer = _pages[1] as VBoxContainer
	var grp_disp: Dictionary = _make_group_card(_label("Settings.Display", "Display"))
	video.add_child(grp_disp["card"] as PanelContainer)
	var disp_vb: VBoxContainer = grp_disp["vbox"] as VBoxContainer
	disp_vb.add_child(_make_slider_row("fov", _label("Settings.Camera.FOV", "Field of View"), FOV_MIN, FOV_MAX, 1.0))
	disp_vb.add_child(_make_check_row("fullscreen", _label("Settings.Display.WindowMode.Fullscreen", "Fullscreen")))
	disp_vb.add_child(_make_check_row("vsync", _label("Settings.Display.VSync", "V-Sync")))

	var grp_qual: Dictionary = _make_group_card(_label("Settings.GraphicsQuality", "Graphics Quality"))
	video.add_child(grp_qual["card"] as PanelContainer)
	var qual_vb: VBoxContainer = grp_qual["vbox"] as VBoxContainer
	qual_vb.add_child(_make_slider_row("render_scale", _label("Settings.GraphicsQuality.ResolutionScale", "Resolution Scale"), SCALE_MIN, SCALE_MAX, SCALE_STEP))

	# AUDIO tab: grouped into Volume card.
	var audio: VBoxContainer = _pages[2] as VBoxContainer
	var grp_vol: Dictionary = _make_group_card(_label("Settings.Volume", "Volume"))
	audio.add_child(grp_vol["card"] as PanelContainer)
	var vol_vb: VBoxContainer = grp_vol["vbox"] as VBoxContainer
	vol_vb.add_child(_make_slider_row("master_volume", _label("Settings.Volume.MasterVolume", "Master Volume"), VOL_MIN, VOL_MAX, VOL_STEP))
	vol_vb.add_child(_make_slider_row("music_volume", _label("Settings.Volume.MusicVolume", "Music Volume"), VOL_MIN, VOL_MAX, VOL_STEP))
	vol_vb.add_child(_make_slider_row("sfx_volume", _label("Settings.Volume.SFXVolume", "SFX Volume"), VOL_MIN, VOL_MAX, VOL_STEP))
	vol_vb.add_child(_make_slider_row("dialogue_volume", _label("Settings.Volume.DialogueVolume", "Dialogue Volume"), VOL_MIN, VOL_MAX, VOL_STEP))

	# CONTROLS tab: grouped card.
	var controls: VBoxContainer = _pages[3] as VBoxContainer
	var grp_ctrl: Dictionary = _make_group_card(_label("Settings.Controls.Header", "Controls"))
	controls.add_child(grp_ctrl["card"] as PanelContainer)
	var ctrl_vb: VBoxContainer = grp_ctrl["vbox"] as VBoxContainer
	var rows: Array[Array] = [
		["W A S D", _label("Settings.Controls.KBM.Movement", "Movement & Lean")],
		["MOUSE", _label("Settings.Controls.Look", "Look")],
		["F", _label("Settings.Controls.Interact", "Interact")],
		["SHIFT", _label("Settings.Controls.KBM.Sprint", "Sprint")],
		["C", _label("Settings.Controls.KBM.Crouch", "Crouch / Slide")],
		["SPACE", _label("Settings.Controls.Jump", "Jump")],
		["1 2 3", _label("Settings.Controls.ToolSlots", "Tool Slots")],
		["H", _label("Settings.Controls.Slot4", "Vistara Diamond")],
		["ESC", _label("Settings.Controls.GameMenu", "Game Menu")],
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
		ctrl_vb.add_child(_make_binding_row(str(entry[0]), str(entry[1])))
	if MobileProfile.is_mobile():
		ctrl_vb.add_child(_make_slider_row("touch_sensitivity", "Touch Look", 0.5, 5.0, 0.1))
		var qrow: HBoxContainer = HBoxContainer.new()
		_quality_btn = Button.new()
		_quality_btn.text = "MOBILE QUALITY: " + MobileProfile.tier_label(MobileProfile.current_tier()).to_upper()
		_quality_btn.custom_minimum_size = Vector2(300, 42)
		ThemeScript.style_button(_quality_btn, false)
		_quality_btn.pressed.connect(_cycle_quality)
		qrow.add_child(_quality_btn)
		ctrl_vb.add_child(qrow)

	vbox.add_child(ThemeScript.divider())
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)
	var reset_btn: Button = Button.new()
	reset_btn.text = _label("Settings.Changes.Revert", "RESET DEFAULTS").to_upper()
	reset_btn.custom_minimum_size = Vector2(190, 42)
	ThemeScript.style_button(reset_btn, false)
	reset_btn.pressed.connect(reset_defaults)
	btn_row.add_child(reset_btn)
	var back_row: HBoxContainer = HBoxContainer.new()
	back_row.add_theme_constant_override("separation", 6)
	btn_row.add_child(back_row)
	var back_btn: Button = Button.new()
	back_btn.text = _label("Settings.Changes.Apply", "APPLY & BACK").to_upper()
	back_btn.custom_minimum_size = Vector2(160, 42)
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
	lab.add_theme_color_override("font_color", TEAL_ACCENT)
	row.add_child(lab)
	return row


func _make_slider_row(setting_key: String, label_text: String, min_v: float, max_v: float, step_v: float) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lab: Label = Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(210, 0)
	lab.add_theme_font_size_override("font_size", 15)
	lab.add_theme_color_override("font_color", TEAL_TEXT)
	row.add_child(lab)
	var slider: HSlider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grab_area: StyleBoxFlat = StyleBoxFlat.new()
	grab_area.bg_color = TEAL_BORDER
	grab_area.set_corner_radius_all(3)
	slider.add_theme_stylebox_override("grabber_area", grab_area)
	row.add_child(slider)
	var val: Label = Label.new()
	val.custom_minimum_size = Vector2(70, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 15)
	val.add_theme_color_override("font_color", TEAL_ACCENT)
	row.add_child(val)
	slider.value_changed.connect(func(_v: float) -> void:
		_refresh_value_labels()
		_apply_live(false)
	)
	match setting_key:
		"mouse_sensitivity":
			_sens_slider = slider
			_sens_val = val
		"fov":
			_fov_slider = slider
			_fov_val = val
		"master_volume":
			_vol_slider = slider
			_vol_val = val
		"music_volume":
			_music_slider = slider
			_music_val = val
		"sfx_volume":
			_sfx_slider = slider
			_sfx_val = val
		"dialogue_volume":
			_dlg_slider = slider
			_dlg_val = val
		"render_scale":
			_scale_slider = slider
			_scale_val = val
		"touch_sensitivity":
			_touch_slider = slider
			_touch_val = val
	return row


func _make_check_row(setting_key: String, label_text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var check: CheckBox = CheckBox.new()
	check.text = label_text
	check.add_theme_font_size_override("font_size", 15)
	check.add_theme_color_override("font_color", TEAL_TEXT)
	check.toggled.connect(func(_pressed: bool) -> void: _apply_live(false))
	row.add_child(check)
	match setting_key:
		"invert_y":
			_invert_check = check
		"sprint_toggle":
			_sprint_check = check
		"reduced_camera_bounce":
			_bounce_check = check
		"fullscreen":
			_fullscreen_check = check
		"vsync":
			_vsync_check = check
	return row
