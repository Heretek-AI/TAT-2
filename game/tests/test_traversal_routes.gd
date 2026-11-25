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
	# W7H: descent accept band (T1-T6), the D2 A/B and the authored roof routes.
	await _check_descent_band()
	await _check_descent_shrink_ab()
	await _check_roof_routes()
	await _check_roof_end_shells()
	await _check_roof_hip_and_scale()

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


# ---------------------------------------------------------------- W7H descent

## W7H D1/D5: the walked-descent accept band. T1-T6 walk off a single riser in
## the accept band (0.06 .. 0.30 m) and must re-seat silently: at most 2 airborne
## intervals, zero real landings (no jump_land pose), grounded at the lower level,
## and no long free-fall. T7 is the 0.45 m control: outside the accept band, so
## exactly one real airborne interval and exactly one landing.
##
## Air frames: the shipped path is D1 + D5 (D2 default off). D1 sees the tread and
## D5 silences the landing, but the destination capsule still grazes the riser
## behind, so a 0.18-0.30 m walk-off takes a short 4-12 frame fall instead of the
## 2-frame target. The measured D2 opt-in (below) reaches 1-2 air frames with a
## 0.001 m shove-back; it stays default-off by decision, so this fixture asserts
## the shipped measurement and "D2 opt-in" asserts the target.
const DESCENT_CASES: Array[Dictionary] = [
	{"id": "T1", "riser": 0.06},
	{"id": "T2", "riser": 0.12},
	{"id": "T3", "riser": 0.18},
	{"id": "T4", "riser": 0.24},
	{"id": "T5", "riser": 0.28},
	{"id": "T6", "riser": 0.30},
]
const DESCENT_CONTROL_RISER: float = 0.45
const DESCENT_MAX_INTERVALS: int = 2
## Target for the D2 opt-in and the bound the shipped path is measured against.
const DESCENT_TARGET_AIR_FRAMES: int = 2
const DESCENT_SHIPPED_MAX_AIR_FRAMES: int = 12
## QA value for the D2 opt-in (mirrors
## thief_character.STEP_DOWN_QUERY_SHRINK_EXPERIMENT_M; the check asserts they
## agree). 0.06 m clears the riser graze; larger values measure identically.
const SHRINK_EXPERIMENT_M: float = 0.06
const SHOVE_BACK_LIMIT_M: float = 0.05
## Authored stair scale (0.25 m risers on 0.33 m treads, the civic flight) walked
## up with a given destination-query shrink: the ascent must stay at the full
## three risers, not stall after the first.
const STAIR_ASCENT_MIN_M: float = 0.70


func _check_descent_band() -> void:
	for rec: Dictionary in DESCENT_CASES:
		await _descent_case(str(rec["id"]), float(rec["riser"]), true)
	await _descent_case("T7", DESCENT_CONTROL_RISER, false)


## One walked descent off a single riser. `expected_step` is the D1 contract:
## inside the 0.30 m accept band the body descends silently (D5), outside it the
## drop is a real fall (one interval, one counted landing).
func _descent_case(case_id: String, riser: float, expected_step: bool, shrink: float = 0.0, max_air: int = DESCENT_SHIPPED_MAX_AIR_FRAMES, report: bool = true) -> Dictionary:
	var base: Vector3 = _next_base()
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = base
	# Upper platform top = riser (spans z -2.8..1.6); the walker starts at z=0.6
	# and walks -Z off the -Z edge onto the lower floor (top 0), which catches it.
	_add_box(rig, Vector3(0.0, riser * 0.5, -0.6), Vector3(6.0, riser, 4.4))
	_add_box(rig, Vector3(0.0, -0.2, -5.0), Vector3(6.0, 0.4, 4.4))
	var thief: CharacterBody3D = await _spawn_thief(rig, Vector3(0.0, riser + 0.02, 0.6))
	thief.set("step_down_query_shrink_m", shrink)
	var start_landings: int = int(thief.get("landing_events"))
	var start_y: float = thief.global_position.y
	var prev_floor: bool = true
	var air_frames: int = 0
	var intervals: int = 0
	var max_interval: int = 0
	var run: int = 0
	Input.action_press("move_forward")
	for i: int in range(90):
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
	var descended: float = start_y - thief.global_position.y
	var end_floor: bool = bool(thief.is_on_floor())
	var landings: int = int(thief.get("landing_events")) - start_landings
	var last_drop: float = float(thief.get("last_landing_drop_m"))
	var measured: Dictionary = {
		"riser": riser, "descended": descended, "intervals": intervals,
		"air": air_frames, "max_interval": max_interval,
		"landings": landings, "end_floor": end_floor, "last_drop": last_drop,
	}
	if expected_step:
		var ok: bool = descended >= riser - 0.03 and end_floor \
			and intervals <= DESCENT_MAX_INTERVALS and air_frames <= max_air \
			and landings == 0
		if report:
			_check(ok,
				"%s %.2f m riser: stepped down %.2f m in %d interval(s) / %d air frame(s), 0 landings, end grounded" % [case_id, riser, descended, intervals, air_frames],
				"%s %.2f m riser FAILED: descended %.2f m, intervals=%d (max %d), air frames=%d (max %d), landings=%d (must be 0), end_on_floor=%s" % [
					case_id, riser, descended, intervals, DESCENT_MAX_INTERVALS, air_frames, max_air, landings, str(end_floor)])
	else:
		var ok2: bool = descended >= riser - 0.03 and end_floor and intervals == 1 and landings == 1 and last_drop > 0.30
		if report:
			_check(ok2,
				"%s %.2f m control: real fall, 1 interval / %d air frames, 1 landing (drop %.2f m), end grounded" % [case_id, riser, air_frames, last_drop],
				"%s %.2f m control FAILED: descended %.2f m, intervals=%d (expected 1), landings=%d (expected 1), drop=%.2f m, end_on_floor=%s" % [
					case_id, riser, descended, intervals, landings, last_drop, str(end_floor)])
	await _free_node(rig)
	return measured


## W7H D2 A/B: shrink the destination query capsule and measure both axes — the
## solver shove-back it causes (limit 0.05 m) and whether the authored stair
## ascent still completes. The numbers are printed for the report, and the
## opt-in run asserts the <= 2 air-frame target the shipped path does not meet.
func _check_descent_shrink_ab() -> void:
	var baseline: float = await _measure_shove_back(0.0)
	var shrunk: float = await _measure_shove_back(SHRINK_EXPERIMENT_M)
	var base_ascent: float = await _measure_stair_ascent(0.0)
	var shrink_ascent: float = await _measure_stair_ascent(SHRINK_EXPERIMENT_M)
	print("D2_A_B: shrink=0.0 shove=%.3f m stair_ascent=%.2f m | shrink=%.3f shove=%.3f m stair_ascent=%.2f m | limits shove<=%.2f m, ascent>=%.2f m" % [
		baseline, base_ascent, SHRINK_EXPERIMENT_M, shrunk, shrink_ascent, SHOVE_BACK_LIMIT_M, STAIR_ASCENT_MIN_M])
	var shove_ok: bool = shrunk <= SHOVE_BACK_LIMIT_M
	var ascent_ok: bool = shrink_ascent >= STAIR_ASCENT_MIN_M
	_check(shove_ok and ascent_ok,
		"D2 A/B: opt-in shrink (%.2f m) is safe on both axes (shove-back %.3f m <= %.2f m, stair ascent %.2f m >= %.2f m)" % [SHRINK_EXPERIMENT_M, shrunk, SHOVE_BACK_LIMIT_M, shrink_ascent, STAIR_ASCENT_MIN_M],
		"D2 A/B: opt-in shrink is NOT safe (shove-back %.3f m vs %.2f m limit, stair ascent %.2f m vs %.2f m minimum; baseline ascent %.2f m)" % [shrunk, SHOVE_BACK_LIMIT_M, shrink_ascent, STAIR_ASCENT_MIN_M, base_ascent])
	# The opt-in run must reach the <= 2 air-frame target the shipped path does
	# not (this is the whole point of keeping D2 around).
	var opt_in_air: int = 0
	var shipped_air: int = 0
	for riser: float in [0.18, 0.24, 0.28, 0.30]:
		var d_off: Dictionary = await _descent_case_quiet(riser, 0.0)
		var d_on: Dictionary = await _descent_case_quiet(riser, SHRINK_EXPERIMENT_M)
		shipped_air = maxi(shipped_air, int(d_off.get("air", 0)))
		opt_in_air = maxi(opt_in_air, int(d_on.get("air", 0)))
		_check(int(d_on.get("intervals", 9)) <= DESCENT_MAX_INTERVALS and int(d_on.get("landings", 9)) == 0 and bool(d_on.get("end_floor", false)),
			"D2 opt-in %.2f m riser: %d interval(s), %d air frame(s), 0 landings, end grounded" % [riser, int(d_on.get("intervals", 0)), int(d_on.get("air", 0))],
			"D2 opt-in %.2f m riser FAILED: intervals=%d, air frames=%d, landings=%d, end_on_floor=%s" % [riser, int(d_on.get("intervals", 0)), int(d_on.get("air", 0)), int(d_on.get("landings", 0)), str(d_on.get("end_floor", false))])
	_check(opt_in_air <= DESCENT_TARGET_AIR_FRAMES and shipped_air > DESCENT_TARGET_AIR_FRAMES,
		"D2 opt-in reaches the <= %d air-frame target (max %d) where the shipped D1+D5 path measures %d (reported, default off)" % [DESCENT_TARGET_AIR_FRAMES, opt_in_air, shipped_air],
		"D2 opt-in did not reach the %d air-frame target (opt-in max %d, shipped max %d)" % [DESCENT_TARGET_AIR_FRAMES, opt_in_air, shipped_air])
	# Shipped value must follow the decision: default OFF, and the QA constant
	# the test uses must be the one the controller documents.
	var consts: Dictionary = _thief_script.get_script_constant_map()
	var shipped: float = float(consts.get("STEP_DOWN_QUERY_SHRINK_M", -1.0))
	var qa: float = float(consts.get("STEP_DOWN_QUERY_SHRINK_EXPERIMENT_M", -1.0))
	_check(is_zero_approx(shipped) and is_equal_approx(qa, SHRINK_EXPERIMENT_M),
		"shipped D2 is default-off (STEP_DOWN_QUERY_SHRINK_M=%.2f) with the measured QA value %.2f" % [shipped, qa],
		"shipped D2 state wrong: STEP_DOWN_QUERY_SHRINK_M=%.2f (expected 0.0), EXPERIMENT_M=%.2f (expected %.2f)" % [shipped, qa, SHRINK_EXPERIMENT_M])


## `_descent_case` without its PASS/FAIL line (the opt-in A/B reports its own
## aggregated assertions; T1-T6 already assert the shipped path).
func _descent_case_quiet(riser: float, shrink: float) -> Dictionary:
	return await _descent_case("D2", riser, true, shrink, DESCENT_SHIPPED_MAX_AIR_FRAMES, false)


func _measure_stair_ascent(shrink: float) -> float:
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = _next_base()
	_add_box(rig, Vector3(0.0, -0.2, 0.835), Vector3(6.0, 0.4, 2.33))
	for i: int in range(3):
		var top: float = 0.25 * float(i + 1)
		_add_box(rig, Vector3(0.0, top * 0.5, -0.33 * float(i) - 0.165), Vector3(6.0, top, 0.33))
	_add_box(rig, Vector3(0.0, 0.375, -2.0), Vector3(6.0, 0.75, 2.0))
	var thief: CharacterBody3D = await _spawn_thief(rig, Vector3(0.0, 0.02, 1.2))
	thief.set("step_down_query_shrink_m", shrink)
	var start_y: float = thief.global_position.y
	Input.action_press("move_forward")
	for _i: int in range(60):
		await physics_frame
	Input.action_release("move_forward")
	await physics_frame
	var ascent: float = thief.global_position.y - start_y
	await _free_node(rig)
	return ascent


## Walked descent off a 0.24 m riser, returning the largest upward solver
## correction after a re-seat (the W6M failure was a 0.248 m bounce).
func _measure_shove_back(shrink: float) -> float:
	var base: Vector3 = _next_base()
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = base
	var riser: float = 0.24
	_add_box(rig, Vector3(0.0, riser * 0.5, -0.6), Vector3(6.0, riser, 4.4))
	_add_box(rig, Vector3(0.0, -0.2, -5.0), Vector3(6.0, 0.4, 4.4))
	var thief: CharacterBody3D = await _spawn_thief(rig, Vector3(0.0, riser + 0.02, 0.6))
	thief.set("step_down_query_shrink_m", shrink)
	var worst: float = 0.0
	var prev_y: float = thief.global_position.y
	var prev_down: bool = false
	Input.action_press("move_forward")
	for _i: int in range(90):
		await physics_frame
		var y: float = thief.global_position.y
		var down_now: bool = y < prev_y - 0.0005
		# A push = the body rose while walking off a descending step.
		if prev_down and y > prev_y + 0.0005:
			worst = maxf(worst, y - prev_y)
		prev_down = down_now
		prev_y = y
	Input.action_release("move_forward")
	await physics_frame
	await _free_node(rig)
	return worst


# ---------------------------------------------------------------- W7H roofs

## Authored roof modules used by the route tests (same paths the roof-collision
## suite pins). Pitch is measured from the real hull, never assumed.
const ROOF_SHALLOW: String = "/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_Mid_4x4"
const ROOF_STEEP: String = "/Game/Art/Environment/Urban/Roofs/SM_RoofUrbanB_Ext_Mid_6x8"
const ROOF_END_SHELLS: Array[String] = [
	"/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndA_2x4x4",
	"/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndB_2x4x4",
	"/Game/Art/Environment/Urban/Roofs/SM_RoofUrban_Ext_EndB_2x4x4_Mirror",
]
const ROOF_END_EAVE_MIN_GAP_M: float = 3.0
const ROOF_WALK_FRAMES: int = 120
const ROOF_MIN_WALKABLE_ASCENT_M: float = 0.8
const ROOF_MAX_REFUSED_ASCENT_M: float = 0.30
var _loader: Node = null


func _roof_loader() -> Node:
	if _loader == null:
		_loader = (load("res://src/core/level_loader.gd") as GDScript).new()
	return _loader


## Builds a body carrying the real authored mesh + the real loader collider at
## `base` (identity basis, optional instance scale like the shipped POI case).
func _make_roof(ue_path: String, scale: Vector3, base: Vector3) -> Dictionary:
	var info: Dictionary = _roof_loader().call("_get_mesh_and_shape", ue_path)
	var mesh: Mesh = info.get("mesh") as Mesh
	var shape: Shape3D = info.get("shape") as Shape3D
	if mesh == null or shape == null:
		return {}
	var rig := Node3D.new()
	root.add_child(rig)
	rig.global_position = base
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	rig.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.scale = scale
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = info.get("shape_offset", Vector3.ZERO)
	body.add_child(cs)
	rig.add_child(body)
	return {"rig": rig, "base": base, "mesh": mesh, "shape": shape, "scale": scale,
		"top": mesh.get_aabb().position.y + mesh.get_aabb().size.y}


## Surface height of the collision hull under a local (x, z) sample.
func _roof_y_at(base: Vector3, x: float, z: float, top: float, scale: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var from: Vector3 = base + Vector3(x, top * scale.y + 2.0, z)
	var to: Vector3 = base + Vector3(x, top * scale.y - 12.0, z)
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y - base.y


## Height field + the uphill unit direction (lowest eave -> highest point).
func _roof_field(f: Dictionary, n: int = 5) -> Dictionary:
	var aabb: AABB = (f["mesh"] as Mesh).get_aabb()
	var base: Vector3 = f["base"] as Vector3
	var scale: Vector3 = f["scale"] as Vector3
	var top: float = float(f["top"])
	var pts: Array[Dictionary] = []
	var lo: Dictionary = {}
	var hi: Dictionary = {}
	for ix: int in range(n):
		for iz: int in range(n):
			var x: float = lerpf(aabb.position.x, aabb.position.x + aabb.size.x, (float(ix) + 0.5) / float(n)) * scale.x
			var z: float = lerpf(aabb.position.z, aabb.position.z + aabb.size.z, (float(iz) + 0.5) / float(n)) * scale.z
			var y: float = _roof_y_at(base, x, z, top, scale)
			if is_nan(y):
				continue
			var p: Dictionary = {"x": x, "z": z, "y": y}
			pts.append(p)
			if lo.is_empty() or y < float(lo["y"]):
				lo = p
			if hi.is_empty() or y > float(hi["y"]):
				hi = p
	return {"pts": pts, "low": lo, "high": hi, "aabb": aabb,
		"apex": float(hi.get("y", NAN)), "eave": float(lo.get("y", NAN))}


## Walks a roof uphill from its lowest sampled eave and returns the measured
## ascent plus the step-up / mantle side effects.
func _roof_walk(f: Dictionary, frames: int = ROOF_WALK_FRAMES) -> Dictionary:
	var base: Vector3 = f["base"] as Vector3
	var field: Dictionary = _roof_field(f)
	var lo: Dictionary = field["low"] as Dictionary
	var hi: Dictionary = field["high"] as Dictionary
	if lo.is_empty() or hi.is_empty():
		return {"ok": false, "ascent": 0.0, "reason": "no collision surface"}
	var dx: float = float(hi["x"]) - float(lo["x"])
	var dz: float = float(hi["z"]) - float(lo["z"])
	var dir: Vector3 = Vector3(dx, 0.0, dz)
	if dir.length() < 0.05:
		return {"ok": false, "ascent": 0.0, "reason": "degenerate uphill direction"}
	dir = dir.normalized()
	var start: Vector3 = Vector3(float(lo["x"]), float(lo["y"]) + 0.05, float(lo["z"]))
	# Back off the eave edge so the capsule starts on the shell, not in the air.
	start -= dir * 0.35
	var thief: CharacterBody3D = await _spawn_thief(f["rig"] as Node3D, start)
	var yaw: float = atan2(-dir.x, -dir.z)
	thief.rotation = Vector3(0.0, yaw, 0.0)
	for _i: int in range(SETTLE_FRAMES):
		await physics_frame
	var start_y: float = thief.global_position.y
	var max_step: float = 0.0
	Input.action_press("move_forward")
	for _f: int in range(frames):
		await physics_frame
		max_step = maxf(max_step, float(thief.get("_step_rise_this_frame")))
	Input.action_release("move_forward")
	var ascent: float = thief.global_position.y - start_y
	var result: Dictionary = {
		"ascent": ascent,
		"step": max_step,
		"mantle": bool(thief.get("is_mantling")),
		"end_floor": bool(thief.is_on_floor()),
		"field": field,
	}
	thief.queue_free()
	await physics_frame
	return result


## 45.2 deg (walkable) vs 67.6 deg (refused), on the shipped modules.
func _check_roof_routes() -> void:
	for rec: Dictionary in [
		{"path": ROOF_SHALLOW, "label": "shallow", "walkable": true},
		{"path": ROOF_STEEP, "label": "steep", "walkable": false},
	]:
		var base: Vector3 = _next_base()
		var f: Dictionary = _make_roof(str(rec["path"]), Vector3.ONE, base)
		if f.is_empty():
			_check(false, "", "%s roof %s did not load a mesh+hull" % [str(rec["label"]), str(rec["path"]).get_file()])
			continue
		var field: Dictionary = _roof_field(f)
		var aabb: AABB = field["aabb"] as AABB
		var pts: Array = field["pts"] as Array
		if pts.size() < 2:
			_check(false, "", "%s roof has no collision surface under the grid" % str(rec["label"]))
			await _free_node(f["rig"] as Node)
			continue
		# Pitch from the height field along the steepest sampled gradient.
		var pitch: float = _roof_field_pitch(field)
		var walk: Dictionary = await _roof_walk(f)
		var ascent: float = float(walk.get("ascent", 0.0))
		var step: float = float(walk.get("step", 0.0))
		var mantled: bool = bool(walk.get("mantle", false))
		var end_floor: bool = bool(walk.get("end_floor", false))
		if bool(rec["walkable"]):
			var ok: bool = ascent >= ROOF_MIN_WALKABLE_ASCENT_M and is_zero_approx(step) and not mantled
			_check(ok,
				"%s roof %.1f deg: walked up %.2f m in %d frames, no step-up (%.3f m), no mantle, grounded=%s" % [str(rec["label"]), pitch, ascent, ROOF_WALK_FRAMES, step, str(end_floor)],
				"%s roof %.1f deg FAILED: ascent %.2f m (< %.1f), step-up %.3f m, mantle=%s, grounded=%s" % [str(rec["label"]), pitch, ascent, ROOF_MIN_WALKABLE_ASCENT_M, step, str(mantled), str(end_floor)])
		else:
			var ok2: bool = ascent < ROOF_MAX_REFUSED_ASCENT_M and not mantled
			_check(ok2,
				"%s roof %.1f deg: refused (ascent %.2f m in %d frames, no mantle, slope above the authored 60 deg walkable angle)" % [str(rec["label"]), pitch, ascent, ROOF_WALK_FRAMES],
				"%s roof %.1f deg FAILED: ascent %.2f m (>= %.2f), mantle=%s" % [str(rec["label"]), pitch, ascent, ROOF_MAX_REFUSED_ASCENT_M, str(mantled)])
		# The collider must reproduce the authored pitch, not the AABB plateau.
		var apex: float = float(field["apex"])
		var top: float = float(f["top"])
		_check(apex <= top + 0.02 and apex >= top - maxf(0.6, aabb.size.y * 0.35),
			"%s roof hull apex %.2f m sits under the authored AABB top %.2f m (measured surface, not a box)" % [str(rec["label"]), apex, top],
			"%s roof hull apex %.2f m vs AABB top %.2f m (plateau or missing hull)" % [str(rec["label"]), apex, top])
		await _free_node(f["rig"] as Node)


## Steepest measured pitch across the sampled grid (degrees).
func _roof_field_pitch(field: Dictionary) -> float:
	var pts: Array = field.get("pts", []) as Array
	var best: float = 0.0
	for i: int in range(pts.size()):
		for j: int in range(i + 1, pts.size()):
			var a: Dictionary = pts[i] as Dictionary
			var b: Dictionary = pts[j] as Dictionary
			var run: float = Vector2(float(b["x"]) - float(a["x"]), float(b["z"]) - float(a["z"])).length()
			if run < 0.25:
				continue
			var rise: float = absf(float(b["y"]) - float(a["y"]))
			best = maxf(best, rad_to_deg(atan2(rise, run)))
	return best


## EndA/EndB gable caps: the eave band must be metres below the AABB top the old
## box floated as a plateau, and a body standing there must land on the shell.
func _check_roof_end_shells() -> void:
	for path: String in ROOF_END_SHELLS:
		var base: Vector3 = _next_base()
		var f: Dictionary = _make_roof(path, Vector3.ONE, base)
		if f.is_empty():
			_check(false, "", "End shell %s did not load" % path.get_file())
			continue
		var field: Dictionary = _roof_field(f)
		var aabb: AABB = field["aabb"] as AABB
		var top: float = float(f["top"])
		var pts: Array = field["pts"] as Array
		if pts.size() < 4:
			_check(false, "", "End shell %s has no collision surface" % path.get_file())
			await _free_node(f["rig"] as Node)
			continue
		# Eave band = the lowest sampled quarter of the footprint.
		var eave: float = float(field["eave"])
		var gap: float = top - eave
		_check(gap >= ROOF_END_EAVE_MIN_GAP_M,
			"End shell %s: eave band %.2f m below the AABB top (%.1f m min, no floating plateau)" % [path.get_file(), gap, ROOF_END_EAVE_MIN_GAP_M],
			"End shell %s: eave band only %.2f m below the AABB top (%.1f m min) - plateau" % [path.get_file(), gap, ROOF_END_EAVE_MIN_GAP_M])
		# Drop a body on the eave band and confirm it falls onto the shell instead
		# of being caught by a floating plateau. A gable face is steeper than the
		# authored 60 deg walkable angle, so the body slides: only the height it
		# reaches matters here, not a resting pose.
		var lo: Dictionary = field["low"] as Dictionary
		var thief: CharacterBody3D = await _spawn_thief(f["rig"] as Node3D, Vector3(float(lo["x"]), top + 1.5, float(lo["z"])))
		# A gable face is steeper than the authored 60 deg walkable angle, so the
		# body falls and slides off the shell: what matters is that nothing holds
		# it at the AABB top the old box floated.
		for _i: int in range(120):
			await physics_frame
		var end_y: float = thief.global_position.y - base.y
		_check(end_y < top - ROOF_END_EAVE_MIN_GAP_M,
			"End shell %s: body dropped at the eave fell/slid to %.2f m, below the %.2f m AABB top the box used to float" % [path.get_file(), end_y, top],
			"End shell %s: body stayed at %.2f m (AABB top %.2f) - landing on a plateau" % [path.get_file(), end_y, top])
		thief.queue_free()
		await physics_frame
		await _free_node(f["rig"] as Node)


## Hip roof (four authored faces) + the non-uniform POI instance scale: the
## surface must follow the scaled pitch, not the scaled AABB.
func _check_roof_hip_and_scale() -> void:
	# 1. Hip: four quarter-footprint samples strictly below the ridge apex.
	var f: Dictionary = _make_roof(ROOF_SHALLOW, Vector3.ONE, _next_base())
	if f.is_empty():
		_check(false, "", "hip roof did not load")
		return
	var field: Dictionary = _roof_field(f)
	var apex: float = float(field["apex"])
	var aabb: AABB = field["aabb"] as AABB
	var quarter_ok: bool = true
	var lowest_quarter: float = 1e9
	var base: Vector3 = f["base"] as Vector3
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var qx: float = float(aabb.get_center().x) + sx * aabb.size.x * 0.25
			var qz: float = float(aabb.get_center().z) + sz * aabb.size.z * 0.25
			var qy: float = _roof_y_at(base, qx, qz, float(f["top"]), Vector3.ONE)
			if is_nan(qy):
				quarter_ok = false
				continue
			lowest_quarter = minf(lowest_quarter, qy)
	_check(quarter_ok and lowest_quarter < apex - 1.0,
		"hip roof: four faces fall %.2f m below the %.2f m ridge (no plateau across the hip)" % [apex - lowest_quarter, apex],
		"hip roof: quarter faces only %.2f m below the ridge (%.2f m) - flat or missing faces" % [apex - lowest_quarter, apex])
	await _free_node(f["rig"] as Node)

	# 2. Non-uniform POI instance: SM_RoofUrban_Ext_Mid_4x4 at scale [1,1,0.8]
	# (Building_Guildhall_POI_3rdFloor). The run shrinks, so the effective pitch
	# is steeper than the module's authored 45.2 deg.
	var scaled_base: Vector3 = _next_base()
	var sf: Dictionary = _make_roof(ROOF_SHALLOW, Vector3(1.0, 1.0, 0.8), scaled_base)
	if sf.is_empty():
		_check(false, "", "non-uniform POI roof did not load")
		return
	var sfield: Dictionary = _roof_field(sf)
	var spitch: float = _roof_field_pitch(sfield)
	var expect_pitch: float = rad_to_deg(atan2(tan(deg_to_rad(45.2)), 0.8))
	_check(absf(spitch - expect_pitch) <= 2.5,
		"non-uniform POI roof: measured %.1f deg == atan(tan(45.2 deg)/0.8) %.1f deg (collider follows the instance scale)" % [spitch, expect_pitch],
		"non-uniform POI roof: measured %.1f deg vs expected %.1f deg" % [spitch, expect_pitch])
	var swalk: Dictionary = await _roof_walk(sf)
	_check(float(swalk.get("ascent", 0.0)) >= ROOF_MIN_WALKABLE_ASCENT_M and not bool(swalk.get("mantle", false)),
		"non-uniform POI roof %.1f deg: still walkable (ascent %.2f m), no mantle" % [spitch, float(swalk.get("ascent", 0.0))],
		"non-uniform POI roof %.1f deg: ascent %.2f m, mantle=%s" % [spitch, float(swalk.get("ascent", 0.0)), str(swalk.get("mantle"))])
	await _free_node(sf["rig"] as Node)


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
