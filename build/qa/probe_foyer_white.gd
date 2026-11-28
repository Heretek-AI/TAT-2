extends SceneTree

var OUT_DIR: String = ProjectSettings.globalize_path("res://../build/qa").simplify_path()

func _init() -> void:
	call_deferred("_run")

func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + "/" + fname)
		print("FOYER CAP ", fname)

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
	for _i in range(15): await process_frame
	var player: Node3D = mission.get("player") as Node3D
	player.global_position = Vector3(27.0, 28.0, -50.0)
	player.rotation = Vector3(0.0, 0.0, 0.0)
	for _i in range(10): await process_frame
	var eye: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	var near: Array = []
	for n: Node in mission.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if gi == null or not gi.is_visible_in_tree(): continue
		var d: float = gi.global_position.distance_to(eye)
		if d < 7.0:
			var m: Material = null
			if gi is MeshInstance3D:
				var mi: MeshInstance3D = gi as MeshInstance3D
				if mi.mesh != null and mi.mesh.get_surface_count() > 0:
					m = mi.get_active_material(0)
			var sm: StandardMaterial3D = m as StandardMaterial3D
			near.append({"d": d, "name": gi.name, "ue": str(gi.get_meta("ue_mesh", "")), "mat": sm.albedo_color if sm else null, "unshaded": sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED if sm else null, "emis": sm.emission_energy_multiplier if sm and sm.emission_enabled else 0.0, "albedo_tex": sm.albedo_texture.resource_path if sm and sm.albedo_texture else ""})
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for e: Dictionary in near.slice(0, 15):
		print("FOYER NEAR ", e)
	# Hide the closest unshaded/emissive cards and recapture.
	var hidden: int = 0
	for n: Node in mission.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if gi == null: continue
		if gi.global_position.distance_to(eye) < 7.0 and gi is MeshInstance3D:
			var mi: MeshInstance3D = gi as MeshInstance3D
			if mi.mesh == null or mi.mesh.get_surface_count() == 0: continue
			var sm: StandardMaterial3D = mi.get_active_material(0) as StandardMaterial3D
			if sm != null and (sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or sm.emission_enabled):
				gi.visible = false
				hidden += 1
	print("FOYER hidden=", hidden)
	for _i in range(5): await process_frame
	await _save("vf_foyer_nocards.png")
	print("FOYER DONE")
	quit(0)
