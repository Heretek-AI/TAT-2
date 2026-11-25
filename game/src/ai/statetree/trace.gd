extends RefCounted
## Structured StateTree trace (W9-P4 S1).
##
## One row per event, never per frame: a 60 Hz mission with eight guards would
## otherwise write ~30,000 rows a second. Rows are emitted on start, state enter,
## state exit, transition (chosen or armed), a blocked task, and a condition the
## payload cannot evaluate. A per-tick row is available behind
## `every_tick = true` for tests and for the synthetic harness.
##
## Row shape (all rows):
##   kind       "start" | "enter" | "exit" | "transition" | "transition_armed"
##              | "transition_unmet" | "task_enter" | "task_block" |
##              "task_succeeded" | "condition_unknown" | "block" |
##              "linked_refused" | "tick"
##   tick, t    interpreter tick index and seconds
##   interpreter  the tree the interpreter was started on
##   tree, state, name, path, ...   kind-specific
##
## `TAT2_STATETREE_TRACE=/abs/path.ndjson` streams the rows to disk (flushed
## every 64 rows). Without it the rows stay in the ring buffer for a test to
## read; nothing about shadow mode requires a writable path.

const MAX_ROWS: int = 8192

var rows: Array[Dictionary] = []
var dropped: int = 0
var every_tick: bool = false
var path: String = ""

var _file: FileAccess = null
var _since_flush: int = 0

static var _shared: RefCounted = null


## The process-wide trace. Shadow guards share one sink so the whole mission
## lands in one file, ordered by tick.
static func shared() -> RefCounted:
	if _shared == null:
		_shared = load("res://src/ai/statetree/trace.gd").new()
		var configured: String = OS.get_environment("TAT2_STATETREE_TRACE")
		if configured != "":
			_shared.configure(configured)
	return _shared


static func reset_shared() -> void:
	if _shared != null:
		_shared.close()
	_shared = null


func configure(file_path: String) -> void:
	path = file_path
	if _file != null:
		_file.close()
		_file = null
	if file_path == "":
		return
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file == null:
		push_warning("StateTreeTrace: cannot write %s (err %d)" % [file_path, FileAccess.get_open_error()])


func close() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null


func clear() -> void:
	rows.clear()
	dropped = 0


func count() -> int:
	return rows.size()


func push(row: Dictionary) -> void:
	if rows.size() >= MAX_ROWS:
		dropped += 1
		# Keep the first MAX_ROWS rows: the start of a run is the part that
		# explains the branch choice, and a wrapped buffer would hide it.
		if _file == null:
			return
	if rows.size() < MAX_ROWS:
		rows.append(row)
	if _file != null:
		_file.store_line(JSON.stringify(row))
		_since_flush += 1
		if _since_flush >= 64:
			_file.flush()
			_since_flush = 0


func flush() -> void:
	if _file != null:
		_file.flush()
		_since_flush = 0


## Rows for one interpreter (all rows when `tree` is empty).
func rows_for(tree: String) -> Array:
	if tree == "":
		return rows
	var out: Array = []
	for row: Dictionary in rows:
		if str(row.get("interpreter", "")) == tree:
			out.append(row)
	return out


## Kinds histogram + the distinct trees/states/transitions seen. Measured, never
## asserted: the report quotes this.
func summary() -> Dictionary:
	var kinds: Dictionary = {}
	var trees: Dictionary = {}
	var states: Dictionary = {}
	var transitions: Dictionary = {}
	var unknowns: Dictionary = {}
	var blocks: Dictionary = {}
	for row: Dictionary in rows:
		var kind: String = str(row.get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		var tree: String = str(row.get("tree", row.get("interpreter", "")))
		if tree != "":
			trees[tree] = true
		if row.has("state"):
			states["%s:%s" % [tree, str(row.get("state", ""))]] = true
		if kind == "transition":
			var chosen: Dictionary = row.get("chosen", {})
			var key: String = "%s#%s" % [str(chosen.get("from_state", "")), str(chosen.get("transition", ""))]
			transitions[key] = int(transitions.get(key, 0)) + 1
		elif kind == "condition_unknown":
			var name: String = str(row.get("name", ""))
			unknowns[name] = int(unknowns.get(name, 0)) + 1
		elif kind == "block":
			var reason: String = str(row.get("reason", ""))
			blocks[reason] = int(blocks.get(reason, 0)) + 1
	var tree_list: Array = trees.keys()
	tree_list.sort()
	return {
		"rows": rows.size(),
		"dropped": dropped,
		"kinds": kinds,
		"trees": tree_list,
		"distinct_states": states.size(),
		"transitions": transitions.size(),
		"transition_rows": transitions,
		"unknown_conditions": unknowns,
		"blocks": blocks,
		"path": path,
	}


## Write the whole buffer as NDJSON (used by probes/tests; the runtime stream
## uses `configure`).
func to_ndjson(file_path: String) -> bool:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return false
	for row: Dictionary in rows:
		file.store_line(JSON.stringify(row))
	file.flush()
	file.close()
	return true
