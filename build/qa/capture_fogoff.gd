extends SceneTree

## QA-only diagnostic harness (lives in gitignored build/qa).
## Loads the Guildhall mission with HEAD code, then forces
## Environment.fog_sky_affect = 0 at runtime (HEAD leaves it at the engine
## default 1.0, which replaces the sky with the near-black preset fog colour)
## and renders a free camera aimed at the authored moon direction.
## It does not modify any project file.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		print("DIAG FAIL: no GameState autoload")
		quit(1)
		return
	gs.set("active_contract_order", 4)
	gs.set("active_map_id", "guildhall")
	var err: int = change_scene_to_file("res://scenes/mission.tscn")
	print("DIAG change_scene err=", err)

	var waited: float = 0.0
	var player: Node = null
	while waited < 150.0:
		await process_frame
		waited += 1.0 / maxf(Engine.get_frames_per_second(), 1.0)
		player = get_first_node_in_group("player")
		if player != null:
			break
	print("DIAG player after ", snappedf(waited, 0.1), " s: ", player != null)
	if player == null:
		quit(1)
		return

	# Let loading screens/streaming settle like the screenshot recipe does.
	var settle: float = 0.0
	while settle < 12.0:
		await process_frame
		settle += 1.0 / maxf(Engine.get_frames_per_second(), 1.0)

	var scene: Node = current_scene
	var we: WorldEnvironment = null
	for child in scene.get_children():
		if child is WorldEnvironment:
			we = child as WorldEnvironment
			break
	if we == null or we.environment == null:
		print("DIAG FAIL: no WorldEnvironment")
		quit(1)
		return
	var env: Environment = we.environment
	print("DIAG env bg=", env.background_mode, " sky=", env.sky != null,
		" fog=", env.fog_enabled, " fog_density=", env.fog_density,
		" fog_sky_affect_before=", env.fog_sky_affect)
	env.fog_sky_affect = 0.0

	var cam := Camera3D.new()
	cam.fov = 85.0
	cam.rotation_degrees = Vector3(30.0, 50.0, 0.0)
	scene.add_child(cam)
	cam.current = true

	cam.global_position = Vector3(0.0, 300.0, 0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("/home/john/Projects/TAT-2/build/qa/sky_moon_after_moon_fogoff.png")

	cam.global_position = Vector3(107.0, 27.0, -5.0)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	img = root.get_texture().get_image()
	img.save_png("/home/john/Projects/TAT-2/build/qa/sky_moon_after_balcony_fogoff.png")
	print("DIAG saved ", img.get_width(), "x", img.get_height(),
		" fog_sky_affect_after=", env.fog_sky_affect)
	quit(0)
