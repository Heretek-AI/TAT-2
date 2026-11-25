extends SceneTree
## W5A/W6M: authored stair traversal (real level colliders) + Den wardrobe prompt.
## Run: tools/godot --headless --path game --script res://tests/test_stair_walk.gd
##
## Why this exists: the geometry audit found every stair run in the shipped
## levels is a trimesh flight — the civic flight measures 0.25 m risers on
## 0.33 m treads (~37 deg) — and the port could not walk it: the step probe
## reached 0.35 m from the capsule axis (past the tread), so a riser read as a
## wall and auto-mantle covered it with a 0.3 s animation.
##
## The colliders are the real ones: level_loader._get_mesh_and_shape() builds
## the same ConcavePolygonShape3D the loader drops into the level, so the
## fixture walks the shipped geometry, not a synthetic staircase. Ground and
## top-landing slabs are test scaffolding: the flights have no approach or
## exit floor of their own.
##
## W6M adds the shipped INSTANCES, not just the meshes: each route carries the
## authored basis/scale (and the level/pos it came from) so the rotated civic
## run (−X), the rotated industrial run (+Z), the non-uniform Old Manor tower
## (10.29 m mesh / 10.49 m scaled) and the 3x850 POI run are walked the way the
## loader places them. A descent pass walks the rotated civic flight downwards
## (0.25 m risers must stay snapped), and the civic ascent also verifies the
## camera settles after the climb and the interaction prompt still resolves.
##
## The walk is driven by the real input action (move_forward) through the real
## _physics_process, one physics frame per step, exactly like play.

## basis is the shipped `.tatlevel.json` array (column-major, same decode as
## level_loader._json_to_transform), scale the shipped instance scale. The
## source note names the level and world position the instance came from.
const FLIGHTS: Array[Dictionary] = [
	{
		"label": "civic_3x150", "path": "/Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x150cm",
		"basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "scale": [1, 1, 1], "frames": 180, "min_ascent": 1.4,
		"source": "Guildhall POI 24.95/26.47/-27.10 (identity)",
	},
	{
		"label": "industrial_3x150", "path": "/Game/Art/Environment/Urban/Industrial/Stairs/SM_Stairs_Industrial_3x150cm",
		"basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "scale": [1, 1, 1], "frames": 180, "min_ascent": 1.4,
		"source": "Guildhall POI 3rdFloor 12.40/64.00/-46.35 (identity, y 1.0454)",
	},
	{
		"label": "city_6x2m", "path": "/Game/Art/Environment/City/Architecture/Stairs/2m/SM_StairsCity6x2m",
		"basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "scale": [1, 1, 1], "frames": 180, "min_ascent": 1.4,
		"source": "authored mesh AABB only (no single shipped instance)",
	},
	{
		"label": "poi_3x850", "path": "/Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x850cm",
		"basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "scale": [1, 1, 1], "frames": 260, "min_ascent": 7.4,
		"source": "Guildhall POI 36.65/36.51/-37.50 (rising -Z)",
	},
	{
		"label": "civic_3x150_rotX", "path": "/Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x150cm",
		"basis": [0, 0, 1, 0, 1, 0, -1, 0, 0], "scale": [1, 1, 1], "frames": 100, "min_ascent": 1.4,
		"down": true,
		"source": "Guildhall PeripheryA 47.58/12.48/-4.18 (rising -X)",
	},
	{
		"label": "industrial_rotZ", "path": "/Game/Art/Environment/Urban/Industrial/Stairs/SM_Stairs_Industrial_3x150cm",
		"basis": [-1, 0, 0, 0, 1, 0, 0, 0, -1], "scale": [1, 1, 1], "frames": 180, "min_ascent": 1.4,
		"source": "Guildhall PeripheryA 54.14/20.07/69.42 (rising +Z)",
	},
	{
		"label": "oldmanor_tower_4x850", "path": "/Game/Art/Environment/OldManor/SM_OldManor_Tower_Stairs_4x850",
		"basis": [1, 0, 0, 0, 1, 0, 0, 0, 1], "scale": [1, 1.02, 0.9503], "frames": 280, "min_ascent": 8.4,
		"source": "OldManor_Geo -53.00/33.23/16.50 (10.29 m mesh AABB; 8.8 m of walkable treads, the rest is rail/post tops)",
	},
]
const WALK_FRAMES: int = 180
const MAX_ZERO_PROGRESS_FRAMES: int = 2
const MAX_LATERAL_DRIFT_M: float = 0.15
## A frame counts as progress when the body advanced along the flight (-z) or
## rose. A sub-millimetre frame is noise, not progress.
const PROGRESS_EPS_M: float = 0.0005
## W6M camera settle target: after the climb, the eye must be back within 2 cm
## of the resting height in at most 0.4 s (24 physics frames at 60 Hz). The
## 0.20 m step smoothing cap decays at 9/s, so 24 frames is ~3.6 e-foldings.
const CAMERA_SETTLE_EPS_M: float = 0.02
const CAMERA_SETTLE_MAX_FRAMES: int = 24

var fails: int = 0
var _ld: Node = null
var _route_index: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.set("state", "playing")
	var thief_script: GDScript = load("res://src/player/thief_character.gd") as GDScript
	_ld = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(_ld)
	await process_frame

	for flight: Dictionary in FLIGHTS:
		var res: Dictionary = await _walk_flight(thief_script, flight)
		_check_walk(flight, res)
		var down: bool = bool(flight.get("down", false))
		_check(res.get("end_on_floor", false) == true,
			"%s %s ends grounded (is_on_floor=true)" % [str(flight.get("label", "?")), "descent" if down else "ascent"],
			"%s %s did NOT end on the floor: %s" % [str(flight.get("label", "?")), "descent" if down else "ascent", str(res.get("end", "?"))])

	await _check_wardrobe_prompt(thief_script)
	await _check_ramp_not_stepped(thief_script)
	Input.action_release("move_forward")
	Input.action_release("jump")
	await process_frame
	_ld.queue_free()
	await process_frame
	print("W6M_STAIR_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


## Build the shipped collider in its shipped pose, place a run-up slab and a top
## landing, then walk for `frames` physics frames and report measured metrics.
func _walk_flight(thief_script: GDScript, flight: Dictionary) -> Dictionary:
	var path: String = str(flight.get("path", ""))
	var label: String = str(flight.get("label", "?"))
	_route_index += 1
	var out: Dictionary = {"label": label, "ok": false}
	var info: Dictionary = _ld.call("_get_mesh_and_shape", path) as Dictionary
	var shape: Shape3D = info.get("shape") as Shape3D
	if not (shape is ConcavePolygonShape3D):
		out["error"] = "no trimesh collider for " + path
		return out
	var faces: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
	var basis: Basis = _shipped_basis(flight)
	var scale: Vector3 = _shipped_scale(flight)

	var rig := Node3D.new()
	rig.name = "StairRig_" + label
	root.add_child(rig)
	# Frame is the flight's own yaw: local forward is -Z and local +X is the
	# tread width, so the W5A scaffolding math stays in metres. Only the mesh
	# collider under it carries the shipped scale.
	var frame := Node3D.new()
	frame.name = "Frame"
	rig.add_child(frame)
	rig.global_position = Vector3(20000.0 + 400.0 * float(_route_index), 0.0, 20000.0)
	var rise_dir: Vector3 = (basis * Vector3(0.0, 0.0, -1.0)).normalized()
	frame.rotation = Vector3(0.0, atan2(-rise_dir.x, -rise_dir.z), 0.0)
	await process_frame

	# Mesh collider exactly like level_loader._add_collider: shape in mesh-local
	# space, orthonormal rotation + non-uniform scale on the CollisionShape3D.
	var body := StaticBody3D.new()
	body.name = "ShippedFlight"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(basis.orthonormalized(), Vector3.ZERO)
	cs.scale = Vector3(maxf(absf(scale.x), 0.05), maxf(absf(scale.y), 0.05), maxf(absf(scale.z), 0.05))
	body.add_child(cs)
	# The collider hangs off the rig (identity), not the frame: the frame only
	# orients the scaffolding/walker, so the mesh keeps its shipped basis.
	rig.add_child(body)

	# Frame-local AABB of the placed mesh (scale applied, shipped basis folded
	# into the frame yaw) — the frame's -Z is the world rise direction.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v: Vector3 in faces:
		var p: Vector3 = frame.global_transform.affine_inverse() * rig.to_global(basis * (v * scale))
		lo = lo.min(p)
		hi = hi.max(p)
	var mid_x: float = (lo.x + hi.x) * 0.5
	var width: float = maxf(hi.x - lo.x, 1.0)
	# Approach floor and the landing at the flight's measured top tread, so the
	# held input never falls off an edge. The mesh AABB max-y can be a handrail
	# (industrial 1.675 vs a 1.58 tread), so the landing height comes from a ray.
	var top_y: float = _floor_height_at(frame.to_global(Vector3(mid_x, hi.y + 0.5, lo.z + 0.15)), lo.y - 0.5)
	if is_nan(top_y):
		top_y = hi.y
	# The rig/frame sit at y = 0 with a yaw-only frame, so frame-local y is
	# world y; top_y is already the local height the landing must support.
	top_y -= frame.global_position.y
	var ground_sz := Vector3(width + 2.0, 0.4, 6.0)
	_add_box(frame, Vector3(mid_x, -0.2, hi.z + 2.9), ground_sz)
	var landing_sz := Vector3(width + 2.0, 0.4, 2.0)
	_add_box(frame, Vector3(mid_x, top_y - 0.2, lo.z - 0.95), landing_sz)
	# Backstop at the far end of the landing: keeps the final height honest
	# once the climb is done (the streak metric stops at min_ascent). Tall
	# enough (top > 4 m of mantle reach) that the seam cannot mantle it.
	_add_box(frame, Vector3(mid_x, top_y + 3.0, lo.z - 2.0), Vector3(width + 2.0, 8.0, 0.2))
	# The landing's own top face is the destination for the descent pass.
	var down: bool = bool(flight.get("down", false))
	var thief: CharacterBody3D = thief_script.new() as CharacterBody3D
	thief.name = "StairWalker_" + label
	thief.set_physics_process(false)
	# Keep the walker directly under the identity rig: the controller evaluates
	# its input in `transform.basis` (parent-local) but feeds `velocity` to
	# move_and_slide in global space, so a rotated parent would turn the held
	# move_forward into a sideways walk. Face it along the flight's world rise.
	rig.add_child(thief)
	await process_frame
	var walk_yaw: float = atan2(-rise_dir.x, -rise_dir.z)
	if down:
		# Descent: start on the landing, face back down the flight.
		thief.rotation = Vector3(0.0, walk_yaw + PI, 0.0)
		thief.global_position = frame.to_global(Vector3(mid_x, top_y + 0.02, lo.z - 0.85))
	else:
		thief.rotation = Vector3(0.0, walk_yaw, 0.0) # forward is -Z, the flight's rise direction
		thief.global_position = frame.to_global(Vector3(mid_x, 0.02, hi.z + 0.7))
	thief.set_physics_process(true)
	await physics_frame

	var start_y: float = (thief as Node3D).global_position.y
	var start_local: Vector3 = frame.to_local((thief as Node3D).global_position)
	var start_x: float = (thief as Node3D).global_position.x
	var prev_local_z: float = start_local.z
	var prev_y: float = start_y
	var zero_streak: int = 0
	var max_zero_streak: int = 0
	var air_streak: int = 0
	var max_air_streak: int = 0
	var max_drift: float = 0.0
	var mantled: bool = false
	var frames_to_target: int = -1
	var zero_frames_total: int = 0
	var climbs: int = 0
	var max_cam_offset: float = 0.0
	var cam_node: Camera3D = thief.get("cam") as Camera3D
	var eye_rest_y: float = float(thief_script.get_script_constant_map().get("STAND_HEAD_HEIGHT", 1.66875))
	var target_m: float = 0.6 * float(flight.get("min_ascent", 1.4)) if down else float(flight.get("min_ascent", 1.4))
	Input.action_press("move_forward")
	for i: int in range(int(flight.get("frames", WALK_FRAMES))):
		await physics_frame
		var pos: Vector3 = (thief as Node3D).global_position
		var rose: float = pos.y - prev_y
		if cam_node != null:
			max_cam_offset = maxf(max_cam_offset, absf((cam_node.global_position.y - pos.y) - eye_rest_y))
		if bool(thief.get("is_mantling")):
			mantled = true
			print("W6M: unexpected auto-mantle at frame ", i, " route=", label, " pos=", pos)
		var local: Vector3 = frame.to_local(pos)
		max_drift = maxf(max_drift, absf(local.x - start_local.x))
		# Progress is measured in the flight's own frame: rotated routes walk
		# +Z local while others walk -Z, so a world-axis test read them as stuck.
		var advanced: bool = (prev_local_z - local.z) > PROGRESS_EPS_M or rose > PROGRESS_EPS_M
		if down:
			if start_y - pos.y >= target_m and frames_to_target < 0:
				frames_to_target = i + 1
		elif pos.y - start_y >= target_m and frames_to_target < 0:
			frames_to_target = i + 1
		if frames_to_target < 0:
			if advanced:
				zero_streak = 0
			else:
				zero_streak += 1
				zero_frames_total += 1
				max_zero_streak = maxi(max_zero_streak, zero_streak)
		if rose > 0.02:
			climbs += 1
		# Descent is measured, not asserted: consecutive airborne frames.
		if not bool(thief.is_on_floor()):
			air_streak += 1
			max_air_streak = maxi(max_air_streak, air_streak)
		else:
			air_streak = 0
		prev_local_z = local.z
		prev_y = pos.y
	Input.action_release("move_forward")
	await physics_frame

	# W6M camera settle: stop steering and let the step smoothing ease out.
	var settle_frames: int = -1
	if cam_node != null:
		for s: int in range(CAMERA_SETTLE_MAX_FRAMES + 8):
			await physics_frame
			var p: Vector3 = (thief as Node3D).global_position
			if absf((cam_node.global_position.y - p.y) - eye_rest_y) < CAMERA_SETTLE_EPS_M:
				settle_frames = s + 1
				break
	var end_pos: Vector3 = (thief as Node3D).global_position
	var end_floor: bool = bool(thief.is_on_floor())
	out["ok"] = true
	out["ascent_m"] = (start_y - end_pos.y) if down else (end_pos.y - start_y)
	out["frames_to_target"] = frames_to_target
	out["max_zero_streak"] = max_zero_streak
	out["zero_frames_total"] = zero_frames_total
	out["max_air_streak"] = max_air_streak
	out["max_drift_m"] = max_drift
	out["mantled"] = mantled
	out["step_frames"] = climbs
	out["max_cam_offset_m"] = max_cam_offset
	out["camera_settle_frames"] = settle_frames
	out["rise_m"] = top_y
	out["run_m"] = hi.z - lo.z
	out["end"] = end_pos
	out["end_on_floor"] = end_floor
	out["down"] = down
	if label == "civic_3x150":
		out["prompt"] = await _prompt_after_climb(thief, frame, mid_x, top_y, end_pos)
	thief.queue_free()
	rig.queue_free()
	await physics_frame
	return out


## The interaction prompt must still resolve after an ascent: a real Area3D
## interactable on the landing, one capsule-and-a-bit to the side, with the
## authored "floor position + UP*1.2" interaction point the Den fill uses.
func _prompt_after_climb(thief: CharacterBody3D, frame: Node3D, mid_x: float, top_y: float, end_pos: Vector3) -> String:
	var area := Area3D.new()
	area.name = "W6MLandingPrompt"
	area.add_to_group("interactables")
	var local_end: Vector3 = frame.to_local(end_pos)
	var at_local := Vector3(mid_x + clampf(local_end.x - mid_x, -1.0, 1.0) + 0.9, top_y, local_end.z)
	area.position = at_local
	area.set_meta("interaction_point", frame.to_global(at_local + Vector3(0.0, 1.2, 0.0)))
	var sphere := SphereShape3D.new()
	sphere.radius = 2.2
	var acol := CollisionShape3D.new()
	acol.shape = sphere
	area.add_child(acol)
	var script := GDScript.new()
	script.source_code = "extends Area3D\nfunc get_interact_prompt() -> String:\n\treturn \"[F] CLIMB LOOT\"\n"
	script.reload()
	area.set_script(script)
	frame.add_child(area)
	await physics_frame
	var reached: Node = thief.call("get_nearest_interactable")
	var prompt: String = str(thief.call("get_look_interact_prompt"))
	var ok: bool = reached == area and prompt == "[F] CLIMB LOOT"
	_check(ok,
		"interaction prompt resolves from the stair landing after the climb (nearest=landing, prompt='" + prompt + "')",
		"interaction prompt BROKEN after the climb: nearest=" + str(reached) + " prompt='" + prompt + "'")
	area.queue_free()
	await physics_frame
	return prompt


func _check_walk(flight: Dictionary, res: Dictionary) -> void:
	var label: String = str(flight.get("label", "?"))
	if not bool(res.get("ok", false)):
		printerr("FAIL: ", label, " stair fixture: ", str(res.get("error", "unknown")))
		fails += 1
		return
	var down: bool = bool(res.get("down", false))
	var moved: float = float(res["ascent_m"])
	var min_m: float = 0.6 * float(flight.get("min_ascent", 1.4)) if down else float(flight.get("min_ascent", 1.4))
	var ok: bool = moved >= min_m \
		and not bool(res["mantled"]) \
		and float(res["max_drift_m"]) < MAX_LATERAL_DRIFT_M \
		and float(res["max_cam_offset_m"]) <= 0.25 \
		and int(res["camera_settle_frames"]) > 0 \
		and int(res["camera_settle_frames"]) <= CAMERA_SETTLE_MAX_FRAMES
	if not down:
		ok = ok and int(res["max_zero_streak"]) <= MAX_ZERO_PROGRESS_FRAMES
	var ok_msg: String = "%s %s: %s=%.2f m (authored %.2f m over %.2f m run, %s), target in %d frames, max zero-progress streak=%d, air streak=%d, step frames=%d, drift=%.3f m, camera lag=%.3f m, settle=%d frames, mantle=%s" % [
		label, "descent" if down else "ascent", "descent" if down else "ascent", moved,
		float(res["rise_m"]), float(res["run_m"]), str(flight.get("source", "")),
		int(res["frames_to_target"]), int(res["max_zero_streak"]), int(res["max_air_streak"]),
		int(res["step_frames"]), float(res["max_drift_m"]), float(res["max_cam_offset_m"]),
		int(res["camera_settle_frames"]), str(res["mantled"])]
	var fail_msg: String = "%s %s FAILED: moved=%.2f m (< %.2f), zero streak=%d (> %d), max air streak=%d, drift=%.3f m, camera lag=%.3f m, settle=%d frames, mantled=%s, frames_to_target=%d, end=%s" % [
		label, "descent" if down else "ascent", moved, min_m,
		int(res["max_zero_streak"]), MAX_ZERO_PROGRESS_FRAMES, int(res["max_air_streak"]),
		float(res["max_drift_m"]), float(res["max_cam_offset_m"]),
		int(res["camera_settle_frames"]), str(res["mantled"]), int(res["frames_to_target"]),
		str(res["end"])]
	_check(ok, ok_msg, fail_msg)


func _shipped_basis(flight: Dictionary) -> Basis:
	var b: Array = flight.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]) as Array
	return Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	)


func _shipped_scale(flight: Dictionary) -> Vector3:
	var s: Array = flight.get("scale", [1, 1, 1]) as Array
	return Vector3(float(s[0]), float(s[1]), float(s[2]))


## Den wardrobe regression: the authored interaction point sits 0.48 m behind
## the cabinet's front face (mission_controller DenWardrobeArea:
## position + UP*1.2). The old LOS endpoint was capped at half the player
## distance, so a close player's ray ended inside the cabinet and the prompt
## never resolved. The fixture reproduces that geometry from the front.
func _check_wardrobe_prompt(thief_script: GDScript) -> void:
	var base := Vector3(9000.0, 0.0, 9000.0)
	var host := Node3D.new()
	host.name = "WardrobePromptRig"
	host.global_position = base
	root.add_child(host)
	# Cabinet body: 0.6 m deep, front face at z = +0.7 relative to base.
	_add_box(host, Vector3(0.0, 1.0, 1.0), Vector3(1.2, 2.0, 0.6))
	# Interactable Area, exactly like the Den fill: floor position + UP*1.2.
	var area := Area3D.new()
	area.name = "W5AWardrobeArea"
	area.position = Vector3(0.0, 0.0, 1.0)
	area.add_to_group("interactables")
	area.set_meta("interaction_point", base + Vector3(0.0, 1.2, 1.0))
	var sphere := SphereShape3D.new()
	sphere.radius = 2.2
	var acol := CollisionShape3D.new()
	acol.shape = sphere
	area.add_child(acol)
	var script := GDScript.new()
	script.source_code = "extends Area3D\nfunc get_interact_prompt() -> String:\n\treturn \"[F] CUSTOMIZE LOADOUT\"\n"
	script.reload()
	area.set_script(script)
	host.add_child(area)

	# Player capsule stands where the cabinet body lets it: 0.32 m in front of
	# the face, i.e. 0.80 m from the interaction point.
	var thief: CharacterBody3D = thief_script.new() as CharacterBody3D
	thief.name = "W5AWardrobeThief"
	thief.set_physics_process(false)
	host.add_child(thief)
	await process_frame
	thief.global_position = base + Vector3(0.0, 0.0, 0.38)
	await physics_frame
	var reached: Node = thief.call("get_nearest_interactable")
	var prompt: String = str(thief.call("get_look_interact_prompt"))
	var reachable_ok: bool = reached == area and prompt == "[F] CUSTOMIZE LOADOUT"
	_check(reachable_ok,
		"Den wardrobe prompt resolves through its own 0.48 m-deep cabinet (nearest=wardrobe, prompt='" + prompt + "')",
		"Den wardrobe prompt BLOCKED: nearest=" + str(reached) + " prompt='" + prompt + "'")

	# Negative control: real geometry between the eye and the point still
	# refuses the prompt (the standoff must not become a see-through wall).
	_add_box(host, Vector3(0.0, 1.0, 0.55), Vector3(1.2, 2.0, 0.2))
	await physics_frame
	var blocked: Node = thief.call("get_nearest_interactable")
	var blocked_prompt: String = str(thief.call("get_look_interact_prompt"))
	_check(blocked == null and blocked_prompt == "",
		"a wall 0.63 m in front of the wardrobe point still blocks the prompt",
		"wall between player and wardrobe did NOT block: nearest=" + str(blocked) + " prompt='" + blocked_prompt + "'")

	# The global interaction range is untouched by this wave.
	var range_m: float = float((thief_script.get_script_constant_map() as Dictionary).get("INTERACT_RANGE", -1.0))
	_check(is_equal_approx(range_m, 1.75),
		"INTERACT_RANGE stays the authored 1.75 m (only the LOS standoff changed)",
		"INTERACT_RANGE changed to " + str(range_m))

	thief.queue_free()
	host.queue_free()
	await process_frame


## Step-up must not fire on a walkable ramp: a horizontal capsule sweep reports
## a blocked collision on a 35 deg ramp (normal.y 0.82), and an unguarded lift
## fired every frame — a ramp became an elevator. 35 deg matches the civic
## flight's slope so the ramp and the stairs differ only in continuity.
func _check_ramp_not_stepped(thief_script: GDScript) -> void:
	var base := Vector3(9400.0, 0.0, 9400.0)
	var host := Node3D.new()
	host.name = "W5ARampRig"
	host.global_position = base
	root.add_child(host)
	var ramp := StaticBody3D.new()
	ramp.collision_layer = 1
	ramp.collision_mask = 0
	ramp.rotation = Vector3(deg_to_rad(35.0), 0.0, 0.0)
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(6.0, 0.2, 10.0)
	rcs.shape = rbox
	ramp.add_child(rcs)
	host.add_child(ramp)
	# Ramp top surface passes through the host origin side at +z; the walker
	# starts halfway up and holds forward toward the high end (-z).
	ramp.position = Vector3(0.0, 1.5, 0.0)
	var thief: CharacterBody3D = thief_script.new() as CharacterBody3D
	thief.name = "W5ARampThief"
	thief.set_physics_process(false)
	host.add_child(thief)
	await process_frame
	thief.rotation = Vector3.ZERO
	thief.global_position = base + Vector3(0.0, 0.6, 2.0)
	thief.set_physics_process(true)
	await physics_frame
	var start_y: float = (thief as Node3D).global_position.y
	var prev_y: float = start_y
	var max_frame_rise: float = 0.0
	var max_step_rise: float = 0.0
	Input.action_press("move_forward")
	for _i: int in range(60):
		await physics_frame
		var y: float = (thief as Node3D).global_position.y
		max_frame_rise = maxf(max_frame_rise, y - prev_y)
		max_step_rise = maxf(max_step_rise, float(thief.get("_step_rise_this_frame")))
		prev_y = y
	Input.action_release("move_forward")
	var ascent: float = prev_y - start_y
	# A walked 35 deg ramp over 60 frames at 3.6 m/s rises ~2.5 m; a step-up
	# elevator rose ~0.35 m per frame (max_frame_rise >= 0.3). Both directions
	# matter: the ramp must still be walked up, just not lifted.
	var ok: bool = max_frame_rise < 0.12 and ascent > 1.5 and max_step_rise <= 0.0
	_check(ok,
		"35 deg ramp is walked, not stepped (ascent=%.2f m over 60 frames, max frame rise=%.3f m, step-up rise=%.3f m)" % [ascent, max_frame_rise, max_step_rise],
		"35 deg ramp STEPPED or blocked (max frame rise=%.3f m, ascent=%.2f m, step-up rise=%.3f m): the step-up fired on a walkable slope or the ramp stopped being walkable" % [max_frame_rise, ascent, max_step_rise])
	thief.queue_free()
	host.queue_free()
	await process_frame


## Top-most walkable surface under (x, z), or NAN when the ray misses.
func _floor_height_at(from: Vector3, floor_y: float) -> float:
	var w3d: World3D = root.world_3d
	if w3d == null:
		return NAN
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, Vector3(from.x, floor_y, from.z), 1)
	var hit: Dictionary = w3d.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


func _add_box(parent: Node, at: Vector3, sz: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = sz
	cs.shape = box
	body.add_child(cs)
	parent.add_child(body)
	body.position = at
	return body
