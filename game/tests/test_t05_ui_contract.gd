extends SceneTree
## T05-UI contract tests (headless, numeric — no Vulkan, no captures).
##
## P0 prep stage:
##   * the live MissionLobby camera equals the authored CameraActor_0
##     (position / forward / pitch / yaw / roll / FOV 20 horizontal),
##   * the authored 10 deg cone really contains the authored backdrop
##     (>= 380 of 2,107 mesh pivots; the pre-fix reframe saw 13),
##   * every expansion skyline piece's projected AABB is inside the tracked
##     composition band, and the subject stays in KF11's 0.70-0.84 chest band.
## P1 HUD:
##   * the health bar uses the authored shaped fill (never loaded before),
##   * the splatter is a damage state (< 50 %), not a permanent decoration,
##   * frame and fill share the authored 4:1 rect,
##   * one HudScript / one hp frame / one objective label / one hint row.
## P1 pause:
##   * the world dim is >= 0.80 near-black, the live HUD is hidden,
##   * "RETURN TO THIEF'S DEN" targets the Den (mission scene, contract 1),
##   * leaving a live run banks a payout exactly once (capture keeps stashed).
##
## Run:  tools/godot --headless --path game --script res://tests/test_t05_ui_contract.gd

const LOBBY_LEVELS: Array[String] = [
	"res://data/generated/levels/MissionLobby/MissionLobby_Geo3.tatlevel.json",
	"res://data/generated/levels/MissionLobby/MissionLobby_Periphery.tatlevel.json",
]

const UIStringsScript: GDScript = preload("res://src/ui/ui_strings.gd")

var fails: int = 0
var checks: int = 0


class DummyBody extends Node3D:
	var max_health: float = 100.0
	var health: float = 100.0
	var max_stamina: float = 100.0
	var stamina: float = 100.0


func _init() -> void:
	call_deferred("_run")


func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _check(ok: bool, what: String, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS: ", what)
	else:
		fails += 1
		printerr("FAIL: ", what, (" | " + detail) if detail != "" else "")


func _frac(cam: Camera3D, p: Vector3) -> Vector2:
	var vp: Vector2 = Vector2(cam.get_viewport().size)
	if vp.x <= 0.0 or vp.y <= 0.0:
		return Vector2(-1, -1)
	return cam.unproject_position(p) / vp


func _project_box(cam: Camera3D, box: AABB) -> Array:
	var mn: Vector2 = Vector2(9, 9)
	var mx: Vector2 = Vector2(-9, -9)
	var front: int = 0
	for i: int in 8:
		var world: Vector3 = box.get_endpoint(i)
		if (-cam.global_transform.basis.z).dot(world - cam.global_position) <= 0.01:
			continue
		front += 1
		var s: Vector2 = _frac(cam, world)
		mn = Vector2(minf(mn.x, s.x), minf(mn.y, s.y))
		mx = Vector2(maxf(mx.x, s.x), maxf(mx.y, s.y))
	return [mn, mx, front]


# --- P0: authored prep camera ------------------------------------------------

func _prep_checks() -> void:
	var prep_script: GDScript = load("res://src/ui/mission_prep_ui.gd") as GDScript
	_check(prep_script != null, "T05.P1 mission_prep_ui.gd loads")
	if prep_script == null:
		return
	# Authored CameraActor_0 (MissionLobby_Geo3 -> CameraActor_0).
	var want_pos: Vector3 = Vector3(12.6065, -0.16698, -1.05384)
	var want_fwd: Vector3 = Vector3(-0.986184, 0.116419, 0.117848)
	var want_roll: float = -14.780165
	var cam_pos: Vector3 = prep_script.LOBBY_CAM_POS as Vector3
	var cam_fwd: Vector3 = prep_script.LOBBY_CAM_FWD as Vector3
	_check(cam_pos.is_equal_approx(want_pos), "T05.P2 LOBBY_CAM_POS equals the authored CameraActor_0",
		"got %s want %s" % [str(cam_pos), str(want_pos)])
	_check(cam_fwd.normalized().is_equal_approx(want_fwd.normalized()), "T05.P3 LOBBY_CAM_FWD equals the authored forward (pitch 6.685 / yaw 173.186)",
		"got %s want %s" % [str(cam_fwd), str(want_fwd)])
	_check(absf(float(prep_script.LOBBY_CAM_FOV) - 20.0) < 0.001, "T05.P4 authored FOV is 20.0 horizontal (KEEP_WIDTH)")
	_check(absf(float(prep_script.LOBBY_CAM_ROLL_DEG) - want_roll) < 0.001, "T05.P5 authored roll is -14.780165")
	var thief_pos: Vector3 = prep_script.LOBBY_THIEF_POS as Vector3
	_check(absf(thief_pos.x - -1.5871) < 0.001 and absf(thief_pos.z - -0.7868) < 0.001,
		"T05.P6 the thief stands on the authored BP_MatchLobbyDummyPlayer_C_1 slot",
		"got %s" % str(thief_pos))

	# Live stage: build the real prep screen and inspect the spawned camera.
	var mp: Control = prep_script.new() as Control
	mp.size = Vector2(1280, 720)
	root.add_child(mp)
	await _wait(4)
	mp.call("open_prep", "guildhall", 1, "Solo", 0, false)
	var cam: Camera3D = null
	for _i: int in range(1500):
		cam = mp.find_child("MissionLobbyCamera", true, false) as Camera3D
		if cam != null:
			break
		await process_frame
	await _wait(30)
	_check(cam != null, "T05.P7 the prep stage builds its camera")
	if cam == null:
		mp.queue_free()
		return
	_check(cam.global_position.is_equal_approx(want_pos), "T05.P8 live camera position is authored",
		"got %s" % str(cam.global_position))
	_check(absf(cam.fov - 20.0) < 0.01 and cam.keep_aspect == Camera3D.KEEP_WIDTH,
		"T05.P9 live camera keeps FOV 20 / KEEP_WIDTH", "fov=%.3f keep=%d" % [cam.fov, cam.keep_aspect])
	# Expected authored basis: look_at(fwd) then roll about local +Z.
	var probe: Node3D = Node3D.new()
	root.add_child(probe)
	probe.global_position = want_pos
	probe.look_at(want_pos + want_fwd.normalized(), Vector3.UP)
	probe.rotate_object_local(Vector3.FORWARD, deg_to_rad(want_roll))
	var want_basis: Basis = probe.global_transform.basis
	probe.queue_free()
	var basis_ok: bool = cam.global_transform.basis.x.is_equal_approx(want_basis.x) \
		and cam.global_transform.basis.y.is_equal_approx(want_basis.y) \
		and cam.global_transform.basis.z.is_equal_approx(want_basis.z)
	_check(basis_ok, "T05.P10 live camera basis equals authored pitch/yaw/roll",
		"x=%s want %s" % [str(cam.global_transform.basis.x), str(want_basis.x)])

	# Authored backdrop: cone count over the generated lobby mesh pivots.
	var fwd: Vector3 = -cam.global_transform.basis.z
	var total: int = 0
	var inside: int = 0
	for path: String in LOBBY_LEVELS:
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if not (parsed is Dictionary):
			continue
		for m_v: Variant in ((parsed as Dictionary).get("meshes", []) as Array):
			if not (m_v is Dictionary):
				continue
			var pos_v: Variant = (m_v as Dictionary).get("pos", [])
			if not (pos_v is Array) or (pos_v as Array).size() < 3:
				continue
			total += 1
			var p: Vector3 = Vector3(float(pos_v[0]), float(pos_v[1]), float(pos_v[2]))
			var v: Vector3 = p - cam.global_position
			if v.length() < 0.5:
				continue
			if rad_to_deg(fwd.angle_to(v)) < 10.0:
				inside += 1
	_check(total >= 2100, "T05.P11 both lobby sublevels are loaded in the generated set (%d meshes)" % total)
	_check(inside >= 380, "T05.P12 the authored 10 deg cone contains the authored city (>= 380 of %d)" % total,
		"inside=%d (the pre-fix reframe saw 13)" % inside)

	# Expansion skyline composition band (real spawned meshes, authored camera).
	# W9-P1 re-derived the band from KF11: the city is the MID-GROUND roofline
	# (official silhouette tops p50 sy 0.372), so each piece's projected top has
	# to land in [0.28, 0.46]. The old band [0.65, 0.98] was the pre-T05 310-500 m
	# standoff at base_y 0, which projects to 0.746-0.954 — KF11's NEAR-roof band
	# — and at the authored camera that placement rendered zero visible pixels
	# (prep vs prep_nosky identical: build/qa/w9/p0-report.md §A1). Measured after
	# the re-author: 0.300 / 0.330 / 0.340 / 0.360 / 0.380 / 0.400 / 0.420 / 0.440.
	var max_w: float = float(prep_script.PREP_SKYLINE_MAX_WIDTH_FRAC)
	var top_min: float = float(prep_script.PREP_SKYLINE_TOP_MIN)
	var top_max: float = float(prep_script.PREP_SKYLINE_TOP_MAX)
	var sky_nodes: Array[Node] = mp.find_children("PrepSkyline_*", "MeshInstance3D", true, false)
	_check(sky_nodes.size() == 8, "T05.P13 every tracked expansion skyline piece spawns (%d/8)" % sky_nodes.size())
	var bad: Array[String] = []
	for n: Node in sky_nodes:
		var mi: MeshInstance3D = n as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		var proj: Array = _project_box(cam, box)
		var mn: Vector2 = proj[0] as Vector2
		var mx: Vector2 = proj[1] as Vector2
		var w: float = mx.x - mn.x
		var overlap: float = minf(mx.x, 1.0) - maxf(mn.x, 0.0)
		var ok: bool = w <= max_w + 0.001 and mn.y >= top_min - 0.001 and mn.y <= top_max + 0.001 and overlap > 0.0
		# Always print the measured band: the numbers, not just the verdict, are
		# the evidence a report cites (KF11 city tops p50 sy 0.372).
		print("T05.P14 %s x=%.3f..%.3f top=%.3f bottom=%.3f w=%.3f overlap=%.3f ok=%s" % [
			mi.name, mn.x, mx.x, mn.y, mx.y, w, overlap, str(ok)])
		if not ok:
			bad.append("%s w=%.2f top=%.3f overlap=%.2f" % [mi.name, w, mn.y, overlap])
	_check(bad.is_empty(), "T05.P14 every skyline piece is inside the tracked band (w <= %.2f, top in [%.2f, %.2f])" % [max_w, top_min, top_max],
		"%s" % str(bad))

	# Authored 9-slice frame on the prep cards (never zero margins: the
	# "corrupted ribbon" mechanism is stretching the painterly frame unscaled).
	var frames: Array[Node] = mp.find_children("AuthoredFrame", "NinePatchRect", true, false)
	_check(frames.size() == 3, "T05.P14b the three prep cards carry the authored 9-slice frame (%d)" % frames.size())
	if not frames.is_empty():
		var np: NinePatchRect = frames[0] as NinePatchRect
		var tex_path: String = np.texture.resource_path if np.texture != null else ""
		_check(tex_path.find("T_boxFrame_ornate_2.png") >= 0, "T05.P14c prep card frame is T_boxFrame_ornate_2", tex_path)
		_check(np.patch_margin_left > 0 and np.patch_margin_top > 0 and np.patch_margin_right > 0 and np.patch_margin_bottom > 0,
			"T05.P14d authored frame margins are non-zero (%d/%d/%d/%d)" % [np.patch_margin_left, np.patch_margin_top, np.patch_margin_right, np.patch_margin_bottom])

	# Subject framing from the authored camera (KF11 0.70-0.84 chest band).
	var anchor: Node3D = mp.find_child("MissionLobbyThiefAnchor", true, false) as Node3D
	_check(anchor != null, "T05.P15 prep thief anchor exists")
	if anchor != null:
		var chest: Vector2 = _frac(cam, anchor.global_position + Vector3(0.0, 0.9, 0.0))
		var feet: Vector2 = _frac(cam, anchor.global_position)
		_check(chest.x >= 0.70 and chest.x <= 0.84, "T05.P16 thief chest x stays in KF11's 0.70-0.84 (%.3f)" % chest.x,
			"chest=(%.3f,%.3f) feet=(%.3f,%.3f)" % [chest.x, chest.y, feet.x, feet.y])
		_check(feet.y >= 0.70 and feet.y <= 0.98, "T05.P17 thief soles sit in the lower band (%.3f)" % feet.y)

	# LOCATION thumbnail keeps the authored splash aspect (no 3.54:1 row crop).
	var art: TextureRect = mp.find_child("LocationArt", true, false) as TextureRect
	_check(art != null, "T05.P18 LOCATION art exists")
	if art != null:
		var aspect: float = art.size.x / maxf(art.size.y, 1.0)
		_check(aspect >= 1.70 and aspect <= 1.90, "T05.P19 LOCATION art is 16:9 (%.3f:1), not a 3.54:1 crop" % aspect,
			"size=%s" % str(art.size))
	var left: VBoxContainer = null
	for n2: Node in mp.get_children():
		if n2 is VBoxContainer and (n2 as VBoxContainer).position.x < 100.0:
			left = n2 as VBoxContainer
	_check(left != null and left.get_global_rect().end.y <= 710.0,
		"T05.P20 the three prep cards fit the 720p canvas (bottom %.1f)" % (left.get_global_rect().end.y if left != null else -1.0))

	# KF11 readiness: nameplate stays READY while the button/hint say UNREADY.
	var readiness: Label = mp.get("_readiness_lbl") as Label
	var ready_btn: Button = mp.get("_ready_btn") as Button
	var controls: Label = mp.get("_controls_lbl") as Label
	mp.call("_on_ready_action")
	_check(readiness != null and readiness.text == "READY" \
		and ready_btn != null and ready_btn.text.find("UNREADY") >= 0 \
		and controls != null and controls.text.find("UNREADY") >= 0,
		"T05.P21 counting state keeps the READY nameplate, flips button + hint",
		"label=%s btn=%s hint=%s" % [readiness.text if readiness != null else "?", ready_btn.text if ready_btn != null else "?", controls.text if controls != null else "?"])
	mp.call("_on_ready_action")

	# T05 l10n: prep labels now carry the authored StringTable rows.
	_check(UIStringsScript.row_count("ST_Screens") == 109 and UIStringsScript.row_count("ST_HUD") == 15,
		"T05.P22 the UI string-table reader sees ST_Screens (109) and ST_HUD (15)",
		"screens=%d hud=%d postmatch=%d" % [UIStringsScript.row_count("ST_Screens"), UIStringsScript.row_count("ST_HUD"), UIStringsScript.row_count("ST_PostMatch")])
	var countdown: Label = mp.get("_countdown_lbl") as Label
	var mode_lbl: Label = mp.get("_mode_sub_lbl") as Label
	var diff_lbl: Label = mp.get("_diff_sub_lbl") as Label
	_check(countdown != null and countdown.text == UIStringsScript.raw("ST_Screens", "Screen.MissionLobby.Countdown", "").replace("<Num>", "").replace("</>", "").replace("{number}", "6").to_upper(),
		"T05.P23 countdown renders the authored Screen.MissionLobby.Countdown row (%s)" % (countdown.text if countdown != null else "?"))
	_check(mode_lbl != null and mode_lbl.text == "Mode: Solo" and diff_lbl != null and diff_lbl.text == "Difficulty: Novice",
		"T05.P24 mode/difficulty render the authored MissionLobby rows",
		"mode=%s diff=%s" % [mode_lbl.text if mode_lbl != null else "?", diff_lbl.text if diff_lbl != null else "?"])

	mp.queue_free()
	await _wait(3)


# --- P1: HUD health bar + C-4 instrumentation --------------------------------

func _hud_checks() -> void:
	var hud_scr: GDScript = load("res://src/ui/hud.gd") as GDScript
	_check(hud_scr != null, "T05.H1 hud.gd loads")
	if hud_scr == null:
		return
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("active_contract_order", 2)
		gs.set("state", "playing")
	var hud: CanvasLayer = hud_scr.new() as CanvasLayer
	root.add_child(hud)
	await _wait(4)

	var counts: Dictionary = hud.call("debug_hud_counts") as Dictionary
	_check(int(counts.get("hp_frames", 0)) == 1, "T05.H2 exactly one hp frame is built (%d)" % int(counts.get("hp_frames", 0)),
		"%s" % str(counts))
	_check(int(counts.get("hp_fills", 0)) == 1, "T05.H3 exactly one hp fill is built (%d)" % int(counts.get("hp_fills", 0)),
		"%s" % str(counts))
	_check(int(counts.get("objectives", 0)) == 1, "T05.H4 exactly one objectives label is built (%d)" % int(counts.get("objectives", 0)),
		"%s" % str(counts))
	_check(int(counts.get("map_ping_hints", 0)) == 1, "T05.H5 exactly one MAP/PING hint row is built (%d)" % int(counts.get("map_ping_hints", 0)),
		"%s" % str(counts))
	var hint_labels: Array[String] = []
	var hint_bar: HBoxContainer = hud.find_child("MapPingHintBar", true, false) as HBoxContainer
	if hint_bar != null:
		for c: Node in hint_bar.get_children():
			if c is Label:
				hint_labels.append((c as Label).text)
	_check(hint_labels.has(UIStringsScript.st_upper("ST_HUD", "MapButtonLabel", "MAP")) \
		and hint_labels.has(UIStringsScript.st_upper("ST_HUD", "PingButtonLabel", "[HOLD] PING MENU")),
		"T05.H5b the hint row renders the authored ST_HUD Map/Ping rows",
		"%s" % str(hint_labels))
	_check(int(counts.get("hp_frame_builds", 0)) == 1, "T05.H6 the hp-frame build path ran once (%d)" % int(counts.get("hp_frame_builds", 0)))

	# RE-L-18/19/20: authored type roles and the 1280x720 scale rule.
	var theme_scr: GDScript = load("res://src/ui/art_nouveau_theme.gd") as GDScript
	_check(theme_scr != null, "T05.H6a art_nouveau_theme loads")
	if theme_scr != null:
		var fonts_ok: bool = theme_scr.call("font_display") != null and theme_scr.call("font_numbers") != null \
			and theme_scr.call("font_handwritten") != null and theme_scr.call("font_map_hand") != null \
			and theme_scr.call("font_session") != null
		_check(fonts_ok, "T05.H6b the five authored-role faces load (Balthazar/FacultyGlyphic/PermanentMarker/Caveat/Abel)")
		_check(int(theme_scr.call("font_size_px", 48.0)) == 32 and int(theme_scr.call("font_size_px", 54.0)) == 36 \
			and int(theme_scr.call("font_size_px", 42.0)) == 28 and int(theme_scr.call("font_size_px", 32.0)) == 21 \
			and int(theme_scr.call("font_size_px", 55.0)) == 37 and int(theme_scr.call("font_size_px", 24.0)) == 16,
			"T05.H6c the authored-px -> design-px scale rule is 2/3 (48->32, 54->36, 42->28, 32->21, 55->37, 24->16)")
	var pause_root: Control = hud.get("_pause_root") as Control
	var pause_frame: NinePatchRect = null
	if pause_root != null:
		pause_frame = pause_root.find_child("AuthoredFrame", true, false) as NinePatchRect
	_check(pause_frame != null and pause_frame.texture != null \
		and pause_frame.texture.resource_path.find("T_PanelFrame_Primary.png") >= 0 \
		and pause_frame.patch_margin_left > 0 and pause_frame.patch_margin_top > 0,
		"T05.H6d the pause panel carries the authored primary 9-slice frame with margins")

	var hp_fill: TextureRect = hud.get("hp_fill") as TextureRect
	_check(hp_fill != null and hp_fill.texture != null \
		and hp_fill.texture.resource_path.find("T_healthBar_straight_RGB.png") >= 0,
		"T05.H7 the authored shaped fill T_healthBar_straight_RGB.png is loaded",
		"tex=%s" % (hp_fill.texture.resource_path if hp_fill != null and hp_fill.texture != null else "none"))
	var frame: TextureRect = hud.find_child("HpFrame", true, false) as TextureRect
	_check(frame != null and absf(frame.size.x / maxf(frame.size.y, 1.0) - 4.0) <= 0.05,
		"T05.H8 frame and fill share the authored 4:1 rect",
		"frame=%s fill=%s" % [str(frame.size) if frame != null else "?", str(hp_fill.size) if hp_fill != null else "?"])

	var body: DummyBody = DummyBody.new()
	body.health = 80.0
	root.add_child(body)
	hud.call("_update_health_and_stamina", body, false)
	var splatter: TextureRect = hud.find_child("HpSplatter", true, false) as TextureRect
	_check(splatter != null and not splatter.visible, "T05.H9 no blood splatter at 80 % health")
	var width_80: float = hp_fill.size.x if hp_fill != null else -1.0
	body.health = 40.0
	hud.call("_update_health_and_stamina", body, false)
	_check(splatter != null and splatter.visible, "T05.H10 splatter appears below half health")
	_check(hp_fill != null and absf(hp_fill.size.x - (width_80 * 0.5)) <= 1.0,
		"T05.H11 the fill width tracks health (%.1f -> %.1f)" % [width_80, hp_fill.size.x if hp_fill != null else -1.0])
	body.queue_free()

	# Pause: authored dim, live HUD hidden, no footer/hint-row overprint.
	hud.call("_set_paused", true)
	var dim: ColorRect = hud.find_child("PauseDim", true, false) as ColorRect
	_check(dim != null and dim.color.a >= 0.80 and dim.color.get_luminance() <= 0.05,
		"T05.H12 pause backdrop carries the authored near-black dim (a=%.2f)" % (dim.color.a if dim != null else -1.0))
	var hint_row: HBoxContainer = hud.find_child("MapPingHintBar", true, false) as HBoxContainer
	var footer: Label = null
	for n: Node in hud.find_children("*", "Label", true, false):
		var lbl: Label = n as Label
		if lbl.text.begins_with("1.5.148559"):
			footer = lbl
			break
	_check(hint_row != null and not hint_row.is_visible_in_tree(),
		"T05.H13 the live hint row is hidden while paused (KF30 shows no HUD)")
	_check(footer != null and footer.is_visible_in_tree(), "T05.H14 the pause footer stays visible")
	hud.call("_set_paused", false)
	_check(hint_row != null and hint_row.is_visible_in_tree(), "T05.H15 resuming restores the live HUD")

	_check(str(hud.call("pause_return_scene_path")) == "res://scenes/mission.tscn",
		"T05.H16 RETURN TO THIEF'S DEN targets the Den (mission scene, contract 1), not the start screen")

	# Post-match rack-up from the authored ST_PostMatch rows (RE-L-09).
	if gs != null:
		gs.set("active_map_id", "guildhall")
		gs.set("active_mission_id", "Mission.Guildhall.LootTheRoom")
		gs.set("active_contract_order", 2)
	hud.call("show_result", true, 500, {})
	await _wait(2)
	var status_lbl: Label = hud.get("result_lbl") as Label
	var panel_text: String = ""
	var ghost_words: int = 0
	for n3: Node in hud.find_children("*", "Label", true, false):
		var l3: Label = n3 as Label
		if l3.is_visible_in_tree():
			panel_text += l3.text + "\n"
			if l3.text.find("GHOST") >= 0 or l3.text.find("BRAWLER") >= 0 or l3.text.find("CONSTABULARY") >= 0:
				ghost_words += 1
	_check(status_lbl != null and status_lbl.text == UIStringsScript.raw("ST_PostMatch", "PostMatch.Status.Escaped", "Escaped").to_upper(),
		"T05.H20 post-match status uses the authored PostMatch.Status.Escaped row (%s)" % (status_lbl.text if status_lbl != null else "?"))
	_check(panel_text.find(UIStringsScript.raw("ST_PostMatch", "PostMatch.Haul", "Ill-Gotten Gains").to_upper()) >= 0 \
		and panel_text.find(UIStringsScript.raw("ST_PostMatch", "PostMatch.Mission.GuildHall.LootTheRoom.Success", "")) >= 0,
		"T05.H21 post-match haul + mission outcome are the authored ST_PostMatch rows")
	_check(ghost_words == 0, "T05.H22 no invented GHOST/SHADOW/BRAWLER/CONSTABULARY rating strings remain", "%d" % ghost_words)
	var continue_btn: Button = hud.get("_result_continue_btn") as Button
	_check(continue_btn != null and continue_btn.text == UIStringsScript.raw("ST_Screens", "Screen.Continue", "Continue").to_upper(),
		"T05.H23 post-match Continue uses the authored Screen.Continue row (%s)" % (continue_btn.text if continue_btn != null else "?"))
	hud.call("show_result", false, 0, {})

	# Payout: abandoning a live run banks exactly once (capture keeps stashed).
	var save: Node = root.get_node_or_null("/root/SaveSystem")
	var backup: Dictionary = {}
	if save != null:
		backup = (save.get("data") as Dictionary).duplicate(true)
	var r1: Dictionary = hud.call("_settle_run_for_exit") as Dictionary
	_check(bool(r1.get("applied", false)), "T05.H17 abandoning a live run applies a payout", "%s" % str(r1))
	var r2: Dictionary = hud.call("_settle_run_for_exit") as Dictionary
	_check(not bool(r2.get("applied", true)), "T05.H18 the abandonment payout is idempotent", "%s" % str(r2))
	_check(gs != null and str(gs.get("phase")) == "resolved", "T05.H19 the abandoned run resolves its phase")

	# Prompt contrast (L3-14): the disabled LAUNCH row must stay legible.
	hud.call("_refresh_action_hints", [{"key": "LMB", "label": "LAUNCH", "enabled": false}])
	var hint_col: Color = Color(0, 0, 0, 0)
	var hint_size: int = 0
	var hints_box: VBoxContainer = hud.get("_action_hints_box") as VBoxContainer
	if hints_box != null and hints_box.get_child_count() > 0:
		var row: HBoxContainer = hints_box.get_child(0) as HBoxContainer
		if row != null and row.get_child_count() > 0:
			var lbl: Label = row.get_child(0) as Label
			if lbl != null:
				hint_col = lbl.get_theme_color("font_color")
				hint_size = lbl.get_theme_font_size("font_size")
	_check(hint_col.a >= 0.75 and hint_col.get_luminance() >= 0.55 and hint_size == 14,
		"T05.H24 disabled LAUNCH keeps contrast (a=%.2f luma=%.2f size=%d)" % [hint_col.a, hint_col.get_luminance(), hint_size])
	if save != null and not backup.is_empty():
		save.set("data", backup)
		if save.has_method("write_save"):
			save.call("write_save")

	hud.queue_free()
	await _wait(3)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _prep_checks()
	await _hud_checks()
	print("T05_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(1 if fails > 0 else 0)
