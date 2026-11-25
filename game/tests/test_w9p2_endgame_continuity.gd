extends SceneTree
## W9-P2 B3 (magic-door continuity): decision = keep the current continuous
## re-arm behaviour, document it, and pin it headless.
##
## Contract under test (escape_gate.gd + mission_controller._rearm_escape_gates):
##   * an authored BP_EscapePoint is dormant during the main window and never
##     extracts; only `activate()` + endgame phase + all objectives complete
##     emits `extracted`;
##   * the 240 s open lifetime is one cycle, not the endgame window: `expire()`
##     closes the cycle and the next endgame tick re-arms it while the endgame
##     is live (at most a one-frame boundary gap; this test proves the re-arm
##     call itself restores availability with no intermediate state);
##   * `collapsed` is terminal: `activate()` refuses forever, no extraction.
##
## Run (never beside another Godot; thermal rule):
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game \
##       --script res://tests/test_w9p2_endgame_continuity.gd"

const ESCAPE_SCRIPT := "res://src/interact/escape_gate.gd"
const MISSION_SCRIPT := "res://src/missions/mission_controller.gd"

var fails: int = 0
var checks: int = 0


class PlayerStub extends CharacterBody3D:
	func _ready() -> void:
		add_to_group("player")
		collision_layer = 2
		collision_mask = 1
		var cap := CapsuleShape3D.new()
		cap.radius = 0.30
		cap.height = 1.70
		var cs := CollisionShape3D.new()
		cs.shape = cap
		cs.position = Vector3(0.0, 0.85, 0.0)
		add_child(cs)


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, ok: String, fail: String = "") -> bool:
	checks += 1
	if cond:
		print("PASS: [endgame] ", ok)
		return true
	fails += 1
	printerr("FAIL: [endgame] ", fail if fail != "" else ok)
	return false


func _wait_physics(frames: int) -> void:
	for _i: int in range(frames):
		await physics_frame


## One real Area3D/body entry. The stub enters at the gate centre, waits for
## the physics step, then leaves. Returns the number of `extracted` signals.
func _overlap(gate: Node, body: Node3D, frames: int = 4) -> int:
	var box: Array = [0]
	var cb: Callable = func() -> void:
		box[0] = int(box[0]) + 1
	gate.connect("extracted", cb)
	body.global_position = Vector3(0.0, 1.0, 0.0)
	await _wait_physics(frames)
	body.global_position = Vector3(40.0, 1.0, 40.0)
	await _wait_physics(3)
	gate.disconnect("extracted", cb)
	return int(box[0])


func _objectives(gs: Node, done: bool) -> void:
	gs.call("set_mission_objectives", [
		{"id": "w9p2_continuity", "target": 1, "current": 1 if done else 0, "done": done},
	], 0)


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("ENDGAME_CONTINUITY FAIL: GameState autoload missing")
		quit(1)
		return
	gs.call("reset_run", 2, "guildhall")
	gs.set("state", "playing")
	_objectives(gs, true)
	gs.call("begin_endgame", 480.0)
	_check(str(gs.get("phase")) == "endgame",
		"test starts in the endgame phase", "phase=%s" % str(gs.get("phase")))
	_check(bool(gs.call("are_all_objectives_complete")),
		"objectives complete fixture is valid", "objectives not complete")
	_check(str(gs.get("state")) == "playing", "GameState.state is playing")

	var gate: Node = (load(ESCAPE_SCRIPT) as GDScript).new() as Node
	gate.name = "W9P2ContinuityGate"
	root.add_child(gate)
	var body: PlayerStub = PlayerStub.new() as PlayerStub
	body.name = "W9P2ContinuityPlayer"
	root.add_child(body)
	await _wait_physics(4)
	_check(is_equal_approx(float(gate.get("open_duration_sec")), 240.0),
		"gate uses the authored BP_EscapePoint 240 s cycle",
		"open_duration=%.1f" % float(gate.get("open_duration_sec")))

	# 1. Dormant gate in the endgame never extracts.
	var n: int = await _overlap(gate, body)
	print("ENDGAME_CONTINUITY dormant extracted=%d available=%s phase=%s" % [
		n, str(gate.call("is_available")), str(gs.get("phase"))])
	_check(n == 0, "a dormant gate emits nothing in the endgame", "dormant gate emitted %d" % n)
	_check(int(gate.get("use_count")) == 0, "dormant overlap is not a use", "use_count=%d" % int(gate.get("use_count")))

	# 2. Activated + endgame but objectives incomplete: still no extraction.
	_objectives(gs, false)
	_check(not bool(gs.call("are_all_objectives_complete")), "objectives can be made incomplete")
	_check(bool(gate.call("activate")), "activate() summons the gate")
	n = await _overlap(gate, body)
	print("ENDGAME_CONTINUITY incomplete extracted=%d use_count=%d" % [n, int(gate.get("use_count"))])
	_check(n == 0, "activated gate with incomplete objectives emits nothing",
		"incomplete-objective gate emitted %d" % n)

	# 3. Activated + endgame + objectives complete: exactly one extraction.
	_objectives(gs, true)
	n = await _overlap(gate, body)
	print("ENDGAME_CONTINUITY complete extracted=%d use_count=%d" % [n, int(gate.get("use_count"))])
	_check(n == 1, "one body entry on an available endgame gate emits exactly one extracted",
		"emitted %d" % n)
	_check(int(gate.get("use_count")) == 1, "extraction counts one use", "use_count=%d" % int(gate.get("use_count")))

	# 4. 240 s cycle -> re-arm on the next endgame tick, no state loss.
	gs.call("set_escape_markers", [{
		"gate": gate,
		"marker_index": 0,
		"activated": true,
		"expired": false,
	}])
	var count_before: int = int(gs.call("active_escape_count"))
	var rearm_before: int = int(gate.get("rearm_count"))
	gate.call("_process", 240.1)
	_check(bool(gate.get("expired")) and not bool(gate.call("is_available")),
		"the authored 240 s cycle expires the gate",
		"expired=%s available=%s" % [str(gate.get("expired")), str(gate.call("is_available"))])
	var mc: Node = (load(MISSION_SCRIPT) as GDScript).new() as Node
	var rearmed: int = int(mc.call("_rearm_escape_gates"))
	mc.free()
	print("ENDGAME_CONTINUITY rearm returned=%d count=%d->%d rearm_count=%d->%d available=%s phase=%s" % [
		rearmed, count_before, int(gs.call("active_escape_count")),
		rearm_before, int(gate.get("rearm_count")), str(gate.call("is_available")), str(gs.get("phase"))])
	_check(rearmed == 1, "_rearm_escape_gates re-arms the expired marker", "rearmed=%d" % rearmed)
	# No await between activate() and this assertion: the re-arm call itself
	# restores availability, so the endgame tick has no gap beyond one frame.
	_check(bool(gate.call("is_available")),
		"re-arm restores is_available() immediately (same tick)",
		"gate unavailable after re-arm")
	_check(int(gate.get("rearm_count")) == rearm_before + 1,
		"rearm_count grows on the re-arm", "rearm_count=%d want %d" % [int(gate.get("rearm_count")), rearm_before + 1])
	_check(int(gs.call("active_escape_count")) == count_before,
		"GameState.active_escape_count() is unchanged across the re-arm",
		"count %d -> %d" % [count_before, int(gs.call("active_escape_count"))])
	var markers: Array = gs.get("escape_markers") as Array
	var rec: Dictionary = markers[0] as Dictionary if not markers.is_empty() else {}
	_check(rec.get("expired") == false and rec.get("activated") == true,
		"marker record stays activated/not-expired for HUD parity",
		"record=%s" % str(rec))

	# 5. Resolved phase: the still-available gate emits nothing.
	gs.call("resolve_phase")
	n = await _overlap(gate, body)
	print("ENDGAME_CONTINUITY resolved extracted=%d phase=%s" % [n, str(gs.get("phase"))])
	_check(str(gs.get("phase")) == "resolved", "resolve_phase reaches resolved",
		"phase=%s" % str(gs.get("phase")))
	_check(n == 0, "a resolved run emits nothing on a body overlap", "resolved gate emitted %d" % n)

	# 6. Collapse is terminal: no re-activation, no extraction.
	var rearm_at_collapse: int = int(gate.get("rearm_count"))
	gate.call("collapse")
	_check(bool(gate.get("collapsed")) and not bool(gate.call("is_available")),
		"collapse makes the gate unavailable", "collapsed=%s" % str(gate.get("collapsed")))
	_check(not bool(gate.call("activate")),
		"activate() refuses forever after collapse", "collapsed gate re-activated")
	_check(int(gate.get("rearm_count")) == rearm_at_collapse,
		"a collapsed gate never re-arms", "rearm_count moved %d -> %d" % [rearm_at_collapse, int(gate.get("rearm_count"))])
	n = await _overlap(gate, body)
	print("ENDGAME_CONTINUITY collapsed extracted=%d activated=%s active=%s" % [
		n, str(gate.get("activated")), str(gate.get("active"))])
	_check(n == 0, "a collapsed gate emits nothing on a body overlap", "collapsed gate emitted %d" % n)

	var ok: bool = fails == 0
	print("ENDGAME_CONTINUITY ", "PASS" if ok else "FAIL", " checks=%d" % checks)
	quit(0 if ok else 1)
