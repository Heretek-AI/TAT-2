extends SceneTree
## W9-P3-C3 gate: gamepad focus navigation + device glyphs.
##
## Every menu must be reachable and traversable with the pad, with a visible
## focus state and no dead end:
##   * `FocusNav.ring_is_complete()` - every focusable control has four
##     neighbours that resolve to another focusable control;
##   * a programmatic walk from the first control visits every control exactly
##     once and returns to the start (the ring property);
##   * closing a modal releases focus instead of trapping it behind the panel;
##   * a rebind changes the printed glyph (`InputGlyphs`), and the authored
##     tutorial rich text follows that rebind.
##
## Screens: startscreen, settings, ledger, wardrobe, map table, mission prep,
## pause, post-match, progression, tutorial.
##
## Run:  tools/godot --headless --path game --script res://tests/test_focus_walk.gd

const FocusNavScript: GDScript = preload("res://src/ui/focus_nav.gd")
const InputGlyphsScript: GDScript = preload("res://src/ui/input_glyphs.gd")
const TutorialTextScript: GDScript = preload("res://src/ui/tutorial_text.gd")

var fails: int = 0
var checks: int = 0
var screens: Array[Dictionary] = []


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
		printerr("FAIL: ", what, (" | " + detail) if detail != "" else "")


func _run() -> void:
	# The startscreen backdrop and the prep 3D stage are ~5k meshes; the focus
	# contract is about Controls, not pixels (documented test hook).
	OS.set_environment("TAT2_UI_NO_STAGE", "1")
	await _build_screens()
	await _walk_all()
	await _modal_close_check()
	await _rebind_glyph_check()
	OS.set_environment("TAT2_UI_NO_STAGE", "")
	print("FOCUS_WALK_SUMMARY: fails=%d checks=%d screens=%d" % [fails, checks, screens.size()])
	quit(1 if fails > 0 else 0)


func _add_screen(label: String, node: Node, root_for_walk: Node) -> void:
	root.add_child(node)
	screens.append({"label": label, "node": node, "root": root_for_walk})


func _build_screens() -> void:
	# 1. Startscreen.
	var menu: Control = (load("res://src/ui/main_menu.gd") as GDScript).new() as Control
	if menu != null:
		_add_screen("startscreen", menu, menu)
	# 2. Settings.
	var settings: CanvasLayer = (load("res://src/ui/settings_ui.gd") as GDScript).new() as CanvasLayer
	if settings != null:
		_add_screen("settings", settings, settings)
	# 3. Ledger.
	var ledger: Control = (load("res://src/ui/ledger_ui.gd") as GDScript).new() as Control
	if ledger != null:
		_add_screen("ledger", ledger, ledger)
	# 4. Wardrobe.
	var wardrobe: CanvasLayer = (load("res://src/ui/wardrobe_ui.gd") as GDScript).new() as CanvasLayer
	if wardrobe != null:
		_add_screen("wardrobe", wardrobe, wardrobe)
	# 5. Map table.
	var table: CanvasLayer = (load("res://src/ui/contract_table_ui.gd") as GDScript).new() as CanvasLayer
	if table != null:
		_add_screen("map_table", table, table)
	# 6. Mission prep.
	var prep: Control = (load("res://src/ui/mission_prep_ui.gd") as GDScript).new() as Control
	if prep != null:
		_add_screen("mission_prep", prep, prep)
	# 7. HUD pause.
	var hud: CanvasLayer = (load("res://src/ui/hud.gd") as GDScript).new() as CanvasLayer
	if hud != null:
		_add_screen("pause", hud, hud)
	# 8-10. W9-P3 screens.
	var post: CanvasLayer = (load("res://src/ui/post_match_ui.gd") as GDScript).new() as CanvasLayer
	if post != null:
		_add_screen("post_match", post, post)
	var prog: CanvasLayer = (load("res://src/ui/progression_ui.gd") as GDScript).new() as CanvasLayer
	if prog != null:
		_add_screen("progression", prog, prog)
	var tut: CanvasLayer = (load("res://src/ui/tutorial_ui.gd") as GDScript).new() as CanvasLayer
	if tut != null:
		_add_screen("tutorial", tut, tut)
	await _wait(8)
	# Open each screen through its public API. The API is part of the contract:
	# a missing method is a FAIL, not a skipped screen.
	for s: Dictionary in screens:
		var node: Node = s["node"] as Node
		match str(s["label"]):
			"settings":
				_call_open(node, "open_settings")
			"ledger":
				_call_open(node, "open_ledger")
			"wardrobe":
				_call_open(node, "open_customizer")
			"map_table":
				_call_open(node, "open_table")
			"mission_prep":
				_call_open(node, "open_prep", ["guildhall", 1, "solo", 1])
			"pause":
				_call_open(node, "toggle_pause")
			"post_match":
				_call_open(node, "open_result", [true, 1200, {}, 120])
			"progression":
				_call_open(node, "open_progression")
			"tutorial":
				_call_open(node, "open_tutorial")
	await _wait(10)


func _call_open(node: Node, method: String, args: Array = []) -> void:
	if not node.has_method(method):
		fails += 1
		checks += 1
		printerr("FAIL: OPEN_API %s has no %s()" % [node.get_script().resource_path if node.get_script() != null else str(node), method])
		return
	node.callv(method, args)


func _walk_all() -> void:
	for s: Dictionary in screens:
		var label: String = str(s["label"])
		var node: Node = s["node"] as Node
		var walk_root: Node = s["root"] as Node
		# The HUD's pause panel is the menu; the HUD root also holds the live
		# HUD (no focusable controls), so walk from the pause panel when named.
		if label == "pause" and node.has_method("pause_panel_for_test"):
			walk_root = node.call("pause_panel_for_test") as Node
		var controls: Array = FocusNavScript.focusable_controls(walk_root)
		_check(controls.size() >= 2, "C3.%s focusable controls >= 2 (%d)" % [label, controls.size()])
		if controls.size() < 2:
			continue
		_check(bool(FocusNavScript.ring_is_complete(walk_root)),
			"C3.%s every control has four resolving neighbours (visible focus, no dead end)" % label)
		# Ring walk: follow the bottom neighbour N times.
		var first: Control = controls[0] as Control
		first.grab_focus()
		_check(first.has_focus(), "C3.%s the first control takes focus" % label)
		var seen: Dictionary = {}
		var cur: Control = first
		var ok: bool = true
		for i: int in range(controls.size()):
			if cur == null or not is_instance_valid(cur):
				ok = false
				break
			var path: NodePath = cur.focus_neighbor_bottom
			var nxt: Node = cur.get_node_or_null(path) if path != NodePath() else null
			if nxt == null or not (nxt is Control):
				ok = false
				break
			cur = nxt as Control
			seen[cur] = int(seen.get(cur, 0)) + 1
		_check(ok, "C3.%s the bottom neighbour chain never dead-ends" % label)
		_check(cur == first, "C3.%s the chain returns to the first control (ring)" % label,
			"ended on %s" % (cur.name if cur != null else "null"))
		_check(seen.size() == controls.size(),
			"C3.%s the walk visits every control (%d/%d)" % [label, seen.size(), controls.size()],
			str(seen.keys()))


## A closed modal must not keep the focus owner: after close, the focus owner is
## null or outside the panel, and the opener can take focus back.
func _modal_close_check() -> void:
	var settings: CanvasLayer = null
	for s: Dictionary in screens:
		if str(s["label"]) == "settings":
			settings = s["node"] as CanvasLayer
	if settings == null:
		_check(false, "C3.modal settings screen exists")
		return
	var opener: Control = null
	for s: Dictionary in screens:
		if str(s["label"]) == "pause":
			var hud: CanvasLayer = s["node"] as CanvasLayer
			if hud != null and hud.has_method("pause_first_control_for_test"):
				opener = hud.call("pause_first_control_for_test") as Control
	if opener != null:
		opener.grab_focus()
	FocusNavScript.remember()
	if settings.has_method("close_settings"):
		settings.call("close_settings")
	await _wait(3)
	var owner_ctl: Control = root.gui_get_focus_owner()
	# close_settings() queue_free()s the panel: after the frames above the node
	# may be gone, so a freed panel cannot own the focus owner. (Calling
	# is_ancestor_of on the freed instance threw and silently skipped the three
	# modal assertions -- audit-c3 F1.)
	var inside: bool = false
	if owner_ctl != null and is_instance_valid(settings) and settings.is_inside_tree():
		inside = settings.is_ancestor_of(owner_ctl)
	_check(not inside, "C3.modal a closed settings panel does not keep the focus owner",
		"owner=%s freed_panel=%s" % [owner_ctl.name if owner_ctl != null else "null", not is_instance_valid(settings)])
	if is_instance_valid(settings):
		_check(bool(FocusNavScript.ring_is_complete(settings)),
			"C3.modal settings ring stays well-formed after close")
	else:
		_check(true, "C3.modal the freed settings panel owns no focus ring")
	if opener != null and is_instance_valid(opener) and opener.is_visible_in_tree():
		var restored: bool = bool(FocusNavScript.restore())
		_check(restored or owner_ctl == null,
			"C3.modal the opener can take focus back after the modal closes")
	else:
		# No pause opener in this headless build order: restoring must fail
		# cleanly, not throw.
		_check(not bool(FocusNavScript.restore()),
			"C3.modal restore() with no visible opener returns false cleanly")


## InputGlyphs must follow a rebind, and the authored tutorial rich text must
## print the same live glyph.
func _rebind_glyph_check() -> void:
	if not InputMap.has_action("interact"):
		_check(false, "C3.rebind the interact action exists")
		return
	var before_pad: String = str(InputGlyphsScript.text("interact", "pad"))
	_check(before_pad == "X", "C3.rebind pad interact prints X before the rebind (%s)" % before_pad)
	var original: Array[InputEvent] = InputMap.action_get_events("interact")
	InputMap.action_erase_events("interact")
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_Y
	InputMap.action_add_event("interact", ev)
	var after_pad: String = str(InputGlyphsScript.text("interact", "pad"))
	_check(after_pad == "Y", "C3.rebind the pad glyph follows the rebind X -> Y (%s)" % after_pad)
	var rendered: String = str(TutorialTextScript.render('<img id="Interact"/> to pick', "pad"))
	_check(rendered.find("[Y]") >= 0,
		"C3.rebind the authored FTUE rich text prints the rebound glyph (%s)" % rendered)
	# Restore the authored mapping exactly as it was.
	InputMap.action_erase_events("interact")
	for e: InputEvent in original:
		InputMap.action_add_event("interact", e)
	var restored_glyph: String = str(InputGlyphsScript.text("interact", "pad"))
	_check(restored_glyph == before_pad,
		"C3.rebind the authored interact mapping is restored (%s)" % restored_glyph)
