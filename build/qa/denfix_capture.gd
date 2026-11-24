extends SceneTree
## Den-only P0 capture matrix (FIX_SPEC). Four KF-aligned views at 1280x720.
## Run native Vulkan on DISPLAY=:95 with TAT2_TEX_CAP=512.
## OUT_DIR is overridable with TAT2_DEN_CAPTURE_DIR for before/after pairs.

const DEFAULT_OUT: String = "/tmp/opencode/denfix"
var out_dir: String = DEFAULT_OUT


func _init() -> void:
	call_deferred("_run")


func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null and not img.is_empty():
		var err: int = img.save_png(out_dir + "/" + fname)
		print("QA CAPTURE: ", fname, " err=", err, " ", img.get_width(), "x", img.get_height())
	else:
		printerr("QA CAPTURE FAILED: ", fname)


func _shot(cam: Camera3D, fname: String) -> void:
	await _wait(10)
	await _save(fname)


func _light_report(den: Node) -> void:
	var idx: int = 0
	for n: Node in den.find_children("*", "Light3D", true, false):
		var l: Light3D = n as Light3D
		var extra: String = ""
		if l is SpotLight3D:
			var sp: SpotLight3D = l as SpotLight3D
			extra = " spot_range=%.2f angle=%.2f att=%.2f" % [sp.spot_range, sp.spot_angle, sp.spot_attenuation]
		elif l is OmniLight3D:
			var om: OmniLight3D = l as OmniLight3D
			extra = " omni_range=%.2f att=%.2f" % [om.omni_range, om.omni_attenuation]
		print("DEN_LIGHT ", idx, " name=", l.name, " class=", l.get_class(), " energy=%.4f" % l.light_energy, " color=", l.light_color, " shadow=", l.shadow_enabled, extra)
		idx += 1
	var fills: float = 0.0
	for fl: Node in get_nodes_in_group("den_hand_fills"):
		if fl is Light3D and den.is_ancestor_of(fl):
			fills += (fl as Light3D).light_energy
	print("DEN_FILL_SUM=%.3f" % fills)
	var flames: int = 0
	for n2: Node in den.find_children("CandleFlame*", "", true, false):
		flames += 1
	print("DEN_CANDLE_FLAME_NODES=", flames)
	var mmi: int = 0
	var candle_mmi: int = 0
	for n3: Node in den.find_children("LevelNiagara_*", "", true, false):
		mmi += 1
		if "Candelabra" in str(n3.name):
			candle_mmi += 1
			var inst: MultiMeshInstance3D = n3 as MultiMeshInstance3D
			if inst != null and inst.multimesh != null:
				print("DEN_CANDLE_NIAGARA ", n3.name, " instances=", inst.multimesh.instance_count)
	print("DEN_NIAGARA_NODES=", mmi, " candle_systems=", candle_mmi)
	var env: Environment = null
	for ch: Node in den.get_children():
		if ch is WorldEnvironment and (ch as WorldEnvironment).environment != null:
			env = (ch as WorldEnvironment).environment
			break
	if env != null:
		print("DEN_ENV tonemap=", env.tonemap_mode, " exposure=%.3f bright=%.3f sat=%.3f ambient=%.3f/%s" % [env.tonemap_exposure, env.adjustment_brightness, env.adjustment_saturation, env.ambient_light_energy, env.ambient_light_color])
		print("DEN_GLOW enabled=", env.glow_enabled, " intensity=%.3f bloom=%.3f threshold=%.3f hdr=%.3f" % [env.glow_intensity, env.glow_bloom, env.glow_hdr_threshold, env.glow_hdr_scale])
		print("DEN_FOG density=%.5f energy=%.3f color=%s" % [env.fog_density, env.fog_light_energy, env.fog_light_color])
	var back: Node = den.find_child("DenWindowBacklight", true, false)
	print("DEN_WINDOW_BACKLIGHT_NODE=", back != null)
	var plane: int = 0
	for n4: Node in den.find_children("*", "MultiMeshInstance3D", true, false):
		var mi: MultiMeshInstance3D = n4 as MultiMeshInstance3D
		if mi != null and str(mi.get_meta("ue_mesh", "")).find("SM_Shape_Plane") >= 0 and mi.is_visible_in_tree():
			plane += 1
			print("DEN_VISIBLE_PLANE ", mi.name, " visible=", mi.visible, " aabb=", mi.get_aabb())
	print("DEN_VISIBLE_SHAPE_PLANES=", plane)


func _run() -> void:
	if OS.has_environment("TAT2_DEN_CAPTURE_DIR"):
		out_dir = OS.get_environment("TAT2_DEN_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	await _wait(3)
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("active_contract_order", 1)
		gs.set("active_map_id", "thieves_den")
	var mission_scene: PackedScene = load("res://scenes/mission.tscn") as PackedScene
	if mission_scene == null:
		printerr("DENFIX_FATAL: mission.tscn missing")
		quit(1)
		return
	var den: Node3D = mission_scene.instantiate() as Node3D
	root.add_child(den)
	var waited: int = 0
	while (den.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and waited < 1200:
		await process_frame
		waited += 1
	print("DENFIX_READY waited=", waited)
	await _wait(30)
	var hud: Node = den.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(8)
	# P0.1: capture the 3D only. The Den look-at card ("CONSTABLES'
	# GUILDHALL / Prepare for Mission") is player-aim driven and otherwise sits
	# in every shot, skewing the histograms. Hide the HUD for clean frames.
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	# KF10 reference state: the highlighted 3D token is Constables' Guildhall
	# (KEYFRAME_INDEX.md). The port defaults to Old Manor, so select Guildhall
	# before the shots and log it for the ROI gate.
	if den.has_method("set_den_selected_map"):
		den.call("set_den_selected_map", "guildhall")
		await _wait(8)
	print("DEN_SELECTED_MAP=", str(den.get("_den_selected_map_id")))
	await _light_report(den)

	var cam: Camera3D = Camera3D.new()
	cam.far = 400.0
	den.add_child(cam)
	cam.current = true

	# KF02: entry/wide - arched window left, rolltop desk + map table foreground.
	cam.fov = 74.0
	cam.global_position = Vector3(4.6, 41.85, 272.1)
	cam.look_at(Vector3(-3.2, 41.35, 269.6), Vector3.UP)
	await _shot(cam, "KF02_wide_entry.png")

	# KF06: arched window + wanted posters + telescope.
	cam.fov = 62.0
	cam.global_position = Vector3(-1.4, 41.7, 271.4)
	cam.look_at(Vector3(-6.1, 41.55, 270.85), Vector3.UP)
	await _shot(cam, "KF06_window.png")

	# KF09: candelabra + phonograph warm pool.
	cam.fov = 62.0
	cam.global_position = Vector3(3.3, 41.65, 273.4)
	cam.look_at(Vector3(5.8, 41.15, 275.45), Vector3.UP)
	await _shot(cam, "KF09_candles.png")

	# KF10: map table, banker lamp, parchment, bust (KF10 framing).
	cam.fov = 58.0
	cam.global_position = Vector3(2.7, 42.35, 270.1)
	cam.look_at(Vector3(2.9, 41.05, 267.9), Vector3.UP)
	await _shot(cam, "KF10_map_table.png")

	print("DENFIX_DONE")
	den.queue_free()
	await _wait(4)
	quit(0)
