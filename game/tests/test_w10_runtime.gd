extends SceneTree
## W10-A INV-2: runtime defect suite (investigation red proof).
## Run: tools/godot --headless --path game --script res://tests/test_w10_runtime.gd
##      ... --script res://tests/test_w10_runtime.gd -- d10      (adds the D10 dump)
##
## D6 — StateTree trace disk cap. `trace.gd` stopped appending to the in-memory
## ring at MAX_ROWS = 8192 but kept `store_line`-ing every row to the NDJSON
## file, so the artefact a long mission leaves behind grew without bound. The
## fix gives the sink its own budget (`MAX_FILE_ROWS` / `MAX_FILE_BYTES`,
## whichever binds first), a `file_dropped` counter and one printed cap line.
## This suite keeps the original 9000-row/8192-line proof and adds the counter
## identity, the "stops, not slows" phase and the byte-budget path.
##
## D7 — coplanar authored geometry. The brief said "zero-thickness authored
## boxes clamp to 2 cm solid slabs (SM_SlowWardZone_Quad x82)". The authored
## data says otherwise: exactly ONE box has a zero axis
## (/Engine/BasicShapes/Plane) and exactly THREE CONVEX elements are coplanar
## (SM_SlowWardZone_Quad + two FX quads). A convex element was never clamped; it
## was emitted as a zero-volume ConvexPolygonShape3D that Jolt inflates into a
## slab. The implemented rule: a convex element whose baked point AABB is below
## `PLANAR_EPS_M` (0.1 mm) on any axis emits no shape, is counted
## (`planar_convex_skipped`) and is named once per path (`COL_PLANAR`); boxes
## keep the documented clamp and are counted as `box_clamped`. This suite pins
## both halves plus the grounding ray the skip buys.
##
## D10 (diagnostic, `-- d10`): prints what level_loader._get_mesh_and_shape now
## returns for the seven authored stair flights and the roof shells — the
## `shape` compatibility field is the FIRST element only, while `shapes` /
## `shape_offsets` carry the authored per-element union. The two stale tests
## (test_stair_walk.gd:137-141, test_traversal_routes.gd:592-598) still read the
## single field.
##
## Self-contained: the three trace files live under `user://` and are removed.

const TRACE_PATH: String = "user://w10_trace_cap.ndjson"
const TRACE_MAX_ROWS: int = 8192
const TRACE_PUSH_ROWS: int = 9000
## W10-A D6 file-budget probes (separate sink, separate file).
const TRACE_FILE_PATH: String = "user://w10_trace_file_cap.ndjson"
const TRACE_BYTES_PATH: String = "user://w10_trace_byte_cap.ndjson"
const TRACE_FILE_PUSH: int = 9000
const TRACE_FILE_EXTRA: int = 6000
const TRACE_FAT_ROWS: int = 400
const TRACE_FAT_ROW_CHARS: int = 64 * 1024

const WARD_ZONE: String = "/Game/Art/Effects/WardZones/SM_SlowWardZone_Quad"
const FX_CENTER: String = "/Game/Art/VFX/Meshes/FXSHAPES_1_FXQuadPivotCenter"
const FX_DOWN_EDGE: String = "/Game/Art/VFX/Meshes/FXSHAPES_1_FXQuadPivotDownEdge"
const ENGINE_PLANE: String = "/Engine/BasicShapes/Plane"
## W10-A D7 correction fixtures: a real thin BOX (8.5 mm glass, the clamp is
## legitimate) and the multi-element mesh the gather measures (14 hulls, placed
## 37x in `OldManor_Geo`, i.e. exactly over `MAX_ELEMENT_SHAPE_COST`).
const GLASS_BOX: String = "/Game/Art/Environment/Civic/GlassModules/SM_Civic_GlassPanel_Window6x6"
const DOORWAY_MESH: String = "/Game/Art/Environment/OldManor/SM_OldManor_Doorway_4x650"
const DOORWAY_ELEMENTS: int = 14
const DOORWAY_INSTANCES: int = 37
const MESH_COLLISION: String = "res://data/generated/mesh_collision.json"

## A hull whose smallest point-set extent is below this is a sheet, not a
## solid: 1e-5 m = 0.01 mm. The authored flat quads measure ~1e-18 m (float
## residue of exactly 0); the next-flattest convex in the whole dump is
## 2.0e-3 m (SM_OldManor_Window_LivingRoom_Glass, 2 mm of authored glass), so
## the gap between "degenerate" and "thin but real" is four orders of magnitude.
const FLAT_EPS_M: float = 1e-5
## "Exactly zero" for the box path: 1e-9 m = 1e-7 cm, four orders below the
## smallest authored non-zero thickness (the glass panes carry 1e-5..1e-7 cm
## float residue). Only /Engine/BasicShapes/Plane is a true zero.
const ZERO_EPS_M: float = 1e-9
const GUILDHALL_LEVEL: String = "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json"

const STAIR_PATHS: Array[String] = [
	"/Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x150cm",
	"/Game/Art/Environment/Urban/Industrial/Stairs/SM_Stairs_Industrial_3x150cm",
	"/Game/Art/Environment/City/Architecture/Stairs/2m/SM_StairsCity6x2m",
	"/Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x850cm",
	"/Game/Art/Environment/OldManor/SM_OldManor_Tower_Stairs_4x850",
]
const ROOF_PATHS: Array[String] = [
	"/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndA_2x4x4",
	"/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndB_2x4x4",
	"/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndB_2x4x4_Mirror",
]

const AC: GDScript = preload("res://src/core/collision/authored_collision.gd")

var fails: int = 0
var checks: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_check_trace_cap()
	_check_trace_file_budget()
	var data: Dictionary = _measure_collision_data()
	_check_collision_data(data)
	await _check_flat_convex(data)
	await _check_planar_rule()
	if "d10" in OS.get_cmdline_user_args():
		await _dump_d10()
	_cleanup()
	print("W10_RUNTIME_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(0 if fails == 0 else 1)


func _cleanup() -> void:
	for path: String in [TRACE_PATH, TRACE_FILE_PATH, TRACE_BYTES_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ------------------------------------------------------------------ D6 trace

func _count_lines(path: String) -> int:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n: int = 0
	while not f.eof_reached():
		var line: String = f.get_line()
		if line != "":
			n += 1
	f.close()
	return n


func _trace_size() -> int:
	return _file_size(TRACE_PATH)


func _file_size(path: String) -> int:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n: int = f.get_length()
	f.close()
	return n


func _check_trace_cap() -> void:
	_cleanup()
	var trace: RefCounted = (load("res://src/ai/statetree/trace.gd") as GDScript).new()
	trace.configure(TRACE_PATH)
	for i: int in range(TRACE_PUSH_ROWS):
		trace.push({"kind": "tick", "tick": i, "t": float(i) / 60.0})
	trace.flush()
	var ring: int = int(trace.count())
	var dropped: int = int(trace.dropped)
	trace.close()
	var lines: int = _count_lines(TRACE_PATH)
	var bytes: int = _trace_size()
	print("D6_TRACE ring=%d dropped=%d pushed=%d file_lines=%d file_bytes=%d path=%s" % [
		ring, dropped, TRACE_PUSH_ROWS, lines, bytes, TRACE_PATH])
	_check(ring == TRACE_MAX_ROWS,
		"trace ring holds the first %d rows (got %d)" % [TRACE_MAX_ROWS, ring],
		"trace ring size drifted: got %d, expected %d" % [ring, TRACE_MAX_ROWS])
	_check(dropped == TRACE_PUSH_ROWS - TRACE_MAX_ROWS,
		"trace counts %d rows dropped past the ring" % dropped,
		"trace dropped counter is %d, expected %d" % [dropped, TRACE_PUSH_ROWS - TRACE_MAX_ROWS])
	_check(lines <= TRACE_MAX_ROWS,
		"trace NDJSON file honours the %d-row cap (%d lines, %d bytes)" % [TRACE_MAX_ROWS, lines, bytes],
		"trace NDJSON file is unbounded: %d lines written for %d pushed rows (cap %d); ring=%d dropped=%d" % [
			lines, TRACE_PUSH_ROWS, TRACE_MAX_ROWS, ring, dropped])


## W10-A D6, the file budget itself: the counter identity
## (`file_dropped == pushed - file_rows`), the exact byte accounting, the stop
## (a second push phase must add no line) and the independent byte cap.
func _check_trace_file_budget() -> void:
	var script_res: GDScript = load("res://src/ai/statetree/trace.gd") as GDScript
	var consts: Dictionary = script_res.get_script_constant_map()
	var file_max_rows: int = int(consts.get("MAX_FILE_ROWS", -1))
	var file_max_bytes: int = int(consts.get("MAX_FILE_BYTES", -1))
	_check(file_max_rows > 0 and file_max_bytes > 0,
		"trace declares a file budget (rows=%d bytes=%d)" % [file_max_rows, file_max_bytes],
		"trace has no usable file budget: rows=%d bytes=%d" % [file_max_rows, file_max_bytes])
	if FileAccess.file_exists(TRACE_FILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TRACE_FILE_PATH))
	var trace: RefCounted = script_res.new()
	trace.configure(TRACE_FILE_PATH)
	for i: int in range(TRACE_FILE_PUSH):
		trace.push({"kind": "tick", "tick": i, "t": float(i) / 60.0})
	trace.flush()
	var rows: int = int(trace.file_rows)
	var bytes: int = int(trace.file_bytes)
	var dropped: int = int(trace.file_dropped)
	var lines: int = _count_lines(TRACE_FILE_PATH)
	var disk: int = _file_size(TRACE_FILE_PATH)
	print("D6_FILE pushed=%d file_rows=%d file_dropped=%d file_bytes=%d disk_bytes=%d lines=%d cap_rows=%d cap_bytes=%d" % [
		TRACE_FILE_PUSH, rows, dropped, bytes, disk, lines, file_max_rows, file_max_bytes])
	_check(rows == file_max_rows,
		"file sink stops at the %d-row budget (wrote %d)" % [file_max_rows, rows],
		"file sink wrote %d rows against a %d-row budget" % [rows, file_max_rows])
	_check(lines == rows,
		"NDJSON holds exactly file_rows=%d lines" % rows,
		"NDJSON holds %d lines but file_rows=%d" % [lines, rows])
	_check(dropped == TRACE_FILE_PUSH - rows,
		"file_dropped counts the %d refused rows" % dropped,
		"file_dropped=%d, expected %d" % [dropped, TRACE_FILE_PUSH - rows])
	_check(bytes > 0 and bytes <= file_max_bytes,
		"file_bytes=%d is inside the %d-byte budget" % [bytes, file_max_bytes],
		"file_bytes=%d against a %d-byte budget" % [bytes, file_max_bytes])
	_check(disk == bytes,
		"file_bytes is the exact on-disk length (%d)" % disk,
		"file_bytes=%d but the file is %d bytes" % [bytes, disk])
	# The sink must STOP, not slow down: another 6000 rows add no line.
	for i2: int in range(TRACE_FILE_EXTRA):
		trace.push({"kind": "tick", "tick": TRACE_FILE_PUSH + i2, "t": 0.0})
	trace.flush()
	var total: int = TRACE_FILE_PUSH + TRACE_FILE_EXTRA
	var lines2: int = _count_lines(TRACE_FILE_PATH)
	var dropped2: int = int(trace.file_dropped)
	print("D6_FILE_STOP pushed=%d lines=%d file_rows=%d file_dropped=%d" % [
		total, lines2, int(trace.file_rows), dropped2])
	_check(lines2 == lines,
		"the capped sink writes nothing more (%d lines after %d rows)" % [lines2, total],
		"the capped sink kept writing: %d lines, was %d" % [lines2, lines])
	_check(dropped2 == total - rows,
		"file_dropped tracks every refused row (%d)" % dropped2,
		"file_dropped=%d, expected %d" % [dropped2, total - rows])
	trace.close()
	# Independent byte cap: 400 x 64 KiB rows cannot fit in 16 MiB.
	if FileAccess.file_exists(TRACE_BYTES_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TRACE_BYTES_PATH))
	var fat_row: String = "x".repeat(TRACE_FAT_ROW_CHARS)
	var trace2: RefCounted = script_res.new()
	trace2.configure(TRACE_BYTES_PATH)
	for i3: int in range(TRACE_FAT_ROWS):
		trace2.push({"kind": "tick", "tick": i3, "pad": fat_row})
	trace2.flush()
	var fat_rows: int = int(trace2.file_rows)
	var fat_bytes: int = int(trace2.file_bytes)
	var fat_dropped: int = int(trace2.file_dropped)
	trace2.close()
	var fat_disk: int = _file_size(TRACE_BYTES_PATH)
	print("D6_BYTES pushed=%d file_rows=%d file_dropped=%d file_bytes=%d disk_bytes=%d cap_bytes=%d" % [
		TRACE_FAT_ROWS, fat_rows, fat_dropped, fat_bytes, fat_disk, file_max_bytes])
	_check(fat_rows >= 1 and fat_rows < TRACE_FAT_ROWS,
		"the byte budget binds before the row budget (%d of %d rows)" % [fat_rows, TRACE_FAT_ROWS],
		"the byte budget never bound: %d of %d rows written" % [fat_rows, TRACE_FAT_ROWS])
	_check(fat_bytes <= file_max_bytes and fat_disk <= file_max_bytes,
		"the huge-row sink stays inside %d bytes (accounted %d, disk %d)" % [file_max_bytes, fat_bytes, fat_disk],
		"the huge-row sink exceeded the byte budget: accounted %d, disk %d, cap %d" % [
			fat_bytes, fat_disk, file_max_bytes])
	_check(fat_dropped == TRACE_FAT_ROWS - fat_rows,
		"byte-capped sink refuses the remaining %d rows" % fat_dropped,
		"byte-capped file_dropped=%d, expected %d" % [fat_dropped, TRACE_FAT_ROWS - fat_rows])


# ------------------------------------------------------- D7 authored data

func _element_min_extent(el: Dictionary) -> float:
	# Box: authored full extents in UE cm. Convex: baked-in vertex AABB is the
	# authoring; the element transform is identity-scale for all three flat
	# quads, so the raw vertex ranges are the authored extents (x100 cm->m).
	var rng: Array = []
	if str(el.get("type", "")) == "box":
		var he: Array = el.get("half_extent", []) as Array
		if he.size() < 3:
			return INF
		rng = [absf(float(he[0])), absf(float(he[1])), absf(float(he[2]))]
	else:
		var flat: Array = el.get("vertices_flat", []) as Array
		if flat.size() < 9:
			return INF
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		for i: int in range(flat.size() / 3):
			var v := Vector3(float(flat[i * 3]), float(flat[i * 3 + 1]), float(flat[i * 3 + 2]))
			mn = mn.min(v)
			mx = mx.max(v)
		rng = [(mx.x - mn.x), (mx.y - mn.y), (mx.z - mn.z)]
	return minf(minf(float(rng[0]), float(rng[1])), float(rng[2])) * 0.01


func _measure_collision_data() -> Dictionary:
	var out: Dictionary = {
		"zero_boxes": [] as Array,
		"near_zero_boxes": [] as Array,
		"flat_convex": [] as Array,
		"near_flat_convex": [] as Array,
	}
	var txt: String = FileAccess.get_file_as_string(MESH_COLLISION)
	if txt.is_empty():
		printerr("FAIL: cannot read ", MESH_COLLISION)
		fails += 1
		return out
	var parsed: Variant = JSON.parse_string(txt)
	txt = ""
	if not (parsed is Dictionary):
		printerr("FAIL: ", MESH_COLLISION, " is not a JSON object")
		fails += 1
		return out
	var meshes: Dictionary = (parsed as Dictionary).get("meshes", {}) as Dictionary
	for path_var: Variant in meshes.keys():
		var path: String = str(path_var)
		var rec: Dictionary = meshes[path_var] as Dictionary
		var els: Array = rec.get("elements", []) as Array
		for i: int in range(els.size()):
			var el: Dictionary = els[i] as Dictionary
			var etype: String = str(el.get("type", ""))
			if etype != "box" and etype != "convex":
				continue
			var min_ext: float = _element_min_extent(el)
			var row: Dictionary = {"path": path, "index": i, "min_ext_m": min_ext}
			if etype == "box":
				if min_ext < ZERO_EPS_M:
					row["profile"] = str(rec.get("collision_profile", ""))
					(out["zero_boxes"] as Array).append(row)
				elif min_ext < 1e-5:
					# Authored sub-micrometre glass: not zero, but the same 2 cm
					# clamp rewrites it. Counted so the fix decision sees them.
					row["profile"] = str(rec.get("collision_profile", ""))
					(out["near_zero_boxes"] as Array).append(row)
			elif min_ext < FLAT_EPS_M:
				row["profile"] = str(rec.get("collision_profile", ""))
				row["points"] = (el.get("vertices_flat", []) as Array).size() / 3
				row["aabb_min"] = el.get("aabb_min")
				row["aabb_max"] = el.get("aabb_max")
				(out["flat_convex"] as Array).append(row)
				if path == WARD_ZONE:
					out["ward_vertices"] = (el.get("vertices_flat", []) as Array).duplicate()
			elif min_ext < 0.01:
				row["profile"] = str(rec.get("collision_profile", ""))
				(out["near_flat_convex"] as Array).append(row)
	out["elements_total"] = int(((parsed as Dictionary).get("counts", {}) as Dictionary).get("elements", 0))
	out["meshes_total"] = meshes.size()
	return out


func _check_collision_data(data: Dictionary) -> void:
	var zero_boxes: Array = data["zero_boxes"] as Array
	var flat_convex: Array = data["flat_convex"] as Array
	var near_zero: Array = data["near_zero_boxes"] as Array
	print("D7_DATA meshes=%d elements=%d zero_axis_boxes=%d near_zero_boxes=%d flat_convex=%d near_flat_convex=%d" % [
		int(data.get("meshes_total", 0)), int(data.get("elements_total", 0)),
		zero_boxes.size(), near_zero.size(), flat_convex.size(),
		(data["near_flat_convex"] as Array).size()])
	for r: Dictionary in zero_boxes:
		print("  zero_axis_box %s[%d] min_ext=%.9f profile=%s" % [
			str(r["path"]), int(r["index"]), float(r["min_ext_m"]), str(r.get("profile", ""))])
	for rn: Dictionary in near_zero:
		print("  near_zero_box %s[%d] min_ext=%.9f profile=%s (authored float residue, clamps too)" % [
			str(rn["path"]), int(rn["index"]), float(rn["min_ext_m"]), str(rn.get("profile", ""))])
	for r2: Dictionary in flat_convex:
		print("  flat_convex %s[%d] points=%d min_ext=%.9f profile=%s aabb_min=%s aabb_max=%s" % [
			str(r2["path"]), int(r2["index"]), int(r2.get("points", 0)),
			float(r2["min_ext_m"]), str(r2.get("profile", "")),
			str(r2.get("aabb_min")), str(r2.get("aabb_max"))])
	for r3: Dictionary in (data["near_flat_convex"] as Array):
		print("  near_flat_convex %s[%d] min_ext=%.9f (thin but real; NOT flat)" % [
			str(r3["path"]), int(r3["index"]), float(r3["min_ext_m"])])

	_check(zero_boxes.size() == 1 and str((zero_boxes[0] as Dictionary)["path"]) == ENGINE_PLANE,
		"exactly one authored box has a zero axis: %s" % ENGINE_PLANE,
		"zero-axis box set changed: %s" % str(zero_boxes))
	var flat_paths: Array[String] = []
	for r4: Dictionary in flat_convex:
		flat_paths.append(str(r4["path"]))
	flat_paths.sort()
	var expected: Array[String] = [FX_CENTER, FX_DOWN_EDGE, WARD_ZONE]
	expected.sort()
	_check(flat_paths == expected,
		"exactly three authored convex elements are coplanar (ward + 2 FX quads)",
		"coplanar convex set changed: %s" % str(flat_paths))


# ---------------------------------------------------- D7 shape + Jolt probe

func _points_aabb(pts: PackedVector3Array) -> AABB:
	if pts.is_empty():
		return AABB()
	var mn := pts[0]
	var mx := pts[0]
	for p: Vector3 in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return AABB(mn, mx - mn)


## Every convex hull in `shapes` whose point-set AABB has a degenerate axis.
func _degenerate_hulls(shapes: Array) -> Array:
	var out: Array = []
	for s_var: Variant in shapes:
		var sh: Shape3D = s_var as Shape3D
		if not (sh is ConvexPolygonShape3D):
			continue
		var pts: PackedVector3Array = (sh as ConvexPolygonShape3D).points
		var a: AABB = _points_aabb(pts)
		var mn: float = minf(minf(a.size.x, a.size.y), a.size.z)
		if mn < FLAT_EPS_M:
			out.append({"points": pts.size(), "extent_m": mn, "aabb": a})
	return out


func _check_flat_convex(data: Dictionary) -> void:
	var ward: Dictionary = AC.resolve(WARD_ZONE, 82) as Dictionary
	var ward_shapes: Array = ward["shapes"] as Array
	var ward_degenerate: Array = _degenerate_hulls(ward_shapes)
	print("D7_WARD source=%s elements=%d convex=%d shapes=%d offsets=%d degenerate_hulls=%d" % [
		str(ward.get("source", "")), int(ward.get("elements", 0)), int(ward.get("convex", 0)),
		ward_shapes.size(), (ward["offsets"] as Array).size(), ward_degenerate.size()])
	var probe_hull: Shape3D = null
	if not ward_degenerate.is_empty():
		var d0: Dictionary = ward_degenerate[0] as Dictionary
		print("  ward hull points=%d min_extent=%.9f aabb=%s" % [
			int(d0["points"]), float(d0["extent_m"]), str(d0["aabb"])])
		probe_hull = ward_shapes[0] as Shape3D
	else:
		# Post-fix the shape is (correctly) gone; rebuild the pre-fix encoding
		# from the authored vertices with the documented P(v) = (x, z, y) * 0.01
		# swap (authored_collision.gd:11-13) so the Jolt fact stays re-derivable.
		var raw: Array = data.get("ward_vertices", []) as Array
		if raw.size() >= 9:
			var pts := PackedVector3Array()
			pts.resize(raw.size() / 3)
			for i: int in range(raw.size() / 3):
				pts[i] = Vector3(float(raw[i * 3]), float(raw[i * 3 + 2]), float(raw[i * 3 + 1])) * 0.01
			probe_hull = ConvexPolygonShape3D.new()
			(probe_hull as ConvexPolygonShape3D).points = pts
			print("  pre-fix hull reconstructed from authored vertices: points=%d aabb=%s" % [
				pts.size(), str(_points_aabb(pts))])
	if probe_hull != null:
		await _probe_jolt_flat_hull(probe_hull)
		await _probe_placed_ward_sheet(probe_hull)

	var fx_red: Array[String] = []
	for p: String in [FX_CENTER, FX_DOWN_EDGE]:
		var res: Dictionary = AC.resolve(p, 6) as Dictionary
		var deg: Array = _degenerate_hulls(res["shapes"] as Array)
		print("D7_FX %s source=%s elements=%d shapes=%d degenerate=%d" % [
			p.get_file(), str(res.get("source", "")), int(res.get("elements", 0)),
			(res["shapes"] as Array).size(), deg.size()])
		if not deg.is_empty():
			fx_red.append(p.get_file())

	# The engine Plane is the ONE box the clamp fires for: 2 m x 2 m authored,
	# Z = 0 -> size.y = 2 * MIN_HALF_EXTENT_M = 0.02 m. Pin it, because the
	# brief's "solid slab" mechanism is real *here* and only here.
	var plane: Dictionary = AC.resolve(ENGINE_PLANE, 1) as Dictionary
	var plane_shapes: Array = plane["shapes"] as Array
	var plane_size := Vector3(-1.0, -1.0, -1.0)
	if plane_shapes.size() == 1 and (plane_shapes[0] as Shape3D) is BoxShape3D:
		plane_size = ((plane_shapes[0] as Shape3D) as BoxShape3D).size
	print("D7_PLANE source=%s elements=%d shapes=%d size=%s (clamp fires: size.y == %.3f)" % [
		str(plane.get("source", "")), int(plane.get("elements", 0)), plane_shapes.size(),
		str(plane_size), 2.0 * float(AC.MIN_HALF_EXTENT_M)])
	_check(is_equal_approx(plane_size.y, 2.0 * float(AC.MIN_HALF_EXTENT_M)) and is_equal_approx(plane_size.x, 1.0),
		"/Engine/BasicShapes/Plane keeps the documented 2 cm clamp (size %s)" % str(plane_size),
		"/Engine/BasicShapes/Plane shape changed: %s (expected 1.0 x 0.02 x 1.0 m)" % str(plane_size))

	_check(ward_degenerate.is_empty(),
		"ward zone emits no zero-volume convex hull (%d shapes)" % ward_shapes.size(),
		"ward zone emits a zero-volume convex hull: %s" % str(ward_degenerate))
	_check(fx_red.is_empty(),
		"FX quads emit no zero-volume convex hull",
		"flat FX quads emitted as zero-volume hulls: %s" % str(fx_red))
	_check(int(ward.get("degenerate", 0)) >= 1,
		"ward zone reports the skipped degenerate element (degenerate=%d)" % int(ward.get("degenerate", 0)),
		"ward zone does not report a counted degenerate skip (degenerate=%s, expected >= 1)" % str(ward.get("degenerate")))


## W10-A D7 (corrected rule): coplanar CONVEX elements emit no shape; boxes keep
## the clamp and are counted; a real multi-element hull mesh is unchanged; and
## the grounding ray proves what the skip buys.
func _check_planar_rule() -> void:
	var before: int = int((AC.stats() as Dictionary).get("planar_convex_skipped", -1))
	var ward1: Dictionary = AC.resolve(WARD_ZONE, 1) as Dictionary
	var after1: int = int((AC.stats() as Dictionary).get("planar_convex_skipped", -1))
	var s1: Array = ward1["shapes"] as Array
	var o1: Array = ward1["offsets"] as Array
	print("D7_WARD instances=1 source=%s elements=%d convex=%d shapes=%d offsets=%d planar=%d counter=%d->%d" % [
		str(ward1.get("source", "")), int(ward1.get("elements", 0)), int(ward1.get("convex", 0)),
		s1.size(), o1.size(), int(ward1.get("planar_convex_skipped", 0)), before, after1])
	_check(s1.is_empty() and o1.is_empty(),
		"ward zone at 1 placement emits no shape at all",
		"ward zone still emits %d shape(s) / %d offset(s)" % [s1.size(), o1.size()])
	_check(int(ward1.get("planar_convex_skipped", 0)) == 1,
		"ward zone reports its one coplanar convex element",
		"ward planar_convex_skipped=%d, expected 1" % int(ward1.get("planar_convex_skipped", 0)))
	_check(after1 == before + 1,
		"planar counter increments once for a fresh resolve (%d -> %d)" % [before, after1],
		"planar counter moved %d -> %d, expected +1" % [before, after1])
	# Cache: the same path+instances key must not count twice.
	AC.resolve(WARD_ZONE, 1)
	var after_cached: int = int((AC.stats() as Dictionary).get("planar_convex_skipped", -1))
	_check(after_cached == after1,
		"re-resolving the same key is free (%d)" % after_cached,
		"the resolve cache double-counted: %d -> %d" % [after1, after_cached])
	var ward160: Dictionary = AC.resolve(WARD_ZONE, 160) as Dictionary
	var after160: int = int((AC.stats() as Dictionary).get("planar_convex_skipped", -1))
	var s160: Array = ward160["shapes"] as Array
	print("D7_WARD instances=160 shapes=%d planar=%d (authoring: 82 placements in Guildhall, 78 in OldManor)" % [
		s160.size(), int(ward160.get("planar_convex_skipped", 0))])
	_check(s160.is_empty(),
		"ward zone at 160 placements emits no shape",
		"ward zone at 160 placements emits %d shape(s)" % s160.size())
	_check(after160 == after1 + 1,
		"a second placement count is one more resolve, one more skip (%d -> %d)" % [after1, after160],
		"planar counter moved %d -> %d, expected +1" % [after1, after160])
	var st: Dictionary = AC.stats() as Dictionary
	var paths: Array = st.get("planar_skipped_paths", []) as Array
	_check(paths.has(WARD_ZONE), "the ward path is listed in planar_skipped_paths", "ward path missing from %s" % str(paths))
	_check(paths.has(FX_CENTER), "the FX quad path is listed in planar_skipped_paths", "FX path missing from %s" % str(paths))
	_check(paths.size() <= 32, "the reported path list is capped at 32 (%d)" % paths.size(), "path list is unbounded: %d" % paths.size())

	var fx: Dictionary = AC.resolve(FX_CENTER, 6) as Dictionary
	var fx_shapes: Array = fx["shapes"] as Array
	_check(fx_shapes.is_empty() and int(fx.get("planar_convex_skipped", 0)) == 1,
		"FXSHAPES_1_FXQuadPivotCenter emits no shape (%d shapes, planar=%d)" % [fx_shapes.size(), int(fx.get("planar_convex_skipped", 0))],
		"FX quad still emits %d shape(s), planar=%d" % [fx_shapes.size(), int(fx.get("planar_convex_skipped", 0))])
	var fx2: Dictionary = AC.resolve(FX_DOWN_EDGE, 6) as Dictionary
	_check((fx2["shapes"] as Array).is_empty() and int(fx2.get("planar_convex_skipped", 0)) == 1,
		"FXSHAPES_1_FXQuadPivotDownEdge emits no shape",
		"FX down-edge quad still emits %d shape(s)" % (fx2["shapes"] as Array).size())

	# The engine plane is a BOX: the clamp is legitimate and stays.
	var plane: Dictionary = AC.resolve(ENGINE_PLANE, 1) as Dictionary
	var plane_shapes: Array = plane["shapes"] as Array
	var plane_box: bool = plane_shapes.size() == 1 and (plane_shapes[0] as Shape3D) is BoxShape3D
	var plane_size := Vector3.ZERO
	if plane_box:
		plane_size = ((plane_shapes[0] as Shape3D) as BoxShape3D).size
	print("D7_PLANE source=%s elements=%d shapes=%d box=%s size=%s box_clamped=%d" % [
		str(plane.get("source", "")), int(plane.get("elements", 0)), plane_shapes.size(),
		str(plane_box), str(plane_size), int(plane.get("box_clamped", 0))])
	_check(plane_box and is_equal_approx(plane_size.y, 2.0 * float(AC.MIN_HALF_EXTENT_M)),
		"/Engine/BasicShapes/Plane stays one box with the 2 cm clamp (size %s)" % str(plane_size),
		"/Engine/BasicShapes/Plane changed: box=%s size=%s" % [str(plane_box), str(plane_size)])
	_check(int(plane.get("box_clamped", 0)) == 1,
		"the engine plane is counted as box_clamped",
		"engine plane box_clamped=%d, expected 1" % int(plane.get("box_clamped", 0)))
	_check(int(plane.get("planar_convex_skipped", 0)) == 0,
		"a box is never counted as a planar convex skip",
		"the engine plane was counted as planar: %d" % int(plane.get("planar_convex_skipped", 0)))

	# A real thin box (8.5 mm glass, placed 4x): still one clamped box.
	var glass: Dictionary = AC.resolve(GLASS_BOX, 4) as Dictionary
	var glass_shapes: Array = glass["shapes"] as Array
	var glass_box: bool = glass_shapes.size() == 1 and (glass_shapes[0] as Shape3D) is BoxShape3D
	var glass_size := Vector3.ZERO
	if glass_box:
		glass_size = ((glass_shapes[0] as Shape3D) as BoxShape3D).size
	print("D7_GLASS source=%s elements=%d shapes=%d box=%s size=%s box_clamped=%d planar=%d" % [
		str(glass.get("source", "")), int(glass.get("elements", 0)), glass_shapes.size(),
		str(glass_box), str(glass_size), int(glass.get("box_clamped", 0)),
		int(glass.get("planar_convex_skipped", 0))])
	_check(glass_box and is_equal_approx(minf(glass_size.x, minf(glass_size.y, glass_size.z)), 2.0 * float(AC.MIN_HALF_EXTENT_M)),
		"a real thin glass pane still resolves to one clamped box (size %s)" % str(glass_size),
		"the thin glass pane changed: box=%s size=%s" % [str(glass_box), str(glass_size)])
	_check(int(glass.get("box_clamped", 0)) == 1,
		"the thin glass pane is counted as box_clamped",
		"glass box_clamped=%d, expected 1" % int(glass.get("box_clamped", 0)))
	_check(int(st.get("box_clamped", 0)) >= 1,
		"stats() reports box_clamped=%d" % int(st.get("box_clamped", 0)),
		"stats() has no box_clamped counter: %s" % str(st.keys()))

	# A real 14-hull mesh: unchanged, per element at 1 placement and reduced at
	# the 37 placements `OldManor_Geo` actually uses.
	var d1: Dictionary = AC.resolve(DOORWAY_MESH, 1) as Dictionary
	var d37: Dictionary = AC.resolve(DOORWAY_MESH, DOORWAY_INSTANCES) as Dictionary
	var d1_shapes: Array = d1["shapes"] as Array
	var d37_shapes: Array = d37["shapes"] as Array
	print("D7_DOORWAY elements=%d instances=1 shapes=%d reduced=%s | instances=%d shapes=%d reduced=%s" % [
		int(d1.get("elements", 0)), d1_shapes.size(), str(bool(d1.get("reduced", false))),
		DOORWAY_INSTANCES, d37_shapes.size(), str(bool(d37.get("reduced", false)))])
	_check(int(d1.get("elements", 0)) == DOORWAY_ELEMENTS and d1_shapes.size() == DOORWAY_ELEMENTS,
		"a 14-element hull mesh keeps 14 shapes at 1 placement (%d)" % d1_shapes.size(),
		"hull mesh changed: elements=%d shapes=%d" % [int(d1.get("elements", 0)), d1_shapes.size()])
	_check(not bool(d1.get("reduced", true)),
		"a 14-element hull mesh is not reduced at 1 placement",
		"hull mesh was reduced at 1 placement")
	_check(d37_shapes.size() == 1 and bool(d37.get("reduced", false)),
		"the same mesh reduces to 1 shape at %d placements" % DOORWAY_INSTANCES,
		"reduction changed at %d placements: shapes=%d reduced=%s" % [
			DOORWAY_INSTANCES, d37_shapes.size(), str(bool(d37.get("reduced", false)))])
	_check(int(d1.get("planar_convex_skipped", 0)) == 0 and int(d37.get("planar_convex_skipped", 0)) == 0,
		"no element of a real hull mesh is treated as planar",
		"a real hull mesh lost elements to the planar rule: %d / %d" % [
			int(d1.get("planar_convex_skipped", 0)), int(d37.get("planar_convex_skipped", 0))])
	await _check_ward_grounding()


func _ray_down(space: PhysicsDirectSpaceState3D, at: Vector3, from_y: float) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(
		at + Vector3(0.0, from_y, 0.0), at + Vector3(0.0, -2.0, 0.0), 1))


## Grounding proof. Two halves, labelled:
##   * RESOLVED DATA — `AuthoredCollision.resolve()` emits 0 shapes / 0 offsets
##     for the ward zone, so a downward ray from y = 2.0 reaches the floor at
##     y ~ 0: loot/civilians ground on the floor, not on an invisible decal.
##   * SYNTHETIC CONTROL — the pre-fix coplanar hull, rebuilt from the authored
##     points this module no longer emits. The decoded hull is flat in mesh Y
##     (UE authors the quad in its XY plane; the exporter's Y/Z swap puts it in
##     XZ), so an identity basis lays it horizontally at y = 1.0, squarely in
##     the ray's path: it answers the ray at ~1.0, i.e. the defect was real and
##     the skip is what removes it.
func _check_ward_grounding() -> void:
	# Far from the origin: the Jolt probes above build their own bodies there and
	# a lingering one must never answer this ray.
	var fixture_base := Vector3(500.0, 0.0, 500.0)
	var floor_body := StaticBody3D.new()
	floor_body.name = "W10GroundingFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 0.2, 40.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0.0, -0.1, 0.0) # top face at fixture_base.y = 0
	floor_body.add_child(floor_shape)
	floor_body.position = fixture_base
	root.add_child(floor_body)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state

	var ward: Dictionary = AC.resolve(WARD_ZONE, 160) as Dictionary
	var resolved: Array = ward["shapes"] as Array
	var resolved_offsets: Array = ward["offsets"] as Array
	var fixed_hit: Dictionary = _ray_down(space, fixture_base, 2.0)
	var fixed_y: float = float((fixed_hit.get("position", Vector3.ZERO) as Vector3).y) - fixture_base.y

	var els: Array = AC.decoded_elements(WARD_ZONE) as Array
	var pts := PackedVector3Array()
	if not els.is_empty():
		pts = (els[0] as Dictionary).get("points", PackedVector3Array()) as PackedVector3Array
	var control := StaticBody3D.new()
	control.name = "W10PreFixWardSheet"
	control.collision_layer = 1
	control.collision_mask = 0
	var control_shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	control_shape.shape = hull
	control.add_child(control_shape)
	# The ward hull lies in its local XZ plane, so local +Y is already the sheet
	# normal: an identity basis makes it a horizontal sheet 1.0 m above the
	# floor, squarely in the ray's path. (A 90 deg X rotation would stand it
	# edge-on to the ray and the control would prove nothing.)
	control.transform = Transform3D(Basis(), fixture_base + Vector3(0.0, 1.0, 0.0))
	root.add_child(control)
	await physics_frame
	await physics_frame
	var pre_hit: Dictionary = _ray_down(space, fixture_base, 2.0)
	var pre_y: float = float((pre_hit.get("position", Vector3.ZERO) as Vector3).y) - fixture_base.y
	print("D7_GROUNDING resolved_shapes=%d resolved_offsets=%d authored_points=%d fixed_hit=%s fixed_y=%.4f pre_fix_hit=%s pre_fix_y=%.4f floor_y=0.0000" % [
		resolved.size(), resolved_offsets.size(), pts.size(), str(not fixed_hit.is_empty()), fixed_y,
		str(not pre_hit.is_empty()), pre_y])
	_check(pts.size() >= 4,
		"the authored ward hull is recoverable for the control (%d points)" % pts.size(),
		"cannot rebuild the pre-fix ward hull: %d points" % pts.size())
	_check(resolved.is_empty() and resolved_offsets.is_empty(),
		"the loader's ward set is empty: 0 shapes, 0 offsets",
		"the loader's ward set is not empty: %d shapes, %d offsets" % [resolved.size(), resolved_offsets.size()])
	_check(not fixed_hit.is_empty() and absf(fixed_y) <= 0.02,
		"a downward ray from y=2.0 reaches the floor at y=%.3f with the resolved set" % fixed_y,
		"the grounding ray was stopped at y=%.3f (expected the floor at y~0)" % fixed_y)
	_check(not pre_hit.is_empty() and absf(pre_y - 1.0) <= 0.1,
		"the synthetic pre-fix hull answers the same ray at y=%.3f (control: the defect was real)" % pre_y,
		"the control sheet did not answer the ray at y=1.0 (hit=%s y=%.3f)" % [str(not pre_hit.is_empty()), pre_y])
	control.queue_free()
	floor_body.queue_free()
	await physics_frame


## What does Jolt do with the pre-fix zero-volume hull? Measured, printed, never
## asserted as correct: a ray must not be answered by an invisible sheet and a
## dropped body must not rest on one.
func _probe_jolt_flat_hull(hull: Shape3D) -> void:
	var pts: PackedVector3Array = (hull as ConvexPolygonShape3D).points
	var a: AABB = _points_aabb(pts)
	print("  local hull: points=%d aabb=%s" % [pts.size(), str(a)])
	var body := StaticBody3D.new()
	body.name = "W10FlatHullProbe"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = hull
	body.add_child(cs)
	root.add_child(body)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 0.5, 0.0), Vector3(0.0, -0.5, 0.0), 1))
	var local_samples: Array[String] = []
	var qbox_probe := BoxShape3D.new()
	qbox_probe.size = Vector3(0.05, 0.05, 0.05)
	for off_m: float in [0.0, 0.25, 0.5, 0.75, 0.9, 1.05, 1.5]:
		var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		q.shape = qbox_probe
		q.transform = Transform3D(Basis(), Vector3(off_m, 0.0, 0.0))
		q.collision_mask = 1
		var hits_q: Array[Dictionary] = space.intersect_shape(q, 4)
		local_samples.append("%.2f:%s" % [off_m, "Y" if not hits_q.is_empty() else "n"])
	print("  JOLT_FLAT_HULL_LOCAL_2M shape_queries=%s" % str(local_samples))
	var shape_q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var qbox := BoxShape3D.new()
	qbox.size = Vector3(0.2, 0.2, 0.2)
	shape_q.shape = qbox
	shape_q.transform = Transform3D(Basis(), Vector3(0.0, 0.05, 0.0))
	shape_q.collision_mask = 1
	var qhits: Array[Dictionary] = space.intersect_shape(shape_q, 4)
	print("  JOLT_FLAT_HULL ray_hit=%s ray_y=%.4f shape_query_hits=%d" % [
		str(not hit.is_empty()), float((hit.get("position", Vector3.ZERO) as Vector3).y), qhits.size()])
	body.queue_free()
	await physics_frame


## The placed ward sheet, using the real authored record and the real
## level_loader._dict_to_transform (basis decode + the [0.05, 40] scale clamp).
## A horizontal placement gets rays 30 m apart along the sheet; the pre-fix
## zero-volume hull answers both, i.e. the invisible sheet is solid over 60 m.
func _probe_placed_ward_sheet(hull: Shape3D) -> void:
	var txt: String = FileAccess.get_file_as_string(GUILDHALL_LEVEL)
	if txt.is_empty():
		print("  D7_PLACED level JSON unreadable; placed probe skipped")
		return
	var parsed: Variant = JSON.parse_string(txt)
	txt = ""
	if not (parsed is Dictionary):
		print("  D7_PLACED level JSON is not an object; placed probe skipped")
		return
	var meshes: Array = (parsed as Dictionary).get("meshes", []) as Array
	var rec: Dictionary = {}
	var count: int = 0
	for m_var: Variant in meshes:
		var m: Dictionary = m_var as Dictionary
		if str(m.get("mesh", "")) != WARD_ZONE:
			continue
		count += 1
		if rec.is_empty():
			rec = m
	if rec.is_empty():
		print("  D7_PLACED no ward placement in %s" % GUILDHALL_LEVEL)
		return
	var loader: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	var tr: Transform3D = loader.call("_dict_to_transform", rec) as Transform3D
	loader.free()
	var sc: Vector3 = tr.basis.get_scale()
	var scaled: Dictionary = AC.scaled_variant("w10_placed_ward", {"shapes": [hull]}, sc) as Dictionary
	var placed: Shape3D = (scaled["shapes"] as Array)[0] as Shape3D
	var body := StaticBody3D.new()
	body.name = "W10PlacedWardSheet"
	body.collision_layer = 1
	body.collision_mask = 0
	# Exactly `_add_collider(..., bake_scale=true)`: the shape carries the
	# instance scale, the body keeps only the orthonormal rotation + origin.
	body.transform = Transform3D(tr.basis.orthonormalized(), tr.origin)
	var cs := CollisionShape3D.new()
	cs.shape = placed
	body.add_child(cs)
	root.add_child(body)
	await physics_frame
	await physics_frame
	var n: Vector3 = tr.basis.y.normalized()
	var t1: Vector3 = tr.basis.x.normalized()
	var t2: Vector3 = tr.basis.z.normalized()
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var hits: Array[bool] = []
	var offsets: Array[Vector3] = [Vector3.ZERO, t1 * 30.0, t2 * 30.0]
	for off: Vector3 in offsets:
		var from: Vector3 = tr.origin + off + n * 10.0
		var to: Vector3 = tr.origin + off - n * 10.0
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
		hits.append(not hit.is_empty())
	# Sample the sheet's actual solid region: 0..41 m along each in-plane axis.
	var qbox := BoxShape3D.new()
	qbox.size = Vector3(0.2, 0.2, 0.2)
	for axis: Vector3 in [t1, t2]:
		var samples: Array[String] = []
		for off_m: float in [0.0, 0.25, 0.5, 1.0, 2.0, 5.0, 20.0, 39.0, 41.0]:
			var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
			q.shape = qbox
			q.transform = Transform3D(Basis(), tr.origin + axis * off_m)
			q.collision_mask = 1
			var hq: Array[Dictionary] = space.intersect_shape(q, 4)
			var who: String = "-"
			if not hq.is_empty():
				var col: Object = (hq[0] as Dictionary).get("collider") as Object
				who = (col as Node).name if col is Node else "?"
			samples.append("%.2f:%s(%s)" % [off_m, "Y" if not hq.is_empty() else "n", who])
		print("  D7_PLACED_SAMPLE axis=%s %s" % [str(axis), str(samples)])
	var quad: AABB = _points_aabb((hull as ConvexPolygonShape3D).points)
	print("  D7_PLACED guildhall_wards=%d pos=%s authored_scale=%s clamped_scale=%s local_quad_m=(%.3f, %.3f) placed_span_m=(%.2f, %.2f)" % [
		count, str(tr.origin), str(rec.get("scale")), str(sc),
		quad.size.x, quad.size.z,
		quad.size.x * tr.basis.x.length(), quad.size.z * tr.basis.z.length()])
	print("  D7_PLACED world_basis_axes x=%s y(normal)=%s z=%s ray_hits_centre/30m_x/30m_z=%s" % [
		str(t1), str(n), str(t2), str(hits)])
	body.queue_free()
	await physics_frame


# ------------------------------------------------------------ D10 diagnostic

func _dump_d10() -> void:
	var loader: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(loader)
	await process_frame
	await _probe_roof_union(loader)
	var tags: Array[String] = []
	tags.append_array(STAIR_PATHS)
	tags.append_array(ROOF_PATHS)
	for path: String in tags:
		var info: Dictionary = loader.call("_get_mesh_and_shape", path) as Dictionary
		var shape: Variant = info.get("shape")
		var shapes: Array = info.get("shapes", []) as Array
		var offsets: Array = info.get("shape_offsets", []) as Array
		var res: Dictionary = AC.resolve(path, 1) as Dictionary
		var shape_cls: String = "null"
		if shape is Object and shape != null:
			shape_cls = (shape as Object).get_class()
		var classes: Array[String] = []
		for s_var: Variant in shapes:
			classes.append((s_var as Object).get_class() if s_var != null else "null")
		print("D10 %s" % path.get_file())
		print("    resolve: source=%s elements=%d convex=%d reduced=%s shapes=%d" % [
			str(res.get("source", "")), int(res.get("elements", 0)), int(res.get("convex", 0)),
			str(res.get("reduced", false)), (res["shapes"] as Array).size()])
		print("    _get_mesh_and_shape: shape=%s shapes=%s offsets=%d" % [
			shape_cls, str(classes), offsets.size()])
		var mesh: Mesh = info.get("mesh") as Mesh
		if mesh != null and not shapes.is_empty():
			var mn := Vector3(INF, INF, INF)
			var mx := Vector3(-INF, -INF, -INF)
			var points: int = 0
			for i: int in range(shapes.size()):
				var xf: Transform3D = Transform3D.IDENTITY
				if i < offsets.size():
					xf = offsets[i] as Transform3D
				var pts: PackedVector3Array = _shape_points(shapes[i] as Shape3D)
				points += pts.size()
				for p: Vector3 in pts:
					var v: Vector3 = xf * p
					mn = mn.min(v)
					mx = mx.max(v)
			var union_aabb := AABB(mn, mx - mn)
			var mesh_aabb: AABB = mesh.get_aabb()
			print("    union_aabb=%s mesh_aabb=%s delta_pos=%s delta_size=%s points=%d" % [
				str(union_aabb), str(mesh_aabb),
				str(union_aabb.position - mesh_aabb.position),
				str(union_aabb.size - mesh_aabb.size), points])
	loader.queue_free()
	await process_frame


func _shape_points(shape: Shape3D) -> PackedVector3Array:
	if shape == null:
		return PackedVector3Array()
	if shape is ConvexPolygonShape3D:
		return (shape as ConvexPolygonShape3D).points
	if shape is ConcavePolygonShape3D:
		return (shape as ConcavePolygonShape3D).get_faces()
	if shape is BoxShape3D:
		var h: Vector3 = (shape as BoxShape3D).size * 0.5
		return PackedVector3Array([
			Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
			Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
			Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
			Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
		])
	if shape is SphereShape3D:
		var r: float = (shape as SphereShape3D).radius
		return PackedVector3Array([
			Vector3(-r, 0.0, 0.0), Vector3(r, 0.0, 0.0), Vector3(0.0, -r, 0.0),
			Vector3(0.0, r, 0.0), Vector3(0.0, 0.0, -r), Vector3(0.0, 0.0, r),
		])
	if shape is CapsuleShape3D:
		var cr: float = (shape as CapsuleShape3D).radius
		var hh: float = (shape as CapsuleShape3D).height * 0.5
		return PackedVector3Array([
			Vector3(-cr, -hh, 0.0), Vector3(cr, -hh, 0.0),
			Vector3(-cr, hh, 0.0), Vector3(cr, hh, 0.0),
			Vector3(0.0, -hh, -cr), Vector3(0.0, -hh, cr),
			Vector3(0.0, hh, -cr), Vector3(0.0, hh, cr),
		])
	return PackedVector3Array()


## Does reading the full authored hull set change the roof suite's verdicts?
## Builds one roof body from `info["shape"]` (first hull, what the suite does
## today) and one from `info["shapes"]` (the authored union), then samples the
## same 5x5 height field the suite samples. Printed, not asserted.
func _probe_roof_union(loader: Node) -> void:
	for path: String in ["/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Mid_4x4", "/Game/Art/Environment/Urban/Roofs/SM_RoofUrbanB_Ext_Mid_6x8"]:
		for scale: Vector3 in [Vector3.ONE, Vector3(1.0, 1.0, 0.8)]:
			var info: Dictionary = loader.call("_get_mesh_and_shape", path) as Dictionary
			var mesh: Mesh = info.get("mesh") as Mesh
			var shapes: Array = info.get("shapes", []) as Array
			if mesh == null or shapes.is_empty():
				continue
			var first: Array = [shapes[0]]
			var first_offsets: Array = [(info.get("shape_offsets", []) as Array)[0]]
			var all_offsets: Array = info.get("shape_offsets", []) as Array
			var f_first: Dictionary = await _roof_field_probe(mesh, first, first_offsets, scale)
			var f_all: Dictionary = await _roof_field_probe(mesh, shapes, all_offsets, scale)
			print("D10_ROOF_UNION %s scale=%s elements=%d" % [path.get_file(), str(scale), shapes.size()])
			print("    first_hull: samples=%d apex=%.2f eave=%.2f pitch=%.1f" % [
				int(f_first["n"]), float(f_first["apex"]), float(f_first["eave"]), float(f_first["pitch"])])
			print("    all_hulls:  samples=%d apex=%.2f eave=%.2f pitch=%.1f" % [
				int(f_all["n"]), float(f_all["apex"]), float(f_all["eave"]), float(f_all["pitch"])])


func _roof_field_probe(mesh: Mesh, shapes: Array, offsets: Array, scale: Vector3) -> Dictionary:
	var base := Vector3(40000.0, 0.0, 40000.0)
	var use_shapes: Array = shapes
	var body_scale: Vector3 = Vector3.ONE
	if not scale.is_equal_approx(Vector3.ONE):
		# Jolt refuses a non-uniform CollisionShape3D.scale for convex shapes;
		# `_add_collider_shapes` bakes it, so the probe must too.
		use_shapes = (AC.scaled_variant("w10_roof_probe", {"shapes": shapes}, scale)["shapes"]) as Array
	else:
		body_scale = scale
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = base
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.scale = body_scale
	for i: int in range(use_shapes.size()):
		var cs := CollisionShape3D.new()
		cs.shape = use_shapes[i] as Shape3D
		cs.position = (offsets[i] as Transform3D).origin if i < offsets.size() else Vector3.ZERO
		body.add_child(cs)
	rig.add_child(body)
	await physics_frame
	await physics_frame
	var aabb: AABB = mesh.get_aabb()
	var top: float = aabb.position.y + aabb.size.y
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var pts: Array[Dictionary] = []
	for ix: int in range(5):
		for iz: int in range(5):
			var x: float = lerpf(aabb.position.x, aabb.position.x + aabb.size.x, (float(ix) + 0.5) / 5.0) * scale.x
			var z: float = lerpf(aabb.position.z, aabb.position.z + aabb.size.z, (float(iz) + 0.5) / 5.0) * scale.z
			var from: Vector3 = base + Vector3(x, top * scale.y + 2.0, z)
			var to: Vector3 = base + Vector3(x, top * scale.y - 12.0, z)
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
			if hit.is_empty():
				continue
			pts.append({"x": x, "z": z, "y": (hit["position"] as Vector3).y - base.y})
	var apex: float = -INF
	var eave: float = INF
	for p: Dictionary in pts:
		apex = maxf(apex, float(p["y"]))
		eave = minf(eave, float(p["y"]))
	var pitch: float = 0.0
	for i: int in range(pts.size()):
		for j: int in range(i + 1, pts.size()):
			var a: Dictionary = pts[i] as Dictionary
			var b: Dictionary = pts[j] as Dictionary
			var run: float = Vector2(float(b["x"]) - float(a["x"]), float(b["z"]) - float(a["z"])).length()
			if run < 0.25:
				continue
			pitch = maxf(pitch, rad_to_deg(atan2(absf(float(b["y"]) - float(a["y"])), run)))
	rig.queue_free()
	await physics_frame
	return {"n": pts.size(), "apex": apex, "eave": eave, "pitch": pitch}

