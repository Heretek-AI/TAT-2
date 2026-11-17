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

var registered_lights: Array[Light3D] = []
var disabled_until: Dictionary = {} # Light3D instance_id -> unix/run time

var _has_cache: bool = false
var _cached_value: float = 0.1
var _cached_pos: Vector3 = Vector3.ZERO
var _cached_ms: int = -100000000
var _sample_calls: int = 0
var _sample_computes: int = 0


func register_light(light: Light3D) -> void:
	if not registered_lights.has(light):
		registered_lights.append(light)


func clear_lights() -> void:
	registered_lights.clear()
	disabled_until.clear()
	_has_cache = false


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
	_has_cache = false
	return count


func tick(now_sec: float) -> void:
	for l in registered_lights:
		if not is_instance_valid(l):
			continue
		var iid := l.get_instance_id()
		if disabled_until.has(iid) and now_sec >= float(disabled_until[iid]):
			l.visible = true
			disabled_until.erase(iid)
			_has_cache = false


## Returns how many times sampling actually recomputed (used by tests).
func sample_compute_count() -> int:
	return _sample_computes


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


func sample_visibility(world_pos: Vector3, space_state: PhysicsDirectSpaceState3D, exclude: Array[RID] = []) -> float:
	_sample_calls += 1
	if _has_cache:
		var age_ms: int = Time.get_ticks_msec() - _cached_ms
		if age_ms >= 0 and float(age_ms) < SAMPLE_MIN_INTERVAL_SEC * 1000.0:
			if _cached_pos.distance_squared_to(world_pos) <= SAMPLE_CACHE_DISTANCE * SAMPLE_CACHE_DISTANCE:
				return _cached_value
	var total := 0.08 # ambient Kilcairn night floor
	var max_dist_sq: float = LIGHT_SAMPLE_RANGE * LIGHT_SAMPLE_RANGE
	for l in registered_lights:
		if not is_instance_valid(l) or not l.visible:
			continue
		if l is DirectionalLight3D:
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
		var q := PhysicsRayQueryParameters3D.create(l.global_position, world_pos + Vector3.UP * 0.9, 1, exclude)
		var hit := space_state.intersect_ray(q)
		if not hit.is_empty():
			continue
		var dist: float = sqrt(dist_sq)
		var falloff := 1.0 - clampf(dist / max_range, 0.0, 1.0)
		total += falloff * falloff * clampf(l.light_energy * 0.35, 0.15, 0.9)
	var result: float = clampf(total, 0.0, 1.0)
	_has_cache = true
	_cached_pos = world_pos
	_cached_value = result
	_cached_ms = Time.get_ticks_msec()
	_sample_computes += 1
	return result
