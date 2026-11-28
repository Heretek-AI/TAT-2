extends SceneTree
## W10 P3-AUD gate: the authored Wwise control plane.
##
## Pins the four contracts the lane owes, against the real generated document
## (`res://data/generated/audio_control.json`, schema `tat2.audio_control/1`,
## produced by `tools/parse_audio_control.py`):
##
##   1. Control inventory: the measured named counts — 14 switch groups, 4
##      state groups, 16 RTPCs — plus the group/value names the wiring uses.
##      The brief's "5 state groups" is NOT reproducible from the extraction:
##      there are 4 named AkStateValue groups (Player_HeightenedSenses,
##      Player_Downed, Weather_isExterior, Modal_State) and 4 more state-group
##      ids the bank references with no asset dump. The test asserts the
##      measured 4 and prints the discrepancy rather than inventing a fifth.
##   2. Fail-closed setters: an unknown group, value or RTPC changes nothing.
##   3. Switch-aware media selection: `Play_FS_Player_Walk` with
##      FS_Material=Stone keeps the Stone surface family and drops Carpet, Tile,
##      Dirt, Mud, Grass, Sludge and water clips; WoodFloor gives a different set.
##   4. RTPC curve application: the authored music-node curve drives gain and
##      pitch, an authored id-only low-pass curve drives the filter Hz, and
##      Constant/edge evaluation matches the authored points.
##   5. W11-B music: 2 MusicSwitchContainers, 9 DecisionTree keys (6 resolved,
##      3 id-only), the authored 2000 ms transition and the single stinger.
##   6. W11-C `FS_Layers`: the surface -> layer mapping and the measured
##      44 -> 52 media step (Stone + Puddle).
##   7. W11-D RTPCs: stamina/crouch/fall/rain/disguise exact curve values.
##   8. W11-E state rows: the 183-row census and the 24 deferred unnamed buses.
##
## Then the runtime wiring (`AudioManager`): the control plane loads, the
## footstep path still resolves clips (no cue regression), interior/exterior and
## the pause modal state reach the control plane, and the detection RTPC drives
## the music gain. Suite 50/`test_audio_mix.gd` stay the floors for the existing
## cue and bus contracts; this suite adds the control plane on top.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/test_audio_control.gd"

const CONTROL_PATH: String = "res://data/generated/audio_control.json"
const EVENTS_PATH: String = "res://data/generated/audio_events.json"
const FOOTSTEP_EVENT: String = "Play_FS_Player_Walk"
const DETECTION_RTPC: String = "Character_Enemy_Detection_Level_RTPC"
const DETECTION_MUSIC_NODE: String = "MusicRandomSequenceContainer:248405997"
## Authored id-only RTPC with a low-pass curve (no AkRtpc dump, so it is emitted
## by id under unnamed_rtpcs; its curve is points [-90,44] ... [90,0]).
const LPF_RTPC: int = 2141048674
## W11-C: the surface resolver owns the FS_Layers mapping.
const SurfaceResolverScript := preload("res://src/stealth/surface_resolver.gd")
## Phase 3B.3: the ONE preset -> RTPC/visual rain converter lives in WeatherProfile.
const WeatherProfileScript := preload("res://src/core/weather_profile.gd")

## Surface families that must NOT survive FS_Material=Stone.
const NOT_STONE: Array[String] = ["carpet", "tile", "dirt", "mud", "grassrustle",
	"shallowwater", "puddle_walk", "slime", "metalgrate", "metalpipe",
	"electricalwire", "woodfloor", "woodbeam", "woodobject", "car-"]

var fails: int = 0
var checks: int = 0
var _media_names: Dictionary = {}


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", ok_msg)
	else:
		fails += 1
		printerr("FAIL: ", fail_msg)


func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var ctl: AudioControl = AudioControl.new()
	var ok: bool = ctl.load_data()
	_check(ok, "AUD1 control document loads (%s)" % CONTROL_PATH,
		"AUD1 audio_control.json did not load: %s" % ctl.degraded_reason())
	if not ok:
		_finish(ctl)
		return
	_load_media_names()
	_test_inventory(ctl)
	_test_groups(ctl)
	_test_fail_closed(ctl)
	_test_selection(ctl)
	_test_curves(ctl)
	_test_music(ctl)
	_test_layers(ctl)
	_test_rtpc_callers(ctl)
	_test_rain_converter(ctl)
	_test_state_report(ctl)
	await _test_runtime(ctl)
	_test_degraded(ctl)
	await _finish(ctl)


## 1. Measured inventory. The document counts are the producer's verified table;
## the accessor counts are the consumer's own index and must agree with it.
func _test_inventory(ctl: AudioControl) -> void:
	var counts: Dictionary = ctl.counts()
	_check(int(counts.get("switch_groups", 0)) == 14,
		"AUD1.1 14 named switch groups (measured; 23 group ids referenced by the bank)",
		"AUD1.1 switch_groups=%d (want 14)" % int(counts.get("switch_groups", 0)))
	_check(int(counts.get("switch_values", 0)) == 84,
		"AUD1.1 84 named switch values (measured)",
		"AUD1.1 switch_values=%d (want 84)" % int(counts.get("switch_values", 0)))
	_check(int(counts.get("state_groups", 0)) == 4,
		"AUD1.1 4 named state groups (measured; the brief's 5 is not in the extraction)",
		"AUD1.1 state_groups=%d (want the measured 4)" % int(counts.get("state_groups", 0)))
	_check(int(counts.get("state_values", 0)) == 10,
		"AUD1.1 10 named state values (measured)",
		"AUD1.1 state_values=%d (want 10)" % int(counts.get("state_values", 0)))
	_check(int(counts.get("rtpcs", 0)) == 16,
		"AUD1.1 16 named RTPCs (34 more are bank ids with no asset dump)",
		"AUD1.1 rtpcs=%d (want 16)" % int(counts.get("rtpcs", 0)))
	_check(int(counts.get("rtpc_curves", 0)) == 142,
		"AUD1.1 142 authored node/param curves (de-duplicated per curve, not per param)",
		"AUD1.1 rtpc_curves=%d (want 142)" % int(counts.get("rtpc_curves", 0)))
	_check(int(counts.get("switch_containers", 0)) == 185,
		"AUD1.1 185 switch containers carry a group + package (1 unset object excluded)",
		"AUD1.1 switch_containers=%d (want 185)" % int(counts.get("switch_containers", 0)))
	_check(ctl.switch_group_count() == 14 and ctl.state_group_count() == 4 and ctl.rtpc_count() == 16,
		"AUD1.2 accessor counts agree (switch=%d state=%d rtpc=%d)" % [
			ctl.switch_group_count(), ctl.state_group_count(), ctl.rtpc_count()],
		"AUD1.2 accessor counts disagree: %d/%d/%d" % [
			ctl.switch_group_count(), ctl.state_group_count(), ctl.rtpc_count()])
	_check(ctl.rtpc_names().size() == 16,
		"AUD1.2 rtpc_names() lists exactly the 16 named RTPCs",
		"AUD1.2 rtpc_names()=%d" % ctl.rtpc_names().size())


## 2. The groups/values the wiring depends on, by authored name.
func _test_groups(ctl: AudioControl) -> void:
	var material: Array = ctl.switch_value_names("FS_Material")
	_check(material.size() == 14 and material.has("Stone") and material.has("Carpet")
		and material.has("Tile") and material.has("WoodFloor"),
		"AUD2.1 FS_Material carries 14 authored values (Stone/Carpet/Tile/WoodFloor present)",
		"AUD2.1 FS_Material values=%s" % str(material))
	var gait: Array = ctl.switch_value_names("Character_Movement_Mode")
	var want_gait: Array = ["Crouch", "Jog", "Run", "Walk", "WallClimb"]
	_check(gait == want_gait,
		"AUD2.2 Character_Movement_Mode == Crouch/Jog/Run/Walk/WallClimb",
		"AUD2.2 gaits=%s" % str(gait))
	var env: Array = ctl.state_value_names("Weather_isExterior")
	_check(env == ["Exterior", "Interior"],
		"AUD2.3 Weather_isExterior == Exterior/Interior",
		"AUD2.3 env states=%s" % str(env))
	var modal: Array = ctl.state_value_names("Modal_State")
	_check(modal == ["Modal_Gameplay", "Modal_Menu"],
		"AUD2.4 Modal_State == Modal_Gameplay/Modal_Menu",
		"AUD2.4 modal states=%s" % str(modal))
	var senses: Array = ctl.state_value_names("Player_HeightenedSenses")
	_check(senses.size() == 4,
		"AUD2.5 Player_HeightenedSenses has 4 authored states (%s)" % str(senses),
		"AUD2.5 heightened senses states=%s" % str(senses))
	# Switch state is per-group and independent.
	_check(ctl.set_switch("FS_Material", "Stone") and ctl.set_switch("FS_Material", "Carpet"),
		"AUD2.6 a switch can be changed to any authored value",
		"AUD2.6 set_switch failed for an authored value")
	_check(ctl.switch_value("FS_Material") == "Carpet",
		"AUD2.6 switch_value() reports the last authored value",
		"AUD2.6 switch_value()=%s" % ctl.switch_value("FS_Material"))
	_check(ctl.switch_value("Character_Movement_Mode") == "",
		"AUD2.6 an unset group reports \"\" (not a guessed default)",
		"AUD2.6 unset group reported %s" % ctl.switch_value("Character_Movement_Mode"))
	# Authored state property rows: exposed for a consumer, not applied globally.
	_check(ctl.set_state("Player_HeightenedSenses", "Listening"),
		"AUD2.7 Player_HeightenedSenses accepts the Listening state",
		"AUD2.7 set_state(Listening) refused")
	var rows: Array = ctl.state_override_rows("Player_HeightenedSenses")
	var volume_rows: int = 0
	var well_formed: bool = not rows.is_empty()
	for row_v: Variant in rows:
		if not (row_v is Dictionary):
			well_formed = false
			break
		var row: Dictionary = row_v as Dictionary
		if str(row.get("node", "")).find(":") < 0 or str(row.get("param", "")).is_empty():
			well_formed = false
			break
		if str(row.get("param", "")) == "volume_db":
			volume_rows += 1
	_check(well_formed and volume_rows > 0,
		"AUD2.7 Listening exposes %d authored override rows (%d volume)" % [rows.size(), volume_rows],
		"AUD2.7 override rows malformed: %s" % str(rows.slice(0, 2)))
	ctl.set_state("Player_HeightenedSenses", "Normal")
	var normal_rows: Array = ctl.state_override_rows("Player_HeightenedSenses")
	_check(normal_rows.size() != rows.size(),
		"AUD2.7 a different state exposes a different row set (%d vs %d)" % [normal_rows.size(), rows.size()],
		"AUD2.7 Normal and Listening expose the same rows")


## 3. Fail-closed setters: an unknown id/name never mutates state.
func _test_fail_closed(ctl: AudioControl) -> void:
	ctl.set_switch("FS_Material", "Stone")
	_check(not ctl.set_switch("FS_Material", "Lava"),
		"AUD3.1 unknown switch value is refused",
		"AUD3.1 set_switch accepted a value that does not exist")
	_check(ctl.switch_value("FS_Material") == "Stone",
		"AUD3.1 refused value leaves the previous switch intact",
		"AUD3.1 refused value changed the switch to %s" % ctl.switch_value("FS_Material"))
	_check(not ctl.set_switch("NoSuchGroup", "Stone"),
		"AUD3.2 unknown switch group is refused",
		"AUD3.2 set_switch accepted an unknown group")
	ctl.set_state("Weather_isExterior", "Interior")
	_check(not ctl.set_state("Weather_isExterior", "Underwater"),
		"AUD3.3 unknown state value is refused",
		"AUD3.3 set_state accepted a value that does not exist")
	_check(ctl.state_value("Weather_isExterior") == "Interior",
		"AUD3.3 refused state leaves the previous state intact",
		"AUD3.3 refused state changed to %s" % ctl.state_value("Weather_isExterior"))
	_check(not ctl.set_rtpc("NoSuchRtpc", 1.0),
		"AUD3.4 unknown RTPC name is refused",
		"AUD3.4 set_rtpc accepted an unknown name")
	_check(not ctl.set_rtpc(123456789, 1.0),
		"AUD3.5 unknown RTPC id is refused",
		"AUD3.5 set_rtpc accepted an unknown id")


## 4. Switch-aware media selection on a known event.
func _test_selection(ctl: AudioControl) -> void:
	var media: Array = _event_media(FOOTSTEP_EVENT)
	_check(media.size() >= 300,
		"AUD4.0 %s carries %d media ids (a 319-media event)" % [FOOTSTEP_EVENT, media.size()],
		"AUD4.0 footstep event only has %d media ids" % media.size())
	if media.is_empty():
		return
	_select(ctl, "Stone")
	var stone: Array = ctl.select_media(FOOTSTEP_EVENT, media)
	_check(not stone.is_empty() and stone.size() < media.size(),
		"AUD4.1 FS_Material=Stone narrows %d media to %d" % [media.size(), stone.size()],
		"AUD4.1 Stone selection kept %d of %d media (expected a strict subset)" % [
			stone.size(), media.size()])
	var stone_clips: int = 0
	var leaked: Array = []
	for mid: Variant in stone:
		var name: String = str(_media_names.get(int(mid), "")).to_lower()
		if name.find("stone") >= 0:
			stone_clips += 1
		for family: String in NOT_STONE:
			if name.find(family) >= 0:
				leaked.append(name)
				break
	_check(stone_clips >= 8,
		"AUD4.2 Stone selection keeps %d Stone clips" % stone_clips,
		"AUD4.2 Stone selection only kept %d Stone clips" % stone_clips)
	_check(leaked.is_empty(),
		"AUD4.3 Stone selection drops every non-Stone surface family",
		"AUD4.3 Stone selection leaked %d non-Stone clips, e.g. %s" % [
			leaked.size(), str(leaked.slice(0, 4))])
	_select(ctl, "WoodFloor")
	var wood: Array = ctl.select_media(FOOTSTEP_EVENT, media)
	var wood_names: Array = []
	for mid: Variant in wood:
		wood_names.append(str(_media_names.get(int(mid), "")).to_lower())
	var wood_beam: int = 0
	var wood_stone: int = 0
	for name: String in wood_names:
		if name.find("woodbeam") >= 0:
			wood_beam += 1
		if name.find("stone") >= 0:
			wood_stone += 1
	_check(not wood.is_empty() and wood != stone,
		"AUD4.4 FS_Material=WoodFloor selects a different set (%d media)" % wood.size(),
		"AUD4.4 WoodFloor and Stone selected the same media")
	_check(wood_beam >= 8 and wood_stone == 0,
		"AUD4.5 WoodFloor keeps the bank's WoodBeam family (%d) and no Stone clip" % wood_beam,
		"AUD4.5 WoodFloor selection: woodbeam=%d stone=%d" % [wood_beam, wood_stone])
	# A group left unset must use the authored DefaultSwitch, never an invention.
	var fresh: AudioControl = AudioControl.new()
	fresh.load_data()
	var defaults: Array = fresh.select_media(FOOTSTEP_EVENT, media)
	_check(not defaults.is_empty() and defaults.size() <= media.size(),
		"AUD4.6 unset groups resolve the authored DefaultSwitch (%d media)" % defaults.size(),
		"AUD4.6 default resolution failed")
	_check(ctl.media_ids_for(FOOTSTEP_EVENT, "FS_Material", "Stone").size() >= 8,
		"AUD4.7 media_ids_for() exposes the authored Stone package",
		"AUD4.7 media_ids_for() found no Stone package media")
	# W11-C: the authored FS_Layers branch is additive: Stone 44 -> +Puddle 52.
	_select(ctl, "Stone")
	var stone_exact: Array = ctl.select_media(FOOTSTEP_EVENT, media)
	_check(stone_exact.size() == 44,
		"AUD4.8 FS_Material=Stone selects exactly the measured 44 media",
		"AUD4.8 Stone selection=%d (want 44)" % stone_exact.size())
	ctl.set_switch("FS_Layers", "Puddle")
	var stone_puddle: Array = ctl.select_media(FOOTSTEP_EVENT, media)
	_check(stone_puddle.size() == 52,
		"AUD4.9 Stone + FS_Layers=Puddle selects exactly the measured 52 media",
		"AUD4.9 Stone+Puddle selection=%d (want 52)" % stone_puddle.size())
	var layer_ids: Array = ctl.media_ids_for(FOOTSTEP_EVENT, "FS_Layers", "Puddle")
	var layer_set: Dictionary = {}
	for mid: Variant in layer_ids:
		layer_set[int(mid)] = true
	var added: Array = []
	for mid: Variant in stone_puddle:
		if not stone_exact.has(int(mid)):
			added.append(int(mid))
	var all_authored: bool = true
	for mid: Variant in added:
		if not layer_set.has(int(mid)):
			all_authored = false
	_check(added.size() == 8 and all_authored,
		"AUD4.10 the Puddle layer adds exactly 8 recordings, all from its authored package",
		"AUD4.10 added=%d all_authored=%s (package carries %d; it is a per-container superset)" % [
			added.size(), str(all_authored), layer_ids.size()])
	ctl.set_switch("FS_Layers", "Nothing")


## 5. RTPC curves: authored gain, pitch and low-pass evaluation.
func _test_curves(ctl: AudioControl) -> void:
	_check(ctl.set_rtpc(DETECTION_RTPC, 0.0),
		"AUD5.1 detection RTPC accepts 0.0",
		"AUD5.1 set_rtpc(%s) refused" % DETECTION_RTPC)
	_check(_approx(ctl.rtpc_value(DETECTION_RTPC), 0.0),
		"AUD5.1 rtpc_value() reads back the set value",
		"AUD5.1 rtpc_value()=%f" % ctl.rtpc_value(DETECTION_RTPC))
	_check(_approx(ctl.gain_db(DETECTION_RTPC, DETECTION_MUSIC_NODE), -1.0),
		"AUD5.2 authored music-node gain at 0 is -1.0 dB",
		"AUD5.2 gain at 0 = %f dB (want -1.0)" % ctl.gain_db(DETECTION_RTPC, DETECTION_MUSIC_NODE))
	_check(_approx(ctl.pitch_scale(DETECTION_RTPC, "MusicRandomSequenceContainer:405990808"), 1.0),
		"AUD5.2 authored music-node pitch at 0 is unity",
		"AUD5.2 pitch at 0 = %f" % ctl.pitch_scale(DETECTION_RTPC, "MusicRandomSequenceContainer:405990808"))
	ctl.set_rtpc(DETECTION_RTPC, 0.6)
	var want_gain: float = -1.0 + (0.6 - 0.20189) / (1.0 - 0.20189)
	_check(_approx(ctl.gain_db(DETECTION_RTPC, DETECTION_MUSIC_NODE), want_gain, 0.002),
		"AUD5.3 authored curve interpolates at 0.6 (%.4f dB)" % want_gain,
		"AUD5.3 gain at 0.6 = %f (want %.4f)" % [
			ctl.gain_db(DETECTION_RTPC, DETECTION_MUSIC_NODE), want_gain])
	var want_pitch: float = pow(2.0, (62.0 + (0.6 - 0.17547) / (1.0 - 0.17547) * 24.0) / 1200.0)
	_check(_approx(ctl.pitch_scale(DETECTION_RTPC, "MusicRandomSequenceContainer:405990808"), want_pitch, 0.002),
		"AUD5.3 authored pitch curve at 0.6 is %.4f" % want_pitch,
		"AUD5.3 pitch at 0.6 = %f (want %.4f)" % [
			ctl.pitch_scale(DETECTION_RTPC, "MusicRandomSequenceContainer:405990808"), want_pitch])
	ctl.set_rtpc(DETECTION_RTPC, 1.0)
	_check(_approx(ctl.gain_db(DETECTION_RTPC, DETECTION_MUSIC_NODE), 0.0),
		"AUD5.4 authored gain at full detection is 0 dB",
		"AUD5.4 gain at 1 = %f" % ctl.gain_db(DETECTION_RTPC, DETECTION_MUSIC_NODE))
	# Constant segments and out-of-range clamping are exact (Wwise semantics).
	var constant_points: Array = [[0.0, 0.0], [0.5, 10.0], [1.0, 10.0]]
	var constant_interp: Array = ["Constant", "Linear", "Linear"]
	_check(_approx(ctl.evaluate_curve(constant_points, constant_interp, 0.25), 0.0),
		"AUD5.5 a Constant segment holds the left value",
		"AUD5.5 Constant at 0.25 = %f" % ctl.evaluate_curve(constant_points, constant_interp, 0.25))
	_check(_approx(ctl.evaluate_curve(constant_points, constant_interp, 0.75), 10.0),
		"AUD5.5 a Linear segment interpolates",
		"AUD5.5 Linear at 0.75 = %f" % ctl.evaluate_curve(constant_points, constant_interp, 0.75))
	_check(_approx(ctl.evaluate_curve(constant_points, constant_interp, -1.0), 0.0)
		and _approx(ctl.evaluate_curve(constant_points, constant_interp, 2.0), 10.0),
		"AUD5.6 values outside the authored range clamp to the endpoints",
		"AUD5.6 out-of-range evaluation did not clamp")
	# Low-pass: the named 16 have no LPF curve; the authored id-only RTPC does.
	_check(_approx(ctl.low_pass_hz(DETECTION_RTPC), 0.0),
		"AUD5.7 the detection RTPC has no authored low-pass curve (0 Hz = none)",
		"AUD5.7 detection low-pass = %f" % ctl.low_pass_hz(DETECTION_RTPC))
	_check(ctl.set_rtpc(LPF_RTPC, -90.0),
		"AUD5.8 the id-only low-pass RTPC accepts a value",
		"AUD5.8 set_rtpc(%d) refused" % LPF_RTPC)
	var want_hz: float = 20.0 * pow(2.0, 44.0 / 10.0)
	_check(_approx(ctl.low_pass_hz(LPF_RTPC), want_hz, 0.5),
		"AUD5.8 authored 44%% filter -> %.1f Hz" % want_hz,
		"AUD5.8 low-pass = %.1f Hz (want %.1f)" % [ctl.low_pass_hz(LPF_RTPC), want_hz])
	var lpf_a: float = ctl.low_pass_hz(LPF_RTPC)
	var lpf_b: float = ctl.low_pass_hz(LPF_RTPC)
	_check(_approx(lpf_a, lpf_b),
		"AUD5.9 low-pass evaluation is deterministic (%.3f Hz twice)" % lpf_a,
		"AUD5.9 low-pass evaluation drifted: %.3f vs %.3f" % [lpf_a, lpf_b])
	var report: Dictionary = ctl.curve_report()
	_check(int(report.get("calls", 0)) > 0,
		"AUD5.9 curve evaluator counted %d calls" % int(report.get("calls", 0)),
		"AUD5.9 curve report did not count calls")


## 6. W11-B: the authored MusicSwitchContainers (DecisionTree keys, transitions,
## stingers) and the fail-closed selection.
func _test_music(ctl: AudioControl) -> void:
	var counts: Dictionary = ctl.counts()
	_check(int(counts.get("music_containers", 0)) == 2,
		"AUD7.1 2 authored MusicSwitchContainers",
		"AUD7.1 music_containers=%d (want 2)" % int(counts.get("music_containers", 0)))
	_check(int(counts.get("music_keys", 0)) == 9
		and int(counts.get("music_resolved_keys", 0)) == 6
		and int(counts.get("music_unresolved_keys", 0)) == 3,
		"AUD7.1 9 decision keys: 6 resolve to a named value, 3 stay id-only",
		"AUD7.1 keys=%d resolved=%d unresolved=%d (want 9/6/3)" % [
			int(counts.get("music_keys", 0)), int(counts.get("music_resolved_keys", 0)),
			int(counts.get("music_unresolved_keys", 0))])
	_check(ctl.music_containers().size() == 2,
		"AUD7.1 music_containers() exposes both containers",
		"AUD7.1 music_containers()=%d" % ctl.music_containers().size())
	_check(ctl.music_container_for_group("Music_Switch_Phase") == 369450896
		and ctl.music_container_for_group("Music_Switch_Escape") == 1052896423,
		"AUD7.2 the two authored groups map to their container ids",
		"AUD7.2 Phase=%d Escape=%d" % [
			ctl.music_container_for_group("Music_Switch_Phase"),
			ctl.music_container_for_group("Music_Switch_Escape")])
	_check(ctl.music_container_for_event("Play_Mus_TVT_Match_Generic_Mission_MX") == 369450896
		and ctl.music_container_for_event("Play_Mus_EndMission_Escape") == 1052896423,
		"AUD7.2 the authored play events bind to their containers",
		"AUD7.2 event bindings=%d/%d" % [
			ctl.music_container_for_event("Play_Mus_TVT_Match_Generic_Mission_MX"),
			ctl.music_container_for_event("Play_Mus_EndMission_Escape")])
	# A resolved key selects the authored value and its audio node.
	var early: Dictionary = ctl.music_select("Music_Switch_Phase", "Music_Switch_Phase_Early")
	_check(bool(early.get("found", false))
		and int(early.get("key", 0)) == 3143687845
		and int(early.get("audio_node_id", 0)) == 664990907
		and (early.get("play_events", []) as Array).has("Play_Mus_TVT_Match_Generic_Mission_MX"),
		"AUD7.3 Phase=Early resolves key 3143687845 -> node 664990907",
		"AUD7.3 Phase=Early=%s" % str(early))
	var mid: Dictionary = ctl.music_select("Music_Switch_Escape", "Escape_Mid")
	_check(bool(mid.get("found", false)) and int(mid.get("key", 0)) == 1699409647,
		"AUD7.3 Escape=Mid resolves key 1699409647",
		"AUD7.3 Escape=Mid=%s" % str(mid))
	# The three unresolved keys stay id-only: selecting by id is refused.
	var unresolved: Dictionary = ctl.music_select("Music_Switch_Phase", 1363461318)
	_check(not bool(unresolved.get("found", false))
		and str(unresolved.get("reason", "")) == "unresolved_key"
		and int(unresolved.get("key", 0)) == 1363461318,
		"AUD7.4 an unresolved decision key is refused with its id (no invented name)",
		"AUD7.4 unresolved=%s" % str(unresolved))
	var unknown_group: Dictionary = ctl.music_select("Music_Switch_NoSuch", "Whatever")
	_check(not bool(unknown_group.get("found", false))
		and str(unknown_group.get("reason", "")) == "unknown_group",
		"AUD7.4 an unknown music group is refused",
		"AUD7.4 unknown group=%s" % str(unknown_group))
	var unknown_value: Dictionary = ctl.music_select("Music_Switch_Escape", "Escape_NoSuch")
	_check(not bool(unknown_value.get("found", false))
		and str(unknown_value.get("reason", "")) == "unknown_value",
		"AUD7.4 an unknown music value is refused",
		"AUD7.4 unknown value=%s" % str(unknown_value))
	# Transitions: the authored fade is exact (2000 ms on the Phase container).
	var phase_rule: Dictionary = ctl.music_transition(369450896)
	_check(bool(phase_rule.get("found", false))
		and _approx(float(phase_rule.get("fade_ms", 0.0)), 2000.0)
		and str(phase_rule.get("fade_source", "")) == "src"
		and str(phase_rule.get("fade_curve", "")) == "Linear",
		"AUD7.5 the Phase container authors a 2000 ms Linear transition",
		"AUD7.5 phase transition=%s" % str(phase_rule))
	var escape_rule: Dictionary = ctl.music_transition(1052896423)
	_check(bool(escape_rule.get("found", false))
		and _approx(float(escape_rule.get("fade_ms", -1.0)), 0.0)
		and str(escape_rule.get("fade_source", "")) == "none"
		and str(escape_rule.get("src_sync", "")) == "ExitMarker",
		"AUD7.5 the Escape container authors a 0 ms ExitMarker transition",
		"AUD7.5 escape transition=%s" % str(escape_rule))
	_check(not bool(ctl.music_transition(123456).get("found", false)),
		"AUD7.6 an unknown music container has no transition",
		"AUD7.6 unknown container returned a transition")
	# Stingers: one authored row, trigger id-only, segment duration from the bank.
	var stingers: Array = ctl.music_stingers(369450896)
	var stinger_ok: bool = stingers.size() == 1
	if stinger_ok:
		var row: Dictionary = stingers[0] as Dictionary
		stinger_ok = int(row.get("trigger_id", 0)) == 547253114 \
			and int(row.get("segment_id", 0)) == 797529307 \
			and _approx(float(row.get("segment_duration_ms", 0.0)), 8000.0) \
			and str(row.get("sync_play_at", "")) == "NextBeat" \
			and row.get("trigger_name", "") == null
	_check(stinger_ok,
		"AUD7.7 the Phase container authors 1 stinger (trigger id-only, 8 s segment, NextBeat)",
		"AUD7.7 stingers=%s" % str(stingers))
	_check(ctl.music_stingers(1052896423).is_empty(),
		"AUD7.7 the Escape container authors no stinger",
		"AUD7.7 Escape stingers=%s" % str(ctl.music_stingers(1052896423)))


## 7. W11-C: the authored FS_Layers value per surface.
func _test_layers(ctl: AudioControl) -> void:
	var resolvers: Array = [
		["Puddle", "Puddle"], ["GroundWet", "Puddle"], ["BrokenGlass", "Glass_Broken"],
		["Foliage", "Foliage"], ["Grass", "Grass"], ["Stone", "Nothing"],
		["WoodFloor", "Nothing"], ["NotASurface", "Nothing"],
	]
	var wrong: Array = []
	for pair: Array in resolvers:
		var got: String = str(SurfaceResolverScript.layer_for(str(pair[0])))
		if got != str(pair[1]):
			wrong.append("%s=%s" % [str(pair[0]), got])
	_check(wrong.is_empty(),
		"AUD8.1 layer_for() maps the authored wet/glass/foliage/grass surfaces (8 cases)",
		"AUD8.1 wrong layer mapping: %s" % str(wrong))
	_check(SurfaceResolverScript.layer_values() == PackedStringArray(
		["Glass_Broken", "Grass", "Foliage", "Nothing", "Puddle"]),
		"AUD8.2 the resolver produces exactly the five documented layer values",
		"AUD8.2 layer_values()=%s" % str(SurfaceResolverScript.layer_values()))
	var names: Array = ctl.switch_value_names("FS_Layers")
	_check(names.size() == 10 and names.has("Puddle") and names.has("Glass_Broken")
		and names.has("Foliage") and names.has("Grass") and names.has("Nothing"),
		"AUD8.3 FS_Layers carries the 10 authored values (5 produced, 5 documented)",
		"AUD8.3 FS_Layers=%s" % str(names))
	# Phase 3B.3: prove or refute the "double-ban" rationale for the five values
	# the port does not produce (MetalPipe, MetalSheet, Glass, Metal, Slime).
	#
	# The claim was: a shared FS_Material family re-selected as a layer would ban
	# the same clips twice and empty the selection. Measured from the authored
	# switch containers it is REFUTED: the ban is confined to the FS_Layers
	# branch, so material-selected media is never removed. The real reasons the
	# five stay unproduced are recorded in docs/reports/phase3-audio-20261127.md.
	var media: Array = _event_media(FOOTSTEP_EVENT)
	_select(ctl, "Stone")
	var base: Array = ctl.select_media(FOOTSTEP_EVENT, media)
	var lost_any: Array = []
	var zero_media_values: Array[String] = ["MetalPipe", "MetalSheet", "Metal", "Slime"]
	for value: String in zero_media_values:
		_select(ctl, "Stone")
		ctl.set_switch("FS_Layers", value)
		var sel: Array = ctl.select_media(FOOTSTEP_EVENT, media)
		var added: int = 0
		for mid: Variant in sel:
			if not base.has(int(mid)):
				added += 1
		if added != 0:
			lost_any.append("%s +%d" % [value, added])
		if sel.size() != base.size():
			lost_any.append("%s size %d != %d" % [value, sel.size(), base.size()])
		for mid: Variant in base:
			if not sel.has(int(mid)):
				lost_any.append("%s lost %d" % [value, int(mid)])
	_check(lost_any.is_empty() and base.size() == 44,
		"AUD8.4 FS_Layers=MetalPipe/MetalSheet/Metal/Slime changes nothing (44 -> 44): no double-ban",
		"AUD8.4 double-ban or divergence measured: %s" % str(lost_any))
	# Glass is the one shared value whose layer package carries media on the
	# footstep events: it is purely additive (+5, 0 lost), which also refutes a
	# ban (the claim would predict a shrinking set).
	_select(ctl, "Stone")
	ctl.set_switch("FS_Layers", "Glass")
	var glass: Array = ctl.select_media(FOOTSTEP_EVENT, media)
	var glass_lost: int = 0
	for mid: Variant in base:
		if not glass.has(int(mid)):
			glass_lost += 1
	_check(glass.size() == base.size() + 5 and glass_lost == 0,
		"AUD8.5 FS_Layers=Glass is additive (+5 recordings, 0 lost): a layer never bans material media",
		"AUD8.5 Glass selection=%d lost=%d (want %d / 0)" % [glass.size(), glass_lost, base.size() + 5])
	# The container-side census: the four zero-media values own no recording on
	# this event, so producing them could not change playback; Glass owns 5.
	var census_wrong: Array = []
	for value: String in zero_media_values:
		if ctl.media_ids_for(FOOTSTEP_EVENT, "FS_Layers", value).size() != 0:
			census_wrong.append(value)
	if ctl.media_ids_for(FOOTSTEP_EVENT, "FS_Layers", "Glass").size() != 5:
		census_wrong.append("Glass")
	_check(census_wrong.is_empty(),
		"AUD8.6 the authored FS_Layers containers own 0 media for MetalPipe/MetalSheet/Metal/Slime and 5 for Glass",
		"AUD8.6 layer media census mismatch: %s" % str(census_wrong))
	ctl.set_switch("FS_Layers", "Nothing")


## 8. W11-D: the five authored mix parameters and their exact curve values.
func _test_rtpc_callers(ctl: AudioControl) -> void:
	var stamina := "Character_Stamina_RTPC"
	_check(ctl.set_rtpc(stamina, 63.67521),
		"AUD9.1 the stamina RTPC accepts the authored 0..100 domain",
		"AUD9.1 set_rtpc(%s) refused" % stamina)
	_check(_approx(ctl.gain_db(stamina), -0.317507, 0.00001),
		"AUD9.2 stamina 63.67521 -> exactly -0.317507 dB",
		"AUD9.2 stamina gain=%f" % ctl.gain_db(stamina))
	ctl.set_rtpc(stamina, 100.0)
	_check(_approx(ctl.gain_db(stamina), -1.0),
		"AUD9.2 stamina 100 -> exactly -1.0 dB",
		"AUD9.2 stamina 100 gain=%f" % ctl.gain_db(stamina))
	ctl.set_rtpc(stamina, 50.0)
	var want_half: float = -0.317507 * 50.0 / 63.67521
	_check(_approx(ctl.gain_db(stamina), want_half, 0.00001),
		"AUD9.2 stamina 50 -> %.6f dB (authored linear segment)" % want_half,
		"AUD9.2 stamina 50 gain=%f (want %.6f)" % [ctl.gain_db(stamina), want_half])

	var crouch := "Character_FS_isCrouching"
	ctl.set_rtpc(crouch, 0.0)
	_check(_approx(ctl.gain_db(crouch, "ActorMixer:492723062"), 0.0),
		"AUD9.3 crouch 0 -> 0 dB",
		"AUD9.3 crouch 0 gain=%f" % ctl.gain_db(crouch, "ActorMixer:492723062"))
	ctl.set_rtpc(crouch, 1.0)
	_check(_approx(ctl.gain_db(crouch, "ActorMixer:492723062"), -0.608844, 0.00001),
		"AUD9.3 crouch 1 -> exactly -0.608844 dB",
		"AUD9.3 crouch 1 gain=%f" % ctl.gain_db(crouch, "ActorMixer:492723062"))

	var fall := "Character_Fall_Velocity_Z"
	var fall_node := "LayerContainer:350464786"
	ctl.set_rtpc(fall, -5000.0)
	_check(_approx(ctl.gain_db(fall, fall_node), 0.498813, 0.00001)
		and _approx(ctl.pitch_scale(fall, fall_node), pow(2.0, -100.0 / 1200.0), 0.00001),
		"AUD9.4 fall -5000 cm/s -> +0.498813 dB and -100 cents",
		"AUD9.4 fall -5000 gain=%f pitch=%f" % [
			ctl.gain_db(fall, fall_node), ctl.pitch_scale(fall, fall_node)])
	ctl.set_rtpc(fall, -500.0)
	_check(_approx(ctl.gain_db(fall, fall_node), -1.0)
		and _approx(ctl.pitch_scale(fall, fall_node), pow(2.0, -2.0 / 1200.0), 0.00001),
		"AUD9.4 fall -500 cm/s -> exactly -1.0 dB and -2 cents",
		"AUD9.4 fall -500 gain=%f" % ctl.gain_db(fall, fall_node))
	ctl.set_rtpc(fall, 500.0)
	_check(_approx(ctl.gain_db(fall, fall_node), -1.0),
		"AUD9.4 fall 500 cm/s clamps to the authored tail (-1.0 dB)",
		"AUD9.4 fall 500 gain=%f" % ctl.gain_db(fall, fall_node))

	var rain := "Weather_Rain_Intensity"
	ctl.set_rtpc(rain, 0.0)
	_check(_approx(ctl.gain_db(rain), -1.0),
		"AUD9.5 rain 0 -> -1.0 dB",
		"AUD9.5 rain 0 gain=%f" % ctl.gain_db(rain))
	ctl.set_rtpc(rain, 0.65)
	_check(_approx(ctl.gain_db(rain), 0.0),
		"AUD9.5 rain 0.65 -> exactly 0 dB (authored breakpoint)",
		"AUD9.5 rain 0.65 gain=%f" % ctl.gain_db(rain))
	ctl.set_rtpc(rain, 0.3)
	var want_rain: float = -1.0 + (0.3 / 0.65)
	_check(_approx(ctl.gain_db(rain), want_rain, 0.00001),
		"AUD9.5 rain 0.3 -> %.6f dB (authored linear segment)" % want_rain,
		"AUD9.5 rain 0.3 gain=%f (want %.6f)" % [ctl.gain_db(rain), want_rain])

	var disguise := "Character_DisguiseIntegrity"
	ctl.set_rtpc(disguise, 0.0)
	_check(_approx(ctl.gain_db(disguise), 0.0),
		"AUD9.6 disguise curve x=0 -> 0 dB",
		"AUD9.6 disguise 0 gain=%f" % ctl.gain_db(disguise))
	ctl.set_rtpc(disguise, 1.0)
	_check(_approx(ctl.gain_db(disguise), -1.0, 0.00001),
		"AUD9.6 disguise curve x=1 -> exactly -1.0 dB (authored 0..1 domain)",
		"AUD9.6 disguise 1.0 gain=%f" % ctl.gain_db(disguise))
	# Restore the authored rests so later runtime assertions see a clean table.
	# The disguise value is the authored 0..1 domain, never the player's 0..100
	# unit (the manager normalises at the call site; AUD6.11 pins that).
	ctl.set_rtpc(stamina, 100.0)
	ctl.set_rtpc(crouch, 0.0)
	ctl.set_rtpc(fall, 0.0)
	ctl.set_rtpc(rain, 0.0)
	ctl.set_rtpc(disguise, 1.0)
	_check(_approx(ctl.rtpc_value(disguise), 1.0),
		"AUD9.6 the disguise RTPC is left at the authored 1.0 (not 100.0)",
		"AUD9.6 disguise rest value=%f" % ctl.rtpc_value(disguise))


## 9b. Phase 3B.3: the ONE preset -> authored-0..1 rain converter.
##
## The authored `Weather_Rain_Intensity` curve is 0..1 (AUD9.5). Every shipped
## preset is in that domain except `blood_moon`, which authors 10.0. The
## converter passes in-domain values through, saturates an out-of-domain value
## at the endpoint, and reports it — it never invents a unit for 10.0.
func _test_rain_converter(ctl: AudioControl) -> void:
	WeatherProfileScript.reset_rain_domain_warnings()
	# The real authored preset (read from disk, never regenerated here).
	var blood_moon: Dictionary = WeatherProfileScript.load_preset("blood_moon")
	_check(not blood_moon.is_empty(),
		"AUD9.7 the authored blood_moon preset loads",
		"AUD9.7 blood_moon preset missing")
	_check(_approx(float(WeatherProfileScript.rain_intensity(blood_moon)), 10.0, 0.0001),
		"AUD9.7 the raw authored blood_moon rain.intensity is 10.0 (out of domain)",
		"AUD9.7 raw rain.intensity=%s (want 10.0)" % str(WeatherProfileScript.rain_intensity(blood_moon)))
	var converted_blood: Variant = WeatherProfileScript.rain_intensity_01(blood_moon)
	_check(converted_blood != null and _approx(float(converted_blood), 1.0, 0.000001),
		"AUD9.7 blood_moon 10.0 converts to 1.0 (documented domain saturation)",
		"AUD9.7 blood_moon converted to %s (want 1.0)" % str(converted_blood))
	# The documented unit cases: 0 -> 0, 1 -> 1, and an in-domain pass-through.
	var cases: Array = [[0.0, 0.0], [1.0, 1.0], [0.5, 0.5], [0.65, 0.65]]
	var wrong: Array = []
	for pair: Array in cases:
		var got: Variant = WeatherProfileScript.rain_intensity_01(
			{"preset": "case", "rain": {"intensity": float(pair[0])}})
		if got == null or not _approx(float(got), float(pair[1]), 0.000001):
			wrong.append("%s->%s" % [str(pair[0]), str(got)])
	_check(wrong.is_empty(),
		"AUD9.8 the converter maps 0->0, 1->1, 0.5->0.5 and 0.65->0.65 (in-domain unchanged)",
		"AUD9.8 wrong in-domain conversions: %s" % str(wrong))
	# A preset without the field stays null (the caller keeps its default).
	_check(WeatherProfileScript.rain_intensity_01({"preset": "no_rain"}) == null,
		"AUD9.8 a preset with no rain.intensity converts to null",
		"AUD9.8 a missing field produced %s" % str(WeatherProfileScript.rain_intensity_01({"preset": "no_rain"})))
	# A negative value saturates at the low endpoint and is reported too.
	var neg: Variant = WeatherProfileScript.rain_intensity_01(
		{"preset": "negative_case", "rain": {"intensity": -2.0}})
	_check(neg != null and _approx(float(neg), 0.0, 0.000001),
		"AUD9.8 a negative intensity saturates at 0.0",
		"AUD9.8 negative converted to %s" % str(neg))
	# Warning path: every out-of-domain occurrence is counted and the preset id
	# is recorded once (one loud line per preset, the count keeps incrementing).
	var before: int = WeatherProfileScript.rain_domain_warnings()
	WeatherProfileScript.rain_intensity_01(blood_moon)
	WeatherProfileScript.rain_intensity_01(blood_moon)
	WeatherProfileScript.rain_intensity_01({"preset": "ten_again", "rain": {"intensity": 10.0}})
	var after: int = WeatherProfileScript.rain_domain_warnings()
	var warned: Array = WeatherProfileScript.rain_domain_warned_presets()
	_check(after - before == 3 and warned.has("blood_moon") and warned.has("ten_again"),
		"AUD9.9 the out-of-domain path warns and counts each occurrence (%d -> %d, presets=%s)" % [
			before, after, str(warned)],
		"AUD9.9 warning count %d -> %d, presets=%s" % [before, after, str(warned)])
	# In-domain presets never take the warning path.
	var quiet_before: int = WeatherProfileScript.rain_domain_warnings()
	for name: String in ["gloomy", "heavy_rain", "stormy", "dusk_stormy", "midnight_clear"]:
		var p: Dictionary = WeatherProfileScript.load_preset(name)
		WeatherProfileScript.rain_intensity_01(p)
	_check(WeatherProfileScript.rain_domain_warnings() == quiet_before,
		"AUD9.9 the five shipped in-domain presets take no warning path",
		"AUD9.9 in-domain presets incremented the warning count")
	# End to end: the converted 10.0 reaches the authored curve's 0 dB endpoint.
	ctl.set_rtpc("Weather_Rain_Intensity", float(converted_blood))
	_check(_approx(ctl.gain_db("Weather_Rain_Intensity"), 0.0, 0.000001),
		"AUD9.9 the converted blood_moon value evaluates the authored 1.0 endpoint (0 dB)",
		"AUD9.9 converted value gave %f dB" % ctl.gain_db("Weather_Rain_Intensity"))
	# Leave the authored rest value for the later runtime assertions.
	ctl.set_rtpc("Weather_Rain_Intensity", 0.0)
	WeatherProfileScript.reset_rain_domain_warnings()


## 9. W11-E: the counted state-override table and the deferred unnamed buses.
func _test_state_report(ctl: AudioControl) -> void:
	var report: Dictionary = ctl.state_override_report()
	_check(int(report.get("rows", 0)) == 183,
		"AUD10.1 the state table has 183 authored row references",
		"AUD10.1 rows=%d (want 183)" % int(report.get("rows", 0)))
	_check(int(report.get("nodes", 0)) == 62,
		"AUD10.1 those rows target 62 authored nodes",
		"AUD10.1 nodes=%d (want 62)" % int(report.get("nodes", 0)))
	_check(int(report.get("audio_bus_rows", 0)) == 98
		and int(report.get("audio_bus_nodes", 0)) == 24,
		"AUD10.2 98 rows target 24 AudioBus nodes",
		"AUD10.2 bus rows=%d nodes=%d (want 98/24)" % [
			int(report.get("audio_bus_rows", 0)), int(report.get("audio_bus_nodes", 0))])
	_check(int(report.get("other_rows", 0)) == 85,
		"AUD10.2 the other 85 rows target non-bus nodes",
		"AUD10.2 other_rows=%d (want 85)" % int(report.get("other_rows", 0)))
	var deferred: Dictionary = report.get("deferred", {}) as Dictionary
	_check(int(deferred.get("unnamed_buses", 0)) == 24
		and int(deferred.get("rows", 0)) == 98,
		"AUD10.3 the 24 unnamed buses are deferred with their row count (98)",
		"AUD10.3 deferred=%s" % str(deferred))
	var groups: Dictionary = report.get("groups", {}) as Dictionary
	_check(groups.size() == 7
		and int(groups.get("Player_HeightenedSenses", 0)) == 113
		and int(groups.get("Player_Downed", 0)) == 16
		and int(groups.get("Weather_isExterior", 0)) == 10
		and int(groups.get("Modal_State", 0)) == 7
		and int(groups.get("354100577", 0)) == 7,
		"AUD10.3 7 authored state groups with the measured per-group rows",
		"AUD10.3 groups=%s" % str(groups))
	# The existing per-selection API is unchanged.
	ctl.set_state("Player_HeightenedSenses", "Listening")
	var rows: Array = ctl.state_override_rows("Player_HeightenedSenses")
	_check(not rows.is_empty(),
		"AUD10.4 state_override_rows() still returns the selected state's rows",
		"AUD10.4 state_override_rows() returned nothing")
	ctl.set_state("Player_HeightenedSenses", "Normal")


## 6. Runtime wiring: AudioManager consumes the control plane without breaking
## the existing cue/pool contracts.
func _test_runtime(ctl: AudioControl) -> void:
	var am: Node = root.get_node_or_null("AudioManager")
	_check(am != null, "AUD6.0 AudioManager autoload present", "AUD6.0 AudioManager missing")
	if am == null:
		return
	_check(bool(am.call("has_control_plane")),
		"AUD6.1 AudioManager loaded the control plane",
		"AUD6.1 AudioManager control plane missing: %s" % str(am.call("control_state")))
	var state: Dictionary = am.call("mix_state") as Dictionary
	_check(state.has("control") and bool((state["control"] as Dictionary).get("loaded", false)),
		"AUD6.1 mix_state().control reports the loaded plane",
		"AUD6.1 mix_state() control block missing or not loaded")
	# No cue regression: the nine shipped tags still resolve, and the token
	# pools keep the T03 floors (the control filter must not shrink them).
	var real: int = 0
	for tag: String in ["footstep", "blackjack", "lockpick", "grapple", "smoke",
			"fairy", "alert", "loot", "door"]:
		if bool(am.call("has_real_clip", tag)):
			real += 1
	_check(real == 9,
		"AUD6.2 all 9 shipped gameplay tags still resolve a real clip",
		"AUD6.2 only %d of 9 tags resolve" % real)
	var pools_v: Variant = am.get("_foot_pools")
	var pools: Dictionary = {}
	if pools_v is Dictionary:
		pools = pools_v as Dictionary
	var entries: int = 0
	for key: Variant in pools.keys():
		entries += (pools[key] as Array).size()
	_check(pools.has("walk|stone") and (pools["walk|stone"] as Array).size() >= 16,
		"AUD6.2 walk|stone pool unchanged (>= 16)",
		"AUD6.2 walk|stone pool=%d" % ((pools.get("walk|stone", []) as Array).size()))
	_check(pools.has("run|wet") and (pools["run|wet"] as Array).size() >= 90,
		"AUD6.2 run|wet pool unchanged (>= 90)",
		"AUD6.2 run|wet pool=%d" % ((pools.get("run|wet", []) as Array).size()))
	_check(entries >= 650,
		"AUD6.2 footstep pool entries unchanged (>= 650, got %d)" % entries,
		"AUD6.2 footstep entries %d below the 650 floor" % entries)
	var foot: bool = bool(am.call("play_footstep", "stone", "walk", Vector3(1.0, 0.0, 1.0)))
	_check(foot, "AUD6.3 play_footstep('stone','walk') still plays",
		"AUD6.3 play_footstep refused under the control plane")
	var ctl_state: Dictionary = am.call("control_state") as Dictionary
	var switches: Dictionary = ctl_state.get("switches", {}) as Dictionary
	_check(str(switches.get("Stone", "")) == "FS_Material",
		"AUD6.3 the footstep path set FS_Material=Stone",
		"AUD6.3 footstep switches=%s" % str(switches))
	# Interior/exterior -> authored state.
	am.call("set_environment", true)
	ctl_state = am.call("control_state") as Dictionary
	var states: Dictionary = ctl_state.get("states", {}) as Dictionary
	_check(str(states.get("Interior", "")) == "Weather_isExterior",
		"AUD6.4 set_environment(true) sets Weather_isExterior=Interior",
		"AUD6.4 states=%s" % str(states))
	am.call("set_environment", false)
	ctl_state = am.call("control_state") as Dictionary
	states = ctl_state.get("states", {}) as Dictionary
	_check(str(states.get("Exterior", "")) == "Weather_isExterior",
		"AUD6.4 set_environment(false) sets Weather_isExterior=Exterior",
		"AUD6.4 states=%s" % str(states))
	# Pause -> authored modal state.
	self.paused = true
	await process_frame
	await process_frame
	ctl_state = am.call("control_state") as Dictionary
	states = ctl_state.get("states", {}) as Dictionary
	_check(str(states.get("Modal_Menu", "")) == "Modal_State",
		"AUD6.5 paused sets Modal_State=Modal_Menu",
		"AUD6.5 states after pause=%s" % str(states))
	self.paused = false
	await process_frame
	await process_frame
	ctl_state = am.call("control_state") as Dictionary
	states = ctl_state.get("states", {}) as Dictionary
	_check(str(states.get("Modal_Gameplay", "")) == "Modal_State",
		"AUD6.5 unpaused sets Modal_State=Modal_Gameplay",
		"AUD6.5 states after unpause=%s" % str(states))
	# Detection RTPC -> authored music gain.
	_check(bool(am.call("set_detection_level", 0.6)),
		"AUD6.6 AudioManager.set_detection_level(0.6) accepted",
		"AUD6.6 set_detection_level refused")
	state = am.call("mix_state") as Dictionary
	_check(_approx(float(state.get("detection_level", -1.0)), 0.6, 0.0001),
		"AUD6.6 mix_state().detection_level is 0.6",
		"AUD6.6 detection_level=%f" % float(state.get("detection_level", -1.0)))
	_check(_approx(float(state.get("rtpc_music_gain_db", 0.0)), -0.501190, 0.002),
		"AUD6.6 authored music gain at 0.6 is -0.501 dB",
		"AUD6.6 rtpc_music_gain_db=%f" % float(state.get("rtpc_music_gain_db", 0.0)))
	am.call("set_detection_level", 0.0)
	# W11-C: the footstep path sets the authored FS_Layers value, and the
	# authored layer recordings play as their own branch.
	am.call("play_footstep", "wet", "walk", Vector3(2.0, 0.0, 2.0))
	ctl_state = am.call("control_state") as Dictionary
	switches = ctl_state.get("switches", {}) as Dictionary
	_check(str(switches.get("Puddle", "")) == "FS_Layers",
		"AUD6.7 a wet surface sets FS_Layers=Puddle",
		"AUD6.7 switches=%s" % str(switches))
	am.call("play_footstep", "stone", "walk", Vector3(3.0, 0.0, 3.0), "Puddle")
	var layer_pools_v: Variant = am.get("_layer_pools")
	var layer_pools: Dictionary = layer_pools_v as Dictionary if layer_pools_v is Dictionary else {}
	var puddle_pool: Array = layer_pools.get("walk|stone|Puddle", []) as Array
	_check(puddle_pool.size() == 8,
		"AUD6.8 Stone + Puddle builds the authored 8-recording layer pool",
		"AUD6.8 layer pool=%d (%s)" % [puddle_pool.size(), str(layer_pools.keys())])
	# W11-D: the five authored parameters are exposed with their exact curves.
	am.call("set_rtpc", "Character_Stamina_RTPC", 63.67521)
	var mix: Dictionary = am.call("mix_state") as Dictionary
	var rtpc: Dictionary = mix.get("rtpc", {}) as Dictionary
	var stamina_block: Dictionary = rtpc.get("Character_Stamina_RTPC", {}) as Dictionary
	_check(rtpc.size() == 5
		and _approx(float(stamina_block.get("gain_db", 0.0)), -0.317507, 0.00001),
		"AUD6.9 mix_state().rtpc reports the 5 authored parameters with exact curves",
		"AUD6.9 rtpc=%s" % str(rtpc))
	am.call("set_rtpc", "Character_Stamina_RTPC", 100.0)
	# W11-D: the player's 0..100 disguise unit must be normalised into the
	# authored 0..1 RTPC domain. Feeding the raw value would saturate every
	# integrity >= 1 at the curve's 1.0 endpoint and never traverse it.
	var domain: Array = [[0.0, 0.0], [25.0, 0.25], [50.0, 0.5], [75.0, 0.75], [100.0, 1.0]]
	var domain_wrong: Array = []
	var state_now: Dictionary = {}
	var values: Dictionary = {}
	for pair: Array in domain:
		am.call("push_disguise_integrity", float(pair[0]))
		var stored: float = -1.0
		state_now = am.call("control_state") as Dictionary
		values = state_now.get("rtpc_values", {}) as Dictionary
		stored = float(values.get("Character_DisguiseIntegrity", -1.0))
		if not _approx(stored, float(pair[1]), 0.00001):
			domain_wrong.append("%d->%.2f" % [int(pair[0]), stored])
	_check(domain_wrong.is_empty(),
		"AUD6.11 disguise 0/25/50/75/100 stores 0/0.25/0.5/0.75/1.0",
		"AUD6.11 wrong stored domain: %s" % str(domain_wrong))
	am.call("push_disguise_integrity", 25.0)
	mix = am.call("mix_state") as Dictionary
	rtpc = mix.get("rtpc", {}) as Dictionary
	var disguise_block: Dictionary = rtpc.get("Character_DisguiseIntegrity", {}) as Dictionary
	# The authored first curve is [0,0] [0.39834,-1] [1,-1]; x=0.25 is mid-knee.
	var want_disguise_gain: float = -1.0 * 0.25 / 0.39834
	var got_disguise_gain: float = float(disguise_block.get("gain_db", 0.0))
	_check(_approx(got_disguise_gain, want_disguise_gain, 0.0001)
		and not _approx(got_disguise_gain, -1.0, 0.0001),
		"AUD6.11 disguise 25 -> %.6f dB (mid-curve, not the -1 dB endpoint)" % want_disguise_gain,
		"AUD6.11 disguise 25 gain=%f (want %.6f, endpoint is -1.0)" % [
			got_disguise_gain, want_disguise_gain])
	# The signal handler itself must normalise, not just the helper.
	am.call("_on_disguise_changed", 75.0, true)
	state_now = am.call("control_state") as Dictionary
	values = state_now.get("rtpc_values", {}) as Dictionary
	_check(_approx(float(values.get("Character_DisguiseIntegrity", -1.0)), 0.75, 0.00001),
		"AUD6.11 the disguise_changed handler stores 75 as 0.75",
		"AUD6.11 handler stored %s" % str(values.get("Character_DisguiseIntegrity", -1.0)))
	am.call("push_disguise_integrity", 100.0)
	# W11-B: the authored Phase transition (2000 ms) is the music fade.
	var authored_fade: float = float(am.call("music_fade_for_event",
		"Play_Mus_TVT_Match_Generic_Mission_MX"))
	_check(_approx(authored_fade, 2.0),
		"AUD6.10 the Phase music event authors a 2.0 s fade",
		"AUD6.10 authored fade=%f" % authored_fade)
	_check(bool(am.call("start_music", "mission")),
		"AUD6.10 start_music('mission') plays the authored event",
		"AUD6.10 start_music('mission') refused")
	mix = am.call("mix_state") as Dictionary
	var music: Dictionary = mix.get("music", {}) as Dictionary
	_check(_approx(float(music.get("fade_s", -1.0)), 2.0)
		and int(music.get("container_id", 0)) == 369450896,
		"AUD6.10 the runtime music player uses the authored 2.0 s fade",
		"AUD6.10 mix_state().music=%s" % str(music))
	am.call("stop_music", 0.0)


## 7. Degradation: no document -> identity selection and a stated reason.
func _test_degraded(ctl: AudioControl) -> void:
	OS.set_environment("TAT2_AUDIO_CONTROL_JSON", "res://tests/fixtures/__absent__.json")
	var absent: AudioControl = AudioControl.new()
	_check(not absent.load_data(),
		"AUD7.1 an absent control document degrades instead of failing",
		"AUD7.1 load_data() claimed a missing file")
	_check(not absent.degraded_reason().is_empty(),
		"AUD7.1 degraded_reason() explains the fallback (%s)" % absent.degraded_reason(),
		"AUD7.1 degraded_reason() was empty")
	var ids: Array = [1, 2, 3]
	_check(absent.select_media(FOOTSTEP_EVENT, ids) == ids,
		"AUD7.2 degraded select_media() returns the input unchanged",
		"AUD7.2 degraded select_media() changed the input")
	OS.set_environment("TAT2_AUDIO_CONTROL_JSON", "")
	_check(ctl.load_data(),
		"AUD7.3 the real document reloads after the degraded probe",
		"AUD7.3 reload of %s failed: %s" % [CONTROL_PATH, ctl.degraded_reason()])


## Puts the five groups the footstep selection depends on into a known state.
func _select(ctl: AudioControl, material: String) -> void:
	ctl.set_switch("FS_Material", material)
	ctl.set_switch("Character_Movement_Mode", "Walk")
	ctl.set_switch("Character_Select", "Player_Cotter")
	ctl.set_switch("Character_IsLocallyControlled", "Local")
	ctl.set_switch("FS_Layers", "Nothing")


## MediaId -> DebugName from the events join (read-only).
func _load_media_names() -> void:
	_media_names.clear()
	var text: String = FileAccess.get_file_as_string(EVENTS_PATH)
	if text.is_empty():
		return
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		return
	for ev: Variant in ((doc as Dictionary).get("events", []) as Array):
		if not (ev is Dictionary):
			continue
		for m: Variant in ((ev as Dictionary).get("media", []) as Array):
			if not (m is Dictionary):
				continue
			_media_names[int((m as Dictionary).get("media_id", 0))] = str(
				(m as Dictionary).get("debug_name", ""))


func _event_media(event_name: String) -> Array:
	var out: Array = []
	var text: String = FileAccess.get_file_as_string(EVENTS_PATH)
	if text.is_empty():
		return out
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		return out
	for ev: Variant in ((doc as Dictionary).get("events", []) as Array):
		if not (ev is Dictionary) or str((ev as Dictionary).get("event", "")) != event_name:
			continue
		for m: Variant in ((ev as Dictionary).get("media", []) as Array):
			if m is Dictionary:
				out.append(int((m as Dictionary).get("media_id", 0)))
	return out


func _finish(ctl: AudioControl) -> void:
	# Leave the autoload in its authored state and release the players this suite
	# created, like the other audio suites do before SUMMARY.
	var am: Node = root.get_node_or_null("AudioManager")
	if am != null and am.has_method("cleanup_on_exit"):
		am.call("cleanup_on_exit")
		for _i: int in range(8):
			await process_frame
	print("AUDIO_CONTROL counts: switch=%d/%d values=%d state=%d/%d values=%d rtpcs=%d/%d curves=%d containers=%d" % [
		ctl.switch_group_count(), int(ctl.counts().get("switch_groups_total", 0)),
		int(ctl.counts().get("switch_values", 0)), ctl.state_group_count(),
		int(ctl.counts().get("state_groups_total", 0)), int(ctl.counts().get("state_values", 0)),
		ctl.rtpc_count(), int(ctl.counts().get("rtpcs_total", 0)),
		int(ctl.counts().get("rtpc_curves", 0)), int(ctl.counts().get("switch_containers", 0))])
	print("AUDIO_CONTROL_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(0 if fails == 0 else 1)
