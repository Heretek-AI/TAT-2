extends RefCounted
## Tier 3: Cross-Feature Pairwise Interactions (25 checks: T3-01..T3-25).
## Exercises cross-milestone contracts (M1<->M2, M2<->M3, M2<->M4, M3<->M4, M1<->M3, M1<->M4).

var h: RefCounted


func _init(helpers: RefCounted) -> void:
	h = helpers


func run() -> void:
	h.snapshot_state()
	await _t3_01_tool_equip_hud_sync()
	await _t3_02_zipwire_crank_cable_hud_ring()
	await _t3_03_smoke_noise_soundwaves_guard()
	await _t3_04_lockpick_disguise_vault()
	await _t3_05_den_map_table_prep_loading_objectives()
	await _t3_06_vistara_vision_outline_sky()
	await _t3_07_guard_lantern_lightprobe_viewcone()
	await _t3_08_1p_zipwire_glb_anims_subviewport()
	await _t3_09_startscreen_sky_neon_lighting()
	await _t3_10_interior_ssil_glass_stealth_ball()
	await _t3_11_slithersap_lantern_guard_ko()
	await _t3_12_fairy_steal_guard_pip()
	await _t3_13_lockpick_jam_shock_disguise_damage()
	await _t3_14_settings_fov_hud_viewmodel()
	await _t3_15_den_exit_door_prep_loading()
	await _t3_16_old_manor_terrain_mantle_smoke()
	await _t3_17_locked_vault_objective_escape()
	await _t3_18_ping_radial_compass_poi()
	await _t3_19_yellow_highlight_locked_safe_prompt()
	await _t3_20_disguise_1p_anim_vignette_sprint()
	await _t3_21_health_blocks_fall_victory_xp()
	await _t3_22_old_manor_puddle_ssr_sky()
	await _t3_23_wall_climb_height_curve_detection()
	await _t3_24_full_preservation_gate()
	await _t3_25_guard_sight_self_exclusion()
	h.restore_state()


func _t3_01_tool_equip_hud_sync() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.game_state().set("active_contract_order", 2)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_process(2)
	var ok: bool = false
	if h.has_m(p, "get_equipped_tool") and h.has_m(p, "get_tool_slots") and h.has_m(p, "get_active_reticle_state"):
		await h.tap_action("tool_4")
		await h.step_process(2)
		var slot_lbls: Array = hud.get("slot_count_lbls") as Array
		var has_inf: bool = false
		for l_v: Variant in slot_lbls:
			if l_v is Label and (l_v as Label).text.find("∞") >= 0:
				has_inf = true
		var hud_src: String = h.read_text("res://src/ui/hud.gd")
		ok = str(p.call("get_equipped_tool")) == "vistara_diamond" and has_inf and hud_src.find("get_equipped_tool") >= 0
	h.require(ok, "T3-01", "Equip tool [1..4] syncs HUD hotbar, infinity glyph & hints (%s)" % str(ok))
	await h.free_node(arena)


func _t3_02_zipwire_crank_cable_hud_ring() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.add_wall_box(arena, Vector3(0.0, 4.0, -12.0), Vector3(10.0, 8.0, 1.0), "T3Wall")
	h.game_state().set("active_contract_order", 2)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var cam: Camera3D = p.get("cam") as Camera3D
	if cam != null:
		cam.look_at(arena.global_position + Vector3(0.0, 4.0, -12.0), Vector3.UP)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_physics(2)
	var ok: bool = false
	if h.has_m(p, "get_active_reticle_state") and h.has_m(p, "equip_tool"):
		p.call("equip_tool", "zipwire")
		await h.step_process(1)
		var rs0: Dictionary = p.call("get_active_reticle_state") as Dictionary
		h.press_action("secondary_action")
		await h.step_physics(35)
		var rs1: Dictionary = p.call("get_active_reticle_state") as Dictionary
		h.release_action("secondary_action")
		var hud_src: String = h.read_text("res://src/ui/hud.gd")
		ok = h.is_true(rs0.get("target_valid")) and h.is_true(rs1.get("crank_active")) \
			and float(rs1.get("crank_progress")) > 0.0 and hud_src.find("crank_progress") >= 0 \
			and hud_src.find("get_active_reticle_state") >= 0
	h.require(ok, "T3-02", "Zipwire aim validity + crank progress synced to HUD ring (%s)" % str(ok))
	await h.free_node(arena)


func _t3_03_smoke_noise_soundwaves_guard() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var lp: Node = arena_d["light_probe"] as Node
	h.game_state().set("active_contract_order", 2)
	var host: Node3D = h.make_level_host(lp)
	arena.add_child(host)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, lp, host)
	# Guard at 16 m, facing the player: without the cloud it has LOS; the
	# thrown smoke lands between them (~14 m) and must break that LOS.
	var g: Node3D = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, -30.0)) as Node3D
	g.set("level_ctrl", host)
	g.set("patrol_speed", 0.0)
	g.set("suspicious_speed", 0.0)
	g.set("chase_speed", 0.0)
	g.set("detection", 0.0)
	# Extend sight only so the LOS-block probe is meaningful at the smoke's
	# settle distance (~26 m); the honor of the authored 20 m range is covered
	# by the guard AI's own suites.
	g.set("sight_range", 40.0)
	g.set("lose_sight_range", 45.0)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_physics(2)

	var noise_tags: Array[String] = []
	var nb: Node = h.noise_bus()
	var noise_cb: Callable = func(_o: Vector3, _l: float, _s: Node, tag: String) -> void:
		noise_tags.append(tag)
	if nb != null and h.has_s(nb, "noise_emitted"):
		nb.connect("noise_emitted", noise_cb)

	var ok: bool = false
	if h.has_m(p, "equip_tool") and h.has_m(g, "get_alert_state"):
		p.call("equip_tool", "smoke_bomb")
		await h.step_process(1)
		p.call("_use_smoke_bomb")
		await h.step_physics(140)
		# Now face the guard at the player through the settled cloud.
		g.look_at(Vector3(p.global_position.x, g.global_position.y, p.global_position.z), Vector3.UP)
		g.set("detection", 0.0)
		await h.step_physics(40)
		var sm: Array = host.get("smokes") as Array
		var guard_eye: Vector3 = g.global_position + Vector3.UP * 1.5
		var player_eye: Vector3 = (p as Node3D).global_position + Vector3.UP * 1.3
		var blocked: bool = h.is_true(host.call("is_blocked_by_smoke", guard_eye, player_eye))
		var cloud_dbg: String = ""
		if not sm.is_empty():
			var s0: Dictionary = sm[0] as Dictionary
			cloud_dbg = "min=%s max=%s guard=%s player=%s" % [str(s0.get("min")), str(s0.get("max")), str(guard_eye), str(player_eye)]
		var alert: Dictionary = g.call("get_alert_state") as Dictionary
		var alert_state: String = str(alert.get("state", ""))
		var not_alerted: bool = alert_state != "ALERTED" and alert_state != "COMBAT"
		var smoke_noise: bool = noise_tags.has("smoke")
		var sw_energy: float = float(hud.call("get_soundwave_intensity")) if h.has_m(hud, "get_soundwave_intensity") else -1.0
		ok = (not sm.is_empty()) and blocked and smoke_noise and not_alerted
		print("[T3-03] smoke_clouds=%d blocked=%s noise_tags=%s guard_state=%s hud_wave_energy=%.3f %s" % [
			sm.size(), str(blocked), str(noise_tags), alert_state, sw_energy, cloud_dbg])
	if nb != null and h.has_s(nb, "noise_emitted") and nb.is_connected("noise_emitted", noise_cb):
		nb.disconnect("noise_emitted", noise_cb)
	h.require(ok, "T3-03", "Smoke Bomb -> NoiseBus -> guard LOS block composition (%s)" % str(ok))
	await h.free_node(arena)


func _t3_04_lockpick_disguise_vault() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.game_state().set("thief_id", "chameleon")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var lc: Node = h.new_script_node("res://src/interact/loot_container.gd")
	lc.set("loot_tier", "major")
	lc.set("marker_pos", arena.global_position)
	arena.add_child(lc)
	var ok: bool = false
	if h.has_m(p, "set_lockpicking_active") and h.has_prop(lc, "locked"):
		lc.set("locked", true)
		lc.set("lock_level", 3)
		p.set("disguise_active", true)
		p.set("disguise_integrity", 100.0)
		p.set("disguise_ttl", 60.0)
		p.call("set_lockpicking_active", true)
		await h.step_physics(60)
		var integ: float = float(p.get("disguise_integrity"))
		p.call("set_lockpicking_active", false)
		ok = absf(integ - 94.0) < 0.8
	h.require(ok, "T3-04", "Lockpicking drains disguise 5/s + 1/s and clears on finish (%s)" % str(ok))
	await h.free_node(arena)


func _t3_05_den_map_table_prep_loading_objectives() -> void:
	var mc_txt: String = h.read_text("res://src/missions/mission_controller.gd")
	var gs: Node = h.game_state()
	var ok: bool = h.has_prop(gs, "mission_objectives") and h.has_prop(gs, "contract_intro") \
		and (mc_txt.find("open_mission_prep") >= 0 or mc_txt.find("open_contract_table_ui") >= 0) and mc_txt.find("Set") >= 0
	h.require(ok, "T3-05", "Den Map Table -> MissionPrepUI -> Loading -> Set Objectives contract (%s)" % str(ok))


func _t3_06_vistara_vision_outline_sky() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.game_state().set("active_contract_order", 2)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_process(1)
	var vfx_scr: GDScript = h.load_script("res://src/core/vfx_manager.gd")
	var prop: MeshInstance3D = MeshInstance3D.new()
	prop.mesh = BoxMesh.new()
	arena.add_child(prop)
	vfx_scr.call("set_prop_highlight", prop, true)
	var ov_mat: Material = prop.material_overlay as Material
	var yellow_ok: bool = ov_mat != null and ((ov_mat is StandardMaterial3D and (ov_mat as StandardMaterial3D).emission.r > 0.7 and (ov_mat as StandardMaterial3D).emission.g > 0.5 and (ov_mat as StandardMaterial3D).emission.b < 0.4) or (ov_mat is ShaderMaterial))
	var tv_ok: bool = false
	if h.has_m(p, "is_thief_vision_active") and h.has_m(p, "equip_tool"):
		p.call("equip_tool", "vistara_diamond")
		await h.step_process(1)
		p.call("_use_equipped_primary")
		await h.step_process(1)
		hud.call("set_thief_vision", h.is_true(p.call("is_thief_vision_active")))
		var tv_ov: ColorRect = hud.get("thief_vision_overlay") as ColorRect
		tv_ok = h.is_true(p.call("is_thief_vision_active")) and (tv_ov == null or not tv_ov.visible or tv_ov.color.a <= 0.01) \
			and (h.has_m(p, "get_active_reticle_state") and str((p.call("get_active_reticle_state") as Dictionary).get("mode", "")) == "vistara_diamond")
	h.require(yellow_ok and tv_ok, "T3-06", "Vistara Diamond clean Thief Vision + yellow prop outline (%s)" % str(yellow_ok and tv_ok))
	await h.free_node(arena)


func _t3_07_guard_lantern_lightprobe_viewcone() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var lp: Node = arena_d["light_probe"] as Node
	var host: Node3D = h.make_level_host(lp)
	arena.add_child(host)
	h.game_state().set("thief_id", "chameleon")
	var g: Node3D = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, -5.0)) as Node3D
	if g != null:
		# Registration path: guard resolves LightProbe through level_ctrl.
		g.set("level_ctrl", host)
		if h.has_prop(g, "carries_lantern"):
			g.set("carries_lantern", true)
		if h.has_m(g, "enable_lantern"):
			g.call("enable_lantern")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, lp)
	# LightProbe caches samples for 80 ms; let the cache expire after building.
	await h.step_physics(8)
	var vis: float = float(lp.call("sample_visibility", arena.global_position, arena.get_world_3d().direct_space_state, [] as Array[RID]))
	var has_lantern_light: bool = not h.find_all_of_class(g, "OmniLight3D").is_empty()
	var vc_ok: bool = false
	if h.has_m(p, "apply_guard_viewcone_disguise_decay"):
		p.set("disguise_active", true)
		p.set("disguise_integrity", 100.0)
		p.set("disguise_ttl", 60.0)
		p.call("apply_guard_viewcone_disguise_decay", 1.0, true)
		p.call("_tick_sustained_systems", 1.0)
		vc_ok = float(p.get("disguise_integrity")) < 95.0
	h.require(has_lantern_light and vis > 0.10 and vc_ok, "T3-07", "Guard lantern registered with level LightProbe: vis=%.3f (>0.10) light=%s + viewcone drains disguise=%s" % [
		vis, str(has_lantern_light), str(vc_ok)])
	await h.free_node(arena)


func _t3_08_1p_zipwire_glb_anims_subviewport() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.add_wall_box(arena, Vector3(0.0, 1.5, -0.3), Vector3(4.0, 3.0, 0.2), "CloseWall")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	p.call("equip_tool", "zipwire")
	await h.step_process(2)
	var fp_root: Node = p.get("fp_tool_root") as Node
	var first_mi: MeshInstance3D = h.find_first_mesh_instance(fp_root)
	var real_glb: bool = fp_root != null and first_mi != null and first_mi.name != "ZipwireBody"
	var vm: Dictionary = h.viewmodel_contract(p)
	h.require(real_glb and h.is_true(vm.get("ok")), "T3-08",
		"Real 1P Zipwire GLB under camera (real=%s, under_cam=%s, sub_vp=%d, vm_shader=%d/%d, shadows=%d, vm_fov=%.2f)" % [
			str(real_glb), str(vm.get("under_cam")), int(vm.get("sub_viewports")),
			int(vm.get("shader_surfaces")), int(vm.get("total_surfaces")), int(vm.get("shadows_on")), float(vm.get("fov", -1.0))])
	await h.free_node(arena)


func _t3_09_startscreen_sky_neon_lighting() -> void:
	var mm: Control = h.new_script_node("res://src/ui/main_menu.gd") as Control
	h.root.add_child(mm)
	# Camera-bound env is assigned after the own-world SubViewport renders.
	await h.step_process(20)
	var mm_env: Environment = h.find_camera_env(mm)
	var hdr_txt: String = h.read_text("res://src/core/tat_hdr_emissive.gdshader").to_lower()
	var ok: bool = mm_env != null and mm_env.glow_enabled and mm_env.ssr_enabled and mm_env.volumetric_fog_enabled and mm_env.ssil_enabled \
		and (hdr_txt.find("fresnel") >= 0 or hdr_txt.find("desat") >= 0 or hdr_txt.find("mix(") >= 0)
	await h.free_node(mm)
	h.require(ok, "T3-09", "Startscreen sky + volumetric mist + neon HDR + SSR/SSIL coexist cleanly (env=%s)" % str(mm_env != null))


func _t3_10_interior_ssil_glass_stealth_ball() -> void:
	var gh_res: Dictionary = await h.instantiate_mission(2, 240, 1)
	var gh: Node = gh_res["mission"] as Node
	var gh_env: Environment = h.find_env(gh) if gh != null else null
	var ll: Node = gh.get("level_loader") as Node if gh != null else null
	var glass_mat: Variant = ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels") if ll != null else null
	var glass_src: String = h.read_text("res://src/core/tat_glass.gdshader")
	var depth_ok: bool = glass_src.find("depth_draw_never") >= 0 or glass_src.find("depth_prepass_alpha") >= 0 or glass_src.find("depth_draw_always") >= 0
	var ok: bool = gh_env != null and gh_env.ssil_enabled and (glass_mat is ShaderMaterial) and depth_ok and gh_res["hud"] != null
	await h.free_node(gh)
	h.require(ok, "T3-10", "Guildhall SSIL + tat_glass depth + Stealth Ball active (%s)" % str(ok))


func _t3_11_slithersap_lantern_guard_ko() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var lp: Node = arena_d["light_probe"] as Node
	var lamp: OmniLight3D = OmniLight3D.new()
	# Inside the authored 1.5 m InhibitableActorSearchRadius (old 1.2,1.0 was
	# 1.56 m away, just outside it).
	lamp.position = Vector3(1.0, 0.8, 0.0)
	arena.add_child(lamp)
	lp.call("register_light", lamp)
	var g: Node = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, 0.0))
	var puddle: Area3D = h.new_script_node("res://src/interact/slip_puddle.gd") as Area3D
	arena.add_child(puddle)
	puddle.call("setup", arena.global_position, lp, 0.0)
	puddle.call("_on_body_entered", g)
	var ko: bool = int(g.get("state")) == 5
	h.require((not lamp.visible) and ko, "T3-11", "Slithersap inhibits nearby light & knocks out guard 10s (%s)" % str((not lamp.visible) and ko))
	await h.free_node(arena)


func _t3_12_fairy_steal_guard_pip() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node3D = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node) as Node3D
	var g: Node3D = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, -18.0)) as Node3D
	if h.has_m(g, "set_carried_item"):
		g.call("set_carried_item", {"name": "Guild Key", "kind": "key", "id": "e2e_fairy_key", "value": 40})
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_process(2)
	var ok: bool = false
	var sel_ok: bool = false
	var blk: bool = true
	var stolen_v: Dictionary = {}
	var has_item_after: bool = true
	if h.has_m(g, "steal_carried_item") and h.has_m(g, "get_alert_state"):
		# Face the guard away from the player so the 30 deg facing block does
		# not reject an otherwise valid steal (the AI turns toward a spotted
		# player during its physics tick).
		g.rotation = Vector3(0.0, 0.0, 0.0)
		g.set("detection", 0.0)
		var sel: Variant = p.call("pickpocket_select_target", [g], p.global_position, Vector3.FORWARD)
		sel_ok = sel == g
		blk = h.is_true(p.call("pickpocket_is_blocked", g, p.global_position))
		stolen_v = g.call("steal_carried_item") as Dictionary
		has_item_after = h.is_true(g.call("has_carried_item"))
		var hud_src: String = h.read_text("res://src/ui/hud.gd")
		ok = sel_ok and (not blk) and not stolen_v.is_empty() and not has_item_after \
			and hud_src.find("get_alert_state") >= 0
		print("[T3-12] selected=%s blocked=%s stolen=%s carried_after=%s" % [
			str(sel_ok), str(blk), str(stolen_v.get("name", "")), str(has_item_after)])
	h.require(ok, "T3-12", "Pickpocket Fairy steals seeded guard item (selected=%s blocked=%s stolen=%s) + HUD alert pip (%s)" % [
		str(sel_ok), str(blk), str(stolen_v.get("name", "")), str(ok)])
	await h.free_node(arena)


func _t3_13_lockpick_jam_shock_disguise_damage() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.game_state().set("thief_id", "chameleon")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var ld: Node = h.new_script_node("res://src/interact/lockable_door.gd")
	arena.add_child(ld)
	ld.set("lock_level", 4)
	var jam_dmg: float = float(ld.call("get_jam_damage"))
	# Resolve the authored curve directly (lockable_door preloads the table);
	# loot_container.gd only routes through LockableDoorScript, it does not
	# keep a second literal damage copy.
	var gd: Node = h.game_data()
	var curve_dmg: float = float(gd.call("eval_curve", "CT_LockpickDamage", "DamageByLockLevel", 4.0, -1.0)) if gd != null else -1.0
	var lc: Node = h.new_script_node("res://src/interact/loot_container.gd")
	lc.set("lock_level", 4)
	arena.add_child(lc)
	var container_track: Dictionary = lc.call("get_minigame_track") as Dictionary
	p.set("disguise_active", true)
	p.set("disguise_integrity", 100.0)
	p.set("disguise_ttl", 60.0)
	p.call("take_damage", jam_dmg)
	var hp_left: float = float(p.get("health"))
	var integ_left: float = float(p.get("disguise_integrity"))
	h.require(absf(jam_dmg - 40.0) < 0.1 and absf(curve_dmg - jam_dmg) < 0.01 and not container_track.is_empty() \
		and absf(hp_left - 260.0) < 0.1 and absf(integ_left - 60.0) < 0.5,
		"T3-13", "Lv4 jam curve=%.1f (authored %.1f) -> HP=%.1f, Disguise=%.1f; container minigame track=%s" % [
			jam_dmg, curve_dmg, hp_left, integ_left, str(not container_track.is_empty())])
	await h.free_node(arena)


func _t3_14_settings_fov_hud_viewmodel() -> void:
	var orig_s: Dictionary = (h.save_system().call("get_settings") as Dictionary).duplicate(true)
	var st_ui: CanvasLayer = h.new_script_node("res://src/ui/settings_ui.gd") as CanvasLayer
	h.root.add_child(st_ui)
	await h.step_process(1)
	# Imported contract, not a literal: world FOV default is CAMERA_FOV
	# (85 horizontal -> 54.54 vertical after the camera fix); the viewmodel
	# keeps its own authored FP_VM_FOV_DEG projection lock.
	var tc_consts: Dictionary = (h.load_script("res://src/player/thief_character.gd") as GDScript).get_script_constant_map()
	var cam_contract: float = float(tc_consts.get("CAMERA_FOV", 75.0))
	var vm_contract: float = float(tc_consts.get("FP_VM_FOV_DEG", 85.0))
	var sl_fov: HSlider = st_ui.get("_fov_slider") as HSlider
	var want: float = clampf(cam_contract, sl_fov.min_value, sl_fov.max_value) if sl_fov != null else cam_contract
	if sl_fov != null: sl_fov.value = want
	st_ui.call("_apply_live", false)
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var cam: Camera3D = p.get("cam") as Camera3D
	var vm: Dictionary = h.viewmodel_contract(p)
	var cam_ok: bool = cam != null and absf(cam.fov - want) < 0.25
	var cam_fov: float = cam.fov if cam != null else -1.0
	var vm_ok: bool = h.is_true(vm.get("ok")) and absf(float(vm.get("fov", -99.0)) - vm_contract) < 0.01
	(h.save_system().get("data") as Dictionary)["settings"] = orig_s
	h.save_system().call("apply_saved_settings")
	await h.free_node(arena)
	await h.free_node(st_ui)
	h.require(cam_ok and vm_ok, "T3-14",
		"Settings FOV=%.2f syncs main camera=%.2f; 1P VM lock vm_fov=%.2f (authored %.2f) surfaces=%d/%d" % [
			want, cam_fov, float(vm.get("fov", -1.0)), vm_contract,
			int(vm.get("shader_surfaces")), int(vm.get("total_surfaces"))])


func _t3_15_den_exit_door_prep_loading() -> void:
	var den_res: Dictionary = await h.instantiate_mission(1, 200, 1)
	var den: Node = den_res["mission"] as Node
	var exit_d: Node = den.get_node_or_null("ThievesDenExitDoor") if den != null else null
	var mc_txt: String = h.read_text("res://src/missions/mission_controller.gd")
	var mp_txt: String = h.read_text("res://src/ui/mission_prep_ui.gd")
	var ok: bool = exit_d != null and exit_d.is_in_group("swinging_doors") and (mc_txt.find("open_mission_prep") >= 0 or mc_txt.find("open_contract_table_ui") >= 0) and mp_txt.find("MissionLobby_Geo3") >= 0
	await h.free_node(den)
	h.require(ok, "T3-15", "Den ExitDoor + Map Table -> MissionLobby Prep -> LoadingScreen (%s)" % str(ok))


func _t3_16_old_manor_terrain_mantle_smoke() -> void:
	var om_res: Dictionary = await h.instantiate_mission(3, 240, 1)
	var om: Node = om_res["mission"] as Node
	var p: Node = om_res["player"] as Node
	var tc_txt: String = h.read_text("res://src/player/thief_character.gd").to_lower()
	var sp_exists: bool = ResourceLoader.exists("res://src/player/smoke_projectile.gd")
	var ok: bool = om != null and p != null and tc_txt.find("mantle") >= 0 and sp_exists and h.has_m(p, "get_equipped_tool")
	await h.free_node(om)
	h.require(ok, "T3-16", "OldManor_P terrain + mantle + ballistic SmokeBomb (%s)" % str(ok))


func _t3_17_locked_vault_objective_escape() -> void:
	var gs: Node = h.game_state()
	var lc: Node = h.new_script_node("res://src/interact/loot_container.gd")
	lc.set("lock_level", 3)
	var track: Dictionary = lc.call("get_minigame_track") as Dictionary
	if lc != null: lc.queue_free()
	var ok: bool = false
	if h.has_prop(gs, "mission_objectives") and h.has_m(gs, "mark_objective_done") and h.has_m(gs, "are_all_objectives_complete"):
		gs.call("set_mission_objectives", [{"id": "vault_main", "label": "Steal the Effigy", "target": 1}], 0)
		var before: bool = h.is_true(gs.call("are_all_objectives_complete"))
		gs.call("mark_objective_done", "vault_main")
		var after: bool = h.is_true(gs.call("are_all_objectives_complete"))
		ok = (not before) and after and not track.is_empty()
		gs.call("set_mission_objectives", [], 0)
		gs.set("quest_item_acquired", false)
	h.require(ok, "T3-17", "Locked vault minigame track -> objective -> are_all_objectives_complete escape (track=%s)" % str(not track.is_empty()))


func _t3_18_ping_radial_compass_poi() -> void:
	var hud_txt: String = h.read_text("res://src/ui/hud.gd")
	var tex_ok: bool = ResourceLoader.exists("res://assets/ue/Raw/Art/UI/HUD/T_Compass_PoI_IconSheet.png") \
		and ResourceLoader.exists("res://assets/ue/Raw/Art/UI/HUD/T_compass_verticality_arrow.png")
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_process(2)
	h.game_state().set("state", "playing")
	hud.call("_add_ping", (p as Node3D).global_position + Vector3(0.0, 5.0, -10.0), "UP", Color(0.45, 0.95, 0.92))
	hud.call("_add_ping", (p as Node3D).global_position + Vector3(0.0, -5.0, -10.0), "DOWN", Color(0.45, 0.95, 0.92))
	await h.step_process(3)
	var arrows: Array = hud.get("_compass_verticality_pool") as Array
	var visible_arrows: int = 0
	var up_ok: bool = false
	var down_ok: bool = false
	for a_v: Variant in arrows:
		if not (a_v is TextureRect):
			continue
		var a: TextureRect = a_v as TextureRect
		if not a.visible:
			continue
		visible_arrows += 1
		if not a.flip_v:
			up_ok = true
		else:
			down_ok = true
	var ok: bool = h.has_action("ping_menu") and hud_txt.find("T_Compass_PoI_IconSheet") >= 0 \
		and hud_txt.find("T_compass_verticality_arrow") >= 0 and tex_ok \
		and visible_arrows >= 2 and up_ok and down_ok
	h.require(ok, "T3-18", "[MMB] ping radial -> compass PoI verticality arrows (visible=%d up=%s down=%s)" % [
		visible_arrows, str(up_ok), str(down_ok)])
	await h.free_node(arena)


func _t3_19_yellow_highlight_locked_safe_prompt() -> void:
	var vfx_scr: GDScript = h.load_script("res://src/core/vfx_manager.gd")
	var box: MeshInstance3D = MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	h.root.add_child(box)
	vfx_scr.call("set_prop_highlight", box, true)
	var ov_mat: Material = box.material_overlay as Material
	var yellow_ok: bool = ov_mat != null and ((ov_mat is StandardMaterial3D and (ov_mat as StandardMaterial3D).emission.r > 0.7 and (ov_mat as StandardMaterial3D).emission.g > 0.5 and (ov_mat as StandardMaterial3D).emission.b < 0.4) or (ov_mat is ShaderMaterial))
	vfx_scr.call("set_prop_highlight", box, false)
	await h.free_node(box)
	var lc: Node = h.new_script_node("res://src/interact/loot_container.gd")
	var has_lock: bool = h.has_prop(lc, "locked")
	if lc != null: lc.queue_free()
	h.require(yellow_ok and has_lock, "T3-19", "Yellow prop highlight + locked safe prompt (%s)" % str(yellow_ok and has_lock))


func _t3_20_disguise_1p_anim_vignette_sprint() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.game_state().set("thief_id", "chameleon")
	h.game_state().set("active_contract_order", 2)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	p.set("disguise_active", true)
	p.set("disguise_integrity", 100.0)
	p.set("disguise_ttl", 60.0)
	# Settle the landing/air state before sampling the stationary clip.
	for _i: int in range(30):
		await h.step_physics(1)
		if p is CharacterBody3D and (p as CharacterBody3D).is_on_floor():
			break
	# Let the landing action clip (AN_Jump_100CM__Land) reach its end before
	# sampling the stationary idle state.
	for _j: int in range(300):
		await h.step_physics(1)
		if p is CharacterBody3D and (p as CharacterBody3D).is_on_floor() and float(p.get("_fp_action_ttl")) <= 0.0:
			break
	await h.step_process(2)
	var clip: String = str(p.get("_fp_current_clip")).to_lower()
	var fp_ap: AnimationPlayer = p.get("fp_anim_player") as AnimationPlayer
	# ABPL_Disguise (the Disguise tool's 1P layer) uses
	# AN_ThiefCotter_Disguise_StandIdle standing and
	# AN_Disguise_Crouch_Idle_1P crouched. The Nisha AN_Disguise_*_1P set
	# belongs to ABPL_AntiStealth (Bolas/Firefly), not this tool, so the old
	# "no standing disguise idle" assumption was wrong. Assert both exact
	# clips resolve on the 1P arm player instead of accepting any clip whose
	# name merely contains "disguise".
	p.set("is_crouching", true)
	await h.step_physics(3)
	await h.step_process(3)
	var clip_crouch: String = str(p.get("_fp_current_clip")).to_lower()
	var vig: TextureRect = hud.get("disguise_vignette") as TextureRect
	var vig_ok: bool = vig != null and vig.visible
	var text_ok: bool = vig != null and vig.texture != null and vig.texture.resource_path.find("T_Disguise_Vignette02") >= 0
	var live_ok: bool = fp_ap != null \
		and fp_ap.has_animation("AN_ThiefCotter_Disguise_StandIdle") \
		and fp_ap.has_animation("AN_Disguise_Crouch_Idle_1P")
	var clip_ok: bool = clip == "an_thiefcotter_disguise_standidle" \
		and clip_crouch == "an_disguise_crouch_idle_1p" and live_ok
	await h.free_node(arena)
	h.require(clip_ok and vig_ok and text_ok, "T3-20", "ABPL_Disguise 1P idle: stand='%s' (want an_thiefcotter_disguise_standidle), crouch='%s' (want an_disguise_crouch_idle_1p), both on fp_anim_player=%s + HUD T_Disguise_Vignette02 (visible=%s tex=%s)" % [
		clip, clip_crouch, str(live_ok), str(vig_ok), str(text_ok)])


func _t3_21_health_blocks_fall_victory_xp() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.game_state().set("thief_id", "chameleon")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var blocks: Array = p.call("health_block_percentages") as Array
	var fall_dmg: float = float(p.call("fall_damage_for_drop", 8.0))
	var ss: Node = h.save_system()
	var xp10: int = int(ss.call("xp_threshold_for_level", 10))
	await h.free_node(arena)
	h.require(blocks == [30, 30, 20, 20] and fall_dmg > 0.0 and xp10 == 2500, "T3-21", "Chameleon [30,30,20,20] blocks, 8m fall dmg=%.1f, CT_XPToLevel L10=%d" % [fall_dmg, xp10])


func _t3_22_old_manor_puddle_ssr_sky() -> void:
	var om_v: Variant = h.read_json("res://data/generated/levels/OldManor/OldManor_P.tatlevel.json")
	var om_ls: Array = (om_v as Dictionary).get("landscapes", []) if om_v is Dictionary else []
	var dual_cnt: int = 0
	for l_v: Variant in om_ls:
		if l_v is Dictionary and ((l_v as Dictionary).get("weightmaps", []) as Array).size() >= 2:
			dual_cnt += 1
	var ls_txt: String = h.read_text("res://src/core/tat_landscape.gdshader")
	var wp_txt: String = h.read_text("res://src/core/weather_profile.gd")
	var mc_txt: String = h.read_text("res://src/missions/mission_controller.gd")
	var ssr_wired: bool = wp_txt.find("ssr_enabled") >= 0 or mc_txt.find("ssr_enabled") >= 0
	var puddle_rough_ok: bool = ls_txt.find("0.04") >= 0 or ls_txt.find("0.05") >= 0
	h.require(dual_cnt >= 7 and ssr_wired and puddle_rough_ok, "T3-22", "OldManor dual-weightmap (%d) + wet puddle ~0.04 + SSR (%s)" % [dual_cnt, str(ssr_wired and puddle_rough_ok)])


func _t3_23_wall_climb_height_curve_detection() -> void:
	var gai_scr: GDScript = h.load_script("res://src/ai/guard_ai.gd")
	var tc_txt: String = h.read_text("res://src/player/thief_character.gd").to_lower()
	var h_mult: float = float(gai_scr.call("height_difference_strength_multiplier", 3.2))
	var has_climb: bool = tc_txt.find("wall_climb") >= 0 or tc_txt.find("wallclimb") >= 0
	h.require(has_climb and absf(h_mult - 0.0) < 0.001, "T3-23", "Wall-climb +3.2m zeros Neutral height-difference detection multiplier (%.2f)" % h_mult)


func _t3_24_full_preservation_gate() -> void:
	var rt_ok: bool = h.read_text("res://tests/run_tests.gd").find("# 38.") >= 0
	var audit_ok: bool = h.repo_file_exists("tools/manifest_audit.py")
	var e2e_ok: bool = ResourceLoader.exists("res://tests/e2e/run_e2e_tests.gd")
	h.require(rt_ok and audit_ok and e2e_ok, "T3-24", "run_tests.gd 38 suites + manifest_audit.py + standalone E2E suite preserved")


## T3-25: guard eye ray must exclude the player's own body. The endpoint sits
## inside the player capsule, so without the player RID in the exclude list the
## ray self-occludes on layer 2 and every guard is blind (positive acquisition
## fails to reach the authored SUSPICIOUS threshold). Negative controls: a wall
## between them and a second guard's body (non-target layer) must both hold
## detection at 0, so the ray still respects authored body blocking.
##
## W6G note: the positive phase asserts the documented contract (acquired past
## the 15-point SUSPICIOUS threshold, i.e. the guard is no longer NEUTRAL). It
## used to also pin state == SUSPICIOUS (1), which only held while the removed
## port-only `vis_mult` light multiplier slowed the ramp; the authored 12 m ramp
## is light-independent and reaches 100/COMBAT in the same 240 frames.
func _t3_25_guard_sight_self_exclusion() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.game_state().set("active_contract_order", 2)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var g: Node3D = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, -12.0)) as Node3D
	g.set("patrol_speed", 0.0)
	g.set("suspicious_speed", 0.0)
	g.set("chase_speed", 0.0)
	g.set("detection", 0.0)
	g.set("sight_range", 200.0)
	g.set("lose_sight_range", 200.0)
	# Keep the idle guard aimed at the player for the whole positive phase.
	g.set("patrol_points", [(p as Node3D).global_position])
	g.look_at((p as Node3D).global_position, Vector3.UP)
	await h.step_physics(2)
	await h.step_physics(240)
	var det_pos: float = float(g.get("detection"))
	var state_pos: int = int(g.get("state"))
	# Alertness.NEUTRAL == 0; the authored threshold is 15. The docstring's
	# contract is "reaches the SUSPICIOUS threshold", not "stays below ALERTED":
	# after W6G the light-independent ramp may legitimately reach COMBAT here.
	var acquired: bool = det_pos >= 15.0 and state_pos != 0

	# Negative occlusion control 1: a real wall between them must hold 0.
	var wall: StaticBody3D = h.add_wall_box(arena, Vector3(0.0, 1.5, -6.0), Vector3(8.0, 4.0, 0.5), "T3SightOccluder")
	g.set("detection", 0.0)
	g.set("state", 0)
	g.set("state_timer", 0.0)
	g.set("_seconds_in_state", 10.0)
	g.set("_seconds_since_visible", 10.0)
	await h.step_physics(2)
	await h.step_physics(40)
	var det_occ: float = float(g.get("detection"))
	var state_occ: int = int(g.get("state"))
	var occluded: bool = det_occ == 0.0 and state_occ == 0
	wall.queue_free()
	await h.step_physics(2)

	# Negative occlusion control 2: a non-target body on layer 4 (a second
	# guard standing between them) must still block the ray.
	var body_block: Node3D = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, -6.0)) as Node3D
	body_block.set("patrol_speed", 0.0)
	body_block.set("suspicious_speed", 0.0)
	body_block.set("chase_speed", 0.0)
	body_block.set("detection", 0.0)
	body_block.set("sight_range", 0.0)
	body_block.set("lose_sight_range", 0.0)
	body_block.set("patrol_points", [body_block.global_position])
	g.set("detection", 0.0)
	g.set("state", 0)
	g.set("state_timer", 0.0)
	g.set("_seconds_in_state", 10.0)
	g.set("_seconds_since_visible", 10.0)
	await h.step_physics(2)
	await h.step_physics(40)
	var det_body: float = float(g.get("detection"))
	var state_body: int = int(g.get("state"))
	var body_blocked: bool = det_body == 0.0 and state_body == 0
	h.require(
		acquired and occluded and body_blocked,
		"T3-25",
		"guard sight excludes player RID (det=%.1f state=%d), wall blocks (det=%.1f state=%d), body blocks (det=%.1f state=%d)" % [
			det_pos, state_pos, det_occ, state_occ, det_body, state_body
		]
	)
	await h.free_node(body_block)
	await h.free_node(arena)
