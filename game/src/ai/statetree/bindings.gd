extends RefCounted
## Gameplay-agnostic binding surface for the StateTree interpreter (W10-B2.1).
##
## The interpreter knows states, transitions and NODES; everything that needs a
## game (the player, perception, an animation, a blackboard) is supplied here by
## a subclass. This file is the default: every condition is UNKNOWN and every
## task is UNSET, except the generic `Delay Task` driver below, which needs no
## game state.
##
## EVIDENCE CLASSES (the coverage table is built from `declaration()`):
##   * IMPLEMENTED     the authored semantics are driven from fields the payload
##                     actually carries (e.g. a transition's trigger/priority, a
##                     literal `Delay Task` duration);
##   * MAPPED          the port performs the authored effect through a different
##                     authored data source; the interpreter observes it instead
##                     of executing it;
##   * UNSUPPORTED     no port counterpart exists.
##
## A binding MUST NOT mutate game state during shadow mode. Cutover bindings may
## act; they are a different subclass and are declared `mutates() == true`.

const STATUS_IMPLEMENTED: String = "implemented"
const STATUS_MAPPED: String = "mapped-to-port"
const STATUS_UNSUPPORTED: String = "unsupported"

## EStateTreeRunStatus mirror. UNSET means "this task cannot be driven".
const RUNNING: int = 0
const RUNNING_LATENT: int = 1
const SUCCEEDED: int = 2
const FAILED: int = 3
const UNSET: int = 4

## Tri-state condition result.
const COND_UNKNOWN: int = -1
const COND_FALSE: int = 0
const COND_TRUE: int = 1

## Sentinel for a value the payload/port cannot supply. Distinct from a JSON
## `false`/`0`: `resolve()` returns this instead of the template default.
const VALUE_UNKNOWN: String = "UNKNOWN"

## `resolve()` sources, from most to least authoritative:
##   bound-authored-record  a `bound` target supplied from an authored runtime
##                          record (the patrol point);
##   bound-port-fallback    a `bound` target the port supplies from a synthetic
##                          fallback record (the 6x6 m patrol square);
##   bound-unknown          a `bound` target with no value anywhere;
##   context                a `bound` ContextData slot (the guard, the actor);
##   literal                an authored `parameters` value, no binding;
##   ref-access             a `{"RefAccessIndex": ...}` output slot, not a value;
##   unset                  neither bound nor present.
const SOURCE_AUTHORED_RECORD: String = "bound-authored-record"
const SOURCE_PORT_FALLBACK: String = "bound-port-fallback"
const SOURCE_BOUND_UNKNOWN: String = "bound-unknown"
const SOURCE_CONTEXT: String = "context"
const SOURCE_LITERAL: String = "literal"
const SOURCE_REF_ACCESS: String = "ref-access"
const SOURCE_UNSET: String = "unset"

## The authored runtime records the port can supply a bound value from. Measured
## against the shipped level data (`patrol_paths[].points[]`): wait, wait
## deviation, facing flag, yaw, patrol point type and the point position are
## authored; `SmartObjectComponent` is not (no smart-object system), so it stays
## UNKNOWN even though its path root is `PatrolPointData`.
const AUTHORED_RECORD_PATHS: Array = [
	["PatrolPointData", "WaitSeconds"],
	["PatrolPointData", "WaitDeviation"],
	["PatrolPointData", "HasFacing"],
	["PatrolPointData", "Facing"],
	["PatrolPointData", "PatrolPointType"],
	["CurrentPatrolWorldLocation"],
]

const STATUS_NAMES: Dictionary = {
	RUNNING: "running",
	RUNNING_LATENT: "running_latent",
	SUCCEEDED: "succeeded",
	FAILED: "failed",
	UNSET: "unset",
}

const COND_NAMES: Dictionary = {
	COND_UNKNOWN: "unknown",
	COND_FALSE: "false",
	COND_TRUE: "true",
}

## The base binding owns exactly one task: `Delay Task` driven from the authored
## `Duration` (a literal template value or a bound value the subclass supplies).
## It needs no game state, so it belongs here; every other name is UNSUPPORTED.
const TASK_DECL: Dictionary = {
	"Delay Task": {
		"status": "implemented", "parameter_blind": false,
		"note": "counts the authored Duration (literal or bound) down; no game state",
	},
}

## Diagnostics, measured (never used for control flow).
var resolves: int = 0
var resolve_unknown: int = 0
var resolve_ref_access: int = 0


func status_name(value: int) -> String:
	return str(STATUS_NAMES.get(value, "?"))


func cond_name(value: int) -> String:
	return str(COND_NAMES.get(value, "?"))


## True when this binding can change the world. Shadow mode asserts false.
func mutates() -> bool:
	return false


## Declaration used by the coverage table:
## { "status": STATUS_*, "parameter_blind": bool, "note": String }
func declaration(kind: String, name: String) -> Dictionary:
	if kind == "task" and TASK_DECL.has(name):
		var row: Dictionary = TASK_DECL[name]
		return {
			"status": str(row.get("status", STATUS_UNSUPPORTED)),
			"parameter_blind": bool(row.get("parameter_blind", false)),
			"note": str(row.get("note", "")),
			"kind": kind,
			"name": name,
		}
	return {"status": STATUS_UNSUPPORTED, "parameter_blind": false, "note": "no binding declared", "kind": kind, "name": name}


# ---------------------------------------------------------------------------
# Value resolution (bound target precedence)
# ---------------------------------------------------------------------------


## Resolve one authored property of a node.
##
##   resolve(node, "Duration", ctx) -> {
##     "target": "Duration", "value": <Variant|"UNKNOWN">,
##     "source": SOURCE_*, "template": <authored parameters value or null>,
##     "template_present": bool, "binding": <bound record or {}>,
##     "path": <source_path or []>, "reason": String }
##
## PRECEDENCE (measured, not chosen): when the node has a `bound` entry for the
## target, that entry is authoritative and the template default is reported only
## as `template` -- it is NEVER returned as `value`. `ST_Patrol[17] Delay Task`
## proves the need: the template says `duration: 1.0` while the authored binding
## is `StateParameterData(state 3).PatrolPointData.WaitSeconds`.
##
## `bound` targets match `parameters` case-insensitively when there is no exact
## key (`Duration` vs `duration` on `Delay Task`) -- the only such pair in the
## payload; every other bound key without a parameter is a context slot.
func resolve(node: Dictionary, target: String, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"target": target,
		"value": VALUE_UNKNOWN,
		"source": SOURCE_UNSET,
		"template": null,
		"template_present": false,
		"binding": {},
		"path": [],
		"reason": "",
	}
	var parameters: Dictionary = node.get("parameters", {})
	var parameter_key: String = _match_key(parameters, target)
	if parameter_key != "":
		out["template_present"] = true
		out["template"] = parameters[parameter_key]
	var bound: Dictionary = node.get("bound", {})
	var bound_key: String = _match_key(bound, target)
	if bound_key == "":
		if parameter_key != "":
			if _is_ref_access(parameters[parameter_key]):
				out["source"] = SOURCE_REF_ACCESS
				out["reason"] = "RefAccessIndex is an output slot, not a value"
				resolve_ref_access += 1
			else:
				out["value"] = parameters[parameter_key]
				out["source"] = SOURCE_LITERAL
		resolves += 1
		return out
	var binding: Dictionary = bound[bound_key]
	out["binding"] = binding
	out["path"] = (binding.get("source_path", []) as Array).duplicate()
	if str(binding.get("source_array", "")) == "ContextData":
		out["source"] = SOURCE_CONTEXT
		out["reason"] = "ContextData slot (an object, not an authored value)"
		resolves += 1
		return out
	if str(binding.get("value", "")) != VALUE_UNKNOWN and binding.has("value"):
		# A producer that could resolve a literal binding emits it directly.
		out["value"] = binding["value"]
		out["source"] = SOURCE_AUTHORED_RECORD
		resolves += 1
		return out
	var bag: Dictionary = bag_value(node, binding, ctx)
	out["value"] = bag.get("value", VALUE_UNKNOWN)
	out["source"] = str(bag.get("source", SOURCE_BOUND_UNKNOWN))
	out["reason"] = str(bag.get("reason", ""))
	if str(out["value"]) == VALUE_UNKNOWN:
		resolve_unknown += 1
	resolves += 1
	return out


## Read a bound target out of the active frame bags. The bag is keyed
## `bags[source_array][source_index][path...]`; a leaf is
## `{"value": <Variant>, "source": SOURCE_*}`. The owning frame is the deepest
## active state with `state == source_state_index` in the reading node's tree
## (the state parameter bag belongs to that state, not to the caller).
static func bag_value(node: Dictionary, binding: Dictionary, ctx: Dictionary) -> Dictionary:
	var source_array: String = str(binding.get("source_array", ""))
	var source_state_raw: Variant = binding.get("source_state_index", null)
	var source_index_raw: Variant = binding.get("source_index", null)
	var source_state: int = -1 if source_state_raw == null else int(source_state_raw)
	var source_index: int = -1 if source_index_raw == null else int(source_index_raw)
	var tree_name: String = str(ctx.get("tree", node.get("tree", "")))
	var frames: Array = ctx.get("frames", [])
	for i: int in range((frames as Array).size() - 1, -1, -1):
		var frame: Dictionary = frames[i]
		if str(frame.get("tree", "")) != tree_name:
			continue
		if int(frame.get("state", -1)) != source_state:
			continue
		var bags: Dictionary = frame.get("bags", {})
		var by_source: Dictionary = bags.get(source_array, {})
		var slot_key: String = str(source_index)
		if not by_source.has(slot_key):
			return {"value": VALUE_UNKNOWN, "source": SOURCE_BOUND_UNKNOWN,
				"reason": "no %s[%s] in state %d's bag" % [source_array, slot_key, source_state]}
		var cursor: Variant = by_source[slot_key]
		for segment: Variant in (binding.get("source_path", []) as Array):
			if not (cursor is Dictionary):
				return {"value": VALUE_UNKNOWN, "source": SOURCE_BOUND_UNKNOWN,
					"reason": "bag path stops at a non-struct"}
			var d: Dictionary = cursor as Dictionary
			if d.has("value") and d.has("source"):
				# The port supplies this leaf as UNKNOWN (e.g. SmartObjectComponent).
				return d
			if not d.has(str(segment)):
				return {"value": VALUE_UNKNOWN, "source": SOURCE_BOUND_UNKNOWN,
					"reason": "bag has no '%s'" % str(segment)}
			cursor = d[str(segment)]
		if cursor is Dictionary and (cursor as Dictionary).has("value") and (cursor as Dictionary).has("source"):
			return cursor
	return {"value": VALUE_UNKNOWN, "source": SOURCE_BOUND_UNKNOWN,
		"reason": "owning state %d is not active" % source_state}


## Per-frame parameter bags. `{source_array: {source_index: {path...: leaf}}}`,
## built by the interpreter on state entry from `state_bags()`. Base: empty.
func state_bags(_tree_name: String, _state_index: int) -> Dictionary:
	return {}


## Classify where a node's VALUE parameters come from. Used by the coverage
## table for the per-instance `param_source` column; it never claims a value.
##   ref-access | inherited | bound-unknown | bound-authored-record |
##   literal  | context | none
static func param_source(node: Dictionary) -> String:
	if not (node.get("ref_access", []) as Array).is_empty():
		return "ref-access"
	if bool(node.get("inherited", false)):
		return "inherited"
	var bound: Dictionary = node.get("bound", {})
	var value_bindings: int = 0
	var authored_record: int = 0
	var unknown: int = 0
	for target: Variant in bound.keys():
		var binding: Dictionary = bound[target]
		if str(binding.get("source_array", "")) == "ContextData":
			continue
		value_bindings += 1
		if is_authored_record_path(binding.get("source_path", [])):
			authored_record += 1
		else:
			unknown += 1
	if value_bindings > 0:
		if unknown > 0:
			return "bound-unknown"
		return "bound-authored-record"
	if not (node.get("parameters", {}) as Dictionary).is_empty():
		return "literal"
	if not bound.is_empty():
		return "context"
	return "none"


## True when a binding path is one of the authored runtime records the port
## actually reads (`AUTHORED_RECORD_PATHS`, exact match).
static func is_authored_record_path(path: Variant) -> bool:
	if not (path is Array):
		return false
	var segments: Array = path as Array
	for candidate: Array in AUTHORED_RECORD_PATHS:
		if segments == candidate:
			return true
	return false


static func _match_key(table: Dictionary, target: String) -> String:
	if table.has(target):
		return target
	var lower: String = target.to_lower()
	for key: Variant in table.keys():
		if str(key).to_lower() == lower:
			return str(key)
	return ""


static func _is_ref_access(value: Variant) -> bool:
	return value is Dictionary and (value as Dictionary).has("RefAccessIndex")


# ---------------------------------------------------------------------------
# Conditions / tasks
# ---------------------------------------------------------------------------


## Evaluate one condition INSTANCE.
##   node:   the normalised node (`name`, `class`, `node_index`, `parameters`,
##           `bound`, `tree`, `state`);
##   ctx:    {tree, state, transition, tick, time, frames, interpreter}.
## Return COND_TRUE / COND_FALSE / COND_UNKNOWN.
func condition_state(_node: Dictionary, _ctx: Dictionary) -> int:
	return COND_UNKNOWN


## Per-instance coverage predicate for the coverage table. `node` is the
## normalised node (empty for a legacy caller); a binding that drives only some
## instances (e.g. `Delay Task` on a bound duration) narrows it here.
func covers(_kind: String, name: String, _tree_name: String, _state_index: int, _node: Dictionary = {}) -> bool:
	return str(declaration(_kind, name).get("status", STATUS_UNSUPPORTED)) != STATUS_UNSUPPORTED


## Instantiate a per-entry task instance. Return a Dictionary the interpreter
## will carry until the task exits; `task_tick`/`task_exit` receive the same
## dictionary. Return {} to mean "cannot drive".
##
## The base drives `Delay Task` from the AUTHORED duration (literal or bound).
## The guard subclass delegates here for literal durations and observes the
## FSM's authored WaitSeconds for the bound patrol case.
func task_enter(node: Dictionary, ctx: Dictionary) -> Dictionary:
	var name: String = str(node.get("name", ""))
	if str(declaration("task", name).get("status", STATUS_UNSUPPORTED)) == STATUS_UNSUPPORTED:
		return {}
	if name == "Delay Task":
		var duration: Dictionary = resolve(node, "Duration", ctx)
		if str(duration["source"]) == SOURCE_REF_ACCESS:
			return {}
		if str(duration["value"]) == VALUE_UNKNOWN:
			return {}
		if not (duration["value"] is float or duration["value"] is int):
			return {}
		var seconds: float = maxf(0.0, float(duration["value"]))
		return {
			"task": name,
			"node": node,
			"tree": str(ctx.get("tree", "")),
			"state": int(ctx.get("state", -1)),
			"status": SUCCEEDED if seconds <= 0.0 else RUNNING,
			"duration_s": seconds,
			"remaining_s": seconds,
			"duration_source": str(duration["source"]),
		}
	return {}


## Advance one task instance. Return RUNNING / RUNNING_LATENT / SUCCEEDED /
## FAILED / UNSET.
func task_tick(instance: Dictionary, delta: float) -> int:
	if instance.has("duration_s"):
		instance["remaining_s"] = maxf(0.0, float(instance.get("remaining_s", 0.0)) - delta)
		return SUCCEEDED if float(instance["remaining_s"]) <= 0.0 else RUNNING
	return UNSET


## Release a task instance (called on state exit). Must not fail.
func task_exit(_instance: Dictionary) -> void:
	pass


## Does an event satisfy a transition's `RequiredEvent`? Return COND_TRUE,
## COND_FALSE or COND_UNKNOWN (e.g. the event tag matches but its payload is not
## carried by the payload, so the transition's conditions cannot be evaluated).
func event_matches(_transition: Dictionary, _event: Dictionary) -> int:
	return COND_FALSE


## Called once after the interpreter finishes a tick. Shadow bindings flush
## per-tick observations here.
func after_tick(_interpreter: RefCounted) -> void:
	pass
