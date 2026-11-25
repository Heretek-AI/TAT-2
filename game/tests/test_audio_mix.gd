extends SceneTree
## T03 audio control-plane + mix-state truth test.
##
## Pins the six T03 runtime contracts against the *fixture* control plane
## (res://tests/fixtures/audio_wwise_sample.json), so it runs on a fresh clone
## with no generated data:
##
##   1. pause duck (AU4-05 / L5-06): the duck covers Ambience+SFX+Music by the
##      authored -19 dB and leaves UI/Dialogue up. The pre-T03 code ducked the
##      Ambience bus alone, so a bed or one-shot on another bus kept its level.
##   2. loading silence (AU1-03): begin_loading_silence() reaches digital zero
##      (no beds, no emitters, no music, gameplay buses muted) and the end of it
##      restores the saved levels.
##   3. authored attenuation (RE-M-02): a per-event radius/curve replaces the
##      single 60 m inverse-distance model, and an unknown event keeps the
##      documented legacy fallback.
##   4. authored emitters (RE-M-04): the placed emitters for a map spawn, stop,
##      and a map with none stays empty instead of inventing one.
##   5. music gating (RE-M-05): only authored Play_Mus_* events that resolve a
##      clip can start, and only one is live at a time.
##   6. degradation: with no control plane the runtime reports a reason and
##      falls back to the legacy bed keys instead of failing.
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_audio_mix.gd

const FIXTURE: String = "res://tests/fixtures/audio_wwise_sample.json"

var fails: int = 0
var passed: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		passed += 1
		print("PASS: ", ok_msg)
	else:
		fails += 1
		printerr("FAIL: ", fail_msg)


func _approx(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func _finish() -> void:
	print("AUDIO_MIX_SUMMARY: fails=%d passed=%d" % [fails, passed])
	quit(1 if fails > 0 else 0)


func _initialize() -> void:
	await process_frame
	var am: Node = root.get_node_or_null("AudioManager")
	if am == null:
		_check(false, "", "T03.0 AudioManager autoload missing")
		_finish()
		return

	# Deterministic sliders: 1.0 linear = 0 dB, so every asserted number is the
	# authored/duck value alone rather than a slider artefact.
	am.call("apply_volumes", 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)

	await _test_legacy_degradation(am)
	_test_fixture_load(am)
	await _test_pause_duck(am)
	await _test_loading_silence(am)
	_test_attenuation(am)
	_test_footstep_pools(am)
	_test_emitters(am)
	await _test_scene_bed_fallback(am)
	await _test_music(am)
	_finish()


## 6. With no control plane loaded the manager must stay fully functional and
## say why it is degraded.
func _test_legacy_degradation(am: Node) -> void:
	OS.set_environment("TAT2_AUDIO_WWISE_JSON", "res://tests/fixtures/__absent__.json")
	am.call("_load_wwise")
	am.call("_ensure_buses")
	_check(not bool(am.call("has_authored_audio")), "T03.6 no control plane -> has_authored_audio() false", "T03.6 expected the fixture to be absent")
	var st: Dictionary = am.call("mix_state") as Dictionary
	_check(not str(st.get("degraded_reason", "")).is_empty(), "T03.6 degraded_reason() explains the fallback", "T03.6 degraded_reason() was empty")
	am.call("play_bed_scene", "thieves_den")
	await process_frame
	var beds: Dictionary = am.call("active_bed_levels") as Dictionary
	_check(beds.has("den"), "T03.6 legacy path still starts the den bed", "T03.6 legacy bed did not start: %s" % str(beds.keys()))
	am.call("stop_all_beds", 0.0)


## 3/4/5 need the fixture loaded through the documented env override.
func _test_fixture_load(am: Node) -> void:
	OS.set_environment("TAT2_AUDIO_WWISE_JSON", FIXTURE)
	am.call("_load_wwise")
	am.call("_ensure_buses")
	_check(bool(am.call("has_authored_audio")), "T03.0 fixture control plane loads", "T03.0 fixture did not load: %s" % str(am.call("mix_state").get("degraded_reason", "")))
	var st: Dictionary = am.call("mix_state") as Dictionary
	for key: String in ["bus_levels_db", "pause_duck_db", "duck_buses", "interior", "music_kind", "emitters", "beds"]:
		_check(st.has(key), "T03.0 mix_state() exposes %s" % key, "T03.0 mix_state() missing %s" % key)


## 1. AU4-05: the pause duck is a gameplay duck over three buses.
func _test_pause_duck(am: Node) -> void:
	self.paused = false
	await process_frame
	var base_amb: float = float(am.call("bus_level_db", "Ambience"))
	var base_sfx: float = float(am.call("bus_level_db", "SFX"))
	var base_mus: float = float(am.call("bus_level_db", "Music"))
	var base_ui: float = float(am.call("bus_level_db", "UI"))
	self.paused = true
	await process_frame
	await process_frame
	var duck: float = float(am.call("mix_state").get("pause_duck_db", 0.0))
	_check(_approx(duck, -19.0), "T03.1 pause duck is the authored -19 dB", "T03.1 pause duck was %.2f dB" % duck)
	_check(_approx(float(am.call("bus_level_db", "Ambience")), base_amb - 19.0), "T03.1 Ambience ducks -19 dB", "T03.1 Ambience %.2f dB (want %.2f)" % [float(am.call("bus_level_db", "Ambience")), base_amb - 19.0])
	_check(_approx(float(am.call("bus_level_db", "SFX")), base_sfx - 19.0), "T03.1 SFX ducks -19 dB (pre-T03: untouched)", "T03.1 SFX %.2f dB (want %.2f)" % [float(am.call("bus_level_db", "SFX")), base_sfx - 19.0])
	_check(_approx(float(am.call("bus_level_db", "Music")), base_mus - 19.0), "T03.1 Music ducks -19 dB (pre-T03: untouched)", "T03.1 Music %.2f dB (want %.2f)" % [float(am.call("bus_level_db", "Music")), base_mus - 19.0])
	_check(_approx(float(am.call("bus_level_db", "UI")), base_ui), "T03.1 UI is not ducked (pause clicks)", "T03.1 UI moved to %.2f dB" % float(am.call("bus_level_db", "UI")))
	self.paused = false
	await process_frame
	await process_frame
	_check(_approx(float(am.call("bus_level_db", "Ambience")), base_amb), "T03.1 unpause restores Ambience", "T03.1 Ambience did not restore")
	_check(_approx(float(am.call("bus_level_db", "SFX")), base_sfx), "T03.1 unpause restores SFX", "T03.1 SFX did not restore")


## 2. AU1-03: loading owns the mix and reaches digital zero.
func _test_loading_silence(am: Node) -> void:
	am.call("play_bed_scene", "guildhall")
	await process_frame
	am.call("start_map_emitters", "guildhall")
	var before: int = int(am.call("active_emitters"))
	am.call("begin_loading_silence")
	await process_frame
	_check(bool(am.call("is_loading_silence")), "T03.2 loading silence is active", "T03.2 loading silence did not engage")
	_check(int(am.call("active_emitters")) == 0, "T03.2 loading stops every authored emitter", "T03.2 %d emitters survived loading" % int(am.call("active_emitters")))
	_check((am.call("active_bed_levels") as Dictionary).is_empty(), "T03.2 loading stops every bed", "T03.2 beds survived loading")
	_check(not bool(am.call("is_music_playing")), "T03.2 loading stops music", "T03.2 music survived loading")
	var idx_amb: int = AudioServer.get_bus_index("Ambience")
	var idx_sfx: int = AudioServer.get_bus_index("SFX")
	_check(idx_amb >= 0 and AudioServer.is_bus_mute(idx_amb), "T03.2 Ambience muted for digital zero", "T03.2 Ambience not muted")
	_check(idx_sfx >= 0 and AudioServer.is_bus_mute(idx_sfx), "T03.2 SFX muted for digital zero", "T03.2 SFX not muted")
	am.call("end_loading_silence")
	await process_frame
	_check(not bool(am.call("is_loading_silence")), "T03.2 loading silence clears", "T03.2 loading silence stuck")
	_check(not AudioServer.is_bus_mute(idx_amb), "T03.2 Ambience unmuted after loading", "T03.2 Ambience still muted")
	_check(int(am.call("active_emitters")) == 0 and before >= 0, "T03.2 emitters stay stopped until the next map scene", "T03.2 emitters restarted without a map")
	am.call("stop_all_beds", 0.0)


## 3. RE-M-02: authored radius per event, legacy fallback for the rest.
func _test_attenuation(am: Node) -> void:
	# The fixture's 75 m event is the authored case; read the name from the
	# fixture itself so the test cannot drift from the data it asserts on.
	var ev_name: String = ""
	var want_m: float = 0.0
	var f: FileAccess = FileAccess.open(FIXTURE, FileAccess.READ)
	if f != null:
		var doc: Variant = JSON.parse_string(f.get_as_text())
		if doc is Dictionary:
			for e: Variant in ((doc as Dictionary).get("events", []) as Array):
				if not (e is Dictionary):
					continue
				var ed: Dictionary = e
				if float(ed.get("max_radius_cm", 0.0)) > 0.0:
					ev_name = str(ed.get("name", ""))
					want_m = float(ed.get("max_radius_cm", 0.0)) / 100.0
					break
	_check(not ev_name.is_empty(), "T03.3 fixture carries a 3D event to assert on", "T03.3 fixture has no 3D event")
	if ev_name.is_empty():
		return
	var info: Dictionary = (am.call("authored_attenuation", ev_name) as Dictionary)
	_check(bool(info.get("found", false)), "T03.3 authored attenuation resolves for %s" % ev_name, "T03.3 authored attenuation missing for %s" % ev_name)
	_check(_approx(float(info.get("max_distance_m", 0.0)), want_m, 0.05), "T03.3 authored radius is %.1f m (not the 60 m fallback)" % want_m, "T03.3 radius %.2f m (want %.2f)" % [float(info.get("max_distance_m", 0.0)), want_m])
	var p := AudioStreamPlayer3D.new()
	root.add_child(p)
	var applied: bool = bool(am.call("_apply_authored_attenuation", p, ev_name))
	_check(applied, "T03.3 authored attenuation stamps the 3D player", "T03.3 stamp returned false for a known event")
	_check(_approx(p.max_distance, want_m, 0.05), "T03.3 player max_distance is the authored radius", "T03.3 player max_distance %.2f" % p.max_distance)
	var q := AudioStreamPlayer3D.new()
	root.add_child(q)
	var legacy: bool = bool(am.call("_apply_authored_attenuation", q, "Play_Mus_NoSuchEvent_XYZ"))
	_check(not legacy, "T03.3 unknown event keeps the legacy model", "T03.3 unknown event claimed an authored attenuation")
	_check(_approx(q.max_distance, 60.0, 0.5), "T03.3 unknown event radius is 60 m", "T03.3 legacy radius %.1f" % q.max_distance)
	p.queue_free()
	q.queue_free()


## 4. RE-M-09: the widen keys reach every authored FS family that has media.
## Pre-T03 the pools held 466 entries / 290 distinct clips; the Tile, Marble,
## ShallowWater, Mud, MetalPipe and WoodBeam media were decoded and unplayable,
## and crouch had no stone pool at all.
func _test_footstep_pools(am: Node) -> void:
	var pools_v: Variant = am.get("_foot_pools")
	if not (pools_v is Dictionary):
		_check(false, "", "T03.4b footstep pools are not a Dictionary")
		return
	var pools: Dictionary = pools_v as Dictionary
	var distinct: Dictionary = {}
	var entries: int = 0
	for key: Variant in pools.keys():
		var pool: Array = pools[key] as Array
		entries += pool.size()
		for clip: Variant in pool:
			distinct[str(clip)] = true
	_check(pools.has("walk|stone") and (pools["walk|stone"] as Array).size() >= 16, "T03.4b walk|stone pool >= 16 clips (measured 16, pre-T03 8: Tile/Marble were unreachable)", "T03.4b walk|stone pool missing or below 16")
	_check(pools.has("run|wet") and (pools["run|wet"] as Array).size() >= 90, "T03.4b run|wet pool >= 90 clips (measured 99, pre-T03 33: the ShallowWater family was unreachable)", "T03.4b run|wet pool missing or below 90")
	_check(entries >= 650, "T03.4b footstep pool entries >= 650 (measured 695, pre-T03 466; got %d)" % entries, "T03.4b footstep entries %d below the 650 floor" % entries)
	_check(distinct.size() >= 460, "T03.4b distinct footstep clips >= 460 (measured 495, pre-T03 290; got %d)" % distinct.size(), "T03.4b distinct footstep clips %d below the 460 floor" % distinct.size())


## 4. RE-M-04: placed emitters per map, none invented.
func _test_emitters(am: Node) -> void:
	am.call("stop_map_emitters")
	var started: int = int(am.call("start_map_emitters", "guildhall"))
	_check(started == 2, "T03.4 the fixture's two Guildhall emitters start (got %d)" % started, "T03.4 started %d of 2 fixture emitters" % started)
	_check(int(am.call("active_emitters")) == started, "T03.4 active_emitters matches the start count", "T03.4 emitter count mismatch")
	var none: int = int(am.call("start_map_emitters", "no_such_map"))
	_check(none == 0 and int(am.call("active_emitters")) == 0, "T03.4 a map with no authored emitters starts none", "T03.4 invented emitters for an unknown map")
	am.call("stop_map_emitters")


## 5. RE-M-04 fallback: a map whose authored dump has no emitter the contract can
## read and no room bed (the Thieves' Den) keeps its legacy bed instead of going
## silent. This is the bug an empty-string `or` produced ("false" is truthy).
func _test_scene_bed_fallback(am: Node) -> void:
	am.call("play_bed_scene", "thieves_den")
	await process_frame
	var den_beds: Dictionary = am.call("active_bed_levels") as Dictionary
	_check(den_beds.has("den"), "T03.4c authored mode still starts the Den bed (fallback), got %s" % str(den_beds.keys()), "T03.4c the Den went silent under the authored path")
	am.call("play_bed_scene", "guildhall")
	await process_frame
	var gh_beds: Dictionary = am.call("active_bed_levels") as Dictionary
	_check(gh_beds.has("authored_room"), "T03.4c Guildhall uses the authored room bed (%s)" % str(gh_beds.keys()), "T03.4c Guildhall did not start the authored room bed")
	_check(int(am.call("active_emitters")) > 0, "T03.4c Guildhall starts authored emitters", "T03.4c no emitters for Guildhall")
	am.call("stop_all_beds", 0.0)


## 5. RE-M-05: only authored Play_Mus_* events with a clip can start.
func _test_music(am: Node) -> void:
	am.call("stop_music", 0.0)
	_check(not bool(am.call("play_music_event", "Play_VO_Enforcer1_169_ThiefSeen_VisionStim_Heavy_01")), "T03.5 a non-music event is refused", "T03.5 a VO event started as music")
	_check(not bool(am.call("play_music_event", "Play_Mus_EventThatDoesNotExist")), "T03.5 an unauthored Play_Mus_ event is refused", "T03.5 an unauthored music event started")
	var ok: bool = bool(am.call("start_music", "title", -10.0, 0.0))
	if ok:
		_check(str(am.call("music_kind")) == "title", "T03.5 title music starts and reports its kind", "T03.5 music kind was %s" % str(am.call("music_kind")))
		_check(bool(am.call("is_music_playing")), "T03.5 is_music_playing true", "T03.5 is_music_playing false")
		am.call("stop_music", 0.0)
		await process_frame
		_check(not bool(am.call("is_music_playing")), "T03.5 stop_music ends it", "T03.5 music survived stop_music")
	else:
		_check(false, "", "T03.5 authored title event Play_Mus_MainTitleScreen did not resolve a clip")
