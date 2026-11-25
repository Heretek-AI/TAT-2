extends RefCounted
## Authored hearing + perception layer (W6G, S1a/S1b).
##
## Single read-through of the producer output:
##   game/data/generated/gameplay/hearing.json     (tools/parse_hearing.py)
##   game/data/generated/gameplay/perception.json  (tools/parse_hearing.py)
##   game/data/generated/gameplay/guard_ai.json    (tools/parse_gameplay.py)
##
## hearing.json carries the 54 authored `TATHearingEventStimSettings` rows:
## UE centimetres under the original property names plus a `metric` mirror in
## metres. Rows are cached once per process and normalised here so no consumer
## has to know the cm/mirror convention:
##   * ranges are metres;
##   * an authored anomaly is clamped into a usable band and counted/logged once
##     (LockPicking.Picked / ShareKnowledge / EnterExitHedge / SecretSwitch
##     author OuterInvestigationRange > MaxRange; Tool.DartLaunch authors
##     InnerInvestigationRange > OuterInvestigationRange). The raw authored
##     values stay in the JSON; this layer is what runtime code reads.
##   * `behaviours` (e.g. AI.Behaviors.Investigate.Long) is reduced to the
##     short/long investigation kind that ST_InvestigateStims_Guard routes to
##     "Short Investigation" / "Long Investigation".
##
## Port emitter tags (NoiseBus) are mapped to authored stims by
## PORT_TAG_TO_STIM. `footstep` is resolved by gait because the port emits one
## tag for crouch/walk/sprint and the shipped data authors two rows
## (Footstep.Walking 4 m, Footstep.Running 20 m). Tags with no honest authored
## counterpart stay on the legacy loudness path and are listed in
## LEGACY_TAGS; that path is unchanged (`min(loudness, HearingRange)`).
##
## Weather/perception: perception.json authors the shared-config range
## modifiers (Status.Nervous 1.2, Weather.SoundCarry High 1.0 / Mid 0.9 /
## Low 0.8 / High_Extra 1.25) and hearing.json joins every weather type to a
## SoundCarry tag + multiplier. Both are exposed here as multipliers; the
## listener applies them once (see guard_ai.hearing_sense_multiplier).
##
## The 285 authored acoustic portals are exposed read-only here; the runtime
## occlusion consumer is `game/src/ai/hearing_occlusion.gd` (W8): a segment that
## crosses world geometry is heard only through a portal box with no closed
## swinging door in it. No attenuation value is recoverable from the dump, so the
## rule is binary (see RE-I-05).
##
## Everything fails closed on a missing/corrupt table: an unknown stim resolves
## to {}, an unknown weather tag to 1.0, an unknown surface to 1.0. No value is
## invented; the metres fallback only mirrors the authored cm field.

const HEARING_PATH := "res://data/generated/gameplay/hearing.json"
const PERCEPTION_PATH := "res://data/generated/gameplay/perception.json"
const GUARD_AI_PATH := "res://data/generated/gameplay/guard_ai.json"

## AIC_GuardBase TATAISenseConfig_Hearing.HearingRange 2500 cm. Used as the
## sense ceiling (the authored stim MaxRange is capped by it) and as the legacy
## fallback radius when a tag has no authored stim.
const DEFAULT_SENSE_RANGE_M := 25.0

const FACTION_HOSTILES := "hostiles"
const FACTION_NEUTRALS := "neutrals"
const FACTION_FRIENDLIES := "friendlies"

const BEHAVIOUR_SHORT := "short"
const BEHAVIOUR_LONG := "long"

const SENSE_HEARING := "hearing"
const SENSE_VISION_GUARD := "vision_guard"

## Port emitter tag -> authored stim tag. Only entries the shipped rows support
## semantically are listed; the authored range replaces the emitter's hand
## tuned metre value for these tags.
##   takedown          player blackjack takedown          -> Takedown 2.5 m
##   bottle            thrown-bottle impact (APPROX 10 m) -> ImpactGeo 10 m
##   door/lock         door swing / lock mechanism        -> OpeningCreak 5 m
##   lockpick          working pick tick                  -> LockPicking.Picked 3 m
##   lockpick_jammed   pick failure / jam                 -> LockPicking.Jammed 10 m
##   noise_alarm       BP_Trap_Action_NoiseAlarm_C        -> Trap.NoiseAlarm 15 m
##   footstep          gait resolved below                -> Footstep.Walking/Running
## W8 additions (RE-I-05: 8 of 54 rows were reachable):
##   combat_hit        a landed non-lethal hit (guard ranged / chaser melee)
##                                                        -> Combat.Hit 10 m Heavy Long
##   npc_yelp          civilian sees the thief            -> NPC.Yelp 25 m Heavy Long
##   npc_call_help     civilian flees calling for help    -> NPC.CallForHelp 30 m Heavy Long
## A blackjack is NOT a Combat.Hit: the shipped takedown is a synced ability with
## its own Takedown stim, and a one-shot KO would otherwise be heard at 10 m.
const PORT_TAG_TO_STIM: Dictionary = {
	"takedown": "AI.Stim.Hearing.Takedown",
	"bottle": "AI.Stim.Hearing.ImpactGeo",
	"door": "AI.Stim.Hearing.OpeningCreak",
	"lock": "AI.Stim.Hearing.OpeningCreak",
	"lockpick": "AI.Stim.Hearing.LockPicking.Picked",
	"lockpick_jammed": "AI.Stim.Hearing.LockPicking.Jammed",
	"noise_alarm": "AI.Stim.Hearing.Trap.NoiseAlarm",
	"combat_hit": "AI.Stim.Hearing.Combat.Hit",
	"npc_yelp": "AI.Stim.Hearing.NPC.Yelp",
	"npc_call_help": "AI.Stim.Hearing.NPC.CallForHelp",
}

## One port tag, two authored rows. Crouch has no authored row of its own, so it
## uses Walking (the quietest authored footstep) rather than silencing it here:
## the surface loudness multiplier still zeroes it on carpet/grass/dirt.
const FOOTSTEP_STIM_BY_GAIT: Dictionary = {
	"crouch": "AI.Stim.Hearing.Footstep.Walking",
	"walk": "AI.Stim.Hearing.Footstep.Walking",
	"run": "AI.Stim.Hearing.Footstep.Running",
}

## Deliberately legacy (emitter loudness capped by the sense range). Each is a
## port-only event with no semantically honest authored row, or one whose
## authored range would change tuned behaviour far beyond the data's intent:
##   guard_alert         VO shout / alarm eye. The emitter authors its own range
##                       (guard 12-14 m, alarm eye 25 m); using NPC.CallForHelp
##                       (30 m) would widen every shout and cascade alerts.
##   smoke/wire/fairy    tool and traversal effects, no authored hearing row.
##   pickpocket*          port-only interaction feedback.
##   slithersap/disguise/clue/generic  port-only feedback tags.
const LEGACY_TAGS: Array[String] = [
	"guard_alert",
	"smoke",
	"wire",
	"slithersap",
	"fairy",
	"disguise",
	"pickpocket",
	"pickpocket_spotted",
	"clue",
	"generic",
]

## GameData.get_surface_loudness aliases the seven AudioManager surface tokens
## to authored physical rows; mirrored here so this layer and GameData agree.
const SURFACE_TOKEN_ALIASES: Dictionary = {
	"wood": "woodfloor",
	"metal": "metalthick",
	"wet": "puddle",
	"earth": "dirt",
}

static var _hearing: Dictionary = {}
static var _perception: Dictionary = {}
static var _guard_ai: Dictionary = {}
static var _stimuli: Dictionary = {} # authored tag -> normalised row
static var _stimuli_lower: Dictionary = {} # lower(authored tag) -> tag
static var _surfaces: Dictionary = {} # lower(surface) -> multiplier
static var _anomalies: Array[String] = []
static var _loaded: bool = false
static var _anomaly_logged: bool = false


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


static func reload_cache() -> void:
	_hearing = {}
	_perception = {}
	_guard_ai = {}
	_stimuli = {}
	_stimuli_lower = {}
	_surfaces = {}
	_anomalies = []
	_loaded = false
	_anomaly_logged = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var hearing_v: Variant = _read_json(HEARING_PATH)
	if hearing_v is Dictionary:
		_hearing = hearing_v as Dictionary
	else:
		push_warning("[hearing_data] hearing.json missing/corrupt at " + HEARING_PATH + "; authored hearing is unavailable (legacy loudness fallback)")
	var perception_v: Variant = _read_json(PERCEPTION_PATH)
	if perception_v is Dictionary:
		_perception = perception_v as Dictionary
	else:
		push_warning("[hearing_data] perception.json missing/corrupt at " + PERCEPTION_PATH + "; range modifiers fail closed to 1.0")
	var guard_v: Variant = _read_json(GUARD_AI_PATH)
	if guard_v is Dictionary:
		_guard_ai = guard_v as Dictionary
	_build_stimuli()


static func _metres(metric: Dictionary, metric_key: String, row: Dictionary, cm_key: String) -> float:
	if metric.get(metric_key) != null:
		return float(metric[metric_key])
	return float(row.get(cm_key, 0.0)) / 100.0


static func _build_stimuli() -> void:
	_stimuli = {}
	_stimuli_lower = {}
	_anomalies = []
	_surfaces = {}
	var rows_v: Variant = _hearing.get("stimuli", [])
	if not (rows_v is Array):
		return
	for row_v: Variant in (rows_v as Array):
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		var tag: String = str(row.get("tag", ""))
		if tag == "":
			continue
		var metric_v: Variant = row.get("metric", {})
		var metric: Dictionary = metric_v as Dictionary if metric_v is Dictionary else {}
		var max_m: float = maxf(0.0, _metres(metric, "max_range_m", row, "max_range_cm"))
		var inner_m: float = maxf(0.0, _metres(metric, "inner_investigation_range_m", row, "inner_investigation_range_cm"))
		var outer_m: float = maxf(0.0, _metres(metric, "outer_investigation_range_m", row, "outer_investigation_range_cm"))
		var raw_inner: float = inner_m
		var raw_outer: float = outer_m
		if inner_m > max_m:
			_anomalies.append("%s: inner %s m > max %s m (clamped)" % [tag, str(snappedf(inner_m, 0.0001)), str(snappedf(max_m, 0.0001))])
			inner_m = max_m
		if outer_m > max_m:
			_anomalies.append("%s: outer %s m > max %s m (clamped)" % [tag, str(snappedf(outer_m, 0.0001)), str(snappedf(max_m, 0.0001))])
			outer_m = max_m
		if inner_m > outer_m:
			_anomalies.append("%s: inner %s m > outer %s m (clamped)" % [tag, str(snappedf(inner_m, 0.0001)), str(snappedf(outer_m, 0.0001))])
			outer_m = inner_m
		var behaviours_v: Variant = row.get("behaviors", [])
		var behaviours: Array[String] = []
		var behaviour: String = BEHAVIOUR_SHORT
		if behaviours_v is Array:
			for b_v: Variant in (behaviours_v as Array):
				var b: String = str(b_v)
				if b == "":
					continue
				behaviours.append(b)
				if b.to_lower().find("investigate.long") >= 0:
					behaviour = BEHAVIOUR_LONG
		var heard_v: Variant = row.get("heard_by", {})
		var heard_raw: Dictionary = heard_v as Dictionary if heard_v is Dictionary else {}
		var heard: Dictionary = {
			FACTION_HOSTILES: heard_raw.get(FACTION_HOSTILES, false) == true,
			FACTION_NEUTRALS: heard_raw.get(FACTION_NEUTRALS, false) == true,
			FACTION_FRIENDLIES: heard_raw.get(FACTION_FRIENDLIES, false) == true,
		}
		_stimuli[tag] = {
			"tag": tag,
			"short": tag.replace("AI.Stim.Hearing.", ""),
			"severity": str(row.get("severity", "")),
			"propagation": str(row.get("propagation", "")),
			"max_range_m": max_m,
			"inner_range_m": inner_m,
			"outer_range_m": outer_m,
			"authored_inner_range_m": raw_inner,
			"authored_outer_range_m": raw_outer,
			"behaviour": behaviour,
			"behaviours": behaviours,
			"query_bitmask": int(row.get("query_bitmask", 127)),
			"heard_by": heard,
		}
		_stimuli_lower[tag.to_lower()] = tag
	var loud_v: Variant = _hearing.get("loudness_modifiers", {})
	if loud_v is Dictionary:
		var by_surface_v: Variant = (loud_v as Dictionary).get("by_surface", {})
		if by_surface_v is Dictionary:
			for k: Variant in (by_surface_v as Dictionary).keys():
				var entry_v: Variant = (by_surface_v as Dictionary)[k]
				if entry_v is Dictionary:
					_surfaces[str(k).to_lower()] = float((entry_v as Dictionary).get("multiplier", 1.0))
	_log_anomalies_once()


## Loud, one-line anomaly report. The per-row detail is in anomalies().
static func _log_anomalies_once() -> void:
	if _anomaly_logged or _anomalies.is_empty():
		return
	_anomaly_logged = true
	push_warning("[hearing_data] " + str(_anomalies.size()) + " authored investigation-range anomalies clamped: " + "; ".join(_anomalies))


static func anomalies() -> Array[String]:
	ensure_loaded()
	return _anomalies.duplicate()


static func stats() -> Dictionary:
	ensure_loaded()
	var out: Dictionary = {}
	var stats_v: Variant = _hearing.get("stats", {})
	if stats_v is Dictionary:
		out = (stats_v as Dictionary).duplicate(true)
	out["clamped_anomalies"] = _anomalies.size()
	out["loaded_stimuli"] = _stimuli.size()
	return out


static func hearing_stats_raw() -> Dictionary:
	ensure_loaded()
	var stats_v: Variant = _hearing.get("stats", {})
	return (stats_v as Dictionary).duplicate(true) if stats_v is Dictionary else {}


static func stim_count() -> int:
	ensure_loaded()
	return _stimuli.size()


## Authored stim row, normalised to metres. `tag` may be the full authored tag or
## its short form (Combat.Block). Unknown -> {}.
static func stim(tag: String) -> Dictionary:
	ensure_loaded()
	var key: String = tag.strip_edges()
	if key == "":
		return {}
	if _stimuli.has(key):
		return (_stimuli[key] as Dictionary).duplicate(true)
	var lower: String = key.to_lower()
	if _stimuli_lower.has(lower):
		return (_stimuli[_stimuli_lower[lower]] as Dictionary).duplicate(true)
	if _stimuli.has("AI.Stim.Hearing." + key):
		return (_stimuli["AI.Stim.Hearing." + key] as Dictionary).duplicate(true)
	return {}


static func has_stim(tag: String) -> bool:
	return not stim(tag).is_empty()


## Port emitter tag -> authored stim tag ("" when the tag stays on the legacy
## loudness path). Accepts the authored tag itself and the short form.
static func resolve_port_tag(tag: String) -> String:
	ensure_loaded()
	var key: String = tag.strip_edges()
	if key == "":
		return ""
	if _stimuli.has(key) or _stimuli_lower.has(key.to_lower()) or _stimuli.has("AI.Stim.Hearing." + key):
		return str(stim(key).get("tag", ""))
	if PORT_TAG_TO_STIM.has(key.to_lower()):
		return str(PORT_TAG_TO_STIM[key.to_lower()])
	return ""


## Resolved, normalised stim for an emitter tag. `gait` only matters for the
## footstep tag ("crouch" / "walk" / "run"; "" falls back to walk). Returns {}
## when the tag is legacy or unknown.
static func resolve_stim(tag: String, gait: String = "") -> Dictionary:
	ensure_loaded()
	var key: String = tag.strip_edges().to_lower()
	if key == "footstep":
		var gait_key: String = gait.strip_edges().to_lower()
		var stim_tag: String = str(FOOTSTEP_STIM_BY_GAIT.get(gait_key, FOOTSTEP_STIM_BY_GAIT["walk"]))
		return stim(stim_tag)
	var resolved: String = resolve_port_tag(tag)
	if resolved == "":
		return {}
	return stim(resolved)


static func max_range_m(tag: String, gait: String = "") -> float:
	var row: Dictionary = resolve_stim(tag, gait)
	return float(row.get("max_range_m", 0.0))


static func inner_range_m(tag: String, gait: String = "") -> float:
	var row: Dictionary = resolve_stim(tag, gait)
	return float(row.get("inner_range_m", 0.0))


static func outer_range_m(tag: String, gait: String = "") -> float:
	var row: Dictionary = resolve_stim(tag, gait)
	return float(row.get("outer_range_m", 0.0))


static func severity(tag: String, gait: String = "") -> String:
	return str(resolve_stim(tag, gait).get("severity", ""))


## "short" / "long" investigation kind (ST_InvestigateStims_Guard routes these
## to the Short/Long Investigation subtree states).
static func behaviour(tag: String, gait: String = "") -> String:
	return str(resolve_stim(tag, gait).get("behaviour", BEHAVIOUR_SHORT))


## Authored heard-by flag for a faction. Unknown stim/faction -> false.
static func heard_by(stim_or_tag: Variant, faction: String) -> bool:
	var row: Dictionary = {}
	if stim_or_tag is Dictionary:
		row = stim_or_tag as Dictionary
	else:
		row = stim(str(stim_or_tag))
	var flags_v: Variant = row.get("heard_by", {})
	if not (flags_v is Dictionary):
		return false
	return (flags_v as Dictionary).get(faction, false) == true


## Stimulus query bitmask gate. The authored bit meanings are not recovered, so
## the listener supplies its accepted mask (guards accept 127 = all). A stim is
## accepted when it shares at least one bit with the listener mask.
static func accepts_query(stim_or_row: Variant, listener_mask: int) -> bool:
	var row: Dictionary = stim_or_row as Dictionary if stim_or_row is Dictionary else stim(str(stim_or_row))
	if row.is_empty():
		return false
	var bitmask: int = int(row.get("query_bitmask", 127))
	return (bitmask & listener_mask) != 0


## Authored investigation target. Within the authored OuterInvestigationRange
## the stimulus location itself is investigated; farther away the guard walks to
## the midpoint of the authored Inner..Outer band on its own side of the sound.
## The 50 % point keeps the target deterministic (no RNG) and inside the authored
## band. This is an inference from the property names: the shipped state tree
## moves to the stim location and then runs EQS for nearby locations, it does not
## expose the runtime pick.
static func investigation_point(stim_or_row: Variant, origin: Vector3, listener: Vector3) -> Vector3:
	var row: Dictionary = stim_or_row as Dictionary if stim_or_row is Dictionary else stim(str(stim_or_row))
	var inner_m: float = float(row.get("inner_range_m", 0.0))
	var outer_m: float = float(row.get("outer_range_m", inner_m))
	var to_listener: Vector3 = listener - origin
	var dist: float = to_listener.length()
	if dist <= 0.001:
		return origin
	if dist <= outer_m:
		return origin
	var band_mid: float = clampf((inner_m + outer_m) * 0.5, 0.0, dist)
	return origin + to_listener / dist * band_mid


## Legacy radius for a tag with no authored row: the emitter's loudness capped by
## the authored sense range. This is the port contract the authored path
## replaces, kept for the LEGACY_TAGS list.
static func unknown_fallback_range(loudness_m: float, sense_range_m: float) -> float:
	return minf(maxf(loudness_m, 0.0), maxf(sense_range_m, 0.0))


# --- Shared perception config (perception.json) ------------------------------


static func perception_modifiers(sense: String) -> Array:
	ensure_loaded()
	var senses_v: Variant = _perception.get("senses", {})
	if not (senses_v is Dictionary):
		return []
	var sense_v: Variant = (senses_v as Dictionary).get(sense, {})
	if not (sense_v is Dictionary):
		return []
	var mods_v: Variant = (sense_v as Dictionary).get("range_modifiers", [])
	return (mods_v as Array).duplicate(true) if mods_v is Array else []


## Product of every authored range modifier whose gameplay tag is active.
## Unknown sense/tags -> 1.0 (never a guessed multiplier).
static func perception_range_multiplier(sense: String, active_tags: Array) -> float:
	if active_tags.is_empty():
		return 1.0
	var mult: float = 1.0
	for row_v: Variant in perception_modifiers(sense):
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		if active_tags.has(str(row.get("tag", ""))):
			mult *= float(row.get("range_multiplier", 1.0))
	return maxf(0.0, mult)


## Authored Drowsy/Asleep vision range modifier (0.1). The port maps
## Alertness.KNOCKED_OUT to the escalation Drowsy row, so this is the one place
## that modifier applies.
const DROWSY_VISION_TAG := "AI.Status.Escalation.Drowsy.Asleep"


static func drowsy_vision_multiplier() -> float:
	return perception_range_multiplier(SENSE_VISION_GUARD, [DROWSY_VISION_TAG])


# --- Weather sound carry -----------------------------------------------------


static func weather_sound_carry_row(weather_tag: String, indoors: bool) -> Dictionary:
	ensure_loaded()
	var table_v: Variant = _hearing.get("weather_sound_carry", {})
	if not (table_v is Dictionary):
		return {}
	var row_v: Variant = (table_v as Dictionary).get(weather_tag, {})
	if not (row_v is Dictionary):
		return {}
	var side_v: Variant = (row_v as Dictionary).get("indoors" if indoors else "outdoors", {})
	return (side_v as Dictionary).duplicate(true) if side_v is Dictionary else {}


static func weather_sound_carry_multiplier(weather_tag: String, indoors: bool) -> float:
	var row: Dictionary = weather_sound_carry_row(weather_tag, indoors)
	if row.is_empty():
		return 1.0
	return maxf(0.0, float(row.get("range_multiplier", 1.0)))


static func weather_types() -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	var table_v: Variant = _hearing.get("weather_sound_carry", {})
	if table_v is Dictionary:
		for k: Variant in (table_v as Dictionary).keys():
			out.append(str(k))
	return out


# --- Surfaces ----------------------------------------------------------------


## DA_LoudnessModifiers multiplier for a physical surface. Accepts the authored
## name (Carpet, MetalThick, ...) and the seven AudioManager tokens via the same
## aliases GameData uses. "" / unknown -> 1.0.
static func surface_loudness(surface: String) -> float:
	ensure_loaded()
	var key: String = surface.strip_edges().split("/")[-1].split(".")[-1].to_lower()
	if key == "":
		return 1.0
	if _surfaces.has(key):
		return float(_surfaces[key])
	var alias: String = str(SURFACE_TOKEN_ALIASES.get(key, ""))
	if alias != "" and _surfaces.has(alias):
		return float(_surfaces[alias])
	return 1.0


## hearing.json and guard_ai.json are produced from the same
## DA_LoudnessModifiers asset by two producers. True when all 22 rows match.
static func surface_parity() -> bool:
	ensure_loaded()
	var other_v: Variant = _read_json(GUARD_AI_PATH)
	if not (other_v is Dictionary):
		return false
	var rows_v: Variant = (other_v as Dictionary).get("surface_loudness", {})
	if not (rows_v is Dictionary):
		return false
	var rows: Dictionary = rows_v as Dictionary
	if rows.size() != _surfaces.size():
		return false
	for k: Variant in rows.keys():
		var key: String = str(k).to_lower()
		if not _surfaces.has(key):
			return false
		if not is_equal_approx(float(_surfaces[key]), float(rows[k])):
			return false
	return true


# --- Acoustic portals (W6.3 runtime layer deferred) --------------------------


static func acoustic_portal_count() -> int:
	ensure_loaded()
	var portals_v: Variant = _hearing.get("acoustic_portals", {})
	if not (portals_v is Dictionary):
		return 0
	return int((portals_v as Dictionary).get("count", 0))


## Read-only authored portal rows (Godot metres + column-major basis + box
## scale). No occlusion behaviour is derived from them in W6G.
static func acoustic_portals() -> Array:
	ensure_loaded()
	var portals_v: Variant = _hearing.get("acoustic_portals", {})
	if not (portals_v is Dictionary):
		return []
	var rows_v: Variant = (portals_v as Dictionary).get("portals", [])
	return (rows_v as Array).duplicate(true) if rows_v is Array else []


## Every stim tag this build can actually reach, given the tags the port emits.
## RE-I-15 corrected `docs/FIDELITY_GAPS.md`'s "all 54 authored hearing stims are
## wired": the registry holds all 54 rows, but a row is reachable only when an
## emitter in `game/src` produces a tag that resolves to it. This function makes
## that measurable instead of a claim, and `test_ai_perception.gd` pins the count
## so a new emitter (or a lost one) is a gate result, not a doc drift.
static func reachable_stim_tags(emitter_tags: Array) -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	for tag_v: Variant in emitter_tags:
		var tag: String = str(tag_v)
		if tag.strip_edges() == "":
			continue
		if tag.to_lower() == "footstep":
			# One emitter tag, one authored row per gait (Walking / Running).
			for gait: Variant in FOOTSTEP_STIM_BY_GAIT.keys():
				var gait_row: Dictionary = resolve_stim(tag, str(gait))
				var gait_tag: String = str(gait_row.get("tag", ""))
				if gait_tag != "" and not out.has(gait_tag):
					out.append(gait_tag)
			continue
		var row: Dictionary = resolve_stim(tag)
		var authored: String = str(row.get("tag", ""))
		if authored != "" and not out.has(authored):
			out.append(authored)
	out.sort()
	return out


## Authored rows with no reachable emitter (the complement of the above).
static func unreachable_stim_tags(emitter_tags: Array) -> Array[String]:
	ensure_loaded()
	var reachable: Array[String] = reachable_stim_tags(emitter_tags)
	var out: Array[String] = []
	for tag: Variant in _stimuli.keys():
		if not reachable.has(str(tag)):
			out.append(str(tag))
	out.sort()
	return out


## Escalation rows authored in guard_ai.json (`escalation_tables`). Kept here so
## the guard and the hearing tests read the same source. Unknown profile/state ->
## {}.
static func escalation_row(profile: String, state_name: String) -> Dictionary:
	ensure_loaded()
	var tables_v: Variant = _guard_ai.get("escalation_tables", {})
	if not (tables_v is Dictionary):
		return {}
	var profile_v: Variant = (tables_v as Dictionary).get(profile, {})
	if not (profile_v is Dictionary):
		return {}
	var row_v: Variant = (profile_v as Dictionary).get(state_name, {})
	return (row_v as Dictionary).duplicate(true) if row_v is Dictionary else {}


static func guard_ai_value(key: String, fallback: Variant) -> Variant:
	ensure_loaded()
	return _guard_ai.get(key, fallback)
