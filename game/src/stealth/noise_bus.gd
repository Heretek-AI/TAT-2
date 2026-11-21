extends Node
## Global acoustic stimulus bus connecting player/gadget noises to AI hearing.
## AudioManager mirrors these stimuli as 3D positional audio on the SFX bus;
## guard VO and footstep variation are layered there (PG-6 full audio runtime).
##
## Footstep-surface vocabulary (AU3). NOTE (P2-D7): the surface does NOT
## travel on this bus — emit_noise has no surface argument. The player
## controller resolves its surface listener-side and calls
## AudioManager.play_footstep(surface, ...) directly; AI hearing stays
## surface-agnostic by design (listeners use distance <= loudness only).
## is_known_surface() lets emitters fail loud on typos instead of silently
## falling back to the "wood" default pool.

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


func emit_noise(origin: Vector3, loudness_meters: float, source: Node = null, tag: String = "generic") -> void:
	if tag.strip_edges() == "":
		push_warning("[noise_bus] emit_noise called with empty tag; emitting unchanged (listeners resolve it as before)")
	noise_emitted.emit(origin, loudness_meters, source, tag)
