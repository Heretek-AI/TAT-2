extends SceneTree

## QA-only probe (lives in gitignored build/qa). Loads Guildhall, then holds
## move_forward for 12 s and prints the player position each second. Does not
## modify any project file.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		print("PROBE FAIL: no GameState autoload")
		quit(1)
		return
	gs.set("active_contract_order", 4)
	gs.set("active_map_id", "guildhall")
	var err: int = change_scene_to_file("res://scenes/mission.tscn")
	print("PROBE change_scene err=", err)

	var waited: float = 0.0
	var player: Node = null
	while waited < 150.0:
		await process_frame
		waited += 1.0 / maxf(Engine.get_frames_per_second(), 1.0)
		player = get_first_node_in_group("player")
		if player != null:
			break
	print("PROBE player after ", snappedf(waited, 0.1), " s: ", player != null)
	if player == null:
		quit(1)
		return

	var settle: float = 0.0
	while settle < 12.0:
		await process_frame
		settle += 1.0 / maxf(Engine.get_frames_per_second(), 1.0)

	var p: Node3D = player as Node3D
	print("PROBE start pos=", p.global_position, " yaw_deg=", rad_to_deg(p.rotation.y))
	Input.action_press("move_forward")
	var t: float = 0.0
	var last: Vector3 = p.global_position
	while t < 12.0:
		await process_frame
		t += 1.0 / maxf(Engine.get_frames_per_second(), 1.0)
		if int(t) != int(t - 1.0 / maxf(Engine.get_frames_per_second(), 1.0)):
			var pos: Vector3 = p.global_position
			print("PROBE t=", int(t), " pos=", pos, " step=", pos.distance_to(last), " yaw_deg=", rad_to_deg(p.rotation.y))
			last = pos
	Input.action_release("move_forward")
	print("PROBE end pos=", p.global_position, " yaw_deg=", rad_to_deg(p.rotation.y))
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("/home/john/Projects/TAT-2/build/qa/probe_walk_end.png")
	print("PROBE saved probe_walk_end.png ", img.get_width(), "x", img.get_height())
	quit(0)
