extends SceneTree
## Live Vulkan Forward+ visual QA capture script (build/qa/capture_vf.gd, gitignored).

var OUT_DIR: String = ProjectSettings.globalize_path("res://../build/qa").simplify_path()


func _init() -> void:
	call_deferred("_run_captures")


func _wait_frames(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _save_shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null and not img.is_empty():
		var path: String = OUT_DIR + "/" + fname
		var err: int = img.save_png(path)
		print("QA CAPTURE: ", fname, " size=", img.get_width(), "x", img.get_height(), " err=", err)
	else:
		printerr("QA CAPTURE FAILED (empty image): ", fname)


func _run_captures() -> void:
	root.size = Vector2i(1280, 720)
	await _wait_frames(3)
	var gs: Node = root.get_node_or_null("/root/GameState")

	# 1. Startscreen (full-rect CineCameraActor_0 + BeautifulCorner_Startscreen_P)
	var mm: Control = (load("res://src/ui/main_menu.gd") as GDScript).new() as Control
	mm.size = Vector2(1280, 720)
	root.add_child(mm)
	await _wait_frames(60)
	await _save_shot("vf_startscreen.png")

	# 2. Settings UI (teal theme + grouped cards over Startscreen)
	var st: CanvasLayer = (load("res://src/ui/settings_ui.gd") as GDScript).new() as CanvasLayer
	root.add_child(st)
	await _wait_frames(6)
	await _save_shot("vf_settings.png")
	st.queue_free()
	mm.queue_free()
	await _wait_frames(4)

	# 3. Mission Prep UI (Guildhall Vault Heist — real artwork + Warburg Effigy icon + 11 rows)
	var mp: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	mp.size = Vector2(1280, 720)
	root.add_child(mp)
	await _wait_frames(4)
	mp.call("open_prep", "guildhall", 1, "Solo", 0)
	await _wait_frames(12)
	await _save_shot("vf_mission_prep.png")
	mp.queue_free()
	await _wait_frames(4)

	# 4. Guildhall (OverrideMaterials, tat_glass.gdshader windows, CPD lights)
	if gs != null:
		gs.set("active_contract_order", 4)
	var gh: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(gh)
	var gh_wait: int = 0
	while (gh.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and gh_wait < 600:
		await process_frame
		gh_wait += 1
	await _wait_frames(35)
	if gh.get("hud") != null and gh.hud.has_method("is_mission_letter_open") and gh.hud.call("is_mission_letter_open"):
		gh.hud.call("_close_mission_letter")
		await _wait_frames(8)
	await _save_shot("vf_guildhall.png")
	# Also capture Guildhall exterior street/courtyard view
	var gh_cam: Camera3D = Camera3D.new()
	gh_cam.fov = 65.0
	gh_cam.position = Vector3(114.0, 21.0, -5.0)
	gh.add_child(gh_cam)
	gh_cam.current = true
	gh_cam.look_at(Vector3(70.0, 23.0, -20.0), Vector3.UP)
	await _wait_frames(8)
	await _save_shot("vf_guildhall_street.png")
	gh.queue_free()
	await _wait_frames(6)

	# 5. Old Manor (MI_GlassPanels_oldmanor, OverrideMaterials, CPD lights)
	if gs != null:
		gs.set("active_contract_order", 3)
	var om: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(om)
	var om_wait: int = 0
	while (om.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and om_wait < 600:
		await process_frame
		om_wait += 1
	await _wait_frames(35)
	if om.get("hud") != null and om.hud.has_method("is_mission_letter_open") and om.hud.call("is_mission_letter_open"):
		om.hud.call("_close_mission_letter")
		await _wait_frames(8)
	await _save_shot("vf_old_manor.png")
	om.queue_free()
	await _wait_frames(4)

	print("QA CAPTURE DONE")
	quit(0)
