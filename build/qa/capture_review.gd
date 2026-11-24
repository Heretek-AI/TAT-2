extends SceneTree
## Post-review visual probes: Guildhall POI beams/doors, ornate gate, loot.

const OUT_DIR: String = "/home/john/Projects/TAT-2/build/qa/review"

func _initialize() -> void:
	call_deferred("_run")

func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame

func _shot(cam: Camera3D, name: String) -> void:
	await _wait(8)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(OUT_DIR + "/" + name)
		print("REVIEW SHOT: ", name, " cam=", cam.global_position)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.size = Vector2i(1280, 720)
	await _wait(3)
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("state", "playing")
		gs.set("thief_id", "spider")
		gs.set("active_contract_order", 4)
		gs.set("active_map_id", "guildhall")
	var mission: Node3D = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(mission)
	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and waited < 1200:
		await process_frame
		waited += 1
	await _wait(30)
	var hud: Node = mission.get("hud") as Node
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	var cam: Camera3D = Camera3D.new()
	cam.fov = 70.0
	cam.far = 300.0
	mission.add_child(cam)
	cam.current = true
	# POI grand hall / lounge beams and doors.
	cam.global_position = Vector3(50.0, 27.0, 8.0)
	cam.look_at(Vector3(55.0, 27.0, -8.0), Vector3.UP)
	await _shot(cam, "poi_lounge.png")
	cam.global_position = Vector3(55.0, 27.0, -2.0)
	cam.look_at(Vector3(60.0, 27.0, -10.0), Vector3.UP)
	await _shot(cam, "poi_lounge2.png")
	# Ornate gate at (80.3, 18.5, 15.7).
	cam.global_position = Vector3(80.0, 20.0, 30.0)
	cam.look_at(Vector3(80.3, 19.5, 15.7), Vector3.UP)
	await _shot(cam, "ornate_gate.png")
	# Loot grounding sample near the POI display.
	cam.global_position = Vector3(53.0, 27.0, 2.0)
	cam.look_at(Vector3(58.0, 25.0, -6.0), Vector3.UP)
	await _shot(cam, "poi_display.png")
	print("REVIEW DONE")
	quit(0)
