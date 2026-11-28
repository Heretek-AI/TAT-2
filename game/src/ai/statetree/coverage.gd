extends RefCounted
## Coverage table for the 21 authored trees (W10-B2.1), measured from the
## payload and the binding's per-instance predicate.
##
## TWO DIFFERENT NUMBERS, never conflated:
##   * `fully_covered`         STRUCTURAL: every task and condition instance has
##                             a handler that can drive it, either from an
##                             authored literal or from an authored record the
##                             port supplies. This is what "the port can run the
##                             tree" means.
##   * `fully_parity_covered`  DATA PARITY: additionally, no instance reads a
##                             value the payload/port cannot supply (`parity ==
##                             "unknown"`). A tree can be structurally covered
##                             and still be far from parity.
##
## Per instance the table records `param_source` (where the value comes from) and
## `parity` (whether that value is the authored one):
##   param_source: literal | bound-authored-record | bound-unknown | context |
##                 ref-access | inherited | none
##   parity:       authored | runtime-fed | unknown | uncovered
## and `blind` counts the covered instances whose parity is `unknown`.
##
## PARITY IS DATA PARITY, not behaviour parity. A `PORT GAP` row (e.g. a voice
## line the port does not play) can be `authored` because the value it would read
## is in the payload; the `status`/`note` columns remain the behaviour statement.
## `fully_parity_covered` therefore answers "every value this tree reads is the
## authored one", not "the port behaves like UE".
##
## Nothing here is asserted: the table is recomputed from `guard_behavior.json`
## on every run, so a producer change or a new binding moves it.
##
## Phase 3B.1 adds two honesty columns:
##   * `vacuous_trees` names a structurally covered tree whose tasks are PORT
##     GAPs (`ST_Subtree_IntruderNoLongerSuspicious`, 4 states) so
##     `fully_covered_trees` cannot be quoted as "a guard tree runs";
##   * `events` is the authored `StateTreeEvent.*` census (authored / emitted /
##     unemitted), measured from the payload against `events.gd`.

const TreeModel = preload("res://src/ai/statetree/tree_model.gd")
const Bindings = preload("res://src/ai/statetree/bindings.gd")
const StateEvents = preload("res://src/ai/statetree/events.gd")

const PARITY_AUTHORED: String = "authored"
const PARITY_RUNTIME_FED: String = "runtime-fed"
const PARITY_UNKNOWN: String = "unknown"
const PARITY_UNCOVERED: String = "uncovered"

const ROW_KEYS: Array[String] = ["status", "instances", "covered", "blind", "note"]

## The one structurally covered tree is an ALGEBRA result, not behaviour. It
## must be named as such wherever `fully_covered_trees=1` is quoted, so the
## number cannot be read as "the port runs a guard StateTree".
##
## Authored shape (payload v2): 4 states, 3 task instances, 0 conditions,
## 0 events, 0 subtree links.
##   Root -> Set Focus (Set Focus (Actor)) -> VO Line (Request Voice Line)
##        -> Delay (Delay Task) -> Succeeded (OnStateCompleted, to_kind Succeeded)
## `Set Focus (Actor)` and `Request Voice Line` are deliberate PORT GAPs: the
## port has no focus subsystem and its VO is FSM-tag driven, so both are
## immediately SUCCEEDED vacuously (`VACUOUS_TASKS` in `guard_bindings.gd`).
## Only the literal `Delay Task` has a port effect. The tree therefore proves
## the coverage algebra (every instance has a handler) and nothing about
## behaviour. Removing the gap would need a focus subsystem, which 3B.1 does
## not fake.
const VACUOUS_TREES: Dictionary = {
	"ST_Subtree_IntruderNoLongerSuspicious": {
		"states": 4,
		"state_flow": "Set Focus -> Request Voice Line -> Delay -> Succeeded",
		"payload_states": ["Root", "Set Focus", "VO Line", "Delay"],
		"tasks": ["Set Focus (Actor)", "Request Voice Line", "Delay Task"],
		"vacuous_tasks": ["Set Focus (Actor)", "Request Voice Line"],
		"why": "structurally covered but behaviourally vacuous: 2 of its 3 tasks are PORT GAPs (no focus subsystem, no tree-driven VO) that complete immediately and the leaf exits through a literal Delay Task; it proves the coverage algebra, not guard behaviour",
	},
}


## Returns
## {
##   "tasks": {name: {status, instances, covered, blind, note, param_sources,
##                    parity, trees}},
##   "conditions": {...},
##   "instances": [ {tree, state, state_name, kind, name, class, key, covered,
##                   param_source, parity, blind} ... ],
##   "totals": {...},
##   "per_tree": {tree: {tasks_instances, tasks_covered, conditions_instances,
##                       conditions_covered, fully_covered,
##                       fully_parity_covered, parity_unknown, param_sources}},
## }
static func build(trees: Dictionary, bindings: RefCounted) -> Dictionary:
	var tasks: Dictionary = {}
	var conditions: Dictionary = {}
	var per_tree: Dictionary = {}
	var instances: Array = []
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		per_tree[tree_name] = {
			"tasks_instances": 0, "tasks_covered": 0, "tasks_blind": 0,
			"conditions_instances": 0, "conditions_covered": 0, "conditions_blind": 0,
			"states": TreeModel.state_count(tree),
			"parity_authored": 0, "parity_runtime_fed": 0, "parity_unknown": 0,
			"param_sources": {},
		}
		var tree_row: Dictionary = per_tree[tree_name]
		for i: int in range(TreeModel.state_count(tree)):
			var state: Dictionary = TreeModel.state(tree, i)
			for node: Dictionary in state.get("task_nodes", []):
				_accumulate(tasks, node, "task", str(tree_name), i, str(state.get("name", "")), bindings, tree_row, true, instances)
			for node: Dictionary in state.get("enter_condition_nodes", []):
				_accumulate(conditions, node, "condition", str(tree_name), i, str(state.get("name", "")), bindings, tree_row, false, instances)
			for tr: Dictionary in state.get("transitions", []):
				for node: Dictionary in tr.get("condition_nodes", []):
					_accumulate(conditions, node, "condition", str(tree_name), i, str(state.get("name", "")), bindings, tree_row, false, instances)
		var row: Dictionary = per_tree[tree_name]
		row["fully_covered"] = int(row["tasks_instances"]) == int(row["tasks_covered"]) \
				and int(row["conditions_instances"]) == int(row["conditions_covered"])
		row["fully_parity_covered"] = bool(row["fully_covered"]) and int(row["parity_unknown"]) == 0
	var fully_covered_trees: Array = []
	var fully_parity_trees: Array = []
	var vacuous_trees: Array = []
	var vacuous_state_mismatch: Array = []
	for tree_name: Variant in per_tree.keys():
		if bool((per_tree[tree_name] as Dictionary)["fully_covered"]):
			fully_covered_trees.append(str(tree_name))
		if bool((per_tree[tree_name] as Dictionary)["fully_parity_covered"]):
			fully_parity_trees.append(str(tree_name))
		if VACUOUS_TREES.has(str(tree_name)):
			var declared: Dictionary = VACUOUS_TREES[str(tree_name)]
			var tree_row: Dictionary = per_tree[tree_name]
			tree_row["vacuous"] = true
			tree_row["vacuous_state_flow"] = str(declared["state_flow"])
			tree_row["vacuous_reason"] = str(declared["why"])
			vacuous_trees.append(str(tree_name))
			if int(tree_row["states"]) != int(declared["states"]):
				vacuous_state_mismatch.append("%s declared=%d measured=%d"
					% [str(tree_name), int(declared["states"]), int(tree_row["states"])])
	fully_covered_trees.sort()
	fully_parity_trees.sort()
	var events: Dictionary = StateEvents.census(trees)
	var by_status: Dictionary = {}
	for table: Dictionary in [tasks, conditions]:
		for name: Variant in table.keys():
			var row: Dictionary = table[name]
			var status: String = str(row["status"])
			by_status[status] = int(by_status.get(status, 0)) + 1
	var task_parity: Dictionary = _sum_dict(tasks, "parity")
	var condition_parity: Dictionary = _sum_dict(conditions, "parity")
	return {
		"tasks": tasks,
		"conditions": conditions,
		"instances": instances,
		"totals": {
			"task_classes": tasks.size(),
			"condition_classes": conditions.size(),
			"task_instances": _sum(tasks, "instances"),
			"task_covered": _sum(tasks, "covered"),
			"task_blind": _sum(tasks, "blind"),
			"task_parity_authored": int(task_parity.get(PARITY_AUTHORED, 0)),
			"task_parity_runtime_fed": int(task_parity.get(PARITY_RUNTIME_FED, 0)),
			"task_parity_unknown": int(task_parity.get(PARITY_UNKNOWN, 0)),
			"condition_instances": _sum(conditions, "instances"),
			"condition_covered": _sum(conditions, "covered"),
			"condition_blind": _sum(conditions, "blind"),
			"condition_parity_authored": int(condition_parity.get(PARITY_AUTHORED, 0)),
			"condition_parity_runtime_fed": int(condition_parity.get(PARITY_RUNTIME_FED, 0)),
			"condition_parity_unknown": int(condition_parity.get(PARITY_UNKNOWN, 0)),
			"by_status": by_status,
			"fully_covered_trees": fully_covered_trees,
			"fully_parity_covered_trees": fully_parity_trees,
			"vacuous_trees": vacuous_trees,
			"vacuous_state_mismatch": vacuous_state_mismatch,
			"events": events,
			"trees_total": per_tree.size(),
			"instances": instances.size(),
		},
		"per_tree": per_tree,
	}


static func _accumulate(table: Dictionary, node: Dictionary, kind: String, tree: String, state_index: int, state_name: String, bindings: RefCounted, tree_row: Dictionary, is_task: bool, instances: Array) -> void:
	var name: String = str(node.get("name", ""))
	var row: Dictionary = table.get(name, {})
	if row.is_empty():
		var decl: Dictionary = bindings.declaration(kind, name) if bindings != null else {}
		row = {
			"status": str(decl.get("status", "unsupported")),
			"instances": 0,
			"covered": 0,
			"blind": 0,
			"note": str(decl.get("note", "")),
			"parameter_blind_class": bool(decl.get("parameter_blind", false)),
			"trees": {},
			"param_sources": {},
			"parity": {},
		}
		table[name] = row
	var covered: bool = false
	if bindings != null:
		covered = bool(bindings.covers(kind, name, tree, state_index, node))
	var param_source: String = Bindings.param_source(node)
	var parity: String = _parity(covered, param_source)
	var blind: bool = covered and parity == PARITY_UNKNOWN
	row["instances"] = int(row["instances"]) + 1
	if covered:
		row["covered"] = int(row["covered"]) + 1
	if blind:
		row["blind"] = int(row["blind"]) + 1
	var source_counts: Dictionary = row["param_sources"]
	source_counts[param_source] = int(source_counts.get(param_source, 0)) + 1
	var parity_counts: Dictionary = row["parity"]
	parity_counts[parity] = int(parity_counts.get(parity, 0)) + 1
	var tree_counts: Dictionary = row["trees"]
	tree_counts[tree] = int(tree_counts.get(tree, 0)) + 1
	var tree_sources: Dictionary = tree_row["param_sources"]
	tree_sources[param_source] = int(tree_sources.get(param_source, 0)) + 1
	if parity == PARITY_AUTHORED:
		tree_row["parity_authored"] = int(tree_row["parity_authored"]) + 1
	elif parity == PARITY_RUNTIME_FED:
		tree_row["parity_runtime_fed"] = int(tree_row["parity_runtime_fed"]) + 1
	elif parity == PARITY_UNKNOWN:
		tree_row["parity_unknown"] = int(tree_row["parity_unknown"]) + 1
	if is_task:
		tree_row["tasks_instances"] = int(tree_row["tasks_instances"]) + 1
		if covered:
			tree_row["tasks_covered"] = int(tree_row["tasks_covered"]) + 1
		if blind:
			tree_row["tasks_blind"] = int(tree_row["tasks_blind"]) + 1
	else:
		tree_row["conditions_instances"] = int(tree_row["conditions_instances"]) + 1
		if covered:
			tree_row["conditions_covered"] = int(tree_row["conditions_covered"]) + 1
		if blind:
			tree_row["conditions_blind"] = int(tree_row["conditions_blind"]) + 1
	instances.append({
		"tree": tree,
		"state": state_index,
		"state_name": state_name,
		"kind": kind,
		"name": name,
		"class": str(node.get("class", "")),
		"key": str(node.get("key", "")),
		"node_index": int(node.get("node_index", -1)),
		"covered": covered,
		"param_source": param_source,
		"parity": parity,
		"blind": blind,
	})


## Data parity for one instance. `uncovered` first: a tree can be structurally
## covered only if every instance is covered, so this never hides a gap.
static func _parity(covered: bool, param_source: String) -> String:
	if not covered:
		return PARITY_UNCOVERED
	if param_source == "bound-authored-record":
		return PARITY_RUNTIME_FED
	if param_source == "bound-unknown" or param_source == "ref-access" or param_source == "inherited":
		return PARITY_UNKNOWN
	return PARITY_AUTHORED


static func _sum(table: Dictionary, key: String) -> int:
	var total: int = 0
	for name: Variant in table.keys():
		total += int((table[name] as Dictionary).get(key, 0))
	return total


## Per-row parity histogram summed across a class table.
static func _sum_dict(table: Dictionary, key: String) -> Dictionary:
	var out: Dictionary = {}
	for name: Variant in table.keys():
		var d: Dictionary = (table[name] as Dictionary).get(key, {})
		for k: Variant in d.keys():
			out[k] = int(out.get(k, 0)) + int(d[k])
	return out


## One line per vacuous tree, for the probe/report:
##   VACUOUS|tree|states|state_flow|reason
static func vacuous_lines(coverage: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var totals: Dictionary = coverage.get("totals", {})
	var per_tree: Dictionary = coverage.get("per_tree", {})
	for tree_name: Variant in totals.get("vacuous_trees", []):
		var row: Dictionary = per_tree.get(tree_name, {})
		out.append("VACUOUS|%s|%d|%s|%s" % [
			str(tree_name), int(row.get("states", 0)),
			str(row.get("vacuous_state_flow", "")), str(row.get("vacuous_reason", "")),
		])
	return out


## A stable human table for the report/probe:
##   TASK|name|status|instances|covered|blind|note|param_sources|parity
static func table_lines(coverage: Dictionary, kind: String = "tasks") -> PackedStringArray:
	var out: PackedStringArray = []
	var table: Dictionary = coverage.get(kind, {})
	var names: Array = table.keys()
	names.sort()
	for name: Variant in names:
		var row: Dictionary = table[name]
		out.append("%s|%s|%s|%d|%d|%d|%s|%s|%s" % [
			"TASK" if kind == "tasks" else "COND",
			str(name), str(row["status"]), int(row["instances"]),
			int(row["covered"]), int(row["blind"]), str(row["note"]),
			_compact(row.get("param_sources", {})), _compact(row.get("parity", {})),
		])
	return out


static func _compact(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key: Variant in keys:
		parts.append("%s=%d" % [str(key), int(counts[key])])
	return ",".join(parts)


## One-line machine summary used by the probe and the test.
static func summary_line(coverage: Dictionary) -> String:
	var t: Dictionary = coverage["totals"]
	var status: Dictionary = t["by_status"]
	var ts: Dictionary = _sum_dict(coverage["tasks"], "param_sources")
	var cs: Dictionary = _sum_dict(coverage["conditions"], "param_sources")
	return "STATETREE_COVERAGE trees=%d task_classes=%d task_instances=%d task_covered=%d task_blind=%d condition_classes=%d condition_instances=%d condition_covered=%d condition_blind=%d implemented=%d mapped=%d unsupported=%d fully_covered_trees=%d fully_parity_covered_trees=%d task_parity_authored=%d task_parity_runtime_fed=%d task_parity_unknown=%d condition_parity_authored=%d condition_parity_runtime_fed=%d condition_parity_unknown=%d task_sources=%s condition_sources=%s trees_total=%d vacuous_trees=%d vacuous_names=%s authored_events=%d emitted_events=%d unemitted_events=%d event_enter=%d event_transition=%d event_gates=%d event_total=%d" % [
		(coverage["per_tree"] as Dictionary).size(),
		int(t["task_classes"]), int(t["task_instances"]), int(t["task_covered"]), int(t["task_blind"]),
		int(t["condition_classes"]), int(t["condition_instances"]), int(t["condition_covered"]), int(t["condition_blind"]),
		int(status.get("implemented", 0)), int(status.get("mapped-to-port", 0)), int(status.get("unsupported", 0)),
		(t["fully_covered_trees"] as Array).size(), (t["fully_parity_covered_trees"] as Array).size(),
		int(t["task_parity_authored"]), int(t["task_parity_runtime_fed"]), int(t["task_parity_unknown"]),
		int(t["condition_parity_authored"]), int(t["condition_parity_runtime_fed"]), int(t["condition_parity_unknown"]),
		_compact(ts), _compact(cs),
		int(t.get("trees_total", 0)), (t["vacuous_trees"] as Array).size(), ",".join(PackedStringArray(t["vacuous_trees"])),
		int((t["events"] as Dictionary)["counts"]["authored"]),
		int((t["events"] as Dictionary)["counts"]["emitted"]),
		int((t["events"] as Dictionary)["counts"]["unemitted"]),
		int((t["events"] as Dictionary)["counts"]["enter"]),
		int((t["events"] as Dictionary)["counts"]["transition"]),
		int((t["events"] as Dictionary)["counts"]["gates"]),
		int((t["events"] as Dictionary)["counts"]["total"]),
	]
