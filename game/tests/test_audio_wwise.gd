extends SceneTree
## T03 audio: standalone headless test for res://src/core/audio_wwise.gd.
##
## Two groups:
##   * fixture — always runs, loads res://tests/fixtures/audio_wwise_sample.json
##     (a hand-built, valid `tat2.audio_wwise/1` document) and asserts the bus
##     graph, attenuation, occlusion, emitter/bed/music resolution, VO labels,
##     idempotency and the missing-file degradation path. No generated data is
##     needed, so a fresh clone passes.
##   * real-data — runs only when TAT2_AUDIO_WWISE_JSON (or the default
##     res://data/generated/audio_wwise.json) exists; prints the measured
##     numbers and SKIPs with zero failures when the produced file is absent.
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_audio_wwise.gd
##   TAT2_AUDIO_WWISE_JSON=/tmp/opencode/t03-b/audio_wwise.json \
##     tools/godot --headless --path game --script res://tests/test_audio_wwise.gd
##
## _init() is used on purpose: the claims are all synchronous (AudioServer is a
## global singleton and the fixture needs no scene), so the run finishes before
## autoloads start and the exit code is exact.

const FIXTURE_PATH: String = "res://tests/fixtures/audio_wwise_sample.json"
const VERB_PREFIX: String = "VERB_"
const SEND_PROBE_BUS: String = "AWW_SEND_PROBE"

var fails: int = 0
var passed: int = 0


func _init() -> void:
	_fixture_group()
	_real_data_group()
	print("AUDIO_WWISE_SUMMARY: fails=%d passed=%d" % [fails, passed])
	quit(1 if fails > 0 else 0)


# =========================================================================
# Fixture group (always)
# =========================================================================


func _fixture_group() -> void:
	print("--- fixture group: ", FIXTURE_PATH)
	var aw: AudioWwise = AudioWwise.new()
	var loaded: bool = aw.load_data(FIXTURE_PATH)
	_check(loaded and aw.is_loaded(),
		"fixture loads as tat2.audio_wwise/1",
		"fixture load failed: %s" % aw.degraded_reason())
	if not loaded:
		return

	var stats: Dictionary = aw.stats()
	_check(int(stats["buses"]) == 3 and int(stats["named_buses"]) == 2,
		"fixture parses 3 buses (2 named): %d/%d" % [int(stats["buses"]), int(stats["named_buses"])],
		"fixture bus counts wrong: %s" % str(stats))
	_check(int(stats["attenuations"]) == 2 and int(stats["events"]) == 4,
		"fixture parses 2 attenuations, 4 events",
		"fixture attenuation/event counts wrong: %s" % str(stats))
	_check(int(stats["events_with_bus"]) == 3 and int(stats["events_with_attenuation"]) == 2,
		"fixture parses 3 events with a bus, 2 with an attenuation",
		"fixture event refs wrong: %s" % str(stats))
	_check(aw.counts().get("buses", -1) == 3,
		"declared counts() block is exposed (buses=3)",
		"counts() block missing or wrong: %s" % str(aw.counts()))

	# -- bus graph ---------------------------------------------------------
	var report: Dictionary = aw.build_buses()
	var rows: Array = report.get("buses", []) as Array
	_check(bool(report.get("built", false)) and rows.size() == 2,
		"build_buses() creates 2 reverb buses",
		"build_buses() row count wrong: %d (%s)" % [rows.size(), str(report.get("degraded", ""))])

	var server_verbs: Array = _verb_bus_indices()
	_check(server_verbs.size() == 2,
		"AudioServer holds exactly 2 VERB_* buses (%s)" % str(server_verbs),
		"AudioServer VERB_* bus count is %d" % server_verbs.size())
	var reverbs_ok: bool = server_verbs.size() == 2
	for bus_idx: int in server_verbs:
		if not _has_reverb(bus_idx):
			reverbs_ok = false
	_check(reverbs_ok,
		"every VERB_* bus carries an AudioEffectReverb",
		"a VERB_* bus has no AudioEffectReverb")

	var ext_row: Dictionary = _row_named(rows, "VERB_Cmn_Ext_World")
	var int_row: Dictionary = _row_named(rows, "VERB_Cmn_Int_Room_Large")
	_check(not ext_row.is_empty() and str(ext_row["convolution"]) == "unavailable:BOOM Library IR - F&S\\Metropole 05 50m FOA.wav",
		"convolution impulse is reported unavailable with its authored name",
		"convolution degradation missing: %s" % str(ext_row.get("convolution", "<no row>")))
	_check(str(ext_row.get("fallback", "")) == "AudioEffectReverb",
		"the named impulse reports its AudioEffectReverb fallback",
		"fallback not reported on the convolution row")
	_check(str(ext_row.get("output", "")) == "Master" and str(int_row.get("output", "")) == "Master",
		"both reverb buses output to Master",
		"a reverb bus does not output to Master")
	_check(str(int_row.get("convolution", "")) == "none" and str(int_row.get("fallback", "")) == "",
		"a bus with no authored impulse reports no convolution",
		"the bus without an IR claims a convolution impulse")
	_check(int(ext_row.get("index", -1)) >= 0 and is_equal_approx(float(ext_row.get("decay_s", 0.0)), 8.0),
		"the exterior bus is seeded from the authored 8.0 s decay",
		"authored decay not resolved: %s" % str(ext_row.get("decay_s", "<missing>")))
	_check(is_equal_approx(float(ext_row.get("max_radius_m", 0.0)), 25.0),
		"authored MaxAttenuationRadius 25.0 m is recorded as a distance note",
		"authored reverb radius missing: %s" % str(ext_row.get("max_radius_m", "<missing>")))
	_check(is_equal_approx(float(int_row.get("decay_s", 0.0)), 1.0),
		"a reverb bus with no assignment row uses the documented 1.0 s default",
		"default decay not applied: %s" % str(int_row.get("decay_s", "<missing>")))

	var master: Dictionary = report.get("master", {}) as Dictionary
	var limiter: Dictionary = master.get("limiter", {}) as Dictionary
	var eq: Dictionary = master.get("eq", {}) as Dictionary
	var master_effects: Array = report.get("master_effects", []) as Array
	_check(absf(float(limiter.get("ceiling_db", 0.0)) + 0.3) < 0.001,
		"Master limiter uses the documented -0.3 dB ceiling when no authored params exist",
		"Master limiter ceiling wrong: %s" % str(limiter.get("ceiling_db", "<missing>")))
	_check(master_effects.has("AudioEffectHardLimiter") and master_effects.has("AudioEffectEQ10"),
		"Master carries the hard limiter + EQ10 mastering chain (%s)" % str(master_effects),
		"mastering chain incomplete: %s" % str(master_effects))
	_check(int(eq.get("bands", 0)) == 10,
		"Master EQ10 exposes 10 flat bands",
		"Master EQ band count wrong: %s" % str(eq.get("bands", "<missing>")))

	# -- attenuation -------------------------------------------------------
	var door: Dictionary = aw.attenuation_for("Play_Prop_Int_Door_Wood_Open")
	var curve: Array = door.get("curve", []) as Array
	_check(bool(door["found"]) and is_equal_approx(float(door["max_distance_m"]), 75.0),
		"75 m event reports max_distance_m=75.0",
		"75 m event radius wrong: %s" % str(door.get("max_distance_m", "<missing>")))
	# T03 integration: the unit_size rule changed from "end of the leading 0 dB
	# plateau" (5.0 m here) to the least-squares fit of the one free parameter of
	# Godot's inverse-distance model over the audible part of the authored curve,
	# because the plateau rule produced 0.1 m for a curve with a knee and a -60 dB
	# tail. The fixture's curve (0/5/15/40/75 m at 0/0/-6/-20/-60 dB) fits 5.317 m;
	# the fit is exact at the knee for a two-point curve (see the real-data group).
	_check(is_equal_approx(float(door["unit_size"]), 5.31749486923218),
		"unit_size is the least-squares fit of the authored curve (5.317 m)",
		"unit_size wrong: %s" % str(door.get("unit_size", "<missing>")))
	var monotone: bool = curve.size() == 5
	var previous_gain: float = INF
	for point: Variant in curve:
		var gain: float = float((point as Dictionary)["gain_db"])
		if gain > previous_gain + 0.0001:
			monotone = false
		previous_gain = gain
	_check(monotone,
		"authored dB curve is monotone non-increasing over distance (%d points)" % curve.size(),
		"authored dB curve is not monotone: %s" % str(curve))

	var ui_event: Dictionary = aw.attenuation_for("Play_UI_Menu_Press")
	_check(bool(ui_event["found"]) and bool(ui_event["is_2d"]) and is_equal_approx(float(ui_event["max_distance_m"]), 0.0),
		"max_radius_cm=0 event reports is_2d",
		"2D event not resolved: %s" % str(ui_event))
	var unknown: Dictionary = aw.attenuation_for("Play_Does_Not_Exist")
	_check(not bool(unknown["found"]) and (unknown["curve"] as Array).is_empty() and is_equal_approx(float(unknown["max_distance_m"]), 0.0),
		"unknown event reports found=false with neutral values",
		"unknown event not neutral: %s" % str(unknown))

	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	var applied: bool = aw.apply_attenuation(player, "Play_Prop_Int_Door_Wood_Open")
	_check(applied and is_equal_approx(player.max_distance, 75.0) and is_equal_approx(player.unit_size, 5.31749486923218) and is_equal_approx(player.max_db, 0.0),
		"apply_attenuation stamps max_distance/unit_size/max_db on a 3D player",
		"apply_attenuation wrong: max=%s unit=%s max_db=%s" % [player.max_distance, player.unit_size, player.max_db])
	var applied_2d: bool = aw.apply_attenuation(player, "Play_UI_Menu_Press")
	_check(applied_2d and player.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED,
		"apply_attenuation disables distance attenuation for a 2D-authored event",
		"2D event stamped a distance model: %d" % player.attenuation_model)
	_check(not aw.apply_attenuation(player, "Play_Does_Not_Exist"),
		"apply_attenuation returns false for an unknown event",
		"apply_attenuation accepted an unknown event")
	player.free()

	# -- occlusion ---------------------------------------------------------
	_check(is_equal_approx(aw.occlusion_cutoff_hz(1.0), 20000.0),
		"occlusion_cutoff_hz(1.0) == 20000.0 (authored unity does not muffle)",
		"occlusion_cutoff_hz(1.0) = %f" % aw.occlusion_cutoff_hz(1.0))
	_check(is_equal_approx(aw.occlusion_gain_db(1.0), 0.0),
		"occlusion_gain_db(1.0) == 0 dB (unity transmission adds no extra authored loss)",
		"occlusion_gain_db(1.0) = %f" % aw.occlusion_gain_db(1.0))
	_check(absf(aw.occlusion_gain_db(0.5) - 6.0206) < 0.01,
		"occlusion_gain_db(0.5) == +6.02 dB energy model",
		"occlusion_gain_db(0.5) = %f" % aw.occlusion_gain_db(0.5))
	var occluded: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	var occluded_db: float = aw.apply_occlusion(occluded, true, 1.0)
	_check(is_equal_approx(occluded_db, -12.0) and is_equal_approx(occluded.attenuation_filter_cutoff_hz, 20000.0),
		"apply_occlusion(blocked, loss=1.0) adds the documented -12 dB without muffling",
		"apply_occlusion wrong: db=%f cutoff=%f" % [occluded_db, occluded.attenuation_filter_cutoff_hz])
	var open_db: float = aw.apply_occlusion(occluded, false, 1.0)
	_check(is_equal_approx(open_db, 0.0) and is_equal_approx(occluded.attenuation_filter_db, 0.0),
		"apply_occlusion(unblocked) clears the filter and adds 0 dB",
		"unblocked occlusion wrong: db=%f filter=%f" % [open_db, occluded.attenuation_filter_db])
	occluded.free()

	# -- VO, emitters, beds, music ----------------------------------------
	var vo: String = aw.vo_subtitle("Play_VO_Enforcer1_169_ThiefSeen_VisionStim_Heavy_01")
	_check(vo == "Enforcer1 · ThiefSeen · VisionStim · Heavy (01)",
		"vo_subtitle builds 'Enforcer1 · ThiefSeen · VisionStim · Heavy (01)'",
		"vo_subtitle wrong: '%s'" % vo)
	var vo_name: String = aw.vo_subtitle("Play_VO_Enforcer3_7_PatrolIdle_Calm_Light_03")
	_check(vo_name.begins_with("Enforcer3") and vo_name.ends_with("(03)"),
		"vo_subtitle derives a functional label from an authored name not in vo.lines",
		"name-derived vo_subtitle wrong: '%s'" % vo_name)
	_check(aw.vo_subtitle("Play_Prop_Int_Door_Wood_Open").is_empty(),
		"vo_subtitle is empty for a non-VO event",
		"vo_subtitle invented a label for a non-VO event")

	var emitters: Array = aw.emitters_for_map("guildhall")
	_check(emitters.size() == 2,
		"emitters_for_map('guildhall') returns the fixture's 2 emitters",
		"emitters_for_map('guildhall') returned %d" % emitters.size())
	var emitter_shape: bool = emitters.size() == 2
	if emitter_shape:
		emitter_shape = str(emitters[0]["actor"]) == "AkAmbientSound_0" \
			and str(emitters[0]["event"]) == "Play_Amb_BeautifulCorner_Exterior_Steam_Loop" \
			and emitters[0]["pos"] is Vector3 \
			and str(emitters[1]["actor"]) == "TATCCAudioComponent_1"
	_check(emitter_shape,
		"emitters are sorted by actor with {event, pos, actor} shape",
		"emitter shape/order wrong: %s" % str(emitters))
	_check(aw.emitters_for_map("atlantis").is_empty(),
		"an unlisted map returns no emitters (nothing invented)",
		"an unlisted map produced emitters")
	_check(aw.emitter_map_keys() == PackedStringArray(["Guildhall_Audio"]),
		"emitter_map_keys() exposes the raw dump basename",
		"emitter_map_keys() = %s" % str(aw.emitter_map_keys()))

	_check(aw.room_bed_for("guildhall") == "Play_Amb_AbbotsfordPark_Exterior_Rooftops",
		"room_bed_for('guildhall') resolves the authored bed",
		"room_bed_for('guildhall') = '%s'" % aw.room_bed_for("guildhall"))
	_check(aw.room_bed_for("atlantis").is_empty(),
		"room_bed_for returns '' for an unlisted map",
		"room_bed_for invented a bed for an unlisted map")

	_check(aw.music_event("title") == "Play_Mus_MainTitleScreen",
		"music_event('title') resolves the authored play event",
		"music_event('title') = '%s'" % aw.music_event("title"))
	_check(aw.music_event("nope").is_empty() and aw.music_event("guard_alerted").is_empty(),
		"music_event returns '' for an unknown kind and for an absent authored event",
		"music_event invented: nope='%s' guard_alerted='%s'" % [
			aw.music_event("nope"), aw.music_event("guard_alerted")])
	_check(aw.reverb_bus_for("exterior") == "VERB_Cmn_Ext_World",
		"reverb_bus_for('exterior') returns the authored exterior bus",
		"reverb_bus_for('exterior') = '%s'" % aw.reverb_bus_for("exterior"))
	_check(aw.reverb_bus_for("exterior", 7.9) == "VERB_Cmn_Ext_World",
		"reverb_bus_for('exterior', 7.9) picks the nearest authored decay (8.0 s)",
		"nearest-decay resolution failed: '%s'" % aw.reverb_bus_for("exterior", 7.9))
	_check(aw.reverb_bus_for("interior").is_empty() and aw.reverb_bus_for("bogus").is_empty(),
		"reverb_bus_for keeps the bus dry when the authored bus/kind is absent",
		"reverb_bus_for invented: interior='%s' bogus='%s'" % [
			aw.reverb_bus_for("interior"), aw.reverb_bus_for("bogus")])
	_check(aw.events_2d() == PackedStringArray(["Play_Mus_MainTitleScreen", "Play_UI_Menu_Press"]),
		"events_2d() lists the authored 2D events, sorted",
		"events_2d() = %s" % str(aw.events_2d()))

	# -- idempotency -------------------------------------------------------
	var signature_before: String = _bus_signature()
	var second_report: Dictionary = aw.build_buses()
	var signature_after: String = _bus_signature()
	_check(signature_before == signature_after and (second_report.get("buses", []) as Array).size() == 2,
		"build_buses() is idempotent (no bus/effect/send change on the second call)",
		"second build changed the bus graph:\n%s\n%s" % [signature_before, signature_after])

	# -- send topology (honest limitation) --------------------------------
	AudioServer.add_bus()
	var probe_idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(probe_idx, SEND_PROBE_BUS)
	AudioServer.set_bus_send(probe_idx, "Master")
	var send: Dictionary = aw.set_reverb_send(SEND_PROBE_BUS, "VERB_Cmn_Ext_World", -6.0)
	_check(bool(send.get("ok", false)) and AudioServer.get_bus_send(probe_idx) == "VERB_Cmn_Ext_World",
		"set_reverb_send re-parents a bus output into the authored reverb bus",
		"set_reverb_send failed: %s" % str(send))
	var routed_ok: bool = aw.route_bus_to_reverb(SEND_PROBE_BUS, "VERB_Cmn_Ext_World")
	_check(routed_ok,
		"route_bus_to_reverb returns a bool for the integrator's wiring",
		"route_bus_to_reverb did not return true")
	_check(str(send.get("limitation", "")).find("one output") >= 0,
		"set_reverb_send reports the single-output send limitation",
		"send limitation not documented: %s" % str(send))
	var master_send: bool = aw.route_bus_to_reverb("Master", "VERB_Cmn_Ext_World")
	_check(not master_send,
		"Master is refused as a send source (terminal bus, would cycle)",
		"Master was routed into a reverb bus")
	aw.set_reverb_send(SEND_PROBE_BUS, "VERB_Cmn_Ext_World", 0.0)
	AudioServer.remove_bus(probe_idx)

	# -- missing-file degradation -----------------------------------------
	var bus_count_before: int = AudioServer.bus_count
	var effect_count_before: int = _total_effect_count()
	var missing_ok: bool = aw.load_data("/nonexistent/audio_wwise.json")
	var reason: String = aw.degraded_reason()
	var degraded_report: Dictionary = aw.build_buses()
	_check(not missing_ok and not reason.is_empty(),
		"missing file returns false with a reason: %s" % reason,
		"missing file did not report a degraded reason")
	_check(not bool(degraded_report.get("built", true)) and int((degraded_report.get("buses", []) as Array).size()) == 0,
		"degraded build_buses() builds nothing",
		"degraded build_buses() reported a built graph")
	_check(AudioServer.bus_count == bus_count_before and _total_effect_count() == effect_count_before,
		"degraded build_buses() leaves the legacy bus layout untouched",
		"degraded build_buses() changed AudioServer")
	var neutral_ok: bool = not bool(aw.stats()["loaded"]) \
		and not bool(aw.attenuation_for("Play_Prop_Int_Door_Wood_Open")["found"]) \
		and aw.events_2d().is_empty() \
		and aw.emitters_for_map("guildhall").is_empty() \
		and aw.room_bed_for("guildhall").is_empty() \
		and aw.music_event("title").is_empty() \
		and aw.vo_subtitle("Play_VO_Enforcer1_169_ThiefSeen_VisionStim_Heavy_01").is_empty()
	_check(neutral_ok,
		"degraded getters return documented empty/neutral values",
		"a getter returned non-neutral data after a failed load")


# =========================================================================
# Real-data group (only when the produced file exists)
# =========================================================================


func _real_data_group() -> void:
	var env_path: String = OS.get_environment(AudioWwise.ENV_OVERRIDE).strip_edges()
	var path: String = ""
	for candidate: String in [env_path, AudioWwise.DEFAULT_PATH]:
		if not candidate.is_empty() and FileAccess.file_exists(candidate):
			path = candidate
			break
	if path.is_empty():
		print("SKIP real-data: no produced audio_wwise.json (env %s='%s', default '%s' absent)" % [
			AudioWwise.ENV_OVERRIDE, env_path, AudioWwise.DEFAULT_PATH])
		return

	print("--- real-data group: ", path)
	var aw: AudioWwise = AudioWwise.new()
	if not aw.load_data(path):
		_check(false, "", "real-data load failed: %s" % aw.degraded_reason())
		return
	var stats: Dictionary = aw.stats()
	var radii: PackedFloat32Array = aw.event_radii_m()
	print("REAL_DATA: buses=%d named_verb=%d attenuations=%d events=%d with_bus=%d with_attenuation=%d events_2d=%d vo=%d emitters=%d beds=%d music=%d fx=%d" % [
		int(stats["buses"]), int(stats["named_reverb_buses"]), int(stats["attenuations"]),
		int(stats["events"]), int(stats["events_with_bus"]), int(stats["events_with_attenuation"]),
		int(stats["events_2d"]), int(stats["vo_lines"]), int(stats["emitters"]),
		int(stats["room_beds"]), int(stats["music_play_events"]), int(stats["fx"])])
	print("REAL_DATA: radii_m=%s" % str(radii))

	_check(int(stats["buses"]) >= 130,
		"real data: >=130 buses parsed (%d)" % int(stats["buses"]),
		"real data: only %d buses" % int(stats["buses"]))
	_check(int(stats["named_reverb_buses"]) >= 16,
		"real data: >=16 named VERB_* buses parsed (%d)" % int(stats["named_reverb_buses"]),
		"real data: only %d named VERB_* buses" % int(stats["named_reverb_buses"]))
	_check(int(stats["attenuations"]) == 23,
		"real data: exactly 23 attenuations parsed (%d)" % int(stats["attenuations"]),
		"real data: %d attenuations (want 23)" % int(stats["attenuations"]))
	_check(radii.has(75.0) and radii.has(25.0) and radii.has(400.0),
		"real data: 75 m, 25 m and 400 m authored radii all present",
		"real data: a required authored radius is missing")
	_check(int(stats["events_with_bus"]) >= 500,
		"real data: >=500 events resolve a non-null bus (%d)" % int(stats["events_with_bus"]),
		"real data: only %d events with a bus" % int(stats["events_with_bus"]))
	_check(int(stats["events_with_attenuation"]) >= 100,
		"real data: >=100 events resolve a non-null attenuation (%d)" % int(stats["events_with_attenuation"]),
		"real data: only %d events with an attenuation" % int(stats["events_with_attenuation"]))
	_check(int(stats["vo_lines"]) >= 600,
		"real data: >=600 VO lines parsed (%d)" % int(stats["vo_lines"]),
		"real data: only %d VO lines" % int(stats["vo_lines"]))
	_check(int(stats["emitters"]) >= 90,
		"real data: >=90 placed emitters parsed (%d)" % int(stats["emitters"]),
		"real data: only %d emitters" % int(stats["emitters"]))


# =========================================================================
# Helpers
# =========================================================================


func _check(condition: bool, ok_msg: String, fail_msg: String) -> void:
	if condition:
		print("PASS: ", ok_msg)
		passed += 1
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _verb_bus_indices() -> Array:
	var out: Array = []
	for bus_idx: int in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(bus_idx).begins_with(VERB_PREFIX):
			out.append(bus_idx)
	return out


func _has_reverb(bus_idx: int) -> bool:
	for effect_idx: int in range(AudioServer.get_bus_effect_count(bus_idx)):
		if AudioServer.get_bus_effect(bus_idx, effect_idx) is AudioEffectReverb:
			return true
	return false


func _total_effect_count() -> int:
	var total: int = 0
	for bus_idx: int in range(AudioServer.bus_count):
		total += AudioServer.get_bus_effect_count(bus_idx)
	return total


func _bus_signature() -> String:
	var parts: PackedStringArray = PackedStringArray(["count=%d" % AudioServer.bus_count])
	for bus_idx: int in range(AudioServer.bus_count):
		parts.append("%s:effects=%d:send=%s" % [
			AudioServer.get_bus_name(bus_idx),
			AudioServer.get_bus_effect_count(bus_idx),
			str(AudioServer.get_bus_send(bus_idx)),
		])
	return "|".join(parts)


func _row_named(rows: Array, bus_name: String) -> Dictionary:
	for row: Variant in rows:
		if row is Dictionary and str((row as Dictionary).get("name", "")) == bus_name:
			return row
	return {}
