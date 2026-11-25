class_name TutorialUI
extends CanvasLayer
## Authored FTUE / tutorial browser (W9-P3-C1).
##
## The shipped game has no standalone tutorial index screen: its copy lives in
## three StringTables (`ST_Tutorial` 75 rows, `ST_Tutorial_Infographics` 22,
## `ST_Tutorial_ThievesDen` 12) and every row is UE rich text with inline input
## icons. This screen indexes those rows by their authored key prefix and
## renders each body through `TutorialText.render()`, which resolves
## `<img id=".."/>` to the live bound glyph and the authored `<Highlight>` /
## `<Danger>` / `<Special>` / `<Noise>` colours. No prose is written here: the
## only visible text is the authored body, the authored key id (a stable id,
## not copy), the authored category labels where they exist, and the 4 labelled
## port strings below.
##
## Category labels: `Controls` is authored (`ST_Settings.Settings.Controls.
## Header`) and `Clues` is authored (`ST_MapTool.CluePage.Clues`). The shipped
## tables carry no category-title rows for objectives / infographics / the
## Thieves' Den, so those three are marked port labels.

signal closed()
## Emitted by the "Play Tutorial" button (authored
## `ST_Screens.Screen.MainMenu.PlayTutorial`); the caller owns the FTUE start.
signal start_tutorial_requested()

const UIStringsScript := preload("res://src/ui/ui_strings.gd")
const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")
const FocusNavScript := preload("res://src/ui/focus_nav.gd")
const TutorialTextScript := preload("res://src/ui/tutorial_text.gd")

const PANEL_MIN_SIZE: Vector2 = Vector2(1100, 660)
const DIM_COLOR: Color = Color(0.008, 0.012, 0.025, 0.86)
const SCROLL_MIN_HEIGHT: int = 450
const TAB_WIDTH: int = 240

const TUTORIAL_TABLE: String = "ST_Tutorial"
## Generated FTUE movie index (`tools/convert_videos.py`): the screen reads it to
## verify the authored video ids. Playback stays blocked (no VideoStreamPlayer in
## the port yet), which is why the ids are only used for the [ VIDEO ] marker.
const VIDEOS_PATH: String = "res://data/generated/videos.json"
const INFO_TABLE: String = "ST_Tutorial_Infographics"
const DEN_TABLE: String = "ST_Tutorial_ThievesDen"

const CATEGORY_OBJECTIVES: String = "objectives"
const CATEGORY_CONTROLS: String = "controls"
const CATEGORY_INFOGRAPHICS: String = "infographics"
const CATEGORY_STORY: String = "story"
const CATEGORY_DEN: String = "den"
## Fixed display order; a category with no authored rows is not shown.
const CATEGORY_ORDER: Array[String] = [
	CATEGORY_OBJECTIVES, CATEGORY_CONTROLS, CATEGORY_INFOGRAPHICS,
	CATEGORY_STORY, CATEGORY_DEN,
]

## PORT LABELS (3): the authored tables have no category-title rows for these.
const PORT_OBJECTIVES: String = "Objectives"
const PORT_INFOGRAPHICS: String = "Infographics"
const PORT_DEN: String = "Thieves' Den"
## PORT LABEL (4): a structural marker for a video-only infographic row. It is
## emitted only when an authored table has no body for a row that videos.json
## does ship; today every such row has prose, so zero are rendered.
const PORT_VIDEO: String = "[ VIDEO ]"

## Authored video ids from `game/data/generated/videos.json` (15 FTUE movies).
## The row -> video binding is a labelled port inference from the id names (the
## UE blueprint that owns the binding is not in the extract); it is used ONLY to
## decide whether a body-less row could show the [ VIDEO ] marker.
const VIDEO_ROW_IDS: Dictionary = {
	"Tut_Info_Security_Turret": "Lean_and_turret_video",
	"Tut_Info_Smoke_Bomb_LOS": "SmokeBomb_LOS_video",
	"Tut_Info_Stealth_Orb_Intro": "ShadowStealth_01_video",
	"Tut_Info_Stealth_Orb_Continued": "ShadowStealth_02_video",
	"Tut_Info_Take_Down": "Takedown_01_video",
	"Tut_Info_Lockpicking": "lockpicking_tutorial_video",
}

static var _video_index: Dictionary = {}
var _built: bool = false
var _root: Control = null
var _panel: PanelContainer = null
var _tabs_box: VBoxContainer = null
var _page: VBoxContainer = null
var _scroll: ScrollContainer = null
var _back_btn: Button = null
var _start_btn: Button = null
var _tab_buttons: Dictionary = {}
var _groups: Dictionary = {}
var _active: String = ""


func _ready() -> void:
	visible = false
	_ensure_built()


func open_tutorial() -> void:
	_ensure_built()
	visible = true
	_show_category(_first_category())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	FocusNavScript.install_and_focus(_panel)


## `name` accepts the category key ("controls") or its visible label
## ("Controls"); an unknown name falls back to the first authored category.
func open_category(name: String) -> void:
	_ensure_built()
	visible = true
	var key: String = _resolve_category(name)
	_show_category(key if key != "" else _first_category())
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


func category_key_for_label(name: String) -> String:
	return _resolve_category(name)


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
	load_video_index()
	_built = true
	_build_catalog()
	_root = Control.new()
	_root.name = "TutorialRoot"
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
	_panel.name = "TutorialPanel"
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	_panel.add_theme_stylebox_override("panel",
		ThemeScript.teal_panel_style(2, 6, ThemeScript.TEAL_PANEL_BG, 20))
	center.add_child(_panel)
	ThemeScript.add_authored_frame(_panel, true, 0)
	ThemeScript.add_teal_filigree(_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)

	var title: Label = Label.new()
	title.name = "TutorialTitle"
	# Authored entry label for the tutorial menu item.
	title.text = UIStringsScript.st_text("ST_Settings", "Settings.Gameplay.ShowTutorials", "").to_upper()
	title.add_theme_font_size_override("font_size", ThemeScript.PX_HEADER)
	title.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	_apply_font(title, ThemeScript.font_display())
	vb.add_child(title)
	vb.add_child(ThemeScript.teal_divider(0.55))

	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)

	_tabs_box = VBoxContainer.new()
	_tabs_box.name = "TutorialCategories"
	_tabs_box.custom_minimum_size = Vector2(TAB_WIDTH, 0)
	_tabs_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tabs_box.add_theme_constant_override("separation", 6)
	body.add_child(_tabs_box)
	_build_tabs()

	_scroll = ScrollContainer.new()
	_scroll.name = "TutorialScroll"
	_scroll.custom_minimum_size = Vector2(0, SCROLL_MIN_HEIGHT)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_page = VBoxContainer.new()
	_page.name = "TutorialPage"
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 8)
	_scroll.add_child(_page)

	vb.add_child(ThemeScript.teal_divider(0.45))
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vb.add_child(footer)
	_start_btn = Button.new()
	_start_btn.name = "PlayTutorialButton"
	_start_btn.text = UIStringsScript.st_upper("ST_Screens", "Screen.MainMenu.PlayTutorial", "")
	_start_btn.custom_minimum_size = Vector2(240, 42)
	ThemeScript.style_teal_button(_start_btn, true, ThemeScript.PX_BODY)
	_start_btn.pressed.connect(_on_start_pressed)
	footer.add_child(_start_btn)
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


func _build_tabs() -> void:
	_tab_buttons.clear()
	for key: String in CATEGORY_ORDER:
		var rows: Array = _groups.get(key, []) as Array
		if rows.is_empty():
			continue
		var btn: Button = Button.new()
		btn.name = "TutorialTab_" + key
		btn.text = _category_label(key)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(TAB_WIDTH, 40)
		ThemeScript.style_teal_tab(btn, false)
		btn.pressed.connect(_show_category.bind(key))
		_tabs_box.add_child(btn)
		_tab_buttons[key] = btn


# --- authored index --------------------------------------------------------

## Build the category index from the three authored tables' own row order.
## Prefix rules mirror the shipped FTUE flow (objective prompts, control
## prompts, infographics, Fey/clue/contract story rows, Thieves' Den walkthrough);
## anything outside them lands in the story group instead of being dropped.
## Real read of the generated movie index: {id: path}. A missing/broken file
## leaves the index empty and no video marker is ever claimed.
static func load_video_index() -> Dictionary:
	_video_index.clear()
	if not FileAccess.file_exists(VIDEOS_PATH):
		return _video_index
	var f: FileAccess = FileAccess.open(VIDEOS_PATH, FileAccess.READ)
	if f == null:
		return _video_index
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		return _video_index
	for row_v: Variant in (parsed as Array):
		if row_v is Dictionary:
			var id: String = str((row_v as Dictionary).get("id", ""))
			if id != "":
				_video_index[id] = str((row_v as Dictionary).get("path", ""))
	return _video_index


static func video_count() -> int:
	if _video_index.is_empty():
		load_video_index()
	return _video_index.size()


func _build_catalog() -> void:
	_groups.clear()
	for key: String in CATEGORY_ORDER:
		_groups[key] = []
	_append_table(TUTORIAL_TABLE)
	_append_table(INFO_TABLE)
	_append_table(DEN_TABLE)


func _append_table(table_name: String) -> void:
	var rows: Dictionary = UIStringsScript.table(table_name)
	var info_rows: Dictionary = UIStringsScript.table(INFO_TABLE)
	for key_v: Variant in rows.keys():
		var key: String = str(key_v)
		# The shipped FTUE data asset uses the ST_Tutorial_Infographics prose for
		# these two keys; the older ST_Tutorial rows differ and are unused
		# (p3-facts-screens §a2). Prefer the infographic row, skip the duplicate.
		if table_name == TUTORIAL_TABLE and info_rows.has(key):
			continue
		var body: String = str(rows[key_v])
		var category: String = _classify(table_name, key)
		var list: Array = _groups.get(category, []) as Array
		list.append({"key": key, "body": body, "table": table_name})
		_groups[category] = list


func _classify(table_name: String, key: String) -> String:
	if table_name == DEN_TABLE:
		return CATEGORY_DEN
	if table_name == INFO_TABLE:
		return CATEGORY_INFOGRAPHICS
	if key.begins_with("Tut_Objective_") or key.begins_with("Tut_Quest_Objective"):
		return CATEGORY_OBJECTIVES
	if key.begins_with("Tut_Use_") or key.begins_with("Tut_Equip_") \
			or key.begins_with("Tut_Crank_") or key.begins_with("Tut_Movement_") \
			or key == "Tut_Learn_Lockpicking":
		return CATEGORY_CONTROLS
	if key.begins_with("Tut_Info_") or key.begins_with("Tut_HUD_") \
			or key == "Tut_Smoke_Bomb_Blocks_LOS":
		return CATEGORY_INFOGRAPHICS
	return CATEGORY_STORY


func _category_label(key: String) -> String:
	match key:
		CATEGORY_CONTROLS:
			# Authored: ST_Settings.Settings.Controls.Header.
			return UIStringsScript.st_text("ST_Settings", "Settings.Controls.Header", "")
		CATEGORY_STORY:
			# Authored: ST_MapTool.CluePage.Clues.
			return UIStringsScript.st_text("ST_MapTool", "CluePage.Clues", "")
		CATEGORY_OBJECTIVES:
			return PORT_OBJECTIVES
		CATEGORY_INFOGRAPHICS:
			return PORT_INFOGRAPHICS
		CATEGORY_DEN:
			return PORT_DEN
	return key


func _resolve_category(name: String) -> String:
	var clean: String = name.strip_edges().to_lower()
	if clean == "":
		return ""
	if _groups.has(clean) and not (_groups.get(clean, []) as Array).is_empty():
		return clean
	for key: String in CATEGORY_ORDER:
		if _category_label(key).to_lower() == clean:
			return key
	return ""


func _first_category() -> String:
	for key: String in CATEGORY_ORDER:
		if not (_groups.get(key, []) as Array).is_empty():
			return key
	return ""


# --- page ------------------------------------------------------------------

func _show_category(key: String) -> void:
	if key == "":
		return
	_active = key
	for tab_key: Variant in _tab_buttons.keys():
		var btn: Button = _tab_buttons[tab_key] as Button
		var active: bool = str(tab_key) == key
		btn.disabled = active
		ThemeScript.style_teal_tab(btn, active)
	_rebuild_page()
	if _scroll != null:
		_scroll.scroll_vertical = 0
	FocusNavScript.install(_panel)


func _rebuild_page() -> void:
	if _page == null:
		return
	_clear(_page)
	var rows: Array = _groups.get(_active, []) as Array
	for row_v: Variant in rows:
		if not (row_v is Dictionary):
			continue
		var entry: Dictionary = row_v as Dictionary
		_page.add_child(_entry_card(entry))


## One authored entry. There is no per-entry title row in the shipped tables,
## so the authored key id is shown as a small muted technical id and the body
## (rendered through TutorialText) is the copy. A [ VIDEO ] marker is added
## only for a body-less row whose video id is authored in videos.json.
func _entry_card(entry: Dictionary) -> Control:
	var key: String = str(entry.get("key", ""))
	var body_raw: String = str(entry.get("body", ""))
	var card: PanelContainer = PanelContainer.new()
	# Table-qualified: Tut_Info_Ammo_Refills / Tut_Info_Stashes / Tut_Info_Zipwire
	# ship in BOTH ST_Tutorial and ST_Tutorial_Infographics, so a bare key name
	# would collide and Godot would auto-rename the later card.
	card.name = "TutorialCard_%s_%s" % [str(entry.get("table", "")), key]
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
		ThemeScript.teal_card_style(1, 5, ThemeScript.TEAL_GROUP_BG, 12))
	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var id_lbl: Label = Label.new()
	# Authored table:key id (technical, not copy); the shipped tables use this
	# exact form as the locres key (`ST_Tutorial.Tut_Fey_Intro`).
	id_lbl.text = "%s.%s" % [str(entry.get("table", "")), key]
	id_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_TINY + 2)
	id_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	_apply_font(id_lbl, ThemeScript.font_typewriter())
	vb.add_child(id_lbl)
	var rendered: String = TutorialTextScript.render(body_raw, "")
	if rendered.strip_edges() != "":
		var rich: RichTextLabel = RichTextLabel.new()
		rich.name = "Body"
		rich.bbcode_enabled = true
		rich.fit_content = true
		rich.scroll_active = false
		rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rich.add_theme_font_override("normal_font", ThemeScript.font_sans())
		rich.add_theme_font_size_override("normal_font_size", ThemeScript.PX_SESSION)
		rich.add_theme_color_override("default_color", ThemeScript.TEAL_TEXT)
		rich.text = rendered
		# The body is read-only copy, not a pad target: keeping it FOCUS_NONE
		# leaves the focus ring on the category tabs + footer (a 25-card page
		# must not become a 25-stop focus chain that never scrolls into view).
		rich.focus_mode = Control.FOCUS_NONE
		vb.add_child(rich)
	elif str(VIDEO_ROW_IDS.get(key, "")) != "" and _video_index.has(str(VIDEO_ROW_IDS.get(key, ""))):
		var marker: Label = Label.new()
		marker.text = PORT_VIDEO
		marker.add_theme_font_size_override("font_size", ThemeScript.PX_SESSION)
		marker.add_theme_color_override("font_color", ThemeScript.GOLD)
		_apply_font(marker, ThemeScript.font_display())
		vb.add_child(marker)
	return card


# --- helpers ---------------------------------------------------------------

func _on_start_pressed() -> void:
	_play_ui("click")
	start_tutorial_requested.emit()


func _apply_font(control: Control, font: Font) -> void:
	if control != null and font != null:
		control.add_theme_font_override("font", font)


func _clear(box: VBoxContainer) -> void:
	if box == null:
		return
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _play_ui(cue: String) -> void:
	var am: Node = _autoload("AudioManager")
	if am != null and am.has_method("play_ui"):
		am.call("play_ui", cue)


func _autoload(node_name: String) -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
