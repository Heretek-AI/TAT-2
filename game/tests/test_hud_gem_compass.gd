extends SceneTree
## W5D standalone HUD Light Gem / compass structural test.
##
## Reference HUD (clip_1795033698901):
##   * the Light Gem is a glazed sphere, not a cut diamond;
##   * the compass shows the one heading nearest the centre tick, not a
##     580 px ribbon carrying every cardinal.
##
## Defects pinned here:
##   * STEALTH_ORB_SHADER masked with abs(p.x)+abs(p.y) (a diamond) while its
##     normals already assumed a unit sphere. The mask is now length(p).
##   * _build_compass_strip() stretched T_compass_lines across 580 px and
##     scrolled a thirteen-cardinal ribbon. Only compass_lbl is visible now,
##     with the authored strip as a small centred line.
##
## Run:
##   XDG_DATA_HOME=/tmp/opencode/w5d-data tools/godot --headless --path game \
##     --script res://tests/test_hud_gem_compass.gd

const HUD_PATH := "res://src/ui/hud.gd"

var fails: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _shader_block(src: String, start_marker: String, end_marker: String) -> String:
	var a: int = src.find(start_marker)
	var b: int = src.find(end_marker, a + 1) if a >= 0 else -1
	if a < 0 or b < 0:
		return ""
	return src.substr(a, b - a)


func _initialize() -> void:
	await process_frame
	var src: String = FileAccess.get_file_as_string(HUD_PATH)
	var orb_shader: String = _shader_block(src, "const STEALTH_ORB_SHADER", "const THIEF_VISION_VIGNETTE_SHADER")
	_check(not orb_shader.is_empty(),
		"W5D.1 STEALTH_ORB_SHADER found in hud.gd",
		"W5D.1 STEALTH_ORB_SHADER block missing")

	var circular: bool = orb_shader.find("float d = length(p);") >= 0 \
		and orb_shader.find("abs(p.x) + abs(p.y)") < 0
	_check(circular,
		"W5D.2 Light Gem mask is length(p) (glazed sphere, not a diamond)",
		"W5D.2 Light Gem mask is not circular")
	var sphere_kept: bool = orb_shader.find("normalize(vec3(p.x, p.y, z))") >= 0 \
		and orb_shader.find("float z = sqrt(max(0.0, 1.0 - dot(p, p)));") >= 0
	_check(sphere_kept,
		"W5D.3 sphere normals kept (z = sqrt(1 - dot(p,p)))",
		"W5D.3 sphere normals were removed with the mask change")
	var sector_kept: bool = orb_shader.find("sector_angle") >= 0 \
		and orb_shader.find("float wedge") >= 0
	_check(sector_kept,
		"W5D.4 warm light sector kept",
		"W5D.4 sector shading was lost")

	# Real HUD node structure (the HUD script references autoloads, so load it
	# after startup rather than preloading at parse time).
	var hud_scr: GDScript = load(HUD_PATH) as GDScript
	var hud: CanvasLayer = hud_scr.new() as CanvasLayer
	root.add_child(hud)
	await process_frame
	await process_frame

	# Heading mapping: 0 = N, clockwise, wrap-safe, nearest of eight.
	var headings_ok: bool = hud.call("update_compass_heading", 0.0) == "N" \
		and hud.call("update_compass_heading", 90.0) == "E" \
		and hud.call("update_compass_heading", 180.0) == "S" \
		and hud.call("update_compass_heading", 270.0) == "W" \
		and hud.call("update_compass_heading", 359.0) == "N" \
		and hud.call("update_compass_heading", 22.4) == "N" \
		and hud.call("update_compass_heading", 22.6) == "NE" \
		and hud.call("update_compass_heading", -45.0) == "NW"
	_check(headings_ok,
		"W5D.5 heading maps to the nearest cardinal and wraps at 0/360",
		"W5D.5 heading mapping wrong")

	var compass: Label = hud.get("compass_lbl") as Label
	var ribbon_clip: Control = hud.get("ribbon_clip") as Control
	var ribbon_lbl: Label = hud.get("ribbon_lbl") as Label
	var box: Node = hud.find_child("CompassStrip", true, false)
	_check(compass != null and box != null and compass.get_parent() == box,
		"W5D.6 compass_lbl is the centred heading on CompassStrip",
		"W5D.6 compass_lbl/CompassStrip contract broken")

	var ribbon_gone: bool = ribbon_clip != null and not ribbon_clip.visible \
		and ribbon_lbl != null and not ribbon_lbl.visible and ribbon_lbl.text == ""
	_check(ribbon_gone,
		"W5D.7 the full cardinal ribbon is retired (hidden, empty text)",
		"W5D.7 compass ribbon still visible/text: clip=%s lbl=%s text=%s" % [
			ribbon_clip.visible if ribbon_clip != null else false,
			ribbon_lbl.visible if ribbon_lbl != null else false,
			ribbon_lbl.text if ribbon_lbl != null else "<null>"])

	var line: TextureRect = hud.find_child("CompassCenterLine", true, false) as TextureRect
	_check(line != null and line.size.x <= 160.0,
		"W5D.8 authored compass strip is a small centre line (%.0f px)" % [
			line.size.x if line != null else -1.0],
		"W5D.8 compass centre line missing or still full-width")

	var visible_labels: int = 0
	if box != null:
		for child: Node in box.get_children():
			if child is Label and (child as Label).visible:
				visible_labels += 1
	_check(visible_labels == 1,
		"W5D.9 exactly one visible heading label on the strip",
		"W5D.9 %d visible heading labels on CompassStrip" % visible_labels)

	var heading_ne: String = hud.call("update_compass_heading", 42.0)
	var heading_w: String = hud.call("update_compass_heading", -90.0)
	var single_heading: bool = heading_ne == "NE" and heading_w == "W" \
		and compass != null and compass.text == heading_w and compass.text.length() <= 2 \
		and ribbon_lbl != null and ribbon_lbl.text == ""
	_check(single_heading,
		"W5D.10 update_compass_heading writes one short heading (%s then %s)" % [heading_ne, heading_w],
		"W5D.10 heading write wrong: ne=%s w=%s label=%s" % [
			heading_ne, heading_w, compass.text if compass != null else "<null>"])

	# The applied material must be the circular shader, not just the source.
	var orb: ColorRect = hud.find_child("StealthOrbInner", true, false) as ColorRect
	var orb_mat: ShaderMaterial = null
	if orb != null:
		orb_mat = orb.material as ShaderMaterial
	var applied_ok: bool = orb_mat != null and orb_mat.shader != null \
		and orb_mat.shader.code.find("float d = length(p);") >= 0
	_check(applied_ok,
		"W5D.11 StealthOrbInner material uses the circular gem shader",
		"W5D.11 orb material does not carry the length(p) shader")

	hud.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	print("HUD_GEM_COMPASS_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)
