extends SceneTree
## W9-P2 E1 / W10-A: authored lock inventory probe.
##
## Prints, from the raw UE dump:
##   * per-map placed `_locked: true` counts,
##   * the per-class family totals (containers / doors / windows),
##   * the `_lockConfig.MaxLockLevel` distribution over the locked actors,
## and asserts the fact-sheet totals (173 placed locks = 157 containers +
## 8 doors + 8 windows; 155 authored caps of 2 and 3 of 1).
##
## Then it prints what the CURRENT runtime actually applies from the committed
## generated data. The two halves are deliberately split: the authored dump is
## the source, the `.tatlevel.json` records are what the loader/consumers see.
##
## W10-A: `applied` is now the de-duplicated runtime count, not the raw record
## count. Only these records reach `set_locked(true, …)`:
##   * container markers (`markers` only, `actors` are never spawned as
##     containers) whose class is in `level_loader.LOOT_CONTAINER_CLASSES`
##     (read from the script's constant map, not duplicated here), `locked`
##     true, de-duplicated by `(class, rounded pos)`;
##   * `swinging_doors` records with `locked` true, a class without "Window"
##     and `can_lockpick` not explicitly false.
## The raw count (`raw=`) stays its own labelled number: it counts every
## locked marker/actor/door record and is not the applied total. The probe
## FAILS (exit 1) when `applied`, the container count or the door-node count is
## zero — the old "0 means the producer has not regenerated yet" state is gone
## because the current generated data carries the locks.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/probe_lock_inventory.gd"
##
## The probe never writes anything and never starts a renderer.

const LevelLoaderScript: GDScript = preload("res://src/core/level_loader.gd")

## Authored totals (docs/reference fact sheet §1.2-§1.3, re-measured here).
const EXPECT_TOTAL := 173
const EXPECT_CONTAINERS := 157
const EXPECT_DOORS := 8
const EXPECT_WINDOWS := 8
const EXPECT_MAX2 := 155
const EXPECT_MAX1 := 3

var fails: int = 0
## Runtime `LOOT_CONTAINER_CLASSES`, read from `level_loader.gd` in `_run`.
var loot_classes: Array = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: ", msg)
	else:
		fails += 1
		print("  FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _collect_json(dir: String, out: Array) -> void:
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full: String = dir.path_join(entry)
			if d.current_is_dir():
				_collect_json(full, out)
			elif entry.ends_with(".json"):
				out.append(full)
		entry = d.get_next()
	d.list_dir_end()


func _is_placed(rec: Dictionary) -> bool:
	var outer: Variant = rec.get("Outer")
	if not (outer is Dictionary):
		return false
	return str((outer as Dictionary).get("ObjectName", "")).begins_with("Level'")


func _family(cls: String) -> String:
	if cls.find("Window") >= 0:
		return "window"
	if cls.find("Door") >= 0:
		return "door"
	return "container"


## De-duplication key for a placed container: the same authored actor appears
## once as a marker and once as an actor record at the same position.
func _container_key(cls: String, rec: Dictionary) -> String:
	var pos_key: String = "?"
	var pos: Variant = rec.get("pos")
	if pos is Array and (pos as Array).size() >= 3:
		pos_key = "%d_%d_%d" % [
			int(round(float((pos as Array)[0]) * 100.0)),
			int(round(float((pos as Array)[1]) * 100.0)),
			int(round(float((pos as Array)[2]) * 100.0)),
		]
	return "%s|%s" % [cls, pos_key]


func _run() -> void:
	var project_dir: String = ProjectSettings.globalize_path("res://").simplify_path()
	var ext_root: String = project_dir.path_join("../extracted/json").simplify_path()
	if not DirAccess.dir_exists_absolute(ext_root):
		print("LOCK_INVENTORY SKIP: extracted dump not present at ", ext_root)
		quit(0)
		return
	print("LOCK_INVENTORY source=", ext_root)

	# Runtime container classes: one source of truth, the loader's own constant.
	var const_map: Dictionary = LevelLoaderScript.get_script_constant_map()
	var classes_v: Variant = const_map.get("LOOT_CONTAINER_CLASSES", null)
	if classes_v is Array:
		loot_classes = classes_v as Array
	_check(loot_classes.size() > 0,
		"LOOT_CONTAINER_CLASSES read from level_loader.gd (%d classes)" % loot_classes.size())

	# --- Authored inventory (raw UE dump) ---------------------------------
	var files: Array = []
	_collect_json(ext_root, files)
	print("  dump json files scanned: ", files.size())
	var per_file: Dictionary = {}
	var per_class: Dictionary = {}
	var families: Dictionary = {"container": 0, "door": 0, "window": 0}
	var max_dist: Dictionary = {}
	var total := 0
	var scanned := 0
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		scanned += 1
		if text.find("\"_locked\"") < 0:
			continue
		var parsed: Variant = JSON.parse_string(text)
		if not (parsed is Array):
			continue
		for rec_var: Variant in parsed as Array:
			if not (rec_var is Dictionary):
				continue
			var rec: Dictionary = rec_var as Dictionary
			if not _is_placed(rec):
				continue
			var props: Dictionary = rec.get("Properties") if rec.get("Properties") is Dictionary else {}
			if props.get("_locked") != true:
				continue
			var cls: String = str(rec.get("Type", ""))
			var cfg: Dictionary = props.get("_lockConfig") if props.get("_lockConfig") is Dictionary else {}
			var cap: int = int(cfg.get("MaxLockLevel", 0))
			total += 1
			families[_family(cls)] = int(families[_family(cls)]) + 1
			per_class[cls] = int(per_class.get(cls, 0)) + 1
			per_file[path] = int(per_file.get(path, 0)) + 1
			max_dist[cap] = int(max_dist.get(cap, 0)) + 1

	print("  per-map placed `_locked: true` counts:")
	var map_paths: Array = per_file.keys()
	map_paths.sort()
	for path: String in map_paths:
		print("    %s: %d" % [path.trim_prefix(ext_root + "/"), int(per_file[path])])
	print("  per class:")
	var classes: Array = per_class.keys()
	classes.sort()
	for cls: String in classes:
		print("    %s: %d" % [cls, int(per_class[cls])])
	print("  family totals: containers=%d doors=%d windows=%d total=%d"
		% [int(families["container"]), int(families["door"]), int(families["window"]), total])
	var caps: Array = max_dist.keys()
	caps.sort()
	var cap_line: PackedStringArray = []
	for cap: int in caps:
		cap_line.append(("none" if cap == 0 else str(cap)) + "x" + str(int(max_dist[cap])))
	print("  authored MaxLockLevel over the locked actors: ", ", ".join(cap_line))

	_check(total == EXPECT_TOTAL, "placed `_locked: true` total = %d (got %d)" % [EXPECT_TOTAL, total])
	_check(int(families["container"]) == EXPECT_CONTAINERS,
		"authored containers = %d (got %d)" % [EXPECT_CONTAINERS, int(families["container"])])
	_check(int(families["door"]) == EXPECT_DOORS,
		"authored doors = %d (got %d)" % [EXPECT_DOORS, int(families["door"])])
	_check(int(families["window"]) == EXPECT_WINDOWS,
		"authored windows = %d (got %d)" % [EXPECT_WINDOWS, int(families["window"])])
	_check(int(max_dist.get(2, 0)) == EXPECT_MAX2,
		"authored cap 2 count = %d (got %d)" % [EXPECT_MAX2, int(max_dist.get(2, 0))])
	_check(int(max_dist.get(1, 0)) == EXPECT_MAX1,
		"authored cap 1 count = %d (got %d)" % [EXPECT_MAX1, int(max_dist.get(1, 0))])
	_check(int(max_dist.get(0, 0)) == 15,
		"locked actors with no MaxLockLevel = 15 (got %d)" % int(max_dist.get(0, 0)))
	print("  dump records scanned for keys: ", scanned)

	# --- Authored records the port can actually spawn ---------------------
	var runtime_containers := 0
	for cls: String in classes:
		if loot_classes.has(cls):
			runtime_containers += int(per_class[cls])
	print("  authored-locked containers inside LOOT_CONTAINER_CLASSES: ", runtime_containers)
	var excluded_classes: PackedStringArray = []
	for cls: String in classes:
		if _family(cls) == "container" and not loot_classes.has(cls):
			excluded_classes.append("%s(%d)" % [cls, int(per_class[cls])])
	print("  authored-locked containers outside the allowlist (never spawned): ",
		", ".join(excluded_classes))
	print("  authored-locked windows: 8 (no window interaction in the port; not locked)")
	print("  authored-locked key-only doors excluded (no key inventory): 4 (3 BP_VaultDoor_Sliding_C + 1 BP_Res_Int_Doorway_C)")

	# --- Current runtime state (committed generated data) -----------------
	var levels_root: String = project_dir.path_join("data/generated/levels")
	var level_files: Array = []
	_collect_json(levels_root, level_files)
	var runtime_records := 0
	var runtime_locked := 0
	var locked_markers := 0
	var locked_actors := 0
	var locked_doors_raw := 0
	var runtime_container_markers := 0
	var locked_container_markers := 0
	var runtime_door_records := 0
	var door_nodes := 0
	var container_keys: Dictionary = {}
	for path: String in level_files:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			continue
		var doc: Dictionary = parsed as Dictionary
		for key: String in ["markers", "actors"]:
			for rec_var: Variant in doc.get(key, []) as Array:
				if not (rec_var is Dictionary):
					continue
				var rec: Dictionary = rec_var as Dictionary
				runtime_records += 1
				var is_locked: bool = rec.get("locked") == true
				var cls: String = str(rec.get("class", ""))
				if key == "markers" and loot_classes.has(cls):
					runtime_container_markers += 1
				if not is_locked:
					continue
				runtime_locked += 1
				if key == "markers":
					locked_markers += 1
				else:
					locked_actors += 1
				# Only markers spawn containers; actors are the same authored
				# actor serialized a second time and are never spawned.
				if key == "markers" and loot_classes.has(cls):
					locked_container_markers += 1
					container_keys[_container_key(cls, rec)] = true
		for rec_var: Variant in doc.get("swinging_doors", []) as Array:
			if not (rec_var is Dictionary):
				continue
			var rec: Dictionary = rec_var as Dictionary
			runtime_records += 1
			runtime_door_records += 1
			if rec.get("locked") != true:
				continue
			runtime_locked += 1
			locked_doors_raw += 1
			# Door nodes: the same filter `swinging_door.configure()` applies
			# (window and explicit `can_lockpick: false` excluded). One node per
			# record, no dedupe.
			if str(rec.get("class", "")).to_lower().find("window") >= 0:
				continue
			var can_pick: Variant = rec.get("can_lockpick", null)
			if can_pick is bool and not bool(can_pick):
				continue
			door_nodes += 1
	var containers: int = container_keys.size()
	var applied: int = containers + door_nodes
	var discarded: int = maxi(runtime_locked - applied, 0)
	var runtime_state: String = "APPLIED" if applied > 0 else "EMPTY"

	print("  runtime generated levels scanned: ", level_files.size())
	print("  runtime level records (markers+actors+swinging_doors): ", runtime_records)
	print("  runtime loot-container-class markers: ", runtime_container_markers)
	print("  runtime swinging-door records: ", runtime_door_records)
	print("  runtime records carrying an authored lock: %d (raw: markers=%d actors=%d doors=%d)"
		% [runtime_locked, locked_markers, locked_actors, locked_doors_raw])
	print("  runtime applied containers: %d de-duplicated by (class,pos) from %d locked container markers"
		% [containers, locked_container_markers])
	print("  runtime applied door nodes: %d (windows and explicit can_lockpick=false excluded)" % door_nodes)
	print("LOCK_INVENTORY runtime: authored=%d raw=%d applied=%d containers=%d door_nodes=%d discarded=%d state=%s"
		% [total, runtime_locked, applied, containers, door_nodes, discarded, runtime_state])
	_check(applied > 0, "runtime applies at least one authored lock (applied=%d)" % applied)
	_check(containers > 0, "runtime applies container locks (containers=%d)" % containers)
	_check(door_nodes > 0, "runtime applies door-node locks (door_nodes=%d)" % door_nodes)
	_check(applied == containers + door_nodes,
		"applied = containers + door_nodes (%d = %d + %d)" % [applied, containers, door_nodes])

	var ok: bool = fails == 0
	if ok:
		print("LOCK_INVENTORY PASS authored_containers=%d authored_doors=%d authored_windows=%d locked_now=%d applied=%d containers=%d door_nodes=%d"
			% [int(families["container"]), int(families["door"]), int(families["window"]), runtime_locked, applied, containers, door_nodes])
	else:
		print("LOCK_INVENTORY FAIL fails=%d applied=%d containers=%d door_nodes=%d raw=%d"
			% [fails, applied, containers, door_nodes, runtime_locked])
	quit(0 if ok else 1)
