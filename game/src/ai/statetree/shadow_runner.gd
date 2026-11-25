extends RefCounted
## Shadow StateTree runner (W9-P4 S1).
##
## `TAT2_STATETREE=off|shadow|patrol` (default `off`, read once per process):
##   off     - nothing is loaded and no per-tick work happens;
##   shadow  - every spawned guard runs one interpreter beside the FSM, reads
##             its state, and writes a structured trace. NOTHING is written back
##             to the guard: the interpreter has no reference to the guard except
##             through `guard_bindings.gd`, whose `mutates()` is false, and the
##             binding only calls getters/fields;
##   patrol  - reserved for the S2 cutover. `guard_ai.gd` checks the mode before
##             using the interpreter as the movement authority; until S2 lands
##             this behaves exactly like `shadow` and says so once.
##
## The trace sink is shared per process (`trace.gd`). `TAT2_STATETREE_TRACE`
## streams NDJSON to a path; without it the rows stay in memory for tests.
##
## Cost: one `Dictionary` snapshot + one interpreter tick per guard per physics
## frame. No allocation beyond the snapshot and the (event-only) trace rows.
##
## Determinism: the runner holds no RNG, no time-of-day and no instance-order
## dependence; its only inputs are the guard's own fields.

const TreeModel = preload("res://src/ai/statetree/tree_model.gd")
const Interpreter = preload("res://src/ai/statetree/interpreter.gd")
const Trace = preload("res://src/ai/statetree/trace.gd")
const GuardBindings = preload("res://src/ai/statetree/guard_bindings.gd")
const BindingsBase = preload("res://src/ai/statetree/bindings.gd")
const Coverage = preload("res://src/ai/statetree/coverage.gd")

const MODE_OFF: String = "off"
const MODE_SHADOW: String = "shadow"
const MODE_PATROL: String = "patrol"
const MODE_ENV: String = "TAT2_STATETREE"

## A state held this long is reported once as a stall (the FSM has no stuck
## timer for guards, RE-I-06; the shadow measures it instead of guessing).
const STALL_SECONDS: float = 20.0

## Root tree for a guard: the authored room tree, which links ST_Patrol.
const GUARD_ROOT: String = "ST_Guard"

static var _mode: String = ""
static var _library: Dictionary = {}
static var _patrol_note_emitted: bool = false

var guard: Node = null
var interpreter: RefCounted = null
var bindings: RefCounted = null
var started: bool = false
var start_failed: bool = false
var ticks: int = 0
var last_state: int = -1
var last_state_changed_t: float = 0.0
var stall_reported: bool = false
var stalls: int = 0
var max_state_seconds: float = 0.0


# ---------------------------------------------------------------------------
# Mode and library
# ---------------------------------------------------------------------------


static func mode() -> String:
	if _mode == "":
		_mode = parse_mode(OS.get_environment(MODE_ENV))
	return _mode


static func parse_mode(raw: String) -> String:
	var value: String = raw.strip_edges().to_lower()
	if value == "" or value == MODE_OFF:
		return MODE_OFF
	if value == MODE_SHADOW:
		return MODE_SHADOW
	if value == MODE_PATROL:
		return MODE_PATROL
	push_warning("TAT2_STATETREE='%s' is not off|shadow|patrol; using off" % raw)
	return MODE_OFF


static func enabled() -> bool:
	return mode() != MODE_OFF


## Test-only override. The env var stays the shipping switch; a test flips this
## before spawning guards and restores it with `set_mode_for_test("")`.
static func set_mode_for_test(value: String) -> void:
	_mode = value if value != "" else parse_mode(OS.get_environment(MODE_ENV))


static func library() -> Dictionary:
	if _library.is_empty():
		_library = TreeModel.load_library()
		if not bool(_library.get("ok", false)):
			var errors: Array = _library.get("errors", [])
			var first: String = str(errors[0]) if not errors.is_empty() else ""
			push_warning("StateTree library has %d validation errors (first: %s)" % [errors.size(), first])
	return _library


static func trees() -> Dictionary:
	return library().get("trees", {})


static func cleanup_static_caches() -> void:
	Trace.reset_shared()
	_library = {}
	_mode = ""
	_patrol_note_emitted = false


# ---------------------------------------------------------------------------
# Per-guard runner
# ---------------------------------------------------------------------------


## Create and start a shadow runner for one guard. Returns null when shadow mode
## is off or the tree cannot start, so the caller can keep a single null check.
static func attach(p_guard: Node) -> RefCounted:
	if not enabled():
		return null
	if mode() == MODE_PATROL and not _patrol_note_emitted:
		_patrol_note_emitted = true
		push_warning("TAT2_STATETREE=patrol: the S2 cutover is not enabled in this build; running shadow only")
	var runner: RefCounted = load("res://src/ai/statetree/shadow_runner.gd").new()
	runner.guard = p_guard
	runner._start()
	return runner


func _start() -> void:
	var lib: Dictionary = library()
	var tree_set: Dictionary = lib.get("trees", {})
	if not tree_set.has(GUARD_ROOT):
		start_failed = true
		return
	bindings = GuardBindings.new()
	bindings.setup(guard, tree_set)
	interpreter = Interpreter.new()
	interpreter.setup(tree_set, GUARD_ROOT, bindings, Trace.shared())
	interpreter.trace_context = {
		"guard": str(guard.name) if guard != null else "",
		"guard_id": int(guard.get_instance_id()) if guard != null else 0,
		"mode": mode(),
	}
	started = interpreter.start()
	start_failed = not started
	if started:
		last_state = interpreter.current_state()
		last_state_changed_t = 0.0


## Advance the shadow by one frame. Safe to call when the runner failed to start.
func tick(delta: float) -> void:
	if not started or interpreter == null:
		return
	ticks += 1
	bindings.observe(delta)
	interpreter.tick(delta)
	var state: int = interpreter.current_state()
	if state != last_state:
		last_state = state
		last_state_changed_t = interpreter.time_s
		stall_reported = false
	else:
		var held: float = interpreter.time_s - last_state_changed_t
		max_state_seconds = maxf(max_state_seconds, held)
		if held >= STALL_SECONDS and not stall_reported:
			stall_reported = true
			stalls += 1
			var rows: RefCounted = Trace.shared()
			rows.push({
				"kind": "stall",
				"tick": interpreter.ticks,
				"t": interpreter.time_s,
				"interpreter": GUARD_ROOT,
				"tree": interpreter.current_tree(),
				"state": state,
				"name": interpreter.current_state_name(),
				"path": interpreter.current_path(),
				"seconds": held,
				"guard": str(guard.name) if guard != null else "",
				"guard_id": int(guard.get_instance_id()) if guard != null else 0,
				"reason": "state held >= %.1f s" % STALL_SECONDS,
			})


## Flat summary for tests/probes.
func summary() -> Dictionary:
	if interpreter == null:
		return {"started": false, "reason": "no interpreter (shadow off or no library)"}
	return {
		"started": started,
		"guard": str(guard.name) if guard != null else "",
		"ticks": ticks,
		"interpreter_ticks": interpreter.ticks,
		"path": interpreter.current_path(),
		"state": interpreter.current_state(),
		"state_name": interpreter.current_state_name(),
		"frames": interpreter.frames.size(),
		"stats": interpreter.stats.duplicate(true),
		"blocks": interpreter.blocks.duplicate(true),
		"transitions_fired": interpreter.transitions_fired.size(),
		"visited": interpreter.visited.size(),
		"unknown_conditions": interpreter.unknown_conditions.duplicate(true),
		"stalls": stalls,
		"max_state_seconds": max_state_seconds,
	}


# ---------------------------------------------------------------------------
# Structural harness: start every authored tree once
# ---------------------------------------------------------------------------


## Start every tree in the payload, tick it `ticks` times with the base (all
## UNKNOWN/UNSUPPORTED) binding and record the trace. This is the "S1 shadow
## traces exist for all 21 trees" proof: it needs no guard, no map and no GPU,
## and every tree leaves at least a start row, an enter row and the block that
## stopped it.
##
## Returns {"traces": {tree: rows}, "started": n, "blocked": n, "rows": n,
##          "missing": [names]}.
static func trace_all_trees(p_ticks: int = 4) -> Dictionary:
	var lib: Dictionary = library()
	var tree_set: Dictionary = lib.get("trees", {})
	var sink: RefCounted = Trace.new()  # private sink: never mixes with a live run
	var names: Array = tree_set.keys()
	names.sort()
	var start_rows: Dictionary = {}
	var blocked: int = 0
	for tree_name: String in names:
		var bindings: RefCounted = BindingsBase.new()
		var interp: RefCounted = Interpreter.new()
		interp.setup(tree_set, tree_name, bindings, sink)
		interp.trace_context = {"guard": "", "guard_id": 0, "mode": "structural", "tree_root": tree_name}
		var ok: bool = interp.start()
		start_rows[tree_name] = ok
		if not ok:
			blocked += 1
		for _i: int in range(p_ticks):
			interp.tick(0.05)
	var traces: Dictionary = {}
	var missing: Array = []
	for tree_name: String in names:
		var rows: Array = sink.rows_for(tree_name)
		traces[tree_name] = rows
		if rows.is_empty():
			missing.append(tree_name)
	return {
		"traces": traces,
		"started": names.size() - blocked,
		"blocked": blocked,
		"rows": sink.count(),
		"missing": missing,
		"start_rows": start_rows,
		"summary": sink.summary(),
	}


## Coverage table for the payload with this build's guard bindings. Needs a
## guard instance only for `covers()`; pass null for the class-level table.
static func coverage(p_guard: Node = null) -> Dictionary:
	var tree_set: Dictionary = trees()
	var bindings: RefCounted = GuardBindings.new()
	bindings.setup(p_guard, tree_set)
	return Coverage.build(tree_set, bindings)
