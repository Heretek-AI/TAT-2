extends Node
## Global run state: selected thief, contract, difficulty, loot, stealth ratings.

signal loot_changed(collected: int, needed: int, value: int)
## Carried inventory (W7S-S2). The HUD tickers are deferred; these signals are
## the wiring point (used slots, capacity, carried face value) and stash change.
signal carried_loot_changed(used_slots: int, max_slots: int, carried_value: int)
signal stash_changed(stashed_value: int)
signal objective_completed()
signal state_changed(new_state: String)
signal objectives_updated()
signal mission_letter_requested(title: String, intro_text: String)
signal clue_facts_changed()
## Emitted when the two-phase run clock changes phase (main -> endgame ->
## resolved). HUD/pause screens may poll GameState.phase instead; the signal is
## for QA and future listeners.
signal phase_changed(new_phase: String)

enum Difficulty { NOVICE = 1, THIEF = 2, MASTER_THIEF = 3 }

## Two-phase run clock (W7E). The main window is the mission row's authored
## match duration (LootTheRoom 3300 s = 55:00); completing the objectives
## summons the escape doors and starts the endgame window (KF13 override
## 1200 s = 20:00 for LootTheRoom, authored QG values for other missions).
const PHASE_MAIN: String = "main"
const PHASE_ENDGAME: String = "endgame"
const PHASE_RESOLVED: String = "resolved"

var thief_id: String = "spider" # spider (Nisha) | chameleon (Cotter)
## Optional player-chosen handle. Blank means "no explicit handle": the HUD
## portrait plate, ledger and prep screen then show the authored thief title
## ("The Spider" / "The Chameleon"). SaveSystem owns the persisted,
## type-validated copy (SaveSystem.set_player_name() is the API).
var player_name: String = ""
var outfit_body: String = "Default"
var outfit_head: String = "Default"
var calling_card: String = "Default"
var difficulty: int = Difficulty.NOVICE
var active_contract_order: int = 2
var active_map_id: String = "old_manor"
var active_mission_id: String = ""
var active_mission_mode: String = "Solo"
## Free-play ("Contract Inactive") mode: a Guildhall Cleanout run with no
## active contract. Hosted on the existing Guildhall contract order (2) so the
## shipped 16-contract tables and the Den hub's `order <= 1` semantics are
## untouched; contract 2 is also the order the prep UI already resolves to the
## LootTheRoom row for the Guildhall map (matching[2 % 3]).
const FREE_PLAY_CONTRACT_ORDER: int = 2
const FREE_PLAY_MISSION_ID: String = "Mission.Guildhall.LootTheRoom"
var free_play: bool = false
## reset_run() clears the live run fields (including free_play and
## active_mission_id on a map change), so the mode choice is staged here and
## republished by reset_run. Prep and the QA autostart set these; the deploy
## closure re-stages them around its own reset_run call.
var free_play_pending: bool = false
var pending_mission_id: String = ""
# Run-selection state used by SV_* scene variants and match modes.
var active_map_seed: int = 0
var active_scene_variants: Array[String] = []
var active_match_mode: String = "solo" # solo | coop_host | coop_client | ftue

## Canonical identity accessor (contract name); keeps thief_id as the store.
var active_thief_id: String:
	get:
		return thief_id
	set(value):
		thief_id = value

var state: String = "menu" # menu | hub | playing | paused | victory | failed
var elapsed_sec: float = 0.0
var run_time_limit: float = 0.0 # main-phase match timer seconds; 0 = unlimited (FTUE/tutorial/expansion)
## W7E two-phase clock. `phase` is main until the objectives complete, then
## endgame while the summoned doors are open, then resolved once the run is
## banked/failed. Each phase owns its own elapsed counter so only the active
## phase ticks (the main clock freezes when the doors open).
var phase: String = PHASE_MAIN
var endgame_time_limit: float = 0.0 # endgame door window seconds; 0 = unlimited
var endgame_elapsed: float = 0.0
## Authored BP_EscapePoint markers spawned for this run, one record per marker:
## {index, authored, position, grounded, connected, activated, expired, gate}.
var escape_markers: Array[Dictionary] = []
## Peer ids that have already extracted this run (host-once local transport).
var extracted_players: Array[int] = []
var loot_collected: int = 0
var loot_needed: int = 0 # LEGACY compat for loot_changed/snapshots only; the live threshold is loot_goal.
## Gross authored loot value collected this run. It is the ORIGINAL haul and is
## monotonically increasing: stashing moves carried entries to stashed_loot_value
## but never subtracts from this counter (the post-match Original field).
var loot_value: int = 0
var loot_goal: int = 0
## Carried loot (W7S-S2): one entry per carried item, written by
## src/interact/loot_inventory.gd. Slots are 12 (authored
## TATLootInventoryComponent.InventorySlotMaxCapacity); a major entry costs 3.
var carried_loot: Array[Dictionary] = []
## False until the first tracked pickup. Staged/legacy runs that only set
## loot_value are paid from the gross counter (see LootInventory.build_payout).
var carried_tracking_active: bool = false
## Value already deposited in a stash; always kept at match end.
var stashed_loot_value: int = 0
## Payout id for this run (idempotent SaveSystem.bank_payout key).
var loot_run_id: String = ""
## Last built payout record (UI/read-only mirror of SaveSystem.last_match).
var last_payout: Dictionary = {}
static var _loot_run_serial: int = 0
var mission_objectives: Array[Dictionary] = []
var contract_title: String = ""
var contract_intro: String = ""
var stolen_keys: Array[String] = []
## Shipped item names (authored text tables), not the extracted mesh/icon
## family: the pickpocketed constable key reads "Guildhall Key" (S22/KF25),
## the Old Manor key "Elway Manor Key", and the safe/lock keys "Vault Key".
## Unknown ids still render, title-cased, instead of vanishing.
const STOLEN_KEY_NAMES: Dictionary = {
	"key_guildhall": "Guildhall Key",
	"key_manor": "Elway Manor Key",
	"key_vault": "Vault Key",
}
## Journal of authored clue facts learned this run (see GameData.clue_facts).
## Ordinary facts dedupe by fact id; templated Set.Location facts dedupe by
## fact id + the quest item that supplied {item}/{Location}. This is run state
## only — the save schema is untouched.
var clue_facts: Array[Dictionary] = []
var quest_item_acquired: bool = false
var ever_spotted: bool = false
var ever_chased: bool = false
var takedowns: int = 0
var player_light_visibility: float = 0.2 # 0.0 shadow .. 1.0 bright


## Player-facing handle used by the HUD portrait plate, the ledger and the
## mission-prep nameplate. An explicit non-empty saved handle wins; otherwise
## the authored title for the active thief is shown. The shipped footage's
## audience is a named player, never the capture machine's Steam persona.
func player_display_name() -> String:
	var explicit: String = player_name.strip_edges()
	if explicit != "":
		return explicit
	var source: String = "The Chameleon" if thief_id == "chameleon" else "The Spider"
	var loc: Node = get_node_or_null("/root/Loc")
	if loc != null and loc.has_method("t"):
		return str(loc.call("t", source))
	return source


func reset_run(contract_order: int, map_id: String) -> void:
	active_contract_order = contract_order
	if active_map_id != map_id:
		active_mission_id = ""
	active_map_id = map_id
	# Free-play is a mode, not run progress: clear the live flag with the rest
	# of the run and republish the staged choice (prep / QA autostart / deploy
	# closure). The pending mission id also survives the map-change wipe of
	# active_mission_id above.
	free_play = false
	if free_play_pending:
		free_play = true
		if pending_mission_id != "":
			active_mission_id = pending_mission_id
	elapsed_sec = 0.0
	run_time_limit = 0.0
	phase = PHASE_MAIN
	endgame_time_limit = 0.0
	endgame_elapsed = 0.0
	escape_markers = []
	extracted_players = []
	loot_collected = 0
	loot_needed = 0
	loot_value = 0
	loot_goal = 0
	carried_loot = []
	carried_tracking_active = false
	stashed_loot_value = 0
	last_payout = {}
	_loot_run_serial += 1
	loot_run_id = "%s-%d-%d" % [map_id, int(Time.get_unix_time_from_system()), _loot_run_serial]
	mission_objectives = []
	contract_title = ""
	contract_intro = ""
	stolen_keys = []
	quest_item_acquired = false
	# A new run starts a fresh journal. Returning to the Den hub (map_id
	# "thieves_den") is not a mission reset, so the journal survives the hub
	# transition and is only cleared when the next mission deploys.
	if map_id != "thieves_den" and not clue_facts.is_empty():
		clue_facts.clear()
		clue_facts_changed.emit()
	# Personal-quest facts are the exception: they are save state, so they are
	# re-journaled after the wipe. Contract facts only live for the run.
	hydrate_personal_facts()
	ever_spotted = false
	ever_chased = false
	takedowns = 0
	player_light_visibility = 0.2
	state = "playing"
	state_changed.emit(state)
	objectives_updated.emit()
	loot_changed.emit(loot_collected, loot_needed, loot_value)
	carried_loot_changed.emit(carried_slots_used(), 12, carried_total_value())
	stash_changed.emit(stashed_loot_value)


## Carried inventory helpers (W7S-S2). Slots are per-entry slot_cost (a major
## entry costs 3); the capacity constant lives in loot_inventory.gd.
func carried_slots_used() -> int:
	var used: int = 0
	for entry: Dictionary in carried_loot:
		used += maxi(int(entry.get("slot_cost", 1)), 0)
	return used


func carried_total_value() -> int:
	var total: int = 0
	for entry: Dictionary in carried_loot:
		total += maxi(int(entry.get("value", 0)), 0)
	return total


func notify_carried_loot_changed() -> void:
	carried_loot_changed.emit(carried_slots_used(), 12, carried_total_value())


func notify_stash_changed() -> void:
	stash_changed.emit(maxi(stashed_loot_value, 0))


func is_main_phase() -> bool:
	return phase == PHASE_MAIN


func is_endgame_phase() -> bool:
	return phase == PHASE_ENDGAME


func is_resolved_phase() -> bool:
	return phase == PHASE_RESOLVED


## Start the endgame door window. Only a main-phase run can transition; a
## repeated call (two objective completions, extraction races) is a no-op and
## returns false so the caller can log an idempotent transition once.
func begin_endgame(seconds_override: float = -1.0) -> bool:
	if phase != PHASE_MAIN:
		return false
	if seconds_override > 0.0:
		endgame_time_limit = seconds_override
	if endgame_time_limit <= 0.0:
		# No authored QG/override value: keep a bounded door window rather than
		# an infinite one. MissionController logs the fallback explicitly.
		endgame_time_limit = 480.0
	endgame_elapsed = 0.0
	phase = PHASE_ENDGAME
	phase_changed.emit(phase)
	return true


## Mark the run resolved (victory or failure). Idempotent.
func resolve_phase() -> void:
	if phase == PHASE_RESOLVED:
		return
	phase = PHASE_RESOLVED
	phase_changed.emit(phase)


## Seconds budget of the phase that is actually ticking (main or endgame).
func phase_time_limit() -> float:
	if phase == PHASE_ENDGAME:
		return endgame_time_limit
	if phase == PHASE_RESOLVED:
		return 0.0
	return run_time_limit


## Seconds already spent in the active phase.
func phase_elapsed() -> float:
	if phase == PHASE_ENDGAME:
		return endgame_elapsed
	if phase == PHASE_RESOLVED:
		return 0.0
	return elapsed_sec


## Seconds left in the active phase; 0 when unlimited/resolved.
func phase_time_remaining() -> float:
	var limit: float = phase_time_limit()
	if limit <= 0.0:
		return 0.0
	return maxf(0.0, limit - phase_elapsed())


## Total run time (both phases) for result panels/logs.
func total_elapsed() -> float:
	return elapsed_sec + endgame_elapsed


## Register a peer that extracted. Returns false when that peer already
## completed the run (host-once guard for the local-only co-op transport).
func register_extracted_player(peer_id: int) -> bool:
	if extracted_players.has(peer_id):
		return false
	extracted_players.append(peer_id)
	return true


## Replace the run's authored escape-marker records (one per BP_EscapePoint).
func set_escape_markers(records: Array) -> void:
	escape_markers = []
	for rec_v: Variant in records:
		if rec_v is Dictionary:
			escape_markers.append((rec_v as Dictionary).duplicate(true))


func active_escape_count() -> int:
	var count: int = 0
	for rec: Dictionary in escape_markers:
		if rec.get("activated", false) == true and rec.get("expired", false) != true:
			count += 1
	return count


## Enter free play: stage the mode so reset_run republishes it, and publish it
## immediately for callers that are already past their reset (prep READY).
func begin_free_play(mission_id: String = FREE_PLAY_MISSION_ID) -> void:
	free_play = true
	free_play_pending = true
	pending_mission_id = mission_id
	active_mission_id = mission_id


## Leave free play (a normal contract deploy / normal READY). Clears both the
## live flag and the stash so a later reset_run cannot resurrect it.
func end_free_play() -> void:
	free_play = false
	free_play_pending = false
	pending_mission_id = ""


## Group digits with thousands separators (4000 -> "4,000") for HUD/objective
## text that the reference prints in full (e.g. "Steal 4,000 in loot value").
func format_thousands(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


func set_mission_objectives(objs: Array, p_loot_goal: int = -1) -> void:
	var normalized: Array[Dictionary] = []
	for item_v: Variant in objs:
		if not (item_v is Dictionary):
			continue
		var d: Dictionary = item_v as Dictionary
		var target_val: int = maxi(int(d.get("target", 1)), 0)
		var cur_val: int = maxi(int(d.get("current", 0)), 0)
		var is_done: bool = d.get("done") == true
		if target_val > 0 and cur_val >= target_val:
			is_done = true
		normalized.append({
			"id": str(d.get("id", "obj_%d" % normalized.size())),
			"label": str(d.get("label", "")),
			"done": is_done,
			"current": cur_val,
			"target": target_val,
		})
	mission_objectives = normalized
	if p_loot_goal >= 0:
		loot_goal = p_loot_goal
		# S2 companion: loot_needed is the LEGACY HUD/gate threshold (read by
		# hud.gd + escape_gate.gd). It used to sit at 5 forever while the real
		# completion read loot_goal — two thresholds, one stale. Sync it here
		# so legacy readers follow the live goal; the loot_changed signal
		# keeps its (collected, needed, value) shape for compat.
		loot_needed = p_loot_goal
	objectives_updated.emit()


func update_objective_progress(obj_id: String, delta_or_current: int, is_absolute: bool = false) -> bool:
	var matched_done: bool = false
	var found: bool = false
	for i: int in range(mission_objectives.size()):
		var entry: Dictionary = mission_objectives[i]
		if str(entry.get("id", "")) != obj_id:
			continue
		found = true
		var target_val: int = maxi(int(entry.get("target", 1)), 0)
		var prev_cur: int = int(entry.get("current", 0))
		var next_cur: int = delta_or_current if is_absolute else (prev_cur + delta_or_current)
		if target_val > 0:
			next_cur = clampi(next_cur, 0, target_val)
		else:
			next_cur = maxi(next_cur, 0)
		entry["current"] = next_cur
		entry["done"] = (next_cur >= target_val) if target_val > 0 else (next_cur > 0)
		mission_objectives[i] = entry
		matched_done = entry["done"] == true
		break
	if found:
		if are_all_objectives_complete():
			objective_completed.emit()
		objectives_updated.emit()
	return matched_done


func mark_objective_done(obj_id: String) -> void:
	for i: int in range(mission_objectives.size()):
		var entry: Dictionary = mission_objectives[i]
		if str(entry.get("id", "")) == obj_id:
			var target_val: int = maxi(int(entry.get("target", 1)), 1)
			update_objective_progress(obj_id, target_val, true)
			return


func are_all_objectives_complete() -> bool:
	if loot_goal > 0 and loot_value < loot_goal:
		return false
	if mission_objectives.is_empty():
		return quest_item_acquired
	for entry: Dictionary in mission_objectives:
		if entry.get("done") != true:
			return false
	return true


func request_mission_letter(title: String, intro_text: String) -> void:
	contract_title = title
	contract_intro = intro_text
	mission_letter_requested.emit(title, intro_text)


func add_stolen_key(key_id: String) -> void:
	if key_id != "" and not stolen_keys.has(key_id):
		stolen_keys.append(key_id)


func has_stolen_key(key_id: String) -> bool:
	return stolen_keys.has(key_id)


## Shipped key display name; unknown ids fall back to title case ("key_foo"
## -> "Key Foo") so a new key is still readable rather than hidden.
func stolen_key_display_name(key_id: String) -> String:
	var clean: String = key_id.strip_edges()
	if clean == "":
		return ""
	if STOLEN_KEY_NAMES.has(clean):
		return str(STOLEN_KEY_NAMES[clean])
	var out: String = ""
	for part: String in clean.replace("-", "_").split("_", false):
		if out != "":
			out += " "
		out += part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return out


## Display names for the HUD key row, in acquisition order.
func stolen_key_display_names() -> Array[String]:
	var out: Array[String] = []
	for key_id: String in stolen_keys:
		var label: String = stolen_key_display_name(key_id)
		if label != "" and not out.has(label):
			out.append(label)
	return out


## Learn an authored clue fact (GameData.get_fact). Ordinary facts dedupe by
## fact id; the templated DT_ClueFacts_Quest_Guildhall:Set.Location fact dedupes
## by fact id + source_item_tag so each gem's location can be recorded once.
## Params only replace authored tokens such as {item}/{Location}; nothing is
## invented when a value is missing.
func grant_fact(fact_id: String, params: Dictionary = {}, source: String = "", source_item_tag: String = "", source_index: int = -1) -> bool:
	var fact: Dictionary = GameData.get_fact(fact_id)
	if fact.is_empty():
		push_error("[game_state] grant_fact: unknown authored fact id '", fact_id, "' (source=", source, ")")
		return false
	var templated: bool = fact_id.ends_with(":Set.Location") or fact_id.ends_with(".Set.Location")
	var dedupe_key: String = fact_id
	if templated:
		dedupe_key = fact_id + "|" + source_item_tag
	for entry: Dictionary in clue_facts:
		if str(entry.get("dedupe_key", entry.get("id", ""))) == dedupe_key:
			return false
	var journal_text: String = _format_fact_text(str(fact.get("journal_text", "")), params)
	if journal_text.strip_edges() == "":
		push_warning("[game_state] grant_fact: authored fact '", fact_id, "' has no journal text; not added")
		return false
	if templated and (str(params.get("item", "")) == "" or str(params.get("Location", "")) == ""):
		push_warning("[game_state] grant_fact: Set.Location fact '", fact_id, "' received incomplete params (item='", str(params.get("item", "")), "', Location='", str(params.get("Location", "")), "'); journal keeps the authored placeholders")
	clue_facts.append({
		"id": fact_id,
		"dedupe_key": dedupe_key,
		"fact_tag": str(fact.get("fact_tag", "")),
		"journal_text": journal_text,
		"display_priority": int(fact.get("display_priority", 0)),
		"category": str(fact.get("category", "")),
		"source": source,
		"source_item_tag": source_item_tag,
		"source_index": source_index,
		"learned_index": clue_facts.size(),
		"params": params.duplicate(true),
	})
	clue_facts_changed.emit()
	return true


func has_clue_fact(fact_id: String, source_item_tag: String = "") -> bool:
	for entry: Dictionary in clue_facts:
		if str(entry.get("id", "")) != fact_id:
			continue
		if source_item_tag == "" or str(entry.get("source_item_tag", "")) == source_item_tag:
			return true
	return false


## Re-journal the active thief's persisted personal-quest facts. Called by
## reset_run() after the contract journal is wiped, so the Spider chain's
## facts survive a deploy while contract facts (which are never in the save
## record) do not. Returns how many facts were added this call; already
## journaled facts are skipped, so calling it on the Den transition is cheap.
## Facts are authored rows only (SaveSystem already filtered the record), and
## each one is re-read from GameData.grant_fact so the journal text stays
## authoritative.
func hydrate_personal_facts() -> int:
	var ss: Node = get_node_or_null("/root/SaveSystem")
	if ss == null or not ss.has_method("get_personal_quest"):
		return 0
	var entry: Dictionary = ss.call("get_personal_quest", thief_id) as Dictionary
	if entry.is_empty():
		return 0
	var facts_v: Variant = entry.get("facts", [])
	if not (facts_v is Array):
		return 0
	var added: int = 0
	for fact_v: Variant in facts_v as Array:
		if not (fact_v is String):
			continue
		var fact_id: String = str(fact_v).strip_edges()
		if fact_id == "" or has_clue_fact(fact_id):
			continue
		if grant_fact(fact_id, {}, "personal_quest"):
			added += 1
	return added


func _format_fact_text(text: String, params: Dictionary) -> String:
	var out: String = text
	for key_v: Variant in params.keys():
		var key: String = str(key_v)
		var value: String = str(params[key_v])
		if key == "":
			continue
		out = out.replace("{%s}" % key, value)
		out = out.replace("{%s}" % key.to_lower(), value)
		out = out.replace("{%s}" % key.capitalize(), value)
	return out


func add_loot(amount: int, value: int, is_quest_item: bool = false, objective_id: String = "") -> void:
	loot_collected += amount
	loot_value += value
	var obj_dirty: bool = false
	var should_emit_complete: bool = false
	if loot_goal > 0:
		for i: int in range(mission_objectives.size()):
			var entry: Dictionary = mission_objectives[i]
			if str(entry.get("id", "")) == "cleanout_loot":
				var next_val: int = mini(loot_value, loot_goal)
				entry["current"] = next_val
				entry["done"] = loot_value >= loot_goal
				mission_objectives[i] = entry
				obj_dirty = true
				break
		# S1: the loot path used to set quest_item_acquired + emit complete
		# on its own, so a rich run finished with vault/set objectives open
		# (dual completion sources). Now it only completes when the full
		# objective list — including the quest item — is actually done.
		if are_all_objectives_complete():
			should_emit_complete = true
	if is_quest_item:
		var handled_set: bool = false
		if objective_id != "":
			for i: int in range(mission_objectives.size()):
				var entry: Dictionary = mission_objectives[i]
				if str(entry.get("id", "")) == objective_id:
					var target_val: int = maxi(int(entry.get("target", 1)), 1)
					entry["current"] = mini(int(entry.get("current", 0)) + 1, target_val)
					entry["done"] = int(entry["current"]) >= target_val
					mission_objectives[i] = entry
					obj_dirty = true
					break
		# S2: the old code bumped set_main on EVERY quest pickup, even when
			# a specific objective_id was given (double-counting that item
			# toward both its own objective and the set counter). The set
			# counter now advances only for generic pickups (objective_id
			# "" — the live loot_item flow) or an explicit "set_main".
		if objective_id == "" or objective_id == "set_main":
			for i: int in range(mission_objectives.size()):
				var entry: Dictionary = mission_objectives[i]
				if str(entry.get("id", "")) == "set_main":
					var target_val: int = maxi(int(entry.get("target", 3)), 1)
					var next_cur: int = mini(int(entry.get("current", 0)) + 1, target_val)
					entry["current"] = next_cur
					entry["done"] = next_cur >= target_val
					mission_objectives[i] = entry
					# Also mark the next incomplete set sub-item done.
					for j: int in range(mission_objectives.size()):
						var sub: Dictionary = mission_objectives[j]
						if str(sub.get("id", "")).begins_with("set_item_") and sub.get("done") != true:
							sub["current"] = maxi(int(sub.get("target", 1)), 1)
							sub["done"] = true
							mission_objectives[j] = sub
							break
					obj_dirty = true
					handled_set = true
					if entry["done"] == true:
						quest_item_acquired = true
						should_emit_complete = true
					break
		if not handled_set:
			quest_item_acquired = true
			should_emit_complete = true
			for i: int in range(mission_objectives.size()):
				var entry: Dictionary = mission_objectives[i]
				var eid: String = str(entry.get("id", ""))
				if eid == "vault_main" or eid == "contract_main":
					var t_val: int = maxi(int(entry.get("target", 1)), 1)
					entry["current"] = t_val
					entry["done"] = true
					mission_objectives[i] = entry
					obj_dirty = true
	if obj_dirty:
		objectives_updated.emit()
	if should_emit_complete:
		objective_completed.emit()
	loot_changed.emit(loot_collected, loot_needed, loot_value)


## Authored Set quest-item pickup: advance set_main once for a specific
## set_item_N objective. Kept out of add_loot() so the legacy dedupe contract
## (T2-18-B: a repeated set_item id never advances set_main by itself) holds.
func advance_set_objective() -> void:
	for i: int in range(mission_objectives.size()):
		var entry: Dictionary = mission_objectives[i]
		if str(entry.get("id", "")) != "set_main":
			continue
		var target_val: int = maxi(int(entry.get("target", 1)), 1)
		var next_cur: int = mini(int(entry.get("current", 0)) + 1, target_val)
		entry["current"] = next_cur
		entry["done"] = next_cur >= target_val
		mission_objectives[i] = entry
		if entry["done"] == true and are_all_objectives_complete():
			quest_item_acquired = true
			objective_completed.emit()
		objectives_updated.emit()
		return


func difficulty_label() -> String:
	match difficulty:
		Difficulty.NOVICE: return "Novice"
		Difficulty.THIEF: return "Thief"
		Difficulty.MASTER_THIEF: return "Master Thief"
	return "Novice"


func difficulty_curve_x() -> float:
	return float(difficulty)


func compute_stealth_bonus_multiplier() -> float:
	var mult := 1.0
	if not ever_spotted:
		mult += 0.25 # Ghost
	elif not ever_chased:
		mult += 0.10 # Shadow
	return mult
