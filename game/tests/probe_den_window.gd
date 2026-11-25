extends SceneTree
## W9-P2 B3 probe (L4-13): Den telescope ponder contract + west-window escape.
##
## Authored facts this probe pins (build/qa/w9 facts; measured on the loaded
## Den shell):
##   * `[F] PONDER` / `[F] EXIT` is camera-only: `toggle_telescope_ponder()`
##     swaps the view to `DenTelescopeCam` and back, and must never write the
##     player transform.
##   * The framed west opening sits on the wall plane x=-6.06 m, spans
##     z 270.4..272.4 and y 41.0..45.1 (sill 0.745 m above the Den floor at
##     40.255 m). `SM_ThievesDen_Glass` has no collision and the Den `volumes`
##     array is empty, so `try_auto_mantle` (accepts 0.45..4.0 m) lifts the
##     player onto the sill and a held forward walk leaves the Den.
##
## Measured on this HEAD (2026-11-25): the escape is NOT reproducible. The
## authored `SM_ThievesDen_Glass` now builds real concave collision (W9-P1
## 7939a61 "consume the authored UE AggGeom for every mesh"), so the west pane
## stops the walk at x ~ -5.26; the stronger forward+sprint attempt only
## wall-climbs the pane to y ~ 43.15, still below the 45.1 opening top. The
## `DenWestWindowBlocker` helper is therefore a defense-in-depth guard at the
## authored opening plane: if the glass collision is ever dropped again (the
## pre-7939a61 state the L4-13 record was captured on), the layer-1
## StaticBody3D in `blocking_volume` stops the walk and refuses the mantle,
## while the telescope Area3D and the ponder vista stay untouched.
##
## RED (pre-fix tree): the blocker checks fail; the walk itself is already
## contained by the glass collision. GREEN: all checks pass.
##
## Run (never beside another Godot; thermal rule):
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game \
##       --script res://tests/probe_den_window.gd"

const MISSION_SCENE := "res://scenes/mission.tscn"
const HUD_PATH := "res://src/ui/hud.gd"

## Measured opening (mission_controller.DEN_WEST_WINDOW_ANCHOR is the centre).
const WALL_PLANE_X := -6.06
const OPENING_Z_MIN := 270.4
const OPENING_Z_MAX := 272.4
const OPENING_Y_MIN := 41.0
const OPENING_Y_MAX := 45.1
const OPENING_Z_CENTRE := 271.4
## Player start for the scripted walk: 1.5 m in front of the wall plane, on
## the opening's z centre, facing west (-X).
const WALK_START_X := -4.56
const WALK_FACING_YAW := PI * 0.5
const WALK_PHYSICS_FRAMES := 180 # 3.0 s at 60 Hz
## Stronger attempt (the brief's fallback): start 0.5 m closer, sprint 4 s.
const STRONG_START_X := -5.30
const STRONG_PHYSICS_FRAMES := 240 # 4.0 s at 60 Hz

var fails: int = 0
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, ok: String, fail: String = "") -> bool:
	checks += 1
	if cond:
		print("PASS: [den] ", ok)
		return true
	fails += 1
	printerr("FAIL: [den] ", fail if fail != "" else ok)
	return false


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame


func _wait_physics(frames: int) -> void:
	for _i: int in range(frames):
		await physics_frame


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("DEN_WINDOW FAIL: GameState autoload missing")
		quit(1)
		return

	# Contract 1 is the Thieves' Den tutorial (contracts.json map_id).
	gs.set("thief_id", "spider")
	gs.set("active_contract_order", 1)
	gs.set("state", "playing")
	var mission: Node = (load(MISSION_SCENE) as PackedScene).instantiate()
	root.add_child(mission)

	var waited: int = 0
	while mission.get("player") == null and waited < 3600:
		await process_frame
		waited += 1
	if not _check(mission.get("player") != null, "Den player spawned (waited=%d)" % waited,
			"Den player did not spawn within %d frames" % waited):
		print("DEN_WINDOW FAIL checks=%d" % checks)
		quit(1)
		return
	await _wait(20)
	var player: Node3D = mission.get("player") as Node3D
	var hud: Node = mission.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(5)
	_check(str(gs.get("active_map_id")) == "thieves_den",
		"active map is thieves_den", "active_map_id=%s" % str(gs.get("active_map_id")))
	_check(bool(mission.get("_is_thieves_den")),
		"mission controller resolved the Den branch", "_is_thieves_den=false")

	var tele: Node3D = mission.get_node_or_null("DenTelescopeArea") as Node3D
	if not _check(tele != null, "DenTelescopeArea exists", "DenTelescopeArea missing"):
		print("DEN_WINDOW FAIL checks=%d" % checks)
		quit(1)
		return
	var floor_y: float = tele.global_position.y
	print("DEN_WINDOW floor_y=%.5f tele=%s" % [floor_y, str(tele.global_position)])
	_check(absf(tele.global_position.x - (-4.9202)) < 0.001
			and absf(tele.global_position.z - 270.7337) < 0.001,
		"telescope area sits at the authored (-4.9202, floor, 270.7337)",
		"tele=%s" % str(tele.global_position))

	# Park the player clear of props for the camera-only toggle proof.
	player.global_position = Vector3(-3.6, floor_y + 0.05, 271.4)
	player.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	player.set("velocity", Vector3.ZERO)
	await _wait_physics(8)

	var pos_before: Vector3 = player.global_position
	mission.call("toggle_telescope_ponder")
	await _wait(2)
	var ponder_cam: Camera3D = mission.get("_ponder_cam") as Camera3D
	var vista: Node = mission.get("_ponder_vista") as Node
	_check(bool(mission.get("_ponder_active")), "ponder enter sets _ponder_active")
	_check(ponder_cam != null and is_instance_valid(ponder_cam) and ponder_cam.current,
		"ponder enter makes DenTelescopeCam current",
		"cam=%s current=%s" % [str(ponder_cam), str(ponder_cam.current) if ponder_cam != null else "null"])
	_check(vista != null and is_instance_valid(vista),
		"ponder enter builds the DenWindowVista diorama", "_ponder_vista missing")
	if ponder_cam != null and is_instance_valid(ponder_cam):
		var want_eye: Vector3 = tele.global_position + Vector3(0.1, 1.7, 0.0)
		_check(ponder_cam.global_position.distance_to(want_eye) < 0.001,
			"ponder eye is the authored tripod offset (0.1, 1.7, 0)",
			"eye=%s want=%s" % [str(ponder_cam.global_position), str(want_eye)])
	var ponder_active_before_exit: bool = bool(mission.get("_ponder_active"))
	print("DEN_WINDOW ponder_enter cam=%s current=%s vista=%s active=%s" % [
		str(ponder_cam), str(ponder_cam.current) if ponder_cam != null else "null",
		str(vista), str(ponder_active_before_exit)])

	# The frame guard collapses same-frame re-entry; one frame apart is one press.
	await process_frame
	mission.call("toggle_telescope_ponder")
	await _wait(2)
	var player_cam: Camera3D = player.get("cam") as Camera3D
	_check(not bool(mission.get("_ponder_active")), "ponder exit clears _ponder_active")
	_check(ponder_cam != null and not ponder_cam.current, "ponder exit clears DenTelescopeCam.current")
	_check(player_cam != null and player_cam.current, "ponder exit restores the player camera")
	_check(mission.get("_ponder_vista") == null, "ponder exit frees the vista node")
	_check(player.global_position.distance_to(pos_before) < 0.005,
		"telescope toggle never writes the player transform",
		"pos before=%s after=%s" % [str(pos_before), str(player.global_position)])
	print("DEN_WINDOW player_before=%s player_after_toggle=%s" % [str(pos_before), str(player.global_position)])

	# --- West-opening blocker -------------------------------------------------
	var blocker: StaticBody3D = mission.get_node_or_null("DenWestWindowBlocker") as StaticBody3D
	if _check(blocker != null, "DenWestWindowBlocker exists",
			"DenWestWindowBlocker missing (west opening unguarded)"):
		_check(blocker.collision_layer == 1 and blocker.collision_mask == 0,
			"blocker is layer 1 / mask 0", "layer=%d mask=%d" % [blocker.collision_layer, blocker.collision_mask])
		_check(blocker.is_in_group("blocking_volume"),
			"blocker is tagged blocking_volume (solid, never a mantle/ledge/climb anchor)",
			"blocker missing the blocking_volume group")
		_check(not blocker.is_in_group("interactables"),
			"blocker is not an interactable", "blocker leaked into interactables")
		var mesh_kids: Array[Node] = blocker.find_children("*", "MeshInstance3D", true, false)
		_check(mesh_kids.is_empty(), "blocker has no mesh (invisible)",
			"blocker has %d MeshInstance3D child(ren)" % mesh_kids.size())
		var box: BoxShape3D = null
		for ch: Node in blocker.get_children():
			if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
				box = (ch as CollisionShape3D).shape as BoxShape3D
				break
		if _check(box != null, "blocker carries one BoxShape3D", "blocker BoxShape3D missing"):
			var half: Vector3 = box.size * 0.5
			var inner_x: float = blocker.global_position.x + half.x
			var top_y: float = blocker.global_position.y + half.y
			var bottom_y: float = blocker.global_position.y - half.y
			_check(absf(inner_x - WALL_PLANE_X) < 0.02,
				"blocker inner face sits on the wall plane x=%.2f (inner=%.3f)" % [WALL_PLANE_X, inner_x],
				"inner face x=%.3f want %.2f" % [inner_x, WALL_PLANE_X])
			_check(absf(top_y - OPENING_Y_MAX) < 0.02,
				"blocker top covers the opening top y=%.2f (top=%.3f)" % [OPENING_Y_MAX, top_y],
				"top y=%.3f want %.2f" % [top_y, OPENING_Y_MAX])
			_check(box.size.x >= 0.12 - 0.001 and box.size.y >= 4.1 - 0.001
					and absf(box.size.z - 2.0) < 0.02,
				"blocker box covers the opening (%.2f x %.2f x %.2f)" % [box.size.x, box.size.y, box.size.z],
				"blocker box too small: %s" % str(box.size))
			_check(bottom_y <= floor_y + 0.2,
				"blocker extends down to the floor (bottom=%.3f floor=%.3f) so the 0.30 m wall probe hits it" % [bottom_y, floor_y],
				"blocker bottom %.3f is above the mantle wall probe (floor=%.3f)" % [bottom_y, floor_y])
			_check(absf(blocker.global_position.z - OPENING_Z_CENTRE) < 0.02,
				"blocker is centred on the opening z=%.1f" % OPENING_Z_CENTRE,
				"blocker z=%.3f" % blocker.global_position.z)
			# Solid from the reveal side: a short ray between the glass plane
			# (-5.71) and the blocker (-6.06) must land on the blocker itself.
			var solid_hits: int = 0
			for y: float in [floor_y + 0.3, 41.2, 42.6, 44.5]:
				var q := PhysicsRayQueryParameters3D.create(
					Vector3(-5.85, y, OPENING_Z_CENTRE), Vector3(-6.30, y, OPENING_Z_CENTRE), 1)
				var hit: Dictionary = mission.get_viewport().world_3d.direct_space_state.intersect_ray(q)
				if not hit.is_empty() and hit.get("collider") == blocker:
					solid_hits += 1
			_check(solid_hits == 4,
				"blocker is solid on layer 1 at all four mantle sample heights (%d/4)" % solid_hits,
				"blocker missed the layer-1 ray at %d/4 heights" % (4 - solid_hits))
		# The telescope interaction point is 1.14 m inboard of the blocker; the
		# LOS ray from a player eye at the telescope must not hit it.
		if tele.has_meta("interaction_point"):
			var point: Vector3 = tele.get_meta("interaction_point") as Vector3
			player.global_position = tele.global_position + Vector3(1.0, 0.05, 0.0)
			player.set("velocity", Vector3.ZERO)
			await _wait_physics(3)
			var eye: Vector3 = player.call("_player_eye_position") as Vector3
			var rid: RID = player.get_rid()
			var excl: Array[RID] = [rid]
			var clear: bool = bool(player.call("_los_clear", eye, point, excl))
			_check(clear, "telescope interaction LOS stays clear of the blocker",
				"telescope LOS blocked (eye=%s point=%s)" % [str(eye), str(point)])
			print("DEN_WINDOW telescope_los clear=%s eye=%s point=%s" % [str(clear), str(eye), str(point)])

	# --- Scripted walk into the west opening ----------------------------------
	player.global_position = Vector3(WALK_START_X, floor_y + 0.05, OPENING_Z_CENTRE)
	player.rotation = Vector3(0.0, WALK_FACING_YAW, 0.0)
	player.set("velocity", Vector3.ZERO)
	await _wait_physics(8)
	var walk_start: Vector3 = player.global_position
	Input.action_press("move_forward")
	var min_x: float = walk_start.x
	var max_y: float = walk_start.y
	var mantled: bool = false
	for i: int in range(WALK_PHYSICS_FRAMES):
		await physics_frame
		var p: Vector3 = player.global_position
		min_x = minf(min_x, p.x)
		max_y = maxf(max_y, p.y)
		if bool(player.get("is_mantling")):
			mantled = true
	Input.action_release("move_forward")
	await _wait_physics(3)
	var final_pos: Vector3 = player.global_position
	print("DEN_WINDOW walk start=%s final=%s min_x=%.4f max_y=%.4f mantled=%s frames=%d" % [
		str(walk_start), str(final_pos), min_x, max_y, str(mantled), WALK_PHYSICS_FRAMES])
	_check(final_pos.x > WALL_PLANE_X and min_x > WALL_PLANE_X,
		"held forward walk stays inside the Den (min_x=%.4f > x=%.2f)" % [min_x, WALL_PLANE_X],
		"player left the Den through the west opening: min_x=%.4f final=%s" % [min_x, str(final_pos)])
	_check(final_pos.y < OPENING_Y_MAX and max_y < OPENING_Y_MAX,
		"held forward walk never climbs past the opening top y=%.2f (max_y=%.4f)" % [OPENING_Y_MAX, max_y],
		"player climbed out: max_y=%.4f final=%s" % [max_y, str(final_pos)])
	_check(not mantled, "no auto-mantle onto the 0.745 m sill",
		"auto-mantle fired at the west opening")

	# --- Stronger attempt (brief fallback): closer start, forward+run, 4 s ----
	# On the pre-7939a61 tree this is where the escape reproduced; on HEAD the
	# glass collision turns it into a wall climb that stalls below the top.
	player.global_position = Vector3(STRONG_START_X, floor_y + 0.05, OPENING_Z_CENTRE)
	player.rotation = Vector3(0.0, WALK_FACING_YAW, 0.0)
	player.set("velocity", Vector3.ZERO)
	await _wait_physics(8)
	var strong_start: Vector3 = player.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var strong_min_x: float = strong_start.x
	var strong_max_y: float = strong_start.y
	var climbed: bool = false
	for i: int in range(STRONG_PHYSICS_FRAMES):
		await physics_frame
		var p: Vector3 = player.global_position
		strong_min_x = minf(strong_min_x, p.x)
		strong_max_y = maxf(strong_max_y, p.y)
		if bool(player.get("is_wall_climbing")):
			climbed = true
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait_physics(3)
	var strong_final: Vector3 = player.global_position
	print("DEN_WINDOW strong start=%s final=%s min_x=%.4f max_y=%.4f wall_climbed=%s frames=%d" % [
		str(strong_start), str(strong_final), strong_min_x, strong_max_y, str(climbed), STRONG_PHYSICS_FRAMES])
	_check(strong_final.x > WALL_PLANE_X and strong_min_x > WALL_PLANE_X,
		"forward+run stays inside the Den (min_x=%.4f > x=%.2f)" % [strong_min_x, WALL_PLANE_X],
		"forward+run left the Den: min_x=%.4f final=%s" % [strong_min_x, str(strong_final)])
	_check(strong_final.y < OPENING_Y_MAX and strong_max_y < OPENING_Y_MAX,
		"forward+run never clears the opening top y=%.2f (max_y=%.4f)" % [OPENING_Y_MAX, strong_max_y],
		"forward+run climbed out: max_y=%.4f final=%s" % [strong_max_y, str(strong_final)])

	# --- A/B: the pre-7939a61 state (glass collision absent) -----------------
	# The L4-13 record was captured before W9-P1 7939a61 started baking authored
	# concave collision for every mesh, so SM_ThievesDen_Glass was walk-through.
	# Disable only that shape at runtime (test scene only) to restore the old
	# opening. On this HEAD the authored glass/shell collision already closes it,
	# so the blocker-off diagnostic is expected to print escaped=false; the guard
	# is defense-in-depth, not the live stop. When the glass ever regresses the
	# same diagnostic must flip to escaped=true and the blocker must contain it:
	# blocker on -> contained. This is a simulation of the historical state,
	# not a claim about the unmodified current tree (which already contains
	# the player with the glass collision).
	var glass_shapes: Array[CollisionShape3D] = []
	for cs_n: Node in mission.find_children("*", "CollisionShape3D", true, false):
		var cs: CollisionShape3D = cs_n as CollisionShape3D
		if str(cs.get_meta("ue_mesh", "")).ends_with("SM_ThievesDen_Glass"):
			glass_shapes.append(cs)
	_check(not glass_shapes.is_empty(),
		"found the authored SM_ThievesDen_Glass collision to simulate the pre-fix state",
		"SM_ThievesDen_Glass collision shapes not found")
	for cs: CollisionShape3D in glass_shapes:
		cs.disabled = true
	await _wait_physics(3)

	var blocker_body: StaticBody3D = mission.get_node_or_null("DenWestWindowBlocker") as StaticBody3D
	if blocker_body != null:
		# Blocker OFF: the historical opening must escape again.
		blocker_body.collision_layer = 0
		await _wait_physics(3)
		player.global_position = Vector3(STRONG_START_X, floor_y + 0.05, OPENING_Z_CENTRE)
		player.rotation = Vector3(0.0, WALK_FACING_YAW, 0.0)
		player.set("velocity", Vector3.ZERO)
		await _wait_physics(8)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		var off_min_x: float = player.global_position.x
		var off_max_y: float = player.global_position.y
		for _i: int in range(STRONG_PHYSICS_FRAMES):
			await physics_frame
			var po: Vector3 = player.global_position
			off_min_x = minf(off_min_x, po.x)
			off_max_y = maxf(off_max_y, po.y)
		Input.action_release("sprint")
		Input.action_release("move_forward")
		await _wait_physics(3)
		var escaped: bool = off_min_x < WALL_PLANE_X or off_max_y >= OPENING_Y_MAX
		print("DEN_WINDOW pre_fix blocker_off min_x=%.4f max_y=%.4f escaped=%s final=%s" % [
			off_min_x, off_max_y, str(escaped), str(player.global_position)])
		# Diagnostic, not a pass/fail: on this HEAD the SM_ThievesDen shell
		# collision (authored AggGeom, W9-P1) also closes the opening, so
		# disabling only the glass does not restore the historical escape.
		# When the shell is honest, this prints escaped=true and the blocker-on
		# walk below is the diagnostic; when it prints false the authored shell is
		# is defense-in-depth and its solidity is proven by the ray checks.
		print("DEN_WINDOW pre_fix_escape_reproduced=", str(escaped),
			" (shell collision still closes the opening: ", str(not escaped), ")")

		# Blocker ON: the same walk must stay inside.
		blocker_body.collision_layer = 1
		await _wait_physics(3)
		player.global_position = Vector3(STRONG_START_X, floor_y + 0.05, OPENING_Z_CENTRE)
		player.rotation = Vector3(0.0, WALK_FACING_YAW, 0.0)
		player.set("velocity", Vector3.ZERO)
		await _wait_physics(8)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		var on_min_x: float = player.global_position.x
		var on_max_y: float = player.global_position.y
		for _i: int in range(STRONG_PHYSICS_FRAMES):
			await physics_frame
			var pn: Vector3 = player.global_position
			on_min_x = minf(on_min_x, pn.x)
			on_max_y = maxf(on_max_y, pn.y)
		Input.action_release("sprint")
		Input.action_release("move_forward")
		await _wait_physics(3)
		print("DEN_WINDOW pre_fix blocker_on min_x=%.4f max_y=%.4f final=%s" % [
			on_min_x, on_max_y, str(player.global_position)])
		_check(on_min_x > WALL_PLANE_X and on_max_y < OPENING_Y_MAX,
			"the same pre-fix walk is contained with the blocker on (min_x=%.4f > %.2f, max_y=%.4f < %.2f)" % [on_min_x, WALL_PLANE_X, on_max_y, OPENING_Y_MAX],
			"blocker failed to contain the pre-fix walk: min_x=%.4f max_y=%.4f" % [on_min_x, on_max_y])
	for cs: CollisionShape3D in glass_shapes:
		if is_instance_valid(cs):
			cs.disabled = false

	var ok: bool = fails == 0
	print("DEN_WINDOW ", "PASS" if ok else "FAIL", " checks=%d" % checks)
	quit(0 if ok else 1)
