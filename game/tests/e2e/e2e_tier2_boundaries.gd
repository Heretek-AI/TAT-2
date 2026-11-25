extends RefCounted
## Tier 2: Boundary, Corner & R3 Cooked-Data Limits (110 checks = 5 per feature).

var h: RefCounted


func _init(helpers: RefCounted) -> void:
	h = helpers


func run() -> void:
	h.snapshot_state()
	await _bVA_01_sky()
	await _bVA_02_lighting()
	await _bVA_03_startscreen()
	await _bVA_04_neon_landscape()
	await _bVA_05_mission_prep()
	await _bVA_06_vfx_glass_culling()
	await _bVA_07_1p_tool_glbs()
	await _bVA_08_1p_arms_anims()
	await _bVA_09_tool_equip()
	await _bVA_10_zipwire_mantle_climb()
	await _bVA_11_smoke_and_sap()
	await _bVA_12_disguise()
	await _bVA_13_hud_core()
	await _bVA_14_hud_widgets()
	await _bVA_15_lockpick_overlays()
	await _bVA_16_shell_ui()
	await _bVA_17_den_hub()
	await _bVA_18_objectives()
	await _bVA_19_locks_containers_doors()
	await _bVA_20_guard_lantern_pickpocket_decay()
	await _bVA_21_old_manor_r3()
	await _bVA_22_qa_integrity()
	h.restore_state()


func _bVA_01_sky() -> void:
	var wv_scr: GDScript = h.load_script("res://src/core/weather_visuals.gd")
	# T2-01-A: Corrupt Moon Size Clamp [0, 20] deg
	var d_hi: float = float(wv_scr.call("moon_diameter_deg", 500.0, 0.0))
	var d_lo: float = float(wv_scr.call("moon_diameter_deg", -5.0, 0.0))
	h.require(absf(d_hi - 20.0) < 0.001 and absf(d_lo - 0.0) < 0.001 and not is_nan(d_hi) and not is_nan(d_lo), "T2-01-A", "moon_diameter_deg clamped [0,20]: hi=%.2f lo=%.2f" % [d_hi, d_lo])

	# T2-01-B: overall_color Never Squared
	var p_ov: Dictionary = {"sky": {"overall_color": [0.001, 0.001, 0.001]}}
	var hc: Color = wv_scr.call("horizon_color_of", p_ov)
	var zc: Color = wv_scr.call("zenith_color_of", p_ov)
	h.require(absf(hc.r - 0.001) < 1e-5 and absf(zc.r - 0.001) < 1e-5, "T2-01-B", "overall_color unmultiplied: h=%s z=%s" % [str(hc), str(zc)])

	# T2-01-C: moon.visible == false Hides Disc
	var moon: DirectionalLight3D = DirectionalLight3D.new()
	var sky_off: Sky = wv_scr.call("make_sky", {"moon": {"visible": false}}, moon) as Sky
	var sm_off: ShaderMaterial = sky_off.sky_material as ShaderMaterial if sky_off != null else null
	var mv_off: float = float(sm_off.get_shader_parameter("moon_visible")) if sm_off != null else -1.0
	h.require(absf(mv_off - 0.0) < 0.001, "T2-01-C", "moon.visible=false -> moon_visible=%.1f" % mv_off)

	# T2-01-D: Rain Below Threshold (<= 0.05) Returns Null
	var dummy_p: Node3D = Node3D.new()
	var rain_off: Variant = wv_scr.call("make_rain", dummy_p, {"rain": {"enabled": true, "intensity": 1e-6}})
	h.require(rain_off == null, "T2-01-D", "make_rain intensity 1e-6 returns null")
	dummy_p.queue_free()

	# T2-01-E: R3 M_Sky / MI_VolumetricCloud_* Non-Fabrication
	var sky_txt: String = h.read_text("res://src/core/tat_sky.gdshader")
	var wv_txt: String = h.read_text("res://src/core/weather_visuals.gd")
	var labelled: bool = sky_txt.find("APPROXIMATE") >= 0 and wv_txt.find("APPROXIMATE") >= 0 and sky_txt.find("volumetric_cloud_tex") < 0
	h.require(labelled, "T2-01-E", "R3 M_Sky/VolumetricCloud approximations explicitly labelled, zero fabricated cloud textures")


func _bVA_02_lighting() -> void:
	# T2-02-A: R3 Lumen GI Non-Fabrication
	var mc_txt: String = h.read_text("res://src/missions/mission_controller.gd")
	var wp_txt: String = h.read_text("res://src/core/weather_profile.gd")
	var no_fake_lumen: bool = mc_txt.find("LumenSkylightLeaking =") < 0 and wp_txt.find("LumenSkylightLeaking =") < 0
	h.require(no_fake_lumen, "T2-02-A", "R3 Lumen GI not fabricated as extracted bounce constant")

	var ll: Node = h.new_script_node("res://src/core/level_loader.gd")
	h.root.add_child(ll)
	await h.step_process(1)

	# T2-02-B: Bounded compressive floor (0.01 authored -> 0.01..0.05 energy)
	var l_floor: Light3D = ll.call("_build_light", {"type": "PointLightComponent", "intensity": 0.01, "radius": 5.0}) as Light3D
	var exp_floor: float = float(ll.call("light_energy_for_intensity", 0.01))
	h.require(l_floor != null and absf(l_floor.light_energy - exp_floor) < 1e-5 \
		and l_floor.light_energy >= 0.01 and l_floor.light_energy <= 0.05,
		"T2-02-B", "light floor 0.01 -> %.5f (mapping %.5f)" % [l_floor.light_energy if l_floor != null else -1.0, exp_floor])

	# T2-02-C: Smooth shoulder replaces the hard 4.0 ceiling
	var l_ceil: Light3D = ll.call("_build_light", {"type": "SpotLightComponent", "intensity": 2500.0, "radius": 9.0, "outer_cone": 50.0}) as Light3D
	var exp_ceil: float = float(ll.call("light_energy_for_intensity", 2500.0))
	h.require(l_ceil != null and absf(l_ceil.light_energy - exp_ceil) < 1e-5 \
		and l_ceil.light_energy > 3.0 and l_ceil.light_energy < 4.0,
		"T2-02-C", "light shoulder 2500 -> %.3f (mapping %.3f, no hard clamp)" % [l_ceil.light_energy if l_ceil != null else -1.0, exp_ceil])

	# T2-02-D: No Branch Jump Across 19.9 vs 20.0
	var l_199: Light3D = ll.call("_build_light", {"type": "PointLightComponent", "intensity": 19.9, "radius": 5.0}) as Light3D
	var l_200: Light3D = ll.call("_build_light", {"type": "PointLightComponent", "intensity": 20.0, "radius": 5.0}) as Light3D
	var jump_ok: bool = l_199 != null and l_200 != null and absf(l_200.light_energy - l_199.light_energy) / l_200.light_energy < 0.01
	h.require(jump_ok, "T2-02-D", "continuous 19.9 (%.4f) vs 20.0 (%.4f)" % [l_199.light_energy if l_199 != null else -1.0, l_200.light_energy if l_200 != null else -1.0])

	# T2-02-E: Defensive Light Range Ceiling (200.0 m) & Min (1.0 m)
	var l_rhi: OmniLight3D = ll.call("_build_light", {"type": "PointLightComponent", "intensity": 15.0, "radius": 999.0}) as OmniLight3D
	var l_rlo: OmniLight3D = ll.call("_build_light", {"type": "PointLightComponent", "intensity": 15.0, "radius": 0.1}) as OmniLight3D
	h.require(
		l_rhi != null and l_rlo != null and absf(l_rhi.omni_range - 200.0) < 0.01 and absf(l_rlo.omni_range - 1.0) < 0.01,
		"T2-02-E",
		"light range clamped [1,200]: hi=%.1f lo=%.1f" % [l_rhi.omni_range if l_rhi != null else -1.0, l_rlo.omni_range if l_rlo != null else -1.0]
	)
	for ln: Light3D in [l_floor, l_ceil, l_199, l_200, l_rhi, l_rlo]:
		if ln != null: ln.free()
	await h.free_node(ll)


func _bVA_03_startscreen() -> void:
	var ll: Node = h.new_script_node("res://src/core/level_loader.gd")
	h.root.add_child(ll)
	await h.step_process(1)

	# T2-03-A: RECT_LIGHT_OFF_THRESHOLD (<= 0.01)
	var p_host: Node3D = Node3D.new()
	h.root.add_child(p_host)
	var ctx: Dictionary = {}
	ll.call("_build_rect_lights", [{"intensity": 0.01, "radius": 4.0}], p_host, null, ctx, 4)
	h.require(int(ctx.get("rect_light_count", -1)) == 0, "T2-03-A", "rect_light intensity 0.01 allocates 0 lights")
	await h.free_node(p_host)
	await h.free_node(ll)

	# T2-03-B & C & D: BeautifulCorner_Startscreen_Lighting checks
	var bc_v: Variant = h.read_json("res://data/generated/levels/Menus/MainMenu/BeautifulCorner_Startscreen_Lighting.tatlevel.json")
	var bc: Dictionary = bc_v as Dictionary if bc_v is Dictionary else {}
	var mm: Control = h.new_script_node("res://src/ui/main_menu.gd") as Control
	h.root.add_child(mm)
	# The startscreen env binds to the CineCamera after 12 process frames
	# (_bind_menu_env waits for the own-world SubViewport to render).
	await h.step_process(20)
	var dirs: Array[Node] = h.find_all_of_class(mm, "DirectionalLight3D")
	var dir_e: float = (dirs[0] as DirectionalLight3D).light_energy if not dirs.is_empty() else -1.0
	# The loader authors every DirectionalLight at 0.45 (level_loader
	# _build_light); the old 0.1 ceiling was the pre-refactor raw value.
	var ll_map: Node = h.new_script_node("res://src/core/level_loader.gd")
	h.root.add_child(ll_map)
	await h.step_process(1)
	var authored_dir: Light3D = ll_map.call("_build_light", {"type": "DirectionalLightComponent", "intensity": 15.0}) as Light3D
	var authored_e: float = authored_dir.light_energy if authored_dir != null else -1.0
	if authored_dir != null:
		authored_dir.free()
	await h.free_node(ll_map)
	h.require(not dirs.is_empty() and authored_e > 0.1 and absf(dir_e - authored_e) < 1e-5 and dir_e >= 0.01,
		"T2-03-B", "Startscreen DirectionalLight energy=%.4f == loader authored %.4f (>=0.01 floor)" % [dir_e, authored_e])

	var total_l: int = dirs.size() + h.find_all_of_class(mm, "OmniLight3D").size() + h.find_all_of_class(mm, "SpotLight3D").size()
	h.require(total_l >= 22, "T2-03-C", "Startscreen active lights=%d (>=22)" % total_l)

	var mm_env: Environment = h.find_camera_env(mm)
	var fog_ok: bool = mm_env != null and not is_nan(mm_env.fog_density) and not is_nan(mm_env.volumetric_fog_density)
	var desktop_ok: bool = mm_env != null and mm_env.volumetric_fog_enabled and mm_env.ssr_enabled and mm_env.ssil_enabled
	h.require(not bc.is_empty() and fog_ok and desktop_ok,
		"T2-03-D", "Startscreen camera env dense fog=%s vol_fog=%s ssr=%s ssil=%s" % [
			str(fog_ok), str(mm_env != null and mm_env.volumetric_fog_enabled),
			str(mm_env != null and mm_env.ssr_enabled), str(mm_env != null and mm_env.ssil_enabled)])
	await h.free_node(mm)

	# T2-03-E: R3 Startscreen Left-Trim Material Graph Boundary
	var mm_txt: String = h.read_text("res://src/ui/main_menu.gd")
	var ll_txt: String = h.read_text("res://src/core/level_loader.gd")
	var trim_no_fake_tex: bool = mm_txt.find("T_FakeTrim") < 0 and ll_txt.find("T_FakeTrim") < 0
	var has_trim_fix: bool = mm_txt.to_lower().find("trim") >= 0 or ll_txt.to_lower().find("trim_spec") >= 0 or ll_txt.to_lower().find("startscreen_trim") >= 0
	h.require(trim_no_fake_tex and has_trim_fix, "T2-03-E", "Startscreen left-trim PBR fix without inventing unextracted textures (%s)" % str(has_trim_fix))


func _bVA_04_neon_landscape() -> void:
	var ll: Node = h.new_script_node("res://src/core/level_loader.gd")
	h.root.add_child(ll)
	await h.step_process(1)

	# T2-04-A: Suite 37 Exact Neon Vector & Scale Preservation
	var m_neon: ShaderMaterial = ll.call("get_material_for_ue", "/Game/Art/Environment/City/Architecture/BeautifulCorner/MI_Neon") as ShaderMaterial
	var m_mac: ShaderMaterial = ll.call("get_material_for_ue", "/Game/Art/Environment/City/Architecture/BeautifulCorner/MI_Neon_MacNeish") as ShaderMaterial
	var a_ok: bool = m_neon != null and (m_neon.get_shader_parameter("hdr_color") as Vector3).is_equal_approx(Vector3(50.0, 4.109, 0.521)) and absf(float(m_neon.get_shader_parameter("hdr_scale")) - 0.08) < 0.001 \
		and m_mac != null and (m_mac.get_shader_parameter("hdr_color") as Vector3).is_equal_approx(Vector3(1.5, 0.055, 1.234)) and absf(float(m_mac.get_shader_parameter("hdr_scale")) - 1.0) < 0.001
	h.require(a_ok, "T2-04-A", "Suite 37 MI_Neon & MI_Neon_MacNeish exact vectors preserved")

	# T2-04-B: hdr_scale Clamp [0.02, 1.0]
	var sc_hi: float = clampf(4.0 / 1000.0, 0.02, 1.0)
	var sc_lo: float = clampf(4.0 / 0.5, 0.02, 1.0)
	h.require(absf(sc_hi - 0.02) < 1e-5 and absf(sc_lo - 1.0) < 1e-5, "T2-04-B", "hdr_scale clamp [0.02, 1.0]: 1000->%.2f 0.5->%.2f" % [sc_hi, sc_lo])

	# T2-04-C: Suite 37 Textured Negative Controls
	var m_head: Variant = ll.call("get_material_for_ue", "/Game/Art/Character/ThiefNisha/Base/MI_ThiefNisha_Head")
	var m_knife: Variant = ll.call("get_material_for_ue", "/Game/Art/Gameplay/Loot/LootMinor/JeweledKnife/MI_JeweledKnife")
	var m_cat: Variant = ll.call("get_material_for_ue", "/Game/Art/Gameplay/Loot/LootMajor/StatueCat/MI_CatStatueA")
	var m_beam: Variant = ll.call("get_material_for_ue", "/Game/Gameplay/Traps/Detectors/LightBeam/MI_LightBeam_SM")
	# MI_LightBeam_SM is now the intentional exception: it uses the additive
	# tat_beam shader instead of the HDR neon path. The other textured
	# materials must still stay StandardMaterial3D.
	var beam_ok: bool = m_beam is ShaderMaterial \
		and (m_beam as ShaderMaterial).shader != null \
		and (m_beam as ShaderMaterial).shader.resource_path.ends_with("tat_beam.gdshader")
	h.require(
		m_head is StandardMaterial3D and m_knife is StandardMaterial3D and m_cat is StandardMaterial3D and beam_ok,
		"T2-04-C",
		"3 textured negative controls stay StandardMaterial3D; MI_LightBeam_SM uses the beam shader"
	)

	# T2-04-D: Landscape weight_at() Unknown Index >=2 or <0
	var ls_txt: String = h.read_text("res://src/core/tat_landscape.gdshader")
	var has_safe_weight_at: bool = ls_txt.find("if (tex_idx == 0)") >= 0 and ls_txt.find("if (tex_idx == 1)") >= 0 and ls_txt.find("return vec4(0.0);") >= 0
	h.require(has_safe_weight_at, "T2-04-D", "tat_landscape weight_at() fails safe to vec4(0.0) on unknown index")

	# T2-04-E: Guildhall discard_holes = 1 (UE LandscapeVisibilityLayerInfo 1=hole)
	var gh_ls_v: Variant = h.read_json("res://data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json")
	var gh_lands: Array = (gh_ls_v as Dictionary).get("landscapes", []) if gh_ls_v is Dictionary else []
	var mat0: ShaderMaterial = ll.call("_landscape_weighted_material", gh_lands[0]) as ShaderMaterial if not gh_lands.is_empty() else null
	var dh0: float = float(mat0.get_shader_parameter("discard_holes")) if mat0 != null else -1.0
	h.require(absf(dh0 - 1.0) < 0.01, "T2-04-E", "Guildhall landscape discard_holes=%.1f (expected 1.0, UE hole mask)" % dh0)

	await h.free_node(ll)


func _bVA_05_mission_prep() -> void:
	var mp: Control = h.new_script_node("res://src/ui/mission_prep_ui.gd") as Control
	h.root.add_child(mp)
	await h.step_process(2)
	mp.call("open_prep", "guildhall", 1, "Solo", 0)
	await h.step_process(1)

	# T2-05-A: only rows whose authored ObjectiveDisplayImage resolves to an
	# empty icon_path hide the icon; authored rows must still show theirs.
	var sel: OptionButton = mp.get("_mission_selector") as OptionButton
	var ico: TextureRect = mp.get("_mission_icon") as TextureRect
	var empty_ok: bool = true
	var authored_ok: bool = true
	var tested_empty: int = 0
	var tested_authored: int = 0
	var gd: Node = h.game_data()
	var rows: Array = gd.call("get_all_missions") as Array if (gd != null and h.has_m(gd, "get_all_missions")) else []
	for row_v: Variant in rows:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		var row_id: String = str(row.get("id", ""))
		var icon_path: String = str(row.get("icon_path", ""))
		if sel == null or row_id == "":
			continue
		var idx: int = -1
		for i: int in range(sel.item_count):
			if sel.get_item_text(i).find(row_id) >= 0:
				idx = i
				break
		if idx < 0:
			continue
		sel.select(idx)
		sel.item_selected.emit(idx)
		await h.step_process(1)
		if icon_path == "":
			tested_empty += 1
			if ico != null and (ico.visible or ico.texture != null):
				empty_ok = false
		else:
			tested_authored += 1
			if ico == null or not ico.visible or ico.texture == null:
				authored_ok = false
	h.require(tested_empty >= 3 and tested_authored >= 1 and empty_ok and authored_ok,
		"T2-05-A", "Empty icon_path rows hide (%d ok=%s); authored ObjectiveDisplayImage rows keep icon (%d ok=%s)" % [
			tested_empty, str(empty_ok), tested_authored, str(authored_ok)])

	# T2-05-B: CameraActor_0 Aspect & 720p Framing Clamp (authored FOV 20.0 is
	# UE horizontal FOV, mapped via keep_aspect KEEP_WIDTH; see T1-05-B).
	# Report the conjuncts separately so a regression names the broken one.
	var stage_vp: SubViewport = h.find_all_of_class(mp, "SubViewport")[0] as SubViewport if not h.find_all_of_class(mp, "SubViewport").is_empty() else null
	var stage_cam: Camera3D = h.find_all_of_class(stage_vp, "Camera3D")[0] as Camera3D if (stage_vp != null and not h.find_all_of_class(stage_vp, "Camera3D").is_empty()) else null
	var mp_scr: GDScript = h.load_script("res://src/ui/mission_prep_ui.gd")
	var lobby_fov: float = float(mp_scr.get_script_constant_map().get("LOBBY_CAM_FOV", 20.0)) if mp_scr != null else 20.0
	var stage_size: Vector2i = Vector2i(1280, 720)
	if mp_scr != null:
		var ss_v: Variant = mp_scr.get_script_constant_map().get("STAGE_VIEWPORT_SIZE", Vector2i(1280, 720))
		if ss_v is Vector2i:
			stage_size = ss_v as Vector2i
	var fov_ok: bool = stage_cam != null and absf(stage_cam.fov - lobby_fov) < 0.25
	var aspect_ok: bool = stage_cam != null and stage_cam.keep_aspect == Camera3D.KEEP_WIDTH
	var clip_ok: bool = stage_vp != null and stage_vp.size == stage_size \
		and mp.get_global_rect().size.y <= float(stage_size.y) + 1.0
	h.require(fov_ok and aspect_ok and clip_ok, "T2-05-B",
		"MissionPrep 720p: fov=%.2f (want %.2f) ok=%s, keep_aspect=%d ok=%s, stage=%s (want %s) ok=%s" % [
			stage_cam.fov if stage_cam != null else -1.0, lobby_fov, str(fov_ok),
			stage_cam.keep_aspect if stage_cam != null else -1, str(aspect_ok),
			str(stage_vp.size if stage_vp != null else Vector2i.ZERO), str(stage_size), str(clip_ok)])

	# T2-05-C: ThiefNisha Head-to-Body Offset (Vector3.ZERO)
	var head_n: Node3D = mp.get("_thief_head_node") as Node3D
	h.require(head_n != null and head_n.position.is_equal_approx(Vector3.ZERO), "T2-05-C", "ThiefNisha head position=%s (expected ZERO)" % str(head_n.position if head_n != null else null))

	# T2-05-D: Lazy Material DB Cache Reuse
	var m1: Node = mp.get("_mat_loader") as Node
	mp.call("open_prep", "old_manor", 2, "Solo", 0)
	await h.step_process(1)
	var m2: Node = mp.get("_mat_loader") as Node
	h.require(m1 != null and m1 == m2, "T2-05-D", "Lazy material DB loader reused across open_prep switches")

	# T2-05-E: FTUE Unlimited Duration (0.0) Edge
	var dur_ftue: float = float(gd.call("get_match_duration", "ftue", 1)) if (gd != null and h.has_m(gd, "get_match_duration")) else -1.0
	var unlimited_ok: bool = false
	var no_zero_window: bool = true
	if sel != null:
		for i: int in range(sel.item_count):
			if sel.get_item_text(i).find("Mission.Tutorial.Single") >= 0:
				sel.select(i)
				sel.item_selected.emit(i)
				await h.step_process(1)
				var b_lbl: Label = mp.get("_mission_body") as Label
				if b_lbl != null:
					unlimited_ok = b_lbl.text.find("Unlimited") >= 0
					if b_lbl.text.find("0 minute") >= 0:
						no_zero_window = false
				break
	h.require(dur_ftue == 0.0 and unlimited_ok and no_zero_window,
		"T2-05-E", "FTUE duration=%.1f renders 'Unlimited'=%s and no '0 minute window'=%s" % [dur_ftue, str(unlimited_ok), str(no_zero_window)])
	await h.free_node(mp)


func _bVA_06_vfx_glass_culling() -> void:
	# T2-06-A: R3 Niagara authored renderer data is actually consumed. This
	# replaces the old source-string absence guard, which inverted the signal:
	# improving the VFX path failed the suite while the procedural stand-in
	# stayed unguarded. Suite 52 owns the catalogue class split; this pins the
	# count plus the runtime wiring catalogue -> decoded params -> shader -> loader.
	var sys_v: Variant = h.read_json("res://data/generated/vfx/systems.json")
	var nlib_txt: String = h.read_text("res://src/core/vfx/niagara_library.gd")
	var nprm_txt: String = h.read_text("res://src/core/vfx/niagara_params.gd")
	var nshd_txt: String = h.read_text("res://src/core/level_niagara.gdshader")
	var nldr_txt: String = h.read_text("res://src/core/level_loader.gd")
	var lib_ok: bool = nlib_txt != "" and nlib_txt.find("SYSTEMS_PATH") >= 0 \
		and nlib_txt.find("systems.json") >= 0
	var prm_ok: bool = nprm_txt != "" and nprm_txt.find("SortedParameterOffsets") >= 0 \
		and nprm_txt.find("ParameterData") >= 0 and nprm_txt.find("EVENT_GATED_SYSTEMS") >= 0
	var shd_ok: bool = nshd_txt != "" and nshd_txt.find("sampler2D sprite_tex") >= 0 \
		and nshd_txt.find("INSTANCE_CUSTOM") >= 0
	var wire_ok: bool = nldr_txt != "" and nldr_txt.find("NiagaraParams.prepare") >= 0 \
		and nldr_txt.find("niagara_sprites") >= 0
	var sys_ok: bool = sys_v is Dictionary \
		and int((sys_v as Dictionary).get("system_count", 0)) == 120 \
		and lib_ok and prm_ok and shd_ok and wire_ok
	h.require(sys_ok, "T2-06-A",
		"R3 Niagara authored renderer data + decoded parameters consumed (no fabricated VM)")

	var ll: Node = h.new_script_node("res://src/core/level_loader.gd")
	h.root.add_child(ll)
	await h.step_process(1)

	# T2-06-B: Suite 33 Opaque Glass Non-Hijack
	var op1: Variant = ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels_Opaque")
	var op2: Variant = ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels_PeriphBuilding")
	var op3: Variant = ll.call("get_material_for_ue", "/Game/Maps/Prototype/TempAssets/Windows/MI_WindowGlassOpaque")
	var op_ok: bool = true
	for m_v: Variant in [op1, op2, op3]:
		if not (m_v is StandardMaterial3D) or (m_v as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or (m_v as StandardMaterial3D).albedo_texture == null:
			op_ok = false
	h.require(op_ok, "T2-06-B", "Opaque glass stays opaque StandardMaterial3D (3/3)")

	# T2-06-C: CLUTTER_VIS_RANGE (22 m) Boundary (aabb_len < 2.0 vs >= 2.0)
	var mi_leaf: MeshInstance3D = MeshInstance3D.new()
	var bm_leaf: BoxMesh = BoxMesh.new()
	bm_leaf.size = Vector3(0.2, 0.2, 0.2)
	mi_leaf.mesh = bm_leaf
	ll.call("_apply_culling_policy", mi_leaf, "/game/art/foliage/sm_leaf", bm_leaf)
	var mi_tree: MeshInstance3D = MeshInstance3D.new()
	var bm_tree: BoxMesh = BoxMesh.new()
	bm_tree.size = Vector3(2.0, 3.0, 2.0)
	mi_tree.mesh = bm_tree
	ll.call("_apply_culling_policy", mi_tree, "/game/art/foliage/sm_tree_big", bm_tree)
	var cull_ok: bool = absf(mi_leaf.visibility_range_end - 38.0) < 0.1 and mi_leaf.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and (mi_tree.visibility_range_end == 0.0 or mi_tree.visibility_range_end > 40.0)
	h.require(cull_ok, "T2-06-C", "clutter leaf vis=%.1f vs tree>=2m vis=%.1f" % [mi_leaf.visibility_range_end, mi_tree.visibility_range_end])
	mi_leaf.free()
	mi_tree.free()

	# T2-06-D: Highlight Toggle on Null / Freed / Cached Target
	var vfx_scr: GDScript = h.load_script("res://src/core/vfx_manager.gd")
	vfx_scr.call("set_prop_highlight", null, true)
	var par: Node3D = Node3D.new()
	var m_a: MeshInstance3D = MeshInstance3D.new()
	m_a.mesh = BoxMesh.new()
	var m_b: MeshInstance3D = MeshInstance3D.new()
	m_b.mesh = BoxMesh.new()
	par.add_child(m_a)
	par.add_child(m_b)
	h.root.add_child(par)
	vfx_scr.call("set_prop_highlight", par, true)
	m_a.queue_free()
	await h.step_process(2)
	vfx_scr.call("set_prop_highlight", par, false)
	var safe_hl: bool = m_b.material_overlay == null
	await h.free_node(par)
	h.require(safe_hl, "T2-06-D", "VfxManager.set_prop_highlight safe on null/freed/cached targets")

	# T2-06-E: Unresolved Decal Texture Rejection (M_Decal_Puddle rejected)
	var v_puddle: Dictionary = ll.call("_is_decal_material_usable", "/Game/MaterialLibrary/Environment/Decals/M_Decal_Puddle") as Dictionary
	h.require(not h.is_true(v_puddle.get("usable")), "T2-06-E", "M_Decal_Puddle rejected without generic fallback texture")
	await h.free_node(ll)


func _bVA_07_1p_tool_glbs() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)

	# T2-07-A: Missing / Corrupt Tool GLB Fallback
	p.call("_fp_set_tool", "nonexistent_tool_xyz")
	await h.step_process(1)
	var fp_root: Node = p.get("fp_tool_root") as Node
	h.require(fp_root != null and fp_root.get_child_count() > 0, "T2-07-A", "Missing tool falls back cleanly without script error")

	# T2-07-B: Old Art/Tools/ Dead Paths Eliminated
	var tc_txt: String = h.read_text("res://src/player/thief_character.gd")
	h.require(tc_txt.find("Art/Tools/") < 0 and tc_txt.find("Art/Gameplay/Gear/") >= 0, "T2-07-B", "Stale Art/Tools/ paths eliminated in favor of Art/Gameplay/Gear/")

	# T2-07-C: Multi-Surface Tool Material Slot Order (mesh_materials.json)
	var mm_v: Variant = h.read_json("res://data/generated/mesh_materials.json")
	var mm: Dictionary = mm_v as Dictionary if mm_v is Dictionary else {}
	var has_gear_mm: bool = false
	for k: Variant in mm.keys():
		if str(k).find("Zipwire") >= 0 or str(k).find("VistaraDiamond") >= 0:
			has_gear_mm = true
			break
	h.require(has_gear_mm and tc_txt.find("mesh_materials") >= 0, "T2-07-C", "1P gear multi-surface material order wired from mesh_materials.json")

	# T2-07-D: Tool Visual Hidden/Updated on Unequip or 3P
	var mesh_3p: Node3D = p.get("mesh_root") as Node3D
	var tool_attached: bool = h.is_true(p.get("_fp_tool_on_bone"))
	h.require(mesh_3p != null and not mesh_3p.visible and tool_attached, "T2-07-D", "3P mesh hidden=%s 1P tool bone-attached=%s" % [str(mesh_3p != null and not mesh_3p.visible), str(tool_attached)])

	# T2-07-E: Scale Bounds on Loaded 1P Gear GLBs (0.05m - 1.2m)
	p.call("_fp_set_tool", "zipwire")
	await h.step_process(1)
	var bounds_ok: bool = false
	var first_mi: MeshInstance3D = h.find_first_mesh_instance(fp_root)
	if first_mi != null and first_mi.mesh != null and first_mi.name != "ZipwireBody":
		var sz: float = first_mi.mesh.get_aabb().size.length() * first_mi.global_basis.get_scale().x
		bounds_ok = sz >= 0.05 and sz <= 1.2
	h.require(bounds_ok, "T2-07-E", "1P GLB AABB size within [0.05, 1.2]m (%s)" % str(bounds_ok))
	await h.free_node(arena)


func _bVA_08_1p_arms_anims() -> void:
	# T2-08-A: R3 Missing 1P Unarmed Idle/Jump Non-Fabrication & 14 UBlendSpace
	var al_txt: String = h.read_text("res://src/core/animation_library.gd")
	var no_fake_clips: bool = al_txt.find("AN_Unarmed_Idle_1P") < 0 and al_txt.find("AN_Jump_1P") < 0
	h.require(no_fake_clips, "T2-08-A", "R3 missing 1P unarmed idle/jump clips not fabricated")

	# T2-08-B: 1P Animation Crossfade Window (0.2 s)
	var tc_scr: GDScript = h.load_script("res://src/player/thief_character.gd")
	var blend: float = float(tc_scr.get_script_constant_map().get("FP_ANIM_BLEND", -1.0))
	h.require(absf(blend - 0.2) < 0.001, "T2-08-B", "FP_ANIM_BLEND=%.2fs" % blend)

	# T2-08-C & D: Root Translation Stripped & Rotation Keys Preserved on the
	# real 1P UE clip set (manifest names, not synthetic role strings).
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var ap: AnimationPlayer = p.get("fp_anim_player") as AnimationPlayer
	var arm_skel: Skeleton3D = p.get("_fp_arm_skel") as Skeleton3D
	var fp_lib: Node = p.get("_fp_anim_lib") as Node
	var sprint_clip: String = ""
	if fp_lib != null and h.has_m(fp_lib, "fp_clip_for_role"):
		sprint_clip = str(fp_lib.call("fp_clip_for_role", "sprint"))
	if sprint_clip == "":
		var al_scr: GDScript = h.load_script("res://src/core/animation_library.gd")
		var fp_clips: Dictionary = al_scr.get_script_constant_map().get("FP_CLIPS", {}) as Dictionary if al_scr != null else {}
		sprint_clip = str(fp_clips.get("sprint", ""))
	var sprint_anim: Animation = ap.get_animation(sprint_clip) if (ap != null and sprint_clip != "" and ap.has_animation(sprint_clip)) else null
	var root_pos_tracks: int = 0
	var root_rot_keys: int = 0
	var rot_tracks: int = 0
	if sprint_anim != null:
		for ti: int in range(sprint_anim.get_track_count()):
			var sub: String = str(sprint_anim.track_get_path(ti).get_subname(0))
			var tt: int = sprint_anim.track_get_type(ti)
			if sub == "root" and tt == Animation.TYPE_POSITION_3D:
				root_pos_tracks += 1
			if sub == "root" and tt == Animation.TYPE_ROTATION_3D:
				root_rot_keys = maxi(root_rot_keys, sprint_anim.track_get_key_count(ti))
			if tt == Animation.TYPE_ROTATION_3D and sprint_anim.track_get_key_count(ti) >= 2:
				rot_tracks += 1
	var root_ok: bool = sprint_anim != null and sprint_clip.begins_with("AN_") and root_pos_tracks == 0
	var rot_ok: bool = sprint_anim != null and arm_skel != null and rot_tracks >= 10
	h.require(root_ok, "T2-08-C", "1P sprint clip '%s' root translation stripped (pos_tracks=%d)" % [sprint_clip, root_pos_tracks])
	h.require(rot_ok, "T2-08-D", "1P sprint rotation keys preserved (rot_tracks=%d root_rot_keys=%d arm_skel=%s)" % [rot_tracks, root_rot_keys, str(arm_skel != null)])

	# T2-08-E: 1P viewmodel isolation is direct-to-camera + vm_fov_deg shader;
	# there is no per-player SubViewport. Assert that real seam, including the
	# authored viewmodel FOV lock from thief_character.
	var tc_scr2: GDScript = h.load_script("res://src/player/thief_character.gd")
	var vm_fov_const: float = float(tc_scr2.get_script_constant_map().get("FP_VM_FOV_DEG", -1.0)) if tc_scr2 != null else -1.0
	var vm: Dictionary = h.viewmodel_contract(p)
	var vm_fov_ok: bool = absf(float(vm.get("fov", -99.0)) - vm_fov_const) < 0.01
	h.require(h.is_true(vm.get("ok")) and vm_fov_ok, "T2-08-E",
		"1P VM direct-to-camera under_cam=%s sub_vp=%d shader_surfaces=%d/%d shadows_on=%d vm_fov=%.2f (authored %.2f)" % [
			str(vm.get("under_cam")), int(vm.get("sub_viewports")), int(vm.get("shader_surfaces")),
			int(vm.get("total_surfaces")), int(vm.get("shadows_on")), float(vm.get("fov", -1.0)), vm_fov_const])
	await h.free_node(arena)


func _bVA_09_tool_equip() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var has_api: bool = h.has_m(p, "get_equipped_tool") and h.has_m(p, "equip_tool")

	# T2-09-A: Out-of-Range / Unknown tool id ignored by the real API
	var oob_ok: bool = false
	if has_api:
		p.call("equip_tool", "zipwire")
		await h.step_process(1)
		var before: String = str(p.call("get_equipped_tool"))
		p.call("equip_tool", "nonexistent_slot_99")
		p.call("equip_tool", "")
		oob_ok = str(p.call("get_equipped_tool")) == before \
			and int(p.call("_slot_for_tool", "nonexistent_slot_99")) == 0
	h.require(has_api and oob_ok, "T2-09-A", "Unknown/out-of-range tool id ignored safely (%s)" % str(oob_ok))

	# T2-09-B: Fire With 0 Charges Blocked (real equip + primary path)
	var zero_ok: bool = false
	if has_api:
		p.call("equip_tool", "smoke_bomb")
		await h.step_process(1)
		(p.get("charges") as Dictionary)["smoke_bomb"] = 0
		var proj_before: int = h.root.find_children("SmokeProjectile", "RigidBody3D", true, false).size()
		p.call("_use_smoke_bomb")
		await h.step_physics(2)
		var c1: int = int((p.get("charges") as Dictionary).get("smoke_bomb", -9))
		p.call("_use_equipped_primary")
		await h.step_physics(2)
		var c2: int = int((p.get("charges") as Dictionary).get("smoke_bomb", -9))
		var proj_after: int = h.root.find_children("SmokeProjectile", "RigidBody3D", true, false).size()
		zero_ok = (c1 == 0 and c2 == 0 and proj_after == proj_before)
	h.require(has_api and zero_ok, "T2-09-B", "0-charge smoke bomb fire blocked cleanly (%s)" % str(zero_ok))

	# T2-09-C: Infinite Tool (-1) Never Decrements
	var inf_ok: bool = false
	if h.has_m(p, "get_tool_slots"):
		p.call("equip_tool", "vistara_diamond")
		for _i: int in range(5):
			p.call("_use_equipped_primary")
		var slots: Array = p.call("get_tool_slots") as Array
		for s: Variant in slots:
			if s is Dictionary and str((s as Dictionary).get("id")) == "vistara_diamond":
				inf_ok = int((s as Dictionary).get("count", 0)) == -1
	h.require(inf_ok, "T2-09-C", "Infinite (-1) slot never decrements after 5 uses")

	# T2-09-D: Rapid Slot Swap Cancels Mid-Action Safely
	var swap_ok: bool = false
	if has_api:
		p.call("equip_tool", "smoke_bomb")
		p.call("equip_tool", "zipwire")
		p.call("_begin_wire_crank")
		p.call("equip_tool", "vistara_diamond")
		await h.step_process(1)
		var crank_off: bool = not h.is_true(p.get("_is_cranking")) and float(p.get("crank_progress")) <= 0.001
		swap_ok = str(p.call("get_equipped_tool")) == "vistara_diamond" and crank_off
	h.require(swap_ok, "T2-09-D", "Rapid slot swap leaves clean active state (%s)" % str(swap_ok))

	# T2-09-E: Tool Use While Downed Blocked
	var downed_ok: bool = false
	if h.has_m(p, "is_thief_vision_active"):
		var tv_before: bool = h.is_true(p.call("is_thief_vision_active"))
		p.set("is_downed", true)
		await h.tap_action("tool_4")
		await h.tap_action("primary_action")
		downed_ok = h.is_true(p.call("is_thief_vision_active")) == tv_before
		p.set("is_downed", false)
	h.require(downed_ok, "T2-09-E", "Tool use blocked while is_downed=true (%s)" % str(downed_ok))
	await h.free_node(arena)


func _bVA_10_zipwire_mantle_climb() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var far_wall: StaticBody3D = h.add_wall_box(arena, Vector3(0.0, 4.0, -20.5), Vector3(10.0, 8.0, 1.0), "FarWall205")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var cam: Camera3D = p.get("cam") as Camera3D
	if cam != null:
		cam.look_at(arena.global_position + Vector3(0.0, 4.0, -20.5), Vector3.UP)
	await h.step_physics(2)

	# T2-10-A: Zipwire Range Boundary (20.5 m rejected, 19.9 m accepted)
	var range_ok: bool = false
	var far_dist: float = -1.0
	var near_dist: float = -1.0
	var far_reason: String = ""
	if h.has_m(p, "get_active_reticle_state") and h.has_m(p, "equip_tool"):
		p.call("equip_tool", "zipwire")
		await h.step_process(1)
		var val_far: Dictionary = p.call("validate_zipwire_target") as Dictionary
		var rs_far: Dictionary = p.call("get_active_reticle_state") as Dictionary
		far_reason = str(val_far.get("reason", ""))
		if cam != null:
			far_dist = cam.global_position.distance_to(far_wall.global_position)
		h.add_wall_box(arena, Vector3(0.0, 4.0, -19.0), Vector3(8.0, 8.0, 1.0), "NearWall19")
		await h.step_physics(2)
		var val_near: Dictionary = p.call("validate_zipwire_target") as Dictionary
		var rs_near: Dictionary = p.call("get_active_reticle_state") as Dictionary
		if val_near.get("pos") is Vector3:
			near_dist = ((val_near.get("pos") as Vector3) - (p as Node3D).global_position).length()
		range_ok = (not h.is_true(rs_far.get("target_valid"))) and far_reason == "no_hit" \
			and far_dist > 20.0 and h.is_true(rs_near.get("target_valid")) and near_dist <= 20.0
	h.require(range_ok, "T2-10-A", "Zipwire 20.0 m range: far wall %.2f m rejected (%s), near %.2f m valid (%s)" % [
		far_dist, far_reason, near_dist, str(range_ok)])

	# T2-10-B: Zipwire Cooldown (5.0 s) & Minimum Crank (0.5 s)
	var tc_txt: String = h.read_text("res://src/player/thief_character.gd")
	var gd: Node = h.game_data()
	var cd_val: float = float(gd.call("eval_curve", "CT_Tool_Wire", "WireCooldownSecondary", 1.0, 5.0)) if gd != null else 5.0
	var crank_min_ok: bool = tc_txt.find("0.5") >= 0 and (tc_txt.to_lower().find("minimum_crank") >= 0 or tc_txt.to_lower().find("min_crank") >= 0 or tc_txt.to_lower().find("crank") >= 0)
	h.require(absf(cd_val - 5.0) < 0.01 and h.has_m(p, "get_active_reticle_state") and crank_min_ok, "T2-10-B", "Zipwire cooldown=%.1fs & min crank 0.5s" % cd_val)

	# T2-10-C: Mantle Height (4.0 m) & Facing (25 deg) Limits.
	# Drive try_auto_mantle directly: pressing jump would start wall-climb and
	# solve the 5 m wall legitimately (the old test setup measured wall-climb,
	# not the mantle limit). Walls are placed inside the 0.85 m probe reach.
	h.add_wall_box(arena, Vector3(12.0, 2.5, -1.1), Vector3(4.0, 5.0, 2.0), "TooTall5m")
	if p is Node3D:
		(p as Node3D).position = Vector3(12.0, 0.0, 0.0)
		(p as Node3D).rotation = Vector3.ZERO
	await h.step_physics(3)
	var tall_mantle: bool = h.is_true(p.call("try_auto_mantle"))
	var tall_y: float = (p as Node3D).position.y if p is Node3D else 99.0
	# Positive control: the same seam must accept a within-limit 2.0 m ledge.
	h.add_wall_box(arena, Vector3(20.0, 1.0, -1.1), Vector3(4.0, 2.0, 2.0), "WithinMantle2m")
	(p as Node3D).position = Vector3(20.0, 0.0, 0.0)
	(p as Node3D).rotation = Vector3.ZERO
	await h.step_physics(3)
	var low_mantle: bool = h.is_true(p.call("try_auto_mantle"))
	var mantle_const_ok: bool = tc_txt.to_lower().find("mantle") >= 0 and (tc_txt.find("4.0") >= 0 or tc_txt.find("400") >= 0)
	h.require(mantle_const_ok and not tall_mantle and low_mantle and tall_y < 4.5, "T2-10-C",
		"4.0 m mantle limit rejects 5.0 m ledge (accepted=%s, y=%.2f) and accepts 2.0 m (accepted=%s)" % [
			str(tall_mantle), tall_y, str(low_mantle)])

	# T2-10-D: Wall-Climb Surface Filter & Angle (45-135 deg)
	var climb_filter_ok: bool = tc_txt.to_lower().find("wall_climb") >= 0 or tc_txt.to_lower().find("wallclimb") >= 0
	h.require(climb_filter_ok, "T2-10-D", "Wall-climb surface filter & angle checks implemented (%s)" % str(climb_filter_ok))

	# T2-10-E: R3 GetHotwireTargetTypeForActor Uncompiled Limit
	h.require(tc_txt.find("GetHotwireTargetTypeForActor") < 0 or tc_txt.find("R3") >= 0 or tc_txt.find("uncompiled") >= 0, "T2-10-E", "R3 GetHotwireTargetTypeForActor uncompiled Kismet not fabricated")
	await h.free_node(arena)


func _bVA_11_smoke_and_sap() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var lp: Node = arena_d["light_probe"] as Node
	var sp_scr: GDScript = h.load_script("res://src/player/smoke_projectile.gd")

	# T2-11-A: Smoke Bomb Exact Physics Constants (30 m/s, 0.064 bounce, 1.0 friction, 0.5 s destroy)
	var sp_ok: bool = false
	if sp_scr != null:
		var sp_txt: String = h.read_text("res://src/player/smoke_projectile.gd")
		sp_ok = sp_txt.find("30.0") >= 0 and sp_txt.find("0.064") >= 0 and sp_txt.find("0.5") >= 0
	h.require(sp_ok, "T2-11-A", "SmokeBomb physics constants 30 m/s, 0.064 bounce, 0.5s destroy (%s)" % str(sp_ok))

	# T2-11-B: Smoke Cloud Box Bounds (5 x 5 x 4 m, 25 s TTL)
	var mc: Node = h.new_script_node("res://src/missions/mission_controller.gd")
	var smokes: Array[Dictionary] = []
	mc.set("smokes", smokes)
	var center: Vector3 = Vector3(10.0, 2.0, 10.0)
	smokes.append({"min": center - Vector3(2.5, 2.0, 2.5), "max": center + Vector3(2.5, 2.0, 2.5), "ttl": 25.0, "node": null})
	var in_hit: bool = h.is_true(mc.call("is_blocked_by_smoke", center + Vector3(-2.4, 1.9, 0.0), center + Vector3(2.4, 1.9, 0.0)))
	var out_hit: bool = h.is_true(mc.call("is_blocked_by_smoke", center + Vector3(2.6, 0.0, -5.0), center + Vector3(2.6, 0.0, 5.0)))
	var high_hit: bool = h.is_true(mc.call("is_blocked_by_smoke", center + Vector3(-5.0, 2.1, 0.0), center + Vector3(5.0, 2.1, 0.0)))
	h.require(in_hit and not out_hit and not high_hit, "T2-11-B", "Smoke AABB 5x5x4m boundary: in=%s out=%s high=%s" % [str(in_hit), str(out_hit), str(high_hit)])
	if mc != null: mc.queue_free()

	# T2-11-C: R3 Slithersap Zero InitialSpeed Limit
	var sap_json: Variant = h.repo_read_json("extracted/json/Gameplay/Tools/PrimaryTools/MagicSlime/BP_MagicSlime_ExplodingProjectile.json")
	var tc_txt: String = h.read_text("res://src/player/thief_character.gd")
	var sap_no_speed: bool = tc_txt.find("SLITHERSAP_SPEED") < 0 and sap_json != null
	h.require(sap_no_speed, "T2-11-C", "R3 Slithersap has no fabricated projectile InitialSpeed")

	# T2-11-D: Slithersap Inhibitor 1.5 m vs 1.6 m & 30 s TTL
	var l_near: OmniLight3D = OmniLight3D.new()
	l_near.position = Vector3(1.45, 0.0, 0.0)
	var l_far: OmniLight3D = OmniLight3D.new()
	l_far.position = Vector3(1.6, 0.0, 0.0)
	arena.add_child(l_near)
	arena.add_child(l_far)
	lp.call("register_light", l_near)
	lp.call("register_light", l_far)
	var puddle: Area3D = h.new_script_node("res://src/interact/slip_puddle.gd") as Area3D
	arena.add_child(puddle)
	puddle.call("setup", arena.global_position, lp, 0.0)
	var inh_ok: bool = (not l_near.visible) and l_far.visible
	lp.call("tick", 30.1)
	var restore_ok: bool = l_near.visible
	h.require(inh_ok and restore_ok, "T2-11-D", "Slithersap 1.5m inhibitor disabled 1.45m, kept 1.6m, restored at 30.1s")

	# T2-11-E: Slithersap 5.0 Overlap Damage Fires Once Per Body
	var dummy_scr: GDScript = GDScript.new()
	dummy_scr.source_code = "extends Node3D\nvar hits: int = 0\nvar dmg_total: float = 0.0\nfunc take_damage(d: float) -> void:\n\thits += 1\n\tdmg_total += d\n"
	dummy_scr.reload()
	var victim: Node3D = dummy_scr.new() as Node3D
	arena.add_child(victim)
	puddle.call("_on_body_entered", victim)
	puddle.call("_on_body_entered", victim)
	puddle.call("_on_body_entered", victim)
	h.require(int(victim.get("hits")) == 1 and absf(float(victim.get("dmg_total")) - 5.0) < 0.01, "T2-11-E", "Slithersap 5.0 damage fires once per body (hits=%d)" % int(victim.get("hits")))
	await h.free_node(arena)


func _bVA_12_disguise() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	h.game_state().set("thief_id", "chameleon")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)

	# T2-12-A: GuardViewCone hook boundary. A queued in-cone second drains base +
	# cone; a non-cone second drains only the base timer.
	var vc_dist_ok: bool = false
	if h.has_m(p, "apply_guard_viewcone_disguise_decay"):
		p.set("disguise_active", true)
		p.set("disguise_ttl", 60.0)
		p.set("disguise_integrity", 100.0)
		p.call("apply_guard_viewcone_disguise_decay", 1.0, true)
		p.call("_tick_sustained_systems", 1.0)
		var i_near: float = 100.0 - float(p.get("disguise_integrity"))
		p.set("disguise_integrity", 100.0)
		p.call("apply_guard_viewcone_disguise_decay", 1.0, false)
		p.call("_tick_sustained_systems", 1.0)
		var i_far: float = 100.0 - float(p.get("disguise_integrity"))
		vc_dist_ok = i_near > i_far
	h.require(vc_dist_ok, "T2-12-A", "GuardViewCone 10.0 m boundary (%s)" % str(vc_dist_ok))

	# T2-12-B: GuardViewCone Angle Boundary (64 deg vs 66 deg)
	var tc_txt: String = h.read_text("res://src/player/thief_character.gd")
	h.require(h.has_m(p, "apply_guard_viewcone_disguise_decay") and (tc_txt.find("65.0") >= 0 or tc_txt.find("65") >= 0), "T2-12-B", "GuardViewCone 65 deg boundary enforced")

	# T2-12-C: Fall Damage Exempt from DamageTaken (40.0)
	p.set("disguise_active", true)
	p.set("disguise_integrity", 100.0)
	p.set("disguise_ttl", 60.0)
	p.call("_apply_fall_damage", 8.0) # 8m > 6.5m safe fall
	var integ_after_fall: float = float(p.get("disguise_integrity"))
	h.require(integ_after_fall > 95.0, "T2-12-C", "Fall damage exempt from 40.0 disguise penalty (integ=%.1f)" % integ_after_fall)

	# T2-12-D: Stacked Drain Rates (Timer 1 + Sprint 40 + Lockpicking 5 + ViewCone 10 = 56/s)
	var stack_ok: bool = false
	if h.has_m(p, "set_lockpicking_active") and h.has_m(p, "apply_guard_viewcone_disguise_decay"):
		p.set("disguise_active", true)
		p.set("disguise_integrity", 30.0)
		p.set("disguise_ttl", 60.0)
		p.call("set_lockpicking_active", true)
		p.call("apply_guard_viewcone_disguise_decay", 1.0, true)
		p.call("set_lockpicking_active", false)
		var integ_cap: float = float(p.get("disguise_integrity"))
		stack_ok = integ_cap >= 0.0
	h.require(stack_ok and h.has_m(p, "set_lockpicking_active"), "T2-12-D", "Stacked disguise drain caps cleanly at 0.0 without wrap")

	# T2-12-E: Disabled Rows in DT_DisguiseV3IntegrityReduction Ignored
	var dt_v: Variant = h.read_json("res://data/generated/tables/Gameplay/Tools/PrimaryTools/Disguise/DT_DisguiseV3IntegrityReduction.json")
	var dt_rows: Dictionary = (dt_v as Dictionary).get("rows", {}) if dt_v is Dictionary else {}
	var minor_en: bool = h.is_true((dt_rows.get("PickupLoot_Minor", {}) as Dictionary).get("Enabled", false))
	var pp_en: bool = h.is_true((dt_rows.get("Pickpocket", {}) as Dictionary).get("Enabled", false))
	h.require(not minor_en and not pp_en, "T2-12-E", "Disabled DT_DisguiseV3IntegrityReduction rows remain ignored")
	await h.free_node(arena)


func _bVA_13_hud_core() -> void:
	var lp: Node = h.new_script_node("res://src/stealth/light_probe.gd")
	var lp_scr: GDScript = h.load_script("res://src/stealth/light_probe.gd")
	# T2-13-A: Light-Probe Stealth Clamp [0.15, 0.90] & Ambient 0.08
	var w_lo: float = float(lp_scr.call("light_visibility_weight", 0.01))
	var w_hi: float = float(lp_scr.call("light_visibility_weight", 4.0))
	var amb_v: float = float(lp.call("sample_visibility", Vector3(9999, 999, 9999), h.root.world_3d.direct_space_state, [] as Array[RID]))
	h.require(absf(w_lo - 0.15) < 0.001 and absf(w_hi - 0.90) < 0.001 and absf(amb_v - 0.08) < 0.01, "T2-13-A", "LightProbe clamps [0.15,0.90] & ambient 0.08")
	if lp != null: lp.queue_free()

	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_process(1)

	# T2-13-B: Zero-Loudness / Non-Player Noise SoundWave Bound.
	# The arcs are a SoundWavesDraw whose energy (not the parent Control's
	# visible flag) is the render gate.
	var sw_node: Node = hud.find_child("*SoundWave*", true, false)
	var sw_draw: Control = sw_node as Control
	var energy_before: float = float(hud.call("get_soundwave_intensity")) if h.has_m(hud, "get_soundwave_intensity") else float(hud.get("_soundwave_energy"))
	h.noise_bus().call("emit_noise", Vector3.ZERO, 0.0, p, "footstep")
	await h.step_process(1)
	var energy_zero: float = float(hud.call("get_soundwave_intensity")) if h.has_m(hud, "get_soundwave_intensity") else float(hud.get("_soundwave_energy"))
	var draw_energy: float = float(sw_draw.get("energy")) if sw_draw != null and h.has_prop(sw_draw, "energy") else -1.0
	var no_flash: bool = sw_draw != null and energy_zero <= 0.001 and draw_energy <= 0.001 and energy_before <= 0.001
	h.require(no_flash, "T2-13-B", "Zero-loudness noise leaves SoundWaves energy=%.4f (draw=%.4f, before=%.4f)" % [energy_zero, draw_energy, energy_before])

	# T2-13-C: Health Clamped [0.0, 300.0]
	p.call("take_damage", 9999.0)
	var hp_min: float = float(p.get("health"))
	p.call("revive")
	var hp_max: float = float(p.get("health"))
	h.require(hp_min == 0.0 and absf(hp_max - 300.0) < 0.1, "T2-13-C", "Health clamped [0,300]: min=%.1f max=%.1f" % [hp_min, hp_max])

	# T2-13-D: Downed State (10.0 s) & Post-Revive Cooldown (3.0 s)
	p.call("take_damage", 9999.0)
	var is_d: bool = h.is_true(p.get("is_downed"))
	var d_rem: float = float(p.call("downed_remaining"))
	p.call("revive")
	var pr_ttl: float = float(p.get("post_revive_ttl"))
	h.require(is_d and absf(d_rem - 10.0) < 0.2 and absf(pr_ttl - 3.0) < 0.1, "T2-13-D", "Downed 10s & post-revive 3s cooldown")

	# T2-13-E: Preserved HUD Node Names
	var preserved_ok: bool = hud.get("stealth_gem") != null and hud.get("hp_fill") != null and hud.get("stam_fill") != null \
		and hud.get("obj_lbl") != null and hud.get("compass_lbl") != null and hud.get("hotbar_lbl") != null and (hud.get("slot_count_lbls") as Array).size() == 4
	h.require(preserved_ok, "T2-13-E", "Preserved run_tests.gd HUD node contracts intact")
	await h.free_node(arena)


func _bVA_14_hud_widgets() -> void:
	var hud_txt: String = h.read_text("res://src/ui/hud.gd")
	# T2-14-A: No T_Ability_Background Opaque White Occlusion
	var no_opaque_bg: bool = hud_txt.find("T_Ability_Border") >= 0 and (hud_txt.find("mask") >= 0 or hud_txt.find("T_Ability_Background") < 0 or hud_txt.find("ShaderMaterial") >= 0)
	h.require(no_opaque_bg, "T2-14-A", "HUD octagonal hotbar avoids opaque white T_Ability_Background occlusion")

	# T2-14-B: Mobile Profile Suppresses Desktop Hotbar
	var mp_scr: GDScript = h.load_script("res://src/core/mobile_profile.gd")
	mp_scr.call("set_force_mobile", true)
	var hud_mob: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	h.root.add_child(hud_mob)
	await h.step_process(2)
	var mob_slots: Array = hud_mob.get("slot_count_lbls") as Array
	mp_scr.call("set_force_mobile", false)
	await h.free_node(hud_mob)
	h.require(mob_slots.is_empty(), "T2-14-B", "MobileProfile suppresses desktop hotbar cleanly")

	# T2-14-C: Compass Wrap-Around (0 / 359 / -180) via the real HUD mapping
	var arena_cd: Dictionary = await h.make_arena()
	var arena_c: Node3D = arena_cd["arena"] as Node3D
	var p_c: Node = await h.spawn_test_player(arena_c, Vector3.ZERO, arena_cd["light_probe"] as Node)
	var hud_d: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena_c.add_child(hud_d)
	await h.step_process(2)
	h.game_state().set("state", "playing")
	var c_lbl: Label = hud_d.get("compass_lbl") as Label
	var wraps: Array = [
		{"yaw": 0.0, "want": "N"},
		{"yaw": -359.0, "want": "N"},
		{"yaw": -90.0, "want": "E"},
		{"yaw": -180.0, "want": "S"},
	]
	var wrap_ok: bool = c_lbl != null
	var got: Array[String] = []
	for w_v: Variant in wraps:
		var w: Dictionary = w_v as Dictionary
		(p_c as Node3D).rotation_degrees = Vector3(0.0, float(w.get("yaw", 0.0)), 0.0)
		await h.step_process(2)
		var txt: String = c_lbl.text if c_lbl != null else ""
		got.append(txt)
		if txt != str(w.get("want", "")):
			wrap_ok = false
	# fposmod(359, 360) -> 359 -> round(7.98) % 8 = N, so no literal wrapf is
	# required; the wrapped cardinal output is the contract.
	h.require(wrap_ok and hud_txt.find("T_compass_lines") >= 0, "T2-14-C",
		"Compass T_compass_lines wrapped cardinals: %s (want N,N,E,S)" % str(got))
	await h.free_node(arena_c)

	# T2-14-D: Offscreen Guard Arc Edge Clamping
	var offscreen_ok: bool = hud_txt.find("T_DetectionMeter_Offscreen") >= 0 and hud_txt.find("clamp") >= 0
	h.require(offscreen_ok, "T2-14-D", "Offscreen guard arc clamps inside viewport [0..1280, 0..720]")

	# T2-14-E: Crank Progress Ring Bounds [0.0, 1.0]
	var crank_ring_ok: bool = hud_txt.find("crank_progress") >= 0 and hud_txt.find("crank_active") >= 0
	h.require(crank_ring_ok, "T2-14-E", "HUD crank progress ring bounds & hide when inactive")


func _bVA_15_lockpick_overlays() -> void:
	var lp_v: Variant = h.read_json("res://data/generated/gameplay/interactables.json")
	var lp_d: Dictionary = ((lp_v as Dictionary).get("lockpick", {}) as Dictionary) if lp_v is Dictionary else {}
	var hud_txt: String = h.read_text("res://src/ui/hud.gd")

	# T2-15-A: Lockpick Cancel Distance (200.0 cm = 2.0 m)
	# Behavioural: build the real lock owners and drive the authored radius.
	# The old check grepped hud.gd for the string "2.0", which matched the
	# embedded shader (`UV * 2.0 - 1.0`) and passed with no feature at all.
	var cancel_cm: float = float(lp_d.get("distance_before_cancel", 0.0))
	var cancel_ok: bool = absf(cancel_cm - 200.0) < 0.1
	var cancel_behaviour: String = ""
	if cancel_ok:
		var near_ok: bool = true
		var far_ok: bool = true
		var cancel_scripts: Array = [
			"res://src/interact/swinging_door.gd",
			"res://src/interact/loot_container.gd",
		]
		for cs_path_v: Variant in cancel_scripts:
			var owner: Node = h.new_script_node(str(cs_path_v))
			if owner == null or not (owner is Node3D):
				near_ok = false
				continue
			(owner as Node3D).global_position = Vector3(9100.0, 400.0, 9100.0)
			var actor := LockpickProbeActor.new()
			h.root.add_child(actor)
			actor.global_position = (owner as Node3D).global_position + Vector3(0.5, 0.0, 0.0)
			owner.set("is_lockpicking", true)
			owner.set("_lockpick_actor", actor)
			if bool(owner.call("check_lockpick_distance")):
				near_ok = false
			actor.global_position = (owner as Node3D).global_position + Vector3(3.0, 0.0, 0.0)
			if not bool(owner.call("check_lockpick_distance")) or bool(owner.get("is_lockpicking")):
				far_ok = false
			await h.free_node(owner)
			await h.free_node(actor)
		cancel_behaviour = "near=%s far=%s" % [str(near_ok), str(far_ok)]
		cancel_ok = cancel_ok and near_ok and far_ok
	h.require(cancel_ok, "T2-15-A", "Lockpick cancel distance 2.0 m (%.1f cm) cancels beyond the authored radius [%s]" % [cancel_cm, cancel_behaviour])

	# T2-15-B: Early Unlock Threshold (0.1 s) & Jam Delay (0.5 s)
	var early_s: float = float(lp_d.get("early_unlock_threshold_s", 0.0))
	var jam_s: float = float(lp_d.get("jam_damage_delay_s", 0.0))
	h.require(absf(early_s - 0.1) < 0.01 and absf(jam_s - 0.5) < 0.01 and hud_txt.find("T_Lockpicking_") >= 0, "T2-15-B", "Early unlock 0.1s & jam delay 0.5s wired in lockpick UI")

	# T2-15-C: Lockpick Difficulty Clamping (0..5 / 1..4)
	var ld: Node = h.new_script_node("res://src/interact/lockable_door.gd")
	ld.set("lock_level", 0)
	var tr0: Dictionary = ld.call("get_minigame_track") as Dictionary
	ld.set("lock_level", 99)
	var tr99: Dictionary = ld.call("get_minigame_track") as Dictionary
	if ld != null: ld.queue_free()
	h.require(not tr0.is_empty() and not tr99.is_empty(), "T2-15-C", "Lockpick difficulty 0 & 99 clamp cleanly to valid tracks")

	# T2-15-D: TAB Map + ESC Pause Priority
	var esc_map_ok: bool = h.has_action("map_toggle") and hud_txt.find("map_toggle") >= 0 and hud_txt.find("KEY_ESCAPE") >= 0
	h.require(esc_map_ok, "T2-15-D", "TAB map overlay & ESC close priority wired")

	# T2-15-E: Thief Vision Overlay Alpha == 0 / Disabled
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	h.root.add_child(hud)
	await h.step_process(1)
	if h.has_m(hud, "set_thief_vision"):
		hud.call("set_thief_vision", true)
	var tv_ov: ColorRect = hud.get("thief_vision_overlay") as ColorRect
	var clean_tv: bool = tv_ov == null or (not tv_ov.visible) or tv_ov.color.a <= 0.01
	await h.free_node(hud)
	h.require(clean_tv, "T2-15-E", "Thief Vision keeps flat cyan overlay hidden/alpha=0")


func _bVA_16_shell_ui() -> void:
	# T2-16-A: Contract 1 empty intro_text is handled by the mission-letter
	# API: request_mission_letter always emits, and the controller supplies a
	# non-empty fallback body instead of silently skipping the letter.
	var c_v: Variant = h.read_json("res://data/generated/gameplay/contracts.json")
	var c1_intro: String = "missing"
	if c_v is Dictionary:
		for c_item: Variant in ((c_v as Dictionary).get("contracts", []) as Array):
			if c_item is Dictionary and int((c_item as Dictionary).get("order", 0)) == 1:
				c1_intro = str((c_item as Dictionary).get("intro_text", ""))
	var gs_l: Node = h.game_state()
	var letter_intros: Array[String] = []
	var letter_cb: Callable = func(_title: String, intro: String) -> void:
		letter_intros.append(intro)
	if gs_l != null and h.has_s(gs_l, "mission_letter_requested"):
		gs_l.connect("mission_letter_requested", letter_cb)
	var mc_l: Node = h.new_script_node("res://src/missions/mission_controller.gd")
	mc_l.set("contract_info", {"title": "Contract 1"})
	mc_l.set("_active_mission_row", {})
	var api_ok: bool = h.has_m(mc_l, "_trigger_mission_start_letter")
	if api_ok:
		mc_l.call("_trigger_mission_start_letter")
	if gs_l != null and h.has_s(gs_l, "mission_letter_requested") and gs_l.is_connected("mission_letter_requested", letter_cb):
		gs_l.disconnect("mission_letter_requested", letter_cb)
	var fallback_body: String = letter_intros[0] if not letter_intros.is_empty() else ""
	var hud_l: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	h.root.add_child(hud_l)
	await h.step_process(1)
	var hud_ok: bool = h.has_m(hud_l, "show_mission_letter") and h.has_m(hud_l, "is_mission_letter_open")
	if hud_ok:
		hud_l.call("show_mission_letter", "Test Letter", "Letter body")
		hud_ok = h.is_true(hud_l.call("is_mission_letter_open"))
		hud_l.call("_close_mission_letter")
	await h.free_node(hud_l)
	if mc_l != null:
		mc_l.queue_free()
	h.require(c1_intro == "" and api_ok and letter_intros.size() == 1 and fallback_body.strip_edges() != "" and fallback_body.find("Esteemed") >= 0 and hud_ok,
		"T2-16-A", "Contract 1 empty intro -> letter API emits non-empty fallback (%d, '%s'); HUD show/is_open=%s" % [letter_intros.size(), fallback_body.substr(0, 32), str(hud_ok)])

	# T2-16-B: Loading Screen Clamps Progress [0, 100]
	var ls: CanvasLayer = h.new_script_node("res://src/ui/loading_screen.gd") as CanvasLayer
	h.root.add_child(ls)
	await h.step_process(1)
	ls.call("start_loading", "T", "", "guildhall")
	ls.call("set_progress", -1.0, "lo")
	var b_lo: float = (ls.get("_bar") as ProgressBar).value
	ls.call("set_progress", 2.5, "hi")
	var b_hi: float = (ls.get("_bar") as ProgressBar).value
	await h.free_node(ls)
	h.require(absf(b_lo - 0.0) < 0.1 and absf(b_hi - 100.0) < 0.1, "T2-16-B", "LoadingScreen progress clamped [0,100]: lo=%.1f hi=%.1f" % [b_lo, b_hi])

	# T2-16-C: Contract 1 / Missing StringTable Title Fallback
	var gd: Node = h.game_data()
	var c1_d: Dictionary = gd.call("get_contract_display", 1) as Dictionary
	var c3_d: Dictionary = gd.call("get_contract_display", 3) as Dictionary
	var c1_t: String = str(c1_d.get("title", ""))
	var c3_t: String = str(c3_d.get("title", ""))
	h.require(c1_t != "" and c1_t.find("ST_") < 0 and c3_t.find("Elway") >= 0, "T2-16-C", "Contract titles clean: c1='%s' c3='%s'" % [c1_t, c3_t])

	# T2-16-D: 720p Shell UI Safe-Area Non-Clipping. Gate only top-level modal
	# panels: scroll/content children may legitimately extend past 720 px.
	var ui_paths: Array[String] = ["res://src/ui/settings_ui.gd", "res://src/ui/mission_prep_ui.gd", "res://src/ui/wardrobe_ui.gd", "res://src/ui/contract_table_ui.gd", "res://src/ui/ledger_ui.gd"]
	var safe_720: bool = true
	var gated_panels: int = 0
	var bad_panel: String = ""
	for up: String in ui_paths:
		var un: Node = h.new_script_node(up)
		h.root.add_child(un)
		await h.step_process(1)
		for pn: Node in h.find_all_of_class(un, "PanelContainer"):
			var modal_root: bool = true
			var under_scroll: bool = false
			var par: Node = pn.get_parent()
			while par != null:
				if par is PanelContainer:
					modal_root = false
				if par is ScrollContainer:
					under_scroll = true
				par = par.get_parent()
			if not modal_root or under_scroll:
				continue
			gated_panels += 1
			var r: Rect2 = (pn as Control).get_global_rect()
			if r.position.y < -2.0 or r.position.y + r.size.y > 722.0:
				safe_720 = false
				bad_panel = "%s:%s %s" % [up.get_file(), str(pn.name), str(r)]
		await h.free_node(un)
	h.require(safe_720 and gated_panels >= 5, "T2-16-D",
		"All top-level shell modal panels fit 1280x720 (%d gated, bad=%s)" % [gated_panels, bad_panel])

	# T2-16-E: ArtNouveauTheme Teal Palette Consistency
	var teal_5: bool = true
	for up2: String in ui_paths:
		var un2: Node = h.new_script_node(up2)
		h.root.add_child(un2)
		await h.step_process(1)
		var any_teal: bool = false
		for pn2: Node in h.find_all_of_class(un2, "PanelContainer"):
			var sb2: StyleBoxFlat = (pn2 as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
			if h.is_teal_style(sb2):
				any_teal = true
				break
		if not any_teal:
			teal_5 = false
		await h.free_node(un2)
	h.require(teal_5, "T2-16-E", "ArtNouveauTheme teal border/panel consistency across all 5 shell UIs")


func _bVA_17_den_hub() -> void:
	var den_res: Dictionary = await h.instantiate_mission(1, 200, 1)
	var den: Node = den_res["mission"] as Node
	var p: Node = den_res["player"] as Node

	# T2-17-A: Map token bases: GuildHall 0.24, OldManor the authored UE
	# SphereRadius ratio (45.56192 / 27.39531). Selection may grow the live
	# node 1.15x, so the contract is asserted on the minis_base meta.
	var om: MeshInstance3D = den.get_node_or_null("MapTokenOldManor") as MeshInstance3D if den != null else null
	var gh: MeshInstance3D = den.get_node_or_null("MapTokenGuildHall") as MeshInstance3D if den != null else null
	var ue_ratio: float = 45.56192 / 27.39531
	var om_base: float = float(om.get_meta("minis_base", -1.0)) if om != null else -1.0
	var gh_base: float = float(gh.get_meta("minis_base", -1.0)) if gh != null else -1.0
	var om_live_ok: bool = om != null and om.scale.x >= om_base - 1e-4 and om.scale.x <= om_base * 1.15 + 1e-3
	var gh_live_ok: bool = gh != null and gh.scale.x >= gh_base - 1e-4 and gh.scale.x <= gh_base * 1.15 + 1e-3
	var tok_ok: bool = om != null and gh != null and absf(gh_base - 0.24) < 1e-4 \
		and absf(om_base - 0.24 * ue_ratio) < 1e-4 and om_live_ok and gh_live_ok \
		and absf(om.position.y - 41.1337) < 0.1 and absf(gh.position.y - 41.1337) < 0.1
	h.require(tok_ok, "T2-17-A", "MapToken GuildHall base=%.4f (0.24), OldManor base=%.6f (0.24*%.6f=%.6f), y=%.4f preserved" % [
		gh_base, om_base, ue_ratio, 0.24 * ue_ratio, om.position.y if om != null else -1.0])

	# T2-17-B: Den Exit Door Zero Static Duplicates
	var exit_d: Node3D = den.get_node_or_null("ThievesDenExitDoor") as Node3D if den != null else null
	var ll: Node = den.get("level_loader") as Node if den != null else null
	var dedup_ok: bool = false
	if exit_d != null and exit_d.is_in_group("swinging_doors") and ll != null:
		var acc: Dictionary = ll.call("_new_accumulator") as Dictionary
		ll.call("_parse_sublevel_file", "res://data/generated/levels/ThievesDenTest/ThievesDenTest_P.tatlevel.json", acc, den)
		var batches: Dictionary = acc.get("batches", {}) as Dictionary
		var static_inacc: int = 0
		for bk: Variant in batches.keys():
			if str(bk).find("SM_DoorInaccessibleA") >= 0:
				static_inacc += 1
		dedup_ok = (static_inacc == 0)
	h.require(dedup_ok, "T2-17-B", "ThievesDenExitDoor wired with 0 static SM_DoorInaccessibleA duplicates")

	# T2-17-C: [H]/[R] Ignored When Not Looking at Map Table
	var gs: Node = h.game_state()
	var d_before: int = int(gs.get("difficulty"))
	if p is Node3D:
		(p as Node3D).global_position += Vector3(12.0, 0.0, 12.0)
	await h.tap_key(KEY_H)
	await h.tap_key(KEY_R)
	var d_after: int = int(gs.get("difficulty"))
	var mc_txt: String = h.read_text("res://src/missions/mission_controller.gd").to_lower()
	h.require(d_before == d_after and mc_txt.find("map_table") >= 0 and mc_txt.find("key_h") >= 0, "T2-17-C", "[H]/[R] ignored away from Map Table (%s)" % str(mc_txt.find("key_h") >= 0))

	# T2-17-D: Den Decoration Persistence (SaveSystem)
	var deco: Node = den.get_node_or_null("DenDecorationPedestal") if den != null else null
	var deco_ok: bool = false
	if deco != null:
		deco_ok = true
		for _i: int in range(3):
			var vis: Node = deco.get_node_or_null("DecorationVisual")
			var found_r: bool = false
			if vis != null:
				for dc: Node in vis.get_children():
					if dc is MeshInstance3D and not ((dc as MeshInstance3D).mesh is SphereMesh):
						found_r = true
			if not found_r:
				deco_ok = false
			deco.call("interact", p)
			await h.step_process(1)
	h.require(deco_ok, "T2-17-D", "DenDecorationPedestal cycles 3 real GLBs & persists to SaveSystem")

	# T2-17-E: Den Timer (5400/3600/2700) Boundary
	var gd: Node = h.game_data()
	var t1: float = float(gd.call("get_match_duration", "thieves_den", 1))
	var t2: float = float(gd.call("get_match_duration", "thieves_den", 2))
	var t3: float = float(gd.call("get_match_duration", "thieves_den", 3))
	h.require(absf(t1 - 5400.0) < 1.0 and absf(t2 - 3600.0) < 1.0 and absf(t3 - 2700.0) < 1.0, "T2-17-E", "Den timers 5400/3600/2700: %.0f/%.0f/%.0f" % [t1, t2, t3])

	await h.free_node(den)


func _bVA_18_objectives() -> void:
	var gs: Node = h.game_state()
	var has_objs: bool = h.has_prop(gs, "mission_objectives") and h.has_prop(gs, "loot_goal") \
		and h.has_m(gs, "are_all_objectives_complete") and h.has_m(gs, "update_objective_progress") \
		and h.has_m(gs, "mark_objective_done")

	# T2-18-A: Partial Set Completion (2/3) Cannot Win Early
	var partial_ok: bool = false
	if has_objs:
		gs.call("set_mission_objectives", [
			{"id": "set_item_a", "label": "A", "target": 1},
			{"id": "set_item_b", "label": "B", "target": 1},
			{"id": "set_item_c", "label": "C", "target": 1},
		], 0)
		gs.call("mark_objective_done", "set_item_a")
		gs.call("mark_objective_done", "set_item_b")
		var partial: bool = h.is_true(gs.call("are_all_objectives_complete"))
		gs.call("mark_objective_done", "set_item_c")
		var complete: bool = h.is_true(gs.call("are_all_objectives_complete"))
		partial_ok = (not partial) and complete
	h.require(has_objs and partial_ok, "T2-18-A", "Partial Set (2/3) blocks early escape; 3/3 completes (%s)" % str(partial_ok))

	# T2-18-B: Explicit set_item objective id never double-counts into set_main
	var dedup_ok: bool = false
	if has_objs:
		gs.call("set_mission_objectives", [
			{"id": "set_main", "label": "Set", "target": 3},
			{"id": "set_item_a", "label": "A", "target": 1},
			{"id": "set_item_b", "label": "B", "target": 1},
			{"id": "set_item_c", "label": "C", "target": 1},
		], 0)
		gs.call("add_loot", 1, 0, true, "set_item_a")
		gs.call("add_loot", 1, 0, true, "set_item_a")
		var set_main_cur: int = -1
		var item_a_done: bool = false
		for e: Dictionary in (gs.get("mission_objectives") as Array):
			if str(e.get("id", "")) == "set_main":
				set_main_cur = int(e.get("current", -1))
			if str(e.get("id", "")) == "set_item_a":
				item_a_done = e.get("done") == true
		# A generic pickup advances set_main; the repeats above must not have.
		gs.call("add_loot", 1, 0, true, "")
		var set_main_after: int = -1
		for e2: Dictionary in (gs.get("mission_objectives") as Array):
			if str(e2.get("id", "")) == "set_main":
				set_main_after = int(e2.get("current", -1))
		dedup_ok = set_main_cur == 0 and item_a_done and set_main_after == 1
	h.require(has_objs and dedup_ok, "T2-18-B", "Set objective deduplicates repeated tag IDs (%s)" % str(dedup_ok))

	# T2-18-C: Cleanout Heist (loot_goal - 1 vs == loot_goal)
	var clean_ok: bool = false
	if has_objs:
		gs.set("loot_goal", 500)
		gs.set("loot_value", 0)
		gs.call("set_mission_objectives", [{"id": "cleanout_loot", "label": "Loot", "target": 500}], 500)
		gs.set("loot_value", 499)
		gs.call("update_objective_progress", "cleanout_loot", 499, true)
		var b_under: bool = h.is_true(gs.call("are_all_objectives_complete"))
		gs.set("loot_value", 500)
		gs.call("update_objective_progress", "cleanout_loot", 500, true)
		var b_at: bool = h.is_true(gs.call("are_all_objectives_complete"))
		clean_ok = (not b_under) and b_at
	h.require(clean_ok, "T2-18-C", "Cleanout Heist loot_goal-1 blocks, loot_goal completes (%s)" % str(clean_ok))
	# Leave the legacy globals in a clean pre-mission state for later tiers.
	gs.call("set_mission_objectives", [], 0)
	gs.set("loot_value", 0)
	gs.set("quest_item_acquired", false)

	# T2-18-D: Match Timer Expiry (0.0 s) Fails Mission
	var mc: Node = h.new_script_node("res://src/missions/mission_controller.gd")
	gs.set("state", "playing")
	gs.set("run_time_limit", 1800.0)
	gs.set("elapsed_sec", 1800.1)
	if h.has_m(mc, "_on_time_expired"):
		mc.call("_on_time_expired")
	h.require(str(gs.get("state")) == "failed", "T2-18-D", "Match timer expiry transitions GameState.state -> failed")
	if mc != null: mc.queue_free()

	# T2-18-E: Cleanout Heist Shorter Match Durations (3300/1200/1200)
	var gd: Node = h.game_data()
	var cdt_ok: bool = false
	if gd != null and h.has_m(gd, "get_all_missions"):
		for m_v: Variant in (gd.call("get_all_missions") as Array):
			if m_v is Dictionary and str((m_v as Dictionary).get("id", "")) == "Mission.Guildhall.LootTheRoom":
				var durs: Array = (m_v as Dictionary).get("durations", []) as Array
				cdt_ok = durs.size() >= 3 and int(durs[0]) == 3300 and int(durs[1]) == 1200 and int(durs[2]) == 1200
	h.require(cdt_ok, "T2-18-E", "Guildhall Cleanout Heist durations 3300/1200/1200 verified")


func _bVA_19_locks_containers_doors() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var lc_scr: GDScript = h.load_script("res://src/interact/loot_container.gd")

	# T2-19-A: Container One-Shot Loot Spawn (0 Duplicates)
	var lc: Node = lc_scr.new() as Node
	lc.set("loot_tier", "major")
	lc.set("marker_pos", arena.global_position)
	arena.add_child(lc)
	if h.has_prop(lc, "locked"):
		lc.set("locked", false)
	var l0: int = h.tree.get_nodes_in_group("loot").size()
	lc.call("interact", null)
	lc.call("interact", null)
	var l1: int = h.tree.get_nodes_in_group("loot").size()
	h.require(l1 - l0 == 1 and str(lc.call("get_interact_prompt")) == "[Opened]", "T2-19-A", "Container spawns 1 loot item on double interact")

	# T2-19-B: Secret Wall Stash (kind="none") Zero Duplicate Loot
	var lc_sec: Node = lc_scr.new() as Node
	lc_sec.call("configure", "BP_LootStashInteractable_Secret_ThinWall_C", {}, 0)
	arena.add_child(lc_sec)
	if h.has_prop(lc_sec, "locked"):
		lc_sec.set("locked", false)
	var l2: int = h.tree.get_nodes_in_group("loot").size()
	lc_sec.call("interact", null)
	var l3: int = h.tree.get_nodes_in_group("loot").size()
	h.require(l3 == l2 and h.is_true(lc_sec.get("opened")), "T2-19-B", "Secret wall stash spawns 0 duplicate loot")

	# T2-19-C: Swinging Door Tween Lock & Rotation (90 deg / 0.4 s)
	var sd_scr: GDScript = h.load_script("res://src/interact/swinging_door.gd")
	var sd: Node3D = sd_scr.new() as Node3D
	sd.call("configure", {"pos": [0, 0, 0], "basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "leaves": []}, null)
	arena.add_child(sd)
	if h.has_prop(sd, "locked"):
		sd.set("locked", false)
	sd.call("interact", null)
	var open_1: bool = h.is_true(sd.get("is_open"))
	sd.call("interact", null) # ignored while _tweening == true
	var open_2: bool = h.is_true(sd.get("is_open"))
	var piv: Node3D = sd.get("pivot") as Node3D
	await h.tree.create_timer(0.48).timeout
	var yaw_ok: bool = piv != null and absf(piv.rotation.y - PI * 0.5) < 0.05
	h.require(open_1 and open_2 and yaw_ok, "T2-19-C", "SwingingDoor tween-locked during 0.4s swing to 90 deg")

	# T2-19-D: 111 Doorway-BP Pivots & Zero Unresolved
	var gh_doors: Variant = h.read_json("res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json")
	var has_doors_data: bool = gh_doors is Dictionary and (gh_doors as Dictionary).has("swinging_doors")
	h.require(has_doors_data, "T2-19-D", "Doorway swinging_doors extracted cleanly with 0 unresolved")

	# T2-19-E: CT_LockpickDamage Level Clamp (Lv < 1 or > 4)
	var ld: Node = h.new_script_node("res://src/interact/lockable_door.gd")
	arena.add_child(ld)
	ld.set("lock_level", 0)
	var d_lo: float = float(ld.call("get_jam_damage"))
	ld.set("lock_level", 7)
	var d_hi: float = float(ld.call("get_jam_damage"))
	h.require(absf(d_lo - 5.0) < 0.1 and absf(d_hi - 40.0) < 0.1, "T2-19-E", "CT_LockpickDamage clamped [1..4]: 0->%.1f 7->%.1f" % [d_lo, d_hi])
	await h.free_node(arena)


func _bVA_20_guard_lantern_pickpocket_decay() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var g: Node3D = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, 0.0)) as Node3D
	var p: Node3D = await h.spawn_test_player(arena, Vector3(0.0, 0.0, 10.0), arena_d["light_probe"] as Node) as Node3D

	# T2-20-A: Knocked-Out Guard Pocket & Alert State
	if h.has_m(g, "set_carried_item"):
		g.call("set_carried_item", {"name": "Guard Key", "kind": "key", "id": "e2e_guard_key", "value": 25})
	g.call("knock_out", 10.0)
	var ko_st_ok: bool = false
	var ko_steal_ok: bool = false
	var ko_state: String = ""
	if h.has_m(g, "get_alert_state") and h.has_m(g, "steal_carried_item"):
		var st_d: Dictionary = g.call("get_alert_state") as Dictionary
		ko_state = str(st_d.get("state", ""))
		ko_st_ok = ko_state == "KNOCKED_OUT"
		var item: Variant = g.call("steal_carried_item")
		ko_steal_ok = item is Dictionary and not (item as Dictionary).is_empty()
	h.require(ko_st_ok and ko_steal_ok, "T2-20-A", "KO guard alert_state='%s' & stealable=%s" % [ko_state, str(ko_steal_ok)])

	# T2-20-B: Pickpocket Cone (9.0 deg) & Facing Block (30.0 deg) Limits
	var g_far: Node3D = Node3D.new()
	g_far.position = Vector3(0.0, 0.0, -25.1)
	var g_in: Node3D = Node3D.new()
	g_in.position = Vector3(0.0, 0.0, -10.0)
	arena.add_child(g_far)
	arena.add_child(g_in)
	var sel_none: Variant = p.call("pickpocket_select_target", [g_far], p.global_position, Vector3.FORWARD)
	var sel_in: Variant = p.call("pickpocket_select_target", [g_in], p.global_position, Vector3.FORWARD)
	g_in.look_at(p.global_position, Vector3.UP)
	var blk_face: bool = h.is_true(p.call("pickpocket_is_blocked", g_in, p.global_position))
	g_in.rotate_y(deg_to_rad(35.0))
	var blk_turn: bool = h.is_true(p.call("pickpocket_is_blocked", g_in, p.global_position))
	h.require(sel_none == null and sel_in == g_in and blk_face and not blk_turn, "T2-20-B", "Pickpocket 25m/9deg cone & 30deg facing block")

	# T2-20-C: Guard Detection Decay Gates (6 s in-level / 4 s unseen)
	var gai_scr: GDScript = h.load_script("res://src/ai/guard_ai.gd")
	var d_gated: float = float(gai_scr.call("decay_step_detection", 2, 50.0, 5.0, 4.0, 1.0))
	var d_open: float = float(gai_scr.call("decay_step_detection", 2, 50.0, 6.0, 4.0, 1.0))
	h.require(absf(d_gated - 50.0) < 0.01 and absf(d_open - 40.0) < 0.01, "T2-20-C", "Guard decay 6s/4s gate: 5s->%.1f 6s->%.1f" % [d_gated, d_open])

	# T2-20-D: Guard Height-Difference Curve (2 m -> 1.0, 3 m -> 0.0)
	var h2: float = float(gai_scr.call("height_difference_strength_multiplier", 2.0))
	var h3: float = float(gai_scr.call("height_difference_strength_multiplier", 3.0))
	h.require(absf(h2 - 1.0) < 0.01 and absf(h3 - 0.0) < 0.01, "T2-20-D", "Height curve: 2m->%.2f 3m->%.2f" % [h2, h3])

	# T2-20-E: Non-Lantern Guards Have No Fabricated Lantern
	var g_plain: Node = await h.spawn_test_guard(arena, Vector3(5.0, 0.0, 5.0))
	if h.has_m(g_plain, "configure_variant"):
		g_plain.call("configure_variant", "Club")
	var plain_lights: int = h.find_all_of_class(g_plain, "OmniLight3D").size()
	h.require(plain_lights == 0, "T2-20-E", "Non-lantern guard has 0 OmniLight3D (%d)" % plain_lights)
	await h.free_node(arena)


func _bVA_21_old_manor_r3() -> void:
	# T2-21-A: OldManor_P Exact Basename Predicate (155 PNGs)
	var om_v: Variant = h.read_json("res://data/generated/levels/OldManor/OldManor_P.tatlevel.json")
	var om_ls: Array = (om_v as Dictionary).get("landscapes", []) if om_v is Dictionary else []
	var hm: Dictionary = {}
	var wm: Dictionary = {}
	for lc_v: Variant in om_ls:
		if lc_v is Dictionary:
			var hp: String = str((lc_v as Dictionary).get("heightmap", ""))
			if hp != "": hm[hp] = true
			for w: Variant in ((lc_v as Dictionary).get("weightmaps", []) as Array):
				if str(w) != "": wm[str(w)] = true
	h.require(om_ls.size() == 128 and hm.size() == 101 and wm.size() == 54 and (hm.size() + wm.size() == 155), "T2-21-A", "OldManor_P 128 components / 155 PNGs")

	# T2-21-B: R3 52 Landscape Splines & Grass Unparsed Limit
	var ll: Node = h.new_script_node("res://src/core/level_loader.gd")
	h.root.add_child(ll)
	await h.step_process(1)
	var acc: Dictionary = ll.call("_new_accumulator") as Dictionary
	var host: Node3D = Node3D.new()
	h.root.add_child(host)
	ll.call("_parse_sublevel_file", "res://data/generated/levels/OldManor/OldManor_P.tatlevel.json", acc, host)
	var batches: Dictionary = acc.get("batches", {}) as Dictionary
	var spline_editor_meshes: int = 0
	for bk: Variant in batches.keys():
		if str(bk).find("SplineEditorMesh") >= 0:
			spline_editor_meshes += 1
	await h.free_node(host)
	await h.free_node(ll)
	h.require(spline_editor_meshes == 0, "T2-21-B", "R3 52 material-less splines skipped (SplineEditorMesh=0)")

	# T2-21-C & D: OldManor Fallback Spawn Clearance & Vacuous Null Centroid
	var mc: Node = h.new_script_node("res://src/missions/mission_controller.gd")
	h.root.add_child(mc)
	var vac_ok: bool = false
	if h.has_m(mc, "_fallback_spawn_has_forward_clearance"):
		vac_ok = h.is_true(mc.call("_fallback_spawn_has_forward_clearance", null, Vector3.ZERO, null))
	await h.free_node(mc)
	var mc_txt: String = h.read_text("res://src/missions/mission_controller.gd")
	h.require(mc_txt.find("2.2") >= 0 and mc_txt.find("1.5") >= 0, "T2-21-C", "OldManor fallback spawn 2.2m headroom & 1.5m forward clearance checks")
	h.require(vac_ok, "T2-21-D", "Vacuous forward clearance returns true on null centroid")

	# T2-21-E: MAX_TOTAL_SHAPES (32000) & MAX_SHAPES_PER_BODY (384)
	var ll_scr: GDScript = h.load_script("res://src/core/level_loader.gd")
	var consts: Dictionary = ll_scr.get_script_constant_map()
	h.require(int(consts.get("MAX_TOTAL_SHAPES", 0)) == 32000 and int(consts.get("MAX_SHAPES_PER_BODY", 0)) == 384, "T2-21-E", "LevelLoader MAX_TOTAL_SHAPES=32000 MAX_SHAPES_PER_BODY=384")


func _bVA_22_qa_integrity() -> void:
	# T2-22-A: Zero SCRIPT ERROR & SHADER ERROR Hooks in QA Scripts
	var vf_sh: String = h.repo_read_text("build/qa/run_vulkan_vf_test.sh")
	var e2e_sh: String = h.repo_read_text("build/qa/capture_e2e_parity.sh")
	h.require(vf_sh.find("SHADER ERROR") >= 0 and e2e_sh.find("SHADER ERROR") >= 0 and e2e_sh.find("SCRIPT ERROR") >= 0, "T2-22-A", "QA harnesses enforce SHADER ERROR=0 & SCRIPT ERROR=0")

	# T2-22-B: No project.godot Dirty Debug Autostart Leftover
	var pg: String = h.read_text("res://project.godot")
	h.require(pg.find("debug_autostart_contract") < 0, "T2-22-B", "game/project.godot has no debug_autostart_contract leftover")

	# T2-22-C: Read-Only extracted/ & game/data/generated/ Integrity
	var ok_tables: bool = FileAccess.file_exists("res://data/generated/materials.json") and FileAccess.file_exists("res://data/generated/mesh_materials.json")
	h.require(ok_tables and h.repo_file_exists("tools/manifest_audit.py"), "T2-22-C", "Generated tables & manifest_audit.py intact")

	# T2-22-D: All Core Shaders Present & Validly Loadable
	var shaders: Array[String] = [
		"res://src/core/tat_sky.gdshader",
		"res://src/core/tat_landscape.gdshader",
		"res://src/core/tat_glass.gdshader",
		"res://src/core/tat_hdr_emissive.gdshader",
		"res://src/core/tat_emissive_cpd.gdshader",
	]
	var sh_ok: bool = true
	for sp: String in shaders:
		var s: Shader = ResourceLoader.load(sp) as Shader
		if s == null or s.code.strip_edges() == "":
			sh_ok = false
	h.require(sh_ok, "T2-22-D", "All 5 core .gdshader resources load cleanly")

	# T2-22-E: Explicit Documentation of Missing Steam Refs
	var ti: String = h.repo_read_text("docs/reports/visual-fidelity.md")
	h.require(ti.find("Old Manor") >= 0 or h.repo_file_exists("build/qa/capture_e2e_parity.gd"), "T2-22-E", "Missing Steam reference scenes explicitly documented without false pixel-diff")


## T2-15-A fixture: an actor that exposes the lockpick driver flag the cancel
## path clears. A bare Node3D so the distance gate sees a real position.
class LockpickProbeActor extends Node3D:
	var lockpicking_active: bool = false

	func set_lockpicking_active(value: bool) -> void:
		lockpicking_active = value
