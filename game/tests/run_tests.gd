extends SceneTree
## Headless automated verification suite for TAT-2.

func _initialize() -> void:
	await process_frame
	var fails := 0
	var root := get_root()
	var gd := root.get_node_or_null("GameData")
	var gs := root.get_node_or_null("GameState")
	var nb := root.get_node_or_null("NoiseBus")
	var ss := root.get_node_or_null("SaveSystem")

	if gd == null or gs == null or nb == null or ss == null:
		printerr("FAIL: autoloads missing")
		quit(1)
		return

	# 1. Contracts loaded (16 shipped + 2 expansion = 18)
	if gd.contracts.size() != 18:
		printerr("FAIL: expected 18 contracts, got ", gd.contracts.size())
		fails += 1
	else:
		print("PASS: 18 contracts loaded (16 shipped + 2 expansion)")

	var c2: Dictionary = gd.get_contract_display(2)
	if str(c2.get("title", "")) != "Into the Lion's Den":
		printerr("FAIL: Contract 2 title mismatch: ", c2.get("title", ""))
		fails += 1
	else:
		print("PASS: Contract 2 string table resolved ('Into the Lion's Den')")

	if gd.get_contract_sublevel_tag(2) != "Guildhall_Contract_02" or gd.tables.is_empty():
		printerr("FAIL: sublevel tag or DataTables missing: ", gd.get_contract_sublevel_tag(2), " tables=", gd.tables.size())
		fails += 1
	else:
		print("PASS: Contract sublevel tags & ", gd.tables.size(), " DataTables loaded")

	if root.get_node_or_null("AudioManager") == null:
		printerr("FAIL: AudioManager autoload missing")
		fails += 1
	else:
		print("PASS: AudioManager autoload active")

	# 2. CurveTables
	var hp_novice: float = gd.eval_curve("CT_PlayerStats", "BaseHealth", 1.0, -1.0)
	var hp_master: float = gd.eval_curve("CT_PlayerStats", "BaseHealth", 3.0, -1.0)
	var ko_novice: float = gd.eval_curve("CT_AIStats", "GuardKnockoutDuration", 1.0, -1.0)
	var bj_heavy: float = gd.eval_curve("CT_Tool_Blackjack", "BlackjackDamageHeavy", 1.0, -1.0)
	if not is_equal_approx(hp_novice, 300.0) or not is_equal_approx(hp_master, 150.0) or not is_equal_approx(ko_novice, 300.0) or not is_equal_approx(bj_heavy, 75.0):
		printerr("FAIL: curve values mismatch: ", [hp_novice, hp_master, ko_novice, bj_heavy])
		fails += 1
	else:
		print("PASS: Shipped CurveTables (Player HP 300->150, Guard KO 300s, Blackjack 75)")

	# 3. LightProbe short-circuit
	var lp: Node = (load("res://src/stealth/light_probe.gd") as GDScript).new()
	var l := OmniLight3D.new()
	l.position = Vector3(5, 2, 0)
	lp.register_light(l)
	var killed: int = lp.short_circuit_lights(Vector3(0, 0, 0), 20.0, 25.0, 0.0)
	if killed != 1 or l.visible:
		printerr("FAIL: Slithersap light short-circuit failed")
		fails += 1
	else:
		lp.tick(26.0)
		if not l.visible:
			printerr("FAIL: Light did not restore after 25s")
			fails += 1
		else:
			print("PASS: LightProbe Slithersap short-circuit & 25s restore")
	l.free()
	lp.free()

	# 4. MissionController smoke test (Contract 3 - Old Manor)
	gs.thief_id = "spider"
	gs.difficulty = 2
	gs.active_contract_order = 3
	var mission_scene: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission_scene)
	await process_frame
	await process_frame
	var guards := get_nodes_in_group("guards")
	var loots := get_nodes_in_group("loot")
	if guards.size() < 4 or loots.size() < 5:
		printerr("FAIL: mission spawn counts too low: guards=", guards.size(), " loots=", loots.size())
		fails += 1
	else:
		print("PASS: Old Manor mission spawned ", guards.size(), " guards and ", loots.size(), " loot items")

	# 5. End-to-end contract completion
	gs.add_loot(1, 350, true)
	var mult: float = gs.compute_stealth_bonus_multiplier()
	if not is_equal_approx(mult, 1.25):
		printerr("FAIL: expected Ghost multiplier 1.25, got ", mult)
		fails += 1
	else:
		print("PASS: Ghost stealth bonus 1.25x verified")

	mission_scene.queue_free()
	await process_frame

	# 6. LockableDoor lockpicking progression
	var door_node: Node = (load("res://src/interact/lockable_door.gd") as GDScript).new()
	door_node.locked = true
	door_node.lock_level = 2
	root.add_child(door_node)
	door_node.interact(null)
	if door_node.lockpick_progress <= 0.0 or not door_node.get_interact_prompt().begins_with("[E] Pick Lock"):
		printerr("FAIL: LockableDoor lockpicking failed")
		fails += 1
	else:
		print("PASS: LockableDoor lockpick progress & prompt verified")
	door_node.queue_free()
	await process_frame

	# 7. ThievesDen peaceful hub (0 hostile guards)
	gs.active_contract_order = 1
	var den_scene: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(den_scene)
	await process_frame
	await process_frame
	var den_guards := get_nodes_in_group("guards")
	var den_interactables := get_nodes_in_group("interactables")
	if den_guards.size() != 0 or den_interactables.size() < 2:
		printerr("FAIL: ThievesDen hub guards=", den_guards.size(), " interactables=", den_interactables.size())
		fails += 1
	else:
		print("PASS: ThievesDen peaceful hub verified (0 guards, ", den_interactables.size(), " interactables)")
	den_scene.queue_free()
	await process_frame

	# 8. WardrobeUI, ContractTableUI, ClueItem & VfxManager new helpers
	var wui_scr: GDScript = load("res://src/ui/wardrobe_ui.gd") as GDScript
	var cui_scr: GDScript = load("res://src/ui/contract_table_ui.gd") as GDScript
	var clue_scr: GDScript = load("res://src/interact/clue_item.gd") as GDScript
	var vfx_scr: GDScript = load("res://src/core/vfx_manager.gd") as GDScript
	if wui_scr == null or cui_scr == null or clue_scr == null or vfx_scr == null:
		printerr("FAIL: New scripts failed to load")
		fails += 1
	else:
		var wui: CanvasLayer = wui_scr.new()
		var cui: CanvasLayer = cui_scr.new()
		var clue: Area3D = clue_scr.new()
		root.add_child(wui)
		root.add_child(cui)
		root.add_child(clue)
		await process_frame
		clue.interact(null)
		vfx_scr.spawn_lockpick_sparks(root, Vector3.ZERO)
		vfx_scr.spawn_blackjack_swing(root, Vector3.ZERO, Vector3.FORWARD)
		vfx_scr.spawn_window_godray(root, Vector3(0, 3, 0), Vector3.ZERO)
		if not clue.collected:
			printerr("FAIL: ClueItem interact failed")
			fails += 1
		else:
			print("PASS: WardrobeUI, ContractTableUI, ClueItem & VfxManager full-port checks verified")
		wui.queue_free()
		cui.queue_free()
		clue.queue_free()
		await process_frame

	print("SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)
