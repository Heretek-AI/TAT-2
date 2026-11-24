class_name ArtNouveauTheme
extends RefCounted
## Shared Art Nouveau styling: dark translucent panels with teal/gold filigree,
## section headers, keycap badges, typography helpers, and modal scaffolding.

const TEAL: Color = Color(0.30, 0.75, 0.72, 1.0)
const TEAL_DIM: Color = Color(0.22, 0.52, 0.52, 1.0)
const TEAL_DARK: Color = Color(0.07, 0.16, 0.17, 1.0)
const TEAL_PANEL_BG: Color = Color(0.032, 0.072, 0.092, 0.94)
const TEAL_CARD_BG: Color = Color(0.035, 0.078, 0.100, 0.86)
const TEAL_GROUP_BG: Color = Color(0.050, 0.118, 0.145, 0.90)
const TEAL_BORDER: Color = Color(0.26, 0.68, 0.70, 0.92)
const TEAL_BORDER_SOFT: Color = Color(0.24, 0.62, 0.65, 0.55)
const TEAL_ACCENT: Color = Color(0.55, 0.92, 0.94, 1.0)
const TEAL_TITLE: Color = Color(0.76, 0.94, 0.95, 1.0)
const TEAL_TEXT: Color = Color(0.88, 0.94, 0.95, 1.0)
const TEAL_MUTED: Color = Color(0.62, 0.78, 0.82, 0.90)
## P2-1 tokens (clears HARD_LIMIT 5.7): KF-verified pink/green/red accents
## previously inline at call sites. Values port the exact inline colors from
## wardrobe_ui.gd (LOCKED_PINK, hint pink) and ledger_ui.gd (completed /
## purchased greens, card-done border, insufficient red) into named tokens;
## no UE cooked source exists, so the theme file is the source of truth.
const PINK_LOCKED: Color = Color(1.0, 0.38, 0.72)
const PINK_HINT: Color = Color(0.95, 0.55, 0.65)
const GREEN_COMPLETED: Color = Color(0.45, 0.90, 0.65)
const GREEN_PURCHASED: Color = Color(0.45, 0.85, 0.45)
const GREEN_CARD_BORDER: Color = Color(0.32, 0.72, 0.56, 0.85)
const RED_INSUFFICIENT: Color = Color(0.9, 0.4, 0.35)
# Task-6 parity note (KF08/KF03-KF04 cite): purchase-green check, "Active"
# green, and pink LOCKED/padlock accents are verified on footage but have no
# cooked UE source in scope (was HARD_LIMIT 5.7). P2-1 pass adds the named
# tokens above (PINK_*/GREEN_*/RED_INSUFFICIENT) and routes call sites;
# never inline hex at call sites.

const GOLD: Color = Color(0.95, 0.80, 0.45, 1.0)
const GOLD_DIM: Color = Color(0.72, 0.55, 0.25, 1.0)
const GOLD_DARK: Color = Color(0.38, 0.28, 0.12, 1.0)
const IVORY: Color = Color(0.92, 0.89, 0.82, 1.0)
const PANEL_BG: Color = Color(0.045, 0.05, 0.085, 0.96)
const DIM_COLOR: Color = Color(0.008, 0.010, 0.022, 0.78)
const PROMPT_TEAL: Color = Color(0.55, 0.92, 0.95, 1.0)
const KEYCAP_WHITE_BG: Color = Color(0.94, 0.95, 0.98, 0.96)
const KEYCAP_DARK_TEXT: Color = Color(0.08, 0.10, 0.16, 1.0)
# P1 touch tokens (mobile_touch_ui.gd route): translucent aliases of the
# IVORY / GOLD / TEAL palette above, named so call sites never inline hex.
# Cooked source: no UE touch-theme values in scope; alphas are port-authored
# for finger-target legibility (HARD_LIMIT 5.2 class). UE path: n/a (mobile
# overlay); theme file is the source of truth:
# res://src/ui/art_nouveau_theme.gd.
const TOUCH_STICK_FILL: Color = Color(1.0, 1.0, 1.0, 0.10)
const TOUCH_STICK_RING: Color = Color(1.0, 0.86, 0.55, 0.45)
const TOUCH_KNOB_FILL: Color = Color(1.0, 0.88, 0.62, 0.30)
const TOUCH_KNOB_RING: Color = Color(1.0, 0.90, 0.70, 0.80)
const TOUCH_BTN_FILL: Color = Color(0.04, 0.06, 0.09, 0.42)
const TOUCH_BTN_BORDER: Color = Color(0.90, 0.78, 0.45, 0.55)
const TOUCH_BTN_LABEL: Color = Color(0.95, 0.90, 0.75, 1.0)
const TOUCH_PROMPT: Color = Color(0.65, 0.95, 1.0, 1.0)
const TOUCH_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.90)
const TOUCH_FLASH_DOWN: Color = Color(0.55, 0.42, 0.18, 0.62)
const TOUCH_GLOW_ACTIVE: Color = Color(0.55, 0.95, 1.0, 0.95)
const TOUCH_GLOW_IDLE: Color = Color(0.90, 0.78, 0.45, 0.35)
const TOUCH_ICON_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.85)
const TOUCH_BADGE_FULL: Color = Color(1.0, 1.0, 1.0, 1.0)
const TOUCH_BADGE_EMPTY: Color = Color(1.0, 1.0, 1.0, 0.35)

const FONT_SANS_PATH: String = "res://assets/ue/fonts/Raleway-Regular.ttf"
const FONT_ITALIC_PATH: String = "res://assets/ue/fonts/Raleway-Italic.ttf"
const FONT_SERIF_PATH: String = "res://assets/ue/fonts/SourceSerifPro-Bold.ttf"
const FONT_TYPEWRITER_PATH: String = "res://assets/ue/fonts/SpecialElite-Regular.ttf"
const DIVIDER_TEX_PATH: String = "res://assets/ue/Raw/Art/UI/Components/T_Divider.png"

## Shipped CJK faces used as fallbacks for the Latin display fonts so the
## ja/zh-Hans/zh-Hant locales render rather than showing tofu. Korean is not
## shipped in the extract (no folder), so it is deliberately absent.
const CJK_FALLBACK_PATHS: Array[String] = [
	"res://assets/ue/fonts/Traditional_Chinese/Noto_Serif_HK/NotoSerifHK-Regular.ttf",
	"res://assets/ue/fonts/Simplified_Chinese/NotoSerif/NotoSerifSC-Regular.ttf",
	"res://assets/ue/fonts/Japanese/NotoSerif/NotoSerifJP-Regular.ttf",
]

static var _font_cache: Dictionary = {}
static var _cjk_fallback_cache: Array[Font] = []


static func _cjk_fallbacks() -> Array[Font]:
	if not _cjk_fallback_cache.is_empty():
		return _cjk_fallback_cache
	for path: String in CJK_FALLBACK_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var f: Font = ResourceLoader.load(path) as Font
		if f != null:
			_cjk_fallback_cache.append(f)
	return _cjk_fallback_cache


static func _load_font(path: String) -> Font:
	if _font_cache.has(path):
		return _font_cache[path] as Font
	var f: Font = null
	if ResourceLoader.exists(path):
		f = ResourceLoader.load(path) as Font
	# Font.fallbacks is the engine fallback chain, used when the primary face
	# lacks a glyph (CJK locales). Latin glyphs still come from the display font.
	if f != null:
		var fallbacks: Array[Font] = _cjk_fallbacks()
		if not fallbacks.is_empty():
			f.fallbacks = fallbacks
	_font_cache[path] = f
	return f


static func font_sans() -> Font:
	return _load_font(FONT_SANS_PATH)


static func font_italic() -> Font:
	return _load_font(FONT_ITALIC_PATH)


static func font_serif() -> Font:
	return _load_font(FONT_SERIF_PATH)


static func font_typewriter() -> Font:
	return _load_font(FONT_TYPEWRITER_PATH)


static func panel_style(border_width: int = 2, radius: int = 8, bg: Color = PANEL_BG) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = TEAL_BORDER
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(22)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 12
	return style


static func teal_panel_style(border_width: int = 2, radius: int = 6, bg: Color = TEAL_PANEL_BG, margin: int = 18) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = TEAL_BORDER
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	style.shadow_color = Color(0.0, 0.01, 0.02, 0.55)
	style.shadow_size = 10
	return style


static func teal_card_style(border_width: int = 1, radius: int = 4, bg: Color = TEAL_CARD_BG, margin: int = 14) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = TEAL_BORDER
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	style.shadow_color = Color(0.0, 0.01, 0.02, 0.42)
	style.shadow_size = 6
	return style


static func inner_line_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(TEAL_DIM.r, TEAL_DIM.g, TEAL_DIM.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(0)
	return style


## P1 dedup target: settings group card (ex-settings_ui._make_group_card).
## Single source of truth for grouped teal cards: TEAL_GROUP_BG + TEAL_BORDER
## + 14/14/10/10 margins, header label 14 TEAL_ACCENT, soft divider.
## Cooked source: port-authored grouping (HARD_LIMIT 5.2); theme file is truth:
## res://src/ui/art_nouveau_theme.gd. Sentinel: fail loudly on empty title.
static func group_card(title_text: String) -> Dictionary:
	if title_text.strip_edges() == "":
		push_error("TAT-2 UI theme group_card: empty title (res://src/ui/art_nouveau_theme.gd)")
		assert(false, "group_card requires a non-empty title")
	var card: PanelContainer = PanelContainer.new()
	card.name = "Group_" + title_text.replace(" ", "")
	var style: StyleBoxFlat = teal_card_style(1, 6, TEAL_GROUP_BG, 0)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	var hdr: Label = Label.new()
	hdr.text = title_text.to_upper()
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", TEAL_ACCENT)
	vb.add_child(hdr)
	vb.add_child(teal_divider(0.45))
	return {"card": card, "vbox": vb}


static func style_button(btn: Button, primary: bool = false) -> void:
	style_teal_button(btn, primary)


static func style_teal_button(btn: Button, primary: bool = false) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_ALL
	var sans: Font = font_sans()
	if sans != null:
		btn.add_theme_font_override("font", sans)
	if primary:
		btn.add_theme_color_override("font_color", Color(0.96, 1.0, 0.99))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_pressed_color", TEAL_ACCENT)
		var normal: StyleBoxFlat = StyleBoxFlat.new()
		normal.bg_color = Color(0.11, 0.34, 0.37, 0.96)
		normal.border_color = TEAL_ACCENT
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(4)
		normal.set_content_margin_all(10)
		btn.add_theme_stylebox_override("normal", normal)
		var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.16, 0.46, 0.49, 0.98)
		hover.border_color = Color(0.75, 0.98, 0.98, 1.0)
		btn.add_theme_stylebox_override("hover", hover)
		var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		pressed.bg_color = Color(0.08, 0.24, 0.27, 0.98)
		btn.add_theme_stylebox_override("pressed", pressed)
	else:
		btn.add_theme_color_override("font_color", TEAL_TEXT)
		btn.add_theme_color_override("font_hover_color", TEAL_ACCENT)
		btn.add_theme_color_override("font_pressed_color", Color(0.96, 1.0, 0.99))
		var normal2: StyleBoxFlat = StyleBoxFlat.new()
		normal2.bg_color = Color(0.05, 0.11, 0.14, 0.92)
		normal2.border_color = Color(TEAL_BORDER.r, TEAL_BORDER.g, TEAL_BORDER.b, 0.72)
		normal2.set_border_width_all(1)
		normal2.set_corner_radius_all(4)
		normal2.set_content_margin_all(10)
		btn.add_theme_stylebox_override("normal", normal2)
		var hover2: StyleBoxFlat = normal2.duplicate() as StyleBoxFlat
		hover2.bg_color = Color(0.09, 0.21, 0.25, 0.96)
		hover2.border_color = TEAL_ACCENT
		btn.add_theme_stylebox_override("hover", hover2)
		var pressed2: StyleBoxFlat = normal2.duplicate() as StyleBoxFlat
		pressed2.bg_color = Color(0.04, 0.09, 0.12, 0.98)
		btn.add_theme_stylebox_override("pressed", pressed2)
	btn.add_theme_font_size_override("font_size", 15)


static func style_teal_tab(btn: Button, active: bool) -> void:
	if btn == null:
		return
	var st_box: StyleBoxFlat = StyleBoxFlat.new()
	st_box.set_border_width_all(1)
	st_box.set_corner_radius_all(4)
	st_box.set_content_margin_all(10)
	if active:
		st_box.bg_color = Color(0.14, 0.42, 0.44, 0.98)
		st_box.border_color = TEAL_ACCENT
		btn.add_theme_color_override("font_color", Color(0.96, 1.0, 0.99))
		btn.add_theme_color_override("font_disabled_color", Color(0.96, 1.0, 0.99))
	else:
		st_box.bg_color = Color(0.045, 0.11, 0.135, 0.92)
		st_box.border_color = Color(TEAL_BORDER.r, TEAL_BORDER.g, TEAL_BORDER.b, 0.55)
		btn.add_theme_color_override("font_color", TEAL_TEXT)
		btn.add_theme_color_override("font_disabled_color", TEAL_MUTED)
	btn.add_theme_stylebox_override("normal", st_box)
	btn.add_theme_stylebox_override("pressed", st_box)
	btn.add_theme_stylebox_override("disabled", st_box)
	var hov: StyleBoxFlat = st_box.duplicate() as StyleBoxFlat
	hov.border_color = TEAL_ACCENT
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_font_size_override("font_size", 15)


static func style_teal_option(opt: OptionButton) -> void:
	if opt == null:
		return
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.045, 0.105, 0.13, 0.94)
	normal.border_color = Color(TEAL_BORDER.r, TEAL_BORDER.g, TEAL_BORDER.b, 0.78)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.08, 0.19, 0.23, 0.96)
	hover.border_color = TEAL_ACCENT
	opt.add_theme_stylebox_override("normal", normal)
	opt.add_theme_stylebox_override("hover", hover)
	opt.add_theme_stylebox_override("pressed", hover)
	opt.add_theme_color_override("font_color", TEAL_TEXT)
	opt.add_theme_color_override("font_hover_color", Color(0.96, 1.0, 1.0))
	opt.add_theme_font_size_override("font_size", 14)


static func section_header(text: String, font_size: int = 18) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left: ColorRect = ColorRect.new()
	left.color = Color(TEAL_BORDER.r, TEAL_BORDER.g, TEAL_BORDER.b, 0.65)
	left.custom_minimum_size = Vector2(26, 1)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	var lbl: Label = Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", TEAL_ACCENT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	var right: ColorRect = ColorRect.new()
	right.color = Color(TEAL_BORDER.r, TEAL_BORDER.g, TEAL_BORDER.b, 0.35)
	right.custom_minimum_size = Vector2(0, 1)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	return row


static func divider(alpha: float = 0.42) -> Control:
	return teal_divider(alpha)


static func teal_divider(alpha: float = 0.45) -> Control:
	if ResourceLoader.exists(DIVIDER_TEX_PATH):
		var tex: Texture2D = ResourceLoader.load(DIVIDER_TEX_PATH) as Texture2D
		if tex != null:
			var tr: TextureRect = TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.custom_minimum_size = Vector2(0, 6)
			tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tr.modulate = Color(TEAL_ACCENT.r, TEAL_ACCENT.g, TEAL_ACCENT.b, clampf(alpha * 1.4, 0.0, 0.85))
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return tr
	var line: ColorRect = ColorRect.new()
	line.color = Color(TEAL_BORDER.r, TEAL_BORDER.g, TEAL_BORDER.b, alpha)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


static func keycap(text: String, font_size: int = 14) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.13, 0.16, 0.96)
	style.border_color = TEAL_ACCENT
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", style)
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", TEAL_ACCENT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)
	return badge


static func white_keycap(text: String, font_size: int = 12) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = KEYCAP_WHITE_BG
	style.border_color = Color(0.75, 0.82, 0.92, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", style)
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", KEYCAP_DARK_TEXT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)
	return badge


static func prompt_label(text: String, font_size: int = 15) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", PROMPT_TEAL)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


static func add_filigree(panel: PanelContainer, inset: float = 5.0, arm: float = 24.0) -> Control:
	return add_teal_filigree(panel, inset, arm)


static func add_teal_filigree(panel: PanelContainer, inset: float = 4.0, arm: float = 22.0) -> Control:
	var overlay: Control = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(overlay)
	# Inner hairline frame (teal Art Nouveau double border).
	var frame: ReferenceRect = ReferenceRect.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = inset
	frame.offset_top = inset
	frame.offset_right = -inset
	frame.offset_bottom = -inset
	frame.border_color = Color(TEAL_BORDER.r, TEAL_BORDER.g, TEAL_BORDER.b, 0.48)
	frame.border_width = 1.0
	frame.editor_only = false
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(frame)
	# Four L-shaped teal corner flourishes.
	for i: int in range(4):
		var corner: Control = Control.new()
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 0:
			corner.set_anchors_preset(Control.PRESET_TOP_LEFT)
			corner.position = Vector2(inset, inset)
		elif i == 1:
			corner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			corner.position = Vector2(-inset, inset)
		elif i == 2:
			corner.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			corner.position = Vector2(inset, -inset)
		else:
			corner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			corner.position = Vector2(-inset, -inset)
		var h_arm: ColorRect = ColorRect.new()
		h_arm.color = Color(TEAL_ACCENT.r, TEAL_ACCENT.g, TEAL_ACCENT.b, 0.88)
		h_arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h_arm.size = Vector2(arm, 2.0)
		h_arm.position = Vector2(-arm if (i == 1 or i == 3) else 0.0, -2.0 if (i == 2 or i == 3) else 0.0)
		corner.add_child(h_arm)
		var v_arm: ColorRect = ColorRect.new()
		v_arm.color = Color(TEAL_ACCENT.r, TEAL_ACCENT.g, TEAL_ACCENT.b, 0.88)
		v_arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v_arm.size = Vector2(2.0, arm)
		v_arm.position = Vector2(-2.0 if (i == 1 or i == 3) else 0.0, -arm if (i == 2 or i == 3) else 0.0)
		corner.add_child(v_arm)
		overlay.add_child(corner)
	# Small center-top diamond flourish.
	var gem_holder: Control = Control.new()
	gem_holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	gem_holder.position = Vector2(-4.0, inset - 3.0)
	gem_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gem: ColorRect = ColorRect.new()
	gem.color = Color(TEAL_ACCENT.r, TEAL_ACCENT.g, TEAL_ACCENT.b, 0.85)
	gem.size = Vector2(7.0, 7.0)
	gem.rotation_degrees = 45.0
	gem.pivot_offset = Vector2(3.5, 3.5)
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem_holder.add_child(gem)
	overlay.add_child(gem_holder)
	return overlay


static func make_modal(parent: CanvasLayer, min_size: Vector2, title_text: String, subtitle: String = "") -> Dictionary:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(root)
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = DIM_COLOR
	root.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", teal_panel_style())
	center.add_child(panel)
	add_teal_filigree(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	var title: Label = Label.new()
	title.text = title_text.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", TEAL_TITLE)
	var serif: Font = font_serif()
	if serif != null:
		title.add_theme_font_override("font", serif)
	vbox.add_child(title)
	if subtitle != "":
		var sub: Label = Label.new()
		sub.text = subtitle.to_upper()
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 13)
		sub.add_theme_color_override("font_color", TEAL_MUTED)
		vbox.add_child(sub)
	vbox.add_child(teal_divider())
	var out: Dictionary = {
		"root": root,
		"dim": dim,
		"center": center,
		"panel": panel,
		"vbox": vbox,
		"title": title,
	}
	return out


## Drops cached FontFile resources so fonts do not survive shutdown.
static func cleanup_static_caches() -> void:
	_font_cache.clear()
	_cjk_fallback_cache.clear()
