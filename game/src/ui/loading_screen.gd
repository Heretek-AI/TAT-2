extends CanvasLayer
## Responsive Loading Screen overlay shown while contracts/sublevels stream in.
## Dark atmospheric backdrop + optional map splash, title, subtitle,
## progress bar and status line. Pauses nothing: PROCESS_MODE_ALWAYS.

var _backdrop: ColorRect
var _splash_rect: TextureRect
var _title_lbl: Label
var _subtitle_lbl: Label
var _bar: ProgressBar
var _status_lbl: Label
var _root: Control


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.03, 0.035, 0.06, 0.96)
	_root.add_child(_backdrop)

	_splash_rect = TextureRect.new()
	_splash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_splash_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_splash_rect.modulate = Color(1.0, 1.0, 1.0, 0.35)
	_splash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash_rect.visible = false
	_root.add_child(_splash_rect)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.custom_minimum_size = Vector2(560, 0)
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)

	_title_lbl = Label.new()
	_title_lbl.text = "LOADING CONTRACT..."
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 32)
	_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.84, 0.52))
	vb.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_lbl.custom_minimum_size = Vector2(560, 0)
	_subtitle_lbl.add_theme_font_size_override("font_size", 16)
	_subtitle_lbl.add_theme_color_override("font_color", Color(0.80, 0.82, 0.88))
	vb.add_child(_subtitle_lbl)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 5.0
	_bar.custom_minimum_size = Vector2(560, 22)
	_bar.show_percentage = true
	vb.add_child(_bar)

	_status_lbl = Label.new()
	_status_lbl.text = "Preparing sublevels..."
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 14)
	_status_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	vb.add_child(_status_lbl)


## Show the overlay, reset the bar to 5%, set texts and optional splash.
func start_loading(title: String, clue: String, map_id: String) -> void:
	visible = true
	if _bar != null:
		_bar.value = 5.0
	if _title_lbl != null:
		_title_lbl.text = "LOADING CONTRACT..."
	if _subtitle_lbl != null:
		if clue.strip_edges() == "":
			_subtitle_lbl.text = title
		else:
			_subtitle_lbl.text = title + "\n" + clue
	if _status_lbl != null:
		_status_lbl.text = "Preparing sublevels..."
	_update_splash(map_id)


## Update progress: pct_0_to_1 in [0, 1] maps to bar 0..100.
func set_progress(pct_0_to_1: float, status_text: String) -> void:
	var clamped: float = clampf(pct_0_to_1, 0.0, 1.0)
	if _bar != null:
		_bar.value = clamped * 100.0
	if _status_lbl != null:
		_status_lbl.text = status_text


## Set 100%, hide and free so the level is revealed.
func finish_loading() -> void:
	if _bar != null:
		_bar.value = 100.0
	if _status_lbl != null:
		_status_lbl.text = "Ready."
	visible = false
	queue_free()


func _update_splash(map_id: String) -> void:
	if _splash_rect == null:
		return
	var tex: Texture2D = _splash_for(map_id)
	if tex != null:
		_splash_rect.texture = tex
		_splash_rect.modulate = Color(1.0, 1.0, 1.0, 0.35)
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
	for p: String in ordered:
		if ResourceLoader.exists(p):
			var t: Texture2D = ResourceLoader.load(p) as Texture2D
			if t != null:
				return t
	return null
