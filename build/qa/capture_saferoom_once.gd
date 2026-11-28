extends SceneTree
var OUT_DIR: String = ProjectSettings.globalize_path("res://../build/qa").simplify_path()
func _init() -> void: call_deferred("_run")
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
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + "/vf_saferoom_postfill.png")
		print("SAFE1 CAP")
	print("SAFE1 DONE")
	quit(0)
