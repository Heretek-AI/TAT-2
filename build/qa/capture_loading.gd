extends SceneTree

var OUT_DIR: String = ProjectSettings.globalize_path("res://../build/qa").simplify_path()

func _init() -> void:
	call_deferred("_run")

func _save(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(OUT_DIR + "/" + fname)
		print("LOAD CAP ", fname, " ", img.get_width(), "x", img.get_height())

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for _i in range(3): await process_frame
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null: gs.set("active_contract_order", 1)
	var mm: Control = (load("res://src/ui/main_menu.gd") as GDScript).new() as Control
	mm.size = Vector2(1280, 720)
	root.add_child(mm)
	for _i in range(30): await process_frame
	var mission: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission)
	for _i in range(6): await process_frame
	await _save("vf_loading_a.png")
	for _i in range(60): await process_frame
	await _save("vf_loading_b.png")
	print("LOAD CAP DONE")
	quit(0)
