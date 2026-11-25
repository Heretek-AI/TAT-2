extends RefCounted
## T02-A save-integrity suite: RE-N-03 (a corrupt save must not become a fresh
## profile), RE-N-06 (the payout outbox must be a production path and
## write_save() must be able to fail) and RE-N-04 (get_loadout must not hand out
## live save state).
##
## Same contract as suite 90 (test_w7s_loot_save.gd): `run(host) -> Array[String]`
## returns problem strings and prints one `PASS:` line per block, so run_tests
## can call it. Every SaveScript here carries a `path_override` into
## `user://t02_save_integrity/`, which the suite creates and removes itself: it
## never reads, writes or restores the developer save, and it does not touch
## GameState, so it cannot collide with the other lane.

const SaveScript := preload("res://src/core/save_system.gd")
const TEST_DIR := "user://t02_save_integrity"


func run(host: Node) -> Array[String]:
	var problems: Array[String] = []
	_expect(problems, host != null, "T02-00 no host node")
	_reset_dir()
	_check_corrupt_bytes(problems)
	_check_not_an_object(problems)
	_check_good_save_migrates_once(problems)
	_check_write_errors(problems)
	_check_outbox_recovery(problems)
	_check_bank_persisted(problems)
	_check_loadout_isolation(problems)
	_reset_dir()
	return problems


# ----------------------------------------------------------------- helpers ---
func _expect(problems: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		problems.append(msg)


func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


## Empty the throwaway directory (each block starts from a clean slate so the
## "no extra file was minted" assertions are exact).
func _reset_dir() -> void:
	var abs_dir: String = _abs(TEST_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		var dir: DirAccess = DirAccess.open(TEST_DIR)
		if dir != null:
			for name: String in dir.get_files():
				dir.remove(name)
			dir.list_dir_end()
		DirAccess.remove_absolute(abs_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)


func _dir_files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir: DirAccess = DirAccess.open(TEST_DIR)
	if dir == null:
		return out
	for name: String in dir.get_files():
		out.append(name)
	dir.list_dir_end()
	return out


func _new_save(path: String) -> Node:
	var sv: Node = SaveScript.new() as Node
	sv.set("path_override", path)
	sv.set("data", sv.call("_defaults"))
	return sv


func _write_text(path: String, text: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _payout(match_id: String, money: int) -> Dictionary:
	return {
		"match_id": match_id,
		"mission_id": "Mission.Guildhall.VaultHeist",
		"contract_order": 2,
		"map_id": "guildhall",
		"outcome": "escape",
		"original": 1000,
		"kept": 1000,
		"stashed": 250,
		"reward": 1000,
		"score": 1250,
		"money_taken": money,
		"stealth_mult": 1.25,
		"capture": false,
		"free_play": false,
		"applied": false,
		"banked": 0,
		"carried": [],
	}


# ------------------------------------------------ RE-N-03 corrupt bytes ---
func _check_corrupt_bytes(problems: Array[String]) -> void:
	_reset_dir()
	var path: String = TEST_DIR + "/corrupt.json"
	var garbage: String = "{broken json,,"
	var sv: Node = _new_save(path)
	var events: Array = []
	sv.connect(&"load_failed", func(reason: String, backup: String) -> void:
		events.append([reason, backup])
	)
	_expect(problems, _write_text(path, garbage), "T02-01 could not write the corrupt fixture")
	sv.call("load_save")
	var failure: Dictionary = sv.call("get_load_failure") as Dictionary
	var backup: String = str(failure.get("backup_path", ""))
	_expect(problems, bool(sv.call("has_load_failure")), "T02-01 corrupt save not reported (has_load_failure false)")
	_expect(problems, str(failure.get("reason", "")) == "parse_error", "T02-01 corrupt reason=%s (want parse_error)" % str(failure.get("reason", "")))
	_expect(problems, str(failure.get("error", "")) != "", "T02-01 corrupt load carries no parser error text")
	_expect(problems, str(failure.get("path", "")) == path, "T02-01 failure path=%s (want %s)" % [str(failure.get("path", "")), path])
	_expect(problems, backup != "" and FileAccess.file_exists(backup), "T02-01 corrupt save was not quarantined (%s)" % backup)
	if backup != "" and FileAccess.file_exists(backup):
		_expect(problems, _read_text(backup) == garbage, "T02-01 quarantine does not hold the original bytes")
	_expect(problems, not FileAccess.file_exists(path), "T02-01 corrupt load left the file at save_path (it must be moved, never rewritten)")
	_expect(problems, not FileAccess.file_exists(str(sv.call("tmp_path"))), "T02-01 corrupt load left a .tmp behind")
	_expect(problems, events.size() == 1, "T02-01 load_failed emitted %d time(s) (want 1)" % events.size())
	if events.size() == 1:
		var ev: Array = events[0] as Array
		_expect(problems, str(ev[0]) == "parse_error" and str(ev[1]) == backup, "T02-01 load_failed payload=%s (want reason+backup)" % str(ev))
	var recovered: Dictionary = sv.get("data") as Dictionary
	_expect(problems, int(recovered.get("currency", -1)) == 0, "T02-01 recovered currency=%d (want defaults 0)" % int(recovered.get("currency", -1)))
	_expect(problems, (recovered.get("unlocked_tools", []) as Array).has("zipwire"), "T02-01 recovered data is not the default profile")
	sv.free()
	print("PASS: T02 save integrity 1 (corrupt bytes quarantined whole, nothing overwritten, load_failed emitted once)")


# --------------------------------- valid JSON, but not a JSON object ---
func _check_not_an_object(problems: Array[String]) -> void:
	for fixture: Array in [["string.json", "\"hello\""], ["array.json", "[1,2]"], ["null.json", "null"]]:
		_reset_dir()
		var name: String = str(fixture[0])
		var text: String = str(fixture[1])
		var path: String = TEST_DIR + "/" + name
		var sv: Node = _new_save(path)
		_expect(problems, _write_text(path, text), "T02-02 could not write %s" % name)
		sv.call("load_save")
		var failure: Dictionary = sv.call("get_load_failure") as Dictionary
		var backup: String = str(failure.get("backup_path", ""))
		_expect(problems, bool(sv.call("has_load_failure")), "T02-02 %s not reported as a failed load" % name)
		_expect(problems, str(failure.get("reason", "")) == "not_an_object", "T02-02 %s reason=%s (want not_an_object)" % [name, str(failure.get("reason", ""))])
		_expect(problems, backup != "" and FileAccess.file_exists(backup), "T02-02 %s was not quarantined" % name)
		if backup != "" and FileAccess.file_exists(backup):
			_expect(problems, _read_text(backup) == text, "T02-02 %s quarantine bytes differ" % name)
		_expect(problems, not FileAccess.file_exists(path), "T02-02 %s still at save_path after a failed load" % name)
		sv.free()
	# The empty object is a valid save and must NOT be quarantined.
	_reset_dir()
	var ok_path: String = TEST_DIR + "/empty-object.json"
	var ok_save: Node = _new_save(ok_path)
	_expect(problems, _write_text(ok_path, "{}"), "T02-02 could not write the empty-object fixture")
	ok_save.call("load_save")
	_expect(problems, not bool(ok_save.call("has_load_failure")), "T02-02 an empty JSON object was treated as corrupt")
	_expect(problems, FileAccess.file_exists(ok_path), "T02-02 the empty-object save was moved")
	ok_save.free()
	print("PASS: T02 save integrity 2 (string/array/null roots quarantined; {} is a valid save)")


# --------------------------------------------- good save, one migration ---
func _check_good_save_migrates_once(problems: Array[String]) -> void:
	_reset_dir()
	var path: String = TEST_DIR + "/good.json"
	var sv: Node = _new_save(path)
	var data: Dictionary = sv.get("data") as Dictionary
	data["currency"] = 777
	data["completed_contracts"] = {"2": {"best_score": 900, "ghost": true}}
	data["save_schema"] = 0
	data["loot_schema"] = 0
	data["settings_schema"] = 1
	var settings: Dictionary = data["settings"] as Dictionary
	settings["fov"] = 75.0
	settings["fov_migrated"] = false
	data["settings"] = settings
	_expect(problems, _write_text(path, JSON.stringify(data, "\t")), "T02-03 could not write the good fixture")
	sv.call("load_save")
	_expect(problems, not bool(sv.call("has_load_failure")), "T02-03 a good save was reported as a failed load")
	var loaded: Dictionary = sv.get("data") as Dictionary
	_expect(problems, int(loaded.get("currency", -1)) == 777, "T02-03 good save currency=%d (want 777)" % int(loaded.get("currency", -1)))
	_expect(problems, int(loaded.get("save_schema", 0)) == 8, "T02-03 good save not migrated to save_schema 8")
	var loaded_settings: Dictionary = loaded.get("settings", {}) as Dictionary
	_expect(problems, is_equal_approx(float(loaded_settings.get("fov", 0.0)), 54.54), "T02-03 legacy fov not migrated (%.2f)" % float(loaded_settings.get("fov", 0.0)))
	_expect(problems, FileAccess.file_exists(path), "T02-03 good save moved away by its own load")
	var after_first: String = _read_text(path)
	var files_after_first: PackedStringArray = _dir_files()
	_expect(problems, files_after_first.size() == 1, "T02-03 a good load left %d files (want 1: the save)" % files_after_first.size())
	# A second boot sees the migration flags and must not write again.
	var second: Node = _new_save(path)
	second.call("load_save")
	_expect(problems, not bool(second.call("has_load_failure")), "T02-03 second load of a good save reported a failure")
	_expect(problems, _read_text(path) == after_first, "T02-03 the migration write was not one-shot (file changed on the second load)")
	_expect(problems, int(second.call("get_currency")) == 777, "T02-03 second load lost the good profile")
	sv.free()
	second.free()
	print("PASS: T02 save integrity 3 (good save loads, migrates exactly once, is never quarantined)")


# ------------------------------------------- RE-N-06 write_save() error ---
func _check_write_errors(problems: Array[String]) -> void:
	_reset_dir()
	var path: String = TEST_DIR + "/writable.json"
	var sv: Node = _new_save(path)
	var ok_err: int = int(sv.call("write_save"))
	_expect(problems, ok_err == OK, "T02-04 write_save on a writable path returned %d (%s)" % [ok_err, error_string(ok_err)])
	_expect(problems, FileAccess.file_exists(path), "T02-04 write_save returned %s but no save exists" % error_string(ok_err))
	_expect(problems, not FileAccess.file_exists(str(sv.call("tmp_path"))), "T02-04 write_save left a .tmp behind")
	_expect(problems, JSON.parse_string(_read_text(path)) is Dictionary, "T02-04 the written save does not parse")
	var bad_path: String = TEST_DIR + "/no_such_dir/x.json"
	var bad: Node = _new_save(bad_path)
	var bad_err: int = int(bad.call("write_save"))
	_expect(problems, bad_err != OK, "T02-04 write_save into a missing directory returned OK")
	_expect(problems, not FileAccess.file_exists(str(bad.call("tmp_path"))), "T02-04 a failed write left a .tmp behind")
	_expect(problems, not DirAccess.dir_exists_absolute(_abs(TEST_DIR + "/no_such_dir")), "T02-04 a failed write created the missing directory")
	sv.free()
	bad.free()
	print("PASS: T02 save integrity 4 (write_save returns OK on a good path, non-OK on an unwritable one, no .tmp left)")


# ------------------------------------- RE-N-06 outbox crash recovery ---
func _check_outbox_recovery(problems: Array[String]) -> void:
	_reset_dir()
	var path: String = TEST_DIR + "/outbox.json"
	var sv: Node = _new_save(path)
	var data: Dictionary = sv.get("data") as Dictionary
	data["currency"] = 100
	var staged: Dictionary = sv.call("stage_pending_payout", _payout("outbox-1", 500)) as Dictionary
	_expect(problems, not bool(staged.get("applied", true)), "T02-05 staged payout marked applied")
	_expect(problems, int(staged.get("outbox_error", -1)) == OK, "T02-05 staging write failed (%d)" % int(staged.get("outbox_error", -1)))
	var on_disk_v: Variant = JSON.parse_string(_read_text(path))
	var pending_id: String = ""
	if on_disk_v is Dictionary:
		var pending: Dictionary = (on_disk_v as Dictionary).get("pending_payout", {}) as Dictionary
		pending_id = str(pending.get("match_id", ""))
	_expect(problems, pending_id == "outbox-1", "T02-05 pending payout not on disk (got '%s')" % pending_id)
	# A fresh boot settles the staged record exactly once.
	var reloaded: Node = _new_save(path)
	reloaded.call("load_save")
	_expect(problems, not bool(reloaded.call("has_load_failure")), "T02-05 the staged save was treated as corrupt")
	_expect(problems, int(reloaded.call("get_currency")) == 600, "T02-05 reload banked %d (want 600)" % int(reloaded.call("get_currency")))
	_expect(problems, str(reloaded.call("get_last_match").get("match_id", "")) == "outbox-1", "T02-05 recovery did not record last_match")
	_expect(problems, str(reloaded.call("get_pending_payout").get("match_id", "")) == "", "T02-05 recovery left the pending record")
	reloaded.call("load_save")
	_expect(problems, int(reloaded.call("get_currency")) == 600, "T02-05 second load double-banked (%d)" % int(reloaded.call("get_currency")))
	sv.free()
	reloaded.free()
	print("PASS: T02 save integrity 5 (staged payout settles exactly once through the override path)")


# ------------------------------------------- RE-N-06 bank_payout write ---
func _check_bank_persisted(problems: Array[String]) -> void:
	_reset_dir()
	var path: String = TEST_DIR + "/bank.json"
	var sv: Node = _new_save(path)
	var result: Dictionary = sv.call("bank_payout", _payout("bank-1", 300)) as Dictionary
	_expect(problems, bool(result.get("applied", false)), "T02-06 bank_payout not applied")
	_expect(problems, bool(result.get("persisted", false)), "T02-06 bank_payout persisted=false write_error=%d" % int(result.get("write_error", -1)))
	_expect(problems, int(result.get("write_error", -1)) == OK, "T02-06 bank_payout write_error=%d" % int(result.get("write_error", -1)))
	_expect(problems, int(result.get("outbox_error", -1)) == OK, "T02-06 bank_payout outbox_error=%d" % int(result.get("outbox_error", -1)))
	_expect(problems, int(result.get("banked", -1)) == 300, "T02-06 bank_payout banked=%d (want 300)" % int(result.get("banked", -1)))
	_expect(problems, str(result.get("reason", "")) == "banked", "T02-06 bank_payout reason=%s" % str(result.get("reason", "")))
	_expect(problems, str(sv.call("get_pending_payout").get("match_id", "")) == "", "T02-06 pending payout not cleared after banking")
	var on_disk_v: Variant = JSON.parse_string(_read_text(path))
	var disk_ok: bool = false
	var disk_currency: int = -1
	if on_disk_v is Dictionary:
		var disk: Dictionary = on_disk_v as Dictionary
		disk_currency = int(disk.get("currency", -1))
		var last: Dictionary = disk.get("last_match", {}) as Dictionary
		disk_ok = str(last.get("match_id", "")) == "bank-1" and bool(last.get("applied", false))
	_expect(problems, disk_ok, "T02-06 the file on disk does not hold the applied last_match")
	_expect(problems, disk_currency == 300, "T02-06 the file on disk holds currency=%d (want 300)" % disk_currency)
	# The replay is still a no-op through the same API.
	var replay: Dictionary = sv.call("bank_payout", _payout("bank-1", 300)) as Dictionary
	_expect(problems, not bool(replay.get("applied", true)), "T02-06 replay was applied again")
	_expect(problems, str(replay.get("reason", "")) == "duplicate", "T02-06 replay reason=%s (want duplicate)" % str(replay.get("reason", "")))
	_expect(problems, int(sv.call("get_currency")) == 300, "T02-06 replay changed currency")
	# A bank whose writes cannot land must still report applied:true (the
	# in-memory profile is updated) but never persisted:true.
	var broken: Node = _new_save(TEST_DIR + "/no_such_dir/bank.json")
	var broken_data: Dictionary = broken.get("data") as Dictionary
	broken_data["currency"] = 10
	var failed: Dictionary = broken.call("bank_payout", _payout("bank-2", 400)) as Dictionary
	_expect(problems, bool(failed.get("applied", false)), "T02-06 a failed-write bank was not applied in memory")
	_expect(problems, not bool(failed.get("persisted", true)), "T02-06 a failed-write bank claimed persisted=true")
	_expect(problems, int(failed.get("write_error", -1)) != OK, "T02-06 a failed second write reported write_error=OK")
	_expect(problems, int(failed.get("outbox_error", -1)) != OK, "T02-06 a failed staged write reported outbox_error=OK")
	_expect(problems, int(broken.call("get_currency")) == 410, "T02-06 failed-write bank currency=%d (want 410 in memory)" % int(broken.call("get_currency")))
	_expect(problems, not FileAccess.file_exists(str(broken.call("tmp_path"))), "T02-06 a failed bank left a .tmp behind")
	sv.free()
	broken.free()
	print("PASS: T02 save integrity 6 (bank_payout persists, clears pending, replays as duplicate, never lies about a failed write)")


# ------------------------------------- RE-N-04 get_loadout is a copy ---
func _check_loadout_isolation(problems: Array[String]) -> void:
	var sv: Node = _new_save(TEST_DIR + "/loadout.json")
	var loadout: Dictionary = sv.call("get_loadout", "spider") as Dictionary
	var tools: Array = loadout.get("tools", []) as Array
	tools.append("t02-sentinel")
	var data: Dictionary = sv.get("data") as Dictionary
	var equipped: Dictionary = data.get("equipped_loadout", {}) as Dictionary
	var spider: Dictionary = equipped.get("spider", {}) as Dictionary
	var owned: Array = spider.get("tools", []) as Array
	_expect(problems, not owned.has("t02-sentinel"), "T02-07 get_loadout aliases the live save (an append leaked into data: %s)" % str(owned))
	sv.call("set_loadout", "spider", loadout)
	var round_trip: Dictionary = sv.call("get_loadout", "spider") as Dictionary
	_expect(problems, (round_trip.get("tools", []) as Array).has("t02-sentinel"), "T02-07 set_loadout/get_loadout round-trip lost the tools")
	sv.free()
	print("PASS: T02 save integrity 7 (get_loadout hands out a copy; set_loadout round-trips)")
