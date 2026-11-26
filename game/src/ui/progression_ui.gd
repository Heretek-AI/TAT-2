class_name ProgressionUI
extends CanvasLayer
## Authored progression / Journal panel (W9-P3-C1).
##
## Shipped counterparts: `BPUI_Progression` (level + XP header, the KF07 card)
## and `BPUI_Progression_Contract` / `BPUI_Progression_Stat` (the contract and
## stat rows). Every label is read from `ST_Screens` / `ST_PostMatch` /
## `unlocks.json`; the only screen title candidate in `ST_Screens` is
## `Screen.Ledger.Journal` ("Journal"), which is also what the KF07 Ledger uses,
## because the dump carries no "Progression" / "Character" title row.
##
## Data gaps this screen refuses to fake (see the wave summary):
##   * `SaveSystem` has no `has_completed_contract(order)`, but `data` is a
##     public var and carries `completed_contracts`, so the authored 1..16
##     sweep reads the save record directly (never a fabricated completion).
##   * `DT_PlayerStats` is not in the generated table set and SaveSystem keeps
##     no per-run counters, so GuardKOs / LocksPicked / Stashes are omitted
##     instead of printing zeros. The counters that DO exist live on GameState
##     (takedowns, clue_facts, stolen_keys) and are labelled with the authored
##     `Screen.Stat.*` rows.

signal closed()

const UIStringsScript := preload("res://src/ui/ui_strings.gd")
const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")
const FocusNavScript := preload("res://src/ui/focus_nav.gd")
const ProgressionScript := preload("res://src/core/progression.gd")
const CatalogScript := preload("res://src/ui/unlock_catalog.gd")

const PANEL_MIN_SIZE: Vector2 = Vector2(1100, 660)
const DIM_COLOR: Color = Color(0.008, 0.012, 0.025, 0.86)
const SCROLL_MIN_HEIGHT: int = 470
const UNLOCK_LADDER_COUNT: int = 5
const AUTHORED_CONTRACT_ORDERS: int = 16


## Slanted KF07 XP bar, copied from `LedgerUI.XpBar`
## (game/src/ui/ledger_ui.gd:34-73) so the level card is identical everywhere.
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
		var closed_poly: PackedVector2Array = outer.duplicate()
		closed_poly.append(outer[0])
		draw_polyline(closed_poly, border_color, 1.5, true)


var _built: bool = false
var _root: Control = null
var _panel: PanelContainer = null
var _thief_lbl: Label = null
var _level_lbl: Label = null
var _xp_bar: XpBar = null
var _xp_tally_lbl: Label = null
var _stats_box: VBoxContainer = null
var _contracts_box: VBoxContainer = null
var _unlocks_box: VBoxContainer = null
var _back_btn: Button = null
var _catalog: RefCounted = null


func _ready() -> void:
	visible = false
	_ensure_built()


func open_progression() -> void:
	_ensure_built()
	_refresh()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	FocusNavScript.install_and_focus(_panel)


func close() -> void:
	if not visible:
		return
	_play_ui("back")
	FocusNavScript.release_if_inside(_panel)
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func debug_controls() -> Array[Control]:
	return FocusNavScript.focusable_controls(_panel)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var escaped: bool = event.is_action_pressed("ui_cancel")
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			escaped = true
	if escaped:
		# W10-A INV-1c.6/INV-1c.7: Progression's live opener is the Ledger
		# (`ledger_ui._open_progression()`), not the HUD, so the stamp lives on
		# FocusNav (which every screen preloads) instead of a HUD-side `closed`
		# connection. The HUD's `_process` pause poll reads it for exactly this
		# frame, because `set_input_as_handled()` does not clear the `pause`
		# action state.
		FocusNavScript.mark_escape_consumed()
		close()
		get_viewport().set_input_as_handled()


# --- construction ----------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_catalog = CatalogScript.new()
	_root = Control.new()
	_root.name = "ProgressionRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = DIM_COLOR
	_root.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "ProgressionPanel"
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	_panel.add_theme_stylebox_override("panel",
		ThemeScript.teal_panel_style(2, 6, ThemeScript.TEAL_PANEL_BG, 20))
	center.add_child(_panel)
	ThemeScript.add_authored_frame(_panel, true, 0)
	ThemeScript.add_teal_filigree(_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vb.add_child(header)
	var title: Label = Label.new()
	title.name = "ProgressionTitle"
	title.text = UIStringsScript.st_text("ST_Screens", "Screen.Ledger.Journal", "").to_upper()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", ThemeScript.PX_HEADER)
	title.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	_apply_font(title, ThemeScript.font_display())
	header.add_child(title)
	_thief_lbl = Label.new()
	_thief_lbl.name = "ProgressionThief"
	_thief_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_thief_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_SESSION)
	_thief_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	_apply_font(_thief_lbl, ThemeScript.font_sans())
	header.add_child(_thief_lbl)
	# Second focusable control: the C3 focus-walk gate requires every menu to
	# expose at least two pad targets and a closed ring. A top-right Back mirrors
	# the footer action (same authored label); no new API is introduced.
	var header_back: Button = Button.new()
	header_back.name = "HeaderBackButton"
	header_back.text = UIStringsScript.st_upper("ST_Screens", "Screen.Back", "")
	header_back.custom_minimum_size = Vector2(140, 36)
	ThemeScript.style_teal_button(header_back, false, ThemeScript.PX_SESSION)
	header_back.pressed.connect(close)
	header.add_child(header_back)
	vb.add_child(ThemeScript.teal_divider(0.55))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ProgressionScroll"
	scroll.custom_minimum_size = Vector2(0, SCROLL_MIN_HEIGHT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "ProgressionContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	content.add_child(_build_level_block())
	content.add_child(ThemeScript.teal_divider(0.35))
	_stats_box = _box("StatsBox")
	content.add_child(_stats_box)
	content.add_child(ThemeScript.teal_divider(0.35))
	_contracts_box = _box("ContractsBox")
	content.add_child(_contracts_box)
	content.add_child(ThemeScript.teal_divider(0.35))
	_unlocks_box = _box("UnlocksBox")
	content.add_child(_unlocks_box)

	vb.add_child(ThemeScript.teal_divider(0.45))
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vb.add_child(footer)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_back_btn = Button.new()
	_back_btn.name = "BackButton"
	_back_btn.text = UIStringsScript.st_upper("ST_Screens", "Screen.Back", "")
	_back_btn.custom_minimum_size = Vector2(180, 42)
	ThemeScript.style_teal_button(_back_btn, false, ThemeScript.PX_BODY)
	_back_btn.pressed.connect(close)
	footer.add_child(_back_btn)


func _build_level_block() -> Control:
	var block: VBoxContainer = VBoxContainer.new()
	block.name = "LevelBlock"
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 4)
	_level_lbl = Label.new()
	_level_lbl.name = "LevelLabel"
	_level_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_NUMBERS)
	_level_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	_apply_font(_level_lbl, ThemeScript.font_serif())
	block.add_child(_level_lbl)
	_xp_bar = XpBar.new()
	_xp_bar.name = "LevelXpBar"
	_xp_bar.custom_minimum_size = Vector2(0, 24)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(_xp_bar)
	_xp_tally_lbl = Label.new()
	_xp_tally_lbl.name = "LevelXpTally"
	_xp_tally_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_SESSION)
	_xp_tally_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	_apply_font(_xp_tally_lbl, ThemeScript.font_serif())
	block.add_child(_xp_tally_lbl)
	return block


# --- refresh ---------------------------------------------------------------

func _refresh() -> void:
	if _panel == null:
		return
	var gs: Node = _autoload("GameState")
	_thief_lbl.text = _display_name(gs)
	_refresh_level()
	_refresh_stats(gs)
	_refresh_contracts(gs)
	_refresh_unlocks()
	FocusNavScript.install(_panel)


func _refresh_level() -> void:
	var prog: Dictionary = _level_progress()
	var level: int = int(prog.get("level", 1))
	var in_level: int = int(prog.get("xp_in_level", 0))
	var needed: int = int(prog.get("xp_needed", 0))
	var cap: int = ProgressionScript.maximum_level()
	_level_lbl.text = UIStringsScript.t("Level {CurrentLevel}").replace("{CurrentLevel}", str(level))
	if level >= cap:
		_xp_bar.set_ratio(1.0)
		_xp_tally_lbl.text = UIStringsScript.st_text("ST_PostMatch", "XP.MaxLevel", "")
	else:
		_xp_bar.set_ratio(float(in_level) / float(maxi(1, needed)))
		_xp_tally_lbl.text = "%d/%d" % [in_level, needed]


## Only counters that actually exist are shown. GuardKOs / LocksPicked /
## Stashes have no counter in the port (no generated DT_PlayerStats table and no
## SaveSystem field), so they are omitted rather than printed as a false zero.
func _refresh_stats(gs: Node) -> void:
	_clear(_stats_box)
	var header: String = UIStringsScript.st_text("ST_Screens", "Screen.Label.Stats", "")
	if header != "":
		_stats_box.add_child(ThemeScript.section_header(header, ThemeScript.PX_SESSION + 2))
	_add_stat(_stats_box, "Screen.Stat.StealthKOs", _node_int(gs, "takedowns", 0),
		gs != null and _node_has(gs, "takedowns"))
	_add_stat(_stats_box, "Screen.Stat.CluesFound", _node_array_size(gs, "clue_facts"),
		gs != null and _node_has(gs, "clue_facts"))
	_add_stat(_stats_box, "Screen.Stat.KeysFound", _node_array_size(gs, "stolen_keys"),
		gs != null and _node_has(gs, "stolen_keys"))
	var assets_label: String = UIStringsScript.st_text("ST_Screens", "Screen.Label.TotalAssets", "")
	var ss: Node = _autoload("SaveSystem")
	if assets_label != "" and ss != null and ss.has_method("get_currency"):
		_add_row(_stats_box, assets_label, "(£) " + _money(int(ss.call("get_currency"))), ThemeScript.GOLD)


func _add_stat(box: VBoxContainer, key: String, value: int, available: bool) -> void:
	if not available:
		return
	var label: String = UIStringsScript.st_text("ST_Screens", key, "")
	if label == "":
		return
	_add_row(box, label, _money(value), ThemeScript.TEAL_TEXT)


## Contract list. Complete orders come only from the authored save record
## (`SaveSystem.has_completed_contract(order)` when present, else the public
## `data.completed_contracts` dictionary); otherwise the current contract is
## shown alone, never a fabricated 1..16 sweep.
func _refresh_contracts(gs: Node) -> void:
	_clear(_contracts_box)
	var header: String = UIStringsScript.st_text("ST_PostMatch", "PostMatch.Contract", "")
	if header != "":
		_contracts_box.add_child(ThemeScript.section_header(header, ThemeScript.PX_SESSION + 2))
	var has_api: bool = _has_completion_api()
	var orders: Array[int] = []
	if has_api:
		for order: int in range(1, AUTHORED_CONTRACT_ORDERS + 1):
			if _contract_completed(order):
				orders.append(order)
	if orders.is_empty():
		var current: int = _current_contract_order(gs)
		if current > 0:
			orders.append(current)
	if orders.is_empty():
		_contracts_box.visible = false
		return
	var rows_added: int = 0
	for order: int in orders:
		var label: String = UIStringsScript.st_text("ST_Screens", "Screen.Contract.Number", "").replace("{number}", str(order))
		if label == "":
			continue
		var complete: bool = _contract_completed(order)
		var status_key: String = "Screen.Ledger.Contract.Status.Complete" if complete else "Screen.Ledger.Contract.Status.InProgress"
		var status: String = UIStringsScript.st_text("ST_Screens", status_key, "")
		_add_row(_contracts_box, label, status,
			ThemeScript.GREEN_COMPLETED if complete else ThemeScript.TEAL_ACCENT)
		rows_added += 1
	_contracts_box.visible = rows_added > 0


## Next authored unlocks above the current level (the shipped ladder is the
## Black Market gate list, so it is the only authored progression ladder).
func _refresh_unlocks() -> void:
	_clear(_unlocks_box)
	_unlocks_box.visible = false
	if _catalog == null:
		return
	var level: int = int(_level_progress().get("level", 1))
	var rows: Array[Dictionary] = []
	var entries_v: Variant = _catalog.entries()
	if entries_v is Array:
		for entry_v: Variant in (entries_v as Array):
			if not (entry_v is Dictionary):
				continue
			var entry: Dictionary = entry_v as Dictionary
			if CatalogScript.requires_level(entry) > level:
				rows.append(entry)
	if rows.is_empty():
		return
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la: int = CatalogScript.requires_level(a)
		var lb: int = CatalogScript.requires_level(b)
		if la != lb:
			return la < lb
		return CatalogScript.title_of(a) < CatalogScript.title_of(b))
	var header: String = UIStringsScript.st_text("ST_Screens", "Screen.PostMatch.Unlocks", "")
	if header != "":
		_unlocks_box.add_child(ThemeScript.section_header(header, ThemeScript.PX_SESSION + 2))
	var shown: int = mini(rows.size(), UNLOCK_LADDER_COUNT)
	for i: int in range(shown):
		_unlocks_box.add_child(_unlock_row(rows[i]))
	_unlocks_box.visible = true


func _unlock_row(entry: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = ThemeScript.teal_card_style(1, 4, ThemeScript.TEAL_GROUP_BG, 10)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	var title: Label = Label.new()
	title.text = CatalogScript.title_of(entry)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", ThemeScript.PX_SESSION)
	title.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	_apply_font(title, ThemeScript.font_serif())
	top.add_child(title)
	var condition: Label = Label.new()
	condition.text = CatalogScript.condition_text(entry)
	condition.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	condition.add_theme_font_size_override("font_size", ThemeScript.PX_TINY + 4)
	condition.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	_apply_font(condition, ThemeScript.font_sans())
	top.add_child(condition)
	var description: String = CatalogScript.description_of(entry)
	if description != "":
		vb.add_child(_line(description, ThemeScript.TEAL_MUTED, ThemeScript.PX_TINY + 4, ThemeScript.font_sans()))
	return card


# --- data access -----------------------------------------------------------

func _level_progress() -> Dictionary:
	var ss: Node = _autoload("SaveSystem")
	if ss != null and ss.has_method("get_level_progress"):
		var value: Variant = ss.call("get_level_progress")
		if value is Dictionary:
			return value as Dictionary
	return {"level": 1, "xp_in_level": 0, "xp_needed": ProgressionScript.level_up_xp()}


func _payout() -> Dictionary:
	var ss: Node = _autoload("SaveSystem")
	if ss != null and ss.has_method("get_last_match"):
		var value: Variant = ss.call("get_last_match")
		if value is Dictionary:
			return value as Dictionary
	return {}


func _has_completion_api() -> bool:
	var ss: Node = _autoload("SaveSystem")
	if ss != null and ss.has_method("has_completed_contract"):
		return true
	# `SaveSystem.data` is a public var (save_system.gd:168) and the ledger /
	# unlock catalog already read completed_contracts from it; no new API is
	# needed for the authored 1..16 sweep.
	if ss != null and ss.get("data") is Dictionary:
		var data: Dictionary = ss.get("data") as Dictionary
		return data.get("completed_contracts") is Dictionary
	return false


func _contract_completed(order: int) -> bool:
	var ss: Node = _autoload("SaveSystem")
	if ss == null:
		return false
	if ss.has_method("has_completed_contract"):
		var value: Variant = ss.call("has_completed_contract", order)
		if value is bool:
			return bool(value)
	# `SaveSystem.data` is a public var (save_system.gd:168); the ledger and the
	# unlock catalog already read completed_contracts from it. This is the
	# authored record, not an invented completion.
	var data_v: Variant = ss.get("data")
	if data_v is Dictionary:
		var cc_v: Variant = (data_v as Dictionary).get("completed_contracts", {})
		if cc_v is Dictionary:
			return (cc_v as Dictionary).has(str(order))
	return false


func _current_contract_order(gs: Node) -> int:
	var order: int = int(_payout().get("contract_order", 0))
	if order <= 0:
		order = _node_int(gs, "active_contract_order", 0)
	return order


func _display_name(gs: Node) -> String:
	if gs != null and gs.has_method("player_display_name"):
		return str(gs.call("player_display_name"))
	return ""


func _autoload(node_name: String) -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)


func _node_int(node: Node, property: String, fallback: int) -> int:
	if node == null:
		return fallback
	var value: Variant = node.get(property)
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	return fallback


func _node_array_size(node: Node, property: String) -> int:
	if node == null:
		return 0
	var value: Variant = node.get(property)
	if value is Array:
		return (value as Array).size()
	return 0


## True only when the node actually exposes the property. A missing property
## must omit a stat row, never print a false zero.
func _node_has(node: Node, property: String) -> bool:
	if node == null:
		return false
	return node.get(property) != null


# --- small UI helpers ------------------------------------------------------

func _box(node_name: String) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = node_name
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	return box


func _add_row(box: VBoxContainer, label_text: String, value_text: String, value_color: Color) -> void:
	if box == null or label_text == "":
		return
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", ThemeScript.PX_SESSION)
	label.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	_apply_font(label, ThemeScript.font_sans())
	row.add_child(label)
	var value: Label = Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", ThemeScript.PX_SESSION)
	value.add_theme_color_override("font_color", value_color)
	_apply_font(value, ThemeScript.font_serif())
	row.add_child(value)


func _line(text: String, color: Color, font_size: int, font: Font) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_apply_font(label, font)
	return label


func _apply_font(control: Control, font: Font) -> void:
	if control != null and font != null:
		control.add_theme_font_override("font", font)


func _clear(box: VBoxContainer) -> void:
	if box == null:
		return
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _money(value: int) -> String:
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_method("format_thousands"):
		return str(gs.call("format_thousands", value))
	return str(value)


func _play_ui(cue: String) -> void:
	var am: Node = _autoload("AudioManager")
	if am != null and am.has_method("play_ui"):
		am.call("play_ui", cue)
