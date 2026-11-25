extends RefCounted
## Navigation steering for guards and civilians (RE-I-10), the AI-side consumer.
##
## What ships authored: a navmesh per map, `NavArea_Bushes/_Door/_PrivateArea`,
## four `GA_NavLink_*` behaviours, `EQS_FindNavigableLocationNearQuerier`,
## `TATPathFollowingComponent` on every `AIC_*`. What the port had: no
## `NavigationRegion3D`, no `NavigationAgent3D`, no `map_get_path` -- every
## patrol, chase and investigation was straight-line `move_and_slide`, and 113 of
## 173 multi-point patrol paths turn more than 30 degrees (RE-I-06/RE-I-10).
##
## Splitting the work: *baking* a NavigationRegion3D per loaded map is T09's
## (level_loader geometry/placement), so this module never bakes. It consumes a
## map if one exists and **degrades explicitly** when it does not:
##   * `state == STATE_READY`  - a map with a region is synced, paths are used;
##   * `state == STATE_NO_MAP` - no navigation map/region; straight-line
##     steering plus one loud warning per process (`degraded_reason`), and
##     `degraded_frames()` counts the frames spent without navigation so the
##     condition is measurable instead of silent.
## A map that appears later (T09's bake finishing after spawn) is picked up on
## the next `step_towards` call; the agent is created lazily so a map-less
## session never instantiates a NavigationAgent3D (which would warn per agent).
##
## Arrival radius is the port's existing 1.0 m waypoint gate
## (`guard_ai._patrol_service_waypoint`); this module only supplies direction.

const STATE_UNKNOWN := "unknown"
const STATE_READY := "ready"
const STATE_NO_MAP := "no_map"

## Repath throttle: a target that has not moved more than this is not re-pathed
## every frame (NavigationAgent3D already throttles internally; this keeps the
## target set cost off the hot path for a guard standing still).
const RETARGET_MIN_MOVE_M := 0.35
const AGENT_RADIUS_M := 0.45
const AGENT_HEIGHT_M := 2.0
const PATH_DESIRED_DISTANCE_M := 0.6

static var _degraded_warned: bool = false
static var _degraded_frames_total: int = 0
static var _ready_frames_total: int = 0

var _body: Node3D
var _agent: NavigationAgent3D
var _target: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _state: String = STATE_UNKNOWN
var _degraded_frames: int = 0
var _ready_frames: int = 0
var _repaths: int = 0
var _empty_paths: int = 0


func setup(body: Node3D) -> void:
	_body = body
	_state = STATE_UNKNOWN


func state() -> String:
	return _state


func degraded_frames() -> int:
	return _degraded_frames


func ready_frames() -> int:
	return _ready_frames


func repath_count() -> int:
	return _repaths


func empty_path_count() -> int:
	return _empty_paths


static func degraded_frames_total() -> int:
	return _degraded_frames_total


static func ready_frames_total() -> int:
	return _ready_frames_total


static func reset_stats() -> void:
	_degraded_warned = false
	_degraded_frames_total = 0
	_ready_frames_total = 0


## Navigation map of this body's world, or an invalid RID.
func _nav_map() -> RID:
	if _body == null or not _body.is_inside_tree() or _body.get_world_3d() == null:
		return RID()
	var world: World3D = _body.get_world_3d()
	if not world.has_method("get_navigation_map"):
		return RID()
	return world.get_navigation_map()


## True when a navigation map exists, has been synchronised at least once AND
## carries at least one navigation region (i.e. a navmesh has actually been
## baked). Godot's default map syncs with zero regions, so iteration id alone is
## not evidence of a usable map. Queries before the first sync log an engine
## error, so those are skipped too.
func map_ready() -> bool:
	var map: RID = _nav_map()
	if not map.is_valid():
		return false
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	return NavigationServer3D.map_get_regions(map).size() > 0


func _ensure_agent() -> bool:
	if _agent != null and is_instance_valid(_agent):
		return true
	if _body == null or not _body.is_inside_tree():
		return false
	if not map_ready():
		return false
	_agent = NavigationAgent3D.new()
	_agent.name = "NavAgent"
	_agent.radius = AGENT_RADIUS_M
	_agent.height = AGENT_HEIGHT_M
	_agent.path_desired_distance = PATH_DESIRED_DISTANCE_M
	_agent.target_desired_distance = 0.5
	_agent.avoidance_enabled = false
	_body.add_child(_agent)
	return true


## Unit direction (XZ) the body should move this frame to make progress toward
## `target`, plus the distance left. Falls back to straight-line when there is no
## navigation data; callers keep their own speed and their own `move_and_slide`.
func step_towards(target: Vector3) -> Vector3:
	if _body == null:
		return Vector3.ZERO
	if not map_ready():
		_note_degraded()
		return _straight(target)
	if _ensure_agent():
		_state = STATE_READY
		_ready_frames += 1
		_ready_frames_total += 1
		if not _has_target or _target.distance_to(target) > RETARGET_MIN_MOVE_M:
			_target = target
			_has_target = true
			_agent.target_position = target
			_repaths += 1
		var next: Vector3 = _agent.get_next_path_position()
		var dir: Vector3 = next - _body.global_position
		dir.y = 0.0
		if dir.length() < 0.001:
			# A path that lands on the body (already there, or a degenerate map
			# point) must not freeze the caller: aim straight and let its own
			# arrival test decide.
			_empty_paths += 1
			return _straight(target)
		return dir.normalized()
	_note_degraded()
	return _straight(target)


func _straight(target: Vector3) -> Vector3:
	var dir: Vector3 = target - _body.global_position
	dir.y = 0.0
	if dir.length() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()


func _note_degraded() -> void:
	_state = STATE_NO_MAP
	_degraded_frames += 1
	_degraded_frames_total += 1
	if _degraded_warned:
		return
	_degraded_warned = true
	push_warning("[nav_steering] no synchronised navigation map (no NavigationRegion3D baked for this map); AI uses straight-line steering and will press into corners. Navmesh baking is T09's; this is the documented degradation (RE-I-10).")


## Planar distance left to the current target, straight-line. Used by arrival
## gates that must not depend on path completion.
func distance_to(target: Vector3) -> float:
	var flat: Vector3 = target - _body.global_position
	flat.y = 0.0
	return flat.length()
