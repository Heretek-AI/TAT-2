extends RefCounted
## EXPERIMENTAL StateTree writer spike (Phase 3B.1). NOT the default, NOT a
## cutover.
##
## `TAT2_STATETREE_WRITER=on|1|true|yes` (default `off`) is the explicit
## experimental gate. It is only consulted while `TAT2_STATETREE=patrol`:
## `shadow_runner.attach()` refuses `patrol` outright when the writer is off
## (because `guard_bindings.mutates()` is false and nothing reads the
## interpreter), so `patrol` alone can never certify a no-op again. With the
## writer on, `guard_ai._physics_process()` hands movement to `apply_step(dt)`
## instead of `_move_ai(dt, player)`.
##
## WHAT `apply_step` READS AND WRITES
##   * reads the interpreter's selected leaf (`current_tree()`,
##     `current_state_name()`) and the read-only observation snapshot
##     (`bindings.observed`);
##   * on `ST_Patrol: Move To Point` / `Move To Broken Point`, walks toward the
##     authored waypoint (`guard.patrol_points[wp_index]`) at the guard's own
##     `patrol_speed`, and on arrival (the binding's 1.0 m gate) advances the
##     authored patrol index -- the "Complete Segment / Set Next Patrol Path
##     Point" work the FSM did in `_patrol_service_waypoint`;
##   * on every other leaf it holds still.
## Compared with the FSM it applies no authored dwell (`WaitSeconds`) and no
## authored facing yaw, and it starts moving only once the interpreter has
## selected `ST_Patrol`, so the A/B in `test_w9p4_shadow.gd` measures a bounded,
## different trajectory.
##
## WHAT IT DOES NOT DO (and must never grow here without its own producer data)
##   * no smart-object claim (`Use Smart Object`, `STT Distraction Smart
##     Objects`, `Extract Distraction Data`, `STT Use Smart Object with Target
##     Slot Handle` are all still absent -- see `guard_bindings.gd`);
##   * no EQS / fusion / targeting-group / knowledge subsystem;
##   * no focus, VO or alarm path;
##   * non-NEUTRAL alertness holds and is counted (`blocked_non_neutral`),
##     because the spike implements the NEUTRAL patrol branch only.
##
## The step is bounded by construction: one `move_and_slide()` per call with a
## planar speed of `patrol_speed` and no teleport, so
## `max_planar_step_m <= patrol_speed * delta` plus engine slack.

const WRITER_ENV: String = "TAT2_STATETREE_WRITER"
const WRITER_ON: String = "on"
const WRITER_OFF: String = "off"

## Arrival gate for the spike's own segment completion. It matches the binding's
## 1.0 m `at_point` gate so `Move To` and the writer agree on when the point is
## reached; the difference from the FSM is that the spike applies no authored
## dwell and no authored facing yaw.
const ARRIVE_M: float = 1.0
## Leaves whose authored work is "walk to the current patrol point".
const MOVE_STATES: Array[String] = ["Move To Point", "Move To Broken Point"]
const PATROL_TREE: String = "ST_Patrol"
## Guard `Alertness.NEUTRAL` is 0; anything else holds.
const ALERTNESS_NEUTRAL: int = 0

static var _enabled: String = ""


static func enabled() -> bool:
	if _enabled == "":
		_enabled = _parse(OS.get_environment(WRITER_ENV))
	return _enabled == WRITER_ON


## Fail closed: anything that is not an explicit on value is off, and an unknown
## value says so once instead of silently opening the writer.
static func _parse(raw: String) -> String:
	var value: String = raw.strip_edges().to_lower()
	if value in ["on", "1", "true", "yes"]:
		return WRITER_ON
	if value == "" or value in ["off", "0", "false", "no"]:
		return WRITER_OFF
	push_warning("TAT2_STATETREE_WRITER='%s' is not on|off; using off" % raw)
	return WRITER_OFF


## Test-only override; the env var stays the shipping switch.
static func set_for_test(value: String) -> void:
	_enabled = value.strip_edges().to_lower()
	if _enabled == "":
		_enabled = _parse(OS.get_environment(WRITER_ENV))


static func reset_for_test() -> void:
	_enabled = ""


var guard: Node = null
var runner: RefCounted = null
var active: bool = false

var steps: int = 0
var moves: int = 0
var advances: int = 0
var holds: int = 0
var blocked_non_neutral: int = 0
var path_m: float = 0.0
var max_planar_step_m: float = 0.0
var last_command: Dictionary = {}


func setup(p_guard: Node, p_runner: RefCounted) -> void:
	guard = p_guard
	runner = p_runner
	active = p_guard != null and p_runner != null and bool(p_runner.get("started"))


## One frame of interpreter-driven movement. Returns the command it applied:
##   {"action": "move", "tree", "state", "wp", "target", "moved"}
##   {"action": "advance", "tree", "state", "wp"}
##   {"action": "hold", "reason", "tree", "state"}
##   {"action": "noop", "reason"}
func apply_step(delta: float) -> Dictionary:
	steps += 1
	if not active or guard == null or not is_instance_valid(guard):
		last_command = {"action": "noop", "reason": "no active guard"}
		return last_command
	var body: CharacterBody3D = guard as CharacterBody3D
	if body == null:
		last_command = {"action": "noop", "reason": "guard is not a CharacterBody3D"}
		return last_command
	var interp: RefCounted = runner.get("interpreter") if runner != null else null
	if interp == null:
		last_command = {"action": "noop", "reason": "no interpreter"}
		return last_command
	var tree: String = str(interp.current_tree())
	var state_name: String = str(interp.current_state_name())
	# The spike owns the NEUTRAL patrol branch only. Holding on any other
	# alertness is the honest failure mode: no combat/search movement is faked.
	if int(guard.get("state")) != ALERTNESS_NEUTRAL:
		blocked_non_neutral += 1
		_stop(body, delta)
		holds += 1
		last_command = {"action": "hold", "reason": "non-neutral alertness", "tree": tree, "state": state_name}
		return last_command
	var observed: Dictionary = {}
	var bindings_ref: RefCounted = runner.get("bindings") as RefCounted
	if bindings_ref != null:
		var raw_observed: Variant = bindings_ref.get("observed")
		if raw_observed is Dictionary:
			observed = raw_observed
	var wp: int = int(observed.get("wp_index", -1))
	var points: Array = []
	if guard.get("patrol_points") is Array:
		points = guard.get("patrol_points")
	if tree != PATROL_TREE or not MOVE_STATES.has(state_name) or wp < 0 or wp >= points.size():
		holds += 1
		_stop(body, delta)
		last_command = {"action": "hold", "tree": tree, "state": state_name, "wp": wp}
		return last_command
	var target: Vector3 = points[wp]
	var to_target: Vector3 = Vector3(target.x - body.global_position.x, 0.0, target.z - body.global_position.z)
	if to_target.length() <= ARRIVE_M:
		# The authored "Complete Segment -> Set Next Patrol Path Point" work the
		# spike replaces: the FSM's `_patrol_service_waypoint` does not run while
		# the writer holds movement authority.
		if guard.has_method("_advance_patrol_index"):
			guard.call("_advance_patrol_index")
		advances += 1
		_stop(body, delta)
		last_command = {"action": "advance", "tree": tree, "state": state_name, "wp": wp}
		return last_command
	var dir: Vector3 = to_target.normalized()
	var speed: float = maxf(0.0, float(guard.get("patrol_speed")))
	if body.is_on_floor():
		body.velocity.y = 0.0
	else:
		body.velocity.y -= 9.8 * delta
	body.velocity = Vector3(dir.x * speed, body.velocity.y, dir.z * speed)
	body.look_at(body.global_position + dir, Vector3.UP)
	var before: Vector3 = body.global_position
	body.move_and_slide()
	var moved: Vector3 = body.global_position - before
	var planar: float = Vector2(moved.x, moved.z).length()
	path_m += planar
	max_planar_step_m = maxf(max_planar_step_m, planar)
	moves += 1
	last_command = {
		"action": "move", "tree": tree, "state": state_name, "wp": wp,
		"target": target, "moved": planar,
	}
	return last_command


func _stop(body: CharacterBody3D, delta: float) -> void:
	body.velocity.x = 0.0
	body.velocity.z = 0.0
	# Keep floor contact like `_move_ai` does; the writer owns the whole step, so
	# it also owns gravity.
	if not body.is_on_floor():
		body.velocity.y -= 9.8 * delta
	body.move_and_slide()


## Flat summary for tests/probes.
func summary() -> Dictionary:
	return {
		"enabled": enabled(),
		"active": active,
		"steps": steps,
		"moves": moves,
		"advances": advances,
		"holds": holds,
		"blocked_non_neutral": blocked_non_neutral,
		"path_m": path_m,
		"max_planar_step_m": max_planar_step_m,
		"last_command": last_command.duplicate(true),
	}
