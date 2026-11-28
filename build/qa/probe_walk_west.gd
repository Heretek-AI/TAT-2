extends SceneTree

## QA-only probe (gitignored build/qa). Loads Guildhall, applies the same
## +260 deg west yaw as the 1,890 px mouse turn, then holds move_forward and
## saves a frame every 2 s. Does not modify any project file.

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
	print("PROBE change_scene err=", change_scene_to_file("res://scenes/mission.tscn"))

	var waited: float = 0.0
	var player: Node = null
	while waited < 150.0:
		await process_frame
		waited += 1.0 / maxf(Engine.get_frames_per_second(), 1.0)
		player = get_first_node_in_group("player")
		if player != null:
			break
	if player == null:
		print("PROBE FAIL: no player")
		quit(1)
		return
	print("PROBE player after ", snappedf(waited, 0.1), " s")

	var settle: float = 0.0
	while settle < 12.0:
		await process_frame
		settle += 1.0 / maxf(Engine.get_frames_per_second(), 1.0)

	var p: Node3D = player as Node3D
	# Spawn yaw is -175 deg; the reference recipe turned 1,890 px left
	# (0.0024 rad/px) = +260 deg, landing at +85 deg (compass W).
	p.rotation.y = deg_to_rad(-175.0 + 260.0)
	print("PROBE start pos=", p.global_position, " yaw_deg=", rad_to_deg(p.rotation.y),
		" fps=", Engine.get_frames_per_second())

	Input.action_press("move_forward")
	var start_ms: int = Time.get_ticks_msec()
	var next_capture: int = 2000
	var last: Vector3 = p.global_position
	while Time.get_ticks_msec() - start_ms < 16000:
		await process_frame
		var elapsed: int = Time.get_ticks_msec() - start_ms
		if elapsed >= next_capture:
			var pos: Vector3 = p.global_position
			print("PROBE t=", elapsed / 1000.0, " pos=", pos,
				" step_since_last=", pos.distance_to(last),
				" fps=", Engine.get_frames_per_second())
			last = pos
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path("res://../build/qa/").simplify_path() + "/probe_west_t%02d.png" % (next_capture / 1000))
			next_capture += 2000
	Input.action_release("move_forward")
	print("PROBE end pos=", p.global_position, " yaw_deg=", rad_to_deg(p.rotation.y))
	quit(0)
