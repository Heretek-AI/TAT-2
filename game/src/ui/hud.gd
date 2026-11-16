extends CanvasLayer
## Authentic in-game HUD: compass ribbon, portrait frame, stealth ball, hotbar,
## diegetic center prompt with keycap badge, and Art Nouveau pause menu.

const SettingsUIScript := preload("res://src/ui/settings_ui.gd")
const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")

const VERSION_STRING: String = "v1.5.148559"

var obj_lbl: Label
var compass_lbl: Label
var ribbon_clip: Control
var ribbon_lbl: Label
var interact_lbl: Label
var stealth_gem: TextureRect
var hp_fill: ColorRect
var stam_fill: ColorRect
var hotbar_lbl: Label
var slot_count_lbls: Array[Label] = []
var disguise_vignette: TextureRect
var thief_vision_overlay: ColorRect
var clue_toast_lbl: Label
var downed_lbl: Label
var lockpick_bar: ProgressBar
var pause_center: CenterContainer
var pause_panel: PanelContainer
var result_panel: PanelContainer
var result_lbl: Label
var contract_data: Dictionary = {}
var current_prompt: String = ""

var _pause_root: Control
var _prompt_keycap: PanelContainer
var _prompt_keycap_lbl: Label
var _thief_name_lbl: Label
var _level_badge_lbl: Label
var fps_overlay: Label
var fps_overlay_enabled: bool = false
var _fps_refresh: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var sans: Font = ResourceLoader.load("res://assets/ue/fonts/Raleway-Regular.ttf") as Font

	# Disguise vignette (full-screen overlay, hidden unless disguised).
	disguise_vignette = _tex_rect_full("res://assets/ue/Raw/Art/UI/HUD/T_Disguise_Vignette02.png")
	if disguise_vignette != null:
		disguise_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disguise_vignette.visible = false
		root.add_child(disguise_vignette)

	# Thief Vision indigo/teal screen-space tint
	thief_vision_overlay = ColorRect.new()
	thief_vision_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	thief_vision_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thief_vision_overlay.color = Color(0.08, 0.24, 0.36, 0.24)
	thief_vision_overlay.visible = false
	root.add_child(thief_vision_overlay)

	# Clue toast label (top-center below compass)
	clue_toast_lbl = Label.new()
	clue_toast_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	clue_toast_lbl.position = Vector2(-280, 56)
	clue_toast_lbl.custom_minimum_size = Vector2(560, 44)
	clue_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clue_toast_lbl.add_theme_font_size_override("font_size", 15)
	clue_toast_lbl.add_theme_color_override("font_color", Color(0.65, 0.92, 1.0))
	clue_toast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clue_toast_lbl.visible = false
	root.add_child(clue_toast_lbl)

	# Downed countdown label (center, below the clue toast; driven by
	# set_downed_display and the per-frame player poll in _process).
	downed_lbl = Label.new()
	downed_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	downed_lbl.position = Vector2(-280, 104)
	downed_lbl.custom_minimum_size = Vector2(560, 44)
	downed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	downed_lbl.add_theme_font_size_override("font_size", 26)
	downed_lbl.add_theme_color_override("font_color", Color(1.0, 0.32, 0.28))
	downed_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	downed_lbl.add_theme_constant_override("shadow_offset_x", 2)
	downed_lbl.add_theme_constant_override("shadow_offset_y", 2)
	downed_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	downed_lbl.visible = false
	root.add_child(downed_lbl)

	# Lockpick progress bar (center below reticle)
	lockpick_bar = ProgressBar.new()
	lockpick_bar.set_anchors_preset(Control.PRESET_CENTER)
	lockpick_bar.position = Vector2(-90, 56)
	lockpick_bar.custom_minimum_size = Vector2(180, 12)
	lockpick_bar.max_value = 1.0
	lockpick_bar.show_percentage = false
	lockpick_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lockpick_bar.visible = false
	root.add_child(lockpick_bar)

	_build_compass_strip(root, sans)
	_build_thief_plate(root, sans)
	_build_objective(root, sans)
	_build_reticle_and_prompt(root, sans)
	_build_bottom_left(root)
	_build_fps_overlay(root, sans)

	hotbar_lbl = Label.new()
	hotbar_lbl.visible = false
	root.add_child(hotbar_lbl)

	var is_hub: bool = GameState.active_contract_order <= 1
	if not is_hub and not MobileProfile.is_mobile():
		_build_tool_hotbar(root, sans)
	_build_result_panel(root)
	_build_pause_menu(root)


func _build_compass_strip(root: Control, sans: Font) -> void:
	# Slim top-center compass strip with cardinal markers.
	var compass_box: Control = Control.new()
	compass_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass_box.position = Vector2(-220, 10)
	compass_box.custom_minimum_size = Vector2(440, 28)
	compass_box.size = Vector2(440, 28)
	compass_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(compass_box)

	var c_bg: TextureRect = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/T_compass_bg.png", Vector2(440, 28))
	if c_bg != null:
		c_bg.modulate = Color(1, 1, 1, 0.72)
		compass_box.add_child(c_bg)
	var c_lines: TextureRect = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/T_compass_lines.png", Vector2(440, 24))
	if c_lines != null:
		c_lines.modulate = Color(1, 1, 1, 0.75)
		compass_box.add_child(c_lines)

	# Scrolling compass ribbon: clipped strip with a wide cardinal label.
	ribbon_clip = Control.new()
	ribbon_clip.position = Vector2(30, 2)
	ribbon_clip.custom_minimum_size = Vector2(380, 24)
	ribbon_clip.size = Vector2(380, 24)
	ribbon_clip.clip_contents = true
	ribbon_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_box.add_child(ribbon_clip)

	ribbon_lbl = Label.new()
	ribbon_lbl.text = "W   ·   NW   ·   N   ·   NE   ·   E   ·   SE   ·   S   ·   SW   ·   W   ·   NW   ·   N   ·   NE   ·   E"
	ribbon_lbl.position = Vector2(0, 0)
	ribbon_lbl.custom_minimum_size = Vector2(1400, 24)
	ribbon_lbl.size = Vector2(1400, 24)
	ribbon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ribbon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ribbon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon_lbl.add_theme_font_size_override("font_size", 13)
	ribbon_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	if sans != null:
		ribbon_lbl.add_theme_font_override("font", sans)
	ribbon_clip.add_child(ribbon_lbl)

	compass_lbl = Label.new()
	compass_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	compass_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	compass_lbl.add_theme_font_size_override("font_size", 13)
	compass_lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	compass_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	compass_lbl.add_theme_constant_override("shadow_offset_x", 1)
	compass_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if sans != null:
		compass_lbl.add_theme_font_override("font", sans)
	compass_box.add_child(compass_lbl)


func _build_thief_plate(root: Control, sans: Font) -> void:
	# Top-right thief name + portrait box + level badge.
	var port_anchor: Control = Control.new()
	port_anchor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	port_anchor.position = Vector2(-118, 16)
	port_anchor.custom_minimum_size = Vector2(96, 96)
	root.add_child(port_anchor)

	var p_bg: TextureRect = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/portrait/T_portrait_frameBg.png", Vector2(84, 84))
	if p_bg != null:
		port_anchor.add_child(p_bg)

	var port_path: String = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_spider.png"
	if GameState.thief_id == "chameleon" or GameState.thief_id == "moth":
		port_path = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_chameleon.png"
	var p_img: TextureRect = _tex_rect(port_path, Vector2(76, 76))
	if p_img != null:
		p_img.position = Vector2(4, 4)
		if GameState.thief_id == "moth":
			p_img.modulate = Color(0.75, 0.65, 1.0)
		port_anchor.add_child(p_img)

	var p_frame: TextureRect = _tex_rect("res://assets/ue/Raw/Art/UI/Components/T_PortraitFrame_noPlayerColor.png", Vector2(84, 84))
	if p_frame != null:
		port_anchor.add_child(p_frame)

	_thief_name_lbl = Label.new()
	_thief_name_lbl.text = str(GameState.thief_id).capitalize()
	_thief_name_lbl.position = Vector2(-140, 6)
	_thief_name_lbl.custom_minimum_size = Vector2(130, 22)
	_thief_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_thief_name_lbl.add_theme_font_size_override("font_size", 15)
	_thief_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	if sans != null:
		_thief_name_lbl.add_theme_font_override("font", sans)
	port_anchor.add_child(_thief_name_lbl)

	var lvl: int = 1
	var saved_lvl: Variant = SaveSystem.data.get("level", 1)
	if saved_lvl is float or saved_lvl is int:
		lvl = int(saved_lvl)
	_level_badge_lbl = Label.new()
	_level_badge_lbl.text = "LV %d · %s" % [lvl, str(GameState.difficulty_label()).to_upper()]
	_level_badge_lbl.position = Vector2(-140, 86)
	_level_badge_lbl.custom_minimum_size = Vector2(130, 20)
	_level_badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level_badge_lbl.add_theme_font_size_override("font_size", 12)
	_level_badge_lbl.add_theme_color_override("font_color", Color(0.55, 0.92, 0.95))
	if sans != null:
		_level_badge_lbl.add_theme_font_override("font", sans)
	port_anchor.add_child(_level_badge_lbl)


func _build_objective(root: Control, sans: Font) -> void:
	obj_lbl = Label.new()
	obj_lbl.position = Vector2(24, 18)
	obj_lbl.add_theme_font_size_override("font_size", 15)
	obj_lbl.add_theme_color_override("font_color", Color(0.88, 0.84, 0.74, 0.9))
	if sans != null:
		obj_lbl.add_theme_font_override("font", sans)
	root.add_child(obj_lbl)


func _build_reticle_and_prompt(root: Control, sans: Font) -> void:
	var ret_tex: Texture2D = ResourceLoader.load("res://assets/ue/Raw/Art/UI/HUD/Reticles/T_Reticles_Main.png") as Texture2D
	if ret_tex != null:
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = ret_tex
		atlas.region = Rect2(32, 0, 32, 32)
		var ret: TextureRect = TextureRect.new()
		ret.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ret.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ret.texture = atlas
		ret.set_anchors_preset(Control.PRESET_CENTER)
		ret.offset_left = -8
		ret.offset_top = -8
		ret.offset_right = 8
		ret.offset_bottom = 8
		ret.modulate = Color(1, 1, 1, 0.8)
		ret.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(ret)

	# Diegetic center prompt: keycap badge [F]/[E] + uppercase teal/blue label.
	var prompt_row: HBoxContainer = HBoxContainer.new()
	prompt_row.set_anchors_preset(Control.PRESET_CENTER)
	prompt_row.position = Vector2(-180, 26)
	prompt_row.custom_minimum_size = Vector2(360, 30)
	prompt_row.size = Vector2(360, 30)
	prompt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_row.add_theme_constant_override("separation", 8)
	prompt_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_row)
	_prompt_keycap = ThemeScript.keycap("[F]", 14)
	_prompt_keycap.visible = false
	prompt_row.add_child(_prompt_keycap)
	_prompt_keycap_lbl = _prompt_keycap.get_child(0) as Label
	interact_lbl = Label.new()
	interact_lbl.custom_minimum_size = Vector2(300, 28)
	interact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	interact_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interact_lbl.add_theme_font_size_override("font_size", 15)
	interact_lbl.add_theme_color_override("font_color", Color(0.55, 0.92, 0.95))
	interact_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	interact_lbl.add_theme_constant_override("shadow_offset_x", 1)
	interact_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if sans != null:
		interact_lbl.add_theme_font_override("font", sans)
	prompt_row.add_child(interact_lbl)


func _build_bottom_left(root: Control) -> void:
	# Bottom-left Stealth Ball (Light Gem) + Slim Health/Stamina (hidden in peaceful Thieves' Den hub)
	var is_hub: bool = GameState.active_contract_order <= 1
	var bl: Control = Control.new()
	if MobileProfile.is_mobile():
		# Bottom-left belongs to the virtual move stick on touch; move the meters up.
		bl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		bl.position = Vector2(24, 94)
	else:
		bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		bl.position = Vector2(24, -76)
	bl.visible = not is_hub
	root.add_child(bl)

	stealth_gem = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/Stealth_Ball/T_stealthball_frame.png", Vector2(56, 56))
	if stealth_gem != null:
		bl.add_child(stealth_gem)

	var hp_bg: ColorRect = ColorRect.new()
	hp_bg.position = Vector2(68, 16)
	hp_bg.size = Vector2(140, 8)
	hp_bg.color = Color(0.1, 0.1, 0.12, 0.75)
	bl.add_child(hp_bg)
	hp_fill = ColorRect.new()
	hp_fill.position = Vector2(68, 16)
	hp_fill.size = Vector2(140, 8)
	hp_fill.color = Color(0.76, 0.22, 0.22, 0.9)
	bl.add_child(hp_fill)

	var st_bg: ColorRect = ColorRect.new()
	st_bg.position = Vector2(68, 30)
	st_bg.size = Vector2(140, 6)
	st_bg.color = Color(0.1, 0.1, 0.12, 0.75)
	bl.add_child(st_bg)
	stam_fill = ColorRect.new()
	stam_fill.position = Vector2(68, 30)
	stam_fill.size = Vector2(140, 6)
	stam_fill.color = Color(0.32, 0.72, 0.88, 0.9)
	bl.add_child(stam_fill)


func _build_fps_overlay(root: Control, sans: Font) -> void:
	# F3 debug overlay: FPS, frame time, draw calls, visible objects and VRAM.
	fps_overlay = Label.new()
	fps_overlay.position = Vector2(24, 78)
	fps_overlay.custom_minimum_size = Vector2(620, 44)
	fps_overlay.add_theme_font_size_override("font_size", 13)
	fps_overlay.add_theme_color_override("font_color", Color(0.62, 1.0, 0.72))
	fps_overlay.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	fps_overlay.add_theme_constant_override("shadow_offset_x", 1)
	fps_overlay.add_theme_constant_override("shadow_offset_y", 1)
	if sans != null:
		fps_overlay.add_theme_font_override("font", sans)
	fps_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_overlay.visible = false
	root.add_child(fps_overlay)


func is_fps_overlay_visible() -> bool:
	return fps_overlay_enabled


func toggle_fps_overlay() -> void:
	fps_overlay_enabled = not fps_overlay_enabled
	_fps_refresh = 0.0
	if fps_overlay != null:
		fps_overlay.visible = fps_overlay_enabled
		if fps_overlay_enabled:
			_update_fps_overlay()
	print("TAT-2 perf overlay ", "ON" if fps_overlay_enabled else "OFF")


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_F3 or key_event.physical_keycode == KEY_F3:
				toggle_fps_overlay()
				get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_set_paused(not get_tree().paused)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if MobileProfile.is_mobile() and GameState.state == "playing" and not get_tree().paused:
			_set_paused(true)


func _update_fps_overlay() -> void:
	if fps_overlay == null:
		return
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = 1000.0 / maxf(fps, 1.0)
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var pos_txt: String = "-"
	var p: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		pos_txt = "%.1f, %.1f, %.1f" % [p.global_position.x, p.global_position.y, p.global_position.z]
	fps_overlay.text = "FPS %d | %.1f ms | draws %d | objs %d | prims %d\nnodes %d | VRAM %.0f MB | pos %s | %s" % [
		int(round(fps)), frame_ms, draw_calls, objects, primitives, nodes, vram_mb, pos_txt,
		str(contract_data.get("title", "Contract #%d" % GameState.active_contract_order)),
	]


func _tex_rect(path: String, min_sz: Vector2) -> TextureRect:
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	if tex == null:
		return null
	var tr: TextureRect = TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = tex
	tr.custom_minimum_size = min_sz
	tr.offset_right = min_sz.x
	tr.offset_bottom = min_sz.y
	tr.size = min_sz
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _tex_rect_full(path: String) -> TextureRect:
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	if tex == null:
		return null
	var tr: TextureRect = TextureRect.new()
	tr.texture = tex
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _build_tool_hotbar(root: Control, sans: Font) -> void:
	slot_count_lbls.clear()
	var anchor: Control = Control.new()
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	anchor.position = Vector2(-320, -140)
	anchor.custom_minimum_size = Vector2(296, 68)
	anchor.size = Vector2(296, 68)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(anchor)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.position = Vector2(0, 0)
	hb.custom_minimum_size = Vector2(296, 68)
	hb.size = Vector2(296, 68)
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(hb)
	var keys: Array[String] = ["1", "2", "3", "G"]
	var names: Array[String] = ["Sap", "Smoke", "Fairy", "Ability"]
	var icons: Array[String] = [
		"res://assets/ue/Raw/Art/UI/Icons/Icon_Ability_Lockpick.png",
		"res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_Bomb_Smoke_Wide.png",
		"res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_PickpocketFairy_Wide.png",
		"res://assets/ue/Raw/Art/UI/Rewards/Gear/T_Zipwire_Wide.png",
	]
	# Fall back to the pre-existing icon path if the alternate one is missing.
	icons[3] = "res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_Zipwire_Wide.png"
	for i: int in range(4):
		var slot: Control = Control.new()
		slot.custom_minimum_size = Vector2(68, 68)
		slot.size = Vector2(68, 68)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(slot)
		# Slot background: dark translucent rounded panel with a thin gold
		# border. The old T_Ability_Background / T_Ability_Border textures are
		# opaque and covered the tool icons, rendering blank slots.
		var bg: Panel = Panel.new()
		bg.position = Vector2(0, 0)
		bg.custom_minimum_size = Vector2(68, 68)
		bg.size = Vector2(68, 68)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg_style: StyleBoxFlat = ThemeScript.panel_style(1, 10, Color(0.04, 0.06, 0.09, 0.55))
		bg_style.border_color = Color(0.9, 0.78, 0.45, 0.5)
		bg.add_theme_stylebox_override("panel", bg_style)
		slot.add_child(bg)
		var icon_tex: Texture2D = ResourceLoader.load(icons[i]) as Texture2D
		if icon_tex != null:
			var icon: TextureRect = TextureRect.new()
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = icon_tex
			icon.custom_minimum_size = Vector2(44, 44)
			icon.offset_right = 44.0
			icon.offset_bottom = 44.0
			icon.size = Vector2(44, 44)
			icon.position = Vector2(12, 12)
			icon.modulate = Color(1, 1, 1, 1)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(icon)
		var key_lbl: Label = Label.new()
		key_lbl.text = "[%s] %s" % [keys[i], names[i]]
		key_lbl.position = Vector2(4, 2)
		key_lbl.custom_minimum_size = Vector2(64, 16)
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		key_lbl.add_theme_font_size_override("font_size", 11)
		key_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if sans != null:
			key_lbl.add_theme_font_override("font", sans)
		slot.add_child(key_lbl)
		var count_lbl: Label = Label.new()
		count_lbl.text = "0"
		count_lbl.position = Vector2(38, 46)
		count_lbl.custom_minimum_size = Vector2(28, 20)
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_lbl.add_theme_font_size_override("font_size", 14)
		count_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		count_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		count_lbl.add_theme_constant_override("shadow_offset_x", 1)
		count_lbl.add_theme_constant_override("shadow_offset_y", 1)
		count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if sans != null:
			count_lbl.add_theme_font_override("font", sans)
		slot.add_child(count_lbl)
		slot_count_lbls.append(count_lbl)


func _build_result_panel(root: Control) -> void:
	var cc: CenterContainer = CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	result_panel = PanelContainer.new()
	result_panel.visible = false
	cc.add_child(result_panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.custom_minimum_size = Vector2(520, 0)
	result_panel.add_child(vb)
	result_lbl = Label.new()
	result_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_lbl.add_theme_font_size_override("font_size", 20)
	vb.add_child(result_lbl)
	var btn: Button = Button.new()
	btn.text = "Return to Main Menu"
	btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	vb.add_child(btn)


func _build_pause_menu(root: Control) -> void:
	_pause_root = Control.new()
	_pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.visible = false
	root.add_child(_pause_root)
	# Blurred/dimmed full-screen backdrop (dim + teal vignette tint).
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.004, 0.006, 0.014, 0.72)
	_pause_root.add_child(dim)
	var tint: ColorRect = ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.10, 0.28, 0.30, 0.12)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_root.add_child(tint)

	pause_center = CenterContainer.new()
	pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.add_child(pause_center)
	pause_panel = PanelContainer.new()
	pause_panel.custom_minimum_size = Vector2(420, 0)
	pause_panel.add_theme_stylebox_override("panel", ThemeScript.panel_style())
	pause_center.add_child(pause_panel)
	ThemeScript.add_filigree(pause_panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	pause_panel.add_child(margin)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.custom_minimum_size = Vector2(360, 0)
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	var title: Label = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.45))
	vb.add_child(title)
	vb.add_child(ThemeScript.divider())
	var resume_btn: Button = Button.new()
	resume_btn.text = "RESUME"
	ThemeScript.style_button(resume_btn, true)
	resume_btn.pressed.connect(func() -> void: _set_paused(false))
	vb.add_child(resume_btn)
	var settings_btn: Button = Button.new()
	settings_btn.text = "SETTINGS"
	ThemeScript.style_button(settings_btn, false)
	settings_btn.pressed.connect(func() -> void:
		var sui: CanvasLayer = SettingsUIScript.new()
		add_child(sui)
		if sui.has_method("open_settings"):
			sui.call("open_settings")
	)
	vb.add_child(settings_btn)
	var menu_btn: Button = Button.new()
	menu_btn.text = "RETURN TO MAIN MENU"
	ThemeScript.style_button(menu_btn, false)
	menu_btn.pressed.connect(func() -> void:
		_set_paused(false)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vb.add_child(menu_btn)
	var quit_btn: Button = Button.new()
	quit_btn.text = "QUIT TO DESKTOP"
	ThemeScript.style_button(quit_btn, false)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(quit_btn)
	var esc_row: HBoxContainer = HBoxContainer.new()
	esc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	esc_row.add_theme_constant_override("separation", 6)
	esc_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(esc_row)
	var esc_badge: PanelContainer = ThemeScript.keycap("[ESC]", 12)
	esc_row.add_child(esc_badge)
	var esc_lbl: Label = Label.new()
	esc_lbl.text = "RESUME"
	esc_lbl.add_theme_font_size_override("font_size", 12)
	esc_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.78))
	esc_row.add_child(esc_lbl)
	# Bottom-left version string.
	var ver: Label = Label.new()
	ver.text = VERSION_STRING
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(16, -30)
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color(0.55, 0.60, 0.65, 0.85))
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_root.add_child(ver)


func toggle_pause() -> void:
	_toggle_pause()


func _toggle_pause() -> void:
	_set_paused(not get_tree().paused)


func _set_paused(value: bool) -> void:
	get_tree().paused = value
	var touch_ui: Node = get_tree().get_first_node_in_group("mobile_touch_ui")
	if touch_ui != null and touch_ui.has_method("clear_input"):
		touch_ui.call("clear_input")
	if _pause_root != null:
		_pause_root.visible = value
	if pause_center != null and _pause_root == null:
		pause_center.visible = value
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_contract_info(info: Dictionary) -> void:
	contract_data = info


func update_loot(collected: int, needed: int, value: int) -> void:
	if obj_lbl == null:
		return
	var title: String = str(contract_data.get("title", "Contract"))
	obj_lbl.text = "%s\n%d / %d LOOT (%dg)" % [title, collected, needed, value]


func set_steal_prompt(text: String) -> void:
	_set_prompt(text)


func show_toast(text: String) -> void:
	show_clue_toast("NOTICE", text)


func _set_prompt(raw: String) -> void:
	if interact_lbl == null:
		return
	var txt: String = raw.strip_edges()
	current_prompt = txt
	if txt == "":
		interact_lbl.text = ""
		if _prompt_keycap != null:
			_prompt_keycap.visible = false
		return
	var key: String = ""
	var rest: String = txt
	if txt.begins_with("["):
		var end: int = txt.find("]")
		if end > 1:
			key = txt.substr(1, end - 1).strip_edges()
			rest = txt.substr(end + 1).strip_edges()
	if key != "" and _prompt_keycap != null and _prompt_keycap_lbl != null:
		_prompt_keycap_lbl.text = "[" + key.to_upper() + "]"
		_prompt_keycap.visible = true
	elif _prompt_keycap != null:
		_prompt_keycap.visible = false
	# Touch builds show the verb next to the on-screen USE button instead.
	interact_lbl.text = rest.to_upper()
	if MobileProfile.is_mobile():
		if _prompt_keycap != null:
			_prompt_keycap.visible = false
		interact_lbl.visible = false


func _process(delta: float) -> void:
	if fps_overlay_enabled:
		_fps_refresh += delta
		if _fps_refresh >= 0.25:
			_fps_refresh = 0.0
			_update_fps_overlay()
	if InputMap.has_action("pause") and Input.is_action_just_pressed("pause"):
		_toggle_pause()
	if get_tree().paused:
		return
	if GameState.state != "playing":
		return
	var title: String = str(contract_data.get("title", "Contract #%d" % GameState.active_contract_order))
	var item: String = str(contract_data.get("quest_item", "Objective"))
	var status: String = "Reach Escape Gate" if GameState.quest_item_acquired else "%s  (%d/%d Loot | %dg)" % [item, GameState.loot_collected, GameState.loot_needed, GameState.loot_value]
	var timing: String = ""
	if GameState.run_time_limit > 0.0:
		var remain: float = maxf(0.0, GameState.run_time_limit - GameState.elapsed_sec)
		timing = "  |  %02d:%02d LEFT" % [int(remain) / 60, int(remain) % 60]
	obj_lbl.text = "%s\n%s%s" % [title, status, timing]

	if _thief_name_lbl != null:
		_thief_name_lbl.text = str(GameState.thief_id).capitalize()

	if stealth_gem != null:
		var vis: float = clampf(GameState.player_light_visibility, 0.0, 1.0)
		stealth_gem.modulate = Color(0.22, 0.32, 0.48).lerp(Color(1.0, 0.86, 0.35), vis)

	var p: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		var deg: float = fposmod(-p.rotation_degrees.y, 360.0)
		var dirs: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
		compass_lbl.text = dirs[int(round(deg / 45.0)) % 8]
		if ribbon_lbl != null and ribbon_clip != null:
			var frac: float = deg / 360.0
			var max_scroll: float = maxf(0.0, ribbon_lbl.size.x - ribbon_clip.size.x)
			ribbon_lbl.position.x = -frac * max_scroll
		var mhp: float = maxf(1.0, float(p.get("max_health")))
		var mst: float = maxf(1.0, float(p.get("max_stamina")))
		hp_fill.size.x = 140.0 * clampf(float(p.get("health")) / mhp, 0.0, 1.0)
		stam_fill.size.x = 140.0 * clampf(float(p.get("stamina")) / mst, 0.0, 1.0)
		var ch: Dictionary = p.get("charges")
		var ab: String = "Grapple" if GameState.thief_id == "spider" else ("Disguise" if GameState.thief_id == "chameleon" else "Scout")
		hotbar_lbl.text = "[1]Sap:%d  [2]Smoke:%d  [3]Fairy:%d  [G]%s  |  BOTTLES:%d" % [
			int(ch.get("slithersap", 0)), int(ch.get("smoke_bomb", 0)), int(ch.get("pickpocket_fairy", 0)), ab,
			int(ch.get("bottle", 0))
		]
		if slot_count_lbls.size() >= 4:
			slot_count_lbls[0].text = str(int(ch.get("slithersap", 0)))
			slot_count_lbls[1].text = str(int(ch.get("smoke_bomb", 0)))
			slot_count_lbls[2].text = str(int(ch.get("pickpocket_fairy", 0)))
			if ch.has("ability"):
				slot_count_lbls[3].text = str(int(ch.get("ability", 0)))
			elif ch.has("grapple"):
				slot_count_lbls[3].text = str(int(ch.get("grapple", 0)))
			else:
				slot_count_lbls[3].text = "∞"
		if disguise_vignette != null:
			disguise_vignette.visible = bool(p.get("disguise_active")) == true
		if p.has_method("downed_remaining") and downed_lbl != null:
			# DOWNED — Ns countdown while the player bleeds out; hidden otherwise.
			var downed_now: bool = bool(p.get("is_downed"))
			set_downed_display(downed_now, float(p.call("downed_remaining")))
		if p.has_method("get_look_interact_prompt"):
			_set_prompt(str(p.call("get_look_interact_prompt")))


func show_result(won: bool, score: int, info: Dictionary) -> void:
	set_downed_display(false, 0.0)
	result_panel.visible = true
	var rating: String = "GHOST (+25%)" if not GameState.ever_spotted else ("SHADOW (+10%)" if not GameState.ever_chased else "BRAWLER")
	var outro: String = str(info.get("outro", ""))
	if outro.length() > 260:
		outro = outro.substr(0, 260) + "..."
	var timed_out: bool = bool(info.get("timed_out", false))
	if not timed_out and not won and GameState.run_time_limit > 0.0 and GameState.elapsed_sec >= GameState.run_time_limit:
		timed_out = true
	var timeout_note: String = ""
	if timed_out and not won:
		var reason: String = str(info.get("timeout_reason", "TIME EXPIRED"))
		if reason == "":
			reason = "TIME EXPIRED"
		timeout_note = "\n\nTime expired — the match window closed before you escaped. (%s)" % reason
	result_lbl.text = "%s\n\nScore: %dg | Stealth Rating: %s\nTime: %.1fs | Takedowns: %d\n\n%s%s" % [
		"CONTRACT COMPLETE" if won else "CAPTURED BY THE CONSTABULARY",
		score, rating, GameState.elapsed_sec, GameState.takedowns, outro, timeout_note
	]


func set_thief_vision(enabled: bool) -> void:
	if thief_vision_overlay != null:
		thief_vision_overlay.visible = enabled


## DOWNED — Ns bleed-out countdown. Called by the mission controller on
## downed_started and refreshed every frame from downed_remaining().
func set_downed_display(active: bool, seconds: float) -> void:
	if downed_lbl == null:
		return
	downed_lbl.visible = active
	if active:
		downed_lbl.text = "DOWNED — %ds" % maxi(0, int(ceil(seconds)))


func show_clue_toast(title: String, body: String) -> void:
	if clue_toast_lbl == null:
		return
	var snippet: String = body if body.length() <= 110 else body.substr(0, 110) + "..."
	clue_toast_lbl.text = "CLUE — %s: %s" % [title, snippet]
	clue_toast_lbl.visible = true
	get_tree().create_timer(5.5).timeout.connect(func() -> void:
		if is_instance_valid(clue_toast_lbl):
			clue_toast_lbl.visible = false
	)


func set_lockpick_progress(active: bool, progress: float, _lock_level: int) -> void:
	if lockpick_bar == null:
		return
	lockpick_bar.visible = active
	lockpick_bar.value = clampf(progress, 0.0, 1.0)
