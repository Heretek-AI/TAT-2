extends "res://src/ai/statetree/bindings.gd"
## Guard observation binding for shadow mode (W10-B2.1).
##
## WHAT THIS IS: the port's mapping from the authored StateTree NODES to state it
## already has. It reads the live guard and never writes to it. Payload /2
## carries each node's authored `parameters` and `bound` map; B2.1 consumes them
## through `resolve()` (base class), so a bound target is authoritative and
## `UNKNOWN` never falls back to the template default.
##
## REACHABLE PATH THIS DRIVES (measured, see `p4-report.md`):
##   ST_Guard Root -> Standard States -> Reset Focus -> Return To Normal
##     -> Patrolling (LinkedAsset) -> ST_Patrol Root -> Patrol
## and inside ST_Patrol: Set Next Patrol Path Point -> (Has Broken Location? is
## false by construction) -> Reset Alertness -> Is Patrol Point A Patrol to
## Location -> Move To Point -> Say a Voice Line -> Rotate -> Delay
##     -> Complete Segment -> Set Next Patrol Path Point ...
##
## AUTHORED RECORDS THIS READS (all measured from the shipped level data,
## `patrol_paths[].points[]`, not inferred):
##   * `WaitSeconds`, `WaitDeviation`, `HasFacing`, `Facing`,
##     `EPatrolPointType` and the point position for the guard's current
##     waypoint; `CurrentPatrolWorldLocation` is that point's position. These are
##     exactly the six `AUTHORED_RECORD_PATHS` in `bindings.gd`.
##   * The shipped 673 authored points are 668 `PatrolToLocation` and 5
##     `SmartObjectInteraction`, so the patrol point type is NOT assumed.
##
## WHAT THIS CANNOT DRIVE, AND SAYS SO:
##   * every smart-object task (no smart-object system in the port), including
##     `PatrolPointData.SmartObjectComponent`, which stays UNKNOWN;
##   * every targeting-group / individual-knowledge / attitude task (no
##     knowledge subsystem; `Extract Target From Targeting Group` cannot answer
##     "which target");
##   * every EQS (`Run Env Query`), gameplay-ability, lockdown, revive and
##     combat-positioning task;
##   * every `Setup Patrol` output (`PatrolData`, `PatrolWorldLocation`,
##     `PatrolWasInterrupted`, `PatrolBrokenLocation` are `RefAccessIndex` output
##     slots in the payload; the port does not invent their values);
##   * the `GlobalParameterData` bags (`ResetAlertness`, `Target`,
##     `ShouldReactToIncorrectObjects`, ...): schema only, always UNKNOWN;
##   * 16 of the 17 authored `StateTreeEvent.*` tags: the port has one live
##     emitter (Phase 3B.1: `StateTreeEvent.StimChange` from `guard_ai._hear`,
##     see `events.gd`). The remaining tags have no event bus, so the branches
##     that listen for them stay unreachable. The interpreter's event gates are
##     exercised with synthetic events in suite 110; `event_matches` is the path
##     the one live tag goes through.
##
## The two conditions that decide the patrol branch are now answered from the
## authored values first and fall back to the declared mapping only when the
## value is UNKNOWN: `Patrol Point Is Of Type` compares the authored
## `PatrolPathType` with `PatrolPointData.PatrolPointType`; `Bool Compare`
## compares `bLeft` (bound `PatrolPointData.HasFacing` / `ResetAlertness` / ...)
## with `bRight`.

const TreeModel = preload("res://src/ai/statetree/tree_model.gd")
const BindingsBase = preload("res://src/ai/statetree/bindings.gd")

## Class-level declarations. `parameter_blind` is kept for compatibility with
## the W9 declaration table; the coverage table now derives per-instance
## `param_source`/`parity` from the node itself, so a class-level flag can no
## longer hide an authored parameter that a handler reads.
const GUARD_TASK_DECL: Dictionary = {
	"TATState Tree Task Setup Patrol": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "reads the same authored patrol record the FSM uses (level `patrol_paths`); its four outputs are RefAccessIndex slots, not values",
	},
	"TATState Tree Task Persist Patrol Data": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "the port persists patrol state in guard fields (wp_index/_patrol_wait_left); the node has no value parameter",
	},
	"TATState Tree Task Set Alertness": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "compares the authored EAlertnessLevel with the FSM's alertness (observation, not command)",
	},
	"Move To": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "completes when the FSM reaches the authored patrol point (1.0 m gate) or advances wp_index; Destination resolves from the authored patrol record",
	},
	"TATState Tree Task Rotate to Face": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "observes the authored patrol yaw the FSM already applies; TargetRotation resolves from PatrolPointData.Facing",
	},
	"Delay Task": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "bound Duration observes the FSM's authored WaitSeconds dwell; a literal Duration is driven by the generic base handler",
	},
	"Complete Patrol Segment": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "the FSM advances the authored path index itself; completion is observed, not commanded",
	},
	"Complete Broken Segment": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "the port has no broken-patrol-segment concept, so this branch is unreachable",
	},
	"Clear Focus": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "PORT GAP (vacuous): the port has no focus subsystem, so clearing focus completes immediately",
	},
	"Set Focus (Actor)": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP (vacuous): no focus subsystem; the Target binding is a GlobalParameterData slot with no serialized value",
	},
	"Set Focus (Location)": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP (vacuous): no focus subsystem; the Target binding is a state parameter with no serialized value",
	},
	"STT Set Focus": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "PORT GAP (vacuous): no focus subsystem",
	},
	"Request Voice Line": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "PORT GAP: the port's VO is tag-driven from the FSM, not from the tree; the authored VOLineTag is carried but not played",
	},
	"Request Conditional Voice Line": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "PORT GAP: as Request Voice Line; the tag parameter is authored but not played",
	},
	"Request Conditional Voice Line Copy": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "PORT GAP: as Request Voice Line",
	},
	"Repeatedly Trigger VO": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "PORT GAP: the tag/delay parameters are authored; the port completes it as a one-shot",
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

const GUARD_COND_DECL: Dictionary = {
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
		"note": "answered as 'the FSM is not NEUTRAL' (it has a target); the authored tag is carried but the port has no knowledge subsystem",
	},
	"Bool Compare": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "compares the two resolved operands when both carry values; otherwise the declared state-name mapping answers or UNKNOWN",
	},
	"Patrol Point Is Of Type": {
		"status": "mapped-to-port", "parameter_blind": false,
		"note": "compares the authored PatrolPathType with the authored patrol record's point type; only an UNKNOWN record falls back to the state-name mapping",
	},
	"Object Is Valid": {
		"status": "mapped-to-port", "parameter_blind": true,
		"note": "false where the port has no smart object; otherwise UNKNOWN (the bound object is not serialized)",
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
var _slot_cache: Dictionary = {}


func setup(p_guard: Node, p_trees: Dictionary) -> void:
	guard = p_guard
	trees = p_trees
	_slot_cache.clear()


func mutates() -> bool:
	return false


# ---------------------------------------------------------------------------
# Declaration / coverage
# ---------------------------------------------------------------------------


func declaration(kind: String, name: String) -> Dictionary:
	var table: Dictionary = GUARD_TASK_DECL if kind == "task" else GUARD_COND_DECL
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


## Narrow a class-level declaration to one authored INSTANCE. Everything not
## explicitly reachable is excluded, so the coverage table cannot claim a class
## is covered because one of its instances happens to be.
func covers(kind: String, name: String, tree_name: String, state_index: int, node: Dictionary = {}) -> bool:
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
			# A bound Duration is driven only where the port supplies it from the
			# authored patrol record (ST_Patrol's WaitSeconds); a literal Duration
			# is driven by the generic base handler in any tree.
			var source: String = BindingsBase.param_source(node) if not node.is_empty() else "literal"
			if source == "bound-authored-record":
				return tree_name == "ST_Patrol"
			if source == "bound-port-fallback" or source == "bound-unknown" or source == "ref-access" or source == "inherited":
				return false
			return true
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
	var waits: Array = []
	if guard.get("patrol_waits") is Array:
		waits = guard.get("patrol_waits")
	var types: Array = []
	if guard.get("patrol_types") is Array:
		types = guard.get("patrol_types")
	var deviations: Array = []
	if guard.get("patrol_wait_deviations") is Array:
		deviations = guard.get("patrol_wait_deviations")
	var wp: int = int(guard.get("wp_index"))
	var wait_left: float = 0.0
	if guard.has_method("patrol_wait_remaining"):
		wait_left = float(guard.call("patrol_wait_remaining"))
	# The FSM's arrival gate is strictly `< 1.0` m (`_patrol_service_waypoint`);
	# the binding must not accept a boundary the FSM has not accepted.
	var at_point: bool = wp >= 0 and wp < points.size() and pos.distance_to(points[wp] as Vector3) < 1.0
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
	# The mission controller fills waits/yaws/facing/types together from the
	# authored APatrolPath; the synthetic 6x6 m fallback sets patrol_points only.
	# So an equal-length waits array is the measured discriminator for "this
	# guard's record is authored", with no new runtime flag.
	var authored_record: bool = not waits.is_empty() and waits.size() == points.size()
	var wait_s: float = 0.0
	if authored_record and wp >= 0 and wp < waits.size():
		wait_s = maxf(0.0, float(waits[wp]))
	var point_type: String = "UNKNOWN"
	if authored_record and wp >= 0 and wp < types.size() and str(types[wp]) != "":
		point_type = str(types[wp])
	var wait_deviation_s: float = 0.0
	if authored_record and wp >= 0 and wp < deviations.size():
		wait_deviation_s = maxf(0.0, float(deviations[wp]))
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
		"wait_s": wait_s,
		"wait_deviation_s": wait_deviation_s,
		"patrol_authored": authored_record,
		"point_type": point_type,
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
# Frame bags (authored patrol record -> StateParameterData)
# ---------------------------------------------------------------------------


## Which `StateParameterData` slots the tree's nodes bind on `state_index`. The
## slot index comes from the payload (`source_index`), never from a guess; for
## ST_Patrol state 3 the 13 bindings all name slot 3.
func _state_parameter_slots(tree_name: String, state_index: int) -> Array:
	var cache_key: String = "%s|%d" % [tree_name, state_index]
	if _slot_cache.has(cache_key):
		return _slot_cache[cache_key]
	var slots: Dictionary = {}
	var tree: Dictionary = trees.get(tree_name, {})
	for node: Dictionary in TreeModel.all_nodes(tree):
		for target: Variant in (node.get("bound", {}) as Dictionary).keys():
			var binding: Dictionary = (node.get("bound", {}) as Dictionary)[target]
			if str(binding.get("source_array", "")) != "StateParameterData":
				continue
			var owner_raw: Variant = binding.get("source_state_index", null)
			if owner_raw == null or int(owner_raw) != state_index:
				continue
			var index_raw: Variant = binding.get("source_index", null)
			if index_raw != null:
				slots[str(int(index_raw))] = true
	var out: Array = slots.keys()
	out.sort()
	_slot_cache[cache_key] = out
	return out


## Fill ST_Patrol's `Patrol` state bag from the authored patrol record. The
## fields are exactly the six `AUTHORED_RECORD_PATHS`; `SmartObjectComponent`
## stays UNKNOWN (no smart-object system), and the four `Setup Patrol` outputs
## are not supplied because the payload carries them as `RefAccessIndex` slots.
func state_bags(tree_name: String, state_index: int) -> Dictionary:
	if observed.is_empty():
		return {}
	if tree_name != "ST_Patrol":
		return {}
	var tree: Dictionary = trees.get(tree_name, {})
	if TreeModel.state_name(tree, state_index) != "Patrol":
		return {}
	var wp: int = int(observed.get("wp_index", -1))
	var points: Array = []
	if guard != null and guard.get("patrol_points") is Array:
		points = guard.get("patrol_points")
	if wp < 0 or wp >= points.size():
		return {}
	var authored: bool = bool(observed.get("patrol_authored", false))
	var position_source: String = SOURCE_AUTHORED_RECORD if authored else SOURCE_PORT_FALLBACK
	var point: Dictionary = {
		"WaitSeconds": _bag_leaf(float(observed.get("wait_s", 0.0)), authored),
		"WaitDeviation": _bag_leaf(float(observed.get("wait_deviation_s", 0.0)), authored),
		"HasFacing": _bag_leaf(bool(observed.get("has_facing", false)), authored),
		"Facing": _bag_leaf(float(observed.get("facing_yaw", 0.0)), authored),
		"PatrolPointType": _bag_leaf(str(observed.get("point_type", "UNKNOWN")), authored),
		"SmartObjectComponent": {"value": VALUE_UNKNOWN, "source": SOURCE_BOUND_UNKNOWN},
	}
	var slot_value: Dictionary = {
		"PatrolPointData": point,
		"CurrentPatrolWorldLocation": {"value": points[wp] as Vector3, "source": position_source},
		# Setup Patrol outputs: the payload carries them as RefAccessIndex slots.
		"PatrolData": {"value": VALUE_UNKNOWN, "source": SOURCE_REF_ACCESS},
		"PatrolWorldLocation": {"value": VALUE_UNKNOWN, "source": SOURCE_REF_ACCESS},
		"PatrolWasInterrupted": {"value": VALUE_UNKNOWN, "source": SOURCE_REF_ACCESS},
		"PatrolBrokenLocation": {"value": VALUE_UNKNOWN, "source": SOURCE_REF_ACCESS},
	}
	var by_slot: Dictionary = {}
	for slot: Variant in _state_parameter_slots(tree_name, state_index):
		by_slot[str(slot)] = slot_value
	return {"StateParameterData": by_slot}


func _bag_leaf(value: Variant, authored: bool) -> Dictionary:
	if not authored:
		return {"value": VALUE_UNKNOWN, "source": SOURCE_PORT_FALLBACK}
	return {"value": value, "source": SOURCE_AUTHORED_RECORD}


# ---------------------------------------------------------------------------
# Conditions
# ---------------------------------------------------------------------------


func condition_state(node: Dictionary, ctx: Dictionary) -> int:
	if guard == null or not is_instance_valid(guard):
		return COND_UNKNOWN
	var name: String = str(node.get("name", ""))
	var tree_name: String = str(ctx.get("tree", ""))
	var state_index: int = int(ctx.get("state", -1))
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
			var left: Dictionary = resolve(node, "bLeft", ctx)
			var right: Dictionary = resolve(node, "bRight", ctx)
			if (left["value"] is bool) and (right["value"] is bool) \
					and str(left["source"]) != SOURCE_BOUND_UNKNOWN and str(left["source"]) != SOURCE_REF_ACCESS:
				return COND_TRUE if bool(left["value"]) == bool(right["value"]) else COND_FALSE
			# Declared mapping, used only when an operand is UNKNOWN.
			if state_name.find("Broken Location") >= 0:
				return COND_FALSE
			if tasks.has("TATState Tree Task Rotate to Face"):
				return COND_TRUE if bool(observed.get("has_facing", false)) else COND_FALSE
			return COND_UNKNOWN
		"Patrol Point Is Of Type":
			var expected: Dictionary = resolve(node, "PatrolPathType", ctx)
			var actual: Dictionary = resolve(node, "TargetPatrolPathType", ctx)
			if str(expected["source"]) == SOURCE_LITERAL and str(actual["value"]) != VALUE_UNKNOWN \
					and (str(actual["source"]) == SOURCE_AUTHORED_RECORD or str(actual["source"]) == SOURCE_PORT_FALLBACK):
				return COND_TRUE if str(expected["value"]) == str(actual["value"]) else COND_FALSE
			# Declared mapping, used only when the record carries no type.
			if state_name.find("Smart Object") >= 0:
				return COND_FALSE
			if state_name.find("Patrol to Location") >= 0:
				return COND_TRUE
			return COND_UNKNOWN
		"Object Is Valid":
			var object_value: Dictionary = resolve(node, "Object", ctx)
			if str(object_value["value"]) != VALUE_UNKNOWN \
					and str(object_value["source"]) == SOURCE_AUTHORED_RECORD:
				return COND_TRUE
			if state_name.find("Smart Object") >= 0:
				return COND_FALSE
			return COND_UNKNOWN
	# Everything else needs a parameter or a subsystem the payload/port lacks.
	unknown_conditions[name] = int(unknown_conditions.get(name, 0)) + 1
	return COND_UNKNOWN


# ---------------------------------------------------------------------------
# Tasks
# ---------------------------------------------------------------------------


func task_enter(node: Dictionary, ctx: Dictionary) -> Dictionary:
	var name: String = str(node.get("name", ""))
	var tree_name: String = str(ctx.get("tree", ""))
	var state_index: int = int(ctx.get("state", -1))
	if not covers("task", name, tree_name, state_index, node):
		return {}
	# A literal `Delay Task` is fully drivable by the generic base handler.
	if name == "Delay Task" and BindingsBase.param_source(node) != "bound-authored-record":
		return super.task_enter(node, ctx)
	task_instances[name] = int(task_instances.get(name, 0)) + 1
	var instance: Dictionary = {
		"task": name,
		"node": node,
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
	if instance.has("duration_s"):
		return super.task_tick(instance, delta)
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
			if float(observed.get("dist_to_point", -1.0)) >= 0.0 and float(observed.get("dist_to_point", 1e9)) < 1.0:
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
			# Bound Duration: the FSM's own dwell IS the authored WaitSeconds.
			if int(observed.get("wp_index", -1)) != int(instance.get("wp_at_enter", -1)):
				return SUCCEEDED
			if float(instance.get("wait_at_enter", 0.0)) <= 0.0:
				return SUCCEEDED
			if float(observed.get("wait_left", 0.0)) <= 0.0:
				return SUCCEEDED
			return RUNNING
	return SUCCEEDED


## `Set Alertness`: compare the AUTHORED `EAlertnessLevel` with the FSM's current
## alertness. The state-name inference survives only as the fallback for a node
## whose level is missing (none in the payload: 20/20 carry it).
func _tick_set_alertness(instance: Dictionary) -> int:
	var node: Dictionary = instance.get("node", {})
	var level: Dictionary = resolve(node, "AlertnessLevel", {})
	var current: String = str(observed.get("state_name", "Unknown"))
	if str(level["source"]) == SOURCE_LITERAL and str(level["value"]) != VALUE_UNKNOWN:
		var want: String = str(level["value"])
		var split_at: int = want.find("::")
		if split_at >= 0:
			want = want.substr(split_at + 2)
		return SUCCEEDED if current == want else RUNNING
	var tree: Dictionary = trees.get(str(instance.get("tree", "")), {})
	var state_name: String = TreeModel.state_name(tree, int(instance.get("state", -1)))
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


## Match one authored `OnEvent` gate against a live event. Phase 3B.1 wires
## exactly one tag (`StateTreeEvent.StimChange`, from `guard_ai._hear`, see
## `events.gd`); every other authored tag still never arrives, so its branch is
## unreachable -- not a data gap in the payload. Returning FALSE (not UNKNOWN)
## keeps that meaning precise. This method is what the one live tag goes
## through; suite 110 drives the same gates with synthetic events.
func event_matches(transition: Dictionary, event: Dictionary) -> int:
	if str(transition.get("required_event", "")) == str(event.get("tag", "")):
		events_matched += 1
		return COND_TRUE
	events_refused += 1
	return COND_FALSE


func after_tick(_interpreter: RefCounted) -> void:
	pass
