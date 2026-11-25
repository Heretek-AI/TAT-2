extends RefCounted
## Engine-neutral StateTree interpreter (W9-P4 S1).
##
## Semantics come from the cooked UE 5.5 assets (`guard_behavior.json`) plus the
## UE StateTree execution model; where the payload cannot prove a rule the
## comment says so and the choice is a documented port decision.
##
## WHAT THE INTERPRETER DOES
##   * keeps a stack of active frames (root .. selected leaf); a frame is
##     `{tree, state}` so a `LinkedAsset` state can run another tree without
##     flattening the two;
##   * enters states by evaluating `enter_conditions` (TRUE / FALSE / UNKNOWN),
##     then runs `TrySelectChildrenInOrder` / `TryEnterState` selection;
##   * drives task instances through `bindings.task_enter/tick/exit` and
##     propagates RUNNING / SUCCEEDED / FAILED / UNSET up the frame stack;
##   * arbitrates transitions from every active frame: enabled, trigger match,
##     every condition TRUE, highest `EStateTreeTransitionPriority` first, then
##     deepest frame, then lowest authored transition index;
##   * handles `to_kind == "state"` (enter the target), `"Succeeded"` (the owning
##     state completes successfully) and `"Next"` (the owning state's parent
##     advances past it);
##   * queues events (`StateTreeEvent.*` tags) and matches them against
##     `RequiredEvent`.
##
## PROVEN RULES ENCODED (citations in `build/qa/w9/p4-re-statetree.md`):
##   * priority order is `None < Low < Normal < Medium < High < Critical` (UE
##     5.5 enum values; `Medium` outranks `Normal`);
##   * all active states are candidate sources, leaf first; highest priority
##     wins, ties go to the deepest state then to authored array order;
##   * `OnStateCompleted` fires on success OR failure; `OnStateSucceeded` /
##     `OnStateFailed` are the discriminated forms;
##   * a candidate whose target cannot be selected is skipped and the next
##     candidate is considered (`ST_Subtree_Combat_ActivateAttack` state 3);
##   * a state with children that cannot select any child is not selected
##     (Epic's selection docs), so its entry is rolled back and the parent tries
##     its next sibling;
##   * a no-task state has finished its own work on entry, which is how a Group
##     waits for a child and how a no-task leaf completes at once.
##
## PORT DECISIONS (no UE reference was available for these two, so they are
## stated rather than hidden):
##   1. UNKNOWN is treated like FALSE for both selection and transition
##      conditions. The interpreter never fires a transition on a condition the
##      payload cannot evaluate; every UNKNOWN is recorded in the trace.
##   2. A state whose children all fail to enter stays the active leaf instead of
##      failing its parent. A no-task state (every Group with no tasks) is
##      already "own work done" on entry, so it completes on the next pass and
##      its parent advances -- it never fails. UE's
##      `EStateTreeSelectionFallback` is `None`/`NextSelectableSibling`; the
##      payload does not carry the property, and this reading keeps the tree
##      alive rather than collapsing it when one branch cannot be entered.
##
## The interpreter is gameplay-agnostic: it never touches a Node, a transform, a
## player or an autoload. Everything observable goes through `bindings`.

const TreeModel = preload("res://src/ai/statetree/tree_model.gd")
const Bindings = preload("res://src/ai/statetree/bindings.gd")

## Frame status values (same numbering as the bindings' run status).
const RUNNING: int = 0
const RUNNING_LATENT: int = 1
const SUCCEEDED: int = 2
const FAILED: int = 3
const UNSET: int = 4

## Enter results.
const ENTER_OK: int = 0
const ENTER_FALSE: int = 1
const ENTER_UNKNOWN: int = 2

const MAX_FRAMES: int = 32

var trees: Dictionary = {}
var tree_name: String = ""
var bindings: RefCounted = null
var trace: RefCounted = null
## Merged into every trace row (the shadow runner puts the guard identity here).
var trace_context: Dictionary = {}

var frames: Array[Dictionary] = []
var pending_events: Array[Dictionary] = []
var tick_events: Array[Dictionary] = []
var time_s: float = 0.0
var ticks: int = 0
var running: bool = false
var tree_status: int = RUNNING

## Diagnostics, all measured (never reset unless `reset_stats()` is called).
var stats: Dictionary = {
	"entries": 0,
	"exits": 0,
	"transitions": 0,
	"conditions_true": 0,
	"conditions_false": 0,
	"conditions_unknown": 0,
	"tasks_entered": 0,
	"tasks_succeeded": 0,
	"tasks_failed": 0,
	"tasks_unset": 0,
	"blocks": 0,
	"unknown_enters": 0,
	"unknown_transition_votes": 0,
	"fallback_selections": 0,
	"selection_refused": 0,
	"events": 0,
	"max_frames": 0,
}
var visited: Dictionary = {}
var transitions_fired: Array[Dictionary] = []
var blocks: Array[Dictionary] = []
var unknown_conditions: Dictionary = {}

var _pending_transition: Dictionary = {}
var _pending_remaining: float = 0.0
var _pending_frame_key: String = ""
var _enter_depth: int = 0


func setup(p_trees: Dictionary, p_tree_name: String, p_bindings: RefCounted, p_trace: RefCounted = null) -> void:
	trees = p_trees
	tree_name = p_tree_name
	bindings = p_bindings
	trace = p_trace


## Enter the tree's first root. Returns true when a root was selected.
func start() -> bool:
	reset_stats()
	frames.clear()
	pending_events.clear()
	tick_events.clear()
	time_s = 0.0
	ticks = 0
	tree_status = RUNNING
	running = false
	var tree: Dictionary = trees.get(tree_name, {})
	if tree.is_empty():
		_record_block("", -1, "tree", "unknown tree '%s'" % tree_name)
		return false
	var entry: int = int(tree.get("entry", -1))
	if entry < 0:
		_record_block(tree_name, -1, "tree", "tree has no entry root")
		return false
	var result: int = _enter_state(tree_name, entry)
	if result == ENTER_OK:
		running = true
		_emit({"kind": "start", "tree": tree_name, "state": entry, "path": current_path()})
		return true
	_record_block(tree_name, entry, "enter", "root refused to enter (%s)" % _enter_name(result))
	return false


func push_event(tag: String, payload: Dictionary = {}) -> void:
	if tag == "":
		return
	pending_events.append({"tag": tag, "payload": payload, "t": time_s})
	stats["events"] = int(stats["events"]) + 1


## One interpreter tick. `delta` is seconds.
func tick(delta: float) -> void:
	if not running:
		return
	ticks += 1
	time_s += delta
	tick_events = pending_events
	pending_events = []

	if not _pending_transition.is_empty():
		_pending_remaining -= delta
		if _pending_remaining <= 0.0 and _pending_frame_key == _frame_key(frames.size() - 1):
			var delayed: Dictionary = _pending_transition
			_pending_transition = {}
			_pending_frame_key = ""
			_apply_transition(delayed)
			if not running:
				return

	_tick_tasks(delta)
	_resolve_completions()

	# A completed frame is resolved by its own OnStateCompleted/Succeeded/Failed
	# transitions first, then by the parent's next-sibling selection.
	var completion_applied: bool = _collect_and_apply(_completion_candidates(), true)
	if not completion_applied and _pending_transition.is_empty():
		_resolve_terminal_fallback()
	_collect_and_apply(_tick_candidates(), false)
	_collect_and_apply(_event_candidates(), false)

	if bindings != null:
		bindings.after_tick(self)


## The current leaf path, e.g. `"ST_Guard:Root/Standard States/... -> ST_Patrol:Root"`.
func current_path() -> String:
	var parts: PackedStringArray = []
	for frame: Dictionary in frames:
		parts.append("%s:%s" % [str(frame.get("tree", "")), TreeModel.path_string(trees.get(str(frame.get("tree", "")), {}), int(frame.get("state", -1)))])
	return " -> ".join(parts)


func current_state() -> int:
	if frames.is_empty():
		return -1
	return int(frames[frames.size() - 1].get("state", -1))


func current_tree() -> String:
	if frames.is_empty():
		return ""
	return str(frames[frames.size() - 1].get("tree", ""))


func current_state_name() -> String:
	if frames.is_empty():
		return ""
	var frame: Dictionary = frames[frames.size() - 1]
	return TreeModel.state_name(trees.get(str(frame["tree"]), {}), int(frame["state"]))


func selected_index() -> int:
	return frames.size() - 1


func is_blocked() -> bool:
	return not blocks.is_empty() and _leaf_blocked()


func blocked_reason() -> String:
	if blocks.is_empty():
		return ""
	return str((blocks[blocks.size() - 1] as Dictionary).get("reason", ""))


func reset_stats() -> void:
	for key: Variant in stats.keys():
		stats[key] = 0
	visited.clear()
	transitions_fired.clear()
	blocks.clear()
	unknown_conditions.clear()
	_pending_transition = {}
	_pending_remaining = 0.0
	_pending_frame_key = ""


# ---------------------------------------------------------------------------
# Frame stack
# ---------------------------------------------------------------------------


func _leaf_blocked() -> bool:
	if frames.is_empty():
		return true
	return int(frames[frames.size() - 1].get("own", RUNNING)) == UNSET


func _frame_key(index: int) -> String:
	if index < 0 or index >= frames.size():
		return ""
	var f: Dictionary = frames[index]
	return "%s:%d" % [str(f.get("tree", "")), int(f.get("state", -1))]


func _tree_of(frame: Dictionary) -> Dictionary:
	return trees.get(str(frame.get("tree", "")), {})


func _enter_state(tree: String, state_index: int) -> int:
	if _enter_depth > MAX_FRAMES or frames.size() >= MAX_FRAMES:
		return ENTER_UNKNOWN
	var tree_dict: Dictionary = trees.get(tree, {})
	if not TreeModel.has_state(tree_dict, state_index):
		return ENTER_FALSE
	var state: Dictionary = TreeModel.state(tree_dict, state_index)
	var result: int = _evaluate_enter_conditions(tree, state_index)
	if result != ENTER_OK:
		return result
	# A state with no tasks has finished its own work the moment it is entered;
	# its status then depends only on its selected child (or, for a leaf, on
	# nothing). That is how a Group waits for a child and how a no-task leaf
	# completes immediately -- both are load-bearing in the authored data.
	var has_tasks: bool = not (state.get("tasks", []) as Array).is_empty()
	# Pop any sibling frames at this depth: entering is always a replacement.
	var frame: Dictionary = {
		"tree": tree,
		"state": state_index,
		"name": str(state.get("name", "")),
		"tasks": [],
		"own": RUNNING if has_tasks else SUCCEEDED,
		"child": RUNNING,
		"completion_consumed": false,
		"entered_s": time_s,
		"next_child_cursor": 0,
		"has_child": false,
	}
	frames.append(frame)
	stats["entries"] = int(stats["entries"]) + 1
	stats["max_frames"] = maxi(int(stats["max_frames"]), frames.size())
	visited[frame_key(tree, state_index, str(state.get("name", "")))] = true
	_emit({
		"kind": "enter",
		"tree": tree,
		"state": state_index,
		"name": str(state.get("name", "")),
		"path": current_path(),
		"type": str(state.get("type", "")),
	})
	_enter_tasks(frame)
	_enter_depth += 1
	# Composition: a LinkedAsset runs another asset's root; a local `Linked`
	# state runs a second root inside the same asset.
	if TreeModel.is_linked_asset(tree_dict, state_index):
		var target: String = str(state.get("linked_asset", ""))
		var target_tree: Dictionary = trees.get(target, {})
		var target_entry: int = int(target_tree.get("entry", -1))
		if target_entry >= 0:
			var linked_result: int = _enter_state(target, target_entry)
			if linked_result == ENTER_OK:
				# The link state's only child is the linked asset's root. Without
				# this the link frame looks childless, completes at once and takes
				# `OnStateCompleted -> Root` (ST_Guard "Patrolling", tick 2).
				frame["has_child"] = true
				frame["child"] = RUNNING
			else:
				_emit({"kind": "linked_refused", "tree": target, "state": target_entry, "result": _enter_name(linked_result)})
		else:
			_record_block(tree, state_index, "link", "linked asset '%s' has no entry" % target)
	elif TreeModel.is_local_link(tree_dict, state_index):
		var local_entry: int = int(state.get("linked_state_index", -1))
		if TreeModel.has_state(tree_dict, local_entry):
			if _enter_state(tree, local_entry) == ENTER_OK:
				frame["has_child"] = true
				frame["child"] = RUNNING
	_enter_depth -= 1
	# Children: `TrySelectChildrenInOrder` selects the first child that can be
	# entered; `TryEnterState` is a leaf by construction (no children authored
	# on any of the 20 measured TryEnterState states).
	if not TreeModel.children(tree_dict, state_index).is_empty():
		var frame_index: int = frames.size() - 1
		if not _select_child_at(frame_index):
			# UE: "If a State has child States, yet none can be selected ... the
			# State will not be selected even if all its Enter Conditions passed."
			# Roll the entry back so the caller can try its next sibling.
			_exit_to(frame_index)
			stats["selection_refused"] = int(stats.get("selection_refused", 0)) + 1
			return ENTER_FALSE
	return ENTER_OK


## Re-run a frame's child selection starting after the currently selected child
## (`EStateTreeSelectionFallback::NextSelectableSibling`). Returns true when a
## sibling was entered.
func _select_next_sibling(index: int, after_state: int = -1) -> bool:
	if index < 0 or index >= frames.size():
		return false
	var parent_frame: Dictionary = frames[index]
	var tree_dict: Dictionary = _tree_of(parent_frame)
	var kids: Array = TreeModel.children(tree_dict, int(parent_frame["state"]))
	# `after_state` is the state that just finished: selection resumes at the
	# sibling *after it*. Using the stored cursor instead re-enters the finished
	# child whenever a transition (not the initial selection) entered it.
	var cursor: int = int(parent_frame.get("next_child_cursor", 0))
	if after_state >= 0:
		var found: int = kids.find(after_state)
		cursor = found + 1 if found >= 0 else cursor
	while cursor < kids.size():
		var child: int = int(kids[cursor])
		cursor += 1
		parent_frame["next_child_cursor"] = cursor
		var was: int = frames.size()
		var result: int = _enter_state(str(parent_frame["tree"]), child)
		if result == ENTER_OK:
			parent_frame["has_child"] = true
			parent_frame["child"] = RUNNING
			return true
		# `_enter_state` only appends on success; truncate defensively so a
		# partial entry can never leave a stray frame behind.
		while frames.size() > was:
			frames.pop_back()
		if result == ENTER_UNKNOWN:
			stats["unknown_enters"] = int(stats["unknown_enters"]) + 1
	stats["fallback_selections"] = int(stats["fallback_selections"]) + 1
	return false


func _select_child_at(index: int) -> bool:
	if index < 0 or index >= frames.size():
		return false
	var parent_frame: Dictionary = frames[index]
	var tree_dict: Dictionary = _tree_of(parent_frame)
	var kids: Array = TreeModel.children(tree_dict, int(parent_frame["state"]))
	parent_frame["next_child_cursor"] = 0
	for child: Variant in kids:
		parent_frame["next_child_cursor"] = int(parent_frame["next_child_cursor"]) + 1
		var was: int = frames.size()
		var result: int = _enter_state(str(parent_frame["tree"]), int(child))
		if result == ENTER_OK:
			parent_frame["has_child"] = true
			parent_frame["child"] = RUNNING
			return true
		while frames.size() > was:
			frames.pop_back()
		if result == ENTER_UNKNOWN:
			stats["unknown_enters"] = int(stats["unknown_enters"]) + 1
	stats["fallback_selections"] = int(stats["fallback_selections"]) + 1
	return false


func _exit_to(depth: int) -> void:
	while frames.size() > depth:
		var frame: Dictionary = frames[frames.size() - 1]
		for instance: Dictionary in frame.get("tasks", []):
			if bindings != null:
				bindings.task_exit(instance)
		frames.pop_back()
		stats["exits"] = int(stats["exits"]) + 1
		_emit({"kind": "exit", "tree": str(frame["tree"]), "state": int(frame["state"]), "name": str(frame["name"])})


# ---------------------------------------------------------------------------
# Conditions and tasks
# ---------------------------------------------------------------------------


func _evaluate_enter_conditions(tree: String, state_index: int, count_stats: bool = true) -> int:
	var tree_dict: Dictionary = trees.get(tree, {})
	var conditions: PackedStringArray = PackedStringArray(TreeModel.state(tree_dict, state_index).get("enter_conditions", []))
	var saw_unknown: bool = false
	for name: String in conditions:
		var value: int = _condition(name, tree, state_index, {}, count_stats)
		if value == Bindings.COND_FALSE:
			return ENTER_FALSE
		if value == Bindings.COND_UNKNOWN:
			saw_unknown = true
	if saw_unknown:
		return ENTER_UNKNOWN
	return ENTER_OK


func _condition(name: String, tree: String, frame_state: int, transition: Dictionary, count_stats: bool = true) -> int:
	var value: int = Bindings.COND_UNKNOWN
	if bindings != null:
		value = bindings.condition_state(name, tree, frame_state, transition)
	if value == Bindings.COND_TRUE:
		if count_stats:
			stats["conditions_true"] = int(stats["conditions_true"]) + 1
	elif value == Bindings.COND_FALSE:
		if count_stats:
			stats["conditions_false"] = int(stats["conditions_false"]) + 1
	else:
		value = Bindings.COND_UNKNOWN
		if count_stats:
			stats["conditions_unknown"] = int(stats["conditions_unknown"]) + 1
			var key: String = "%s|%s|%d" % [name, tree, frame_state]
			unknown_conditions[key] = int(unknown_conditions.get(key, 0)) + 1
			_emit({"kind": "condition_unknown", "name": name, "tree": tree, "state": frame_state})
	return value


func _enter_tasks(frame: Dictionary) -> void:
	var tree_dict: Dictionary = _tree_of(frame)
	var names: PackedStringArray = PackedStringArray(TreeModel.state(tree_dict, int(frame["state"])).get("tasks", []))
	var instances: Array = []
	for name: String in names:
		stats["tasks_entered"] = int(stats["tasks_entered"]) + 1
		var instance: Dictionary = {}
		if bindings != null:
			instance = bindings.task_enter(name, str(frame["tree"]), int(frame["state"]))
		if instance.is_empty():
			instance = {"task": name, "status": UNSET, "state": int(frame["state"]), "unsupported": true}
			stats["tasks_unset"] = int(stats["tasks_unset"]) + 1
			_record_block(str(frame["tree"]), int(frame["state"]), "task", "unsupported task '%s'" % name)
			_emit({"kind": "task_block", "task": name, "state": int(frame["state"]), "name": str(frame["name"])})
		else:
			instance["task"] = name
			instance["state"] = int(frame["state"])
			if not instance.has("status"):
				instance["status"] = RUNNING
			_emit({
				"kind": "task_enter", "task": name, "state": int(frame["state"]),
				"name": str(frame["name"]),
				"declaration": bindings.declaration("task", name) if bindings != null else {},
			})
		instances.append(instance)
	frame["tasks"] = instances


func _tick_tasks(delta: float) -> void:
	for frame: Dictionary in frames:
		var instances: Array = frame.get("tasks", [])
		if instances.is_empty():
			continue
		var all_done: bool = true
		var any_failed: bool = false
		var any_unset: bool = false
		for instance: Dictionary in instances:
			var status: int = int(instance.get("status", UNSET))
			if status == RUNNING or status == RUNNING_LATENT:
				status = bindings.task_tick(instance, delta) if bindings != null else UNSET
				instance["status"] = status
				if status == SUCCEEDED:
					stats["tasks_succeeded"] = int(stats["tasks_succeeded"]) + 1
					_emit({"kind": "task_succeeded", "task": str(instance.get("task", "")), "state": int(frame["state"])})
				elif status == FAILED:
					stats["tasks_failed"] = int(stats["tasks_failed"]) + 1
			if status == FAILED:
				any_failed = true
			elif status == UNSET:
				any_unset = true
				all_done = false
			elif status != SUCCEEDED:
				all_done = false
		if any_failed:
			frame["own"] = FAILED
		elif any_unset:
			frame["own"] = UNSET
		elif all_done:
			frame["own"] = SUCCEEDED


## Propagate child status upward and resolve frames that completed. Completed
## frames are left in place for one tick so their own transitions can fire; the
## `_completion_candidates` pass then consumes them.
func _resolve_completions() -> void:
	for i: int in range(frames.size() - 1, -1, -1):
		var frame: Dictionary = frames[i]
		var own: int = int(frame.get("own", RUNNING))
		var child: int = int(frame.get("child", RUNNING))
		# A parent must not inherit a completion that has not been resolved yet:
		# the completed child owns the first shot at its OnStateCompleted
		# transitions, and only after those are consumed may the status travel up.
		# Without this, ST_Patrol's `Patrol` completes on the same tick as its
		# `Set Next Patrol Path Point` child and exits the whole sub-tree.
		var child_pending: bool = false
		if i + 1 < frames.size():
			var child_frame: Dictionary = frames[i + 1]
			var child_status_raw: int = int(child_frame.get("status", RUNNING))
			if (child_status_raw == SUCCEEDED or child_status_raw == FAILED) \
					and not bool(child_frame.get("completion_consumed", false)):
				child_pending = true
		var status: int = RUNNING
		if own == FAILED or child == FAILED:
			status = FAILED
		elif own == UNSET:
			status = UNSET
		elif child_pending:
			status = RUNNING
		elif own == SUCCEEDED and (child == SUCCEEDED or not bool(frame.get("has_child", false))):
			status = SUCCEEDED
		if status != RUNNING and status != RUNNING_LATENT:
			frame["status"] = status
			if i == 0:
				tree_status = status
			else:
				(frames[i - 1] as Dictionary)["child"] = status
		else:
			frame["status"] = RUNNING


## No transition consumed the completed frame: advance the parent's selection
## past it (`NextSelectableSibling`), or finish the tree when it is the root.
func _resolve_terminal_fallback() -> void:
	for i: int in range(frames.size() - 1, -1, -1):
		var frame: Dictionary = frames[i]
		var status: int = int(frame.get("status", RUNNING))
		if (status != SUCCEEDED and status != FAILED) or bool(frame.get("completion_consumed", false)):
			continue
		frame["completion_consumed"] = true
		var parent_status: int = status
		var completed_state: int = int(frame["state"])
		_exit_to(i)
		if i - 1 >= 0 and i - 1 < frames.size():
			var parent: Dictionary = frames[i - 1]
			parent["has_child"] = false
			parent["child"] = parent_status
			var advanced: bool = _select_next_sibling(i - 1, completed_state)
			_emit({"kind": "fallback", "status": parent_status, "advanced": advanced,
				"parent": int(parent["state"]), "cursor": int(parent.get("next_child_cursor", -1))})
		else:
			tree_status = parent_status
			running = false
		return


# ---------------------------------------------------------------------------
# Transitions
# ---------------------------------------------------------------------------


func _completion_candidates() -> Array:
	var out: Array = []
	for i: int in range(frames.size() - 1, -1, -1):
		var frame: Dictionary = frames[i]
		var status: int = int(frame.get("status", RUNNING))
		if status != SUCCEEDED and status != FAILED:
			continue
		if bool(frame.get("completion_consumed", false)):
			continue
		var trigger_ok: String = "OnStateCompleted"
		if status == SUCCEEDED:
			trigger_ok = "OnStateSucceeded"
		var tree_dict: Dictionary = _tree_of(frame)
		for tr: Dictionary in TreeModel.state(tree_dict, int(frame["state"])).get("transitions", []):
			var trigger: String = str(tr.get("trigger", ""))
			if trigger != "OnStateCompleted" and trigger != trigger_ok:
				continue
			out.append({"frame": i, "transition": tr})
	return out


func _tick_candidates() -> Array:
	var out: Array = []
	for i: int in range(frames.size()):
		var frame: Dictionary = frames[i]
		var tree_dict: Dictionary = _tree_of(frame)
		for tr: Dictionary in TreeModel.state(tree_dict, int(frame["state"])).get("transitions", []):
			if str(tr.get("trigger", "")) == "OnTick":
				out.append({"frame": i, "transition": tr})
	return out


func _event_candidates() -> Array:
	var out: Array = []
	if tick_events.is_empty():
		return out
	for i: int in range(frames.size()):
		var frame: Dictionary = frames[i]
		var tree_dict: Dictionary = _tree_of(frame)
		for tr: Dictionary in TreeModel.state(tree_dict, int(frame["state"])).get("transitions", []):
			if str(tr.get("trigger", "")) != "OnEvent":
				continue
			for event: Dictionary in tick_events:
				var matched: int = Bindings.COND_FALSE
				if bindings != null:
					matched = bindings.event_matches(tr, event)
				if matched == Bindings.COND_TRUE:
					out.append({"frame": i, "transition": tr, "event": event})
					break
	return out


func _collect_and_apply(candidates: Array, completion_pass: bool) -> bool:
	if candidates.is_empty() or not running:
		return false
	# Highest priority first; ties go to the deepest active state (the docs walk
	# leaf -> root), then to authored array order ("the first transition ...").
	var ordered: Array = candidates.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: Dictionary = a["transition"]
		var tb: Dictionary = b["transition"]
		if int(ta.get("priority_rank", 0)) != int(tb.get("priority_rank", 0)):
			return int(ta.get("priority_rank", 0)) > int(tb.get("priority_rank", 0))
		if int(a["frame"]) != int(b["frame"]):
			return int(a["frame"]) > int(b["frame"])
		return int(ta.get("index", 0)) < int(tb.get("index", 0)))
	var unmet: Array = []
	var unavailable: Array = []
	for candidate: Dictionary in ordered:
		var tr: Dictionary = candidate["transition"]
		if not bool(tr.get("enabled", true)):
			continue
		var frame_index: int = int(candidate["frame"])
		if frame_index < 0 or frame_index >= frames.size():
			continue
		var frame: Dictionary = frames[frame_index]
		var verdict: Dictionary = _evaluate_transition_conditions(tr, frame)
		if not bool(verdict["ok"]):
			if not (verdict["unmet"] as Array).is_empty():
				unmet.append({"transition": int(tr.get("index", -1)), "state": int(frame["state"]), "unmet": verdict["unmet"]})
			continue
		# "The first Transition that succeeds **and leads to State selection** is
		# selected." A candidate whose target cannot be entered is skipped and the
		# next candidate is considered -- proven by ST_Subtree_Combat_ActivateAttack
		# state 3, which has two condition-less OnTick transitions into
		# enter-conditioned states.
		if str(tr.get("to_kind", "")) == "state":
			var owner_tree: String = str(frame.get("tree", ""))
			var target: int = int(tr.get("to_state_index", -1))
			if _evaluate_enter_conditions(owner_tree, target, false) != ENTER_OK:
				unavailable.append({"transition": int(tr.get("index", -1)), "state": int(frame["state"]), "target": target})
				continue
		if float(tr.get("delay_s", 0.0)) > 0.0 and not completion_pass:
			if not _pending_transition.is_empty() \
					and int(_pending_transition.get("index", -1)) == int(tr.get("index", -2)) \
					and _pending_frame_key == _frame_key(frame_index):
				# Already counting down: re-arming every tick would reset the timer
				# and the delay could never elapse.
				return false
			_pending_transition = tr
			_pending_remaining = float(tr.get("delay_s", 0.0))
			_pending_frame_key = _frame_key(frame_index)
			_emit({"kind": "transition_armed", "transition": int(tr.get("index", -1)), "delay_s": _pending_remaining})
			return false
		_apply_transition(tr)
		return true
	if not unmet.is_empty() or not unavailable.is_empty():
		_emit({
			"kind": "transition_unmet",
			"pass": "completion" if completion_pass else "tick",
			"candidates": unmet,
			"unavailable": unavailable,
		})
	# Nothing applied: `_resolve_terminal_fallback` owns the frame now. Marking it
	# consumed here would leave the parent with child=SUCCEEDED and no next
	# sibling selected, so the parent would complete instead of advancing.
	return false


func _evaluate_transition_conditions(tr: Dictionary, frame: Dictionary) -> Dictionary:
	var unmet: Array = []
	for name: Variant in tr.get("conditions", []):
		var value: int = _condition(str(name), str(frame["tree"]), int(frame["state"]), tr)
		if value != Bindings.COND_TRUE:
			unmet.append({"name": str(name), "result": "true" if value == Bindings.COND_TRUE else ("false" if value == Bindings.COND_FALSE else "unknown")})
			if value == Bindings.COND_UNKNOWN:
				stats["unknown_transition_votes"] = int(stats["unknown_transition_votes"]) + 1
	return {"ok": unmet.is_empty(), "unmet": unmet}


func _apply_transition(tr: Dictionary) -> void:
	stats["transitions"] = int(stats["transitions"]) + 1
	var owner_state: int = int(tr.get("state", -1))
	var to_kind: String = str(tr.get("to_kind", ""))
	var fired: Dictionary = {
		"transition": int(tr.get("index", -1)),
		"from_state": owner_state,
		"trigger": str(tr.get("trigger", "")),
		"priority": str(tr.get("priority", "")),
		"to_kind": to_kind,
		"to_state": str(tr.get("to_state", "")),
		"to_state_index": int(tr.get("to_state_index", -1)),
	}
	transitions_fired.append(fired)
	_emit({"kind": "transition", "chosen": fired, "path": current_path()})
	# Find the owning frame (deepest frame whose tree AND state match the owner).
	# Matching on the state index alone picks the wrong tree whenever a
	# LinkedAsset is active and both trees have a state with that index.
	var owner_tree_name: String = str(tr.get("tree", ""))
	var owner_frame: int = -1
	for i: int in range(frames.size() - 1, -1, -1):
		var candidate: Dictionary = frames[i]
		if int(candidate.get("state", -1)) != owner_state:
			continue
		if owner_tree_name != "" and str(candidate.get("tree", "")) != owner_tree_name:
			continue
		owner_frame = i
		break
	if owner_frame < 0:
		owner_frame = frames.size() - 1
	var owner_tree: String = str((frames[owner_frame] as Dictionary).get("tree", tree_name)) if owner_frame < frames.size() else tree_name
	if to_kind == "state":
		var target: int = int(tr.get("to_state_index", -1))
		var tree_dict: Dictionary = trees.get(owner_tree, {})
		if not TreeModel.has_state(tree_dict, target):
			_record_block(str(frames[owner_frame]["tree"]), owner_state, "transition", "target %d missing" % target)
			return
		# Exit down to the deepest active ancestor of the target, then enter it.
		var chain: Dictionary = {}
		var cursor: int = target
		var hops: int = 0
		while cursor >= 0 and hops < 64:
			chain[cursor] = true
			cursor = TreeModel.parent_index(tree_dict, cursor)
			hops += 1
		var depth: int = frames.size()
		for i: int in range(frames.size() - 1, -1, -1):
			if str((frames[i] as Dictionary).get("tree", "")) != str(frames[owner_frame]["tree"]):
				continue
			if chain.has(int((frames[i] as Dictionary).get("state", -1))):
				depth = i + 1
				break
		_exit_to(depth)
		if depth > 0 and target == int((frames[depth - 1] as Dictionary).get("state", -1)):
			return
		var result: int = _enter_state(owner_tree, target)
		if result != ENTER_OK:
			_record_block(owner_tree, target, "transition", "target refused (%s)" % _enter_name(result))
			return
		# The ancestor kept from the exit is the new target's parent: it now has
		# a running child (without this, a stale child=SUCCEEDED completes it).
		if depth - 1 >= 0 and depth - 1 < frames.size():
			var parent: Dictionary = frames[depth - 1]
			parent["has_child"] = true
			parent["child"] = RUNNING
		return
	# Succeeded / Next: the owning frame's status is already SUCCEEDED; exit its
	# subtree and let the parent select the next sibling.
	if owner_frame < frames.size():
		var parent_index: int = owner_frame - 1
		_exit_to(owner_frame)
		if to_kind == "Next" and parent_index >= 0 and parent_index < frames.size():
			(frames[parent_index] as Dictionary)["has_child"] = false
			(frames[parent_index] as Dictionary)["child"] = RUNNING
			_select_next_sibling(parent_index, owner_state)
		elif parent_index >= 0:
			(frames[parent_index] as Dictionary)["child"] = SUCCEEDED
			(frames[parent_index] as Dictionary)["has_child"] = false
		else:
			tree_status = SUCCEEDED


# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------


func _record_block(tree: String, state_index: int, kind: String, reason: String) -> void:
	stats["blocks"] = int(stats["blocks"]) + 1
	var row: Dictionary = {"tree": tree, "state": state_index, "kind": kind, "reason": reason, "t": time_s, "tick": ticks}
	# Keep one row per (state, kind, reason): a 60 Hz block would otherwise grow
	# without bound and say the same thing.
	for existing: Dictionary in blocks:
		if int(existing.get("state", -1)) == state_index and str(existing.get("reason", "")) == reason:
			existing["count"] = int(existing.get("count", 1)) + 1
			return
	row["count"] = 1
	blocks.append(row)
	_emit({"kind": "block", "tree": tree, "state": state_index, "block": kind, "reason": reason})


func _emit(row: Dictionary) -> void:
	if trace == null:
		return
	row["tick"] = ticks
	row["t"] = time_s
	row["interpreter"] = tree_name
	for key: Variant in trace_context.keys():
		row[key] = trace_context[key]
	trace.push(row)


func _enter_name(result: int) -> String:
	match result:
		ENTER_OK:
			return "ok"
		ENTER_FALSE:
			return "false"
		ENTER_UNKNOWN:
			return "unknown"
	return "?"


static func frame_key(tree: String, state_index: int, state_name: String) -> String:
	return "%s/%d/%s" % [tree, state_index, state_name]
