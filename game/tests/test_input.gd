extends SceneTree
## T06-INPUT headless gates: authored bindings, gamepad resolution, rebinding,
## glyph formatting, the sensitivity ladder, and modal input gating.
##
##   tools/godot --headless --path game --script res://tests/test_input.gd
##
## Prints `INPUT_SUMMARY: fails=<N>` and exits non-zero on failure.

var _fails: int = 0
var _checks: int = 0


func _initialize() -> void:
	await process_frame
	var ctx: Node = get_root().get_node_or_null("InputContext")
	var gd: Node = get_root().get_node_or_null("GameData")
	if ctx == null or gd == null:
		printerr("FAIL: InputContext/GameData autoloads missing")
		print("INPUT_SUMMARY: fails=1")
		quit(1)
		return
	var saved_overrides: Dictionary = ctx.call("overrides") as Dictionary

	_check_table()
	_check_resolution()
	_check_five_key_contradictions()
	_check_glyphs()
	_check_rebind_round_trip()
	_check_sensitivity_ladder()
	await _check_modal_gating(ctx)
	await _check_player_gate(ctx)
	await _check_settings_ui()

	# Restore the caller's bindings (the rebind tests mutate the live InputMap).
	ctx.call("set_overrides", saved_overrides, true)
	print("INPUT_SUMMARY: fails=%d checks=%d" % [_fails, _checks])
	quit(0 if _fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS: " + what)
	else:
		_fails += 1
		printerr("FAIL: " + what)


func _eq_str_list(a: Array, b: Array, what: String) -> void:
	var aa: Array = _dedupe(a)
	var bb: Array = _dedupe(b)
	aa.sort()
	bb.sort()
	_expect(aa == bb, "%s (got %s want %s)" % [what, str(aa), str(bb)])


func _dedupe(values: Array) -> Array:
	var out: Array = []
	for v: Variant in values:
		if not out.has(v):
			out.append(v)
	return out


# ---------------------------------------------------------------------------
# 1. Authored table coverage (S2: 3 IMCs, 91 rows, 52 actions)
# ---------------------------------------------------------------------------

func _check_table() -> void:
	_expect(InputActions.AUTHORED_ACTIONS.size() == 52, "table declares 52 authored IA_* actions")
	var seen: Array[String] = []
	for r: Dictionary in InputActions.rows():
		if str(r.get("ctx", "")) == "legacy":
			continue # DefaultInput.ini ActionMappings (Pause), not Enhanced Input
		var ia: String = str(r.get("ia", ""))
		if not seen.has(ia):
			seen.append(ia)
	_expect(seen.size() == 52, "rows cover all 52 authored actions (got %d)" % seen.size())
	var missing: Array[String] = []
	for ia: String in InputActions.AUTHORED_ACTIONS:
		if not seen.has(ia):
			missing.append(ia)
	_expect(missing.is_empty(), "no authored action dropped (missing %s)" % str(missing))
	var ids: Array[String] = InputActions.ids()
	_expect(ids.size() >= 30, "port action ids present (%d)" % ids.size())
	var table: Dictionary = InputActions.load_table()
	_expect(str(table.get("source", "")) == "authored", "table source falls back to the authored mirror (T01 JSON absent)")
	_expect((table.get("rows", []) as Array).size() == InputActions.rows().size(), "load_table returns the full row set")
	# Move is split into four 1D port actions; the rest keep one row per action.
	_expect(InputActions.row_for("move_forward").get("deadzone", 0.0) == 0.18, "move deadzone is the authored 0.18")
	_expect(InputActions.row_for("look_gamepad").get("deadzone", 0.0) == 0.12, "look deadzone is the authored 0.12")
	_expect(InputActions.PAD_TURN_H_DEG_S == 90.0 and InputActions.PAD_TURN_V_DEG_S == 52.0, "authored pad turn speeds 90/52 deg-per-s")
	_expect(InputActions.HOLD_SECONDS == 0.2, "authored hold 0.2 s")


# ---------------------------------------------------------------------------
# 2. InputMap resolution on both devices (the P0 red proof)
# ---------------------------------------------------------------------------

func _check_resolution() -> void:
	var expected: Dictionary = {
		"interact": {"kb": ["F"], "pad": ["Gamepad_FaceButton_Left"]},
		"crouch": {"kb": ["LeftControl"], "pad": ["Gamepad_FaceButton_Right"]},
		"jump": {"kb": ["SpaceBar"], "pad": ["Gamepad_FaceButton_Bottom"]},
		"sprint": {"kb": ["LeftShift"], "pad": ["Gamepad_LeftThumbstick"]},
		"attack": {"kb": ["C"], "pad": ["Gamepad_RightShoulder"]},
		"block": {"kb": ["V"], "pad": ["Gamepad_LeftTrigger"]},
		"traversal": {"kb": ["E"], "pad": []},
		"secondary_interact": {"kb": ["R"], "pad": ["Gamepad_FaceButton_Top"]},
		"tool_4": {"kb": ["Four"], "pad": ["Gamepad_DPad_Down"]},
		"map_toggle": {"kb": ["Tab", "M"], "pad": ["Gamepad_Special_Left"]},
		"ping_menu": {"kb": ["MiddleMouseButton"], "pad": ["Gamepad_RightShoulder"]},
		"primary_action": {"kb": ["LeftMouseButton"], "pad": ["Gamepad_RightTrigger"]},
		"secondary_action": {"kb": ["RightMouseButton"], "pad": ["Gamepad_LeftTrigger"]},
		"lean_left": {"kb": ["Q"], "pad": ["Gamepad_LeftX-"]},
		"lean_right": {"kb": ["E"], "pad": ["Gamepad_LeftX+"]},
		"look_gamepad": {"kb": [], "pad": ["Gamepad_RightX-", "Gamepad_RightX+", "Gamepad_RightY-", "Gamepad_RightY+"]},
		"change_input_mapping": {"kb": ["Backslash"], "pad": []},
	}
	for id: String in expected.keys():
		var got: Dictionary = InputActions.bound_keys(id)
		_eq_str_list(got.get("kb", []), (expected[id] as Dictionary).get("kb", []), "%s resolves on keyboard" % id)
		_eq_str_list(got.get("pad", []), (expected[id] as Dictionary).get("pad", []), "%s resolves on gamepad" % id)

	# Every non-metadata port action must be bindable on at least one device,
	# and the authore'd pad rows must produce pad events.
	var dead: Array[String] = []
	var pad_missing: Array[String] = []
	for r: Dictionary in InputActions.rows():
		var id: String = str(r.get("id", ""))
		if id == "" or InputActions.is_metadata_only(r):
			continue
		if not InputMap.has_action(id):
			dead.append(id + " (no InputMap action)")
			continue
		if InputMap.action_get_events(id).is_empty():
			dead.append(id)
		if not (r.get("pad", []) as Array).is_empty():
			var pad_keys: Array = InputActions.bound_keys(id).get("pad", [])
			if pad_keys.is_empty():
				pad_missing.append(id)
	_expect(dead.is_empty(), "no authored port action is dead (dead: %s)" % str(dead))
	_expect(pad_missing.is_empty(), "every authored pad row binds gamepad events (missing: %s)" % str(pad_missing))

	# P0 specifics: pad look is a real right-stick action with the authored deadzone.
	var events: Array[InputEvent] = InputMap.action_get_events("look_gamepad") if InputMap.has_action("look_gamepad") else []
	var axes: Array = []
	for ev: InputEvent in events:
		if ev is InputEventJoypadMotion:
			axes.append(int((ev as InputEventJoypadMotion).axis))
	_expect(_dedupe(axes) == [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y], "look_gamepad binds right-stick X+Y (got %s)" % str(_dedupe(axes)))
	_expect(InputMap.has_action("look_gamepad") and absf(InputMap.action_get_deadzone("look_gamepad") - 0.12) < 0.001, "look_gamepad carries the 0.12 axial deadzone")
	_expect(InputMap.has_action("primary_action") and _dedupe(InputActions.bound_keys("primary_action").get("pad", [])) == ["Gamepad_RightTrigger"], "primary_action fires on RT")
	_expect(_dedupe(InputActions.bound_keys("tool_1").get("pad", [])) == ["Gamepad_DPad_Left"], "tool_1 selects on DPad left")
	_expect(_dedupe(InputActions.bound_keys("map_toggle").get("pad", [])) == ["Gamepad_Special_Left"], "map opens on View")
	# The chorded rows are declared and enforced by InputContext.
	_expect(str(InputActions.row_for("lean_left").get("chord", "")) == "IA_ControllerLeftShoulder", "lean_left keeps the authored LB chord")
	_expect(InputMap.has_action("input_chord_lb"), "the LB chord source action exists")
	_expect(InputMap.has_action("pause") and InputActions.bound_keys("pause").get("pad", []) == ["Gamepad_Special_Right"], "pause keeps the legacy Escape and gains gamepad Start")


# ---------------------------------------------------------------------------
# 3. The five contradicting keys (RE-H-02)
# ---------------------------------------------------------------------------

func _check_five_key_contradictions() -> void:
	_expect(not InputActions.bound_keys("crouch").get("kb", []).has("C"), "crouch no longer steals authored Attack (C)")
	_expect(InputActions.bound_keys("crouch").get("kb", []) == ["LeftControl"], "crouch is Ctrl, as authored")
	_expect(not InputActions.bound_keys("interact").get("kb", []).has("E"), "interact no longer steals authored Traversal (E)")
	_expect(InputActions.bound_keys("lean_right").get("kb", []) == ["E"], "lean_right is E, as authored")
	_expect(InputActions.bound_keys("secondary_interact").get("kb", []) == ["R"], "secondary_interact is R, as authored")
	_expect(InputActions.bound_keys("block").get("kb", []) == ["V"], "block is V, as authored")
	_expect(InputActions.bound_keys("attack").get("kb", []) == ["C"], "attack is C, as authored")
	_expect(InputActions.bound_keys("melee_toggle").get("kb", []) == ["H"], "melee_toggle is H, as authored")
	_expect(not InputMap.has_action("thief_vision") or InputMap.action_get_events("thief_vision").is_empty(), "the invented thief_vision key is gone")
	_expect(InputActions.bound_keys("ability").get("kb", []) == ["X"], "ability re-homed onto the authored thiefsign action X (expansion mapping)")
	_expect(str(InputActions.row_for("ability").get("note", "")).contains("EXPANSION"), "the ability re-home is labelled an expansion mapping")
	# The hotbar and the Controls screen can no longer disagree about slot 4.
	_expect(InputGlyphs.text("tool_4", "kb") == "4", "tool 4 prints 4 on keyboard")
	_expect(InputGlyphs.text("tool_4", "pad") == "DPAD DOWN", "tool 4 prints DPAD DOWN on pad")


# ---------------------------------------------------------------------------
# 4. Glyph formatter, both devices (RE-H-06/07/14)
# ---------------------------------------------------------------------------

func _check_glyphs() -> void:
	_expect(InputGlyphs.bracket("interact", "kb") == "[F]", "kb glyph interact = [F]")
	_expect(InputGlyphs.bracket("interact", "pad") == "[X]", "pad glyph interact = [X]")
	_expect(InputGlyphs.prompt("interact", "OPEN", "kb") == "[F] OPEN", "prompt kb = [F] OPEN")
	_expect(InputGlyphs.prompt("interact", "OPEN", "pad") == "[X] OPEN", "prompt pad = [X] OPEN")
	_expect(InputGlyphs.bracket("lean_left", "pad") == "[LB + LS LEFT]", "pad chorded lean = [LB + LS LEFT]")
	_expect(InputGlyphs.bracket("look_gamepad", "pad") == "[RIGHT STICK]", "pad look glyph = [RIGHT STICK]")
	_expect(InputGlyphs.bracket("tool_4", "kb") == "[4]", "kb tool 4 = [4]")
	_expect(InputGlyphs.bracket("interact", "touch") == "" and InputGlyphs.prompt("interact", "OPEN", "touch") == "OPEN", "touch has no authored glyph: the keycap is hidden, the verb stays")
	_expect(InputGlyphs.icon_name("interact", "pad") == "S_Controller_Xbox_X", "authored Xbox X sprite for pad interact")
	_expect(InputGlyphs.icon_name("interact", "kb") == "S_Controller_PC_F", "authored PC F sprite for kb interact")
	_expect(InputGlyphs.action_label("map_toggle") == "Toggle Map", "authored label from ST_Settings_Input")
	_expect(InputGlyphs.action_category("map_toggle") == "Interaction", "authored category from ST_Settings_Input")
	# Shipped oddity: IA_Interact carries no PlayerMappableKeySettings, so the
	# authored build does not offer Interact as a rebind cell. Recorded, not fixed.
	_expect(InputGlyphs.action_category("interact") == "", "Interact is not an authored rebind cell")
	# Device default follows the last input event.
	InputGlyphs.set_device("kb")
	_expect(InputGlyphs.prompt("interact", "OPEN") == "[F] OPEN", "prompt follows the active kb device")
	InputGlyphs.set_device("pad")
	_expect(InputGlyphs.prompt("interact", "OPEN") == "[X] OPEN", "prompt follows the active pad device")
	InputGlyphs.set_device("kb")
	var jb: InputEventJoypadButton = InputEventJoypadButton.new()
	InputGlyphs.note_event(jb)
	_expect(InputGlyphs.current_device() == "pad", "note_event switches to pad")
	var kev: InputEventKey = InputEventKey.new()
	InputGlyphs.note_event(kev)
	_expect(InputGlyphs.current_device() == "kb", "note_event switches back to kb")

	# Legacy prose: the E->F hand patch becomes a binding query.
	_expect(InputGlyphs.format_legacy("[E] Pick Lock (Lv 3)", "interact", "kb") == "[F] Pick Lock (Lv 3)", "legacy [E] pick-lock re-keys to [F]")
	_expect(InputGlyphs.format_legacy("[F] OPEN", "interact", "pad") == "[X] OPEN", "legacy [F] OPEN re-keys to [X] on pad")
	_expect(InputGlyphs.format_legacy("[HOLD] PIN MENU", "interact", "kb") == "[HOLD] PIN MENU", "prose tokens are never rewritten")
	var legend_map: Dictionary = {"SPACE": "jump", "LMB": "primary_action", "ESC": "pause"}
	_expect(InputGlyphs.format_legend("[SPACE] / [LMB] STRIKE PIN · [ESC] CANCEL", legend_map, "kb") == "[SPACE] / [LMB] STRIKE PIN · [ESC] CANCEL", "legend unchanged at authored defaults")
	_expect(InputGlyphs.format_legend("[LMB] CRANK", legend_map, "pad") == "[RT] CRANK", "legend follows the device (LMB -> RT)")


# ---------------------------------------------------------------------------
# 5. Rebinding + conflict + persistence round trip (RE-H-05)
# ---------------------------------------------------------------------------

func _check_rebind_round_trip() -> void:
	var ov: Dictionary = {}
	var g: InputEventKey = InputEventKey.new()
	g.physical_keycode = KEY_G
	var res: Dictionary = InputRebinder.rebind("interact", "kb", g, ov)
	_expect(bool(res.get("ok", false)) and str(res.get("key_name", "")) == "G", "rebind interact -> G succeeds")
	InputRebinder.apply(ov)
	_expect(InputActions.bound_keys("interact").get("kb", []) == ["G"], "InputMap interact is G after rebind")
	_expect(InputGlyphs.bracket("interact", "kb") == "[G]", "glyph follows the rebind without touching the caller")

	# Conflict detection with the authored sentence.
	var conflict_ev: InputEventKey = InputEventKey.new()
	conflict_ev.physical_keycode = KEY_G
	var bad: Dictionary = InputRebinder.rebind("crouch", "kb", conflict_ev, ov)
	_expect(not bool(bad.get("ok", false)), "binding a taken key is refused")
	_expect(str(bad.get("message", "")).contains("already bound to"), "conflict uses the authored sentence")
	_expect(str(bad.get("message", "")).contains("Interact"), "conflict names the owning action")
	_expect((bad.get("conflicts", []) as Array).has("interact"), "conflict lists the owning action id")
	_expect(InputActions.bound_keys("crouch").get("kb", []) == ["LeftControl"], "refused rebind left crouch untouched")

	# Pad conflict: START is free, LB belongs to melee_toggle.
	var free_btn: InputEventJoypadButton = InputEventJoypadButton.new()
	free_btn.button_index = JOY_BUTTON_RIGHT_STICK
	var pad_ok: Dictionary = InputRebinder.rebind("interact", "pad", free_btn, ov)
	_expect(bool(pad_ok.get("ok", false)), "pad rebind interact -> R3 succeeds")
	var lb_ev: InputEventJoypadButton = InputEventJoypadButton.new()
	lb_ev.button_index = JOY_BUTTON_LEFT_SHOULDER
	var pad_bad: Dictionary = InputRebinder.rebind("interact", "pad", lb_ev, ov)
	_expect(not bool(pad_bad.get("ok", false)) and str(pad_bad.get("message", "")).contains("Melee"), "pad conflict names the LB owner")

	# Persist -> serialize -> reload -> still bound.
	var settings: Dictionary = {}
	InputRebinder.write_overrides(settings, ov)
	var as_text: String = JSON.stringify(settings)
	var reloaded: Variant = JSON.parse_string(as_text)
	_expect(reloaded is Dictionary, "binding block survives JSON serialization")
	var ov2: Dictionary = InputRebinder.overrides_from_settings(reloaded as Dictionary)
	InputRebinder.apply(ov2)
	_expect(InputActions.bound_keys("interact").get("kb", []) == ["G"], "rebind survives save -> reload")
	_expect(_dedupe(InputActions.bound_keys("interact").get("pad", [])) == ["Gamepad_RightThumbstick"], "pad rebind survives save -> reload")
	_expect(InputGlyphs.bracket("interact", "pad") == "[R3]", "reloaded pad glyph is R3")

	# Reset restores the authored binding per device.
	InputRebinder.reset_action("interact", "kb", ov2)
	InputRebinder.reset_action("interact", "pad", ov2)
	InputRebinder.apply(ov2)
	_expect(InputActions.bound_keys("interact").get("kb", []) == ["F"], "reset restores authored F")
	_expect(_dedupe(InputActions.bound_keys("interact").get("pad", [])) == ["Gamepad_FaceButton_Left"], "reset restores authored X")

	# Garbage in the save is dropped, never applied.
	var dirty: Dictionary = InputRebinder.overrides_from_settings({"bindings": {"interact": {"kb": ["NotAKey", "F"]}, "no_such_action": {"kb": ["G"]}}})
	_expect(dirty.has("interact") and (dirty["interact"] as Dictionary)["kb"] == ["F"], "unknown key names are dropped on load")
	_expect(not dirty.has("no_such_action"), "unknown actions are dropped on load")


# ---------------------------------------------------------------------------
# 6. Authored sensitivity ladder (RE-H-08)
# ---------------------------------------------------------------------------

func _check_sensitivity_ladder() -> void:
	_expect(InputActions.SENSITIVITY_STEPS.size() == 5, "ladder has the authored 5 steps")
	_expect(InputActions.SENSITIVITY_STEPS == ["VeryLow", "Low", "Normal", "Fast", "VeryFast"], "ladder names match OSEInputSensitivityLevel")
	_expect(is_equal_approx(InputActions.mouse_rad_per_px("Normal"), 0.0025), "Normal keeps the port's effective base")
	_expect(is_equal_approx(InputActions.mouse_rad_per_px("VeryFast"), 0.005), "VeryFast = 2.0x authored mouse multiplier")
	_expect(is_equal_approx(InputActions.pad_look_scale("Fast"), 1.25), "pad look Fast = 1.25x (authored pad ladder differs)")
	_expect(is_equal_approx(InputActions.pad_move_scale("VeryFast"), 2.0), "pad move VeryFast = 2.0x")
	_expect(InputActions.sensitivity_step_index("bogus") == 2, "unknown step falls back to Normal")
	_expect(InputActions.nearest_mouse_step(0.0042) == "Fast", "legacy free-slider value migrates to its nearest step")


# ---------------------------------------------------------------------------
# 7. Modal gating (RE-H-11/12)
# ---------------------------------------------------------------------------

func _check_modal_gating(ctx: Node) -> void:
	await process_frame
	_expect(not bool(ctx.call("blocks_gameplay")), "no modal by default")
	ctx.call("push_modal", "lockpick", InputContext.LOCKPICK_DISABLED, 200.0)
	_expect(bool(ctx.call("blocks", "interact")), "lockpick blocks interaction")
	_expect(bool(ctx.call("blocks", "move_forward")), "lockpick blocks movement")
	_expect(bool(ctx.call("blocks", "tool_4")), "lockpick blocks tool equipping")
	_expect(bool(ctx.call("blocks", "look_gamepad")), "lockpick blocks pad look")
	_expect(not bool(ctx.call("blocks", "primary_action")), "lockpick keeps the strike input (primary fire is not in the authored tag set)")
	_expect(bool(ctx.call("blocks_gameplay")), "lockpick reports gameplay blocked")
	_expect(bool(ctx.call("blocks_look")), "lockpick reports look blocked")
	_expect((ctx.call("active_modals") as Array).has("lockpick"), "lockpick modal is active")
	# The 200 cm walk-away cancel: no player in the tree yet, so it must not fire
	# spuriously, and the anchor must round-trip.
	ctx.call("set_cancel_anchor", "lockpick", Vector3(100.0, 0.0, 100.0))
	await process_frame
	_expect(bool(ctx.call("is_modal", "lockpick")), "cancel distance does not fire without a player")
	ctx.call("pop_modal", "lockpick")
	_expect(not bool(ctx.call("blocks_gameplay")), "popping the modal releases gameplay")
	ctx.call("push_modal", "map", InputContext.MAP_DISABLED)
	_expect(bool(ctx.call("blocks", "move_forward")) and not bool(ctx.call("blocks", "map_toggle")), "map blocks movement but not its own toggle")
	ctx.call("pop_modal", "map")


func _check_player_gate(ctx: Node) -> void:
	var script: GDScript = load("res://src/player/thief_character.gd") as GDScript
	var player: Node = script.new() as Node
	get_root().add_child(player)
	await process_frame
	_expect(bool(player.call("can_act")), "player can act with no modal")
	ctx.call("push_modal", "lockpick", InputContext.LOCKPICK_DISABLED, 200.0)
	_expect(not bool(player.call("can_act")), "player can_act() honours the lockpick modal")
	ctx.call("pop_modal", "lockpick")
	_expect(bool(player.call("can_act")), "player can_act() recovers when the modal closes")
	# Downed still wins over everything.
	player.set("is_downed", true)
	_expect(not bool(player.call("can_act")), "downed still blocks acting")
	player.set("is_downed", false)
	player.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 8. Settings UI wiring: ladder control + rebind cells (RE-H-05/08)
# ---------------------------------------------------------------------------

func _check_settings_ui() -> void:
	var ss: Node = get_root().get_node_or_null("SaveSystem")
	var orig: Dictionary = (ss.call("get_settings") as Dictionary).duplicate(true) if ss != null else {}
	var ui: CanvasLayer = (load("res://src/ui/settings_ui.gd") as GDScript).new() as CanvasLayer
	get_root().add_child(ui)
	await process_frame
	_expect(ui.get("_mouse_sens_option") != null, "Controls tab exposes the mouse ladder selector")
	_expect(ui.get("_pad_look_option") != null, "Controls tab exposes the gamepad look ladder selector")
	_expect(ui.get("_pad_move_option") != null, "Controls tab exposes the gamepad move ladder selector")
	var cells: Dictionary = ui.get("_rebind_buttons") as Dictionary
	_expect(cells.size() == 15, "15 authored rebind cells (17 shipped rows minus the Primary/Move repeats); got %d" % cells.size())
	_expect(cells.has("map_toggle") and cells.has("tool_4"), "rebind cells are keyed by port action")
	ui.call("set_look_sensitivity_step", "kb", 4) # VeryFast
	var s: Dictionary = ss.call("get_settings") as Dictionary if ss != null else {}
	_expect(absf(float(s.get("mouse_sensitivity", 0.0)) - 0.005) < 0.00001, "VeryFast writes the 2.0x effective value")
	_expect(str(s.get("mouse_look_sensitivity", "")) == "VeryFast", "the persisted source of truth is the authored step name")
	ui.call("set_look_sensitivity_step", "kb", 2) # back to Normal
	if ss != null and not orig.is_empty():
		var sd: Dictionary = ss.get("data") as Dictionary
		sd["settings"] = orig
		ss.call("apply_saved_settings")
	ui.queue_free()
	await process_frame
