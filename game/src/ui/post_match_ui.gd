class_name PostMatchUI
extends CanvasLayer
## Authored post-match rack-up + end-match XP screen (W9-P3-C1).
##
## Shipped counterparts: `BPUI_PostMatchRackup_AllPlayers` (the rack-up) and
## `EndMatchXPScreen` (the XP breakdown / level-up card). The copy comes from
## `ST_PostMatch` (71 rows), `ST_Screens` (the PostMatch/rankup rows) and the
## locres-only rows `Level {CurrentLevel}` / `LEVEL UP!`; the XP weights come
## from `Progression.xp_award` (`DefaultGame.ini` via project_settings.json), so
## no number on this screen is a literal. The single non-authored string is the
## total label (`PORT_XP_EARNED`): the shipped table has breakdown rows but no
## "XP earned" total row.
##
## Data: `SaveSystem.get_level_progress()` / `get_last_match()` are read through
## `/root/SaveSystem` (guarded) because this screen must also load in a bare
## SceneTree. `xp_awarded` is the *measured* award (the caller passes what the
## save actually gained); -1 means "not measured" and the total/level-up block
## stays absent rather than printing a guess.

signal continue_requested()
signal closed()

const UIStringsScript := preload("res://src/ui/ui_strings.gd")
const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")
const FocusNavScript := preload("res://src/ui/focus_nav.gd")
const ProgressionScript := preload("res://src/core/progression.gd")
const CatalogScript := preload("res://src/ui/unlock_catalog.gd")

const PANEL_MIN_SIZE: Vector2 = Vector2(1100, 660)
const DIM_COLOR: Color = Color(0.008, 0.012, 0.025, 0.86)
const SCROLL_MIN_HEIGHT: int = 420

## PORT LABEL (1/1 on this screen): the authored ST_PostMatch carries every
## breakdown row and `XP.MaxLevel`, but no label for the measured total award.
## Kept structural so the screen can state the number the caller measured.
const PORT_XP_EARNED: String = "XP earned"


## Slanted KF07 XP bar: teal fill in a parchment-boat frame, copied from
## `LedgerUI.XpBar` (game/src/ui/ledger_ui.gd:34-73) so the Journal and the
## post-match level block read as one widget. Canvas-only, no GPU cost.
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
var _status_lbl: Label = null
var _contract_lbl: Label = null
var _haul_box: VBoxContainer = null
var _xp_box: VBoxContainer = null
var _total_box: VBoxContainer = null
var _level_lbl: Label = null
var _xp_bar: XpBar = null
var _xp_tally_lbl: Label = null
var _levelup_lbl: Label = null
var _unlocks_box: VBoxContainer = null
var _continue_btn: Button = null
var _back_btn: Button = null
var _catalog: RefCounted = null

var _won: bool = false
var _score: int = 0
var _info: Dictionary = {}
var _xp_awarded: int = -1


func _ready() -> void:
	visible = false
	_ensure_built()


## Public API: `won` is the run outcome, `score` is the payout fallback when
## no payout record exists, `info` is the contract/mission record the caller
## already has, and `xp_awarded` is the measured XP gain (-1 = unmeasured).
func open_result(won: bool, score: int, info: Dictionary, xp_awarded: int = -1) -> void:
	_won = won
	_score = maxi(score, 0)
	_info = info.duplicate(true)
	_xp_awarded = xp_awarded
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
		close()
		get_viewport().set_input_as_handled()


# --- construction ----------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_catalog = CatalogScript.new()
	_root = Control.new()
	_root.name = "PostMatchRoot"
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
	_panel.name = "PostMatchPanel"
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	_panel.add_theme_stylebox_override("panel",
		ThemeScript.teal_panel_style(2, 6, ThemeScript.TEAL_PANEL_BG, 20))
	center.add_child(_panel)
	ThemeScript.add_authored_frame(_panel, true, 0)
	ThemeScript.add_teal_filigree(_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)

	_status_lbl = Label.new()
	_status_lbl.name = "PostMatchStatus"
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_HEADER)
	_status_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	_apply_font(_status_lbl, ThemeScript.font_display())
	vb.add_child(_status_lbl)
	vb.add_child(ThemeScript.teal_divider(0.55))

	_contract_lbl = Label.new()
	_contract_lbl.name = "PostMatchContractOutcome"
	_contract_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_contract_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_contract_lbl.visible = false
	_contract_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_SESSION)
	_contract_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	_apply_font(_contract_lbl, ThemeScript.font_italic())
	vb.add_child(_contract_lbl)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "PostMatchScroll"
	scroll.custom_minimum_size = Vector2(0, SCROLL_MIN_HEIGHT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "PostMatchContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	_haul_box = VBoxContainer.new()
	_haul_box.name = "HaulBox"
	_haul_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_haul_box.add_theme_constant_override("separation", 2)
	content.add_child(_haul_box)

	_xp_box = VBoxContainer.new()
	_xp_box.name = "XpBreakdownBox"
	_xp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_box.add_theme_constant_override("separation", 2)
	content.add_child(_xp_box)

	_total_box = VBoxContainer.new()
	_total_box.name = "XpTotalBox"
	_total_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_total_box.add_theme_constant_override("separation", 2)
	content.add_child(_total_box)

	content.add_child(ThemeScript.teal_divider(0.35))
	content.add_child(_build_level_block())

	_unlocks_box = VBoxContainer.new()
	_unlocks_box.name = "UnlocksBox"
	_unlocks_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unlocks_box.add_theme_constant_override("separation", 4)
	_unlocks_box.visible = false
	content.add_child(_unlocks_box)

	vb.add_child(ThemeScript.teal_divider(0.45))
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vb.add_child(footer)
	_back_btn = Button.new()
	_back_btn.name = "BackButton"
	_back_btn.text = UIStringsScript.st_upper("ST_Screens", "Screen.Back", "")
	_back_btn.custom_minimum_size = Vector2(180, 42)
	ThemeScript.style_teal_button(_back_btn, false, ThemeScript.PX_BODY)
	_back_btn.pressed.connect(close)
	footer.add_child(_back_btn)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_continue_btn = Button.new()
	_continue_btn.name = "ContinueButton"
	_continue_btn.text = UIStringsScript.st_upper("ST_Screens", "Screen.Continue", "")
	_continue_btn.custom_minimum_size = Vector2(240, 42)
	ThemeScript.style_teal_button(_continue_btn, true, ThemeScript.PX_BODY)
	_continue_btn.pressed.connect(_on_continue_pressed)
	footer.add_child(_continue_btn)


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
	_levelup_lbl = Label.new()
	_levelup_lbl.name = "LevelUpLabel"
	_levelup_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_levelup_lbl.visible = false
	_levelup_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_HEADER)
	_levelup_lbl.add_theme_color_override("font_color", ThemeScript.GOLD)
	_apply_font(_levelup_lbl, ThemeScript.font_display())
	block.add_child(_levelup_lbl)
	return block


# --- refresh ---------------------------------------------------------------

func _refresh() -> void:
	if _panel == null:
		return
	var status_key: String = "PostMatch.Status.Escaped" if _won else "PostMatch.Status.Caught"
	_status_lbl.text = UIStringsScript.st_upper("ST_PostMatch", status_key, "")
	var contract_line: String = _contract_outcome_line()
	_contract_lbl.text = contract_line
	_contract_lbl.visible = contract_line != ""
	_refresh_haul()
	_refresh_xp()
	_refresh_level()
	FocusNavScript.install(_panel)


func _refresh_haul() -> void:
	_clear(_haul_box)
	var payout: Dictionary = _payout()
	var kept: int = int(payout.get("kept", 0))
	var original: int = int(payout.get("original", kept))
	var cash: int = int(payout.get("money_taken", kept))
	var haul_header: String = UIStringsScript.st_text("ST_PostMatch", "PostMatch.Haul", "")
	if haul_header != "":
		_haul_box.add_child(ThemeScript.section_header(haul_header, ThemeScript.PX_SESSION + 2))
	var earned: String = UIStringsScript.st_text("ST_Screens", "Screen.PostMatch.LootEarned", "").replace("{0}", _money(kept))
	if earned != "":
		_haul_box.add_child(_line(earned, ThemeScript.TEAL_TEXT, ThemeScript.PX_SESSION, ThemeScript.font_sans()))
	if original > kept:
		var lost: String = UIStringsScript.st_text("ST_Screens", "Screen.PostMatch.LootLost", "").replace("{0}", _money(original - kept))
		if lost != "":
			_haul_box.add_child(_line(lost, ThemeScript.RED_INSUFFICIENT, ThemeScript.PX_SESSION, ThemeScript.font_sans()))
	var cash_label: String = UIStringsScript.st_text("ST_Screens", "Screen.PostMatch.CashInHand", "")
	if cash_label != "":
		_add_row(_haul_box, cash_label, "£ " + _money(cash), ThemeScript.TEAL_TITLE)
	var assets_label: String = UIStringsScript.st_text("ST_Screens", "Screen.Label.TotalAssets", "")
	if assets_label != "":
		_add_row(_haul_box, assets_label, "(£) " + _money(_currency()), ThemeScript.GOLD)
	var total_haul_label: String = UIStringsScript.st_text("ST_Screens", "Screen.Label.TotalHaul", "")
	if total_haul_label != "":
		_add_row(_haul_box, total_haul_label, "£ " + _money(kept), ThemeScript.TEAL_TITLE)


func _refresh_xp() -> void:
	_clear(_xp_box)
	var header: String = UIStringsScript.st_text("ST_PostMatch", "XP.Breakdown", "")
	if header != "":
		_xp_box.add_child(ThemeScript.section_header(header, ThemeScript.PX_SESSION + 2))
	var rows: Array[Dictionary] = _xp_rows()
	for row: Dictionary in rows:
		var label: String = str(row.get("label", ""))
		if label == "":
			continue
		_add_row(_xp_box, label, str(row.get("value", "")),
			ThemeScript.GOLD if row.get("multiplier", false) else ThemeScript.TEAL_TEXT)

	_clear(_total_box)
	# Authored FTUE credit: save_system.record_contract_complete() adds
	# Progression.ftue_level_up_xp() (3 authored tags x contracts_xp = 60) ON TOP
	# of the difficulty-multiplied base, so the remainder over the multiplied
	# weights is exactly the authored FinishedTutorial row -- never a guess.
	if _xp_awarded >= 0:
		var expected: int = _expected_xp()
		var remainder: int = _xp_awarded - expected
		if _won and remainder > 0:
			var ftue_label: String = UIStringsScript.st_text("ST_PostMatch", "XP.Breakdown.FinishedTutorial", "")
			if ftue_label != "":
				_add_row(_total_box, ftue_label, "+" + _money(remainder), ThemeScript.TEAL_MUTED)
		_add_row(_total_box, PORT_XP_EARNED, "+" + _money(_xp_awarded), ThemeScript.GOLD)


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
	var crossed: Dictionary = _crossed_levels()
	var up: bool = bool(crossed.get("up", false))
	_levelup_lbl.visible = up
	_levelup_lbl.text = UIStringsScript.t("LEVEL UP!") if up else ""
	_rebuild_unlocks(crossed)


func _rebuild_unlocks(crossed: Dictionary) -> void:
	_clear(_unlocks_box)
	_unlocks_box.visible = false
	if not bool(crossed.get("up", false)) or _catalog == null:
		return
	var before: int = int(crossed.get("before", 1))
	var after: int = int(crossed.get("after", 1))
	var rows: Array[Dictionary] = []
	var entries_v: Variant = _catalog.entries()
	if entries_v is Array:
		for entry_v: Variant in (entries_v as Array):
			if not (entry_v is Dictionary):
				continue
			var entry: Dictionary = entry_v as Dictionary
			var need: int = CatalogScript.requires_level(entry)
			if need > before and need <= after:
				rows.append(entry)
	if rows.is_empty():
		return
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return CatalogScript.requires_level(a) < CatalogScript.requires_level(b))
	var header: String = UIStringsScript.st_text("ST_Screens", "Screen.PostMatch.Unlocks", "")
	if header != "":
		_unlocks_box.add_child(ThemeScript.section_header(header, ThemeScript.PX_SESSION + 2))
	for entry: Dictionary in rows:
		var title: String = CatalogScript.title_of(entry)
		var description: String = CatalogScript.description_of(entry)
		if title != "":
			_unlocks_box.add_child(_line(title, ThemeScript.TEAL_TITLE, ThemeScript.PX_SESSION, ThemeScript.font_serif()))
		if description != "":
			_unlocks_box.add_child(_line(description, ThemeScript.TEAL_MUTED, ThemeScript.PX_TINY + 4, ThemeScript.font_sans()))
	_unlocks_box.visible = true


# --- authored values -------------------------------------------------------

## The five authored breakdown rows. A captured run records no contract and
## therefore earns no XP (mission_controller records only on escape), so it
## shows the three authored "Unsuccessful" rows at +0 and nothing else; the
## time weight and the difficulty multiplier are only meaningful when won.
func _xp_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not _won:
		rows.append({"label": UIStringsScript.st_text("ST_PostMatch", "XP.Breakdown.Contract.Unsuccessful", ""), "value": "+0"})
		rows.append({"label": UIStringsScript.st_text("ST_PostMatch", "XP.Breakdown.Mission.Unsuccessful", ""), "value": "+0"})
		rows.append({"label": UIStringsScript.st_text("ST_PostMatch", "XP.Breakdown.Extraction.Unsuccessful", ""), "value": "+0"})
		return rows
	var gs: Node = _autoload("GameState")
	var minutes: float = maxf(_node_float(gs, "elapsed_sec", 0.0), 0.0) / 60.0
	var difficulty: int = _node_int(gs, "difficulty", 1)
	var mult: float = ProgressionScript.difficulty_xp_multiplier(difficulty)
	rows.append({"label": UIStringsScript.st_text("ST_PostMatch", "XP.Breakdown.Contract.Successful", ""),
		"value": "+" + _money(ProgressionScript.xp_award("contracts"))})
	rows.append({"label": UIStringsScript.st_text("ST_PostMatch", "XP.Breakdown.Mission.Successful", ""),
		"value": "+" + _money(ProgressionScript.xp_award("mission"))})
	rows.append({"label": UIStringsScript.st_text("ST_PostMatch", "XP.Breakdown.Extraction.Successful", ""),
		"value": "+" + _money(ProgressionScript.xp_award("win"))})
	rows.append({"label": UIStringsScript.st_text("ST_PostMatch", "XP.Breakdown.Time", ""),
		"value": "+" + _money(ProgressionScript.xp_award("time", {"minutes": minutes}))})
	rows.append({"label": UIStringsScript.st_text("ST_PostMatch", "XP.Breakdown.Difficulty", ""),
		"value": "×" + _mult_text(mult), "multiplier": true})
	return rows


## Difficulty-multiplied base the save actually awards (record_contract_complete).
func _expected_xp() -> int:
	if not _won:
		return 0
	var gs: Node = _autoload("GameState")
	var minutes: float = maxf(_node_float(gs, "elapsed_sec", 0.0), 0.0) / 60.0
	var base: int = ProgressionScript.xp_award("contracts") \
		+ ProgressionScript.xp_award("mission") \
		+ ProgressionScript.xp_award("win") \
		+ ProgressionScript.xp_award("time", {"minutes": minutes})
	var difficulty: int = _node_int(gs, "difficulty", 1)
	return int(roundf(float(base) * ProgressionScript.difficulty_xp_multiplier(difficulty)))


## Authored PostMatch.Contract.<order>.<Result> row ("Contract: Success"), using
## the payout record first because mission_controller banks before showing this
## screen; `info` and GameState are only fallbacks.
func _contract_outcome_line() -> String:
	var order: int = _contract_order()
	if order <= 0:
		return ""
	var key: String = "PostMatch.Contract.%d.%s" % [order, "Success" if _won else "Failure"]
	var row: String = UIStringsScript.st_text("ST_PostMatch", key, "")
	if row == "":
		return ""
	var head: String = UIStringsScript.st_text("ST_PostMatch", "PostMatch.Contract", "")
	if head == "":
		return row
	return "%s: %s" % [head, row]


# --- data access -----------------------------------------------------------

func _payout() -> Dictionary:
	var ss: Node = _autoload("SaveSystem")
	if ss != null and ss.has_method("get_last_match"):
		var value: Variant = ss.call("get_last_match")
		if value is Dictionary:
			var payout: Dictionary = value as Dictionary
			if str(payout.get("match_id", "")) != "":
				return payout
	if _score > 0:
		return {"kept": _score, "original": _score, "money_taken": _score, "stashed": 0}
	return {}


func _level_progress() -> Dictionary:
	var ss: Node = _autoload("SaveSystem")
	if ss != null and ss.has_method("get_level_progress"):
		var value: Variant = ss.call("get_level_progress")
		if value is Dictionary:
			return value as Dictionary
	return {"level": 1, "xp_in_level": 0, "xp_needed": ProgressionScript.level_up_xp()}


## Levels crossed by the measured award: the save already holds the post-match
## XP, so subtracting the award reconstructs the pre-match level exactly.
func _crossed_levels() -> Dictionary:
	if _xp_awarded < 0:
		return {}
	var ss: Node = _autoload("SaveSystem")
	if ss == null or not ss.has_method("level_for_xp") or not ss.has_method("xp_total_for_level"):
		return {}
	var level_after: int = int(_level_progress().get("level", 1))
	var in_level: int = int(_level_progress().get("xp_in_level", 0))
	var xp_after: int = int(ss.call("xp_total_for_level", level_after)) + in_level
	var xp_before: int = maxi(xp_after - _xp_awarded, 0)
	var level_before: int = int(ss.call("level_for_xp", xp_before))
	return {"before": level_before, "after": level_after, "up": level_after > level_before}


func _contract_order() -> int:
	var payout: Dictionary = _payout()
	var order: int = int(payout.get("contract_order", 0))
	if order <= 0:
		order = int(_info.get("order", _info.get("contract_order", 0)))
	if order <= 0:
		order = _node_int(_autoload("GameState"), "active_contract_order", 0)
	return order


func _currency() -> int:
	var ss: Node = _autoload("SaveSystem")
	if ss != null and ss.has_method("get_currency"):
		return int(ss.call("get_currency"))
	return 0


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


func _node_float(node: Node, property: String, fallback: float) -> float:
	if node == null:
		return fallback
	var value: Variant = node.get(property)
	if value is float:
		return float(value)
	if value is int:
		return float(value)
	return fallback


# --- small UI helpers ------------------------------------------------------

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


func _mult_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _on_continue_pressed() -> void:
	_play_ui("click")
	continue_requested.emit()


func _play_ui(cue: String) -> void:
	var am: Node = _autoload("AudioManager")
	if am != null and am.has_method("play_ui"):
		am.call("play_ui", cue)
