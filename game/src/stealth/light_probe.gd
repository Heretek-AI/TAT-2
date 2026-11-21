extends Node
## Evaluates player light visibility (0.0 shadow .. 1.0 lit) against all active scene lights.
## Supports Slithersap light short-circuiting (temporarily disables lights in radius).
##
## Perf: sampling is throttled to ~12.5 Hz and lights farther than LIGHT_SAMPLE_RANGE
## are rejected with a squared-distance early-out so a 96-light map never raycasts
## every light every physics frame.

const LIGHT_SAMPLE_RANGE: float = 25.0
const SAMPLE_MIN_INTERVAL_SEC: float = 0.08
const SAMPLE_CACHE_DISTANCE: float = 0.75

# Authored AI light curves. Both CurveFloat assets use RCIM_Cubic with zero
# arrive/leave tangents on the first key (UE's smoothstep) and RCIM_Linear on
# the second, so each is a clamped two-key smoothstep between the rows below.
# - extracted/json/AI/Data/C_LightIntensityToRangeMultiplier.json rows 10-33:
#   light intensity 0..1 -> detection range multiplier. Consumed by
#   BP_NPC_Base._LightIntensityToRangeMultiplierCurve (BP_NPC_Base rows 785-787).
# - extracted/json/AI/Data/C_MovementSpeedToMinimumLightDetectionValue.json rows
#   10-33: movement speed (cm/s) -> the minimum light-detection value a moving
#   player contributes. Consumed by the player's TATLightDetectionCharacterComponent
#   _MovementSpeedToMinimumLightIntensity (BP_TATPlayerCharacter rows 978-981).
const LIGHT_INTENSITY_RANGE_MIN: float = 0.15 # C_LightIntensityToRangeMultiplier Time 0.0 / Value 0.15, rows 15-16
const LIGHT_INTENSITY_RANGE_MAX: float = 1.0 # C_LightIntensityToRangeMultiplier Time 1.0 / Value 1.0, rows 26-27
const MOVEMENT_SPEED_LIGHT_MAX_CM_S: float = 600.0 # C_MovementSpeedToMinimumLightDetectionValue Time 600.0, row 26
const MOVEMENT_SPEED_LIGHT_MIN_VALUE: float = 0.0 # C_MovementSpeedToMinimumLightDetectionValue Value 0.0, row 16
const MOVEMENT_SPEED_LIGHT_MAX_VALUE: float = 0.1 # C_MovementSpeedToMinimumLightDetectionValue Value 0.1, row 27

# Energy -> per-light visibility weight. Loader lights map authored UE
# Intensity through level_loader.LIGHT_INTENSITY_SCALE (1/15), so a median
# authored light (Intensity 15) arrives as energy 1.0. Before the lighting-
# fidelity wave that median light saturated at the old 4.2 ceiling and
# contributed 0.9; scaling by 0.9 restores that response while preserving the
# authored ordering below the median (authored 5 -> energy 0.333 -> 0.30).
# Floor/ceiling match the previous clamps so dim fills stay > 0 and a single
# light cannot exceed the fully-lit weight.
const LIGHT_ENERGY_TO_VISIBILITY: float = 0.9
const LIGHT_VISIBILITY_MIN: float = 0.15
const LIGHT_VISIBILITY_MAX: float = 0.9
## H1/H3 seam: probe raycasts use the loader's physics layer (bodies are
## created with collision_layer = 1 in level_loader._add_collider) and an
## eye-height offset. Named consts so a layer or offset change is one edit
## with a comment, not a silent mismatch. H3 stays HARD_LIMIT: layer 1 is
## correct today and the 0.9 m offset is stealth balance (see ledger).
const OCCLUSION_MASK: int = 1
const EYE_OFFSET_M: float = 0.9
## H1: directionals are occluded along their light axis, not free. The
## to-light direction is the moon basis +Z convention shared with
## weather_visuals (moon disc sits along the +Z axis the light shines from).
## Range 50 m covers interiors; the sky always wins beyond that.
const DIRECTIONAL_OCCLUSION_RANGE: float = 50.0

var registered_lights: Array[Light3D] = []
var disabled_until: Dictionary = {} # Light3D instance_id -> unix/run time

## (Single-slot _has_cache_* fields removed by H4: the two-slot ring above
## replaces them. short_circuit_lights/tick invalidate via _clear_slots().)
## H4: the single-slot cache thrashed with >1 sampler (player + guard
## queries alternate positions, so the 80 ms throttle never hit). Two slots —
## one per sampler in the 2-actor stealth loop — keyed by quantized position.
## More samplers than slots degrade to recompute, never to wrong values.
var _slot_pos: Array[Vector3] = []
var _slot_val: Array[float] = []
var _slot_ms: Array[int] = []
var _slot_next: int = 0
var _sample_calls: int = 0
var _sample_computes: int = 0


func register_light(light: Light3D) -> void:
	if not registered_lights.has(light):
		registered_lights.append(light)


func clear_lights() -> void:
	registered_lights.clear()
	disabled_until.clear()
	_clear_slots()


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
	_clear_slots()
	return count


func tick(now_sec: float) -> void:
	for l in registered_lights:
		if not is_instance_valid(l):
			continue
		var iid := l.get_instance_id()
		if disabled_until.has(iid) and now_sec >= float(disabled_until[iid]):
			l.visible = true
			disabled_until.erase(iid)
			_clear_slots()


## Returns how many times sampling actually recomputed (used by tests).
func sample_compute_count() -> int:
	return _sample_computes


## P2-D6: _sample_calls was write-only telemetry. Total sample_visibility
## invocations (including 80 ms / 0.75 m cache hits); compare against
## sample_compute_count() to see the throttle/cache hit rate.
func sample_call_count() -> int:
	return _sample_calls


## C_LightIntensityToRangeMultiplier: light intensity 0..1 -> detection range
## multiplier 0.15..1.0. Guards multiply their fresh sight range by this value.
static func light_intensity_range_multiplier(intensity: float) -> float:
	var t: float = smoothstep(0.0, 1.0, clampf(intensity, 0.0, 1.0))
	return lerpf(LIGHT_INTENSITY_RANGE_MIN, LIGHT_INTENSITY_RANGE_MAX, t)


## C_MovementSpeedToMinimumLightDetectionValue: movement speed in cm/s -> the
## minimum light-detection value (0..0.1) a moving player contributes even when
## the sampled light is darker. Callers take max(sampled_light, this value).
static func minimum_light_detection_for_speed(speed_cm_s: float) -> float:
	var clamped: float = clampf(speed_cm_s, 0.0, MOVEMENT_SPEED_LIGHT_MAX_CM_S)
	var t: float = smoothstep(0.0, MOVEMENT_SPEED_LIGHT_MAX_CM_S, clamped)
	return lerpf(MOVEMENT_SPEED_LIGHT_MIN_VALUE, MOVEMENT_SPEED_LIGHT_MAX_VALUE, t)


## Per-light stealth weight for a local (omni/spot) light energy. 1.0 is the
## authored median (UE Intensity 15 -> energy 1.0 via the loader's 1/15 scale)
## and must read as the pre-lighting-wave 0.9 so fixing the render scale did not
## silently halve detection. Hand-placed Godot lights use the same energy space.
## Directional lights bypass this helper (0.25 factor in sample_visibility).
static func light_visibility_weight(energy: float) -> float:
	return clampf(energy * LIGHT_ENERGY_TO_VISIBILITY, LIGHT_VISIBILITY_MIN, LIGHT_VISIBILITY_MAX)


func sample_visibility(world_pos: Vector3, space_state: PhysicsDirectSpaceState3D, exclude: Array[RID] = []) -> float:
	_sample_calls += 1
	var now_ms: int = Time.get_ticks_msec()
	for slot_i: int in range(_slot_pos.size()):
		var age_ms: int = now_ms - _slot_ms[slot_i]
		if age_ms >= 0 and float(age_ms) < SAMPLE_MIN_INTERVAL_SEC * 1000.0:
			if _slot_pos[slot_i].distance_squared_to(world_pos) <= SAMPLE_CACHE_DISTANCE * SAMPLE_CACHE_DISTANCE:
				return _slot_val[slot_i]
	var total := 0.08 # ambient Kilcairn night floor
	var max_dist_sq: float = LIGHT_SAMPLE_RANGE * LIGHT_SAMPLE_RANGE
	for l in registered_lights:
		if not is_instance_valid(l) or not l.visible:
			continue
		if l is DirectionalLight3D:
			# H1: directionals no longer bypass occlusion. A moon/sky light
				# hidden behind level geometry must not leak up to 0.35
				# indoors. Off lights (energy <= 0.01) skip like locals.
				if l.light_energy <= 0.01:
					continue
				if _directional_occluded(l, world_pos, space_state, exclude):
					continue
				total += clampf(l.light_energy * 0.25, 0.0, 0.35)
				continue
		if l.light_energy <= 0.01:
			continue
		var dist_sq: float = l.global_position.distance_squared_to(world_pos)
		if dist_sq > max_dist_sq:
			continue
		var max_range: float = 12.0
		if l is OmniLight3D:
			max_range = l.omni_range
		elif l is SpotLight3D:
			max_range = l.spot_range
		if max_range <= 0.01 or dist_sq > max_range * max_range:
			continue
		var q := PhysicsRayQueryParameters3D.create(l.global_position, world_pos + Vector3.UP * EYE_OFFSET_M, OCCLUSION_MASK, exclude)
		var hit := space_state.intersect_ray(q)
		if not hit.is_empty():
			continue
		var dist: float = sqrt(dist_sq)
		var falloff := 1.0 - clampf(dist / max_range, 0.0, 1.0)
		total += falloff * falloff * light_visibility_weight(l.light_energy)
	var result: float = clampf(total, 0.0, 1.0)
	_store_slot(world_pos, result, now_ms)
	_sample_computes += 1
	return result


## H1 helper: ray from the sample point toward the directional source.
## Returns true (occluded) on any blocking hit; fail-open (false) when the
## physics space is unusable so a bad query never reports full darkness.
func _directional_occluded(light: DirectionalLight3D, world_pos: Vector3, space_state: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> bool:
	if light == null or space_state == null:
		return false
	var to_light: Vector3 = light.basis * Vector3(0.0, 0.0, 1.0)
	if to_light.length() < 0.001:
		return false
	var q := PhysicsRayQueryParameters3D.create(world_pos + Vector3.UP * EYE_OFFSET_M, world_pos + Vector3.UP * EYE_OFFSET_M + to_light.normalized() * DIRECTIONAL_OCCLUSION_RANGE, OCCLUSION_MASK, exclude)
	var hit: Dictionary = space_state.intersect_ray(q)
	return not hit.is_empty()


## H4: ring-store one computed value; two slots cover the player + guard
## sampler pair without thrash.
func _clear_slots() -> void:
	_slot_pos.clear()
	_slot_val.clear()
	_slot_ms.clear()
	_slot_next = 0


func _store_slot(world_pos: Vector3, value: float, now_ms: int) -> void:
	if _slot_pos.size() < 2:
		_slot_pos.append(world_pos)
		_slot_val.append(value)
		_slot_ms.append(now_ms)
		return
	_slot_pos[_slot_next] = world_pos
	_slot_val[_slot_next] = value
	_slot_ms[_slot_next] = now_ms
	_slot_next = (_slot_next + 1) % 2
