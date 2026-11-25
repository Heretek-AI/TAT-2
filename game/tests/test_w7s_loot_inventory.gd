extends RefCounted
## Suite 89 (W7S-S2): carried loot inventory, one-use stash, payout model and
## producer provenance.
##
## Headless, no map load. The two real GLB instances only exercise loot_item's
## major-mesh path and the linger timer. Every GameState field this suite
## touches is snapshotted and restored so later suites see the same run state.
##
## Provenance assertions are skipped with an explicit SKIP line when the
## private extracted/ tree is absent (the generated data is still asserted).

const LootItemScript := preload("res://src/interact/loot_item.gd")
const LootInventoryScript := preload("res://src/interact/loot_inventory.gd")
const LootStashScript := preload("res://src/interact/loot_stash.gd")

const SETTINGS_PATH := "res://data/generated/gameplay/loot_settings.json"
const LOOT_ACTORS_PATH := "res://data/generated/gameplay/loot_actors.json"
const CONTAINERS_PATH := "res://data/generated/gameplay/containers.json"
const EX_PROJECT := "extracted/json/Core/BP_TATPlayerState.json"
const EX_STRINGS := "extracted/json/StringTables/ST_Interactables.json"
const EX_MAJOR := "extracted/json/Gameplay/Loot/Data/DT_LootInfo_Major.json"
const EX_MISSIONS := "game/data/generated/tables/Gameplay/Quests/DT_Missions_Guildhall.json"

var _snap: Dictionary = {}


func run(host: Node) -> Array[String]:
	var problems: Array[String] = []
	_snapshot()
	LootInventoryScript.reset_settings_cache()
	LootStashScript.reset_for_test()
	_check_provenance(host, problems)
	_check_capacity(host, problems)
	await _check_linger(host, problems)
	await _check_quest_items(host, problems)
	_check_stash(host, problems)
	_check_payout(problems)
	_restore()
	return problems


# ---------------------------------------------------------------- snapshot ---
func _snapshot() -> void:
	_snap = {
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
		"difficulty": GameState.difficulty,
		"spotted": GameState.ever_spotted,
		"chased": GameState.ever_chased,
		"map": GameState.active_map_id,
		"mission": GameState.active_mission_id,
		"state": GameState.state,
	}


func _restore() -> void:
	GameState.loot_value = int(_snap.get("loot_value", 0))
	GameState.loot_collected = int(_snap.get("loot_collected", 0))
	GameState.loot_goal = int(_snap.get("loot_goal", 0))
	GameState.loot_needed = int(_snap.get("loot_needed", 0))
	GameState.carried_loot = _snap.get("carried", []) as Array[Dictionary]
	GameState.carried_tracking_active = bool(_snap.get("tracking", false))
	GameState.stashed_loot_value = int(_snap.get("stashed", 0))
	GameState.loot_run_id = str(_snap.get("run_id", ""))
	GameState.last_payout = _snap.get("last_payout", {}) as Dictionary
	GameState.free_play = bool(_snap.get("free_play", false))
	GameState.difficulty = int(_snap.get("difficulty", 1))
	GameState.ever_spotted = bool(_snap.get("spotted", false))
	GameState.ever_chased = bool(_snap.get("chased", false))
	GameState.active_map_id = str(_snap.get("map", "old_manor"))
	GameState.active_mission_id = str(_snap.get("mission", ""))
	GameState.state = str(_snap.get("state", "playing"))
	LootStashScript.reset_for_test()


func _reset_run_loot() -> void:
	GameState.loot_value = 0
	GameState.loot_collected = 0
	GameState.loot_goal = 0
	GameState.loot_needed = 0
	GameState.carried_loot = []
	GameState.carried_tracking_active = false
	GameState.stashed_loot_value = 0
	GameState.last_payout = {}
	GameState.free_play = false
	GameState.difficulty = GameState.Difficulty.NOVICE
	GameState.ever_spotted = false
	GameState.ever_chased = false
	GameState.active_map_id = "guildhall"
	GameState.active_mission_id = "Mission.Guildhall.VaultHeist"
	GameState.loot_run_id = "suite89-run"


func _expect(problems: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		problems.append(msg)


func _read_json(res_or_path: String) -> Variant:
	if not FileAccess.file_exists(res_or_path):
		return null
	var f: FileAccess = FileAccess.open(res_or_path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## Private extracted/generated sources live at the repo root, not under res://.
func _repo_path(rel_path: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join(rel_path)


func _make_item(tier: String, value: int, quest: bool = false, name: String = "Suite Item") -> Node:
	var item: Node = LootItemScript.new() as Node
	item.set("loot_tier", tier)
	item.set("is_quest_item", quest)
	item.set("value", value)
	item.set("item_name", name)
	item.set("display_name", name)
	item.set("mesh_path", "")
	return item


# ------------------------------------------------------------- provenance ---
func _check_provenance(host: Node, problems: Array[String]) -> void:
	var settings: Dictionary = LootInventoryScript.settings()
	_expect(problems, not settings.is_empty(), "89.1 loot_settings.json unreadable")
	_expect(problems, LootInventoryScript.max_slots() == 12, "89.2 settings slots != 12")
	_expect(problems, LootInventoryScript.tier_slot_cost("minor") == 1, "89.3 minor slot cost != 1")
	_expect(problems, LootInventoryScript.tier_slot_cost("major") == 3, "89.4 major slot cost != 3")
	_expect(problems, LootInventoryScript.tier_slot_cost("quest") == 1, "89.5 quest slot cost != 1")
	_expect(problems, LootInventoryScript.capacity_enforced(), "89.6 cap not enforced")
	_expect(problems, is_equal_approx(LootInventoryScript.actor_linger_s(), 1.0), "89.7 linger != 1.0")
	_expect(problems, is_equal_approx(LootInventoryScript.kept_ratio("escape"), 1.0), "89.8 kept-on-escape != 1.0")
	_expect(problems, is_equal_approx(LootInventoryScript.kept_ratio("capture"), 0.0), "89.9 kept-on-capture != 0.0")
	_expect(problems, LootInventoryScript.refusal_text() == "INVENTORY FULL", "89.10 refusal text not authored")
	_expect(problems, LootInventoryScript.contract_reward("guildhall") == 1000, "89.11 guildhall reward != 1000")
	_expect(problems, LootInventoryScript.contract_reward("thieves_den") == 0, "89.12 hub reward != 0")

	# Generated loot actors: authored carry fields.
	var loot_actors: Variant = _read_json(LOOT_ACTORS_PATH)
	var faberge: Dictionary = {}
	var piety: Dictionary = {}
	if loot_actors is Dictionary:
		var actors: Variant = (loot_actors as Dictionary).get("actors", {})
		if actors is Dictionary:
			faberge = (actors as Dictionary).get("BP_LootActor_Major_FabergeEgg_C", {}) as Dictionary
		var quest_actors: Variant = (loot_actors as Dictionary).get("quest_actors", {})
		if quest_actors is Dictionary:
			piety = (quest_actors as Dictionary).get("BP_LootActor_Quest_Abbessford_Northgate_60_Piety_C", {}) as Dictionary
	_expect(problems, str(faberge.get("carry_mesh_res", "")) != "", "89.13 Faberge has no authored carry mesh")
	_expect(problems, not bool(faberge.get("is_large_carry", true)), "89.14 Faberge is_large_carry should be false")
	_expect(problems, bool(piety.get("is_large_carry", false)), "89.15 Piety is_large_carry should be true")
	_expect(problems, int(faberge.get("slot_size_override", 0)) == 1, "89.16 authored slot size != 1")

	var containers: Variant = _read_json(CONTAINERS_PATH)
	var stash_rec: Dictionary = {}
	if containers is Dictionary:
		var classes: Variant = (containers as Dictionary).get("classes", {})
		if classes is Dictionary:
			stash_rec = (classes as Dictionary).get("BP_LootStashInteractable_Secret_ThinWall_C", {}) as Dictionary
	_expect(problems, str(stash_rec.get("kind", "")) == "stash", "89.17 stash container kind != stash")
	_expect(problems, int(stash_rec.get("stash_uses", 0)) == 1, "89.18 stash uses != 1")

	# Live extraction provenance: skip loudly when the private tree is absent.
	if not FileAccess.file_exists(_repo_path(EX_PROJECT)):
		print("SKIP: 89 provenance (extracted/ absent; generated values asserted only)")
		return
	var player: Variant = _read_json(_repo_path(EX_PROJECT))
	var slots: int = -1
	if player is Array:
		for entry_v: Variant in (player as Array):
			if entry_v is Dictionary and str((entry_v as Dictionary).get("Type", "")) == "TATLootInventoryComponent":
				var props: Variant = (entry_v as Dictionary).get("Properties", {})
				if props is Dictionary:
					slots = int((props as Dictionary).get("InventorySlotMaxCapacity", -1))
	_expect(problems, slots == 12, "89.19 authored InventorySlotMaxCapacity != 12")
	var strings: Variant = _read_json(_repo_path(EX_STRINGS))
	var full_text: String = ""
	if strings is Array and not (strings as Array).is_empty():
		var table: Variant = ((strings as Array)[0] as Dictionary).get("StringTable", {})
		if table is Dictionary:
			var rows: Variant = (table as Dictionary).get("KeysToEntries", {})
			if rows is Dictionary:
				full_text = str((rows as Dictionary).get("ErrorInventoryFull", ""))
	_expect(problems, full_text == "INVENTORY FULL", "89.20 authored ErrorInventoryFull != INVENTORY FULL")
	var major: Variant = _read_json(_repo_path(EX_MAJOR))
	var row_value: int = -1
	if major is Array and not (major as Array).is_empty():
		var rows2: Variant = ((major as Array)[0] as Dictionary).get("Rows", {})
		if rows2 is Dictionary and (rows2 as Dictionary).has("FabergeEgg"):
			row_value = int(((rows2 as Dictionary)["FabergeEgg"] as Dictionary).get("Value", -1))
	_expect(problems, row_value == 1000, "89.21 authored FabergeEgg Value != 1000")
	var missions: Variant = _read_json(_repo_path(EX_MISSIONS))
	var reward: int = -1
	if missions is Dictionary:
		var mrows: Variant = (missions as Dictionary).get("rows", {})
		if mrows is Dictionary and (mrows as Dictionary).has("Mission.Guildhall.VaultHeist"):
			var rewards: Variant = ((mrows as Dictionary)["Mission.Guildhall.VaultHeist"] as Dictionary).get("Rewards", [])
			if rewards is Array:
				for r_v: Variant in (rewards as Array):
					if r_v is Dictionary and str((r_v as Dictionary).get("RewardType", {}).get("ObjectName", "")) == "Class'TATQuestRewardType_Money'":
						reward = int((r_v as Dictionary).get("Quantity", -1))
	_expect(problems, reward == 1000, "89.22 authored Guildhall money reward != 1000")
	print("PASS: 89 provenance (12 slots, major 3, INVENTORY FULL, £1,000, stash kind)")


# --------------------------------------------------------------- capacity ---
func _check_capacity(host: Node, problems: Array[String]) -> void:
	_reset_run_loot()
	var minor: Node = _make_item("minor", 45, false, "Purse")
	var first: Dictionary = LootInventoryScript.carry(minor, host)
	_expect(problems, bool(first.get("ok", false)), "89.23 first minor pickup refused")
	_expect(problems, GameState.carried_slots_used() == 1, "89.24 minor used != 1 slot")
	_expect(problems, GameState.loot_value == 45, "89.25 gross loot_value != 45")
	_expect(problems, GameState.carried_total_value() == 45, "89.26 carried value != 45")
	_expect(problems, LootInventoryScript.prompt_for(minor) == "[E] Steal Purse", "89.27 minor prompt != authored Steal")
	minor.free()

	# A major item costs 3 of the 12 slots.
	var major: Node = _make_item("major", 1000, false, "Jeweled Egg")
	var mres: Dictionary = LootInventoryScript.carry(major, host)
	_expect(problems, bool(mres.get("ok", false)), "89.28 major pickup refused")
	_expect(problems, GameState.carried_slots_used() == 4, "89.29 major used != 3 slots")
	major.free()

	# Fill to 12 and prove the authored refusal keeps the item in the world.
	while GameState.carried_slots_used() < 12:
		var filler: Node = _make_item("minor", 10, false, "Filler")
		LootInventoryScript.carry(filler, host)
		filler.free()
	_expect(problems, GameState.carried_slots_used() == 12, "89.30 fill did not reach 12 slots")
	var overflow: Node = LootItemScript.new() as Node
	overflow.set("loot_tier", "minor")
	overflow.set("is_quest_item", false)
	overflow.set("value", 45)
	overflow.set("item_name", "Overflow Purse")
	overflow.set("display_name", "Overflow Purse")
	overflow.set("mesh_path", "")
	host.add_child(overflow)
	var groups_before: bool = overflow.is_in_group("loot")
	overflow.call("interact", host)
	_expect(problems, not bool(overflow.get_meta("collected", false)), "89.31 over-cap item was collected")
	_expect(problems, overflow.is_in_group("loot") and groups_before, "89.32 over-cap item left the loot group")
	_expect(problems, LootInventoryScript.prompt_for(overflow) == "[E] INVENTORY FULL", "89.33 over-cap prompt not INVENTORY FULL")
	_expect(problems, LootInventoryScript.show_inventory_full(host) == "INVENTORY FULL", "89.34 refusal helper text wrong")
	_expect(problems, GameState.carried_slots_used() == 12, "89.35 refusal changed the slot count")
	overflow.queue_free()
	await host.get_tree().process_frame
	print("PASS: 89 carried capacity (12 slots, major 3, authored refusal)")


# ----------------------------------------------------------------- linger ---
func _check_linger(host: Node, problems: Array[String]) -> void:
	_reset_run_loot()
	var item: Node = LootItemScript.new() as Node
	item.set("loot_tier", "minor")
	item.set("is_quest_item", false)
	item.set("value", 100)
	item.set("item_name", "Silver Platter")
	item.set("display_name", "Silver Platter")
	item.set("mesh_path", "")
	host.add_child(item)
	await host.get_tree().process_frame
	item.call("interact", host)
	_expect(problems, bool(item.get_meta("collected", false)), "89.36 pickup did not mark collected")
	_expect(problems, is_instance_valid(item), "89.37 pickup freed in the same frame (no linger)")
	_expect(problems, not item.is_in_group("loot"), "89.38 lingering actor still in loot group")
	_expect(problems, not item.is_in_group("interactables"), "89.39 lingering actor still interactable")
	_expect(problems, is_equal_approx(float(item.get_meta("linger_s", 0.0)), 1.0), "89.40 linger beat != 1.0 s")
	var area := item as Area3D
	_expect(problems, area.monitoring == false and area.collision_layer == 0, "89.41 lingering actor still collides/monitors")
	await host.get_tree().create_timer(0.6).timeout
	_expect(problems, is_instance_valid(item), "89.42 actor freed before the 1 s beat")
	await host.get_tree().create_timer(0.6).timeout
	_expect(problems, not is_instance_valid(item), "89.43 actor survived past the 1 s beat")
	print("PASS: 89 actor linger (group/collision off at once, freed after 1.0 s)")


# ------------------------------------------------------------- quest items ---
func _check_quest_items(host: Node, problems: Array[String]) -> void:
	_reset_run_loot()
	var quest: Node = _make_item("quest", 1000, true, "Vistara Files")
	var qres: Dictionary = LootInventoryScript.carry(quest, host)
	_expect(problems, bool(qres.get("ok", false)), "89.44 quest pickup refused")
	_expect(problems, GameState.carried_slots_used() == 1, "89.45 quest used != 1 slot")
	_expect(problems, LootInventoryScript.prompt_for(quest) == "[E] Take Vistara Files", "89.46 quest prompt != Take")
	var deposit: Dictionary = LootStashScript.deposit_all(host, 1)
	_expect(problems, not bool(deposit.get("ok", false)), "89.47 quest-only stash deposit succeeded")
	_expect(problems, str(deposit.get("reason", "")) == "quest_only", "89.48 quest-only reason != quest_only")
	_expect(problems, GameState.carried_loot.size() == 1, "89.49 quest item was removed by the stash")
	_expect(problems, GameState.stashed_loot_value == 0, "89.50 quest item value was stashed")
	quest.free()
	print("PASS: 89 quest items (1 slot, Take prompt, never depositable)")


# ------------------------------------------------------------------ stash ---
func _check_stash(host: Node, problems: Array[String]) -> void:
	_reset_run_loot()
	var a: Node = _make_item("minor", 45, false, "Purse")
	var b: Node = _make_item("major", 405, false, "Chalice")
	var q: Node = _make_item("quest", 1000, true, "Vistara Files")
	LootInventoryScript.carry(a, host)
	LootInventoryScript.carry(b, host)
	LootInventoryScript.carry(q, host)
	a.free()
	b.free()
	q.free()
	_expect(problems, GameState.loot_value == 1450, "89.51 gross value != 1450 before stash")
	var spy_calls: Array = []
	LootStashScript.deposit_feedback = func(_h: Node, _p: Vector3, n: int) -> void:
		spy_calls.append(n)
	var first: Dictionary = LootStashScript.deposit_all(host, 1)
	_expect(problems, bool(first.get("ok", false)), "89.52 deposit failed")
	_expect(problems, int(first.get("deposited", 0)) == 2, "89.53 deposit did not take 2 non-quest items")
	_expect(problems, int(first.get("deposited_value", 0)) == 450, "89.54 deposited value != 450")
	_expect(problems, GameState.stashed_loot_value == 450, "89.55 stashed value != 450")
	_expect(problems, GameState.carried_loot.size() == 1 and bool(GameState.carried_loot[0].get("is_quest_item", false)), "89.56 stash removed the quest item")
	_expect(problems, GameState.loot_value == 1450, "89.57 stash subtracted from the monotonic loot_value")
	_expect(problems, int(first.get("uses_left", -1)) == 0, "89.58 one-use stash did not consume its use")
	_expect(problems, spy_calls.size() == 1, "89.59 SFX/VFX hook fired %d times (expected 1)" % spy_calls.size())
	var second: Dictionary = LootStashScript.deposit_all(host, 0)
	_expect(problems, not bool(second.get("ok", false)) and str(second.get("reason", "")) == "spent", "89.60 spent stash accepted a deposit")
	_expect(problems, LootStashScript.prompt_for(1, true) == "[F] Deposit All Loot", "89.61 deposit prompt not authored")
	_expect(problems, LootStashScript.prompt_for(1, false) == "[F] No Loot To Deposit", "89.62 empty prompt not authored")
	_expect(problems, LootStashScript.uses_remaining_text(1) == "1 Uses Remaining", "89.63 uses-remaining text not authored")
	print("PASS: 89 stash (one-use deposit-all, quest kept, monotonic value, hook once)")


# ----------------------------------------------------------------- payout ---
func _check_payout(problems: Array[String]) -> void:
	_reset_run_loot()
	var a: Node = _make_item("minor", 100, false, "Purse")
	var b: Node = _make_item("major", 900, false, "Faberge")
	LootInventoryScript.carry(a, null)
	LootInventoryScript.carry(b, null)
	a.free()
	b.free()
	GameState.stashed_loot_value = 250
	GameState.ever_spotted = false
	GameState.ever_chased = false
	var escape: Dictionary = LootInventoryScript.build_payout("escape", {"objectives_complete": true, "match_id": "suite89-escape"})
	_expect(problems, int(escape.get("original", 0)) == 1000, "89.64 Original != 1000")
	_expect(problems, int(escape.get("kept", 0)) == 1000, "89.65 Kept != 1000 on escape")
	_expect(problems, int(escape.get("stashed", 0)) == 250, "89.66 Stashed != 250")
	_expect(problems, int(escape.get("reward", 0)) == 1000, "89.67 reward != 1000 on complete escape")
	_expect(problems, int(escape.get("score", 0)) == 1250, "89.68 ghost score != 1250 (kept x 1.25)")
	_expect(problems, int(escape.get("money_taken", 0)) == 2500, "89.69 MoneyTaken != 2500")
	_expect(problems, is_equal_approx(float(escape.get("stealth_mult", 0.0)), 1.25), "89.70 stealth multiplier != 1.25")

	var capture: Dictionary = LootInventoryScript.build_payout("capture", {"objectives_complete": true, "match_id": "suite89-capture"})
	_expect(problems, int(capture.get("kept", -1)) == 0, "89.71 capture Kept != 0")
	_expect(problems, int(capture.get("score", -1)) == 0, "89.72 capture score != 0")
	_expect(problems, int(capture.get("money_taken", -1)) == 250, "89.73 capture MoneyTaken != stashed 250")
	_expect(problems, int(capture.get("reward", -1)) == 0, "89.74 capture paid a contract reward")

	# No difficulty multiplier is applied anywhere in the payout.
	var scores: Array[int] = []
	for diff: int in [GameState.Difficulty.NOVICE, GameState.Difficulty.THIEF, GameState.Difficulty.MASTER_THIEF]:
		GameState.difficulty = diff
		var p: Dictionary = LootInventoryScript.build_payout("escape", {"objectives_complete": true, "match_id": "diff"})
		scores.append(int(p.get("money_taken", 0)))
	_expect(problems, scores.size() == 3 and scores[0] == scores[1] and scores[1] == scores[2], "89.75 difficulty changed the payout")

	# Stealth behaviour stays explicit: spot but never chased = Shadow 1.10.
	GameState.ever_spotted = true
	GameState.ever_chased = false
	var shadow: Dictionary = LootInventoryScript.build_payout("escape", {"objectives_complete": false, "match_id": "shadow"})
	_expect(problems, int(shadow.get("score", 0)) == 1100 and int(shadow.get("reward", -1)) == 0, "89.76 shadow score/reward wrong")
	GameState.ever_chased = true
	var loud: Dictionary = LootInventoryScript.build_payout("escape", {"objectives_complete": false, "match_id": "loud"})
	_expect(problems, int(loud.get("score", 0)) == 1000, "89.77 loud score != kept face value")

	# Free play records the numbers but the reward is never paid.
	GameState.free_play = true
	GameState.ever_spotted = false
	GameState.ever_chased = false
	var free_p: Dictionary = LootInventoryScript.build_payout("escape", {"objectives_complete": true, "match_id": "free"})
	_expect(problems, bool(free_p.get("free_play", false)), "89.78 free-play payout not flagged")
	_expect(problems, int(free_p.get("reward", -1)) == 0, "89.79 free play paid a contract reward")
	_expect(problems, int(free_p.get("money_taken", 0)) == 1500, "89.80 free-play MoneyTaken != 1250 + 250 stashed")
	GameState.free_play = false

	# Legacy staged run: loot_value only, no carried tracking.
	GameState.carried_loot = []
	GameState.carried_tracking_active = false
	GameState.loot_value = 500
	GameState.stashed_loot_value = 0
	var legacy: Dictionary = LootInventoryScript.build_payout("escape", {"objectives_complete": false, "match_id": "legacy"})
	_expect(problems, int(legacy.get("kept", 0)) == 500 and int(legacy.get("money_taken", 0)) == 625, "89.81 legacy staged payout != 625")
	print("PASS: 89 payout (Original/Kept/Stashed/MoneyTaken, reward, binary keep, stealth, no difficulty)")
