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

signal noise_emitted(origin: Vector3, loudness_meters: float, source: Node, tag: String)

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


static func is_known_surface(surface: String) -> bool:
	return SURFACES.has(surface.to_lower().strip_edges())


func emit_noise(origin: Vector3, loudness_meters: float, source: Node = null, tag: String = "generic", surface: String = "") -> void:
	if tag.strip_edges() == "":
		push_warning("[noise_bus] emit_noise called with empty tag; emitting unchanged (listeners resolve it as before)")
	var emitted: float = loudness_meters
	if surface.strip_edges() != "":
		# Authored surface modifier: the value listeners receive is final.
		emitted *= GameData.get_surface_loudness(surface)
	noise_emitted.emit(origin, emitted, source, tag)
