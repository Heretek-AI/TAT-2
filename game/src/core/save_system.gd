extends Node
## Atomic JSON save system (mirrors TATAtomicSave): XP, level, completed contracts, settings.
## Workstream 2: progression state (currency, unlocks, loadouts, den decoration).

const SAVE_PATH := "user://tat2_save.json"
const TMP_PATH := "user://tat2_save.json.tmp"

const XP_CURVE_TABLE := "CT_XPToLevel"
const XP_CURVE_ROW := "XPToLevel"
# Fallback only if the authored curve is unreadable (its level 1-4 value).
const XP_PER_LEVEL_FALLBACK := 500
# Defensive bounds for save-sourced values so a corrupt or hand-edited save
# cannot drive the per-level loops for an absurd number of iterations.
# These are not gameplay caps.
const MAX_SAVE_LEVEL := 200
const MAX_SAVE_XP := 1_000_000

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


## Stored levels are legacy: old saves used `xp / 500 + 1`, which is higher
## than the authored curve allows once XP passes 2500. The runtime level is
## therefore always re-derived from XP; the stored value is never trusted.
func _sync_level_from_xp() -> void:
	var raw: Variant = data.get("xp", 0)
	var xp: int = clampi(int(raw), 0, MAX_SAVE_XP)
	# Only rewrite XP when clamping actually changes it, so valid saves keep
	# their stored numeric representation; the level value is always recomputed.
	if xp != int(raw) or not (raw is int or raw is float):
		data["xp"] = xp
	data["level"] = level_for_xp(xp)


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_ensure_defaults()
		_sync_level_from_xp()
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		_ensure_defaults()
		_sync_level_from_xp()
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var pd: Dictionary = parsed as Dictionary
		data.merge(pd, true)
	_ensure_defaults()
	_sync_level_from_xp()


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
	data["xp"] = clampi(int(data["xp"]) + maxi(100, score / 2), 0, MAX_SAVE_XP)
	_sync_level_from_xp()
	write_save()


## XP required to advance out of `level`, read from the authored
## CT_XPToLevel.XPToLevel curve. That curve is RCIM_Linear with constant
## extrapolation, so this evaluates linearly (integer levels land exactly on
## the authored keys: 1-4 = 500, 5-9 = 1000, 10-24 = 2500).
func xp_threshold_for_level(level: int) -> int:
	var lvl: int = maxi(1, level)
	var value: float = GameData.eval_curve(XP_CURVE_TABLE, XP_CURVE_ROW, float(lvl), float(XP_PER_LEVEL_FALLBACK))
	if value <= 0.0:
		return XP_PER_LEVEL_FALLBACK
	return int(roundf(value))


## Cumulative XP needed to reach `level` (level 1 starts at 0 XP).
func xp_total_for_level(level: int) -> int:
	var total: int = 0
	var lvl: int = 1
	# Defensive clamp for malformed saves, not a gameplay cap.
	var target: int = clampi(level, 1, MAX_SAVE_LEVEL)
	while lvl < target:
		total += xp_threshold_for_level(lvl)
		lvl += 1
	return total


## Level implied by a cumulative XP total under the authored per-level curve.
func level_for_xp(xp: int) -> int:
	# Defensive clamps for malformed saves, not gameplay caps.
	var remaining: int = clampi(xp, 0, MAX_SAVE_XP)
	var level: int = 1
	var need: int = xp_threshold_for_level(level)
	while remaining >= need and level < MAX_SAVE_LEVEL:
		remaining -= need
		level += 1
		need = xp_threshold_for_level(level)
	return level


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
	var xp: int = clampi(int(data.get("xp", 0)), 0, MAX_SAVE_XP)
	# The stored level is legacy and may be inflated; derive it from XP.
	var level: int = level_for_xp(xp)
	var needed: int = xp_threshold_for_level(level)
	var spent: int = xp_total_for_level(level)
	var in_level: int = clampi(xp - spent, 0, maxi(0, needed - 1))
	return {"level": level, "xp_in_level": in_level, "xp_needed": needed}
