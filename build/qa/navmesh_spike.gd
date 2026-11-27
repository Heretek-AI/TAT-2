extends SceneTree
## P2-NAV spike — Detour tile consumer probe.
##
## Reads the extractor's `tat2.nav_tiles/1` dump (tools/tat-extract `nav`
## command), builds a Godot NavigationMesh from the **authored** Detour polys
## and measures parse / build / map-sync / path cost. It never bakes, never
## edits nav_steering.gd, never registers a runtime region and never writes a
## file. The baked navmesh is authored content from the shipped UE5.5 map; this
## probe only proves it can be consumed.
##
## The doorway is also authored data: the default is the doorless 6x6 interior
## opening `BP_Doorless_Civic_DoorA_Wall_Int_6x6_C_281` in
## `Building_Guildhall_POI`. A doorway is emitted as one record per leaf; the
## probe uses their midpoint and the aligned local +Z (record basis column 2),
## places points 2.2 m either side and projects them onto the navmesh.
## `--door=<actor>` selects another record: the closed prison door
## `BP_Prison_WallA_DoorwayB_6x6_C_0` is the partial-path negative control.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 600 tools/godot --headless --path game \
##        --script $PWD/build/qa/navmesh_spike.gd \
##        -- --nav=/tmp/opencode/nav-spike/nav/Maps/Guildhall/Guildhall_P.json"
## or simply `build/qa/navmesh_spike.sh` (extracts the tiles if missing).
##
## Exit 0 only when the tile counts match the authored map, every polygon fits
## the vertex table and the known doorway path has >1 waypoint.

const DOOR_LEVEL := "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json"
## Authored 6x6 internal doorless doorway (`BP_Prison_WallA_DoorwayB_6x6_C`).
## The open doorway is the positive traversal case: the closed/locked prison
## door (`BP_Prison_WallA_DoorwayB_6x6_C_0`) returns a PARTIAL path because the
## baked navmesh cuts the doorway; that gap is what `GA_NavLink_SwingingDoor`
## is authored for, not a tile-extraction defect.
const DOOR_ACTOR := "BP_Doorless_Civic_DoorA_Wall_Int_6x6_C_281"
const DOOR_SIDE_M := 2.2
## Authored map totals from the extracted ARecastNavMesh (SizeInfo sums). The
## probe fails if the dump drifts; these are the shipped tile numbers, not a
## port target.
const EXPECTED_TILES := 2958
const EXPECTED_POLYS := 14930

var fails := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  PASS  ", what)
	else:
		fails += 1
		print("  FAIL  ", what)


func _run() -> void:
	var nav_path := _arg("--nav=")
	if nav_path == "":
		nav_path = OS.get_environment("TAT2_NAV_JSON")
	if nav_path == "":
		printerr("NAV_SPIKE usage: -- --nav=<path to Guildhall_P.json>")
		quit(2)
		return

	var t0 := Time.get_ticks_msec()
	var mem0 := OS.get_static_memory_usage()
	var f := FileAccess.open(nav_path, FileAccess.READ)
	if f == null:
		printerr("NAV_SPIKE cannot read ", nav_path)
		quit(2)
		return
	var text := f.get_as_text()
	f.close()
	var t_read := Time.get_ticks_msec()
	var doc: Variant = JSON.parse_string(text)
	var t_parse := Time.get_ticks_msec()
	if typeof(doc) != TYPE_DICTIONARY:
		printerr("NAV_SPIKE JSON parse failed")
		quit(2)
		return
	text = ""
	var d: Dictionary = doc
	if str(d.get("schema", "")) != "tat2.nav_tiles/1":
		_check(false, "schema is tat2.nav_tiles/1 (got %s)" % str(d.get("schema", "")))
		_quit_with_summary()
		return

	var tiles: Array = d.get("tiles", [])
	var tile_total := int(d.get("tile_count", 0))
	var poly_total := int(d.get("poly_count_total", 0))
	var vert_total := int(d.get("vert_count_total", 0))
	var offmesh_total := int(d.get("offmesh_connection_total", 0))
	print("NAV_TILES tiles=%d polys=%d verts=%d offmesh=%d cache_tiles=%d cache_bytes=%d decompress_fail=%d" % [
		tile_total, poly_total, vert_total, offmesh_total,
		int(d.get("cache_tiles", 0)), int(d.get("cache_compressed_bytes", 0)),
		int(d.get("cache_decompress_fail", 0))])

	# ---- build one NavigationMesh from every ground poly ---------------------
	var navmesh := NavigationMesh.new()
	var verts := PackedVector3Array()
	var key_to_index: Dictionary = {}
	var poly_arrays: Array[PackedInt32Array] = []
	var skipped: int = 0
	var max_poly_verts := 0
	for tile_v: Variant in tiles:
		var tile: Dictionary = tile_v
		var tv: Array = tile.get("verts", [])
		var local := PackedInt32Array()
		local.resize(tv.size() / 3)
		for i in range(0, tv.size(), 3):
			# Nav space is Recast Y-up centimetres; the port places the world as
			# Godot metres (x, y, -z) (parse_tables.ue_mat4_to_godot_trs).
			var key := Vector3i(roundi(float(tv[i])), roundi(float(tv[i + 1])), roundi(float(tv[i + 2])))
			var gi: int = key_to_index.get(key, -1)
			if gi < 0:
				gi = verts.size()
				key_to_index[key] = gi
				verts.append(Vector3(key.x * 0.01, key.y * 0.01, -key.z * 0.01))
			local[i / 3] = gi
		var tpolys: Array = tile.get("polys", [])
		var tflags: Array = tile.get("poly_flags", [])
		for pi in range(tpolys.size()):
			var flags := int(tflags[pi]) if pi < tflags.size() else 0
			if flags & 0x10 != 0:  # DT_POLYFLAGS_DISABLED
				skipped += 1
				continue
			var src: Array = tpolys[pi]
			var poly := PackedInt32Array()
			poly.resize(src.size())
			var bad := false
			for k in range(src.size()):
				var vi := local[int(src[k])]
				if vi < 0 or vi >= verts.size():
					bad = true
					break
				poly[k] = vi
			if bad or poly.size() < 3:
				skipped += 1
				continue
			max_poly_verts = maxi(max_poly_verts, poly.size())
			poly_arrays.append(poly)
	navmesh.vertices = verts
	for poly in poly_arrays:
		navmesh.add_polygon(poly)
	var t_build := Time.get_ticks_msec()
	print("NAV_BUILD verts=%d polys=%d skipped=%d max_poly_verts=%d read_ms=%d parse_ms=%d build_ms=%d" % [
		verts.size(), poly_arrays.size(), skipped, max_poly_verts,
		t_read - t0, t_parse - t_read, t_build - t_parse])

	_check(tile_total == EXPECTED_TILES, "authored tile count == %d (got %d)" % [EXPECTED_TILES, tile_total])
	_check(poly_total == EXPECTED_POLYS, "authored poly count == %d (got %d)" % [EXPECTED_POLYS, poly_total])
	_check(verts.size() > 0 and poly_arrays.size() == 14709, "walkable poly count == 14709 (got %d)" % poly_arrays.size())
	_check(vert_total == 40126, "authored vertex count == 40126 (got %d)" % vert_total)
	_check(offmesh_total == 221, "authored off-mesh connection count == 221 (got %d)" % offmesh_total)
	_check(skipped == 0, "no polygon skipped (got %d)" % skipped)

	if poly_arrays.is_empty():
		_check(false, "dump contains at least one ground polygon")
		_quit_with_summary()
		return

	# ---- one region on the default world map ---------------------------------
	var region := NavigationRegion3D.new()
	region.name = "NavSpikeRegion"
	region.navigation_mesh = navmesh
	root.add_child(region)
	await process_frame
	var map: RID = root.world_3d.navigation_map
	# Authored detour edges are centimetre-scale; the default 0.25 m map cell
	# would quantise them away. These are consumer settings, not authored data.
	NavigationServer3D.map_set_cell_size(map, 0.01)
	NavigationServer3D.map_set_edge_connection_margin(map, 0.05)
	var probe: Vector3 = verts[poly_arrays[0][0]]
	var t_sync0 := Time.get_ticks_msec()
	var synced := false
	var frames := 0
	for i in range(900):
		await physics_frame
		frames = i + 1
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			var c: Vector3 = NavigationServer3D.map_get_closest_point(map, probe)
			if c.distance_to(probe) < 0.5:
				synced = true
				break
	NavigationServer3D.map_force_update(map)
	var t_sync := Time.get_ticks_msec()
	print("NAV_MAP synced=%s frames=%d iteration=%d regions=%d cell=%.3f margin=%.3f sync_ms=%d region_enabled=%s" % [
		str(synced), frames, NavigationServer3D.map_get_iteration_id(map),
		NavigationServer3D.map_get_regions(map).size(),
		NavigationServer3D.map_get_cell_size(map),
		NavigationServer3D.map_get_edge_connection_margin(map),
		t_sync - t_sync0, str(region.enabled)])
	_check(synced, "navigation map synchronised (region polygons committed)")
	_check(NavigationServer3D.map_get_regions(map).size() >= 1, "map carries the spike region")
	_check(navmesh.get_polygon_count() == 14709, "NavigationMesh holds 14709 polys (got %d)" % navmesh.get_polygon_count())

	# ---- known doorway: authored doorless civic doorway ----------------------
	var door_level := _arg("--level=")
	if door_level == "":
		door_level = DOOR_LEVEL
	var door_actor := _arg("--door=")
	if door_actor == "":
		door_actor = DOOR_ACTOR
	var door := _door_record(door_level, door_actor)
	if door.is_empty():
		_check(false, "authored door record %s found" % door_actor)
	else:
		var pos: Vector3 = door["pos"]
		var normal: Vector3 = door["normal"]
		var a: Vector3 = pos + normal * DOOR_SIDE_M
		var b: Vector3 = pos - normal * DOOR_SIDE_M
		var sa: Vector3 = NavigationServer3D.map_get_closest_point(map, a)
		var sb: Vector3 = NavigationServer3D.map_get_closest_point(map, b)
		var da: float = sa.distance_to(a)
		var db: float = sb.distance_to(b)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, sa, sb, true)
		var path_len: float = 0.0
		for i in range(1, path.size()):
			path_len += path[i - 1].distance_to(path[i])
		var straight: float = sa.distance_to(sb)
		print("NAV_DOOR_PATH actor=%s level=%s door=%s normal=%s a=%s b=%s snapped_a=%s snapped_b=%s snap_dist=(%.2f,%.2f) waypoints=%d length_m=%.2f straight_m=%.2f" % [
			door_actor, door_level, str(pos), str(normal), str(a), str(b), str(sa), str(sb),
			da, db, path.size(), path_len, straight])
		for i in range(path.size()):
			print("  WP %d %s" % [i, str(path[i])])
		var reach: float = path[path.size() - 1].distance_to(sb) if path.size() > 0 else INF
		_check(da <= 2.5 and db <= 2.5, "both door-side points project onto the navmesh (<=2.5 m)")
		_check(path.size() > 1, "known doorway path has >1 waypoint (got %d)" % path.size())
		_check(path.size() > 2, "known doorway path crosses a poly boundary (got %d waypoints)" % path.size())
		_check(reach <= 0.5, "path reaches the far side of the doorway (last waypoint %.2f m from target)" % reach)
		_check(path_len >= straight - 0.5, "path is not a partial/short path (%.2f >= %.2f - 0.5)" % [path_len, straight])
		_check(path_len <= straight + 3.0, "doorway path is not a wall detour (%.2f <= %.2f + 3.0)" % [path_len, straight])
		_check(sa.distance_to(sb) > 2.0, "doorway endpoints are on opposite sides (>2 m)")

	var t_total := Time.get_ticks_msec()
	var mem_mb := float(OS.get_static_memory_usage() - mem0) / 1048576.0
	print("NAV_LOAD_MS read=%d parse=%d build=%d sync=%d total=%d mem_mb=%.1f" % [
		t_read - t0, t_parse - t_read, t_build - t_parse, t_sync - t_sync0,
		t_total - t0, mem_mb])
	_quit_with_summary()


func _door_record(level_path: String, actor: String) -> Dictionary:
	var f := FileAccess.open(level_path, FileAccess.READ)
	if f == null:
		return {}
	var doc: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(doc) != TYPE_DICTIONARY:
		return {}
	# A doorway is emitted as one record per leaf (`Pivot` + `SecondPivot`).
	# The opening centre is their midpoint; the pivot alone sits on a jamb and a
	# perpendicular ray from it lands on the wall, not through the doorway.
	var centre := Vector3.ZERO
	var normal := Vector3.ZERO
	var n := 0
	for rec: Variant in (doc as Dictionary).get("swinging_doors", []):
		var dr: Dictionary = rec
		if str(dr.get("actor", "")) != actor:
			continue
		var p: Array = dr.get("pos", [])
		var b: Array = dr.get("basis", [])
		if p.size() < 3 or b.size() < 9:
			continue
		var leaf_normal := Vector3(float(b[2]), float(b[5]), float(b[8]))
		leaf_normal.y = 0.0
		if leaf_normal.length() < 0.001:
			continue
		leaf_normal = leaf_normal.normalized()
		if normal.length() > 0.001 and normal.dot(leaf_normal) < 0.0:
			leaf_normal = -leaf_normal
		normal += leaf_normal
		centre += Vector3(float(p[0]), float(p[1]), float(p[2]))
		n += 1
	if n == 0 or normal.length() < 0.001:
		return {}
	return {
		"pos": centre / float(n),
		"normal": normal.normalized(),
	}


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	for a: String in OS.get_cmdline_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _quit_with_summary() -> void:
	print("NAV_SPIKE_SUMMARY checks=%d fails=%d" % [checks, fails])
	quit(0 if fails == 0 else 1)
