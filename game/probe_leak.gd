extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var helpers_scr: GDScript = load("res://tests/e2e/e2e_helpers.gd") as GDScript
	var h: RefCounted = helpers_scr.new(self)
	await process_frame
	await physics_frame
	print("PROBE start players=" + str(h.tree.get_nodes_in_group("player").size()))
	var den_res: Dictionary = await h.instantiate_mission(1, 200, 1)
	print("PROBE after den players=" + str(h.tree.get_nodes_in_group("player").size()))
	for pl: Node in h.tree.get_nodes_in_group("player"):
		print("PROBE den player path=" + str(pl.get_path()))
	await h.free_node(den_res["mission"] as Node)
	await process_frame
	print("PROBE after den free players=" + str(h.tree.get_nodes_in_group("player").size()))
	var gh_res: Dictionary = await h.instantiate_mission(2, 240, 1)
	print("PROBE after gh players=" + str(h.tree.get_nodes_in_group("player").size()))
	for pl2: Node in h.tree.get_nodes_in_group("player"):
		print("PROBE gh player path=" + str(pl2.get_path()))
	await h.free_node(gh_res["mission"] as Node)
	await process_frame
	await process_frame
	print("PROBE after gh free players=" + str(h.tree.get_nodes_in_group("player").size()))
	for pl3: Node in h.tree.get_nodes_in_group("player"):
		var ok: String = str(is_instance_valid(pl3))
		print("PROBE leftover valid=" + ok + " path=" + (str(pl3.get_path()) if is_instance_valid(pl3) else "<invalid>"))
	var am_node: Node = root.get_node_or_null("/root/AudioManager")
	if am_node != null and am_node.has_method("cleanup_on_exit"):
		am_node.call("cleanup_on_exit")
		await process_frame
		await process_frame
	quit(0)
