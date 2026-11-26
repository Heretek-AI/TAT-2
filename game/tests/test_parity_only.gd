extends SceneTree
## P0b parity-only governance contract test (standalone, not registered in
## `run_tests.gd`; Lane H owns the harness). Run:
##
##   tools/godot --headless --path game --script res://tests/test_parity_only.gd
##
## Proves:
## 1. every `content_overrides` rule is classified (`parity_restoration` for the
##    graybox -> authored-material rules, `tat2_expansion` for new content) and
##    an unclassified rule is refused by the producer/checker and skipped with a
##    counted diagnostic at runtime (never a crash);
## 2. `TAT2_PARITY_ONLY=1` excludes every registered expansion record/node
##    (prep skyline, Spider personal quest, co-op transport, briefing overrides,
##    candle-fire nodes) and every expansion-class content rule; off includes
##    them and changes nothing;
## 3. the graybox restoration rules still apply in parity-only (all 133 tagged
##    instances across the rule levels are kept);
## 4. no shipped marker/guard/GC/loot record is dropped: every non-mesh payload
##    key is returned unchanged by the parity-only mesh filter.
##
## Generated-level checks are a loud SKIP when the private extract is absent
## (hosted tooling has no `game/data/generated`).

const Governance := preload("res://src/core/parity_governance.gd")

const TABLE_PATH: String = "res://data/expansion/content_overrides.json"
const LEVELS_ROOT: String = "res://data/generated/levels"
const LOOT_KINDS: Array[String] = ["loot", "minor_loot", "major_loot", "quest", "chest", "displaycase", "lockbox", "clue"]

## Loaded in `_run` after one frame: a `--script` bootstrap compiles top-level
## preloads before the autoload singletons (AudioManager, GameState) exist, so
## a preload here would break the very scripts under test.
var PersonalQuestScript: GDScript
var NetManagerScript: GDScript
var MissionPrepScript: GDScript

var fails: int = 0
var passes: int = 0
var table: Dictionary = {}
var rule_classes: Dictionary = {}
var class_counts: Dictionary = {}


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		passes += 1
		print("PASS: ", ok_msg)
	else:
		fails += 1
		printerr("FAIL: ", fail_msg)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _arr(v: Variant) -> Array:
	return v as Array if v is Array else []


func _set_parity(on: bool) -> void:
	OS.set_environment(Governance.ENV_FLAG, "1" if on else "0")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	PersonalQuestScript = load("res://src/quests/personal_quest.gd") as GDScript
	NetManagerScript = load("res://src/core/net_manager.gd") as GDScript
	MissionPrepScript = load("res://src/ui/mission_prep_ui.gd") as GDScript
	var raw: Variant = _read_json(TABLE_PATH)
	if not (raw is Dictionary):
		printerr("FAIL: cannot read ", TABLE_PATH)
		print("PARITY_ONLY_SUMMARY: fails=1 passed=0")
		quit(1)
		return
	table = raw as Dictionary
	check_table_classes()
	rule_classes = Governance.load_rule_classes()
	check_rule_class_map()
	check_parity_only_excludes()
	check_off_includes()
	check_runtime_filter_contract()
	check_generated_levels()
	_set_parity(false)
	_check(not Governance.enabled(), "flag off restores the shipped path",
		"flag stayed on after _set_parity(false)")
	print("PARITY_ONLY_SUMMARY: fails=%d passed=%d rules=%d restoration=%d expansion=%d"
		% [fails, passes, class_counts.get("total", 0),
			class_counts.get(Governance.PARITY_RESTORATION, 0),
			class_counts.get(Governance.TAT2_EXPANSION, 0)])
	quit(0 if fails == 0 else 1)


## 1. Every rule has a known class. The owner's decision classifies every
## graybox -> authored-material rule as a parity restoration, so that population
## is asserted by construction, not by a hard-coded id list.
func check_table_classes() -> void:
	_check(str(table.get("schema", "")) == "tat2.content_overrides/1",
		"content_overrides schema is tat2.content_overrides/1",
		"content_overrides schema is %s" % str(table.get("schema", "")))
	var declared: Array = _arr(table.get("parity_classes"))
	_check(declared == [Governance.PARITY_RESTORATION, Governance.TAT2_EXPANSION],
		"parity_classes declares both classes",
		"parity_classes is %s" % str(declared))
	var prefixes: Array = _arr(table.get("graybox_prefixes"))
	var rules: Array = _arr(table.get("rules"))
	_check(not rules.is_empty(), "%d content-override rules" % rules.size(),
		"content_overrides has no rules")
	var unclassified: Array[String] = []
	var bad_restoration: Array[String] = []
	class_counts.clear()
	class_counts["total"] = rules.size()
	for rv: Variant in rules:
		var rule: Dictionary = rv as Dictionary
		var rid: String = str(rule.get("id", ""))
		var parity_class: String = str(rule.get("parity_class", ""))
		if not Governance.is_parity_class(parity_class):
			unclassified.append("%s=%s" % [rid, parity_class])
			continue
		class_counts[parity_class] = int(class_counts.get(parity_class, 0)) + 1
		var graybox_only: bool = true
		for mv: Variant in _arr(rule.get("meshes")):
			var mesh: String = str(mv)
			var matched: bool = false
			for pv: Variant in prefixes:
				if mesh.begins_with(str(pv)):
					matched = true
					break
			if not matched:
				graybox_only = false
				break
		var authored: bool = str(rule.get("material", "")).begins_with("/Game/")
		if graybox_only and authored and parity_class != Governance.PARITY_RESTORATION:
			bad_restoration.append("%s=%s" % [rid, parity_class])
	_check(unclassified.is_empty(),
		"every rule has a known parity_class (%d/%d classified)" % [rules.size(), rules.size()],
		"unclassified rule(s): %s" % ", ".join(unclassified))
	_check(bad_restoration.is_empty(),
		"every graybox -> authored-material rule is parity_restoration",
		"graybox restoration rule(s) not labelled %s: %s"
			% [Governance.PARITY_RESTORATION, ", ".join(bad_restoration)])
	_check(int(class_counts.get(Governance.PARITY_RESTORATION, 0)) > 0,
		"%d parity_restoration rule(s)" % int(class_counts.get(Governance.PARITY_RESTORATION, 0)),
		"no parity_restoration rule")
	if int(class_counts.get(Governance.TAT2_EXPANSION, 0)) == 0:
		print("NOTE: no tat2_expansion content-override rule exists today; "
			+ "the expansion class is exercised by the synthetic rule below")


func check_rule_class_map() -> void:
	var rules: Array = _arr(table.get("rules"))
	_check(rule_classes.size() == rules.size(),
		"runtime rule map covers every rule (%d)" % rule_classes.size(),
		"runtime rule map covers %d/%d rules" % [rule_classes.size(), rules.size()])
	var mismatched: Array[String] = []
	for rv: Variant in rules:
		var rule: Dictionary = rv as Dictionary
		var rid: String = str(rule.get("id", ""))
		if str(rule_classes.get(rid, "")) != str(rule.get("parity_class", "")):
			mismatched.append(rid)
	_check(mismatched.is_empty(), "runtime rule map classes match the table",
		"runtime rule map mismatch: %s" % ", ".join(mismatched))


## 2a. Parity-only excludes every registered expansion record and node.
func check_parity_only_excludes() -> void:
	_set_parity(true)
	_check(Governance.enabled(), "TAT2_PARITY_ONLY=1 enables parity-only",
		"TAT2_PARITY_ONLY=1 did not enable parity-only")
	var missing: Array[String] = []
	var allowed: Array[String] = []
	var owner_gate: Array[String] = []
	for rv: Variant in Governance.EXPANSION_RECORDS:
		var rec: Dictionary = rv as Dictionary
		var path: String = str(rec.get("path", ""))
		if not FileAccess.file_exists(path):
			missing.append(path)
		if Governance.record_allowed(path):
			allowed.append(path)
		var owner: String = str(rec.get("owner", ""))
		if not FileAccess.file_exists(owner):
			owner_gate.append("%s (missing)" % owner)
		else:
			var src: String = FileAccess.get_file_as_string(owner)
			if src.find("ParityGovernance") < 0:
				owner_gate.append("%s (no gate)" % owner)
	_check(missing.is_empty(), "%d expansion records exist" % Governance.EXPANSION_RECORDS.size(),
		"missing expansion record(s): %s" % ", ".join(missing))
	_check(allowed.is_empty(), "%d expansion records excluded in parity-only" % Governance.EXPANSION_RECORDS.size(),
		"parity-only still allows: %s" % ", ".join(allowed))
	_check(owner_gate.is_empty(), "every expansion record owner consults ParityGovernance",
		"owner gate missing: %s" % ", ".join(owner_gate))
	_check(not Governance.expansion_nodes_allowed(),
		"expansion node kinds excluded in parity-only",
		"expansion node kinds still allowed in parity-only")
	_check(not Governance.expansion_node_kind_allowed("candle_flame"),
		"candle_flame node excluded in parity-only",
		"candle_flame node still allowed in parity-only")
	_check(not Governance.coop_transport_allowed(),
		"co-op transport excluded in parity-only",
		"co-op transport still allowed in parity-only")

	var gs: Node = root.get_node_or_null("/root/GameState")
	_check(gs != null, "GameState autoload present", "GameState autoload missing")
	if gs != null:
		_check(bool(gs.call("parity_only")), "GameState.parity_only() mirrors the flag",
			"GameState.parity_only() is false in parity-only")
		_check(not bool(gs.call("coop_transport_available")),
			"GameState.coop_transport_available() is false in parity-only",
			"GameState.coop_transport_available() is true in parity-only")

	# Personal quest: chain, deploy and hub hooks are inert.
	_check(PersonalQuestScript.chain().is_empty(),
		"personal_spider chain is empty in parity-only",
		"personal_spider chain is still populated in parity-only")
	var pq: Dictionary = PersonalQuestScript.on_deploy("guildhall")
	_check(str(pq.get("reason", "")) == "parity_only" and _arr(pq.get("plan")).is_empty(),
		"personal quest deploy is a counted no-op in parity-only",
		"personal quest deploy returned %s" % str(pq.get("reason", "")))
	var hub: Dictionary = PersonalQuestScript.on_hub_enter()
	_check(str(hub.get("reason", "")) == "parity_only",
		"personal quest hub hook is a counted no-op in parity-only",
		"personal quest hub hook returned %s" % str(hub.get("reason", "")))

	# Prep skyline loader returns {} (0 pieces). The stage keeps the authored sky.
	var prep: Node = MissionPrepScript.new()
	var sky: Dictionary = prep.call("_load_prep_skyline") as Dictionary
	prep.free()
	_check(sky.is_empty(), "prep skyline is excluded in parity-only (0 pieces)",
		"prep skyline still loads %d key(s) in parity-only" % sky.size())

	# Briefing overrides are excluded; the authored QG endgame value wins.
	var gd: Node = root.get_node_or_null("/root/GameData")
	_check(gd != null, "GameData autoload present", "GameData autoload missing")
	if gd != null:
		gd.call("_load_briefing_overrides")
		var ov: Dictionary = gd.get("briefing_overrides") as Dictionary
		_check(ov.is_empty(), "briefing overrides excluded in parity-only",
			"briefing overrides still load %d row(s) in parity-only" % ov.size())
		var plan: Dictionary = gd.call("get_mission_plan", "Mission.Guildhall.LootTheRoom") as Dictionary
		if not plan.is_empty():
			var secs: float = float(gd.call("get_mission_endgame_seconds", "Mission.Guildhall.LootTheRoom", -1))
			_check(is_equal_approx(secs, float(plan.get("endgame_duration", -1.0))),
				"parity-only endgame window is the authored QG value (%.0f s)" % secs,
				"parity-only endgame window %.0f s != QG %.0f s"
					% [secs, float(plan.get("endgame_duration", -1.0))])

	# Co-op transport refuses to open a socket.
	var net: Node = NetManagerScript.new()
	var host_err: int = int(net.call("host", 0))
	var join_err: int = int(net.call("join", "127.0.0.1", 0))
	net.free()
	_check(host_err == ERR_UNAVAILABLE, "co-op host refused in parity-only",
		"co-op host returned %d, expected ERR_UNAVAILABLE" % host_err)
	_check(join_err == ERR_UNAVAILABLE, "co-op join refused in parity-only",
		"co-op join returned %d, expected ERR_UNAVAILABLE" % join_err)

	# A new-content rule found in the parity-only path is skipped, not applied.
	for rv: Variant in _arr(table.get("rules")):
		var rule: Dictionary = rv as Dictionary
		if str(rule.get("parity_class", "")) == Governance.PARITY_RESTORATION:
			_check(Governance.rule_applies(rule),
				"%s parity_restoration still applies in parity-only" % str(rule.get("id", "")),
				"%s restoration was dropped in parity-only" % str(rule.get("id", "")))
	var synthetic_expansion: Dictionary = {"id": "synthetic-expansion", "parity_class": Governance.TAT2_EXPANSION}
	_check(not Governance.rule_applies(synthetic_expansion),
		"synthetic tat2_expansion rule is excluded in parity-only",
		"synthetic tat2_expansion rule still applies in parity-only")
	var synthetic_unknown: Dictionary = {"id": "synthetic-unclassified", "parity_class": "future_class"}
	_check(not Governance.rule_applies(synthetic_unknown),
		"unclassified rule fails closed in parity-only (skipped, no crash)",
		"unclassified rule still applies in parity-only")


## 2b. With the flag off every expansion record/node is included and the
## synthetic expansion rule applies; parity-only is not a permanent build mode.
func check_off_includes() -> void:
	_set_parity(false)
	_check(not Governance.enabled(), "flag off disables parity-only",
		"flag off still reports parity-only")
	var blocked: Array[String] = []
	for rv: Variant in Governance.EXPANSION_RECORDS:
		var rec: Dictionary = rv as Dictionary
		if not Governance.record_allowed(str(rec.get("path", ""))):
			blocked.append(str(rec.get("path", "")))
	_check(blocked.is_empty(), "flag off includes every expansion record",
		"flag off still blocks: %s" % ", ".join(blocked))
	_check(Governance.expansion_nodes_allowed(), "flag off includes expansion nodes",
		"flag off still excludes expansion nodes")
	_check(Governance.coop_transport_allowed(), "flag off allows the co-op transport",
		"flag off still blocks the co-op transport")
	var synthetic_expansion: Dictionary = {"id": "synthetic-expansion", "parity_class": Governance.TAT2_EXPANSION}
	_check(Governance.rule_applies(synthetic_expansion),
		"flag off applies a tat2_expansion rule",
		"flag off still excludes a tat2_expansion rule")
	var chain: Dictionary = PersonalQuestScript.chain()
	_check(not chain.is_empty() and not _arr(chain.get("stages")).is_empty(),
		"flag off includes the personal_spider chain (%d stages)" % _arr(chain.get("stages")).size(),
		"flag off still excludes the personal_spider chain")
	var prep: Node = MissionPrepScript.new()
	var sky: Dictionary = prep.call("_load_prep_skyline") as Dictionary
	prep.free()
	_check(not sky.is_empty() and not _arr(sky.get("pieces")).is_empty(),
		"flag off includes the prep skyline (%d pieces)" % _arr(sky.get("pieces")).size(),
		"flag off still excludes the prep skyline")
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd != null:
		gd.call("_load_briefing_overrides")
		var ov: Dictionary = gd.get("briefing_overrides") as Dictionary
		_check(not ov.is_empty(), "flag off includes the briefing overrides",
			"flag off still excludes the briefing overrides")
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		_check(bool(gs.call("coop_transport_available")),
			"flag off reports the co-op transport available",
			"flag off reports the co-op transport unavailable")


## 3/4. Filter contract on synthetic data: expansion entries are skipped and
## counted; restoration entries are kept; every non-mesh key survives intact.
func check_runtime_filter_contract() -> void:
	var classes: Dictionary = {
		"poi-lounge-floor-tile": Governance.PARITY_RESTORATION,
		"synthetic-expansion": Governance.TAT2_EXPANSION,
	}
	var synthetic: Dictionary = {
		"markers": [{"name": "guard_a", "spawn_bucket": "StandardGuards_Bouncers"}],
		"guard_spawn_meta": {"buckets": 4},
		"gc": [{"owner": "BP_Chest"}],
		"gc_leaves": [{"owner": "BP_Chest"}],
		"spawn_elements": [{"kind": "loot", "name": "BP_Loot"}],
		"meshes": [
			{"mesh": "/Game/Test/Graybox/GB_Floor_2x2", "content_rule": "poi-lounge-floor-tile",
				"content_parity_class": Governance.PARITY_RESTORATION,
				"override_material": "/Game/Mat.MI_FloorTileA"},
			{"mesh": "/Game/Test/Graybox/GB_Floor_2x2", "content_rule": "synthetic-expansion",
				"content_parity_class": Governance.TAT2_EXPANSION,
				"override_material": "/Game/Mat.MI_Expansion"},
			{"mesh": "/Game/Art/SM_Wall"},
		],
	}
	_set_parity(true)
	var on: Dictionary = Governance.filter_level_payload(synthetic, classes, true)
	var on_payload: Dictionary = on.get("payload") as Dictionary
	_check(int(on.get("skipped", -1)) == 1,
		"parity-only filter skips the expansion mesh (%d)" % int(on.get("skipped", -1)),
		"parity-only filter skipped %d, expected 1" % int(on.get("skipped", -1)))
	_check(int((on.get("by_reason") as Dictionary).get("tat2_expansion", 0)) == 1,
		"skip is labelled tat2_expansion (counted diagnostic)",
		"skip reason is not tat2_expansion")
	_check(_arr(on_payload.get("meshes")).size() == 2,
		"parity-only keeps the restoration + untagged meshes (2)",
		"parity-only kept %d meshes, expected 2" % _arr(on_payload.get("meshes")).size())
	var untouched: bool = true
	for key: String in synthetic.keys():
		if key == "meshes":
			continue
		if on_payload.get(key) != synthetic.get(key):
			untouched = false
	_check(untouched, "parity-only filter returns every non-mesh record unchanged",
		"parity-only filter changed a non-mesh record")
	var off: Dictionary = Governance.filter_level_payload(synthetic, classes, false)
	_check(int(off.get("skipped", -1)) == 0,
		"flag off keeps the expansion mesh",
		"flag off skipped %d mesh(es)" % int(off.get("skipped", -1)))
	var unknown: Dictionary = Governance.mesh_decision(
		{"content_rule": "future-rule"}, {"future-rule": "future_class"}, true)
	_check(bool(unknown.get("skip", false)) and str(unknown.get("reason", "")) == "unclassified",
		"unknown class is skipped as unclassified in parity-only (no crash)",
		"unknown class decision is %s" % str(unknown))
	_set_parity(false)


## 3/4 on real generated data: all restoration tags are kept and no shipped
## marker/guard/GC/loot record is dropped from any rule level.
func check_generated_levels() -> void:
	if not DirAccess.dir_exists_absolute(LEVELS_ROOT):
		print("SKIP: generated levels absent (private extract); table + runtime contract only")
		return
	var levels: Dictionary = {}
	var expected_tagged: int = 0
	for rv: Variant in _arr(table.get("rules")):
		var rule: Dictionary = rv as Dictionary
		if str(rule.get("parity_class", "")) == Governance.PARITY_RESTORATION:
			expected_tagged += int(rule.get("expect_changed", rule.get("expect_count", 0)))
		for lv: Variant in _arr(rule.get("levels")):
			levels[str(lv)] = true
	# Two guard/loot-bearing maps prove the shipped-record contract on payloads
	# the restoration rules do not touch (rule levels carry no guards/loot).
	for extra: String in ["Guildhall/Guildhall_Gameplay", "OldManor/OldManor_Gameplay"]:
		if FileAccess.file_exists("%s/%s.tatlevel.json" % [LEVELS_ROOT, extra]):
			levels[extra] = true
	_set_parity(true)
	var total_tagged: int = 0
	var explicit_class: int = 0
	var restored_kept: int = 0
	var shipped: Dictionary = {
		"markers": 0,
		"guard_markers": 0,
		"gc": 0,
		"gc_leaves": 0,
		"loot": 0,
	}
	var problems: Array[String] = []
	for level_key: String in levels.keys():
		var path: String = "%s/%s.tatlevel.json" % [LEVELS_ROOT, level_key]
		var raw: Variant = _read_json(path)
		if not (raw is Dictionary):
			problems.append("missing level %s" % level_key)
			continue
		var payload: Dictionary = raw as Dictionary
		var filtered: Dictionary = Governance.filter_level_payload(payload, rule_classes, true)
		var out: Dictionary = filtered.get("payload") as Dictionary
		if int(filtered.get("skipped", 0)) != 0:
			problems.append("%s: parity-only skipped %d restoration mesh(es)"
				% [level_key, int(filtered.get("skipped", 0))])
		if out.size() != payload.size():
			problems.append("%s: payload key count changed" % level_key)
		for key: String in payload.keys():
			if key == "meshes":
				continue
			if out.get(key) != payload.get(key):
				problems.append("%s: non-mesh key %s changed" % [level_key, key])
		var raw_meshes: Array = _arr(payload.get("meshes"))
		var out_meshes: Array = _arr(out.get("meshes"))
		if raw_meshes.size() != out_meshes.size():
			problems.append("%s: mesh count %d -> %d" % [level_key, raw_meshes.size(), out_meshes.size()])
		shipped["markers"] = int(shipped["markers"]) + _arr(payload.get("markers")).size()
		shipped["guard_markers"] = int(shipped["guard_markers"]) + _count_guard_markers(payload)
		shipped["gc"] = int(shipped["gc"]) + _arr(payload.get("gc")).size()
		shipped["gc_leaves"] = int(shipped["gc_leaves"]) + _arr(payload.get("gc_leaves")).size()
		shipped["loot"] = int(shipped["loot"]) + _count_loot_records(payload)
		for mv: Variant in out_meshes:
			if not (mv is Dictionary):
				continue
			var entry: Dictionary = mv as Dictionary
			var rid: String = str(entry.get("content_rule", ""))
			if rid == "":
				continue
			total_tagged += 1
			restored_kept += 1
			if str(entry.get("content_parity_class", "")) != "":
				explicit_class += 1
			var cls: String = str(entry.get("content_parity_class", ""))
			if cls == "":
				cls = str(rule_classes.get(rid, ""))
			if cls != Governance.PARITY_RESTORATION:
				problems.append("%s: kept %s with class %s" % [level_key, rid, cls])
	_check(problems.is_empty(), "every rule level keeps its shipped records and restoration meshes",
		"; ".join(problems.slice(0, 8)))
	_check(total_tagged == expected_tagged,
		"parity-only keeps all %d restoration-tagged instances" % total_tagged,
		"parity-only kept %d of %d tagged instances" % [total_tagged, expected_tagged])
	_check(restored_kept == total_tagged, "all kept tags are restoration meshes",
		"%d kept tag(s) are not restoration" % (total_tagged - restored_kept))
	_check(int(shipped["markers"]) > 0 and int(shipped["gc"]) > 0
			and int(shipped["guard_markers"]) > 0 and int(shipped["loot"]) > 0,
		"shipped records present in checked levels: markers=%d guards=%d gc=%d leaves=%d loot=%d"
			% [int(shipped["markers"]), int(shipped["guard_markers"]),
				int(shipped["gc"]), int(shipped["gc_leaves"]), int(shipped["loot"])],
		"no shipped marker/guard/GC/loot records found in the checked levels")
	print("MEASURED: rule_levels=%d tagged_kept=%d explicit_class=%d restoration_rules=%d expansion_rules=%d"
		% [levels.size(), total_tagged, explicit_class,
			int(class_counts.get(Governance.PARITY_RESTORATION, 0)),
			int(class_counts.get(Governance.TAT2_EXPANSION, 0))])
	if explicit_class < total_tagged:
		print("NOTE: %d/%d tagged instances predate content_parity_class; runtime used the tracked table"
			% [total_tagged - explicit_class, total_tagged])


func _count_guard_markers(payload: Dictionary) -> int:
	var n: int = 0
	for mv: Variant in _arr(payload.get("markers")):
		if not (mv is Dictionary):
			continue
		var cls: String = str((mv as Dictionary).get("class", ""))
		if "MissionSpawner_Character" in cls:
			n += 1
	return n


func _count_loot_records(payload: Dictionary) -> int:
	var n: int = 0
	for ev: Variant in _arr(payload.get("spawn_elements")):
		if ev is Dictionary and str((ev as Dictionary).get("kind", "")) in LOOT_KINDS:
			n += 1
	return n
