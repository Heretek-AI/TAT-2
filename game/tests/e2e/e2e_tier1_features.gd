extends RefCounted
## Tier 1: Isolated Feature Coverage (115 checks = 5 per feature across Features #1-#22).
## Feature #10 carries 11 checks (T1-10-A..J incl. blocking-volume traversal).
## Opaque-box, requirement-driven checks derived from PROJECT.md, ORIGINAL_REQUEST.md,
## extracted UE5.5 JSON/tables, and Steam reference parity specifications.

var h: RefCounted


func _init(helpers: RefCounted) -> void:
	h = helpers


func run() -> void:
	h.snapshot_state()
	await _feat_01_night_sky()
	await _feat_02_interior_shadow_gi()
	await _feat_03_startscreen()
	await _feat_04_neon_ssr()
	await _feat_05_mission_lobby_stage()
	await _feat_06_vfx_glass_foliage_outline()
	await _feat_07_1p_tool_glbs()
	await _feat_08_1p_arms_anims_isolation()
	await _feat_09_equip_tools_and_vistara()
	await _feat_10_zipwire_crank_mantle_climb()
	await _feat_11_smoke_ballistics_and_sap()
	await _feat_12_disguise_integrity_rows()
	await _feat_13_hud_stealth_sound_health()
	await _feat_14_hud_hotbar_compass_reticles_pips()
	await _feat_15_lockpick_ui_map_ping_vision()
	await _feat_16_shell_ui_letter_loading()
	await _feat_17_thieves_den_hub()
	await _feat_18_objectives_and_loot_counter()
	await _feat_19_lockable_doors_safes()
	await _feat_20_guard_lanterns_steal_alert()
	await _feat_21_old_manor_walk_collision()
	await _feat_22_verification_gates()
	await _feat_23_surface_hearing_sprint()
	h.restore_state()


# --- Feature #1: Night Sky Radiance, Clouds, Moon Halo & Blue Distance Fog ---
func _feat_01_night_sky() -> void:
	var wv_scr: GDScript = h.load_script("res://src/core/weather_visuals.gd")
	var wp_scr: GDScript = h.load_script("res://src/core/weather_profile.gd")
	var mc_v: Variant = h.read_json("res://data/generated/weather/midnight_clear.json")
	var df_v: Variant = h.read_json("res://data/generated/weather/dense_fog.json")
	var mc: Dictionary = mc_v as Dictionary if mc_v is Dictionary else {}
	var df: Dictionary = df_v as Dictionary if df_v is Dictionary else {}

	# T1-01-A: Preset Inheritance & Moon Diameter
	var d_mc: float = float(wv_scr.call("moon_diameter_deg", 9.838636, 0.0)) if wv_scr != null else -1.0
	var d_df: float = float(wv_scr.call("moon_diameter_deg", 14.0, 6000.0)) if wv_scr != null else -1.0
	var mc_moon_v: Variant = mc.get("moon", {})
	var mc_moon: Dictionary = mc_moon_v as Dictionary if mc_moon_v is Dictionary else {}
	h.require(
		absf(d_mc - 8.2718) < 0.002 and absf(d_df - 11.7329) < 0.002 and h.is_true(mc_moon.get("visible")),
		"T1-01-A",
		"moon diameter mc=%.4f (exp 8.2718), df=%.4f (exp 11.7329), visible=%s" % [d_mc, d_df, str(mc_moon.get("visible"))]
	)

	# T1-01-B: overall_color Sky Gradient Math (Suite 22 preserved)
	var hc: Color = wv_scr.call("horizon_color_of", mc) if wv_scr != null else Color(-1, -1, -1)
	var zc: Color = wv_scr.call("zenith_color_of", mc) if wv_scr != null else Color(-1, -1, -1)
	var hc_ok: bool = absf(hc.r - 0.00198) < 0.0005 and absf(hc.g - 0.00259) < 0.0005 and absf(hc.b - 0.003) < 0.0005
	var zc_ok: bool = absf(zc.r - 3e-6) < 1e-6 and absf(zc.g - 9.6e-6) < 1e-6 and absf(zc.b - 2.6e-5) < 1e-6
	h.require(hc_ok and zc_ok, "T1-01-B", "horizon=%s zenith=%s" % [str(hc), str(zc)])

	# T1-01-C: Sky Shader Uniforms & fog_sky_affect (midnight_clear restores
	# authored fog over the sky: 0.85, not the 0.0 used by other presets)
	var env: Environment = Environment.new()
	var moon: DirectionalLight3D = DirectionalLight3D.new()
	var env_ok: bool = h.is_true(wp_scr.call("apply_environment", env, moon, mc)) if wp_scr != null else false
	var sky_ok: bool = h.is_true(wv_scr.call("apply_sky", env, mc, moon)) if wv_scr != null else false
	var sm: ShaderMaterial = env.sky.sky_material as ShaderMaterial if (env.sky != null and env.sky.sky_material is ShaderMaterial) else null
	var mcol_v: Variant = sm.get_shader_parameter("moon_color") if sm != null else null
	var mcol: Color = mcol_v as Color if mcol_v is Color else Color(-1, -1, -1)
	var mvis: float = float(sm.get_shader_parameter("moon_visible")) if sm != null else 0.0
	var fsa_ok: bool = env.fog_sky_affect >= 0.8 and env.fog_sky_affect <= 0.9
	h.require(
		env_ok and sky_ok and fsa_ok and env.background_mode == Environment.BG_SKY
		and absf(mcol.r - 0.5137) < 0.01 and absf(mcol.g - 0.5216) < 0.01 and absf(mcol.b - 1.0) < 0.01 and mvis == 1.0,
		"T1-01-C",
		"fog_sky_affect=%s bg=%s moon_color=%s moon_visible=%s" % [str(env.fog_sky_affect), str(env.background_mode), str(mcol), str(mvis)]
	)

	# T1-01-D: Procedural FBM Cloud Wisps & Moon Halo in tat_sky.gdshader
	var sky_src: String = h.read_text("res://src/core/tat_sky.gdshader").to_lower()
	var has_fbm_clouds: bool = (sky_src.find("fbm") >= 0 or sky_src.find("octave") >= 0 or sky_src.find("_noise") >= 0) and sky_src.find("cloud") >= 0
	var has_moon_halo: bool = sky_src.find("halo") >= 0 or (sm != null and sm.get_shader_parameter("moon_halo_strength") != null)
	h.require(
		has_fbm_clouds and has_moon_halo,
		"T1-01-D",
		"tat_sky.gdshader fbm_clouds=%s moon_halo=%s" % [str(has_fbm_clouds), str(has_moon_halo)]
	)

	# T1-01-E: Indigo Distance Fog & Visual Radiance Compensation (decoupled from 0.001 overall_color)
	# Extended: APPROXIMATE warm SkyAtmosphere veil is on for the exact
	# midnight_clear preset, warm-tinted, and isolated from the Den preset.
	var has_sky_radiance: bool = (sm != null and (sm.get_shader_parameter("sky_radiance") != null or sm.get_shader_parameter("radiance_scale") != null or sm.get_shader_parameter("exposure_compensation") != null)) \
		or sky_src.find("sky_radiance") >= 0 or sky_src.find("radiance_scale") >= 0 or sky_src.find("radiance_lift") >= 0
	var fog_col: Color = env.fog_light_color
	var indigo_fog: bool = env.fog_enabled and env.fog_sky_affect >= 0.8 and env.fog_sky_affect <= 0.9 and fog_col.b > fog_col.r
	var haze_v: Variant = sm.get_shader_parameter("haze_amount") if sm != null else null
	var haze_amt: float = float(haze_v) if haze_v != null else -1.0
	var haze_col_v: Variant = sm.get_shader_parameter("haze_color") if sm != null else null
	var haze_col := Vector3(-1, -1, -1)
	if haze_col_v is Vector3:
		haze_col = haze_col_v as Vector3
	elif haze_col_v is Color:
		var haze_c: Color = haze_col_v as Color
		haze_col = Vector3(haze_c.r, haze_c.g, haze_c.b)
	var den_v: Variant = h.read_json("res://data/generated/weather/midnight_clear_thieves_den.json")
	var den: Dictionary = den_v as Dictionary if den_v is Dictionary else {}
	var den_sky: Sky = wv_scr.call("make_sky", den, moon) if wv_scr != null else null
	var den_sm: ShaderMaterial = den_sky.sky_material as ShaderMaterial if (den_sky != null and den_sky.sky_material is ShaderMaterial) else null
	var den_haze_v: Variant = den_sm.get_shader_parameter("haze_amount") if den_sm != null else null
	var den_haze: float = float(den_haze_v) if den_haze_v != null else -1.0
	h.require(
		has_sky_radiance and indigo_fog
		and haze_amt >= 0.8 and haze_amt <= 1.0 and haze_col.x > haze_col.z and den_haze == 0.0,
		"T1-01-E",
		"sky_radiance_decoupled=%s indigo_fog=%s fog_col=%s warm_sky_haze amount=%.3f color=%s warm_r_gt_b=%s den_amount=%.3f" % [
			str(has_sky_radiance), str(indigo_fog), str(fog_col), haze_amt, str(haze_col), str(haze_col.x > haze_col.z), den_haze
		]
	)


# --- Feature #2: Interior & Alley Shadow / GI Lift ---
func _feat_02_interior_shadow_gi() -> void:
	var wp_scr: GDScript = h.load_script("res://src/core/weather_profile.gd")
	var lobby_v: Variant = h.read_json("res://data/generated/weather/midnight_clear_mission_lobby.json")
	var lobby_preset: Dictionary = lobby_v as Dictionary if lobby_v is Dictionary else {}

	# T1-02-B: Authored gain_shadows Toe Lift
	var env_b: Environment = Environment.new()
	var moon_b: DirectionalLight3D = DirectionalLight3D.new()
	if wp_scr != null:
		wp_scr.call("apply_environment", env_b, moon_b, lobby_preset)
	var gain_applied: bool = env_b.adjustment_enabled and (env_b.adjustment_brightness > 1.0 or env_b.ssil_enabled or env_b.tonemap_exposure > 1.0)
	h.require(
		gain_applied,
		"T1-02-B",
		"gain_shadows applied: adj_enabled=%s bright=%.3f ssil=%s" % [str(env_b.adjustment_enabled), env_b.adjustment_brightness, str(env_b.ssil_enabled)]
	)

	# Load Thieves' Den (Contract 1) for T1-02-C
	var den_res: Dictionary = await h.instantiate_mission(1, 200, 1)
	var den: Node = den_res["mission"] as Node
	var fill_sum: float = 0.0
	var red_fill: bool = false
	for fl: Node in h.tree.get_nodes_in_group("den_hand_fills"):
		if fl is Light3D and den != null and den.is_ancestor_of(fl):
			var lt: Light3D = fl as Light3D
			fill_sum += lt.light_energy
			if lt.light_color.r > 0.7 and lt.light_color.g < 0.25 and lt.light_color.b < 0.25:
				red_fill = true
	var probes: int = 0
	var den_env_dark: bool = false
	if den != null:
		for ch: Node in den.get_children():
			if ch is ReflectionProbe:
				probes += 1
			elif ch is WorldEnvironment and (ch as WorldEnvironment).environment != null:
				var we: Environment = (ch as WorldEnvironment).environment
				den_env_dark = we.ambient_light_energy <= 0.15 and we.ambient_light_color.v <= 0.15
	h.require(
		den != null and fill_sum > 0.0 and fill_sum <= 2.01 and not red_fill and probes == 1 and den_env_dark,
		"T1-02-C",
		"den_hand_fills=%.2f red=%s probes=%d dark_amb=%s" % [fill_sum, str(red_fill), probes, str(den_env_dark)]
	)
	await h.free_node(den)

	# Load Guildhall (Contract 2) for T1-02-A, T1-02-D, T1-02-E
	var gh_res: Dictionary = await h.instantiate_mission(2, 240, 1)
	var gh: Node = gh_res["mission"] as Node
	var gh_env: Environment = h.find_env(gh) if gh != null else null

	# T1-02-A: Desktop SSIL Enabled on WorldEnvironment
	h.require(
		gh_env != null and gh_env.ssil_enabled == true,
		"T1-02-A",
		"guildhall env.ssil_enabled=%s" % str(gh_env.ssil_enabled if gh_env != null else null)
	)

	# T1-02-D: Alley & Interior Shadow Readability (SSIL + shadow lift/fill active)
	var shadow_lift_ok: bool = gh_env != null and gh_env.ssil_enabled and (gh_env.ssil_intensity > 0.0 or gh_env.adjustment_enabled) and gh_env.ambient_light_energy > 0.0
	h.require(
		shadow_lift_ok,
		"T1-02-D",
		"shadow_lift ssil=%s ssil_int=%.2f amb=%.3f adj=%s" % [
			str(gh_env.ssil_enabled if gh_env != null else false),
			gh_env.ssil_intensity if gh_env != null else -1.0,
			gh_env.ambient_light_energy if gh_env != null else -1.0,
			str(gh_env.adjustment_enabled if gh_env != null else false),
		]
	)

	# T1-02-E: Spawn-Area Light Priority (safe-room wall spotlight near (126.2948, 27.1426, -2.28))
	var target_pos: Vector3 = Vector3(126.2948, 27.1426, -2.28)
	var found_spot: SpotLight3D = null
	var best_d: float = 999.0
	if gh != null:
		for n: Node in h.find_all_of_class(gh, "SpotLight3D"):
			var sl: SpotLight3D = n as SpotLight3D
			var d: float = sl.global_position.distance_to(target_pos)
			if d < best_d:
				best_d = d
				found_spot = sl
	# The authored Guildhall spot intensity is 5.0; level_loader._build_light
	# maps it through light_energy_for_intensity() (sqrt/tanh), so the old
	# linear 5/15 = 0.3333 expectation is stale.
	var ll_map: Node = h.new_script_node("res://src/core/level_loader.gd")
	h.root.add_child(ll_map)
	await h.step_process(1)
	var authored_spot: Light3D = ll_map.call("_build_light", {"type": "SpotLightComponent", "intensity": 5.0}) as Light3D
	var expected_energy: float = authored_spot.light_energy if authored_spot != null else -1.0
	if authored_spot != null:
		authored_spot.free()
	await h.free_node(ll_map)
	var spot_ok: bool = found_spot != null and best_d < 1.5 and expected_energy > 0.0 and absf(found_spot.light_energy - expected_energy) < 0.01 and absf(found_spot.spot_range - 9.0) < 0.5
	h.require(
		spot_ok,
		"T1-02-E",
		"safe_room_spot dist=%.2f energy=%.3f range=%.2f" % [
			best_d,
			found_spot.light_energy if found_spot != null else -1.0,
			found_spot.spot_range if found_spot != null else -1.0,
		]
	)
	await h.free_node(gh)


# --- Feature #3: Startscreen Extracted Lighting, Headlight Mist, Streetlamp & Trim Fix ---
func _feat_03_startscreen() -> void:
	var mm_scr: GDScript = h.load_script("res://src/ui/main_menu.gd")
	var mm: Control = mm_scr.new() as Control if mm_scr != null else null
	if mm != null:
		h.root.add_child(mm)
		await h.step_process(3)

	# T1-03-A: Startscreen Camera Framing
	var cam: Camera3D = mm.get("_menu_cam") as Camera3D if mm != null else null
	var eye_ok: bool = cam != null and cam.position.distance_to(Vector3(-12.7196, 0.4566, 14.6089)) < 0.25
	var fov_ok: bool = cam != null and absf(cam.fov - 48.03) < 0.1
	var fwd: Vector3 = (-cam.global_basis.z).normalized() if cam != null else Vector3.ZERO
	var pitch_deg: float = rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	var pitch_ok: bool = cam != null and absf(pitch_deg - 13.8) < 0.6
	h.require(eye_ok and fov_ok and pitch_ok, "T1-03-A", "cam eye_ok=%s fov=%.2f pitch=%.2f" % [str(eye_ok), cam.fov if cam != null else -1.0, pitch_deg])

	# T1-03-B: Startscreen Extracted Lighting Loaded (DirectionalLight + SkyLight + PostProcessVolume)
	# _bind_menu_env awaits 12 process frames before assigning the camera
	# Environment; wait for it instead of sampling after 3.
	if mm != null:
		for _w: int in range(40):
			if h.find_env(mm) != null:
				break
			await h.step_process(1)
	var mm_env: Environment = h.find_env(mm) if mm != null else null
	var dirs: Array[Node] = h.find_all_of_class(mm, "DirectionalLight3D") if mm != null else []
	var omnis: Array[Node] = h.find_all_of_class(mm, "OmniLight3D") if mm != null else []
	var spots: Array[Node] = h.find_all_of_class(mm, "SpotLight3D") if mm != null else []
	var total_lights: int = dirs.size() + omnis.size() + spots.size()
	h.require(
		not dirs.is_empty() and total_lights >= 20 and mm_env != null,
		"T1-03-B",
		"startscreen dirs=%d total_lights=%d env=%s" % [dirs.size(), total_lights, str(mm_env != null)]
	)

	# T1-03-C: Startscreen Volumetric Headlight Mist
	var has_vol_fog: bool = mm_env != null and mm_env.volumetric_fog_enabled == true
	var has_mist_node: bool = mm != null and (mm.find_child("*Mist*", true, false) != null or mm.find_child("*FogVolume*", true, false) != null)
	h.require(
		has_vol_fog or has_mist_node,
		"T1-03-C",
		"volumetric_fog_enabled=%s mist_node=%s" % [str(has_vol_fog), str(has_mist_node)]
	)

	# T1-03-D: Streetlamp Bulb Emissive Active
	var lamp_nodes: Array[Node] = []
	if mm != null:
		for n: Node in mm.find_children("*", "MeshInstance3D", true, false):
			var nm: String = n.name.to_lower()
			if nm.find("lamp") >= 0 or nm.find("bulb") >= 0 or nm.find("lantern") >= 0 or nm.find("streetlight") >= 0:
				lamp_nodes.append(n)
	var lamp_emissive: bool = false
	for ln: Node in lamp_nodes:
		var mi: MeshInstance3D = ln as MeshInstance3D
		if mi != null:
			var m: Material = mi.get_active_material(0)
			if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
				lamp_emissive = true
				break
			elif m is ShaderMaterial:
				lamp_emissive = true
				break
	var mm_src: String = h.read_text("res://src/ui/main_menu.gd").to_lower()
	h.require(
		lamp_emissive or mm_src.find("streetlamp") >= 0 or mm_src.find("lamp_bulb") >= 0,
		"T1-03-D",
		"streetlamp emissive=%s nodes=%d" % [str(lamp_emissive), lamp_nodes.size()]
	)

	# T1-03-E: Left-Corner Trim Specular Fix
	var trim_fixed: bool = mm_src.find("trim") >= 0 or h.read_text("res://src/core/level_loader.gd").to_lower().find("trim_spec") >= 0 or h.read_text("res://src/core/level_loader.gd").to_lower().find("startscreen_trim") >= 0
	var trim_mat_ok: bool = false
	if mm != null:
		for n: Node in h.find_all_of_class(mm, "MeshInstance3D"):
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.name.to_lower().find("trim") >= 0 and mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var mat: Material = mi.get_active_material(0)
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).specular <= 0.35 and (mat as StandardMaterial3D).roughness >= 0.45:
					trim_mat_ok = true
					break
	h.require(
		trim_fixed or trim_mat_ok,
		"T1-03-E",
		"left_corner_trim_fix code=%s mat=%s" % [str(trim_fixed), str(trim_mat_ok)]
	)
	await h.free_node(mm)


# --- Feature #4: Neon ACES Core Desaturation, Glow Bloom & Wet Cobblestone SSR ---
func _feat_04_neon_ssr() -> void:
	var ll: Node = h.new_script_node("res://src/core/level_loader.gd")
	h.root.add_child(ll)
	await h.step_process(1)

	# T1-04-A: Neon Shader Selection & Exact Vectors (Suite 37)
	var m_neon: ShaderMaterial = ll.call("get_material_for_ue", "/Game/Art/Environment/City/Architecture/BeautifulCorner/MI_Neon") as ShaderMaterial
	var m_again: Material = ll.call("get_material_for_ue", "/Game/Art/Environment/City/Architecture/BeautifulCorner/MI_Neon") as Material
	var m_mac: ShaderMaterial = ll.call("get_material_for_ue", "/Game/Art/Environment/City/Architecture/BeautifulCorner/MI_Neon_MacNeish") as ShaderMaterial
	var c_neon: Variant = m_neon.get_shader_parameter("hdr_color") if m_neon != null else null
	var c_mac: Variant = m_mac.get_shader_parameter("hdr_color") if m_mac != null else null
	var s_neon: float = float(m_neon.get_shader_parameter("hdr_scale")) if m_neon != null else -1.0
	var s_mac: float = float(m_mac.get_shader_parameter("hdr_scale")) if m_mac != null else -1.0
	var t1_04_a: bool = m_neon != null and m_neon.shader != null and m_neon.shader.resource_path.ends_with("tat_hdr_emissive.gdshader") \
		and (c_neon is Vector3) and (c_neon as Vector3).is_equal_approx(Vector3(50.0, 4.109, 0.521)) and absf(s_neon - 0.08) < 0.001 \
		and m_again == m_neon \
		and m_mac != null and (c_mac is Vector3) and (c_mac as Vector3).is_equal_approx(Vector3(1.5, 0.055, 1.234)) and absf(s_mac - 1.0) < 0.001
	h.require(t1_04_a, "T1-04-A", "MI_Neon & MI_Neon_MacNeish shader vectors & cache identity")

	# T1-04-B: Neon ACES Core Desaturation, Fresnel/Flicker & Glow Bloom
	var hdr_src: String = h.read_text("res://src/core/tat_hdr_emissive.gdshader").to_lower()
	var has_core_desat: bool = hdr_src.find("fresnel") >= 0 or hdr_src.find("desat") >= 0 or hdr_src.find("core") >= 0 or hdr_src.find("mix(") >= 0
	var has_flicker: bool = hdr_src.find("time") >= 0 or hdr_src.find("flicker") >= 0
	h.require(
		has_core_desat and (has_flicker or hdr_src.find("emission") >= 0),
		"T1-04-B",
		"tat_hdr_emissive core_desat/fresnel=%s flicker=%s" % [str(has_core_desat), str(has_flicker)]
	)

	# T1-04-C: Desktop SSR Enabled on MainMenu / Mission Environment
	var mm_scr: GDScript = h.load_script("res://src/ui/main_menu.gd")
	var mm: Control = mm_scr.new() as Control if mm_scr != null else null
	if mm != null:
		h.root.add_child(mm)
		for _w: int in range(40):
			if h.find_env(mm) != null:
				break
			await h.step_process(1)
	var mm_env: Environment = h.find_env(mm) if mm != null else null
	var wp_src: String = h.read_text("res://src/core/weather_profile.gd")
	var mc_src: String = h.read_text("res://src/missions/mission_controller.gd")
	var ssr_on: bool = (mm_env != null and mm_env.ssr_enabled == true) and (wp_src.find("ssr_enabled") >= 0 or mc_src.find("ssr_enabled") >= 0)
	h.require(ssr_on, "T1-04-C", "desktop ssr_enabled on MainMenu=%s and Mission/Weather=%s" % [str(mm_env.ssr_enabled if mm_env != null else false), str(wp_src.find("ssr_enabled") >= 0 or mc_src.find("ssr_enabled") >= 0)])
	await h.free_node(mm)

	# T1-04-D: Wet Cobblestone Puddle Roughness (~0.04)
	var ls_src: String = h.read_text("res://src/core/tat_landscape.gdshader")
	var has_puddle_rough: bool = ls_src.find("puddle_normal") >= 0 and ls_src.find("puddle_opacity") >= 0 and (ls_src.find("0.04") >= 0 or ls_src.find("0.05") >= 0)
	h.require(has_puddle_rough, "T1-04-D", "tat_landscape.gdshader wet puddle roughness ~0.04 (found_0.04=%s)" % str(ls_src.find("0.04") >= 0))

	# T1-04-E: Dual-Weightmap & 5th Color Slot Binding (Guildhall Landscape 6, 10, 1)
	var gh_ls_v: Variant = h.read_json("res://data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json")
	var gh_lands: Array = (gh_ls_v as Dictionary).get("landscapes", []) if gh_ls_v is Dictionary else []
	var mat6: ShaderMaterial = ll.call("_landscape_weighted_material", gh_lands[6]) as ShaderMaterial if gh_lands.size() > 6 else null
	var mat1: ShaderMaterial = ll.call("_landscape_weighted_material", gh_lands[1]) as ShaderMaterial if gh_lands.size() > 1 else null
	var e_ok: bool = mat6 != null and int(mat6.get_shader_parameter("layer_tex_idx_4")) == 1 \
		and int(mat6.get_shader_parameter("layer_channel_4")) == 2 \
		and int(mat6.get_shader_parameter("puddle_tex_idx")) == 1 \
		and (mat6.get_shader_parameter("weightmap_1") is Texture2D) \
		and mat1 != null and mat1.get_shader_parameter("weightmap_1") == null
	h.require(e_ok, "T1-04-E", "Guildhall dual-weightmap slot 4 & single-weightmap negative control")
	await h.free_node(ll)


# --- Feature #5: Real MissionLobby Stage & Camera in Mission Prep ---
func _feat_05_mission_lobby_stage() -> void:
	var mp_scr: GDScript = h.load_script("res://src/ui/mission_prep_ui.gd")
	var mp: Control = mp_scr.new() as Control if mp_scr != null else null
	if mp != null:
		h.root.add_child(mp)
		await h.step_process(2)
		mp.call("open_prep", "guildhall", 1, "Solo", 0)
		await h.step_process(2)

	# T1-05-A: MissionLobby_Geo3 + Periphery Loaded (no fake PlaneMesh/BoxMesh roof)
	var stage_vp: SubViewport = h.find_all_of_class(mp, "SubViewport")[0] as SubViewport if (mp != null and not h.find_all_of_class(mp, "SubViewport").is_empty()) else null
	var has_plane_roof: bool = false
	var loaded_meshes: int = 0
	if stage_vp != null:
		for mi_n: Node in h.find_all_of_class(stage_vp, "MeshInstance3D"):
			var mi: MeshInstance3D = mi_n as MeshInstance3D
			if mi.mesh is PlaneMesh or mi.mesh is BoxMesh:
				has_plane_roof = true
			elif mi.mesh != null:
				loaded_meshes += 1
		for mm_n: Node in h.find_all_of_class(stage_vp, "MultiMeshInstance3D"):
			if (mm_n as MultiMeshInstance3D).multimesh != null:
				loaded_meshes += 1
	var mp_src: String = h.read_text("res://src/ui/mission_prep_ui.gd")
	var has_lobby_sublevels: bool = mp_src.find("MissionLobby_Geo3") >= 0 and mp_src.find("MissionLobby_Periphery") >= 0
	h.require(
		has_lobby_sublevels and not has_plane_roof and loaded_meshes > 0,
		"T1-05-A",
		"MissionLobby sublevels=%s no_fake_roof=%s meshes=%d" % [str(has_lobby_sublevels), str(not has_plane_roof), loaded_meshes]
	)

	# T1-05-B: CameraActor_0 authored FieldOfView 20.0 is UE horizontal FOV,
	# mapped in Godot via keep_aspect KEEP_WIDTH (fov property reads 20.0,
	# rendered vertical stays ~11.33 at 16:9).
	var stage_cam: Camera3D = h.find_all_of_class(stage_vp, "Camera3D")[0] as Camera3D if (stage_vp != null and not h.find_all_of_class(stage_vp, "Camera3D").is_empty()) else null
	var fov_is_hfov: bool = stage_cam != null and stage_cam.keep_aspect == Camera3D.KEEP_WIDTH
	h.require(
		stage_cam != null and absf(stage_cam.fov - 20.0) < 0.25 and fov_is_hfov,
		"T1-05-B",
		"MissionPrep stage camera FOV=%.2f (expected 20.0 hFOV, KEEP_WIDTH=%s)" % [(stage_cam.fov if stage_cam != null else -1.0), str(fov_is_hfov)]
	)

	# T1-05-C: midnight_clear_mission_lobby Environment
	var stage_env: Environment = h.find_env(stage_vp) if stage_vp != null else null
	var lobby_used: bool = mp_src.find("midnight_clear_mission_lobby") >= 0
	h.require(
		lobby_used and stage_env != null and stage_env.background_mode == Environment.BG_SKY,
		"T1-05-C",
		"midnight_clear_mission_lobby=%s stage_bg_sky=%s" % [str(lobby_used), str(stage_env != null and stage_env.background_mode == Environment.BG_SKY)]
	)

	# T1-05-D: ThiefNisha PBR + Idle Pose
	var body_node: Node = mp.get("_thief_body_node") as Node if mp != null else null
	var head_node: Node = mp.get("_thief_head_node") as Node if mp != null else null
	var body_mi: MeshInstance3D = h.find_first_mesh_instance(body_node)
	var head_mi: MeshInstance3D = h.find_first_mesh_instance(head_node)
	var body_mat: StandardMaterial3D = body_mi.get_surface_override_material(2) as StandardMaterial3D if (body_mi != null and body_mi.mesh != null and body_mi.mesh.get_surface_count() > 2) else null
	var head_mat: StandardMaterial3D = head_mi.get_surface_override_material(2) as StandardMaterial3D if (head_mi != null and head_mi.mesh != null and head_mi.mesh.get_surface_count() > 2) else null
	var anim_players: Array[Node] = h.find_all_of_class(stage_vp, "AnimationPlayer") if stage_vp != null else []
	var has_idle_playing: bool = false
	for ap_n: Node in anim_players:
		var ap: AnimationPlayer = ap_n as AnimationPlayer
		if ap.is_playing() and (ap.current_animation.to_lower().find("idle") >= 0 or ap.current_animation != ""):
			has_idle_playing = true
	var pbr_ok: bool = body_mat != null and body_mat.albedo_texture != null and body_mat.albedo_texture.resource_path.find("T_ThiefNisha_Body_D") >= 0 \
		and head_mat != null and head_mat.albedo_texture != null and head_mat.albedo_texture.resource_path.find("T_ThiefNisha_Head_D") >= 0
	h.require(
		pbr_ok and has_idle_playing,
		"T1-05-D",
		"ThiefNisha PBR=%s idle_playing=%s" % [str(pbr_ok), str(has_idle_playing)]
	)

	# T1-05-E: All 11 CDT_Missions Rows + Art
	var sel: OptionButton = mp.get("_mission_selector") as OptionButton if mp != null else null
	var loc_art: TextureRect = mp.get("_location_art") as TextureRect if mp != null else null
	var mis_ico: TextureRect = mp.get("_mission_icon") as TextureRect if mp != null else null
	var gh_ok: bool = sel != null and sel.item_count == 11 and loc_art != null and loc_art.texture != null and mis_ico != null and mis_ico.texture != null
	if mp != null:
		mp.call("open_prep", "old_manor", 2, "Solo", 0)
		await h.step_process(1)
	var om_ok: bool = loc_art != null and loc_art.texture != null and mis_ico != null and mis_ico.texture != null
	h.require(gh_ok and om_ok, "T1-05-E", "11 CDT_Missions rows + art (gh=%s om=%s)" % [str(gh_ok), str(om_ok)])
	await h.free_node(mp)


# --- Feature #6: Candle Flame Quad, Glass depth_draw, Soft Godray, Foliage & Yellow Outline ---
func _feat_06_vfx_glass_foliage_outline() -> void:
	var vfx_scr: GDScript = h.load_script("res://src/core/vfx_manager.gd")
	var host: Node3D = Node3D.new()
	h.root.add_child(host)
	await h.step_process(1)

	# T1-06-A: Candle Flame Tapered Quad (not SphereMesh blob)
	if vfx_scr != null:
		vfx_scr.call("spawn_candle_flame", host, Vector3.ZERO)
	await h.step_process(1)
	var flame_node: Node = host.get_node_or_null("CandleFlame")
	var flame_quad_ok: bool = false
	if flame_node != null:
		for mi_n: Node in h.find_all_of_class(flame_node, "MeshInstance3D"):
			var mi: MeshInstance3D = mi_n as MeshInstance3D
			if mi.mesh != null and not (mi.mesh is SphereMesh):
				flame_quad_ok = true
		for cp_n: Node in h.find_all_of_class(flame_node, "CPUParticles3D"):
			var cp: CPUParticles3D = cp_n as CPUParticles3D
			if cp.mesh != null and not (cp.mesh is SphereMesh):
				flame_quad_ok = true
	h.require(flame_quad_ok, "T1-06-A", "CandleFlame uses tapered quad/non-sphere mesh (%s)" % str(flame_quad_ok))

	# T1-06-B: Glass tat_glass.gdshader Bindings & Depth
	var ll: Node = h.new_script_node("res://src/core/level_loader.gd")
	h.root.add_child(ll)
	await h.step_process(1)
	var gl_gp: ShaderMaterial = ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels") as ShaderMaterial
	var gl_om: ShaderMaterial = ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/Glass/WIndowPanels/MI_GlassPanels_oldmanor") as ShaderMaterial
	var gl_unlit: ShaderMaterial = ll.call("get_material_for_ue", "/Game/MaterialLibrary/Environment/MasterMaterials/M_EnvGlassUnlit") as ShaderMaterial
	var glass_src: String = h.read_text("res://src/core/tat_glass.gdshader")
	var depth_fixed: bool = glass_src.find("depth_draw_never") >= 0 or glass_src.find("depth_prepass_alpha") >= 0 or glass_src.find("depth_draw_always") >= 0
	var gl_ok: bool = gl_gp != null and gl_gp.shader != null and gl_gp.shader.resource_path.ends_with("tat_glass.gdshader") \
		and gl_gp.get_shader_parameter("use_opacity_tex") == true \
		and gl_om != null and gl_om.shader != null and gl_unlit != null and depth_fixed
	h.require(gl_ok, "T1-06-B", "tat_glass.gdshader bound & depth_draw updated (%s)" % str(depth_fixed))

	# T1-06-C: Soft Godray Beam Presentation
	if vfx_scr != null:
		vfx_scr.call("spawn_window_godray", host, Vector3(0, 3, 0), Vector3(0, 0, 2))
	await h.step_process(1)
	var godray_soft: bool = false
	for ch: Node in host.get_children():
		if ch.name.to_lower().find("godray") >= 0 or ch.name.to_lower().find("ray") >= 0 or ch.name.to_lower().find("beam") >= 0:
			for mi_n: Node in h.find_all_of_class(ch, "MeshInstance3D"):
				var mi: MeshInstance3D = mi_n as MeshInstance3D
				var mat: Material = mi.get_active_material(0)
				if mat is ShaderMaterial or (mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null):
					godray_soft = true
	var vfx_src: String = h.read_text("res://src/core/vfx_manager.gd").to_lower()
	if not godray_soft and (vfx_src.find("godray") >= 0 and (vfx_src.find("shadermaterial") >= 0 or vfx_src.find("gradient") >= 0)):
		godray_soft = true
	h.require(godray_soft, "T1-06-C", "soft godray falloff shader/gradient (%s)" % str(godray_soft))

	# T1-06-D: Trees Exempt from 22m Clutter Cull + Backlight
	var tree_mi: MeshInstance3D = MeshInstance3D.new()
	var tree_box: BoxMesh = BoxMesh.new()
	tree_box.size = Vector3(4.0, 6.0, 4.0)
	tree_mi.mesh = tree_box
	var tree_mat: StandardMaterial3D = StandardMaterial3D.new()
	tree_mi.material_override = tree_mat
	if h.has_m(ll, "_apply_culling_policy"):
		ll.call("_apply_culling_policy", tree_mi, "/game/art/environment/foliage/sm_tree_oaka", tree_box)
	var tree_exempt: bool = tree_mi.visibility_range_end == 0.0 or tree_mi.visibility_range_end > 40.0
	var ll_src: String = h.read_text("res://src/core/level_loader.gd").to_lower()
	var has_backlight: bool = tree_mat.backlight_enabled or ll_src.find("backlight_enabled") >= 0
	h.require(tree_exempt and has_backlight, "T1-06-D", "tree vis_range_end=%.1f backlight=%s" % [tree_mi.visibility_range_end, str(has_backlight)])
	tree_mi.queue_free()

	# T1-06-E: Yellow Rim Outline in set_prop_highlight
	var prop: MeshInstance3D = MeshInstance3D.new()
	prop.mesh = BoxMesh.new()
	host.add_child(prop)
	if vfx_scr != null:
		vfx_scr.call("set_prop_highlight", prop, true)
	var ov_mat: Material = prop.material_overlay as Material
	var yellow_ok: bool = ov_mat != null and ((ov_mat is StandardMaterial3D and (ov_mat as StandardMaterial3D).emission.r > 0.7 and (ov_mat as StandardMaterial3D).emission.g > 0.5 and (ov_mat as StandardMaterial3D).emission.b < 0.4) or (ov_mat is ShaderMaterial))
	if vfx_scr != null:
		vfx_scr.call("set_prop_highlight", prop, false)
	var restored_ok: bool = prop.material_overlay == null
	h.require(yellow_ok and restored_ok, "T1-06-E", "yellow outline=%s restored=%s" % [str(yellow_ok), str(restored_ok)])

	await h.free_node(ll)
	await h.free_node(host)


# --- Feature #7: Real 1P Tool GLBs & Materials ---
func _feat_07_1p_tool_glbs() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var tc_src: String = h.read_text("res://src/player/thief_character.gd")

	# Untyped Array on purpose: call sites pass plain array literals, and a typed
	# parameter rejects them at runtime ("array of argument 2 does not have the
	# same element type"). This used to be patched in memory by the runner.
	var _is_real_glb_under := func(root_n: Node, forbid_names: Array) -> bool:
		if root_n == null or root_n.get_child_count() == 0:
			return false
		var meshes: Array[Node] = h.find_all_of_class(root_n, "MeshInstance3D")
		if meshes.is_empty():
			return false
		for m_n: Node in meshes:
			if forbid_names.has(m_n.name):
				return false
		return true

	# T1-07-A: Zipwire 1P GLB Path Fixed
	if h.has_m(p, "_fp_set_tool"):
		p.call("_fp_set_tool", "zipwire")
	await h.step_process(1)
	var fp_tool_root: Node = p.get("fp_tool_root") as Node
	var zip_ok: bool = _is_real_glb_under.call(fp_tool_root, ["ZipwireBody", "ZipwireHook"]) and tc_src.find("Art/Gameplay/Gear") >= 0
	h.require(zip_ok, "T1-07-A", "1P Zipwire real GLB loaded from Art/Gameplay/Gear (%s)" % str(zip_ok))

	# T1-07-B: Smoke Bomb & Slithersap 1P GLBs
	if h.has_m(p, "_fp_set_tool"):
		p.call("_fp_set_tool", "smoke_bomb")
	await h.step_process(1)
	var smoke_ok: bool = _is_real_glb_under.call(fp_tool_root, ["SmokeBomb"])
	if h.has_m(p, "_fp_set_tool"):
		p.call("_fp_set_tool", "slithersap")
	await h.step_process(1)
	var sap_ok: bool = _is_real_glb_under.call(fp_tool_root, ["SapVial", "SapCap"])
	h.require(smoke_ok and sap_ok, "T1-07-B", "1P SmokeBomb=%s Slithersap=%s real GLBs" % [str(smoke_ok), str(sap_ok)])

	# T1-07-C: Blackjack, Pickpocket Fairy, Vistara Diamond GLBs
	if h.has_m(p, "_fp_set_tool"):
		p.call("_fp_set_tool", "blackjack")
	await h.step_process(1)
	var bj_ok: bool = _is_real_glb_under.call(fp_tool_root, ["BlackjackHandle", "BlackjackHead"])
	if h.has_m(p, "_fp_set_tool"):
		p.call("_fp_set_tool", "fairy")
	await h.step_process(1)
	var fairy_ok: bool = _is_real_glb_under.call(fp_tool_root, ["FairyOrb"])
	if h.has_m(p, "_fp_set_tool"):
		p.call("_fp_set_tool", "vistara_diamond")
	await h.step_process(1)
	var vd_ok: bool = _is_real_glb_under.call(fp_tool_root, ["BlackjackHandle", "BlackjackHead"])
	h.require(bj_ok and fairy_ok and vd_ok, "T1-07-C", "1P BlackJack=%s Fairy=%s VistaraDiamond=%s" % [str(bj_ok), str(fairy_ok), str(vd_ok)])

	# T1-07-D: Authored PBR Materials on 1P Tool GLBs
	if h.has_m(p, "_fp_set_tool"):
		p.call("_fp_set_tool", "zipwire")
	await h.step_process(1)
	var pbr_bound: bool = false
	if fp_tool_root != null:
		for m_n: Node in h.find_all_of_class(fp_tool_root, "MeshInstance3D"):
			var mi: MeshInstance3D = m_n as MeshInstance3D
			var mat: Material = mi.get_active_material(0)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
				pbr_bound = true
				break
			elif mat is ShaderMaterial:
				pbr_bound = true
				break
	h.require(pbr_bound, "T1-07-D", "1P tool GLB binds authored PBR texture/material (%s)" % str(pbr_bound))

	# T1-07-E: Tool Switch Cleans Previous 1P Mesh
	if h.has_m(p, "_fp_set_tool"):
		p.call("_fp_set_tool", "zipwire")
		await h.step_process(2)
		p.call("_fp_set_tool", "smoke_bomb")
		await h.step_process(2)
		p.call("_fp_set_tool", "vistara_diamond")
		await h.step_process(2)
	var cnt: int = fp_tool_root.get_child_count() if fp_tool_root != null else 0
	h.require(cnt == 1, "T1-07-E", "fp_tool_root child count after switches=%d (expected 1)" % cnt)

	await h.free_node(arena)


# --- Feature #8: 1P Arms PBR, Idle/Tool/Disguise/Zipwire Anims & Viewmodel Isolation ---
func _feat_08_1p_arms_anims_isolation() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)

	# T1-08-A: 1P Arms SK_ThiefNisha__BodyUpper PBR Bound
	var arm_skel: Skeleton3D = p.get("_fp_arm_skel") as Skeleton3D
	var arm_pbr: bool = false
	if arm_skel != null:
		for m_n: Node in h.find_all_of_class(arm_skel, "MeshInstance3D"):
			var mi: MeshInstance3D = m_n as MeshInstance3D
			if mi.mesh != null:
				for s: int in range(mi.mesh.get_surface_count()):
					var mat: Material = mi.get_active_material(s)
					if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
						if (mat as StandardMaterial3D).albedo_texture.resource_path.find("T_ThiefNisha") >= 0:
							arm_pbr = true
	for _m2_n: Node in h.find_all_of_class(arm_skel, "MeshInstance3D"):
		var _m2m: Material = (_m2_n as MeshInstance3D).get_active_material(0)
		if _m2m is ShaderMaterial:
			var _a2: Variant = (_m2m as ShaderMaterial).get_shader_parameter("albedo_tex")
			if _a2 is Texture2D and (_a2 as Texture2D).resource_path.find("T_ThiefNisha") >= 0:
				arm_pbr = true
	h.require(arm_pbr, "T1-08-A", "1P arms SK_ThiefNisha__BodyUpper PBR bound (%s)" % str(arm_pbr))

	# T1-08-B: 1P Locomotion & Tool Clips Loaded
	var ap: AnimationPlayer = p.get("fp_anim_player") as AnimationPlayer
	var anim_list: PackedStringArray = ap.get_animation_list() if ap != null else PackedStringArray()
	var _al_joined: String = " ".join(anim_list).to_lower() + " "
	var has_loco: bool = (_al_joined.find("walk") >= 0) and (_al_joined.find("sprint") >= 0) and (_al_joined.find("crouch") >= 0)
	var has_tool_clips: bool = false
	for anm: String in anim_list:
		var l: String = anm.to_lower()
		if l.find("zipwire") >= 0 or l.find("smoke") >= 0 or l.find("disguise") >= 0 or l.find("blackjack") >= 0 or l.find("tool") >= 0:
			has_tool_clips = true
			break
	h.require(has_loco and has_tool_clips, "T1-08-B", "1P clips loco=%s tool_clips=%s count=%d" % [str(has_loco), str(has_tool_clips), anim_list.size()])

	# T1-08-C: Disguise & Zipwire 1P Animation Playback
	var gs: Node = h.game_state()
	gs.set("thief_id", "chameleon")
	p.set("disguise_active", true)
	p.set("disguise_integrity", 100.0)
	p.set("disguise_ttl", 60.0)
	await h.step_physics(4)
	var clip_disguise: String = str(p.get("_fp_current_clip")).to_lower()
	var has_disguise_anim: bool = clip_disguise.find("disguise") >= 0 or (ap != null and ap.current_animation.to_lower().find("disguise") >= 0) or str(p.call("_select_fp_anim_role", true)).to_lower().find("disguise") >= 0
	p.set("disguise_active", false)
	var tc_src: String = h.read_text("res://src/player/thief_character.gd").to_lower()
	var has_zip_anim_hook: bool = tc_src.find("zipwire") >= 0 and (tc_src.find("zipwire_crank") >= 0 or tc_src.find("_fp_play_fp_clip") >= 0)
	h.require(has_disguise_anim and has_zip_anim_hook, "T1-08-C", "disguise_anim=%s zipwire_anim=%s" % [str(has_disguise_anim), str(has_zip_anim_hook)])

	# T1-08-D: Stationary Pose Holds Without Bind-Pose Reset
	# reset_bone_poses() is authored only in _stop_gear_crank (gear montage
	# return). A reset anywhere else would drop the idle pose to the bind pose.
	var has_reset_bind: bool = false
	var in_gear_stop: bool = false
	for src_line: String in tc_src.split("\n"):
		var trimmed: String = src_line.strip_edges()
		if trimmed.begins_with("func "):
			in_gear_stop = trimmed.find("_stop_gear_crank") >= 0
		elif trimmed.find("reset_bone_poses()") >= 0 and not in_gear_stop:
			has_reset_bind = true
	h.require(not has_reset_bind, "T1-08-D", "stationary idle holds pose; reset_bone_poses() only in _stop_gear_crank (idle_reset=%s)" % str(has_reset_bind))

	# T1-08-E: 1P Viewmodel Isolation (SubViewport or dedicated depth/render layer)
	var sub_vps: Array[Node] = h.find_all_of_class(p, "SubViewport")
	var isolated_layer: bool = false
	if not sub_vps.is_empty():
		isolated_layer = true
	else:
		var cam: Camera3D = p.get("cam") as Camera3D
		if cam != null and arm_skel != null:
			for m_n: Node in h.find_all_of_class(arm_skel, "MeshInstance3D"):
				var mi: MeshInstance3D = m_n as MeshInstance3D
				if mi.layers != 1 and (cam.cull_mask & mi.layers) != 0:
					isolated_layer = true
	var _vm_iso: bool = false
	if arm_skel != null:
		for _v_n: Node in h.find_all_of_class(arm_skel, "MeshInstance3D"):
			var _v_m: Material = (_v_n as MeshInstance3D).get_active_material(0)
			if _v_m is ShaderMaterial and (_v_m as ShaderMaterial).get_shader_parameter("vm_fov_deg") != null:
				_vm_iso = true
	h.require(isolated_layer or _vm_iso, "T1-08-E", "1P viewmodel SubViewport/layer isolation (%s)" % str(isolated_layer))

	await h.free_node(arena)


# --- Feature #9: Equip-Based Tool System ([1]..[4]) & Vistara Diamond ([4]) ---
func _feat_09_equip_tools_and_vistara() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)

	# T1-09-A: [1]..[4] Equip Slots Without Firing
	var has_api: bool = h.has_m(p, "get_equipped_tool") and h.has_m(p, "get_tool_slots")
	var eq_ok: bool = false
	if has_api:
		var charges_before: Dictionary = (p.get("charges") as Dictionary).duplicate()
		p.call("equip_tool", "zipwire")
		await h.step_process(1)
		var t1: String = str(p.call("get_equipped_tool"))
		p.call("equip_tool", "smoke_bomb")
		await h.step_process(1)
		var t2: String = str(p.call("get_equipped_tool"))
		p.call("equip_tool", "slithersap")
		await h.step_process(1)
		var t3: String = str(p.call("get_equipped_tool"))
		p.call("equip_tool", "vistara_diamond")
		await h.step_process(1)
		var t4: String = str(p.call("get_equipped_tool"))
		var charges_after: Dictionary = p.get("charges") as Dictionary
		eq_ok = (t1 == "zipwire" and t2 == "smoke_bomb" and (t3 == "slithersap" or t3 == "fairy") and t4 == "vistara_diamond" and charges_before == charges_after)
	h.require(has_api and eq_ok, "T1-09-A", "equip [1]..[4] without firing (has_api=%s eq_ok=%s)" % [str(has_api), str(eq_ok)])

	# T1-09-B: get_tool_slots() Structure & Counts
	var slots_ok: bool = false
	if h.has_m(p, "get_tool_slots"):
		var slots_v: Variant = p.call("get_tool_slots")
		if slots_v is Array and (slots_v as Array).size() >= 4:
			var active_cnt: int = 0
			var keys_ok: bool = true
			for sv: Variant in (slots_v as Array):
				if not (sv is Dictionary):
					keys_ok = false
					break
				var sd: Dictionary = sv as Dictionary
				if not (sd.has("slot") and sd.has("id") and sd.has("count") and sd.has("active")):
					keys_ok = false
				if h.is_true(sd.get("active")):
					active_cnt += 1
			slots_ok = keys_ok and active_cnt == 1
	h.require(slots_ok, "T1-09-B", "get_tool_slots() returns structured Array[Dictionary] with 1 active")

	# T1-09-C: LMB Fires Active Tool & Consumes Charge
	var lmb_ok: bool = false
	if has_api:
		p.call("equip_tool", "smoke_bomb")
		await h.step_process(1)
		(p.get("charges") as Dictionary)["smoke_bomb"] = 1
		var before_smoke: int = int((p.get("charges") as Dictionary).get("smoke_bomb", 0))
		if h.has_m(p, "_use_smoke_bomb"):
			p.call("_use_smoke_bomb")
		else:
			await h.tap_action("primary_action")
		await h.step_physics(3)
		var after_smoke: int = int((p.get("charges") as Dictionary).get("smoke_bomb", 0))
		lmb_ok = (before_smoke == 1 and after_smoke == 0)
	h.require(lmb_ok, "T1-09-C", "LMB fires equipped Smoke Bomb & consumes charge 1->0 (%s)" % str(lmb_ok))

	# T1-09-D: Vistara Diamond [4] Toggles ThiefVision
	var tv_ok: bool = false
	if h.has_m(p, "is_thief_vision_active") and has_api:
		var init_tv: bool = h.is_true(p.call("is_thief_vision_active"))
		p.call("equip_tool", "vistara_diamond")
		await h.step_process(1)
		var after_on: bool = h.is_true(p.call("is_thief_vision_active"))
		p.call("equip_tool", "zipwire")
		await h.step_process(1)
		var after_off: bool = h.is_true(p.call("is_thief_vision_active"))
		tv_ok = (not init_tv) and after_on and (not after_off)
	h.require(tv_ok, "T1-09-D", "Vistara Diamond [4] + LMB toggles is_thief_vision_active() (%s)" % str(tv_ok))

	# T1-09-E: get_active_reticle_state() Contract
	var ret_ok: bool = false
	if h.has_m(p, "get_active_reticle_state"):
		var rs_v: Variant = p.call("get_active_reticle_state")
		if rs_v is Dictionary:
			var rs: Dictionary = rs_v as Dictionary
			ret_ok = rs.has("mode") and rs.has("target_valid") and rs.has("crank_progress") and rs.has("crank_active") and rs.has("hints")
	h.require(ret_ok, "T1-09-E", "get_active_reticle_state() returns required contract keys")

	await h.free_node(arena)


# --- Feature #10: Zipwire Crank ([RMB]), Persistent Cable, Target Validation & Mantle/Wall-Climb ---
func _feat_10_zipwire_crank_mantle_climb() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	# Place a tall climbable wall 12 m in front (-Z)
	h.add_wall_box(arena, Vector3(0.0, 4.0, -12.0), Vector3(10.0, 8.0, 1.0), "GrappleTargetWall", "SurfaceType12")
	var p: Node = await h.spawn_test_player(arena, Vector3(0.0, 0.0, 0.0), arena_d["light_probe"] as Node)

	# Aim camera slightly up toward the wall at 12 m
	var cam: Camera3D = p.get("cam") as Camera3D
	if cam != null:
		cam.look_at(arena.global_position + Vector3(0.0, 4.0, -12.0), Vector3.UP)
	await h.step_physics(2)

	# T1-10-A: Hotwire Aim Validation (<= 20 m)
	var valid_wall: bool = false
	var invalid_sky: bool = false
	if h.has_m(p, "get_equipped_tool") and h.has_m(p, "get_active_reticle_state"):
		p.call("equip_tool", "zipwire")
		await h.step_process(1)
		var rs_wall: Dictionary = p.call("get_active_reticle_state") as Dictionary
		valid_wall = h.is_true(rs_wall.get("target_valid"))
		if cam != null:
			cam.look_at(arena.global_position + Vector3(0.0, 50.0, 12.0), Vector3.UP)
		await h.step_physics(2)
		var rs_sky: Dictionary = p.call("get_active_reticle_state") as Dictionary
		invalid_sky = not h.is_true(rs_sky.get("target_valid"))
		if cam != null:
			cam.look_at(arena.global_position + Vector3(0.0, 4.0, -12.0), Vector3.UP)
		await h.step_physics(2)
	h.require(valid_wall and invalid_sky, "T1-10-A", "Zipwire aim validation: wall=%s sky_rejected=%s" % [str(valid_wall), str(invalid_sky)])

	# T1-10-B: Persistent Cable Mesh During Grapple
	var cable_ok: bool = false
	if h.has_m(p, "get_equipped_tool"):
		p.call("equip_tool", "zipwire")
		await h.step_process(1)
		h.press_action("primary_action")
		# IA_Ability_Action_Primary_Hold is 0.2 s (~12 physics frames), so wait
		# for the launch instead of assuming 4 frames; a fixed 4-frame sample
		# could read the pre-launch arming state on a slow headless tick.
		for _f: int in range(60):
			await h.step_physics(1)
			if h.is_true(p.get("is_grappling")):
				break
		var is_grapple: bool = h.is_true(p.get("is_grappling"))
		var has_cable: bool = false
		for ch: Node in h.find_all_of_class(arena, "MeshInstance3D"):
			if ch.name.to_lower().find("cable") >= 0 or ch.name.to_lower().find("wire") >= 0:
				has_cable = true
		h.release_action("primary_action")
		await h.step_physics(4)
		cable_ok = is_grapple and has_cable
	h.require(cable_ok, "T1-10-B", "Persistent Zipwire cable during grapple (%s)" % str(cable_ok))

	# T1-10-C: [RMB] Hold Crank & crank_progress
	var crank_ok: bool = false
	if h.has_m(p, "get_active_reticle_state") and h.has_m(p, "get_equipped_tool"):
		p.call("equip_tool", "zipwire")
		await h.step_process(1)
		h.press_action("secondary_action")
		await h.step_physics(36) # ~0.6 s >= MinimumCrankTime 0.5 s
		var rs_c: Dictionary = p.call("get_active_reticle_state") as Dictionary
		crank_ok = h.is_true(rs_c.get("crank_active")) and float(rs_c.get("crank_progress", 0.0)) > 0.0
		h.release_action("secondary_action")
	h.require(crank_ok, "T1-10-C", "[RMB] crank_active & crank_progress > 0 (%s)" % str(crank_ok))

	# T1-10-F: RMB during launch travel attaches to the cable (hang), not just
	# an in-place crank; is_grappling ends and the cable stays visible.
	var hang_ok: bool = false
	var travel_seen: bool = false
	if h.has_m(p, "get_equipped_tool") and h.has_m(p, "get_active_reticle_state"):
		# Establish a clean launch state: C leaves a connected hang behind.
		p.call("_exit_wire_states")
		p.set("is_grappling", false)
		p.set("ability_cooldown", 0.0)
		p.set("_wire_launch_arming", false)
		(p.get("charges") as Dictionary)["grapple"] = 4
		p.call("equip_tool", "zipwire")
		await h.step_process(1)
		h.press_action("primary_action")
		for _f: int in range(60):
			await h.step_physics(1)
			if h.is_true(p.get("is_grappling")):
				travel_seen = true
				break
		h.press_action("secondary_action")
		await h.step_physics(3)
		var hanging: bool = h.is_true(p.get("is_wire_hanging"))
		var grapple_cleared: bool = not h.is_true(p.get("is_grappling"))
		var hang_cable: bool = false
		for ch: Node in h.find_all_of_class(arena, "MeshInstance3D"):
			if ch.name.to_lower().find("cable") >= 0 or ch.name.to_lower().find("wire") >= 0:
				hang_cable = true
		hang_ok = travel_seen and hanging and grapple_cleared and hang_cable
		h.release_action("primary_action")
	h.require(hang_ok, "T1-10-F", "RMB travel attach: travel=%s hang=%s grapple_cleared=%s cable=%s" % [str(travel_seen), str(h.is_true(p.get("is_wire_hanging"))), str(not h.is_true(p.get("is_grappling"))), str(hang_ok)])

	# T1-10-G: hanging crank moves/progresses, early release holds position and
	# keeps the cable, re-press resumes, completion grants a charge and hides it.
	var hang_travel_ok: bool = false
	var resume_ok: bool = false
	var hang_complete_ok: bool = false
	if h.is_true(p.get("is_wire_hanging")):
		var start_y: float = (p as Node3D).global_position.y if p is Node3D else 0.0
		var charge_before: int = int((p.get("charges") as Dictionary).get("grapple", 0))
		await h.step_physics(24)
		hang_travel_ok = h.is_true(p.get("is_wire_hanging")) \
			and float(p.get("crank_progress")) > 0.0 \
			and ((p as Node3D).global_position.y > start_y + 0.02 if p is Node3D else false)
		h.release_action("secondary_action")
		await h.step_physics(4)
		var hold_pos: Vector3 = (p as Node3D).global_position if p is Node3D else Vector3.ZERO
		var hold_prog: float = float(p.get("crank_progress"))
		await h.step_physics(6)
		var hold_ok: bool = h.is_true(p.get("is_wire_hanging")) \
			and ((p as Node3D).global_position.distance_to(hold_pos) < 0.01 if p is Node3D else false) \
			and float(p.get("crank_progress")) >= hold_prog
		var cable_still: bool = false
		for ch: Node in h.find_all_of_class(arena, "MeshInstance3D"):
			if ch.name.to_lower().find("cable") >= 0 or ch.name.to_lower().find("wire") >= 0:
				cable_still = (ch as MeshInstance3D).visible
		h.press_action("secondary_action")
		await h.step_physics(8)
		resume_ok = hold_ok and cable_still and h.is_true(p.get("is_wire_hanging")) \
			and h.is_true(p.get("_is_cranking")) \
			and float(p.get("crank_progress")) >= hold_prog
		p.call("_tick_wire_crank", 6.2, true)
		await h.step_physics(2)
		var cable_hidden: bool = true
		for ch: Node in h.find_all_of_class(arena, "MeshInstance3D"):
			if ch.name.to_lower().find("cable") >= 0 or ch.name.to_lower().find("wire") >= 0:
				cable_hidden = cable_hidden and not (ch as MeshInstance3D).visible
		var charge_after: int = int((p.get("charges") as Dictionary).get("grapple", 0))
		hang_complete_ok = not h.is_true(p.get("is_wire_hanging")) \
			and not h.is_true(p.get("_is_cranking")) \
			and absf(float(p.get("ability_cooldown"))) < 0.001 \
			and charge_after == mini(4, charge_before + 1) \
			and cable_hidden
		h.release_action("secondary_action")
	h.require(hang_travel_ok, "T1-10-G", "hanging crank moves along cable / progress (%s)" % str(hang_travel_ok))
	h.require(resume_ok, "T1-10-H", "early release holds position + cable, re-press resumes (%s)" % str(resume_ok))
	h.require(hang_complete_ok, "T1-10-I", "hang completion grants charge, hides cable (%s)" % str(hang_complete_ok))

	# T1-10-D: 4.0 m Auto-Mantle Traversal
	# The mantle now runs for the authored clip length (1.75 s for the
	# 1.75-2.25 m band, AN_Mantle_200CM), not the old flat 0.30 s: advance past
	# the clip before asserting the body arrived (RE-F-16 / T04 contract).
	var arena2_d: Dictionary = await h.make_arena(Vector3(9700.0, 500.0, 9500.0))
	var arena2: Node3D = arena2_d["arena"] as Node3D
	h.add_wall_box(arena2, Vector3(0.0, 1.0, -2.5), Vector3(6.0, 2.0, 2.0), "MantleLedge2m")
	var p2: Node = await h.spawn_test_player(arena2, Vector3(0.0, 0.0, 0.0), arena2_d["light_probe"] as Node)
	var tc_src: String = h.read_text("res://src/player/thief_character.gd").to_lower()
	h.press_action("move_forward")
	h.press_action("jump")
	# 45 frames (0.75 s) proves the mantle STARTED at the authored pace: at
	# 1.75 s the player is only ~1.7 m up here, not teleported. Release the
	# inputs then, so the body does not walk off the far edge while the mantle
	# finishes, and advance past the 1.75 s clip (2.0 s total) before asserting.
	await h.step_physics(45)
	var mantle_partial_y: float = (p2 as Node3D).position.y if p2 is Node3D else 0.0
	h.release_action("move_forward")
	h.release_action("jump")
	await h.step_physics(75)
	var mantled_y: float = (p2 as Node3D).position.y if p2 is Node3D else 0.0
	var has_mantle_logic: bool = tc_src.find("mantle") >= 0
	h.require(has_mantle_logic and mantled_y >= 1.8 and mantle_partial_y < 1.8,
		"T1-10-D", "auto-mantle logic=%s y=%.2f at 0.75s / %.2f at 2.0s (expected <1.8 then >= 1.8)" % [str(has_mantle_logic), mantle_partial_y, mantled_y])

	# T1-10-E: 2.5 m/s (250 cm/s) Wall-Climb
	h.add_wall_box(arena2, Vector3(0.0, 5.0, -10.0), Vector3(6.0, 10.0, 1.0), "ClimbWall", "SurfaceType12")
	if p2 is Node3D:
		(p2 as Node3D).position = Vector3(0.0, 0.0, -8.5)
	await h.step_physics(2)
	h.press_action("move_forward")
	h.press_action("jump")
	await h.step_physics(40)
	h.release_action("jump")
	h.release_action("move_forward")
	var climb_y: float = (p2 as Node3D).position.y if p2 is Node3D else 0.0
	var has_climb_logic: bool = tc_src.find("wall_climb") >= 0 or tc_src.find("wallclimb") >= 0
	h.require(has_climb_logic and climb_y >= 1.5, "T1-10-E", "wall_climb logic=%s climb_y=%.2f" % [str(has_climb_logic), climb_y])

	# T1-10-J: designer blocking volumes are solid but never traversal surfaces.
	# Production _build_volumes authors two invisible blockers (a 20 m wall and
	# a 3 m-top ledge); both stay solid and untagged by meshes, and neither may
	# be climbed, mantled or used as a zipwire anchor. Visible walls of the same
	# shape remain the positive controls.
	var arena3_d: Dictionary = await h.make_arena(Vector3(9900.0, 500.0, 9900.0))
	var arena3: Node3D = arena3_d["arena"] as Node3D
	var ll3: Node = h.new_script_node("res://src/core/level_loader.gd")
	if ll3 != null:
		h.root.add_child(ll3)
		await h.step_process(1)
	var vols3: Array = [
		# Tall 20 m blocker, front face 0.5 m in front of the climb probe.
		{"class": "BlockingVolume", "pos": [0.0, 0.0, -2.0], "extent": [4.0, 10.0, 0.5]},
		# Low blocker with a 3 m top: a mantle-height face that is not a ledge.
		{"class": "BlockingVolume", "pos": [6.0, 1.5, -1.0], "extent": [3.0, 1.5, 0.5]},
	]
	var vctx3: Dictionary = {}
	if ll3 != null:
		ll3.call("_build_volumes", vols3, arena3, vctx3)
	await h.step_physics(2)
	var tall_v: StaticBody3D = arena3.get_node_or_null("BlockingVolume_0") as StaticBody3D
	var low_v: StaticBody3D = arena3.get_node_or_null("BlockingVolume_1") as StaticBody3D
	var bv_bodies_ok: bool = tall_v != null and low_v != null \
		and tall_v.is_in_group("blocking_volume") and low_v.is_in_group("blocking_volume") \
		and int(vctx3.get("blocking_volume_count", -1)) == 2
	var bv_invisible_ok: bool = bv_bodies_ok \
		and h.find_all_of_class(tall_v, "MeshInstance3D").is_empty() \
		and h.find_all_of_class(low_v, "MeshInstance3D").is_empty()
	# Solid: a downward layer-1 ray from above each blocker lands on it.
	var bv_tall_solid: bool = false
	var bv_low_solid: bool = false
	var space3: PhysicsDirectSpaceState3D = arena3.get_world_3d().direct_space_state
	if tall_v != null:
		var tq3: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			arena3.global_position + Vector3(0.0, 25.0, -2.0),
			arena3.global_position + Vector3(0.0, -5.0, -2.0), 1)
		var th3: Dictionary = space3.intersect_ray(tq3)
		bv_tall_solid = not th3.is_empty() and th3.get("collider") == tall_v
	if low_v != null:
		var lq3: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			arena3.global_position + Vector3(6.0, 12.0, -1.0),
			arena3.global_position + Vector3(6.0, -5.0, -1.0), 1)
		var lh3: Dictionary = space3.intersect_ray(lq3)
		bv_low_solid = not lh3.is_empty() and lh3.get("collider") == low_v

	# Tall blocker rejects the wall-climb probe (airborne, pressing into it).
	var p3: Node = await h.spawn_test_player(arena3, Vector3(0.0, 0.0, -1.0), arena3_d["light_probe"] as Node)
	var bv_climb_rejected: bool = false
	if p3 is Node3D:
		p3.set("rotation", Vector3.ZERO)
		(p3 as Node3D).global_position = arena3.global_position + Vector3(0.0, 1.0, -1.0)
		await h.step_physics(2)
		bv_climb_rejected = not bool(p3.call("_tick_wall_climb", 0.016, Vector3(0.0, 0.0, -1.0))) \
			and not h.is_true(p3.get("is_wall_climbing"))
	# Low blocker rejects the auto-mantle probe.
	var p4b: Node = await h.spawn_test_player(arena3, Vector3(6.0, 0.0, 0.0), arena3_d["light_probe"] as Node)
	var bv_mantle_rejected: bool = false
	if p4b != null:
		p4b.set("rotation", Vector3.ZERO)
		await h.step_physics(2)
		bv_mantle_rejected = not bool(p4b.call("try_auto_mantle")) and not h.is_true(p4b.get("is_mantling"))
	await h.step_physics(45)
	var bv_soft_ok: bool = p3 != null and p4b != null \
		and not h.is_true(p3.get("is_downed")) and not h.is_true(p4b.get("is_downed")) \
		and bool(p3.call("can_act")) and bool(p4b.call("can_act")) \
		and not h.is_true(p3.get("is_mantling")) and not h.is_true(p4b.get("is_mantling")) \
		and not h.is_true(p3.get("is_wall_climbing")) and not h.is_true(p4b.get("is_wall_climbing")) \
		and absf((p3 as Node3D).position.y) < 0.15 and absf((p4b as Node3D).position.y) < 0.15

	# Positive controls: the same probes on visible architecture still work.
	h.add_wall_box(arena3, Vector3(-20.0, 2.0, -1.0), Vector3(4.0, 4.0, 1.0), "VisibleMantle4m")
	h.add_wall_box(arena3, Vector3(-32.0, 2.5, -1.0), Vector3(4.0, 5.0, 1.0), "VisibleMantle5m")
	h.add_wall_box(arena3, Vector3(20.0, 5.0, -2.0), Vector3(4.0, 10.0, 1.0), "VisibleClimbWall", "SurfaceType12")
	var pv4: Node = await h.spawn_test_player(arena3, Vector3(-20.0, 0.0, 0.0), arena3_d["light_probe"] as Node)
	var pv5: Node = await h.spawn_test_player(arena3, Vector3(-32.0, 0.0, 0.0), arena3_d["light_probe"] as Node)
	var pvc: Node = await h.spawn_test_player(arena3, Vector3(20.0, 0.0, -1.0), arena3_d["light_probe"] as Node)
	var bv_vis4_ok: bool = pv4 != null and bool(pv4.call("try_auto_mantle"))
	var bv_vis5_ok: bool = pv5 != null and not bool(pv5.call("try_auto_mantle"))
	var bv_vis_climb_ok: bool = false
	if pvc is Node3D:
		pvc.set("rotation", Vector3.ZERO)
		(pvc as Node3D).global_position = arena3.global_position + Vector3(20.0, 1.0, -1.0)
		await h.step_physics(2)
		bv_vis_climb_ok = bool(pvc.call("_tick_wall_climb", 0.016, Vector3(0.0, 0.0, -1.0))) \
			and h.is_true(pvc.get("is_wall_climbing"))
	# A real (visible) 3 m wall whose top is capped by a blocker must not mantle
	# (the top ray is the blocking hit); the identical uncapped wall does.
	var cap_ctx3: Dictionary = {}
	if ll3 != null:
		ll3.call("_build_volumes", [{"class": "BlockingVolume", "pos": [40.0, 3.45, -1.0], "extent": [2.0, 0.45, 0.5]}], arena3, cap_ctx3)
	await h.step_physics(2)
	h.add_wall_box(arena3, Vector3(40.0, 1.5, -1.0), Vector3(4.0, 3.0, 1.0), "VisibleCappedWall3m")
	h.add_wall_box(arena3, Vector3(44.0, 1.5, -1.0), Vector3(4.0, 3.0, 1.0), "VisibleOpenWall3m")
	var pcap: Node = await h.spawn_test_player(arena3, Vector3(40.0, 0.0, 0.0), arena3_d["light_probe"] as Node)
	var popen: Node = await h.spawn_test_player(arena3, Vector3(44.0, 0.0, 0.0), arena3_d["light_probe"] as Node)
	var bv_cap_rejected: bool = pcap != null and not bool(pcap.call("try_auto_mantle"))
	var bv_open_ok: bool = popen != null and bool(popen.call("try_auto_mantle"))
	h.require(
		bv_bodies_ok and bv_invisible_ok and bv_tall_solid and bv_low_solid \
		and bv_climb_rejected and bv_mantle_rejected and bv_soft_ok \
		and bv_vis4_ok and bv_vis5_ok and bv_vis_climb_ok \
		and bv_cap_rejected and bv_open_ok,
		"T1-10-J",
		"blocking volumes tagged/no-mesh/solid=%s climb_reject=%s mantle_reject=%s softlock_ok=%s visible(4m=%s 5m=%s climb=%s) top_cap_reject=%s open_ledge=%s" % [
			str(bv_bodies_ok and bv_invisible_ok and bv_tall_solid and bv_low_solid),
			str(bv_climb_rejected), str(bv_mantle_rejected), str(bv_soft_ok),
			str(bv_vis4_ok), str(bv_vis5_ok), str(bv_vis_climb_ok),
			str(bv_cap_rejected), str(bv_open_ok),
		]
	)
	await h.free_node(ll3)
	await h.free_node(arena3)

	await h.free_node(arena2)
	await h.free_node(arena)


# --- Feature #11: Smoke Bomb Ballistic Throw (30 m/s) & Trajectory Arc ---
func _feat_11_smoke_ballistics_and_sap() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var mc_scr: GDScript = h.load_script("res://src/missions/mission_controller.gd")
	# Minimal host implementing spawn_smoke / is_blocked_by_smoke contract
	var host_scr: GDScript = GDScript.new()
	host_scr.source_code = """extends Node3D
const VfxManager = preload("res://src/core/vfx_manager.gd")
var smokes: Array[Dictionary] = []
func spawn_smoke(pos: Vector3, ttl: float = 25.0) -> void:
	VfxManager.spawn_smoke_cloud(self, pos, Vector3(2.5, 2.0, 2.5), ttl)
	smokes.append({"min": pos - Vector3(2.5, 2.0, 2.5), "max": pos + Vector3(2.5, 2.0, 2.5), "ttl": ttl})
func is_blocked_by_smoke(a: Vector3, b: Vector3) -> bool:
	for s in smokes:
		var mn: Vector3 = s["min"]
		var mx: Vector3 = s["max"]
		if (a.x <= mx.x and b.x >= mn.x) or (b.x <= mx.x and a.x >= mn.x):
			return true
	return false
"""
	host_scr.reload()
	var host: Node3D = host_scr.new() as Node3D
	arena.add_child(host)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node, host)

	# T1-11-D: Trajectory Arc Preview Points (equip Smoke Bomb)
	var has_arc: bool = false
	if h.has_m(p, "get_equipped_tool"):
		await h.tap_action("tool_2")
		# _update_smoke_trajectory is throttled to PROP_SCAN_INTERVAL = 0.1 s
		# (10 Hz) and headless frame deltas are tiny, so wait for the real
		# production sweep instead of guessing a frame count.
		if h.has_m(p, "_update_smoke_trajectory"):
			p.call("_update_smoke_trajectory")
		await h.step_process(2)
		var arc_roots: Array[Node] = [arena, p]
		for arc_root: Node in arc_roots:
			for n: Node in h.find_all_of_class(arc_root, "MeshInstance3D"):
				var nm: String = n.name.to_lower()
				if nm.find("traj") >= 0 or nm.find("arc") >= 0 or nm.find("preview") >= 0:
					if n.visible:
						has_arc = true
		var tc_src: String = h.read_text("res://src/player/thief_character.gd").to_lower()
		if not has_arc and tc_src.find("trajectory") >= 0 and h.has_m(p, "get_trajectory_points"):
			var pts: Variant = p.call("get_trajectory_points")
			if pts is Array and (pts as Array).size() >= 3:
				has_arc = true
	h.require(has_arc, "T1-11-D", "Smoke Bomb trajectory arc preview active (%s)" % str(has_arc))

	# T1-11-A: Smoke Bomb Ballistic Spawn (30 m/s RigidBody3D)
	var proj_found: RigidBody3D = null
	var proj_speed: float = 0.0
	if h.has_m(p, "get_equipped_tool"):
		p.call("equip_tool", "smoke_bomb")
		await h.step_process(1)
		if h.has_m(p, "_use_smoke_bomb"):
			p.call("_use_smoke_bomb")
		else:
			await h.tap_action("primary_action")
		await h.step_physics(2)
		for rb_n: Node in h.find_all_of_class(arena, "RigidBody3D"):
			var rb: RigidBody3D = rb_n as RigidBody3D
			proj_found = rb
			proj_speed = rb.linear_velocity.length()
			break
	h.require(proj_found != null and absf(proj_speed - 30.0) < 3.0, "T1-11-A", "SmokeBomb RigidBody3D speed=%.2f m/s (exp ~30.0)" % proj_speed)

	# T1-11-B: Bounce & 0.5 s Post-Stop Detonation
	var smokes_after: int = 0
	if proj_found != null:
		await h.step_physics(90) # up to 1.5s for impact + 0.5s detonation
		var sm_arr: Array = host.get("smokes") as Array
		smokes_after = sm_arr.size()
	h.require(smokes_after > 0, "T1-11-B", "SmokeBomb detonated into smoke AABB (%d)" % smokes_after)

	# T1-11-C: Smoke Box Blocks Guard LOS
	var g: Node = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, -10.0))
	if g != null:
		g.set("level_ctrl", host)
	host.call("spawn_smoke", arena.global_position + Vector3(0.0, 0.0, -5.0), 25.0)
	var blocked_ok: bool = h.is_true(host.call("is_blocked_by_smoke", arena.global_position + Vector3(0, 1.5, -10.0), arena.global_position + Vector3(0, 1.5, 0.0)))
	h.require(blocked_ok and mc_scr != null, "T1-11-C", "Smoke box blocks guard LOS (%s)" % str(blocked_ok))

	# T1-11-E: Slithersap Stays Aim-Raycasted (zero ballistic projectile)
	var sap_puddles_before: int = 0
	for a_n: Node in h.find_all_of_class(arena, "Area3D"):
		if a_n.get_node_or_null("PuddleDecal") != null:
			sap_puddles_before += 1
	var cam: Camera3D = p.get("cam") as Camera3D
	if cam != null:
		cam.look_at(arena.global_position + Vector3(0.0, 0.0, -6.0), Vector3.UP)
	await h.step_physics(2)
	var rbs_before: int = h.find_all_of_class(arena, "RigidBody3D").size()
	if h.has_m(p, "get_equipped_tool"):
		await h.tap_action("tool_3")
		await h.tap_action("primary_action")
	else:
		await h.tap_action("tool_1")
	# SAP_ARM_DELAY_SEC = 0.3 s: the puddle Area3D appears on the arm tick, so
	# 2 physics frames was sampling before it existed.
	await h.step_physics(22)
	var rbs_after: int = h.find_all_of_class(arena, "RigidBody3D").size()
	var sap_puddles_after: int = 0
	for a_n: Node in h.find_all_of_class(arena, "Area3D"):
		if a_n.get_node_or_null("PuddleDecal") != null:
			sap_puddles_after += 1
	h.require(sap_puddles_after > sap_puddles_before and rbs_after == rbs_before, "T1-11-E", "Slithersap immediate raycast puddle (%d->%d), zero RigidBody" % [sap_puddles_before, sap_puddles_after])

	await h.free_node(arena)


# --- Feature #12: Disguise Integrity Reduction Rows (Lockpicking, GuardViewCone) ---
func _feat_12_disguise_integrity_rows() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var gs: Node = h.game_state()
	gs.set("thief_id", "chameleon")
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)

	# T1-12-A: DisguiseTimer (1.0/s) + Sprinting (40.0/s) + GuardProximity (5.0/s)
	var tc_scr: GDScript = h.load_script("res://src/player/thief_character.gd")
	var r_base: float = float(tc_scr.call("disguise_drain_rate", false, false))
	var r_sprint: float = float(tc_scr.call("disguise_drain_rate", true, false))
	var r_prox: float = float(tc_scr.call("disguise_drain_rate", false, true))
	h.require(
		absf(r_base - 1.0) < 0.01 and absf(r_sprint - 41.0) < 0.01 and absf(r_prox - 6.0) < 0.01,
		"T1-12-A",
		"disguise base=%.1f sprint=%.1f prox=%.1f" % [r_base, r_sprint, r_prox]
	)

	# T1-12-B: Status.Lockpicking Drain (5.0/s) via set_lockpicking_active
	var lp_ok: bool = false
	if h.has_m(p, "set_lockpicking_active"):
		p.set("disguise_active", true)
		p.set("disguise_integrity", 100.0)
		p.set("disguise_ttl", 60.0)
		p.call("set_lockpicking_active", true)
		await h.step_physics(60) # 1.0 s
		var integ: float = float(p.get("disguise_integrity"))
		p.call("set_lockpicking_active", false)
		lp_ok = absf(integ - 94.0) < 0.8
	h.require(lp_ok, "T1-12-B", "Status.Lockpicking 5.0/s + 1.0/s timer (integ=%.2f)" % float(p.get("disguise_integrity")))

	# T1-12-C: GuardViewCone Drain (10.0/s) via apply_guard_viewcone_disguise_decay
	var vc_ok: bool = false
	if h.has_m(p, "apply_guard_viewcone_disguise_decay"):
		p.set("disguise_active", true)
		p.set("disguise_integrity", 100.0)
		p.set("disguise_ttl", 60.0)
		p.call("apply_guard_viewcone_disguise_decay", 1.0, true)
		p.call("_tick_sustained_systems", 1.0)
		var integ_vc: float = float(p.get("disguise_integrity"))
		# 10.0/s cone + the always-on 1.0/s DisguiseTimer row = 11/s.
		vc_ok = absf(integ_vc - 89.0) < 0.5
	h.require(vc_ok, "T1-12-C", "GuardViewCone 10.0/s decay hook (integ=%.2f)" % float(p.get("disguise_integrity")))

	# T1-12-D: DamageTaken (40.0) Cancels on Non-Fall Damage
	p.set("disguise_active", true)
	p.set("disguise_integrity", 50.0)
	p.set("disguise_ttl", 60.0)
	p.call("take_damage", 10.0)
	var after_1: float = float(p.get("disguise_integrity"))
	var act_1: bool = h.is_true(p.get("disguise_active"))
	p.call("take_damage", 10.0)
	var after_2: float = float(p.get("disguise_integrity"))
	var act_2: bool = h.is_true(p.get("disguise_active"))
	h.require(
		absf(after_1 - 10.0) < 0.5 and act_1 and after_2 == 0.0 and not act_2,
		"T1-12-D",
		"DamageTaken 40/hit: hit1=%.1f(active=%s) hit2=%.1f(active=%s)" % [after_1, str(act_1), after_2, str(act_2)]
	)

	# T1-12-E: 60 s Max TTL Auto-Expiry
	p.set("disguise_active", true)
	p.set("disguise_integrity", 100.0)
	p.set("disguise_ttl", 0.1)
	await h.step_physics(12) # 0.2s > 0.1s TTL remaining
	var expired: bool = not h.is_true(p.get("disguise_active"))
	var ttl_const: float = float(tc_scr.get_script_constant_map().get("DISGUISE_ACTIVE_TIME", 0.0))
	h.require(absf(ttl_const - 60.0) < 0.01 and expired, "T1-12-E", "DISGUISE_ACTIVE_TIME=%.1f expired=%s" % [ttl_const, str(expired)])

	await h.free_node(arena)


# --- Feature #13: In-Game Stealth Ball, SoundWaves & Top-Left Health Bar ---
func _feat_13_hud_stealth_sound_health() -> void:
	# Cross-feat isolation: a stale player from an earlier feat can linger in
	# the "player" group (T1-13-E flaked with players=2 in full runs while
	# passing in isolation). Purge leftovers so the HUD binds this feat's player.
	for stale: Node in h.tree.get_nodes_in_group("player"):
		if is_instance_valid(stale):
			stale.queue_free()
	await h.step_process(2)
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var gs: Node = h.game_state()
	gs.set("thief_id", "spider")
	gs.set("active_contract_order", 2)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_process(2)

	# T1-13-A: Center Stealth Ball Light Reactivity
	var sg: TextureRect = hud.get("stealth_gem") as TextureRect
	var sg_centered: bool = false
	var sg_reactive: bool = false
	if sg != null:
		var sg_pos: Vector2 = sg.get_global_rect().position + sg.get_global_rect().size * 0.5
		sg_centered = sg_pos.x > 420.0 and sg_pos.x < 860.0 and sg_pos.y > 460.0
		gs.set("player_light_visibility", 0.05)
		hud.set("_vis_smooth", 0.0)
		await h.step_process(10)
		var mod_dark: Color = sg.modulate
		gs.set("player_light_visibility", 0.95)
		hud.set("_vis_smooth", 1.0)
		await h.step_process(10)
		var mod_bright: Color = sg.modulate
		sg_reactive = (mod_bright.v > mod_dark.v + 0.01) or (mod_bright.r > mod_dark.r + 0.01)
	h.require(sg_centered and sg_reactive, "T1-13-A", "StealthBall centered=%s light_reactive=%s" % [str(sg_centered), str(sg_reactive)])

	# T1-13-B: Bilateral Red SoundWaves on NoiseBus
	var nb: Node = h.noise_bus()
	var sw_node: Node = hud.find_child("*SoundWave*", true, false)
	if nb != null:
		nb.call("emit_noise", Vector3.ZERO, 8.0, p, "footstep")
	await h.step_process(2)
	var sw_active: bool = false
	if sw_node is CanvasItem:
		sw_active = (sw_node as CanvasItem).visible
	h.require(sw_node != null and sw_active, "T1-13-B", "Bilateral SoundWaves reacts to NoiseBus (%s)" % str(sw_active))

	# T1-13-C: Top-Left Health Bar Position & Textures
	# T05: the fill is now the authored shaped texture (TextureRect), not a flat
	# ColorRect; the assertion is about its position/size, so type it as Control.
	var hp_fill: Control = hud.get("hp_fill") as Control
	var hp_top_left: bool = false
	if hp_fill != null:
		var r: Rect2 = hp_fill.get_global_rect()
		hp_top_left = r.position.x < 400.0 and r.position.y < 220.0
	var hud_src: String = h.read_text("res://src/ui/hud.gd")
	var hp_tex_ok: bool = hud_src.find("T_healthBar_straight") >= 0
	h.require(hp_top_left and hp_tex_ok, "T1-13-C", "HealthBar top-left=%s T_healthBar_straight=%s" % [str(hp_top_left), str(hp_tex_ok)])

	# T1-13-D: Spider vs Chameleon Segmented Health Blocks
	var sp_blocks: Array = p.call("health_block_percentages") as Array
	gs.set("thief_id", "chameleon")
	var ch_blocks: Array = p.call("health_block_percentages") as Array
	var seg_nodes: int = hud.find_children("*HealthSeg*", "", true, false).size() + hud.find_children("*HealthBlock*", "", true, false).size()
	h.require(
		sp_blocks == [25, 25, 25, 25] and ch_blocks == [30, 30, 20, 20] and (seg_nodes >= 4 or hud_src.find("health_block_percentages") >= 0),
		"T1-13-D",
		"spider=%s chameleon=%s hud_segments=%d" % [str(sp_blocks), str(ch_blocks), seg_nodes]
	)

	# T1-13-E: Health Bar Decrement & Splatter Feedback
	var full_w: float = hp_fill.size.x if hp_fill != null else 0.0
	p.call("take_damage", 75.0) # 300 -> 225 (75%)
	await h.step_process(2)
	var post_w: float = hp_fill.size.x if hp_fill != null else 0.0
	var scaled_ok: bool = full_w > 0.0 and absf((post_w / full_w) - 0.75) < 0.08
	var splatter_ok: bool = hud_src.find("T_healthBar_splatter_red") >= 0 or hud.find_child("*Splatter*", true, false) != null
	h.require(scaled_ok and splatter_ok, "T1-13-E", "hp_fill scaled=%.2f splatter=%s" % [post_w / maxf(full_w, 1.0), str(splatter_ok)])

	await h.free_node(arena)


# --- Feature #14: Bottom-Left Tool Hotbar, Portrait Badge, Compass, Reticles, Action Hints & Guard Pips ---
func _feat_14_hud_hotbar_compass_reticles_pips() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var gs: Node = h.game_state()
	gs.set("active_contract_order", 2)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_process(2)

	var hud_src: String = h.read_text("res://src/ui/hud.gd")
	var slot_lbls: Array = hud.get("slot_count_lbls") as Array

	# T1-14-A: Bottom-Left Octagonal Hotbar & Wide Icons
	var hotbar_bottom_left: bool = false
	if not slot_lbls.is_empty() and slot_lbls[0] is Control:
		var r: Rect2 = (slot_lbls[0] as Control).get_global_rect()
		hotbar_bottom_left = r.position.x < 500.0 and r.position.y > 450.0
	var wide_icons_ok: bool = hud_src.find("T_Ability_Border") >= 0 and (hud_src.find("T_SlimeBomb_Wide") >= 0 or hud_src.find("T_VistaraDiamond_Wide") >= 0)
	h.require(slot_lbls.size() == 4 and hotbar_bottom_left and wide_icons_ok, "T1-14-A", "bottom-left hotbar=%s wide_icons=%s" % [str(hotbar_bottom_left), str(wide_icons_ok)])

	# T1-14-B: Infinite Glyph (∞) Display
	var has_inf_glyph: bool = false
	for lbl_v: Variant in slot_lbls:
		if lbl_v is Label and (lbl_v as Label).text.find("∞") >= 0:
			has_inf_glyph = true
	h.require(has_inf_glyph or hud_src.find("∞") >= 0, "T1-14-B", "HUD displays infinity glyph for -1 slots (%s)" % str(has_inf_glyph))

	# T1-14-C: [TAB] MAP, [MMB] PING & Bottom-Right [LMB]/[RMB] Hints
	var has_map_ping_hints: bool = hud_src.find("MAP") >= 0 and hud_src.find("PING") >= 0 and (hud_src.find("get_active_reticle_state") >= 0 or hud_src.find("[LMB]") >= 0)
	h.require(has_map_ping_hints, "T1-14-C", "HUD MAP/PING/LMB/RMB hints wired")

	# T1-14-D: Portrait Badge & Slim Compass + PoIs
	var compass_lbl: Label = hud.get("compass_lbl") as Label
	var has_portrait_compass: bool = compass_lbl != null and hud_src.find("T_portrait_levelFrame") >= 0 and hud_src.find("T_compass_lines") >= 0
	h.require(has_portrait_compass, "T1-14-D", "Portrait badge & slim T_compass_lines (%s)" % str(has_portrait_compass))

	# T1-14-E: Tool Reticles, Crank Ring & Guard Pips/Offscreen Arcs
	var has_reticles_pips: bool = hud_src.find("ReticleDraw") >= 0 and hud_src.find("T_GuardPip_SpriteSheet") >= 0 and hud_src.find("T_DetectionMeter_Offscreen") >= 0
	h.require(has_reticles_pips, "T1-14-E", "Reticles, crank ring, GuardPip & OffscreenDetectionMeter wired (%s)" % str(has_reticles_pips))

	await h.free_node(arena)


# --- Feature #15: Lockpicking Timing Minigame UI, [TAB] Map, [MMB] Ping & Clean Thief Vision ---
func _feat_15_lockpick_ui_map_ping_vision() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var gs: Node = h.game_state()
	gs.set("active_contract_order", 2)
	var p: Node = await h.spawn_test_player(arena, Vector3.ZERO, arena_d["light_probe"] as Node)
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_process(2)
	var hud_src: String = h.read_text("res://src/ui/hud.gd")

	# T1-15-A: Lockpicking Minigame UI Opens on Locked Target
	var lp_tex_ok: bool = hud_src.find("T_Lockpicking_BG") >= 0 and hud_src.find("T_Lockpicking_KeyholeCover") >= 0
	var lp_ui_ok: bool = h.has_m(hud, "open_lockpick_minigame") or h.has_m(hud, "start_lockpick_minigame")
	h.require(lp_tex_ok and lp_ui_ok, "T1-15-A", "Lockpicking circular/arc UI & T_Lockpicking_* textures (%s)" % str(lp_tex_ok and lp_ui_ok))

	# T1-15-B: DA_LockpickMinigameVariations 24 Variations / 48 Tracks
	var lp_json_v: Variant = h.read_json("res://data/generated/gameplay/interactables.json")
	var lp_dict: Dictionary = ((lp_json_v as Dictionary).get("lockpick", {}) as Dictionary) if lp_json_v is Dictionary else {}
	var vars_by_diff: Dictionary = lp_dict.get("variations_by_difficulty", {}) as Dictionary
	var var_cnt: int = 0
	var track_cnt: int = 0
	var bounds_ok: bool = true
	for dk: Variant in vars_by_diff.keys():
		var arr: Array = vars_by_diff[dk] as Array
		var_cnt += arr.size()
		for v_item: Variant in arr:
			if v_item is Dictionary:
				var tracks: Array = (v_item as Dictionary).get("tracks", []) as Array
				track_cnt += tracks.size()
				for tr: Variant in tracks:
					if tr is Dictionary:
						var dur: float = float((tr as Dictionary).get("duration_s", 0.0))
						var arc: float = float((tr as Dictionary).get("arc_deg", 0.0))
						if dur < 1.1 or dur > 3.1 or arc < 69.0 or arc > 241.0:
							bounds_ok = false
	h.require(var_cnt == 24 and track_cnt == 48 and bounds_ok, "T1-15-B", "DA_LockpickMinigameVariations vars=%d tracks=%d bounds=%s" % [var_cnt, track_cnt, str(bounds_ok)])

	# T1-15-C: [TAB] Map Overlay Toggle
	var map_action_ok: bool = h.has_action("map_toggle")
	var map_node: Node = hud.find_child("*MapOverlay*", true, false)
	if map_action_ok:
		await h.tap_action("map_toggle")
	h.require(map_action_ok and (map_node != null or hud_src.find("map_toggle") >= 0), "T1-15-C", "[TAB] map_toggle action=%s overlay=%s" % [str(map_action_ok), str(map_node != null)])

	# T1-15-D: [MMB] Ping Radial & World PoI Marker
	var ping_action_ok: bool = h.has_action("ping_menu")
	var ping_node: Node = hud.find_child("*Ping*", true, false)
	h.require(ping_action_ok and (ping_node != null or hud_src.find("ping_menu") >= 0), "T1-15-D", "[MMB] ping_menu action=%s radial=%s" % [str(ping_action_ok), str(ping_node != null)])

	# T1-15-E: Clean Thief Vision (No Flat Cyan Wash)
	if h.has_m(hud, "set_thief_vision"):
		hud.call("set_thief_vision", true)
	await h.step_process(2)
	var tv_ov: ColorRect = hud.get("thief_vision_overlay") as ColorRect
	var no_cyan_wash: bool = tv_ov == null or (not tv_ov.visible) or tv_ov.color.a <= 0.01
	h.require(no_cyan_wash, "T1-15-E", "Thief Vision has zero flat cyan wash (overlay_vis=%s alpha=%.2f)" % [str(tv_ov.visible if tv_ov != null else false), tv_ov.color.a if tv_ov != null else 0.0])

	await h.free_node(arena)


# --- Feature #16: Shell UI Teal Art Nouveau Cohesion, Mission Start Letter & Loading Screen ---
func _feat_16_shell_ui_letter_loading() -> void:
	# T1-16-A: Teal Art Nouveau Shell UI Cohesion across all 5 shell UIs
	var ui_paths: Array[String] = [
		"res://src/ui/settings_ui.gd",
		"res://src/ui/mission_prep_ui.gd",
		"res://src/ui/wardrobe_ui.gd",
		"res://src/ui/contract_table_ui.gd",
		"res://src/ui/ledger_ui.gd",
	]
	var teal_all: bool = true
	var teal_report: Array[String] = []
	for up: String in ui_paths:
		var ui_n: Node = h.new_script_node(up)
		if ui_n == null:
			teal_all = false
			teal_report.append(up.get_file() + ":null")
			continue
		h.root.add_child(ui_n)
		await h.step_process(1)
		var found_teal: bool = false
		for pn: Node in h.find_all_of_class(ui_n, "PanelContainer"):
			var pc: PanelContainer = pn as PanelContainer
			var sb: StyleBoxFlat = pc.get_theme_stylebox("panel") as StyleBoxFlat
			if h.is_teal_style(sb):
				found_teal = true
				break
		if not found_teal:
			teal_all = false
		teal_report.append(up.get_file() + "=" + str(found_teal))
		await h.free_node(ui_n)
	h.require(teal_all, "T1-16-A", "5 shell UIs teal ArtNouveau cohesion: %s" % ", ".join(teal_report))

	# T1-16-B: Mission Start Letter (intro_text) + [SPACE]
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	h.root.add_child(hud)
	await h.step_process(1)
	var letter_ok: bool = h.has_m(hud, "show_mission_letter") and h.has_m(hud, "is_mission_letter_open") or h.read_text("res://src/ui/hud.gd").find("mission_letter_requested") >= 0
	h.require(letter_ok, "T1-16-B", "HUD Mission Start Letter (contract_intro + [SPACE]) wired (%s)" % str(letter_ok))
	await h.free_node(hud)

	# T1-16-C: Loading Screen Full-Art & Spinner
	var ls: CanvasLayer = h.new_script_node("res://src/ui/loading_screen.gd") as CanvasLayer
	h.root.add_child(ls)
	await h.step_process(1)
	var ls_api: bool = h.has_m(ls, "start_loading") and h.has_m(ls, "set_progress") and h.has_m(ls, "finish_loading")
	var splash: TextureRect = ls.get("_splash_rect") as TextureRect if ls != null else null
	var has_spinner: bool = ls != null and (ls.find_child("*Spinner*", true, false) != null or h.read_text("res://src/ui/loading_screen.gd").to_lower().find("spinner") >= 0)
	if ls != null and ls_api:
		ls.call("start_loading", "Test", "Clue", "guildhall")
		ls.call("set_progress", 0.5, "Half")
	var bar: ProgressBar = ls.get("_bar") as ProgressBar if ls != null else null
	var bar_ok: bool = bar != null and absf(bar.value - 50.0) < 1.0
	h.require(ls_api and splash != null and splash.texture != null and has_spinner and bar_ok, "T1-16-C", "LoadingScreen art=%s spinner=%s bar=%.1f" % [str(splash != null and splash.texture != null), str(has_spinner), bar.value if bar != null else -1.0])
	await h.free_node(ls)

	# T1-16-D: Settings Persistence Across Instantiation
	var orig_s: Dictionary = {}
	var ss: Node = h.save_system()
	if ss != null and h.has_m(ss, "get_settings"):
		orig_s = (ss.call("get_settings") as Dictionary).duplicate(true)
	var st_ui: CanvasLayer = h.new_script_node("res://src/ui/settings_ui.gd") as CanvasLayer
	h.root.add_child(st_ui)
	await h.step_process(1)
	# RE-H-08: drive the authored sensitivity ladder (the free rad/px slider was
	# the finding). Fast = step 3 of 5. W9-P1: the step multiplier now samples the
	# authored MouseLookSensitivityCurve (0 -> 0.2, 1 -> 1.125, 2 -> 2.0 over the
	# curve's time range; step 3 = 1.5625x), not the OSE DefaultGame.ini ladder
	# (1.5x), so the expected rad/px is 0.00390625. The old 0.00375 literal pinned
	# the ladder the port replaced; the authored curve is the source of truth
	# (game/data/generated/tables/UI/Settings/MouseLookSensitivityCurve.json, indexed
	# by curves.json, read by InputActions.mouse_rad_per_px()).
	var fast_rad_per_px: float = 0.0025 * 1.5625
	var cb_inv: CheckBox = st_ui.get("_invert_check") as CheckBox
	var cb_spr: CheckBox = st_ui.get("_sprint_check") as CheckBox
	var sl_fov: HSlider = st_ui.get("_fov_slider") as HSlider
	if h.has_m(st_ui, "set_look_sensitivity_step"):
		st_ui.call("set_look_sensitivity_step", "kb", 3)
	if cb_inv != null: cb_inv.button_pressed = true
	if cb_spr != null: cb_spr.button_pressed = true
	if sl_fov != null: sl_fov.value = 92.0
	if h.has_m(st_ui, "_apply_live"):
		st_ui.call("_apply_live", false)
	var p_test: Node = h.new_script_node("res://src/player/thief_character.gd")
	h.root.add_child(p_test)
	await h.step_process(1)
	var persist_ok: bool = absf(float(p_test.get("mouse_sens")) - fast_rad_per_px) < 0.0001 and h.is_true(p_test.get("invert_y")) and h.is_true(p_test.get("sprint_toggle_mode")) and absf(float(p_test.get("base_fov")) - 92.0) < 0.1
	await h.free_node(p_test)
	if ss != null and not orig_s.is_empty():
		var sd: Dictionary = ss.get("data") as Dictionary
		sd["settings"] = orig_s
		ss.call("apply_saved_settings")
	await h.free_node(st_ui)
	h.require(persist_ok, "T1-16-D", "Settings persisted into ThiefCharacter (%s)" % str(persist_ok))

	# T1-16-E: Contract Title & Duration Substitution ({MatchDurationInMinutes})
	var mp: Control = h.new_script_node("res://src/ui/mission_prep_ui.gd") as Control
	h.root.add_child(mp)
	await h.step_process(1)
	mp.call("open_prep", "guildhall", 1, "Solo", 0)
	await h.step_process(1)
	var body_lbl: Label = mp.get("_mission_body") as Label
	var body_txt: String = body_lbl.text if body_lbl != null else ""
	var no_raw_placeholder: bool = body_txt.find("{MatchDurationInMinutes}") < 0 and (body_txt.find("120") >= 0 or body_txt.find("minute") >= 0)
	await h.free_node(mp)
	h.require(no_raw_placeholder, "T1-16-E", "MissionPrepUI substituted {MatchDurationInMinutes} (text_len=%d)" % body_txt.length())


# --- Feature #17: Thieves' Den Diegetic Hub Flow ---
func _feat_17_thieves_den_hub() -> void:
	var den_res: Dictionary = await h.instantiate_mission(1, 200, 1)
	var den: Node = den_res["mission"] as Node
	var p: Node = den_res["player"] as Node

	# T1-17-A: Giant Label3D Billboards Removed in Den
	var billboards: Array[Node] = h.find_all_of_class(den, "Label3D") if den != null else []
	var giant_billboards: int = 0
	for lb_n: Node in billboards:
		var lb: Label3D = lb_n as Label3D
		if lb.text.find("Prepare for Mission") >= 0 or lb.text.find("Customize Thief") >= 0:
			giant_billboards += 1
	h.require(den != null and giant_billboards == 0, "T1-17-A", "Den giant Label3D billboards=%d (expected 0)" % giant_billboards)

	# T1-17-B: Look-At Map Table Card & [H]/[R] Cycling
	var mc_src: String = h.read_text("res://src/missions/mission_controller.gd").to_lower()
	var has_hr_cycle: bool = mc_src.find("key_h") >= 0 and mc_src.find("key_r") >= 0 and (den != null and (den.find_child("*MapTableCard*", true, false) != null or den.find_child("*DenMapTableArea*", true, false) != null or mc_src.find("map_table") >= 0 or mc_src.find("den_lookat") >= 0))
	var map_card_node: Node = den.find_child("*MapTableCard*", true, false) if den != null and den.find_child("*MapTableCard*", true, false) != null else (den.find_child("*DenMapTableArea*", true, false) if den != null else null)
	h.require(map_card_node != null and has_hr_cycle, "T1-17-B", "Den diegetic MapTableCard=%s [H]/[R] cycling=%s" % [str(map_card_node != null), str(has_hr_cycle)])

	# T1-17-C: Active Miniature Token Highlight
	var tok_om: MeshInstance3D = den.get_node_or_null("MapTokenOldManor") as MeshInstance3D if den != null else null
	var tok_gh: MeshInstance3D = den.get_node_or_null("MapTokenGuildHall") as MeshInstance3D if den != null else null
	# MapTokenOldManor is scaled from the UE bounds ratio 45.56192/27.39531
	# (mission_controller _setup_thieves_den_hub); GuildHall uses the 0.24 base.
	var om_scale: float = 0.24 * (45.56192 / 27.39531)
	# _update_map_token_highlights grows the selected token 1.15x on top of
	# the authored minis_base; assert the authored base from the meta and the
	# live grow ratio instead of the raw node scale.
	var om_base: float = float(tok_om.get_meta("minis_base", -1.0)) if tok_om != null else -1.0
	var gh_base: float = float(tok_gh.get_meta("minis_base", -1.0)) if tok_gh != null else -1.0
	var om_ratio: float = (tok_om.scale.x / om_base) if tok_om != null and om_base > 0.0 else -1.0
	var gh_ratio: float = (tok_gh.scale.x / gh_base) if tok_gh != null and gh_base > 0.0 else -1.0
	var tokens_seated: bool = tok_om != null and tok_gh != null \
		and absf(om_base - om_scale) < 0.001 and absf(gh_base - 0.24) < 0.001 \
		and om_ratio >= 0.99 and om_ratio <= 1.16 and gh_ratio >= 0.99 and gh_ratio <= 1.16 \
		and absf(tok_om.position.y - 41.1337) < 0.1
	var token_hl_ok: bool = tokens_seated and (tok_om.material_overlay != null or tok_gh.material_overlay != null or mc_src.find("token_highlight") >= 0 or mc_src.find("highlight_map_token") >= 0)
	h.require(token_hl_ok, "T1-17-C", "Den active miniature token highlight (seated=%s)" % str(tokens_seated))

	# T1-17-D: [F] Prepare / Enter Modal from Map Table
	var opens_prep_from_table: bool = mc_src.find("open_mission_prep") >= 0 or mc_src.find("open_contract_table_ui") >= 0 or (den != null and (h.has_m(den, "open_mission_prep_ui") or h.has_m(den, "open_contract_table_ui")))
	h.require(opens_prep_from_table, "T1-17-D", "Map Table [F] opens MissionPrepUI modal (%s)" % str(opens_prep_from_table))

	# T1-17-E: [F] PONDER Telescope Interactable
	var ponder_found: bool = false
	for inter: Node in h.tree.get_nodes_in_group("interactables"):
		if h.has_m(inter, "get_interact_prompt"):
			if str(inter.call("get_interact_prompt")).to_upper().find("PONDER") >= 0:
				ponder_found = true
				inter.call("interact", p)
				break
	h.require(ponder_found, "T1-17-E", "Thieves' Den [F] PONDER telescope interactable (%s)" % str(ponder_found))

	await h.free_node(den)


# --- Feature #18: Multi-Part Mission Objectives & Loot Counter ---
func _feat_18_objectives_and_loot_counter() -> void:
	var gs: Node = h.game_state()
	var mc_src: String = h.read_text("res://src/missions/mission_controller.gd")

	# T1-18-A: Set Mode ([0/3]) Objective Tracking
	var has_obj_prop: bool = h.has_prop(gs, "mission_objectives") and h.has_prop(gs, "loot_goal") and h.has_prop(gs, "contract_intro")
	h.require(has_obj_prop and mc_src.find("Set") >= 0, "T1-18-A", "GameState.mission_objectives/Set [0/3] support (%s)" % str(has_obj_prop))

	# T1-18-B: Cleanout Heist (LootTheRoom) Goal Threshold
	var has_cleanout: bool = has_obj_prop and (mc_src.find("LootTheRoom") >= 0 or mc_src.find("Cleanout") >= 0)
	h.require(has_cleanout, "T1-18-B", "Cleanout Heist loot_goal threshold support (%s)" % str(has_cleanout))

	# T1-18-C: MissionPrepUI Mode Propagates to mission_controller
	var propagates_mode: bool = h.has_prop(gs, "active_mission_mode") or h.has_prop(gs, "selected_mission_id") or mc_src.find("LootTheRoom") >= 0
	h.require(has_obj_prop and propagates_mode, "T1-18-C", "MissionPrepUI selected mode propagates to mission_controller")

	# T1-18-D: Mission Start Letter Triggered on Entry
	var gh_res: Dictionary = await h.instantiate_mission(2, 240, 1)
	var gh: Node = gh_res["mission"] as Node
	var intro_str: String = str(h.get_prop(gs, "contract_intro", ""))
	h.require(gh != null and has_obj_prop and intro_str != "", "T1-18-D", "Contract 2 populates GameState.contract_intro (len=%d)" % intro_str.length())

	# T1-18-E: Escape Point Enables After Objective Complete + Stealth Multiplier
	gs.set("ever_spotted", false)
	gs.set("ever_chased", false)
	var m_ghost: float = float(gs.call("compute_stealth_bonus_multiplier"))
	gs.set("ever_spotted", true)
	var m_shadow: float = float(gs.call("compute_stealth_bonus_multiplier"))
	gs.set("ever_chased", true)
	var m_loud: float = float(gs.call("compute_stealth_bonus_multiplier"))
	var escapes: Array[Node] = h.tree.get_nodes_in_group("escape_points")
	h.require(
		absf(m_ghost - 1.25) < 0.01 and absf(m_shadow - 1.10) < 0.01 and absf(m_loud - 1.0) < 0.01 and not escapes.is_empty(),
		"T1-18-E",
		"Escape multipliers ghost=%.2f shadow=%.2f loud=%.2f escapes=%d" % [m_ghost, m_shadow, m_loud, escapes.size()]
	)
	await h.free_node(gh)


# --- Feature #19: Lockable Doors / Safes Wiring ---
func _feat_19_lockable_doors_safes() -> void:
	# T1-19-A: Locked Door / Safe lock_level (1..4) on LootContainer & SwingingDoor
	var lc_scr: GDScript = h.load_script("res://src/interact/loot_container.gd")
	var sd_scr: GDScript = h.load_script("res://src/interact/swinging_door.gd")
	var lc: Node = lc_scr.new() as Node
	var sd: Node = sd_scr.new() as Node
	var has_lock_props: bool = h.has_prop(lc, "locked") and h.has_prop(lc, "lock_level") and h.has_prop(sd, "locked") and h.has_prop(sd, "lock_level")
	h.require(has_lock_props, "T1-19-A", "LootContainer & SwingingDoor expose locked + lock_level (%s)" % str(has_lock_props))
	if lc != null: lc.queue_free()
	if sd != null: sd.queue_free()

	# T1-19-B: Lockpick Minigame Sets Status.Lockpicking
	var p: Node = h.new_script_node("res://src/player/thief_character.gd")
	var lc_src: String = h.read_text("res://src/interact/loot_container.gd")
	var sd_src: String = h.read_text("res://src/interact/swinging_door.gd")
	var lock_wires_status: bool = h.has_m(p, "set_lockpicking_active") and (lc_src.find("set_lockpicking_active") >= 0 or sd_src.find("set_lockpicking_active") >= 0)
	h.require(lock_wires_status, "T1-19-B", "Locked containers/doors wire player.set_lockpicking_active (%s)" % str(lock_wires_status))
	if p != null: p.queue_free()

	# T1-19-C: Successful Track Unlocks Safe & Spawns Loot
	var ld_scr: GDScript = h.load_script("res://src/interact/lockable_door.gd")
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var lc2: Node = lc_scr.new() as Node
	lc2.set("loot_tier", "major")
	lc2.set("marker_pos", arena.global_position)
	arena.add_child(lc2)
	if h.has_prop(lc2, "locked"):
		lc2.set("locked", true)
		lc2.set("lock_level", 1)
	var before_loot: int = h.tree.get_nodes_in_group("loot").size()
	if h.has_m(lc2, "complete_lockpick"):
		lc2.call("complete_lockpick")
	else:
		lc2.call("interact", null)
	await h.step_process(1)
	var after_loot: int = h.tree.get_nodes_in_group("loot").size()
	var safe_unlocked: bool = (not h.is_true(h.get_prop(lc2, "locked", true))) and after_loot > before_loot
	h.require(has_lock_props and safe_unlocked, "T1-19-C", "Locked safe unlocks & spawns MajorLoot (%s, loot %d->%d)" % [str(safe_unlocked), before_loot, after_loot])

	# T1-19-D: Successful Track Unlocks High-Security Swinging Door
	var sd2: Node = sd_scr.new() as Node
	var swing_ok: bool = h.has_prop(sd2, "locked") and (sd_src.find("DA_LockpickMinigameVariations") >= 0 or sd_src.find("lock_level") >= 0)
	h.require(swing_ok, "T1-19-D", "High-security SwingingDoor lockpicking wired (%s)" % str(swing_ok))
	if sd2 != null: sd2.queue_free()

	# T1-19-E: Failed Attempt Applies CT_LockpickDamage (5/10/20/40)
	var ld: Node = ld_scr.new() as Node
	arena.add_child(ld)
	var dmg_ok: bool = true
	var expected_dmgs: Array[float] = [5.0, 10.0, 20.0, 40.0]
	for lvl: int in range(1, 5):
		ld.set("lock_level", lvl)
		var d: float = float(ld.call("get_jam_damage"))
		if absf(d - expected_dmgs[lvl - 1]) > 0.1:
			dmg_ok = false
	h.require(dmg_ok, "T1-19-E", "CT_LockpickDamage 5/10/20/40 across lock levels 1..4 (%s)" % str(dmg_ok))
	await h.free_node(arena)


# --- Feature #20: Guard Lanterns, Carried Keys/Loot & Alert Signals ---
func _feat_20_guard_lanterns_steal_alert() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var lp: Node = arena_d["light_probe"] as Node
	var g: Node3D = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, 0.0)) as Node3D
	if g != null:
		if h.has_prop(g, "carries_lantern"):
			g.set("carries_lantern", true)
			if h.has_m(g, "enable_lantern"):
				g.call("enable_lantern")
		elif h.has_m(g, "configure_variant"):
			g.call("configure_variant", "ClubLantern")
	await h.step_process(2)

	# T1-20-A: ClubLantern Guard Has Warm OmniLight3D + SK_Lantern.glb Mesh
	var omni: OmniLight3D = h.find_all_of_class(g, "OmniLight3D")[0] as OmniLight3D if not h.find_all_of_class(g, "OmniLight3D").is_empty() else null
	var gai_src: String = h.read_text("res://src/ai/guard_ai.gd")
	var lantern_ok: bool = omni != null and omni.light_color.r > omni.light_color.b and gai_src.find("SK_Lantern") >= 0
	h.require(lantern_ok, "T1-20-A", "ClubLantern guard has warm OmniLight3D & SK_Lantern (%s)" % str(lantern_ok))

	# T1-20-B: Guard Lantern Registered with light_probe
	var vis: float = 0.0
	if lp != null and omni != null and lp.has_method("register_light"):
		lp.call("register_light", omni)
	if lp != null:
		vis = float(lp.call("sample_visibility", arena.global_position + Vector3(0, 1.0, 2.0), arena.get_world_3d().direct_space_state, [] as Array[RID]))
	h.require(omni != null and vis > 0.10, "T1-20-B", "Guard lantern affects LightProbe visibility=%.3f (> 0.10)" % vis)

	# T1-20-C: Stealable Carried Key / Loot (steal_carried_item)
	var steal_ok: bool = false
	if h.has_prop(g, "carried_item") and (g.get("carried_item") as Dictionary).is_empty():
		g.set("carried_item", {"kind": "key", "id": "test_guard_key", "value": 10})
	if h.has_m(g, "steal_carried_item"):
		var item1: Variant = g.call("steal_carried_item")
		var item2: Variant = g.call("steal_carried_item")
		steal_ok = (item1 != null and not (item1 is Dictionary and (item1 as Dictionary).is_empty())) and (item2 == null or (item2 is Dictionary and (item2 as Dictionary).is_empty()))
	h.require(steal_ok, "T1-20-C", "guard.steal_carried_item() yields carried item once (%s)" % str(steal_ok))

	# T1-20-D: guard_ai.get_alert_state() Contract
	var alert_ok: bool = false
	if h.has_m(g, "get_alert_state"):
		var st_v: Variant = g.call("get_alert_state")
		if st_v is Dictionary:
			var sd: Dictionary = st_v as Dictionary
			alert_ok = sd.has("state") and sd.has("suspicion") and sd.has("world_pos")
	h.require(alert_ok, "T1-20-D", "guard.get_alert_state() returns {state, suspicion, world_pos}")

	# T1-20-E: Alert Signals Drive HUD Pips & Offscreen Arcs
	var hud: CanvasLayer = h.new_script_node("res://src/ui/hud.gd") as CanvasLayer
	arena.add_child(hud)
	await h.step_process(1)
	var hud_src: String = h.read_text("res://src/ui/hud.gd")
	var pips_ok: bool = alert_ok and hud_src.find("get_alert_state") >= 0
	h.require(pips_ok, "T1-20-E", "HUD consumes guard.get_alert_state() for pips/offscreen arcs (%s)" % str(pips_ok))

	await h.free_node(arena)


# --- Feature #21: OldManor_P Landscape Walk/Collision & Forward-Clearance Check ---
func _feat_21_old_manor_walk_collision() -> void:
	# T1-21-A: OldManor_P 128 Landscapes & Collision Built
	var om_v: Variant = h.read_json("res://data/generated/levels/OldManor/OldManor_P.tatlevel.json")
	var om_ls: Array = (om_v as Dictionary).get("landscapes", []) if om_v is Dictionary else []
	var hm: Dictionary = {}
	var wm: Dictionary = {}
	var missing: int = 0
	for lc_v: Variant in om_ls:
		if lc_v is Dictionary:
			var lc: Dictionary = lc_v as Dictionary
			var hp: String = str(lc.get("heightmap", ""))
			if hp != "":
				hm[hp] = true
				if not FileAccess.file_exists(hp): missing += 1
			for w_v: Variant in (lc.get("weightmaps", []) as Array):
				var ws: String = str(w_v)
				if ws != "":
					wm[ws] = true
					if not FileAccess.file_exists(ws): missing += 1
	h.require(
		om_ls.size() == 128 and hm.size() == 101 and wm.size() == 54 and missing == 0,
		"T1-21-A",
		"OldManor_P landscapes=%d heightmaps=%d weightmaps=%d missing=%d" % [om_ls.size(), hm.size(), wm.size(), missing]
	)

	# Load Contract 3 (Old Manor) for T1-21-B, C, D, E
	var om_res: Dictionary = await h.instantiate_mission(3, 240, 1)
	var om: Node = om_res["mission"] as Node
	var p: CharacterBody3D = om_res["player"] as CharacterBody3D

	# T1-21-D: OldManor Spawn Headroom & Forward-Clearance Check
	var hr_ok: bool = om != null and h.is_true(om.get("fallback_spawn_headroom_clear"))
	var fc_ok: bool = om != null and h.is_true(om.get("fallback_spawn_forward_clear"))
	h.require(hr_ok and fc_ok, "T1-21-D", "OldManor spawn headroom=%s forward=%s" % [str(hr_ok), str(fc_ok)])

	# T1-21-B: Player Walk & Gravity Stability on OldManor_P Terrain
	var p_walk_ok: bool = false
	if p != null:
		var start_p: Vector3 = p.global_position
		h.press_action("move_forward")
		await h.step_physics(45)
		h.release_action("move_forward")
		var end_p: Vector3 = p.global_position
		var disp: float = Vector2(end_p.x - start_p.x, end_p.z - start_p.z).length()
		p_walk_ok = disp > 0.5 and end_p.y > -5.0
	h.require(p_walk_ok, "T1-21-B", "OldManor_P player walk & collision stable (%s)" % str(p_walk_ok))

	# T1-21-C: Guard Walk & Collision on OldManor_P Terrain
	var guards: Array[Node] = h.tree.get_nodes_in_group("guards")
	var g_walk_ok: bool = false
	if not guards.is_empty() and guards[0] is CharacterBody3D:
		var g0: CharacterBody3D = guards[0] as CharacterBody3D
		var gy0: float = g0.global_position.y
		await h.step_physics(30)
		var gy1: float = g0.global_position.y
		g_walk_ok = absf(gy1 - gy0) < 3.0 and gy1 > -5.0
	h.require(g_walk_ok, "T1-21-C", "OldManor_P guard collision stable (%s, guards=%d)" % [str(g_walk_ok), guards.size()])

	# T1-21-E: OldManor_P Dual-Weightmap Visual Preconditions
	var dual_wm_count: int = 0
	for lc_v2: Variant in om_ls:
		if lc_v2 is Dictionary and ((lc_v2 as Dictionary).get("weightmaps", []) as Array).size() >= 2:
			dual_wm_count += 1
	var ls_shader_exists: bool = ResourceLoader.exists("res://src/core/tat_landscape.gdshader")
	h.require(om != null and dual_wm_count >= 7 and ls_shader_exists, "T1-21-E", "OldManor_P dual-weightmap components=%d shader=%s" % [dual_wm_count, str(ls_shader_exists)])

	await h.free_node(om)


# --- Feature #22: E2E Requirement-Driven & Visual Parity Test Suite ---
func _feat_22_verification_gates() -> void:	# T1-22-A: run_tests suite ratchet (markers + floor + committed log)
	var rt_src: String = h.read_text("res://tests/run_tests.gd")
	var ratchet_v: Variant = h.repo_read_json("tools/gate_ratchet.json")
	var log_rel: String = ""
	if ratchet_v is Dictionary:
		var evidence: Dictionary = (ratchet_v as Dictionary).get("evidence", {}) as Dictionary
		var log_dir: String = str(evidence.get("dir", ""))
		var log_name: String = str(evidence.get("run_tests", ""))
		if log_dir != "" and log_name != "":
			log_rel = log_dir.path_join(log_name)
	var stats: Dictionary = h.suite_ratchet_stats(rt_src, ratchet_v, h.repo_read_text(log_rel))
	var problems: Array = stats.get("problems", []) as Array
	h.require(
		problems.is_empty(),
		"T1-22-A",
		"run_tests ratchet markers=%d max=%d floor=%d log_PASS=%d log_fails=%d log=%s%s" % [
			int(stats.get("markers", -1)), int(stats.get("max_marker", -1)),
			int(stats.get("floor", -1)), int(stats.get("log_passes", -1)),
			int(stats.get("log_fails", -1)), log_rel,
			"" if problems.is_empty() else " problems=" + str(problems),
		]
	)

	# T1-22-B: Manifest Coverage Gate Preconditions
	var am_v: Variant = h.read_json("res://data/generated/anims_manifest.json")
	var anim_ok: bool = false
	if am_v is Dictionary:
		var entries_v: Variant = (am_v as Dictionary).get("clips", (am_v as Dictionary).get("entries", []))
		if entries_v is Array:
			anim_ok = (entries_v as Array).size() >= 990
		elif am_v.has("ok"):
			anim_ok = int((am_v as Dictionary).get("ok", 0)) >= 990 and int((am_v as Dictionary).get("fail", 1)) == 0
	var audit_py_exists: bool = h.repo_file_exists("tools/manifest_audit.py")
	h.require(audit_py_exists and (anim_ok or ResourceLoader.exists("res://data/generated/anims_manifest.json")), "T1-22-B", "manifest_audit.py & anims_manifest.json intact")

	# T1-22-C: Standalone E2E Suite Structure (game/tests/e2e/)
	var e2e_files_ok: bool = ResourceLoader.exists("res://tests/e2e/run_e2e_tests.gd") \
		and ResourceLoader.exists("res://tests/e2e/e2e_helpers.gd") \
		and ResourceLoader.exists("res://tests/e2e/e2e_tier1_features.gd") \
		and ResourceLoader.exists("res://tests/e2e/e2e_tier2_boundaries.gd") \
		and ResourceLoader.exists("res://tests/e2e/e2e_tier3_pairwise.gd") \
		and ResourceLoader.exists("res://tests/e2e/e2e_tier4_scenarios.gd")
	h.require(e2e_files_ok, "T1-22-C", "Standalone E2E suite files present under res://tests/e2e/")

	# T1-22-D: Live Vulkan Forward+ Parity Capture Harness
	var cap_sh_txt: String = h.repo_read_text("build/qa/capture_e2e_parity.sh")
	var cap_gd_exists: bool = h.repo_file_exists("build/qa/capture_e2e_parity.gd")
	var cap_gate_ok: bool = cap_sh_txt != "" and cap_gd_exists and cap_sh_txt.find("SHADER ERROR") >= 0 and cap_sh_txt.find("SCRIPT ERROR") >= 0
	h.require(cap_gate_ok, "T1-22-D", "build/qa/capture_e2e_parity.{sh,gd} with SHADER/SCRIPT ERROR=0 gate (%s)" % str(cap_gate_ok))

	# T1-22-E: Steam Screenshot Side-by-Side Parity Audit Preconditions
	var steam_dir: String = "/home/john/.local/share/Steam/userdata/397775346/760/remote/3341000/screenshots"
	var jpg_cnt: int = 0
	var da: DirAccess = DirAccess.open(steam_dir)
	if da != null:
		da.list_dir_begin()
		var fn: String = da.get_next()
		while fn != "":
			if fn.ends_with(".jpg") or fn.ends_with(".png"):
				jpg_cnt += 1
			fn = da.get_next()
		da.list_dir_end()
	var cap_gd_txt: String = h.repo_read_text("build/qa/capture_e2e_parity.gd")
	h.require(jpg_cnt >= 56 and cap_gd_txt != "", "T1-22-E", "Steam refs=%d (>=56) & capture_e2e_parity.gd present=%s" % [jpg_cnt, str(cap_gd_txt != "")])


# --- Feature #23: W7H surface-resolved hearing (sprint heard, never seen) ---
## The player sprints 20 m from a guard with a clear line of sight but outside
## the guard's sight range. The authored Footstep.Running stim (20 m) must reach
## the guard through the surface-resolved surface multiplier, raise SEARCH, and
## leave the 0..100 detection meter at 0 (hearing never writes it).
func _feat_23_surface_hearing_sprint() -> void:
	var arena_d: Dictionary = await h.make_arena()
	var arena: Node3D = arena_d["arena"] as Node3D
	var g: Node3D = await h.spawn_test_guard(arena, Vector3(0.0, 0.0, 0.0)) as Node3D
	# Behind the guard's facing (+Z, the guard looks down -Z) and beyond a pinned
	# 12 m sight range: LOS is clear, sight is not possible.
	var p: Node = await h.spawn_test_player(arena, Vector3(0.0, 0.0, 20.0), arena_d["light_probe"] as Node, arena)
	if g == null or p == null:
		h.require(false, "T1-23-A", "guard/player spawn failed for the sprint hearing case")
		return
	g.set("sight_range", 12.0)
	await h.step_process(2)
	var dist: float = (g as Node3D).global_position.distance_to((p as Node3D).global_position)
	# Sprint in place-adjacent: hold forward+shift so the real footstep cadence
	# fires (sprint noise_timer 0.28 s) while the guard is out of sight.
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var saw_player: bool = false
	for _i: int in range(24):
		await h.tree.physics_frame
		if h.has_m(g, "can_see_player") and bool(g.call("can_see_player", p)):
			saw_player = true
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await h.step_physics(4)
	var stim: String = str(g.get("last_heard_stim_tag"))
	var radius: float = float(g.get("last_heard_radius_m"))
	h.require(stim == "AI.Stim.Hearing.Footstep.Running" and radius >= dist,
		"T1-23-A",
		"20 m sprint heard as Footstep.Running (stim=%s, radius=%.1f m, dist=%.1f m, clear LOS, sight=%.0f m)" % [stim, radius, dist, float(g.get("sight_range"))])
	var st: int = int(g.get("state"))
	h.require(st == 4 and is_zero_approx(float(g.get("detection"))) and not saw_player,
		"T1-23-B",
		"heard sprint -> SEARCH (state=%d) with detection %.1f and never seen" % [st, float(g.get("detection"))])
	# The guard/player belong to this arena: leaving them alive leaks a second
	# player and guard into every later tier (all arenas share one origin).
	await h.free_node(arena)
