extends SceneTree
## Real-map walkthrough of the Spider personal chain 01 -> 04 (W1S).
##
## Loads the authored Guildhall (contract 4) and Old Manor (contract 3) levels
## through the real mission controller and drives the same interactions the
## player does: read the Library note, return to the Den, locate and take the
## Vault Owl, hand it to the Lounge courier, then talk to the Courtyard
## informant twice (first line + follow-up close).
##
## Run alone (never beside another Godot process, thermal rule):
##   tools/godot --headless --path game --script res://tests/probe_personal_quest.gd
##
## The probe restores the developer save and the GameState run fields it
## borrows, and exits non-zero on the first failed expectation.

const PersonalQuestScript := preload("res://src/quests/personal_quest.gd")

var fails: int = 0
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, ok: String, fail: String = "") -> bool:
	checks += 1
	if cond:
		print("PASS: [pq] ", ok)
		return true
	fails += 1
	printerr("FAIL: [pq] ", fail if fail != "" else ok)
	return false


func _wait_tree(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _wait_mission(mission: Node, want_personal: bool) -> bool:
	var waited: int = 0
	while waited < 3600:
		var player: Node = mission.get("player") as Node
		var actors: Array = mission.get("personal_quest_actors") as Array
		if player != null and (not want_personal or not actors.is_empty()):
			# Let the spawn/grounding pass and the first physics frame settle.
			await process_frame
			await process_frame
			return true
		await process_frame
		waited += 1
	return false


func _actor(mission: Node, anchor_id: String) -> Dictionary:
	var actors: Array = mission.get("personal_quest_actors") as Array
	for rec_v: Variant in actors:
		if rec_v is Dictionary and str((rec_v as Dictionary).get("anchor_id", "")) == anchor_id:
			return rec_v as Dictionary
	return {}


func _journal_ids(gs: Node) -> Array:
	var out: Array = []
	for entry_v: Variant in gs.get("clue_facts") as Array:
		if entry_v is Dictionary:
			out.append(str((entry_v as Dictionary).get("id", "")))
	return out


func _load_mission(order: int) -> Node:
	var gs: Node = root.get_node_or_null("/root/GameState")
	gs.set("active_contract_order", order)
	var mission: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission)
	return mission


func _free_mission(mission: Node) -> void:
	if mission != null and is_instance_valid(mission):
		mission.queue_free()
	await _wait_tree(8)


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	var ss: Node = root.get_node_or_null("/root/SaveSystem")
	if gs == null or ss == null:
		printerr("PERSONAL QUEST FAIL: autoloads missing")
		quit(1)
		return

	var save_path: String = "user://tat2_save.json"
	var had_file: bool = FileAccess.file_exists(save_path)
	var file_backup: String = FileAccess.get_file_as_string(save_path) if had_file else ""
	var live_backup: Dictionary = (ss.get("data") as Dictionary).duplicate(true)
	var gs_thief: String = str(gs.get("thief_id"))
	var gs_free: bool = bool(gs.get("free_play"))
	var gs_free_pending: bool = bool(gs.get("free_play_pending"))
	var gs_facts: Array = (gs.get("clue_facts") as Array).duplicate(true)
	var loot_before: int = int(gs.get("loot_collected"))
	var value_before: int = int(gs.get("loot_value"))
	var currency_before: int = int((ss.get("data") as Dictionary).get("currency", 0))
	var objectives_before: int = (gs.get("mission_objectives") as Array).size()

	ss.call("reset_personal_quest", "spider")
	gs.clue_facts.clear()
	gs.set("thief_id", "spider")

	# ---- Guildhall: intro note -> hub -> located Owl --------------------
	var guildhall: Node = _load_mission(4)
	var guildhall_ready: bool = await _wait_mission(guildhall, true)
	if not guildhall_ready:
		_check(false, "Guildhall mission with personal actors", "Guildhall did not load the intro actor")
		await _cleanup(guildhall, ss, live_backup, save_path, had_file, file_backup, gs, gs_thief, gs_free, gs_free_pending, gs_facts)
		quit(1)
		return
	_check(str(PersonalQuestScript.stage_for("spider")) == "intro", "deploy starts intro")
	var note_rec: Dictionary = _actor(guildhall, "library_note")
	_check(not note_rec.is_empty(), "Library note actor spawned")
	var note: Node = note_rec.get("node", null) as Node
	if note != null:
		var np: Vector3 = (note as Node3D).global_position
		_check(Vector2(np.x + 26.8541, np.z + 9.4431).length() < 0.1 and absf(np.y - 28.0021) < 3.0, "note is grounded at the Library pin", "note pos=%s" % str(np))
		_check(note.is_in_group("interactables"), "note is interactable")
		var player: Node = guildhall.get("player") as Node
		note.call("interact", player)
		await process_frame
	_check(str(PersonalQuestScript.stage_for("spider")) == "letter", "reading the note advances letter")
	_check(_journal_ids(gs).has("DT_ClueFacts_Personal_Spider_01:FoundLetter"), "FoundLetter journaled")

	# Den return (the Den itself is a separate hub scene; this is its hook).
	var hub: Dictionary = PersonalQuestScript.on_hub_enter()
	_check(str(PersonalQuestScript.stage_for("spider")) == "electrotype", "hub delivers pending messages", str(hub))
	# Next Guildhall deploy/entry: locate the Owl and repin it in this loaded map.
	var deploy: Dictionary = PersonalQuestScript.on_deploy("guildhall")
	_check(str(PersonalQuestScript.stage_for("spider")) == "located", "next deploy locates the Owl", str(deploy))
	if guildhall.has_method("_spawn_personal_quest_actors"):
		guildhall.call("_spawn_personal_quest_actors")
	await _wait_tree(3)
	var owl_rec: Dictionary = _actor(guildhall, "owl")
	_check(not owl_rec.is_empty(), "Vault Owl spawned for located")
	var owl: Node = owl_rec.get("node", null) as Node
	if owl != null:
		var op: Vector3 = (owl as Node3D).global_position
		_check(Vector2(op.x + 31.6286, op.z + 43.9759).length() < 0.1 and absf(op.y - 36.4655) < 3.0, "Owl is grounded at the Vault pin", "owl pos=%s" % str(op))
		_check(str(owl.call("get_interact_prompt")) == "[E] Take Theban Owl", "Owl prompt is Take")
		var player2: Node = guildhall.get("player") as Node
		owl.call("interact", player2)
		await _wait_tree(3)
	_check(str(PersonalQuestScript.stage_for("spider")) == "carrying" and str(PersonalQuestScript.owl_for("spider")) == "held", "Owl pickup -> carrying/held")
	_check(int(gs.get("loot_collected")) == loot_before and int(gs.get("loot_value")) == value_before, "Owl pickup adds no loot")
	_check(int((ss.get("data") as Dictionary).get("currency", 0)) == currency_before, "Owl pickup adds no currency")
	_check(not bool(gs.get("quest_item_acquired")), "Owl pickup sets no quest_item_acquired")

	var courier_rec: Dictionary = _actor(guildhall, "courier")
	_check(not courier_rec.is_empty(), "courier spawned immediately after the Owl pickup")
	var courier: Node = courier_rec.get("node", null) as Node
	if courier != null:
		var cp: Vector3 = (courier as Node3D).global_position
		_check(Vector2(cp.x - 35.9, cp.z + 22.728).length() < 0.1 and absf(cp.y - 27.0019) < 3.0, "courier is grounded at the Lounge pin", "courier pos=%s" % str(cp))
		_check(str(courier.call("get_interact_prompt")) == "[E] Talk", "courier prompt is [E] Talk")
		var player3: Node = guildhall.get("player") as Node
		courier.call("interact", player3)
		await _wait_tree(2)
	_check(str(PersonalQuestScript.stage_for("spider")) == "delivered" and str(PersonalQuestScript.owl_for("spider")) == "delivered", "courier hand-off -> delivered")
	_check(_journal_ids(gs).has("DT_ClueFacts_Personal_Spider_03:HandedOff"), "03:HandedOff journaled")
	var hud: Node = guildhall.get("hud") as Node
	_check(hud != null and hud.has_method("is_npc_dialogue_open") and bool(hud.call("is_npc_dialogue_open")), "courier opens the HUD conversation modal")
	var dlg: Node = hud.get_node_or_null("NpcClueDialogue") if hud != null else null
	_check(dlg != null and str(dlg.call("body_text")) == "Aye, it's a Langnacht night tonight. I'll take the goods.", "courier shows the shipped 03 line")
	if dlg != null:
		dlg.call("close")
	await _free_mission(guildhall)

	# ---- Old Manor: 04 informant, first line then follow-up close -------
	var manor: Node = _load_mission(3)
	var manor_ready: bool = await _wait_mission(manor, true)
	if not manor_ready:
		_check(false, "Old Manor mission with the informant", "Old Manor did not load the informant")
		await _cleanup(manor, ss, live_backup, save_path, had_file, file_backup, gs, gs_thief, gs_free, gs_free_pending, gs_facts)
		quit(1)
		return
	var inf_rec: Dictionary = _actor(manor, "informant")
	_check(not inf_rec.is_empty(), "04 informant spawned on Old Manor")
	var informant: Node = inf_rec.get("node", null) as Node
	if informant != null:
		var ip: Vector3 = (informant as Node3D).global_position
		_check(Vector2(ip.x - 1.5, ip.z - 13.0).length() < 0.1 and ip.y > 5.0, "informant is grounded in the Courtyard", "informant pos=%s" % str(ip))
		_check(str(informant.call("get_interact_prompt")) == "[E] Talk", "informant prompt is [E] Talk")
		var player4: Node = manor.get("player") as Node
		informant.call("interact", player4)
		await _wait_tree(2)
	_check(str(PersonalQuestScript.stage_for("spider")) == "info", "informant first talk -> info")
	_check(_journal_ids(gs).has("DT_ClueFacts_Personal_Spider_04:GotInfo"), "04:GotInfo journaled")
	var hud2: Node = manor.get("hud") as Node
	var dlg2: Node = hud2.get_node_or_null("NpcClueDialogue") if hud2 != null else null
	_check(dlg2 != null and str(dlg2.call("body_text")).begins_with("I heard you're looking for dirt on Mallick."), "informant shows the shipped 04 line")
	if dlg2 != null:
		dlg2.call("close")
	if informant != null:
		var player5: Node = manor.get("player") as Node
		informant.call("interact", player5)
		await _wait_tree(2)
	_check(str(PersonalQuestScript.stage_for("spider")) == "complete", "informant follow-up closes the chain")
	var dlg3: Node = hud2.get_node_or_null("NpcClueDialogue") if hud2 != null else null
	_check(dlg3 != null and str(dlg3.call("body_text")) == "We're done here. I have nothing else for you.", "informant follow-up is the shipped 04 line")
	if dlg3 != null:
		dlg3.call("close")
	await _free_mission(manor)

	# ---- Chain invariants ----------------------------------------------
	var facts: Array = PersonalQuestScript.facts_for("spider")
	_check(str(PersonalQuestScript.owl_for("spider")) == "delivered", "Owl ends delivered")
	_check(facts.size() == 7, "seven chain facts persisted", str(facts))
	for bad: String in [
		"DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Clue",
		"DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Electrogram",
		"DT_ClueFacts_Personal_Spider_03:Reminder",
		"DT_ClueFacts_Personal_Spider_04:Renegade",
	]:
		_check(not facts.has(bad) and not gs.call("has_clue_fact", bad), "suppressed fact absent: " + bad)
	_check(int(gs.get("loot_collected")) == loot_before and int(gs.get("loot_value")) == value_before, "chain banks no loot")
	_check(int((ss.get("data") as Dictionary).get("currency", 0)) == currency_before, "chain banks no currency")
	_check((gs.get("mission_objectives") as Array).size() == objectives_before, "chain adds no objective")

	_print_chain()
	await _cleanup(null, ss, live_backup, save_path, had_file, file_backup, gs, gs_thief, gs_free, gs_free_pending, gs_facts)
	print("PERSONAL QUEST ", "PASS" if fails == 0 else "FAIL", " checks=", checks, " fails=", fails)
	quit(0 if fails == 0 else 1)


func _print_chain() -> void:
	print("PERSONAL QUEST stage=", PersonalQuestScript.stage_for("spider"), " owl=", PersonalQuestScript.owl_for("spider"))
	for fact_v: Variant in PersonalQuestScript.facts_for("spider"):
		print("PERSONAL QUEST fact=", str(fact_v))


func _cleanup(mission: Node, ss: Node, live_backup: Dictionary, save_path: String, had_file: bool, file_backup: String, gs: Node, thief: String, free: bool, free_pending: bool, facts: Array) -> void:
	if mission != null and is_instance_valid(mission):
		await _free_mission(mission)
	ss.set("data", live_backup)
	if had_file:
		var f: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
		if f != null:
			f.store_string(file_backup)
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	gs.set("thief_id", thief)
	gs.set("free_play", free)
	gs.set("free_play_pending", free_pending)
	gs.clue_facts.clear()
	for fact_v: Variant in facts:
		if fact_v is Dictionary:
			(gs.get("clue_facts") as Array).append(fact_v as Dictionary)
