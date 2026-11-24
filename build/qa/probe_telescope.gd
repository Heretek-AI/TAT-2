extends SceneTree

const OUT_DIR: String = "/home/john/Projects/TAT-2/build/qa"

func _init() -> void:
	call_deferred("_run")

func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + "/" + fname)
		print("TEL CAP ", fname)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("active_contract_order", 1)
	var mission: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission)
	var waited: int = 0
	while (mission.get("player") == null or mission.get("_is_thieves_den") != true) and waited < 1200:
		await process_frame
		waited += 1
	for _i in range(20): await process_frame
	print("TEL waited=", waited, " den=", mission.get("_is_thieves_den"), " vista=", mission.get_node_or_null("DenWindowVista") != null)
	var cam0: Camera3D = root.get_viewport().get_camera_3d()
	print("TEL before cam=", cam0.name if cam0 else null, " fov=", cam0.fov if cam0 else -1)
	mission.call("toggle_telescope_ponder")
	for _i in range(10): await process_frame
	var cam1: Camera3D = root.get_viewport().get_camera_3d()
	var pcam: Camera3D = mission.get("_ponder_cam") as Camera3D
	print("TEL after active=", mission.get("_ponder_active"), " current=", pcam.current if pcam else null, " view_cam=", cam1.name if cam1 else null, " fov=", cam1.fov if cam1 else -1, " pos=", cam1.global_position if cam1 else null)
	await _save("vf_telescope.png")
	print("TEL DONE")
	quit(0)
