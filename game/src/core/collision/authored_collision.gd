extends RefCounted
## W9-P1: authored UE `AggGeom` simple collision as Godot shapes.
##
## Source of truth: `game/data/generated/mesh_collision.json`
## (`tat2.mesh_collision/1`, 1,992 meshes / 8,601 elements, mesh-local
## centimetres). Parsed ONCE per process (static state) and decoded into a
## compact form so the 17.6 MB raw JSON is released immediately; the per-mesh
## shape resources are built lazily and shared by every placed instance (the
## loader caches the result per UE path, so no instance ever parses JSON).
##
## Conversion binding, from `build/qa/w9/re-a1.md` (RE-A1, measured):
##   * `P(v) = Vector3(v.x, v.z, v.y) * 0.01` — cm -> m plus the Y/Z swap that
##     the GLB exporter itself applied (no sign flip). [AUTHORED, re-a1 §0/B1]
##   * `Basis = P·M·P` columns, exactly `tools/parse_tables.py`
##     `ue_rotator_to_mat3` + `ue_mat4_to_godot_trs` column order. [AUTHORED]
##   * box: the producer's `half_extent` field is the FULL extent (its name and
##     `notes` are wrong by 2×: UE `KBoxElem::X/Y/Z` are full extents — the
##     engine cube X=100 -> a 1 m GLB, and 453 axis-aligned meshes measure
##     `2·X / mesh_size` = 1.9997 median). So `size = Vector3(X, Z, Y) * 0.01`
##     with NO factor of two. [AUTHORED, re-a1 §3.1]
##   * sphere: `radius = Radius * 0.01`, unrotated. [AUTHORED, re-a1 §3.2]
##   * sphyl: UE's capsule axis is element-local Z and `Length` is the cylinder
##     segment only, so `height = (Length + 2*Radius) * 0.01` (Godot's height
##     includes both caps) and `radius = Radius * 0.01`. `P·M·P` already lands
##     local Z on Godot Y, which is `CapsuleShape3D`'s axis. [AUTHORED, re-a1 §3.3]
##   * convex: bake the element FTransform in UE space
##     (`v' = R_quat · (scale3d ⊙ v) + translation`, scale applied per axis,
##     order matters — 19 load-set hulls have a non-unit scale), then `P(v')`.
##     `aabb_min/max` is the AABB of the *pre-transform* vertices and is never
##     used as the placed bound. [AUTHORED, re-a1 §2.4/§3.4]
##
## One shape per instance is the budget: the loader caps collision at
## MAX_BUILDING_SHAPES / MAX_TOTAL_SHAPES (level_loader.gd:183-197). Encoding:
##   * all-primitive mesh       -> ONE shape (the primitive itself when the mesh
##                                 has a single element, else an exact
##                                 tessellation of every element).
##   * mesh with convex hulls   -> one shape per element (ConvexPolygonShape3D
##                                 for the hulls, primitives for the rest),
##                                 shared across instances.
##   * over the element/cost cap -> ONE coalesced trimesh of the element AABBs,
##                                 `reduced = true`, counted and named by the
##                                 loader. Never silent.
## `MAX_ELEMENT_SHAPE_COST` is the *extra* shape cost above the one-per-instance
## floor (`(elements - 1) * instances`). It exists because the measured authored
## set needs ~30.9 k shapes against a 32 k world budget; the 16 meshes it
## coalesces are printed by `stats()` consumers and named in the wave report.

## Element kinds in the compact record.
const KIND_BOX: int = 0
const KIND_SPHERE: int = 1
const KIND_CAPSULE: int = 2
const KIND_CONVEX: int = 3

## `ECollisionEnabled::` states that the Guildhall load set actually contains.
const ENABLED_PHYSICS: int = 0
const ENABLED_QUERY_ONLY: int = 1
const ENABLED_NONE: int = 2

const DATA_PATH: String = "res://data/generated/mesh_collision.json"
const CM_TO_M: float = 0.01
## UE's default (`CTF_UseDefaultCollision`) collides with the render triangles
## when the mesh has no simple collision, so a render trimesh IS the authored
## answer for those. Placed meshes with no dump at all in `extracted/json` are
## all under this prefix (measured: 10 of the 79 Guildhall absent paths, 13 of
## the 107 level-JSON paths; the other 69/94 DO have a BodySetup dump with no
## `AggGeom`). Those keep the loader's AABB heuristic. [re-a1 §B6]
const ABSENT_NO_DUMP_PREFIX: String = "/game/test/"

## Per-mesh element cap: above this a convex set coalesces to one hull of
## element AABBs. 16 keeps every door frame / arch / stair flight / pitched roof
## in the load set per-element; the meshes it touches are 20+ hull detail props.
const MAX_CONVEX_ELEMENTS_PER_MESH: int = 16
## Extra-shape budget per mesh, `(elements - 1) * instances`. 250 was chosen
## from the measured curve: 150 -> 29.6 k shapes, 250 -> 30.9 k, 300 -> 31.2 k,
## 400 -> 32.2 k (over MAX_TOTAL_SHAPES). Single-element meshes cost 0 here, so
## a one-hull mesh with 1,000 instances is never degraded.
const MAX_ELEMENT_SHAPE_COST: int = 250

## Fixed, documented tessellation for the coalesced/primitive trimeshes. A box
## needs 12 triangles exactly; spheres/capsules are tessellated finely enough to
## keep the authored AABB within a millimetre of the true surface.
const SPHERE_SEGMENTS: int = 12
const SPHERE_RINGS: int = 8
const CAPSULE_SEGMENTS: int = 12
const CAPSULE_CAP_RINGS: int = 3
## Jolt rejects a zero-sized box; `/Engine/BasicShapes/Plane` authors Z=0.
const MIN_HALF_EXTENT_M: float = 0.01

## Compact DB: ue_path -> {enabled:int, complex:bool, elements:Array[Dictionary]}.
static var _records: Dictionary = {}
static var _loaded: bool = false
static var _json_ms: int = -1
static var _mesh_count: int = 0
static var _element_count: int = 0
static var _convex_count: int = 0
## Resolved encoding cache: "<ue_path>|<instances>" -> resolve() result.
static var _cache: Dictionary = {}
## Non-uniform instance-scale variants: "<ue_path>|<sx>_<sy>_<sz>" -> shapes.
## Jolt refuses a non-uniform `CollisionShape3D.scale` for capsule / convex /
## trimesh shapes (it logs "Failed to correctly scale shape ... not supported by
## Jolt Physics" per shape per tick and falls back to an averaged uniform
## scale), so the loader asks for a baked variant instead. Distinct non-uniform
## scales in the shipped levels are few (the 1.0598 case is one), so this stays
## tiny; the key includes round-to-4-decimals so float noise cannot explode it.
static var _scaled_cache: Dictionary = {}


## Scale-baked copy of an authored encoding: the same shape set with `scale`
## multiplied into each shape's own local axes — exactly what `CS.scale` did,
## but representable by Jolt for every shape type.
##
## Approximation for the two primitives that cannot represent an ellipse/ovoid:
## a capsule keeps a circular cross-section (`radius *= mean(sx, sz)`, `height
## *= sy` — its local axis is Y, see `_decode_element`) and a sphere uses the
## mean of the three axes. Boxes, convex hulls and trimeshes (including
## `complex_default` render trimeshes) are scaled exactly, per axis.
static func scaled_variant(ue_path: String, base: Dictionary, scale: Vector3) -> Dictionary:
	var key: String = "%s|%.4f_%.4f_%.4f" % [ue_path, scale.x, scale.y, scale.z]
	if _scaled_cache.has(key):
		return _scaled_cache[key]
	var src_shapes: Array = base["shapes"] as Array
	var out_shapes: Array = []
	out_shapes.resize(src_shapes.size())
	for i: int in range(src_shapes.size()):
		out_shapes[i] = _scaled_shape(src_shapes[i] as Shape3D, scale)
	var out: Dictionary = base.duplicate(false)
	out["shapes"] = out_shapes
	_scaled_cache[key] = out
	return out


static func clear_scaled_cache() -> void:
	_scaled_cache.clear()


static func _scaled_shape(sh: Shape3D, s: Vector3) -> Shape3D:
	if sh == null:
		return null
	var ax: float = absf(s.x)
	var ay: float = absf(s.y)
	var az: float = absf(s.z)
	if sh is BoxShape3D:
		var box := BoxShape3D.new()
		box.size = Vector3((sh as BoxShape3D).size.x * ax, (sh as BoxShape3D).size.y * ay, (sh as BoxShape3D).size.z * az)
		return box
	if sh is SphereShape3D:
		var sph := SphereShape3D.new()
		sph.radius = maxf((sh as SphereShape3D).radius * (ax + ay + az) / 3.0, MIN_HALF_EXTENT_M)
		return sph
	if sh is CapsuleShape3D:
		var cap := CapsuleShape3D.new()
		var src: CapsuleShape3D = sh as CapsuleShape3D
		cap.radius = maxf(src.radius * (ax + az) * 0.5, MIN_HALF_EXTENT_M)
		cap.height = maxf(src.height * ay, 2.0 * cap.radius + 0.001)
		return cap
	if sh is ConvexPolygonShape3D:
		var pts: PackedVector3Array = (sh as ConvexPolygonShape3D).points
		var out_pts := PackedVector3Array()
		out_pts.resize(pts.size())
		for i: int in range(pts.size()):
			out_pts[i] = Vector3(pts[i].x * ax, pts[i].y * ay, pts[i].z * az)
		var hull := ConvexPolygonShape3D.new()
		hull.points = out_pts
		return hull
	if sh is ConcavePolygonShape3D:
		var faces: PackedVector3Array = (sh as ConcavePolygonShape3D).get_faces()
		var out_faces := PackedVector3Array()
		out_faces.resize(faces.size())
		for i: int in range(faces.size()):
			out_faces[i] = Vector3(faces[i].x * ax, faces[i].y * ay, faces[i].z * az)
		var tris := ConcavePolygonShape3D.new()
		tris.set_faces(out_faces)
		tris.backface_collision = (sh as ConcavePolygonShape3D).backface_collision
		return tris
	# Unknown shape family: keep it shared and let the caller fall back to
	# `CollisionShape3D.scale` (the pre-W9 behaviour) rather than guessing.
	return sh


## One line of counters for the loader's `AUTHORED_COLLISION` summary.
static func stats() -> Dictionary:
	_ensure_loaded()
	return {
		"meshes": _mesh_count,
		"elements": _element_count,
		"convex": _convex_count,
		"load_ms": _json_ms,
	}


static func is_loaded() -> bool:
	return _loaded


## Resolve one UE package path to its Godot collision encoding.
##
## Returns:
##   source:  "hull"            authored elements, one shape per element
##            "prims"           authored elements, one coalesced/primitive shape
##            "complex_default" no simple collision in UE -> render trimesh
##            "absent"          no authored data at all -> loader heuristic
##            "no_collision"    authored NoCollision -> no shape
##   shapes:  Array[Shape3D] (shared resources; empty for the loader-built cases)
##   offsets: Array[Transform3D], same length, applied as `instance_tr * offset`
##   elements, reduced, enabled
##
## `instances` is the placement count for this path in the current load; it only
## feeds the cost cap, and it is part of the cache key so two loads with
## different placement counts can never share a stale reduction decision.
static func resolve(ue_path: String, instances: int = 1) -> Dictionary:
	_ensure_loaded()
	var key: String = "%s|%d" % [ue_path, instances]
	if _cache.has(key):
		return _cache[key]
	var out: Dictionary = {
		"source": "absent",
		"shapes": [] as Array,
		"offsets": [] as Array,
		"elements": 0,
		"reduced": false,
		"enabled": "QueryAndPhysics",
	}
	var rec: Dictionary = _records.get(ue_path, {}) as Dictionary
	if rec.is_empty():
		# No AggGeom record. 69/79 Guildhall paths still have a BodySetup with no
		# AggGeom (UE complex-as-simple = the render triangles are the collision);
		# the 10 under /Game/Test/ have no dump at all and keep the heuristic.
		out["source"] = "absent" if ue_path.to_lower().begins_with(ABSENT_NO_DUMP_PREFIX) else "complex_default"
		_cache[key] = out
		return out
	var enabled: int = int(rec["enabled"])
	out["enabled"] = _enabled_name(enabled)
	var els: Array = rec["elements"] as Array
	out["elements"] = els.size()
	if enabled == ENABLED_NONE:
		out["source"] = "no_collision"
		_cache[key] = out
		return out
	if bool(rec["complex"]):
		# `CTF_UseComplexAsSimple`: UE ignores the authored simple elements.
		out["source"] = "complex_default"
		_cache[key] = out
		return out
	if els.is_empty():
		# Producer never emits an empty element list for a kept record; if it
		# ever does, the render mesh is the only authored answer left.
		out["source"] = "complex_default"
		_cache[key] = out
		return out
	var convex: int = 0
	for el_var: Variant in els:
		if int((el_var as Dictionary)["kind"]) == KIND_CONVEX:
			convex += 1
	out["convex"] = convex
	var shapes: Array = out["shapes"] as Array
	var offsets: Array = out["offsets"] as Array
	if convex == 0:
		# Primitive-only: one shape per instance. A single element keeps its
		# native primitive (exact, cheap); a multi-element set tessellates into
		# one closed trimesh.
		if els.size() == 1:
			shapes.append(_shape_of(els[0] as Dictionary))
			offsets.append((els[0] as Dictionary)["xf"] as Transform3D)
		else:
			shapes.append(_tessellate_elements(els))
			offsets.append(Transform3D.IDENTITY)
		out["source"] = "prims"
		_cache[key] = out
		return out
	var n: int = maxi(instances, 1)
	if els.size() > MAX_CONVEX_ELEMENTS_PER_MESH or (els.size() - 1) * n > MAX_ELEMENT_SHAPE_COST:
		shapes.append(_coalesce_element_aabbs(els))
		offsets.append(Transform3D.IDENTITY)
		out["reduced"] = true
		out["source"] = "hull"
		_cache[key] = out
		return out
	for el_var2: Variant in els:
		var el: Dictionary = el_var2 as Dictionary
		shapes.append(_shape_of(el))
		offsets.append(el["xf"] as Transform3D)
	out["source"] = "hull"
	_cache[key] = out
	return out


## Clear the resolved-shape cache (per-load bookkeeping only; the JSON stays).
static func reset_cache() -> void:
	_cache.clear()


static func _enabled_name(flag: int) -> String:
	match flag:
		ENABLED_QUERY_ONLY:
			return "QueryOnly"
		ENABLED_NONE:
			return "NoCollision"
	return "QueryAndPhysics"


static func _enabled_flag(name: String) -> int:
	if name.ends_with("QueryOnly"):
		return ENABLED_QUERY_ONLY
	if name.ends_with("NoCollision"):
		return ENABLED_NONE
	# QueryAndPhysics, PhysicsOnly and the absent default all carry physics in
	# the shipped load set (element-level PhysicsOnly exists only on skeletal
	# PhysicsAssets, never on a placed static mesh).
	return ENABLED_PHYSICS


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var t0: int = Time.get_ticks_msec()
	var txt: String = FileAccess.get_file_as_string(DATA_PATH)
	if txt.is_empty():
		push_warning("[authored_collision] cannot read %s; authored collision has no data (the loader falls back to the AABB heuristic)" % DATA_PATH)
		_json_ms = 0
		return
	var parsed: Variant = JSON.parse_string(txt)
	txt = ""
	if not (parsed is Dictionary):
		push_warning("[authored_collision] %s is not a JSON object; authored collision disabled" % DATA_PATH)
		_json_ms = 0
		return
	var meshes: Dictionary = (parsed as Dictionary).get("meshes", {}) as Dictionary
	for key_var: Variant in meshes.keys():
		var ue_path: String = str(key_var)
		var rec: Dictionary = meshes[key_var] as Dictionary
		var els_in: Array = rec.get("elements", []) as Array
		var els_out: Array = []
		els_out.resize(els_in.size())
		for i: int in range(els_in.size()):
			var el: Dictionary = els_in[i] as Dictionary
			els_out[i] = _decode_element(el)
			if int((els_out[i] as Dictionary)["kind"]) == KIND_CONVEX:
				_convex_count += 1
		_element_count += els_out.size()
		_records[ue_path] = {
			"enabled": _enabled_flag(str(rec.get("collision_enabled", ""))),
			"complex": bool(rec.get("complex_as_simple", false)),
			"elements": els_out,
		}
	_mesh_count = _records.size()
	parsed = null
	meshes = {}
	_json_ms = Time.get_ticks_msec() - t0


## Decode one producer element into compact mesh-space data (metres).
## `xf` is the element-local -> mesh-local transform; a convex hull bakes its
## FTransform into the points and keeps an identity xf.
static func _decode_element(el: Dictionary) -> Dictionary:
	var kind: String = str(el.get("type", ""))
	var center: Vector3 = _p3(el.get("center"))
	match kind:
		"box":
			# `half_extent` holds the FULL UE extent (re-a1 §3.1): X,Y,Z along UE
			# axes -> Vector3(X, Z, Y) after the Y/Z swap, no factor of two.
			var ext: Vector3 = _p3(el.get("half_extent"))
			var size := Vector3(
				maxf(absf(ext.x), MIN_HALF_EXTENT_M * 2.0),
				maxf(absf(ext.y), MIN_HALF_EXTENT_M * 2.0),
				maxf(absf(ext.z), MIN_HALF_EXTENT_M * 2.0))
			return {"kind": KIND_BOX, "size": size, "xf": Transform3D(_rotator_basis(el.get("rotation")), center)}
		"sphere":
			return {"kind": KIND_SPHERE, "radius": maxf(float(el.get("radius", 0.0)) * CM_TO_M, MIN_HALF_EXTENT_M), "xf": Transform3D(Basis(), center)}
		"sphyl":
			# UE: axis = element-local Z, Length = cylinder segment only, total =
			# Length + 2*Radius == Godot `CapsuleShape3D.height` (re-a1 §3.3).
			var rad: float = maxf(float(el.get("radius", 0.0)) * CM_TO_M, MIN_HALF_EXTENT_M)
			var height: float = float(el.get("length", 0.0)) * CM_TO_M + 2.0 * rad
			return {
				"kind": KIND_CAPSULE,
				"radius": rad,
				"height": maxf(height, 2.0 * rad + 0.001),
				"xf": Transform3D(_rotator_basis(el.get("rotation")), center),
			}
		"convex":
			return {"kind": KIND_CONVEX, "points": _baked_points(el), "xf": Transform3D.IDENTITY}
	push_warning("[authored_collision] unknown element type '%s'; replaced by an empty hull" % kind)
	return {"kind": KIND_CONVEX, "points": PackedVector3Array(), "xf": Transform3D.IDENTITY}


## `v' = R_quat · (scale3d ⊙ v) + translation` in UE space, then P(·) * 0.01.
static func _baked_points(el: Dictionary) -> PackedVector3Array:
	var flat: Array = el.get("vertices_flat", []) as Array
	var out := PackedVector3Array()
	if flat.size() < 9:
		return out
	var t: Dictionary = el.get("transform", {}) as Dictionary
	var r: Dictionary = t.get("rotation", {}) as Dictionary
	var q := Quaternion(float(r.get("X", 0.0)), float(r.get("Y", 0.0)), float(r.get("Z", 0.0)), float(r.get("W", 1.0))).normalized()
	var s: Array = t.get("scale3d", [1.0, 1.0, 1.0]) as Array
	var sc := Vector3(float(s[0]) if s.size() == 3 else 1.0, float(s[1]) if s.size() == 3 else 1.0, float(s[2]) if s.size() == 3 else 1.0)
	var tr: Array = t.get("translation", [0.0, 0.0, 0.0]) as Array
	var tv := Vector3(float(tr[0]) if tr.size() == 3 else 0.0, float(tr[1]) if tr.size() == 3 else 0.0, float(tr[2]) if tr.size() == 3 else 0.0)
	var n: int = flat.size() / 3
	out.resize(n)
	for i: int in range(n):
		var v := Vector3(float(flat[i * 3]), float(flat[i * 3 + 1]), float(flat[i * 3 + 2]))
		v = q * Vector3(v.x * sc.x, v.y * sc.y, v.z * sc.z) + tv
		out[i] = Vector3(v.x, v.z, v.y) * CM_TO_M
	return out


## UE FRotator (degrees) -> Godot mesh-space basis, `P·M·P`.
## Copied from `tools/parse_tables.py` (`ue_rotator_to_mat3` +
## `ue_mat4_to_godot_trs` column order); do not re-derive. The negated `m02`
## is the documented repo fix that keeps the basis orthonormal.
static func _rotator_basis(rot_v: Variant) -> Basis:
	var rot: Dictionary = rot_v as Dictionary if rot_v is Dictionary else {}
	var p: float = deg_to_rad(float(rot.get("pitch", 0.0)))
	var y: float = deg_to_rad(float(rot.get("yaw", 0.0)))
	var rr: float = deg_to_rad(float(rot.get("roll", 0.0)))
	var cp: float = cos(p)
	var sp: float = sin(p)
	var cy: float = cos(y)
	var sy: float = sin(y)
	var cr: float = cos(rr)
	var sr: float = sin(rr)
	var m00: float = cp * cy
	var m01: float = sr * sp * cy - cr * sy
	var m02: float = -(cr * sp * cy + sr * sy)
	var m10: float = cp * sy
	var m11: float = sr * sp * sy + cr * cy
	var m12: float = sr * cy - cr * sp * sy
	var m20: float = sp
	var m21: float = -sr * cp
	var m22: float = cr * cp
	return Basis(Vector3(m00, m20, m10), Vector3(m02, m22, m12), Vector3(m01, m21, m11))


## UE cm vector (JSON array) -> Godot metres with the Y/Z swap.
static func _p3(v: Variant) -> Vector3:
	if not (v is Array):
		return Vector3.ZERO
	var a: Array = v as Array
	if a.size() < 3:
		return Vector3.ZERO
	return Vector3(float(a[0]), float(a[2]), float(a[1])) * CM_TO_M


static func _shape_of(el: Dictionary) -> Shape3D:
	match int(el["kind"]):
		KIND_BOX:
			var box := BoxShape3D.new()
			box.size = el["size"] as Vector3
			return box
		KIND_SPHERE:
			var sph := SphereShape3D.new()
			sph.radius = float(el["radius"])
			return sph
		KIND_CAPSULE:
			var cap := CapsuleShape3D.new()
			cap.radius = float(el["radius"])
			cap.height = float(el["height"])
			return cap
	var hull := ConvexPolygonShape3D.new()
	var pts: PackedVector3Array = el["points"] as PackedVector3Array
	if pts.is_empty():
		hull.points = PackedVector3Array([Vector3.ZERO, Vector3(0.01, 0.0, 0.0), Vector3(0.0, 0.01, 0.0), Vector3(0.0, 0.0, 0.01)])
	else:
		hull.points = pts
	return hull


## Exact closed trimesh of every primitive element, in mesh-local metres.
## Convex hulls are NOT handled here (they are not representable as triangles
## without index data); callers only route primitive-only sets to this path.
static func _tessellate_elements(els: Array) -> ConcavePolygonShape3D:
	var tris := PackedVector3Array()
	for el_var: Variant in els:
		var el: Dictionary = el_var as Dictionary
		var xf: Transform3D = el["xf"] as Transform3D
		match int(el["kind"]):
			KIND_BOX:
				_append_box(tris, xf, Vector3.ZERO, (el["size"] as Vector3) * 0.5)
			KIND_SPHERE:
				_append_sphere(tris, xf, float(el["radius"]))
			KIND_CAPSULE:
				_append_capsule(tris, xf, float(el["radius"]), float(el["height"]))
			_:
				# Defensive: a convex element reaching this path is encoded by its
				# element-space AABB so the mesh is never left with a hole.
				_append_box(tris, xf, Vector3.ZERO, aabb_half_extent(el["points"] as PackedVector3Array))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(tris)
	# Closed authored solids: collide from both sides so a winding slip can
	# never open a wall (UE's simple collision is solid from inside too).
	shape.backface_collision = true
	return shape


## One trimesh over the element AABBs (the measured over-cap reduction).
static func _coalesce_element_aabbs(els: Array) -> ConcavePolygonShape3D:
	var tris := PackedVector3Array()
	for el_var: Variant in els:
		var el: Dictionary = el_var as Dictionary
		var xf: Transform3D = el["xf"] as Transform3D
		match int(el["kind"]):
			KIND_BOX:
				_append_box(tris, xf, Vector3.ZERO, (el["size"] as Vector3) * 0.5)
			KIND_SPHERE:
				var r: float = float(el["radius"])
				_append_box(tris, xf, Vector3.ZERO, Vector3(r, r, r))
			KIND_CAPSULE:
				var cr: float = float(el["radius"])
				_append_box(tris, xf, Vector3.ZERO, Vector3(cr, float(el["height"]) * 0.5, cr))
			_:
				var pts: PackedVector3Array = el["points"] as PackedVector3Array
				if pts.is_empty():
					continue
				var mn := pts[0]
				var mx := pts[0]
				for p: Vector3 in pts:
					mn = mn.min(p)
					mx = mx.max(p)
				_append_box(tris, Transform3D.IDENTITY, (mn + mx) * 0.5, (mx - mn) * 0.5)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(tris)
	shape.backface_collision = true
	return shape


static func aabb_half_extent(pts: PackedVector3Array) -> Vector3:
	if pts.is_empty():
		return Vector3(MIN_HALF_EXTENT_M, MIN_HALF_EXTENT_M, MIN_HALF_EXTENT_M)
	var mn := pts[0]
	var mx := pts[0]
	for p: Vector3 in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return (mx - mn) * 0.5


## 12 triangles, outward winding (Godot front faces are clockwise).
static func _append_box(tris: PackedVector3Array, xf: Transform3D, center: Vector3, half: Vector3) -> void:
	var h := Vector3(maxf(absf(half.x), MIN_HALF_EXTENT_M), maxf(absf(half.y), MIN_HALF_EXTENT_M), maxf(absf(half.z), MIN_HALF_EXTENT_M))
	var c: Vector3 = center
	# 8 corners in Godot mesh space: 0..3 bottom (-y) CCW seen from +y, 4..7 top.
	var v: Array[Vector3] = [
		xf * (c + Vector3(-h.x, -h.y, -h.z)),
		xf * (c + Vector3(h.x, -h.y, -h.z)),
		xf * (c + Vector3(h.x, -h.y, h.z)),
		xf * (c + Vector3(-h.x, -h.y, h.z)),
		xf * (c + Vector3(-h.x, h.y, -h.z)),
		xf * (c + Vector3(h.x, h.y, -h.z)),
		xf * (c + Vector3(h.x, h.y, h.z)),
		xf * (c + Vector3(-h.x, h.y, h.z)),
	]
	# Faces as (a, b, c, d) quads; each emitted as two triangles.
	var quads: Array = [
		[4, 5, 6, 7], # +y
		[0, 3, 2, 1], # -y
		[3, 7, 6, 2], # +z
		[1, 2, 6, 5], # +x
		[0, 4, 7, 3], # -x
		[0, 1, 5, 4], # -z
	]
	for q_var: Variant in quads:
		var q: Array = q_var as Array
		_append_quad(tris, v[int(q[0])], v[int(q[1])], v[int(q[2])], v[int(q[3])])


## UV sphere in element-local space (axis-agnostic), radius r.
static func _append_sphere(tris: PackedVector3Array, xf: Transform3D, r: float) -> void:
	var rings: int = SPHERE_RINGS
	var segs: int = SPHERE_SEGMENTS
	for i: int in range(rings):
		var p0: float = PI * (float(i) / float(rings)) - PI * 0.5
		var p1: float = PI * (float(i + 1) / float(rings)) - PI * 0.5
		for j: int in range(segs):
			var a0: float = TAU * (float(j) / float(segs))
			var a1: float = TAU * (float(j + 1) / float(segs))
			var v00: Vector3 = xf * Vector3(cos(p0) * cos(a0), sin(p0), cos(p0) * sin(a0)) * r
			var v01: Vector3 = xf * Vector3(cos(p0) * cos(a1), sin(p0), cos(p0) * sin(a1)) * r
			var v10: Vector3 = xf * Vector3(cos(p1) * cos(a0), sin(p1), cos(p1) * sin(a0)) * r
			var v11: Vector3 = xf * Vector3(cos(p1) * cos(a1), sin(p1), cos(p1) * sin(a1)) * r
			_append_quad(tris, v00, v01, v11, v10)


## Capsule in the element's xf-local frame. That frame is `S · UE_local`
## (`S` = the Y/Z swap), so the authored UE-Z capsule axis lands on local **Y**
## — which is also `CapsuleShape3D`'s own axis, so `xf` needs no extra ±90°.
## `height` is the TOTAL length including both caps.
static func _append_capsule(tris: PackedVector3Array, xf: Transform3D, r: float, height: float) -> void:
	var segs: int = CAPSULE_SEGMENTS
	var caps: int = CAPSULE_CAP_RINGS
	var hy: float = maxf(height * 0.5 - r, 0.0)
	for j: int in range(segs):
		var a0: float = TAU * (float(j) / float(segs))
		var a1: float = TAU * (float(j + 1) / float(segs))
		var b0: Vector3 = xf * Vector3(cos(a0) * r, -hy, sin(a0) * r)
		var b1: Vector3 = xf * Vector3(cos(a1) * r, -hy, sin(a1) * r)
		var t0: Vector3 = xf * Vector3(cos(a0) * r, hy, sin(a0) * r)
		var t1: Vector3 = xf * Vector3(cos(a1) * r, hy, sin(a1) * r)
		_append_quad(tris, b0, b1, t1, t0)
		# Top cap: rings from the cylinder edge to the pole.
		for k: int in range(caps):
			var q0: float = PI * 0.5 * (float(k) / float(caps))
			var q1: float = PI * 0.5 * (float(k + 1) / float(caps))
			var c00: Vector3 = xf * Vector3(cos(q0) * cos(a0) * r, hy + sin(q0) * r, cos(q0) * sin(a0) * r)
			var c01: Vector3 = xf * Vector3(cos(q0) * cos(a1) * r, hy + sin(q0) * r, cos(q0) * sin(a1) * r)
			var c10: Vector3 = xf * Vector3(cos(q1) * cos(a0) * r, hy + sin(q1) * r, cos(q1) * sin(a0) * r)
			var c11: Vector3 = xf * Vector3(cos(q1) * cos(a1) * r, hy + sin(q1) * r, cos(q1) * sin(a1) * r)
			_append_quad(tris, c00, c01, c11, c10)
		# Bottom cap (mirrored).
		for k2: int in range(caps):
			var d0: float = PI * 0.5 * (float(k2) / float(caps))
			var d2: float = PI * 0.5 * (float(k2 + 1) / float(caps))
			var e00: Vector3 = xf * Vector3(cos(d0) * cos(a0) * r, -hy - sin(d0) * r, cos(d0) * sin(a0) * r)
			var e01: Vector3 = xf * Vector3(cos(d0) * cos(a1) * r, -hy - sin(d0) * r, cos(d0) * sin(a1) * r)
			var e10: Vector3 = xf * Vector3(cos(d2) * cos(a0) * r, -hy - sin(d2) * r, cos(d2) * sin(a0) * r)
			var e11: Vector3 = xf * Vector3(cos(d2) * cos(a1) * r, -hy - sin(d2) * r, cos(d2) * sin(a1) * r)
			_append_quad(tris, e00, e11, e10, e01)


## Quad -> 2 triangles, Godot's clockwise front-face order.
static func _append_quad(tris: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tris.append(a)
	tris.append(c)
	tris.append(b)
	tris.append(a)
	tris.append(d)
	tris.append(c)
