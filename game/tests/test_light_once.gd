extends SceneTree
## W6G standalone single-light truth test.
##
## The port used light visibility twice in guard sight:
##   * C_LightIntensityToRangeMultiplier (authored) scaled the acquisition RANGE
##     in _can_see_player, and
##   * a port-only `vis_mult` (0.35..1.5) scaled the 0..100 detection RAMP.
## Darkness therefore slowed detection twice, and a lit target ramped faster for
## no authored reason. W6G keeps the authored range curve and removes vis_mult:
## light gates WHETHER the guard can see, never a second multiplicative ramp.
## The retained 15/45/100 state thresholds are untouched.
##
## Run:
##   XDG_DATA_HOME=/tmp/opencode/w6g-data tools/godot --headless --path game \
##     --script res://tests/test_light_once.gd

const HearingData := preload("res://src/ai/hearing_data.gd")
const LightProbeScript := preload("res://src/stealth/light_probe.gd")

const GUARD_SOURCE := "res://src/ai/guard_ai.gd"

var fails: int = 0
## guard_ai.gd touches the GameState autoload; a --script main script compiles
## before autoloads register, so load it at runtime.
var GuardScript: GDScript = null


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _approx(a: float, b: float, eps: float = 0.0005) -> bool:
	return absf(a - b) <= eps


func _initialize() -> void:
	await process_frame
	GuardScript = load("res://src/ai/guard_ai.gd") as GDScript
	if GuardScript == null:
		printerr("FAIL: guard_ai.gd failed to load")
		fails += 1
		print("LIGHT_ONCE_SUMMARY: fails=", fails)
		quit(1)
		return
	var src: String = FileAccess.get_file_as_string(GUARD_SOURCE)
	_check(src.find("var vis_mult") < 0 and src.find("* vis_mult") < 0,
		"W6G-L.1 guard_ai.gd carries no port-only vis_mult ramp multiplier",
		"W6G-L.1 vis_mult is still applied in guard_ai.gd")
	_check(src.find("func detection_gain_per_second(") >= 0 \
		and src.find("func effective_vision_range(") >= 0,
		"W6G-L.2 detection gain and effective vision range are single-purpose seams",
		"W6G-L.2 W6G seams missing")

	# Authored range curve values (C_LightIntensityToRangeMultiplier: 0 -> 0.15,
	# 1 -> 1.0) still gate range.
	var dark_mult: float = LightProbeScript.light_intensity_range_multiplier(0.0)
	var lit_mult: float = LightProbeScript.light_intensity_range_multiplier(1.0)
	_check(_approx(dark_mult, 0.15) and _approx(lit_mult, 1.0),
		"W6G-L.3 authored light->range curve kept (0 m light x0.15, full light x1.0)",
		"W6G-L.3 light range curve dark=%s lit=%s" % [str(dark_mult), str(lit_mult)])

	var guard: CharacterBody3D = GuardScript.new() as CharacterBody3D
	guard.global_position = Vector3(0.0, 0.0, 900.0)
	root.add_child(guard)
	await process_frame
	guard.set_physics_process(false)

	var gs: Node = root.get_node_or_null("GameState")
	var saved_light: float = 0.2
	if gs != null:
		saved_light = float(gs.get("player_light_visibility"))

	# Same distance/pose, only the sampled light differs: the ramp is identical.
	if gs != null:
		gs.set("player_light_visibility", 0.05)
	var dark_gain: float = float(guard.call("detection_gain_per_second", 10.0, false, false, 0.0))
	if gs != null:
		gs.set("player_light_visibility", 0.95)
	var lit_gain: float = float(guard.call("detection_gain_per_second", 10.0, false, false, 0.0))
	_check(_approx(dark_gain, lit_gain) and dark_gain > 0.0,
		"W6G-L.4 detection gain is light-independent at 10 m (dark %s/s = lit %s/s)" % [str(dark_gain), str(lit_gain)],
		"W6G-L.4 ramp still reads light: dark=%s lit=%s" % [str(dark_gain), str(lit_gain)])

	# ... while acquisition range still collapses in darkness.
	var base_range: float = float(guard.call("effective_vision_range", false))
	_check(base_range > 0.0 and base_range * dark_mult < base_range * lit_mult,
		"W6G-L.5 acquisition range still scales with light (dark %.2f m < lit %.2f m)" % [base_range * dark_mult, base_range * lit_mult],
		"W6G-L.5 acquisition range ignored light")

	# Retained thresholds: 15 / 45 / 100 (no authored replacement exists).
	var consts: Dictionary = GuardScript.get_script_constant_map()
	_check(_approx(float(consts.get("DETECTION_SUSPICIOUS_AT", -1.0)), 15.0) \
		and _approx(float(consts.get("DETECTION_ALERTED_AT", -1.0)), 45.0) \
		and _approx(float(consts.get("DETECTION_COMBAT_AT", -1.0)), 100.0),
		"W6G-L.6 retained detection thresholds 15/45/100 unchanged",
		"W6G-L.6 thresholds = %s/%s/%s" % [
			str(consts.get("DETECTION_SUSPICIOUS_AT")),
			str(consts.get("DETECTION_ALERTED_AT")),
			str(consts.get("DETECTION_COMBAT_AT"))])

	# Authored escalation: GuardBase Fresh/Mindful/Vigilant share 20 m; Drowsy
	# (KNOCKED_OUT) authors 30 m and the x0.1 Asleep vision modifier.
	var scale: float = float(guard.get("_sense_diff_scale"))
	var fresh_sight: float = float(guard.get("sight_range"))
	guard.call("_set_state", 1) # SUSPICIOUS -> Mindful
	var mindful_sight: float = float(guard.get("sight_range"))
	guard.call("_set_state", 2) # ALERTED -> Vigilant
	var vigilant_sight: float = float(guard.get("sight_range"))
	var vigilant_fov: float = float(guard.get("fov_deg"))
	guard.call("_set_state", 5) # KNOCKED_OUT -> Drowsy
	var drowsy_sight: float = float(guard.get("sight_range"))
	var ko_effective: float = float(guard.call("effective_vision_range", false))
	var drowsy_rows_ok: bool = _approx(fresh_sight, 20.0 * scale) \
		and _approx(mindful_sight, 20.0 * scale) \
		and _approx(vigilant_sight, 20.0 * scale) \
		and _approx(vigilant_fov, 80.0) \
		and _approx(drowsy_sight, 30.0 * scale) \
		and _approx(ko_effective, drowsy_sight * HearingData.drowsy_vision_multiplier())
	_check(drowsy_rows_ok,
		"W6G-L.7 GuardBase Fresh/Mindful/Vigilant 20 m + FOV 80, Drowsy 30 m x0.1 Asleep (scale %.2f)" % scale,
		"W6G-L.7 escalation failed: fresh=%s mindful=%s vigilant=%s fov=%s drowsy=%s ko_eff=%s scale=%s" % [
			str(fresh_sight), str(mindful_sight), str(vigilant_sight), str(vigilant_fov),
			str(drowsy_sight), str(ko_effective), str(scale)])

	if gs != null:
		gs.set("player_light_visibility", saved_light)
	guard.queue_free()
	await process_frame
	print("LIGHT_ONCE_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)
