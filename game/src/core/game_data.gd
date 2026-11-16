extends Node
## Loads normalized UE5 DataTables, CurveTables, and StringTables from res://data/generated/tables/.

var contracts: Array[Dictionary] = []
var curves: Dictionary = {} # table_name -> { row_name -> Array[{time, value}] }
var tables: Dictionary = {} # data table_name -> rows Dictionary (non-curve DataTables)
var contract_strings: Dictionary = {} # contract_order -> Dictionary[key -> text]

func _ready() -> void:
	_load_curves()
	_load_contracts()
	_load_contract_strings()


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
	# Add TAT-2 Expansion Contracts (17-18)
	contracts.append({
		"id": "Contract.Expansion.17",
		"order": 17,
		"map_id": "jaspering_hall",
		"map_path": "res://scenes/maps/jaspering_hall.tscn",
		"loot_tag": "Loot.Quest.BlueMalcolm",
		"outro_flow": "Expansion",
		"title": "The Blue Malcolm",
		"description": "Infiltrate Jaspering Hall, bypass the Private Security detail, and liberate the Blue Malcolm painting from Rose Hall's private vault.",
		"quest_item": "Blue Malcolm Painting",
		"location": "Jaspering Hall — Rose Gallery",
		"sublevels": [],
		"sublevel_tag": "",
	})
	contracts.append({
		"id": "Contract.Expansion.18",
		"order": 18,
		"map_id": "jaspering_hall",
		"map_path": "res://scenes/maps/jaspering_hall.tscn",
		"loot_tag": "Loot.Quest.OberonSeal",
		"outro_flow": "Expansion",
		"title": "The Jaspering Vault",
		"description": "Breach the twin-lock Jaspering Hall Treasury and steal the Arcane Seal of Oberon before the Constabulary lockdown.",
		"quest_item": "Arcane Seal of Oberon",
		"location": "Jaspering Hall — Lower Treasury",
		"sublevels": [],
		"sublevel_tag": "",
	})


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
				if parts.size() >= 2:
					var prefix: String = parts[1] # e.g. Contract2
					var num: int = int(prefix.replace("Contract", ""))
					contract_strings[num] = (data as Dictionary)["entries"]
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


func get_contract_display(order: int) -> Dictionary:
	var base: Dictionary = {}
	for c in contracts:
		if c["order"] == order:
			base = (c as Dictionary).duplicate()
			break
	var st: Dictionary = contract_strings.get(order, {})
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
	return base
