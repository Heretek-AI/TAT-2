extends SceneTree
## W10-A INV-1 — red reproduction of five reported UI defects. Investigation
## only: this suite must FAIL on the current tree and go green after the fixes.
##
## Defects under test (all in `game/src/ui/`):
##   1. `PostMatchUI.continue_requested` has no consumer: the screen emits it
##      (post_match_ui.gd:642-644) but never closes, and `hud.gd` connects only
##      `closed` (hud.gd:2369-2383), so pressing Continue does nothing.
##   2. The main menu never restores focus after Tutorial or Settings:
##      `FocusNav.remember()` is called (main_menu.gd:701-717) but `closed` is
##      never connected and `restore()` is never called. Intended pattern:
##      hud.gd:2204-2213.
##   3. ESC on a PostMatch/Progression screen closes it and marks input handled,
##      but the HUD polls the `pause` action in `_process` (hud.gd:2841-2863)
##      and still opens the pause menu behind it. The lockpick guard is
##      `_pause_consumed_frame` (hud.gd:2742, 2841-2846).
##   4. Timeout / collapse renders as "Caught": post_match_ui.gd:309-313 and
##      hud.gd:2335 only know Escaped/Caught, even though mission_controller
##      sets `timed_out` + `timeout_reason` (mission_controller.gd:4656-4657,
##      4688).
##   5. Repeated opens stack hidden `CanvasLayer`s: `hud._open_post_match_xp()`
##      constructs a new PostMatchUI every press and `close()` only hides it
##      (post_match_ui.gd:127-133).
##
## The test drives real nodes: it presses the real Continue button, calls the
## real `_on_settings_pressed()` / `_on_tutorial_pressed()`, delivers a real ESC
## `InputEventKey` to the screen's `_unhandled_input`, and drives the HUD's
## `_process` in play order (input first, then the process tick).
##
## Run:
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 900 tools/godot --headless --path game --script res://tests/test_w10_screens.gd"

const HUD_SCRIPT: String = "res://src/ui/hud.gd"
const POST_MATCH_SCRIPT: String = "res://src/ui/post_match_ui.gd"
const PROGRESSION_SCRIPT: String = "res://src/ui/progression_ui.gd"
const MAIN_MENU_SCRIPT: String = "res://src/ui/main_menu.gd"
const SETTINGS_SCRIPT: String = "res://src/ui/settings_ui.gd"
const TUTORIAL_SCRIPT: String = "res://src/ui/tutorial_ui.gd"

const FocusNavScript := preload("res://src/ui/focus_nav.gd")
const UIStringsScript := preload("res://src/ui/ui_strings.gd")

var fails: int = 0
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _wait(n: int) -> void:
	for _i: int in range(n):
		await process_frame


func _check(ok: bool, what: String, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS: ", what)
	else:
		fails += 1
		print("FAIL: ", what, (" | " + detail) if detail != "" else "")


# --- helpers ---------------------------------------------------------------

func _script_path(node: Node) -> String:
	var s: Script = node.get_script() as Script
	return s.resource_path if s != null else ""


func _children_with_script(parent: Node, path: String) -> Array[Node]:
	var out: Array[Node] = []
	for ch: Node in parent.get_children():
		if _script_path(ch) == path:
			out.append(ch)
	return out


func _find_child_with_script(parent: Node, path: String) -> Node:
	for ch: Node in parent.get_children():
		if _script_path(ch) == path:
			return ch
	return null


func _continue_button(screen: Node) -> Button:
	var by_name: Node = screen.find_child("ContinueButton", true, false)
	if by_name is Button:
		return by_name as Button
	# Fallback: the authored Screen.Continue row, as stored on the button.
	var want: String = str(UIStringsScript.raw("ST_Screens", "Screen.Continue", "Continue")).to_upper()
	for node: Node in screen.find_children("*", "Button", true, false):
		if (node as Button).text.to_upper().find(want) >= 0:
			return node as Button
	return null


func _post_match_status(screen: Node) -> String:
	for node: Node in screen.find_children("PostMatchStatus", "Label", true, false):
		return (node as Label).text
	return ""


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
	Input.action_press("pause")


func _release_pause_action() -> void:
	Input.action_release("pause")


# --- 1. continue_requested has no consumer ---------------------------------

func _continue_standalone_checks() -> void:
	var script: GDScript = load(POST_MATCH_SCRIPT) as GDScript
	_check(script != null, "INV-1a.0 post_match_ui.gd loads")
	if script == null:
		return
	var ui: CanvasLayer = script.new() as CanvasLayer
	ui.name = "W10ContinueScreen"
	root.add_child(ui)
	await _wait(3)
	ui.call("open_result", true, 500, {}, 0)
	await _wait(3)
	var btn: Button = _continue_button(ui)
	_check(btn != null, "INV-1a.1 the Continue button exists (%s)" % (
		btn.name if btn != null else "not found"))
	if btn == null:
		ui.queue_free()
		await _wait(2)
		return
	btn.pressed.emit()
	await _wait(2)
	_check(not bool(ui.call("is_open")),
		"INV-1a.2 pressing Continue closes the post-match screen",
		"is_open=%s" % str(ui.call("is_open")))
	ui.queue_free()
	await _wait(2)


# --- 2. main-menu focus restore --------------------------------------------

func _focus_owner() -> Control:
	return root.gui_get_focus_owner()


func _focus_restore_checks() -> void:
	# The startscreen backdrop is ~2.7k meshes; the focus contract is about
	# Controls (same documented test hook test_focus_walk.gd uses).
	OS.set_environment("TAT2_UI_NO_STAGE", "1")
	var script: GDScript = load(MAIN_MENU_SCRIPT) as GDScript
	_check(script != null, "INV-1b.0 main_menu.gd loads")
	if script == null:
		return
	var menu: Control = script.new() as Control
	root.add_child(menu)
	await _wait(8)
	var first_ok: bool = bool(FocusNavScript.focus_first(menu))
	_check(first_ok, "INV-1b.1 the menu can take focus before opening a modal")

	# --- Settings ---
	menu.call("_on_settings_pressed")
	await _wait(4)
	var settings: Node = _find_child_with_script(menu, SETTINGS_SCRIPT)
	_check(settings != null, "INV-1b.2 SettingsUI opened as a child of the menu")
	if settings != null:
		var inside_before: bool = _focus_owner() != null and settings.is_ancestor_of(_focus_owner())
		_check(inside_before, "INV-1b.3 settings takes focus while open")
		settings.call("close_settings")
		await _wait(4)
	var owner_after_settings: Control = _focus_owner()
	_check(owner_after_settings != null,
		"INV-1b.4 focus is restored after Settings closes (owner=%s)" % (
			owner_after_settings.name if owner_after_settings != null else "null"))
	_check(owner_after_settings != null and menu.is_ancestor_of(owner_after_settings),
		"INV-1b.5 the restored focus owner is inside the main menu")

	# --- Tutorial ---
	# Re-seat focus on the menu so this sub-check is independent of b.4/b.5.
	FocusNavScript.focus_first(menu)
	menu.call("_on_tutorial_pressed")
	await _wait(4)
	var tutorial: Node = _find_child_with_script(menu, TUTORIAL_SCRIPT)
	_check(tutorial != null, "INV-1b.6 TutorialUI opened as a child of the menu")
	if tutorial != null:
		var inside_tut: bool = _focus_owner() != null and tutorial.is_ancestor_of(_focus_owner())
		_check(inside_tut, "INV-1b.7 tutorial takes focus while open")
		tutorial.call("close")
		await _wait(4)
	var owner_after_tutorial: Control = _focus_owner()
	_check(owner_after_tutorial != null,
		"INV-1b.8 focus is restored after the Tutorial closes (owner=%s)" % (
			owner_after_tutorial.name if owner_after_tutorial != null else "null"))
	_check(owner_after_tutorial != null and menu.is_ancestor_of(owner_after_tutorial),
		"INV-1b.9 the restored focus owner is inside the main menu")

	menu.queue_free()
	await _wait(3)


# --- 4. timeout / collapse status (PostMatchUI half) ------------------------

func _post_match_timeout_checks() -> void:
	var script: GDScript = load(POST_MATCH_SCRIPT) as GDScript
	if script == null:
		return
	var ui: CanvasLayer = script.new() as CanvasLayer
	ui.name = "W10TimeoutScreen"
	root.add_child(ui)
	await _wait(3)
	ui.call("open_result", false, 0, {"timed_out": true, "timeout_reason": "TIME EXPIRED"}, 0)
	await _wait(3)
	var text: String = _post_match_status(ui)
	_check(text.find("TIME EXPIRED") >= 0,
		"INV-1d.1 PostMatchUI timeout renders TIME EXPIRED",
		"status='%s'" % text)
	_check(text.find("CAUGHT") < 0,
		"INV-1d.2 PostMatchUI timeout does not render CAUGHT",
		"status='%s'" % text)
	ui.call("open_result", false, 0, {"timed_out": true, "timeout_reason": "MAGIC DOOR COLLAPSED"}, 0)
	await _wait(3)
	text = _post_match_status(ui)
	_check(text.find("MAGIC DOOR COLLAPSED") >= 0,
		"INV-1d.3 PostMatchUI door collapse renders MAGIC DOOR COLLAPSED",
		"status='%s'" % text)
	# Normal capture keeps the authored Caught row (no over-fix).
	ui.call("open_result", false, 0, {}, 0)
	await _wait(3)
	text = _post_match_status(ui)
	_check(text.find("CAUGHT") >= 0,
		"INV-1d.4 PostMatchUI normal capture still renders CAUGHT",
		"status='%s'" % text)
	ui.queue_free()
	await _wait(2)


# --- HUD-backed checks (4 HUD half, 3 ESC/pause, 5 stacking, 1 HUD half) ----

func _hud_status_text(hud: CanvasLayer) -> String:
	var lbl: Label = hud.get("result_lbl") as Label
	return lbl.text if lbl != null else ""


func _hud_timeout_checks(hud: CanvasLayer) -> void:
	hud.call("show_result", false, 0, {"timed_out": true, "timeout_reason": "TIME EXPIRED"})
	await _wait(1)
	var text: String = _hud_status_text(hud)
	_check(text.find("TIME EXPIRED") >= 0,
		"INV-1d.5 HUD result timeout renders TIME EXPIRED",
		"status='%s'" % text)
	_check(text.find("CAUGHT") < 0,
		"INV-1d.6 HUD result timeout does not render CAUGHT",
		"status='%s'" % text)
	hud.call("show_result", false, 0, {"timed_out": true, "timeout_reason": "MAGIC DOOR COLLAPSED"})
	await _wait(1)
	text = _hud_status_text(hud)
	_check(text.find("MAGIC DOOR COLLAPSED") >= 0,
		"INV-1d.7 HUD result door collapse renders MAGIC DOOR COLLAPSED",
		"status='%s'" % text)
	hud.call("show_result", false, 0, {})
	await _wait(1)
	text = _hud_status_text(hud)
	_check(text.find("CAUGHT") >= 0,
		"INV-1d.8 HUD normal capture still renders CAUGHT",
		"status='%s'" % text)
	hud.call("show_result", true, 0, {})
	await _wait(1)
	text = _hud_status_text(hud)
	_check(text.find("ESCAPED") >= 0,
		"INV-1d.9 HUD escape still renders ESCAPED",
		"status='%s'" % text)


func _new_hud() -> CanvasLayer:
	var script: GDScript = load(HUD_SCRIPT) as GDScript
	if script == null:
		return null
	var hud: CanvasLayer = script.new() as CanvasLayer
	hud.name = "W10ScreensHud"
	root.add_child(hud)
	hud.add_to_group("hud")
	await _wait(3)
	# The test drives `_process` by hand so the assertion frame is explicit.
	hud.set_process(false)
	return hud


func _esc_pause_checks(hud: CanvasLayer) -> void:
	# --- 3a. PostMatchUI opened through the HUD itself ----------------------
	hud.call("_open_post_match_xp")
	await _wait(3)
	var screens: Array[Node] = _children_with_script(hud, POST_MATCH_SCRIPT)
	_check(screens.size() >= 1, "INV-1c.0 the HUD opened a PostMatchUI")
	if screens.is_empty():
		return
	var screen: Node = screens.back()
	_check(bool(screen.call("is_open")), "INV-1c.1 the HUD post-match screen is open")
	_press_pause_action()
	screen.call("_unhandled_input", _esc_event())
	hud.call("_process", 0.016)
	_release_pause_action()
	var paused: bool = _tree_paused()
	_check(not paused,
		"INV-1c.2 ESC on the HUD post-match screen must not open the pause menu behind it (paused=%s)" % str(paused))
	_check(not bool(screen.call("is_open")), "INV-1c.3 ESC still closes the post-match screen")
	if paused:
		# Keep the RED run usable: a paused tree would stop the rest of the probe.
		hud.call("_set_paused", false)
	if is_instance_valid(screen) and screen.get_parent() == hud and bool(screen.call("is_open")):
		screen.call("close")
	screen.queue_free()
	await _wait(2)

	# --- 3b. ProgressionUI: same class of defect ----------------------------
	# Opened under the HUD (its live entry point is the Den ledger, which also
	# runs under a HUD). The pause poll must not fire after the screen's ESC.
	var prog_script: GDScript = load(PROGRESSION_SCRIPT) as GDScript
	_check(prog_script != null, "INV-1c.4 progression_ui.gd loads")
	if prog_script != null:
		var prog: CanvasLayer = prog_script.new() as CanvasLayer
		prog.name = "W10ProgressionScreen"
		hud.add_child(prog)
		await _wait(3)
		prog.call("open_progression")
		await _wait(3)
		_check(bool(prog.call("is_open")), "INV-1c.5 the progression screen is open")
		_press_pause_action()
		prog.call("_unhandled_input", _esc_event())
		hud.call("_process", 0.016)
		_release_pause_action()
		var paused_prog: bool = _tree_paused()
		_check(not paused_prog,
			"INV-1c.6 ESC on Progression must not open the pause menu behind it (paused=%s)" % str(paused_prog))
		_check(not bool(prog.call("is_open")), "INV-1c.7 ESC still closes the progression screen")
		if paused_prog:
			hud.call("_set_paused", false)
		prog.queue_free()
		await _wait(2)

	# --- 3c. The guard is not a blanket pause disable -----------------------
	await process_frame
	_press_pause_action()
	hud.call("_process", 0.016)
	_release_pause_action()
	var paused_normal: bool = _tree_paused()
	_check(paused_normal,
		"INV-1c.8 a later pause press with no screen open still pauses (paused=%s)" % str(paused_normal))
	if paused_normal:
		hud.call("_set_paused", false)
	await process_frame
	_check(not _tree_paused(), "INV-1c.9 pause closed again for a clean exit")


func _layer_stacking_checks(hud: CanvasLayer) -> void:
	hud.call("_open_post_match_xp")
	await _wait(2)
	hud.call("_open_post_match_xp")
	await _wait(2)
	var screens: Array[Node] = _children_with_script(hud, POST_MATCH_SCRIPT)
	var visible_count: int = 0
	for s: Node in screens:
		if (s as CanvasLayer).visible:
			visible_count += 1
	_check(screens.size() == 1,
		"INV-1e.1 exactly one PostMatchUI lives under the HUD after two opens (%d)" % screens.size())
	_check(visible_count == 1,
		"INV-1e.2 exactly one PostMatchUI is visible after two opens (%d)" % visible_count)
	for s: Node in screens:
		s.queue_free()
	await _wait(2)


func _hud_continue_checks(hud: CanvasLayer) -> void:
	# Last, because a correct consumer may also return to the Den (deferred
	# scene change) — no later check depends on this HUD.
	hud.call("_open_post_match_xp")
	await _wait(3)
	var screens: Array[Node] = _children_with_script(hud, POST_MATCH_SCRIPT)
	_check(screens.size() >= 1, "INV-1a.3 the HUD opened a PostMatchUI")
	if screens.is_empty():
		return
	var screen: Node = screens.back()
	var conns: Array = screen.get_signal_connection_list("continue_requested")
	_check(conns.size() >= 1,
		"INV-1a.4 the HUD connects continue_requested (connections=%d)" % conns.size())
	var btn: Button = _continue_button(screen)
	_check(btn != null, "INV-1a.5 the HUD post-match screen has a Continue button")
	if btn == null:
		return
	btn.pressed.emit()
	await _wait(2)
	var still_open: bool = is_instance_valid(screen) and bool(screen.call("is_open"))
	_check(not still_open,
		"INV-1a.6 pressing Continue closes the HUD post-match screen",
		"valid=%s is_open=%s" % [str(is_instance_valid(screen)), str(still_open)])


# --- run -------------------------------------------------------------------

func _run() -> void:
	await _continue_standalone_checks()
	await _focus_restore_checks()
	await _post_match_timeout_checks()
	var hud: CanvasLayer = await _new_hud()
	_check(hud != null, "INV-1.0 hud.gd loads and builds headlessly")
	if hud != null:
		await _hud_timeout_checks(hud)
		await _esc_pause_checks(hud)
		await _layer_stacking_checks(hud)
		await _hud_continue_checks(hud)
		hud.queue_free()
		await _wait(2)
	OS.set_environment("TAT2_UI_NO_STAGE", "")
	print("W10_SCREENS_SUMMARY: fails=%d checks=%d" % [fails, checks])
	quit(1 if fails > 0 else 0)
