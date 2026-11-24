extends SceneTree

func _initialize() -> void:
	var vfx_scr: GDScript = load("res://src/core/vfx_manager.gd") as GDScript
	var vfx: Object = vfx_scr.new()
	var root3d: Node3D = Node3D.new()
	get_root().add_child(root3d)
	await process_frame
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.45, 0.55)
	e.ambient_light_energy = 0.7
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_hdr_threshold = 1.0
	env.environment = e
	root3d.add_child(env)
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0.0, 1.6, 7.0)
	root3d.add_child(cam)
	cam.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
	cam.current = true
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	key.light_energy = 0.8
	root3d.add_child(key)
	vfx.call("spawn_smoke_plume", root3d, Vector3(-2.8, 0.6, 0.0), Vector3(1.6, 1.0, 1.6), 8.0)
	vfx.call("spawn_foyer_security_beam", root3d, Vector3(-1.2, 2.0, -1.5), Vector3(3.2, 2.0, -1.5), 0.7, 0.0)
	vfx.call("spawn_arcane_ward", root3d, Vector3(3.0, 0.0, -2.0), 0.0, 2.2, 2.6, 0.0)
	vfx.call("spawn_crimson_alarm", root3d, Vector3(0.6, 3.0, 1.5), Vector3(0.6, 0.0, -0.5), 8.0)
	for i: int in range(40):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img != null and not img.is_empty():
		var err: int = img.save_png("res://probe_vfx.png")
		print("VFX_PNG err=", err, " size=", img.get_width(), "x", img.get_height())
	print("VFX_PROBE_DONE")
	quit(0)
