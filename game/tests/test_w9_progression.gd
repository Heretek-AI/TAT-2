extends SceneTree
## W9-P1 / A2 standalone gate: authored progression consumption.
##
## What this pins, all of it read from game/data/generated/project_settings.json
## at runtime:
##   1. the level-25 cap with XP preserved (fresh, v8-migrated and 500k-XP saves);
##   2. the authored CT_XPToLevel thresholds 1..25 and the 44,500 cumulative;
##   3. the authored XP award (20+20+80, difficulty x1/x2/x3, time bonus, FTUE
##      +60, free play nothing, score kept only for the record);
##   4. endgame precedence: KF13 1200 s always wins for LootTheRoom, the
##      authored ladder 1200/600/300 wins for the other missions, no published
##      index keeps the QG plan, and the run clock reaches the ladder through
##      GameState.reset_run() without a mission_controller edit;
##   5. the 5,000 FTUE bankroll and its one-shot migration;
##   6. all 48 level-gated market rows unlock at their authored level and not
##      one level below, and level 25 is reachable from the authored curve;
##   7. the authored Guildhall mission order.
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_w9_progression.gd
##
## Save files live under user://w9_progression/ (path_override), so every
## SaveSystem this suite drives writes only there. The GameData/Progression
## autoloads the engine boots may still expose the developer save; nothing here
## reads or writes it, and no assertion depends on it.

const Progression := preload("res://src/core/progression.gd")

## Autoload-adjacent scripts are load()ed inside _initialize() exactly like
## test_w7e_endgame.gd does: a const preload of a script that binds the
## SaveSystem autoload can trip the compile-order dependency when this file is
## the engine's main loop script. Progression is data-only, so it stays a const.
const SAVE_SCRIPT_PATH := "res://src/core/save_system.gd"
const MISSION_SCRIPT_PATH := "res://src/missions/mission_controller.gd"
const CATALOG_SCRIPT_PATH := "res://src/ui/unlock_catalog.gd"

const TEST_DIR := "user://w9_progression"
const XP_CURVE_PATH := "res://data/generated/tables/Gameplay/Tuning/CT_XPToLevel.json"
const UNLOCKS_PATH := "res://data/generated/gameplay/unlocks.json"

const OUT_MISSION := "Mission.Guildhall.LootTheRoom"
const VAULT_MISSION := "Mission.Guildhall.VaultHeist"
const MANOR_VAULT_MISSION := "Mission.OldManor.Vault"

var fails: int = 0
var gs: Node
var gd: Node
var ss: Node
var SaveScript: GDScript
var MissionScript: GDScript
var CatalogScript: GDScript


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _finish() -> void:
	print("W9_PROGRESSION SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


func _reset_dir() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(TEST_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		var dir: DirAccess = DirAccess.open(TEST_DIR)
		if dir != null:
			for name: String in dir.get_files():
				dir.remove(name)
			dir.list_dir_end()
		DirAccess.remove_absolute(abs_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)


# --------------------------------------------------------------- fixtures ---
## Unattached save: no _ready(), no GameState read; the developer save is not
## touched because every path goes through path_override. `data` is seeded with
## _defaults() first exactly like _ready() does: _merge_validated only accepts
## keys already present in the target schema, so an empty data would drop every
## staged key (the suite-49/T02 fixture convention).
func _save(name: String) -> Node:
	var sv: Node = SaveScript.new() as Node
	sv.set("path_override", TEST_DIR + "/" + name + ".json")
	sv.set("data", sv.call("_defaults"))
	return sv


## Attached save: _ready() runs (defaults + load_save on an empty override
## path) and /root/GameState resolves, which the XP award reads for elapsed
## time, difficulty and the free-play guard.
func _live_save(name: String) -> Node:
	var sv: Node = _save(name)
	sv.name = name
	root.add_child(sv)
	return sv


## Write a save built from _defaults() + `fields`, then load it in a fresh
## instance exactly like a boot would.
func _staged_save(name: String, fields: Dictionary) -> Node:
	var path: String = TEST_DIR + "/" + name + ".json"
	var seed: Node = _save(name)
	var d: Dictionary = seed.call("_defaults") as Dictionary
	for key: Variant in fields.keys():
		d[str(key)] = fields[key]
	seed.set("data", d)
	seed.call("write_save")
	seed.free()
	var loaded: Node = _save(name)
	loaded.call("load_save")
	return loaded


func _xp(sv: Node) -> int:
	return int((sv.get("data") as Dictionary).get("xp", 0))


func _currency(sv: Node) -> int:
	return int((sv.get("data") as Dictionary).get("currency", 0))


## Authored per-level curve evaluated independently of GameData/SaveSystem: the
## port's linear interpolation over CT_XPToLevel's Keys (RCIM_Linear with
## constant extrapolation).
func _authored_threshold(level: int) -> float:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(XP_CURVE_PATH))
	var keys: Array = []
	if doc is Dictionary:
		var rows_v: Variant = (doc as Dictionary).get("rows", {})
		if rows_v is Dictionary:
			var row_v: Variant = (rows_v as Dictionary).get("XPToLevel", {})
			if row_v is Dictionary:
				var k_v: Variant = (row_v as Dictionary).get("Keys", [])
				if k_v is Array:
					keys = k_v as Array
	if keys.is_empty():
		return -1.0
	var x: float = float(level)
	var first: Dictionary = keys[0] as Dictionary
	if x <= float(first.get("Time", 0.0)):
		return float(first.get("Value", -1.0))
	for i: int in range(keys.size() - 1):
		var ka: Dictionary = keys[i] as Dictionary
		var kb: Dictionary = keys[i + 1] as Dictionary
		var t0: float = float(ka.get("Time", 0.0))
		var v0: float = float(ka.get("Value", -1.0))
		var t1: float = float(kb.get("Time", 0.0))
		var v1: float = float(kb.get("Value", -1.0))
		if x <= t1:
			if is_equal_approx(t0, t1):
				return v1
			return lerpf(v0, v1, (x - t0) / (t1 - t0))
	return float((keys[-1] as Dictionary).get("Value", -1.0))


# ------------------------------------------------------------------ blocks ---
func _check_authored_source() -> void:
	_check(Progression.loaded(),
		"W9.0a project_settings.json parsed (schema tat2.project_settings/1)",
		"W9.0a project_settings.json not loaded: %s" % str(Progression.load_diagnostics()))
	_check(Progression.fallback_count() == 0,
		"W9.0b no fallback reads on a healthy file",
		"W9.0b %d fallback read(s): %s" % [Progression.fallback_count(), str(Progression.load_diagnostics())])
	_check(Progression.maximum_level() == 25 and Progression.level_up_xp() == 500,
		"W9.0c authored maximum_level=25, level_up_xp=500",
		"W9.0c maximum_level=%d level_up_xp=%d" % [Progression.maximum_level(), Progression.level_up_xp()])
	var raw: Dictionary = Progression.raw()
	var prog_v: Variant = raw.get("progression", {})
	_check(prog_v is Dictionary and int((prog_v as Dictionary).get("maximum_level", 0)) == 25,
		"W9.0d raw() exposes the parsed document (tests cite the file, not a literal)",
		"W9.0d raw() has no progression.maximum_level")


## 1. Authored trajectory identical for a fresh and a migrated profile.
func _check_trajectory() -> void:
	var fresh: Node = _save("fresh")
	fresh.call("load_save")
	var fresh_prog: Dictionary = fresh.call("get_level_progress") as Dictionary
	_check(int(fresh_prog.get("level", 0)) == 1
			and _xp(fresh) == 0
			and int(fresh_prog.get("xp_needed", 0)) == 500
			and Progression.maximum_level() == 25,
		"W9.1a fresh save: level 1, xp 0, xp_needed 500, maximum_level 25",
		"W9.1a fresh level=%s xp=%d needed=%s cap=%d" % [
			str(fresh_prog.get("level", -1)), _xp(fresh),
			str(fresh_prog.get("xp_needed", -1)), Progression.maximum_level()])
	fresh.free()

	# A v8 save (schema 8) keeps its own XP and lands on the same curve.
	var v8: Node = _staged_save("v8_1200", {
		"save_schema": 8,
		"loot_schema": 1,
		"xp": 1200,
		"progression_migrated": true,
		"progression_schema": 1,
	})
	var v8_prog: Dictionary = v8.call("get_level_progress") as Dictionary
	_check(int(v8_prog.get("level", 0)) == 3
			and _xp(v8) == 1200
			and int(v8_prog.get("xp_needed", 0)) == 500
			and int(v8.call("xp_total_for_level", 3)) == 1000,
		"W9.1b staged v8 save xp=1200 loads to level 3 (unchanged), 200/500, total(3)=1000",
		"W9.1b v8 level=%s xp=%d needed=%s total3=%s" % [
			str(v8_prog.get("level", -1)), _xp(v8),
			str(v8_prog.get("xp_needed", -1)), str(v8.call("xp_total_for_level", 3))])
	v8.free()

	# The cap is a level, not a currency: 500,000 XP is kept verbatim.
	var huge: Node = _staged_save("huge_xp", {
		"xp": 500000,
		"progression_migrated": true,
		"progression_schema": 1,
	})
	var huge_prog: Dictionary = huge.call("get_level_progress") as Dictionary
	_check(int(huge_prog.get("level", 0)) == Progression.maximum_level() and _xp(huge) == 500000,
		"W9.1c 500,000 XP loads to level 25 and keeps every point (xp=500000)",
		"W9.1c level=%s xp=%d (want 25 / 500000)" % [str(huge_prog.get("level", -1)), _xp(huge)])
	huge.free()

	# Same destination by both roads: a fresh profile whose last award lands on
	# exactly 2,000 XP is level 5, exactly like a migrated 2,000-XP save.
	var live: Node = _live_save("award_2000")
	var d: Dictionary = live.call("_defaults") as Dictionary
	d["xp"] = 1880
	d["completed_contracts"] = {"1": {"best_score": 500, "ghost": false}}
	live.set("data", d)
	gs.set("free_play", false)
	gs.set("difficulty", 1)
	gs.set("elapsed_sec", 0.0)
	live.call("record_contract_complete", 2, 500, true)
	var live_level: int = int((live.call("get_level_progress") as Dictionary).get("level", 0))
	root.remove_child(live)
	live.free()
	var migrated: Node = _staged_save("migrated_2000", {
		"xp": 2000,
		"progression_migrated": true,
		"progression_schema": 1,
	})
	var migrated_level: int = int((migrated.call("get_level_progress") as Dictionary).get("level", 0))
	migrated.free()
	_check(live_level == 5 and migrated_level == 5,
		"W9.1d 2,000 XP is level 5 on the fresh-award path and the migrated-save path",
		"W9.1d fresh-award level=%d migrated level=%d (want 5/5)" % [live_level, migrated_level])


## 2. Authored thresholds 1..25 and the level-25 cumulative.
func _check_thresholds() -> void:
	var sv: Node = _save("thresholds")
	sv.call("load_save")
	var bad: String = ""
	for lvl: int in range(1, 26):
		var authored: float = _authored_threshold(lvl)
		var got: int = int(sv.call("xp_threshold_for_level", lvl))
		if absf(float(got) - authored) > 0.001:
			bad = "L%d got %d authored %.1f" % [lvl, got, authored]
			break
	_check(bad == "",
		"W9.2a xp_threshold_for_level 1..25 equals the authored CT_XPToLevel curve",
		"W9.2a threshold mismatch: " + bad)
	var groups_ok: bool = true
	for lvl: int in range(1, 5):
		groups_ok = groups_ok and int(sv.call("xp_threshold_for_level", lvl)) == 500
	for lvl: int in range(5, 10):
		groups_ok = groups_ok and int(sv.call("xp_threshold_for_level", lvl)) == 1000
	for lvl: int in range(10, 26):
		groups_ok = groups_ok and int(sv.call("xp_threshold_for_level", lvl)) == 2500
	_check(groups_ok,
		"W9.2b groups: 1-4 = 500, 5-9 = 1000, 10-25 = 2500",
		"W9.2b authored threshold groups broken")
	_check(int(sv.call("xp_total_for_level", 1)) == 0
			and int(sv.call("xp_total_for_level", 2)) == 500
			and int(sv.call("xp_total_for_level", 5)) == 2000
			and int(sv.call("xp_total_for_level", 10)) == 7000,
		"W9.2c cumulative: L1=0, L2=500, L5=2000, L10=7000",
		"W9.2c cumulative mismatch: L1=%d L2=%d L5=%d L10=%d" % [
			int(sv.call("xp_total_for_level", 1)), int(sv.call("xp_total_for_level", 2)),
			int(sv.call("xp_total_for_level", 5)), int(sv.call("xp_total_for_level", 10))])
	_check(int(sv.call("xp_total_for_level", 25)) == 44500
			and int(sv.call("xp_total_for_level", 26)) == 44500
			and int(sv.call("xp_total_for_level", 200)) == 44500,
		"W9.2d total(25)=44,500 and 26+/200 clamp to 44,500",
		"W9.2d total25=%d total26=%d total200=%d (want 44500)" % [
			int(sv.call("xp_total_for_level", 25)), int(sv.call("xp_total_for_level", 26)),
			int(sv.call("xp_total_for_level", 200))])
	sv.free()


## 3. Authored XP award composition (weights authored, composition a port decision).
func _check_award() -> void:
	var sv: Node = _live_save("award")
	gs.set("free_play", false)
	gs.set("elapsed_sec", 0.0)
	var novice: int = _award_once(sv, 1, "award_novice")
	var thief: int = _award_once(sv, 2, "award_thief")
	var master: int = _award_once(sv, 3, "award_master")
	_check(novice == 120 and thief == 240 and master == 360,
		"W9.3a Novice 20+20+80=120, Thief x2=240, Master x3=360",
		"W9.3a award novice=%d thief=%d master=%d (want 120/240/360)" % [novice, thief, master])

	var timed: int = _award_once(sv, 1, "award_timed", 600.0)
	_check(timed == 126,
		"W9.3b 10 elapsed minutes adds clamp(0.6*10,0,25)=6 before the multiplier (126)",
		"W9.3b timed award=%d (want 126)" % timed)
	var capped: int = _award_once(sv, 1, "award_capped", 6000.0)
	_check(capped == 120 + 25,
		"W9.3c the time bonus clamps at maximum_time_in_game_xp=25 (145)",
		"W9.3c long-run award=%d (want 145)" % capped)

	# FTUE: no completion row before this one adds the three authored categories.
	var ftue_xp: int = _award_once(sv, 1, "award_ftue", 0.0, true)
	_check(ftue_xp == 120 + 60 and Progression.ftue_level_up_xp() == 60
			and Progression.ftue_level_up_xp_categories().size() == 3
			and Progression.ftue_level_up_xp_is_on_top_of_regular_xp(),
		"W9.3d FTUE adds the 3 authored categories once (+60) on top of the 120",
		"W9.3d FTUE award=%d ftue=%d categories=%d on_top=%s" % [
			ftue_xp, Progression.ftue_level_up_xp(),
			Progression.ftue_level_up_xp_categories().size(),
			str(Progression.ftue_level_up_xp_is_on_top_of_regular_xp())])

	# Free play never banks progression, even on a direct call.
	var before: int = _xp(sv)
	gs.set("free_play", true)
	sv.call("record_contract_complete", 2, 625, true)
	gs.set("free_play", false)
	_check(_xp(sv) == before,
		"W9.3e free play awards nothing (xp unchanged)",
		"W9.3e free play changed xp %d -> %d" % [before, _xp(sv)])

	# The score argument survives only in the completion record.
	gs.set("elapsed_sec", 0.0)
	sv.call("record_contract_complete", 2, 625, true)
	var cc: Dictionary = (sv.get("data") as Dictionary).get("completed_contracts", {}) as Dictionary
	_check(int((cc.get("2", {}) as Dictionary).get("best_score", 0)) == 625,
		"W9.3f score 625 is kept as completed_contracts[2].best_score (not as XP)",
		"W9.3f best_score=%s" % str((cc.get("2", {}) as Dictionary).get("best_score", -1)))
	root.remove_child(sv)
	sv.free()


## Reset one attached save to a non-FTUE profile, award exactly once and return
## the XP delta. `ftue` empties completed_contracts to exercise the bonus.
func _award_once(sv: Node, difficulty: int, tag: String, elapsed: float = 0.0, ftue: bool = false) -> int:
	var d: Dictionary = sv.call("_defaults") as Dictionary
	d["xp"] = 0
	if not ftue:
		d["completed_contracts"] = {"1": {"best_score": 100, "ghost": false}}
	sv.set("data", d)
	gs.set("free_play", false)
	gs.set("difficulty", difficulty)
	gs.set("elapsed_sec", 0.0)
	var before: int = _xp(sv)
	sv.call("record_contract_complete", 3, 625, true, elapsed)
	var delta: int = _xp(sv) - before
	if delta < 0:
		printerr("FAIL: W9 award delta negative for ", tag)
	return delta


## 4. Endgame precedence: KF13 > authored ladder > QG plan > 480 fallback.
func _check_endgame() -> void:
	# 1. KF13 wins at every difficulty.
	var kf13_ok: bool = true
	for idx: int in range(0, 3):
		var secs: float = float(gd.call("get_mission_endgame_seconds", OUT_MISSION, idx))
		var src: String = str(gd.call("get_mission_endgame_source", OUT_MISSION, idx))
		kf13_ok = kf13_ok and absf(secs - 1200.0) < 0.001 and src == "KF13"
	_check(kf13_ok,
		"W9.4a LootTheRoom = 1200 s from KF13 at difficulty index 0/1/2",
		"W9.4a KF13 precedence broken")

	# 2. Authored ladder for a non-override mission.
	var ladder_ok: bool = true
	var ladder_values: Array[float] = [1200.0, 600.0, 300.0]
	for idx: int in range(0, 3):
		var secs: float = float(gd.call("get_mission_endgame_seconds", VAULT_MISSION, idx))
		var src: String = str(gd.call("get_mission_endgame_source", VAULT_MISSION, idx))
		ladder_ok = ladder_ok and absf(secs - ladder_values[idx]) < 0.001 and src == "project_settings"
	_check(ladder_ok,
		"W9.4b VaultHeist ladder 1200/600/300 with source project_settings",
		"W9.4b authored ladder broken: %s/%s/%s" % [
			str(gd.call("get_mission_endgame_seconds", VAULT_MISSION, 0)),
			str(gd.call("get_mission_endgame_seconds", VAULT_MISSION, 1)),
			str(gd.call("get_mission_endgame_seconds", VAULT_MISSION, 2))])

	# 3. No published index keeps today's QG value (fail-closed default).
	gd.set("current_difficulty_index", -1)
	var qg_secs: float = float(gd.call("get_mission_endgame_seconds", VAULT_MISSION))
	var qg_src: String = str(gd.call("get_mission_endgame_source", VAULT_MISSION))
	_check(absf(qg_secs - 300.0) < 0.001 and qg_src == "quest_graph",
		"W9.4c no index -> QG plan 300 s, source quest_graph",
		"W9.4c no-index endgame=%s source=%s (want 300 quest_graph)" % [str(qg_secs), qg_src])

	# 4. The authored plan itself never moves (480 LootTheRoom / 300 VaultHeist).
	var plan_out: Dictionary = gd.call("get_mission_plan", OUT_MISSION) as Dictionary
	var plan_vault: Dictionary = gd.call("get_mission_plan", VAULT_MISSION) as Dictionary
	var plan_manor: Dictionary = gd.call("get_mission_plan", MANOR_VAULT_MISSION) as Dictionary
	_check(int(plan_out.get("endgame_duration", 0)) == 480
			and int(plan_vault.get("endgame_duration", 0)) == 300
			and int(plan_manor.get("endgame_duration", 0)) == 480,
		"W9.4d QG plans unchanged: LootTheRoom 480, VaultHeist 300, OldManor Vault 480",
		"W9.4d QG plan endgame changed: %s/%s/%s" % [
			str(plan_out.get("endgame_duration", -1)), str(plan_vault.get("endgame_duration", -1)),
			str(plan_manor.get("endgame_duration", -1))])

	# 5. The run clock itself: reset_run publishes the difficulty index, and the
	#    unedited _apply_run_clock() resolves the authored ladder.
	var mc: Node = MissionScript.new() as Node
	var runtime: Array[String] = []
	for pair: Array in [[1, 1200.0], [2, 600.0], [3, 300.0]]:
		gs.set("difficulty", int(pair[0]))
		gs.call("reset_run", 2, "guildhall")
		gs.set("active_mission_id", VAULT_MISSION)
		gs.set("free_play", false)
		var clock: Dictionary = mc.call("_apply_run_clock", "guildhall") as Dictionary
		var limit: float = float(gs.get("endgame_time_limit"))
		var source: String = str(clock.get("endgame_source", ""))
		if absf(limit - float(pair[1])) > 0.001 or source != "project_settings":
			runtime.append("difficulty %d -> %s s / %s (want %s project_settings)" % [
				int(pair[0]), str(limit), source, str(pair[1])])
	mc.free()
	_check(runtime.is_empty(),
		"W9.4e _apply_run_clock (unedited) gets 1200/600/300 from GameState.reset_run()",
		"W9.4e run clock ladder: " + str(runtime))


## 5. Authored FTUE bankroll + one-shot migration.
func _check_ftue_money() -> void:
	var fresh: Node = _save("money_fresh")
	fresh.call("load_save")
	_check(_currency(fresh) == 5000 and Progression.ftue_min_thieves_den_money() == 5000,
		"W9.5a fresh save starts with the authored 5,000 bankroll",
		"W9.5a fresh currency=%d authored=%d" % [_currency(fresh), Progression.ftue_min_thieves_den_money()])
	fresh.free()

	# A profile that completed a contract is never granted money.
	var veteran: Node = _staged_save("money_veteran", {
		"currency": 0,
		"completed_contracts": {"1": {"best_score": 400, "ghost": false}},
		"progression_migrated": false,
	})
	_check(_currency(veteran) == 0 and bool((veteran.get("data") as Dictionary).get("progression_migrated", false)),
		"W9.5b contract 1 completed + currency 0 stays 0 (migration still stamps)",
		"W9.5b veteran currency=%d migrated=%s" % [
			_currency(veteran), str((veteran.get("data") as Dictionary).get("progression_migrated", null))])
	veteran.free()

	# An empty profile with 123 is raised once, then spending is permanent.
	var grant: Node = _staged_save("money_grant", {
		"currency": 123,
		"completed_contracts": {},
		"progression_migrated": false,
		"progression_schema": 0,
	})
	_check(_currency(grant) == 5000,
		"W9.5c empty profile with 123 is raised to 5,000 on load",
		"W9.5c grant currency=%d (want 5000)" % _currency(grant))
	var gd_data: Dictionary = grant.get("data") as Dictionary
	gd_data["currency"] = 2500
	grant.set("data", gd_data)
	grant.call("write_save")
	grant.free()
	var spent: Node = _save("money_grant")
	spent.call("load_save")
	_check(_currency(spent) == 2500,
		"W9.5d after spending to 2,500 a reload does not re-grant (one-shot flag persisted)",
		"W9.5d reload currency=%d (want 2500)" % _currency(spent))
	spent.free()


## 6. All 48 level-gated market rows, and the level-25 curve reach.
func _check_unlock_gating() -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(UNLOCKS_PATH))
	var rows: Array = []
	if doc is Dictionary:
		var entries_v: Variant = (doc as Dictionary).get("entries", [])
		if entries_v is Array:
			for entry_v: Variant in (entries_v as Array):
				if entry_v is Dictionary:
					rows.append(entry_v)
	var gated: Array[Dictionary] = []
	for entry: Dictionary in rows:
		var cond: Dictionary = entry.get("condition", {}) as Dictionary
		var raw_level: Variant = cond.get("requires_level", null)
		if (raw_level is int or raw_level is float) and int(raw_level) > 0:
			gated.append(entry)
	_check(rows.size() == 68 and gated.size() == 48,
		"W9.6a unlocks.json carries 68 rows, 48 level-gated",
		"W9.6a rows=%d gated=%d (want 68/48)" % [rows.size(), gated.size()])

	var catalog: RefCounted = CatalogScript.new() as RefCounted
	var save_prog: Node = _save("unlock_curve")
	save_prog.call("load_save")
	var problems: Array[String] = []
	var ss_data: Dictionary = ss.get("data") as Dictionary
	var xp_backup: int = int(ss_data.get("xp", 0))
	for entry: Dictionary in gated:
		var cond: Dictionary = entry.get("condition", {}) as Dictionary
		var need: int = int(cond.get("requires_level", 0))
		var save_id: String = str(entry.get("save_id", ""))
		var raw_contract: Variant = cond.get("requires_contract", null)
		if raw_contract is int or raw_contract is float:
			problems.append("%s carries a level+contract gate" % save_id)
			continue
		var at: int = int(save_prog.call("xp_total_for_level", need))
		if int(save_prog.call("level_for_xp", at)) != need:
			problems.append("%s: %d XP is level %d, want %d" % [
				save_id, at, int(save_prog.call("level_for_xp", at)), need])
			continue
		if int(save_prog.call("level_for_xp", at - 1)) >= need:
			problems.append("%s: %d XP already reaches level %d" % [save_id, at - 1, need])
			continue
		ss_data["xp"] = at
		if not bool(catalog.call("conditions_met", entry)):
			problems.append("%s locked at its authored level %d" % [save_id, need])
		ss_data["xp"] = at - 1
		if bool(catalog.call("conditions_met", entry)):
			problems.append("%s unlocked one level early (%d XP)" % [save_id, at - 1])
	ss_data["xp"] = xp_backup
	_check(problems.is_empty(),
		"W9.6b every gated row unlocks at its authored level and not one level below",
		"W9.6b gating problems: " + str(problems.slice(0, mini(8, problems.size()))))

	# Level 25 must be reachable from the authored curve (44,500 XP), and its
	# two ModelShip rows are the only 25s.
	var ships: Array[String] = []
	var ships_locked_below: bool = true
	for entry: Dictionary in gated:
		var cond: Dictionary = entry.get("condition", {}) as Dictionary
		if int(cond.get("requires_level", 0)) == 25:
			ships.append(str(entry.get("save_id", "")))
			ss_data["xp"] = 44499
			ships_locked_below = ships_locked_below and not bool(catalog.call("conditions_met", entry))
			ss_data["xp"] = 44500
			ships_locked_below = ships_locked_below and bool(catalog.call("conditions_met", entry))
	ss_data["xp"] = xp_backup
	var reach_ok: bool = ships.size() == 2 \
		and int(save_prog.call("xp_total_for_level", 25)) == 44500 \
		and int(Progression.maximum_level()) == 25 \
		and ships_locked_below \
		and int(save_prog.call("level_for_xp", 44499)) == 24 \
		and int(save_prog.call("level_for_xp", 44500)) == 25
	save_prog.free()
	_check(reach_ok,
		"W9.6c level 25 (2 ModelShip rows) is reachable at 44,500 XP, locked at 44,499",
		"W9.6c ships=%d below_ok=%s cap=%d" % [ships.size(), str(ships_locked_below), Progression.maximum_level()])


## 7. Authored Guildhall mission order.
func _check_map_order() -> void:
	var guildhall: Array[String] = Progression.missions_for_map("Guildhall")
	var expected: Array[String] = [VAULT_MISSION, "Mission.Guildhall.Set", OUT_MISSION]
	_check(guildhall == expected,
		"W9.7a Guildhall missions in authored order: VaultHeist, Set, LootTheRoom",
		"W9.7a Guildhall order=%s (want %s)" % [str(guildhall), str(expected)])
	var by_runtime_id: Array[String] = Progression.missions_for_map("guildhall")
	var by_tag: Array[String] = Progression.missions_for_map("Map.Guildhall")
	_check(by_runtime_id == expected and by_tag == expected,
		"W9.7b the same list resolves from the runtime id and the authored tag",
		"W9.7b id=%s tag=%s" % [str(by_runtime_id), str(by_tag)])
	var manor: Array[String] = Progression.missions_for_map("Old Manor")
	_check(manor.size() == 3
			and str(manor[0]) == "Mission.OldManor.Set"
			and str(manor[1]) == "Mission.OldManor.Vault"
			and str(manor[2]) == "Mission.OldManor.LootTheRoom"
			and Progression.maps().size() == 2,
		"W9.7c OldManor authored order is Set, Vault, LootTheRoom (differs from DT_Missions)",
		"W9.7c manor=%s maps=%d" % [str(manor), Progression.maps().size()])

	# W9.7d: GameState's difficulty-index clamp matches the authored ladder rung
	# count (game_state.gd has no Progression preload, so the constant is named
	# and this assertion is what keeps it honest).
	var gs_script: GDScript = load("res://src/core/game_state.gd") as GDScript
	_check(gs_script != null and int(gs_script.LADDER_INDEX_MAX) == Progression.ladder_size() - 1,
		"W9.7d GameState.LADDER_INDEX_MAX matches EndgameDurationsByDifficulty",
		"W9.7d const=%s ladder=%d" % [str(gs_script.LADDER_INDEX_MAX) if gs_script != null else "null", Progression.ladder_size()])


func _initialize() -> void:
	await process_frame
	gs = root.get_node_or_null("/root/GameState")
	gd = root.get_node_or_null("/root/GameData")
	ss = root.get_node_or_null("/root/SaveSystem")
	SaveScript = load(SAVE_SCRIPT_PATH) as GDScript
	MissionScript = load(MISSION_SCRIPT_PATH) as GDScript
	CatalogScript = load(CATALOG_SCRIPT_PATH) as GDScript
	_check(gs != null and gd != null and ss != null,
		"W9.0 GameState/GameData/SaveSystem autoloads present",
		"W9.0 autoloads missing")
	_check(SaveScript != null and MissionScript != null and CatalogScript != null,
		"W9.0b save_system / mission_controller / unlock_catalog scripts load",
		"W9.0b a dependency script failed to load: save=%s mission=%s catalog=%s" % [
			str(SaveScript), str(MissionScript), str(CatalogScript)])
	if gs == null or gd == null or ss == null or SaveScript == null or MissionScript == null or CatalogScript == null:
		_finish()
		return
	_reset_dir()
	_check_authored_source()
	_check_trajectory()
	_check_thresholds()
	_check_award()
	_check_endgame()
	_check_ftue_money()
	_check_unlock_gating()
	_check_map_order()
	# The developer save is never touched (every fixture uses path_override) and
	# this runs as its own process, so GameState/GameData mutations die with it.
	_finish()
