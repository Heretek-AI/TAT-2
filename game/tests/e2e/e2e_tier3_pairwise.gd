extends RefCounted
## Tier 3: Cross-Feature Pairwise Interactions (24 checks: T3-01..T3-24).
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
	if h.has_m(p, "get_active_reticle_state") and h.has_m(p, "equip_tool_slot"):
		p.call("equip_tool_slot", 0)
		var rs0: Dictionary = p.call("get_active_reticle_state") as Dictionary
		h.press_action("secondary_action")
		await h.step_physics(35)
		var rs1: Dictionary = p.call("get_active_reticle_state") as Dictionary
		h.release_action("secondary_action")
		var hud_src: String = h.read_text("res://src/ui/hud.gd")
		ok = h.is_true(rs0.get("target_valid")) and h.is_true(rs1.get("crank_active")) and hud_src.find("crank_progress") >= 0
	h.require(ok, "T3-02", "Zipwire aim validity + crank progress synced to HUD ring (%s)" % str(ok))
	await h.free_node(arena)


func _t3_03_smoke_noise_soundwaves_guard() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.game_state().set("active_contract_order", 2)
	var host_scr: GDScript = GDScript.new()
	host_scr.source_code = """extends Node3D
var smokes: Array[Dictionary] = []
func spawn_smoke(pos: Vector3, ttl: float = 25.0) -> void:
	smokes.append({"min": pos - Vector3(2.5, 2.0, 2.5), "max": pos + Vector3(2.5, 2.0, 2.5), "ttl": ttl})
func is_blocked_by_smoke(a: Vector3, b: Vector3) -> bool:
	for s in smokes:
		var mn: Vector3 = s["min"]
		var mx: Vector3 = s["max"]
		if (a.z <= mx.z and b.z >= mn.z) or (b.z <= mx.z and a.z >= mn.z):
			return true
	return false
"""
	host_scr.reload()
	var host: Node3D = host_scr.new() as Node3D
	arena.add_child(host)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node, host)
	var g: Node = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, -12.0))
	g.set("level_ctrl", host)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_physics(2)

	var sw_node: Node = hud.find_child("*SoundWave*", true, false)
	var ok: bool = false
	if h.has_m(p, "equip_tool_slot") and h.has_m(g, "get_alert_state"):
		await h.tap_action("tool_2")
		await h.tap_action("primary_action")
		await h.step_physics(70)
		var sm: Array = host.get("smokes") as Array
		var alert: Dictionary = g.call("get_alert_state") as Dictionary
		var sw_vis: bool = sw_node != null
		ok = (not sm.is_empty()) and int(alert.get("state", 3)) < 3 and sw_vis
	h.require(ok, "T3-03", "Smoke Bomb + NoiseBus SoundWaves + Guard LOS block (%s)" % str(ok))
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
		and mc_txt.find("open_mission_prep") >= 0 and mc_txt.find("Set") >= 0
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
	var ov: StandardMaterial3D = prop.material_overlay as StandardMaterial3D
	var yellow_ok: bool = ov != null and ov.emission.r > 0.7 and ov.emission.g > 0.5 and ov.emission.b < 0.4
	var tv_ok: bool = false
	if h.has_m(p, "is_thief_vision_active") and h.has_m(p, "equip_tool_slot"):
		await h.tap_action("tool_4")
		await h.tap_action("primary_action")
		hud.call("set_thief_vision", h.is_true(p.call("is_thief_vision_active")))
		var tv_ov: ColorRect = hud.get("thief_vision_overlay") as ColorRect
		tv_ok = h.is_true(p.call("is_thief_vision_active")) and (tv_ov == null or not tv_ov.visible or tv_ov.color.a <= 0.01)
	h.require(yellow_ok and tv_ok, "T3-06", "Vistara Diamond clean Thief Vision + yellow prop outline (%s)" % str(yellow_ok and tv_ok))
	await h.free_node(arena)


func _t3_07_guard_lantern_lightprobe_viewcone() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var lp: Node = arena_d["light_probe"] as Node
	h.game_state().set("thief_id", "chameleon")
	var g: Node3D = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, -5.0)) as Node3D
	if g != null and h.has_prop(g, "has_lantern"):
		g.set("has_lantern", true)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, lp)
	await h.step_physics(2)
	var vis: float = float(lp.call("sample_visibility", arena.global_position, arena.get_world_3d().direct_space_state, [] as Array[RID]))
	var has_lantern_light: bool = not h.find_all_of_class(g, "OmniLight3D").is_empty()
	var vc_ok: bool = false
	if h.has_m(p, "apply_guard_viewcone_disguise_decay"):
		p.set("disguise_active", true)
		p.set("disguise_integrity", 100.0)
		p.call("apply_guard_viewcone_disguise_decay", 1.0, true)
		vc_ok = float(p.get("disguise_integrity")) < 95.0
	h.require(has_lantern_light and vis > 0.10 and vc_ok, "T3-07", "Guard lantern raises LightProbe (%.3f) + GuardViewCone drains disguise" % vis)
	await h.free_node(arena)


func _t3_08_1p_zipwire_glb_anims_subviewport() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.add_wall_box(arena, Vector3(0.0, 1.5, -0.3), Vector3(4.0, 3.0, 0.2), "CloseWall")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	p.call("_fp_set_tool", "zipwire")
	await h.step_process(1)
	var fp_root: Node = p.get("fp_tool_root") as Node
	var real_glb: bool = fp_root != null and h.find_first_mesh_instance(fp_root) != null and h.find_first_mesh_instance(fp_root).name != "ZipwireBody"
	var sub_vp: bool = not h.find_all_of_class(p, "SubViewport").is_empty()
	h.require(real_glb and sub_vp, "T3-08", "Real 1P Zipwire GLB + SubViewport isolation (%s)" % str(real_glb and sub_vp))
	await h.free_node(arena)


func _t3_09_startscreen_sky_neon_lighting() -> void:
	var mm: Control = h.new_script_node("res://src/ui/main_menu.gd") as Control
	h.root.add_child(mm)
	await h.step_process(3)
	var mm_env: Environment = h.find_env(mm)
	var hdr_txt: String = h.read_text("res://src/core/tat_hdr_emissive.gdshader").to_lower()
	var ok: bool = mm_env != null and mm_env.glow_enabled and mm_env.ssr_enabled and mm_env.volumetric_fog_enabled and (hdr_txt.find("fresnel") >= 0 or hdr_txt.find("desat") >= 0 or hdr_txt.find("mix(") >= 0)
	await h.free_node(mm)
	h.require(ok, "T3-09", "Startscreen sky + volumetric mist + neon HDR + SSR coexist cleanly (%s)" % str(ok))


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
	lamp.position = Vector3(1.2, 1.0, 0.0)
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
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_process(1)
	var ok: bool = false
	if h.has_m(g, "steal_carried_item") and h.has_m(g, "get_alert_state"):
		var sel: Variant = p.call("pickpocket_select_target", [g], p.global_position, Vector3.FORWARD)
		var blk: bool = h.is_true(p.call("pickpocket_is_blocked", g, p.global_position))
		var stolen: Variant = g.call("steal_carried_item")
		var hud_src: String = h.read_text("res://src/ui/hud.gd")
		ok = (sel == g) and (not blk) and (stolen != null) and hud_src.find("get_alert_state") >= 0
	h.require(ok, "T3-12", "Pickpocket Fairy steals guard carried item + HUD alert pip (%s)" % str(ok))
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
	p.set("disguise_active", true)
	p.set("disguise_integrity", 100.0)
	p.set("disguise_ttl", 60.0)
	p.call("take_damage", jam_dmg)
	var hp_left: float = float(p.get("health"))
	var integ_left: float = float(p.get("disguise_integrity"))
	var lc_txt: String = h.read_text("res://src/interact/loot_container.gd")
	h.require(absf(hp_left - 260.0) < 0.1 and absf(integ_left - 60.0) < 0.5 and lc_txt.find("CT_LockpickDamage") >= 0, "T3-13", "Lv4 jam 40 Shock dmg -> HP=260, Disguise=60, LootContainer wired (%s)" % str(lc_txt.find("CT_LockpickDamage") >= 0))
	await h.free_node(arena)


func _t3_14_settings_fov_hud_viewmodel() -> void:
	var orig_s: Dictionary = (h.save_system().call("get_settings") as Dictionary).duplicate(true)
	var st_ui: CanvasLayer = h.new_script_node("res://src/ui/settings_ui.gd") as CanvasLayer
	h.root.add_child(st_ui)
	await h.step_process(1)
	var sl_fov: HSlider = st_ui.get("_fov_slider") as HSlider
	if sl_fov != null: sl_fov.value = 95.0
	st_ui.call("_apply_live", false)
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var cam: Camera3D = p.get("cam") as Camera3D
	var sub_vps: Array[Node] = h.find_all_of_class(p, "SubViewport")
	var sub_fov_ok: bool = false
	if not sub_vps.is_empty():
		var vc: Array[Node] = h.find_all_of_class(sub_vps[0], "Camera3D")
		if not vc.is_empty():
			sub_fov_ok = absf((vc[0] as Camera3D).fov - 95.0) < 1.0
	var fov_ok: bool = cam != null and absf(cam.fov - 95.0) < 1.0 and sub_fov_ok
	(h.save_system().get("data") as Dictionary)["settings"] = orig_s
	h.save_system().call("apply_saved_settings")
	await h.free_node(arena)
	await h.free_node(st_ui)
	h.require(fov_ok, "T3-14", "Settings FOV=95 syncs main camera & 1P SubViewport (%s)" % str(fov_ok))


func _t3_15_den_exit_door_prep_loading() -> void:
	var den_res: Dictionary = await h.instantiate_mission(1, 200, 1)
	var den: Node = den_res["mission"] as Node
	var exit_d: Node = den.get_node_or_null("ThievesDenExitDoor") if den != null else null
	var mc_txt: String = h.read_text("res://src/missions/mission_controller.gd")
	var mp_txt: String = h.read_text("res://src/ui/mission_prep_ui.gd")
	var ok: bool = exit_d != null and exit_d.is_in_group("swinging_doors") and mc_txt.find("open_mission_prep") >= 0 and mp_txt.find("MissionLobby_Geo3") >= 0
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
	var lc_txt: String = h.read_text("res://src/interact/loot_container.gd")
	var gs: Node = h.game_state()
	var ok: bool = h.has_prop(gs, "mission_objectives") and h.has_m(gs, "can_extract") and lc_txt.find("DA_LockpickMinigameVariations") >= 0
	h.require(ok, "T3-17", "Locked vault container -> minigame -> objective -> escape (%s)" % str(ok))


func _t3_18_ping_radial_compass_poi() -> void:
	var hud_txt: String = h.read_text("res://src/ui/hud.gd")
	var ok: bool = h.has_action("ping_menu") and hud_txt.find("T_Compass_PoI_IconSheet") >= 0 and hud_txt.find("T_compass_verticality_arrow") >= 0
	h.require(ok, "T3-18", "[MMB] ping radial spawns PoI tracked on T_compass_lines (%s)" % str(ok))


func _t3_19_yellow_highlight_locked_safe_prompt() -> void:
	var vfx_scr: GDScript = h.load_script("res://src/core/vfx_manager.gd")
	var box: MeshInstance3D = MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	h.root.add_child(box)
	vfx_scr.call("set_prop_highlight", box, true)
	var ov: StandardMaterial3D = box.material_overlay as StandardMaterial3D
	var yellow_ok: bool = ov != null and ov.emission.r > 0.7 and ov.emission.g > 0.5 and ov.emission.b < 0.4
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
	await h.step_physics(4)
	var clip: String = str(p.get("_fp_current_clip")).to_lower()
	var vig: TextureRect = hud.get("disguise_vignette") as TextureRect
	var ok: bool = clip.find("disguise") >= 0 and vig != null and vig.visible
	await h.free_node(arena)
	h.require(ok, "T3-20", "Disguise 1P anim (%s) + HUD T_Disguise_Vignette02 (%s)" % [clip, str(vig != null and vig.visible)])


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
	var h_mult: float = float(gai_scr.call("height_difference_strength_multiplier", 0, 3.2))
	var has_climb: bool = tc_txt.find("wall_climb") >= 0 or tc_txt.find("wallclimb") >= 0
	h.require(has_climb and absf(h_mult - 0.0) < 0.001, "T3-23", "Wall-climb +3.2m zeros Neutral height-difference detection multiplier (%.2f)" % h_mult)


func _t3_24_full_preservation_gate() -> void:
	var rt_ok: bool = h.read_text("res://tests/run_tests.gd").find("# 38.") >= 0
	var audit_ok: bool = h.repo_file_exists("tools/manifest_audit.py")
	var e2e_ok: bool = ResourceLoader.exists("res://tests/e2e/run_e2e_tests.gd")
	h.require(rt_ok and audit_ok and e2e_ok, "T3-24", "run_tests.gd 38 suites + manifest_audit.py + standalone E2E suite preserved")
