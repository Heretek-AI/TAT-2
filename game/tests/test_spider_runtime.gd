extends RefCounted
## In-process mock/unit suite for the Spider personal-chain runtime (W1S).
##
## Suite 87 in `tests/run_tests.gd` calls `run(root)`. Nothing here loads a map,
## spawns a mission or starts a second engine: the mock drives the same
## PersonalQuest API the mission/NPC/dialogue call, plus the real dialogue and
## loot-item classes in an isolated fixture, then restores every shared autoload
## field and the developer save exactly like suite 86 does.
##
## Covered:
##   * deploy/hub chain per stage and map (spawn plan pins, Chameleon no-op);
##   * the authored 03/04 prompt, first line, follow-up and fact grants;
##   * no Reminder / Renegade / ObjectiveComplete_* fact, ever;
##   * the Owl pickup grants no loot value, no currency, no objective, and is
##     not in the "loot" group;
##   * the dialogue modal opens without pausing, ignores the opening frame,
##     closes on Escape/interact, and uses Alata 32 / 30 with CONTINUE;
##   * save persistence after a full chain.

const PersonalQuestScript := preload("res://src/quests/personal_quest.gd")
const NpcActorScript := preload("res://src/quests/npc_clue_actor.gd")
const NpcDialogueScript := preload("res://src/quests/npc_clue_dialogue.gd")
const LootScript := preload("res://src/interact/loot_item.gd")

const FIRST_03: String = "Aye, it's a Langnacht night tonight. I'll take the goods."
const FOLLOW_03: String = "We're done here. Skedaddle aff."
const FIRST_04: String = "I heard you're looking for dirt on Mallick. This might help. If anyone asks, you didn't get it from me."
const FOLLOW_04: String = "We're done here. I have nothing else for you."


## Host stub for the dialogue: the real HUD only adds a reference and the two
## arbitration methods, so a Node with the same surface exercises the contract.
class MockHud extends Node:
	var dialogue: Node = null

	func set_npc_dialogue(node: Node) -> void:
		dialogue = node

	func is_npc_dialogue_open() -> bool:
		return dialogue != null and is_instance_valid(dialogue) and bool(dialogue.call("is_open"))


static func _check(problems: Array[String], cond: bool, ok: String, fail: String = "") -> void:
	if cond:
		print("PASS: [spider] ", ok)
	else:
		problems.append(fail if fail != "" else ok)


static func _anchor_ids(plan: Array) -> Array[String]:
	var out: Array[String] = []
	for rec_v: Variant in plan:
		if rec_v is Dictionary:
			out.append(str((rec_v as Dictionary).get("id", "")))
	out.sort()
	return out


static func _journal_ids(gs: Node) -> Array:
	var out: Array = []
	for entry_v: Variant in gs.get("clue_facts") as Array:
		if entry_v is Dictionary:
			out.append(str((entry_v as Dictionary).get("id", "")))
	return out


static func run(host: Node) -> Array[String]:
	var problems: Array[String] = []
	if host == null:
		problems.append("suite host is null")
		return problems
	var ss: Node = host.get_node_or_null("/root/SaveSystem")
	var gs: Node = host.get_node_or_null("/root/GameState")
	if ss == null or gs == null:
		problems.append("SaveSystem/GameState autoload missing")
		return problems

	var save_path: String = "user://tat2_save.json"
	var had_file: bool = FileAccess.file_exists(save_path)
	var file_backup: String = FileAccess.get_file_as_string(save_path) if had_file else ""
	var live_backup: Dictionary = (ss.get("data") as Dictionary).duplicate(true)
	var gs_thief: String = str(gs.get("thief_id"))
	var gs_thumb: bool = bool(gs.get("free_play"))
	var gs_free_pending: bool = bool(gs.get("free_play_pending"))
	var gs_facts: Array = (gs.get("clue_facts") as Array).duplicate(true)
	var gs_loot: int = int(gs.get("loot_collected"))
	var gs_value: int = int(gs.get("loot_value"))
	var gs_quest_item: bool = bool(gs.get("quest_item_acquired"))
	var gs_objectives: Array = (gs.get("mission_objectives") as Array).duplicate(true)

	ss.call("reset_personal_quest", "spider")
	ss.call("reset_personal_quest", "chameleon")
	gs.clue_facts.clear()
	gs.set("thief_id", "spider")

	# --- Deploy / hub chain and pins -------------------------------------
	var deploy0: Dictionary = PersonalQuestScript.on_deploy("guildhall")
	_check(problems, str(PersonalQuestScript.stage_for("spider")) == "intro", "first Guildhall deploy starts intro", "deploy did not start intro: %s" % str(deploy0))
	_check(problems, _anchor_ids(PersonalQuestScript.spawn_plan("guildhall")).has("library_note"), "intro pins the Library note", "intro plan lacks the Library note")
	_check(problems, not (PersonalQuestScript.facts_for("spider") as Array).has("DT_ClueFacts_Personal_Spider_01:FoundLetter"), "intro grants only Intro")
	_check(problems, str(PersonalQuestScript.on_deploy("old_manor").get("reason", "")) == "ok" and str(PersonalQuestScript.stage_for("spider")) == "intro", "a non-Guildhall deploy does not advance the chain")
	_check(problems, PersonalQuestScript.spawn_plan("old_manor").is_empty(), "intro has no Old Manor pin")

	PersonalQuestScript.record("letter")
	_check(problems, PersonalQuestScript.spawn_plan("guildhall").is_empty(), "after the note is read its pin is gone")
	_check(problems, (PersonalQuestScript.facts_for("spider") as Array).has("DT_ClueFacts_Personal_Spider_01:FoundLetter"), "reading the note grants FoundLetter")
	var hub: Dictionary = PersonalQuestScript.on_hub_enter()
	_check(problems, str(PersonalQuestScript.stage_for("spider")) == "electrotype", "Den entry delivers the pending messages", "hub stage=%s %s" % [str(PersonalQuestScript.stage_for("spider")), str(hub)])
	_check(problems, (PersonalQuestScript.facts_for("spider") as Array).has("DT_ClueFacts_Personal_Spider_01:MallickSlip") and (PersonalQuestScript.facts_for("spider") as Array).has("DT_ClueFacts_Personal_Spider_01:StatuePet"), "electrotype grants MallickSlip and StatuePet")
	_check(problems, ",".join(_anchor_ids(PersonalQuestScript.spawn_plan("guildhall"))) == "owl", "electrotype pins the Owl")

	var located: Dictionary = PersonalQuestScript.on_deploy("guildhall")
	_check(problems, str(PersonalQuestScript.stage_for("spider")) == "located", "next Guildhall deploy locates the Owl", str(located))
	_check(problems, (PersonalQuestScript.facts_for("spider") as Array).has("DT_ClueFacts_Personal_Spider_02:OwlLocation"), "located grants OwlLocation")
	_check(problems, ",".join(_anchor_ids(PersonalQuestScript.spawn_plan("guildhall"))) == "owl", "located still pins the Owl")

	var carried: Dictionary = PersonalQuestScript.acquire_owl()
	_check(problems, str(PersonalQuestScript.stage_for("spider")) == "carrying" and str(PersonalQuestScript.owl_for("spider")) == "held", "Owl pickup -> carrying/held", str(carried))
	_check(problems, ",".join(_anchor_ids(PersonalQuestScript.spawn_plan("guildhall"))) == "courier", "carrying pins the Lounge courier")
	_check(problems, _anchor_ids(PersonalQuestScript.spawn_plan("old_manor")).is_empty(), "carrying has no Old Manor pin")

	# --- Courier actor: prompt, first line, follow-up ---------------------
	var courier: Node = NpcActorScript.new()
	courier.call("setup_npc", "courier", "spider", "", "", Vector3.ZERO)
	_check(problems, str(courier.call("get_interact_prompt")) == "[E] Talk", "courier prompt is [E] Talk")
	var talk1: Dictionary = courier.call("resolve_talk")
	_check(problems, bool(talk1.get("ok", false)) and bool(talk1.get("first", false)), "courier first interaction succeeds")
	_check(problems, str(talk1.get("text", "")) == FIRST_03, "courier first line is the shipped 03 line", "courier line=%s" % str(talk1.get("text", "")))
	_check(problems, (PersonalQuestScript.facts_for("spider") as Array).has("DT_ClueFacts_Personal_Spider_03:HandedOff"), "courier grants 03:HandedOff")
	_check(problems, not (PersonalQuestScript.facts_for("spider") as Array).has("DT_ClueFacts_Personal_Spider_03:Reminder"), "03:Reminder is never granted")
	_check(problems, str(PersonalQuestScript.stage_for("spider")) == "delivered" and str(PersonalQuestScript.owl_for("spider")) == "delivered", "courier -> delivered, Owl delivered")
	var talk2: Dictionary = courier.call("resolve_talk")
	_check(problems, bool(talk2.get("ok", false)) and not bool(talk2.get("first", true)), "courier later interaction is a follow-up")
	_check(problems, str(talk2.get("text", "")) == FOLLOW_03, "courier follow-up is the shipped 03 line", "courier follow-up=%s" % str(talk2.get("text", "")))
	_check(problems, (PersonalQuestScript.facts_for("spider") as Array).size() == 6, "the follow-up adds no fact")
	courier.free()
	_check(problems, PersonalQuestScript.spawn_plan("guildhall").is_empty(), "delivered has no Guildhall pin")
	_check(problems, ",".join(_anchor_ids(PersonalQuestScript.spawn_plan("old_manor"))) == "informant", "delivered pins the Old Manor informant")

	# --- Informant actor: first fact, then follow-up close ---------------
	var informant: Node = NpcActorScript.new()
	informant.call("setup_npc", "informant", "spider", "", "", Vector3.ZERO)
	_check(problems, str(informant.call("get_interact_prompt")) == "[E] Talk", "informant prompt is [E] Talk")
	var info1: Dictionary = informant.call("resolve_talk")
	_check(problems, bool(info1.get("ok", false)) and str(info1.get("text", "")) == FIRST_04, "informant first line is the shipped 04 line", "informant line=%s" % str(info1.get("text", "")))
	_check(problems, (PersonalQuestScript.facts_for("spider") as Array).has("DT_ClueFacts_Personal_Spider_04:GotInfo"), "informant grants 04:GotInfo once")
	_check(problems, not (PersonalQuestScript.facts_for("spider") as Array).has("DT_ClueFacts_Personal_Spider_04:Renegade"), "04:Renegade is never granted")
	_check(problems, str(PersonalQuestScript.stage_for("spider")) == "info", "informant -> info")
	var info2: Dictionary = informant.call("resolve_talk")
	_check(problems, bool(info2.get("ok", false)) and str(info2.get("text", "")) == FOLLOW_04, "informant follow-up is the shipped 04 line", "informant follow-up=%s" % str(info2.get("text", "")))
	_check(problems, str(PersonalQuestScript.stage_for("spider")) == "complete", "informant follow-up closes the chain")
	_check(problems, (PersonalQuestScript.facts_for("spider") as Array).size() == 7, "closing grants no extra fact")
	var info3: Dictionary = informant.call("resolve_talk")
	_check(problems, str(info3.get("text", "")) == FOLLOW_04 and str(PersonalQuestScript.stage_for("spider")) == "complete", "complete keeps the authored follow-up")
	informant.free()

	var forbidden: Array[String] = [
		"DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Clue",
		"DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Electrogram",
		"DT_ClueFacts_Personal_Spider_03:Reminder",
		"DT_ClueFacts_Personal_Spider_04:Renegade",
	]
	var final_facts: Array = PersonalQuestScript.facts_for("spider")
	for bad: String in forbidden:
		_check(problems, not final_facts.has(bad) and not gs.call("has_clue_fact", bad), "suppressed fact absent: " + bad)

	# --- Chameleon is not this chain -------------------------------------
	var cham_deploy: Dictionary = PersonalQuestScript.on_deploy("guildhall", "chameleon")
	_check(problems, str(cham_deploy.get("reason", "")) == "not_spider" and str(PersonalQuestScript.stage_for("chameleon")) == "", "Chameleon deploy is a no-op")
	_check(problems, PersonalQuestScript.spawn_plan("guildhall", "chameleon").is_empty(), "Chameleon has no spawn plan")

	# --- Owl pickup is not loot ------------------------------------------
	ss.call("reset_personal_quest", "spider")
	gs.clue_facts.clear()
	PersonalQuestScript.on_deploy("guildhall")
	PersonalQuestScript.record("letter")
	PersonalQuestScript.on_hub_enter()
	PersonalQuestScript.on_deploy("guildhall")
	_check(problems, str(PersonalQuestScript.stage_for("spider")) == "located", "fixture reaches located")

	var currency_before: int = int((ss.get("data") as Dictionary).get("currency", 0))
	var completed_before: Dictionary = ((ss.get("data") as Dictionary).get("completed_contracts", {}) as Dictionary).duplicate(true)
	var loot_before: int = int(gs.get("loot_collected"))
	var value_before: int = int(gs.get("loot_value"))
	var owl: Node = LootScript.new()
	owl.set("personal_quest_id", "personal_spider")
	owl.set("display_name", "Theban Owl")
	owl.set("item_name", "Theban Owl")
	owl.set("value", 2500)
	owl.name = "SpiderRuntimeOwlFixture"
	host.add_child(owl)
	_check(problems, not owl.is_in_group("loot"), "the Owl is not in the loot group")
	_check(problems, str(owl.call("get_interact_prompt")) == "[E] Take Theban Owl", "Owl prompt is [E] Take Theban Owl", "owL prompt=%s" % str(owl.call("get_interact_prompt")))
	owl.call("interact", null)
	_check(problems, str(PersonalQuestScript.stage_for("spider")) == "carrying" and str(PersonalQuestScript.owl_for("spider")) == "held", "Owl interaction -> carrying/held")
	_check(problems, int(gs.get("loot_collected")) == loot_before and int(gs.get("loot_value")) == value_before, "Owl pickup adds no loot count/value")
	_check(problems, not bool(gs.get("quest_item_acquired")), "Owl pickup does not set quest_item_acquired")
	_check(problems, int((ss.get("data") as Dictionary).get("currency", 0)) == currency_before, "Owl pickup adds no currency")
	_check(problems, ((ss.get("data") as Dictionary).get("completed_contracts", {}) as Dictionary) == completed_before, "Owl pickup banks no contract progress")
	_check(problems, bool(owl.get_meta("collected", false)), "the Owl marks itself collected")

	# --- Dialogue modal --------------------------------------------------
	var mock: MockHud = MockHud.new()
	mock.name = "SpiderRuntimeMockHud"
	host.add_child(mock)
	var dlg: Node = NpcDialogueScript.new()
	mock.add_child(dlg)
	dlg.call("open", mock, FIRST_03)
	_check(problems, bool(dlg.call("is_open")) and dlg.visible, "dialogue opens visible")
	_check(problems, mock.dialogue == dlg and mock.is_npc_dialogue_open(), "dialogue registers with the HUD")
	_check(problems, not host.get_tree().paused, "dialogue does not pause the tree")
	_check(problems, str(dlg.call("body_text")) == FIRST_03, "dialogue shows the authored line")
	_check(problems, int(dlg.call("body_font_size")) == 32, "dialogue body is Alata 32")
	_check(problems, str(dlg.call("button_text")) == "CONTINUE" and int(dlg.call("button_font_size")) == 30, "dialogue button is CONTINUE at 30")
	var esc: InputEventKey = InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	dlg.call("_input", esc)
	_check(problems, bool(dlg.call("is_open")), "opening-frame input does not self-close the dialogue")
	dlg.set("_opened_frame", Engine.get_process_frames() - 1)
	dlg.call("_input", esc)
	_check(problems, not bool(dlg.call("is_open")) and not dlg.visible, "Escape closes the dialogue on a later frame")
	_check(problems, not mock.is_npc_dialogue_open(), "closing clears the HUD reference")
	# Interact closes too.
	dlg.call("open", mock, FOLLOW_03)
	dlg.set("_opened_frame", Engine.get_process_frames() - 1)
	var interact_ev: InputEventKey = InputEventKey.new()
	interact_ev.physical_keycode = KEY_F
	interact_ev.pressed = true
	dlg.call("_input", interact_ev)
	_check(problems, not bool(dlg.call("is_open")), "interact closes the dialogue")
	# The real HUD exposes the same arbitration surface.
	var hud_script: GDScript = load("res://src/ui/hud.gd") as GDScript
	var hud_has: bool = false
	for m: Dictionary in hud_script.get_script_method_list():
		if str(m.get("name", "")) == "is_npc_dialogue_open":
			hud_has = true
			break
	_check(problems, hud_has, "HUD exposes is_npc_dialogue_open()")
	mock.queue_free()

	# --- The chain banks no contract progress or objectives --------------
	_check(problems, int(gs.get("loot_collected")) == gs_loot and int(gs.get("loot_value")) == gs_value, "the chain leaves the loot counters alone")
	_check(problems, bool(gs.get("quest_item_acquired")) == gs_quest_item, "the chain leaves quest_item_acquired alone")
	_check(problems, (gs.get("mission_objectives") as Array) == gs_objectives, "the chain adds no objective")

	# --- Persistence: finish the fixture and reload a fresh save ---------
	PersonalQuestScript.deliver_owl()
	PersonalQuestScript.deliver_info()
	PersonalQuestScript.close_info()
	_check(problems, str(PersonalQuestScript.stage_for("spider")) == "complete", "fixture completes after the Owl path")
	ss.call("write_save")
	var fresh: Node = (load("res://src/core/save_system.gd") as GDScript).new()
	fresh.set("data", fresh.call("_defaults"))
	fresh.call("load_save")
	var restored: Dictionary = fresh.call("get_personal_quest", "spider") as Dictionary
	_check(problems, str(restored.get("stage", "")) == "complete" and str(restored.get("owl", "")) == "delivered", "save round-trip keeps stage/owl", str(restored))
	_check(problems, (restored.get("facts", []) as Array).size() == 7, "save round-trip keeps the seven facts", str(restored.get("facts", [])))
	fresh.free()

	# Restore everything this suite borrowed.
	ss.set("data", live_backup)
	if had_file:
		var f: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
		if f != null:
			f.store_string(file_backup)
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	gs.set("thief_id", gs_thief)
	gs.set("free_play", gs_thumb)
	gs.set("free_play_pending", gs_free_pending)
	gs.clue_facts.clear()
	for fact_v: Variant in gs_facts:
		if fact_v is Dictionary:
			(gs.get("clue_facts") as Array).append(fact_v as Dictionary)
	gs.set("loot_collected", gs_loot)
	gs.set("loot_value", gs_value)
	gs.set("quest_item_acquired", gs_quest_item)
	var restored_objs: Array[Dictionary] = []
	for obj_v: Variant in gs_objectives:
		if obj_v is Dictionary:
			restored_objs.append(obj_v as Dictionary)
	gs.set("mission_objectives", restored_objs)

	if problems.is_empty():
		print("PASS: [spider] runtime mock (deploy/hub/plan, 03/04 lines and facts, no loot, dialogue, persistence)")
	return problems
