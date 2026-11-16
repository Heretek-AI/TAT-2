extends Control
## Main Menu: 3D BeautifulCorner Startscreen backdrop (MacNeish Jeweller) + Title overlay + Contract Journal.

const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const SettingsUIScript := preload("res://src/ui/settings_ui.gd")

var thief_opt: OptionButton
var diff_opt: OptionButton
var contract_list: ItemList
var detail_lbl: Label
var portrait_rect: TextureRect
var net_status: Label
var ip_edit: LineEdit
var journal_panel: PanelContainer
var _menu_cam: Camera3D
var _shop_glow: OmniLight3D
var _sway_t: float = 0.0
var selected_order: int = 1


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_3d_backdrop()
	_build_ui()


func _build_3d_backdrop() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	add_child(svc)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.scaling_3d_scale = 0.75
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)

	var scene_root := Node3D.new()
	vp.add_child(scene_root)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.025, 0.02, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.18, 0.14, 0.28)
	e.ambient_light_energy = 0.42
	e.fog_enabled = true
	e.fog_light_color = Color(0.14, 0.07, 0.22)
	e.fog_density = 0.014
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	scene_root.add_child(env)

	_menu_cam = Camera3D.new()
	_menu_cam.fov = 46.0
	_menu_cam.position = Vector3(-9.2, 8.1, 11.8)
	_menu_cam.current = true
	scene_root.add_child(_menu_cam)
	_menu_cam.look_at(Vector3(-0.6, 8.7, 0.4), Vector3.UP)

	# Warm magenta/amber storefront glow matching MacNeish Jeweller
	_shop_glow = OmniLight3D.new()
	_shop_glow.position = Vector3(-1.2, 8.8, 2.2)
	_shop_glow.light_color = Color(1.0, 0.28, 0.72)
	_shop_glow.light_energy = 3.2
	_shop_glow.omni_range = 14.0
	scene_root.add_child(_shop_glow)

	var street_lamp := SpotLight3D.new()
	street_lamp.position = Vector3(-4.5, 13.0, 6.0)
	street_lamp.light_color = Color(1.0, 0.72, 0.35)
	street_lamp.light_energy = 2.6
	street_lamp.spot_range = 18.0
	street_lamp.spot_angle = 55.0
	scene_root.add_child(street_lamp)
	street_lamp.look_at(Vector3(-1.0, 6.2, 1.5), Vector3.UP)

	var loader := LevelLoaderScript.new()
	var sublevels: Array[String] = [
		"res://data/generated/levels/Menus/MainMenu/BeautifulCorner_Startscreen_P.tatlevel.json",
		"res://data/generated/levels/Menus/MainMenu/BeautifulCorner_Startscreen_Lighting.tatlevel.json",
	]
	loader.load_sublevels(sublevels, scene_root, null, 16, false)


func _process(delta: float) -> void:
	_sway_t += delta
	if _menu_cam != null:
		_menu_cam.position = Vector3(-9.2 + sin(_sway_t * 0.35) * 0.22, 8.1 + cos(_sway_t * 0.25) * 0.1, 11.8)
		_menu_cam.look_at(Vector3(-0.6, 8.7, 0.4), Vector3.UP)
	if _shop_glow != null:
		_shop_glow.light_energy = 3.1 + sin(_sway_t * 7.5) * 0.18 + cos(_sway_t * 17.0) * 0.08


func _make_menu_btn(text: String, font: Font) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.78, 0.38))
	if font != null:
		b.add_theme_font_override("font", font)
	return b


func _build_ui() -> void:
	var sans := ResourceLoader.load("res://assets/ue/fonts/Raleway-Regular.ttf") as Font
	var serif := ResourceLoader.load("res://assets/ue/fonts/SourceSerifPro-Bold.ttf") as Font

	# Right-aligned title & clean vertical menu matching shipped startscreen
	var right_anchor := Control.new()
	right_anchor.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_anchor.offset_left = -460
	right_anchor.offset_right = -64
	add_child(right_anchor)

	var menu_v := VBoxContainer.new()
	menu_v.set_anchors_preset(Control.PRESET_VCENTER_WIDE)
	menu_v.offset_top = -170
	menu_v.offset_bottom = 200
	menu_v.add_theme_constant_override("separation", 10)
	right_anchor.add_child(menu_v)

	var logo_tex := ResourceLoader.load("res://assets/ue/Raw/Art/UI/Branding/T_TaT_Logo_Primary_White.png") as Texture2D
	if logo_tex != null:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.custom_minimum_size = Vector2(360, 180)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		menu_v.add_child(logo)
	else:
		var title := Label.new()
		title.text = "THICK AS THIEVES"
		title.add_theme_font_size_override("font_size", 44)
		if serif != null:
			title.add_theme_font_override("font", serif)
		menu_v.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	menu_v.add_child(spacer)

	var play_btn := _make_menu_btn("PLAY", sans)
	play_btn.pressed.connect(func():
		selected_order = 1
		_launch()
	)
	menu_v.add_child(play_btn)

	var contracts_btn := _make_menu_btn("CONTRACTS & CO-OP", sans)
	contracts_btn.pressed.connect(func(): journal_panel.visible = not journal_panel.visible)
	menu_v.add_child(contracts_btn)

	var settings_btn := _make_menu_btn("SETTINGS", sans)
	settings_btn.pressed.connect(_on_settings_pressed)
	menu_v.add_child(settings_btn)

	var quit_btn := _make_menu_btn("QUIT", sans)
	quit_btn.pressed.connect(func(): get_tree().quit())
	menu_v.add_child(quit_btn)

	# Contract Journal drawer (hidden until "CONTRACTS & CO-OP" is clicked)
	journal_panel = PanelContainer.new()
	journal_panel.visible = false
	journal_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	journal_panel.offset_left = 48
	journal_panel.offset_top = 48
	journal_panel.offset_right = -48
	journal_panel.offset_bottom = -48
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.035, 0.06, 0.94)
	style.border_color = Color(0.55, 0.45, 0.25, 0.8)
	style.set_border_width_all(2)
	style.set_content_margin_all(24)
	journal_panel.add_theme_stylebox_override("panel", style)
	add_child(journal_panel)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 14)
	journal_panel.add_child(root_v)

	var hdr := HBoxContainer.new()
	root_v.add_child(hdr)
	var jtitle := Label.new()
	jtitle.text = "KILCAIRN CONTRACT JOURNAL"
	jtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jtitle.add_theme_font_size_override("font_size", 28)
	jtitle.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	if serif != null:
		jtitle.add_theme_font_override("font", serif)
	hdr.add_child(jtitle)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(func(): journal_panel.visible = false)
	hdr.add_child(close_btn)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	root_v.add_child(top_bar)

	thief_opt = OptionButton.new()
	thief_opt.add_item("The Spider (Grapple Wire)")
	thief_opt.add_item("The Chameleon (Disguise)")
	thief_opt.add_item("The Moth [TAT-2] (Astral Scout)")
	thief_opt.item_selected.connect(_on_thief_selected)
	top_bar.add_child(thief_opt)

	diff_opt = OptionButton.new()
	diff_opt.add_item("Novice")
	diff_opt.add_item("Thief")
	diff_opt.add_item("Master Thief")
	top_bar.add_child(diff_opt)

	var host_btn := Button.new()
	host_btn.text = "Host Co-op (7742)"
	host_btn.pressed.connect(func():
		var err := NetManager.host()
		net_status.text = "Hosting on :7742" if err == OK else "Host failed: %d" % err
	)
	top_bar.add_child(host_btn)

	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(130, 0)
	top_bar.add_child(ip_edit)

	var join_btn := Button.new()
	join_btn.text = "Join Co-op"
	join_btn.pressed.connect(func():
		var err := NetManager.join(ip_edit.text)
		net_status.text = "Connecting..." if err == OK else "Join failed: %d" % err
	)
	top_bar.add_child(join_btn)

	net_status = Label.new()
	net_status.text = "Solo Mode"
	top_bar.add_child(net_status)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 20)
	root_v.add_child(split)

	contract_list = ItemList.new()
	contract_list.custom_minimum_size = Vector2(420, 0)
	contract_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for c in GameData.contracts:
		var order := int(c["order"])
		var disp := GameData.get_contract_display(order)
		var tag: String = "[EXPANSION]" if order >= 17 else str(c["map_id"]).to_upper()
		contract_list.add_item("#%02d  %s  (%s)" % [order, disp.get("title", c["id"]), tag])
	contract_list.item_selected.connect(_on_contract_selected)
	split.add_child(contract_list)

	var right_v := VBoxContainer.new()
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.add_theme_constant_override("separation", 12)
	split.add_child(right_v)

	portrait_rect = TextureRect.new()
	portrait_rect.custom_minimum_size = Vector2(160, 160)
	portrait_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right_v.add_child(portrait_rect)
	_on_thief_selected(0)

	detail_lbl = Label.new()
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_lbl.add_theme_font_size_override("font_size", 18)
	if sans != null:
		detail_lbl.add_theme_font_override("font", sans)
	right_v.add_child(detail_lbl)

	var launch_btn := Button.new()
	launch_btn.text = "LAUNCH CONTRACT"
	launch_btn.custom_minimum_size = Vector2(0, 48)
	launch_btn.pressed.connect(_launch)
	right_v.add_child(launch_btn)

	if contract_list.item_count > 1:
		contract_list.select(1)
		_on_contract_selected(1)


func _on_settings_pressed() -> void:
	var ui := SettingsUIScript.new()
	add_child(ui)
	ui.open_settings()


func _on_thief_selected(idx: int) -> void:
	if portrait_rect == null:
		return
	var tex_path := "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_spider.png"
	portrait_rect.modulate = Color.WHITE
	if idx == 1:
		tex_path = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_chameleon.png"
	elif idx == 2:
		tex_path = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_chameleon.png"
		portrait_rect.modulate = Color(0.75, 0.65, 1.0)
	var tex := ResourceLoader.load(tex_path) as Texture2D
	if tex != null:
		portrait_rect.texture = tex


func _on_contract_selected(idx: int) -> void:
	if idx < 0 or idx >= GameData.contracts.size():
		return
	selected_order = int(GameData.contracts[idx]["order"])
	var d := GameData.get_contract_display(selected_order)
	var clues: Array = d.get("clue_facts", [])
	var clue_txt := "\n".join(clues.map(func(x): return "• " + str(x))) if not clues.is_empty() else "• Reconnoiter the landmark for clues."
	detail_lbl.text = "%s\nTarget: %s\nLocation: %s\n\n%s\n\nIntel:\n%s" % [
		d.get("title", ""), d.get("quest_item", ""), d.get("location", ""), d.get("description", ""), clue_txt
	]


func _launch() -> void:
	GameState.thief_id = ["spider", "chameleon", "moth"][thief_opt.selected]
	GameState.difficulty = diff_opt.selected + 1
	GameState.active_contract_order = selected_order
	get_tree().change_scene_to_file("res://scenes/mission.tscn")
