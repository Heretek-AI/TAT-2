extends "res://src/ai/statetree/bindings.gd"
## Guard observation binding for shadow mode (W9-P4 S1).
##
## WHAT THIS IS: the port's mapping from the authored StateTree nodes to state it
## already has. It reads the live guard and never writes to it. Where the source
## payload does not carry a node's parameter (`guard_behavior.json` carries NAMES
## only -- see `tree_model.gd`), the declaration says `parameter_blind: true`
## and the note says which port fact the answer came from. Nothing here claims
## that an authored number was recovered; the coverage table prints the count of
## parameter-blind instances so the reader can see the size of the inference.
##
## REACHABLE PATH THIS DRIVES (measured, see `p4-report.md`):
##   ST_Guard Root -> Standard States -> Reset Focus -> Return To Normal
##     -> Patrolling (LinkedAsset) -> ST_Patrol Root -> Patrol
## and inside ST_Patrol: Set Next Patrol Path Point -> (Has Broken Location? is
## false by construction) -> Reset Alertness -> Is Patrol Point A Patrol to
## Location -> Move To Point -> Say a Voice Line -> Rotate -> Delay
##     -> Complete Segment -> Set Next Patrol Path Point ...
##
## WHAT IT CANNOT DRIVE, AND SAYS SO:
##   * every smart-object task (no smart-object system in the port);
##   * every targeting-group / individual-knowledge / attitude task (no
##     knowledge subsystem; `Extract Target From Targeting Group` cannot answer
##     "which target");
##   * every EQS (`Run Env Query`), gameplay-ability, lockdown, revive and
##     combat-positioning task;
##   * every `OnEvent` transition: the port has **no** `StateTreeEvent.*`
##     emitter (0 hits in `game/src`), so no event-bearing branch can fire. The
##     trace records the required event and the shadow summary counts it.
##
## The two conditions that decide the patrol branch are answered from the port's
## own authored patrol record, not from a guess: `Patrol Point Is Of Type` from
## the state name ("Smart Object" vs "Patrol to Location", matching the one
## authored parameter in the dump plus the 673 authored points, all of which are
## `EPatrolPointType::PatrolToLocation`), and `Bool Compare` in "Rotate" from the
## point's authored `HasFacing`.

const TreeModel = preload("res://src/ai/statetree/tree_model.gd")
const BindingsBase = preload("res://src/ai/statetree/bindings.gd")

## Class-level declarations. `parameter_blind` means the authored node parameter
## is NOT in the payload, so the handler's behaviour is a port mapping.
const TASK_DECL: Dictionary = {
	"TATState Tree Task Setup Patrol": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "reads the same authored patrol record the FSM uses (level `patrol_paths`); Setup Patrol's own task params are not in the payload",
	},
	"TATState Tree Task Persist Patrol Data": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "the port persists patrol state in guard fields (wp_index/_patrol_wait_left); no authored parameter is carried",
	},
	"TATState Tree Task Set Alertness": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "observes the FSM's alertness; the authored EAlertnessLevel parameter is not in the payload, the target is inferred from the state name",
	},
	"Move To": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "completes when the FSM reaches the authored patrol point (1.0 m gate) or advances wp_index; the target binding is not in the payload",
	},
	"TATState Tree Task Rotate to Face": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "observes the authored patrol yaw the FSM already applies; the task's target binding is not in the payload",
	},
	"Delay Task": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "observes the FSM's authored WaitSeconds dwell; the task's Duration binding is not in the payload",
	},
	"Complete Patrol Segment": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "the FSM advances the authored path index itself; completion is observed, not commanded",
	},
	"Complete Broken Segment": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "the port has no broken-patrol-segment concept, so this branch is unreachable",
	},
	"Clear Focus": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "PORT GAP (vacuous): the port has no focus subsystem, so clearing focus completes immediately",
	},
	"Set Focus (Actor)": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP (vacuous): no focus subsystem; completes without turning the guard",
	},
	"Set Focus (Location)": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP (vacuous): no focus subsystem; completes without turning the guard",
	},
	"STT Set Focus": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP (vacuous): no focus subsystem",
	},
	"Request Voice Line": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP: the port's VO is tag-driven from the FSM, not from the tree; the task completes without playing the authored line",
	},
	"Request Conditional Voice Line": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP: as Request Voice Line; the tag parameter is not in the payload",
	},
	"Request Conditional Voice Line Copy": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP: as Request Voice Line",
	},
	"Repeatedly Trigger VO": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP: the delay/tag parameters are not in the payload; completes as a one-shot",
	},
	"Add Targeting Groups": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP (vacuous): the port keeps no targeting-group registry at the tree level; ReactionRoles covers only the combat role cap",
	},
	"Track Targeting Groups": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP (vacuous): no targeting-group registry",
	},
}

const COND_DECL: Dictionary = {
	"Is Carrying Major Loot": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "guards never carry major loot in the port; false by construction",
	},
	"STC Blackboard Actor Is Set": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "PORT GAP: the port has no StateTree blackboard, so no blackboard actor is set",
	},
	"Check Target Has Gameplay Tag": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "answered as 'the FSM is not NEUTRAL' (it has a target); the authored tag is not in the payload",
	},
	"Bool Compare": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "answered only where the owning state disambiguates it; every other instance is UNKNOWN",
	},
	"Patrol Point Is Of Type": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "answered from the owning state name; all 673 authored patrol points are PatrolToLocation, so the Smart Object branch is false",
	},
	"Object Is Valid": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "answered false only where the port has no such object (smart-object states); otherwise UNKNOWN",
	},
}

## Tasks whose completion is immediate and has no port effect.
const VACUOUS_TASKS: Array[String] = [
	"Complete Patrol Segment",
	"Complete Broken Segment",
	"Clear Focus",
	"Set Focus (Actor)",
	"Set Focus (Location)",
	"STT Set Focus",
	"Request Voice Line",
	"Request Conditional Voice Line",
	"Request Conditional Voice Line Copy",
	"Repeatedly Trigger VO",
	"Add Targeting Groups",
	"Track Targeting Groups",
]

var guard: Node = null
var trees: Dictionary = {}
var observed: Dictionary = {}
var events_matched: int = 0
var events_refused: int = 0
var unknown_conditions: Dictionary = {}
var task_instances: Dictionary = {}
var last_guard_position: Vector3 = Vector3.ZERO
var stationary_s: float = 0.0


func setup(p_guard: Node, p_trees: Dictionary) -> void:
	guard = p_guard
	trees = p_trees


func mutates() -> bool:
	return false


# ---------------------------------------------------------------------------
# Declaration / coverage
# ---------------------------------------------------------------------------


func declaration(kind: String, name: String) -> Dictionary:
	var table: Dictionary = TASK_DECL if kind == "task" else COND_DECL
	var row: Dictionary = table.get(name, {})
	if row.is_empty():
		return {
			"status": STATUS_UNSUPPORTED,
			"parameter_blind": false,
			"note": "no port counterpart",
			"kind": kind,
			"name": name,
		}
	return {
		"status": str(row.get("status", STATUS_UNSUPPORTED)),
		"parameter_blind": bool(row.get("parameter_blind", false)),
		"note": str(row.get("note", "")),
		"kind": kind,
		"name": name,
	}


## Narrow a class-level declaration to one authored instance. Everything not
## explicitly reachable is excluded, so the coverage table cannot claim a class
## is covered because one of its instances happens to be.
func covers(kind: String, name: String, tree_name: String, state_index: int) -> bool:
	var decl: Dictionary = declaration(kind, name)
	if str(decl.get("status", STATUS_UNSUPPORTED)) == STATUS_UNSUPPORTED:
		return false
	var tree: Dictionary = trees.get(tree_name, {})
	if tree.is_empty():
		return false
	var state: Dictionary = TreeModel.state(tree, state_index)
	var state_name: String = str(state.get("name", ""))
	var tasks: Array = state.get("tasks", [])
	if kind == "task":
		if name == "TATState Tree Task Setup Patrol" or name == "TATState Tree Task Persist Patrol Data" \
				or name == "Complete Patrol Segment" or name == "Complete Broken Segment":
			return tree_name == "ST_Patrol"
		if name == "Move To":
			return tree_name == "ST_Patrol" and state_name.begins_with("Move To")
		if name == "TATState Tree Task Rotate to Face":
			return tree_name == "ST_Patrol" and tasks.has("TATState Tree Task Rotate to Face")
		if name == "Delay Task":
			return tree_name == "ST_Patrol" and (state_name == "Delay" or state_name == "Failed")
		return true
	# Conditions.
	if name == "Bool Compare":
		if state_name.find("Broken Location") >= 0:
			return true
		if tasks.has("TATState Tree Task Rotate to Face"):
			return true
		return false
	if name == "Patrol Point Is Of Type":
		return tree_name == "ST_Patrol" and (state_name.find("Smart Object") >= 0 or state_name.find("Patrol to Location") >= 0)
	if name == "Object Is Valid":
		return tree_name == "ST_Patrol" and state_name.find("Smart Object") >= 0
	return true


# ---------------------------------------------------------------------------
# Observation (read-only)
# ---------------------------------------------------------------------------


## Take a read-only snapshot of the guard. Called once per shadow tick before
## `interpreter.tick`, so a task/condition always sees the same frame.
func observe(delta: float) -> void:
	observed = {}
	if guard == null or not is_instance_valid(guard):
		return
	var node: Node3D = guard as Node3D
	var pos: Vector3 = node.global_position
	if pos.distance_to(last_guard_position) < 0.005:
		stationary_s += delta
	else:
		stationary_s = 0.0
	last_guard_position = pos
	var points: Array = []
	if guard.get("patrol_points") is Array:
		points = guard.get("patrol_points")
	var wp: int = int(guard.get("wp_index"))
	var wait_left: float = 0.0
	if guard.has_method("patrol_wait_remaining"):
		wait_left = float(guard.call("patrol_wait_remaining"))
	var at_point: bool = wp >= 0 and wp < points.size() and pos.distance_to(points[wp] as Vector3) <= 1.0
	var has_facing: bool = false
	var facing_yaw: float = 0.0
	var facing: Array = []
	var yaws: Array = []
	if guard.get("patrol_facing") is Array:
		facing = guard.get("patrol_facing")
	if guard.get("patrol_yaws") is Array:
		yaws = guard.get("patrol_yaws")
	if wp >= 0 and wp < facing.size() and wp < yaws.size():
		has_facing = bool(facing[wp])
		facing_yaw = float(yaws[wp])
	var state_value: int = int(guard.get("state"))
	observed = {
		"pos": pos,
		"yaw": node.rotation.y,
		"state": state_value,
		"state_name": _alertness_name(state_value),
		"detection": float(guard.get("detection")),
		"health": float(guard.get("health")),
		"wp_index": wp,
		"wp_count": points.size(),
		"wait_left": wait_left,
		"at_point": at_point,
		"dist_to_point": pos.distance_to(points[wp] as Vector3) if wp >= 0 and wp < points.size() else -1.0,
		"has_facing": has_facing,
		"facing_yaw": facing_yaw,
		"stationary_s": stationary_s,
		"knocked_out": state_value == 5,
	}


static func _alertness_name(value: int) -> String:
	match value:
		0:
			return "Neutral"
		1:
			return "Suspicious"
		2:
			return "Alerted"
		3:
			return "Combat"
		4:
			return "Search"
		5:
			return "KnockedOut"
	return "Unknown"


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------


func condition_state(name: String, tree_name: String, state_index: int, _transition: Dictionary) -> int:
	if guard == null or not is_instance_valid(guard):
		return COND_UNKNOWN
	var tree: Dictionary = trees.get(tree_name, {})
	var state: Dictionary = TreeModel.state(tree, state_index)
	var state_name: String = str(state.get("name", ""))
	var tasks: Array = state.get("tasks", [])
	match name:
		"Is Carrying Major Loot":
			return COND_FALSE
		"STC Blackboard Actor Is Set":
			return COND_FALSE
		"Check Target Has Gameplay Tag":
			return COND_TRUE if int(observed.get("state", 0)) != 0 and not bool(observed.get("knocked_out", false)) else COND_FALSE
		"Bool Compare":
			if state_name.find("Broken Location") >= 0:
				return COND_FALSE
			if tasks.has("TATState Tree Task Rotate to Face"):
				return COND_TRUE if bool(observed.get("has_facing", false)) else COND_FALSE
			return COND_UNKNOWN
		"Patrol Point Is Of Type":
			if state_name.find("Smart Object") >= 0:
				return COND_FALSE
			if state_name.find("Patrol to Location") >= 0:
				return COND_TRUE
			return COND_UNKNOWN
		"Object Is Valid":
			if state_name.find("Smart Object") >= 0:
				return COND_FALSE
			return COND_UNKNOWN
	# Everything else needs a parameter or a subsystem the payload/port lacks.
	unknown_conditions[name] = int(unknown_conditions.get(name, 0)) + 1
	return COND_UNKNOWN


# ---------------------------------------------------------------------------
# Tasks
# ---------------------------------------------------------------------------


func task_enter(name: String, tree_name: String, state_index: int) -> Dictionary:
	if not covers("task", name, tree_name, state_index):
		return {}
	task_instances[name] = int(task_instances.get(name, 0)) + 1
	var instance: Dictionary = {
		"task": name,
		"tree": tree_name,
		"state": state_index,
		"entered_t": 0.0,
		"elapsed": 0.0,
		"wp_at_enter": int(observed.get("wp_index", -1)),
		"wait_at_enter": float(observed.get("wait_left", 0.0)),
		"status": RUNNING,
	}
	if VACUOUS_TASKS.has(name):
		instance["status"] = SUCCEEDED
	elif name == "TATState Tree Task Setup Patrol":
		instance["status"] = RUNNING
	elif name == "TATState Tree Task Persist Patrol Data":
		instance["status"] = SUCCEEDED
	return instance


func task_tick(instance: Dictionary, delta: float) -> int:
	instance["elapsed"] = float(instance.get("elapsed", 0.0)) + delta
	var name: String = str(instance.get("task", ""))
	match name:
		"TATState Tree Task Setup Patrol":
			if int(observed.get("wp_count", 0)) <= 0:
				return FAILED
			return SUCCEEDED
		"TATState Tree Task Set Alertness":
			return _tick_set_alertness(instance)
		"Move To":
			if int(observed.get("wp_index", -1)) != int(instance.get("wp_at_enter", -1)):
				return SUCCEEDED
			if float(observed.get("dist_to_point", -1.0)) >= 0.0 and float(observed.get("dist_to_point", 1e9)) <= 1.0:
				return SUCCEEDED
			return RUNNING
		"TATState Tree Task Rotate to Face":
			if not bool(observed.get("has_facing", false)):
				return SUCCEEDED
			if _yaw_error() <= 0.10:
				return SUCCEEDED
			# The FSM's yaw lerp is asymptotic; a hard cap keeps the shadow from
			# stalling on an angle that never quite reaches zero.
			if float(instance.get("elapsed", 0.0)) >= 3.0:
				return SUCCEEDED
			return RUNNING
		"Delay Task":
			if int(observed.get("wp_index", -1)) != int(instance.get("wp_at_enter", -1)):
				return SUCCEEDED
			if float(instance.get("wait_at_enter", 0.0)) <= 0.0:
				return SUCCEEDED
			if float(observed.get("wait_left", 0.0)) <= 0.0:
				return SUCCEEDED
			return RUNNING
	return SUCCEEDED


## `Set Alertness` has no authored level in the payload. The target comes from
## the owning state name: "Reset Alertness" / "Set Alertness" (the patrol entry)
## mean Neutral, "Raise alertness (so we run back)" means at least Suspicious.
## Declared parameter_blind in TASK_DECL.
func _tick_set_alertness(instance: Dictionary) -> int:
	var tree: Dictionary = trees.get(str(instance.get("tree", "")), {})
	var state_name: String = TreeModel.state_name(tree, int(instance.get("state", -1)))
	var current: String = str(observed.get("state_name", "Unknown"))
	if state_name.find("Raise") >= 0:
		return SUCCEEDED if current != "Neutral" else RUNNING
	return SUCCEEDED if current == "Neutral" else RUNNING


func _yaw_error() -> float:
	if guard == null or not is_instance_valid(guard):
		return 0.0
	var node: Node3D = guard as Node3D
	if node == null:
		return 0.0
	var guard_yaw: float = node.rotation.y
	# Same transform the FSM applies (`_apply_patrol_yaw`): UE yaw 0 faces +X and
	# positive turns toward +Y; Godot rotation.y 0 faces -Z.
	var target: float = deg_to_rad(-(float(observed.get("facing_yaw", 0.0)) + 90.0))
	return absf(angle_difference(guard_yaw, target))


func task_exit(_instance: Dictionary) -> void:
	pass


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------


## The port has no `StateTreeEvent.*` emitter. Returning FALSE (not UNKNOWN)
## keeps the meaning precise: the authored event never happens in this port, so
## the branch is unreachable -- it is not a data gap in the payload.
func event_matches(transition: Dictionary, event: Dictionary) -> int:
	if str(transition.get("required_event", "")) == str(event.get("tag", "")):
		events_matched += 1
		return COND_TRUE
	events_refused += 1
	return COND_FALSE


func after_tick(_interpreter: RefCounted) -> void:
	pass
