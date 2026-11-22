extends SceneTree
## Real-coordinate Guildhall doorway probe: [21, 20.5, 127] is the authored
## SM_Urban_Ext_FrontDoorA_Glass pivot. A 0.30 m capsule at x=20 must hit the
## closed leaf and pass the same aperture once the leaf has swung past 70 deg.

func _init() -> void:
	call_deferred("_run")


func _query(space: PhysicsDirectSpaceState3D, x: float) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.70
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, Vector3(x, 21.25, 127.0))
	q.collision_mask = 1
	return space.intersect_shape(q, 32)


func _door_hits(hits: Array, door: Node3D) -> int:
	var n: int = 0
	for h: Dictionary in hits:
		var col: Object = h.get("collider")
		if col == null:
			continue
		var node: Node = col as Node
		if node == null:
			continue
		var p: Node = node
		while p != null:
			if p == door:
				n += 1
				break
			p = p.get_parent()
	return n


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("active_contract_order", 4)
	var mission: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission)
	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and waited < 1200:
		await process_frame
		waited += 1
	await process_frame
	var player: Node3D = mission.get("player") as Node3D
	var doors: Array = get_nodes_in_group("swinging_doors")
	var nearest: Node3D = null
	var best: float = 1e9
	for d: Node in doors:
		var dn: Node3D = d as Node3D
		if dn == null:
			continue
		var dist: float = dn.global_position.distance_to(Vector3(21.0, 20.5, 127.0))
		if dist < best:
			best = dist
			nearest = dn
	if nearest == null:
		printerr("DOORWALK FAIL no door")
		quit(1)
		return
	print("DOORWALK nearest=", nearest.global_position, " dist=", best, " locked=", nearest.get("locked"), " open=", nearest.get("is_open"))
	var space: PhysicsDirectSpaceState3D = nearest.get_world_3d().direct_space_state
	var closed_hits: Array = _query(space, 20.0)
	for yy: float in [20.75, 21.25, 22.0]:
		var row: String = ""
		for xx: float in [18.5, 19.0, 19.5, 20.0, 20.5, 21.0, 21.5, 22.0, 22.5, 23.0]:
			var q := PhysicsRayQueryParameters3D.create(Vector3(xx, yy, 125.5), Vector3(xx, yy, 128.5))
			q.collision_mask = 1
			var hit: Dictionary = space.intersect_ray(q)
			row += "X" if not hit.is_empty() else "."
		print("DOORWALK ray y=", yy, " ", row)
	var closed_door: int = _door_hits(closed_hits, nearest)
	print("DOORWALK closed hits=", closed_hits.size(), " door=", closed_door)
	nearest.call("set_locked", false, 0)
	nearest.call("_start_swing_toggle")
	for _i: int in range(45):
		await physics_frame
	var angle: float = float(nearest.call("open_angle_deg"))
	var open_hits: Array = _query(space, 20.0)
	var open_door: int = _door_hits(open_hits, nearest)
	print("DOORWALK open angle=", angle, " hits=", open_hits.size(), " door=", open_door)
	for h: Dictionary in open_hits:
		var col: Object = h.get("collider")
		if col is Node:
			var b3: CollisionObject3D = col as CollisionObject3D
			print("DOORWALK open collider=", (col as Node).get_path())
			if b3 != null:
				var qpt := Vector3(20.0, 21.25, 127.0)
				for ch: Node in b3.get_children():
					if not (ch is CollisionShape3D):
						continue
					var cs: CollisionShape3D = ch as CollisionShape3D
					var dbg: Mesh = cs.shape.get_debug_mesh() if cs.shape != null else null
					if dbg == null:
						continue
					var waabb: AABB = cs.global_transform * dbg.get_aabb()
					if waabb.has_point(qpt):
						print("DOORWALK cand=", str(cs.get_meta("ue_mesh", "?")), " aabb=", waabb)
	var ok: bool = closed_door >= 1 and open_door == 0 and angle > 70.0
	if player != null:
		var p: Vector3 = player.global_position
		print("DOORWALK player=", p)
	print("DOORWALK ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
