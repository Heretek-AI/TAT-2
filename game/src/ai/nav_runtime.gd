extends Node3D
## N-P1: authored Recast navmesh runtime (behind `TAT2_NAV=off|on`, default off).
##
## The shipped game carries a cooked `ARecastNavMesh` per map; `tools/parse_nav.py`
## turns the extractor's decoded tiles into `game/data/generated/nav/<map>.nav.bin`
## plus a manifest. This node builds one `NavigationMesh` / `NavigationRegion3D`
## from that authored data and exposes the off-mesh connections as
## `NavigationLink3D`s. It never bakes from collision: the authored tile set
## already carries the tile borders, area ids, agent parameters and links.
##
## Contract:
##   * `setup(map_id)` returns false and changes nothing when the feature is off,
##     when the map has no generated asset, or when the asset is malformed. The
##     caller keeps the existing straight-line `nav_steering` degradation.
##   * `wait_ready()` waits until the navigation server has committed at least one
##     region and a mesh point is queryable. The mission calls it before guards
##     spawn so an AI's first `step_towards` sees a ready map.
##   * `register_swinging_doors()` adds one bidirectional door link per authored
##     door actor (leaf midpoint + normal); the link is enabled only while every
##     leaf of that actor is open past 70 degrees. The co-located
##     `NavLinkFront/Back` actors are not used.
##   * `clear()` removes the region and every link; it is called on contract
##     start and teardown so a reload cannot stack regions.
##
## Authored numbers this consumer relies on (measured, navmesh-spike.md):
## Guildhall 2,958 tiles / 14,709 walkable polys / 30,918 unique verts /
## 221 off-mesh records -> 80 logical links (35 bidirectional); Old Manor
## 1,469 / 9,059 / 17,643 / 216 -> 64; FTUE 1,558 / 5,576 / 11,711 / 11 -> 4.
## Area ids are per-map (`NavArea_Default` is 63 and is walkable, never null;
## Old Manor has Door=3 / Bushes=4, Guildhall and FTUE Door=4 / Bushes=3).

const DEFAULT_NAV_DIR := "res://data/generated/nav"
const MANIFEST_FILE := "manifest.json"
const MAGIC := "TAT2NAV1"
const FORMAT_VERSION := 1

## Consumer settings for the authored centimetre mesh. The default 0.25 m map
## cell would quantise the authored edges away; these are not authored fields.
const MAP_CELL_SIZE_M := 0.01
const MAP_EDGE_MARGIN_M := 0.05
const MAP_LINK_RADIUS_M := 1.0

## The spike measured 1.0-1.5 s / ~67-92 physics frames for 14.7k polys. Five
## seconds is a fail-closed ceiling: a map that never commits must not hold the
## mission before guards forever.
const READY_MAX_FRAMES := 300

## Door links: the authored leaf midpoint is the opening centre; the leaf
## normal is the door plane normal. Endpoints sit +/-2.2 m across the opening
## (the measured doorway sample in navmesh-spike.md; a 1.25 m offset stays
## inside a thick prison-wall opening and snaps to the near-side poly) and are
## snapped to the navmesh; a side that misses the mesh by >2.5 m skips the
## whole door (fail closed, no floating link).
const DOOR_OPEN_DEG := 70.0
const DOOR_SIDE_M := 2.2
const DOOR_SNAP_LIMIT_M := 2.5

const STATE_OFF := "off"
const STATE_DISABLED := "disabled"
const STATE_ASSETS_MISSING := "assets_missing"
const STATE_MAP_MISSING := "map_missing"
const STATE_BAD_ASSET := "bad_asset"
const STATE_BUILT := "built"
const STATE_READY := "ready"
const STATE_SYNC_TIMEOUT := "sync_timeout"

var _state: String = STATE_OFF
var _map_id: String = ""
var _nav_dir: String = DEFAULT_NAV_DIR
var _region: NavigationRegion3D = null
var _navmesh: NavigationMesh = null
var _links: Array[NavigationLink3D] = []
var _door_links: Array[Dictionary] = []
var _baked_bidirectional: int = 0
var _baked_one_way: int = 0
var _door_groups: int = 0
var _door_skipped: int = 0
var _door_toggles: int = 0
var _build_ms: int = 0
var _ready_frames: int = 0
var _ready_ms: int = 0
var _last_warning: String = ""
var _warned_assets: bool = false


## `TAT2_NAV` is the documented switch. Anything except the four accepted
## truthy spellings keeps the feature off, including an absent variable.
static func is_enabled() -> bool:
	var v := OS.get_environment("TAT2_NAV").strip_edges().to_lower()
	return v == "on" or v == "1" or v == "true" or v == "yes"


func setup(map_id: String) -> bool:
	var started := Time.get_ticks_msec()
	_map_id = map_id
	if not is_enabled():
		_state = STATE_DISABLED
		return false
	var env_dir := OS.get_environment("TAT2_NAV_DIR").strip_edges()
	if env_dir != "":
		_nav_dir = env_dir
	var manifest_path := _nav_dir.path_join(MANIFEST_FILE)
	if not FileAccess.file_exists(manifest_path):
		_warn_once("no generated nav manifest at %s (run tools/parse_nav.py); AI keeps straight-line steering" % manifest_path)
		_state = STATE_ASSETS_MISSING
		return false
	var manifest_v: Variant = JSON.parse_string(_read_text(manifest_path))
	if typeof(manifest_v) != TYPE_DICTIONARY:
		_warn_once("nav manifest is not a JSON object: %s" % manifest_path)
		_state = STATE_BAD_ASSET
		return false
	var manifest: Dictionary = manifest_v
	if str(manifest.get("schema", "")) != "tat2.nav/1":
		_warn_once("nav manifest schema %s != tat2.nav/1" % str(manifest.get("schema", "")))
		_state = STATE_BAD_ASSET
		return false
	var maps: Dictionary = manifest.get("maps", {})
	var entry_v: Variant = maps.get(map_id, null)
	if typeof(entry_v) != TYPE_DICTIONARY:
		_warn_once("nav manifest has no map '%s' (%s)" % [map_id, manifest_path])
		_state = STATE_MAP_MISSING
		return false
	var entry: Dictionary = entry_v
	var bin_name := str(entry.get("file", ""))
	if bin_name == "":
		_warn_once("nav manifest map '%s' has no file" % map_id)
		_state = STATE_BAD_ASSET
		return false
	var bin_path := _nav_dir.path_join(bin_name)
	var parsed := _read_bin(bin_path)
	if parsed.is_empty():
		_state = STATE_BAD_ASSET
		return false

	var expected_polys := int(entry.get("polys", -1))
	var expected_verts := int(entry.get("verts", -1))
	var polys: Array = parsed["polygons"]
	var verts: PackedVector3Array = parsed["vertices"]
	if expected_polys >= 0 and polys.size() != expected_polys:
		_warn_once("nav binary %s has %d polys, manifest says %d" % [bin_path, polys.size(), expected_polys])
		_state = STATE_BAD_ASSET
		return false
	if expected_verts >= 0 and verts.size() != expected_verts:
		_warn_once("nav binary %s has %d verts, manifest says %d" % [bin_path, verts.size(), expected_verts])
		_state = STATE_BAD_ASSET
		return false

	_navmesh = NavigationMesh.new()
	_navmesh.vertices = verts
	var cfg: Dictionary = entry.get("nav_data_config", {})
	for poly_v: Variant in polys:
		_navmesh.add_polygon(poly_v as PackedInt32Array)
	_navmesh.agent_radius = float(cfg.get("agent_radius_cm", 45.0)) * 0.01
	_navmesh.agent_height = float(cfg.get("agent_height_cm", 240.0)) * 0.01
	_navmesh.agent_max_climb = float(cfg.get("agent_step_height_cm", 45.0)) * 0.01

	var map_rid := _map_rid()
	if not map_rid.is_valid():
		_warn_once("nav runtime has no world navigation map")
		_state = STATE_BAD_ASSET
		return false
	# Set the consumer cell/margin before the region enters the server map: the
	# authored edges are centimetre-scale and the default 0.25 m cell would
	# quantise them away before the first commit.
	NavigationServer3D.map_set_cell_size(map_rid, MAP_CELL_SIZE_M)
	NavigationServer3D.map_set_edge_connection_margin(map_rid, MAP_EDGE_MARGIN_M)
	NavigationServer3D.map_set_link_connection_radius(map_rid, MAP_LINK_RADIUS_M)

	_region = NavigationRegion3D.new()
	_region.name = "NavRegion_%s" % map_id
	_region.navigation_mesh = _navmesh
	_region.top_level = true
	add_child(_region)

	for link_v: Variant in parsed["links"]:
		var link_def: Dictionary = link_v
		var link := NavigationLink3D.new()
		link.name = "NavLink_%d" % _links.size()
		link.bidirectional = bool(link_def.get("bidirectional", false))
		link.navigation_layers = 1
		link.top_level = true
		# Positions must be set BEFORE the link enters the tree: the server
		# registers the link on enter and does not re-read a post-enter position
		# write. top_level makes local == world for this authored mesh.
		link.start_position = _nav_to_world(link_def["a"])
		link.end_position = _nav_to_world(link_def["b"])
		link.enabled = true
		add_child(link)
		_links.append(link)
		if link.bidirectional:
			_baked_bidirectional += 1
		else:
			_baked_one_way += 1

	_build_ms = Time.get_ticks_msec() - started
	_state = STATE_BUILT
	return true


## Wait until the server has committed the region and a mesh point answers.
func wait_ready(max_frames: int = READY_MAX_FRAMES) -> bool:
	if _state != STATE_BUILT:
		return false
	var map_rid := _map_rid()
	if not map_rid.is_valid():
		return false
	var probe := _probe_point()
	var started := Time.get_ticks_msec()
	for i in range(max_frames):
		await get_tree().physics_frame
		_ready_frames = i + 1
		if NavigationServer3D.map_get_iteration_id(map_rid) == 0:
			continue
		if NavigationServer3D.map_get_regions(map_rid).is_empty():
			continue
		NavigationServer3D.map_force_update(map_rid)
		var closest := NavigationServer3D.map_get_closest_point(map_rid, probe)
		if closest.distance_to(probe) <= 1.0:
			_ready_ms = Time.get_ticks_msec() - started
			_state = STATE_READY
			return true
	_warn_once("nav map did not commit within %d frames (map=%s); AI keeps straight-line steering" % [max_frames, _map_id])
	_state = STATE_SYNC_TIMEOUT
	return false


## One link per authored door actor. The door nodes are the mission's real
## `SwingingDoor` instances (group `swinging_doors`), two of them per double
## door actor; the link centre is the leaf midpoint and the normal is the
## averaged authored leaf plane normal. Call after the doors have entered the
## tree and after `wait_ready()`.
func register_swinging_doors() -> int:
	if _state != STATE_READY:
		return 0
	# Rebuild from the current tree so a probe (or a reloaded mission) can call
	# this again after the authored doors change; the mission calls it once.
	_free_door_links()
	_door_groups = 0
	_door_skipped = 0
	var groups: Dictionary = {}
	for node_v: Node in get_tree().get_nodes_in_group("swinging_doors"):
		if not (node_v is Node3D) or not node_v.has_method("open_angle_deg"):
			continue
		var door := node_v as Node3D
		var entry_v: Variant = door.get("door_entry")
		var actor := str(door.name)
		if typeof(entry_v) == TYPE_DICTIONARY:
			var actor_v: Variant = (entry_v as Dictionary).get("actor", "")
			if str(actor_v) != "":
				actor = str(actor_v)
		if not groups.has(actor):
			groups[actor] = []
		(groups[actor] as Array).append(door)
	_door_groups = groups.size()
	var map_rid := _map_rid()
	var made := 0
	for actor_v: Variant in groups.keys():
		var actor := str(actor_v)
		var doors: Array = groups[actor_v]
		var mid := Vector3.ZERO
		var normal := Vector3.ZERO
		for door_v: Variant in doors:
			var door := door_v as Node3D
			mid += door.global_position
			var n := door.global_transform.basis.z
			n.y = 0.0
			if n.length() < 0.001:
				continue
			n = n.normalized()
			if normal.length() > 0.001 and normal.dot(n) < 0.0:
				n = -n
			normal += n
		if doors.is_empty() or normal.length() < 0.001:
			_door_skipped += 1
			continue
		mid /= float(doors.size())
		normal = normal.normalized()
		var a := mid + normal * DOOR_SIDE_M
		var b := mid - normal * DOOR_SIDE_M
		var sa := NavigationServer3D.map_get_closest_point(map_rid, a)
		var sb := NavigationServer3D.map_get_closest_point(map_rid, b)
		if sa.distance_to(a) > DOOR_SNAP_LIMIT_M or sb.distance_to(b) > DOOR_SNAP_LIMIT_M:
			_door_skipped += 1
			continue
		var link := NavigationLink3D.new()
		link.name = "DoorLink_%s" % actor.replace("/", "_")
		link.bidirectional = true
		link.navigation_layers = 1
		link.top_level = true
		# Same pre-enter position contract as the baked links; `sa`/`sb` are
		# already snapped to the navmesh and are world coordinates.
		link.start_position = sa
		link.end_position = sb
		link.enabled = _doors_open(doors)
		add_child(link)
		_door_links.append({"link": link, "doors": doors, "actor": actor})
		made += 1
	if not _door_links.is_empty():
		set_physics_process(true)
	print("NAV_DOORS groups=%d links=%d skipped=%d open_now=%d" % [
		_door_groups, made, _door_skipped, _open_door_link_count()
	])
	return made


func _physics_process(_delta: float) -> void:
	for rec: Dictionary in _door_links:
		var link: NavigationLink3D = rec.get("link", null) as NavigationLink3D
		if link == null or not is_instance_valid(link):
			continue
		var open := _doors_open(rec.get("doors", []) as Array)
		if link.enabled != open:
			link.enabled = open
			_door_toggles += 1


func _free_door_links() -> void:
	for rec: Dictionary in _door_links:
		var link: NavigationLink3D = rec.get("link", null) as NavigationLink3D
		_free_node(link)
	_door_links.clear()


func _doors_open(doors: Array) -> bool:
	if doors.is_empty():
		return false
	for door_v: Variant in doors:
		if not (door_v is Node) or not is_instance_valid(door_v):
			return false
		if float((door_v as Node).call("open_angle_deg")) <= DOOR_OPEN_DEG:
			return false
	return true


func _open_door_link_count() -> int:
	var n := 0
	for rec: Dictionary in _door_links:
		var link: NavigationLink3D = rec.get("link", null) as NavigationLink3D
		if link != null and is_instance_valid(link) and link.enabled:
			n += 1
	return n


## Remove the region and every link. Safe to call twice; called at contract
## start and on teardown so a reload cannot stack navigation regions.
func clear() -> void:
	set_physics_process(false)
	for link: NavigationLink3D in _links:
		_free_node(link)
	_links.clear()
	for rec: Dictionary in _door_links:
		var door_link: NavigationLink3D = rec.get("link", null) as NavigationLink3D
		_free_node(door_link)
	_door_links.clear()
	if _region != null and is_instance_valid(_region):
		_region.navigation_mesh = null
		_free_node(_region)
	_region = null
	_navmesh = null
	_baked_bidirectional = 0
	_baked_one_way = 0
	_door_groups = 0
	_door_skipped = 0
	_door_toggles = 0
	_ready_frames = 0
	_ready_ms = 0
	_build_ms = 0
	_state = STATE_OFF


func status() -> String:
	return _state


func map_id() -> String:
	return _map_id


func region() -> NavigationRegion3D:
	return _region


func navmesh() -> NavigationMesh:
	return _navmesh


func link_count() -> int:
	return _links.size()


func bidirectional_link_count() -> int:
	return _baked_bidirectional


func one_way_link_count() -> int:
	return _baked_one_way


func door_link_count() -> int:
	return _door_links.size()


func door_group_count() -> int:
	return _door_groups


func door_skipped_count() -> int:
	return _door_skipped


func door_toggle_count() -> int:
	return _door_toggles


func build_ms() -> int:
	return _build_ms


func ready_frames() -> int:
	return _ready_frames


func ready_ms() -> int:
	return _ready_ms


func last_warning() -> String:
	return _last_warning


func report() -> Dictionary:
	return {
		"state": _state,
		"map_id": _map_id,
		"nav_dir": _nav_dir,
		"polys": 0 if _navmesh == null else _navmesh.get_polygon_count(),
		"verts": 0 if _navmesh == null else _navmesh.get_vertices().size(),
		"links": _links.size(),
		"links_bidirectional": _baked_bidirectional,
		"links_one_way": _baked_one_way,
		"door_groups": _door_groups,
		"door_links": _door_links.size(),
		"door_skipped": _door_skipped,
		"door_toggles": _door_toggles,
		"build_ms": _build_ms,
		"ready_frames": _ready_frames,
		"ready_ms": _ready_ms,
		"last_warning": _last_warning,
	}


# --------------------------------------------------------------- asset reading
func _read_bin(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_warn_once("nav binary missing: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_warn_once("cannot open nav binary: %s" % path)
		return {}
	var magic := f.get_buffer(8).get_string_from_ascii()
	if magic != MAGIC:
		f.close()
		_warn_once("nav binary magic %s != %s: %s" % [magic, MAGIC, path])
		return {}
	var version := f.get_32()
	if version != FORMAT_VERSION:
		f.close()
		_warn_once("nav binary version %d != %d: %s" % [version, FORMAT_VERSION, path])
		return {}
	var vert_count := f.get_32()
	var poly_count := f.get_32()
	var link_count := f.get_32()
	if vert_count <= 0 or vert_count > 4000000 or poly_count <= 0 or poly_count > 4000000 or link_count > 100000:
		f.close()
		_warn_once("nav binary counts out of range (%d verts, %d polys, %d links): %s" % [vert_count, poly_count, link_count, path])
		return {}
	var verts := PackedVector3Array()
	verts.resize(vert_count)
	for i in range(vert_count):
		verts[i] = Vector3(_read_i32(f) * 0.01, _read_i32(f) * 0.01, -_read_i32(f) * 0.01)
	var polys: Array[PackedInt32Array] = []
	polys.resize(poly_count)
	for pi in range(poly_count):
		var n := f.get_8()
		if n < 3 or n > 6:
			f.close()
			_warn_once("nav binary poly %d has %d verts (3..6 required): %s" % [pi, n, path])
			return {}
		var poly := PackedInt32Array()
		poly.resize(n)
		var good := true
		for k in range(n):
			var idx := f.get_16()
			if idx >= vert_count:
				good = false
			poly[k] = idx
		if not good:
			f.close()
			_warn_once("nav binary poly %d has an out-of-range vertex: %s" % [pi, path])
			return {}
		polys[pi] = poly
	for _pi in range(poly_count):
		var area := f.get_8()
		if area == 0:
			f.close()
			_warn_once("nav binary poly area 0 (NavArea_Null) is not walkable: %s" % path)
			return {}
	var links: Array[Dictionary] = []
	for li in range(link_count):
		var a := Vector3i(_read_i32(f), _read_i32(f), _read_i32(f))
		var b := Vector3i(_read_i32(f), _read_i32(f), _read_i32(f))
		var radius := f.get_16()
		var height := f.get_16()
		var bidir := f.get_8()
		var flags := f.get_8()
		var records := f.get_16()
		if a == b:
			f.close()
			_warn_once("nav binary link %d has identical endpoints: %s" % [li, path])
			return {}
		links.append({
			"a": a, "b": b, "radius": radius, "height": height,
			"bidirectional": bidir != 0, "flags": flags, "records": records,
		})
	if f.get_position() != f.get_length():
		f.close()
		_warn_once("nav binary has trailing bytes (%d != %d): %s" % [f.get_position(), f.get_length(), path])
		return {}
	f.close()
	return {"vertices": verts, "polygons": polys, "links": links}


static func _read_i32(f: FileAccess) -> int:
	var raw := f.get_32()
	return raw - 0x100000000 if (raw & 0x80000000) != 0 else raw


static func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


static func _nav_to_world(cm: Vector3i) -> Vector3:
	# Nav space is Recast Y-up centimetres; the port maps it to Godot metres
	# with (x, y, -z), matching parse_tables.ue_mat4_to_godot_trs.
	return Vector3(cm.x * 0.01, cm.y * 0.01, -cm.z * 0.01)


func _probe_point() -> Vector3:
	if _navmesh == null or _navmesh.get_polygon_count() == 0:
		return Vector3.ZERO
	var poly := _navmesh.get_polygon(0)
	var verts := _navmesh.get_vertices()
	if poly.size() == 0:
		return Vector3.ZERO
	var p := Vector3.ZERO
	for idx in poly:
		p += verts[idx]
	return p / float(poly.size())


func _map_rid() -> RID:
	if not is_inside_tree() or get_world_3d() == null:
		return RID()
	return get_world_3d().navigation_map


func _warn_once(msg: String) -> void:
	_last_warning = msg
	if _warned_assets:
		return
	_warned_assets = true
	push_warning("[nav_runtime] " + msg)


func _free_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()
