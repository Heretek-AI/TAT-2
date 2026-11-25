class_name InputActions
extends RefCounted
## Generated Enhanced Input table for TAT-2, and the InputMap builder on top of it.
##
## Source of truth: `tools/parse_input.py` ->
## `res://data/generated/gameplay/input_actions.json` (`tat2.input_actions/1`).
## That file holds 237 mapping rows; the three shipping IMCs (`IMC_Character`,
## `IMC_Radial`, `IMC_MapTool`) hold 91 of them over 52 `IA_*` actions, and the
## `actions` object holds 65 action assets. `load_table()` adapts the producer
## schema (`contexts[*].mappings` with `action`/`key`/`key_is_gamepad`/
## `trigger`/`modifiers`/`chord_action`) to the consumer row shape below, then
## applies the small `PORT_DECISIONS` table where the producer has no 1:1
## representation (the `IA_Move` split, the `sprint` and `primary_action`
## merges, the `tool_4` pick, the LB chord source, the legacy `Pause` mapping).
## Every key, deadzone, trigger and chord in a row comes from the generated file;
## `PORT_ID_FOR_IA` only names the port action each authored action feeds.
##
## Port ids are runtime contracts (AGENTS rule 7): the 21 pre-existing
## `project.godot` ids and the 40 ids the P0/T06 wave shipped keep their names.
## Authored actions with no port consumer are still rows (`id == ""`), so the
## diff and the rebind UI stay complete.
##
## If the generated file is absent or unusable there is NO transcription
## fallback: nothing is bound, the actions already in `project.godot [input]`
## stay untouched, and a warning names the missing producer output.

const GENERATED_PATH: String = "res://data/generated/gameplay/input_actions.json"
const SCHEMA: String = "tat2.input_actions/1"
## The three shipping IMCs. The producer's per-context `shipping` flag is
## authoritative; this list is the fallback and documents what "shipping" means.
## The two `*_ClimbTest` / `*_Testing` dev contexts are skipped and counted.
const SHIPPING_CONTEXTS: Array[String] = ["IMC_Character", "IMC_Radial", "IMC_MapTool"]
const DEVICE_KB: String = "kb"
const DEVICE_PAD: String = "pad"

## Authored deadzones (IMC subobjects InputModifierDeadZone_0/_2).
const DEADZONE_MOVE: float = 0.18
const DEADZONE_LOOK: float = 0.12
const LOOK_UPPER: float = 0.98
## Authored gamepad look (OSEInputModifierGamepadLookSpeed_0), degrees per second.
const PAD_TURN_H_DEG_S: float = 90.0
const PAD_TURN_V_DEG_S: float = 52.0
## Authored hold threshold (InputTriggerHold_0/_1/_3).
const HOLD_SECONDS: float = 0.2
## Authored edge-acceleration values (OSEEnhancedInputGamepadEdgeAcceleration_0).
## The threshold and the curve name are read from the `look_gamepad` row (the
## generated modifier carries `edge_threshold` and `boost_over_time`); these are
## the documented fallbacks for a producer-less boot.
const EDGE_BOOST_THRESHOLD_FALLBACK: float = 0.95
const EDGE_BOOST_CURVE_FALLBACK: String = "Curve_GamepadLookEdgeBoost"

## UE key name -> Godot physical keycode. Values verified on this engine build
## (T06 dump, 4.7.2) rather than assumed from the docs.
const KEY_CODES: Dictionary = {
	"SpaceBar": KEY_SPACE, "Tab": KEY_TAB, "CapsLock": KEY_CAPSLOCK,
	"Enter": KEY_ENTER, "Escape": KEY_ESCAPE, "Backslash": KEY_BACKSLASH,
	"LeftControl": KEY_CTRL, "RightControl": KEY_CTRL,
	"LeftShift": KEY_SHIFT, "RightShift": KEY_SHIFT,
	"LeftAlt": KEY_ALT, "RightAlt": KEY_ALT, "Pause": KEY_PAUSE,
	"One": KEY_1, "Two": KEY_2, "Three": KEY_3, "Four": KEY_4,
	"Five": KEY_5, "Six": KEY_6, "Seven": KEY_7, "Eight": KEY_8,
	"Nine": KEY_9, "Zero": KEY_0,
}
## Letters are one-to-one.
const LETTER_KEYS: Dictionary = {"A": KEY_A, "B": KEY_B, "C": KEY_C, "D": KEY_D, "E": KEY_E, "F": KEY_F, "G": KEY_G, "H": KEY_H, "I": KEY_I, "J": KEY_J, "K": KEY_K, "L": KEY_L, "M": KEY_M, "N": KEY_N, "O": KEY_O, "P": KEY_P, "Q": KEY_Q, "R": KEY_R, "S": KEY_S, "T": KEY_T, "U": KEY_U, "V": KEY_V, "W": KEY_W, "X": KEY_X, "Y": KEY_Y, "Z": KEY_Z}
const MOUSE_BUTTONS: Dictionary = {
	"LeftMouseButton": MOUSE_BUTTON_LEFT, "RightMouseButton": MOUSE_BUTTON_RIGHT,
	"MiddleMouseButton": MOUSE_BUTTON_MIDDLE,
	"ThumbMouseButton": MOUSE_BUTTON_XBUTTON1, "ThumbMouseButton2": MOUSE_BUTTON_XBUTTON2,
	"MouseWheelAxis+": MOUSE_BUTTON_WHEEL_UP, "MouseWheelAxis-": MOUSE_BUTTON_WHEEL_DOWN,
}
const JOY_BUTTONS: Dictionary = {
	"Gamepad_FaceButton_Bottom": JOY_BUTTON_A,
	"Gamepad_FaceButton_Right": JOY_BUTTON_B,
	"Gamepad_FaceButton_Left": JOY_BUTTON_X,
	"Gamepad_FaceButton_Top": JOY_BUTTON_Y,
	"Gamepad_Special_Left": JOY_BUTTON_BACK,
	"Gamepad_Special_Right": JOY_BUTTON_START,
	"Gamepad_LeftThumbstick": JOY_BUTTON_LEFT_STICK,
	"Gamepad_RightThumbstick": JOY_BUTTON_RIGHT_STICK,
	"Gamepad_LeftShoulder": JOY_BUTTON_LEFT_SHOULDER,
	"Gamepad_RightShoulder": JOY_BUTTON_RIGHT_SHOULDER,
	"Gamepad_DPad_Up": JOY_BUTTON_DPAD_UP,
	"Gamepad_DPad_Down": JOY_BUTTON_DPAD_DOWN,
	"Gamepad_DPad_Left": JOY_BUTTON_DPAD_LEFT,
	"Gamepad_DPad_Right": JOY_BUTTON_DPAD_RIGHT,
}
## name -> [axis, sign]; sign 0 means a full -1..+1 axis (two events).
## Signed axis names only: one entry -> one event, and the inverse mapping is
## therefore unambiguous (a zero-sign "full axis" name would expand to two events
## that reverse-map to the signed names, so the two forms cannot coexist).
const JOY_AXES: Dictionary = {
	"Gamepad_LeftX-": [JOY_AXIS_LEFT_X, -1.0], "Gamepad_LeftX+": [JOY_AXIS_LEFT_X, 1.0],
	"Gamepad_LeftY-": [JOY_AXIS_LEFT_Y, -1.0], "Gamepad_LeftY+": [JOY_AXIS_LEFT_Y, 1.0],
	"Gamepad_RightX-": [JOY_AXIS_RIGHT_X, -1.0], "Gamepad_RightX+": [JOY_AXIS_RIGHT_X, 1.0],
	"Gamepad_RightY-": [JOY_AXIS_RIGHT_Y, -1.0], "Gamepad_RightY+": [JOY_AXIS_RIGHT_Y, 1.0],
	"Gamepad_LeftTrigger": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	"Gamepad_RightTrigger": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
}

# ---------------------------------------------------------------------------
# Authored sensitivity ladder
# ---------------------------------------------------------------------------
# Two shipped sources describe the mouse/gamepad look sensitivity:
#   1. `DefaultGame.ini:483-486` / [OSECore.OSEInputDeveloperSettings] — the 5
#      named steps: Mouse 0.5/0.75/1.0/1.5/2.0, GamepadLook 0.5/0.75/1.0/1.25/1.5,
#      GamepadMove 0.5/0.75/1.0/1.5/2.0. The shipped build saves one step per
#      hardware type (OSECore.hpp FOSEGamepadMouseKeyboardSettings), not a slider.
#   2. `DefaultGame.ini:895-897` / [TAT.TATInputDeveloperSettings] — the
#      `MouseLookSensitivityCurve` / `GamepadLookSensitivityCurve` CurveFloat
#      assets (`game/data/generated/tables/UI/Settings/`, indexed by
#      `curves.json`). Both curves map the setting value over [0, 2] to a
#      multiplier: 0 -> 0.2, 1 -> 1.125, 2 -> 2.0.
# The port keeps the authored 5-step input and samples each curve at evenly
# spaced positions across the curve's own authored time range (step 0 = first
# key, step 4 = last key). The ini ladder tables below stay as the documented
# fallback when the curve index/table is unreadable; pad move has no shipped
# curve (only mouse and pad look do) and keeps the ini ladder.
#
# The 0.0025 rad/px base is the **port's unit bridge** (the value the port shipped
# as its invented default), NOT authored: RE-H-08 records that the UE chain
# (0.07 deg/count x FOVScale/tan(halfFOV)) cannot be mapped to Godot pixels without
# an unshot measurement. Only the base unit is carried over; the multiplier on top
# is the shipped curve.
const MOUSE_RAD_PER_PX_BASE: float = 0.0025
const SENSITIVITY_STEPS: Array[String] = ["VeryLow", "Low", "Normal", "Fast", "VeryFast"]
const MOUSE_LOOK_CURVE: String = "MouseLookSensitivityCurve"
const PAD_LOOK_CURVE: String = "GamepadLookSensitivityCurve"
const MOUSE_LOOK_MULT: Array[float] = [0.5, 0.75, 1.0, 1.5, 2.0]
const PAD_LOOK_MULT: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5]
const PAD_MOVE_MULT: Array[float] = [0.5, 0.75, 1.0, 1.5, 2.0]
## Cached GameData autoload for the curve reads (never a hard preload).
static var _game_data: Node = null

static func sensitivity_step_index(name: String) -> int:
	var idx: int = SENSITIVITY_STEPS.find(name)
	return idx if idx >= 0 else 2 # authored default: Normal


static func sensitivity_step_name(index: int) -> String:
	return SENSITIVITY_STEPS[clampi(index, 0, SENSITIVITY_STEPS.size() - 1)]


static func mouse_rad_per_px(step_name: String) -> float:
	return MOUSE_RAD_PER_PX_BASE * _sensitivity_multiplier(MOUSE_LOOK_CURVE, MOUSE_LOOK_MULT, sensitivity_step_index(step_name))


static func pad_look_scale(step_name: String) -> float:
	return _sensitivity_multiplier(PAD_LOOK_CURVE, PAD_LOOK_MULT, sensitivity_step_index(step_name))


static func pad_move_scale(step_name: String) -> float:
	return PAD_MOVE_MULT[sensitivity_step_index(step_name)]


## One ladder step's multiplier from the shipped curve: the 5 steps map to evenly
## spaced x positions across the curve's authored time range (clamped by
## construction). `fallback` is the DefaultGame.ini ladder, used when the curve
## index, its table or the GameData autoload is unavailable.
static func _sensitivity_multiplier(curve_name: String, fallback: Array[float], index: int) -> float:
	var idx: int = clampi(index, 0, SENSITIVITY_STEPS.size() - 1)
	var gd: Node = _game_data_node()
	if gd == null or not gd.has_method("eval_standalone_curve") or not gd.has_method("standalone_curve_range"):
		return fallback[idx]
	var span: Vector2 = gd.call("standalone_curve_range", curve_name) as Vector2
	if is_equal_approx(span.x, span.y):
		return fallback[idx]
	var t: float = span.x + (float(idx) / float(SENSITIVITY_STEPS.size() - 1)) * (span.y - span.x)
	var got: float = float(gd.call("eval_standalone_curve", curve_name, t, "Value", NAN))
	return fallback[idx] if is_nan(got) else got


## Nearest authored step for a legacy free-slider value (migration only).
static func nearest_mouse_step(rad_per_px: float) -> String:
	var best: String = "Normal"
	var best_d: float = INF
	for name: String in SENSITIVITY_STEPS:
		var d: float = absf(mouse_rad_per_px(name) - rad_per_px)
		if d < best_d:
			best_d = d
			best = name
	return best


## Every authored `IA_*` in the three shipped contexts (52). Used by the coverage
## test so a dropped row fails loudly instead of shrinking the table silently.
const AUTHORED_ACTIONS: Array[String] = [
	"IA_Ability03", "IA_Ability04", "IA_Ability05", "IA_Ability06", "IA_Ability07",
	"IA_Ability08", "IA_Ability09", "IA_Ability10",
	"IA_Ability_Action_Primary", "IA_Ability_Action_Primary_Hold",
	"IA_Ability_Action_Primary_Tap", "IA_Ability_Action_Secondary",
	"IA_Ability_Attack", "IA_Ability_Block", "IA_Ability_Lean_Left",
	"IA_Ability_Lean_Right", "IA_Ability_MeleeToggle", "IA_Ability_OpenRadial",
	"IA_Ability_OpenThiefsignRadial", "IA_Ability_RangedAttack",
	"IA_Ability_RangedReload", "IA_Ability_RunToggle", "IA_Ability_Traversal",
	"IA_ChangeInputMapping", "IA_ControllerLeftShoulder", "IA_DisplayInputCycle",
	"IA_DisplayInputDebug", "IA_Interact", "IA_LookGamepad", "IA_LookMouseKeyboard",
	"IA_MapSwitch_Next", "IA_MapSwitch_Prev", "IA_MissionPanelToggle", "IA_Move",
	"IA_Movement_Crouch", "IA_Movement_CrouchHold", "IA_Movement_Dodge",
	"IA_Movement_Jump", "IA_Movement_Run", "IA_PreventLookGamepad",
	"IA_PreventMoveGamepad", "IA_Radial_Cancel", "IA_Radial_Directional",
	"IA_Radial_NextPage", "IA_Radial_PreviousPage", "IA_Radial_Select_Primary",
	"IA_Radial_Select_Secondary", "IA_Secondary_Interact",
	"IA_ToolSelect_EquipMap", "IA_ToolSelect_EquipNextWeapon",
	"IA_ToolSelect_EquipPreviousWeapon", "IA_ToolSelect_EquipVistaraDiamond",
]

## Authored mapping categories the settings screen groups by (ST_Settings_Input).
const CATEGORY_LABELS: Dictionary = {
	"Movement": "InputSetting.Category.Movement",
	"Interaction": "InputSetting.Category.Interaction",
	"Tools": "InputSetting.Category.Tools",
	"Primary Fire": "InputSetting.PrimaryFire",
	"Lean": "InputSetting.Category.Lean",
}

## Consumer row schema: id, ia, ctx, kb[], pad[], deadzone, trigger, chord,
## mappable{}, consumer, note (+ edge_threshold / edge_boost_curve on the
## `look_gamepad` row). `id == ""` marks a coverage row: a shipped mapping with no
## port action of its own, or an additional authored mapping whose keys are bound
## through the owner row (the row that carries the id).

# ---------------------------------------------------------------------------
# Producer-schema bridges (no authored binding is transcribed here)
# ---------------------------------------------------------------------------

## UE directional/composite key names -> the port's signed-axis names. The port
## declares one action per signed axis (Godot cannot read a 2D key from a single
## action), so a stick direction becomes a signed name. Keys not listed pass
## through unchanged (`W`, `LeftControl`, `Gamepad_FaceButton_Left`, ...).
const KEY_ALIASES: Dictionary = {
	"Gamepad_LeftStick_Left": "Gamepad_LeftX-", "Gamepad_LeftStick_Right": "Gamepad_LeftX+",
	"Gamepad_LeftStick_Up": "Gamepad_LeftY-", "Gamepad_LeftStick_Down": "Gamepad_LeftY+",
	"Gamepad_RightStick_Left": "Gamepad_RightX-", "Gamepad_RightStick_Right": "Gamepad_RightX+",
	"Gamepad_RightStick_Up": "Gamepad_RightY-", "Gamepad_RightStick_Down": "Gamepad_RightY+",
}
## A 2D stick key means both axes; the port's signed-axis actions cover them.
const TWO_AXIS_KEYS: Dictionary = {
	"Gamepad_Left2D": ["Gamepad_LeftX-", "Gamepad_LeftX+", "Gamepad_LeftY-", "Gamepad_LeftY+"],
	"Gamepad_Right2D": ["Gamepad_RightX-", "Gamepad_RightX+", "Gamepad_RightY-", "Gamepad_RightY+"],
}

## The port action each authored action feeds. This is the id vocabulary, not a
## binding transcription: no key, deadzone or trigger is repeated here (AGENTS
## rule 7 — these ids are runtime contracts). Authored actions absent from this
## table stay coverage-only rows. `IA_Move` is absent because its split produces
## four ids (see PORT_DECISIONS), and the legacy `Pause` row has no IA at all.
const PORT_ID_FOR_IA: Dictionary = {
	"IA_Ability_Action_Primary": "primary_action",
	"IA_Ability_Action_Primary_Tap": "primary_action",
	"IA_Ability_Action_Primary_Hold": "primary_action",
	"IA_Ability_Action_Secondary": "secondary_action",
	"IA_Movement_Jump": "jump", "IA_Movement_Crouch": "crouch",
	"IA_Movement_CrouchHold": "crouch_hold", "IA_Movement_Run": "sprint",
	"IA_Ability_RunToggle": "sprint", "IA_Movement_Dodge": "dodge",
	"IA_Interact": "interact", "IA_Ability_MeleeToggle": "melee_toggle",
	"IA_PreventLookGamepad": "prevent_look_gamepad",
	"IA_PreventMoveGamepad": "prevent_move_gamepad",
	"IA_LookMouseKeyboard": "look_mouse", "IA_MissionPanelToggle": "mission_panel",
	"IA_Ability_Traversal": "traversal",
	"IA_Ability03": "tool_1", "IA_Ability04": "tool_2", "IA_Ability05": "tool_3",
	"IA_ControllerLeftShoulder": "input_chord_lb",
	"IA_ToolSelect_EquipNextWeapon": "tool_select_next",
	"IA_ToolSelect_EquipPreviousWeapon": "tool_select_prev",
	"IA_Ability_Lean_Left": "lean_left", "IA_Ability_Lean_Right": "lean_right",
	"IA_LookGamepad": "look_gamepad", "IA_Ability_Attack": "attack",
	"IA_Ability_Block": "block", "IA_Ability_RangedAttack": "ranged_attack",
	"IA_Secondary_Interact": "secondary_interact",
	"IA_Ability_RangedReload": "ranged_reload",
	"IA_Ability_OpenRadial": "ping_menu", "IA_ToolSelect_EquipMap": "map_toggle",
	"IA_Ability_OpenThiefsignRadial": "ability",
	"IA_ChangeInputMapping": "change_input_mapping",
	"IA_DisplayInputDebug": "display_input_debug",
	"IA_DisplayInputCycle": "display_input_cycle",
	"IA_ToolSelect_EquipVistaraDiamond": "tool_4",
}

## file:line that polls each 1:1 port action ("" = bound for coverage/rebind but
## no current reader). The merge/pick/split rows carry theirs in PORT_DECISIONS.
const PORT_CONSUMERS: Dictionary = {
	"secondary_action": "thief_character.gd:951,1417,1742",
	"jump": "thief_character.gd:1496,1529",
	"crouch": "thief_character.gd:884",
	"interact": "thief_character.gd:890; npc_clue_dialogue.gd:187",
	"prevent_look_gamepad": "input_context.gd:295",
	"prevent_move_gamepad": "input_context.gd:295",
	"look_mouse": "thief_character.gd:866 (InputEventMouseMotion)",
	"look_gamepad": "thief_character.gd:981 (Input.get_joy_axis)",
	"tool_1": "thief_character.gd:933", "tool_2": "thief_character.gd:935",
	"tool_3": "thief_character.gd:937",
	"lean_left": "thief_character.gd:1355", "lean_right": "thief_character.gd:1357",
	"ping_menu": "hud.gd:2447", "map_toggle": "hud.gd:2435",
	"ability": "thief_character.gd:931,1407",
	"change_input_mapping": "input_context.gd:141",
}

## Notes that explain an adaptation or a recorded shipped oddity. Keyed by port id
## for id rows and by authored IA for coverage rows.
const PORT_NOTES: Dictionary = {
	"ability": "EXPANSION: the port's per-thief signature ability takes the authored thiefsign slot (X); the shipped radial menu is unimplemented",
	"crouch_hold": "no port consumer (crouch is a toggle); recorded",
	"dodge": "no port consumer; the authored row double-binds L3 with IA_Ability_RunToggle",
	"look_gamepad": "authored deadzone 0.12 Axial, turn 90/52 deg/s, edge boost curve above the modifier threshold",
	"prevent_look_gamepad": "authored LB chord suppresses pad look while the chord is held",
	"prevent_move_gamepad": "authored LB chord suppresses pad move while the chord is held",
	"tool_select_next": "wheel up comes from the authored OSEEnhancedInputModifierRequireSign Positive (the IMC has no signed wheel key name)",
	"tool_select_prev": "wheel down comes from OSEEnhancedInputModifierRequireSign with the Negative default",
	"IA_Ability06": "Four is authored on both IA_Ability06 and the Vistara action; the port's tool_4 binds Vistara",
	"IA_Ability07": "no consumer and no port slot", "IA_Ability08": "no consumer and no port slot",
	"IA_Ability09": "no consumer and no port slot", "IA_Ability10": "no consumer and no port slot",
	"IA_Radial_Directional": "no port consumer (the HUD ping radial is unimplemented)",
	"IA_Radial_Cancel": "no port consumer", "IA_Radial_NextPage": "no port consumer",
	"IA_Radial_PreviousPage": "no port consumer", "IA_Radial_Select_Primary": "no port consumer",
	"IA_Radial_Select_Secondary": "no port consumer",
	"IA_MapSwitch_Prev": "no port consumer (the port map has one page)",
	"IA_MapSwitch_Next": "no port consumer (the port map has one page)",
}

# ---------------------------------------------------------------------------
# Port decisions — the only block in this file that names a binding, and only
# where the generated producer schema has no 1:1 representation. Every value is
# a port split/merge of authored rows or the legacy non-Enhanced-Input Pause.
# ---------------------------------------------------------------------------
const PORT_DECISIONS: Array[Dictionary] = [
	{
		"kind": "split", "ia": "IA_Move",
		"ids": [
			{"id": "move_forward", "kb": "W", "pad": "Gamepad_LeftY-"},
			{"id": "move_backward", "kb": "S", "pad": "Gamepad_LeftY+"},
			{"id": "move_left", "kb": "A", "pad": "Gamepad_LeftX-"},
			{"id": "move_right", "kb": "D", "pad": "Gamepad_LeftX+"},
		],
		"consumer": "thief_character.gd:1442",
		"note": "PORT DECISION: IA_Move is one swizzled 2D action in the IMC; the port polls four 1D actions (Input.get_vector) with the same authored keys and deadzone",
	},
	{
		"kind": "merge", "id": "sprint", "ias": ["IA_Movement_Run", "IA_Ability_RunToggle"],
		"consumer": "thief_character.gd:877,1456",
		"note": "PORT DECISION: sprint merges IA_Movement_Run (hold Shift) and IA_Ability_RunToggle (L3); both authored rows exist",
	},
	{
		"kind": "merge", "id": "primary_action",
		"ias": ["IA_Ability_Action_Primary", "IA_Ability_Action_Primary_Tap", "IA_Ability_Action_Primary_Hold"],
		"trigger": "tap+hold:0.2",
		"consumer": "thief_character.gd:949,1183,1407",
		"note": "PORT DECISION: the port has one press action; the authored _Tap/_Hold variants share its keys (hold 0.2 s)",
	},
	{
		"kind": "pick", "id": "tool_4", "ia": "IA_ToolSelect_EquipVistaraDiamond",
		"consumer": "thief_character.gd:947,1407",
		"note": "PORT DECISION: Four is authored on both IA_Ability06 and the Vistara action; the port ships Vistara",
	},
	{
		"kind": "pick", "id": "input_chord_lb", "ia": "IA_ControllerLeftShoulder",
		"consumer": "input_context.gd:284",
		"note": "PORT DECISION: the authored LB chord source becomes its own action so input_context can hold it",
	},
	{
		"kind": "legacy", "id": "pause", "ia": "Pause",
		"kb": ["Escape", "Pause"], "pad": ["Gamepad_Special_Right"],
		"consumer": "hud.gd:2507",
		"note": "PORT DECISION: Pause is a DefaultInput.ini ActionMapping, not Enhanced Input (Escape/Pause/Start; Global_Pause has no Godot key)",
	},
]


## Deep copy of the adapted table (91 rows on the 2026-11-25 generated file: 90
## rows adapted from the 91 shipping mappings — IA_Move's five mappings become the
## four port actions — plus the legacy Pause row).
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in _table_rows():
		out.append(r.duplicate(true))
	return out


## The owner row for a port id (the row that carries the merged keys).
static func row_for(id: String) -> Dictionary:
	if id == "":
		return {}
	for r: Dictionary in _table_rows():
		if str(r.get("id", "")) == id:
			return r.duplicate(true)
	return {}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in _table_rows():
		var id: String = str(r.get("id", ""))
		if id != "" and not out.has(id):
			out.append(id)
	return out


## True when a row only carries provenance (a shipped mapping with no port action,
## or one already consumed through another action).
static func is_coverage_only(row: Dictionary) -> bool:
	return str(row.get("id", "")) == ""


## True when the action exists in the table but has no bindable event (mouse look:
## `Mouse2D` is read as motion, so it expands to zero InputMap events).
static func is_metadata_only(row: Dictionary) -> bool:
	if is_coverage_only(row):
		return true
	var bindable: int = 0
	for key_v: Variant in (row.get("kb", []) as Array):
		bindable += events_for_key(str(key_v)).size()
	for key_v: Variant in (row.get("pad", []) as Array):
		bindable += events_for_key(str(key_v)).size()
	return bindable == 0


static func authored_key_names(id: String, device: String) -> Array[String]:
	var r: Dictionary = row_for(id)
	var key: String = "kb" if device == DEVICE_KB else "pad"
	var out: Array[String] = []
	for k: Variant in (r.get(key, []) as Array):
		out.append(str(k))
	return out


static func deadzone_for(id: String) -> float:
	var r: Dictionary = row_for(id)
	return float(r.get("deadzone", 0.2))


## The chord is authored as an IA name; the port action that carries it is
## `input_chord_lb`. Returns "" when the chord IA has no port action.
static func port_id_for_ia(ia: String) -> String:
	var direct: String = str(PORT_ID_FOR_IA.get(ia, ""))
	if direct != "":
		return direct
	for r: Dictionary in _table_rows():
		if str(r.get("ia", "")) == ia:
			var id: String = str(r.get("id", ""))
			if id != "":
				return id
	return ""


static func is_pad_key(key_name: String) -> bool:
	return key_name.begins_with("Gamepad_")


# ---------------------------------------------------------------------------
# Table loading: producer schema -> consumer rows (no transcription fallback)
# ---------------------------------------------------------------------------

static var _cache: Dictionary = {}
static var _cache_loaded: bool = false
static var _reported: bool = false


## Returns {source, rows, warnings, shipping, actions, skipped_contexts,
## skipped_mappings}. `source` is "generated" or "" (nothing is bound; the
## actions already in project.godot [input] stay untouched). The load runs once
## per process and prints `INPUT_TABLE source=... rows=... shipping=... actions=...`.
static func load_table() -> Dictionary:
	if not _cache_loaded:
		_cache = _load_once()
		_cache_loaded = true
		if not _reported:
			_reported = true
			print("INPUT_TABLE source=%s rows=%d shipping=%d actions=%d" % [
				str(_cache.get("source", "")), (_cache.get("rows", []) as Array).size(),
				int(_cache.get("shipping", 0)), int(_cache.get("actions", 0))])
			var skipped_names: Array[String] = []
			for v: Variant in (_cache.get("skipped_contexts", []) as Array):
				skipped_names.append(str(v))
			if not skipped_names.is_empty():
				var dev_only: Array[String] = []
				for v: Variant in (_cache.get("skipped_only_actions", []) as Array):
					dev_only.append(str(v))
				print("INPUT_TABLE_SKIPPED contexts=%s mappings=%d dev_only_actions=%s" % [
					String(", ").join(PackedStringArray(skipped_names)),
					int(_cache.get("skipped_mappings", 0)),
					String(", ").join(PackedStringArray(dev_only)) if not dev_only.is_empty() else "none"])
	return _cache.duplicate(true)


## The last load's summary for tests and export logs (loads on first call).
static func load_report() -> Dictionary:
	if not _cache_loaded:
		load_table()
	var skipped: Array[String] = []
	for v: Variant in (_cache.get("skipped_contexts", []) as Array):
		skipped.append(str(v))
	return {
		"source": str(_cache.get("source", "")),
		"rows": (_cache.get("rows", []) as Array).size(),
		"shipping": int(_cache.get("shipping", 0)),
		"actions": int(_cache.get("actions", 0)),
		"skipped_contexts": skipped,
		"skipped_mappings": int(_cache.get("skipped_mappings", 0)),
		"skipped_only_actions": (_cache.get("skipped_only_actions", []) as Array).duplicate(),
		"warnings": (_cache.get("warnings", []) as Array).duplicate(),
	}


## Cached rows, not copied (internal readers only).
static func _table_rows() -> Array[Dictionary]:
	if not _cache_loaded:
		load_table()
	var out: Array[Dictionary] = []
	for v: Variant in (_cache.get("rows", []) as Array):
		if v is Dictionary:
			out.append(v as Dictionary)
	return out


static func _load_once() -> Dictionary:
	var warnings: Array[String] = []
	if FileAccess.file_exists(GENERATED_PATH):
		var f: FileAccess = FileAccess.open(GENERATED_PATH, FileAccess.READ)
		if f == null:
			warnings.append("cannot open %s" % GENERATED_PATH)
		else:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				var adapted: Dictionary = _adapt_generated(parsed as Dictionary)
				warnings.append_array(adapted.get("warnings", []) as Array[String])
				var adapted_rows: Array = adapted.get("rows", []) as Array
				if not adapted_rows.is_empty():
					return {
						"source": "generated",
						"rows": adapted_rows,
						"warnings": warnings,
						"shipping": int(adapted.get("shipping_mappings", 0)),
						"actions": int(adapted.get("actions", 0)),
						"skipped_contexts": adapted.get("skipped_contexts", []),
						"skipped_mappings": int(adapted.get("skipped_mappings", 0)),
						"skipped_only_actions": adapted.get("skipped_only_actions", []),
					}
			else:
				warnings.append("generated input table is not valid JSON: %s" % GENERATED_PATH)
	warnings.append("no generated input table at %s; leaving project.godot [input] untouched (no transcription fallback)" % GENERATED_PATH)
	return {"source": "", "rows": [] as Array, "warnings": warnings, "shipping": 0, "actions": 0, "skipped_contexts": [], "skipped_mappings": 0, "skipped_only_actions": [] as Array}


## Adapts the producer schema (`contexts[*].mappings`) to the consumer rows.
## Shipping contexts only; the two `*_ClimbTest` / `*_Testing` dev contexts are
## skipped and counted (they hold the other 146 mapping rows and only add
## `IA_AbilityLoadout_01` / `IA_Ability_SpecialAttack`, which no shipping context
## binds). The producer's `shipping` flag wins; the name list is the fallback.
static func _adapt_generated(doc: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	var schema: String = str(doc.get("schema", ""))
	if schema != "" and schema != SCHEMA:
		warnings.append("generated input schema %s != %s" % [schema, SCHEMA])
	var contexts_v: Variant = doc.get("contexts", null)
	if not (contexts_v is Dictionary):
		warnings.append("generated input table has no contexts{...} object")
		return {"rows": [], "warnings": warnings}
	var groups: Dictionary = {} # IA -> Array[mapping] (shipping contexts only)
	var order: Array[String] = []
	var skipped_contexts: Array[String] = []
	var skipped_actions: Dictionary = {}
	var skipped_mappings: int = 0
	var shipping_mappings: int = 0
	for ctx_name_v: Variant in (contexts_v as Dictionary).keys():
		var ctx_name: String = str(ctx_name_v)
		var ctx_v: Variant = (contexts_v as Dictionary)[ctx_name_v]
		if not (ctx_v is Dictionary):
			continue
		var ctx: Dictionary = ctx_v as Dictionary
		var maps_v: Variant = ctx.get("mappings", null)
		var maps: Array = maps_v as Array if maps_v is Array else []
		if not bool(ctx.get("shipping", SHIPPING_CONTEXTS.has(ctx_name))):
			skipped_contexts.append(ctx_name)
			skipped_mappings += maps.size()
			for m_v: Variant in maps:
				if m_v is Dictionary:
					var skipped_ia: String = str((m_v as Dictionary).get("action", ""))
					if skipped_ia != "":
						skipped_actions[skipped_ia] = true
			continue
		shipping_mappings += maps.size()
		for m_v: Variant in maps:
			if not (m_v is Dictionary):
				warnings.append("generated input mapping is not a dictionary in %s" % ctx_name)
				continue
			var m: Dictionary = (m_v as Dictionary).duplicate(true)
			m["_ctx"] = _context_tag(ctx_name)
			var ia: String = str(m.get("action", ""))
			if ia == "":
				warnings.append("generated input mapping without an action name in %s" % ctx_name)
				continue
			if not groups.has(ia):
				groups[ia] = [] as Array
				order.append(ia)
			(groups[ia] as Array).append(m)
	var rows: Array[Dictionary] = []
	var consumed: Dictionary = {}
	var seen_ids: Dictionary = {}
	for decision_v: Variant in PORT_DECISIONS:
		var decision: Dictionary = decision_v as Dictionary
		var kind: String = str(decision.get("kind", ""))
		if kind == "split":
			var split_ia: String = str(decision.get("ia", ""))
			if not groups.has(split_ia):
				warnings.append("port decision split: no shipping mapping for %s" % split_ia)
				continue
			consumed[split_ia] = true
			rows.append_array(_split_rows(decision, groups[split_ia] as Array, warnings))
		elif kind == "merge":
			var merged: Array = []
			var merge_id: String = str(decision.get("id", ""))
			for src_v: Variant in (decision.get("ias", []) as Array):
				var src: String = str(src_v)
				if not groups.has(src):
					warnings.append("port decision %s: no shipping mapping for %s" % [merge_id, src])
					continue
				consumed[src] = true
				merged.append_array(groups[src] as Array)
			if merged.is_empty():
				continue
			seen_ids[merge_id] = true
			rows.append(_owner_row(str((merged[0] as Dictionary).get("action", "")), merged, merge_id, decision))
			for i: int in range(1, merged.size()):
				rows.append(_extra_row(merged[i] as Dictionary, merge_id, "merged into " + merge_id))
	for ia: String in order:
		if consumed.has(ia):
			continue
		var maps: Array = groups[ia] as Array
		var id: String = str(PORT_ID_FOR_IA.get(ia, ""))
		var decision: Dictionary = _pick_decision_for_ia(ia)
		if id != "" and seen_ids.has(id):
			warnings.append("port id %s is produced by more than one authored action (%s)" % [id, ia])
			id = ""
		if id != "":
			seen_ids[id] = true
		rows.append(_owner_row(ia, maps, id, decision))
		for i: int in range(1, maps.size()):
			rows.append(_extra_row(maps[i] as Dictionary, id if id != "" else ia))
	for decision_v: Variant in PORT_DECISIONS:
		var decision: Dictionary = decision_v as Dictionary
		if str(decision.get("kind", "")) == "legacy":
			rows.append(_legacy_row(decision))
	var actions: Dictionary = {}
	for r: Dictionary in rows:
		var row_ia: String = str(r.get("ia", ""))
		if row_ia.begins_with("IA_"):
			actions[row_ia] = true
	# Actions that exist only in a skipped dev context: proof the skip removed no
	# shipping action (empty on the 2026-11-25 tree apart from the two dev-only IAs).
	var skipped_only: Array[String] = []
	for skipped_v: Variant in skipped_actions.keys():
		var skipped_ia: String = str(skipped_v)
		if not groups.has(skipped_ia):
			skipped_only.append(skipped_ia)
	skipped_only.sort()
	return {
		"rows": rows,
		"warnings": warnings,
		"shipping_mappings": shipping_mappings,
		"actions": actions.size(),
		"skipped_contexts": skipped_contexts,
		"skipped_mappings": skipped_mappings,
		"skipped_only_actions": skipped_only,
	}


static func _context_tag(context_name: String) -> String:
	if context_name.ends_with("MapTool"):
		return "map"
	if context_name.ends_with("Radial"):
		return "radial"
	return "character"


static func _pick_decision_for_ia(ia: String) -> Dictionary:
	for decision_v: Variant in PORT_DECISIONS:
		var decision: Dictionary = decision_v as Dictionary
		if str(decision.get("kind", "")) == "pick" and str(decision.get("ia", "")) == ia:
			return decision
	return {}


## One owner row: all of the action's authored mappings merged into one binding
## (kb/pad union, tightest authored deadzone, first authored trigger/chord/
## mappable). Later mappings of the same action become coverage rows so nothing
## authored is dropped from the table.
static func _owner_row(ia: String, maps: Array, id: String, decision: Dictionary) -> Dictionary:
	var first: Dictionary = maps[0] as Dictionary
	var row: Dictionary = {
		"id": id,
		"ia": ia,
		"ctx": str(first.get("_ctx", "character")),
		"kb": [] as Array[String],
		"pad": [] as Array[String],
		"deadzone": 0.2,
		"trigger": "",
		"chord": "",
		"mappable": {},
		"consumer": str(decision.get("consumer", PORT_CONSUMERS.get(id, ""))),
		"note": str(decision.get("note", PORT_NOTES.get(id, ""))),
	}
	var deadzone: float = -1.0
	for m_v: Variant in maps:
		var m: Dictionary = m_v as Dictionary
		_add_mapping_keys(row, m)
		deadzone = maxf(deadzone, _mapping_deadzone(m))
		if str(row["trigger"]) == "":
			row["trigger"] = _trigger_text(m)
		if str(row["chord"]) == "" and m.get("chord_action") != null:
			row["chord"] = str(m["chord_action"])
		if (row["mappable"] as Dictionary).is_empty():
			row["mappable"] = _mappable_of(m)
		var edge: Dictionary = _edge_boost_of(m)
		if not edge.is_empty():
			row["edge_threshold"] = edge["threshold"]
			row["edge_boost_curve"] = edge["curve"]
	if deadzone >= 0.0:
		row["deadzone"] = deadzone
	if id == "" and str(row["note"]) == "":
		row["note"] = str(PORT_NOTES.get(ia, ""))
	if str(decision.get("trigger", "")) != "":
		row["trigger"] = str(decision["trigger"])
	return row


## A coverage row for one authored mapping beyond the first: its own key, its own
## IA (so the action vocabulary stays complete), but no id and no rebind cell.
static func _extra_row(m: Dictionary, owner_label: String, note_override: String = "") -> Dictionary:
	var row: Dictionary = {
		"id": "",
		"ia": str(m.get("action", "")),
		"ctx": str(m.get("_ctx", "character")),
		"kb": [] as Array[String],
		"pad": [] as Array[String],
		"deadzone": 0.2,
		"trigger": _trigger_text(m),
		"chord": str(m.get("chord_action", "")) if m.get("chord_action") != null else "",
		"mappable": {},
		"consumer": "",
		"note": note_override if note_override != "" else "additional authored mapping of %s (keys are bound through the owner row)" % owner_label,
	}
	var deadzone: float = _mapping_deadzone(m)
	if deadzone >= 0.0:
		row["deadzone"] = deadzone
	_add_mapping_keys(row, m)
	return row


## The `IA_Move` split: each declared port id takes its authored 1D key and one
## signed axis of the authored 2D stick key. A key the IMC no longer binds is
## reported, never invented.
static func _split_rows(decision: Dictionary, maps: Array, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ia: String = str(decision.get("ia", ""))
	var first: Dictionary = maps[0] as Dictionary
	var deadzone: float = -1.0
	var pad_names: Array[String] = []
	var kb_names: Array[String] = []
	for m_v: Variant in maps:
		var m: Dictionary = m_v as Dictionary
		deadzone = maxf(deadzone, _mapping_deadzone(m))
		for name: String in _port_key_names(str(m.get("key", "")), m):
			var bag: Array[String] = pad_names if bool(m.get("key_is_gamepad", false)) else kb_names
			if not bag.has(name):
				bag.append(name)
	if deadzone < 0.0:
		deadzone = 0.2
	for def_v: Variant in (decision.get("ids", []) as Array):
		var def: Dictionary = def_v as Dictionary
		var id: String = str(def.get("id", ""))
		var kb_key: String = str(def.get("kb", ""))
		var pad_key: String = str(def.get("pad", ""))
		if kb_key != "" and not kb_names.has(kb_key):
			warnings.append("%s: IA_Move no longer binds the authored key %s" % [id, kb_key])
		if pad_key != "" and not pad_names.has(pad_key):
			warnings.append("%s: IA_Move no longer binds the authored axis %s" % [id, pad_key])
		var kb: Array[String] = []
		var pad: Array[String] = []
		if kb_key != "":
			kb.append(kb_key)
		if pad_key != "":
			pad.append(pad_key)
		out.append({
			"id": id, "ia": ia, "ctx": str(first.get("_ctx", "character")),
			"kb": kb, "pad": pad, "deadzone": deadzone, "trigger": "", "chord": "",
			"mappable": _mappable_for_key(maps, kb_key),
			"consumer": str(decision.get("consumer", "")),
			"note": str(decision.get("note", "")),
		})
	return out


static func _legacy_row(decision: Dictionary) -> Dictionary:
	var kb: Array[String] = []
	for v: Variant in (decision.get("kb", []) as Array):
		kb.append(str(v))
	var pad: Array[String] = []
	for v: Variant in (decision.get("pad", []) as Array):
		pad.append(str(v))
	return {
		"id": str(decision.get("id", "")),
		"ia": str(decision.get("ia", "")),
		"ctx": "legacy",
		"kb": kb, "pad": pad, "deadzone": 0.2, "trigger": "", "chord": "",
		"mappable": {},
		"consumer": str(decision.get("consumer", "")),
		"note": str(decision.get("note", "")),
	}


# ---------------------------------------------------------------------------
# Producer field helpers
# ---------------------------------------------------------------------------

## One authored key -> the port key name(s). Wheel sign comes from the authored
## OSEEnhancedInputModifierRequireSign; 2D sticks expand to both signed axes.
static func _port_key_names(key_name: String, m: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if key_name == "":
		return out
	if key_name == "MouseWheelAxis":
		out.append("MouseWheelAxis+" if _require_sign_positive(m) else "MouseWheelAxis-")
		return out
	if KEY_ALIASES.has(key_name):
		out.append(str(KEY_ALIASES[key_name]))
		return out
	if TWO_AXIS_KEYS.has(key_name):
		for v: Variant in (TWO_AXIS_KEYS[key_name] as Array):
			out.append(str(v))
		return out
	out.append(key_name)
	return out


static func _add_mapping_keys(row: Dictionary, m: Dictionary) -> void:
	var names: Array[String] = _port_key_names(str(m.get("key", "")), m)
	var bag: Array = row["pad"] if bool(m.get("key_is_gamepad", false)) else row["kb"]
	for key_name: String in names:
		if not bag.has(key_name):
			bag.append(key_name)


static func _require_sign_positive(m: Dictionary) -> bool:
	var mods_v: Variant = m.get("modifiers", [])
	if not (mods_v is Array):
		return false
	for md_v: Variant in (mods_v as Array):
		if not (md_v is Dictionary):
			continue
		var md: Dictionary = md_v as Dictionary
		if str(md.get("type", "")) != "OSEEnhancedInputModifierRequireSign":
			continue
		return str(md.get("sign", "")).ends_with("Positive")
	return false


## The mapping's authored DeadZone lower bound, or -1 when it declares none.
static func _mapping_deadzone(m: Dictionary) -> float:
	var mods_v: Variant = m.get("modifiers", [])
	if not (mods_v is Array):
		return -1.0
	for md_v: Variant in (mods_v as Array):
		if not (md_v is Dictionary):
			continue
		var md: Dictionary = md_v as Dictionary
		if str(md.get("type", "")) != "DeadZone":
			continue
		var lower_v: Variant = md.get("lower", null)
		if lower_v == null:
			var props_v: Variant = md.get("properties", null)
			if props_v is Dictionary:
				lower_v = (props_v as Dictionary).get("LowerThreshold", null)
		if lower_v != null:
			return float(lower_v)
	return -1.0


## "hold:0.2" / "tap" / "pressed" / "" from the authored trigger object.
## Chord triggers are recorded in `chord` instead (the port holds the chord action).
static func _trigger_text(m: Dictionary) -> String:
	var trig_v: Variant = m.get("trigger", null)
	if not (trig_v is Dictionary):
		return ""
	var trig: Dictionary = trig_v
	match str(trig.get("type", "")):
		"Hold":
			return "hold:%s" % _trim_float(float(trig.get("hold_time", HOLD_SECONDS)))
		"Tap":
			return "tap"
		"Pressed":
			return "pressed"
		"Down":
			return "down"
	return ""


static func _trim_float(value: float) -> String:
	var s: String = "%.3f" % value
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s


## The authored rebind cell for a mapping: only rows the shipped settings screen
## offers (PlayerMappableKeySettings) carry one. Display fields are the
## ST_Settings_Input keys, so labels and categories stay authored.
static func _mappable_of(m: Dictionary) -> Dictionary:
	if not bool(m.get("player_mappable", false)):
		return {}
	var label: String = str(m.get("display_name_key", ""))
	if label == "":
		label = str(m.get("display_name", ""))
	if label == "":
		label = str(m.get("mappable_name", ""))
	var category: String = str(m.get("display_category", ""))
	if label == "" and category == "":
		return {}
	return {"category": category, "label": label}


static func _mappable_for_key(maps: Array, key_name: String) -> Dictionary:
	for m_v: Variant in maps:
		var m: Dictionary = m_v as Dictionary
		if str(m.get("key", "")) == key_name:
			return _mappable_of(m)
	return {}


## OSEEnhancedInputGamepadEdgeAcceleration on the look mapping: the authored
## threshold and boost-curve name, carried on the `look_gamepad` row so the
## reader never hardcodes them.
static func _edge_boost_of(m: Dictionary) -> Dictionary:
	var mods_v: Variant = m.get("modifiers", [])
	if not (mods_v is Array):
		return {}
	for md_v: Variant in (mods_v as Array):
		if not (md_v is Dictionary):
			continue
		var md: Dictionary = md_v as Dictionary
		if str(md.get("type", "")) != "OSEEnhancedInputGamepadEdgeAcceleration":
			continue
		return {
			"threshold": float(md.get("edge_threshold", EDGE_BOOST_THRESHOLD_FALLBACK)),
			"curve": str(md.get("boost_over_time", EDGE_BOOST_CURVE_FALLBACK)),
		}
	return {}


# ---------------------------------------------------------------------------
# Gamepad look edge boost (Curve_GamepadLookEdgeBoost)
# ---------------------------------------------------------------------------

## Authored edge-acceleration threshold read from the `look_gamepad` row (the
## generated modifier's `edge_threshold`); 0.95 is the documented fallback.
static func gamepad_look_edge_threshold() -> float:
	var row: Dictionary = row_for("look_gamepad")
	var v: Variant = row.get("edge_threshold", null)
	return float(v) if v != null else EDGE_BOOST_THRESHOLD_FALLBACK


## Curve_GamepadLookEdgeBoost sampled at the seconds the stick has spent past the
## authored threshold: 1.0 until it crosses, then the authored 1.0 -> 1.5 ramp over
## the curve's 0..0.4 s BoostOverTime. The look tick that applies it belongs to the
## input-feel phase; this is the data reader and its tested contract.
static func gamepad_look_edge_boost(stick_magnitude: float, seconds_at_edge: float) -> float:
	var row: Dictionary = row_for("look_gamepad")
	var threshold: float = float(row.get("edge_threshold", EDGE_BOOST_THRESHOLD_FALLBACK))
	if absf(stick_magnitude) <= threshold:
		return 1.0
	var curve_name: String = str(row.get("edge_boost_curve", EDGE_BOOST_CURVE_FALLBACK))
	var gd: Node = _game_data_node()
	if gd == null or not gd.has_method("eval_standalone_curve"):
		return 1.0
	return maxf(1.0, float(gd.call("eval_standalone_curve", curve_name, maxf(seconds_at_edge, 0.0), "Value", 1.0)))


static func _game_data_node() -> Node:
	if _game_data != null and is_instance_valid(_game_data):
		return _game_data
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_game_data = tree.root.get_node_or_null("GameData")
	return _game_data


# ---------------------------------------------------------------------------
# UE key name <-> Godot event
# ---------------------------------------------------------------------------

## One event per binding name; a full axis name yields two opposite events, so the
## caller gets an array. `Mouse2D` yields none (mouse look is read as motion).
static func events_for_key(key_name: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if LETTER_KEYS.has(key_name) or KEY_CODES.has(key_name):
		var kev: InputEventKey = InputEventKey.new()
		kev.physical_keycode = int(LETTER_KEYS[key_name] if LETTER_KEYS.has(key_name) else KEY_CODES[key_name])
		out.append(kev)
		return out
	if MOUSE_BUTTONS.has(key_name):
		var mev: InputEventMouseButton = InputEventMouseButton.new()
		mev.button_index = int(MOUSE_BUTTONS[key_name])
		out.append(mev)
		return out
	if JOY_BUTTONS.has(key_name):
		var jev: InputEventJoypadButton = InputEventJoypadButton.new()
		jev.button_index = int(JOY_BUTTONS[key_name])
		out.append(jev)
		return out
	if JOY_AXES.has(key_name):
		var pair: Array = JOY_AXES[key_name] as Array
		var axis: JoyAxis = int(pair[0]) as JoyAxis
		var sign_v: float = float(pair[1])
		if sign_v == 0.0:
			out.append(_axis_event(axis, -1.0))
			out.append(_axis_event(axis, 1.0))
		else:
			out.append(_axis_event(axis, sign_v))
		return out
	return out


static func _axis_event(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e: InputEventJoypadMotion = InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


## Inverse of events_for_key for bindable events. Returns "" for motion/unknown
## events that the rebind UI does not accept (axis rebinding is out of scope).
static func key_name_for_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = (ev as InputEventKey).physical_keycode
		if code == 0:
			code = (ev as InputEventKey).keycode
		for name: String in LETTER_KEYS.keys():
			if int(LETTER_KEYS[name]) == code:
				return name
		for name: String in KEY_CODES.keys():
			if int(KEY_CODES[name]) == code:
				return name
		return ""
	if ev is InputEventMouseButton:
		var idx: int = (ev as InputEventMouseButton).button_index
		for name: String in MOUSE_BUTTONS.keys():
			if int(MOUSE_BUTTONS[name]) == idx:
				return name
		return ""
	if ev is InputEventJoypadButton:
		var bidx: int = (ev as InputEventJoypadButton).button_index
		for name: String in JOY_BUTTONS.keys():
			if int(JOY_BUTTONS[name]) == bidx:
				return name
		return ""
	if ev is InputEventJoypadMotion:
		var mev: InputEventJoypadMotion = ev as InputEventJoypadMotion
		for name: String in JOY_AXES.keys():
			var pair: Array = JOY_AXES[name] as Array
			if int(pair[0]) == int(mev.axis) and float(pair[1]) == signf(mev.axis_value):
				return name
		return ""
	return ""


static func device_for_key(key_name: String) -> String:
	return DEVICE_PAD if is_pad_key(key_name) else DEVICE_KB


# ---------------------------------------------------------------------------
# InputMap builder
# ---------------------------------------------------------------------------

## Rebuilds the port's actions from the table. `overrides` is
## {action: {"kb": ["G"], "pad": ["Gamepad_FaceButton_Top"]}} — a device key
## present in an override replaces that device's authored list; the other device
## keeps the authored list. Returns a small report for tests and logs.
static func apply_to_input_map(table_rows: Array = [], overrides: Dictionary = {}) -> Dictionary:
	# With no loaded table there is nothing to bind: rows() is empty and the
	# actions already in project.godot [input] stay untouched (no transcription).
	var use_rows: Array = table_rows if not table_rows.is_empty() else rows()
	var report: Dictionary = {"actions": 0, "events": 0, "unbound": [] as Array[String], "source": ""}
	var seen: Dictionary = {}
	for v: Variant in use_rows:
		var r: Dictionary = v as Dictionary
		var id: String = str(r.get("id", ""))
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		var authored_kb: Array = r.get("kb", []) as Array
		var authored_pad: Array = r.get("pad", []) as Array
		if authored_kb.is_empty() and authored_pad.is_empty():
			continue
		var ov: Dictionary = {}
		if overrides.has(id) and overrides[id] is Dictionary:
			ov = overrides[id] as Dictionary
		var kb_list: Array = (ov.get(DEVICE_KB, authored_kb) as Array)
		var pad_list: Array = (ov.get(DEVICE_PAD, authored_pad) as Array)
		if not InputMap.has_action(id):
			InputMap.add_action(id)
		InputMap.action_set_deadzone(id, float(r.get("deadzone", 0.2)))
		InputMap.action_erase_events(id)
		var event_count: int = 0
		for key_v: Variant in kb_list:
			for ev: InputEvent in events_for_key(str(key_v)):
				InputMap.action_add_event(id, ev)
				event_count += 1
		for key_v: Variant in pad_list:
			for ev: InputEvent in events_for_key(str(key_v)):
				InputMap.action_add_event(id, ev)
				event_count += 1
		report["actions"] = int(report["actions"]) + 1
		report["events"] = int(report["events"]) + event_count
		if event_count == 0:
			(report["unbound"] as Array[String]).append(id)
	report["source"] = str(load_report().get("source", ""))
	return report


## Snapshot of one action as key names, for drift tests and the settings screen.
static func bound_keys(id: String) -> Dictionary:
	var out: Dictionary = {"kb": [] as Array[String], "pad": [] as Array[String]}
	if not InputMap.has_action(id):
		return out
	for ev: InputEvent in InputMap.action_get_events(id):
		var name: String = key_name_for_event(ev)
		if name == "":
			continue
		var dev: String = device_for_key(name)
		(out[dev] as Array[String]).append(name)
	return out
