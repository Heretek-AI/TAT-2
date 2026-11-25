extends Node
## Global acoustic stimulus bus connecting player/gadget noises to AI hearing.
## AudioManager mirrors these stimuli as 3D positional audio on the SFX bus;
## guard VO and footstep variation are layered there (PG-6 full audio runtime).
##
## Footstep-surface loudness (AU3 + DA_LoudnessModifiers). The surface now
## travels with an emitted noise: emit_noise(..., surface) multiplies the
## emitted loudness by GameData.get_surface_loudness(surface) from the authored
## AI/Data/DA_LoudnessModifiers table (Carpet/Foliage/Dirt 0.0, Glass/Stone/
## Metal 1.5, ...). Listeners (guards, HUD arcs) receive the already-modified
## value, so nobody applies the multiplier twice. Existing callers without a
## surface keep 1.0 (unmodified). is_known_surface() lets emitters fail loud on
## typos instead of silently falling back to the "wood" default pool.
##
## W6G authored hearing (S1a): every emission also produces a record carrying
## the resolved stim row from hearing.json (see src/ai/hearing_data.gd):
## authored MaxRange / Inner-Outer investigation ranges, severity, short/long
## behaviour, heard-by flags, query bitmask and the surface multiplier as its own
## field. `noise_emitted` keeps its exact 4-argument contract and its loudness
## value so existing listeners (AudioManager, HUD arcs, tests) are unchanged;
## `noise_record_emitted` is the richer signal AI hearing consumes. Tags with no
## honest authored row (guard_alert, smoke, ...; see HearingData.LEGACY_TAGS)
## resolve to an empty stim and stay on the legacy loudness path.

const HearingData: GDScript = preload("res://src/ai/hearing_data.gd")

signal noise_emitted(origin: Vector3, loudness_meters: float, source: Node, tag: String)
## W6G rich emission. Keys:
##   origin: Vector3, base_loudness_m: float, loudness_m: float (final, surface
##   modified), source: Node, tag: String (emitter tag, unchanged), gait: String,
##   surface: String, surface_multiplier: float, stim_tag: String,
##   stim: Dictionary (normalised authored row or {}).
signal noise_record_emitted(record: Dictionary)

## AU3 footstep surfaces. Emitters pass one of these; AudioManager falls back
## to "wood" (Den interiors) when the surface is unknown.
const SURFACE_WOOD: String = "wood"
const SURFACE_STONE: String = "stone"
const SURFACE_CARPET: String = "carpet"
const SURFACE_METAL: String = "metal"
const SURFACE_WET: String = "wet"
const SURFACE_EARTH: String = "earth"
const SURFACE_GLASS: String = "glass"
const SURFACES: Array[String] = ["wood", "stone", "carpet", "metal", "wet", "earth", "glass"]

## The port emits one "footstep" tag at three gaits (crouch 1.5 m / walk 3.5 m /
## sprint 8.0 m; thief_character.gd). The shipped table authors two rows, so the
## gait is resolved from the emitter (flags when present) and from the mentioned
## loudness as a fallback for callers that pass no node.
const FOOTSTEP_SPRINT_MIN_M: float = 6.0
const FOOTSTEP_CROUCH_MAX_M: float = 2.0

## W8: every record carries a monotonic `event_id` so listeners can tell "the
## same stimulus" from "another footstep" and share the authored reaction-role
## caps (AI.Stim.Hearing.* registrations, DT_ReactionEvents). The counter lives
## here (not in the AI) so a record built by a test and a record emitted by the
## bus share one id space.
static var _event_counter: int = 0


static func reset_event_counter() -> void:
	_event_counter = 0


static func next_event_id() -> int:
	_event_counter += 1
	return _event_counter


static func is_known_surface(surface: String) -> bool:
	return SURFACES.has(surface.to_lower().strip_edges())


## Gait of an emitter for the footstep stim lookup. Source flags win; otherwise
## the port's authored footstep loudness bands (<=2 crouch, >=6 sprint).
func resolve_gait(source: Node, loudness_meters: float) -> String:
	if source != null:
		if _typed_flag(source, "is_sprinting"):
			return "run"
		if _typed_flag(source, "is_crouching"):
			return "crouch"
	if loudness_meters >= FOOTSTEP_SPRINT_MIN_M:
		return "run"
	if loudness_meters <= FOOTSTEP_CROUCH_MAX_M:
		return "crouch"
	return "walk"


static func _typed_flag(obj: Object, prop: String) -> bool:
	if obj == null:
		return false
	var value: Variant = obj.get(prop)
	return value is bool and value == true


## Builds the rich record without emitting it (tests and AI reuse). The bus keeps
## no state about the stimulus beyond the monotonic `event_id`, so two listeners
## receiving the same record agree on which event they are reacting to.
func build_record(origin: Vector3, loudness_meters: float, source: Node, tag: String, surface: String) -> Dictionary:
	var gait: String = resolve_gait(source, loudness_meters)
	var surface_mult: float = 1.0
	if surface.strip_edges() != "":
		# Authored surface modifier: the value listeners receive is final.
		surface_mult = GameData.get_surface_loudness(surface)
	var stim: Dictionary = HearingData.resolve_stim(tag, gait)
	return {
		"event_id": next_event_id(),
		"origin": origin,
		"base_loudness_m": loudness_meters,
		"loudness_m": loudness_meters * surface_mult,
		"source": source,
		"tag": tag,
		"gait": gait,
		"surface": surface,
		"surface_multiplier": surface_mult,
		"stim_tag": str(stim.get("tag", "")),
		"stim": stim,
	}


func emit_noise(origin: Vector3, loudness_meters: float, source: Node = null, tag: String = "generic", surface: String = "") -> void:
	if tag.strip_edges() == "":
		push_warning("[noise_bus] emit_noise called with empty tag; emitting unchanged (listeners resolve it as before)")
	var record: Dictionary = build_record(origin, loudness_meters, source, tag, surface)
	noise_emitted.emit(origin, float(record["loudness_m"]), source, tag)
	noise_record_emitted.emit(record)
