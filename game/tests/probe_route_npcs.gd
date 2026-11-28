extends SceneTree
## Route NPC population re-measure (C4-08 / L4-08).
##
## The P0b staged route reports "4 guards + 3 civilians at 48-151 m" and
## therefore defers S19/S20/S22/S23 (scan, pickpocket, takedown, patrol
## barks). This probe boots the same Novice Contract 2 Guildhall safe-room
## spawn the route uses and measures every live guard and civilian from the
## player's authored spawn. It does not move anything: the authored spawn
## placement is the measurement.
##
## Output (machine-readable, consumed by build/qa/p0b_route_stats.py notes):
##   ROUTE_NPC guard id=... pos=(x,y,z) dist_anchor=NN.N
##   ROUTE_NPC civilian id=... pos=(x,y,z) dist_anchor=NN.N
##   ROUTE_NPC SUMMARY guards=N civilians=N nearest_m=NN.N in_range_30m=N ...
##   ROUTE_NPC PASS checks=N fails=0 unreachable_beats=S19,S22,S23
##
## "in range" means the NPC is within NPC_REACH_M of the route anchor (the
## safe-room spawn). If none are, the NPC-dependent beats are recorded as
## unreachable in the route scorer; this probe never moves an NPC to make a
## beat pass.
##
## Run (never beside another Godot):
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game \
##       --script res://tests/probe_route_npcs.gd"

const MAP_ID: String = "guildhall"
const CONTRACT_ORDER: int = 2
const BOOT_FRAME_LIMIT: int = 3600
const SETTLE_PHYSICS_FRAMES: int = 60
## The staged route's engagement radius. A guard 30 m away or more is not on
## the route's traversal (the route's beats all sit inside the building).
const NPC_REACH_M: float = 30.0
## The P0b report's claim, re-measured here.
const REPORTED_GUARDS: int = 4
const REPORTED_CIVILIANS: int = 3

var _checks: int = 0
var _fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, ok: String, fail: String = "") -> bool:
	_checks += 1
	if cond:
		print("PASS: [route_npc] ", ok)
		return true
	_fails += 1
	printerr("FAIL: [route_npc] ", fail if fail != "" else ok)
	return false


func _fmt(v: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [v.x, v.y, v.z]


func _wait_physics(frames: int) -> void:
	for _i: int in range(frames):
		await physics_frame


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("ROUTE_NPC FAIL: GameState autoload missing")
		quit(1)
		return
	gs.set("active_contract_order", CONTRACT_ORDER)
	gs.set("difficulty", 1) # Novice
	var mission: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission)

	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("guards").is_empty()) and waited < BOOT_FRAME_LIMIT:
		await process_frame
		waited += 1
	await _wait_physics(SETTLE_PHYSICS_FRAMES)
	if not _check(mission.get("player") != null, "Guildhall player spawned (waited=%d)" % waited,
			"player did not spawn within %d frames" % waited):
		print("ROUTE_NPC FAIL checks=%d" % _checks)
		quit(1)
		return
	var player: Node3D = mission.get("player") as Node3D
	var anchor: Vector3 = player.global_position
	print("ROUTE_NPC boot map=%s order=%d difficulty=1 anchor=%s frames=%d" % [
		str(gs.get("active_map_id")), CONTRACT_ORDER, _fmt(anchor), waited,
	])
	_check(str(gs.get("active_map_id")) == MAP_ID,
		"loaded map is guildhall", "loaded map=%s" % str(gs.get("active_map_id")))

	var guards: Array = get_nodes_in_group("guards")
	var civilians: Array = get_nodes_in_group("civilians")
	guards.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
	civilians.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
	var nearest_type: String = "-"
	var nearest_name: String = "-"
	var nearest_m: float = INF
	var max_m: float = 0.0
	var in_range: int = 0
	for g_v: Node in guards:
		var g: Node3D = g_v as Node3D
		if g == null:
			continue
		var d: float = g.global_position.distance_to(anchor)
		nearest_m = minf(nearest_m, d)
		max_m = maxf(max_m, d)
		if d <= NPC_REACH_M:
			in_range += 1
		if d == nearest_m:
			nearest_type = "guard"
			nearest_name = str(g.name)
		print("ROUTE_NPC guard id=%s pos=%s dist_anchor=%.1f" % [str(g.name), _fmt(g.global_position), d])
	for c_v: Node in civilians:
		var c: Node3D = c_v as Node3D
		if c == null:
			continue
		var d: float = c.global_position.distance_to(anchor)
		nearest_m = minf(nearest_m, d)
		max_m = maxf(max_m, d)
		if d <= NPC_REACH_M:
			in_range += 1
		if d == nearest_m:
			nearest_type = "civilian"
			nearest_name = str(c.name)
		print("ROUTE_NPC civilian id=%s pos=%s dist_anchor=%.1f" % [str(c.name), _fmt(c.global_position), d])

	_check(guards.size() >= 1, "live guards found (%d)" % guards.size(), "no guard node in the guards group")
	_check(civilians.size() >= 1, "live civilians found (%d)" % civilians.size(), "no civilian node in the civilians group")
	var count_text: String = "guards=%d civilians=%d reported_guards=%d reported_civilians=%d" % [
		guards.size(), civilians.size(), REPORTED_GUARDS, REPORTED_CIVILIANS,
	]
	if guards.size() != REPORTED_GUARDS or civilians.size() != REPORTED_CIVILIANS:
		print("ROUTE_NPC count_delta %s" % count_text)
	else:
		print("ROUTE_NPC count_matches %s" % count_text)

	var unreachable: Array[String] = []
	# S19 scan, S22 pickpocket, S23 takedown, S20 patrol, plus the guard-bark
	# rows. If nothing is inside NPC_REACH_M, all of them are unreachable.
	if in_range == 0:
		unreachable = ["S19", "S20", "S22", "S23"]
	print("ROUTE_NPC SUMMARY guards=%d civilians=%d nearest_m=%.1f nearest_type=%s nearest_id=%s max_m=%.1f in_range_%.0fm=%d" % [
		guards.size(), civilians.size(), nearest_m if nearest_m != INF else -1.0,
		nearest_type, nearest_name, max_m if max_m != INF else -1.0, NPC_REACH_M, in_range,
	])
	var ok: bool = _fails == 0
	if ok:
		print("ROUTE_NPC PASS checks=%d fails=0 unreachable_beats=%s nearest_m=%.1f" % [
			_checks, ",".join(unreachable) if not unreachable.is_empty() else "none", nearest_m if nearest_m != INF else -1.0,
		])
	else:
		print("ROUTE_NPC FAIL checks=%d fails=%d" % [_checks, _fails])
	mission.queue_free()
	quit(0 if ok else 1)
