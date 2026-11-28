extends RefCounted
## Phase 3B.5 end-to-end cases (tier "s2"): Cleanout as a first-class mission.
##
## One real Guildhall deploy on the authored Mission.Guildhall.LootTheRoom row
## with free_play=false covers:
##   * the side-mission row drives the run (3300 s Novice window, 4,000 loot
##     goal, safe-room spawn) instead of the 7200 s hosting-contract fallback;
##   * the escape banks the haul exactly once but records no Contract 2
##     completion, no XP and no contract reward;
##   * a free-play run still banks nothing;
##   * the Den contract table exposes a separate Cleanout entry wired to the
##     first-class staging path (free_play stays false).
##
## Invocation:
##   tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=s2
##
## The suite snapshots SaveSystem.data (deep) and the GameState run fields and
## restores both, so later tiers see the same profile and run state.

const SAFE_ROOM_SPAWN_XZ: Vector2 = Vector2(127.2747, -5.3296)

var h: RefCounted
var _save_snap: Dictionary = {}
var _gs_snap: Dictionary = {}


func _init(p_helpers: RefCounted) -> void:
	h = p_helpers


func run() -> void:
	_snapshot()
	var res: Dictionary = await _deploy_cleanout()
	var mission: Node = res["mission"] as Node
	var player: Node = res["player"] as Node
	var deployed: bool = mission != null and not bool(res.get("timed_out", true))
	h.require(
		deployed
			and str(GameState.active_mission_id) == "Mission.Guildhall.LootTheRoom"
			and not GameState.free_play
			and GameState.cleanout_run
			and absf(GameState.run_time_limit - 3300.0) < 0.5
			and int(GameState.loot_goal) == 4000
			and _objective_label() == "Steal 4,000 in loot value",
		"S2-13",
		"cleanout deploy runs the authored side-mission row (mission=%s free_play=%s cleanout=%s main_s=%.0f goal=%d label='%s')" % [
			str(GameState.active_mission_id), str(GameState.free_play), str(GameState.cleanout_run),
			float(GameState.run_time_limit), int(GameState.loot_goal), _objective_label()
		]
	)
	var spawn_ok: bool = player is Node3D and str(mission.get("fallback_spawn_source")) == "authored"
	if player is Node3D:
		spawn_ok = spawn_ok and Vector2((player as Node3D).position.x, (player as Node3D).position.z).distance_to(SAFE_ROOM_SPAWN_XZ) < 2.5
	h.require(
		spawn_ok,
		"S2-14",
		"cleanout starts at the safe-room spawn (source=%s pos=%s)" % [
			str(mission.get("fallback_spawn_source")) if mission != null else "n/a",
			str((player as Node3D).position) if player is Node3D else "n/a"
		]
	)

	var bank_ok: bool = await _cleanout_banks_once(mission, mission != null)
	h.require(bank_ok, "S2-15", "cleanout escape banks the haul once with no Contract 2 credit or reward")

	var free_ok: bool = await _free_play_banks_nothing(mission, mission != null)
	h.require(free_ok, "S2-16", "free-play run records the haul but banks nothing and writes no contract")

	var ui_ok: bool = await _contract_table_exposes_cleanout()
	h.require(ui_ok, "S2-17", "contract table exposes a CLEANOUT entry wired to the first-class staging path (free_play=false)")

	var fail_ok: bool = await _cleanout_failure_paths_bank_once(mission, mission != null)
	h.require(fail_ok, "S2-18", "cleanout capture and timeout bank the stashed haul once with no contract credit")

	await h.free_node(mission)
	_restore()


# ---------------------------------------------------------------- helpers ---
func _deploy_cleanout() -> Dictionary:
	var gs: Node = h.game_state()
	# Stage exactly what prep READY does for the first-class Cleanout entry; the
	# mission scene's reset_run republishes the stash after the map-change wipe.
	gs.call("begin_cleanout", "Mission.Guildhall.LootTheRoom")
	return await h.instantiate_mission(2, 400, 1)


func _objective_label() -> String:
	var objs_v: Variant = GameState.mission_objectives
	if objs_v is Array:
		for o_v: Variant in (objs_v as Array):
			if o_v is Dictionary and str((o_v as Dictionary).get("id", "")) == "cleanout_loot":
				return str((o_v as Dictionary).get("label", ""))
	return ""


## Escape through the live mission handler. A contract would record Contract 2
## and pay the £1,000 reward because the objective flag is forced complete; a
## Cleanout must do neither while still banking score + stashed once.
func _cleanout_banks_once(mission: Node, have_mission: bool) -> bool:
	if not have_mission:
		return false
	var ss: Node = h.save_system()
	var save_data: Dictionary = ss.get("data") as Dictionary
	var before_contracts: Dictionary = (save_data.get("completed_contracts", {}) as Dictionary).duplicate(true)
	var before_xp: int = int(save_data.get("xp", 0))
	var before_currency: int = int(save_data.get("currency", 0))
	# Stage a real haul and force the escape objective complete so the reward
	# gate is genuinely exercised (a Cleanout must still pay 0).
	GameState.loot_value = 500
	GameState.stashed_loot_value = 100
	GameState.carried_loot = []
	GameState.carried_tracking_active = false
	GameState.set_mission_objectives([], 0)
	GameState.quest_item_acquired = true
	GameState.loot_run_id = "s2-cleanout-%d" % int(Time.get_ticks_usec())
	var run_id: String = GameState.loot_run_id
	mission.set("_payout_applied", false)
	mission.call("_on_extracted")
	await h.step_process(1)
	var last: Dictionary = ss.call("get_last_match")
	var stealth: float = float(GameState.compute_stealth_bonus_multiplier())
	var expected_score: int = int(round(500.0 * stealth))
	var expected_money: int = expected_score + 100
	var after_currency: int = int((save_data.get("currency", 0)) - before_currency)
	var once: bool = (
		str(last.get("match_id", "")) == run_id
		and str(last.get("mission_id", "")) == "Mission.Guildhall.LootTheRoom"
		and int(last.get("contract_order", -1)) == 2
		and int(last.get("kept", -1)) == 500
		and int(last.get("stashed", -1)) == 100
		and int(last.get("reward", -1)) == 0
		and int(last.get("score", -1)) == expected_score
		and int(last.get("money_taken", -1)) == expected_money
		and int(last.get("banked", -1)) == expected_money
		and after_currency == expected_money
		and int(save_data.get("xp", 0)) == before_xp
		and ((save_data.get("completed_contracts", {}) as Dictionary) == before_contracts)
	)
	# A second extract must not bank again (state is no longer "playing").
	mission.call("_on_extracted")
	await h.step_process(1)
	once = once and int((save_data.get("currency", 0))) == before_currency + expected_money \
		and str((ss.call("get_last_match") as Dictionary).get("match_id", "")) == run_id
	# Restore the profile rows this case moved so later checks see the snapshot.
	save_data["completed_contracts"] = before_contracts
	save_data["xp"] = before_xp
	save_data["currency"] = before_currency
	ss.call("write_save")
	return once


## A free-play run on the same live mission records the same arithmetic but
## banks 0 and touches neither currency, XP nor the contract table.
func _free_play_banks_nothing(mission: Node, have_mission: bool) -> bool:
	if not have_mission:
		return false
	var ss: Node = h.save_system()
	var save_data: Dictionary = ss.get("data") as Dictionary
	var before_contracts: Dictionary = (save_data.get("completed_contracts", {}) as Dictionary).duplicate(true)
	var before_xp: int = int(save_data.get("xp", 0))
	var before_currency: int = int(save_data.get("currency", 0))
	GameState.cleanout_run = false
	GameState.cleanout_pending = false
	GameState.begin_free_play("Mission.Guildhall.LootTheRoom")
	GameState.state = "playing"
	GameState.loot_value = 500
	GameState.stashed_loot_value = 100
	GameState.carried_loot = []
	GameState.carried_tracking_active = false
	GameState.set_mission_objectives([], 0)
	GameState.quest_item_acquired = true
	GameState.loot_run_id = "s2-cleanout-free-%d" % int(Time.get_ticks_usec())
	var run_id: String = GameState.loot_run_id
	mission.set("_payout_applied", false)
	mission.call("_on_extracted")
	await h.step_process(1)
	var last: Dictionary = ss.call("get_last_match")
	var stealth: float = float(GameState.compute_stealth_bonus_multiplier())
	var expected_score: int = int(round(500.0 * stealth))
	var ok: bool = (
		bool(last.get("free_play", false))
		and str(last.get("match_id", "")) == run_id
		and int(last.get("reward", -1)) == 0
		and int(last.get("banked", -1)) == 0
		and int(last.get("money_taken", -1)) == expected_score + 100
		and int(save_data.get("currency", 0)) == before_currency
		and int(save_data.get("xp", 0)) == before_xp
		and ((save_data.get("completed_contracts", {}) as Dictionary) == before_contracts)
	)
	save_data["completed_contracts"] = before_contracts
	save_data["xp"] = before_xp
	save_data["currency"] = before_currency
	ss.call("write_save")
	return ok


func _stage_and_finish_cleanout(mission: Node, outcome: String, run_id: String) -> bool:
	GameState.end_free_play()
	GameState.begin_cleanout("Mission.Guildhall.LootTheRoom")
	GameState.state = "playing"
	GameState.phase = GameState.PHASE_MAIN
	GameState.loot_value = 500
	GameState.stashed_loot_value = 100
	GameState.carried_loot = []
	GameState.carried_tracking_active = false
	GameState.set_mission_objectives([], 0)
	GameState.quest_item_acquired = false
	GameState.loot_run_id = run_id
	var before_currency: int = int(SaveSystem.get_currency())
	mission.set("_payout_applied", false)
	if outcome == "capture":
		mission.call("_on_player_downed")
	else:
		mission.call("_on_time_expired")
	await h.step_process(1)
	var last: Dictionary = SaveSystem.call("get_last_match")
	var ok: bool = (
		str(last.get("match_id", "")) == run_id
		and int(last.get("reward", -1)) == 0
		and int(last.get("kept", -1)) == 0
		and int(last.get("stashed", -1)) == 100
		and int(last.get("money_taken", -1)) == 100
		and int(last.get("banked", -1)) == 100
		and int(SaveSystem.get_currency()) == before_currency + 100
	)
	# Replay the same outcome: the run is already resolved, so nothing banks.
	if outcome == "capture":
		mission.call("_on_player_downed")
	else:
		mission.call("_on_time_expired")
	await h.step_process(1)
	return ok and int(SaveSystem.get_currency()) == before_currency + 100 \
		and str((SaveSystem.call("get_last_match") as Dictionary).get("match_id", "")) == run_id


## Capture and timeout/collapse each keep only the stashed haul and bank exactly
## once; neither may record Contract 2 or pay a reward.
func _cleanout_failure_paths_bank_once(mission: Node, have_mission: bool) -> bool:
	if not have_mission:
		return false
	var ss: Node = h.save_system()
	var save_data: Dictionary = ss.get("data") as Dictionary
	var before_contracts: Dictionary = (save_data.get("completed_contracts", {}) as Dictionary).duplicate(true)
	var before_xp: int = int(save_data.get("xp", 0))
	var before_currency: int = int(save_data.get("currency", 0))
	var capture_ok: bool = await _stage_and_finish_cleanout(
		mission, "capture", "s2-cleanout-capture-%d" % int(Time.get_ticks_usec()))
	var timeout_ok: bool = await _stage_and_finish_cleanout(
		mission, "timeout", "s2-cleanout-timeout-%d" % int(Time.get_ticks_usec()))
	var ok: bool = capture_ok and timeout_ok \
		and int(save_data.get("xp", 0)) == before_xp \
		and ((save_data.get("completed_contracts", {}) as Dictionary) == before_contracts) \
		and int(save_data.get("currency", 0)) == before_currency + 200
	save_data["completed_contracts"] = before_contracts
	save_data["xp"] = before_xp
	save_data["currency"] = before_currency
	ss.call("write_save")
	return ok


## The Den table's Cleanout entry must be its own control, wired to the
## first-class staging method, and must leave free_play false.
func _contract_table_exposes_cleanout() -> bool:
	var table_scr: GDScript = h.load_script("res://src/ui/contract_table_ui.gd")
	if table_scr == null:
		return false
	var table: Node = table_scr.new() as Node
	h.tree.root.add_child(table)
	await h.step_process(2)
	var btn: Button = _find_cleanout_button(table)
	var wired: bool = false
	if btn != null:
		for conn: Dictionary in btn.pressed.get_connections():
			var cb: Callable = conn.get("callable", Callable()) as Callable
			if cb.is_valid() and cb.get_method() == "_start_cleanout":
				wired = true
				break
	var has_stage: bool = h.has_m(table, "_stage_cleanout_selection")
	if has_stage:
		table.call("_stage_cleanout_selection")
	var ok: bool = btn != null and wired \
		and bool(table.get("cleanout")) and not bool(table.get("free_play")) \
		and int(table.get("selected_order")) == 2 and str(table.get("selected_map_id")) == "guildhall"
	await h.free_node(table)
	return ok


func _find_cleanout_button(node: Node) -> Button:
	if node is Button:
		var b: Button = node as Button
		if b.text.find("CLEANOUT HEIST") >= 0:
			return b
	for child: Node in node.get_children():
		var found: Button = _find_cleanout_button(child)
		if found != null:
			return found
	return null


func _snapshot() -> void:
	_save_snap = (SaveSystem.data as Dictionary).duplicate(true)
	_gs_snap = {
		"loot_value": GameState.loot_value,
		"loot_collected": GameState.loot_collected,
		"loot_goal": GameState.loot_goal,
		"loot_needed": GameState.loot_needed,
		"carried": GameState.carried_loot.duplicate(true),
		"tracking": GameState.carried_tracking_active,
		"stashed": GameState.stashed_loot_value,
		"run_id": GameState.loot_run_id,
		"last_payout": GameState.last_payout.duplicate(true),
		"free_play": GameState.free_play,
		"free_play_pending": GameState.free_play_pending,
		"pending_mission_id": GameState.pending_mission_id,
		"cleanout": GameState.cleanout_run,
		"cleanout_pending": GameState.cleanout_pending,
		"pending_cleanout_mission_id": GameState.pending_cleanout_mission_id,
		"state": GameState.state,
		"phase": GameState.phase,
		"elapsed": GameState.elapsed_sec,
		"run_time_limit": GameState.run_time_limit,
		"endgame_time_limit": GameState.endgame_time_limit,
		"difficulty": GameState.difficulty,
		"spotted": GameState.ever_spotted,
		"map": GameState.active_map_id,
		"contract": GameState.active_contract_order,
		"mission": GameState.active_mission_id,
		"objectives": GameState.mission_objectives.duplicate(true),
		"quest_item": GameState.quest_item_acquired,
	}


func _restore() -> void:
	GameState.loot_value = int(_gs_snap.get("loot_value", 0))
	GameState.loot_collected = int(_gs_snap.get("loot_collected", 0))
	GameState.loot_goal = int(_gs_snap.get("loot_goal", 0))
	GameState.loot_needed = int(_gs_snap.get("loot_needed", 0))
	GameState.carried_loot = _gs_snap.get("carried", []) as Array[Dictionary]
	GameState.carried_tracking_active = bool(_gs_snap.get("tracking", false))
	GameState.stashed_loot_value = int(_gs_snap.get("stashed", 0))
	GameState.loot_run_id = str(_gs_snap.get("run_id", ""))
	GameState.last_payout = _gs_snap.get("last_payout", {}) as Dictionary
	GameState.free_play = bool(_gs_snap.get("free_play", false))
	GameState.free_play_pending = bool(_gs_snap.get("free_play_pending", false))
	GameState.pending_mission_id = str(_gs_snap.get("pending_mission_id", ""))
	GameState.cleanout_run = bool(_gs_snap.get("cleanout", false))
	GameState.cleanout_pending = bool(_gs_snap.get("cleanout_pending", false))
	GameState.pending_cleanout_mission_id = str(_gs_snap.get("pending_cleanout_mission_id", ""))
	GameState.state = str(_gs_snap.get("state", "playing"))
	GameState.phase = str(_gs_snap.get("phase", "main"))
	GameState.elapsed_sec = float(_gs_snap.get("elapsed", 0.0))
	GameState.run_time_limit = float(_gs_snap.get("run_time_limit", 0.0))
	GameState.endgame_time_limit = float(_gs_snap.get("endgame_time_limit", 0.0))
	GameState.difficulty = int(_gs_snap.get("difficulty", 1))
	GameState.ever_spotted = bool(_gs_snap.get("spotted", false))
	GameState.active_map_id = str(_gs_snap.get("map", "old_manor"))
	GameState.active_contract_order = int(_gs_snap.get("contract", 2))
	GameState.active_mission_id = str(_gs_snap.get("mission", ""))
	GameState.mission_objectives = _gs_snap.get("objectives", []) as Array[Dictionary]
	GameState.quest_item_acquired = bool(_gs_snap.get("quest_item", false))
	SaveSystem.data = _save_snap
	SaveSystem.write_save()
