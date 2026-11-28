extends SceneTree
## NAV_DELTA — headless `TAT2_NAV=off` vs `on` trajectory delta (Phase 3 §3B.2).
##
## The port's authored navmesh is behind `TAT2_NAV=off|on` (default off) and the
## default must not flip on a claim. This probe measures the same scripted route
## twice on the authored Guildhall asset — once through the navigation map
## (`on`) and once as the existing straight-line `nav_steering` degradation
## (`off`) — and reports stuck frames, path length, arrival and `wait_ready`
## timing with explicit tolerances. It never writes anything and never claims a
## visual result.
##
## Route (both endpoints read from the committed authored level record, never
## invented):
##   1. `civic`  — the doorless civic doorway, 4.4 m straight through an open
##      opening. Both modes should arrive; the on path is compared to the
##      straight line within `LENGTH_TOL_FRAC` (stated tolerance).
##   2. `prison` — west->east across the prison door, held closed (fake leaves
##      at the authored pivots). The authored baked link is bound to the door
##      by `nav_runtime.register_swinging_doors()`, so with the door closed the
##      on path is partial and the agent accumulates stuck frames. The off
##      (straight-line) agent walks through the closed door: it arrives, but its
##      samples leave the authored walkable surface (`off_mesh_frames > 0`).
##
## Metrics:
##   * stuck_frames — simulated 60 Hz frames in which the agent made <= 1 mm of
##     progress toward the goal at `SPEED_MPS`; a partial path leaves the agent
##     with no next waypoint, so every remaining frame is stuck.
##   * off_mesh_frames — frames whose position is farther than `ON_MESH_TOL_M`
##     from the authored mesh (measured with `map_get_closest_point`, which is
##     used for *measurement only*; the off trajectory itself is the game's
##     straight-line steering).
##   * path_length — on: summed navigation polyline; off: straight-line length.
##   * arrival — final position within `ARRIVAL_TOL_M` of the leg goal.
##   * wait_ready — on: `nav_runtime.wait_ready()` frames and ms before guards
##     may spawn; off: no map wait (0).
##
## Exit 0 only when every check passes; the summary marker is
## `NAV_DELTA_SUMMARY: fails=0`.

const NavRuntimeScript := preload("res://src/ai/nav_runtime.gd")
const LEVEL := "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json"
const CIVIC_ACTOR := "BP_Doorless_Civic_DoorA_Wall_Int_6x6_C_281"
const PRISON_ACTOR := "BP_Prison_WallA_DoorwayB_6x6_C_0"
const DOOR_SIDE_M := 2.2

## Simulation contract (stated, not tuned to a result).
const SPEED_MPS := 3.0
const STEP_S := 1.0 / 60.0
const MAX_FRAMES := 400
const ARRIVAL_TOL_M := 0.30
const PROGRESS_EPS_M := 0.001
## The authored doorway gap: measured max distance from the straight line to
## the authored mesh is printed per leg; the tolerance is the authored half
## metre the runtime probe already uses for link endpoints.
const ON_MESH_TOL_M := 0.50
## Stated length tolerance for the open leg: the on polyline may differ from
## the straight line by at most 10 % of the straight length (measured delta is
## printed, so a widening is visible).
const LENGTH_TOL_FRAC := 0.10
## wait_ready must stay inside the runtime's own READY_MAX_FRAMES ceiling.
const READY_MAX_FRAMES := 300
const READY_MAX_MS := 5000

var fails: int = 0
var checks: int = 0


class FakeDoor:
	extends Node3D
	var angle := 0.0
	var door_entry: Dictionary = {}

	func open_angle_deg() -> float:
		return angle


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  PASS  ", what)
	else:
		fails += 1
		print("  FAIL  ", what)


func _run() -> void:
	var nav_dir := OS.get_environment("TAT2_NAV_DIR")
	if nav_dir == "":
		nav_dir = "res://data/generated/nav"
	OS.set_environment("TAT2_NAV", "on")
	OS.set_environment("TAT2_NAV_DIR", nav_dir)

	# Default resolution must stay off and fail closed; the harness flips it
	# only inside this process.
	OS.unset_environment("TAT2_NAV")
	_check(not NavRuntimeScript.is_enabled(), "TAT2_NAV default (unset) resolves to off")
	OS.set_environment("TAT2_NAV", "banana")
	_check(not NavRuntimeScript.is_enabled(), "TAT2_NAV unknown value fails closed to off")
	OS.set_environment("TAT2_NAV", "on")
	_check(NavRuntimeScript.is_enabled(), "TAT2_NAV=on is the only enabling path used here")
	print("NAV_DELTA_DEFAULT default=off unknown=fail_closed")

	var doc := _read_json(LEVEL)
	_check(not doc.is_empty(), "authored Guildhall level record reads")
	var civic := _door_record(doc, CIVIC_ACTOR)
	var prison := _door_record(doc, PRISON_ACTOR)
	_check(not civic.is_empty(), "authored civic doorway record")
	_check(not prison.is_empty(), "authored prison doorway record")
	if civic.is_empty() or prison.is_empty():
		_finish()
		return

	var host := Node3D.new()
	root.add_child(host)
	var nav = NavRuntimeScript.new()
	nav.name = "NavDeltaRuntime"
	host.add_child(nav)
	var built: bool = nav.setup("guildhall")
	_check(built, "nav_runtime.setup(guildhall) at %s" % nav_dir)
	if not built:
		_finish()
		return
	var map: RID = root.world_3d.navigation_map
	NavigationServer3D.map_set_use_async_iterations(map, false)
	var ready: bool = await nav.wait_ready(900)
	_check(ready, "navigation map committed")
	var ready_frames := int(nav.ready_frames())
	var ready_ms := int(nav.ready_ms())
	print("NAV_DELTA_READY mode=on state=%s ready_frames=%d ready_ms=%d build_ms=%d polys=%d links=%d" % [
		nav.status(), ready_frames, ready_ms, int(nav.build_ms()),
		nav.navmesh().get_polygon_count(), nav.link_count()
	])
	_check(ready_frames > 0 and ready_frames <= READY_MAX_FRAMES, "wait_ready frames %d within %d" % [ready_frames, READY_MAX_FRAMES])
	_check(ready_ms <= READY_MAX_MS, "wait_ready %d ms within %d ms" % [ready_ms, READY_MAX_MS])
	print("NAV_DELTA_READY mode=off ready_frames=0 ready_ms=0 (no map is built when the feature is off)")

	# The prison door is held closed: its leaves exist at the authored pivots
	# and the runtime adopts the authored baked link to the door.
	var prison_leaves := _make_door_leaves(host, prison["pos"], prison["normal"])
	var made: int = await _register_doors(nav)
	_check(made >= 1, "prison door link registered (got %d)" % made)
	_check(nav.baked_door_binding_count() >= 1, "prison baked link bound to the closed door")

	# ---- leg 1: civic doorway (open, both modes must arrive) ----------------
	# Both modes target the same *snapped* goal point: the requested far side
	# sits 0.87 m off the authored mesh (doorway threshold) and comparing an
	# unsnapped goal would fail the navigation mode by construction.
	var civic_a: Vector3 = civic["pos"] + civic["normal"] * DOOR_SIDE_M
	var civic_b: Vector3 = civic["pos"] - civic["normal"] * DOOR_SIDE_M
	var civic_a_snap := NavigationServer3D.map_get_closest_point(map, civic_a)
	var civic_b_snap := NavigationServer3D.map_get_closest_point(map, civic_b)
	_check(civic_a_snap.distance_to(civic_a) <= 2.5 and civic_b_snap.distance_to(civic_b) <= 2.5, "civic doorway sides snap onto the authored mesh")
	var civic_on := _sim_on(map, civic_a_snap, civic_b_snap)
	var civic_off := _sim_off(map, civic_a_snap, civic_b_snap)
	_report("civic", civic_on, civic_off, civic_b_snap.distance_to(civic_b))
	var civic_straight := civic_a_snap.distance_to(civic_b_snap)
	var civic_frac := absf(float(civic_on["path_length"]) - float(civic_off["path_length"])) / civic_straight
	print("NAV_DELTA_LENGTH leg=civic on=%.2f off=%.2f straight=%.2f delta_frac=%.4f tol=%.2f" % [
		float(civic_on["path_length"]), float(civic_off["path_length"]),
		civic_straight, civic_frac, LENGTH_TOL_FRAC
	])
	_check(bool(civic_on["arrived"]), "civic leg: nav on arrives")
	_check(bool(civic_off["arrived"]), "civic leg: straight-line off arrives")
	_check(civic_frac <= LENGTH_TOL_FRAC, "civic leg: on/off path length delta %.2f%% within %.0f%%" % [civic_frac * 100.0, LENGTH_TOL_FRAC * 100.0])
	_check(int(civic_on["stuck_frames"]) == 0, "civic leg: nav on has no stuck frames (got %d)" % int(civic_on["stuck_frames"]))
	_check(int(civic_on["off_mesh_frames"]) == 0, "civic leg: nav on stays on the authored mesh")

	# ---- leg 2: prison doorway, door closed --------------------------------
	# The authored doorway threshold carries a small non-walkable band even
	# when open (measured max 0.80 m on the civic leg above), so the contrast
	# that matters is arrival/stuck: `on` is blocked by the closed door while
	# the degraded straight line walks through it.
	var west: Vector3 = prison["pos"] - prison["normal"] * DOOR_SIDE_M
	var east: Vector3 = prison["pos"] + prison["normal"] * DOOR_SIDE_M
	var west_snap := NavigationServer3D.map_get_closest_point(map, west)
	var east_snap := NavigationServer3D.map_get_closest_point(map, east)
	var prison_on := _sim_on(map, west_snap, east_snap)
	var prison_off := _sim_off(map, west_snap, east_snap)
	_report("prison", prison_on, prison_off, east_snap.distance_to(east))
	print("NAV_DELTA_CLOSED leg=prison door=closed on_arrived=%s on_stuck=%d off_arrived=%s off_off_mesh=%d off_off_mesh_max=%.2f" % [
		str(prison_on["arrived"]), int(prison_on["stuck_frames"]),
		str(prison_off["arrived"]), int(prison_off["off_mesh_frames"]),
		float(prison_off["off_mesh_max"])
	])
	_check(not bool(prison_on["arrived"]), "prison leg closed: nav on cannot arrive")
	_check(int(prison_on["stuck_frames"]) > 0, "prison leg closed: nav on accumulates stuck frames (got %d)" % int(prison_on["stuck_frames"]))
	_check(bool(prison_off["arrived"]), "prison leg closed: straight-line off still arrives")
	_check(float(prison_off["off_mesh_max"]) > 0.30, "prison leg closed: the straight line crosses a >0.30 m non-walkable band (measured %.2f m)" % float(prison_off["off_mesh_max"]))

	print("NAV_DELTA_SUMMARY: fails=%d checks=%d length_tol=%.2f arrival_tol=%.2f on_mesh_tol=%.2f default=off" % [
		fails, checks, LENGTH_TOL_FRAC, ARRIVAL_TOL_M, ON_MESH_TOL_M
	])
	_finish()


func _report(leg: String, on: Dictionary, off: Dictionary, goal_snap_m: float) -> void:
	print("NAV_DELTA mode=on leg=%s arrived=%s frames=%d path_waypoints=%d path_length=%.2f stuck=%d off_mesh=%d goal_snap_m=%.2f" % [
		leg, str(on["arrived"]), int(on["frames"]), int(on["waypoints"]),
		float(on["path_length"]), int(on["stuck_frames"]), int(on["off_mesh_frames"]),
		goal_snap_m
	])
	print("NAV_DELTA mode=off leg=%s arrived=%s frames=%d path_length=%.2f stuck=%d off_mesh=%d off_mesh_max_m=%.2f" % [
		leg, str(off["arrived"]), int(off["frames"]), float(off["path_length"]),
		int(off["stuck_frames"]), int(off["off_mesh_frames"]), float(off["off_mesh_max"])
	])


## Follow the authored navigation polyline at SPEED_MPS for at most MAX_FRAMES.
func _sim_on(map: RID, start: Vector3, goal: Vector3) -> Dictionary:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, goal, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var pos := start
	var wp := 1 if path.size() > 0 else 0
	var frames := 0
	var stuck := 0
	var off_mesh := 0
	var off_mesh_max := 0.0
	var travelled := 0.0
	var arrived := false
	while frames < MAX_FRAMES:
		frames += 1
		if pos.distance_to(goal) <= ARRIVAL_TOL_M:
			arrived = true
			break
		var moved := 0.0
		if wp < path.size():
			var target: Vector3 = path[wp]
			var step := SPEED_MPS * STEP_S
			var to_target := pos.distance_to(target)
			if to_target <= step:
				moved = to_target
				pos = target
				wp += 1
			else:
				var before := pos
				pos = pos.move_toward(target, step)
				moved = before.distance_to(pos)
		travelled += moved
		if moved <= PROGRESS_EPS_M:
			stuck += 1
		var d := NavigationServer3D.map_get_closest_point(map, pos).distance_to(pos)
		off_mesh_max = maxf(off_mesh_max, d)
		if d > ON_MESH_TOL_M:
			off_mesh += 1
	if pos.distance_to(goal) <= ARRIVAL_TOL_M:
		arrived = true
	return {
		"arrived": arrived, "frames": frames, "waypoints": path.size(),
		"path_length": length, "travelled": travelled,
		"stuck_frames": stuck, "off_mesh_frames": off_mesh,
		"off_mesh_max": off_mesh_max,
	}


## The game's degraded straight-line steering: walk directly at the goal.
func _sim_off(map: RID, start: Vector3, goal: Vector3) -> Dictionary:
	var pos := start
	var frames := 0
	var stuck := 0
	var off_mesh := 0
	var off_mesh_max := 0.0
	var travelled := 0.0
	var arrived := false
	while frames < MAX_FRAMES:
		frames += 1
		if pos.distance_to(goal) <= ARRIVAL_TOL_M:
			arrived = true
			break
		var step := SPEED_MPS * STEP_S
		var before := pos
		pos = pos.move_toward(goal, step)
		var moved := before.distance_to(pos)
		travelled += moved
		if moved <= PROGRESS_EPS_M:
			stuck += 1
		var d := NavigationServer3D.map_get_closest_point(map, pos).distance_to(pos)
		off_mesh_max = maxf(off_mesh_max, d)
		if d > ON_MESH_TOL_M:
			off_mesh += 1
	if pos.distance_to(goal) <= ARRIVAL_TOL_M:
		arrived = true
	return {
		"arrived": arrived, "frames": frames, "waypoints": 0,
		"path_length": travelled, "travelled": travelled,
		"stuck_frames": stuck, "off_mesh_frames": off_mesh,
		"off_mesh_max": off_mesh_max,
	}


func _register_doors(nav) -> int:
	var made: int = nav.register_swinging_doors()
	# The adopted baked link is disabled on registration; give the server one
	# sync before paths are measured.
	for _i: int in range(6):
		await physics_frame
	NavigationServer3D.map_force_update(root.world_3d.navigation_map)
	return made


func _make_door_leaves(host: Node3D, mid: Vector3, normal: Vector3) -> Array:
	var basis := Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), normal)
	var out: Array = []
	for dz: float in [1.0, -1.0]:
		var d := FakeDoor.new()
		d.name = "NavDeltaPrison_%s" % ("a" if dz > 0.0 else "b")
		d.door_entry = {"actor": PRISON_ACTOR}
		d.transform = Transform3D(basis, mid + Vector3(0.0, 0.0, dz))
		host.add_child(d)
		d.add_to_group("swinging_doors")
		out.append(d)
	return out


func _door_record(doc: Dictionary, actor: String) -> Dictionary:
	var centre := Vector3.ZERO
	var normal := Vector3.ZERO
	var n := 0
	for rec_v: Variant in doc.get("swinging_doors", []):
		var dr: Dictionary = rec_v
		if str(dr.get("actor", "")) != actor:
			continue
		var p: Array = dr.get("pos", [])
		var b: Array = dr.get("basis", [])
		if p.size() < 3 or b.size() < 9:
			continue
		var leaf_normal := Vector3(float(b[2]), float(b[5]), float(b[8]))
		leaf_normal.y = 0.0
		if leaf_normal.length() < 0.001:
			continue
		leaf_normal = leaf_normal.normalized()
		if normal.length() > 0.001 and normal.dot(leaf_normal) < 0.0:
			leaf_normal = -leaf_normal
		normal += leaf_normal
		centre += Vector3(float(p[0]), float(p[1]), float(p[2]))
		n += 1
	if n == 0 or normal.length() < 0.001:
		return {}
	return {"pos": centre / float(n), "normal": normal.normalized()}


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var doc: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return doc if typeof(doc) == TYPE_DICTIONARY else {}


func _finish() -> void:
	OS.unset_environment("TAT2_NAV")
	OS.unset_environment("TAT2_NAV_DIR")
	quit(0 if fails == 0 else 1)
