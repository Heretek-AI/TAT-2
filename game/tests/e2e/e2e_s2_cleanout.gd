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
	h.require(fail_ok, "S2-18", "cleanout capture, timeout and door-collapse bank the stashed haul once with no contract credit")

	var display_ok: bool = await _cleanout_display_copy(mission, mission != null)
	h.require(display_ok, "S2-19", "cleanout win shows no Contract 2 outcome row and a +0 XP breakdown (measured award 0)")

	var coop_ok: bool = await _coop_cleanout_skips_credit(mission, mission != null)
	h.require(coop_ok, "S2-20", "co-op cleanout resolve banks once without recording the hosting contract")

	var overlay_ok: bool = await _qa_side_mission_without_overlay()
	h.require(overlay_ok, "S2-21", "QA cleanout detection works without the contracts.json overlay (authored id/LootTheRoom fallback)")

	var hub_ok: bool = await _hub_return_clears_run_modes(mission, mission != null)
	h.require(hub_ok, "S2-22", "pause/continue hub return clears free-play and cleanout modes")

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
	var call_name: String = "_on_player_downed"
	if outcome == "timeout":
		call_name = "_on_time_expired"
	elif outcome == "collapse":
		call_name = "_on_door_collapsed"
	mission.call(call_name)
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
	mission.call(call_name)
	await h.step_process(1)
	return ok and int(SaveSystem.get_currency()) == before_currency + 100 \
		and str((SaveSystem.call("get_last_match") as Dictionary).get("match_id", "")) == run_id


## Capture, timeout and door-collapse each keep only the stashed haul and bank
## exactly once; none may record Contract 2 or pay a reward.
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
	var collapse_ok: bool = await _stage_and_finish_cleanout(
		mission, "collapse", "s2-cleanout-collapse-%d" % int(Time.get_ticks_usec()))
	var ok: bool = capture_ok and timeout_ok and collapse_ok \
		and int(save_data.get("xp", 0)) == before_xp \
		and ((save_data.get("completed_contracts", {}) as Dictionary) == before_contracts) \
		and int(save_data.get("currency", 0)) == before_currency + 300
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


## Stage a cleanout escape on the live mission (banks score+stashed, no
## contract credit) so the post-match display can be inspected.
func _stage_cleanout_win(mission: Node, run_id: String) -> void:
	GameState.end_free_play()
	GameState.begin_cleanout("Mission.Guildhall.LootTheRoom")
	GameState.state = "playing"
	GameState.phase = GameState.PHASE_MAIN
	GameState.loot_value = 500
	GameState.stashed_loot_value = 100
	GameState.carried_loot = []
	GameState.carried_tracking_active = false
	GameState.set_mission_objectives([], 0)
	GameState.quest_item_acquired = true
	GameState.loot_run_id = run_id
	mission.set("_payout_applied", false)
	mission.call("_on_extracted")
	await h.step_process(1)


## A Cleanout win must not display a Contract 2 completion row or the
## +20/+20/+80 successful XP breakdown while the measured award is +0.
func _cleanout_display_copy(mission: Node, have_mission: bool) -> bool:
	if not have_mission:
		return false
	var ss: Node = h.save_system()
	var save_data: Dictionary = ss.get("data") as Dictionary
	var before_contracts: Dictionary = (save_data.get("completed_contracts", {}) as Dictionary).duplicate(true)
	var before_xp: int = int(save_data.get("xp", 0))
	var before_currency: int = int(save_data.get("currency", 0))
	var run_id: String = "s2-cleanout-display-%d" % int(Time.get_ticks_usec())
	await _stage_cleanout_win(mission, run_id)
	var last: Dictionary = ss.call("get_last_match")
	var hud: Node = mission.get("hud") as Node
	var hud_contract: String = ""
	var hud_mission: String = ""
	if hud != null:
		hud_contract = str(hud.call("_post_match_contract_line", true))
		hud_mission = str(hud.call("_post_match_mission_line", true))
	var ui_scr: GDScript = h.load_script("res://src/ui/post_match_ui.gd")
	var ui: CanvasLayer = null
	if ui_scr != null:
		ui = ui_scr.new() as CanvasLayer
	var ui_ok: bool = false
	if ui != null:
		h.tree.root.add_child(ui)
		await h.step_process(2)
		ui.call("open_result", true, int(last.get("score", 0)), {}, 0)
		await h.step_process(2)
		var contract_lbl: Label = ui.get("_contract_lbl") as Label
		var contract_text: String = str(contract_lbl.text) if contract_lbl != null else "<missing>"
		var contract_visible: bool = contract_lbl.visible if contract_lbl != null else true
		var xp_values: Array[String] = _xp_value_texts(ui.get("_xp_box") as Node)
		var total_values: Array[String] = _xp_value_texts(ui.get("_total_box") as Node)
		var ui_text: String = ""
		for n_v: Node in ui.find_children("*", "Label", true, false):
			ui_text += (n_v as Label).text + "\n"
		ui_ok = contract_text == "" and not contract_visible \
			and not xp_values.is_empty() and _all_plus_zero(xp_values) \
			and total_values.size() == 1 and total_values[0] == "+0" \
			and ui_text.find("+20") < 0 and ui_text.find("+80") < 0
		ui.queue_free()
		await h.step_process(2)
	var ok: bool = str(last.get("match_id", "")) == run_id \
		and hud_contract == "" and hud_mission != "" and ui_ok \
		and int(save_data.get("xp", 0)) == before_xp \
		and ((save_data.get("completed_contracts", {}) as Dictionary) == before_contracts)
	save_data["completed_contracts"] = before_contracts
	save_data["xp"] = before_xp
	save_data["currency"] = before_currency
	ss.call("write_save")
	return ok


## Co-op resolve applies the host's banked record: a Cleanout must bank it but
## still skip record_contract_complete / XP (host and client share the gate).
func _coop_cleanout_skips_credit(mission: Node, have_mission: bool) -> bool:
	if not have_mission:
		return false
	var ss: Node = h.save_system()
	var save_data: Dictionary = ss.get("data") as Dictionary
	var before_contracts: Dictionary = (save_data.get("completed_contracts", {}) as Dictionary).duplicate(true)
	var before_xp: int = int(save_data.get("xp", 0))
	var before_currency: int = int(save_data.get("currency", 0))
	GameState.end_free_play()
	GameState.begin_cleanout("Mission.Guildhall.LootTheRoom")
	GameState.state = "playing"
	GameState.phase = GameState.PHASE_MAIN
	var run_id: String = "s2-cleanout-coop-%d" % int(Time.get_ticks_usec())
	GameState.loot_run_id = run_id
	mission.set("_payout_applied", false)
	var payout: Dictionary = {
		"match_id": run_id,
		"mission_id": "Mission.Guildhall.LootTheRoom",
		"contract_order": 2,
		"map_id": "guildhall",
		"outcome": "escape",
		"original": 500,
		"kept": 500,
		"stashed": 100,
		"reward": 0,
		"score": 500,
		"money_taken": 600,
		"stealth_mult": 1.0,
		"capture": false,
		"free_play": false,
		"applied": false,
		"banked": 0,
		"carried": [],
	}
	mission.call("_on_coop_run_resolved", "escape", payout)
	await h.step_process(1)
	var last: Dictionary = ss.call("get_last_match")
	var ok: bool = str(last.get("match_id", "")) == run_id \
		and int(last.get("banked", -1)) == 600 \
		and int(save_data.get("currency", 0)) == before_currency + 600 \
		and int(save_data.get("xp", 0)) == before_xp \
		and ((save_data.get("completed_contracts", {}) as Dictionary) == before_contracts) \
		and str(GameState.state) == "victory"
	save_data["completed_contracts"] = before_contracts
	save_data["xp"] = before_xp
	save_data["currency"] = before_currency
	ss.call("write_save")
	return ok


## The QA `--qa-mission` cleanout detection must not depend on the gitignored
## contracts.json overlay: the authored `.LootTheRoom` id (and the authored loot
## goals) is the fallback. Clearing both overlay-derived maps reproduces a fresh
## checkout without contracts.json.
func _qa_side_mission_without_overlay() -> bool:
	var gd: Node = h.game_data()
	if gd == null:
		return false
	var md_v: Variant = gd.get("mission_durations")
	var lg_v: Variant = gd.get("mission_loot_goals")
	var md: Dictionary = (md_v as Dictionary).duplicate(true) if md_v is Dictionary else {}
	var lg: Dictionary = (lg_v as Dictionary).duplicate(true) if lg_v is Dictionary else {}
	gd.set("mission_durations", {})
	gd.set("mission_loot_goals", {})
	var ok: bool = bool(gd.call("is_side_mission", "Mission.Guildhall.LootTheRoom")) \
		and bool(gd.call("is_side_mission", "Mission.OldManor.LootTheRoom")) \
		and not bool(gd.call("is_side_mission", "Mission.Guildhall.VaultHeist")) \
		and not bool(gd.call("is_side_mission", ""))
	gd.set("mission_durations", md)
	gd.set("mission_loot_goals", lg)
	return ok


## Both hub-return paths (pause RETURN TO DEN and post-match Continue) share one
## reset; no run mode may survive at the hub.
func _hub_return_clears_run_modes(mission: Node, have_mission: bool) -> bool:
	if not have_mission:
		return false
	var hud: Node = mission.get("hud") as Node
	if hud == null or not h.has_m(hud, "reset_run_modes_for_hub"):
		return false
	GameState.begin_cleanout("Mission.Guildhall.LootTheRoom")
	GameState.free_play_pending = true
	GameState.pending_mission_id = "Mission.Guildhall.LootTheRoom"
	hud.call("reset_run_modes_for_hub")
	return not GameState.cleanout_run and not GameState.cleanout_pending \
		and GameState.pending_cleanout_mission_id == "" \
		and not GameState.free_play and not GameState.free_play_pending \
		and GameState.pending_mission_id == "" \
		and int(GameState.active_contract_order) == 1


func _xp_value_texts(box: Node) -> Array[String]:
	var out: Array[String] = []
	if box == null:
		return out
	for row_v: Node in box.get_children():
		if not (row_v is HBoxContainer):
			continue
		var labels: Array[Node] = (row_v as HBoxContainer).get_children()
		if labels.size() == 2 and labels[0] is Label and labels[1] is Label:
			out.append((labels[1] as Label).text)
	return out


func _all_plus_zero(values: Array[String]) -> bool:
	for v: String in values:
		if v != "+0":
			return false
	return true


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
