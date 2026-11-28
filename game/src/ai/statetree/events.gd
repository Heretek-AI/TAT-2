extends RefCounted
## Authored `StateTreeEvent.*` tags and the port paths that emit them
## (Phase 3B.1, census corrected in round 2).
##
## The payload lists 17 distinct event tags across the 21 trees. A tag reaches a
## node through TWO different shapes, and both must be counted:
##   * a transition's `required_event` is a plain tag String (89 gates);
##   * a state's `required_event_to_enter` is `{tag, payload_struct}` in payload
##     /2 (`TreeModel._normalise_required_event`, tree_model.gd), 3 enabled
##     state-entry gates -- `ST_InvestigateStims_Guard` and `ST_Subtree_Combat`
##     `Extract Reaction Role from Event` (ReactionRoleChange) and `ST_Patrol`
##     `Extract distraction Event` (DistractionEvent).
## Round 1 counted only the String shape and reported 89; the measured census is
## 92 (89 transition + 3 enter). `_event_tag()` reads both shapes.
##
## Before 3B.1 the port emitted none: `guard_bindings.event_matches()` existed
## only for synthetic test events, and `guard_bindings.gd` said so. 3B.1 wires
## exactly one live emitter and this table is the single place that says which:
##
##   * `StateTreeEvent.StimChange` is pushed by `guard_ai._hear()` after a real
##     `NoiseBus` record passes the authored heard-by/query/range/occlusion
##     filters -- i.e. from the existing hearing path, not from a test hook.
##     This mapping is a PORT INFERENCE, not authored data: the cook serialises
##     the tag name only (a `payload_struct` exists for the enter gates but no
##     value bytes), and nothing in the payload says "a heard record is a
##     StimChange". The inference is that an accepted hearing record is a
##     stimulus change for the listener; every other tag stays unemitted.
##
## Nothing else is claimed. A tag with no entry here is UNEMITTED: the port has
## no event bus for it, so the authored branch that listens for it is
## unreachable. This function measures that list from the payload instead of
## restating it in prose, so a new emitter that is not registered here (or a
## producer that adds a tag) moves the census.
##
## NO PARAMETERS ARE INVENTED. The payload serialises only the tag name; the
## `payload` dictionary a live emitter attaches is trace metadata copied from
## the record that already reached the listener (`heard_tag`, `stim_tag`), not a
## bound StateTree parameter bag.

## The one live emitter: `guard_ai._hear()` (NoiseBus `noise_record_emitted`).
const STIM_CHANGE: String = "StateTreeEvent.StimChange"

## tag -> the live port path that pushes it. One entry per measured emitter.
const EMITTERS: Dictionary = {
	STIM_CHANGE: "guard_ai._hear (NoiseBus hearing record, after the heard-by/query/range/occlusion filters) -- PORT INFERENCE, see the header",
}


## The tag behind either payload shape, or "" when the gate is absent.
##   * String              -> the tag (a transition's `required_event`, payload v1)
##   * {tag, payload_struct} -> `tag` (a state's `required_event_to_enter`, /2)
static func _event_tag(raw: Variant) -> String:
	if raw is String:
		return str(raw).strip_edges()
	if raw is Dictionary:
		return str((raw as Dictionary).get("tag", "")).strip_edges()
	return ""


## Census of authored tags versus live emitters.
## Returns
## {
##   "authored": [tag...]      distinct tags named by any state/transition
##   "emitted": [tag...]       authored tags with a registered emitter
##   "unemitted": [tag...]     authored tags with no emitter
##   "gates": {tag: n}         all gates naming the tag (enter + transition)
##   "enter": {tag: n}         state `required_event_to_enter` gates
##   "transition": {tag: n}    transition `required_event` gates
##   "counts": {authored, emitted, unemitted, enter, transition, gates, total}
##   "emitters": {tag: path}
## }
static func census(trees: Dictionary) -> Dictionary:
	var enter: Dictionary = {}
	var transition: Dictionary = {}
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		var states: Array = tree.get("states", [])
		for i: int in range(states.size()):
			var state: Dictionary = states[i]
			# Payload /2 stores this as {tag, payload_struct}; a v1 payload or a
			# synthetic tree may still carry a bare String. Count both.
			var enter_tag: String = _event_tag(state.get("required_event_to_enter"))
			if enter_tag != "":
				enter[enter_tag] = int(enter.get(enter_tag, 0)) + 1
			for tr: Dictionary in state.get("transitions", []):
				var transition_tag: String = _event_tag(tr.get("required_event"))
				if transition_tag != "":
					transition[transition_tag] = int(transition.get(transition_tag, 0)) + 1
	# The union of the two shapes is what a gate census means.
	var gates: Dictionary = enter.duplicate()
	for tag: Variant in transition.keys():
		gates[tag] = int(gates.get(tag, 0)) + int(transition[tag])
	var authored: Array = gates.keys()
	authored.sort()
	var emitted: Array = []
	var unemitted: Array = []
	var enter_total: int = 0
	var transition_total: int = 0
	var gate_total: int = 0
	for tag: Variant in authored:
		enter_total += int(enter.get(tag, 0))
		transition_total += int(transition.get(tag, 0))
		gate_total += int(gates[tag])
		if EMITTERS.has(str(tag)):
			emitted.append(str(tag))
		else:
			unemitted.append(str(tag))
	return {
		"authored": authored,
		"emitted": emitted,
		"unemitted": unemitted,
		"gates": gates,
		"enter": enter,
		"transition": transition,
		"counts": {
			"authored": authored.size(),
			"emitted": emitted.size(),
			"unemitted": unemitted.size(),
			"enter": enter_total,
			"transition": transition_total,
			"gates": gate_total,
			"total": enter_total + transition_total,
		},
		"emitters": EMITTERS.duplicate(true),
	}
