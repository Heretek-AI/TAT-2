extends CanvasLayer
class_name WardrobeUI
## Wardrobe / Bureau Character Customizer for the Thieves' Den hub.
## Workstream 3: 3D full-body thief preview (SubViewport turntable with warm
## wardrobe lighting), Q/E thief switcher (Spider unlocked / Chameleon locked
## unless unlocked in SaveSystem), Edit Loadout 4-slot tool bar with large tool
## preview card, and Head / Body / Calling Card slots parsed from
## DT_CharacterOutfitsMetadata.json. Persists to GameState + SaveSystem.
##
## All mesh paths below were verified to exist on disk. No inferred types are
## used on Variant / Dictionary values anywhere in this file.

signal closed()

const ThemeScript: GDScript = preload("res://src/ui/art_nouveau_theme.gd")
const LevelLoaderScript: GDScript = preload("res://src/core/level_loader.gd")

const OUTFITS_JSON_PATH: String = "res://data/generated/tables/Character/Player/DT_CharacterOutfitsMetadata.json"

const BODY_BASE_PATH: String = "res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/SK_ThiefNisha__Body.glb"
const BODY_TARANTULA_PATH: String = "res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/Dyn/SK_ThiefNisha_Dyn__Body_Tarantula.glb"
const BODY_TARANTULA_B_PATH: String = "res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/Dyn/SK_ThiefNisha_Dyn__Body_Tarantula_PatternB.glb"
const HEAD_STATIC_PATH: String = "res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/SK_ThiefNisha__Head.glb"
const DYN_HEAD_DIR: String = "res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/Dyn/"

const CARD_SPIDER: String = "res://assets/ue/Content/Art/Gameplay/CallingCards/Spider/SM_CallingCard_Spider.glb"
const CARD_SPIDER_SILVER: String = "res://assets/ue/Content/Art/Gameplay/CallingCards/Spider/SM_CallingCard_Spider_Silver.glb"
const CARD_SPIDER_GOLD: String = "res://assets/ue/Content/Art/Gameplay/CallingCards/Spider/SM_CallingCard_Spider_Gold.glb"
const CARD_SPIDER_MAGIC: String = "res://assets/ue/Content/Art/Gameplay/CallingCards/Spider/SM_CallingCard_Spider_Magic.glb"
const CARD_SPIDER_SHIP: String = "res://assets/ue/Content/Art/Gameplay/CallingCards/Ship/SM_CallingCard_Ship_Spider.glb"
const CARD_CHAMELEON: String = "res://assets/ue/Content/Art/Gameplay/CallingCards/Chameleon/SM_CallingCard_Chameleon.glb"
const CARD_CHAMELEON_SILVER: String = "res://assets/ue/Content/Art/Gameplay/CallingCards/Chameleon/SM_CallingCard_Chameleon_Silver.glb"
const CARD_CHAMELEON_GOLD: String = "res://assets/ue/Content/Art/Gameplay/CallingCards/Chameleon/SM_CallingCard_Chameleon_Gold.glb"
const CARD_CHAMELEON_MAGIC: String = "res://assets/ue/Content/Art/Gameplay/CallingCards/Chameleon/SM_CallingCard_Chameleon_Magic.glb"
const CARD_CHAMELEON_SHIP: String = "res://assets/ue/Content/Art/Gameplay/CallingCards/Ship/SM_CallingCard_Ship_Chameleon.glb"

const TOOL_ZIPWIRE_MESH: String = "res://assets/ue/Content/Art/Gameplay/Gear/Zipwire/SM_Zipwire.glb"
const TOOL_SMOKE_MESH: String = "res://assets/ue/Content/Art/Gameplay/Gear/SmokeBomb/SK_SmokeBomb.glb"
const TOOL_BLACKJACK_MESH: String = "res://assets/ue/Content/Art/Gameplay/Gear/BlackJack/SM_Blackjack.glb"
const TOOL_SLITHERSAP_MESH: String = "res://assets/ue/Content/Art/Gameplay/Gear/Slithersap/SK_SlimeBomb.glb"

const THIEF_IDS: Array[String] = ["spider", "chameleon"]
const THIEF_LABELS: Array[String] = ["The Spider", "The Chameleon"]

const TOOLS: Array = [
	{"id": "zipwire", "name": "Zipwire", "mesh": TOOL_ZIPWIRE_MESH, "desc": "Silent traversal line. Cross gaps and reach high ledges without a sound."},
	{"id": "smoke_bomb", "name": "Smoke Bomb", "mesh": TOOL_SMOKE_MESH, "desc": "Burst of cover. Break line of sight and vanish mid-hunt."},
	{"id": "blackjack", "name": "Blackjack", "mesh": TOOL_BLACKJACK_MESH, "desc": "Quiet takedown tool. Drop an isolated guard up close."},
	{"id": "slithersap", "name": "Slithersap", "mesh": TOOL_SLITHERSAP_MESH, "desc": "Sticky slowing agent. Gums up patrols and devices."},
]

var _thief_id: String = "spider"
var _rows: Dictionary = {}
var _body_keys: Array[String] = []
var _head_keys: Array[String] = []
var _card_keys: Array[String] = []
var _body: String = ""
var _head: String = ""
var _card: String = ""
var _active_tool: int = 0

var _yaw: float = 0.6
var _pitch: float = 0.0
var _last_drag_msec: int = 0
var _tool_yaw: float = 0.5

var _thief_name_lbl: Label
var _thief_lock_lbl: Label
var _hint_lbl: Label
var _body_opt: OptionButton
var _head_opt: OptionButton
var _card_opt: OptionButton
var _desc_lbl: Label
var _tool_btns: Array[Button] = []
var _tool_name_lbl: Label
var _tool_desc_lbl: Label

var _turntable: Node3D
var _tool_holder: Node3D
var _mat_loader: Node = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_drag_msec = Time.get_ticks_msec()
	_thief_id = str(GameState.thief_id) if str(GameState.thief_id) != "" else "spider"
	if not THIEF_IDS.has(_thief_id):
		_thief_id = "spider"
	_rows = _load_outfit_rows()
	_build_ui()
	if AudioManager != null and AudioManager.has_method("wire_hover_sfx"):
		AudioManager.wire_hover_sfx(self)
	_load_saved_loadout()
	_refresh_thief_ui()


## Instance helper: show the customizer and take mouse control.
func open_customizer() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("wardrobe_open")
	_refresh_thief_ui()


## Instance helper: persist selection, restore mouse, emit closed, hide.
func close_customizer() -> void:
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("back")
	_apply_and_close(true)


func _process(delta: float) -> void:
	if not visible:
		return
	if _turntable != null and is_instance_valid(_turntable):
		var now: int = Time.get_ticks_msec()
		if now - _last_drag_msec > 3000:
			_yaw += delta * 0.35
		_turntable.rotation = Vector3(_pitch, _yaw, 0.0)
	if _tool_holder != null and is_instance_valid(_tool_holder):
		_tool_yaw += delta * 0.5
		_tool_holder.rotation = Vector3(0.0, _tool_yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_apply_and_close(true)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if not kev.pressed or kev.echo:
			return
		if kev.keycode == KEY_ESCAPE:
			_apply_and_close(true)
			get_viewport().set_input_as_handled()
		elif kev.keycode == KEY_Q:
			_cycle_thief(-1)
			get_viewport().set_input_as_handled()
		elif kev.keycode == KEY_E:
			_cycle_thief(1)
			get_viewport().set_input_as_handled()
		elif kev.keycode >= KEY_1 and kev.keycode <= KEY_4:
			_on_tool_selected(int(kev.keycode - KEY_1))
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.01, 0.03, 0.86)
	root.add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 16)
	root.add_child(margin)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	vb.add_child(_build_top_bar())
	var main: HBoxContainer = HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(main)
	main.add_child(_build_left_panel())
	main.add_child(_build_right_panel())


func _build_top_bar() -> PanelContainer:
	var bar: PanelContainer = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(2, 6, ThemeScript.TEAL_PANEL_BG, 12))
	ThemeScript.add_teal_filigree(bar, 3.0, 14.0)
	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(hb)
	var q_btn: Button = Button.new()
	q_btn.text = "< Q"
	q_btn.custom_minimum_size = Vector2(72, 42)
	ThemeScript.style_teal_button(q_btn, false)
	q_btn.pressed.connect(_cycle_thief.bind(-1))
	hb.add_child(q_btn)
	var name_vb: VBoxContainer = VBoxContainer.new()
	name_vb.custom_minimum_size = Vector2(420, 0)
	name_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(name_vb)
	_thief_name_lbl = Label.new()
	_thief_name_lbl.text = "THE SPIDER"
	_thief_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thief_name_lbl.add_theme_font_size_override("font_size", 26)
	_thief_name_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		_thief_name_lbl.add_theme_font_override("font", serif)
	name_vb.add_child(_thief_name_lbl)
	_thief_lock_lbl = Label.new()
	_thief_lock_lbl.text = ""
	_thief_lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thief_lock_lbl.add_theme_font_size_override("font_size", 13)
	_thief_lock_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	if sans != null:
		_thief_lock_lbl.add_theme_font_override("font", sans)
	name_vb.add_child(_thief_lock_lbl)
	var e_btn: Button = Button.new()
	e_btn.text = "E >"
	e_btn.custom_minimum_size = Vector2(72, 42)
	ThemeScript.style_teal_button(e_btn, false)
	e_btn.pressed.connect(_cycle_thief.bind(1))
	hb.add_child(e_btn)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	var back_btn: Button = Button.new()
	back_btn.text = "BACK [ESC]"
	back_btn.custom_minimum_size = Vector2(160, 42)
	ThemeScript.style_teal_button(back_btn, false)
	back_btn.pressed.connect(func() -> void: _apply_and_close(true))
	hb.add_child(back_btn)
	return bar


func _build_left_panel() -> VBoxContainer:
	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	var prev_hdr: Label = Label.new()
	prev_hdr.text = "WARDROBE — DRAG TO ROTATE"
	prev_hdr.add_theme_font_size_override("font_size", 14)
	prev_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	if sans != null:
		prev_hdr.add_theme_font_override("font", sans)
	left.add_child(prev_hdr)
	var svc: SubViewportContainer = SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.custom_minimum_size = Vector2(420, 300)
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	left.add_child(svc)
	var sv: SubViewport = SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(sv)
	_setup_preview_world(sv)
	svc.gui_input.connect(_on_preview_gui_input)
	var load_hdr: Label = Label.new()
	load_hdr.text = "EDIT LOADOUT"
	load_hdr.add_theme_font_size_override("font_size", 15)
	load_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		load_hdr.add_theme_font_override("font", serif)
	left.add_child(load_hdr)
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	left.add_child(toolbar)
	_tool_btns.clear()
	for i: int in range(TOOLS.size()):
		var entry_var: Variant = TOOLS[i]
		var entry: Dictionary = entry_var as Dictionary
		var b: Button = Button.new()
		b.text = "[" + str(i + 1) + "] " + str(entry.get("name", "?"))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 38)
		ThemeScript.style_teal_tab(b, i == _active_tool)
		b.pressed.connect(_on_tool_selected.bind(i))
		toolbar.add_child(b)
		_tool_btns.append(b)
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", ThemeScript.teal_card_style(1, 5, ThemeScript.TEAL_PANEL_BG, 12))
	ThemeScript.add_teal_filigree(card, 3.0, 14.0)
	left.add_child(card)
	var card_hb: HBoxContainer = HBoxContainer.new()
	card_hb.add_theme_constant_override("separation", 12)
	card.add_child(card_hb)
	var tool_svc: SubViewportContainer = SubViewportContainer.new()
	tool_svc.stretch = true
	tool_svc.custom_minimum_size = Vector2(200, 120)
	tool_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_hb.add_child(tool_svc)
	var tool_sv: SubViewport = SubViewport.new()
	tool_sv.own_world_3d = true
	tool_sv.transparent_bg = false
	tool_sv.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	tool_svc.add_child(tool_sv)
	_setup_tool_world(tool_sv)
	var tool_vb: VBoxContainer = VBoxContainer.new()
	tool_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_vb.add_theme_constant_override("separation", 6)
	card_hb.add_child(tool_vb)
	_tool_name_lbl = Label.new()
	_tool_name_lbl.text = "Zipwire"
	_tool_name_lbl.add_theme_font_size_override("font_size", 20)
	_tool_name_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		_tool_name_lbl.add_theme_font_override("font", serif)
	tool_vb.add_child(_tool_name_lbl)
	_tool_desc_lbl = Label.new()
	_tool_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tool_desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tool_desc_lbl.add_theme_font_size_override("font_size", 14)
	_tool_desc_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_tool_desc_lbl.add_theme_font_override("font", sans)
	tool_vb.add_child(_tool_desc_lbl)
	return left


func _build_right_panel() -> PanelContainer:
	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()
	var right_card: PanelContainer = PanelContainer.new()
	right_card.custom_minimum_size = Vector2(310, 0)
	right_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_card.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(1, 6, ThemeScript.TEAL_PANEL_BG, 16))
	ThemeScript.add_teal_filigree(right_card, 3.0, 14.0)
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	right_card.add_child(right)
	var cust_hdr: Label = Label.new()
	cust_hdr.text = "CUSTOMIZATION"
	cust_hdr.add_theme_font_size_override("font_size", 19)
	cust_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		cust_hdr.add_theme_font_override("font", serif)
	right.add_child(cust_hdr)
	right.add_child(ThemeScript.teal_divider())
	var head_hdr: Label = Label.new()
	head_hdr.text = "HEAD"
	head_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	right.add_child(head_hdr)
	_head_opt = OptionButton.new()
	ThemeScript.style_teal_option(_head_opt)
	_head_opt.item_selected.connect(_on_head_selected)
	right.add_child(_head_opt)
	var body_hdr: Label = Label.new()
	body_hdr.text = "BODY"
	body_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	right.add_child(body_hdr)
	_body_opt = OptionButton.new()
	ThemeScript.style_teal_option(_body_opt)
	_body_opt.item_selected.connect(_on_body_selected)
	right.add_child(_body_opt)
	var card_hdr: Label = Label.new()
	card_hdr.text = "CALLING CARD"
	card_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	right.add_child(card_hdr)
	_card_opt = OptionButton.new()
	ThemeScript.style_teal_option(_card_opt)
	_card_opt.item_selected.connect(_on_card_selected)
	right.add_child(_card_opt)
	_desc_lbl = Label.new()
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_lbl.add_theme_font_size_override("font_size", 14)
	_desc_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_desc_lbl.add_theme_font_override("font", sans)
	right.add_child(_desc_lbl)
	_hint_lbl = Label.new()
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.add_theme_font_size_override("font_size", 14)
	_hint_lbl.add_theme_color_override("font_color", Color(0.95, 0.55, 0.65))
	right.add_child(_hint_lbl)
	var apply_btn: Button = Button.new()
	apply_btn.text = "APPLY"
	apply_btn.custom_minimum_size = Vector2(160, 42)
	ThemeScript.style_teal_button(apply_btn, true)
	apply_btn.pressed.connect(func() -> void: _apply_and_close(true))
	right.add_child(apply_btn)
	return right_card


func _panel_style(bg: Color) -> StyleBoxFlat:
	return ThemeScript.teal_panel_style(1, 5, bg, 12)


func _setup_preview_world(sv: SubViewport) -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.045, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.4, 0.3)
	env.ambient_light_energy = 0.75
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	sv.add_child(world_env)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 1.15
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sv.add_child(key)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.light_color = Color(1.0, 0.72, 0.45)
	fill.light_energy = 0.9
	fill.position = Vector3(-2.0, 2.2, 2.6)
	sv.add_child(fill)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.light_color = Color(0.55, 0.62, 0.9)
	rim.light_energy = 0.45
	rim.rotation_degrees = Vector3(-18.0, 150.0, 0.0)
	sv.add_child(rim)
	var floor_mi: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(9.0, 9.0)
	floor_mi.mesh = plane
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.075, 0.08)
	mat.roughness = 0.92
	floor_mi.material_override = mat
	sv.add_child(floor_mi)
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	_turntable.rotation = Vector3(_pitch, _yaw, 0.0)
	sv.add_child(_turntable)
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0.0, 1.35, 3.4)
	cam.fov = 40.0
	cam.current = true
	sv.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.95, 0.0))


func _setup_tool_world(sv: SubViewport) -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.4, 0.3)
	env.ambient_light_energy = 0.8
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	sv.add_child(world_env)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	sv.add_child(key)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.light_color = Color(1.0, 0.72, 0.45)
	fill.light_energy = 0.8
	fill.position = Vector3(-1.2, 1.4, 1.6)
	sv.add_child(fill)
	_tool_holder = Node3D.new()
	_tool_holder.name = "ToolHolder"
	sv.add_child(_tool_holder)
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0.0, 0.4, 1.7)
	cam.fov = 38.0
	cam.current = true
	sv.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.25, 0.0))


func _on_preview_gui_input(event: InputEvent) -> void:
	if _turntable == null or not is_instance_valid(_turntable):
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var mask: int = int(mm.button_mask)
		if (mask & MOUSE_BUTTON_MASK_LEFT) != 0 or (mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
			_yaw += mm.relative.x * 0.012
			_pitch = clampf(_pitch - mm.relative.y * 0.008, -0.45, 0.45)
			_last_drag_msec = Time.get_ticks_msec()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_yaw += drag.relative.x * 0.012
		_pitch = clampf(_pitch - drag.relative.y * 0.008, -0.45, 0.45)
		_last_drag_msec = Time.get_ticks_msec()


func _cycle_thief(dir: int) -> void:
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("click")
	var idx: int = THIEF_IDS.find(_thief_id)
	if idx < 0:
		idx = 0
	var next: int = (idx + dir + THIEF_IDS.size()) % THIEF_IDS.size()
	var target: String = THIEF_IDS[next]
	if not _is_thief_unlocked(target):
		_set_hint("The Chameleon is locked. Finish a contract to earn this disguise.")
		return
	_thief_id = target
	_set_hint("")
	_refresh_thief_ui()


func _is_thief_unlocked(thief: String) -> bool:
	if thief == "spider":
		return true
	var data: Dictionary = SaveSystem.data
	var unlocked_var: Variant = data.get("unlocked_thieves", [])
	if unlocked_var is Array:
		var unlocked: Array = unlocked_var as Array
		if unlocked.has(thief):
			return true
	var flag_var: Variant = data.get("chameleon_unlocked", false)
	if flag_var is bool and bool(flag_var):
		return true
	var completed_var: Variant = data.get("completed_contracts", {})
	if completed_var is Dictionary:
		var completed: Dictionary = completed_var as Dictionary
		if not completed.is_empty():
			return true
	return false


func _set_hint(text: String) -> void:
	if _hint_lbl != null:
		_hint_lbl.text = text


func _on_tool_selected(idx: int) -> void:
	if idx < 0 or idx >= TOOLS.size():
		return
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("click")
	_active_tool = idx
	_refresh_tool_ui()


func _refresh_tool_ui() -> void:
	for i: int in range(_tool_btns.size()):
		var b: Button = _tool_btns[i]
		b.button_pressed = (i == _active_tool)
		ThemeScript.style_teal_tab(b, i == _active_tool)
	if _tool_holder != null and is_instance_valid(_tool_holder):
		for c: Node in _tool_holder.get_children():
			_tool_holder.remove_child(c)
			c.queue_free()
		var entry_var: Variant = TOOLS[_active_tool]
		var entry: Dictionary = entry_var as Dictionary
		var mesh_path: String = str(entry.get("mesh", ""))
		var node: Node = _load_model(mesh_path)
		if node != null:
			_tool_holder.add_child(node)
			_bind_preview_materials(node, _glb_to_ue_mesh(mesh_path))
	var entry_var2: Variant = TOOLS[_active_tool]
	var entry2: Dictionary = entry_var2 as Dictionary
	if _tool_name_lbl != null:
		_tool_name_lbl.text = str(entry2.get("name", "Tool"))
	if _tool_desc_lbl != null:
		var lock_note: String = ""
		if not _is_tool_unlocked(str(entry2.get("id", ""))):
			lock_note = "\n[Locked - preview only]"
		_tool_desc_lbl.text = str(entry2.get("desc", "")) + lock_note


func _is_tool_unlocked(tool_id: String) -> bool:
	var data: Dictionary = SaveSystem.data
	var unlocked_var: Variant = data.get("unlocked_tools", [])
	if unlocked_var is Array:
		var unlocked: Array = unlocked_var as Array
		return unlocked.has(tool_id)
	return false


func _on_body_selected(idx: int) -> void:
	if idx >= 0 and idx < _body_keys.size():
		if AudioManager != null and AudioManager.has_method("play_ui"):
			AudioManager.play_ui("click")
		_body = _body_keys[idx]
		_update_desc()
		_rebuild_figure()


func _on_head_selected(idx: int) -> void:
	if idx >= 0 and idx < _head_keys.size():
		if AudioManager != null and AudioManager.has_method("play_ui"):
			AudioManager.play_ui("click")
		_head = _head_keys[idx]
		_update_desc()
		_rebuild_figure()


func _on_card_selected(idx: int) -> void:
	if idx >= 0 and idx < _card_keys.size():
		if AudioManager != null and AudioManager.has_method("play_ui"):
			AudioManager.play_ui("click")
		_card = _card_keys[idx]
		_update_desc()
		_rebuild_figure()


func _refresh_thief_ui() -> void:
	var label_idx: int = THIEF_IDS.find(_thief_id)
	if label_idx < 0:
		label_idx = 0
	if _thief_name_lbl != null:
		_thief_name_lbl.text = THIEF_LABELS[label_idx].to_upper()
	if _thief_lock_lbl != null:
		if _thief_id == "chameleon":
			_thief_lock_lbl.text = "Q / E to switch thief - Chameleon contracts pay a disguise bonus"
		else:
			_thief_lock_lbl.text = "Q / E to switch thief"
	_collect_slots()
	_fill_option(_body_opt, _body_keys, _body)
	_fill_option(_head_opt, _head_keys, _head)
	_fill_option(_card_opt, _card_keys, _card)
	if not _body_keys.is_empty() and not _body_keys.has(_body):
		_body = _body_keys[0]
	if not _head_keys.is_empty() and not _head_keys.has(_head):
		_head = _head_keys[0]
	if not _card_keys.is_empty() and not _card_keys.has(_card):
		_card = _card_keys[0]
	_update_desc()
	_rebuild_figure()
	_refresh_tool_ui()


func _rebuild_figure() -> void:
	if _turntable == null or not is_instance_valid(_turntable):
		return
	for c: Node in _turntable.get_children():
		_turntable.remove_child(c)
		c.queue_free()
	var body_path: String = _resolve_body_path(_body)
	var body_node: Node = _load_model(body_path)
	if body_node != null:
		_turntable.add_child(body_node)
		_bind_preview_materials(body_node, _glb_to_ue_mesh(body_path))
	var head_path: String = _resolve_head_path(_head)
	if head_path != "":
		var head_node: Node = _load_model(head_path)
		if head_node != null:
			_turntable.add_child(head_node)
			_bind_preview_materials(head_node, _glb_to_ue_mesh(head_path))
	var card_path: String = _resolve_card_path(_card, _thief_id)
	if card_path != "":
		var card_node: Node = _load_model(card_path)
		if card_node != null:
			var prop: Node3D = card_node as Node3D
			if prop != null:
				prop.position = Vector3(0.55, 1.05, 0.25)
				prop.scale = Vector3(0.6, 0.6, 0.6)
			_turntable.add_child(card_node)
			_bind_preview_materials(card_node, _glb_to_ue_mesh(card_path))


func _glb_to_ue_mesh(res_path: String) -> String:
	var marker: String = "assets/ue/Content/"
	var idx: int = res_path.find(marker)
	if idx < 0:
		return ""
	var rel: String = res_path.substr(idx + marker.length())
	if rel.ends_with(".glb"):
		rel = rel.substr(0, rel.length() - 4)
	return "/Game/" + rel


func _get_mat_loader() -> Node:
	if _mat_loader == null:
		_mat_loader = LevelLoaderScript.new()
		add_child(_mat_loader)
	return _mat_loader


func _bind_preview_materials(root: Node, ue_mesh_path: String) -> void:
	if root == null or ue_mesh_path == "":
		return
	var loader: Node = _get_mat_loader()
	if loader == null:
		return
	var db: Variant = loader.get("_mesh_mats_db")
	var slots_v: Variant = (db as Dictionary).get(ue_mesh_path, null) if db is Dictionary else null
	if not (slots_v is Array):
		var db_low: Variant = loader.get("_mesh_mats_db_lower")
		slots_v = (db_low as Dictionary).get(ue_mesh_path.to_lower(), null) if db_low is Dictionary else null
	if not (slots_v is Array):
		return
	_bind_preview_meshes(root, loader, slots_v as Array)


func _bind_preview_meshes(node: Node, loader: Node, slots: Array) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			var count: int = mini(mi.mesh.get_surface_count(), slots.size())
			for s: int in range(count):
				var mat_path: String = str(slots[s])
				if mat_path == "":
					continue
				var mat: Material = loader.call("get_material_for_ue", mat_path) as Material
				if mat != null:
					mi.set_surface_override_material(s, mat)
	for child: Node in node.get_children():
		_bind_preview_meshes(child, loader, slots)


func _load_model(path: String) -> Node:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path)
	if res is PackedScene:
		var scene: PackedScene = res as PackedScene
		var node: Node = scene.instantiate()
		return node
	return null


func _resolve_body_path(outfit_key: String) -> String:
	var lowered: String = outfit_key.to_lower()
	if "patternb" in lowered and ResourceLoader.exists(BODY_TARANTULA_B_PATH):
		return BODY_TARANTULA_B_PATH
	if "alta" in lowered and ResourceLoader.exists(BODY_TARANTULA_PATH):
		return BODY_TARANTULA_PATH
	return BODY_BASE_PATH


func _resolve_head_path(outfit_key: String) -> String:
	var lowered: String = outfit_key.to_lower()
	var candidates: Array[String] = []
	if "thiefmaska" in lowered and "mustachea" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_ThiefMaskA_MustacheA.glb")
	if "thiefmaska" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_ThiefMaskA.glb")
	if "bowlera" in lowered and "mustachea" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_BowlerA_MustacheA.glb")
	if "bowlera" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_BowlerA.glb")
	if "tophat" in lowered and "monocle" in lowered and "beard" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_TopHatA_MonocleA_BeardA.glb")
	if "tophat" in lowered and "mustache" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_TopHatA_MustacheA.glb")
	if "tophat" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_TopHatA.glb")
	if "chignon" in lowered and "thiefmask" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_Hair_Chignon_ThiefMaskA.glb")
	if "chignon" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_Hair_Chignon.glb")
	if "bob" in lowered and "eyepatch" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_Hair_Bob_EyePatchA.glb")
	if "bob" in lowered or "hairb" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_Hair_Bob.glb")
	if "eyepatch" in lowered or "eyepatcha" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_EyePatchA.glb")
	if "glasses" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_GlassesA.glb")
	if "monocle" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_MonocleA.glb")
	if "beard" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_BeardA.glb")
	if "mustache" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_MustacheA.glb")
	if "nocap" in lowered or "capa" in lowered:
		candidates.append("SK_ThiefNisha_Dyn__Head_NoCap.glb")
	candidates.append("SK_ThiefNisha_Dyn__Head.glb")
	for f: String in candidates:
		var full: String = DYN_HEAD_DIR + f
		if ResourceLoader.exists(full):
			return full
	if ResourceLoader.exists(HEAD_STATIC_PATH):
		return HEAD_STATIC_PATH
	return ""


func _resolve_card_path(outfit_key: String, thief: String) -> String:
	var lowered: String = outfit_key.to_lower()
	var use_chameleon: bool = thief == "chameleon"
	var base: String = CARD_CHAMELEON if use_chameleon else CARD_SPIDER
	var silver: String = CARD_CHAMELEON_SILVER if use_chameleon else CARD_SPIDER_SILVER
	var gold: String = CARD_CHAMELEON_GOLD if use_chameleon else CARD_SPIDER_GOLD
	var magic: String = CARD_CHAMELEON_MAGIC if use_chameleon else CARD_SPIDER_MAGIC
	var ship: String = CARD_CHAMELEON_SHIP if use_chameleon else CARD_SPIDER_SHIP
	var chosen: String = base
	if "modelship" in lowered or "ship" in lowered:
		chosen = ship
	elif "gold" in lowered:
		chosen = gold
	elif "magic" in lowered:
		chosen = magic
	elif "silver" in lowered:
		chosen = silver
	if ResourceLoader.exists(chosen):
		return chosen
	if ResourceLoader.exists(base):
		return base
	return ""


func _fill_option(opt: OptionButton, keys: Array[String], current: String) -> void:
	if opt == null:
		return
	opt.clear()
	var sel: int = 0
	for i: int in range(keys.size()):
		var label_text: String = _display_name(keys[i])
		opt.add_item(label_text, i)
		if keys[i] == current:
			sel = i
	if opt.item_count > 0:
		opt.select(sel)


func _update_desc() -> void:
	if _desc_lbl == null:
		return
	var lines: Array[String] = []
	var bdesc: String = _display_desc(_body)
	var hdesc: String = _display_desc(_head)
	var cdesc: String = _display_desc(_card)
	if bdesc != "":
		lines.append("Body: " + bdesc)
	if hdesc != "":
		lines.append("Head: " + hdesc)
	if cdesc != "":
		lines.append("Calling Card: " + cdesc)
	if lines.is_empty():
		lines.append("No outfits found for this thief.")
	_desc_lbl.text = "\n".join(lines)


func _load_outfit_rows() -> Dictionary:
	var result: Dictionary = {}
	if not FileAccess.file_exists(OUTFITS_JSON_PATH):
		return result
	var f: FileAccess = FileAccess.open(OUTFITS_JSON_PATH, FileAccess.READ)
	if f == null:
		return result
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var d: Dictionary = parsed as Dictionary
		var rows_var: Variant = d.get("rows", {})
		if rows_var is Dictionary:
			result = (rows_var as Dictionary).duplicate()
	return result


func _collect_slots() -> void:
	_body_keys.clear()
	_head_keys.clear()
	_card_keys.clear()
	var tag: String = _thief_id.capitalize()
	for key_var: Variant in _rows.keys():
		var key: String = str(key_var)
		if not _key_matches_thief(key, tag):
			continue
		var slot: String = _slot_of(key)
		if slot == "Body":
			_body_keys.append(key)
		elif slot == "Head":
			_head_keys.append(key)
		elif slot == "CallingCard":
			_card_keys.append(key)
	_body_keys.sort()
	_head_keys.sort()
	_card_keys.sort()


func _key_matches_thief(key: String, tag: String) -> bool:
	return key.begins_with("Outfit." + tag + ".")


func _slot_of(key: String) -> String:
	var row_var: Variant = _rows.get(key, {})
	if not (row_var is Dictionary):
		return ""
	var row: Dictionary = row_var as Dictionary
	var cat_var: Variant = row.get("OutfitLoadoutSlotCategory", {})
	var cat: Dictionary = cat_var as Dictionary if cat_var is Dictionary else {}
	var tag_name: String = str(cat.get("TagName", ""))
	if "CallingCard" in tag_name:
		return "CallingCard"
	if tag_name.ends_with(".Head") or ".Head" in tag_name:
		return "Head"
	if tag_name.ends_with(".Body") or ".Body" in tag_name:
		return "Body"
	if ".Head." in key or ".Head" in key:
		return "Head"
	if ".Body." in key or ".Body" in key:
		return "Body"
	if "CallingCard" in key:
		return "CallingCard"
	return ""


func _display_name(key: String) -> String:
	if key == "":
		return "(None)"
	var row_var: Variant = _rows.get(key, {})
	if not (row_var is Dictionary):
		return key
	var row: Dictionary = row_var as Dictionary
	var meta_var: Variant = row.get("MetaData", {})
	var meta: Dictionary = meta_var as Dictionary if meta_var is Dictionary else {}
	var name_var: Variant = meta.get("OutfitName", {})
	var name_d: Dictionary = name_var as Dictionary if name_var is Dictionary else {}
	return str(name_d.get("LocalizedString", key))


func _display_desc(key: String) -> String:
	if key == "":
		return ""
	var row_var: Variant = _rows.get(key, {})
	if not (row_var is Dictionary):
		return ""
	var row: Dictionary = row_var as Dictionary
	var meta_var: Variant = row.get("MetaData", {})
	var meta: Dictionary = meta_var as Dictionary if meta_var is Dictionary else {}
	var desc_var: Variant = meta.get("OutfitDescription", {})
	var desc_d: Dictionary = desc_var as Dictionary if desc_var is Dictionary else {}
	return str(desc_d.get("LocalizedString", ""))


func _load_saved_loadout() -> void:
	var data: Dictionary = SaveSystem.data
	var data_var: Variant = data.get("loadout", {})
	if data_var is Dictionary:
		var loadout: Dictionary = data_var as Dictionary
		var saved_thief: String = str(loadout.get("thief_id", _thief_id))
		if THIEF_IDS.has(saved_thief):
			_thief_id = saved_thief
		_body = str(loadout.get("body", ""))
		_head = str(loadout.get("head", ""))
		_card = str(loadout.get("calling_card", ""))
		var tool_var: Variant = loadout.get("active_tool", 0)
		_active_tool = clampi(int(tool_var), 0, TOOLS.size() - 1)


func _apply_and_close(should_emit: bool) -> void:
	GameState.thief_id = _thief_id
	GameState.outfit_body = _short_name(_body)
	GameState.outfit_head = _short_name(_head)
	GameState.calling_card = _short_name(_card)
	var entry_var: Variant = TOOLS[_active_tool]
	var entry: Dictionary = entry_var as Dictionary
	var loadout: Dictionary = {
		"thief_id": _thief_id,
		"body": _body,
		"head": _head,
		"calling_card": _card,
		"active_tool": _active_tool,
		"active_tool_id": str(entry.get("id", "zipwire")),
	}
	SaveSystem.data["loadout"] = loadout
	_set_game_state_if_present("loadout_body", _body)
	_set_game_state_if_present("loadout_head", _head)
	_set_game_state_if_present("loadout_calling_card", _card)
	_set_game_state_if_present("loadout", loadout)
	if SaveSystem.has_method("write_save"):
		SaveSystem.write_save()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if should_emit:
		closed.emit()
	visible = false
	queue_free()


func _short_name(key: String) -> String:
	if key == "":
		return "Default"
	var parts: PackedStringArray = key.split(".")
	if parts.is_empty():
		return key
	return str(parts[parts.size() - 1])


func _set_game_state_if_present(prop: String, value: Variant) -> void:
	for p: Dictionary in GameState.get_property_list():
		if str(p.get("name", "")) == prop:
			GameState.set(prop, value)
			return
