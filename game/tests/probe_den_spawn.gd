extends SceneTree
## Fail-closed Thieves Den hub-spawn probe (headless).
##
## W10 DEN-FLOOR regression gate. The P0a turret fix added a blanket
## `/Game/Developers/` mesh skip in `tools/parse_tables.py`, which also deleted
## the Den shell (`gjasp/SM_ThievesDen`, `SM_ThievesDen_Floor`,
## `SM_ThievesDen_Glass`). With no floor under the authored `TATPlayerStart`
## markers the mission controller logged
##
##   spawn fallback exhausted (no grounded authored start, no marker floor hit);
##   legacy origin with centroid facing, source=legacy
##
## and the hub booted at `(0, 2, 0)`. This probe boots the real contract-1
## `thieves_den` mission and pins the target state:
##
##   * `fallback_spawn_source == "authored"` (never the legacy last resort),
##   * the player stands inside the Den hub bounds (x 0..10, y 40..43,
##     z 266..276) and within 2 m of an authored `TATPlayerStart` marker,
##   * the restored floor carries a layer-1 collider (`ue_mesh` meta
##     `/Game/Developers/gjasp/SM_ThievesDen_Floor`) and a downward ray from the
##     authored start hits it (the same 7 m query `_spawn_player` uses),
##   * the Den shell (`gjasp/SM_ThievesDen`) is restored with its collider.
##
## Run:
##   tools/godot --headless --path game --script res://tests/probe_den_spawn.gd
##
## Prints `DEN_SPAWN` lines and exits non-zero on failure.

const DEN_MAP_ID: String = "thieves_den"
const DEN_ORDER: int = 1
const BOOT_FRAME_LIMIT: int = 7200
const SETTLE_PHYSICS_FRAMES: int = 30
## Den hub bounds from the measured authored spawn cluster
## (TATPlayerStart_0..2 at x ~5.2..5.7, y 41.16, z 270.7..273.0).
const HUB_MIN := Vector3(0.0, 40.0, 266.0)
const HUB_MAX := Vector3(10.0, 43.0, 276.0)
## Authored-marker match: spawn is tp + 1 m, then `_snap_player_to_ground`
## replaces Y, so XZ stays within a few centimetres of the marker.
const MARKER_MATCH_M: float = 2.0
const SPAWN_FLOOR_MARGIN_M: float = 0.5
const FLOOR_MESH := "/game/developers/gjasp/sm_thievesden_floor"
const SHELL_MESH := "/game/developers/gjasp/sm_thievesden"

var _fails: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String, detail: String) -> void:
	_checks += 1
	if ok:
		print("  ok: ", name, " ", detail)
	else:
		_fails += 1
		printerr("  FAIL: ", name, " ", detail)


func _fmt_vec(v: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [v.x, v.y, v.z]


## Authored `TATPlayerStart` markers from the Den sublevels. Positions only; the
## probe uses them to prove the spawn is marker-grounded, never a marker-fallback
## loot centroid that happens to sit near the hub.
func _load_player_starts() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var dirs: Array[String] = [
		"res://data/generated/levels/ThievesDenTest",
	]
	for dir_path: String in dirs:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		var files: PackedStringArray = DirAccess.get_files_at(dir_path)
		files.sort()
		for file: String in files:
			if not file.ends_with(".tatlevel.json"):
				continue
			var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(dir_path.path_join(file)))
			if not (parsed is Dictionary):
				continue
			var rows: Variant = (parsed as Dictionary).get("markers", [])
			if not (rows is Array):
				continue
			for row_v: Variant in (rows as Array):
				if not (row_v is Dictionary):
					continue
				var row: Dictionary = row_v as Dictionary
				if str(row.get("class", "")) != "TATPlayerStart":
					continue
				var pos_v: Variant = row.get("pos", null)
				if not (pos_v is Array) or (pos_v as Array).size() < 3:
					continue
				var pos_a: Array = pos_v as Array
				out.append(Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2])))
	return out


## Every `CollisionShape3D` the loader emitted for a UE path (it stamps
## `ue_mesh` on each authored shape).
func _collision_shapes_for(mesh_path_lower: String) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for n: Node in root.find_children("*", "CollisionShape3D", true, false):
		var cs: CollisionShape3D = n as CollisionShape3D
		if cs == null:
			continue
		var ue: String = str(cs.get_meta("ue_mesh", "")).replace("\\", "/").to_lower()
		if ue == mesh_path_lower:
			out.append(cs)
	return out


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("DEN_SPAWN FAIL no /root/GameState")
		quit(1)
		return
	gs.set("active_contract_order", DEN_ORDER)
	# GameState.Difficulty.NOVICE = 1, set through the autoload (the static name
	# compiles game_state.gd before GameData exists in a --script run).
	gs.set("difficulty", 1)
	print("DEN_SPAWN boot order=%d difficulty=%s expect_map=%s" % [
		DEN_ORDER, str(gs.get("difficulty")), DEN_MAP_ID,
	])

	var mission: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission)
	var waited: int = 0
	while mission.get("player") == null and waited < BOOT_FRAME_LIMIT:
		await process_frame
		waited += 1
	for _i: int in range(SETTLE_PHYSICS_FRAMES):
		await physics_frame

	var player: Node3D = mission.get("player") as Node3D
	var loaded_map: String = str(gs.get("active_map_id"))
	var source: String = str(mission.get("fallback_spawn_source"))
	var spawn: Vector3 = player.global_position if player != null else Vector3.ZERO
	print("DEN_SPAWN boot_state loaded_map=%s frames=%d player=%s" % [
		loaded_map, waited, str(player != null),
	])
	if player == null:
		print("DEN_SPAWN FAIL boot_timeout frames=%d" % waited)
		quit(1)
		return
	print("DEN_SPAWN spawn source=%s pos=%s yaw=%.3f headroom_clear=%s forward_clear=%s" % [
		source, _fmt_vec(spawn), player.rotation.y,
		str(mission.get("fallback_spawn_headroom_clear")),
		str(mission.get("fallback_spawn_forward_clear")),
	])

	_check(loaded_map == DEN_MAP_ID, "contract 1 boots the Den hub",
		"loaded_map=%s" % loaded_map)
	_check(source == "authored", "spawn source is authored (never legacy)",
		"source=%s" % source)
	_check(spawn.distance_to(Vector3(0.0, 2.0, 0.0)) > 0.001,
		"player is not at the legacy origin", "pos=%s" % _fmt_vec(spawn))
	var in_bounds: bool = (
		spawn.x >= HUB_MIN.x and spawn.x <= HUB_MAX.x
		and spawn.y >= HUB_MIN.y and spawn.y <= HUB_MAX.y
		and spawn.z >= HUB_MIN.z and spawn.z <= HUB_MAX.z
	)
	_check(in_bounds, "player is inside the Den hub bounds",
		"pos=%s bounds=%s..%s" % [_fmt_vec(spawn), _fmt_vec(HUB_MIN), _fmt_vec(HUB_MAX)])

	var starts: Array[Vector3] = _load_player_starts()
	var nearest_m: float = INF
	for p: Vector3 in starts:
		nearest_m = minf(nearest_m, Vector2(p.x, p.z).distance_to(Vector2(spawn.x, spawn.z)))
	_check(starts.size() >= 3 and nearest_m <= MARKER_MATCH_M,
		"player stands on an authored TATPlayerStart",
		"starts=%d nearest_xz=%.3f m" % [starts.size(), nearest_m])

	# The floor must exist twice: the producer emitted the placement (it lives in
	# ThievesDen_Geo's level JSON) and the loader built a layer-1 collider for it.
	var floor_json: bool = false
	var den_geo: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/generated/levels/ThievesDen/ThievesDen_Geo.tatlevel.json"))
	if den_geo is Dictionary:
		for m_v: Variant in ((den_geo as Dictionary).get("meshes", []) as Array):
			if not (m_v is Dictionary):
				continue
			var mp: String = str((m_v as Dictionary).get("mesh", "")).replace("\\", "/").to_lower()
			if mp == FLOOR_MESH:
				floor_json = true
				break
	_check(floor_json, "producer emitted the Den floor placement", FLOOR_MESH)

	var floor_shapes: Array[CollisionShape3D] = _collision_shapes_for(FLOOR_MESH)
	var shell_shapes: Array[CollisionShape3D] = _collision_shapes_for(SHELL_MESH)
	_check(not floor_shapes.is_empty(), "loader built the Den floor collider",
		"shapes=%d" % floor_shapes.size())
	_check(not shell_shapes.is_empty(), "loader built the Den shell collider",
		"shapes=%d" % shell_shapes.size())

	# Reproduce `_spawn_player`'s floor query from the authored start and require
	# a hit just below it. This is the exact test that failed before the fix.
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	var start_y: float = NAN
	var first_hit_y: float = NAN
	if not starts.is_empty():
		var tp: Vector3 = starts[0]
		start_y = tp.y
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			tp + Vector3(0, 1.0, 0), tp + Vector3(0, -6.0, 0), 1)
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			var hp: Variant = hit.get("position", null)
			if hp is Vector3:
				first_hit_y = (hp as Vector3).y
	var grounded: bool = not is_nan(first_hit_y) and absf(first_hit_y - start_y) <= 2.0
	_check(grounded, "authored start ray hits the Den floor",
		"start_y=%s hit_y=%s" % [
			"%.3f" % start_y if not is_nan(start_y) else "none",
			"%.3f" % first_hit_y if not is_nan(first_hit_y) else "none",
		])

	print("DEN_SPAWN stats meshes=%d collision_shapes=%d floor_shapes=%d shell_shapes=%d" % [
		int((mission.get("level_stats") as Dictionary).get("mesh_instances", 0)),
		int((mission.get("level_stats") as Dictionary).get("collision_shapes", 0)),
		floor_shapes.size(), shell_shapes.size(),
	])
	print("DEN_SPAWN %s checks=%d fails=%d" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails,
	])
	quit(0 if _fails == 0 else 1)
