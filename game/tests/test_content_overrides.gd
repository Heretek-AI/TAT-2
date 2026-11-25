extends SceneTree
## W6T static content-override test (no Godot scene/asset load).
##
## The graybox P0 + 3rd-floor re-materialisation lives in one tracked table,
## `game/data/expansion/content_overrides.json`, applied by
## `tools/parse_tables.py` before each `.tatlevel.json` is written. This test
## pins the invariants the Python producer/checker rely on, so a hand-edit that
## breaks the contract fails in the engine test suite too:
##
## 1. schema, unique ids, set_material/add_cap only;
## 2. only graybox kit meshes (declared prefixes) may be targeted;
## 3. every material is an authored entry in materials.json;
## 4. expect_count > 0 and expect_changed <= expect_count (no no-op rule);
## 5. add_cap never touches a W5B roof-census level (PeripheryA), so the
##    733/46/334/399/0 roof-collision census cannot silently change;
## 6. when generated levels exist, the applied report counts match the table
##    and every `content_rule`-tagged instance carries the rule material.
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_content_overrides.gd

const TABLE_PATH := "res://data/expansion/content_overrides.json"
const MATERIALS_PATH := "res://data/generated/materials.json"
const LEVELS_ROOT := "res://data/generated/levels"
const REPORT_PATH := "res://data/generated/content_overrides_applied.json"
const ROOF_CENSUS_LEVEL := "Guildhall/Guildhall_PeripheryA"

var fails: int = 0
var table: Dictionary = {}


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed


## GDScript's `a or []` yields a bool (unlike Python), so a typed `Array = v or []`
## is a runtime type error and `for x in (v or [])` iterates a bool. Read JSON
## lists through this helper so the loops actually run.
static func _arr(v: Variant) -> Array:
	return v as Array if v is Array else []


func _initialize() -> void:
	var raw: Variant = _read_json(TABLE_PATH)
	if not (raw is Dictionary):
		printerr("FAIL: cannot read ", TABLE_PATH)
		print("CONTENT_OVERRIDES_SUMMARY: fails=1")
		quit(1)
		return
	table = raw as Dictionary
	check_schema()
	check_rules()
	check_caps()
	check_coverage_regions()
	check_applied_output()
	print("CONTENT_OVERRIDES_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


func check_schema() -> void:
	_check(str(table.get("schema", "")) == "tat2.content_overrides/1",
		"schema is tat2.content_overrides/1",
		"schema is %s" % str(table.get("schema", "")))
	var prefixes: Array = _arr(table.get("graybox_prefixes"))
	_check(not prefixes.is_empty(), "graybox_prefixes declared", "no graybox_prefixes")
	var rules: Array = _arr(table.get("rules"))
	_check(not rules.is_empty(), "%d override rules" % rules.size(), "no override rules")


func _is_graybox(mesh: String) -> bool:
	for prefix: Variant in _arr(table.get("graybox_prefixes")):
		if mesh.begins_with(str(prefix)):
			return true
	return false


func check_rules() -> void:
	var materials: Variant = _read_json(MATERIALS_PATH)
	var has_materials: bool = materials is Dictionary
	var ids := {}
	var noop := 0
	var compass := 0
	for rv: Variant in _arr(table.get("rules")):
		var r: Dictionary = rv as Dictionary
		var rid: String = str(r.get("id", ""))
		_check(not rid.is_empty(), "rule id present", "a rule has no id")
		_check(not ids.has(rid), "rule id unique: %s" % rid, "duplicate rule id: %s" % rid)
		ids[rid] = true
		_check(str(r.get("op", "")) == "set_material",
			"%s op is set_material" % rid, "%s has unsupported op %s" % [rid, str(r.get("op", ""))])
		var meshes: Array = _arr(r.get("meshes"))
		_check(not meshes.is_empty(), "%s targets a mesh" % rid, "%s has no meshes" % rid)
		for mv: Variant in meshes:
			_check(_is_graybox(str(mv)), "%s graybox-only: %s" % [rid, str(mv).get_file()],
				"%s targets non-graybox mesh %s" % [rid, str(mv)])
		var mat: String = str(r.get("material", ""))
		_check(mat.begins_with("/Game/"), "%s material path is an authored /Game path" % rid,
			"%s material is malformed: %s" % [rid, mat])
		if has_materials:
			_check((materials as Dictionary).has(mat), "%s material exists in materials.json" % rid,
				"%s material missing from materials.json: %s" % [rid, mat])
		var count: int = int(r.get("expect_count", -1))
		var changed: int = int(r.get("expect_changed", count))
		_check(count > 0, "%s expect_count=%d" % [rid, count], "%s expect_count is not positive" % rid)
		_check(changed >= 0 and changed <= count, "%s expect_changed=%d <= %d" % [rid, changed, count],
			"%s expect_changed %d is out of range for %d" % [rid, changed, count])
		if changed == 0:
			noop += 1
		if str(r.get("material", "")).ends_with("MI_ConcreteB"):
			compass += 1
	_check(noop == 0, "no no-op rule (expect_changed=0)", "%d rule(s) would be a no-op" % noop)
	_check(compass > 0, "ConcreteB used for structure/deck floors (%d rules)" % compass,
		"no rule uses the authored MI_ConcreteB material")


func check_caps() -> void:
	var caps: Array = _arr(table.get("add_caps"))
	for cv: Variant in caps:
		var cap: Dictionary = cv as Dictionary
		var cid: String = str(cap.get("id", ""))
		_check(not cid.is_empty(), "add_cap id present", "an add_cap has no id")
		_check(_is_graybox(str(cap.get("mesh", ""))), "%s add_cap graybox-only" % cid,
			"%s add_cap targets a non-graybox mesh" % cid)
		var declared: int = int(cap.get("expect_count", -1))
		_check(declared == _arr(cap.get("caps")).size(), "%s add_cap count %d" % [cid, declared],
			"%s add_cap count %d != %d caps" % [cid, declared, _arr(cap.get("caps")).size()])
		for lv: Variant in _arr(cap.get("levels")):
			_check(str(lv) != ROOF_CENSUS_LEVEL, "%s add_cap avoids the roof census level" % cid,
				"%s add_cap touches roof-census level %s" % [cid, str(lv)])


func check_coverage_regions() -> void:
	var regions: Array = _arr(table.get("coverage_regions"))
	_check(not regions.is_empty(), "%d coverage regions declared" % regions.size(),
		"no coverage_regions declared")
	for rv: Variant in regions:
		var region: Dictionary = rv as Dictionary
		var rid: String = str(region.get("id", ""))
		_check(not rid.is_empty(), "coverage region id present", "a coverage_region has no id")
		_check(not _arr(region.get("meshes")).is_empty(), "%s names its meshes" % rid,
			"%s has no meshes" % rid)
		for mv: Variant in _arr(region.get("meshes")):
			_check(_is_graybox(str(mv)), "%s coverage mesh is graybox" % rid,
				"%s coverage mesh is not graybox: %s" % [rid, str(mv)])
		# The 2x2 floor is the P0 greybox check for every floor region.
		var floors: Array = _arr(region.get("meshes"))
		_check(floors.has("/Game/Test/LevelKits/Graybox/GB_Floor_2x2") or rid.begins_with("missionlobby"),
			"%s tracks GB_Floor_2x2 coverage" % rid,
			"%s does not track GB_Floor_2x2" % rid)


func check_applied_output() -> void:
	if not DirAccess.dir_exists_absolute(LEVELS_ROOT):
		print("SKIP: generated levels absent (private extract); table checks only")
		return
	var report_raw: Variant = _read_json(REPORT_PATH)
	_check(report_raw is Dictionary, "applied report exists", "missing applied report %s" % REPORT_PATH)
	if not (report_raw is Dictionary):
		return
	var rows := {}
	for rv: Variant in _arr((report_raw as Dictionary).get("rules")):
		var row: Dictionary = rv as Dictionary
		rows[str(row.get("id", ""))] = row
	var applied := 0
	for rv: Variant in _arr(table.get("rules")):
		var rule: Dictionary = rv as Dictionary
		var rid: String = str(rule.get("id", ""))
		var row: Variant = rows.get(rid)
		_check(row != null, "%s applied" % rid, "%s missing from applied report" % rid)
		if row == null:
			continue
		applied += 1
		var matched: int = int((row as Dictionary).get("matched", -1))
		var changed: int = int((row as Dictionary).get("changed", -1))
		_check(matched == int(rule.get("expect_count", -2)),
			"%s applied matched=%d" % [rid, matched],
			"%s matched %d != expect_count %d" % [rid, matched, int(rule.get("expect_count", -2))])
		_check(changed == int(rule.get("expect_changed", -2)),
			"%s applied changed=%d" % [rid, changed],
			"%s changed %d != expect_changed %d" % [rid, changed, int(rule.get("expect_changed", -2))])
		var level_key: String = str((row as Dictionary).get("level", ""))
		var payload: Variant = _read_json("%s/%s.tatlevel.json" % [LEVELS_ROOT, level_key])
		if not (payload is Dictionary):
			_check(false, "%s level present" % rid, "%s level payload missing: %s" % [rid, level_key])
			continue
		var tagged := 0
		for mv: Variant in _arr((payload as Dictionary).get("meshes")):
			if not (mv is Dictionary):
				continue
			var entry: Dictionary = mv as Dictionary
			if str(entry.get("content_rule", "")) != rid:
				continue
			tagged += 1
			_check(str(entry.get("override_material", "")) == str(rule.get("material", "")),
				"%s tagged instance carries its authored material" % rid,
				"%s leaf %s has %s" % [rid, str(entry.get("mesh", "")).get_file(), str(entry.get("override_material", ""))])
			_check(_is_graybox(str(entry.get("mesh", ""))),
				"%s rewrote a graybox mesh" % rid,
				"%s rewrote non-graybox %s" % [rid, str(entry.get("mesh", ""))])
		_check(tagged == changed, "%s tag count=%d" % [rid, tagged],
			"%s tag count %d != changed %d" % [rid, tagged, changed])
	_check(applied == _arr(table.get("rules")).size(),
		"%d/%d rules applied" % [applied, _arr(table.get("rules")).size()],
		"only %d/%d rules applied" % [applied, _arr(table.get("rules")).size()])
