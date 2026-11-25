extends RefCounted
## Authored reaction-role caps (RE-I-12), `DT_ReactionEvents`.
##
## Shipped asset: `extracted/json/AI/Data/DT_ReactionEvents.json`, row struct
## `TATAIReactionEventConfig`, 8 rows. The rows that matter to the port:
##   HeavyStim              -> default Standby, Investigator max 2, grace 0.5 s
##   FootstepStim/Landed/   -> Investigator max 2, grace 0.0, Standby unlimited
##     Panting/FootstepStim_Running
##   Phonograph             -> Investigator max 0 (nobody investigates)
##   Combat                 -> default Combat.RangedAttack, Chaser max 1, grace 5.0
##   SawIncorrectObject     -> Fixer max 1
## The port has no roles at all: `_hear` is a broadcast, so one footstep pulls
## every guard in radius (RE-I-12). This module is the registry the listener
## consults before it moves.
##
## SEMANTICS (inference, stated): an "event" is one emitted stimulus, identified
## by `NoiseBus`'s monotonic `event_id`. The authored registration grace is the
## window during which the event stays open for more registrants; after it, a
## late listener gets the default role (Standby for hearing stimuli), which is
## what stops the whole room converging. `MaxRegistrants == 0` on the Standby row
## means "unlimited", matching UE's 0 = no cap convention used on that row.
##
## Deterministic, no RNG: ties are broken by registration order within a frame,
## which is the order the bus delivers. `EQS_ReactionEvaluator_Default` scored
## these in UE; the scoring query is not recoverable, so the port keeps arrival
## order and says so (no invented score).

const ROLE_INVESTIGATOR := "investigator"
const ROLE_STANDBY := "standby"
const ROLE_CHASER := "chaser"
const ROLE_RANGED := "ranged"
const ROLE_NONE := "none"

## Authored caps (DT_ReactionEvents).
const INVESTIGATOR_MAX := 2
const INVESTIGATOR_GRACE_S := 0.5
const LIGHT_INVESTIGATOR_MAX := 2
const LIGHT_INVESTIGATOR_GRACE_S := 0.0
const PHONOGRAPH_INVESTIGATOR_MAX := 0
const CHASER_MAX := 1
const CHASER_GRACE_S := 5.0

## Stimulus tags that route to their own row. Everything else uses the severity
## row (Heavy -> HeavyStim, Light -> light rows).
const STIM_PHONOGRAPH := "AI.Stim.Hearing.Device.Phonograph"

## event_id -> { "key": String, "opened_ms": int, "grace_ms": int,
##               "cap": int, "claims": { listener_id: ms } }
static var _events: Dictionary = {}
## target key -> { "opened_ms": int, "claims": { listener_id: ms } } for Combat.
static var _combat: Dictionary = {}
static var _next_event_id: int = 0
static var _granted_investigator: int = 0
static var _granted_standby: int = 0
static var _granted_chaser: int = 0
static var _granted_ranged: int = 0


## Monotonic stimulus id. `NoiseBus` stamps it on every record; exposed so a
## record built by hand (tests) can share the space.
static func next_event_id() -> int:
	_next_event_id += 1
	return _next_event_id


static func reset() -> void:
	_events.clear()
	_combat.clear()
	_next_event_id = 0
	_granted_investigator = 0
	_granted_standby = 0
	_granted_chaser = 0
	_granted_ranged = 0


## Investigator cap + grace for a stimulus. Heavy rows wait 0.5 s for
## registrants; the four light rows do not; Phonograph caps at 0.
static func investigator_policy(stim_tag: String, severity: String) -> Dictionary:
	if stim_tag == STIM_PHONOGRAPH:
		return {"cap": PHONOGRAPH_INVESTIGATOR_MAX, "grace_s": LIGHT_INVESTIGATOR_GRACE_S}
	if severity.to_lower() == "heavy":
		return {"cap": INVESTIGATOR_MAX, "grace_s": INVESTIGATOR_GRACE_S}
	return {"cap": LIGHT_INVESTIGATOR_MAX, "grace_s": LIGHT_INVESTIGATOR_GRACE_S}


## Register a listener for a hearing stimulus. Returns ROLE_INVESTIGATOR when a
## slot is free (and the event is still open) or ROLE_STANDBY otherwise.
## `now_ms` is a monotonic clock (Time.get_ticks_msec in game, any clock in tests).
static func claim_hearing(event_id: int, stim_tag: String, severity: String, listener_id: int, now_ms: int) -> String:
	var policy: Dictionary = investigator_policy(stim_tag, severity)
	var cap: int = int(policy["cap"])
	var grace_ms: int = int(round(float(policy["grace_s"]) * 1000.0))
	var ev: Dictionary = _events.get(event_id, {}) as Dictionary
	if ev.is_empty():
		ev = {
			"key": stim_tag,
			"opened_ms": now_ms,
			"grace_ms": grace_ms,
			"cap": cap,
			"claims": {},
		}
		_events[event_id] = ev
	var claims: Dictionary = ev["claims"] as Dictionary
	if claims.has(listener_id):
		return ROLE_INVESTIGATOR if claims.size() <= int(ev["cap"]) else ROLE_STANDBY
	var open: bool = now_ms - int(ev["opened_ms"]) <= int(ev["grace_ms"])
	if cap > 0 and claims.size() < cap and open:
		claims[listener_id] = now_ms
		_granted_investigator += 1
		return ROLE_INVESTIGATOR
	_granted_standby += 1
	return ROLE_STANDBY


## Authored combat pair: `DefaultRole = AI.Behavior.Role.Combat.RangedAttack` for
## everyone, plus **one** `AI.Behavior.Role.Combat.Chaser` (max 1, 5 s
## registration grace). The chaser is the exception, not the default: a listener
## asks for it only when it is already inside the authored EQS band minimum
## ("Handle Ranged Attacks and Melee up close"), so the first guard to see you
## from 8 m stays ranged instead of charging. `target_key` identifies the fight
## (the target instance id).
static func claim_combat(target_key: String, listener_id: int, now_ms: int, wants_chaser: bool = false) -> String:
	var ev: Dictionary = _combat.get(target_key, {}) as Dictionary
	if ev.is_empty():
		ev = {"opened_ms": now_ms, "claims": {}}
		_combat[target_key] = ev
	var claims: Dictionary = ev["claims"] as Dictionary
	if not wants_chaser:
		return ROLE_RANGED
	if claims.has(listener_id):
		return ROLE_CHASER
	var open: bool = now_ms - int(ev["opened_ms"]) <= int(round(CHASER_GRACE_S * 1000.0))
	if open and claims.size() < CHASER_MAX:
		claims[listener_id] = now_ms
		_granted_chaser += 1
		return ROLE_CHASER
	_granted_ranged += 1
	return ROLE_RANGED


## Drop expired events so a long session does not grow the registry. A hearing
## event lives for its grace window plus one second of slack (late listeners
## must still read Standby from the same id), a combat event for the chaser
## grace window.
static func prune(now_ms: int) -> void:
	for id: Variant in _events.keys():
		var ev: Dictionary = _events[id] as Dictionary
		if now_ms - int(ev["opened_ms"]) > int(ev["grace_ms"]) + 1000:
			_events.erase(id)
	for key: Variant in _combat.keys():
		var ev: Dictionary = _combat[key] as Dictionary
		if now_ms - int(ev["opened_ms"]) > int(round(CHASER_GRACE_S * 1000.0)) + 1000:
			_combat.erase(key)


static func stats() -> Dictionary:
	return {
		"events": _events.size(),
		"combat_events": _combat.size(),
		"investigators": _granted_investigator,
		"standby": _granted_standby,
		"chasers": _granted_chaser,
		"ranged": _granted_ranged,
		"investigator_max": INVESTIGATOR_MAX,
		"chaser_max": CHASER_MAX,
	}


## Investigators currently registered on an event (tests / diagnostics).
static func claim_count(event_id: int) -> int:
	var ev: Dictionary = _events.get(event_id, {}) as Dictionary
	if ev.is_empty():
		return 0
	return (ev["claims"] as Dictionary).size()


static func combat_claim_count(target_key: String) -> int:
	var ev: Dictionary = _combat.get(target_key, {}) as Dictionary
	if ev.is_empty():
		return 0
	return (ev["claims"] as Dictionary).size()
