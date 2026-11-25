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
## Desktop quality ladder consumed by WeatherProfile.quality_level(). The value
## is perf policy, not extracted data; "high" is the shipped desktop behaviour.
const GRAPHICS_QUALITY_KEYS: Array[String] = ["low", "medium", "high"]
const GRAPHICS_QUALITY_DEFAULT := "high"
## Default handle: blank means "no explicit handle", so the UI shows the
## authored thief title (GameState.player_display_name). Persisted at the save
## root; GameState exposes the live copy the HUD/ledger read.
const DEFAULT_PLAYER_NAME := ""
const MAX_PLAYER_NAME_CHARS := 48
## The capture machine's Steam persona, never shipped game copy. Saves written
## before the identity correction persisted it as the default, so one boot
## rewrites exactly that value to blank (guarded by player_name_migrated).
const CAPTURE_PERSONA_NAME := "Johnny Cipher"

## Unlock-catalog migration (W6U2). The Black Market is data-driven from
## game/data/generated/gameplay/unlocks.json (see src/ui/unlock_catalog.gd),
## whose stable save ids are snake_case for tools/perks and the authored outfit
## tag for cosmetics. Saves written by the old hard-coded ledger stored short
## UI ids; they are rewritten exactly once and unknown ids are preserved.
const UNLOCK_IDS_SCHEMA_VERSION := 1
## Catalog save category -> persisted array. Keep this the only mapping: the
## catalog test validates every authored row against it.
const UNLOCK_CATEGORY_KEYS: Dictionary = {
	"tools": "unlocked_tools",
	"perks": "unlocked_perks",
	"cosmetics": "unlocked_cosmetics",
}
## Tool ids the gameplay layer uses that predate the catalog ids.
const LEGACY_TOOL_IDS: Dictionary = {
	"slithersap": "slither_sap",
	"fairy": "pickpocket_fairy",
}
## Old ledger/Wardrobe cosmetic ids -> authored outfit tags. A short id shared
## by both thieves (bowler_hat, top_hat, ...) maps to both authored rows: a
## migration must never take a cosmetic away, so the ambiguous id is granted on
## both sides instead of guessing which thief the player meant. Fresh saves own
## only the Spider starter set (KF08 shows the Chameleon rows locked).
const LEGACY_COSMETIC_TAGS: Dictionary = {
	"no_hat": ["Outfit.Spider.Head.NoCap"],
	"bob_hair": ["Outfit.Spider.Head.Hair.Bob"],
	"bob_hair_eyepatch": ["Outfit.Spider.Head.Hair.Bob.EyepatchA"],
	"parted_hair": ["Outfit.Chameleon.Head.HairB"],
	"cap": ["Outfit.Chameleon.Head.CapA"],
	"bowler_hat": ["Outfit.Spider.Head.BowlerA", "Outfit.Chameleon.Head.BowlerA"],
	"top_hat": ["Outfit.Spider.Head.TopHatA", "Outfit.Chameleon.Head.TopHatA"],
	"mustache": ["Outfit.Spider.Head.MustacheA", "Outfit.Chameleon.Head.MustacheA"],
	"full_beard": ["Outfit.Spider.Head.BeardA", "Outfit.Chameleon.Head.BeardA"],
	"glasses": ["Outfit.Spider.Head.GlassesA", "Outfit.Chameleon.Head.GlassesA"],
	"thief_mask": ["Outfit.Spider.Head.ThiefMaskA", "Outfit.Chameleon.Head.ThiefMaskA"],
	"monocle": ["Outfit.Spider.Head.MonocleA", "Outfit.Chameleon.Head.MonocleA"],
	"eyepatch": ["Outfit.Spider.Head.EyepatchA", "Outfit.Chameleon.Head.EyepatchA"],
	"tarantula": ["Outfit.Spider.Body.AltA"],
	"tarantula_patternb": ["Outfit.Spider.Body.AltA.PatternB"],
}
## Cosmetic rows the shipped profile already owned: the three Spider defaults
## plus the Bowler Hat worn in KF03 and checked in KF08.
const STARTER_COSMETICS: Array[String] = [
	"Outfit.Spider.Head.Default",
	"Outfit.Spider.Body.Default",
	"Outfit.Spider.CallingCard.Default",
	"Outfit.Spider.Head.BowlerA",
]
## Tools the shipped profile owns (KF08: Zipwire and Smoke Bomb checked). The
## other catalog tools are gate-locked; blackjack is a built-in, not a row.
const STARTER_TOOLS: Array[String] = ["zipwire", "smoke_bomb"]
const STARTER_PERKS: Array[String] = [
	"novice_difficulty", "guildhall", "old_manor", "spider",
]
## The Chameleon is the Contract 3 reward (Thief.Chameleon, £10,000). Any
## completed contract used to unlock it, which let contract 1 hand over a
## 10,000-unit disguise; the authored gate is contract order 3.
const CHAMELEON_CONTRACT_ORDER := 3

## Personal quest (Spider "The Theban Owl") save schema. The chain itself is
## authored in game/data/expansion/personal_spider.json; this module owns only
## the persisted per-thief record so it can normalize a hand-edited or corrupt
## save without loading the expansion data. Facts are stored as ids, never as
## journal records: the journal is rehydrated from GameData on deploy and
## contract clue facts never reach this record.
const PERSONAL_QUEST_SCHEMA_VERSION := 1
const PERSONAL_QUEST_KEY := "personal_quest"
const PERSONAL_QUEST_STAGES: Array[String] = [
	"", "intro", "letter", "electrotype", "located", "carrying", "delivered",
	"info", "complete",
]
const PERSONAL_QUEST_OWL_STATES: Array[String] = ["none", "held", "delivered"]
const PERSONAL_QUEST_THIEVES: Array[String] = ["spider", "chameleon"]
## The only fact ids the chain may persist. ObjectiveComplete_* rows carry no
## journal text, Reminder is only the dropped 03 electrotype and Renegade is
## the dropped 04 warning, so none of those are ever stored.
const PERSONAL_QUEST_FACT_INTRO := "DT_ClueFacts_Personal_Spider_01:Intro"
const PERSONAL_QUEST_FACT_LETTER := "DT_ClueFacts_Personal_Spider_01:FoundLetter"
const PERSONAL_QUEST_FACT_MALLICK := "DT_ClueFacts_Personal_Spider_01:MallickSlip"
const PERSONAL_QUEST_FACT_STATUE := "DT_ClueFacts_Personal_Spider_01:StatuePet"
const PERSONAL_QUEST_FACT_OWL_LOCATION := "DT_ClueFacts_Personal_Spider_02:OwlLocation"
const PERSONAL_QUEST_FACT_HANDED_OFF := "DT_ClueFacts_Personal_Spider_03:HandedOff"
const PERSONAL_QUEST_FACT_GOT_INFO := "DT_ClueFacts_Personal_Spider_04:GotInfo"
const PERSONAL_QUEST_PERSISTED_FACTS: Array[String] = [
	PERSONAL_QUEST_FACT_INTRO,
	PERSONAL_QUEST_FACT_LETTER,
	PERSONAL_QUEST_FACT_MALLICK,
	PERSONAL_QUEST_FACT_STATUE,
	PERSONAL_QUEST_FACT_OWL_LOCATION,
	PERSONAL_QUEST_FACT_HANDED_OFF,
	PERSONAL_QUEST_FACT_GOT_INFO,
]
## Fact id -> earliest stage it proves. Normalization raises a stage when the
## saved facts already prove a later beat (e.g. a crash between the fact grant
## and the stage write cannot strand a delivered Owl at "carrying").
const PERSONAL_QUEST_FACT_STAGES: Dictionary = {
	PERSONAL_QUEST_FACT_INTRO: "intro",
	PERSONAL_QUEST_FACT_LETTER: "letter",
	PERSONAL_QUEST_FACT_MALLICK: "electrotype",
	PERSONAL_QUEST_FACT_STATUE: "electrotype",
	PERSONAL_QUEST_FACT_OWL_LOCATION: "located",
	PERSONAL_QUEST_FACT_HANDED_OFF: "delivered",
	PERSONAL_QUEST_FACT_GOT_INFO: "info",
}

## Populated from _defaults() in _ready() so the schema has one source of truth.
var data: Dictionary = {}


func _ready() -> void:
	data = _defaults()
	load_save()
	apply_saved_settings()
	_sync_player_name()


## Push the validated saved handle into GameState (the HUD/ledger source).
func _sync_player_name() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("player_name", str(data.get("player_name", DEFAULT_PLAYER_NAME)))


## Persist a new handle. Blank is valid and means "show the authored thief
## title"; oversized input is truncated. This is the profile-name API (there
## is no Settings field; the UI reads GameState.player_display_name()).
func set_player_name(new_name: String) -> void:
	var clean: String = new_name.strip_edges()
	data["player_name"] = clean.substr(0, MAX_PLAYER_NAME_CHARS)
	# An explicit choice is never migrated again, even if it happens to match
	# the legacy capture persona.
	data["player_name_migrated"] = true
	_sync_player_name()
	write_save()


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
	# Locale is save data, not a display-server setting: apply on headless too so
	# tests/export scripts see the same UI language as a client boot.
	var locale_code: String = str(s.get("locale", "en")).strip_edges()
	if locale_code == "":
		locale_code = "en"
	var loc: Node = get_node_or_null("/root/Loc")
	if loc != null and loc.has_method("set_locale"):
		loc.call("set_locale", locale_code)
	else:
		TranslationServer.set_locale(locale_code)


func _apply_bus_direct(bus_name: String, bus_vol: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(bus_vol, 0.001)))
	AudioServer.set_bus_mute(idx, bus_vol <= 0.001)


func _default_loadout() -> Dictionary:
	return {
		"head": "",
		"body": "",
		"calling_card": "",
		# KF03 slots: 1 Zipwire (signature), 2 Smoke Bomb, 3 empty/swappable,
		# 4 Vistara Diamond (signature). Active indices are UI state only.
		"tools": ["zipwire", "smoke_bomb", "", "vistara_diamond"],
		"perks": [],
		"active_tool": 0,
		"active_tool_id": "zipwire",
	}


func _default_personal_quest_entry() -> Dictionary:
	return {"stage": "", "owl": "none", "facts": []}


## Canonical schema. `equipped_loadout` is keyed by thief id so Spider and
## Chameleon keep independent cosmetics/tools (the old flat "loadout" key and
## the array form are migrated in _ensure_defaults). `personal_quest` is keyed
## the same way: a thief's chain record holds {stage, owl, facts} and unknown
## keys inside it are preserved by _ensure_personal_quest.
func _defaults() -> Dictionary:
	return {
		"xp": 0,
		"level": 1,
		"completed_contracts": {},
		"unlocked_tools": ["blackjack", "smoke_bomb", "zipwire"],
		"unlocked_perks": ["novice_difficulty", "guildhall", "old_manor", "spider"],
		"unlocked_cosmetics": STARTER_COSMETICS.duplicate(),
		"unlock_ids_schema": UNLOCK_IDS_SCHEMA_VERSION,
		"unlock_ids_migrated": false,
		"currency": 0,
		"player_name": DEFAULT_PLAYER_NAME,
		"player_name_migrated": false,
		"equipped_loadout": {"spider": _default_loadout(), "chameleon": _default_loadout()},
		"active_decoration": "faberge_egg",
		"personal_quest_schema": PERSONAL_QUEST_SCHEMA_VERSION,
		"personal_quest_migrated": false,
		"personal_quest": {
			"spider": _default_personal_quest_entry(),
			"chameleon": _default_personal_quest_entry(),
		},
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
			"graphics_quality": GRAPHICS_QUALITY_DEFAULT,
			"touch_sensitivity": 2.5,
			"mobile_quality": "balanced",
			"locale": "en",
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
		# Per-thief chain records are free-form on purpose: replacement keeps
		# unknown entry keys, which _ensure_personal_quest then normalizes in
		# place. This must run before the generic dict merge, or the schema
		# walk drops keys it does not know.
		if key == PERSONAL_QUEST_KEY and inc is Dictionary:
			target[key] = (inc as Dictionary).duplicate(true)
			continue
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
		# Locale is a short shipped code; a missing/wrong-typed/blank value
		# falls back to the authored English table (Loc still validates it).
		if not s.has("locale") or not (s["locale"] is String) or str(s["locale"]).strip_edges() == "":
			s["locale"] = "en"
		# Desktop quality ladder: a hand-edited or legacy save may carry an
		# unknown value; WeatherProfile would silently fall back to high, but
		# the settings UI needs a canonical stored key. Normalise in place.
		var gq: Variant = s.get("graphics_quality", GRAPHICS_QUALITY_DEFAULT)
		if not (gq is String) or not GRAPHICS_QUALITY_KEYS.has(str(gq).to_lower()):
			s["graphics_quality"] = GRAPHICS_QUALITY_DEFAULT
		else:
			s["graphics_quality"] = str(gq).to_lower()
	for key: Variant in defaults.keys():
		var k: String = str(key)
		if not data.has(k):
			data[k] = (defaults[k] as Variant)
	# Validated player handle: type and length are checked here so every
	# consumer can trust GameState.player_name/SaveSystem.data["player_name"].
	# Blank stays blank (the UI then shows the authored thief title).
	var pn_v: Variant = data.get("player_name", "")
	if not (pn_v is String):
		data["player_name"] = DEFAULT_PLAYER_NAME
	else:
		data["player_name"] = str(pn_v).strip_edges().substr(0, MAX_PLAYER_NAME_CHARS)
	# Legacy saves may use "slithersap" without underscore; normalize it.
	if data.has("unlocked_tools") and data["unlocked_tools"] is Array:
		var tools: Array = data["unlocked_tools"] as Array
		if tools.has("slithersap") and not tools.has("slither_sap"):
			tools.append("slither_sap")
	# Guarantee the two starter tools even if an old save overwrote the list.
	for starter: String in STARTER_TOOLS:
		var arr: Array = data["unlocked_tools"] as Array
		if not arr.has(starter):
			arr.append(starter)
	# Guarantee starter perks / cosmetics on old saves.
	if data.has("unlocked_perks") and data["unlocked_perks"] is Array:
		var perks: Array = data["unlocked_perks"] as Array
		for pid: String in STARTER_PERKS:
			if not perks.has(pid):
				perks.append(pid)
	if data.has("unlocked_cosmetics") and data["unlocked_cosmetics"] is Array:
		var cosmetics: Array = data["unlocked_cosmetics"] as Array
		for cid: String in STARTER_COSMETICS:
			if not cosmetics.has(cid):
				cosmetics.append(cid)
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
	_ensure_personal_quest()


## Stage ordering index (invalid -> -1) for the personal-quest record.
func _personal_stage_index(stage: String) -> int:
	return PERSONAL_QUEST_STAGES.find(stage)


## Normalize the persisted personal-quest subtree in place. Known keys are
## type/domain-checked, facts are filtered to the seven authored ids and
## deduped, and the stage/owl pair is made self-consistent:
##   * facts raise the stage to the earliest beat they prove;
##   * "info"/"complete" need GotInfo and a delivered Owl (the 04 clamp);
##   * "delivered"+ needs HandedOff, otherwise the stage holds at "carrying";
##   * "carrying" needs the Owl held, "delivered"+ needs it delivered, and
##     anything earlier resets the Owl to "none".
## Unknown keys (entry-level and thief-level) are preserved untouched.
func _ensure_personal_quest() -> void:
	var root_v: Variant = data.get(PERSONAL_QUEST_KEY, {})
	if not (root_v is Dictionary):
		root_v = {}
	var root: Dictionary = root_v as Dictionary
	# Schema marker: keep a newer integer schema intact (forward-compatible),
	# but never leave a missing/corrupt value below the known version.
	var schema_v: Variant = data.get("personal_quest_schema", 0)
	if not (schema_v is int) or int(schema_v) < PERSONAL_QUEST_SCHEMA_VERSION:
		data["personal_quest_schema"] = PERSONAL_QUEST_SCHEMA_VERSION
	for thief: String in PERSONAL_QUEST_THIEVES:
		var entry_v: Variant = root.get(thief, null)
		if not (entry_v is Dictionary):
			entry_v = _default_personal_quest_entry()
		var entry: Dictionary = entry_v as Dictionary
		var stage: String = str(entry.get("stage", ""))
		if _personal_stage_index(stage) < 0:
			stage = ""
		var owl: String = str(entry.get("owl", "none"))
		if not PERSONAL_QUEST_OWL_STATES.has(owl):
			owl = "none"
		var facts: Array = []
		var facts_v: Variant = entry.get("facts", [])
		if facts_v is Array:
			for fact_v: Variant in facts_v as Array:
				if not (fact_v is String):
					continue
				var fact_id: String = str(fact_v).strip_edges()
				if fact_id == "" or not PERSONAL_QUEST_PERSISTED_FACTS.has(fact_id):
					continue
				if not facts.has(fact_id):
					facts.append(fact_id)
		# Facts prove a minimum stage even if the stage write was lost.
		for fact_id: String in facts:
			var implied: String = str(PERSONAL_QUEST_FACT_STAGES.get(fact_id, ""))
			if _personal_stage_index(implied) > _personal_stage_index(stage):
				stage = implied
		# 04 clamps: never claim info/complete without the informant fact.
		if _personal_stage_index(stage) >= _personal_stage_index("info") \
				and not facts.has(PERSONAL_QUEST_FACT_GOT_INFO):
			stage = "delivered"
		# The drop needs the courier hand-off; without its fact hold at carrying.
		if _personal_stage_index(stage) >= _personal_stage_index("delivered") \
				and not facts.has(PERSONAL_QUEST_FACT_HANDED_OFF):
			stage = "carrying"
		# Owl consistency mirrors the stage beats.
		var stage_idx: int = _personal_stage_index(stage)
		if stage_idx >= _personal_stage_index("delivered"):
			owl = "delivered"
		elif stage_idx >= _personal_stage_index("carrying"):
			owl = "held"
		else:
			owl = "none"
		entry["stage"] = stage
		entry["owl"] = owl
		entry["facts"] = facts
		root[thief] = entry
	data[PERSONAL_QUEST_KEY] = root


## One-time personal-quest migration. No shipped build wrote this record, so
## the migration only backfills the per-thief entries and stamps the flag;
## it exists so a later schema bump rewrites an old save exactly once.
## Returns true when the save should be persisted.
func _migrate_personal_quest() -> bool:
	if bool(data.get("personal_quest_migrated", false)):
		return false
	data["personal_quest_schema"] = PERSONAL_QUEST_SCHEMA_VERSION
	data["personal_quest_migrated"] = true
	return true


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


## One-time identity migration: early saves defaulted the handle to the
## capture machine's Steam persona. Only that exact value is rewritten to
## blank; any other explicit handle is preserved. `player_name_migrated`
## records the decision so a later explicit persona name (or the game writing
## new saves) never re-runs it. Returns true when the save should be persisted.
func _migrate_player_name() -> bool:
	if bool(data.get("player_name_migrated", false)):
		return false
	var current: String = str(data.get("player_name", "")).strip_edges()
	if current == CAPTURE_PERSONA_NAME:
		data["player_name"] = ""
	data["player_name_migrated"] = true
	return true


## One-time catalog-id migration. Rewrites only ids the old UI shipped:
##   * tools:       "slithersap" -> "slither_sap", "fairy" -> "pickpocket_fairy"
##   * cosmetics:   short ledger ids -> authored outfit tags (see
##                  LEGACY_COSMETIC_TAGS; shared ids map to both thieves)
##   * loadout:     a short head/body/card id -> the authored tag for that thief
## Unknown ids (a newer build's, a hand-edited one) are copied through
## untouched, list order is preserved, and duplicates collapse to the first
## occurrence. `unlock_ids_migrated` makes this run exactly once.
## Returns true when the save should be persisted.
func _migrate_unlock_ids() -> bool:
	if bool(data.get("unlock_ids_migrated", false)):
		return false
	data["unlocked_tools"] = _migrate_id_list(
		data.get("unlocked_tools", []), LEGACY_TOOL_IDS, {}
	)
	data["unlocked_cosmetics"] = _migrate_id_list(
		data.get("unlocked_cosmetics", []), {}, LEGACY_COSMETIC_TAGS
	)
	var eq_v: Variant = data.get("equipped_loadout", {})
	if eq_v is Dictionary:
		var eq: Dictionary = eq_v as Dictionary
		for thief: String in eq.keys():
			var entry_v: Variant = eq[thief]
			if not (entry_v is Dictionary):
				continue
			var entry: Dictionary = entry_v as Dictionary
			for field: String in ["head", "body", "calling_card"]:
				var current: String = str(entry.get(field, "")).strip_edges()
				if current == "" or current.contains("."):
					continue
				entry[field] = _legacy_cosmetic_tag(current, str(thief), field)
			# Slot tool ids too, or the Wardrobe cannot resolve a legacy
			# "slithersap" against the authored catalog and drops the slot.
			entry["tools"] = _migrate_id_list(
				entry.get("tools", []), LEGACY_TOOL_IDS, {}
			)
			eq[thief] = entry
		data["equipped_loadout"] = eq
	data["unlock_ids_schema"] = UNLOCK_IDS_SCHEMA_VERSION
	data["unlock_ids_migrated"] = true
	return true


## Map one legacy id through `direct` (id -> id) then through `multi`
## (id -> Array of ids); anything unknown is kept verbatim.
func _migrate_id_list(value: Variant, direct: Dictionary, multi: Dictionary) -> Array:
	var out: Array = []
	if value is Array:
		for id_v: Variant in value as Array:
			if not (id_v is String):
				continue
			var raw: String = str(id_v).strip_edges()
			if raw == "":
				continue
			if direct.has(raw):
				raw = str(direct[raw])
			if multi.has(raw):
				for mapped_v: Variant in multi[raw] as Array:
					var mapped: String = str(mapped_v)
					if mapped != "" and not out.has(mapped):
						out.append(mapped)
				continue
			if not out.has(raw):
				out.append(raw)
	return out


## Thief-scoped tag for a legacy loadout field. A shared short id resolves to
## that thief's authored row (the loadout always names its thief), falling back
## to the Spider row when the thief has no such cosmetic.
func _legacy_cosmetic_tag(short_id: String, thief: String, field: String) -> String:
	var candidates: Array = []
	if LEGACY_COSMETIC_TAGS.has(short_id):
		candidates = (LEGACY_COSMETIC_TAGS[short_id] as Array).duplicate()
	if candidates.is_empty():
		return short_id
	var slot: String = "Head"
	if field == "body":
		slot = "Body"
	elif field == "calling_card":
		slot = "CallingCard"
	for mapped_v: Variant in candidates:
		var mapped: String = str(mapped_v)
		if mapped.begins_with("Outfit." + thief.capitalize() + "." + slot + "."):
			return mapped
	return str(candidates[0])


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_ensure_defaults()
		_sync_level_from_xp()
		_migrate_unlock_ids()
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		_ensure_defaults()
		_sync_level_from_xp()
		_migrate_unlock_ids()
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_merge_validated(parsed as Dictionary)
	_ensure_defaults()
	_sync_level_from_xp()
	# Persist the one-time migrations (settings schema v2 FOV, capture persona
	# -> blank, personal-quest record, catalog save ids) so the next load sees
	# their flags and never re-runs them.
	var migrated: bool = _migrate_settings_schema()
	if _migrate_player_name():
		migrated = true
	if _migrate_personal_quest():
		migrated = true
	if _migrate_unlock_ids():
		migrated = true
	if migrated:
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


## Persisted array for a catalog category ("tools" / "perks" / "cosmetics"),
## with the historical aliases the UI and tests used. Returns [] for an unknown
## category.
func unlock_list_for(category: String) -> Array:
	var key: String = category.strip_edges().to_lower()
	if key in ["tool", "unlocked_tools"]:
		key = "tools"
	elif key in ["perk", "guild_perks", "unlocked_perks"]:
		key = "perks"
	elif key in ["cosmetic", "unlocked_cosmetics"]:
		key = "cosmetics"
	var list_key: String = str(UNLOCK_CATEGORY_KEYS.get(key, ""))
	if list_key == "":
		return []
	if not (data.get(list_key) is Array):
		data[list_key] = []
	return data[list_key] as Array


func _unlock_list_for(category: String) -> Array:
	return unlock_list_for(category)


func is_unlocked(category: String, item_id: String) -> bool:
	var key: String = category.strip_edges().to_lower()
	if key in ["tool", "unlocked_tools"]:
		key = "tools"
	elif key in ["perk", "guild_perks", "unlocked_perks"]:
		key = "perks"
	elif key in ["cosmetic", "unlocked_cosmetics"]:
		key = "cosmetics"
	if not UNLOCK_CATEGORY_KEYS.has(key):
		return false
	return unlock_list_for(key).has(item_id.strip_edges())


## Purchase a Black Market row by its stable catalog save id. `cost` must be
## the authored price the catalog read from unlocks.json: SaveSystem never
## derives or repairs a price. Fails closed for an unknown category, a blank
## id, an owned row, a negative/zero-cost mismatch caller or short funds.
func purchase_item(category: String, item_id: String, cost: int) -> bool:
	# C1: validate the category BEFORE deducting — the old order kept the
	# deduction in memory for unknown categories (no write_save, but the
	# autoload balance was already reduced until reload).
	var key: String = category.strip_edges().to_lower()
	if key in ["tool", "unlocked_tools"]:
		key = "tools"
	elif key in ["perk", "guild_perks", "unlocked_perks"]:
		key = "perks"
	elif key in ["cosmetic", "unlocked_cosmetics"]:
		key = "cosmetics"
	if not UNLOCK_CATEGORY_KEYS.has(key):
		return false
	var clean_id: String = item_id.strip_edges()
	if clean_id == "" or cost < 0:
		return false
	if is_unlocked(key, clean_id):
		return false
	if int(data.get("currency", 0)) < cost:
		return false
	var lst: Array = unlock_list_for(key)
	data["currency"] = int(data.get("currency", 0)) - cost
	if not lst.has(clean_id):
		lst.append(clean_id)
	write_save()
	return true


## Named wrapper for the catalog call site: the id is the save id.
func purchase_by_save_id(category: String, save_id: String, cost: int) -> bool:
	return purchase_item(category, save_id, cost)


## Chameleon gate, shared by the Wardrobe and any other consumer: the authored
## Thief.Chameleon row (Contract 3) is the only contract that unlocks the
## disguise. Legacy explicit flags are honoured for old saves; completing *any*
## contract is not a unlock condition.
func is_thief_unlocked(thief_id: String) -> bool:
	var thief: String = thief_id.strip_edges().to_lower()
	if thief == "" or thief == "spider":
		return true
	if is_unlocked("perks", thief):
		return true
	var completed_v: Variant = data.get("completed_contracts", {})
	if completed_v is Dictionary:
		if (completed_v as Dictionary).has(str(CHAMELEON_CONTRACT_ORDER)):
			return true
	var unlocked_v: Variant = data.get("unlocked_thieves", [])
	if unlocked_v is Array and (unlocked_v as Array).has(thief):
		return true
	return bool(data.get("chameleon_unlocked", false))


func get_level_progress() -> Dictionary:
	var xp: int = clampi(int(data.get("xp", 0)), 0, MAX_SAVE_XP)
	# The stored level is legacy and may be inflated; derive it from XP.
	var level: int = level_for_xp(xp)
	var needed: int = xp_threshold_for_level(level)
	var spent: int = xp_total_for_level(level)
	var in_level: int = clampi(xp - spent, 0, maxi(0, needed - 1))
	return {"level": level, "xp_in_level": in_level, "xp_needed": needed}


# --- Personal quest record (Spider personal chain) -------------------------

## Active thief resolution for the default-argument API: GameState is the live
## source during a run, with "spider" as the schema default outside a run.
func _personal_quest_thief(thief_id: String) -> String:
	var clean: String = thief_id.strip_edges().to_lower()
	if clean != "":
		return clean
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		clean = str(gs.get("thief_id")).strip_edges().to_lower()
		if clean != "":
			return clean
	return "spider"


## Copy of one thief's chain record {stage, owl, facts} (unknown keys kept).
func get_personal_quest(thief_id: String = "") -> Dictionary:
	_ensure_personal_quest()
	var thief: String = _personal_quest_thief(thief_id)
	var root: Dictionary = data[PERSONAL_QUEST_KEY] as Dictionary
	var entry_v: Variant = root.get(thief, null)
	if entry_v is Dictionary:
		return (entry_v as Dictionary).duplicate(true)
	return _default_personal_quest_entry()


func has_personal_quest_fact(thief_id: String, fact_id: String) -> bool:
	var entry: Dictionary = get_personal_quest(thief_id)
	var facts_v: Variant = entry.get("facts", [])
	return facts_v is Array and (facts_v as Array).has(fact_id.strip_edges())


## Set a valid stage. Ordering is the controller's contract; storage only
## rejects unknown domain values, then normalizes stage/owl/facts consistency.
func set_personal_quest_stage(thief_id: String, stage: String) -> bool:
	var clean: String = stage.strip_edges()
	if _personal_stage_index(clean) < 0:
		return false
	var thief: String = _personal_quest_thief(thief_id)
	_ensure_personal_quest()
	var root: Dictionary = data[PERSONAL_QUEST_KEY] as Dictionary
	var entry: Dictionary = (root.get(thief, _default_personal_quest_entry()) as Dictionary)
	if str(entry.get("stage", "")) == clean:
		return false
	entry["stage"] = clean
	root[thief] = entry
	data[PERSONAL_QUEST_KEY] = root
	_ensure_personal_quest()
	write_save()
	return true


func set_personal_quest_owl(thief_id: String, owl: String) -> bool:
	var clean: String = owl.strip_edges()
	if not PERSONAL_QUEST_OWL_STATES.has(clean):
		return false
	var thief: String = _personal_quest_thief(thief_id)
	_ensure_personal_quest()
	var root: Dictionary = data[PERSONAL_QUEST_KEY] as Dictionary
	var entry: Dictionary = (root.get(thief, _default_personal_quest_entry()) as Dictionary)
	if str(entry.get("owl", "none")) == clean:
		return false
	entry["owl"] = clean
	root[thief] = entry
	data[PERSONAL_QUEST_KEY] = root
	_ensure_personal_quest()
	write_save()
	return true


## Persist authored chain facts. Unknown/never-grant ids are ignored by
## normalization (contract facts, Reminder, Renegade, ObjectiveComplete_*);
## returns the number of new ids actually stored.
func add_personal_quest_facts(thief_id: String, fact_ids: Array) -> int:
	var thief: String = _personal_quest_thief(thief_id)
	_ensure_personal_quest()
	var root: Dictionary = data[PERSONAL_QUEST_KEY] as Dictionary
	var entry: Dictionary = (root.get(thief, _default_personal_quest_entry()) as Dictionary)
	var facts: Array = entry.get("facts", []) as Array
	if not (entry.get("facts", []) is Array):
		facts = []
	var added: int = 0
	for fact_v: Variant in fact_ids:
		if not (fact_v is String):
			continue
		var fact_id: String = str(fact_v).strip_edges()
		if fact_id == "" or not PERSONAL_QUEST_PERSISTED_FACTS.has(fact_id):
			continue
		if facts.has(fact_id):
			continue
		facts.append(fact_id)
		added += 1
	if added == 0:
		return 0
	entry["facts"] = facts
	root[thief] = entry
	data[PERSONAL_QUEST_KEY] = root
	_ensure_personal_quest()
	write_save()
	return added


## Clear one thief's chain record (blank = the active thief). The chain can
## start again on the next Guildhall deploy.
func reset_personal_quest(thief_id: String = "") -> void:
	var thief: String = _personal_quest_thief(thief_id)
	_ensure_personal_quest()
	var root: Dictionary = data[PERSONAL_QUEST_KEY] as Dictionary
	root[thief] = _default_personal_quest_entry()
	data[PERSONAL_QUEST_KEY] = root
	_ensure_personal_quest()
	write_save()


## Clear every thief's chain record (new profile / QA reset).
func reset_all_personal_quests() -> void:
	_ensure_personal_quest()
	var root: Dictionary = data[PERSONAL_QUEST_KEY] as Dictionary
	for thief: String in PERSONAL_QUEST_THIEVES:
		root[thief] = _default_personal_quest_entry()
	data[PERSONAL_QUEST_KEY] = root
	_ensure_personal_quest()
	write_save()
