extends CanvasLayer
## Diegetic Mission Selector (Thieves' Den Map Table) for the Thieves' Den hub.
## Left: scrollable contract list from GameData.contracts. Right: selected
## contract details (splash, description, clue intel), difficulty selector,
## 2P co-op host/join controls, deploy + close actions.

signal deploy_requested(contract_order: int, map_id: String)
signal closed()

const SPLASH_CANDIDATES: Array[String] = [
	"res://assets/ue/Content/Art/UI/MapSplash_Guildhall.png",
	"res://assets/ue/Content/Art/UI/T_MapBuilding_OldManor_D.png",
	"res://assets/ue/Raw/Art/UI/Map/Textures/MapSplash_Guildhall.png",
	"res://assets/ue/Raw/Art/UI/Map/Textures/T_MapBuilding_OldManor_D.png",
]

var selected_order: int = 1
var selected_map_id: String = ""

var _contracts: Array[Dictionary] = []
var _list: ItemList
var _splash_rect: TextureRect
var _title_lbl: Label
var _detail_lbl: Label
var _intel_lbl: Label
var _diff_opt: OptionButton
var _net_status: Label
var _ip_edit: LineEdit


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_collect_contracts()
	_build_ui()
	_refresh_list()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Instance helper: show the table and take mouse control.
func open_table() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_list()


## Instance helper: restore mouse, emit closed, hide.
func close_table() -> void:
	_close_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_ui()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo and kev.keycode == KEY_ESCAPE:
			_close_ui()
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
	panel.custom_minimum_size = Vector2(1020, 640)
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
	title.text = "MAP TABLE — CONTRACT SELECTOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	vb.add_child(title)

	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(split)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(360, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_contract_selected)
	split.add_child(_list)

	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)

	_splash_rect = TextureRect.new()
	_splash_rect.custom_minimum_size = Vector2(480, 180)
	_splash_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_splash_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	right.add_child(_splash_rect)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 22)
	_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	right.add_child(_title_lbl)

	_detail_lbl = Label.new()
	_detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_lbl.add_theme_font_size_override("font_size", 15)
	_detail_lbl.add_theme_color_override("font_color", Color(0.86, 0.84, 0.76))
	right.add_child(_detail_lbl)

	_intel_lbl = Label.new()
	_intel_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intel_lbl.add_theme_font_size_override("font_size", 14)
	_intel_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88))
	right.add_child(_intel_lbl)

	var diff_row: HBoxContainer = HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 10)
	right.add_child(diff_row)
	var diff_lbl: Label = Label.new()
	diff_lbl.text = "Difficulty:"
	diff_lbl.add_theme_font_size_override("font_size", 16)
	diff_row.add_child(diff_lbl)
	_diff_opt = OptionButton.new()
	_diff_opt.add_item("Novice (1)", 1)
	_diff_opt.add_item("Thief (2)", 2)
	_diff_opt.add_item("Master Thief (3)", 3)
	_diff_opt.item_selected.connect(_on_difficulty_selected)
	diff_row.add_child(_diff_opt)

	var coop_row: HBoxContainer = HBoxContainer.new()
	coop_row.add_theme_constant_override("separation", 10)
	right.add_child(coop_row)
	var host_btn: Button = Button.new()
	host_btn.text = "Host Co-op"
	host_btn.pressed.connect(_on_host_pressed)
	coop_row.add_child(host_btn)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(130, 0)
	coop_row.add_child(_ip_edit)
	var join_btn: Button = Button.new()
	join_btn.text = "Join Co-op"
	join_btn.pressed.connect(_on_join_pressed)
	coop_row.add_child(join_btn)
	_net_status = Label.new()
	_net_status.text = "Solo Mode"
	_net_status.add_theme_font_size_override("font_size", 14)
	coop_row.add_child(_net_status)

	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 12)
	vb.add_child(bottom)
	var deploy_btn: Button = Button.new()
	deploy_btn.text = "DEPLOY CONTRACT"
	deploy_btn.custom_minimum_size = Vector2(220, 48)
	deploy_btn.pressed.connect(_on_deploy_pressed)
	bottom.add_child(deploy_btn)
	var close_btn: Button = Button.new()
	close_btn.text = "CLOSE [ESC]"
	close_btn.custom_minimum_size = Vector2(160, 48)
	close_btn.pressed.connect(_on_close_pressed)
	bottom.add_child(close_btn)


func _collect_contracts() -> void:
	_contracts.clear()
	var raw_var: Variant = GameData.contracts
	if raw_var is Array:
		var raw: Array = raw_var as Array
		for c: Variant in raw:
			if c is Dictionary:
				_contracts.append((c as Dictionary).duplicate())
	_contracts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))


func _refresh_list() -> void:
	if _list == null:
		return
	_list.clear()
	if _contracts.is_empty():
		_collect_contracts()
	var sel_idx: int = 0
	for i: int in range(_contracts.size()):
		var c: Dictionary = _contracts[i]
		var order: int = int(c.get("order", 0))
		var disp: Dictionary = GameData.get_contract_display(order)
		var title_text: String = str(disp.get("title", c.get("id", "Contract")))
		var map_text: String = str(c.get("map_id", "")).to_upper()
		_list.add_item("#%02d  %s  (%s)" % [order, title_text, map_text])
		if order == selected_order:
			sel_idx = i
	if _list.item_count > 0:
		var target: int = clampi(sel_idx, 0, _list.item_count - 1)
		_list.select(target)
		_on_contract_selected(target)
	var diff_idx: int = clampi(int(GameState.difficulty) - 1, 0, 2)
	if _diff_opt != null and _diff_opt.item_count == 3:
		_diff_opt.select(diff_idx)


func _on_contract_selected(idx: int) -> void:
	if idx < 0 or idx >= _contracts.size():
		return
	var c: Dictionary = _contracts[idx]
	selected_order = int(c.get("order", 1))
	selected_map_id = str(c.get("map_id", ""))
	_refresh_details(c)


func _refresh_details(c: Dictionary) -> void:
	var disp: Dictionary = GameData.get_contract_display(selected_order)
	var title_text: String = str(disp.get("title", c.get("id", "Contract")))
	_title_lbl.text = "#%02d  %s" % [selected_order, title_text]
	var map_text: String = str(disp.get("location", c.get("map_id", "")))
	var desc_text: String = str(disp.get("description", ""))
	var quest_text: String = str(disp.get("quest_item", ""))
	_detail_lbl.text = "Target: %s\nLocation: %s\n\n%s" % [quest_text, map_text, desc_text]
	var clue_text: String = "• Reconnoiter the landmark for clues."
	var clues_var: Variant = disp.get("clue_facts", [])
	if clues_var is Array and not (clues_var as Array).is_empty():
		var parts: Array[String] = []
		for clue: Variant in (clues_var as Array):
			parts.append("• " + str(clue))
		clue_text = "\n".join(parts)
	_intel_lbl.text = "Intel:\n" + clue_text
	_update_splash(selected_map_id)


func _update_splash(map_id: String) -> void:
	if _splash_rect == null:
		return
	var tex: Texture2D = _splash_for(map_id)
	if tex != null:
		_splash_rect.texture = tex
		_splash_rect.visible = true
	else:
		_splash_rect.visible = false


func _splash_for(map_id: String) -> Texture2D:
	var ordered: Array[String] = []
	if map_id == "old_manor":
		ordered = [
			"res://assets/ue/Content/Art/UI/T_MapBuilding_OldManor_D.png",
			"res://assets/ue/Content/Art/UI/MapSplash_Guildhall.png",
		]
	else:
		ordered = [
			"res://assets/ue/Content/Art/UI/MapSplash_Guildhall.png",
			"res://assets/ue/Content/Art/UI/T_MapBuilding_OldManor_D.png",
		]
	for extra: String in SPLASH_CANDIDATES:
		if not ordered.has(extra):
			ordered.append(extra)
	for p: String in ordered:
		if ResourceLoader.exists(p):
			var t: Texture2D = ResourceLoader.load(p) as Texture2D
			if t != null:
				return t
	return null


func _on_difficulty_selected(idx: int) -> void:
	GameState.difficulty = clampi(idx + 1, 1, 3)


func _on_host_pressed() -> void:
	var err_code: int = FAILED
	if NetManager.has_method("host_game"):
		err_code = int(NetManager.call("host_game"))
	elif NetManager.has_method("host"):
		err_code = int(NetManager.call("host"))
	if err_code == OK:
		_net_status.text = "Hosting co-op"
	else:
		_net_status.text = "Host failed: %d" % err_code


func _on_join_pressed() -> void:
	var addr: String = _ip_edit.text if _ip_edit != null else "127.0.0.1"
	if addr.strip_edges() == "":
		addr = "127.0.0.1"
	var err_code: int = FAILED
	if NetManager.has_method("join_game"):
		err_code = int(NetManager.call("join_game", addr))
	elif NetManager.has_method("join"):
		err_code = int(NetManager.call("join", addr))
	if err_code == OK:
		_net_status.text = "Connecting to " + addr + "..."
	else:
		_net_status.text = "Join failed: %d" % err_code


func _on_deploy_pressed() -> void:
	deploy_requested.emit(selected_order, selected_map_id)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	visible = false
	queue_free()


func _on_close_pressed() -> void:
	_close_ui()


func _close_ui() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	visible = false
	queue_free()
