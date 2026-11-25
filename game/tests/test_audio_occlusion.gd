extends SceneTree
## Footstep / one-shot occlusion regression (W9 hotfix, 2026-11-25).
##
## The live playtest raised, on **every footstep**:
##   SCRIPT ERROR: Trying to assign an array of type "Array[PhysicsBody3D]"
##   to a variable of type "Array[RID]" at audio_manager.gd:_occluded()
## and, because the typed assignment failed, the exclusion list stayed empty:
## the ray then hit the player's own capsule at ~0.32 m, which is below
## OCCLUSION_MIN_HIT_M (0.4), so `_occluded()` returned false and occlusion
## never applied at all. The spam hid a silent feature outage.
##
## This test pins the behaviour, not the log:
##   1. a clear path reports 0 dB;
##   2. a wall between listener and source reports the authored attenuation;
##   3. the player's own feet (distance < 1 m) are never treated as occluded;
##   4. the player capsule is excluded from the ray, so a footstep emitted at
##      the player is not occluded by the player.
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_audio_occlusion.gd

var fails: int = 0
var passed: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		passed += 1
		print("PASS: ", ok_msg)
	else:
		fails += 1
		printerr("FAIL: ", fail_msg)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var am: Node = root.get_node_or_null("/root/AudioManager")
	_check(am != null, "AudioManager autoload present", "AudioManager autoload missing")
	if am == null:
		print("AUDIO_OCCLUSION_SUMMARY fails=%d passed=%d" % [fails, passed])
		quit(1)
		return

	var world := Node3D.new()
	world.name = "OcclusionArena"
	root.add_child(world)

	# The player capsule, in the group the occlusion ray excludes.
	var player := CharacterBody3D.new()
	player.name = "OcclusionPlayer"
	player.add_to_group("player")
	var cap := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = 0.32
	caps.height = 1.82
	cap.shape = caps
	cap.position = Vector3(0.0, 0.91, 0.0)
	player.add_child(cap)
	world.add_child(player)

	# A wall 5 m along +Z, wide enough that the ray cannot miss it.
	var wall := StaticBody3D.new()
	wall.name = "OcclusionWall"
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 4.0, 0.4)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	wall.position = Vector3(0.0, 1.5, 5.0)
	world.add_child(wall)

	for _i: int in range(4):
		await physics_frame

	# A listener outside the capsule: the camera, 1.2 m behind the player. Without
	# the exclusion the ray would pass through the player's own body and report
	# occlusion for a footstep that is merely in front of the player.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.5, -1.2)
	world.add_child(cam)
	cam.make_current()
	await process_frame

	var clear_db: float = float(am.call("occlusion_gain_db", Vector3(0.0, 1.5, -8.0)))
	_check(is_equal_approx(clear_db, 0.0), "clear path -> 0 dB", "clear path reported %.2f dB" % clear_db)

	var blocked_db: float = float(am.call("occlusion_gain_db", Vector3(0.0, 1.5, 9.0)))
	_check(absf(blocked_db) > 0.5, "wall -> attenuation (%.2f dB)" % blocked_db, "wall reported %.2f dB (occlusion never applied)" % blocked_db)

	var feet_db: float = float(am.call("occlusion_gain_db", Vector3(0.0, 0.1, 0.2)))
	_check(is_equal_approx(feet_db, 0.0), "own feet -> 0 dB", "own feet reported %.2f dB" % feet_db)

	# Inside 1.0 m the ray is skipped entirely (emitter at the listener).
	var near_db: float = float(am.call("occlusion_gain_db", Vector3(0.0, 1.5, -1.2)))
	_check(is_equal_approx(near_db, 0.0), "emitter at listener -> 0 dB", "emitter at listener reported %.2f dB" % near_db)

	# The discriminating case: a source in front of the player, listener behind
	# it. The player's capsule is on the segment, so only the exclusion keeps
	# this at 0 dB; a broken/empty exclusion reports the wall attenuation here.
	var through_body_db: float = float(am.call("occlusion_gain_db", Vector3(0.0, 1.5, 0.6)))
	_check(is_equal_approx(through_body_db, 0.0), "player body excluded from the occlusion ray", "player body not excluded: %.2f dB through the capsule" % through_body_db)

	print("AUDIO_OCCLUSION_SUMMARY fails=%d passed=%d" % [fails, passed])
	quit(1 if fails > 0 else 0)
