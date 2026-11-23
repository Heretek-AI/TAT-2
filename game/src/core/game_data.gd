extends Node
## Loads normalized UE5 DataTables, CurveTables, and StringTables from res://data/generated/tables/.

var contracts: Array[Dictionary] = []
var curves: Dictionary = {} # table_name -> { row_name -> Array[{time, value}] }
var tables: Dictionary = {} # data table_name -> rows Dictionary (non-curve DataTables)
var contract_strings: Dictionary = {} # contract_order -> Dictionary[key -> text]
var mission_durations: Dictionary = {} # map_id -> { durations, quest_graph_ue_path, title/description, source_* }
var missions: Array[Dictionary] = [] # all CDT_Missions / DT_Missions_* rows (11 authored rows)
var missions_by_id: Dictionary = {}
## Free-play Cleanout Heist loot thresholds, keyed by mission id. Populated
## from contracts.json's "mission_loot_goals" (tools/parse_contracts.py reads
## the QG objective node amounts); the documented fallback below keeps the
## accessor honest when generated data predates that parser key.
var mission_loot_goals: Dictionary = {}
const FALLBACK_MISSION_LOOT_GOALS: Dictionary = {
	# QG_Guildhall_LootTheRoom TATQuestGraphObjectiveNode_21/22/23
	# Properties.objective.amount (extracted UE capture).
	"Mission.Guildhall.LootTheRoom": [4000, 6000, 8000],
}
## Provenance for the contracts.json overlay (which DT_/CDT_ table it was
## generated from). Written by _load_contracts_json; read via
## contracts_source() (P2-D5: the var was write-only).
var contracts_source_table: String = ""
## G1/G2 sentinels: every fallback routing decision is counted and named so
## a misspelled row or map can never route silently. Export gates on these.
## The 64-row list caps below are named constants so the bound is provable
## (warning lines print cap=<CONST>); counts stay exact past the cap.
const MAP_FALLBACK_MAX_ROWS := 64
const ICON_UNIMPORTED_MAX_ROWS := 64
var map_fallback_count: int = 0
var map_fallback_rows: Array[String] = []
var icon_unimported_count: int = 0
var icon_unimported_rows: Array[String] = []

func _ready() -> void:
	_load_curves()
	_load_contracts()
	_load_contracts_json()
	_load_contract_strings()
	_load_missions()


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed


func _load_curves() -> void:
	_load_tables_from_dir("res://data/generated/tables/Gameplay/Tuning", false)
	_load_tables_from_dir("res://data/generated/tables/Character/Player", false)
	_load_tables_from_dir("res://data/generated/tables/Gameplay/Tools", true)
	_load_tables_from_dir("res://data/generated/tables/AI/Data", false)
	# Curves that live outside the scanned roots. Together with the four roots
	# above this loads all 31 authored CurveTables (the audit found 7 silently
	# missing, including the two gamepad response curves and the weather
	# exposure curves).
	for dir_path: String in [
		"res://data/generated/tables/Gameplay/Abilities/Effects",
		"res://data/generated/tables/Gameplay/Combat/Guard/Melee/RangedAttack",
		"res://data/generated/tables/Gameplay/Interactables/ElectricPower",
		"res://data/generated/tables/Gameplay/Progression",
		"res://data/generated/tables/AI/Alertness",
		"res://data/generated/tables/Art/Environment/Weather",
		"res://data/generated/tables/Gameplay/Carry",
		"res://data/generated/tables/Gameplay/Input/Character",
		"res://data/generated/tables/Gameplay/Traversal/Dodge",
	]:
		_load_tables_from_dir(dir_path, true)


func _load_tables_from_dir(base_dir: String, recursive: bool) -> void:
	var dir: DirAccess = DirAccess.open(base_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname == "." or fname == "..":
			fname = dir.get_next()
			continue
		var full_path: String = base_dir + "/" + fname
		if dir.current_is_dir():
			if recursive:
				_load_tables_from_dir(full_path, true)
		elif fname.ends_with(".json"):
			_store_table_file(full_path, fname)
		fname = dir.get_next()
	dir.list_dir_end()


func _store_table_file(full_path: String, fname: String) -> void:
	var data: Variant = _load_json(full_path)
	if not (data is Dictionary):
		return
	var d: Dictionary = data
	if not d.has("rows"):
		return
	var rows: Variant = d["rows"]
	if not (rows is Dictionary):
		return
	var tname: String = str(d.get("name", fname.get_basename()))
	var kind: String = str(d.get("type", ""))
	var is_curve: bool = kind == "CurveTable" or fname.begins_with("CT_")
	var is_data: bool = kind == "DataTable" or fname.begins_with("DT_")
	if is_curve and not is_data:
		curves[tname] = rows
	elif is_data and not is_curve:
		tables[tname] = rows
	else:
		if _rows_look_like_curves(rows):
			curves[tname] = rows
		else:
			tables[tname] = rows


func _rows_look_like_curves(rows: Dictionary) -> bool:
	for key: Variant in rows.keys():
		var row: Variant = rows[key]
		if row is Dictionary and (row as Dictionary).has("Keys"):
			return true
	return false


func eval_curve(table_name: String, row_name: String, x: float, fallback: float = 0.0) -> float:
	var tbl: Variant = curves.get(table_name)
	if (tbl == null or not (tbl is Dictionary)) and tables.has(table_name):
		tbl = tables.get(table_name)
	if tbl == null or not (tbl is Dictionary):
		return fallback
	var row: Variant = (tbl as Dictionary).get(row_name)
	if row == null or not (row is Dictionary):
		return fallback
	var keys: Array = (row as Dictionary).get("Keys", [])
	if keys.is_empty():
		return fallback
	var first: Dictionary = keys[0]
	if x <= float(first.get("Time", 0.0)):
		return float(first.get("Value", fallback))
	for i: int in range(keys.size() - 1):
		var ka: Dictionary = keys[i]
		var kb: Dictionary = keys[i + 1]
		var t0: float = float(ka.get("Time", 0.0))
		var v0: float = float(ka.get("Value", fallback))
		var t1: float = float(kb.get("Time", 0.0))
		var v1: float = float(kb.get("Value", fallback))
		if x <= t1:
			if is_equal_approx(t0, t1):
				return v1
			return lerpf(v0, v1, (x - t0) / (t1 - t0))
	var last: Dictionary = keys[-1]
	return float(last.get("Value", fallback))


## Tolerant table lookup by name hint: the converter keys tables by their asset
## name, which is stable, but a suffix match keeps this resilient.
func _table_by_hint(hint: String) -> Dictionary:
	for key: Variant in tables.keys():
		if str(key).find(hint) >= 0 and tables[key] is Dictionary:
			return tables[key] as Dictionary
	return {}


func _curve_by_hint(hint: String) -> Dictionary:
	for key: Variant in curves.keys():
		if str(key).find(hint) >= 0 and curves[key] is Dictionary:
			return curves[key] as Dictionary
	return {}


## DT_PlayerStats row by id (Alarms.Disabled, Cooperation.Respawns, ...).
func get_player_stat_def(id: String) -> Dictionary:
	var row: Variant = _table_by_hint("PlayerStats").get(id)
	return row as Dictionary if row is Dictionary else {}


## DT_PlayerExperience row by category (FinishedTutorial, MajorLoot, ...).
func get_xp_def(category: String) -> Dictionary:
	var row: Variant = _table_by_hint("PlayerExperience").get(category)
	return row as Dictionary if row is Dictionary else {}


## CT_UpgradeStatCurves sampled at a level (falls back to the curve table if the
## progression table is keyed by row name).
func get_upgrade_curve(id: String, level: int) -> float:
	var curve_name: String = ""
	for key: Variant in curves.keys():
		if str(key).find("UpgradeStat") >= 0:
			curve_name = str(key)
			break
	if curve_name == "":
		return 0.0
	return eval_curve(curve_name, id, float(level), 0.0)


func get_data_row(table_name: String, row_name: String) -> Dictionary:
	var tbl: Variant = tables.get(table_name)
	if tbl == null or not (tbl is Dictionary):
		tbl = curves.get(table_name)
	if tbl == null or not (tbl is Dictionary):
		return {}
	var row: Variant = (tbl as Dictionary).get(row_name)
	if row is Dictionary:
		return (row as Dictionary).duplicate()
	return {}


func _sublevel_path_to_tag(asset_path: String) -> String:
	var p: String = asset_path.strip_edges()
	if p == "":
		return ""
	var dot_idx: int = p.rfind(".")
	if dot_idx >= 0 and dot_idx + 1 < p.length():
		return p.substr(dot_idx + 1)
	var slash_idx: int = p.rfind("/")
	if slash_idx >= 0 and slash_idx + 1 < p.length():
		return p.substr(slash_idx + 1)
	return p


func _load_contracts() -> void:
	var data: Variant = _load_json("res://data/generated/tables/Gameplay/Quests/DT_Contracts_1_to_16.json")
	if not (data is Dictionary) or not (data as Dictionary).has("rows"):
		return
	var rows: Dictionary = (data as Dictionary)["rows"]
	var list: Array[Dictionary] = []
	for key: Variant in rows.keys():
		var row: Dictionary = rows[key]
		var order: int = int(row.get("ContractOrder", 0))
		if order <= 0:
			# Shipped data bug: Contract.Main.15 has ContractOrder 0. Repair it
			# from the row key (parse_contracts does the same) instead of sorting
			# a contract to the front of the table.
			var key_s: String = str(key)
			var suffix: String = key_s.get_slice(".", key_s.get_slice_count(".") - 1)
			if suffix.is_valid_int():
				order = int(suffix)
		var map_raw: Variant = row.get("Map")
		var map_d: Dictionary = map_raw if map_raw is Dictionary else {}
		var map_path: String = str(map_d.get("AssetPathName", ""))
		var map_id: String = "thieves_den"
		if "Guildhall" in map_path:
			map_id = "guildhall"
		elif "OldManor" in map_path:
			map_id = "old_manor"
		var obj_raw: Variant = row.get("objective")
		var obj: Dictionary = obj_raw if obj_raw is Dictionary else {}
		var item_raw: Variant = obj.get("Item")
		var item_d: Dictionary = item_raw if item_raw is Dictionary else {}
		var lt_raw: Variant = item_d.get("LootTag")
		var lt_d: Dictionary = lt_raw if lt_raw is Dictionary else {}
		var loot_tag: String = str(lt_d.get("TagName", ""))
		var outro_raw: Variant = row.get("OutroEncounterText")
		var outro_tbl: Dictionary = outro_raw if outro_raw is Dictionary else {}
		var sublevels_raw: Variant = row.get("SublevelsToLoad", [])
		var sublevels: Array[String] = []
		if sublevels_raw is Array:
			for entry: Variant in (sublevels_raw as Array):
				if entry is Dictionary:
					var ap: String = str((entry as Dictionary).get("AssetPathName", ""))
					if ap != "":
						sublevels.append(ap)
		var sublevel_tag: String = ""
		if not sublevels.is_empty():
			sublevel_tag = _sublevel_path_to_tag(sublevels[0])
		list.append({
			"id": key,
			"order": order,
			"map_id": map_id,
			"map_path": map_path,
			"loot_tag": loot_tag,
			"outro_flow": row.get("OutroFlow", ""),
			"outro_preview": outro_tbl.get("SourceString", ""),
			"sublevels": sublevels,
			"sublevel_tag": sublevel_tag,
		})
	list.sort_custom(func(a, b): return a["order"] < b["order"])
	contracts = list


## Exactly the 16 contracts Steam ships (Contract.Main.1..16).
func get_contracts() -> Array[Dictionary]:
	return contracts


## The tutorial route: Steam's FTUE maps, in load order. The port previously
## routed "jaspering_hall" at a scene that does not exist.
func get_ftue_sublevels() -> Array[String]:
	return [
		"FTUE_P",
		"FTUE_Checkpoints",
		"FTUE_AI",
		"FTUE_Fairy",
		"FTUE_TutorialRunner",
		"FTUE_Building_JewelryStore",
		"FTUE_Building_SpawnArea",
		"FTUE_Gameplay",
		"FTUE_Geometry",
		"FTUE_Audio",
	]


func _load_contract_strings() -> void:
	var dir: DirAccess = DirAccess.open("res://data/generated/tables/StringTables/Missions/Contracts")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var data: Variant = _load_json("res://data/generated/tables/StringTables/Missions/Contracts/" + fname)
			if data is Dictionary and (data as Dictionary).has("entries"):
				var parts: PackedStringArray = fname.split("_")
				if parts.size() >= 2 and parts[1].begins_with("Contract"):
					# G3: the old code int()-ed whatever parts[1] was, so a
					# renamed file (prefix without trailing digits) yielded
					# int("") == 0 and silently overwrote contract_strings[0].
					# Only Contract<N> parses; anything else is an error.
					var digits: String = parts[1].substr("Contract".length())
					if digits.is_valid_int():
						contract_strings[int(digits)] = (data as Dictionary)["entries"]
					else:
						push_error("[game_data] contract string file '" + fname + "' has non-numeric Contract suffix '" + parts[1] + "'; skipped (not loaded into contract_strings)")
				elif parts.size() >= 2:
					push_error("[game_data] contract string file '" + fname + "' does not match ST_Contract<N>_*; skipped (not loaded into contract_strings)")
		fname = dir.get_next()
	dir.list_dir_end()


func get_contract_sublevel_tag(order: int) -> String:
	for c: Dictionary in contracts:
		if int(c.get("order", -1)) == order:
			var tag: String = str(c.get("sublevel_tag", ""))
			if tag != "":
				return tag
			var subs: Variant = c.get("sublevels", [])
			if subs is Array and not (subs as Array).is_empty():
				return _sublevel_path_to_tag(str((subs as Array)[0]))
			return ""
	return ""


## P2-D5 accessor: which source table the contracts.json overlay came from
## ("" when the overlay is absent and the DT_ rows stand as-is).
func contracts_source() -> String:
	return contracts_source_table


## Overlay generated by tools/parse_contracts.py onto the table-parsed
## contracts. Falls back cleanly: if contracts.json is missing, the contracts
## built by _load_contracts() from DT_Contracts_1_to_16.json stand as-is and
## mission_durations stays empty (get_match_duration returns 0 = unlimited).
func _load_contracts_json() -> void:
	var data: Variant = _load_json("res://data/generated/gameplay/contracts.json")
	if not (data is Dictionary):
		return
	var d: Dictionary = data
	contracts_source_table = str(d.get("source_table", ""))
	var md: Variant = d.get("mission_durations", {})
	if md is Dictionary:
		mission_durations = (md as Dictionary).duplicate(true)
	var mlg: Variant = d.get("mission_loot_goals", {})
	if mlg is Dictionary:
		mission_loot_goals = (mlg as Dictionary).duplicate(true)
	var jlist: Variant = d.get("contracts", [])
	if not (jlist is Array):
		return
	var by_order: Dictionary = {}
	for jc: Variant in (jlist as Array):
		if jc is Dictionary:
			by_order[int((jc as Dictionary).get("order", -1))] = jc
	for c: Dictionary in contracts:
		var jc: Variant = by_order.get(int(c.get("order", -1)))
		if not (jc is Dictionary):
			continue
		var j: Dictionary = jc
		if str(j.get("map_id", "")) != "":
			c["map_id"] = str(j.get("map_id", ""))
		if str(j.get("map_ue_path", "")) != "":
			c["map_path"] = str(j.get("map_ue_path", ""))
		var jsubs: Variant = j.get("sublevels_ue_paths", [])
		if jsubs is Array and not (jsubs as Array).is_empty():
			var ue_list: Array[String] = []
			for s: Variant in (jsubs as Array):
				var sp: String = str(s)
				if sp != "":
					ue_list.append(sp)
			c["sublevels"] = ue_list
			c["sublevel_tag"] = _sublevel_path_to_tag(ue_list[0])
		if str(j.get("loot_tag", "")) != "":
			c["loot_tag"] = str(j.get("loot_tag", ""))
		if str(j.get("clues_ue_path", "")) != "":
			c["clues_ue_path"] = str(j.get("clues_ue_path", ""))
		if str(j.get("outro_flow", "")) != "":
			c["outro_flow"] = str(j.get("outro_flow", ""))
		if str(j.get("intro_text", "")) != "":
			c["intro"] = str(j.get("intro_text", ""))
		if str(j.get("outro_text", "")) != "":
			c["outro"] = str(j.get("outro_text", ""))
			c["outro_preview"] = str(j.get("outro_text", ""))


## UE sublevel asset path -> Godot level JSON (same rule as parse_tables.py:
## the `Maps/` prefix is stripped).
## e.g. /Game/Maps/Guildhall/Guildhall_Contract_02.Guildhall_Contract_02
##   -> res://data/generated/levels/Guildhall/Guildhall_Contract_02.tatlevel.json
func _ue_sublevel_to_res(asset_path: String) -> String:
	var p: String = asset_path.strip_edges()
	if p == "":
		return ""
	var dot_idx: int = p.find(".")
	var base: String = p.substr(0, dot_idx) if dot_idx >= 0 else p
	var prefix: String = "/Game/Maps/"
	if base.begins_with(prefix):
		base = base.substr(prefix.length())
	elif base.begins_with("/Game/"):
		base = base.substr("/Game/".length())
	if base == "":
		return ""
	return "res://data/generated/levels/" + base + ".tatlevel.json"


## Resolved contract sublevel files that actually exist on disk.
## Used by the mission controller instead of the old Contract%02d wildcard.
func get_contract_sublevels(order: int) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in contracts:
		if int(c.get("order", -1)) != order:
			continue
		var subs: Variant = c.get("sublevels", [])
		if subs is Array:
			for s: Variant in (subs as Array):
				var res_path: String = _ue_sublevel_to_res(str(s))
				if res_path != "" and FileAccess.file_exists(res_path) and not out.has(res_path):
					out.append(res_path)
		break
	return out


## Mission-row match time limit in seconds for a mission id + difficulty
## (1 Novice, 2 Thief, 3 Master Thief), read from
## missions_by_id[id].durations (DT_Missions_* MatchDurationsByDifficulty).
## Free play uses the mission row's authored limit (LootTheRoom Novice = 3300,
## i.e. 55:00) instead of the map row's contract window. Returns 0.0 for an
## unknown id (unlimited), matching get_match_duration's safe default.
func get_mission_duration(mission_id: String, difficulty: int) -> float:
	var entry_v: Variant = missions_by_id.get(mission_id)
	if not (entry_v is Dictionary):
		return 0.0
	var durs_v: Variant = (entry_v as Dictionary).get("durations", [])
	if not (durs_v is Array) or (durs_v as Array).is_empty():
		return 0.0
	var durs: Array = durs_v as Array
	var idx: int = clampi(difficulty - 1, 0, durs.size() - 1)
	return float(durs[idx])


## Free-play / Cleanout Heist loot threshold for a mission id + difficulty.
## Values come from contracts.json's mission_loot_goals (QG objective node
## amounts parsed by tools/parse_contracts.py) with a documented static
## fallback for generated data that predates the parser key. Returns 0 when
## the mission authors no loot target.
func get_mission_loot_goal(mission_id: String, difficulty: int) -> int:
	var goals_v: Variant = mission_loot_goals.get(mission_id, null)
	if not (goals_v is Array):
		goals_v = FALLBACK_MISSION_LOOT_GOALS.get(mission_id, null)
	if not (goals_v is Array) or (goals_v as Array).is_empty():
		return 0
	var goals: Array = goals_v as Array
	var idx: int = clampi(difficulty - 1, 0, goals.size() - 1)
	return int(goals[idx])


## Match time limit in seconds for a map + difficulty (1 Novice, 2 Thief,
## 3 Master Thief). Returns 0.0 when unknown or unlimited (FTUE/tutorial and
## the Jaspering Hall expansion have no limit).
## G2: unknown map ids fail LOUD. The FTUE zero limit (unlimited) is the
## safe default — an invented timer on a real map would be worse — but the
## miss is push_error'd with the key and counted, never silently shared.
## Callers (mission_controller start_contract) keep working; the error tells
## the author which row to fix.
func get_match_duration(map_id: String, difficulty: int) -> float:
	var key: String = map_id.strip_edges().to_lower()
	if key == "jaspering_hall" or key == "jaspering" or key == "tutorial":
		key = "ftue" if mission_durations.has("ftue") else key
	var entry: Variant = mission_durations.get(key)
	if not (entry is Dictionary):
		if key != "ftue" and mission_durations.has("ftue"):
			_note_map_fallback(map_id, "unknown map inherits FTUE unlimited timer")
			entry = mission_durations.get("ftue")
		else:
			_note_map_fallback(map_id, "no durations and no FTUE row; unlimited")
	if not (entry is Dictionary):
		return 0.0
	var durs: Variant = (entry as Dictionary).get("durations", [])
	if not (durs is Array) or (durs as Array).is_empty():
		return 0.0
	var idx: int = clampi(difficulty - 1, 0, (durs as Array).size() - 1)
	return float((durs as Array)[idx])


## G1/G2 accounting: name the row, say why it fell back, count it. Cap the
## stored list at 64; the count stays exact.
func _note_map_fallback(row_key: String, why: String) -> void:
	map_fallback_count += 1
	if map_fallback_rows.size() < MAP_FALLBACK_MAX_ROWS and not map_fallback_rows.has(row_key):
		map_fallback_rows.append(row_key)
	push_warning("[game_data] map fallback (", why, ") for row '", row_key, "' (fallbacks=", map_fallback_count, ", cap=", MAP_FALLBACK_MAX_ROWS, ")")


func get_contract_display(order: int) -> Dictionary:
	var base: Dictionary = {}
	for c in contracts:
		if c["order"] == order:
			base = (c as Dictionary).duplicate()
			break
	var st: Dictionary = contract_strings.get(order, {})
	base["clue_facts"] = [] as Array[String] # key contract: always present, even with no string table.
	if not st.is_empty():
		var p: String = "Contract%d." % order
		base["title"] = st.get(p + "Title", base.get("id", "Contract %d" % order))
		base["description"] = st.get(p + "Description", "")
		base["quest_item"] = st.get(p + "QuestItem_Name", base.get("loot_tag", "Objective"))
		base["location"] = st.get(p + "QuestObjectLocation", base.get("map_id", ""))
		base["intro"] = st.get(p + "Intro", "")
		base["outro"] = st.get(p + "Outro", "")
		var clues: Array[String] = []
		for i in range(1, 7):
			var ck: String = "%sClue_%02d_Fact" % [p, i]
			if st.has(ck):
				clues.append(str(st[ck]))
		base["clue_facts"] = clues
	# Display-title fallback: a missing string-table entry leaves the raw row
	# id (e.g. "Contract.Main.3" — the Contract 3 table ships the key as
	# "Contract3.TItle") or an empty title when the contract has no table at
	# all. Rebuild a human-readable title from already-parsed quest data only
	# — never invent lore. Real titles are untouched.
	var raw_title: String = str(base.get("title", ""))
	if raw_title == "" or raw_title.begins_with("Contract."):
		var qi: String = str(base.get("quest_item", "")).strip_edges()
		var loc: String = str(base.get("location", "")).strip_edges()
		if qi != "" and qi != "Objective" and not qi.begins_with("Loot."):
			base["title"] = "Contract %d — %s" % [order, qi]
		elif loc != "":
			base["title"] = "Contract %d — %s" % [order, loc]
		else:
			base["title"] = "Contract %d" % order
	return base


func _extract_ue_text(v: Variant) -> String:
	if v is Dictionary:
		var d: Dictionary = v as Dictionary
		for k: String in ["LocalizedString", "SourceString", "CultureInvariantString"]:
			var s: String = str(d.get(k, "")).strip_edges()
			if s != "":
				return s
	elif v is String:
		return (v as String).strip_edges()
	return ""


func _ue_texture_to_res(asset_path: String) -> String:
	var p: String = asset_path.strip_edges()
	if p == "":
		return ""
	var dot_idx: int = p.find(".")
	var clean: String = p.substr(0, dot_idx) if dot_idx >= 0 else p
	if clean.begins_with("/Game/"):
		clean = clean.substr("/Game/".length())
	var raw_path: String = "res://assets/ue/Raw/" + clean + ".png"
	if ResourceLoader.exists(raw_path):
		return raw_path
	var content_path: String = "res://assets/ue/Content/" + clean + ".png"
	if ResourceLoader.exists(content_path):
		return content_path
	# G5: a never-imported raw .png passes FileAccess but fails at runtime
	# load(). Still returned (callers need a path), but named and counted —
	# an unimported icon is a pipeline gap, not a silent pass.
	if FileAccess.file_exists(raw_path) or FileAccess.file_exists(content_path):
		icon_unimported_count += 1
		var hit: String = raw_path if FileAccess.file_exists(raw_path) else content_path
		if icon_unimported_rows.size() < ICON_UNIMPORTED_MAX_ROWS and not icon_unimported_rows.has(asset_path):
			icon_unimported_rows.append(asset_path)
		push_warning("[game_data] icon path not imported (raw file only, runtime load() may fail): ", hit, " from UE '", asset_path, "' (unimported=", icon_unimported_count, ", cap=", ICON_UNIMPORTED_MAX_ROWS, ")")
		return hit
	return ""


func _mission_map_id(row_key: String, row: Dictionary = {}) -> String:
	var low: String = row_key.to_lower()
	var graph: String = ""
	var quest_graph: Variant = row.get("QuestGraph", {})
	if quest_graph is Dictionary:
		graph = str((quest_graph as Dictionary).get("AssetPathName", "")).to_lower()
	var hay: String = low + "|" + graph
	if "oldmanor" in hay:
		return "old_manor"
	if "guildhall" in hay:
		return "guildhall"
	if "thievesden" in hay:
		return "thieves_den"
	if "ftue" in hay:
		return "ftue"
	if "tutorial" in low:
		# Steam's tutorial is the FTUE map set, not a Jaspering Hall scene.
		return "ftue"
	_note_map_fallback(row_key, "unrecognized mission row routes to example")
	return "example"


## G4: difficulty durations read the shape the converter actually emits.
## Rows carry EITHER a 3-element MatchDurationsByDifficulty Array OR three
## scalar keys (MatchDurationsByDifficulty + [1] + [2]). The old code only
## read the scalar keys, so an Array-shaped row silently shared Novice
## across all difficulties. Array wins when valid; scalar keys next; d0
## fallback last (warned + counted, never silent).
func _match_durations_of(rv: Dictionary, rk: String) -> Array[float]:
	var raw_arr: Variant = rv.get("MatchDurationsByDifficulty", null)
	if raw_arr is Array and (raw_arr as Array).size() >= 3:
		var a: Array = raw_arr as Array
		return [float(a[0]), float(a[1]), float(a[2])]
	if rv.has("MatchDurationsByDifficulty[1]") or rv.has("MatchDurationsByDifficulty[2]"):
		var d0: float = float(rv.get("MatchDurationsByDifficulty", 0.0))
		var d1: float = float(rv.get("MatchDurationsByDifficulty[1]", d0))
		return [d0, d1, float(rv.get("MatchDurationsByDifficulty[2]", d1))]
	_note_map_fallback(rk, "no MatchDurationsByDifficulty data; durations default to 0")
	return [0.0, 0.0, 0.0]


func _load_missions() -> void:
	missions.clear()
	missions_by_id.clear()
	var files: Array[String] = [
		"res://data/generated/tables/Gameplay/Quests/CDT_Missions.json",
		"res://data/generated/tables/Gameplay/Quests/DT_Missions_OldManor.json",
		"res://data/generated/tables/Gameplay/Quests/DT_Missions_Guildhall.json",
		"res://data/generated/tables/Gameplay/Quests/DT_Missions_Tutorial.json",
		"res://data/generated/tables/Gameplay/Quests/DT_Missions_ThievesDen_Tutorial.json",
	]
	for fp: String in files:
		var parsed: Variant = _load_json(fp)
		if not (parsed is Dictionary):
			continue
		var rows_v: Variant = (parsed as Dictionary).get("rows", {})
		if not (rows_v is Dictionary):
			continue
		var rows: Dictionary = rows_v as Dictionary
		for rk_v: Variant in rows.keys():
			var rk: String = str(rk_v)
			if missions_by_id.has(rk):
				continue
			var rv_v: Variant = rows[rk_v]
			if not (rv_v is Dictionary):
				continue
			var rv: Dictionary = rv_v as Dictionary
			var title_s: String = _extract_ue_text(rv.get("Title", null))
			if title_s == "":
				title_s = rk
			var desc_s: String = _extract_ue_text(rv.get("Description", null))
			var durs: Array[float] = _match_durations_of(rv, rk)
			var img_raw: Variant = rv.get("ObjectiveDisplayImage", {})
			var img_ap: String = str((img_raw as Dictionary).get("AssetPathName", "")) if img_raw is Dictionary else ""
			var icon_res: String = _ue_texture_to_res(img_ap)
			var entry: Dictionary = {
				"id": rk,
				"map_id": _mission_map_id(rk, rv),
				"title": title_s,
				"description": desc_s,
				"durations": durs,
				"icon_path": icon_res,
				"icon_ue_path": img_ap,
				"source_file": fp.get_file(),
			}
			missions.append(entry)
			missions_by_id[rk] = entry


func get_all_missions() -> Array[Dictionary]:
	return missions


func get_missions_for_map(p_map_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in missions:
		if str(m.get("map_id", "")) == p_map_id:
			out.append(m)
	return out
