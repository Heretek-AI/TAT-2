class_name VoDirector
extends RefCounted
## W11-A: authored VO director — which of the 645 authored `Play_VO_*` lines
## plays for a guard alertness transition or a player/quest beat.
##
## Pure selector. It owns no player, no tree, no `AudioServer` call and no clip
## load: `AudioManager` feeds it the index `AudioWwise.vo_index()` builds
## (`speaker -> verb -> state -> [line record]`) and plays what `vo_pick`
## returns. Time is an explicit `now_s` parameter, so cooldown behaviour is
## deterministic and testable without waiting.
##
## What is authored vs what is a port decision:
##   * authored — the 645 lines, their `(speaker, verb, state, severity,
##     variant)` and whether a line carries media. The director never invents a
##     speaker, verb, state or line name.
##   * PORT_DECISION — the mapping from a port cue ("SUSPICIOUS>ALERTED",
##     "stash_deposit", ...) to one or more authored triples. Each mapping row
##     names an authored triple; a row whose triple does not exist for the
##     requested speaker is skipped, never rewritten.
##
## Cooldowns / priority contract:
##   * a cooldown is per `(speaker, verb, state)` and starts when that exact
##     triple plays; a different line under the same triple is the same bark and
##     shares the cooldown;
##   * among the eligible candidates of one cue the highest `priority` wins
##     (ties keep the authored list order);
##   * a candidate whose priority is lower than the last played line cannot play
##     within `PRIORITY_HOLD_S`, so a calmer bark cannot step on an alert shout;
##   * variants of one triple rotate round-robin, so a repeated bark is not the
##     same recording twice in a row.
##
## Zero-media refusal: `Play_VO_Enforcer1_0_Silent_Empty_01` is authored silence
## (`media_count == 0`), not a missing join. `vo_pick` refuses it with reason
## `zero_media` even though it exists in the index and has a real event name.
##
## It is NOT a claim that all 645 lines are wired: the suite counts the cues this
## file maps and the authored lines left without a caller are reported.

## Guard alertness transitions -> authored candidate triples, in authored
## preference order. The speaker is supplied by the guard (`Enforcer1` or
## `Hauntstable1`); a candidate the requested speaker never authored is skipped.
##
## Measured authored gap: Hauntstable1 never recorded an `ExertionCombat/
## KnockedOut` row (Enforcer1 has 8), so the five `*>KNOCKED_OUT` transitions
## refuse for a Hauntstable instead of borrowing the Enforcer recording. Suite
## 122 pins that gap by name; it is authored data, not a director defect.
const GUARD_CUES: Dictionary = {
	"NEUTRAL>SUSPICIOUS": [
		{"verb": "ThiefSeen", "state": "VisionStim", "priority": 20, "cooldown_s": 6.0},
	],
	"NEUTRAL>SEARCH": [
		{"verb": "IdleAloneOnPatrol", "state": "Searching", "priority": 15, "cooldown_s": 8.0},
		{"verb": "NoiseHeard", "state": "LowSeverityNoiseSearching", "priority": 10, "cooldown_s": 8.0},
	],
	"SUSPICIOUS>NEUTRAL": [
		{"verb": "ThiefObserved", "state": "LostTargetToPatrol", "priority": 10, "cooldown_s": 10.0},
	],
	"SUSPICIOUS>ALERTED": [
		{"verb": "CallForHelp", "state": "CallForGuards", "priority": 40, "cooldown_s": 8.0},
		{"verb": "ThiefObserved", "state": "ChasingThief", "priority": 30, "cooldown_s": 8.0},
	],
	"SUSPICIOUS>SEARCH": [
		{"verb": "IdleAloneOnPatrol", "state": "Searching", "priority": 15, "cooldown_s": 8.0},
		{"verb": "NoiseHeard", "state": "LowSeverityNoiseSearching", "priority": 10, "cooldown_s": 8.0},
	],
	"ALERTED>COMBAT": [
		{"verb": "ThiefObserved", "state": "ChasingThiefFighting", "priority": 50, "cooldown_s": 8.0},
	],
	"ALERTED>SEARCH": [
		{"verb": "ThiefObserved", "state": "ChasingThiefLostTargetSearching", "priority": 25, "cooldown_s": 8.0},
	],
	"ALERTED>NEUTRAL": [
		{"verb": "ThiefObserved", "state": "LostTargetToPatrol", "priority": 10, "cooldown_s": 10.0},
	],
	"COMBAT>ALERTED": [
		{"verb": "ThiefObserved", "state": "ChasingThief", "priority": 30, "cooldown_s": 8.0},
	],
	"COMBAT>SEARCH": [
		{"verb": "ThiefObserved", "state": "ChasingThiefLostTargetSearching", "priority": 25, "cooldown_s": 8.0},
	],
	"COMBAT>NEUTRAL": [
		{"verb": "ThiefObserved", "state": "LostTargetToPatrol", "priority": 10, "cooldown_s": 10.0},
	],
	"SEARCH>ALERTED": [
		{"verb": "ThiefObserved", "state": "ChasingThiefLostTargetFound", "priority": 35, "cooldown_s": 8.0},
		{"verb": "ThiefObserved", "state": "ChasingThief", "priority": 30, "cooldown_s": 8.0},
	],
	"SEARCH>NEUTRAL": [
		{"verb": "ThiefObserved", "state": "LostTargetToPatrol", "priority": 10, "cooldown_s": 10.0},
	],
	"NEUTRAL>KNOCKED_OUT": [
		{"verb": "ExertionCombat", "state": "KnockedOut", "priority": 60, "cooldown_s": 30.0},
	],
	"SUSPICIOUS>KNOCKED_OUT": [
		{"verb": "ExertionCombat", "state": "KnockedOut", "priority": 60, "cooldown_s": 30.0},
	],
	"SEARCH>KNOCKED_OUT": [
		{"verb": "ExertionCombat", "state": "KnockedOut", "priority": 60, "cooldown_s": 30.0},
	],
	"ALERTED>KNOCKED_OUT": [
		{"verb": "ExertionCombat", "state": "KnockedOut", "priority": 60, "cooldown_s": 30.0},
	],
	"COMBAT>KNOCKED_OUT": [
		{"verb": "ExertionCombat", "state": "KnockedOut", "priority": 60, "cooldown_s": 30.0},
	],
	"KNOCKED_OUT>NEUTRAL": [
		{"verb": "WakingUp", "state": "RevivedSelf", "priority": 15, "cooldown_s": 20.0},
		{"verb": "IdleAloneOnPatrol", "state": "Idle", "priority": 5, "cooldown_s": 20.0},
	],
	"KNOCKED_OUT>ALERTED": [
		{"verb": "ThiefObserved", "state": "ChasingThief", "priority": 30, "cooldown_s": 10.0},
	],
	"KNOCKED_OUT>SUSPICIOUS": [
		{"verb": "ThiefSeen", "state": "VisionStim", "priority": 20, "cooldown_s": 10.0},
	],
}

## Guard exertion/attack barks, keyed by a port beat. The speaker is the guard's
## own authored speaker (`Enforcer1` / `Hauntstable1`), supplied by the caller;
## a speaker that never recorded the triple is skipped, never borrowed.
##
## Phase 3B.3 measured gap: only `Enforcer1` recorded `ExertionCombat/
## TakingDamage` (30) and `ExertionCombat/Attacking` (9); `Hauntstable1` has
## neither, so both beats refuse for a Hauntstable and their two recordings stay
## silent rather than reusing the Enforcer1 set. Suite 122 pins that gap.
##
## `caller` documents the existing port system that owns the beat — these are
## wired because that system already exists, not because a line was looking for
## a home:
##   * taking_damage -> GuardAi.take_knockout(), non-lethal hit only (health > 0)
##   * attacking     -> GuardAi._play_guard_attack(), the melee swing
const GUARD_BEAT_CUES: Dictionary = {
	"taking_damage": [
		{"verb": "ExertionCombat", "state": "TakingDamage", "priority": 55, "cooldown_s": 6.0},
	],
	"attacking": [
		{"verb": "ExertionCombat", "state": "Attacking", "priority": 45, "cooldown_s": 5.0},
	],
}

## Port cue -> authored candidate triples for the player/quest beats. Speaker is
## part of the row because these lines belong to a specific authored character.
## `caller` documents the shipping trigger; `caller: none` is an authored line
## the port has no honest trigger for yet (never silently mapped onto another
## event).
const EVENT_CUES: Dictionary = {
	# caller: LootInventory.carry(), major tier only (port tiers are minor/major).
	"loot_pickup_major": [
		{"speaker": "Player", "verb": "PickupLoot", "state": "Major", "priority": 15, "cooldown_s": 25.0},
	],
	# caller: LootInventory.carry(), quest/contract relic (is_quest_item).
	"match_loot_picked": [
		{"speaker": "TalkingLoot01", "verb": "MatchLootIsPickedUp", "state": "", "priority": 15, "cooldown_s": 60.0},
	],
	# caller: LootInventory.carry(), first non-quest entry of a run.
	"carrying_loot": [
		{"speaker": "TalkingLoot01", "verb": "PlayerIsCarryingLoot", "state": "", "priority": 10, "cooldown_s": 60.0},
	],
	# caller: none — the port has no drop-carried-loot action.
	"loot_dropped": [
		{"speaker": "TalkingLoot01", "verb": "LootIsDropped", "state": "", "priority": 10, "cooldown_s": 60.0},
	],
	# caller: LootStash.deposit_all() success.
	"stash_deposit": [
		{"speaker": "Player", "verb": "StashInteract", "state": "StoringLoot", "priority": 15, "cooldown_s": 20.0},
	],
	# caller: GameState.phase_changed -> endgame.
	"escape_phase": [
		{"speaker": "Player", "verb": "EscapePhaseStarted", "state": "", "priority": 30, "cooldown_s": 30.0},
	],
	# caller: none — the mission begin already plays the authored fairy intro pin
	# (`Play_tristan_fairy_ftue_intro_01`); a second simultaneous line would be a
	# mix change, not a fix. Kept mapped so a future briefing hook can pick it.
	"main_quest_intro": [
		{"speaker": "Player", "verb": "MainQuestIntro", "state": "Generic", "priority": 20, "cooldown_s": 60.0},
	],
	# caller: AudioManager on the disguise_changed signal when integrity hits 0.
	"disguise_ending": [
		{"speaker": "Player", "verb": "DisguiseEnding", "state": "", "priority": 25, "cooldown_s": 30.0},
	],
	# caller: none — no authored new-objective pop-up hook exists yet.
	"new_objective": [
		{"speaker": "FairyTristan", "verb": "PopUp", "state": "NewObjective", "priority": 20, "cooldown_s": 60.0},
	],
	# caller: none — no vault opening interaction path yet.
	"opening_vault": [
		{"speaker": "Player", "verb": "OpeningVault", "state": "", "priority": 20, "cooldown_s": 60.0},
	],
	# caller: none — POI is a level/art term in this port, not a gameplay event.
	"poi_entered": [
		{"speaker": "Player", "verb": "POI", "state": "Entered", "priority": 10, "cooldown_s": 60.0},
	],
	# caller: none — single-player build, no revive action.
	"reviving_teammate": [
		{"speaker": "Player", "verb": "Reviving", "state": "Teammate", "priority": 20, "cooldown_s": 60.0},
	],
	# caller: none — the port's loot tiers are minor/major, not mission/story.
	"pickup_loot_mission": [
		{"speaker": "Player", "verb": "PickupLoot", "state": "Mission", "priority": 15, "cooldown_s": 60.0},
	],
	"pickup_loot_story": [
		{"speaker": "Player", "verb": "PickupLoot", "state": "Story", "priority": 15, "cooldown_s": 60.0},
	],
}

## A lower-priority line is suppressed for this long after a higher-priority one.
const PRIORITY_HOLD_S: float = 2.0

var _index: Dictionary = {}
var _loaded: bool = false
## key "speaker\u001fverb\u001fstate" -> last accepted `now_s`.
var _cooldowns: Dictionary = {}
## key -> next variant offset.
var _rotation: Dictionary = {}
var _last_priority: int = -1
var _last_priority_at: float = -100000.0
var _last_pick: Dictionary = {}
var _picks: int = 0
var _refusals: int = 0
var _zero_media_refusals: int = 0


## Loads the index `AudioWwise.vo_index()` produced. False (and a cleared
## index) when it is empty, so every getter stays neutral on a fresh clone.
func load_index(index: Dictionary) -> bool:
	reset()
	_index = index.duplicate(true)
	_loaded = not _index.is_empty()
	return _loaded


func is_loaded() -> bool:
	return _loaded


## Number of authored lines in the index (645 in the shipped extraction).
func line_count() -> int:
	var total: int = 0
	for speaker: Variant in _index.keys():
		var by_verb: Dictionary = _index[speaker]
		for verb: Variant in by_verb.keys():
			var by_state: Dictionary = by_verb[verb]
			for state: Variant in by_state.keys():
				total += (by_state[state] as Array).size()
	return total


## Number of authored `(speaker, verb, state)` triples (76 shipped).
func triple_count() -> int:
	var total: int = 0
	for speaker: Variant in _index.keys():
		var by_verb: Dictionary = _index[speaker]
		for verb: Variant in by_verb.keys():
			var by_state: Dictionary = by_verb[verb]
			total += by_state.size()
	return total


## Picks the authored line for a guard alertness transition.
## [param previous]/[param next] are the guard state names (`NEUTRAL`,
## `SUSPICIOUS`, `ALERTED`, `COMBAT`, `SEARCH`, `KNOCKED_OUT`).
func vo_pick_transition(previous: String, next: String, speaker: String, now_s: float) -> Dictionary:
	var cue: String = "%s>%s" % [previous.strip_edges().to_upper(), next.strip_edges().to_upper()]
	if not GUARD_CUES.has(cue):
		return _refuse(cue, "unknown_cue", "no authored guard mapping for '%s'" % cue)
	return _pick(cue, GUARD_CUES[cue] as Array, speaker, now_s)


## Picks the authored line for a player/quest cue (see [constant EVENT_CUES]).
func vo_pick_event(cue: String, now_s: float) -> Dictionary:
	var key: String = cue.strip_edges().to_lower()
	if not EVENT_CUES.has(key):
		return _refuse(key, "unknown_cue", "no authored event mapping for '%s'" % key)
	return _pick(key, EVENT_CUES[key] as Array, "", now_s)


## Picks the authored exertion/attack bark for a guard beat (see
## [constant GUARD_BEAT_CUES]). [param speaker] is the guard's authored speaker;
## a beat that speaker never recorded is refused, never borrowed.
func vo_pick_guard_beat(cue: String, speaker: String, now_s: float) -> Dictionary:
	var key: String = cue.strip_edges().to_lower()
	if not GUARD_BEAT_CUES.has(key):
		return _refuse(key, "unknown_cue", "no authored guard beat mapping for '%s'" % key)
	return _pick(key, GUARD_BEAT_CUES[key] as Array, speaker, now_s)


## Generic picker: [param cue] is only for reporting; [param speaker] overrides
## the row's speaker when non-empty. Returns `{ok, event, speaker, verb, state,
## priority, media_count, cue, reason}`; `ok=false` carries a `reason`
## (`index_absent`, `unknown_cue`, `unknown_triple`, `zero_media`, `cooldown`,
## `priority`) and never an invented event.
func vo_pick(cue: String, rows: Array, speaker: String, now_s: float) -> Dictionary:
	return _pick(cue, rows, speaker, now_s)


## Seconds before the exact `(speaker, verb, state)` triple may play again.
func cooldown_remaining(speaker: String, verb: String, state: String, now_s: float, cooldown_s: float) -> float:
	var key: String = _key(speaker, verb, state)
	if not _cooldowns.has(key):
		return 0.0
	var elapsed: float = now_s - float(_cooldowns[key])
	return maxf(0.0, cooldown_s - elapsed)


## Forgets every cooldown, rotation offset and the priority window.
func reset() -> void:
	_index = {}
	_loaded = false
	_cooldowns = {}
	_rotation = {}
	_last_priority = -1
	_last_priority_at = -100000.0
	_last_pick = {}
	_picks = 0
	_refusals = 0
	_zero_media_refusals = 0


## Forgets only the cooldowns, rotation cursors and priority window. The index
## stays loaded, so a scene change or a QA probe can start from a clean slate
## without re-reading the authored document.
func reset_cooldowns() -> void:
	_cooldowns = {}
	_rotation = {}
	_last_priority = -1
	_last_priority_at = -100000.0
	_last_pick = {}


## QA surface: what this director holds and what it refused.
func report() -> Dictionary:
	return {
		"loaded": _loaded,
		"lines": line_count(),
		"triples": triple_count(),
		"guard_cues": GUARD_CUES.size(),
		"guard_beat_cues": GUARD_BEAT_CUES.size(),
		"event_cues": EVENT_CUES.size(),
		"cooldowns": _cooldowns.size(),
		"picks": _picks,
		"refusals": _refusals,
		"zero_media_refusals": _zero_media_refusals,
		"last_pick": _last_pick.duplicate(true),
	}


## Authored line names this director can reach through a mapped cue (every
## candidate row that exists in the index). Used by suite 122 to prove the
## mapping never names a line outside the 645.
func mapped_events() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for cue: Variant in GUARD_CUES.keys():
		for row: Dictionary in (GUARD_CUES[cue] as Array):
			for speaker: String in ["Enforcer1", "Hauntstable1"]:
				for event: String in _rows(speaker, str(row["verb"]), str(row["state"])):
					if not out.has(event):
						out.append(event)
	for cue: Variant in GUARD_BEAT_CUES.keys():
		for row: Dictionary in (GUARD_BEAT_CUES[cue] as Array):
			for speaker: String in ["Enforcer1", "Hauntstable1"]:
				for event: String in _rows(speaker, str(row["verb"]), str(row["state"])):
					if not out.has(event):
						out.append(event)
	for cue: Variant in EVENT_CUES.keys():
		for row: Dictionary in (EVENT_CUES[cue] as Array):
			for event: String in _rows(str(row["speaker"]), str(row["verb"]), str(row["state"])):
				if not out.has(event):
					out.append(event)
	out.sort()
	return out


# =========================================================================
# Internals
# =========================================================================


func _pick(cue: String, rows: Array, speaker_override: String, now_s: float) -> Dictionary:
	if not _loaded:
		return _refuse(cue, "index_absent", "audio_wwise.json VO index is absent")
	var best: Dictionary = {}
	var best_priority: int = -1000000
	var saw_triple: bool = false
	var saw_zero: bool = false
	var saw_cooldown: bool = false
	var saw_priority: bool = false
	for row_v: Variant in rows:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var speaker: String = str(row.get("speaker", "")).strip_edges()
		if not speaker_override.is_empty():
			speaker = speaker_override
		var verb: String = str(row.get("verb", "")).strip_edges()
		var state: String = str(row.get("state", "")).strip_edges()
		var priority: int = int(row.get("priority", 0))
		var cooldown_s: float = float(row.get("cooldown_s", 0.0))
		var events: PackedStringArray = _rows(speaker, verb, state)
		if events.is_empty():
			continue
		saw_triple = true
		# Zero-media lines are authored silence: refused, never played.
		var playable: PackedStringArray = PackedStringArray()
		for event: String in events:
			var media: int = _media_count(speaker, verb, state, event)
			if media <= 0:
				saw_zero = true
				_zero_media_refusals += 1
				continue
			playable.append(event)
		if playable.is_empty():
			continue
		if cooldown_remaining(speaker, verb, state, now_s, cooldown_s) > 0.0:
			saw_cooldown = true
			continue
		if priority < _last_priority and now_s - _last_priority_at < PRIORITY_HOLD_S:
			saw_priority = true
			continue
		if priority > best_priority:
			best_priority = priority
			best = {
				"speaker": speaker,
				"verb": verb,
				"state": state,
				"priority": priority,
				"cooldown_s": cooldown_s,
				"events": playable,
			}
	if best.is_empty():
		if not saw_triple:
			return _refuse(cue, "unknown_triple", "no authored triple exists for '%s'" % cue)
		if saw_cooldown:
			return _refuse(cue, "cooldown", "'%s' is on cooldown" % cue)
		if saw_priority:
			return _refuse(cue, "priority", "'%s' is below the last line's priority" % cue)
		if saw_zero:
			return _refuse(cue, "zero_media", "'%s' resolves only a zero-media authored line" % cue)
		return _refuse(cue, "unknown_triple", "no playable authored line for '%s'" % cue)
	var key: String = _key(str(best["speaker"]), str(best["verb"]), str(best["state"]))
	var events: PackedStringArray = best["events"]
	var offset: int = int(_rotation.get(key, 0)) % events.size()
	var event: String = events[offset]
	_rotation[key] = offset + 1
	_cooldowns[key] = now_s
	_last_priority = int(best["priority"])
	_last_priority_at = now_s
	_picks += 1
	_last_pick = {
		"ok": true,
		"cue": cue,
		"event": event,
		"speaker": str(best["speaker"]),
		"verb": str(best["verb"]),
		"state": str(best["state"]),
		"priority": int(best["priority"]),
		"media_count": _media_count(str(best["speaker"]), str(best["verb"]), str(best["state"]), event),
		"reason": "ok",
	}
	return _last_pick.duplicate(true)


func _refuse(cue: String, reason: String, detail: String) -> Dictionary:
	_refusals += 1
	return {
		"ok": false,
		"cue": cue,
		"event": "",
		"reason": reason,
		"detail": detail,
	}


func _key(speaker: String, verb: String, state: String) -> String:
	return "%s\u001f%s\u001f%s" % [speaker, verb, state]


func _rows(speaker: String, verb: String, state: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var by_verb: Variant = _index.get(speaker, null)
	if not (by_verb is Dictionary):
		return out
	var by_state: Variant = (by_verb as Dictionary).get(verb, null)
	if not (by_state is Dictionary):
		return out
	var rows: Variant = (by_state as Dictionary).get(state, null)
	if not (rows is Array):
		return out
	for record: Variant in (rows as Array):
		if record is Dictionary:
			out.append(str((record as Dictionary).get("event", "")))
	return out


func _media_count(speaker: String, verb: String, state: String, event: String) -> int:
	var by_verb: Variant = _index.get(speaker, null)
	if not (by_verb is Dictionary):
		return -1
	var by_state: Variant = (by_verb as Dictionary).get(verb, null)
	if not (by_state is Dictionary):
		return -1
	var rows: Variant = (by_state as Dictionary).get(state, null)
	if not (rows is Array):
		return -1
	for record: Variant in (rows as Array):
		if record is Dictionary and str((record as Dictionary).get("event", "")) == event:
			return int((record as Dictionary).get("media_count", 0))
	return -1
