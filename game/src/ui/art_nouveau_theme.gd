class_name ArtNouveauTheme
extends RefCounted
## Shared Art Nouveau styling: dark translucent panels with teal/gold filigree,
## section headers, keycap badges, and modal scaffolding.

const TEAL: Color = Color(0.30, 0.75, 0.72, 1.0)
const TEAL_DIM: Color = Color(0.22, 0.52, 0.52, 1.0)
const TEAL_DARK: Color = Color(0.07, 0.16, 0.17, 1.0)
const GOLD: Color = Color(0.95, 0.80, 0.45, 1.0)
const GOLD_DIM: Color = Color(0.72, 0.55, 0.25, 1.0)
const GOLD_DARK: Color = Color(0.38, 0.28, 0.12, 1.0)
const IVORY: Color = Color(0.92, 0.89, 0.82, 1.0)
const PANEL_BG: Color = Color(0.045, 0.05, 0.085, 0.96)
const DIM_COLOR: Color = Color(0.008, 0.010, 0.022, 0.78)
const PROMPT_TEAL: Color = Color(0.55, 0.92, 0.95, 1.0)


static func panel_style(border_width: int = 2, radius: int = 8, bg: Color = PANEL_BG) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = GOLD_DIM
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(22)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 12
	return style


static func inner_line_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(TEAL_DIM.r, TEAL_DIM.g, TEAL_DIM.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(0)
	return style


static func style_button(btn: Button, primary: bool = false) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_ALL
	if primary:
		btn.add_theme_color_override("font_color", Color(0.08, 0.07, 0.04))
		btn.add_theme_color_override("font_hover_color", Color(0.05, 0.05, 0.02))
		var normal: StyleBoxFlat = StyleBoxFlat.new()
		normal.bg_color = GOLD
		normal.border_color = GOLD_DARK
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(5)
		normal.set_content_margin_all(10)
		btn.add_theme_stylebox_override("normal", normal)
		var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(1.0, 0.87, 0.55)
		btn.add_theme_stylebox_override("hover", hover)
		var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		pressed.bg_color = GOLD_DIM
		btn.add_theme_stylebox_override("pressed", pressed)
	else:
		btn.add_theme_color_override("font_color", IVORY)
		btn.add_theme_color_override("font_hover_color", GOLD)
		var normal2: StyleBoxFlat = StyleBoxFlat.new()
		normal2.bg_color = Color(0.10, 0.11, 0.17, 0.95)
		normal2.border_color = Color(TEAL_DIM.r, TEAL_DIM.g, TEAL_DIM.b, 0.8)
		normal2.set_border_width_all(1)
		normal2.set_corner_radius_all(5)
		normal2.set_content_margin_all(10)
		btn.add_theme_stylebox_override("normal", normal2)
		var hover2: StyleBoxFlat = normal2.duplicate() as StyleBoxFlat
		hover2.border_color = GOLD_DIM
		btn.add_theme_stylebox_override("hover", hover2)
		var pressed2: StyleBoxFlat = normal2.duplicate() as StyleBoxFlat
		pressed2.bg_color = Color(0.06, 0.08, 0.12, 0.98)
		btn.add_theme_stylebox_override("pressed", pressed2)
	btn.add_theme_font_size_override("font_size", 16)


static func section_header(text: String, font_size: int = 18) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left: ColorRect = ColorRect.new()
	left.color = Color(GOLD_DIM.r, GOLD_DIM.g, GOLD_DIM.b, 0.65)
	left.custom_minimum_size = Vector2(26, 1)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	var lbl: Label = Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", GOLD)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	var right: ColorRect = ColorRect.new()
	right.color = Color(GOLD_DIM.r, GOLD_DIM.g, GOLD_DIM.b, 0.35)
	right.custom_minimum_size = Vector2(0, 1)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	return row


static func divider(alpha: float = 0.35) -> ColorRect:
	var line: ColorRect = ColorRect.new()
	line.color = Color(GOLD_DIM.r, GOLD_DIM.g, GOLD_DIM.b, alpha)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


static func keycap(text: String, font_size: int = 14) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.15, 0.97)
	style.border_color = GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	badge.add_theme_stylebox_override("panel", style)
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", GOLD)
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


static func add_filigree(panel: PanelContainer, inset: float = 5.0, arm: float = 26.0) -> Control:
	var overlay: Control = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(overlay)
	# Inner hairline frame (Control accent).
	var frame: ReferenceRect = ReferenceRect.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = inset
	frame.offset_top = inset
	frame.offset_right = -inset
	frame.offset_bottom = -inset
	frame.border_color = Color(TEAL_DIM.r, TEAL_DIM.g, TEAL_DIM.b, 0.55)
	frame.border_width = 1.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(frame)
	# Four L-shaped gold corner flourishes (pure Control hairlines).
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
		h_arm.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.95)
		h_arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h_arm.size = Vector2(arm, 2.0)
		h_arm.position = Vector2(-arm if (i == 1 or i == 3) else 0.0, -2.0 if (i == 2 or i == 3) else 0.0)
		corner.add_child(h_arm)
		var v_arm: ColorRect = ColorRect.new()
		v_arm.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.95)
		v_arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v_arm.size = Vector2(2.0, arm)
		v_arm.position = Vector2(-2.0 if (i == 1 or i == 3) else 0.0, -arm if (i == 2 or i == 3) else 0.0)
		corner.add_child(v_arm)
		overlay.add_child(corner)
	# Small center-top diamond flourish.
	var gem_holder: Control = Control.new()
	gem_holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	gem_holder.position = Vector2(-5.0, inset - 3.0)
	gem_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gem: ColorRect = ColorRect.new()
	gem.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
	gem.size = Vector2(8.0, 8.0)
	gem.rotation_degrees = 45.0
	gem.pivot_offset = Vector2(4.0, 4.0)
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
	panel.add_theme_stylebox_override("panel", panel_style())
	center.add_child(panel)
	add_filigree(panel)
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
	title.add_theme_color_override("font_color", GOLD)
	vbox.add_child(title)
	if subtitle != "":
		var sub: Label = Label.new()
		sub.text = subtitle.to_upper()
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 13)
		sub.add_theme_color_override("font_color", Color(TEAL.r, TEAL.g, TEAL.b, 0.9))
		vbox.add_child(sub)
	vbox.add_child(divider())
	var out: Dictionary = {
		"root": root,
		"dim": dim,
		"center": center,
		"panel": panel,
		"vbox": vbox,
		"title": title,
	}
	return out
