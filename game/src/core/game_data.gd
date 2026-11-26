extends Node
## Loads normalized UE5 DataTables, CurveTables, and StringTables from res://data/generated/tables/.

## Authored progression data (W9-P1): the per-difficulty endgame ladder. The
## getters below keep their documented fallbacks when the file is unreadable.
const Progression := preload("res://src/core/progression.gd")

var contracts: Array[Dictionary] = []
var curves: Dictionary = {} # table_name -> { row_name -> Array[{time, value}] }
var tables: Dictionary = {} # data table_name -> rows Dictionary (non-curve DataTables)
## Index of the standalone curve assets (tools/parse_curves.py -> curves.json,
## `tat2.curves/1`). curve name -> index record {name, type, channels, table,
## rows, time_range, ...}. The 16 records are the shipped curve assets that were
## emitted as standalone tables; eval_standalone_curve reads the table file the
## record names through `curves`, and falls back to the record's own `rows` for
## the four curves whose table sits outside the 13 scanned roots (UI/Settings,
## Gameplay/Indicators, MaterialLibrary/Character/EyeLibrary).
var standalone_curves: Dictionary = {}
## 1 when curves.json is absent or unreadable (export gate diagnostic; never fatal).
var curves_index_missing: int = 0
var _curves_index_loaded: bool = false
const CURVES_INDEX_PATH: String = "res://data/generated/curves.json"
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
## Authored clue data (tools/parse_clues.py -> gameplay/clues.json). Facts are
## keyed by their table:row id; clue sets keep every authored entry so the
## mission controller never invents a clue body. All lookups fail soft with a
## warning when the generated file is absent.
var clue_facts: Dictionary = {} # fact id -> authored fact record
var clue_fact_tags: Dictionary = {} # ClueFact.* tag -> Array[fact id]
var clue_sets: Dictionary = {} # CLS_* -> authored set + clues
var readable_visuals: Dictionary = {} # DA_ReadableVisuals_* -> actor class
var readable_spawners: Array[Dictionary] = [] # authored readable-clue spawners
var quest_spawners: Array[Dictionary] = [] # authored quest item spawners
var pickup_clues: Dictionary = {} # loot row -> authored pickup clue
var _pickup_clues_by_tag: Dictionary = {} # loot tag -> same record
var clue_stats: Dictionary = {}
var dead_fact_ids: Array[String] = []
var suppressed_fact_ids: Array[String] = []
var _clue_text_replacement: Dictionary = {}
## Authored quest graph data (tools/parse_quests.py -> gameplay/quests.json).
var quest_contracts: Dictionary = {} # Contract.Main.N -> authored row
var quest_missions: Dictionary = {} # Mission.* -> authored row
var quest_graphs: Dictionary = {} # QG_* -> authored graph
var loot_quest: Dictionary = {} # DT_LootInfo_Quest row -> authored row
var _loot_quest_by_tag: Dictionary = {} # Loot.Quest.* -> same record
var _quest_text_replacement: Dictionary = {}
var _mission_plan_cache: Dictionary = {}
## Authored briefing letters from StringTables/ST_Missions_*.json (parsed by
## tools/parse_quests.py) keyed by Mission.*. The raw text keeps the authored
## `{MatchDurationInMinutes}` / `{EndgameDurationInMinutes}` placeholders;
## format_mission_briefing() is the only code that substitutes them.
var mission_briefings: Dictionary = {}
## Tracked expansion overlay for briefing/endgame rules that differ from the
## extracted quest graph. game/data/expansion/briefing_overrides.json is
## hand-authored expansion data (not generated), e.g. the LootTheRoom letter's
## 20-minute magic door (1200 s, source KF13) over the QG's 480 s.
var briefing_overrides: Dictionary = {}
## W9-P1: 0-based difficulty index the authored endgame ladder resolves
## through (project.endgame_durations_by_difficulty = [1200, 600, 300]).
## -1 = nothing published, so get_mission_endgame_seconds() keeps the authored
## QG EndgameDuration exactly as before. GameState.reset_run() publishes
## clampi(difficulty - 1, 0, 2) at deploy: the run snapshots its difficulty and
## the controller needs no edit. It is NOT re-read mid-run.
var current_difficulty_index: int = -1
const BRIEFING_OVERRIDES_PATH: String = "res://data/expansion/briefing_overrides.json"
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
	_load_curves_index()
	_load_contracts()
	_load_contracts_json()
	_load_contract_strings()
	_load_missions()
	_load_clues()
	_load_quests()
	_load_briefing_overrides()


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


func _load_curves_index() -> void:
	if _curves_index_loaded:
		return
	_curves_index_loaded = true
	var doc: Variant = _load_json(CURVES_INDEX_PATH)
	if not (doc is Dictionary):
		curves_index_missing = 1
		push_warning("[curves] index missing: %s (standalone curve access keeps its documented fallbacks)" % CURVES_INDEX_PATH)
		return
	var recs: Variant = (doc as Dictionary).get("standalone", null)
	if not (recs is Array):
		curves_index_missing = 1
		push_warning("[curves] index has no standalone[] array: %s" % CURVES_INDEX_PATH)
		return
	for v: Variant in (recs as Array):
		if not (v is Dictionary):
			continue
		var rec: Dictionary = v as Dictionary
		var curve_name: String = str(rec.get("name", ""))
		if curve_name == "":
			continue
		standalone_curves[curve_name] = rec


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
	return _eval_keys((row as Dictionary).get("Keys", []), x, fallback)


## Shared key evaluator for the CurveTable cache and the standalone curve index.
## UE stores InterpMode on the key that STARTS a segment:
##   * RCIM_Constant holds that key's value until the next key's time
##     (Curve_AI_HeightDifferenceToStrengthMultiplier needs this: 1.0 across
##     2.0..3.0 m, then 0.0),
##   * RCIM_Linear / RCIM_Cubic keep the port's lerp. Cubic tangents are not
##     reconstructed here; a 2-key zero-tangent cubic (UE's smoothstep) is
##     reproduced at its own call site (light_probe.gd), not silently here.
## A curve with no InterpMode keeps the old lerp behaviour.
func _eval_keys(keys_v: Variant, x: float, fallback: float) -> float:
	if not (keys_v is Array):
		return fallback
	var keys: Array = keys_v as Array
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
			if str(ka.get("InterpMode", "")) == "RCIM_Constant" and x < t1:
				return v0
			return lerpf(v0, v1, (x - t0) / (t1 - t0))
	var last: Dictionary = keys[-1]
	return float(last.get("Value", fallback))


# ---------------------------------------------------------------------------
# Standalone curve index (curves.json -> tables the 13 roots do not scan)
# ---------------------------------------------------------------------------

## Every standalone curve the producer emitted, sorted (16 on the 2026-11-25 tree).
func standalone_curve_names() -> Array[String]:
	_load_curves_index()
	var out: Array[String] = []
	for name_v: Variant in standalone_curves.keys():
		out.append(str(name_v))
	out.sort()
	return out


## Authored [first key time, last key time] for a standalone curve, or
## Vector2.ZERO when the curve is unknown. Read from the index's `time_range`;
## the sensitivity ladders in input_actions.gd sample across this range.
func standalone_curve_range(curve_name: String) -> Vector2:
	_load_curves_index()
	var rec_v: Variant = standalone_curves.get(curve_name)
	if not (rec_v is Dictionary):
		return Vector2.ZERO
	var rec: Dictionary = rec_v
	var tr_v: Variant = rec.get("time_range", null)
	if tr_v is Array and (tr_v as Array).size() >= 2:
		return Vector2(float((tr_v as Array)[0]), float((tr_v as Array)[1]))
	var keys: Array = _standalone_keys(rec, "Value")
	if keys.size() < 2:
		return Vector2.ZERO
	return Vector2(float((keys[0] as Dictionary).get("Time", 0.0)), float((keys[-1] as Dictionary).get("Time", 0.0)))


## Samples one channel of a standalone curve by name. The table file the index
## names is preferred (`curves`), then the index's own `rows`; an unknown name or
## an unreadable curve returns `fallback` — never a crash.
func eval_standalone_curve(curve_name: String, x: float, channel: String = "Value", fallback: float = 0.0) -> float:
	_load_curves_index()
	var rec_v: Variant = standalone_curves.get(curve_name)
	if not (rec_v is Dictionary):
		return fallback
	var keys: Array = _standalone_keys(rec_v as Dictionary, channel)
	if keys.is_empty():
		return fallback
	return _eval_keys(keys, x, fallback)


## Keys for one channel of a standalone curve: the emitted table first, the
## index record second (UI/Settings, Indicators and EyeLibrary tables live
## outside the scanned roots, so their only copy is the index's `rows`).
func _standalone_keys(rec: Dictionary, channel: String) -> Array:
	var table_path: String = str(rec.get("table", ""))
	var table_name: String = table_path.get_file().get_basename() if table_path != "" else str(rec.get("name", ""))
	var tbl_v: Variant = curves.get(table_name)
	if tbl_v is Dictionary:
		var row_v: Variant = (tbl_v as Dictionary).get(channel)
		if row_v is Dictionary:
			var keys_v: Variant = (row_v as Dictionary).get("Keys", [])
			if keys_v is Array and not (keys_v as Array).is_empty():
				return keys_v as Array
	var rows_v: Variant = rec.get("rows", null)
	if rows_v is Dictionary:
		var index_row_v: Variant = (rows_v as Dictionary).get(channel)
		if index_row_v is Dictionary:
			var index_keys_v: Variant = (index_row_v as Dictionary).get("Keys", [])
			if index_keys_v is Array:
				return index_keys_v as Array
	return []


## Authored footstep-surface loudness multipliers
## (tools/parse_gameplay.py -> gameplay/guard_ai.json surface_loudness). Raw
## keys are the DA_LoudnessModifiers surface names (Carpet 0.0, Glass 1.5,
## Stone 1.5, ...); matching is case-insensitive. The seven AudioManager
## surface tokens the game emits are aliased to their authored physical row
## when the raw token is not itself a surface name. Unknown surfaces default
## to 1.0 (unmodified), never a guessed multiplier.
const SURFACE_LOUDNESS_PATH := "res://data/generated/gameplay/guard_ai.json"
const SURFACE_LOUDNESS_ALIASES: Dictionary = {
	"wood": "WoodFloor", # AU3 "wood" = Den timber floors (WoodFloor 1.5)
	"metal": "MetalThick", # every authored Metal* row is 1.5
	"wet": "Puddle", # Puddle/GroundWet both 1.5
	"earth": "Dirt", # Dirt 0.0
}
var _surface_loudness: Dictionary = {}
var _surface_loudness_loaded: bool = false


func _load_surface_loudness() -> void:
	_surface_loudness_loaded = true
	var data: Variant = _load_json(SURFACE_LOUDNESS_PATH)
	if not (data is Dictionary):
		return
	var rows: Variant = (data as Dictionary).get("surface_loudness", {})
	if not (rows is Dictionary):
		return
	for k: Variant in (rows as Dictionary).keys():
		_surface_loudness[str(k).to_lower()] = float((rows as Dictionary)[k])


## Authored loudness multiplier for a footstep surface. "" / unknown -> 1.0.
func get_surface_loudness(surface: String) -> float:
	var key: String = surface.strip_edges()
	if key == "":
		return 1.0
	if not _surface_loudness_loaded:
		_load_surface_loudness()
	key = key.split("/")[-1].split(".")[-1].to_lower()
	if _surface_loudness.has(key):
		return float(_surface_loudness[key])
	var alias: String = str(SURFACE_LOUDNESS_ALIASES.get(key, ""))
	if alias != "" and _surface_loudness.has(alias.to_lower()):
		return float(_surface_loudness[alias.to_lower()])
	return 1.0


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


## Authored briefing letter record for a mission id (StringTables/ST_Missions_*).
## `text` is raw: the `{MatchDurationInMinutes}` / `{EndgameDurationInMinutes}`
## placeholders are still present. Empty when the mission authors no letter.
func get_mission_briefing_record(mission_id: String) -> Dictionary:
	var rec_v: Variant = mission_briefings.get(mission_id)
	if not (rec_v is Dictionary):
		return {}
	return (rec_v as Dictionary).duplicate(true)


## Endgame (magic escape door) window in seconds.
##
## Precedence is fixed (W9-P1 keeps the order, adds one level):
##   1. the tracked briefing override (KF13) — LootTheRoom's 20-minute letter,
##      authored as 1200 s against the quest graph's 480 s; it always wins;
##   2. the authored per-difficulty ladder,
##      project.endgame_durations_by_difficulty = [1200, 600, 300]
##      (progression.endgame_seconds_for_difficulty, index order only — the
##      producer labels the index -> difficulty map "unproven");
##   3. the mission plan's authored QG EndgameDuration (480 LootTheRoom/OldManor,
##      300 Guildhall VaultHeist);
##   4. the caller's 480 s fallback (mission_controller.ENDGAME_FALLBACK_SEC).
##
## Ladder selection: an explicit `difficulty_index` (0-based) wins; otherwise
## `current_difficulty_index` is used when a deploy published one. That field
## is written by GameState.reset_run() (clampi(difficulty - 1, 0, 2)), so the
## run clock gets the ladder without a mission_controller edit. -1 (default,
## nothing published) preserves the pre-W9 behaviour exactly: the QG plan.
func get_mission_endgame_seconds(mission_id: String, difficulty_index: int = -1) -> float:
	var ov_v: Variant = briefing_overrides.get(mission_id)
	if ov_v is Dictionary:
		var secs: Variant = (ov_v as Dictionary).get("endgame_seconds", null)
		if secs is float or secs is int:
			return float(secs)
	# PORT DECISION (W9-P1): the authored global ladder outranks a mission's own
	# quest-graph EndgameDuration when a difficulty is known. The user decision
	# for this wave is "adopt the authored EndgameDurationsByDifficulty" with the
	# KF13 override preserved; the QG values (VaultHeist 300, OldManor 480) stay
	# recorded in get_mission_plan() and are still asserted, they just no longer
	# win the run clock. The producer labels the index->difficulty map
	# "unproven: index order only", so the mapping is documented in progression.gd.
	var idx: int = difficulty_index if difficulty_index >= 0 else current_difficulty_index
	if idx >= 0 and Progression.endgame_ladder_authored():
		return Progression.endgame_seconds_for_difficulty(idx)
	var plan: Dictionary = get_mission_plan(mission_id)
	return float(plan.get("endgame_duration", 0.0))


## Runtime source label for an endgame window: "KF13" (tracked override),
## "project_settings" (authored per-difficulty ladder) or "quest_graph" (the
## plan's EndgameDuration node / the caller's fallback). Printed by the mission
## controller so the provenance of the door window is visible in the log.
func get_mission_endgame_source(mission_id: String, difficulty_index: int = -1) -> String:
	var ov_v: Variant = briefing_overrides.get(mission_id)
	if ov_v is Dictionary:
		return str((ov_v as Dictionary).get("source", ""))
	var idx: int = difficulty_index if difficulty_index >= 0 else current_difficulty_index
	if idx >= 0 and Progression.endgame_ladder_authored():
		return "project_settings"
	return "quest_graph"


## Format an authored briefing letter for the HUD. Only the two authored
## placeholders are substituted, from seconds (never a hand-typed minute count
## in UI code). CRLF is normalised so Label renders the authored line breaks.
static func format_mission_briefing(raw: String, match_seconds: float, endgame_seconds: float) -> String:
	var text: String = raw.replace("\r\n", "\n").replace("\r", "\n")
	var match_min: int = int(round(match_seconds / 60.0)) if match_seconds > 0.0 else 0
	var endgame_min: int = int(round(endgame_seconds / 60.0)) if endgame_seconds > 0.0 else 0
	if match_min > 0:
		text = text.replace("{MatchDurationInMinutes}", str(match_min))
	if endgame_min > 0:
		text = text.replace("{EndgameDurationInMinutes}", str(endgame_min))
	if text.find("{MatchDurationInMinutes}") >= 0 or text.find("{EndgameDurationInMinutes}") >= 0:
		push_warning("[game_data] briefing placeholders left unsubstituted: match=", match_seconds, " endgame=", endgame_seconds)
	return text.strip_edges()


## Convenience: formatted letter for a mission, defaulting the match window to
## the mission row's Novice limit and the endgame window to the override/plan.
func get_mission_briefing_text(mission_id: String, match_seconds: float = -1.0, endgame_seconds: float = -1.0) -> String:
	var rec: Dictionary = get_mission_briefing_record(mission_id)
	if rec.is_empty():
		return ""
	var match_s: float = match_seconds
	if match_s < 0.0:
		match_s = get_mission_duration(mission_id, 1)
	var endgame_s: float = endgame_seconds
	if endgame_s < 0.0:
		endgame_s = get_mission_endgame_seconds(mission_id)
	return format_mission_briefing(str(rec.get("text", "")), match_s, endgame_s)


func _load_briefing_overrides() -> void:
	briefing_overrides.clear()
	if not ParityGovernance.record_allowed(BRIEFING_OVERRIDES_PATH):
		# P0b parity-only: the KF13 briefing/endgame overlay is TAT-2 expansion
		# content. Excluded, the authored QG EndgameDuration (480 s) and the
		# authored per-difficulty ladder stay authoritative. Default off = no
		# change.
		print("[game_data] TAT2_PARITY_ONLY=1: briefing override overlay excluded; authored quest-graph values stay authoritative")
		return
	var data: Variant = _load_json(BRIEFING_OVERRIDES_PATH)
	if not (data is Dictionary):
		push_warning("[game_data] briefing_overrides.json missing or unreadable; extracted quest-graph endgame values stay authoritative")
		return
	var rows_v: Variant = (data as Dictionary).get("briefings", {})
	if not (rows_v is Dictionary):
		push_warning("[game_data] briefing_overrides.json has no 'briefings' object")
		return
	for mid_v: Variant in (rows_v as Dictionary).keys():
		var mid: String = str(mid_v)
		var rec_v: Variant = (rows_v as Dictionary)[mid_v]
		if not (rec_v is Dictionary):
			push_warning("[game_data] briefing override '", mid, "' is not an object; skipped")
			continue
		var rec: Dictionary = (rec_v as Dictionary).duplicate(true)
		var secs: Variant = rec.get("endgame_seconds", null)
		if not (secs is int or secs is float) or float(secs) <= 0.0:
			push_warning("[game_data] briefing override '", mid, "' has no positive endgame_seconds; skipped")
			continue
		if str(rec.get("source", "")).strip_edges() == "":
			push_warning("[game_data] briefing override '", mid, "' has no source; provenance is required")
		if not quest_missions.has(mid) and not mission_briefings.has(mid):
			push_warning("[game_data] briefing override '", mid, "' matches no authored mission row/letter")
		briefing_overrides[mid] = rec


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


# --- Authored clues (gameplay/clues.json) ---------------------------------

func _load_clues() -> void:
	var data: Variant = _load_json("res://data/generated/gameplay/clues.json")
	if not (data is Dictionary):
		push_warning("[game_data] gameplay/clues.json missing or unreadable; authored clue data unavailable")
		return
	var d: Dictionary = data as Dictionary
	var facts_v: Variant = d.get("facts", {})
	if facts_v is Dictionary:
		clue_facts = (facts_v as Dictionary).duplicate(true)
	var tags_v: Variant = d.get("fact_tags", {})
	if tags_v is Dictionary:
		clue_fact_tags = (tags_v as Dictionary).duplicate(true)
	var sets_v: Variant = d.get("clue_sets", {})
	if sets_v is Dictionary:
		clue_sets = (sets_v as Dictionary).duplicate(true)
	var vis_v: Variant = d.get("readable_visuals", {})
	if vis_v is Dictionary:
		readable_visuals = (vis_v as Dictionary).duplicate(true)
	readable_spawners = _dict_array(d.get("readable_spawners", []))
	quest_spawners = _dict_array(d.get("quest_spawners", []))
	var pickups_v: Variant = d.get("pickup_clues", [])
	if pickups_v is Array:
		for rec_v: Variant in (pickups_v as Array):
			if not (rec_v is Dictionary):
				continue
			var rec: Dictionary = rec_v as Dictionary
			var row: String = str(rec.get("loot_row", ""))
			var tag: String = str(rec.get("loot_tag", ""))
			if row != "":
				pickup_clues[row] = rec
			if tag != "":
				_pickup_clues_by_tag[tag] = rec
	var stats_v: Variant = d.get("stats", {})
	if stats_v is Dictionary:
		clue_stats = (stats_v as Dictionary).duplicate(true)
	var tr_v: Variant = d.get("text_replacement", {})
	if tr_v is Dictionary:
		_clue_text_replacement = (tr_v as Dictionary).duplicate(true)
	dead_fact_ids = _string_array(d.get("dead_fact_ids", []))
	suppressed_fact_ids = _string_array(d.get("suppressed_fact_ids", []))
	var validation: Variant = d.get("validation", {})
	if validation is Dictionary and (validation as Dictionary).get("ok", false) != true:
		push_error("[game_data] clues.json validation is not ok; see gameplay/clues.json")


func _dict_array(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for item: Variant in (value as Array):
			if item is Dictionary:
				out.append((item as Dictionary).duplicate(true))
	return out


func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item: Variant in (value as Array):
			out.append(str(item))
	return out


## Authored clue fact by id ("DT_ClueFacts_Contracts_02:Clue01"). Returns the
## record including journal_text, display_priority and fact_tag, or {}.
func get_fact(id: String) -> Dictionary:
	var row_v: Variant = clue_facts.get(id)
	return (row_v as Dictionary).duplicate(true) if row_v is Dictionary else {}


## Fact ids authored for a ClueFact.* tag. `tables` optionally limits the
## answer to facts from those DT_ClueFacts_* tables.
func get_fact_ids_for_tag(tag: String, tables: Array = []) -> Array[String]:
	var out: Array[String] = []
	var ids_v: Variant = clue_fact_tags.get(tag)
	if ids_v is Array:
		for id_v: Variant in (ids_v as Array):
			var fid: String = str(id_v)
			if tables.is_empty():
				out.append(fid)
				continue
			var fact: Dictionary = get_fact(fid)
			if tables.has(str(fact.get("table", ""))):
				out.append(fid)
	return out


## Clue set by asset name ("CLS_Contract_02") or UE path
## ("/Game/.../CLS_Contract_02.CLS_Contract_02").
func get_clue_set(name_or_asset: String) -> Dictionary:
	var key: String = _clue_set_key(name_or_asset)
	if key == "":
		return {}
	return (clue_sets[key] as Dictionary).duplicate(true)


func _clue_set_key(name_or_asset: String) -> String:
	var key: String = name_or_asset.strip_edges()
	if key == "":
		return ""
	if clue_sets.has(key):
		return key
	var dot: int = key.rfind(".")
	if dot >= 0:
		var short_name: String = key.substr(dot + 1)
		if clue_sets.has(short_name):
			return short_name
	var slash: int = key.rfind("/")
	if slash >= 0:
		var leaf: String = key.substr(slash + 1)
		if clue_sets.has(leaf):
			return leaf
	return ""


## Authored readable-clue spawner records for a map (and optional exact
## placement tag / loaded level filter). Never synthesises a position.
func get_readable_spawners(map_id: String, placement_tag: String = "", levels: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in readable_spawners:
		if str(rec.get("map_id", "")) != map_id:
			continue
		if placement_tag != "" and str(rec.get("placement_tag", "")) != placement_tag:
			continue
		if not levels.is_empty() and not levels.has(str(rec.get("level", ""))):
			continue
		out.append(rec.duplicate(true))
	return out


## Authored quest-item spawner records for a map + QuestLocation.* tag with
## the full pos/basis transform (readable by mission_controller).
func get_quest_spawners(map_id: String, quest_location_tag: String = "", levels: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in quest_spawners:
		if str(rec.get("map_id", "")) != map_id:
			continue
		if quest_location_tag != "" and str(rec.get("quest_location_tag", "")) != quest_location_tag:
			continue
		if not levels.is_empty() and not levels.has(str(rec.get("level", ""))):
			continue
		out.append(rec.duplicate(true))
	return out


## Authored civilian body/head variants (spawners.json civilian_meshes) for
## runtime NPC actors that are not mission spawners (e.g. the Spider courier /
## 04 informant). The hardcoded pair is the same extracted values and applies
## only when the generated file is absent; it is existence-checked at parse
## time, never invented here.
const CIVILIAN_MESH_FALLBACK := [
	{"body": "res://assets/ue/Content/Art/Animation/CivMale/Skin/Common/SK_CivMale_Common_01.glb", "head": "res://assets/ue/Content/Art/Animation/CivMale/Skin/Heads/SK_CivMale_Head_Adam_Fade01.glb"},
	{"body": "res://assets/ue/Content/Art/Animation/CivFemale/Skin/Common/SK_CivFemale_Common_01C.glb", "head": "res://assets/ue/Content/Art/Animation/CivFemale/Skin/Heads/SK_CivFemale_Head_Abby_Short01.glb"},
]
var _civilian_meshes: Array[Dictionary] = []


func get_civilian_meshes() -> Array[Dictionary]:
	if not _civilian_meshes.is_empty():
		return _civilian_meshes
	var data: Variant = _load_json("res://data/generated/gameplay/spawners.json")
	if data is Dictionary:
		var civs_v: Variant = (data as Dictionary).get("civilian_meshes", {})
		if civs_v is Dictionary:
			for ckey: Variant in (civs_v as Dictionary).keys():
				var c_v: Variant = (civs_v as Dictionary)[ckey]
				if not (c_v is Dictionary):
					continue
				var c: Dictionary = c_v as Dictionary
				var body: String = str(c.get("body_res_path", ""))
				var head: String = str(c.get("head_res_path", ""))
				if body != "" and head != "":
					_civilian_meshes.append({"body": body, "head": head})
	if _civilian_meshes.is_empty():
		for rec: Dictionary in CIVILIAN_MESH_FALLBACK:
			_civilian_meshes.append(rec.duplicate(true))
	return _civilian_meshes


## Authored pickup clue for a DT_LootInfo_Quest row or loot tag.
func get_pickup_clue(loot_row: String) -> Dictionary:
	var row_v: Variant = pickup_clues.get(loot_row)
	if row_v is Dictionary:
		return (row_v as Dictionary).duplicate(true)
	var tag_v: Variant = _pickup_clues_by_tag.get(loot_row)
	if tag_v is Dictionary:
		return (tag_v as Dictionary).duplicate(true)
	return {}


# --- Authored quests (gameplay/quests.json) --------------------------------

func _load_quests() -> void:
	var data: Variant = _load_json("res://data/generated/gameplay/quests.json")
	if not (data is Dictionary):
		push_warning("[game_data] gameplay/quests.json missing or unreadable; authored quest data unavailable")
		return
	var d: Dictionary = data as Dictionary
	var c_v: Variant = d.get("contracts", {})
	if c_v is Dictionary:
		quest_contracts = (c_v as Dictionary).duplicate(true)
	var m_v: Variant = d.get("missions", {})
	if m_v is Dictionary:
		quest_missions = (m_v as Dictionary).duplicate(true)
	var mb_v: Variant = d.get("mission_briefings", {})
	if mb_v is Dictionary:
		mission_briefings = (mb_v as Dictionary).duplicate(true)
	var g_v: Variant = d.get("quest_graphs", {})
	if g_v is Dictionary:
		quest_graphs = (g_v as Dictionary).duplicate(true)
	var l_v: Variant = d.get("loot_quest", {})
	if l_v is Dictionary:
		loot_quest = (l_v as Dictionary).duplicate(true)
		for row_key: Variant in loot_quest.keys():
			var rec: Variant = loot_quest[row_key]
			if rec is Dictionary:
				var tag: String = str((rec as Dictionary).get("loot_tag", ""))
				if tag != "":
					_loot_quest_by_tag[tag] = rec
	var tr_v: Variant = d.get("text_replacement", {})
	if tr_v is Dictionary:
		_quest_text_replacement = (tr_v as Dictionary).duplicate(true)
	_mission_plan_cache.clear()
	var validation: Variant = d.get("validation", {})
	if validation is Dictionary and (validation as Dictionary).get("ok", false) != true:
		push_error("[game_data] quests.json validation is not ok; see gameplay/quests.json")


## Authored contract row from quests.json (quest objective, clue set, texts).
func get_quest_contract(order_or_id: Variant) -> Dictionary:
	for key_v: Variant in quest_contracts.keys():
		var row_v: Variant = quest_contracts[key_v]
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		if (order_or_id is int or order_or_id is float) and int(row.get("order", -1)) == int(order_or_id):
			return row.duplicate(true)
		if str(key_v) == str(order_or_id):
			return row.duplicate(true)
	return {}


## Authored DT_LootInfo_Quest row by row name ("RedGem") or loot tag
## ("Loot.Quest.Set.RedGem").
func get_loot_quest_row(row: String) -> Dictionary:
	var by_row: Variant = loot_quest.get(row)
	if by_row is Dictionary:
		return (by_row as Dictionary).duplicate(true)
	var by_tag: Variant = _loot_quest_by_tag.get(row)
	if by_tag is Dictionary:
		return (by_tag as Dictionary).duplicate(true)
	return {}


## Authored quest graph by name ("QG_Guildhall_Set") or UE asset path.
func get_quest_graph(name: String) -> Dictionary:
	var key: String = name.strip_edges()
	if key == "":
		return {}
	if not quest_graphs.has(key):
		var dot: int = key.rfind(".")
		if dot >= 0:
			key = key.substr(dot + 1)
		var slash: int = key.rfind("/")
		if slash >= 0 and not quest_graphs.has(key):
			key = key.substr(slash + 1)
	var graph_v: Variant = quest_graphs.get(key)
	return (graph_v as Dictionary).duplicate(true) if graph_v is Dictionary else {}


## Authored St_Clues_TextReplacement entry (e.g. "Missions.GH.Set").
func get_text_replacement(key: String) -> String:
	var rec_v: Variant = _quest_text_replacement.get(key)
	if rec_v is Dictionary:
		return str((rec_v as Dictionary).get("text", ""))
	rec_v = _clue_text_replacement.get(key)
	if rec_v is Dictionary:
		return str((rec_v as Dictionary).get("text", ""))
	return ""


## Authored mission plan: DT mission row + reachable QG objectives (items
## enriched from DT_LootInfo_Quest), reachable clue-set nodes, and the QG
## MatchMainPhase/Endgame durations. Cached per mission id.
func get_mission_plan(mission_id: String) -> Dictionary:
	if _mission_plan_cache.has(mission_id):
		return (_mission_plan_cache[mission_id] as Dictionary).duplicate(true)
	var row_v: Variant = quest_missions.get(mission_id)
	if not (row_v is Dictionary):
		push_warning("[game_data] get_mission_plan: unknown mission id '", mission_id, "'")
		return {}
	var plan: Dictionary = (row_v as Dictionary).duplicate(true)
	plan["mission_id"] = mission_id
	if not plan.has("map_id") or str(plan.get("map_id", "")) == "":
		plan["map_id"] = _mission_map_id(mission_id, {})
	var graph_name: String = str(plan.get("quest_graph", ""))
	var graph: Dictionary = {}
	var graph_v: Variant = quest_graphs.get(graph_name)
	if graph_v is Dictionary:
		graph = graph_v as Dictionary
	else:
		push_warning("[game_data] get_mission_plan: mission '", mission_id, "' references missing quest graph '", graph_name, "'")
	var objectives: Array[Dictionary] = []
	var clue_refs: Array[Dictionary] = []
	var main_phase: float = 0.0
	var endgame: float = 0.0
	var seen_sets: Dictionary = {}
	if not graph.is_empty():
		var nodes_v: Variant = graph.get("nodes", {})
		if nodes_v is Dictionary:
			var nodes: Dictionary = nodes_v as Dictionary
			for node_key: Variant in nodes.keys():
				var node_v: Variant = nodes[node_key]
				if not (node_v is Dictionary):
					continue
				var node: Dictionary = node_v as Dictionary
				if node.get("reachable", false) != true:
					continue
				var ntype: String = str(node.get("type", ""))
				if ntype == "TATQuestGraphObjectiveNode":
					objectives.append(_enrich_plan_objective(node, graph))
				elif ntype == "TATQuestGraphClueSetNode" or ntype == "TATQuestGraphClueSetForSpawnNode":
					var set_name: String = str(node.get("clue_set", ""))
					if set_name != "":
						clue_refs.append({
							"graph": graph_name,
							"node": str(node_key),
							"node_type": ntype,
							"clue_set": set_name,
							"loot_tag": str(node.get("loot_tag", "")),
						})
						seen_sets[set_name] = true
				elif ntype == "TATQuestGraphPropertyNode":
					match str(node.get("property_type", "")):
						"MatchMainPhaseDuration":
							main_phase = maxf(main_phase, float(node.get("duration", 0.0)))
						"EndgameDuration":
							endgame = maxf(endgame, float(node.get("endgame_duration", 0.0)))
	plan["objectives"] = objectives
	plan["clue_set_nodes"] = clue_refs
	plan["clue_sets"] = seen_sets.keys()
	plan["main_phase_duration"] = main_phase
	plan["endgame_duration"] = endgame
	var loot_goals: Array[int] = []
	var by_difficulty: Dictionary = {}
	for obj: Dictionary in objectives:
		var amount_v: Variant = obj.get("amount", null)
		if amount_v == null:
			continue
		var difficulty: int = int(obj.get("difficulty", 0))
		if difficulty <= 0:
			loot_goals.append(int(amount_v))
		else:
			by_difficulty[difficulty] = int(amount_v)
	if by_difficulty.is_empty():
		pass
	else:
		loot_goals.clear()
		for d_idx: int in range(1, 4):
			if by_difficulty.has(d_idx):
				loot_goals.append(int(by_difficulty[d_idx]))
	plan["loot_goals"] = loot_goals
	var text: String = ""
	var min_steal: Variant = null
	var override_min: Variant = null
	for obj: Dictionary in objectives:
		if text == "" and str(obj.get("objective_text", "")) != "":
			text = str(obj.get("objective_text", ""))
		if min_steal == null and obj.get("min_number_to_steal", null) != null:
			min_steal = obj.get("min_number_to_steal")
			override_min = obj.get("override_min_number_to_steal")
	plan["objective_text"] = text
	plan["min_number_to_steal"] = min_steal
	plan["override_min_number_to_steal"] = override_min
	_mission_plan_cache[mission_id] = plan
	return plan.duplicate(true)


## Enrich an authored objective dictionary: loot rows, display names, actor
## classes and the effective QuestLocation tag. Shared by mission plans and
## contract deploys so both read the shipped DT_LootInfo_Quest row.
func enrich_quest_objective(objective_in: Dictionary) -> Dictionary:
	var objective: Dictionary = objective_in.duplicate(true)
	var items: Array[Dictionary] = []
	var raw_items: Variant = objective.get("items", [])
	if raw_items is Array:
		for item_v: Variant in (raw_items as Array):
			if not (item_v is Dictionary):
				continue
			var item: Dictionary = (item_v as Dictionary).duplicate(true)
			var loot_tag: String = str(item.get("loot_tag", ""))
			var loot_row: Dictionary = get_loot_quest_row(loot_tag)
			item["loot_row"] = str(loot_row.get("row", ""))
			item["display_name"] = str(loot_row.get("display_name", ""))
			item["actor_class"] = str(loot_row.get("actor_class", ""))
			item["actor_class_ue"] = str(loot_row.get("actor_class_ue", ""))
			item["value"] = int(loot_row.get("value", 0))
			var effective: String = str(item.get("quest_spawn_location", ""))
			# The objective item's authored QuestSpawnLocation wins; the loot
			# row's QuestLocationTag is the fallback only when the objective
			# authors no location (e.g. a generic Item reference).
			if effective == "" or effective == "None":
				var row_loc: String = str(loot_row.get("quest_location_tag", ""))
				if row_loc != "":
					effective = row_loc
			item["effective_quest_location"] = effective
			items.append(item)
	objective["items"] = items
	var label: String = str(objective.get("objective_text", ""))
	objective["label"] = label
	return objective


## Enrich one authored objective node: loot rows, display names, actor
## classes and the effective QuestLocation tag.
func _enrich_plan_objective(node: Dictionary, graph: Dictionary) -> Dictionary:
	var obj_v: Variant = node.get("objective", {})
	var objective: Dictionary = enrich_quest_objective(obj_v as Dictionary if obj_v is Dictionary else {})
	objective["node"] = str(node.get("name", ""))
	objective["difficulty"] = _objective_difficulty(graph, str(node.get("name", "")))
	return objective


## Difficulty gate on the edge that enters an objective node (world tag
## query Difficulty.Novice / Thief / MasterThief). 0 = unconditional.
func _objective_difficulty(graph: Dictionary, node_name: String) -> int:
	var nodes_v: Variant = graph.get("nodes", {})
	if not (nodes_v is Dictionary):
		return 0
	var nodes: Dictionary = nodes_v as Dictionary
	var node_v: Variant = nodes.get(node_name)
	if not (node_v is Dictionary):
		return 0
	var parents_v: Variant = (node_v as Dictionary).get("parents", [])
	if not (parents_v is Array):
		return 0
	for parent_v: Variant in (parents_v as Array):
		var parent_node_v: Variant = nodes.get(str(parent_v))
		if not (parent_node_v is Dictionary):
			continue
		var edges_v: Variant = (parent_node_v as Dictionary).get("edges", [])
		if not (edges_v is Array):
			continue
		for edge_v: Variant in (edges_v as Array):
			if not (edge_v is Dictionary):
				continue
			var edge: Dictionary = edge_v as Dictionary
			if str(edge.get("target", "")) != node_name:
				continue
			var query_v: Variant = edge.get("world_tag_query", null)
			if not (query_v is Dictionary):
				continue
			var tags_v: Variant = (query_v as Dictionary).get("TagDictionary", [])
			if not (tags_v is Array):
				continue
			for tag_v: Variant in (tags_v as Array):
				var tag: String = str((tag_v as Dictionary).get("TagName", "")) if tag_v is Dictionary else ""
				match tag:
					"Difficulty.Novice":
						return 1
					"Difficulty.Thief":
						return 2
					"Difficulty.MasterThief":
						return 3
	return 0
