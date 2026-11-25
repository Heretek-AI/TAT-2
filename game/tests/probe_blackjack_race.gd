extends SceneTree
## Blackjack winnability probe (T11-AI, RE-I-02a / RE-I-14).
##
## The port invented a 3.5 m all-round sight bypass (`angle > fov*0.5 and dist >
## 3.5`) against the authored MinimumSightRadius of 100 cm. Inside the 2.4 m
## blackjack reach that made every rear approach "seen", and the detection ramp
## then beat the 0.45 s takedown hold: at 2.4 m the authored ramp runs
## 100 / (0.4 * 2.4) = 104.2 points/s, so ALERTED (45) lands at 0.432 s, before
## the hold completes, and `ever_spotted` forfeits the GHOST bonus.
##
## Phase A is the geometry proof (stub player, no animation load): the old gate
## and the authored frustum are both evaluated on the same pose.
## Phase B is the behavioural proof: real thief, live physics, the real
## 0.45 s hold accumulation and the real `_perform_hold_action` (suite 55c froze
## physics and called `_try_blackjack` directly, so neither raced).
##
## Run: tools/godot --headless --path game --script res://tests/probe_blackjack_race.gd
## Exits 0 when the takedown is winnable, 1 otherwise.

const GUARD_SCRIPT := "res://src/ai/guard_ai.gd"
const THIEF_SCRIPT := "res://src/player/thief_character.gd"
const HOLD_SEC: float = 0.45
const REACH_M: float = 2.2
const OLD_BYPASS_M: float = 3.5

var fails: int = 0


func _initialize() -> void:
	await process_frame
	var root: Window = get_root()
	if root == null:
		printerr("PROBE FAIL: no root")
		quit(1)
		return
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		printerr("PROBE FAIL: GameState autoload missing")
		quit(1)
		return
	gs.set("state", "playing")
	_build_floor(root, Vector3(0, -0.55, 0))
	_build_floor(root, Vector3(100, -0.55, 0))
	await physics_frame

	await _phase_a_geometry(root)
	await _phase_b_hold(root)
	print("BLACKJACK_PROBE ", "PASS" if fails == 0 else "FAIL", " fails=", fails)
	quit(0 if fails == 0 else 1)


func _build_floor(root: Node, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	body.add_child(shape)
	body.position = at
	root.add_child(body)


func _stub_player(root: Node, at: Vector3) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "ProbePlayer"
	p.collision_layer = 2
	p.collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	p.add_child(shape)
	p.position = at
	root.add_child(p)
	return p


## Phase A: the same rear pose evaluated by the invented gate and by the
## authored frustum. The guard faces -Z, so "behind" is +Z.
func _phase_a_geometry(root: Node) -> void:
	var guard: CharacterBody3D = (load(GUARD_SCRIPT) as GDScript).new() as CharacterBody3D
	guard.name = "ProbeGuardA"
	guard.position = Vector3(0, 0, 0)
	guard.rotation = Vector3.ZERO
	guard.set("patrol_points", [Vector3(0, 0, 0)])
	root.add_child(guard)
	await process_frame
	var player: CharacterBody3D = _stub_player(root, Vector3(0, 0, REACH_M))
	await physics_frame
	var sees_now: bool = bool(guard.call("_can_see_player", player))
	# The old model on the same pose: the cone is bypassed for anything inside
	# 3.5 m, so a 2.2 m rear approach is seen.
	var to_player: Vector3 = player.global_position - guard.global_position
	var fwd: Vector3 = -guard.global_transform.basis.z
	fwd.y = 0.0
	var dist: float = to_player.length()
	var angle: float = rad_to_deg(fwd.angle_to(to_player.normalized()))
	var fov: float = float(guard.get("fov_deg"))
	var old_seen: bool = (angle <= fov * 0.5) or (dist <= OLD_BYPASS_M)
	var ramp_rate: float = 100.0 / (0.4 * dist)
	var seconds_to_alerted: float = 45.0 / ramp_rate
	print("[phase A] pose: dist=%.2f m angle=%.1f deg fov=%.1f" % [dist, angle, fov])
	print("[phase A] inhabited 3.5 m bypass -> seen=", old_seen, " (ramp ", snappedf(ramp_rate, 0.1), " pts/s, ALERTED at ", snappedf(seconds_to_alerted, 0.001), " s vs hold ", HOLD_SEC, " s)")
	print("[phase A] authored frustum    -> seen=", sees_now)
	if old_seen and seconds_to_alerted < HOLD_SEC:
		print("[phase A] reproduced: the invented gate sees the rear approach and the ramp wins the race")
	else:
		printerr("[phase A] could not reproduce the invented gate")
		fails += 1
	if sees_now:
		printerr("[phase A] FAIL: a rear approach inside the blackjack reach is still seen by the authored frustum")
		fails += 1
	else:
		print("[phase A] PASS: rear approach outside the authored frustum")
	player.queue_free()
	guard.queue_free()
	await process_frame


## Phase B: the real hold. A live thief behind a live guard holds F for the
## authored duration; the guard's own physics ticks, so a detection ramp race
## would show up as a non-KO or a set `ever_spotted`.
func _phase_b_hold(root: Node) -> void:
	var gs: Node = root.get_node("GameState")
	var guard: CharacterBody3D = (load(GUARD_SCRIPT) as GDScript).new() as CharacterBody3D
	guard.name = "ProbeGuardB"
	guard.position = Vector3(100, 0, 0)
	guard.rotation = Vector3.ZERO
	guard.set("patrol_points", [Vector3(100, 0, 0)])
	guard.set("patrol_speed", 0.0)
	guard.set("suspicious_speed", 0.0)
	guard.set("chase_speed", 0.0)
	root.add_child(guard)
	var player: Node3D = (load(THIEF_SCRIPT) as GDScript).new() as Node3D
	player.name = "ProbeThief"
	player.position = Vector3(100, 0, REACH_M)
	root.add_child(player)
	await process_frame
	await physics_frame
	guard.set("detection", 0.0)
	guard.set("state", 0)
	gs.set("ever_spotted", false)
	var prompt: String = str(player.call("get_look_secondary_prompt"))
	print("[phase B] prompt=", prompt)
	# Exactly what the input handler does on a press: open the hold clock.
	player.set("_interact_hold_ms", Time.get_ticks_msec())
	player.set("_interact_hold_sec", 0.0)
	var frames: int = 0
	while float(player.get("_interact_hold_sec")) < HOLD_SEC and frames < 240:
		await physics_frame
		frames += 1
	var held: float = float(player.get("_interact_hold_sec"))
	var seen_during_hold: bool = bool(guard.call("_can_see_player", player))
	var detection_during_hold: float = float(guard.get("detection"))
	var peak_detection: float = 0.0
	# Release: the handler reads the physics-accumulated seconds and fires.
	player.set("_interact_hold_ms", -1)
	player.set("_interact_hold_sec", -1.0)
	player.call("_perform_hold_action")
	peak_detection = maxf(detection_during_hold, float(guard.get("detection")))
	var ko: bool = int(guard.get("state")) == 5
	var spotted: bool = bool(gs.get("ever_spotted"))
	var takedowns: int = int(gs.get("takedowns"))
	print("[phase B] held=%.3f s seen_during_hold=%s det=%.2f ko=%s ever_spotted=%s takedowns=%d" % [
		held, str(seen_during_hold), peak_detection, str(ko), str(spotted), takedowns,
	])
	if held + 0.0001 < HOLD_SEC:
		printerr("[phase B] FAIL: hold never reached the authored duration")
		fails += 1
	if seen_during_hold:
		printerr("[phase B] FAIL: guard saw the thief during the hold")
		fails += 1
	if not ko:
		printerr("[phase B] FAIL: takedown did not knock the guard out")
		fails += 1
	if spotted:
		printerr("[phase B] FAIL: ever_spotted was set by the takedown")
		fails += 1
	if peak_detection > 0.0:
		printerr("[phase B] FAIL: detection ramp ran during the hold (", peak_detection, ")")
		fails += 1
	if fails == 0:
		print("[phase B] PASS: authored %.2f s hold inside the %.1f m reach knocks out an unaware guard without ever_spotted" % [HOLD_SEC, REACH_M])
	player.queue_free()
	guard.queue_free()
	await process_frame
