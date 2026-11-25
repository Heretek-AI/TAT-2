extends RefCounted
## W7S-S2 end-to-end cases (tier "s2").
##
## One real Guildhall mission load covers the whole carried-loot path with the
## shipped actors and markers: a real major loot item (one mesh instance, no
## authored-off light), carrying it at the 3-slot cost, a real secret-stash
## marker depositing it, the authored INVENTORY FULL refusal on a real pickup,
## and the escape payout banked once with Original/Kept/Stashed/MoneyTaken.
##
## Invocation:
##   tools/godot --headless --path game --script res://tests/e2e/run_e2e_tests.gd -- --tier=s2
##
## The suite snapshots SaveSystem.data (deep) and the GameState run fields and
## restores both, so later tiers see the same profile and run state.

const LootInventoryScript := preload("res://src/interact/loot_inventory.gd")
const LootStashScript := preload("res://src/interact/loot_stash.gd")

var h: RefCounted
var _save_snap: Dictionary = {}
var _gs_snap: Dictionary = {}


func _init(p_helpers: RefCounted) -> void:
	h = p_helpers


func run() -> void:
	_snapshot()
	var data_ok: bool = _check_generated_data()
	h.require(data_ok, "S2-01", "loot settings/producers resolve 12 slots, major 3, INVENTORY FULL, £1,000, stash kind")

	var res: Dictionary = await h.instantiate_mission(2, 400, 1)
	var mission: Node = res["mission"] as Node
	h.require(mission != null and not bool(res.get("timed_out", true)), "S2-02", "Guildhall contract mission loaded for the loot pass")
	if mission == null:
		_restore()
		return

	# Loot is spawned during mission setup; wait for the real wave.
	var loot_nodes: Array[Node] = []
	for _i: int in range(240):
		loot_nodes = h.tree.get_nodes_in_group("loot")
		if not loot_nodes.is_empty():
			break
		await h.step_process(1)
	h.require(not loot_nodes.is_empty(), "S2-03", "real Guildhall loot wave spawned (%d items)" % loot_nodes.size())

	var major: Node = _pick_tier(loot_nodes, "major")
	h.require(major != null, "S2-04", "real major loot actor present")
	if major != null:
		var root: Node3D = major.get("visual_root") as Node3D
		var meshes: Array[int] = [0]
		var lights: Array[int] = [0]
		if root != null:
			_count_render_nodes(root, meshes, lights)
		h.require(
			root != null and root.get_child_count() == 1 and meshes[0] >= 1 and lights[0] == 0,
			"S2-05",
			"major loot mesh: one visual root, %d mesh node(s), %d authored-off light(s)" % [meshes[0], lights[0]]
		)

	# Carry the real major actor: 3 slots, gross value monotonic, actor lingers.
	var value_before: int = int(GameState.loot_value)
	var major_value: int = int(major.get("value"))
	major.call("interact", null)
	var carried_ok: bool = GameState.carried_slots_used() >= 3 \
		and GameState.carried_loot.size() == 1 \
		and int((GameState.carried_loot[0] as Dictionary).get("slot_cost", 0)) == 3
	var linger_ok: bool = is_instance_valid(major) and bool(major.get_meta("collected", false)) and not major.is_in_group("loot")
	h.require(
		carried_ok and linger_ok and GameState.loot_value == value_before + major_value,
		"S2-06",
		"real major pickup: 3 slots, value %d -> %d, actor lingers out of the loot group" % [value_before, GameState.loot_value]
	)

	# Real secret-stash marker: one-use deposit-all.
	var stash: Node = _find_stash()
	var deposited: int = 0
	if stash != null:
		stash.call("interact", null)
		deposited = int(GameState.stashed_loot_value)
	var stash_ok: bool = stash != null and deposited >= major_value \
		and GameState.carried_loot.is_empty() \
		and int(stash.get("stash_uses")) == 0 \
		and GameState.loot_value == value_before + major_value
	h.require(
		stash_ok,
		"S2-07",
		"real secret stash deposit-all: %d stashed, uses=%s, gross value unchanged (%d)" % [
			deposited, str(stash.get("stash_uses")) if stash != null else "n/a", GameState.loot_value
		]
	)

	# Authored capacity refusal on a real pickup (fill the 12 slots first).
	var minors: Array[Node] = []
	for n_v: Variant in h.tree.get_nodes_in_group("loot"):
		if n_v is Node and str((n_v as Node).get("loot_tier")) == "minor" and not bool((n_v as Node).get_meta("collected", false)):
			minors.append(n_v as Node)
	for minor: Node in minors:
		if GameState.carried_slots_used() >= 12:
			break
		minor.call("interact", null)
	var refused: Node = null
	for minor2: Node in minors:
		if not bool(minor2.get_meta("collected", false)):
			refused = minor2
			break
	if refused != null:
		refused.call("interact", null)
	var toast: String = ""
	var hud: Node = mission.get("hud") as Node
	if hud != null:
		var lbl: Label = hud.get("clue_toast_lbl") as Label
		if lbl != null:
			toast = lbl.text
	h.require(
		GameState.carried_slots_used() == 12 and refused != null and not bool(refused.get_meta("collected", false)) and toast.find("INVENTORY FULL") >= 0,
		"S2-08",
		"12-slot cap refuses a real pickup with the authored line (toast='%s')" % toast
	)

	# Escape payout through the real mission handler. Force the contract
	# objective complete so the £1,000 reward is exercised, bank once, and
	# compare the save record with the live payout.
	GameState.set_mission_objectives([], 0)
	GameState.quest_item_acquired = true
	var carried_value: int = GameState.carried_total_value()
	var stashed: int = GameState.stashed_loot_value
	var original: int = GameState.loot_value
	var before_currency: int = int((SaveSystem.data as Dictionary).get("currency", 0))
	mission.call("_on_extracted")
	await h.step_process(1)
	var after_currency: int = int((SaveSystem.data as Dictionary).get("currency", 0))
	var last: Dictionary = SaveSystem.call("get_last_match")
	var stealth: float = float(GameState.compute_stealth_bonus_multiplier())
	var expected_score: int = int(round(float(carried_value) * stealth))
	var expected_money: int = expected_score + stashed + 1000
	h.require(
		int(last.get("original", -1)) == original
			and int(last.get("kept", -1)) == carried_value
			and int(last.get("stashed", -1)) == stashed
			and int(last.get("reward", -1)) == 1000
			and int(last.get("score", -1)) == expected_score
			and int(last.get("money_taken", -1)) == expected_money
			and after_currency - before_currency == expected_money,
		"S2-09",
		"escape payout Original=%d Kept=%d Stashed=%d Reward=1000 MoneyTaken=%d banked=%d" % [
			original, carried_value, stashed, expected_money, after_currency - before_currency
		]
	)

	# RE-N-18 / S2-10: replay the same banked record through the public API. The
	# old case called `_on_extracted` again, which returned at its own
	# `_payout_applied` guard (4386), so the match_id key was never exercised.
	var before_replay: int = int((SaveSystem.data as Dictionary).get("currency", 0))
	var replay: Dictionary = SaveSystem.bank_payout(SaveSystem.get_last_match())
	await h.step_process(1)
	h.require(
		str(replay.get("reason", "")) == "duplicate"
			and not bool(replay.get("applied", true))
			and int((SaveSystem.data as Dictionary).get("currency", 0)) == before_replay,
		"S2-10",
		"repeat bank is idempotent through the API (reason=%s, currency stays %d)" % [str(replay.get("reason", "")), before_replay]
	)

	# Capture model keeps only the stashed value (unit-covered; asserted here
	# against the same live run so the binary keep rule is end-to-end).
	var capture: Dictionary = LootInventoryScript.build_payout("capture", {"objectives_complete": true, "match_id": "s2-capture"})
	h.require(
		int(capture.get("kept", -1)) == 0 and int(capture.get("reward", -1)) == 0 and int(capture.get("money_taken", -1)) == stashed,
		"S2-11",
		"capture keeps stashed only (%d), no reward, no carried haul" % stashed
	)

	# RE-N-18 / S2-12: a second run staged as free play with its own loot_run_id
	# must record the same haul arithmetic but bank 0, write no contract and
	# leave currency/xp unchanged. The old case compared
	# `last_payout.free_play` with `GameState.free_play` — the flag with itself.
	var currency_before_free: int = int((SaveSystem.data as Dictionary).get("currency", 0))
	var contracts_before_free: Dictionary = ((SaveSystem.data as Dictionary).get("completed_contracts", {}) as Dictionary).duplicate(true)
	var xp_before_free: int = int((SaveSystem.data as Dictionary).get("xp", 0))
	var free_run_id: String = "s2-free-%d" % int(Time.get_ticks_usec())
	GameState.free_play = true
	GameState.loot_run_id = free_run_id
	GameState.state = "playing"
	GameState.set_mission_objectives([], 0)
	GameState.quest_item_acquired = true
	mission.set("_payout_applied", false)
	mission.call("_on_extracted")
	await h.step_process(1)
	var free_last: Dictionary = SaveSystem.call("get_last_match")
	h.require(
		bool(free_last.get("free_play", false))
			and str(free_last.get("match_id", "")) == free_run_id
			and int(free_last.get("kept", -1)) == carried_value
			and int(free_last.get("stashed", -1)) == stashed
			and int(free_last.get("score", -1)) == expected_score
			and int(free_last.get("reward", -1)) == 0
			and int(free_last.get("money_taken", -1)) == expected_score + stashed
			and int(free_last.get("banked", -1)) == 0
			and int((SaveSystem.data as Dictionary).get("currency", 0)) == currency_before_free
			and int((SaveSystem.data as Dictionary).get("xp", 0)) == xp_before_free
			and ((SaveSystem.data as Dictionary).get("completed_contracts", {}) as Dictionary) == contracts_before_free,
		"S2-12",
		"free-play escape records the same haul (Kept=%d Stashed=%d Score=%d) but banks 0, writes no contract, keeps currency/xp" % [carried_value, stashed, expected_score]
	)

	await h.free_node(mission)
	_restore()


# ---------------------------------------------------------------- helpers ---
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
		"state": GameState.state,
		"difficulty": GameState.difficulty,
		"spotted": GameState.ever_spotted,
		"chased": GameState.ever_chased,
		"map": GameState.active_map_id,
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
	GameState.state = str(_gs_snap.get("state", "playing"))
	GameState.difficulty = int(_gs_snap.get("difficulty", 1))
	GameState.ever_spotted = bool(_gs_snap.get("spotted", false))
	GameState.ever_chased = bool(_gs_snap.get("chased", false))
	GameState.active_map_id = str(_gs_snap.get("map", "old_manor"))
	GameState.active_mission_id = str(_gs_snap.get("mission", ""))
	GameState.mission_objectives = _gs_snap.get("objectives", []) as Array[Dictionary]
	GameState.quest_item_acquired = bool(_gs_snap.get("quest_item", false))
	SaveSystem.data = _save_snap
	SaveSystem.write_save()


func _check_generated_data() -> bool:
	var settings: Dictionary = LootInventoryScript.settings()
	if settings.is_empty():
		return false
	var ok: bool = LootInventoryScript.max_slots() == 12 \
		and LootInventoryScript.tier_slot_cost("major") == 3 \
		and LootInventoryScript.tier_slot_cost("minor") == 1 \
		and LootInventoryScript.refusal_text() == "INVENTORY FULL" \
		and LootInventoryScript.contract_reward("guildhall") == 1000 \
		and LootStashScript.default_uses() == 1
	var containers: Variant = h.read_json("res://data/generated/gameplay/containers.json")
	if containers is Dictionary:
		var classes: Variant = (containers as Dictionary).get("classes", {})
		if classes is Dictionary:
			var stash: Dictionary = (classes as Dictionary).get("BP_LootStashInteractable_Secret_ThinWall_C", {}) as Dictionary
			ok = ok and str(stash.get("kind", "")) == "stash" and int(stash.get("stash_uses", 0)) == 1
	return ok


func _pick_tier(nodes: Array[Node], tier: String) -> Node:
	for n: Node in nodes:
		if str(n.get("loot_tier")) == tier and not bool(n.get_meta("collected", false)):
			return n
	return null


func _find_stash() -> Node:
	for n_v: Variant in h.tree.get_nodes_in_group("loot_containers"):
		if n_v is Node and bool((n_v as Node).get("is_stash")) and int((n_v as Node).get("stash_uses")) > 0:
			return n_v as Node
	return null


func _count_render_nodes(node: Node, meshes: Array[int], lights: Array[int]) -> void:
	if node is MeshInstance3D:
		meshes[0] += 1
	if node is Light3D:
		lights[0] += 1
	for child: Node in node.get_children():
		_count_render_nodes(child, meshes, lights)
