extends RefCounted
## T02-B run-lifecycle suite (REMEDIATION RE-N-08 / RE-N-11 / RE-N-15).
##
## Covers, without a map load and without a child engine:
## - `GameState.reset_run` clearing the run fields and publishing the phase
##   (RE-N-14/RE-N-16 contract, fixed by the T02 lead in `game_state.gd`:
##   asserted here so the payout path can rely on it);
## - the Thieves' Den hub owning no mission clock (RE-N-15);
## - failure-path banking for capture / main timeout / door collapse, exactly
##   once per `match_id`, with a resolved phase (RE-N-08);
## - escape banking plus idempotency through `SaveSystem.bank_payout` itself,
##   not through the handler's own guard (RE-N-08 / E2E S2-10);
## - the host-authoritative co-op run outcome: host banks once and broadcasts,
##   a client resolves from the host's banked record, a client extraction is
##   routed as a request and never resolved locally (RE-N-11).
##
## Mission instances are created from the script and never added to the tree, so
## `_ready`/`start_contract` never run. `GameState` run fields and
## `SaveSystem.data` are snapshotted and restored; the NetManager test seam is
## reset on exit.

const TIME_EXPIRED_REASON := "TIME EXPIRED"
const DOOR_COLLAPSED_REASON := "MAGIC DOOR COLLAPSED"
const LEVEL_LOADER := preload("res://src/core/level_loader.gd")

var _save_snap: Dictionary = {}
var _gs_snap: Dictionary = {}


func run(_host: Node) -> Array[String]:
	var problems: Array[String] = []
	_snapshot()
	# Transport gates first: no mission has connected to `run_requested` yet, so
	# a rejected request cannot reach a payout handler.
	_check_transport_bounds(problems)
	_check_remote_visual_paths(problems)
	_check_reset_clears(problems)
	_check_hub_clock(problems)
	_check_failure_banking(problems)
	_check_escape_banking(problems)
	_check_coop_host_once(problems)
	_check_coop_client_resolves(problems)
	_check_client_extraction_routes(problems)
	_restore()
	return problems


# ----------------------------------------------------------------- helpers ---
func _expect(problems: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		problems.append(msg)


func _currency() -> int:
	return int((SaveSystem.data as Dictionary).get("currency", 0))


func _new_mission() -> Node:
	var mc: Node = (load("res://src/missions/mission_controller.gd") as GDScript).new() as Node
	mc.set("contract_info", {})
	mc.set("hud", null)
	mc.set("_payout_applied", false)
	return mc


func _nm_counter(name: String) -> int:
	var v: Variant = NetManager.get(name)
	if v is int or v is float:
		return int(v)
	return 0


## One consistent run staging: 750 stashed + `carried_value` carried, gross
## `loot_value` = both. `carried_tracking_active` makes `build_payout` read the
## carried entries rather than the legacy gross fallback.
func _stage_run(map_id: String, order: int, stashed: int, carried_value: int, run_id: String) -> void:
	GameState.reset_run(order, map_id)
	GameState.state = "playing"
	GameState.difficulty = 1
	GameState.free_play = false
	GameState.free_play_pending = false
	GameState.pending_mission_id = ""
	GameState.loot_run_id = run_id
	GameState.stashed_loot_value = stashed
	var carried: Array[Dictionary] = []
	if carried_value > 0:
		carried.append({
			"name": "Purse",
			"value": carried_value,
			"tier": "major",
			"slot_cost": 3,
			"is_quest_item": false,
		})
	GameState.carried_loot = carried
	GameState.carried_tracking_active = true
	GameState.loot_value = stashed + carried_value
	GameState.loot_goal = 0
	GameState.loot_needed = 0
	GameState.mission_objectives = []
	GameState.quest_item_acquired = true
	GameState.ever_spotted = false
	GameState.ever_chased = false


func _snapshot() -> void:
	_save_snap = (SaveSystem.data as Dictionary).duplicate(true)
	_gs_snap = {
		"state": GameState.state,
		"phase": GameState.phase,
		"elapsed": GameState.elapsed_sec,
		"run_limit": GameState.run_time_limit,
		"endgame_limit": GameState.endgame_time_limit,
		"endgame_elapsed": GameState.endgame_elapsed,
		"markers": GameState.escape_markers.duplicate(true),
		"extracted": GameState.extracted_players.duplicate(),
		"collected": GameState.loot_collected,
		"needed": GameState.loot_needed,
		"value": GameState.loot_value,
		"goal": GameState.loot_goal,
		"carried": GameState.carried_loot.duplicate(true),
		"tracking": GameState.carried_tracking_active,
		"stashed": GameState.stashed_loot_value,
		"run_id": GameState.loot_run_id,
		"last_payout": GameState.last_payout.duplicate(true),
		"objectives": GameState.mission_objectives.duplicate(true),
		"quest_item": GameState.quest_item_acquired,
		"free_play": GameState.free_play,
		"free_play_pending": GameState.free_play_pending,
		"pending_mission": GameState.pending_mission_id,
		"order": GameState.active_contract_order,
		"map": GameState.active_map_id,
		"mission": GameState.active_mission_id,
		"difficulty": GameState.difficulty,
		"spotted": GameState.ever_spotted,
		"chased": GameState.ever_chased,
		"seed": GameState.active_map_seed,
		"variants": GameState.active_scene_variants.duplicate(),
		"net_coop": NetManager.is_coop,
	}


func _restore() -> void:
	GameState.state = str(_gs_snap.get("state", "menu"))
	GameState.phase = str(_gs_snap.get("phase", GameState.PHASE_MAIN))
	GameState.elapsed_sec = float(_gs_snap.get("elapsed", 0.0))
	GameState.run_time_limit = float(_gs_snap.get("run_limit", 0.0))
	GameState.endgame_time_limit = float(_gs_snap.get("endgame_limit", 0.0))
	GameState.endgame_elapsed = float(_gs_snap.get("endgame_elapsed", 0.0))
	GameState.escape_markers = _gs_snap.get("markers", []) as Array[Dictionary]
	GameState.extracted_players = _gs_snap.get("extracted", []) as Array[int]
	GameState.loot_collected = int(_gs_snap.get("collected", 0))
	GameState.loot_needed = int(_gs_snap.get("needed", 0))
	GameState.loot_value = int(_gs_snap.get("value", 0))
	GameState.loot_goal = int(_gs_snap.get("goal", 0))
	GameState.carried_loot = _gs_snap.get("carried", []) as Array[Dictionary]
	GameState.carried_tracking_active = bool(_gs_snap.get("tracking", false))
	GameState.stashed_loot_value = int(_gs_snap.get("stashed", 0))
	GameState.loot_run_id = str(_gs_snap.get("run_id", ""))
	GameState.last_payout = _gs_snap.get("last_payout", {}) as Dictionary
	GameState.mission_objectives = _gs_snap.get("objectives", []) as Array[Dictionary]
	GameState.quest_item_acquired = bool(_gs_snap.get("quest_item", false))
	GameState.free_play = bool(_gs_snap.get("free_play", false))
	GameState.free_play_pending = bool(_gs_snap.get("free_play_pending", false))
	GameState.pending_mission_id = str(_gs_snap.get("pending_mission", ""))
	GameState.active_contract_order = int(_gs_snap.get("order", 2))
	GameState.active_map_id = str(_gs_snap.get("map", "old_manor"))
	GameState.active_mission_id = str(_gs_snap.get("mission", ""))
	GameState.difficulty = int(_gs_snap.get("difficulty", 1))
	GameState.ever_spotted = bool(_gs_snap.get("spotted", false))
	GameState.ever_chased = bool(_gs_snap.get("chased", false))
	GameState.active_map_seed = int(_gs_snap.get("seed", 0))
	GameState.active_scene_variants = _gs_snap.get("variants", []) as Array[String]
	NetManager.is_coop = bool(_gs_snap.get("net_coop", false))
	NetManager.set_test_peer_id(0)
	SaveSystem.data = _save_snap
	SaveSystem.write_save()


## RE-N-11 transport gates: the outcome vocabulary is closed and the host gate
## rejects an unknown outcome and an unreadable sender. Run before any mission
## instance connects to `run_requested`.
func _check_transport_bounds(problems: Array[String]) -> void:
	var before_count: int = problems.size()
	var constant_map: Dictionary = NetManager.get_script().get_script_constant_map()
	_expect(
		problems,
		constant_map.get("RUN_OUTCOMES", []) == ["escape", "capture", "timeout"],
		"RE-N-11 transport: RUN_OUTCOMES allowlist missing or open (got %s)" % str(constant_map.get("RUN_OUTCOMES", null))
	)
	var has_gate: bool = NetManager.has_method("_host_accept_run_request")
	_expect(problems, has_gate, "RE-N-11 transport: host run-request gate missing")
	if has_gate:
		var rejects0: int = _nm_counter("run_resolved_reject_count")
		NetManager.call("_host_accept_run_request", "drop_table", 2)
		_expect(
			problems,
			_nm_counter("run_resolved_reject_count") == rejects0 + 1,
			"RE-N-11 transport: unknown outcome was not rejected"
		)
		NetManager.call("_host_accept_run_request", "escape", 0)
		_expect(
			problems,
			_nm_counter("run_resolved_reject_count") == rejects0 + 2,
			"RE-N-11 transport: sender id 0 was not rejected"
		)
	if problems.size() == before_count:
		print("PASS: T02-B transport gates (closed outcome allowlist, host validation)")


## RE-N-11 transport visual: the Chameleon remote body must resolve the authored
## `Skin/Base/SK_ThiefCotter__Body.glb` (the old `Dyn/` candidate never existed
## on disk, so a Chameleon always fell back to the capsule), and every candidate
## list entry must be an existing imported scene or be skipped.
func _check_remote_visual_paths(problems: Array[String]) -> void:
	var before_count: int = problems.size()
	var constant_map: Dictionary = NetManager.get_script().get_script_constant_map()
	var candidates: Array = constant_map.get("REMOTE_GLB_CANDIDATES", []) as Array
	_expect(problems, not candidates.is_empty(), "RE-N-11 visual: REMOTE_GLB_CANDIDATES missing")
	for path_v: Variant in candidates:
		var path: String = str(path_v)
		_expect(problems, not path.contains("ThiefCotter/Skin/Base/Dyn/"), "RE-N-11 visual: bogus Cotter Dyn/ candidate %s" % path)
		if ResourceLoader.exists(path):
			_expect(problems, ResourceLoader.load(path) is PackedScene, "RE-N-11 visual: existing candidate is not an imported scene: %s" % path)
	var chameleon: PackedScene = NetManager.call("_find_remote_packed", "chameleon") as PackedScene
	var spider: PackedScene = NetManager.call("_find_remote_packed", "spider") as PackedScene
	_expect(problems, chameleon != null, "RE-N-11 visual: Chameleon remote body did not resolve")
	if chameleon != null:
		var canonical: String = str((GameState.THIEF_BASE_MESHES.get("chameleon", {}) as Dictionary).get("body", ""))
		_expect(problems, chameleon.resource_path == canonical, "RE-N-11 visual: Chameleon resolved %s (want %s)" % [chameleon.resource_path, canonical])
	_expect(problems, spider != null, "RE-N-11 visual: Spider remote body did not resolve")
	if spider != null:
		_expect(problems, spider.resource_path.find("ThiefNisha") >= 0, "RE-N-11 visual: Spider resolved %s" % spider.resource_path)
	if problems.size() == before_count:
		print("PASS: T02-B remote visuals resolve the authored per-thief bodies")


## RE-N-14/RE-N-16 (T02-A contract): a reset is a fresh run — seed cleared,
## per-run arrays emptied, phase back to main and *published* so a listener
## cannot desync at mission start.
func _check_reset_clears(problems: Array[String]) -> void:
	var before_count: int = problems.size()
	GameState.active_map_seed = 123456
	GameState.active_scene_variants = ["SV_Test"] as Array[String]
	GameState.escape_markers = [{"index": 0, "gate": null}] as Array[Dictionary]
	GameState.extracted_players = [1] as Array[int]
	GameState.carried_loot = [{"name": "Purse", "value": 45}] as Array[Dictionary]
	GameState.last_payout = {"match_id": "stale"} as Dictionary
	GameState.phase = GameState.PHASE_RESOLVED
	var emits: Array[int] = [0]
	var on_phase: Callable = func(_p: String) -> void: emits[0] += 1
	GameState.phase_changed.connect(on_phase)
	GameState.reset_run(2, "guildhall")
	GameState.phase_changed.disconnect(on_phase)
	var first_run_id: String = GameState.loot_run_id
	_expect(problems, GameState.active_map_seed == 0, "reset_run left active_map_seed=%d (want 0)" % GameState.active_map_seed)
	_expect(problems, GameState.active_scene_variants.is_empty(), "reset_run left %d scene variants" % GameState.active_scene_variants.size())
	_expect(problems, GameState.escape_markers.is_empty(), "reset_run left %d escape markers" % GameState.escape_markers.size())
	_expect(problems, GameState.extracted_players.is_empty(), "reset_run left %d extracted players" % GameState.extracted_players.size())
	_expect(problems, GameState.carried_loot.is_empty(), "reset_run left %d carried entries" % GameState.carried_loot.size())
	_expect(problems, GameState.last_payout.is_empty(), "reset_run kept the stale last_payout")
	_expect(problems, GameState.phase == GameState.PHASE_MAIN, "reset_run phase=%s (want main)" % GameState.phase)
	_expect(problems, emits[0] == 1, "reset_run emitted phase_changed %d time(s) (want 1)" % emits[0])
	# start_contract loads a map, so the derivation is asserted through its
	# contract: the reset leaves 0 so the next deploy derives from map|order,
	# and the two deploy strings hash to different seeds.
	GameState.reset_run(3, "old_manor")
	var second_run_id: String = GameState.loot_run_id
	_expect(problems, GameState.active_map_seed == 0, "second reset_run left active_map_seed=%d (want 0)" % GameState.active_map_seed)
	_expect(problems, first_run_id != second_run_id, "two runs shared loot_run_id %s" % first_run_id)
	var seed_a: int = LEVEL_LOADER._sv_fnv1a("guildhall|2") & 0x7FFFFFFF
	var seed_b: int = LEVEL_LOADER._sv_fnv1a("old_manor|3") & 0x7FFFFFFF
	_expect(problems, seed_a != seed_b, "map|order seed derivation is not map-specific (%d/%d)" % [seed_a, seed_b])
	if problems.size() == before_count:
		print("PASS: T02-B reset clears the run and republishes the phase")


## RE-N-15: the Den is the hub. It must own no mission clock, so idling can
## never expire it; the very next map row is still applied, so the guard is
## Den-only.
func _check_hub_clock(problems: Array[String]) -> void:
	var before_count: int = problems.size()
	GameState.reset_run(1, "thieves_den")
	GameState.active_mission_id = ""
	GameState.difficulty = 1
	var mc: Node = _new_mission()
	var clock: Dictionary = mc.call("_apply_run_clock", "thieves_den") as Dictionary
	_expect(problems, float(GameState.run_time_limit) == 0.0, "hub run_time_limit=%s (want 0)" % str(GameState.run_time_limit))
	_expect(problems, float(GameState.endgame_time_limit) == 0.0, "hub endgame_time_limit=%s (want 0)" % str(GameState.endgame_time_limit))
	_expect(problems, str(clock.get("main_source", "")) == "hub", "hub main_source=%s (want hub)" % str(clock.get("main_source", "")))
	_expect(problems, str(clock.get("endgame_source", "")) == "hub", "hub endgame_source=%s (want hub)" % str(clock.get("endgame_source", "")))
	_expect(problems, clock.get("mission_row", true) == false, "hub reported a mission_row")
	mc.set("_is_thieves_den", true)
	mc.call("_process", 6000.0)
	_expect(problems, GameState.state == "playing", "hub idled into state=%s (want playing)" % GameState.state)
	var info: Dictionary = mc.get("contract_info") as Dictionary
	_expect(problems, not bool(info.get("timed_out", false)), "hub timeout_reason=%s (want none)" % str(info.get("timeout_reason", "")))
	mc.free()
	# Control: the next map still gets its authored map row (7200 s Novice).
	var control: Node = _new_mission()
	GameState.active_mission_id = ""
	GameState.difficulty = 1
	var map_clock: Dictionary = control.call("_apply_run_clock", "guildhall") as Dictionary
	_expect(
		problems,
		absf(float(GameState.run_time_limit) - 7200.0) < 0.5 and str(map_clock.get("main_source", "")) == "map_row",
		"map row after the hub: main=%s source=%s (want 7200 map_row)" % [str(GameState.run_time_limit), str(map_clock.get("main_source", ""))]
	)
	control.free()
	if problems.size() == before_count:
		print("PASS: T02-B hub has no mission clock (Den-only guard)")


## RE-N-08: every failure path banks the stashed value exactly once, resolves
## the phase, mirrors the *banked* record into GameState.last_payout and is
## inert on a repeat call.
func _check_failure_banking(problems: Array[String]) -> void:
	var before_count: int = problems.size()
	_failure_case(problems, "capture", "capture", "", func(mc: Node) -> void: mc.call("_on_player_downed"))
	_failure_case(problems, "main timeout", "timeout", TIME_EXPIRED_REASON, func(mc: Node) -> void: mc.call("_on_time_expired"))
	_failure_case(problems, "door collapse", "timeout", DOOR_COLLAPSED_REASON, func(mc: Node) -> void: mc.call("_on_door_collapsed"))
	if problems.size() == before_count:
		print("PASS: T02-B capture/timeout/collapse bank the stash once and resolve")


func _failure_case(problems: Array[String], label: String, outcome: String, reason: String, call: Callable) -> void:
	var run_id: String = "t02-b-%s-%d" % [outcome, Time.get_ticks_usec()]
	_stage_run("guildhall", 2, 750, 1000, run_id)
	var mc: Node = _new_mission()
	var before: int = _currency()
	call.call(mc)
	var after: int = _currency()
	var last: Dictionary = SaveSystem.get_last_match()
	_expect(problems, after - before == 750, "%s banked %d (want the stashed 750)" % [label, after - before])
	_expect(problems, str(last.get("match_id", "")) == run_id, "%s recorded match_id=%s (want %s)" % [label, str(last.get("match_id", "")), run_id])
	_expect(problems, int(last.get("kept", -1)) == 0 and int(last.get("reward", -1)) == 0, "%s kept=%s reward=%s (want 0/0)" % [label, str(last.get("kept", "")), str(last.get("reward", ""))])
	_expect(problems, GameState.state == "failed", "%s state=%s (want failed)" % [label, GameState.state])
	_expect(problems, GameState.phase == GameState.PHASE_RESOLVED, "%s phase=%s (want resolved)" % [label, GameState.phase])
	var mirrored: Dictionary = GameState.last_payout
	_expect(
		problems,
		bool(mirrored.get("applied", false)) and int(mirrored.get("banked", -1)) == 750,
		"%s last_payout applied=%s banked=%s (want true/750, the banked record)" % [label, str(mirrored.get("applied", null)), str(mirrored.get("banked", null))]
	)
	var info: Dictionary = mc.get("contract_info") as Dictionary
	if reason != "":
		_expect(problems, bool(info.get("timed_out", false)) and str(info.get("timeout_reason", "")) == reason, "%s timeout reason=%s (want %s)" % [label, str(info.get("timeout_reason", "")), reason])
	# A repeat signal cannot bank again or rewrite the recorded match.
	call.call(mc)
	_expect(problems, _currency() == after, "%s repeat call changed currency" % label)
	_expect(problems, str(SaveSystem.get_last_match().get("match_id", "")) == run_id, "%s repeat call rewrote last_match" % label)
	mc.free()


## RE-N-08 / E2E S2-10: escape banks carried + stashed + reward once, mirrors
## the banked record, and the *API* rejects a replay by match_id.
func _check_escape_banking(problems: Array[String]) -> void:
	var before_count: int = problems.size()
	var run_id: String = "t02-b-escape-%d" % Time.get_ticks_usec()
	_stage_run("guildhall", 2, 750, 1000, run_id)
	var mc: Node = _new_mission()
	var before: int = _currency()
	mc.call("_on_extracted")
	var after: int = _currency()
	var last: Dictionary = SaveSystem.get_last_match()
	var banked: int = int(last.get("banked", -1))
	_expect(problems, str(last.get("match_id", "")) == run_id, "escape recorded match_id=%s (want %s)" % [str(last.get("match_id", "")), run_id])
	_expect(problems, int(last.get("kept", -1)) == 1000 and int(last.get("stashed", -1)) == 750 and int(last.get("reward", -1)) == 1000, "escape Original/Kept/Stashed/Reward wrong (%s/%s/%s/%s)" % [str(last.get("original", "")), str(last.get("kept", "")), str(last.get("stashed", "")), str(last.get("reward", ""))])
	_expect(problems, after - before == banked and banked > 0, "escape banked %d (want %d)" % [after - before, banked])
	_expect(problems, GameState.state == "victory", "escape state=%s (want victory)" % GameState.state)
	_expect(problems, GameState.phase == GameState.PHASE_RESOLVED, "escape phase=%s (want resolved)" % GameState.phase)
	var mirrored: Dictionary = GameState.last_payout
	_expect(problems, bool(mirrored.get("applied", false)) and int(mirrored.get("banked", -1)) == banked, "escape last_payout applied=%s banked=%s (want true/%d)" % [str(mirrored.get("applied", null)), str(mirrored.get("banked", null)), banked])
	# Replay through the public API: the match_id key is what makes this a
	# duplicate, so the assertion does not ride the handler's own guard.
	var replay: Dictionary = SaveSystem.bank_payout(SaveSystem.get_last_match())
	_expect(problems, str(replay.get("reason", "")) == "duplicate", "bank_payout replay reason=%s (want duplicate)" % str(replay.get("reason", "")))
	_expect(problems, not bool(replay.get("applied", true)), "bank_payout replay marked applied")
	_expect(problems, _currency() == after, "bank_payout replay changed currency")
	mc.free()
	if problems.size() == before_count:
		print("PASS: T02-B escape banks once and the match_id replay is a duplicate")


## RE-N-11 host: one bank, one broadcast, and neither a client request nor the
## host's own second extraction can bank again.
func _check_coop_host_once(problems: Array[String]) -> void:
	var before_count: int = problems.size()
	if not NetManager.has_signal("run_requested") or not NetManager.has_signal("run_resolved"):
		_expect(problems, false, "RE-N-11 host: run_requested/run_resolved transport signals missing")
		return
	NetManager.is_coop = true
	NetManager.set_test_peer_id(1)
	var run_id: String = "t02-b-host-%d" % Time.get_ticks_usec()
	_stage_run("guildhall", 2, 250, 1000, run_id)
	var mc: Node = _new_mission()
	_expect(problems, mc.has_method("_finish_run"), "RE-N-11 host: mission_controller has no _finish_run")
	if not mc.has_method("_finish_run"):
		mc.free()
		return
	mc.call("_connect_coop_listener")
	var before: int = _currency()
	var sends0: int = _nm_counter("run_resolved_send_count")
	mc.call("_finish_run", "escape", "", -1)
	var after: int = _currency()
	var last: Dictionary = SaveSystem.get_last_match()
	_expect(problems, GameState.state == "victory", "host finish state=%s (want victory)" % GameState.state)
	_expect(problems, after - before == int(last.get("money_taken", -1)), "host finish banked %d (want %d)" % [after - before, int(last.get("money_taken", -1))])
	_expect(problems, _nm_counter("run_resolved_send_count") == sends0 + 1, "host broadcast count=%d (want %d)" % [_nm_counter("run_resolved_send_count"), sends0 + 1])
	if NetManager.has_signal("run_requested"):
		NetManager.emit_signal("run_requested", "escape", 2)
	_expect(problems, _currency() == after, "client request after the host banked changed currency")
	_expect(problems, _nm_counter("run_resolved_send_count") == sends0 + 1, "client request after the host banked re-broadcast")
	# Re-open the phase gate so the call reaches the payout guard itself.
	GameState.phase = GameState.PHASE_ENDGAME
	mc.call("_on_escape_gate_extracted", null)
	_expect(problems, _currency() == after, "host re-extraction changed currency")
	_expect(problems, GameState.state == "victory", "host re-extraction changed state to %s" % GameState.state)
	mc.free()
	NetManager.set_test_peer_id(0)
	NetManager.is_coop = false
	if problems.size() == before_count:
		print("PASS: T02-B co-op host banks and broadcasts once")


## RE-N-11 client: the host's banked record is applied verbatim, the currency
## delta matches the host's `banked`, and the client's own clock cannot convert
## the resolved run into a timeout failure.
func _check_coop_client_resolves(problems: Array[String]) -> void:
	var before_count: int = problems.size()
	if not NetManager.has_signal("run_resolved"):
		_expect(problems, false, "RE-N-11 client: run_resolved transport signal missing")
		return
	# Build the host record first (host peer 1), then simulate the client's own
	# profile by restoring the pre-suite save data: two processes have two saves.
	NetManager.is_coop = true
	NetManager.set_test_peer_id(1)
	var run_id: String = "t02-b-client-%d" % Time.get_ticks_usec()
	_stage_run("guildhall", 2, 250, 1000, run_id)
	var host_mc: Node = _new_mission()
	if not host_mc.has_method("_finish_run"):
		host_mc.free()
		_expect(problems, false, "RE-N-11 client: mission_controller has no _finish_run")
		return
	var host_before: int = _currency()
	host_mc.call("_finish_run", "escape", "", -1)
	var host_record: Dictionary = SaveSystem.get_last_match().duplicate(true)
	var host_banked: int = int(host_record.get("banked", -1))
	var host_delta: int = _currency() - host_before
	host_mc.free()
	SaveSystem.data = _save_snap.duplicate(true)
	SaveSystem.write_save()
	# Client peer id 2.
	NetManager.set_test_peer_id(2)
	_stage_run("guildhall", 2, 0, 0, run_id)
	GameState.phase = GameState.PHASE_ENDGAME
	var client_mc: Node = _new_mission()
	client_mc.call("_connect_coop_listener")
	var client_before: int = _currency()
	var sends0: int = _nm_counter("run_resolved_send_count")
	NetManager.emit_signal("run_resolved", "escape", host_record)
	var client_after: int = _currency()
	_expect(problems, GameState.state == "victory", "client resolve state=%s (want victory)" % GameState.state)
	_expect(problems, GameState.phase == GameState.PHASE_RESOLVED, "client resolve phase=%s (want resolved)" % GameState.phase)
	_expect(problems, str(GameState.last_payout.get("match_id", "")) == str(host_record.get("match_id", "")), "client last_payout match_id=%s (want %s)" % [str(GameState.last_payout.get("match_id", "")), str(host_record.get("match_id", ""))])
	_expect(problems, client_after - client_before == host_banked, "client banked %d (want the host's %d)" % [client_after - client_before, host_banked])
	_expect(problems, host_delta == host_banked, "host banked %d but recorded %d" % [host_delta, host_banked])
	_expect(problems, _nm_counter("run_resolved_send_count") == sends0, "client broadcast the run outcome")
	client_mc.call("_process", 999999.0)
	_expect(problems, GameState.state == "victory", "client clock expired the resolved run into %s" % GameState.state)
	_expect(problems, _currency() == client_after, "client clock changed currency after resolution")
	client_mc.free()
	NetManager.set_test_peer_id(0)
	NetManager.is_coop = false
	if problems.size() == before_count:
		print("PASS: T02-B co-op client resolves from the host's banked record")


## RE-N-11 routing: a client extraction asks the host and never resolves or
## banks locally.
func _check_client_extraction_routes(problems: Array[String]) -> void:
	var before_count: int = problems.size()
	if not NetManager.has_signal("run_requested"):
		_expect(problems, false, "RE-N-11 routing: run_requested transport signal missing")
		return
	NetManager.is_coop = true
	NetManager.set_test_peer_id(2)
	var run_id: String = "t02-b-route-%d" % Time.get_ticks_usec()
	_stage_run("guildhall", 2, 250, 1000, run_id)
	GameState.phase = GameState.PHASE_ENDGAME
	var mc: Node = _new_mission()
	var requests0: int = _nm_counter("run_request_count")
	var before: int = _currency()
	mc.call("_on_escape_gate_extracted", null)
	_expect(problems, GameState.state == "playing", "client extraction resolved locally (state=%s)" % GameState.state)
	_expect(problems, GameState.phase == GameState.PHASE_ENDGAME, "client extraction moved phase to %s" % GameState.phase)
	_expect(problems, GameState.extracted_players.is_empty(), "client extraction registered a local peer")
	_expect(problems, _currency() == before, "client extraction banked locally")
	_expect(problems, _nm_counter("run_request_count") == requests0 + 1, "client extraction reported %d request(s) (want 1)" % (_nm_counter("run_request_count") - requests0))
	mc.free()
	NetManager.set_test_peer_id(0)
	NetManager.is_coop = false
	if problems.size() == before_count:
		print("PASS: T02-B client extraction routes to the host")
