extends RefCounted
## Authored UE 5.5 StateTree graphs as a Godot model (W9-P4 S1).
##
## Data: `res://data/generated/gameplay/guard_behavior.json`
## (`tat2.guard_behavior/2`, 21 trees / 459 states / 467 transitions, produced by
## `tools/parse_state_tree.py` from `extracted/json/AI/StateTrees/**`).
##
## WHAT THE PAYLOAD IS, AND WHAT THIS MODEL KEEPS
## It is a *property dump* of the cooked assets, flattened into a state list. It
## is NOT a compiled tree. Payload /2 carries one node object per task /
## enter-condition / utility consideration / transition condition
## (`{name, class, kind, node_index, template_index, data_source, inherited,
## parameters, bound}`); B2.1 keeps that object and exposes it as a normalised
## node (`_normalise_node`), because node identity, authored parameters and the
## `bound` map are what the interpreter now passes to the bindings. The name
## arrays (`tasks[]`, `enter_conditions[]`, `utility[]`,
## `transitions[].conditions[]`) are kept unchanged for legacy traces and
## inventory helpers.
##
##   * a state carries: index, name, depth, type (State | Group | LinkedAsset |
##     Linked | Subtree), parent, children (direct), span (the raw
##     `ChildrenBegin..ChildrenEnd` pre-order range, which includes every
##     descendant -- NOT the direct child list), tasks, task_nodes,
##     enter_conditions, enter_condition_nodes, utility, utility_nodes,
##     condition_nodes (enter + every transition condition, flat),
##     transitions, required_event_to_enter, consume_event_on_select,
##     linked_asset, linked_state_index, enabled, selection_behavior;
##   * a transition carries: index, trigger (OnEvent | OnStateCompleted |
##     OnStateSucceeded | OnStateFailed | OnTick), priority, required_event,
##     consume_event_on_select, to_kind (state | Succeeded | Next), target,
##     condition NAMES, condition_nodes, enabled;
##   * a node carries: name, class, kind, node_index, template_index,
##     data_source, inherited, parameters, bound, bound_targets, ref_access,
##     template_present, object_path, is_object, tree, state, key.
##
## NODE IDENTITY. `key` is `"<tree>#<node_index>"` for payload /2 objects and
## `"<tree>#n:<name>"` for /1 bare names. Display names are NOT unique (12
## classes share two display names), so every join and every diagnostic uses
## the key, never the name.
##
## MEASURED PAYLOAD FACTS THIS MODEL NOW EXPOSES (see `measure()`):
##   * 566 `Nodes.Structs` entries = 559 referenced + 7 unreferenced, all keyed;
##   * 497 records with non-empty `parameters`; 139 Blueprint object templates,
##     65 of them `inherited: true` (class default unknown);
##   * 676 `bound` entries; a binding from a parameter bag carries
##     `value: "UNKNOWN"` (canonical case: `Bool Compare.bLeft` <-
##     `GlobalParameterData.ResetAlertness`);
##   * 3 states with `required_event_to_enter`; `consume_event_on_select` false
##     on 2 states / 5 transitions;
##   * a `RefAccessIndex` parameter (`{"RefAccessIndex": {"Value": n}}`) is an
##     output slot, NOT a value; `_is_ref_access()` classifies it.
##   * state/asset-level parameter values are still absent: the bags serialise a
##     schema only (`PropertyDescs`, `SerialSize`), so those stay UNKNOWN.
##
## Consequences the interpreter respects (see `interpreter.gd`):
##   * a condition evaluates to TRUE / FALSE / UNKNOWN; UNKNOWN means "the
##     runtime does not determine this", never "false by default";
##   * a bound target is authoritative: `bindings.resolve()` never falls back to
##     the template default for a target that has a `bound` entry;
##   * every task handler is declared with an evidence class (implemented /
##     mapped-to-port / unsupported); the coverage table now splits structural
##     coverage (`fully_covered`) from data parity (`fully_parity_covered`).
##
## Composition is two different things in this dump and the model keeps them
## apart:
##   * `LinkedAsset` (45 states): `linked_asset` names another tree; execution
##     continues at that tree's `Root` (the payload never carries an entry state
##     for these: all 45 have `linked_state_index` null).
##   * `Linked` (2 states, both in ST_InvestigateStims_Guard): no asset; the
##     state's `linked_state_index` (8) is a **second root inside the same
##     asset** (`type == "Subtree"`), used as a named local sub-graph.
##
## The model is pure data: no Node, no autoload, no per-state instance object.
## One dictionary per tree keeps the interpreter's hot path allocation-free and
## makes the payload's shape (and its gaps) visible instead of hidden behind
## accessors.

const SCHEMA: String = "tat2.guard_behavior/2"
## Schema /1 payloads are still accepted: they carry node NAMES where /2 carries
## node objects, so the loader normalises both to the same name-only model.
const SCHEMA_V1: String = "tat2.guard_behavior/1"
const DEFAULT_PATH: String = "res://data/generated/gameplay/guard_behavior.json"

## `FStateTreeStateHandle` special indices (UE MAX_uint16 - n).
const HANDLE_INVALID: int = 65535
const HANDLE_SUCCEEDED: int = 65534
const HANDLE_NEXT: int = 65533

## `EStateTreeTransitionPriority` order, low to high. The payload preserves the
## authored enum name, so the interpreter ranks by this table and never by the
## string. UE 5.5's numeric order is `None(0), Low(1), Normal(2), Medium(3),
## High(4), Critical(5)` (`StateTreeTransitionPriority`, cited in
## `build/qa/w9/p4-re-statetree.md` §3.2) -- **Normal is weaker than Medium**.
## The names read like the opposite; 67 authored `Normal` and 21 `Medium`
## transitions make the difference observable, and `Critical` exists only on the
## forced-state `OnEvent` transitions that must beat the active leaf.
const PRIORITY_RANK: Dictionary = {
	"None": 0,
	"Low": 1,
	"Normal": 2,
	"Medium": 3,
	"High": 4,
	"Critical": 5,
}

## Rank for an enum name this model does not know. Sorts above every authored
## value so a future engine addition cannot be silently demoted; the parser
## records it as a validation error too.
const PRIORITY_UNKNOWN_RANK: int = 99

const TRIGGERS: Array[String] = [
	"OnStateCompleted",
	"OnStateSucceeded",
	"OnStateFailed",
	"OnTick",
	"OnEvent",
]

## A `Linked` state whose LinkedAsset is null names a root *inside* the same asset.
const LOCAL_LINK_TYPES: Array[String] = ["Linked", "Subtree"]

## Normalised node kinds.
const NODE_TASK: String = "task"
const NODE_ENTER: String = "enter_condition"
const NODE_UTILITY: String = "utility_consideration"
const NODE_TRANSITION: String = "transition_condition"
const NODE_UNREFERENCED: String = "unreferenced"


# ---------------------------------------------------------------------------
# Loading and parsing
# ---------------------------------------------------------------------------


## Load and parse one payload. Returns
##   { "ok": bool, "path": String, "schema": String, "trees": {name: tree},
##     "errors": Array[String], "warnings": Array[String], "stats": Dictionary }
## Nothing is cached here; the caller owns the trees.
static func load_library(path: String = DEFAULT_PATH) -> Dictionary:
	var out: Dictionary = {
		"ok": false, "path": path, "schema": "", "trees": {},
		"errors": [], "warnings": [], "stats": {},
	}
	if not FileAccess.file_exists(path):
		out["errors"].append("missing payload %s" % path)
		return out
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		out["errors"].append("cannot open %s (err %d)" % [path, FileAccess.get_open_error()])
		return out
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		out["errors"].append("%s is not a JSON object" % path)
		return out
	return parse_payload(parsed, path)


## Parse an already-decoded payload dictionary (tests use this).
static func parse_payload(payload: Dictionary, path: String = "<memory>") -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var schema: String = str(payload.get("schema", ""))
	if schema != SCHEMA and schema != SCHEMA_V1:
		errors.append("schema '%s' != %s" % [schema, SCHEMA])
	var trees_raw: Variant = payload.get("trees", {})
	if not (trees_raw is Dictionary):
		errors.append("trees is not an object")
		return {"ok": false, "path": path, "schema": schema, "trees": {}, "errors": errors, "warnings": warnings, "stats": {}}
	var trees: Dictionary = {}
	var names: Array = (trees_raw as Dictionary).keys()
	names.sort()
	for tree_name: Variant in names:
		var tree_raw: Variant = (trees_raw as Dictionary)[tree_name]
		if not (tree_raw is Dictionary):
			errors.append("tree %s is not an object" % str(tree_name))
			continue
		var tree: Dictionary = parse_tree(str(tree_name), tree_raw, path)
		trees[str(tree_name)] = tree
		for err: String in tree["errors"]:
			errors.append("%s: %s" % [str(tree_name), err])
		for warn: String in tree["warnings"]:
			warnings.append("%s: %s" % [str(tree_name), warn])
	# Cross-tree checks need every tree parsed: every LinkedAsset target must
	# resolve, and a link's entry index must exist when present.
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		for state: Dictionary in tree["states"]:
			if str(state.get("type", "")) != "LinkedAsset":
				continue
			var target: String = str(state.get("linked_asset", ""))
			if target == "":
				errors.append("%s: state %d links an empty asset" % [tree_name, int(state["index"])])
				continue
			if not trees.has(target):
				errors.append("%s: state %d links unknown asset '%s'" % [tree_name, int(state["index"]), target])
			var entry: int = int(state.get("linked_state_index", -1))
			if entry != -1 and entry != HANDLE_INVALID and not (entry >= 0 and entry < (tree["states"] as Array).size()):
				errors.append("%s: state %d has invalid linked entry %d" % [tree_name, int(state["index"]), entry])
	return {
		"ok": errors.is_empty(),
		"path": path,
		"schema": schema,
		"trees": trees,
		"errors": errors,
		"warnings": warnings,
		"stats": payload.get("stats", {}),
	}


## Parse one tree dictionary into the normalised model:
## {
##   "name", "package", "asset", "source", "roots": Array[String],
##   "stats": Dictionary, "errors": Array[String], "warnings": Array[String],
##   "states": Array[Dictionary],     # index == position
##   "entry": int,                    # roots[0]'s index, -1 when empty
##   "by_name": Dictionary,           # state name -> index (first wins)
##   "transitions": Array[Dictionary], # flat, in authored order
##   "unreferenced_nodes": Array[Dictionary]  # the 7 Nodes.Structs the graph skips
## }
## A state is:
## { "index", "name", "depth", "type", "parent", "children": Array[int],
##   "span": Vector2i,
##   "tasks": Array[String], "task_nodes": Array[Dictionary],
##   "enter_conditions": Array[String], "enter_condition_nodes": Array[Dictionary],
##   "utility": Array[String], "utility_nodes": Array[Dictionary],
##   "condition_nodes": Array[Dictionary],   # enter + every transition condition
##   "transitions": Array[Dictionary],
##   "required_event_to_enter": Dictionary, "consume_event_on_select": bool,
##   "linked_asset": String, "linked_state_index": int, "enabled": bool,
##   "selection": String, "is_root": bool }
static func parse_tree(tree_name: String, raw: Dictionary, path: String = "") -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var roots: Array = []
	var roots_raw: Variant = raw.get("roots", [])
	if roots_raw is Array:
		for r: Variant in roots_raw:
			roots.append(str(r))
	var states_raw: Variant = raw.get("states", [])
	if not (states_raw is Array):
		errors.append("states is not an array")
		return _empty_tree(tree_name, raw, path, roots, errors, warnings)
	var by_index: Dictionary = {}
	for entry: Variant in states_raw:
		if not (entry is Dictionary):
			errors.append("state entry is not an object")
			continue
		var s: Dictionary = entry
		var index: int = int(s.get("index", -1))
		if index < 0:
			errors.append("state with no index")
			continue
		if by_index.has(index):
			errors.append("duplicate state index %d" % index)
			continue
		by_index[index] = s
	# The authored list is dense 0..n-1; every other index in the payload is
	# positional, so a hole is a hard error rather than a skip.
	var expected: int = states_raw.size()
	var states: Array = []
	var transitions: Array = []
	var by_name: Dictionary = {}
	if by_index.size() != expected:
		errors.append("%d unique state indices for %d entries" % [by_index.size(), expected])
	for i: int in range(expected):
		if not by_index.has(i):
			errors.append("missing state index %d" % i)
			by_index[i] = {}
		var state: Dictionary = _normalise_state(i, by_index[i], tree_name)
		states.append(state)
		if not by_name.has(str(state["name"])):
			by_name[str(state["name"])] = i
		# The flat list keeps authored transition order: transition arbitration
		# ties are broken by it so two runs of the same data agree. Every
		# transition carries its owning TREE because a `LinkedAsset` stack holds
		# two trees at once and state indices are only unique inside one tree
		# (ST_Guard[3] and ST_Patrol[3] are both live in a patrolling guard).
		for tr: Dictionary in state["transitions"]:
			tr["tree"] = tree_name
			transitions.append(tr)
	var tree: Dictionary = {
		"name": tree_name,
		"package": str(raw.get("package", "")),
		"asset": str(raw.get("asset", "")),
		"source": path,
		"roots": roots,
		"stats": raw.get("stats", {}),
		"errors": errors,
		"warnings": warnings,
		"states": states,
		"entry": -1,
		"by_name": by_name,
		"transitions": transitions,
		"unreferenced_nodes": [],
	}
	# The 7 `Nodes.Structs` entries the graph never references (`Get Actor
	# Location` property functions + ST_Guard's Difficulty Evaluator). They are
	# part of the 566-node inventory, so the model keys them too.
	var unref_raw: Variant = raw.get("nodes_unreferenced", [])
	if unref_raw is Array:
		for entry: Variant in unref_raw:
			tree["unreferenced_nodes"].append(_normalise_node(entry, NODE_UNREFERENCED, tree_name, -1))
	else:
		warnings.append("nodes_unreferenced is not an array")
	tree["entry"] = entry_index(tree)
	_join_flat_transitions(tree, raw.get("transitions", []))
	_validate(tree)
	return tree


## The per-state `transitions[]` copies are 9-key records without `fallback` or
## the delay; the tree's flat `transitions[]` has all 14. Join by `index` and
## fail closed when a record is missing or belongs to another state.
##
## Conditions are joined by NODE IDENTITY (`node_index`, or the name on a /1
## payload) plus the authored `parameters`/`bound` maps -- never by the
## display-name list alone: two different nodes can share a display name, and a
## producer that changed a parameter without changing the name would otherwise
## pass silently.
static func _join_flat_transitions(tree: Dictionary, flat_raw: Variant) -> void:
	var errors: Array = tree["errors"]
	if not (flat_raw is Array) or (flat_raw as Array).is_empty():
		# A payload without the flat array (older producers, synthetic fixtures)
		# keeps the nested `delay.duration` and fallback "None".
		return
	var by_index: Dictionary = {}
	var flat_count: int = (flat_raw as Array).size()
	for entry: Variant in flat_raw:
		if not (entry is Dictionary):
			errors.append("flat transition entry is not an object")
			continue
		by_index[int((entry as Dictionary).get("index", -1))] = entry
	var joined: int = 0
	for state: Dictionary in tree["states"]:
		for tr: Dictionary in state["transitions"]:
			var index: int = int(tr["index"])
			if not by_index.has(index):
				errors.append("transition %d has no flat record" % index)
				continue
			var flat: Dictionary = by_index[index]
			if int(flat.get("from_state_index", -1)) != int(state["index"]):
				errors.append("transition %d flat from_state_index %d != owning state %d"
					% [index, int(flat.get("from_state_index", -1)), int(state["index"])])
			var fallback: String = str(flat.get("fallback", "None"))
			if fallback != "None" and fallback != "NextSelectableSibling":
				errors.append("transition %d has unknown fallback '%s'" % [index, fallback])
			# Cross-check every field the two records share: a producer that
			# changes one list and not the other must fail here, not silently
			# mix a nested target with a flat fallback. JSON numbers arrive as
			# floats, so the index compares numerically and a null `to_state`
			# (Succeeded/Next handles) normalises to the empty string.
			if flat.has("to_state_index") and int(flat["to_state_index"]) != int(tr.get("to_state_index", -1)):
				errors.append("transition %d flat to_state_index=%d != nested %d"
					% [index, int(flat["to_state_index"]), int(tr.get("to_state_index", -1))])
			if flat.has("enabled") and bool(flat["enabled"]) != bool(tr.get("enabled", true)):
				errors.append("transition %d flat enabled=%s != nested %s"
					% [index, str(flat["enabled"]), str(tr.get("enabled", true))])
			for key: String in ["to_kind", "trigger", "priority", "required_event"]:
				if flat.has(key) and str(flat[key]) != str(tr.get(key, "")):
					errors.append("transition %d flat %s=%s != nested %s"
						% [index, key, str(flat[key]), str(tr.get(key, ""))])
			if flat.has("to_state"):
				var flat_name: String = "" if flat["to_state"] == null else str(flat["to_state"])
				if flat_name != str(tr.get("to_state", "")):
					errors.append("transition %d flat to_state '%s' != nested '%s'"
						% [index, flat_name, str(tr.get("to_state", ""))])
			if flat.has("conditions"):
				var flat_ids: Array = []
				for c: Variant in (flat["conditions"] as Array):
					flat_ids.append(_node_signature(c))
				var nested_ids: Array = []
				for c: Dictionary in tr.get("condition_nodes", []):
					nested_ids.append(_node_signature(c))
				if flat_ids != nested_ids:
					errors.append("transition %d flat conditions differ from nested (identity %s != %s)"
						% [index, str(flat_ids), str(nested_ids)])
				elif (flat["conditions"] as Array).size() > 0 and (flat["conditions"] as Array)[0] is Dictionary:
					# Same identity list: the authored values must agree too.
					var flat_full: Array = []
					for c: Variant in (flat["conditions"] as Array):
						flat_full.append([(c as Dictionary).get("parameters", {}), (c as Dictionary).get("bound", {})])
					var nested_full: Array = []
					for c: Dictionary in tr.get("condition_nodes", []):
						nested_full.append([(c as Dictionary).get("parameters", {}), (c as Dictionary).get("bound", {})])
					if flat_full != nested_full:
						errors.append("transition %d flat conditions carry different parameters/bindings" % index)
			if flat.has("consume_event_on_select") and bool(flat["consume_event_on_select"]) != bool(tr.get("consume_event_on_select", true)):
				errors.append("transition %d flat consume_event_on_select=%s != nested %s"
					% [index, str(flat["consume_event_on_select"]), str(tr.get("consume_event_on_select", true))])
			tr["fallback"] = fallback
			tr["delay_s"] = float(flat.get("delay_seconds", 0.0))
			tr["delay_variance_s"] = float(flat.get("delay_random_variance", 0.0))
			if flat.has("consume_event_on_select"):
				tr["consume_event_on_select"] = bool(flat["consume_event_on_select"])
			joined += 1
	var total: int = int((tree["transitions"] as Array).size())
	if joined != total:
		errors.append("joined %d of %d transitions" % [joined, total])
	if by_index.size() != total:
		errors.append("flat transition count %d != per-state count %d" % [by_index.size(), total])
	if flat_count != total:
		errors.append("flat array has %d entries for %d per-state transitions" % [flat_count, total])


static func _empty_tree(tree_name: String, raw: Dictionary, path: String, roots: Array, errors: Array, warnings: Array) -> Dictionary:
	return {
		"name": tree_name,
		"package": str(raw.get("package", "")),
		"asset": str(raw.get("asset", "")),
		"source": path,
		"roots": roots,
		"stats": raw.get("stats", {}),
		"errors": errors,
		"warnings": warnings,
		"states": [],
		"entry": -1,
		"by_name": {},
		"transitions": [],
		"unreferenced_nodes": [],
	}


static func _validate(tree: Dictionary) -> void:
	var states: Array = tree["states"]
	var errors: Array = tree["errors"]
	var warnings: Array = tree["warnings"]
	var count: int = states.size()
	var seen_keys: Dictionary = {}
	for unref: Dictionary in tree.get("unreferenced_nodes", []):
		var ukey: String = str(unref.get("key", ""))
		if bool(unref.get("is_object", false)) and seen_keys.has(ukey):
			errors.append("node key '%s' is not unique" % ukey)
		seen_keys[ukey] = true
	for i: int in range(count):
		var state: Dictionary = states[i]
		if int(state["index"]) != i:
			errors.append("state at position %d carries index %d" % [i, int(state["index"])])
		if str(state["type"]) == "Group" and not (state["tasks"] as Array).is_empty():
			warnings.append("group state %d carries %d tasks" % [i, (state["tasks"] as Array).size()])
		if state["is_root"] and int(state["depth"]) != 0:
			errors.append("root state %d has depth %d" % [i, int(state["depth"])])
		var parent: int = int(state["parent"])
		if not state["is_root"] and parent >= 0 and parent < count:
			if int(state["depth"]) != int((states[parent] as Dictionary)["depth"]) + 1:
				errors.append("state %d depth %d does not follow parent %d" % [i, int(state["depth"]), parent])
		for child: Variant in state["children"]:
			var c: int = int(child)
			if c < 0 or c >= count:
				errors.append("state %d child %d out of range" % [i, c])
				continue
			if int((states[c] as Dictionary)["parent"]) != i:
				errors.append("state %d child %d claims parent %d" % [i, c, int((states[c] as Dictionary)["parent"])])
		# The name arrays are a legacy view of the node arrays; they must stay in
		# lockstep or a trace would name a different node than the interpreter ran.
		if (state["task_nodes"] as Array).size() != (state["tasks"] as Array).size():
			errors.append("state %d has %d task nodes for %d task names" % [i, (state["task_nodes"] as Array).size(), (state["tasks"] as Array).size()])
		if (state["enter_condition_nodes"] as Array).size() != (state["enter_conditions"] as Array).size():
			errors.append("state %d has %d enter nodes for %d names" % [i, (state["enter_condition_nodes"] as Array).size(), (state["enter_conditions"] as Array).size()])
		if (state["utility_nodes"] as Array).size() != (state["utility"] as Array).size():
			errors.append("state %d has %d utility nodes for %d names" % [i, (state["utility_nodes"] as Array).size(), (state["utility"] as Array).size()])
		var gate: Dictionary = state.get("required_event_to_enter", {})
		if not gate.is_empty() and str(gate.get("tag", "")) == "":
			errors.append("state %d has required_event_to_enter without a tag" % i)
		for node_list: Array in [state["task_nodes"], state["enter_condition_nodes"], state["utility_nodes"]]:
			for node: Dictionary in node_list:
				var key: String = str(node.get("key", ""))
				if key == "":
					errors.append("state %d has a node with no identity" % i)
				elif bool(node.get("is_object", false)) and seen_keys.has(key):
					errors.append("state %d node key '%s' is not unique" % [i, key])
				seen_keys[key] = true
		for tr: Dictionary in state["transitions"]:
			var to_kind: String = str(tr["to_kind"])
			var to_index: int = int(tr["to_state_index"])
			if to_kind == "state":
				if to_index < 0 or to_index >= count:
					errors.append("state %d transition %d targets missing state %d" % [i, int(tr["index"]), to_index])
			elif to_kind == "Succeeded" or to_kind == "Next":
				var want: int = HANDLE_SUCCEEDED if to_kind == "Succeeded" else HANDLE_NEXT
				if to_index != want:
					errors.append("state %d transition %d to_kind=%s carries handle %d (want %d)"
						% [i, int(tr["index"]), to_kind, to_index, want])
			else:
				errors.append("state %d transition %d has unknown to_kind '%s'" % [i, int(tr["index"]), to_kind])
			var trigger: String = str(tr["trigger"])
			if not (trigger in TRIGGERS):
				errors.append("state %d transition %d has unknown trigger '%s'" % [i, int(tr["index"]), trigger])
			if trigger == "OnEvent" and str(tr["required_event"]) == "":
				errors.append("state %d transition %d is OnEvent with no required_event" % [i, int(tr["index"])])
			if trigger != "OnEvent" and str(tr["required_event"]) != "":
				warnings.append("state %d transition %d carries required_event on %s" % [i, int(tr["index"]), trigger])
			if int(tr["priority_rank"]) == PRIORITY_UNKNOWN_RANK:
				errors.append("state %d transition %d has unknown priority '%s'" % [i, int(tr["index"]), str(tr["priority"])])
			for node: Dictionary in tr.get("condition_nodes", []):
				var key: String = str(node.get("key", ""))
				if key == "":
					errors.append("state %d transition %d has a condition with no identity" % [i, int(tr["index"])])
				elif bool(node.get("is_object", false)) and seen_keys.has(key):
					errors.append("state %d transition %d node key '%s' is not unique" % [i, int(tr["index"]), key])
				seen_keys[key] = true
	# A tree root must be indexed before the tree can be entered.
	if tree["entry"] < 0:
		errors.append("no entry root")


## One task / condition entry -> its authored display name.
## Payload /2 carries node objects (`{name, class, node_index, …}`); /1 carried
## bare names. Names stay the trace key; `_normalise_node()` keeps the object.
static func _node_name(entry: Variant) -> String:
	if entry is Dictionary:
		return str((entry as Dictionary).get("name", ""))
	return str(entry)


## Stable identity for a raw payload entry or an already-normalised node:
## `node:<index>` for payload /2 objects, `name:<name>` for /1 bare names.
static func _node_signature(entry: Variant) -> String:
	if entry is Dictionary:
		var d: Dictionary = entry as Dictionary
		var idx: int = int(d.get("node_index", -1))
		if idx >= 0:
			return "node:%d" % idx
		return "name:%s" % str(d.get("name", ""))
	return "name:%s" % str(entry)


## A `{"RefAccessIndex": {"Value": n}}` parameter is an output *slot*, not a
## value: the task writes it at run time. 119 authored parameter values are this
## shape, so treating it as data would fabricate a number.
static func _is_ref_access(value: Variant) -> bool:
	return value is Dictionary and (value as Dictionary).has("RefAccessIndex")


## Payload /2 node object (or /1 bare name) -> the normalised node the
## interpreter and bindings consume. `parameters`/`bound` are kept by reference:
## the parsed payload is read-only after `load_library()`.
static func _normalise_node(entry: Variant, kind: String, tree_name: String, state_index: int) -> Dictionary:
	var out: Dictionary = {
		"name": "",
		"class": "",
		"kind": kind,
		"node_index": -1,
		"template_index": -1,
		"data_source": "",
		"inherited": false,
		"parameters": {},
		"bound": {},
		"bound_targets": [],
		"ref_access": [],
		"template_present": false,
		"object_path": "",
		"is_object": false,
		"tree": tree_name,
		"state": state_index,
		"key": "",
	}
	if entry is Dictionary:
		var d: Dictionary = entry as Dictionary
		out["is_object"] = true
		out["name"] = str(d.get("name", ""))
		out["class"] = "" if d.get("class", null) == null else str(d.get("class"))
		if d.has("kind"):
			out["kind"] = str(d.get("kind", kind))
		out["node_index"] = int(d.get("node_index", -1))
		out["template_index"] = int(d.get("template_index", -1))
		out["data_source"] = str(d.get("data_source", ""))
		out["inherited"] = bool(d.get("inherited", false))
		var params: Variant = d.get("parameters", {})
		if params is Dictionary:
			out["parameters"] = params
			out["template_present"] = true
		var bound: Variant = d.get("bound", {})
		if bound is Dictionary:
			out["bound"] = bound
		out["object_path"] = str(d.get("object_path", ""))
	else:
		out["name"] = str(entry)
	# Derived views, built once at parse time.
	var bound_targets: Array = []
	for target: Variant in (out["bound"] as Dictionary).keys():
		bound_targets.append(str(target))
	bound_targets.sort()
	out["bound_targets"] = bound_targets
	var ref_access: Array = []
	for key: Variant in (out["parameters"] as Dictionary).keys():
		if _is_ref_access((out["parameters"] as Dictionary)[key]):
			ref_access.append(str(key))
	ref_access.sort()
	out["ref_access"] = ref_access
	out["key"] = node_key(tree_name, int(out["node_index"]), str(out["name"]))
	return out


## The identity key: `"<tree>#<node_index>"` for payload /2, `"<tree>#n:<name>"`
## when the payload carries only a display name. Unique across the 566 nodes.
static func node_key(tree_name: String, node_index: int, node_name: String) -> String:
	if node_index >= 0:
		return "%s#%d" % [tree_name, node_index]
	return "%s#n:%s" % [tree_name, node_name]


static func _normalise_required_event(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		return {
			"tag": str(d.get("tag", "")),
			"payload_struct": str(d.get("payload_struct", "")),
		}
	if raw is String and str(raw) != "":
		return {"tag": str(raw), "payload_struct": ""}
	return {}


static func _normalise_state(index: int, raw: Dictionary, tree_name: String = "") -> Dictionary:
	var out: Dictionary = {
		"index": index,
		"name": str(raw.get("name", "")),
		"depth": int(raw.get("depth", 0)),
		"type": str(raw.get("type", "State")),
		"parent": int(raw.get("parent_index", -1)) if raw.get("parent_index", null) != null else -1,
		"children": [],
		"span": Vector2i(0, 0),
		"tasks": [],
		"task_nodes": [],
		"enter_conditions": [],
		"enter_condition_nodes": [],
		"utility": [],
		"utility_nodes": [],
		"condition_nodes": [],
		"transitions": [],
		"required_event_to_enter": {},
		"consume_event_on_select": bool(raw.get("consume_event_on_select", true)),
		"linked_asset": str(raw.get("linked_asset", "")) if raw.get("linked_asset", null) != null else "",
		"linked_state_index": int(raw.get("linked_state_index", -1)) if raw.get("linked_state_index", null) != null else -1,
		"enabled": bool(raw.get("enabled", true)),
		"selection": str(raw.get("selection_behavior", "")),
		"is_root": raw.get("parent_index", null) == null,
	}
	for child: Variant in (raw.get("children", []) as Array):
		out["children"].append(int(child))
	var span: Variant = raw.get("children_range", null)
	if span is Array and (span as Array).size() == 2:
		out["span"] = Vector2i(int((span as Array)[0]), int((span as Array)[1]))
	for t: Variant in (raw.get("tasks", []) as Array):
		var node: Dictionary = _normalise_node(t, NODE_TASK, tree_name, index)
		out["task_nodes"].append(node)
		out["tasks"].append(str(node["name"]))
	for c: Variant in (raw.get("enter_conditions", []) as Array):
		var node: Dictionary = _normalise_node(c, NODE_ENTER, tree_name, index)
		out["enter_condition_nodes"].append(node)
		out["enter_conditions"].append(str(node["name"]))
		out["condition_nodes"].append(node)
	for u: Variant in (raw.get("utility_considerations", []) as Array):
		var node: Dictionary = _normalise_node(u, NODE_UTILITY, tree_name, index)
		out["utility_nodes"].append(node)
		out["utility"].append(str(node["name"]))
	out["required_event_to_enter"] = _normalise_required_event(raw.get("required_event_to_enter", null))
	var list: Array = []
	for tr_raw: Variant in (raw.get("transitions", []) as Array):
		if not (tr_raw is Dictionary):
			continue
		var tr: Dictionary = _normalise_transition(index, tr_raw, tree_name)
		list.append(tr)
		for node: Dictionary in tr["condition_nodes"]:
			out["condition_nodes"].append(node)
	out["transitions"] = list
	return out


static func _normalise_transition(owner_state: int, raw: Dictionary, tree_name: String = "") -> Dictionary:
	var priority: String = str(raw.get("priority", "None"))
	var conditions: Array = []
	var condition_nodes: Array = []
	for c: Variant in (raw.get("conditions", []) as Array):
		var node: Dictionary = _normalise_node(c, NODE_TRANSITION, tree_name, owner_state)
		condition_nodes.append(node)
		conditions.append(str(node["name"]))
	var delay: Dictionary = raw.get("delay", {}) if raw.get("delay", {}) is Dictionary else {}
	return {
		"index": int(raw.get("index", -1)),
		"state": owner_state,
		"trigger": str(raw.get("trigger", "")),
		"priority": priority,
		"priority_rank": int(PRIORITY_RANK.get(priority, PRIORITY_UNKNOWN_RANK)),
		"required_event": str(raw.get("required_event", "")),
		"consume_event_on_select": bool(raw.get("consume_event_on_select", true)),
		"to_kind": str(raw.get("to_kind", "")),
		"to_state_index": int(raw.get("to_state_index", -1)),
		"to_state": str(raw.get("to_state", "")) if raw.get("to_state", null) != null else "",
		"conditions": conditions,
		"condition_nodes": condition_nodes,
		"enabled": bool(raw.get("enabled", true)),
		# The nested copy's own delay is the fallback for payloads without the
		# flat array; the join overwrites it with the authored value when present.
		"delay_s": float(delay.get("duration", 0.0)),
		"delay_variance_s": float(delay.get("RandomVariance", 0.0)),
		"fallback": "None",
	}


# ---------------------------------------------------------------------------
# Accessors (pure; a tree is a Dictionary)
# ---------------------------------------------------------------------------


static func state_count(tree: Dictionary) -> int:
	return (tree.get("states", []) as Array).size()


static func has_state(tree: Dictionary, index: int) -> bool:
	return index >= 0 and index < state_count(tree)


static func state(tree: Dictionary, index: int) -> Dictionary:
	if not has_state(tree, index):
		return {}
	return (tree["states"] as Array)[index]


static func state_name(tree: Dictionary, index: int) -> String:
	return str(state(tree, index).get("name", ""))


static func children(tree: Dictionary, index: int) -> Array:
	return state(tree, index).get("children", [])


static func parent_index(tree: Dictionary, index: int) -> int:
	return int(state(tree, index).get("parent", -1))


static func is_root(tree: Dictionary, index: int) -> bool:
	return bool(state(tree, index).get("is_root", false))


static func is_linked_asset(tree: Dictionary, index: int) -> bool:
	var s: Dictionary = state(tree, index)
	return str(s.get("type", "")) == "LinkedAsset" and str(s.get("linked_asset", "")) != ""


static func is_local_link(tree: Dictionary, index: int) -> bool:
	var s: Dictionary = state(tree, index)
	if not LOCAL_LINK_TYPES.has(str(s.get("type", ""))):
		return false
	return int(s.get("linked_state_index", -1)) >= 0


static func entry_index(tree: Dictionary) -> int:
	var states: Array = tree.get("states", [])
	var roots: Array = tree.get("roots", [])
	if not roots.is_empty():
		for i: int in range(states.size()):
			var s: Dictionary = states[i]
			if s.get("is_root", false) and str(s.get("name", "")) == str(roots[0]):
				return i
	for i: int in range(states.size()):
		if (states[i] as Dictionary).get("is_root", false):
			return i
	return -1


static func root_index_for(tree: Dictionary, root_name: String) -> int:
	var states: Array = tree.get("states", [])
	for i: int in range(states.size()):
		var s: Dictionary = states[i]
		if s.get("is_root", false) and str(s.get("name", "")) == root_name:
			return i
	return -1


## `"Root/Standard States/Reset Focus"` for the trace.
static func path_string(tree: Dictionary, index: int) -> String:
	var parts: PackedStringArray = []
	var cursor: int = index
	var hops: int = 0
	while cursor >= 0 and hops < 64:
		parts.insert(0, state_name(tree, cursor))
		cursor = parent_index(tree, cursor)
		hops += 1
	return "/".join(parts)


## Every state index reachable from `index` through direct children and local
## `Linked` roots in the same asset. `LinkedAsset` targets belong to another tree
## and are not expanded here.
static func local_reach(tree: Dictionary, index: int) -> Array:
	var seen: Dictionary = {}
	var queue: Array = [index]
	var out: Array = []
	while not queue.is_empty():
		var cursor: int = int(queue.pop_front())
		if not has_state(tree, cursor) or seen.has(cursor):
			continue
		seen[cursor] = true
		out.append(cursor)
		for child: Variant in children(tree, cursor):
			queue.append(int(child))
		if is_local_link(tree, cursor):
			queue.append(int(state(tree, cursor).get("linked_state_index", -1)))
	return out


# ---------------------------------------------------------------------------
# Inventory helpers (the coverage table is measured from these, never asserted)
# ---------------------------------------------------------------------------


## Every distinct task name with its instance count across the given trees.
static func task_inventory(trees: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		for i: int in range(state_count(tree)):
			for t: Variant in state(tree, i).get("tasks", []):
				out[str(t)] = int(out.get(str(t), 0)) + 1
	return out


## Every normalised node in one tree, referenced first then unreferenced.
static func all_nodes(tree: Dictionary) -> Array:
	var out: Array = []
	for i: int in range(state_count(tree)):
		var state: Dictionary = state(tree, i)
		for node: Dictionary in state.get("task_nodes", []):
			out.append(node)
		for node: Dictionary in state.get("enter_condition_nodes", []):
			out.append(node)
		for node: Dictionary in state.get("utility_nodes", []):
			out.append(node)
		for tr: Dictionary in state.get("transitions", []):
			for node: Dictionary in tr.get("condition_nodes", []):
				out.append(node)
	for node: Dictionary in tree.get("unreferenced_nodes", []):
		out.append(node)
	return out


## Sorted identity keys for one tree (referenced + unreferenced).
static func node_keys(tree: Dictionary) -> PackedStringArray:
	var keys: PackedStringArray = []
	for node: Dictionary in all_nodes(tree):
		keys.append(str(node.get("key", "")))
	keys.sort()
	return keys


## Every distinct condition name (enter + transition) with instance counts.
static func condition_inventory(trees: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		for i: int in range(state_count(tree)):
			for c: Variant in state(tree, i).get("enter_conditions", []):
				out[str(c)] = int(out.get(str(c), 0)) + 1
			for tr: Dictionary in state(tree, i).get("transitions", []):
				for c: Variant in tr.get("conditions", []):
					out[str(c)] = int(out.get(str(c), 0)) + 1
	return out


## Per-tree counts measured from the parsed model, in the payload's `stats`
## shape, so producer drift shows up as a mismatch. The node block is what B2.1
## added: 566 keys, 497 records with parameters, 676 bindings.
static func measure(tree: Dictionary) -> Dictionary:
	var transitions: int = 0
	var task_instances: int = 0
	var condition_instances: int = 0
	var disabled: int = 0
	var linked: int = 0
	var groups: int = 0
	var max_depth: int = 0
	var task_names: Dictionary = {}
	var condition_names: Dictionary = {}
	var events: Dictionary = {}
	var triggers: Dictionary = {}
	var node_keys_seen: Dictionary = {}
	var nodes: int = 0
	var node_duplicates: int = 0
	var nodes_with_parameters: int = 0
	var object_templates: int = 0
	var inherited_templates: int = 0
	var bound_bindings: int = 0
	var binding_sources: Dictionary = {}
	var ref_access_values: int = 0
	var gated_states: int = 0
	var consume_false_states: int = 0
	var consume_false_transitions: int = 0
	for i: int in range(state_count(tree)):
		var s: Dictionary = state(tree, i)
		max_depth = maxi(max_depth, int(s.get("depth", 0)))
		if not bool(s.get("enabled", true)):
			disabled += 1
		if str(s.get("type", "")) == "Group":
			groups += 1
		if is_linked_asset(tree, i):
			linked += 1
		if not (s.get("required_event_to_enter", {}) as Dictionary).is_empty():
			gated_states += 1
		if not bool(s.get("consume_event_on_select", true)):
			consume_false_states += 1
		for t: Variant in s.get("tasks", []):
			task_instances += 1
			task_names[str(t)] = true
		for c: Variant in s.get("enter_conditions", []):
			condition_instances += 1
			condition_names[str(c)] = true
		for tr: Dictionary in s.get("transitions", []):
			transitions += 1
			var trigger: String = str(tr.get("trigger", ""))
			triggers[trigger] = int(triggers.get(trigger, 0)) + 1
			var ev: String = str(tr.get("required_event", ""))
			if ev != "":
				events[ev] = true
			if not bool(tr.get("consume_event_on_select", true)):
				consume_false_transitions += 1
			for c: Variant in tr.get("conditions", []):
				condition_instances += 1
				condition_names[str(c)] = true
	for node: Dictionary in all_nodes(tree):
		nodes += 1
		var key: String = str(node.get("key", ""))
		if bool(node.get("is_object", false)):
			if node_keys_seen.has(key):
				node_duplicates += 1
			node_keys_seen[key] = true
		if not (node.get("parameters", {}) as Dictionary).is_empty():
			nodes_with_parameters += 1
		if str(node.get("object_path", "")) != "":
			object_templates += 1
		if bool(node.get("inherited", false)):
			inherited_templates += 1
		for target: Variant in (node.get("bound", {}) as Dictionary).keys():
			bound_bindings += 1
			var binding: Dictionary = (node.get("bound", {}) as Dictionary)[target]
			var source: String = str(binding.get("source_array", ""))
			binding_sources[source] = int(binding_sources.get(source, 0)) + 1
		ref_access_values += (node.get("ref_access", []) as Array).size()
	var event_list: Array = events.keys()
	event_list.sort()
	return {
		"states": state_count(tree),
		"transitions": transitions,
		"groups": groups,
		"linked_asset_states": linked,
		"disabled_states": disabled,
		"max_depth": max_depth,
		"tasks": task_names.size(),
		"task_instances": task_instances,
		"conditions": condition_names.size(),
		"condition_instances": condition_instances,
		"events": event_list,
		"triggers": triggers,
		"nodes": nodes,
		"nodes_referenced": nodes - (tree.get("unreferenced_nodes", []) as Array).size(),
		"nodes_unreferenced": (tree.get("unreferenced_nodes", []) as Array).size(),
		"node_keys": node_keys_seen.size(),
		"nodes_duplicate_keys": node_duplicates,
		"nodes_with_parameters": nodes_with_parameters,
		"object_templates": object_templates,
		"inherited_templates": inherited_templates,
		"bound_bindings": bound_bindings,
		"binding_sources": binding_sources,
		"ref_access_values": ref_access_values,
		"required_event_states": gated_states,
		"consume_event_false_states": consume_false_states,
		"consume_event_false_transitions": consume_false_transitions,
	}
