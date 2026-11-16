extends Node
## Evaluates player light visibility (0.0 shadow .. 1.0 lit) against all active scene lights.
## Supports Slithersap light short-circuiting (temporarily disables lights in radius).

var registered_lights: Array[Light3D] = []
var disabled_until: Dictionary = {} # Light3D instance_id -> unix/run time


func register_light(light: Light3D) -> void:
	if not registered_lights.has(light):
		registered_lights.append(light)


func clear_lights() -> void:
	registered_lights.clear()
	disabled_until.clear()


func short_circuit_lights(origin: Vector3, radius: float, duration_sec: float, now_sec: float) -> int:
	var count := 0
	for l in registered_lights:
		if not is_instance_valid(l):
			continue
		if l is DirectionalLight3D:
			continue
		if l.global_position.distance_to(origin) <= radius:
			l.visible = false
			disabled_until[l.get_instance_id()] = now_sec + duration_sec
			count += 1
	return count


func tick(now_sec: float) -> void:
	for l in registered_lights:
		if not is_instance_valid(l):
			continue
		var iid := l.get_instance_id()
		if disabled_until.has(iid) and now_sec >= float(disabled_until[iid]):
			l.visible = true
			disabled_until.erase(iid)


func sample_visibility(world_pos: Vector3, space_state: PhysicsDirectSpaceState3D, exclude: Array[RID] = []) -> float:
	var total := 0.08 # ambient Kilcairn night floor
	for l in registered_lights:
		if not is_instance_valid(l) or not l.visible:
			continue
		if l is DirectionalLight3D:
			total += clampf(l.light_energy * 0.25, 0.0, 0.35)
			continue
		var dist := l.global_position.distance_to(world_pos)
		var max_range := 12.0
		if l is OmniLight3D:
			max_range = l.omni_range
		elif l is SpotLight3D:
			max_range = l.spot_range
		if dist > max_range or max_range <= 0.01:
			continue
		var q := PhysicsRayQueryParameters3D.create(l.global_position, world_pos + Vector3.UP * 0.9, 1, exclude)
		var hit := space_state.intersect_ray(q)
		if not hit.is_empty():
			continue
		var falloff := 1.0 - clampf(dist / max_range, 0.0, 1.0)
		total += falloff * falloff * clampf(l.light_energy * 0.35, 0.15, 0.9)
	return clampf(total, 0.0, 1.0)
