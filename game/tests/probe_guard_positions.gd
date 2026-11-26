extends SceneTree
## Fail-closed guard-spawn probe (W10 A2). Boots a real contract on Novice and
## checks the LIVE guard group against the SPAWN MARKER each guard records:
##
##   * count == expected (4 on Novice),
##   * each guard within 2.0 m of its own `spawn_marker` meta (never "nearest
##     marker": C_116 is 1.62 m from Guard_1 and would pass the 8 m-up bug),
##   * each guard within 0.5 m of that marker's own downward floor ray when the
##     ray hits,
##   * at least one guard inside the Guildhall Lounge bbox x 20..52, y 24..32,
##     z -46..-5,
##   * no guard disappeared or became hidden/meshless after 600 physics frames.
##
## Prints one `GUARD_CHECK` line per value and `GUARD_CHECK PASS|FAIL` last;
## quits 1 on any failure. It deliberately does NOT use TAT2_GUARD_DIAG: every
## number comes from the running tree and the authored JSON.
##
## Usage:
##   tools/godot --headless --path game --script res://tests/probe_guard_positions.gd
##   tools/godot --headless --path game --script res://tests/probe_guard_positions.gd \
##       -- --map=old_manor --order=3

const DEFAULT_MAP: String = "guildhall"
const DEFAULT_ORDER: int = 2
const DEFAULT_EXPECT_GUARDS: int = 4
const BOOT_FRAME_LIMIT: int = 3600
const SETTLE_PHYSICS_FRAMES: int = 30
const PERSIST_PHYSICS_FRAMES: int = 600
const MOVED_M: float = 0.5
## A2 acceptance thresholds.
const SPAWN_MARKER_MAX_M: float = 2.0
const MARKER_FLOOR_MAX_M: float = 0.5
## Exact-position match tolerance for the authored marker fallback.
const MARKER_MATCH_M: float = 0.01
## Guildhall Lounge: x 20..52, y 24..32, z -46..-5 (AABB position + size).
const LOUNGE_BBOX := AABB(Vector3(20.0, 24.0, -46.0), Vector3(32.0, 8.0, 41.0))
## Marker directories per map. The probe only needs exact-position matches for
## reporting the authored marker name; the spawn marker itself comes from meta.
const MAP_MARKER_DIRS := {
	"guildhall": "res://data/generated/levels/Guildhall",
	"old_manor": "res://data/generated/levels/OldManor",
}

var _map_id: String = DEFAULT_MAP
var _order: int = DEFAULT_ORDER
var _expect_guards: int = DEFAULT_EXPECT_GUARDS
## Authored guard pool the loader handed to _spawn_guards. Guildhall has 116
## MissionSpawner_Character markers once the three SkyboxGeo BP_AirshipGuard_*
## set-dressing actors are excluded (they made it 119 before A2).
const EXPECTED_GUARD_POOL := {"guildhall": 116}


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			_map_id = arg.substr(6)
		elif arg.begins_with("--order="):
			_order = int(arg.substr(8))
		elif arg.begins_with("--expect="):
			_expect_guards = int(arg.substr(9))
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


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1)
	return space.intersect_ray(q)


func _hit_y(hit: Dictionary) -> float:
	if hit.is_empty():
		return NAN
	var hp: Variant = hit.get("position", null)
	if hp is Vector3:
		return (hp as Vector3).y
	return NAN


## Authored guard markers from every `.tatlevel.json` in the map directory.
## Same class filter as the loader's guard branch: SmartObject posts excluded,
## BP_AirshipGuard_* set dressing excluded (not mission guards), everything else
## with MissionSpawner_Character or "Guard" kept for exact-name reporting.
func _load_markers(map_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir_path: String = str(MAP_MARKER_DIRS.get(map_id, ""))
	if dir_path == "" or not DirAccess.dir_exists_absolute(dir_path):
		print("GUARD_CHECK marker_source=none map=%s dir=%s" % [map_id, dir_path])
		return out
	var files: PackedStringArray = DirAccess.get_files_at(dir_path)
	files.sort()
	for file: String in files:
		if not file.ends_with(".tatlevel.json"):
			continue
		var path: String = dir_path.path_join(file)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			print("GUARD_CHECK marker_source=bad_json path=", path)
			continue
		var rows: Variant = (parsed as Dictionary).get("markers", [])
		if not (rows is Array):
			continue
		for row_v: Variant in (rows as Array):
			if not (row_v is Dictionary):
				continue
			var row: Dictionary = row_v as Dictionary
			var cls: String = str(row.get("class", ""))
			if "SmartObject" in cls:
				continue
			if cls.begins_with("BP_AirshipGuard_"):
				continue
			if not ("MissionSpawner_Character" in cls or "Guard" in cls):
				continue
			var pos_v: Variant = row.get("pos", null)
			if not (pos_v is Array) or (pos_v as Array).size() < 3:
				continue
			var pos_a: Array = pos_v as Array
			out.append({
				"name": str(row.get("name", "?")),
				"file": file,
				"pos": Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2])),
			})
	print("GUARD_CHECK marker_source=%s markers=%d" % [dir_path, out.size()])
	return out


## Exact authored-marker match only. The old probe's nearest-XZ search is what
## let C_116 (1.62 m from Guard_1) hide an 8 m displacement; proximity is never
## used as identity.
func _exact_marker(markers: Array[Dictionary], p: Vector3) -> Dictionary:
	for m: Dictionary in markers:
		if (m["pos"] as Vector3).distance_to(p) <= MARKER_MATCH_M:
			return m
	return {}


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("GUARD_CHECK FAIL no /root/GameState")
		quit(1)
		return
	gs.set("active_contract_order", _order)
	# GameState.Difficulty.NOVICE = 1 (game/src/core/game_state.gd:19). Set
	# through the autoload node, not a static GameState identifier: in a
	# --script run the static name compiles game_state.gd before GameData
	# exists, which aborts the probe before it boots.
	gs.set("difficulty", 1)
	print("GUARD_CHECK boot map=%s order=%d difficulty=%s expect_guards=%d" % [
		_map_id, _order, str(gs.get("difficulty")), _expect_guards,
	])

	var mission: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission)
	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("guards").is_empty()) and waited < BOOT_FRAME_LIMIT:
		await process_frame
		waited += 1
	for _i: int in range(SETTLE_PHYSICS_FRAMES):
		await physics_frame
	var booted: bool = mission.get("player") != null and not get_nodes_in_group("guards").is_empty()
	var loaded_map: String = str(gs.get("active_map_id"))
	print("GUARD_CHECK boot_state loaded_map=%s frames=%d player=%s guards=%d" % [
		loaded_map, waited, str(mission.get("player") != null), get_nodes_in_group("guards").size(),
	])
	if not booted:
		print("GUARD_CHECK FAIL boot_timeout frames=%d player=%s guards=%d" % [
			waited, str(mission.get("player") != null), get_nodes_in_group("guards").size(),
		])
		quit(1)
		return

	var failures: Array[String] = []
	if loaded_map != _map_id:
		failures.append("loaded map %s != requested %s" % [loaded_map, _map_id])

	var player: Node3D = mission.get("player") as Node3D
	var anchor: Vector3 = player.global_position if player != null else Vector3.ZERO
	print("GUARD_CHECK anchor=%s" % _fmt_vec(anchor))
	var pool_count: int = -1
	var stats_v: Variant = mission.get("level_stats")
	if stats_v is Dictionary:
		pool_count = ((stats_v as Dictionary).get("guard_spawns", []) as Array).size()
	print("GUARD_CHECK guard_pool=%d" % pool_count)
	if EXPECTED_GUARD_POOL.has(_map_id) and pool_count != int(EXPECTED_GUARD_POOL[_map_id]):
		failures.append("loader guard pool %d != expected %d" % [
			pool_count, int(EXPECTED_GUARD_POOL[_map_id]),
		])

	var markers: Array[Dictionary] = _load_markers(_map_id)
	var guards: Array = get_nodes_in_group("guards")
	guards.sort_custom(_by_name)
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	var t1: Array[Dictionary] = []
	var lounge_guards: int = 0
	var with_meshes: int = 0
	var floor_checked: int = 0
	var floor_ok: int = 0
	for g_v: Node in guards:
		var g: Node3D = g_v as Node3D
		if g == null:
			continue
		var pos: Vector3 = g.global_position
		var visible_meshes: int = _visible_mesh_count(g)
		var meshes: int = g.find_children("*", "MeshInstance3D", true, false).size()
		if meshes > 0:
			with_meshes += 1

		var marker_v: Variant = null
		if g.has_meta(&"spawn_marker"):
			marker_v = g.get_meta(&"spawn_marker")
		var marker_ok: bool = marker_v is Vector3
		var marker: Vector3 = Vector3.ZERO
		var marker_src: String = "-"
		if marker_ok:
			marker = marker_v as Vector3
			var mk: Dictionary = _exact_marker(markers, marker)
			if not mk.is_empty():
				marker_src = str(mk["name"])
		else:
			# Fallback: exact position match only (a guard that has not moved
			# off its authored point). Never nearest.
			var exact: Dictionary = _exact_marker(markers, pos)
			if not exact.is_empty():
				marker = exact["pos"] as Vector3
				marker_ok = true
				marker_src = str(exact["name"])

		var grounded_meta_v: Variant = null
		if g.has_meta(&"grounded_spawn"):
			grounded_meta_v = g.get_meta(&"grounded_spawn")
		var grounded_text: String = "none"
		var grounded_dist_text: String = "none"
		if grounded_meta_v is Vector3:
			var gsp: Vector3 = grounded_meta_v as Vector3
			grounded_text = _fmt_vec(gsp)
			if marker_ok:
				grounded_dist_text = "%.3f" % gsp.distance_to(marker)

		var dist_text: String = "none"
		if marker_ok:
			var dist_marker: float = pos.distance_to(marker)
			dist_text = "%.3f" % dist_marker
			if dist_marker > SPAWN_MARKER_MAX_M:
				failures.append("%s: %.2f m from its spawn marker %s (max %.1f m)" % [
					str(g.name), dist_marker, _fmt_vec(marker), SPAWN_MARKER_MAX_M,
				])
		else:
			failures.append("%s: no spawn_marker meta and no exact authored marker match" % str(g.name))

		var floor_text: String = "none"
		var floor_delta_text: String = "none"
		var floor_hit: Dictionary = {}
		if marker_ok:
			floor_hit = _ray(space, marker + Vector3(0.0, 0.05, 0.0), marker + Vector3(0.0, -30.0, 0.0))
			var floor_y: float = _hit_y(floor_hit)
			if not is_nan(floor_y):
				floor_checked += 1
				var floor_delta: float = absf(pos.y - floor_y)
				floor_text = "%.3f" % floor_y
				floor_delta_text = "%.3f" % floor_delta
				if floor_delta <= MARKER_FLOOR_MAX_M:
					floor_ok += 1
				else:
					failures.append("%s: %.2f m off its marker floor %.3f (max %.1f m)" % [
						str(g.name), floor_delta, floor_y, MARKER_FLOOR_MAX_M,
					])
			else:
				floor_text = "none"
				floor_delta_text = "none"

		var in_lounge: bool = LOUNGE_BBOX.has_point(pos)
		if in_lounge:
			lounge_guards += 1
		if not g.is_visible_in_tree() or visible_meshes == 0:
			failures.append("%s: hidden or meshless at spawn (visible_in_tree=%s meshes_visible=%d)" % [
				str(g.name), str(g.is_visible_in_tree()), visible_meshes,
			])

		t1.append({"name": str(g.name), "pos": pos})
		print("GUARD_CHECK guard id=%s src=%s marker=%s grounded_meta=%s dist_marker=%s grounded_to_marker=%s floor_ray=%s floor_y=%s delta_floor=%s lounge=%s dist_anchor=%.1f meshes=%d meshes_visible=%d visible_in_tree=%s" % [
			str(g.name), marker_src, _fmt_vec(marker) if marker_ok else "none",
			grounded_text, dist_text, grounded_dist_text,
			"hit" if not floor_hit.is_empty() else "miss", floor_text, floor_delta_text,
			"yes" if in_lounge else "no", pos.distance_to(anchor), meshes, visible_meshes, str(g.is_visible_in_tree()),
		])

	if t1.size() != _expect_guards:
		failures.append("guard count %d != expected %d" % [t1.size(), _expect_guards])
	# The Lounge bbox is Guildhall geometry (Contract 2's authored room); the
	# Old Manor day-1 run reports count/offsets, not a Guildhall room.
	if _map_id == "guildhall":
		if lounge_guards < 1:
			failures.append("no guard inside the Lounge bbox x 20..52, y 24..32, z -46..-5")
	else:
		print("GUARD_CHECK lounge_check=not_applicable map=%s" % _map_id)

	# Persistence: guards must not be freed, hidden or made meshless while the
	# mission idles for 600 physics frames (~10 s).
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
		print("GUARD_CHECK t2 id=%s pos=%s visible_in_tree=%s meshes_visible=%d" % [
			str(g.name), _fmt_vec(g.global_position), str(g.is_visible_in_tree()),
			_visible_mesh_count(g),
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
	for name_s: String in disappeared:
		failures.append("%s: disappeared during the 600-frame persistence window" % name_s)
	for name_s: String in hidden:
		failures.append("%s: hidden or meshless after 600 physics frames" % name_s)

	print("GUARD_CHECK detail lanterns_t1=%d" % _count_lanterns(get_nodes_in_group("guards")))
	print("GUARD_CHECK SUMMARY map=%s order=%d guards_t1=%d guards_t2=%d expected=%d lounge_guards=%d with_meshes=%d marker_floor_within_%.1fm=%d/%d" % [
		_map_id, _order, t1.size(), t2_nodes.size(), _expect_guards, lounge_guards,
		with_meshes, MARKER_FLOOR_MAX_M, floor_ok, floor_checked,
	])
	if failures.is_empty():
		print("GUARD_CHECK PASS map=%s order=%d guards=%d lounge=%d" % [
			_map_id, _order, t1.size(), lounge_guards,
		])
		quit(0)
		return
	for reason: String in failures:
		print("GUARD_CHECK FAIL reason=", reason)
	print("GUARD_CHECK FAIL map=%s order=%d failures=%d" % [_map_id, _order, failures.size()])
	quit(1)


func _count_lanterns(nodes: Array) -> int:
	var n: int = 0
	for n_v: Node in nodes:
		if n_v == null:
			continue
		if n_v.find_child("LanternLight", true, false) != null \
			or n_v.find_child("GuardLantern", true, false) != null:
			n += 1
	return n
