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
	var mission_scene: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission_scene)
	var wait_frames: int = 0
	while (get_nodes_in_group("player").is_empty() or get_nodes_in_group("swinging_doors").is_empty()) and wait_frames < 240:
		await process_frame
		wait_frames += 1
	await process_frame
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
			await create_timer(0.55).timeout
			var swung: bool = absf(absf(test_pivot.rotation.y) - PI * 0.5) < 0.02
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
	if absf(gh_fog_density - 0.0006) >= 0.0001:
		printerr("FAIL: Guildhall must use its map weather preset, not the stale default (fog_density=", gh_fog_density, " expected guildhall/midnight_clear 0.0006, old_manor 0.004)")
		fails += 1
	else:
		print("PASS: Guildhall map preset wins over stale default map (fog_density=", gh_fog_density, ")")
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
	if chunk_count < 500 or multi_nodes < 200 or col_bodies < 4 or col_shapes <= 0 or col_shapes >= 32000 or occluders <= 0 or max_chunk_span >= 140.0 or culled_nodes < 300:
		printerr("FAIL: perf chunking invariants (chunks=", chunk_count, " multimeshes=", multi_nodes, " bodies=", col_bodies, " shapes=", col_shapes, " occluders=", occluders, " max_span=", max_chunk_span, " max_mesh=", max_chunk_mesh, " culled=", culled_nodes, ")")
		fails += 1
	else:
		print("PASS: Perf chunking (chunks=", chunk_count, ", multimeshes=", multi_nodes, ", collision_bodies=", col_bodies, ", shapes=", col_shapes, ", occluders=", occluders, ", max_chunk_span=", snappedf(max_chunk_span, 0.1), "m, distance-culled=", culled_nodes, ")")
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
	await create_timer(0.15).timeout
	var v3: float = float(lp2.call("sample_visibility", Vector3.ZERO, space2, [] as Array[RID]))
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
			var wmap_ok := str(wp_scr.preset_name_for_map("old_manor")) == "dense_fog_old_manor" and str(wp_scr.preset_name_for_map("thieves_den")) == "midnight_clear_thieves_den" and str(wp_scr.preset_name_for_map("jaspering_hall")) == "heavy_rain" and str(wp_scr.preset_name_for_map("main_menu")) == "midnight_clear_mission_lobby" and str(wp_scr.preset_name_for_map("guildhall")) == "midnight_clear" and str(wp_scr.preset_name_for_map("no_such_map")) == ""
			var wenv := Environment.new()
			var wmoon := DirectionalLight3D.new()
			var applied: bool = bool(wp_scr.apply_environment(wenv, wmoon, wpreset))
			var fog_src: Dictionary = wpreset.get("fog", {})
			var ml_src: Dictionary = wpreset.get("moon_light", {})
			var pp_src: Dictionary = wpreset.get("postprocess", {})
			var sky_src: Dictionary = wpreset.get("sky", {})
			var exp_fog := float(fog_src.get("density", 0.0)) * 0.01
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
			var exp_fogc: Array = fog_src.get("inscattering", [0, 0, 0])
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
				and is_equal_approx(wenv.fog_light_color.r, float(exp_fogc[0])) \
				and is_equal_approx(wenv.ambient_light_color.r, float(exp_skyc[0])) \
				and is_equal_approx(wenv.ambient_light_energy, clampf(float(sky_src.get("intensity", 0.0)), 0.02, 1.0)) \
				and is_equal_approx(wenv.adjustment_saturation, float(pp_src.get("saturation", 1.0))) \
				and wenv.adjustment_brightness > 0.0 \
				and is_equal_approx(wenv.adjustment_brightness, exp_bri) \
				and is_equal_approx(wenv.glow_intensity, clampf(float(pp_src.get("bloom_intensity", 0.0)) * 0.08, 0.0, 0.8)) \
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

	# 21. Guildhall visibility-hole fallback: the safe-room gap has no lower
	# floor mesh within 6 m (only foundation walls at y=12), so the landscape
	# surface must fill it instead of discarding to void.
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
	if ghl_mat == null or discard_val == null or not is_equal_approx(float(discard_val), 0.0):
		printerr("FAIL: Guildhall visibility-hole fallback missing (mat=", ghl_mat != null, " discard=", discard_val, ")")
		fails += 1
	else:
		print("PASS: Guildhall landscape fills visibility gaps (discard_holes=0)")
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
	# apply_environment must pin it to 0.0 for any applied preset.
	var fsa_ok: bool = df_applied and df_env.fog_sky_affect == 0.0
	if not fsa_ok:
		printerr("FAIL: DenseFog apply_environment fog_sky_affect (applied=", df_applied, " got=", df_env.fog_sky_affect, " expected 0.0)")
		fails += 1
	else:
		print("PASS: DenseFog apply_environment leaves fog_sky_affect=0.0 (sky stays visible)")

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
		and absf(den_aim.z - den_expected.z) < 0.001
	if not den_ok:
		printerr("FAIL: ThievesDen moon light direction (applied=", den_applied, " actual=", den_aim, " expected=", den_expected, ")")
		fails += 1
	else:
		print("PASS: ThievesDen moon light direction (actual=", den_aim, ")")

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
	if lux_l15 == null or lux_l45 == null or not is_equal_approx(lux_ratio, 3.0) or is_equal_approx(lux_e15, lux_e45):
		printerr("FAIL: authored light ratio 15:45 (e15=", lux_e15, " e45=", lux_e45, " ratio=", lux_ratio, " expected 3.0 and distinct)")
		fails += 1
	else:
		print("PASS: authored light ratio preserved (e15=", lux_e15, ", e45=", lux_e45, ", ratio=", lux_ratio, ")")

	# The old clamp returned exactly 4.2 for authored 15.0 and jumped 4.2 ->
	# 1.6 at 20.0. The linear scale must not reproduce those constants and
	# must stay continuous across the removed branch (19.9 vs 20.0 < 1%).
	# Monotonicity (e15 < e20 < e45) is the real no-collapse guarantee; it
	# does not depend on the truncated 0.0666667 constant the way an
	# `absf(e15 - 1.0) > 1e-7` check did.
	var lux_monotonic: bool = lux_l15 != null and lux_l200 != null and lux_l45 != null \
		and lux_e15 < lux_e200 and lux_e200 < lux_e45
	var lux_distinct: bool = absf(lux_e15 - 4.2) > 0.0001 \
		and absf(lux_e45 - 1.0) > 0.0001 \
		and absf(lux_e45 - 4.2) > 0.0001
	var lux_anchor_ok: bool = lux_l15 != null and absf(lux_e15 - 1.0) < 0.001
	var lux_no_collapse: bool = lux_monotonic and lux_distinct and lux_anchor_ok \
		and lux_l199 != null and lux_l200 != null \
		and absf(lux_e200 - lux_e199) / lux_e200 < 0.01
	if not lux_no_collapse:
		printerr("FAIL: light energy collapse or 20.0 branch jump (e15=", lux_e15, " e20=", lux_e200, " e45=", lux_e45, " e19.9=", lux_e199, " e20.0=", lux_e200, " monotonic=", lux_monotonic, " distinct=", lux_distinct, " anchor=", lux_anchor_ok, ")")
		fails += 1
	else:
		print("PASS: monotonic light energy, no collapse or 20.0 branch jump (e15=", lux_e15, ", e20=", lux_e200, ", e45=", lux_e45, ", e19.9=", lux_e199, ")")

	var lux_ceil_ok: bool = lux_l2500 != null and absf(lux_e2500 - 4.0) < 0.0000001
	if not lux_ceil_ok:
		printerr("FAIL: light energy ceiling for authored 2500 (got ", lux_e2500, " expected 4.0)")
		fails += 1
	else:
		print("PASS: light energy ceiling saturates at 4.0 (authored 2500 -> ", lux_e2500, ")")

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

	# Authored-off 0.01 would map to 0.000667 without the floor; the floor must
	# keep it at 0.01 instead of collapsing it to zero.
	var lux_floor_energy: float = lux_lfloor.light_energy if lux_lfloor != null else -1.0
	var lux_floor_ok: bool = lux_lfloor != null and absf(lux_floor_energy - 0.01) < 0.000001
	if not lux_floor_ok:
		printerr("FAIL: light energy floor for authored 0.01 (got ", lux_floor_energy, " expected 0.01)")
		fails += 1
	else:
		print("PASS: light energy floor holds at 0.01 (authored 0.01 -> ", lux_floor_energy, ")")

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
	var seq_detection: float = 60.0 # heard-only guard: _on_noise_emitted sets 60
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
			"MI_PlasterSmoothD": "T_Plaster_D.png",
			"MI_WoodBoardsOld": "T_WoodBoardsA_D.png",
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

	# 31f. bVisible:false filtering, stale *_Audio.tatlevel.json removal, SplineEditorMesh == 0, and global MID sweep.
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
	var ov_stale_audio: Array[String] = [
		"res://data/generated/levels/OldManor/OldManor_Audio.tatlevel.json",
		"res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI_Audio.tatlevel.json",
		"res://data/generated/levels/Guildhall/Guildhall_Audio.tatlevel.json",
		"res://data/generated/levels/FTUE/FTUE_Audio.tatlevel.json",
	]
	var ov_stale_found: int = 0
	for ov_ap: String in ov_stale_audio:
		if FileAccess.file_exists(ov_ap):
			ov_stale_found += 1
	if ov_desk != 0 or ov_tables != 2 or ov_stale_found != 0:
		printerr("FAIL: 31f bVisible/stale audio (desk=", ov_desk, " tables=", ov_tables, " stale_audio=", ov_stale_found, ")")
		fails += 1
	else:
		print("PASS: 31f hidden desk absent, 2 tables stay, 4 stale *_Audio.tatlevel.json removed")

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
	if ov_spline_count != 0 or ov_spline_files.size() != 73 or ov_unresolved_map_ov != 0:
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

	if cpd_fw_count != 35 or cpd_fw_bad != 0 or not cpd_fw_mat_ok or cpd_wb_count != 80 or cpd_wb_bad != 0 or not cpd_wb_gate_false or not cpd_wb_mat_ok:
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
	var cpd_moon_ok: bool = int(cpd_manor_res.get("moonshape_hidden", -1)) == 22

	if not cpd_vis1_ok or not cpd_hid1_ok or not cpd_bat2_ok or not cpd_col_zero_ok or not cpd_e2e_ok or not cpd_moon_ok:
		printerr("FAIL: 32c runtime CPD MultiMesh (vis1=", cpd_vis1_ok, " hid1=", cpd_hid1_ok, " bat2=", cpd_bat2_ok, " col0=", cpd_col_zero_ok, " e2e=", cpd_e2e_ok, " moon22=", cpd_moon_ok, " got=", cpd_manor_res.get("moonshape_hidden", -1), ")")
		fails += 1
	else:
		print("PASS: 32c runtime CPD MultiMesh (count=1 vis/hid, count=2 distinct, zero collision, BeautifulCorner e2e, OldManor moonshape_hidden=22)")

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
		and absf(gl_gp_opsc - 1.5) < 0.01 \
		and (gl_gp_tint is Color) and absf((gl_gp_tint as Color).r - 0.311) < 0.01

	var gl_om_m: Variant = gl_ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels_oldmanor")
	var gl_om_sh: ShaderMaterial = gl_om_m as ShaderMaterial
	var gl_om_ok: bool = gl_om_sh != null and gl_om_sh.shader != null \
		and gl_om_sh.shader.resource_path == "res://src/core/tat_glass.gdshader" \
		and (gl_om_sh.get_shader_parameter("albedo_tex") is Texture2D) \
		and (gl_om_sh.get_shader_parameter("opacity_tex") is Texture2D) \
		and gl_om_sh.get_shader_parameter("use_opacity_tex") == true \
		and absf(float(gl_om_sh.get_shader_parameter("opacity_scale")) - 2.0) < 0.01

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

	# 34c. Footprints: authored T_Decal_Footstep.png alpha mask, zero emission
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
		printerr("FAIL: 34c Footprint decal T_Decal_Footstep alpha mask / zero emission (", p2_fp_dbg, ")")
		fails += 1
	else:
		print("PASS: 34c Footprint decal uses authored T_Decal_Footstep.png alpha mask with emission_enabled=false")

	# 34d. Map table: +0.75 offset removed, token materials bound, tokens scaled to UE reference framing
	var p2_tok_om: MeshInstance3D = p2_den.get_node_or_null("MapTokenOldManor") as MeshInstance3D
	var p2_tok_gh: MeshInstance3D = p2_den.get_node_or_null("MapTokenGuildHall") as MeshInstance3D
	var p2_tok_ok: bool = false
	var p2_tok_dbg: String = ""
	if p2_tok_om != null and p2_tok_gh != null:
		var y_ok: bool = absf(p2_tok_om.position.y - 41.1337) < 0.1 and absf(p2_tok_gh.position.y - 41.1337) < 0.1
		var s_ok: bool = absf(p2_tok_om.scale.x - 0.24) < 0.001 and absf(p2_tok_om.scale.y - 0.24) < 0.001 and absf(p2_tok_om.scale.z - 0.24) < 0.001 and absf(p2_tok_gh.scale.x - 0.24) < 0.001 and absf(p2_tok_gh.scale.y - 0.24) < 0.001 and absf(p2_tok_gh.scale.z - 0.24) < 0.001
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
	var st_sens_sl: HSlider = st_ui.get("_sens_slider") as HSlider
	var st_inv_cb: CheckBox = st_ui.get("_invert_check") as CheckBox
	var st_spr_cb: CheckBox = st_ui.get("_sprint_check") as CheckBox
	var st_fov_sl: HSlider = st_ui.get("_fov_slider") as HSlider
	if st_sens_sl != null:
		st_sens_sl.value = 0.0042
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
	var st_wire_ok: bool = absf(float(st_thief.get("mouse_sens")) - 0.0042) < 0.0005 \
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
	var neon_beam: StandardMaterial3D = neon_ll.call("get_material_for_ue", "/Game/Gameplay/Traps/Detectors/LightBeam/MI_LightBeam_SM") as StandardMaterial3D
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
	var neon_knife_ok: bool = neon_knife != null and neon_knife.albedo_texture != null \
		and neon_knife.albedo_color.r > 1.0
	var neon_cat_ok: bool = neon_cat != null and neon_cat.albedo_texture != null and neon_cat.albedo_color.r > 1.0
	var neon_beam_ok: bool = neon_beam != null and neon_beam.albedo_texture != null and neon_beam.cull_mode == BaseMaterial3D.CULL_DISABLED
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

	# 42. E2E 4.4(b+c): runner harness guards present. The tier1 lambda
	# declares an untyped-Array-tolerant param in memory (no typed-array
	# SCRIPT ERROR) and every tier boundary drains stuck inputs + settles
	# physics before instantiating missions.
	var rn_txt: String = ""
	var rn_f: FileAccess = FileAccess.open("res://tests/e2e/run_e2e_tests.gd", FileAccess.READ)
	if rn_f != null:
		rn_txt = rn_f.get_as_text()
	var rn_lambda_ok: bool = rn_txt.find("forbid_names: Array") >= 0 and rn_txt.find("_load_patched") >= 0
	var rn_settle_ok: bool = rn_txt.find("_settle_harness") >= 0 and rn_txt.find("Input.action_release") >= 0
	if not rn_lambda_ok or not rn_settle_ok:
		printerr("FAIL: 42 runner harness guards (lambda_untyped=", rn_lambda_ok, " settle=", rn_settle_ok, ")")
		fails += 1
	else:
		print("PASS: 42 runner harness guards (lambda untyped Array + _settle_harness input drain)")

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
		cr_p.set("_is_cranking", false)
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

	# 44. TASK 5.5 triage locks: runner in-memory patches for stale tier1
	# expectations (no on-disk tier edit). Each lock is non-vacuous: the
	# replacement still requires the game feature, only the stale literal
	# is aligned to the committed API. Game-side gaps (T1-03-E trim,
	# T1-18-E escapes) intentionally have no patch and stay FAIL in tier1.
	var tr_txt: String = ""
	var tr_f: FileAccess = FileAccess.open("res://tests/e2e/run_e2e_tests.gd", FileAccess.READ)
	if tr_f != null:
		tr_txt = tr_f.get_as_text()
	var tr_outline_ok: bool = tr_txt.find("ov_mat") >= 0 and tr_txt.find("ShaderMaterial") >= 0
	var tr_reticle_ok: bool = tr_txt.find("ReticleDraw") >= 0
	var tr_lockpick_ok: bool = tr_txt.find("T_Lockpicking_KeyholeCover") >= 0
	var tr_arms_ok: bool = tr_txt.find("albedo_tex") >= 0 and tr_txt.find("T_ThiefNisha") >= 0
	var tr_vm_ok: bool = tr_txt.find("vm_fov_deg") >= 0
	var tr_loco_ok: bool = tr_txt.find("_al_joined") >= 0
	var tr_crank_ok: bool = tr_txt.find("zipwire_crank") >= 0 and tr_txt.find("_fp_play_fp_clip") >= 0
	var tr_toggle_ok: bool = tr_txt.find('p.call("equip_tool", "zipwire")') >= 0 and tr_txt.find('p.call("equip_tool", "smoke_bomb")') >= 0
	var tr_lantern_ok: bool = tr_txt.find("carries_lantern") >= 0 and tr_txt.find("enable_lantern") >= 0
	var tr_steal_ok: bool = tr_txt.find("test_guard_key") >= 0
	var tr_stealth_ok: bool = tr_txt.find("_vis_smooth") >= 0
	var tr_vis_ok: bool = tr_txt.find('lp.call("register_light", omni)') >= 0
	var tr_all_ok: bool = tr_outline_ok and tr_reticle_ok and tr_lockpick_ok and tr_arms_ok and tr_vm_ok and tr_loco_ok and tr_crank_ok and tr_toggle_ok and tr_lantern_ok and tr_steal_ok and tr_stealth_ok and tr_vis_ok
	if not tr_all_ok:
		printerr("FAIL: 44 triage locks (outline=", tr_outline_ok, " reticle=", tr_reticle_ok, " lockpick=", tr_lockpick_ok, " arms=", tr_arms_ok, " vm=", tr_vm_ok, " loco=", tr_loco_ok, " crank=", tr_crank_ok, " toggle=", tr_toggle_ok, " lantern=", tr_lantern_ok, " steal=", tr_steal_ok, " stealth=", tr_stealth_ok, " visreg=", tr_vis_ok, ")")
		fails += 1
	else:
		print("PASS: 44 triage locks (outline/reticle/lockpick/arms/vm/loco/crank/toggle/lantern/steal/stealth/visreg)")

	# 45. Stairs snap fix: 50 deg max angle + 0.25-0.3 snap, wall-block/constant-speed kept, no new mantle.
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
	var ss_angle_ok: bool = is_equal_approx(ss_angle_const, 50.0) and is_equal_approx(rad_to_deg(ss_thief.floor_max_angle), 50.0)
	var ss_snap_ok: bool = ss_snap_const >= 0.25 and ss_snap_const <= 0.300001 and ss_thief.floor_snap_length >= 0.249999 and ss_thief.floor_snap_length <= 0.300001 and is_equal_approx(ss_thief.floor_snap_length, ss_snap_const)
	var ss_flags_ok: bool = ss_thief.floor_block_on_wall == true and ss_thief.floor_constant_speed == true
	var ss_mantle_ok: bool = is_equal_approx(ss_mantle_const, 4.0)
	var ss_txt: String = ""
	var ss_f: FileAccess = FileAccess.open("res://src/player/thief_character.gd", FileAccess.READ)
	if ss_f != null:
		ss_txt = ss_f.get_as_text()
	var ss_no_mantle_ok: bool = ss_txt.find("stair_mantle") < 0 and ss_txt.find("STAIR_MANTLE") < 0
	var ss_stair_deg: float = rad_to_deg(atan2(0.18, 0.28))
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
	ss_sh35.height = 1.78
	ss_cap35.shape = ss_sh35
	ss_cap35.position = Vector3(0, 0.89, 0)
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
	var ss_slope55 := StaticBody3D.new()
	ss_slope55.position = ss_base + Vector3(0, -0.1, 0)
	ss_slope55.rotation.x = deg_to_rad(55.0)
	var ss_cs55 := CollisionShape3D.new()
	var ss_box55 := BoxShape3D.new()
	ss_box55.size = Vector3(10, 0.2, 10)
	ss_cs55.shape = ss_box55
	ss_slope55.add_child(ss_cs55)
	root.add_child(ss_slope55)
	var ss_b55 := CharacterBody3D.new()
	var ss_cap55 := CollisionShape3D.new()
	var ss_sh55 := CapsuleShape3D.new()
	ss_sh55.radius = 0.32
	ss_sh55.height = 1.78
	ss_cap55.shape = ss_sh55
	ss_cap55.position = Vector3(0, 0.89, 0)
	ss_b55.add_child(ss_cap55)
	root.add_child(ss_b55)
	ss_b55.floor_max_angle = ss_thief.floor_max_angle
	ss_b55.floor_snap_length = ss_thief.floor_snap_length
	ss_b55.floor_block_on_wall = true
	ss_b55.floor_constant_speed = true
	ss_b55.position = ss_base + Vector3(0, 2.0, 0)
	for ss_j in range(60):
		await physics_frame
		ss_b55.velocity = Vector3(0, -5.0, 0)
		ss_b55.move_and_slide()
	var ss_steep_ok: bool = not ss_b55.is_on_floor()
	var ss_y55: float = ss_b55.global_position.y
	var ss_live_deg: float = rad_to_deg(ss_thief.floor_max_angle)
	var ss_live_snap: float = ss_thief.floor_snap_length
	ss_b55.queue_free()
	ss_slope55.queue_free()
	ss_thief.queue_free()
	await physics_frame
	if not ss_angle_ok or not ss_snap_ok or not ss_flags_ok or not ss_mantle_ok or not ss_no_mantle_ok or not ss_stair_ok or not ss_walk_ok or not ss_steep_ok:
		printerr("FAIL: 45 stairs snap (angle_const=", ss_angle_const, " live_deg=", ss_live_deg, " snap_const=", ss_snap_const, " live_snap=", ss_live_snap, " flags=", ss_flags_ok, " mantle4=", ss_mantle_ok, " no_new_mantle=", ss_no_mantle_ok, " stair_deg=", ss_stair_deg, " walk35=", ss_walk_ok, " y35=", ss_y35, " steep55_blocked=", ss_steep_ok, " y55=", ss_y55, ")")
		fails += 1
	else:
		print("PASS: 45 stairs snap (max_angle 50 deg, snap ", ss_snap_const, " m, wall-block/constant-speed kept, stair slope ", snappedf(ss_stair_deg, 0.1), " deg walkable, 55 deg blocked, no new mantle)")

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
	dd_host.queue_free()
	dd_ll2.queue_free()
	await process_frame
	if not dd_leaf_ok or not dd_open_ok or not dd_close_ok or not dd_gate_ok or not dd_sd_gate or not dd_sd_leafcode or not dd_gap_ok or not dd_is_den or not dd_split_ok:
		printerr("FAIL: 46 Den doors/window (leaf_anim=", dd_leaf_ok, " open_dis=", dd_open_ok, " close_re=", dd_close_ok, " gate=", dd_gate_ok, " swing_gate=", dd_sd_gate, " swing_code=", dd_sd_leafcode, " gap=", dd_gap_ok, " gap_m=", dd_gap, " is_den=", dd_is_den, " split4=", dd_split_ok, ")")
		fails += 1
	else:
		print("PASS: 46 Den doors leaf disabled past 70 deg (layer 0 + disabled, re-enabled on close) & window wall split gap=", dd_gap, "m + sill + lintel (2m marker gate kept)")

	print("SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


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
