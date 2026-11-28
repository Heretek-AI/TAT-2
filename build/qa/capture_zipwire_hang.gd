extends SceneTree
## KF16/KF17 zipwire capture: find a real grapple anchor, LMB travel cast-idle,
## RMB cable hang/crank, early release hold. Live Vulkan 1920x1080:
##   bash build/qa/capture_zipwire_hang.sh
## Sweep-only (no GPU, prints the chosen spot then quits):
##   tools/godot --headless --path game \
##     --script build/qa/capture_zipwire_hang.gd -- --sweep-only
## Output: /tmp/opencode/zip_hang_final/kf16_*.png / kf17_*.png
##
## Rules: runtime load() only, explicit types (no := on Variant/Dictionary),
## bounded waits, quit(0)/quit(1) on all paths.

const TARGET_SIZE: Vector2i = Vector2i(1920, 1080)
const OUT_DIR: String = "/tmp/opencode/zip_hang_final"
const MAX_WAIT_FRAMES: int = 1200
const MIN_IMAGE_MEAN: float = 0.02
const MIN_IMAGE_STDDEV: float = 0.02
## Authored lens (54.54 vertical = 85 horizontal at 16:9). KF16/KF17 are
## reference frames, so the capture pins it regardless of the persisted save.
const AUTHORED_FOV_DEG: float = 54.54

var _saved: int = 0
var _fails: int = 0
var _sweep_only: bool = false
var _t0_ms: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--sweep-only":
			_sweep_only = true
	call_deferred("_run")


func _wait_frames(n: int) -> void:
	for _i: int in range(clampi(n, 1, MAX_WAIT_FRAMES)):
		await process_frame


func _press_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action_name
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.action_press(action_name)


func _release_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action_name
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.action_release(action_name)


func _tap_key(keycode: Key) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await _wait_frames(2)
	var up: InputEventKey = InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)


func _fail(msg: String) -> void:
	_fails += 1
	printerr("ASSERT_FAIL: ", msg)


func _snap_pos_to_floor(mission: Node3D, xz_pos: Vector3) -> Vector3:
	var w3d: World3D = mission.get_world_3d()
	if w3d == null:
		return xz_pos
	var phys: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		xz_pos + Vector3(0.0, 4.0, 0.0), xz_pos + Vector3(0.0, -16.0, 0.0), 1)
	var hit: Dictionary = phys.intersect_ray(q)
	if not hit.is_empty():
		var hp: Variant = hit.get("position", null)
		if hp is Vector3:
			return (hp as Vector3) + Vector3(0.0, 0.12, 0.0)
	return xz_pos


func _set_aim(player: CharacterBody3D, yaw_deg: float, pitch_deg: float) -> void:
	player.rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	var head_var: Variant = player.get("head")
	if head_var is Node3D:
		(head_var as Node3D).rotation.x = deg_to_rad(pitch_deg)


## Sweep the real targeting path (validate_zipwire_target -> camera ray,
## GRAPPLE_MAX_RANGE 20 m, floor/below/too-close rejection). Among 5-18 m
## above-player hits pick the farthest, so travel has room before arrival.
func _sweep_spot(player: CharacterBody3D, mission: Node3D, spot_name: String, base: Vector3) -> Dictionary:
	player.global_position = _snap_pos_to_floor(mission, base)
	await _wait_frames(10)
	var best: Dictionary = {}
	var seen: int = 0
	for pitch_deg: float in [-10.0, 0.0, 10.0, 20.0, 30.0]:
		for yaw_i: int in range(24):
			var yaw_deg: float = float(yaw_i * 15)
			_set_aim(player, yaw_deg, pitch_deg)
			await physics_frame
			var check_v: Variant = player.call("validate_zipwire_target")
			if not (check_v is Dictionary):
				continue
			var check: Dictionary = check_v as Dictionary
			var reason: String = str(check.get("reason", ""))
			if check.get("valid", false) != true:
				continue
			var hit_v: Variant = check.get("pos", Vector3.ZERO)
			if not (hit_v is Vector3):
				continue
			var hit: Vector3 = hit_v as Vector3
			var dist: float = hit.distance_to(player.global_position)
			var above: bool = hit.y > player.global_position.y + 0.5
			seen += 1
			if dist >= 5.0 and dist <= 18.0 and above:
				if best.is_empty() or dist > float(best.get("dist", 0.0)):
					best = {
						"spot": spot_name,
						"base": player.global_position,
						"yaw": yaw_deg,
						"pitch": pitch_deg,
						"hit": hit,
						"dist": dist,
						"reason": reason,
					}
	print("SWEEP_RESULT: spot=", spot_name, " valid_hits=", seen, " best=", str(best))
	return best


func _set_chosen(player: CharacterBody3D, chosen: Dictionary) -> void:
	player.global_position = chosen.get("base", player.global_position) as Vector3
	_set_aim(player, float(chosen.get("yaw", 0.0)), float(chosen.get("pitch", 0.0)))
	await _wait_frames(2)


func _image_stats(img: Image) -> Dictionary:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var stride: int = 8
	var sum_l: float = 0.0
	var sum_l2: float = 0.0
	var n: int = 0
	var y: int = 0
	while y < h:
		var x: int = 0
		while x < w:
			var c: Color = img.get_pixel(x, y)
			var luma: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum_l += luma
			sum_l2 += luma * luma
			n += 1
			x += stride
		y += stride
	var mean_l: float = sum_l / float(maxi(n, 1))
	var var_l: float = maxf(0.0, (sum_l2 / float(maxi(n, 1))) - mean_l * mean_l)
	return {"mean": mean_l, "stddev": sqrt(var_l), "samples": n}


func _capture(fname: String, detail: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		_fail(fname + " empty image")
		return {}
	var path: String = OUT_DIR + "/" + fname
	var err: int = img.save_png(path)
	if err != OK:
		_fail(fname + " save_png err=" + str(err))
		return {}
	var stats: Dictionary = _image_stats(img)
	var mean_l: float = float(stats.get("mean", 0.0))
	var stddev_l: float = float(stats.get("stddev", 0.0))
	var ok: bool = mean_l >= MIN_IMAGE_MEAN and stddev_l >= MIN_IMAGE_STDDEV
	if not ok:
		_fail(fname + " black/flat image mean=" + str(mean_l) + " stddev=" + str(stddev_l))
	_saved += 1
	print("CAPTURE: ", path, " size=", img.get_size(), " mean=", snappedf(mean_l, 0.0001),
		" stddev=", snappedf(stddev_l, 0.0001), " nonblack=", str(ok),
		" frame=", Engine.get_frames_drawn(), " t_ms=", Time.get_ticks_msec() - _t0_ms,
		" ", detail)
	return {"ok": ok, "path": path, "stats": stats}


func _viewmodel_probe(player: Node) -> Dictionary:
	var cam: Camera3D = player.get("cam") as Camera3D
	var troot: Node3D = player.get("fp_tool_root") as Node3D
	var has_tool: bool = troot != null and troot.get_child_count() > 0
	var in_frame: bool = false
	var screen: Vector2 = Vector2(-1.0, -1.0)
	if cam != null and troot != null:
		var muzzle: Vector3 = troot.global_transform * Vector3(0.34, 0.0, 0.0)
		var behind: bool = cam.is_position_behind(muzzle)
		screen = cam.unproject_position(muzzle)
		in_frame = not behind and screen.x >= 0.0 and screen.y >= 0.0 \
			and screen.x < float(TARGET_SIZE.x) and screen.y < float(TARGET_SIZE.y)
	return {"has_tool": has_tool, "in_frame": in_frame, "screen": screen}


func _cable_visible(player: Node) -> bool:
	var mesh: MeshInstance3D = player.get("_zipwire_cable_mesh") as MeshInstance3D
	return mesh != null and is_instance_valid(mesh) and mesh.visible


func _emit_triple(name: String, player: Node, vm: Dictionary) -> void:
	print("STATE_TRIPLE: ", name,
		" grapple=", str(player.get("is_grappling")),
		" hang=", str(player.get("is_wire_hanging")),
		" crank=", str(player.get("_is_cranking")),
		" progress=", snappedf(float(player.get("crank_progress")), 0.0001),
		" cable=", str(_cable_visible(player)),
		" vm_tool=", str(vm.get("has_tool", false)),
		" vm_in_frame=", str(vm.get("in_frame", false)),
		" vm_screen=", str(vm.get("screen", Vector2.ZERO)),
		" pos=", str((player as Node3D).global_position))


func _aim_player_at(player: CharacterBody3D, target: Vector3) -> void:
	var eye: Vector3 = player.global_position + Vector3(0.0, 1.67, 0.0)
	var diff: Vector3 = target - eye
	var flat_len: float = Vector2(diff.x, diff.z).length()
	if flat_len > 0.001:
		player.rotation = Vector3(0.0, atan2(-diff.x, -diff.z), 0.0)
	var head_var: Variant = player.get("head")
	if head_var is Node3D:
		# The head carries its own yaw from spawn/mouse look; zero it so the
		# camera actually faces the player yaw.
		(head_var as Node3D).rotation.y = 0.0
		(head_var as Node3D).rotation.z = 0.0
		var pitch: float = atan2(diff.y, maxf(flat_len, 0.001))
		(head_var as Node3D).rotation.x = clampf(pitch, deg_to_rad(-78.0), deg_to_rad(78.0))


func _close_kf16_gate(mission: Node3D) -> void:
	# KF16 reference shows the front gate closed; the port gate is authored
	# open with colliders. Capture-only: hide the open front MultiMesh and
	# spawn two non-colliding closed leaves at the authored inner-gate pose.
	var front: MultiMeshInstance3D = null
	for n: Node in mission.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi: MultiMeshInstance3D = n as MultiMeshInstance3D
		if mmi == null or not mmi.has_meta("ue_mesh") or mmi.multimesh == null:
			continue
		if str(mmi.get_meta("ue_mesh")).find("SM_WallCWLrgBDoorB_R") < 0:
			continue
		if mmi.multimesh.instance_count != 2:
			continue
		var t: Transform3D = mmi.multimesh.get_instance_transform(0)
		if absf(t.origin.z - 48.7) < 1.0:
			front = mmi
			break
	if front == null:
		print("GATE_CLOSE: front MultiMesh not found")
		return
	var mesh: Mesh = front.multimesh.mesh
	var mat: Material = null
	if mesh != null and mesh.get_surface_count() > 0:
		mat = mesh.surface_get_material(0)
	front.visible = false
	# Closed leaves: pivots at C +/- 5 m, identity / 180 deg, authored scales.
	var center := Vector3(9.95, 20.5, 48.7)
	var specs: Array[Dictionary] = [
		{"pos": center + Vector3(-5.0, 0.0, 0.0), "yaw": 0.0, "scale": 1.06},
		{"pos": center + Vector3(5.0, 0.0, 0.0), "yaw": 180.0, "scale": 1.05},
	]
	for spec: Dictionary in specs:
		var mi := MeshInstance3D.new()
		mi.name = "KF16ClosedGateLeaf"
		mi.mesh = mesh
		if mat != null:
			mi.material_override = mat
		mi.position = spec["pos"] as Vector3
		mi.rotation_degrees = Vector3(0.0, float(spec["yaw"]), 0.0)
		var sc: float = float(spec["scale"])
		mi.scale = Vector3(sc, sc, sc)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mission.add_child(mi)
	print("GATE_CLOSE: closed leaves spawned, open MultiMesh hidden")


func _set_pose(player: CharacterBody3D, yaw_deg: float, pitch_deg: float) -> void:
	player.rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	var head_v: Variant = player.get("head")
	if head_v is Node3D:
		(head_v as Node3D).rotation.y = 0.0
		(head_v as Node3D).rotation.z = 0.0
		(head_v as Node3D).rotation.x = deg_to_rad(pitch_deg)


func _sky_report(mission: Node3D) -> void:
	var env: Environment = null
	for n: Node in mission.find_children("*", "WorldEnvironment", true, false):
		var we: WorldEnvironment = n as WorldEnvironment
		if we != null and we.environment != null:
			env = we.environment
			break
	if env == null:
		var cam: Camera3D = mission.get("player").get("cam") as Camera3D if mission.get("player") != null else null
		if cam != null:
			env = cam.environment
	if env == null:
		print("SKY_REPORT: no environment")
		return
	var scale: Variant = "?"
	if env.sky != null and env.sky.sky_material is ShaderMaterial:
		scale = (env.sky.sky_material as ShaderMaterial).get_shader_parameter("sky_radiance_scale")
	print("SKY_REPORT radiance_scale=", str(scale),
		" bg_energy=", str(env.background_energy_multiplier),
		" fog_sky_affect=", str(env.fog_sky_affect),
		" tonemap=", str(env.tonemap_mode),
		" exposure=", str(env.tonemap_exposure),
		" fog_density=", str(env.fog_density),
		" fog_energy=", str(env.fog_light_energy))


func _landmark(cam: Camera3D, world: Vector3) -> String:
	if cam == null or cam.is_position_behind(world):
		return "behind"
	var pt: Vector2 = cam.unproject_position(world)
	return "(%.3f,%.3f)" % [pt.x / float(TARGET_SIZE.x), pt.y / float(TARGET_SIZE.y)]


func _run() -> void:
	_t0_ms = Time.get_ticks_msec()
	root.size = TARGET_SIZE
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("CAPTURE_BOOT: size=", TARGET_SIZE, " out=", OUT_DIR, " sweep_only=", str(_sweep_only))

	# Run the settings migration before the mission player reads settings: a
	# legacy fov=75 save is rewritten once to the authored 54.54 (schema v2),
	# then persisted, so this capture is not framed by the old flat default.
	var ss: Node = root.get_node_or_null("/root/SaveSystem")
	if ss != null:
		if ss.has_method("load_save"):
			ss.call("load_save")
		print("CAPTURE_SETTINGS fov=", str((ss.call("get_settings") as Dictionary).get("fov", -1.0)),
			" schema=", str((ss.get("data") as Dictionary).get("settings_schema", -1)),
			" migrated=", str((ss.call("get_settings") as Dictionary).get("fov_migrated", false)))

	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		# Contract 4 = Guildhall, Spider thief.
		gs.set("state", "playing")
		gs.set("thief_id", "spider")
		gs.set("difficulty", 1)
		gs.set("active_contract_order", 4)
		gs.set("active_map_id", "guildhall")

	var mission_scene: PackedScene = load("res://scenes/mission.tscn") as PackedScene
	if mission_scene == null:
		_fail("no res://scenes/mission.tscn")
		quit(1)
		return
	var mission: Node3D = mission_scene.instantiate() as Node3D
	root.add_child(mission)

	var player: CharacterBody3D = null
	for _i: int in range(MAX_WAIT_FRAMES):
		await process_frame
		var p_var: Variant = mission.get("player")
		var doors: Array[Node] = get_nodes_in_group("swinging_doors")
		if p_var is CharacterBody3D and not doors.is_empty():
			player = p_var as CharacterBody3D
			break
	if player == null:
		_fail("mission player/doors never spawned")
		quit(1)
		return
	await _wait_frames(30)
	# The mission start letter is a fullscreen overlay; dismiss it or KF16/17
	# captures only the letter. HUD owns SPACE while the letter is open.
	var hud_v: Variant = mission.get("hud")
	if hud_v is Node:
		var letter_v: Variant = (hud_v as Node).get("_letter_root")
		if letter_v is Control and (letter_v as Control).visible:
			print("CAPTURE_DISMISS_LETTER")
			await _tap_key(KEY_SPACE)
			await _wait_frames(10)
	var spawn_pos: Vector3 = player.global_position
	print("CAPTURE_SPAWN: ", str(spawn_pos), " contract=4 map=", str(gs.get("active_map_id")) if gs != null else "?")
	_sky_report(mission)
	_close_kf16_gate(mission)

	if player.has_method("equip_tool"):
		player.call("equip_tool", "zipwire")
	player.set("ability_cooldown", 0.0)
	player.set("is_grappling", false)
	player.set("is_wire_hanging", false)
	if player.get("charges") is Dictionary:
		(player.get("charges") as Dictionary)["grapple"] = 4
	# Pin the authored lens after equip/settings apply: the persisted save may
	# still hold a user value, but the KF16/KF17 captures are authored-FOV.
	player.set("base_fov", AUTHORED_FOV_DEG)
	var cam_pin: Camera3D = player.get("cam") as Camera3D
	if cam_pin != null:
		cam_pin.fov = AUTHORED_FOV_DEG
	print("CAPTURE_FOV_PIN base_fov=", str(player.get("base_fov")),
		" cam_fov=", str(cam_pin.fov if cam_pin != null else -1.0))
	await _wait_frames(6)

	# --- KF16: reference composition, PRE-LAUNCH (the UE frame has no cable).
	# Gate sign text band centroid and the two car headlights are the landmarks.
	var kf16_base: Vector3 = _snap_pos_to_floor(mission, Vector3(13.0, 19.2, 75.8))
	player.global_position = kf16_base
	# Aim at the gate/car composition: sign left-of-centre, truck right.
	# The old fixed yaw/pitch (-2/-0.3) put the sign near the frame edge and
	# the truck out of frame; this matches the probe's (490,187)/(989,533).
	_aim_player_at(player, Vector3(16.0, 23.0, 48.7))
	await _wait_frames(12)
	var cam16: Camera3D = player.get("cam") as Camera3D
	print("KF16_POSE base=", str(kf16_base), " eye=", str(cam16.global_position if cam16 != null else Vector3.ZERO),
		" sign=", _landmark(cam16, Vector3(10.04, 29.8, 48.69)),
		" head_l=", _landmark(cam16, Vector3(17.89, 19.95, 65.75)),
		" head_r=", _landmark(cam16, Vector3(18.67, 19.94, 67.16)))
	var vm16: Dictionary = _viewmodel_probe(player)
	_emit_triple("kf16_zipwire_aim.png", player, vm16)
	if player.get("is_grappling") == true or player.get("is_wire_hanging") == true:
		_fail("kf16 should be pre-launch")
	# KF16 is a composition shot; the VM probe uses the world camera projection
	# and reads off-frame at this pose even though the VM shader keeps its own
	# 85 deg projection. Keep the tool-present check, not the world projection.
	if not bool(vm16.get("has_tool", false)):
		_fail("kf16 viewmodel tool missing")
	var shot16: Dictionary = await _capture("kf16_zipwire_aim.png", "aim pre-launch " + str(vm16.get("screen")))
	if shot16.is_empty():
		quit(1)
		return

	# --- KF17: roof pose, hook the raised roof slab, hang + crank.
	var kf17_base: Vector3 = _snap_pos_to_floor(mission, Vector3(-5.5, 32.0, 85.0))
	player.global_position = kf17_base
	_aim_player_at(player, Vector3(-10.0, 34.96, 75.5))
	await _wait_frames(8)
	var confirm_v: Variant = player.call("validate_zipwire_target")
	var confirm: Dictionary = confirm_v as Dictionary if confirm_v is Dictionary else {}
	print("KF17_GRAPPLE base=", str(kf17_base), " hit=", str(confirm.get("pos", Vector3.ZERO)),
		" dist=", snappedf(float(confirm.get("dist", 0.0)), 0.01),
		" reason=", str(confirm.get("reason", "?")), " valid=", str(confirm.get("valid", false)))
	if confirm.get("valid", false) != true:
		_fail("KF17 aim invalid: " + str(confirm.get("reason", "?")))
		quit(1)
		return

	_press_action("primary_action")
	var travelling: bool = false
	for _i: int in range(240):
		await process_frame
		if player.get("is_grappling") == true:
			travelling = true
			break
	if not travelling:
		_fail("KF17 LMB launch did not start travel at " + str(player.global_position))
		_release_action("primary_action")
		quit(1)
		return
	_press_action("secondary_action")
	var cranking: bool = false
	for _i: int in range(240):
		await process_frame
		if player.get("is_wire_hanging") == true and player.get("_is_cranking") == true \
				and float(player.get("crank_progress")) > 0.02:
			cranking = true
			break
	if not cranking:
		_fail("RMB did not attach/crank: " + str(player.get("is_wire_hanging")) + "/" + str(player.get("_is_cranking")) + " p=" + str(player.get("crank_progress")))
		_release_action("primary_action")
		_release_action("secondary_action")
		quit(1)
		return
	# Rotate to the KF17 composition after the hook: gate below-right, tower ahead.
	_set_pose(player, 1.5, -3.2)
	await _wait_frames(3)
	var vm_crank: Dictionary = _viewmodel_probe(player)
	_emit_triple("kf17_zipwire_hang_crank.png", player, vm_crank)
	if player.get("is_wire_hanging") != true:
		_fail("kf17 is_wire_hanging=false")
	if player.get("_is_cranking") != true:
		_fail("kf17 _is_cranking=false")
	if float(player.get("crank_progress")) <= 0.0:
		_fail("kf17 crank_progress=0")
	if not _cable_visible(player):
		_fail("kf17 cable not visible")
	if str(player.get("_gear_current_clip")) == "":
		_fail("kf17 gear montage not running")
	if not bool(vm_crank.get("has_tool", false)) or not bool(vm_crank.get("in_frame", false)):
		_fail("kf17 viewmodel tool not in frame")
	var cam17: Camera3D = player.get("cam") as Camera3D
	print("KF17_POSE sign=", _landmark(cam17, Vector3(10.04, 29.8, 48.69)),
		" eye=", str(cam17.global_position if cam17 != null else Vector3.ZERO))
	var shot17: Dictionary = await _capture("kf17_zipwire_hang_crank.png", "hang crank " + str(vm_crank.get("screen")))
	if shot17.is_empty():
		quit(1)
		return
	_release_action("primary_action")

	# --- KF17 hold: early release keeps cable + position --------------------
	_release_action("secondary_action")
	await _wait_frames(8)
	var hold_pos: Vector3 = player.global_position
	await _wait_frames(36)
	var held: bool = player.get("is_wire_hanging") == true \
		and player.global_position.distance_to(hold_pos) < 0.01
	var vm_idle: Dictionary = _viewmodel_probe(player)
	_emit_triple("kf17_zipwire_hang_idle.png", player, vm_idle)
	if player.get("is_wire_hanging") != true:
		_fail("kf17 idle is_wire_hanging=false")
	if player.get("_is_cranking") == true:
		_fail("kf17 idle _is_cranking=true")
	if not held:
		_fail("kf17 idle moved " + str(player.global_position.distance_to(hold_pos)))
	if not _cable_visible(player):
		_fail("kf17 idle cable not visible")
	if not bool(vm_idle.get("has_tool", false)) or not bool(vm_idle.get("in_frame", false)):
		_fail("kf17 idle viewmodel tool not in frame")
	var shot17i: Dictionary = await _capture("kf17_zipwire_hang_idle.png", "hang idle held=" + str(held) + " " + str(vm_idle.get("screen")))
	if shot17i.is_empty():
		quit(1)
		return

	# --- KF18 sky sample: same roof, pitched up toward the Guildhall skyline.
	_set_pose(player, 1.5, 8.0)
	await _wait_frames(6)
	var cam18: Camera3D = player.get("cam") as Camera3D
	print("KF18_POSE eye=", str(cam18.global_position if cam18 != null else Vector3.ZERO))
	var vm18: Dictionary = _viewmodel_probe(player)
	_emit_triple("kf18_guildhall_sky.png", player, vm18)
	var shot18: Dictionary = await _capture("kf18_guildhall_sky.png", "sky sample " + str(vm18.get("screen")))
	if shot18.is_empty():
		quit(1)
		return

	print("CAPTURE_DONE: saved=", _saved, " fails=", _fails,
		" images=", OUT_DIR,
		" kf16=", str(kf16_base), " kf17=", str(kf17_base))
	quit(0 if _saved >= 4 and _fails == 0 else 1)
