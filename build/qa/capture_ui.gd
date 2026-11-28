extends SceneTree

var OUT_DIR: String = ProjectSettings.globalize_path("res://../build/qa").simplify_path()

func _init() -> void:
	call_deferred("_run")

func _wait_frames(n: int) -> void:
	for _i: int in range(n):
		await process_frame

func _save_shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null and not img.is_empty():
		var err: int = img.save_png(OUT_DIR + "/" + fname)
		print("UI CAPTURE: ", fname, " err=", err)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _wait_frames(3)
	var mm: Control = (load("res://src/ui/main_menu.gd") as GDScript).new() as Control
	mm.size = Vector2(1280, 720)
	root.add_child(mm)
	await _wait_frames(50)
	await _save_shot("vf_startscreen.png")
	mm.queue_free()
	await _wait_frames(4)

	var mp: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	mp.size = Vector2(1280, 720)
	root.add_child(mp)
	await _wait_frames(4)
	mp.call("open_prep", "guildhall", 1, "Solo", 0)
	await _wait_frames(30)
	await _save_shot("vf_mission_prep.png")
	mp.queue_free()
	await _wait_frames(4)

	var wd: CanvasLayer = (load("res://src/ui/wardrobe_ui.gd") as GDScript).new() as CanvasLayer
	root.add_child(wd)
	await _wait_frames(4)
	wd.call("open_customizer")
	await _wait_frames(30)
	await _save_shot("vf_wardrobe.png")
	wd.queue_free()
	await _wait_frames(4)
	print("UI CAPTURE DONE")
	quit(0)
