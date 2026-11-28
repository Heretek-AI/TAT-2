extends RefCounted
## Authored `StateTreeEvent.*` tags and the port paths that emit them
## (Phase 3B.1).
##
## The payload lists 17 distinct event tags across the 21 trees (a tag is named
## by a state's `required_event_to_enter` or by a transition's `required_event`).
## Before 3B.1 the port emitted none: `guard_bindings.event_matches()` existed
## only for synthetic test events, and `guard_bindings.gd` said so. 3B.1 wires
## exactly one live emitter and this table is the single place that says which:
##
##   * `StateTreeEvent.StimChange` is pushed by `guard_ai._hear()` after a real
##     `NoiseBus` record passes the authored heard-by/query/range/occlusion
##     filters -- i.e. from the existing hearing path, not from a test hook.
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
	STIM_CHANGE: "guard_ai._hear (NoiseBus hearing record, after the heard-by/query/range/occlusion filters)",
}


## Census of authored tags versus live emitters.
## Returns
## {
##   "authored": [tag...]      distinct tags named by any state/transition
##   "emitted": [tag...]       authored tags with a registered emitter
##   "unemitted": [tag...]     authored tags with no emitter
##   "gates": {tag: n}         number of state/transition gates naming the tag
##   "counts": {authored, emitted, unemitted, gates}
##   "emitters": {tag: path}
## }
static func census(trees: Dictionary) -> Dictionary:
	var gates: Dictionary = {}
	for tree_name: Variant in trees.keys():
		var tree: Dictionary = trees[tree_name]
		var states: Array = tree.get("states", [])
		for i: int in range(states.size()):
			var state: Dictionary = states[i]
			var required: Variant = state.get("required_event_to_enter")
			if required is String and str(required) != "":
				gates[str(required)] = int(gates.get(str(required), 0)) + 1
			for tr: Dictionary in state.get("transitions", []):
				var event: Variant = tr.get("required_event")
				if event is String and str(event) != "":
					gates[str(event)] = int(gates.get(str(event), 0)) + 1
	var authored: Array = gates.keys()
	authored.sort()
	var emitted: Array = []
	var unemitted: Array = []
	var gate_total: int = 0
	for tag: Variant in authored:
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
		"counts": {
			"authored": authored.size(),
			"emitted": emitted.size(),
			"unemitted": unemitted.size(),
			"gates": gate_total,
		},
		"emitters": EMITTERS.duplicate(true),
	}
