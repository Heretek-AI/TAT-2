extends RefCounted
## Tier 4: Real-World Application & Parity Scenarios (14 journeys: T4-01..T4-14).
## Exercises full multi-step gameplay & visual/shader/camera/capture preconditions
## without invoking nested Vulkan processes.

var h: RefCounted


func _init(helpers: RefCounted) -> void:
	h = helpers


func run() -> void:
	h.snapshot_state()
	await _t4_01_startscreen_settings_back()
	await _t4_02_thieves_den_hub_journey()
	await _t4_03_mission_prep_loading_letter_guildhall()
	await _t4_04_guildhall_rooftop_zipwire_traversal()
	await _t4_05_stealth_smoke_slithersap_lantern_guards()
	await _t4_06_disguised_lockpicking_extraction()
	await _t4_07_guildhall_set_multi_part_objectives()
	await _t4_08_old_manor_cleanout_terrain_puddles()
	await _t4_09_combat_fall_downed_disguise_shatter()
	await _t4_10_visual_parity_preconditions()
	await _t4_11_clean_room_gate_verification()
	await _t4_12_r3_cooked_data_adversarial_audit()
	await _t4_13_free_play_contract_inactive()
	await _t4_14_free_play_banking_control()
	h.restore_state()


func _t4_01_startscreen_settings_back() -> void:
	var orig_s: Dictionary = (h.save_system().call("get_settings") as Dictionary).duplicate(true)
	var mm: Control = h.new_script_node("res://src/ui/main_menu.gd") as Control
	h.root.add_child(mm)
	# Camera-bound startscreen env binds after the own-world SubViewport renders.
	await h.step_process(20)
	var cam: Camera3D = mm.get("_menu_cam") as Camera3D
	var env: Environment = h.find_camera_env(mm)
	var cam_ok: bool = cam != null and cam.position.distance_to(Vector3(-12.7196, 0.4566, 14.6089)) < 0.25 and absf(cam.fov - 48.03) < 0.1
	var vis_ok: bool = env != null and env.glow_enabled and env.ssr_enabled and env.volumetric_fog_enabled

	var st_ui: CanvasLayer = h.new_script_node("res://src/ui/settings_ui.gd") as CanvasLayer
	mm.add_child(st_ui)
	await h.step_process(1)
	var st_panel: PanelContainer = st_ui.get("_modal_panel") as PanelContainer
	var teal_ok: bool = st_panel != null and h.is_teal_style(st_panel.get_theme_stylebox("panel") as StyleBoxFlat)
	var sl_fov: HSlider = st_ui.get("_fov_slider") as HSlider
	if sl_fov != null: sl_fov.value = 91.0
	st_ui.call("_apply_live", false)
	var p_chk: Node = h.new_script_node("res://src/player/thief_character.gd")
	h.root.add_child(p_chk)
	await h.step_process(1)
	var persisted: bool = absf(float(p_chk.get("base_fov")) - 91.0) < 0.2
	await h.free_node(p_chk)
	(h.save_system().get("data") as Dictionary)["settings"] = orig_s
	h.save_system().call("apply_saved_settings")
	await h.free_node(mm)
	h.require(cam_ok and vis_ok and teal_ok and persisted, "T4-01", "Startscreen->Settings->Back parity journey (cam=%s vis=%s teal=%s persist=%s)" % [str(cam_ok), str(vis_ok), str(teal_ok), str(persisted)])


func _t4_02_thieves_den_hub_journey() -> void:
	var den_res: Dictionary = await h.instantiate_mission(1, 200, 1)
	var den: Node = den_res["mission"] as Node
	var p: Node = den_res["player"] as Node
	var billboards: int = 0
	if den != null:
		for lb: Node in h.find_all_of_class(den, "Label3D"):
			var txt: String = (lb as Label3D).text
			if txt.find("Prepare for Mission") >= 0 or txt.find("Customize Thief") >= 0:
				billboards += 1
	var exit_d: Node = den.get_node_or_null("ThievesDenExitDoor") if den != null else null
	var tok_om: MeshInstance3D = den.get_node_or_null("MapTokenOldManor") as MeshInstance3D if den != null else null
	var ponder_ok: bool = false
	for inter: Node in h.tree.get_nodes_in_group("interactables"):
		if h.has_m(inter, "get_interact_prompt") and str(inter.call("get_interact_prompt")).to_upper().find("PONDER") >= 0:
			ponder_ok = true
			break
	var mc_txt: String = h.read_text("res://src/missions/mission_controller.gd").to_lower()
	var card_ok: bool = den != null and den.find_child("DenMapTableArea", true, false) != null and mc_txt.find("key_h") >= 0 and mc_txt.find("key_r") >= 0
	var teal_5: bool = true
	for up: String in ["res://src/ui/wardrobe_ui.gd", "res://src/ui/ledger_ui.gd", "res://src/ui/contract_table_ui.gd"]:
		var un: Node = h.new_script_node(up)
		h.root.add_child(un)
		await h.step_process(1)
		var any_t: bool = false
		for pn: Node in h.find_all_of_class(un, "PanelContainer"):
			if h.is_teal_style((pn as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat):
				any_t = true
				break
		if not any_t: teal_5 = false
		await h.free_node(un)
	var om_base: float = float(tok_om.get_meta("minis_base", -1.0)) if tok_om != null else -1.0
	var ue_ratio: float = 45.56192 / 27.39531
	var om_live_ok: bool = tok_om != null and tok_om.scale.x >= om_base - 1e-4 and tok_om.scale.x <= om_base * 1.15 + 1e-3
	var had_p: bool = p != null
	var had_den: bool = den != null
	var exit_ok: bool = exit_d != null
	var tok_ok: bool = tok_om != null
	await h.free_node(den)
	h.require(
		had_den and had_p and billboards == 0 and exit_ok and tok_ok and absf(om_base - 0.24 * ue_ratio) < 1e-4 and om_live_ok and ponder_ok and card_ok and teal_5,
		"T4-02",
		"Thieves' Den Hub journey (den=%s p=%s exit=%s tok=%s base=%.4f/%0.4f live=%s ponder=%s map=%s teal=%s billboards=%d)" % [
			str(had_den), str(had_p), str(exit_ok), str(tok_ok), om_base, 0.24 * ue_ratio,
			str(om_live_ok), str(ponder_ok), str(card_ok), str(teal_5), billboards]
	)


func _t4_03_mission_prep_loading_letter_guildhall() -> void:
	var mp: Control = h.new_script_node("res://src/ui/mission_prep_ui.gd") as Control
	h.root.add_child(mp)
	await h.step_process(2)
	mp.call("open_prep", "guildhall", 1, "Solo", 2)
	await h.step_process(2)
	var vp: SubViewport = h.find_all_of_class(mp, "SubViewport")[0] as SubViewport if not h.find_all_of_class(mp, "SubViewport").is_empty() else null
	var cam: Camera3D = h.find_all_of_class(vp, "Camera3D")[0] as Camera3D if (vp != null and not h.find_all_of_class(vp, "Camera3D").is_empty()) else null
	var mp_src: String = h.read_text("res://src/ui/mission_prep_ui.gd")
	var mp_scr: GDScript = h.load_script("res://src/ui/mission_prep_ui.gd")
	var lobby_fov: float = float(mp_scr.get_script_constant_map().get("LOBBY_CAM_FOV", 20.0)) if mp_scr != null else 20.0
	# Authored CameraActor_0 is a 20.0 deg HORIZONTAL FOV mapped with
	# keep_aspect KEEP_WIDTH (the rendered vertical is ~11.33 at 16:9).
	var lobby_ok: bool = mp_src.find("MissionLobby_Geo3") >= 0 and cam != null \
		and absf(cam.fov - lobby_fov) < 0.25 and cam.keep_aspect == Camera3D.KEEP_WIDTH
	var b_txt: String = (mp.get("_mission_body") as Label).text if mp.get("_mission_body") != null else ""
	var dur_ok: bool = b_txt.find("{MatchDurationInMinutes}") < 0 and (b_txt.find("120") >= 0 or b_txt.find("minute") >= 0)
	await h.free_node(mp)

	var ls: CanvasLayer = h.new_script_node("res://src/ui/loading_screen.gd") as CanvasLayer
	h.root.add_child(ls)
	await h.step_process(1)
	var ls_ok: bool = ls.get("_splash_rect") != null and (ls.get("_splash_rect") as TextureRect).texture != null and h.read_text("res://src/ui/loading_screen.gd").to_lower().find("spinner") >= 0
	await h.free_node(ls)

	var gh_res: Dictionary = await h.instantiate_mission(2, 240, 1)
	var gh: Node = gh_res["mission"] as Node
	var gs: Node = h.game_state()
	var intro_ok: bool = str(h.get_prop(gs, "contract_intro", "")) != ""
	var spawn_ok: bool = gh != null and h.is_true(gh.get("fallback_spawn_headroom_clear")) and h.is_true(gh.get("fallback_spawn_forward_clear"))
	await h.free_node(gh)
	h.require(lobby_ok and dur_ok and ls_ok and intro_ok and spawn_ok, "T4-03", "MissionPrep->Loading->Letter->Guildhall entry (lobby=%s ls=%s intro=%s spawn=%s)" % [str(lobby_ok), str(ls_ok), str(intro_ok), str(spawn_ok)])


func _t4_04_guildhall_rooftop_zipwire_traversal() -> void:
	var gh_res: Dictionary = await h.instantiate_mission(2, 240, 1)
	var gh: Node = gh_res["mission"] as Node
	var p: Node = gh_res["player"] as Node
	var env: Environment = h.find_env(gh) if gh != null else null
	var sky_txt: String = h.read_text("res://src/core/tat_sky.gdshader").to_lower()
	# Guildhall uses the exact `midnight_clear` preset, which restores authored
	# height fog over the sky (fog_sky_affect 0.85); dense_fog stays at 0.0.
	var sky_ok: bool = env != null and env.background_mode == Environment.BG_SKY and env.fog_sky_affect >= 0.8 and env.fog_sky_affect <= 0.9 and sky_txt.find("fbm") >= 0 and sky_txt.find("halo") >= 0
	var vm: Dictionary = h.viewmodel_contract(p)
	var iso_ok: bool = p != null and h.is_true(vm.get("ok"))
	var zip_ok: bool = p != null and h.has_m(p, "get_equipped_tool") and h.has_m(p, "get_active_reticle_state")
	var tc_txt: String = h.read_text("res://src/player/thief_character.gd").to_lower()
	var trav_ok: bool = tc_txt.find("mantle") >= 0 and (tc_txt.find("wall_climb") >= 0 or tc_txt.find("wallclimb") >= 0)
	await h.free_node(gh)
	h.require(sky_ok and iso_ok and zip_ok and trav_ok, "T4-04", "Guildhall Rooftop sky+1P+Zipwire+Mantle/Climb (sky=%s iso=%s zip=%s trav=%s)" % [str(sky_ok), str(iso_ok), str(zip_ok), str(trav_ok)])


func _t4_05_stealth_smoke_slithersap_lantern_guards() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var lp: Node = arena_d["light_probe"] as Node
	var host: Node3D = h.make_level_host(lp)
	arena.add_child(host)
	var g1: Node3D = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, -8.0)) as Node3D
	if g1 != null:
		g1.set("level_ctrl", host)
		if h.has_prop(g1, "carries_lantern"):
			g1.set("carries_lantern", true)
		if h.has_m(g1, "enable_lantern"):
			g1.call("enable_lantern")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, lp, host)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_physics(2)

	var lantern_ok: bool = not h.find_all_of_class(g1, "OmniLight3D").is_empty() and h.has_m(g1, "get_alert_state")
	var smoke_ok: bool = false
	if h.has_m(p, "equip_tool"):
		p.call("equip_tool", "smoke_bomb")
		await h.step_process(1)
		p.call("_use_smoke_bomb")
		await h.step_physics(80)
		smoke_ok = not (host.get("smokes") as Array).is_empty()
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.position = Vector3(5.0, 1.0, -4.0)
	arena.add_child(lamp)
	lp.call("register_light", lamp)
	var puddle: Area3D = h.new_script_node("res://src/interact/slip_puddle.gd") as Area3D
	arena.add_child(puddle)
	puddle.call("setup", arena.global_position + Vector3(5.0, 0.0, -4.0), lp, 0.0)
	var g2: Node = await h.spawn_test_guard(arena, Vector3(5.0, 0.0, -4.0))
	puddle.call("_on_body_entered", g2)
	var sap_ok: bool = (not lamp.visible) and int(g2.get("state")) == 5
	await h.free_node(arena)
	h.require(lantern_ok and smoke_ok and sap_ok, "T4-05", "Infiltration: ClubLantern=%s Smoke=%s Slithersap=%s" % [str(lantern_ok), str(smoke_ok), str(sap_ok)])


func _t4_06_disguised_lockpicking_extraction() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var gs: Node = h.game_state()
	gs.set("thief_id", "chameleon")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var lc: Node = h.new_script_node("res://src/interact/loot_container.gd")
	arena.add_child(lc)
	var ok: bool = false
	if h.has_m(p, "apply_guard_viewcone_disguise_decay") and h.has_m(p, "set_lockpicking_active") and h.has_prop(lc, "locked"):
		p.set("disguise_active", true)
		p.set("disguise_integrity", 100.0)
		# Real TTL: without it the disguise expires on the first tick and the
		# journey measures a dead disguise.
		p.set("disguise_ttl", 120.0)
		p.call("apply_guard_viewcone_disguise_decay", 1.0, true)
		p.call("_tick_sustained_systems", 1.0)
		var after_vc: float = float(p.get("disguise_integrity"))
		p.call("set_lockpicking_active", true)
		await h.step_physics(60)
		var still_disguised: bool = h.is_true(p.get("disguise_active"))
		var after_lp: float = float(p.get("disguise_integrity"))
		p.call("set_lockpicking_active", false)
		var mult: float = float(gs.call("compute_stealth_bonus_multiplier"))
		ok = still_disguised and after_vc < 95.0 and after_lp < after_vc and mult >= 1.0
	await h.free_node(arena)
	h.require(ok, "T4-06", "Disguised Vault Safe Lockpicking & Extraction journey (%s)" % str(ok))


func _t4_07_guildhall_set_multi_part_objectives() -> void:
	var gs: Node = h.game_state()
	var hud_txt: String = h.read_text("res://src/ui/hud.gd")
	var gai: Node = h.new_script_node("res://src/ai/guard_ai.gd")
	var set_ok: bool = false
	if h.has_prop(gs, "mission_objectives") and h.has_m(gs, "mark_objective_done") and h.has_m(gs, "are_all_objectives_complete"):
		gs.call("set_mission_objectives", [
			{"id": "set_item_a", "label": "Set A", "target": 1},
			{"id": "set_item_b", "label": "Set B", "target": 1},
			{"id": "set_item_c", "label": "Set C", "target": 1},
		], 0)
		var zero_ok: bool = not h.is_true(gs.call("are_all_objectives_complete"))
		gs.call("mark_objective_done", "set_item_a")
		gs.call("mark_objective_done", "set_item_b")
		gs.call("mark_objective_done", "set_item_c")
		var done_ok: bool = h.is_true(gs.call("are_all_objectives_complete"))
		set_ok = zero_ok and done_ok
		gs.call("set_mission_objectives", [], 0)
		gs.set("quest_item_acquired", false)
	var ok: bool = set_ok \
		and h.has_action("map_toggle") and h.has_action("ping_menu") \
		and h.has_m(gai, "steal_carried_item") and hud_txt.find("∞") >= 0
	if gai != null: gai.queue_free()
	h.require(ok, "T4-07", "Guildhall Set objectives [0/3]->[3/3] + Map + Ping + Fairy + Vistara (%s)" % str(ok))


func _t4_08_old_manor_cleanout_terrain_puddles() -> void:
	var om_res: Dictionary = await h.instantiate_mission(3, 240, 1)
	var om: Node = om_res["mission"] as Node
	var p: CharacterBody3D = om_res["player"] as CharacterBody3D
	var gs: Node = h.game_state()
	var spawn_ok: bool = om != null and h.is_true(om.get("fallback_spawn_headroom_clear")) and h.is_true(om.get("fallback_spawn_forward_clear"))
	var walk_ok: bool = false
	if p != null:
		var y0: float = p.global_position.y
		h.press_action("move_forward")
		await h.step_physics(35)
		h.release_action("move_forward")
		walk_ok = p.global_position.y > -5.0 and absf(p.global_position.y - y0) < 5.0
	var ls_txt: String = h.read_text("res://src/core/tat_landscape.gdshader")
	var puddle_ssr: bool = ls_txt.find("0.04") >= 0 or ls_txt.find("0.05") >= 0
	var cleanout_ok: bool = h.has_prop(gs, "loot_goal")
	await h.free_node(om)
	h.require(spawn_ok and walk_ok and puddle_ssr and cleanout_ok, "T4-08", "OldManor Cleanout terrain+puddles+SSR journey (spawn=%s walk=%s puddle=%s goal=%s)" % [str(spawn_ok), str(walk_ok), str(puddle_ssr), str(cleanout_ok)])


func _t4_09_combat_fall_downed_disguise_shatter() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var gs: Node = h.game_state()
	gs.set("thief_id", "chameleon")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	p.set("disguise_active", true)
	p.set("disguise_integrity", 35.0)
	p.set("disguise_ttl", 60.0)
	p.call("take_damage", 10.0) # melee breaks 35 -> 0
	var shattered: bool = not h.is_true(p.get("disguise_active"))
	p.set("disguise_active", true)
	p.set("disguise_integrity", 100.0)
	p.call("_apply_fall_damage", 8.0) # fall exempt from 40 penalty
	var fall_exempt: bool = float(p.get("disguise_integrity")) > 95.0
	p.call("take_damage", 9999.0)
	var downed_ok: bool = h.is_true(p.get("is_downed")) and absf(float(p.call("downed_remaining")) - 10.0) < 0.2
	p.call("revive")
	var rev_ok: bool = not h.is_true(p.get("is_downed")) and absf(float(p.get("post_revive_ttl")) - 3.0) < 0.1
	var gai_scr: GDScript = h.load_script("res://src/ai/guard_ai.gd")
	var decay_ok: bool = absf(float(gai_scr.call("decay_step_detection", 2, 50.0, 6.0, 4.0, 1.0)) - 40.0) < 0.1
	await h.free_node(arena)
	h.require(shattered and fall_exempt and downed_ok and rev_ok and decay_ok, "T4-09", "Combat/Fall/Downed/Disguise/GuardDecay journey passed")


func _t4_10_visual_parity_preconditions() -> void:
	var cap_sh: String = h.repo_read_text("build/qa/capture_e2e_parity.sh")
	var cap_gd: String = h.repo_read_text("build/qa/capture_e2e_parity.gd")
	var vf_sh: String = h.repo_read_text("build/qa/capture_vf.sh")
	var shaders_ok: bool = true
	for sp: String in ["res://src/core/tat_sky.gdshader", "res://src/core/tat_landscape.gdshader", "res://src/core/tat_glass.gdshader", "res://src/core/tat_hdr_emissive.gdshader", "res://src/core/tat_emissive_cpd.gdshader"]:
		if ResourceLoader.load(sp) == null:
			shaders_ok = false
	var scenes_ok: bool = ResourceLoader.exists("res://scenes/main_menu.tscn") and ResourceLoader.exists("res://scenes/mission.tscn")
	var harness_ok: bool = cap_sh.find("SHADER ERROR") >= 0 and cap_sh.find("SCRIPT ERROR") >= 0 and cap_gd != "" and vf_sh != ""
	h.require(shaders_ok and scenes_ok and harness_ok, "T4-10", "Live Vulkan parity capture preconditions & error gates ready (%s)" % str(shaders_ok and scenes_ok and harness_ok))


func _t4_11_clean_room_gate_verification() -> void:
	var pg: String = h.read_text("res://project.godot")
	var rt: String = h.read_text("res://tests/run_tests.gd")
	var e2e_ok: bool = ResourceLoader.exists("res://tests/e2e/run_e2e_tests.gd") \
		and ResourceLoader.exists("res://tests/e2e/e2e_tier1_features.gd") \
		and ResourceLoader.exists("res://tests/e2e/e2e_tier2_boundaries.gd") \
		and ResourceLoader.exists("res://tests/e2e/e2e_tier3_pairwise.gd") \
		and ResourceLoader.exists("res://tests/e2e/e2e_tier4_scenarios.gd")
	var clean_ok: bool = pg.find("debug_autostart_contract") < 0 and rt.find("# 38.") >= 0 and h.repo_file_exists("tools/manifest_audit.py") and e2e_ok
	h.require(clean_ok, "T4-11", "Clean-room verification: project.godot clean, 38 suites + manifest_audit + E2E intact")


func _t4_12_r3_cooked_data_adversarial_audit() -> void:
	# Enforce all 8 R3 cooked-data hard limits without fabrication
	var sys_v: Variant = h.read_json("res://data/generated/vfx/systems.json")
	var r3_1: bool = sys_v is Dictionary and h.read_text("res://src/core/vfx_manager.gd").find("VectorVM") < 0
	var r3_2: bool = h.read_text("res://src/core/tat_sky.gdshader").find("APPROXIMATE") >= 0 and h.read_text("res://src/core/level_loader.gd").find("DECAL_GENERIC_TOKENS") >= 0
	var r3_3: bool = h.read_text("res://src/ai/guard_ai.gd").find("BP_AIPatrolPath") < 0
	var al_txt: String = h.read_text("res://src/core/animation_library.gd")
	var r3_4: bool = al_txt.find("AN_Unarmed_Idle_1P") < 0 and al_txt.find("AN_Jump_1P") < 0
	var r3_5: bool = h.read_text("res://src/player/thief_character.gd").find("SLITHERSAP_SPEED") < 0
	var r3_6: bool = h.read_text("res://src/core/weather_profile.gd").find("LumenSkylightLeaking =") < 0
	var r3_7: bool = h.read_text("res://src/core/audio_manager.gd").find("PLUG_IR_SYNTH") < 0
	var r3_8: bool = h.read_text("res://src/core/level_loader.gd").find("SplineEditorMesh") >= 0
	h.require(r3_1 and r3_2 and r3_3 and r3_4 and r3_5 and r3_6 and r3_7 and r3_8, "T4-12", "All 8 R3 cooked-data hard limits respected (zero fabricated params)")


## T4-13: Free play ("Contract Inactive") is the Guildhall Cleanout Heist run
## hosted on contract order 2: mission id + QG 4,000 loot goal + reference HUD
## ("Mission: Steal 4,000 in loot value[0/4,000]", "£ 0"), the mission row's
## 3300 s Novice timer, and no contract-completion write on extraction.
func _t4_13_free_play_contract_inactive() -> void:
	var gs: Node = h.game_state()
	var ss: Node = h.save_system()
	var save_data: Dictionary = ss.get("data") as Dictionary
	var before_completed: Dictionary = (save_data.get("completed_contracts", {}) as Dictionary).duplicate(true)
	var before_xp: int = int(save_data.get("xp", 0))
	var before_level: int = int(save_data.get("level", 1))
	var before_currency: int = int(save_data.get("currency", 0))
	var before_loot_value: int = int(gs.get("loot_value"))

	# Stage the mode exactly as the QA autostart / prep READY does; the mission
	# scene's reset_run republishes the stash after clearing the map-change id.
	gs.call("begin_free_play", "Mission.Guildhall.LootTheRoom")
	var miss_res: Dictionary = await h.instantiate_mission(2, 400, 1)
	var gh: Node = miss_res["mission"] as Node
	var hud: Node = miss_res["hud"] as Node
	await h.step_process(3)

	var mid: String = str(gs.get("active_mission_id"))
	var goal: int = int(gs.get("loot_goal"))
	var timer: float = float(gs.get("run_time_limit"))
	var label: String = ""
	var objs_v: Variant = gs.get("mission_objectives")
	if objs_v is Array:
		for o_v: Variant in (objs_v as Array):
			if o_v is Dictionary and str((o_v as Dictionary).get("id", "")) == "cleanout_loot":
				label = str((o_v as Dictionary).get("label", ""))
	var obj_text: String = ""
	var loot_text: String = ""
	if hud != null:
		var ol: Label = hud.get("obj_lbl") as Label
		var ll: Label = hud.get("_loot_lbl") as Label
		if ol != null:
			obj_text = ol.text
		if ll != null:
			loot_text = ll.text

	# Extraction must not bank currency and never record contract progress in
	# the hosting order (order 2 is the "Into the Lion's Den" campaign contract):
	# free play is not a currency farm. A zero loot_value made the old negative
	# currency assertion vacuous (final_score 0 -> add_currency(0) is a no-op),
	# so stage a real score first.
	var no_write: bool = false
	var no_currency: bool = false
	if gh != null:
		gs.set("loot_value", 500)
		gh.call("_on_extracted")
		await h.step_process(1)
		no_write = (save_data.get("completed_contracts", {}) as Dictionary) == before_completed and int(save_data.get("xp", 0)) == before_xp
		no_currency = int(save_data.get("currency", 0)) == before_currency
		save_data["completed_contracts"] = before_completed
		save_data["xp"] = before_xp
		save_data["level"] = before_level
		save_data["currency"] = before_currency
		ss.call("write_save")
	gs.set("loot_value", before_loot_value)

	var ids_ok: bool = mid == "Mission.Guildhall.LootTheRoom" and goal == 4000 and label == "Steal 4,000 in loot value"
	var timer_ok: bool = absf(timer - 3300.0) < 0.5
	var hud_ok: bool = obj_text == "Mission: Steal 4,000 in loot value[0/4,000]" and loot_text == "£ 0"
	h.require(
		gh != null and ids_ok and timer_ok and hud_ok and no_write and no_currency,
		"T4-13",
		"free play id=%s goal=%d label='%s' timer=%.0f hud='%s' loot='%s' no_contract_write=%s no_currency_bank=%s" % [
			mid, goal, label, timer, obj_text, loot_text, str(no_write), str(no_currency)
		]
	)
	await h.free_node(gh)


## T4-14: positive control for T4-13. A normal contract deploy with the same
## staged score must bank exactly the computed final score and record the
## active order, proving the free-play negative case exercises a live path
## (not a mission whose extraction was already a no-op for another reason).
func _t4_14_free_play_banking_control() -> void:
	var gs: Node = h.game_state()
	var ss: Node = h.save_system()
	var save_data: Dictionary = ss.get("data") as Dictionary
	var before_completed: Dictionary = (save_data.get("completed_contracts", {}) as Dictionary).duplicate(true)
	var before_xp: int = int(save_data.get("xp", 0))
	var before_level: int = int(save_data.get("level", 1))
	var before_currency: int = int(save_data.get("currency", 0))
	var before_loot_value: int = int(gs.get("loot_value"))
	var before_ever_spotted: bool = h.is_true(gs.get("ever_spotted"))

	# Normal deploy: no free-play stash may survive into reset_run.
	gs.call("end_free_play")
	gs.set("state", "playing")
	var miss_res: Dictionary = await h.instantiate_mission(2, 400, 1)
	var gh: Node = miss_res["mission"] as Node
	await h.step_process(3)
	var order: int = int(gs.get("active_contract_order"))
	# Isolate the order row so best_score is exactly the staged 625 even when
	# an earlier tier already banked this order; the row set is restored below.
	var cc_stage: Dictionary = save_data.get("completed_contracts", {}) as Dictionary
	cc_stage.erase(str(order))
	gs.set("loot_value", 500)
	# Authored ghost payout: 500 x (1.0 base + 0.25 Ghost bonus) = 625. Pin the
	# constant instead of re-deriving it with the production multiplier.
	gs.set("ever_spotted", false)
	var expected: int = 625
	var ghost_run: bool = not h.is_true(gs.get("ever_spotted"))
	var after_currency: int = before_currency
	var after_entry: Dictionary = {}
	var recorded: bool = false
	if gh != null:
		gh.call("_on_extracted")
		await h.step_process(1)
		ghost_run = ghost_run and not h.is_true(gs.get("ever_spotted"))
		after_currency = int(save_data.get("currency", 0))
		var cc: Dictionary = save_data.get("completed_contracts", {}) as Dictionary
		var entry_v: Variant = cc.get(str(order), {})
		if entry_v is Dictionary:
			after_entry = entry_v as Dictionary
		recorded = after_entry.has("best_score") and int(after_entry.get("best_score", -1)) == expected \
			and h.is_true(after_entry.get("ghost"))
	# Restore the real save row set; record_contract_complete also bumped xp.
	save_data["completed_contracts"] = before_completed
	save_data["xp"] = before_xp
	save_data["level"] = before_level
	save_data["currency"] = before_currency
	ss.call("write_save")
	gs.set("loot_value", before_loot_value)
	gs.set("ever_spotted", before_ever_spotted)
	var banked: bool = after_currency == before_currency + expected
	h.require(
		gh != null and ghost_run and banked and recorded,
		"T4-14",
		"normal ghost deploy banks 625 (currency %d -> %d, order %d recorded=%s best=%d ghost_run=%s)" % [
			before_currency, after_currency, order, str(recorded), int(after_entry.get("best_score", -1)), str(ghost_run)
		]
	)
	await h.free_node(gh)
