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

	# Thermal-safe QA shortcut: only the in-process Spider suites (87 runtime
	# mock, 88 settle path), no mission load and no child engine. The full
	# `make test` remains the ship gate; this exists so a hot host can still
	# verify the runtime chain.
	if OS.get_cmdline_user_args().has("--spider-only"):
		var only_fails: int = 0
		var c87_only: Array[String] = _run_suite87(root)
		if c87_only.is_empty():
			print("PASS: 87 Spider personal chain runtime (mock only)")
		else:
			printerr("FAIL: 87 Spider personal chain runtime: ", c87_only)
			only_fails += 1
		var c88_only: Array[String] = await _run_suite88(root)
		if c88_only.is_empty():
			print("PASS: 88 Spider personal chain settle path (mock only)")
		else:
			printerr("FAIL: 88 Spider personal chain settle path: ", c88_only)
			only_fails += 1
		print("SUMMARY: fails=", only_fails)
		quit(0 if only_fails == 0 else 1)
		return

	# P2-7: res://assets/ue/Content + Raw are symlinks into extracted/;
	# deleting/regenerating extracted/ orphans every GLB/PNG/OGG path.
	if DirAccess.open("res://assets/ue/Content") == null or DirAccess.open("res://assets/ue/Raw") == null:
		printerr("FAIL: assets/ue symlink target missing (extracted/ deleted or regenerated?)")
		fails += 1
	else:
		print("PASS: assets/ue symlinks resolve (Content + Raw)")

	# P2-6 fixture: blocks below mutate shared autoloads in place
	# (gs.thief_id/difficulty/active_contract_order/active_map_id). Snapshot
	# the boot values here, restore before SUMMARY, so inserting or
	# reordering blocks cannot cascade through stale autoload state.
	var fx_thief_id: String = str(gs.thief_id)
	var fx_difficulty: int = int(gs.difficulty)
	var fx_order: int = int(gs.active_contract_order)
	var fx_map_id: String = str(gs.active_map_id)

	# 1. Contracts loaded: Steam ships exactly 16 (Contract.Main.1..16).
	var c1_orders: Array = []
	for c1_v: Variant in gd.contracts:
		c1_orders.append(int((c1_v as Dictionary).get("order", -1)))
	c1_orders.sort()
	var c1_expect: Array = []
	for c1_i: int in range(1, 17):
		c1_expect.append(c1_i)
	if gd.contracts.size() != 16 or c1_orders != c1_expect:
		printerr("FAIL: expected 16 ordered contracts 1..16, got ", gd.contracts.size(), " orders=", c1_orders)
		fails += 1
	else:
		print("PASS: 16 shipped contracts, orders 1..16 (Contract.Main.15 repaired)")

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
	root.add_child(lp)
	root.add_child(l)
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
	l.queue_free()
	lp.queue_free()
	await process_frame

	# 4. MissionController smoke test (Contract 3 - Old Manor)
	gs.thief_id = "spider"
	gs.difficulty = 2
	gs.active_contract_order = 3
	# W0b: suite 85 reuses this mission instance for the mission_ready smoke.
	# Dictionary capture keeps the lambda's writes visible after the signal.
	var c4_ready: Dictionary = {"fired": false, "map": "", "stats": {}}
	var mission_scene: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	mission_scene.connect("mission_ready", func(map_id: String, stats: Dictionary) -> void:
		c4_ready["fired"] = true
		c4_ready["map"] = map_id
		c4_ready["stats"] = stats
	)
	root.add_child(mission_scene)
	var wait_frames: int = 0
	while (get_nodes_in_group("player").is_empty() or get_nodes_in_group("swinging_doors").is_empty()) and wait_frames < 240:
		await process_frame
		wait_frames += 1
	await process_frame
	var c4_ready_wait: int = 0
	while not bool(c4_ready["fired"]) and c4_ready_wait < 240:
		await process_frame
		c4_ready_wait += 1
	var guards := get_nodes_in_group("guards")
	var loots := get_nodes_in_group("loot")
	var om_doors := get_nodes_in_group("swinging_doors")
	var om_door_leaves := 0
	for d_var: Node in om_doors:
		var pivot_node: Node = d_var.get_node_or_null("DoorPivot")
		if pivot_node == null:
			continue
		for child: Node in pivot_node.get_children():
			if child is MeshInstance3D:
				om_door_leaves += 1
	if guards.size() < 4 or loots.size() < 5:
		printerr("FAIL: mission spawn counts too low: guards=", guards.size(), " loots=", loots.size())
		fails += 1
	elif om_doors.size() < 120 or om_door_leaves < 120:
		printerr("FAIL: Old Manor swinging doors too low: doors=", om_doors.size(), " leaves=", om_door_leaves)
		fails += 1
	else:
		print("PASS: Old Manor mission spawned ", guards.size(), " guards, ", loots.size(), " loot items and ", om_doors.size(), " doors / ", om_door_leaves, " leaves")
		# Real pivot-mesh doors (formerly 56 unresolved doorway hinges) must
		# swing: interact once and verify the 90-degree tween completes.
		var test_door: Node3D = om_doors[0] as Node3D
		var test_pivot: Node3D = test_door.get_node_or_null("DoorPivot") as Node3D
		if test_pivot != null:
			test_door.call("interact", null)
			# P2-6: was `await create_timer(0.55).timeout` (tween 0.5 s +
			# 50 ms margin — machine-speed dependent). Poll the tween to
			# completion with a generous frame cap instead (fail-closed).
			var swung: bool = false
			var swing_wait: int = 0
			while swing_wait < 300 and not swung:
				await process_frame
				swing_wait += 1
				swung = absf(absf(test_pivot.rotation.y) - PI * 0.5) < 0.02
			if not swung:
				printerr("FAIL: pivot-mesh door did not swing: rot=", test_pivot.rotation.y)
				fails += 1
			else:
				print("PASS: pivot-mesh door swings 90 degrees (rot=", snappedf(test_pivot.rotation.y, 0.001), ")")

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
	var den_wait: int = 0
	while get_nodes_in_group("interactables").size() < 2 and den_wait < 60:
		await process_frame
		den_wait += 1
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

	# 8. WardrobeUI, ContractTableUI, SettingsUI, LoadingScreen, ClueItem & VfxManager new helpers
	var wui_scr: GDScript = load("res://src/ui/wardrobe_ui.gd") as GDScript
	var cui_scr: GDScript = load("res://src/ui/contract_table_ui.gd") as GDScript
	var sui_scr: GDScript = load("res://src/ui/settings_ui.gd") as GDScript
	var lsc_scr: GDScript = load("res://src/ui/loading_screen.gd") as GDScript
	var clue_scr: GDScript = load("res://src/interact/clue_item.gd") as GDScript
	var vfx_scr: GDScript = load("res://src/core/vfx_manager.gd") as GDScript
	if wui_scr == null or cui_scr == null or sui_scr == null or lsc_scr == null or clue_scr == null or vfx_scr == null:
		printerr("FAIL: New scripts failed to load")
		fails += 1
	else:
		var wui: CanvasLayer = wui_scr.new()
		var cui: CanvasLayer = cui_scr.new()
		var sui: CanvasLayer = sui_scr.new()
		var lsc: CanvasLayer = lsc_scr.new()
		var clue: Area3D = clue_scr.new()
		root.add_child(wui)
		root.add_child(cui)
		root.add_child(sui)
		root.add_child(lsc)
		root.add_child(clue)
		await process_frame
		# W6U2: KF03/KF04 wardrobe is a true three-column panel with authored
		# loadout slots, signature padlocks and no APPLY button.
		var w8_slots: Array = wui.get("_slots") as Array
		var w8_three_col: bool = false
		for w8_c: Node in wui.find_children("*", "HBoxContainer", true, false):
			var w8_hb: HBoxContainer = w8_c as HBoxContainer
			if w8_hb.get_child_count() == 3 and w8_hb.get_child(0) is VBoxContainer \
					and w8_hb.get_child(1) is VBoxContainer and w8_hb.get_child(2) is PanelContainer:
				w8_three_col = true
				break
		var w8_apply: int = 0
		for w8_b: Node in wui.find_children("*", "Button", true, false):
			if (w8_b as Button).text.strip_edges().to_upper() == "APPLY":
				w8_apply += 1
		var w8_first: String = str(w8_slots[0]) if w8_slots.size() == 4 else ""
		var w8_ok: bool = w8_slots.size() == 4 and (w8_first == "zipwire" or w8_first == "glamour") \
			and str(w8_slots[3]) == "vistara_diamond" and w8_apply == 0 and w8_three_col
		if not w8_ok:
			printerr("FAIL: Wardrobe W6U2 layout slots=", w8_slots, " apply=", w8_apply, " three_col=", w8_three_col)
			fails += 1
		else:
			print("PASS: Wardrobe 3-column KF03/KF04 layout, authored slots, no APPLY")
		clue.interact(null)
		vfx_scr.spawn_lockpick_sparks(root, Vector3.ZERO)
		vfx_scr.spawn_blackjack_swing(root, Vector3.ZERO, Vector3.FORWARD)
		vfx_scr.spawn_window_godray(root, Vector3(0, 3, 0), Vector3.ZERO)
		if not clue.collected:
			printerr("FAIL: ClueItem interact failed")
			fails += 1
		else:
			print("PASS: WardrobeUI, ContractTableUI, SettingsUI, LoadingScreen, ClueItem & VfxManager verified")
		wui.queue_free()
		cui.queue_free()
		sui.queue_free()
		lsc.queue_free()
		clue.queue_free()
		await process_frame

	# 9. LedgerUI, MissionPrepUI, ArtNouveauTheme, SaveSystem progression & new VFX helpers
	var led_scr: GDScript = load("res://src/ui/ledger_ui.gd") as GDScript
	var prep_scr: GDScript = load("res://src/ui/mission_prep_ui.gd") as GDScript
	var ant_scr: GDScript = load("res://src/ui/art_nouveau_theme.gd") as GDScript
	var save_sys: Node = root.get_node_or_null("/root/SaveSystem")
	if led_scr == null or prep_scr == null or ant_scr == null or save_sys == null:
		printerr("FAIL: LedgerUI/MissionPrepUI/ArtNouveauTheme/SaveSystem missing")
		fails += 1
	else:
		var led: Control = led_scr.new()
		var prep: Control = prep_scr.new()
		root.add_child(led)
		root.add_child(prep)
		await process_frame
		vfx_scr.spawn_footprint_decal(Vector3.ZERO, Vector3.FORWARD, true)
		var wisp_host: Node3D = Node3D.new()
		root.add_child(wisp_host)
		var wisp: Node3D = vfx_scr.spawn_blue_wisp(wisp_host, Vector3.ZERO)
		vfx_scr.set_prop_highlight(wisp_host, true)
		vfx_scr.set_prop_highlight(wisp_host, false)
		var lvl_prog: Dictionary = save_sys.get_level_progress()
		var body_node: Node = prep.get("_thief_body_node") as Node
		var head_node: Node = prep.get("_thief_head_node") as Node
		var genuine_character_loaded: bool = body_node != null and head_node != null
		if wisp == null or int(lvl_prog.get("xp_needed", 0)) <= 0 or save_sys.get_currency() < 0 or not genuine_character_loaded:
			printerr("FAIL: Progression, BlueWisp or MissionPrepUI genuine character meshes invalid (body=", body_node != null, " head=", head_node != null, ")")
			fails += 1
		else:
			print("PASS: LedgerUI, MissionPrepUI, ArtNouveauTheme, SaveSystem progression & Footprint/Wisp VFX verified")
		led.queue_free()
		prep.queue_free()
		wisp_host.queue_free()
		await process_frame

	# 10. Guildhall full ground, landscape terrain & spawn grounding check
	gs.active_contract_order = 4
	# Regression: simulate a stale GameState default right before the mission
	# boots. The contract's map preset (guildhall) must win, not old_manor.
	gs.active_map_id = "old_manor"
	var gh_scene: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(gh_scene)
	var gh_env: Environment = null
	for gh_env_node: Node in gh_scene.get_children():
		if gh_env_node is WorldEnvironment and (gh_env_node as WorldEnvironment).environment != null:
			gh_env = (gh_env_node as WorldEnvironment).environment
			break
	var gh_fog_density: float = gh_env.fog_density if gh_env != null else -1.0
	# W5C: guildhall resolves to the authored `gloomy` preset (level dressing
	# evidence), and fog is scaled by FOG_DENSITY_SCALE (0.03, 20-120 m band).
	# Assert against the producer output + the constant, never the old literal.
	var gh_wp: GDScript = load("res://src/core/weather_profile.gd") as GDScript
	var gh_preset_name: String = str(gh_wp.preset_name_for_map("guildhall")) if gh_wp != null else ""
	var gh_preset: Dictionary = gh_wp.preset_for_map("guildhall") if gh_wp != null else {}
	var gh_exp_fog: float = float((gh_preset.get("fog", {}) as Dictionary).get("density", 0.0)) * float(gh_wp.FOG_DENSITY_SCALE) if gh_wp != null else -1.0
	if gh_preset_name != "gloomy" or gh_exp_fog <= 0.0 or absf(gh_fog_density - gh_exp_fog) >= 0.0002:
		printerr("FAIL: Guildhall must use its authored map weather preset, not the stale default (preset=", gh_preset_name, " fog_density=", gh_fog_density, " expected ", gh_exp_fog, " from that preset x FOG_DENSITY_SCALE; old_manor would be 0.012)")
		fails += 1
	else:
		print("PASS: Guildhall map preset wins over stale default map (preset=", gh_preset_name, " fog_density=", gh_fog_density, ")")
	var gh_wait: int = 0
	while get_nodes_in_group("guards").size() == 0 and gh_wait < 240:
		await process_frame
		gh_wait += 1
	await process_frame
	await physics_frame
	await physics_frame
	var gh_player: Node3D = gh_scene.get("player") as Node3D
	var gh_spawn_lights: int = 0
	var gh_spawn_light_desc: String = ""
	var gh_safe_light_ok: bool = false
	var gh_safe_light_aim: Vector3 = Vector3.ZERO
	var gh_safe_light_angle: float = 0.0
	if gh_player != null:
		for gh_n: Node in gh_scene.get_children():
			if gh_n is SpotLight3D or gh_n is OmniLight3D:
				if (gh_n as Node3D).global_position.distance_to(gh_player.global_position) < 20.0:
					gh_spawn_lights += 1
					if gh_spawn_light_desc == "":
						var gh_l: Light3D = gh_n as Light3D
						gh_spawn_light_desc = "%s pos=%s energy=%.2f" % [gh_l.get_class(), gh_l.global_position, gh_l.light_energy]
			if gh_n is SpotLight3D:
				var sl_cand: SpotLight3D = gh_n as SpotLight3D
				if sl_cand.global_position.distance_to(Vector3(126.2758, 27.1426, -2.4736)) < 1.0:
					gh_safe_light_aim = -sl_cand.global_transform.basis.z
					gh_safe_light_angle = sl_cand.spot_angle
					gh_safe_light_ok = (gh_safe_light_aim.z < -0.9) and (absf(gh_safe_light_aim.y) < 0.05) and is_equal_approx(gh_safe_light_angle, 88.0)
	var gh_ground_ok: bool = false
	var gh_gap_hit: Dictionary = {}
	var lc12_span_ok: bool = false
	var lc12_span_x: float = 0.0
	var lc12_span_z: float = 0.0
	var alley_land_y: float = -999.0
	var alley_ok: bool = false
	var overhang_land_y: float = -999.0
	var overhang_ok: bool = false
	var space: PhysicsDirectSpaceState3D = null
	if gh_player != null:
		space = gh_player.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(gh_player.global_position + Vector3(0, 0.5, 0), gh_player.global_position + Vector3(0, -4.0, 0))
		q.collision_mask = 1
		q.hit_back_faces = true
		if gh_player is CollisionObject3D:
			q.exclude = [(gh_player as CollisionObject3D).get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		gh_ground_ok = (not hit.is_empty()) and (hit["position"] as Vector3).y > 15.0
		var gap_q := PhysicsRayQueryParameters3D.create(Vector3(126.0, 30.0, -10.43), Vector3(126.0, 8.0, -10.43))
		gap_q.collision_mask = 1
		gap_q.hit_back_faces = true
		gh_gap_hit = space.intersect_ray(gap_q)
		var lc12_node: Node = gh_scene.get_node_or_null("LandscapeCollision_12")
		if lc12_node is StaticBody3D and lc12_node.get_child_count() > 0:
			var lc12_cs: CollisionShape3D = lc12_node.get_child(0) as CollisionShape3D
			if lc12_cs != null and lc12_cs.shape is ConcavePolygonShape3D:
				var lc12_faces: PackedVector3Array = (lc12_cs.shape as ConcavePolygonShape3D).get_faces()
				if not lc12_faces.is_empty():
					var min_x: float = lc12_faces[0].x
					var max_x: float = lc12_faces[0].x
					var min_z: float = lc12_faces[0].z
					var max_z: float = lc12_faces[0].z
					for fv: Vector3 in lc12_faces:
						min_x = minf(min_x, fv.x)
						max_x = maxf(max_x, fv.x)
						min_z = minf(min_z, fv.z)
						max_z = maxf(max_z, fv.z)
					lc12_span_x = max_x - min_x
					lc12_span_z = max_z - min_z
					lc12_span_ok = is_equal_approx(lc12_span_x, 63.0) and is_equal_approx(lc12_span_z, 63.0)
		var alley_y_top: float = 22.0
		for _astep: int in range(8):
			if alley_y_top <= 5.0:
				break
			var aq := PhysicsRayQueryParameters3D.create(Vector3(114.5, alley_y_top, -3.2), Vector3(114.5, 5.0, -3.2), 1)
			aq.hit_back_faces = true
			var ahit: Dictionary = space.intersect_ray(aq)
			if ahit.is_empty():
				break
			var ahit_pos: Vector3 = ahit["position"] as Vector3
			var acol: Variant = ahit.get("collider")
			if acol == lc12_node:
				alley_land_y = ahit_pos.y
				break
			alley_y_top = ahit_pos.y - 0.05
		alley_ok = absf(alley_land_y - 18.56) < 0.2
		var oh_y_top: float = 35.0
		for _ostep: int in range(8):
			if oh_y_top <= 5.0:
				break
			var oq := PhysicsRayQueryParameters3D.create(Vector3(126.0, oh_y_top, -10.43), Vector3(126.0, 5.0, -10.43), 1)
			oq.hit_back_faces = true
			var ohit: Dictionary = space.intersect_ray(oq)
			if ohit.is_empty():
				break
			var ohit_pos: Vector3 = ohit["position"] as Vector3
			var ocol: Variant = ohit.get("collider")
			if ocol == lc12_node:
				overhang_land_y = ohit_pos.y
				break
			oh_y_top = ohit_pos.y - 0.05
		overhang_ok = absf(overhang_land_y - 18.56) < 0.2
	if not gh_ground_ok or gh_gap_hit.is_empty() or gh_spawn_lights < 1 or not lc12_span_ok or not alley_ok or not overhang_ok or not gh_safe_light_ok or get_nodes_in_group("guards").size() == 0:
		printerr("FAIL: Guildhall ground/overhang/light check failed (ground=", gh_ground_ok, " gap_hit=", gh_gap_hit, " spawn_lights=", gh_spawn_lights, " lc12_span=(", lc12_span_x, ",", lc12_span_z, ") alley_land_y=", alley_land_y, " overhang_land_y=", overhang_land_y, " safe_light_ok=", gh_safe_light_ok, " safe_aim=", gh_safe_light_aim, " safe_angle=", gh_safe_light_angle, " pos=", gh_player.global_position if gh_player != null else Vector3.ZERO, " guards=", get_nodes_in_group("guards").size(), ")")
		fails += 1
	else:
		print("PASS: Guildhall terrain, floor collision & spawn ground raycast verified (gap_hit_y=", (gh_gap_hit["position"] as Vector3).y, ", lc12_span=(", lc12_span_x, ",", lc12_span_z, "), alley_y=", alley_land_y, ", overhang_y=", overhang_land_y, ", spawn_lights=", gh_spawn_lights, ", safe_aim=", gh_safe_light_aim, ", safe_angle=", gh_safe_light_angle, ", light=", gh_spawn_light_desc, ")")

	# 11. Perf chunking: 32m MultiMesh chunks, split collision bodies, occluders
	var gh_stats_v: Variant = gh_scene.get("level_stats")
	var gh_stats: Dictionary = {}
	if gh_stats_v is Dictionary:
		gh_stats = gh_stats_v
	var chunk_count: int = int(gh_stats.get("chunk_count", 0))
	var col_bodies: int = int(gh_stats.get("collision_bodies", 0))
	var col_shapes: int = int(gh_stats.get("collision_shapes", 0))
	var occluders: int = int(gh_stats.get("occluder_count", 0))
	var gh_fallback_materials: int = int(gh_stats.get("fallback_material_count", -1))
	# PG-1: with the pre-baked 1024px imports the Guildhall load must not
	# decode-and-resize any texture at runtime (downscaled=0). A non-zero
	# count means a fresh extraction lost the .import caps.
	var gh_downscaled: int = int(gh_stats.get("downscaled_count", -1))
	var gh_downscaled_tex: Array = (gh_stats.get("downscaled_textures", []) as Array)
	# Steady state is downscaled=0. One documented exception is allowed while
	# a fresh extraction's .import caps are still pre-bake-pending: the road
	# normal is the only new cap from `prebake_texture_cap.py --dry-run` and
	# its sidecar still says size_limit=0. Once the pre-bake is applied, a
	# runtime downscale of that same texture fails this gate.
	var gh_downscaled_pending: Array[String] = []
	var gh_downscaled_ok: bool = gh_downscaled == 0
	if not gh_downscaled_ok and gh_downscaled == 1 and not gh_downscaled_tex.is_empty():
		var gh_ds_path: String = str(gh_downscaled_tex[0])
		if gh_ds_path.ends_with("Stone/FloorExterior/T_RoadBricksA_N.png"):
			var gh_ds_import: String = FileAccess.get_file_as_string(gh_ds_path + ".import")
			if gh_ds_import.contains("process/size_limit=0"):
				gh_downscaled_ok = true
				gh_downscaled_pending.append(gh_ds_path)
	var multi_nodes: int = 0
	var max_chunk_span: float = 0.0
	var max_chunk_mesh: String = ""
	var culled_nodes: int = 0
	for n: Node in gh_scene.get_children():
		if n is MultiMeshInstance3D:
			multi_nodes += 1
			var mmi: MultiMeshInstance3D = n as MultiMeshInstance3D
			if mmi.multimesh != null:
				var span: float = mmi.multimesh.custom_aabb.size.length()
				var is_decorative: bool = bool(mmi.get_meta("decorative", false))
				if not is_decorative and span > max_chunk_span:
					max_chunk_span = span
					max_chunk_mesh = str(mmi.get_meta("ue_mesh", ""))
			if mmi.visibility_range_end > 0.0:
				culled_nodes += 1
	if chunk_count < 500 or multi_nodes < 200 or col_bodies < 4 or col_shapes <= 0 or col_shapes >= 32000 or occluders <= 0 or max_chunk_span >= 140.0 or culled_nodes < 300 or gh_fallback_materials != 0 or not gh_downscaled_ok:
		printerr("FAIL: perf chunking invariants (chunks=", chunk_count, " multimeshes=", multi_nodes, " bodies=", col_bodies, " shapes=", col_shapes, " occluders=", occluders, " max_span=", max_chunk_span, " max_mesh=", max_chunk_mesh, " culled=", culled_nodes, " material_fallbacks=", gh_fallback_materials, " downscaled=", gh_downscaled, " downscaled_tex=", gh_downscaled_tex.slice(0, 5), ")")
		fails += 1
	else:
		print("PASS: Perf chunking (chunks=", chunk_count, ", multimeshes=", multi_nodes, ", collision_bodies=", col_bodies, ", shapes=", col_shapes, ", occluders=", occluders, ", max_chunk_span=", snappedf(max_chunk_span, 0.1), "m, distance-culled=", culled_nodes, ", material_fallbacks=0, downscaled=", gh_downscaled, ", prebake_pending=", gh_downscaled_pending, ")")

	# 11b. W1p structural census: source_sublevel provenance on every draw item
	# and the PERF_CENSUS counters the perf harness consumes. Headless only.
	var gh_census: Dictionary = gh_stats.get("perf_census", {}) as Dictionary
	var gh_src_totals: Dictionary = gh_census.get("source_sublevels", {}) as Dictionary
	var gh_census_ok: bool = int(gh_census.get("meshes", 0)) > 0 \
		and int(gh_census.get("surface_draws", 0)) > 0 \
		and int(gh_census.get("lights", 0)) > 0 \
		and int(gh_census.get("collision_shapes", 0)) > 0 \
		and int(gh_census.get("periph_nodes", 0)) > 0 \
		and int(gh_census.get("hero_shadows", -1)) == 6 \
		and int(gh_census.get("light_budget", -1)) == 160 \
		and int(gh_src_totals.get("Guildhall_PeripheryA", 0)) > 0
	var gh_draw_nodes: int = 0
	var gh_draw_src_missing: int = 0
	var gh_draw_periph: int = 0
	var gh_missing_names: Array[String] = []
	for gh_n: Node in gh_scene.get_children():
		if not (gh_n is MeshInstance3D or gh_n is MultiMeshInstance3D):
			continue
		var gh_ue: String = str(gh_n.get_meta("ue_mesh", ""))
		if gh_ue == "" or gh_ue.begins_with("MERGED_CELL_"):
			continue
		gh_draw_nodes += 1
		if not gh_n.has_meta("source_sublevel") or str(gh_n.get_meta("source_sublevel", "")) == "":
			gh_draw_src_missing += 1
			if gh_missing_names.size() < 5:
				gh_missing_names.append("%s/%s" % [gh_n.name, gh_ue])
		elif str(gh_n.get_meta("source_sublevel", "")).to_lower().find("peripherya") >= 0:
			gh_draw_periph += 1
	if not gh_census_ok or gh_draw_nodes < 3000 or gh_draw_src_missing != 0 or gh_draw_periph == 0:
		printerr("FAIL: 11b W1p census/source metadata (census_ok=", gh_census_ok, " draw_nodes=", gh_draw_nodes, " missing_source=", gh_draw_src_missing, " missing_names=", gh_missing_names, " periph=", gh_draw_periph, " census=", gh_census, ")")
		fails += 1
	else:
		print("PASS: 11b W1p PERF_CENSUS (meshes=", int(gh_census.get("meshes", 0)), ", surface_draws=", int(gh_census.get("surface_draws", 0)), ", lights=", int(gh_census.get("lights", 0)), ", shadows=", int(gh_census.get("shadow_lights", 0)), ", periph_nodes=", int(gh_census.get("periph_nodes", 0)), ", source-tagged draw nodes=", gh_draw_nodes, " missing=", gh_draw_src_missing, ")")
	gh_scene.queue_free()
	await process_frame

	# 12. Skybox/periphery decorative sublevels never generate physics
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	var ll: Node = ll_scr.new()
	root.add_child(ll)
	var dec_sky: bool = bool(ll.call("_is_decorative_sublevel", "res://data/generated/levels/Guildhall/Guildhall_SkyboxGeo.tatlevel.json"))
	var dec_per: bool = bool(ll.call("_is_decorative_sublevel", "res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json"))
	var dec_geo: bool = bool(ll.call("_is_decorative_sublevel", "res://data/generated/levels/Guildhall/Guildhall_Geometry.tatlevel.json"))
	if not dec_sky or dec_per or dec_geo:
		printerr("FAIL: decorative sublevel classification skybox=", dec_sky, " periphery=", dec_per, " geometry=", dec_geo)
		fails += 1
	else:
		print("PASS: Skybox excluded from physics; packed-city PeripheryA is collidable")
	ll.queue_free()
	await process_frame

	# 13. HUD F3 perf overlay + cached prop-highlight mesh list
	var hud_scr: GDScript = load("res://src/ui/hud.gd") as GDScript
	var test_hud: CanvasLayer = hud_scr.new() as CanvasLayer
	root.add_child(test_hud)
	await process_frame
	var overlay_hidden_ok: bool = not bool(test_hud.call("is_fps_overlay_visible"))
	test_hud.call("toggle_fps_overlay")
	await process_frame
	var overlay_lbl: Label = test_hud.get("fps_overlay") as Label
	var overlay_shown_ok: bool = bool(test_hud.call("is_fps_overlay_visible")) and overlay_lbl != null and overlay_lbl.visible and overlay_lbl.text.find("FPS") >= 0
	var hl_host: Node3D = Node3D.new()
	var hl_mesh: MeshInstance3D = MeshInstance3D.new()
	hl_mesh.mesh = BoxMesh.new()
	hl_host.add_child(hl_mesh)
	root.add_child(hl_host)
	vfx_scr.set_prop_highlight(hl_host, true)
	var hl_cached: bool = hl_host.has_meta("_vfx_hl_meshes") and hl_mesh.material_overlay != null
	vfx_scr.set_prop_highlight(hl_host, false)
	var hl_cleared: bool = not hl_host.has_meta("_vfx_hl_meshes") and hl_mesh.material_overlay == null
	# Regression: a cached highlight mesh can be freed before the highlight is
	# cleared (interactables rebuild their visuals) and must not cast-error.
	vfx_scr.set_prop_highlight(hl_host, true)
	hl_mesh.queue_free()
	await process_frame
	vfx_scr.set_prop_highlight(hl_host, false)
	if not overlay_hidden_ok or not overlay_shown_ok or not hl_cached or not hl_cleared:
		printerr("FAIL: HUD F3 overlay / VFX highlight cache (hidden=", overlay_hidden_ok, " shown=", overlay_shown_ok, " cached=", hl_cached, " cleared=", hl_cleared, ")")
		fails += 1
	else:
		print("PASS: HUD F3 perf overlay toggle & cached prop highlight verified")
	test_hud.queue_free()
	hl_host.queue_free()
	await process_frame

	# 14. LightProbe sampling throttle (12.5 Hz + squared-distance early-out)
	var lp2: Node = (load("res://src/stealth/light_probe.gd") as GDScript).new()
	root.add_child(lp2)
	var l2 := OmniLight3D.new()
	l2.position = Vector3(1, 1, 0)
	l2.omni_range = 8.0
	l2.light_energy = 2.0
	root.add_child(l2)
	lp2.register_light(l2)
	var space2: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	var v1: float = float(lp2.call("sample_visibility", Vector3.ZERO, space2, [] as Array[RID]))
	l2.visible = false
	var v2: float = float(lp2.call("sample_visibility", Vector3.ZERO, space2, [] as Array[RID]))
	var computes_after_2: int = int(lp2.call("sample_compute_count"))
	# P2-6: was `await create_timer(0.15).timeout` (150 ms wait vs the 80 ms
	# throttle window — 70 ms margin, flakes on slow CI). Poll until the
	# throttle window expires and a recompute lands, with a frame cap
	# (fail-closed: a cap hit keeps computes_after_2 == 1 and fails below).
	var v3: float = v1
	var probe_wait: int = 0
	while int(lp2.call("sample_compute_count")) <= computes_after_2 and probe_wait < 240:
		await process_frame
		probe_wait += 1
		v3 = float(lp2.call("sample_visibility", Vector3.ZERO, space2, [] as Array[RID]))
	if v1 <= 0.1 or not is_equal_approx(v1, v2) or computes_after_2 != 1 or v3 >= v1:
		printerr("FAIL: LightProbe throttle v1=", v1, " v2=", v2, " v3=", v3, " computes=", computes_after_2)
		fails += 1
	else:
		print("PASS: LightProbe sampling throttle (cached <=80ms, recomputed after)")
	lp2.queue_free()
	l2.queue_free()
	await process_frame

	# 15. Moth astral projection 8s TTL start/expiry
	gs.thief_id = "moth"
	gs.difficulty = 2
	var moth: CharacterBody3D = (load("res://src/player/thief_character.gd") as GDScript).new() as CharacterBody3D
	moth.set_physics_process(false)
	root.add_child(moth)
	await process_frame
	moth.call("_trigger_thief_ability")
	var astral_started: bool = bool(moth.get("astral_active")) and float(moth.get("astral_ttl")) > 7.9
	moth.set("astral_ttl", 0.01)
	moth.call("_tick_astral", 0.02)
	var astral_ended: bool = not bool(moth.get("astral_active")) and not bool(moth.get("thief_vision_on"))
	if not astral_started or not astral_ended:
		printerr("FAIL: Moth astral TTL (started=", astral_started, " ended=", astral_ended, ")")
		fails += 1
	else:
		print("PASS: Moth astral projection 8s TTL start/expiry verified")
	moth.queue_free()
	gs.thief_id = "spider"
	await process_frame

	# 16. Mobile quality profile + touch UI layout/input plumbing
	var mp_scr: GDScript = load("res://src/core/mobile_profile.gd") as GDScript
	mp_scr.set_force_mobile(true)
	var mobile_on: bool = bool(mp_scr.is_mobile())
	var lights_balanced: int = int(mp_scr.max_lights())
	var shadows_balanced: int = int(mp_scr.hero_shadows())
	var lod_balanced: float = float(mp_scr.lod_bias())
	mp_scr.set_tier(0, save_sys)
	var lights_perf: int = int(mp_scr.max_lights())
	mp_scr.set_tier(1, save_sys)
	var touch_scr: GDScript = load("res://src/ui/mobile_touch_ui.gd") as GDScript
	var touch_ui: CanvasLayer = touch_scr.new() as CanvasLayer
	root.add_child(touch_ui)
	await process_frame
	await process_frame
	var touch_buttons: int = int(touch_ui.call("get_button_count"))
	var interact_center: Vector2 = touch_ui.call("get_button_center", "interact")
	var hit_id: String = str(touch_ui.call("_hit_button", interact_center))
	touch_ui.call("clear_input")
	var touch_ok: bool = mobile_on and lights_balanced == 24 and shadows_balanced == 2 and is_equal_approx(lod_balanced, 2.0) and lights_perf == 12 and touch_buttons >= 13 and hit_id == "interact"
	if not touch_ok:
		printerr("FAIL: mobile profile/touch UI (mobile=", mobile_on, " lights=", lights_balanced, " shadows=", shadows_balanced, " lod=", lod_balanced, " perf_lights=", lights_perf, " buttons=", touch_buttons, " hit=", hit_id, ")")
		fails += 1
	else:
		print("PASS: Mobile profile (24 lights/2 shadows/LOD 2.0, Performance=12) & ", touch_buttons, "-button touch UI verified")
	touch_ui.queue_free()
	mp_scr.set_force_mobile(false)
	mp_scr.set_tier(1, save_sys)
	await process_frame

	# 17. Real TAT weather: DenseFog preset drives Environment/DirectionalLight3D
	var wp_scr: GDScript = load("res://src/core/weather_profile.gd") as GDScript
	if wp_scr == null:
		printerr("FAIL: weather_profile.gd failed to load")
		fails += 1
	else:
		var wfile: FileAccess = FileAccess.open("res://data/generated/weather/dense_fog.json", FileAccess.READ)
		if wfile == null:
			printerr("FAIL: dense_fog.json weather preset missing")
			fails += 1
		else:
			var wpreset: Variant = JSON.parse_string(wfile.get_as_text())
			var wok := wpreset is Dictionary and str(wpreset.get("preset", "")) == "dense_fog" and str(wpreset.get("source", "")).ends_with("BP_WeatherPreset_DenseFog.json")
			var wmap_ok := str(wp_scr.preset_name_for_map("old_manor")) == "dense_fog_old_manor" and str(wp_scr.preset_name_for_map("thieves_den")) == "midnight_clear_thieves_den" and str(wp_scr.preset_name_for_map("jaspering_hall")) == "heavy_rain" and str(wp_scr.preset_name_for_map("main_menu")) == "midnight_clear_mission_lobby" and str(wp_scr.preset_name_for_map("guildhall")) == "gloomy" and str(wp_scr.preset_name_for_map("no_such_map")) == ""
			var wenv := Environment.new()
			var wmoon := DirectionalLight3D.new()
			var applied: bool = bool(wp_scr.apply_environment(wenv, wmoon, wpreset))
			var fog_src: Dictionary = wpreset.get("fog", {})
			var ml_src: Dictionary = wpreset.get("moon_light", {})
			var pp_src: Dictionary = wpreset.get("postprocess", {})
			var sky_src: Dictionary = wpreset.get("sky", {})
			var exp_fog := float(fog_src.get("density", 0.0)) * float(wp_scr.FOG_DENSITY_SCALE)
			var exp_haze: Color = wp_scr.fog_haze_color(wpreset)
			var exp_haze_lum: float = 0.2126 * exp_haze.r + 0.7152 * exp_haze.g + 0.0722 * exp_haze.b
			var exp_energy: float = clampf(float(ml_src.get("intensity", 0.0)) * 10.0, 0.05, 1.0)
			var exp_basis: Basis = wp_scr.moon_basis(wpreset)
			var wb: Basis = wmoon.basis
			var basis_ok: bool = absf(wb.x.length() - 1.0) < 1e-4 \
				and absf(wb.y.length() - 1.0) < 1e-4 \
				and absf(wb.z.length() - 1.0) < 1e-4 \
				and absf(wb.x.dot(wb.y)) < 1e-4 \
				and absf(wb.x.dot(wb.z)) < 1e-4 \
				and absf(wb.y.dot(wb.z)) < 1e-4
			var exp_mc: Array = ml_src.get("color", [1, 1, 1])
			var exp_skyc: Array = sky_src.get("light_color", [1, 1, 1])
			var exp_gain: Array = pp_src.get("gain_midtones", [1.0, 1.0, 1.0])
			var exp_bri := float(exp_gain[0])
			var wvals_ok := applied \
				and is_equal_approx(wenv.fog_density, exp_fog) \
				and is_equal_approx(wmoon.light_energy, exp_energy) \
				and wmoon.basis.is_equal_approx(exp_basis) \
				and basis_ok \
				and is_equal_approx(wmoon.light_color.r, float(exp_mc[0])) \
				and is_equal_approx(wmoon.light_color.g, float(exp_mc[1])) \
				and is_equal_approx(wmoon.light_color.b, float(exp_mc[2])) \
				and is_equal_approx(wenv.fog_light_color.r, exp_haze.r) \
				and is_equal_approx(wenv.fog_light_color.g, exp_haze.g) \
				and is_equal_approx(wenv.fog_light_color.b, exp_haze.b) \
				and exp_haze_lum >= float(wp_scr.FOG_HAZE_LUMA_FLOOR) - 1e-4 \
				and is_equal_approx(wenv.fog_sky_affect, float(wp_scr.FOG_SKY_AFFECT_FLOOR)) \
				and is_equal_approx(wenv.ambient_light_color.r, float(exp_skyc[0])) \
				and is_equal_approx(wenv.ambient_light_energy, float(wp_scr.ambient_energy(wpreset))) \
				and is_equal_approx(wenv.adjustment_saturation, float(pp_src.get("saturation", 1.0))) \
				and wenv.adjustment_brightness > 0.0 \
				and is_equal_approx(wenv.adjustment_brightness, exp_bri) \
				and is_equal_approx(wenv.glow_intensity, clampf(float(pp_src.get("bloom_intensity", 0.0)) * float(wp_scr.BLOOM_TO_GLOW), 0.0, 0.8)) \
				and bool(wp_scr.enable_rain(wpreset)) \
				and is_equal_approx(float(wp_scr.rain_intensity(wpreset)), float(wpreset.get("rain", {}).get("intensity", 0.0)))
			var wden_ok := true
			var wden_file: FileAccess = FileAccess.open("res://data/generated/weather/midnight_clear_thieves_den.json", FileAccess.READ)
			if wden_file == null:
				printerr("FAIL: midnight_clear_thieves_den.json weather preset missing")
				wden_ok = false
			else:
				var wden_preset: Variant = JSON.parse_string(wden_file.get_as_text())
				var wden_pp: Dictionary = (wden_preset as Dictionary).get("postprocess", {})
				var wden_gain: Array = wden_pp.get("gain_midtones", [1.0, 1.0, 1.0])
				var wden_env := Environment.new()
				var wden_moon := DirectionalLight3D.new()
				wden_ok = bool(wp_scr.apply_environment(wden_env, wden_moon, wden_preset)) \
					and wden_env.adjustment_brightness > 0.0 \
					and is_equal_approx(wden_env.adjustment_brightness, float(wden_gain[0])) \
					and is_equal_approx(wden_env.adjustment_saturation, float(wden_pp.get("saturation", 1.0)))
				if not wden_ok:
					printerr("FAIL: thieves-den brightness regression (brightness=", wden_env.adjustment_brightness, " expected=", float(wden_gain[0]), ")")
				wden_moon.free()
			var wenv2 := Environment.new()
			var wmoon2 := DirectionalLight3D.new()
			var map_applied: bool = bool(wp_scr.apply_for_map(wenv2, wmoon2, "old_manor"))
			var wenv3 := Environment.new()
			var wmoon3 := DirectionalLight3D.new()
			var b_fog := wenv3.fog_density
			var b_energy := wmoon3.light_energy
			var b_rot := wmoon3.rotation_degrees
			var missing_applied: bool = bool(wp_scr.apply_for_map(wenv3, wmoon3, "no_such_map"))
			var empty_applied: bool = bool(wp_scr.apply_environment(wenv3, wmoon3, {}))
			var untouched_ok := is_equal_approx(wenv3.fog_density, b_fog) and is_equal_approx(wmoon3.light_energy, b_energy) and wmoon3.rotation_degrees.is_equal_approx(b_rot)
			var wmap_apply_ok := map_applied and not missing_applied and not empty_applied and untouched_ok
			if not wok or not wmap_ok or not wvals_ok or not wmap_apply_ok or not wden_ok:
				printerr("FAIL: weather preset apply (file=", wok, " map=", wmap_ok, " values=", wvals_ok, " den_bri=", wden_ok, " apply=", wmap_apply_ok, " fog=", wenv.fog_density, " energy=", wmoon.light_energy, " rot=", wmoon.rotation_degrees, ")")
				fails += 1
			else:
				print("PASS: Real weather DenseFog applied (fog=", snappedf(wenv.fog_density, 0.0001), " moon_energy=", snappedf(wmoon.light_energy, 0.01), " rot=", wmoon.rotation_degrees, ")")
			wmoon.free()
			wmoon2.free()
			wmoon3.free()

	# 17b. W5C weather mapping + near-field fog + horizon haze + sky cloud tint.
	# Guildhall_P authors no PresetOverrides, so the hub's weather comes from
	# the authored level dressing (puddles, 27 named local fog volumes, cloud
	# masks, moon cards) -> gloomy. The fog scale is calibrated for 20-120 m
	# and the sky now carries a horizon haze term instead of a black horizon.
	var w5_gh_wp: GDScript = load("res://src/core/weather_profile.gd") as GDScript
	var w5_gh_wv: GDScript = load("res://src/core/weather_visuals.gd") as GDScript
	var w5_gh_preset: Dictionary = w5_gh_wp.preset_for_map("guildhall") if w5_gh_wp != null else {}
	var w5_gh_name: String = str(w5_gh_preset.get("preset", ""))
	var w5_gh_rain: Dictionary = w5_gh_preset.get("rain", {})
	var w5_gh_fog_sec: Dictionary = w5_gh_preset.get("fog", {})
	var w5_gh_map_file: FileAccess = FileAccess.open("res://data/generated/weather/map_weather.json", FileAccess.READ)
	var w5_gh_evidence: Dictionary = {}
	if w5_gh_map_file != null:
		var gh_map_v: Variant = JSON.parse_string(w5_gh_map_file.get_as_text())
		if gh_map_v is Dictionary:
			var gh_maps: Dictionary = (gh_map_v as Dictionary).get("maps", {})
			w5_gh_evidence = (gh_maps.get("guildhall", {}) as Dictionary).get("authored_evidence", {})
	var w5_gh_map_ok: bool = w5_gh_name == "gloomy" \
		and bool(w5_gh_rain.get("enabled", false)) \
		and is_equal_approx(float(w5_gh_rain.get("intensity", 0.0)), 1.0) \
		and is_equal_approx(float(w5_gh_rain.get("ground_wetness", 0.0)), 1.0) \
		and is_equal_approx(float(w5_gh_fog_sec.get("density", 0.0)), 0.16) \
		and int(w5_gh_evidence.get("wet_ground", 0)) > 0 \
		and int(w5_gh_evidence.get("haze_volumes", 0)) > 0 \
		and int(w5_gh_evidence.get("cloud_masks", 0)) > 0 \
		and int(w5_gh_evidence.get("moon_actors", 0)) > 0
	if not w5_gh_map_ok:
		printerr("FAIL: W5C Guildhall weather mapping (preset=", w5_gh_name, " rain=", w5_gh_rain, " fog=", w5_gh_fog_sec.get("density", null), " evidence=", w5_gh_evidence, ")")
		fails += 1
	else:
		print("PASS: W5C Guildhall weather = authored gloomy (rain=", w5_gh_rain.get("intensity", 0.0), " wet=", w5_gh_rain.get("ground_wetness", 0.0), " fog=", w5_gh_fog_sec.get("density", 0.0), " evidence=", w5_gh_evidence, ")")

	var w5_gh_density: float = float(w5_gh_wp.fog_density(w5_gh_preset)) * float(w5_gh_wp.FOG_DENSITY_SCALE) if w5_gh_wp != null else -1.0
	var w5_t20: float = exp(-w5_gh_density * 20.0)
	var w5_t30: float = exp(-w5_gh_density * 30.0)
	var w5_t120: float = exp(-w5_gh_density * 120.0)
	var w5_near_ok: bool = w5_gh_density > 0.0 and w5_t30 < 0.93 and w5_t30 > 0.80 and w5_t120 < 0.70 and w5_t120 > 0.45 and w5_t20 > w5_t30 and w5_t30 > w5_t120
	if not w5_near_ok:
		printerr("FAIL: W5C near-field fog (density=", w5_gh_density, " w5_t20=", w5_t20, " w5_t30=", w5_t30, " w5_t120=", w5_t120, " expected ~13% at 30 m and ~44% at 120 m)")
		fails += 1
	else:
		print("PASS: W5C near-field fog calibrated (density=", snappedf(w5_gh_density, 0.0001), " transmittance 20/30/120 m=", snappedf(w5_t20, 0.01), "/", snappedf(w5_t30, 0.01), "/", snappedf(w5_t120, 0.01), ")")

	var w5_hz_moon := DirectionalLight3D.new()
	var w5_hz_sky: Sky = w5_gh_wv.make_sky(w5_gh_preset, w5_hz_moon) if w5_gh_wv != null else null
	var w5_hz_sm: ShaderMaterial = w5_hz_sky.sky_material as ShaderMaterial if w5_hz_sky != null else null
	var w5_hz_strength: float = float(w5_hz_sm.get_shader_parameter("horizon_haze")) if w5_hz_sm != null and w5_hz_sm.get_shader_parameter("horizon_haze") != null else -1.0
	var w5_hz_col_v: Variant = w5_hz_sm.get_shader_parameter("horizon_haze_color") if w5_hz_sm != null else null
	var w5_hz_lum: float = -1.0
	if w5_hz_col_v is Vector3:
		var hzc: Vector3 = w5_hz_col_v
		w5_hz_lum = 0.2126 * hzc.x + 0.7152 * hzc.y + 0.0722 * hzc.z
	var w5_den_sky_preset: Dictionary = w5_gh_wp.load_preset("midnight_clear_thieves_den") if w5_gh_wp != null else {}
	var w5_den_sky: Sky = w5_gh_wv.make_sky(w5_den_sky_preset, w5_hz_moon) if w5_gh_wv != null else null
	var w5_den_sm: ShaderMaterial = w5_den_sky.sky_material as ShaderMaterial if w5_den_sky != null else null
	var w5_den_hz: float = float(w5_den_sm.get_shader_parameter("horizon_haze")) if w5_den_sm != null and w5_den_sm.get_shader_parameter("horizon_haze") != null else -1.0
	var w5_haze_ok: bool = is_equal_approx(w5_hz_strength, float(w5_gh_wv.OUTDOOR_HORIZON_HAZE)) and w5_hz_lum > 0.05 and w5_hz_lum < 0.30 and w5_den_hz == 0.0
	if not w5_haze_ok:
		printerr("FAIL: W5C horizon haze floor (outdoor=", w5_hz_strength, " lum=", w5_hz_lum, " den=", w5_den_hz, " expected outdoor ", w5_gh_wv.OUTDOOR_HORIZON_HAZE, " and den 0)")
		fails += 1
	else:
		print("PASS: W5C horizon haze floor (outdoor=", w5_hz_strength, " lum=", snappedf(w5_hz_lum, 0.001), " den=0, exposure untouched)")
	w5_hz_moon.free()

	var w5_sky_src: String = ""
	var w5_sky_file: FileAccess = FileAccess.open("res://src/core/tat_sky.gdshader", FileAccess.READ)
	if w5_sky_file != null:
		w5_sky_src = w5_sky_file.get_as_text()
	var w5_tint_uses: int = w5_sky_src.count("cloud_tint")
	var w5_tint_ok: bool = w5_tint_uses >= 3 \
		and w5_sky_src.find("vec3 cloud_tint") >= 0 \
		and w5_sky_src.find("mix(col, cloud_color") < 0 \
		and w5_sky_src.find("lit_cloud") < 0 \
		and w5_sky_src.find("cloud_alpha = coverage * cloud_opacity") >= 0 \
		and w5_sky_src.find("uniform float horizon_haze") >= 0 \
		and w5_sky_src.find("horizon_haze_color") >= 0 \
		and w5_sky_src.find("smoothstep(lo, hi, n)") >= 0
	if not w5_tint_ok:
		printerr("FAIL: W5C sky cloud-tint invariants (cloud_tint uses=", w5_tint_uses, " raw_cloud_mix=", w5_sky_src.find("mix(col, cloud_color") >= 0, " lit_cloud=", w5_sky_src.find("lit_cloud") >= 0, " coverage_opacity=", w5_sky_src.find("cloud_alpha = coverage * cloud_opacity") >= 0, ")")
		fails += 1
	else:
		print("PASS: W5C sky shader one moonlit cloud tint + coverage/opacity split (cloud_tint uses=", w5_tint_uses, ")")

	# 17c. W5C Den staging: the parsed window list selects the framed window on
	# the authored telescope axis; the south-wall WindowBorder hatch does not.
	var w5_mc_scr: Script = load("res://src/missions/mission_controller.gd") as Script
	var w5_den_facing: Vector3 = Vector3.ZERO
	var w5_den_pick: Dictionary = {}
	var w5_den_miss: Dictionary = {}
	var w5_den_east: Dictionary = {}
	var w5_den_anchor_v: Variant = null
	var w5_den_sil: Color = Color(0, 0, 0)
	var w5_den_pick_anchor: Vector3 = Vector3.ZERO
	if w5_mc_scr != null:
		var w5_facing_v: Variant = w5_mc_scr.call("den_telescope_facing")
		if w5_facing_v is Vector3:
			w5_den_facing = w5_facing_v
		var w5_den_eye: Vector3 = Vector3(-4.82, 41.8, 270.73)
		var w5_den_west: Vector3 = Vector3(-6.06, 43.05, 271.4)
		var w5_den_hatch: Vector3 = Vector3(5.2374, 40.6471, 266.6629)
		w5_den_pick = w5_mc_scr.call("select_den_window_anchor", w5_den_eye, [w5_den_west, w5_den_hatch], w5_den_facing)
		w5_den_miss = w5_mc_scr.call("select_den_window_anchor", w5_den_eye, [w5_den_hatch], w5_den_facing)
		w5_den_east = w5_mc_scr.call("select_den_window_anchor", w5_den_eye, [w5_den_hatch], -w5_den_facing)
		var w5_den_consts: Dictionary = w5_mc_scr.get_script_constant_map()
		w5_den_anchor_v = w5_den_consts.get("DEN_WEST_WINDOW_ANCHOR", null)
		var w5_sil_v: Variant = w5_mc_scr.call("den_vista_silhouette_color", Color(0.1277, 0.7238, 1.0))
		if w5_sil_v is Color:
			w5_den_sil = w5_sil_v
		var w5_pick_anchor_v: Variant = w5_den_pick.get("anchor", null)
		if w5_pick_anchor_v is Vector3:
			w5_den_pick_anchor = w5_pick_anchor_v
	var w5_den_anchor: Vector3 = Vector3.ZERO
	if w5_den_anchor_v is Vector3:
		w5_den_anchor = w5_den_anchor_v
	var w5_den_sil_lum: float = 0.2126 * w5_den_sil.r + 0.7152 * w5_den_sil.g + 0.0722 * w5_den_sil.b
	var w5_den_win_ok: bool = w5_den_facing.is_equal_approx(Vector3(-0.848048, 0.0, 0.529919)) \
		and int(w5_den_pick.size()) > 0 \
		and str(w5_den_pick.get("source", "")) == "window_positions" \
		and w5_den_pick_anchor.is_equal_approx(Vector3(-6.06, 43.05, 271.4)) \
		and w5_den_miss.is_empty() \
		and int(w5_den_east.size()) > 0 \
		and w5_den_anchor.x < -5.5 and w5_den_anchor.y > 40.0 and w5_den_anchor.z > 270.0 and w5_den_anchor.z < 273.0 \
		and w5_den_sil_lum > 0.03 and w5_den_sil_lum < 0.09
	if not w5_den_win_ok:
		printerr("FAIL: W5C Den window anchor (facing=", w5_den_facing, " picked=", w5_den_pick, " hatch_miss=", w5_den_miss.is_empty(), " east=", w5_den_east.size(), " west_anchor=", w5_den_anchor, " sil_lum=", w5_den_sil_lum, ")")
		fails += 1
	else:
		print("PASS: W5C Den window staging anchors the west framed window (facing=", w5_den_facing, " source=", w5_den_pick.get("source", ""), " anchor=", w5_den_anchor, " sil_lum=", snappedf(w5_den_sil_lum, 0.001), ")")

	# 18. Swinging-door extraction: every pivot resolves to a real leaf mesh.
	# The 111 doorway-BP pivots carry their leaf StaticMesh on the pivot
	# template itself (not a separate level SMC stub); this guards both that
	# fallback and the identity local transform it implies.
	var door_json_stack: Array[String] = ["res://data/generated/levels"]
	var door_json_paths: Array[String] = []
	while not door_json_stack.is_empty():
		var cur_dir: String = door_json_stack.pop_back()
		var da := DirAccess.open(cur_dir)
		if da == null:
			continue
		da.list_dir_begin()
		var entry: String = da.get_next()
		while entry != "":
			var full_path: String = cur_dir.path_join(entry)
			if da.current_is_dir():
				door_json_stack.append(full_path)
			elif entry.ends_with(".tatlevel.json"):
				door_json_paths.append(full_path)
			entry = da.get_next()
		da.list_dir_end()
	var door_total: int = 0
	var leaf_total: int = 0
	var unresolved_total: int = 0
	var pivot_mesh_leaves: int = 0
	var leaf_bad: int = 0
	for jp: String in door_json_paths:
		var jf := FileAccess.open(jp, FileAccess.READ)
		if jf == null:
			continue
		var parsed: Variant = JSON.parse_string(jf.get_as_text())
		if not (parsed is Dictionary):
			continue
		var lv: Dictionary = parsed
		unresolved_total += (lv.get("swinging_doors_unresolved", []) as Array).size()
		for dv: Variant in (lv.get("swinging_doors", []) as Array):
			if not (dv is Dictionary):
				continue
			var dd: Dictionary = dv
			var leaves: Array = dd.get("leaves", [])
			door_total += 1
			leaf_total += leaves.size()
			if leaves.is_empty():
				leaf_bad += 1
			for lv2: Variant in leaves:
				if not (lv2 is Dictionary):
					continue
				var ldict: Dictionary = lv2
				if str(ldict.get("mesh", "")) == "" or str(ldict.get("res", "")) == "":
					leaf_bad += 1
				if str(ldict.get("leaf_source", "")) == "pivot_static_mesh":
					pivot_mesh_leaves += 1
					var leaf_pos: Array = ldict.get("rel_pos", [])
					var leaf_basis: Array = ldict.get("rel_basis", [])
					var identity_ok: bool = leaf_pos.size() == 3 and leaf_basis.size() == 9
					if identity_ok:
						identity_ok = absf(float(leaf_pos[0])) < 1e-6 and absf(float(leaf_pos[1])) < 1e-6 and absf(float(leaf_pos[2])) < 1e-6
						identity_ok = identity_ok and absf(float(leaf_basis[0]) - 1.0) < 1e-6 and absf(float(leaf_basis[4]) - 1.0) < 1e-6 and absf(float(leaf_basis[8]) - 1.0) < 1e-6
					if not identity_ok:
						leaf_bad += 1
	if door_json_paths.size() < 70 or door_total < 281 or leaf_total < 373 or unresolved_total != 0 or pivot_mesh_leaves < 111 or leaf_bad != 0:
		printerr("FAIL: swinging-door extraction (files=", door_json_paths.size(), " doors=", door_total, " leaves=", leaf_total, " unresolved=", unresolved_total, " pivot_mesh_leaves=", pivot_mesh_leaves, " bad=", leaf_bad, ")")
		fails += 1
	else:
		print("PASS: swinging-door extraction (", door_json_paths.size(), " levels, ", door_total, " doors, ", leaf_total, " leaves, ", pivot_mesh_leaves, " pivot meshes, 0 unresolved)")

	# 19. Packed Level Actor instance expansion: PeripheryA is the city ring
	# with the Guildhall safe-room buildings. Its BPP class templates carry
	# 30k+ PerInstanceSMData transforms; collapsing them to the actor root is
	# the black-void / floating-fragment regression.
	var pa_file := FileAccess.open("res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json", FileAccess.READ)
	var pa_meshes: Array = []
	var pa_dict: Dictionary = {}
	if pa_file != null:
		var pa_parsed: Variant = JSON.parse_string(pa_file.get_as_text())
		if pa_parsed is Dictionary:
			pa_dict = pa_parsed
			pa_meshes = pa_dict.get("meshes", [])
	var pa_spawn := Vector3(127.2747, 25.4694, -5.3296)
	var pa_near_spawn: int = 0
	for pa_m: Variant in pa_meshes:
		if not (pa_m is Dictionary):
			continue
		var pa_pos: Array = (pa_m as Dictionary).get("pos", [])
		if pa_pos.size() >= 3:
			var pa_v := Vector3(float(pa_pos[0]), float(pa_pos[1]), float(pa_pos[2]))
			if pa_v.distance_to(pa_spawn) < 25.0:
				pa_near_spawn += 1
	if pa_meshes.size() < 10000 or pa_near_spawn < 200:
		printerr("FAIL: packed Level Actor instances not expanded (PeripheryA meshes=", pa_meshes.size(), " near_spawn=", pa_near_spawn, ")")
		fails += 1
	else:
		print("PASS: packed Level Actor instances expanded (PeripheryA meshes=", pa_meshes.size(), ", ", pa_near_spawn, " around safe-room spawn)")

	# 20. LevelInstance sublevels: PeripheryA places Facade_Apartment_CarUnderpass
	# at its authored transform. These sublevels are not in the AlwaysLoaded
	# list, so the parser must merge them explicitly.
	var li_instances: Array = []
	var li_car_near: int = 0
	var li_car_pos := Vector3(-67.1, 17.6, 61.9)
	if not pa_dict.is_empty():
		li_instances = pa_dict.get("level_instances", [])
		for li_m: Variant in (pa_dict.get("meshes", []) as Array):
			if not (li_m is Dictionary):
				continue
			var li_pos: Array = (li_m as Dictionary).get("pos", [])
			if li_pos.size() >= 3:
				var li_v := Vector3(float(li_pos[0]), float(li_pos[1]), float(li_pos[2]))
				if li_v.distance_to(li_car_pos) < 30.0:
					li_car_near += 1
	var li_has_car: bool = false
	for li_s: Variant in li_instances:
		if str(li_s).find("Facade_Apartment_CarUnderpass") >= 0:
			li_has_car = true
	if not li_has_car or li_car_near < 100:
		printerr("FAIL: LevelInstance sublevels not merged (car_underpass=", li_has_car, " near_meshes=", li_car_near, ")")
		fails += 1
	else:
		print("PASS: LevelInstance sublevels merged (", li_instances.size(), " instances, ", li_car_near, " car-underpass meshes near authored transform)")

	# 21. Guildhall visibility-hole semantics: UE stores 1 = hole. The shader
	# must discard authored holes (discard_holes=1) so the 27 m elevated shell
	# no longer renders as a solid ceiling over the lower street. Components
	# without a visibility mask fail safe to vis=0 and stay visible.
	var ghl_file := FileAccess.open("res://data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json", FileAccess.READ)
	var ghl_lc: Dictionary = {}
	if ghl_file != null:
		var ghl_parsed: Variant = JSON.parse_string(ghl_file.get_as_text())
		if ghl_parsed is Dictionary:
			var ghl_lands: Array = (ghl_parsed as Dictionary).get("landscapes", [])
			for ghl_var: Variant in ghl_lands:
				if ghl_var is Dictionary and str((ghl_var as Dictionary).get("weightmap", "")) != "":
					ghl_lc = ghl_var
					break
	var ll3: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ll3)
	var ghl_mat: ShaderMaterial = null
	if not ghl_lc.is_empty():
		ghl_mat = ll3.call("_landscape_weighted_material", ghl_lc) as ShaderMaterial
	var discard_val: Variant = ghl_mat.get_shader_parameter("discard_holes") if ghl_mat != null else null
	if ghl_mat == null or discard_val == null or not is_equal_approx(float(discard_val), 1.0):
		printerr("FAIL: Guildhall visibility-hole discard missing (mat=", ghl_mat != null, " discard=", discard_val, ")")
		fails += 1
	else:
		print("PASS: Guildhall landscape discards authored visibility holes (discard_holes=1, UE 1=hole)")
	ll3.queue_free()
	await process_frame

	# 22. Sky/moon fidelity: inherited preset fields, geometry-derived moon
	# diameter, overall_color-multiplied gradient and UE->Godot moon light
	# directions.
	var wv_scr: GDScript = load("res://src/core/weather_visuals.gd") as GDScript
	var mc_file: FileAccess = FileAccess.open("res://data/generated/weather/midnight_clear.json", FileAccess.READ)
	var mc_preset: Dictionary = {}
	if mc_file != null:
		var mc_parsed: Variant = JSON.parse_string(mc_file.get_as_text())
		if mc_parsed is Dictionary:
			mc_preset = mc_parsed
	var mc_moon_raw: Variant = mc_preset.get("moon", null)
	var mc_moon: Dictionary = mc_moon_raw if mc_moon_raw is Dictionary else {}
	var mc_sky_raw: Variant = mc_preset.get("sky", null)
	var mc_sky: Dictionary = mc_sky_raw if mc_sky_raw is Dictionary else {}
	# A pre-fix parser emits `horizon_color: null`; keep this Variant-guarded so
	# the regression reports FAIL instead of raising on a typed Array assignment.
	var mc_horizon_raw: Variant = mc_sky.get("horizon_color", null)
	var mc_horizon: Array = mc_horizon_raw if mc_horizon_raw is Array else []
	var mc_visible: bool = mc_moon.get("visible") == true
	var mc_size: float = float(mc_moon.get("size", 0.0))
	var mc_cloud: float = float(mc_sky.get("cloud_opacity", 0.0))
	var mc_hdr: bool = mc_horizon.size() >= 3 and float(mc_horizon[0]) > 1.5
	var mc_horizon_desc: String = "missing/null" if mc_horizon.is_empty() else str(mc_horizon)
	if not mc_visible or not is_equal_approx(mc_size, 9.838636) or not is_equal_approx(mc_cloud, 3.299213) or not mc_hdr:
		printerr("FAIL: midnight_clear inherited fields (moon.visible=", mc_moon.get("visible"), " moon.size=", mc_size, " cloud_opacity=", mc_cloud, " horizon=", mc_horizon_desc, " expected horizon_r>1.5)")
		fails += 1
	else:
		print("PASS: midnight_clear inherited fields (moon.visible=true, moon.size=", mc_size, ", cloud_opacity=", mc_cloud, ", horizon_r=", float(mc_horizon[0]), ")")

	var diam_a: float = -1.0
	var diam_b: float = -1.0
	if wv_scr != null:
		diam_a = float(wv_scr.moon_diameter_deg(9.838636, 0.0))
		diam_b = float(wv_scr.moon_diameter_deg(14.0, 6000.0))
	if wv_scr == null or absf(diam_a - 8.2718) >= 0.001 or absf(diam_b - 11.7329) >= 0.001:
		printerr("FAIL: moon angular diameter (size=9.838636 offset=0 -> ", diam_a, " expected 8.2718; size=14 offset=6000 -> ", diam_b, " expected 11.7329)")
		fails += 1
	else:
		print("PASS: moon angular diameter geometry (", snappedf(diam_a, 0.0001), " deg, ", snappedf(diam_b, 0.0001), " deg)")

	# midnight_clear: authored horizon [1.9796, 2.5866, 3.0] * overall_color
	# 0.001 = (0.0019796, 0.0025866, 0.003). The authored multiplier is kept,
	# so the night gradient stays legitimately dark instead of tone-mapped up.
	var mc_hc: Color = Color(-1.0, -1.0, -1.0)
	if wv_scr != null:
		mc_hc = wv_scr.horizon_color_of(mc_preset)
	var hc_ok: bool = absf(mc_hc.r - 0.00198) < 0.0005 and absf(mc_hc.g - 0.00259) < 0.0005 and absf(mc_hc.b - 0.003) < 0.0005
	if wv_scr == null or not hc_ok:
		printerr("FAIL: overall_color-multiplied horizon color (got ", mc_hc, " expected (0.00198, 0.00259, 0.003))")
		fails += 1
	else:
		print("PASS: overall_color-multiplied horizon (", mc_hc, ")")

	# midnight_clear: authored zenith [0.003, 0.0096, 0.026] * overall_color
	# 0.001 = (3e-06, 9.6e-06, 2.6e-05). Pins the multiplier on the zenith path
	# so a change that stops multiplying zenith fails.
	var mc_zc: Color = Color(-1.0, -1.0, -1.0)
	if wv_scr != null:
		mc_zc = wv_scr.zenith_color_of(mc_preset)
	var zc_ok: bool = absf(mc_zc.r - 3e-6) < 1e-6 and absf(mc_zc.g - 9.6e-6) < 1e-6 and absf(mc_zc.b - 2.6e-5) < 1e-6
	if wv_scr == null or not zc_ok:
		printerr("FAIL: overall_color-multiplied zenith color (got ", mc_zc, " expected (3e-06, 9.6e-06, 2.6e-05))")
		fails += 1
	else:
		print("PASS: overall_color-multiplied zenith (%.7f, %.7f, %.7f)" % [mc_zc.r, mc_zc.g, mc_zc.b])

	# The moon disc's authored emissive tint must win over `moon.color` (the
	# authored Sun / Moon Color sky term; the directional light colour is
	# moon_light.color); midnight_clear emissive = [0.5137, 0.5216, 1.0].
	var mdc_raw: Variant = null
	if wp_scr != null:
		mdc_raw = wp_scr.moon_disc_color(mc_preset)
	var mdc: Color = mdc_raw if mdc_raw is Color else Color(-1.0, -1.0, -1.0)
	var mdc_ok: bool = absf(mdc.r - 0.5137) < 0.001 and absf(mdc.g - 0.5216) < 0.001 and absf(mdc.b - 1.0) < 0.001
	if wp_scr == null or not mdc_ok:
		printerr("FAIL: moon disc colour prefers authored emissive (got ", mdc, " expected (0.5137, 0.5216, 1.0))")
		fails += 1
	else:
		print("PASS: moon disc colour prefers authored emissive (", mdc, ")")

	var df_file: FileAccess = FileAccess.open("res://data/generated/weather/dense_fog.json", FileAccess.READ)
	var df_preset: Dictionary = {}
	if df_file != null:
		var df_parsed: Variant = JSON.parse_string(df_file.get_as_text())
		if df_parsed is Dictionary:
			df_preset = df_parsed
	var df_env := Environment.new()
	var df_moon := DirectionalLight3D.new()
	var df_applied: bool = false
	if wp_scr != null:
		df_applied = bool(wp_scr.apply_environment(df_env, df_moon, df_preset))
	# NOTE: dense_fog's pitch of -90 is the degenerate case where the raw-Euler
	# and rotator-conversion paths agree, so this only proves the sky direction
	# is anti-parallel to the light. The discriminating rotator test is the
	# midnight_clear_thieves_den assertion below.
	var df_down: Vector3 = df_moon.basis * Vector3(0.0, 0.0, -1.0)
	var df_up: Vector3 = df_moon.basis * Vector3(0.0, 0.0, 1.0)
	var df_ok: bool = df_applied \
		and absf(df_down.x) < 0.001 \
		and absf(df_down.y + 1.0) < 0.001 \
		and absf(df_down.z) < 0.001 \
		and absf(df_up.x) < 0.001 \
		and absf(df_up.y - 1.0) < 0.001 \
		and absf(df_up.z) < 0.001
	if not df_ok:
		printerr("FAIL: DenseFog moon light (degenerate pitch -90) points straight down (applied=", df_applied, " down=", df_down, " expected (0, -1, 0), sky_dir=", df_up, " expected (0, 1, 0))")
		fails += 1
	else:
		print("PASS: DenseFog moon light (degenerate pitch -90) points straight down (down=", df_down, ", sky=", df_up, ")")

	# Godot's fog_sky_affect defaults to 1.0, which fully replaces the sky at
	# infinite depth. UE height fog does not occlude the sky sphere, so
	# apply_environment pins a calibrated haze floor for outdoor presets (the
	# horizon must read hazy, not black) and 0.0 for the indoor Den, whose sky
	# is a window pane.
	var fsa_ok: bool = df_applied \
		and is_equal_approx(df_env.fog_sky_affect, float(wp_scr.FOG_SKY_AFFECT_FLOOR)) \
		and is_equal_approx(df_env.volumetric_fog_sky_affect, float(wp_scr.VOLUMETRIC_FOG_SKY_AFFECT_FLOOR)) \
		and df_env.fog_sky_affect > 0.0
	if not fsa_ok:
		printerr("FAIL: DenseFog apply_environment fog_sky_affect (applied=", df_applied, " got=", df_env.fog_sky_affect, " volumetric=", df_env.volumetric_fog_sky_affect, " expected outdoor floors ", wp_scr.FOG_SKY_AFFECT_FLOOR, "/", wp_scr.VOLUMETRIC_FOG_SKY_AFFECT_FLOOR, ")")
		fails += 1
	else:
		print("PASS: DenseFog apply_environment outdoor haze floors (fog_sky_affect=", df_env.fog_sky_affect, " volumetric=", df_env.volumetric_fog_sky_affect, ")")
	df_moon.free()

	var den_file: FileAccess = FileAccess.open("res://data/generated/weather/midnight_clear_thieves_den.json", FileAccess.READ)
	var den_preset: Dictionary = {}
	if den_file != null:
		var den_parsed: Variant = JSON.parse_string(den_file.get_as_text())
		if den_parsed is Dictionary:
			den_preset = den_parsed
	var den_env := Environment.new()
	var den_moon := DirectionalLight3D.new()
	var den_applied: bool = false
	if wp_scr != null:
		den_applied = bool(wp_scr.apply_environment(den_env, den_moon, den_preset))
	var den_aim: Vector3 = den_moon.basis * Vector3(0.0, 0.0, -1.0)
	var den_expected: Vector3 = Vector3(0.777677, -0.587785, -0.222995)
	var den_ok: bool = den_applied \
		and absf(den_aim.x - den_expected.x) < 0.001 \
		and absf(den_aim.y - den_expected.y) < 0.001 \
		and absf(den_aim.z - den_expected.z) < 0.001 \
		and den_env.fog_sky_affect == 0.0 \
		and den_env.volumetric_fog_sky_affect == 0.0
	if not den_ok:
		printerr("FAIL: ThievesDen moon light direction (applied=", den_applied, " actual=", den_aim, " expected=", den_expected, ")")
		fails += 1
	else:
		print("PASS: ThievesDen moon light direction (actual=", den_aim, ")")
	den_moon.free()

	# 23. Light intensity and attenuation fidelity: authored intensities map
	# through one linear scale (median 15.0 -> energy 1.0) so authored ratios
	# survive, instead of the old two-branch clamp pinning most lights to 1.0
	# or 4.2. Radii stay authored metres and attenuation is Godot's 1.0.
	# The loader helpers are private, so they are invoked through an instance
	# with call(), as block 21 does for _landscape_weighted_material.
	var lux_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	var lux_ll: Node = lux_scr.new()
	root.add_child(lux_ll)
	var lux_i15: Dictionary = {"type": "SpotLightComponent", "intensity": 15.0, "radius": 9.0, "outer_cone": 50.0}
	var lux_i45: Dictionary = {"type": "SpotLightComponent", "intensity": 45.0, "radius": 9.0, "outer_cone": 50.0}
	var lux_i2500: Dictionary = {"type": "SpotLightComponent", "intensity": 2500.0, "radius": 9.0, "outer_cone": 50.0}
	var lux_i199: Dictionary = {"type": "SpotLightComponent", "intensity": 19.9, "radius": 9.0, "outer_cone": 50.0}
	var lux_i200: Dictionary = {"type": "SpotLightComponent", "intensity": 20.0, "radius": 9.0, "outer_cone": 50.0}
	var lux_iwall: Dictionary = {"type": "SpotLightComponent", "intensity": 5.0, "radius": 9.0, "outer_cone": 88.0}
	var lux_iwall2: Dictionary = {"type": "SpotLightComponent", "intensity": 5.0, "radius": 12.0, "outer_cone": 88.0}
	var lux_iomni: Dictionary = {"type": "PointLightComponent", "intensity": 15.0, "radius": 4.5}
	var lux_ifloor: Dictionary = {"type": "PointLightComponent", "intensity": 0.01, "radius": 5.0}
	var lux_l15: Light3D = lux_ll.call("_build_light", lux_i15) as Light3D
	var lux_l45: Light3D = lux_ll.call("_build_light", lux_i45) as Light3D
	var lux_l2500: Light3D = lux_ll.call("_build_light", lux_i2500) as Light3D
	var lux_l199: Light3D = lux_ll.call("_build_light", lux_i199) as Light3D
	var lux_l200: Light3D = lux_ll.call("_build_light", lux_i200) as Light3D
	var lux_lwall: Light3D = lux_ll.call("_build_light", lux_iwall) as Light3D
	var lux_lwall2: Light3D = lux_ll.call("_build_light", lux_iwall2) as Light3D
	var lux_lomni: Light3D = lux_ll.call("_build_light", lux_iomni) as Light3D
	var lux_lfloor: Light3D = lux_ll.call("_build_light", lux_ifloor) as Light3D
	var lux_e15: float = lux_l15.light_energy if lux_l15 != null else -1.0
	var lux_e45: float = lux_l45.light_energy if lux_l45 != null else -1.0
	var lux_e2500: float = lux_l2500.light_energy if lux_l2500 != null else -1.0
	var lux_e199: float = lux_l199.light_energy if lux_l199 != null else -1.0
	var lux_e200: float = lux_l200.light_energy if lux_l200 != null else -1.0
	var lux_ratio: float = lux_e45 / lux_e15 if absf(lux_e15) > 0.000001 else 0.0
	# The sqrt/tanh mapping is intentionally compressive above the median:
	# 45 lumens keeps a >1 ratio (hierarchy survives) but no longer reads as
	# the old linear 3.0 because the shoulder starts before the 95th percentile.
	if lux_l15 == null or lux_l45 == null or lux_ratio <= 1.0 or lux_ratio >= 3.0 or is_equal_approx(lux_e15, lux_e45):
		printerr("FAIL: authored light ratio 15:45 (e15=", lux_e15, " e45=", lux_e45, " ratio=", lux_ratio, " expected 1<ratio<3 and distinct)")
		fails += 1
	else:
		print("PASS: authored light ratio preserved with compression (e15=", lux_e15, ", e45=", lux_e45, ", ratio=", lux_ratio, ")")

	# Monotonic across the whole authored range: 15 < 20 < 45 < 2500.
	# The mapping has no branch, so 19.9 vs 20.0 stays continuous (<1%).
	var lux_monotonic: bool = lux_l15 != null and lux_l45 != null and lux_l200 != null and lux_l2500 != null \
		and lux_e15 < lux_e200 and lux_e200 < lux_e45 and lux_e45 < lux_e2500
	var lux_distinct: bool = absf(lux_e45 - 4.2) > 0.0001 \
		and absf(lux_e45 - 1.0) > 0.0001 \
		and absf(lux_e2500 - 4.0) > 0.0001
	var lux_anchor_ok: bool = lux_l15 != null and absf(lux_e15 - 1.0) < 0.001
	var lux_no_collapse: bool = lux_monotonic and lux_distinct and lux_anchor_ok \
		and lux_l199 != null and lux_l200 != null \
		and absf(lux_e200 - lux_e199) / lux_e200 < 0.01
	if not lux_no_collapse:
		printerr("FAIL: light energy collapse or 20.0 branch jump (e15=", lux_e15, " e20=", lux_e200, " e45=", lux_e45, " e2500=", lux_e2500, " e19.9=", lux_e199, " e20.0=", lux_e200, " monotonic=", lux_monotonic, " distinct=", lux_distinct, " anchor=", lux_anchor_ok, ")")
		fails += 1
	else:
		print("PASS: monotonic light energy, no collapse or 20.0 branch jump (e15=", lux_e15, ", e20=", lux_e200, ", e45=", lux_e45, ", e2500=", lux_e2500, ", e19.9=", lux_e199, ")")

	# Smooth compression replaces the hard 4.0 ceiling: the 2500-lumen
	# security spot stays below 4.0 but remains well above the median.
	var lux_ceil_ok: bool = lux_l2500 != null and lux_e2500 > 3.0 and lux_e2500 < 4.0
	if not lux_ceil_ok:
		printerr("FAIL: light energy shoulder for authored 2500 (got ", lux_e2500, " expected 3.0..4.0)")
		fails += 1
	else:
		print("PASS: light energy shoulder compresses authored 2500 -> ", lux_e2500, " (no hard clamp)")

	# The compressive low end lifts the 0.01 floor instead of pinning it to
	# a constant; the floor remains a bounded, non-zero minimum.
	var lux_efloor: float = lux_lfloor.light_energy if lux_lfloor != null else -1.0
	var lux_floor_ok: bool = lux_lfloor != null and lux_efloor >= 0.01 and lux_efloor <= 0.05
	if not lux_floor_ok:
		printerr("FAIL: light energy floor for authored 0.01 (got ", lux_efloor, " expected 0.01..0.05)")
		fails += 1
	else:
		print("PASS: bounded light energy floor (authored 0.01 -> ", lux_efloor, ")")

	var lux_range: float = -1.0
	var lux_att: float = -1.0
	if lux_lwall is SpotLight3D:
		var lux_spot: SpotLight3D = lux_lwall as SpotLight3D
		lux_range = lux_spot.spot_range
		lux_att = lux_spot.spot_attenuation
	var lux_range2: float = -1.0
	if lux_lwall2 is SpotLight3D:
		lux_range2 = (lux_lwall2 as SpotLight3D).spot_range
	var lux_radius_ok: bool = lux_lwall != null and absf(lux_range - 9.0) <= 0.01 \
		and absf(lux_range2 - 12.0) <= 0.01 \
		and is_equal_approx(lux_att, 1.0)
	if not lux_radius_ok:
		printerr("FAIL: Guildhall wall spot radius/attenuation (range=", lux_range, " expected 9.0, range2=", lux_range2, " expected 12.0, attenuation=", lux_att, " expected 1.0)")
		fails += 1
	else:
		print("PASS: authored radius kept 1:1 (spot_range=", lux_range, ", spot_range2=", lux_range2, ", attenuation=", lux_att, ")")

	# PointLightComponent takes the OmniLight3D branch; authored 15.0 is the
	# median anchor (energy 1.0) and 4.5 m must stay 4.5 m.
	var lux_omni_energy: float = -1.0
	var lux_omni_range: float = -1.0
	if lux_lomni is OmniLight3D:
		lux_omni_energy = lux_lomni.light_energy
		lux_omni_range = (lux_lomni as OmniLight3D).omni_range
	var lux_omni_ok: bool = lux_lomni is OmniLight3D \
		and absf(lux_omni_energy - 1.0) < 0.001 \
		and absf(lux_omni_range - 4.5) <= 0.01
	if not lux_omni_ok:
		printerr("FAIL: PointLightComponent omni energy/range (energy=", lux_omni_energy, " expected 1.0, range=", lux_omni_range, " expected 4.5)")
		fails += 1
	else:
		print("PASS: PointLightComponent maps to OmniLight3D (energy=", lux_omni_energy, ", range=", lux_omni_range, ")")

	var lux_rects: Array = [{"intensity": 15.0, "radius": 4.0, "color": [255.0, 215.0, 150.0], "width": 200.0, "height": 100.0}]
	var lux_parent := Node3D.new()
	root.add_child(lux_parent)
	var lux_ctx: Dictionary = {}
	lux_ll.call("_build_rect_lights", lux_rects, lux_parent, null, lux_ctx, 4)
	var lux_rect_light: OmniLight3D = null
	for lux_child: Node in lux_parent.get_children():
		if lux_child is OmniLight3D:
			lux_rect_light = lux_child as OmniLight3D
			break
	var lux_rect_expected: float = clampf(15.0 * (1.0 / 15.0), 0.01, 4.0)
	var lux_rect_ok: bool = lux_rect_light != null \
		and is_equal_approx(lux_rect_light.light_energy, lux_rect_expected) \
		and is_equal_approx(lux_rect_light.omni_range, 4.0) \
		and is_equal_approx(lux_rect_light.omni_attenuation, 1.0) \
		and int(lux_ctx.get("rect_light_count", 0)) == 1
	if not lux_rect_ok:
		var lux_rect_got: float = lux_rect_light.light_energy if lux_rect_light != null else -1.0
		printerr("FAIL: rect light energy scale (got ", lux_rect_got, " expected ", lux_rect_expected, ", count=", lux_ctx.get("rect_light_count", 0), ")")
		fails += 1
	else:
		print("PASS: rect light uses the same energy scale (energy=", lux_rect_light.light_energy, ", range=", lux_rect_light.omni_range, ")")

	for lux_node: Light3D in [lux_l15, lux_l45, lux_l2500, lux_l199, lux_l200, lux_lwall, lux_lwall2, lux_lomni, lux_lfloor]:
		if lux_node != null:
			lux_node.free()
	lux_parent.queue_free()
	lux_ll.queue_free()
	await process_frame

	# 24. Landscape second weightmap and fifth colour slot: the parser emits
	# `weightmaps` per component. Index 6 allocates CobbleB/RockTileA to
	# weightmap 1 channels 1/2 after Visibility stops consuming a colour slot,
	# and the bound weightmap_1 must be that component's authored second
	# weightmap file. Index 10 keeps Visibility on weightmap 1; index 1 has a
	# single weightmap, so weightmap_1 must stay unbound while its real colour
	# slots are bound (channel_2 == 3) and slots 3/4 stay at -1.
	var lw2_file := FileAccess.open("res://data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json", FileAccess.READ)
	var lw2_lands: Array = []
	if lw2_file != null:
		var lw2_parsed: Variant = JSON.parse_string(lw2_file.get_as_text())
		if lw2_parsed is Dictionary:
			lw2_lands = (lw2_parsed as Dictionary).get("landscapes", [])
	var lw2_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(lw2_ll)

	var lw2_mat6: ShaderMaterial = null
	if lw2_lands.size() > 6 and lw2_lands[6] is Dictionary:
		lw2_mat6 = lw2_ll.call("_landscape_weighted_material", lw2_lands[6]) as ShaderMaterial
	var lw2_6_tex_idx: int = -1
	var lw2_6_channel: int = -1
	var lw2_6_puddle_idx: int = -1
	var lw2_6_puddle_ch: int = -1
	var lw2_6_wm1: Variant = null
	var lw2_6_idx3: int = -1
	var lw2_6_ch3: int = -1
	if lw2_mat6 != null:
		lw2_6_tex_idx = int(lw2_mat6.get_shader_parameter("layer_tex_idx_4"))
		lw2_6_channel = int(lw2_mat6.get_shader_parameter("layer_channel_4"))
		lw2_6_puddle_idx = int(lw2_mat6.get_shader_parameter("puddle_tex_idx"))
		lw2_6_puddle_ch = int(lw2_mat6.get_shader_parameter("puddle_channel"))
		lw2_6_wm1 = lw2_mat6.get_shader_parameter("weightmap_1")
		lw2_6_idx3 = int(lw2_mat6.get_shader_parameter("layer_tex_idx_3"))
		lw2_6_ch3 = int(lw2_mat6.get_shader_parameter("layer_channel_3"))
	# Which texture is bound, not merely that something is: weightmap_1 must be
	# the component's authored second weightmap (CobbleB/RockTileA live there).
	var lw2_6_wm1_path: String = ""
	if lw2_6_wm1 is Texture2D:
		lw2_6_wm1_path = (lw2_6_wm1 as Texture2D).resource_path
	var lw2_6_expected_wm1: String = ""
	if lw2_lands.size() > 6 and lw2_lands[6] is Dictionary:
		var lw2_6_wms: Variant = (lw2_lands[6] as Dictionary).get("weightmaps", [])
		if lw2_6_wms is Array and (lw2_6_wms as Array).size() > 1:
			lw2_6_expected_wm1 = str((lw2_6_wms as Array)[1])
	var lw2_ok6: bool = lw2_mat6 != null \
		and lw2_6_tex_idx == 1 \
		and lw2_6_channel == 2 \
		and lw2_6_puddle_idx == 1 \
		and lw2_6_puddle_ch == 0 \
		and lw2_6_idx3 == 1 \
		and lw2_6_ch3 == 1 \
		and lw2_6_wm1_path != "" \
		and lw2_6_wm1_path == lw2_6_expected_wm1
	if not lw2_ok6:
		printerr("FAIL: landscape second weightmap slot 4 (mat=", lw2_mat6 != null, " tex_idx_4=", lw2_6_tex_idx, " expected 1, channel_4=", lw2_6_channel, " expected 2, tex_idx_3=", lw2_6_idx3, " expected 1, channel_3=", lw2_6_ch3, " expected 1, puddle_tex_idx=", lw2_6_puddle_idx, " expected 1, puddle_channel=", lw2_6_puddle_ch, " expected 0, weightmap_1='", lw2_6_wm1_path, "' expected '", lw2_6_expected_wm1, "')")
		fails += 1
	else:
		print("PASS: Guildhall landscape second weightmap slot 4 (RockTileA tex_idx=", lw2_6_tex_idx, ", channel=", lw2_6_channel, ", CobbleB tex_idx=", lw2_6_idx3, ", channel=", lw2_6_ch3, ", puddle tex_idx=", lw2_6_puddle_idx, ", puddle channel=", lw2_6_puddle_ch, ", weightmap_1=", lw2_6_wm1_path, ")")

	var lw2_mat10: ShaderMaterial = null
	if lw2_lands.size() > 10 and lw2_lands[10] is Dictionary:
		lw2_mat10 = lw2_ll.call("_landscape_weighted_material", lw2_lands[10]) as ShaderMaterial
	var lw2_10_vis_idx: int = -1
	var lw2_10_vis_ch: int = -1
	var lw2_10_puddle_idx: int = -1
	var lw2_10_puddle_ch: int = -1
	if lw2_mat10 != null:
		lw2_10_vis_idx = int(lw2_mat10.get_shader_parameter("visibility_tex_idx"))
		lw2_10_vis_ch = int(lw2_mat10.get_shader_parameter("visibility_channel"))
		lw2_10_puddle_idx = int(lw2_mat10.get_shader_parameter("puddle_tex_idx"))
		lw2_10_puddle_ch = int(lw2_mat10.get_shader_parameter("puddle_channel"))
	var lw2_ok10: bool = lw2_mat10 != null \
		and lw2_10_vis_idx == 1 \
		and lw2_10_vis_ch == 0 \
		and lw2_10_puddle_idx == 0 \
		and lw2_10_puddle_ch == 3
	if not lw2_ok10:
		printerr("FAIL: landscape visibility on second weightmap (mat=", lw2_mat10 != null, " visibility_tex_idx=", lw2_10_vis_idx, " expected 1, visibility_channel=", lw2_10_vis_ch, " expected 0, puddle_tex_idx=", lw2_10_puddle_idx, " expected 0, puddle_channel=", lw2_10_puddle_ch, " expected 3)")
		fails += 1
	else:
		print("PASS: Guildhall landscape visibility on second weightmap (visibility tex_idx=", lw2_10_vis_idx, ", channel=", lw2_10_vis_ch, ", puddle tex_idx=", lw2_10_puddle_idx, ", puddle channel=", lw2_10_puddle_ch, ")")

	var lw2_mat1: ShaderMaterial = null
	if lw2_lands.size() > 1 and lw2_lands[1] is Dictionary:
		lw2_mat1 = lw2_ll.call("_landscape_weighted_material", lw2_lands[1]) as ShaderMaterial
	var lw2_1_wm1: Variant = lw2_mat1.get_shader_parameter("weightmap_1") if lw2_mat1 != null else null
	var lw2_1_idx_ok: bool = lw2_mat1 != null
	var lw2_1_idx_desc: String = ""
	var lw2_1_ch2: int = -1
	var lw2_1_ch3: int = 0
	var lw2_1_ch4: int = 0
	if lw2_mat1 != null:
		for lw2_slot: int in range(5):
			var lw2_idx_raw: Variant = lw2_mat1.get_shader_parameter("layer_tex_idx_%d" % lw2_slot)
			var lw2_idx: int = 0 if lw2_idx_raw == null else int(lw2_idx_raw)
			if lw2_idx != 0:
				lw2_1_idx_ok = false
			lw2_1_idx_desc += str(lw2_idx)
		# An unset parameter means the shader uniform keeps its default, so
		# null maps to the uniform's -1 ("no layer in this slot").
		lw2_1_ch2 = int(lw2_mat1.get_shader_parameter("layer_channel_2"))
		var lw2_1_ch3_raw: Variant = lw2_mat1.get_shader_parameter("layer_channel_3")
		var lw2_1_ch4_raw: Variant = lw2_mat1.get_shader_parameter("layer_channel_4")
		lw2_1_ch3 = -1 if lw2_1_ch3_raw == null else int(lw2_1_ch3_raw)
		lw2_1_ch4 = -1 if lw2_1_ch4_raw == null else int(lw2_1_ch4_raw)
	# channel_2 == 3 is a genuinely bound slot (CobbleA on weightmap 0 channel
	# 3), so this cannot pass on code that never binds the layer slots.
	var lw2_1_ok: bool = lw2_mat1 != null \
		and lw2_1_idx_ok \
		and lw2_1_wm1 == null \
		and lw2_1_ch2 == 3 \
		and lw2_1_ch3 == -1 \
		and lw2_1_ch4 == -1
	if not lw2_1_ok:
		printerr("FAIL: single-weightmap landscape (mat=", lw2_mat1 != null, " weightmap_1=", lw2_1_wm1, " expected null, layer_tex_idx=", lw2_1_idx_desc, " expected all 0, channel_2=", lw2_1_ch2, " expected 3, channel_3=", lw2_1_ch3, " expected -1, channel_4=", lw2_1_ch4, " expected -1)")
		fails += 1
	else:
		print("PASS: single-weightmap landscape leaves weightmap_1 unbound (layer_tex_idx=", lw2_1_idx_desc, ", channel_2=", lw2_1_ch2, ", channel_3=", lw2_1_ch3, ", channel_4=", lw2_1_ch4, ")")

	lw2_ll.queue_free()
	await process_frame

	# 25. Disguise and XP authored defaults
	var disguise_rows: Dictionary = {}
	var disguise_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/tables/Gameplay/Tools/PrimaryTools/Disguise/DT_DisguiseV3IntegrityReduction.json"))
	if disguise_doc is Dictionary:
		var disguise_rows_v: Variant = (disguise_doc as Dictionary).get("rows", {})
		if disguise_rows_v is Dictionary:
			disguise_rows = disguise_rows_v as Dictionary
	var timer_row: float = _authored_row_value(disguise_rows, "DisguiseTimer", ["IntegrityReduction", "Value"])
	var sprint_row: float = _authored_row_value(disguise_rows, "Sprinting", ["IntegrityReduction", "Value"])
	var proximity_row: float = _authored_row_value(disguise_rows, "GuardProximity", ["IntegrityReduction", "Value"])
	var proximity_radius_cm: float = _authored_row_value(disguise_rows, "GuardProximity", ["NearbyCharacterState", "CharacterRadius"])
	var damage_row: float = _authored_row_value(disguise_rows, "DamageTaken", ["IntegrityReduction", "Value"])
	var thief_scr: GDScript = load("res://src/player/thief_character.gd") as GDScript
	var thief_consts: Dictionary = thief_scr.get_script_constant_map()
	var timer_const: float = float(thief_consts.get("DISGUISE_DRAIN_TIMER", -1.0))
	var sprint_const: float = float(thief_consts.get("DISGUISE_DRAIN_SPRINTING", -1.0))
	var proximity_const: float = float(thief_consts.get("DISGUISE_DRAIN_GUARD_PROXIMITY", -1.0))
	var proximity_m_const: float = float(thief_consts.get("DISGUISE_GUARD_PROXIMITY_M", -1.0))
	var damage_const: float = float(thief_consts.get("DISGUISE_DAMAGE_INTEGRITY_LOSS", -1.0))
	var base_rate: float = float(thief_scr.call("disguise_drain_rate", false, false))
	var sprint_rate: float = float(thief_scr.call("disguise_drain_rate", true, false))
	var proximity_rate: float = float(thief_scr.call("disguise_drain_rate", false, true))
	var disguise_ok: bool = \
		timer_row == 1.0 \
		and sprint_row == 40.0 \
		and proximity_row == 5.0 \
		and proximity_radius_cm == 100.0 \
		and damage_row == 40.0 \
		and timer_const == timer_row \
		and sprint_const == sprint_row \
		and proximity_const == proximity_row \
		and is_equal_approx(proximity_m_const, proximity_radius_cm * 0.01) \
		and damage_const == damage_row \
		and base_rate == timer_row \
		and sprint_rate - base_rate == sprint_row \
		and proximity_rate - base_rate == proximity_row
	if not disguise_ok:
		printerr("FAIL: disguise authored defaults (rows=", disguise_rows.size(), " timer=", timer_row, "/", timer_const, " sprint=", sprint_row, "/", sprint_const, " proximity=", proximity_row, "/", proximity_const, " radius_cm=", proximity_radius_cm, " radius_m=", proximity_m_const, " damage=", damage_row, "/", damage_const, " rates=", base_rate, "/", sprint_rate, "/", proximity_rate, ")")
		fails += 1
	else:
		print("PASS: disguise drain matches DT_DisguiseV3IntegrityReduction (timer ", timer_row, "/s, sprint ", sprint_row, "/s, guard proximity ", proximity_row, "/s within ", proximity_radius_cm, "cm; damage event ", damage_row, ")")

	var xp_keys: Array = []
	var xp_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/tables/Gameplay/Tuning/CT_XPToLevel.json"))
	if xp_doc is Dictionary:
		var xp_rows_v: Variant = (xp_doc as Dictionary).get("rows", {})
		if xp_rows_v is Dictionary:
			var xp_row_v: Variant = (xp_rows_v as Dictionary).get("XPToLevel", {})
			if xp_row_v is Dictionary:
				var xp_keys_v: Variant = (xp_row_v as Dictionary).get("Keys", [])
				if xp_keys_v is Array:
					xp_keys = xp_keys_v as Array
	var authored_xp: Dictionary = {}
	for key_v: Variant in xp_keys:
		if key_v is Dictionary:
			var key_d: Dictionary = key_v as Dictionary
			authored_xp[int(float(key_d.get("Time", -1.0)))] = float(key_d.get("Value", -1.0))
	var authored_l1: float = float(authored_xp.get(1, -1.0))
	var authored_l5: float = float(authored_xp.get(5, -1.0))
	var authored_l10: float = float(authored_xp.get(10, -1.0))
	var xp_l1: int = int(save_sys.xp_threshold_for_level(1))
	var xp_l5: int = int(save_sys.xp_threshold_for_level(5))
	var xp_l10: int = int(save_sys.xp_threshold_for_level(10))
	# The old flat constant was 500: levels 5 and 10 must now differ from it.
	var xp_ok: bool = \
		authored_l1 == 500.0 \
		and authored_l5 == 1000.0 \
		and authored_l10 == 2500.0 \
		and float(xp_l1) == authored_l1 \
		and float(xp_l5) == authored_l5 \
		and float(xp_l10) == authored_l10 \
		and float(xp_l5) != 500.0 \
		and float(xp_l10) != 500.0
	if not xp_ok:
		printerr("FAIL: XP authored curve (keys=", xp_keys.size(), " authored L1/L5/L10=", authored_l1, "/", authored_l5, "/", authored_l10, " thresholds=", xp_l1, "/", xp_l5, "/", xp_l10, ")")
		fails += 1
	else:
		print("PASS: XP thresholds match CT_XPToLevel.XPToLevel (L1=", xp_l1, ", L5=", xp_l5, ", L10=", xp_l10, "; flat 500 would fail L5/L10)")

	# 26. AI detection authored curves
	var guard_scr: GDScript = load("res://src/ai/guard_ai.gd") as GDScript
	var lp_scr: GDScript = load("res://src/stealth/light_probe.gd") as GDScript
	var guard_consts: Dictionary = guard_scr.get_script_constant_map()
	var alertness_enum: Dictionary = {}
	var alertness_v: Variant = guard_consts.get("Alertness", {})
	if alertness_v is Dictionary:
		alertness_enum = alertness_v as Dictionary
	var detection_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/gameplay/detection.json"))
	var decay_doc: Dictionary = {}
	var sprint_mult_authored: float = -1.0
	if detection_doc is Dictionary:
		var det: Dictionary = detection_doc as Dictionary
		var decay_v: Variant = det.get("decay", {})
		if decay_v is Dictionary:
			decay_doc = decay_v as Dictionary
		var tags_v: Variant = det.get("tag_ramp_modifiers", {})
		if tags_v is Dictionary:
			var sprint_v: Variant = (tags_v as Dictionary).get("Status.Sprinting", {})
			if sprint_v is Dictionary:
				sprint_mult_authored = float((sprint_v as Dictionary).get("Neutral", -1.0))
	var authored_decay: Dictionary = {}
	var alertness_doc: Variant = _repo_json("extracted/json/AI/Alertness/DA_AlertnessSettings.json")
	if alertness_doc is Array and not (alertness_doc as Array).is_empty():
		var asset_v: Variant = (alertness_doc as Array)[0]
		if asset_v is Dictionary:
			var props_v: Variant = (asset_v as Dictionary).get("Properties", {})
			if props_v is Dictionary:
				var decay_settings_v: Variant = (props_v as Dictionary).get("DecaySettings", {})
				if decay_settings_v is Dictionary:
					var decay_rows_v: Variant = (decay_settings_v as Dictionary).get("DecayTimeSeconds", [])
					if decay_rows_v is Array:
						for decay_row_v: Variant in (decay_rows_v as Array):
							if decay_row_v is Dictionary:
								var decay_row: Dictionary = decay_row_v as Dictionary
								var decay_key: String = str(decay_row.get("Key", "")).replace("EAlertnessLevel::", "").to_lower()
								authored_decay[decay_key] = float(decay_row.get("Value", -1.0))
	var gate_in_level: float = float(guard_consts.get("DECAY_MIN_SECONDS_IN_LEVEL", -1.0))
	var gate_since_visible: float = float(guard_consts.get("DECAY_MIN_SECONDS_SINCE_VISIBLE", -1.0))
	var base_seconds: float = float(guard_consts.get("DECAY_BASE_SECONDS", -1.0))
	var decay_ok: bool = \
		is_equal_approx(gate_in_level, float(decay_doc.get("min_seconds_in_level_before_decay", -1.0))) \
		and is_equal_approx(gate_since_visible, float(decay_doc.get("min_seconds_since_visible_before_decay", -1.0))) \
		and is_equal_approx(base_seconds, float(decay_doc.get("detection_decay_seconds", -1.0)))
	var state_pairs: Array = [
		["neutral", int(alertness_enum.get("NEUTRAL", -1))],
		["suspicious", int(alertness_enum.get("SUSPICIOUS", -1))],
		["alerted", int(alertness_enum.get("ALERTED", -1))],
		["combat", int(alertness_enum.get("COMBAT", -1))],
	]
	var decay_rates: Dictionary = {}
	for pair_v: Variant in state_pairs:
		var pair: Array = pair_v as Array
		var state_name: String = str(pair[0])
		var state_id: int = int(pair[1])
		var seconds: float = float(authored_decay.get(state_name, -1.0))
		var expected_rate: float = 100.0 / seconds if seconds > 0.0 else -1.0
		var actual_rate: float = float(guard_scr.call("detection_decay_per_second", state_id))
		var after_one_second: float = float(guard_scr.call("decayed_detection", 100.0, 1.0, state_id))
		var expected_after: float = maxf(0.0, 100.0 - expected_rate)
		decay_rates[state_name] = actual_rate
		if seconds <= 0.0 \
			or not is_equal_approx(actual_rate, expected_rate) \
			or is_equal_approx(actual_rate, 22.0) \
			or not is_equal_approx(after_one_second, expected_after):
			decay_ok = false
	var search_id: int = int(alertness_enum.get("SEARCH", -1))
	var search_expected: float = 100.0 / base_seconds if base_seconds > 0.0 else -1.0
	var search_actual: float = float(guard_scr.call("detection_decay_per_second", search_id))
	if not is_equal_approx(search_actual, search_expected):
		decay_ok = false
	if not decay_ok:
		printerr("FAIL: AI detection decay gates/rates (gates=", gate_in_level, "/", gate_since_visible, "/", base_seconds, " authored=", decay_doc, " rates=", decay_rates, " search=", search_actual, ")")
		fails += 1
	else:
		print("PASS: AI detection decay matches DA_AlertnessSettings.DecayTimeSeconds (Neutral ", decay_rates.get("neutral"), "/s, Suspicious ", decay_rates.get("suspicious"), "/s, Alerted ", decay_rates.get("alerted"), "/s, Combat ", decay_rates.get("combat"), "/s; 22/s would fail)")

	# The two authored gates still guard the four states with
	# DA_AlertnessSettings rows; only Godot-only SEARCH is unconditional.
	var gates_ok: bool = true
	var gate_desc: String = ""
	for pair_v: Variant in state_pairs:
		var pair: Array = pair_v as Array
		var state_name: String = str(pair[0])
		var state_id: int = int(pair[1])
		var seconds_authored: float = float(authored_decay.get(state_name, -1.0))
		var gated_frame: float = float(guard_scr.call("decay_step_detection", state_id, 50.0, gate_in_level - 1.0, gate_since_visible, 1.0))
		var open_frame: float = float(guard_scr.call("decay_step_detection", state_id, 50.0, gate_in_level, gate_since_visible, 1.0))
		var open_expected: float = maxf(0.0, 50.0 - 100.0 / seconds_authored) if seconds_authored > 0.0 else -1.0
		gate_desc += "%s gate=%s open=%s " % [state_name, gated_frame, open_frame]
		if not is_equal_approx(gated_frame, 50.0) or not is_equal_approx(open_frame, open_expected):
			gates_ok = false
	if not gates_ok:
		printerr("FAIL: authored decay gates (", gate_desc, ")")
		fails += 1
	else:
		print("PASS: authored 6 s in-level / 4 s unseen decay gates still hold for Neutral/Suspicious/Alerted/Combat (", gate_desc, ")")

	# Behavioural transition check: a guard that loses sight in COMBAT must not
	# carry 35-60 detection into NEUTRAL. Drives the same pure helpers
	# _physics_process uses (downward clamp + no-sight decay step). SEARCH is
	# entered with state_timer 6.0, equal to the in-level gate, so gated decay
	# would open exactly when SEARCH exits.
	var combat_id: int = int(alertness_enum.get("COMBAT", -1))
	var alerted_id: int = int(alertness_enum.get("ALERTED", -1))
	var neutral_id: int = int(alertness_enum.get("NEUTRAL", -1))
	var suspicious_at: float = float(guard_consts.get("DETECTION_SUSPICIOUS_AT", -1.0))
	var alerted_at: float = float(guard_consts.get("DETECTION_ALERTED_AT", -1.0))
	var combat_at: float = float(guard_consts.get("DETECTION_COMBAT_AT", -1.0))
	var neutral_ceiling: float = float(guard_scr.call("detection_entry_ceiling", neutral_id))
	var seq_step: float = 1.0 / 60.0
	var seq_detection: float = 60.0 # arbitrary high meter value (the sight ramp owns it since W6G)
	var combat_to_alerted: float = float(guard_scr.call("clamped_detection_for_transition", combat_id, alerted_id, seq_detection))
	seq_detection = combat_to_alerted
	var seq_in_state: float = 0.0
	var seq_since_visible: float = 0.0
	while seq_in_state < 6.0:
		seq_detection = float(guard_scr.call("decay_step_detection", alerted_id, seq_detection, seq_in_state, seq_since_visible, seq_step))
		seq_in_state += seq_step
		seq_since_visible += seq_step
	var alerted_exit: float = seq_detection
	seq_detection = float(guard_scr.call("clamped_detection_for_transition", alerted_id, search_id, seq_detection))
	var seq_search_in_state: float = 0.0
	while seq_search_in_state < 6.0:
		seq_detection = float(guard_scr.call("decay_step_detection", search_id, seq_detection, seq_search_in_state, seq_since_visible, seq_step))
		seq_search_in_state += seq_step
		seq_since_visible += seq_step
	var search_exit: float = seq_detection
	seq_detection = float(guard_scr.call("clamped_detection_for_transition", search_id, neutral_id, seq_detection))
	var search_fresh_frame: float = float(guard_scr.call("decay_step_detection", search_id, 60.0, 0.0, 0.0, 1.0))
	var search_fresh_expected: float = 60.0 - 100.0 / base_seconds
	var transition_ok: bool = \
		is_equal_approx(suspicious_at, 15.0) \
		and is_equal_approx(alerted_at, 45.0) \
		and is_equal_approx(combat_at, 100.0) \
		and is_equal_approx(neutral_ceiling, suspicious_at) \
		and is_equal_approx(combat_to_alerted, alerted_at) \
		and alerted_exit <= alerted_at \
		and search_exit <= neutral_ceiling \
		and seq_detection <= neutral_ceiling \
		and seq_detection < 35.0 \
		and is_equal_approx(search_fresh_frame, search_fresh_expected)
	if not transition_ok:
		printerr("FAIL: guard detection carry across COMBAT->ALERTED->SEARCH->NEUTRAL (start 60, combat->alerted=", combat_to_alerted, ", alerted exit=", alerted_exit, ", search exit=", search_exit, ", neutral=", seq_detection, ", ceiling=", neutral_ceiling, ", fresh SEARCH frame=", search_fresh_frame, " expected=", search_fresh_expected, ")")
		fails += 1
	else:
		print("PASS: guard forgets across COMBAT->ALERTED->SEARCH->NEUTRAL (detection 60 -> ", combat_to_alerted, " at Alerted clamp -> ", search_exit, " after 6 s SEARCH -> ", seq_detection, " in Neutral, ceiling ", neutral_ceiling, "; SEARCH decays unconditionally: 60 -> ", search_fresh_frame, " in one frame)")

	var sprint_ramp_const: float = float(guard_consts.get("SPRINT_RAMP_MULTIPLIER", -1.0))
	var sprint_on: float = float(guard_scr.call("sprint_ramp_multiplier", true))
	var sprint_off: float = float(guard_scr.call("sprint_ramp_multiplier", false))
	var sprint_ok: bool = \
		is_equal_approx(sprint_mult_authored, sprint_ramp_const) \
		and is_equal_approx(sprint_on, sprint_mult_authored) \
		and is_equal_approx(sprint_off, 1.0)
	if not sprint_ok:
		printerr("FAIL: AI sprint ramp multiplier (authored=", sprint_mult_authored, " const=", sprint_ramp_const, " on=", sprint_on, " off=", sprint_off, ")")
		fails += 1
	else:
		print("PASS: AI sprint ramp matches detection.json Status.Sprinting x", sprint_on)

	var height_keys: Array = _curve_keys("extracted/json/AI/Alertness/Curve_AI_HeightDifferenceToStrengthMultiplier.json")
	var height_ok: bool = height_keys.size() >= 2
	var height_desc: String = ""
	if height_ok:
		var hk0: Dictionary = height_keys[0] as Dictionary
		var hk1: Dictionary = height_keys[1] as Dictionary
		var hx0: float = float(hk0.get("Time", -1.0))
		var hy0: float = float(hk0.get("Value", -1.0))
		var hx1: float = float(hk1.get("Time", -1.0))
		var hy1: float = float(hk1.get("Value", -1.0))
		var got0: float = float(guard_scr.call("height_difference_strength_multiplier", hx0))
		var got1: float = float(guard_scr.call("height_difference_strength_multiplier", hx1))
		height_desc = "%s m -> %s / %s m -> %s" % [hx0, got0, hx1, got1]
		height_ok = is_equal_approx(got0, hy0) and is_equal_approx(got1, hy1)
	if not height_ok:
		printerr("FAIL: AI height-difference strength curve (", height_desc, " keys=", height_keys.size(), ")")
		fails += 1
	else:
		print("PASS: AI height-difference strength matches Curve_AI_HeightDifferenceToStrengthMultiplier (", height_desc, ")")

	var light_keys: Array = _curve_keys("extracted/json/AI/Data/C_LightIntensityToRangeMultiplier.json")
	var speed_keys: Array = _curve_keys("extracted/json/AI/Data/C_MovementSpeedToMinimumLightDetectionValue.json")
	var light_ok: bool = light_keys.size() >= 2 and speed_keys.size() >= 2
	var light_desc: String = ""
	var speed_desc: String = ""
	if light_ok:
		var lk0: Dictionary = light_keys[0] as Dictionary
		var lk1: Dictionary = light_keys[1] as Dictionary
		var lx0: float = float(lk0.get("Time", -1.0))
		var ly0: float = float(lk0.get("Value", -1.0))
		var lx1: float = float(lk1.get("Time", -1.0))
		var ly1: float = float(lk1.get("Value", -1.0))
		var lgot0: float = float(lp_scr.call("light_intensity_range_multiplier", lx0))
		var lgot1: float = float(lp_scr.call("light_intensity_range_multiplier", lx1))
		light_desc = "%s -> %s / %s -> %s" % [lx0, lgot0, lx1, lgot1]
		light_ok = is_equal_approx(lgot0, ly0) and is_equal_approx(lgot1, ly1)
		var sk0: Dictionary = speed_keys[0] as Dictionary
		var sk1: Dictionary = speed_keys[1] as Dictionary
		var sx0: float = float(sk0.get("Time", -1.0))
		var sy0: float = float(sk0.get("Value", -1.0))
		var sx1: float = float(sk1.get("Time", -1.0))
		var sy1: float = float(sk1.get("Value", -1.0))
		var sgot0: float = float(lp_scr.call("minimum_light_detection_for_speed", sx0))
		var sgot1: float = float(lp_scr.call("minimum_light_detection_for_speed", sx1))
		speed_desc = "%s cm/s -> %s / %s cm/s -> %s" % [sx0, sgot0, sx1, sgot1]
		light_ok = light_ok and is_equal_approx(sgot0, sy0) and is_equal_approx(sgot1, sy1)
	if not light_ok:
		printerr("FAIL: AI light curves (range=", light_desc, " speed=", speed_desc, " light_keys=", light_keys.size(), " speed_keys=", speed_keys.size(), ")")
		fails += 1
	else:
		print("PASS: AI light curves match C_LightIntensityToRangeMultiplier (", light_desc, ") and C_MovementSpeedToMinimumLightDetectionValue (", speed_desc, ")")

	# W6G: single light path. Light visibility still gates acquisition RANGE
	# (the authored curve asserted just above) but no longer multiplies the
	# 0..100 ramp: detection_gain_per_second is light-independent and the
	# port-only vis_mult is gone. Hearing raises alertness only (it must not seed
	# the meter with 25/60), so stale suspicion cannot leak into sight.
	var w6g_gain_guard: CharacterBody3D = guard_scr.new() as CharacterBody3D
	var w6g_saved_light: float = float(gs.get("player_light_visibility"))
	gs.set("player_light_visibility", 0.05)
	var w6g_dark_gain: float = float(w6g_gain_guard.call("detection_gain_per_second", 10.0, false, false, 0.0))
	gs.set("player_light_visibility", 0.95)
	var w6g_lit_gain: float = float(w6g_gain_guard.call("detection_gain_per_second", 10.0, false, false, 0.0))
	gs.set("player_light_visibility", w6g_saved_light)
	var w6g_guard_src: String = FileAccess.get_file_as_string("res://src/ai/guard_ai.gd")
	var w6g_once_ok: bool = is_equal_approx(w6g_dark_gain, w6g_lit_gain) \
		and w6g_lit_gain > 0.0 \
		and w6g_guard_src.find("var vis_mult") < 0 \
		and w6g_guard_src.find("* vis_mult") < 0 \
		and w6g_guard_src.find("detection = maxf(detection, 25.0)") < 0 \
		and w6g_guard_src.find("detection = maxf(detection, 60.0)") < 0
	w6g_gain_guard.free()
	if not w6g_once_ok:
		printerr("FAIL: W6G single light / hearing meter (dark gain=", w6g_dark_gain, " lit=", w6g_lit_gain, " vis_mult applied=", w6g_guard_src.find("var vis_mult") >= 0, " hearing writes detection)")
		fails += 1
	else:
		print("PASS: W6G single light path: detection gain is light-independent (", w6g_lit_gain, "/s at 10 m in both) and hearing no longer writes the detection meter")

	# 27. UE rotator shear regression: every generated basis is orthonormal.
	# The parser stores bases with 5-decimal rounding, so the tolerance is
	# 1e-4 (rounding noise is <= ~1e-5; the m12 shear signal was ~6.5e-2).
	var ortho_files: Array[String] = []
	var ortho_stack: Array[String] = ["res://data/generated/levels"]
	var ortho_probe: DirAccess = DirAccess.open("res://data/generated/levels")
	if ortho_probe == null:
		printerr("FAIL: generated levels dir missing (res://data/generated/levels); regenerate with python3 tools/parse_tables.py")
		fails += 1
	else:
		while not ortho_stack.is_empty():
			var ortho_dir: String = ortho_stack.pop_back()
			var ortho_da: DirAccess = DirAccess.open(ortho_dir)
			if ortho_da == null:
				continue
			ortho_da.list_dir_begin()
			var ortho_entry: String = ortho_da.get_next()
			while ortho_entry != "":
				var ortho_full: String = ortho_dir.path_join(ortho_entry)
				if ortho_da.current_is_dir():
					ortho_stack.append(ortho_full)
				elif ortho_entry.ends_with(".tatlevel.json"):
					ortho_files.append(ortho_full)
				ortho_entry = ortho_da.get_next()
			ortho_da.list_dir_end()
		var ortho_total: int = 0
		var ortho_bad: int = 0
		var ortho_bad_files: Array[String] = []
		for ortho_path: String in ortho_files:
			var ortho_f: FileAccess = FileAccess.open(ortho_path, FileAccess.READ)
			if ortho_f == null:
				continue
			var ortho_parsed: Variant = JSON.parse_string(ortho_f.get_as_text())
			if not (ortho_parsed is Dictionary):
				continue
			var ortho_pending: Array = [ortho_parsed]
			while not ortho_pending.is_empty():
				var ortho_node: Variant = ortho_pending.pop_back()
				if ortho_node is Dictionary:
					var ortho_dict: Dictionary = ortho_node
					for ortho_key: Variant in ortho_dict.keys():
						var ortho_val: Variant = ortho_dict[ortho_key]
						if (str(ortho_key) == "basis" or str(ortho_key) == "rel_basis") and ortho_val is Array and (ortho_val as Array).size() == 9:
							var ortho_b: Array = ortho_val
							var ortho_nums_ok: bool = true
							for ortho_el: Variant in ortho_b:
								if not (ortho_el is float or ortho_el is int):
									ortho_nums_ok = false
							var ortho_ok: bool = false
							if ortho_nums_ok:
								var ortho_c0: Vector3 = Vector3(float(ortho_b[0]), float(ortho_b[3]), float(ortho_b[6]))
								var ortho_c1: Vector3 = Vector3(float(ortho_b[1]), float(ortho_b[4]), float(ortho_b[7]))
								var ortho_c2: Vector3 = Vector3(float(ortho_b[2]), float(ortho_b[5]), float(ortho_b[8]))
								ortho_ok = absf(ortho_c0.length() - 1.0) <= 1e-4 \
									and absf(ortho_c1.length() - 1.0) <= 1e-4 \
									and absf(ortho_c2.length() - 1.0) <= 1e-4 \
									and absf(ortho_c0.dot(ortho_c1)) <= 1e-4 \
									and absf(ortho_c0.dot(ortho_c2)) <= 1e-4 \
									and absf(ortho_c1.dot(ortho_c2)) <= 1e-4
							ortho_total += 1
							if not ortho_ok:
								ortho_bad += 1
								if not ortho_bad_files.has(ortho_path) and ortho_bad_files.size() < 5:
									ortho_bad_files.append(ortho_path)
						elif ortho_val is Dictionary or ortho_val is Array:
							ortho_pending.append(ortho_val)
				elif ortho_node is Array:
					for ortho_item: Variant in (ortho_node as Array):
						if ortho_item is Dictionary or ortho_item is Array:
							ortho_pending.append(ortho_item)
		if ortho_files.is_empty() or ortho_total == 0:
			printerr("FAIL: no generated bases scanned (files=", ortho_files.size(), " total=", ortho_total, ")")
			fails += 1
		elif ortho_bad != 0:
			printerr("FAIL: ", ortho_bad, " non-orthonormal bases in generated levels (", ortho_bad_files, ")")
			fails += 1
		else:
			print("PASS: ", ortho_total, " generated bases orthonormal (", ortho_files.size(), " files)")

	# 28. Material discovery/classification: authored decal and glass textures
	# bind directly, and no non-UI environment material falls back to map art.
	var mats_path: String = "res://data/generated/materials.json"
	var mats_doc: Dictionary = {}
	if not FileAccess.file_exists(mats_path):
		printerr("FAIL: materials.json missing at ", mats_path, "; run python3 tools/parse_materials.py")
		fails += 1
	else:
		var mats_file: FileAccess = FileAccess.open(mats_path, FileAccess.READ)
		var mats_doc_v: Variant = null
		if mats_file != null:
			mats_doc_v = JSON.parse_string(mats_file.get_as_text())
		if mats_doc_v is Dictionary:
			mats_doc = mats_doc_v as Dictionary
		else:
			printerr("FAIL: materials.json is not a JSON object; run python3 tools/parse_materials.py")
			fails += 1
	if not mats_doc.is_empty():
		var mat_fails: Array[String] = []
		var foot_entry: Dictionary = _material_entry_ending_with(mats_doc, "MI_Decal_TrailMarker_Footstep")
		var foot_albedo: String = str(_entry_texs(foot_entry).get("albedo", ""))
		if not foot_albedo.ends_with("T_Decal_Footstep.png"):
			mat_fails.append("MI_Decal_TrailMarker_Footstep albedo=" + foot_albedo)
		var disguise_entry: Dictionary = _material_entry_ending_with(mats_doc, "MI_Decal_TrailMarker_Footstep_Disguise")
		var disguise_albedo: String = str(_entry_texs(disguise_entry).get("albedo", ""))
		if not disguise_albedo.ends_with("T_Decal_Footstep_Disguise.png"):
			mat_fails.append("MI_Decal_TrailMarker_Footstep_Disguise albedo=" + disguise_albedo)
		var glass_texs: Dictionary = _entry_texs(_material_entry_ending_with(mats_doc, "MI_GlassPanels_oldmanor"))
		var glass_expect: Dictionary = {
			"albedo": "WindowPanels_Oldmanor_D.png",
			"normal": "WindowPanels_Oldmanor_N.png",
			"opacity": "WindowPanels_Oldmanor_O.png",
			"orm": "WindowPanels_Oldmanor_ORM.png",
		}
		for glass_slot: Variant in glass_expect.keys():
			var glass_got: String = str(glass_texs.get(str(glass_slot), ""))
			if not glass_got.ends_with(str(glass_expect[glass_slot])):
				mat_fails.append("MI_GlassPanels_oldmanor " + str(glass_slot) + "=" + glass_got)
		var fallback_expect: Dictionary = {
			"MI_TrimMetalA_brass_dark": "T_TrimMetalA_D.png",
			"MI_ManorPanels_Dark": "T_ManorPanels_D.png",
			# Authored TextureStreamingData: T_Plaster_D04 (not the old generic
			# T_Plaster_D guess) and WoodBoardsOld_D (not T_WoodBoardsA_D).
			"MI_PlasterSmoothD": "T_Plaster_D04.png",
			"MI_WoodBoardsOld": "WoodBoardsOld_D.png",
			"MI_WallMoldingTrimA_Dark": "T_WallMoldingTrimA_D.png",
			"MI_OldManorStone_exterior": "T_WallStoneManorA_D.png",
			"MI_StoreFrontWoodTile": "StorefrontWoodTile_D.png",
			"MI_TrimFabricFancyA_Default": "TrimFabricFancyA_D.png",
			"MI_OldBricksB": "T_OldBricksB_D.png",
		}
		for fallback_suffix: Variant in fallback_expect.keys():
			var fallback_albedo: String = str(_entry_texs(_material_entry_ending_with(mats_doc, str(fallback_suffix))).get("albedo", ""))
			if not fallback_albedo.ends_with(str(fallback_expect[fallback_suffix])):
				mat_fails.append(str(fallback_suffix) + " albedo=" + fallback_albedo)
		var glass_panels_albedo: String = str(_entry_texs(_material_entry_ending_with(mats_doc, "M_GlassPanels")).get("albedo", ""))
		if not glass_panels_albedo.contains("/Glass/") or not glass_panels_albedo.ends_with("WindowPanel_D.png"):
			mat_fails.append("M_GlassPanels albedo=" + glass_panels_albedo)
		# Storefront glass decals: the authored texture lives only in the stream
		# list; the old fallback bound storefront wood and lost its 1-bit alpha.
		for sd_suffix: String in ["M_Storefront_Decal", "MI_Storefront_Decal"]:
			var sd_albedo: String = str(_entry_texs(_material_entry_ending_with(mats_doc, sd_suffix)).get("albedo", ""))
			if not sd_albedo.ends_with("T_Storefront_GlassDecalsA.png"):
				mat_fails.append(sd_suffix + " albedo=" + sd_albedo)
		# The only DXT1 source with real punch-through alpha. It must stay
		# full-res; the 1024 import cap blends its 7,611 transparent pixels away.
		var sd_tex: Texture2D = load("res://assets/ue/Raw/Art/Environment/Storefront/GlassDecals/T_Storefront_GlassDecalsA.png") as Texture2D
		var sd_img: Image = sd_tex.get_image() if sd_tex != null else null
		if sd_img == null or sd_img.get_width() <= 1024 or sd_img.get_pixel(3, 3075).a > 0.01:
			mat_fails.append("T_Storefront_GlassDecalsA alpha/size lost")
		# C5: authored defaults from CachedExpressionData, explicit texture
		# params, and the Engine carriers. These are the paths that used to emit
		# "material fallback" warnings or render flat grey.
		var c5_albedo_expect: Dictionary = {
			"MI_TeleScope_Inst": "T_TeleScope_A.png",
			"Mi_Blackjack": "T_Blackjack_D.png",
			"T_LightSm_SconceA_Brass": "T_LightWallCastleSm_D.png",
			"CobwebFogy": "Web_Fogy_diff.png",
			"BaseMaterial": "Web_diff2.png",
			"WorldGridMaterial": "T_Default_Material_Grid_M.png",
		}
		for c5_suffix: Variant in c5_albedo_expect.keys():
			var c5_entry: Dictionary = _material_entry_ending_with(mats_doc, str(c5_suffix))
			var c5_albedo: String = str(_entry_texs(c5_entry).get("albedo", ""))
			if not c5_albedo.ends_with(str(c5_albedo_expect[c5_suffix])):
				mat_fails.append("C5 " + str(c5_suffix) + " albedo=" + c5_albedo)
		var c5_tint_expect: Dictionary = {
			"Utility/M_DarkGrey": [0.09, 0.09, 0.09],
			"gjasp/Chrome": [0.427, 0.427, 0.427],
			"MI_Solid_Blue": [0.002, 0.138, 0.578],
			"BasicShapeMaterial": [0.9, 0.9, 0.9],
		}
		for c5_suffix2: Variant in c5_tint_expect.keys():
			var c5_entry2: Dictionary = _material_entry_ending_with(mats_doc, str(c5_suffix2))
			var c5_tint_v: Variant = c5_entry2.get("tint", null)
			var c5_want: Array = c5_tint_expect[c5_suffix2] as Array
			var c5_tint_ok: bool = c5_tint_v is Array and (c5_tint_v as Array).size() >= 3
			if c5_tint_ok:
				var c5_got: Array = c5_tint_v as Array
				for ci: int in range(3):
					if absf(float(c5_got[ci]) - float(c5_want[ci])) > 0.003:
						c5_tint_ok = false
			if not c5_tint_ok:
				mat_fails.append("C5 " + str(c5_suffix2) + " tint=" + str(c5_tint_v))
		var c5_power: Dictionary = _material_entry_ending_with(mats_doc, "MI_PowerLight_On")
		var c5_power_vecs: Variant = c5_power.get("vectors", null)
		var c5_power_emissive: bool = c5_power_vecs is Dictionary and (c5_power_vecs as Dictionary).has("EmissiveColor")
		var c5_power_params: Variant = c5_power.get("params", null)
		var c5_power_strength: bool = c5_power_params is Dictionary and (c5_power_params as Dictionary).has("EmissiveStrength")
		if not c5_power_emissive or not c5_power_strength:
			mat_fails.append("C5 MI_PowerLight_On emissive defaults missing")
		var emissive_expect: Array[String] = ["M_EmissiveBase", "MI_EmissiveShape", "MI_MoonshapeEmissive"]
		for emissive_suffix: String in emissive_expect:
			var emissive_albedo: String = str(_entry_texs(_material_entry_ending_with(mats_doc, emissive_suffix)).get("albedo", ""))
			if emissive_albedo.contains("T_Carpet"):
				mat_fails.append(emissive_suffix + " albedo=" + emissive_albedo)
		var brass_entry: Dictionary = _material_entry_ending_with(mats_doc, "MI_TrimMetalA_brass")
		var brass_vectors_v: Variant = brass_entry.get("vectors", null)
		var brass_overlay: Array = []
		if brass_vectors_v is Dictionary:
			var brass_overlay_v: Variant = (brass_vectors_v as Dictionary).get("Overlay", null)
			if brass_overlay_v is Array:
				brass_overlay = brass_overlay_v as Array
		var brass_want: Array = [0.2135, 0.1995, 0.1902]
		var brass_ok: bool = brass_overlay.size() >= brass_want.size()
		if brass_ok:
			for bi: int in range(brass_want.size()):
				if absf(float(brass_overlay[bi]) - float(brass_want[bi])) > 1e-4:
					brass_ok = false
		if not brass_ok:
			mat_fails.append("MI_TrimMetalA_brass vectors.Overlay=" + str(brass_overlay))
		# BasePropertyOverrides.TwoSided must reach render.two_sided (the old
		# parser read only the top-level flag; MI_TrimMetalC_Rusty gates/fences
		# and MI_TrimMetalA_brass doors/chandeliers were single-sided).
		var rusty_entry: Dictionary = _material_entry_ending_with(mats_doc, "MI_TrimMetalC_Rusty")
		var rusty_render_v: Variant = rusty_entry.get("render", null)
		if not (
			rusty_render_v is Dictionary
			and (rusty_render_v as Dictionary).get("two_sided", false) == true
		):
			mat_fails.append("MI_TrimMetalC_Rusty render.two_sided missing (BasePropertyOverrides)")
		# Paint-stroke albedo recovery: the gate frame and aligned floor bind
		# their own _D, not the master's inherited T_PaintStrokesD.
		var gate_frame_albedo: String = str(_entry_texs(_material_entry_ending_with(mats_doc, "MI_BrickNewClean_XYZ")).get("albedo", ""))
		if not gate_frame_albedo.ends_with("T_BrickNewClean_D.png"):
			mat_fails.append("MI_BrickNewClean_XYZ albedo=" + gate_frame_albedo)
		var floor_tile_albedo: String = str(_entry_texs(_material_entry_ending_with(mats_doc, "MI_FloorTileA_AlignXYZ")).get("albedo", ""))
		if not floor_tile_albedo.ends_with("T_FloorTileA_D.png"):
			mat_fails.append("MI_FloorTileA_AlignXYZ albedo=" + floor_tile_albedo)
		var mats_total: int = mats_doc.size()
		var albedo_count: int = 0
		var map_albedo_bad: Array[String] = []
		var eye_albedo_bad: Array[String] = []
		var glass_albedo_bad: Array[String] = []
		for mat_key: Variant in mats_doc.keys():
			var key_s: String = str(mat_key)
			var entry_v: Variant = mats_doc[mat_key]
			var texs: Dictionary = {}
			if entry_v is Dictionary:
				texs = _entry_texs(entry_v as Dictionary)
			var albedo: String = str(texs.get("albedo", ""))
			if albedo != "":
				albedo_count += 1
			var is_ui: bool = key_s.contains("/UI/") or key_s.contains("MI_UI") or key_s.contains("M_UI")
			if not is_ui and albedo.contains("T_MapBuilding_"):
				map_albedo_bad.append(key_s)
			var is_character: bool = key_s.contains("/Character/") or key_s.contains("EyeLibrary") or key_s.contains("Eye")
			if not is_character and albedo.contains("T_Eye_"):
				eye_albedo_bad.append(key_s)
			if key_s.contains("/Glass/") and albedo != "":
				# Authored glass stems may live outside /Glass/ (e.g. car glass).
				# Light fixtures stored under Glass/Opaque (DisplayLight, GlassBulb)
				# legitimately use light-emission textures instead of glass.
				var glass_name: String = key_s.get_file().to_lower()
				var is_light_fixture: bool = glass_name.contains("light") or glass_name.contains("bulb")
				if not is_light_fixture and not albedo.contains("/Glass/") and not albedo.get_file().to_lower().contains("glass"):
					glass_albedo_bad.append(key_s + " -> " + albedo)
		if not map_albedo_bad.is_empty():
			mat_fails.append("non-UI materials with map albedo: " + str(map_albedo_bad.slice(0, 5)))
		if not eye_albedo_bad.is_empty():
			mat_fails.append("non-character materials with eye albedo: " + str(eye_albedo_bad.slice(0, 5)))
		if not glass_albedo_bad.is_empty():
			mat_fails.append("glass materials with non-glass albedo: " + str(glass_albedo_bad.slice(0, 5)))
		if mats_total <= 1500:
			mat_fails.append("material count " + str(mats_total) + " <= 1500")
		if albedo_count <= 1000:
			mat_fails.append("albedo count " + str(albedo_count) + " <= 1000")
		if mat_fails.is_empty():
			print("PASS: materials.json bindings (", mats_total, " materials, ", albedo_count, " with albedo; footstep/disguise/glass/brass/fallback families authored, 0 map/eye/glass leaks)")
		else:
			for mat_fail: String in mat_fails:
				printerr("FAIL: material binding: ", mat_fail)
			fails += 1

	# 29. UE vector tint (Overlay/Multiply) darkens metals; BlackUnlit is unshaded black.
	var vec_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(vec_ll)
	await process_frame
	var brass_mat29: StandardMaterial3D = vec_ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalA_brass") as StandardMaterial3D
	var iron_mat29: StandardMaterial3D = vec_ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalA_Iron") as StandardMaterial3D
	var black_mat29: StandardMaterial3D = vec_ll.call("get_material_for_ue", "/Game/MaterialLibrary/Utility/BlackUnlitMaterial") as StandardMaterial3D
	var brass_entry29: Dictionary = _material_entry_ending_with(mats_doc, "MI_TrimMetalA_brass")
	var brass_vec29: Array = []
	var brass_vecs29: Variant = brass_entry29.get("vectors", null)
	if brass_vecs29 is Dictionary:
		var bov29: Variant = (brass_vecs29 as Dictionary).get("Overlay", null)
		if bov29 is Array:
			brass_vec29 = bov29
	var brass_want29: Array = [0.2135, 0.1995, 0.1902]
	var brass_vec_ok29: bool = brass_vec29.size() >= 3
	if brass_vec_ok29:
		for bi29: int in range(3):
			if absf(float(brass_vec29[bi29]) - float(brass_want29[bi29])) > 0.0001:
				brass_vec_ok29 = false
	var iron_entry29: Dictionary = _material_entry_ending_with(mats_doc, "MI_TrimMetalA_Iron")
	var iron_vec29: Array = []
	var iron_vecs29: Variant = iron_entry29.get("vectors", null)
	if iron_vecs29 is Dictionary:
		var imv29: Variant = (iron_vecs29 as Dictionary).get("Multiply", null)
		if imv29 is Array:
			iron_vec29 = imv29
	var iron_want29: Array = [0.3595, 0.4062, 0.4022]
	var iron_vec_ok29: bool = iron_vec29.size() >= 3
	if iron_vec_ok29:
		for ii29: int in range(3):
			if absf(float(iron_vec29[ii29]) - float(iron_want29[ii29])) > 0.0001:
				iron_vec_ok29 = false
	var brass_ok29: bool = brass_mat29 != null and brass_mat29.albedo_color.r < 1.0 and brass_mat29.albedo_color.g < 1.0 and brass_mat29.albedo_color.b < 1.0
	var iron_ok29: bool = iron_mat29 != null and iron_mat29.albedo_color.r < 1.0 and iron_mat29.albedo_color.g < 1.0 and iron_mat29.albedo_color.b < 1.0
	var black_ok29: bool = black_mat29 != null and black_mat29.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and is_equal_approx(black_mat29.albedo_color.r, 0.0) and is_equal_approx(black_mat29.albedo_color.g, 0.0) and is_equal_approx(black_mat29.albedo_color.b, 0.0)
	if not brass_vec_ok29 or not iron_vec_ok29 or not brass_ok29 or not iron_ok29 or not black_ok29:
		printerr("FAIL: UE vector tint / BlackUnlit (brass_vec=", brass_vec29, " ok=", brass_vec_ok29, " brass_albedo=", brass_mat29.albedo_color if brass_mat29 != null else Color(-1, -1, -1), " iron_vec=", iron_vec29, " ok=", iron_vec_ok29, " iron_albedo=", iron_mat29.albedo_color if iron_mat29 != null else Color(-1, -1, -1), " black_shading=", black_mat29.shading_mode if black_mat29 != null else -1, " black_albedo=", black_mat29.albedo_color if black_mat29 != null else Color(-1, -1, -1), ")")
		fails += 1
	else:
		print("PASS: UE Overlay/Multiply darken metals (brass ", brass_mat29.albedo_color, ", iron ", iron_mat29.albedo_color, ") and BlackUnlit is unshaded black")
	# 29b. MI_LightBeam_SM uses the additive/unlit beam shader with the
	# authored warm-white colour, not an opaque lit StandardMaterial3D.
	var beam_mat29: Variant = vec_ll.call("get_material_for_ue", "/Game/Gameplay/Traps/Detectors/LightBeam/MI_LightBeam_SM")
	var beam_sm29 := beam_mat29 as ShaderMaterial
	var beam_ok29: bool = beam_sm29 != null and beam_sm29.shader != null and beam_sm29.shader.resource_path.ends_with("tat_beam.gdshader")
	if beam_ok29:
		var beam_col29: Variant = beam_sm29.get_shader_parameter("beam_color")
		var beam_energy29: Variant = beam_sm29.get_shader_parameter("energy")
		beam_ok29 = beam_col29 is Color \
			and is_equal_approx((beam_col29 as Color).a, 0.55) \
			and absf(float((beam_col29 as Color).r) - 1.0) < 0.002 \
			and absf(float((beam_col29 as Color).g) - 0.93) < 0.002 \
			and absf(float((beam_col29 as Color).b) - 0.82) < 0.002 \
			and is_equal_approx(float(beam_energy29), 1.7)
	if not beam_ok29:
		printerr("FAIL: 29b MI_LightBeam_SM not the additive beam shader (mat=", beam_mat29, ")")
		fails += 1
	else:
		print("PASS: 29b MI_LightBeam_SM binds tat_beam.gdshader (warm white a=0.55, energy 1.7)")
	# 29c. _build_volumes tags designer blockers for traversal rejection while
	# leaving the body solid on layer 1.
	var vol_parent29 := Node3D.new()
	root.add_child(vol_parent29)
	var vol_ctx29: Dictionary = {}
	vec_ll.call("_build_volumes", [{
		"class": "BlockingVolume",
		"extent": [1.0, 1.0, 1.0],
		"pos": [0.0, 0.0, 0.0],
		"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
	}], vol_parent29, vol_ctx29)
	var vol_body29 := vol_parent29.get_child(0) as StaticBody3D if vol_parent29.get_child_count() == 1 else null
	var vol_ok29: bool = vol_body29 != null \
		and vol_body29.is_in_group("blocking_volume") \
		and vol_body29.collision_layer == 1 \
		and int(vol_ctx29.get("blocking_volume_count", 0)) == 1
	if not vol_ok29:
		printerr("FAIL: 29c blocking volume group/layer missing (body=", vol_body29, " ctx=", vol_ctx29, ")")
		fails += 1
	else:
		print("PASS: 29c blocking volumes tagged 'blocking_volume', solid on layer 1")
	vol_parent29.queue_free()
	vec_ll.queue_free()
	await process_frame

	# 30. GLB material-slot order: mesh_materials.json follows GLB primitive
	# order (authoritative), not UE sidecar slot order. Regression for the
	# 17/27 wrong surfaces in docs/reports/glb-material-slot-proof.md:
	# ThievesDen surface7 must be MI_WoodBoardsOld (not WorldGridMaterial),
	# WindowStandardA 0 wood/1 glass (not swapped), FacadeLrgA_Base/TopA and
	# RoofCity reorders corrected. Counts are GLB primitive counts
	# (ThievesDen 10 source slots -> 8, TopA 7 -> 6; dropped source slots
	# OldManorPanels/Pipes/StoneWallA never bound).
	var mm_path := "res://data/generated/mesh_materials.json"
	var mm_doc: Dictionary = {}
	if not FileAccess.file_exists(mm_path):
		printerr("FAIL: mesh_materials.json missing at ", mm_path, "; run python3 tools/parse_materials.py")
		fails += 1
	else:
		var mm_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(mm_path))
		if mm_v is Dictionary:
			mm_doc = mm_v as Dictionary
		if mm_doc.is_empty():
			printerr("FAIL: mesh_materials.json empty or invalid; run python3 tools/parse_materials.py")
			fails += 1
	if not mm_doc.is_empty():
		var glb_expect := {
			"/Game/Developers/gjasp/SM_ThievesDen": [
				"/Game/MaterialLibrary/Environment/Wood/ML/MI_OldManorWood",
				"/Game/MaterialLibrary/Environment/Wood/Floors/ML/MI_WoodFloorA",
				"/Game/MaterialLibrary/Environment/Wallpaper/ML/MI_WallpaperFloralC_5",
				"/Game/MaterialLibrary/Environment/Wood/ML/MI_OldManorTrim",
				"/Game/MaterialLibrary/Environment/Stone/Trimsheets/ML/MI_Manor_StoneTrim_Dark",
				"/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalA_brass",
				"/Engine/EngineMaterials/WorldGridMaterial",
				"/Game/MaterialLibrary/Environment/Wood/TrimInterior/ML/MI_WoodBoardsOld",
			],
			"/Game/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA": [
				"/Game/Maps/Prototype/TempAssets/MI_WoodBasicA",
				"/Game/MaterialLibrary/Environment/MasterMaterials/M_EnvGlassUnlit",
			],
			"/Game/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA_Open": [
				"/Game/Maps/Prototype/TempAssets/MI_WoodBasicA",
				"/Game/MaterialLibrary/Environment/MasterMaterials/M_EnvGlassUnlit",
			],
			"/Game/Art/Environment/City/Facades/SM_FacadeLrgA_Base": [
				"/Game/MaterialLibrary/Environment/Stone/Trimsheets/ML/MI_StoneTrimsheetB_Grey",
				"/Game/MaterialLibrary/Environment/Wood/TrimInterior/MI_TrimOrnateWoodA_White",
				"/Game/MaterialLibrary/Environment/Mirror/MI_GlassFacadeA",
				"/Game/MaterialLibrary/Environment/Wood/TrimInterior/MI_TrimOrnateBronze",
				"/Game/MaterialLibrary/Environment/Stone/ML/MI_StoneStripA",
				"/Game/MaterialLibrary/Environment/Stone/Wall/ML/MI_StoneWallA",
			],
			"/Game/Art/Environment/City/Facades/SM_FacadeLrgA_TopA": [
				"/Game/MaterialLibrary/Environment/Stone/Trimsheets/ML/MI_StoneTrimsheetB_Grey",
				"/Game/MaterialLibrary/Environment/Roof/Shingles/ML/MI_RoofSlateC",
				"/Game/MaterialLibrary/Environment/Roof/FloorExterior/MI_RoofBitumenA",
				"/Game/MaterialLibrary/Environment/Glass/Opaque/ML/MI_WindowDecoOpaque",
				"/Game/Art/Environment/City/Architecture/BeautifulCorner/Materials/ML/MI_WindowDecoTrim",
				"/Game/MaterialLibrary/Environment/Stone/WallsExterior/ML/MI_WallStoneBlockD",
			],
			"/Game/Art/Environment/City/Architecture/Roofs/RoofDetails/SM_RoofCity_WindowA": [
				"/Game/MaterialLibrary/Environment/Metal/MI_TrimMetalA_Iron",
				"/Game/MaterialLibrary/Environment/Metal/MI_CopperTile",
				"/Game/MaterialLibrary/Environment/Glass/Opaque/MI_GlassSkylightA",
			],
		}
		var glb_bad: Array[String] = []
		for glb_key: Variant in glb_expect.keys():
			var want: Array = glb_expect[glb_key]
			var got_v: Variant = mm_doc.get(str(glb_key), null)
			if not (got_v is Array):
				glb_bad.append(str(glb_key) + " missing (got null)")
				continue
			var got: Array = got_v as Array
			if got.size() != want.size():
				glb_bad.append(str(glb_key) + " count " + str(got.size()) + " expected " + str(want.size()))
				continue
			for gi: int in range(want.size()):
				if str(got[gi]) != str(want[gi]):
					glb_bad.append(str(glb_key) + " surface" + str(gi) + " got=" + str(got[gi]) + " expected=" + str(want[gi]))
					break
		var den_slots: Array = mm_doc.get("/Game/Developers/gjasp/SM_ThievesDen", [])
		var den_s7_ok: bool = den_slots.size() == 8 and str(den_slots[7]).ends_with("MI_WoodBoardsOld")
		var den_dropped_ok: bool = true
		for den_s: Variant in den_slots:
			var den_n := str(den_s)
			if den_n.ends_with("MI_OldManorPanels") or den_n.ends_with("MI_Pipes"):
				den_dropped_ok = false
		var win_slots: Array = mm_doc.get("/Game/Maps/Prototype/TempAssets/Windows/SM_WindowStandardA", [])
		var win_ok: bool = win_slots.size() == 2 and str(win_slots[0]).ends_with("MI_WoodBasicA") and str(win_slots[1]).ends_with("M_EnvGlassUnlit")
		var top_slots: Array = mm_doc.get("/Game/Art/Environment/City/Facades/SM_FacadeLrgA_TopA", [])
		var top_dropped_ok: bool = true
		for top_s: Variant in top_slots:
			if str(top_s).ends_with("/MI_StoneWallA"):
				top_dropped_ok = false
		if not glb_bad.is_empty() or not den_s7_ok or not den_dropped_ok or not win_ok or not top_dropped_ok:
			printerr("FAIL: GLB material-slot order (mismatches=", glb_bad, " den_s7=", den_s7_ok, " den_dropped=", den_dropped_ok, " win01=", win_ok, " top_no_stonewall=", top_dropped_ok, ")")
			fails += 1
		else:
			print("PASS: GLB material-slot order (ThievesDen 8 incl surface7 MI_WoodBoardsOld, Windows 2 wood/glass, FacadeBase 6, FacadeTopA 6, RoofCity 3)")

	# 31. Per-component OverrideMaterials + MID + BPP_* + UE-to-GLB slot remap + bVisible:false + SplineEditorMesh.
	# 31a. Box_83DC6DA6 single-slot override in BeautifulCorner_Startscreen_P.
	var ov_box_meshes: Array = []
	var ov_box_file: FileAccess = FileAccess.open("res://data/generated/levels/Menus/MainMenu/BeautifulCorner_Startscreen_P.tatlevel.json", FileAccess.READ)
	if ov_box_file != null:
		var ov_box_parsed: Variant = JSON.parse_string(ov_box_file.get_as_text())
		if ov_box_parsed is Dictionary:
			ov_box_meshes = (ov_box_parsed as Dictionary).get("meshes", []) as Array
	var ov_slab_count: int = 0
	var ov_slab_bad: int = 0
	for ov_m: Variant in ov_box_meshes:
		if ov_m is Dictionary and str((ov_m as Dictionary).get("mesh", "")).ends_with("Box_83DC6DA6"):
			ov_slab_count += 1
			var ov_slab_arr: Variant = (ov_m as Dictionary).get("override_materials", [])
			if not (ov_slab_arr is Array) or (ov_slab_arr as Array).is_empty() or not str((ov_slab_arr as Array)[0]).ends_with("MI_FloorStoneBlockF"):
				ov_slab_bad += 1
	if ov_slab_count != 5 or ov_slab_bad != 0:
		printerr("FAIL: 31a Box_83DC6DA6 slab overrides (slabs=", ov_slab_count, " expected 5, bad=", ov_slab_bad, ")")
		fails += 1
	else:
		print("PASS: 31a 5 Box_83DC6DA6 slabs carry MI_FloorStoneBlockF in override_materials")

	# 31b. None-slot preservation + UE-to-GLB slot remapping in JSON.
	var ov_front_meshes: Array = []
	var ov_front_file: FileAccess = FileAccess.open("res://data/generated/levels/Buildings/Facades/Facade_Apartment_1000_2Story_Front.tatlevel.json", FileAccess.READ)
	if ov_front_file != null:
		var ov_front_parsed: Variant = JSON.parse_string(ov_front_file.get_as_text())
		if ov_front_parsed is Dictionary:
			ov_front_meshes = (ov_front_parsed as Dictionary).get("meshes", []) as Array
	var ov_lsm_count: int = 0
	var ov_lsm_bad: int = 0
	var ov_lsm_want: Array = ["", "/Game/Art/Environment/Lights/LightModules/MI_LightSmGlassA_Off"]
	for ov_fm: Variant in ov_front_meshes:
		if ov_fm is Dictionary and str((ov_fm as Dictionary).get("mesh", "")).ends_with("SM_LightSmC_Iron"):
			ov_lsm_count += 1
			var ov_fd: Dictionary = ov_fm as Dictionary
			var ov_farr: Variant = ov_fd.get("override_materials", [])
			if not (ov_farr is Array) or (ov_farr as Array) != ov_lsm_want or ov_fd.has("override_material"):
				ov_lsm_bad += 1
	var ov_alley_meshes: Array = []
	var ov_alley_file: FileAccess = FileAccess.open("res://data/generated/levels/Buildings/Alley/Alley_Arched_1800.tatlevel.json", FileAccess.READ)
	if ov_alley_file != null:
		var ov_alley_parsed: Variant = JSON.parse_string(ov_alley_file.get_as_text())
		if ov_alley_parsed is Dictionary:
			ov_alley_meshes = (ov_alley_parsed as Dictionary).get("meshes", []) as Array
	var ov_facb_count: int = 0
	var ov_facb_bad: int = 0
	var ov_facb_slot1_hits: int = 0
	var ov_arch_hits: int = 0
	for ov_am: Variant in ov_alley_meshes:
		if not (ov_am is Dictionary):
			continue
		var ov_ad: Dictionary = ov_am as Dictionary
		var ov_amp: String = str(ov_ad.get("mesh", ""))
		if ov_amp.ends_with("SM_FacadeLrgB"):
			ov_facb_count += 1
			var ov_aarr: Variant = ov_ad.get("override_materials", [])
			if not (ov_aarr is Array) or (ov_aarr as Array).size() != 6:
				ov_facb_bad += 1
			else:
				var ov_aa: Array = ov_aarr as Array
				if str(ov_aa[0]) != "" or str(ov_aa[2]) != "" or str(ov_aa[3]) != "" or str(ov_aa[4]) != "" or not str(ov_aa[5]).ends_with("MI_WallStoneAlley_XYZ") or ov_ad.has("override_material"):
					ov_facb_bad += 1
				if str(ov_aa[1]).ends_with("MI_WallStoneAlley_XYZ"):
					ov_facb_slot1_hits += 1
		elif ov_amp.ends_with("SM_ArchCityA_4x8"):
			var ov_arch_arr: Variant = ov_ad.get("override_materials", [])
			if ov_arch_arr is Array and (ov_arch_arr as Array) == ["", "/Game/MaterialLibrary/Environment/Stone/WallsInterior/ML/MI_WallStoneAlley_XYZ"]:
				ov_arch_hits += 1
	if ov_lsm_count != 2 or ov_lsm_bad != 0 or ov_facb_count != 2 or ov_facb_bad != 0 or ov_facb_slot1_hits < 1 or ov_arch_hits < 1:
		printerr("FAIL: 31b None-slot/GLB-remap (lsm=", ov_lsm_count, "/", ov_lsm_bad, " facb=", ov_facb_count, "/", ov_facb_bad, " s1=", ov_facb_slot1_hits, " arch=", ov_arch_hits, ")")
		fails += 1
	else:
		print("PASS: 31b None-slot preservation + GLB-slot remapping (SM_LightSmC_Iron, SM_FacadeLrgB, SM_ArchCityA_4x8)")

	# 31c. Multi-slot >1 distinct overrides in Facade_Storefront_1000.
	var ov_sf_meshes: Array = []
	var ov_sf_file: FileAccess = FileAccess.open("res://data/generated/levels/Buildings/Facades/Facade_Storefront_1000.tatlevel.json", FileAccess.READ)
	if ov_sf_file != null:
		var ov_sf_parsed: Variant = JSON.parse_string(ov_sf_file.get_as_text())
		if ov_sf_parsed is Dictionary:
			ov_sf_meshes = (ov_sf_parsed as Dictionary).get("meshes", []) as Array
	var ov_sff_want: Array = [
		"/Game/MaterialLibrary/Environment/Wood/ML/MI_StoreFrontTrimA_Painted",
		"/Game/MaterialLibrary/Environment/Wood/ML/MI_StoreFrontTrimB_Painted_Inst",
		"/Game/MaterialLibrary/Environment/Wood/ML/MI_StoreFrontWoodTile_Painted",
		"/Game/MaterialLibrary/Environment/Wood/ML/MI_StoreFrontTrimB_Painted_Inst",
	]
	var ov_sff_count: int = 0
	var ov_sff_bad: int = 0
	for ov_sm: Variant in ov_sf_meshes:
		if ov_sm is Dictionary and str((ov_sm as Dictionary).get("mesh", "")).ends_with("SM_Storefront_Facade_1200"):
			ov_sff_count += 1
			var ov_sarr: Variant = (ov_sm as Dictionary).get("override_materials", [])
			if not (ov_sarr is Array) or (ov_sarr as Array) != ov_sff_want:
				ov_sff_bad += 1
	if ov_sff_count != 1 or ov_sff_bad != 0:
		printerr("FAIL: 31c multi-slot overrides (count=", ov_sff_count, " bad=", ov_sff_bad, ")")
		fails += 1
	else:
		print("PASS: 31c SM_Storefront_Facade_1200 carries 4-slot distinct override_materials")

	# 31d. MID -> Parent resolution in Alley_Arched_1800 and Facade_Apartment_1000_2Story_Mansard.
	var ov_lrgb_count: int = 0
	var ov_lrgb_bad: int = 0
	var ov_lrgb_want: Array = [
		"/Game/Art/Environment/Lights/LightModules/MI_LightLrgABC",
		"/Game/Art/Environment/Lights/LightModules/MI_LightLrgABC_Glass_Blue",
	]
	for ov_am2: Variant in ov_alley_meshes:
		if ov_am2 is Dictionary and str((ov_am2 as Dictionary).get("mesh", "")).ends_with("SM_LightLrgB"):
			ov_lrgb_count += 1
			var ov_larr: Variant = (ov_am2 as Dictionary).get("override_materials", [])
			if not (ov_larr is Array) or (ov_larr as Array) != ov_lrgb_want:
				ov_lrgb_bad += 1
	var ov_mans_meshes: Array = []
	var ov_mans_file: FileAccess = FileAccess.open("res://data/generated/levels/Buildings/Facades/Facade_Apartment_1000_2Story_Mansard.tatlevel.json", FileAccess.READ)
	if ov_mans_file != null:
		var ov_mans_parsed: Variant = JSON.parse_string(ov_mans_file.get_as_text())
		if ov_mans_parsed is Dictionary:
			ov_mans_meshes = (ov_mans_parsed as Dictionary).get("meshes", []) as Array
	var ov_mans_count: int = 0
	var ov_mans_bad: int = 0
	var ov_mans_want: Array = [
		"/Game/Art/Environment/Lights/LightModules/MI_LightSmA_Iron",
		"/Game/Art/Environment/Lights/LightModules/MI_LightSmGlassA_Blue",
	]
	for ov_mm: Variant in ov_mans_meshes:
		if ov_mm is Dictionary and str((ov_mm as Dictionary).get("mesh", "")).ends_with("SM_LightSmC_Iron"):
			ov_mans_count += 1
			var ov_marr: Variant = (ov_mm as Dictionary).get("override_materials", [])
			if not (ov_marr is Array) or (ov_marr as Array) != ov_mans_want:
				ov_mans_bad += 1
	if ov_lrgb_count != 2 or ov_lrgb_bad != 0 or ov_mans_count != 2 or ov_mans_bad != 0:
		printerr("FAIL: 31d MID resolution (lrgb=", ov_lrgb_count, "/", ov_lrgb_bad, " mansard=", ov_mans_count, "/", ov_mans_bad, ")")
		fails += 1
	else:
		print("PASS: 31d MID overrides resolved via Parent.ObjectPath (SM_LightLrgB, SM_LightSmC_Iron)")

	# 31e. BPP_* template overrides in Facade_Monorail_Passthrough and Guildhall_PeripheryA.
	var ov_mono_meshes: Array = []
	var ov_mono_file: FileAccess = FileAccess.open("res://data/generated/levels/Guildhall/Facade_Monorail_Passthrough.tatlevel.json", FileAccess.READ)
	if ov_mono_file != null:
		var ov_mono_parsed: Variant = JSON.parse_string(ov_mono_file.get_as_text())
		if ov_mono_parsed is Dictionary:
			ov_mono_meshes = (ov_mono_parsed as Dictionary).get("meshes", []) as Array
	var ov_bay_want: Array = [
		"/Game/MaterialLibrary/Environment/Stone/WallsExterior/MI_Urban_Ext_Stone",
		"",
		"",
		"/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels_PeriphBuilding_Deco",
	]
	var ov_mono_bay: int = 0
	var ov_mono_bad: int = 0
	for ov_bm: Variant in ov_mono_meshes:
		if ov_bm is Dictionary and str((ov_bm as Dictionary).get("mesh", "")).ends_with("SM_RoofUrbanB_Ext_BayWindowA_6x8"):
			ov_mono_bay += 1
			var ov_barr: Variant = (ov_bm as Dictionary).get("override_materials", [])
			if not (ov_barr is Array) or (ov_barr as Array) != ov_bay_want:
				ov_mono_bad += 1
	var ov_gp_meshes: Array = []
	var ov_gp_file: FileAccess = FileAccess.open("res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json", FileAccess.READ)
	if ov_gp_file != null:
		var ov_gp_parsed: Variant = JSON.parse_string(ov_gp_file.get_as_text())
		if ov_gp_parsed is Dictionary:
			ov_gp_meshes = (ov_gp_parsed as Dictionary).get("meshes", []) as Array
	var ov_gp_bay: int = 0
	var ov_gp_4slot: int = 0
	var ov_gp_stone0: int = 0
	for ov_gm: Variant in ov_gp_meshes:
		if ov_gm is Dictionary and str((ov_gm as Dictionary).get("mesh", "")).ends_with("SM_RoofUrbanB_Ext_BayWindowA_6x8"):
			ov_gp_bay += 1
			var ov_garr: Variant = (ov_gm as Dictionary).get("override_materials", [])
			if ov_garr is Array and not (ov_garr as Array).is_empty():
				if str((ov_garr as Array)[0]) == "/Game/MaterialLibrary/Environment/Stone/WallsExterior/MI_Urban_Ext_Stone":
					ov_gp_stone0 += 1
				if (ov_garr as Array) == ov_bay_want:
					ov_gp_4slot += 1
	if ov_mono_bay != 2 or ov_mono_bad != 0 or ov_gp_bay != 3 or ov_gp_4slot != 2 or ov_gp_stone0 != 3:
		printerr("FAIL: 31e BPP_ overrides (mono=", ov_mono_bay, "/", ov_mono_bad, " gp=", ov_gp_bay, " 4slot=", ov_gp_4slot, " stone0=", ov_gp_stone0, ")")
		fails += 1
	else:
		print("PASS: 31e BPP_* template overrides preserved (Facade_Monorail_Passthrough, Guildhall_PeripheryA)")

	# 31f. bVisible:false filtering, audio sublevels present (they carry the
	# acoustic portals / audio-room components), SplineEditorMesh == 0, and a
	# global MID sweep over all 107 emitted maps.
	var ov_den_meshes: Array = []
	var ov_den_file: FileAccess = FileAccess.open("res://data/generated/levels/ThievesDenTest/ThievesDenTest_P.tatlevel.json", FileAccess.READ)
	if ov_den_file != null:
		var ov_den_parsed: Variant = JSON.parse_string(ov_den_file.get_as_text())
		if ov_den_parsed is Dictionary:
			ov_den_meshes = (ov_den_parsed as Dictionary).get("meshes", []) as Array
	var ov_desk: int = 0
	var ov_tables: int = 0
	for ov_m2: Variant in ov_den_meshes:
		if ov_m2 is Dictionary:
			var ov_mp2: String = str((ov_m2 as Dictionary).get("mesh", ""))
			if ov_mp2.ends_with("SM_Storefront_Countertop_Desk"):
				ov_desk += 1
			if ov_mp2.ends_with("SM_DiningTable_2m_End"):
				ov_tables += 1
	var ov_audio_maps: Array[String] = [
		"res://data/generated/levels/OldManor/OldManor_Audio.tatlevel.json",
		"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI_Audio.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_Audio.tatlevel.json",
		"res://data/generated/levels/FTUE/FTUE_Audio.tatlevel.json",
	]
	var ov_audio_found: int = 0
	for ov_ap: String in ov_audio_maps:
		if FileAccess.file_exists(ov_ap):
			ov_audio_found += 1
	if ov_desk != 0 or ov_tables != 2 or ov_audio_found != 4:
		printerr("FAIL: 31f bVisible/audio sublevels (desk=", ov_desk, " tables=", ov_tables, " audio_maps=", ov_audio_found, ")")
		fails += 1
	else:
		print("PASS: 31f hidden desk absent, 2 tables stay, 4 authored *_Audio.tatlevel.json present")

	var ov_mats_db: Dictionary = {}
	var ov_mats_file: FileAccess = FileAccess.open("res://data/generated/materials.json", FileAccess.READ)
	if ov_mats_file != null:
		var ov_mats_parsed: Variant = JSON.parse_string(ov_mats_file.get_as_text())
		if ov_mats_parsed is Dictionary:
			ov_mats_db = ov_mats_parsed as Dictionary
	var ov_spline_files: Array[String] = []
	var ov_spline_stack: Array[String] = ["res://data/generated/levels"]
	while not ov_spline_stack.is_empty():
		var ov_dir: String = ov_spline_stack.pop_back()
		var ov_da: DirAccess = DirAccess.open(ov_dir)
		if ov_da == null:
			continue
		ov_da.list_dir_begin()
		var ov_entry: String = ov_da.get_next()
		while ov_entry != "":
			var ov_full: String = ov_dir.path_join(ov_entry)
			if ov_da.current_is_dir():
				ov_spline_stack.append(ov_full)
			elif ov_entry.ends_with(".tatlevel.json"):
				ov_spline_files.append(ov_full)
			ov_entry = ov_da.get_next()
		ov_da.list_dir_end()
	var ov_spline_count: int = 0
	var ov_unresolved_map_ov: int = 0
	for ov_jp: String in ov_spline_files:
		var ov_jf: FileAccess = FileAccess.open(ov_jp, FileAccess.READ)
		if ov_jf == null:
			continue
		var ov_parsed2: Variant = JSON.parse_string(ov_jf.get_as_text())
		if not (ov_parsed2 is Dictionary):
			continue
		for ov_e: Variant in ((ov_parsed2 as Dictionary).get("meshes", []) as Array):
			if ov_e is Dictionary:
				var ov_ed: Dictionary = ov_e as Dictionary
				if str(ov_ed.get("mesh", "")).find("SplineEditorMesh") >= 0:
					ov_spline_count += 1
				var ov_eov: Variant = ov_ed.get("override_materials", [])
				if ov_eov is Array:
					for ov_slot: Variant in (ov_eov as Array):
						var ov_s: String = str(ov_slot)
						if ov_s.begins_with("/Game/Maps/") and not ov_mats_db.has(ov_s):
							ov_unresolved_map_ov += 1
		for ov_e2: Variant in ((ov_parsed2 as Dictionary).get("landscape_splines", []) as Array):
			if ov_e2 is Dictionary and str((ov_e2 as Dictionary).get("mesh", "")).find("SplineEditorMesh") >= 0:
				ov_spline_count += 1
	if ov_spline_count != 0 or ov_spline_files.size() != 107 or ov_unresolved_map_ov != 0:
		printerr("FAIL: 31f global sweep (SplineEditorMesh=", ov_spline_count, " files=", ov_spline_files.size(), " unresolved_map_ov=", ov_unresolved_map_ov, ")")
		fails += 1
	else:
		print("PASS: 31f SplineEditorMesh=0 and unresolved_map_ov=0 across ", ov_spline_files.size(), " clean levels")

	# 31g. Runtime level_loader.gd per-surface override_materials + non-mutation + batch separation.
	var ov_host: Node3D = Node3D.new()
	root.add_child(ov_host)
	var ov_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ov_ll)
	await process_frame
	var ov_ctx: Dictionary = ov_ll.call("_new_build_ctx", ov_host, null, false)

	var ov_lsm_mp: String = "/Game/Art/Environment/Lights/LightModules/SM_LightSmC_Iron"
	var ov_mat_iron: Variant = ov_ll.call("get_material_for_ue", "/Game/Art/Environment/Lights/LightModules/MI_LightSmA_Iron")
	var ov_mat_off: Variant = ov_ll.call("get_material_for_ue", "/Game/Art/Environment/Lights/LightModules/MI_LightSmGlassA_Off")
	var ov_mat_gold: Variant = ov_ll.call("get_material_for_ue", "/Game/Art/Environment/Lights/LightModules/MI_LightSmGlassA_Gold")
	var ov_item1: Dictionary = {
		"mp": ov_lsm_mp,
		"override_materials": ["", "/Game/Art/Environment/Lights/LightModules/MI_LightSmGlassA_Off"],
		"trs": [Transform3D.IDENTITY],
		"collide": false,
		"cell": Vector2i.ZERO,
	}
	var ov_built1: int = int(ov_ll.call("_build_one_draw_item", ov_item1, ov_host, ov_ctx))
	var ov_node1: MeshInstance3D = ov_host.get_child(ov_host.get_child_count() - 1) as MeshInstance3D if ov_host.get_child_count() > 0 else null
	var ov_r1_ok: bool = ov_built1 == 1 and ov_node1 != null and ov_node1.mesh != null \
		and ov_node1.material_override == null \
		and ov_node1.mesh.surface_get_material(0) == ov_mat_iron \
		and ov_node1.mesh.surface_get_material(1) == ov_mat_off \
		and ov_node1.mesh.surface_get_material(1) != ov_mat_gold \
		and (ov_node1.get_meta("override_materials", []) as Array) == ov_lsm_want

	var ov_item2: Dictionary = {
		"mp": ov_lsm_mp,
		"override_materials": [],
		"trs": [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(1, 0, 0))],
		"collide": false,
		"cell": Vector2i.ZERO,
	}
	var ov_built2: int = int(ov_ll.call("_build_one_draw_item", ov_item2, ov_host, ov_ctx))
	var ov_node2: MultiMeshInstance3D = ov_host.get_child(ov_host.get_child_count() - 1) as MultiMeshInstance3D if ov_host.get_child_count() > 1 else null
	var ov_r2_ok: bool = ov_built2 == 2 and ov_node2 != null and ov_node2.multimesh != null and ov_node2.multimesh.mesh != null \
		and ov_node2.material_override == null \
		and not ov_node2.has_meta("override_materials") \
		and ov_node2.multimesh.mesh.surface_get_material(0) == ov_mat_iron \
		and ov_node2.multimesh.mesh.surface_get_material(1) == ov_mat_gold

	var ov_sff_mp: String = "/Game/Art/Environment/Storefront/Architecture/Facades/SM_Storefront_Facade_1200"
	var ov_item3: Dictionary = {
		"mp": ov_sff_mp,
		"override_materials": ov_sff_want,
		"trs": [Transform3D.IDENTITY],
		"collide": false,
		"cell": Vector2i.ZERO,
	}
	var ov_built3: int = int(ov_ll.call("_build_one_draw_item", ov_item3, ov_host, ov_ctx))
	var ov_node3: MeshInstance3D = ov_host.get_child(ov_host.get_child_count() - 1) as MeshInstance3D if ov_host.get_child_count() > 2 else null
	var ov_sff_m0: Variant = ov_ll.call("get_material_for_ue", ov_sff_want[0])
	var ov_sff_m1: Variant = ov_ll.call("get_material_for_ue", ov_sff_want[1])
	var ov_sff_m2: Variant = ov_ll.call("get_material_for_ue", ov_sff_want[2])
	var ov_sff_m4: Variant = ov_ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Glass/Opaque/ML/MI_WindowDecoBOpaque")
	var ov_sff_m5: Variant = ov_ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Stone/FloorExterior/MI_Manor_StoneBlockF")
	var ov_r3_ok: bool = ov_built3 == 1 and ov_node3 != null and ov_node3.mesh != null \
		and ov_node3.material_override == null \
		and ov_node3.mesh.surface_get_material(0) == ov_sff_m0 \
		and ov_node3.mesh.surface_get_material(1) == ov_sff_m1 \
		and ov_node3.mesh.surface_get_material(2) == ov_sff_m2 \
		and ov_node3.mesh.surface_get_material(3) == ov_sff_m1 \
		and ov_node3.mesh.surface_get_material(4) == ov_sff_m4 \
		and ov_node3.mesh.surface_get_material(5) == ov_sff_m5 \
		and ov_sff_m0 != ov_sff_m1 and ov_sff_m1 != ov_sff_m2

	var ov_batches: Dictionary = {}
	ov_batches[ov_lsm_mp + "||" + "|/Game/Art/Environment/Lights/LightModules/MI_LightSmGlassA_Off"] = [Transform3D.IDENTITY] as Array[Transform3D]
	ov_batches[ov_lsm_mp + "||" + "|/Game/Art/Environment/Lights/LightModules/MI_LightSmGlassA_Blue"] = [Transform3D.IDENTITY] as Array[Transform3D]
	ov_batches["/Game/Art/Environment/City/Facades/SM_FacadeLrgB||" + "|||||/Game/MaterialLibrary/Environment/Stone/WallsInterior/ML/MI_WallStoneAlley_XYZ"] = [Transform3D.IDENTITY] as Array[Transform3D]
	var ov_draw_items: Array = ov_ll.call("_make_draw_items", ov_batches, true) as Array
	var ov_batch_ok: bool = ov_draw_items.size() == 3
	if ov_batch_ok:
		var ov_di0: Dictionary = ov_draw_items[0] as Dictionary
		var ov_di1: Dictionary = ov_draw_items[1] as Dictionary
		var ov_di2: Dictionary = ov_draw_items[2] as Dictionary
		ov_batch_ok = str(ov_di0.get("mp", "")) == ov_lsm_mp \
			and str(ov_di1.get("mp", "")) == ov_lsm_mp \
			and (ov_di0.get("override_materials", []) as Array) != (ov_di1.get("override_materials", []) as Array) \
			and str(ov_di2.get("mp", "")) == "/Game/Art/Environment/City/Facades/SM_FacadeLrgB" \
			and (ov_di2.get("override_materials", []) as Array).size() == 6

	if not ov_r1_ok or not ov_r2_ok or not ov_r3_ok or not ov_batch_ok:
		printerr("FAIL: 31g runtime per-surface overrides (r1_none_slot=", ov_r1_ok, " r2_base_nonmut=", ov_r2_ok, " r3_multislot=", ov_r3_ok, " batch_sep=", ov_batch_ok, ")")
		fails += 1
	else:
		print("PASS: 31g runtime per-surface surface_set_material, material_override==null, base cache non-mutation, batch separation")
	ov_host.queue_free()
	ov_ll.queue_free()
	await process_frame

	# 32. Phase 1(b) Emissive CustomPrimitiveData MultiMesh + tat_emissive_cpd.gdshader.
	# 32a. Generated .tatlevel.json cpd + hidden_in_game checks & global sweep.
	var cpd_bc_meshes: Array = []
	var cpd_bc_file: FileAccess = FileAccess.open("res://data/generated/levels/Menus/MainMenu/BeautifulCorner_Startscreen_P.tatlevel.json", FileAccess.READ)
	if cpd_bc_file != null:
		var cpd_bc_parsed: Variant = JSON.parse_string(cpd_bc_file.get_as_text())
		if cpd_bc_parsed is Dictionary:
			cpd_bc_meshes = (cpd_bc_parsed as Dictionary).get("meshes", []) as Array
	var cpd_bc_hits: int = 0
	var cpd_bc_ok: bool = true
	var cpd_bc_want: Array = [0.0, 8.0, 1.0, 0.161586, 0.031644]
	for cpd_m: Variant in cpd_bc_meshes:
		if cpd_m is Dictionary and str((cpd_m as Dictionary).get("mesh", "")).ends_with("SM_Shape_Sphere"):
			cpd_bc_hits += 1
			var cpd_md: Dictionary = cpd_m as Dictionary
			var cpd_arr_v: Variant = cpd_md.get("cpd", null)
			var cpd_hid_v: Variant = cpd_md.get("hidden_in_game", false)
			if not (cpd_arr_v is Array) or (cpd_arr_v as Array).size() != 5 or not (cpd_hid_v is bool and (cpd_hid_v as bool)):
				cpd_bc_ok = false
			else:
				var cpd_arr: Array = cpd_arr_v as Array
				for cpd_i: int in range(5):
					if absf(float(cpd_arr[cpd_i]) - float(cpd_bc_want[cpd_i])) > 0.0001:
						cpd_bc_ok = false

	var cpd_fs_meshes: Array = []
	var cpd_fs_file: FileAccess = FileAccess.open("res://data/generated/levels/Buildings/Facades/Facade_Store_1000_2Story_Flat.tatlevel.json", FileAccess.READ)
	if cpd_fs_file != null:
		var cpd_fs_parsed: Variant = JSON.parse_string(cpd_fs_file.get_as_text())
		if cpd_fs_parsed is Dictionary:
			cpd_fs_meshes = (cpd_fs_parsed as Dictionary).get("meshes", []) as Array
	var cpd_fs_hits: int = 0
	var cpd_fs_ok: bool = true
	var cpd_fs_want: Array = [1.0, 0.5, 0.380208, 0.540048, 1.0]
	for cpd_fm: Variant in cpd_fs_meshes:
		if cpd_fm is Dictionary and str((cpd_fm as Dictionary).get("mesh", "")).ends_with("SM_Sphere2Count"):
			cpd_fs_hits += 1
			var cpd_fmd: Dictionary = cpd_fm as Dictionary
			var cpd_fa_v: Variant = cpd_fmd.get("cpd", null)
			var cpd_fh_v: Variant = cpd_fmd.get("hidden_in_game", false)
			if not (cpd_fa_v is Array) or (cpd_fa_v as Array).size() != 5 or not (cpd_fh_v is bool and (cpd_fh_v as bool)):
				cpd_fs_ok = false
			else:
				var cpd_fa: Array = cpd_fa_v as Array
				for cpd_fi: int in range(5):
					if absf(float(cpd_fa[cpd_fi]) - float(cpd_fs_want[cpd_fi])) > 0.0001:
						cpd_fs_ok = false

	var cpd_al_meshes: Array = []
	var cpd_al_file: FileAccess = FileAccess.open("res://data/generated/levels/Buildings/Alley/Alley_Arched_1800.tatlevel.json", FileAccess.READ)
	if cpd_al_file != null:
		var cpd_al_parsed: Variant = JSON.parse_string(cpd_al_file.get_as_text())
		if cpd_al_parsed is Dictionary:
			cpd_al_meshes = (cpd_al_parsed as Dictionary).get("meshes", []) as Array
	var cpd_al_hits: int = 0
	var cpd_al_ok: bool = true
	var cpd_al_want: Array = [0.0, 0.75, 0.043199, 0.121815, 1.0]
	for cpd_am: Variant in cpd_al_meshes:
		if cpd_am is Dictionary and str((cpd_am as Dictionary).get("mesh", "")).ends_with("SM_Sphere4Count"):
			cpd_al_hits += 1
			var cpd_amd: Dictionary = cpd_am as Dictionary
			var cpd_aa_v: Variant = cpd_amd.get("cpd", null)
			var cpd_ah_v: Variant = cpd_amd.get("hidden_in_game", false)
			if not (cpd_aa_v is Array) or (cpd_aa_v as Array).size() != 5 or not (cpd_ah_v is bool and (cpd_ah_v as bool)):
				cpd_al_ok = false
			else:
				var cpd_aa: Array = cpd_aa_v as Array
				for cpd_ai: int in range(5):
					if absf(float(cpd_aa[cpd_ai]) - float(cpd_al_want[cpd_ai])) > 0.0001:
						cpd_al_ok = false

	var cpd_global_total: int = 0
	var cpd_global_bad: int = 0
	var cpd_donut_total: int = 0
	var cpd_donut_bad: int = 0
	var cpd_water_hits: int = 0
	var cpd_water_bad: int = 0
	for cpd_jp: String in ov_spline_files:
		var cpd_jf: FileAccess = FileAccess.open(cpd_jp, FileAccess.READ)
		if cpd_jf == null:
			continue
		var cpd_jparsed: Variant = JSON.parse_string(cpd_jf.get_as_text())
		if not (cpd_jparsed is Dictionary):
			continue
		var cpd_is_manor: bool = cpd_jp.ends_with("OldManor_Geo.tatlevel.json")
		for cpd_ge: Variant in ((cpd_jparsed as Dictionary).get("meshes", []) as Array):
			if not (cpd_ge is Dictionary):
				continue
			var cpd_ged: Dictionary = cpd_ge as Dictionary
			var cpd_gmp: String = str(cpd_ged.get("mesh", ""))
			if cpd_ged.has("cpd"):
				cpd_global_total += 1
				var cpd_gv: Variant = cpd_ged.get("cpd", null)
				var cpd_gh: Variant = cpd_ged.get("hidden_in_game", false)
				if not (cpd_gv is Array) or (cpd_gv as Array).size() != 5 or not (cpd_gh is bool and (cpd_gh as bool)):
					cpd_global_bad += 1
				else:
					for cpd_el: Variant in (cpd_gv as Array):
						if not (cpd_el is float or cpd_el is int):
							cpd_global_bad += 1
							break
			if cpd_gmp.ends_with("SM_DonutShell"):
				cpd_donut_total += 1
				var cpd_dv: Variant = cpd_ged.get("cpd", null)
				if not (cpd_dv is Array) or (cpd_dv as Array).size() != 5:
					cpd_donut_bad += 1
			if cpd_is_manor and cpd_gmp.ends_with("SM_Shape_Plane"):
				var cpd_mov: Variant = cpd_ged.get("override_materials", [])
				if cpd_mov is Array and (cpd_mov as Array).size() > 0 and str((cpd_mov as Array)[0]).ends_with("MI_WaterTest_Inst"):
					cpd_water_hits += 1
					if cpd_ged.has("cpd"):
						cpd_water_bad += 1

	if cpd_bc_hits != 1 or not cpd_bc_ok or cpd_fs_hits != 1 or not cpd_fs_ok or cpd_al_hits != 2 or not cpd_al_ok or cpd_global_total < 1200 or cpd_global_bad != 0 or cpd_donut_total != 12 or cpd_donut_bad != 0 or cpd_water_hits != 2 or cpd_water_bad != 0:
		printerr("FAIL: 32a generated cpd sweep (bc=", cpd_bc_hits, "/", cpd_bc_ok, " fs=", cpd_fs_hits, "/", cpd_fs_ok, " al=", cpd_al_hits, "/", cpd_al_ok, " global=", cpd_global_total, "/bad=", cpd_global_bad, " donut=", cpd_donut_total, "/bad=", cpd_donut_bad, " water=", cpd_water_hits, "/bad=", cpd_water_bad, ")")
		fails += 1
	else:
		print("PASS: 32a generated .tatlevel.json cpd checks (total=", cpd_global_total, ", donut=", cpd_donut_total, ", OldManor water=", cpd_water_hits, " clean)")

	# 32b. Non-emissive separation: Firewood_01 and SM_WardBox (MI_WardZone_Slow).
	var cpd_fw_files: Array[String] = [
		"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_PeripheryA.tatlevel.json",
		"res://data/generated/levels/OldManor/OldManor_Geo.tatlevel.json",
	]
	var cpd_fw_count: int = 0
	var cpd_fw_bad: int = 0
	for cpd_fwp: String in cpd_fw_files:
		var cpd_fwf: FileAccess = FileAccess.open(cpd_fwp, FileAccess.READ)
		if cpd_fwf == null:
			continue
		var cpd_fw_parsed: Variant = JSON.parse_string(cpd_fwf.get_as_text())
		if not (cpd_fw_parsed is Dictionary):
			continue
		for cpd_fwe: Variant in ((cpd_fw_parsed as Dictionary).get("meshes", []) as Array):
			if cpd_fwe is Dictionary and str((cpd_fwe as Dictionary).get("mesh", "")).ends_with("Firewood_01"):
				cpd_fw_count += 1
				if (cpd_fwe as Dictionary).has("cpd"):
					cpd_fw_bad += 1

	var cpd_wb_files: Array[String] = [
		"res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
		"res://data/generated/levels/OldManor/OldManor_Gameplay.tatlevel.json",
	]
	var cpd_wb_count: int = 0
	var cpd_wb_bad: int = 0
	for cpd_wbp: String in cpd_wb_files:
		var cpd_wbf: FileAccess = FileAccess.open(cpd_wbp, FileAccess.READ)
		if cpd_wbf == null:
			continue
		var cpd_wb_parsed: Variant = JSON.parse_string(cpd_wbf.get_as_text())
		if not (cpd_wb_parsed is Dictionary):
			continue
		for cpd_wbe: Variant in ((cpd_wb_parsed as Dictionary).get("meshes", []) as Array):
			if cpd_wbe is Dictionary and str((cpd_wbe as Dictionary).get("mesh", "")).ends_with("SM_WardBox"):
				cpd_wb_count += 1
				if (cpd_wbe as Dictionary).has("cpd"):
					cpd_wb_bad += 1

	var cpd_host: Node3D = Node3D.new()
	root.add_child(cpd_host)
	var cpd_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(cpd_ll)
	await process_frame
	var cpd_ctx_nonem: Dictionary = cpd_ll.call("_new_build_ctx", cpd_host, null, false)
	var cpd_fw_mp: String = "/Game/Art/VFX/FluidNinja/WIP/Meshes/Firewood_01"
	var cpd_fw_item: Dictionary = {
		"mp": cpd_fw_mp,
		"override_materials": [],
		"trs": [Transform3D.IDENTITY],
		"cpds": [] as Array[Color],
		"hidden_in_game": false,
		"collide": false,
		"cell": Vector2i.ZERO,
	}
	var cpd_fw_built: int = int(cpd_ll.call("_build_one_draw_item", cpd_fw_item, cpd_host, cpd_ctx_nonem))
	var cpd_fw_node: MeshInstance3D = cpd_host.get_child(cpd_host.get_child_count() - 1) as MeshInstance3D if cpd_host.get_child_count() > 0 else null
	var cpd_fw_mat_ok: bool = cpd_fw_built == 1 and cpd_fw_node != null and cpd_fw_node.material_override == null \
		and cpd_fw_node.mesh != null and (cpd_fw_node.mesh.surface_get_material(0) is StandardMaterial3D)

	var cpd_wb_mp: String = "/Game/Art/Gameplay/Wards/SM_WardBox"
	var cpd_wb_ov: Array[String] = ["/Game/Art/Effects/WardZones/MI_WardZone_Slow"]
	var cpd_wb_gate_false: bool = not bool(cpd_ll.call("_is_emissive_cpd_override", cpd_wb_ov))
	var cpd_wb_item: Dictionary = {
		"mp": cpd_wb_mp,
		"override_materials": cpd_wb_ov,
		"trs": [Transform3D.IDENTITY],
		"cpds": [] as Array[Color],
		"hidden_in_game": false,
		"collide": false,
		"cell": Vector2i.ZERO,
	}
	var cpd_wb_built: int = int(cpd_ll.call("_build_one_draw_item", cpd_wb_item, cpd_host, cpd_ctx_nonem))
	var cpd_wb_node: MeshInstance3D = cpd_host.get_child(cpd_host.get_child_count() - 1) as MeshInstance3D if cpd_host.get_child_count() > 1 else null
	var cpd_wb_mat_ok: bool = cpd_wb_built == 1 and cpd_wb_node != null and cpd_wb_node.material_override == null \
		and cpd_wb_node.mesh != null and (cpd_wb_node.mesh.surface_get_material(0) is StandardMaterial3D)

	# W10-A3: the merged BP component props/transform fix emits the authored
	# Firewood_01..04 components of every campfire Blueprint. The old count (35)
	# was the pre-fix under-emission: PeripheryA gained 3 and OldManor_Geo 15
	# Firewood_01 placements that the raw level stubs did not carry. The
	# property under test is unchanged: none of them may carry CPD.
	if cpd_fw_count != 53 or cpd_fw_bad != 0 or not cpd_fw_mat_ok or cpd_wb_count != 80 or cpd_wb_bad != 0 or not cpd_wb_gate_false or not cpd_wb_mat_ok:
		printerr("FAIL: 32b non-emissive separation (fw=", cpd_fw_count, "/bad=", cpd_fw_bad, "/mat=", cpd_fw_mat_ok, " wb=", cpd_wb_count, "/bad=", cpd_wb_bad, "/gate=", cpd_wb_gate_false, "/mat=", cpd_wb_mat_ok, ")")
		fails += 1
	else:
		print("PASS: 32b Firewood_01 (", cpd_fw_count, ") and SM_WardBox/MI_WardZone_Slow (", cpd_wb_count, ") bind StandardMaterial3D without CPD shader")

	# 32c. Runtime level_loader.gd MultiMesh custom_data, visible vs hidden_in_game, batching, and end-to-end sublevel load.
	var cpd_has_rd: bool = RenderingServer.get_rendering_device() != null
	var cpd_ctx_rt: Dictionary = cpd_ll.call("_new_build_ctx", cpd_host, null, true)
	var cpd_c1_arr: Array[Color] = [Color(1.0, 0.161586, 0.031644, 8.0)]
	var cpd_item_vis1: Dictionary = {
		"mp": "/Game/Test/Art/Primitives/SM_Shape_Sphere",
		"override_materials": ["/Game/MaterialLibrary/Environment/Lights/MI_EmissiveShapeExterior"],
		"trs": [Transform3D.IDENTITY],
		"cpds": cpd_c1_arr,
		"hidden_in_game": false,
		"collide": true,
		"cell": Vector2i.ZERO,
	}
	var cpd_b_vis1: int = int(cpd_ll.call("_build_one_draw_item", cpd_item_vis1, cpd_host, cpd_ctx_rt))
	var cpd_n_vis1: MultiMeshInstance3D = cpd_host.get_child(cpd_host.get_child_count() - 1) as MultiMeshInstance3D
	var cpd_vis1_sh: ShaderMaterial = cpd_n_vis1.material_override as ShaderMaterial if cpd_n_vis1 != null else null
	var cpd_vis1_d0: Color = cpd_n_vis1.multimesh.get_instance_custom_data(0) if cpd_n_vis1 != null and cpd_n_vis1.multimesh != null else Color(-1, -1, -1, -1)
	var cpd_vis1_d0_ok: bool = (not cpd_has_rd) or cpd_vis1_d0.is_equal_approx(cpd_c1_arr[0])
	var cpd_vis1_ok: bool = cpd_b_vis1 == 1 and cpd_n_vis1 != null and cpd_n_vis1.multimesh != null \
		and cpd_n_vis1.multimesh.use_custom_data == true and cpd_n_vis1.multimesh.instance_count == 1 \
		and cpd_vis1_d0_ok \
		and cpd_n_vis1.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and cpd_n_vis1.visible == true \
		and cpd_vis1_sh != null and cpd_vis1_sh.shader != null and cpd_vis1_sh.shader.resource_path == "res://src/core/tat_emissive_cpd.gdshader"

	var cpd_item_hid1: Dictionary = {
		"mp": "/Game/Test/Art/Primitives/SM_Shape_Sphere",
		"override_materials": ["/Game/MaterialLibrary/Environment/Lights/MI_EmissiveShapeExterior"],
		"trs": [Transform3D(Basis.IDENTITY, Vector3(2, 0, 0))],
		"cpds": cpd_c1_arr,
		"hidden_in_game": true,
		"collide": true,
		"cell": Vector2i.ZERO,
	}
	var cpd_b_hid1: int = int(cpd_ll.call("_build_one_draw_item", cpd_item_hid1, cpd_host, cpd_ctx_rt))
	var cpd_n_hid1: MultiMeshInstance3D = cpd_host.get_child(cpd_host.get_child_count() - 1) as MultiMeshInstance3D
	var cpd_hid1_sh: ShaderMaterial = cpd_n_hid1.material_override as ShaderMaterial if cpd_n_hid1 != null else null
	var cpd_hid1_d0: Color = cpd_n_hid1.multimesh.get_instance_custom_data(0) if cpd_n_hid1 != null and cpd_n_hid1.multimesh != null else Color(-1, -1, -1, -1)
	var cpd_hid1_d0_ok: bool = (not cpd_has_rd) or cpd_hid1_d0.is_equal_approx(cpd_c1_arr[0])
	var cpd_hid1_ok: bool = cpd_b_hid1 == 1 and cpd_n_hid1 != null and cpd_n_hid1.multimesh != null \
		and cpd_n_hid1.multimesh.use_custom_data == true and cpd_n_hid1.multimesh.instance_count == 1 \
		and cpd_hid1_d0_ok \
		and cpd_n_hid1.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and cpd_n_hid1.visible == false \
		and cpd_n_hid1.gi_mode == GeometryInstance3D.GI_MODE_STATIC \
		and cpd_hid1_sh != null and cpd_hid1_sh.shader != null and cpd_hid1_sh.shader.resource_path == "res://src/core/tat_emissive_cpd.gdshader"

	var cpd_c2_arr: Array[Color] = [
		Color(0.043199, 0.121815, 1.0, 0.75),
		Color(0.380208, 0.540048, 1.0, 0.5),
	]
	var cpd_item_bat2: Dictionary = {
		"mp": "/Game/Art/Environment/Lights/LightModules/EmissiveShapes/SM_Sphere4Count",
		"override_materials": ["/Game/MaterialLibrary/Environment/Lights/MI_EmissiveShape"],
		"trs": [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(4, 0, 0))],
		"cpds": cpd_c2_arr,
		"hidden_in_game": true,
		"collide": true,
		"cell": Vector2i.ZERO,
	}
	var cpd_b_bat2: int = int(cpd_ll.call("_build_one_draw_item", cpd_item_bat2, cpd_host, cpd_ctx_rt))
	var cpd_n_bat2: MultiMeshInstance3D = cpd_host.get_child(cpd_host.get_child_count() - 1) as MultiMeshInstance3D
	var cpd_bat2_sh: ShaderMaterial = cpd_n_bat2.material_override as ShaderMaterial if cpd_n_bat2 != null else null
	var cpd_bat2_d0: Color = cpd_n_bat2.multimesh.get_instance_custom_data(0) if cpd_n_bat2 != null and cpd_n_bat2.multimesh != null else Color(-1, -1, -1, -1)
	var cpd_bat2_d1: Color = cpd_n_bat2.multimesh.get_instance_custom_data(1) if cpd_n_bat2 != null and cpd_n_bat2.multimesh != null else Color(-1, -1, -1, -1)
	var cpd_bat2_data_ok: bool = (not cpd_has_rd) or (cpd_bat2_d0.is_equal_approx(cpd_c2_arr[0]) and cpd_bat2_d1.is_equal_approx(cpd_c2_arr[1]) and not cpd_bat2_d0.is_equal_approx(cpd_bat2_d1))
	var cpd_bat2_ok: bool = cpd_b_bat2 == 2 and cpd_n_bat2 != null and cpd_n_bat2.multimesh != null \
		and cpd_n_bat2.multimesh.use_custom_data == true and cpd_n_bat2.multimesh.instance_count == 2 \
		and cpd_bat2_data_ok \
		and cpd_n_bat2.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and cpd_n_bat2.visible == false \
		and cpd_bat2_sh != null and cpd_bat2_sh.shader != null and cpd_bat2_sh.shader.resource_path == "res://src/core/tat_emissive_cpd.gdshader"

	var cpd_col_zero_ok: bool = int(cpd_ctx_rt.get("collision_shapes", -1)) == 0 and int(cpd_ctx_rt.get("collision_bodies", -1)) == 0

	var cpd_e2e_host: Node3D = Node3D.new()
	root.add_child(cpd_e2e_host)
	var cpd_acc: Dictionary = cpd_ll.call("_new_accumulator") as Dictionary
	cpd_ll.call("_parse_sublevel_file", "res://data/generated/levels/Menus/MainMenu/BeautifulCorner_Startscreen_P.tatlevel.json", cpd_acc, cpd_e2e_host)
	var cpd_e2e_items: Array = cpd_ll.call("_collect_draw_items", cpd_acc) as Array
	var cpd_e2e_ctx: Dictionary = cpd_ll.call("_new_build_ctx", cpd_e2e_host, null, true)
	var cpd_e2e_ok: bool = false
	for cpd_it_v: Variant in cpd_e2e_items:
		if cpd_it_v is Dictionary and str((cpd_it_v as Dictionary).get("mp", "")).ends_with("SM_Shape_Sphere"):
			var cpd_e2e_cnt: int = int(cpd_ll.call("_build_one_draw_item", cpd_it_v, cpd_e2e_host, cpd_e2e_ctx))
			var cpd_e2e_node: MultiMeshInstance3D = cpd_e2e_host.get_child(cpd_e2e_host.get_child_count() - 1) as MultiMeshInstance3D
			var cpd_e2e_d0_ok: bool = (not cpd_has_rd) or (cpd_e2e_node != null and cpd_e2e_node.multimesh != null and cpd_e2e_node.multimesh.get_instance_custom_data(0).is_equal_approx(Color(1.0, 0.161586, 0.031644, 8.0)))
			if cpd_e2e_cnt == 1 and cpd_e2e_node != null and cpd_e2e_node.multimesh != null \
				and cpd_e2e_node.multimesh.use_custom_data == true and cpd_e2e_node.multimesh.instance_count == 1 \
				and cpd_e2e_d0_ok \
				and cpd_e2e_node.visible == false \
				and cpd_e2e_node.material_override is ShaderMaterial \
				and (cpd_e2e_node.material_override as ShaderMaterial).shader != null \
				and (cpd_e2e_node.material_override as ShaderMaterial).shader.resource_path == "res://src/core/tat_emissive_cpd.gdshader":
				cpd_e2e_ok = true

	var cpd_manor_acc: Dictionary = cpd_ll.call("_new_accumulator") as Dictionary
	cpd_ll.call("_parse_sublevel_file", "res://data/generated/levels/OldManor/OldManor_Geo.tatlevel.json", cpd_manor_acc, cpd_e2e_host)
	var cpd_manor_res: Dictionary = cpd_manor_acc.get("result", {}) as Dictionary
	# W10-A3: 47 (not 22) is the authored census of visible `1m_Plane_Reverse`
	# moon planes in OldManor_Geo (50 SM_Shape_Plane/_Shadow stubs minus 3
	# bVisible=false). The merged-template fix resolves all of them and every one
	# is hidden_in_game, so the moonshape rule still hides the whole set.
	var cpd_moon_ok: bool = int(cpd_manor_res.get("moonshape_hidden", -1)) == 47

	if not cpd_vis1_ok or not cpd_hid1_ok or not cpd_bat2_ok or not cpd_col_zero_ok or not cpd_e2e_ok or not cpd_moon_ok:
		printerr("FAIL: 32c runtime CPD MultiMesh (vis1=", cpd_vis1_ok, " hid1=", cpd_hid1_ok, " bat2=", cpd_bat2_ok, " col0=", cpd_col_zero_ok, " e2e=", cpd_e2e_ok, " moon22=", cpd_moon_ok, " got=", cpd_manor_res.get("moonshape_hidden", -1), ")")
		fails += 1
	else:
		print("PASS: 32c runtime CPD MultiMesh (count=1 vis/hid, count=2 distinct, zero collision, BeautifulCorner e2e, OldManor moonshape_hidden=47)")

	cpd_e2e_host.queue_free()
	cpd_host.queue_free()
	cpd_ll.queue_free()
	await process_frame

	# 33. Phase 1(c): tat_glass.gdshader (authored albedo + opacity map) replacing flat-blue fallback
	var gl_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(gl_ll)
	await process_frame

	# 33a. materials.json opacity map resolution
	var gl_mats_f: FileAccess = FileAccess.open("res://data/generated/materials.json", FileAccess.READ)
	var gl_mats_v: Variant = JSON.parse_string(gl_mats_f.get_as_text()) if gl_mats_f != null else null
	var gl_mats: Dictionary = gl_mats_v as Dictionary if gl_mats_v is Dictionary else {}
	var gl_gp_op: String = str(_entry_texs(gl_mats.get("/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels", {})).get("opacity", ""))
	var gl_mgp_op: String = str(_entry_texs(gl_mats.get("/Game/MaterialLibrary/Environment/Glass/WIndowPanels/M_GlassPanels", {})).get("opacity", ""))
	var gl_om_op: String = str(_entry_texs(gl_mats.get("/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels_oldmanor", {})).get("opacity", ""))
	var gl_mg_op: String = str(_entry_texs(gl_mats.get("/Game/MaterialLibrary/Environment/Glass/WIndowPanels/M_Glass", {})).get("opacity", ""))
	var gl_33a_ok: bool = gl_gp_op.ends_with("WindowPanel_O.png") and gl_mgp_op.ends_with("WindowPanel_O.png") \
		and gl_om_op.ends_with("WindowPanels_Oldmanor_O.png") and gl_mg_op.ends_with("T_StorefrontGlass_O.png")
	if not gl_33a_ok:
		printerr("FAIL: 33a materials.json opacity resolution (MI_GlassPanels=", gl_gp_op, " M_GlassPanels=", gl_mgp_op, " oldmanor=", gl_om_op, " M_Glass=", gl_mg_op, ")")
		fails += 1
	else:
		print("PASS: 33a materials.json opacity maps resolved (WindowPanel_O, WindowPanels_Oldmanor_O, T_StorefrontGlass_O)")

	# 33b. Translucent glass binds tat_glass.gdshader with authored albedo + opacity map
	# 33b (W6L): a mask IS the opacity. MI_GlassPanels authors Opacity 1.5 and
	# _oldmanor 2.0; multiplying a 0.51 mask by either saturated the pane
	# centre. Mask-based glass now caps opacity_scale at 1.0 (see
	# _build_glass_material), so both panes assert 1.0, not the old scalars.
	var gl_gp_m: Variant = gl_ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels")
	var gl_gp_sh: ShaderMaterial = gl_gp_m as ShaderMaterial
	var gl_gp_alb: Variant = gl_gp_sh.get_shader_parameter("albedo_tex") if gl_gp_sh != null else null
	var gl_gp_opt: Variant = gl_gp_sh.get_shader_parameter("opacity_tex") if gl_gp_sh != null else null
	var gl_gp_tint: Variant = gl_gp_sh.get_shader_parameter("albedo_tint") if gl_gp_sh != null else null
	var gl_gp_opsc: float = float(gl_gp_sh.get_shader_parameter("opacity_scale")) if gl_gp_sh != null else -1.0
	var gl_gp_ok: bool = gl_gp_sh != null and gl_gp_sh.shader != null \
		and gl_gp_sh.shader.resource_path == "res://src/core/tat_glass.gdshader" \
		and (gl_gp_alb is Texture2D) and (gl_gp_opt is Texture2D) \
		and gl_gp_sh.get_shader_parameter("use_albedo_tex") == true \
		and gl_gp_sh.get_shader_parameter("use_opacity_tex") == true \
		and absf(gl_gp_opsc - 1.0) < 0.01 \
		and (gl_gp_tint is Color) and absf((gl_gp_tint as Color).r - 0.311) < 0.01

	var gl_om_m: Variant = gl_ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels_oldmanor")
	var gl_om_sh: ShaderMaterial = gl_om_m as ShaderMaterial
	var gl_om_ok: bool = gl_om_sh != null and gl_om_sh.shader != null \
		and gl_om_sh.shader.resource_path == "res://src/core/tat_glass.gdshader" \
		and (gl_om_sh.get_shader_parameter("albedo_tex") is Texture2D) \
		and (gl_om_sh.get_shader_parameter("opacity_tex") is Texture2D) \
		and gl_om_sh.get_shader_parameter("use_opacity_tex") == true \
		and absf(float(gl_om_sh.get_shader_parameter("opacity_scale")) - 1.0) < 0.01

	var gl_unlit_m: Variant = gl_ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/MasterMaterials/M_EnvGlassUnlit")
	var gl_unlit_sh: ShaderMaterial = gl_unlit_m as ShaderMaterial
	var gl_unlit_ok: bool = gl_unlit_sh != null and gl_unlit_sh.shader != null \
		and gl_unlit_sh.shader.resource_path == "res://src/core/tat_glass.gdshader" \
		and (gl_unlit_sh.get_shader_parameter("albedo_tex") is Texture2D) \
		and gl_unlit_sh.get_shader_parameter("use_albedo_tex") == true \
		and gl_unlit_sh.get_shader_parameter("use_opacity_tex") == false

	if not gl_gp_ok or not gl_om_ok or not gl_unlit_ok:
		printerr("FAIL: 33b tat_glass.gdshader bindings (MI_GlassPanels=", gl_gp_ok, " oldmanor=", gl_om_ok, " M_EnvGlassUnlit=", gl_unlit_ok, ")")
		fails += 1
	else:
		print("PASS: 33b tat_glass.gdshader bound with authored albedo+opacity (MI_GlassPanels, MI_GlassPanels_oldmanor, M_EnvGlassUnlit)")

	# 33c. Opaque glass materials stay opaque StandardMaterial3D (no flat-blue hijack)
	var gl_op_paths: Array[String] = [
		"/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels_Opaque",
		"/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels_PeriphBuilding",
		"/Game/Maps/Prototype/TempAssets/Windows/MI_WindowGlassOpaque",
	]
	var gl_op_bad: Array[String] = []
	for gl_opp: String in gl_op_paths:
		var gl_om_mat: Variant = gl_ll.call("get_material_for_ue", gl_opp)
		if not (gl_om_mat is StandardMaterial3D):
			gl_op_bad.append(gl_opp + ":not_std")
			continue
		var gl_std: StandardMaterial3D = gl_om_mat as StandardMaterial3D
		if gl_std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			gl_op_bad.append(gl_opp + ":transparent")
		if gl_std.albedo_texture == null:
			gl_op_bad.append(gl_opp + ":no_albedo_tex")
	if not gl_op_bad.is_empty():
		printerr("FAIL: 33c opaque glass kept opaque: ", gl_op_bad)
		fails += 1
	else:
		print("PASS: 33c opaque glass stays opaque StandardMaterial3D with authored albedo (3/3)")

	# 33d. Exact MI_Storefront_Decal instance uses the dedicated decal shader
	# (90.4% of the albedo texels are black; tinting that black magenta is the bug).
	var sd_path: String = "/Game/Art/Environment/Storefront/GlassDecals/MI_Storefront_Decal"
	var sd_m: Variant = gl_ll.call("get_material_for_ue", sd_path)
	var sd_sh: ShaderMaterial = sd_m as ShaderMaterial
	var sd_shader_ok: bool = sd_sh != null and sd_sh.shader != null \
		and sd_sh.shader.resource_path.ends_with("tat_storefront_decal.gdshader")
	var sd_alb: Variant = sd_sh.get_shader_parameter("albedo_tex") if sd_sh != null else null
	var sd_alb_ok: bool = sd_alb is Texture2D
	var sd_parent_m: Variant = gl_ll.call("get_material_for_ue", "/Game/Art/Environment/Storefront/GlassDecals/M_Storefront_Decal")
	var sd_parent_ok: bool = sd_parent_m is StandardMaterial3D
	var sd_src: String = sd_sh.shader.code if sd_sh != null and sd_sh.shader != null else ""
	var sd_src_ok: bool = sd_src.find("smoothstep(luma_lo, luma_hi, luma)") >= 0 \
		and sd_src.find("ALPHA_SCISSOR_THRESHOLD") >= 0
	if not sd_shader_ok or not sd_alb_ok or not sd_parent_ok or not sd_src_ok:
		printerr("FAIL: 33d storefront decal shader (shader=", sd_shader_ok, " albedo=", sd_alb_ok, " parent_std=", sd_parent_ok, " source=", sd_src_ok, ")")
		fails += 1
	else:
		print("PASS: 33d MI_Storefront_Decal binds tat_storefront_decal.gdshader (albedo bound, parent M_ stays StandardMaterial3D, luma gate + scissor in source)")

	gl_ll.queue_free()
	await process_frame

	# 34. Phase 2A: Den exit door, Den lighting/probe/props, footprints, map table & tokens
	gs.active_contract_order = 1
	var p2_den: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(p2_den)
	var p2_wait: int = 0
	while p2_den.get_node_or_null("ThievesDenReflectionProbe") == null and p2_wait < 80:
		await process_frame
		p2_wait += 1
	await process_frame

	# 34a. Den exit door wired into swinging-door path (reusing SM_DoorInaccessibleA, no static duplicate)
	var p2_exit: Node3D = p2_den.get_node_or_null("ThievesDenExitDoor") as Node3D
	var p2_exit_piv: Node3D = p2_exit.get_node_or_null("DoorPivot") as Node3D if p2_exit != null else null
	var p2_exit_has_mesh: bool = false
	if p2_exit_piv != null:
		for ch_d: Node in p2_exit_piv.get_children():
			if ch_d is MeshInstance3D and (ch_d as MeshInstance3D).mesh != null:
				p2_exit_has_mesh = true
				break
	var p2_exit_ok: bool = p2_exit != null and p2_exit.is_in_group("swinging_doors") \
		and p2_exit.position.distance_to(Vector3(1.8171, 38.8279, 276.4258)) < 0.05 \
		and p2_exit_has_mesh
	var p2_den_ll: Node = p2_den.get("level_loader") as Node
	var p2_dedup_ok: bool = false
	if p2_den_ll != null:
		var p2_acc: Dictionary = p2_den_ll.call("_new_accumulator") as Dictionary
		p2_den_ll.call("_parse_sublevel_file", "res://data/generated/levels/ThievesDenTest/ThievesDenTest_P.tatlevel.json", p2_acc, p2_den)
		var p2_batches: Dictionary = p2_acc.get("batches", {}) as Dictionary
		var p2_static_inacc: int = 0
		for bk_v: Variant in p2_batches.keys():
			if str(bk_v).find("SM_DoorInaccessibleA") >= 0:
				p2_static_inacc += 1
		var p2_res: Dictionary = p2_acc.get("result", {}) as Dictionary
		var p2_dsr: Array = p2_res.get("door_spawn_records", []) as Array
		p2_dedup_ok = (p2_static_inacc == 0 and p2_dsr.size() == 1)
	if not p2_exit_ok or not p2_dedup_ok:
		printerr("FAIL: 34a Den exit door (exit_ok=", p2_exit_ok, " dedup_ok=", p2_dedup_ok, ")")
		fails += 1
	else:
		print("PASS: 34a Den exit door wired into swinging-door path (SM_DoorInaccessibleA, 0 static duplicates)")

	# 34b. Den lighting (hand fills <= 2.0, dark ambient, 1 ReflectionProbe, no invented red, no purple spheres)
	var p2_fill_sum: float = 0.0
	var p2_red_fill: bool = false
	for fl_n: Node in get_nodes_in_group("den_hand_fills"):
		if fl_n is Light3D and p2_den.is_ancestor_of(fl_n):
			var lt: Light3D = fl_n as Light3D
			p2_fill_sum += lt.light_energy
			if lt.light_color.r > 0.7 and lt.light_color.g < 0.25 and lt.light_color.b < 0.25:
				p2_red_fill = true
	var p2_probes: int = 0
	var p2_env_dark: bool = false
	for ch_e: Node in p2_den.get_children():
		if ch_e is ReflectionProbe:
			p2_probes += 1
		elif ch_e is WorldEnvironment and (ch_e as WorldEnvironment).environment != null:
			var we: Environment = (ch_e as WorldEnvironment).environment
			p2_env_dark = we.ambient_light_energy <= 0.15 and we.ambient_light_color.v <= 0.15
	var p2_deco: Node = p2_den.get_node_or_null("DenDecorationPedestal")
	var p2_deco_ok: bool = false
	if p2_deco != null:
		var p2_deco_all_real: bool = true
		for _di: int in range(3):
			var dvis: Node = p2_deco.get_node_or_null("DecorationVisual")
			var found_real: bool = false
			if dvis != null:
				for dc: Node in dvis.get_children():
					if dc is MeshInstance3D and not ((dc as MeshInstance3D).mesh is SphereMesh) and (dc as MeshInstance3D).mesh != null:
						found_real = true
			if not found_real:
				p2_deco_all_real = false
			p2_deco.call("interact", null)
			await process_frame
		p2_deco_ok = p2_deco_all_real
	if p2_fill_sum <= 0.0 or p2_fill_sum > 2.01 or p2_red_fill or p2_probes != 1 or not p2_env_dark or not p2_deco_ok:
		printerr("FAIL: 34b Den lighting/probe/props (fill_sum=", p2_fill_sum, " red=", p2_red_fill, " probes=", p2_probes, " dark_amb=", p2_env_dark, " deco_real=", p2_deco_ok, ")")
		fails += 1
	else:
		print("PASS: 34b Den lighting (hand_fills=", snappedf(p2_fill_sum, 0.01), "<=2.0, dark_amb=true, probes=1, no_red=true, 3/3 real deco GLBs)")

	# 34c. Footprints: authored footstep decal alpha mask (NS_MagicMarker_Footstep
	# -> T_Crate_Decal_D alpha), zero emission
	var p2_vfx: GDScript = load("res://src/core/vfx_manager.gd") as GDScript
	var p2_fp_before: int = root.get_child_count()
	p2_vfx.call("spawn_footprint_decal", Vector3.ZERO, Vector3.FORWARD, true)
	var p2_fp: Node = root.get_child(root.get_child_count() - 1) if root.get_child_count() > p2_fp_before else root.get_node_or_null("FootprintLeft")
	var p2_fp_ok: bool = false
	var p2_fp_dbg: String = "node=null"
	if p2_fp != null:
		var p2_fp_q: MeshInstance3D = p2_fp.get_node_or_null("FootprintQuad") as MeshInstance3D
		if p2_fp_q != null and p2_fp_q.mesh != null and p2_fp_q.mesh.material is StandardMaterial3D:
			var fp_mat: StandardMaterial3D = p2_fp_q.mesh.material as StandardMaterial3D
			var fp_tex: Texture2D = fp_mat.albedo_texture
			var fp_alpha_ok: bool = false
			var corner_a: float = -1.0
			var max_a: float = 0.0
			if fp_tex != null:
				var fp_img: Image = fp_tex.get_image()
				if fp_img != null and not fp_img.is_empty():
					corner_a = fp_img.get_pixel(0, 0).a
					for py: int in range(0, fp_img.get_height(), 4):
						for px: int in range(0, fp_img.get_width(), 4):
							var pa: float = fp_img.get_pixel(px, py).a
							if pa > max_a:
								max_a = pa
					fp_alpha_ok = corner_a < 0.05 and max_a > 0.5
			p2_fp_dbg = "em=" + str(fp_mat.emission_enabled) + " tex=" + str(fp_tex != null) + " ca=" + str(corner_a) + " ma=" + str(max_a)
			p2_fp_ok = (fp_mat.emission_enabled == false and fp_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and fp_tex != null and fp_alpha_ok)
		p2_fp.queue_free()
	if not p2_fp_ok:
		printerr("FAIL: 34c Footprint decal authored-decal alpha mask / zero emission (", p2_fp_dbg, ")")
		fails += 1
	else:
		print("PASS: 34c Footprint decal uses the authored decal alpha mask (NS_MagicMarker_Footstep) with emission_enabled=false")

	# 34d. Map table: +0.75 offset removed, token materials bound, tokens scaled to UE reference framing
	var p2_tok_om: MeshInstance3D = p2_den.get_node_or_null("MapTokenOldManor") as MeshInstance3D
	var p2_tok_gh: MeshInstance3D = p2_den.get_node_or_null("MapTokenGuildHall") as MeshInstance3D
	var p2_tok_ok: bool = false
	var p2_tok_dbg: String = ""
	if p2_tok_om != null and p2_tok_gh != null:
		var y_ok: bool = absf(p2_tok_om.position.y - 41.1337) < 0.1 and absf(p2_tok_gh.position.y - 41.1337) < 0.1
		# T10 UE-relative framing: GH 0.24 anchor, OM 0.24*45.56192/27.39531
		# (SM_MapBuilding_* ExtendedBounds); selected token rests at base*1.15,
		# so any scale in [base, base*1.15] is a legal animation state.
		var om_b: float = float(p2_tok_om.get_meta("minis_base", 0.24))
		var gh_b: float = float(p2_tok_gh.get_meta("minis_base", 0.24))
		var s_ok: bool = absf(gh_b - 0.24) < 0.001 and absf(om_b / maxf(gh_b, 0.0001) - 45.56192 / 27.39531) < 0.01 and p2_tok_om.scale.x >= om_b - 0.01 and p2_tok_om.scale.x <= om_b * 1.15 + 0.01 and p2_tok_gh.scale.x >= gh_b - 0.01 and p2_tok_gh.scale.x <= gh_b * 1.15 + 0.01
		var om_mat: StandardMaterial3D = p2_tok_om.get_surface_override_material(0) as StandardMaterial3D
		var gh_mat: StandardMaterial3D = p2_tok_gh.get_surface_override_material(0) as StandardMaterial3D
		p2_tok_ok = y_ok and s_ok and om_mat != null and om_mat.albedo_texture != null and gh_mat != null and gh_mat.albedo_texture != null
		p2_tok_dbg = "y_ok=" + str(y_ok) + " s_ok=" + str(s_ok) + " s_om=" + str(p2_tok_om.scale) + " s_gh=" + str(p2_tok_gh.scale) + " om_mat=" + str(om_mat != null) + " gh_mat=" + str(gh_mat != null)
	if not p2_tok_ok:
		printerr("FAIL: 34d Map table tokens (om=", p2_tok_om != null, " gh=", p2_tok_gh != null, " y_om=", p2_tok_om.position.y if p2_tok_om != null else -1.0, " ", p2_tok_dbg, ")")
		fails += 1
	else:
		print("PASS: 34d Map table tokens seated at y=", snappedf(p2_tok_om.position.y, 0.001), " scale=", snappedf(p2_tok_om.scale.x, 0.001), " (+0.75 removed) with authored M_MapBuilding_* materials")

	p2_den.queue_free()
	await process_frame

	# 35. Phase 2B: Startscreen camera, Settings teal+grouped+persistence, Mission Prep artwork+11 DT_Missions rows
	# 35a. Startscreen camera (authored CineCameraActor_0 eye, pitch 13.8 deg, vFOV 48.03)
	var mm_scr: GDScript = load("res://src/ui/main_menu.gd") as GDScript
	var mm_node: Control = mm_scr.new() as Control
	root.add_child(mm_node)
	await process_frame
	var mm_cam: Camera3D = mm_node.get("_menu_cam") as Camera3D
	var mm_eye_ok: bool = mm_cam != null and mm_cam.position.distance_to(Vector3(-12.7196, 0.4566, 14.6089)) < 0.25
	var mm_fov_ok: bool = mm_cam != null and absf(mm_cam.fov - 48.03) < 0.05
	var mm_fwd: Vector3 = (-mm_cam.global_basis.z).normalized() if mm_cam != null else Vector3.ZERO
	var mm_pitch_deg: float = rad_to_deg(asin(clampf(mm_fwd.y, -1.0, 1.0)))
	var mm_pitch_ok: bool = mm_cam != null and absf(mm_pitch_deg - 13.8) < 0.6
	if not mm_eye_ok or not mm_fov_ok or not mm_pitch_ok:
		printerr("FAIL: 35a Startscreen camera (eye_ok=", mm_eye_ok, " fov=", mm_cam.fov if mm_cam != null else -1.0, " pitch=", mm_pitch_deg, ")")
		fails += 1
	else:
		print("PASS: 35a Startscreen CineCamera eye=", mm_cam.position, " pitch=", snappedf(mm_pitch_deg, 0.01), " deg vFOV=", mm_cam.fov)
	# 35a2. Startscreen headlights: taming must key off the authored UE intensity
	# metadata (7000 lumens), not the mapped light_energy (~3.9 ceiling). Two
	# authored car headlights sit at x < -10 and become 2.6 energy / 32 deg /
	# attenuation 2.0; a mapped-energy test is unreachable for them.
	var mm_hl_count: int = 0
	var mm_hl_ok: bool = true
	var mm_hl_desc: Array[String] = []
	for mm_hl_node: Node in mm_node.find_children("*", "SpotLight3D", true, false):
		var mm_hl: SpotLight3D = mm_hl_node as SpotLight3D
		if mm_hl == null:
			continue
		var mm_hl_authored: float = float(mm_hl.get_meta("tat_ue_intensity", 0.0))
		if mm_hl_authored < 2500.0:
			continue
		mm_hl_count += 1
		var mm_hl_pos: Vector3 = mm_hl.position
		var mm_hl_row_ok: bool = mm_hl_pos.x < -10.0 \
			and absf(mm_hl.light_energy - 2.6) < 0.001 \
			and absf(mm_hl.spot_angle - 32.0) < 0.01 \
			and absf(mm_hl.spot_attenuation - 2.0) < 0.001
		mm_hl_ok = mm_hl_ok and mm_hl_row_ok
		mm_hl_desc.append("%s authored=%.0f x=%.2f energy=%.2f angle=%.1f atten=%.2f" % [
			mm_hl.name, mm_hl_authored, mm_hl_pos.x, mm_hl.light_energy, mm_hl.spot_angle, mm_hl.spot_attenuation])
	if mm_hl_count != 2 or not mm_hl_ok:
		printerr("FAIL: 35a2 Startscreen headlight taming (count=", mm_hl_count, " ok=", mm_hl_ok, " ", mm_hl_desc, ")")
		fails += 1
	else:
		print("PASS: 35a2 Startscreen headlight taming via tat_ue_intensity (", mm_hl_desc, ")")
	mm_node.queue_free()
	await process_frame

	# 35b. Settings teal theme + grouped rows + persisted values wired into ThiefCharacter
	var st_ui: CanvasLayer = (load("res://src/ui/settings_ui.gd") as GDScript).new() as CanvasLayer
	root.add_child(st_ui)
	await process_frame
	var st_panel: PanelContainer = st_ui.get("_modal_panel") as PanelContainer
	var st_box: StyleBoxFlat = st_panel.get_theme_stylebox("panel") as StyleBoxFlat if st_panel != null else null
	var st_teal_ok: bool = st_box != null and st_box.border_color.b > st_box.border_color.r and st_box.border_color.g > st_box.border_color.r
	var st_groups_v: Variant = st_ui.get("_group_cards")
	var st_groups_cnt: int = (st_groups_v as Array).size() if st_groups_v is Array else 0
	var st_save: Node = root.get_node_or_null("/root/SaveSystem")
	var st_orig: Dictionary = (st_save.call("get_settings") as Dictionary).duplicate(true) if st_save != null else {}
	# RE-H-08: the invented rad/px slider is gone; the authored 5-step ladder is
	# the mouse control, so the persistence probe drives it instead.
	var st_inv_cb: CheckBox = st_ui.get("_invert_check") as CheckBox
	var st_spr_cb: CheckBox = st_ui.get("_sprint_check") as CheckBox
	var st_fov_sl: HSlider = st_ui.get("_fov_slider") as HSlider
	if st_ui.has_method("set_look_sensitivity_step"):
		st_ui.call("set_look_sensitivity_step", "kb", 3) # Fast: shipped curve samples 1.5625x = 0.00390625 rad/px (W9-P1: was the ini ladder 1.5x)
	if st_inv_cb != null:
		st_inv_cb.button_pressed = true
	if st_spr_cb != null:
		st_spr_cb.button_pressed = true
	if st_fov_sl != null:
		st_fov_sl.value = 92.0
	st_ui.call("_apply_live", false)
	var st_thief: Node = (load("res://src/player/thief_character.gd") as GDScript).new()
	root.add_child(st_thief)
	await process_frame
	var st_wire_ok: bool = absf(float(st_thief.get("mouse_sens")) - 0.00390625) < 0.0001 \
		and st_thief.get("invert_y") == true \
		and st_thief.get("sprint_toggle_mode") == true \
		and absf(float(st_thief.get("base_fov")) - 92.0) < 0.1
	st_thief.queue_free()
	if st_save != null and not st_orig.is_empty():
		var sd: Dictionary = st_save.get("data") as Dictionary
		sd["settings"] = st_orig
		st_save.call("apply_saved_settings")
	st_ui.queue_free()
	await process_frame
	if not st_teal_ok or st_groups_cnt < 6 or not st_wire_ok:
		printerr("FAIL: 35b Settings UI/persistence (teal=", st_teal_ok, " groups=", st_groups_cnt, " wired=", st_wire_ok, ")")
		fails += 1
	else:
		print("PASS: 35b Settings teal theme, ", st_groups_cnt, " grouped cards, persisted values wired into ThiefCharacter")

	# 35c. Mission Prep real artwork/icons + all 11 DT_Missions/CDT_Missions rows
	var gd_node: Node = root.get_node_or_null("/root/GameData")
	var all_mis_v: Variant = gd_node.call("get_all_missions") if gd_node != null else []
	var all_mis_cnt: int = (all_mis_v as Array).size() if all_mis_v is Array else 0
	var mp_ui: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	root.add_child(mp_ui)
	await process_frame
	mp_ui.call("open_prep", "old_manor", 2, "Solo", 0)
	var mp_sel: OptionButton = mp_ui.get("_mission_selector") as OptionButton
	var mp_loc_art: TextureRect = mp_ui.get("_location_art") as TextureRect
	var mp_mis_ico: TextureRect = mp_ui.get("_mission_icon") as TextureRect
	var mp_om_ok: bool = mp_sel != null and mp_sel.item_count == 11 \
		and mp_loc_art != null and mp_loc_art.texture != null \
		and mp_mis_ico != null and mp_mis_ico.texture != null
	mp_ui.call("open_prep", "guildhall", 1, "Solo", 0)
	var mp_gh_ok: bool = mp_loc_art != null and mp_loc_art.texture != null \
		and mp_mis_ico != null and mp_mis_ico.texture != null
	var mp_body_node: Node = mp_ui.get("_thief_body_node") as Node
	var mp_head_node: Node = mp_ui.get("_thief_head_node") as Node
	var mp_body_mi: MeshInstance3D = _find_first_mesh_instance(mp_body_node)
	var mp_head_mi: MeshInstance3D = _find_first_mesh_instance(mp_head_node)
	var mp_body_mat: StandardMaterial3D = null
	var mp_head_mat: StandardMaterial3D = null
	var mp_head_glass: Material = mp_head_mi.get_surface_override_material(1) if mp_head_mi != null and mp_head_mi.mesh != null and mp_head_mi.mesh.get_surface_count() > 1 else null
	if mp_body_mi != null and mp_body_mi.mesh != null and mp_body_mi.mesh.get_surface_count() > 2:
		mp_body_mat = mp_body_mi.get_surface_override_material(2) as StandardMaterial3D
	if mp_head_mi != null and mp_head_mi.mesh != null and mp_head_mi.mesh.get_surface_count() > 2:
		mp_head_mat = mp_head_mi.get_surface_override_material(2) as StandardMaterial3D
	var mp_mats_ok: bool = mp_body_mat != null and mp_body_mat.albedo_texture != null \
		and mp_body_mat.albedo_texture.resource_path.find("T_ThiefNisha_Body_D") >= 0 \
		and mp_head_mat != null and mp_head_mat.albedo_texture != null \
		and mp_head_mat.albedo_texture.resource_path.find("T_ThiefNisha_Head_D") >= 0 \
		and (mp_head_glass is ShaderMaterial)
	mp_ui.queue_free()
	await process_frame
	if all_mis_cnt != 11 or not mp_om_ok or not mp_gh_ok or not mp_mats_ok:
		printerr("FAIL: 35c Mission Prep (rows=", all_mis_cnt, " om_ok=", mp_om_ok, " gh_ok=", mp_gh_ok, " preview_pbr=", mp_mats_ok, " head_glass=", mp_head_glass is ShaderMaterial, ")")
		fails += 1
	else:
		print("PASS: 35c Mission Prep loaded all ", all_mis_cnt, " CDT_Missions rows with real artwork, icons & preview PBR")

	# 36. Light-probe authored-light retune: the authored median light (UE
	# Intensity 15 -> energy 1.0 after the linear 1/15 lighting scale) must
	# contribute the pre-lighting-wave 0.9 weight again, while authored dimmer
	# lights keep a monotonic lower weight.
	var lp_retune: GDScript = load("res://src/stealth/light_probe.gd") as GDScript
	var w_median: float = float(lp_retune.call("light_visibility_weight", 1.0))
	var w_authored5: float = float(lp_retune.call("light_visibility_weight", 0.3333333))
	var w_dim: float = float(lp_retune.call("light_visibility_weight", 0.2))
	var w_floor: float = float(lp_retune.call("light_visibility_weight", 0.01))
	var w_bright: float = float(lp_retune.call("light_visibility_weight", 4.0))
	var retune_ok: bool = \
		absf(w_median - 0.9) < 0.001 \
		and absf(w_authored5 - 0.3) < 0.001 \
		and absf(w_dim - 0.18) < 0.001 \
		and absf(w_floor - 0.15) < 0.001 \
		and absf(w_bright - 0.9) < 0.001 \
		and w_dim < w_authored5 and w_authored5 < w_median
	if not retune_ok:
		printerr("FAIL: 36 light-probe retune (median=", w_median, " authored5=", w_authored5, " dim=", w_dim, " floor=", w_floor, " bright=", w_bright, ")")
		fails += 1
	else:
		print("PASS: 36 Light-probe authored-light retune (median 1.0 -> 0.90, authored 5 -> 0.30, dim 0.2 -> 0.18, floor/ceil 0.15/0.90)")

	# 36b. Integration: sample_visibility must apply the retuned weight. An
	# energy-1.0 omni 2 m from the sample point (empty physics space far from
	# level geometry): falloff = 1 - 2/10 = 0.8, contribution = 0.8^2 * 0.90,
	# plus the 0.08 ambient floor.
	var lp_integration: Node = (load("res://src/stealth/light_probe.gd") as GDScript).new()
	root.add_child(lp_integration)
	var retune_light := OmniLight3D.new()
	var retune_origin := Vector3(9000, 500, 9000)
	retune_light.position = retune_origin + Vector3(0, 2, 0)
	retune_light.omni_range = 10.0
	retune_light.light_energy = 1.0
	root.add_child(retune_light)
	lp_integration.register_light(retune_light)
	var retune_space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	var sampled: float = float(lp_integration.call("sample_visibility", retune_origin, retune_space, [] as Array[RID]))
	var expected: float = 0.08 + 0.8 * 0.8 * 0.9
	if absf(sampled - expected) >= 0.01:
		printerr("FAIL: 36b light-probe integration sampled=", sampled, " expected=", expected)
		fails += 1
	else:
		print("PASS: 36b LightProbe integration (energy 1.0 at 2 m / 10 m range -> ", snappedf(sampled, 0.001), ")")
	lp_integration.queue_free()
	retune_light.queue_free()
	await process_frame

	# 37. Startscreen neon: authored HDR "Color" tints on untextured materials
	# must drive a linear HDR unshaded pass, not a clamped/sRGB-converted
	# StandardMaterial3D colour (MI_Neon authored 50/4.109/0.521 previously
	# rendered as a saturated red diffuse blob).
	var neon_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(neon_ll)
	await process_frame
	var neon_mat: ShaderMaterial = neon_ll.call("get_material_for_ue", "/Game/Art/Environment/City/Architecture/BeautifulCorner/MI_Neon") as ShaderMaterial
	var neon_again: Material = neon_ll.call("get_material_for_ue", "/Game/Art/Environment/City/Architecture/BeautifulCorner/MI_Neon") as Material
	var neon_mac: ShaderMaterial = neon_ll.call("get_material_for_ue", "/Game/Art/Environment/City/Architecture/BeautifulCorner/MI_Neon_MacNeish") as ShaderMaterial
	var neon_head: StandardMaterial3D = neon_ll.call("get_material_for_ue", "/Game/Art/Character/ThiefNisha/Base/MI_ThiefNisha_Head") as StandardMaterial3D
	var neon_knife: StandardMaterial3D = neon_ll.call("get_material_for_ue", "/Game/Art/Gameplay/Loot/LootMinor/JeweledKnife/MI_JeweledKnife") as StandardMaterial3D
	var neon_cat: StandardMaterial3D = neon_ll.call("get_material_for_ue", "/Game/Art/Gameplay/Loot/LootMajor/StatueCat/MI_CatStatueA") as StandardMaterial3D
	var neon_beam: ShaderMaterial = neon_ll.call("get_material_for_ue", "/Game/Gameplay/Traps/Detectors/LightBeam/MI_LightBeam_SM") as ShaderMaterial
	var neon_col_v: Variant = neon_mat.get_shader_parameter("hdr_color") if neon_mat != null else null
	var neon_col: Vector3 = neon_col_v if neon_col_v is Vector3 else Vector3.ZERO
	var neon_mac_col_v: Variant = neon_mac.get_shader_parameter("hdr_color") if neon_mac != null else null
	var neon_mac_col: Vector3 = neon_mac_col_v if neon_mac_col_v is Vector3 else Vector3.ZERO
	var neon_scale: float = float(neon_mat.get_shader_parameter("hdr_scale")) if neon_mat != null else -1.0
	var neon_mac_scale: float = float(neon_mac.get_shader_parameter("hdr_scale")) if neon_mac != null else -1.0
	var neon_mesh_info: Dictionary = neon_ll.call("_get_mesh_and_shape", "/Game/Art/Environment/City/Architecture/BeautifulCorner/SM_NeonB")
	var neon_mesh: Mesh = neon_mesh_info.get("mesh") as Mesh
	var neon_bound: Material = neon_mesh.surface_get_material(0) if neon_mesh != null and neon_mesh.get_surface_count() > 0 else null
	var neon_ok: bool = neon_mat != null and neon_mat.shader != null \
		and neon_mat.shader.resource_path.ends_with("tat_hdr_emissive.gdshader") \
		and neon_col.is_equal_approx(Vector3(50.0, 4.109, 0.521)) \
		and absf(neon_scale - 0.08) < 0.001 \
		and neon_again == neon_mat \
		and neon_bound == neon_mat
	var neon_mac_ok: bool = neon_mac != null and neon_mac.shader != null \
		and neon_mac.shader.resource_path.ends_with("tat_hdr_emissive.gdshader") \
		and neon_mac_col.is_equal_approx(Vector3(1.5, 0.055, 1.234)) \
		and absf(neon_mac_scale - 1.0) < 0.001
	var neon_head_ok: bool = neon_head != null and neon_head.albedo_texture != null \
		and (not neon_head.emission_enabled or neon_head.emission.r <= 1.0)
	# RE-C-08/T08: the two textured controls assert the TINT-SPACE CONTRACT, not
	# "the HDR value survives into albedo_color". The old expectation
	# (albedo_color.r > 1.0) pinned C2-02: a 600x shine colour multiplied onto
	# the albedo map, which tonal-maps to flat cream. The contract is now: the
	# albedo colour is sRGB(encode) of the authored linear tint when the tint is
	# <= 1, and the legacy pass-through when it is an HDR carry. This holds for
	# the pre-T08 data (tint 600/2.0) and the post-T08 data (Flat Color
	# 0.948/0.9479) without weakening either.
	var neon_db: Variant = _repo_json("game/data/generated/materials.json")
	var knife_expect: Color = _t08_expected_albedo_tint(neon_db, "/Game/Art/Gameplay/Loot/LootMinor/JeweledKnife/MI_JeweledKnife")
	var cat_expect: Color = _t08_expected_albedo_tint(neon_db, "/Game/Art/Gameplay/Loot/LootMajor/StatueCat/MI_CatStatueA")
	# The expectation is version-agnostic: HDR-authored tints pass through
	# (pre-T08 data: 2.0 / 600), <=1 authored tints are sRGB-encoded (post-T08
	# Flat Color 0.9479 / 0.948). Either way albedo_color must equal the
	# contract value, so an encode on an HDR carry (or a raw linear value)
	# fails here.
	var neon_knife_ok: bool = neon_knife != null and neon_knife.albedo_texture != null \
		and neon_knife.albedo_color.is_equal_approx(knife_expect)
	var neon_cat_ok: bool = neon_cat != null and neon_cat.albedo_texture != null \
		and neon_cat.albedo_color.is_equal_approx(cat_expect)
	var neon_beam_ok: bool = neon_beam != null and neon_beam.shader != null \
		and neon_beam.shader.resource_path.ends_with("tat_beam.gdshader")
	if not neon_ok or not neon_mac_ok or not neon_head_ok or not neon_knife_ok or not neon_cat_ok or not neon_beam_ok:
		printerr("FAIL: 37 neon HDR shader (neon=", neon_ok, " mac=", neon_mac_ok, " head_tex_control=", neon_head_ok, " hdr_tex_control=", neon_knife_ok, " hdr_tex_cat=", neon_cat_ok, " two_sided_beam=", neon_beam_ok, ")")
		fails += 1
	else:
		print("PASS: 37 startscreen neon HDR shader (MI_Neon ", neon_col, " x", snappedf(neon_scale, 0.001), ", MI_Neon_MacNeish ", neon_mac_col, " x", snappedf(neon_mac_scale, 0.001), ")")
	neon_ll.queue_free()
	await process_frame

	# 38. OldManor_P landscape: the extractor now exports the 128 components'
	# heightmaps/weightmaps from the map package; every generated path must exist.
	var om_doc: Variant = _repo_json("game/data/generated/levels/OldManor/OldManor_P.tatlevel.json")
	var om_ls: Array = []
	if om_doc is Dictionary:
		var om_ls_v: Variant = (om_doc as Dictionary).get("landscapes", [])
		if om_ls_v is Array:
			om_ls = om_ls_v as Array
	var om_missing: int = 0
	var om_heightmaps: Dictionary = {}
	var om_weightmaps: Dictionary = {}
	for lc_v: Variant in om_ls:
		if not (lc_v is Dictionary):
			continue
		var lc: Dictionary = lc_v as Dictionary
		var hp: String = str(lc.get("heightmap", ""))
		if hp != "":
			om_heightmaps[hp] = true
			if not FileAccess.file_exists(hp):
				om_missing += 1
		var wms_v: Variant = lc.get("weightmaps", [])
		if wms_v is Array:
			for wm_v: Variant in (wms_v as Array):
				var wm: String = str(wm_v)
				if wm == "":
					continue
				om_weightmaps[wm] = true
				if not FileAccess.file_exists(wm):
					om_missing += 1
	var om_ls_ok: bool = om_ls.size() == 128 and om_missing == 0 \
		and om_heightmaps.size() == 101 and om_weightmaps.size() == 54
	var om_built: int = 0
	if not om_ls.is_empty():
		var om_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
		root.add_child(om_ll)
		await process_frame
		var om_host: Node3D = Node3D.new()
		root.add_child(om_host)
		var om_ctx: Dictionary = om_ll.call("_new_build_ctx", om_host, null, false)
		om_ll.call("_build_one_landscape", om_ls[0], om_host, om_ctx)
		om_built = int(om_ctx.get("landscapes_built", 0))
		om_ll.queue_free()
		om_host.queue_free()
		await process_frame
	var om_built_ok: bool = om_built == 1
	var om_all_ok: bool = om_ls_ok and om_built_ok
	if not om_all_ok:
		printerr("FAIL: 38 OldManor_P landscape assets (components=", om_ls.size(), " heightmaps=", om_heightmaps.size(), " weightmaps=", om_weightmaps.size(), " missing=", om_missing, " built=", om_built, ")")
		fails += 1
	else:
		print("PASS: 38 OldManor_P landscape assets (128 components, 101 heightmaps, 54 weightmaps, 0 missing, runtime build=1)")

	# 39. Tiny-texture mip guard with visible skip accounting (TASK 4.2):
	# icon-size sprites skip the mip chain and are recorded in
	# skipped_tiny_textures/skipped_tiny_count (no silent hide);
	# landscape/PBR textures keep full res + mipmaps.
	var ttg_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ttg_ll)
	await process_frame
	var ttg_tiny_ok: bool = bool(ttg_ll.call("_is_tiny_texture", 8, 8)) \
		and bool(ttg_ll.call("_is_tiny_texture", 16, 64)) \
		and not bool(ttg_ll.call("_is_tiny_texture", 32, 32)) \
		and not bool(ttg_ll.call("_is_tiny_texture", 256, 256)) \
		and not bool(ttg_ll.call("_is_tiny_texture", 1024, 512))
	var ttg_tiny_path: String = "user://__tiny_guard_8x8.png"
	var ttg_big_path: String = "user://__tiny_guard_256x256.png"
	var ttg_img_small: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	ttg_img_small.fill(Color(1, 0, 0, 1))
	ttg_img_small.save_png(ttg_tiny_path)
	var ttg_img_big: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	ttg_img_big.fill(Color(0, 1, 0, 1))
	ttg_img_big.save_png(ttg_big_path)
	var ttg_tex_small: Texture2D = ttg_ll.call("_load_tex", ttg_tiny_path) as Texture2D
	var ttg_tex_big: Texture2D = ttg_ll.call("_load_tex", ttg_big_path) as Texture2D
	ttg_ll.call("_load_tex", ttg_tiny_path)
	var ttg_skipped: Array = (ttg_ll.get("skipped_tiny_textures") as Array).duplicate()
	var ttg_count: int = int(ttg_ll.get("skipped_tiny_count"))
	var ttg_small_img: Image = ttg_tex_small.get_image() if ttg_tex_small != null else null
	var ttg_big_img: Image = ttg_tex_big.get_image() if ttg_tex_big != null else null
	var ttg_small_mips: bool = ttg_small_img.has_mipmaps() if ttg_small_img != null else true
	var ttg_big_mips: bool = ttg_big_img.has_mipmaps() if ttg_big_img != null else false
	var ttg_acct_ok: bool = ttg_tex_small != null and ttg_tex_big != null \
		and ttg_skipped.has(ttg_tiny_path) and not ttg_skipped.has(ttg_big_path) \
		and ttg_count == ttg_skipped.size() and ttg_count >= 1 \
		and ttg_tex_small.get_width() == 8 and ttg_tex_small.get_height() == 8 \
		and ttg_tex_big.get_width() == 256 and ttg_tex_big.get_height() == 256 \
		and not ttg_small_mips and ttg_big_mips
	if not ttg_tiny_ok or not ttg_acct_ok:
		printerr("FAIL: 39 tiny-texture mip guard (thresholds=", ttg_tiny_ok, " acct=", ttg_acct_ok, " skipped=", ttg_skipped, " count=", ttg_count, " small_mips=", ttg_small_mips, " big_mips=", ttg_big_mips, ")")
		fails += 1
	else:
		print("PASS: 39 tiny-texture mip guard (8x8 skipped, 256x256 keeps mips, skipped_tiny_count=", ttg_count, ")")
	var ttg_udir: DirAccess = DirAccess.open("user://")
	if ttg_udir != null:
		ttg_udir.remove("__tiny_guard_8x8.png")
		ttg_udir.remove("__tiny_guard_256x256.png")
	ttg_ll.queue_free()
	await process_frame

	# 39b. Tiny-texture ResourceLoader/.ctex fallback guard (TASK 4.2): a
	# synthetic tiny ImageTexture WITH mipmaps must come back mip-free and
	# be recorded in the same skipped_tiny counter; a 256x256 mipmapped
	# texture passes through untouched and unrecorded.
	var ttf_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ttf_ll)
	await process_frame
	var ttf_tiny_img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	ttf_tiny_img.fill(Color(0, 0, 1, 1))
	ttf_tiny_img.generate_mipmaps()
	var ttf_tiny_src: ImageTexture = ImageTexture.create_from_image(ttf_tiny_img)
	var ttf_big_img: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	ttf_big_img.fill(Color(1, 1, 0, 1))
	ttf_big_img.generate_mipmaps()
	var ttf_big_src: ImageTexture = ImageTexture.create_from_image(ttf_big_img)
	var ttf_tiny_has_mips_before: bool = ttf_tiny_src.get_image().has_mipmaps()
	var ttf_count_before: int = int(ttf_ll.get("skipped_tiny_count"))
	var ttf_tiny_out: Texture2D = ttf_ll.call("_guard_tiny_resource_texture", ttf_tiny_src, "res://__synthetic_tiny.ctex") as Texture2D
	var ttf_big_out: Texture2D = ttf_ll.call("_guard_tiny_resource_texture", ttf_big_src, "res://__synthetic_big.ctex") as Texture2D
	var ttf_tiny_out_img: Image = ttf_tiny_out.get_image() if ttf_tiny_out != null else null
	var ttf_big_out_img: Image = ttf_big_out.get_image() if ttf_big_out != null else null
	var ttf_skipped: Array = (ttf_ll.get("skipped_tiny_textures") as Array).duplicate()
	var ttf_count_after: int = int(ttf_ll.get("skipped_tiny_count"))
	var ttf_tiny_mips_after: bool = ttf_tiny_out_img.has_mipmaps() if ttf_tiny_out_img != null else true
	var ttf_big_mips_after: bool = ttf_big_out_img.has_mipmaps() if ttf_big_out_img != null else false
	var ttf_fallback_ok: bool = ttf_tiny_has_mips_before \
		and ttf_tiny_out != null and ttf_tiny_out.get_width() == 16 and ttf_tiny_out.get_height() == 16 \
		and not ttf_tiny_mips_after \
		and ttf_skipped.has("res://__synthetic_tiny.ctex") and not ttf_skipped.has("res://__synthetic_big.ctex") \
		and ttf_count_after == ttf_count_before + 1 and ttf_count_after == ttf_skipped.size() \
		and ttf_big_out == ttf_big_src and ttf_big_mips_after
	if not ttf_fallback_ok:
		printerr("FAIL: 39b tiny-texture ResourceLoader fallback (mips_before=", ttf_tiny_has_mips_before, " mips_after=", ttf_tiny_mips_after, " big_mips=", ttf_big_mips_after, " skipped=", ttf_skipped, " count=", ttf_count_before, "->", ttf_count_after, ")")
		fails += 1
	else:
		print("PASS: 39b tiny-texture ResourceLoader fallback (16x16 mips stripped, 256x256 untouched, skipped_tiny_count=", ttf_count_after, ")")
	ttf_ll.queue_free()
	await process_frame

	# 39c. Storefront glass-decal alpha bypass through the level loader. The
	# regression at 28 uses load(); this proves the PG-1 texture budget path
	# keeps the only real 1-bit-alpha DXT1 source at its authored 4096² and
	# never records it as downscaled. The import pre-bake already preserves it
	# (ALPHA_CRITICAL_PATHS); this catches a runtime TAT2_TEX_CAP regression.
	var ac_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ac_ll)
	await process_frame
	ac_ll.set("texture_budget_max_dim", 1024)
	var ac_path: String = "res://assets/ue/Raw/Art/Environment/Storefront/GlassDecals/T_Storefront_GlassDecalsA.png"
	var ac_tex: Texture2D = ac_ll.call("_load_tex", ac_path) as Texture2D
	var ac_img: Image = ac_tex.get_image() if ac_tex != null else null
	var ac_alpha: float = ac_img.get_pixel(3, 3075).a if ac_img != null else 1.0
	var ac_downscaled: Array = (ac_ll.get("downscaled_textures") as Array)
	var ac_ok: bool = ac_img != null \
		and ac_img.get_width() == 4096 and ac_img.get_height() == 4096 \
		and ac_alpha <= 0.01 \
		and not ac_downscaled.has(ac_path)
	if not ac_ok:
		printerr("FAIL: 39c storefront alpha bypass via _load_tex (size=", ac_img.get_width() if ac_img != null else -1, "x", ac_img.get_height() if ac_img != null else -1, " alpha(3,3075)=", ac_alpha, " downscaled=", ac_downscaled.has(ac_path), ")")
		fails += 1
	else:
		print("PASS: 39c storefront alpha bypass via _load_tex (4096x4096, alpha(3,3075)=", snappedf(ac_alpha, 0.001), ", runtime cap=1024 ignored)")
	ac_ll.queue_free()
	await process_frame

	# 40. E2E 4.4(a): interactables var/track bounds alias. T1-15-B reads
	# duration_s + arc_deg with bounds dur 1.1..3.1 / arc 69..241 over
	# 24 variations / 48 tracks; the authored key is arc_angle_deg, mirrored
	# here as arc_deg by tools/parse_tables.py fix_interactables_var_track_bounds.
	var iv_file: FileAccess = FileAccess.open("res://data/generated/gameplay/interactables.json", FileAccess.READ)
	var iv_ok: bool = false
	var iv_dbg: String = "missing"
	if iv_file != null:
		var iv_parsed: Variant = JSON.parse_string(iv_file.get_as_text())
		if iv_parsed is Dictionary:
			var iv_lock: Variant = (iv_parsed as Dictionary).get("lockpick", {})
			var iv_vbd: Variant = (iv_lock as Dictionary).get("variations_by_difficulty", {}) if iv_lock is Dictionary else {}
			if iv_vbd is Dictionary:
				var iv_vars: int = 0
				var iv_tracks: int = 0
				var iv_bounds: bool = true
				for iv_k: Variant in (iv_vbd as Dictionary).keys():
					var iv_arr: Variant = (iv_vbd as Dictionary)[iv_k]
					if not (iv_arr is Array):
						continue
					iv_vars += (iv_arr as Array).size()
					for iv_v: Variant in (iv_arr as Array):
						if not (iv_v is Dictionary):
							continue
						var iv_tr: Variant = (iv_v as Dictionary).get("tracks", [])
						if not (iv_tr is Array):
							continue
						iv_tracks += (iv_tr as Array).size()
						for iv_t: Variant in (iv_tr as Array):
							if not (iv_t is Dictionary):
								continue
							var iv_d: float = float((iv_t as Dictionary).get("duration_s", 0.0))
							var iv_a: float = float((iv_t as Dictionary).get("arc_deg", 0.0))
							if iv_d < 1.1 or iv_d > 3.1 or iv_a < 69.0 or iv_a > 241.0:
								iv_bounds = false
				iv_dbg = "vars=%d tracks=%d bounds=%s" % [iv_vars, iv_tracks, str(iv_bounds)]
				iv_ok = iv_vars == 24 and iv_tracks == 48 and iv_bounds
	if not iv_ok:
		printerr("FAIL: 40 interactables var/track bounds (", iv_dbg, ")")
		fails += 1
	else:
		print("PASS: 40 interactables var/track bounds (", iv_dbg, ")")

	# 41. E2E 4.4(d+e): smoke direct API + tool/crank slot contract.
	# Headless-robust: direct equip/fire APIs (no Input tap), mirroring the
	# passing T1-09-B/C/E pattern. Verifies _use_smoke_bomb consumes a
	# charge, get_tool_slots returns 4 structured slots with 1 active, and
	# get_active_reticle_state carries the crank_progress/crank_active keys.
	var sm_gs: Node = root.get_node_or_null("GameState")
	if sm_gs != null:
		sm_gs.set("state", "playing")
	var sm_p: Node = (load("res://src/player/thief_character.gd") as GDScript).new()
	root.add_child(sm_p)
	await process_frame
	var sm_has: bool = sm_p.has_method("equip_tool") and sm_p.has_method("get_tool_slots") and sm_p.has_method("get_active_reticle_state") and sm_p.has_method("_use_smoke_bomb")
	var sm_slots_ok: bool = false
	var sm_ret_ok: bool = false
	var sm_fire_ok: bool = false
	if sm_has:
		sm_p.call("equip_tool", "smoke_bomb")
		await process_frame
		var sm_slots_v: Variant = sm_p.call("get_tool_slots")
		if sm_slots_v is Array and (sm_slots_v as Array).size() >= 4:
			var sm_active: int = 0
			var sm_keys: bool = true
			for sm_sv: Variant in (sm_slots_v as Array):
				if not (sm_sv is Dictionary):
					sm_keys = false
					break
				var sm_sd: Dictionary = sm_sv as Dictionary
				if not (sm_sd.has("slot") and sm_sd.has("id") and sm_sd.has("count") and sm_sd.has("active")):
					sm_keys = false
				if sm_sd.get("active") == true:
					sm_active += 1
			sm_slots_ok = sm_keys and sm_active == 1
		var sm_rs_v: Variant = sm_p.call("get_active_reticle_state")
		if sm_rs_v is Dictionary:
			var sm_rs: Dictionary = sm_rs_v as Dictionary
			sm_ret_ok = sm_rs.has("mode") and sm_rs.has("target_valid") and sm_rs.has("crank_progress") and sm_rs.has("crank_active") and sm_rs.has("hints")
		(sm_p.get("charges") as Dictionary)["smoke_bomb"] = 1
		sm_p.call("_use_smoke_bomb")
		await process_frame
		sm_fire_ok = int((sm_p.get("charges") as Dictionary).get("smoke_bomb", -1)) == 0
	sm_p.queue_free()
	await process_frame
	if not sm_has or not sm_slots_ok or not sm_ret_ok or not sm_fire_ok:
		printerr("FAIL: 41 smoke/crank slots (has=", sm_has, " slots=", sm_slots_ok, " reticle=", sm_ret_ok, " fire1to0=", sm_fire_ok, ")")
		fails += 1
	else:
		print("PASS: 41 smoke _use_smoke_bomb 1->0, 4 tool slots/1 active, crank reticle contract")

	# 42. (removed) This suite asserted that the E2E runner still carried
	# in-memory expectation patches and _load_patched(). Both are masking and
	# were deleted in Phase 12; Suite 43 below is a real functional assertion.

	# 43. Zipwire crank 1P clip: AN_ThiefNisha_Zipwire__Reload_Loop resolves via
	# ensure_fp_clip and plays on crank. Headless-robust: manifest/table/role
	# resolution asserted unconditionally; live playback asserted through a
	# synthetic player (no GLB import needed), mirroring the T1-09 direct-API
	# pattern (no Input tap).
	var cr_lib_scr: GDScript = load("res://src/core/animation_library.gd") as GDScript
	var cr_thief_scr: GDScript = load("res://src/player/thief_character.gd") as GDScript
	var cr_want: String = "AN_ThiefNisha_Zipwire__Reload_Loop"
	var cr_spec: Dictionary = cr_lib_scr.FP_TOOL_CLIPS.get("zipwire_crank", {}) as Dictionary
	var cr_table_ok: bool = str(cr_spec.get("clip", "")) == cr_want and cr_spec.get("loop", false) == true
	var cr_manifest_ok: bool = false
	var cr_mf: FileAccess = FileAccess.open("res://data/generated/anims_manifest.json", FileAccess.READ)
	if cr_mf != null:
		var cr_parsed: Variant = JSON.parse_string(cr_mf.get_as_text())
		if cr_parsed is Dictionary:
			for cr_e: Variant in ((cr_parsed as Dictionary).get("entries", []) as Array):
				if cr_e is Dictionary and str((cr_e as Dictionary).get("animation", "")) == cr_want:
					cr_manifest_ok = true
					break
	var cr_li: RefCounted = cr_lib_scr.new() as RefCounted
	var cr_resolve_ok: bool = str(cr_li.call("fp_clip_for_role", "zipwire_crank")) == cr_want
	var cr_role_ok: bool = false
	var cr_play_ok: bool = false
	var cr_p: Node = cr_thief_scr.new()
	root.add_child(cr_p)
	await process_frame
	if is_instance_valid(cr_p) and cr_p.has_method("_select_fp_anim_role") and cr_p.has_method("_begin_wire_crank") and cr_p.has_method("_play_wire_crank_clip"):
		cr_p.set("_is_cranking", true)
		cr_role_ok = str(cr_p.call("_select_fp_anim_role", false)) == "zipwire_crank"
		# Attached hang reuses the same in-frame pair: crank while cranking,
		# cast idle while holding. A winch + crank also returns the crank clip
		# (the out-of-frame travel clip is never selected).
		cr_p.set("is_grappling", true)
		var cr_role_winch: String = str(cr_p.call("_select_fp_anim_role", false))
		cr_p.set("is_grappling", false)
		cr_p.set("_is_cranking", false)
		cr_p.set("is_wire_hanging", true)
		var cr_role_hang_idle: String = str(cr_p.call("_select_fp_anim_role", false))
		cr_p.set("_is_cranking", true)
		var cr_role_hang_crank: String = str(cr_p.call("_select_fp_anim_role", false))
		cr_p.set("is_wire_hanging", false)
		cr_p.set("_is_cranking", false)
		cr_role_ok = cr_role_ok and cr_role_winch == "zipwire_crank" \
			and cr_role_hang_idle == "zipwire_cast_idle" \
			and cr_role_hang_crank == "zipwire_crank"
		# Synthetic live playback: seed the resolve cache, attach a player
		# carrying the crank clip, then crank; current_animation must follow.
		(cr_li.get("applied") as Dictionary)["zipwire_crank"] = cr_want
		cr_p.set("_fp_anim_lib", cr_li)
		var cr_player := AnimationPlayer.new()
		cr_p.add_child(cr_player)
		var cr_anim_lib := AnimationLibrary.new()
		var cr_dummy := Animation.new()
		cr_dummy.set_length(1.2)
		cr_dummy.set_loop_mode(Animation.LOOP_LINEAR)
		cr_anim_lib.add_animation(cr_want, cr_dummy)
		cr_player.add_animation_library("", cr_anim_lib)
		cr_p.set("fp_anim_player", cr_player)
		cr_p.set("_fp_use_real_arms", true)
		cr_p.call("_begin_wire_crank")
		await process_frame
		if is_instance_valid(cr_player):
			cr_play_ok = cr_player.current_animation == cr_want and cr_player.is_playing()
		cr_p.call("_end_wire_crank")
	cr_p.queue_free()
	await process_frame
	if not cr_table_ok or not cr_manifest_ok or not cr_resolve_ok or not cr_role_ok or not cr_play_ok:
		printerr("FAIL: 43 zipwire crank clip (table=", cr_table_ok, " manifest=", cr_manifest_ok, " resolve=", cr_resolve_ok, " role=", cr_role_ok, " plays=", cr_play_ok, ")")
		fails += 1
	else:
		print("PASS: 43 zipwire crank ", cr_want, " resolves via ensure_fp_clip and plays on crank")

	# 44. (removed) This suite asserted that the E2E runner contained the
	# in-memory triage patches for stale tier-1 expectations. That patching is
	# masking, deleted in Phase 12; the stale expectations are fixed on disk in
	# tests/e2e instead.

	# 45. Stairs: authored 60 deg max angle + 0.25-0.3 snap, wall-block/constant
	# speed kept. W5A replaced the 50 deg / 0.18-0.28 m retune with the authored
	# values: WalkableFloorAngle 60, MaxStepHeight 45 cm, capsule half-height
	# 0.91 m, and the civic flight measures 0.25 m risers on 0.33 m treads
	# (37.1 deg). The walk itself is tests/test_stair_walk.gd; this suite pins
	# the contracts the fix depends on.
	var stair_scr: GDScript = load("res://src/player/thief_character.gd") as GDScript
	var ss_thief: CharacterBody3D = stair_scr.new() as CharacterBody3D
	ss_thief.set_physics_process(false)
	root.add_child(ss_thief)
	await process_frame
	await physics_frame
	var ss_consts: Dictionary = stair_scr.get_script_constant_map()
	var ss_angle_const: float = float(ss_consts.get("FLOOR_MAX_ANGLE_DEG", -1.0))
	var ss_snap_const: float = float(ss_consts.get("FLOOR_SNAP_LENGTH", -1.0))
	var ss_mantle_const: float = float(ss_consts.get("MANTLE_MAX_HEIGHT_M", -1.0))
	var ss_angle_ok: bool = is_equal_approx(ss_angle_const, 60.0) and is_equal_approx(rad_to_deg(ss_thief.floor_max_angle), 60.0)
	var ss_snap_ok: bool = ss_snap_const >= 0.25 and ss_snap_const <= 0.300001 and ss_thief.floor_snap_length >= 0.249999 and ss_thief.floor_snap_length <= 0.300001 and is_equal_approx(ss_thief.floor_snap_length, ss_snap_const)
	var ss_flags_ok: bool = ss_thief.floor_block_on_wall == true and ss_thief.floor_constant_speed == true
	var ss_mantle_ok: bool = is_equal_approx(ss_mantle_const, 4.0)
	var ss_txt: String = ""
	var ss_f: FileAccess = FileAccess.open("res://src/player/thief_character.gd", FileAccess.READ)
	if ss_f != null:
		ss_txt = ss_f.get_as_text()
	var ss_no_mantle_ok: bool = ss_txt.find("stair_mantle") < 0 and ss_txt.find("STAIR_MANTLE") < 0
	# W5A step contracts: MaxStepHeight 0.45 m, 0.20 m probe reach past the
	# capsule surface, authored 0.91 m half-height capsule (1.82 m total), and
	# the mantle gate band above step height.
	var ss_step_ok: bool = is_equal_approx(float(ss_consts.get("STEP_UP_MAX_M", -1.0)), 0.45) \
		and is_equal_approx(float(ss_consts.get("STEP_UP_FORWARD_M", -1.0)), 0.20) \
		and is_equal_approx(float(ss_consts.get("CAPSULE_HALF_HEIGHT_M", -1.0)), 0.91) \
		and is_equal_approx(float(ss_consts.get("MANTLE_STEP_GUARD_M", -1.0)), 0.05)
	var ss_cap: CapsuleShape3D = null
	var ss_cshape: CollisionShape3D = ss_thief.get("col_shape") as CollisionShape3D
	if ss_cshape != null:
		ss_cap = ss_cshape.shape as CapsuleShape3D
	var ss_capsule_ok: bool = ss_cap != null and is_equal_approx(ss_cap.height, 1.82) and is_equal_approx(ss_cap.radius, 0.32) \
		and ss_cshape != null and is_equal_approx(ss_cshape.position.y, 0.91)
	# W6M body/capsule contract: body_height_m() feeds the device detector/beam
	# segment, so it must report the built 1.82 m capsule (W5A rebuilt the body
	# but left the constant at the port's 1.78 m).
	var ss_body_h: float = float(ss_thief.call("body_height_m"))
	var ss_body_ok: bool = is_equal_approx(float(ss_consts.get("BODY_HEIGHT_STANDING", -1.0)), 1.82) \
		and is_equal_approx(ss_body_h, 1.82)
	# W6M blocker contract (T1-10-J style, at the step-up): a 0.40 m designer
	# blocking volume sits inside MaxStepHeight, so the floor probe used to find
	# its top and step onto it. The same box without the group must still step.
	var ss_bg := StaticBody3D.new()
	ss_bg.collision_layer = 1
	ss_bg.collision_mask = 0
	var ss_bg_cs := CollisionShape3D.new()
	var ss_bg_box := BoxShape3D.new()
	ss_bg_box.size = Vector3(6.0, 0.4, 3.6)
	ss_bg_cs.shape = ss_bg_box
	ss_bg.add_child(ss_bg_cs)
	root.add_child(ss_bg)
	ss_bg.global_position = Vector3(70.0, -0.2, 72.2)
	var ss_blk := StaticBody3D.new()
	ss_blk.collision_layer = 1
	ss_blk.collision_mask = 0
	var ss_blk_cs := CollisionShape3D.new()
	var ss_blk_box := BoxShape3D.new()
	ss_blk_box.size = Vector3(6.0, 0.4, 4.4)
	ss_blk_cs.shape = ss_blk_box
	ss_blk.add_child(ss_blk_cs)
	ss_blk.add_to_group("blocking_volume")
	root.add_child(ss_blk)
	ss_blk.global_position = Vector3(70.0, 0.2, 68.2)
	ss_thief.global_position = Vector3(70.0, 0.02, 70.70)
	await physics_frame
	await physics_frame
	var ss_blk_rise: float = float(ss_thief.call("_try_step_up", Vector3(0.0, 0.0, -3.6)))
	ss_blk.remove_from_group("blocking_volume")
	var ss_vis_rise: float = float(ss_thief.call("_try_step_up", Vector3(0.0, 0.0, -3.6)))
	# Assert the destination, not the returned delta. `_try_step_up` commits
	# `global_position.y = floor_y`, so the box top is the contract; the delta is
	# measured from wherever gravity has settled the body (0.4154 when it sits
	# 0.0154 below the origin), which made this flake after the W10-A collision
	# change. The W10-A stair fixtures use the same destination assertion.
	var ss_vis_dest: float = float(ss_thief.global_position.y)
	var ss_blocker_ok: bool = is_zero_approx(ss_blk_rise) and absf(ss_vis_dest - 0.40) <= 0.01
	ss_bg.queue_free()
	ss_blk.queue_free()
	await physics_frame
	ss_thief.global_position = Vector3(60, 0.02, 60)
	var ss_stair_deg: float = rad_to_deg(atan2(0.25, 0.33))
	var ss_stair_ok: bool = ss_stair_deg < ss_angle_const and ss_snap_const >= 0.2
	var ss_base := Vector3(50, 0, 50)
	var ss_slope35 := StaticBody3D.new()
	ss_slope35.position = ss_base + Vector3(0, -0.1, 0)
	ss_slope35.rotation.x = deg_to_rad(35.0)
	var ss_cs35 := CollisionShape3D.new()
	var ss_box35 := BoxShape3D.new()
	ss_box35.size = Vector3(10, 0.2, 10)
	ss_cs35.shape = ss_box35
	ss_slope35.add_child(ss_cs35)
	root.add_child(ss_slope35)
	var ss_b35 := CharacterBody3D.new()
	var ss_cap35 := CollisionShape3D.new()
	var ss_sh35 := CapsuleShape3D.new()
	ss_sh35.radius = 0.32
	ss_sh35.height = 1.82
	ss_cap35.shape = ss_sh35
	ss_cap35.position = Vector3(0, 0.91, 0)
	ss_b35.add_child(ss_cap35)
	root.add_child(ss_b35)
	ss_b35.floor_max_angle = ss_thief.floor_max_angle
	ss_b35.floor_snap_length = ss_thief.floor_snap_length
	ss_b35.floor_block_on_wall = true
	ss_b35.floor_constant_speed = true
	ss_b35.position = ss_base + Vector3(0, 2.0, 0)
	for ss_i in range(60):
		await physics_frame
		ss_b35.velocity = Vector3(0, -5.0, 0)
		ss_b35.move_and_slide()
	var ss_walk_ok: bool = ss_b35.is_on_floor()
	var ss_y35: float = ss_b35.global_position.y
	ss_b35.queue_free()
	ss_slope35.queue_free()
	await physics_frame
	var ss_slope70 := StaticBody3D.new()
	ss_slope70.position = ss_base + Vector3(0, -0.1, 0)
	ss_slope70.rotation.x = deg_to_rad(70.0)
	var ss_cs70 := CollisionShape3D.new()
	var ss_box70 := BoxShape3D.new()
	ss_box70.size = Vector3(10, 0.2, 10)
	ss_cs70.shape = ss_box70
	ss_slope70.add_child(ss_cs70)
	root.add_child(ss_slope70)
	var ss_b70 := CharacterBody3D.new()
	var ss_cap70 := CollisionShape3D.new()
	var ss_sh70 := CapsuleShape3D.new()
	ss_sh70.radius = 0.32
	ss_sh70.height = 1.82
	ss_cap70.shape = ss_sh70
	ss_cap70.position = Vector3(0, 0.91, 0)
	ss_b70.add_child(ss_cap70)
	root.add_child(ss_b70)
	ss_b70.floor_max_angle = ss_thief.floor_max_angle
	ss_b70.floor_snap_length = ss_thief.floor_snap_length
	ss_b70.floor_block_on_wall = true
	ss_b70.floor_constant_speed = true
	ss_b70.position = ss_base + Vector3(0, 2.0, 0)
	for ss_j in range(60):
		await physics_frame
		ss_b70.velocity = Vector3(0, -5.0, 0)
		ss_b70.move_and_slide()
	var ss_steep_ok: bool = not ss_b70.is_on_floor()
	var ss_y70: float = ss_b70.global_position.y
	var ss_live_deg: float = rad_to_deg(ss_thief.floor_max_angle)
	var ss_live_snap: float = ss_thief.floor_snap_length
	ss_b70.queue_free()
	ss_slope70.queue_free()
	ss_thief.queue_free()
	await physics_frame
	if not ss_angle_ok or not ss_snap_ok or not ss_flags_ok or not ss_mantle_ok or not ss_no_mantle_ok or not ss_stair_ok or not ss_walk_ok or not ss_steep_ok or not ss_step_ok or not ss_capsule_ok or not ss_body_ok or not ss_blocker_ok:
		printerr("FAIL: 45 stairs (step_ok=", ss_step_ok, " capsule_ok=", ss_capsule_ok, " body_ok=", ss_body_ok, " blocker_ok=", ss_blocker_ok, " blocker_rise=", ss_blk_rise, " visible_rise=", ss_vis_rise, " angle_const=", ss_angle_const, " live_deg=", ss_live_deg, " snap_const=", ss_snap_const, " live_snap=", ss_live_snap, " flags=", ss_flags_ok, " mantle4=", ss_mantle_ok, " no_new_mantle=", ss_no_mantle_ok, " stair_deg=", ss_stair_deg, " walk35=", ss_walk_ok, " y35=", ss_y35, " steep70_blocked=", ss_steep_ok, " y70=", ss_y70, ")")
		fails += 1
	else:
		print("PASS: 45 stairs (max_angle ", ss_angle_const, " deg, snap ", ss_snap_const, " m, capsule ", snappedf(ss_cap.height, 0.01) if ss_cap != null else -1.0, " m, body_height_m ", snappedf(ss_body_h, 0.01), " m, step ", ss_consts.get("STEP_UP_MAX_M", -1.0), " m + ", ss_consts.get("STEP_UP_FORWARD_M", -1.0), " m probe, blocker 0.40 m refused, visible 0.40 m steps ", snappedf(ss_vis_rise, 0.01), " m, civic flight ", snappedf(ss_stair_deg, 0.1), " deg walkable, 70 deg blocked, wall-block/constant-speed kept, no new mantle)")

	# 46. Den doors collision (leaf disabled past 70 deg) + Den window-wall gap.
	var dd_ld: Node = (load("res://src/interact/lockable_door.gd") as GDScript).new()
	root.add_child(dd_ld)
	await process_frame
	await physics_frame
	var dd_leaf: Node = dd_ld.get("_leaf_body") as Node
	var dd_cshape: CollisionShape3D = dd_ld.get("_leaf_shape") as CollisionShape3D
	var dd_leaf_ok: bool = dd_leaf is AnimatableBody3D and bool(dd_leaf.get("sync_to_physics")) and dd_cshape != null
	var dd_open_ok: bool = false
	var dd_close_ok: bool = false
	var dd_gate_ok: bool = false
	if dd_leaf_ok:
		dd_gate_ok = bool(dd_ld.call("should_disable_leaf", 80.0)) and not bool(dd_ld.call("should_disable_leaf", 0.0))
		var dd_piv: Node3D = dd_ld.get("pivot") as Node3D
		if dd_piv != null:
			dd_piv.rotation.y = deg_to_rad(80.0)
			dd_ld.call("_update_leaf_collision")
			await process_frame
			await physics_frame
			dd_open_ok = dd_cshape.disabled == true and int(dd_leaf.get("collision_layer")) == 0
			dd_piv.rotation.y = 0.0
			dd_ld.call("_update_leaf_collision")
			await process_frame
			await physics_frame
			dd_close_ok = dd_cshape.disabled == false and int(dd_leaf.get("collision_layer")) == 1
	dd_ld.queue_free()
	await process_frame
	var dd_sd: Node = (load("res://src/interact/swinging_door.gd") as GDScript).new()
	var dd_sd_consts: Dictionary = (load("res://src/interact/swinging_door.gd") as GDScript).get_script_constant_map()
	var dd_sd_gate: bool = bool(dd_sd.call("should_disable_leaf", 80.0)) and not bool(dd_sd.call("should_disable_leaf", 0.0)) and is_equal_approx(float(dd_sd_consts.get("OPEN_DISABLE_DEG", -1.0)), 70.0)
	var dd_sd_src: String = ""
	var dd_sd_file: FileAccess = FileAccess.open("res://src/interact/swinging_door.gd", FileAccess.READ)
	if dd_sd_file != null:
		dd_sd_src = dd_sd_file.get_as_text()
	var dd_sd_leafcode: bool = dd_sd_src.find("AnimatableBody3D") >= 0 and dd_sd_src.find("sync_to_physics") >= 0
	dd_sd.queue_free()
	var dd_ll2: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(dd_ll2)
	await process_frame
	var dd_spec: Dictionary = dd_ll2.call("den_window_gap_spec") as Dictionary
	var dd_gap: float = float(dd_spec.get("gap_m", -1.0))
	var dd_gap_ok: bool = dd_gap >= 0.9 and dd_gap <= 1.0 \
		and is_equal_approx(float(dd_spec.get("sill_top_m", -1.0)), 0.9) \
		and is_equal_approx(float(dd_spec.get("lintel_bottom_m", -1.0)), 2.0) \
		and bool(dd_spec.get("marker_gate_kept", false)) \
		and int(dd_spec.get("boxes", 0)) >= 2
	var dd_is_den: bool = bool(dd_ll2.call("_is_den_window_wall", "sm_thievesden_glass")) \
		and not bool(dd_ll2.call("_is_den_window_wall", "sm_facadelrga_base")) \
		and not bool(dd_ll2.call("_is_den_window_wall", "guildhall_wall_stone"))
	var dd_host := Node3D.new()
	root.add_child(dd_host)
	var dd_ctx: Dictionary = dd_ll2.call("_new_build_ctx", dd_host, null, true) as Dictionary
	var dd_box := BoxShape3D.new()
	dd_box.size = Vector3(4.0, 3.0, 0.3)
	var dd_before: int = int(dd_ctx.get("collision_shapes", 0))
	dd_ll2.call("_add_den_window_split", dd_ctx, Vector2i.ZERO, Transform3D.IDENTITY, dd_box, Vector3.ZERO)
	var dd_split_ok: bool = int(dd_ctx.get("collision_shapes", 0)) - dd_before == 4
	# 46b. Mirrored door leaves: the mirror branch must test the composed
	# door-root x leaf basis. A negative determinant there means the authored
	# pairing mirrors the mesh, so every BaseMaterial3D surface gets a
	# CULL_DISABLED duplicate; the identity control stays single-sided.
	var dd_mirror_ok: bool = false
	var dd_ctrl_ok: bool = false
	# Old Manor interior door: 3 authored single-sided StandardMaterial3D
	# surfaces, so the identity control is a meaningful negative.
	var dd_mirror_ue: String = "/Game/Art/Environment/OldManor/SM_OldManor_Door_1x3"
	var dd_mirror_info: Dictionary = dd_ll2.call("_get_mesh_and_shape", dd_mirror_ue) as Dictionary
	var dd_mirror_mesh: Mesh = dd_mirror_info.get("mesh") as Mesh
	if dd_mirror_mesh != null:
		var dd_mirror_scr: GDScript = load("res://src/interact/swinging_door.gd") as GDScript
		var dd_mirror_leaf: Dictionary = {
			"mesh": dd_mirror_ue,
			"rel_pos": [0.0, 0.0, 0.0],
			"rel_basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
			"rel_scale": [1.0, 1.0, 1.0],
		}
		var dd_mirror_door: Node = dd_mirror_scr.new() as Node
		dd_mirror_door.call("configure", {
			"pos": [7000.0, 0.0, 7000.0],
			"basis": [-1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
			"leaves": [dd_mirror_leaf],
		}, dd_ll2)
		root.add_child(dd_mirror_door)
		await process_frame
		var dd_mirror_piv: Node3D = dd_mirror_door.get_node_or_null("DoorPivot") as Node3D
		var dd_mirror_mi: MeshInstance3D = null
		if dd_mirror_piv != null:
			for ch_v: Variant in dd_mirror_piv.get_children():
				if ch_v is MeshInstance3D:
					dd_mirror_mi = ch_v as MeshInstance3D
					break
		if dd_mirror_mi != null and dd_mirror_mi.mesh != null:
			var dd_mirror_composed: float = (dd_mirror_door as Node3D).transform.basis.determinant() * dd_mirror_mi.transform.basis.determinant()
			var dd_mirror_surfaces: int = 0
			var dd_mirror_culled: int = 0
			for s_dm: int in range(dd_mirror_mi.mesh.get_surface_count()):
				var dd_mirror_src: Material = dd_mirror_mi.mesh.surface_get_material(s_dm)
				if dd_mirror_src is BaseMaterial3D:
					dd_mirror_surfaces += 1
					var dd_mirror_ov: Material = dd_mirror_mi.get_surface_override_material(s_dm)
					if dd_mirror_ov is BaseMaterial3D and (dd_mirror_ov as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED:
						dd_mirror_culled += 1
			dd_mirror_ok = dd_mirror_composed < 0.0 and dd_mirror_surfaces > 0 and dd_mirror_culled == dd_mirror_surfaces
		# Non-mirrored control: same mesh/materials, identity door basis.
		var dd_ctrl_door: Node = dd_mirror_scr.new() as Node
		dd_ctrl_door.call("configure", {
			"pos": [7200.0, 0.0, 7000.0],
			"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
			"leaves": [dd_mirror_leaf],
		}, dd_ll2)
		root.add_child(dd_ctrl_door)
		await process_frame
		var dd_ctrl_piv: Node3D = dd_ctrl_door.get_node_or_null("DoorPivot") as Node3D
		var dd_ctrl_mi: MeshInstance3D = null
		if dd_ctrl_piv != null:
			for ch2_v: Variant in dd_ctrl_piv.get_children():
				if ch2_v is MeshInstance3D:
					dd_ctrl_mi = ch2_v as MeshInstance3D
					break
		if dd_ctrl_mi != null and dd_ctrl_mi.mesh != null:
			var dd_ctrl_composed: float = (dd_ctrl_door as Node3D).transform.basis.determinant() * dd_ctrl_mi.transform.basis.determinant()
			var dd_ctrl_surfaces: int = 0
			var dd_ctrl_two_sided: int = 0
			for s_dc: int in range(dd_ctrl_mi.mesh.get_surface_count()):
				var dd_ctrl_src: Material = dd_ctrl_mi.mesh.surface_get_material(s_dc)
				if dd_ctrl_src is BaseMaterial3D:
					dd_ctrl_surfaces += 1
					var dd_ctrl_eff: Material = dd_ctrl_mi.get_surface_override_material(s_dc)
					if dd_ctrl_eff == null:
						dd_ctrl_eff = dd_ctrl_src
					if dd_ctrl_eff is BaseMaterial3D and (dd_ctrl_eff as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED:
						dd_ctrl_two_sided += 1
			dd_ctrl_ok = dd_ctrl_composed > 0.0 and dd_ctrl_surfaces > 0 and dd_ctrl_two_sided == 0
		dd_mirror_door.queue_free()
		dd_ctrl_door.queue_free()
		await process_frame
	dd_host.queue_free()
	dd_ll2.queue_free()
	await process_frame
	if not dd_leaf_ok or not dd_open_ok or not dd_close_ok or not dd_gate_ok or not dd_sd_gate or not dd_sd_leafcode or not dd_gap_ok or not dd_is_den or not dd_split_ok or not dd_mirror_ok or not dd_ctrl_ok:
		printerr("FAIL: 46 Den doors/window (leaf_anim=", dd_leaf_ok, " open_dis=", dd_open_ok, " close_re=", dd_close_ok, " gate=", dd_gate_ok, " swing_gate=", dd_sd_gate, " swing_code=", dd_sd_leafcode, " gap=", dd_gap_ok, " gap_m=", dd_gap, " is_den=", dd_is_den, " split4=", dd_split_ok, " mirrored=", dd_mirror_ok, " ctrl=", dd_ctrl_ok, ")")
		fails += 1
	else:
		print("PASS: 46 Den doors leaf disabled past 70 deg (layer 0 + disabled, re-enabled on close) & window wall split gap=", dd_gap, "m + sill + lintel (2m marker gate kept) & mirrored leaf CULL_DISABLED (control single-sided)")

	# 47. P1-9(a): every contract (not just the booted 3/1/4) resolves
	# title/map/loot at data level. Runtime boot of all 18 is suite-cost
	# prohibitive (see HARD_LIMIT in task-p1-pipeline.md); this gates the
	# wiring the boot depends on: contiguity, titles, map ids, loot actors.
	var c47_bad: Array = []
	var c47_notes: Array = []
	var c47_orders: Array = []
	var c47_loot_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/gameplay/loot_actors.json"))
	var c47_tag_to_actor: Dictionary = {}
	var c47_generic: String = ""
	if c47_loot_doc is Dictionary:
		var c47_tta_v: Variant = (c47_loot_doc as Dictionary).get("tag_to_actor", {})
		if c47_tta_v is Dictionary:
			c47_tag_to_actor = c47_tta_v as Dictionary
		var c47_fb_v: Variant = (c47_loot_doc as Dictionary).get("fallback", {})
		if c47_fb_v is Dictionary:
			c47_generic = str((c47_fb_v as Dictionary).get("generic_quest_actor", ""))
	if c47_tag_to_actor.is_empty() or c47_generic == "":
		c47_bad.append("loot_actors.json tag map or generic fallback unreadable")
	for c47_c: Variant in gd.contracts:
		if not (c47_c is Dictionary):
			c47_bad.append("non-dict contract entry")
			continue
		var c47_cd: Dictionary = c47_c as Dictionary
		var c47_order: int = int(c47_cd.get("order", -1))
		# Shipped data bug (mirrors parse_contracts.py repair): Contract.Main.15
		# carries ContractOrder 0; the row key is authoritative. Named here,
		# never silently assumed.
		if c47_order <= 0:
			var c47_parts: PackedStringArray = str(c47_cd.get("id", "")).split(".")
			if c47_parts.size() == 3 and c47_parts[2].is_valid_int():
				c47_order = int(c47_parts[2])
			c47_notes.append("%s -> %d (raw ContractOrder 0)" % [str(c47_cd.get("id", "")), c47_order])
		c47_orders.append(c47_order)
		var c47_disp: Dictionary = gd.get_contract_display(c47_order)
		var c47_title: String = str(c47_disp.get("title", ""))
		var c47_map: String = str(c47_cd.get("map_id", ""))
		var c47_loot: String = str(c47_cd.get("loot_tag", ""))
		var c47_subs: Array = []
		var c47_subs_v: Variant = c47_cd.get("sublevels", [])
		if c47_subs_v is Array:
			c47_subs = c47_subs_v as Array
		var c47_stag: String = str(c47_cd.get("sublevel_tag", ""))
		var c47_loot_ok: bool = c47_loot != "" and (c47_tag_to_actor.has(c47_loot) or c47_generic != "")
		if c47_title == "":
			c47_bad.append("order=%d empty title" % c47_order)
		if c47_map == "":
			c47_bad.append("order=%d empty map_id" % c47_order)
		if not c47_loot_ok:
			c47_bad.append("order=%d loot_tag unresolvable: %s" % [c47_order, c47_loot])
		if not c47_subs.is_empty() and c47_stag == "":
			c47_bad.append("order=%d sublevels without sublevel_tag" % c47_order)
	c47_orders.sort()
	var c47_expect: Array = []
	for c47_i: int in range(1, gd.contracts.size() + 1):
		c47_expect.append(c47_i)
	if c47_orders != c47_expect:
		c47_bad.append("contract orders not contiguous 1..%d" % gd.contracts.size())
	if not c47_bad.is_empty():
		printerr("FAIL: 47 all-contracts sweep (", "; ".join(PackedStringArray(c47_bad.slice(0, 8))), ")")
		fails += 1
	else:
		print("PASS: 47 all ", gd.contracts.size(), " contracts resolve title/map/loot_tag (generic=", c47_generic, ") repairs: ", ", ".join(PackedStringArray(c47_notes)))

	# 48. P1-7/P1-6: spawner approximations pinned to the implementation they
	# document, and the alerted/combat fallback pinned to the authored BP.
	var sp48_ok: bool = true
	var sp48_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/gameplay/spawners.json"))
	var sp48_approx: Dictionary = {}
	if sp48_doc is Dictionary:
		var sp48_av: Variant = (sp48_doc as Dictionary).get("approximations", {})
		if sp48_av is Dictionary:
			sp48_approx = sp48_av as Dictionary
	for sp48_k: String in ["health_heal_amount", "ammo_refill_amount", "bottle_throw_speed_m_s", "bottle_impact_noise_m", "civilian_walk_speed_m_s"]:
		if not sp48_approx.has(sp48_k):
			printerr("FAIL: 48 spawners.json approximations missing key: ", sp48_k)
			sp48_ok = false
	var sp48_rx := RegEx.new()
	sp48_rx.compile("\\d+\\.\\d+")
	var tb48_consts: Dictionary = (load("res://src/interact/thrown_bottle.gd") as GDScript).get_script_constant_map()
	var civ48_consts: Dictionary = (load("res://src/ai/civilian_npc.gd") as GDScript).get_script_constant_map()
	var pk48_consts: Dictionary = (load("res://src/interact/world_pickup.gd") as GDScript).get_script_constant_map()
	var tb48_speed: float = float(tb48_consts.get("THROW_SPEED_M_S", -1.0))
	var tb48_noise: float = float(tb48_consts.get("IMPACT_NOISE_M", -1.0))
	var civ48_walk: float = float(civ48_consts.get("WALK_SPEED_M_S", -1.0))
	var tb48_m: RegExMatch = sp48_rx.search(str(sp48_approx.get("bottle_throw_speed_m_s", "")))
	var tb48_n: RegExMatch = sp48_rx.search(str(sp48_approx.get("bottle_impact_noise_m", "")))
	var civ48_m: RegExMatch = sp48_rx.search(str(sp48_approx.get("civilian_walk_speed_m_s", "")))
	var tb48_doc_speed: float = float(tb48_m.get_string()) if tb48_m != null else -1.0
	var tb48_doc_noise: float = float(tb48_n.get_string()) if tb48_n != null else -1.0
	var civ48_doc_walk: float = float(civ48_m.get_string()) if civ48_m != null else -1.0
	if not is_equal_approx(tb48_speed, 12.0) or not is_equal_approx(tb48_doc_speed, tb48_speed):
		printerr("FAIL: 48 bottle throw speed const/doc mismatch: const=", tb48_speed, " doc=", tb48_doc_speed)
		sp48_ok = false
	if not is_equal_approx(tb48_noise, 10.0) or not is_equal_approx(tb48_doc_noise, tb48_noise):
		printerr("FAIL: 48 bottle impact noise const/doc mismatch: const=", tb48_noise, " doc=", tb48_doc_noise)
		sp48_ok = false
	if not is_equal_approx(civ48_walk, 1.4) or not is_equal_approx(civ48_doc_walk, civ48_walk):
		printerr("FAIL: 48 civilian walk speed const/doc mismatch: const=", civ48_walk, " doc=", civ48_doc_walk)
		sp48_ok = false
	var pk48_scr: GDScript = load("res://src/interact/world_pickup.gd") as GDScript
	var pk48_max: Dictionary = {}
	var pk48_max_v: Variant = pk48_consts.get("AMMO_REFILL_MAX", {})
	if pk48_max_v is Dictionary:
		pk48_max = pk48_max_v as Dictionary
	# THROWABLE=0: +1 bottle. AMMO=1: refill every charge key to its max.
	# HEALTH=2: full-HP restore (the documented no-heal-amount approximation).
	var mk48_throw: Node = P1MockActor.new()
	var pk48_throw: Node = pk48_scr.new()
	pk48_throw.call("setup", 0, "")
	pk48_throw.call("interact", mk48_throw)
	if int((mk48_throw.get("charges") as Dictionary).get("bottle", -1)) != 1:
		printerr("FAIL: 48 throwable pickup did not +1 bottle")
		sp48_ok = false
	var mk48_ammo: Node = P1MockActor.new()
	var pk48_ammo: Node = pk48_scr.new()
	pk48_ammo.call("setup", 1, "")
	pk48_ammo.call("interact", mk48_ammo)
	for pk48_k: Variant in pk48_max.keys():
		if int((mk48_ammo.get("charges") as Dictionary).get(pk48_k, -999)) != int(pk48_max[pk48_k]):
			printerr("FAIL: 48 ammo refill key not restored to max: ", pk48_k)
			sp48_ok = false
	var mk48_hp: Node = P1MockActor.new()
	mk48_hp.set("health", 20.0)
	var pk48_hp: Node = pk48_scr.new()
	pk48_hp.call("setup", 2, "")
	pk48_hp.call("interact", mk48_hp)
	if not is_equal_approx(float(mk48_hp.get("health")), float(mk48_hp.get("max_health"))):
		printerr("FAIL: 48 health pack did not restore full HP")
		sp48_ok = false
	# These mock actors/pickups are never parented to the tree; unparented
	# Nodes are not auto-freed and leaked at exit (suite 48 hygiene).
	for pk48_node: Node in [mk48_throw, pk48_throw, mk48_ammo, pk48_ammo, mk48_hp, pk48_hp]:
		if is_instance_valid(pk48_node) and not pk48_node.is_queued_for_deletion():
			pk48_node.free()
	# Alerted/combat fallback: BP-authored MaxWalkSpeed/100 == state_speeds == guard const.
	var st48_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/gameplay/state_speeds.json"))
	var st48_fallback: float = -1.0
	if st48_doc is Dictionary:
		st48_fallback = float((st48_doc as Dictionary).get("alerted_combat_fallback_m_s", -1.0))
	var bp48_doc: Variant = _repo_json("extracted/json/Character/Guards/BP_Guard_Base.json")
	var bp48_walk: float = -1.0
	if bp48_doc is Array:
		for bp48_e: Variant in (bp48_doc as Array):
			if bp48_e is Dictionary and str((bp48_e as Dictionary).get("Type", "")) == "TATCharacterAIMovement" and str((bp48_e as Dictionary).get("Name", "")) == "CharMoveComp":
				var bp48_p: Variant = (bp48_e as Dictionary).get("Properties", {})
				if bp48_p is Dictionary:
					bp48_walk = float((bp48_p as Dictionary).get("MaxWalkSpeed", -1.0))
	var gd48_consts: Dictionary = (load("res://src/ai/guard_ai.gd") as GDScript).get_script_constant_map()
	var gd48_alerted: float = float(gd48_consts.get("ALERTED_SPEED", -1.0))
	if bp48_walk <= 0.0 or not is_equal_approx(st48_fallback, bp48_walk / 100.0) or not is_equal_approx(gd48_alerted, st48_fallback):
		printerr("FAIL: 48 alerted speed chain broken: BP=", bp48_walk, " state_speeds=", st48_fallback, " guard=", gd48_alerted)
		sp48_ok = false
	if not sp48_ok:
		fails += 1
	else:
		print("PASS: 48 spawner approximations pinned (throw 12.0/noise 10.0/walk 1.4, ammo refill-all, full-heal) & alerted=", st48_fallback, "m/s derived from BP ", bp48_walk)

	# 49. P1-9(b): save write/reload round-trip, corrupt-save fail-closed, and
	# schema-based nested merge. The real developer save is backed up first and
	# restored BEFORE every assertion, so a failed check cannot leave test
	# payload rows (or the nested-currency sentinel) in user://.
	var sv49_ok: bool = true
	var sv49: Node = root.get_node_or_null("/root/SaveSystem")
	var sv49_path: String = "user://tat2_save.json"
	if sv49 == null:
		printerr("FAIL: 49 SaveSystem missing")
		sv49_ok = false
	else:
		var sv49_had_file: bool = FileAccess.file_exists(sv49_path)
		var sv49_backup: String = FileAccess.get_file_as_string(sv49_path) if sv49_had_file else ""
		var sv49_backup_data: Dictionary = {}
		if sv49_had_file:
			var sv49_bp: Variant = JSON.parse_string(sv49_backup)
			if sv49_bp is Dictionary:
				sv49_backup_data = sv49_bp as Dictionary
		var sv49_backup_cc: Dictionary = (sv49_backup_data.get("completed_contracts", {}) as Dictionary).duplicate(true)
		print("INFO: 49 developer save before: completed_contracts=", sv49_backup_cc, " xp=", sv49_backup_data.get("xp", 0), " level=", sv49_backup_data.get("level", 1), " currency=", sv49_backup_data.get("currency", 0))
		var sv49_write_raw := func(text: String) -> bool:
			var f: FileAccess = FileAccess.open(sv49_path, FileAccess.WRITE)
			if f == null:
				return false
			f.store_string(text)
			f.close()
			return true
		# Reset the live dictionary before loading the real backup: loading on
		# top of a temporary payload kept its sentinel keys and persisted them.
		var sv49_restore := func() -> bool:
			sv49.set("data", sv49.call("_defaults"))
			if sv49_had_file:
				if not bool(sv49_write_raw.call(sv49_backup)):
					return false
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(sv49_path))
			sv49.call("load_save")
			return true
		var sv49_orig: int = int(sv49.call("get_currency"))
		sv49.call("add_currency", 7)
		sv49.call("load_save")
		if int(sv49.call("get_currency")) != sv49_orig + 7:
			printerr("FAIL: 49 currency did not survive write/reload")
			sv49_ok = false
		var sv49_post_add: String = FileAccess.get_file_as_string(sv49_path)
		if not bool(sv49_write_raw.call("{broken json,,")):
			printerr("FAIL: 49 could not write corrupt save")
			sv49_ok = false
		sv49.call("load_save")
		# RE-N-03: `currency >= 0` was vacuous (the defaults satisfy it). The
		# real contract is that a corrupt file is quarantined whole and this boot
		# does not mint a fresh profile over it: a failure is reported, the
		# original bytes survive under .corrupt-<ts>, and SAVE_PATH is gone.
		var sv49_quarantine: Array[String] = _t02_quarantine_files()
		var sv49_failure: Dictionary = sv49.call("get_load_failure") as Dictionary
		var sv49_quarantined_text: String = ""
		if not sv49_quarantine.is_empty():
			sv49_quarantined_text = FileAccess.get_file_as_string("user://" + sv49_quarantine[0])
		if not bool(sv49.call("has_load_failure")) \
				or str(sv49_failure.get("reason", "")) != "parse_error" \
				or sv49_quarantine.is_empty() \
				or not sv49_quarantined_text.contains("{broken json,,"):
			printerr("FAIL: 49 corrupt save was not quarantined whole: failure=", sv49_failure, " quarantine=", sv49_quarantine, " bytes=", sv49_quarantined_text)
			sv49_ok = false
		if FileAccess.file_exists(sv49_path):
			printerr("FAIL: 49 a corrupt load left/created a save at the live path (a fresh profile would overwrite the player's file)")
			sv49_ok = false
		for sv49_q: String in sv49_quarantine:
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + sv49_q))
		if not bool(sv49_write_raw.call(sv49_post_add)):
			printerr("FAIL: 49 could not restore post-add save")
			sv49_ok = false
		sv49.call("load_save")
		if int(sv49.call("get_currency")) != sv49_orig + 7:
			printerr("FAIL: 49 save backup restore mismatch")
			sv49_ok = false
		# 49b. Free-form nested dictionaries (completed_contracts schema {}):
		# keys merge into the nested dict and never into the root.
		var sv49_case_a: Dictionary = sv49.call("_defaults") as Dictionary
		sv49_case_a["xp"] = 1200
		sv49_case_a["completed_contracts"] = {"3": {"best_score": 900, "ghost": true}}
		if not bool(sv49_write_raw.call(JSON.stringify(sv49_case_a, "\t"))):
			printerr("FAIL: 49 could not write case A save")
			sv49_ok = false
		sv49.set("data", sv49.call("_defaults"))
		sv49.call("load_save")
		var sv49_data_a: Dictionary = sv49.get("data") as Dictionary
		var sv49_cc_a: Dictionary = (sv49_data_a.get("completed_contracts", {}) as Dictionary).duplicate(true)
		var sv49_xp_a: int = int(sv49_data_a.get("xp", 0))
		var sv49_level_a: int = int(sv49_data_a.get("level", 0))
		var sv49_currency_a: int = int(sv49_data_a.get("currency", -1))
		if not bool(sv49_restore.call()):
			printerr("FAIL: 49 could not restore the developer save after case A")
			sv49_ok = false
		var sv49_expected_cc: Dictionary = {"3": {"best_score": 900.0, "ghost": true}}
		# W9-P1: a fresh profile now starts at the authored FTUE bankroll
		# (project_settings project.ftue_min_thieves_den_money = 5000), so case A
		# carries the default 5000. Case A has a completed contract, so the
		# no-contract FTUE migration must not change it.
		var sv49_expected_currency: int = 5000
		if sv49_cc_a != sv49_expected_cc or sv49_xp_a != 1200 or sv49_level_a != 3 or sv49_currency_a != sv49_expected_currency:
			printerr("FAIL: 49 completed_contracts/xp/level/currency wrong after load: cc=", sv49_cc_a, " xp=", sv49_xp_a, " level=", sv49_level_a, " currency=", sv49_currency_a)
			sv49_ok = false
		# 49c. A nested key with the same name as a root key must not leak up.
		var sv49_case_b: Dictionary = sv49.call("_defaults") as Dictionary
		sv49_case_b["completed_contracts"] = {"currency": 5}
		if not bool(sv49_write_raw.call(JSON.stringify(sv49_case_b, "\t"))):
			printerr("FAIL: 49 could not write case B save")
			sv49_ok = false
		sv49.set("data", sv49.call("_defaults"))
		sv49.call("load_save")
		var sv49_data_b: Dictionary = sv49.get("data") as Dictionary
		var sv49_currency_b: int = int(sv49_data_b.get("currency", -1))
		var sv49_cc_b: Dictionary = (sv49_data_b.get("completed_contracts", {}) as Dictionary).duplicate(true)
		if not bool(sv49_restore.call()):
			printerr("FAIL: 49 could not restore the developer save after case B")
			sv49_ok = false
		# W9-P1: same authored default — a fresh profile is worth 5,000, and the
		# hand-written `completed_contracts.currency` row is non-empty, so the
		# no-contract FTUE migration must not touch it either.
		if sv49_currency_b != 5000 or sv49_cc_b != {"currency": 5.0}:
			printerr("FAIL: 49 nested completed_contracts.currency leaked or was dropped: currency=", sv49_currency_b, " cc=", sv49_cc_b)
			sv49_ok = false
		# 49d. Regression: a second load_save() into populated data still
		# accepts new completion keys and keeps the existing row.
		var sv49_twice_a: Dictionary = sv49.call("_defaults") as Dictionary
		sv49_twice_a["completed_contracts"] = {"3": {"best_score": 900, "ghost": true}}
		if not bool(sv49_write_raw.call(JSON.stringify(sv49_twice_a, "\t"))):
			printerr("FAIL: 49 could not write two-load save A")
			sv49_ok = false
		sv49.set("data", sv49.call("_defaults"))
		sv49.call("load_save")
		var sv49_twice_b: Dictionary = sv49.call("_defaults") as Dictionary
		sv49_twice_b["completed_contracts"] = {"4": {"best_score": 700, "ghost": false}}
		if not bool(sv49_write_raw.call(JSON.stringify(sv49_twice_b, "\t"))):
			printerr("FAIL: 49 could not write two-load save B")
			sv49_ok = false
		sv49.call("load_save")
		var sv49_cc_twice: Dictionary = ((sv49.get("data") as Dictionary).get("completed_contracts", {}) as Dictionary).duplicate(true)
		if not bool(sv49_restore.call()):
			printerr("FAIL: 49 could not restore the developer save after two-load regression")
			sv49_ok = false
		var sv49_expected_twice: Dictionary = {
			"3": {"best_score": 900.0, "ghost": true},
			"4": {"best_score": 700.0, "ghost": false},
		}
		if sv49_cc_twice != sv49_expected_twice:
			printerr("FAIL: 49 second load dropped rows: cc=", sv49_cc_twice, " expected=", sv49_expected_twice)
			sv49_ok = false
		# Final restore verification: the developer save's real rows and root
		# progression values must match the backup exactly (no sentinel leak).
		if not bool(sv49_restore.call()):
			printerr("FAIL: 49 could not restore the developer save at exit")
			sv49_ok = false
		var sv49_final_data: Dictionary = sv49.get("data") as Dictionary
		var sv49_final_cc: Dictionary = (sv49_final_data.get("completed_contracts", {}) as Dictionary).duplicate(true)
		var sv49_file_cc: Dictionary = {}
		if sv49_had_file:
			var sv49_file_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(sv49_path))
			if sv49_file_v is Dictionary:
				sv49_file_cc = ((sv49_file_v as Dictionary).get("completed_contracts", {}) as Dictionary).duplicate(true)
		print("INFO: 49 developer save after restore: completed_contracts=", sv49_final_cc, " file=", sv49_file_cc)
		if sv49_final_cc != sv49_backup_cc or sv49_file_cc != sv49_backup_cc:
			printerr("FAIL: 49 developer completed_contracts not restored: live=", sv49_final_cc, " file=", sv49_file_cc, " backup=", sv49_backup_cc)
			sv49_ok = false
		if int(sv49_final_data.get("xp", 0)) != int(sv49_backup_data.get("xp", 0)) \
				or int(sv49_final_data.get("level", 1)) != int(sv49_backup_data.get("level", 1)) \
				or int(sv49_final_data.get("currency", 0)) != int(sv49_backup_data.get("currency", 0)):
			printerr("FAIL: 49 developer xp/level/currency not restored: ", sv49_final_data.get("xp", 0), "/", sv49_final_data.get("level", 1), "/", sv49_final_data.get("currency", 0))
			sv49_ok = false
		if sv49_final_cc.has("currency") and not sv49_backup_cc.has("currency"):
			printerr("FAIL: 49 sentinel completed_contracts.currency leaked into the developer save")
			sv49_ok = false
	if not sv49_ok:
		fails += 1
	else:
		print("PASS: 49 save round-trip (+7 persisted, corrupt load fail-closed, full completed_contracts/xp/level kept, second load accepts new rows, developer save restored before assertions)")

	# 50. P1-9(c): audio audibility smoke. Block #1 only pins the autoload;
	# this pins that the gameplay one-shots resolve to real clips on disk.
	var au50_ok: bool = true
	var au50: Node = root.get_node_or_null("AudioManager")
	var au50_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/audio_events.json"))
	var au50_counts: Dictionary = {}
	var au50_tags: Dictionary = {}
	if au50_doc is Dictionary:
		var au50_cv: Variant = (au50_doc as Dictionary).get("counts", {})
		if au50_cv is Dictionary:
			au50_counts = au50_cv as Dictionary
		var au50_tv: Variant = (au50_doc as Dictionary).get("tags", {})
		if au50_tv is Dictionary:
			au50_tags = au50_tv as Dictionary
	if int(au50_counts.get("events_with_resolved_clip", 0)) < 1200:
		printerr("FAIL: 50 resolved audio events below floor: ", au50_counts.get("events_with_resolved_clip", 0))
		au50_ok = false
	if au50 == null:
		printerr("FAIL: 50 AudioManager missing")
		au50_ok = false
	else:
		for au50_tag: String in ["footstep", "blackjack", "lockpick", "grapple", "smoke", "fairy", "alert", "loot"]:
			if not bool(au50.call("has_real_clip", au50_tag)):
				printerr("FAIL: 50 no real clip for tag: ", au50_tag)
				au50_ok = false
			else:
				var au50_entry_v: Variant = au50_tags.get(au50_tag, {})
				if au50_entry_v is Dictionary:
					var au50_clip: String = str((au50_entry_v as Dictionary).get("clip", ""))
					if au50_clip == "" or not ResourceLoader.exists(au50_clip):
						printerr("FAIL: 50 clip file missing for tag ", au50_tag, ": ", au50_clip)
						au50_ok = false
	if not au50_ok:
		fails += 1
	else:
		print("PASS: 50 audio audibility (", au50_counts.get("events_with_resolved_clip", 0), " resolved events, 8 gameplay one-shots real)")

	# 51. P1-9(e): GLB-for-every-mesh_res. Mirrors level_loader _ue_mesh_to_res
	# (Content first, Raw Engine mirror for /Engine/ paths, .gltf second).
	# The 9 _GENERATED gjasp meshes are exported and imported (P1-1 queues
	# /_GENERATED/); the old allow-list that masked them is gone, so a missing
	# GLB is a real failure.
	var glb51_checked: Dictionary = {}
	var glb51_missing: Array = []
	var glb51_empty: int = 0
	var glb51_total: int = 0
	var glb51_files: Array = []
	_p1_collect_json("res://data/generated/levels", glb51_files)
	for glb51_f: String in glb51_files:
		var glb51_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(glb51_f))
		if not (glb51_doc is Dictionary):
			continue
		var glb51_meshes_v: Variant = (glb51_doc as Dictionary).get("meshes", [])
		if not (glb51_meshes_v is Array):
			continue
		for glb51_m: Variant in (glb51_meshes_v as Array):
			if not (glb51_m is Dictionary):
				continue
			var glb51_raw: Variant = (glb51_m as Dictionary).get("mesh", "")
			if glb51_raw == null:
				glb51_empty += 1
				continue
			var glb51_mp: String = str(glb51_raw)
			glb51_total += 1
			if glb51_mp == "":
				glb51_empty += 1
				continue
			var glb51_cand: String = ""
			if glb51_mp.begins_with("/Engine/"):
				glb51_cand = "res://assets/ue/Raw/Engine/Content/" + glb51_mp.substr("/Engine/".length()) + ".glb"
			elif glb51_mp.begins_with("/Game/"):
				glb51_cand = "res://assets/ue/Content/" + glb51_mp.substr("/Game/".length()) + ".glb"
			else:
				glb51_missing.append(glb51_mp + " (non-/Game non-/Engine path)")
				continue
			if glb51_checked.has(glb51_cand):
				continue
			glb51_checked[glb51_cand] = true
			if not ResourceLoader.exists(glb51_cand) and not ResourceLoader.exists(glb51_cand.get_basename() + ".gltf"):
				glb51_missing.append(glb51_mp)
	if glb51_empty > 0 or not glb51_missing.is_empty():
		printerr("FAIL: 51 GLB gate (total=", glb51_total, " empty=", glb51_empty, " missing=", glb51_missing.size(), "): ", "; ".join(PackedStringArray(glb51_missing.slice(0, 12))))
		fails += 1
	else:
		print("PASS: 51 GLB-for-every-mesh_res (", glb51_total, " refs, ", glb51_checked.size(), " unique, 0 allowlisted)")

	# 52. P1-9(d,f,g): guard transition data, VFX catalogue boundary, export
	# presence. Guard behavior stays in e2e tiers; here the transition
	# inputs (ramps + speeds) must equal the tables the AI reads.
	var gx52_ok: bool = true
	var gx52_det: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/gameplay/detection.json"))
	for gx52_ramp: String in ["neutral", "suspicious", "alerted", "combat"]:
		if not (gx52_det is Dictionary) or not (gx52_det as Dictionary).has(gx52_ramp):
			printerr("FAIL: 52 detection.json missing ramp: ", gx52_ramp)
			gx52_ok = false
	var gx52_speeds: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/gameplay/state_speeds.json"))
	var gx52_gconsts: Dictionary = (load("res://src/ai/guard_ai.gd") as GDScript).get_script_constant_map()
	if gx52_speeds is Dictionary:
		var gx52_sd: Dictionary = gx52_speeds as Dictionary
		if not is_equal_approx(float(gx52_gconsts.get("PATROL_SPEED", -1.0)), float(gx52_sd.get("neutral_m_s", -2.0))) \
			or not is_equal_approx(float(gx52_gconsts.get("SUSPICIOUS_SPEED", -1.0)), float(gx52_sd.get("suspicious_m_s", -2.0))) \
			or not is_equal_approx(float(gx52_gconsts.get("ALERTED_SPEED", -1.0)), float(gx52_sd.get("alerted_combat_fallback_m_s", -2.0))):
			printerr("FAIL: 52 guard speed consts drifted from state_speeds.json")
			gx52_ok = false
	var gx52_vfx: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/vfx/systems.json"))
	var gx52_vok: bool = false
	if gx52_vfx is Dictionary:
		var gx52_vd: Dictionary = gx52_vfx as Dictionary
		var gx52_cls_v: Variant = gx52_vd.get("classes", {})
		var gx52_sys_v: Variant = gx52_vd.get("systems", [])
		var gx52_notes_v: Variant = gx52_vd.get("notes", [])
		var gx52_notes: String = " ".join(PackedStringArray(gx52_notes_v as Array)) if gx52_notes_v is Array else ""
		if int(gx52_vd.get("system_count", 0)) == 120 and gx52_sys_v is Array and (gx52_sys_v as Array).size() == 120 \
			and gx52_cls_v is Dictionary and int((gx52_cls_v as Dictionary).get("graph_heavy", 0)) == 21 \
			and int((gx52_cls_v as Dictionary).get("mesh_or_ribbon", 0)) == 70 \
			and int((gx52_cls_v as Dictionary).get("sprite_only", 0)) == 29 \
			and gx52_notes.find("ParameterData") >= 0:
			gx52_vok = true
	if not gx52_vok:
		printerr("FAIL: 52 vfx catalogue boundary changed (120/21/70/29 + ParameterData note)")
		gx52_ok = false
	var gx52_cfg := ConfigFile.new()
	if gx52_cfg.load("res://export_presets.cfg") != OK or not gx52_cfg.has_section("preset.0") \
		or str(gx52_cfg.get_value("preset.0", "platform", "")) != "Linux":
		printerr("FAIL: 52 export_presets.cfg Linux preset missing")
		gx52_ok = false
	var gx52_mob_path: String = ProjectSettings.globalize_path("res://").path_join("../tools/prepare_mobile_project.py")
	var gx52_mob: String = FileAccess.get_file_as_string(gx52_mob_path)
	if gx52_mob.find("--texture-cap") < 0 or gx52_mob.find("ETC2") < 0:
		printerr("FAIL: 52 prepare_mobile_project.py lost texture-cap/ETC2 path")
		gx52_ok = false
	if not gx52_ok:
		fails += 1
	else:
		print("PASS: 52 guard ramps+speeds/data-consistent, vfx catalogue 120 (21/70/29) + ParameterData boundary, Linux preset + mobile ETC2 path")

	# 53. Doors traversal (todo 6): closed leaf blocks the player capsule,
	# past-70-deg shapes-off + layer-0 lets it through, re-toggle returns to
	# 0 and re-enables, close-while-occupied never teleports the occupant,
	# and an authored locked door (scene-variant `Locks.Doors`, level 3) opens
	# through the lockpick path. R10 deleted the spawn-index auto-lock
	# heuristics: the lock below is set explicitly, not derived from `count`.
	# Capsule dims match the Spider body (thief_character
	# _build_body: radius 0.32, height 1.78, centre 0.89). The rig sits at a
	# remote origin so no other test body can join the sweep query.
	var dr53_ok := true
	var dr53_base := Vector3(5000.0, 0.0, 5000.0)
	var dr53_swing: GDScript = load("res://src/interact/swinging_door.gd") as GDScript
	var dr53_door: Node = dr53_swing.new() as Node
	dr53_door.call("configure", {"pos": [dr53_base.x, dr53_base.y, dr53_base.z], "basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0], "leaves": []}, null)
	root.add_child(dr53_door)
	await process_frame
	await physics_frame
	var dr53_piv := dr53_door.get_node_or_null("DoorPivot") as Node3D
	if dr53_piv == null:
		printerr("FAIL: 53 door rig pivot missing")
		dr53_ok = false
	else:
		var dr53_leaf := AnimatableBody3D.new()
		dr53_leaf.sync_to_physics = true
		dr53_leaf.collision_layer = 1
		dr53_leaf.collision_mask = 0
		dr53_piv.add_child(dr53_leaf)
		var dr53_cs := CollisionShape3D.new()
		var dr53_box := BoxShape3D.new()
		dr53_box.size = Vector3(1.3, 2.4, 0.16)
		dr53_cs.shape = dr53_box
		dr53_cs.position = Vector3(0.65, 1.2, 0.0)
		dr53_leaf.add_child(dr53_cs)
		(dr53_door.get("_leaf_bodies") as Array).append(dr53_leaf)
		await physics_frame
		var dr53_space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
		var dr53_cap := CapsuleShape3D.new()
		dr53_cap.radius = 0.32
		dr53_cap.height = 1.78
		# 53a. Closed leaf blocks the capsule.
		var dr53_closed: float = _door53_cast(dr53_space, dr53_cap, dr53_base)
		if dr53_closed < 0.0 or dr53_closed >= 0.99:
			printerr("FAIL: 53 closed leaf did not block capsule: safe=", dr53_closed)
			dr53_ok = false
		# 53b. Real swing opens past 70 deg: shapes off + layer 0, capsule passes.
		dr53_door.call("interact", null)
		var dr53_sw := 0
		var dr53_open := false
		while dr53_sw < 300 and not dr53_open:
			await process_frame
			dr53_sw += 1
			dr53_open = absf(absf(dr53_piv.rotation.y) - PI * 0.5) < 0.02
		if not dr53_open:
			printerr("FAIL: 53 door did not swing open: rot=", dr53_piv.rotation.y)
			dr53_ok = false
		else:
			var dr53_bsettle := 0
			while bool(dr53_door.get("_tweening")) and dr53_bsettle < 300:
				await process_frame
				dr53_bsettle += 1
			await physics_frame
			if dr53_cs.disabled != true or int(dr53_leaf.collision_layer) != 0:
				printerr("FAIL: 53 open leaf still blocking: disabled=", dr53_cs.disabled, " layer=", dr53_leaf.collision_layer)
				dr53_ok = false
			var dr53_thru: float = _door53_cast(dr53_space, dr53_cap, dr53_base)
			if dr53_thru < 0.999:
				printerr("FAIL: 53 open doorway did not let capsule through: safe=", dr53_thru)
				dr53_ok = false
			# 53c. Gate explicit on the instance: 60 deg still blocks, 80 deg clears.
			dr53_piv.rotation.y = deg_to_rad(60.0)
			dr53_door.call("_update_leaf_collision")
			await process_frame
			await physics_frame
			if dr53_cs.disabled != false or int(dr53_leaf.collision_layer) != 1:
				printerr("FAIL: 53 60-deg leaf wrongly cleared: disabled=", dr53_cs.disabled, " layer=", dr53_leaf.collision_layer)
				dr53_ok = false
			dr53_piv.rotation.y = deg_to_rad(80.0)
			dr53_door.call("_update_leaf_collision")
			await process_frame
			await physics_frame
			if dr53_cs.disabled != true or int(dr53_leaf.collision_layer) != 0:
				printerr("FAIL: 53 80-deg leaf still blocking: disabled=", dr53_cs.disabled, " layer=", dr53_leaf.collision_layer)
				dr53_ok = false
		# 53d. Re-toggle closes to 0 and re-enables (re-blocks the capsule).
		dr53_door.call("interact", null)
		var dr53_cw := 0
		var dr53_shut := false
		while dr53_cw < 300 and not dr53_shut:
			await process_frame
			dr53_cw += 1
			dr53_shut = absf(dr53_piv.rotation.y) < 0.02
		if not dr53_shut:
			printerr("FAIL: 53 re-toggle did not return to 0: rot=", dr53_piv.rotation.y)
			dr53_ok = false
		else:
			var dr53_dsettle := 0
			while bool(dr53_door.get("_tweening")) and dr53_dsettle < 300:
				await process_frame
				dr53_dsettle += 1
			await physics_frame
			if dr53_cs.disabled != false or int(dr53_leaf.collision_layer) != 1:
				printerr("FAIL: 53 closed leaf did not re-enable: disabled=", dr53_cs.disabled, " layer=", dr53_leaf.collision_layer)
				dr53_ok = false
			var dr53_reblock: float = _door53_cast(root.get_world_3d().direct_space_state, dr53_cap, dr53_base)
			if dr53_reblock < 0.0 or dr53_reblock >= 0.99:
				printerr("FAIL: 53 re-closed leaf did not re-block capsule: safe=", dr53_reblock)
				dr53_ok = false
		# 53e. F-spam mid-tween: the second toggle is ignored, one swing lands open.
		dr53_door.call("interact", null)
		dr53_door.call("interact", null)
		var dr53_fw := 0
		var dr53_fopen := false
		while dr53_fw < 300 and not dr53_fopen:
			await process_frame
			dr53_fw += 1
			dr53_fopen = absf(absf(dr53_piv.rotation.y) - PI * 0.5) < 0.02
		if dr53_fopen:
			var dr53_fsettle := 0
			while bool(dr53_door.get("_tweening")) and dr53_fsettle < 300:
				await process_frame
				dr53_fsettle += 1
		if not dr53_fopen or not bool(dr53_door.get("is_open")):
			printerr("FAIL: 53 F-spam broke the single swing: rot=", dr53_piv.rotation.y, " open=", dr53_door.get("is_open"))
			dr53_ok = false
		# 53f. Close-while-occupied: the occupant never moves, the door still closes.
		var dr53_occ := Node3D.new()
		dr53_occ.position = dr53_base + Vector3(0.0, 1.0, 0.0)
		root.add_child(dr53_occ)
		await process_frame
		var dr53_before: Vector3 = dr53_occ.global_position
		dr53_door.call("interact", null)
		var dr53_ow := 0
		var dr53_oshut := false
		while dr53_ow < 300 and not dr53_oshut:
			await process_frame
			dr53_ow += 1
			dr53_oshut = absf(dr53_piv.rotation.y) < 0.02
		if not dr53_oshut:
			printerr("FAIL: 53 occupied close did not finish: rot=", dr53_piv.rotation.y)
			dr53_ok = false
		else:
			var dr53_osettle := 0
			while bool(dr53_door.get("_tweening")) and dr53_osettle < 300:
				await process_frame
				dr53_osettle += 1
			if not dr53_occ.global_position.is_equal_approx(dr53_before):
				printerr("FAIL: 53 occupant teleported by close: was=", dr53_before, " now=", dr53_occ.global_position)
				dr53_ok = false
			await physics_frame
			if dr53_cs.disabled != false or int(dr53_leaf.collision_layer) != 1:
				printerr("FAIL: 53 occupied close did not re-enable leaf")
				dr53_ok = false
		dr53_occ.queue_free()
	dr53_door.queue_free()
	await process_frame
	# 53g. An authored locked door (level 3, inside the authored 4 cap) opens
	# through the lockpick path. No spawn index participates any more.
	var dr53_lock: Node = dr53_swing.new() as Node
	var dr53_lbase := dr53_base + Vector3(10.0, 0.0, 0.0)
	dr53_lock.call("configure", {"pos": [dr53_lbase.x, dr53_lbase.y, dr53_lbase.z], "basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0], "leaves": []}, null)
	root.add_child(dr53_lock)
	await process_frame
	await physics_frame
	dr53_lock.call("set_locked", true, 1 + (5 % 3))
	if not bool(dr53_lock.get("locked")) or int(dr53_lock.get("lock_level")) != 3:
		printerr("FAIL: 53 auto-lock setup wrong: locked=", dr53_lock.get("locked"), " level=", dr53_lock.get("lock_level"))
		dr53_ok = false
	elif not str(dr53_lock.call("get_interact_prompt")).begins_with("[F] PICK LOCK (Lv 3)"):
		printerr("FAIL: 53 auto-lock prompt wrong: ", dr53_lock.call("get_interact_prompt"))
		dr53_ok = false
	else:
		var dr53_spins := 0
		while bool(dr53_lock.get("locked")) and dr53_spins < 12:
			dr53_lock.call("interact", null)
			dr53_spins += 1
		if bool(dr53_lock.get("locked")):
			printerr("FAIL: 53 lockpick path never unlocked after ", dr53_spins, " attempts")
			dr53_ok = false
		else:
			var dr53_lpiv := dr53_lock.get_node_or_null("DoorPivot") as Node3D
			var dr53_lw := 0
			var dr53_lopen := false
			while dr53_lw < 300 and not dr53_lopen:
				await process_frame
				dr53_lw += 1
				if dr53_lpiv != null:
					dr53_lopen = absf(absf(dr53_lpiv.rotation.y) - PI * 0.5) < 0.02
			if not dr53_lopen:
				printerr("FAIL: 53 lockpicked door did not swing open")
				dr53_ok = false
	dr53_lock.queue_free()
	await process_frame
	if not dr53_ok:
		fails += 1
	else:
		print("PASS: 53 doors traversal (closed blocks / 70-deg gate / re-toggle re-blocks / F-spam single swing / occupied close no-teleport / count5 lockpick opens)")

	# 54. Settings schema v2: a legacy fov=75 save migrates once to the authored
	# 54.54, an explicit non-75 value is untouched, and a post-migration 75
	# (the player deliberately choosing it) stays 75 on the next load. The
	# settings write itself must mark fov_migrated, otherwise a fresh install
	# that deliberately picks 75 is rewritten to 54.54 on the next boot.
	var sv54_ok: bool = true
	var sv54: Node = root.get_node_or_null("/root/SaveSystem")
	var sv54_path: String = "user://tat2_save.json"
	var sv54_had_file: bool = FileAccess.file_exists(sv54_path)
	var sv54_backup: String = FileAccess.get_file_as_string(sv54_path) if sv54_had_file else ""
	if sv54 == null:
		printerr("FAIL: 54 SaveSystem missing")
		sv54_ok = false
	else:
		# Simulate a fresh process boot: reset to schema defaults, then load the
		# on-disk save. (A second load_save() in the same process keeps the
		# in-memory migration flag, which is what we test for "once".)
		var sv54_boot := func() -> void:
			sv54.set("data", sv54.call("_defaults"))
			sv54.call("load_save")
		var sv54_write := func(payload: Dictionary) -> void:
			var wf: FileAccess = FileAccess.open(sv54_path, FileAccess.WRITE)
			if wf == null:
				return
			wf.store_string(JSON.stringify(payload, "\t"))
			wf.close()
		sv54_write.call({"settings": {"fov": 75.0}})
		sv54_boot.call()
		var sv54_s1: Dictionary = sv54.call("get_settings") as Dictionary
		var sv54_fov1: float = float(sv54_s1.get("fov", -1.0))
		var sv54_flag1: bool = bool(sv54_s1.get("fov_migrated", false))
		var sv54_schema1: int = int((sv54.get("data") as Dictionary).get("settings_schema", 0))
		if not is_equal_approx(sv54_fov1, 54.54) or not sv54_flag1 or sv54_schema1 != 2:
			printerr("FAIL: 54 legacy fov 75 did not migrate (fov=", sv54_fov1, " flag=", sv54_flag1, " schema=", sv54_schema1, ")")
			sv54_ok = false
		# Second load of the now-migrated file must not touch the value.
		sv54_boot.call()
		var sv54_fov1b: float = float((sv54.call("get_settings") as Dictionary).get("fov", -1.0))
		if not is_equal_approx(sv54_fov1b, 54.54):
			printerr("FAIL: 54 second load re-migrated fov to ", sv54_fov1b)
			sv54_ok = false
		# Explicit non-75 user choice is preserved.
		sv54_write.call({"settings": {"fov": 65.0}})
		sv54_boot.call()
		var sv54_fov2: float = float((sv54.call("get_settings") as Dictionary).get("fov", -1.0))
		if not is_equal_approx(sv54_fov2, 65.0):
			printerr("FAIL: 54 explicit fov 65 was changed to ", sv54_fov2)
			sv54_ok = false
		# A deliberate 75 chosen after migration (flag already set) stays 75.
		sv54_write.call({"settings": {"fov": 75.0, "fov_migrated": true}})
		sv54_boot.call()
		var sv54_fov3: float = float((sv54.call("get_settings") as Dictionary).get("fov", -1.0))
		if not is_equal_approx(sv54_fov3, 75.0):
			printerr("FAIL: 54 post-migration fov 75 was re-migrated to ", sv54_fov3)
			sv54_ok = false
		# Fresh install: defaults -> settings screen writes a deliberate 75 and
		# marks the migration flag in the same save. A full-schema reload must
		# keep 75 (the bug rewrote it to 54.54 because the UI never set the flag).
		var sv54_fresh: Dictionary = sv54.call("_defaults") as Dictionary
		var sv54_fresh_s: Dictionary = sv54_fresh["settings"] as Dictionary
		sv54_fresh_s["fov"] = 75.0
		sv54_fresh_s["fov_migrated"] = true
		sv54_write.call(sv54_fresh)
		sv54_boot.call()
		var sv54_fov4: float = float((sv54.call("get_settings") as Dictionary).get("fov", -1.0))
		var sv54_flag4: bool = bool((sv54.call("get_settings") as Dictionary).get("fov_migrated", false))
		if not is_equal_approx(sv54_fov4, 75.0) or not sv54_flag4:
			printerr("FAIL: 54 fresh-install fov 75 was rewritten to ", sv54_fov4, " flag=", sv54_flag4)
			sv54_ok = false
		# Real SettingsUI: opening/closing must not mark the authored default as
		# an explicit FOV choice. Start from in-memory schema defaults (flag
		# false) so no boot migration has run.
		var sv54_read_settings := func() -> Dictionary:
			var rf: FileAccess = FileAccess.open(sv54_path, FileAccess.READ)
			if rf == null:
				return {}
			var parsed: Variant = JSON.parse_string(rf.get_as_text())
			rf.close()
			if parsed is Dictionary:
				return ((parsed as Dictionary).get("settings", {}) as Dictionary).duplicate(true)
			return {}
		sv54.set("data", sv54.call("_defaults"))
		var sv54_ui1: CanvasLayer = (load("res://src/ui/settings_ui.gd") as GDScript).new() as CanvasLayer
		root.add_child(sv54_ui1)
		await process_frame
		sv54_ui1.call("open_settings")
		sv54_ui1.call("close_settings")
		await process_frame
		await process_frame
		var sv54_closed_s: Dictionary = sv54_read_settings.call()
		if bool(sv54_closed_s.get("fov_migrated", true)) or not is_equal_approx(float(sv54_closed_s.get("fov", -1.0)), 54.54):
			printerr("FAIL: 54 settings open/close changed fov/flag: fov=", sv54_closed_s.get("fov", -1.0), " flag=", sv54_closed_s.get("fov_migrated", true))
			sv54_ok = false
		# A real slider move is an explicit choice: persist it with the flag.
		sv54.set("data", sv54.call("_defaults"))
		var sv54_ui2: CanvasLayer = (load("res://src/ui/settings_ui.gd") as GDScript).new() as CanvasLayer
		root.add_child(sv54_ui2)
		await process_frame
		var sv54_slider: HSlider = sv54_ui2.get("_fov_slider") as HSlider
		if sv54_slider == null:
			printerr("FAIL: 54 settings_ui has no FOV slider")
			sv54_ok = false
		else:
			sv54_slider.value = 75.0
			await process_frame
			sv54_ui2.call("open_settings")
			sv54_ui2.call("close_settings")
			await process_frame
			await process_frame
			var sv54_ui_s: Dictionary = sv54_read_settings.call()
			if not is_equal_approx(float(sv54_ui_s.get("fov", -1.0)), 75.0) or not bool(sv54_ui_s.get("fov_migrated", false)):
				printerr("FAIL: 54 slider fov 75 was not persisted with fov_migrated (fov=", sv54_ui_s.get("fov", -1.0), " flag=", sv54_ui_s.get("fov_migrated", false), ")")
				sv54_ok = false
			sv54_boot.call()
			var sv54_fov5: float = float((sv54.call("get_settings") as Dictionary).get("fov", -1.0))
			if not is_equal_approx(sv54_fov5, 75.0):
				printerr("FAIL: 54 slider fov 75 was re-migrated to ", sv54_fov5)
				sv54_ok = false
		if sv54_had_file:
			var rf: FileAccess = FileAccess.open(sv54_path, FileAccess.WRITE)
			if rf != null:
				rf.store_string(sv54_backup)
				rf.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(sv54_path))
		sv54_boot.call()
	if not sv54_ok:
		fails += 1
	else:
		print("PASS: 54 settings schema v2 fov migration (75 -> 54.54 once, 65 kept, post-migration 75 kept, UI open/close leaves flag false, slider 75 persists + reloads)")

	# 60. W5 player-facing UI: mission-prep countdown + card wrap, HUD identity/
	# currency/key row, Black Market unknown prices, deterministic pause seed,
	# escape-portal visual, startscreen rain and working localization.
	var w60: Array[String] = []
	var w60_save_path: String = "user://tat2_save.json"
	var w60_had_save: bool = FileAccess.file_exists(w60_save_path)
	var w60_save_backup: String = FileAccess.get_file_as_string(w60_save_path) if w60_had_save else ""
	var w60_player: String = str(gs.player_name)
	var w60_keys: Array = (gs.get("stolen_keys") as Array).duplicate()
	var w60_loot_value: int = int(gs.loot_value)
	var w60_loot_goal: int = int(gs.loot_goal)
	var w60_free: bool = bool(gs.free_play)
	var w60_free_pending: bool = bool(gs.free_play_pending)
	var w60_pending_mission: String = str(gs.pending_mission_id)
	var w60_state: String = str(gs.state)
	var w60_map_seed: int = int(gs.active_map_seed)
	var w60_order: int = int(gs.active_contract_order)
	var w60_difficulty: int = int(gs.difficulty)
	var w60_locale: String = str(ss.get_settings().get("locale", "en"))
	var w60_quest_item: bool = bool(gs.quest_item_acquired)
	var w60_objectives: Array = (gs.get("mission_objectives") as Array).duplicate(true)

	# 60a. Mission prep: card body wrap insets and the 6 s READY/UNREADY flow.
	var w60_mp: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	w60_mp.size = Vector2(1280, 720)
	root.add_child(w60_mp)
	await process_frame
	await process_frame
	w60_mp.call("open_prep", "guildhall", 1, "Solo", 2, true)
	await process_frame
	await process_frame
	for w60_key: String in ["_location_body", "_mission_body", "_contract_body"]:
		var w60_body: Label = w60_mp.get(w60_key) as Label
		var w60_card: Control = w60_body.get_parent().get_parent() as Control if w60_body != null else null
		var w60_gap: float = (w60_card.global_position.x + w60_card.size.x) - (w60_body.global_position.x + w60_body.size.x) if (w60_card != null and w60_body != null) else -1.0
		_w60_assert(w60_body != null and w60_body.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and w60_body.size.x > 0.0 and w60_gap >= 12.0,
			"prep %s wrap=%s width=%.1f gap=%.1f" % [w60_key, str(w60_body.autowrap_mode if w60_body != null else -1), w60_body.size.x if w60_body != null else -1.0, w60_gap], w60)
	var w60_contract_body: Label = w60_mp.get("_contract_body") as Label
	_w60_assert(w60_contract_body != null and w60_contract_body.text.begins_with("Free play:") and w60_contract_body.text.ends_with("."),
		"free-play prep body text complete", w60)

	var w60_cd: Label = w60_mp.get("_countdown_lbl") as Label
	var w60_ready_btn: Button = w60_mp.get("_ready_btn") as Button
	var w60_ready_lbl: Label = w60_mp.get("_readiness_lbl") as Label
	var w60_emits: Array = []
	w60_mp.connect("ready_pressed", func(_m: String, _d: int, _mo: String, _c: int) -> void: w60_emits.append(1))
	_w60_assert(w60_cd != null and w60_cd.text == "MISSION STARTING IN 6..." and w60_ready_btn != null and w60_ready_btn.text.find("UNREADY") < 0,
		"prep idle countdown/READY label", w60)
	w60_mp.call("_on_ready_action")
	# KF11 at 01:00 (counting): nameplate READY + button [F] UNREADY + hint
	# [F] UNREADY. T05 fixed the nameplate to stay on the readiness STATE; the
	# old assertion pinned the pre-fix shared word (UNREADY on all three).
	_w60_assert(bool(w60_mp.get("_countdown_running")) and w60_cd.text == "MISSION STARTING IN 6..." and w60_ready_btn.text.find("UNREADY") >= 0 and w60_ready_lbl.text == "READY" and w60_emits.is_empty(),
		"first READY starts 6 s countdown in UNREADY button state with a READY nameplate", w60)
	w60_mp.call("_process", 2.0)
	_w60_assert(w60_cd.text == "MISSION STARTING IN 4...", "countdown ticks with _process delta (%s)" % w60_cd.text, w60)
	w60_mp.call("_on_ready_action")
	_w60_assert(not bool(w60_mp.get("_countdown_running")) and w60_ready_btn.text.find("UNREADY") < 0 and w60_ready_lbl.text == "READY" and w60_cd.text == "MISSION STARTING IN 6..." and w60_emits.is_empty(),
		"second READY cancels and restores READY", w60)
	w60_mp.call("_on_ready_action")
	for _w60_i: int in range(5):
		w60_mp.call("_process", 1.0)
	_w60_assert(w60_cd.text == "MISSION STARTING IN 1...", "countdown reaches 1... (%s)" % w60_cd.text, w60)
	w60_mp.call("_process", 1.0)
	_w60_assert(w60_emits.size() == 1 and bool(gs.free_play), "countdown deploys exactly once at zero (emits=%d free_play=%s)" % [w60_emits.size(), str(gs.free_play)], w60)
	w60_mp.call("_process", 1.0)
	_w60_assert(w60_emits.size() == 1, "deploy signal not repeated", w60)
	w60_mp.queue_free()
	await process_frame
	gs.call("end_free_play")

	# 60b. HUD identity/currency/key row + deterministic pause seed.
	gs.set("state", "playing")
	gs.set("active_contract_order", 2)
	gs.set("difficulty", 1)
	gs.set("player_name", "Test Handle")
	var w60_keys_now: Array = gs.get("stolen_keys") as Array
	w60_keys_now.clear()
	var w60_hud: CanvasLayer = (load("res://src/ui/hud.gd") as GDScript).new() as CanvasLayer
	root.add_child(w60_hud)
	await process_frame
	w60_hud.call("_update_portrait_plate")
	var w60_name_lbl: Label = w60_hud.get("_thief_name_lbl") as Label
	_w60_assert(w60_name_lbl != null and w60_name_lbl.text == "Test Handle", "HUD uses GameState.player_name (%s)" % (w60_name_lbl.text if w60_name_lbl != null else "?"), w60)
	w60_hud.call("update_loot", 0, 0, 1234)
	var w60_loot_lbl: Label = w60_hud.get("_loot_lbl") as Label
	_w60_assert(w60_loot_lbl != null and w60_loot_lbl.text == "(£) 1234", "HUD currency format (%s)" % (w60_loot_lbl.text if w60_loot_lbl != null else "?"), w60)
	gs.set("loot_value", 1234)
	gs.set("loot_goal", 4000)
	gs.set("free_play", false)
	w60_hud.call("_update_objectives_and_loot", false)
	_w60_assert(w60_loot_lbl != null and w60_loot_lbl.text == "(£) 1234 / £ 4000", "HUD currency cap format (%s)" % (w60_loot_lbl.text if w60_loot_lbl != null else "?"), w60)
	var w60_keys_lbl: Label = w60_hud.get("_keys_lbl") as Label
	w60_hud.call("_update_key_row", false)
	_w60_assert(w60_keys_lbl != null and not w60_keys_lbl.visible, "empty key row hidden", w60)
	gs.call("add_stolen_key", "key_manor")
	gs.call("add_stolen_key", "key_vault")
	w60_hud.call("_update_key_row", false)
	_w60_assert(w60_keys_lbl != null and w60_keys_lbl.visible and w60_keys_lbl.text.find("Elway Manor Key") >= 0 and w60_keys_lbl.text.find("Vault Key") >= 0,
		"key row shows shipped names (%s)" % (w60_keys_lbl.text if w60_keys_lbl != null else "?"), w60)
	_w60_assert(str(gs.call("stolen_key_display_name", "key_guildhall")) == "Guildhall Key", "Guildhall Key display name", w60)
	_w60_assert(str(gs.call("stolen_key_display_name", "weird_key")) == "Weird Key", "unknown key id title-cased", w60)
	gs.set("active_map_seed", 424242)
	var w60_footer: String = str(w60_hud.call("_pause_footer_text"))
	_w60_assert(w60_footer == "1.5.148559   Novice   424242", "pause footer deterministic seed (%s)" % w60_footer, w60)

	# 60c. Ledger player name + catalog-driven KF08 states (W6U2). The Black
	# Market reads the authored unlock catalog: a row is purchased / price /
	# locked, never "PRICE UNKNOWN", and a gate is enforced on BUY.
	var w60_ledger: Control = (load("res://src/ui/ledger_ui.gd") as GDScript).new() as Control
	root.add_child(w60_ledger)
	await process_frame
	var w60_thief_lbl: Label = w60_ledger.get("_thief_lbl") as Label
	_w60_assert(w60_thief_lbl != null and w60_thief_lbl.text == "Test Handle", "ledger uses GameState.player_name (%s)" % (w60_thief_lbl.text if w60_thief_lbl != null else "?"), w60)
	var w60_data: Dictionary = save_sys.get("data") as Dictionary
	var w60_ledger_backup: Dictionary = w60_data.duplicate(true)
	# Owned rows come from the live profile, and a migrated save may already own
	# pickpocket_fairy (W6U2 legacy "fairy" -> "pickpocket_fairy"). Pin the
	# shipped starter profile so the gate assertions do not depend on what the
	# player has bought; the whole dict is restored at the end of 60c.
	w60_data["xp"] = 0
	w60_data["currency"] = 0
	w60_data["completed_contracts"] = {}
	w60_data["unlocked_tools"] = (save_sys.STARTER_TOOLS as Array).duplicate()
	var w60_status: Label = w60_ledger.get("_preview_status") as Label
	var w60_buy: Button = w60_ledger.get("_buy_btn") as Button
	# Locked row at the test profile's level (Contract 3 tool).
	w60_ledger.call("_on_item_pressed", "pickpocket_fairy")
	_w60_assert(w60_status != null and w60_status.text == "Requires Contract 3" and w60_buy != null and not w60_buy.visible,
		"gated row shows its authored gate and hides BUY (%s)" % (w60_status.text if w60_status != null else "?"), w60)
	var w60_locked_btn: String = str(w60_ledger.call("_item_button_text", {"save_id": "pickpocket_fairy", "name": "Pickpocket Fairy", "cat": "tools", "cost": 5000, "desc": "test"}))
	_w60_assert(w60_locked_btn.find("LOCKED") >= 0 and w60_locked_btn.find("PRICE UNKNOWN") < 0,
		"locked row reads LOCKED, never PRICE UNKNOWN (%s)" % w60_locked_btn, w60)
	# KF08 profile: Level 4 with £26,275 shows Bob Hair's authored £7,500 + BUY.
	w60_data["xp"] = 1500
	w60_data["level"] = 4
	w60_data["currency"] = 26275
	w60_ledger.call("_on_item_pressed", "Outfit.Spider.Head.Hair.Bob")
	_w60_assert(w60_status != null and w60_status.text == "£ 7,500" and w60_buy != null and w60_buy.visible,
		"KF08 Bob Hair shows the authored £ 7,500 + BUY (%s)" % (w60_status.text if w60_status != null else "?"), w60)
	var w60_owned: String = str(w60_ledger.call("_item_button_text", {"save_id": "Outfit.Spider.Head.BowlerA", "name": "Bowler Hat", "cat": "cosmetics", "cost": 2500, "desc": "test"}))
	_w60_assert(w60_owned.find("✓ PURCHASED") >= 0, "owned item shows PURCHASED (%s)" % w60_owned, w60)
	var w60_ledger_src: String = FileAccess.get_file_as_string("res://src/ui/ledger_ui.gd")
	_w60_assert(w60_ledger_src.find("TBD PRICE") < 0 and w60_ledger_src.find("DO NOT SHIP") < 0 and w60_ledger_src.find("PRICE UNKNOWN") < 0,
		"ledger source has no placeholder/unknown price strings", w60)
	var w60_bad_btn: bool = false
	var w60_rows: int = 0
	var w60_sections: Array = w60_ledger.call("_sections") as Array
	for w60_s_v: Variant in w60_sections:
		var w60_sd: Dictionary = w60_s_v as Dictionary
		for w60_it_v: Variant in (w60_sd.get("items", []) as Array):
			w60_rows += 1
			var w60_txt: String = str(w60_ledger.call("_item_button_text", w60_it_v as Dictionary))
			if w60_txt.find("TBD") >= 0 or w60_txt.find("DO NOT SHIP") >= 0 or w60_txt.find("PRICE UNKNOWN") >= 0:
				w60_bad_btn = true
	_w60_assert(not w60_bad_btn and w60_rows == 68, "all %d shop rows carry an authored state" % w60_rows, w60)
	save_sys.set("data", w60_ledger_backup)
	w60_ledger.queue_free()
	await process_frame

	# 60d. Escape portal: wall outline mesh/shader, 3x3x3 trigger, extracted signal.
	var w60_gate: Area3D = (load("res://src/interact/escape_gate.gd") as GDScript).new() as Area3D
	root.add_child(w60_gate)
	await process_frame
	var w60_portal: MeshInstance3D = w60_gate.get("portal_visual") as MeshInstance3D
	var w60_portal_mat: ShaderMaterial = w60_portal.material_override as ShaderMaterial if w60_portal != null else null
	var w60_shape: BoxShape3D = null
	for w60_c: Node in w60_gate.get_children():
		if w60_c is CollisionShape3D and (w60_c as CollisionShape3D).shape is BoxShape3D:
			w60_shape = (w60_c as CollisionShape3D).shape as BoxShape3D
	_w60_assert(w60_portal != null and w60_portal.mesh is QuadMesh and w60_portal_mat != null and w60_portal_mat.shader != null and w60_portal_mat.shader.resource_path.find("tat_escape_portal") >= 0,
		"portal uses QuadMesh + portal ShaderMaterial", w60)
	_w60_assert(w60_gate.find_children("*", "Label3D", true, false).is_empty(), "portal has no floating Label3D", w60)
	_w60_assert(w60_shape != null and w60_shape.size.is_equal_approx(Vector3(3.0, 3.0, 3.0)), "portal 3x3x3 trigger kept", w60)
	var w60_gate_emits: Array = []
	w60_gate.connect("extracted", func() -> void: w60_gate_emits.append(1))
	var w60_body: CharacterBody3D = CharacterBody3D.new()
	w60_body.add_to_group("player")
	root.add_child(w60_body)
	gs.set("state", "playing")
	gs.set("quest_item_acquired", true)
	gs.set("mission_objectives", [])
	gs.set("loot_goal", 0)
	# W7E: an authored escape marker is dormant during the main window and only
	# extracts after the objectives complete (endgame) and the door is summoned.
	# This suite owns the portal visual/trigger contract, so it activates the
	# gate explicitly instead of relying on the pre-W7E always-open behaviour.
	gs.set("phase", "endgame")
	w60_gate.call("activate")
	w60_gate.call("_on_body_entered", w60_body)
	_w60_assert(w60_gate_emits.size() == 1, "portal extracted signal fires", w60)
	w60_body.queue_free()
	w60_gate.queue_free()
	gs.set("phase", "main")
	await process_frame

	# 60e. Startscreen rain layer spawns with the menu and is freed with it.
	var w60_menu: Control = (load("res://src/ui/main_menu.gd") as GDScript).new() as Control
	root.add_child(w60_menu)
	await process_frame
	await process_frame
	var w60_rain: Node3D = w60_menu.get("_menu_rain") as Node3D
	var w60_rain_ref: WeakRef = weakref(w60_rain) if w60_rain != null else null
	_w60_assert(w60_rain != null and w60_rain.name == "RainVolume" and w60_rain.is_inside_tree() and w60_rain.get_child_count() > 0,
		"menu rain layer spawned (%s)" % (w60_rain.name if w60_rain != null else "none"), w60)
	w60_menu.queue_free()
	await process_frame
	await process_frame
	_w60_assert(w60_rain_ref == null or w60_rain_ref.get_ref() == null, "menu rain freed with the menu", w60)

	# 60f. Localization: reverse map, de translation, fallback, no GUID, restore.
	var w60_loc: Node = root.get_node_or_null("Loc")
	_w60_assert(w60_loc != null and (w60_loc.call("languages") as Array).size() == 8, "Loc autoload with 8 shipped locales", w60)
	var w60_sans: Font = ArtNouveauTheme.font_sans()
	var w60_fallback_paths: Array[String] = []
	if w60_sans != null:
		for w60_fb: Font in w60_sans.fallbacks:
			w60_fallback_paths.append(w60_fb.resource_path)
	var w60_hk_ok: bool = false
	var w60_sc_ok: bool = false
	var w60_jp_ok: bool = false
	for w60_fp: String in w60_fallback_paths:
		if w60_fp.find("NotoSerifHK-Regular") >= 0:
			w60_hk_ok = true
		elif w60_fp.find("NotoSerifSC-Regular") >= 0:
			w60_sc_ok = true
		elif w60_fp.find("NotoSerifJP-Regular") >= 0:
			w60_jp_ok = true
	_w60_assert(w60_hk_ok and w60_sc_ok and w60_jp_ok, "CJK font fallbacks attached to the UI theme (%s)" % str(w60_fallback_paths), w60)
	if w60_loc != null:
		w60_loc.call("set_locale", "en")
		var w60_en_play: String = str(w60_loc.call("t", "Play"))
		w60_loc.call("set_locale", "de")
		var w60_de_play: String = str(w60_loc.call("t", "PLAY"))
		var w60_de_resume: String = str(w60_loc.call("t", "Resume"))
		var w60_de_credits: String = str(w60_loc.call("t", "Credits"))
		var w60_unknown: String = str(w60_loc.call("t", "W5 UNKNOWN STRING"))
		var w60_guid_re: RegEx = RegEx.new()
		w60_guid_re.compile("^[0-9A-F]{32}$")
		_w60_assert(w60_en_play == "Play", "en Play stays English (%s)" % w60_en_play, w60)
		_w60_assert(w60_de_play != "PLAY" and w60_de_play != "Play", "de PLAY translates (%s)" % w60_de_play, w60)
		_w60_assert(w60_de_resume != "Resume", "de Resume translates (%s)" % w60_de_resume, w60)
		_w60_assert(w60_de_credits == "Credits", "de miss falls back to English source (%s)" % w60_de_credits, w60)
		_w60_assert(w60_unknown == "W5 UNKNOWN STRING", "unknown source falls through", w60)
		_w60_assert(w60_guid_re.search(w60_de_resume) == null and w60_guid_re.search(w60_de_credits) == null, "Loc never returns a raw GUID", w60)
		w60_loc.call("set_locale", "en")
		_w60_assert(str(w60_loc.call("t", "Play")) == "Play", "en restores English", w60)

	# 60g. Settings language option persists the shipped code.
	var w60_settings: CanvasLayer = (load("res://src/ui/settings_ui.gd") as GDScript).new() as CanvasLayer
	root.add_child(w60_settings)
	await process_frame
	await process_frame
	var w60_lang_opt: OptionButton = w60_settings.get("_language_option") as OptionButton
	_w60_assert(w60_lang_opt != null and w60_lang_opt.item_count == 8, "settings language option has 8 locales", w60)
	if w60_lang_opt != null and w60_lang_opt.item_count == 8:
		var w60_de_idx: int = -1
		var w60_en_idx: int = -1
		for w60_li: int in range(w60_lang_opt.item_count):
			var w60_code: String = str(w60_lang_opt.get_item_metadata(w60_li))
			if w60_code == "de_DE":
				w60_de_idx = w60_li
			elif w60_code == "en":
				w60_en_idx = w60_li
		w60_lang_opt.select(w60_de_idx)
		w60_settings.call("_on_language_selected", w60_de_idx)
		var w60_saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(w60_save_path))
		var w60_saved_locale: String = str((w60_saved as Dictionary).get("settings", {}).get("locale", "")) if w60_saved is Dictionary else ""
		_w60_assert(str(ss.get_settings().get("locale", "")) == "de_DE" and str(w60_loc.call("get_locale")) == "de_DE" and w60_saved_locale == "de_DE",
			"language option applies + persists de_DE (memory=%s saved=%s)" % [str(ss.get_settings().get("locale", "")), w60_saved_locale], w60)
		w60_lang_opt.select(w60_en_idx)
		w60_settings.call("_on_language_selected", w60_en_idx)
		_w60_assert(str(ss.get_settings().get("locale", "")) == "en" and str(w60_loc.call("get_locale")) == "en", "language option restores en", w60)
	w60_settings.queue_free()
	await process_frame

	# Restore shared state and the on-disk save exactly as suite 49/54 expect.
	gs.set("loot_value", w60_loot_value)
	gs.set("loot_goal", w60_loot_goal)
	gs.set("free_play", w60_free)
	gs.set("free_play_pending", w60_free_pending)
	gs.set("pending_mission_id", w60_pending_mission)
	gs.set("state", w60_state)
	gs.set("active_map_seed", w60_map_seed)
	gs.set("active_contract_order", w60_order)
	gs.set("difficulty", w60_difficulty)
	gs.set("player_name", w60_player)
	gs.set("quest_item_acquired", w60_quest_item)
	gs.set("mission_objectives", w60_objectives)
	var w60_restore_keys: Array = gs.get("stolen_keys") as Array
	w60_restore_keys.clear()
	for w60_rk: Variant in w60_keys:
		w60_restore_keys.append(str(w60_rk))
	if w60_had_save:
		var w60_rf: FileAccess = FileAccess.open(w60_save_path, FileAccess.WRITE)
		if w60_rf != null:
			w60_rf.store_string(w60_save_backup)
			w60_rf.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(w60_save_path))
	ss.set("data", ss.call("_defaults"))
	ss.call("load_save")
	ss.call("apply_saved_settings")
	ss.call("_sync_player_name")
	if w60_loc != null:
		w60_loc.call("set_locale", w60_locale)
	else:
		TranslationServer.set_locale(w60_locale)
	if not w60.is_empty():
		printerr("FAIL: 60 W5 UI: ", "; ".join(w60))
		fails += 1
	else:
		print("PASS: 60 W5 UI (prep 6 s countdown/UNREADY + card wrap, player_name, (£) currency, key row, PRICE UNKNOWN, pause seed, portal, menu rain, localization)")

	# 82. W0a: shipped identity (no capture persona), shipped key names, and the
	# texture-cap sidecars. The persona is the capture machine's Steam account;
	# the shipped card/ledger read PlayerState.GetPlayerName and fall back to
	# the authored thief title when the player has no handle.
	var w82: Array[String] = []
	var w82_locale: String = str(ss.get_settings().get("locale", "en"))
	var w82_save_path: String = "user://tat2_save.json"
	var w82_had_save: bool = FileAccess.file_exists(w82_save_path)
	var w82_save_backup: String = FileAccess.get_file_as_string(w82_save_path) if w82_had_save else ""
	var w82_thief: String = str(gs.thief_id)
	var w82_keys: Array = (gs.get("stolen_keys") as Array).duplicate()
	var w82_loc: Node = root.get_node_or_null("Loc")
	if w82_loc != null:
		w82_loc.call("set_locale", "en")

	# 82a. The two SafeBlackFaction albedo sidecars carry the cap + mipmaps, and
	# the alpha-critical storefront decal stays full-res (its punch-through
	# alpha is destroyed by downscaling).
	var w82_cap_textures: Array[String] = [
		"res://assets/ue/Raw/Art/Gameplay/MajorLootSafe/SafeBlackFaction/T_SafeBlackFaction_Base_D.png",
		"res://assets/ue/Raw/Art/Gameplay/MajorLootSafe/SafeBlackFaction/T_SafeBlackFaction_Ornaments_D.png",
	]
	for w82_tex: String in w82_cap_textures:
		var w82_sidecar: String = FileAccess.get_file_as_string(w82_tex + ".import")
		var w82_long: int = _w82_png_long_edge(w82_tex)
		var w82_imported: Vector2i = _w82_imported_texture_size(w82_tex)
		_w60_assert(w82_long > 1024 and w82_sidecar.find("process/size_limit=1024") >= 0 and w82_sidecar.find("mipmaps/generate=true") >= 0 and maxi(w82_imported.x, w82_imported.y) == 1024,
			"cap sidecar %s long=%d limit=%s mips=%s ctex=%s" % [w82_tex.get_file(), w82_long,
				str(w82_sidecar.find("process/size_limit=1024") >= 0), str(w82_sidecar.find("mipmaps/generate=true") >= 0), str(w82_imported)], w82)
	var w82_alpha_tex: String = "res://assets/ue/Raw/Art/Environment/Storefront/GlassDecals/T_Storefront_GlassDecalsA.png"
	var w82_alpha_sidecar: String = FileAccess.get_file_as_string(w82_alpha_tex + ".import")
	var w82_alpha_long: int = _w82_png_long_edge(w82_alpha_tex)
	var w82_alpha_imported: Vector2i = _w82_imported_texture_size(w82_alpha_tex)
	_w60_assert(w82_alpha_long >= 4096 and w82_alpha_sidecar.find("process/size_limit=1024") < 0 and w82_alpha_imported == Vector2i(4096, 4096),
		"alpha-critical storefront decal stays 4096 (source long=%d ctex=%s)" % [w82_alpha_long, str(w82_alpha_imported)], w82)

	# 82b. Identity: blank shows the authored title, an explicit handle wins.
	gs.set("thief_id", "spider")
	gs.set("player_name", "")
	_w60_assert(str(gs.call("player_display_name")) == "The Spider", "blank handle -> The Spider (%s)" % str(gs.call("player_display_name")), w82)
	gs.set("thief_id", "chameleon")
	_w60_assert(str(gs.call("player_display_name")) == "The Chameleon", "chameleon -> The Chameleon (%s)" % str(gs.call("player_display_name")), w82)
	gs.set("player_name", "Test Handle")
	_w60_assert(str(gs.call("player_display_name")) == "Test Handle", "explicit handle preserved (%s)" % str(gs.call("player_display_name")), w82)
	gs.set("player_name", "")
	gs.set("thief_id", "spider")

	# 82c. Migration: legacy persona -> blank once; explicit name kept; a second
	# boot with Alice keeps Alice; a flagged save is never re-migrated.
	_w82_write_save({"player_name": "Johnny Cipher"})
	ss.set("data", ss.call("_defaults"))
	ss.call("load_save")
	var w82_data: Dictionary = ss.get("data") as Dictionary
	_w60_assert(str(w82_data.get("player_name", "?")) == "" and bool(w82_data.get("player_name_migrated", false)),
		"legacy persona migrates to blank + flag (name=%s flag=%s)" % [str(w82_data.get("player_name", "?")), str(w82_data.get("player_name_migrated", false))], w82)
	var w82_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(w82_save_path))
	_w60_assert(w82_disk is Dictionary and str((w82_disk as Dictionary).get("player_name", "?")) == "" and bool((w82_disk as Dictionary).get("player_name_migrated", false)),
		"migration is persisted to disk", w82)
	_w82_write_save({"player_name": "Alice"})
	ss.set("data", ss.call("_defaults"))
	ss.call("load_save")
	_w60_assert(str((ss.get("data") as Dictionary).get("player_name", "?")) == "Alice", "second boot keeps Alice", w82)
	_w82_write_save({"player_name": "Johnny Cipher", "player_name_migrated": true})
	ss.set("data", ss.call("_defaults"))
	ss.call("load_save")
	_w60_assert(str((ss.get("data") as Dictionary).get("player_name", "?")) == "Johnny Cipher", "flagged save is never re-migrated", w82)
	ss.call("set_player_name", "")
	_w60_assert(str((ss.get("data") as Dictionary).get("player_name", "?")) == "" and bool((ss.get("data") as Dictionary).get("player_name_migrated", false)),
		"set_player_name(blank) stays blank", w82)

	# 82d. Source scan: no capture-persona literal outside the migration
	# tombstone constant in save_system.gd.
	var w82_hits: Array[String] = []
	_w82_scan_gd("res://src", "Johnny Cipher", w82_hits)
	_w60_assert(w82_hits.size() == 1 and w82_hits[0].begins_with("res://src/core/save_system.gd:"),
		"only the migration tombstone names the persona (%s)" % str(w82_hits), w82)
	var w82_save_src: String = FileAccess.get_file_as_string("res://src/core/save_system.gd")
	_w60_assert(w82_save_src.find("const CAPTURE_PERSONA_NAME := \"Johnny Cipher\"") >= 0,
		"migration tombstone constant present", w82)

	# 82e. Shipped key names, not mesh/icon names.
	_w60_assert(str(gs.call("stolen_key_display_name", "key_guildhall")) == "Guildhall Key", "key_guildhall display name", w82)
	_w60_assert(str(gs.call("stolen_key_display_name", "key_manor")) == "Elway Manor Key", "key_manor display name", w82)
	_w60_assert(str(gs.call("stolen_key_display_name", "key_vault")) == "Vault Key", "key_vault display name", w82)
	var w82_mc: Node = (load("res://src/missions/mission_controller.gd") as GDScript).new() as Node
	var w82_g: Array = w82_mc.call("_key_pool_for_map", "guildhall") as Array
	var w82_o: Array = w82_mc.call("_key_pool_for_map", "old_manor") as Array
	var w82_g0: Dictionary = w82_g[0] as Dictionary
	var w82_o0: Dictionary = w82_o[0] as Dictionary
	var w82_vault_rows_ok: bool = true
	for w82_i: int in range(1, w82_g.size()):
		if str((w82_g[w82_i] as Dictionary).get("id", "")) != "key_vault":
			w82_vault_rows_ok = false
	_w60_assert(str(w82_g0.get("id", "")) == "key_guildhall" and str(w82_g0.get("name", "")) == "Guildhall Key" and str(w82_g0.get("mesh_path", "")).ends_with("SM_LootableKeys_ManorKey.glb"),
		"Guildhall guard key is Guildhall Key with the shipped mesh (%s)" % str(w82_g0), w82)
	_w60_assert(str(w82_o0.get("id", "")) == "key_manor" and str(w82_o0.get("name", "")) == "Elway Manor Key",
		"Old Manor guard key is Elway Manor Key (%s)" % str(w82_o0), w82)
	_w60_assert(w82_vault_rows_ok, "remaining guard key rows are Vault Keys", w82)
	w82_mc.free()

	if w82_had_save:
		var w82_rf: FileAccess = FileAccess.open(w82_save_path, FileAccess.WRITE)
		if w82_rf != null:
			w82_rf.store_string(w82_save_backup)
			w82_rf.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(w82_save_path))
	ss.set("data", ss.call("_defaults"))
	ss.call("load_save")
	ss.call("apply_saved_settings")
	ss.call("_sync_player_name")
	if w82_loc != null:
		w82_loc.call("set_locale", w82_locale)
	else:
		TranslationServer.set_locale(w82_locale)
	gs.set("thief_id", w82_thief)
	var w82_restore_keys: Array = gs.get("stolen_keys") as Array
	w82_restore_keys.clear()
	for w82_rk: Variant in w82_keys:
		w82_restore_keys.append(str(w82_rk))
	if not w82.is_empty():
		printerr("FAIL: 82 W0a identity/keys/texture cap: ", "; ".join(w82))
		fails += 1
	else:
		print("PASS: 82 W0a identity (persona migrated once, authored titles), shipped key names (Guildhall/Elway Manor/Vault), texture cap sidecars + alpha-critical exception")

	# 55. W2: authored patrols, surface loudness, interaction LOS/takedown gates,
	# civilian collision.
	# 55a. level_loader merges APatrolPath records and the mission controller
	# hands each guard a real path (PingPong loop, waits, authored facing).
	var w2_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	var w2_host: Node3D = Node3D.new()
	root.add_child(w2_ll)
	root.add_child(w2_host)
	await process_frame
	var w2_acc: Dictionary = w2_ll.call("_new_accumulator") as Dictionary
	w2_ll.call("_parse_sublevel_file", "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json", w2_acc, w2_host)
	var w2_merged_res: Dictionary = w2_acc.get("result", {}) as Dictionary
	var w2_paths: Array = w2_merged_res.get("patrol_paths", []) as Array
	var w2_wp_total: int = 0
	for w2_pv: Variant in w2_paths:
		w2_wp_total += ((w2_pv as Dictionary).get("points", []) as Array).size()
	var w2_raw_v: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json"))
	var w2_raw_paths: Array = (w2_raw_v as Dictionary).get("patrol_paths", []) as Array if w2_raw_v is Dictionary else []
	var w2_preserved: bool = w2_paths.size() == w2_raw_paths.size() and not w2_paths.is_empty()
	if w2_preserved:
		var w2_rp: Dictionary = w2_raw_paths[0] as Dictionary
		var w2_mp: Dictionary = w2_paths[0] as Dictionary
		w2_preserved = str(w2_mp.get("actor", "")) == str(w2_rp.get("actor", "")) \
			and str(w2_mp.get("class", "")) == str(w2_rp.get("class", "")) \
			and str(w2_mp.get("loop_type", "")) == str(w2_rp.get("loop_type", "")) \
			and (w2_mp.get("points", []) as Array).size() == (w2_rp.get("points", []) as Array).size()
		if w2_preserved:
			var w2_rpts: Array = w2_rp.get("points", []) as Array
			var w2_mpts: Array = w2_mp.get("points", []) as Array
			for w2_pi: int in range(w2_rpts.size()):
				var w2_rpt: Dictionary = w2_rpts[w2_pi] as Dictionary
				var w2_mpt: Dictionary = w2_mpts[w2_pi] as Dictionary
				var w2_rp_arr: Array = w2_rpt.get("pos", []) as Array
				var w2_mp_arr: Array = w2_mpt.get("pos", []) as Array
				if w2_rp_arr.size() != 3 or w2_mp_arr.size() != 3 \
					or not is_equal_approx(float(w2_rp_arr[0]), float(w2_mp_arr[0])) \
					or not is_equal_approx(float(w2_rp_arr[1]), float(w2_mp_arr[1])) \
					or not is_equal_approx(float(w2_rp_arr[2]), float(w2_mp_arr[2])) \
					or not is_equal_approx(float(w2_rpt.get("wait", -1.0)), float(w2_mpt.get("wait", -2.0))) \
					or bool(w2_rpt.get("facing", false)) != bool(w2_mpt.get("facing", false)) \
					or not is_equal_approx(float(w2_rpt.get("yaw", 0.0)), float(w2_mpt.get("yaw", 0.0))) \
					or str(w2_rpt.get("type", "")) != str(w2_mpt.get("type", "")):
					w2_preserved = false
					break

	# Pick one PingPong path with >= 4 points and a second path close to it so a
	# second guard has an available alternative (no path reused while another
	# is available).
	var w2_a_idx: int = -1
	var w2_b_idx: int = -1
	for w2_i: int in range(w2_paths.size()):
		var w2_cand: Dictionary = w2_paths[w2_i] as Dictionary
		if str(w2_cand.get("loop_type", "")).find("PingPong") < 0 or (w2_cand.get("points", []) as Array).size() < 4:
			continue
		var w2_cp: Array = w2_cand.get("points", []) as Array
		var w2_cp0: Array = (w2_cp[0] as Dictionary).get("pos", []) as Array
		if w2_cp0.size() < 3:
			continue
		var w2_cpos := Vector3(float(w2_cp0[0]), float(w2_cp0[1]), float(w2_cp0[2]))
		for w2_j: int in range(w2_paths.size()):
			if w2_j == w2_i:
				continue
			var w2_other: Dictionary = w2_paths[w2_j] as Dictionary
			var w2_op: Array = w2_other.get("points", []) as Array
			if w2_op.is_empty():
				continue
			var w2_op0: Array = (w2_op[0] as Dictionary).get("pos", []) as Array
			if w2_op0.size() < 3:
				continue
			if w2_cpos.distance_to(Vector3(float(w2_op0[0]), float(w2_op0[1]), float(w2_op0[2]))) <= 15.0:
				w2_a_idx = w2_i
				w2_b_idx = w2_j
				break
		if w2_a_idx >= 0:
			break

	var w2_spawn_ok: bool = false
	var w2_fallback_ok: bool = false
	if w2_a_idx >= 0 and w2_b_idx >= 0:
		var w2_path_a: Dictionary = w2_paths[w2_a_idx] as Dictionary
		var w2_apts: Array = w2_path_a.get("points", []) as Array
		var w2_ap0: Array = (w2_apts[0] as Dictionary).get("pos", []) as Array
		var w2_spawn_a := Vector3(float(w2_ap0[0]), float(w2_ap0[1]), float(w2_ap0[2]))
		var w2_path_b: Dictionary = w2_paths[w2_b_idx] as Dictionary
		var w2_bpts: Array = w2_path_b.get("points", []) as Array
		var w2_bp0: Array = (w2_bpts[0] as Dictionary).get("pos", []) as Array
		var w2_spawn_b := Vector3(float(w2_bp0[0]), float(w2_bp0[1]), float(w2_bp0[2])) + Vector3(1.0, 0.0, 0.0)
		var w2_anchor: Vector3 = w2_spawn_a + Vector3(20.0, 0.0, 20.0)
		var w2_mc: Node = (load("res://src/missions/mission_controller.gd") as GDScript).new()
		w2_mc.call("_spawn_guards", [w2_spawn_a, w2_spawn_b], w2_anchor, w2_paths)
		var w2_mc_children: Array[Node] = w2_mc.get_children()
		var w2_g0: Node = w2_mc_children[0] if w2_mc_children.size() > 0 else null
		var w2_g1: Node = w2_mc_children[1] if w2_mc_children.size() > 1 else null
		if w2_g0 != null and w2_g1 != null:
			var w2_got_pts: Array = w2_g0.get("patrol_points") as Array
			var w2_got_waits: Array = w2_g0.get("patrol_waits") as Array
			var w2_got_yaws: Array = w2_g0.get("patrol_yaws") as Array
			var w2_got_facing: Array = w2_g0.get("patrol_facing") as Array
			var w2_g1_pts: Array = w2_g1.get("patrol_points") as Array
			# Which authored path did each guard adopt? Several paths can share
			# a first waypoint, so match the whole point list, not one position.
			var w2_assigned_a: int = _w2_match_patrol_path(w2_got_pts, w2_paths)
			var w2_assigned_b: int = _w2_match_patrol_path(w2_g1_pts, w2_paths)
			w2_spawn_ok = w2_assigned_a >= 0 and w2_assigned_b >= 0 \
				and w2_assigned_a != w2_assigned_b \
				and int(w2_mc.get("patrol_paths_assigned")) == 2
			var w2_used_path: Dictionary = {}
			var w2_used_pts: Array = []
			if w2_assigned_a >= 0:
				w2_used_path = w2_paths[w2_assigned_a] as Dictionary
				w2_used_pts = w2_used_path.get("points", []) as Array
				w2_spawn_ok = w2_spawn_ok \
					and w2_got_waits.size() == w2_used_pts.size() \
					and w2_got_yaws.size() == w2_used_pts.size() \
					and w2_got_facing.size() == w2_used_pts.size() \
					and str(w2_g0.get("patrol_loop_mode")) == str(w2_used_path.get("loop_type", ""))
				if w2_spawn_ok:
					for w2_k: int in range(w2_used_pts.size()):
						var w2_apt: Dictionary = w2_used_pts[w2_k] as Dictionary
						var w2_ap_ar: Array = w2_apt.get("pos", []) as Array
						var w2_expect := Vector3(float(w2_ap_ar[0]), float(w2_ap_ar[1]), float(w2_ap_ar[2]))
						if not (w2_got_pts[w2_k] is Vector3) or (w2_got_pts[w2_k] as Vector3).distance_to(w2_expect) > 0.05 \
							or not is_equal_approx(float(w2_got_waits[w2_k]), float(w2_apt.get("wait", 0.0))) \
							or not is_equal_approx(float(w2_got_yaws[w2_k]), float(w2_apt.get("yaw", 0.0))) \
							or bool(w2_got_facing[w2_k]) != bool(w2_apt.get("facing", false)):
							w2_spawn_ok = false
							break
			# WaitSeconds dwell + authored facing yaw on the real guard. The
			# guard joins the tree for this check (global_position needs a
			# world); authored patrol data is already assigned, so _ready keeps
			# it instead of installing the legacy square.
			w2_mc.remove_child(w2_g0)
			root.add_child(w2_g0)
			w2_g0.set_physics_process(false)
			await physics_frame
			if w2_assigned_a >= 0:
				var w2_wait_i: int = -1
				for w2_wi: int in range(w2_used_pts.size()):
					if float((w2_used_pts[w2_wi] as Dictionary).get("wait", 0.0)) > 0.0 and w2_wi < w2_used_pts.size() - 1:
						w2_wait_i = w2_wi
						break
				if w2_wait_i >= 0:
					w2_g0.set("wp_index", w2_wait_i)
					w2_g0.set("_patrol_wait_left", 0.0)
					w2_g0.global_position = w2_got_pts[w2_wait_i] as Vector3
					var w2_wait_s: float = float((w2_used_pts[w2_wait_i] as Dictionary).get("wait", 0.0))
					var w2_waiting: bool = bool(w2_g0.call("_patrol_service_waypoint", 0.0))
					var w2_wait_held: bool = is_equal_approx(float(w2_g0.get("_patrol_wait_left")), w2_wait_s)
					var w2_index_before: int = int(w2_g0.get("wp_index"))
					w2_g0.call("_patrol_service_waypoint", w2_wait_s + 0.1)
					var w2_advanced: bool = int(w2_g0.get("wp_index")) != w2_index_before
					w2_spawn_ok = w2_spawn_ok and w2_waiting and w2_wait_held and w2_advanced
				var w2_facing_i: int = -1
				for w2_fi: int in range(w2_used_pts.size()):
					if bool((w2_used_pts[w2_fi] as Dictionary).get("facing", false)):
						w2_facing_i = w2_fi
						break
				if w2_facing_i >= 0:
					var w2_yaw_deg: float = float((w2_used_pts[w2_facing_i] as Dictionary).get("yaw", 0.0))
					w2_g0.set("rotation", Vector3.ZERO)
					w2_g0.call("_apply_patrol_yaw", 1.0, w2_facing_i)
					var w2_expect_yaw: float = deg_to_rad(-(w2_yaw_deg + 90.0))
					w2_spawn_ok = w2_spawn_ok and absf(angle_difference((w2_g0 as Node3D).rotation.y, w2_expect_yaw)) < 0.001
			# PingPong reversal: synthetic three-point path at both ends.
			var w2_pp: Node3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as Node3D
			w2_pp.set("patrol_points", [Vector3.ZERO, Vector3(2.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0)] as Array[Vector3])
			w2_pp.set("patrol_loop_mode", "EPatrolLoopType::PingPong")
			w2_pp.set("wp_index", 0)
			w2_pp.set("_patrol_dir", 1)
			w2_pp.call("_advance_patrol_index")
			w2_pp.call("_advance_patrol_index")
			var w2_at_end: bool = int(w2_pp.get("wp_index")) == 2
			w2_pp.call("_advance_patrol_index")
			var w2_pp_back: bool = int(w2_pp.get("wp_index")) == 1 and int(w2_pp.get("_patrol_dir")) == -1
			w2_pp.call("_advance_patrol_index")
			var w2_pp_back2: bool = int(w2_pp.get("wp_index")) == 0
			w2_pp.call("_advance_patrol_index")
			var w2_pp_turn: bool = int(w2_pp.get("wp_index")) == 1 and int(w2_pp.get("_patrol_dir")) == 1
			w2_pp.free()
			w2_spawn_ok = w2_spawn_ok and w2_at_end and w2_pp_back and w2_pp_back2 and w2_pp_turn
		if w2_g0 != null and w2_g0.is_inside_tree():
			w2_g0.queue_free()
			await process_frame
		w2_mc.free()
		# No authored path within 30 m -> synthetic square + one logged line.
		var w2_mc2: Node = (load("res://src/missions/mission_controller.gd") as GDScript).new()
		var w2_far := Vector3(9000.0, 0.0, 9000.0)
		w2_mc2.call("_spawn_guards", [w2_far], w2_far + Vector3(20.0, 0.0, 20.0), w2_paths)
		var w2_far_children: Array[Node] = w2_mc2.get_children()
		var w2_fg: Node = w2_far_children[0] if w2_far_children.size() > 0 else null
		var w2_fg_pts: Array = w2_fg.get("patrol_points") as Array if w2_fg != null else []
		var w2_fb_log: Array = w2_mc2.get("patrol_fallback_log") as Array
		var w2_fb_line: String = str(w2_fb_log[0]) if w2_fb_log.size() > 0 else ""
		w2_fallback_ok = w2_fg != null and w2_fg_pts.size() == 4 \
			and int(w2_mc2.get("patrol_fallback_count")) == 1 \
			and w2_fb_line.find("patrol fallback") >= 0 and w2_fb_line.find("nearest") >= 0
		w2_mc2.free()
	if w2_paths.size() >= 100 and w2_wp_total >= 300 and w2_preserved and w2_spawn_ok and w2_fallback_ok:
		print("PASS: 55a authored patrols merged (", w2_paths.size(), " paths / ", w2_wp_total, " waypoints) and assigned (waits/yaws/PingPong/fallback log)")
	else:
		printerr("FAIL: 55a authored patrols (paths=", w2_paths.size(), " waypoints=", w2_wp_total, " preserved=", w2_preserved, " spawn=", w2_spawn_ok, " fallback=", w2_fallback_ok, ")")
		fails += 1

	# 55b. DA_LoudnessModifiers surface loudness: generated data, GameData
	# accessor, NoiseBus multiplier and guard hearing.
	var w2_ga_v: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/gameplay/guard_ai.json"))
	var w2_surface: Dictionary = ((w2_ga_v as Dictionary).get("surface_loudness", {}) as Dictionary) if w2_ga_v is Dictionary else {}
	var w2_surface_ok: bool = w2_surface.size() == 22 \
		and is_equal_approx(float(w2_surface.get("Carpet", -1.0)), 0.0) \
		and is_equal_approx(float(w2_surface.get("Foliage", -1.0)), 0.0) \
		and is_equal_approx(float(w2_surface.get("Grass", -1.0)), 0.0) \
		and is_equal_approx(float(w2_surface.get("Dirt", -1.0)), 0.0) \
		and is_equal_approx(float(w2_surface.get("Ivy", -1.0)), 0.0) \
		and is_equal_approx(float(w2_surface.get("Glass", -1.0)), 1.5) \
		and is_equal_approx(float(w2_surface.get("Stone", -1.0)), 1.5) \
		and is_equal_approx(float(w2_surface.get("MetalThick", -1.0)), 1.5) \
		and is_equal_approx(float(w2_surface.get("Lattice", -1.0)), 1.0) \
		and is_equal_approx(float(w2_surface.get("Tile", -1.0)), 1.0)
	var w2_gd_ok: bool = is_equal_approx(gd.get_surface_loudness("Carpet"), 0.0) \
		and is_equal_approx(gd.get_surface_loudness("glass"), 1.5) \
		and is_equal_approx(gd.get_surface_loudness("Stone"), 1.5) \
		and is_equal_approx(gd.get_surface_loudness(""), 1.0) \
		and is_equal_approx(gd.get_surface_loudness("not_a_surface"), 1.0)
	var w2_radii: Array[float] = []
	var w2_nb_cb: Callable = func(_o: Vector3, l: float, _s: Node, _t: String) -> void:
		w2_radii.append(l)
	nb.connect("noise_emitted", w2_nb_cb)
	nb.call("emit_noise", Vector3.ZERO, 4.0, null, "footstep", "Carpet")
	nb.call("emit_noise", Vector3.ZERO, 4.0, null, "footstep", "Glass")
	nb.call("emit_noise", Vector3.ZERO, 4.0, null, "footstep")
	nb.disconnect("noise_emitted", w2_nb_cb)
	var w2_ratio_ok: bool = w2_radii.size() == 3 \
		and is_equal_approx(w2_radii[0], 0.0) and is_equal_approx(w2_radii[1], 6.0) and is_equal_approx(w2_radii[2], 4.0)
	# Guard hearing receives the modified radius exactly once.
	var w2_ear_guard: Node3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as Node3D
	w2_ear_guard.name = "Guard_W2Ear"
	w2_ear_guard.position = Vector3(6000.0, 0.0, 6000.0)
	root.add_child(w2_ear_guard)
	await process_frame
	w2_ear_guard.set_physics_process(false)
	nb.call("emit_noise", w2_ear_guard.global_position + Vector3(3.0, 0.0, 0.0), 8.0, null, "footstep", "carpet")
	var w2_carpet_silent: bool = is_equal_approx(float(w2_ear_guard.get("detection")), 0.0) and int(w2_ear_guard.get("state")) == 0
	nb.call("emit_noise", w2_ear_guard.global_position + Vector3(5.0, 0.0, 0.0), 3.5, null, "footstep", "glass")
	# W6G: hearing raises alertness only; it no longer seeds the 0..100 meter
	# (that is the sight ramp's). The state transition is the real contract, and
	# detection must stay 0 so a heard noise cannot leak suspicion into sight.
	var w2_glass_walk: bool = int(w2_ear_guard.get("state")) != 0 and is_zero_approx(float(w2_ear_guard.get("detection"))) \
		and str(w2_ear_guard.get("last_heard_stim_tag")) == "AI.Stim.Hearing.Footstep.Walking"
	w2_ear_guard.set("state", 0)
	w2_ear_guard.set("detection", 0.0)
	nb.call("emit_noise", w2_ear_guard.global_position + Vector3(8.0, 0.0, 0.0), 8.0, null, "footstep", "glass")
	var w2_glass_sprint8: bool = int(w2_ear_guard.get("state")) != 0 and is_zero_approx(float(w2_ear_guard.get("detection"))) \
		and str(w2_ear_guard.get("last_heard_stim_tag")) == "AI.Stim.Hearing.Footstep.Running"
	w2_ear_guard.queue_free()
	await process_frame
	if w2_surface_ok and w2_gd_ok and w2_ratio_ok and w2_carpet_silent and w2_glass_walk and w2_glass_sprint8:
		print("PASS: 55b surface loudness (22 authored rows, Carpet 0.0/Glass 1.5, radii 0/6/4, carpet sprint silent @3m, glass walk heard @5m, glass run heard @8m; authored Walking/Running stim, meter stays 0)")
	else:
		printerr("FAIL: 55b surface loudness (json=", w2_surface_ok, " api=", w2_gd_ok, " ratio=", w2_ratio_ok, " carpet=", w2_carpet_silent, " glass_walk=", w2_glass_walk, " glass_run8=", w2_glass_sprint8, " radii=", w2_radii, ")")
		fails += 1

	# 55c. Interaction LOS and takedown gates: world geometry blocks the
	# nearest-interactable prompt, direct guard pickpocket and blackjack, while
	# open-floor pickpocket and behind-guard takedown still work.
	var w2_base := Vector3(5000.0, 0.0, 5000.0)
	var w2_target_scr: GDScript = load("res://src/interact/loot_container.gd") as GDScript
	var w2_target: Area3D = w2_target_scr.new() as Area3D
	w2_target.name = "W2Container"
	w2_target.call("configure", "BP_MissionSpawner_MinorLoot_C", {"pos": w2_base + Vector3(0.0, 0.0, 1.2), "basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]}, 0)
	root.add_child(w2_target)
	var w2_wall_a: StaticBody3D = _w2_make_wall(root, w2_base + Vector3(0.0, 1.0, 0.6))
	var w2_player: Node3D = (load("res://src/player/thief_character.gd") as GDScript).new() as Node3D
	w2_player.name = "W2Thief"
	w2_player.position = w2_base
	root.add_child(w2_player)
	w2_player.set_physics_process(false)
	await process_frame
	var w2_blocked: bool = w2_player.call("get_nearest_interactable") == null \
		and str(w2_player.call("get_look_interact_prompt")) == ""
	w2_wall_a.queue_free()
	await process_frame
	await physics_frame
	var w2_open: bool = w2_player.call("get_nearest_interactable") == w2_target \
		and str(w2_player.call("get_look_interact_prompt")) == "[F] OPEN"

	# Direct guard pickpocket: open floor steals, wall refuses without escalation.
	var w2_pick_guard: Node3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as Node3D
	w2_pick_guard.name = "Guard_W2Pick"
	w2_pick_guard.position = w2_base + Vector3(10.0, 0.0, 10.0)
	root.add_child(w2_pick_guard)
	w2_pick_guard.set_physics_process(false)
	await process_frame
	w2_pick_guard.call("set_carried_item", {"name": "W2 Key", "kind": "key", "id": "w2_key", "value": 10})
	w2_player.position = w2_pick_guard.global_position + Vector3(0.0, 0.0, 1.2)
	w2_player.set_physics_process(false)
	await physics_frame
	var w2_pick_prompt: bool = w2_player.call("get_nearest_interactable") != null \
		and str(w2_player.call("get_look_interact_prompt")) == "[F] PICK POCKET"
	w2_pick_guard.call("interact", w2_player)
	var w2_pick_open: bool = not bool(w2_pick_guard.call("has_carried_item"))
	w2_pick_guard.call("set_carried_item", {"name": "W2 Key", "kind": "key", "id": "w2_key", "value": 10})
	w2_pick_guard.set("state", 0)
	var w2_wall_pick: StaticBody3D = _w2_make_wall(root, w2_pick_guard.global_position + Vector3(0.0, 1.0, 0.6))
	await physics_frame
	var w2_pick_blocked_prompt: bool = w2_player.call("get_nearest_interactable") == null \
		and str(w2_player.call("get_look_interact_prompt")) == ""
	w2_pick_guard.call("interact", w2_player)
	var w2_pick_wall: bool = bool(w2_pick_guard.call("has_carried_item")) and int(w2_pick_guard.get("state")) == 0
	w2_wall_pick.queue_free()
	await physics_frame

	# Blackjack: behind works; in front or behind a wall is refused.
	var w2_take_guard: Node3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as Node3D
	w2_take_guard.name = "Guard_W2Take"
	w2_take_guard.position = Vector3(5300.0, 0.0, 5300.0)
	w2_take_guard.rotation = Vector3.ZERO
	root.add_child(w2_take_guard)
	w2_take_guard.set_physics_process(false)
	await process_frame
	w2_take_guard.rotation = Vector3.ZERO
	w2_player.position = w2_take_guard.global_position + Vector3(0.0, 0.0, 1.5)
	await physics_frame
	var w2_behind_prompt: bool = str(w2_player.call("get_look_secondary_prompt")) == "[F] [HOLD] TAKEDOWN"
	w2_player.call("_try_blackjack", w2_take_guard)
	# RE-F-12: the KO now lands at the authored blackjack contact (0.390 s into
	# the 0.667 s swing, CombatHitbox 0.280-0.500 s), not on the key frame.
	# Advance the notify clock deterministically instead of waiting wall-clock
	# frames; the assertion (behind -> KO) is unchanged.
	w2_player.call("_tick_pending_melee", 0.5)
	var w2_behind_ko: bool = int(w2_take_guard.get("state")) == 5
	var w2_front_guard: Node3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as Node3D
	w2_front_guard.name = "Guard_W2Front"
	w2_front_guard.position = Vector3(5600.0, 0.0, 5600.0)
	w2_front_guard.rotation = Vector3.ZERO
	root.add_child(w2_front_guard)
	w2_front_guard.set_physics_process(false)
	await process_frame
	w2_front_guard.rotation = Vector3.ZERO
	w2_player.position = w2_front_guard.global_position + Vector3(0.0, 0.0, -1.5)
	await physics_frame
	var w2_front_refused: bool = w2_player.call("_find_nearest_guard", 2.4) == null \
		and str(w2_player.call("get_look_secondary_prompt")) != "[F] [HOLD] TAKEDOWN"
	w2_player.call("_try_blackjack", w2_front_guard)
	w2_front_refused = w2_front_refused and int(w2_front_guard.get("state")) != 5
	var w2_wall_guard: Node3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as Node3D
	w2_wall_guard.name = "Guard_W2Wall"
	w2_wall_guard.position = Vector3(5900.0, 0.0, 5900.0)
	w2_wall_guard.rotation = Vector3.ZERO
	root.add_child(w2_wall_guard)
	w2_wall_guard.set_physics_process(false)
	await process_frame
	w2_wall_guard.rotation = Vector3.ZERO
	w2_player.position = w2_wall_guard.global_position + Vector3(0.0, 0.0, 1.5)
	var w2_wall_take: StaticBody3D = _w2_make_wall(root, w2_wall_guard.global_position + Vector3(0.0, 1.0, 0.75))
	await physics_frame
	var w2_take_wall_refused: bool = w2_player.call("_find_nearest_guard", 2.4) == null \
		and str(w2_player.call("get_look_secondary_prompt")) != "[F] [HOLD] TAKEDOWN"
	w2_player.call("_try_blackjack", w2_wall_guard)
	w2_take_wall_refused = w2_take_wall_refused and int(w2_wall_guard.get("state")) != 5
	w2_wall_take.queue_free()
	await physics_frame
	# 55c-live (RE-I-14): every check above froze physics and called
	# `_try_blackjack` directly, so no AI tick and no hold race ran. The same
	# takedown now runs with a real ticking guard, the real 0.45 s hold clock and
	# `_perform_hold_action`: inside the authored 1.0 m MinimumSightRadius cone
	# bypass the old 3.5 m bypass lost this race (detection 61.25 at release,
	# ever_spotted set, guard awake). See tests/probe_blackjack_race.gd.
	var w2_live_floor: StaticBody3D = _w2_make_floor(root, Vector3(6200.0, -0.55, 6200.0))
	await physics_frame
	var w2_live: Dictionary = await _ai_blackjack_hold(root, Vector3(6200.0, 0.0, 6200.0), 2.2)
	var w2_live_ok: bool = str(w2_live.get("prompt", "")) == "[F] [HOLD] TAKEDOWN" \
		and float(w2_live.get("held", 0.0)) >= 0.45 \
		and bool(w2_live.get("ko", false)) \
		and not bool(w2_live.get("spot", true)) \
		and float(w2_live.get("detection", 1.0)) <= 0.0
	if w2_blocked and w2_open and w2_pick_prompt and w2_pick_open and w2_pick_blocked_prompt and w2_pick_wall and w2_behind_prompt and w2_behind_ko and w2_front_refused and w2_take_wall_refused and w2_live_ok:
		print("PASS: 55c interaction LOS (wall blocks container/prompt), pickpocket (open steals, wall refuses without escalation), takedown (behind works, front/wall refuse, live 0.45 s hold wins)")
	else:
		printerr("FAIL: 55c interaction LOS (container_blocked=", w2_blocked, " open=", w2_open, " pick_prompt=", w2_pick_prompt, " pick_open=", w2_pick_open, " pick_blocked_prompt=", w2_pick_blocked_prompt, " pick_wall=", w2_pick_wall, " behind_prompt=", w2_behind_prompt, " behind_ko=", w2_behind_ko, " front_refused=", w2_front_refused, " wall_refused=", w2_take_wall_refused, " live=", w2_live, ")")
		fails += 1
	w2_live_floor.queue_free()
	w2_player.queue_free()
	w2_target.queue_free()
	w2_pick_guard.queue_free()
	w2_take_guard.queue_free()
	w2_front_guard.queue_free()
	w2_wall_guard.queue_free()
	await process_frame

	# 55d. Civilian capsule: layer 4 (bit 8), radius 0.35 / height 1.7 /
	# centre 0.85, settles on the floor with < 0.05 m y drift over 5 s.
	var w2_floor: StaticBody3D = _w2_make_floor(root, Vector3(7000.0, -0.5, 7000.0))
	var w2_civ_scr: GDScript = load("res://src/ai/civilian_npc.gd") as GDScript
	var w2_civ: Node3D = w2_civ_scr.new() as Node3D
	w2_civ.name = "W2Civilian"
	w2_civ.call("setup", "", "", Vector3(7000.0, 0.02, 7000.0))
	w2_civ.position = Vector3(7000.0, 0.02, 7000.0)
	root.add_child(w2_civ)
	await process_frame
	var w2_civ_col: CollisionShape3D = w2_civ.get_node_or_null("CivilianCollision") as CollisionShape3D
	var w2_civ_cap: CapsuleShape3D = w2_civ_col.shape as CapsuleShape3D if w2_civ_col != null else null
	var w2_civ_shape_ok: bool = w2_civ_col != null and w2_civ_cap != null \
		and is_equal_approx(w2_civ_cap.radius, 0.35) and is_equal_approx(w2_civ_cap.height, 1.7) \
		and is_equal_approx(w2_civ_col.position.y, 0.85) \
		and int(w2_civ.get("collision_layer")) == 8 and int(w2_civ.get("collision_mask")) == 1
	var w2_civ_y0: float = w2_civ.global_position.y
	await physics_frame
	await physics_frame
	for w2_step: int in range(300):
		await physics_frame
	var w2_civ_drift: float = absf(w2_civ.global_position.y - w2_civ_y0)
	var w2_civ_floor: bool = bool(w2_civ.call("is_on_floor")) and w2_civ.global_position.y >= -0.01
	if w2_civ_shape_ok and w2_civ_drift < 0.05 and w2_civ_floor:
		print("PASS: 55d civilian capsule (layer 4, r=0.35 h=1.7 y=0.85) settles on floor, y drift=", snappedf(w2_civ_drift, 0.0001), " m over 5 s")
	else:
		printerr("FAIL: 55d civilian capsule (shape=", w2_civ_shape_ok, " drift=", w2_civ_drift, " on_floor=", w2_civ_floor, " y=", w2_civ.global_position.y, ")")
		fails += 1
	w2_civ.queue_free()
	w2_floor.queue_free()
	await process_frame
	w2_ll.queue_free()
	w2_host.queue_free()
	await process_frame

	# 65. Authored clues, quest items and journal (W4). All expected strings are
	# read from / asserted against the shipped generators (clues.json,
	# quests.json); the only literal strings are the seven Contract 2 journal
	# facts and the authored Set objective text.
	var c65_ok: bool = true
	var c65_mc: Node = (load("res://src/missions/mission_controller.gd") as GDScript).new()
	# 65a. Fact totals: 96 authored, 90 reachable, 6 dead, 0 suppressed.
	var c65_reachable: int = 0
	for c65_fid_v: Variant in gd.clue_facts.keys():
		var c65_f: Dictionary = gd.clue_facts[c65_fid_v] as Dictionary
		if c65_f.get("reachable", false) == true:
			c65_reachable += 1
	if gd.clue_facts.size() != 96 or c65_reachable != 90 or gd.dead_fact_ids.size() != 6 or not gd.suppressed_fact_ids.is_empty():
		printerr("FAIL: 65 clue facts totals: total=", gd.clue_facts.size(), " reachable=", c65_reachable, " dead=", gd.dead_fact_ids.size(), " suppressed=", gd.suppressed_fact_ids.size())
		c65_ok = false
	# 65b. Contract 2: exactly 7 facts, 3 priority-1 + 4 priority-2, exact text.
	var c65_c2_texts: Array[String] = []
	var c65_p1: int = 0
	var c65_p2: int = 0
	var c65_suppressed: int = 0
	for c65_fid_v: Variant in gd.clue_facts.keys():
		var c65_fid: String = str(c65_fid_v)
		if not c65_fid.begins_with("DT_ClueFacts_Contracts_02:"):
			continue
		var c65_f: Dictionary = gd.clue_facts[c65_fid_v] as Dictionary
		c65_c2_texts.append(str(c65_f.get("journal_text", "")))
		var c65_prio: int = int(c65_f.get("display_priority", 0))
		if c65_prio == 1:
			c65_p1 += 1
		elif c65_prio == 2:
			c65_p2 += 1
		var c65_sup_v: Variant = c65_f.get("suppressed_by", [])
		if c65_sup_v is Array and not (c65_sup_v as Array).is_empty():
			c65_suppressed += 1
	var c65_c2_expect: Array[String] = [
		"The Chief Constable has taken a personal interest in the theft of the Vistara Diamond.",
		"The files are somewhere on the second floor",
		"The files are on a desk in the bullpen",
		"The files are on a constable's desk",
		"The Vistara files are being processed on the second floor.",
		"The officer named Sgt. Campbell has a desk in the middle of the bullpen",
		"The Vistara Diamond was brought to Kilkairn by Mr. Hugh Montogomery, by irregular means.",
	]
	c65_c2_expect.sort()
	c65_c2_texts.sort()
	if c65_c2_texts.size() != 7 or c65_p1 != 3 or c65_p2 != 4 or c65_suppressed != 0 or c65_c2_texts != c65_c2_expect:
		printerr("FAIL: 65 Contract 2 facts: count=", c65_c2_texts.size(), " p1=", c65_p1, " p2=", c65_p2, " suppressed=", c65_suppressed, " texts=", c65_c2_texts)
		c65_ok = false
	# 65c. CLS_Contract_02: 6 enabled / 0 disabled, authored placement demand.
	var c65_set: Dictionary = gd.get_clue_set("CLS_Contract_02")
	var c65_counts: Dictionary = c65_set.get("counts", {}) as Dictionary
	var c65_demand: Dictionary = c65_set.get("placement_demand", {}) as Dictionary
	if int(c65_counts.get("enabled", -1)) != 6 or int(c65_counts.get("disabled", -1)) != 0 \
			or int(c65_demand.get("CluePlacement.Common.Guildhall.Contracts.Entrance", 0)) != 1 \
			or int(c65_demand.get("CluePlacement.Common.Guildhall.Contracts.FirstFloor", 0)) != 3 \
			or int(c65_demand.get("CluePlacement.Common.Guildhall.Contracts.SecondFloor", 0)) != 2:
		printerr("FAIL: 65 CLS_Contract_02 counts/demand: ", c65_counts, " demand=", c65_demand)
		c65_ok = false
	# 65d. Guildhall_Contracts carries 28 authored readable spawners.
	var c65_contract_levels: Array = ["Guildhall/Guildhall_Contracts"]
	if gd.get_readable_spawners("guildhall", "", c65_contract_levels).size() != 28:
		printerr("FAIL: 65 Guildhall_Contracts readable spawners=", gd.get_readable_spawners("guildhall", "", c65_contract_levels).size())
		c65_ok = false
	# 65e. Spawn pass: 6 distinct readable clues with the authored bodies.
	var c65_reqs: Array[Dictionary] = [{"set": "CLS_Contract_02", "mode": "all", "loot_tag": "", "node": ""}]
	var c65_recs: Array = c65_mc.call("spawn_clue_requests", c65_reqs, "guildhall", 424242, c65_contract_levels, [] as Array)
	var c65_spawner_keys: Dictionary = {}
	var c65_bodies: Array[String] = []
	var c65_expect_bodies: Array[String] = []
	var c65_clues_v: Variant = c65_set.get("clues", [])
	if c65_clues_v is Array:
		for c65_clue_v: Variant in (c65_clues_v as Array):
			if c65_clue_v is Dictionary and (c65_clue_v as Dictionary).get("enabled", false) == true:
				c65_expect_bodies.append(str((c65_clue_v as Dictionary).get("text", "")))
	c65_expect_bodies.sort()
	for c65_rec_v: Variant in c65_recs:
		var c65_rec: Dictionary = c65_rec_v as Dictionary
		c65_bodies.append(str(c65_rec.get("body", "")))
		var c65_sp: Dictionary = c65_rec.get("spawner", {}) as Dictionary
		c65_spawner_keys["%s|%s|%s" % [str(c65_sp.get("level", "")), str(c65_sp.get("actor", "")), str(c65_sp.get("pos", []))]] = true
		var c65_node: Node = c65_rec.get("node", null) as Node
		if c65_node == null or str(c65_node.get("clue_body")) != str(c65_rec.get("body", "")) or str(c65_node.call("get_interact_prompt")) != "[E] Read":
			printerr("FAIL: 65 spawned clue node/body/prompt mismatch: ", c65_rec)
			c65_ok = false
	c65_bodies.sort()
	if c65_recs.size() != 6 or c65_spawner_keys.size() != 6 or c65_bodies != c65_expect_bodies:
		printerr("FAIL: 65 clue spawn pass: records=", c65_recs.size(), " distinct=", c65_spawner_keys.size(), " bodies=", c65_bodies)
		c65_ok = false
	# 65f. Guildhall Set plan: one reachable objective, authored text, 3 gems.
	var c65_set_plan: Dictionary = gd.get_mission_plan("Mission.Guildhall.Set")
	var c65_set_objs: Array = c65_set_plan.get("objectives", []) as Array
	var c65_set_obj: Dictionary = c65_set_objs[0] as Dictionary if c65_set_objs.size() == 1 else {}
	var c65_gem_names: Array[String] = []
	var c65_set_items: Array = c65_set_obj.get("items", []) as Array
	for c65_item_v: Variant in c65_set_items:
		c65_gem_names.append(str((c65_item_v as Dictionary).get("display_name", "")))
	c65_gem_names.sort()
	var c65_gem_expect: Array[String] = ["Gem of Arcana", "Gem of Fire", "Gem of Strength"]
	if c65_set_objs.size() != 1 \
			or str(c65_set_obj.get("objective_text", "")) != "Steal the components of the Staff of Edinburgh" \
			or c65_gem_names != c65_gem_expect \
			or int(c65_set_obj.get("min_number_to_steal", 0)) != 1 \
			or c65_set_obj.get("override_min_number_to_steal", true) != false \
			or int(c65_set_plan.get("endgame_duration", 0)) != 480:
		printerr("FAIL: 65 Guildhall Set plan: objs=", c65_set_objs.size(), " text='", c65_set_obj.get("objective_text", ""), "' gems=", c65_gem_names, " min=", c65_set_obj.get("min_number_to_steal"), " endgame=", c65_set_plan.get("endgame_duration"))
		c65_ok = false
	# 65g. Set quest items spawn on 3 distinct authored Office spawners.
	var c65_guildhall_levels: Array = ["Guildhall/Guildhall_Gameplay", "Guildhall/Guildhall_Loot", "Guildhall/Guildhall_SetSpawners", "Guildhall/Guildhall_MissionClues"]
	var c65_gem_recs: Array = c65_mc.call("spawn_authored_quest_items", c65_set_obj, "guildhall", 9090, c65_guildhall_levels)
	var c65_gem_spawners: Dictionary = {}
	var c65_gem_spawned_names: Array[String] = []
	var c65_forbidden: Array[String] = ["Sapphire", "Ruby", "Emerald of Edinburgh", "Relic Piece", "Claymur"]
	for c65_rec_v: Variant in c65_gem_recs:
		var c65_rec: Dictionary = c65_rec_v as Dictionary
		c65_gem_spawned_names.append(str(c65_rec.get("display_name", "")))
		var c65_sp: Dictionary = c65_rec.get("spawner", {}) as Dictionary
		c65_gem_spawners["%s|%s" % [str(c65_sp.get("level", "")), str(c65_sp.get("actor", ""))]] = true
		if str(c65_sp.get("quest_location_tag", "")) != "QuestLocation.Office":
			printerr("FAIL: 65 Set gem spawner tag: ", c65_sp.get("quest_location_tag"))
			c65_ok = false
		for c65_bad: String in c65_forbidden:
			if str(c65_rec.get("display_name", "")).find(c65_bad) >= 0:
				printerr("FAIL: 65 invented Set gem label: ", c65_rec.get("display_name"))
				c65_ok = false
	c65_gem_spawned_names.sort()
	gs.clue_facts.clear()
	for c65_rec_v: Variant in c65_gem_recs:
		var c65_rec: Dictionary = c65_rec_v as Dictionary
		var c65_fids: Array = c65_rec.get("fact_ids", []) as Array
		for c65_fid_v: Variant in c65_fids:
			gs.grant_fact(str(c65_fid_v), c65_rec.get("fact_params", {}) as Dictionary, "loot", str(c65_rec.get("loot_tag", "")), 0)
	for c65_entry: Dictionary in gs.clue_facts:
		for c65_bad: String in c65_forbidden:
			if str(c65_entry.get("journal_text", "")).find(c65_bad) >= 0:
				printerr("FAIL: 65 invented Set journal text: ", c65_entry.get("journal_text"))
				c65_ok = false
	if c65_gem_recs.size() != 3 or c65_gem_spawners.size() != 3 or c65_gem_spawned_names != c65_gem_expect:
		printerr("FAIL: 65 Set gem spawn: records=", c65_gem_recs.size(), " distinct=", c65_gem_spawners.size(), " names=", c65_gem_spawned_names)
		c65_ok = false
	# 65h. LootTheRoom plan: authored goals/durations, no 1000*difficulty ladder.
	var c65_lt: Dictionary = gd.get_mission_plan("Mission.Guildhall.LootTheRoom")
	var c65_goals: Array = c65_lt.get("loot_goals", []) as Array
	var c65_durs: Array = c65_lt.get("durations", []) as Array
	if c65_goals.size() != 3 or int(c65_goals[0]) != 4000 or int(c65_goals[1]) != 6000 or int(c65_goals[2]) != 8000 \
			or int(c65_lt.get("main_phase_duration", 0)) != 1320 \
			or int(c65_lt.get("endgame_duration", 0)) != 480 \
			or c65_durs.size() != 3 or int(c65_durs[0]) != 3300 or int(c65_durs[1]) != 1200 or int(c65_durs[2]) != 1200:
		printerr("FAIL: 65 LootTheRoom plan: goals=", c65_goals, " main=", c65_lt.get("main_phase_duration"), " endgame=", c65_lt.get("endgame_duration"), " durs=", c65_durs)
		c65_ok = false
	# 65i. Journal dedupe: clue 1 twice + Vistara pickup = 2 facts.
	gs.clue_facts.clear()
	var c65_clue1: String = "DT_ClueFacts_Contracts_02:Clue01"
	var c65_clue_node: Area3D = (load("res://src/interact/clue_item.gd") as GDScript).new()
	var c65_clue_fids: Array[String] = [c65_clue1]
	c65_clue_node.set("fact_ids", c65_clue_fids)
	root.add_child(c65_clue_node)
	await process_frame
	c65_clue_node.call("interact", null)
	c65_clue_node.call("interact", null)
	c65_clue_node.queue_free()
	await process_frame
	var c65_contract2: Dictionary = gd.get_quest_contract(2)
	var c65_vobj: Dictionary = gd.enrich_quest_objective(c65_contract2.get("objective", {}) as Dictionary)
	var c65_vlevels: Array = ["Guildhall/Guildhall_Contract_02"]
	var c65_vrecs: Array = c65_mc.call("spawn_authored_quest_items", c65_vobj, "guildhall", 111, c65_vlevels)
	if c65_vrecs.size() == 1:
		var c65_vrec: Dictionary = c65_vrecs[0] as Dictionary
		for c65_fid_v: Variant in (c65_vrec.get("fact_ids", []) as Array):
			gs.grant_fact(str(c65_fid_v), c65_vrec.get("fact_params", {}) as Dictionary, "loot", str(c65_vrec.get("loot_tag", "")), 0)
	if c65_vrecs.size() != 1 or gs.clue_facts.size() != 2 or not gs.has_clue_fact(c65_clue1):
		printerr("FAIL: 65 journal dedupe: vistara_recs=", c65_vrecs.size(), " facts=", gs.clue_facts.size())
		c65_ok = false
	# 65j. Set.Location formats from authored values only.
	gs.clue_facts.clear()
	var c65_setloc: Dictionary = gd.get_fact("DT_ClueFacts_Quest_Guildhall:Set.Location")
	var c65_red: Dictionary = gd.get_loot_quest_row("RedGem")
	var c65_office: Array = gd.get_quest_spawners("guildhall", "QuestLocation.Office", c65_guildhall_levels)
	var c65_basement: String = ""
	for c65_sp_v: Variant in c65_office:
		if str((c65_sp_v as Dictionary).get("clue_location_text", "")) == "basement":
			c65_basement = "basement"
			break
	gs.grant_fact(str(c65_setloc.get("id", "")), {"item": str(c65_red.get("display_name", "")), "Location": c65_basement}, "loot", str(c65_red.get("loot_tag", "")), 0)
	var c65_setloc_text: String = str((gs.clue_facts[-1] as Dictionary).get("journal_text", "")) if not gs.clue_facts.is_empty() else ""
	if str(c65_red.get("display_name", "")) != "Gem of Fire" or c65_basement == "" or c65_setloc_text != "The Gem of Fire is around the basement":
		printerr("FAIL: 65 Set.Location format: item='", c65_red.get("display_name", ""), "' location='", c65_basement, "' text='", c65_setloc_text, "'")
		c65_ok = false
	gs.clue_facts.clear()
	c65_mc.free()
	if not c65_ok:
		fails += 1
	else:
		print("PASS: 65 authored clues/journal (96 facts/90 reachable/6 dead, Contract 2 7 facts + 6 clues on 28 spawners, Guildhall Set gems on 3 Office spawners, LootTheRoom 4000/6000/8000 + 1320/480/3300, dedupe, Set.Location)")
	# 70. W3: authored device runtime layer (detectors, power, turrets, cameras,
	# wards). Data comes only from game/data/generated/gameplay/devices_runtime.json
	# + family_defaults; the brief's "339 linked detectors" is not in the
	# dataset (C_3 feeds 328 devices, 321 of them detectors), so the suite pins
	# the authored numbers and prints the discrepancy rather than inventing one.
	var w3_layer_scr: GDScript = load("res://src/devices/device_layer.gd") as GDScript
	var w3_beam_scr: GDScript = load("res://src/devices/security_beam.gd") as GDScript
	var w3_plate_scr: GDScript = load("res://src/devices/pressure_plate.gd") as GDScript
	var w3_power_scr: GDScript = load("res://src/devices/power_source.gd") as GDScript
	var w3_turret_scr: GDScript = load("res://src/devices/security_turret.gd") as GDScript
	var w3_eye_scr: GDScript = load("res://src/devices/alarm_eye.gd") as GDScript
	var w3_ward_scr: GDScript = load("res://src/devices/ward_zone.gd") as GDScript
	var w3_noise_scr: GDScript = load("res://src/devices/noise_alarm.gd") as GDScript
	var w3_doc: Dictionary = w3_layer_scr.call("runtime_document") as Dictionary
	var w3_scripts_ok: bool = w3_layer_scr != null and w3_beam_scr != null and w3_plate_scr != null and w3_power_scr != null and w3_turret_scr != null and w3_eye_scr != null and w3_ward_scr != null and w3_noise_scr != null
	if not w3_scripts_ok or w3_doc.is_empty():
		printerr("FAIL: 70 device runtime scripts or devices_runtime.json missing")
		fails += 1
	else:
		var w3_stats: Dictionary = w3_doc.get("stats", {}) as Dictionary
		var w3_maps: Dictionary = w3_doc.get("maps", {}) as Dictionary
		var w3_by_map: Dictionary = w3_stats.get("by_map", {}) as Dictionary
		var w3_fam_stats: Dictionary = w3_stats.get("families", {}) as Dictionary
		var w3_counted: Dictionary = {}
		for w3_map_v: Variant in w3_maps.keys():
			var w3_map_id: String = str(w3_map_v)
			var w3_map_data: Dictionary = w3_maps[w3_map_v] as Dictionary
			for w3_rec_v: Variant in (w3_map_data.get("devices", []) as Array):
				if w3_rec_v is Dictionary:
					var w3_fam: String = str((w3_rec_v as Dictionary).get("family", ""))
					w3_counted[w3_fam] = int(w3_counted.get(w3_fam, 0)) + 1
		var w3_total: int = int(w3_stats.get("devices_total", -1))
		var w3_counts_ok: bool = w3_total == 2095 and int(w3_by_map.get("guildhall", -1)) == 903 and int(w3_by_map.get("old_manor", -1)) == 1164 and int(w3_by_map.get("ftue", -1)) == 26 and int(w3_by_map.get("thieves_den", -1)) == 2
		for w3_fam_key: Variant in w3_fam_stats.keys():
			var w3_meta: Dictionary = w3_fam_stats[w3_fam_key] as Dictionary
			# magnetic_lock is component-only: 12 components live on vault
			# doors and are not separate device records (producer stats says
			# component_only=true), so it is not part of the record census.
			if bool(w3_meta.get("component_only", false)):
				continue
			if int(w3_meta.get("loaded", -1)) != int(w3_counted.get(str(w3_fam_key), -2)):
				w3_counts_ok = false
		fails += _w3_check(w3_counts_ok and str(w3_doc.get("schema", "")) == "tat2.devices_runtime/1",
			"70.0 devices_runtime: 2,095 loaded (guildhall 903, old_manor 1164, ftue 26, den 2); 13 device-record family counts match (magnetic_lock is component-only)",
			"70.0 devices_runtime census mismatch: total=%d by_map=%s counted=%s" % [w3_total, w3_by_map, w3_counted])

		# Spawn pass: Guildhall 903 nodes in id order, authored transforms, no scale.
		var w3_layer: Node3D = w3_layer_scr.new() as Node3D
		root.add_child(w3_layer)
		w3_layer.call("set_tick_enabled", false)
		var w3_spawn: int = int(w3_layer.call("spawn_for_map", "guildhall", null, 1))
		var w3_nodes: Dictionary = w3_layer.get("devices") as Dictionary
		var w3_order: Array = (w3_layer.get("device_order") as Array).duplicate()
		var w3_sample_ids: Array[String] = [
			"guildhall/Building_Guildhall_POI:BP_PowerSupply_LightSwitch_C_0",
			"guildhall/Guildhall_Gameplay:BP_Detector_LightBeam_C_1",
			"guildhall/Guildhall_Gameplay:BP_Detector_PressurePlate_C_107",
			"guildhall/Guildhall_Gameplay:BP_SecurityTurret_180_C_1",
			"guildhall/Guildhall_Gameplay:BP_WardZone_Blocker_C_47",
		]
		var w3_rec_by_id: Dictionary = {}
		for w3_map_v2: Variant in w3_maps.keys():
			for w3_rec_v2: Variant in (((w3_maps[w3_map_v2] as Dictionary).get("devices", [])) as Array):
				if w3_rec_v2 is Dictionary:
					var w3_rid: String = str((w3_rec_v2 as Dictionary).get("id", ""))
					if not w3_rid.is_empty():
						w3_rec_by_id[w3_rid] = w3_rec_v2
		var w3_spawn_ok: bool = w3_spawn == 903 and w3_nodes.size() == 903 and w3_order.size() == 903
		w3_spawn_ok = w3_spawn_ok and int(w3_layer.call("family_count", "turret")) == 229 and int(w3_layer.call("family_count", "pressure_plate")) == 162 and int(w3_layer.call("family_count", "light_beam")) == 134 and int(w3_layer.call("family_count", "ward_blocker")) == 36 and int(w3_layer.call("family_count", "ward_slow")) == 41
		var w3_sample_lines: Array[String] = []
		for w3_sid: String in w3_sample_ids:
			var w3_rec: Dictionary = w3_rec_by_id.get(w3_sid, {}) as Dictionary
			var w3_node: Node3D = w3_nodes.get(w3_sid) as Node3D
			if w3_node == null or w3_rec.is_empty():
				w3_spawn_ok = false
				w3_sample_lines.append(w3_sid + ":missing")
				continue
			var w3_p: Array = w3_rec.get("pos", []) as Array
			var w3_expected := Vector3(float(w3_p[0]), float(w3_p[1]), float(w3_p[2]))
			var w3_basis_ok: bool = w3_node.global_transform.basis.is_equal_approx(_w3_basis_from_rec(w3_rec))
			var w3_no_scale: bool = w3_node.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE)
			if w3_node.global_position.distance_to(w3_expected) > 0.0005 or not w3_basis_ok or not w3_no_scale:
				w3_spawn_ok = false
			w3_sample_lines.append("%s pos=%s scale=%.3f" % [w3_sid.get_file(), w3_node.global_position, w3_node.global_transform.basis.get_scale().x])
		fails += _w3_check(w3_spawn_ok,
			"70.1 spawn pass: Guildhall 903 devices, id-sorted, 5 authored transforms match (basis exact, scale 1.0); " + str(w3_sample_lines),
			"70.1 spawn pass mismatch: count=%d nodes=%d order=%d lines=%s" % [w3_spawn, w3_nodes.size(), w3_order.size(), w3_sample_lines])

		# Determinism: a second pass gives the identical id order.
		var w3_layer2: Node3D = w3_layer_scr.new() as Node3D
		root.add_child(w3_layer2)
		w3_layer2.call("set_tick_enabled", false)
		var w3_spawn2: int = int(w3_layer2.call("spawn_for_map", "guildhall", null, 1))
		var w3_order2: Array = (w3_layer2.get("device_order") as Array).duplicate()
		var w3_det_ok: bool = w3_spawn2 == w3_spawn and w3_order.size() == w3_order2.size()
		if w3_det_ok:
			for w3_oi: int in range(w3_order.size()):
				if str(w3_order[w3_oi]) != str(w3_order2[w3_oi]):
					w3_det_ok = false
					break
		fails += _w3_check(w3_det_ok,
			"70.2 determinism: two Guildhall spawn passes produce the identical 903-id order",
			"70.2 determinism failed: n1=%d n2=%d" % [w3_order.size(), w3_order2.size()])
		w3_layer2.queue_free()
		await process_frame
		var w3_group_ok: bool = get_nodes_in_group("devices").size() == 903 and get_nodes_in_group("device_detector").size() == 356 and get_nodes_in_group("device_action").size() == 509 and get_nodes_in_group("ward_zone").size() == 77 and get_nodes_in_group("power_source").size() == 38
		fails += _w3_check(w3_group_ok,
			"70.2b groups: devices=903, device_detector=356, device_action=509, ward_zone=77, power_source=38",
			"70.2b group census mismatch: devices=%d detector=%d action=%d ward=%d power=%d" % [get_nodes_in_group("devices").size(), get_nodes_in_group("device_detector").size(), get_nodes_in_group("device_action").size(), get_nodes_in_group("ward_zone").size(), get_nodes_in_group("power_source").size()])

		# 70.3 beam: authored 7.748 m sample, capsule geometry, endpoints,
		# standing/crouch at the authored 1.75 m height, linked action.
		var w3_beam_rec: Dictionary = w3_rec_by_id.get("guildhall/Guildhall_Gameplay:BP_Detector_LightBeam_C_1", {}) as Dictionary
		var w3_defaults: Dictionary = w3_stats.get("family_defaults", {}) as Dictionary
		var w3_beam: Area3D = w3_beam_scr.new() as Area3D
		root.add_child(w3_beam)
		w3_beam.call("configure", w3_beam_rec, w3_defaults, 2)
		w3_beam.global_position = Vector3.ZERO
		var w3_player: W3MockPlayer = W3MockPlayer.new()
		w3_player.add_to_group("player")
		root.add_child(w3_player)
		w3_beam.call("set_player", w3_player)
		var w3_action: W3MockAction = W3MockAction.new()
		root.add_child(w3_action)
		w3_beam.call("set_action_targets", [w3_action])
		var w3_shape: CollisionShape3D = w3_beam.get_node_or_null("BeamPivot/BeamShape") as CollisionShape3D
		var w3_capsule_ok: bool = w3_shape != null and w3_shape.shape is CapsuleShape3D
		if w3_capsule_ok:
			var w3_cap: CapsuleShape3D = w3_shape.shape as CapsuleShape3D
			w3_capsule_ok = absf(float(w3_beam.get("beam_length_m")) - 7.7482395) < 0.0001 and absf(w3_cap.radius - 0.1) < 0.0001 and absf(w3_cap.height - 7.7482395) < 0.001 and absf(w3_shape.position.z - 3.8741198) < 0.001 and absf(w3_shape.rotation.x - PI * 0.5) < 0.0001
		var w3_beam_ok: bool = w3_capsule_ok
		w3_player.global_position = Vector3(0.0, 0.0, 7.9)
		for w3_i: int in range(10):
			w3_beam.call("tick", 0.1)
		w3_beam_ok = w3_beam_ok and int(w3_beam.get("actions_fired")) == 0
		w3_player.global_position = Vector3(0.0, 0.0, 7.5)
		for w3_i: int in range(4):
			w3_beam.call("tick", 0.1)
		var w3_before_half: int = int(w3_beam.get("actions_fired"))
		w3_beam.call("tick", 0.1)
		w3_beam_ok = w3_beam_ok and w3_before_half == 0 and int(w3_beam.get("actions_fired")) == 1 and w3_action.hits == 1
		w3_beam.global_position = Vector3(0.0, 1.75, 0.0)
		w3_player.global_position = Vector3(0.0, 0.0, 1.5)
		w3_player.is_crouching = true
		for w3_i: int in range(10):
			w3_beam.call("tick", 0.1)
		var w3_crouch_fired: int = int(w3_beam.get("actions_fired"))
		w3_player.is_crouching = false
		for w3_i: int in range(5):
			w3_beam.call("tick", 0.1)
		w3_beam_ok = w3_beam_ok and w3_crouch_fired == 1 and int(w3_beam.get("actions_fired")) == 2
		fails += _w3_check(w3_beam_ok,
			"70.3 beam: 7.748 m capsule (r=0.10, centre 3.874); 7.9 m no, 7.5 m fires at 0.5 s; crouched 1.0 m no, standing 1.78 m yes at 1.75 m; linked action fired",
			"70.3 beam failed: capsule=%s fired=%d crouch=%d hits=%d" % [w3_capsule_ok, int(w3_beam.get("actions_fired")), w3_crouch_fired, w3_action.hits])
		w3_beam.queue_free()
		w3_player.queue_free()
		w3_action.queue_free()
		await process_frame

		# 70.4 plate: 1.5 s trigger, 0.2 s reset, damage once per crossing,
		# a second crossing re-triggers.
		var w3_plate_rec: Dictionary = w3_rec_by_id.get("guildhall/Guildhall_Gameplay:BP_Detector_PressurePlate_C_107", {}) as Dictionary
		var w3_plate: Area3D = w3_plate_scr.new() as Area3D
		root.add_child(w3_plate)
		w3_plate.call("configure", w3_plate_rec, w3_defaults, 2)
		w3_plate.global_position = Vector3.ZERO
		var w3_plate_player: W3MockPlayer = W3MockPlayer.new()
		root.add_child(w3_plate_player)
		w3_plate_player.global_position = Vector3.ZERO
		w3_plate.call("set_player", w3_plate_player)
		w3_plate.call("tick", 1.4)
		var w3_p1: int = int(w3_plate.get("actions_fired"))
		w3_plate.call("tick", 0.11)
		var w3_p2: int = int(w3_plate.get("actions_fired"))
		var w3_hp1: float = w3_plate_player.health
		w3_plate.call("tick", 2.0)
		var w3_p3: int = int(w3_plate.get("actions_fired"))
		w3_plate_player.global_position = Vector3(1.5, 0.0, 0.0)
		w3_plate.call("tick", 0.3)
		w3_plate_player.global_position = Vector3.ZERO
		w3_plate.call("tick", 1.6)
		var w3_p4: int = int(w3_plate.get("actions_fired"))
		var w3_plate_ok: bool = w3_p1 == 0 and w3_p2 == 1 and w3_p3 == 1 and w3_p4 == 2 and is_equal_approx(w3_hp1, 290.0) and is_equal_approx(w3_plate_player.health, 280.0) and is_equal_approx(float(w3_plate.get("reset_seconds")), 0.2)
		fails += _w3_check(w3_plate_ok,
			"70.4 plate: 1.5 s trigger, 0.2 s reset, 10 Physical once per crossing, second crossing re-triggers (hp 300->290->280)",
			"70.4 plate failed: fires=%d/%d/%d/%d hp=%.1f/%.1f" % [w3_p1, w3_p2, w3_p3, w3_p4, w3_hp1, w3_plate_player.health])
		w3_plate.queue_free()
		w3_plate_player.queue_free()
		await process_frame

		# 70.4b noise alarm: null _triggeringDuration uses the authored 0.5 s
		# fallback, then emits the 15 m Heavy trap stimulus once.
		var w3_noise_rec: Dictionary = w3_rec_by_id.get("guildhall/Guildhall_Gameplay:BP_Trap_Action_NoiseAlarm_C_0", {}) as Dictionary
		var w3_noise: Node3D = w3_noise_scr.new() as Node3D
		root.add_child(w3_noise)
		w3_noise.call("configure", w3_noise_rec, w3_defaults, 2)
		w3_noise.global_position = Vector3(0.0, 0.0, 300.0)
		var w3_noise_hits: Array = []
		var w3_alarm_cb := func(_o: Vector3, loud: float, _s: Node, tag: String) -> void:
			if tag == "noise_alarm":
				w3_noise_hits.append(loud)
		if nb != null:
			nb.connect("noise_emitted", w3_alarm_cb)
		w3_noise.call("trigger_from", null)
		w3_noise.call("tick", 0.4)
		var w3_noise_before: int = w3_noise_hits.size()
		w3_noise.call("tick", 0.11)
		var w3_noise_after: int = w3_noise_hits.size()
		if nb != null and nb.is_connected("noise_emitted", w3_alarm_cb):
			nb.disconnect("noise_emitted", w3_alarm_cb)
		var w3_noise_ok: bool = is_equal_approx(float(w3_noise.get("trigger_seconds")), 0.5) and w3_noise_before == 0 and w3_noise_after == 1 and is_equal_approx(float(w3_noise_hits[0]), 15.0)
		fails += _w3_check(w3_noise_ok,
			"70.4b noise alarm: null trigger duration -> authored 0.5 s fallback, one 15 m noise_alarm stimulus",
			"70.4b noise alarm failed: trigger=%.2f before=%d after=%d hits=%s" % [float(w3_noise.get("trigger_seconds")), w3_noise_before, w3_noise_after, w3_noise_hits])
		w3_noise.queue_free()
		await process_frame

		# 70.5 power: Guildhall C_3 cuts its authored 328-device graph (321
		# detectors), 30 s auto-reset restores it; breakable health 20.
		var w3_src: Node = w3_layer.call("get_device", "guildhall/Guildhall_Gameplay:BP_PowerSupply_Wall_C_3") as Node
		var w3_power_ok: bool = w3_src != null and bool(w3_src.call("is_powered"))
		var w3_power_lines: Array[String] = []
		if w3_src != null:
			var w3_consumers: Array = w3_src.get_meta("device_consumers", []) as Array
			var w3_auto: float = float(w3_src.get("auto_reset_seconds"))
			w3_power_ok = w3_power_ok and w3_consumers.size() == 328 and is_equal_approx(w3_auto, 30.0) and str(w3_src.call("get_interact_prompt")).begins_with("[F]")
			w3_src.call("set_power_state", false)
			var w3_off: int = 0
			for w3_c_v: Variant in w3_consumers:
				var w3_c: Node = w3_c_v as Node
				if w3_c != null and w3_c.has_method("can_trigger") and not bool(w3_c.call("can_trigger")):
					w3_off += 1
			w3_src.call("tick", 29.9)
			var w3_still_off: bool = not bool(w3_src.call("is_powered"))
			w3_src.call("tick", 0.11)
			var w3_back_on: bool = bool(w3_src.call("is_powered"))
			var w3_reenabled: int = 0
			for w3_c_v2: Variant in w3_consumers:
				var w3_c2: Node = w3_c_v2 as Node
				if w3_c2 != null and w3_c2.has_method("can_trigger") and bool(w3_c2.call("can_trigger")):
					w3_reenabled += 1
			w3_power_lines.append("C_3 consumers=328 detectors_off=%d auto=%.0fs still_off=%.0f reenabled=%d" % [w3_off, w3_auto, 1.0 if w3_still_off else 0.0, w3_reenabled])
			w3_power_ok = w3_power_ok and w3_off == 321 and w3_still_off and w3_back_on and w3_reenabled == 321
		var w3_src_b_rec: Dictionary = w3_rec_by_id.get("guildhall/Guildhall_Gameplay:BP_PowerSupply_Wall_C_1", {}) as Dictionary
		var w3_src_b: Node3D = w3_power_scr.new() as Node3D
		root.add_child(w3_src_b)
		w3_src_b.call("configure", w3_src_b_rec, w3_defaults, 1)
		var w3_break_ok: bool = is_equal_approx(float(w3_src_b.get("health")), 20.0)
		w3_src_b.call("take_damage", 20.0)
		w3_break_ok = w3_break_ok and not bool(w3_src_b.call("is_powered")) and bool(w3_src_b.get("broken"))
		w3_src_b.queue_free()
		fails += _w3_check(w3_power_ok and w3_break_ok,
			"70.5 power: C_3 disables its 321 authored detectors (328 linked devices; brief said 339, data has 328), 30 s auto-reset re-enables, breakable 20 toggles off; " + str(w3_power_lines),
			"70.5 power failed: %s break=%s" % [w3_power_lines, w3_break_ok])

		# 70.6 turret: 12 m / +/-15 deg, 0.5 s Normal interval, 40 m/s
		# 10-damage 30 s projectile, 150 health; linked plate turns on the
		# _180_Triggered variant.
		var w3_turret_rec: Dictionary = w3_rec_by_id.get("guildhall/Guildhall_Gameplay:BP_SecurityTurret_180_C_1", {}) as Dictionary
		var w3_turret: Node3D = w3_turret_scr.new() as Node3D
		root.add_child(w3_turret)
		w3_turret.call("configure", w3_turret_rec, w3_defaults, 2)
		w3_turret.global_position = Vector3.ZERO
		var w3_t_player: W3MockPlayer = W3MockPlayer.new()
		w3_t_player.add_to_group("player")
		root.add_child(w3_t_player)
		w3_turret.call("set_player", w3_t_player)
		var w3_far_ok: bool = not bool(w3_turret.call("can_see", _w3_at(w3_t_player, Vector3(12.1, 0.0, 0.0))))
		var w3_near_ok: bool = bool(w3_turret.call("can_see", _w3_at(w3_t_player, Vector3(11.9, 0.0, 0.0))))
		var w3_in_fov: bool = bool(w3_turret.call("can_see", _w3_at(w3_t_player, Vector3(11.0, 0.0, 2.8))))
		var w3_out_fov: bool = not bool(w3_turret.call("can_see", _w3_at(w3_t_player, Vector3(11.0, 0.0, 3.0))))
		_w3_at(w3_t_player, Vector3(11.0, 0.0, 0.0))
		w3_turret.call("tick", 0.01)
		var w3_shots1: int = int(w3_turret.get("shots_fired"))
		var w3_proj: Node = w3_turret.get("last_projectile") as Node
		var w3_proj_ok: bool = w3_proj != null and is_equal_approx(float(w3_proj.get("speed_m_s")), 40.0) and is_equal_approx(float(w3_proj.get("damage_amount")), 10.0) and is_equal_approx(float(w3_proj.get("life_seconds")), 30.0)
		if w3_proj != null:
			w3_t_player.health = 300.0
			w3_proj.call("_impact", w3_t_player)
			w3_proj_ok = w3_proj_ok and is_equal_approx(w3_t_player.health, 290.0)
		w3_turret.call("tick", 0.4)
		var w3_shots2: int = int(w3_turret.get("shots_fired"))
		w3_turret.call("tick", 0.11)
		var w3_shots3: int = int(w3_turret.get("shots_fired"))
		var w3_interval_ok: bool = is_equal_approx(float(w3_turret.get("fire_interval_s")), 0.5) and w3_shots1 == 1 and w3_shots2 == 1 and w3_shots3 == 2
		w3_turret.call("take_damage", 150.0)
		w3_turret.call("tick", 0.1)
		var w3_dead_ok: bool = not bool(w3_turret.get("alive")) and int(w3_turret.get("shots_fired")) == w3_shots3
		var w3_trig_rec: Dictionary = w3_rec_by_id.get("guildhall/Guildhall_Gameplay:BP_SecurityTurret_C_50", {}) as Dictionary
		var w3_trig: Node3D = w3_turret_scr.new() as Node3D
		root.add_child(w3_trig)
		w3_trig.call("configure", w3_trig_rec, w3_defaults, 2)
		var w3_trig_off: bool = not bool(w3_trig.get("starts_on")) and not bool(w3_trig.get("is_on"))
		var w3_act_plate: Area3D = w3_plate_scr.new() as Area3D
		root.add_child(w3_act_plate)
		w3_act_plate.call("configure", w3_plate_rec, w3_defaults, 2)
		w3_act_plate.global_position = Vector3(100.0, 0.0, 0.0)
		var w3_act_player: W3MockPlayer = W3MockPlayer.new()
		root.add_child(w3_act_player)
		w3_act_player.global_position = Vector3(100.0, 0.0, 0.0)
		w3_act_plate.call("set_player", w3_act_player)
		w3_act_plate.call("set_action_targets", [w3_trig])
		w3_act_plate.call("tick", 1.6)
		var w3_trig_on: bool = bool(w3_trig.get("is_on"))
		var w3_sw90_rec: Dictionary = w3_rec_by_id.get("guildhall/Guildhall_Gameplay:BP_SecurityTurret_90_C_1", {}) as Dictionary
		var w3_sw90: Node3D = w3_turret_scr.new() as Node3D
		w3_sw90.call("configure", w3_sw90_rec, w3_defaults, 2)
		var w3_sw360_rec: Dictionary = w3_rec_by_id.get("old_manor/OldManor_Gameplay:BP_SecurityTurret_180_C_101", {}) as Dictionary
		var w3_sw360: Node3D = w3_turret_scr.new() as Node3D
		w3_sw360.call("configure", w3_sw360_rec, w3_defaults, 2)
		var w3_swivel_ok: bool = is_equal_approx(float(w3_sw90.get("swivel_angle_deg")), 45.0) and is_equal_approx(float(w3_sw90.get("swivel_seconds")), 1.0) and is_equal_approx(float(w3_sw360.get("swivel_seconds")), 10.0) and str(w3_sw360.get("swivel_type")).find("ThreeSixty") >= 0
		w3_sw90.free()
		w3_sw360.free()
		fails += _w3_check(w3_far_ok and w3_near_ok and w3_in_fov and w3_out_fov and w3_interval_ok and w3_proj_ok and w3_dead_ok and w3_trig_off and w3_trig_on and w3_swivel_ok,
			"70.6 turret: 12 m/15 deg (11.9 yes, 12.1 no; 2.8 m in, 3.0 m out), 0.5 s interval, 40 m/s 10 dmg 30 s projectile, 150 hp stops firing; _180_Triggered off -> linked plate on",
			"70.6 turret failed: far=%s near=%s fov=%s/%s interval=%s proj=%s dead=%s trig=%s/%s" % [w3_far_ok, w3_near_ok, w3_in_fov, w3_out_fov, w3_interval_ok, w3_proj_ok, w3_dead_ok, w3_trig_off, w3_trig_on])
		w3_turret.queue_free()
		w3_t_player.queue_free()
		w3_trig.queue_free()
		w3_act_plate.queue_free()
		w3_act_player.queue_free()
		if w3_proj != null and is_instance_valid(w3_proj):
			w3_proj.queue_free()
		await process_frame

		# 70.7 camera: 2.0 s alarm (FTUE 0.25 s), 25 m guard_alert noise;
		# a guard at 20 m reacts, one at 26 m does not.
		var w3_eye_rec: Dictionary = w3_rec_by_id.get("guildhall/Guildhall_Gameplay:BP_MagicAlarm_LongRange_Narrow_C_0", {}) as Dictionary
		var w3_eye: Node3D = w3_eye_scr.new() as Node3D
		root.add_child(w3_eye)
		w3_eye.call("configure", w3_eye_rec, w3_defaults, 1)
		w3_eye.global_position = Vector3(0.0, 0.0, 500.0)
		w3_eye.set("swivel_seconds", 0.0) # isolate the authored alarm delay from the authored sweep
		var w3_c_player: W3MockPlayer = W3MockPlayer.new()
		root.add_child(w3_c_player)
		w3_c_player.global_position = Vector3(5.0, 0.0, 500.0)
		w3_eye.call("set_player", w3_c_player)
		var w3_noises: Array = []
		var w3_noise_cb := func(_o: Vector3, loud: float, _s: Node, tag: String) -> void:
			if tag == "guard_alert":
				w3_noises.append(loud)
		if nb != null:
			nb.connect("noise_emitted", w3_noise_cb)
		w3_eye.call("tick", 1.9)
		var w3_eye_before: int = int(w3_eye.get("alarms"))
		w3_eye.call("tick", 0.11)
		var w3_eye_after: int = int(w3_eye.get("alarms"))
		if nb != null and nb.is_connected("noise_emitted", w3_noise_cb):
			nb.disconnect("noise_emitted", w3_noise_cb)
		var w3_eye_ok: bool = w3_eye_before == 0 and w3_eye_after == 1 and is_equal_approx(float(w3_eye.get("alarm_delay_s")), 2.0) and w3_noises.size() == 1 and is_equal_approx(float(w3_noises[0]), 25.0)
		var w3_eye_n: Node3D = w3_eye_scr.new() as Node3D
		w3_eye_n.call("configure", w3_eye_rec, w3_defaults, 2)
		var w3_eye_h: Node3D = w3_eye_scr.new() as Node3D
		w3_eye_h.call("configure", w3_eye_rec, w3_defaults, 3)
		var w3_eye_diff_ok: bool = is_equal_approx(float(w3_eye_n.get("alarm_delay_s")), 1.0) and is_equal_approx(float(w3_eye_h.get("alarm_delay_s")), 0.2)
		w3_eye_n.free()
		w3_eye_h.free()
		w3_eye_ok = w3_eye_ok and w3_eye_diff_ok
		var w3_ftue_rec: Dictionary = {}
		for w3_fr: Variant in (((w3_maps.get("ftue", {}) as Dictionary).get("devices", [])) as Array):
			if w3_fr is Dictionary and str((w3_fr as Dictionary).get("family", "")) == "alarm_eye":
				w3_ftue_rec = w3_fr
				break
		var w3_ftue: Node3D = w3_eye_scr.new() as Node3D
		root.add_child(w3_ftue)
		w3_ftue.call("configure", w3_ftue_rec, w3_defaults, 1)
		w3_ftue.global_position = Vector3(0.0, 0.0, 1000.0)
		w3_ftue.set("swivel_seconds", 0.0)
		var w3_f_player: W3MockPlayer = W3MockPlayer.new()
		root.add_child(w3_f_player)
		w3_f_player.global_position = Vector3(5.0, 0.0, 1000.0)
		w3_ftue.call("set_player", w3_f_player)
		w3_ftue.call("tick", 0.2)
		var w3_ftue_before: int = int(w3_ftue.get("alarms"))
		w3_ftue.call("tick", 0.06)
		var w3_ftue_ok: bool = w3_ftue_before == 0 and int(w3_ftue.get("alarms")) == 1 and is_equal_approx(float(w3_ftue.get("alarm_delay_s")), 0.25)
		# Guards on the existing NoiseBus hearing path.
		var w3_guard_scr: GDScript = load("res://src/ai/guard_ai.gd") as GDScript
		var w3_g20: CharacterBody3D = w3_guard_scr.new() as CharacterBody3D
		root.add_child(w3_g20)
		w3_g20.global_position = Vector3(20.0, 0.0, 500.0)
		await process_frame
		var w3_guard_mask: int = int(w3_g20.collision_mask)
		w3_eye.call("reset_alarm")
		w3_eye.call("tick", 2.1)
		var w3_g20_state: int = int(w3_g20.get("state"))
		w3_g20.queue_free()
		await process_frame
		var w3_g26: CharacterBody3D = w3_guard_scr.new() as CharacterBody3D
		root.add_child(w3_g26)
		w3_g26.global_position = Vector3(26.0, 0.0, 500.0)
		await process_frame
		w3_eye.call("reset_alarm")
		w3_eye.call("tick", 2.1)
		var w3_g26_state: int = int(w3_g26.get("state"))
		w3_g26.queue_free()
		await process_frame
		var w3_camera_ok: bool = w3_eye_ok and w3_ftue_ok and w3_g20_state == 2 and w3_g26_state == 0
		fails += _w3_check(w3_camera_ok,
			"70.7 camera: 2.0 s alarm (FTUE 0.25 s), 25 m guard_alert; guard 20 m -> ALERTED, guard 26 m -> NEUTRAL; guard mask has no ward bit (%d)" % w3_guard_mask,
			"70.7 camera failed: eye=%s ftue=%s g20=%d g26=%d" % [w3_eye_ok, w3_ftue_ok, w3_g20_state, w3_g26_state])
		w3_eye.queue_free()
		w3_c_player.queue_free()
		w3_ftue.queue_free()
		w3_f_player.queue_free()
		await process_frame

		# 70.8 wards: blocker on bit 4 blocks the player but not a guard;
		# slow applies 0.25x/6 s and 50 magic once with 1 s immunity.
		var w3_block_rec: Dictionary = w3_rec_by_id.get("guildhall/Guildhall_Gameplay:BP_WardZone_Blocker_C_47", {}) as Dictionary
		var w3_slow_rec: Dictionary = w3_rec_by_id.get("guildhall/Guildhall_Gameplay:BP_WardZone_Slow_C_12", {}) as Dictionary
		var w3_block: Node3D = w3_ward_scr.new() as Node3D
		var w3_slow: Node3D = w3_ward_scr.new() as Node3D
		root.add_child(w3_block)
		root.add_child(w3_slow)
		w3_block.call("configure", w3_block_rec, w3_defaults, 2)
		w3_slow.call("configure", w3_slow_rec, w3_defaults, 2)
		w3_block.global_position = Vector3(200.0, 0.0, 0.0)
		w3_slow.global_position = Vector3(300.0, 0.0, 0.0)
		var w3_ward_init_ok: bool = not bool(w3_block.get("active")) and not bool(w3_slow.get("active"))
		var w3_act_plate2: Area3D = w3_plate_scr.new() as Area3D
		root.add_child(w3_act_plate2)
		w3_act_plate2.call("configure", w3_plate_rec, w3_defaults, 2)
		w3_act_plate2.global_position = Vector3(400.0, 0.0, 0.0)
		var w3_w_player: W3MockPlayer = W3MockPlayer.new()
		root.add_child(w3_w_player)
		w3_w_player.global_position = Vector3(400.0, 0.0, 0.0)
		w3_act_plate2.call("set_player", w3_w_player)
		w3_act_plate2.call("set_action_targets", [w3_block, w3_slow])
		w3_act_plate2.call("tick", 1.6)
		var w3_ward_active_ok: bool = bool(w3_block.get("active")) and bool(w3_slow.get("active"))
		var w3_block_body: StaticBody3D = w3_block.get("blocker_body") as StaticBody3D
		var w3_block_shape: CollisionShape3D = w3_block_body.get_node_or_null("WardBox") as CollisionShape3D
		var w3_block_geo_ok: bool = w3_block_body != null and w3_block_shape != null and w3_block_body.collision_layer == 16 and (w3_block_shape.shape as BoxShape3D).size.is_equal_approx(Vector3(0.3, 4.5, 3.0)) and (w3_block_shape as CollisionShape3D).position.is_equal_approx(Vector3(0.0, 2.25, 0.0))
		await physics_frame
		await physics_frame
		var w3_pmover: CharacterBody3D = CharacterBody3D.new()
		w3_pmover.collision_layer = 2
		w3_pmover.collision_mask = 1 | 4 | 16
		var w3_pcap := CollisionShape3D.new()
		var w3_pcap_shape := CapsuleShape3D.new()
		w3_pcap_shape.radius = 0.3
		w3_pcap_shape.height = 1.78
		w3_pcap.shape = w3_pcap_shape
		w3_pcap.position = Vector3(0.0, 0.89, 0.0)
		w3_pmover.add_child(w3_pcap)
		root.add_child(w3_pmover)
		w3_pmover.global_position = Vector3(200.0, 0.2, 1.8)
		await physics_frame
		var w3_p_hit: KinematicCollision3D = w3_pmover.move_and_collide(Vector3(0.0, 0.0, -3.6), true)
		w3_pmover.queue_free()
		await process_frame
		var w3_gmover: CharacterBody3D = CharacterBody3D.new()
		w3_gmover.collision_layer = 4
		w3_gmover.collision_mask = 1 | 2
		var w3_gcap := CollisionShape3D.new()
		var w3_gcap_shape := CapsuleShape3D.new()
		w3_gcap_shape.radius = 0.3
		w3_gcap_shape.height = 1.78
		w3_gcap.shape = w3_gcap_shape
		w3_gcap.position = Vector3(0.0, 0.89, 0.0)
		w3_gmover.add_child(w3_gcap)
		root.add_child(w3_gmover)
		w3_gmover.global_position = Vector3(200.0, 0.2, 1.8)
		await physics_frame
		var w3_g_hit: KinematicCollision3D = w3_gmover.move_and_collide(Vector3(0.0, 0.0, -3.6), true)
		w3_gmover.queue_free()
		await process_frame
		var w3_block_ok: bool = w3_ward_init_ok and w3_ward_active_ok and w3_block_geo_ok and w3_p_hit != null and w3_g_hit == null
		# Slow ward: enter once, damage 50, multiplier 0.25/6 s, immunity.
		w3_w_player.global_position = Vector3(300.0, 0.0, 0.0)
		w3_w_player.health = 300.0
		w3_slow.call("set_player", w3_w_player)
		w3_slow.call("tick", 0.1)
		var w3_slow_applied1: int = int(w3_slow.get("applied_count"))
		var w3_slow_damage: int = int(w3_slow.get("damage_applied"))
		var w3_slow_hp: float = w3_w_player.health
		w3_slow.call("tick", 0.5)
		var w3_slow_applied2: int = int(w3_slow.get("applied_count"))
		var w3_slow_calls_ok: bool = w3_w_player.slow_calls.size() == 1 and is_equal_approx(float(w3_w_player.slow_calls[0][0]), 0.25) and is_equal_approx(float(w3_w_player.slow_calls[0][1]), 6.0)
		var w3_thief_scr: GDScript = load("res://src/player/thief_character.gd") as GDScript
		var w3_thief: CharacterBody3D = w3_thief_scr.new() as CharacterBody3D
		var w3_thief_base: float = float(w3_thief.call("effective_speed", 3.6))
		w3_thief.call("apply_ward_slow", 0.25, 6.0)
		var w3_thief_slow: float = float(w3_thief.call("effective_speed", 3.6))
		w3_thief.call("_tick_ward_slow", 6.1)
		var w3_thief_back: float = float(w3_thief.call("effective_speed", 3.6))
		w3_thief.free()
		var w3_slow_ok: bool = w3_slow_applied1 == 1 and w3_slow_damage == 1 and is_equal_approx(w3_slow_hp, 250.0) and w3_slow_applied2 == 1 and w3_slow_calls_ok and is_equal_approx(w3_thief_base, 3.6) and is_equal_approx(w3_thief_slow, 0.9) and is_equal_approx(w3_thief_back, 3.6) and int((w3_thief_scr.get_script_constant_map() as Dictionary).get("WARD_BLOCKER_LAYER", -1)) == 16 and (w3_guard_mask & 16) == 0
		fails += _w3_check(w3_block_ok and w3_slow_ok,
			"70.8 wards: initially inactive; linked plate activates; blocker layer bit4/16 size (0.3,4.5,3.0) centre y=2.25 blocks player mask, guard passes; slow 0.25x for 6 s + 50 magic once (hp 300->250), 1 s immunity; thief hook 3.6->0.9->3.6",
			"70.8 wards failed: init=%s active=%s geo=%s block=%s/%s slow=%d/%d hp=%.1f calls=%s thief=%.2f/%.2f/%.2f" % [w3_ward_init_ok, w3_ward_active_ok, w3_block_geo_ok, w3_p_hit != null, w3_g_hit == null, w3_slow_applied1, w3_slow_damage, w3_slow_hp, w3_w_player.slow_calls, w3_thief_base, w3_thief_slow, w3_thief_back])
		w3_block.queue_free()
		w3_slow.queue_free()
		w3_act_plate2.queue_free()
		w3_w_player.queue_free()
		await process_frame

		# Deferred families stay authored markers, never deleted or faked.
		var w3_deferred: Array = w3_layer.call("deferred_families") as Array
		var w3_deferred_ok: bool = w3_deferred.has("goo_pipe") and w3_deferred.has("vault_door") and w3_deferred.has("junction")
		fails += _w3_check(w3_deferred_ok,
			"70.9 deferred families remain authored data-only markers: " + str(w3_deferred),
			"70.9 deferred family marker list unexpected: " + str(w3_deferred))
		w3_layer.queue_free()
		await process_frame

	# 80. W6b: co-op transport. No live ENet peer: host/client routing uses the
	# _peer_id_override test seam, the default OfflineMultiplayerPeer makes RPC
	# sends harmless, and the world-event gate is exercised directly.
	var w6_nm: Node = root.get_node_or_null("NetManager")
	if w6_nm == null:
		printerr("FAIL: 80 NetManager autoload missing")
		fails += 1
	else:
		var w6_prev_coop: bool = bool(w6_nm.get("is_coop"))
		var w6_prev_peer: MultiplayerPeer = w6_nm.multiplayer.multiplayer_peer
		var w6_prev_broadcast_msec: int = int(w6_nm.get("_last_broadcast_msec"))
		var w6_known: Dictionary = w6_nm.get("_last_known_pos") as Dictionary
		var w6_last_event: Dictionary = w6_nm.get("_last_world_event_msec") as Dictionary
		w6_known.clear()
		w6_last_event.clear()
		var w6_root: Node = w6_nm.call("_get_mission_root") as Node

		# 80.0 host/client identity is explicit; solo is neither.
		w6_nm.set("is_coop", false)
		w6_nm.call("set_test_peer_id", 0)
		var w6_offline_ok: bool = not bool(w6_nm.call("is_host")) and not bool(w6_nm.call("is_client"))
		w6_nm.set("is_coop", true)
		w6_nm.call("set_test_peer_id", 1)
		var w6_host_ok: bool = bool(w6_nm.call("is_host")) and not bool(w6_nm.call("is_client"))
		w6_nm.call("set_test_peer_id", 2)
		var w6_client_ok: bool = not bool(w6_nm.call("is_host")) and bool(w6_nm.call("is_client"))
		w6_nm.call("set_test_peer_id", 1)
		fails += _w3_check(w6_offline_ok and w6_host_ok and w6_client_ok,
			"80.0 is_host/is_client: solo neither, host id 1, client id 2",
			"80.0 identity mismatch: offline=%s host=%s client=%s" % [w6_offline_ok, w6_host_ok, w6_client_ok])

		# Mock mission target for the host gate.
		var w6_target: Node3D = Node3D.new()
		w6_target.name = "W6bDoor"
		w6_target.position = Vector3(0.0, 0.0, 0.0)
		w6_root.add_child(w6_target)
		w6_target.global_position = Vector3.ZERO
		var w6_outside: Node3D = Node3D.new()
		w6_outside.name = "W6bOutside"
		root.add_child(w6_outside)
		w6_outside.global_position = Vector3.ZERO
		var w6_events: Array = []
		var w6_cb := func(kind: String, target: Node, from_peer: int) -> void:
			w6_events.append([kind, target, from_peer])
		w6_nm.connect("world_event_applied", w6_cb)

		# 80.1 host gate: unknown kind / overlong / non-alphanumeric / missing /
		# outside-scene / no known position / out-of-range all reject.
		w6_known[2] = Vector3(1.0, 0.0, 0.0)
		var w6_bad_kind: Node = w6_nm.call("_validate_world_event", "explode", "W6bDoor", 2) as Node
		var w6_bad_long: Node = w6_nm.call("_validate_world_event", "open", "A".repeat(65), 2) as Node
		var w6_bad_chars: Node = w6_nm.call("_validate_world_event", "open", "W6b Door!", 2) as Node
		var w6_bad_missing: Node = w6_nm.call("_validate_world_event", "open", "NoSuchDoor", 2) as Node
		var w6_bad_outside: Node = w6_nm.call("_validate_world_event", "open", "W6bOutside", 2) as Node
		w6_known.erase(2)
		var w6_bad_unknown_pos: Node = w6_nm.call("_validate_world_event", "open", "W6bDoor", 2) as Node
		w6_known[2] = Vector3(10.0, 0.0, 0.0)
		var w6_bad_far: Node = w6_nm.call("_validate_world_event", "open", "W6bDoor", 2) as Node
		w6_known[2] = Vector3(2.9, 0.0, 0.0)
		var w6_good: Node = w6_nm.call("_validate_world_event", "open", "W6bDoor", 2) as Node
		var w6_accept_ok: bool = bool(w6_nm.call("_host_accept_world_event", "open", "W6bDoor", 2))
		var w6_events_ok: bool = w6_events.size() == 1 and w6_events[0][0] == "open" and w6_events[0][1] == w6_target and int(w6_events[0][2]) == 2
		fails += _w3_check(w6_bad_kind == null and w6_bad_long == null and w6_bad_chars == null and w6_bad_missing == null and w6_bad_outside == null and w6_bad_unknown_pos == null and w6_bad_far == null and w6_good == w6_target and w6_accept_ok and w6_events_ok,
			"80.1 host gate rejects unknown kind/long/non-alnum/missing/outside/no-pos/10 m; accepts 2.9 m and emits world_event_applied(open, target, 2)",
			"80.1 gate mismatch: kind=%s long=%s chars=%s missing=%s outside=%s nopos=%s far=%s good=%s accept=%s events=%s" % [w6_bad_kind, w6_bad_long, w6_bad_chars, w6_bad_missing, w6_bad_outside, w6_bad_unknown_pos, w6_bad_far, w6_good, w6_accept_ok, w6_events])

		# 80.2 cooldown spam is rejected; elapsed cooldown and the compatibility
		# alias both route to the host path.
		var w6_spam_ok: bool = not bool(w6_nm.call("_host_accept_world_event", "close", "W6bDoor", 2))
		w6_last_event[2] = Time.get_ticks_msec() - 300
		var w6_after_cooldown_ok: bool = bool(w6_nm.call("_host_accept_world_event", "close", "W6bDoor", 2))
		w6_events.clear()
		var w6_player: Node = w6_nm.get_tree().get_first_node_in_group("player")
		if w6_player is Node3D:
			w6_target.global_position = (w6_player as Node3D).global_position
		else:
			w6_target.global_position = Vector3.ZERO
			w6_known[1] = Vector3.ZERO
		w6_last_event.erase(1)
		w6_nm.call("send_world_event", "open", "W6bDoor")
		var w6_alias_ok: bool = w6_events.size() == 1 and w6_events[0][0] == "open"
		fails += _w3_check(w6_spam_ok and w6_after_cooldown_ok and w6_alias_ok,
			"80.2 host cooldown: same-250 ms close rejected, elapsed close accepted, send_world_event alias applies locally on the host",
			"80.2 cooldown/alias mismatch: spam=%s after=%s alias=%s events=%s" % [w6_spam_ok, w6_after_cooldown_ok, w6_alias_ok, w6_events])

		# 80.3 player-state send is 20 Hz and rejects non-finite/far transforms;
		# the thief controller actually calls it.
		w6_nm.set("_last_broadcast_msec", -100000)
		var w6_count0: int = int(w6_nm.get("broadcast_send_count"))
		var w6_send1: bool = bool(w6_nm.call("broadcast_player_state", Vector3.ZERO, 0.0, false, "chameleon"))
		var w6_send2: bool = bool(w6_nm.call("broadcast_player_state", Vector3.ZERO, 0.0, false, "chameleon"))
		var w6_bad_send: bool = bool(w6_nm.call("broadcast_player_state", Vector3(INF, 0.0, 0.0), 0.0, false, "chameleon"))
		var w6_bad_yaw: bool = bool(w6_nm.call("broadcast_player_state", Vector3.ZERO, NAN, false, "chameleon"))
		var w6_far_send: bool = bool(w6_nm.call("broadcast_player_state", Vector3(6000.0, 0.0, 0.0), 0.0, false, "chameleon"))
		var w6_send_delta: int = int(w6_nm.get("broadcast_send_count")) - w6_count0
		# RE-N-18: prove the controller publishes instead of reading its source
		# text. A bare ThiefCharacter (never added to the tree, so `_ready` and
		# the GLB load never run) is driven through its own 20 Hz tick and the
		# transport's send counter is the observation.
		w6_nm.set("_last_broadcast_msec", -100000)
		var w6_tick0: int = int(w6_nm.get("broadcast_send_count"))
		var w6_thief: Node = (load("res://src/player/thief_character.gd") as GDScript).new() as Node
		w6_thief.call("_tick_coop_broadcast", 0.06)
		var w6_tick_sent: bool = int(w6_nm.get("broadcast_send_count")) == w6_tick0 + 1
		w6_thief.call("_tick_coop_broadcast", 0.01)
		var w6_tick_gated: bool = int(w6_nm.get("broadcast_send_count")) == w6_tick0 + 1
		w6_thief.free()
		w6_nm.set("is_coop", false)
		var w6_solo0: int = int(w6_nm.get("broadcast_send_count"))
		var w6_solo_thief: Node = (load("res://src/player/thief_character.gd") as GDScript).new() as Node
		w6_solo_thief.call("_tick_coop_broadcast", 0.06)
		var w6_solo_quiet: bool = int(w6_nm.get("broadcast_send_count")) == w6_solo0
		w6_solo_thief.free()
		w6_nm.set("is_coop", true)
		var w6_thief_call_ok: bool = w6_tick_sent and w6_tick_gated and w6_solo_quiet
		fails += _w3_check(w6_send1 and not w6_send2 and not w6_bad_send and not w6_bad_yaw and not w6_far_send and w6_send_delta == 1 and w6_thief_call_ok,
			"80.3 broadcast_player_state: 2 calls in one 50 ms window -> 1 send, INF/NAN/6000 m rejected, ThiefCharacter tick sends once then gates and stays silent solo",
			"80.3 player-state mismatch: send=%s/%s bad=%s/%s/%s delta=%d tick=%s" % [w6_send1, w6_send2, w6_bad_send, w6_bad_yaw, w6_far_send, w6_send_delta, w6_thief_call_ok])

		# 80.4 cosmetic remote visual create/free, door remote toggle, and the
		# mission listener wiring (source shape; no live mission instance).
		w6_nm.set("_last_broadcast_msec", w6_prev_broadcast_msec)
		var w6_visual: Node3D = w6_nm.call("_ensure_remote_visual", 42, "chameleon") as Node3D
		var w6_visual_ok: bool = w6_visual != null and w6_nm.call("get_remote_visual", 42) == w6_visual
		w6_nm.call("_on_peer_disconnected_despawn", 42)
		await process_frame
		var w6_visual_freed: bool = not is_instance_valid(w6_visual) and w6_nm.call("get_remote_visual", 42) == null
		var w6_door_scr: GDScript = load("res://src/interact/swinging_door.gd") as GDScript
		var w6_door: Node3D = w6_door_scr.new() as Node3D
		w6_door.name = "W6bSwingDoor"
		w6_door.call("configure", {
			"pos": [0.0, 0.0, 0.0],
			"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
			"leaves": [],
		}, null)
		w6_root.add_child(w6_door)
		await process_frame
		w6_door.call("apply_remote_toggle", true)
		var w6_door_open_ok: bool = bool(w6_door.get("is_open")) and bool(w6_door.get("_tweening"))
		w6_door.call("apply_remote_toggle", true)
		var w6_door_idem_ok: bool = bool(w6_door.get("is_open"))
		w6_door.call("apply_remote_toggle", false)
		var w6_door_close_ok: bool = not bool(w6_door.get("is_open"))
		# RE-N-18: wiring is proved through the real signal, not source text.
		# `_connect_coop_listener` is the exact method `_ready` calls; on a bare
		# mission instance it binds the transport signals without loading a map.
		var w6_mc: Node = (load("res://src/missions/mission_controller.gd") as GDScript).new() as Node
		w6_mc.call("_connect_coop_listener")
		var w6_listener_ok: bool = w6_nm.world_event_applied.is_connected(Callable(w6_mc, "_on_world_event_applied"))
		w6_nm.world_event_applied.emit("open", w6_door, 2)
		var w6_signal_open_ok: bool = bool(w6_door.get("is_open"))
		w6_nm.world_event_applied.emit("close", w6_door, 2)
		var w6_signal_close_ok: bool = not bool(w6_door.get("is_open"))
		w6_nm.world_event_applied.emit("open", w6_outside, 2)
		var w6_signal_guard_ok: bool = not bool(w6_door.get("is_open"))
		# The door announces its own state through the host gate: a validated
		# accept is the proof the send path exists (again, no source text).
		w6_nm.set("_last_world_event_msec", {})
		w6_known[1] = w6_door.global_position
		var w6_accept0: int = int(w6_nm.get("world_event_accept_count"))
		w6_door.set("is_open", true)
		w6_door.call("_announce_world_state")
		var w6_door_send_ok: bool = int(w6_nm.get("world_event_accept_count")) == w6_accept0 + 1
		if w6_listener_ok:
			w6_nm.world_event_applied.disconnect(Callable(w6_mc, "_on_world_event_applied"))
		w6_mc.free()
		var w6_wiring_ok: bool = w6_listener_ok and w6_signal_open_ok and w6_signal_close_ok and w6_signal_guard_ok and w6_door_send_ok
		fails += _w3_check(w6_visual_ok and w6_visual_freed and w6_door_open_ok and w6_door_idem_ok and w6_door_close_ok and w6_wiring_ok,
			"80.4 remote visual create/free without a peer; door apply_remote_toggle open/idempotent/close; the mission's coop listener opens/closes a real door from the transport signal and the door announces through the host gate",
			"80.4 visual/door mismatch: visual=%s freed=%s open=%s idem=%s close=%s wiring=%s" % [w6_visual_ok, w6_visual_freed, w6_door_open_ok, w6_door_idem_ok, w6_door_close_ok, w6_wiring_ok])

		# Restore transport state for the rest of the run.
		if w6_nm.is_connected("world_event_applied", w6_cb):
			w6_nm.disconnect("world_event_applied", w6_cb)
		w6_door.queue_free()
		w6_target.queue_free()
		w6_outside.queue_free()
		await process_frame
		w6_known.clear()
		w6_last_event.clear()
		w6_nm.call("set_test_peer_id", 0)
		w6_nm.multiplayer.multiplayer_peer = w6_prev_peer
		w6_nm.set("is_coop", w6_prev_coop)

	# P2-6 fixture restore (see boot snapshot): leave no mutated autoload
	# state behind for the next run or embedding harness.
	gs.thief_id = fx_thief_id
	gs.difficulty = fx_difficulty
	gs.active_contract_order = fx_order
	gs.active_map_id = fx_map_id

	# 75. Authored animation metadata: UE AnimNotify events and montage
	# sections exported by tools/parse_anim_meta.py (stats measured 2026-11-24:
	# 995 clips / 782 sequences / 213 montages / 3594 notifies). The accessor
	# is data-only by design; animation_library.gd documents the per-owner
	# polling point that would emit a notify signal.
	var c75_ok := true
	var c75_path := "res://data/generated/anims_meta.json"
	var c75_meta: Dictionary = {}
	if not FileAccess.file_exists(c75_path):
		printerr("FAIL: 75 missing authored animation metadata: ", c75_path)
		c75_ok = false
	else:
		var c75_file := FileAccess.open(c75_path, FileAccess.READ)
		var c75_parsed = JSON.parse_string(c75_file.get_as_text()) if c75_file != null else null
		if c75_file != null:
			c75_file.close()
		if c75_parsed is Dictionary:
			c75_meta = c75_parsed as Dictionary
		else:
			printerr("FAIL: 75 animation metadata is not a JSON object")
			c75_ok = false
	var c75_clips: Dictionary = {}
	if c75_ok:
		if str(c75_meta.get("schema", "")) != "tat2.anims_meta/1":
			printerr("FAIL: 75 animation metadata schema: ", c75_meta.get("schema"))
			c75_ok = false
		var c75_clips_v = c75_meta.get("clips", null)
		if c75_clips_v is Dictionary:
			c75_clips = c75_clips_v as Dictionary
		else:
			printerr("FAIL: 75 animation metadata has no clips dictionary")
			c75_ok = false
	var c75_stats_v = c75_meta.get("stats", null)
	var c75_stats: Dictionary = c75_stats_v as Dictionary if c75_stats_v is Dictionary else {}
	if c75_ok and (c75_clips.size() != 995 \
			or GuardAnimationLibrary.manifest_clip_count() != 995 \
			or GuardAnimationLibrary.meta_clip_count() != c75_clips.size() \
			or int(c75_stats.get("sequences", 0)) != 782 \
			or int(c75_stats.get("montages", 0)) != 213 \
			or int(c75_stats.get("notifies", 0)) != 3594):
		printerr("FAIL: 75 metadata census: clips=", c75_clips.size(), " manifest=", GuardAnimationLibrary.manifest_clip_count(), " accessor=", GuardAnimationLibrary.meta_clip_count(), " stats=", c75_stats)
		c75_ok = false
	# 75a. Known authored montage notify classes, times and serialized payloads.
	var c75_known := [
		{"clip": "AN_Disguise_Equip_Montage", "class": "AnimNotify_AkPlayerEvent", "time": 0.012435, "key": "BlueprintEvent", "value": "Play_Ability_Disguise_Equip"},
		{"clip": "AN_Zipwire_Crank_Montage", "class": "AnimNotifyState_ToolAnimationEvent_C", "time": 0.0, "key": "FinishMontageSectionName", "value": "Finish"},
		{"clip": "AN_ThiefSign_Decal_Montage", "class": "AnimNotify_GameplayEvent_C", "time": 0.667208, "key": "EventTag", "value": "Animation.Event.Thiefsign.TriggerSymbol"},
		{"clip": "AN_BlackJack_Attack_Light__Slash_L_03_Montage", "class": "AnimNotify_CombatAnimationEnd", "time": 0.501738, "key": "", "value": ""},
	]
	var c75_known_found := 0
	for c75_spec_v: Variant in c75_known:
		var c75_spec: Dictionary = c75_spec_v as Dictionary
		var c75_clip_name := str(c75_spec.get("clip", ""))
		var c75_matched := false
		for c75_n_v: Variant in GuardAnimationLibrary.get_notifies(c75_clip_name):
			if not (c75_n_v is Dictionary):
				continue
			var c75_n: Dictionary = c75_n_v as Dictionary
			if str(c75_n.get("class", "")) != str(c75_spec.get("class", "")):
				continue
			if absf(float(c75_n.get("time", -1.0)) - float(c75_spec.get("time", 0.0))) > 0.0001:
				continue
			var c75_key := str(c75_spec.get("key", ""))
			if c75_key != "":
				var c75_payload: Dictionary = c75_n.get("payload", {}) as Dictionary
				if str(c75_payload.get(c75_key, "")) != str(c75_spec.get("value", "")):
					continue
			c75_matched = true
			break
		if c75_matched:
			c75_known_found += 1
		else:
			printerr("FAIL: 75 authored notify not found: ", c75_spec)
			c75_ok = false
	if c75_known_found < 3:
		printerr("FAIL: 75 known notify classes found=", c75_known_found)
		c75_ok = false
	# 75b. AN_Zipwire_Crank_Montage's authored sections (CrankStart/Loop/Finish).
	var c75_sec_names: Array[String] = []
	var c75_sec_starts: Array[float] = []
	var c75_sec_ends: Array[float] = []
	for c75_sec_v: Variant in GuardAnimationLibrary.get_sections("AN_Zipwire_Crank_Montage"):
		if c75_sec_v is Dictionary:
			var c75_sec: Dictionary = c75_sec_v as Dictionary
			c75_sec_names.append(str(c75_sec.get("name", "")))
			c75_sec_starts.append(float(c75_sec.get("start", -1.0)))
			c75_sec_ends.append(float(c75_sec.get("end", -1.0)))
	var c75_sec_expect: Array[String] = ["CrankStart", "CrankLoop", "CrankFinish"]
	if c75_sec_names != c75_sec_expect \
			or c75_sec_starts.size() != 3 or absf(c75_sec_starts[1] - 2.240913) > 0.0001 \
			or absf(c75_sec_starts[2] - 3.6) > 0.0001 \
			or absf(c75_sec_ends[0] - 2.240913) > 0.0001 \
			or absf(c75_sec_ends[2] - 4.666666) > 0.0001:
		printerr("FAIL: 75 crank montage sections: names=", c75_sec_names, " starts=", c75_sec_starts, " ends=", c75_sec_ends)
		c75_ok = false
	# 75c. notify_at nearest-match inside tolerance, null outside.
	var c75_near = GuardAnimationLibrary.notify_at("AN_BlackJack_Attack_Light__Slash_L_03_Montage", 0.0626, 0.002)
	if not (c75_near is Dictionary) or absf(float((c75_near as Dictionary).get("time", -1.0)) - 0.062471) > 0.0001:
		printerr("FAIL: 75 notify_at nearest: ", c75_near)
		c75_ok = false
	if GuardAnimationLibrary.notify_at("AN_Disguise_Equip_Montage", 0.5, 0.05) != null:
		printerr("FAIL: 75 notify_at should be null outside tolerance")
		c75_ok = false
	# 75d. Every authored notify time is inside its clip and durations >= 0.
	var c75_bad_notifies: Array[String] = []
	for c75_clip_key_v: Variant in c75_clips:
		var c75_clip_key := str(c75_clip_key_v)
		var c75_clip_v = c75_clips[c75_clip_key_v]
		if not (c75_clip_v is Dictionary):
			continue
		var c75_clip: Dictionary = c75_clip_v as Dictionary
		var c75_len := float(c75_clip.get("length", -1.0))
		for c75_d_v: Variant in c75_clip.get("notifies", []) as Array:
			if not (c75_d_v is Dictionary):
				continue
			var c75_dn: Dictionary = c75_d_v as Dictionary
			var c75_t := float(c75_dn.get("time", -1.0))
			if c75_t < -0.0001 or c75_t > c75_len + 0.0001 or c75_len <= 0.0 \
					or float(c75_dn.get("duration", 0.0)) < 0.0:
				c75_bad_notifies.append("%s %.6f/%.6f" % [c75_clip_key, c75_t, c75_len])
	if not c75_bad_notifies.is_empty():
		printerr("FAIL: 75 out-of-range notifies: ", c75_bad_notifies.slice(0, 5))
		c75_ok = false
	if not c75_ok:
		fails += 1
	else:
		print("PASS: 75 authored animation metadata (995 clips, 213 montages, 3594 notifies, 4 known notify classes, CrankStart/Loop/Finish sections, notify_at nearest/null)")

	# 85. W0b performance measurement truth: desktop graphics_quality schema +
	# CLI parser + mission_ready emission. The mission emission is observed on
	# the Contract 3 instance loaded in suite 4 (no extra 3D load).
	var c85_problems: Array[String] = []
	var c85_ss: Node = (load("res://src/core/save_system.gd") as GDScript).new()
	var c85_defaults: Dictionary = c85_ss.call("_defaults") as Dictionary
	var c85_default_settings: Dictionary = c85_defaults.get("settings", {}) as Dictionary
	if str(c85_default_settings.get("graphics_quality", "")) != "high":
		c85_problems.append("default graphics_quality=%s expected high" % str(c85_default_settings.get("graphics_quality", "")))
	if not c85_default_settings.has("render_scale"):
		c85_problems.append("default settings lost render_scale")
	for c85_key: String in ["low", "medium", "high"]:
		var c85_data: Dictionary = c85_defaults.duplicate(true)
		var c85_data_s: Dictionary = c85_data["settings"] as Dictionary
		c85_data_s["graphics_quality"] = c85_key
		c85_ss.set("data", c85_data)
		c85_ss.call("_ensure_defaults")
		var c85_live: Dictionary = c85_ss.get("data") as Dictionary
		var c85_live_s: Dictionary = c85_live.get("settings", {}) as Dictionary
		var c85_got: String = str(c85_live_s.get("graphics_quality", ""))
		if c85_got != c85_key:
			c85_problems.append("valid graphics_quality '%s' normalised to '%s'" % [c85_key, c85_got])
	var c85_bad_data: Dictionary = c85_defaults.duplicate(true)
	var c85_bad_data_s: Dictionary = c85_bad_data["settings"] as Dictionary
	c85_bad_data_s["graphics_quality"] = "ultra"
	c85_ss.set("data", c85_bad_data)
	c85_ss.call("_ensure_defaults")
	var c85_bad_live: Dictionary = c85_ss.get("data") as Dictionary
	var c85_bad_live_s: Dictionary = c85_bad_live.get("settings", {}) as Dictionary
	var c85_bad_norm: String = str(c85_bad_live_s.get("graphics_quality", ""))
	if c85_bad_norm != "high":
		c85_problems.append("invalid graphics_quality not normalised to high (got '%s')" % c85_bad_norm)
	var c85_wrong_type: Dictionary = c85_defaults.duplicate(true)
	var c85_wrong_s: Dictionary = c85_wrong_type["settings"] as Dictionary
	c85_wrong_s["graphics_quality"] = 2
	c85_ss.set("data", c85_wrong_type)
	c85_ss.call("_ensure_defaults")
	var c85_wrong_live: Dictionary = c85_ss.get("data") as Dictionary
	var c85_wrong_live_s: Dictionary = c85_wrong_live.get("settings", {}) as Dictionary
	if str(c85_wrong_live_s.get("graphics_quality", "")) != "high":
		c85_problems.append("non-string graphics_quality not normalised to high")
	c85_ss.free()

	var c85_pp: GDScript = load("res://src/core/perf_profile.gd") as GDScript
	var c85_cfg: Dictionary = c85_pp.parse_args(PackedStringArray([
		"--perf-quality=low", "--perf-scale=0.85", "--perf-scaling=fsr1",
		"--perf-lights=80", "--perf-shadows=3", "--perf-vsync=off",
	]))
	if not bool(c85_cfg.get("ok", false)):
		c85_problems.append("valid perf args rejected: %s" % str(c85_cfg.get("errors", [])))
	else:
		if str(c85_cfg.get("quality", "")) != "low" or int(c85_cfg.get("quality_index", -1)) != 0:
			c85_problems.append("perf quality parse mismatch: %s" % str(c85_cfg))
		if not is_equal_approx(float(c85_cfg.get("scale", -1.0)), 0.85):
			c85_problems.append("perf scale parse mismatch: %s" % str(c85_cfg.get("scale", null)))
		if str(c85_cfg.get("scaling", "")) != "fsr1":
			c85_problems.append("perf scaling parse mismatch: %s" % str(c85_cfg.get("scaling", null)))
		if int(c85_cfg.get("lights", -1)) != 80 or int(c85_cfg.get("shadows", -1)) != 3:
			c85_problems.append("perf light/shadow parse mismatch: %s" % str(c85_cfg))
		if int(c85_cfg.get("vsync", -1)) != 0:
			c85_problems.append("perf vsync=off did not parse to 0")
	var c85_bad_args: Array = [
		PackedStringArray(["--perf-quality=ultra"]),
		PackedStringArray(["--perf-scale=0.5"]),
		PackedStringArray(["--perf-scaling=dlss"]),
		PackedStringArray(["--perf-lights=-1"]),
		PackedStringArray(["--perf-shadows=abc"]),
		PackedStringArray(["--perf-vsync=maybe"]),
		PackedStringArray(["--perf-nope=1"]),
	]
	for c85_bad: PackedStringArray in c85_bad_args:
		var c85_bad_cfg: Dictionary = c85_pp.parse_args(c85_bad)
		if bool(c85_bad_cfg.get("ok", true)):
			c85_problems.append("invalid perf args accepted: " + str(c85_bad))
	var c85_no_args: Dictionary = c85_pp.parse_args(PackedStringArray())
	if not bool(c85_no_args.get("ok", false)) or bool(c85_no_args.get("requested", true)):
		c85_problems.append("empty perf args should be ok and not requested")
	var c85_matrix_only: Dictionary = c85_pp.parse_args(PackedStringArray(["--perf-matrix"]))
	if not bool(c85_matrix_only.get("ok", false)) or bool(c85_matrix_only.get("requested", true)):
		c85_problems.append("--perf-matrix selector should be ignored by the value parser")

	var c85_mc: GDScript = load("res://src/missions/mission_controller.gd") as GDScript
	var c85_signal_found: bool = false
	for c85_sig: Dictionary in c85_mc.get_script_signal_list():
		if str(c85_sig.get("name", "")) == "mission_ready":
			c85_signal_found = true
			break
	if not c85_signal_found:
		c85_problems.append("mission_controller has no mission_ready signal")
	if not bool(c4_ready.get("fired", false)):
		c85_problems.append("mission_ready never emitted for the suite-4 mission")
	elif str(c4_ready.get("map", "")) != "old_manor":
		c85_problems.append("mission_ready map=%s expected old_manor" % str(c4_ready.get("map", "")))
	elif not (c4_ready.get("stats", {}) is Dictionary) or (c4_ready.get("stats", {}) as Dictionary).is_empty():
		c85_problems.append("mission_ready stats missing/empty")
	var c85_ok: bool = c85_problems.is_empty()
	if not c85_ok:
		printerr("FAIL: 85 perf measurement contract: ", c85_problems)
		fails += 1
	else:
		print("PASS: 85 graphics_quality default/validation, --perf-* parser accept/reject, mission_ready emitted (old_manor)")

	# 83. Review-map baker: the tagger unit tests plus a real thieves_den bake
	# run in a child engine (test_review_baker.gd). The child exits 0 only when
	# every tag assertion, manifest key, consistency check and scene-load test
	# passed, so this suite forwards that verdict. ~6 s, headless, no GPU.
	var w83_out: Array = []
	var w83_args: PackedStringArray = [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/test_review_baker.gd",
	]
	var w83_t0: int = Time.get_ticks_msec()
	var w83_code: int = OS.execute(OS.get_executable_path(), w83_args, w83_out, true)
	var w83_ms: int = Time.get_ticks_msec() - w83_t0
	var w83_text: String = "\n".join(PackedStringArray(w83_out))
	if w83_code != 0 or w83_text.find("REVIEW_TEST SUMMARY: fails=0") < 0:
		printerr("FAIL: 83 review baker exit=", w83_code, " ms=", w83_ms, "\n", w83_text.right(2000))
		fails += 1
	else:
		print("PASS: 83 review baker (tagger + thieves_den bake, exit=0, ", w83_ms, " ms)")

	# 86. W0S: Spider personal chain data/save foundation. This suite owns the
	# persisted record, its normalization and the pure beat controller only —
	# the NPC/dialogue/mission runtime is a later wave, so there are no actor
	# assertions here.
	var c86_problems: Array[String] = []
	var c86_pq: GDScript = load("res://src/quests/personal_quest.gd") as GDScript
	if c86_pq == null:
		c86_problems.append("personal_quest.gd did not load")
	var c86_save_path := "user://tat2_save.json"
	var c86_had_file: bool = FileAccess.file_exists(c86_save_path)
	var c86_file_backup: String = FileAccess.get_file_as_string(c86_save_path) if c86_had_file else ""
	var c86_live_backup: Dictionary = (ss.get("data") as Dictionary).duplicate(true)
	var c86_gs_thief: String = str(gs.thief_id)
	var c86_gs_free: bool = bool(gs.free_play)
	var c86_gs_free_pending: bool = bool(gs.free_play_pending)
	var c86_gs_facts: Array = (gs.get("clue_facts") as Array).duplicate(true)
	var c86_gs_order: int = int(gs.active_contract_order)
	var c86_gs_map: String = str(gs.active_map_id)
	var c86_gs_mission: String = str(gs.active_mission_id)
	var c86_gs_state: String = str(gs.state)

	# 86a. Defaults: schema 1, migration flag false, one empty record per thief.
	var c86_defaults: Dictionary = ss.call("_defaults") as Dictionary
	var c86_default_record: Dictionary = c86_defaults.get("personal_quest", {}) as Dictionary
	var c86_default_spider: Dictionary = c86_default_record.get("spider", {}) as Dictionary
	if int(c86_defaults.get("personal_quest_schema", 0)) != 1:
		c86_problems.append("default personal_quest_schema != 1")
	if c86_defaults.get("personal_quest_migrated", true) != false:
		c86_problems.append("default personal_quest_migrated should be false")
	if str(c86_default_spider.get("stage", "x")) != "" \
			or str(c86_default_spider.get("owl", "x")) != "none" \
			or not (c86_default_spider.get("facts", null) is Array) \
			or not (c86_default_spider.get("facts", [null]) as Array).is_empty():
		c86_problems.append("default spider personal record is not empty: %s" % str(c86_default_spider))
	if not (c86_default_record.get("chameleon", null) is Dictionary):
		c86_problems.append("default chameleon personal record missing")

	# 86b. Migration is one-shot and stamps the schema.
	var c86_mig: Dictionary = (ss.call("_defaults") as Dictionary).duplicate(true)
	c86_mig["personal_quest_migrated"] = false
	ss.set("data", c86_mig)
	var c86_mig_first: bool = bool(ss.call("_migrate_personal_quest"))
	var c86_mig_second: bool = bool(ss.call("_migrate_personal_quest"))
	var c86_mig_live: Dictionary = ss.get("data") as Dictionary
	if not c86_mig_first or c86_mig_second:
		c86_problems.append("personal-quest migration is not one-shot: first=%s second=%s" % [c86_mig_first, c86_mig_second])
	if c86_mig_live.get("personal_quest_migrated", false) != true \
			or int(c86_mig_live.get("personal_quest_schema", 0)) != 1:
		c86_problems.append("migration did not persist flags: %s" % str(c86_mig_live.get("personal_quest")))

	# 86c. Normalization: unknown keys/thieves survive; bad domain values reset;
	# facts are ids-only, deduped and filtered to the seven authored rows; facts
	# raise the stage; stage/owl stay consistent.
	var c86_norm: Dictionary = (ss.call("_defaults") as Dictionary).duplicate(true)
	c86_norm["personal_quest"] = {
		"spider": {
			"stage": "bogus",
			"owl": "bogus",
			"facts": [
				"DT_ClueFacts_Personal_Spider_01:FoundLetter",
				"DT_ClueFacts_Personal_Spider_01:FoundLetter",
				"DT_ClueFacts_Contracts_02:Clue01",
				"DT_ClueFacts_Personal_Spider_03:Reminder",
				"DT_ClueFacts_Personal_Spider_04:Renegade",
				"DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Clue",
				"",
				42,
			],
			"custom_entry": {"keep": true},
		},
		"chameleon": {"stage": "intro", "owl": "none", "facts": [], "custom_thief": 7},
		"custom_thief": {"stage": "intro", "owl": "none", "facts": []},
	}
	ss.set("data", c86_norm)
	ss.call("_ensure_defaults")
	var c86_norm_live: Dictionary = ss.get("data") as Dictionary
	var c86_norm_root: Dictionary = c86_norm_live.get("personal_quest", {}) as Dictionary
	var c86_norm_spider: Dictionary = c86_norm_root.get("spider", {}) as Dictionary
	if str(c86_norm_spider.get("stage", "")) != "letter":
		c86_problems.append("normalization did not raise stage from facts: %s" % str(c86_norm_spider.get("stage")))
	if str(c86_norm_spider.get("owl", "")) != "none":
		c86_problems.append("normalization left owl %s at a pre-carry stage" % str(c86_norm_spider.get("owl")))
	if (c86_norm_spider.get("facts", []) as Array) != ["DT_ClueFacts_Personal_Spider_01:FoundLetter"]:
		c86_problems.append("normalization fact filter wrong: %s" % str(c86_norm_spider.get("facts")))
	if not ((c86_norm_spider.get("custom_entry", {}) as Dictionary).get("keep", false)):
		c86_problems.append("normalization dropped an unknown entry key")
	var c86_norm_cham: Dictionary = c86_norm_root.get("chameleon", {}) as Dictionary
	if int(c86_norm_cham.get("custom_thief", 0)) != 7:
		c86_problems.append("normalization dropped an unknown chameleon key")
	if not (c86_norm_root.get("custom_thief", null) is Dictionary):
		c86_problems.append("normalization dropped an unknown thief record")

	# The real load merge must keep unknown entry/thief keys: personal_quest is
	# replaced free-form, not walked with the default schema.
	ss.set("data", (ss.call("_defaults") as Dictionary).duplicate(true))
	ss.call("_merge_validated", {
		"personal_quest": {
			"spider": {"stage": "intro", "owl": "none", "facts": [], "custom_merge": 123},
			"custom_thief": {"stage": "intro"},
		},
	})
	ss.call("_ensure_defaults")
	var c86_merged_entry: Dictionary = ss.call("get_personal_quest", "spider") as Dictionary
	if int(c86_merged_entry.get("custom_merge", 0)) != 123:
		c86_problems.append("load merge dropped an unknown personal-quest entry key")
	var c86_merged_root: Dictionary = (ss.get("data") as Dictionary).get("personal_quest", {}) as Dictionary
	if not (c86_merged_root.get("custom_thief", null) is Dictionary):
		c86_problems.append("load merge dropped an unknown thief record")
	if str(c86_merged_entry.get("stage", "")) != "intro":
		c86_problems.append("load merge did not keep the known stage")

	# 86d. 04 clamps: info/complete need GotInfo; delivered needs HandedOff.
	var c86_clamp_cases: Array = [
		["info", ["DT_ClueFacts_Personal_Spider_03:HandedOff"], "delivered"],
		["complete", ["DT_ClueFacts_Personal_Spider_03:HandedOff"], "delivered"],
		["delivered", [], "carrying"],
		["info", ["DT_ClueFacts_Personal_Spider_03:HandedOff", "DT_ClueFacts_Personal_Spider_04:GotInfo"], "info"],
	]
	for c86_case_v: Variant in c86_clamp_cases:
		var c86_case: Array = c86_case_v as Array
		var c86_clamp: Dictionary = (ss.call("_defaults") as Dictionary).duplicate(true)
		c86_clamp["personal_quest"] = {
			"spider": {"stage": str(c86_case[0]), "owl": "delivered", "facts": (c86_case[1] as Array).duplicate()},
		}
		ss.set("data", c86_clamp)
		ss.call("_ensure_defaults")
		var c86_clamp_entry: Dictionary = ss.call("get_personal_quest", "spider") as Dictionary
		if str(c86_clamp_entry.get("stage", "")) != str(c86_case[2]):
			c86_problems.append("04 clamp %s/%s -> %s expected %s" % [str(c86_case[0]), str(c86_case[1]), str(c86_clamp_entry.get("stage")), str(c86_case[2])])
		var c86_clamp_owl: String = str(c86_clamp_entry.get("owl", ""))
		if str(c86_case[2]) == "carrying":
			if c86_clamp_owl != "held":
				c86_problems.append("04 clamp carrying owl=%s expected held" % c86_clamp_owl)
		elif c86_clamp_owl != "delivered":
			c86_problems.append("04 clamp %s owl=%s expected delivered" % [str(c86_case[2]), c86_clamp_owl])

	# 86e. Public save API: only authored chain facts persist.
	ss.set("data", (ss.call("_defaults") as Dictionary).duplicate(true))
	ss.call("_ensure_defaults")
	ss.call("reset_all_personal_quests")
	if bool(ss.call("set_personal_quest_stage", "spider", "bogus")):
		c86_problems.append("set_personal_quest_stage accepted an unknown stage")
	var c86_added: int = int(ss.call("add_personal_quest_facts", "spider", [
		"DT_ClueFacts_Personal_Spider_01:FoundLetter",
		"DT_ClueFacts_Personal_Spider_01:FoundLetter",
		"DT_ClueFacts_Contracts_02:Clue01",
		"DT_ClueFacts_Personal_Spider_03:Reminder",
		"DT_ClueFacts_Personal_Spider_04:Renegade",
	]))
	if c86_added != 1:
		c86_problems.append("add_personal_quest_facts stored %d ids, expected 1" % c86_added)
	var c86_api_entry: Dictionary = ss.call("get_personal_quest", "spider") as Dictionary
	if (c86_api_entry.get("facts", []) as Array) != ["DT_ClueFacts_Personal_Spider_01:FoundLetter"]:
		c86_problems.append("public fact API kept invalid ids: %s" % str(c86_api_entry.get("facts")))
	if str(c86_api_entry.get("stage", "")) != "letter":
		c86_problems.append("public fact API did not raise the stage: %s" % str(c86_api_entry.get("stage")))
	if not bool(ss.call("has_personal_quest_fact", "spider", "DT_ClueFacts_Personal_Spider_01:FoundLetter")):
		c86_problems.append("has_personal_quest_fact false for a stored fact")
	if bool(ss.call("has_personal_quest_fact", "spider", "DT_ClueFacts_Contracts_02:Clue01")):
		c86_problems.append("has_personal_quest_fact true for a contract fact")
	if not bool(ss.call("set_personal_quest_stage", "spider", "electrotype")):
		c86_problems.append("set_personal_quest_stage rejected a valid stage")
	if not bool(ss.call("set_personal_quest_owl", "spider", "held")):
		c86_problems.append("set_personal_quest_owl rejected held")
	if str((ss.call("get_personal_quest", "spider") as Dictionary).get("owl", "")) != "none":
		c86_problems.append("owl held persisted before the carrying stage (clamp expected)")
	if not bool(ss.call("set_personal_quest_stage", "spider", "carrying")):
		c86_problems.append("set_personal_quest_stage rejected carrying")
	if str((ss.call("get_personal_quest", "spider") as Dictionary).get("owl", "")) != "held":
		c86_problems.append("carrying stage did not clamp the owl to held")

	# 86f. Full chain transitions, per thief, and the free-play start.
	ss.set("data", (ss.call("_defaults") as Dictionary).duplicate(true))
	ss.call("_ensure_defaults")
	ss.call("reset_all_personal_quests")
	gs.thief_id = "spider"
	gs.clue_facts.clear()
	var c86_has_fact := func(fid: String) -> bool:
		for c86_fact_v: Variant in gs.get("clue_facts") as Array:
			if str((c86_fact_v as Dictionary).get("id", "")) == fid:
				return true
		return false
	if not bool(c86_pq.should_start("guildhall")) or bool(c86_pq.should_start("old_manor")):
		c86_problems.append("should_start must be true only on the first Guildhall deploy")
	if bool((c86_pq.record("letter") as Dictionary).get("ok", true)):
		c86_problems.append("record accepted an out-of-order stage")
	var c86_r_intro: Dictionary = c86_pq.record("intro") as Dictionary
	if not bool(c86_r_intro.get("ok", false)) or str(c86_r_intro.get("stage", "")) != "intro":
		c86_problems.append("record intro failed: %s" % str(c86_r_intro))
	var c86_intro_sets: Array = c86_pq.suppressed_clue_sets("intro") as Array
	if c86_intro_sets.has("CLS_Personal_Spider_01") or c86_intro_sets.size() != 3:
		c86_problems.append("intro must release CLS_01 and suppress the other three: %s" % str(c86_intro_sets))
	if not c86_has_fact.call("DT_ClueFacts_Personal_Spider_01:Intro"):
		c86_problems.append("intro did not journal the Intro fact")
	if bool((c86_pq.deliver_pending_messages() as Dictionary).get("ok", true)):
		c86_problems.append("pending messages delivered before the letter was read")
	var c86_r_letter: Dictionary = c86_pq.record("letter") as Dictionary
	if str(c86_r_letter.get("stage", "")) != "letter" \
			or not c86_has_fact.call("DT_ClueFacts_Personal_Spider_01:FoundLetter"):
		c86_problems.append("letter beat wrong: %s" % str(c86_r_letter))
	var c86_r_pending: Dictionary = c86_pq.deliver_pending_messages() as Dictionary
	if str(c86_r_pending.get("stage", "")) != "electrotype" \
			or not c86_has_fact.call("DT_ClueFacts_Personal_Spider_01:MallickSlip") \
			or not c86_has_fact.call("DT_ClueFacts_Personal_Spider_01:StatuePet"):
		c86_problems.append("pending electrotype messages wrong: %s" % str(c86_r_pending))
	if str(c86_pq.stage_for()) != "electrotype":
		c86_problems.append("stage_for did not follow the pending messages")
	if (c86_pq.spawn_plan("guildhall") as Array).is_empty():
		c86_problems.append("Owl pin missing at electrotype on the Guildhall")
	if bool((c86_pq.acquire_owl() as Dictionary).get("ok", true)):
		c86_problems.append("acquire_owl succeeded before the Owl was located")
	var c86_r_located: Dictionary = c86_pq.record("located") as Dictionary
	if str(c86_r_located.get("stage", "")) != "located" \
			or not c86_has_fact.call("DT_ClueFacts_Personal_Spider_02:OwlLocation"):
		c86_problems.append("located beat wrong: %s" % str(c86_r_located))
	var c86_r_owl: Dictionary = c86_pq.acquire_owl() as Dictionary
	if str(c86_r_owl.get("stage", "")) != "carrying" or str(c86_pq.owl_for()) != "held":
		c86_problems.append("acquire_owl wrong: %s / %s" % [str(c86_r_owl), str(c86_pq.owl_for())])
	var c86_courier: Array = c86_pq.spawn_plan("guildhall") as Array
	if c86_courier.size() != 1 or str((c86_courier[0] as Dictionary).get("id", "")) != "courier":
		c86_problems.append("courier pin missing while carrying: %s" % str(c86_courier))
	var c86_r_owl_done: Dictionary = c86_pq.deliver_owl() as Dictionary
	if str(c86_r_owl_done.get("stage", "")) != "delivered" \
			or str(c86_pq.owl_for()) != "delivered" \
			or not c86_has_fact.call("DT_ClueFacts_Personal_Spider_03:HandedOff"):
		c86_problems.append("deliver_owl wrong: %s / %s" % [str(c86_r_owl_done), str(c86_pq.owl_for())])
	var c86_informant: Array = c86_pq.spawn_plan("old_manor") as Array
	if c86_informant.size() != 1 or str((c86_informant[0] as Dictionary).get("id", "")) != "informant":
		c86_problems.append("informant pin missing at delivered: %s" % str(c86_informant))
	if not (c86_pq.spawn_plan("guildhall") as Array).is_empty():
		c86_problems.append("Guildhall pins must be empty at delivered")
	if bool((c86_pq.close_info() as Dictionary).get("ok", true)):
		c86_problems.append("close_info succeeded before the informant talk")
	var c86_r_info: Dictionary = c86_pq.deliver_info() as Dictionary
	if str(c86_r_info.get("stage", "")) != "info" \
			or not c86_has_fact.call("DT_ClueFacts_Personal_Spider_04:GotInfo"):
		c86_problems.append("deliver_info wrong: %s" % str(c86_r_info))
	var c86_r_close: Dictionary = c86_pq.close_info() as Dictionary
	if str(c86_r_close.get("stage", "")) != "complete" or str(c86_pq.owl_for()) != "delivered":
		c86_problems.append("close_info wrong: %s" % str(c86_r_close))
	if not bool((c86_pq.close_info() as Dictionary).get("ok", false)):
		c86_problems.append("close_info is not idempotent")
	var c86_final_facts: Array = c86_pq.facts_for() as Array
	if c86_final_facts.size() != 7:
		c86_problems.append("final chain stored %d facts, expected 7" % c86_final_facts.size())
	for c86_bad_fact: String in [
		"DT_ClueFacts_Personal_Spider_03:Reminder",
		"DT_ClueFacts_Personal_Spider_04:Renegade",
		"DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Clue",
		"DT_ClueFacts_Personal_Spider_01:ObjectiveComplete_Electrogram",
	]:
		if c86_final_facts.has(c86_bad_fact) or c86_has_fact.call(c86_bad_fact):
			c86_problems.append("suppressed fact persisted/granted: " + c86_bad_fact)
	if c86_pq.is_grantable("DT_ClueFacts_Personal_Spider_03:Reminder"):
		c86_problems.append("is_grantable accepted the dropped Reminder row")
	if not (c86_pq.suppressed_clue_sets("complete") as Array).is_empty():
		c86_problems.append("complete chain still suppresses clue sets")
	if (c86_pq.suppressed_clue_sets("") as Array).size() != 4:
		c86_problems.append("empty stage must suppress all four Spider clue sets")
	# Per-thief: the Chameleon record is independent of the finished Spider one.
	var c86_cham_record: Dictionary = c86_pq.entry_for("chameleon") as Dictionary
	if str(c86_cham_record.get("stage", "x")) != "" or not (c86_cham_record.get("facts", [null]) as Array).is_empty():
		c86_problems.append("Spider chain leaked into the Chameleon record: %s" % str(c86_cham_record))
	if str((c86_pq.record("intro", "chameleon") as Dictionary).get("stage", "")) != "intro":
		c86_problems.append("chameleon chain did not start independently")
	if str(c86_pq.stage_for("spider")) != "complete":
		c86_problems.append("chameleon start mutated the Spider record")

	# 86g. Free play starts the chain without banking contract progression.
	ss.call("reset_personal_quest", "spider")
	gs.clue_facts.clear()
	var c86_cc_before: Dictionary = ((ss.get("data") as Dictionary).get("completed_contracts", {}) as Dictionary).duplicate(true)
	var c86_currency_before: int = int((ss.get("data") as Dictionary).get("currency", 0))
	var c86_xp_before: int = int((ss.get("data") as Dictionary).get("xp", 0))
	gs.free_play = true
	gs.free_play_pending = true
	if not bool(c86_pq.should_start("guildhall", "spider")):
		c86_problems.append("free play did not qualify for the first Guildhall start")
	var c86_free_intro: Dictionary = c86_pq.record("intro") as Dictionary
	var c86_after: Dictionary = ss.get("data") as Dictionary
	if not bool(c86_free_intro.get("ok", false)):
		c86_problems.append("free-play intro failed: %s" % str(c86_free_intro))
	if str(c86_pq.stage_for("spider")) != "intro":
		c86_problems.append("free-play intro did not persist the stage")
	if (c86_after.get("completed_contracts", {}) as Dictionary) != c86_cc_before \
			or int(c86_after.get("currency", -1)) != c86_currency_before \
			or int(c86_after.get("xp", -1)) != c86_xp_before:
		c86_problems.append("free-play chain start banked contract progression")

	# 86h. Save restore: stage/owl/facts survive a real write + fresh load.
	c86_pq.record("letter", "spider")
	ss.call("write_save")
	var c86_fresh: Node = (load("res://src/core/save_system.gd") as GDScript).new()
	c86_fresh.set("data", c86_fresh.call("_defaults"))
	c86_fresh.call("load_save")
	var c86_restored: Dictionary = c86_fresh.call("get_personal_quest", "spider") as Dictionary
	if str(c86_restored.get("stage", "")) != "letter" \
			or str(c86_restored.get("owl", "")) != "none" \
			or (c86_restored.get("facts", []) as Array) != [
				"DT_ClueFacts_Personal_Spider_01:Intro",
				"DT_ClueFacts_Personal_Spider_01:FoundLetter",
			]:
		c86_problems.append("personal record did not round-trip: %s" % str(c86_restored))
	c86_fresh.free()

	# 86i. Contract facts never persist: a deploy wipes them and rehydrates the
	# personal ones only.
	gs.grant_fact("DT_ClueFacts_Contracts_02:Clue01", {}, "test")
	gs.reset_run(2, "guildhall")
	var c86_journal_ids: Array = []
	for c86_j_v: Variant in gs.get("clue_facts") as Array:
		c86_journal_ids.append(str((c86_j_v as Dictionary).get("id", "")))
	if c86_journal_ids.has("DT_ClueFacts_Contracts_02:Clue01"):
		c86_problems.append("contract fact survived a deploy")
	if not c86_journal_ids.has("DT_ClueFacts_Personal_Spider_01:Intro") \
			or not c86_journal_ids.has("DT_ClueFacts_Personal_Spider_01:FoundLetter"):
		c86_problems.append("personal facts did not survive a deploy: %s" % str(c86_journal_ids))
	if c86_journal_ids.size() != 2:
		c86_problems.append("deploy journal has %d facts, expected the 2 personal ones" % c86_journal_ids.size())

	# Restore the process state this suite borrowed (save data + user:// file,
	# GameState run fields) so later suites and the developer save are intact.
	ss.set("data", c86_live_backup)
	if c86_had_file:
		var c86_restore_file: FileAccess = FileAccess.open(c86_save_path, FileAccess.WRITE)
		if c86_restore_file != null:
			c86_restore_file.store_string(c86_file_backup)
			c86_restore_file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(c86_save_path))
	gs.thief_id = c86_gs_thief
	gs.free_play = c86_gs_free
	gs.free_play_pending = c86_gs_free_pending
	gs.clue_facts.clear()
	for c86_restore_fact_v: Variant in c86_gs_facts:
		if c86_restore_fact_v is Dictionary:
			gs.clue_facts.append(c86_restore_fact_v as Dictionary)
	gs.active_contract_order = c86_gs_order
	gs.active_map_id = c86_gs_map
	gs.active_mission_id = c86_gs_mission
	gs.state = c86_gs_state
	if not c86_problems.is_empty():
		printerr("FAIL: 86 Spider personal chain foundation: ", c86_problems)
		fails += 1
	else:
		print("PASS: 86 Spider personal chain (schema/migration/normalization, 8-beat chain, per-thief, free-play, save restore, contract-fact wipe)")

	# 87. W1S Spider runtime: in-process mock only. Suite 86 owns the record;
	# this suite drives the same PersonalQuest runtime API the NPCs, dialogue
	# and mission hook call, plus the real dialogue/loot classes in isolation.
	# The real-map walkthrough is tests/probe_personal_quest.gd and is run as
	# its own single engine process (never a child engine from here).
	#
	# `--spider-only` runs just suites 87 + 88 for a thermal-safe QA pass:
	#   tools/godot --headless --path game --script res://tests/run_tests.gd -- --spider-only
	var c87_problems: Array[String] = _run_suite87(root)
	if not c87_problems.is_empty():
		printerr("FAIL: 87 Spider personal chain runtime: ", c87_problems)
		fails += 1
	else:
		print("PASS: 87 Spider personal chain runtime (deploy/hub/plan, 03/04 lines and facts, Owl not loot, dialogue modal, save persistence)")

	# 88. W4O Spider settle path: the real spawn_anchor()/_settle_node() applied
	# to synthetic readable/quest-item/NPC records on one transformed host, plus
	# the authored yaw and the Chameleon zero-actor/no-record-mutation guard.
	# No map load: the real-map floor/pedestal gate is the subset probe.
	var c88_problems: Array[String] = await _run_suite88(root)
	if not c88_problems.is_empty():
		printerr("FAIL: 88 Spider personal chain settle path: ", c88_problems)
		fails += 1
	else:
		print("PASS: 88 Spider personal chain settle path (world-pin settle, mesh-bottom feet, authored yaw, guards, Chameleon no-op)")

	# 89. W7S-S2 carried loot inventory: 12 slots / major 3 / quest 1, authored
	# INVENTORY FULL refusal, one-use deposit-all stash, monotonic loot_value,
	# the 1.0 s pickup linger, and the payout model (Original/Kept/Stashed/
	# MoneyTaken, binary keep, £1,000 contract reward, stealth untouched, no
	# difficulty multiplier). Producer provenance is asserted against the live
	# extract when present and SKIPs loudly when extracted/ is absent.
	var c89_problems: Array[String] = await _run_suite89(root)
	if not c89_problems.is_empty():
		printerr("FAIL: 89 W7S-S2 loot inventory: ", c89_problems)
		fails += 1
	else:
		print("PASS: 89 W7S-S2 loot inventory (capacity, stash, linger, payout, provenance)")

	# 90. W7S-S2 loot save v8 + major-loot mesh: save_schema/loot_schema stamps,
	# strict payout normaliser (no unknown-key minting), idempotent bank_payout,
	# pending-payout crash recovery, one-shot migration, and exactly one major
	# loot mesh instance with the authored-off point light still off.
	var c90_problems: Array[String] = await _run_suite90(root)
	if not c90_problems.is_empty():
		printerr("FAIL: 90 W7S-S2 loot save v8: ", c90_problems)
		fails += 1
	else:
		print("PASS: 90 W7S-S2 loot save v8 (payout idempotency, migration, major mesh)")

	# 91. T02-STATE run lifecycle (RE-N-08/11/14/15/16): the reset contract, the
	# Thieves' Den without a mission clock, one banked payout per failure path,
	# and the host-authoritative co-op run outcome (client resolves on the
	# host's record, never on its own clock).
	var c91_problems: Array[String] = _run_suite91(root)
	if not c91_problems.is_empty():
		printerr("FAIL: 91 T02 run lifecycle: ", c91_problems)
		fails += 1
	else:
		print("PASS: 91 T02 run lifecycle (reset clears, hub clock, failure-path banking, co-op outcome)")

	# 92. T02-STATE save integrity (RE-N-03/06): a corrupt save is quarantined
	# whole and never replaced by a fresh profile, write_save reports its Error,
	# and the payout outbox settles once through the production API.
	var c92_problems: Array[String] = _run_suite92(root)
	if not c92_problems.is_empty():
		printerr("FAIL: 92 T02 save integrity: ", c92_problems)
		fails += 1
	else:
		print("PASS: 92 T02 save integrity (corrupt quarantine, write errors, outbox settle, loadout copy)")

	# 93. T02-STATE identity contracts. The authored cosmetic data path
	# (RE-N-10) and the co-op provenance label (RE-N-12) are consumed by other
	# lanes (T04-ANIM character bind, T05 UI copy), so their shape is pinned.
	var t02_prev_thief: String = str(gs.thief_id)
	var t02_prev_head: String = str(gs.get("outfit_head"))
	var t02_tags_ok: bool = true
	var t02_meshes_ok: bool = true
	var t02_body_spider: String = ""
	var t02_body_chameleon: String = ""
	var t02_head_chameleon: String = ""
	for t02_thief: String in ["spider", "chameleon"]:
		gs.set("thief_id", t02_thief)
		var t02_outfit: Dictionary = gs.call("active_outfit") as Dictionary
		var t02_prefix: String = "Outfit.%s." % t02_thief.capitalize()
		for t02_slot: String in ["head", "body", "calling_card"]:
			var t02_tag: String = str(t02_outfit.get(t02_slot, ""))
			if not t02_tag.begins_with(t02_prefix):
				printerr("FAIL: 93 active_outfit.%s='%s' is not an authored '%s*' tag" % [t02_slot, t02_tag, t02_prefix])
				t02_tags_ok = false
		var t02_body: String = str(gs.call("thief_base_mesh", "body"))
		var t02_head: String = str(gs.call("thief_base_mesh", "head"))
		if not FileAccess.file_exists(t02_body) or not FileAccess.file_exists(t02_head):
			printerr("FAIL: 93 base mesh missing for ", t02_thief, ": ", t02_body, " / ", t02_head)
			t02_meshes_ok = false
		if t02_thief == "spider":
			t02_body_spider = t02_body
		else:
			t02_body_chameleon = t02_body
			t02_head_chameleon = t02_head
	# The legacy short-name mirror must not feed the new accessor: the save is
	# the source of truth, so writing outfit_head changes nothing.
	gs.set("thief_id", "chameleon")
	gs.set("outfit_head", "bowler_hat")
	var t02_after_legacy: String = str((gs.call("active_outfit") as Dictionary).get("head", ""))
	gs.set("thief_id", t02_prev_thief)
	gs.set("outfit_head", t02_prev_head)
	var t02_legacy_ok: bool = t02_after_legacy.begins_with("Outfit.Chameleon.") and t02_after_legacy != "bowler_hat"
	var t02_per_thief_ok: bool = t02_body_spider.find("ThiefNisha") >= 0 \
		and t02_body_chameleon.find("ThiefCotter") >= 0 \
		and t02_head_chameleon.find("ThiefCotter") >= 0 \
		and t02_body_spider != t02_body_chameleon
	# Provenance: co-op is a shipped feature; only the transport is invented.
	var t02_prov: Dictionary = gs.call("coop_provenance") as Dictionary
	var t02_shipped: Dictionary = t02_prov.get("shipped", {}) as Dictionary
	var t02_xp_row: Dictionary = t02_shipped.get("xp_row", {}) as Dictionary
	var t02_xp_def: Dictionary = gd.call("get_xp_def", "XP.Cooperative") as Dictionary
	var t02_xp_display: String = str((t02_xp_def.get("DisplayName", {}) as Dictionary).get("SourceString", ""))
	var t02_prov_ok: bool = bool(t02_prov.get("expansion", true)) == false \
		and bool(t02_prov.get("transport_invented", false)) == true \
		and not bool(gs.call("coop_is_expansion")) \
		and str(t02_xp_row.get("row", "")) == "XP.Cooperative" \
		and t02_xp_display == "Co-op Bonus"
	# The recorded shipped assets are checked against the private dump when it
	# is present; a missing dump is a loud SKIP, never a silent pass.
	var t02_filelist_path: String = "res://../extracted/filelist.txt"
	if FileAccess.file_exists(t02_filelist_path):
		var t02_filelist: String = FileAccess.get_file_as_string(t02_filelist_path)
		var t02_missing: int = 0
		var t02_modes: Variant = t02_shipped.get("game_modes", [])
		if t02_modes is Array:
			for t02_mode_v: Variant in (t02_modes as Array):
				if not (t02_mode_v is Dictionary):
					continue
				var t02_file: String = str((t02_mode_v as Dictionary).get("file", ""))
				if t02_file != "" and not t02_filelist.contains(t02_file):
					t02_missing += 1
		if t02_missing > 0:
			printerr("FAIL: 93 provenance names ", t02_missing, " shipped asset(s) absent from extracted/filelist.txt")
			t02_prov_ok = false
	else:
		print("SKIP: 93 extracted/filelist.txt absent; shipped-asset names not re-verified")
	fails += _w3_check(t02_tags_ok and t02_legacy_ok and t02_meshes_ok and t02_per_thief_ok and t02_prov_ok,
		"93 T02 identity contracts: authored Outfit.<Thief>.* tags, per-thief Nisha/Cotter base meshes present, legacy mirror inert, co-op provenance expansion=false against the authored XP.Cooperative row",
		"93 identity mismatch: tags=%s legacy=%s meshes=%s per_thief=%s provenance=%s (xp='%s')" % [t02_tags_ok, t02_legacy_ok, t02_meshes_ok, t02_per_thief_ok, t02_prov_ok, t02_xp_display])
	# 94. T10 remediation: the objectives group producer (C4-14), the capacity
	# signal contract (C4-07), authored-only door/container locks (C4-04 /
	# RE-K-07/17), the dropped authored container classes (RE-K-06), the
	# large-carry movement penalty (RE-K-04), the authored steal time (RE-K-05)
	# and the authored 200 cm lockpick cancel distance (C4-06).
	var c94_raw: Variant = await _run_suite94(root)
	var c94_problems: Array[String] = []
	if c94_raw is Array:
		for problem_v: Variant in (c94_raw as Array):
			c94_problems.append(str(problem_v))
	else:
		c94_problems.append("suite 94 returned no problem list (script error; fail closed)")
	if not c94_problems.is_empty():
		printerr("FAIL: 94 T10 gameplay remediation: ", c94_problems)
		fails += 1
	else:
		print("PASS: 94 T10 gameplay (objective markers, capacity signal, authored locks, container classes, carry speed, steal time, cancel distance)")
	# 95. T09 geometry/placement contract: authored SplineMeshComponent loft,
	# the authored LevelStreaming graph + LevelInstance double-load guard, the
	# previously silent [0.05, 40] scale clamp / mirrored-basis accounting, the
	# world-origin door-marker refusal, and the authored mantle clip length the
	# movement curve must follow (RE-B-01/03/04, RE-P-05/08/09/10, RE-F-16).
	var c95_problems: Array[String] = await _run_suite95(root)
	if not c95_problems.is_empty():
		printerr("FAIL: 95 T09 geometry/placement contract: ", c95_problems)
		fails += 1
	else:
		print("PASS: 95 T09 geometry/placement contract (spline loft, streaming graph, LevelInstance dedupe, clamp/mirror accounting, origin doors, mantle duration)")
	# 96. T08 material/texture remediation: authored linear tints reach
	# albedo_color through the sRGB encode (and HDR carries pass through),
	# GLB slots bind by authored index instead of a name-substring override,
	# props instantiated outside the level build get their authored material,
	# and untextured debug geometry / flat colours are counted + named. The
	# producer-dependent half SKIPs loudly when materials.json predates the
	# T08 producer (integrator runs `make normalize`, then it is enforced).
	var t08_checks: GDScript = load("res://tests/t08_material_checks.gd") as GDScript
	var t08_ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(t08_ll)
	await process_frame
	t08_ll.call("_load_material_dbs")
	var t08_db_v: Variant = _repo_json("game/data/generated/materials.json")
	var t08_raw: Variant = t08_checks.call(
		"run", t08_ll, t08_db_v if t08_db_v is Dictionary else {})
	var t08_problems: Array[String] = []
	if t08_raw is Array:
		for t08_s: Variant in (t08_raw as Array):
			t08_problems.append(str(t08_s))
	t08_ll.queue_free()
	await process_frame
	if not t08_problems.is_empty():
		printerr("FAIL: 96 T08 materials: ", t08_problems)
		fails += 1
	else:
		print("PASS: 96 T08 materials (tint sRGB contract, authored slot index, prop GLB binding, flat-colour census)")
	# 97. W8 AI (T11-AI): the authored perception/roster/reaction/hearing model.
	# Behavioural, not constant mirrors: live physics for the blackjack hold,
	# authored rows compared against the raw extract, reaction caps across four
	# listening guards, a downed-guard witness, the rosters and the ranged curve.
	var c97_problems: Array[String] = await _run_suite97(root)
	if not c97_problems.is_empty():
		printerr("FAIL: 97 W8 AI authored perception: ", c97_problems)
		fails += 1
	else:
		print("PASS: 97 W8 AI (sight frustum vs authored rows, blackjack hold race, investigator cap, GuardDowned, roster buckets, ranged curve, hearing occlusion, nav degradation)")

	# 98. W9-P1-A4 night-grade guard (investigation outcome, NO code change made).
	# The Guildhall's single `gloomy` environment cannot grade both of its rooms.
	# Measured at 1920x1080 Vulkan through build/qa/w9_frame_stats.py (PNGs under
	# build/qa/w9/captures/): the interior foyer is ~2x too bright against KF27
	# (upper_foyer p50 34 vs 15; foyer_sweep_yaw180 p50 31 vs 15) while the gate
	# approach is already BELOW its KF16/KF18 reference (p50 10 vs 26) and loses
	# black floor for every step of exposure removed (gate %<8: 23.9 at 1.15 ->
	# 38.0 at 1.00 -> 51.9 at 0.85 -> 62.2 at 0.75). A global exposure/ambient
	# cut is therefore a regression, and the interior band was BLOCKED-ON P2:
	# the two shadowless foyer fills (mission_controller.gd, 1.6 at 3.3 m and
	# 1.3 at 14.1 m from the upper-foyer eye) dominated that pose -- freeing
	# them moves upper_foyer mean 28.8 -> 22.7 and %<8 8.0 -> 32.2 at one
	# exposure. W9-P2 removed the near fill and the band is still NOT met
	# (upper 29 / 1.1 %); a camera-scoped room grade failed its pre-registered
	# sweep and was reverted. This suite stays the guard against a global cut.
	var w9_problems: Array[String] = []
	var w9_wp: GDScript = load("res://src/core/weather_profile.gd") as GDScript
	if w9_wp == null:
		w9_problems.append("weather_profile.gd failed to load")
	else:
		var w9_floor: float = float(w9_wp.NIGHT_EXPOSURE)
		# The reference is a LITERAL, not the constant under test: comparing the
		# applied value against NIGHT_EXPOSURE alone is tautological and accepts a
		# global cut to 1.00 (W9-P1 audit A4, item 7). 1.15 is the measured night
		# anchor the gate view was calibrated at; at 1.00 its black floor goes
		# 23.9 -> 38.0 % < 8.
		const W9_NIGHT_FLOOR_REFERENCE: float = 1.15
		if w9_floor < W9_NIGHT_FLOOR_REFERENCE - 0.0001:
			w9_problems.append("NIGHT_EXPOSURE %.3f lowered below the measured reference %.2f (the gate loses its black floor)" % [w9_floor, W9_NIGHT_FLOOR_REFERENCE])
		# (a) Guildhall keeps the authored night floor and the authored ambient.
		var w9_gh: Dictionary = w9_wp.preset_for_map("guildhall")
		var e_gh := Environment.new()
		var m_gh := DirectionalLight3D.new()
		var ok_gh: bool = bool(w9_wp.apply_for_map(e_gh, m_gh, "guildhall"))
		if not ok_gh or e_gh.tonemap_mode != Environment.TONE_MAPPER_AGX:
			w9_problems.append("guildhall not graded AGX (applied=%s mode=%d)" % [str(ok_gh), e_gh.tonemap_mode])
		if not is_equal_approx(e_gh.tonemap_exposure, W9_NIGHT_FLOOR_REFERENCE):
			w9_problems.append("guildhall exposure=%.3f (must stay at the measured night floor %.2f; a global cut regresses the gate)" % [e_gh.tonemap_exposure, W9_NIGHT_FLOOR_REFERENCE])
		if not is_equal_approx(e_gh.ambient_light_energy, 0.16):
			w9_problems.append("guildhall ambient=%.4f (must stay the authored 0.16)" % e_gh.ambient_light_energy)
		# (b) The other night preset (lobby/prep stage) keeps the same floor.
		var w9_lob: Dictionary = w9_wp.preset_for_map("main_menu")
		var e_lob := Environment.new()
		var m_lob := DirectionalLight3D.new()
		w9_wp.apply_environment(e_lob, m_lob, w9_lob)
		if not is_equal_approx(e_lob.tonemap_exposure, W9_NIGHT_FLOOR_REFERENCE):
			w9_problems.append("lobby night preset exposure=%.3f (expected the measured floor %.2f)" % [e_lob.tonemap_exposure, W9_NIGHT_FLOOR_REFERENCE])
		# (c) The Den keeps its authored bias + floor (its own hand grade runs
		# later in mission_controller; this seam must not move).
		var w9_den: Dictionary = w9_wp.preset_for_map("thieves_den")
		var e_den := Environment.new()
		var m_den := DirectionalLight3D.new()
		w9_wp.apply_environment(e_den, m_den, w9_den)
		var w9_den_bias: float = float((w9_den.get("postprocess", {}) as Dictionary).get("auto_exposure_bias", 0.0))
		var w9_den_expected: float = maxf(1.0 + w9_den_bias, W9_NIGHT_FLOOR_REFERENCE)
		if not is_equal_approx(e_den.tonemap_exposure, w9_den_expected):
			w9_problems.append("Den exposure=%.3f (expected %.3f = authored bias + floor)" % [e_den.tonemap_exposure, w9_den_expected])
		# (d) Old Manor is not re-graded (not a night preset).
		if bool(w9_wp.is_night_preset(w9_wp.preset_for_map("old_manor"))):
			w9_problems.append("old_manor became a night preset")
		# (e) Scope guard: exactly one shipped map resolves to gloomy, so a future
		# interior calibration stays a single-map decision instead of silently
		# inheriting the Guildhall's treatment.
		var w9_map_file: FileAccess = FileAccess.open("res://data/generated/weather/map_weather.json", FileAccess.READ)
		if w9_map_file == null:
			w9_problems.append("map_weather.json missing")
		else:
			var w9_maps_v: Variant = JSON.parse_string(w9_map_file.get_as_text())
			var w9_maps: Dictionary = (w9_maps_v as Dictionary).get("maps", {}) if w9_maps_v is Dictionary else {}
			var w9_gloomy: Array[String] = []
			for w9_k: Variant in w9_maps.keys():
				if str((w9_maps[w9_k] as Dictionary).get("preset", "")) == "gloomy":
					w9_gloomy.append(str(w9_k))
			if w9_gloomy.size() != 1 or w9_gloomy[0] != "guildhall":
				w9_problems.append("gloomy is mapped from %s; the interior calibration is a one-map decision" % str(w9_gloomy))
		# Environment is a Resource (RefCounted): it is released by scope, never
		# free()d. Only the DirectionalLight3D nodes need an explicit free.
		for w9_m in [m_gh, m_lob, m_den]:
			(w9_m as DirectionalLight3D).free()
	if not w9_problems.is_empty():
		printerr("FAIL: 98 W9-P1-A4 night-grade guard: ", w9_problems)
		fails += 1
	else:
		print("PASS: 98 W9-P1-A4 night-grade guard (guildhall keeps AGX %.2f / ambient 0.16, lobby floor held, Den bias+floor held, old_manor ungraded, gloomy preset is one-map scoped)" % float(w9_wp.NIGHT_EXPOSURE))

	# 99. W9-P1 A2 authored progression: project_settings.json finally has a
	# consumer. The suite is a standalone SceneTree gate (it owns its save
	# fixtures under user://w9_progression/ and prints its own SUMMARY), so it
	# runs in a child engine exactly like suite 83: exit 0 AND the summary line
	# are both required, or the whole gate fails closed. It pins the level-25
	# cap with XP preserved, the authored thresholds, the authored XP award
	# (weights from the file, composition labelled), the KF13 > ladder > QG
	# endgame precedence, the 5,000 FTUE bankroll migration, all 48 market
	# level gates and the authored Guildhall mission order.
	var w9p_out: Array = []
	var w9p_args: PackedStringArray = [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/test_w9_progression.gd",
	]
	var w9p_t0: int = Time.get_ticks_msec()
	var w9p_code: int = OS.execute(OS.get_executable_path(), w9p_args, w9p_out, true)
	var w9p_ms: int = Time.get_ticks_msec() - w9p_t0
	var w9p_text: String = "\n".join(PackedStringArray(w9p_out))
	if w9p_code != 0 or w9p_text.find("W9_PROGRESSION SUMMARY: fails=0") < 0:
		printerr("FAIL: 99 W9-P1 authored progression exit=", w9p_code, " ms=", w9p_ms, "\n", w9p_text.right(4000))
		fails += 1
	else:
		print("PASS: 99 W9-P1 authored progression (level cap 25 with XP kept, authored XP award, KF13>ladder>QG endgame, FTUE 5,000, 48 level gates, map order; ", w9p_ms, " ms)")

	# 101-105. W9-P2 B2/B3 behaviour suites (standalone SceneTree children, the
	# same pattern as suite 99: exit 0 AND the PASS marker are both required).
	# These pin the authored-lock rule, the ESC-while-lockpicking guard, the
	# labelled lockpick stand-in, the jam-damage decision and the magic-door
	# continuity decision. They are headless and do not load a full mission.
	for w9p2_suite: Array in [
		["101", "W9-P2 B2 authored locks (cap-as-level, key-only/window exclusions, no invented level)", "res://tests/test_w9p2_locks.gd", "LOCKS PASS checks="],
		["102", "W9-P2 B2 lockpick ESC cancel does not open pause (LV4 path)", "res://tests/test_lockpick_cancel.gd", "LOCKPICK_CANCEL PASS checks="],
		["103", "W9-P2 B2 labelled lockpick hands stand-in (no authored mesh/animation)", "res://tests/test_lockpick_hands.gd", "LOCKPICK_HANDS PASS checks="],
		["104", "W9-P2 B3 jam damage is the authored value (no balance change)", "res://tests/test_jam_damage.gd", "JAM_DAMAGE PASS checks="],
		["105", "W9-P2 B3 magic-door continuity during the endgame (dormant never extracts)", "res://tests/test_w9p2_endgame_continuity.gd", "ENDGAME_CONTINUITY PASS checks="],
	]:
		var w9p2_out: Array = []
		var w9p2_args: PackedStringArray = [
			"--headless",
			"--path", ProjectSettings.globalize_path("res://"),
			"--script", str(w9p2_suite[2]),
		]
		var w9p2_t0: int = Time.get_ticks_msec()
		var w9p2_code: int = OS.execute(OS.get_executable_path(), w9p2_args, w9p2_out, true)
		var w9p2_ms: int = Time.get_ticks_msec() - w9p2_t0
		var w9p2_text: String = "\n".join(PackedStringArray(w9p2_out))
		if w9p2_code != 0 or w9p2_text.find(str(w9p2_suite[3])) < 0:
			printerr("FAIL: ", w9p2_suite[0], " ", w9p2_suite[1], " exit=", w9p2_code, " ms=", w9p2_ms, "\n", w9p2_text.right(3000))
			fails += 1
		else:
			print("PASS: ", w9p2_suite[0], " ", w9p2_suite[1], " (", w9p2_ms, " ms)")

	# 106-109. W9-P3 UI suites (standalone SceneTree children, the same pattern
	# as 99/101-105: exit 0 AND the summary marker are both required).
	# These pin the three authored screens (post-match/XP, progression,
	# tutorial), the gamepad focus walk over all ten menus, the authored TAB-map
	# boundary contract + loot toast, and the Loc fallback/reverse-map proof.
	for w9p3_suite: Array in [
		["106", "W9-P3 C1 post-match/XP + progression + tutorial from authored tables", "res://tests/test_w9p3_screens.gd", "W9P3_SCREENS_SUMMARY: fails=0"],
		["107", "W9-P3 C3 gamepad focus walk + rebind glyph (10 menus, no dead end)", "res://tests/test_focus_walk.gd", "FOCUS_WALK_SUMMARY: fails=0"],
		["108", "W9-P3 C4 authored TAB-map boundaries + major-loot toast", "res://tests/test_w9p3_map_toast.gd", "W9P3_MAP_TOAST_SUMMARY: fails=0"],
		["109", "W9-P3 C2 Loc fallback (English, never a GUID) + reverse map", "res://tests/test_w9p3_localization.gd", "W9P3_LOC_SUMMARY: fails=0"],
	]:
		var w9p3_out: Array = []
		var w9p3_args: PackedStringArray = [
			"--headless",
			"--path", ProjectSettings.globalize_path("res://"),
			"--script", str(w9p3_suite[2]),
		]
		var w9p3_t0: int = Time.get_ticks_msec()
		var w9p3_code: int = OS.execute(OS.get_executable_path(), w9p3_args, w9p3_out, true)
		var w9p3_ms: int = Time.get_ticks_msec() - w9p3_t0
		var w9p3_text: String = "\n".join(PackedStringArray(w9p3_out))
		if w9p3_code != 0 or w9p3_text.find(str(w9p3_suite[3])) < 0:
			printerr("FAIL: ", w9p3_suite[0], " ", w9p3_suite[1], " exit=", w9p3_code, " ms=", w9p3_ms, "\n", w9p3_text.right(3000))
			fails += 1
		else:
			print("PASS: ", w9p3_suite[0], " ", w9p3_suite[1], " (", w9p3_ms, " ms)")

	# 110-111. W9-P4 S1 StateTree runtime (standalone SceneTree children, the same
	# pattern as 99/101-109: exit 0 AND the summary marker are both required).
	# These parse/validate all 21 authored trees (459 states / 467 transitions),
	# exercise the generic interpreter on synthetic selector/task/priority/
	# observer/event/delay/UNKNOWN paths, build the measured coverage table, and
	# prove shadow mode is side-effect free by running the same live arena with
	# TAT2_STATETREE=off and =shadow and comparing the FSM signature.
	for w9p4_suite: Array in [
		["110", "W9-P4 S1 StateTree parse/interpreter/coverage (21 trees, 459/467, synthetic paths)", "res://tests/test_w9p4_statetree.gd", "W9P4_STATETREE_SUMMARY: fails=0"],
		["111", "W9-P4 S1 shadow mode is side-effect free (off vs shadow, 240 live frames)", "res://tests/test_w9p4_shadow.gd", "W9P4_SHADOW_SUMMARY: fails=0"],
	]:
		var w9p4_out: Array = []
		var w9p4_args: PackedStringArray = [
			"--headless",
			"--path", ProjectSettings.globalize_path("res://"),
			"--script", str(w9p4_suite[2]),
		]
		var w9p4_t0: int = Time.get_ticks_msec()
		var w9p4_code: int = OS.execute(OS.get_executable_path(), w9p4_args, w9p4_out, true)
		var w9p4_ms: int = Time.get_ticks_msec() - w9p4_t0
		var w9p4_text: String = "\n".join(PackedStringArray(w9p4_out))
		if w9p4_code != 0 or w9p4_text.find(str(w9p4_suite[3])) < 0:
			printerr("FAIL: ", w9p4_suite[0], " ", w9p4_suite[1], " exit=", w9p4_code, " ms=", w9p4_ms, "\n", w9p4_text.right(3000))
			fails += 1
		else:
			print("PASS: ", w9p4_suite[0], " ", w9p4_suite[1], " (", w9p4_ms, " ms)")

	# 112-120. W10 correctness gates (standalone SceneTree children, the same
	# pattern as 99/101-111: exit 0 AND the summary marker are both required).
	# These pin the five UI defects reproduced by INV-1 (continue consumer,
	# focus restore, ESC/pause, timeout reason, one rack-up layer), the StateTree
	# trace file budget and the coplanar-convex collision rule, the authored
	# `CanBeLockpicked` resolution (explicit-false exclusion + prison-door
	# fallback), and the two traversal fixtures that now build the authored
	# per-element union instead of `shapes[0]` (W10-A D10; the OldManor tower
	# flight is per-element because stair meshes are exempt from the 16-hull cap).
	# 117/118/120 are the P0a/P0b acceptance suites (guard placement, civilian
	# dress/sight/facing, GC hold-smash trigger). Suite 119 is deliberately
	# absent: `test_w10a2_cream.gd` is a standalone RED proof of the invented
	# white emissive and is registered by the data wave that fixes it.
	for w10_suite: Array in [
		["112", "W10-A screens: continue consumer, focus restore, ESC/pause, timeout reason, one layer", "res://tests/test_w10_screens.gd", "W10_SCREENS_SUMMARY: fails=0"],
		["113", "W10-A runtime: StateTree trace file budget + coplanar convex rule (ward zone)", "res://tests/test_w10_runtime.gd", "W10_RUNTIME_SUMMARY: fails=0"],
		["114", "W10-A locks: authored CanBeLockpicked resolution, explicit-false exclusion, prison fallback", "res://tests/test_w10_locks.gd", "W10_LOCKS_SUMMARY: fails=0"],
		["115", "W10-A stairs: authored per-element union walk (7 flights, tower 36 hulls)", "res://tests/test_stair_walk.gd", "W6M_STAIR_SUMMARY: fails=0"],
		["116", "W10-A traversal: authored per-element union roofs (3-4 hulls, no shapes[0])", "res://tests/test_traversal_routes.gd", "W6M_TRAVERSAL_SUMMARY: fails=0"],
		["117", "W10-A2 guards: authored bucket/layer selection, 2 m marker / 0.5 m floor, C_20 Lounge pick", "res://tests/test_w10a2_guard_placement.gd", "GUARD_PLACEMENT_SUMMARY: fails=0"],
		["118", "W10-A2 civilian: head-cast LOS, 180 deg facing, body/head 3+6 authored surfaces", "res://tests/test_w10a2_civilian.gd", "W10A2_CIV_SUMMARY: fails=0"],
		["120", "W10-A3 GC: hold-interact smash swaps leaf/broken once; tap keeps the lockpick", "res://tests/test_gc_break_trigger.gd", "GC_TRIGGER PASS"],
	]:
		var w10_out: Array = []
		var w10_args: PackedStringArray = [
			"--headless",
			"--path", ProjectSettings.globalize_path("res://"),
			"--script", str(w10_suite[2]),
		]
		var w10_t0: int = Time.get_ticks_msec()
		var w10_code: int = OS.execute(OS.get_executable_path(), w10_args, w10_out, true)
		var w10_ms: int = Time.get_ticks_msec() - w10_t0
		var w10_text: String = "\n".join(PackedStringArray(w10_out))
		if w10_code != 0 or w10_text.find(str(w10_suite[3])) < 0:
			printerr("FAIL: ", w10_suite[0], " ", w10_suite[1], " exit=", w10_code, " ms=", w10_ms, "\n", w10_text.right(3000))
			fails += 1
		else:
			print("PASS: ", w10_suite[0], " ", w10_suite[1], " (", w10_ms, " ms)")

	# 12.6/12.7 process-lifetime caches must not outlive the run.
	var am_node: Node = root.get_node_or_null("/root/AudioManager")
	if am_node != null and am_node.has_method("cleanup_on_exit"):
		am_node.call("cleanup_on_exit")
		# Audio playbacks are released by the audio thread after the player is
		# freed; 2 frames left Ogg playback refs alive at exit.
		for _i: int in range(8):
			await process_frame
	VfxManager.cleanup_static_caches()
	GuardAnimationLibrary.cleanup_static_caches()
	ArtNouveauTheme.cleanup_static_caches()
	XrayOverlay.clear_static_caches()
	(load("res://src/core/weather_profile.gd") as GDScript).cleanup_static_caches()
	(load("res://src/core/weather_visuals.gd") as GDScript).cleanup_static_caches()
	(load("res://src/ai/guard_ai.gd") as GDScript).cleanup_static_caches()
	for _j: int in range(8):
		await process_frame

	print("SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


## W5 suite helper: collects failure detail without aborting the whole gate.
func _w60_assert(cond: bool, msg: String, problems: Array) -> void:
	if not cond:
		problems.append(msg)


## Suite 87 helper (also a `--spider-only` entry): run the in-process Spider
## runtime mock and return its problems. Kept out of the main flow so the
## thermal shortcut and the full suite exercise exactly the same code.
func _run_suite87(host: Node) -> Array[String]:
	var problems: Array[String] = []
	var script: GDScript = load("res://tests/test_spider_runtime.gd") as GDScript
	if script == null:
		problems.append("test_spider_runtime.gd did not load")
		return problems
	var runner: RefCounted = script.new() as RefCounted
	if runner == null or not runner.has_method("run"):
		problems.append("test_spider_runtime.gd has no run(host)")
		return problems
	var out: Variant = runner.call("run", host)
	if out is Array:
		for problem_v: Variant in (out as Array):
			problems.append(str(problem_v))
	else:
		problems.append("test_spider_runtime.run(host) returned no problem list")
	return problems


## Suite 88 helper: the settle-path/binding suite (W4O). Same contract as 87,
## except `run(host)` is a coroutine (it awaits the physics frame that puts its
## synthetic supports into the broadphase), so this helper is one too and every
## caller must `await` it.
func _run_suite88(host: Node) -> Array[String]:
	var problems: Array[String] = []
	var script: GDScript = load("res://tests/test_personal_quest_settle.gd") as GDScript
	if script == null:
		problems.append("test_personal_quest_settle.gd did not load")
		return problems
	var runner: RefCounted = script.new() as RefCounted
	if runner == null or not runner.has_method("run"):
		problems.append("test_personal_quest_settle.gd has no run(host)")
		return problems
	var out: Variant = await runner.call("run", host)
	if out is Array:
		for problem_v: Variant in (out as Array):
			problems.append(str(problem_v))
	else:
		problems.append("test_personal_quest_settle.run(host) returned no problem list")
	return problems


## Suite 89 helper (W7S-S2): carried inventory/stash/payout. Coroutine because
## the 1.0 s actor-linger beat is measured with a real SceneTreeTimer.
func _run_suite89(host: Node) -> Array[String]:
	var problems: Array[String] = []
	var script: GDScript = load("res://tests/test_w7s_loot_inventory.gd") as GDScript
	if script == null:
		problems.append("test_w7s_loot_inventory.gd did not load")
		return problems
	var runner: RefCounted = script.new() as RefCounted
	if runner == null or not runner.has_method("run"):
		problems.append("test_w7s_loot_inventory.gd has no run(host)")
		return problems
	var out: Variant = await runner.call("run", host)
	if out is Array:
		for problem_v: Variant in (out as Array):
			problems.append(str(problem_v))
	else:
		problems.append("test_w7s_loot_inventory.run(host) returned no problem list")
	return problems


## Suite 91 helper (T02-STATE): run lifecycle — reset contract, hub clock,
## failure-path banking and the co-op run outcome. Synchronous: no map load.
func _run_suite91(host: Node) -> Array[String]:
	var problems: Array[String] = []
	var script: GDScript = load("res://tests/test_t02_state_lifecycle.gd") as GDScript
	if script == null:
		problems.append("test_t02_state_lifecycle.gd did not load")
		return problems
	var runner: RefCounted = script.new() as RefCounted
	if runner == null or not runner.has_method("run"):
		problems.append("test_t02_state_lifecycle.gd has no run(host)")
		return problems
	var out: Variant = runner.call("run", host)
	if out is Array:
		for problem_v: Variant in (out as Array):
			problems.append(str(problem_v))
	else:
		problems.append("test_t02_state_lifecycle.run(host) returned no problem list")
	return problems


## Suite 92 helper (T02-STATE): save integrity — corrupt quarantine, write
## errors, outbox settle and loadout copying. Synchronous (path_override files).
func _run_suite92(host: Node) -> Array[String]:
	var problems: Array[String] = []
	var script: GDScript = load("res://tests/test_t02_save_integrity.gd") as GDScript
	if script == null:
		problems.append("test_t02_save_integrity.gd did not load")
		return problems
	var runner: RefCounted = script.new() as RefCounted
	if runner == null or not runner.has_method("run"):
		problems.append("test_t02_save_integrity.gd has no run(host)")
		return problems
	var out: Variant = runner.call("run", host)
	if out is Array:
		for problem_v: Variant in (out as Array):
			problems.append(str(problem_v))
	else:
		problems.append("test_t02_save_integrity.run(host) returned no problem list")
	return problems


## Quarantined-save names in user:// (.corrupt-<ts>), used by suite 49 to prove
## the corrupt file was preserved and to clean the artefact up afterwards.
func _t02_quarantine_files() -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		return out
	for name: String in dir.get_files():
		if name.contains(".corrupt-"):
			out.append(name)
	return out


## Suite 90 helper (W7S-S2): save v8 + major-loot mesh. Coroutine for the
## one-frame GLB instantiation before counting mesh/light nodes.
func _run_suite90(host: Node) -> Array[String]:
	var problems: Array[String] = []
	var script: GDScript = load("res://tests/test_w7s_loot_save.gd") as GDScript
	if script == null:
		problems.append("test_w7s_loot_save.gd did not load")
		return problems
	var runner: RefCounted = script.new() as RefCounted
	if runner == null or not runner.has_method("run"):
		problems.append("test_w7s_loot_save.gd has no run(host)")
		return problems
	var out: Variant = await runner.call("run", host)
	if out is Array:
		for problem_v: Variant in (out as Array):
			problems.append(str(problem_v))
	else:
		problems.append("test_w7s_loot_save.run(host) returned no problem list")
	return problems


## Suite 91 helper (T10 remediation): objective markers, authored locks,
## container classes, carry speed, steal time, lockpick cancel distance.
## Coroutine: the marker/container/door fixtures await a frame between builds.
func _run_suite94(host: Node) -> Array[String]:
	var problems: Array[String] = []
	var loaded: Variant = load("res://tests/test_t10_gameplay.gd")
	if not (loaded is GDScript):
		problems.append("test_t10_gameplay.gd did not load (parse error)")
		return problems
	var script: GDScript = loaded as GDScript
	var runner: RefCounted = script.new() as RefCounted
	if runner == null or not runner.has_method("run"):
		problems.append("test_t10_gameplay.gd has no run(host)")
		return problems
	var out: Variant = await runner.call("run", host)
	if out is Array:
		for problem_v: Variant in (out as Array):
			problems.append(str(problem_v))
	else:
		problems.append("test_t10_gameplay.run(host) returned no problem list")
	return problems
## W0a suite helper: long edge from a PNG IHDR (no decode).
func _w82_png_long_edge(res_path: String) -> int:
	var f: FileAccess = FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return 0
	f.get_buffer(16)
	var w: int = f.get_32()
	var h: int = f.get_32()
	f.close()
	return maxi(w, h)
## W0a suite helper: imported .ctex dimensions from the sidecar's dest path.
## The header is `GST2`, u32 version, u32 width, u32 height (little-endian).
func _w82_imported_texture_size(res_path: String) -> Vector2i:
	var sidecar: String = FileAccess.get_file_as_string(res_path + ".import")
	var marker: String = "path=\"res://.godot/imported/"
	var at: int = sidecar.find(marker)
	if at < 0:
		return Vector2i.ZERO
	var rest: String = sidecar.substr(at + 6)
	var endq: int = rest.find("\"")
	if endq <= 0:
		return Vector2i.ZERO
	var f: FileAccess = FileAccess.open(rest.substr(0, endq), FileAccess.READ)
	if f == null:
		return Vector2i.ZERO
	var magic: PackedByteArray = f.get_buffer(4)
	f.get_buffer(4)
	var wb: PackedByteArray = f.get_buffer(4)
	var hb: PackedByteArray = f.get_buffer(4)
	f.close()
	if wb.size() != 4 or hb.size() != 4 or magic.get_string_from_ascii() != "GST2":
		return Vector2i.ZERO
	return Vector2i(int(wb.decode_u32(0)), int(hb.decode_u32(0)))
## W0a suite helper: every occurrence of `needle` in .gd files under dir_path.
func _w82_scan_gd(dir_path: String, needle: String, hits: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				_w82_scan_gd(full, needle, hits)
			elif entry.ends_with(".gd"):
				var text: String = FileAccess.get_file_as_string(full)
				var at: int = text.find(needle)
				while at >= 0:
					hits.append("%s:%d" % [full, text.substr(0, at).count("\n") + 1])
					at = text.find(needle, at + needle.length())
		entry = dir.get_next()
	dir.list_dir_end()
## W0a suite helper: minimal save file for migration boot tests.
func _w82_write_save(fields: Dictionary) -> void:
	var d: Dictionary = {"settings": {}, "completed_contracts": {}}
	d.merge(fields, true)
	var f: FileAccess = FileAccess.open("user://tat2_save.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, "\t"))
		f.close()
## W2: index of the authored patrol path whose points equal `points` (0.05 m
## per waypoint), or -1. Guards are matched by their whole assigned list
## because several authored paths share a first waypoint.
func _w2_match_patrol_path(points: Array, paths: Array) -> int:
	for i: int in range(paths.size()):
		if not (paths[i] is Dictionary):
			continue
		var authored: Array = (paths[i] as Dictionary).get("points", []) as Array
		if authored.size() != points.size() or points.is_empty():
			continue
		var matched: bool = true
		for k: int in range(authored.size()):
			var pos_v: Array = (authored[k] as Dictionary).get("pos", []) as Array
			if pos_v.size() < 3 or not (points[k] is Vector3):
				matched = false
				break
			var expect := Vector3(float(pos_v[0]), float(pos_v[1]), float(pos_v[2]))
			if (points[k] as Vector3).distance_to(expect) > 0.05:
				matched = false
				break
		if matched:
			return i
	return -1


## W2 test helpers: a layer-1 wall box and a layer-1 floor slab so interaction
## LOS and civilian grounding run against real collision.
func _w2_make_wall(parent: Node, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "W2Wall"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.2)
	shape.shape = box
	body.add_child(shape)
	body.position = at
	parent.add_child(body)
	return body


func _w2_make_floor(parent: Node, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "W2Floor"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	body.add_child(shape)
	body.position = at
	parent.add_child(body)
	return body


## Returns the first MeshInstance3D at or below `node` (null when absent).
## Test-only: the imported character GLBs wrap the mesh in a skeleton root.
func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_first_mesh_instance(child)
		if found != null:
			return found
	return null


func _authored_row_value(rows: Dictionary, row: String, field_path: Array[String]) -> float:
	var cur: Variant = rows.get(row, {})
	for field: String in field_path:
		if not (cur is Dictionary):
			return -1.0
		cur = (cur as Dictionary).get(field, null)
	if cur == null:
		return -1.0
	return float(cur)


## Reads an extracted-source JSON outside res:// (the repo checkout is the
## parent of game/). Test-only: runtime game code never reads extracted/.
func _repo_json(rel_path: String) -> Variant:
	var repo_dir: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return JSON.parse_string(FileAccess.get_file_as_string(repo_dir.path_join(rel_path)))


## T08: expected Godot albedo_color for an authored UE (linear) tint. Mirrors
## LevelLoader._srgb_encode_albedo_tint so suite 37 asserts the contract rather
## than a per-data-version literal. White when the row or tint is absent.
func _t08_expected_albedo_tint(db: Variant, mat_path: String) -> Color:
	if not (db is Dictionary):
		return Color(1.0, 1.0, 1.0, 1.0)
	var rec: Variant = (db as Dictionary).get(mat_path, null)
	if not (rec is Dictionary):
		return Color(1.0, 1.0, 1.0, 1.0)
	var t: Variant = (rec as Dictionary).get("tint", null)
	if not (t is Array) or (t as Array).size() < 3:
		return Color(1.0, 1.0, 1.0, 1.0)
	var a: Array = t as Array
	var lin := Color(float(a[0]), float(a[1]), float(a[2]), 1.0)
	return (load("res://src/core/level_loader.gd") as GDScript).call("_srgb_encode_albedo_tint", lin) as Color


## Returns FloatCurve.Keys from a UE CurveFloat JSON dump.
func _curve_keys(rel_path: String) -> Array:
	var doc: Variant = _repo_json(rel_path)
	if not (doc is Array) or (doc as Array).is_empty():
		return []
	var asset_v: Variant = (doc as Array)[0]
	if not (asset_v is Dictionary):
		return []
	var props_v: Variant = (asset_v as Dictionary).get("Properties", {})
	if not (props_v is Dictionary):
		return []
	var curve_v: Variant = (props_v as Dictionary).get("FloatCurve", {})
	if not (curve_v is Dictionary):
		return []
	var keys_v: Variant = (curve_v as Dictionary).get("Keys", [])
	if not (keys_v is Array):
		return []
	return keys_v as Array


## Returns the first materials.json entry whose /Game/... key ends with `suffix`.
func _material_entry_ending_with(mat_doc: Dictionary, suffix: String) -> Dictionary:
	for mat_key: Variant in mat_doc.keys():
		if str(mat_key).ends_with(suffix):
			var entry_v: Variant = mat_doc[mat_key]
			if entry_v is Dictionary:
				return entry_v as Dictionary
	return {}


## Returns the `texs` dictionary of a materials.json entry (empty if absent).
func _entry_texs(entry: Dictionary) -> Dictionary:
	var texs_v: Variant = entry.get("texs", null)
	if texs_v is Dictionary:
		return texs_v as Dictionary
	return {}


## W3 suite helper: count a check and print a PASS/FAIL line.
func _w3_check(cond: bool, ok_msg: String, fail_msg: String) -> int:
	if cond:
		print("PASS: ", ok_msg)
		return 0
	printerr("FAIL: ", fail_msg)
	return 1


## W3 suite helper: authored column-major basis from a devices_runtime record.
func _w3_basis_from_rec(rec: Dictionary) -> Basis:
	var b_v: Variant = rec.get("basis", [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0])
	var b: Array = b_v as Array if b_v is Array else [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
	return Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	)


## W3 suite helper: place a mock and return it for can_see() calls.
func _w3_at(node: Node3D, pos: Vector3) -> Node3D:
	node.global_position = pos
	return node


## P1-9(e) helper: collect every *.tatlevel.json under a res:// dir.
func _p1_collect_json(dir_path: String, out: Array) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname == "." or fname == "..":
			fname = dir.get_next()
			continue
		var full: String = dir_path.path_join(fname)
		if dir.current_is_dir():
			_p1_collect_json(full, out)
		elif fname.ends_with(".tatlevel.json"):
			out.append(full)
		fname = dir.get_next()
	dir.list_dir_end()


## W3 device suite mocks: a body with the authored standing/crouch heights and
## the damage/slow methods detectors and wards call.
class W3MockPlayer extends CharacterBody3D:
	var is_crouching: bool = false
	var health: float = 300.0
	var slow_calls: Array = []
	func body_height_m() -> float:
		return 1.0 if is_crouching else 1.78
	func take_damage(amount: float, _source: String = "") -> void:
		health = maxf(0.0, health - amount)
	func apply_ward_slow(multiplier: float, seconds: float) -> void:
		slow_calls.append([multiplier, seconds])
		set_meta("speed_multiplier", multiplier)


## W3 linked-action mock.
class W3MockAction extends Node:
	var hits: int = 0
	func activate_from(_source: Node = null) -> void:
		hits += 1


## P1-7 mock pickup interactor: exposes the health/max_health/charges
## surface world_pickup.interact() reads, plus the signals it emits.
class P1MockActor extends Node:
	var health: float = 20.0
	var max_health: float = 100.0
	var charges: Dictionary = {
		"slithersap": 0,
		"smoke_bomb": 0,
		"pickpocket_fairy": 0,
		"grapple": 0,
		"bottle": 0,
	}
	signal health_changed(h, mh)
	signal tool_used(a, b)


## Todo 6: sweep a player-sized capsule across a doorway. Returns the safe
## motion fraction (1.0 = passes through, <1 = blocked by the leaf).
func _door53_cast(space: PhysicsDirectSpaceState3D, cap: CapsuleShape3D, base: Vector3) -> float:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.transform = Transform3D(Basis(), base + Vector3(0.0, 0.89, -2.0))
	q.motion = Vector3(0.0, 0.0, 4.0)
	var r: PackedFloat32Array = space.cast_motion(q)
	if r.size() < 1:
		return -1.0
	return float(r[0])


## 91. T09 geometry/placement contract. Pure functions plus two payload reads;
## no map load, so it costs the suite ~0.3 s.
func _run_suite95(host: Node) -> Array[String]:
	var problems: Array[String] = []
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	if ll_scr == null:
		problems.append("level_loader.gd did not load")
		return problems
	var ll: Node = ll_scr.new() as Node
	host.add_child(ll)
	var levels_root: String = "res://data/generated/levels/"

	# 91a. Spline record conversion: the producer's documented schema is
	# Godot-local metres with the UE (x, z, y) swap and the negated roll.
	var raw := {
		"p0": [-2.0, 0.0, 0.0], "t0": [6.0, 0.0, 0.0],
		"p1": [2.0, 1.0, 0.0], "t1": [6.0, 0.0, 0.0],
		"scale0": [2.0, 3.0], "scale1": [2.0, 3.0],
		"offset0": [0.0, 0.5, 0.25], "offset1": [0.0, 0.5, 0.25],
		"roll0": 0.0, "roll1": 0.0,
	}
	var rec: Dictionary = ll.call("normalize_spline", raw) as Dictionary
	if rec.is_empty() or not (rec.get("p0") is Vector3):
		problems.append("normalize_spline did not produce Vector3 params")
	else:
		# 91b. The loft must place the mesh ends on the authored endpoints and
		# bend through the tangents (a straight lerp would put t=0.5 at y=0.5).
		var p0: Vector3 = ll.call("spline_point", rec, 0.0) as Vector3
		var p1: Vector3 = ll.call("spline_point", rec, 1.0) as Vector3
		var mid: Vector3 = ll.call("spline_point", rec, 0.5) as Vector3
		if p0.distance_to(Vector3(-2.0, 0.0, 0.0)) > 1e-4:
			problems.append("spline t=0 is %s, expected (-2, 0, 0)" % str(p0))
		if p1.distance_to(Vector3(2.0, 1.0, 0.0)) > 1e-4:
			problems.append("spline t=1 is %s, expected (2, 1, 0)" % str(p1))
		if mid.y <= 0.1 or absf(mid.x) > 1.0:
			problems.append("spline t=0.5 is %s: not a bent Hermite" % str(mid))
		# 91c. The slice frame carries the authored 2D cross-section offset.
		var frame: Transform3D = ll.call("spline_frame", rec, 0.5) as Transform3D
		if (frame.origin - mid).length() < 0.4:
			problems.append("spline frame origin %s does not apply the authored offset" % str(frame.origin))
		# 91d. A real deformed mesh must span the spline, not the rigid AABB.
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.2, 0.2)
		var deformed: Mesh = ll.call("spline_deform_mesh", box, rec) as Mesh
		if deformed == null:
			problems.append("spline_deform_mesh returned null")
		else:
			var aabb: AABB = deformed.get_aabb()
			if aabb.size.x < 3.5:
				problems.append("deformed spline spans %.2f m in X, expected >= 3.5" % aabb.size.x)

	# 91e. Level keys: only generated-level paths qualify, and both producer
	# normalisations (/Game/Maps/... and /Game/...) land on the same key.
	if str(ll.call("_level_key_from_res", levels_root + "OldManor/OldManor_P.tatlevel.json")) != "OldManor/OldManor_P":
		problems.append("_level_key_from_res mis-keys a generated level path")
	if str(ll.call("_level_key_from_res", "res://scenes/mission.tscn")) != "":
		problems.append("_level_key_from_res accepted a non-level path")

	# 91f. The authored always-loaded graph must add the two levels the
	# hardcoded lists dropped, and must never add a dynamic one.
	var acc: Dictionary = ll.call("_new_accumulator") as Dictionary
	for sl: Dictionary in [
		{"level": "OldManor/OldManor_PathBlockers", "type": "always"},
		{"level": "ThievesDenTest/ThievesDenTest_Contracts", "type": "always"},
		{"level": "Guildhall/Guildhall_SkyboxGeo", "type": "dynamic"},
		{"level": "Guildhall/Guildhall_P", "type": "always"},
	]:
		(acc["streaming_levels"] as Array).append(sl)
	(acc["sublevel_keys"] as Dictionary)["Guildhall/Guildhall_P"] = true
	var added: Array = ll.call("_resolve_authored_streaming", acc) as Array
	var added_paths: Array[String] = []
	for a_var: Variant in added:
		added_paths.append(str(a_var))
	if not added_paths.has(levels_root + "OldManor/OldManor_PathBlockers.tatlevel.json"):
		problems.append("graph resolver dropped OldManor_PathBlockers")
	if not added_paths.has(levels_root + "ThievesDenTest/ThievesDenTest_Contracts.tatlevel.json"):
		problems.append("graph resolver dropped ThievesDenTest_Contracts")
	if added_paths.has(levels_root + "Guildhall/Guildhall_SkyboxGeo.tatlevel.json"):
		problems.append("graph resolver added a dynamic sublevel")
	if added_paths.size() != 2:
		problems.append("graph resolver added %d sublevels, expected 2" % added_paths.size())

	# 91g. A sublevel already merged as a LevelInstance must be recognised so
	# it is never parsed standalone (the 1,693-mesh FTUE jewelry-store copy).
	var ftue_parent: String = levels_root + "FTUE/FTUE_Geometry.tatlevel.json"
	if FileAccess.file_exists(ftue_parent):
		var merged: Dictionary = ll.call("_prescan_merged_sublevels", [ftue_parent]) as Dictionary
		if not merged.has("FTUE/FTUE_Building_JewelryStore"):
			problems.append("_prescan_merged_sublevels missed the FTUE jewelry-store LevelInstance")
	else:
		problems.append("FTUE_Geometry payload missing")

	# 91h. The [0.05, 40] clamp and mirrored bases are counted, not silent.
	ll.set("_scale_clamp_count", 0)
	ll.set("_scale_clamp_worst", 1.0)
	ll.set("_mirrored_basis_count", 0)
	ll.call("_dict_to_transform", {"pos": [0, 0, 0], "basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "scale": [0.0021, 1.0, 42.55]})
	if int(ll.get("_scale_clamp_count")) != 1:
		problems.append("clamped scale not counted")
	# 0.05/0.0021 = 23.81x is the worst of the two clamped axes for this record
	# (42.55/40 = 1.06x); the payload's true worst is 500x (a 0.0001 m sliver).
	if absf(float(ll.get("_scale_clamp_worst")) - (0.05 / 0.0021)) > 0.01:
		problems.append("clamp worst ratio %f, expected %.3f" % [
			float(ll.get("_scale_clamp_worst")), 0.05 / 0.0021])
	ll.call("_dict_to_transform", {"pos": [0, 0, 0], "basis": [-1, 0, 0, 0, 1, 0, 0, 0, 1], "scale": [1, 1, 1]})
	if int(ll.get("_mirrored_basis_count")) != 1:
		problems.append("mirrored basis not counted")

	# 91i. The auto-mantle duration follows the authored clip, not 0.3 s.
	var tc_src: String = FileAccess.get_file_as_string("res://src/player/thief_character.gd")
	if tc_src.find("delta / 0.3") >= 0:
		problems.append("thief_character.gd still divides the mantle by 0.3 s")
	if tc_src.find("MANTLE_MOVE_SEC_BY_BAND") < 0:
		problems.append("thief_character.gd lost the authored mantle duration table")
	var meta_path: String = "res://data/generated/anims_meta.json"
	if FileAccess.file_exists(meta_path):
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if meta is Dictionary:
			var clips: Dictionary = (meta as Dictionary).get("clips", {}) as Dictionary
			var bands := {
				"mantle_050": "AN_Mantle_050CM",
				"mantle_100": "AN_Mantle_100CM",
				"mantle_150": "AN_Mantle_150CM",
				"mantle_200": "AN_Mantle_200CM",
				"mantle_250": "AN_Mantle_250CM",
				"mantle_300": "AN_Mantle_300CM",
			}
			var tc_scr: GDScript = load("res://src/player/thief_character.gd") as GDScript
			var table: Dictionary = tc_scr.get_script_constant_map().get("MANTLE_MOVE_SEC_BY_BAND", {}) as Dictionary
			for band: String in bands.keys():
				var clip_name: String = bands[band]
				if not clips.has(clip_name) or not table.has(band):
					problems.append("mantle band %s missing from data or table" % band)
					continue
				var authored: float = float((clips[clip_name] as Dictionary).get("length", 0.0))
				var used: float = float(table[band])
				if absf(authored - used) > 0.01:
					problems.append("mantle band %s uses %.3fs, authored %.3fs" % [band, used, authored])
	else:
		problems.append("anims_meta.json missing; mantle duration cannot be checked")

	ll.queue_free()
	return problems
# --- W8 AI suite (T11-AI) ----------------------------------------------------
# Authored consumers from the RE-I lane. Everything here is behavioural or a
# comparison against the raw extract; no constant is asserted against itself.


## A player-shaped body with the properties guard_ai reads. Cheaper than the real
## thief (no GLB loads) and enough for perception geometry.
func _ai_stub_player(host: Node, at: Vector3) -> CharacterBody3D:
	var body: CharacterBody3D = CharacterBody3D.new()
	body.name = "AIPlayerStub"
	body.collision_layer = 2
	body.collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(col)
	body.position = at
	host.add_child(body)
	return body


## The authored 0.45 s blackjack hold with live physics: the real thief, the real
## guard, the real hold accumulation and the real `_perform_hold_action`. Suite
## 55c froze every actor and called `_try_blackjack` directly, so neither the AI
## tick nor the hold race ever ran (RE-I-14).
func _ai_blackjack_hold(host: Node, at: Vector3, reach_m: float) -> Dictionary:
	var gs: Node = host.get_node_or_null("GameState")
	var state_before: String = str(gs.get("state"))
	var spotted_before: bool = bool(gs.get("ever_spotted"))
	var takedowns_before: int = int(gs.get("takedowns"))
	gs.set("state", "playing")
	gs.set("ever_spotted", false)
	var guard: CharacterBody3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as CharacterBody3D
	guard.name = "AIHoldGuard"
	guard.position = at
	guard.rotation = Vector3.ZERO
	guard.set("patrol_points", [at])
	guard.set("patrol_speed", 0.0)
	guard.set("suspicious_speed", 0.0)
	guard.set("chase_speed", 0.0)
	host.add_child(guard)
	var player: Node3D = (load("res://src/player/thief_character.gd") as GDScript).new() as Node3D
	player.name = "AIHoldThief"
	player.position = at + Vector3(0.0, 0.0, reach_m)
	host.add_child(player)
	await process_frame
	await physics_frame
	guard.set("detection", 0.0)
	guard.set("state", 0)
	var prompt: String = str(player.call("get_look_secondary_prompt"))
	player.set("_interact_hold_ms", Time.get_ticks_msec())
	player.set("_interact_hold_sec", 0.0)
	var frames: int = 0
	while float(player.get("_interact_hold_sec")) < 0.45 and frames < 240:
		await physics_frame
		frames += 1
	var held: float = float(player.get("_interact_hold_sec"))
	var seen: bool = bool(guard.call("_can_see_player", player))
	var detection: float = float(guard.get("detection"))
	player.set("_interact_hold_ms", -1)
	player.set("_interact_hold_sec", -1.0)
	player.call("_perform_hold_action")
	# T04-ANIM (RE-F-12): the KO lands inside the authored CombatHitbox window
	# (0.390 s of the 0.667 s light swing), not on the release frame. Wait for
	# the contact — bounded so a genuine failure still fails fast — instead of
	# asserting the pre-T04 frame-0 timing. Suite 55c and 91d share this helper.
	var ko_frames: int = 0
	while int(guard.get("state")) != 5 and ko_frames < 90:
		await physics_frame
		ko_frames += 1
	var out: Dictionary = {
		"prompt": prompt,
		"held": held,
		"seen": seen,
		"detection": detection,
		"ko": int(guard.get("state")) == 5,
		"spot": bool(gs.get("ever_spotted")),
		"takedowns": int(gs.get("takedowns")) - takedowns_before,
	}
	gs.set("ever_spotted", spotted_before)
	gs.set("state", state_before)
	player.queue_free()
	guard.queue_free()
	await process_frame
	return out


## Suite 91. Returns human-readable problems (empty = pass).
func _run_suite97(host: Node) -> Array[String]:
	var problems: Array[String] = []
	var SightModel: GDScript = load("res://src/ai/sight_model.gd") as GDScript
	var GuardRoster: GDScript = load("res://src/ai/guard_roster.gd") as GDScript
	var ReactionRoles: GDScript = load("res://src/ai/reaction_roles.gd") as GDScript
	var RangedAttack: GDScript = load("res://src/ai/ranged_attack.gd") as GDScript
	var NavSteering: GDScript = load("res://src/ai/nav_steering.gd") as GDScript
	var hearing: GDScript = load("res://src/ai/hearing_data.gd") as GDScript
	var occlusion: GDScript = load("res://src/ai/hearing_occlusion.gd") as GDScript
	var gs: Node = host.get_node_or_null("GameState")
	var noise_bus: Node = host.get_node_or_null("NoiseBus")

	# 91a. The five dropped sight fields: every fallback value equals the raw
	# authored asset, and the derived frustum is the audit's arithmetic.
	var raw: Variant = _repo_json("extracted/json/AI/Controllers/AIC_GuardBase.json")
	if raw is Array:
		var raw_rows: Array = []
		for obj_v: Variant in (raw as Array):
			var obj: Dictionary = obj_v as Dictionary
			var props: Dictionary = obj.get("Properties", {}) as Dictionary
			if props.has("_EscalationStateToSettings"):
				raw_rows = props["_EscalationStateToSettings"] as Array
				break
		var names: Array[String] = ["Drowsy", "Fresh", "Mindful", "Vigilant"]
		var mismatches: Array[String] = []
		for i: int in range(mini(names.size(), raw_rows.size())):
			var v: Dictionary = ((raw_rows[i] as Dictionary).get("Value", {}) as Dictionary)
			var row: Dictionary = SightModel.call("row", "guardbase", names[i])
			var pairs: Array = [
				["sight_radius_m", "SightRadius"],
				["lose_sight_radius_m", "LoseSightRadius"],
				["peripheral_half_angle_deg", "PeripheralVisionAngleDegrees"],
				["minimum_sight_radius_m", "MinimumSightRadius"],
				["point_of_view_backward_offset_m", "PointOfViewBackwardOffset"],
				["near_clipping_radius_m", "NearClippingRadius"],
				["frustum_aspect_ratio", "FrustumAspectRatio"],
				["frustum_pitch_deg", "FrustumPitch"],
			]
			for pair: Array in pairs:
				var ours: float = float(row.get(str(pair[0]), -9999.0))
				var authored_cm: float = float(v.get(str(pair[1]), -9999.0))
				var expect: float = authored_cm
				if str(pair[0]).ends_with("_m"):
					expect = authored_cm / 100.0
				if absf(ours - expect) > 0.0001:
					mismatches.append("%s.%s=%s want %s" % [names[i], str(pair[0]), str(ours), str(expect)])
		var band: Vector2 = SightModel.call("elevation_band_deg", SightModel.call("row", "guardbase", "Fresh"))
		if not mismatches.is_empty():
			problems.append("91a sight rows differ from the authored asset: " + ", ".join(mismatches))
		elif absf(band.x - -44.75) > 0.1 or absf(band.y - 0.75) > 0.1:
			problems.append("91a Fresh elevation band %s want [-44.75, 0.75]" % str(band))
	else:
		print("[91a] SKIP: extracted/ absent, authored sight rows not compared")

	# 91b. The frustum matrix: behind = outside, in front = inside, a balcony
	# above the horizon = outside, point blank = inside (near clip).
	var fresh: Dictionary = SightModel.call("row", "guardbase", "Fresh")
	var fwd := Vector3(0.0, 0.0, -1.0)
	var cases: Array = [
		[Vector3(0.0, 0.0, 2.2), false, "rear 2.2 m"],
		[Vector3(0.0, 0.0, -5.0), true, "front 5 m"],
		[Vector3(0.0, 2.0, -5.0), false, "balcony +2 m at 5 m"],
		[Vector3(0.0, 0.0, 0.9), true, "point blank 0.9 m behind"],
		[Vector3(2.0, 0.0, -5.0), true, "front 28 deg"],
		[Vector3(4.0, 0.0, -4.0), false, "front 55 deg off the POV axis"],
		[Vector3(7.0, 0.0, -3.0), false, "front 76 deg outside the cone"],
	]
	for case_v: Array in cases:
		var dir: Vector3 = (case_v[0] as Vector3)
		var got: bool = bool(SightModel.call("frustum_admits", fresh, dir, fwd))
		if got != bool(case_v[1]):
			problems.append("91b frustum case '%s' got %s want %s" % [str(case_v[2]), str(got), str(case_v[1])])

	# 91c. Detection ramps are a mirror of detection.json, not a free constant.
	var det_json: Variant = _repo_json("game/data/generated/gameplay/detection.json")
	if det_json is Dictionary:
		var gconsts: Dictionary = (load("res://src/ai/guard_ai.gd") as GDScript).get_script_constant_map()
		var ramps: Dictionary = gconsts.get("DETECTION_RAMPS", {}) as Dictionary
		for state_name: String in ["neutral", "suspicious", "alerted", "combat"]:
			var idx: int = {"neutral": 0, "suspicious": 1, "alerted": 2, "combat": 3}[state_name]
			var json_rows: Variant = (det_json as Dictionary).get(state_name, [])
			if not (json_rows is Array) or (json_rows as Array).is_empty():
				continue
			var row: Dictionary = (json_rows as Array)[0] as Dictionary
			var ours: Dictionary = ramps.get(idx, {}) as Dictionary
			if not is_equal_approx(float(ours.get("agnostic", -1.0)), float(row.get("agnostic_seconds_per_meter", row.get("agnostic", -1.0)))):
				problems.append("91c ramp %s agnostic %s != %s" % [state_name, str(ours.get("agnostic")), str(row.get("agnostic_seconds_per_meter", row.get("agnostic")))])
	else:
		print("[91c] SKIP: detection.json absent")

	# 91d. Live blackjack hold: winnable, no ever_spotted, no detection ramp.
	var arena := Vector3(8100.0, 0.0, 8100.0)
	var floor_a: StaticBody3D = _w2_make_floor(host, arena + Vector3(0.0, -0.55, 0.0))
	await physics_frame
	var hold: Dictionary = await _ai_blackjack_hold(host, arena, 2.2)
	if str(hold.get("prompt", "")) != "[F] [HOLD] TAKEDOWN":
		problems.append("91d live hold prompt=%s" % str(hold.get("prompt")))
	if float(hold.get("held", 0.0)) + 0.0001 < 0.45:
		problems.append("91d hold never reached 0.45 s (held=%s)" % str(hold.get("held")))
	if bool(hold.get("seen", true)):
		problems.append("91d guard saw the thief during the hold")
	if float(hold.get("detection", 1.0)) > 0.0:
		problems.append("91d detection ramp ran during the hold (%s)" % str(hold.get("detection")))
	if not bool(hold.get("ko", false)):
		problems.append("91d takedown did not knock the guard out")
	if bool(hold.get("spot", true)):
		problems.append("91d ever_spotted set by the takedown")
	if int(hold.get("takedowns", 0)) != 1:
		problems.append("91d takedown counter did not move")

	# 91e. Reaction-role cap: one heavy stimulus, four listeners, two
	# investigators (DT_ReactionEvents HeaviestStim Investigator max 2).
	ReactionRoles.call("reset")
	noise_bus.call("reset_event_counter")
	var listeners: Array[Node] = []
	for i: int in range(4):
		var g: CharacterBody3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as CharacterBody3D
		g.name = "AICapGuard%d" % i
		g.position = arena + Vector3(20.0 + float(i) * 2.0, 0.0, 0.0)
		g.set("patrol_points", [g.position])
		host.add_child(g)
		listeners.append(g)
	await process_frame
	for g2: Node in listeners:
		g2.set_physics_process(false)
	var record: Dictionary = noise_bus.call("build_record", arena + Vector3(22.0, 0.0, 3.0), 10.0, null, "bottle", "")
	for g3: Node in listeners:
		g3.call("_on_noise_record", record)
	var investigators: int = 0
	var standby: int = 0
	for g4: Node in listeners:
		if int(g4.get("state")) == 1:
			investigators += 1
		elif int(g4.get("state")) == 0 and int(g4.get("heard_as_standby")) > 0:
			standby += 1
	if investigators != 2 or standby != 2:
		problems.append("91e investigator cap: investigators=%d standby=%d want 2/2" % [investigators, standby])
	if int(ReactionRoles.call("claim_count", int(record.get("event_id", 0)))) != 2:
		problems.append("91e registry records %d investigators" % int(ReactionRoles.call("claim_count", int(record.get("event_id", 0)))))
	for g5: Node in listeners:
		g5.queue_free()
	await process_frame

	# 91f. GuardDowned: a body in front of a live guard raises the witness.
	var body_arena := arena + Vector3(0.0, 0.0, 30.0)
	var floor_b: StaticBody3D = _w2_make_floor(host, body_arena + Vector3(0.0, -0.55, 0.0))
	await physics_frame
	var victim: CharacterBody3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as CharacterBody3D
	victim.name = "AIBody"
	victim.position = body_arena + Vector3(0.0, 0.0, -5.0)
	host.add_child(victim)
	var witness: CharacterBody3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as CharacterBody3D
	witness.name = "AIWitness"
	witness.position = body_arena
	witness.rotation = Vector3.ZERO
	witness.set("patrol_points", [body_arena])
	host.add_child(witness)
	await process_frame
	await physics_frame
	victim.call("knock_out", 5.0)
	witness.set("detection", 0.0)
	witness.set("state", 0)
	await physics_frame
	for _f: int in range(60):
		await physics_frame
	var witness_ok: bool = int(witness.get("bodies_seen")) >= 1 and int(witness.get("state")) != 0
	var investigate_near: bool = (witness.get("investigate_pos") as Vector3).distance_to(victim.global_position) < 2.0
	if not witness_ok:
		problems.append("91f GuardDowned not noticed (bodies_seen=%d state=%d)" % [int(witness.get("bodies_seen")), int(witness.get("state"))])
	elif not investigate_near:
		problems.append("91f GuardDowned witness investigate_pos is not the body")
	victim.queue_free()
	witness.queue_free()
	floor_b.queue_free()
	await process_frame

	# 91g. Roster buckets: all seven authored buckets resolve, the Bouncer row
	# and the Hauntstable's own 30 m row are reachable, KeyHolder carries a key.
	var bucket_names: Array = ["DA_SpawnBucket_KeyHolder", "DA_SpawnBucket_Hauntstable", "DA_SpawnBucket_PrivateSecurity", "DA_SpawnBucket_PrivateSecurity_Lanterns", "DA_SpawnBucket_StandardGuards_Bouncers", "DA_SpawnBucket_StandardGuards_Lanterns", "DA_SpawnBucket_StandardGuards_PrivateSecurity_JasperingHall_Lantern"]
	for bucket: String in bucket_names:
		var row: Dictionary = GuardRoster.call("roster_for", bucket)
		if str(row.get("source", "unbound")) == "unbound":
			problems.append("91g roster bucket %s unresolved" % bucket)
	var bouncer_row: Dictionary = GuardRoster.call("roster_for", "BP_GuardEnforcer_Club_C")
	var haunt_row: Dictionary = GuardRoster.call("roster_for", "BP_Hauntstable_C")
	var key_row: Dictionary = GuardRoster.call("roster_for", "BP_GuardSecurity_KeyHolder_C")
	if str(bouncer_row.get("profile", "")) != "bouncer":
		problems.append("91g BP_GuardEnforcer_Club_C profile=%s" % str(bouncer_row.get("profile")))
	if str(haunt_row.get("profile", "")) != "hauntstable" or str(haunt_row.get("weapon", "")) != "hauntstable":
		problems.append("91g BP_Hauntstable_C row=%s" % JSON.stringify(haunt_row))
	if key_row.get("carries_key", false) != true or GuardRoster.call("carried_key_id", key_row, "guildhall") != "key_guildhall":
		problems.append("91g KeyHolder does not carry the Guildhall Key")
	var haunt_sight: Dictionary = SightModel.call("row", "hauntstable", "Fresh")
	if absf(float(haunt_sight.get("sight_radius_m", 0.0)) - 30.0) > 0.0001:
		problems.append("91g Hauntstable sight %s want 30 m" % str(haunt_sight.get("sight_radius_m")))

	# 91h. The stolen key reaches GameState through a real pickpocket, so the
	# KeyHolder loop has a source end even though the lock consumer is T10's.
	var key_guard: CharacterBody3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as CharacterBody3D
	key_guard.name = "AIKeyGuard"
	key_guard.position = arena + Vector3(0.0, 0.0, 60.0)
	key_guard.set("roster_bucket", "BP_GuardSecurity_KeyHolder_C")
	host.add_child(key_guard)
	var thief_stub: CharacterBody3D = _ai_stub_player(host, key_guard.position + Vector3(0.0, 0.0, 1.2))
	await process_frame
	await physics_frame
	var keys_before: int = (gs.get("stolen_keys") as Array).size()
	key_guard.set("carried_item", {"id": "key_guildhall", "name": "Guildhall Key", "kind": "key", "value": 150})
	key_guard.call("interact", thief_stub)
	if not bool(gs.call("has_stolen_key", "key_guildhall")):
		problems.append("91h pickpocket did not grant the Guildhall Key (keys %d -> %d)" % [keys_before, (gs.get("stolen_keys") as Array).size()])
	if str(key_guard.call("escalation_profile")) != "guardbase":
		problems.append("91h KeyHolder profile=%s" % str(key_guard.call("escalation_profile")))
	key_guard.queue_free()
	thief_stub.queue_free()
	await process_frame

	# 91i. Ranged combat: the authored damage curve, the 20 m extent, the 2 s
	# cooldown and the shock contract; and the DT_ReactionEvents combat pair.
	if absf(float(RangedAttack.call("damage_at_m", 0.0)) - 10.0) > 0.0001 \
		or absf(float(RangedAttack.call("damage_at_m", 10.0)) - 6.0) > 0.0001 \
		or absf(float(RangedAttack.call("damage_at_m", 20.0)) - 2.0) > 0.0001 \
		or absf(float(RangedAttack.call("damage_at_m", 35.0)) - 2.0) > 0.0001:
		problems.append("91i ranged damage curve is not 10@0 -> 2@20 m")
	var shock_holder: Dictionary = {"damage": -1.0, "shock": -1.0}
	var victim_stub: Node = _ranged_victim_stub(shock_holder)
	var delivered: Dictionary = RangedAttack.call("deliver", victim_stub, 10.0, "guard_ranged") as Dictionary
	if absf(float(shock_holder["damage"]) - 6.0) > 0.0001 or absf(float(shock_holder["shock"]) - 3.0) > 0.0001:
		problems.append("91i deliver at 10 m: damage=%s shock=%s" % [str(shock_holder["damage"]), str(shock_holder["shock"])])
	if delivered.get("shock_applied", false) != true or absf(float(delivered.get("shock_seconds", 0.0)) - 3.0) > 0.0001:
		problems.append("91i shock contract not delivered")
	victim_stub.free()
	ReactionRoles.call("reset")
	var chaser_a: String = str(ReactionRoles.call("claim_combat", "target:1", 11, 1000, true))
	var chaser_b: String = str(ReactionRoles.call("claim_combat", "target:1", 22, 1000, true))
	var ranged_c: String = str(ReactionRoles.call("claim_combat", "target:1", 33, 1000, false))
	if chaser_a != "chaser" or chaser_b != "ranged" or ranged_c != "ranged":
		problems.append("91i combat pair a=%s b=%s c=%s want chaser/ranged/ranged" % [chaser_a, chaser_b, ranged_c])
	# Live: a COMBAT guard at 8 m with LOS fires the authored curve instead of
	# walking into 1 m melee (RE-I-11). The old port damaged only inside 1 m.
	ReactionRoles.call("reset")
	var ranged_arena := arena + Vector3(0.0, 0.0, 120.0)
	var floor_r: StaticBody3D = _w2_make_floor(host, ranged_arena + Vector3(0.0, -0.55, 0.0))
	await physics_frame
	var shooter: CharacterBody3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as CharacterBody3D
	shooter.name = "AIRangedGuard"
	shooter.position = ranged_arena
	shooter.rotation = Vector3.ZERO
	shooter.set("patrol_points", [ranged_arena])
	host.add_child(shooter)
	var target_stub: CharacterBody3D = _ai_damage_stub(host, ranged_arena + Vector3(0.0, 0.0, -8.0))
	target_stub.add_to_group("player")
	await process_frame
	await physics_frame
	shooter.set("state", 3)  # Alertness.COMBAT
	shooter.set("attack_cooldown", 0.0)
	shooter.set("detection", 100.0)
	for _rf: int in range(30):
		await physics_frame
	var dealt: float = float(target_stub.get("damage_taken"))
	var expected: float = float(RangedAttack.call("damage_at_m", shooter.global_position.distance_to(target_stub.global_position)))
	if dealt <= 0.0:
		problems.append("91i COMBAT guard at 8 m never fired (damage_taken=%s)" % str(dealt))
	elif absf(dealt - expected) > 0.75:
		problems.append("91i ranged damage %s != curve %s" % [str(dealt), str(expected)])
	if absf(float(shooter.get("last_ranged_damage")) - expected) > 0.75:
		problems.append("91i last_ranged_damage %s != %s" % [str(shooter.get("last_ranged_damage")), str(expected)])
	if int(shooter.get("ranged_accuracy_stacks")) < 1:
		problems.append("91i accuracy stack did not increment")
	shooter.queue_free()
	target_stub.queue_free()
	floor_r.queue_free()
	await process_frame

	# 91j. Hearing: 11 of the 54 authored rows are reachable from the port's
	# emitter tags (8 before W8), walls block, and the authored portal rule is
	# what admits a sound through a doorway.
	var emitter_tags: Array = ["takedown", "bottle", "door", "lock", "lockpick", "lockpick_jammed", "noise_alarm", "combat_hit", "npc_yelp", "npc_call_help", "footstep"]
	var reachable: Array = hearing.call("reachable_stim_tags", emitter_tags)
	var unreachable: Array = hearing.call("unreachable_stim_tags", emitter_tags)
	if reachable.size() != 11:
		problems.append("91j reachable hearing rows=%d want 11 (%s)" % [reachable.size(), ", ".join(reachable)])
	if int(hearing.call("stim_count")) != 54 or reachable.size() + unreachable.size() != 54:
		problems.append("91j stim registry/reachability do not partition 54 rows")
	var occ_arena := arena + Vector3(60.0, 0.0, 0.0)
	var floor_c: StaticBody3D = _w2_make_floor(host, occ_arena + Vector3(0.0, -0.55, 0.0))
	await physics_frame
	var ear: CharacterBody3D = (load("res://src/ai/guard_ai.gd") as GDScript).new() as CharacterBody3D
	ear.name = "AIEar"
	ear.position = occ_arena
	ear.set("patrol_points", [occ_arena])
	host.add_child(ear)
	await process_frame
	ear.set_physics_process(false)
	occlusion.call("reset_stats")
	var open_record: Dictionary = noise_bus.call("build_record", occ_arena + Vector3(0.0, 0.0, 3.0), 10.0, null, "bottle", "")
	ear.call("_on_noise_record", open_record)
	var heard_open: bool = int(ear.get("state")) != 0
	var wall: StaticBody3D = _w2_make_wall(host, occ_arena + Vector3(0.0, 1.0, 1.5))
	await physics_frame
	ear.set("state", 0)
	var occh: Dictionary = occlusion.call("stats") as Dictionary
	var blocked_before: int = int(occh.get("blocks", 0))
	var wall_record: Dictionary = noise_bus.call("build_record", occ_arena + Vector3(0.0, 0.0, 3.0), 10.0, null, "bottle", "")
	ear.call("_on_noise_record", wall_record)
	var heard_wall: bool = int(ear.get("state")) != 0
	var occh2: Dictionary = occlusion.call("stats") as Dictionary
	if not heard_open:
		problems.append("91j open-floor stimulus was not heard")
	if heard_wall or int(occh2.get("blocks", 0)) <= blocked_before:
		problems.append("91j wall did not block the stimulus (heard=%s blocks %d->%d)" % [str(heard_wall), blocked_before, int(occh2.get("blocks", 0))])
	if int(occlusion.call("portal_count")) != 285:
		problems.append("91j acoustic portal registry=%d want 285" % int(occlusion.call("portal_count")))
	wall.queue_free()
	ear.queue_free()
	floor_c.queue_free()
	await process_frame

	# 91k. Navigation: no baked map => explicit degradation, straight-line fall.
	NavSteering.call("reset_stats")
	var nav_body: Node3D = Node3D.new()
	nav_body.position = Vector3.ZERO
	host.add_child(nav_body)
	var nav = NavSteering.new()
	nav.call("setup", nav_body)
	var dir: Vector3 = nav.call("step_towards", Vector3(5.0, 0.0, 0.0)) as Vector3
	if str(nav.call("state")) != "no_map" or int(nav.call("degraded_frames")) < 1:
		problems.append("91k nav did not report the documented degradation (state=%s)" % str(nav.call("state")))
	if dir.distance_to(Vector3.RIGHT) > 0.01:
		problems.append("91k degraded steering is not straight-line: %s" % str(dir))
	if int(NavSteering.call("degraded_frames_total")) < 1:
		problems.append("91k global degraded-frame counter did not move")
	nav_body.queue_free()
	await process_frame

	# 91l. Civilian: authored 40 HP / 60 s KO and the yelp+call-for-help chain.
	var civ_scr: GDScript = load("res://src/ai/civilian_npc.gd") as GDScript
	if absf(float(civ_scr.get_script_constant_map().get("CIVILIAN_MAX_HP", 0.0)) - 40.0) > 0.0001 \
		or absf(float(civ_scr.get_script_constant_map().get("CIVILIAN_KNOCKOUT_S", 0.0)) - 60.0) > 0.0001:
		problems.append("91l civilian HP/KO constants are not 40/60")
	var civ_arena := arena + Vector3(0.0, 0.0, 90.0)
	var floor_d: StaticBody3D = _w2_make_floor(host, civ_arena + Vector3(0.0, -0.55, 0.0))
	var civ: Node3D = civ_scr.new() as Node3D
	civ.name = "AICivilian"
	civ.call("setup", "", "", civ_arena)
	civ.position = civ_arena
	host.add_child(civ)
	var threat: CharacterBody3D = _ai_stub_player(host, civ_arena + Vector3(0.0, 0.0, -4.0))
	threat.add_to_group("player")
	await process_frame
	for _cf: int in range(40):
		await physics_frame
	var fled: bool = str(civ.call("state_name")) == "flee" or str(civ.call("state_name")) == "cower"
	if not fled:
		problems.append("91l civilian did not react to a visible thief (state=%s)" % str(civ.call("state_name")))
	if int(civ.get("yelps")) < 1:
		problems.append("91l civilian did not yelp")
	civ.call("take_knockout", 40.0)
	if str(civ.call("state_name")) != "downed":
		problems.append("91l civilian did not go down at 40 damage")
	floor_d.queue_free()
	civ.queue_free()
	threat.queue_free()
	await process_frame
	return problems


## Minimal victim for RangedAttack.deliver: records damage and the shock contract.
func _ranged_victim_stub(sink: Dictionary) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar sink: Dictionary = {}\nfunc take_damage(amount: float, _src: String = \"\") -> void:\n\tsink[\"damage\"] = amount\nfunc apply_shock(seconds: float, _mult: float) -> void:\n\tsink[\"shock\"] = seconds\n"
	script.reload()
	var node: Node = Node.new()
	node.set_script(script)
	node.set("sink", sink)
	return node


## A body that records ranged damage, so the live COMBAT case can assert the
## authored curve value rather than "something happened".
func _ai_damage_stub(host: Node, at: Vector3) -> CharacterBody3D:
	var script := GDScript.new()
	script.source_code = "extends CharacterBody3D\nvar damage_taken: float = 0.0\nvar last_source: String = \"\"\nfunc take_damage(amount: float, src: String = \"\") -> void:\n\tdamage_taken += amount\n\tlast_source = src\nfunc apply_shock(_seconds: float, _mult: float) -> void:\n\tpass\n"
	script.reload()
	var body := CharacterBody3D.new()
	body.set_script(script)
	body.name = "AIDamageStub"
	body.collision_layer = 2
	body.collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(col)
	body.position = at
	host.add_child(body)
	return body
