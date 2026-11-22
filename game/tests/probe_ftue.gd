extends SceneTree
## Headless proof for the FTUE collider budget (task B3).
## Loads the full authored FTUE sublevel set and reports whether every
## gameplay collider survived and the safe-room start exists.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		printerr("FTUE_PROBE FAIL no GameData")
		quit(2)
		return
	var paths: Array[String] = []
	for sub: String in (gd.call("get_ftue_sublevels") as Array):
		paths.append("res://data/generated/levels/FTUE/%s.tatlevel.json" % sub)
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	var ll: Node = ll_scr.new() as Node
	root.add_child(ll)
	var host := Node3D.new()
	root.add_child(host)
	var res: Dictionary = ll.call("load_sublevels", paths, host, null, 96, true) as Dictionary
	var player_spawns: int = (res.get("player_spawns", []) as Array).size()
	var dropped: int = int(res.get("collision_dropped", -1))
	var shapes: int = int(res.get("collision_shapes", -1))
	var budget_ok: bool = bool(res.get("collider_budget_ok", false))
	var safe_room: bool = false
	var checkpoints: String = FileAccess.get_file_as_string(
		"res://data/generated/levels/FTUE/FTUE_Checkpoints.tatlevel.json"
	)
	safe_room = checkpoints.find("TATSafeRoomPlayerStart_0") >= 0
	print("FTUE_PROBE sublevels=", paths.size(),
		" player_spawns=", player_spawns,
		" collision_shapes=", shapes,
		" collision_dropped=", dropped,
		" budget_ok=", budget_ok,
		" safe_room_start=", safe_room)
	var ok: bool = player_spawns > 0 and dropped == 0 and budget_ok and safe_room
	print("FTUE_PROBE ", "PASS" if ok else "FAIL")
	ll.queue_free()
	host.queue_free()
	await process_frame
	quit(0 if ok else 1)
