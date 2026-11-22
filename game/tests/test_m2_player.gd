extends SceneTree
## Standalone Milestone M2 test suite (Features #7-#12 & M2<->M3/M4 Interface Contracts).
## Run: flatpak run org.godotengine.Godot --headless --path game --script res://tests/test_m2_player.gd

var fails: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _add_static_box(parent: Node, pos: Vector3, sz: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = sz
	cs.shape = bx
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_position = pos
	return sb


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var ThiefScript: GDScript = load("res://src/player/thief_character.gd") as GDScript
	var SmokeProjScript: GDScript = load("res://src/player/smoke_projectile.gd") as GDScript
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("state", "playing")
		gs.set("thief_id", "spider")
		gs.set("difficulty", 2)

	# 0. Generated gameplay JSON exports (tools/parse_gameplay.py)
	var cm_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/gameplay/character_movement.json"))
	var pt_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/gameplay/player_tools.json"))
	var cm_p: Dictionary = (cm_doc as Dictionary).get("player", {}) if cm_doc is Dictionary else {}
	var pt_zw: Dictionary = (pt_doc as Dictionary).get("zipwire", {}) if pt_doc is Dictionary else {}
	var pt_sb: Dictionary = (pt_doc as Dictionary).get("smoke_bomb", {}) if pt_doc is Dictionary else {}
	var json_ok: bool = is_equal_approx(float(cm_p.get("mantle_max_height_m", 0.0)), 4.0) \
		and is_equal_approx(float(cm_p.get("mantle_max_angle_deg", 0.0)), 25.0) \
		and cm_p.get("allow_mantle_from_crouch", false) == true \
		and is_equal_approx(float(cm_p.get("wall_climb_speed_m_s", 0.0)), 2.5) \
		and is_equal_approx(float(pt_zw.get("crank_duration_s", 0.0)), 6.0) \
		and is_equal_approx(float(pt_zw.get("crank_min_time_s", 0.0)), 0.5) \
		and is_equal_approx(float(pt_sb.get("initial_speed_m_s", 0.0)), 30.0) \
		and is_equal_approx(float(pt_sb.get("bounciness", 0.0)), 0.064) \
		and is_equal_approx(float(pt_sb.get("destroy_delay_s", 0.0)), 0.5)
	_check(json_ok, "M2.0 parse_gameplay.py exports mantle/climb/crank/smoke_bomb constants",
		"M2.0 parse_gameplay.py missing expected keys: cm=" + str(cm_p) + " zw=" + str(pt_zw) + " sb=" + str(pt_sb))

	# Create world arena for player tests
	var arena := Node3D.new()
	arena.name = "M2Arena"
	root.add_child(arena)
	# Floor slab
	_add_static_box(arena, Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))

	var player: CharacterBody3D = ThiefScript.new() as CharacterBody3D
	player.set_physics_process(false)
	arena.add_child(player)
	player.global_position = Vector3(0.0, 0.05, 0.0)
	await process_frame
	await process_frame

	# 1. Feature #8: 1P arms real GLB, upright orientation, PBR + VM ShaderMaterial
	var real_arms: bool = player.get("_fp_use_real_arms") == true
	var arm_holder: Node3D = player.get("_fp_arm_holder") as Node3D
	var body_upper: Node3D = arm_holder.get_node_or_null("BodyUpper1P") as Node3D if arm_holder != null else null
	var arms_yaw_ok: bool = body_upper != null and is_equal_approx(body_upper.rotation_degrees.y, 180.0) and absf(body_upper.rotation_degrees.x) < 0.1
	var arm_vm_surfaces: int = 0
	var arm_tex_surfaces: int = 0
	if body_upper != null:
		for ch: Node in body_upper.find_children("*", "MeshInstance3D", true, false):
			var mi := ch as MeshInstance3D
			if mi != null and mi.mesh != null:
				for s: int in range(mi.mesh.get_surface_count()):
					var sm := mi.get_surface_override_material(s) as ShaderMaterial
					if sm != null and is_equal_approx(float(sm.get_shader_parameter("vm_fov_deg")), 85.0):
						arm_vm_surfaces += 1
						if sm.get_shader_parameter("albedo_tex") != null:
							arm_tex_surfaces += 1
	_check(real_arms and arms_yaw_ok and arm_vm_surfaces >= 2 and arm_tex_surfaces >= 2,
		"M2.1 1P BodyUpper1P real arms upright (yaw=180) with PBR + VM isolation (" + str(arm_vm_surfaces) + " surfaces)",
		"M2.1 1P arms check failed: real=" + str(real_arms) + " yaw_ok=" + str(arms_yaw_ok) + " vm=" + str(arm_vm_surfaces) + " tex=" + str(arm_tex_surfaces))

	# 2. Feature #7: All 6 tools load real GLBs at scale 1.0, socket roll -90, PBR + VM isolation
	var fallback_names: Array[String] = ["ZipwireBody", "SmokeBomb", "SapVial", "FairyOrb", "BlackjackHandle"]
	var all_tools: Array[String] = ["zipwire", "smoke_bomb", "slithersap", "blackjack", "fairy", "vistara_diamond"]
	var tools_ok: bool = true
	var tools_dbg: String = ""
	var bj_ok: bool = false
	var vistara_ok: bool = false
	var fairy_ok: bool = false
	for tid: String in all_tools:
		player.call("equip_tool", tid)
		await process_frame
		var troot: Node3D = player.get("fp_tool_root") as Node3D
		if troot == null or troot.get_child_count() == 0:
			tools_ok = false
			tools_dbg += tid + ":empty "
			continue
		var inst := troot.get_child(0) as Node3D
		var is_fallback: bool = false
		for fn: String in fallback_names:
			if troot.get_node_or_null(fn) != null:
				is_fallback = true
		var scale_ok: bool = inst != null and inst.scale.is_equal_approx(Vector3.ONE)
		var roll_ok: bool = inst != null and is_equal_approx(inst.rotation_degrees.x, -90.0)
		var vm_cnt: int = 0
		var surface_mats: Array = []
		for ch: Node in troot.find_children("*", "MeshInstance3D", true, false):
			var mi := ch as MeshInstance3D
			if mi != null and mi.mesh != null:
				for s: int in range(mi.mesh.get_surface_count()):
					var sm := mi.get_surface_override_material(s) as ShaderMaterial
					if sm != null and is_equal_approx(float(sm.get_shader_parameter("vm_fov_deg")), 85.0):
						vm_cnt += 1
						surface_mats.append(sm)
		if is_fallback or not scale_ok or not roll_ok or vm_cnt == 0:
			tools_ok = false
			tools_dbg += tid + "(fb=" + str(is_fallback) + ",sc=" + str(scale_ok) + ",rl=" + str(roll_ok) + ",vm=" + str(vm_cnt) + ") "
		if tid == "blackjack" and surface_mats.size() >= 1:
			var bsm := surface_mats[0] as ShaderMaterial
			bj_ok = bsm.get_shader_parameter("albedo_tex") != null \
				and bsm.get_shader_parameter("orm_tex") != null \
				and is_equal_approx(float(bsm.get_shader_parameter("metallic_val")), 1.0)
		if tid == "vistara_diamond" and surface_mats.size() >= 2:
			var g0 := surface_mats[0] as ShaderMaterial
			var g1 := surface_mats[1] as ShaderMaterial
			vistara_ok = g0.shader != g1.shader and g1.get_shader_parameter("albedo_tex") != null and float(g0.get_shader_parameter("fresnel_strength")) > 0.5
		if tid == "fairy" and surface_mats.size() >= 5:
			var f0 := surface_mats[0] as ShaderMaterial
			var f2 := surface_mats[2] as ShaderMaterial
			fairy_ok = f0.get_shader_parameter("use_albedo_tex") == false and f2.get_shader_parameter("use_albedo_tex") == false
	_check(tools_ok and bj_ok and vistara_ok and fairy_ok,
		"M2.2 All 6 1P tool GLBs loaded (scale=1, roll=-90, VM ShaderMaterial, Blackjack/Vistara/Fairy PBR verified)",
		"M2.2 Tool GLB check failed: " + tools_dbg + " bj=" + str(bj_ok) + " vistara=" + str(vistara_ok) + " fairy=" + str(fairy_ok))

	# 3. Feature #8: Stationary 1P animations & bone in camera front (-Z)
	player.call("equip_tool", "zipwire")
	await process_frame
	var ap: AnimationPlayer = player.get("fp_anim_player") as AnimationPlayer
	var zw_idle_clip: String = str(player.get("_fp_current_clip"))
	var zw_playing: bool = ap != null and ap.is_playing() and zw_idle_clip == "AN_ThiefNisha_Zipwire_StandIdle"
	var cam: Camera3D = player.get("cam") as Camera3D
	var troot_now: Node3D = player.get("fp_tool_root") as Node3D
	var tool_in_cam: Vector3 = cam.to_local(troot_now.global_position) if (cam != null and troot_now != null) else Vector3.ZERO
	var tool_front_ok: bool = tool_in_cam.z < -0.05 and tool_in_cam.z > -1.0
	player.call("equip_tool", "smoke_bomb")
	await process_frame
	var sb_idle_ok: bool = str(player.get("_fp_current_clip")) == "AN_SmokeBomb__Idle"
	player.set("disguise_active", true)
	player.set("is_crouching", true)
	player.call("_update_fp_anim_state")
	var disg_clip_ok: bool = str(player.get("_fp_current_clip")) == "AN_Disguise_Crouch_Idle_1P"
	player.set("disguise_active", false)
	player.set("is_crouching", false)
	_check(zw_playing and tool_front_ok and sb_idle_ok and disg_clip_ok,
		"M2.3 1P anims stay active stationary (zipwire/smoke/disguise) & tool in camera front z=" + str(snappedf(tool_in_cam.z, 0.001)),
		"M2.3 1P anim check failed: zw=" + str(zw_playing) + "(" + zw_idle_clip + ") cam_pos=" + str(tool_in_cam) + " sb=" + str(sb_idle_ok) + " disg=" + str(disg_clip_ok))

	# 4. Feature #9: Equip state machine, Vistara Diamond ThiefVision & M2<->M3 Interface Contracts
	var equipped_events: Array = []
	player.connect("tool_equipped", func(tid: String, slot_idx: int) -> void:
		equipped_events.append([tid, slot_idx])
	)
	player.call("equip_tool", "vistara_diamond")
	var tv_on_vistara: bool = player.call("is_thief_vision_active") == true
	var eq_vistara: String = str(player.call("get_equipped_tool"))
	var slots: Array = player.call("get_tool_slots") as Array
	var slots_ok: bool = slots.size() == 4 \
		and str((slots[0] as Dictionary).get("id", "")) == "zipwire" \
		and str((slots[1] as Dictionary).get("id", "")) == "smoke_bomb" \
		and int((slots[3] as Dictionary).get("count", 0)) == -1 \
		and (slots[3] as Dictionary).get("active", false) == true
	var reticle: Dictionary = player.call("get_active_reticle_state") as Dictionary
	var reticle_ok: bool = str(reticle.get("mode", "")) == "vistara_diamond" \
		and reticle.has("target_valid") and reticle.has("crank_progress") \
		and reticle.has("crank_active") and reticle.get("hints") is Array
	player.call("equip_tool", "zipwire")
	var tv_off_after: bool = player.call("is_thief_vision_active") == false
	_check(tv_on_vistara and eq_vistara == "vistara_diamond" and slots_ok and reticle_ok and tv_off_after and equipped_events.size() >= 2,
		"M2.4 Equip state machine, Vistara Diamond ThiefVision & HUD Interface Contract verified",
		"M2.4 Equip/contract failed: tv_on=" + str(tv_on_vistara) + " eq=" + eq_vistara + " slots=" + str(slots_ok) + " ret=" + str(reticle_ok) + " tv_off=" + str(tv_off_after))

	# 5. Feature #10a: Zipwire target validation, persistent cable, and [RMB] crank
	# Place an elevated ledge wall at z = -10, y = 4
	var zw_wall: StaticBody3D = _add_static_box(arena, Vector3(0.0, 4.0, -10.0), Vector3(6.0, 6.0, 1.0))
	await physics_frame
	await physics_frame
	# Aim straight at (0, 4, -10)
	var head_node: Node3D = player.get("head") as Node3D
	if head_node != null:
		head_node.rotation.x = atan2(4.0 - 1.67, 9.5)
	var valid_res: Dictionary = player.call("validate_zipwire_target") as Dictionary
	var valid_hit_ok: bool = valid_res.get("valid", false) == true
	var launched: bool = player.call("_try_spider_grapple") == true
	var cable_node: MeshInstance3D = player.get("_zipwire_cable_mesh") as MeshInstance3D
	var cable_vis: bool = cable_node != null and cable_node.visible and cable_node.top_level
	player.set("is_grappling", false)
	player.call("_update_zipwire_cable")
	var cable_hid: bool = cable_node != null and not cable_node.visible
	# Crank test: partial cranks grant nothing (GA_Hotwire_Crank full-crank
	# reward only); a full 6.0s crank clears cooldown and restores +1 charge.
	player.set("ability_cooldown", 5.0)
	var ch_before: int = int((player.get("charges") as Dictionary).get("grapple", 0))
	player.call("_begin_wire_crank")
	player.call("_tick_wire_crank", 1.0, true)
	var crank_prog_mid: float = float(player.get("crank_progress"))
	var crank_ret: Dictionary = player.call("get_active_reticle_state") as Dictionary
	var crank_active_ok: bool = crank_ret.get("crank_active", false) == true and crank_prog_mid > 0.1
	player.call("_end_wire_crank")
	var cd_unchanged: bool = is_equal_approx(float(player.get("ability_cooldown")), 5.0)
	player.call("_begin_wire_crank")
	player.call("_tick_wire_crank", 6.1, true)
	var ch_after: int = int((player.get("charges") as Dictionary).get("grapple", 0))
	var crank_full_ok: bool = is_equal_approx(float(player.get("ability_cooldown")), 0.0) and ch_after == mini(4, ch_before + 1)
	zw_wall.queue_free()
	if head_node != null:
		head_node.rotation.x = 0.0
	await physics_frame
	_check(valid_hit_ok and launched and cable_vis and cable_hid and crank_active_ok and cd_unchanged and crank_full_ok,
		"M2.5 Zipwire target validation, persistent cable & [RMB] crank verified",
		"M2.5 Zipwire failed: valid=" + str(valid_hit_ok) + " launch=" + str(launched) + " cable=" + str(cable_vis) + "/" + str(cable_hid) + " crank=" + str(crank_active_ok) + "/" + str(cd_unchanged) + "/" + str(crank_full_ok))

	# 6. Feature #10b: Auto-mantle (4.0m max, 25 deg, crouch allowed) & stamina-burning wall-climb (2.5 m/s)
	var ledge: StaticBody3D = _add_static_box(arena, Vector3(0.0, 1.25, -1.0), Vector3(4.0, 2.5, 1.2))
	await physics_frame
	await physics_frame
	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.rotation_degrees = Vector3.ZERO
	player.set("is_crouching", true)
	var mantle_crouch_ok: bool = player.call("try_auto_mantle") == true and player.get("is_mantling") == true
	player.set("is_mantling", false)
	player.set("is_crouching", false)
	# Off-angle > 25 deg must fail
	player.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	var mantle_angle_reject: bool = player.call("try_auto_mantle") == false
	player.rotation_degrees = Vector3.ZERO
	# Wall-climb test (airborne facing wall)
	player.global_position = Vector3(0.0, 0.5, 0.0)
	player.velocity = Vector3(0.0, 1.0, 0.0)
	player.move_and_slide()
	var stam_before: float = float(player.get("stamina"))
	var climbed: bool = player.call("_tick_wall_climb", 0.5, Vector3(0.0, 0.0, -1.0)) == true
	var stam_after: float = float(player.get("stamina"))
	var climb_vel_ok: bool = player.velocity.y > 0.5 and player.velocity.y <= 2.51
	ledge.queue_free()
	await physics_frame
	_check(mantle_crouch_ok and mantle_angle_reject and climbed and stam_after < stam_before and climb_vel_ok,
		"M2.6 Auto-mantle (crouch allowed, <=25 deg) & wall-climb (2.5 m/s, stamina burn) verified",
		"M2.6 Traversal failed: mantle=" + str(mantle_crouch_ok) + " angle_rej=" + str(mantle_angle_reject) + " climb=" + str(climbed) + " stam=" + str(stam_before) + "->" + str(stam_after) + " vy=" + str(player.velocity.y))

	# 7. Feature #11: Smoke Bomb ballistic projectile (30 m/s, bounciness 0.064, 0.5s delay) & trajectory arc
	var proj_consts: Dictionary = SmokeProjScript.get_script_constant_map()
	var proj_consts_ok: bool = is_equal_approx(float(proj_consts.get("INITIAL_SPEED_M_S", 0.0)), 30.0) \
		and is_equal_approx(float(proj_consts.get("BOUNCINESS", 0.0)), 0.064) \
		and is_equal_approx(float(proj_consts.get("DETONATE_DELAY_S", 0.0)), 0.5)
	player.call("equip_tool", "smoke_bomb")
	(player.get("charges") as Dictionary)["smoke_bomb"] = 1
	player.call("_update_smoke_trajectory")
	var traj_node: MeshInstance3D = player.get("_smoke_traj_mesh") as MeshInstance3D
	var traj_vis: bool = traj_node != null and traj_node.visible
	var before_children: int = arena.get_child_count()
	player.call("_use_smoke_bomb")
	await process_frame
	var spawned_proj: RigidBody3D = null
	for i: int in range(before_children, arena.get_child_count()):
		var c: Node = arena.get_child(i)
		if c is RigidBody3D and c.name.begins_with("SmokeProjectile"):
			spawned_proj = c as RigidBody3D
			break
	var proj_speed_ok: bool = spawned_proj != null and is_equal_approx(spawned_proj.linear_velocity.length(), 30.0)
	player.call("_update_smoke_trajectory")
	var traj_hid_empty: bool = traj_node != null and not traj_node.visible
	if spawned_proj != null and is_instance_valid(spawned_proj):
		spawned_proj.queue_free()
	_check(proj_consts_ok and traj_vis and proj_speed_ok and traj_hid_empty,
		"M2.7 Smoke Bomb ballistic throw (30 m/s, bounce 0.064, 0.5s) & trajectory arc verified",
		"M2.7 Smoke Bomb failed: consts=" + str(proj_consts_ok) + " traj=" + str(traj_vis) + "/" + str(traj_hid_empty) + " proj=" + str(proj_speed_ok))

	# 8. Feature #12: Disguise Integrity Reduction (Lockpicking 5.0/s, GuardViewCone 10.0/s)
	var r_base: float = float(ThiefScript.call("disguise_drain_rate", false, false))
	var r_lock: float = float(ThiefScript.call("disguise_drain_rate", false, false, true, false))
	var r_cone: float = float(ThiefScript.call("disguise_drain_rate", false, false, false, true))
	var r_both: float = float(ThiefScript.call("disguise_drain_rate", false, false, true, true))
	player.set("disguise_active", true)
	player.set("disguise_ttl", 60.0)
	player.call("set_lockpicking_active", true)
	var lp_flag_ok: bool = player.get("is_lockpicking") == true
	player.call("set_lockpicking_active", false)
	# P1 call-order fix: external viewcone decay is queued and consumed once per
	# sustained-systems tick, and the tick always applies the base timer drain.
	player.set("disguise_integrity", 100.0)
	player.call("apply_guard_viewcone_disguise_decay", 1.0, false)
	player.call("_tick_sustained_systems", 1.0)
	var no_cone_drained: float = 100.0 - float(player.get("disguise_integrity"))
	player.set("disguise_integrity", 100.0)
	player.call("apply_guard_viewcone_disguise_decay", 1.0, true)
	player.call("_tick_sustained_systems", 1.0)
	var cone_drained: float = 100.0 - float(player.get("disguise_integrity"))
	var no_cone_ok: bool = is_equal_approx(no_cone_drained, r_base)
	var cone_drain_ok: bool = is_equal_approx(cone_drained, r_cone)
	_check(is_equal_approx(r_base, 1.0) and is_equal_approx(r_lock, 6.0) and is_equal_approx(r_cone, 11.0) and is_equal_approx(r_both, 16.0) and lp_flag_ok and no_cone_ok and cone_drain_ok,
		"M2.8 Disguise Lockpicking (5.0/s) & GuardViewCone (10.0/s) decay verified",
		"M2.8 Disguise failed: rates=" + str([r_base, r_lock, r_cone, r_both]) + " lp=" + str(lp_flag_ok) + " no_cone=" + str(no_cone_ok) + "/" + str(no_cone_drained) + " cone=" + str(cone_drain_ok) + "/" + str(cone_drained))

	arena.queue_free()
	await process_frame
	# Same process-lifetime teardown as run_tests: audio playbacks, VFX/weather
	# caches and animation retarget caches otherwise report leaked resources.
	var m2_am: Node = root.get_node_or_null("/root/AudioManager")
	if m2_am != null and m2_am.has_method("cleanup_on_exit"):
		m2_am.call("cleanup_on_exit")
		for _a: int in range(8):
			await process_frame
	VfxManager.cleanup_static_caches()
	GuardAnimationLibrary.cleanup_static_caches()
	ArtNouveauTheme.cleanup_static_caches()
	(load("res://src/core/weather_profile.gd") as GDScript).cleanup_static_caches()
	(load("res://src/core/weather_visuals.gd") as GDScript).cleanup_static_caches()
	(load("res://src/ai/guard_ai.gd") as GDScript).cleanup_static_caches()
	for _b: int in range(8):
		await process_frame
	print("M2_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)
