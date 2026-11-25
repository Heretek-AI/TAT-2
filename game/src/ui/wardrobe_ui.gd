extends CanvasLayer
class_name WardrobeUI
## Wardrobe / Bureau Character Customizer for the Thieves' Den hub.
## Workstream 3 + W6U2: 3D full-body thief preview (SubViewport turntable with
## warm wardrobe lighting), Q/E thief switcher (Chameleon locked until the
## authored Thief.Chameleon / Contract 3 gate), a three-column KF03/KF04 layout
## (loadout + tool card | 3D thief | Head / Body / Calling Card), and loadout
## slots sourced from the authored Black Market catalog:
##   slot 1 + slot 4 hold the thief's signature tools (grey padlock, KF03),
##   slots 2-3 are swappable; selecting one reveals the KF04 candidate row of
##   the remaining authored tools with pink padlocks when not owned.
## Head / Body / Calling Card slot cards show the authored reward icon and
## cycle the DT_CharacterOutfitsMetadata rows. There is no APPLY button: BACK
## (bottom-right, KF03) persists and closes. Persists to GameState + SaveSystem.
##
## All mesh paths below were verified to exist on disk. No inferred types are
## used on Variant / Dictionary values anywhere in this file.

signal closed()

const ThemeScript: GDScript = preload("res://src/ui/art_nouveau_theme.gd")
const CatalogScript: GDScript = preload("res://src/ui/unlock_catalog.gd")
const LevelLoaderScript: GDScript = preload("res://src/core/level_loader.gd")
const GuardAnimLibScript: GDScript = preload("res://src/core/animation_library.gd")

const OUTFITS_JSON_PATH: String = "res://data/generated/tables/Character/Player/DT_CharacterOutfitsMetadata.json"
const LOCK_ICON_PATH: String = "res://assets/ue/Raw/Art/UI/Icons/T_Icon_Locked.png"

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

## Catalog save id -> authored gear mesh (all verified on disk). Every tool the
## Black Market sells has a 3D preview; blackjack is the built-in.
const TOOL_MESHES: Dictionary = {
	"zipwire": "res://assets/ue/Content/Art/Gameplay/Gear/Zipwire/SM_Zipwire.glb",
	"smoke_bomb": "res://assets/ue/Content/Art/Gameplay/Gear/SmokeBomb/SK_SmokeBomb.glb",
	"pickpocket_fairy": "res://assets/ue/Content/Art/Gameplay/Gear/PickpocketFairy/SK_PickpocketFairy.glb",
	"insult_fairy": "res://assets/ue/Content/Art/Gameplay/Gear/InsultFairy/SK_InsultFairy.glb",
	"slither_sap": "res://assets/ue/Content/Art/Gameplay/Gear/Slithersap/SK_SlimeBomb.glb",
	"glamour": "res://assets/ue/Content/Art/Gameplay/Gear/Disguise/SK_DisguiseMask.glb",
	"vistara_diamond": "res://assets/ue/Content/Art/Gameplay/Gear/VistaraDiamond/SM_VistaraDiamond_Gem.glb",
	"blackjack": "res://assets/ue/Content/Art/Gameplay/Gear/BlackJack/SM_Blackjack.glb",
}

## KF03: slot 1 and slot 4 are the thief's signature tools (grey padlock,
## "Signature Tools cannot be swapped out"). The other two slots swap from the
## KF04 candidate row. Spider's disguise counterpart is the Chameleon's Glamour.
const SIGNATURES_BY_THIEF: Dictionary = {
	"spider": ["zipwire", "vistara_diamond"],
	"chameleon": ["glamour", "vistara_diamond"],
}
const SIGNATURE_SLOTS: Array[int] = [0, 3]
const SLOT_COUNT: int = 4

## KF03/KF04 cite: pink/magenta LOCKED badges (thief portrait overlay, slot-3
## expanded-row tool locks). P2-1 token pass: routed to ThemeScript.PINK_LOCKED;
## this alias stays so existing comments/call sites keep a local name.
const LOCKED_PINK: Color = Color(1.0, 0.38, 0.72)

const THIEF_IDS: Array[String] = ["spider", "chameleon"]
const THIEF_LABELS: Array[String] = ["The Spider", "The Chameleon"]

var _thief_id: String = "spider"
var _catalog: RefCounted = null
var _tools: Array[Dictionary] = []
var _slots: Array[String] = []
var _slots_by_thief: Dictionary = {}
var _slot_index: int = 0
var _rows: Dictionary = {}
var _body_keys: Array[String] = []
var _head_keys: Array[String] = []
var _card_keys: Array[String] = []
var _body: String = ""
var _head: String = ""
var _card: String = ""

var _yaw: float = 0.6
var _pitch: float = 0.0
var _last_drag_msec: int = 0
var _tool_yaw: float = 0.5

var _hint_lbl: Label
var _body_card: Button
var _head_card: Button
var _card_card: Button
var _spider_frame_btn: Button
var _cham_frame_btn: Button
var _spider_lock_lbl: Label
var _cham_lock_lbl: Label
var _slot_btns: Array[Button] = []
var _slot_icons: Array[TextureRect] = []
var _slot_locks: Array[TextureRect] = []
var _cell_btns: Array[Button] = []
var _cell_locks: Array[TextureRect] = []
var _cells_row: HBoxContainer
var _slot_row: HBoxContainer
var _desc_lbl: Label
var _tool_name_lbl: Label
var _tool_desc_lbl: Label
var _tool_cond_lbl: Label

var _turntable: Node3D
var _preview_cam: Camera3D
var _tool_cam: Camera3D
var _tool_holder: Node3D
var _mat_loader: Node = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_drag_msec = Time.get_ticks_msec()
	_thief_id = str(GameState.thief_id) if str(GameState.thief_id) != "" else "spider"
	if not THIEF_IDS.has(_thief_id):
		_thief_id = "spider"
	_catalog = CatalogScript.new()
	_build_tools()
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


## Build the tool list the Wardrobe offers: the authored Black Market tools
## (catalog order) plus the built-in blackjack, each with its authored title,
## description, reward icon, condition text and gear mesh. A missing catalog
## still yields the built-in so the panel renders; ownership then fails closed.
func _build_tools() -> void:
	_tools.clear()
	if _catalog != null and _catalog.is_available():
		for entry: Dictionary in _catalog.entries_for_column("tools"):
			var save_id: String = CatalogScript.save_id_of(entry)
			_tools.append({
				"id": save_id,
				"name": CatalogScript.title_of(entry),
				"desc": CatalogScript.description_of(entry),
				"icon": CatalogScript.icon_res_of(entry),
				"mesh": str(TOOL_MESHES.get(save_id, "")),
				"condition": CatalogScript.condition_text(entry),
				"entry": entry,
				"built_in": false,
			})
	if _catalog != null:
		for built: Dictionary in _catalog.built_in_tools():
			var built_id: String = str(built.get("save_id", ""))
			if built_id == "" or _tool(built_id).size() > 0:
				continue
			_tools.append({
				"id": built_id,
				"name": str(built.get("title", built_id.capitalize())),
				"desc": str(built.get("reason", "")),
				"icon": "",
				"mesh": str(TOOL_MESHES.get(built_id, "")),
				"condition": "",
				"entry": {},
				"built_in": true,
			})


func _tool(save_id: String) -> Dictionary:
	for tool: Dictionary in _tools:
		if str(tool.get("id", "")) == save_id:
			return tool
	return {}


func _signatures() -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = SIGNATURES_BY_THIEF.get(_thief_id, [])
	if raw is Array:
		for id_v: Variant in raw as Array:
			out.append(str(id_v))
	return out


func _default_slots() -> Array[String]:
	var sigs: Array[String] = _signatures()
	var out: Array[String] = ["", "", "", ""]
	if sigs.size() >= 1:
		out[0] = sigs[0]
	if sigs.size() >= 2:
		out[3] = sigs[sigs.size() - 1]
	out[1] = "smoke_bomb"
	return out


func _is_signature_slot(idx: int) -> bool:
	return SIGNATURE_SLOTS.has(idx)


func _is_tool_owned(tool: Dictionary) -> bool:
	if tool.is_empty():
		return false
	if bool(tool.get("built_in", false)):
		return true
	var entry_v: Variant = tool.get("entry", {})
	if not (entry_v is Dictionary):
		return false
	var entry: Dictionary = entry_v as Dictionary
	if entry.is_empty():
		return false
	if _catalog == null or not _catalog.is_available():
		return false
	return _catalog.state_of(entry) == CatalogScript.STATE_PURCHASED


## Every thief's signature tools. Glamour is the Chameleon's disguise and the
## Vistara Diamond is shared, so neither belongs in the Spider's swap row.
func _all_signature_ids() -> Array[String]:
	var out: Array[String] = []
	for thief_v: Variant in SIGNATURES_BY_THIEF.keys():
		var list_v: Variant = SIGNATURES_BY_THIEF[thief_v]
		if not (list_v is Array):
			continue
		for id_v: Variant in list_v as Array:
			var id: String = str(id_v)
			if id != "" and not out.has(id):
				out.append(id)
	return out


## Candidate tools: the authored tools that are nobody's signature and are not
## the built-in blackjack, in catalog order. Spider gets exactly the four KF04
## tiles (Smoke Bomb, Pickpocket Fairy, Insult Fairy, Slither Sap); the
## Chameleon gets the same four with Glamour as its own signature.
func _candidate_tools() -> Array[Dictionary]:
	var sigs: Array[String] = _all_signature_ids()
	var out: Array[Dictionary] = []
	for tool: Dictionary in _tools:
		if bool(tool.get("built_in", false)):
			continue
		if sigs.has(str(tool.get("id", ""))):
			continue
		out.append(tool)
	return out


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
			_on_slot_pressed(int(kev.keycode - KEY_1))
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# KF03: warm, almost-black room behind the left/right cards; the preview
	# stage itself is a warm 3D set, not a black void.
	dim.color = Color(0.015, 0.012, 0.018, 0.90)
	root.add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 10)
	root.add_child(margin)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	# KF03/KF04 cite: centered "WARDROBE" header above the thief switcher.
	var ward_hdr: Label = Label.new()
	ward_hdr.text = "WARDROBE"
	ward_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ward_hdr.add_theme_font_size_override("font_size", 27)
	ward_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	var _serif: Font = ThemeScript.font_serif()
	if _serif != null:
		ward_hdr.add_theme_font_override("font", _serif)
	vb.add_child(ward_hdr)
	vb.add_child(_build_top_bar())
	# True KF03/KF04 three columns: loadout + tool card (fixed), the tall 3D
	# thief stage (expands), and the Head/Body/Calling Card stack (fixed).
	var main: HBoxContainer = HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(main)
	var left_col: VBoxContainer = _build_left_panel()
	left_col.size_flags_stretch_ratio = 1.0
	main.add_child(left_col)
	var center_col: VBoxContainer = _build_preview_panel()
	center_col.size_flags_stretch_ratio = 1.45
	main.add_child(center_col)
	var right_col: PanelContainer = _build_right_panel()
	right_col.size_flags_stretch_ratio = 0.95
	main.add_child(right_col)
	vb.add_child(_build_bottom_bar())


func _build_top_bar() -> PanelContainer:
	# KF03 cite: Q/E-flanked thief portrait switcher (Spider selected w/ teal
	# frame, Chameleon dimmed w/ pink LOCKED). Portraits are empty frames:
	# standing HARD_LIMIT 5.1 (no cooked portrait texture path recovered).
	var bar: PanelContainer = PanelContainer.new()
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(400, 0)
	bar.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(2, 6, ThemeScript.TEAL_PANEL_BG, 8))
	ThemeScript.add_teal_filigree(bar, 3.0, 14.0)
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(hb)
	var q_btn: Button = Button.new()
	q_btn.text = "< Q"
	q_btn.custom_minimum_size = Vector2(56, 34)
	ThemeScript.style_teal_button(q_btn, false)
	q_btn.pressed.connect(_cycle_thief.bind(-1))
	hb.add_child(q_btn)
	hb.add_child(_build_thief_card("spider", THIEF_LABELS[0]))
	hb.add_child(_build_thief_card("chameleon", THIEF_LABELS[1]))
	var e_btn: Button = Button.new()
	e_btn.text = "E >"
	e_btn.custom_minimum_size = Vector2(56, 34)
	ThemeScript.style_teal_button(e_btn, false)
	e_btn.pressed.connect(_cycle_thief.bind(1))
	hb.add_child(e_btn)
	return bar


## KF03 cite: portrait card + name label per thief. Empty frame until portrait
## art source found (standing HARD_LIMIT 5.1); pink LOCKED overlay cites KF03
## (standing HARD_LIMIT 5.7: local LOCKED_PINK, no theme token in scope).
func _build_thief_card(thief: String, title: String) -> VBoxContainer:
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var stack: Control = Control.new()
	stack.custom_minimum_size = Vector2(88, 100)
	vb.add_child(stack)
	var frame: Button = Button.new()
	frame.text = ""
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.custom_minimum_size = Vector2(88, 100)
	ThemeScript.style_teal_tab(frame, thief == _thief_id)
	frame.pressed.connect(_on_portrait_pressed.bind(thief))
	stack.add_child(frame)
	var portrait_path: String = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_%s.png" % thief
	if ResourceLoader.exists(portrait_path):
		var portrait := TextureRect.new()
		portrait.texture = ResourceLoader.load(portrait_path) as Texture2D
		portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(portrait)
	var lock_lbl: Label = Label.new()
	lock_lbl.text = "LOCKED"
	lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_lbl.add_theme_font_size_override("font_size", 12)
	lock_lbl.add_theme_color_override("font_color", ThemeScript.PINK_LOCKED)
	stack.add_child(lock_lbl)
	var name_lbl: Label = Label.new()
	name_lbl.text = title
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	var serif: Font = ThemeScript.font_serif()
	if serif != null:
		name_lbl.add_theme_font_override("font", serif)
	vb.add_child(name_lbl)
	if thief == "spider":
		_spider_frame_btn = frame
		_spider_lock_lbl = lock_lbl
	else:
		_cham_frame_btn = frame
		_cham_lock_lbl = lock_lbl
	_refresh_portraits()
	return vb


## KF03 cite: selected portrait glows teal, locked portrait shows pink LOCKED.
func _refresh_portraits() -> void:
	var spider_locked: bool = not _is_thief_unlocked("spider")
	var cham_locked: bool = not _is_thief_unlocked("chameleon")
	if _spider_frame_btn != null:
		ThemeScript.style_teal_tab(_spider_frame_btn, _thief_id == "spider")
	if _cham_frame_btn != null:
		ThemeScript.style_teal_tab(_cham_frame_btn, _thief_id == "chameleon")
	if _spider_lock_lbl != null:
		_spider_lock_lbl.visible = spider_locked
	if _cham_lock_lbl != null:
		_cham_lock_lbl.visible = cham_locked


## KF03 cite: clicking a portrait selects that thief (locked -> hint only).
func _on_portrait_pressed(thief: String) -> void:
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("click")
	if not _is_thief_unlocked(thief):
		_set_hint("The Chameleon is locked. Unlock it in the Black Market (£10,000, Contract 3).")
		return
	_stash_slots()
	_thief_id = thief
	_set_hint("")
	_refresh_thief_ui()


## KF03/KF04 cite: BACK sits bottom-right (was top bar: task-6 row 22 MISMATCH).
func _build_bottom_bar() -> HBoxContainer:
	var hb: HBoxContainer = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	var back_btn: Button = Button.new()
	back_btn.text = "BACK [ESC]"
	back_btn.custom_minimum_size = Vector2(160, 34)
	ThemeScript.style_teal_button(back_btn, false)
	back_btn.pressed.connect(func() -> void: _apply_and_close(true))
	hb.add_child(back_btn)
	return hb


## KF03 slot tile: authored tool icon, a white number keycap at top-left and a
## padlock at bottom-left (grey for a signature tool, pink for an unowned one).
func _add_slot_cell(parent: Container, idx: int) -> void:
	var cell: Control = Control.new()
	cell.custom_minimum_size = Vector2(78, 78)
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(cell)
	var b: Button = Button.new()
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.toggle_mode = true
	b.text = ""
	b.custom_minimum_size = Vector2(78, 78)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ThemeScript.style_teal_tab(b, idx == _slot_index)
	b.pressed.connect(_on_slot_pressed.bind(idx))
	cell.add_child(b)
	_slot_btns.append(b)
	var icon: TextureRect = TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 14.0
	icon.offset_top = 12.0
	icon.offset_right = -14.0
	icon.offset_bottom = -12.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	_slot_icons.append(icon)
	var num: PanelContainer = ThemeScript.white_keycap(str(idx + 1), 11)
	num.custom_minimum_size = Vector2(18, 18)
	num.position = Vector2(2, 2)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(num)
	var lock: TextureRect = _lock_badge()
	lock.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lock.offset_left = 3.0
	lock.offset_top = -21.0
	lock.offset_right = 21.0
	lock.offset_bottom = -3.0
	cell.add_child(lock)
	_slot_locks.append(lock)


## KF04 candidate tile: authored tool icon in a framed square with the pink
## padlock at bottom-right (the frame shows Smoke Bomb unlocked, the rest
## locked).
func _add_candidate_cell(parent: Container, tool: Dictionary) -> void:
	var cell: Control = Control.new()
	cell.custom_minimum_size = Vector2(78, 62)
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(cell)
	var b: Button = Button.new()
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.toggle_mode = true
	b.text = ""
	b.custom_minimum_size = Vector2(78, 62)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ThemeScript.style_teal_tab(b, false)
	var save_id: String = str(tool.get("id", ""))
	b.pressed.connect(_on_candidate_pressed.bind(save_id))
	b.tooltip_text = str(tool.get("name", ""))
	cell.add_child(b)
	_cell_btns.append(b)
	var icon: TextureRect = TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 12.0
	icon.offset_top = 8.0
	icon.offset_right = -12.0
	icon.offset_bottom = -8.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	var tool_icon: String = str(tool.get("icon", ""))
	if tool_icon != "" and ResourceLoader.exists(tool_icon):
		var res: Resource = ResourceLoader.load(tool_icon)
		if res is Texture2D:
			icon.texture = res as Texture2D
	var lock: TextureRect = _lock_badge()
	lock.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	lock.offset_left = -23.0
	lock.offset_top = -23.0
	lock.offset_right = -5.0
	lock.offset_bottom = -5.0
	cell.add_child(lock)
	_cell_locks.append(lock)


func _lock_badge() -> TextureRect:
	var lock: TextureRect = TextureRect.new()
	if ResourceLoader.exists(LOCK_ICON_PATH):
		var res: Resource = ResourceLoader.load(LOCK_ICON_PATH)
		if res is Texture2D:
			lock.texture = res as Texture2D
	lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock.modulate = ThemeScript.PINK_LOCKED
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lock


func _small_header(text: String, color: Color) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	var sans: Font = ThemeScript.font_sans()
	if sans != null:
		lbl.add_theme_font_override("font", sans)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


## KF03: loadout is the left column (numbers 1-4, candidate row below, tool
## detail card under that); the 3D preview is the tall centre column and the
## Head/Body/Card cards are the right column (a true three-column layout).
func _build_left_panel() -> VBoxContainer:
	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(392, 0)
	left.size_flags_horizontal = Control.SIZE_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	var load_hdr: Label = Label.new()
	load_hdr.text = "Edit Loadout"
	load_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_hdr.add_theme_font_size_override("font_size", 18)
	load_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		load_hdr.add_theme_font_override("font", serif)
	left.add_child(load_hdr)
	left.add_child(ThemeScript.teal_divider())
	left.add_child(_small_header("LOADOUT SLOTS", ThemeScript.TEAL_ACCENT))
	# KF03: numbered loadout slots 1-4; slot 1 and 4 are signature tools.
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(toolbar)
	_slot_row = toolbar
	_slot_btns.clear()
	_slot_icons.clear()
	_slot_locks.clear()
	for i: int in range(SLOT_COUNT):
		_add_slot_cell(toolbar, i)
	# KF04: the candidate row only appears for a swappable slot.
	_cells_row = HBoxContainer.new()
	_cells_row.add_theme_constant_override("separation", 6)
	_cells_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cells_row.visible = false
	left.add_child(_cells_row)
	# KF03 cite: hint below the loadout slots (verified on-screen text).
	var load_hint: Label = Label.new()
	load_hint.text = "Select a loadout slot to equip or swap out tools"
	load_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	load_hint.add_theme_font_size_override("font_size", 12)
	load_hint.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	if sans != null:
		load_hint.add_theme_font_override("font", sans)
	left.add_child(load_hint)
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", ThemeScript.teal_card_style(1, 5, ThemeScript.TEAL_PANEL_BG, 10))
	ThemeScript.add_teal_filigree(card, 2.0, 10.0)
	left.add_child(card)
	var card_hb: HBoxContainer = HBoxContainer.new()
	card_hb.add_theme_constant_override("separation", 8)
	card.add_child(card_hb)
	var tool_svc: SubViewportContainer = SubViewportContainer.new()
	tool_svc.stretch = true
	tool_svc.custom_minimum_size = Vector2(130, 104)
	tool_svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	tool_vb.add_theme_constant_override("separation", 3)
	card_hb.add_child(tool_vb)
	_tool_name_lbl = Label.new()
	_tool_name_lbl.text = ""
	_tool_name_lbl.add_theme_font_size_override("font_size", 18)
	_tool_name_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		_tool_name_lbl.add_theme_font_override("font", serif)
	tool_vb.add_child(_tool_name_lbl)
	_tool_cond_lbl = Label.new()
	_tool_cond_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tool_cond_lbl.add_theme_font_size_override("font_size", 11)
	_tool_cond_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	if sans != null:
		_tool_cond_lbl.add_theme_font_override("font", sans)
	tool_vb.add_child(_tool_cond_lbl)
	_tool_desc_lbl = Label.new()
	_tool_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tool_desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tool_desc_lbl.add_theme_font_size_override("font_size", 12)
	_tool_desc_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_tool_desc_lbl.add_theme_font_override("font", sans)
	tool_vb.add_child(_tool_desc_lbl)
	return left


## Tall centre stage (KF03): the thief fills the column between loadout and
## customization, not a letterboxed strip above the loadout.
func _build_preview_panel() -> VBoxContainer:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 4)
	var prev_hdr: Label = Label.new()
	prev_hdr.text = "WARDROBE — DRAG TO ROTATE"
	prev_hdr.add_theme_font_size_override("font_size", 13)
	prev_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	var sans: Font = ThemeScript.font_sans()
	if sans != null:
		prev_hdr.add_theme_font_override("font", sans)
	panel.add_child(prev_hdr)
	var svc: SubViewportContainer = SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.custom_minimum_size = Vector2(360, 300)
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(svc)
	var sv: SubViewport = SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(sv)
	_setup_preview_world(sv)
	svc.gui_input.connect(_on_preview_gui_input)
	return panel


func _build_right_panel() -> PanelContainer:
	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()
	var right_card: PanelContainer = PanelContainer.new()
	right_card.custom_minimum_size = Vector2(292, 0)
	right_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_card.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(1, 6, ThemeScript.TEAL_PANEL_BG, 16))
	ThemeScript.add_teal_filigree(right_card, 3.0, 14.0)
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	right_card.add_child(right)
	var cust_hdr: Label = Label.new()
	cust_hdr.text = "CUSTOMIZATION"
	cust_hdr.add_theme_font_size_override("font_size", 18)
	cust_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		cust_hdr.add_theme_font_override("font", serif)
	right.add_child(cust_hdr)
	right.add_child(ThemeScript.teal_divider())
	var head_hdr: Label = Label.new()
	head_hdr.text = "Head"
	head_hdr.add_theme_font_size_override("font_size", 17)
	head_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		head_hdr.add_theme_font_override("font", serif)
	right.add_child(head_hdr)
	# KF03/KF04 cite: framed thumbnail card for the equipped Head. The art is
	# the authored Black Market reward icon for that outfit row (the same
	# texture the shipped table draws); click cycles the DT outfit rows.
	_head_card = _build_outfit_card(_on_head_card_pressed)
	right.add_child(_head_card)
	var body_hdr: Label = Label.new()
	body_hdr.text = "Body"
	body_hdr.add_theme_font_size_override("font_size", 17)
	body_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		body_hdr.add_theme_font_override("font", serif)
	right.add_child(body_hdr)
	_body_card = _build_outfit_card(_on_body_card_pressed)
	right.add_child(_body_card)
	var card_hdr: Label = Label.new()
	card_hdr.text = "Calling Card"
	card_hdr.add_theme_font_size_override("font_size", 17)
	card_hdr.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		card_hdr.add_theme_font_override("font", serif)
	right.add_child(card_hdr)
	_card_card = _build_outfit_card(_on_card_card_pressed)
	right.add_child(_card_card)
	_desc_lbl = Label.new()
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_lbl.max_lines_visible = 3
	_desc_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_desc_lbl.add_theme_font_size_override("font_size", 12)
	_desc_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_desc_lbl.add_theme_font_override("font", sans)
	right.add_child(_desc_lbl)
	_hint_lbl = Label.new()
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.add_theme_font_size_override("font_size", 11)
	_hint_lbl.add_theme_color_override("font_color", ThemeScript.PINK_HINT)
	right.add_child(_hint_lbl)
	# KF03 cite: BACK [ESC] is the only action (bottom-right). A dedicated APPLY
	# button is not in the shipped frame; BACK commits the selection.
	return right_card


## Framed outfit card: authored reward icon + DT display name + level tag.
func _build_outfit_card(on_pressed: Callable) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(0, 54)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 12)
	btn.clip_text = true
	ThemeScript.style_teal_tab(btn, true)
	btn.pressed.connect(on_pressed)
	return btn


## P2-8: removed dead _panel_style helper (all call sites use
## ThemeScript.teal_panel_style directly). Both preview SubViewports already
## render UPDATE_WHEN_VISIBLE and _process early-returns when hidden, so no
## per-frame cost accrues while the wardrobe is closed.


## KF03/KF04 cite: warm practical-lit dressing-room staging. Exact rig
## numbers are port-authored (standing HARD_LIMIT 5.2: no UMG/light values in
## cooked JSON), but the room palette follows the reference's walnut panelling,
## dresser, rug and warm wall lamp instead of a grey plane on black.
func _setup_preview_world(sv: SubViewport) -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.030, 0.026)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.40, 0.28)
	env.ambient_light_energy = 0.98
	env.tonemap_exposure = 1.12
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.06
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	sv.add_child(world_env)

	var key: SpotLight3D = SpotLight3D.new()
	key.name = "WardrobeKey"
	key.light_color = Color(1.0, 0.88, 0.72)
	key.light_energy = 3.2
	key.spot_range = 9.0
	key.spot_angle = 42.0
	key.shadow_enabled = true
	key.position = Vector3(2.4, 3.1, 2.8)
	sv.add_child(key)
	key.look_at_from_position(key.position, Vector3(0.0, 1.15, 0.0))

	var fill: OmniLight3D = OmniLight3D.new()
	fill.light_color = Color(1.0, 0.70, 0.44)
	fill.light_energy = 1.1
	fill.omni_range = 6.0
	fill.position = Vector3(-2.0, 2.1, 1.8)
	sv.add_child(fill)

	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.light_color = Color(0.52, 0.62, 0.90)
	rim.light_energy = 0.55
	rim.rotation_degrees = Vector3(-24.0, 158.0, 0.0)
	sv.add_child(rim)

	_build_dressing_room(sv)

	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	_turntable.rotation = Vector3(_pitch, _yaw, 0.0)
	sv.add_child(_turntable)
	var cam: Camera3D = Camera3D.new()
	cam.name = "WardrobePreviewCam"
	cam.position = Vector3(0.0, 1.15, 3.4)
	cam.fov = 36.0
	cam.current = true
	sv.add_child(cam)
	# Godot 4.7: WorldEnvironment is missed inside own-world SubViewports; bind
	# the environment to the camera after it enters the tree.
	cam.environment = env
	cam.look_at_from_position(cam.position, Vector3(0.0, 1.0, 0.0))
	_preview_cam = cam


## Warm room shell built from primitive boxes: walnut back/side walls, plank
## floor, rug, dresser and wall lamp. Kept in-scope (no level load) so the
## wardrobe stays a lightweight canvas-layer screen.
func _build_dressing_room(sv: SubViewport) -> void:
	var room: Node3D = Node3D.new()
	room.name = "DressingRoom"
	sv.add_child(room)
	var floor_col: Color = Color(0.145, 0.095, 0.065)
	var wall_col: Color = Color(0.130, 0.078, 0.052)
	var trim_col: Color = Color(0.205, 0.126, 0.080)
	_add_room_box(room, Vector3(8.0, 0.10, 7.4), Vector3(0.0, -0.05, 0.2), floor_col, 0.86)
	_add_room_box(room, Vector3(2.6, 0.025, 1.9), Vector3(0.0, 0.015, 0.45), Color(0.235, 0.075, 0.060), 0.95)
	_add_room_box(room, Vector3(8.0, 3.8, 0.12), Vector3(0.0, 1.9, -2.4), wall_col, 0.92)
	_add_room_box(room, Vector3(0.12, 3.8, 7.4), Vector3(-3.1, 1.9, 0.2), wall_col.darkened(0.12), 0.94)
	_add_room_box(room, Vector3(0.12, 3.8, 7.4), Vector3(3.1, 1.9, 0.2), wall_col.darkened(0.12), 0.94)
	# Vertical panelling battens + chair rail / baseboard.
	for i: int in range(8):
		var x: float = -2.8 + float(i) * 0.8
		_add_room_box(room, Vector3(0.055, 3.5, 0.035), Vector3(x, 1.75, -2.32), trim_col, 0.80)
	_add_room_box(room, Vector3(7.6, 0.10, 0.055), Vector3(0.0, 0.95, -2.31), Color(0.085, 0.050, 0.033), 0.72)
	_add_room_box(room, Vector3(7.6, 0.14, 0.07), Vector3(0.0, 0.07, -2.31), Color(0.085, 0.050, 0.033), 0.72)
	# Dresser on the right, matching the reference's chest of drawers.
	_add_room_box(room, Vector3(1.7, 1.05, 0.60), Vector3(1.95, 0.525, -1.45), Color(0.145, 0.083, 0.055), 0.78)
	_add_room_box(room, Vector3(1.82, 0.07, 0.68), Vector3(1.95, 1.085, -1.45), trim_col, 0.62)
	for d: int in range(3):
		var dy: float = 0.24 + float(d) * 0.29
		_add_room_box(room, Vector3(1.42, 0.22, 0.035), Vector3(1.95, dy, -1.13), Color(0.180, 0.108, 0.070), 0.70)
		_add_room_box(room, Vector3(0.11, 0.03, 0.030), Vector3(1.95, dy, -1.10), Color(0.60, 0.44, 0.20), 0.35, true)
	# Warm wall lamp above the dresser: fixture, glowing globe + practical.
	_add_room_box(room, Vector3(0.16, 0.28, 0.09), Vector3(2.52, 1.95, -2.31), Color(0.42, 0.30, 0.14), 0.40, true)
	var globe: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	globe.mesh = sphere
	var glow_mat: StandardMaterial3D = StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.78, 0.48)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.62, 0.30)
	glow_mat.emission_energy_multiplier = 3.0
	globe.material_override = glow_mat
	globe.position = Vector3(2.52, 1.78, -2.19)
	room.add_child(globe)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.64, 0.36)
	lamp.light_energy = 2.6
	lamp.omni_range = 5.5
	lamp.position = Vector3(2.35, 1.75, -1.75)
	room.add_child(lamp)


func _add_room_box(parent: Node, box_size: Vector3, pos: Vector3, color: Color, roughness: float, metallic: bool = false) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = box_size
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 1.0 if metallic else 0.0
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## KF03/KF04 cite: tool tooltip-card staging (3D model + name + desc).
## Port-authored numbers (standing HARD_LIMIT 5.2).
func _setup_tool_world(sv: SubViewport) -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.075, 0.052, 0.040)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.42, 0.28)
	env.ambient_light_energy = 0.95
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	sv.add_child(world_env)
	_add_room_box(sv, Vector3(3.2, 2.2, 0.08), Vector3(0.0, 1.0, -0.8), Color(0.13, 0.078, 0.052), 0.9)
	_add_room_box(sv, Vector3(3.2, 0.08, 2.0), Vector3(0.0, -0.05, 0.2), Color(0.145, 0.095, 0.065), 0.86)
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
	cam.environment = env
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.25, 0.0))
	_tool_cam = cam


func _frame_tool_camera() -> void:
	if _tool_cam == null or _tool_holder == null or not is_instance_valid(_tool_cam) or not is_instance_valid(_tool_holder):
		return
	# The gallery is deferred: a close in the same frame removes the SubViewport
	# before this runs, and global transforms are invalid outside the tree.
	if not _tool_holder.is_inside_tree() or not _tool_cam.is_inside_tree():
		return
	var box: AABB = AABB()
	var have: bool = false
	var inv: Transform3D = _tool_holder.global_transform.affine_inverse()
	for node: Node in _tool_holder.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		var ab: AABB = xf * mi.get_aabb()
		if not have:
			box = ab
			have = true
		else:
			box = box.merge(ab)
	if not have:
		return
	var center: Vector3 = _tool_holder.global_transform * box.get_center()
	var max_dim: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	max_dim = maxf(max_dim, 0.15)
	var fov: float = deg_to_rad(_tool_cam.fov)
	var dist: float = (max_dim * 0.5) / tan(fov * 0.5) * 1.25
	var pos: Vector3 = center + Vector3(0.0, max_dim * 0.18, dist)
	_tool_cam.position = pos
	_tool_cam.look_at_from_position(pos, center)


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
		_set_hint("The Chameleon is locked. Unlock it in the Black Market (£10,000, Contract 3).")
		return
	_stash_slots()
	_thief_id = target
	_set_hint("")
	_refresh_thief_ui()


## The authored Thief.Chameleon gate lives in SaveSystem (Contract 3, not any
## completed contract).
func _is_thief_unlocked(thief: String) -> bool:
	return SaveSystem.is_thief_unlocked(thief)


func _set_hint(text: String) -> void:
	if _hint_lbl != null:
		_hint_lbl.text = text


func _on_slot_pressed(idx: int) -> void:
	if idx < 0 or idx >= SLOT_COUNT:
		return
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("click")
	_slot_index = idx
	if _is_signature_slot(idx):
		_set_hint("Signature Tools cannot be swapped out")
	else:
		_set_hint("")
	_refresh_tool_ui()


func _on_candidate_pressed(save_id: String) -> void:
	var tool: Dictionary = _tool(save_id)
	if tool.is_empty():
		return
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("click")
	_slot_index = _current_slot_for_preview()
	var target: int = _slot_index
	if _is_signature_slot(target):
		# A signature slot cannot be overwritten: the shipped frame keeps the
		# candidate row closed for it, so a click is a hint only.
		_set_hint("Signature Tools cannot be swapped out")
		_refresh_tool_ui()
		return
	if not _is_tool_owned(tool):
		var reason: String = str(tool.get("condition", ""))
		_set_hint(("Locked - %s" % reason) if reason != "" else "Locked - not owned")
		_refresh_tool_ui()
		return
	# Equipping a tool that already lives in the other swappable slot swaps the
	# two, so a loadout never holds the same tool twice.
	for i: int in range(SLOT_COUNT):
		if i == target or _is_signature_slot(i):
			continue
		if _slots[i] == save_id:
			_slots[i] = _slots[target]
			break
	_slots[target] = save_id
	_set_hint("")
	_refresh_tool_ui()


## The slot whose tool the preview card shows. Once a swappable slot is
## selected it stays selected; otherwise the first non-empty slot.
func _current_slot_for_preview() -> int:
	return clampi(_slot_index, 0, SLOT_COUNT - 1)


func _refresh_tool_ui() -> void:
	if _slots.size() != SLOT_COUNT:
		_slots = _default_slots()
	# Slot tiles: authored icon, signature grey lock, unowned pink lock.
	for i: int in range(_slot_btns.size()):
		var b: Button = _slot_btns[i]
		b.button_pressed = (i == _slot_index)
		ThemeScript.style_teal_tab(b, i == _slot_index)
		var tool: Dictionary = _tool(_slots[i]) if i < _slots.size() else {}
		if i < _slot_icons.size():
			var icon_path: String = str(tool.get("icon", ""))
			var tex: Texture2D = null
			if icon_path != "" and ResourceLoader.exists(icon_path):
				var res: Resource = ResourceLoader.load(icon_path)
				if res is Texture2D:
					tex = res as Texture2D
			_slot_icons[i].texture = tex
			_slot_icons[i].visible = tex != null
		if i < _slot_locks.size():
			if _is_signature_slot(i):
				_slot_locks[i].visible = true
				_slot_locks[i].modulate = ThemeScript.TEAL_MUTED
			else:
				_slot_locks[i].visible = not _is_tool_owned(tool)
				_slot_locks[i].modulate = ThemeScript.PINK_LOCKED
	# Candidate row: only for a swappable slot (KF04 expands slot 3).
	var candidates: Array[Dictionary] = _candidate_tools()
	_cells_row.visible = not _is_signature_slot(_slot_index)
	for child: Node in _cells_row.get_children():
		child.queue_free()
	_cell_btns.clear()
	_cell_locks.clear()
	for tool: Dictionary in candidates:
		_add_candidate_cell(_cells_row, tool)
	for i: int in range(_cell_btns.size()):
		if i < _cell_locks.size():
			_cell_locks[i].visible = not _is_tool_owned(candidates[i])
		_cell_btns[i].button_pressed = str(candidates[i].get("id", "")) == _slots[_slot_index]
		ThemeScript.style_teal_tab(_cell_btns[i], str(candidates[i].get("id", "")) == _slots[_slot_index])
	# 3D tool preview + authored name/description/condition.
	var shown: Dictionary = _tool(_slots[_current_slot_for_preview()])
	if shown.is_empty() and not _is_signature_slot(_slot_index) and not candidates.is_empty():
		shown = candidates[0]
	if _tool_holder != null and is_instance_valid(_tool_holder):
		for c: Node in _tool_holder.get_children():
			_tool_holder.remove_child(c)
			c.queue_free()
		var mesh_path: String = str(shown.get("mesh", ""))
		var node: Node = _load_model(mesh_path)
		if node != null:
			_tool_holder.add_child(node)
			_bind_preview_materials(node, _glb_to_ue_mesh(mesh_path))
			call_deferred("_frame_tool_camera")
	if _tool_name_lbl != null:
		_tool_name_lbl.text = str(shown.get("name", "Empty slot"))
	if _tool_cond_lbl != null:
		var cond: String = str(shown.get("condition", ""))
		if shown.is_empty():
			_tool_cond_lbl.text = "Select a tool below to fill this slot"
		elif _is_tool_owned(shown):
			_tool_cond_lbl.text = cond
		else:
			_tool_cond_lbl.text = ("Locked - %s" % cond) if cond != "" else "Locked - not owned"
	if _tool_desc_lbl != null:
		_tool_desc_lbl.text = str(shown.get("desc", ""))


func _on_body_card_pressed() -> void:
	_cycle_outfit("Body")


func _on_head_card_pressed() -> void:
	_cycle_outfit("Head")


func _on_card_card_pressed() -> void:
	_cycle_outfit("CallingCard")


## KF03/KF04 cite: a card click steps to the next DT outfit in that slot
## (54-row table: Spider 20 Head / 3 Body / 5 CallingCard, Chameleon
## 18 Head / 3 Body / 5 CallingCard). Replaces the OptionButton dropdowns.
func _cycle_outfit(slot: String) -> void:
	var keys: Array[String] = _head_keys
	var current: String = _head
	if slot == "Body":
		keys = _body_keys
		current = _body
	elif slot == "CallingCard":
		keys = _card_keys
		current = _card
	if keys.is_empty():
		return
	var next: int = (keys.find(current) + 1) % keys.size()
	if slot == "Body":
		_body = keys[next]
	elif slot == "CallingCard":
		_card = keys[next]
	else:
		_head = keys[next]
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("click")
	_update_desc()
	_update_outfit_cards()
	_rebuild_figure()


## DT cite: "Unlocked at Level N" parsed from each row's LocalizedString
## description; base outfits carry no level tag.
func _outfit_level_tag(key: String) -> String:
	var desc: String = _display_desc(key)
	var re: RegEx = RegEx.new()
	if re.compile("Level (\\d+)") == OK:
		var m: RegExMatch = re.search(desc)
		if m != null:
			return " · Lv " + m.get_string(1)
	return ""


## KF03/KF04 cite: one framed thumbnail card per Head / Body / CallingCard
## slot. The icon is the authored Black Market reward art for that outfit row
## when the row is in the catalog (same texture the shipped table draws);
## otherwise the card is name-only.
func _update_outfit_cards() -> void:
	_update_outfit_card(_head_card, _head)
	_update_outfit_card(_body_card, _body)
	_update_outfit_card(_card_card, _card)


func _update_outfit_card(btn: Button, key: String) -> void:
	if btn == null:
		return
	btn.text = _display_name(key) + _outfit_level_tag(key)
	var entry: Dictionary = {}
	if _catalog != null and _catalog.is_available() and key != "":
		entry = _catalog.entry(key)
	btn.icon = CatalogScript.icon_texture(entry) if not entry.is_empty() else null


func _refresh_thief_ui() -> void:
	_collect_slots()
	if not _body_keys.is_empty() and not _body_keys.has(_body):
		_body = _body_keys[0]
	if not _head_keys.is_empty() and not _head_keys.has(_head):
		_head = _head_keys[0]
	if not _card_keys.is_empty() and not _card_keys.has(_card):
		_card = _card_keys[0]
	_sync_slots_for_thief()
	_refresh_portraits()
	_update_outfit_cards()
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
		_apply_preview_idle(body_node)
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
	call_deferred("_frame_preview_camera")


## Auto-frames the preview camera from the composed body+head+card bounds in
## turntable space, so the thief fills the tall centre stage instead of sitting
## small in a wide letterbox. Height-fit uses the camera's vertical FOV.
func _frame_preview_camera() -> void:
	if _preview_cam == null or _turntable == null or not is_instance_valid(_preview_cam) or not is_instance_valid(_turntable):
		return
	if not _turntable.is_inside_tree() or not _preview_cam.is_inside_tree():
		return
	var box: AABB = AABB()
	var have: bool = false
	var inv: Transform3D = _turntable.global_transform.affine_inverse()
	for node: Node in _turntable.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		var ab: AABB = xf * mi.get_aabb()
		if not have:
			box = ab
			have = true
		else:
			box = box.merge(ab)
	if not have:
		return
	var center: Vector3 = box.get_center()
	var height: float = maxf(box.size.y, 0.5)
	var fov: float = deg_to_rad(_preview_cam.fov)
	var dist: float = (height * 0.5) / tan(fov * 0.5) * 1.12
	dist = clampf(dist, 1.8, 7.0)
	_preview_cam.position = Vector3(center.x, center.y + height * 0.06, center.z + dist)
	_preview_cam.look_at_from_position(_preview_cam.position, Vector3(center.x, center.y - height * 0.02, center.z))


func _apply_preview_idle(root: Node) -> void:
	var skels: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0] as Skeleton3D
	if skel == null or skel.get_parent() == null:
		return
	var alib: GuardAnimationLibrary = GuardAnimLibScript.new()
	if not alib.setup("club", skel):
		return
	var anim: Animation = alib._retarget_general("AN_ThiefNisha_WardrobeIdle", true, true, true)
	if anim == null:
		anim = alib._retarget_general("AN_GuardEnforcer_NeutralFresh_Idle", true, true, true)
	if anim == null:
		anim = alib._retarget_general("AN_ThiefNisha_Unarmed_StandIdle", true, true, true)
	if anim == null:
		return
	var ap := AnimationPlayer.new()
	ap.name = "WardrobePreviewIdle"
	root.add_child(ap)
	ap.root_node = ap.get_path_to(skel.get_parent())
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", anim)
	ap.add_animation_library("", lib)
	ap.play("idle")


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
	var saved_thief: String = str(GameState.thief_id)
	if THIEF_IDS.has(saved_thief):
		_thief_id = saved_thief
	var loadout: Dictionary = SaveSystem.get_loadout(_thief_id)
	_body = str(loadout.get("body", ""))
	_head = str(loadout.get("head", ""))
	_card = str(loadout.get("calling_card", ""))
	_slots = _normalize_slots(loadout.get("tools", []))
	_slot_index = 0
	_slots_by_thief[_thief_id] = _slots.duplicate()


## Normalize a persisted 4-entry tool array to KF03 semantics: the signature
## slots are fixed to this thief's signature tools, and the swappable slots take
## the saved non-signature tools in order (a legacy loadout's arbitrary four
## tools therefore keep at most two swappable ones), defaulting to Smoke Bomb.
func _normalize_slots(saved: Variant) -> Array[String]:
	var defaults: Array[String] = _default_slots()
	var sigs: Array[String] = _signatures()
	var swappable: Array[String] = []
	if saved is Array:
		for id_v: Variant in saved as Array:
			var id: String = str(id_v).strip_edges()
			if id == "" or sigs.has(id) or swappable.has(id):
				continue
			if _tool(id).is_empty():
				continue
			swappable.append(id)
	var out: Array[String] = defaults.duplicate()
	if swappable.size() >= 1:
		out[1] = swappable[0]
	if swappable.size() >= 2:
		out[2] = swappable[1]
	return out


## Remember the working slots before the panel switches thief.
func _stash_slots() -> void:
	if _slots.size() == SLOT_COUNT:
		_slots_by_thief[_thief_id] = _slots.duplicate()


## Keep per-thief slot edits while the panel is open; switching thieves swaps
## the working set instead of losing the other thief's changes.
func _sync_slots_for_thief() -> void:
	if _slots_by_thief.is_empty():
		_slots_by_thief[_thief_id] = _slots.duplicate() if _slots.size() == SLOT_COUNT else _default_slots()
		return
	var saved_v: Variant = _slots_by_thief.get(_thief_id, null)
	if saved_v is Array:
		_slots = _normalize_slots(saved_v)
	else:
		_slots = _default_slots()
	_slot_index = 0


func _apply_and_close(should_emit: bool) -> void:
	GameState.thief_id = _thief_id
	GameState.outfit_body = _short_name(_body)
	GameState.outfit_head = _short_name(_head)
	GameState.calling_card = _short_name(_card)
	_slots_by_thief[_thief_id] = _slots.duplicate()
	var active_id: String = ""
	var active_idx: int = 0
	for i: int in range(_slots.size()):
		if _slots[i] != "":
			active_id = _slots[i]
			active_idx = i
			break
	var loadout: Dictionary = {
		"head": _head,
		"body": _body,
		"calling_card": _card,
		"tools": _slots.duplicate(),
		"active_tool": active_idx,
		"active_tool_id": active_id if active_id != "" else "zipwire",
	}
	SaveSystem.set_loadout(_thief_id, loadout)
	SaveSystem.data.erase("loadout")
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
