extends SceneTree
func _init() -> void:
	call_deferred("_go")
func _go() -> void:
	root.size = Vector2i(1280, 720)
	for _i: int in range(3):
		await process_frame
	var mp: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	mp.size = Vector2(1280, 720)
	root.add_child(mp)
	for _i: int in range(4):
		await process_frame
	mp.call("open_prep", "guildhall", 1, "Solo", 0)
	for _i: int in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/qa/vf_mission_prep.png").simplify_path())
	mp.queue_free()
	quit(0)
