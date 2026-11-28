extends SceneTree

var OUT_DIR: String = ProjectSettings.globalize_path("res://../build/qa").simplify_path()

func _init() -> void:
	call_deferred("_run")

func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + "/" + fname)
		print("CARD CAP ", fname)

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
		for _i in range(6): await process_frame
	var player: Node3D = mission.get("player") as Node3D
	player.global_position = Vector3(27.0, 28.0, -50.0)
	player.rotation = Vector3(0.0, 0.0, 0.0)
	for _i in range(10): await process_frame
	var hidden: int = 0
	for n: Node in mission.find_children("RectLightQuad*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).visible = false
		hidden += 1
	print("CARD hidden=", hidden)
	for _i in range(6): await process_frame
	await _save("vf_foyer_no_rectcards.png")
	print("CARD DONE")
	quit(0)
