extends RefCounted
## Shared geometry for the authored device runtime layer.
##
## The producer (tools/parse_devices.py) emits device transforms in Godot
## metres with a column-major basis, and authored lengths/zone sizes in the
## cooked UE centimetres under their original property names. Nothing here
## rescales data silently: callers pass the unit they expect.
##
## The player body is represented as a vertical segment from the feet origin to
## the authored standing/crouch height. Detector volumes therefore behave like
## a capsule without adding the player's 0.35 m collision radius to every
## authored trigger length (a 7.748 m BeamLength must still reject a body whose
## origin is 7.9 m from the emitter while a standing body crosses a beam at
## 1.75 m and a crouched one does not).

const CM_TO_M: float = 0.01
## Authored by thief_character.gd: the crouch collider is 1.0 m and standing
## is 1.78 m (the same values the controller uses for its capsule).
const BODY_HEIGHT_STANDING_M: float = 1.78
const BODY_HEIGHT_CROUCH_M: float = 1.0


## Authored Godot transform from a devices_runtime record. Scale is never
## applied: every runtime device is emitted with scale [1,1,1] by design (the
## 14 acoustic portals keep their authored box scale in params.authored_scale
## and are data-only). A degenerate basis falls back to identity loudly enough
## for the caller to see it in the layer census.
static func transform_from_record(rec: Dictionary) -> Transform3D:
	var p_v: Variant = rec.get("pos", [0.0, 0.0, 0.0])
	var b_v: Variant = rec.get("basis", [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0])
	var p: Array = p_v as Array if p_v is Array else [0.0, 0.0, 0.0]
	var b: Array = b_v as Array if b_v is Array else [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
	var basis := Basis(
		Vector3(_at(b, 0), _at(b, 3), _at(b, 6)),
		Vector3(_at(b, 1), _at(b, 4), _at(b, 7)),
		Vector3(_at(b, 2), _at(b, 5), _at(b, 8))
	)
	if absf(basis.determinant()) < 0.000001:
		basis = Basis.IDENTITY
	return Transform3D(basis, Vector3(_at(p, 0), _at(p, 1), _at(p, 2)))


## Height of the target's authored body. Prefers the controller accessor, then
## the player's crouch flag, then a capsule collision shape, then standing.
static func body_height_m(body: Node) -> float:
	if body == null:
		return BODY_HEIGHT_STANDING_M
	if body.has_method("body_height_m"):
		return maxf(float(body.call("body_height_m")), 0.1)
	var crouch_v: Variant = body.get("is_crouching")
	if crouch_v is bool:
		return BODY_HEIGHT_CROUCH_M if bool(crouch_v) else BODY_HEIGHT_STANDING_M
	if body is CollisionObject3D:
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				var shape: Shape3D = (child as CollisionShape3D).shape
				if shape is CapsuleShape3D:
					return maxf((shape as CapsuleShape3D).height, 0.1)
				if shape is BoxShape3D:
					return maxf((shape as BoxShape3D).size.y, 0.1)
	return BODY_HEIGHT_STANDING_M


## Vertical body segment (feet -> head) in world space.
static func body_segment(body: Node3D) -> PackedVector3Array:
	if body == null:
		return PackedVector3Array()
	var feet: Vector3 = body.global_position
	return PackedVector3Array([feet, feet + Vector3.UP * body_height_m(body)])


## Point a device aims at: chest height rather than the feet origin.
static func body_aim_point(body: Node3D) -> Vector3:
	if body == null:
		return Vector3.ZERO
	return body.global_position + Vector3.UP * (body_height_m(body) * 0.7)


## Shortest distance between two finite 3D segments.
static func segment_segment_distance(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	var pts: PackedVector3Array = Geometry3D.get_closest_points_between_segments(a0, a1, b0, b1)
	if pts.size() < 2:
		return INF
	return pts[0].distance_to(pts[1])


## Shortest distance from a point to a finite 3D segment.
static func point_segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var denom: float = ab.length_squared()
	if denom < 0.0000001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)


## Slab-method segment vs axis-aligned box test in the box's own space.
static func segment_intersects_aabb(p0: Vector3, p1: Vector3, box: AABB) -> bool:
	var d: Vector3 = p1 - p0
	var tmin: float = 0.0
	var tmax: float = 1.0
	for axis: int in range(3):
		var mn: float = box.position[axis]
		var mx: float = box.end[axis]
		if absf(d[axis]) < 0.0000001:
			if p0[axis] < mn or p0[axis] > mx:
				return false
		else:
			var t1: float = (mn - p0[axis]) / d[axis]
			var t2: float = (mx - p0[axis]) / d[axis]
			if t1 > t2:
				var swap: float = t1
				t1 = t2
				t2 = swap
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return false
	return true


static func _at(values: Array, index: int) -> float:
	return float(values[index]) if index < values.size() else 0.0
