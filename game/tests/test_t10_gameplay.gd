extends RefCounted
## Suite 91 (T10 remediation): objective markers, authored door/container
## locks, the container-class contract, large-carry movement penalties, the
## authored steal time, and the authored lockpick cancel distance.
##
## Headless, no map load. Every GameState field this suite touches is
## snapshotted and restored so later suites see the same run state.
##
## Red-proof coverage (each assertion fails on the pre-remediation tree):
##   91.1  the "objectives" group had no producer at all (C4-14)
##   91.2  the bag published no capacity signal and the refusal rode the clue
##         toast (C4-07)
##   91.3  doors/containers invented lock levels from spawn index + mesh-name
##         tokens (C4-04 / RE-K-07 / RE-K-17)
##   91.4  the 16 dropped authored container classes failed closed (RE-K-06)
##   91.5  a large-carry relic had no movement penalty (RE-K-04)
##   91.6  every pickup was instant (RE-K-05)
##   91.7  the authored 200 cm lockpick cancel had no reader (C4-06)

const LootItemScript := preload("res://src/interact/loot_item.gd")
const LootInventoryScript := preload("res://src/interact/loot_inventory.gd")
const LockableDoorScript := preload("res://src/interact/lockable_door.gd")
const SwingingDoorScript := preload("res://src/interact/swinging_door.gd")
const LootContainerScript := preload("res://src/interact/loot_container.gd")
const MissionScript := preload("res://src/missions/mission_controller.gd")
const ThiefScript := preload("res://src/player/thief_character.gd")

const GH_LEVELS := [
	"res://data/generated/levels/Guildhall/Guildhall_Loot.tatlevel.json",
	"res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
]

var _snap: Dictionary = {}


func run(host: Node) -> Array[String]:
	var problems: Array[String] = []
	_snapshot()
	await _check_objective_group(host, problems)
	await _check_capacity_contract(host, problems)
	await _check_authored_locks(host, problems)
	await _check_container_classes(host, problems)
	await _check_large_carry(host, problems)
	_check_steal_time(problems)
	await _check_cancel_distance(host, problems)
	_restore()
	return problems


# ---------------------------------------------------------------- snapshot ---
func _snapshot() -> void:
	_snap = {
		"loot_value": GameState.loot_value,
		"loot_collected": GameState.loot_collected,
		"loot_goal": GameState.loot_goal,
		"carried": GameState.carried_loot.duplicate(true),
		"tracking": GameState.carried_tracking_active,
		"stashed": GameState.stashed_loot_value,
		"run_id": GameState.loot_run_id,
		"last_payout": GameState.last_payout.duplicate(true),
		"free_play": GameState.free_play,
		"difficulty": GameState.difficulty,
		"map": GameState.active_map_id,
		"mission": GameState.active_mission_id,
		"state": GameState.state,
		"phase": GameState.phase,
		"markers": GameState.escape_markers.duplicate(true),
	}


func _restore() -> void:
	GameState.loot_value = int(_snap.get("loot_value", 0))
	GameState.loot_collected = int(_snap.get("loot_collected", 0))
	GameState.loot_goal = int(_snap.get("loot_goal", 0))
	GameState.carried_loot = _snap.get("carried", []) as Array[Dictionary]
	GameState.carried_tracking_active = bool(_snap.get("tracking", false))
	GameState.stashed_loot_value = int(_snap.get("stashed", 0))
	GameState.loot_run_id = str(_snap.get("run_id", ""))
	GameState.last_payout = _snap.get("last_payout", {}) as Dictionary
	GameState.free_play = bool(_snap.get("free_play", false))
	GameState.difficulty = int(_snap.get("difficulty", 1))
	GameState.active_map_id = str(_snap.get("map", "old_manor"))
	GameState.active_mission_id = str(_snap.get("mission", ""))
	GameState.state = str(_snap.get("state", "playing"))
	GameState.phase = str(_snap.get("phase", "main"))
	GameState.escape_markers = _snap.get("markers", []) as Array[Dictionary]


func _reset_run_loot() -> void:
	GameState.loot_value = 0
	GameState.loot_collected = 0
	GameState.loot_goal = 0
	GameState.carried_loot = []
	GameState.carried_tracking_active = false
	GameState.stashed_loot_value = 0
	GameState.last_payout = {}
	GameState.free_play = false
	GameState.difficulty = GameState.Difficulty.NOVICE
	GameState.active_map_id = "guildhall"
	GameState.active_mission_id = "Mission.Guildhall.VaultHeist"
	GameState.state = "playing"
	GameState.phase = "main"


func _expect(problems: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		problems.append(msg)


## Dynamic static-call helper: keeps this suite parseable on the pre-fix tree so
## the red proof reports per-assertion failures instead of a parse error.
func _static(script: GDScript, method: String, args: Array = []) -> Variant:
	var obj: Variant = script
	return obj.callv(method, args)


func _make_item(item_name: String, tier: String, quest: bool = false) -> Node:
	var item: Node = LootItemScript.new() as Node
	item.set("loot_tier", tier)
	item.set("is_quest_item", quest)
	item.set("value", 225)
	item.set("item_name", item_name)
	item.set("display_name", item_name)
	item.set("mesh_path", "")
	return item


# ------------------------------------------------- 91.1 objective markers ---
## C4-14: the compass and TAB map read `get_nodes_in_group("objectives")` and
## nothing produced it, so no contract objective had a marker. A contract quest
## item must be the marker, and it must leave the group when it is taken.
func _check_objective_group(host: Node, problems: Array[String]) -> void:
	_reset_run_loot()
	var quest: Node = _make_item("Vistara Files", "quest", true)
	host.add_child(quest)
	var after_add: Array[Node] = host.get_tree().get_nodes_in_group("objectives")
	_expect(problems, after_add.has(quest), "91.1a a contract quest item does not join the objectives group")
	_expect(problems, quest.is_in_group("interactables") and quest.is_in_group("loot"),
		"91.1b the quest item kept its interactable/loot groups")
	var plain: Node = _make_item("Cat Statue", "major", false)
	host.add_child(plain)
	_expect(problems, not plain.is_in_group("objectives"),
		"91.1c ordinary loot joined the objectives group (only contract objectives may)")
	quest.call("interact", host)
	_expect(problems, not quest.is_in_group("objectives"),
		"91.1d the taken quest item stayed in the objectives group (stale map marker)")
	_expect(problems, not quest.is_in_group("loot"),
		"91.1e the lingering pickup stayed in the loot group")
	plain.queue_free()
	await host.get_tree().process_frame
	# GameState must not be polluted by the pickup.
	GameState.carried_loot = []


# --------------------------------------- 91.2 capacity signal contract ------
## C4-07: 12 slots / 1-3-1 were enforced but invisible; `carried_loot_changed`
## had no subscriber and the refusal rode the CLUE — NOTICE toast. The
## inventory now publishes used/max and a dedicated refusal channel (T05 owns
## the widget; this asserts the producer contract).
class MockHud extends Node:
	var capacity_calls: Array = []
	var full_toasts: Array = []
	var clue_toasts: Array = []
	func show_loot_capacity(used: int, slots: int, full: bool) -> void:
		capacity_calls.append([used, slots, full])
	func show_inventory_full_toast(text: String) -> void:
		full_toasts.append(text)
	func show_toast(text: String) -> void:
		clue_toasts.append(text)
	func is_lockpicking() -> bool:
		return false


func _check_capacity_contract(host: Node, problems: Array[String]) -> void:
	_reset_run_loot()
	var hud: MockHud = MockHud.new()
	hud.name = "T10MockHud"
	host.add_child(hud)
	hud.add_to_group("hud")
	var minor: Node = _make_item("Purse", "minor", false)
	host.add_child(minor)
	var carried: Dictionary = LootInventoryScript.carry(minor, hud)
	_expect(problems, bool(carried.get("ok", false)), "91.2a minor pickup refused on an empty bag")
	_expect(problems, hud.capacity_calls.size() == 1
		and (hud.capacity_calls[0] as Array)[0] == 1 and (hud.capacity_calls[0] as Array)[1] == 12,
		"91.2b the accepted pickup published no used/max capacity state (%s)" % str(hud.capacity_calls))
	# Fill to the cap, then refuse one more: the refusal must use the dedicated
	# capacity channel and still publish the full state.
	var guard: int = 0
	while GameState.carried_slots_used() < LootInventoryScript.max_slots() and guard < 32:
		var filler: Node = _make_item("Filler", "minor", false)
		LootInventoryScript.carry(filler, hud)
		filler.free()
		guard += 1
	var over: Node = _make_item("Overflow Purse", "minor", false)
	host.add_child(over)
	var refused: Dictionary = LootInventoryScript.carry(over, hud)
	_expect(problems, not bool(refused.get("ok", true)) and str(refused.get("reason", "")) == "inventory_full",
		"91.2c a full bag accepted a 13th slot-cost")
	_expect(problems, hud.full_toasts.size() == 1 and str(hud.full_toasts[0]) == LootInventoryScript.refusal_text(),
		"91.2d the refusal did not use the dedicated capacity channel (clue toasts=%s)" % str(hud.clue_toasts))
	_expect(problems, hud.clue_toasts.is_empty(),
		"91.2e the capacity refusal still rode the CLUE toast")
	_expect(problems, bool((hud.capacity_calls[hud.capacity_calls.size() - 1] as Array)[2]) == true,
		"91.2f the full state was never published")
	var snap: Dictionary = _static(LootInventoryScript, "capacity_snapshot") as Dictionary
	_expect(problems, int(snap.get("used", -1)) == 12 and int(snap.get("slots", -1)) == 12 and bool(snap.get("full", false)),
		"91.2g capacity_snapshot disagrees with the enforced state (%s)" % str(snap))
	over.queue_free()
	minor.queue_free()
	hud.remove_from_group("hud")
	hud.queue_free()
	await host.get_tree().process_frame
	GameState.carried_loot = []


# ------------------------------------------------ 91.3 authored lock data ---
## C4-04 / RE-K-07 / RE-K-17: no door or container record authors a lock, and
## the port invented levels from `count % 12`, leaf-mesh filename tokens and
## the container spawn index. Only authored records may lock, at their level.
func _check_authored_locks(host: Node, problems: Array[String]) -> void:
	_reset_run_loot()
	# Data proof: the loaded Guildhall door records author no lock at all.
	var door_records: int = 0
	var authored_locked: int = 0
	for path: String in GH_LEVELS:
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (data is Dictionary):
			continue
		for dv: Variant in ((data as Dictionary).get("swinging_doors", []) as Array):
			if not (dv is Dictionary):
				continue
			door_records += 1
			if (dv as Dictionary).get("locked") == true or int((dv as Dictionary).get("lock_level", 0)) > 0:
				authored_locked += 1
	_expect(problems, authored_locked == 0,
		"91.3a %d/%d authored Guildhall door records carry a lock the spawner ignored" % [authored_locked, door_records])
	# Spawner proof: a synthetic record with a "vault" leaf mesh at count 5 and
	# no authored lock must stay unlocked (the old heuristic locked both).
	var mc: Node = MissionScript.new() as Node
	host.add_child(mc)
	var doors: Array = []
	for i: int in range(6):
		doors.append({
			"pos": [100.0 + float(i) * 3.0, 0.0, 100.0],
			"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
			"leaves": [{"mesh": "/Game/Art/Environment/Props/Doors/SM_VaultDoorA"}],
			"actor": "BP_SwingingDoor_%d" % i,
			"class": "BP_SwingingDoor_C",
			"name": "Door_%d" % i,
			"source": "suite91",
		})
	mc.call("_spawn_swinging_doors", {"swinging_doors": doors})
	var spawned: int = 0
	var locked: int = 0
	for node: Node in host.get_tree().get_nodes_in_group("swinging_doors"):
		if node.get_parent() != mc:
			continue
		spawned += 1
		if bool(node.get("locked")):
			locked += 1
	_expect(problems, spawned == 6 and locked == 0,
		"91.3b the invented lock heuristics still fire (spawned=%d locked=%d, want 6/0)" % [spawned, locked])
	# Authored record still locks, at its authored level.
	var locked_door: Node = SwingingDoorScript.new() as Node
	locked_door.call("configure", {
		"pos": [200.0, 0.0, 200.0],
		"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
		"leaves": [],
		"locked": true,
		"lock_level": 2,
	}, null)
	host.add_child(locked_door)
	_expect(problems, bool(locked_door.get("locked")) and int(locked_door.get("lock_level")) == 2,
		"91.3c an authored locked/lock_level record was not honoured (locked=%s level=%s)" % [str(locked_door.get("locked")), str(locked_door.get("lock_level"))])
	# Lockpick panel title carries the level exactly once (hud appends it).
	var cont: Node = LootContainerScript.new() as Node
	cont.call("configure", "BP_DisplayCaseA_MajorLoot_C", {
		"pos": Vector3(300.0, 0.0, 300.0),
		"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
	}, 0)
	host.add_child(cont)
	var label: String = str(cont.call("_container_label"))
	_expect(problems, label.find("(Lv") < 0 and label.find("LV") < 0,
		"91.3d the container lockpick title still embeds its own level ('%s')" % label)
	_expect(problems, not bool(cont.get("locked")),
		"91.3e a major container was locked without an authored lock")
	locked_door.queue_free()
	cont.queue_free()
	mc.queue_free()
	await host.get_tree().process_frame


# ------------------------------------- 91.4 container class coverage -------
## RE-K-06: 16 authored Guildhall markers (8 BP_SmallSafe_MajorLoot_C + 8
## BP_Manor_Bookcase_Cabinet_MinorLoot_C) were dropped by a 5-class allowlist.
## The consumer half (this suite) must resolve the authored class instead of
## failing closed the moment a producer/loader lane emits it.
func _check_container_classes(host: Node, problems: Array[String]) -> void:
	_reset_run_loot()
	var cases: Array = [
		["BP_SmallSafe_MajorLoot_C", "major", false],
		["BP_Manor_Bookcase_Cabinet_MinorLoot_C", "minor", false],
		["BP_Manor_Bookcase_Cabinet_MajorLoot_C", "major", false],
		["BP_UtilityBoxA_MinorLoot_C", "minor", false],
		["BP_LootStashInteractable_Secret_ThinWall_C", "", true],
	]
	for case_v: Variant in cases:
		var c: Array = case_v as Array
		var cls: String = str(c[0])
		var want_tier: String = str(c[1])
		var want_stash: bool = bool(c[2])
		var node: Node = LootContainerScript.new() as Node
		node.call("configure", cls, {
			"pos": Vector3(10.0, 0.0, 10.0),
			"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
		}, 0)
		host.add_child(node)
		_expect(problems, str(node.get("loot_tier")) == want_tier,
			"91.4a %s resolved tier '%s' (want '%s')" % [cls, str(node.get("loot_tier")), want_tier])
		_expect(problems, bool(node.get("is_stash")) == want_stash,
			"91.4b %s stash=%s (want %s)" % [cls, str(node.get("is_stash")), str(want_stash)])
		_expect(problems, not bool(node.get("locked")),
			"91.4c %s was locked without authored data" % cls)
		node.queue_free()
	await host.get_tree().process_frame
	# The produced table still carries the 5 shipped classes (no consumer drift).
	var containers: Dictionary = LootContainerScript.containers()
	_expect(problems, containers.has("BP_ChestTrunk_MajorLoot_C") and containers.has("BP_DisplayCaseA_MajorLoot_C"),
		"91.4d containers.json classes unreadable (%d)" % containers.size())


# ---------------------------------------------------- 91.5 large carry -----
## RE-K-04: the 8 IsLargeCarry relics authored ×0.6 walk / ×0.3 climb and
## nothing read the flag. The inventory exposes the multiplier and the player
## controller applies it to the authoritative speed.
func _check_large_carry(host: Node, problems: Array[String]) -> void:
	_reset_run_loot()
	_expect(problems, is_equal_approx(float(_static(LootInventoryScript, "carry_speed_multiplier")), 1.0),
		"91.5a an empty bag already carries a movement penalty")
	GameState.carried_loot.append({"name": "Golden Throne", "tier": "major", "slot_cost": 3, "is_large_carry": true})
	_expect(problems, is_equal_approx(float(_static(LootInventoryScript, "carry_speed_multiplier")), 0.6),
		"91.5b a large-carry relic did not apply the authored 0.6 walk multiplier (%s)" % str(float(_static(LootInventoryScript, "carry_speed_multiplier"))))
	_expect(problems, is_equal_approx(float(_static(LootInventoryScript, "carry_climb_multiplier")), 0.3),
		"91.5c a large-carry relic did not apply the authored 0.3 climb multiplier (%s)" % str(float(_static(LootInventoryScript, "carry_climb_multiplier"))))
	var thief: Node = ThiefScript.new() as Node
	var slow: float = float(thief.call("effective_speed", 100.0))
	thief.free()
	_expect(problems, is_equal_approx(slow, 60.0),
		"91.5d the player controller ignored the carry penalty (effective_speed=%.2f, want 60.0)" % slow)
	GameState.carried_loot = [{"name": "Cat Statue", "tier": "major", "slot_cost": 3, "is_large_carry": false}]
	_expect(problems, is_equal_approx(float(_static(LootInventoryScript, "carry_speed_multiplier")), 1.0),
		"91.5f a non-large major item applied the carry penalty")
	GameState.carried_loot = []
	await host.get_tree().process_frame


# --------------------------------------------------- 91.6 steal time ------
## RE-K-05: DT_LootInfo TimeTakenToSteal (0.01-4 s) was parsed and never read,
## so a vault emptied instantly at a full sprint.
func _check_steal_time(problems: Array[String]) -> void:
	var throne_s: float = float(_static(LootItemScript, "authored_steal_time_s", ["major", "", "Golden Throne"]))
	var statue_s: float = float(_static(LootItemScript, "authored_steal_time_s", ["major", "", "Cat Statue"]))
	_expect(problems, is_equal_approx(throne_s, 4.0),
		"91.6a Golden Throne steal time is not the authored 4.0 s (%s)" % str(throne_s))
	_expect(problems, is_equal_approx(statue_s, 1.0),
		"91.6b Cat Statue steal time is not the authored 1.0 s (%s)" % str(statue_s))
	var quest_s: float = float(_static(LootItemScript, "authored_steal_time_s", ["quest", "Loot.Quest.VistaraFiles", ""]))
	_expect(problems, quest_s > 0.0,
		"91.6c the Vistara Files quest row has no resolved steal time (%s)" % str(quest_s))
	var item: Node = LootItemScript.new() as Node
	item.set("loot_tier", "major")
	item.set("item_name", "Golden Throne")
	item.set("display_name", "Golden Throne")
	item.set("mesh_path", "")
	_expect(problems, is_equal_approx(float(item.call("get_interact_hold_seconds")), 4.0),
		"91.6d the loot actor exposes no hold-to-steal beat (%s)" % str(item.call("get_interact_hold_seconds")))
	item.set("display_name", "Suite Item")
	item.set("item_name", "Suite Item")
	_expect(problems, is_equal_approx(float(item.call("get_interact_hold_seconds")), 0.0),
		"91.6e a synthetic item without an authored row invented a steal time")
	item.free()


# ------------------------------------------------ 91.7 cancel distance -----
## C4-06: GA_Lockpick distance_before_cancel = 200 cm had no reader (the old
## E2E "proof" grepped hud.gd for the string "2.0").
func _check_cancel_distance(host: Node, problems: Array[String]) -> void:
	_reset_run_loot()
	_expect(problems, is_equal_approx(float(_static(LockableDoorScript, "lockpick_cancel_distance_m")), 2.0),
		"91.7a the authored 200 cm cancel distance did not resolve to 2.0 m (%s)" % str(float(_static(LockableDoorScript, "lockpick_cancel_distance_m"))))
	for script: GDScript in [SwingingDoorScript, LootContainerScript]:
		var node: Node = script.new() as Node
		if node is Node3D:
			(node as Node3D).position = Vector3(500.0, 0.0, 500.0)
		host.add_child(node)
		var actor: MockActor = MockActor.new()
		actor.name = "T10CancelActor"
		var base: Vector3 = (node as Node3D).global_position
		actor.position = base + Vector3(0.5, 0.0, 0.0)
		host.add_child(actor)
		node.set("is_lockpicking", true)
		node.set("_lockpick_actor", actor)
		var near_cancel: bool = bool(node.call("check_lockpick_distance"))
		_expect(problems, not near_cancel and bool(node.get("is_lockpicking")),
			"91.7b %s cancelled a lockpick at 0.5 m (authored radius 2.0 m)" % str(script.resource_path))
		actor.position = base + Vector3(3.0, 0.0, 0.0)
		var far_cancel: bool = bool(node.call("check_lockpick_distance"))
		_expect(problems, far_cancel and not bool(node.get("is_lockpicking")),
			"91.7c %s did not cancel a lockpick past 2.0 m (cancelled=%s lockpicking=%s)" % [str(script.resource_path), str(far_cancel), str(node.get("is_lockpicking"))])
		_expect(problems, not actor.lockpicking_active,
			"91.7d %s left the player's lockpicking flag set after the cancel" % str(script.resource_path))
		actor.queue_free()
		node.queue_free()
		await host.get_tree().process_frame


class MockActor extends Node3D:
	var lockpicking_active: bool = false
	func set_lockpicking_active(value: bool) -> void:
		lockpicking_active = value
