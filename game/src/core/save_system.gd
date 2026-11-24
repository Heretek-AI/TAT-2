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

## Settings schema (v2) and the one-time FOV migration. Saves written before
## the authored lens existed stored fov=75.0 (the old flat default), which
## overrode the authored 54.54 vertical / 85 horizontal at 16:9. v2 records
## `fov_migrated` so that exact legacy default is rewritten once, while an
## explicit non-75 value (or a deliberate 75 chosen after migration) stays.
const SETTINGS_SCHEMA_VERSION := 2
const LEGACY_FOV_DEFAULT := 75.0
const AUTHORED_FOV_DEG := 54.54

## Populated from _defaults() in _ready() so the schema has one source of truth.
var data: Dictionary = {}


func _ready() -> void:
	data = _defaults()
	load_save()
	apply_saved_settings()


func get_settings() -> Dictionary:
	if not data.has("settings") or not (data["settings"] is Dictionary):
		data["settings"] = {}
	return data["settings"] as Dictionary


func apply_saved_settings() -> void:
	var s: Dictionary = get_settings()
	var vol: float = clampf(float(s.get("master_volume", 0.8)), 0.0, 1.0)
	var music_vol: float = clampf(float(s.get("music_volume", 0.8)), 0.0, 1.0)
	var sfx_vol: float = clampf(float(s.get("sfx_volume", 0.8)), 0.0, 1.0)
	var ambience_vol: float = clampf(float(s.get("ambience_volume", sfx_vol)), 0.0, 1.0)
	var ui_vol: float = clampf(float(s.get("ui_volume", sfx_vol)), 0.0, 1.0)
	var dialogue_vol: float = clampf(float(s.get("dialogue_volume", sfx_vol)), 0.0, 1.0)
	# D8: address the Master bus by name, not index 0 — bus layout is data,
	# not law (AudioManager._ensure_buses appends in fixed order today, but
	# a user-added bus would shift index 0).
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(vol, 0.001)))
	elif AudioServer.get_bus_count() > 0:
		push_warning("[save_system] Master bus missing; leaving bus levels untouched")
	# Route the full bus architecture (PG-6): AudioManager owns bus creation
	# and per-bus volumes; direct AudioServer writes here keep volumes applied
	# even if the AudioManager autoload is unavailable in a minimal scene.
	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("apply_volumes"):
		am.call("apply_volumes", vol, music_vol, sfx_vol, ambience_vol, ui_vol, dialogue_vol)
	else:
		_apply_bus_direct("Music", music_vol)
		_apply_bus_direct("SFX", sfx_vol)
		_apply_bus_direct("Ambience", ambience_vol)
		_apply_bus_direct("UI", ui_vol)
		_apply_bus_direct("Dialogue", dialogue_vol)
	if DisplayServer.get_name() != "headless":
		var fullscreen: bool = bool(s.get("fullscreen", false))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		var vsync_on: bool = bool(s.get("vsync", true))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED)
		var vp: Viewport = get_viewport()
		if vp != null:
			vp.scaling_3d_scale = clampf(float(s.get("render_scale", 1.0)), 0.6, 1.0)


func _apply_bus_direct(bus_name: String, bus_vol: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(bus_vol, 0.001)))
	AudioServer.set_bus_mute(idx, bus_vol <= 0.001)


func _default_loadout() -> Dictionary:
	return {
		"head": "bowler_hat",
		"body": "",
		"calling_card": "",
		"tools": ["blackjack", "smoke_bomb", "zipwire", "slither_sap"],
		"perks": [],
		"active_tool": 0,
		"active_tool_id": "zipwire",
	}


## Canonical schema. `equipped_loadout` is keyed by thief id so Spider and
## Chameleon keep independent cosmetics/tools (the old flat "loadout" key and
## the array form are migrated in _ensure_defaults).
func _defaults() -> Dictionary:
	return {
		"xp": 0,
		"level": 1,
		"completed_contracts": {},
		"unlocked_tools": ["blackjack", "slither_sap", "smoke_bomb", "pickpocket_fairy", "zipwire"],
		"unlocked_perks": ["novice_difficulty", "guildhall", "old_manor", "spider"],
		"unlocked_cosmetics": ["bowler_hat"],
		"currency": 0,
		"equipped_loadout": {"spider": _default_loadout(), "chameleon": _default_loadout()},
		"active_decoration": "faberge_egg",
		"settings_schema": SETTINGS_SCHEMA_VERSION,
		"settings": {
			"mouse_sensitivity": 0.0025,
			"invert_y": false,
			"sprint_toggle": false,
			"reduced_camera_bounce": false,
			"fov": AUTHORED_FOV_DEG,
			"fov_migrated": false,
			"vsync": true,
			"master_volume": 0.8,
			"music_volume": 0.8,
			"sfx_volume": 0.8,
			"ambience_volume": 0.8,
			"ui_volume": 0.8,
			"dialogue_volume": 0.8,
			"fullscreen": false,
			"window_mode": "windowed_fullscreen",
			"gamepad_sensitivity": 0.0025,
			"gamepad_invert_y": false,
			"render_scale": 1.0,
			"touch_sensitivity": 2.5,
			"mobile_quality": "balanced",
		},
	}


## Loadout accessors used by the wardrobe and gameplay identity code.
func get_loadout(thief_id: String) -> Dictionary:
	var eq: Variant = data.get("equipped_loadout", {})
	if eq is Dictionary and (eq as Dictionary).get(thief_id) is Dictionary:
		var out: Dictionary = _default_loadout()
		out.merge((eq as Dictionary)[thief_id] as Dictionary, true)
		return out
	return _default_loadout()


func set_loadout(thief_id: String, loadout: Dictionary) -> void:
	if not (data.get("equipped_loadout") is Dictionary):
		data["equipped_loadout"] = {}
	var eq: Dictionary = data["equipped_loadout"] as Dictionary
	var entry: Dictionary = _default_loadout()
	entry.merge(loadout, true)
	eq[thief_id] = entry
	data["equipped_loadout"] = eq


## Recursive type-checked merge. Only known keys with compatible types are
## accepted; a wrong-typed value (e.g. "currency": "bad") leaves the default
## intact instead of crashing the first caller that casts it.
func _merge_validated(incoming: Dictionary) -> void:
	_merge_into(incoming, data, _defaults())


## One merge level. `schema` is the matching default dictionary for `target`.
## A dictionary whose schema default is an empty Dictionary is free-form
## (today only completed_contracts): its unknown keys are accepted whether the
## live target is empty or already populated, so a second load_save() keeps
## accepting new completion rows. Unknown keys anywhere else (root, settings,
## loadout) stay ignored. Deriving this from the live target's emptiness made
## a populated map reject new rows; aliasing an empty target to the root made
## every completion row look like an unknown root key.
func _merge_into(incoming: Dictionary, target: Dictionary, schema: Dictionary) -> void:
	for key_v: Variant in incoming.keys():
		var key: String = str(key_v)
		if not target.has(key):
			if schema.is_empty():
				target[key] = _duplicate_freeform(incoming[key_v])
			continue
		var base: Variant = target[key]
		var inc: Variant = incoming[key_v]
		if base is Dictionary and inc is Dictionary:
			var child_schema: Dictionary = {}
			var schema_v: Variant = schema.get(key, null)
			if schema_v is Dictionary:
				child_schema = schema_v as Dictionary
			_merge_into(inc as Dictionary, base as Dictionary, child_schema)
		elif key == "equipped_loadout" and (inc is Array or inc is Dictionary):
			target[key] = inc  # normalized by _ensure_defaults
		elif base is Array:
			if inc is Array:
				target[key] = (inc as Array).duplicate(true)
		elif typeof(base) == typeof(inc) \
				or (base is int and inc is float) \
				or (base is float and inc is int):
			target[key] = inc


## Free-form values have no schema to validate against, but they are still
## duplicated so a parsed JSON tree never aliases the live save map.
func _duplicate_freeform(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


func _ensure_defaults() -> void:
	var defaults: Dictionary = _defaults()
	# Backfill the PG-6 bus volumes on old saves that predate them.
	if data.has("settings") and data["settings"] is Dictionary:
		var s: Dictionary = data["settings"] as Dictionary
		var fallback_vol: float = clampf(float(s.get("sfx_volume", 0.8)), 0.0, 1.0)
		for bus_key: String in ["ambience_volume", "ui_volume", "dialogue_volume"]:
			if not s.has(bus_key):
				s[bus_key] = fallback_vol
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
	# Normalize every legacy loadout shape into the per-thief canonical dict.
	var eq_v: Variant = data.get("equipped_loadout", null)
	if eq_v is Array:
		var legacy_tools: Array = eq_v as Array
		var lo: Dictionary = _default_loadout()
		lo["tools"] = legacy_tools.duplicate()
		data["equipped_loadout"] = {"spider": lo, "chameleon": _default_loadout()}
	elif eq_v is Dictionary and (eq_v as Dictionary).has("thief_id"):
		var flat: Dictionary = eq_v as Dictionary
		var cur: Dictionary = _default_loadout()
		for field: String in ["head", "body", "calling_card", "active_tool_id"]:
			if flat.has(field):
				cur[field] = str(flat[field])
		cur["active_tool"] = int(flat.get("active_tool", 0))
		data["equipped_loadout"] = {"spider": cur, "chameleon": _default_loadout()}
	var legacy_flat: Variant = data.get("loadout", null)
	if legacy_flat is Dictionary:
		var tid: String = str((legacy_flat as Dictionary).get("thief_id", "spider"))
		set_loadout(tid, legacy_flat as Dictionary)
		data.erase("loadout")
	var eq: Dictionary = data["equipped_loadout"] as Dictionary
	for thief: String in ["spider", "chameleon"]:
		if not (eq.get(thief) is Dictionary):
			eq[thief] = _default_loadout()


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


## One-time FOV migration for settings schema v2 (see the constants above).
## Runs after the defaults merge so a legacy save's `settings.fov` survives as
## data (not the new default). Only the exact legacy default 75.0 is rewritten;
## an explicit 65 stays 65. Returns true when the save should be persisted.
func _migrate_settings_schema() -> bool:
	var s: Dictionary = get_settings()
	var schema: int = int(data.get("settings_schema", 1))
	var migrated: bool = bool(s.get("fov_migrated", false))
	if schema >= SETTINGS_SCHEMA_VERSION and migrated:
		return false
	if not migrated and s.has("fov") and is_equal_approx(float(s.get("fov", 0.0)), LEGACY_FOV_DEFAULT):
		s["fov"] = AUTHORED_FOV_DEG
	s["fov_migrated"] = true
	data["settings_schema"] = SETTINGS_SCHEMA_VERSION
	return true


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
		_merge_validated(parsed as Dictionary)
	_ensure_defaults()
	_sync_level_from_xp()
	# Persist the one-time settings migration (legacy fov 75 -> authored 54.54)
	# so the next load sees fov_migrated and never re-runs it.
	if _migrate_settings_schema():
		write_save()


func write_save() -> void:
	var f: FileAccess = FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		# C2 (partial): the tmp-open failure was silent while callers report
		# success. Warn here; full type-checked merge validation stays
		# HARD_LIMIT (needs a save-migration design).
		push_warning("[save_system] cannot open tmp save for write: ", TMP_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_warning("[save_system] cannot open user://; save not persisted")
		return
	# D8: check the atomic-rename result; a failed rename used to be silent
	# while callers report success unconditionally.
	var rename_err: Error = dir.rename("tat2_save.json.tmp", "tat2_save.json")
	if rename_err != OK:
		push_warning("[save_system] atomic save rename failed: ", error_string(rename_err))


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
	# C1: validate the category BEFORE deducting — the old order kept the
	# deduction in memory for unknown categories (no write_save, but the
	# autoload balance was already reduced until reload).
	var lst: Array = _unlock_list_for(category)
	if lst.is_empty():
		return false
	var clean_id: String = item_id.strip_edges()
	if clean_id == "":
		return false
	if is_unlocked(category, clean_id):
		return false
	if int(data.get("currency", 0)) < cost:
		return false
	data["currency"] = int(data.get("currency", 0)) - cost
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
