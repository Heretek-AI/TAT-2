extends Control
## Main Menu: 3D BeautifulCorner Startscreen backdrop (MacNeish Jeweller) + Title overlay + Contract Journal.

const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const SettingsUIScript := preload("res://src/ui/settings_ui.gd")
const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")
const GuardAnimLibScript: GDScript = preload("res://src/core/animation_library.gd")

const STARTSCREEN_GUARD_GLB: String = "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/SK_GuardEnforcer__Preview.glb"
const STARTSCREEN_GUARD_UE_MESH: String = "/Game/Art/Animation/GuardEnforcer/Skin/Base/SK_GuardEnforcer__Preview"

## Authored CineCameraActor_0 from MainMenu.json:
## RelativeLocation (-1271.964, 1460.8873, 45.659775) cm -> Godot metres
## RelativeRotation Pitch +13.8 deg, Yaw -46.335075 deg; FieldOfView 76.758446 (16:9) -> vFOV 48.03 deg.
const STARTSCREEN_CAM_EYE: Vector3 = Vector3(-12.7196, 0.4566, 14.6089)
const STARTSCREEN_CAM_FWD: Vector3 = Vector3(0.67051, 0.238533, -0.702509)
const STARTSCREEN_CAM_FOCUS_M: float = 17.03233
const STARTSCREEN_CAM_VFOV: float = 48.03
const STARTSCREEN_CAM_PITCH_DEG: float = 13.8

var thief_opt: OptionButton
var diff_opt: OptionButton
var contract_list: ItemList
var detail_lbl: Label
var portrait_rect: TextureRect
var net_status: Label
var ip_edit: LineEdit
var journal_panel: PanelContainer
var _menu_cam: Camera3D
var _shop_glow: OmniLight3D
var _sway_t: float = 0.0
var selected_order: int = 1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_3d_backdrop()
	_build_ui()
	_maybe_autostart_contract()


## QA hook: `tat2/debug_autostart_contract` is 0 in shipped builds. The mobile
## packaging tool can set it to a contract order to boot straight into a mission.
func _maybe_autostart_contract() -> void:
	var order: int = int(ProjectSettings.get_setting("tat2/debug_autostart_contract", 0))
	if order <= 0:
		return
	var info: Dictionary = GameData.get_contract_display(order)
	var map_id: String = str(info.get("map_id", "old_manor"))
	print("TAT-2 QA autostart contract=", order, " map=", map_id)
	GameState.active_contract_order = order
	GameState.active_map_id = map_id
	get_tree().call_deferred("change_scene_to_file", "res://scenes/mission.tscn")


func _build_3d_backdrop() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	add_child(svc)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.scaling_3d_scale = 0.75
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(vp)

	var scene_root := Node3D.new()
	vp.add_child(scene_root)

	var loader := LevelLoaderScript.new()
	scene_root.add_child(loader)
	var sublevels: Array[String] = [
		"res://data/generated/levels/Menus/MainMenu/BeautifulCorner_Startscreen_P.tatlevel.json",
		"res://data/generated/levels/Menus/MainMenu/BeautifulCorner_Startscreen_Lighting.tatlevel.json",
	]
	var load_res: Dictionary = loader.load_sublevels(sublevels, scene_root, null, 32, false)
	_apply_startscreen_trim_specular(scene_root)

	var sky_light_v: Variant = load_res.get("sky_light", {})
	var sky_light: Dictionary = sky_light_v as Dictionary if sky_light_v is Dictionary else {}
	var fog_vol_v: Variant = load_res.get("fog_volume", {})
	var fog_vol: Dictionary = fog_vol_v as Dictionary if fog_vol_v is Dictionary else {}
	var pp_v: Variant = load_res.get("post_process", {})
	var pp_doc: Dictionary = pp_v as Dictionary if pp_v is Dictionary else {}
	var pp_set_v: Variant = pp_doc.get("settings", {})
	var pp_settings: Dictionary = pp_set_v as Dictionary if pp_set_v is Dictionary else {}

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.012, 0.016, 0.036)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.85)
	e.ambient_light_energy = clampf(float(sky_light.get("intensity", 2.0)) * 0.16, 0.08, 0.45)

	var fog_col: Color = Color(0.06, 0.07, 0.14)
	var fog_ins_v: Variant = fog_vol.get("inscattering", null)
	if fog_ins_v is Array and (fog_ins_v as Array).size() >= 3:
		var fa: Array = fog_ins_v as Array
		var fmax: float = maxf(float(fa[0]), maxf(float(fa[1]), maxf(float(fa[2]), 0.001)))
		fog_col = Color(float(fa[0]) / fmax * 0.14, float(fa[1]) / fmax * 0.14, float(fa[2]) / fmax * 0.14)
	e.fog_enabled = true
	e.fog_light_color = fog_col
	e.fog_density = 0.008
	e.fog_sky_affect = 0.0

	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.15
	e.glow_enabled = true
	e.glow_intensity = clampf(float(pp_settings.get("BloomIntensity", 6.336)) * 0.08, 0.0, 0.8)
	e.glow_bloom = 0.22
	e.glow_hdr_threshold = 1.0
	if pp_settings.has("ColorContrast"):
		var cc_v: Variant = pp_settings.get("ColorContrast")
		var cc_val: float = 1.0
		if cc_v is Dictionary:
			cc_val = float((cc_v as Dictionary).get("X", 1.0))
		elif cc_v is Array and not (cc_v as Array).is_empty():
			cc_val = float((cc_v as Array)[0])
		elif cc_v is float or cc_v is int:
			cc_val = float(cc_v)
		e.adjustment_enabled = true
		e.adjustment_contrast = clampf(cc_val, 0.5, 1.5)

	if not MobileProfile.is_mobile():
		# Desktop volumetric mist for car headlights, multi-octave neon bloom, SSR & SSIL
		# (R3 APPROXIMATE Forward+ mappings for BeautifulCorner_Startscreen_Lighting).
		e.volumetric_fog_enabled = true
		e.volumetric_fog_density = 0.016
		e.volumetric_fog_albedo = Color(0.85, 0.82, 0.90)
		e.volumetric_fog_anisotropy = 0.45
		e.volumetric_fog_length = 45.0
		e.volumetric_fog_sky_affect = 0.0
		e.glow_hdr_scale = 2.0
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		for gl_i: int in range(5):
			e.set_glow_level(gl_i, true)
		e.ssr_enabled = true
		e.ssr_max_steps = 48
		e.ssr_fade_in = 0.15
		e.ssr_fade_out = 2.0
		e.ssr_depth_tolerance = 0.2
		e.ssil_enabled = true
		e.ssil_radius = 4.0
		e.ssil_intensity = 1.1

	env.environment = e
	scene_root.add_child(env)

	_menu_cam = Camera3D.new()
	_menu_cam.name = "StartscreenCineCamera"
	_menu_cam.fov = STARTSCREEN_CAM_VFOV
	_menu_cam.position = STARTSCREEN_CAM_EYE
	_menu_cam.current = true
	scene_root.add_child(_menu_cam)
	_menu_cam.look_at(STARTSCREEN_CAM_EYE + STARTSCREEN_CAM_FWD * STARTSCREEN_CAM_FOCUS_M, Vector3.UP)

	# Tune extracted car headlights (#8/#9, BP_CarBC Temperature 3500K) for warm volumetric mist.
	for child: Node in scene_root.get_children():
		if child is SpotLight3D:
			var sl: SpotLight3D = child as SpotLight3D
			if sl.light_energy >= 3.9 and sl.position.x < -10.0:
				sl.light_color = Color(1.0, 0.80, 0.55)
				sl.spot_angle = 32.0
				sl.spot_attenuation = 2.0
				sl.light_energy = 2.6
				sl.light_volumetric_fog_energy = 2.5

	# Restore missing SM_LightStreetA glowing cream-gold bulb aligned with BP_StreetlightA_C_2 & Spot10.
	var bulb := MeshInstance3D.new()
	bulb.name = "StartscreenStreetlampBulb"
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.24
	bulb_mesh.height = 0.48
	bulb_mesh.radial_segments = 16
	bulb_mesh.rings = 10
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb_mat.albedo_color = Color(1.0, 0.90, 0.72)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.84, 0.62)
	bulb_mat.emission_energy_multiplier = 4.5
	bulb_mesh.material = bulb_mat
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(7.72, 12.25, 4.83)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene_root.add_child(bulb)

	_spawn_startscreen_guard(scene_root, loader)


## T1-03-E: Left-corner trim specular fix (KF01 shopfront scrollwork).
## The authored trim metals (SM_Trim_SmB_*/MI_Trim*) resolve through the shared
## PBR path with Godot's default specular reflectance (0.5), which blows out
## the pale-gold scrollwork in the left corner under the neon wash. This
## post-pass clamps trim-batch materials to specular <= 0.35 /
## roughness >= 0.45 with per-node overrides only: shared meshes and cached
## materials are never mutated, and no texture is invented (T2-03-E gate).
const STARTSCREEN_TRIM_SPECULAR_MAX := 0.30
const STARTSCREEN_TRIM_ROUGHNESS_MIN := 0.55


func _apply_startscreen_trim_specular(scene_root: Node3D) -> void:
	if scene_root == null:
		return
	for n: Node in scene_root.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if gi == null or not gi.has_meta("ue_mesh"):
			continue
		if str(gi.get_meta("ue_mesh")).to_lower().find("trim") < 0:
			continue
		_clamp_trim_node_materials(gi)


func _clamp_trim_node_materials(gi: GeometryInstance3D) -> void:
	if gi is MeshInstance3D:
		var mi: MeshInstance3D = gi as MeshInstance3D
		if mi.mesh == null:
			return
		for s: int in range(mi.mesh.get_surface_count()):
			var fixed: StandardMaterial3D = _clamped_trim_material(mi.get_active_material(s))
			if fixed != null:
				mi.set_surface_override_material(s, fixed)
	elif gi is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = gi as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			return
		var src_mesh: Mesh = mmi.multimesh.mesh
		var need_dup: bool = false
		for s: int in range(src_mesh.get_surface_count()):
			if _trim_material_needs_clamp(src_mesh.surface_get_material(s)):
				need_dup = true
				break
		if not need_dup:
			return
		# The MultiMesh itself is per-node, but its mesh is a shared loader
		# cache entry: duplicate the (tiny) trim mesh so the clamp cannot
		# leak into other batches or maps.
		var dup_mesh: Mesh = src_mesh.duplicate() as Mesh
		for s: int in range(dup_mesh.get_surface_count()):
			var fixed: StandardMaterial3D = _clamped_trim_material(dup_mesh.surface_get_material(s))
			if fixed != null:
				dup_mesh.surface_set_material(s, fixed)
		mmi.multimesh.mesh = dup_mesh


static func _trim_material_needs_clamp(m: Material) -> bool:
	if not (m is StandardMaterial3D):
		return false
	var sm: StandardMaterial3D = m as StandardMaterial3D
	return sm.metallic_specular > 0.35 or sm.roughness < 0.45


static func _clamped_trim_material(m: Material) -> StandardMaterial3D:
	if not _trim_material_needs_clamp(m):
		return null
	var dup: StandardMaterial3D = (m as StandardMaterial3D).duplicate() as StandardMaterial3D
	dup.metallic_specular = minf(dup.metallic_specular, STARTSCREEN_TRIM_SPECULAR_MAX)
	dup.roughness = maxf(dup.roughness, STARTSCREEN_TRIM_ROUGHNESS_MIN)
	return dup


## Spawns the extracted Startscreen idle Constable guard (SkeletalMeshActor_16 from
## BeautifulCorner_Startscreen_P.json) with authored PBR slots and neutral idle clip.
func _spawn_startscreen_guard(scene_root: Node3D, loader: Node) -> void:
	if not ResourceLoader.exists(STARTSCREEN_GUARD_GLB):
		return
	var guard_res: Resource = ResourceLoader.load(STARTSCREEN_GUARD_GLB) as Resource
	if not (guard_res is PackedScene):
		return
	var guard_node: Node = (guard_res as PackedScene).instantiate()
	if not (guard_node is Node3D):
		guard_node.queue_free()
		return
	var g3: Node3D = guard_node as Node3D
	g3.name = "StartscreenIdleConstable"
	g3.position = Vector3(-4.2615, -0.0148, 2.5352)
	g3.rotation_degrees = Vector3(0.0, -18.0, 0.0)
	g3.scale = Vector3(1.1, 1.1, 1.1)
	scene_root.add_child(g3)

	var db_v: Variant = loader.get("_mesh_mats_db")
	var slots_v: Variant = (db_v as Dictionary).get(STARTSCREEN_GUARD_UE_MESH, null) if db_v is Dictionary else null
	if not (slots_v is Array):
		var db_low_v: Variant = loader.get("_mesh_mats_db_lower")
		slots_v = (db_low_v as Dictionary).get(STARTSCREEN_GUARD_UE_MESH.to_lower(), null) if db_low_v is Dictionary else null
	if slots_v is Array:
		var slots: Array = slots_v as Array
		var meshes: Array[Node] = g3.find_children("*", "MeshInstance3D", true, false)
		for m_node: Node in meshes:
			var mi: MeshInstance3D = m_node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var count: int = mini(mi.mesh.get_surface_count(), slots.size())
			for s: int in range(count):
				var mat_path: String = str(slots[s])
				if mat_path == "":
					continue
				var mat: Material = loader.call("get_material_for_ue", mat_path) as Material
				if mat != null:
					mi.set_surface_override_material(s, mat)

	var skels: Array[Node] = g3.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var skel: Skeleton3D = skels[0] as Skeleton3D
		if skel != null and skel.get_parent() != null:
			var alib: GuardAnimationLibrary = GuardAnimLibScript.new()
			if alib.setup("club", skel):
				var anim: Animation = alib._retarget_general("AN_GuardEnforcer_NeutralFresh_Idle", false, true, false)
				if anim != null:
					var ap := AnimationPlayer.new()
					ap.name = "StartscreenGuardAnim"
					g3.add_child(ap)
					ap.root_node = ap.get_path_to(skel.get_parent())
					var lib := AnimationLibrary.new()
					lib.add_animation("neutral_idle", anim)
					ap.add_animation_library("", lib)
					ap.play("neutral_idle")


func _process(delta: float) -> void:
	_sway_t += delta
	if _menu_cam != null:
		var sway_eye: Vector3 = STARTSCREEN_CAM_EYE + Vector3(sin(_sway_t * 0.35) * 0.08, cos(_sway_t * 0.25) * 0.04, 0.0)
		_menu_cam.position = sway_eye
		_menu_cam.look_at(STARTSCREEN_CAM_EYE + STARTSCREEN_CAM_FWD * STARTSCREEN_CAM_FOCUS_M, Vector3.UP)
	if _shop_glow != null:
		_shop_glow.light_energy = 1.55 + sin(_sway_t * 7.5) * 0.10 + cos(_sway_t * 17.0) * 0.05


func _make_menu_btn(text: String, font: Font) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.78, 0.38))
	if font != null:
		b.add_theme_font_override("font", font)
	return b


func _build_ui() -> void:
	var sans := ResourceLoader.load("res://assets/ue/fonts/Raleway-Regular.ttf") as Font
	var serif := ResourceLoader.load("res://assets/ue/fonts/SourceSerifPro-Bold.ttf") as Font

	# Right-aligned title & clean vertical menu matching shipped startscreen
	var right_anchor := Control.new()
	right_anchor.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_anchor.offset_left = -460
	right_anchor.offset_right = -64
	right_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right_anchor)

	var menu_v := VBoxContainer.new()
	menu_v.anchor_left = 0.0
	menu_v.anchor_right = 1.0
	menu_v.anchor_top = 0.28
	menu_v.anchor_bottom = 0.90
	menu_v.add_theme_constant_override("separation", 10)
	right_anchor.add_child(menu_v)

	var logo_tex := ResourceLoader.load("res://assets/ue/Raw/Art/UI/Branding/T_TaT_Logo_Primary_White.png") as Texture2D
	if logo_tex != null:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.custom_minimum_size = Vector2(360, 170)
		logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		menu_v.add_child(logo)
	else:
		var title := Label.new()
		title.text = "THICK AS THIEVES"
		title.add_theme_font_size_override("font_size", 44)
		if serif != null:
			title.add_theme_font_override("font", serif)
		menu_v.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	menu_v.add_child(spacer)

	var play_btn := _make_menu_btn("PLAY", sans)
	play_btn.pressed.connect(func():
		selected_order = 1
		if AudioManager != null and AudioManager.has_method("play_ui"):
			AudioManager.play_ui("click")
		_launch()
	)
	menu_v.add_child(play_btn)

	var settings_btn := _make_menu_btn("SETTINGS", sans)
	settings_btn.pressed.connect(_on_settings_pressed)
	menu_v.add_child(settings_btn)

	var credits_btn := _make_menu_btn("CREDITS", sans)
	credits_btn.pressed.connect(_on_credits_pressed)
	menu_v.add_child(credits_btn)

	var quit_btn := _make_menu_btn("QUIT", sans)
	quit_btn.pressed.connect(func(): get_tree().quit())
	menu_v.add_child(quit_btn)

	# Contract Journal drawer (hidden until "CONTRACTS & CO-OP" is clicked)
	journal_panel = PanelContainer.new()
	journal_panel.visible = false
	journal_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	journal_panel.offset_left = 48
	journal_panel.offset_top = 48
	journal_panel.offset_right = -48
	journal_panel.offset_bottom = -48
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.035, 0.06, 0.94)
	style.border_color = Color(0.55, 0.45, 0.25, 0.8)
	style.set_border_width_all(2)
	style.set_content_margin_all(24)
	journal_panel.add_theme_stylebox_override("panel", style)
	add_child(journal_panel)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 14)
	journal_panel.add_child(root_v)

	var hdr := HBoxContainer.new()
	root_v.add_child(hdr)
	var jtitle := Label.new()
	jtitle.text = "KILCAIRN CONTRACT JOURNAL"
	jtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jtitle.add_theme_font_size_override("font_size", 28)
	jtitle.add_theme_color_override("font_color", Color(0.95, 0.82, 0.48))
	if serif != null:
		jtitle.add_theme_font_override("font", serif)
	hdr.add_child(jtitle)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(func(): journal_panel.visible = false)
	hdr.add_child(close_btn)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	root_v.add_child(top_bar)

	thief_opt = OptionButton.new()
	thief_opt.add_item("The Spider (Grapple Wire)")
	thief_opt.add_item("The Chameleon (Disguise)")
	thief_opt.add_item("The Moth [TAT-2] (Astral Scout)")
	thief_opt.item_selected.connect(_on_thief_selected)
	top_bar.add_child(thief_opt)

	diff_opt = OptionButton.new()
	diff_opt.add_item("Novice")
	diff_opt.add_item("Thief")
	diff_opt.add_item("Master Thief")
	top_bar.add_child(diff_opt)

	var host_btn := Button.new()
	host_btn.text = "Host Co-op (7742)"
	host_btn.pressed.connect(func():
		var err := NetManager.host()
		net_status.text = "Hosting on :7742" if err == OK else "Host failed: %d" % err
	)
	top_bar.add_child(host_btn)

	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(130, 0)
	top_bar.add_child(ip_edit)

	var join_btn := Button.new()
	join_btn.text = "Join Co-op"
	join_btn.pressed.connect(func():
		var err := NetManager.join(ip_edit.text)
		net_status.text = "Connecting..." if err == OK else "Join failed: %d" % err
	)
	top_bar.add_child(join_btn)

	net_status = Label.new()
	net_status.text = "Solo Mode"
	top_bar.add_child(net_status)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 20)
	root_v.add_child(split)

	contract_list = ItemList.new()
	contract_list.custom_minimum_size = Vector2(420, 0)
	contract_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for c in GameData.contracts:
		var order := int(c["order"])
		var disp := GameData.get_contract_display(order)
		var tag: String = "[EXPANSION]" if order >= 17 else str(c["map_id"]).to_upper()
		contract_list.add_item("#%02d  %s  (%s)" % [order, disp.get("title", c["id"]), tag])
	contract_list.item_selected.connect(_on_contract_selected)
	split.add_child(contract_list)

	var right_v := VBoxContainer.new()
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.add_theme_constant_override("separation", 12)
	split.add_child(right_v)

	portrait_rect = TextureRect.new()
	portrait_rect.custom_minimum_size = Vector2(160, 160)
	portrait_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right_v.add_child(portrait_rect)
	_on_thief_selected(0)

	detail_lbl = Label.new()
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_lbl.add_theme_font_size_override("font_size", 18)
	if sans != null:
		detail_lbl.add_theme_font_override("font", sans)
	right_v.add_child(detail_lbl)

	var launch_btn := Button.new()
	launch_btn.text = "LAUNCH CONTRACT"
	launch_btn.custom_minimum_size = Vector2(0, 48)
	launch_btn.pressed.connect(_launch)
	right_v.add_child(launch_btn)

	if contract_list.item_count > 1:
		contract_list.select(1)
		_on_contract_selected(1)


func _on_settings_pressed() -> void:
	var ui := SettingsUIScript.new()
	add_child(ui)
	ui.open_settings()


func _on_thief_selected(idx: int) -> void:
	if portrait_rect == null:
		return
	var tex_path := "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_spider.png"
	portrait_rect.modulate = Color.WHITE
	if idx == 1:
		tex_path = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_chameleon.png"
	elif idx == 2:
		tex_path = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_chameleon.png"
		portrait_rect.modulate = Color(0.75, 0.65, 1.0)
	var tex := ResourceLoader.load(tex_path) as Texture2D
	if tex != null:
		portrait_rect.texture = tex


func _on_contract_selected(idx: int) -> void:
	if idx < 0 or idx >= GameData.contracts.size():
		return
	selected_order = int(GameData.contracts[idx]["order"])
	var d := GameData.get_contract_display(selected_order)
	var clues: Array = d.get("clue_facts", [])
	var clue_txt := "\n".join(clues.map(func(x): return "• " + str(x))) if not clues.is_empty() else "• Reconnoiter the landmark for clues."
	detail_lbl.text = "%s\nTarget: %s\nLocation: %s\n\n%s\n\nIntel:\n%s" % [
		d.get("title", ""), d.get("quest_item", ""), d.get("location", ""), d.get("description", ""), clue_txt
	]


func _launch() -> void:
	GameState.thief_id = ["spider", "chameleon", "moth"][thief_opt.selected]
	GameState.difficulty = diff_opt.selected + 1
	GameState.active_contract_order = selected_order
	# Resolve the map here so the mission's weather preset comes from the
	# selected contract, not the GameState default ("old_manor").
	var info: Dictionary = GameData.get_contract_display(selected_order)
	GameState.active_map_id = str(info.get("map_id", "old_manor"))
	get_tree().change_scene_to_file("res://scenes/mission.tscn")


func _on_credits_pressed() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var modal: Dictionary = ArtNouveauTheme.make_modal(layer, Vector2(640, 480), "CREDITS", "Thick As Thieves — OtherSide Entertainment / Megabit")
	var vb: VBoxContainer = modal["vbox"] as VBoxContainer
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	var list_vb: VBoxContainer = VBoxContainer.new()
	list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vb.add_theme_constant_override("separation", 6)
	scroll.add_child(list_vb)
	var entries: Array[String] = []
	if FileAccess.file_exists("res://data/generated/tables/UI/Credits/DT_Credits.json"):
		var f: FileAccess = FileAccess.open("res://data/generated/tables/UI/Credits/DT_Credits.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				var rows: Variant = (parsed as Dictionary).get("rows", {})
				if rows is Dictionary:
					for k: Variant in (rows as Dictionary).keys():
						var r: Variant = (rows as Dictionary)[k]
						if r is Dictionary:
							var rd: Dictionary = r as Dictionary
							var n_dict: Variant = rd.get("Name", {})
							var r_dict: Variant = rd.get("Role", {})
							var nm: String = str((n_dict as Dictionary).get("SourceString", "")) if n_dict is Dictionary else ""
							var rl: String = str((r_dict as Dictionary).get("SourceString", "")) if r_dict is Dictionary else ""
							if nm != "" and nm != "None":
								entries.append("%s  —  %s" % [nm, rl] if rl != "" and rl != "None" else nm)
							if entries.size() >= 80:
								break
	if entries.is_empty():
		entries = ["OtherSide Entertainment", "Warren Spector — Studio Director", "Paul Neurath — Executive Producer", "Godot 4.7 Port — TAT-2"]
	for line: String in entries:
		var lbl: Label = Label.new()
		lbl.text = line
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.86, 0.90, 0.92))
		list_vb.add_child(lbl)
	var close_btn: Button = Button.new()
	close_btn.text = "CLOSE"
	ArtNouveauTheme.style_button(close_btn, true)
	close_btn.pressed.connect(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
	)
	vb.add_child(close_btn)
