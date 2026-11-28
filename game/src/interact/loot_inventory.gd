extends RefCounted
## Carried loot inventory, payout model and picked-up-actor linger (W7S-S2).
##
## The authored inventory component is TATLootInventoryComponent on
## BP_TATPlayerState: InventorySlotMaxCapacity = 12. The carried list is run
## state (GameState.carried_loot); LootInventory owns the rules, the save file
## only ever sees the payout summary (SaveSystem v8).
##
## Port decisions (no authored value exists for these):
##   * a major item occupies 3 of the 12 slots, minor/quest 1 each. The authored
##     row cost is 1/1/1 (`DT_LootInfo_*.SlotSizeOverride` = 1 with
##     `UseSlotSizeOverride=false` everywhere), so `major = 3` is an explicit
##     port capacity decision (recorded in loot_settings.json
##     "port_decisions.major_slot_cost") and `minor`/`quest` follow the authored
##     row. `DefaultGame.ini DefaultLootSlotSize = 1/1/3` exists but no producer
##     reads it and no shipped call site is proven (RE-K-02); it is not the
##     provenance of the 3. Capacity refusals are therefore a port-tuned
##     timing, not authored.
##   * the cap (12, BP_TATPlayerState.InventorySlotMaxCapacity) IS authored.
##   * a picked-up actor stays visible for the authored 1.0 s loot-bag pickup
##     beat (BP_LootBagActor._minInteractDuration) instead of vanishing in the
##     same frame;
##   * binary keep: a getaway keeps the carried haul (1.0), a capture keeps
##     only stashed value (0.0); stashed value is always kept.
##
## Every number has a hard-coded fallback equal to the parsed settings, so a
## tree without the generated file still plays; the provenance test asserts the
## generated values match these constants.

const SLOTS := 12
const SLOT_COST: Dictionary = {"minor": 1, "major": 3, "quest": 1}
const CAP_ENFORCED := true
const ACTOR_LINGER_S := 1.0
const KEPT_ON_ESCAPE := 1.0
const KEPT_ON_CAPTURE := 0.0
const CONTRACT_REWARD_FALLBACK := 1000
const INVENTORY_FULL_FALLBACK := "INVENTORY FULL"

const SETTINGS_PATH := "res://data/generated/gameplay/loot_settings.json"

## Groups a picked-up loot actor leaves immediately (economy audits, tactical
## map, thief vision and the interaction targeter must not see it again). A
## contract quest item also leaves the compass/TAB-map "objectives" group, so
## the marker disappears the moment the objective is taken.
const PICKUP_GROUPS: Array[String] = [
	"loot", "interactables", "xray_target", "thief_vision_highlight", "objectives",
]

## Authored large-carry movement penalties. `GE_CarryingLargeCarryLoot` sets
## MovementMaxSpeedMultiplier 0.6 (walk) and `GE_CarryingLargeCarryLoot_Climbing`
## 0.3 (wall climb) on the 8 DT_LootInfo rows with `IsLargeCarry`. They are not
## in loot_settings.json yet (the GE assets are not parsed); these constants are
## the authored values and the settings keys override them when a producer lands
## them. Carrying ANY large-carry entry applies the single authored multiplier.
const LARGE_CARRY_WALK_MULTIPLIER := 0.6
const LARGE_CARRY_CLIMB_MULTIPLIER := 0.3

static var _settings: Dictionary = {}
static var _settings_loaded: bool = false


## Generated loot_settings.json ({} when unreadable/absent).
static func settings() -> Dictionary:
	if _settings_loaded:
		return _settings
	_settings_loaded = true
	if not FileAccess.file_exists(SETTINGS_PATH):
		return _settings
	var f: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return _settings
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_settings = parsed as Dictionary
	return _settings


static func reset_settings_cache() -> void:
	_settings = {}
	_settings_loaded = false


static func max_slots() -> int:
	var v: Variant = settings().get("slots", SLOTS)
	var n: int = int(v) if v is int or v is float else SLOTS
	return maxi(n, 1)


static func capacity_enforced() -> bool:
	var v: Variant = settings().get("cap_enforced", CAP_ENFORCED)
	return bool(v) if v is bool else CAP_ENFORCED


static func tier_slot_cost(tier: String) -> int:
	var costs: Variant = settings().get("slot_cost_port", {})
	if costs is Dictionary and (costs as Dictionary).has(tier):
		var n: int = int((costs as Dictionary)[tier])
		return maxi(n, 0)
	return maxi(int(SLOT_COST.get(tier, 1)), 0)


static func actor_linger_s() -> float:
	var v: Variant = settings().get("actor_linger_s", ACTOR_LINGER_S)
	var s: float = float(v) if v is int or v is float else ACTOR_LINGER_S
	return maxf(s, 0.0)


static func kept_ratio(outcome: String) -> float:
	if outcome == "escape":
		var v: Variant = settings().get("kept_on_escape", KEPT_ON_ESCAPE)
		return float(v) if v is int or v is float else KEPT_ON_ESCAPE
	var c: Variant = settings().get("kept_on_capture", KEPT_ON_CAPTURE)
	return float(c) if c is int or c is float else KEPT_ON_CAPTURE


static func refusal_text() -> String:
	var prompts: Variant = settings().get("prompts", {})
	if prompts is Dictionary:
		var text: String = str((prompts as Dictionary).get("ErrorInventoryFull", ""))
		if text != "":
			return text
	return INVENTORY_FULL_FALLBACK


static func contract_reward(map_id: String) -> int:
	var rewards: Variant = settings().get("contract_rewards", {})
	if rewards is Dictionary and (rewards as Dictionary).has(map_id):
		return maxi(int((rewards as Dictionary)[map_id]), 0)
	if map_id == "thieves_den":
		return 0
	var fb: Variant = settings().get("contract_reward_fallback", CONTRACT_REWARD_FALLBACK)
	return maxi(int(fb) if fb is int or fb is float else CONTRACT_REWARD_FALLBACK, 0)


## Slot cost of one carried entry (falls back to its tier cost).
static func entry_slot_cost(entry: Dictionary) -> int:
	if entry.has("slot_cost"):
		return maxi(int(entry.get("slot_cost", 1)), 0)
	return tier_slot_cost(str(entry.get("tier", "minor")))


static func used_slots(items: Array = []) -> int:
	var source: Array = items
	if source.is_empty() and GameState != null:
		source = GameState.carried_loot
	var used: int = 0
	for entry_v: Variant in source:
		if entry_v is Dictionary:
			used += entry_slot_cost(entry_v as Dictionary)
	return used


static func carried_value(items: Array = []) -> int:
	var source: Array = items
	if source.is_empty() and GameState != null:
		source = GameState.carried_loot
	var total: int = 0
	for entry_v: Variant in source:
		if entry_v is Dictionary:
			total += maxi(int((entry_v as Dictionary).get("value", 0)), 0)
	return total


static func has_depositable(items: Array = []) -> bool:
	var source: Array = items
	if source.is_empty() and GameState != null:
		source = GameState.carried_loot
	for entry_v: Variant in source:
		if entry_v is Dictionary and not bool((entry_v as Dictionary).get("is_quest_item", false)):
			return true
	return false


## True when any carried entry is an authored large carry (IsLargeCarry).
static func carries_large_carry(items: Array = []) -> bool:
	var source: Array = items
	if source.is_empty() and GameState != null:
		source = GameState.carried_loot
	for entry_v: Variant in source:
		if entry_v is Dictionary and bool((entry_v as Dictionary).get("is_large_carry", false)):
			return true
	return false


## Authored walk-speed multiplier while carrying a large relic
## (GE_CarryingLargeCarryLoot.MovementMaxSpeedMultiplier 0.6, Multiplicitive).
static func large_carry_walk_multiplier() -> float:
	var v: Variant = settings().get("large_carry_walk_multiplier", LARGE_CARRY_WALK_MULTIPLIER)
	var m: float = float(v) if v is int or v is float else LARGE_CARRY_WALK_MULTIPLIER
	return clampf(m, 0.05, 1.0)


## Authored wall-climb multiplier while carrying a large relic
## (GE_CarryingLargeCarryLoot_Climbing 0.3).
static func large_carry_climb_multiplier() -> float:
	var v: Variant = settings().get("large_carry_climb_multiplier", LARGE_CARRY_CLIMB_MULTIPLIER)
	var m: float = float(v) if v is int or v is float else LARGE_CARRY_CLIMB_MULTIPLIER
	return clampf(m, 0.05, 1.0)


## Combined locomotion multiplier from the carried haul (1.0 when the bag holds
## no large carry). The player controller multiplies its authoritative
## ward/difficulty speed by this.
static func carry_speed_multiplier(items: Array = []) -> float:
	return large_carry_walk_multiplier() if carries_large_carry(items) else 1.0


## Combined wall-climb multiplier from the carried haul.
static func carry_climb_multiplier(items: Array = []) -> float:
	return large_carry_climb_multiplier() if carries_large_carry(items) else 1.0


## HUD capacity contract (T05 owns the widget). Returns the numbers a capacity
## readout needs; the HUD draws `used/max` plus the full-state cue.
static func capacity_snapshot() -> Dictionary:
	var used: int = used_slots()
	var slots: int = max_slots()
	return {
		"used": used,
		"slots": slots,
		"free": maxi(slots - used, 0),
		"full": used >= slots,
	}


## Publish the capacity state to the HUD. The HUD owns the widget; this is the
## only producer of the numbers, so a pickup, a refusal and a payout all agree.
## `hud.show_loot_capacity(used_slots, max_slots, full)` is the contract T05
## implements; a HUD without it is a no-op (never a crash, never a clue toast).
static func broadcast_capacity(actor: Node = null) -> Dictionary:
	var snap: Dictionary = capacity_snapshot()
	var hud: Node = _find_hud(actor)
	if hud != null and hud.has_method("show_loot_capacity"):
		hud.call("show_loot_capacity", int(snap["used"]), int(snap["slots"]), bool(snap["full"]))
	return snap


## Capacity check for one pickup. Returns
## {ok, reason, used, cost, slots, prompt} — never mutates state.
static func can_carry(tier: String, is_quest_item: bool = false) -> Dictionary:
	var cost: int = tier_slot_cost(tier)
	var used: int = used_slots()
	var slots: int = max_slots()
	var out: Dictionary = {
		"ok": true,
		"reason": "",
		"used": used,
		"cost": cost,
		"slots": slots,
		"is_quest_item": is_quest_item,
	}
	if not capacity_enforced():
		return out
	if used + cost > slots:
		out["ok"] = false
		out["reason"] = "inventory_full"
		out["prompt"] = refusal_text()
	return out


## Capacity check for a real loot item node.
static func can_carry_item(item: Node) -> Dictionary:
	return can_carry(str(item.get("loot_tier")), bool(item.get("is_quest_item")))


## Authored refusal text shown when a pickup does not fit. The HUD owns the
## channel: `hud.show_inventory_full_toast(text)` when it exists (a dedicated
## capacity cue, T05), else the legacy toast. The capacity broadcast runs either
## way so the bag readout shows WHY the pickup failed.
static func show_inventory_full(actor: Node = null) -> String:
	var text: String = refusal_text()
	var hud: Node = _find_hud(actor)
	if hud != null:
		if hud.has_method("show_inventory_full_toast"):
			hud.call("show_inventory_full_toast", text)
		elif hud.has_method("show_toast"):
			hud.call("show_toast", text)
	broadcast_capacity(actor)
	return text


## Carry one loot item node into GameState. Returns
## {ok, reason, entry, used, slots, prompt}. The caller owns the objective/fact
## side effects and the world-actor linger; the gross loot_value counter and
## the carried entry are written here so both can never drift.
static func carry(item: Node, actor: Node = null) -> Dictionary:
	var tier: String = str(item.get("loot_tier"))
	var is_quest_item: bool = bool(item.get("is_quest_item"))
	var check: Dictionary = can_carry(tier, is_quest_item)
	if not bool(check.get("ok", false)):
		check["text"] = show_inventory_full(actor)
		check["entry"] = {}
		return check
	var value: int = maxi(int(item.get("value")), 0)
	var entry: Dictionary = {
		"name": str(item.get("item_name")),
		"display_name": str(item.get("display_name")),
		"value": value,
		"tier": tier,
		"slot_cost": int(check.get("cost", tier_slot_cost(tier))),
		"is_quest_item": is_quest_item,
		"is_large_carry": bool(item.get("is_large_carry")),
		"loot_tag": str(item.get("loot_tag")),
		"mesh_path": str(item.get("mesh_path")),
		"carry_mesh_path": str(item.get("carry_mesh_path")),
		"objective_id": str(item.get("objective_id")),
	}
	GameState.carried_tracking_active = true
	GameState.carried_loot.append(entry)
	GameState.add_loot(1, value, is_quest_item, str(item.get("objective_id")))
	GameState.notify_carried_loot_changed()
	# T05 capacity widget contract: every accepted pickup publishes used/max so
	# the bag gauge and the refusal share one source of truth.
	broadcast_capacity(actor)
	# W11-A: authored pickup VO. Major tier -> Player/PickupLoot/Major; a quest
	# relic -> the talking bag's MatchLootIsPickedUp; the first carried entry of
	# a run -> PlayerIsCarryingLoot. The director owns cooldowns and refuses an
	# authored triple the speaker never recorded.
	_vo_for_pickup(tier, is_quest_item, actor)
	check["entry"] = entry
	check["used"] = used_slots()
	return check


## W11-A pickup cues. Static-friendly: resolves the AudioManager autoload from
## the main loop like smoke_projectile does, and tolerates its absence (tests
## that call carry() without a tree keep working).
static func _vo_for_pickup(tier: String, is_quest_item: bool, actor: Node) -> void:
	var am: Node = _audio_manager()
	if am == null or not am.has_method("play_vo_cue"):
		return
	var pos: Variant = null
	if actor is Node3D and (actor as Node3D).is_inside_tree():
		pos = (actor as Node3D).global_position
	if is_quest_item:
		am.call("play_vo_cue", "match_loot_picked", pos)
		return
	if tier == "major":
		am.call("play_vo_cue", "loot_pickup_major", pos)
	if GameState.carried_loot.size() == 1:
		am.call("play_vo_cue", "carrying_loot", pos)


static func _audio_manager() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("AudioManager")


## Authored pickup prompt for a loot item. A full inventory reads the authored
## error line instead of an action the player cannot complete.
static func prompt_for(item: Node) -> String:
	var label: String = str(item.get("display_name"))
	if label == "":
		label = str(item.get("item_name"))
	var is_quest_item: bool = bool(item.get("is_quest_item"))
	var personal: String = str(item.get("personal_quest_id"))
	if personal != "":
		return "[E] Take %s" % label
	if not bool(can_carry_item(item).get("ok", true)):
		return "[E] %s" % refusal_text()
	if is_quest_item:
		return "[E] Take %s" % label
	return "[E] Steal %s" % label


## Keep the collected actor visible for the authored pickup beat, then free it.
## The actor leaves every gameplay group and stops monitoring immediately, so
## loot counts, thief vision and the economy audit never see a ghost pickup.
static func begin_linger(item: Node, seconds: float = -1.0) -> float:
	var delay: float = seconds if seconds >= 0.0 else actor_linger_s()
	item.set_meta("collected", true)
	item.set_meta("linger_s", delay)
	for group: String in PICKUP_GROUPS:
		if item.is_in_group(group):
			item.remove_from_group(group)
	if item is Area3D:
		var area := item as Area3D
		area.collision_layer = 0
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
	if item is CollisionObject3D:
		var body := item as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	if not item.is_inside_tree():
		item.queue_free()
		return delay
	var timer: SceneTreeTimer = item.get_tree().create_timer(maxf(delay, 0.0))
	timer.timeout.connect(func() -> void:
		if is_instance_valid(item):
			item.queue_free()
	)
	return delay


## Build the post-match payout record. Every authored field the shipped
## post-match UI reads is present: Original/Kept/Stashed and MoneyTaken.
##   score       = Kept x stealth multiplier (the shipped contract score)
##   money_taken = score + Stashed + Reward
## so an escape banks the full stealth-adjusted haul plus the stashed value,
## a capture keeps only Stashed, and free play records the same numbers but
## SaveSystem.bank_payout banks 0.
static func build_payout(outcome: String, opts: Dictionary = {}) -> Dictionary:
	var stashed: int = maxi(GameState.stashed_loot_value, 0)
	var original: int = maxi(GameState.loot_value, 0)
	var carried_total: int = carried_value()
	if not GameState.carried_tracking_active:
		# Legacy/staged runs (and the headless suites) set loot_value directly:
		# treat the gross counter as the carried haul instead of dropping it.
		carried_total = original
	var ratio: float = kept_ratio(outcome)
	var kept: int = int(round(float(carried_total) * ratio))
	var stealth: float = GameState.compute_stealth_bonus_multiplier()
	var score: int = int(round(float(kept) * stealth))
	var free_play: bool = GameState.free_play
	var complete: bool = bool(opts.get("objectives_complete", false))
	var reward: int = 0
	# A first-class Cleanout banks the haul but earns no contract reward: the
	# hosting contract was never played (GameState.run_credits_contract).
	if outcome == "escape" and complete and GameState.run_credits_contract():
		reward = contract_reward(GameState.active_map_id)
	var money_taken: int = score + stashed + reward
	var entries: Array = []
	for entry_v: Variant in GameState.carried_loot:
		if entry_v is Dictionary:
			entries.append((entry_v as Dictionary).duplicate(true))
	var match_id: String = str(opts.get("match_id", GameState.loot_run_id))
	if match_id == "":
		match_id = "%s|%s|%d" % [GameState.active_mission_id, GameState.active_map_id, int(GameState.elapsed_sec)]
	return {
		"match_id": match_id,
		"mission_id": GameState.active_mission_id,
		"contract_order": GameState.active_contract_order,
		"map_id": GameState.active_map_id,
		"outcome": outcome,
		"original": original,
		"kept": kept,
		"stashed": stashed,
		"reward": reward,
		"score": score,
		"money_taken": money_taken,
		"stealth_mult": stealth,
		"capture": outcome != "escape",
		"free_play": free_play,
		"applied": false,
		"banked": 0,
		"carried": entries,
	}


static func _find_hud(actor: Node) -> Node:
	var tree: SceneTree = null
	if actor != null and actor.is_inside_tree():
		tree = actor.get_tree()
	elif Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var mission: Node = tree.get_first_node_in_group("mission")
	if mission != null:
		var h_v: Variant = mission.get("hud")
		if h_v is Node and is_instance_valid(h_v as Node):
			return h_v as Node
	return tree.get_first_node_in_group("hud")
