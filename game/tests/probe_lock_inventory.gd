extends SceneTree
## W9-P2 E1: authored lock inventory probe.
##
## Prints, from the raw UE dump:
##   * per-map placed `_locked: true` counts,
##   * the per-class family totals (containers / doors / windows),
##   * the `_lockConfig.MaxLockLevel` distribution over the locked actors,
## and asserts the fact-sheet totals (173 placed locks = 157 containers +
## 8 doors + 8 windows; 155 authored caps of 2 and 3 of 1).
##
## Then it prints the CURRENT runtime state from the committed generated data.
## Those are deliberately split: the producer contract
## (build/qa/w9/b2-producer-contract.md) is NOT in the tree yet, so no authored
## lock reaches a `.tatlevel.json` record until the integrator regenerates at
## merged HEAD. `locked_now=0` is therefore the expected pre-regeneration value,
## not a failure of this probe.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/probe_lock_inventory.gd"
##
## The probe never writes anything and never starts a renderer.

const ALLOWLIST: Array[String] = [
	"BP_ChestTrunk_MajorLoot_C",
	"BP_DisplayCaseA_MajorLoot_C",
	"BP_LootStashInteractable_Secret_ThinWall_C",
	"BP_Storefront_DisplayCaseB_MinorLoot_C",
	"BP_Storefront_DisplayCaseD_MinorLoot_C",
]

## Authored totals (docs/reference fact sheet §1.2-§1.3, re-measured here).
const EXPECT_TOTAL := 173
const EXPECT_CONTAINERS := 157
const EXPECT_DOORS := 8
const EXPECT_WINDOWS := 8
const EXPECT_MAX2 := 155
const EXPECT_MAX1 := 3

var fails: int = 0


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


func _run() -> void:
	var project_dir: String = ProjectSettings.globalize_path("res://").simplify_path()
	var ext_root: String = project_dir.path_join("../extracted/json").simplify_path()
	if not DirAccess.dir_exists_absolute(ext_root):
		print("LOCK_INVENTORY SKIP: extracted dump not present at ", ext_root)
		quit(0)
		return
	print("LOCK_INVENTORY source=", ext_root)

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
		if ALLOWLIST.has(cls):
			runtime_containers += int(per_class[cls])
	print("  authored-locked containers inside LOOT_CONTAINER_CLASSES: ", runtime_containers)
	var excluded_classes: PackedStringArray = []
	for cls: String in classes:
		if _family(cls) == "container" and not ALLOWLIST.has(cls):
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
	var runtime_container_markers := 0
	var runtime_door_records := 0
	for path: String in level_files:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			continue
		var doc: Dictionary = parsed as Dictionary
		for key: String in ["markers", "actors"]:
			for rec_var: Variant in doc.get(key, []) as Array:
				if rec_var is Dictionary:
					var rec: Dictionary = rec_var as Dictionary
					runtime_records += 1
					if rec.get("locked") == true:
						runtime_locked += 1
					if ALLOWLIST.has(str(rec.get("class", ""))):
						runtime_container_markers += 1
		for rec_var: Variant in doc.get("swinging_doors", []) as Array:
			if rec_var is Dictionary:
				runtime_records += 1
				runtime_door_records += 1
				if (rec_var as Dictionary).get("locked") == true:
					runtime_locked += 1

	print("  runtime generated levels scanned: ", level_files.size())
	print("  runtime level records (markers+actors+swinging_doors): ", runtime_records)
	print("  runtime loot-container-class markers: ", runtime_container_markers)
	print("  runtime swinging-door records: ", runtime_door_records)
	print("  runtime records carrying an authored lock: ", runtime_locked)
	# The authored dump and the runtime generated data are deliberately split:
	# 0 means the producer contract has not been applied/regenerated yet (this
	# branch), non-zero means it has (integrator tree). Neither is a failure.
	var runtime_state: String = ("BLOCKED-ON-INTEGRATOR-REGENERATION"
		if runtime_locked == 0 else "APPLIED")
	print("LOCK_INVENTORY runtime: authored=%d applied=%d state=%s"
		% [total, runtime_locked, runtime_state])
	if runtime_locked == 0:
		print("  (the producer contract is not in the tree; regeneration at merged HEAD applies it)")

	var ok: bool = fails == 0
	if ok:
		print("LOCK_INVENTORY PASS authored_containers=%d authored_doors=%d authored_windows=%d locked_now=%d"
			% [int(families["container"]), int(families["door"]), int(families["window"]), runtime_locked])
	else:
		print("LOCK_INVENTORY FAIL fails=%d locked_now=%d" % [fails, runtime_locked])
	quit(0 if ok else 1)
