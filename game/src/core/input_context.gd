extends Node
## Input service (autoload `InputContext`): authored bindings at boot, device
## tracking, chord gating, and modal input gating (RE-H-03/05/11/12).
##
## Why an autoload: Godot has no per-action disable switch, and three of the
## authored behaviours are frame-level —
##   * `Status.MovementDisabled` / `LookDisabled` / `InteractionDisabled` /
##     `ToolEquippingDisabled` from `GA_Lockpick` (extracted CDO),
##   * the LB chord (`InputTriggerChordAction(IA_ControllerLeftShoulder)`) that
##     turns the left stick into lean and the right stick into gear cycling,
##   * `IA_ChangeInputMapping` (Backslash) swapping the display device.
## The service releases disabled actions before the physics tick and re-applies
## the saved rebinds after a settings change.
##
## Modal sources are the HUD's own public getters (`is_lockpicking()`,
## `is_map_open()`, `is_ping_radial_open()`, `is_mission_letter_open()`), found by
## duck typing so this file does not depend on T05's HUD structure. T05 may call
## `InputContext.register_hud(self)` to skip the scan.

signal device_changed(device: String)
signal modal_changed(id: String, active: bool)
signal modal_cancel_requested(id: String)
signal bindings_reloaded(source: String)

## Authored `GA_Lockpick` tag set: Movement / Look / Interaction / ToolEquipping.
const LOCKPICK_DISABLED: Array[String] = [
	"move_forward", "move_backward", "move_left", "move_right",
	"jump", "crouch", "sprint", "lean_left", "lean_right",
	"interact", "tool_1", "tool_2", "tool_3", "tool_4",
	"ping_menu", "ability", "thief_vision", "look_gamepad",
]
## CommonUI focus modal in the shipped build; the port's map does not pause, so
## gameplay input is gated to match the observed shipped effect. `map_toggle`,
## `pause` and the HUD's own `_input` handlers stay live.
const MAP_DISABLED: Array[String] = [
	"move_forward", "move_backward", "move_left", "move_right",
	"jump", "crouch", "sprint", "lean_left", "lean_right",
	"interact", "secondary_interact", "tool_1", "tool_2", "tool_3", "tool_4",
	"primary_action", "secondary_action", "ping_menu", "ability",
	"thief_vision", "look_gamepad",
]
const LETTER_DISABLED: Array[String] = [
	"move_forward", "move_backward", "move_left", "move_right",
	"jump", "crouch", "sprint", "lean_left", "lean_right",
	"interact", "secondary_interact", "tool_1", "tool_2", "tool_3", "tool_4",
	"primary_action", "secondary_action", "ping_menu", "ability",
	"thief_vision", "look_gamepad", "map_toggle",
]
const PING_DISABLED: Array[String] = [
	"move_forward", "move_backward", "move_left", "move_right",
	"jump", "crouch", "sprint", "lean_left", "lean_right",
	"interact", "tool_1", "tool_2", "tool_3", "tool_4", "look_gamepad",
]

## Authored `GA_Lockpick.DistanceBeforeCancel = 200.0` (cm).
const LOCKPICK_CANCEL_CM: float = 200.0

const HUD_SCAN_INTERVAL: float = 0.5

var _modals: Array[Dictionary] = []
var _hud: Node = null
var _scan_accum: float = 0.0
var _device: String = "kb"
var _table: Dictionary = {}
var _overrides: Dictionary = {}
var _ready_done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_table = InputActions.load_table()
	for w: Variant in (_table.get("warnings", []) as Array):
		push_warning("[input] " + str(w))
	_overrides = InputRebinder.overrides_from_settings(_save_settings())
	reload_bindings()
	_ready_done = true


func _save_settings() -> Dictionary:
	var ss: Node = get_node_or_null("/root/SaveSystem")
	if ss == null:
		return {}
	var data_v: Variant = ss.get("data")
	if not (data_v is Dictionary):
		return {}
	var settings_v: Variant = (data_v as Dictionary).get("settings", {})
	return settings_v as Dictionary if settings_v is Dictionary else {}


## Re-applies the table plus the saved overrides. Safe to call after a rebind.
func reload_bindings() -> Dictionary:
	var report: Dictionary = InputActions.apply_to_input_map(_table.get("rows", []), _overrides)
	report["source"] = str(_table.get("source", ""))
	bindings_reloaded.emit(str(report["source"]))
	return report


func bindings_source() -> String:
	return str(_table.get("source", ""))


func overrides() -> Dictionary:
	return _overrides.duplicate(true)


func set_overrides(next: Dictionary, persist_now: bool = true) -> void:
	_overrides = next.duplicate(true)
	reload_bindings()
	if persist_now:
		InputRebinder.persist(_overrides)


## Rebinds through the service so the InputMap and the save agree.
func rebind(action: String, device: String, event: InputEvent) -> Dictionary:
	var result: Dictionary = InputRebinder.rebind(action, device, event, _overrides)
	if bool(result.get("ok", false)):
		reload_bindings()
		InputRebinder.persist(_overrides)
	return result


func reset_bindings() -> void:
	_overrides.clear()
	reload_bindings()
	InputRebinder.persist(_overrides)


# ---------------------------------------------------------------------------
# Device tracking (authored EOSEInputHardwareType; IA_ChangeInputMapping)
# ---------------------------------------------------------------------------

func device() -> String:
	return _device


func _input(event: InputEvent) -> void:
	InputGlyphs.note_event(event)
	if InputGlyphs.current_device() != _device:
		_device = InputGlyphs.current_device()
		device_changed.emit(_device)
	if event.is_action_pressed("change_input_mapping"):
		var next: String = InputGlyphs.toggle_device()
		_device = next
		device_changed.emit(_device)
		get_viewport().set_input_as_handled()
		return
	# A press that arrives while its action is gated must not survive into the
	# physics tick (Godot polls action state, it does not respect handled events).
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		for action: String in _disabled_actions():
			if InputMap.has_action(action) and event.is_action(action):
				Input.action_release(action)


# ---------------------------------------------------------------------------
# Modal gating
# ---------------------------------------------------------------------------

## Push (or replace) a modal gate. `disabled` is the action id list; `cancel_cm`
## is the authored walk-away distance (0 = no cancel).
func push_modal(id: String, disabled: Array, cancel_cm: float = 0.0) -> void:
	if id == "":
		return
	for m: Dictionary in _modals:
		if str(m.get("id", "")) == id:
			m["disabled"] = _to_string_array(disabled)
			m["cancel_cm"] = cancel_cm
			return
	_modals.append({
		"id": id,
		"disabled": _to_string_array(disabled),
		"cancel_cm": cancel_cm,
		"anchor": null,
	})
	modal_changed.emit(id, true)


func pop_modal(id: String) -> void:
	for i: int in range(_modals.size()):
		if str((_modals[i] as Dictionary).get("id", "")) == id:
			_modals.remove_at(i)
			modal_changed.emit(id, false)
			return


func is_modal(id: String) -> bool:
	for m: Dictionary in _modals:
		if str(m.get("id", "")) == id:
			return true
	return false


func has_modal() -> bool:
	return not _modals.is_empty()


func active_modals() -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in _modals:
		out.append(str(m.get("id", "")))
	return out


## The 200 cm walk-away cancel needs the world position the minigame started at.
## T05 passes the lock's global_position when it opens the minigame.
func set_cancel_anchor(id: String, world_position: Vector3) -> void:
	for m: Dictionary in _modals:
		if str(m.get("id", "")) == id:
			m["anchor"] = world_position
			return


func blocks(action: String) -> bool:
	if _modals.is_empty():
		return false
	for m: Dictionary in _modals:
		if (m.get("disabled", []) as Array).has(action):
			return true
	return false


## True while any modal owns gameplay input (movement / look / interaction).
func blocks_gameplay() -> bool:
	if _modals.is_empty():
		return false
	for m: Dictionary in _modals:
		for action: String in ["move_forward", "interact", "primary_action"]:
			if (m.get("disabled", []) as Array).has(action):
				return true
	return false


func blocks_look() -> bool:
	return blocks("look_gamepad") or blocks("move_forward")


func _disabled_actions() -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in _modals:
		for action: Variant in (m.get("disabled", []) as Array):
			var s: String = str(action)
			if not out.has(s):
				out.append(s)
	return out


func _to_string_array(values: Array) -> Array[String]:
	var out: Array[String] = []
	for v: Variant in values:
		var s: String = str(v)
		if s != "" and not out.has(s):
			out.append(s)
	return out


# ---------------------------------------------------------------------------
# Per-frame enforcement
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _ready_done:
		return
	_scan_accum += delta
	if _scan_accum >= HUD_SCAN_INTERVAL:
		_scan_accum = 0.0
		_sync_hud_modals()
	_tick_gates()
	_tick_chords()
	_tick_cancel_distance()


func _tick_gates() -> void:
	if _modals.is_empty():
		return
	for action: String in _disabled_actions():
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)


## Authored LB chord: the six pad rows carry
## `InputTriggerChordAction(IA_ControllerLeftShoulder)`. While LB is held the
## chorded actions are live and pad look/move are prevented (IA_PreventLookGamepad
## / IA_PreventMoveGamepad are themselves LB-chorded).
func _tick_chords() -> void:
	if not InputMap.has_action("input_chord_lb"):
		return
	var chord_held: bool = Input.is_action_pressed("input_chord_lb")
	for action: String in InputActions.ids():
		var row: Dictionary = InputActions.row_for(action)
		if str(row.get("chord", "")) == "":
			continue
		if not chord_held and Input.is_action_pressed(action):
			Input.action_release(action)
	if chord_held:
		for action: String in ["look_gamepad", "move_forward", "move_backward", "move_left", "move_right"]:
			if InputMap.has_action(action) and Input.is_action_pressed(action):
				Input.action_release(action)


func _tick_cancel_distance() -> void:
	for m: Dictionary in _modals:
		var cancel_cm: float = float(m.get("cancel_cm", 0.0))
		if cancel_cm <= 0.0 or not (m.get("anchor") is Vector3):
			continue
		var player: Node3D = _find_player()
		if player == null:
			continue
		var d_m: float = player.global_position.distance_to(m["anchor"] as Vector3)
		if d_m * 100.0 > cancel_cm:
			var id: String = str(m.get("id", ""))
			pop_modal(id)
			modal_cancel_requested.emit(id)
			return


# ---------------------------------------------------------------------------
# HUD modal discovery
# ---------------------------------------------------------------------------

func register_hud(node: Node) -> void:
	_hud = node


func _find_player() -> Node3D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var nodes: Array[Node] = tree.get_nodes_in_group("player")
	for n: Node in nodes:
		if n is Node3D and is_instance_valid(n):
			return n as Node3D
	return null


func _sync_hud_modals() -> void:
	if not is_instance_valid(_hud):
		_hud = _discover_hud()
	if not is_instance_valid(_hud):
		return
	_sync_auto("lockpick", _hud.has_method("is_lockpicking") and bool(_hud.call("is_lockpicking")), LOCKPICK_DISABLED, LOCKPICK_CANCEL_CM)
	_sync_auto("map", _hud.has_method("is_map_open") and bool(_hud.call("is_map_open")), MAP_DISABLED, 0.0)
	# The mission letter is deliberately NOT auto-polled. `is_mission_letter_open()`
	# flips on a signal whose timing depends on sublevel streaming, and polling it
	# made the E2E full run flake (the letter could open after the harness had
	# already dismissed it). T05 owns the explicit push/pop inside
	# `show_mission_letter()` / `_close_mission_letter()`; LETTER_DISABLED is ready
	# for that call. See the T06 report call-site list.
	_sync_auto("ping_radial", _hud.has_method("is_ping_radial_open") and bool(_hud.call("is_ping_radial_open")), PING_DISABLED, 0.0)


func _sync_auto(id: String, active: bool, disabled: Array[String], cancel_cm: float) -> void:
	if active and not is_modal(id):
		push_modal(id, disabled, cancel_cm)
	elif not active and is_modal(id):
		pop_modal(id)


func _discover_hud() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	for n: Node in tree.get_root().find_children("*", "CanvasLayer", true, false):
		if n.has_method("is_lockpicking") and n.has_method("is_map_open"):
			return n
	return null
