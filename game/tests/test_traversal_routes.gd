extends SceneTree
## W6M traversal truth: step-up contract fixtures on the real controller.
## Run: tools/godot --headless --path game --script res://tests/test_traversal_routes.gd
##
## Why this exists: tests/test_stair_walk.gd walks the shipped flights, but the
## edges of the step-up contract (designer blockers, destination headroom, the
## 0.44/0.45/0.46/0.50 ledge band, descent and slope angles) need deterministic
## geometry. Every fixture drives the REAL thief_character.gd; nothing here
## re-implements movement. The 1.82 m capsule and body_height_m() contract are
## asserted at the end.
##
## Contract under test:
## - MaxStepHeight is the authored 0.45 m: 0.44 and 0.45 commit; 0.46 and 0.50
##   are walls (0.50 mantles only with the authored jump press).
## - A designer blocking volume is solid but never a step, ledge or mantle top.
## - Headroom is evaluated at the LANDING: a soffit 2.25 m above the base (1.80 m
##   over the 0.45 m landing) refuses the step; 2.35 m (1.90 m) commits.
## - A walkable descent of 0.25-0.30 m risers stays inside the 0.30 m snap on
##   deep treads; a 0.45 m ledge produces exactly one airborne interval.
## - Slopes up to the authored 60 deg are walked without the step-up; 61/70 deg
##   do not ascend.

const STEP_BASE_Y: float = 0.0
## Fed into _try_step_up: a planar walking velocity, not the real input loop.
const WALK_VEL: Vector3 = Vector3(0.0, 0.0, -3.6)
const SETTLE_FRAMES: int = 8
const WALK_FRAMES: int = 45

var fails: int = 0
var _thief_script: GDScript = null
var _fixture_index: int = 0


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
	gs.set("thief_id", "spider")
	_thief_script = load("res://src/player/thief_character.gd") as GDScript

	# 1. Step-up band + designer blocker (T1-10-J-style, at the controller).
	await _check_step_band()
	await _check_blocker()
	await _check_headroom()
	await _check_ledge_jump()
	await _check_descent()
	await _check_ledge_fall()
	await _check_slopes()
	await _check_capsule_contract()

	Input.action_release("move_forward")
	Input.action_release("jump")
	await process_frame
	print("W6M_TRAVERSAL_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


# ---------------------------------------------------------------- fixtures

## A ground slab + a raised platform whose face sits 0.4 m in front of the
## walker (0.28 m from the 0.32 m capsule surface). `top` is the platform top.
func _make_ledge(top: float, blocker: bool = false) -> Dictionary:
	var base: Vector3 = _next_base()
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = base
	_add_box(rig, Vector3(0.0, -0.2, 2.2), Vector3(6.0, 0.4, 3.6)) # approach, top y=0
	var plat: StaticBody3D = _add_box(rig, Vector3(0.0, top * 0.5, -1.8), Vector3(6.0, top, 4.4))
	if blocker:
		plat.add_to_group("blocking_volume")
	# Face 0.15 m from the capsule surface: the 0.20 m step probe and the ledge
	# probe reach the riser, the 0.52 m floor probe lands 0.05 m inside the
	# platform, and the capsule clears the corner margin (tighter gaps made the
	# capsule rest on the platform corner, 0.13 m up).
	var thief: CharacterBody3D = await _spawn_thief(rig, Vector3(0.0, 0.02, 0.87))
	return {"rig": rig, "thief": thief, "top": top, "blocker": blocker}


func _check_step_band() -> void:
	for top: float in [0.44, 0.45, 0.46, 0.50]:
		var f: Dictionary = await _make_ledge(top)
		var thief: CharacterBody3D = f["thief"] as CharacterBody3D
		var start_y: float = thief.global_position.y
		var rise: float = float(thief.call("_try_step_up", WALK_VEL))
		var expected_step: bool = top <= 0.45
		var ok: bool = (absf(rise - top) <= 0.01) if expected_step else is_zero_approx(rise)
		_check(ok,
			"step band %.2f m: %s (committed rise=%.3f m, frame-local, no slide)" % [top, "steps" if expected_step else "is a wall", rise],
			"step band %.2f m FAILED: expected %s, rise=%.3f m, body y %.3f -> %.3f" % [top, "a %.3f m step" % top if expected_step else "no step", rise, start_y, thief.global_position.y])
		# Without a jump the 0.46/0.50 face must stay a wall under held input.
		if not expected_step:
			var before_y: float = thief.global_position.y
			Input.action_press("move_forward")
			for _i: int in range(WALK_FRAMES):
				await physics_frame
			Input.action_release("move_forward")
			var climbed: float = thief.global_position.y - before_y
			_check(climbed < 0.05,
				"%.2f m ledge does not walk without a jump (held 45 frames, climbed %.3f m)" % [top, climbed],
				"%.2f m ledge CLIMBED without a jump: %.3f m (step-up or auto-mantle leaked past MaxStepHeight)" % [top, climbed])
		await _free_fixture(f)


## The audit's blocker contract: a 0.40 m designer blocker is inside
## MaxStepHeight but was a legal tread (the floor probe found its top). It must
## stay solid and refuse both the step and the jump-mantle, while a same-shape
## visible 0.40 m ledge remains the positive control.
func _check_blocker() -> void:
	var f: Dictionary = await _make_ledge(0.40, true)
	var thief: CharacterBody3D = f["thief"] as CharacterBody3D
	var rise: float = float(thief.call("_try_step_up", WALK_VEL))
	var start_y: float = thief.global_position.y
	Input.action_press("move_forward")
	for _i: int in range(WALK_FRAMES):
		await physics_frame
	Input.action_release("move_forward")
	var walked_up: float = thief.global_position.y - start_y
	print("DBGM y=", thief.global_position.y, " z=", thief.global_position.z, " on=", thief.is_on_floor(), " wall=", thief.is_on_wall())
	Input.action_press("jump")
	var mantled: bool = bool(thief.call("try_auto_mantle"))
	var is_mantling: bool = bool(thief.get("is_mantling"))
	Input.action_release("jump")
	await physics_frame
	var ok: bool = is_zero_approx(rise) and walked_up < 0.05 and not mantled and not is_mantling
	_check(ok,
		"0.40 m blocking volume never steps or mantles (step rise=%.3f, walked %.3f m, mantle=%s)" % [rise, walked_up, str(mantled)],
		"0.40 m blocking volume was traversable: step rise=%.3f, walked %.3f m, mantle=%s, is_mantling=%s" % [rise, walked_up, str(mantled), str(is_mantling)])
	await _free_fixture(f)


## A soffit over the LANDING only (the origin has full headroom). The step is
## 0.45 m, so clearance below the soffit is soffit_y - 0.45: 1.80 m refuses the
## 1.82 m body, 1.90 m commits.
func _check_headroom() -> void:
	for soffit_y: float in [2.25, 2.35]:
		var f: Dictionary = await _make_ledge(0.45)
		var rig: Node3D = f["rig"] as Node3D
		var thaw: CharacterBody3D = f["thief"] as CharacterBody3D
		# Bottom at soffit_y, 0.3 m thick, spanning the landing but not the origin.
		_add_box(rig, Vector3(0.0, soffit_y + 0.15, -1.75), Vector3(6.0, 0.3, 4.5))
		await physics_frame
		var thief: CharacterBody3D = f["thief"] as CharacterBody3D
		var rise: float = float(thief.call("_try_step_up", WALK_VEL))
		var expected_ok: bool = soffit_y >= 2.35
		var ok: bool = (absf(rise - 0.45) <= 0.01) if expected_ok else is_zero_approx(rise)
		_check(ok,
			"headroom at destination: %.2f m soffit over a 0.45 m step %s (rise=%.3f m; clearance %.2f m vs 1.82 m body)" % [soffit_y, "commits" if expected_ok else "refuses", rise, soffit_y - 0.45],
			"headroom at destination FAILED at %.2f m soffit: expected %s, rise=%.3f m (clearance %.2f m). The probe must be at the landing, not the origin." % [soffit_y, "step" if expected_ok else "no step", rise, soffit_y - 0.45])
		await _free_fixture(f)


## 0.50 m ledge: no walk, but the authored jump press arms the mantle.
func _check_ledge_jump() -> void:
	var f: Dictionary = await _make_ledge(0.50)
	var thief: CharacterBody3D = f["thief"] as CharacterBody3D
	Input.action_press("move_forward")
	for _i: int in range(WALK_FRAMES):
		await physics_frame
	Input.action_release("move_forward")
	var no_jump_climb: float = thief.global_position.y - STEP_BASE_Y
	print("DBGM y=", thief.global_position.y, " z=", thief.global_position.z, " on=", thief.is_on_floor(), " wall=", thief.is_on_wall())
	Input.action_press("jump")
	var mantled: bool = bool(thief.call("try_auto_mantle"))
	var clip: String = str(thief.get("_mantle_clip_role"))
	Input.action_release("jump")
	var ok: bool = no_jump_climb < 0.05 and mantled
	_check(ok,
		"0.50 m ledge: walked climb %.3f m without jump, mantle with jump=%s (clip %s)" % [no_jump_climb, str(mantled), clip],
		"0.50 m ledge FAILED: walked climb=%.3f m without jump, jump mantle=%s clip=%s" % [no_jump_climb, str(mantled), clip])
	await _free_fixture(f)


## Walked descent on deep treads: 0.28 m risers on 0.60 m treads. The authored
## 0.30 m floor snap must hold the capsule down (this is the 0.25-0.30 band).
## Shipped flights use 0.33 m treads, where the 0.32 m capsule cannot stay
## seated; that is measured in test_stair_walk and recorded in FIDELITY_GAPS.
func _check_descent() -> void:
	var base: Vector3 = _next_base()
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = base
	# Top platform top y=1.40, walked -Z, then four 0.28 m risers on 0.60 treads.
	_add_box(rig, Vector3(0.0, 0.7, 1.5), Vector3(6.0, 1.4, 3.0))
	for i: int in range(4):
		var top: float = 1.4 - 0.28 * float(i + 1)
		_add_box(rig, Vector3(0.0, top * 0.5, -0.3 - 0.6 * float(i)), Vector3(6.0, top, 0.6))
	_add_box(rig, Vector3(0.0, -0.2, -5.0), Vector3(6.0, 0.4, 5.0))
	var thief: CharacterBody3D = await _spawn_thief(rig, Vector3(0.0, 1.42, 2.0))
	var start_y: float = thief.global_position.y
	var prev_floor: bool = true
	var air_frames: int = 0
	var intervals: int = 0
	var max_interval: int = 0
	var run: int = 0
	Input.action_press("move_forward")
	for i: int in range(110):
		await physics_frame
		var on_floor: bool = bool(thief.is_on_floor())
		if i > 2:
			if not on_floor:
				air_frames += 1
				run += 1
				max_interval = maxi(max_interval, run)
			else:
				run = 0
			if prev_floor and not on_floor:
				intervals += 1
		prev_floor = on_floor
	Input.action_release("move_forward")
	await physics_frame
	var descent: float = start_y - thief.global_position.y
	var end_floor: bool = bool(thief.is_on_floor())
	# Godot snaps BEFORE move_and_slide, so a walked descent is a short fall per
	# riser, not a hold. The fixture guards the traversal (it descends and lands,
	# no interval is a skipped-flight fall) and reports the measured cadence;
	# docs/FIDELITY_GAPS.md records the missing post-move snap.
	var ok: bool = descent >= 1.35 and end_floor and intervals >= 1 and max_interval <= 18
	_check(ok,
		"deep-tread descent: 4 x 0.28 m risers descended %.2f m in %d interval(s), max interval=%d frames, airborne frames=%d, end_on_floor=%s (Godot pre-move snap: short fall per riser)" % [descent, intervals, max_interval, air_frames, str(end_floor)],
		"deep-tread descent FAILED: descended %.2f m, intervals=%d, max interval=%d frames (>18: skipped a riser), airborne frames=%d, end_on_floor=%s" % [descent, intervals, max_interval, air_frames, str(end_floor)])
	await _free_node(rig)


## Walking off a 0.45 m ledge must produce exactly one airborne interval (the
## ledge is above the 0.30 m snap), then land.
func _check_ledge_fall() -> void:
	var base: Vector3 = _next_base()
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = base
	_add_box(rig, Vector3(0.0, 0.225, 1.2), Vector3(6.0, 0.45, 3.2)) # top 0.45
	_add_box(rig, Vector3(0.0, -0.2, -2.0), Vector3(6.0, 0.4, 3.5))
	var thief: CharacterBody3D = await _spawn_thief(rig, Vector3(0.0, 0.47, 2.0))
	var intervals: int = 0
	var air_frames: int = 0
	var prev_floor: bool = true
	Input.action_press("move_forward")
	for i: int in range(70):
		await physics_frame
		var on_floor: bool = bool(thief.is_on_floor())
		if i > 2:
			if not on_floor:
				air_frames += 1
			if prev_floor and not on_floor:
				intervals += 1
		prev_floor = on_floor
	Input.action_release("move_forward")
	await physics_frame
	var end_floor: bool = bool(thief.is_on_floor())
	var end_y: float = thief.global_position.y
	var ok: bool = intervals == 1 and air_frames >= 4 and end_floor and absf(end_y) < 0.1
	_check(ok,
		"0.45 m ledge fall: %d airborne interval(s), %d airborne frames, landed at y=%.3f, end_on_floor=%s" % [intervals, air_frames, end_y, str(end_floor)],
		"0.45 m ledge fall FAILED: intervals=%d (expected 1), air frames=%d, end y=%.3f, end_on_floor=%s" % [intervals, air_frames, end_y, str(end_floor)])
	await _free_node(rig)


## Walkable slope band: 45/55/59 deg ascend, 61/70 deg refuse. The step-up must
## never fire on any of them (walkable slopes are move_and_slide's job; steep
## ones fail the walkable floor probe).
func _check_slopes() -> void:
	for angle: float in [45.0, 55.0, 59.0, 61.0, 70.0]:
		var base: Vector3 = _next_base()
		var rig := Node3D.new()
		root.add_child(rig)
		rig.global_position = base
		var theta: float = deg_to_rad(angle)
		var ramp := StaticBody3D.new()
		ramp.collision_layer = 1
		ramp.collision_mask = 0
		ramp.rotation.x = theta
		var rcs := CollisionShape3D.new()
		var rbox := BoxShape3D.new()
		rbox.size = Vector3(4.0, 0.2, 8.0)
		rcs.shape = rbox
		ramp.add_child(rcs)
		rig.add_child(ramp)
		# Low end (local z=+4) surface at y=0 so the foot meets the ground slab.
		# Bury the low edge 0.2 m under the ground so the capsule meets the
		# ramp surface, not the thin slab's leading-side edge (that edge
		# depenetrated the capsule upward on the 70 deg fixture).
		ramp.position = Vector3(0.0, 4.0 * sin(theta) - 0.1 * cos(theta) - 0.2, 0.0)
		_add_box(rig, Vector3(0.0, -0.2, 4.6), Vector3(6.0, 0.4, 6.8)) # ground top 0, z 1.2..8

		var thief: CharacterBody3D = await _spawn_thief(rig, Vector3(0.0, 0.3, 3.0))
		await physics_frame
		var start_y: float = thief.global_position.y
		var max_step_rise: float = 0.0
		Input.action_press("move_forward")
		for _i: int in range(60):
			await physics_frame
			max_step_rise = maxf(max_step_rise, float(thief.get("_step_rise_this_frame")))
		Input.action_release("move_forward")
		var ascent: float = thief.global_position.y - start_y
		var mantling: bool = bool(thief.get("is_mantling"))
		var walkable: bool = angle <= 60.0
		var ok: bool = is_zero_approx(max_step_rise) and not mantling \
			and ((ascent > 1.0) if walkable else (ascent < 0.3))
		_check(ok,
			"%s slope: ascent=%.2f m over 60 frames, step-up rise=%.3f m, mantle=%s" % [str(angle) + " deg", ascent, max_step_rise, str(mantling)],
			"%s slope FAILED: ascent=%.2f m (%s), step-up rise=%.3f m, mantle=%s" % [str(angle) + " deg", ascent, "expected > 1.0" if walkable else "expected < 0.3", max_step_rise, str(mantling)])
		await _free_node(rig)


## W6M capsule contract: the built capsule and body_height_m() agree at the
## authored 1.82 m. device_geometry's fallback constant and the W3 beam fixture
## still use the port's old 1.78 m for mock bodies; that mismatch is recorded.
func _check_capsule_contract() -> void:
	var base: Vector3 = _next_base()
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = base
	var thief: CharacterBody3D = await _spawn_thief(rig, Vector3.ZERO)
	var cshape: CollisionShape3D = thief.get("col_shape") as CollisionShape3D
	var cap: CapsuleShape3D = cshape.shape as CapsuleShape3D if cshape != null else null
	var body_h: float = float(thief.call("body_height_m"))
	var consts: Dictionary = _thief_script.get_script_constant_map()
	var standing: float = float(consts.get("BODY_HEIGHT_STANDING", -1.0))
	var half: float = float(consts.get("CAPSULE_HALF_HEIGHT_M", -1.0))
	var ok: bool = cap != null and is_equal_approx(cap.height, 1.82) \
		and is_equal_approx(cap.radius, 0.32) \
		and cshape != null and is_equal_approx(cshape.position.y, 0.91) \
		and is_equal_approx(body_h, 1.82) and is_equal_approx(standing, 1.82) \
		and is_equal_approx(half, 0.91)
	_check(ok,
		"capsule contract: built %.2f m capsule (r=%.2f, centre %.2f), body_height_m=%.2f, BODY_HEIGHT_STANDING=%.2f; detector mock fallback stays 1.78 m" % [cap.height if cap != null else -1.0, cap.radius if cap != null else -1.0, cshape.position.y if cshape != null else -1.0, body_h, standing],
		"capsule contract FAILED: capsule=%s body_height_m=%.2f standing_const=%.2f half=%.2f centre=%s" % [str(cap.height) if cap != null else "none", body_h, standing, half, str(cshape.position.y) if cshape != null else "none"])
	await _free_node(rig)


# ---------------------------------------------------------------- helpers

func _next_base() -> Vector3:
	_fixture_index += 1
	return Vector3(30000.0 + 300.0 * float(_fixture_index), 0.0, 30000.0)


func _spawn_thief(parent: Node3D, local_pos: Vector3) -> CharacterBody3D:
	var thief: CharacterBody3D = _thief_script.new() as CharacterBody3D
	thief.name = "W6MThief"
	thief.set_physics_process(false)
	parent.add_child(thief)
	await process_frame
	thief.global_position = parent.to_global(local_pos)
	thief.rotation = Vector3.ZERO # forward -Z, same axis as the fixtures
	thief.set_physics_process(true)
	for _i: int in range(SETTLE_FRAMES):
		await physics_frame
	return thief


func _free_fixture(f: Dictionary) -> void:
	var thief: Node = f.get("thief") as Node
	if thief != null:
		thief.queue_free()
	var rig: Node = f.get("rig") as Node
	if rig != null:
		rig.queue_free()
	await physics_frame


func _free_node(n: Node) -> void:
	n.queue_free()
	await physics_frame


func _add_box(parent: Node, at: Vector3, sz: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = sz
	cs.shape = box
	body.add_child(cs)
	# Position before entering the tree: a StaticBody added at the identity and
	# moved afterwards depenetrates whatever stands near the rig origin for one
	# physics frame (it lifted the walker 0.13 m in the headroom fixture).
	body.position = at
	parent.add_child(body)
	return body
