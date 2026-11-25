class_name LedgerUI
extends Control
## Journal & Black Market Ledger modal for the Thieves' Den hub.
## Q | E switches tabs. JOURNAL shows the KF07 portrait/Level/XP header and the
## contract carousel from GameData (fallback titles offline). BLACK MARKET is
## the KF08 layout: assets banner, selected-item preview card, and the four
## authored tables (TOOLS / GUILD PERKS / SPIDER COSMETICS / CHAMELEON
## COSMETICS) read from the emitted unlock catalog. Every price, gate and icon
## comes from unlocks.json through UnlockCatalog; there is no hard-coded row and
## no "unknown price" state. ESC / BACK closes.

signal closed()

const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")
const CatalogScript := preload("res://src/ui/unlock_catalog.gd")

const PORTRAIT_PATH: String = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_%s.png"
const CHECK_ICON_PATH: String = "res://assets/ue/Raw/Art/UI/Icons/T_CheckMark.png"
const LOCK_ICON_PATH: String = "res://assets/ue/Raw/Art/UI/Icons/T_Icon_Locked.png"

## Offline contract copy (GameData.contracts empty). Live rows always win.
const FALLBACK_CONTRACTS: Array = [
	{"order": 1, "title": "In the Eye of the Beholder", "description": "Steal the Beholder's Eye diamond from the Guildhall vault.", "location": "Constables' Guildhall"},
	{"order": 2, "title": "Into the Lion's Den", "description": "Infiltrate the Guildhall under heightened watch.", "location": "Constables' Guildhall"},
	{"order": 3, "title": "Shadows over Old Manor", "description": "Burgle the Elway Manor gallery without waking the household.", "location": "Elway Manor"},
	{"order": 4, "title": "The Spider's Gambit", "description": "A high-wire score across the rooftops of Kilcairn.", "location": "Kilcairn Rooftops"},
	{"order": 5, "title": "The Chameleon's Masquerade", "description": "Blend in at the masquerade and lift the guest of honour's seal.", "location": "Jaspering Hall"},
	{"order": 6, "title": "The Constable's Due", "description": "Reclaim impounded loot from the constabulary lockup.", "location": "Constables' Guildhall"},
]

## Slanted KF07 XP bar: teal fill inside a parchment-boat frame. Canvas-only so
## it costs nothing headless.
class XpBar extends Control:
	const SKEW: float = 9.0
	var ratio: float = 0.0
	var fill_color: Color = Color(0.30, 0.75, 0.72)
	var bg_color: Color = Color(0.045, 0.09, 0.11, 0.95)
	var border_color: Color = Color(0.72, 0.86, 0.86, 0.92)

	func set_ratio(value: float) -> void:
		var next: float = clampf(value, 0.0, 1.0)
		if is_equal_approx(next, ratio):
			return
		ratio = next
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 1.0 or h <= 1.0:
			return
		var skew: float = minf(SKEW, w * 0.08)
		var outer: PackedVector2Array = PackedVector2Array([
			Vector2(skew, 0.0), Vector2(w, 0.0),
			Vector2(w - skew, h), Vector2(0.0, h),
		])
		draw_colored_polygon(outer, bg_color)
		var span: float = w - skew
		if ratio > 0.001:
			var top: float = skew + ratio * span
			var bottom: float = ratio * span
			draw_colored_polygon(PackedVector2Array([
				Vector2(skew, 0.0), Vector2(top, 0.0),
				Vector2(bottom, h), Vector2(0.0, h),
			]), fill_color)
		var closed: PackedVector2Array = outer.duplicate()
		closed.append(outer[0])
		draw_polyline(closed, border_color, 1.5, true)

var _tab: int = 0
var _catalog: RefCounted = null
var _journal_btn: Button
var _market_btn: Button
var _journal_page: VBoxContainer
var _market_page: VBoxContainer
var _portrait: TextureRect
var _level_badge: Label
var _level_lbl: Label
var _thief_lbl: Label
var _xp_bar: XpBar
var _xp_lbl: Label
var _contracts_box: HBoxContainer
var _journal_clues_box: VBoxContainer
var _assets_lbl: Label
var _preview_icon: TextureRect
var _preview_state: Label
var _preview_title: Label
var _preview_desc: Label
var _preview_condition: Label
var _preview_status: Label
var _buy_btn: Button
var _market_notice: Label
var _tables_row: HBoxContainer
var _right_tables_row: HBoxContainer
var _selected_id: String = ""


func _ready() -> void:
	_catalog = CatalogScript.new()
	if not _catalog.is_available():
		push_warning("TAT-2 Ledger: unlock catalog unavailable (%s); Black Market fails closed" % ", ".join(_catalog.errors()))
	else:
		print("TAT-2 UI ledger: %d authored catalog rows, %d columns, %d icons" % [
			_catalog.entries().size(), _catalog.columns().size(),
			_catalog.entries().size()])
	assert(ThemeScript != null, "LedgerUI requires res://src/ui/art_nouveau_theme.gd")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if AudioManager != null and AudioManager.has_method("wire_hover_sfx"):
		AudioManager.wire_hover_sfx(self)
	if not GameState.clue_facts_changed.is_connected(_on_clue_facts_changed):
		GameState.clue_facts_changed.connect(_on_clue_facts_changed)
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
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vb.add_child(header)
	_journal_btn = Button.new()
	_journal_btn.text = "[Q] JOURNAL"
	_journal_btn.custom_minimum_size = Vector2(200, 40)
	ThemeScript.style_teal_tab(_journal_btn, true)
	_journal_btn.pressed.connect(_show_tab.bind(0))
	header.add_child(_journal_btn)
	_market_btn = Button.new()
	_market_btn.text = "BLACK MARKET [E]"
	_market_btn.custom_minimum_size = Vector2(220, 40)
	ThemeScript.style_teal_tab(_market_btn, false)
	_market_btn.pressed.connect(_show_tab.bind(1))
	header.add_child(_market_btn)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var back_btn: Button = Button.new()
	back_btn.text = "BACK [ESC]"
	back_btn.custom_minimum_size = Vector2(150, 40)
	ThemeScript.style_teal_button(back_btn, false)
	back_btn.pressed.connect(_on_back_pressed)
	header.add_child(back_btn)
	vb.add_child(ThemeScript.teal_divider())

	_journal_page = VBoxContainer.new()
	_journal_page.add_theme_constant_override("separation", 8)
	_journal_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_journal_page)

	# KF07: portrait card (with its level square) at the far left, the handle
	# under it, then "Level N" over the slanted XP bar and the "94/500" tally.
	var head_row: HBoxContainer = HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 18)
	_journal_page.add_child(head_row)
	var portrait_col: VBoxContainer = VBoxContainer.new()
	portrait_col.add_theme_constant_override("separation", 2)
	head_row.add_child(portrait_col)
	var portrait_stack: Control = Control.new()
	portrait_stack.custom_minimum_size = Vector2(88, 100)
	portrait_col.add_child(portrait_stack)
	var portrait_frame: PanelContainer = PanelContainer.new()
	portrait_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_frame.add_theme_stylebox_override("panel", ThemeScript.teal_card_style(1, 3, ThemeScript.TEAL_GROUP_BG, 2))
	portrait_stack.add_child(portrait_frame)
	_portrait = TextureRect.new()
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_stack.add_child(_portrait)
	_level_badge = Label.new()
	_level_badge.text = "1"
	_level_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_badge.add_theme_font_size_override("font_size", 13)
	_level_badge.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	var badge_bg: StyleBoxFlat = StyleBoxFlat.new()
	badge_bg.bg_color = Color(0.035, 0.078, 0.100, 0.96)
	badge_bg.border_color = ThemeScript.TEAL_BORDER
	badge_bg.set_border_width_all(1)
	_level_badge.add_theme_stylebox_override("normal", badge_bg)
	_level_badge.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_level_badge.custom_minimum_size = Vector2(20, 18)
	_level_badge.offset_left = -10.0
	_level_badge.offset_top = -20.0
	_level_badge.offset_right = 10.0
	_level_badge.offset_bottom = -2.0
	_level_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_stack.add_child(_level_badge)
	_thief_lbl = Label.new()
	_thief_lbl.text = GameState.player_display_name()
	_thief_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thief_lbl.add_theme_font_size_override("font_size", 14)
	_thief_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_thief_lbl.add_theme_font_override("font", sans)
	portrait_col.add_child(_thief_lbl)
	var xp_col: VBoxContainer = VBoxContainer.new()
	xp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_col.add_theme_constant_override("separation", 2)
	head_row.add_child(xp_col)
	_level_lbl = Label.new()
	_level_lbl.text = "Level 1"
	_level_lbl.add_theme_font_size_override("font_size", 24)
	_level_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		_level_lbl.add_theme_font_override("font", serif)
	xp_col.add_child(_level_lbl)
	_xp_bar = XpBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 26)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_col.add_child(_xp_bar)
	_xp_lbl = Label.new()
	_xp_lbl.add_theme_font_size_override("font_size", 20)
	_xp_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		_xp_lbl.add_theme_font_override("font", serif)
	xp_col.add_child(_xp_lbl)

	# KF07: contracts read as a horizontal carousel (Contract #1 clipped left,
	# #2 Completed center, #3 Active right) with the status word floating ABOVE
	# each card and a top-center "Contract #N" tab.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_journal_page.add_child(scroll)
	_contracts_box = HBoxContainer.new()
	_contracts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contracts_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_contracts_box.add_theme_constant_override("separation", 16)
	scroll.add_child(_contracts_box)
	# Clue journal: GameState.clue_facts in authored order (display_priority
	# then learned order). The labels carry the exact journal_text.
	var clue_scroll: ScrollContainer = ScrollContainer.new()
	clue_scroll.custom_minimum_size = Vector2(0, 120)
	clue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	clue_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_page.add_child(clue_scroll)
	_journal_clues_box = VBoxContainer.new()
	_journal_clues_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_clues_box.add_theme_constant_override("separation", 6)
	clue_scroll.add_child(_journal_clues_box)

	_market_page = VBoxContainer.new()
	_market_page.add_theme_constant_override("separation", 8)
	_market_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_market_page)

	# KF08#1: "YOUR TOTAL ASSETS: (£) 26,275" in a gold-bordered banner.
	var assets_card: PanelContainer = PanelContainer.new()
	assets_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var assets_style: StyleBoxFlat = StyleBoxFlat.new()
	assets_style.bg_color = Color(0.10, 0.085, 0.055, 0.94)
	assets_style.border_color = ThemeScript.GOLD_DIM
	assets_style.set_border_width_all(2)
	assets_style.set_corner_radius_all(3)
	assets_style.set_content_margin_all(8)
	assets_style.content_margin_left = 40
	assets_style.content_margin_right = 40
	assets_card.add_theme_stylebox_override("panel", assets_style)
	_market_page.add_child(assets_card)
	_assets_lbl = Label.new()
	_assets_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_assets_lbl.add_theme_font_size_override("font_size", 19)
	_assets_lbl.add_theme_color_override("font_color", ThemeScript.GOLD)
	if serif != null:
		_assets_lbl.add_theme_font_override("font", serif)
	assets_card.add_child(_assets_lbl)

	_market_notice = Label.new()
	_market_notice.visible = false
	_market_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_market_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_market_notice.add_theme_font_size_override("font_size", 13)
	_market_notice.add_theme_color_override("font_color", ThemeScript.PINK_HINT)
	_market_page.add_child(_market_notice)

	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_page.add_child(split)

	# Left half: preview card above the TOOLS / GUILD PERKS tables.
	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_col)
	left_col.add_child(_build_preview_card())
	_tables_row = HBoxContainer.new()
	_tables_row.add_theme_constant_override("separation", 10)
	_tables_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tables_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_child(_tables_row)

	# Right half: the two cosmetic tables (KF08#4/#5), each scrollable.
	var right_row: HBoxContainer = HBoxContainer.new()
	right_row.add_theme_constant_override("separation", 10)
	right_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_row)
	_right_tables_row = right_row


func _build_preview_card() -> PanelContainer:
	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()
	var preview: PanelContainer = PanelContainer.new()
	preview.custom_minimum_size = Vector2(0, 196)
	preview.add_theme_stylebox_override("panel", ThemeScript.teal_card_style(1, 5, ThemeScript.TEAL_GROUP_BG, 10))
	ThemeScript.add_teal_filigree(preview, 3.0, 14.0)
	var pv: VBoxContainer = VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	preview.add_child(pv)
	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	pv.add_child(top_row)
	_preview_state = Label.new()
	_preview_state.add_theme_font_size_override("font_size", 14)
	_preview_state.add_theme_color_override("font_color", ThemeScript.GREEN_PURCHASED)
	if sans != null:
		_preview_state.add_theme_font_override("font", sans)
	top_row.add_child(_preview_state)
	var top_spacer: Control = Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(top_spacer)
	var icon_row: HBoxContainer = HBoxContainer.new()
	icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(icon_row)
	_preview_icon = TextureRect.new()
	_preview_icon.custom_minimum_size = Vector2(96, 96)
	_preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_row.add_child(_preview_icon)
	_preview_title = Label.new()
	_preview_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_title.add_theme_font_size_override("font_size", 19)
	_preview_title.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		_preview_title.add_theme_font_override("font", serif)
	pv.add_child(_preview_title)
	_preview_desc = Label.new()
	_preview_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_desc.max_lines_visible = 3
	_preview_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_preview_desc.add_theme_font_size_override("font_size", 12)
	_preview_desc.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_preview_desc.add_theme_font_override("font", sans)
	pv.add_child(_preview_desc)
	var buy_row: HBoxContainer = HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	pv.add_child(buy_row)
	_preview_condition = Label.new()
	_preview_condition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_condition.add_theme_font_size_override("font_size", 12)
	_preview_condition.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	if sans != null:
		_preview_condition.add_theme_font_override("font", sans)
	buy_row.add_child(_preview_condition)
	_preview_status = Label.new()
	_preview_status.add_theme_font_size_override("font_size", 15)
	_preview_status.add_theme_color_override("font_color", ThemeScript.GOLD)
	if sans != null:
		_preview_status.add_theme_font_override("font", sans)
	buy_row.add_child(_preview_status)
	_buy_btn = Button.new()
	_buy_btn.text = "BUY"
	_buy_btn.custom_minimum_size = Vector2(150, 32)
	ThemeScript.style_teal_button(_buy_btn, true)
	_buy_btn.pressed.connect(_on_buy_pressed)
	buy_row.add_child(_buy_btn)
	return preview


## One KF08 table: centered caps header + (£) column mark, then rows. Rows are
## rebuilt from the catalog on every refresh so price/lock/check state is live.
func _build_table(column: Dictionary) -> VBoxContainer:
	var sans: Font = ThemeScript.font_sans()
	var table: VBoxContainer = VBoxContainer.new()
	table.add_theme_constant_override("separation", 2)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 4)
	table.add_child(hdr)
	var title_lbl: Label = Label.new()
	title_lbl.text = str(column.get("title", ""))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if sans != null:
		title_lbl.add_theme_font_override("font", sans)
	hdr.add_child(title_lbl)
	var unit: Label = Label.new()
	unit.text = "(£)"
	unit.custom_minimum_size = Vector2(34, 0)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	unit.add_theme_font_size_override("font_size", 12)
	unit.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	if sans != null:
		unit.add_theme_font_override("font", sans)
	hdr.add_child(unit)
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(ThemeScript.TEAL_BORDER.r, ThemeScript.TEAL_BORDER.g, ThemeScript.TEAL_BORDER.b, 0.55)
	rule.custom_minimum_size = Vector2(0, 1)
	table.add_child(rule)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	table.add_child(scroll)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	return table


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


func _portrait_for_active_thief() -> Texture2D:
	var thief: String = str(GameState.thief_id).strip_edges().to_lower()
	if thief != "chameleon":
		thief = "spider"
	var path: String = PORTRAIT_PATH % thief
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path)
	return res as Texture2D if res is Texture2D else null


func _refresh_journal() -> void:
	var prog: Dictionary = SaveSystem.get_level_progress()
	var level: int = int(prog.get("level", 1))
	var in_level: int = int(prog.get("xp_in_level", 0))
	var needed: int = int(prog.get("xp_needed", 500))
	_level_lbl.text = "Level %d" % level
	if _level_badge != null:
		_level_badge.text = str(level)
	if _thief_lbl != null:
		_thief_lbl.text = GameState.player_display_name()
	if _portrait != null:
		var tex: Texture2D = _portrait_for_active_thief()
		_portrait.texture = tex
		_portrait.visible = tex != null
	_xp_bar.set_ratio(float(in_level) / float(maxi(1, needed)))
	_xp_lbl.text = "%d/%d" % [in_level, needed]
	for child: Node in _contracts_box.get_children():
		child.queue_free()
	var contracts: Array = _collect_contracts()
	var italic: Font = ThemeScript.font_italic()
	var serif: Font = ThemeScript.font_serif()
	for c: Variant in contracts:
		var cd: Dictionary = c as Dictionary
		var order: int = int(cd.get("order", 0))
		var done: bool = _is_contract_complete(order)
		# KF07 cite: status floats above the card; card opens with a
		# top-center "Contract #N" tab, then the italic-serif title.
		var slot: VBoxContainer = VBoxContainer.new()
		slot.custom_minimum_size = Vector2(340, 0)
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.add_theme_constant_override("separation", 4)
		_contracts_box.add_child(slot)
		var status_above: Label = Label.new()
		status_above.text = "Completed" if done else "Active"
		status_above.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_above.add_theme_font_size_override("font_size", 14)
		status_above.add_theme_color_override("font_color", ThemeScript.GREEN_COMPLETED if done else ThemeScript.TEAL_ACCENT)
		if italic != null:
			status_above.add_theme_font_override("font", italic)
		slot.add_child(status_above)
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(340, 0)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var cstyle: StyleBoxFlat = ThemeScript.teal_card_style(1, 5, ThemeScript.TEAL_GROUP_BG, 12)
		if done:
			cstyle.border_color = ThemeScript.GREEN_CARD_BORDER
		card.add_theme_stylebox_override("panel", cstyle)
		ThemeScript.add_teal_filigree(card, 3.0, 12.0)
		var cv: VBoxContainer = VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		var tab: Label = Label.new()
		tab.text = "Contract #%d" % order
		tab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.add_theme_font_size_override("font_size", 15)
		tab.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
		cv.add_child(tab)
		var head: HBoxContainer = HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		cv.add_child(head)
		var t: Label = Label.new()
		t.text = str(cd.get("title", "Contract"))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_theme_font_size_override("font_size", 18)
		t.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE if not done else ThemeScript.TEAL_TEXT)
		var title_font: Font = italic if italic != null else serif
		if title_font != null:
			t.add_theme_font_override("font", title_font)
		head.add_child(t)
		var loc: String = str(cd.get("location", ""))
		var desc: String = str(cd.get("description", ""))
		if loc != "" or desc != "":
			var d: Label = Label.new()
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.text = ("Location: %s\n" % loc if loc != "" else "") + desc
			d.add_theme_font_size_override("font_size", 14)
			d.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
			cv.add_child(d)
		slot.add_child(card)
	_refresh_journal_clues()


func _on_clue_facts_changed() -> void:
	if is_inside_tree():
		_refresh_journal_clues()


func _refresh_journal_clues() -> void:
	if _journal_clues_box == null:
		return
	for child: Node in _journal_clues_box.get_children():
		child.queue_free()
	var facts: Array[Dictionary] = []
	for entry: Dictionary in GameState.clue_facts:
		facts.append(entry.duplicate(true))
	facts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a.get("display_priority", 0))
		var pb: int = int(b.get("display_priority", 0))
		if pa != pb:
			return pa < pb
		return int(a.get("learned_index", 0)) < int(b.get("learned_index", 0))
	)
	var sans: Font = ThemeScript.font_sans()
	for entry: Dictionary in facts:
		var text: String = str(entry.get("journal_text", ""))
		if text == "":
			continue
		var label: Label = Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
		if sans != null:
			label.add_theme_font_override("font", sans)
		_journal_clues_box.add_child(label)


## Market display item: a catalog row flattened for the table/preview helpers.
## `state` is a snapshot; the UI re-derives it live through the catalog.
func _item_of(entry: Dictionary) -> Dictionary:
	return {
		"id": CatalogScript.save_id_of(entry),
		"save_id": CatalogScript.save_id_of(entry),
		"tag": str(entry.get("tag", "")),
		"name": CatalogScript.title_of(entry),
		"cat": CatalogScript.category_of(entry),
		"cost": CatalogScript.price_of(entry),
		"desc": CatalogScript.description_of(entry),
		"condition": CatalogScript.condition_text(entry),
		"state": _catalog.state_of(entry),
	}


## The four authored KF08 tables, each {key, title, items}. Kept as the single
## section accessor the suite and the UI share.
func _sections() -> Array:
	var out: Array = []
	if _catalog == null:
		return out
	for column: Dictionary in _catalog.columns():
		var items: Array = []
		for entry: Dictionary in _catalog.entries_for_column(str(column.get("key", ""))):
			items.append(_item_of(entry))
		out.append({
			"key": str(column.get("key", "")),
			"title": str(column.get("title", "")),
			"thief": column.get("thief", null),
			"save_category": str(column.get("save_category", "")),
			"items": items,
		})
	return out


func _refresh_market() -> void:
	_assets_lbl.text = "YOUR TOTAL ASSETS: (£) %s" % GameState.format_thousands(SaveSystem.get_currency())
	var available: bool = _catalog != null and _catalog.is_available()
	_market_notice.visible = not available
	if not available:
		_market_notice.text = "The Black Market catalog could not be read (%s). Nothing can be purchased. Run python3 tools/parse_unlocks.py and reload." % (
			", ".join(_catalog.errors()) if _catalog != null else "no catalog")
	for child: Node in _tables_row.get_children():
		child.queue_free()
	if _right_tables_row != null:
		for child: Node in _right_tables_row.get_children():
			child.queue_free()
	if not available:
		_selected_id = ""
		_refresh_preview()
		return
	var columns: Array[Dictionary] = _catalog.columns()
	for column: Dictionary in columns:
		var key: String = str(column.get("key", ""))
		var host: HBoxContainer = _tables_row
		if key.begins_with("spider") or key.begins_with("chameleon"):
			host = _right_tables_row
		if host == null:
			continue
		var table: VBoxContainer = _build_table(column)
		table.name = "Table_" + key
		host.add_child(table)
		var rows: VBoxContainer = table.find_child("Rows", true, false) as VBoxContainer
		if rows == null:
			continue
		for entry: Dictionary in _catalog.entries_for_column(key):
			rows.add_child(_build_market_row(entry))
	# Keep a valid selection: the shipped frame opens on Zipwire (TOOLS[0]).
	if _selected_id == "" or not _catalog.has(_selected_id):
		var first: Array[Dictionary] = _catalog.entries_for_column("tools")
		_selected_id = CatalogScript.save_id_of(first[0]) if not first.is_empty() else ""
	_refresh_preview()


func _build_market_row(entry: Dictionary) -> Button:
	var state: String = _catalog.state_of(entry)
	var btn: Button = Button.new()
	btn.text = CatalogScript.title_of(entry)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.custom_minimum_size = Vector2(0, 26)
	btn.focus_mode = Control.FOCUS_ALL
	var italic: Font = ThemeScript.font_italic()
	if italic != null:
		btn.add_theme_font_override("font", italic)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	btn.add_theme_color_override("font_hover_color", ThemeScript.TEAL_ACCENT)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.05, 0.06, 0.30)
	normal.border_color = Color(ThemeScript.TEAL_BORDER.r, ThemeScript.TEAL_BORDER.g, ThemeScript.TEAL_BORDER.b, 0.35)
	normal.border_width_bottom = 1
	normal.content_margin_left = 7
	normal.content_margin_right = 7
	normal.content_margin_top = 2
	normal.content_margin_bottom = 2
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.09, 0.21, 0.25, 0.80)
	hover.border_color = ThemeScript.TEAL_ACCENT
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.14, 0.34, 0.36, 0.85)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	var slot: HBoxContainer = HBoxContainer.new()
	slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.alignment = BoxContainer.ALIGNMENT_END
	slot.add_theme_constant_override("separation", 2)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(slot)
	var market_id: String = CatalogScript.save_id_of(entry)
	btn.pressed.connect(_on_item_pressed.bind(market_id))
	btn.tooltip_text = CatalogScript.description_of(entry)
	if state == CatalogScript.STATE_PURCHASED:
		slot.add_child(_state_icon(CHECK_ICON_PATH, ThemeScript.GREEN_PURCHASED))
	elif state == CatalogScript.STATE_LOCKED:
		slot.add_child(_state_icon(LOCK_ICON_PATH, ThemeScript.PINK_LOCKED))
	else:
		var price: Label = Label.new()
		price.text = _catalog.price_text(entry)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.add_theme_font_size_override("font_size", 13)
		price.add_theme_color_override("font_color", ThemeScript.GOLD)
		if italic != null:
			price.add_theme_font_override("font", italic)
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(price)
	return btn


func _state_icon(path: String, tint: Color) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is Texture2D:
			rect.texture = res as Texture2D
	rect.custom_minimum_size = Vector2(18, 18)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.modulate = tint
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Row label used by both this panel and the regression suite: no placeholder
## or unknown-price marker exists -- a row is purchased, locked or priced.
func _item_button_text(item: Dictionary) -> String:
	var name_text: String = str(item.get("name", "?"))
	var entry: Dictionary = _entry_for_item(item)
	if entry.is_empty():
		return "%s  LOCKED" % name_text
	var state: String = _catalog.state_of(entry)
	if state == CatalogScript.STATE_PURCHASED:
		return "%s  ✓ PURCHASED" % name_text
	if state == CatalogScript.STATE_LOCKED:
		return "%s  LOCKED" % name_text
	return "%s  (£ %s)" % [name_text, _catalog.price_text(entry)]


func _entry_for_item(item: Dictionary) -> Dictionary:
	if _catalog == null:
		return {}
	var save_id: String = str(item.get("save_id", item.get("id", ""))).strip_edges()
	if save_id != "" and _catalog.has(save_id):
		return _catalog.entry(save_id)
	var tag: String = str(item.get("tag", "")).strip_edges()
	if tag != "" and _catalog.has(tag):
		return _catalog.entry(tag)
	return {}


func _refresh_preview() -> void:
	if _catalog == null or not _catalog.is_available():
		_preview_title.text = "Black Market unavailable"
		_preview_desc.text = "The authored catalog is missing. Nothing can be purchased."
		_preview_condition.text = ""
		_preview_status.text = ""
		_preview_state.text = ""
		_preview_icon.texture = null
		_buy_btn.visible = false
		return
	var entry: Dictionary = _catalog.entry(_selected_id)
	if entry.is_empty():
		_preview_title.text = "No item selected"
		_preview_desc.text = "Select an item from a table."
		_preview_condition.text = ""
		_preview_status.text = ""
		_preview_state.text = ""
		_preview_icon.texture = null
		_buy_btn.visible = false
		return
	_preview_title.text = CatalogScript.title_of(entry)
	_preview_desc.text = CatalogScript.description_of(entry)
	_preview_icon.texture = CatalogScript.icon_texture(entry)
	var condition: String = CatalogScript.condition_text(entry)
	_preview_condition.text = condition
	var state: String = _catalog.state_of(entry)
	_buy_btn.visible = false
	_buy_btn.text = "BUY"
	_preview_status.text = ""
	if state == CatalogScript.STATE_PURCHASED:
		_preview_state.text = "✓ PURCHASED"
		_preview_state.add_theme_color_override("font_color", ThemeScript.GREEN_PURCHASED)
		_preview_status.text = "✓ PURCHASED"
		_preview_status.add_theme_color_override("font_color", ThemeScript.GREEN_PURCHASED)
	elif state == CatalogScript.STATE_LOCKED:
		_preview_state.text = "LOCKED"
		_preview_state.add_theme_color_override("font_color", ThemeScript.PINK_LOCKED)
		_preview_status.text = CatalogScript.lock_reason(entry)
		_preview_status.add_theme_color_override("font_color", ThemeScript.PINK_LOCKED)
	else:
		_preview_state.text = ""
		_preview_status.text = "£ %s" % _catalog.price_text(entry)
		_preview_status.add_theme_color_override("font_color", ThemeScript.GOLD)
		_buy_btn.visible = true
		_buy_btn.text = "BUY — £ %s" % _catalog.price_text(entry)


func _on_item_pressed(save_id: String) -> void:
	_selected_id = save_id
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("click")
	_refresh_preview()


func _on_buy_pressed() -> void:
	if _catalog == null or not _catalog.is_available() or _selected_id == "":
		push_error("TAT-2 UI ledger BUY without an authored catalog row (res://src/ui/ledger_ui.gd); refusing silent continue.")
		assert(false, "BUY requires an authored catalog row")
		return
	var entry: Dictionary = _catalog.entry(_selected_id)
	# Defensive fail-closed gate: the button is hidden for locked/owned rows,
	# and a gate/price from the catalog is the only thing that can be charged.
	if entry.is_empty() or not _catalog.conditions_met(entry):
		_refresh_preview()
		return
	if _catalog.state_of(entry) != CatalogScript.STATE_BUY:
		_refresh_preview()
		return
	var category: String = CatalogScript.category_of(entry)
	var price: int = CatalogScript.price_of(entry)
	var ok: bool = SaveSystem.purchase_by_save_id(category, _selected_id, price)
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("purchase" if ok else "error")
	if ok:
		_refresh_market()
		_refresh_preview()
		return
	var funds: int = SaveSystem.get_currency()
	_preview_status.text = "Insufficient funds (have (£) %s, need £ %s)" % [
		GameState.format_thousands(funds), GameState.format_thousands(price)]
	_preview_status.add_theme_color_override("font_color", ThemeScript.RED_INSUFFICIENT)


func _on_back_pressed() -> void:
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("back")
	_close_ui()


func _close_ui() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	visible = false
	queue_free()
