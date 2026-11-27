extends SceneTree
## P5 UI capture harness (U-1/U-2) — the twelve adjudication screens.
##
## Screens and the row each frame serves (docs/reference/.../COMPARISON_PORT):
##   startscreen    UI1-01  S01/KF01   main menu stack
##   den_hud        UI3-01  S03/KF02   Den + live HUD (card, compass, gem)
##   pause          UI1-02  S27/KF30   pause modal over the foyer backdrop
##   prep           UI4-03  S09/KF11   mission preparation stage
##   briefing       UI4-04  S11/KF13   the authored letter over the safe room
##   contract_table UI3-06  S08/KF10   map table + keybind legend
##   wardrobe       UI2-02  S04/KF03   Spider turntable + loadout
##   ledger         UI4-01  S06/KF07   Journal tab (ledger_market = UI4-02)
##   safe_room      UI3-05  S12/KF14   HUD + Light Gem at the lantern
##   crank          UI2-04  S15/KF17   centre CRANK prompt + segmented ring
##   doors          UI2-05  S21/KF24   [F] OPEN over [F] [HOLD] LOCK
##   key            UI3-04  S22/KF27   Guildhall Key row above [1]
## `pause_backdrop` is not a screen: it is the same foyer pose without the
## modal, so `build/qa/ui_pixel_stats.py` can measure the blur/dim delta.
##
## Every PNG gets a `.txt` sidecar (engine, renderer, size, save/profile
## snapshot, camera pose, HUD state, ROI luma stats). The HUD state lines are
## what the pixel scorer correlates against; staged frames say `staged=` so no
## frame can be read as a gameplay claim.
##
## Run one Godot at a time, native Vulkan under Xvfb (GPU capture is the
## integrator's step; this script never runs in the headless gate):
##
##   DISPLAY=:99 XDG_DATA_HOME=/tmp/opencode/p5-ui-data \
##     tools/godot --path game --rendering-driver vulkan \
##     --script build/qa/capture_p5_ui.gd
##
## Environment:
##   P5_OUT    output dir (default /tmp/opencode/p5-ui-captures/<run id>)
##   P5_TAG    filename tag (default "p5")
##   P5_SIZE   both | 1080 | 720 (default both; runs 1280x720 then 1920x1080)
##   P5_ONLY   comma list of shots (default all)
##   P5_RUN_ID run id recorded in the sidecar (default UTC stamp)
##   P5_SEED   map seed (default 0 = authored)
##
## Exit 0 when every requested shot wrote a frame; 1 when a shot failed.

const OUT_DEFAULT: String = "/tmp/opencode/p5-ui-captures"
const SHIPPED_FOV: float = 54.54
const EYE_OFFSET: float = 1.67

## Authored capture poses reused from build/qa/p0b_route.gd (same numbers, so
## a UI frame can be paired with the route evidence without a second guess).
const SAFE_ROOM_EYE: Vector3 = Vector3(127.2747, 27.1394, -5.3296)
const SAFE_ROOM_TARGET: Vector3 = Vector3(125.70, 26.70, -2.29)
const FOYER_EYE: Vector3 = Vector3(27.0, 29.67, -50.0)
const FOYER_TARGET: Vector3 = Vector3(27.0, 29.67, -60.0)
const DEN_EYE: Vector3 = Vector3(4.2, 41.9, 271.2)
const DEN_TARGET: Vector3 = Vector3(-4.5, 41.5, 271.5)

const SHOTS: Array[String] = [
	"startscreen", "den_hud", "wardrobe", "ledger", "ledger_market",
	"contract_table", "prep", "briefing", "safe_room", "crank", "doors",
	"key", "pause_backdrop", "pause",
]

var out_dir: String = OUT_DEFAULT
var tag: String = "p5"
var run_id: String = ""
var only: PackedStringArray = PackedStringArray()
var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
var shot_w: int = 1280
var shot_h: int = 720
var failures: int = 0
var captures: int = 0


func _init() -> void:
	call_deferred("_run")


func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _stamp() -> String:
	var t: Dictionary = Time.get_datetime_dict_from_system(true)
	return "%04d%02d%02dT%02d%02d%02dZ" % [
		int(t.get("year", 0)), int(t.get("month", 0)), int(t.get("day", 0)),
		int(t.get("hour", 0)), int(t.get("minute", 0)), int(t.get("second", 0))]


func _wants(shot: String) -> bool:
	return only.is_empty() or only.has(shot)


func _suffix() -> String:
	return "%s_%dx%d" % [tag, shot_w, shot_h]


## Luminance mean/max for a normalised (0..1, top-left origin) rect, sampled
## every 2nd pixel (the same convention as capture_w7v_ui.gd).
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


func _cam_sidecar(cam: Camera3D) -> String:
	if cam == null:
		return "camera=none"
	return "camera.pos=%.4f,%.4f,%.4f fwd=%.4f,%.4f,%.4f fov=%.3f keep_aspect=%d far=%.1f" % [
		cam.global_position.x, cam.global_position.y, cam.global_position.z,
		-cam.global_transform.basis.z.x, -cam.global_transform.basis.z.y, -cam.global_transform.basis.z.z,
		cam.fov, cam.keep_aspect, cam.far]


## HUD state that the pixel scorer correlates with: the gem slice/path, the
## compass letters, the live prompt strings and the key row. Empty when the
## shot has no HUD.
func _hud_sidecar(hud: Node) -> Array:
	var lines: Array = []
	if hud == null or not is_instance_valid(hud):
		lines.append("hud=none")
		return lines
	var state: Dictionary = {}
	if hud.has_method("light_gem_state"):
		state = hud.call("light_gem_state") as Dictionary
	lines.append("hud.gem=path:%s bound:%s layers:%d kind:%s slice:%d amount:%.3f lit_area:%.3f angle:%.1f" % [
		str(state.get("gem_path", "")), str(state.get("array_bound", false)),
		int(state.get("array_layers", 0)), str(state.get("mapping_kind", "")),
		int(state.get("slice_index", -1)), float(state.get("amount", 0.0)),
		float(state.get("lit_area_fraction", 0.0)), float(state.get("sector_angle_deg", 0.0))])
	lines.append("hud.compass=%s" % str(hud.get("compass_lbl").text if hud.get("compass_lbl") != null else ""))
	lines.append("hud.prompt=%s" % str(hud.get("current_prompt")))
	var secondary: Variant = hud.get("_prompt_secondary_lbl")
	lines.append("hud.prompt_secondary=%s" % (str((secondary as Label).text) if secondary is Label and (secondary as Label).visible else ""))
	var keys: Variant = hud.get("_keys_lbl")
	lines.append("hud.keys=%s" % (str((keys as Label).text) if keys is Label and (keys as Label).visible else ""))
	lines.append("hud.letter_open=%s" % str(bool(hud.call("is_mission_letter_open")) if hud.has_method("is_mission_letter_open") else false))
	lines.append("hud.tree_paused=%s" % str(paused))
	return lines


func _save(shot: String, rois: Dictionary, extras: Array) -> bool:
	if DisplayServer.get_name() == "headless":
		# frame_post_draw never fires without a renderer, so a headless run
		# would hang. Fail loudly with the command to use instead.
		printerr("P5_CAPTURE FAILED headless shot=%s: run under Xvfb + Vulkan (see the header)" % shot)
		failures += 1
		return false
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		printerr("P5_CAPTURE FAILED image shot=%s" % shot)
		failures += 1
		return false
	DirAccess.make_dir_recursive_absolute(out_dir)
	var base: String = "%s_%s" % [shot, _suffix()]
	var path: String = out_dir + "/" + base + ".png"
	var err: int = img.save_png(path)
	if err != OK:
		printerr("P5_CAPTURE FAILED save shot=%s err=%d" % [shot, err])
		failures += 1
		return false
	captures += 1
	print("P5_CAPTURE shot=%s path=%s w=%d h=%d" % [shot, path, img.get_width(), img.get_height()])
	var gs: Node = root.get_node_or_null("/root/GameState")
	var save: Node = root.get_node_or_null("/root/SaveSystem")
	var save_path: String = ""
	if save != null and save.has_method("get_save_path"):
		save_path = str(save.call("get_save_path"))
	var side: FileAccess = FileAccess.open(out_dir + "/" + base + ".txt", FileAccess.WRITE)
	if side == null:
		printerr("P5_CAPTURE FAILED sidecar shot=%s" % shot)
		failures += 1
		return false
	side.store_line("capture=%s" % base)
	side.store_line("shot=%s" % shot)
	side.store_line("tag=%s" % tag)
	side.store_line("run_id=%s" % run_id)
	side.store_line("size=%dx%d" % [img.get_width(), img.get_height()])
	side.store_line("engine=%s" % str(Engine.get_version_info().get("string", "")))
	side.store_line("renderer=%s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")))
	side.store_line("timestamp=%s" % Time.get_datetime_string_from_system())
	side.store_line("save_home=%s" % OS.get_environment("XDG_DATA_HOME"))
	side.store_line("save_path=%s" % save_path)
	if gs != null:
		side.store_line("profile=thief:%s level:%s currency:%s map:%s contract:%s mode:%s free_play:%s" % [
			str(gs.get("thief_id")), str(gs.get("level")), str(gs.get("currency")),
			str(gs.get("active_map_id")), str(gs.get("active_contract_order")),
			str(gs.get("active_mission_mode")), str(gs.get("free_play"))])
	for line: String in extras:
		side.store_line(line)
	for roi_name: String in rois.keys():
		var r: Rect2 = rois[roi_name] as Rect2
		var st: Dictionary = _roi_stats(img, r)
		side.store_line("roi.%s=%.4f,%.4f,%.4f,%.4f mean=%.4f max=%.4f px=%d" % [
			roi_name, r.position.x, r.position.y, r.size.x, r.size.y,
			float(st["mean"]), float(st["max"]), int(st["px"])])
	side.close()
	return true


# ---------------------------------------------------------------------------
# Mission helpers (same contract as build/qa/p0b_route.gd, no letter close)
# ---------------------------------------------------------------------------

func _mission(map_id: String, order: int, free_play: bool = false, mission_id: String = "") -> Node3D:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("P5_MISSION_FAIL GameState missing")
		return null
	gs.set("state", "playing")
	gs.set("thief_id", "spider")
	gs.set("difficulty", 1)
	gs.set("active_mission_mode", "Solo")
	gs.set("active_contract_order", order)
	gs.set("active_map_id", map_id)
	if free_play and gs.has_method("begin_free_play"):
		gs.call("begin_free_play", mission_id)
	elif gs.has_method("end_free_play"):
		gs.call("end_free_play")
	var mission: Node3D = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(mission)
	var waited: int = 0
	while waited < 1800:
		var player_ready: bool = mission.get("player") != null
		var doors_ok: bool = order <= 1 or not get_nodes_in_group("swinging_doors").is_empty()
		if player_ready and doors_ok:
			break
		await process_frame
		waited += 1
	await _wait(40)
	if mission.get("player") == null:
		printerr("P5_MISSION_FAIL map=%s waited=%d" % [map_id, waited])
		mission.queue_free()
		return null
	print("P5_MISSION ready map=%s order=%d free_play=%s mission=%s waited=%d doors=%d" % [
		map_id, order, str(free_play), mission_id, waited,
		get_nodes_in_group("swinging_doors").size()])
	return mission


func _make_camera(mission: Node3D, node_name: String) -> Camera3D:
	var cam: Camera3D = Camera3D.new()
	cam.name = node_name
	cam.fov = SHIPPED_FOV
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 4000.0
	mission.add_child(cam)
	return cam


func _aim(cam: Camera3D, eye: Vector3, target: Vector3) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.current = true


## Real first-person rig at the authored eye (feet = eye - 1.67), frozen so the
## still cannot bob or step. Mirrors p0b_route's `_aim_player`.
func _aim_player(mission: Node3D, eye: Vector3, target: Vector3) -> Camera3D:
	if mission == null or not is_instance_valid(mission):
		return null
	var player: Node3D = mission.get("player") as Node3D
	if player == null or not is_instance_valid(player):
		return null
	var head: Node3D = player.get("head") as Node3D
	var cam: Camera3D = player.get("cam") as Camera3D
	if head == null or cam == null:
		return null
	var dir: Vector3 = target - eye
	if dir.length() < 0.001:
		return null
	dir = dir.normalized()
	player.set("velocity", Vector3.ZERO)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_rotation.y = atan2(-dir.x, -dir.z)
	head.rotation.x = asin(clampf(dir.y, -1.0, 1.0))
	player.global_position = Vector3(eye.x, eye.y - EYE_OFFSET, eye.z)
	player.set("base_fov", SHIPPED_FOV)
	cam.fov = SHIPPED_FOV
	cam.current = true
	return cam


func _find_ui_node(host: Node, script_name: String) -> Node:
	for n: Node in host.find_children("*", "CanvasLayer", true, false):
		var scr: Script = n.get_script() as Script
		if scr != null and str(scr.resource_path).ends_with(script_name):
			return n
	return null


func _find_ui_control(host: Node, script_name: String) -> Node:
	for n: Node in host.find_children("*", "Control", true, false):
		var scr: Script = n.get_script() as Script
		if scr != null and str(scr.resource_path).ends_with(script_name):
			return n
	return null


func _free_ui(host: Node, script_name: String) -> void:
	var layer: Node = _find_ui_node(host, script_name)
	if layer != null:
		layer.queue_free()
	else:
		var ctl: Node = _find_ui_control(host, script_name)
		if ctl != null:
			ctl.queue_free()


func _free_mission(mission: Node3D) -> void:
	if mission != null and is_instance_valid(mission):
		mission.queue_free()
	await _wait(8)


# ---------------------------------------------------------------------------
# Shots
# ---------------------------------------------------------------------------

func _shot_startscreen() -> void:
	var mm: Control = (load("res://src/ui/main_menu.gd") as GDScript).new() as Control
	mm.size = Vector2(shot_w, shot_h)
	root.add_child(mm)
	await _wait(50)
	await _save("startscreen", {
		"logo": Rect2(0.42, 0.05, 0.56, 0.26),
		"menu": Rect2(0.55, 0.30, 0.42, 0.50),
		"full": Rect2(0.0, 0.0, 1.0, 1.0),
	}, ["pose=startscreen(none)", "staged=main_menu.gd standalone"])
	mm.queue_free()
	await _wait(4)


func _shot_den(mission: Node3D) -> void:
	var hud: Node = mission.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(10)
	var cam: Camera3D = _make_camera(mission, "P5DenCamera")
	_aim(cam, DEN_EYE, DEN_TARGET)
	await _wait(24)
	await _save("den_hud", {
		# No Light Gem in the hub: the stealth ball is mission-only HUD.
		"compass": Rect2(0.30, 0.0, 0.40, 0.10),
		"player_card": Rect2(0.72, 0.0, 0.28, 0.13),
		"loot": Rect2(0.0, 0.02, 0.27, 0.13),
		"hotbar": Rect2(0.012, 0.79, 0.26, 0.20),
		"full": Rect2(0.0, 0.0, 1.0, 1.0),
	}, [_cam_sidecar(cam), "pose=den_entry(4.2,41.9,271.2)->(-4.5,41.5,271.5)"] + _hud_sidecar(hud))
	cam.queue_free()
	await _wait(4)


func _shot_wardrobe(mission: Node3D) -> void:
	var hud: Node = mission.get("hud") as Node
	if mission.has_method("open_wardrobe_ui"):
		mission.call("open_wardrobe_ui")
		await _wait(45)
		var ward: Node = _find_ui_node(mission, "wardrobe_ui.gd")
		if ward == null:
			printerr("P5_CAPTURE FAILED wardrobe: open_wardrobe_ui did not add wardrobe_ui.gd")
			failures += 1
		else:
			await _save("wardrobe", {
				"thief": Rect2(0.36, 0.06, 0.28, 0.88),
				"left_panel": Rect2(0.01, 0.10, 0.30, 0.84),
				"right_panel": Rect2(0.74, 0.10, 0.25, 0.84),
			}, [_hud_sidecar(hud), "pose=wardrobe turntable (auto frame fov=36)"])
		_free_ui(mission, "wardrobe_ui.gd")
		await _wait(8)
	else:
		printerr("P5_CAPTURE FAILED wardrobe: mission has no open_wardrobe_ui")
		failures += 1


func _shot_ledger(mission: Node3D) -> void:
	var hud: Node = mission.get("hud") as Node
	if not mission.has_method("open_ledger_ui"):
		printerr("P5_CAPTURE FAILED ledger: mission has no open_ledger_ui")
		failures += 1
		return
	mission.call("open_ledger_ui")
	await _wait(24)
	var ledger: Node = _find_ui_control(mission, "ledger_ui.gd")
	if ledger == null:
		printerr("P5_CAPTURE FAILED ledger: open_ledger_ui did not yield a LedgerUI Control")
		failures += 1
	else:
		if _wants("ledger"):
			if ledger.has_method("_show_tab"):
				ledger.call("_show_tab", 0)
			await _wait(16)
			await _save("ledger", {
				"tabs": Rect2(0.01, 0.02, 0.98, 0.10),
				"portrait": Rect2(0.03, 0.08, 0.30, 0.30),
				"contracts": Rect2(0.03, 0.40, 0.94, 0.35),
				"xp": Rect2(0.03, 0.30, 0.30, 0.10),
			}, [_hud_sidecar(hud), "pose=ledger tab:journal"])
		if _wants("ledger_market"):
			if ledger.has_method("_show_tab"):
				ledger.call("_show_tab", 1)
			if ledger.has_method("_on_item_pressed"):
				ledger.call("_on_item_pressed", "zipwire")
			await _wait(24)
			await _save("ledger_market", {
				"tabs": Rect2(0.01, 0.02, 0.98, 0.10),
				"preview_card": Rect2(0.01, 0.14, 0.44, 0.34),
				"tables_left": Rect2(0.01, 0.50, 0.48, 0.46),
				"tables_right": Rect2(0.50, 0.14, 0.48, 0.82),
			}, [_hud_sidecar(hud), "pose=ledger tab:black_market selected:zipwire"])
	_free_ui(mission, "ledger_ui.gd")
	await _wait(8)


func _shot_contract_table(mission: Node3D) -> void:
	var hud: Node = mission.get("hud") as Node
	if not mission.has_method("open_contract_table_ui"):
		printerr("P5_CAPTURE FAILED contract_table: mission has no open_contract_table_ui")
		failures += 1
		return
	if mission.has_method("set_den_selected_map"):
		mission.call("set_den_selected_map", "guildhall")
		await _wait(4)
	mission.call("open_contract_table_ui")
	await _wait(28)
	var table: Node = _find_ui_node(mission, "contract_table_ui.gd")
	if table == null:
		printerr("P5_CAPTURE FAILED contract_table: no contract_table_ui.gd CanvasLayer")
		failures += 1
	else:
		await _save("contract_table", {
			"table": Rect2(0.05, 0.12, 0.9, 0.62),
			"legend": Rect2(0.55, 0.78, 0.42, 0.18),
		}, [_hud_sidecar(hud), "pose=contract_table guildhall Novice Solo", "staged=set_den_selected_map('guildhall')"])
	_free_ui(mission, "contract_table_ui.gd")
	await _wait(8)


func _shot_prep() -> void:
	var mp: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	mp.size = Vector2(shot_w, shot_h)
	root.add_child(mp)
	await _wait(6)
	mp.call("open_prep", "guildhall", 1, "Solo", 0, false)
	await _wait(120)
	var cam: Camera3D = mp.find_child("MissionLobbyCamera", true, false) as Camera3D
	await _save("prep", {
		"cards": Rect2(0.04, 0.14, 0.56, 0.60),
		"stage": Rect2(0.60, 0.06, 0.39, 0.88),
		"prompt": Rect2(0.34, 0.72, 0.32, 0.20),
	}, [_cam_sidecar(cam), "pose=prep guildhall contract1 Solo", "staged=mission_prep_ui.open_prep"])
	mp.queue_free()
	await _wait(6)


func _shot_safe_room(mission: Node3D) -> void:
	var hud: Node = mission.get("hud") as Node
	var dressing: Node = mission.get_node_or_null("SafeRoomDressing")
	if dressing == null:
		for n: Node in mission.find_children("*", "Node3D", true, false):
			if str(n.name) == "SafeRoomDressing":
				dressing = n
				break
	var lantern: Node = dressing.get_node_or_null("SafeRoomLanternStation") if dressing != null else null
	if lantern != null and lantern.has_method("set_lit"):
		lantern.call("set_lit", true, false)
	var cam: Camera3D = _aim_player(mission, SAFE_ROOM_EYE, SAFE_ROOM_TARGET)
	await _wait(24)
	await _save("safe_room", {
		"gem": Rect2(0.455, 0.855, 0.09, 0.14),
		"lantern": Rect2(0.15, 0.35, 0.30, 0.45),
		"portal": Rect2(0.45, 0.30, 0.30, 0.55),
		"full": Rect2(0.0, 0.0, 1.0, 1.0),
	}, [_cam_sidecar(cam), "pose=safe_room authored spawn eye", "lantern_lit=%s" % str(bool(lantern.get("lit")) if lantern != null else false)] + _hud_sidecar(hud))


## Freeze the HUD after its last live update so the staged prompt/ring survives
## the still. Recorded in every sidecar that uses it.
func _stage_hud(hud: Node) -> void:
	if hud != null and hud.has_method("set_process"):
		hud.set_process(false)


func _shot_crank(mission: Node3D) -> void:
	var hud: Node = mission.get("hud") as Node
	var cam: Camera3D = _aim_player(mission, SAFE_ROOM_EYE, SAFE_ROOM_TARGET)
	await _wait(16)
	_stage_hud(hud)
	# KF17: the gem is fully concealed while cranking on the roof. Staged after
	# the HUD is frozen (the live light probe would immediately overwrite it).
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("player_light_visibility", 0.0)
	if hud != null:
		hud.call("apply_light_gem_state", 0.0, Vector3(-0.62, -0.58, 0.53), 0.0)
		var ret: Variant = hud.get("_reticle_draw")
		if ret != null:
			ret.set("mode", "zipwire")
			ret.set("crank_active", true)
			ret.set("crank_progress", 0.62)
			ret.call("queue_redraw")
		var crank_lbl: Variant = hud.get("_crank_prompt_lbl")
		if crank_lbl is Label:
			(crank_lbl as Label).visible = true
		var prompt: Variant = hud.get("_prompt_keycap")
		if prompt is Control:
			(prompt as Control).visible = false
		var prompt_lbl: Variant = hud.get("interact_lbl")
		if prompt_lbl is Label:
			(prompt_lbl as Label).text = ""
	await _wait(4)
	await _save("crank", {
		"gem": Rect2(0.455, 0.855, 0.09, 0.14),
		"ring": Rect2(0.42, 0.40, 0.16, 0.22),
		"prompt": Rect2(0.34, 0.50, 0.32, 0.08),
	}, [_cam_sidecar(cam), "pose=safe_room (HUD staging only)", "staged=hud.set_process(false); reticle crank 0.62 + CRANK label; gem concealed (amount 0)"] + _hud_sidecar(hud))


func _shot_doors(mission: Node3D) -> void:
	var hud: Node = mission.get("hud") as Node
	var cam: Camera3D = _aim_player(mission, SAFE_ROOM_EYE, SAFE_ROOM_TARGET)
	await _wait(12)
	_stage_hud(hud)
	if hud != null:
		var crank_lbl: Variant = hud.get("_crank_prompt_lbl")
		if crank_lbl is Label:
			(crank_lbl as Label).visible = false
		var ret: Variant = hud.get("_reticle_draw")
		if ret != null:
			ret.set("mode", "blackjack")
			ret.set("crank_active", false)
			ret.set("crank_progress", 0.0)
			ret.call("queue_redraw")
		hud.call("set_steal_prompt", "[F] Open Door")
		hud.call("_set_secondary_prompt", "[F] [HOLD] LOCK")
	await _wait(4)
	await _save("doors", {
		"prompt": Rect2(0.36, 0.52, 0.28, 0.05),
		"prompt_secondary": Rect2(0.36, 0.55, 0.28, 0.05),
	}, [_cam_sidecar(cam), "pose=safe_room (HUD staging only)", "staged=hud.set_steal_prompt('[F] Open Door') + _set_secondary_prompt('[F] [HOLD] LOCK')"] + _hud_sidecar(hud))


func _shot_key(mission: Node3D) -> void:
	var hud: Node = mission.get("hud") as Node
	var gs: Node = root.get_node_or_null("/root/GameState")
	var cam: Camera3D = _aim_player(mission, SAFE_ROOM_EYE, SAFE_ROOM_TARGET)
	await _wait(12)
	_stage_hud(hud)
	if gs != null and gs.has_method("add_stolen_key"):
		gs.call("add_stolen_key", "key_guildhall")
	if hud != null:
		hud.call("_update_key_row", false)
		hud.call("set_steal_prompt", "")
		hud.call("_set_secondary_prompt", "")
	await _wait(4)
	await _save("key", {
		"key_row": Rect2(0.012, 0.855, 0.27, 0.07),
		"hotbar": Rect2(0.012, 0.79, 0.26, 0.20),
	}, [_cam_sidecar(cam), "pose=safe_room (HUD staging only)", "staged=GameState.add_stolen_key('key_guildhall') + _update_key_row(false)"] + _hud_sidecar(hud))


func _shot_pause(mission: Node3D) -> void:
	var hud: Node = mission.get("hud") as Node
	var cam: Camera3D = _aim_player(mission, FOYER_EYE, FOYER_TARGET)
	await _wait(20)
	if _wants("pause_backdrop"):
		await _save("pause_backdrop", {
			"world": Rect2(0.20, 0.15, 0.60, 0.55),
			"hud_gem": Rect2(0.455, 0.855, 0.09, 0.14),
		}, [_cam_sidecar(cam), "pose=upper_foyer (no modal)", "pair=pause"] + _hud_sidecar(hud))
	if not _wants("pause"):
		return
	if hud == null or not hud.has_method("toggle_pause"):
		printerr("P5_CAPTURE FAILED pause: hud.toggle_pause missing")
		failures += 1
		return
	hud.call("set_steal_prompt", "")
	hud.call("_set_secondary_prompt", "")
	hud.call("toggle_pause")
	await _wait(18)
	if not paused:
		printerr("P5_CAPTURE FAILED pause: toggle_pause() did not pause the tree")
		failures += 1
		return
	await _save("pause", {
		"world": Rect2(0.20, 0.15, 0.60, 0.55),
		"modal": Rect2(0.28, 0.22, 0.44, 0.56),
		"footer": Rect2(0.25, 0.84, 0.50, 0.10),
	}, [_cam_sidecar(cam), "pose=upper_foyer (paused)", "pair=pause_backdrop"] + _hud_sidecar(hud))
	hud.call("toggle_pause")
	await _wait(8)


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

func _run() -> void:
	if OS.has_environment("P5_OUT"):
		out_dir = OS.get_environment("P5_OUT")
	if OS.has_environment("P5_TAG"):
		tag = OS.get_environment("P5_TAG")
	if OS.has_environment("P5_RUN_ID"):
		run_id = OS.get_environment("P5_RUN_ID")
	if run_id == "":
		run_id = _stamp()
	if OS.has_environment("P5_ONLY"):
		only = OS.get_environment("P5_ONLY").split(",", false)
		for requested: String in only:
			if not SHOTS.has(requested):
				printerr("P5_CAPTURE FAIL unknown shot=%s known=%s" % [requested, ",".join(SHOTS)])
				print("P5_CAPTURE_DONE run_id=%s captures=0 failures=1 out=%s" % [run_id, out_dir])
				quit(2)
				return
	match OS.get_environment("P5_SIZE"):
		"720":
			sizes = [Vector2i(1280, 720)]
		"1080":
			sizes = [Vector2i(1920, 1080)]
		_:
			sizes = [Vector2i(1280, 720), Vector2i(1920, 1080)]
	if out_dir == OUT_DEFAULT:
		out_dir = OUT_DEFAULT + "/" + run_id
	DirAccess.make_dir_recursive_absolute(out_dir)
	var gs: Node = root.get_node_or_null("/root/GameState")
	var save: Node = root.get_node_or_null("/root/SaveSystem")
	if gs != null:
		gs.set("difficulty", 1)
		gs.set("thief_id", "spider")
	if save != null and OS.has_environment("P5_SEED"):
		var data: Dictionary = save.get("data") as Dictionary
		if data != null:
			data["level"] = 4
			data["xp"] = 94
			data["currency"] = 26275
	print("P5_CAPTURE_START run_id=%s out=%s shots=%s sizes=%s" % [
		run_id, out_dir, ",".join(SHOTS), str(sizes)])
	for size: Vector2i in sizes:
		shot_w = size.x
		shot_h = size.y
		root.size = size
		await _wait(6)
		print("P5_CAPTURE_SIZE %dx%d" % [shot_w, shot_h])

		if _wants("startscreen"):
			await _shot_startscreen()

		# Den surface: den_hud -> wardrobe -> ledger -> contract_table.
		if _wants("den_hud") or _wants("wardrobe") or _wants("ledger") or _wants("ledger_market") or _wants("contract_table"):
			var den: Node3D = await _mission("thieves_den", 1)
			if den == null:
				failures += 1
			else:
				if _wants("den_hud"):
					await _shot_den(den)
				if _wants("wardrobe"):
					await _shot_wardrobe(den)
				if _wants("ledger") or _wants("ledger_market"):
					await _shot_ledger(den)
				if _wants("contract_table"):
					await _shot_contract_table(den)
				await _free_mission(den)

		if _wants("prep"):
			await _shot_prep()

		# Guildhall surface: briefing -> safe_room -> crank -> doors -> key ->
		# pause (pause last: it ends with the tree resumed).
		var guildhall: Array[String] = ["briefing", "safe_room", "crank", "doors", "key", "pause_backdrop", "pause"]
		var need_gh: bool = false
		for s: String in guildhall:
			if _wants(s):
				need_gh = true
				break
		if need_gh:
			var gh: Node3D = await _mission("guildhall", 2, true, "Mission.Guildhall.LootTheRoom")
			if gh == null:
				failures += 1
			else:
				var hud: Node = gh.get("hud") as Node
				if _wants("briefing"):
					var letter_seen: bool = false
					for _i: int in range(300):
						if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
							letter_seen = true
							break
						await process_frame
					if not letter_seen:
						printerr("P5_CAPTURE FAILED briefing: letter never opened")
						failures += 1
					else:
						await _wait(24)
						await _save("briefing", {
							"paper": Rect2(0.285, 0.185, 0.43, 0.62),
							"paper_text": Rect2(0.30, 0.28, 0.38, 0.45),
							"world": Rect2(0.0, 0.0, 0.28, 1.0),
						}, [_hud_sidecar(hud), "pose=briefing letter over the live safe room"])
				if hud != null and hud.has_method("_close_mission_letter"):
					hud.call("_close_mission_letter")
					await _wait(20)
				if _wants("safe_room"):
					await _shot_safe_room(gh)
				if _wants("crank"):
					await _shot_crank(gh)
				if _wants("doors"):
					await _shot_doors(gh)
				if _wants("key"):
					await _shot_key(gh)
				if _wants("pause") or _wants("pause_backdrop"):
					await _shot_pause(gh)
				await _free_mission(gh)

	print("P5_CAPTURE_DONE run_id=%s captures=%d failures=%d out=%s" % [
		run_id, captures, failures, out_dir])
	quit(0 if failures == 0 else 1)
