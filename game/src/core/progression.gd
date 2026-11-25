extends RefCounted
## Authored progression reader (W9-P1) for
## game/data/generated/project_settings.json, emitted from
## extracted/raw/TAT/Config/DefaultGame.ini by tools/parse_project_ini.py.
##
## Why this file exists: the shipped progression numbers (MaximumLevel 25,
## LevelUpXP 500, the per-category XP weights, the 1200/600/300 endgame ladder,
## the 5,000 FTUE bankroll, the authored map -> mission order and the scoring
## bonuses) were extracted but had no runtime consumer, so the port kept its
## own guesses (level cap 200, an XP award of max(100, score/2), a flat endgame
## window). Every getter below reads the JSON once, caches it, and falls back to
## the authored default with a *counted* diagnostic when the file or a key is
## missing, so a broken generated file degrades to a named value instead of a
## silent zero.
##
## Use it statically; do not instantiate:
##   const Progression := preload("res://src/core/progression.gd")
##   var cap: int = Progression.maximum_level()

const PATH := "res://data/generated/project_settings.json"
## Producer schema stamp (tools/parse_project_ini.py). A different stamp means
## the key paths below are not guaranteed, so the file is treated as unreadable.
const EXPECTED_SCHEMA := "tat2.project_settings/1"
## Diagnostics are capped so a broken file cannot grow the array unbounded.
const MAX_DIAGNOSTICS := 32

## Documented fallbacks. These are the *authored* values (the port's pre-W9
## behaviour was the defect), used only when the generated file or one key is
## unreadable; every use is recorded by load_diagnostics()/fallback_count().
const FALLBACK_MAXIMUM_LEVEL := 25
const FALLBACK_LEVEL_UP_XP := 500
const FALLBACK_CONTRACTS_XP := 20.0
const FALLBACK_MISSION_XP := 20.0
const FALLBACK_WIN_XP := 80.0
const FALLBACK_OPEN_QUEUE_XP := 5.0
const FALLBACK_MINOR_LOOT_XP := 2.0
const FALLBACK_MAJOR_LOOT_XP := 6.0
const FALLBACK_MAXIMUM_TIME_IN_GAME_XP := 25.0
const FALLBACK_XP_PER_MINUTE := 0.6
const FALLBACK_COOP_XP_MULTIPLIER := 1.5
const FALLBACK_LOOTING_PLAYER_XP_MULTIPLIER := 1.1
const FALLBACK_FTUE_MIN_THIEVES_DEN_MONEY := 5000
const FALLBACK_ENDGAME_DURATIONS: Array[float] = [1200.0, 600.0, 300.0]
const FALLBACK_CONTRACT_COMPLETE_BONUS := 100.0
const FALLBACK_MISSION_COMPLETE_BONUS := 300.0
const FALLBACK_STASHED_LOOT_VALUE_MULTIPLIER_BONUS := 0.1
const FALLBACK_CARRIED_LOOT_VALUE_MULTIPLIER_BONUS := 0.1

## PORT DECISION (difficulty mapping): GameState.Difficulty is the 1-based
## port enum (NOVICE=1, THIEF=2, MASTER_THIEF=3) while the authored multipliers
## are keyed Easy/Normal/Hard (DefaultGame.ini EasyDifficultyXPMultiplier ...).
## The shipped capture carries no enum row, so the ordinal mapping below is a
## port decision, stated here and never inferred at runtime.
const DIFFICULTY_TO_AUTHORED_LABEL: Dictionary = {
	1: "Easy",
	2: "Normal",
	3: "Hard",
}

static var _doc: Dictionary = {}
static var _load_attempted: bool = false
static var _loaded: bool = false
static var _diagnostics: Array[String] = []
static var _fallback_count: int = 0


# --- load / diagnostics ----------------------------------------------------

static func _ensure() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	_doc = {}
	_loaded = false
	if not FileAccess.file_exists(PATH):
		_note("project_settings.json missing; every getter uses its documented fallback")
		return
	var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		_note("project_settings.json unreadable (error %d); fallbacks live" % int(FileAccess.get_open_error()))
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_note("project_settings.json is not a JSON object; fallbacks live")
		return
	var doc: Dictionary = parsed as Dictionary
	if str(doc.get("schema", "")) != EXPECTED_SCHEMA:
		_note("project_settings.json schema '%s' != '%s'; fallbacks live" % [str(doc.get("schema", "")), EXPECTED_SCHEMA])
		return
	_doc = doc
	_loaded = true


## Record one fallback exactly once per reason (the getters are hot paths and
## several call the same missing key). Also warns once so a boot log names it.
static func _note(reason: String) -> void:
	_fallback_count += 1
	if _diagnostics.has(reason):
		return
	if _diagnostics.size() < MAX_DIAGNOSTICS:
		_diagnostics.append(reason)
	push_warning("[progression] " + reason)


## True when project_settings.json parsed and carried the expected schema.
static func loaded() -> bool:
	_ensure()
	return _loaded


## Generated file this reader owns ("" when it could not be used).
static func source() -> String:
	return PATH if loaded() else ""


## Extracted UE config the generated file came from ($.source), for reports.
static func provenance() -> String:
	_ensure()
	return str(_doc.get("source", "")) if _loaded else ""


## Every fallback reason recorded so far (named once, capped).
static func load_diagnostics() -> Array[String]:
	_ensure()
	return _diagnostics.duplicate()


## How many fallback reads happened (exact, beyond the diagnostic cap).
static func fallback_count() -> int:
	_ensure()
	return _fallback_count


## Parsed document (deep copy + the keys are validated by the callers).
## Tests use this to prove a value came from the file, not from a literal.
static func raw() -> Dictionary:
	_ensure()
	return _doc.duplicate(true)


static func _section(name: String) -> Dictionary:
	_ensure()
	var s: Variant = _doc.get(name, null)
	return s as Dictionary if s is Dictionary else {}


static func _number(section: Dictionary, key: String, fallback: float, qualified: String) -> float:
	var v: Variant = section.get(key, null)
	if (v is float or v is int) and is_finite(float(v)):
		return float(v)
	_note("%s missing or not a number; using the documented fallback %s" % [qualified, str(fallback)])
	return fallback


static func _int(section: Dictionary, key: String, fallback: int, qualified: String) -> int:
	return int(roundf(_number(section, key, float(fallback), qualified)))


static func _string_list(section: Dictionary, key: String, qualified: String) -> Array[String]:
	var out: Array[String] = []
	var v: Variant = section.get(key, null)
	if v is Array:
		for item: Variant in (v as Array):
			if item is String and str(item).strip_edges() != "":
				out.append(str(item))
	if out.is_empty():
		_note("%s missing or empty; returning an empty list" % qualified)
	return out


# --- progression block -----------------------------------------------------

## Authored level cap (progression.maximum_level = 25, DefaultGame.ini
## MaximumLevel). SaveSystem.level_for_xp() caps here and keeps the XP.
static func maximum_level() -> int:
	return maxi(1, _int(_section("progression"), "maximum_level", FALLBACK_MAXIMUM_LEVEL, "progression.maximum_level"))


## XP the curve charges to leave level 1 (progression.level_up_xp = 500). The
## per-level curve itself is CT_XPToLevel, read by SaveSystem.
static func level_up_xp() -> int:
	return maxi(1, _int(_section("progression"), "level_up_xp", FALLBACK_LEVEL_UP_XP, "progression.level_up_xp"))


## Authored per-category XP weights, exposed as a value of the category. The
## kinds are the port's names for the authored keys:
##   "contracts"   -> progression.contracts_xp        (20)
##   "mission"     -> progression.mission_xp          (20)
##   "win"         -> progression.win_xp              (80)
##   "open_queue"  -> progression.open_queue_xp       (5)
##   "minor_loot"  -> progression.minor_loot_xp       (2)   * ctx.count
##   "major_loot"  -> progression.major_loot_xp       (6)   * ctx.count
##   "time"        -> progression.xp_per_minute       (0.6) * ctx.minutes,
##                    clamped to progression.maximum_time_in_game_xp (25)
##   "ftue_level_up" -> the three authored FTUE categories (see below)
## Returns 0 for an unknown kind (recorded as a diagnostic).
static func xp_award(kind: String, ctx: Dictionary = {}) -> int:
	var prog: Dictionary = _section("progression")
	match kind:
		"contracts":
			return _int(prog, "contracts_xp", int(FALLBACK_CONTRACTS_XP), "progression.contracts_xp")
		"mission":
			return _int(prog, "mission_xp", int(FALLBACK_MISSION_XP), "progression.mission_xp")
		"win":
			return _int(prog, "win_xp", int(FALLBACK_WIN_XP), "progression.win_xp")
		"open_queue":
			return _int(prog, "open_queue_xp", int(FALLBACK_OPEN_QUEUE_XP), "progression.open_queue_xp")
		"minor_loot":
			return _int(prog, "minor_loot_xp", int(FALLBACK_MINOR_LOOT_XP), "progression.minor_loot_xp") * maxi(int(ctx.get("count", 1)), 0)
		"major_loot":
			return _int(prog, "major_loot_xp", int(FALLBACK_MAJOR_LOOT_XP), "progression.major_loot_xp") * maxi(int(ctx.get("count", 1)), 0)
		"time":
			var per_min: float = _number(prog, "xp_per_minute", FALLBACK_XP_PER_MINUTE, "progression.xp_per_minute")
			var cap: float = _number(prog, "maximum_time_in_game_xp", FALLBACK_MAXIMUM_TIME_IN_GAME_XP, "progression.maximum_time_in_game_xp")
			var minutes: float = maxf(float(ctx.get("minutes", 0.0)), 0.0)
			return int(roundf(clampf(per_min * minutes, 0.0, maxf(cap, 0.0))))
		"ftue_level_up":
			return ftue_level_up_xp()
	_note("xp_award('%s') is not an authored category; 0" % kind)
	return 0


## Authored difficulty multiplier (progression.difficulty_xp_multipliers:
## Easy 1.0 / Normal 2.0 / Hard 3.0) for the port's 1-based Difficulty enum.
## The enum -> authored label mapping is the port decision documented at
## DIFFICULTY_TO_AUTHORED_LABEL; an out-of-range difficulty is treated as
## Novice and named in the diagnostics.
static func difficulty_xp_multiplier(difficulty: int) -> float:
	var idx: int = difficulty
	if not DIFFICULTY_TO_AUTHORED_LABEL.has(idx):
		_note("difficulty %d is outside the authored 1..3 enum; using Easy" % idx)
		idx = 1
	var label: String = str(DIFFICULTY_TO_AUTHORED_LABEL[idx])
	var table: Dictionary = {}
	var table_v: Variant = _section("progression").get("difficulty_xp_multipliers", null)
	if table_v is Dictionary:
		table = table_v as Dictionary
	var fallback: float = 1.0
	if idx == 2:
		fallback = 2.0
	elif idx == 3:
		fallback = 3.0
	return maxf(_number(table, label, fallback, "progression.difficulty_xp_multipliers." + label), 0.0)


static func coop_xp_multiplier() -> float:
	return maxf(_number(_section("progression"), "coop_xp_multiplier", FALLBACK_COOP_XP_MULTIPLIER, "progression.coop_xp_multiplier"), 0.0)


static func looting_player_xp_multiplier() -> float:
	return maxf(_number(_section("progression"), "looting_player_xp_multiplier", FALLBACK_LOOTING_PLAYER_XP_MULTIPLIER, "progression.looting_player_xp_multiplier"), 0.0)


## The three authored FTUE level-up categories (DT_PlayerExperience tags:
## XP.ReachExitInTime / XP.CompleteMission / XP.CompleteContracts).
static func ftue_level_up_xp_categories() -> Array[String]:
	return _string_list(_section("progression"), "ftue_level_up_xp_categories", "progression.ftue_level_up_xp_categories")


## True when the authored FTUE credit is additive to the regular award
## (progression.ftue_level_up_xp_is_on_top_of_regular_xp = true).
static func ftue_level_up_xp_is_on_top_of_regular_xp() -> bool:
	var v: Variant = _section("progression").get("ftue_level_up_xp_is_on_top_of_regular_xp", null)
	if v is bool:
		return bool(v)
	_note("progression.ftue_level_up_xp_is_on_top_of_regular_xp missing or not a bool; using true")
	return true


## FTUE level-up credit: one credit per authored FTUE category.
## PORT DECISION: DT_PlayerExperience authors category *tags only* (no
## per-tag amounts), so the credit per tag is the authored contracts category
## weight (progression.contracts_xp = 20) -- not a derived minimum (open_queue_xp
## is 5 and minor_loot_xp is 2 are smaller, but neither is a level-up category).
## The tag list is authored and read at runtime; three tags award 60 XP once.
static func ftue_level_up_xp() -> int:
	var per_tag: int = xp_award("contracts")
	return per_tag * ftue_level_up_xp_categories().size()


## FTUE minimum Thieves' Den bankroll (project.ftue_min_thieves_den_money =
## 5000, DefaultGame.ini FTUEMinThievesDenMoney).
static func ftue_min_thieves_den_money() -> int:
	return maxi(0, _int(_section("project"), "ftue_min_thieves_den_money", FALLBACK_FTUE_MIN_THIEVES_DEN_MONEY, "project.ftue_min_thieves_den_money"))


# --- endgame ladder --------------------------------------------------------

## Authored endgame (magic door) window in seconds by difficulty index:
## project.endgame_durations_by_difficulty = [1200, 600, 300].
## The producer labels the index -> difficulty map "unproven: index order
## only" (project.difficulty_index_source), so index 0/1/2 is treated as
## Novice/Thief/Master by ordinal only — carried here, not proven.
static func endgame_seconds_for_difficulty(index: int) -> float:
	_ensure()
	var arr_v: Variant = _section("project").get("endgame_durations_by_difficulty", null)
	if arr_v is Array and not (arr_v as Array).is_empty():
		var arr: Array = arr_v as Array
		var i: int = clampi(index, 0, arr.size() - 1)
		var v: Variant = arr[i]
		if (v is float or v is int) and is_finite(float(v)):
			return maxf(float(v), 0.0)
	_note("project.endgame_durations_by_difficulty missing; using the documented fallback")
	var fb: Array[float] = FALLBACK_ENDGAME_DURATIONS
	return float(fb[clampi(index, 0, fb.size() - 1)])


## True when the endgame ladder came from the file. GameData keeps its authored
## QG EndgameDuration when this is false, so a broken file cannot invent a
## window (fail closed).
## Number of authored rungs in EndgameDurationsByDifficulty (3 today). Callers
## clamp a difficulty index against this instead of a literal.
static func ladder_size() -> int:
	_ensure()
	var sec: Dictionary = _section("project")
	var arr: Variant = sec.get("endgame_durations_by_difficulty", null)
	if arr is Array and not (arr as Array).is_empty():
		return (arr as Array).size()
	return FALLBACK_ENDGAME_DURATIONS.size()


static func endgame_ladder_authored() -> bool:
	_ensure()
	if not _loaded:
		return false
	var arr_v: Variant = _section("project").get("endgame_durations_by_difficulty", null)
	if not (arr_v is Array) or (arr_v as Array).is_empty():
		return false
	var v: Variant = (arr_v as Array)[0]
	return v is float or v is int


# --- scoring bonuses (data only; the payout composition is P2's) -----------

static func contract_complete_bonus() -> int:
	return _int(_section("scoring"), "contract_complete_bonus", int(FALLBACK_CONTRACT_COMPLETE_BONUS), "scoring.contract_complete_bonus")


static func mission_complete_bonus() -> int:
	return _int(_section("scoring"), "mission_complete_bonus", int(FALLBACK_MISSION_COMPLETE_BONUS), "scoring.mission_complete_bonus")


static func stashed_loot_value_multiplier_bonus() -> float:
	return _number(_section("scoring"), "stashed_loot_value_multiplier_bonus", FALLBACK_STASHED_LOOT_VALUE_MULTIPLIER_BONUS, "scoring.stashed_loot_value_multiplier_bonus")


static func carried_loot_value_multiplier_bonus() -> float:
	return _number(_section("scoring"), "carried_loot_value_multiplier_bonus", FALLBACK_CARRIED_LOOT_VALUE_MULTIPLIER_BONUS, "scoring.carried_loot_value_multiplier_bonus")


# --- authored map -> mission order ----------------------------------------

## One normalised map key: case, spaces, underscores and a "Map." tag prefix
## are ignored so the runtime id ("old_manor") matches the authored display
## name ("Old Manor") and tag ("Map.OldManor").
static func _map_key(name: String) -> String:
	var key: String = name.strip_edges().to_lower().replace(" ", "").replace("_", "")
	if key.begins_with("map."):
		key = key.substr(4)
	return key


## Authored map records in file order:
## [{map_name, tag, ue_map, missions: Array[String]}, ...].
## project.maps is the only authored map -> mission order; it is exposed here
## because the shipped OldManor list (Set, Vault, LootTheRoom) differs from the
## DT_Missions row order (Vault, Set, LootTheRoom) and must stay visible.
static func maps() -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	var rows_v: Variant = _section("project").get("maps", null)
	if not (rows_v is Array):
		_note("project.maps missing; no authored map order")
		return out
	for row_v: Variant in (rows_v as Array):
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		var missions: Array[String] = []
		var m_v: Variant = row.get("missions", [])
		if m_v is Array:
			for mid_v: Variant in (m_v as Array):
				if mid_v is String and str(mid_v).strip_edges() != "":
					missions.append(str(mid_v))
		out.append({
			"map_name": str(row.get("map_name", "")),
			"tag": str(row.get("tag", "")),
			"ue_map": str(row.get("map", "")),
			"missions": missions,
		})
	return out


## Authored mission ids for a map, in file order. `map_name` accepts the
## authored display name ("Old Manor"), the runtime id ("old_manor") or the tag
## ("Map.OldManor"). Unknown names return [] and are recorded as a diagnostic.
static func missions_for_map(map_name: String) -> Array[String]:
	var want: String = _map_key(map_name)
	for row: Dictionary in maps():
		var name_key: String = _map_key(str(row.get("map_name", "")))
		var tag_key: String = _map_key(str(row.get("tag", "")))
		if want != "" and (want == name_key or want == tag_key):
			var out: Array[String] = []
			var list_v: Variant = row.get("missions", [])
			if list_v is Array:
				for mid_v: Variant in (list_v as Array):
					out.append(str(mid_v))
			return out
	_note("project.maps has no row for '%s'" % map_name)
	return []


# --- unlock content lists --------------------------------------------------

## The 8 authored initial unlock tags (project.initial_unlocked_content).
## Exposed for tests/UI copy only: runtime adoption is DEFERRED (SaveSystem
## still ships its curated starter lists; see the W9-P1 report).
static func initial_unlocked_content() -> Array[String]:
	return _string_list(_section("project"), "initial_unlocked_content", "project.initial_unlocked_content")


## The 3 authored post-FTUE unlock tags (project.post_ftue_unlocked_content).
## Same DEFERRED note as initial_unlocked_content().
static func post_ftue_unlocked_content() -> Array[String]:
	return _string_list(_section("project"), "post_ftue_unlocked_content", "project.post_ftue_unlocked_content")
