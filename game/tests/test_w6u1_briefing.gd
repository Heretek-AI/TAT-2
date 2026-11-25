extends SceneTree
## W6U1 focused gate: authored briefing letter + 1200 s endgame override,
## KF13 HUD letter (paper/blur/scrollbar/HUD-hidden/11 lines), prep stage
## key/fill/rim + decoupled moon disc, and the Den poster-wall fill/backlight.
##
## Run:
##   XDG_DATA_HOME=/tmp/opencode/w6u1-data tools/godot --headless --path game \
##     --script res://tests/test_w6u1_briefing.gd

const OUT_MISSION := "Mission.Guildhall.LootTheRoom"
const OVERRIDE_PATH := "res://data/expansion/briefing_overrides.json"
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

var fails: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _initialize() -> void:
	await process_frame
	var gd: Node = root.get_node_or_null("/root/GameData")
	_check(gd != null, "W6U1.1 GameData autoload present", "W6U1.1 GameData autoload missing")
	if gd == null:
		_finish()
		return

	# --- 1. Authored briefing text + tracked 1200 s override -----------------
	var ov: Dictionary = gd.get("briefing_overrides") as Dictionary
	var rec_v: Variant = ov.get(OUT_MISSION)
	var ov_rec: Dictionary = rec_v as Dictionary if rec_v is Dictionary else {}
	_check(not ov_rec.is_empty(),
		"W6U1.2 tracked briefing override exists for %s" % OUT_MISSION,
		"W6U1.2 no briefing override for %s" % OUT_MISSION)
	_check(int(ov_rec.get("endgame_seconds", 0)) == 1200,
		"W6U1.3 override endgame=1200 s (20 minutes)",
		"W6U1.3 override endgame=%s (want 1200)" % str(ov_rec.get("endgame_seconds")))
	_check(str(ov_rec.get("source", "")) == "KF13",
		"W6U1.4 override source=KF13",
		"W6U1.4 override source='%s' (want KF13)" % str(ov_rec.get("source", "")))
	_check(int(ov_rec.get("authored_qg_endgame_seconds", 0)) == 480,
		"W6U1.5 override records the extracted QG value 480 s",
		"W6U1.5 authored_qg_endgame_seconds missing/!=480")

	var plan: Dictionary = gd.call("get_mission_plan", OUT_MISSION) as Dictionary
	_check(int(plan.get("endgame_duration", 0)) == 480,
		"W6U1.6 QG plan endgame stays 480 (no silent re-baseline)",
		"W6U1.6 QG plan endgame=%s (want 480)" % str(plan.get("endgame_duration")))
	_check(absf(float(gd.call("get_mission_endgame_seconds", OUT_MISSION)) - 1200.0) < 0.5,
		"W6U1.7 runtime endgame accessor=1200 s",
		"W6U1.7 runtime endgame accessor=%s" % str(gd.call("get_mission_endgame_seconds", OUT_MISSION)))
	_check(str(gd.call("get_mission_endgame_source", OUT_MISSION)) == "KF13",
		"W6U1.8 runtime endgame source=KF13",
		"W6U1.8 runtime endgame source wrong")
	_check(absf(float(gd.call("get_mission_duration", OUT_MISSION, 1)) - 3300.0) < 0.5,
		"W6U1.9 mission row match window=3300 s (55 minutes)",
		"W6U1.9 mission row match window=%s" % str(gd.call("get_mission_duration", OUT_MISSION, 1)))

	var brief: Dictionary = gd.call("get_mission_briefing_record", OUT_MISSION) as Dictionary
	_check(not brief.is_empty(),
		"W6U1.10 authored ST_Missions briefing emitted by parse_quests.py",
		"W6U1.10 no mission_briefings record (regenerate quests.json?)")
	var raw: String = str(brief.get("text", ""))
	_check(raw.find("{MatchDurationInMinutes}") >= 0 and raw.find("{EndgameDurationInMinutes}") >= 0,
		"W6U1.11 raw letter keeps both authored placeholders",
		"W6U1.11 raw letter placeholders missing")
	_check(str(brief.get("table", "")) == "ST_Missions_Guildhall_LootTheRoom",
		"W6U1.12 letter source table is ST_Missions_Guildhall_LootTheRoom",
		"W6U1.12 letter table='%s'" % str(brief.get("table", "")))
	var st_text: String = ""
	var st_path: String = (ProjectSettings.globalize_path("res://") + "../extracted/json/StringTables/ST_Missions_Guildhall_LootTheRoom.json").simplify_path()
	if FileAccess.file_exists(st_path):
		var st_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(st_path))
		if st_parsed is Array and not (st_parsed as Array).is_empty():
			var entries: Variant = ((st_parsed as Array)[0] as Dictionary).get("StringTable", {}).get("KeysToEntries", {})
			if entries is Dictionary:
				st_text = str((entries as Dictionary).get("Guildhall.LootTheRoom.Briefing", ""))
	_check(st_text != "" and raw == st_text,
		"W6U1.13 raw letter is byte-identical to the extracted string table",
		"W6U1.13 raw letter differs from the extracted string table")

	var text: String = str(gd.call("get_mission_briefing_text", OUT_MISSION))
	_check(text.find("{") < 0,
		"W6U1.14 formatted letter has no unresolved '{'",
		"W6U1.14 formatted letter still contains a brace")
	_check(text.find("55 minute window") >= 0 and text.find("20 minutes") >= 0,
		"W6U1.15 formatted letter states 55-minute window and 20-minute door",
		"W6U1.15 formatted letter lacks 55/20 text")
	_check(gd.call("format_mission_briefing", raw, 3300.0, 1200.0) == text,
		"W6U1.16 formatting derives 55/20 from seconds (no UI-typed 20)",
		"W6U1.16 formatting is not seconds-derived")

	# --- 2. KF13 HUD letter ---------------------------------------------------
	var hud_scr: GDScript = load("res://src/ui/hud.gd") as GDScript
	var hud: CanvasLayer = hud_scr.new() as CanvasLayer
	root.add_child(hud)
	await _wait(3)
	var obj_lbl: Label = hud.get("obj_lbl") as Label
	hud.call("show_mission_letter", "", text)
	await _wait(2)
	var lines: PackedStringArray = hud.call("format_briefing_layout", text) as PackedStringArray
	var ref_ok: bool = lines.size() == KF13_LINES.size()
	if ref_ok:
		for i: int in range(KF13_LINES.size()):
			if lines[i] != KF13_LINES[i]:
				ref_ok = false
				break
	_check(ref_ok,
		"W6U1.17 letter layout is the authored 11-line KF13 wrap",
		"W6U1.17 letter layout=%d lines: %s" % [lines.size(), str(lines)])
	var body: Label = hud.get("_letter_body_lbl") as Label
	_check(body != null and body.text.find("{") < 0 and body.text.count("\n") == 10,
		"W6U1.18 HUD body renders 11 lines with no placeholder",
		"W6U1.18 HUD body lines=%d text='%s'" % [
			body.text.count("\n") + 1 if body != null else -1,
			body.text.substr(0, 60) if body != null else "<null>"])

	var paper: TextureRect = hud.find_child("MissionLetterPaper", true, false) as TextureRect
	var atlas_ok: bool = paper != null and paper.texture is AtlasTexture
	var region_ok: bool = false
	if atlas_ok:
		var atlas: AtlasTexture = paper.texture as AtlasTexture
		region_ok = absf(atlas.region.size.x - 813.0) < 0.5 and absf(atlas.region.size.y - 882.0) < 0.5
	_check(atlas_ok and region_ok,
		"W6U1.19 parchment uses the authored T_Paper01 crop (813x882)",
		"W6U1.19 parchment texture/crop wrong")
	var bar: Panel = hud.find_child("MissionLetterScrollbar", true, false) as Panel
	_check(bar != null and bar.visible and bar.size.x <= 4.0 and bar.position.x > 500.0,
		"W6U1.20 right inner-margin scrollbar present",
		"W6U1.20 scrollbar missing or misplaced")
	var blur: ColorRect = hud.find_child("MissionLetterBlurBackdrop", true, false) as ColorRect
	var blur_mat: ShaderMaterial = blur.material as ShaderMaterial if blur != null else null
	var blur_ok: bool = blur != null and blur.visible and blur_mat != null and blur_mat.shader != null \
		and blur_mat.shader.code.find("hint_screen_texture") >= 0 and blur_mat.shader.code.find("blur_px") >= 0
	_check(blur_ok,
		"W6U1.21 blurred safe-room backdrop is a screen-texture blur",
		"W6U1.21 blur backdrop missing/wrong shader")
	_check(obj_lbl != null and not obj_lbl.is_visible_in_tree(),
		"W6U1.22 gameplay HUD hidden behind the letter",
		"W6U1.22 gameplay HUD still visible behind the letter")
	var btn: Button = hud.find_child("MissionLetterContinueBtn", true, false) as Button
	_check(btn != null and btn.text.find("CONTINUE") >= 0,
		"W6U1.23 [SPACE] CONTINUE prompt present",
		"W6U1.23 continue prompt missing")
	hud.call("_close_mission_letter")
	await _wait(2)
	_check(obj_lbl != null and obj_lbl.is_visible_in_tree(),
		"W6U1.24 gameplay HUD restored on continue",
		"W6U1.24 gameplay HUD not restored")
	hud.queue_free()
	await _wait(2)

	# --- 3. Prep stage: ridge framing, decoupled moon, key/fill/rim ----------
	var mp_scr: GDScript = load("res://src/ui/mission_prep_ui.gd") as GDScript
	var mp_src: String = FileAccess.get_file_as_string("res://src/ui/mission_prep_ui.gd")
	var mp: Control = mp_scr.new() as Control
	mp.size = Vector2(1280, 720)
	root.add_child(mp)
	await _wait(3)
	mp.call("open_prep", "guildhall", 1, "Solo", 0, false)
	var cam: Camera3D = null
	for _i: int in range(600):
		cam = mp.find_child("MissionLobbyCamera", true, false) as Camera3D
		if cam != null:
			break
		await process_frame
	await _wait(10)
	_check(cam != null, "W6U1.25 prep stage camera built", "W6U1.25 prep stage camera missing")
	if cam != null:
		_check(absf(cam.fov - 20.0) < 0.01 and cam.keep_aspect == Camera3D.KEEP_WIDTH,
			"W6U1.26 authored FOV 20 (KEEP_WIDTH) preserved",
			"W6U1.26 FOV/keep_aspect changed: fov=%.2f keep=%d" % [cam.fov, cam.keep_aspect])
	var key: SpotLight3D = mp.find_child("MissionLobbyKey", true, false) as SpotLight3D
	var fill: OmniLight3D = mp.find_child("MissionLobbyFill", true, false) as OmniLight3D
	var rim: SpotLight3D = mp.find_child("MissionLobbyRim", true, false) as SpotLight3D
	_check(key != null and fill != null and rim != null,
		"W6U1.27 local key/fill/rim lights exist",
		"W6U1.27 local stage lights missing (key=%s fill=%s rim=%s)" % [str(key != null), str(fill != null), str(rim != null)])
	var thief_pos: Vector3 = Vector3(-1.5871, 0.82, -0.7868)
	if key != null:
		var to_thief: Vector3 = (thief_pos + Vector3(0, 1.05, 0) - key.global_position).normalized()
		var key_aim: bool = (-key.global_transform.basis.z).dot(to_thief) > 0.9
		_check(key_aim and key.light_energy > 0.0 and fill.light_energy > 0.0 and rim.light_energy > 0.0,
			"W6U1.28 key aims at the thief; key/fill/rim all lit",
			"W6U1.28 key aim/energies wrong")
	var moon: DirectionalLight3D = mp.find_child("MissionLobbyMoonLight", true, false) as DirectionalLight3D
	var env: Environment = null
	for n: Node in mp.find_children("*", "WorldEnvironment", true, false):
		var we: WorldEnvironment = n as WorldEnvironment
		if we.environment != null:
			env = we.environment
			break
	var disc: Vector3 = Vector3.ZERO
	if env != null and env.sky != null and env.sky.sky_material is ShaderMaterial:
		var sm: ShaderMaterial = env.sky.sky_material as ShaderMaterial
		disc = sm.get_shader_parameter("moon_direction") as Vector3
	var key_dir: Vector3 = (-moon.global_transform.basis.z) if moon != null else Vector3.ZERO
	var decoupled: bool = disc.length() > 0.5 and key_dir.length() > 0.5 and disc.dot(key_dir) < 0.98
	_check(decoupled,
		"W6U1.29 moon disc direction decoupled from the key light (dot=%.2f)" % disc.dot(key_dir),
		"W6U1.29 disc and key still share one direction (dot=%.2f)" % disc.dot(key_dir))
	var disc_screen_ok: bool = false
	if cam != null and disc.length() > 0.5:
		var p: Vector2 = cam.unproject_position(cam.global_position + disc * 10.0)
		var vp_size: Vector2 = cam.get_viewport().size
		if vp_size.x > 0.0 and vp_size.y > 0.0:
			var sx: float = p.x / vp_size.x
			var sy: float = p.y / vp_size.y
			disc_screen_ok = absf(sx - 0.88) < 0.03 and absf(sy - 0.12) < 0.03
			print("W6U1 moon disc screen=(%.3f, %.3f)" % [sx, sy])
	_check(disc_screen_ok,
		"W6U1.30 moon disc lands at the measured upper-right sky gap (0.88, 0.12)",
		"W6U1.30 moon disc screen position off the measured gap")
	_check(env != null and absf(env.background_energy_multiplier - 0.18) < 0.01,
		"W6U1.31 stage sky re-graded to navy (sky multiplier 0.18)",
		"W6U1.31 stage sky multiplier=%s" % str(env.background_energy_multiplier if env != null else -1.0))
	_check(mp_src.find("midnight_clear_mission_lobby") >= 0 and mp_src.find("\"gloomy\"") < 0,
		"W6U1.32 prep stage stays on midnight_clear_mission_lobby (not gloomy)",
		"W6U1.32 prep stage preset changed to gloomy")
	mp.queue_free()
	await _wait(3)

	# --- 4. Den poster wall + window backlight -------------------------------
	var helpers_scr: GDScript = load("res://tests/e2e/e2e_helpers.gd") as GDScript
	var h: RefCounted = helpers_scr.new(self)
	var den_res: Dictionary = await h.instantiate_mission(1, 200, 1)
	var den: Node = den_res.get("mission") as Node
	await _wait(3)
	var poster: OmniLight3D = den.find_child("DenPosterFill", true, false) as OmniLight3D if den != null else null
	var back: Node = den.find_child("DenWindowBacklight", true, false) if den != null else null
	_check(poster != null, "W6U1.33 DenPosterFill exists", "W6U1.33 DenPosterFill missing")
	_check(back != null and back is SpotLight3D and back.get_meta("room_facing", false) == true \
		and back.get_meta("outboard", false) == true,
		"W6U1.34 DenWindowBacklight is an outboard, room-facing spot",
		"W6U1.34 DenWindowBacklight is not the room-facing/outboard spot")
	var back_aim_ok: bool = false
	if back is SpotLight3D:
		var bs: SpotLight3D = back as SpotLight3D
		var anchor: Vector3 = bs.get_meta("den_window_anchor", Vector3.ZERO) as Vector3
		var outward: Vector3 = bs.get_meta("den_outward", Vector3.ZERO) as Vector3
		var outboard_m: float = (bs.global_position - anchor).dot(outward)
		var inward_aim: float = (-bs.global_transform.basis.z).dot(-outward)
		back_aim_ok = outboard_m >= 0.5 and inward_aim > 0.5
		print("W6U1 backlight outboard=%.2f inward_aim=%.2f" % [outboard_m, inward_aim])
	_check(back_aim_ok,
		"W6U1.35 backlight sits outboard and aims into the room",
		"W6U1.35 backlight position/aim wrong")
	var poster_ok: bool = false
	if poster != null:
		var near_wall: float = poster.global_position.distance_to(
			Vector3(-5.7777, 41.58, 269.0) + Vector3(0.52, 0.0, 0.0))
		poster_ok = poster.light_energy <= 0.101 and near_wall < 0.2 \
			and poster.is_in_group("den_hand_fills") \
			and poster.light_color.r > poster.light_color.g and poster.light_color.g > poster.light_color.b
	_check(poster_ok,
		"W6U1.36 poster fill <=0.10 warm, at the authored poster wall, in den_hand_fills",
		"W6U1.36 poster fill values wrong: energy=%s pos=%s group=%s" % [
			str(poster.light_energy) if poster != null else "n/a",
			str(poster.global_position) if poster != null else "n/a",
			str(poster.is_in_group("den_hand_fills")) if poster != null else "n/a"])
	var fill_sum: float = 0.0
	if den != null:
		for fl: Node in get_nodes_in_group("den_hand_fills"):
			if fl is Light3D and den.is_ancestor_of(fl):
				fill_sum += (fl as Light3D).light_energy
	_check(fill_sum <= 2.01,
		"W6U1.37 den_hand_fills=%.2f <= 2.01 (no exposure/glow lift)" % fill_sum,
		"W6U1.37 den_hand_fills=%.2f exceeds 2.01" % fill_sum)
	if den != null:
		await h.free_node(den)
	await _wait(2)
	_finish()


func _finish() -> void:
	print("W6U1_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)
