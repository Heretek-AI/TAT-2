extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(640, 360)
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	root.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)
	var scene_root := Node3D.new()
	vp.add_child(scene_root)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.0, 0.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 8.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	we.environment = e
	scene_root.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 3)
	cam.current = true
	scene_root.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.6, 0.6)
	bm.material = mat
	mi.mesh = bm
	scene_root.add_child(mi)
	for _i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("/tmp/opencode/probe_ambient.png")
	print("AMBIENT PROBE saved center=", img.get_pixel(320, 180), " corner=", img.get_pixel(10, 10))
	quit()
