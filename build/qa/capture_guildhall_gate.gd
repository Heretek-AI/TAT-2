extends SceneTree

var OUT_DIR: String = ProjectSettings.globalize_path("res://../build/qa").simplify_path()

func _init() -> void:
	call_deferred("_run")

func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + "/" + fname)
		print("GATE CAP ", fname)

func _shoot(cam: Camera3D, pos: Vector3, target: Vector3, fname: String) -> void:
	cam.position = pos
	cam.look_at(target, Vector3.UP)
	cam.current = true
	for _i in range(8): await process_frame
	await _save(fname)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null: gs.set("active_contract_order", 4)
	var mission: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission)
	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and waited < 1200:
		await process_frame
		waited += 1
	for _i in range(20): await process_frame
	if mission.get("hud") != null and mission.hud.has_method("is_mission_letter_open") and mission.hud.call("is_mission_letter_open"):
		mission.hud.call("_close_mission_letter")
		for _i in range(4): await process_frame
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 500.0
	mission.add_child(cam)
	await _shoot(cam, Vector3(10.0, 20.0, 100.0), Vector3(10.0, 22.0, 88.0), "vf_guildhall_gate.png")
	await _shoot(cam, Vector3(10.0, 24.0, 62.0), Vector3(10.0, 25.3, 48.7), "vf_guildhall_sign.png")
	print("GATE DONE")
	quit(0)
