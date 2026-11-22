extends Control
## Main Menu: 3D BeautifulCorner Startscreen backdrop (MacNeish Jeweller) + Title overlay.
## Contract selection lives in the Den map table; there is no journal drawer here.

const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const SettingsUIScript := preload("res://src/ui/settings_ui.gd")
const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")
const GuardAnimLibScript: GDScript = preload("res://src/core/animation_library.gd")
const WeatherProfile := preload("res://src/core/weather_profile.gd")
const WeatherVisuals := preload("res://src/core/weather_visuals.gd")

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

var _menu_cam: Camera3D
var _menu_pp_settings: Dictionary
var _menu_fog_vol: Dictionary
var _menu_preset: Dictionary
var _menu_moon: DirectionalLight3D
var _shop_glow: OmniLight3D
var _sway_t: float = 0.0
var selected_order: int = 1


func _ready() -> void:
	# Sentinel: menu chrome routes through res://src/ui/art_nouveau_theme.gd —
	# log it, refuse silent drift. (T9: journal drawer deleted; contract
	# selection lives in the Den map table only — no second deploy path here.)
	print("TAT-2 UI main-menu: theme=res://src/ui/art_nouveau_theme.gd; journal drawer removed (T9)")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_3d_backdrop()
	_build_ui()
	_maybe_autostart_contract()


## QA hook: `tat2/debug_autostart_contract` is 0 in shipped builds. The mobile
## packaging tool can set it to a contract order to boot straight into a mission;
## `--qa-contract=N` overrides it for export-binary perf and capture runs.
func _maybe_autostart_contract() -> void:
	var order: int = int(ProjectSettings.get_setting("tat2/debug_autostart_contract", 0))
	for args: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for arg: String in args:
			if arg.begins_with("--qa-contract="):
				order = int(arg.substr(14))
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

	var fog_vol_v: Variant = load_res.get("fog_volume", {})
	_menu_fog_vol = fog_vol_v as Dictionary if fog_vol_v is Dictionary else {}
	var pp_v: Variant = load_res.get("post_process", {})
	var pp_doc: Dictionary = pp_v as Dictionary if pp_v is Dictionary else {}
	var pp_set_v: Variant = pp_doc.get("settings", {})
	_menu_pp_settings = pp_set_v as Dictionary if pp_set_v is Dictionary else {}
	_menu_preset = WeatherProfile.preset_for_map("main_menu")

	_menu_moon = DirectionalLight3D.new()
	_menu_moon.rotation_degrees = Vector3(-13.0, -3.0, 0.0)
	_menu_moon.light_color = Color(0.6039, 0.702, 1.0)
	_menu_moon.light_energy = 0.18
	_menu_moon.shadow_enabled = true
	scene_root.add_child(_menu_moon)
	# WeatherVisuals places the authored moon disc along the light's +Z axis.
	# The authored lobby rotation points +Z behind the camera, so the disc
	# never entered KF01's frame. Aim +Z toward the upper-right sky (the
	# authored light still shines from that direction); the disc, stars and
	# purple haze then share the reference's top-right composition.
	var moon_dir := Vector3(0.82, 0.30, -0.29).normalized()
	_menu_moon.look_at(_menu_moon.global_position - moon_dir, Vector3.UP)

	_menu_cam = Camera3D.new()
	_menu_cam.name = "StartscreenCineCamera"
	_menu_cam.fov = STARTSCREEN_CAM_VFOV
	_menu_cam.position = STARTSCREEN_CAM_EYE
	_menu_cam.current = true
	scene_root.add_child(_menu_cam)
	# Godot 4.7: an Environment assigned to a Camera3D before the camera enters
	# the tree is silently ignored, and a WorldEnvironment inside a SubViewport
	# with own_world_3d registers on the parent world (Viewport.find_world_3d
	# does not see the SubViewport's own world). Assign after add_child so the
	# authored sky/fog/exposure/ambient actually render.
	_menu_cam.look_at(STARTSCREEN_CAM_EYE + STARTSCREEN_CAM_FWD * STARTSCREEN_CAM_FOCUS_M, Vector3.UP)

	# Tune extracted car headlights (#8/#9, BP_CarBC Temperature 3500K) for warm volumetric mist.
	for child: Node in scene_root.get_children():
		if child is SpotLight3D:
			var sl: SpotLight3D = child as SpotLight3D
			if sl.position.distance_to(Vector3(7.7192, 11.7935, 4.8289)) < 1.0:
				sl.light_color = Color(1.0, 0.82, 0.60)
				sl.light_energy = 8.0
				sl.spot_range = 22.0
				sl.light_volumetric_fog_energy = 2.4
				sl.shadow_enabled = true
			elif sl.light_energy >= 3.9 and sl.position.x < -10.0:
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
	bulb_mat.emission_energy_multiplier = 9.0
	bulb_mesh.material = bulb_mat
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(7.72, 12.25, 4.83)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene_root.add_child(bulb)

	# The declared _shop_glow was animated but never created, so the warm
	# shopfront pool in KF01 did not exist.
	_shop_glow = OmniLight3D.new()
	_shop_glow.name = "StartscreenShopGlow"
	_shop_glow.position = Vector3(0.2, 3.2, 1.8)
	_shop_glow.light_color = Color(1.0, 0.72, 0.42)
	_shop_glow.omni_range = 9.0
	_shop_glow.light_energy = 1.55
	_shop_glow.light_volumetric_fog_energy = 1.2
	_shop_glow.shadow_enabled = false
	scene_root.add_child(_shop_glow)

	# KF01's storefront is washed magenta by the jeweller neon, not just the
	# warm street lamps. One authored-hue fill (no shadows) puts that colour
	# on the facade while the low ambient keeps the scaffold/street dark.
	var shop_magenta := OmniLight3D.new()
	shop_magenta.name = "StartscreenShopMagenta"
	shop_magenta.position = Vector3(0.5, 4.0, 3.0)
	shop_magenta.light_color = Color(1.0, 0.25, 0.85)
	shop_magenta.light_energy = 3.0
	shop_magenta.omni_range = 12.0
	shop_magenta.omni_attenuation = 1.2
	shop_magenta.shadow_enabled = false
	scene_root.add_child(shop_magenta)

	call_deferred("_bind_menu_env")
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


func _bind_menu_env() -> void:
	# Godot 4.7: an Environment resource created before this own-world
	# SubViewport has rendered is never picked up by the camera, and a
	# WorldEnvironment inside the SubViewport registers on the parent world
	# (Viewport.find_world_3d misses the SubViewport's own world). Build the
	# environment after the first frames and assign it to the camera, which is
	# the only binding that renders here.
	for _i: int in range(12):
		await get_tree().process_frame
	if _menu_cam == null:
		return
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.012, 0.016, 0.036)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.42, 0.72)
	e.ambient_light_energy = 0.38
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.95
	e.glow_enabled = true
	e.glow_intensity = 1.9
	e.glow_bloom = 0.26
	e.glow_hdr_threshold = 1.8
	e.glow_hdr_scale = 3.2
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for gl_i: int in range(5):
		e.set_glow_level(gl_i, true)
	if _menu_moon != null and not _menu_preset.is_empty():
		WeatherVisuals.apply_sky(e, _menu_preset, _menu_moon)
		e.ambient_light_sky_contribution = 0.0
		# TAT's M_Sky multiplies the authored HDR gradient by OverallColor
		# 0.001, which the shader's 25x night lift still leaves near-black.
		# The reference KF01 sky/haze sits around 0.07-0.15, so lift the
		# rendered sky radiance once here (authored colours stay untouched).
		e.background_energy_multiplier = 1.2
		# Authored night fog hue, tinted toward the reference's magenta
		# storefront haze rather than a neutral blue. fog_sky_affect also
		# tints the low sky band; the street remains readable at 0.0015.
		e.fog_enabled = true
		e.fog_light_color = Color(0.25, 0.08, 0.32)
		e.fog_light_energy = 1.0
		e.fog_density = 0.0015
		e.fog_sky_affect = 0.5
		e.fog_aerial_perspective = 0.4
	_menu_cam.environment = e


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
					# UE's Preview mesh keeps Cornea/Eyes/Overlay unbound; the
					# GLB default for the full-body Overlay slot is an opaque
					# green debug material that hides the real guard. Hide it.
					var hidden := StandardMaterial3D.new()
					hidden.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					hidden.albedo_color = Color(0, 0, 0, 0)
					hidden.cull_mode = BaseMaterial3D.CULL_DISABLED
					mi.set_surface_override_material(s, hidden)
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
				var anim: Animation = alib._retarget_general("AN_GuardEnforcer_NeutralFresh_Idle", false, true, true)
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
	# P1 chrome route (audit-ui P1-4): flat left-aligned KF01 menu text keeps its
	# look but reads tokens — IVORY idle / GOLD hover / GOLD_DIM pressed — from
	# res://src/ui/art_nouveau_theme.gd. No inline hex at call sites.
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", ArtNouveauTheme.IVORY)
	b.add_theme_color_override("font_hover_color", ArtNouveauTheme.GOLD)
	b.add_theme_color_override("font_pressed_color", ArtNouveauTheme.GOLD_DIM)
	b.add_theme_color_override("font_focus_color", ArtNouveauTheme.GOLD)
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

	# T9: no journal drawer. Contract selection, difficulty, and co-op deploy live
	# only in the Den map table (contract_table_ui -> mission_prep_ui -> the T7
	# deploy closure); a menu drawer would be a second deploy path around it.


func _on_settings_pressed() -> void:
	var ui := SettingsUIScript.new()
	add_child(ui)
	ui.open_settings()


## T9: PLAY is a quick boot into the default contract. Full contract selection,
## difficulty, thief, and co-op deploy live only in the Den map table, which
## threads active_mission_id + active_mission_mode across reset_run (T7).
func _launch() -> void:
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
		# P1 chrome route: credits body reads TEAL_TEXT (was inline 0.86/0.90/0.92).
		lbl.add_theme_color_override("font_color", ArtNouveauTheme.TEAL_TEXT)
		list_vb.add_child(lbl)
	var close_btn: Button = Button.new()
	close_btn.text = "CLOSE"
	ArtNouveauTheme.style_button(close_btn, true)
	close_btn.pressed.connect(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
	)
	vb.add_child(close_btn)
