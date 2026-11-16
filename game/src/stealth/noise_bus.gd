extends Node
## Global acoustic stimulus bus connecting player/gadget noises to AI hearing.

signal noise_emitted(origin: Vector3, loudness_meters: float, source: Node, tag: String)


func emit_noise(origin: Vector3, loudness_meters: float, source: Node = null, tag: String = "generic") -> void:
	noise_emitted.emit(origin, loudness_meters, source, tag)
