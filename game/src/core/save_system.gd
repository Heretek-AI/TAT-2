extends Node
## Atomic JSON save system (mirrors TATAtomicSave): XP, level, completed contracts, settings.
## Workstream 2: progression state (currency, unlocks, loadouts, den decoration).

const SAVE_PATH := "user://tat2_save.json"
const TMP_PATH := "user://tat2_save.json.tmp"

const XP_PER_LEVEL := 500

var data: Dictionary = {
	"xp": 0,
	"level": 1,
	"completed_contracts": {},
	"unlocked_tools": ["blackjack", "slither_sap", "smoke_bomb", "pickpocket_fairy", "zipwire"],
	"unlocked_perks": ["novice_difficulty", "guildhall", "old_manor", "spider"],
	"unlocked_cosmetics": ["bowler_hat"],
	"currency": 26275,
	"equipped_loadout": ["blackjack", "smoke_bomb", "zipwire", "slither_sap"],
	"equipped_cosmetics": {"head": "bowler_hat", "body": "", "calling_card": ""},
	"active_decoration": "faberge_egg",
	"settings": {
		"mouse_sensitivity": 0.0025,
		"sprint_toggle": false,
		"fov": 75.0,
	},
}


func _ready() -> void:
	load_save()


func _defaults() -> Dictionary:
	return {
		"xp": 0,
		"level": 1,
		"completed_contracts": {},
		"unlocked_tools": ["blackjack", "slither_sap", "smoke_bomb", "pickpocket_fairy", "zipwire"],
		"unlocked_perks": ["novice_difficulty", "guildhall", "old_manor", "spider"],
		"unlocked_cosmetics": ["bowler_hat"],
		"currency": 26275,
		"equipped_loadout": ["blackjack", "smoke_bomb", "zipwire", "slither_sap"],
		"equipped_cosmetics": {"head": "bowler_hat", "body": "", "calling_card": ""},
		"active_decoration": "faberge_egg",
	}


func _ensure_defaults() -> void:
	var defaults: Dictionary = _defaults()
	for key: Variant in defaults.keys():
		var k: String = str(key)
		if not data.has(k):
			data[k] = (defaults[k] as Variant)
	# Legacy saves may use "slithersap" without underscore; normalize it.
	if data.has("unlocked_tools") and data["unlocked_tools"] is Array:
		var tools: Array = data["unlocked_tools"] as Array
		if tools.has("slithersap") and not tools.has("slither_sap"):
			tools.append("slither_sap")
	# Guarantee the two starter tools even if an old save overwrote the list.
	for starter: String in ["zipwire", "smoke_bomb"]:
		var arr: Array = data["unlocked_tools"] as Array
		if not arr.has(starter):
			arr.append(starter)
	# Guarantee starter perks / cosmetics on old saves.
	if data.has("unlocked_perks") and data["unlocked_perks"] is Array:
		var perks: Array = data["unlocked_perks"] as Array
		for pid: String in ["novice_difficulty", "guildhall", "old_manor", "spider"]:
			if not perks.has(pid):
				perks.append(pid)
	if data.has("unlocked_cosmetics") and data["unlocked_cosmetics"] is Array:
		var cosmetics: Array = data["unlocked_cosmetics"] as Array
		if not cosmetics.has("bowler_hat"):
			cosmetics.append("bowler_hat")


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_ensure_defaults()
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		_ensure_defaults()
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var pd: Dictionary = parsed as Dictionary
		data.merge(pd, true)
	_ensure_defaults()


func write_save() -> void:
	var f: FileAccess = FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		dir.rename("tat2_save.json.tmp", "tat2_save.json")


func record_contract_complete(order: int, score: int, ghost: bool) -> void:
	var k: String = str(order)
	var prev_raw: Variant = data["completed_contracts"].get(k, {})
	var prev: Dictionary = prev_raw as Dictionary if prev_raw is Dictionary else {}
	data["completed_contracts"][k] = {
		"best_score": maxi(int(prev.get("best_score", 0)), score),
		"ghost": bool(prev.get("ghost", false)) or ghost,
	}
	data["xp"] = int(data["xp"]) + maxi(100, score / 2)
	data["level"] = maxi(int(data.get("level", 1)), int(data["xp"]) / XP_PER_LEVEL + 1)
	write_save()


func get_currency() -> int:
	return int(data.get("currency", 0))


func add_currency(amount: int) -> void:
	data["currency"] = int(data.get("currency", 0)) + amount
	write_save()


func _unlock_list_for(category: String) -> Array:
	var key: String = category.strip_edges().to_lower()
	if key in ["tools", "tool", "unlocked_tools"]:
		return data["unlocked_tools"] as Array
	if key in ["perks", "perk", "guild_perks", "unlocked_perks"]:
		return data["unlocked_perks"] as Array
	if key in ["cosmetics", "cosmetic", "unlocked_cosmetics"]:
		return data["unlocked_cosmetics"] as Array
	return []


func is_unlocked(category: String, item_id: String) -> bool:
	var key: String = category.strip_edges().to_lower()
	if key in ["tools", "tool", "unlocked_tools"]:
		return (data["unlocked_tools"] as Array).has(item_id)
	if key in ["perks", "perk", "guild_perks", "unlocked_perks"]:
		return (data["unlocked_perks"] as Array).has(item_id)
	if key in ["cosmetics", "cosmetic", "unlocked_cosmetics"]:
		return (data["unlocked_cosmetics"] as Array).has(item_id)
	return false


func purchase_item(category: String, item_id: String, cost: int) -> bool:
	var clean_id: String = item_id.strip_edges()
	if clean_id == "":
		return false
	if is_unlocked(category, clean_id):
		return false
	if int(data.get("currency", 0)) < cost:
		return false
	data["currency"] = int(data.get("currency", 0)) - cost
	var lst: Array = _unlock_list_for(category)
	if lst.is_empty():
		return false
	lst.append(clean_id)
	write_save()
	return true


func get_level_progress() -> Dictionary:
	var level: int = maxi(1, int(data.get("level", 1)))
	var xp: int = maxi(0, int(data.get("xp", 0)))
	var needed: int = XP_PER_LEVEL
	var in_level: int = xp % needed
	return {"level": level, "xp_in_level": in_level, "xp_needed": needed}
