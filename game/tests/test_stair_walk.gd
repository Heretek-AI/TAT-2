extends SceneTree
## W5A: authored stair traversal (real level colliders) + Den wardrobe prompt.
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
## The walk is driven by the real input action (move_forward) through the real
## _physics_process, one physics frame per step, exactly like play.

const FLIGHTS: Array[Dictionary] = [
	{"label": "civic", "path": "/Game/Art/Environment/Civic/Stairs/SM_Stairs_Civic_3x150cm"},
	{"label": "industrial", "path": "/Game/Art/Environment/Urban/Industrial/Stairs/SM_Stairs_Industrial_3x150cm"},
	{"label": "city", "path": "/Game/Art/Environment/City/Architecture/Stairs/2m/SM_StairsCity6x2m"},
]
const WALK_FRAMES: int = 180
const MIN_ASCENT_M: float = 1.4
const MAX_ZERO_PROGRESS_FRAMES: int = 2
const MAX_LATERAL_DRIFT_M: float = 0.15
## A frame counts as progress when the body advanced along the flight (-z) or
## rose. A sub-millimetre frame is noise, not progress.
const PROGRESS_EPS_M: float = 0.0005

var fails: int = 0
var _ld: Node = null


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

	await _check_wardrobe_prompt(thief_script)
	await _check_ramp_not_stepped(thief_script)
	Input.action_release("move_forward")
	await process_frame
	_ld.queue_free()
	await process_frame
	print("W5A_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


## Build the real collider, place a run-up slab and a top landing, then walk
## forward for WALK_FRAMES physics frames and report the measured metrics.
func _walk_flight(thief_script: GDScript, flight: Dictionary) -> Dictionary:
	var path: String = str(flight.get("path", ""))
	var out: Dictionary = {"label": str(flight.get("label", "?")), "ok": false}
	var info: Dictionary = _ld.call("_get_mesh_and_shape", path) as Dictionary
	var shape: Shape3D = info.get("shape") as Shape3D
	if not (shape is ConcavePolygonShape3D):
		out["error"] = "no trimesh collider for " + path
		return out
	var faces: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v: Vector3 in faces:
		lo = lo.min(v)
		hi = hi.max(v)
	# Authored flight: rises along -z from a low end near z = hi.z to a top near
	# z = lo.z, so the walker starts on the +z side and holds move_forward.
	var mid_x: float = (lo.x + hi.x) * 0.5
	var width: float = maxf(hi.x - lo.x, 1.0)
	var rig := Node3D.new()
	rig.name = "StairRig_" + str(flight.get("label", "?"))
	root.add_child(rig)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	rig.add_child(body)

	# Approach floor (top at y = 0, the flights' authored base) and the landing
	# at the flight's measured top tread so the 180 frames of held input never
	# fall off an edge. The mesh AABB max-y can be a handrail (industrial
	# 1.675 vs a 1.58 tread), so the landing height comes from a ray, not hi.y.
	var top_y: float = _floor_height_at(Vector3(mid_x, hi.y + 0.5, lo.z + 0.15), lo.y - 0.5)
	if is_nan(top_y):
		top_y = hi.y
	var ground_sz := Vector3(width + 2.0, 0.4, 2.2)
	_add_box(rig, Vector3(mid_x, -0.2, hi.z + 1.0), ground_sz)
	var landing_sz := Vector3(width + 2.0, 0.4, 2.0)
	_add_box(rig, Vector3(mid_x, top_y - 0.2, lo.z - 0.95), landing_sz)
	# Backstop at the far end of the landing: keeps the final height honest
	# once the climb is done (the streak metric stops at MIN_ASCENT_M). Tall
	# enough (top > 4 m of mantle reach) that the seam cannot mantle it.
	_add_box(rig, Vector3(mid_x, top_y + 3.0, lo.z - 2.0), Vector3(width + 2.0, 8.0, 0.2))

	var thief: CharacterBody3D = thief_script.new() as CharacterBody3D
	thief.name = "StairWalker_" + str(flight.get("label", "?"))
	thief.set_physics_process(false)
	rig.add_child(thief)
	await process_frame
	thief.rotation = Vector3.ZERO # forward is -Z, the flight's rise direction
	thief.global_position = Vector3(mid_x, 0.02, hi.z + 0.7)
	thief.set_physics_process(true)
	await physics_frame

	var start_y: float = (thief as Node3D).global_position.y
	var start_x: float = (thief as Node3D).global_position.x
	var prev_z: float = (thief as Node3D).global_position.z
	var prev_y: float = start_y
	var zero_streak: int = 0
	var max_zero_streak: int = 0
	var max_drift: float = 0.0
	var mantled: bool = false
	var frames_to_target: int = -1
	var zero_frames_total: int = 0
	var climbs: int = 0
	var max_cam_offset: float = 0.0
	var cam_node: Camera3D = thief.get("cam") as Camera3D
	var eye_rest_y: float = float(thief_script.get_script_constant_map().get("STAND_HEAD_HEIGHT", 1.66875))
	Input.action_press("move_forward")
	for i: int in range(WALK_FRAMES):
		await physics_frame
		var pos: Vector3 = (thief as Node3D).global_position
		var rose: float = pos.y - prev_y
		# Camera-rise smoothing must never compound: the eye may lag the body by
		# at most the 0.20 m smoothing cap, never sink the view.
		if cam_node != null:
			max_cam_offset = maxf(max_cam_offset, absf((cam_node.global_position.y - pos.y) - eye_rest_y))
		if bool(thief.get("is_mantling")):
			mantled = true
			print("W5A: unexpected auto-mantle at frame ", i, " pos=", pos)
		max_drift = maxf(max_drift, absf(pos.x - start_x))
		var advanced: bool = (prev_z - pos.z) > PROGRESS_EPS_M or rose > PROGRESS_EPS_M
		if pos.y - start_y >= MIN_ASCENT_M and frames_to_target < 0:
			frames_to_target = i + 1
		if frames_to_target < 0:
			# Streak is measured over the climb: after the ascent target the
			# walker is against the landing backstop by design.
			if advanced:
				zero_streak = 0
			else:
				zero_streak += 1
				zero_frames_total += 1
				max_zero_streak = maxi(max_zero_streak, zero_streak)
		if rose > 0.02:
			climbs += 1
		prev_z = pos.z
		prev_y = pos.y
	Input.action_release("move_forward")
	var end_pos: Vector3 = (thief as Node3D).global_position
	out["ok"] = true
	out["ascent_m"] = end_pos.y - start_y
	out["frames_to_target"] = frames_to_target
	out["max_zero_streak"] = max_zero_streak
	out["zero_frames_total"] = zero_frames_total
	out["max_drift_m"] = max_drift
	out["mantled"] = mantled
	out["step_frames"] = climbs
	out["max_cam_offset_m"] = max_cam_offset
	out["rise_m"] = top_y
	out["run_m"] = hi.z - lo.z
	out["end"] = end_pos
	thief.queue_free()
	rig.queue_free()
	await physics_frame
	return out


func _check_walk(flight: Dictionary, res: Dictionary) -> void:
	var label: String = str(flight.get("label", "?"))
	if not bool(res.get("ok", false)):
		printerr("FAIL: ", label, " stair fixture: ", str(res.get("error", "unknown")))
		fails += 1
		return
	var ascent: float = float(res["ascent_m"])
	var ok: bool = ascent >= MIN_ASCENT_M \
		and int(res["max_zero_streak"]) <= MAX_ZERO_PROGRESS_FRAMES \
		and not bool(res["mantled"]) \
		and float(res["max_drift_m"]) < MAX_LATERAL_DRIFT_M \
		and float(res["max_cam_offset_m"]) <= 0.25
	_check(ok,
		"%s stair walk: ascent=%.2f m (authored flight %.2f m over %.2f m run), target in %d frames, max zero-progress streak=%d, step frames=%d, lateral drift=%.3f m, camera lag=%.3f m, mantle=%s" % [
			label, ascent, float(res["rise_m"]), float(res["run_m"]), int(res["frames_to_target"]),
			int(res["max_zero_streak"]), int(res["step_frames"]), float(res["max_drift_m"]),
			float(res["max_cam_offset_m"]), str(res["mantled"])],
		"%s stair walk FAILED: ascent=%.2f m (< %.2f), max zero-progress streak=%d (> %d), lateral drift=%.3f m (>= %.2f), camera lag=%.3f m (> 0.25), mantled=%s, frames_to_target=%d, end=%s" % [
			label, ascent, MIN_ASCENT_M, int(res["max_zero_streak"]), MAX_ZERO_PROGRESS_FRAMES,
			float(res["max_drift_m"]), MAX_LATERAL_DRIFT_M, str(res["mantled"]),
			int(res["frames_to_target"]), str(res["end"])])


## Den wardrobe regression: the authored interaction point sits 0.48 m behind
## the cabinet's front face (mission_controller DenWardrobeArea:
## position + UP*1.2). The old LOS endpoint was capped at half the player
## distance, so a close player's ray ended inside the cabinet and the prompt
## never resolved. The fixture reproduces that geometry from the front.
func _check_wardrobe_prompt(thief_script: GDScript) -> void:
	var base := Vector3(9000.0, 0.0, 9000.0)
	var host := Node3D.new()
	host.name = "WardrobePromptRig"
	root.add_child(host)
	# Cabinet body: 0.6 m deep, front face at z = +0.7 relative to base.
	_add_box(host, base + Vector3(0.0, 1.0, 1.0), Vector3(1.2, 2.0, 0.6))
	# Interactable Area, exactly like the Den fill: floor position + UP*1.2.
	var area := Area3D.new()
	area.name = "W5AWardrobeArea"
	area.position = base + Vector3(0.0, 0.0, 1.0)
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
	_add_box(host, base + Vector3(0.0, 1.0, 0.55), Vector3(1.2, 2.0, 0.2))
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
	ramp.position = base + Vector3(0.0, 1.5, 0.0)
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
	Input.action_press("move_forward")
	for _i: int in range(60):
		await physics_frame
		var y: float = (thief as Node3D).global_position.y
		max_frame_rise = maxf(max_frame_rise, y - prev_y)
		prev_y = y
	Input.action_release("move_forward")
	var ascent: float = prev_y - start_y
	# A walked 35 deg ramp over 60 frames at 3.6 m/s rises ~2.5 m; a step-up
	# elevator rose ~0.35 m per frame (max_frame_rise >= 0.3). Both directions
	# matter: the ramp must still be walked up, just not lifted.
	var ok: bool = max_frame_rise < 0.12 and ascent > 1.5
	_check(ok,
		"35 deg ramp is walked, not stepped (ascent=%.2f m over 60 frames, max frame rise=%.3f m)" % [ascent, max_frame_rise],
		"35 deg ramp STEPPED or blocked (max frame rise=%.3f m, ascent=%.2f m): the step-up fired on a walkable slope or the ramp stopped being walkable" % [max_frame_rise, ascent])
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
	body.global_position = at
	return body
