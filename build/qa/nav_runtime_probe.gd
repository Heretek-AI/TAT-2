extends SceneTree
## N-P1/N-P2 headless probe: authored navmesh runtime + links + doors.
##
## It loads the generated `nav/<map>.nav.bin` (default Guildhall), builds the
## real `src/ai/nav_runtime.gd`, waits for the navigation server to commit the
## 14,709 authored polys, walks the known doorless 6x6 doorway (3-waypoint
## path), checks every baked link, and runs the prison-door link on/off test
## with two fake `SwingingDoor` leaves carrying the authored prison pivots.
##
## The probe is headless and writes nothing. It reads the generated asset, so
## the integrator must run the extractor `nav` command and `tools/parse_nav.py`
## first. Use `--nav-dir=<dir>` to point at a generated tree under /tmp.
##
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 600 tools/godot --headless --path game \
##        --script $PWD/build/qa/nav_runtime_probe.gd \
##        -- --nav-dir=$PWD/game/data/generated/nav"
##
## Exit 0 only when every check passes.

const NavRuntimeScript := preload("res://src/ai/nav_runtime.gd")
const DOOR_LEVEL := "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json"
const DOOR_ACTOR := "BP_Doorless_Civic_DoorA_Wall_Int_6x6_C_281"
const PRISON_ACTOR := "BP_Prison_WallA_DoorwayB_6x6_C_0"
const DOOR_SIDE_M := 2.2

## Measured authored totals for Guildhall (navmesh-spike.md + the N-P0
## extractor run); the probe fails if the generated asset drifts.
const EXPECT_TILES := 2958
const EXPECT_POLYS := 14709
const EXPECT_VERTS := 30918
const EXPECT_RAW_OFFMESH := 221
const EXPECT_LINKS := 80
const EXPECT_BIDIR := 35
const EXPECT_ONE_WAY := 45

var fails := 0
var checks := 0


class FakeDoor:
	extends Node3D
	var angle := 0.0
	var door_entry: Dictionary = {}

	func open_angle_deg() -> float:
		return angle


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
	var nav_dir := _arg("--nav-dir=")
	if nav_dir == "":
		nav_dir = OS.get_environment("TAT2_NAV_DIR")
	if nav_dir == "":
		nav_dir = "res://data/generated/nav"
	OS.set_environment("TAT2_NAV", "on")
	OS.set_environment("TAT2_NAV_DIR", nav_dir)

	var manifest := _read_json(nav_dir.path_join("manifest.json"))
	_check(not manifest.is_empty(), "nav manifest parses (%s)" % nav_dir)
	if manifest.is_empty():
		_quit_with_summary()
		return
	_check(str(manifest.get("schema", "")) == "tat2.nav/1", "manifest schema is tat2.nav/1")
	var maps: Dictionary = manifest.get("maps", {})
	var entry_v: Variant = maps.get("guildhall", null)
	_check(typeof(entry_v) == TYPE_DICTIONARY, "manifest carries guildhall")
	if typeof(entry_v) != TYPE_DICTIONARY:
		_quit_with_summary()
		return
	var entry: Dictionary = entry_v
	_check(int(entry.get("tiles", 0)) == EXPECT_TILES, "guildhall tiles == %d (got %d)" % [EXPECT_TILES, int(entry.get("tiles", 0))])
	_check(int(entry.get("polys", 0)) == EXPECT_POLYS, "guildhall walkable polys == %d (got %d)" % [EXPECT_POLYS, int(entry.get("polys", 0))])
	_check(int(entry.get("verts", 0)) == EXPECT_VERTS, "guildhall deduped verts == %d (got %d)" % [EXPECT_VERTS, int(entry.get("verts", 0))])
	_check(int(entry.get("raw_offmesh", 0)) == EXPECT_RAW_OFFMESH, "raw offmesh records == %d (got %d)" % [EXPECT_RAW_OFFMESH, int(entry.get("raw_offmesh", 0))])
	_check(int(entry.get("links", 0)) == EXPECT_LINKS, "logical links == %d (got %d)" % [EXPECT_LINKS, int(entry.get("links", 0))])
	_check(int(entry.get("links_bidirectional", 0)) == EXPECT_BIDIR, "bidirectional links == %d (got %d)" % [EXPECT_BIDIR, int(entry.get("links_bidirectional", 0))])
	_check(int(entry.get("links_one_way", 0)) == EXPECT_ONE_WAY, "one-way links == %d (got %d)" % [EXPECT_ONE_WAY, int(entry.get("links_one_way", 0))])
	_check(int(entry.get("max_poly_verts", 0)) <= 6, "producer max_poly_verts <= 6")
	var areas: Array = entry.get("areas", [])
	var area_by_id: Dictionary = {}
	for a_v: Variant in areas:
		var a: Dictionary = a_v
		area_by_id[int(a.get("id", -1))] = str(a.get("class", ""))
	_check(area_by_id.size() == 8, "8 authored supported areas (got %d)" % area_by_id.size())
	_check(str(area_by_id.get(63, "")) == "NavArea_Default", "area 63 is NavArea_Default (never Recast null)")
	_check(str(area_by_id.get(4, "")) == "NavArea_Door_C", "Guildhall area 4 is NavArea_Door_C")
	_check(str(area_by_id.get(3, "")) == "NavArea_Bushes_C", "Guildhall area 3 is NavArea_Bushes_C")
	var cfg: Dictionary = entry.get("nav_data_config", {})
	_check(is_equal_approx(float(cfg.get("agent_radius_cm", 0.0)), 45.0), "authored agent radius 45 cm")
	_check(is_equal_approx(float(cfg.get("agent_height_cm", 0.0)), 240.0), "authored agent height 240 cm")
	_check(is_equal_approx(float(cfg.get("agent_step_height_cm", 0.0)), 45.0), "authored agent step 45 cm")

	var host := Node3D.new()
	root.add_child(host)
	var nav = NavRuntimeScript.new()
	nav.name = "NavRuntimeProbe"
	host.add_child(nav)
	var built: bool = nav.setup("guildhall")
	_check(built, "nav_runtime.setup(guildhall)")
	_check(nav.status() == "built", "runtime state is built (got %s)" % nav.status())
	var navmesh: NavigationMesh = nav.navmesh()
	_check(navmesh != null, "runtime owns a NavigationMesh")
	if navmesh == null:
		_quit_with_summary()
		return
	_check(navmesh.get_polygon_count() == EXPECT_POLYS, "NavigationMesh holds %d polys (got %d)" % [EXPECT_POLYS, navmesh.get_polygon_count()])
	_check(navmesh.get_vertices().size() == EXPECT_VERTS, "NavigationMesh holds %d verts (got %d)" % [EXPECT_VERTS, navmesh.get_vertices().size()])
	_check(nav.link_count() == EXPECT_LINKS, "runtime created %d NavigationLink3D (got %d)" % [EXPECT_LINKS, nav.link_count()])
	_check(nav.bidirectional_link_count() == EXPECT_BIDIR, "runtime bidirectional links == %d" % EXPECT_BIDIR)
	_check(nav.one_way_link_count() == EXPECT_ONE_WAY, "runtime one-way links == %d" % EXPECT_ONE_WAY)
	var max_poly := 0
	for pi in range(navmesh.get_polygon_count()):
		max_poly = maxi(max_poly, navmesh.get_polygon(pi).size())
	_check(max_poly <= 6, "every NavigationMesh polygon has <= 6 verts (max %d)" % max_poly)

	var ready: bool = await nav.wait_ready(900)
	_check(ready, "navigation map committed")
	_check(nav.status() == "ready", "runtime state is ready (got %s)" % nav.status())
	var map: RID = root.world_3d.navigation_map
	print("NAV_MAP_ASYNC async=%s" % str(NavigationServer3D.map_get_use_async_iterations(map)))
	NavigationServer3D.map_set_use_async_iterations(map, false)
	_check(NavigationServer3D.map_get_iteration_id(map) > 0, "map iteration id > 0")
	_check(NavigationServer3D.map_get_regions(map).size() >= 1, "map carries the nav region")
	_check(is_equal_approx(NavigationServer3D.map_get_cell_size(map), 0.01), "map cell size 0.01 m")
	_check(is_equal_approx(NavigationServer3D.map_get_edge_connection_margin(map), 0.05), "map edge connection margin 0.05 m")
	_check(is_equal_approx(NavigationServer3D.map_get_link_connection_radius(map), 1.0), "map link connection radius 1.0 m")
	_check(NavigationServer3D.map_get_links(map).size() == EXPECT_LINKS, "map carries %d baked links (got %d)" % [EXPECT_LINKS, NavigationServer3D.map_get_links(map).size()])
	print("NAV_PROBE_READY frames=%d ready_ms=%d build_ms=%d links=%d" % [nav.ready_frames(), nav.ready_ms(), nav.build_ms(), nav.link_count()])

	# Every authored off-mesh endpoint should sit on/near the authored mesh.
	# 155/160 endpoints and 79/80 links meet the 2.5 m authored-link test; the
	# exception is NavLink_71, a 3 m authored drop at y=-5 whose both endpoints
	# are ~6 m from any walkable poly (the cooked mesh has no surface there).
	# It stays in the asset as authored data but cannot connect in Godot.
	var near := 0
	var total := 0
	var links_with_side := 0
	for child: Node in nav.get_children():
		if not (child is NavigationLink3D):
			continue
		var link := child as NavigationLink3D
		var ds := NavigationServer3D.map_get_closest_point(map, link.get_global_start_position()).distance_to(link.get_global_start_position())
		var de := NavigationServer3D.map_get_closest_point(map, link.get_global_end_position()).distance_to(link.get_global_end_position())
		total += 2
		if ds <= 2.5:
			near += 1
		if de <= 2.5:
			near += 1
		if minf(ds, de) <= 2.5:
			links_with_side += 1
	_check(near >= 155, "at least 155/160 baked link endpoints project within 2.5 m (got %d)" % near)
	_check(links_with_side >= 79, "at least 79/80 baked links have one side on the mesh (got %d)" % links_with_side)
	print("NAV_LINKS endpoints_near=%d/%d links_with_side=%d/80" % [near, total, links_with_side])

	# ---- authored doorless doorway: 3 waypoints, no wall detour -------------
	var door := _door_record(DOOR_LEVEL, DOOR_ACTOR)
	_check(not door.is_empty(), "authored door record %s" % DOOR_ACTOR)
	if not door.is_empty():
		var dmid: Vector3 = door["pos"]
		var dn: Vector3 = door["normal"]
		var a: Vector3 = dmid + dn * DOOR_SIDE_M
		var b: Vector3 = dmid - dn * DOOR_SIDE_M
		var p := _path(map, a, b)
		print("NAV_DOOR_PATH actor=%s door=%s normal=%s waypoints=%d length_m=%.2f straight_m=%.2f reach=%.2f" % [
			DOOR_ACTOR, str(dmid), str(dn), int(p.get("waypoints", 0)),
			float(p.get("length", 0.0)), float(p.get("straight", 0.0)), float(p.get("reach", INF))])
		_check(float(p.get("snap_a", INF)) <= 2.5 and float(p.get("snap_b", INF)) <= 2.5, "both doorway sides project onto the navmesh")
		_check(int(p.get("waypoints", 0)) >= 3, "doorless doorway path has >= 3 waypoints (got %d)" % int(p.get("waypoints", 0)))
		_check(float(p.get("reach", INF)) <= 0.5, "doorless path reaches the far side (%.2f m short)" % float(p.get("reach", INF)))
		_check(float(p.get("length", 0.0)) >= float(p.get("straight", 0.0)) - 0.5, "doorless path is not partial")
		_check(float(p.get("length", 0.0)) <= float(p.get("straight", 0.0)) + 3.0, "doorless path is not a wall detour")

	# ---- prison door link on/off (east -> west; the authored baked link is
	#      one-way west -> east, so this direction needs the door link) --------
	var prison := _door_record(DOOR_LEVEL, PRISON_ACTOR)
	_check(not prison.is_empty(), "authored prison door record %s" % PRISON_ACTOR)
	if not prison.is_empty():
		var pmid: Vector3 = prison["pos"]
		var pn: Vector3 = prison["normal"]
		var fakes := _make_prison_doors(host, pmid, pn)
		var made: int = nav.register_swinging_doors()
		_check(made == 1, "one prison door link created (got %d)" % made)
		_check(nav.door_link_count() == 1, "runtime owns one door link")
		var door_link := _door_link(nav)
		_check(door_link != null, "door link node found")
		if door_link != null:
			_check(not door_link.enabled, "door link starts disabled (open angle 0)")
			print("NAV_DOORLINK start=%s end=%s enabled=%s links_on_map=%d" % [
				str(door_link.get_global_start_position()), str(door_link.get_global_end_position()),
				str(door_link.enabled), NavigationServer3D.map_get_links(map).size()])
			print("NAV_DOORLINK snap start=%.2f end=%.2f" % [
				NavigationServer3D.map_get_closest_point(map, door_link.get_global_start_position()).distance_to(door_link.get_global_start_position()),
				NavigationServer3D.map_get_closest_point(map, door_link.get_global_end_position()).distance_to(door_link.get_global_end_position())])
		var east_point := pmid + pn * DOOR_SIDE_M
		var west_point := pmid - pn * DOOR_SIDE_M
		var off := _path(map, east_point, west_point)
		print("NAV_PRISON off waypoints=%d length_m=%.2f straight_m=%.2f reach=%.2f" % [
			int(off.get("waypoints", 0)), float(off.get("length", 0.0)),
			float(off.get("straight", 0.0)), float(off.get("reach", INF))])
		_check(float(off.get("reach", 0.0)) > 0.5, "closed prison door blocks east->west (partial path)")
		for f: FakeDoor in fakes:
			f.angle = 90.0
		# The probe disables async map iterations before this point so the link
		# enable is committed deterministically; 30 frames covers the map's own
		# iteration in either mode.
		await _frames(30)
		NavigationServer3D.map_force_update(map)
		if door_link != null:
			_check(door_link.enabled, "door link enables at open angle 90")
			var dlink_iter := NavigationServer3D.link_get_iteration_id(door_link.get_rid())
			var dlink_enabled := NavigationServer3D.link_get_enabled(door_link.get_rid())
			print("NAV_DOORLINK on enabled=%s links_on_map=%d server_enabled=%s iter=%d" % [
				str(door_link.enabled), NavigationServer3D.map_get_links(map).size(),
				str(dlink_enabled), dlink_iter])
		var on := _path(map, east_point, west_point)
		print("NAV_PRISON on  waypoints=%d length_m=%.2f straight_m=%.2f reach=%.2f" % [
			int(on.get("waypoints", 0)), float(on.get("length", 0.0)),
			float(on.get("straight", 0.0)), float(on.get("reach", INF))])
		_check(float(on.get("reach", INF)) <= 0.5, "open prison door reaches the far side (%.2f m short)" % float(on.get("reach", INF)))
		for f: FakeDoor in fakes:
			f.angle = 0.0
		await _frames(6)
		if door_link != null:
			_check(not door_link.enabled, "door link disables when the door closes")
		var again := _path(map, east_point, west_point)
		_check(float(again.get("reach", 0.0)) > 0.5, "re-closed prison door blocks again")
		print("NAV_PRISON toggles=%d" % nav.door_toggle_count())

		# A door far from the navmesh must not create a floating link.
		for f: FakeDoor in fakes:
			f.get_parent().remove_child(f)
			f.free()
		var far := FakeDoor.new()
		far.name = "FarPrisonFake"
		far.door_entry = {"actor": "FakeFarDoor"}
		far.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1000.0, 0.0))
		host.add_child(far)
		far.add_to_group("swinging_doors")
		var far_made: int = nav.register_swinging_doors()
		_check(far_made == 0, "far door creates no link (got %d)" % far_made)
		_check(nav.door_skipped_count() >= 1, "far door counted as skipped")
		far.get_parent().remove_child(far)
		far.free()

	# ---- clear() and the off/asset-missing negative controls ---------------
	nav.clear()
	await _frames(3)
	_check(nav.status() == "off", "clear() returns the runtime to off")
	_check(nav.link_count() == 0, "clear() removes every baked link")
	_check(nav.region() == null, "clear() removes the region")
	_check(NavigationServer3D.map_get_regions(map).is_empty(), "navigation map has no region after clear")

	# Per-map assets: Old Manor and FTUE build from their own binary (counts
	# measured by the N-P0 producer); no sync/path test for those maps yet.
	for spec: Array in [["old_manor", 9059, 64, 15], ["ftue", 5576, 4, 0]]:
		var other_map := str(spec[0])
		var other = NavRuntimeScript.new()
		host.add_child(other)
		var other_ok: bool = other.setup(other_map)
		_check(other_ok, "nav_runtime.setup(%s)" % other_map)
		if other_ok:
			_check(other.navmesh().get_polygon_count() == int(spec[1]), "%s walkable polys == %d" % [other_map, int(spec[1])])
			_check(other.link_count() == int(spec[2]), "%s links == %d" % [other_map, int(spec[2])])
			_check(other.bidirectional_link_count() == int(spec[3]), "%s bidirectional links == %d" % [other_map, int(spec[3])])
		other.clear()
		other.queue_free()
		await _frames(2)
	_check(NavigationServer3D.map_get_regions(map).is_empty(), "navigation map has no region after the per-map checks")
	OS.set_environment("TAT2_NAV", "off")
	var off_nav = NavRuntimeScript.new()
	host.add_child(off_nav)
	var off_built: bool = off_nav.setup("guildhall")
	_check(not off_built and off_nav.status() == "disabled", "TAT2_NAV=off builds nothing (state %s)" % off_nav.status())
	off_nav.clear()
	off_nav.queue_free()
	OS.set_environment("TAT2_NAV", "on")
	OS.set_environment("TAT2_NAV_DIR", "/tmp/opencode/nav-runtime-probe-empty")
	var miss_nav = NavRuntimeScript.new()
	host.add_child(miss_nav)
	var miss_built: bool = miss_nav.setup("guildhall")
	_check(not miss_built and miss_nav.status() == "assets_missing", "missing assets fail closed (state %s)" % miss_nav.status())
	miss_nav.clear()
	miss_nav.queue_free()

	_quit_with_summary()


func _make_prison_doors(host: Node3D, mid: Vector3, normal: Vector3) -> Array:
	var basis := Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), normal)
	var out: Array = []
	for dz: float in [1.0, -1.0]:
		var d := FakeDoor.new()
		d.name = "PrisonFake_%s" % ("a" if dz > 0.0 else "b")
		d.door_entry = {"actor": PRISON_ACTOR}
		d.transform = Transform3D(basis, mid + Vector3(0.0, 0.0, dz))
		host.add_child(d)
		d.add_to_group("swinging_doors")
		out.append(d)
	return out


func _door_link(nav) -> NavigationLink3D:
	for c: Node in nav.get_children():
		if c is NavigationLink3D and str(c.name).begins_with("DoorLink_"):
			return c as NavigationLink3D
	return null


func _path(map: RID, a: Vector3, b: Vector3) -> Dictionary:
	var sa := NavigationServer3D.map_get_closest_point(map, a)
	var sb := NavigationServer3D.map_get_closest_point(map, b)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, sa, sb, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var reach := path[path.size() - 1].distance_to(sb) if path.size() > 0 else INF
	return {
		"waypoints": path.size(),
		"length": length,
		"straight": sa.distance_to(sb),
		"snap_a": sa.distance_to(a),
		"snap_b": sb.distance_to(b),
		"reach": reach,
	}


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _door_record(level_path: String, actor: String) -> Dictionary:
	var doc := _read_json(level_path)
	if doc.is_empty():
		return {}
	var centre := Vector3.ZERO
	var normal := Vector3.ZERO
	var n := 0
	for rec_v: Variant in doc.get("swinging_doors", []):
		var dr: Dictionary = rec_v
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
	return {"pos": centre / float(n), "normal": normal.normalized()}


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var doc: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return doc if typeof(doc) == TYPE_DICTIONARY else {}


func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	for a: String in OS.get_cmdline_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _quit_with_summary() -> void:
	print("NAV_RUNTIME_PROBE checks=%d fails=%d" % [checks, fails])
	quit(0 if fails == 0 else 1)
