extends SceneTree
## W9-P1 A/B probe: authored UE `AggGeom` collision vs the pre-W9 AABB heuristic.
## W10-A: three authored map sets (Guildhall, OldManor, FTUE), per-map gates and
## the name of every reduced mesh.
##
## For each map it prints one line:
##
##   COL_MAP map=<id> files=<n> placed_meshes=<n> placed_instances=<n>
##     authored=<n> absent=<n> coverage=<f> reduced=<n> planar_skipped=<n>
##     drops=<n> shapes=<n> bodies=<n> load_ms=<n>
##
## then one line per reduced mesh (`COL_REDUCED`) and one assertion line:
##
##   COL_MAP_ASSERT map=<id> coverage>=0.950 dropped==0 coverage=<f>
##     dropped=<n> PASS|FAIL
##
## The Guildhall legacy lines are unchanged (backward compatible):
##
##   COL_AUDIT mode=<authored|aabb> placed_meshes=<n> placed_meshes_seen=<n>
##     placed_instances=<n> authored_hull=<n> authored_prims=<n> absent=<n>
##     no_collision=<n> query_only=<n> reduced=<n> shapes=<n> bodies=<n>
##     dropped=<n> load_ms=<n> coverage=<f> fps_pose=n/a
##   COL_DETAIL …   COL_ASSERT …   COL_WALL total_ms=<n> (whole probe)
##
## The probe ends with the line the gate ratchet reads:
##
##   COL_MAPS PASS maps=3 min_coverage=<f> dropped=0 planar_skipped=<n>
##     coverage_ppm=<n>
##
## Counter meanings (all distinct-path counts unless noted):
##   placed_meshes   the independent draw-item census (distinct collidable UE
##                   paths, counted before any classification). The identity
##                   `authored + absent == placed_meshes` and
##                   `coverage = authored / placed_meshes >= 0.95` are the
##                   per-map gates; `authored_prims` is a subset of `authored`
##                   and is asserted to be one.
##   authored        paths whose collider came from authored data: element
##                   hulls, primitive coalescing, UE complex-as-simple (a
##                   BodySetup with no AggGeom collides with the render tris in
##                   UE, so the render trimesh IS the authored answer) and the
##                   authored NoCollision/QueryOnly flags.
##   authored_prims  subset encoded as ONE coalesced/primitive shape per
##                   instance (primitive-only meshes + complex-as-simple).
##   absent          paths with no authored answer at all -> heuristic fallback.
##   reduced         paths coalesced to one trimesh by the element/cost cap;
##                   every one is named by a `COL_REDUCED` line.
##   planar_skipped  coplanar convex elements skipped by the W10-A D7 rule in
##                   THIS load (Δ of the process counter, snapshot per load).
##   shapes/bodies   the loader's real emitted counts.
##   drops           collider-budget drops; must be 0.
##
## Map sets are explicit file lists (never `_map_id_to_sublevels()` with its
## default order=2, which appends a Guildhall contract sublevel to an FTUE
## load). Guildhall = the 15 authored ground sublevels; OldManor = the 9 base
## sublevels; FTUE = the 10 base sublevels (no contract append: the tutorial
## route sets contract order 0). Each map gets a fresh host, a fresh loader and
## a fresh 45 s collider deadline, then is freed: the loader's per-instance mesh
## cache keys the reduction decision on ONE placement count, so sharing an
## instance across maps would report a mesh reduced by another map's count.
##
## Run:
##   tools/godot --headless --path game --script res://tests/probe_collision_authored.gd
##   TAT2_COLLISION=aabb tools/godot … (A/B control; coverage gate skipped)
##   … -- --validate   (extra: authored vs render-mesh AABB table, 3 meshes/type)
##
## FAIL (exit 1) when a different mode is active than requested, when any map
## emits no shape or classifies no placed mesh, when anything was dropped, when
## its classification does not add up, when fewer reduced meshes are named than
## counted, when the collider deadline was hit, or (authored mode) when a map's
## authored-derived coverage is below 95 %.

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
## The 9 authored OldManor base sublevels (mission_controller base list). No
## contract-only sublevel is appended: those files carry no static meshes except
## order 10's two FX quads, whose collision comes from the heuristic path either
## way, and this probe measures the base map the static replay predicted.
const OLDMANOR_SUBLEVELS: Array[String] = [
	"OldManor/OldManor_P",
	"OldManor/OldManor_Geo",
	"OldManor/OldManor_Landscape",
	"OldManor/OldManor_Gameplay",
	"OldManor/OldManor_Loot",
	"OldManor/OldManor_PickUps",
	"OldManor/OldManor_Clues",
	"OldManor/OldManor_Contracts",
	"OldManor/OldManor_SkyboxGeo",
]
## The 10 authored FTUE base sublevels (`GameData.get_ftue_sublevels()`). The
## FTUE route runs contract order 0, so `get_contract_sublevels(0)` is empty and
## the base list is the whole load.
const FTUE_SUBLEVELS: Array[String] = [
	"FTUE/FTUE_P",
	"FTUE/FTUE_Checkpoints",
	"FTUE/FTUE_AI",
	"FTUE/FTUE_Fairy",
	"FTUE/FTUE_TutorialRunner",
	"FTUE/FTUE_Building_JewelryStore",
	"FTUE/FTUE_Building_SpawnArea",
	"FTUE/FTUE_Gameplay",
	"FTUE/FTUE_Geometry",
	"FTUE/FTUE_Audio",
]
const MIN_AUTHORED_COVERAGE := 0.95
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
	var ll: Node = null
	var host: Node3D = null

	var maps: Array[Dictionary] = [
		{"id": "guildhall", "files": GUILDHALL_SUBLEVELS},
		{"id": "old_manor", "files": OLDMANOR_SUBLEVELS},
		{"id": "ftue", "files": FTUE_SUBLEVELS},
	]
	var probe_t0: int = Time.get_ticks_msec()
	var min_coverage: float = 1.0
	var total_planar: int = 0
	var maps_checked: int = 0
	for map_def: Dictionary in maps:
		var map_id: String = str(map_def["id"])
		# A fresh host, loader and wall-clock deadline per map. The loader keeps a
		# per-instance mesh/shape cache whose reduction decision is keyed by ONE
		# placement count, so reusing an instance across maps would report a mesh
		# reduced by another map's count (measured: OldManor 37 instead of 35,
		# FTUE 16 instead of 20). A production process loads one mission, so a
		# fresh loader per map is also the faithful unit.
		if host != null:
			host.queue_free()
			ll.queue_free()
			await process_frame
		var sublevels: Array = map_def["files"] as Array
		var paths: Array[String] = []
		for sub: String in sublevels:
			paths.append(LEVELS_ROOT + sub + ".tatlevel.json")
		host = Node3D.new()
		root.add_child(host)
		ll = ll_scr.new() as Node
		if ll == null:
			_fail("%s: level_loader.gd did not instantiate" % map_id)
			break
		ll.set("_col_progress", true)
		root.add_child(ll)
		ll.set("_col_deadline_ms", Time.get_ticks_msec() + 45000)
		var t0: int = Time.get_ticks_msec()
		var res: Dictionary = ll.call("load_sublevels", paths, host, null, 8, true) as Dictionary
		var load_ms: int = Time.get_ticks_msec() - t0

		var active_mode: String = str(res.get("collision_mode", ""))
		var placed_meshes: int = int(res.get("col_paths_seen", 0))
		var placed_instances: int = int(res.get("col_placed_instances", 0))
		var authored_hull: int = int(res.get("col_authored_hull", 0))
		var authored_prims: int = int(res.get("col_authored_prims", 0))
		var absent: int = int(res.get("col_absent", 0))
		var no_collision: int = int(res.get("col_no_collision", 0))
		var query_only: int = int(res.get("col_query_only", 0))
		var reduced: int = int(res.get("col_reduced", 0))
		var reduced_names: Array = res.get("col_reduced_names", []) as Array
		var planar_skipped: int = int(res.get("col_planar_skipped", 0))
		var planar_paths: Array = res.get("col_planar_paths", []) as Array
		var shapes: int = int(res.get("collision_shapes", 0))
		var bodies: int = int(res.get("collision_bodies", 0))
		var dropped: int = int(res.get("collision_dropped", 0))
		var coverage: float = 0.0 if placed_meshes <= 0 else float(authored_hull) / float(placed_meshes)
		var map_ok: bool = true

		if map_id == "guildhall":
			# Legacy W9-P1 lines, unchanged apart from `load_ms` being this map's.
			_emit_legacy_guildhall(active_mode, placed_meshes, authored_hull, authored_prims,
				absent, no_collision, query_only, reduced, shapes, bodies, dropped,
				load_ms, coverage, res)

		print("COL_MAP map=%s files=%d placed_meshes=%d placed_instances=%d authored=%d absent=%d coverage=%.3f reduced=%d planar_skipped=%d drops=%d shapes=%d bodies=%d load_ms=%d" % [
			map_id, paths.size(), placed_meshes, placed_instances, authored_hull, absent,
			coverage, reduced, planar_skipped, dropped, shapes, bodies, load_ms])
		# Deterministic order: the draw-item loop visits paths in cell order, which
		# must not make the evidence log row order vary between runs.
		var rows: Array = reduced_names.duplicate(true)
		rows.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str((a as Dictionary).get("path", "")) < str((b as Dictionary).get("path", "")))
		for row_var: Variant in rows:
			var row: Dictionary = row_var as Dictionary
			print("COL_REDUCED map=%s path=%s elements=%d instances=%d shapes=%d" % [
				map_id, str(row.get("path", "")), int(row.get("elements", 0)),
				int(row.get("instances", 0)), int(row.get("shapes", 0))])
		if not planar_paths.is_empty():
			var pnames: PackedStringArray = []
			for p_var: Variant in planar_paths:
				pnames.append(str(p_var))
			print("COL_PLANAR_LOAD map=%s skipped=%d paths=%s" % [
				map_id, planar_skipped, ",".join(pnames)])

		if active_mode != req_mode:
			_fail("%s: mode=%s but requested %s" % [map_id, active_mode, req_mode])
			map_ok = false
		if shapes <= 0:
			_fail("%s: shapes=%d (no collision emitted)" % [map_id, shapes])
			map_ok = false
		if placed_meshes <= 0:
			_fail("%s: placed_meshes=%d (no collidable path classified)" % [map_id, placed_meshes])
			map_ok = false
		if dropped > 0:
			_fail("%s: dropped=%d colliders (budget overflow; encoding must fit)" % [map_id, dropped])
			map_ok = false
		if int(res.get("col_deadline_hit", 0)) > 0:
			_fail("%s: wall-clock deadline hit %d times (collider emission stopped; last path in COL_PROGRESS)" % [map_id, int(res.get("col_deadline_hit", 0))])
			map_ok = false
		if authored_hull + absent != placed_meshes:
			_fail("%s: classification does not add up: authored=%d + absent=%d != placed_meshes=%d" % [map_id, authored_hull, absent, placed_meshes])
			map_ok = false
		if authored_prims > authored_hull:
			_fail("%s: authored_prims=%d > authored=%d (double count: prims must be a subset)" % [map_id, authored_prims, authored_hull])
			map_ok = false
		if rows.size() != reduced:
			_fail("%s: reduced=%d but only %d reduced mesh names reported" % [map_id, reduced, rows.size()])
			map_ok = false
		if req_mode == "authored":
			if coverage < MIN_AUTHORED_COVERAGE:
				_fail("%s: authored coverage %.3f < %.2f (authored=%d placed_meshes=%d)" % [map_id, coverage, MIN_AUTHORED_COVERAGE, authored_hull, placed_meshes])
				map_ok = false
			print("COL_MAP_ASSERT map=%s coverage>=%.3f dropped==0 coverage=%.3f dropped=%d %s" % [
				map_id, MIN_AUTHORED_COVERAGE, coverage, dropped, "PASS" if map_ok else "FAIL"])
		else:
			print("COL_MAP_ASSERT map=%s coverage>=%.3f dropped==0 coverage=%.3f dropped=%d SKIP (mode=%s)" % [
				map_id, MIN_AUTHORED_COVERAGE, coverage, dropped, active_mode])
		maps_checked += 1
		min_coverage = minf(min_coverage, coverage)
		total_planar += planar_skipped

	if req_mode == "authored":
		print("COL_MAPS %s maps=%d min_coverage=%.3f dropped=0 planar_skipped=%d coverage_ppm=%d" % [
			"PASS" if _fails == 0 else "FAIL", maps_checked, min_coverage,
			total_planar, int(round(min_coverage * 1000000.0))])
	else:
		print("COL_MAPS SKIP mode=%s maps=%d min_coverage=%.3f dropped=0 planar_skipped=%d coverage_ppm=%d" % [
			req_mode, maps_checked, min_coverage, total_planar,
			int(round(min_coverage * 1000000.0))])

	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--validate") and ll != null:
		_validate(ll)

	if host != null:
		host.queue_free()
	if ll != null:
		ll.queue_free()
	await process_frame
	print("COL_WALL total_ms=%d (whole probe: three map loads)" % (Time.get_ticks_msec() - probe_t0))
	quit(0 if _fails == 0 else 1)


## The W9-P1 Guildhall lines, kept byte-for-byte compatible so
## `build/qa/w9_collision_ab.sh` and the W9 logs stay comparable.
func _emit_legacy_guildhall(active_mode: String, placed_meshes_seen: int,
		authored_hull: int, authored_prims: int, absent: int, no_collision: int,
		query_only: int, reduced: int, shapes: int, bodies: int, dropped: int,
		load_ms: int, coverage: float, res: Dictionary) -> void:
	var placed_meshes: int = authored_hull + absent
	print("COL_AUDIT mode=%s placed_meshes=%d placed_meshes_seen=%d placed_instances=%d authored_hull=%d authored_prims=%d absent=%d no_collision=%d query_only=%d reduced=%d shapes=%d bodies=%d dropped=%d load_ms=%d coverage=%.3f fps_pose=n/a" % [
		active_mode, placed_meshes, placed_meshes_seen, int(res.get("col_placed_instances", 0)),
		authored_hull, authored_prims, absent, no_collision, query_only, reduced,
		shapes, bodies, dropped, load_ms, coverage])
	# Independent diagnostic numbers (not part of the gate line): the payload
	# census and the load-set denominators, so a silent data regression shows up.
	var st: Dictionary = AuthoredCollision.stats() as Dictionary
	print("COL_DETAIL payload_meshes=%d payload_elements=%d payload_convex=%d payload_load_ms=%d authored_instances=%d authored_shape_demand=%d heuristic_shapes=%d mode_requested=%s elements_on_placed=%d convex_on_placed=%d complex_default_paths=%d placed_paths_payload=%d scale_baked_shapes=%d" % [
		int(st.get("meshes", -1)), int(st.get("elements", -1)), int(st.get("convex", -1)),
		int(st.get("load_ms", -1)), int(res.get("col_authored_instances", 0)),
		int(res.get("col_authored_shapes", 0)), int(res.get("col_heuristic_shapes", 0)),
		active_mode, int(res.get("col_elements", 0)), int(res.get("col_convex", 0)),
		int(res.get("col_complex_default", 0)), int(res.get("col_path_counts", 0)), int(res.get("col_scale_baked", 0))])
	if active_mode == "authored" and placed_meshes_seen > 0:
		print("COL_ASSERT coverage=%.3f (%d/%d) prims_subset=%s classification=%d+%d==%d mode=%s dropped=%d" % [
			coverage, authored_hull, placed_meshes_seen, str(authored_prims <= authored_hull),
			authored_hull, absent, placed_meshes_seen, active_mode, dropped])


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
