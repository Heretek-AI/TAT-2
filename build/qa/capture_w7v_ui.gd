extends SceneTree
## W7V acceptance captures for the UI surfaces this wave touches:
##   prep   — KF11 mission preparation stage (1920x1080, and a 1280x720 fit)
##   wardrobe_kf03 / wardrobe_kf04 / wardrobe_chameleon — KF03/KF04 plus the
##            Cotter Chameleon body/head defaults
##   ledger_kf07 / ledger_kf08 — Journal and Black Market with the live 3D
##            tool preview
##   briefing — KF13 authored letter over the live free-play safe room
##   den_poster — KF06/KF02 Wanted-poster wall
##
## Run one Godot at a time, native Vulkan under Xvfb 1920x1080:
##   DISPLAY=:99 XDG_DATA_HOME=/tmp/opencode/w7v-data \
##     tools/godot --path game --rendering-driver vulkan \
##     --script build/qa/capture_w7v_ui.gd
## Environment:
##   W7V_OUT   output directory (default /tmp/opencode/w7v-captures)
##   W7V_TAG   filename tag, e.g. "before" / "after" (default "after")
##   W7V_SIZE  "1080" or "720" (default 1080)
##   W7V_ONLY  comma list of shots to run (default all)
## Every PNG gets a .txt sidecar with the engine, size, renderer, camera pose,
## FOV/aspect, weather preset, save/profile snapshot and the measured ROI
## luminance stats for that frame.

const DEFAULT_OUT: String = "/tmp/opencode/w7v-captures"
const KF08_CURRENCY: int = 26275
const KF08_XP: int = 1500
const KF08_LEVEL: int = 4

var out_dir: String = DEFAULT_OUT
var tag: String = "after"
var shot_w: int = 1920
var shot_h: int = 1080
var only: PackedStringArray = PackedStringArray()

func _init() -> void:
	call_deferred("_run")

func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame

## Luminance mean/max for a normalised (0..1, top-left origin) rect.
func _roi_stats(img: Image, r: Rect2) -> Dictionary:
	var x0: int = clampi(int(r.position.x * float(img.get_width())), 0, img.get_width() - 1)
	var y0: int = clampi(int(r.position.y * float(img.get_height())), 0, img.get_height() - 1)
	var x1: int = clampi(int(r.end.x * float(img.get_width())), x0 + 1, img.get_width())
	var y1: int = clampi(int(r.end.y * float(img.get_height())), y0 + 1, img.get_height())
	var total: float = 0.0
	var peak: float = 0.0
	var count: int = 0
	for y: int in range(y0, y1, 2):
		for x: int in range(x0, x1, 2):
			var c: Color = img.get_pixel(x, y)
			var l: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			total += l
			peak = maxf(peak, l)
			count += 1
	return {"mean": total / maxf(float(count), 1.0), "max": peak, "px": count}

func _save(fname: String, rois: Dictionary, extra: Array[String]) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		printerr("W7V CAPTURE FAILED: ", fname)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path: String = out_dir + "/" + fname
	var err: int = img.save_png(path)
	print("W7V CAPTURE: ", fname, " ", img.get_width(), "x", img.get_height(), " err=", err)
	var save: Node = root.get_node_or_null("/root/SaveSystem")
	var save_path: String = ""
	if save != null and save.has_method("get_save_path"):
		save_path = str(save.call("get_save_path"))
	var gs: Node = root.get_node_or_null("/root/GameState")
	var side: FileAccess = FileAccess.open(out_dir + "/" + fname.get_basename() + ".txt", FileAccess.WRITE)
	if side == null:
		return
	side.store_line("capture=%s" % fname)
	side.store_line("tag=%s" % tag)
	side.store_line("size=%dx%d" % [img.get_width(), img.get_height()])
	side.store_line("engine=%s" % str(Engine.get_version_info().get("string", "")))
	side.store_line("renderer=%s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")))
	side.store_line("timestamp=%s" % Time.get_datetime_string_from_system())
	side.store_line("save_home=%s" % OS.get_environment("XDG_DATA_HOME"))
	side.store_line("save_path=%s" % save_path)
	if gs != null:
		side.store_line("profile=thief:%s level:%s currency:%s map:%s contract:%s" % [
			str(gs.get("thief_id")), str(gs.get("level")), str(gs.get("currency")),
			str(gs.get("active_map_id")), str(gs.get("active_contract_order"))])
	for line: String in extra:
		side.store_line(line)
	for roi_name: String in rois.keys():
		var r: Rect2 = rois[roi_name] as Rect2
		var st: Dictionary = _roi_stats(img, r)
		side.store_line("roi.%s=%.4f,%.4f,%.4f,%.4f mean=%.4f max=%.4f px=%d" % [
			roi_name, r.position.x, r.position.y, r.size.x, r.size.y,
			float(st["mean"]), float(st["max"]), int(st["px"])])
	side.close()

func _cam_sidecar(cam: Camera3D) -> String:
	if cam == null:
		return "camera=none"
	return "camera.pos=%.4f,%.4f,%.4f fwd=%.4f,%.4f,%.4f fov=%.3f keep_aspect=%d far=%.1f" % [
		cam.global_position.x, cam.global_position.y, cam.global_position.z,
		-cam.global_transform.basis.z.x, -cam.global_transform.basis.z.y, -cam.global_transform.basis.z.z,
		cam.fov, cam.keep_aspect, cam.far]

func _preset_sidecar(map_id: String) -> String:
	return "weather_preset=%s" % str(WeatherProfileScript.preset_for_map(map_id))

func _wants(shot: String) -> bool:
	return only.is_empty() or only.has(shot)

const WeatherProfileScript: GDScript = preload("res://src/core/weather_profile.gd")

func _run() -> void:
	if OS.has_environment("W7V_OUT"):
		out_dir = OS.get_environment("W7V_OUT")
	if OS.has_environment("W7V_TAG"):
		tag = OS.get_environment("W7V_TAG")
	if OS.has_environment("W7V_SIZE") and OS.get_environment("W7V_SIZE") == "720":
		shot_w = 1280
		shot_h = 720
	if OS.has_environment("W7V_ONLY"):
		only = OS.get_environment("W7V_ONLY").split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(shot_w, shot_h)
	await _wait(4)
	var gs: Node = root.get_node_or_null("/root/GameState")
	var save: Node = root.get_node_or_null("/root/SaveSystem")
	if gs != null:
		gs.set("difficulty", 1)
		gs.set("thief_id", "spider")
		gs.set("active_contract_order", 2)
	# KF07/KF08 reference profile: Level 4, 94/500 XP tally, £26,275, two
	# completed contracts. Applied for the capture only; XDG_DATA_HOME isolates
	# the save so the player profile is untouched.
	if save != null:
		var data: Dictionary = save.get("data") as Dictionary
		if data != null:
			data["level"] = KF08_LEVEL
			data["xp"] = KF08_XP
			data["currency"] = KF08_CURRENCY
			data["completed_contracts"] = {"1": true, "2": true}

	# --- prep (KF11) --------------------------------------------------------
	if _wants("prep"):
		var mp: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
		mp.size = Vector2(shot_w, shot_h)
		root.add_child(mp)
		await _wait(4)
		mp.call("open_prep", "guildhall", 1, "Solo", 0, false)
		await _wait(120)
		var cam: Camera3D = mp.find_child("MissionLobbyCamera", true, false) as Camera3D
		var moon: DirectionalLight3D = mp.find_child("MissionLobbyMoonLight", true, false) as DirectionalLight3D
		var skyline: int = mp.find_children("PrepSkyline_*", "MeshInstance3D", true, false).size()
		var extras: Array[String] = [
			_cam_sidecar(cam),
			_preset_sidecar("guildhall"),
			"pose.prep=thief_world(-0.4281,0.82,-1.3868) yaw45 skyline=%d" % skyline,
			"skyline_nodes=%d" % skyline,
		]
		if moon != null:
			extras.append("moon_key.dir=%.4f,%.4f,%.4f energy=%.3f" % [
				-moon.global_transform.basis.z.x, -moon.global_transform.basis.z.y,
				-moon.global_transform.basis.z.z, moon.light_energy])
		var rois: Dictionary = {
			"moon": Rect2(0.62, 0.00, 0.30, 0.26),
			"thief": Rect2(0.68, 0.24, 0.18, 0.72),
			"ridge": Rect2(0.24, 0.68, 0.64, 0.30),
			"skyline_mid": Rect2(0.44, 0.26, 0.40, 0.34),
			"full": Rect2(0.0, 0.0, 1.0, 1.0),
		}
		await _save("prep_%s.png" % tag, rois, extras)
		mp.queue_free()
		await _wait(4)

	# --- wardrobe KF03 / KF04 / Chameleon ------------------------------------
	if _wants("wardrobe_kf03") or _wants("wardrobe_kf04") or _wants("wardrobe_chameleon"):
		var wd: CanvasLayer = (load("res://src/ui/wardrobe_ui.gd") as GDScript).new() as CanvasLayer
		root.add_child(wd)
		await _wait(4)
		wd.call("open_customizer")
		await _wait(45)
		if _wants("wardrobe_kf03"):
			var extras: Array[String] = [
				"pose.wardrobe=thief:%s head:%s body:%s card:%s" % [
					str(wd.get("_thief_id")), str(wd.get("_head")), str(wd.get("_body")), str(wd.get("_card"))],
				"wardrobe.slots=%s" % str(wd.get("_slots")),
				"wardrobe.cam=auto_frame fov=36.0",
			]
			await _save("wardrobe_kf03_%s.png" % tag, {
				"thief": Rect2(0.36, 0.06, 0.28, 0.88),
				"left_panel": Rect2(0.01, 0.10, 0.30, 0.84),
				"right_panel": Rect2(0.74, 0.10, 0.25, 0.84),
			}, extras)
		if _wants("wardrobe_kf04"):
			wd.call("_on_slot_pressed", 2)
			await _wait(24)
			var extras4: Array[String] = [
				"pose.wardrobe=slot3_expanded head:%s body:%s" % [str(wd.get("_head")), str(wd.get("_body"))],
				"wardrobe.candidates=%d" % (wd.get("_cell_btns") as Array).size(),
			]
			await _save("wardrobe_kf04_%s.png" % tag, {
				"thief": Rect2(0.36, 0.06, 0.28, 0.88),
				"candidate_row": Rect2(0.02, 0.76, 0.72, 0.20),
			}, extras4)
		if _wants("wardrobe_chameleon"):
			if save != null:
				var perks: Array = save.get("data").get("unlocked_perks", [])
				if not perks.has("chameleon"):
					perks.append("chameleon")
			wd.call("_cycle_thief", 1)
			await _wait(40)
			var extras5: Array[String] = [
				"pose.wardrobe=thief:%s head:%s body:%s card:%s" % [
					str(wd.get("_thief_id")), str(wd.get("_head")), str(wd.get("_body")), str(wd.get("_card"))],
				"wardrobe.body_path_used=%s" % str(wd.call("_resolve_body_path", wd.get("_body"))),
				"wardrobe.head_path_used=%s" % str(wd.call("_resolve_head_path", wd.get("_head"))),
			]
			await _save("wardrobe_chameleon_%s.png" % tag, {
				"thief": Rect2(0.36, 0.06, 0.28, 0.88),
			}, extras5)
		wd.queue_free()
		await _wait(4)

	# --- ledger KF07 / KF08 -------------------------------------------------
	if _wants("ledger_kf07") or _wants("ledger_kf08"):
		var led: Control = (load("res://src/ui/ledger_ui.gd") as GDScript).new() as Control
		led.size = Vector2(shot_w, shot_h)
		root.add_child(led)
		await _wait(20)
		if _wants("ledger_kf07"):
			led.call("_show_tab", 0)
			await _wait(12)
			var extras7: Array[String] = [
				"pose.ledger=tab:journal",
				"ledger.level=%s xp=%s" % [str(gs.get("level")), str(gs.get("xp"))],
			]
			await _save("ledger_kf07_%s.png" % tag, {
				"portrait": Rect2(0.03, 0.08, 0.30, 0.30),
				"contracts": Rect2(0.03, 0.40, 0.94, 0.35),
				"xp": Rect2(0.03, 0.30, 0.30, 0.10),
			}, extras7)
		if _wants("ledger_kf08"):
			led.call("_show_tab", 1)
			led.call("_on_item_pressed", "zipwire")
			await _wait(24)
			var preview: Node = led.find_child("LedgerToolPreview", true, false)
			var extras8: Array[String] = [
				"pose.ledger=tab:market selected:zipwire",
				"ledger.assets_text=%s" % str((led.get("_assets_lbl") as Label).text),
				"ledger.tool_preview=%s" % ("3d" if preview != null else "icon"),
			]
			await _save("ledger_kf08_%s.png" % tag, {
				"preview_card": Rect2(0.01, 0.14, 0.44, 0.34),
				"tables_left": Rect2(0.01, 0.50, 0.48, 0.46),
				"tables_right": Rect2(0.50, 0.14, 0.48, 0.82),
			}, extras8)
		led.queue_free()
		await _wait(4)

	# --- KF13 briefing over the live free-play safe room -------------------
	if _wants("briefing"):
		var helpers_scr: GDScript = load("res://tests/e2e/e2e_helpers.gd") as GDScript
		var h: RefCounted = helpers_scr.new(self)
		if gs != null:
			gs.set("active_contract_order", 2)
			gs.set("active_map_id", "guildhall")
			gs.call("begin_free_play", "Mission.Guildhall.LootTheRoom")
		var res: Dictionary = await h.instantiate_mission(2, 600, 1)
		var gh: Node = res.get("mission") as Node
		var hud: Node = res.get("hud") as Node
		var letter_seen: bool = false
		for _i: int in range(240):
			if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
				letter_seen = true
				break
			await process_frame
		await _wait(30)
		var extrasb: Array[String] = [
			"pose.briefing=free_play LootTheRoom letter_open=%s" % str(letter_seen),
			_preset_sidecar("guildhall"),
		]
		await _save("briefing_%s.png" % tag, {
			"paper": Rect2(0.285, 0.185, 0.43, 0.62),
			"paper_text": Rect2(0.30, 0.28, 0.38, 0.45),
		}, extrasb)
		if hud != null and hud.has_method("_close_mission_letter"):
			hud.call("_close_mission_letter")
			await _wait(4)
		if gh != null:
			await h.free_node(gh)
		await _wait(4)

	# --- Den Wanted-poster wall (KF06 / C2) --------------------------------
	if _wants("den_poster"):
		var helpers_scr2: GDScript = load("res://tests/e2e/e2e_helpers.gd") as GDScript
		var h2: RefCounted = helpers_scr2.new(self)
		if gs != null:
			gs.set("active_contract_order", 1)
			gs.set("active_map_id", "thieves_den")
		var den_res: Dictionary = await h2.instantiate_mission(1, 600, 1)
		var den: Node = den_res.get("mission") as Node
		if den != null:
			var dhud: Node = den.get("hud") as Node
			if dhud is CanvasLayer:
				(dhud as CanvasLayer).visible = false
			var den_cam: Camera3D = Camera3D.new()
			den_cam.name = "W7VPosterCam"
			den_cam.fov = 54.54
			den_cam.keep_aspect = Camera3D.KEEP_HEIGHT
			den_cam.far = 200.0
			den.add_child(den_cam)
			den_cam.global_position = Vector3(1.2, 41.75, 269.0)
			den_cam.look_at(Vector3(-5.7777, 41.55, 269.0), Vector3.UP)
			den_cam.current = true
			await _wait(20)
			await _save("den_poster_%s.png" % tag, {
				"posters": Rect2(0.10, 0.25, 0.45, 0.45),
			}, [_cam_sidecar(den_cam), _preset_sidecar("thieves_den")])
			# C1: the framed west opening the telescope faces (W5C staging).
			den_cam.fov = 54.54
			den_cam.global_position = Vector3(1.6, 41.8, 272.4)
			den_cam.look_at(Vector3(-6.06, 43.0, 271.4), Vector3.UP)
			await _wait(16)
			await _save("den_west_window_%s.png" % tag, {
				"opening": Rect2(0.02, 0.18, 0.45, 0.55),
				"sill": Rect2(0.20, 0.62, 0.55, 0.30),
			}, [_cam_sidecar(den_cam), _preset_sidecar("thieves_den"),
				"pose.den_west=anchor(-6.06,43.05,271.4) room_side"])
			await h2.free_node(den)
		await _wait(4)

	print("W7V UI CAPTURES DONE tag=", tag)
	quit(0)
