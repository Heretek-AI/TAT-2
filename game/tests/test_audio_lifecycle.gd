extends SceneTree
## W5D standalone audio-lifecycle truth test.
##
## Three defects this pins, all in game/src/core/audio_manager.gd:
##   * duplicate cue fan-out: play_cue/play_sfx/play_ui started a second player
##     for the same cue|position in the same frame (signal fan-out + explicit
##     call). A ~120 ms window now drops the repeat, without touching the
##     cadence-gated footsteps.
##   * bed overlap: play_bed_scene() faded the old bed out and immediately
##     created the new player, so two players shared one bed key for 0.2-0.35 s.
##     start_bed() now cancels/frees the fading player for the same key first.
##   * sustained cues (alarm_loop / smoke_cloud / lightbeam_hum) were one-shot
##     plays of a loop clip with no handle. They now replace one handle per
##     cue|position and alarm_eye.reset_alarm() stops its own loop.
##
## Run:
##   XDG_DATA_HOME=/tmp/opencode/w5d-data tools/godot --headless --path game \
##     --script res://tests/test_audio_lifecycle.gd

var fails: int = 0


func _as_bool(v: Variant) -> bool:
	return v == true


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _ambience_players(am: Node) -> int:
	var n: int = 0
	for child: Node in am.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).bus == "Ambience":
			n += 1
	return n


func _players_with_stream(am: Node, stream: AudioStream) -> int:
	var n: int = 0
	for child: Node in am.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream == stream:
			n += 1
	return n


func _initialize() -> void:
	await process_frame
	var alarm_eye_scr: GDScript = load("res://src/devices/alarm_eye.gd") as GDScript
	var am: Node = root.get_node_or_null("AudioManager")
	if am == null:
		_check(false, "", "W5D.0 AudioManager autoload missing")
		_finish()
		return

	# Start from a clean slate (the autoload may have autostarted a menu bed).
	am.call("stop_all_beds", 0.0)
	for cue: String in ["alarm_loop", "smoke_cloud", "lightbeam_hum"]:
		am.call("stop_cue", cue)
	await process_frame

	# -- W5D.1-W5D.3 single player per bed key ------------------------------
	am.call("play_bed_scene", "old_manor")
	var after_first: int = _ambience_players(am)
	var levels_first: Dictionary = am.call("active_bed_levels") as Dictionary
	_check(after_first == 1 and levels_first.has("rain"),
		"W5D.1 old_manor scene bed starts exactly one rain player (players=%d)" % after_first,
		"W5D.1 old_manor bed wrong: players=%d levels=%s" % [
			after_first, str(levels_first.keys())])

	# Same scene re-entry: the old rain player is fading (0.2 s) when start_bed
	# runs again. It must be freed, not layered under the replacement.
	am.call("play_bed_scene", "old_manor")
	var after_reentry: int = _ambience_players(am)
	var levels_reentry: Dictionary = am.call("active_bed_levels") as Dictionary
	_check(after_reentry == 1 and levels_reentry.size() == 1,
		"W5D.2 scene re-entry keeps one rain player (players=%d levels=%d)" % [
			after_reentry, levels_reentry.size()],
		"W5D.2 bed overlap: players=%d levels=%s" % [
			after_reentry, str(levels_reentry.keys())])
	am.call("stop_all_beds", 0.0)
	await process_frame

	# start_bed twice is idempotent per key.
	am.call("start_bed", "den", 0.0)
	am.call("start_bed", "den", 0.0)
	var beds: Dictionary = am.get("_beds") as Dictionary
	var den_players: int = 0
	if beds.has("den"):
		den_players = _players_with_stream(am, (beds["den"] as AudioStreamPlayer).stream)
	_check(beds.size() == 1 and den_players == 1,
		"W5D.3 start_bed(den) twice leaves one player for the key",
		"W5D.3 start_bed not idempotent: beds=%s players=%d" % [str(beds.keys()), den_players])
	am.call("stop_all_beds", 0.0)
	await process_frame

	# -- W5D.4-W5D.6 cue dedupe window --------------------------------------
	var pos_a := Vector3(10.0, 0.0, 10.0)
	var pos_b := Vector3(10.0, 0.0, 11.0)
	var first: bool = _as_bool(am.call("play_cue", "door_latch", pos_a))
	var voices_after_first: int = int(am.get("_active_voices"))
	var second: bool = _as_bool(am.call("play_cue", "door_latch", pos_a))
	var voices_after_second: int = int(am.get("_active_voices"))
	_check(first and not second and voices_after_second == voices_after_first,
		"W5D.4 same cue|position inside 120 ms is dropped (first=%s second=%s voices %d->%d)" % [
			first, second, voices_after_first, voices_after_second],
		"W5D.4 dedupe failed: first=%s second=%s voices %d->%d" % [
			first, second, voices_after_first, voices_after_second])

	var other_pos: bool = _as_bool(am.call("play_cue", "door_latch", pos_b))
	_check(other_pos,
		"W5D.5 same cue at a different position is not deduped",
		"W5D.5 a distinct emitter was incorrectly suppressed")

	await create_timer(0.16).timeout
	var later: bool = _as_bool(am.call("play_cue", "door_latch", pos_a))
	_check(later,
		"W5D.6 same cue|position plays again after the 120 ms window",
		"W5D.6 dedupe window never expires")

	# UI path uses the same guard.
	var ui_first: bool = _as_bool(am.call("play_ui", "click"))
	var ui_second: bool = _as_bool(am.call("play_ui", "click"))
	_check(ui_first and not ui_second,
		"W5D.7 play_ui drops the duplicate click in the same window",
		"W5D.7 play_ui dedupe failed: first=%s second=%s" % [ui_first, ui_second])

	# Footsteps are cadence-gated and must never be deduped.
	am.call("stop_all_beds", 0.0)
	var foot_a: bool = _as_bool(am.call("play_footstep", "wood", "walk", Vector3(2.0, 0.0, 2.0)))
	var foot_b: bool = _as_bool(am.call("play_footstep", "wood", "walk", Vector3(2.0, 0.0, 2.0)))
	_check(foot_a and foot_b,
		"W5D.8 rapid footsteps are not suppressed (cadence owns the rate)",
		"W5D.8 footstep cadence was overridden by the cue dedupe")

	# -- W5D.9-W5D.11 sustained cue handle ---------------------------------
	var eye: Node3D = alarm_eye_scr.new() as Node3D
	root.add_child(eye)
	eye.global_position = Vector3(3.0, 0.0, 7.0)

	var alarm_started: bool = _as_bool(am.call("play_cue", "alarm_loop", eye.global_position))
	var loops: Array = am.call("active_loop_cues") as Array
	_check(alarm_started and loops.size() == 1 and loops[0].begins_with("alarm_loop|"),
		"W5D.9 alarm_loop owns one sustained handle at its position (%s)" % str(loops),
		"W5D.9 alarm_loop handle wrong: started=%s handles=%s" % [alarm_started, str(loops)])

	am.call("play_cue", "alarm_loop", eye.global_position)
	var loops_again: Array = am.call("active_loop_cues") as Array
	_check(loops_again.size() == 1,
		"W5D.10 re-trigger replaces the handle instead of stacking",
		"W5D.10 alarm_loop stacked %d handles" % loops_again.size())

	eye.set("_alarmed", true)
	eye.set("_alarm_loop_pos", eye.global_position)
	eye.set("_alarm_loop_started", true)
	eye.call("reset_alarm")
	var loops_after_reset: Array = am.call("active_loop_cues") as Array
	_check(loops_after_reset.is_empty(),
		"W5D.11 alarm_eye.reset_alarm() stops its own alarm loop",
		"W5D.11 reset_alarm left handles: %s" % str(loops_after_reset))

	# A reset of a never-alarmed eye must not stop another live loop.
	am.call("play_cue", "alarm_loop", Vector3(20.0, 0.0, 20.0))
	var idle_eye: Node3D = alarm_eye_scr.new() as Node3D
	root.add_child(idle_eye)
	idle_eye.global_position = Vector3(40.0, 0.0, 40.0)
	idle_eye.call("reset_alarm")
	var loops_after_idle: Array = am.call("active_loop_cues") as Array
	_check(loops_after_idle.size() == 1,
		"W5D.12 an unalarmed eye's reset leaves other loops running",
		"W5D.12 idle reset stopped %d loop handle(s)" % (1 - loops_after_idle.size()))

	# A sustained cue with a duration (the smoke cloud TTL) stops itself.
	var smoke_pos := Vector3(12.0, 0.0, 12.0)
	var smoke_started: bool = _as_bool(am.call("play_cue", "smoke_cloud", smoke_pos, 0.15))
	var smoke_live: Array = am.call("active_loop_cues") as Array
	await create_timer(0.30).timeout
	var smoke_after: Array = am.call("active_loop_cues") as Array
	_check(smoke_started and smoke_live.size() == 2 and smoke_after.size() == 1,
		"W5D.13 sustained smoke cue auto-stops at its duration (%d -> %d handles)" % [
			smoke_live.size(), smoke_after.size()],
		"W5D.13 smoke TTL wrong: started=%s live=%d after=%d" % [
			smoke_started, smoke_live.size(), smoke_after.size()])

	# -- teardown -----------------------------------------------------------
	am.call("stop_cue", "alarm_loop")
	am.call("stop_cue", "smoke_cloud")
	am.call("stop_cue", "lightbeam_hum")
	am.call("stop_all_beds", 0.0)
	eye.queue_free()
	idle_eye.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	print("AUDIO_LIFECYCLE_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)
