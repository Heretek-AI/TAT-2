extends SceneTree
## P5 Lane UI — headless HUD/UI corrections probe (first slice).
##
## Measures the real widgets and the real authored data; no renderer, no
## screenshots. Every check prints PASS/FAIL and the summary is one line:
##   P5_UI PASS checks=N
##   P5_UI FAIL checks=N fails=M
##
## Covered rows (REFERENCE_BASELINE.md):
##   UI3-05  Light Gem: amount -> lit-cap area, direction -> cap position
##           (KF14/17/24/25). The authored 21-slice T_stealthball_Array payload
##           is absent from the extract, so the sphere is a PORT_APPROX; the
##           authored frame tint and the 21-slice count are pinned.
##   UI3-01  player card identity + compass geometry (KF02/KF14).
##   UI3-02  single loot line, hotbar slots that carry a tool (1/2/4), no ammo
##           counts, no garbled slot 3/4 labels (KF14/KF19).
##   UI1-02  pause modal: blurred + dimmed world, live HUD hidden, footer clear
##           of the keybind legend (KF30).
##   UI4-04  11-line authored briefing with no overflow (KF13).
##   UI4-03  one READY/BACK prompt pair on prep (KF11).
##   UI2-04  centre prompt reads `CRANK [LMB]` (KF17/KF29).
##   UI3-06  contract list shows authored map names, never internal ids.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 600 tools/godot --headless --path game --script res://tests/probe_p5_ui.gd"

const HUD_PATH: String = "res://src/ui/hud.gd"
const PREP_PATH: String = "res://src/ui/mission_prep_ui.gd"
const TABLE_PATH: String = "res://src/ui/contract_table_ui.gd"

const OUT_MISSION: String = "Mission.Guildhall.LootTheRoom"
const KF13_LINES: Array[String] = [
	"Esteemed Colleague -",
	"The Constables' Guildhall is a",
	"repository of countless treasures seized",
	"over the years. Steal anything you come",
	"across and put them to better use than",
	"gathering dust in a collection case.",
	"There is only a 55 minute window for the",
	"job. Once you collect enough, a magic",
	"door will be summoned for 20 minutes",
	"before collapsing.",
	"We'll be in touch.",
]
const PREP_BACK_TEXT: String = "BACK"
const PREP_READY_TEXT: String = "READY"

var fails: int = 0
var checks: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _finish() -> void:
	if fails == 0:
		print("P5_UI PASS checks=", checks)
	else:
		print("P5_UI FAIL checks=", checks, " fails=", fails)
	quit(0 if fails == 0 else 1)


func _visible_texts(node: Node, needle: String) -> Array[Control]:
	var out: Array[Control] = []
	for c: Node in node.find_children("*", "Label", true, false):
		var lbl: Label = c as Label
		if lbl.visible and lbl.is_visible_in_tree() and lbl.text.find(needle) >= 0:
			out.append(lbl)
	for c: Node in node.find_children("*", "Button", true, false):
		var btn: Button = c as Button
		if btn.visible and btn.is_visible_in_tree() and btn.text.find(needle) >= 0:
			out.append(btn)
	return out


func _initialize() -> void:
	await process_frame
	var hud_scr: GDScript = load(HUD_PATH) as GDScript
	var hud: CanvasLayer = hud_scr.new() as CanvasLayer
	root.add_child(hud)
	await _wait(3)

	var hud_src: String = FileAccess.get_file_as_string(HUD_PATH)

	# =====================================================================
	# 1. Light Gem (UI3-05): amount -> lit-cap area, direction -> position
	# =====================================================================
	var shader_src: String = str(hud_scr.get_script_constant_map().get("STEALTH_ORB_SHADER", ""))
	_check(shader_src.find("lit_amount") >= 0 and shader_src.find("sector_dir") >= 0
			and shader_src.find("sector_z") >= 0 and shader_src.find("float thr = 1.0 - 2.0 * amount") >= 0,
		"P5.1 gem shader sizes the lit cap from amount and places it from the light direction",
		"P5.1 gem shader lacks amount/direction terms")
	_check(shader_src.find("float d = length(p);") >= 0 and shader_src.find("normalize(vec3(p.x, p.y, z))") >= 0,
		"P5.2 gem keeps the circular glazed-sphere mask/normals (W5D contract)",
		"P5.2 gem mask/normals regressed")
	var src_lerp_gone: bool = hud_src.find("Color(0.96, 0.90, 0.62") < 0
	_check(src_lerp_gone,
		"P5.3 the frame no longer lerps to a warm colour with exposure",
		"P5.3 the old frame warm-lerp is still in hud.gd")

	var cam: Camera3D = Camera3D.new()
	cam.rotation = Vector3.ZERO
	root.add_child(cam)
	await process_frame
	var right: Vector3 = hud.call("light_gem_view_dir", Vector3(1, 0, 0), cam) as Vector3
	var up: Vector3 = hud.call("light_gem_view_dir", Vector3(0, 1, 0), cam) as Vector3
	var behind: Vector3 = hud.call("light_gem_view_dir", Vector3(0, 0, 1), cam) as Vector3
	_check(absf(right.x - 1.0) < 0.001 and absf(right.y) < 0.001 and absf(right.z) < 0.001,
		"P5.4 a light to the right maps to canvas +X (angle 0)",
		"P5.4 right-light mapping wrong: %s" % str(right))
	_check(absf(up.y + 1.0) < 0.001,
		"P5.5 a light above maps to canvas -Y (angle -90 deg)",
		"P5.5 up-light mapping wrong: %s" % str(up))
	_check(behind.z > 0.99,
		"P5.6 a light on the viewer's side maps to +Z (front-lit cap)",
		"P5.6 viewer-side light z=%.3f" % behind.z)

	hud.call("apply_light_gem_state", 0.0, Vector3(1, 0, 0), 0.8)
	await process_frame
	var s0: Dictionary = hud.call("light_gem_state") as Dictionary
	hud.call("apply_light_gem_state", 0.5, Vector3(1, 0, 0), 0.8)
	await process_frame
	var s5: Dictionary = hud.call("light_gem_state") as Dictionary
	hud.call("apply_light_gem_state", 1.0, Vector3(0, -1, 0), 0.8)
	await process_frame
	var s1: Dictionary = hud.call("light_gem_state") as Dictionary
	var frac0: float = float(s0.get("lit_area_fraction", -1.0))
	var frac5: float = float(s5.get("lit_area_fraction", -1.0))
	var frac1: float = float(s1.get("lit_area_fraction", -1.0))
	_check(absf(frac0) < 0.001 and absf(frac5 - 0.5) < 0.001 and absf(frac1 - 1.0) < 0.001,
		"P5.7 lit area is 0 / 0.5 / 1.0 for amount 0 / 0.5 / 1.0 (KF17/KF16/KF24)",
		"P5.7 lit fractions = %.3f / %.3f / %.3f" % [frac0, frac5, frac1])
	_check(frac0 < frac5 and frac5 < frac1,
		"P5.8 lit area is monotonic in the light amount",
		"P5.8 lit area not monotonic")
	_check(absf(float(s1.get("sector_angle_deg", 0.0)) + 90.0) < 0.5,
		"P5.9 sector angle follows the applied direction (-90 deg up)",
		"P5.9 sector angle = %.2f" % float(s1.get("sector_angle_deg", 0.0)))
	var orb: ColorRect = hud.find_child("StealthOrbInner", true, false) as ColorRect
	var orb_mat: ShaderMaterial = orb.material as ShaderMaterial if orb != null else null
	var param_amount: float = float(orb_mat.get_shader_parameter("lit_amount")) if orb_mat != null else -1.0
	var param_dir: Variant = orb_mat.get_shader_parameter("sector_dir") if orb_mat != null else null
	var param_angle: float = float(orb_mat.get_shader_parameter("sector_angle")) if orb_mat != null else 0.0
	var applied_ok: bool = orb_mat != null and absf(param_amount - 1.0) < 0.001 \
		and param_dir is Vector2 and (param_dir as Vector2).distance_to(Vector2(0, -1)) < 0.01 \
		and absf(param_angle + PI * 0.5) < 0.01
	_check(applied_ok,
		"P5.10 the shader material carries the applied amount + direction",
		"P5.10 shader params amount=%.3f dir=%s angle=%.3f" % [param_amount, str(param_dir), param_angle])
	var gem: TextureRect = hud.get("stealth_gem") as TextureRect
	var authored_tint: Color = Color(0.082283, 0.109462, 0.686685, 1.0)
	_check(gem != null and gem.modulate.is_equal_approx(authored_tint),
		"P5.11 gem frame keeps the authored BPUI Image_177 violet tint",
		"P5.11 frame tint = %s" % str(gem.modulate if gem != null else Color.BLACK))
	var authored_slices: int = int(hud_scr.get_script_constant_map().get("GEM_AUTHORED_SLICES", 0))
	_check(authored_slices == 21,
		"P5.11b authored stealth-ball array is recorded as 21 slices",
		"P5.11b GEM_AUTHORED_SLICES = %d (want 21)" % authored_slices)

	# =====================================================================
	# 2. Player card identity + compass geometry (UI3-01 / KF02/KF14)
	# =====================================================================
	var gs: Node = root.get_node_or_null("/root/GameState")
	var save: Node = root.get_node_or_null("/root/SaveSystem")
	var saved_name: String = str(gs.get("player_name"))
	var saved_thief: String = str(gs.get("thief_id"))
	gs.set("player_name", "P5 Handle")
	hud.call("_update_portrait_plate")
	var name_lbl: Label = hud.get("_thief_name_lbl") as Label
	var level_lbl: Label = hud.get("_level_badge_lbl") as Label
	_check(name_lbl != null and name_lbl.text == "P5 Handle",
		"P5.12 player card binds the explicit handle (P5 Handle)",
		"P5.12 card name = %s" % (name_lbl.text if name_lbl != null else "<null>"))
	gs.set("player_name", "")
	gs.set("thief_id", "spider")
	hud.call("_update_portrait_plate")
	_check(name_lbl != null and name_lbl.text == str(gs.call("player_display_name"))
			and name_lbl.text.find("Johnny Cipher") < 0,
		"P5.13 blank handle shows the authored thief title, never the capture persona",
		"P5.13 blank-handle card = %s" % (name_lbl.text if name_lbl != null else "<null>"))
	var saved_lvl: Variant = (save.get("data") as Dictionary).get("level", 1)
	var want_lvl: String = "%d" % int(saved_lvl)
	_check(level_lbl != null and level_lbl.text == want_lvl,
		"P5.14 card level badge reads the save (%s)" % want_lvl,
		"P5.14 level badge = %s (want %s)" % [
			level_lbl.text if level_lbl != null else "<null>", want_lvl])
	var card_re: Rect2 = name_lbl.get_global_rect() if name_lbl != null else Rect2()
	_check(card_re.position.x > 700.0 and card_re.position.y < 140.0,
		"P5.15 player card sits in the top-right band (x=%.0f y=%.0f)" % [card_re.position.x, card_re.position.y],
		"P5.15 player card rect = %s" % str(card_re))

	var line: TextureRect = hud.find_child("CompassCenterLine", true, false) as TextureRect
	var tick: Control = hud.find_child("CompassCenterTick", true, false) as Control
	var heading: Label = hud.get("compass_lbl") as Label
	var line_re: Rect2 = line.get_global_rect() if line != null else Rect2()
	var heading_re: Rect2 = heading.get_global_rect() if heading != null else Rect2()
	var tick_re: Rect2 = tick.get_global_rect() if tick != null else Rect2()
	_check(line != null and line_re.size.x >= 500.0 and line_re.size.y <= 12.0,
		"P5.16 compass rule is a wide thin line (%.0f x %.0f px), not a solid bar" % [
			line_re.size.x, line_re.size.y],
		"P5.16 compass line rect = %s" % str(line_re))
	_check(tick != null and tick_re.size.y >= 8.0 and tick_re.position.y < line_re.position.y + 2.0,
		"P5.17 centre tick rises to the rule",
		"P5.17 tick rect = %s" % str(tick_re))
	_check(heading != null and heading_re.position.y + heading_re.size.y <= line_re.position.y + 2.0,
		"P5.18 heading letter sits above the rule (feet=%.0f line=%.0f)" % [
			heading_re.position.y + heading_re.size.y, line_re.position.y],
		"P5.18 heading/line overlap")
	var head_ne: String = str(hud.call("update_compass_heading", 42.0))
	_check(head_ne == "NE" and heading != null and heading.text == "NE",
		"P5.19 compass heading still maps 42 deg -> NE",
		"P5.19 heading = %s / label=%s" % [head_ne, heading.text if heading != null else "<null>"])
	gs.set("player_name", saved_name)
	gs.set("thief_id", saved_thief)
	hud.call("_update_portrait_plate")

	# =====================================================================
	# 3. Loot line + hotbar slots (UI3-02 / KF14/KF19)
	# =====================================================================
	var saved_free: bool = bool(gs.get("free_play"))
	var saved_loot: int = int(gs.get("loot_value"))
	var saved_goal: int = int(gs.get("loot_goal"))
	var saved_order: int = int(gs.get("active_contract_order"))
	gs.set("free_play", true)
	gs.set("loot_value", 0)
	gs.set("loot_goal", 4000)
	gs.set("active_contract_order", 2)
	hud.call("_update_objectives_and_loot", false)
	hud.call("_update_objectives_and_loot", false)
	await process_frame
	var loot_lbl: Label = hud.get("_loot_lbl") as Label
	var obj_lbl: Label = hud.get("obj_lbl") as Label
	var loot_count: int = 0
	for c: Node in hud.find_children("*", "Label", true, false):
		var l: Label = c as Label
		if l.is_visible_in_tree() and l.text.find("(£)") >= 0:
			loot_count += 1
	_check(loot_count == 1,
		"P5.20 exactly one visible loot line (no overprint)",
		"P5.20 visible loot labels = %d" % loot_count)
	_check(obj_lbl != null and obj_lbl.text.find("Steal 4,000 in loot value[0/4,000]") >= 0
			and obj_lbl.text.find("❧") < 0,
		"P5.21 free-play objective is the KF14 inline form with no sub-line",
		"P5.21 objective = %s" % (obj_lbl.text if obj_lbl != null else "<null>"))
	var loot_re: Rect2 = loot_lbl.get_global_rect() if loot_lbl != null else Rect2()
	var obj_re: Rect2 = obj_lbl.get_global_rect() if obj_lbl != null else Rect2()
	_check(loot_lbl != null and obj_lbl != null and loot_re.position.y + loot_re.size.y <= obj_re.position.y + 0.5,
		"P5.22 loot line and objective line do not overlap",
		"P5.22 loot=%s obj=%s" % [str(loot_re), str(obj_re)])

	var kf14_slots: Array[int] = [1, 2, 4]
	var visible_slots: Array[int] = []
	var visible_keys: Array[String] = []
	var count_visible: int = 0
	for i: int in range(4):
		var slot: Control = (hud.get("_slot_containers") as Array)[i] as Control if (hud.get("_slot_containers") as Array).size() > i else null
		if slot != null and slot.visible:
			visible_slots.append(i + 1)
			var key_lbl: Label = (hud.get("_slot_key_lbls") as Array)[i] as Label
			if key_lbl != null and key_lbl.get_parent().visible:
				visible_keys.append(key_lbl.text)
		var cnt: Label = (hud.get("slot_count_lbls") as Array)[i] as Label
		if cnt != null and cnt.is_visible_in_tree():
			count_visible += 1
	_check(visible_slots == kf14_slots,
		"P5.23 hotbar draws only the authored tool slots 1/2/4 (empty slot 3 omitted)",
		"P5.23 visible slots = %s" % str(visible_slots))
	_check(visible_keys == ["1", "2", "4"],
		"P5.24 visible keycaps are 1/2/4 (slot 4 is not renumbered)",
		"P5.24 visible keycaps = %s" % str(visible_keys))
	_check(count_visible == 0,
		"P5.25 no ammo/count text is drawn on the hotbar",
		"P5.25 visible count labels = %d" % count_visible)
	var inf_lbl: Label = (hud.get("slot_count_lbls") as Array)[3] as Label if (hud.get("slot_count_lbls") as Array).size() > 3 else null
	_check((hud.get("slot_count_lbls") as Array).size() == 4 and inf_lbl != null and inf_lbl.text == "∞",
		"P5.26 preserved 4-label contract keeps the slot-4 infinity text",
		"P5.26 slot labels=%d slot4=%s" % [
			(hud.get("slot_count_lbls") as Array).size(), inf_lbl.text if inf_lbl != null else "<null>"])

	# =====================================================================
	# 4. Pause modal (UI1-02 / KF30)
	# =====================================================================
	var footer: Label = null
	for c: Node in hud.find_children("*", "Label", true, false):
		var l: Label = c as Label
		if l.text.find("1.5.148559") >= 0:
			footer = l
			break
	var blur: ColorRect = hud.find_child("PauseBlurBackdrop", true, false) as ColorRect
	var dim: ColorRect = hud.find_child("PauseDim", true, false) as ColorRect
	var blur_mat: ShaderMaterial = blur.material as ShaderMaterial if blur != null else null
	var blur_ok: bool = blur_mat != null and blur_mat.shader != null \
		and blur_mat.shader.code.find("hint_screen_texture") >= 0 \
		and float(blur_mat.get_shader_parameter("blur_px")) >= 4.0
	_check(blur_ok,
		"P5.27 pause backdrop blurs the world (screen-texture 13-tap, blur_px>=4)",
		"P5.27 pause blur backdrop missing/wrong")
	_check(dim != null and dim.color.a >= 0.80,
		"P5.28 pause backdrop also dims the world (alpha %.2f)" % (dim.color.a if dim != null else -1.0),
		"P5.28 pause dim alpha = %s" % str(dim.color.a if dim != null else -1.0))
	_check(footer != null and footer.visible,
		"P5.29 build/difficulty/seed footer is built",
		"P5.29 pause footer missing")
	hud.call("_set_paused", true)
	await _wait(2)
	var hotbar_hint: Control = hud.find_child("MapPingHintBar", true, false) as Control
	var hud_hidden: bool = obj_lbl != null and not obj_lbl.is_visible_in_tree() \
		and hotbar_hint != null and not hotbar_hint.is_visible_in_tree()
	_check(hud_hidden,
		"P5.30 pause hides the live HUD behind the modal",
		"P5.30 HUD still visible: obj=%s hint=%s" % [
			str(obj_lbl.is_visible_in_tree()) if obj_lbl != null else "n/a",
			str(hotbar_hint.is_visible_in_tree()) if hotbar_hint != null else "n/a"])
	var pause_panel: PanelContainer = hud.get("pause_panel") as PanelContainer
	var footer_re: Rect2 = footer.get_global_rect() if footer != null else Rect2()
	var panel_re: Rect2 = pause_panel.get_global_rect() if pause_panel != null else Rect2()
	var vp: Vector2 = root.get_viewport().get_visible_rect().size
	var footer_clear: bool = footer != null and footer_re.position.x < 220.0 \
		and footer_re.position.y > vp.y * 0.85 \
		and not footer_re.intersects(panel_re)
	_check(footer_clear,
		"P5.31 footer is bottom-left and clear of the modal (x=%.0f y=%.0f)" % [
			footer_re.position.x, footer_re.position.y],
		"P5.31 footer rect=%s panel=%s vp=%s" % [str(footer_re), str(panel_re), str(vp)])
	hud.call("_set_paused", false)
	await _wait(2)
	_check(obj_lbl != null and obj_lbl.is_visible_in_tree(),
		"P5.32 resume restores the live HUD",
		"P5.32 HUD not restored after resume")

	# =====================================================================
	# 5. Briefing (UI4-04 / KF13)
	# =====================================================================
	var gd: Node = root.get_node_or_null("/root/GameData")
	var brief_text: String = str(gd.call("get_mission_briefing_text", OUT_MISSION)) if gd != null else ""
	var ref_flat: String = _flat_space(" ".join(KF13_LINES))
	var brief_flat: String = _flat_space(brief_text)
	_check(brief_flat == ref_flat,
		"P5.33 authored ST_Missions letter is the KF13 copy (3 paragraphs, 11 rendered lines)",
		"P5.33 authored letter differs from KF13: '%s'" % brief_flat.substr(0, 120))
	hud.call("show_mission_letter", "", brief_text)
	await _wait(2)
	var body: Label = hud.get("_letter_body_lbl") as Label
	var layout: PackedStringArray = hud.call("format_briefing_layout", brief_text) as PackedStringArray
	var layout_ok: bool = layout.size() == KF13_LINES.size()
	if layout_ok:
		for i: int in range(KF13_LINES.size()):
			if layout[i] != KF13_LINES[i]:
				layout_ok = false
				break
	_check(layout_ok,
		"P5.34 HUD wraps the letter into the authored 11-line KF13 layout",
		"P5.34 HUD layout=%d lines: %s" % [layout.size(), str(layout)])
	var no_brace: bool = body != null and body.text.find("{") < 0 and body.text.count("\n") == 10
	_check(no_brace,
		"P5.35 HUD body renders 11 lines with both placeholders substituted",
		"P5.35 body lines=%d text='%s'" % [
			body.text.count("\n") + 1 if body != null else -1,
			body.text.substr(0, 60) if body != null else "<null>"])
	var overflow_ok: bool = false
	var shaped_h: float = -1.0
	var body_font: Font = body.get_theme_font("font") if body != null else null
	var body_fs: int = body.get_theme_font_size("font_size") if body != null else 0
	if body != null and body_font != null:
		var ts: TextServer = TextServerManager.get_primary_interface()
		shaped_h = 0.0
		var width_ok: bool = true
		for kf_line2: String in KF13_LINES:
			var lrid2: RID = ts.create_shaped_text()
			ts.shaped_text_add_string(lrid2, kf_line2, body_font.get_rids(), body_fs)
			var lsz: Vector2 = ts.shaped_text_get_size(lrid2)
			shaped_h += lsz.y
			if lsz.x > 413.0:
				width_ok = false
			ts.free_rid(lrid2)
		overflow_ok = width_ok and shaped_h <= body.size.y + 1.0
	_check(overflow_ok,
		"P5.36 11 lines fit the parchment text box (shaped %.1f <= %.1f px)" % [
			shaped_h, body.size.y if body != null else -1.0],
		"P5.36 text overflow: shaped=%.1f box=%.1f" % [shaped_h, body.size.y if body != null else -1.0])
	var title_lbl: Label = hud.get("_letter_title_lbl") as Label
	var scroll: Panel = hud.find_child("MissionLetterScrollbar", true, false) as Panel
	_check(title_lbl != null and not title_lbl.visible and scroll != null and scroll.visible,
		"P5.37 own-salutation letter hides the title and keeps the right scrollbar",
		"P5.37 title_visible=%s scroll=%s" % [
			str(title_lbl.visible) if title_lbl != null else "n/a",
			str(scroll != null and scroll.visible)])
	hud.call("_close_mission_letter")
	await _wait(2)
	_check(obj_lbl != null and obj_lbl.is_visible_in_tree(),
		"P5.38 closing the letter restores the HUD",
		"P5.38 HUD not restored after the letter")

	# =====================================================================
	# 6. Prep duplicate READY/BACK + mission-id leak (UI4-03 / KF11)
	# =====================================================================
	# The prep screen otherwise builds the 2,107-mesh MissionLobby stage; the
	# same QA hook the W9-P3 focus-walk test uses skips only that SubViewport.
	var had_no_stage: bool = OS.has_environment("TAT2_UI_NO_STAGE")
	var prev_no_stage: String = OS.get_environment("TAT2_UI_NO_STAGE")
	OS.set_environment("TAT2_UI_NO_STAGE", "1")
	var prep_scr: GDScript = load(PREP_PATH) as GDScript
	var prep: Control = prep_scr.new() as Control
	prep.size = Vector2(1280, 720)
	root.add_child(prep)
	await _wait(3)
	prep.call("open_prep", "guildhall", 1, "Solo", 0, true)
	await _wait(4)
	var back_nodes: Array[Control] = _visible_texts(prep, PREP_BACK_TEXT)
	var ready_nodes: Array[Control] = _visible_texts(prep, PREP_READY_TEXT)
	var action_ready: int = 0
	for c: Control in ready_nodes:
		var txt: String = str(c.get("text"))
		if txt.find("[") >= 0:
			action_ready += 1
	var controls: Label = prep.get("_controls_lbl") as Label
	var ready_btn: Button = prep.get("_ready_btn") as Button
	_check(back_nodes.size() == 1 and action_ready == 1 and ready_nodes.size() == 2,
		"P5.39 prep shows one BACK prompt and one action READY prompt (state label + action)",
		"P5.39 BACK=%d action_ready=%d READY=%d" % [back_nodes.size(), action_ready, ready_nodes.size()])
	_check(controls != null and not controls.is_visible_in_tree() and ready_btn != null and ready_btn.visible,
		"P5.40 the duplicate hint line is not drawn; the single action button is",
		"P5.40 controls_visible=%s ready_btn=%s" % [
			str(controls.is_visible_in_tree()) if controls != null else "n/a",
			str(ready_btn != null and ready_btn.visible)])
	var selector: OptionButton = prep.get("_mission_selector") as OptionButton
	var selector_clean: bool = selector != null and selector.item_count > 0
	if selector != null:
		for i: int in range(selector.item_count):
			var item: String = selector.get_item_text(i)
			if item.find("Mission.") >= 0 or item.find("(") >= 0 or item.find("_") >= 0:
				selector_clean = false
	_check(selector_clean,
		"P5.41 prep mission selector names the authored heist, never the mission id",
		"P5.41 selector items leak ids: %s" % str(_selector_items(selector)))
	prep.queue_free()
	if had_no_stage:
		OS.set_environment("TAT2_UI_NO_STAGE", prev_no_stage)
	else:
		OS.unset_environment("TAT2_UI_NO_STAGE")
	await _wait(2)

	# =====================================================================
	# 7. CRANK [LMB] centre prompt (UI2-04 / KF17/KF29)
	# =====================================================================
	var crank_lbl: Label = hud.get("_crank_prompt_lbl") as Label
	_check(crank_lbl != null and crank_lbl.text == "CRANK [LMB]",
		"P5.42 centre crank prompt reads CRANK [LMB] (label then keycap)",
		"P5.42 crank prompt = '%s'" % (crank_lbl.text if crank_lbl != null else "<null>"))

	# =====================================================================
	# 8. Map table legend has no internal ids (UI3-06 / KF10)
	# =====================================================================
	var table_scr: GDScript = load(TABLE_PATH) as GDScript
	var table: CanvasLayer = table_scr.new() as CanvasLayer
	root.add_child(table)
	await _wait(3)
	var list: ItemList = table.get("_list") as ItemList
	var list_clean: bool = list != null and list.item_count > 0
	var has_authored_map: bool = false
	if list != null:
		for i: int in range(list.item_count):
			var item: String = list.get_item_text(i)
			if item.find("(THIEVES_DEN)") >= 0 or item.find("(OLD_MANOR)") >= 0 \
					or item.find("(GUILDHALL)") >= 0 or item.find("Mission.") >= 0:
				list_clean = false
			if item.find("CONSTABLES' GUILDHALL") >= 0 or item.find("THIEVES' DEN") >= 0:
				has_authored_map = true
	_check(list_clean and has_authored_map,
		"P5.43 contract list shows authored map names, not internal ids",
		"P5.43 contract list leak: %s" % str(_item_list_items(list)))
	table.queue_free()
	await _wait(2)

	gs.set("free_play", saved_free)
	gs.set("loot_value", saved_loot)
	gs.set("loot_goal", saved_goal)
	gs.set("active_contract_order", saved_order)
	hud.queue_free()
	await _wait(2)
	_finish()


func _flat_space(text: String) -> String:
	var out: String = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
	while out.find("  ") >= 0:
		out = out.replace("  ", " ")
	return out.strip_edges()


func _selector_items(sel: OptionButton) -> Array[String]:
	var out: Array[String] = []
	if sel == null:
		return out
	for i: int in range(sel.item_count):
		out.append(sel.get_item_text(i))
	return out


func _item_list_items(list: ItemList) -> Array[String]:
	var out: Array[String] = []
	if list == null:
		return out
	for i: int in range(list.item_count):
		out.append(list.get_item_text(i))
	return out
