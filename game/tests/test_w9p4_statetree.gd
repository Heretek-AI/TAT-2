extends SceneTree
## W9-P4 S1 — StateTree parse, model, interpreter and coverage (suite 110).
##
## Proves, in one headless run with no guard and no map:
##   1. all 21 authored trees parse and validate (459 states / 467 transitions
##      measured from the model, compared with the payload's own `stats`);
##   2. the validator fails closed on five kinds of corruption;
##   3. the generic interpreter drives selector / task / transition-priority /
##      OnTick observer / OnEvent / transition-delay / UNKNOWN-condition paths on
##      synthetic trees (no gameplay binding);
##   4. the coverage table is measured from the payload and the guard binding,
##      and every one of the 21 trees gets a trace.
##
## Run: tools/godot --headless --path game --script res://tests/test_w9p4_statetree.gd
## Marker: W9P4_STATETREE_SUMMARY: fails=0 checks=N

const TreeModel = preload("res://src/ai/statetree/tree_model.gd")
const Interpreter = preload("res://src/ai/statetree/interpreter.gd")
const BindingsBase = preload("res://src/ai/statetree/bindings.gd")
const Trace = preload("res://src/ai/statetree/trace.gd")
const Coverage = preload("res://src/ai/statetree/coverage.gd")
const ShadowRunner = preload("res://src/ai/statetree/shadow_runner.gd")

var fails: int = 0
var checks: int = 0


func _initialize() -> void:
	await process_frame
	_check_library()
	_check_validator_fails_closed()
	_check_selector_and_task()
	_check_priority()
	_check_medium_beats_normal()
	_check_observer_tick()
	_check_event()
	_check_delay()
	_check_fallback()
	_check_ancestor_transition()
	_check_flat_join()
	_check_unknown_enter()
	_check_coverage()
	_check_all_tree_traces()
	print("W9P4_STATETREE_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(0 if fails == 0 else 1)


func _ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		fails += 1
		printerr("FAIL: ", label)


# ---------------------------------------------------------------------------
# 1-2. Payload and validator
# ---------------------------------------------------------------------------


func _check_library() -> void:
	var lib: Dictionary = TreeModel.load_library()
	var errors: Array = lib.get("errors", [])
	_ok(bool(lib.get("ok", false)), "library validates (errors=%s)" % str(errors.slice(0, 5)))
	var trees: Dictionary = lib.get("trees", {})
	_ok(trees.size() == 21, "21 trees parsed (got %d)" % trees.size())
	_ok(str(lib.get("schema", "")) == TreeModel.SCHEMA, "schema tag")
	var total_states: int = 0
	var total_transitions: int = 0
	var drift: Array = []
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		var measured: Dictionary = TreeModel.measure(tree)
		total_states += int(measured["states"])
		total_transitions += int(measured["transitions"])
		var stats: Dictionary = tree.get("stats", {})
		for key: String in ["states", "transitions", "groups", "disabled_states", "max_depth", "tasks", "task_instances", "conditions", "condition_instances"]:
			if stats.has(key) and int(stats[key]) != int(measured[key]):
				drift.append("%s.%s payload=%s model=%s" % [tree_name, key, str(stats[key]), str(measured[key])])
	_ok(total_states == 459, "459 states measured (got %d)" % total_states)
	_ok(total_transitions == 467, "467 transitions measured (got %d)" % total_transitions)
	_ok(drift.is_empty(), "model matches the payload stats (%s)" % str(drift.slice(0, 4)))
	# Entry roots.
	var entry_ok: bool = true
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		if int(tree.get("entry", -1)) < 0:
			entry_ok = false
	_ok(entry_ok, "every tree has an entry root")
	# The payload's own stats block.
	var stats: Dictionary = lib.get("stats", {})
	_ok(int(stats.get("trees", 0)) == 21, "stats.trees == 21")
	_ok(int(stats.get("states", 0)) == 459, "stats.states == 459")
	_ok(int(stats.get("transitions", 0)) == 467, "stats.transitions == 467")
	_ok(int(stats.get("tasks", 0)) == TreeModel.task_inventory(trees).size(),
		"stats.tasks == distinct task names")
	_ok(int(stats.get("conditions", 0)) == TreeModel.condition_inventory(trees).size(),
		"stats.conditions == distinct condition names")
	# Composition facts this runtime depends on.
	var linked_asset: int = 0
	var local_links: int = 0
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		for i: int in range(TreeModel.state_count(tree)):
			if TreeModel.is_linked_asset(tree, i):
				linked_asset += 1
			elif TreeModel.is_local_link(tree, i):
				local_links += 1
	_ok(linked_asset == 45, "45 LinkedAsset states (got %d)" % linked_asset)
	_ok(local_links == 2, "2 local Linked states (got %d)" % local_links)
	print("P4LIB trees=%d states=%d transitions=%d task_classes=%d condition_classes=%d linked_asset=%d local_links=%d"
		% [trees.size(), total_states, total_transitions, TreeModel.task_inventory(trees).size(),
			TreeModel.condition_inventory(trees).size(), linked_asset, local_links])


func _check_validator_fails_closed() -> void:
	var payload: Dictionary = _base_payload()
	var tree: Dictionary = payload["trees"]["SYN_SELECTOR"]
	# a) a child index out of range
	(tree["states"][0] as Dictionary)["children"] = [1, 99]
	var lib: Dictionary = TreeModel.parse_payload(payload, "<bad-child>")
	_ok(not bool(lib["ok"]), "validator rejects an out-of-range child")
	# b) a transition to a missing state
	payload = _base_payload()
	tree = payload["trees"]["SYN_SELECTOR"]
	((tree["states"][1] as Dictionary)["transitions"][0] as Dictionary)["to_state_index"] = 42
	lib = TreeModel.parse_payload(payload, "<bad-target>")
	_ok(not bool(lib["ok"]), "validator rejects a transition to a missing state")
	# c) OnEvent with no required_event
	payload = _base_payload()
	tree = payload["trees"]["SYN_SELECTOR"]
	((tree["states"][1] as Dictionary)["transitions"][0] as Dictionary)["trigger"] = "OnEvent"
	lib = TreeModel.parse_payload(payload, "<bad-event>")
	_ok(not bool(lib["ok"]), "validator rejects OnEvent with no required_event")
	# d) unknown trigger
	payload = _base_payload()
	tree = payload["trees"]["SYN_SELECTOR"]
	((tree["states"][1] as Dictionary)["transitions"][0] as Dictionary)["trigger"] = "OnNonsense"
	lib = TreeModel.parse_payload(payload, "<bad-trigger>")
	_ok(not bool(lib["ok"]), "validator rejects an unknown trigger")
	# e) a LinkedAsset to a tree that does not exist
	payload = _base_payload()
	tree = payload["trees"]["SYN_SELECTOR"]
	(tree["states"][1] as Dictionary)["type"] = "LinkedAsset"
	(tree["states"][1] as Dictionary)["linked_asset"] = "ST_DoesNotExist"
	lib = TreeModel.parse_payload(payload, "<bad-link>")
	_ok(not bool(lib["ok"]), "validator rejects an unresolvable LinkedAsset")
	# f) the clean synthetic payload still validates
	lib = TreeModel.parse_payload(_base_payload(), "<clean>")
	_ok(bool(lib["ok"]), "clean synthetic payload validates: %s" % str(lib["errors"]))


# ---------------------------------------------------------------------------
# 3. Synthetic interpreter paths
# ---------------------------------------------------------------------------


## A recording binding: counts condition/task calls and lets the test drive the
## flags. Not a game binding -- it proves the interpreter's own semantics.
class SynthBinding extends RefCounted:
	const COND_TRUE: int = 1
	const COND_FALSE: int = 0
	const COND_UNKNOWN: int = -1
	const RUNNING: int = 0
	const SUCCEEDED: int = 2
	const FAILED: int = 3

	var flags: Dictionary = {}
	var own_tick: int = 0
	var cond_calls: Dictionary = {}
	var task_ticks: Dictionary = {}
	var task_enters: Dictionary = {}

	func mutates() -> bool:
		return false

	func declaration(kind: String, name: String) -> Dictionary:
		return {"status": "implemented", "parameter_blind": false, "note": "synthetic", "kind": kind, "name": name}

	func covers(_kind: String, _name: String, _tree_name: String, _state_index: int) -> bool:
		return true

	func condition_state(name: String, _tree_name: String, _state_index: int, _transition: Dictionary) -> int:
		cond_calls[name] = int(cond_calls.get(name, 0)) + 1
		if name == "SYN_TRUE":
			return COND_TRUE
		if name == "SYN_FALSE":
			return COND_FALSE
		if name == "SYN_FLAG":
			return COND_TRUE if int(flags.get("flag", 0)) == 1 else COND_FALSE
		return COND_UNKNOWN

	func task_enter(name: String, _tree_name: String, _state_index: int) -> Dictionary:
		task_enters[name] = int(task_enters.get(name, 0)) + 1
		task_ticks[name] = 0
		return {"task": name, "status": RUNNING}

	func task_exit(_instance: Dictionary) -> void:
		pass

	func task_tick(instance: Dictionary, _delta: float) -> int:
		var name: String = str(instance.get("task", ""))
		task_ticks[name] = int(task_ticks.get(name, 0)) + 1
		if name == "SYN_TICK2":
			return SUCCEEDED if int(task_ticks[name]) >= 2 else RUNNING
		if name == "SYN_NEVER":
			return RUNNING
		return SUCCEEDED

	func event_matches(transition: Dictionary, event: Dictionary) -> int:
		return COND_TRUE if str(transition.get("required_event", "")) == str(event.get("tag", "")) else COND_FALSE

	func after_tick(_interpreter: RefCounted) -> void:
		own_tick += 1


func _run(tree_name: String, ticks: int, delta: float = 0.05, flag_at: int = -1, event_at: int = -1) -> Dictionary:
	var lib: Dictionary = TreeModel.parse_payload(_base_payload(), "<synth>")
	var binding: RefCounted = SynthBinding.new()
	var trace: RefCounted = Trace.new()
	var interp: RefCounted = Interpreter.new()
	interp.setup(lib["trees"], tree_name, binding, trace)
	var started: bool = interp.start()
	for i: int in range(ticks):
		if flag_at >= 0 and i >= flag_at:
			binding.flags["flag"] = 1
		if event_at >= 0 and i == event_at:
			interp.push_event("StateTreeEvent.Test")
		interp.tick(delta)
	return {"interp": interp, "binding": binding, "trace": trace, "started": started}


func _check_selector_and_task() -> void:
	var run: Dictionary = _run("SYN_SELECTOR", 8)
	var interp: RefCounted = run["interp"]
	var binding: RefCounted = run["binding"]
	_ok(bool(run["started"]), "selector tree starts")
	# Root selects A (child 1); A's task succeeds on the 2nd tick and its
	# OnStateCompleted transition enters B (child 2).
	var entered: Array = _kinds(run["trace"], "enter", "state")
	_ok(entered.has(1) and entered.has(2), "selector entered A then B (got %s)" % str(entered))
	_ok(entered.find(1) < entered.find(2), "A before B")
	_ok(int(binding.task_enters.get("SYN_TICK2", 0)) == 1, "A's task entered once")
	var fired: Array = interp.transitions_fired
	_ok(fired.size() >= 1 and str((fired[0] as Dictionary)["trigger"]) == "OnStateCompleted",
		"first transition is OnStateCompleted")
	_ok(int((fired[0] as Dictionary)["to_state_index"] if fired.size() > 0 else -1) == 2, "it targets B")
	# TryEnterState leaf: the tree stays in B (its OnTick needs SYN_FLAG).
	_ok(int(interp.current_state()) == 2, "after A completes the leaf is B (got %d)" % interp.current_state())


func _check_priority() -> void:
	var run: Dictionary = _run("SYN_PRIORITY", 4)
	var interp: RefCounted = run["interp"]
	_ok(bool(run["started"]), "priority tree starts")
	# Two enabled OnTick transitions are both true: Critical (to state 3) must
	# beat Normal (to state 2) whatever the authored order is.
	var fired: Array = interp.transitions_fired
	_ok(fired.size() == 1, "exactly one candidate fires (got %d)" % fired.size())
	_ok(fired.size() == 1 and int((fired[0] as Dictionary)["to_state_index"]) == 3,
		"Critical beats Normal (target=%s)" % str((fired[0] as Dictionary)["to_state_index"] if fired.size() > 0 else -1))
	_ok(fired.size() == 1 and str((fired[0] as Dictionary)["priority"]) == "Critical", "the fired transition is Critical")


## UE 5.5 enum order is None(0) < Low(1) < Normal(2) < Medium(3) < High(4) <
## Critical(5): Medium must beat Normal. The payload preserves the enum name, so
## a swapped table silently re-ranks 21 authored Medium transitions.
func _check_medium_beats_normal() -> void:
	var run: Dictionary = _run("SYN_PRIORITY2", 3)
	var interp: RefCounted = run["interp"]
	var fired: Array = interp.transitions_fired
	_ok(fired.size() == 1 and int((fired[0] as Dictionary)["to_state_index"]) == 3,
		"Medium beats Normal (target=%s)" % str((fired[0] as Dictionary)["to_state_index"] if fired.size() > 0 else -1))


func _check_observer_tick() -> void:
	var run: Dictionary = _run("SYN_SELECTOR", 12, 0.05, 5)
	var interp: RefCounted = run["interp"]
	var binding: RefCounted = run["binding"]
	_ok(int(binding.cond_calls.get("SYN_FLAG", 0)) >= 3, "OnTick condition observed while B was selected (%d)" % int(binding.cond_calls.get("SYN_FLAG", 0)))
	var entered: Array = _kinds(run["trace"], "enter", "state")
	_ok(entered.has(3), "the OnTick transition entered C (got %s)" % str(entered))
	_ok(int(interp.tree_status) == int(Interpreter.SUCCEEDED), "the Succeeded handle ended the tree (status=%d)" % int(interp.tree_status))


func _check_event() -> void:
	var run: Dictionary = _run("SYN_EVENT", 6, 0.05, -1, 2)
	var interp: RefCounted = run["interp"]
	var entered_before: Array = _kinds(run["trace"], "enter", "state")
	_ok(entered_before.has(2), "the OnEvent transition entered the event target (got %s)" % str(entered_before))
	var fired: Array = interp.transitions_fired
	_ok(fired.size() == 1 and str((fired[0] as Dictionary)["trigger"]) == "OnEvent", "the fired transition is OnEvent")
	# And the same tree without the event never leaves the first state.
	var idle: Dictionary = _run("SYN_EVENT", 6)
	_ok(int(idle["interp"].current_state()) == 1, "no event -> the state stays selected")


## `Fallback = NextSelectableSibling` (39 of 467 authored): a candidate whose
## target cannot be selected enters the next selectable sibling of the target.
## Without the fallback the same candidate is skipped and the state stays.
func _check_fallback() -> void:
	var run: Dictionary = _run("SYN_FALLBACK", 3)
	var entered: Array = _kinds(run["trace"], "enter", "state")
	_ok(not entered.has(2), "the unenterable target is not entered (got %s)" % str(entered))
	_ok(entered.has(3), "the fallback entered the target's next sibling (got %s)" % str(entered))
	var fired: Array = (run["interp"] as RefCounted).transitions_fired
	_ok(fired.size() == 1 and str((fired[0] as Dictionary).get("fallback", "")) == "NextSelectableSibling",
		"the fired transition carries the authored fallback")
	var run2: Dictionary = _run("SYN_NOFALLBACK", 3)
	var entered2: Array = _kinds(run2["trace"], "enter", "state")
	_ok(not entered2.has(2) and not entered2.has(3), "without a fallback the candidate is skipped (got %s)" % str(entered2))
	_ok(int((run2["interp"] as RefCounted).current_state()) == 1, "the state stays selected without a fallback")
	_ok(int((run2["interp"] as RefCounted).stats["unknown_transition_votes"]) == 0, "no unknown votes on a plain false")


## 71 authored transitions target an ancestor or their own state. The re-entry
## must replace the active frame, not append a duplicate (the audit's N1).
func _check_ancestor_transition() -> void:
	var run: Dictionary = _run("SYN_ANCESTOR", 4)
	var interp: RefCounted = run["interp"]
	var frames: Array = interp.frames
	_ok(frames.size() == 3, "ancestor re-entry keeps the stack depth (got %d)" % frames.size())
	var states: Array = []
	for frame: Dictionary in frames:
		states.append(int(frame.get("state", -1)))
	_ok(states == [0, 1, 2], "no duplicate frame after an ancestor transition (got %s)" % str(states))
	_ok(int(interp.transitions_fired.size()) == 4, "the ancestor transition fired once per tick (got %d)" % interp.transitions_fired.size())
	_ok(int(interp.stats["max_frames"]) == 3, "the stack never exceeded 3 frames (max %d)" % int(interp.stats["max_frames"]))


## The flat per-tree `transitions[]` join: the real payload and its failure modes.
func _check_flat_join() -> void:
	var lib: Dictionary = TreeModel.load_library()
	_ok(bool(lib.get("ok", false)), "real payload still validates with the join")
	var tree: Dictionary = lib["trees"]["ST_Patrol"]
	var by_index: Dictionary = {}
	for tr: Dictionary in tree["transitions"]:
		by_index[int(tr["index"])] = tr
	_ok(str(by_index[3].get("fallback", "")) == "NextSelectableSibling", "ST_Patrol t3 joined the authored fallback")
	_ok(is_equal_approx(float(by_index[3].get("delay_s", -1.0)), 0.0), "ST_Patrol t3 joined the authored delay")
	var total: int = 0
	var next_sibling: int = 0
	var none: int = 0
	for tree_name: Variant in lib["trees"].keys():
		for tr: Dictionary in (lib["trees"][tree_name] as Dictionary)["transitions"]:
			total += 1
			if str(tr.get("fallback", "")) == "NextSelectableSibling":
				next_sibling += 1
			elif str(tr.get("fallback", "")) == "None":
				none += 1
	_ok(total == 467 and next_sibling == 39 and none == 428,
		"join reaches all 467 transitions (39 fallback / 428 none, got %d/%d/%d)" % [total, next_sibling, none])
	# Failure modes.
	var payload: Dictionary = _base_payload()
	((payload["trees"]["SYN_SELECTOR"] as Dictionary)["transitions"] as Array).pop_back()
	_ok(not bool(TreeModel.parse_payload(payload, "<missing-flat>")["ok"]), "a missing flat record fails closed")
	payload = _base_payload()
	(((payload["trees"]["SYN_SELECTOR"] as Dictionary)["transitions"] as Array)[0] as Dictionary)["from_state_index"] = 99
	_ok(not bool(TreeModel.parse_payload(payload, "<foreign-from>")["ok"]), "a foreign from_state_index fails closed")
	payload = _base_payload()
	(((payload["trees"]["SYN_SELECTOR"] as Dictionary)["transitions"] as Array)[0] as Dictionary)["fallback"] = "Bogus"
	_ok(not bool(TreeModel.parse_payload(payload, "<bad-fallback>")["ok"]), "an unknown fallback fails closed")
	payload = _base_payload()
	var flats: Array = (payload["trees"]["SYN_SELECTOR"] as Dictionary)["transitions"]
	flats.append((flats[0] as Dictionary).duplicate(true))
	_ok(not bool(TreeModel.parse_payload(payload, "<dup-flat>")["ok"]), "a duplicate flat record fails closed")
	payload = _base_payload()
	(((payload["trees"]["SYN_SELECTOR"] as Dictionary)["transitions"] as Array)[0] as Dictionary)["to_state_index"] = 3
	_ok(not bool(TreeModel.parse_payload(payload, "<diverged>")["ok"]), "a flat/nested target divergence fails closed")


func _check_delay() -> void:
	# 0.05 s ticks; a 0.20 s delay must not fire before tick 4.
	var run: Dictionary = _run("SYN_DELAY", 3, 0.05)
	var interp: RefCounted = run["interp"]
	_ok(int(interp.current_state()) == 1, "delay transition not fired early (state=%d)" % interp.current_state())
	_ok(int(interp.transitions_fired.size()) == 0, "no transition before the delay elapses")
	run = _run("SYN_DELAY", 8, 0.05)
	interp = run["interp"]
	var fired: Array = interp.transitions_fired
	_ok(fired.size() == 1 and int((fired[0] as Dictionary)["to_state_index"]) == 2,
		"delay transition fired after 0.2 s (fired=%d)" % fired.size())


func _check_unknown_enter() -> void:
	var run: Dictionary = _run("SYN_UNKNOWN", 4)
	var interp: RefCounted = run["interp"]
	var entered: Array = _kinds(run["trace"], "enter", "state")
	_ok(not entered.has(1), "a state with an UNKNOWN enter condition is not entered")
	_ok(entered.has(2), "selection falls through to the next sibling (got %s)" % str(entered))
	_ok(int(interp.stats["unknown_enters"]) >= 1, "the unknown enter is counted")
	_ok(int(interp.stats["conditions_unknown"]) >= 1, "the unknown condition is counted")


func _kinds(trace: RefCounted, kind: String, key: String) -> Array:
	var out: Array = []
	for row: Dictionary in trace.rows:
		if str(row.get("kind", "")) == kind:
			out.append(int(row.get(key, -1)))
	return out


# ---------------------------------------------------------------------------
# 4. Coverage table and 21-tree traces
# ---------------------------------------------------------------------------


func _check_coverage() -> void:
	var coverage: Dictionary = ShadowRunner.coverage(null)
	var lib: Dictionary = TreeModel.load_library()
	var trees: Dictionary = lib["trees"]
	var tasks: Dictionary = TreeModel.task_inventory(trees)
	var conds: Dictionary = TreeModel.condition_inventory(trees)
	var totals: Dictionary = coverage["totals"]
	_ok(int(totals["task_classes"]) == tasks.size(), "coverage covers every task class")
	_ok(int(totals["condition_classes"]) == conds.size(), "coverage covers every condition class")
	_ok(int(totals["task_instances"]) == _sum_values(tasks), "coverage counts every task instance")
	_ok(int(totals["condition_instances"]) == _sum_values(conds),
		"coverage counts every condition instance (enter + transition)")
	_ok(int(totals["task_covered"]) <= int(totals["task_instances"]), "covered <= instances (tasks)")
	_ok(int(totals["condition_covered"]) <= int(totals["condition_instances"]), "covered <= instances (conditions)")
	var bad_status: Array = []
	for table: Dictionary in [coverage["tasks"], coverage["conditions"]]:
		for name: Variant in table.keys():
			var row: Dictionary = table[name]
			var status: String = str(row["status"])
			if status != "implemented" and status != "mapped-to-port" and status != "unsupported":
				bad_status.append("%s=%s" % [str(name), status])
			if str(row.get("note", "")).strip_edges() == "":
				bad_status.append("%s has no note" % str(name))
	_ok(bad_status.is_empty(), "every row has a valid status and a note (%s)" % str(bad_status.slice(0, 4)))
	# A tree is only "fully covered" if every task AND condition instance is
	# driven; the report quotes this count.
	var fully: Array = []
	for tree_name: Variant in coverage["per_tree"].keys():
		if bool((coverage["per_tree"][tree_name] as Dictionary)["fully_covered"]):
			fully.append(tree_name)
	print(Coverage.summary_line(coverage))
	print("P4COVERAGE fully_covered_trees=%d names=%s" % [fully.size(), str(fully)])
	for line: String in Coverage.table_lines(coverage, "tasks"):
		print("P4ROW ", line)
	for line: String in Coverage.table_lines(coverage, "conditions"):
		print("P4ROW ", line)


func _check_all_tree_traces() -> void:
	var result: Dictionary = ShadowRunner.trace_all_trees(4)
	var traces: Dictionary = result["traces"]
	_ok(traces.size() == 21, "structural harness produced a trace for all 21 trees (got %d)" % traces.size())
	var empty: Array = []
	for tree_name: Variant in traces.keys():
		if (traces[tree_name] as Array).is_empty():
			empty.append(tree_name)
	_ok(empty.is_empty(), "no empty trace (%s)" % str(empty))
	_ok(int(result["rows"]) > 21, "the structural harness recorded rows (%d)" % int(result["rows"]))
	# ST_Guard must reach its first task and ST_Patrol must reach the patrol loop
	# with the real guard binding, which the live mission test proves; here only
	# the structural reach (a start row per tree) is asserted.
	var started: Dictionary = result["start_rows"]
	_ok(bool(started.get("ST_Guard", false)), "ST_Guard starts")
	_ok(bool(started.get("ST_Patrol", false)), "ST_Patrol starts")
	_ok(bool(started.get("ST_Civilian", false)), "ST_Civilian starts")
	print("P4TREES started=%d blocked=%d rows=%d trees=%d" % [int(result["started"]), int(result["blocked"]), int(result["rows"]), traces.size()])


func _sum_values(table: Dictionary) -> int:
	var total: int = 0
	for key: Variant in table.keys():
		total += int(table[key])
	return total


func _transition_condition_instances(trees: Dictionary) -> int:
	var total: int = 0
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		for i: int in range(TreeModel.state_count(tree)):
			for tr: Dictionary in TreeModel.state(tree, i).get("transitions", []):
				total += (tr.get("conditions", []) as Array).size()
	return total


# ---------------------------------------------------------------------------
# Synthetic payload
# ---------------------------------------------------------------------------


func _state(index: int, name: String, parent: int, children: Array, tasks: Array = [], enter: Array = [], transitions: Array = [], selection: String = "TrySelectChildrenInOrder") -> Dictionary:
	return {
		"index": index,
		"name": name,
		"depth": 0 if parent < 0 else (1 if parent == 0 else 2),
		"type": "State",
		"parent": "Root" if parent < 0 else "",
		"parent_index": null if parent < 0 else parent,
		"children": children,
		"children_range": [0, 0],
		"tasks": tasks,
		"enter_conditions": enter,
		"utility_considerations": [],
		"transitions": transitions,
		"linked_asset": null,
		"linked_state_index": null,
		"enabled": true,
		"selection_behavior": selection,
	}


func _tr(index: int, to_state: int, trigger: String, conditions: Array = [], priority: String = "None", event: String = "", to_kind: String = "state", to_index: int = -1, delay: float = 0.0, fallback: String = "None") -> Dictionary:
	return {
		"index": index,
		"to_state": "state_%d" % to_state if to_kind == "state" else null,
		"to_state_index": to_index if to_kind != "state" else to_state,
		"to_kind": to_kind,
		"trigger": trigger,
		"priority": priority,
		"required_event": event,
		"conditions": conditions,
		"delay": {"duration": delay, "RandomVariance": 0},
		"fallback": fallback,
		"enabled": true,
	}


## The per-tree flat transition array the real payload carries (14 keys). The
## model joins it onto the per-state copies; building it here means the tests
## exercise the same shape the producer emits.
func _flat_transitions(tree: Dictionary) -> Array:
	var out: Array = []
	for state: Dictionary in tree["states"]:
		for tr: Dictionary in state["transitions"]:
			out.append({
				"index": tr["index"],
				"from_state": state["name"],
				"from_state_index": state["index"],
				"to_state": tr["to_state"],
				"to_state_index": tr["to_state_index"],
				"to_kind": tr["to_kind"],
				"trigger": tr["trigger"],
				"priority": tr["priority"],
				"required_event": tr["required_event"],
				"conditions": tr["conditions"],
				"enabled": tr["enabled"],
				"delay_seconds": float((tr.get("delay", {}) as Dictionary).get("duration", 0.0)),
				"delay_random_variance": 0.0,
				"fallback": str(tr.get("fallback", "None")),
			})
	return out


func _base_payload() -> Dictionary:
	var trees: Dictionary = {}
	trees["SYN_SELECTOR"] = {
		"name": "SYN_SELECTOR", "package": "<synthetic>", "asset": "/Synth/SELECTOR",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1, 2], [], [], []),
			_state(1, "A", 0, [], ["SYN_TICK2"], ["SYN_TRUE"],
				[_tr(0, 2, "OnStateCompleted")]),
			_state(2, "B", 0, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(1, 3, "OnTick", ["SYN_FLAG"]), _tr(2, 4, "OnEvent", [], "Normal", "StateTreeEvent.Test")]),
			_state(3, "C", 0, [], ["SYN_DONE"], ["SYN_TRUE"],
				[_tr(3, -1, "OnStateCompleted", [], "None", "", "Succeeded", 65534)]),
			_state(4, "D", 0, [], ["SYN_DONE"], ["SYN_TRUE"],
				[_tr(4, 0, "OnStateCompleted")]),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	trees["SYN_PRIORITY"] = {
		"name": "SYN_PRIORITY", "package": "<synthetic>", "asset": "/Synth/PRIORITY",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1], [], [], []),
			_state(1, "P", 0, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(0, 2, "OnTick", ["SYN_TRUE"], "Normal"), _tr(1, 3, "OnTick", ["SYN_TRUE"], "Critical")]),
			_state(2, "Low", 0, [], ["SYN_DONE"], ["SYN_TRUE"], []),
			_state(3, "High", 0, [], ["SYN_DONE"], ["SYN_TRUE"], []),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	trees["SYN_PRIORITY2"] = {
		"name": "SYN_PRIORITY2", "package": "<synthetic>", "asset": "/Synth/PRIORITY2",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1], [], [], []),
			_state(1, "P2", 0, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(0, 2, "OnTick", ["SYN_TRUE"], "Normal"), _tr(1, 3, "OnTick", ["SYN_TRUE"], "Medium")]),
			_state(2, "N", 0, [], ["SYN_DONE"], ["SYN_TRUE"], []),
			_state(3, "M", 0, [], ["SYN_DONE"], ["SYN_TRUE"], []),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	trees["SYN_FALLBACK"] = {
		"name": "SYN_FALLBACK", "package": "<synthetic>", "asset": "/Synth/FALLBACK",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1, 2, 3], [], [], []),
			_state(1, "A", 0, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(0, 2, "OnTick", ["SYN_TRUE"], "None", "", "state", -1, 0.0, "NextSelectableSibling")]),
			_state(2, "X", 0, [], ["SYN_DONE"], ["SYN_FALSE"], []),
			_state(3, "Y", 0, [], ["SYN_DONE"], ["SYN_TRUE"], []),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	trees["SYN_NOFALLBACK"] = {
		"name": "SYN_NOFALLBACK", "package": "<synthetic>", "asset": "/Synth/NOFALLBACK",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1, 2, 3], [], [], []),
			_state(1, "A", 0, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(0, 2, "OnTick", ["SYN_TRUE"], "None", "", "state", -1, 0.0, "None")]),
			_state(2, "X", 0, [], ["SYN_DONE"], ["SYN_FALSE"], []),
			_state(3, "Y", 0, [], ["SYN_DONE"], ["SYN_TRUE"], []),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	trees["SYN_ANCESTOR"] = {
		"name": "SYN_ANCESTOR", "package": "<synthetic>", "asset": "/Synth/ANCESTOR",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1], [], [], []),
			_state(1, "A", 0, [2], [], ["SYN_TRUE"], []),
			_state(2, "B", 1, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(0, 1, "OnTick", ["SYN_TRUE"], "Normal")]),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	trees["SYN_EVENT"] = {
		"name": "SYN_EVENT", "package": "<synthetic>", "asset": "/Synth/EVENT",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1], [], [], []),
			_state(1, "E", 0, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(0, 2, "OnEvent", [], "Normal", "StateTreeEvent.Test")]),
			_state(2, "F", 0, [], ["SYN_DONE"], ["SYN_TRUE"], []),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	trees["SYN_DELAY"] = {
		"name": "SYN_DELAY", "package": "<synthetic>", "asset": "/Synth/DELAY",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1], [], [], []),
			_state(1, "G", 0, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(0, 2, "OnTick", ["SYN_TRUE"], "None", "", "state", -1, 0.2)]),
			_state(2, "H", 0, [], ["SYN_DONE"], ["SYN_TRUE"], []),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	trees["SYN_UNKNOWN"] = {
		"name": "SYN_UNKNOWN", "package": "<synthetic>", "asset": "/Synth/UNKNOWN",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1, 2], [], [], []),
			_state(1, "X", 0, [], ["SYN_DONE"], ["SYN_UNKNOWN_COND"], []),
			_state(2, "Y", 0, [], ["SYN_DONE"], ["SYN_TRUE"],
				[_tr(0, -1, "OnStateCompleted", [], "None", "", "Succeeded", 65534)]),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	for tree: Variant in trees.keys():
		(trees[tree] as Dictionary)["transitions"] = _flat_transitions(trees[tree])
	return {
		"schema": TreeModel.SCHEMA,
		"game_version": "synthetic",
		"source": {"state_trees": "<synthetic>"},
		"units": {},
		"roots": ["SYN_SELECTOR"],
		"stats": {},
		"trees": trees,
		"condition_classes": [],
		"task_blueprints": [],
		"targeting_considerations": [],
		"other_blueprints": [],
	}
