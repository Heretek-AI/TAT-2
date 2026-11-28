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
const GuardBindings = preload("res://src/ai/statetree/guard_bindings.gd")

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
	_check_node_model()
	_check_binding_precedence()
	_check_event_gates()
	_check_guard_bag()
	_check_literal_delay()
	_check_coverage()
	_check_vacuous_and_events()
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
		for key: String in ["states", "transitions", "groups", "disabled_states", "max_depth", "tasks", "task_instances", "conditions", "condition_instances",
				"nodes", "nodes_referenced", "nodes_unreferenced", "nodes_with_parameters", "object_templates",
				"inherited_templates", "bound_bindings", "required_event_states", "consume_event_false_states",
				"consume_event_false_transitions"]:
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
## B2.1 signature: conditions/tasks receive the NODE and a ctx dictionary.
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
	var cond_keys: Array = []
	var task_ticks: Dictionary = {}
	var task_enters: Dictionary = {}
	var task_nodes: Array = []

	func mutates() -> bool:
		return false

	func declaration(kind: String, name: String) -> Dictionary:
		return {"status": "implemented", "parameter_blind": false, "note": "synthetic", "kind": kind, "name": name}

	func covers(_kind: String, _name: String, _tree_name: String, _state_index: int, _node: Dictionary = {}) -> bool:
		return true

	func state_bags(_tree_name: String, _state_index: int) -> Dictionary:
		return {}

	func condition_state(node: Dictionary, ctx: Dictionary) -> int:
		var name: String = str(node.get("name", ""))
		cond_calls[name] = int(cond_calls.get(name, 0)) + 1
		cond_keys.append(str(node.get("key", "")))
		# Prove the interpreter passes node identity + ctx, not just a name.
		if not ctx.has("frames") or str(ctx.get("tree", "")) == "":
			return COND_UNKNOWN
		if name == "SYN_TRUE":
			return COND_TRUE
		if name == "SYN_FALSE":
			return COND_FALSE
		if name == "SYN_FLAG":
			return COND_TRUE if int(flags.get("flag", 0)) == 1 else COND_FALSE
		return COND_UNKNOWN

	func task_enter(node: Dictionary, ctx: Dictionary) -> Dictionary:
		var name: String = str(node.get("name", ""))
		task_enters[name] = int(task_enters.get(name, 0)) + 1
		task_ticks[name] = 0
		task_nodes.append(node)
		return {"task": name, "node": node, "tree": str(ctx.get("tree", "")), "status": RUNNING}

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


func _run(tree_name: String, ticks: int, delta: float = 0.05, flag_at: int = -1, event_at: int = -1, event_tag: String = "StateTreeEvent.Test") -> Dictionary:
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
			interp.push_event(event_tag)
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


# ---------------------------------------------------------------------------
# 3b. B2.1 node model and binding precedence
# ---------------------------------------------------------------------------


## 566/566 node keys, the four exposed node arrays, and the five worked
## bindings (T01 contract §5). Every number here is measured from the payload.
func _check_node_model() -> void:
	var lib: Dictionary = TreeModel.load_library()
	var trees: Dictionary = lib["trees"]
	var total_nodes: int = 0
	var total_referenced: int = 0
	var total_unreferenced: int = 0
	var with_parameters: int = 0
	var object_templates: int = 0
	var inherited: int = 0
	var bindings: int = 0
	var gated: int = 0
	var consume_false_states: int = 0
	var consume_false_transitions: int = 0
	var duplicate_keys: int = 0
	var lockstep: bool = true
	var sources_agree: bool = true
	var all_keys: Dictionary = {}
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		var measured: Dictionary = TreeModel.measure(tree)
		total_nodes += int(measured["nodes"])
		total_referenced += int(measured["nodes_referenced"])
		total_unreferenced += int(measured["nodes_unreferenced"])
		with_parameters += int(measured["nodes_with_parameters"])
		object_templates += int(measured["object_templates"])
		inherited += int(measured["inherited_templates"])
		bindings += int(measured["bound_bindings"])
		gated += int(measured["required_event_states"])
		consume_false_states += int(measured["consume_event_false_states"])
		consume_false_transitions += int(measured["consume_event_false_transitions"])
		duplicate_keys += int(measured["nodes_duplicate_keys"])
		for key: String in TreeModel.node_keys(tree):
			all_keys[key] = true
		var payload_stats: Dictionary = tree.get("stats", {})
		if payload_stats.has("binding_sources"):
			# JSON numbers arrive as floats; compare the counts numerically.
			var want: Dictionary = payload_stats["binding_sources"]
			var got: Dictionary = measured["binding_sources"]
			if want.size() != got.size():
				sources_agree = false
			for source_key: Variant in want.keys():
				if int(got.get(str(source_key), -1)) != int(want[source_key]):
					sources_agree = false
		for i: int in range(TreeModel.state_count(tree)):
			var state: Dictionary = TreeModel.state(tree, i)
			if (state["task_nodes"] as Array).size() != (state["tasks"] as Array).size():
				lockstep = false
			if (state["enter_condition_nodes"] as Array).size() != (state["enter_conditions"] as Array).size():
				lockstep = false
			if (state["utility_nodes"] as Array).size() != (state["utility"] as Array).size():
				lockstep = false
			var condition_nodes: int = (state["enter_condition_nodes"] as Array).size()
			var condition_names: int = (state["enter_conditions"] as Array).size()
			for tr: Dictionary in state.get("transitions", []):
				condition_nodes += (tr["condition_nodes"] as Array).size()
				condition_names += (tr["conditions"] as Array).size()
			if condition_nodes != (state["condition_nodes"] as Array).size() or condition_names != (state["condition_nodes"] as Array).size():
				lockstep = false
	_ok(total_nodes == 566, "566 node keys measured (got %d)" % total_nodes)
	_ok(total_referenced == 559, "559 referenced nodes (got %d)" % total_referenced)
	_ok(total_unreferenced == 7, "7 unreferenced nodes (got %d)" % total_unreferenced)
	_ok(all_keys.size() == 566, "566 distinct node identity keys (got %d)" % all_keys.size())
	_ok(duplicate_keys == 0, "no duplicate node keys (got %d)" % duplicate_keys)
	_ok(with_parameters == 497, "497 nodes carry parameters (got %d)" % with_parameters)
	_ok(object_templates == 139, "139 Blueprint object templates (got %d)" % object_templates)
	_ok(inherited == 65, "65 inherited class-default templates (got %d)" % inherited)
	_ok(bindings == 676, "676 bound bindings (got %d)" % bindings)
	_ok(gated == 3, "3 required_event_to_enter states (got %d)" % gated)
	_ok(consume_false_states == 2, "2 consume_event_on_select=false states (got %d)" % consume_false_states)
	_ok(consume_false_transitions == 5, "5 consume_event_on_select=false transitions (got %d)" % consume_false_transitions)
	_ok(lockstep, "node arrays and legacy name arrays are in lockstep")
	_ok(sources_agree, "per-tree binding_sources match the payload stats")
	# The modelled gate records carry the authored tag and payload struct.
	var patrol: Dictionary = trees["ST_Patrol"]
	var gate: Dictionary = TreeModel.state(patrol, 21).get("required_event_to_enter", {})
	_ok(str(gate.get("tag", "")) == "StateTreeEvent.DistractionEvent", "ST_Patrol[21] requires DistractionEvent (got %s)" % str(gate.get("tag", "")))
	_ok(str(gate.get("payload_struct", "")) == "TATAITargetingEvent_DistractionEvent", "ST_Patrol[21] payload struct")
	_ok(not bool(TreeModel.state(patrol, 21).get("consume_event_on_select", true)), "ST_Patrol[21] does not consume on select")
	var into_distraction: Dictionary = TreeModel.state(patrol, 3).get("transitions", [])[1]
	_ok(int(into_distraction.get("index", -1)) == 2 and str(into_distraction.get("trigger", "")) == "OnEvent", "ST_Patrol[3] transition 2 is the DistractionEvent OnEvent transition")
	_ok(not bool(into_distraction.get("consume_event_on_select", true)), "ST_Patrol[3] t2 also keeps the event (authored false)")
	# Node identity is the class, not the display name.
	var patrol_type_node: Dictionary = _enter_node(patrol, 11, "Patrol Point Is Of Type")
	_ok(str(patrol_type_node.get("class", "")) == "STC_PatrolPathPointIsOfType_C",
		"class identity for ST_Patrol[11] (got '%s')" % str(patrol_type_node.get("class", "")))
	_ok(str((patrol_type_node.get("parameters", {}) as Dictionary).get("PatrolPathType", "")) == "EPatrolPointType::SmartObjectInteraction",
		"ST_Patrol[11] authored PatrolPathType")
	var inherited_node: Dictionary = _enter_node(patrol, 13, "Patrol Point Is Of Type")
	_ok(bool(inherited_node.get("inherited", false)), "ST_Patrol[13] template is inherited")
	_ok((inherited_node.get("parameters", {}) as Dictionary).is_empty(), "ST_Patrol[13] has no overrides")
	print("P4NODES nodes=%d referenced=%d unreferenced=%d keys=%d parameters=%d objects=%d inherited=%d bindings=%d gated=%d consume_false_states=%d consume_false_transitions=%d"
		% [total_nodes, total_referenced, total_unreferenced, all_keys.size(), with_parameters,
			object_templates, inherited, bindings, gated, consume_false_states, consume_false_transitions])


func _task_node(tree: Dictionary, state_index: int, name: String) -> Dictionary:
	for node: Dictionary in TreeModel.state(tree, state_index).get("task_nodes", []):
		if str(node.get("name", "")) == name:
			return node
	return {}


func _enter_node(tree: Dictionary, state_index: int, name: String) -> Dictionary:
	for node: Dictionary in TreeModel.state(tree, state_index).get("enter_condition_nodes", []):
		if str(node.get("name", "")) == name:
			return node
	return {}


## The five T01 worked bindings, proved through `resolve()`:
##   ST_Patrol[17] Duration uses PatrolPointData.WaitSeconds, never the 1.0
##   template; ST_Patrol[19] is the 100.0 literal; Bool Compare.bLeft is
##   UNKNOWN (ResetAlertness); Move To.Destination is bound;
##   Setup Patrol's outputs are RefAccessIndex slots, not values.
func _check_binding_precedence() -> void:
	var lib: Dictionary = TreeModel.load_library()
	var patrol: Dictionary = lib["trees"]["ST_Patrol"]
	var base: RefCounted = BindingsBase.new()
	var ctx: Dictionary = {"tree": "ST_Patrol", "state": 17, "transition": {}, "tick": 0, "time": 0.0, "frames": []}
	var delay: Dictionary = _task_node(patrol, 17, "Delay Task")
	_ok(not delay.is_empty(), "ST_Patrol[17] Delay Task node exists")
	var duration: Dictionary = base.resolve(delay, "Duration", ctx)
	_ok(bool(duration["template_present"]), "Duration template is present")
	_ok(duration["template"] is float and is_equal_approx(float(duration["template"]), 1.0),
		"the template value is the 1.0 s default (got %s)" % str(duration["template"]))
	_ok(str(duration["value"]) == BindingsBase.VALUE_UNKNOWN, "a bound Duration with no bag resolves UNKNOWN (got %s)" % str(duration["value"]))
	_ok(str(duration["source"]) == BindingsBase.SOURCE_BOUND_UNKNOWN, "source is bound-unknown (got %s)" % str(duration["source"]))
	_ok(str(duration["path"]) == str(["PatrolPointData", "WaitSeconds"]), "the bound path is PatrolPointData.WaitSeconds (got %s)" % str(duration["path"]))
	_ok(BindingsBase.param_source(delay) == "bound-authored-record", "Delay Task param_source is the authored patrol record")
	# The case difference is real: `parameters.duration` vs `bound.Duration`.
	_ok((delay["parameters"] as Dictionary).has("duration") and not (delay["parameters"] as Dictionary).has("Duration"),
		"Delay Task template key is lowercase 'duration'")
	var duration_lower: Dictionary = base.resolve(delay, "duration", ctx)
	_ok(str(duration_lower["source"]) == BindingsBase.SOURCE_BOUND_UNKNOWN,
		"the bound map matches the lowercase template key case-insensitively (source %s)" % str(duration_lower["source"]))
	# With the authored record in a frame bag, the bound value wins over 1.0.
	var frames: Array = [{
		"tree": "ST_Patrol", "state": 3,
		"bags": {"StateParameterData": {"3": {"PatrolPointData": {
			"WaitSeconds": {"value": 10.0, "source": BindingsBase.SOURCE_AUTHORED_RECORD},
		}}}},
	}]
	var ctx_bag: Dictionary = {"tree": "ST_Patrol", "state": 17, "transition": {}, "tick": 0, "time": 0.0, "frames": frames}
	var authored: Dictionary = base.resolve(delay, "Duration", ctx_bag)
	_ok(is_equal_approx(float(authored["value"]), 10.0), "the bag's WaitSeconds wins (got %s)" % str(authored["value"]))
	_ok(str(authored["source"]) == BindingsBase.SOURCE_AUTHORED_RECORD, "source is bound-authored-record (got %s)" % str(authored["source"]))
	# A bag that lacks WaitSeconds still must not fall back to 1.0.
	var empty_frames: Array = [{"tree": "ST_Patrol", "state": 3, "bags": {"StateParameterData": {"3": {"PatrolPointData": {}}}}}]
	var ctx_empty: Dictionary = {"tree": "ST_Patrol", "state": 17, "transition": {}, "tick": 0, "time": 0.0, "frames": empty_frames}
	var missing: Dictionary = base.resolve(delay, "Duration", ctx_empty)
	_ok(str(missing["value"]) == BindingsBase.VALUE_UNKNOWN,
		"a missing bag value stays UNKNOWN, never the 1.0 template (got %s)" % str(missing["value"]))
	# The 100.0 literal.
	var failed: Dictionary = _task_node(patrol, 19, "Delay Task")
	var literal: Dictionary = base.resolve(failed, "Duration", ctx)
	_ok(str(literal["source"]) == BindingsBase.SOURCE_LITERAL, "ST_Patrol[19] Duration is a literal (got %s)" % str(literal["source"]))
	_ok(is_equal_approx(float(literal["value"]), 100.0), "ST_Patrol[19] Duration is 100.0 (got %s)" % str(literal["value"]))
	_ok((failed["bound"] as Dictionary).is_empty(), "ST_Patrol[19] has no bindings")
	# Bool Compare.bLeft <- ResetAlertness is UNKNOWN; bRight is authored.
	var compare: Dictionary = _enter_node(patrol, 1, "Bool Compare")
	var left: Dictionary = base.resolve(compare, "bLeft", ctx)
	var right: Dictionary = base.resolve(compare, "bRight", ctx)
	_ok(str(left["value"]) == BindingsBase.VALUE_UNKNOWN, "Bool Compare.bLeft is UNKNOWN (got %s)" % str(left["value"]))
	_ok(str(left["source"]) == BindingsBase.SOURCE_BOUND_UNKNOWN, "bLeft source is bound-unknown")
	_ok(str(left["path"]) == str(["ResetAlertness"]), "bLeft is GlobalParameterData.ResetAlertness (got %s)" % str(left["path"]))
	_ok(left["template"] is bool and bool(left["template"]) == false, "bLeft has a false template that is NOT used")
	_ok(right["value"] is bool and bool(right["value"]) == true, "bRight is the authored true")
	# Move To.Destination is bound to CurrentPatrolWorldLocation.
	var move: Dictionary = _task_node(patrol, 14, "Move To")
	var destination: Dictionary = base.resolve(move, "Destination", ctx)
	_ok(str(destination["source"]) == BindingsBase.SOURCE_BOUND_UNKNOWN or str(destination["source"]) == BindingsBase.SOURCE_AUTHORED_RECORD,
		"Move To.Destination is bound (source %s)" % str(destination["source"]))
	_ok(str(destination["path"]) == str(["CurrentPatrolWorldLocation"]), "Destination is CurrentPatrolWorldLocation (got %s)" % str(destination["path"]))
	_ok(destination["template"] is Dictionary, "Destination has a zero-vector template that is NOT used")
	# Setup Patrol outputs are RefAccessIndex slots, not values.
	var setup: Dictionary = _task_node(patrol, 4, "TATState Tree Task Setup Patrol")
	_ok(setup["ref_access"] == ["PatrolBrokenLocation", "PatrolData", "PatrolWasInterrupted", "PatrolWorldLocation"],
		"Setup Patrol exposes four RefAccessIndex outputs (got %s)" % str(setup["ref_access"]))
	var patrol_data: Dictionary = base.resolve(setup, "PatrolData", ctx)
	_ok(str(patrol_data["source"]) == BindingsBase.SOURCE_REF_ACCESS, "PatrolData is ref-access (got %s)" % str(patrol_data["source"]))
	_ok(str(patrol_data["value"]) == BindingsBase.VALUE_UNKNOWN, "PatrolData is not a value (got %s)" % str(patrol_data["value"]))
	# The four worked-example values in one line for the report.
	print("P4BIND delay_template=%s delay_bound=%s delay_bag=%s failed_literal=%s bLeft=%s bRight=%s destination=%s patrol_data=%s"
		% [str(duration["template"]), str(duration["value"]), str(authored["value"]),
			str(literal["value"]), str(left["value"]), str(right["value"]),
			str(destination["source"]), str(patrol_data["source"])])


## `required_event_to_enter` / `consume_event_on_select`, driven by synthetic
## events only: no live event bus is claimed.
func _check_event_gates() -> void:
	# a) A gated sibling is refused at selection time; the plain sibling runs.
	var blocked: Dictionary = _run("SYN_GATE_BLOCK", 2)
	var blocked_interp: RefCounted = blocked["interp"]
	var blocked_enters: Array = _kinds(blocked["trace"], "enter", "state")
	_ok(bool(blocked["started"]), "a tree whose first child is gated still starts")
	_ok(not blocked_enters.has(1), "the gated state is not entered without an event (got %s)" % str(blocked_enters))
	_ok(blocked_enters.has(2), "selection falls through to the plain sibling (got %s)" % str(blocked_enters))
	_ok(int(blocked_interp.stats["event_gate_blocked"]) >= 1, "the blocked gate is counted")
	# b) A live event opens the gate; transition + state consume it once.
	var opened: Dictionary = _run("SYN_GATE_EVENT", 1, 0.05, -1, 0, "StateTreeEvent.Gate")
	var opened_interp: RefCounted = opened["interp"]
	_ok(int(opened_interp.current_state()) >= 0, "the gated tree starts")
	var opened_enters: Array = _kinds(opened["trace"], "enter", "state")
	_ok(opened_enters.has(2), "the event enters the gated state (got %s)" % str(opened_enters))
	_ok(int(opened_interp.stats["event_gate_enters"]) == 1, "one gated enter (got %d)" % int(opened_interp.stats["event_gate_enters"]))
	_ok(int(opened_interp.stats["events_consumed"]) == 1, "the event is consumed once (got %d)" % int(opened_interp.stats["events_consumed"]))
	_ok((opened_interp.tick_events as Array).is_empty(), "the consumed event is gone")
	# c) consume_event_on_select=false on both transition and state keeps it.
	var kept: Dictionary = _run("SYN_GATE_KEEP", 1, 0.05, -1, 0, "StateTreeEvent.Gate")
	var kept_interp: RefCounted = kept["interp"]
	_ok(int(kept_interp.stats["events_consumed"]) == 0, "a kept event is not consumed (got %d)" % int(kept_interp.stats["events_consumed"]))
	_ok(int(kept_interp.stats["events_kept"]) == 2, "the transition and the state each keep the event (got %d)" % int(kept_interp.stats["events_kept"]))
	_ok((kept_interp.tick_events as Array).size() == 1, "the kept event is still live for the tick")
	_ok((_kinds(kept["trace"], "enter", "state") as Array).has(2), "the kept event still entered the gated state")
	# d) A gated parent with a gated child: the child selects before the parent
	# consumes (port decision 3), so both enter and the event is consumed once.
	var nested: Dictionary = _run("SYN_GATE_NESTED", 1, 0.05, -1, 0, "StateTreeEvent.Gate")
	var nested_interp: RefCounted = nested["interp"]
	var nested_enters: Array = _kinds(nested["trace"], "enter", "state")
	_ok(nested_enters.has(2) and nested_enters.has(3), "both gated states enter (got %s)" % str(nested_enters))
	_ok(int(nested_interp.stats["event_gate_enters"]) == 2, "two gated enters (got %d)" % int(nested_interp.stats["event_gate_enters"]))
	_ok(int(nested_interp.stats["events_consumed"]) == 1, "the event is consumed once after the subtree (got %d)" % int(nested_interp.stats["events_consumed"]))
	_ok((nested_interp.tick_events as Array).is_empty(), "the event is gone after the subtree selected")
	# e) A wrong tag never opens the gate.
	var wrong: Dictionary = _run("SYN_GATE_EVENT", 2, 0.05, -1, 0, "StateTreeEvent.Other")
	_ok(int((wrong["interp"] as RefCounted).current_state()) == 1, "a different event tag does not open the gate")
	print("P4GATES blocked=%d gate_enters=%d consumed=%d kept=%d nested_enters=%d"
		% [int(blocked_interp.stats["event_gate_blocked"]), int(opened_interp.stats["event_gate_enters"]),
			int(opened_interp.stats["events_consumed"]), int(kept_interp.stats["events_kept"]),
			int(nested_interp.stats["event_gate_enters"])])


## The generic base `Delay Task` driver: an authored literal duration is fully
## drivable with no game binding. This is what makes
## ST_Subtree_IntruderNoLongerSuspicious structurally covered.
class LiteralDelayBinding extends "res://src/ai/statetree/bindings.gd":
	func condition_state(_node: Dictionary, _ctx: Dictionary) -> int:
		return COND_TRUE


## A minimal stand-in for `guard_ai.gd`: only the fields `GuardBindings.observe`
## reads, so the bag test needs no world, no physics and no autoload.
class FakeGuard extends Node3D:
	var patrol_points: Array = []
	var patrol_waits: Array = []
	var patrol_yaws: Array = []
	var patrol_facing: Array = []
	var patrol_types: Array = []
	var patrol_wait_deviations: Array = []
	var wp_index: int = 0
	var state: int = 0
	var detection: float = 0.0
	var health: float = 100.0

	func patrol_wait_remaining() -> float:
		return 0.0


## `PatrolPointData` comes from the AUTHORED patrol record: the real ST_Patrol[17]
## Delay Task resolves the record's WaitSeconds (10.0) through the frame bag, and
## a synthetic fallback record resolves UNKNOWN instead of the 1.0 template.
func _check_guard_bag() -> void:
	var lib: Dictionary = TreeModel.load_library()
	var trees: Dictionary = lib["trees"]
	var patrol: Dictionary = trees["ST_Patrol"]
	var guard: Node3D = FakeGuard.new()
	var points: Array = [Vector3(1, 0, 1), Vector3(5, 0, 2)]
	guard.set("patrol_points", points)
	guard.set("patrol_waits", [0.0, 10.0])
	guard.set("patrol_yaws", [0.0, 90.0])
	guard.set("patrol_facing", [false, true])
	guard.set("patrol_types", ["EPatrolPointType::PatrolToLocation", "EPatrolPointType::PatrolToLocation"])
	guard.set("patrol_wait_deviations", [0.0, 2.0])
	guard.set("wp_index", 1)
	var bindings: RefCounted = GuardBindings.new()
	bindings.setup(guard, trees)
	bindings.observe(0.05)
	var bags: Dictionary = bindings.state_bags("ST_Patrol", 3)
	_ok((bags.get("StateParameterData", {}) as Dictionary).has("3"),
		"the Patrol state bag fills the payload's slot 3")
	var slot: Dictionary = (bags["StateParameterData"] as Dictionary)["3"]
	var point: Dictionary = slot.get("PatrolPointData", {})
	_ok(is_equal_approx(float((point.get("WaitSeconds", {}) as Dictionary).get("value", -1.0)), 10.0),
		"WaitSeconds comes from the authored record (got %s)" % str((point.get("WaitSeconds", {}) as Dictionary).get("value")))
	_ok(is_equal_approx(float((point.get("WaitDeviation", {}) as Dictionary).get("value", -1.0)), 2.0),
		"WaitDeviation comes from the authored record (got %s)" % str((point.get("WaitDeviation", {}) as Dictionary).get("value")))
	_ok(str((point.get("HasFacing", {}) as Dictionary).get("value", "")) == "true", "HasFacing is the authored true")
	_ok(str((point.get("PatrolPointType", {}) as Dictionary).get("value", "")) == "EPatrolPointType::PatrolToLocation",
		"PatrolPointType comes from the authored record")
	_ok(str((point.get("SmartObjectComponent", {}) as Dictionary).get("source", "")) == BindingsBase.SOURCE_BOUND_UNKNOWN,
		"SmartObjectComponent stays UNKNOWN (no smart-object system)")
	_ok(str((slot.get("PatrolData", {}) as Dictionary).get("source", "")) == BindingsBase.SOURCE_REF_ACCESS,
		"Setup Patrol's PatrolData stays a RefAccessIndex slot")
	_ok((slot.get("CurrentPatrolWorldLocation", {}) as Dictionary).get("value") == points[1],
		"CurrentPatrolWorldLocation is the authored point")
	# The real Delay Task resolves through that bag.
	var delay: Dictionary = _task_node(patrol, 17, "Delay Task")
	var frames: Array = [{"tree": "ST_Patrol", "state": 3, "bags": bags}]
	var ctx: Dictionary = {"tree": "ST_Patrol", "state": 17, "transition": {}, "tick": 0, "time": 0.0, "frames": frames}
	var duration: Dictionary = bindings.resolve(delay, "Duration", ctx)
	_ok(is_equal_approx(float(duration["value"]), 10.0), "ST_Patrol[17] resolves WaitSeconds through the bag (got %s)" % str(duration["value"]))
	_ok(str(duration["source"]) == BindingsBase.SOURCE_AUTHORED_RECORD, "the bag source is bound-authored-record")
	_ok(bool(bindings.covers("task", "Delay Task", "ST_Patrol", 17, delay)), "the bound ST_Patrol Delay Task is covered")
	_ok(not bool(bindings.covers("task", "Delay Task", "ST_Guard", 68, _task_node(trees["ST_Guard"], 68, "Delay Task"))),
		"a Delay Task bound to a GlobalParameterData bag is not covered")
	# A synthetic 6x6 m fallback has patrol_points but no waits: the record fields
	# are UNKNOWN, not invented zeroes.
	var fallback: Node3D = FakeGuard.new()
	fallback.set("patrol_points", [Vector3(0, 0, 0), Vector3(1, 0, 0)])
	fallback.set("wp_index", 0)
	var fallback_bindings: RefCounted = GuardBindings.new()
	fallback_bindings.setup(fallback, trees)
	fallback_bindings.observe(0.05)
	var fallback_bags: Dictionary = fallback_bindings.state_bags("ST_Patrol", 3)
	var fallback_slot: Dictionary = (fallback_bags["StateParameterData"] as Dictionary)["3"]
	var fallback_point: Dictionary = fallback_slot.get("PatrolPointData", {})
	_ok(str((fallback_point.get("WaitSeconds", {}) as Dictionary).get("value", "")) == BindingsBase.VALUE_UNKNOWN,
		"the synthetic fallback leaves WaitSeconds UNKNOWN")
	_ok(str((fallback_point.get("WaitSeconds", {}) as Dictionary).get("source", "")) == BindingsBase.SOURCE_PORT_FALLBACK,
		"the synthetic fallback is labelled port-fallback")
	print("P4BAG wait_s=%s wait_dev=%s facing=%s type=%s position_source=%s fallback_wait=%s"
		% [str((point.get("WaitSeconds", {}) as Dictionary).get("value")),
			str((point.get("WaitDeviation", {}) as Dictionary).get("value")),
			str((point.get("HasFacing", {}) as Dictionary).get("value")),
			str((point.get("PatrolPointType", {}) as Dictionary).get("value")),
			str((slot.get("CurrentPatrolWorldLocation", {}) as Dictionary).get("source")),
			str((fallback_point.get("WaitSeconds", {}) as Dictionary).get("value"))])


func _check_literal_delay() -> void:
	var lib: Dictionary = TreeModel.parse_payload(_base_payload(), "<delay-literal>")
	var binding: RefCounted = LiteralDelayBinding.new()
	var trace: RefCounted = Trace.new()
	var interp: RefCounted = Interpreter.new()
	interp.setup(lib["trees"], "SYN_DELAY_LITERAL", binding, trace)
	_ok(interp.start(), "the literal-delay tree starts")
	# 0.05 s ticks: 0.15 s < 0.20 s, so the task must still be RUNNING at tick 3.
	for _i: int in range(3):
		interp.tick(0.05)
	_ok(int(interp.current_state()) == 1, "the 0.20 s literal delay has not completed at 0.15 s (state %d)" % int(interp.current_state()))
	for _i: int in range(3):
		interp.tick(0.05)
	var entered: Array = _kinds(trace, "enter", "state")
	_ok(entered.has(2), "the literal delay completed into state 2 (got %s)" % str(entered))
	var declares: Dictionary = binding.declaration("task", "Delay Task")
	_ok(str(declares["status"]) == "implemented", "the base declares Delay Task implemented")
	print("P4DELAYLITERAL duration=0.20 completed=%s enters=%s" % [str(entered.has(2)), str(entered)])


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
	# W10-A: absolute ceilings for the numbers the wave reports. The relational
	# assertions above prove the table is internally consistent; these pin the
	# measured payload so a change that quietly moves one of the figures fails
	# here instead of being restated in a report. B2.1 moved them by MEASURED
	# amounts (task_covered 113 -> 139, task_blind 94 -> 56, condition_blind
	# 32 -> 20): node-aware coverage drives 27 authored literal `Delay Task`
	# instances and reads `Set Alertness`/`Delay Task`/`Move To`/`Rotate`
	# parameters. No floor was lowered.
	_ok(int(totals["task_classes"]) == 77,
		"absolute: task classes == 77 (got %d)" % int(totals["task_classes"]))
	_ok(int(totals["task_instances"]) == 326,
		"absolute: task instances == 326 (got %d)" % int(totals["task_instances"]))
	_ok(int(totals["task_covered"]) == 139,
		"absolute: task covered == 139 (got %d)" % int(totals["task_covered"]))
	_ok(int(totals["task_blind"]) == 56,
		"absolute: task parameter-blind == 56 (got %d)" % int(totals["task_blind"]))
	_ok(int(totals["condition_classes"]) == 36,
		"absolute: condition classes == 36 (got %d)" % int(totals["condition_classes"]))
	_ok(int(totals["condition_instances"]) == 233,
		"absolute: condition instances == 233 (got %d)" % int(totals["condition_instances"]))
	_ok(int(totals["condition_covered"]) == 35,
		"absolute: condition covered == 35 (got %d)" % int(totals["condition_covered"]))
	_ok(int(totals["condition_blind"]) == 20,
		"absolute: condition parameter-blind == 20 (got %d)" % int(totals["condition_blind"]))
	_ok(int(totals["task_parity_authored"]) == 80,
		"absolute: task parity authored == 80 (got %d)" % int(totals["task_parity_authored"]))
	_ok(int(totals["task_parity_runtime_fed"]) == 3,
		"absolute: task parity runtime-fed == 3 (got %d)" % int(totals["task_parity_runtime_fed"]))
	_ok(int(totals["task_parity_unknown"]) == 56,
		"absolute: task parity unknown == 56 (got %d)" % int(totals["task_parity_unknown"]))
	_ok(int(totals["condition_parity_authored"]) == 13,
		"absolute: condition parity authored == 13 (got %d)" % int(totals["condition_parity_authored"]))
	_ok(int(totals["condition_parity_runtime_fed"]) == 2,
		"absolute: condition parity runtime-fed == 2 (got %d)" % int(totals["condition_parity_runtime_fed"]))
	_ok(int(totals["condition_parity_unknown"]) == 20,
		"absolute: condition parity unknown == 20 (got %d)" % int(totals["condition_parity_unknown"]))
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
	# Structural coverage vs data parity are different numbers.
	var fully: Array = []
	var fully_parity: Array = []
	for tree_name: Variant in coverage["per_tree"].keys():
		if bool((coverage["per_tree"][tree_name] as Dictionary)["fully_covered"]):
			fully.append(str(tree_name))
		if bool((coverage["per_tree"][tree_name] as Dictionary)["fully_parity_covered"]):
			fully_parity.append(str(tree_name))
	fully.sort()
	fully_parity.sort()
	# The first structurally covered tree is the one with no undeclared task and
	# whose only gap was a literal Delay Task. ST_Patrol is NOT fully covered.
	_ok(fully.size() == 1 and str(fully[0]) == "ST_Subtree_IntruderNoLongerSuspicious",
		"the one structurally covered tree is ST_Subtree_IntruderNoLongerSuspicious (got %s)" % str(fully))
	_ok(fully_parity.is_empty(), "no tree is fully parity-covered yet (got %s)" % str(fully_parity))
	_ok(not fully.has("ST_Patrol"), "ST_Patrol is not claimed fully covered")
	_ok(not bool((coverage["per_tree"]["ST_Patrol"] as Dictionary)["fully_covered"]),
		"ST_Patrol per-tree row is not fully_covered")
	# Per-instance detail: the three Delay Tasks and the UNKNOWN Bool Compare.
	var instances: Array = coverage["instances"]
	_ok(instances.size() == 559, "one coverage row per referenced node (got %d)" % instances.size())
	var by_key: Dictionary = {}
	for row: Dictionary in instances:
		by_key[str(row["key"])] = row
	var delay_17: Dictionary = by_key.get("ST_Patrol#14", {})
	_ok(int(delay_17.get("node_index", -2)) == 14, "instance rows carry the node index")
	_ok(delay_17.get("param_source", "") == "bound-authored-record",
		"ST_Patrol[17] Delay Task param_source (got %s)" % str(delay_17.get("param_source", "")))
	_ok(delay_17.get("parity", "") == "runtime-fed",
		"ST_Patrol[17] Delay Task parity (got %s)" % str(delay_17.get("parity", "")))
	_ok(bool(delay_17.get("covered", false)), "ST_Patrol[17] Delay Task is covered")
	var delay_19: Dictionary = by_key.get("ST_Patrol#16", {})
	_ok(delay_19.get("param_source", "") == "literal",
		"ST_Patrol[19] Delay Task param_source (got %s)" % str(delay_19.get("param_source", "")))
	_ok(delay_19.get("parity", "") == "authored",
		"ST_Patrol[19] Delay Task parity (got %s)" % str(delay_19.get("parity", "")))
	var intruder_delay: Dictionary = {}
	for row: Dictionary in instances:
		if str(row["tree"]) == "ST_Subtree_IntruderNoLongerSuspicious" and str(row["name"]) == "Delay Task":
			intruder_delay = row
	_ok(not intruder_delay.is_empty(), "the intruder tree's Delay Task has an instance row")
	_ok(bool(intruder_delay.get("covered", false)) and intruder_delay.get("parity", "") == "authored",
		"the intruder tree's literal Delay Task is covered and authored (got %s/%s)"
			% [str(intruder_delay.get("covered", false)), str(intruder_delay.get("parity", ""))])
	var bad_rows: Array = []
	var unknown_rows: int = 0
	for row: Dictionary in instances:
		if not (str(row.get("param_source", "")) in ["literal", "bound-authored-record", "bound-unknown", "context", "ref-access", "inherited", "none"]):
			bad_rows.append(str(row.get("key", "")))
		if not (str(row.get("parity", "")) in ["authored", "runtime-fed", "unknown", "uncovered"]):
			bad_rows.append(str(row.get("key", "")))
		if str(row.get("parity", "")) == "unknown":
			unknown_rows += 1
	_ok(bad_rows.is_empty(), "every instance has a valid param_source/parity (%s)" % str(bad_rows.slice(0, 4)))
	_ok(unknown_rows == int(totals["task_parity_unknown"]) + int(totals["condition_parity_unknown"]),
		"instance parity unknown rows == the class totals (%d)" % unknown_rows)
	print(Coverage.summary_line(coverage))
	print("P4COVERAGE fully_covered_trees=%d names=%s fully_parity_covered_trees=%d names=%s"
		% [fully.size(), str(fully), fully_parity.size(), str(fully_parity)])
	for line: String in Coverage.table_lines(coverage, "tasks"):
		print("P4ROW ", line)
	for line: String in Coverage.table_lines(coverage, "conditions"):
		print("P4ROW ", line)


func _check_vacuous_and_events() -> void:
	var coverage: Dictionary = ShadowRunner.coverage(null)
	var totals: Dictionary = coverage["totals"]
	var per_tree: Dictionary = coverage["per_tree"]
	# Phase 3B.1: the one structurally covered tree must be named as an algebra
	# result. If a future binding makes it behaviourally meaningful this fails and
	# the note must be revisited -- it must not silently stay "vacuous".
	var vacuous: Array = totals["vacuous_trees"]
	_ok(vacuous == ["ST_Subtree_IntruderNoLongerSuspicious"],
		"the vacuous tree is named (got %s)" % str(vacuous))
	var intruder: Dictionary = per_tree.get("ST_Subtree_IntruderNoLongerSuspicious", {})
	_ok(bool(intruder.get("vacuous", false)), "per-tree row is flagged vacuous")
	_ok(int(intruder.get("states", 0)) == 4,
		"the vacuous tree has 4 states (got %d)" % int(intruder.get("states", 0)))
	_ok(str(intruder.get("vacuous_state_flow", "")) == "Set Focus -> Request Voice Line -> Delay -> Succeeded",
		"the vacuous state flow is the 4-state Set Focus -> Request Voice Line -> Delay -> Succeeded (got %s)"
			% str(intruder.get("vacuous_state_flow", "")))
	_ok((totals["vacuous_state_mismatch"] as Array).is_empty(),
		"the declared vacuous state count matches the payload (%s)" % str(totals["vacuous_state_mismatch"]))
	# Pin the structural-vs-parity split the plan quotes: 1 structurally covered
	# tree, 0 of 21 data-parity covered.
	_ok(int(totals["trees_total"]) == 21, "the coverage table has 21 trees (got %d)" % int(totals["trees_total"]))
	_ok((totals["fully_covered_trees"] as Array) == ["ST_Subtree_IntruderNoLongerSuspicious"],
		"exactly one structurally covered tree (got %s)" % str(totals["fully_covered_trees"]))
	_ok((totals["fully_parity_covered_trees"] as Array).is_empty(),
		"fully_parity_covered_trees is 0 of 21 (got %s)" % str(totals["fully_parity_covered_trees"]))
	# Event census: 17 authored tags, 1 live emitter (StimChange), 16 unemitted.
	# Round 2: a state's `required_event_to_enter` is `{tag, payload_struct}` in
	# payload /2 (tree_model.gd `_normalise_required_event`), so the census is
	# 92 = 89 transition gates + 3 enabled state-enter gates, not 89.
	var events: Dictionary = totals["events"]
	var counts: Dictionary = events["counts"]
	_ok(int(counts["authored"]) == 17,
		"17 authored StateTreeEvent tags (got %d)" % int(counts["authored"]))
	_ok(int(counts["enter"]) == 3,
		"3 enabled state required_event_to_enter gates (got %d)" % int(counts["enter"]))
	_ok(int(counts["transition"]) == 89,
		"89 transition required_event gates (got %d)" % int(counts["transition"]))
	_ok(int(counts["gates"]) == 92 and int(counts["total"]) == 92,
		"92 authored event gates in total (gates=%d total=%d)"
			% [int(counts["gates"]), int(counts["total"])])
	_ok(int(counts["emitted"]) == 1 and (events["emitted"] as Array) == ["StateTreeEvent.StimChange"],
		"exactly one live-emitted tag is StateTreeEvent.StimChange (got %s)" % str(events["emitted"]))
	_ok(int(counts["unemitted"]) == 16,
		"16 authored tags remain unemitted (got %d)" % int(counts["unemitted"]))
	_ok(not (events["unemitted"] as Array).has("StateTreeEvent.StimChange"),
		"StimChange is not counted as unemitted")
	_ok(str((events["emitters"] as Dictionary).get("StateTreeEvent.StimChange", "")).find("guard_ai._hear") >= 0,
		"the StimChange emitter is the existing hearing path (got %s)"
			% str((events["emitters"] as Dictionary).get("StateTreeEvent.StimChange", "")))
	# NEGATIVE CONTROL, derived from the RAW payload (not by re-applying the
	# census rule): build the gate list straight from the JSON file, counting a
	# state's `required_event_to_enter` in BOTH its String and `{tag}` shapes.
	# A string-only counter (the round-1 bug) yields 89 and must NOT match: the
	# three Dictionary-shaped enter gates are the point of this test.
	var raw: Dictionary = _raw_payload_event_gates()
	var raw_total: int = int(raw.get("total", -1))
	var raw_enter: int = int(raw.get("enter", -1))
	var raw_transition: int = int(raw.get("transition", -1))
	var string_only: int = int(raw.get("string_only", -1))
	_ok(raw_enter == 3, "raw payload: 3 state-entry gates (got %d)" % raw_enter)
	_ok(raw_transition == 89, "raw payload: 89 transition gates (got %d)" % raw_transition)
	_ok(raw_total == 92, "raw payload: 92 gates in total (got %d)" % raw_total)
	_ok(raw_total == int(counts["total"]),
		"the census counts the same gates as the raw payload (%d vs %d)"
			% [int(counts["total"]), raw_total])
	_ok(string_only == 89 and string_only != raw_total,
		"a string-only counter is wrong (89 != 92; got string_only=%d raw_total=%d)"
			% [string_only, raw_total])
	_ok(raw_total - string_only == raw_enter,
		"the missing gates are exactly the %d Dictionary-shaped enter gates" % raw_enter)
	_ok(str(raw.get("enter_gates", [])) == str([
		"ST_InvestigateStims_Guard#Extract Reaction Role from Event:StateTreeEvent.ReactionRoleChange",
		"ST_Patrol#Extract distraction Event:StateTreeEvent.DistractionEvent",
		"ST_Subtree_Combat#Extract Reaction Role from Event:StateTreeEvent.ReactionRoleChange",
	]), "the 3 enter gates are the authored ones (got %s)" % str(raw.get("enter_gates", [])))
	for line: String in Coverage.vacuous_lines(coverage):
		print("P4VACUOUS ", line)
	print("P4EVENTS authored=%d emitted=%d unemitted=%d enter=%d transition=%d total=%d raw_total=%d string_only=%d"
		% [int(counts["authored"]), int(counts["emitted"]), int(counts["unemitted"]),
			int(counts["enter"]), int(counts["transition"]), int(counts["total"]),
			raw_total, string_only])
	print("P4ENTER_GATES %s" % str(raw.get("enter_gates", [])))


## Reads the raw payload JSON (not the normalised model, so the test cannot
## inherit the bug it is checking) and counts event gates in both shapes.
func _raw_payload_event_gates() -> Dictionary:
	var path: String = TreeModel.DEFAULT_PATH
	if not FileAccess.file_exists(path):
		_ok(false, "raw payload present at %s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_ok(false, "raw payload openable at %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_ok(false, "raw payload parses as JSON")
		return {}
	var raw_trees: Variant = (parsed as Dictionary).get("trees", {})
	if not (raw_trees is Dictionary):
		_ok(false, "raw payload has a trees object")
		return {}
	var enter: int = 0
	var transition: int = 0
	var string_only: int = 0
	var enter_gates: Array = []
	for tree_name: Variant in (raw_trees as Dictionary).keys():
		var tree: Dictionary = (raw_trees as Dictionary)[tree_name]
		for state: Variant in (tree.get("states", []) as Array):
			if not (state is Dictionary):
				continue
			var sd: Dictionary = state
			var required: Variant = sd.get("required_event_to_enter")
			if required is Dictionary:
				var tag: String = str((required as Dictionary).get("tag", ""))
				if tag != "":
					enter += 1
					enter_gates.append("%s#%s:%s" % [str(tree_name), str(sd.get("name", "")), tag])
			elif required is String and str(required) != "":
				enter += 1
				string_only += 1
				enter_gates.append("%s#%s:%s" % [str(tree_name), str(sd.get("name", "")), str(required)])
			for tr: Variant in (sd.get("transitions", []) as Array):
				if not (tr is Dictionary):
					continue
				var event: Variant = (tr as Dictionary).get("required_event")
				if event is String and str(event) != "":
					transition += 1
					string_only += 1
				elif event is Dictionary:
					# Round-1 string-only rule would also drop this shape.
					var tr_tag: String = str((event as Dictionary).get("tag", ""))
					if tr_tag != "":
						transition += 1
	enter_gates.sort()
	return {
		"enter": enter,
		"transition": transition,
		"total": enter + transition,
		# What the round-1 rule counted: every transition tag (all Strings) plus
		# only the String-shaped enter gates.
		"string_only": string_only,
		"enter_gates": enter_gates,
	}


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


func _state(index: int, name: String, parent: int, children: Array, tasks: Array = [], enter: Array = [], transitions: Array = [], selection: String = "TrySelectChildrenInOrder", required_event: Dictionary = {}, consume: bool = true) -> Dictionary:
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
		"required_event_to_enter": required_event if not required_event.is_empty() else null,
		"consume_event_on_select": consume,
		"transitions": transitions,
		"linked_asset": null,
		"linked_state_index": null,
		"enabled": true,
		"selection_behavior": selection,
	}


func _tr(index: int, to_state: int, trigger: String, conditions: Array = [], priority: String = "None", event: String = "", to_kind: String = "state", to_index: int = -1, delay: float = 0.0, fallback: String = "None", consume: bool = true) -> Dictionary:
	return {
		"index": index,
		"to_state": "state_%d" % to_state if to_kind == "state" else null,
		"to_state_index": to_index if to_kind != "state" else to_state,
		"to_kind": to_kind,
		"trigger": trigger,
		"priority": priority,
		"required_event": event,
		"consume_event_on_select": consume,
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
				"consume_event_on_select": bool(tr.get("consume_event_on_select", true)),
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
	# B2.1 event gates. `STATE_GATE` is the tag all of these use; the real
	# payload's three gated states carry the same shape.
	var gate_event: Dictionary = {"tag": "StateTreeEvent.Gate", "payload_struct": "SynthGatePayload"}
	trees["SYN_GATE_BLOCK"] = {
		"name": "SYN_GATE_BLOCK", "package": "<synthetic>", "asset": "/Synth/GATE_BLOCK",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1, 2], [], [], []),
			_state(1, "Gated", 0, [], ["SYN_NEVER"], [], [], "TrySelectChildrenInOrder", gate_event),
			_state(2, "Plain", 0, [], ["SYN_NEVER"], [], []),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	# Transition + state both consume (the default pair).
	trees["SYN_GATE_EVENT"] = {
		"name": "SYN_GATE_EVENT", "package": "<synthetic>", "asset": "/Synth/GATE_EVENT",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1], [], [], []),
			_state(1, "Idle", 0, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(0, 2, "OnEvent", [], "Normal", "StateTreeEvent.Gate")]),
			_state(2, "Gated", 0, [], ["SYN_NEVER"], [], [], "TrySelectChildrenInOrder", gate_event),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	# Transition keeps the event (consume_event_on_select false); state keeps it too.
	trees["SYN_GATE_KEEP"] = {
		"name": "SYN_GATE_KEEP", "package": "<synthetic>", "asset": "/Synth/GATE_KEEP",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1], [], [], []),
			_state(1, "Idle", 0, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(0, 2, "OnEvent", [], "Normal", "StateTreeEvent.Gate", "state", -1, 0.0, "None", false)]),
			_state(2, "Gated", 0, [], ["SYN_NEVER"], [], [], "TrySelectChildrenInOrder", gate_event, false),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	# A gated state whose gated child also needs the same event: the parent must
	# consume only AFTER the child selected (port decision 3).
	trees["SYN_GATE_NESTED"] = {
		"name": "SYN_GATE_NESTED", "package": "<synthetic>", "asset": "/Synth/GATE_NESTED",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1], [], [], []),
			_state(1, "Idle", 0, [], ["SYN_NEVER"], ["SYN_TRUE"],
				[_tr(0, 2, "OnEvent", [], "Normal", "StateTreeEvent.Gate", "state", -1, 0.0, "None", false)]),
			_state(2, "GatedParent", 0, [3], [], [], [], "TrySelectChildrenInOrder", gate_event),
			_state(3, "GatedChild", 2, [], ["SYN_NEVER"], [], [], "TrySelectChildrenInOrder", gate_event),
		],
		"transitions": [], "tasks": [], "conditions": [], "subtree_links": [],
		"stats": {},
	}
	# A literal (unbound) Delay Task: the generic base driver must run it.
	trees["SYN_DELAY_LITERAL"] = {
		"name": "SYN_DELAY_LITERAL", "package": "<synthetic>", "asset": "/Synth/DELAY_LITERAL",
		"roots": ["Root"],
		"states": [
			_state(0, "Root", -1, [1], [], [], []),
			_state(1, "Wait", 0, [], [
				{"name": "Delay Task", "node_index": 0, "template_index": 0,
					"data_source": "ActiveInstanceData", "inherited": false,
					"parameters": {"duration": 0.20, "RandomDeviation": 0.0, "bRunForever": false},
					"bound": {}},
			], ["SYN_TRUE"], [_tr(0, 2, "OnStateCompleted")]),
			_state(2, "Done", 0, [], ["SYN_DONE"], ["SYN_TRUE"],
				[_tr(1, -1, "OnStateCompleted", [], "None", "", "Succeeded", 65534)]),
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
