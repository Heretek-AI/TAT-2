extends SceneTree
## Independent guard-spawn probe (W10 guard check). Boots Contract 2
## (Mission.Guildhall.VaultHeist) on Novice, then reports the live guard group
## at spawn and after 600 physics frames: positions, visibility, mesh count,
## lantern children, floor/ceiling rays, and the authored marker under each XZ.
##
## It deliberately does NOT use TAT2_GUARD_DIAG (leave it unset): every number
## here comes from the running tree and the authored JSON, so a prior diag log
## can be checked against it rather than trusted. No push_error: a failed boot
## prints GUARD_CHECK FAIL and exits 1.

const CONTRACT_ORDER: int = 2
const BOOT_FRAME_LIMIT: int = 3600
const SETTLE_PHYSICS_FRAMES: int = 30
const PERSIST_PHYSICS_FRAMES: int = 600
const MOVED_M: float = 0.5
## Contract 2's map is guildhall (game/data/generated/gameplay/contracts.json
## order 2). Guard spawn points and their authored markers are both authored in
## the Guildhall_Gameplay layer, so this is the marker source, not the spawner.
const MARKER_LEVEL_JSON: String = "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json"


func _init() -> void:
	call_deferred("_run")


func _fmt_vec(v: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [v.x, v.y, v.z]


func _by_name(a: Node, b: Node) -> bool:
	return str(a.name) < str(b.name)


func _visible_mesh_count(n: Node) -> int:
	var n_vis: int = 0
	for m: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi != null and mi.is_visible_in_tree():
			n_vis += 1
	return n_vis


func _has_lantern(n: Node) -> bool:
	return n.find_child("LanternLight", true, false) != null \
		or n.find_child("GuardLantern", true, false) != null


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1)
	return space.intersect_ray(q)


func _hit_text(hit: Dictionary) -> String:
	if hit.is_empty():
		return "hit=0"
	var hp: Variant = hit.get("position", null)
	if not (hp is Vector3):
		return "hit=0"
	var col_text: String = "-"
	var col_v: Variant = hit.get("collider", null)
	if col_v is Node:
		col_text = str((col_v as Node).name)
	return "hit=1 pos=%s collider=%s" % [_fmt_vec(hp as Vector3), col_text]


func _hit_y(hit: Dictionary) -> float:
	if hit.is_empty():
		return NAN
	var hp: Variant = hit.get("position", null)
	if hp is Vector3:
		return (hp as Vector3).y
	return NAN


## Authored markers from the level JSON's `markers` list. Kept as plain
## {name, pos} dictionaries so the probe does not depend on loader types.
func _load_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f: FileAccess = FileAccess.open(MARKER_LEVEL_JSON, FileAccess.READ)
	if f == null:
		print("GUARD_CHECK marker_source=unreadable path=", MARKER_LEVEL_JSON)
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		print("GUARD_CHECK marker_source=bad_json path=", MARKER_LEVEL_JSON)
		return out
	var rows: Variant = (parsed as Dictionary).get("markers", [])
	if not (rows is Array):
		return out
	for row_v: Variant in (rows as Array):
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		# Only the authored guard spawner markers: the level's marker list also
		# carries patrol/loot/other points, and a non-spawner row could win the
		# XZ search for a guard that has drifted or fallen.
		if str(row.get("class", "")) != "BP_MissionSpawner_Character_C":
			continue
		var pos_v: Variant = row.get("pos", null)
		if not (pos_v is Array):
			continue
		var pos_a: Array = pos_v as Array
		if pos_a.size() < 3:
			continue
		out.append({
			"name": str(row.get("name", "?")),
			"pos": Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2])),
		})
	print("GUARD_CHECK marker_source=%s markers=%d" % [MARKER_LEVEL_JSON, out.size()])
	return out


## Nearest authored marker by XZ only: the guard marker's Y is the room point,
## so including Y would bias the search toward a different floor.
func _nearest_marker_xz(markers: Array[Dictionary], p: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = 1e9
	for m: Dictionary in markers:
		var mp: Vector3 = m["pos"] as Vector3
		var d: float = Vector2(mp.x - p.x, mp.z - p.z).length()
		if d < best_d:
			best_d = d
			best = m
	if not best.is_empty():
		best = best.duplicate()
		best["xz_dist"] = best_d
	return best


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("GUARD_CHECK FAIL no /root/GameState")
		quit(1)
		return
	gs.set("active_contract_order", CONTRACT_ORDER)
	# GameState.Difficulty.NOVICE = 1 (game/src/core/game_state.gd:19). Set
	# through the autoload node, not a static GameState identifier: in a
	# --script run the static name compiles game_state.gd before GameData
	# exists, which aborts the probe before it boots.
	gs.set("difficulty", 1)
	print("GUARD_CHECK boot contract=%d difficulty=%s" % [CONTRACT_ORDER, str(gs.get("difficulty"))])

	var mission: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission)
	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("guards").is_empty()) and waited < BOOT_FRAME_LIMIT:
		await process_frame
		waited += 1
	for _i: int in range(SETTLE_PHYSICS_FRAMES):
		await physics_frame
	if mission.get("player") == null or get_nodes_in_group("guards").is_empty():
		print("GUARD_CHECK FAIL boot_timeout frames=%d player=%s guards=%d" % [
			waited, str(mission.get("player") != null), get_nodes_in_group("guards").size(),
		])
		quit(1)
		return

	var player: Node3D = mission.get("player") as Node3D
	var anchor: Vector3 = player.global_position if player != null else Vector3.ZERO
	print("GUARD_CHECK anchor=%s boot_frames=%d" % [_fmt_vec(anchor), waited])

	var guards: Array = get_nodes_in_group("guards")
	guards.sort_custom(_by_name)
	var t1: Array[Dictionary] = []
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	for g_v: Node in guards:
		var g: Node3D = g_v as Node3D
		if g == null:
			continue
		var pos: Vector3 = g.global_position
		var meshes: int = g.find_children("*", "MeshInstance3D", true, false).size()
		var meshes_vis: int = _visible_mesh_count(g)
		var floor_hit: Dictionary = _ray(space, pos + Vector3(0.0, 0.10, 0.0), pos + Vector3(0.0, -6.0, 0.0))
		var ceil_hit: Dictionary = _ray(space, pos + Vector3(0.0, 1.0, 0.0), pos + Vector3(0.0, 7.0, 0.0))
		var floor_y: float = _hit_y(floor_hit)
		var ceil_y: float = _hit_y(ceil_hit)
		t1.append({
			"name": str(g.name),
			"pos": pos,
			"visible": g.is_visible_in_tree(),
			"meshes": meshes,
			"meshes_vis": meshes_vis,
			"lantern": _has_lantern(g),
		})
		print("GUARD_CHECK id=%s pos=%s visible_in_tree=%s meshes=%d meshes_visible=%d lantern=%s floor=%s ceil=%s dist_to_anchor=%.1f feet=%.3f surface_below=%s ceiling_above=%s" % [
			str(g.name), _fmt_vec(pos), str(g.is_visible_in_tree()), meshes, meshes_vis,
			"yes" if _has_lantern(g) else "no", _hit_text(floor_hit), _hit_text(ceil_hit),
			pos.distance_to(anchor), pos.y,
			("%.3f" % floor_y) if not is_nan(floor_y) else "none",
			("%.3f" % ceil_y) if not is_nan(ceil_y) else "none",
		])

	var markers: Array[Dictionary] = _load_markers()
	for row: Dictionary in t1:
		var gp: Vector3 = row["pos"] as Vector3
		var mk: Dictionary = _nearest_marker_xz(markers, gp)
		if mk.is_empty():
			print("GUARD_CHECK marker id=%s marker=none marker_floor=none delta_guard_minus_marker_floor=none" % str(row["name"]))
			continue
		var mp: Vector3 = mk["pos"] as Vector3
		var mk_floor_hit: Dictionary = _ray(space, Vector3(mp.x, mp.y + 0.05, mp.z), Vector3(mp.x, mp.y - 3.95, mp.z))
		var mk_floor_y: float = _hit_y(mk_floor_hit)
		var delta_text: String = "none"
		if not is_nan(mk_floor_y):
			delta_text = "%.3f" % (gp.y - mk_floor_y)
		# Reproduce the spawn placement independently of the diagnostic: the
		# engine's ground query casts from marker +8 m down 30 m, then adds the
		# 0.15 m guard clearance. This is the number to compare with a
		# spawn-time log; gp is 30 physics frames later, after gravity + AI.
		var spawn_hit: Dictionary = _ray(space, Vector3(mp.x, mp.y + 8.0, mp.z), Vector3(mp.x, mp.y - 30.0, mp.z))
		var spawn_y: float = _hit_y(spawn_hit)
		var spawn_text: String = "none"
		var live_minus_spawn_text: String = "none"
		if not is_nan(spawn_y):
			var pred_y: float = spawn_y + 0.15
			spawn_text = "(%.3f,%.3f,%.3f)" % [mp.x, pred_y, mp.z]
			live_minus_spawn_text = "%.3f" % (gp.y - pred_y)
		print("GUARD_CHECK marker id=%s src=%s marker=%s marker_xz_dist=%.3f marker_floor=%s guard_y=%.3f delta_guard_minus_marker_floor=%s marker_floor_ray=%s spawn_pred=%s spawn_ray=%s live_y_minus_spawn_pred_y=%s" % [
			str(row["name"]), str(mk["name"]), _fmt_vec(mp), float(mk["xz_dist"]),
			("%.3f" % mk_floor_y) if not is_nan(mk_floor_y) else "none",
			gp.y, delta_text, _hit_text(mk_floor_hit), spawn_text, _hit_text(spawn_hit),
			live_minus_spawn_text,
		])

	for _i: int in range(PERSIST_PHYSICS_FRAMES):
		await physics_frame
	var t2_nodes: Array = get_nodes_in_group("guards")
	t2_nodes.sort_custom(_by_name)
	print("GUARD_CHECK t2 count=%d" % t2_nodes.size())
	var t2_by_name: Dictionary = {}
	for g_v: Node in t2_nodes:
		var g: Node3D = g_v as Node3D
		if g == null:
			continue
		t2_by_name[str(g.name)] = g
		print("GUARD_CHECK t2 id=%s pos=%s visible_in_tree=%s" % [
			str(g.name), _fmt_vec(g.global_position), str(g.is_visible_in_tree()),
		])
	var disappeared: Array[String] = []
	var moved: Array[String] = []
	var hidden: Array[String] = []
	for row: Dictionary in t1:
		var name_s: String = str(row["name"])
		var p1: Vector3 = row["pos"] as Vector3
		if not t2_by_name.has(name_s):
			disappeared.append(name_s)
			continue
		var g2: Node3D = t2_by_name[name_s] as Node3D
		if g2 == null:
			disappeared.append(name_s)
			continue
		if g2.global_position.distance_to(p1) > MOVED_M:
			moved.append("%s(%.2f)" % [name_s, g2.global_position.distance_to(p1)])
		if not g2.is_visible_in_tree() or _visible_mesh_count(g2) == 0:
			hidden.append(name_s)
	print("GUARD_CHECK persistence disappeared=%s moved_over_%.1fm=%s hidden_or_meshless=%s" % [
		str(disappeared), MOVED_M, str(moved), str(hidden),
	])

	var t1_visible: int = 0
	var t1_with_meshes: int = 0
	var t1_lanterns: int = 0
	for row: Dictionary in t1:
		if bool(row["visible"]) and int(row["meshes_vis"]) > 0:
			t1_visible += 1
		if int(row["meshes"]) > 0:
			t1_with_meshes += 1
		if bool(row["lantern"]):
			t1_lanterns += 1
	print("GUARD_CHECK detail lanterns_t1=%d" % t1_lanterns)
	print("GUARD_CHECK SUMMARY guards_t1=%d guards_t2=%d visible=%d with_meshes=%d" % [
		t1.size(), t2_nodes.size(), t1_visible, t1_with_meshes,
	])
	quit(0)
