extends SceneTree
## Free-play / Contract Inactive capture: prep card + in-mission HUD.

const OUT_DIR: String = "/home/john/Projects/TAT-2/build/qa/freeplay"
const MISSION_ID: String = "Mission.Guildhall.LootTheRoom"
const CONTRACT_ORDER: int = 2

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
		print("FREEPLAY CAPTURE: ", fname, " err=", err)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.size = Vector2i(1280, 720)
	await _wait_frames(3)
	var gs: Node = root.get_node_or_null("/root/GameState")

	# --- Prep card (free play) ---
	var mp: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	mp.size = Vector2(1280, 720)
	root.add_child(mp)
	await _wait_frames(4)
	mp.call("open_prep", "guildhall", 1, "Solo", CONTRACT_ORDER, true)
	await _wait_frames(60)
	await _save_shot("freeplay_prep.png")
	mp.queue_free()
	await _wait_frames(4)

	# --- Normal prep control ---
	var mp2: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	mp2.size = Vector2(1280, 720)
	root.add_child(mp2)
	await _wait_frames(4)
	mp2.call("open_prep", "guildhall", 1, "Solo", CONTRACT_ORDER, false)
	await _wait_frames(30)
	await _save_shot("freeplay_control_normal_prep.png")
	mp2.queue_free()
	await _wait_frames(4)

	# --- In-mission HUD ---
	if gs != null:
		gs.set("difficulty", 1)
		gs.set("thief_id", "spider")
		gs.set("active_contract_order", CONTRACT_ORDER)
		gs.set("active_map_id", "guildhall")
		gs.call("begin_free_play", MISSION_ID)
	var scene: PackedScene = load("res://scenes/mission.tscn") as PackedScene
	var gh: Node3D = scene.instantiate() as Node3D
	root.add_child(gh)
	var waited: int = 0
	while waited < 900:
		if gh.get("player") != null and not get_nodes_in_group("swinging_doors").is_empty():
			break
		await process_frame
		waited += 1
	print("FREEPLAY READY waited=", waited)
	await _wait_frames(30)
	var hud: Node = gh.get("hud") as Node
	if hud != null and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait_frames(10)
	await _wait_frames(6)
	var obj: Label = null
	var loot: Label = null
	if hud != null:
		obj = hud.get("obj_lbl") as Label
		loot = hud.get("_loot_lbl") as Label
	if obj != null:
		print("FREEPLAY OBJECTIVES=", obj.text)
	if loot != null:
		print("FREEPLAY LOOT=", loot.text)
	print("FREEPLAY free_play=", str(gs.get("free_play")) if gs != null else "?",
		" mission=", str(gs.get("active_mission_id")) if gs != null else "?")
	await _save_shot("freeplay_hud.png")
	print("FREEPLAY DONE")
	quit(0)
