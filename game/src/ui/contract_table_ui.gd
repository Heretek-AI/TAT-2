extends CanvasLayer
## Diegetic Mission Selector (Thieves' Den Map Table) for the Thieves' Den hub.
## Left: scrollable contract list from GameData.contracts. Right: selected
## contract details (splash, description, clue intel), difficulty selector,
## 2P co-op host/join controls, deploy + close actions.

signal deploy_requested(contract_order: int, map_id: String)
signal mission_selected(contract_order: int, map_id: String, difficulty: int, mode: String)
signal closed()

const MissionPrepUIScript: GDScript = preload("res://src/ui/mission_prep_ui.gd")
const ThemeScript: GDScript = preload("res://src/ui/art_nouveau_theme.gd")
const UIStringsScript: GDScript = preload("res://src/ui/ui_strings.gd")
const FocusNavScript: GDScript = preload("res://src/ui/focus_nav.gd")

const SPLASH_CANDIDATES: Array[String] = [
	"res://assets/ue/Content/Art/UI/MapSplash_Guildhall.png",
	"res://assets/ue/Content/Art/UI/T_MapBuilding_OldManor_D.png",
	"res://assets/ue/Raw/Art/UI/Map/Textures/MapSplash_Guildhall.png",
	"res://assets/ue/Raw/Art/UI/Map/Textures/T_MapBuilding_OldManor_D.png",
]

var selected_order: int = 1
var selected_map_id: String = ""
var coop_mode: String = "Solo"
## Free-play ("Contract Inactive") flag threaded into MissionPrepUI. Default
## false: the Den table keeps normal contract flow unless a caller (QA/test or
## a future free-play entry) opts in.
var free_play: bool = false

var _contracts: Array[Dictionary] = []
var _main_root: Control
var _confirm_root: Control
var _panel: Control = null
var _confirm_lbl: Label
var _confirm_visible: bool = false
var _prep: Control
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
	if AudioManager != null and AudioManager.has_method("wire_hover_sfx"):
		AudioManager.wire_hover_sfx(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ui_sfx(cue: String) -> void:
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui(cue)


## Instance helper: show the table and take mouse control.
func open_table() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ui_sfx("open")
	_refresh_list()
	FocusNavScript.install_and_focus(_panel)


## Instance helper: restore mouse, emit closed, hide.
func close_table() -> void:
	_close_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _confirm_visible:
		_confirm_input(event)
		return
	if event.is_action_pressed("ui_cancel"):
		_close_ui()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo and kev.keycode == KEY_G:
			_start_free_play()
			get_viewport().set_input_as_handled()
			return
		if kev.pressed and not kev.echo and kev.keycode == KEY_ESCAPE:
			_close_ui()
			get_viewport().set_input_as_handled()


## Confirmation-modal keys: [SPACE/F] prepare, [ESC] cancel, [H] difficulty, [R] mode.
func _confirm_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo:
			if kev.keycode == KEY_ESCAPE:
				_hide_confirm()
				get_viewport().set_input_as_handled()
				return
			if kev.keycode == KEY_SPACE or kev.keycode == KEY_F:
				_confirm_prepare()
				get_viewport().set_input_as_handled()
				return
			if kev.keycode == KEY_H:
				_cycle_difficulty()
				get_viewport().set_input_as_handled()
				return
			if kev.keycode == KEY_R:
				_toggle_mode()
				get_viewport().set_input_as_handled()
				return


func _build_ui() -> void:
	var root: Control = Control.new()
	_main_root = root
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
	_panel = panel
	panel.custom_minimum_size = Vector2(1020, 640)
	panel.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(2, 6, ThemeScript.TEAL_PANEL_BG, 20))
	center.add_child(panel)
	ThemeScript.add_teal_filigree(panel)
	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	# W9-P3: the shipped Map Table has no title row (the authored screen opens
	# straight on the contract list), so the port's "MAP TABLE — CONTRACT
	# SELECTOR" banner is deleted rather than translated.
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(split)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(360, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list_style: StyleBoxFlat = ThemeScript.teal_card_style(1, 4, Color(0.028, 0.062, 0.082, 0.92), 8)
	_list.add_theme_stylebox_override("panel", list_style)
	_list.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	_list.add_theme_color_override("font_selected_color", Color(0.98, 1.0, 1.0))
	if sans != null:
		_list.add_theme_font_override("font", sans)
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
	_title_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		_title_lbl.add_theme_font_override("font", serif)
	right.add_child(_title_lbl)

	_detail_lbl = Label.new()
	_detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_lbl.add_theme_font_size_override("font_size", 15)
	_detail_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_detail_lbl.add_theme_font_override("font", sans)
	right.add_child(_detail_lbl)

	_intel_lbl = Label.new()
	_intel_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intel_lbl.add_theme_font_size_override("font_size", 14)
	_intel_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	if sans != null:
		_intel_lbl.add_theme_font_override("font", sans)
	right.add_child(_intel_lbl)

	var diff_row: HBoxContainer = HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 10)
	right.add_child(diff_row)
	var diff_lbl: Label = Label.new()
	diff_lbl.text = UIStringsScript.st_text("ST_ThievesDen", "CityMap.DifficultyHeader", "Difficulty:")
	diff_lbl.add_theme_font_size_override("font_size", 16)
	diff_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	diff_row.add_child(diff_lbl)
	_diff_opt = OptionButton.new()
	# Authored difficulty names; the port's "(n)" index suffix is unchanged text.
	_diff_opt.add_item("%s (1)" % UIStringsScript.st_text("ST_GeneralUI", "Mission.Difficulty.Easy", "Novice"), 1)
	_diff_opt.add_item("%s (2)" % UIStringsScript.st_text("ST_GeneralUI", "Mission.Difficulty.Normal", "Thief"), 2)
	_diff_opt.add_item("%s (3)" % UIStringsScript.st_text("ST_GeneralUI", "Mission.Difficulty.Hard", "Master Thief"), 3)
	ThemeScript.style_teal_option(_diff_opt)
	_diff_opt.item_selected.connect(_on_difficulty_selected)
	diff_row.add_child(_diff_opt)

	var coop_row: HBoxContainer = HBoxContainer.new()
	coop_row.add_theme_constant_override("separation", 10)
	right.add_child(coop_row)
	var host_btn: Button = Button.new()
	# PORT COPY (no authored row): the authored host rows are "Host Co-op (Friends
	# Only)/(Public)"; the port's 2P listen host has neither restriction.
	host_btn.text = UIStringsScript.loc("Host Co-op")
	ThemeScript.style_teal_button(host_btn, false, 20)
	host_btn.pressed.connect(_on_host_pressed)
	coop_row.add_child(host_btn)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(130, 0)
	var ip_style: StyleBoxFlat = ThemeScript.teal_card_style(1, 4, Color(0.04, 0.09, 0.115, 0.94), 6)
	_ip_edit.add_theme_stylebox_override("normal", ip_style)
	_ip_edit.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	coop_row.add_child(_ip_edit)
	var join_btn: Button = Button.new()
	join_btn.text = UIStringsScript.loc("Join Co-op") ## PORT COPY (no authored row)
	ThemeScript.style_teal_button(join_btn, false, 20)
	join_btn.pressed.connect(_on_join_pressed)
	coop_row.add_child(join_btn)
	_net_status = Label.new()
	_net_status.text = UIStringsScript.loc("Solo Mode") ## PORT COPY (no authored row)
	_net_status.add_theme_font_size_override("font_size", 14)
	_net_status.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	coop_row.add_child(_net_status)

	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 12)
	vb.add_child(bottom)
	# Shipped free-play entry (not QA-only): a Contract Inactive Cleanout on the
	# Guildhall. It is a separate button/[G] key, so the normal list selection and
	# its PREPARE/DEPLOY flow are unchanged.
	var free_btn: Button = Button.new()
	# PORT COPY (no authored row): free play is the port's Cleanout entry, labelled
	# with its own name; [G] is the live device glyph.
	free_btn.text = "%s [%s]" % [UIStringsScript.loc("FREE PLAY: GUILDHALL CLEANOUT"), InputGlyphs.key_label("G")]
	free_btn.custom_minimum_size = Vector2(300, 44)
	ThemeScript.style_teal_button(free_btn, false, 20)
	free_btn.pressed.connect(_start_free_play)
	bottom.add_child(free_btn)
	var deploy_btn: Button = Button.new()
	# PORT COPY (no authored row): opens the port's own confirmation step, so it
	# keeps a distinct name from the authored "Prepare for Mission" primary.
	deploy_btn.text = UIStringsScript.loc("DEPLOY CONTRACT").to_upper()
	deploy_btn.custom_minimum_size = Vector2(220, 44)
	ThemeScript.style_teal_button(deploy_btn, true, 20)
	deploy_btn.pressed.connect(_on_deploy_pressed)
	bottom.add_child(deploy_btn)
	var close_btn: Button = Button.new()
	close_btn.text = "%s [%s]" % [
		UIStringsScript.st_upper("ST_Interactables", "PromptClose", "Close"),
		InputGlyphs.text("pause")]
	close_btn.custom_minimum_size = Vector2(160, 44)
	ThemeScript.style_teal_button(close_btn, false, 20)
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
		# UI3-06: the map token is the authored display name, never the raw
		# map id (`GUILDHALL` / `THIEVES_DEN`) the old list printed.
		var map_text: String = _map_display_name(str(c.get("map_id", "")), order)
		_list.add_item("#%02d  %s  (%s)" % [order, title_text, map_text])
		if order == selected_order:
			sel_idx = i
	if _list.item_count > 0:
		var target: int = clampi(sel_idx, 0, _list.item_count - 1)
		_list.select(target)
		_on_contract_selected(target, false)
	var diff_idx: int = clampi(int(GameState.difficulty) - 1, 0, 2)
	if _diff_opt != null and _diff_opt.item_count == 3:
		_diff_opt.select(diff_idx)


func _on_contract_selected(idx: int, play_sfx: bool = true) -> void:
	if idx < 0 or idx >= _contracts.size():
		return
	if play_sfx:
		_ui_sfx("click")
	# A normal contract selection is a normal deploy: drop any free-play mode
	# left over from a cancelled Cleanout prep.
	free_play = false
	var c: Dictionary = _contracts[idx]
	selected_order = int(c.get("order", 1))
	selected_map_id = str(c.get("map_id", ""))
	_refresh_details(c)


func _refresh_details(c: Dictionary) -> void:
	var disp: Dictionary = GameData.get_contract_display(selected_order)
	var title_text: String = str(disp.get("title", c.get("id", "Contract")))
	_title_lbl.text = "#%02d  %s" % [selected_order, title_text]
	var map_text: String = str(disp.get("location", "")).strip_edges()
	if map_text == "" or map_text.to_lower() == str(c.get("map_id", "")).to_lower():
		map_text = _map_display_name(selected_map_id, selected_order)
	var desc_text: String = str(disp.get("description", ""))
	var quest_text: String = str(disp.get("quest_item", ""))
	# PORT COPY (no authored row): the authored contract details are a splash +
	# description; this three-slot summary is the port's own layout.
	_detail_lbl.text = UIStringsScript.loc("Target: %s\nLocation: %s\n\n%s") % [quest_text, map_text, desc_text]
	var clue_text: String = "• Reconnoiter the landmark for clues."
	var clues_var: Variant = disp.get("clue_facts", [])
	if clues_var is Array and not (clues_var as Array).is_empty():
		var parts: Array[String] = []
		for clue: Variant in (clues_var as Array):
			parts.append("• " + str(clue))
		clue_text = "\n".join(parts)
	_intel_lbl.text = UIStringsScript.loc("Intel:\n") + clue_text ## PORT COPY (no authored row)
	_update_splash(selected_map_id)


## UI3-06: authored map names for the contract list/details. The raw map ids
## (`guildhall`, `old_manor`, `thieves_den`) are load keys, never copy.
func _map_display_name(map_id: String, order: int = 0) -> String:
	var mid: String = map_id.strip_edges().to_lower()
	if mid == "guildhall":
		return UIStringsScript.st_upper("ST_MapTool", "Guildhall.MapName", "Constables' Guildhall")
	if mid == "old_manor":
		return UIStringsScript.st_upper("ST_OldManor_map", "OldManor.MapName", "Elway Manor")
	if mid == "thieves_den" or (mid == "" and order <= 1):
		return UIStringsScript.loc("Thieves' Den").to_upper() ## PORT COPY (no authored standalone map-name row; the hub is Thieves' Den)
	if mid == "":
		return UIStringsScript.loc("Contract").to_upper() ## PORT COPY (no authored row)
	return mid.replace("_", " ").to_upper() ## PORT COPY (unknown map key)


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
	# P2-5: non-Manor/Guildhall maps fall back to the mission_prep
	# LOCATION_ART_MAP portraits (jaspering_hall / thieves_den) before hiding.
	var art_fallbacks: Array[String] = [
		"res://assets/ue/Raw/Art/UI/Icons/Rewards/Maps/T_Map_OldManor.png",
		"res://assets/ue/Raw/Art/UI/Shell/MapSplash_Guildhall.png",
		"res://assets/ue/Raw/Art/UI/Shell/SplashScreen/T_loadingScreen_1.png",
		"res://assets/ue/Raw/Art/UI/Shell/SplashScreen/T_loadingScreen_2.png",
	]
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
	for fb: String in art_fallbacks:
		if not ordered.has(fb):
			ordered.append(fb)
	for p: String in ordered:
		if ResourceLoader.exists(p):
			var t: Texture2D = ResourceLoader.load(p) as Texture2D
			if t != null:
				return t
	return null


func _on_difficulty_selected(idx: int) -> void:
	_ui_sfx("click")
	GameState.difficulty = clampi(idx + 1, 1, 3)


func _on_host_pressed() -> void:
	var err_code: int = FAILED
	if NetManager.has_method("host_game"):
		err_code = int(NetManager.call("host_game"))
	elif NetManager.has_method("host"):
		err_code = int(NetManager.call("host"))
	if err_code == OK:
		coop_mode = "Co-op"
		_net_status.text = UIStringsScript.loc("Hosting co-op") ## PORT COPY (no authored row)
		_ui_sfx("confirm")
	else:
		_net_status.text = UIStringsScript.loc("Host failed: %d") % err_code ## PORT COPY (no authored row)
		_ui_sfx("error")


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
		coop_mode = "Co-op"
		_net_status.text = UIStringsScript.loc("Connecting to ") + addr + "..." ## PORT COPY (no authored row)
		_ui_sfx("confirm")
	else:
		_net_status.text = UIStringsScript.loc("Join failed: %d") % err_code ## PORT COPY (no authored row)
		_ui_sfx("error")


func _on_deploy_pressed() -> void:
	_show_confirm()


## Public helper: open the blurred confirmation dialog for the current selection.
func open_confirm() -> void:
	_show_confirm()


func _difficulty_label() -> String:
	var d: int = int(GameState.difficulty)
	if d == 1:
		return "Novice"
	if d == 2:
		return "Thief"
	return "Master Thief"


func _confirm_text() -> String:
	# The authored row separates its lines with \r\n; Labels render \n only.
	return UIStringsScript.st_template("ST_ThievesDen", "CityMap.ConfirmJoinLobby",
		"Join Mission with these settings?\nDifficulty: {difficulty}\nMode: {mode}",
		{"difficulty": _difficulty_label(), "mode": coop_mode}).replace("\r\n", "\n").replace("\r", "\n")


func _show_confirm() -> void:
	if _confirm_root == null:
		_build_confirm()
	_ui_sfx("confirm")
	_refresh_confirm_text()
	# Remember the table row that opened the modal and move focus into it.
	FocusNavScript.remember()
	_confirm_root.visible = true
	_confirm_visible = true
	FocusNavScript.install_and_focus(_confirm_root)


func _hide_confirm(play_sfx: bool = true) -> void:
	if play_sfx:
		_ui_sfx("back")
	_confirm_visible = false
	if _confirm_root != null:
		# Never leave focus trapped in a hidden modal: release it, re-ring the
		# table and put it back on the opener.
		FocusNavScript.release_if_inside(_confirm_root)
		_confirm_root.visible = false
		FocusNavScript.install(_panel)
		FocusNavScript.restore()


func _refresh_confirm_text() -> void:
	if _confirm_lbl != null:
		_confirm_lbl.text = _confirm_text()


func _build_confirm() -> void:
	var dim: Control = Control.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_confirm_root = dim
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.02, 0.62)
	dim.add_child(bg)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	panel.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(2, 6, ThemeScript.TEAL_PANEL_BG, 24))
	center.add_child(panel)
	ThemeScript.add_teal_filigree(panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	_confirm_lbl = Label.new()
	_confirm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_lbl.add_theme_font_size_override("font_size", 20)
	_confirm_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	var serif: Font = ThemeScript.font_serif()
	if serif != null:
		_confirm_lbl.add_theme_font_override("font", serif)
	vb.add_child(_confirm_lbl)
	vb.add_child(ThemeScript.teal_divider())
	var hint: Label = Label.new()
	# PORT COPY (no authored row): the port's own two-toggle confirm hint. [H]/[R]
	# are raw keycodes (no InputMap action), so they stay fixed tokens.
	hint.text = UIStringsScript.loc("[H] Difficulty toggle   ·   [R] Mode toggle   ·   [SPACE/F] PREPARE")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	vb.add_child(hint)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var go_btn: Button = Button.new()
	go_btn.text = InputGlyphs.prompt("jump", UIStringsScript.st_upper("ST_ThievesDen", "CityMap.JoinLobby", "Prepare for Mission"))
	go_btn.custom_minimum_size = Vector2(280, 44)
	ThemeScript.style_teal_button(go_btn, true, 24)
	go_btn.pressed.connect(_confirm_prepare)
	row.add_child(go_btn)
	var cancel_btn: Button = Button.new()
	# "Cancel" is an authored locres source (reverse-map ALL-CAPS normalisation).
	cancel_btn.text = InputGlyphs.prompt("pause", UIStringsScript.loc("CANCEL"))
	cancel_btn.custom_minimum_size = Vector2(160, 44)
	ThemeScript.style_teal_button(cancel_btn, false, 24)
	cancel_btn.pressed.connect(_hide_confirm)
	row.add_child(cancel_btn)
	dim.visible = false
	if AudioManager != null and AudioManager.has_method("wire_hover_sfx"):
		AudioManager.wire_hover_sfx(self)


func _cycle_difficulty() -> void:
	_ui_sfx("click")
	GameState.difficulty = clampi(int(GameState.difficulty) % 3 + 1, 1, 3)
	var idx: int = clampi(int(GameState.difficulty) - 1, 0, 2)
	if _diff_opt != null and _diff_opt.item_count == 3:
		_diff_opt.select(idx)
	_refresh_confirm_text()


func _toggle_mode() -> void:
	_ui_sfx("click")
	if coop_mode == "Solo":
		coop_mode = "Co-op"
	else:
		coop_mode = "Solo"
	if _net_status != null:
		# PORT COPY (no authored row): the port's pending-host/join state line.
		_net_status.text = UIStringsScript.loc("Solo Mode") if coop_mode == "Solo" \
			else UIStringsScript.loc("Co-op Mode (pending host/join)")
	_refresh_confirm_text()


## Confirm: emit the selection flow and open MissionPrepUI on top of the table.
func _confirm_prepare() -> void:
	_hide_confirm(false)
	_ui_sfx("confirm")
	mission_selected.emit(selected_order, selected_map_id, int(GameState.difficulty), coop_mode)
	_open_prep()


## Free play ("Contract Inactive") entry point: Guildhall Cleanout Heist hosted
## on the Guildhall contract order, with no campaign progress. It selects the
## authored Mission.Guildhall.LootTheRoom row (MissionPrepUI's free-play path
## does that by id) and opens prep with free_play = true; the normal list /
## DEPLOY path above is untouched.
func _start_free_play() -> void:
	if _confirm_visible:
		return
	_ui_sfx("confirm")
	free_play = true
	selected_order = int(GameState.FREE_PLAY_CONTRACT_ORDER)
	selected_map_id = "guildhall"
	var sel: Dictionary = {}
	for c: Dictionary in _contracts:
		if int(c.get("order", 0)) == selected_order:
			sel = c
			break
	if not sel.is_empty():
		_refresh_details(sel)
	else:
		_update_splash(selected_map_id)
	mission_selected.emit(selected_order, selected_map_id, int(GameState.difficulty), coop_mode)
	_open_prep()


## Open MissionPrepUI for the current selection, threading the free-play flag.
func _open_prep() -> void:
	var prep: Control = MissionPrepUIScript.new() as Control
	_prep = prep
	add_child(prep)
	# Parentage-side crush guard (godot#86631): prep._ready() runs during
	# add_child while the fresh Control still measures (0,0), and its full-rect
	# anchors must not keep those zero offsets or the backdrop container chain
	# stays (0,0) and crushes the authored 1280x720 SubViewport to the (2,2)
	# floor. Re-assert full-rect here; mission_prep_ui._ensure_stage_size
	# re-checks after layout and on resize.
	prep.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	prep.offset_left = 0.0
	prep.offset_top = 0.0
	prep.offset_right = 0.0
	prep.offset_bottom = 0.0
	if prep.has_signal("ready_pressed"):
		prep.connect("ready_pressed", _on_prep_ready)
	if prep.has_signal("closed"):
		prep.connect("closed", _on_prep_closed)
	if _main_root != null:
		_main_root.visible = false
	if prep.has_method("open_prep"):
		prep.call("open_prep", selected_map_id, int(GameState.difficulty), coop_mode, selected_order, free_play)


func _on_prep_ready(p_map_id: String, p_difficulty: int, p_mode: String, p_order: int) -> void:
	GameState.difficulty = clampi(p_difficulty, 1, 3)
	# T7: the table-local coop_mode never reached GameState — the deploy closure only
	# took (order, map). Persist the prep-confirmed mode here so the deploy closure can
	# carry it across reset_run into the run.
	GameState.active_mission_mode = p_mode
	coop_mode = p_mode
	mission_selected.emit(p_order, p_map_id, int(GameState.difficulty), p_mode)
	deploy_requested.emit(p_order, p_map_id)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(_prep):
		_prep.queue_free()
	_prep = null
	visible = false
	queue_free()


func _on_prep_closed() -> void:
	_prep = null
	# Back out of prep (including a cancelled free-play Cleanout): the table
	# returns to the normal contract flow.
	free_play = false
	if _main_root != null:
		_main_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_list()


func _on_close_pressed() -> void:
	_close_ui()


func _close_ui() -> void:
	FocusNavScript.release_if_inside(_panel)
	_ui_sfx("back")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	visible = false
	queue_free()
