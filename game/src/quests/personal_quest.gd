extends RefCounted
## Spider personal quest: "The Theban Owl" (CLS_Personal_Spider_01..04).
##
## Static, scene-free controller over the authored expansion record
## `game/data/expansion/personal_spider.json` plus the SaveSystem record and
## GameState journal. The mission/NPC/dialogue runtime is a later wave: this
## module only decides which beat is current, which facts that beat grants,
## where the next interaction is pinned, and how the persisted record moves.
##
## Invariants (checked by tools/check_clue_quests.py and suite 86):
##   * stages only move forward one beat at a time;
##   * `03:Reminder` / `04:Renegade` / `ObjectiveComplete_*` are never granted;
##   * the Owl is held only while carrying and delivered from `delivered` on;
##   * `info`/`complete` require GotInfo and a delivered Owl;
##   * completion is a follow-up close, not a new fact.

const EXPANSION_PATH := "res://data/expansion/personal_spider.json"
const THIEF_ID := "spider"

static var _chain_cache: Dictionary = {}


## Parsed expansion record (cached; the file is tracked authored data).
static func chain() -> Dictionary:
	if not _chain_cache.is_empty():
		return _chain_cache
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPANSION_PATH))
	if parsed is Dictionary:
		_chain_cache = parsed as Dictionary
	else:
		push_error("[personal_quest] cannot read ", EXPANSION_PATH)
	return _chain_cache


static func stages() -> Array:
	return chain().get("stages", []) as Array


static func stage_index(stage: String) -> int:
	return stages().find(stage)


static func is_valid_stage(stage: String) -> bool:
	return stage_index(stage.strip_edges()) >= 0


static func fact_order() -> Array:
	return chain().get("fact_order", []) as Array


static func never_grant_fact_ids() -> Array:
	return chain().get("never_grant_fact_ids", []) as Array


## True only for the seven authored chain facts; Reminder/Renegade and both
## ObjectiveComplete_* rows are refused even if a caller asks for them.
static func is_grantable(fact_id: String) -> bool:
	return fact_order().has(fact_id.strip_edges())


## The only fact ids the chain may ever grant (shell for runtime callers).
static func grantable_fact_ids() -> Array:
	return fact_order().duplicate()


## Clue sets whose first beat has not been reached yet: the later runtime
## should not distribute these from the contract clue pass. A set is released
## as soon as any of its beats is current (CLS_01 spans intro/letter/electrotype
## but its Library note exists from the intro deploy).
static func suppressed_clue_sets(stage: String) -> Array:
	var first_beat: Dictionary = {}
	for beat_v: Variant in chain().get("beats", []) as Array:
		if not (beat_v is Dictionary):
			continue
		var beat: Dictionary = beat_v as Dictionary
		var set_name: String = str(beat.get("clue_set", ""))
		if set_name == "":
			continue
		var beat_index: int = stage_index(str(beat.get("stage", "")))
		if not first_beat.has(set_name) or beat_index < int(first_beat[set_name]):
			first_beat[set_name] = beat_index
	var current: int = stage_index(stage)
	var out: Array = []
	for set_name: String in first_beat.keys():
		if int(first_beat[set_name]) > current:
			out.append(set_name)
	return out


static func beat_for(stage: String) -> Dictionary:
	for beat_v: Variant in chain().get("beats", []) as Array:
		if beat_v is Dictionary and str((beat_v as Dictionary).get("stage", "")) == stage:
			return (beat_v as Dictionary).duplicate(true)
	return {}


static func next_stage(stage: String) -> String:
	var beat: Dictionary = beat_for(stage)
	return str(beat.get("on_complete", ""))


# --- Autoload access -------------------------------------------------------

static func _autoload(node_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("/root/" + node_name)


static func _save() -> Node:
	return _autoload("SaveSystem")


static func _state() -> Node:
	return _autoload("GameState")


static func _thief_id(thief_id: String) -> String:
	var clean: String = thief_id.strip_edges().to_lower()
	return clean if clean != "" else THIEF_ID


## Persisted record for a thief (blank = Spider). Never empty when SaveSystem
## is available; a scene-free test can pass an explicit thief id.
static func entry_for(thief_id: String = "") -> Dictionary:
	var ss: Node = _save()
	if ss == null or not ss.has_method("get_personal_quest"):
		return {"stage": "", "owl": "none", "facts": []}
	return ss.call("get_personal_quest", _thief_id(thief_id)) as Dictionary


static func stage_for(thief_id: String = "") -> String:
	return str(entry_for(thief_id).get("stage", ""))


static func owl_for(thief_id: String = "") -> String:
	return str(entry_for(thief_id).get("owl", "none"))


static func facts_for(thief_id: String = "") -> Array:
	return entry_for(thief_id).get("facts", []) as Array


## Re-journal the persisted facts through GameState (used by reset_run and by
## a test that wants to prove personal facts survive a deploy).
static func hydrate_facts() -> int:
	var gs: Node = _state()
	if gs == null or not gs.has_method("hydrate_personal_facts"):
		return 0
	return int(gs.call("hydrate_personal_facts"))


# --- Chain transitions -----------------------------------------------------

## Start the chain on the first Guildhall deploy (contract or free play).
## `start_when_completed_contract` is 0, so it is independent of progression.
static func should_start(map_id: String, thief_id: String = "") -> bool:
	if map_id != str(chain().get("start_map_id", "guildhall")):
		return false
	return stage_for(thief_id) == ""


## Grant one beat's facts to the journal and the save record. Returns the new
## ids this call actually added (idempotent: re-running a beat adds nothing).
static func _grant_beat_facts(stage: String, thief_id: String) -> Array:
	var granted: Array = []
	var ss: Node = _save()
	var gs: Node = _state()
	var beat: Dictionary = beat_for(stage)
	for fact_v: Variant in beat.get("grants", []) as Array:
		if not (fact_v is String):
			continue
		var fact_id: String = str(fact_v).strip_edges()
		if not is_grantable(fact_id):
			continue
		var added: int = 0
		if ss != null and ss.has_method("add_personal_quest_facts"):
			added = int(ss.call("add_personal_quest_facts", _thief_id(thief_id), [fact_id]))
		if gs != null and gs.has_method("grant_fact") and not bool(gs.call("has_clue_fact", fact_id)):
			gs.call("grant_fact", fact_id, {}, "personal_quest")
		if added > 0:
			granted.append(fact_id)
	return granted


## Apply a beat's Owl state after its facts, in the one order normalization
## accepts (the stage must already be at/after the state it implies).
static func _apply_beat_owl(stage: String, thief_id: String) -> void:
	var ss: Node = _save()
	if ss == null or not ss.has_method("set_personal_quest_owl"):
		return
	var beat: Dictionary = beat_for(stage)
	var owl: String = str(beat.get("owl", "none"))
	if owl == "":
		return
	ss.call("set_personal_quest_owl", _thief_id(thief_id), owl)


## Advance one beat. `stage` must be the next stage after the current one (or
## the current one, which is an idempotent no-op). Returns
## {ok, previous, stage, granted, reason}. The caller owns when a beat is
## eligible (deploy, note read, Den message delivery, conversation close).
static func record(stage: String, thief_id: String = "") -> Dictionary:
	var clean: String = stage.strip_edges()
	if not is_valid_stage(clean) or clean == "":
		return {"ok": false, "reason": "invalid_stage", "stage": stage_for(thief_id)}
	var current: String = stage_for(thief_id)
	if current == clean:
		return {"ok": true, "reason": "already", "previous": current, "stage": current, "granted": []}
	if stage_index(clean) != stage_index(current) + 1:
		return {
			"ok": false,
			"reason": "out_of_order",
			"previous": current,
			"stage": current,
			"granted": [],
		}
	# Kill-switch: never let a caller grant the dropped rows by stage name.
	if not beat_for(clean).is_empty():
		for fact_v: Variant in (beat_for(clean).get("grants", []) as Array):
			if never_grant_fact_ids().has(str(fact_v)):
				return {"ok": false, "reason": "suppressed_fact", "previous": current, "stage": current, "granted": []}
	var granted: Array = _grant_beat_facts(clean, thief_id)
	_apply_beat_owl(clean, thief_id)
	var ss: Node = _save()
	if ss != null and ss.has_method("set_personal_quest_stage"):
		ss.call("set_personal_quest_stage", _thief_id(thief_id), clean)
	# SaveSystem may have auto-advanced from the granted facts (e.g. HandedOff
	# implies delivered); report the stored stage, not the request.
	return {"ok": true, "reason": "advanced", "previous": current, "stage": stage_for(thief_id), "granted": granted}


## Pending electrotype messages: letter -> electrotype on the Den return or the
## next deploy. Safe to call repeatedly.
static func deliver_pending_messages(thief_id: String = "") -> Dictionary:
	var current: String = stage_for(thief_id)
	if stage_index(current) >= stage_index("electrotype"):
		return {"ok": true, "reason": "already", "stage": current, "granted": []}
	if current != "letter":
		return {"ok": false, "reason": "not_pending", "stage": current, "granted": []}
	return record("electrotype", thief_id)


## Take the Owl: located -> carrying, owl held.
static func acquire_owl(thief_id: String = "") -> Dictionary:
	var current: String = stage_for(thief_id)
	if stage_index(current) >= stage_index("carrying"):
		return {"ok": true, "reason": "already", "stage": current, "granted": []}
	if current != "located":
		return {"ok": false, "reason": "not_located", "stage": current, "granted": []}
	return record("carrying", thief_id)


## Hand the Owl to the courier: carrying -> delivered, owl delivered,
## 03:HandedOff granted.
static func deliver_owl(thief_id: String = "") -> Dictionary:
	var current: String = stage_for(thief_id)
	if stage_index(current) >= stage_index("delivered"):
		return {"ok": true, "reason": "already", "stage": current, "granted": []}
	if current != "carrying":
		return {"ok": false, "reason": "not_carrying", "stage": current, "granted": []}
	return record("delivered", thief_id)


## Talk to the Old Manor informant: delivered -> info, 04:GotInfo granted.
static func deliver_info(thief_id: String = "") -> Dictionary:
	var current: String = stage_for(thief_id)
	if stage_index(current) >= stage_index("info"):
		return {"ok": true, "reason": "already", "stage": current, "granted": []}
	if current != "delivered":
		return {"ok": false, "reason": "not_delivered", "stage": current, "granted": []}
	return record("info", thief_id)


## Close the 04 follow-up: info -> complete. No fact is granted; `complete` is
## a follow-up flag, not a journal entry.
static func close_info(thief_id: String = "") -> Dictionary:
	var current: String = stage_for(thief_id)
	if current == "complete":
		return {"ok": true, "reason": "already", "stage": current, "granted": []}
	if current != "info":
		return {"ok": false, "reason": "not_info", "stage": current, "granted": []}
	return record("complete", thief_id)


# --- Spawn pins ------------------------------------------------------------

## Anchors active for a map at the current stage. Each record is the authored
## anchor plus `active` (true) and `current_stage`; the runtime is expected to
## ground the pin the same way loot/civilians are grounded, and to use
## `fallbacks` only when the primary actor is absent from the loaded scene.
## No position is invented here: every pos is a producer pin.
static func spawn_plan(map_id: String, thief_id: String = "") -> Array:
	var current: String = stage_for(thief_id)
	var out: Array = []
	for anchor_v: Variant in chain().get("anchors", []) as Array:
		if not (anchor_v is Dictionary):
			continue
		var anchor: Dictionary = (anchor_v as Dictionary).duplicate(true)
		if str(anchor.get("map_id", "")) != map_id:
			continue
		if not (anchor.get("stages", []) as Array).has(current):
			continue
		anchor["active"] = true
		anchor["current_stage"] = current
		out.append(anchor)
	return out


## Convenience: the active pin with a given id, or {} when the beat/map is
## wrong (e.g. the informant on the Guildhall map).
static func anchor(map_id: String, anchor_id: String, thief_id: String = "") -> Dictionary:
	for rec_v: Variant in spawn_plan(map_id, thief_id):
		if str((rec_v as Dictionary).get("id", "")) == anchor_id:
			return rec_v as Dictionary
	return {}
