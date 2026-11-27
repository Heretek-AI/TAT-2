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
