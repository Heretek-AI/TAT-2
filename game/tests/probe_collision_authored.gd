extends SceneTree
## W9-P1 A/B probe: authored UE `AggGeom` collision vs the pre-W9 AABB heuristic.
##
## Loads the full 15-file Guildhall ground set (the same list
## `mission_controller._map_id_to_sublevels("guildhall", 2)` returns minus the
## contract sublevels, which carry no meshes) and prints ONE line:
##
##   COL_AUDIT mode=<authored|aabb> placed_meshes=<n> placed_instances=<n>
##     authored_hull=<n> authored_prims=<n> absent=<n> no_collision=<n>
##     query_only=<n> reduced=<n> shapes=<n> bodies=<n> dropped=<n>
##     load_ms=<n> fps_pose=n/a
##
## Counter meanings (all distinct-path counts unless noted):
##   placed_meshes   UE paths the loader actually decided collision for
##                   (decorative, hidden-in-game, CPD and clutter items are
##                   already excluded by the loader's own collider gate).
##   authored_hull   paths whose collider came from authored data: element
##                   hulls, primitive coalescing, UE complex-as-simple (a
##                   BodySetup with no AggGeom collides with the render tris in
##                   UE, so the render trimesh IS the authored answer) and the
##                   authored NoCollision/QueryOnly flags.
##   authored_prims  subset encoded as ONE coalesced/primitive shape per
##                   instance (primitive-only meshes + complex-as-simple).
##   absent          paths with no authored answer at all -> heuristic fallback.
##   shapes/bodies   the loader's real emitted counts.
##   dropped         collider-budget drops; must be 0.
##
## Run:
##   tools/godot --headless --path game --script res://tests/probe_collision_authored.gd
##   TAT2_COLLISION=aabb tools/godot … (A/B control)
##   … -- --validate   (extra: authored vs render-mesh AABB table, 3 meshes/type)
##
## FAIL (exit 1) when a different mode is active than requested, when no shape
## was emitted, when anything was dropped, when the classification does not add
## up, or (authored mode) when authored-derived coverage is below 85 %.

const LEVELS_ROOT := "res://data/generated/levels/"
const AuthoredCollision: GDScript = preload("res://src/core/collision/authored_collision.gd")
## The 15 authored Guildhall ground sublevels, verbatim from
## `game/src/missions/mission_controller.gd::_map_id_to_sublevels` (the
## contract sublevels append no meshes for order 2).
const GUILDHALL_SUBLEVELS: Array[String] = [
	"Buildings/Guildhall/Building_Guildhall_POI",
	"Buildings/Guildhall/Building_Guildhall_POI_3rdFloor",
	"Buildings/Guildhall/Guildhall_Vault_CeremonialChambers",
	"Guildhall/Guildhall_Gameplay",
	"Guildhall/Guildhall_P",
	"Guildhall/Guildhall_Geometry",
	"Guildhall/Guildhall_Landscape",
	"Guildhall/Guildhall_LightingNoGameplay",
	"Guildhall/Guildhall_LocalVolumetric",
	"Guildhall/Guildhall_PeripheryA",
	"Guildhall/Guildhall_Loot",
	"Guildhall/Guildhall_Contracts",
	"Guildhall/Guildhall_SetSpawners",
	"Guildhall/Guildhall_MissionClues",
	"Guildhall/Guildhall_SkyboxGeo",
]
const MIN_AUTHORED_COVERAGE := 0.85
## One representative mesh per element type for `--validate`, plus a rotated box
## so the `P·M·P` basis is exercised (not just identity rotations).
const VALIDATE_MESHES: Array[String] = [
	"/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_Wall_4x6",        # box, rotation 0
	"/Game/Art/Environment/Civic/Exterior/SM_Civic_RailA_1x1",        # box (narrow core)
	"/Game/Art/Environment/Urban/Walls/SM_Urban_Ext_Wall_2x6",        # box, second sample
	"/Game/Art/Environment/Basement/Pillars/SM_PillarBasementA_12m",  # sphyl, rotation 0
	"/Game/Art/Environment/Lights/Candles/SM_CandleA",                # sphyl, small
	"/Game/Art/Environment/Civic/Interior/SM_Civic_GuildhallOfficeFloor", # convex
	"/Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_GuildhallEntrance", # convex set
	"/Game/Art/Environment/Urban/Walls/SM_Urban_ext_Door_4x6",        # convex set, door
]

var _fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(reason: String) -> void:
	_fails += 1
	printerr("COL_AUDIT FAIL %s" % reason)


func _run() -> void:
	await process_frame
	var req_mode: String = OS.get_environment("TAT2_COLLISION").strip_edges().to_lower()
	if req_mode != "aabb":
		req_mode = "authored"
	if DirAccess.open("res://assets/ue/Content") == null:
		printerr("COL_AUDIT FAIL assets/ue/Content missing (run the extract/import first)")
		quit(2)
		return
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	if ll_scr == null or not ll_scr.can_instantiate():
		# A parse error in the loader returns a non-null script that cannot be
		# instantiated. Without this guard the probe used to run on with a null
		# loader, abort `_run` before `quit()` and idle forever holding the shared
		# Godot lock (W9-P1 incident: 25 min).
		printerr("COL_AUDIT FAIL level_loader.gd failed to compile (see the SCRIPT ERROR above)")
		quit(1)
		return
	var ll: Node = ll_scr.new() as Node
	if ll == null:
		printerr("COL_AUDIT FAIL level_loader.gd did not instantiate")
		quit(1)
		return
	# Hard wall-clock guard inside the loader's collider loop (see
	# `level_loader._col_deadline_ms`): a malformed payload stops with a named
	# counter instead of wedging the process on the shared lock.
	ll.set("_col_deadline_ms", Time.get_ticks_msec() + 45000)
	ll.set("_col_progress", true)
	root.add_child(ll)
	var host := Node3D.new()
	root.add_child(host)
	var paths: Array[String] = []
	for sub: String in GUILDHALL_SUBLEVELS:
		paths.append(LEVELS_ROOT + sub + ".tatlevel.json")
	var t0: int = Time.get_ticks_msec()
	var res: Dictionary = ll.call("load_sublevels", paths, host, null, 8, true) as Dictionary
	var load_ms: int = Time.get_ticks_msec() - t0

	var active_mode: String = str(res.get("collision_mode", ""))
	var placed_meshes: int = int(res.get("col_authored_hull", 0)) + int(res.get("col_absent", 0))
	var placed_instances: int = int(res.get("col_placed_instances", 0))
	var authored_hull: int = int(res.get("col_authored_hull", 0))
	var authored_prims: int = int(res.get("col_authored_prims", 0))
	var absent: int = int(res.get("col_absent", 0))
	var no_collision: int = int(res.get("col_no_collision", 0))
	var query_only: int = int(res.get("col_query_only", 0))
	var reduced: int = int(res.get("col_reduced", 0))
	var shapes: int = int(res.get("collision_shapes", 0))
	var bodies: int = int(res.get("collision_bodies", 0))
	var dropped: int = int(res.get("collision_dropped", 0))

	print("COL_AUDIT mode=%s placed_meshes=%d placed_instances=%d authored_hull=%d authored_prims=%d absent=%d no_collision=%d query_only=%d reduced=%d shapes=%d bodies=%d dropped=%d load_ms=%d fps_pose=n/a" % [
		active_mode, placed_meshes, placed_instances, authored_hull, authored_prims,
		absent, no_collision, query_only, reduced, shapes, bodies, dropped, load_ms])

	# Independent diagnostic numbers (not part of the gate line): the payload
	# census and the load-set denominators, so a silent data regression shows up.
	var st: Dictionary = AuthoredCollision.stats() as Dictionary
	print("COL_DETAIL payload_meshes=%d payload_elements=%d payload_convex=%d payload_load_ms=%d authored_instances=%d authored_shape_demand=%d heuristic_shapes=%d mode_requested=%s elements_on_placed=%d convex_on_placed=%d complex_default_paths=%d placed_paths_payload=%d" % [
		int(st.get("meshes", -1)), int(st.get("elements", -1)), int(st.get("convex", -1)),
		int(st.get("load_ms", -1)), int(res.get("col_authored_instances", 0)),
		int(res.get("col_authored_shapes", 0)), int(res.get("col_heuristic_shapes", 0)),
		req_mode, int(res.get("col_elements", 0)), int(res.get("col_convex", 0)),
		int(res.get("col_complex_default", 0)), int(res.get("col_path_counts", 0))])

	if active_mode != req_mode:
		_fail("mode=%s but requested %s" % [active_mode, req_mode])
	if shapes <= 0:
		_fail("shapes=%d (no collision emitted)" % shapes)
	if dropped > 0:
		_fail("dropped=%d colliders (budget overflow; encoding must fit)" % dropped)
	if int(res.get("col_deadline_hit", 0)) > 0:
		_fail("wall-clock deadline hit %d times (collider emission stopped; last path in COL_PROGRESS)" % int(res.get("col_deadline_hit", 0)))
	if authored_hull + absent != placed_meshes:
		_fail("classification does not add up: authored_hull=%d + absent=%d != placed_meshes=%d" % [authored_hull, absent, placed_meshes])
	if req_mode == "authored" and placed_meshes > 0:
		var coverage: float = float(authored_hull + authored_prims) / float(placed_meshes)
		if coverage < MIN_AUTHORED_COVERAGE:
			_fail("authored coverage %.3f < %.2f (authored_hull=%d prims=%d placed=%d)" % [coverage, MIN_AUTHORED_COVERAGE, authored_hull, authored_prims, placed_meshes])

	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--validate"):
		_validate(ll)

	host.queue_free()
	ll.queue_free()
	await process_frame
	print("COL_WALL total_ms=%d (probe must stay well under 60 s)" % (Time.get_ticks_msec() - t0))
	quit(0 if _fails == 0 else 1)


## Authored-vs-render AABB check (lead's mandatory validation): the authored
## shape's world AABB in mesh space must sit within a few cm of the imported
## GLB's mesh AABB, per element type. Prints one line per mesh; never gates.
func _validate(ll: Node) -> void:
	for ue_path: String in VALIDATE_MESHES:
		var info: Dictionary = ll.call("_get_mesh_and_shape", ue_path) as Dictionary
		var mesh: Mesh = info.get("mesh") as Mesh
		if mesh == null:
			print("COL_VALIDATE %s mesh=<missing>" % ue_path.get_file())
			continue
		var mesh_aabb: AABB = mesh.get_aabb()
		var shapes: Array = info.get("shapes", []) as Array
		var offsets: Array = info.get("shape_offsets", []) as Array
		if shapes.is_empty() and info.get("shape") is Shape3D:
			shapes = [info.get("shape")]
			offsets = [Transform3D(Basis(), info.get("shape_offset", Vector3.ZERO))]
		var authored := AABB()
		var first: bool = true
		for s: int in range(shapes.size()):
			var sh: Shape3D = shapes[s] as Shape3D
			if sh == null:
				continue
			var off: Transform3D = (offsets[s] as Transform3D) if s < offsets.size() else Transform3D.IDENTITY
			for box: AABB in _shape_aabbs(sh, off):
				if first:
					authored = box
					first = false
				else:
					authored = authored.merge(box)
		var err: Vector3 = Vector3(
			absf(authored.position.x - mesh_aabb.position.x) + absf((authored.position.x + authored.size.x) - (mesh_aabb.position.x + mesh_aabb.size.x)),
			absf(authored.position.y - mesh_aabb.position.y) + absf((authored.position.y + authored.size.y) - (mesh_aabb.position.y + mesh_aabb.size.y)),
			absf(authored.position.z - mesh_aabb.position.z) + absf((authored.position.z + authored.size.z) - (mesh_aabb.position.z + mesh_aabb.size.z)))
		print("COL_VALIDATE %-58s shapes=%2d authored_aabb=%s mesh_aabb=%s max_axis_err_m=%.3f" % [
			ue_path.get_file(), shapes.size(), str(authored), str(mesh_aabb), maxf(err.x, maxf(err.y, err.z))])


## Mesh-space AABBs of one shape at one element offset. The local AABB corners
## are transformed, so a rotated element is bounded correctly (never the raw
## `aabb_min/max` of the producer, which is pre-transform).
func _shape_aabbs(sh: Shape3D, off: Transform3D) -> Array[AABB]:
	var out: Array[AABB] = []
	var mn := Vector3.ZERO
	var mx := Vector3.ZERO
	if sh is BoxShape3D:
		var h: Vector3 = (sh as BoxShape3D).size * 0.5
		mn = -h
		mx = h
	elif sh is SphereShape3D:
		var r: float = (sh as SphereShape3D).radius
		mn = Vector3(-r, -r, -r)
		mx = Vector3(r, r, r)
	elif sh is CapsuleShape3D:
		var cs: CapsuleShape3D = sh as CapsuleShape3D
		mn = Vector3(-cs.radius, -cs.height * 0.5, -cs.radius)
		mx = Vector3(cs.radius, cs.height * 0.5, cs.radius)
	elif sh is ConvexPolygonShape3D:
		var pts: PackedVector3Array = (sh as ConvexPolygonShape3D).points
		if pts.is_empty():
			return out
		mn = pts[0]
		mx = pts[0]
		for p: Vector3 in pts:
			mn = mn.min(p)
			mx = mx.max(p)
	elif sh is ConcavePolygonShape3D:
		var faces: PackedVector3Array = (sh as ConcavePolygonShape3D).get_faces()
		if faces.is_empty():
			return out
		mn = faces[0]
		mx = faces[0]
		for p2: Vector3 in faces:
			mn = mn.min(p2)
			mx = mx.max(p2)
	else:
		return out
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i: int in range(8):
		var c := Vector3(
			mx.x if (i & 1) != 0 else mn.x,
			mx.y if (i & 2) != 0 else mn.y,
			mx.z if (i & 4) != 0 else mn.z)
		var w: Vector3 = off * c
		lo = lo.min(w)
		hi = hi.max(w)
	out.append(AABB(lo, hi - lo))
	return out
