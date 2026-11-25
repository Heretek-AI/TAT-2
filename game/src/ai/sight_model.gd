extends RefCounted
## Authored TAT sight geometry (RE-I-02), the five fields the producer dropped.
##
## Shipped asset: `AIC_GuardBase` subobject 29 `TATAISenseConfig_Sight_0`
## `_EscalationStateToSettings` (4 rows x 8 fields), plus the same struct on
## `AIC_Bouncer`, `AIC_Hauntstable` and `AIC_Civilian`:
##   SightRadius, LoseSightRadius, PeripheralVisionAngleDegrees,
##   MinimumSightRadius, PointOfViewBackwardOffset, NearClippingRadius,
##   FrustumAspectRatio, FrustumPitch.
## `tools/parse_gameplay.py:sight_table()` extracts only the first three, so the
## other five never reach `guard_ai.json`.
##
## DATA CONTRACT (the half that is BLOCKED-ON T01)
## `guard_ai.json.escalation_tables.<profile>.<row>` must carry five more keys,
## in metres/degrees, alongside the three it already has:
##   "minimum_sight_radius_m": 100 cm -> 1.0
##   "point_of_view_backward_offset_m": 120 cm -> 1.2 (50 -> 0.5 on Drowsy)
##   "near_clipping_radius_m": 150 cm -> 1.5 (50 -> 0.5 on Drowsy)
##   "frustum_aspect_ratio": 2.0
##   "frustum_pitch_deg": -22.0
## and two profiles the producer never builds: "hauntstable" (3000/3500/40,
## aspect 2.0, pitch -22 -- the Bouncer row is NOT Hauntstable's) and
## "civilian" (4 rows). Until T01 emits them, AUTHORED_FALLBACK below carries the
## exact authored values, and `test_ai_perception.gd` asserts every fallback
## value equals the raw `extracted/json/AI/Controllers/AIC_*.json` field, so the
## JSON silently takes over the moment the producer lands and a data patch that
## changes a fallback value fails the gate instead of drifting.
##
## SEMANTICS (inference, stated so it can be argued with)
## * `minimum_sight_radius` is the radius inside which the guard perceives a
##   target **regardless of facing** (the port's invented 3.5 m all-round bypass
##   was 3.5x this value). Read literally as "minimum sight radius" it could
##   instead be a floor on the light-scaled sight radius; both readings agree
##   that 3.5 m is wrong, and the floor reading never binds on any authored row
##   (0.15 x 20 m = 3.0 m > 1.0 m), so the guarantee reading is the one that is
##   observable and therefore testable.
## * `point_of_view_backward_offset` moves the perception eye backwards along
##   the guard's forward axis. It orients the frustum only: the occlusion ray
##   still leaves the model head, because a POV pushed 1.2 m behind a guard
##   backed against a wall would start inside geometry and blind it.
## * `frustum_aspect_ratio` is horizontal/vertical, so the vertical half-angle is
##   atan(tan(horizontal half) / aspect). With aspect 2.0 and a 40 deg half-angle
##   that is 22.75 deg; with `frustum_pitch` -22 the authored view spans roughly
##   -44.7..+0.7 deg of elevation, i.e. the guard does not look above the
##   horizon. That is the audit's arithmetic (RE-I-02b) and the reason a player
##   2 m up at 5 m is outside the shipped frustum.
## * `near_clipping_radius` is the frustum near plane: below it the angular
##   frustum tests are skipped (a target at arm's length has no meaningful
##   elevation), the horizontal cone still applies unless the minimum radius
##   already granted sight. It is NOT modelled as a blind bubble: nothing in the
##   asset or the audit supports "a guard cannot see you point blank", and a
##   blind bubble would be a larger invention than the value itself.
## * `--sight-frustum=off` is a diagnostic (same shape as TAT2_ROUGH_BAKE=off):
##   it disables ONLY the vertical gate so the authored pitch can be isolated in
##   a playtest. It never changes the minimum radius or the horizontal cone.

const HearingData = preload("res://src/ai/hearing_data.gd")

## Keys the producer must add to `escalation_tables`. Exposed so a test can
## assert the contract in one place.
const CONTRACT_KEYS: Array[String] = [
	"minimum_sight_radius_m",
	"point_of_view_backward_offset_m",
	"near_clipping_radius_m",
	"frustum_aspect_ratio",
	"frustum_pitch_deg",
]

## Authored values, transcribed from
## `extracted/json/AI/Controllers/AIC_{GuardBase,Bouncer,Hauntstable,Civilian}.json`
## `_EscalationStateToSettings[i].Value`. Rows are in asset order, which is the
## order the producer already names Drowsy/Fresh/Mindful/Vigilant for the guard.
## The three extracted fields are repeated here only so the fallback is a
## complete row; the consumer prefers the JSON value whenever it is present.
const AUTHORED_FALLBACK: Dictionary = {
	"guardbase": {
		"Drowsy": {"sight_radius_m": 30.0, "lose_sight_radius_m": 35.0, "peripheral_half_angle_deg": 60.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 0.5, "near_clipping_radius_m": 0.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -22.0},
		"Fresh": {"sight_radius_m": 20.0, "lose_sight_radius_m": 25.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 1.2, "near_clipping_radius_m": 1.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -22.0},
		"Mindful": {"sight_radius_m": 20.0, "lose_sight_radius_m": 25.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 1.2, "near_clipping_radius_m": 1.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -22.0},
		"Vigilant": {"sight_radius_m": 20.0, "lose_sight_radius_m": 25.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 1.2, "near_clipping_radius_m": 1.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -22.0},
	},
	"bouncer": {
		"Drowsy": {"sight_radius_m": 25.0, "lose_sight_radius_m": 30.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 0.5, "near_clipping_radius_m": 0.5, "frustum_aspect_ratio": 1.2, "frustum_pitch_deg": -21.0},
		"Fresh": {"sight_radius_m": 25.0, "lose_sight_radius_m": 30.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 0.5, "near_clipping_radius_m": 0.5, "frustum_aspect_ratio": 1.2, "frustum_pitch_deg": -21.0},
		"Mindful": {"sight_radius_m": 25.0, "lose_sight_radius_m": 30.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 0.5, "near_clipping_radius_m": 0.5, "frustum_aspect_ratio": 1.2, "frustum_pitch_deg": -21.0},
		"Vigilant": {"sight_radius_m": 25.0, "lose_sight_radius_m": 30.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 0.5, "near_clipping_radius_m": 0.5, "frustum_aspect_ratio": 1.2, "frustum_pitch_deg": -21.0},
	},
	"hauntstable": {
		"Drowsy": {"sight_radius_m": 30.0, "lose_sight_radius_m": 35.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 1.2, "near_clipping_radius_m": 1.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -22.0},
		"Fresh": {"sight_radius_m": 30.0, "lose_sight_radius_m": 35.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 1.2, "near_clipping_radius_m": 1.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -22.0},
		"Mindful": {"sight_radius_m": 30.0, "lose_sight_radius_m": 35.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 1.2, "near_clipping_radius_m": 1.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -22.0},
		"Vigilant": {"sight_radius_m": 30.0, "lose_sight_radius_m": 35.0, "peripheral_half_angle_deg": 40.0, "minimum_sight_radius_m": 1.0, "point_of_view_backward_offset_m": 1.2, "near_clipping_radius_m": 1.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -22.0},
	},
	# AIC_Civilian rows in asset order. Row 0 (1000/1500/10 deg, pitch -10) is the
	# calm/asleep row by position; only Mindful/Vigilant drive the flee reaction.
	"civilian": {
		"Drowsy": {"sight_radius_m": 10.0, "lose_sight_radius_m": 15.0, "peripheral_half_angle_deg": 10.0, "minimum_sight_radius_m": 0.0, "point_of_view_backward_offset_m": 1.2, "near_clipping_radius_m": 1.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -10.0},
		"Fresh": {"sight_radius_m": 15.0, "lose_sight_radius_m": 20.0, "peripheral_half_angle_deg": 50.0, "minimum_sight_radius_m": 0.0, "point_of_view_backward_offset_m": 1.2, "near_clipping_radius_m": 1.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -20.0},
		"Mindful": {"sight_radius_m": 20.0, "lose_sight_radius_m": 25.0, "peripheral_half_angle_deg": 50.0, "minimum_sight_radius_m": 0.0, "point_of_view_backward_offset_m": 1.0, "near_clipping_radius_m": 1.49, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": -2.0},
		"Vigilant": {"sight_radius_m": 25.0, "lose_sight_radius_m": 30.0, "peripheral_half_angle_deg": 60.0, "minimum_sight_radius_m": 0.0, "point_of_view_backward_offset_m": 1.0, "near_clipping_radius_m": 1.5, "frustum_aspect_ratio": 2.0, "frustum_pitch_deg": 0.0},
	},
}

## Authored eye height above the capsule origin used by the port's ray endpoint
## (guard_ai._can_see_player). Not a sense-config field: UE derives the POV from
## the pawn's eye socket, which the cooked assets do not expose.
const EYE_HEIGHT_M: float = 1.5
## Player torso/eye sample the port aims at, same constant the ray endpoint uses.
const TARGET_HEIGHT_M: float = 1.0

static var _frustum_enabled: int = -1  # -1 unknown, 0 off, 1 on


## Authored row for a profile + escalation row name, JSON first, documented
## fallback second. Always complete: every field above is present.
static func row(profile: String, state_name: String) -> Dictionary:
	var out: Dictionary = {}
	var authored: Dictionary = AUTHORED_FALLBACK.get(profile, AUTHORED_FALLBACK["guardbase"])
	out = (authored.get(state_name, authored.get("Fresh", {})) as Dictionary).duplicate(true)
	var json_row: Dictionary = HearingData.escalation_row(profile, state_name)
	for k: Variant in json_row.keys():
		out[str(k)] = json_row[k]
	return out


## True when the row came from `guard_ai.json` (the producer half has landed for
## the five contract keys), false when any contract key is still the fallback.
static func row_is_produced(profile: String, state_name: String) -> bool:
	var json_row: Dictionary = HearingData.escalation_row(profile, state_name)
	for key: String in CONTRACT_KEYS:
		if not json_row.has(key):
			return false
	return true


## Profiles the producer builds today. Anything else is fallback-only.
static func produced_profiles() -> Array[String]:
	return ["guardbase", "bouncer"]


static func minimum_sight_radius_m(sight_row: Dictionary) -> float:
	return maxf(0.0, float(sight_row.get("minimum_sight_radius_m", 1.0)))


static func point_of_view_offset_m(sight_row: Dictionary) -> float:
	return maxf(0.0, float(sight_row.get("point_of_view_backward_offset_m", 0.0)))


static func near_clipping_radius_m(sight_row: Dictionary) -> float:
	return maxf(0.0, float(sight_row.get("near_clipping_radius_m", 0.0)))


static func frustum_aspect(sight_row: Dictionary) -> float:
	return maxf(0.01, float(sight_row.get("frustum_aspect_ratio", 2.0)))


static func frustum_pitch_deg(sight_row: Dictionary) -> float:
	return float(sight_row.get("frustum_pitch_deg", -22.0))


## Vertical half-angle implied by the authored horizontal half-angle and aspect.
static func vertical_half_angle_deg(horizontal_half_deg: float, aspect: float) -> float:
	var half: float = clampf(horizontal_half_deg, 0.01, 89.9)
	return rad_to_deg(atan(tan(deg_to_rad(half)) / maxf(aspect, 0.01)))


## Authored elevation band (degrees, min..max) of the view frustum. The centre is
## `frustum_pitch_deg` (negative = looking down) and the half-width is the
## vertical half-angle. Guard Fresh: [-44.75, +0.75].
static func elevation_band_deg(sight_row: Dictionary) -> Vector2:
	var half_h: float = float(sight_row.get("peripheral_half_angle_deg", 40.0))
	var vhalf: float = vertical_half_angle_deg(half_h, frustum_aspect(sight_row))
	var pitch: float = frustum_pitch_deg(sight_row)
	return Vector2(pitch - vhalf, pitch + vhalf)


## Perception eye: capsule origin + authored eye height, moved backwards along
## the body's forward axis by the authored POV offset.
static func eye_position(body: Node3D, sight_row: Dictionary) -> Vector3:
	if body == null:
		return Vector3.ZERO
	var fwd: Vector3 = -body.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.001:
		fwd = fwd.normalized()
	else:
		fwd = Vector3.FORWARD
	return body.global_position + Vector3.UP * EYE_HEIGHT_M - fwd * point_of_view_offset_m(sight_row)


## World point the guard aims at on a target body.
static func target_point(target: Node3D) -> Vector3:
	return target.global_position + Vector3.UP * TARGET_HEIGHT_M


## Horizontal half-angle of a flattened direction pair, degrees. Zero-length
## vectors read as "in front" so a degenerate pose cannot fake a blind spot.
static func horizontal_angle_deg(to_target: Vector3, forward: Vector3) -> float:
	var a: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	var b: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if a.length() < 0.0001 or b.length() < 0.0001:
		return 0.0
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


## Elevation of `to_target` in degrees (positive = above the eye plane).
static func elevation_deg(to_target: Vector3) -> float:
	var len: float = to_target.length()
	if len < 0.0001:
		return 0.0
	return rad_to_deg(asin(clampf(to_target.y / len, -1.0, 1.0)))


## Diagnostic switch: `--sight-frustum=off` disables only the vertical gate.
static func frustum_enabled() -> bool:
	if _frustum_enabled < 0:
		_frustum_enabled = 1
		for arg: String in OS.get_cmdline_user_args():
			if arg == "--sight-frustum=off":
				_frustum_enabled = 0
				push_warning("[sight_model] vertical frustum gate disabled by --sight-frustum=off (diagnostic; the authored pitch is NOT applied)")
	return _frustum_enabled == 1


## One query: does the authored frustum admit a target at `dist` along `dir`?
## Returns true when seen. `dist` is measured from the perception eye.
static func frustum_admits(sight_row: Dictionary, to_target: Vector3, forward: Vector3, min_radius_override: float = -1.0, check_vertical: bool = true) -> bool:
	var dist: float = to_target.length()
	var min_radius: float = minimum_sight_radius_m(sight_row) if min_radius_override < 0.0 else maxf(0.0, min_radius_override)
	if dist <= min_radius:
		# Inside the authored minimum sight radius facing does not matter.
		return true
	var half_h: float = float(sight_row.get("peripheral_half_angle_deg", 40.0))
	if horizontal_angle_deg(to_target, forward) > half_h:
		return false
	if not check_vertical or not frustum_enabled():
		return true
	if dist < near_clipping_radius_m(sight_row):
		# Inside the near plane the elevation is meaningless (a target at 0.6 m
		# and eye height is 40 deg "below" a pitched frustum).
		return true
	var band: Vector2 = elevation_band_deg(sight_row)
	var elev: float = elevation_deg(to_target)
	return elev >= band.x and elev <= band.y
