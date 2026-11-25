extends RefCounted
## Binary acoustic occlusion (RE-I-05): walls block, open portals pass.
##
## What ships authored: all 54 `DT_HearingStimProperties` rows declare
## `PropogateThroughOpenPortals`, `BP_TATAcousticPortal` places 285 portal boxes
## (7 sublevels, 100 cm cube at the component origin, per-instance scale on the
## root), and `HearingData.acoustic_portals()` already exposes every transform in
## Godot metres + basis + authored box scale. What the port had: `_hear` never
## raycast, so a guard heard a footstep through a wall (`docs/FIDELITY_GAPS.md`
## records "285 portals read-only" as a KNOWN gap).
##
## There is NO recoverable attenuation value: the dump carries no `AkAttenuation`
## asset and the DT has no wall-penalty field, so any dB/m number would be
## invented. The defensible model is therefore binary and it is the one the audit
## prescribes: a segment that crosses world geometry is heard only when the
## crossing lies inside an authored acoustic portal box, and a closed swinging
## door at that crossing blocks it (the portal says "sound may pass through this
## doorway", the door says "the doorway is shut").
##
## Fail-open by construction: no physics space, a zero-length segment, or a
## listener/source outside the tree hears the stimulus as before. Every
## fail-open and every block is counted, so the condition is measurable.

const HearingData = preload("res://src/ai/hearing_data.gd")

## World geometry layer the level loader builds (`level_loader._add_collider`).
const WORLD_MASK := 1
## A closed door counts as blocking when its origin is this close to the crossing.
const DOOR_GATE_RADIUS_M := 1.6
## Broad phase: skip portal boxes farther than this from the segment midpoint
## (half the longest authored box diagonal plus slack).
const PORTAL_BROAD_PHASE_M := 3.0

static var _portals: Array = []
static var _portals_loaded: bool = false
static var _blocks: int = 0
static var _passes: int = 0
static var _fail_open: int = 0
static var _portal_passes: int = 0
static var _door_blocks: int = 0
static var _enabled: bool = true


static func reset_stats() -> void:
	_blocks = 0
	_passes = 0
	_fail_open = 0
	_portal_passes = 0
	_door_blocks = 0


static func stats() -> Dictionary:
	return {
		"blocks": _blocks,
		"passes": _passes,
		"portal_passes": _portal_passes,
		"door_blocks": _door_blocks,
		"fail_open": _fail_open,
		"portals": _portals.size(),
		"enabled": _enabled,
	}


## Diagnostic switch (`--hearing-occlusion=off`), same shape as the other
## documented diagnostics. Off = hear through everything (pre-W8 behaviour).
static func set_enabled(on: bool) -> void:
	_enabled = on


static func enabled() -> bool:
	return _enabled


static func _ensure_portals() -> void:
	if _portals_loaded:
		return
	_portals_loaded = true
	_portals = HearingData.acoustic_portals()


static func portal_count() -> int:
	_ensure_portals()
	return _portals.size()


## Result of one segment test. `clear` is what callers act on.
## {"clear": bool, "crossed": bool, "blocked_at": Vector3,
##  "through_portal": bool, "door": String}
static func path(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Dictionary:
	if not _enabled:
		_passes += 1
		return {"clear": true, "crossed": false, "blocked_at": Vector3.ZERO, "through_portal": false, "door": "disabled"}
	if space == null:
		_fail_open += 1
		return {"clear": true, "crossed": false, "blocked_at": Vector3.ZERO, "through_portal": false, "door": "no_space"}
	if from.distance_squared_to(to) < 0.0001:
		_fail_open += 1
		return {"clear": true, "crossed": false, "blocked_at": Vector3.ZERO, "through_portal": false, "door": "degenerate"}
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, exclude)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		_passes += 1
		return {"clear": true, "crossed": false, "blocked_at": Vector3.ZERO, "through_portal": false, "door": ""}
	var at: Vector3 = hit.get("position", from) as Vector3
	var portal: bool = point_in_portal(at)
	if not portal:
		_blocks += 1
		return {"clear": false, "crossed": true, "blocked_at": at, "through_portal": false, "door": ""}
	var door: String = closed_door_at(at)
	if door != "":
		_door_blocks += 1
		_blocks += 1
		return {"clear": false, "crossed": true, "blocked_at": at, "through_portal": true, "door": door}
	_portal_passes += 1
	_passes += 1
	return {"clear": true, "crossed": true, "blocked_at": at, "through_portal": true, "door": ""}


## Convenience boolean for listeners that only need the verdict.
static func clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	return bool(path(space, from, to, exclude).get("clear", true))


## True when `point` lies inside any authored portal box (100 cm cube x the
## authored per-instance scale).
static func point_in_portal(point: Vector3) -> bool:
	_ensure_portals()
	for row_v: Variant in _portals:
		if not (row_v is Dictionary):
			continue
		if _point_in_row(row_v as Dictionary, point):
			return true
	return false


static func _point_in_row(row: Dictionary, point: Vector3) -> bool:
	var pos_v: Variant = row.get("pos", null)
	var basis_v: Variant = row.get("basis", null)
	if not (pos_v is Array) or (pos_v as Array).size() < 3:
		return false
	var origin := Vector3(float(pos_v[0]), float(pos_v[1]), float(pos_v[2]))
	if origin.distance_squared_to(point) > PORTAL_BROAD_PHASE_M * PORTAL_BROAD_PHASE_M:
		return false
	var b: Basis = Basis.IDENTITY
	if basis_v is Array and (basis_v as Array).size() >= 9:
		var a: Array = basis_v as Array
		# parse_tables flattens the basis component-major: Godot's Basis rows are
		# the basis vectors, so rows 0/1/2 come from a[0..2], a[3..5], a[6..8].
		b = Basis(
			Vector3(float(a[0]), float(a[1]), float(a[2])),
			Vector3(float(a[3]), float(a[4]), float(a[5])),
			Vector3(float(a[6]), float(a[7]), float(a[8])))
	var scale_v: Variant = row.get("scale", [1.0, 1.0, 1.0])
	var ext := Vector3(0.5, 0.5, 0.5)  # authored box extent 100 cm cube
	if scale_v is Array and (scale_v as Array).size() >= 3:
		ext *= Vector3(absf(float((scale_v as Array)[0])), absf(float((scale_v as Array)[1])), absf(float((scale_v as Array)[2])))
	var local: Vector3 = b.transposed() * (point - origin)
	return absf(local.x) <= ext.x and absf(local.y) <= ext.y and absf(local.z) <= ext.z


## Name of a closed swinging door at `point`, or "" when the doorway is open (or
## the door class is not loaded). `swinging_doors` is the runtime group name the
## loader and audio layer already publish (AGENTS rule 7).
static func closed_door_at(point: Vector3) -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ""
	for node: Node in tree.get_nodes_in_group("swinging_doors"):
		var door: Node3D = node as Node3D
		if door == null or not is_instance_valid(door):
			continue
		if door.global_position.distance_to(point) > DOOR_GATE_RADIUS_M:
			continue
		var open_v: Variant = door.get("is_open")
		var is_open: bool = open_v is bool and open_v == true
		if not is_open:
			return str(door.name)
	return ""


## World point a listener hears from: the source origin plus the port's chest
## height, so the segment runs listener-eye to source-body.
static func listener_eye(body: Node3D) -> Vector3:
	if body == null:
		return Vector3.ZERO
	return body.global_position + Vector3.UP * 1.5


static func source_point(origin: Vector3) -> Vector3:
	return origin + Vector3.UP * 1.0
