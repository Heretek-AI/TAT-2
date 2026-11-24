extends SceneTree

const OUT_DIR: String = "/home/john/Projects/TAT-2/build/qa"

func _init() -> void:
	call_deferred("_run")

func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + "/" + fname)
		print("GUARD CAP ", fname)

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
	for _i in range(20): await process_frame
	if mission.get("hud") != null and mission.hud.has_method("is_mission_letter_open") and mission.hud.call("is_mission_letter_open"):
		mission.hud.call("_close_mission_letter")
		for _i in range(6): await process_frame
	var guards: Array = get_nodes_in_group("guards")
	print("GUARD count=", guards.size())
	for i in range(mini(guards.size(), 8)):
		var g: Node3D = guards[i] as Node3D
		if g == null: continue
		print("GUARD ", i, " name=", g.name, " pos=", g.global_position, " lantern=", g.get("carries_lantern"), " real=", g.get("_use_real_anims"))
	if guards.is_empty():
		print("GUARD DONE no guards")
		quit(0); return
	var g0: Node3D = guards[0] as Node3D
	for i in range(guards.size()):
		var g: Node3D = guards[i] as Node3D
		if g != null:
			g0 = g
			break
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.position = g0.global_position + Vector3(0.0, 2.0, 2.2)
	mission.add_child(cam)
	cam.look_at(g0.global_position + Vector3(0.0, 1.8, 0.0), Vector3.UP)
	cam.current = true
	var meshes: Array = g0.find_children("*", "MeshInstance3D", true, false)
	print("GUARD meshes=", meshes.size())
	for m: Node in meshes:
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi != null and mi.mesh != null:
			var sm: StandardMaterial3D = mi.get_active_material(0) as StandardMaterial3D
			print("GUARD mi=", mi.name, " surf=", mi.mesh.get_surface_count(), " mat=", sm.albedo_color if sm else "?")
	var skels: Array = g0.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		print("GUARD bones=", (skels[0] as Skeleton3D).get_bone_count())
	await _save("vf_guard.png")
	print("GUARD DONE")
	quit(0)
