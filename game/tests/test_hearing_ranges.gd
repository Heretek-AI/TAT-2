extends SceneTree
## W6G standalone authored-hearing truth test (S1a/S1b).
##
## Pins the runtime contract of src/ai/hearing_data.gd + src/stealth/noise_bus.gd
## + the guard hearing path against the producer output
## game/data/generated/gameplay/hearing.json / perception.json / guard_ai.json:
##   * 54 stim rows, 22 surfaces, 11 weather types, 285 acoustic portals;
##   * ranges read in metres from the authored metric mirror;
##   * inner/outer investigation band, severity, Short/Long behaviour, query
##     bitmask and heard-by flags survive normalisation;
##   * the five authored range anomalies are clamped and counted;
##   * surface loudness has parity with guard_ai.json;
##   * weather sound carry + the shared perception modifiers are multiplicative;
##   * port tags resolve to authored stims (footstep by gait) and unknown tags
##     fall back to the legacy loudness path;
##   * the guard hears the authored radius, raises alertness only (the 0..100
##     meter stays at 0 on hearing) and honours the heard-by gate;
##   * guard_alert keeps its authored shout transition (ALERTED);
##   * escalation rows (GuardBase Fresh/Drowsy/Vigilant/Mindful, Bouncer
##     sight/lose/angle) drive the guard's sense exports.
##
## Run:
##   XDG_DATA_HOME=/tmp/opencode/w6g-data tools/godot --headless --path game \
##     --script res://tests/test_hearing_ranges.gd

const HearingData := preload("res://src/ai/hearing_data.gd")

var fails: int = 0
## guard_ai.gd references the GameState autoload, and a `--script` main script is
## compiled before autoloads register, so it must be loaded at runtime (the
## standalone tests do the same for every autoload-touching script).
var GuardScript: GDScript = null
## The default active map is old_manor (DenseFog, outdoors x0.9). Pin the guard
## hearing cases to Guildhall (Weather.Type.Gloomy, sound carry High = 1.0) so
## the expected authored radii are exact, then restore.
var _saved_map_id: String = ""


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
		_finish()
		return
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		_saved_map_id = str(gs.get("active_map_id"))
		gs.set("active_map_id", "guildhall")
	HearingData.reload_cache()
	_test_registry()
	_test_rows()
	_test_anomalies()
	_test_surfaces()
	_test_weather_and_perception()
	_test_tag_resolution()
	await _test_noise_bus_records()
	await _test_guard_hearing()
	await _test_escalation()
	if gs != null:
		gs.set("active_map_id", _saved_map_id)
	_finish()


func _finish() -> void:
	# The guard_alert case starts a VO playback; release the audio managers'
	# live playbacks so the process exits without leaked Ogg playbacks (same
	# teardown the audio-lifecycle suite uses).
	var am: Node = root.get_node_or_null("AudioManager")
	if am != null and am.has_method("cleanup_on_exit"):
		am.call("cleanup_on_exit")
	print("HEARING_RANGES_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


func _test_registry() -> void:
	_check(HearingData.stim_count() == 54,
		"W6G.1 54 authored hearing stim rows loaded (got %d)" % HearingData.stim_count(),
		"W6G.1 stim count = %d, expected 54" % HearingData.stim_count())
	_check(HearingData.acoustic_portal_count() == 285,
		"W6G.2 285 authored acoustic portals exposed (runtime layer deferred to W6.3)",
		"W6G.2 portal count = %d" % HearingData.acoustic_portal_count())
	_check(HearingData.weather_types().size() == 11,
		"W6G.3 11 weather sound-carry rows joined",
		"W6G.3 weather rows = %d" % HearingData.weather_types().size())
	var stats: Dictionary = HearingData.hearing_stats_raw()
	_check(int(stats.get("stimuli", 0)) == 54 and int(stats.get("loudness_surfaces", 0)) == 22 and int(stats.get("portals", 0)) == 285,
		"W6G.4 producer stats read (54 stimuli / 22 surfaces / 285 portals)",
		"W6G.4 producer stats = %s" % str(stats))


func _test_rows() -> void:
	var block: Dictionary = HearingData.stim("AI.Stim.Hearing.Combat.Block")
	_check(_approx(float(block.get("max_range_m", -1.0)), 7.5) \
		and _approx(float(block.get("inner_range_m", -1.0)), 1.0) \
		and _approx(float(block.get("outer_range_m", -1.0)), 3.0),
		"W6G.5 Combat.Block reads metres 7.5/1.0/3.0 (not the authored cm)",
		"W6G.5 Combat.Block = %s" % str(block))
	_check(str(block.get("severity", "")) == "Heavy" \
		and str(block.get("behaviour", "")) == "long" \
		and int(block.get("query_bitmask", -1)) == 127 \
		and HearingData.heard_by(block, "hostiles") and HearingData.heard_by(block, "neutrals") and HearingData.heard_by(block, "friendlies"),
		"W6G.6 Combat.Block severity/heavy-long/bitmask 127/all factions",
		"W6G.6 Combat.Block meta = %s" % str(block))
	var glass: Dictionary = HearingData.stim("GlassBreak")
	_check(_approx(float(glass.get("max_range_m", -1.0)), 100.0) and str(glass.get("short", "")) == "GlassBreak",
		"W6G.7 short-form tag lookup + 100 m authored GlassBreak",
		"W6G.7 GlassBreak = %s" % str(glass))
	var takedown: Dictionary = HearingData.stim("AI.Stim.Hearing.Takedown")
	_check(_approx(float(takedown.get("max_range_m", -1.0)), 2.5) and str(takedown.get("severity", "")) == "Heavy",
		"W6G.8 Takedown 2.5 m Heavy (was a hand-tuned 4.5 m emitter)",
		"W6G.8 Takedown = %s" % str(takedown))
	_check(HearingData.stim("does.not.exist").is_empty() and not HearingData.has_stim("does.not.exist"),
		"W6G.9 unknown stim fails closed to {}",
		"W6G.9 unknown stim did not fail closed")
	# Restricted heard_by: hostiles hear, neutrals/friendlies do not.
	_check(HearingData.heard_by("AI.Stim.Hearing.Landed", "hostiles") \
		and not HearingData.heard_by("AI.Stim.Hearing.Landed", "neutrals") \
		and not HearingData.heard_by("AI.Stim.Hearing.Hotwire.Attached", "neutrals") \
		and not HearingData.heard_by("AI.Stim.Hearing.BreakObject.Default", "friendlies"),
		"W6G.10 restricted heard_by preserved (Landed/Hotwire hostiles-only, BreakObject no friendlies)",
		"W6G.10 restricted heard_by wrong: landed=%s hotwire=%s broken=%s" % [
			str(HearingData.hearing_stats_raw().get("restricted_heard_by", [])),
			str(HearingData.heard_by("AI.Stim.Hearing.Hotwire.Attached", "neutrals")),
			str(HearingData.heard_by("AI.Stim.Hearing.BreakObject.Default", "friendlies"))])
	var bits_all: bool = true
	for tag: String in ["AI.Stim.Hearing.Footstep.Running", "AI.Stim.Hearing.Player.SprintingPanting", "AI.Stim.Hearing.Device.Phonograph"]:
		bits_all = bits_all and HearingData.accepts_query(tag, 127)
	_check(bits_all and not HearingData.accepts_query("AI.Stim.Hearing.Footstep.Running", 32),
		"W6G.11 query bitmask gate: 127 accepts every row, an unrelated mask rejects",
		"W6G.11 query bitmask gate failed")


func _test_anomalies() -> void:
	var anomalies: Array[String] = HearingData.anomalies()
	_check(anomalies.size() == 5,
		"W6G.12 5 authored investigation-range anomalies clamped and reported (%d)" % anomalies.size(),
		"W6G.12 anomalies = %s" % str(anomalies))
	var picked: Dictionary = HearingData.stim("AI.Stim.Hearing.LockPicking.Picked")
	var hedge: Dictionary = HearingData.stim("AI.Stim.Hearing.EnterExitHedge")
	var shared: Dictionary = HearingData.stim("AI.Stim.Hearing.Alert.ShareKnowledge")
	var dart: Dictionary = HearingData.stim("AI.Stim.Hearing.Tool.DartLaunch")
	var clamped_ok: bool = _approx(float(picked.get("outer_range_m", -1.0)), 3.0) \
		and _approx(float(hedge.get("outer_range_m", -1.0)), 7.5) \
		and _approx(float(shared.get("outer_range_m", -1.0)), 15.0) \
		and float(dart.get("inner_range_m", -1.0)) <= float(dart.get("outer_range_m", -1.0))
	_check(clamped_ok,
		"W6G.13 outer>max clamped to max and inner>outer reordered (Picked 3.0, Hedge 7.5, Share 15.0, Dart ordered)",
		"W6G.13 clamp failed: picked=%s hedge=%s share=%s dart=%s" % [
			str(picked.get("outer_range_m")), str(hedge.get("outer_range_m")),
			str(shared.get("outer_range_m")), str([dart.get("inner_range_m"), dart.get("outer_range_m")])])
	_check(_approx(float(picked.get("authored_outer_range_m", -1.0)), 5.0),
		"W6G.14 raw authored outer (5.0 m) kept alongside the clamped runtime value",
		"W6G.14 authored outer = %s" % str(picked.get("authored_outer_range_m")))


func _test_surfaces() -> void:
	_check(HearingData.surface_parity(),
		"W6G.15 hearing.json surface table parities with guard_ai.json (22 rows)",
		"W6G.15 surface parity failed")
	var surfaces_ok: bool = _approx(HearingData.surface_loudness("Carpet"), 0.0) \
		and _approx(HearingData.surface_loudness("glass"), 1.5) \
		and _approx(HearingData.surface_loudness("stone"), 1.5) \
		and _approx(HearingData.surface_loudness("metal"), 1.5) \
		and _approx(HearingData.surface_loudness("earth"), 0.0) \
		and _approx(HearingData.surface_loudness(""), 1.0) \
		and _approx(HearingData.surface_loudness("not_a_surface"), 1.0)
	_check(surfaces_ok,
		"W6G.16 surface multipliers + AU3 token aliases (carpet 0.0, glass/stone/metal 1.5, earth 0.0, unknown 1.0)",
		"W6G.16 surface lookup failed")


func _test_weather_and_perception() -> void:
	_check(_approx(HearingData.weather_sound_carry_multiplier("Weather.Type.MidnightClear", false), 1.0) \
		and _approx(HearingData.weather_sound_carry_multiplier("Weather.Type.HeavyRain", false), 0.8) \
		and _approx(HearingData.weather_sound_carry_multiplier("Weather.Type.DenseFog", false), 0.9) \
		and _approx(HearingData.weather_sound_carry_multiplier("Weather.Type.HeavyRain", true), 1.0) \
		and _approx(HearingData.weather_sound_carry_multiplier("Weather.Type.Unknown", false), 1.0),
		"W6G.17 weather SoundCarry: clear 1.0 / heavy rain outdoors 0.8 / dense fog 0.9 / indoors 1.0 / unknown 1.0",
		"W6G.17 weather multipliers = %s" % str([
			HearingData.weather_sound_carry_multiplier("Weather.Type.MidnightClear", false),
			HearingData.weather_sound_carry_multiplier("Weather.Type.HeavyRain", false),
			HearingData.weather_sound_carry_multiplier("Weather.Type.DenseFog", false),
			HearingData.weather_sound_carry_multiplier("Weather.Type.HeavyRain", true),
			HearingData.weather_sound_carry_multiplier("Weather.Type.Unknown", false)]))
	_check(_approx(HearingData.perception_range_multiplier(HearingData.SENSE_HEARING, ["Status.Nervous"]), 1.2) \
		and _approx(HearingData.perception_range_multiplier(HearingData.SENSE_HEARING, ["Weather.SoundCarry.Low"]), 0.8) \
		and _approx(HearingData.perception_range_multiplier(HearingData.SENSE_HEARING, ["Weather.SoundCarry.High_Extra"]), 1.25) \
		and _approx(HearingData.perception_range_multiplier(HearingData.SENSE_HEARING, ["Status.Nervous", "Weather.SoundCarry.Low"]), 0.96) \
		and _approx(HearingData.perception_range_multiplier(HearingData.SENSE_HEARING, []), 1.0),
		"W6G.18 perception range modifiers multiply (Nervous 1.2 x Low 0.8 = 0.96)",
		"W6G.18 perception multipliers wrong")
	_check(_approx(HearingData.drowsy_vision_multiplier(), 0.1),
		"W6G.19 authored Drowsy/Asleep vision modifier 0.1",
		"W6G.19 drowsy vision modifier = %s" % str(HearingData.drowsy_vision_multiplier()))


func _test_tag_resolution() -> void:
	_check(HearingData.resolve_port_tag("noise_alarm") == "AI.Stim.Hearing.Trap.NoiseAlarm" \
		and HearingData.resolve_port_tag("bottle") == "AI.Stim.Hearing.ImpactGeo" \
		and HearingData.resolve_port_tag("takedown") == "AI.Stim.Hearing.Takedown" \
		and HearingData.resolve_port_tag("door") == "AI.Stim.Hearing.OpeningCreak",
		"W6G.20 port tag map resolves device/tool tags to authored stims",
		"W6G.20 tag map = %s" % str([HearingData.resolve_port_tag("noise_alarm"), HearingData.resolve_port_tag("bottle")]))
	_check(HearingData.resolve_port_tag("guard_alert") == "" and HearingData.resolve_port_tag("smoke") == "",
		"W6G.21 guard_alert/smoke stay on the documented legacy loudness path",
		"W6G.21 legacy tags unexpectedly mapped")
	_check(_approx(HearingData.max_range_m("footstep", "walk"), 4.0) \
		and _approx(HearingData.max_range_m("footstep", "crouch"), 4.0) \
		and _approx(HearingData.max_range_m("footstep", "run"), 20.0) \
		and _approx(HearingData.max_range_m("footstep"), 4.0),
		"W6G.22 footstep resolves by gait (walk/crouch 4 m, run 20 m, default walk)",
		"W6G.22 footstep ranges = %s" % str([
			HearingData.max_range_m("footstep", "walk"),
			HearingData.max_range_m("footstep", "crouch"),
			HearingData.max_range_m("footstep", "run")]))
	_check(_approx(HearingData.unknown_fallback_range(30.0, 25.0), 25.0) \
		and _approx(HearingData.unknown_fallback_range(12.0, 25.0), 12.0),
		"W6G.23 legacy fallback keeps min(loudness, HearingRange)",
		"W6G.23 fallback range wrong")
	# Investigation target: exact inside the outer band, band midpoint beyond it.
	var row: Dictionary = HearingData.stim("AI.Stim.Hearing.Combat.Block")
	var near: Vector3 = HearingData.investigation_point(row, Vector3.ZERO, Vector3(2.0, 0.0, 0.0))
	var far: Vector3 = HearingData.investigation_point(row, Vector3.ZERO, Vector3(10.0, 0.0, 0.0))
	_check(near.is_equal_approx(Vector3.ZERO) and _approx(far.length(), 2.0),
		"W6G.24 investigation point: exact inside outer band (3 m), band midpoint (2 m) farther out",
		"W6G.24 investigation point near=%s far=%s" % [str(near), str(far)])


func _test_noise_bus_records() -> void:
	var nb: Node = root.get_node_or_null("NoiseBus")
	_check(nb != null, "W6G.25 NoiseBus autoload present", "W6G.25 NoiseBus missing")
	if nb == null:
		return
	var records: Array[Dictionary] = []
	var legacy: Array = []
	var rec_cb: Callable = func(rec: Dictionary) -> void:
		records.append(rec)
	var old_cb: Callable = func(_o: Vector3, l: float, _s: Node, t: String) -> void:
		legacy.append([l, t])
	nb.connect("noise_record_emitted", rec_cb)
	nb.connect("noise_emitted", old_cb)
	nb.call("emit_noise", Vector3.ZERO, 8.0, null, "footstep", "Glass")
	nb.call("emit_noise", Vector3.ZERO, 15.0, null, "noise_alarm")
	nb.call("emit_noise", Vector3.ZERO, 14.0, null, "guard_alert")
	nb.disconnect("noise_record_emitted", rec_cb)
	nb.disconnect("noise_emitted", old_cb)
	_check(records.size() == 3 and legacy.size() == 3,
		"W6G.26 one record + one legacy emission per emit_noise call",
		"W6G.26 records=%d legacy=%d" % [records.size(), legacy.size()])
	if records.size() != 3:
		return
	var run: Dictionary = records[0]
	_check(str(run.get("stim_tag", "")) == "AI.Stim.Hearing.Footstep.Running" \
		and str(run.get("gait", "")) == "run" \
		and _approx(float(run.get("surface_multiplier", 0.0)), 1.5) \
		and _approx(float(run.get("loudness_m", 0.0)), 12.0),
		"W6G.27 footstep record: sprint gait -> Running stim, glass x1.5, legacy loudness 12.0 m kept",
		"W6G.27 footstep record = %s" % str(run))
	var alarm: Dictionary = records[1]
	_check(str(alarm.get("stim_tag", "")) == "AI.Stim.Hearing.Trap.NoiseAlarm" \
		and _approx(float((alarm.get("stim", {}) as Dictionary).get("max_range_m", 0.0)), 15.0),
		"W6G.28 noise_alarm record carries the authored 15 m Trap.NoiseAlarm row",
		"W6G.28 noise_alarm record = %s" % str(alarm.get("stim_tag")))
	_check((records[2].get("stim", {}) as Dictionary).is_empty() and str(records[2].get("stim_tag", "")) == "",
		"W6G.29 guard_alert record has no authored stim (legacy path)",
		"W6G.29 guard_alert resolved a stim: %s" % str(records[2].get("stim_tag")))
	_check(legacy.size() == 3 and _approx(float(legacy[0][0]), 12.0) and str(legacy[0][1]) == "footstep",
		"W6G.30 legacy noise_emitted signature/value unchanged (footstep glass 8 x1.5 = 12)",
		"W6G.30 legacy emission = %s" % str(legacy))


func _test_guard_hearing() -> void:
	var nb: Node = root.get_node_or_null("NoiseBus")
	if nb == null:
		return
	var guard: CharacterBody3D = GuardScript.new() as CharacterBody3D
	root.add_child(guard)
	guard.global_position = Vector3(0.0, 0.0, 500.0)
	await process_frame
	guard.set_physics_process(false)
	await process_frame
	# Authored 15 m trap stimulus: heard at 14 m, silent at 16 m.
	nb.call("emit_noise", guard.global_position + Vector3(14.0, 0.0, 0.0), 15.0, null, "noise_alarm")
	var heard_state: int = int(guard.get("state"))
	var heard_detection: float = float(guard.get("detection"))
	var heard_stim: String = str(guard.get("last_heard_stim_tag"))
	var heard_radius: float = float(guard.get("last_heard_radius_m"))
	_check(heard_state == 1 and is_zero_approx(heard_detection),
		"W6G.31 15 m noise_alarm heard at 14 m -> SUSPICIOUS and the detection meter stays 0",
		"W6G.31 heard state=%d detection=%s" % [heard_state, str(heard_detection)])
	_check(heard_stim == "AI.Stim.Hearing.Trap.NoiseAlarm" and _approx(heard_radius, 15.0 * guard.call("hearing_sense_multiplier")),
		"W6G.32 heard stim/radius recorded (Trap.NoiseAlarm, authored 15 m x listener multiplier)",
		"W6G.32 stim=%s radius=%s mult=%s" % [heard_stim, str(heard_radius), str(guard.call("hearing_sense_multiplier"))])
	guard.set("state", 0)
	guard.set("last_heard_stim_tag", "")
	nb.call("emit_noise", guard.global_position + Vector3(16.0, 0.0, 0.0), 15.0, null, "noise_alarm")
	_check(int(guard.get("state")) == 0 and str(guard.get("last_heard_stim_tag")) == "",
		"W6G.33 the same 15 m stim is silent at 16 m (authored MaxRange, not emitter loudness)",
		"W6G.33 16 m state=%d stim=%s" % [int(guard.get("state")), str(guard.get("last_heard_stim_tag"))])
	# guard_alert keeps its shout transition (authored call path).
	nb.call("emit_noise", guard.global_position + Vector3(20.0, 0.0, 0.0), 25.0, null, "guard_alert")
	_check(int(guard.get("state")) == 2 and str(guard.get("last_investigation_kind")) == "long",
		"W6G.34 guard_alert at 20 m enters ALERTED with a long investigation",
		"W6G.34 guard_alert state=%d kind=%s" % [int(guard.get("state")), str(guard.get("last_investigation_kind"))])
	# heard-by gate is real: a hostile-only=false row is ignored even at 1 m.
	guard.call("_set_state", 0)
	var gate_record: Dictionary = {
		"origin": guard.global_position + Vector3(1.0, 0.0, 0.0),
		"source": null, "tag": "test_restricted", "surface_multiplier": 1.0,
		"stim_tag": "AI.Stim.Hearing.Landed",
		"stim": {"tag": "AI.Stim.Hearing.Landed", "max_range_m": 30.0, "inner_range_m": 0.0,
			"outer_range_m": 1.0, "behaviour": "short", "query_bitmask": 127,
			"heard_by": {"hostiles": false, "neutrals": true, "friendlies": true}},
	}
	guard.call("_on_noise_record", gate_record)
	_check(int(guard.get("state")) == 0,
		"W6G.35 heard_by gate drops a row the hostiles faction may not hear",
		"W6G.35 heard_by gate ignored (state=%d)" % int(guard.get("state")))
	# Bouncer profile + authored Fresh row feeds the exports.
	var bouncer: CharacterBody3D = GuardScript.new() as CharacterBody3D
	bouncer.name = "Guard_Bouncer_1"
	root.add_child(bouncer)
	bouncer.global_position = Vector3(0.0, 0.0, 600.0)
	await process_frame
	bouncer.set_physics_process(false)
	var scale: float = float(bouncer.get("_sense_diff_scale"))
	_check(str(bouncer.call("escalation_profile")) == "bouncer" \
		and _approx(float(bouncer.get("sight_range")), 25.0 * scale) \
		and _approx(float(bouncer.get("lose_sight_range")), 30.0 * scale) \
		and _approx(float(bouncer.get("fov_deg")), 80.0),
		"W6G.36 Bouncer escalation row drives sight 25 / lose 30 / FOV 80 (scaled %.2f)" % scale,
		"W6G.36 bouncer sight=%s lose=%s fov=%s scale=%s" % [
			str(bouncer.get("sight_range")), str(bouncer.get("lose_sight_range")),
			str(bouncer.get("fov_deg")), str(scale)])
	guard.free()
	bouncer.free()
	await process_frame


func _test_escalation() -> void:
	var fresh: Dictionary = HearingData.escalation_row("guardbase", "Fresh")
	var drowsy: Dictionary = HearingData.escalation_row("guardbase", "Drowsy")
	var vigilant: Dictionary = HearingData.escalation_row("guardbase", "Vigilant")
	var mindful: Dictionary = HearingData.escalation_row("guardbase", "Mindful")
	var bouncer: Dictionary = HearingData.escalation_row("bouncer", "Fresh")
	_check(_approx(float(fresh.get("sight_radius_m", -1.0)), 20.0) \
		and _approx(float(fresh.get("lose_sight_radius_m", -1.0)), 25.0) \
		and _approx(float(fresh.get("peripheral_half_angle_deg", -1.0)), 40.0) \
		and _approx(float(drowsy.get("sight_radius_m", -1.0)), 30.0) \
		and _approx(float(drowsy.get("peripheral_half_angle_deg", -1.0)), 60.0) \
		and _approx(float(vigilant.get("sight_radius_m", -1.0)), 20.0) \
		and _approx(float(mindful.get("lose_sight_radius_m", -1.0)), 25.0),
		"W6G.37 GuardBase Fresh/Drowsy/Vigilant/Mindful rows consumed (20/25/40, Drowsy 30/35/60)",
		"W6G.37 guardbase rows = %s" % str([fresh, drowsy, vigilant, mindful]))
	_check(_approx(float(bouncer.get("sight_radius_m", -1.0)), 25.0) \
		and _approx(float(bouncer.get("lose_sight_radius_m", -1.0)), 30.0) \
		and _approx(float(bouncer.get("peripheral_half_angle_deg", -1.0)), 40.0),
		"W6G.38 Bouncer Fresh row 25/30/40 consumed",
		"W6G.38 bouncer row = %s" % str(bouncer))
	# Manual sense override wins over authored escalation writes.
	var guard: CharacterBody3D = GuardScript.new() as CharacterBody3D
	root.add_child(guard)
	guard.global_position = Vector3(0.0, 0.0, 700.0)
	await process_frame
	guard.set_physics_process(false)
	guard.set("sight_range", 40.0)
	guard.call("_set_state", 1)
	_check(_approx(float(guard.get("sight_range")), 40.0),
		"W6G.39 a pinned sight_range is never overwritten by authored escalation",
		"W6G.39 pinned sight_range became %s" % str(guard.get("sight_range")))
	guard.free()
	await process_frame
