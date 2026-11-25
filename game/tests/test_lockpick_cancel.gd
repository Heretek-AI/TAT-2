extends SceneTree
## W9-P2 C1: `[ESC] CANCEL` while lockpicking must cancel the minigame and must
## NOT open the pause menu in the same frame.
##
## The shipped bug: `hud._input` consumes ESC for the lockpick (and clears
## `_lockpick_active`), then the same frame's `hud._process` still sees
## `Input.is_action_just_pressed("pause")` and falls through to `_toggle_pause()`
## because the lockpick branch is already false. One ESC press therefore
## cancelled the pick AND opened the pause menu over the dialog.
##
## This suite drives the real HUD `_input` / `_process` pair for one idle frame
## (order matches play: events are delivered before the frame's process tick),
## then proves the guard is not a blanket pause disable by pausing with a
## normal ESC on a later frame.
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/test_lockpick_cancel.gd"

const HUD_SCRIPT := "res://src/ui/hud.gd"
const CONTAINER_SCRIPT := "res://src/interact/loot_container.gd"

var fails: int = 0
var checks: int = 0


## Only the player surface the HUD and the container touch.
class PlayerStub extends Node3D:
	var lockpicking_calls: Array = []
	var damage_taken: float = 0.0

	func set_lockpicking_active(active: bool) -> void:
		lockpicking_calls.append(active)

	func take_damage(amount: float) -> void:
		damage_taken += amount


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		fails += 1
		print("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _esc_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	ev.echo = false
	return ev


func _tree_paused() -> bool:
	return root.get_tree().paused


func _press_pause_action() -> void:
	# The HUD reads the Input singleton, not the event, for the pause action.
	# This is the same "just pressed this frame" state a real key press leaves.
	Input.action_press("pause")


func _release_pause_action() -> void:
	Input.action_release("pause")


func _run() -> void:
	var hud_script: GDScript = load(HUD_SCRIPT) as GDScript
	var container_script: GDScript = load(CONTAINER_SCRIPT) as GDScript
	_check(hud_script != null, "hud.gd loads")
	_check(container_script != null, "loot_container.gd loads")

	var hud: CanvasLayer = hud_script.new() as CanvasLayer
	hud.name = "CancelTestHud"
	root.add_child(hud)
	hud.add_to_group("hud")
	var player := PlayerStub.new()
	player.name = "CancelTestPlayer"
	root.add_child(player)
	player.add_to_group("player")
	await process_frame
	# The test drives `_process` by hand so the assertion frame is explicit.
	hud.set_process(false)

	# --- 1. HUD-level minigame: ESC cancels without pausing -----------------
	var got: Array = []
	hud.call("start_lockpick_minigame", 3, "Safe Lock",
		func(success: bool = true) -> void: got.append(success))
	_check(bool(hud.call("is_lockpicking")), "LV3 lockpick starts (is_lockpicking)")
	_check(player.lockpicking_calls.size() == 1 and player.lockpicking_calls.back() == true,
		"starting the pick tells the player set_lockpicking_active(true)")

	_press_pause_action()
	hud.call("_input", _esc_event())
	hud.call("_process", 0.016)
	_release_pause_action()

	var paused_after_cancel: bool = _tree_paused()
	_check(not paused_after_cancel,
		"ESC while lockpicking must not pause the tree (got paused=%s)" % str(paused_after_cancel))
	_check(not bool(hud.call("is_lockpicking")), "ESC cancels the lockpick (is_lockpicking false)")
	_check(got.size() == 1 and got[0] == false,
		"cancel callback received false (got %s)" % str(got))
	_check(player.lockpicking_calls.size() == 2 and player.lockpicking_calls.back() == false,
		"cancel tells the player set_lockpicking_active(false)")
	if paused_after_cancel:
		# Keep the RED run usable: a paused tree would stop the rest of the probe.
		hud.call("_set_paused", false)

	# --- 2. A real locked container stays locked after the cancel -----------
	var container: Area3D = container_script.new() as Area3D
	container.name = "CancelTestChest"
	root.add_child(container)
	container.call("set_locked", true, 2)
	_check(bool(container.get("locked")) and int(container.get("lock_level")) == 2,
		"fixture container starts locked at level 2")
	container.call("interact", player)
	_check(bool(hud.call("is_lockpicking")), "container.interact opens the HUD minigame")
	_check(bool(container.get("is_lockpicking")), "container marks itself lockpicking")

	_press_pause_action()
	hud.call("_input", _esc_event())
	hud.call("_process", 0.016)
	_release_pause_action()

	var paused_after_container: bool = _tree_paused()
	_check(not paused_after_container,
		"ESC during a container pick must not pause the tree (got paused=%s)" % str(paused_after_container))
	_check(bool(container.get("locked")),
		"the container stays locked after the cancel")
	_check(int(container.get("lock_level")) == 2,
		"the container keeps its authored level 2 after the cancel")
	_check(not bool(container.get("is_lockpicking")),
		"the container is no longer lockpicking after the cancel")
	_check(not bool(hud.call("is_lockpicking")), "the HUD minigame is closed after the cancel")
	if paused_after_container:
		hud.call("_set_paused", false)

	# --- 3. The guard is not a blanket pause disable ------------------------
	# A later frame (different frame stamp) with no lockpick must still pause.
	await process_frame
	_press_pause_action()
	hud.call("_input", _esc_event())
	hud.call("_process", 0.016)
	_release_pause_action()
	var paused_normal: bool = _tree_paused()
	_check(paused_normal, "a later ESC with no lockpick still opens the pause menu")
	if paused_normal:
		hud.call("_set_paused", false)
	await process_frame
	_check(not _tree_paused(), "pause closed again for a clean exit")

	container.queue_free()
	player.queue_free()
	hud.queue_free()
	await process_frame

	if fails == 0:
		print("LOCKPICK_CANCEL PASS checks=%d" % checks)
	else:
		print("LOCKPICK_CANCEL FAIL checks=%d fails=%d" % [checks, fails])
	quit(0 if fails == 0 else 1)
