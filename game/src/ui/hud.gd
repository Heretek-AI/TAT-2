extends CanvasLayer
## Authentic in-game HUD using extracted Thick As Thieves UI textures (compass, portrait frame, stealth ball, reticle, hotbar).

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
var lockpick_bar: ProgressBar
var pause_center: CenterContainer
var pause_panel: PanelContainer
var result_panel: PanelContainer
var result_lbl: Label
var contract_data: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var sans := ResourceLoader.load("res://assets/ue/fonts/Raleway-Regular.ttf") as Font

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

	# Top-center Compass (T_compass_bg + T_compass_lines)
	var compass_box := Control.new()
	compass_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass_box.position = Vector2(-220, 12)
	compass_box.custom_minimum_size = Vector2(440, 34)
	compass_box.size = Vector2(440, 34)
	root.add_child(compass_box)

	var c_bg := _tex_rect("res://assets/ue/Raw/Art/UI/HUD/T_compass_bg.png", Vector2(440, 28))
	if c_bg != null:
		c_bg.modulate = Color(1, 1, 1, 0.72)
		compass_box.add_child(c_bg)
	var c_lines := _tex_rect("res://assets/ue/Raw/Art/UI/HUD/T_compass_lines.png", Vector2(440, 24))
	if c_lines != null:
		c_lines.modulate = Color(1, 1, 1, 0.75)
		compass_box.add_child(c_lines)

	# Scrolling compass ribbon: clipped strip with a wide cardinal label.
	ribbon_clip = Control.new()
	ribbon_clip.position = Vector2(30, 3)
	ribbon_clip.custom_minimum_size = Vector2(380, 28)
	ribbon_clip.size = Vector2(380, 28)
	ribbon_clip.clip_contents = true
	ribbon_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_box.add_child(ribbon_clip)

	ribbon_lbl = Label.new()
	ribbon_lbl.text = "W   ·   NW   ·   N   ·   NE   ·   E   ·   SE   ·   S   ·   SW   ·   W   ·   NW   ·   N   ·   NE   ·   E"
	ribbon_lbl.position = Vector2(0, 0)
	ribbon_lbl.custom_minimum_size = Vector2(1400, 28)
	ribbon_lbl.size = Vector2(1400, 28)
	ribbon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ribbon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ribbon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon_lbl.add_theme_font_size_override("font_size", 14)
	ribbon_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	if sans != null:
		ribbon_lbl.add_theme_font_override("font", sans)
	ribbon_clip.add_child(ribbon_lbl)

	compass_lbl = Label.new()
	compass_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	compass_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	compass_lbl.add_theme_font_size_override("font_size", 14)
	compass_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	if sans != null:
		compass_lbl.add_theme_font_override("font", sans)
	compass_box.add_child(compass_lbl)

	# Top-right Thief Portrait & Frame
	var port_anchor := Control.new()
	port_anchor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	port_anchor.position = Vector2(-118, 16)
	port_anchor.custom_minimum_size = Vector2(96, 96)
	root.add_child(port_anchor)

	var p_bg := _tex_rect("res://assets/ue/Raw/Art/UI/HUD/portrait/T_portrait_frameBg.png", Vector2(84, 84))
	if p_bg != null:
		port_anchor.add_child(p_bg)

	var port_path := "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_spider.png"
	if GameState.thief_id == "chameleon" or GameState.thief_id == "moth":
		port_path = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_chameleon.png"
	var p_img := _tex_rect(port_path, Vector2(76, 76))
	if p_img != null:
		p_img.position = Vector2(4, 4)
		if GameState.thief_id == "moth":
			p_img.modulate = Color(0.75, 0.65, 1.0)
		port_anchor.add_child(p_img)

	var p_frame := _tex_rect("res://assets/ue/Raw/Art/UI/Components/T_PortraitFrame_noPlayerColor.png", Vector2(84, 84))
	if p_frame != null:
		port_anchor.add_child(p_frame)

	var thief_lbl := Label.new()
	thief_lbl.text = GameState.thief_id.capitalize()
	thief_lbl.position = Vector2(-130, 28)
	thief_lbl.custom_minimum_size = Vector2(120, 24)
	thief_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	thief_lbl.add_theme_font_size_override("font_size", 15)
	thief_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.98))
	if sans != null:
		thief_lbl.add_theme_font_override("font", sans)
	port_anchor.add_child(thief_lbl)

	# Top-left Minimal Objective Header
	obj_lbl = Label.new()
	obj_lbl.position = Vector2(24, 18)
	obj_lbl.add_theme_font_size_override("font_size", 15)
	obj_lbl.add_theme_color_override("font_color", Color(0.88, 0.84, 0.74, 0.9))
	if sans != null:
		obj_lbl.add_theme_font_override("font", sans)
	root.add_child(obj_lbl)

	# Center Reticle (crop cell (1,0) white dot from 64x128 2x4 spritesheet) + Interact Prompt
	var ret_tex := ResourceLoader.load("res://assets/ue/Raw/Art/UI/HUD/Reticles/T_Reticles_Main.png") as Texture2D
	if ret_tex != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = ret_tex
		atlas.region = Rect2(32, 0, 32, 32)
		var ret := TextureRect.new()
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

	interact_lbl = Label.new()
	interact_lbl.set_anchors_preset(Control.PRESET_CENTER)
	interact_lbl.position = Vector2(-180, 26)
	interact_lbl.custom_minimum_size = Vector2(360, 28)
	interact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_lbl.add_theme_font_size_override("font_size", 15)
	interact_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	if sans != null:
		interact_lbl.add_theme_font_override("font", sans)
	root.add_child(interact_lbl)

	# Bottom-left Stealth Ball (Light Gem) + Slim Health/Stamina (hidden in peaceful Thieves' Den hub)
	var is_hub: bool = GameState.active_contract_order <= 1
	var bl := Control.new()
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position = Vector2(24, -76)
	bl.visible = not is_hub
	root.add_child(bl)

	stealth_gem = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/Stealth_Ball/T_stealthball_frame.png", Vector2(56, 56))
	if stealth_gem != null:
		bl.add_child(stealth_gem)

	var hp_bg := ColorRect.new()
	hp_bg.position = Vector2(68, 16)
	hp_bg.size = Vector2(140, 8)
	hp_bg.color = Color(0.1, 0.1, 0.12, 0.75)
	bl.add_child(hp_bg)
	hp_fill = ColorRect.new()
	hp_fill.position = Vector2(68, 16)
	hp_fill.size = Vector2(140, 8)
	hp_fill.color = Color(0.76, 0.22, 0.22, 0.9)
	bl.add_child(hp_fill)

	var st_bg := ColorRect.new()
	st_bg.position = Vector2(68, 30)
	st_bg.size = Vector2(140, 6)
	st_bg.color = Color(0.1, 0.1, 0.12, 0.75)
	bl.add_child(st_bg)
	stam_fill = ColorRect.new()
	stam_fill.position = Vector2(68, 30)
	stam_fill.size = Vector2(140, 6)
	stam_fill.color = Color(0.32, 0.72, 0.88, 0.9)
	bl.add_child(stam_fill)

	hotbar_lbl = Label.new()
	hotbar_lbl.visible = false
	root.add_child(hotbar_lbl)

	if not is_hub:
		_build_tool_hotbar(root, sans)
	_build_result_panel(root)
	_build_pause_menu(root)


func _tex_rect(path: String, min_sz: Vector2) -> TextureRect:
	var tex := ResourceLoader.load(path) as Texture2D
	if tex == null:
		return null
	var tr := TextureRect.new()
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
	var tex := ResourceLoader.load(path) as Texture2D
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.texture = tex
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _build_tool_hotbar(root: Control, sans: Font) -> void:
	slot_count_lbls.clear()
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	anchor.position = Vector2(-320, -140)
	anchor.custom_minimum_size = Vector2(296, 68)
	anchor.size = Vector2(296, 68)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(anchor)
	var hb := HBoxContainer.new()
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
		"res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_Zipwire_Wide.png",
	]
	for i: int in range(4):
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(68, 68)
		slot.size = Vector2(68, 68)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(slot)
		var bg := _tex_rect("res://assets/ue/Raw/Art/UI/HUD/T_Ability_Background.png", Vector2(68, 68))
		if bg != null:
			bg.position = Vector2(0, 0)
			slot.add_child(bg)
		var icon := _tex_rect(icons[i], Vector2(44, 44))
		if icon != null:
			icon.position = Vector2(12, 8)
			slot.add_child(icon)
		var border := _tex_rect("res://assets/ue/Raw/Art/UI/HUD/T_Ability_Border.png", Vector2(68, 68))
		if border != null:
			border.position = Vector2(0, 0)
			slot.add_child(border)
		var key_lbl := Label.new()
		key_lbl.text = "[%s] %s" % [keys[i], names[i]]
		key_lbl.position = Vector2(2, 0)
		key_lbl.custom_minimum_size = Vector2(64, 16)
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_lbl.add_theme_font_size_override("font_size", 11)
		key_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if sans != null:
			key_lbl.add_theme_font_override("font", sans)
		slot.add_child(key_lbl)
		var count_lbl := Label.new()
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
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	result_panel = PanelContainer.new()
	result_panel.visible = false
	cc.add_child(result_panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(520, 0)
	result_panel.add_child(vb)
	result_lbl = Label.new()
	result_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_lbl.add_theme_font_size_override("font_size", 20)
	vb.add_child(result_lbl)
	var btn := Button.new()
	btn.text = "Return to Main Menu"
	btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	vb.add_child(btn)


func _build_pause_menu(root: Control) -> void:
	pause_center = CenterContainer.new()
	pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_center.visible = false
	root.add_child(pause_center)
	pause_panel = PanelContainer.new()
	pause_center.add_child(pause_panel)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(360, 0)
	vb.add_theme_constant_override("separation", 10)
	pause_panel.add_child(vb)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vb.add_child(title)
	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.pressed.connect(func() -> void: _set_paused(false))
	vb.add_child(resume_btn)
	var restart_btn := Button.new()
	restart_btn.text = "Restart Contract"
	restart_btn.pressed.connect(func() -> void:
		_set_paused(false)
		get_tree().reload_current_scene()
	)
	vb.add_child(restart_btn)
	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.pressed.connect(func() -> void:
		_set_paused(false)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vb.add_child(menu_btn)


func _toggle_pause() -> void:
	_set_paused(not get_tree().paused)


func _set_paused(value: bool) -> void:
	get_tree().paused = value
	if pause_center != null:
		pause_center.visible = value
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_contract_info(info: Dictionary) -> void:
	contract_data = info


func _process(_delta: float) -> void:
	if InputMap.has_action("pause") and Input.is_action_just_pressed("pause"):
		_toggle_pause()
	if get_tree().paused:
		return
	if GameState.state != "playing":
		return
	var title: String = str(contract_data.get("title", "Contract #%d" % GameState.active_contract_order))
	var item: String = str(contract_data.get("quest_item", "Objective"))
	var status := "Reach Escape Gate" if GameState.quest_item_acquired else "%s  (%d/%d Loot | %dg)" % [item, GameState.loot_collected, GameState.loot_needed, GameState.loot_value]
	obj_lbl.text = "%s\n%s" % [title, status]

	if stealth_gem != null:
		var vis := clampf(GameState.player_light_visibility, 0.0, 1.0)
		stealth_gem.modulate = Color(0.22, 0.32, 0.48).lerp(Color(1.0, 0.86, 0.35), vis)

	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		var deg := fposmod(-p.rotation_degrees.y, 360.0)
		var dirs: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
		compass_lbl.text = dirs[int(round(deg / 45.0)) % 8]
		if ribbon_lbl != null and ribbon_clip != null:
			var frac: float = deg / 360.0
			var max_scroll: float = maxf(0.0, ribbon_lbl.size.x - ribbon_clip.size.x)
			ribbon_lbl.position.x = -frac * max_scroll
		var mhp := maxf(1.0, float(p.get("max_health")))
		var mst := maxf(1.0, float(p.get("max_stamina")))
		hp_fill.size.x = 140.0 * clampf(float(p.get("health")) / mhp, 0.0, 1.0)
		stam_fill.size.x = 140.0 * clampf(float(p.get("stamina")) / mst, 0.0, 1.0)
		var ch: Dictionary = p.get("charges")
		var ab := "Grapple" if GameState.thief_id == "spider" else ("Disguise" if GameState.thief_id == "chameleon" else "Scout")
		hotbar_lbl.text = "[1]Sap:%d  [2]Smoke:%d  [3]Fairy:%d  [G]%s" % [
			int(ch.get("slithersap", 0)), int(ch.get("smoke_bomb", 0)), int(ch.get("pickpocket_fairy", 0)), ab
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
		if p.has_method("get_look_interact_prompt"):
			interact_lbl.text = str(p.call("get_look_interact_prompt"))


func show_result(won: bool, score: int, info: Dictionary) -> void:
	result_panel.visible = true
	var rating := "GHOST (+25%)" if not GameState.ever_spotted else ("SHADOW (+10%)" if not GameState.ever_chased else "BRAWLER")
	var outro: String = str(info.get("outro", ""))
	if outro.length() > 260:
		outro = outro.substr(0, 260) + "..."
	result_lbl.text = "%s\n\nScore: %dg | Stealth Rating: %s\nTime: %.1fs | Takedowns: %d\n\n%s" % [
		"CONTRACT COMPLETE" if won else "CAPTURED BY THE CONSTABULARY",
		score, rating, GameState.elapsed_sec, GameState.takedowns, outro
	]


func set_thief_vision(enabled: bool) -> void:
	if thief_vision_overlay != null:
		thief_vision_overlay.visible = enabled


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
