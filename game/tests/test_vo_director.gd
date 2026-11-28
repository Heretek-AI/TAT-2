extends SceneTree
## W11-A gate: the authored VO director.
##
## Pins the five contracts this lane owes, against the real generated documents
## (`res://data/generated/audio_wwise.json`, schema `tat2.audio_wwise/1`, and
## the `audio_events.json` clip join):
##
##   1. The index: exactly the 645 authored VO lines, indexed by
##      `(speaker, verb, state)` — 76 triples, 7 speakers, the one authored
##      zero-media line (`Play_VO_Enforcer1_0_Silent_Empty_01`) included and
##      flagged, never dropped.
##   2. Every selection is a real event/clip: every line the director maps is an
##      authored `Play_VO_*` event with >= 1 media whose clip path exists.
##   3. The guard transition choices: every authored guard transition resolves
##      to a triple that speaker really recorded, for both `Enforcer1` and
##      `Hauntstable1`.
##   4. Cooldown suppression and the priority window.
##   5. The zero-media line is refused by the director and by
##      `AudioManager.play_vo_line`.
##
## It does NOT claim that all 645 lines are wired: the report counts the mapped
## cues and the suite asserts that the unmapped authored lines are the ones the
## director documents as callerless.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/test_vo_director.gd"

const WWISE_PATH: String = "res://data/generated/audio_wwise.json"
const EVENTS_PATH: String = "res://data/generated/audio_events.json"
const ZERO_MEDIA_EVENT: String = "Play_VO_Enforcer1_0_Silent_Empty_01"
const GUARD_SPEAKERS: Array[String] = ["Enforcer1", "Hauntstable1"]

var fails: int = 0
var checks: int = 0
var _media_by_event: Dictionary = {}
var _clips_by_event: Dictionary = {}
var _index: Dictionary = {}


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", ok_msg)
	else:
		fails += 1
		printerr("FAIL: ", fail_msg)


func _approx(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_load_event_clips()
	var aw: AudioWwise = AudioWwise.new()
	var ok: bool = aw.load_data()
	_check(ok, "VO1.0 the authored Wwise graph loads (%s)" % WWISE_PATH,
		"VO1.0 audio_wwise.json did not load: %s" % aw.degraded_reason())
	if not ok:
		_finish()
		return
	var index: Dictionary = aw.vo_index()
	_index = index
	var director: VoDirector = VoDirector.new()
	_check(director.load_index(index),
		"VO1.0 VoDirector loads the authored index",
		"VO1.0 VoDirector refused the authored index")
	_test_index(aw, index, director)
	_test_real_events(aw, director)
	_test_guard_transitions(director)
	_test_guard_beats(director)
	_test_event_cues(director)
	_test_cooldowns(director)
	_test_zero_media(aw, director)
	await _test_runtime(aw, director)
	await _test_player_rebind()
	await _finish()


## 1. The 645-line index itself.
func _test_index(aw: AudioWwise, index: Dictionary, director: VoDirector) -> void:
	var stats: Dictionary = aw.stats()
	_check(int(stats.get("vo_lines", 0)) == 645,
		"VO1.1 stats.vo_lines == 645 authored lines",
		"VO1.1 vo_lines=%d (want 645)" % int(stats.get("vo_lines", 0)))
	_check(int(stats.get("vo_triples", 0)) == 76,
		"VO1.1 the index has 76 authored (speaker, verb, state) triples",
		"VO1.1 vo_triples=%d (want 76)" % int(stats.get("vo_triples", 0)))
	_check(int(stats.get("vo_speakers", 0)) == 7,
		"VO1.1 7 authored speakers",
		"VO1.1 vo_speakers=%d (want 7)" % int(stats.get("vo_speakers", 0)))
	_check(director.line_count() == 645,
		"VO1.1 the director index carries all 645 lines",
		"VO1.1 director.line_count()=%d (want 645)" % director.line_count())
	_check(director.triple_count() == 76,
		"VO1.1 the director index carries all 76 triples",
		"VO1.1 director.triple_count()=%d (want 76)" % director.triple_count())
	var speakers: PackedStringArray = aw.vo_speakers()
	_check(speakers.has("Enforcer1") and speakers.has("Hauntstable1")
		and speakers.has("Player") and speakers.has("TalkingLoot01"),
		"VO1.1 authored speakers include Enforcer1/Hauntstable1/Player/TalkingLoot01",
		"VO1.1 speakers=%s" % str(speakers))
	# Every indexed event is an authored line and vice versa (no dropped line).
	var indexed: Dictionary = {}
	for speaker: Variant in index.keys():
		var by_verb: Dictionary = index[speaker]
		for verb: Variant in by_verb.keys():
			var by_state: Dictionary = by_verb[verb]
			for state: Variant in by_state.keys():
				var rows: Array = by_state[state]
				for record: Dictionary in rows:
					var event: String = str(record.get("event", ""))
					if not event.is_empty():
						indexed[event] = row_key(speaker, verb, state)
	_check(indexed.size() == 645,
		"VO1.2 the index holds 645 distinct authored events",
		"VO1.2 %d distinct events in the index (want 645)" % indexed.size())
	_check(indexed.has(ZERO_MEDIA_EVENT)
		and str(indexed[ZERO_MEDIA_EVENT]).ends_with("Silent\u001fEmpty"),
		"VO1.2 the zero-media authored line is indexed under Enforcer1/Silent/Empty",
		"VO1.2 zero-media line missing or mis-indexed: %s" % str(indexed.get(ZERO_MEDIA_EVENT, "")))
	# Authored no-state rows land in the "" bucket (11 lines), not in "None".
	var player_states: PackedStringArray = aw.vo_events("Player", "EscapePhaseStarted", "")
	_check(player_states.size() == 1
		and player_states[0] == "Play_VO_Player_EscapePhaseStarted",
		"VO1.2 a null authored state indexes under the \"\" bucket",
		"VO1.2 EscapePhaseStarted rows=%s" % str(player_states))
	_check(aw.vo_events("Player", "EscapePhaseStarted", "None").is_empty(),
		"VO1.2 no row is invented under the literal state \"None\"",
		"VO1.2 a literal \"None\" bucket exists")
	var zero: PackedStringArray = aw.vo_zero_media_events()
	_check(zero.size() == 1 and zero[0] == ZERO_MEDIA_EVENT,
		"VO1.3 exactly one authored zero-media line is flagged",
		"VO1.3 zero-media events=%s" % str(zero))


## 2. Every mapped line is a real event with a real clip.
func _test_real_events(aw: AudioWwise, director: VoDirector) -> void:
	var mapped: PackedStringArray = director.mapped_events()
	_check(mapped.size() > 0,
		"VO2.0 the director maps %d authored lines" % mapped.size(),
		"VO2.0 the director maps no authored line")
	var not_indexed: Array = []
	var no_media: Array = []
	var no_clip: Array = []
	var zero_media_mapped: Array = []
	for event: String in mapped:
		var media_count: int = aw.vo_media_count(event)
		if media_count < 0:
			not_indexed.append(event)
			continue
		if media_count <= 0:
			zero_media_mapped.append(event)
		var media: Array = _media_by_event.get(event, [])
		if media.is_empty():
			no_media.append(event)
			continue
		var clip: String = str(_clips_by_event.get(event, ""))
		if clip.is_empty() or not FileAccess.file_exists(clip):
			no_clip.append(event)
	_check(not_indexed.is_empty(),
		"VO2.1 every mapped event is one of the 645 authored lines",
		"VO2.1 %d mapped events are not authored VO lines: %s" % [
			not_indexed.size(), str(not_indexed.slice(0, 4))])
	_check(zero_media_mapped.is_empty(),
		"VO2.2 no mapped event is the zero-media authored line",
		"VO2.2 mapped zero-media lines: %s" % str(zero_media_mapped))
	_check(no_media.is_empty(),
		"VO2.3 every mapped event joins >= 1 authored media id",
		"VO2.3 %d mapped events have no media: %s" % [no_media.size(), str(no_media.slice(0, 4))])
	_check(no_clip.is_empty(),
		"VO2.4 every mapped event resolves a clip path that exists on disk",
		"VO2.4 %d mapped events have no existing clip: %s" % [no_clip.size(), str(no_clip.slice(0, 4))])


## 3. Guard transitions resolve for both authored guard speakers.
func _test_guard_transitions(director: VoDirector) -> void:
	var cues: int = 0
	var refused: Array = []
	var wrong: Array = []
	var authored_gaps: Array = []
	for cue_v: Variant in VoDirector.GUARD_CUES.keys():
		var cue: String = str(cue_v)
		var parts: PackedStringArray = cue.split(">")
		if parts.size() != 2:
			wrong.append("bad cue %s" % cue)
			continue
		for speaker: String in GUARD_SPEAKERS:
			cues += 1
			# A fresh director per pick keeps cooldowns from masking a mapping.
			var fresh: VoDirector = VoDirector.new()
			fresh.load_index(director_index(director))
			var pick: Dictionary = fresh.vo_pick_transition(parts[0], parts[1], speaker, 10.0)
			var has_any: bool = false
			for row_v: Variant in (VoDirector.GUARD_CUES[cue] as Array):
				var row: Dictionary = row_v as Dictionary
				if director_row_exists(director, speaker, str(row["verb"]), str(row["state"])):
					has_any = true
					break
			if not has_any:
				# The speaker never recorded any candidate triple (an authored
				# gap). The director must refuse, never borrow another speaker's
				# line.
				authored_gaps.append("%s/%s" % [cue, speaker])
				if bool(pick.get("ok", false)) or str(pick.get("reason", "")) != "unknown_triple":
					wrong.append("%s/%s invented %s" % [cue, speaker, str(pick)])
				continue
			if not bool(pick.get("ok", false)):
				refused.append("%s/%s:%s" % [cue, speaker, str(pick.get("reason", ""))])
				continue
			if str(pick.get("speaker", "")) != speaker:
				wrong.append("%s speaker=%s" % [cue, str(pick.get("speaker", ""))])
			if director_row_exists(director, speaker, str(pick.get("verb", "")), str(pick.get("state", ""))) == false:
				wrong.append("%s triple %s/%s" % [cue, str(pick.get("verb", "")), str(pick.get("state", ""))])
	_check(refused.is_empty(),
		"VO3.1 all %d guard transition/speaker pairs resolve an authored line" % cues,
		"VO3.1 %d pairs refused: %s" % [refused.size(), str(refused.slice(0, 5))])
	_check(wrong.is_empty(),
		"VO3.2 every resolved guard pick is the requested speaker's authored triple",
		"VO3.2 wrong picks: %s" % str(wrong.slice(0, 5)))
	# The measured authored gap: Hauntstable1 never recorded an
	# ExertionCombat/KnockedOut row (Enforcer1 has 8), so its five KO
	# transitions must refuse rather than borrow the Enforcer line.
	var want_gap: Array = []
	for cue: String in ["NEUTRAL>KNOCKED_OUT", "SUSPICIOUS>KNOCKED_OUT", "SEARCH>KNOCKED_OUT",
			"ALERTED>KNOCKED_OUT", "COMBAT>KNOCKED_OUT"]:
		want_gap.append("%s/Hauntstable1" % cue)
	authored_gaps.sort()
	want_gap.sort()
	_check(authored_gaps == want_gap,
		"VO3.2 the only authored guard gap is Hauntstable1's 5 KO transitions (measured)",
		"VO3.2 authored gaps=%s" % str(authored_gaps))
	# The exact authored choice for the most important transition.
	var fresh_alert: VoDirector = VoDirector.new()
	fresh_alert.load_index(director_index(director))
	var alert: Dictionary = fresh_alert.vo_pick_transition("NEUTRAL", "SUSPICIOUS", "Enforcer1", 1.0)
	_check(bool(alert.get("ok", false)) and str(alert.get("verb", "")) == "ThiefSeen"
		and str(alert.get("state", "")) == "VisionStim",
		"VO3.3 NEUTRAL>SUSPICIOUS picks ThiefSeen/VisionStim",
		"VO3.3 NEUTRAL>SUSPICIOUS picked %s" % str(alert))
	var fresh_ko: VoDirector = VoDirector.new()
	fresh_ko.load_index(director_index(director))
	var ko: Dictionary = fresh_ko.vo_pick_transition("NEUTRAL", "KNOCKED_OUT", "Enforcer1", 1.0)
	_check(bool(ko.get("ok", false)) and str(ko.get("verb", "")) == "ExertionCombat"
		and str(ko.get("state", "")) == "KnockedOut",
		"VO3.3 NEUTRAL>KNOCKED_OUT picks ExertionCombat/KnockedOut for Enforcer1",
		"VO3.3 KO picked %s" % str(ko))
	# An unknown transition is refused, never guessed.
	var fresh_bad: VoDirector = VoDirector.new()
	fresh_bad.load_index(director_index(director))
	var bad: Dictionary = fresh_bad.vo_pick_transition("NEUTRAL", "ALERTED", "Enforcer1", 1.0)
	_check(not bool(bad.get("ok", false)) and str(bad.get("reason", "")) == "unknown_cue",
		"VO3.4 an unmapped transition is refused (no invented line)",
		"VO3.4 unmapped transition returned %s" % str(bad))


## 3b. Phase 3B.3: the guard exertion/attack beats whose owning systems already
## exist (GuardAi.take_knockout / _play_guard_attack). These are wired because
## the systems exist, not because a line wanted a caller; the speaker is the
## guard's own, so a Hauntstable cannot borrow an Enforcer1 recording.
func _test_guard_beats(director: VoDirector) -> void:
	var expected: Dictionary = {
		"taking_damage": ["ExertionCombat", "TakingDamage"],
		"attacking": ["ExertionCombat", "Attacking"],
	}
	var wrong: Array = []
	for cue: Variant in expected.keys():
		var want: Array = expected[cue]
		var fresh: VoDirector = VoDirector.new()
		fresh.load_index(director_index(director))
		var pick: Dictionary = fresh.vo_pick_guard_beat(str(cue), "Enforcer1", 1.0)
		if not bool(pick.get("ok", false)):
			wrong.append("%s refused:%s" % [str(cue), str(pick.get("reason", ""))])
			continue
		if (str(pick.get("speaker", "")) != "Enforcer1"
			or str(pick.get("verb", "")) != str(want[0])
			or str(pick.get("state", "")) != str(want[1])):
			wrong.append("%s=%s" % [str(cue), str(pick)])
	_check(wrong.is_empty(),
		"VO4.4 the two wired guard beats pick their authored Enforcer1 triple",
		"VO4.4 wrong guard beat picks: %s" % str(wrong))
	# The measured authored gap: Hauntstable1 recorded neither exertion bucket,
	# so both beats refuse instead of borrowing the Enforcer1 set.
	var gap: Array = []
	for cue: Variant in expected.keys():
		var fresh: VoDirector = VoDirector.new()
		fresh.load_index(director_index(director))
		var pick: Dictionary = fresh.vo_pick_guard_beat(str(cue), "Hauntstable1", 1.0)
		if bool(pick.get("ok", false)) or str(pick.get("reason", "")) != "unknown_triple":
			gap.append("%s=%s" % [str(cue), str(pick)])
	_check(gap.is_empty(),
		"VO4.5 Hauntstable1 has no exertion recording and both beats refuse (no borrowed line)",
		"VO4.5 Hauntstable1 beat gap wrong: %s" % str(gap))
	# Cooldown: the same beat cannot re-bark inside its authored cooldown.
	var d: VoDirector = VoDirector.new()
	d.load_index(director_index(director))
	var first: Dictionary = d.vo_pick_guard_beat("taking_damage", "Enforcer1", 0.0)
	var second: Dictionary = d.vo_pick_guard_beat("taking_damage", "Enforcer1", 1.0)
	_check(bool(first.get("ok", false)) and not bool(second.get("ok", false))
		and str(second.get("reason", "")) == "cooldown",
		"VO4.6 a repeated damage beat inside its 6 s cooldown is suppressed",
		"VO4.6 first=%s second=%s" % [str(first), str(second)])
	# An unknown beat is refused, never guessed.
	var fresh_bad: VoDirector = VoDirector.new()
	fresh_bad.load_index(director_index(director))
	var bad: Dictionary = fresh_bad.vo_pick_guard_beat("not_a_beat", "Enforcer1", 1.0)
	_check(not bool(bad.get("ok", false)) and str(bad.get("reason", "")) == "unknown_cue",
		"VO4.7 an unknown guard beat is refused",
		"VO4.7 unknown beat returned %s" % str(bad))
	# The reachable/unwired census moves only by the wired lines: the director
	# maps 288 of the 645 authored lines; the other 357 are documented families
	# whose owning systems do not exist (see docs/reports/phase3-audio-20261127.md).
	var mapped: int = director.mapped_events().size()
	_check(mapped == 288,
		"VO4.7 the director maps 288 authored lines (249 W11-A + 39 exertion)",
		"VO4.7 mapped=%d (want 288)" % mapped)
	_check(645 - mapped == 357,
		"VO4.7 357 authored lines stay unmapped and counted (was 396 before 3B.3)",
		"VO4.7 unmapped=%d (want 357)" % (645 - mapped))


## 4. The player/quest cues and their authored speakers.
func _test_event_cues(director: VoDirector) -> void:
	var expected: Dictionary = {
		"loot_pickup_major": ["Player", "PickupLoot", "Major"],
		"match_loot_picked": ["TalkingLoot01", "MatchLootIsPickedUp", ""],
		"carrying_loot": ["TalkingLoot01", "PlayerIsCarryingLoot", ""],
		"stash_deposit": ["Player", "StashInteract", "StoringLoot"],
		"escape_phase": ["Player", "EscapePhaseStarted", ""],
		"disguise_ending": ["Player", "DisguiseEnding", ""],
	}
	var wrong: Array = []
	for cue: Variant in expected.keys():
		var want: Array = expected[cue]
		var fresh: VoDirector = VoDirector.new()
		fresh.load_index(director_index(director))
		var pick: Dictionary = fresh.vo_pick_event(str(cue), 1.0)
		if not bool(pick.get("ok", false)):
			wrong.append("%s refused:%s" % [str(cue), str(pick.get("reason", ""))])
			continue
		if (str(pick.get("speaker", "")) != str(want[0])
			or str(pick.get("verb", "")) != str(want[1])
			or str(pick.get("state", "")) != str(want[2])):
			wrong.append("%s=%s" % [str(cue), str(pick)])
	_check(wrong.is_empty(),
		"VO4.1 the six wired player/quest cues pick their authored triple",
		"VO4.1 wrong cue picks: %s" % str(wrong))
	# The documented callerless cues are still mapped to authored lines (so a
	# later owning system can use them), and resolve when asked.
	var callerless: Array[String] = ["main_quest_intro", "new_objective", "opening_vault",
		"poi_entered", "reviving_teammate", "pickup_loot_mission", "pickup_loot_story",
		"loot_dropped"]
	var refused: Array = []
	for cue: String in callerless:
		var fresh: VoDirector = VoDirector.new()
		fresh.load_index(director_index(director))
		var pick: Dictionary = fresh.vo_pick_event(cue, 1.0)
		if not bool(pick.get("ok", false)):
			refused.append("%s:%s" % [cue, str(pick.get("reason", ""))])
	_check(refused.is_empty(),
		"VO4.2 the %d documented callerless cues still resolve an authored line" % callerless.size(),
		"VO4.2 callerless cues refused: %s" % str(refused))
	# Unknown cue -> no invented line.
	var fresh_bad: VoDirector = VoDirector.new()
	fresh_bad.load_index(director_index(director))
	var bad: Dictionary = fresh_bad.vo_pick_event("not_a_cue", 1.0)
	_check(not bool(bad.get("ok", false)) and str(bad.get("reason", "")) == "unknown_cue",
		"VO4.3 an unknown cue is refused",
		"VO4.3 unknown cue returned %s" % str(bad))


## 5. Cooldown suppression, the priority window and variant rotation.
func _test_cooldowns(director: VoDirector) -> void:
	var d: VoDirector = VoDirector.new()
	d.load_index(director_index(director))
	var first: Dictionary = d.vo_pick_transition("NEUTRAL", "SUSPICIOUS", "Enforcer1", 0.0)
	_check(bool(first.get("ok", false)),
		"VO5.1 the first pick at t=0 plays",
		"VO5.1 first pick refused: %s" % str(first))
	var second: Dictionary = d.vo_pick_transition("NEUTRAL", "SUSPICIOUS", "Enforcer1", 1.0)
	_check(not bool(second.get("ok", false)) and str(second.get("reason", "")) == "cooldown",
		"VO5.1 the same triple 1 s later is suppressed by its cooldown",
		"VO5.1 second pick returned %s" % str(second))
	var third: Dictionary = d.vo_pick_transition("NEUTRAL", "SUSPICIOUS", "Enforcer1", 10.0)
	_check(bool(third.get("ok", false)),
		"VO5.2 the same triple after its cooldown plays again",
		"VO5.2 third pick refused: %s" % str(third))
	# Priority window: a high-priority KO bark blocks a calmer line for 2 s.
	var p: VoDirector = VoDirector.new()
	p.load_index(director_index(director))
	var high: Dictionary = p.vo_pick_transition("ALERTED", "KNOCKED_OUT", "Enforcer1", 0.0)
	var low: Dictionary = p.vo_pick_transition("SUSPICIOUS", "NEUTRAL", "Enforcer1", 0.5)
	_check(bool(high.get("ok", false)) and not bool(low.get("ok", false))
		and str(low.get("reason", "")) == "priority",
		"VO5.3 a priority-60 bark suppresses a priority-10 line inside the 2 s window",
		"VO5.3 high=%s low=%s" % [str(high), str(low)])
	var late: Dictionary = p.vo_pick_transition("SUSPICIOUS", "NEUTRAL", "Enforcer1", 3.0)
	_check(bool(late.get("ok", false)),
		"VO5.4 the calmer line plays after the priority window",
		"VO5.4 late pick refused: %s" % str(late))
	# Variant rotation: a multi-variant triple gives two different recordings.
	var r: VoDirector = VoDirector.new()
	r.load_index(director_index(director))
	var a: Dictionary = r.vo_pick_transition("SUSPICIOUS", "ALERTED", "Enforcer1", 0.0)
	var b: Dictionary = r.vo_pick_transition("SUSPICIOUS", "ALERTED", "Enforcer1", 100.0)
	_check(bool(a.get("ok", false)) and bool(b.get("ok", false))
		and str(a.get("event", "")) != str(b.get("event", "")),
		"VO5.5 a multi-variant triple rotates recordings (%s -> %s)" % [
			str(a.get("event", "")), str(b.get("event", ""))],
		"VO5.5 rotation repeated one recording: %s" % str(a))


## 6. The authored zero-media line is refused everywhere.
func _test_zero_media(aw: AudioWwise, director: VoDirector) -> void:
	_check(aw.vo_media_count(ZERO_MEDIA_EVENT) == 0,
		"VO6.1 the Silent line carries 0 authored media",
		"VO6.1 media_count=%d (want 0)" % aw.vo_media_count(ZERO_MEDIA_EVENT))
	var d: VoDirector = VoDirector.new()
	d.load_index(director_index(director))
	var pick: Dictionary = d.vo_pick("silent_probe", [
		{"speaker": "Enforcer1", "verb": "Silent", "state": "Empty", "priority": 10, "cooldown_s": 0.0},
	], "", 1.0)
	_check(not bool(pick.get("ok", false)) and str(pick.get("reason", "")) == "zero_media",
		"VO6.2 the director refuses the zero-media line with reason zero_media",
		"VO6.2 zero-media pick returned %s" % str(pick))
	_check(int(d.report().get("zero_media_refusals", 0)) >= 1,
		"VO6.2 the refusal is counted in the report",
		"VO6.2 zero_media_refusals=%d" % int(d.report().get("zero_media_refusals", 0)))
	var am: Node = root.get_node_or_null("AudioManager")
	_check(am != null, "VO6.3 AudioManager autoload present", "VO6.3 AudioManager missing")
	if am == null:
		return
	var played: bool = bool(am.call("play_vo_event", ZERO_MEDIA_EVENT))
	_check(not played,
		"VO6.3 AudioManager.play_vo_line refuses the zero-media line",
		"VO6.3 the zero-media line played")


## 7. Runtime wiring: the manager owns the director and the guard/quest path
## resolves real authored lines.
func _test_runtime(aw: AudioWwise, director: VoDirector) -> void:
	var am: Node = root.get_node_or_null("AudioManager")
	if am == null:
		return
	_check(am.call("vo_director") != null,
		"VO7.1 AudioManager holds the VO director",
		"VO7.1 AudioManager.vo_director() is null")
	var state: Dictionary = am.call("vo_state") as Dictionary
	_check(int(state.get("authored_lines", 0)) == 645,
		"VO7.1 mix_state().vo reports the 645 authored lines",
		"VO7.1 vo_state.authoring=%d" % int(state.get("authored_lines", 0)))
	var picked: bool = bool(am.call("play_vo_transition", "NEUTRAL", "SUSPICIOUS", "Enforcer1",
		Vector3.ZERO))
	_check(picked,
		"VO7.2 AudioManager.play_vo_transition plays an authored line",
		"VO7.2 play_vo_transition refused")
	var last: Dictionary = (am.call("vo_state") as Dictionary).get("last_transition", {}) as Dictionary
	_check(not str(last.get("event", "")).is_empty(),
		"VO7.2 the resolved event is recorded (%s)" % str(last.get("event", "")),
		"VO7.2 last_transition=%s" % str(last))
	# The player/quest cue path also resolves and plays (reset the priority
	# window first: the guard transition above is a higher-priority line).
	var runtime_director: Variant = am.call("vo_director")
	if runtime_director != null:
		runtime_director.call("reset_cooldowns")
	var cue_played: bool = bool(am.call("play_vo_cue", "stash_deposit"))
	_check(cue_played,
		"VO7.3 AudioManager.play_vo_cue plays an authored player line",
		"VO7.3 play_vo_cue refused")
	_check(aw.vo_media_count(str(last.get("event", ""))) > 0,
		"VO7.4 the played transition is a media-bearing authored line",
		"VO7.4 played a zero-media line")
	# Phase 3B.3: the guard exertion beat plays through the same single
	# playback path and is recorded for QA.
	if runtime_director != null:
		runtime_director.call("reset_cooldowns")
	var beat_played: bool = bool(am.call("play_vo_guard_beat", "taking_damage", "Enforcer1", Vector3.ZERO))
	var beat: Dictionary = (am.call("vo_state") as Dictionary).get("last_beat", {}) as Dictionary
	_check(beat_played and not str(beat.get("event", "")).is_empty()
		and str(beat.get("verb", "")) == "ExertionCombat",
		"VO7.5 AudioManager.play_vo_guard_beat plays and records the authored damage line",
		"VO7.5 beat_played=%s last_beat=%s" % [str(beat_played), str(beat)])


func row_key(speaker: Variant, verb: Variant, state: Variant) -> String:
	return "%s\u001f%s\u001f%s" % [str(speaker), str(verb), str(state)]


## The authored index loaded once in _run (a fresh director gets its own copy).
func director_index(_director: VoDirector) -> Dictionary:
	return _index


## True when the authored document really carries this speaker/triple.
func director_row_exists(_director: VoDirector, speaker: String, verb: String, state: String) -> bool:
	var by_verb: Variant = _index.get(speaker, null)
	if not (by_verb is Dictionary):
		return false
	var by_state: Variant = (by_verb as Dictionary).get(verb, null)
	if not (by_state is Dictionary):
		return false
	return (by_state as Dictionary).has(state)


func _load_event_clips() -> void:
	_media_by_event.clear()
	_clips_by_event.clear()
	var text: String = FileAccess.get_file_as_string(EVENTS_PATH)
	if text.is_empty():
		return
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		return
	for ev: Variant in ((doc as Dictionary).get("events", []) as Array):
		if not (ev is Dictionary):
			continue
		var ed: Dictionary = ev as Dictionary
		var name: String = str(ed.get("event", ""))
		var media: Array = ed.get("media", []) as Array
		_media_by_event[name] = media
		for m: Variant in media:
			if not (m is Dictionary):
				continue
			var clip: String = str((m as Dictionary).get("clip", ""))
			if not clip.is_empty():
				_clips_by_event[name] = clip
				break


## 8. W11-D: the disguise signal follows the *player instance*. AudioManager is
## an autoload while `mission_controller` creates a new ThiefCharacter per
## contract, so a one-shot "bound" flag left every later mission without the
## disguise RTPC or the `disguise_ending` line. This drives two fake players
## through the real `_process` binding path.
func _test_player_rebind() -> void:
	var am: Node = root.get_node_or_null("AudioManager")
	if am == null:
		return
	# The runtime section above left a last transition/cue behind; clear the
	# director's cooldowns so the disguise line is not priority-blocked.
	var director_v: Variant = am.call("vo_director")
	if director_v != null:
		director_v.call("reset_cooldowns")
	var first := FakePlayer.new()
	first.name = "W11FakePlayerOne"
	root.add_child(first)
	first.add_to_group("player")
	for _i: int in range(3):
		await process_frame
	_check(first.get_signal_connection_list("disguise_changed").size() == 1,
		"VO8.1 the first player's disguise_changed is bound exactly once",
		"VO8.1 first player connections=%d" % first.get_signal_connection_list(
			"disguise_changed").size())
	# The bound handler normalises the player's 0..100 unit into the authored 0..1.
	first.emit_disguise(25.0, true)
	var values: Dictionary = (am.call("control_state") as Dictionary).get(
		"rtpc_values", {}) as Dictionary
	_check(_approx(float(values.get("Character_DisguiseIntegrity", -1.0)), 0.25, 0.00001),
		"VO8.2 the first player's disguise RTPC stores 25 as 0.25",
		"VO8.2 stored %s" % str(values.get("Character_DisguiseIntegrity", -1.0)))
	for _i: int in range(3):
		await process_frame
	_check(first.get_signal_connection_list("disguise_changed").size() == 1,
		"VO8.2 repeated frames do not duplicate the connection",
		"VO8.2 connections=%d after repeated frames" % first.get_signal_connection_list(
			"disguise_changed").size())
	# A new contract spawns a new player. Replace the resolved player while the
	# old node is still alive, so the old connection must be dropped explicitly.
	var second := FakePlayer.new()
	second.name = "W11FakePlayerTwo"
	root.add_child(second)
	second.add_to_group("player")
	first.remove_from_group("player")
	for _i: int in range(3):
		await process_frame
	_check(second.get_signal_connection_list("disguise_changed").size() == 1,
		"VO8.3 the second player's disguise_changed is bound",
		"VO8.3 second player connections=%d" % second.get_signal_connection_list(
			"disguise_changed").size())
	_check(first.get_signal_connection_list("disguise_changed").size() == 0,
		"VO8.3 the replaced player's connection is disconnected",
		"VO8.3 old player still has %d connection(s)" % first.get_signal_connection_list(
			"disguise_changed").size())
	# The second player's signal must reach the RTPC and the authored ending line.
	if director_v != null:
		director_v.call("reset_cooldowns")
	var subtitles: Array = []
	var capture: Callable = func(text: String) -> void:
		subtitles.append(text)
	if not am.is_connected("subtitle_shown", capture):
		am.connect("subtitle_shown", capture)
	second.emit_disguise(0.0, false)
	var last_cue: Dictionary = (am.call("vo_state") as Dictionary).get("last_cue", {}) as Dictionary
	_check(str(last_cue.get("cue", "")) == "disguise_ending"
		and str(last_cue.get("event", "")) == "Play_VO_Player_DisguiseEnding",
		"VO8.4 the second player's 0 integrity plays the authored ending line",
		"VO8.4 last_cue=%s" % str(last_cue))
	_check(not subtitles.is_empty()
		and str(subtitles[subtitles.size() - 1]).find("DisguiseEnding") >= 0,
		"VO8.4 the ending line emits its functional subtitle",
		"VO8.4 subtitles=%s" % str(subtitles))
	values = (am.call("control_state") as Dictionary).get("rtpc_values", {}) as Dictionary
	_check(_approx(float(values.get("Character_DisguiseIntegrity", -1.0)), 0.0, 0.00001),
		"VO8.4 the second player's 0 integrity stores 0.0",
		"VO8.4 stored %s" % str(values.get("Character_DisguiseIntegrity", -1.0)))
	if am.is_connected("subtitle_shown", capture):
		am.disconnect("subtitle_shown", capture)
	# Teardown: no player left, so the tracking is cleared (a later mission's
	# player is then bound fresh instead of being skipped).
	second.remove_from_group("player")
	first.queue_free()
	second.queue_free()
	for _i: int in range(4):
		await process_frame
	_check(not bool((am.call("vo_state") as Dictionary).get("bound_player", true)),
		"VO8.5 the player binding is cleared when no player exists",
		"VO8.5 vo_state().bound_player still true")


## Minimal stand-in for `ThiefCharacter`'s disguise signal (the real player
## extends CharacterBody3D; `_sync_vo_sources` only needs the signal and the
## `player` group).
class FakePlayer:
	extends Node3D
	signal disguise_changed(integrity: float, active: bool)

	func emit_disguise(integrity: float, active: bool) -> void:
		disguise_changed.emit(integrity, active)


func _finish() -> void:
	var am: Node = root.get_node_or_null("AudioManager")
	if am != null and am.has_method("cleanup_on_exit"):
		am.call("cleanup_on_exit")
		for _i: int in range(8):
			await process_frame
	print("VO_DIRECTOR_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(0 if fails == 0 else 1)
