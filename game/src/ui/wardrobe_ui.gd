extends CanvasLayer
## Wardrobe / Bureau Character Customizer for the Thieves' Den hub.
## Lets the player pick a thief (Spider / Chameleon / Moth) plus Body outfit,
## Headgear/Mask and Calling Card parsed from DT_CharacterOutfitsMetadata.json,
## then persists the choice to GameState + SaveSystem.

signal closed()

const OUTFITS_JSON_PATH: String = "res://data/generated/tables/Character/Player/DT_CharacterOutfitsMetadata.json"

const PORTRAIT_SPIDER_TASK: String = "res://assets/ue/Content/Art/UI/Portraits/T_portrait_spider.png"
const PORTRAIT_CHAMELEON_TASK: String = "res://assets/ue/Content/Art/UI/Portraits/T_portrait_chameleon.png"
const PORTRAIT_MOTH_TASK: String = "res://assets/ue/Content/Art/UI/Portraits/T_portrait_moth.png"
const PORTRAIT_SPIDER_RAW: String = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_spider.png"
const PORTRAIT_CHAMELEON_RAW: String = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_chameleon.png"

const THIEF_IDS: Array[String] = ["spider", "chameleon", "moth"]
const THIEF_LABELS: Array[String] = ["The Spider", "The Chameleon", "The Moth"]

var _thief_id: String = "spider"
var _rows: Dictionary = {}
var _body_keys: Array[String] = []
var _head_keys: Array[String] = []
var _card_keys: Array[String] = []
var _body: String = ""
var _head: String = ""
var _card: String = ""

var _portrait_rect: TextureRect
var _body_opt: OptionButton
var _head_opt: OptionButton
var _card_opt: OptionButton
var _desc_lbl: Label
var _thief_btns: Array[Button] = []


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_thief_id = str(GameState.thief_id) if str(GameState.thief_id) != "" else "spider"
	if not THIEF_IDS.has(_thief_id):
		_thief_id = "spider"
	_rows = _load_outfit_rows()
	_build_ui()
	_load_saved_loadout()
	_refresh_thief_ui()


## Instance helper: show the customizer and take mouse control.
func open_customizer() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_thief_ui()


## Instance helper: persist selection, restore mouse, emit closed, hide.
func close_customizer() -> void:
	_apply_and_close(true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_apply_and_close(true)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo and kev.keycode == KEY_ESCAPE:
			_apply_and_close(true)
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.01, 0.03, 0.82)
	root.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 560)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.045, 0.08, 0.97)
	style.border_color = Color(0.55, 0.45, 0.25, 0.9)
	style.set_border_width_all(2)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title: Label = Label.new()
	title.text = "BUREAU — CHARACTER CUSTOMIZER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	vb.add_child(title)

	var main: HBoxContainer = HBoxContainer.new()
	main.add_theme_constant_override("separation", 24)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(main)

	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	left.add_theme_constant_override("separation", 8)
	main.add_child(left)
	var thief_hdr: Label = Label.new()
	thief_hdr.text = "THIEF"
	thief_hdr.add_theme_font_size_override("font_size", 18)
	left.add_child(thief_hdr)
	for i: int in range(THIEF_IDS.size()):
		var b: Button = Button.new()
		b.text = THIEF_LABELS[i]
		b.toggle_mode = true
		var thief_key: String = THIEF_IDS[i]
		b.pressed.connect(_on_thief_button.bind(thief_key))
		left.add_child(b)
		_thief_btns.append(b)
	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(200, 200)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	left.add_child(_portrait_rect)

	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	main.add_child(right)
	var body_hdr: Label = Label.new()
	body_hdr.text = "BODY OUTFIT"
	right.add_child(body_hdr)
	_body_opt = OptionButton.new()
	_body_opt.item_selected.connect(_on_body_selected)
	right.add_child(_body_opt)
	var head_hdr: Label = Label.new()
	head_hdr.text = "HEADGEAR / MASK"
	right.add_child(head_hdr)
	_head_opt = OptionButton.new()
	_head_opt.item_selected.connect(_on_head_selected)
	right.add_child(_head_opt)
	var card_hdr: Label = Label.new()
	card_hdr.text = "CALLING CARD"
	right.add_child(card_hdr)
	_card_opt = OptionButton.new()
	_card_opt.item_selected.connect(_on_card_selected)
	right.add_child(_card_opt)
	_desc_lbl = Label.new()
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_lbl.add_theme_font_size_override("font_size", 15)
	_desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.80, 0.72))
	right.add_child(_desc_lbl)

	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 12)
	vb.add_child(bottom)
	var apply_btn: Button = Button.new()
	apply_btn.text = "APPLY"
	apply_btn.custom_minimum_size = Vector2(160, 44)
	apply_btn.pressed.connect(func() -> void: _apply_and_close(true))
	bottom.add_child(apply_btn)
	var close_btn: Button = Button.new()
	close_btn.text = "CLOSE [ESC]"
	close_btn.custom_minimum_size = Vector2(160, 44)
	close_btn.pressed.connect(func() -> void: _apply_and_close(true))
	bottom.add_child(close_btn)


func _on_thief_button(thief_key: String) -> void:
	_thief_id = thief_key
	_refresh_thief_ui()


func _on_body_selected(idx: int) -> void:
	if idx >= 0 and idx < _body_keys.size():
		_body = _body_keys[idx]
		_update_desc()


func _on_head_selected(idx: int) -> void:
	if idx >= 0 and idx < _head_keys.size():
		_head = _head_keys[idx]
		_update_desc()


func _on_card_selected(idx: int) -> void:
	if idx >= 0 and idx < _card_keys.size():
		_card = _card_keys[idx]
		_update_desc()


func _refresh_thief_ui() -> void:
	for i: int in range(_thief_btns.size()):
		_thief_btns[i].button_pressed = (THIEF_IDS[i] == _thief_id)
	var tex: Texture2D = _portrait_for(_thief_id)
	if tex != null and _portrait_rect != null:
		_portrait_rect.texture = tex
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


func _portrait_for(thief: String) -> Texture2D:
	var candidates: Array[String] = []
	if thief == "spider":
		candidates = [PORTRAIT_SPIDER_TASK, PORTRAIT_SPIDER_RAW]
	elif thief == "chameleon":
		candidates = [PORTRAIT_CHAMELEON_TASK, PORTRAIT_CHAMELEON_RAW]
	else:
		candidates = [PORTRAIT_MOTH_TASK, PORTRAIT_SPIDER_TASK, PORTRAIT_SPIDER_RAW]
	for p: String in candidates:
		if ResourceLoader.exists(p):
			var t: Texture2D = ResourceLoader.load(p) as Texture2D
			if t != null:
				return t
	return null


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
	if _body_keys.is_empty() and _head_keys.is_empty() and _card_keys.is_empty() and _thief_id == "moth":
		for key_var: Variant in _rows.keys():
			var key: String = str(key_var)
			if not _key_matches_thief(key, "Spider"):
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
	var data_var: Variant = SaveSystem.data.get("loadout", {})
	if data_var is Dictionary:
		var loadout: Dictionary = data_var as Dictionary
		var saved_thief: String = str(loadout.get("thief_id", _thief_id))
		if THIEF_IDS.has(saved_thief):
			_thief_id = saved_thief
		_body = str(loadout.get("body", ""))
		_head = str(loadout.get("head", ""))
		_card = str(loadout.get("calling_card", ""))


func _apply_and_close(should_emit: bool) -> void:
	GameState.thief_id = _thief_id
	var loadout: Dictionary = {
		"thief_id": _thief_id,
		"body": _body,
		"head": _head,
		"calling_card": _card,
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


func _set_game_state_if_present(prop: String, value: Variant) -> void:
	for p: Dictionary in GameState.get_property_list():
		if str(p.get("name", "")) == prop:
			GameState.set(prop, value)
			return
