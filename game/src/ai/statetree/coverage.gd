extends RefCounted
## Coverage table for the 21 authored trees (W9-P4 S1), measured from the
## payload and the binding's per-instance predicate.
##
## The brief asks for: for each task/condition class in the dump,
## `implemented` / `mapped-to-port` / `unsupported`, counted across all 21 trees.
## This module produces exactly that, plus the two numbers that matter for the
## honest ceiling:
##   * `covered`   how many authored instances the binding can drive;
##   * `blind`     how many covered instances are `parameter_blind` (the payload
##                 does not carry the authored node parameter).
##
## Nothing here is asserted: the table is recomputed from `guard_behavior.json`
## on every run, so a producer change or a new binding moves it.

const TreeModel = preload("res://src/ai/statetree/tree_model.gd")

const ROW_KEYS: Array[String] = ["status", "instances", "covered", "blind", "note"]


## Returns
## {
##   "tasks": {name: {status, instances, covered, blind, note, trees: {tree: n}}},
##   "conditions": {...},
##   "totals": {tasks, conditions, instances, covered, blind} per status,
##   "per_tree": {tree: {tasks_instances, tasks_covered, conditions_instances,
##                       conditions_covered, fully_covered: bool}},
## }
static func build(trees: Dictionary, bindings: RefCounted) -> Dictionary:
	var tasks: Dictionary = {}
	var conditions: Dictionary = {}
	var per_tree: Dictionary = {}
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		per_tree[tree_name] = {
			"tasks_instances": 0, "tasks_covered": 0,
			"conditions_instances": 0, "conditions_covered": 0,
			"states": TreeModel.state_count(tree),
		}
		for i: int in range(TreeModel.state_count(tree)):
			var state: Dictionary = TreeModel.state(tree, i)
			for task: Variant in state.get("tasks", []):
				_accumulate(tasks, str(task), "task", str(tree_name), i, bindings, per_tree[tree_name], true)
			for cond: Variant in state.get("enter_conditions", []):
				_accumulate(conditions, str(cond), "condition", str(tree_name), i, bindings, per_tree[tree_name], false)
			for tr: Dictionary in state.get("transitions", []):
				for cond: Variant in tr.get("conditions", []):
					_accumulate(conditions, str(cond), "condition", str(tree_name), i, bindings, per_tree[tree_name], false)
		var row: Dictionary = per_tree[tree_name]
		row["fully_covered"] = int(row["tasks_instances"]) == int(row["tasks_covered"]) \
				and int(row["conditions_instances"]) == int(row["conditions_covered"])
	var totals: Dictionary = {"tasks": 0, "conditions": 0, "instances": 0, "covered": 0, "blind": 0}
	var by_status: Dictionary = {}
	for table: Dictionary in [tasks, conditions]:
		for name: Variant in table.keys():
			var row: Dictionary = table[name]
			var status: String = str(row["status"])
			by_status[status] = int(by_status.get(status, 0)) + 1
	return {
		"tasks": tasks,
		"conditions": conditions,
		"totals": {
			"task_classes": tasks.size(),
			"condition_classes": conditions.size(),
			"task_instances": _sum(tasks, "instances"),
			"task_covered": _sum(tasks, "covered"),
			"task_blind": _sum(tasks, "blind"),
			"condition_instances": _sum(conditions, "instances"),
			"condition_covered": _sum(conditions, "covered"),
			"condition_blind": _sum(conditions, "blind"),
			"by_status": by_status,
		},
		"per_tree": per_tree,
	}


static func _accumulate(table: Dictionary, name: String, kind: String, tree: String, state_index: int, bindings: RefCounted, tree_row: Dictionary, is_task: bool) -> void:
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
		}
		table[name] = row
	var covered: bool = false
	if bindings != null:
		covered = bool(bindings.covers(kind, name, tree, state_index))
	row["instances"] = int(row["instances"]) + 1
	if covered:
		row["covered"] = int(row["covered"]) + 1
		if bool(row.get("parameter_blind_class", false)):
			row["blind"] = int(row["blind"]) + 1
	var tree_counts: Dictionary = row["trees"]
	tree_counts[tree] = int(tree_counts.get(tree, 0)) + 1
	if is_task:
		tree_row["tasks_instances"] = int(tree_row["tasks_instances"]) + 1
		if covered:
			tree_row["tasks_covered"] = int(tree_row["tasks_covered"]) + 1
	else:
		tree_row["conditions_instances"] = int(tree_row["conditions_instances"]) + 1
		if covered:
			tree_row["conditions_covered"] = int(tree_row["conditions_covered"]) + 1


static func _sum(table: Dictionary, key: String) -> int:
	var total: int = 0
	for name: Variant in table.keys():
		total += int((table[name] as Dictionary).get(key, 0))
	return total


## A stable human table for the report/probe:
##   TASK|name|status|instances|covered|blind|note
static func table_lines(coverage: Dictionary, kind: String = "tasks") -> PackedStringArray:
	var out: PackedStringArray = []
	var table: Dictionary = coverage.get(kind, {})
	var names: Array = table.keys()
	names.sort()
	for name: Variant in names:
		var row: Dictionary = table[name]
		out.append("%s|%s|%s|%d|%d|%d|%s" % [
			"TASK" if kind == "tasks" else "COND",
			str(name), str(row["status"]), int(row["instances"]),
			int(row["covered"]), int(row["blind"]), str(row["note"]),
		])
	return out


## One-line machine summary used by the probe and the test.
static func summary_line(coverage: Dictionary) -> String:
	var t: Dictionary = coverage["totals"]
	var status: Dictionary = t["by_status"]
	return "STATETREE_COVERAGE trees=%d task_classes=%d task_instances=%d task_covered=%d task_blind=%d condition_classes=%d condition_instances=%d condition_covered=%d condition_blind=%d implemented=%d mapped=%d unsupported=%d" % [
		(coverage["per_tree"] as Dictionary).size(),
		int(t["task_classes"]), int(t["task_instances"]), int(t["task_covered"]), int(t["task_blind"]),
		int(t["condition_classes"]), int(t["condition_instances"]), int(t["condition_covered"]), int(t["condition_blind"]),
		int(status.get("implemented", 0)), int(status.get("mapped-to-port", 0)), int(status.get("unsupported", 0)),
	]
