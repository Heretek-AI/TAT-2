extends SceneTree
## Live Vulkan Forward+ visual & HUD parity capture suite (Shots S01-S16, 21 PNGs).
## Grounded in TEST_INFRA.md and teamwork_spec_miner_e2e_r1_2/handoff.md.
## Rules:
## - Zero top-level preload() on autoload-referencing scripts; runtime load() only.
## - Godot 4.7 Variant typing hygiene (explicit types, no := on Variant/Dict).
## - Bounded waits (<= 600 frames) and quit(0)/quit(1) on all paths.

const TARGET_SIZE: Vector2i = Vector2i(1280, 720)
const MIN_LUMA_MEAN: float = 0.010
const MIN_LUMA_STDDEV: float = 0.020
const MAX_WAIT_FRAMES: int = 600

var _out_dir: String = ""
var _shots_saved: int = 0
var _image_failures: int = 0
var _parity_passes: int = 0
var _parity_fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _wait_frames(n: int) -> void:
	var count: int = clampi(n, 1, MAX_WAIT_FRAMES)
	for _i: int in range(count):
		await process_frame


func _press_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action_name
	ev.pressed = true
	Input.parse_input_event(ev)


func _release_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action_name
	ev.pressed = false
	Input.parse_input_event(ev)


func _tap_action(action_name: String) -> void:
	_press_action(action_name)
	await _wait_frames(2)
	_release_action(action_name)


func _tap_key(keycode: Key) -> void:
	var ev_down: InputEventKey = InputEventKey.new()
	ev_down.keycode = keycode
	ev_down.physical_keycode = keycode
	ev_down.pressed = true
	Input.parse_input_event(ev_down)
	await _wait_frames(2)
	var ev_up: InputEventKey = InputEventKey.new()
	ev_up.keycode = keycode
	ev_up.physical_keycode = keycode
	ev_up.pressed = false
	Input.parse_input_event(ev_up)


func _press_mouse_button(btn: MouseButton, pressed: bool) -> void:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	ev.position = Vector2(640.0, 360.0)
	Input.parse_input_event(ev)


func _compute_image_stats(img: Image) -> Dictionary:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var stride: int = 4
	var sum_l: float = 0.0
	var sum_l2: float = 0.0
	var min_l: float = 1.0
	var max_l: float = 0.0
	var n: int = 0
	var y: int = 0
	while y < h:
		var x: int = 0
		while x < w:
			var c: Color = img.get_pixel(x, y)
			var luma: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum_l += luma
			sum_l2 += luma * luma
			if luma < min_l:
				min_l = luma
			if luma > max_l:
				max_l = luma
			n += 1
			x += stride
		y += stride
	var mean_l: float = sum_l / float(maxi(n, 1))
	var variance: float = maxf(0.0, (sum_l2 / float(maxi(n, 1))) - mean_l * mean_l)
	var stddev_l: float = sqrt(variance)
	return {
		"mean": mean_l,
		"stddev": stddev_l,
		"min": min_l,
		"max": max_l,
		"samples": n,
	}


func _capture_shot(shot_id: String, fname: String, missing_reasons: Array[String], detail: String = "") -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		printerr("PARITY_IMAGE_FAIL: [", shot_id, "] ", fname, " empty/null image")
		_image_failures += 1
		return
	var sz: Vector2i = img.get_size()
	var stats: Dictionary = _compute_image_stats(img)
	var l_mean: float = float(stats.get("mean", 0.0))
	var l_std: float = float(stats.get("stddev", 0.0))
	var l_max: float = float(stats.get("max", 0.0))
	var out_path: String = _out_dir + "/" + fname
	var save_err: int = img.save_png(out_path)
	if save_err != OK:
		printerr("PARITY_IMAGE_FAIL: [", shot_id, "] ", fname, " save_png err=", save_err)
		_image_failures += 1
	elif sz != TARGET_SIZE:
		printerr("PARITY_IMAGE_FAIL: [", shot_id, "] ", fname, " bad size=", sz)
		_image_failures += 1
	elif l_mean < MIN_LUMA_MEAN or l_std < MIN_LUMA_STDDEV:
		printerr("PARITY_IMAGE_FAIL: [", shot_id, "] ", fname, " black/uniform L_mean=", snappedf(l_mean, 0.0001), " stddev=", snappedf(l_std, 0.0001))
		_image_failures += 1
	else:
		_shots_saved += 1
	print("PARITY_CAPTURE: [", shot_id, "] ", fname, " size=", sz.x, "x", sz.y, " L_mean=", snappedf(l_mean, 0.0001), " stddev=", snappedf(l_std, 0.0001), " L_max=", snappedf(l_max, 0.0001), " err=", save_err)

	if missing_reasons.is_empty():
		_parity_passes += 1
		print("PARITY_CHECK: [", shot_id, "] PASS ", detail)
	else:
		_parity_fails += 1
		print("PARITY_CHECK: [", shot_id, "] FAIL missing=[", ", ".join(missing_reasons), "] ", detail)


func _free_node_clean(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()
	await _wait_frames(5)


func _find_first_world_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for c: Node in node.get_children():
		var found: WorldEnvironment = _find_first_world_env(c)
		if found != null:
			return found
	return null


func _find_descendants_by_class(node: Node, cls_name: String, out: Array[Node]) -> void:
	if node.is_class(cls_name):
		out.append(node)
	for c: Node in node.get_children():
		_find_descendants_by_class(c, cls_name, out)


func _find_named_node(node: Node, target_substr: String) -> Node:
	if str(node.name).findn(target_substr) >= 0:
		return node
	for c: Node in node.get_children():
		var found: Node = _find_named_node(c, target_substr)
		if found != null:
			return found
	return null


func _has_clipped_ancestor(ctrl: Control) -> bool:
	var p: Node = ctrl.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _controls_inside_viewport(node: Node, out_clipped: Array[String]) -> void:
	if node is Control:
		var ctrl: Control = node as Control
		if ctrl.visible and ctrl.is_visible_in_tree() and not _has_clipped_ancestor(ctrl):
			var r: Rect2 = ctrl.get_global_rect()
			if r.size.x > 0.5 and r.size.y > 0.5:
				if r.position.x < -4.0 or r.position.y < -4.0 or r.end.x > 1284.0 or r.end.y > 724.0:
					if ctrl is Button or ctrl is PanelContainer:
						out_clipped.append(str(ctrl.name) + "@" + str(r))
	for c: Node in node.get_children():
		_controls_inside_viewport(c, out_clipped)


func _wait_for_mission_ready(mission: Node) -> bool:
	var waited: int = 0
	while waited < MAX_WAIT_FRAMES:
		var p_var: Variant = mission.get("player")
		var doors: Array[Node] = get_nodes_in_group("swinging_doors")
		if p_var != null and not doors.is_empty():
			return true
		await process_frame
		waited += 1
	return mission.get("player") != null


func _snap_pos_to_floor(mission: Node3D, xz_pos: Vector3) -> Vector3:
	var w3d: World3D = mission.get_world_3d()
	if w3d == null:
		return xz_pos
	var phys: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(xz_pos + Vector3(0.0, 4.0, 0.0), xz_pos + Vector3(0.0, -16.0, 0.0), 1)
	var hit: Dictionary = phys.intersect_ray(q)
	if not hit.is_empty():
		var hp_var: Variant = hit.get("position", null)
		if hp_var is Vector3:
			return (hp_var as Vector3) + Vector3(0.0, 0.12, 0.0)
	return xz_pos


func _aim_player_at(player: CharacterBody3D, target: Vector3) -> void:
	var eye: Vector3 = player.global_position + Vector3(0.0, 1.67, 0.0)
	var diff: Vector3 = target - eye
	var flat_len: float = Vector2(diff.x, diff.z).length()
	if flat_len > 0.001:
		player.rotation = Vector3(0.0, atan2(-diff.x, -diff.z), 0.0)
	var head_var: Variant = player.get("head")
	if head_var is Node3D:
		var pitch: float = atan2(diff.y, maxf(flat_len, 0.001))
		(head_var as Node3D).rotation.x = clampf(pitch, deg_to_rad(-78.0), deg_to_rad(78.0))


func _shader_has_token(shader: Shader, token: String) -> bool:
	if shader == null:
		return false
	return shader.code.findn(token) >= 0


func _check_panel_has_teal_border(root_node: Node) -> bool:
	var panels: Array[Node] = []
	_find_descendants_by_class(root_node, "PanelContainer", panels)
	for p_node: Node in panels:
		var pc: PanelContainer = p_node as PanelContainer
		if not pc.visible or not pc.is_visible_in_tree():
			continue
		var sb: StyleBox = pc.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			var flat: StyleBoxFlat = sb as StyleBoxFlat
			if flat.border_color.b > flat.border_color.r + 0.05 and flat.border_color.g > flat.border_color.r + 0.05:
				return true
	return false


func _run() -> void:
	root.size = TARGET_SIZE
	_out_dir = ProjectSettings.globalize_path("res://../build/qa/e2e_parity").simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	await _wait_frames(3)

	var gs: Node = root.get_node_or_null("/root/GameState")
	var noise_bus: Node = root.get_node_or_null("/root/NoiseBus")

	# =========================================================================
	# S01: Startscreen (main_menu.gd)
	# =========================================================================
	var mm_script: GDScript = load("res://src/ui/main_menu.gd") as GDScript
	if mm_script == null:
		printerr("PARITY_FATAL: failed to load res://src/ui/main_menu.gd")
		quit(1)
		return
	var mm: Control = mm_script.new() as Control
	mm.size = Vector2(TARGET_SIZE)
	root.add_child(mm)
	await _wait_frames(20)
	var s01_missing: Array[String] = []
	var mm_env: WorldEnvironment = _find_first_world_env(mm)
	if mm_env == null or mm_env.environment == null:
		s01_missing.append("startscreen_world_env")
	else:
		var e01: Environment = mm_env.environment
		if not e01.glow_enabled:
			s01_missing.append("glow_enabled")
		if e01.tonemap_mode != Environment.TONE_MAPPER_ACES:
			s01_missing.append("aces_tonemap")
		if not e01.volumetric_fog_enabled and _find_named_node(mm, "Mist") == null and _find_named_node(mm, "Headlight") == null:
			s01_missing.append("headlight_mist")
		if not e01.ssr_enabled:
			s01_missing.append("desktop_ssr")
	var s01_clipped: Array[String] = []
	_controls_inside_viewport(mm, s01_clipped)
	if not s01_clipped.is_empty():
		s01_missing.append("clipped_controls:" + str(s01_clipped.size()))
	await _capture_shot("S01", "parity_startscreen.png", s01_missing, "Startscreen 3D backdrop + menu")
	await _free_node_clean(mm)

	# =========================================================================
	# S02, S03, S04, S05a, S05b: Thieves' Den Hub + Wardrobe + Ledger
	# =========================================================================
	if gs != null:
		gs.set("active_contract_order", 1)
		gs.set("active_map_id", "thieves_den")
	var mission_scene: PackedScene = load("res://scenes/mission.tscn") as PackedScene
	if mission_scene == null:
		printerr("PARITY_FATAL: failed to load res://scenes/mission.tscn")
		quit(1)
		return
	var den: Node3D = mission_scene.instantiate() as Node3D
	root.add_child(den)
	if not await _wait_for_mission_ready(den):
		printerr("PARITY_FATAL: Thieves' Den timed out waiting for player/doors")
		quit(1)
		return
	await _wait_frames(20)

	# S02: Thieves' Den Wide
	var den_cam: Camera3D = Camera3D.new()
	den_cam.fov = 68.0
	den_cam.position = Vector3(4.2, 41.9, 271.2)
	den.add_child(den_cam)
	den_cam.current = true
	den_cam.look_at(Vector3(-4.5, 41.5, 271.5), Vector3.UP)
	await _wait_frames(8)

	var s02_missing: Array[String] = []
	var den_labels: Array[Node] = []
	_find_descendants_by_class(den, "Label3D", den_labels)
	if den_labels.size() > 0:
		s02_missing.append("giant_label3d_billboards=" + str(den_labels.size()))
	var candle_node: Node = _find_named_node(den, "CandleFlame")
	if candle_node == null:
		s02_missing.append("candle_flame_node")
	else:
		var fp: Node = candle_node.get_node_or_null("FlameParticles")
		if fp is CPUParticles3D and (fp as CPUParticles3D).mesh is SphereMesh:
			s02_missing.append("candle_flame_still_sphere_blob")
	var den_env: WorldEnvironment = _find_first_world_env(den)
	if den_env == null or den_env.environment == null or (not den_env.environment.ssil_enabled and den_env.environment.ambient_light_energy < 0.2):
		s02_missing.append("den_ssil_or_gi_lift")
	await _capture_shot("S02", "parity_thieves_den_wide.png", s02_missing, "labels=" + str(den_labels.size()))
	den_cam.queue_free()
	await _wait_frames(3)

	# S03: Thieves' Den Map Table
	var den_player: CharacterBody3D = den.get("player") as CharacterBody3D
	var map_table_pos: Vector3 = Vector3(2.769, 41.1137, 268.0207)
	if den_player != null:
		den_player.global_position = Vector3(2.75, 40.35, 269.45)
		_aim_player_at(den_player, map_table_pos)
	var map_cam: Camera3D = Camera3D.new()
	map_cam.fov = 58.0
	map_cam.position = Vector3(2.75, 42.18, 269.45)
	den.add_child(map_cam)
	map_cam.current = true
	map_cam.look_at(map_table_pos + Vector3(0.0, 0.0, -0.15), Vector3.UP)
	await _wait_frames(8)

	var s03_missing: Array[String] = []
	var tokens: Array[Node] = get_nodes_in_group("map_table_tokens")
	if tokens.size() < 2:
		s03_missing.append("map_table_tokens<2")
	var den_hud: Node = den.get("hud") as Node
	if den_hud == null or not den_hud.has_method("set_map_table_card"):
		if _find_named_node(den, "MapTableCard") == null:
			s03_missing.append("map_table_look_at_card")
	if _find_named_node(den, "Ponder") == null and get_nodes_in_group("telescope").is_empty():
		# Check if any interactable prompt returns PONDER
		var has_ponder: bool = false
		for inode: Node in get_nodes_in_group("interactables"):
			if inode.has_method("get_interact_prompt") and str(inode.call("get_interact_prompt")).findn("PONDER") >= 0:
				has_ponder = true
				break
		if not has_ponder:
			s03_missing.append("ponder_telescope_interactable")
	await _capture_shot("S03", "parity_thieves_den_map_table.png", s03_missing, "tokens=" + str(tokens.size()))
	map_cam.queue_free()
	await _wait_frames(3)

	# S04: Wardrobe UI
	var ward_script: GDScript = load("res://src/ui/wardrobe_ui.gd") as GDScript
	var ward: CanvasLayer = ward_script.new() as CanvasLayer
	root.add_child(ward)
	await _wait_frames(4)
	if ward.has_method("open_customizer"):
		ward.call("open_customizer")
	await _wait_frames(12)
	var s04_missing: Array[String] = []
	if not _check_panel_has_teal_border(ward):
		s04_missing.append("teal_art_nouveau_style")
	var tt: Variant = ward.get("_turntable")
	if tt == null or not (tt is Node3D):
		s04_missing.append("wardrobe_3d_turntable")
	var ward_clipped: Array[String] = []
	_controls_inside_viewport(ward, ward_clipped)
	if not ward_clipped.is_empty():
		s04_missing.append("clipped_controls")
	await _capture_shot("S04", "parity_wardrobe.png", s04_missing, "Wardrobe 3D thief + loadout UI")
	await _free_node_clean(ward)

	# S05a & S05b: Ledger Journal & Black Market
	var ledger_layer: CanvasLayer = CanvasLayer.new()
	ledger_layer.layer = 20
	root.add_child(ledger_layer)
	var ledger_script: GDScript = load("res://src/ui/ledger_ui.gd") as GDScript
	var ledger: Control = ledger_script.new() as Control
	ledger.size = Vector2(TARGET_SIZE)
	ledger_layer.add_child(ledger)
	await _wait_frames(8)

	var s05a_missing: Array[String] = []
	if not _check_panel_has_teal_border(ledger):
		s05a_missing.append("teal_art_nouveau_style")
	var l05a_clipped: Array[String] = []
	_controls_inside_viewport(ledger, l05a_clipped)
	if not l05a_clipped.is_empty():
		s05a_missing.append("clipped_controls")
	await _capture_shot("S05a", "parity_ledger_journal.png", s05a_missing, "Ledger Journal tab")

	if ledger.has_method("_show_tab"):
		ledger.call("_show_tab", 1)
	else:
		await _tap_key(KEY_E)
	await _wait_frames(8)
	var s05b_missing: Array[String] = []
	if not _check_panel_has_teal_border(ledger):
		s05b_missing.append("teal_art_nouveau_style")
	await _capture_shot("S05b", "parity_ledger_market.png", s05b_missing, "Ledger Black Market tab")

	await _free_node_clean(ledger_layer)
	await _free_node_clean(den)

	# =========================================================================
	# S06a & S06b: Mission Prep (Elway Manor + Constables' Guildhall)
	# =========================================================================
	var mp_script: GDScript = load("res://src/ui/mission_prep_ui.gd") as GDScript
	var mp: Control = mp_script.new() as Control
	mp.size = Vector2(TARGET_SIZE)
	root.add_child(mp)
	await _wait_frames(4)
	mp.call("open_prep", "old_manor", 1, "Solo", 3)
	await _wait_frames(15)

	var s06_missing: Array[String] = []
	var mp_cams: Array[Node] = []
	_find_descendants_by_class(mp, "Camera3D", mp_cams)
	var has_fov20: bool = false
	for cam_n: Node in mp_cams:
		if absf((cam_n as Camera3D).fov - 20.0) <= 2.5:
			has_fov20 = true
	if not has_fov20:
		s06_missing.append("mission_lobby_fov_20")
	if _find_named_node(mp, "MissionLobby") == null:
		s06_missing.append("real_mission_lobby_stage")
	if not _check_panel_has_teal_border(mp):
		s06_missing.append("teal_art_nouveau_cards")
	await _capture_shot("S06a", "parity_mission_prep_manor.png", s06_missing, "Mission Prep Elway Manor")

	mp.call("open_prep", "guildhall", 1, "Solo", 0)
	await _wait_frames(15)
	var s06b_missing: Array[String] = s06_missing.duplicate()
	var con_body_var: Variant = mp.get("_contract_title_lbl")
	if con_body_var is Label:
		if (con_body_var as Label).text.findn("Contract Inactive") < 0:
			s06b_missing.append("contract_inactive_text")
	await _capture_shot("S06b", "parity_mission_prep_guildhall.png", s06b_missing, "Mission Prep Guildhall (Contract Inactive)")
	await _free_node_clean(mp)

	# =========================================================================
	# S07: Loading Screen
	# =========================================================================
	var ls_script: GDScript = load("res://src/ui/loading_screen.gd") as GDScript
	var ls: CanvasLayer = ls_script.new() as CanvasLayer
	root.add_child(ls)
	await _wait_frames(3)
	if ls.has_method("start_loading"):
		ls.call("start_loading", "In the Eye of the Beholder", "Steal the components of the Staff of Edinburgh.", "guildhall")
	if ls.has_method("set_progress"):
		ls.call("set_progress", 0.5, "Streaming Guildhall...")
	await _wait_frames(8)
	var s07_missing: Array[String] = []
	var splash_var: Variant = ls.get("_splash_rect")
	if splash_var is TextureRect:
		var tr: TextureRect = splash_var as TextureRect
		if not tr.visible or tr.modulate.a < 0.85:
			s07_missing.append("full_bleed_T_loadingScreen_alpha=" + str(tr.modulate.a))
		if tr.texture == null or str(tr.texture.resource_path).findn("T_loadingScreen_1") < 0:
			s07_missing.append("T_loadingScreen_1_artwork")
	else:
		s07_missing.append("splash_rect")
	var bar_var: Variant = ls.get("_bar")
	if bar_var is ProgressBar and (bar_var as ProgressBar).visible:
		s07_missing.append("spinner_instead_of_progressbar")
	await _capture_shot("S07", "parity_loading_screen.png", s07_missing, "Loading Screen full-art")
	await _free_node_clean(ls)

	# =========================================================================
	# S08 - S15d: Guildhall Gameplay, Atmosphere, SSR, 1P Tools & HUD
	# =========================================================================
	if gs != null:
		gs.set("thief_id", "spider")
		gs.set("active_contract_order", 4)
		gs.set("active_map_id", "guildhall")
	var gh: Node3D = mission_scene.instantiate() as Node3D
	root.add_child(gh)
	if not await _wait_for_mission_ready(gh):
		printerr("PARITY_FATAL: Guildhall timed out waiting for player/doors")
		quit(1)
		return
	await _wait_frames(30)

	var gh_player: CharacterBody3D = gh.get("player") as CharacterBody3D
	var gh_hud: Node = gh.get("hud") as Node
	var gh_env: WorldEnvironment = _find_first_world_env(gh)

	# S08: Mission Start Letter (pre-dismiss)
	var s08_missing: Array[String] = []
	var has_letter: bool = false
	if gh_hud != null:
		if _find_named_node(gh_hud, "StartLetter") != null or _find_named_node(gh_hud, "MissionLetter") != null:
			has_letter = true
	if not has_letter:
		s08_missing.append("mission_start_letter_overlay")
	await _capture_shot("S08", "parity_start_letter.png", s08_missing, "Guildhall pre-dismiss start letter")
	if has_letter:
		await _tap_key(KEY_SPACE)
		await _wait_frames(6)

	# S09: Guildhall Spawn + Full HUD + Night Sky / Moon / MACLEOD neon
	# Position on open rooftop/courtyard balcony overlooking Guildhall & sky
	if gh_player != null:
		var balcony_pos: Vector3 = _snap_pos_to_floor(gh, Vector3(55.86, 23.2, 83.46))
		gh_player.global_position = balcony_pos
		_aim_player_at(gh_player, Vector3(60.0, 40.0, 20.0))
	await _wait_frames(12)

	var s09_missing: Array[String] = []
	if gh_env == null or gh_env.environment == null or gh_env.environment.sky == null:
		s09_missing.append("sky_environment")
	else:
		var smat: Material = gh_env.environment.sky.sky_material
		if smat is ShaderMaterial:
			var sh: Shader = (smat as ShaderMaterial).shader
			if not _shader_has_token(sh, "fbm") and not _shader_has_token(sh, "cloud_wisps"):
				s09_missing.append("procedural_cloud_wisps")
			if not _shader_has_token(sh, "halo"):
				s09_missing.append("moon_halo")
		else:
			s09_missing.append("tat_sky_shader_material")
	if gh_hud != null:
		var hp_var: Variant = gh_hud.get("hp_fill")
		if hp_var is Control and (hp_var as Control).global_position.y > 220.0:
			s09_missing.append("health_bar_not_top_left")
		var sg_var: Variant = gh_hud.get("stealth_gem")
		if sg_var is Control:
			var sg_c: Control = sg_var as Control
			var sg_cx: float = sg_c.global_position.x + sg_c.size.x * 0.5
			if absf(sg_cx - 640.0) > 120.0:
				s09_missing.append("stealth_ball_not_centered(x=" + str(int(sg_cx)) + ")")
		else:
			s09_missing.append("stealth_gem")
	if not InputMap.has_action("map_toggle"):
		s09_missing.append("input_action_map_toggle")
	if not InputMap.has_action("ping_menu"):
		s09_missing.append("input_action_ping_menu")
	await _capture_shot("S09", "parity_guildhall_spawn_hud.png", s09_missing, "Guildhall rooftop sky + HUD")

	# S10: MacNeish Jeweller Neon ACES + Wet Cobblestone Puddle SSR + Foliage
	if gh_player != null:
		var street_pos: Vector3 = _snap_pos_to_floor(gh, Vector3(-76.5, 19.2, 24.5))
		gh_player.global_position = street_pos
		_aim_player_at(gh_player, Vector3(-92.0, 22.8, 12.0))
	await _wait_frames(15)

	var s10_missing: Array[String] = []
	if gh_env == null or gh_env.environment == null or not gh_env.environment.ssr_enabled:
		s10_missing.append("env_ssr_enabled")
	var land_shader: Shader = load("res://src/core/tat_landscape.gdshader") as Shader
	if land_shader != null and land_shader.code.find("0.18") >= 0 and land_shader.code.find("0.04") < 0:
		s10_missing.append("tat_landscape_puddle_roughness_0.04")
	var sg10_var: Variant = gh_hud.get("stealth_gem") if gh_hud != null else null
	if sg10_var is Control and absf(((sg10_var as Control).global_position.x + (sg10_var as Control).size.x * 0.5) - 640.0) > 120.0:
		s10_missing.append("stealth_ball_not_centered")
	await _capture_shot("S10", "parity_guildhall_macneish_ssr.png", s10_missing, "MacNeish Jeweller neon + wet cobblestone SSR")

	# S11: 1P Zipwire + Crank + Damaged HealthBar + Bilateral SoundWaves
	if gh_player != null:
		if gh_player.has_method("take_damage"):
			gh_player.call("take_damage", 95.0)
		await _tap_action("tool_1")
		if noise_bus != null and noise_bus.has_method("emit_noise"):
			noise_bus.call("emit_noise", gh_player.global_position, 14.0, gh_player, "sprint")
		if gh_player.has_method("get_equipped_tool"):
			_aim_player_at(gh_player, Vector3(-90.0, 29.0, 12.0))
			await _tap_action("primary_action")
			await _wait_frames(6)
			_press_action("secondary_action")
			await _wait_frames(18)
	await _wait_frames(8)

	var s11_missing: Array[String] = []
	if gh_player == null:
		s11_missing.append("player")
	else:
		if not gh_player.has_method("get_equipped_tool"):
			s11_missing.append("get_equipped_tool")
		elif str(gh_player.call("get_equipped_tool")) != "zipwire":
			s11_missing.append("equipped_tool!=zipwire")
		if not gh_player.has_method("get_tool_slots"):
			s11_missing.append("get_tool_slots")
		if not gh_player.has_method("get_active_reticle_state"):
			s11_missing.append("get_active_reticle_state")
		var tool_root: Variant = gh_player.get("fp_tool_root")
		if tool_root is Node:
			if (tool_root as Node).get_node_or_null("ZipwireBody") != null:
				s11_missing.append("fallback_box_zipwire")
	if gh_hud != null and _find_named_node(gh_hud, "SoundWave") == null:
		s11_missing.append("sound_waves_hud")
	await _capture_shot("S11", "parity_1p_zipwire_crank.png", s11_missing, "1P Zipwire + HP damage + SoundWaves")
	_release_action("secondary_action")
	await _wait_frames(4)

	# S12: 1P Smoke Bomb + Ballistic Trajectory Arc
	if gh_player != null:
		gh_player.set("is_grappling", false)
		gh_player.global_position = _snap_pos_to_floor(gh, Vector3(-76.5, 19.2, 24.5))
		_aim_player_at(gh_player, Vector3(-86.0, 20.5, 14.0))
		await _tap_action("tool_2")
		await _wait_frames(8)
	var s12_missing: Array[String] = []
	if gh_player == null or not gh_player.has_method("get_equipped_tool"):
		s12_missing.append("get_equipped_tool")
	else:
		if str(gh_player.call("get_equipped_tool")) != "smoke_bomb":
			s12_missing.append("equipped_tool!=smoke_bomb")
		var tr12: Variant = gh_player.get("fp_tool_root")
		if tr12 is Node and (tr12 as Node).get_node_or_null("SmokeBomb") != null:
			s12_missing.append("fallback_sphere_smoke_bomb")
	if gh_player != null and _find_named_node(gh_player, "Trajectory") == null and _find_named_node(gh, "Trajectory") == null:
		s12_missing.append("smoke_trajectory_arc")
	await _capture_shot("S12", "parity_1p_smokebomb_arc.png", s12_missing, "1P Smoke Bomb + trajectory arc")

	# S13: 1P Vistara Diamond + Clean Thief Vision (no flat cyan screenwash)
	for gh_child: Node in gh.get_children():
		if str(gh_child.name).begins_with("SmokeCloud"):
			gh_child.queue_free()
	var smokes_arr: Variant = gh.get("smokes")
	if smokes_arr is Array:
		(smokes_arr as Array).clear()
	if gh_player != null:
		await _tap_action("tool_4")
		if gh_player.get("thief_vision") != true:
			await _tap_action("thief_vision")
		await _wait_frames(8)
	var s13_missing: Array[String] = []
	if gh_player == null or not gh_player.has_method("is_thief_vision_active"):
		s13_missing.append("is_thief_vision_active")
	if gh_player != null and gh_player.has_method("get_equipped_tool"):
		if str(gh_player.call("get_equipped_tool")) != "vistara_diamond":
			s13_missing.append("equipped_tool!=vistara_diamond")
	if gh_hud != null:
		var tv_var: Variant = gh_hud.get("thief_vision_overlay")
		if tv_var is ColorRect:
			var tvc: ColorRect = tv_var as ColorRect
			if tvc.visible and tvc.color.a >= 0.05:
				s13_missing.append("flat_cyan_thief_vision_wash(a=" + str(snappedf(tvc.color.a, 0.01)) + ")")
	await _capture_shot("S13", "parity_1p_vistara_diamond.png", s13_missing, "1P Vistara Diamond + clean Thief Vision")
	if gh_player != null and gh_player.get("thief_vision") == true:
		await _tap_action("thief_vision")
		await _wait_frames(4)

	# S14: Guard Lantern + Alert Pips & Offscreen Arc
	var guards: Array[Node] = get_nodes_in_group("guards")
	var front_guard: Node3D = null
	var back_guard: Node3D = null
	if guards.size() >= 1 and guards[0] is Node3D:
		front_guard = guards[0] as Node3D
	if guards.size() >= 2 and guards[1] is Node3D:
		back_guard = guards[1] as Node3D
	if gh_player != null and front_guard != null:
		var gp_front: Vector3 = _snap_pos_to_floor(gh, Vector3(-84.5, 19.2, 18.0))
		front_guard.global_position = gp_front
		front_guard.set("detection", 58.0)
		front_guard.set("state", 1)
		gh_player.global_position = _snap_pos_to_floor(gh, Vector3(-77.0, 19.2, 23.0))
		_aim_player_at(gh_player, gp_front + Vector3(0.0, 1.3, 0.0))
	if gh_player != null and back_guard != null:
		back_guard.global_position = _snap_pos_to_floor(gh, Vector3(-70.0, 19.2, 28.0))
		back_guard.set("detection", 48.0)
		back_guard.set("state", 1)
	await _wait_frames(8)

	var s14_missing: Array[String] = []
	if front_guard == null:
		s14_missing.append("no_guards")
	else:
		if not front_guard.has_method("get_alert_state"):
			s14_missing.append("guard.get_alert_state")
		var has_lantern_light: bool = false
		for g_node: Node in guards:
			var lights_g: Array[Node] = []
			_find_descendants_by_class(g_node, "OmniLight3D", lights_g)
			if not lights_g.is_empty():
				has_lantern_light = true
				break
		if not has_lantern_light:
			s14_missing.append("guard_lantern_omnilight")
	if gh_hud != null and _find_named_node(gh_hud, "GuardPip") == null and _find_named_node(gh_hud, "Offscreen") == null:
		s14_missing.append("guard_pips_and_offscreen_arcs")
	await _capture_shot("S14", "parity_guard_lantern_alert.png", s14_missing, "Guard lantern + alert pips")

	# S15a: 1P Slithersap (slot [3])
	if gh_player != null:
		await _tap_action("tool_3")
		await _wait_frames(6)
	var s15a_missing: Array[String] = []
	if gh_player == null or not gh_player.has_method("get_equipped_tool"):
		s15a_missing.append("get_equipped_tool")
	else:
		var eq3: String = str(gh_player.call("get_equipped_tool"))
		if eq3 != "slithersap" and eq3 != "fairy":
			s15a_missing.append("equipped_tool!=slithersap/fairy(" + eq3 + ")")
		var tr15: Variant = gh_player.get("fp_tool_root")
		if tr15 is Node and (tr15 as Node).get_node_or_null("SapVial") != null:
			s15a_missing.append("fallback_sap_vial")
	await _capture_shot("S15a", "parity_1p_slithersap.png", s15a_missing, "1P Slithersap slot [3]")

	# S15b: Lockpick Minigame UI
	if gh_hud != null and gh_hud.has_method("set_lockpick_progress"):
		gh_hud.call("set_lockpick_progress", true, 0.45, 2)
	if gh_player != null and gh_player.has_method("set_lockpicking_active"):
		gh_player.call("set_lockpicking_active", true)
	await _wait_frames(6)
	var s15b_missing: Array[String] = []
	if gh_player == null or not gh_player.has_method("set_lockpicking_active"):
		s15b_missing.append("set_lockpicking_active")
	if gh_hud == null or (_find_named_node(gh_hud, "LockpickWheel") == null and _find_named_node(gh_hud, "LockpickArc") == null and not gh_hud.has_method("open_lockpick_minigame")):
		s15b_missing.append("circular_lockpick_minigame_ui")
	await _capture_shot("S15b", "parity_lockpick_ui.png", s15b_missing, "Lockpick minigame UI")
	if gh_hud != null and gh_hud.has_method("set_lockpick_progress"):
		gh_hud.call("set_lockpick_progress", false, 0.0, 1)
	if gh_player != null and gh_player.has_method("set_lockpicking_active"):
		gh_player.call("set_lockpicking_active", false)

	# S15c: [TAB] Map Overlay
	if InputMap.has_action("map_toggle"):
		await _tap_action("map_toggle")
	else:
		await _tap_key(KEY_TAB)
	await _wait_frames(6)
	var s15c_missing: Array[String] = []
	if not InputMap.has_action("map_toggle"):
		s15c_missing.append("input_action_map_toggle")
	if gh_hud == null or (_find_named_node(gh_hud, "MapOverlay") == null and not gh_hud.has_method("toggle_map_overlay")):
		s15c_missing.append("map_overlay_ui")
	await _capture_shot("S15c", "parity_map_overlay.png", s15c_missing, "[TAB] Map overlay")
	if InputMap.has_action("map_toggle"):
		await _tap_action("map_toggle")
	else:
		await _tap_key(KEY_TAB)
	await _wait_frames(3)

	# S15d: [MMB] Ping Radial
	if InputMap.has_action("ping_menu"):
		_press_action("ping_menu")
	else:
		_press_mouse_button(MOUSE_BUTTON_MIDDLE, true)
	await _wait_frames(6)
	var s15d_missing: Array[String] = []
	if not InputMap.has_action("ping_menu"):
		s15d_missing.append("input_action_ping_menu")
	if gh_hud == null or (_find_named_node(gh_hud, "PingRadial") == null and _find_named_node(gh_hud, "PingMenu") == null and not gh_hud.has_method("open_ping_radial")):
		s15d_missing.append("ping_radial_ui")
	await _capture_shot("S15d", "parity_ping_radial.png", s15d_missing, "[MMB] Ping radial")
	if InputMap.has_action("ping_menu"):
		_release_action("ping_menu")
	else:
		_press_mouse_button(MOUSE_BUTTON_MIDDLE, false)
	await _wait_frames(3)

	await _free_node_clean(gh)

	# =========================================================================
	# S16: OldManor_P Exterior Terrain Grounding & Forward Clearance
	# =========================================================================
	if gs != null:
		gs.set("active_contract_order", 3)
		gs.set("active_map_id", "old_manor")
	var om: Node3D = mission_scene.instantiate() as Node3D
	root.add_child(om)
	if not await _wait_for_mission_ready(om):
		printerr("PARITY_FATAL: Old Manor timed out waiting for player/doors")
		quit(1)
		return
	await _wait_frames(25)

	var s16_missing: Array[String] = []
	var om_player: CharacterBody3D = om.get("player") as CharacterBody3D
	if om_player == null:
		s16_missing.append("player")
	else:
		var om_w3d: World3D = om.get_world_3d()
		var grounded: bool = false
		if om_w3d != null:
			var om_phys: PhysicsDirectSpaceState3D = om_w3d.direct_space_state
			var q16: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(om_player.global_position + Vector3(0.0, 1.0, 0.0), om_player.global_position + Vector3(0.0, -8.0, 0.0), 1)
			var h16: Dictionary = om_phys.intersect_ray(q16)
			if not h16.is_empty():
				var hp16: Variant = h16.get("position", null)
				if hp16 is Vector3 and (hp16 as Vector3).y > -10.0:
					grounded = true
		if not grounded:
			s16_missing.append("old_manor_terrain_grounding")
		if om.get("fallback_spawn_headroom_clear") != true:
			s16_missing.append("fallback_spawn_headroom_clear")
		if om.get("fallback_spawn_forward_clear") != true:
			s16_missing.append("fallback_spawn_forward_clear")
	var om_env: WorldEnvironment = _find_first_world_env(om)
	if om_env == null or om_env.environment == null or not om_env.environment.ssr_enabled:
		s16_missing.append("env_ssr_enabled")
	await _capture_shot("S16", "parity_old_manor_exterior.png", s16_missing, "OldManor_P exterior terrain & SSR")
	await _free_node_clean(om)

	print("PARITY_GD_DONE: shots_saved=", _shots_saved, " image_failures=", _image_failures, " parity_passes=", _parity_passes, " parity_fails=", _parity_fails)
	if _image_failures > 0 or _shots_saved != 21:
		quit(1)
		return
	quit(0)
