class_name LedgerUI
extends Control
## Journal & Black Market Ledger modal for the Thieves' Den hub.
## Q | E switches tabs. JOURNAL shows level XP + contract cards from GameData
## (with fallback titles offline). BLACK MARKET shows total assets, a selected
## item preview card with BUY, and 4 shop sections. ESC / BACK closes.

signal closed()

const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")

const FALLBACK_CONTRACTS: Array = [
	{"order": 1, "title": "In the Eye of the Beholder", "description": "Steal the Beholder's Eye diamond from the Guildhall vault.", "location": "Constables' Guildhall"},
	{"order": 2, "title": "Into the Lion's Den", "description": "Infiltrate the Guildhall under heightened watch.", "location": "Constables' Guildhall"},
	{"order": 3, "title": "Shadows over Old Manor", "description": "Burgle the Elway Manor gallery without waking the household.", "location": "Elway Manor"},
	{"order": 4, "title": "The Spider's Gambit", "description": "A high-wire score across the rooftops of Kilcairn.", "location": "Kilcairn Rooftops"},
	{"order": 5, "title": "The Chameleon's Masquerade", "description": "Blend in at the masquerade and lift the guest of honour's seal.", "location": "Jaspering Hall"},
	{"order": 6, "title": "The Constable's Due", "description": "Reclaim impounded loot from the constabulary lockup.", "location": "Constables' Guildhall"},
]

const TOOLS: Array = [
	{"id": "zipwire", "name": "Zipwire", "cat": "tools", "cost": 1500, "desc": "Fire a wire to traverse rooftops and gaps in seconds."},
	{"id": "smoke_bomb", "name": "Smoke Bomb", "cat": "tools", "cost": 800, "desc": "Burst of thick smoke. Breaks line of sight to slip away."},
	{"id": "pickpocket_fairy", "name": "Pickpocket Fairy", "cat": "tools", "cost": 2000, "desc": "A nimble fey that lifts keys and coins from the unwary."},
	{"id": "insult_fairy", "name": "Insult Fairy", "cat": "tools", "cost": 2000, "desc": "Taunts guards into abandoning their posts to chase it."},
	{"id": "slither_sap", "name": "Slither Sap", "cat": "tools", "cost": 1200, "desc": "Knockout sap. Short-circuits lanterns and lays out guards."},
]

const PERKS: Array = [
	{"id": "novice_difficulty", "name": "Novice Difficulty", "cat": "perks", "cost": 0, "desc": "Unlocks Novice difficulty contracts. Sharper guards look away."},
	{"id": "thief_difficulty", "name": "Thief Difficulty", "cat": "perks", "cost": 3000, "desc": "Unlocks Thief difficulty contracts and richer purses."},
	{"id": "master_thief_difficulty", "name": "Master Thief Difficulty", "cat": "perks", "cost": 6000, "desc": "Unlocks Master Thief difficulty. The ultimate test."},
	{"id": "guildhall", "name": "Constables' Guildhall", "cat": "perks", "cost": 2500, "desc": "Guild charter: access Guildhall scores on the map table."},
	{"id": "old_manor", "name": "Elway Manor", "cat": "perks", "cost": 2500, "desc": "Guild charter: access Elway Manor scores on the map table."},
	{"id": "spider", "name": "The Spider", "cat": "perks", "cost": 4000, "desc": "Recruit the Spider: unmatched rooftop agility."},
	{"id": "chameleon", "name": "The Chameleon", "cat": "perks", "cost": 4000, "desc": "Recruit the Chameleon: a master of disguise."},
]

const SPIDER_COSMETICS: Array = [
	{"id": "no_hat", "name": "No Hat", "cat": "cosmetics", "cost": 0, "desc": "Travel light. Nothing to snag on the guttering."},
	{"id": "bob_hair", "name": "Bob Hair Style", "cat": "cosmetics", "cost": 500, "desc": "A sharp bob favoured by Kilcairn's daring."},
	{"id": "bowler_hat", "name": "Bowler Hat", "cat": "cosmetics", "cost": 750, "desc": "Respectable by day, larcenous by night."},
	{"id": "top_hat", "name": "Top Hat", "cat": "cosmetics", "cost": 1200, "desc": "Towering style for the conspicuous thief."},
	{"id": "mustache", "name": "Mustache", "cat": "cosmetics", "cost": 400, "desc": "A waxed statement piece."},
	{"id": "full_beard", "name": "Full Beard", "cat": "cosmetics", "cost": 600, "desc": "Hides a multitude of sins."},
	{"id": "glasses", "name": "Glasses", "cat": "cosmetics", "cost": 350, "desc": "Scholarly. Nobody suspects a reader."},
	{"id": "thief_mask", "name": "Thief Mask", "cat": "cosmetics", "cost": 900, "desc": "The classic. Business after dark."},
	{"id": "monocle", "name": "Monocle", "cat": "cosmetics", "cost": 1100, "desc": "Appraise loot at a glance."},
	{"id": "eyepatch", "name": "Eyepatch", "cat": "cosmetics", "cost": 450, "desc": "Depth perception is for the law-abiding."},
]

const CHAMELEON_COSMETICS: Array = [
	{"id": "parted_hair", "name": "Parted Hair", "cat": "cosmetics", "cost": 500, "desc": "Neatly parted. Blends into any crowd."},
	{"id": "cap", "name": "Cap", "cat": "cosmetics", "cost": 350, "desc": "Pulled low over the eyes."},
	{"id": "bowler_hat", "name": "Bowler Hat", "cat": "cosmetics", "cost": 750, "desc": "Respectable by day, larcenous by night."},
	{"id": "top_hat", "name": "Top Hat", "cat": "cosmetics", "cost": 1200, "desc": "Towering style for the conspicuous thief."},
	{"id": "mustache", "name": "Mustache", "cat": "cosmetics", "cost": 400, "desc": "A waxed statement piece."},
	{"id": "thief_mask", "name": "Thief Mask", "cat": "cosmetics", "cost": 900, "desc": "The classic. Business after dark."},
	{"id": "monocle", "name": "Monocle", "cat": "cosmetics", "cost": 1100, "desc": "Appraise loot at a glance."},
	{"id": "eyepatch", "name": "Eyepatch", "cat": "cosmetics", "cost": 450, "desc": "Depth perception is for the law-abiding."},
]

var _tab: int = 0
var _journal_btn: Button
var _market_btn: Button
var _journal_page: VBoxContainer
var _market_page: VBoxContainer
var _level_lbl: Label
var _xp_bar: ProgressBar
var _xp_lbl: Label
var _contracts_box: VBoxContainer
var _assets_lbl: Label
var _preview_title: Label
var _preview_desc: Label
var _preview_status: Label
var _buy_btn: Button
var _market_list: VBoxContainer
var _selected: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if AudioManager != null and AudioManager.has_method("wire_hover_sfx"):
		AudioManager.wire_hover_sfx(self)
	_refresh_journal()
	_refresh_market()
	_show_tab(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Instance helper: show the ledger and take mouse control.
func open_ledger() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("ledger_open")
	_refresh_journal()
	_refresh_market()
	_show_tab(_tab)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_ui()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo:
			if kev.keycode == KEY_ESCAPE:
				_close_ui()
				get_viewport().set_input_as_handled()
			elif kev.keycode == KEY_Q:
				_show_tab(0)
				get_viewport().set_input_as_handled()
			elif kev.keycode == KEY_E:
				_show_tab(1)
				get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.008, 0.012, 0.025, 0.86)
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 660)
	panel.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(2, 6, ThemeScript.TEAL_PANEL_BG, 20))
	center.add_child(panel)
	ThemeScript.add_teal_filigree(panel)
	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vb.add_child(header)
	_journal_btn = Button.new()
	_journal_btn.text = "[Q] JOURNAL"
	_journal_btn.custom_minimum_size = Vector2(200, 42)
	ThemeScript.style_teal_tab(_journal_btn, true)
	_journal_btn.pressed.connect(_show_tab.bind(0))
	header.add_child(_journal_btn)
	_market_btn = Button.new()
	_market_btn.text = "BLACK MARKET [E]"
	_market_btn.custom_minimum_size = Vector2(220, 42)
	ThemeScript.style_teal_tab(_market_btn, false)
	_market_btn.pressed.connect(_show_tab.bind(1))
	header.add_child(_market_btn)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var back_btn: Button = Button.new()
	back_btn.text = "BACK [ESC]"
	back_btn.custom_minimum_size = Vector2(150, 42)
	ThemeScript.style_teal_button(back_btn, false)
	back_btn.pressed.connect(_on_back_pressed)
	header.add_child(back_btn)
	vb.add_child(ThemeScript.teal_divider())

	_journal_page = VBoxContainer.new()
	_journal_page.add_theme_constant_override("separation", 10)
	_journal_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_journal_page)
	_level_lbl = Label.new()
	_level_lbl.add_theme_font_size_override("font_size", 22)
	_level_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		_level_lbl.add_theme_font_override("font", serif)
	_journal_page.add_child(_level_lbl)
	var xp_row: HBoxContainer = HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 10)
	_journal_page.add_child(xp_row)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 22)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.show_percentage = false
	var xp_bg: StyleBoxFlat = StyleBoxFlat.new()
	xp_bg.bg_color = Color(0.03, 0.07, 0.09, 0.95)
	xp_bg.border_color = ThemeScript.TEAL_BORDER
	xp_bg.set_border_width_all(1)
	xp_bg.set_corner_radius_all(3)
	var xp_fg: StyleBoxFlat = StyleBoxFlat.new()
	xp_fg.bg_color = ThemeScript.TEAL
	xp_fg.set_corner_radius_all(2)
	_xp_bar.add_theme_stylebox_override("background", xp_bg)
	_xp_bar.add_theme_stylebox_override("fill", xp_fg)
	xp_row.add_child(_xp_bar)
	_xp_lbl = Label.new()
	_xp_lbl.add_theme_font_size_override("font_size", 15)
	_xp_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_xp_lbl.add_theme_font_override("font", sans)
	xp_row.add_child(_xp_lbl)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal_page.add_child(scroll)
	_contracts_box = VBoxContainer.new()
	_contracts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contracts_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_contracts_box)

	_market_page = VBoxContainer.new()
	_market_page.add_theme_constant_override("separation", 10)
	_market_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_market_page)
	_assets_lbl = Label.new()
	_assets_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_assets_lbl.add_theme_font_size_override("font_size", 20)
	_assets_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		_assets_lbl.add_theme_font_override("font", serif)
	_market_page.add_child(_assets_lbl)
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_market_page.add_child(split)
	var preview: PanelContainer = PanelContainer.new()
	preview.custom_minimum_size = Vector2(300, 0)
	preview.add_theme_stylebox_override("panel", ThemeScript.teal_card_style(1, 5, ThemeScript.TEAL_GROUP_BG, 14))
	ThemeScript.add_teal_filigree(preview, 3.0, 14.0)
	split.add_child(preview)
	var pv: VBoxContainer = VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	preview.add_child(pv)
	_preview_title = Label.new()
	_preview_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_title.add_theme_font_size_override("font_size", 20)
	_preview_title.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		_preview_title.add_theme_font_override("font", serif)
	pv.add_child(_preview_title)
	_preview_desc = Label.new()
	_preview_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_desc.add_theme_font_size_override("font_size", 14)
	_preview_desc.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_preview_desc.add_theme_font_override("font", sans)
	pv.add_child(_preview_desc)
	_preview_status = Label.new()
	_preview_status.add_theme_font_size_override("font_size", 16)
	pv.add_child(_preview_status)
	_buy_btn = Button.new()
	_buy_btn.text = "BUY"
	_buy_btn.custom_minimum_size = Vector2(0, 44)
	ThemeScript.style_teal_button(_buy_btn, true)
	_buy_btn.pressed.connect(_on_buy_pressed)
	pv.add_child(_buy_btn)
	var mscroll: ScrollContainer = ScrollContainer.new()
	mscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(mscroll)
	_market_list = VBoxContainer.new()
	_market_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_list.add_theme_constant_override("separation", 6)
	mscroll.add_child(_market_list)


func _show_tab(idx: int) -> void:
	var changed: bool = clampi(idx, 0, 1) != _tab
	_tab = clampi(idx, 0, 1)
	# S06/S08: tab switch is the crisp radial tab tick, not the generic click.
	if changed and AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("tab")
	if _journal_page != null:
		_journal_page.visible = (_tab == 0)
	if _market_page != null:
		_market_page.visible = (_tab == 1)
	if _journal_btn != null:
		_journal_btn.disabled = (_tab == 0)
		ThemeScript.style_teal_tab(_journal_btn, _tab == 0)
	if _market_btn != null:
		_market_btn.disabled = (_tab == 1)
		ThemeScript.style_teal_tab(_market_btn, _tab == 1)


func _collect_contracts() -> Array:
	var out: Array = []
	var raw: Array = GameData.contracts
	if not raw.is_empty():
		for c: Variant in raw:
			if c is Dictionary:
				var cd: Dictionary = c as Dictionary
				var order: int = int(cd.get("order", 0))
				var disp: Dictionary = GameData.get_contract_display(order)
				out.append({
					"order": order,
					"title": str(disp.get("title", cd.get("id", "Contract %d" % order))),
					"description": str(disp.get("description", "")),
					"location": str(disp.get("location", cd.get("map_id", ""))),
				})
	else:
		for f: Variant in FALLBACK_CONTRACTS:
			out.append((f as Dictionary).duplicate())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	return out


func _is_contract_complete(order: int) -> bool:
	var cc_raw: Variant = SaveSystem.data.get("completed_contracts", {})
	if cc_raw is Dictionary:
		return (cc_raw as Dictionary).has(str(order))
	return false


func _refresh_journal() -> void:
	var prog: Dictionary = SaveSystem.get_level_progress()
	var level: int = int(prog.get("level", 1))
	var in_level: int = int(prog.get("xp_in_level", 0))
	var needed: int = int(prog.get("xp_needed", 500))
	_level_lbl.text = "Level %d" % level
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = float(maxi(1, needed))
	_xp_bar.value = float(in_level)
	_xp_lbl.text = "%d/%d XP" % [in_level, needed]
	for child: Node in _contracts_box.get_children():
		child.queue_free()
	var contracts: Array = _collect_contracts()
	for c: Variant in contracts:
		var cd: Dictionary = c as Dictionary
		var order: int = int(cd.get("order", 0))
		var done: bool = _is_contract_complete(order)
		var card: PanelContainer = PanelContainer.new()
		var cstyle: StyleBoxFlat = ThemeScript.teal_card_style(1, 5, ThemeScript.TEAL_GROUP_BG, 12)
		if done:
			cstyle.border_color = Color(0.32, 0.72, 0.56, 0.85)
		card.add_theme_stylebox_override("panel", cstyle)
		ThemeScript.add_teal_filigree(card, 3.0, 12.0)
		var cv: VBoxContainer = VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		var head: HBoxContainer = HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		cv.add_child(head)
		var t: Label = Label.new()
		t.text = "#%02d  %s" % [order, str(cd.get("title", "Contract"))]
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_theme_font_size_override("font_size", 18)
		t.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE if not done else ThemeScript.TEAL_TEXT)
		head.add_child(t)
		var status: Label = Label.new()
		status.text = "Completed" if done else "Active"
		status.add_theme_font_size_override("font_size", 14)
		status.add_theme_color_override("font_color", Color(0.45, 0.90, 0.65) if done else ThemeScript.TEAL_ACCENT)
		head.add_child(status)
		var loc: String = str(cd.get("location", ""))
		var desc: String = str(cd.get("description", ""))
		if loc != "" or desc != "":
			var d: Label = Label.new()
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.text = ("Location: %s\n" % loc if loc != "" else "") + desc
			d.add_theme_font_size_override("font_size", 14)
			d.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
			cv.add_child(d)
		_contracts_box.add_child(card)


func _sections() -> Array:
	return [
		{"title": "TOOLS", "items": TOOLS},
		{"title": "GUILD PERKS", "items": PERKS},
		{"title": "SPIDER COSMETICS", "items": SPIDER_COSMETICS},
		{"title": "CHAMELEON COSMETICS", "items": CHAMELEON_COSMETICS},
	]


func _refresh_market() -> void:
	_assets_lbl.text = "YOUR TOTAL ASSETS: £ %d" % SaveSystem.get_currency()
	for child: Node in _market_list.get_children():
		child.queue_free()
	var sections: Array = _sections()
	for s: Variant in sections:
		var sd: Dictionary = s as Dictionary
		var hdr: Label = Label.new()
		hdr.text = str(sd.get("title", ""))
		hdr.add_theme_font_size_override("font_size", 17)
		hdr.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
		_market_list.add_child(hdr)
		var grid: GridContainer = GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_market_list.add_child(grid)
		var items: Array = sd.get("items", []) as Array
		for it: Variant in items:
			var item: Dictionary = it as Dictionary
			var b: Button = Button.new()
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0, 38)
			b.text = _item_button_text(item)
			ThemeScript.style_teal_button(b, false)
			b.pressed.connect(_on_item_pressed.bind(item.duplicate()))
			grid.add_child(b)
	if _selected.is_empty():
		var first_tools: Array = TOOLS
		if not first_tools.is_empty():
			_selected = (first_tools[0] as Dictionary).duplicate()
	_refresh_preview()


func _item_button_text(item: Dictionary) -> String:
	var owned: bool = SaveSystem.is_unlocked(str(item.get("cat", "")), str(item.get("id", "")))
	if owned:
		return "%s  ✓ PURCHASED" % str(item.get("name", "?"))
	return "%s  (£ %d)" % [str(item.get("name", "?")), int(item.get("cost", 0))]


func _refresh_preview() -> void:
	if _selected.is_empty():
		_preview_title.text = "No item selected"
		_preview_desc.text = "Select an item from the list."
		_preview_status.text = ""
		_buy_btn.visible = false
		return
	var item_id: String = str(_selected.get("id", ""))
	var cat: String = str(_selected.get("cat", ""))
	var cost: int = int(_selected.get("cost", 0))
	_preview_title.text = str(_selected.get("name", "?"))
	_preview_desc.text = str(_selected.get("desc", ""))
	var owned: bool = SaveSystem.is_unlocked(cat, item_id)
	if owned:
		_preview_status.text = "✓ PURCHASED"
		_preview_status.add_theme_color_override("font_color", Color(0.45, 0.85, 0.45))
		_buy_btn.visible = false
	else:
		_preview_status.text = "£ %d" % cost
		_preview_status.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
		_buy_btn.visible = true
		_buy_btn.text = "BUY — £ %d" % cost


func _on_item_pressed(item: Dictionary) -> void:
	_selected = item
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("click")
	_refresh_preview()


func _on_buy_pressed() -> void:
	if _selected.is_empty():
		return
	var ok: bool = SaveSystem.purchase_item(str(_selected.get("cat", "")), str(_selected.get("id", "")), int(_selected.get("cost", 0)))
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("purchase" if ok else "error")
	if ok:
		_refresh_market()
	else:
		var funds: int = SaveSystem.get_currency()
		if SaveSystem.is_unlocked(str(_selected.get("cat", "")), str(_selected.get("id", ""))):
			_preview_status.text = "✓ PURCHASED"
		else:
			_preview_status.text = "Insufficient funds (have £ %d, need £ %d)" % [funds, int(_selected.get("cost", 0))]
			_preview_status.add_theme_color_override("font_color", Color(0.9, 0.4, 0.35))


func _on_back_pressed() -> void:
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("back")
	_close_ui()


func _close_ui() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	visible = false
	queue_free()
