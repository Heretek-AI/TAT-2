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

	print("SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


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
