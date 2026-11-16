extends Node
## Global run state: selected thief, contract, difficulty, loot, stealth ratings.

signal loot_changed(collected: int, needed: int, value: int)
signal objective_completed()
signal state_changed(new_state: String)

enum Difficulty { NOVICE = 1, THIEF = 2, MASTER_THIEF = 3 }

var thief_id: String = "spider" # spider | chameleon | moth
var outfit_body: String = "Default"
var outfit_head: String = "Default"
var calling_card: String = "Default"
var difficulty: int = Difficulty.NOVICE
var active_contract_order: int = 2
var active_map_id: String = "old_manor"

var state: String = "menu" # menu | hub | playing | paused | victory | failed
var elapsed_sec: float = 0.0
var loot_collected: int = 0
var loot_needed: int = 5
var loot_value: int = 0
var quest_item_acquired: bool = false
var ever_spotted: bool = false
var ever_chased: bool = false
var takedowns: int = 0
var player_light_visibility: float = 0.2 # 0.0 shadow .. 1.0 bright


func reset_run(contract_order: int, map_id: String) -> void:
	active_contract_order = contract_order
	active_map_id = map_id
	elapsed_sec = 0.0
	loot_collected = 0
	loot_value = 0
	quest_item_acquired = false
	ever_spotted = false
	ever_chased = false
	takedowns = 0
	player_light_visibility = 0.2
	state = "playing"
	state_changed.emit(state)
	loot_changed.emit(loot_collected, loot_needed, loot_value)


func add_loot(amount: int, value: int, is_quest_item: bool = false) -> void:
	loot_collected += amount
	loot_value += value
	if is_quest_item:
		quest_item_acquired = true
		objective_completed.emit()
	loot_changed.emit(loot_collected, loot_needed, loot_value)


func difficulty_label() -> String:
	match difficulty:
		Difficulty.NOVICE: return "Novice"
		Difficulty.THIEF: return "Thief"
		Difficulty.MASTER_THIEF: return "Master Thief"
	return "Novice"


func difficulty_curve_x() -> float:
	return float(difficulty)


func compute_stealth_bonus_multiplier() -> float:
	var mult := 1.0
	if not ever_spotted:
		mult += 0.25 # Ghost
	elif not ever_chased:
		mult += 0.10 # Shadow
	return mult
