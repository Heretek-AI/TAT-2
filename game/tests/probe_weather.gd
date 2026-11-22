extends SceneTree
## C3 weather probe: roof rain occlusion, lens drops, local fog volumes.

const WeatherVisuals := preload("res://src/core/weather_visuals.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var target := Node3D.new()
	target.position = Vector3(0, 0, 0)
	root.add_child(target)
	var rain_preset: Dictionary = {"rain": {"enabled": true, "intensity": 1.0}}
	var rain: Node3D = WeatherVisuals.make_rain(target, rain_preset) as Node3D
	var grid_ok: bool = rain != null and rain.get_child_count() == 16
	var outside_visible: bool = true
	if rain != null:
		for c: Node in rain.get_children():
			if c is GPUParticles3D and not (c as GPUParticles3D).visible:
				outside_visible = false

	# Roof directly overhead: every column ray hits it -> every column hidden.
	var roof := StaticBody3D.new()
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(70, 0.5, 70)
	rcs.shape = rbox
	roof.add_child(rcs)
	roof.position = Vector3(0, 5, 0)
	root.add_child(roof)
	await physics_frame
	WeatherVisuals.update_rain_occlusion(rain, target)
	var hidden_under_roof: int = -1
	if rain != null:
		hidden_under_roof = int(rain.get_meta("rain_columns_hidden", -1))
	var roof_ok: bool = grid_ok and hidden_under_roof == 16

	# Remove the roof and force the next probe: rain returns outside.
	root.remove_child(roof)
	roof.queue_free()
	await physics_frame
	rain.set_meta("_next_probe_ms", 0)
	WeatherVisuals.update_rain_occlusion(rain, target)
	var shown_after: int = int(rain.get_meta("rain_columns_shown", -1))
	var clear_sky_ok: bool = shown_after == 16

	# Lens drops only for rain presets.
	var lens: CanvasLayer = WeatherVisuals.make_lens_rain(root, rain_preset) as CanvasLayer
	var lens_ok: bool = lens != null and lens.get_child_count() == 1
	if lens_ok:
		var rect: ColorRect = lens.get_child(0) as ColorRect
		var lens_mat: ShaderMaterial = null
		if rect != null:
			lens_mat = rect.material as ShaderMaterial
		lens_ok = lens_mat != null and lens_mat.shader != null \
			and lens_mat.shader.resource_path.ends_with("tat_lens_rain.gdshader")
	var clear_lens: CanvasLayer = WeatherVisuals.make_lens_rain(root, {"rain": {"enabled": false, "intensity": 0.0}}) as CanvasLayer
	var clear_lens_ok: bool = clear_lens == null

	# Authored LocalVolumetric boxes -> FogVolume/FogMaterial.
	var ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ll)
	await process_frame
	var host := Node3D.new()
	root.add_child(host)
	var ctx: Dictionary = ll.call("_new_build_ctx", host, null, false) as Dictionary
	var trs: Array = [Transform3D(Basis().scaled(Vector3(20, 30, 40)), Vector3(1, 2, 3))]
	var built: int = int(ll.call("_build_fog_volumes", trs, ["/Game/Art/Environment/Weather/LocalVolumetricFog/MI_LocalVolumetricFog_Outside_Preset_A"], host, ctx))
	var fog_ok: bool = built == 1 and int(ctx.get("fog_volumes_built", 0)) == 1 and host.get_child_count() == 1
	if fog_ok:
		var fog: FogVolume = host.get_child(0) as FogVolume
		var fm: FogMaterial = null
		if fog != null:
			fm = fog.material as FogMaterial
		fog_ok = fog != null and fm != null and absf(fm.density - 1.0) < 0.001 \
			and fm.albedo.is_equal_approx(Color(0.5, 0.5, 0.5, 1.0))

	if not grid_ok or not outside_visible or not roof_ok or not clear_sky_ok or not lens_ok or not clear_lens_ok or not fog_ok:
		printerr("WEATHER_PROBE FAIL grid=", grid_ok, " outside=", outside_visible, " roof_hidden=", hidden_under_roof, " clear=", shown_after, " lens=", lens_ok, " clear_lens=", clear_lens_ok, " fog=", fog_ok)
		quit(1)
		return
	print("WEATHER_PROBE PASS rain_columns=16 roof_hidden=16 outside_shown=16 lens=true clear_lens=none fog_volumes=1 density=1.0 (authored .05 x20)")
	host.queue_free()
	ll.queue_free()
	target.queue_free()
	quit(0)
