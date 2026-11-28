extends SceneTree
## Track C visual QA (gitignored): C1 NPR/SNN, C2 X-ray through-wall, C3 rain
## roof occlusion + lens drops + authored local fog. Run under Xvfb Vulkan.

var OUT_DIR: String = ProjectSettings.globalize_path("res://../build/qa").simplify_path()
const WeatherVisuals := preload("res://src/core/weather_visuals.gd")
const XrayOverlayScript := preload("res://src/core/xray_overlay.gd")
const OSERendererScript := preload("res://src/core/ose_renderer.gd")

var scene_root: Node3D
var cam: Camera3D
var env: WorldEnvironment
var sun: DirectionalLight3D


func _init() -> void:
	call_deferred("_run")


func _wait(n: int = 4) -> void:
	for _i: int in range(n):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null and not img.is_empty():
		var err: int = img.save_png(OUT_DIR + "/" + name)
		print("QA CAPTURE: ", name, " ", img.get_width(), "x", img.get_height(), " err=", err)
	else:
		printerr("QA CAPTURE FAILED: ", name)


func _reset_scene() -> void:
	if scene_root != null and is_instance_valid(scene_root):
		scene_root.queue_free()
		await _wait(2)
	scene_root = Node3D.new()
	root.add_child(scene_root)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.04, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.52, 0.65)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	scene_root.add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	scene_root.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 65.0
	cam.current = true
	scene_root.add_child(cam)


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.7
	return m


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _wait(2)

	# C2: opaque wall in front, X-ray target behind it.
	await _reset_scene()
	cam.position = Vector3(0, 1.6, 4.0)
	cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(3.4, 3.0, 0.25)
	wall.mesh = wall_mesh
	wall.position = Vector3(0, 1.5, 0)
	wall.material_override = _mat(Color(0.32, 0.30, 0.28))
	scene_root.add_child(wall)
	var target := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.45
	cap.height = 1.7
	target.mesh = cap
	target.position = Vector3(0, 1.05, -1.1)
	target.material_override = _mat(Color(0.45, 0.45, 0.45))
	scene_root.add_child(target)
	await _wait(6)
	await _shot("c2_xray_off.png")
	XrayOverlayScript.set_xray_highlight(target, true, "loot")
	await _wait(3)
	await _shot("c2_xray_loot.png")
	XrayOverlayScript.set_xray_highlight(target, false, "loot")
	XrayOverlayScript.set_xray_highlight(target, true, "guard")
	await _wait(3)
	await _shot("c2_xray_guard.png")
	XrayOverlayScript.set_xray_highlight(target, false, "guard")

	# C1: coloured geometry + camera post pass.
	await _reset_scene()
	cam.position = Vector3(4.5, 2.4, 5.0)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	for i: int in range(5):
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.2, 1.2, 1.2)
		box.mesh = bm
		box.position = Vector3(-3.0 + i * 1.5, 0.6, 0)
		box.material_override = _mat(Color(0.85, 0.35 + i * 0.08, 0.2))
		scene_root.add_child(box)
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(12, 0.2, 8)
	ground.mesh = gm
	ground.position = Vector3(0, -0.1, 0)
	ground.material_override = _mat(Color(0.16, 0.18, 0.2))
	scene_root.add_child(ground)
	var ose: Node = OSERendererScript.attach(cam) as Node
	await _wait(8)
	await _shot("c1_post_off.png")
	ose.call("set_npr", true)
	await _wait(4)
	await _shot("c1_post_npr.png")
	ose.call("set_npr", false)
	ose.call("set_snn", true, 0.65)
	await _wait(4)
	await _shot("c1_post_snn.png")
	ose.call("set_snn", false)

	# C3: roofed fixture + rain columns + lens overlay + authored fog.
	await _reset_scene()
	env.environment.volumetric_fog_enabled = true
	env.environment.volumetric_fog_density = 0.0
	cam.position = Vector3(0, 1.6, 0.2)
	cam.look_at(Vector3(0, 1.2, 6.0), Vector3.UP)
	var c3_ground := MeshInstance3D.new()
	var c3_gm := BoxMesh.new()
	c3_gm.size = Vector3(24, 0.2, 24)
	c3_ground.mesh = c3_gm
	c3_ground.position = Vector3(0, -0.1, 0)
	c3_ground.material_override = _mat(Color(0.2, 0.2, 0.22))
	scene_root.add_child(c3_ground)
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(6, 0.25, 6)
	roof.mesh = rm
	roof.position = Vector3(0, 3.0, 0)
	roof.material_override = _mat(Color(0.28, 0.24, 0.22))
	scene_root.add_child(roof)
	var roof_body := StaticBody3D.new()
	var roof_cs := CollisionShape3D.new()
	var roof_shape := BoxShape3D.new()
	roof_shape.size = Vector3(6, 0.25, 6)
	roof_cs.shape = roof_shape
	roof_body.add_child(roof_cs)
	roof_body.position = roof.position
	scene_root.add_child(roof_body)
	# Posts so the roof reads as a fixture.
	for px: float in [-2.8, 2.8]:
		for pz: float in [-2.8, 2.8]:
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.18, 3.0, 0.18)
			post.mesh = pm
			post.position = Vector3(px, 1.5, pz)
			post.material_override = _mat(Color(0.25, 0.2, 0.18))
			scene_root.add_child(post)
	var rain_preset: Dictionary = {"rain": {"enabled": true, "intensity": 1.0}}
	var rain: Node3D = WeatherVisuals.make_rain(scene_root, rain_preset) as Node3D
	var lens: CanvasLayer = WeatherVisuals.make_lens_rain(root, rain_preset) as CanvasLayer
	var target_node := Node3D.new()
	target_node.position = Vector3(0, 0.2, 0.2)
	scene_root.add_child(target_node)
	await physics_frame
	WeatherVisuals.update_rain_occlusion(rain, target_node)
	await _wait(10)
	await _shot("c3_rain_roof_inside.png")
	# Move outside the roof; rain columns are visible.
	cam.position = Vector3(0, 1.6, 6.5)
	cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
	target_node.position = Vector3(0, 0.2, 6.5)
	rain.set_meta("_next_probe_ms", 0)
	WeatherVisuals.update_rain_occlusion(rain, target_node)
	await _wait(10)
	await _shot("c3_rain_outside.png")
	if lens != null:
		lens.queue_free()
	if rain != null:
		rain.queue_free()
	# Authored local fog volume.
	env.environment.volumetric_fog_density = 0.0
	var fog := FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog.size = Vector3(8, 4, 8)
	fog.position = Vector3(0, 1.5, -4)
	var fm := FogMaterial.new()
	fm.density = 1.0
	fm.albedo = Color(0.5, 0.5, 0.5, 1.0)
	fm.emission = Color(0.034, 0.028, 0.04, 1.0)
	fm.edge_fade = 0.25
	fog.material = fm
	scene_root.add_child(fog)
	# A lit backdrop makes the authored haze readable instead of fog-on-black.
	var backdrop := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(20, 8, 0.3)
	backdrop.mesh = bm
	backdrop.position = Vector3(0, 2.5, -12)
	backdrop.material_override = _mat(Color(0.55, 0.58, 0.62))
	scene_root.add_child(backdrop)
	var c3_light := OmniLight3D.new()
	c3_light.position = Vector3(0, 4.0, -6)
	c3_light.light_energy = 3.0
	c3_light.omni_range = 18.0
	scene_root.add_child(c3_light)
	cam.position = Vector3(0, 1.6, 4.0)
	cam.look_at(Vector3(0, 1.5, -8), Vector3.UP)
	await _wait(8)
	await _shot("c3_fog_volume.png")

	print("TRACK_C_CAPTURE DONE")
	quit(0)
