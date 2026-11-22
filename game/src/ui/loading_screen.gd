extends CanvasLayer
## Full-art Loading Screen overlay matching UE5 parity (T_loadingScreen_1.png):
## Full-brightness illustrated Kilcairn cityscape, centered animated teal-white
## ring spinner + LOADING..., and bottom-center gold THICK AS THIEVES logo.
## Preserves start_loading / set_progress / finish_loading API and internal _bar.

const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")

# T_loadingScreen_2 is the authored 16:9 KF12 splash (6400x3600, bright
# purple, bottom logo). T_loadingScreen_1 is a 2:1 dark variant whose centred
# logo collided with the loading spinner.
const LOADING_ART_PRIMARY: String = "res://assets/ue/Raw/Art/UI/Shell/SplashScreen/T_loadingScreen_2.png"
const LOADING_ART_ALT: String = "res://assets/ue/Raw/Art/UI/Shell/SplashScreen/T_loadingScreen_1.png"
const SPINNER_TEX_PATH: String = "res://assets/ue/Raw/Art/UI/Icons/T_Spinner_Full.png"
const LOGO_TEX_PATH: String = "res://assets/ue/Raw/Art/UI/Branding/T_TaT_Logo_Primary_White.png"

const SPINNER_SHADER_CODE: String = """
shader_type canvas_item;
uniform vec4 tint_color : source_color = vec4(0.70, 0.92, 0.96, 1.0);
void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float lum = max(max(src.r, src.g), src.b);
	COLOR = vec4(tint_color.rgb, lum * tint_color.a);
}
"""

var _backdrop: ColorRect
var _splash_rect: TextureRect
var _title_lbl: Label
var _subtitle_lbl: Label
var _bar: ProgressBar
var _status_lbl: Label
var _root: Control
var _spinner_rect: TextureRect
var _spinner_atlas: AtlasTexture
var _spinner_frame: float = 0.0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	if _spinner_atlas != null:
		_spinner_frame = fposmod(_spinner_frame + delta * 36.0, 64.0)
		var idx: int = int(_spinner_frame)
		var col: int = idx % 8
		var row: int = idx / 8
		_spinner_atlas.region = Rect2(col * 256.0, row * 256.0, 256.0, 256.0)
	elif _spinner_rect != null:
		_spinner_rect.rotation = fposmod(_spinner_rect.rotation + delta * 3.2, TAU)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.02, 0.025, 0.055, 1.0)
	_root.add_child(_backdrop)

	_splash_rect = TextureRect.new()
	_splash_rect.name = "LoadingSplashArt"
	_splash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_splash_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_splash_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_splash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art: Texture2D = _load_art(LOADING_ART_PRIMARY)
	if art == null:
		art = _load_art(LOADING_ART_ALT)
	if art != null:
		_splash_rect.texture = art
		_splash_rect.visible = true
	else:
		_splash_rect.visible = false
	_root.add_child(_splash_rect)

	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()

	# Center spinner + LOADING... matching UE5 reference screenshot.
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.custom_minimum_size = Vector2(460, 0)
	vb.add_theme_constant_override("separation", 8)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vb)

	var spin_wrap: CenterContainer = CenterContainer.new()
	spin_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(spin_wrap)

	_spinner_rect = TextureRect.new()
	_spinner_rect.name = "LoadingSpinner"
	_spinner_rect.custom_minimum_size = Vector2(56, 56)
	_spinner_rect.size = Vector2(56, 56)
	_spinner_rect.pivot_offset = Vector2(28, 28)
	_spinner_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spinner_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_spinner_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spin_tex: Texture2D = _load_art(SPINNER_TEX_PATH)
	if spin_tex != null:
		_spinner_atlas = AtlasTexture.new()
		_spinner_atlas.atlas = spin_tex
		_spinner_atlas.region = Rect2(0.0, 0.0, 256.0, 256.0)
		_spinner_rect.texture = _spinner_atlas
		var sh: Shader = Shader.new()
		sh.code = SPINNER_SHADER_CODE
		var sm: ShaderMaterial = ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("tint_color", Color(0.72, 0.92, 0.96, 0.96))
		_spinner_rect.material = sm
	spin_wrap.add_child(_spinner_rect)

	_title_lbl = Label.new()
	_title_lbl.name = "LoadingTitle"
	_title_lbl.text = "LOADING..."
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 24)
	_title_lbl.add_theme_color_override("font_color", Color(0.74, 0.88, 0.96, 0.98))
	_title_lbl.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.05, 0.9))
	_title_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	if serif != null:
		_title_lbl.add_theme_font_override("font", serif)
	vb.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_lbl.custom_minimum_size = Vector2(460, 0)
	_subtitle_lbl.add_theme_font_size_override("font_size", 14)
	_subtitle_lbl.add_theme_color_override("font_color", Color(0.78, 0.86, 0.92, 0.85))
	_subtitle_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_subtitle_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_subtitle_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if sans != null:
		_subtitle_lbl.add_theme_font_override("font", sans)
	_subtitle_lbl.visible = false
	vb.add_child(_subtitle_lbl)

	# P2-3: slim visible progress bar under the spinner (was permanently hidden).
	# Full-bleed art stays uncovered: 4px bar in the center column.
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 5.0
	_bar.custom_minimum_size = Vector2(280, 4)
	_bar.show_percentage = false
	_bar.visible = true
	var bar_bg: StyleBoxFlat = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.02, 0.05, 0.08, 0.85)
	bar_bg.border_color = ThemeScript.TEAL_BORDER
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(2)
	var bar_fg: StyleBoxFlat = StyleBoxFlat.new()
	bar_fg.bg_color = ThemeScript.TEAL_ACCENT
	bar_fg.set_corner_radius_all(2)
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", bar_fg)
	vb.add_child(_bar)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color(0.70, 0.84, 0.90, 0.90))
	_status_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_status_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_status_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if sans != null:
		_status_lbl.add_theme_font_override("font", sans)
	vb.add_child(_status_lbl)




## Show the overlay, reset progress to 5%, keep full-brightness T_loadingScreen_1 art.
func start_loading(title: String, clue: String, map_id: String) -> void:
	visible = true
	# S02/S10: loading screens are explicit digital silence (no music, no
	# narration) — fade the previous scene's ambience out before the load.
	if AudioManager != null and AudioManager.has_method("stop_all_beds"):
		AudioManager.stop_all_beds(0.35)
	if _bar != null:
		_bar.value = 5.0
	if _title_lbl != null:
		_title_lbl.text = "LOADING..."
	if _subtitle_lbl != null:
		var sub_txt: String = title.strip_edges()
		if clue.strip_edges() != "":
			sub_txt = (sub_txt + " — " + clue.strip_edges()) if sub_txt != "" else clue.strip_edges()
		# The splash art carries the branding; a five-line mission blurb over
		# the title was the KF12 mismatch. Keep the loading overlay quiet.
		_subtitle_lbl.text = ""
		_subtitle_lbl.visible = false
	if _status_lbl != null:
		_status_lbl.text = "Preparing sublevels..."
	_update_splash(map_id)


## Update progress: pct_0_to_1 in [0, 1] maps to bar 0..100.
func set_progress(pct_0_to_1: float, _status_text: String) -> void:
	var clamped: float = clampf(pct_0_to_1, 0.0, 1.0)
	if _bar != null:
		_bar.value = clamped * 100.0
	if _status_lbl != null:
		# Never surface loader internals ("Parsing JSON 12/14", "Batching
		# meshes 5769/5769") over the splash art. Keep the authored mood.
		if clamped < 0.32:
			_status_lbl.text = "Unlocking the doors..."
		elif clamped < 0.72:
			_status_lbl.text = "Raising the rooftops..."
		else:
			_status_lbl.text = "Lighting the lanterns..."


## Set 100%, hide and free so the level is revealed.
func finish_loading() -> void:
	if _bar != null:
		_bar.value = 100.0
	if _status_lbl != null:
		_status_lbl.text = "Ready."
	visible = false
	queue_free()


func _update_splash(_map_id: String) -> void:
	if _splash_rect == null:
		return
	var tex: Texture2D = _load_art(LOADING_ART_PRIMARY)
	if tex == null:
		tex = _load_art(LOADING_ART_ALT)
	if tex != null:
		_splash_rect.texture = tex
		_splash_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_splash_rect.visible = true
	else:
		_splash_rect.visible = false


func _load_art(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var t: Variant = ResourceLoader.load(path)
		if t is Texture2D:
			return t as Texture2D
	if FileAccess.file_exists(path):
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null
