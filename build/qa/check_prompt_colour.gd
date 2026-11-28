extends SceneTree
## Prompt-colour proof (round 3): the authored UE colour must RENDER as the
## authored sRGB hex. The UE payload stores a linear triple
## (0.124772, 0.155927, 0.838799); Godot 4 canvas colours are sRGB when
## rendering/rendering_device/hdr_2d=false (the default), so writing that
## linear triple as a Color rendered #2028D6 (Rec.709 luma ~51), not the
## authored #636EEC (luma ~117). The fix is Color.html("#636EEC") ==
## (0.388235, 0.431373, 0.925490).
##
## Headless (default): asserts the sRGB parse equals the literal (and differs
## from the UE-linear triple), then builds the real HUD prompt labels and reads
## their theme colour / shadow / outline overrides.
##
## Render (--render, Vulkan under Xvfb): draws a ColorRect + Label in
## Color.html("#636EEC"), reads the centre pixel of the swatch and prints its
## hex, so the canvas-sRGB contract is proven by a real frame instead of a
## readback of the value we just wrote (the falsifier's circularity).
##
##   tools/godot --headless --path game \
##     --script "$PWD/build/qa/check_prompt_colour.gd"
##
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "cd '$PWD' && xvfb-run -a -s '-screen 0 640x360x24' \
##      tools/godot --path game --rendering-driver vulkan \
##      --script '$PWD/build/qa/check_prompt_colour.gd' -- --render"

const AUTHORED_HEX: String = "#636EEC"
## Authored sRGB components of #636EEC (99/255, 110/255, 236/255).
const SRGB: Color = Color(0.388235, 0.431373, 0.925490, 1.0)
## The UE payload's linear triple; NOT a Godot sRGB literal (renders #2028D6).
const UE_LINEAR: Color = Color(0.124772, 0.155927, 0.838799, 1.0)
## project.godot: viewport 1280x720 with stretch/mode=canvas_items, so render at
## the base size (scale 1) and sample the swatch centre.
const BASE := Vector2i(1280, 720)
const SWATCH := Rect2i(320, 240, 640, 240)

var _checks: int = 0
var _fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("PROMPT_COLOUR ok ", what)
	else:
		_fails += 1
		printerr("PROMPT_COLOUR FAIL ", what)


func _want_hex() -> String:
	return Color.html(AUTHORED_HEX).to_html(false)


func _colour_delta(a: Color, b: Color) -> int:
	return maxi(
		absi(int(round(a.r * 255.0)) - int(round(b.r * 255.0))),
		maxi(
			absi(int(round(a.g * 255.0)) - int(round(b.g * 255.0))),
			absi(int(round(a.b * 255.0)) - int(round(b.b * 255.0)))
		)
	)


func _headless() -> void:
	var html: Color = Color.html(AUTHORED_HEX)
	_check(html.is_equal_approx(SRGB), "Color.html(#636EEC) == sRGB (0.388235,0.431373,0.925490)")
	_check(not html.is_equal_approx(UE_LINEAR), "Color.html(#636EEC) != the UE-linear triple")
	_check(not UE_LINEAR.is_equal_approx(SRGB), "UE-linear triple != the sRGB literal (the round-2 bug)")
	print("PROMPT_COLOUR hex authored=%s html=%s ue_linear=%s" % [
		AUTHORED_HEX, html.to_html(true), UE_LINEAR.to_html(true),
	])
	# Build the real HUD prompt labels and read their overrides back.
	var hud_script: GDScript = load("res://src/ui/hud.gd") as GDScript
	if hud_script == null:
		_check(false, "hud.gd loads")
		print("PROMPT_COLOUR_HEADLESS %s checks=%d fails=%d" % [
			"PASS" if _fails == 0 else "FAIL", _checks, _fails,
		])
		quit(0 if _fails == 0 else 1)
		return
	var hud: CanvasLayer = hud_script.new() as CanvasLayer
	var ui_root: Control = Control.new()
	ui_root.size = Vector2(1920.0, 1080.0)
	root.add_child(ui_root)
	hud.call("_build_reticle_and_prompt", ui_root)
	ui_root.add_child(hud)
	await process_frame
	var p: Label = hud.get("interact_lbl") as Label
	var s: Label = hud.get("_prompt_secondary_lbl") as Label
	_check(p != null and p.get_theme_color("font_color").is_equal_approx(html),
		"primary prompt uses Color.html(#636EEC)")
	_check(s != null and s.get_theme_color("font_color").is_equal_approx(html),
		"secondary prompt uses Color.html(#636EEC)")
	if p != null and s != null:
		_check(absf(p.get_theme_color("font_color").a - 1.0) < 0.0001
			and absf(s.get_theme_color("font_color").a - 1.0) < 0.0001,
			"both prompt rows are text alpha 1.0")
		_check(absf(p.get_theme_color("font_shadow_color").a - 0.75) < 0.0001
			and p.get_theme_constant("shadow_offset_x") == 1
			and p.get_theme_constant("shadow_offset_y") == 3,
			"primary authored shadow (1,3) alpha 0.75")
		_check(absf(s.get_theme_color("font_shadow_color").a - 0.75) < 0.0001
			and s.get_theme_constant("shadow_offset_x") == 4
			and s.get_theme_constant("shadow_offset_y") == 2,
			"secondary authored shadow (4,2) alpha 0.75")
		_check(s.get_theme_constant("outline_size") == 3
			and absf(s.get_theme_color("font_outline_color").a) < 0.0001,
			"secondary invisible outline 3 with alpha 0")
	hud.queue_free()
	print("PROMPT_COLOUR_HEADLESS %s checks=%d fails=%d" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails,
	])
	quit(0 if _fails == 0 else 1)


func _render() -> void:
	root.size = BASE
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.position = Vector2.ZERO
	bg.size = Vector2(BASE)
	root.add_child(bg)
	var swatch: ColorRect = ColorRect.new()
	swatch.color = Color.html(AUTHORED_HEX)
	swatch.position = Vector2(SWATCH.position)
	swatch.size = Vector2(SWATCH.size)
	root.add_child(swatch)
	var lbl: Label = Label.new()
	lbl.text = "LAUNCH"
	lbl.add_theme_color_override("font_color", Color.html(AUTHORED_HEX))
	lbl.add_theme_font_size_override("font_size", 72)
	lbl.position = Vector2(320, 60)
	lbl.size = Vector2(640, 120)
	root.add_child(lbl)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		printerr("PROMPT_COLOUR_RENDER FAIL empty image")
		quit(1)
		return
	var got: Color = img.get_pixel(SWATCH.position.x + SWATCH.size.x / 2, SWATCH.position.y + SWATCH.size.y / 2)
	var want: Color = Color.html(AUTHORED_HEX)
	var delta: int = _colour_delta(got, want)
	var ok: bool = delta <= 2
	print("PROMPT_COLOUR_RENDER pixel=%s hex=#%s expected=#%s delta8=%d label=#%s size=%dx%d %s" % [
		got, got.to_html(false), _want_hex(), delta,
		lbl.get_theme_color("font_color").to_html(false),
		img.get_width(), img.get_height(), "PASS" if ok else "FAIL",
	])
	quit(0 if ok else 1)


func _run() -> void:
	var render: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--render":
			render = true
	if render:
		await _render()
	else:
		await _headless()
