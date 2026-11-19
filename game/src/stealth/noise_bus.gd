extends Node
## Global acoustic stimulus bus connecting player/gadget noises to AI hearing.
## AudioManager mirrors these stimuli as 3D positional audio on the SFX bus;
## guard VO and footstep variation are layered there (PG-6 full audio runtime).
##
## Surface tags for footstep variation pools (AU3): emitters SHOULD pass one
## of these as [param tag] prefix "footstep:<surface>" is NOT required;
## surface travels in the dedicated [param surface] argument so AI hearing
## stays surface-agnostic while AudioManager picks a variation pool.

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


func emit_noise(origin: Vector3, loudness_meters: float, source: Node = null, tag: String = "generic") -> void:
	noise_emitted.emit(origin, loudness_meters, source, tag)
