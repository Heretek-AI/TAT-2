class_name InputActions
extends RefCounted
## Authored Enhanced Input table for TAT-2, and the InputMap builder on top of it.
##
## Source of truth (S2): `extracted/json/Gameplay/Input/{Character,Radial,Map}/IMC_*.json`
## — 91 mapping rows / 52 unique `IA_*` actions, plus the modifier/trigger values
## carried on the context subobjects (deadzone 0.18 move, 0.12 axial look,
## 0.2 s hold, 90/52 deg-per-s gamepad turn, LB chords). `IA_Move` is one swizzled
## 2D action in the shipped context; the port keeps its four 1D actions because
## every port consumer (`thief_character.gd:1277`) polls them by name — the keys and
## the 0.18 deadzone are 1:1.
##
## Two-tier data contract (REMEDIATION_PLAN T06 coordination):
##   1. `res://data/generated/input/input_actions.json` — T01-PIPELINE's producer.
##      When present and schema-valid it wins, and this file's AUTHORED_ROWS is
##      only the rebind/reset default set.
##   2. `AUTHORED_ROWS` below — a provenance-stamped transcription of the rows in
##      (1)'s absence. It is **not** a producer: it exists so the P0 (gamepad look
##      / fire / tools) can ship before T01 lands. Delete it when the producer lands
##      and the generated file is in the audit baseline.
##   3. If neither is usable, the actions already in `project.godot [input]` stay
##      untouched (no destructive fallback) and a warning names the reason.
##
## Port ids are runtime contracts (AGENTS rule 7): the 21 pre-existing ids keep
## their names. Authored actions with no port consumer are still in the table and
## still bound, so the diff and the rebind UI are complete — they simply have
## `consumer == ""`.

const GENERATED_PATH: String = "res://data/generated/input/input_actions.json"
const SCHEMA: String = "tat2.input_actions/1"
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
## Authored edge-boost threshold (OSEEnhancedInputGamepadEdgeAcceleration_0).
const EDGE_BOOST_THRESHOLD: float = 0.95

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
# Authored sensitivity ladder (`DefaultGame.ini:483-486`)
# ---------------------------------------------------------------------------
# [ /Script/OSECore.OSEInputDeveloperSettings ]
#   MouseLookSensitivity  = VeryLow 0.5, Low 0.75, Normal 1.0, Fast 1.5, VeryFast 2.0
#   GamepadLookSensitivity= VeryLow 0.5, Low 0.75, Normal 1.0, Fast 1.25, VeryFast 1.5
#   GamepadMoveSensitivity= VeryLow 0.5, Low 0.75, Normal 1.0, Fast 1.5, VeryFast 2.0
# The shipped build saves one step per hardware type (OSECore.hpp
# FOSEGamepadMouseKeyboardSettings / FOSEGamepadInputSettings), not a pixel slider.
#
# The 0.0025 rad/px base is the **port's unit bridge** (the value the port shipped
# as its invented default), NOT authored: RE-H-08 records that the UE chain
# (0.07 deg/count x FOVScale/tan(halfFOV)) cannot be mapped to Godot pixels without
# an unshot measurement. The ladder *shape* and every multiplier are authored; only
# the base unit is carried over so "Normal" keeps the current feel.
const MOUSE_RAD_PER_PX_BASE: float = 0.0025
const SENSITIVITY_STEPS: Array[String] = ["VeryLow", "Low", "Normal", "Fast", "VeryFast"]
const MOUSE_LOOK_MULT: Array[float] = [0.5, 0.75, 1.0, 1.5, 2.0]
const PAD_LOOK_MULT: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5]
const PAD_MOVE_MULT: Array[float] = [0.5, 0.75, 1.0, 1.5, 2.0]

static func sensitivity_step_index(name: String) -> int:
	var idx: int = SENSITIVITY_STEPS.find(name)
	return idx if idx >= 0 else 2 # authored default: Normal


static func sensitivity_step_name(index: int) -> String:
	return SENSITIVITY_STEPS[clampi(index, 0, SENSITIVITY_STEPS.size() - 1)]


static func mouse_rad_per_px(step_name: String) -> float:
	return MOUSE_RAD_PER_PX_BASE * MOUSE_LOOK_MULT[sensitivity_step_index(step_name)]


static func pad_look_scale(step_name: String) -> float:
	return PAD_LOOK_MULT[sensitivity_step_index(step_name)]


static func pad_move_scale(step_name: String) -> float:
	return PAD_MOVE_MULT[sensitivity_step_index(step_name)]


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

## Row schema: id, ia, ctx, kb[], pad[], deadzone, trigger, chord, mappable{}, consumer, note.
## id == "" marks a coverage-only row (a shipped mapping the port has no action for,
## or one consumed by another row); it is bound only through the row that owns the id.
const AUTHORED_ROWS: Array[Dictionary] = [
	{"id": "move_forward", "ia": "IA_Move", "ctx": "character", "kb": ["W"], "pad": ["Gamepad_LeftY-"], "deadzone": 0.18, "trigger": "", "chord": "", "mappable": {"category": "Movement", "label": "InputSetting.Movement.MoveForward"}, "consumer": "thief_character.gd:1277", "note": "authored IA_Move is one swizzled 2D action; the port splits it into four 1D actions (1:1 keys, same deadzone)"},
	{"id": "move_backward", "ia": "IA_Move", "ctx": "character", "kb": ["S"], "pad": ["Gamepad_LeftY+"], "deadzone": 0.18, "trigger": "", "chord": "", "mappable": {"category": "Movement", "label": "InputSetting.Movement.MoveBackward"}, "consumer": "thief_character.gd:1277", "note": "port split of IA_Move"},
	{"id": "move_left", "ia": "IA_Move", "ctx": "character", "kb": ["A"], "pad": ["Gamepad_LeftX-"], "deadzone": 0.18, "trigger": "", "chord": "", "mappable": {"category": "Movement", "label": "InputSetting.Movement.MoveLeft"}, "consumer": "thief_character.gd:1277", "note": "port split of IA_Move"},
	{"id": "move_right", "ia": "IA_Move", "ctx": "character", "kb": ["D"], "pad": ["Gamepad_LeftX+"], "deadzone": 0.18, "trigger": "", "chord": "", "mappable": {"category": "Movement", "label": "InputSetting.Movement.MoveRight"}, "consumer": "thief_character.gd:1277", "note": "port split of IA_Move"},
	{"id": "jump", "ia": "IA_Movement_Jump", "ctx": "character", "kb": ["SpaceBar"], "pad": ["Gamepad_FaceButton_Bottom"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {"category": "Movement", "label": "InputSetting.Movement.Jump"}, "consumer": "thief_character.gd:1319", "note": ""},
	{"id": "crouch", "ia": "IA_Movement_Crouch", "ctx": "character", "kb": ["LeftControl"], "pad": ["Gamepad_FaceButton_Right"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {"category": "Movement", "label": "InputSetting.Movement.Crouch"}, "consumer": "thief_character.gd:794", "note": "port previously bound C, which is authored Attack"},
	{"id": "crouch_hold", "ia": "IA_Movement_CrouchHold", "ctx": "character", "kb": ["LeftAlt"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {"category": "Movement", "label": "InputSetting.Movement.CrouchHold"}, "consumer": "", "note": "no port consumer (crouch is a toggle); recorded"},
	{"id": "sprint", "ia": "IA_Movement_Run", "ctx": "character", "kb": ["LeftShift"], "pad": ["Gamepad_LeftThumbstick"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {"category": "Movement", "label": "InputSetting.Movement.Sprint"}, "consumer": "thief_character.gd:787,1287", "note": "port merges IA_Movement_Run (hold Shift) and IA_Ability_RunToggle (L3); identical to the previous port behaviour"},
	{"id": "dodge", "ia": "IA_Movement_Dodge", "ctx": "character", "kb": ["ThumbMouseButton", "ThumbMouseButton2", "LeftShift"], "pad": ["Gamepad_LeftThumbstick"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; authored double-binds L3 with IA_Ability_RunToggle"},
	{"id": "lean_left", "ia": "IA_Ability_Lean_Left", "ctx": "character", "kb": ["Q"], "pad": ["Gamepad_LeftX-"], "deadzone": 0.2, "trigger": "", "chord": "IA_ControllerLeftShoulder", "mappable": {}, "consumer": "thief_character.gd:1190", "note": "pad row is chorded with LB in the IMC; InputContext enforces the chord"},
	{"id": "lean_right", "ia": "IA_Ability_Lean_Right", "ctx": "character", "kb": ["E"], "pad": ["Gamepad_LeftX+"], "deadzone": 0.2, "trigger": "", "chord": "IA_ControllerLeftShoulder", "mappable": {}, "consumer": "thief_character.gd:1192", "note": "port previously bound R, which is authored Secondary Interact"},
	{"id": "look_gamepad", "ia": "IA_LookGamepad", "ctx": "character", "kb": [], "pad": ["Gamepad_RightX-", "Gamepad_RightX+", "Gamepad_RightY-", "Gamepad_RightY+"], "deadzone": 0.12, "trigger": "", "chord": "", "mappable": {}, "consumer": "thief_character.gd:_tick_gamepad_look (new)", "note": "authored deadzone 0.12 Axial, turn 90/52 deg/s, edge boost 0.95"},
	{"id": "look_mouse", "ia": "IA_LookMouseKeyboard", "ctx": "character", "kb": ["Mouse2D"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "thief_character.gd:778", "note": "mouse look is read as InputEventMouseMotion, not an action; metadata row only"},
	{"id": "prevent_look_gamepad", "ia": "IA_PreventLookGamepad", "ctx": "character", "kb": [], "pad": ["Gamepad_RightX-", "Gamepad_RightX+", "Gamepad_RightY-", "Gamepad_RightY+"], "deadzone": 0.2, "trigger": "", "chord": "IA_ControllerLeftShoulder", "mappable": {}, "consumer": "input_context.gd suppression", "note": "authored LB chord suppresses pad look while the chord is held"},
	{"id": "prevent_move_gamepad", "ia": "IA_PreventMoveGamepad", "ctx": "character", "kb": [], "pad": ["Gamepad_LeftX-", "Gamepad_LeftX+", "Gamepad_LeftY-", "Gamepad_LeftY+"], "deadzone": 0.2, "trigger": "", "chord": "IA_ControllerLeftShoulder", "mappable": {}, "consumer": "input_context.gd suppression", "note": "authored LB chord suppresses pad move while the chord is held"},
	{"id": "interact", "ia": "IA_Interact", "ctx": "character", "kb": ["F"], "pad": ["Gamepad_FaceButton_Left"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "thief_character.gd:800", "note": "port previously also bound E, which is authored Traversal / Lean_Right"},
	{"id": "secondary_interact", "ia": "IA_Secondary_Interact", "ctx": "character", "kb": ["R"], "pad": ["Gamepad_FaceButton_Top"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; R was previously mis-bound to lean_right"},
	{"id": "ping_menu", "ia": "IA_Ability_OpenRadial", "ctx": "character", "kb": ["MiddleMouseButton"], "pad": ["Gamepad_RightShoulder"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {"category": "Interaction", "label": "InputSetting.Interaction.Ping"}, "consumer": "hud.gd:2297", "note": "authored display name is Ping"},
	{"id": "map_toggle", "ia": "IA_ToolSelect_EquipMap", "ctx": "character", "kb": ["Tab", "M"], "pad": ["Gamepad_Special_Left"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {"category": "Interaction", "label": "InputSetting.Interaction.Map"}, "consumer": "hud.gd:2289", "note": "port previously dropped M"},
	{"id": "mission_panel", "ia": "IA_MissionPanelToggle", "ctx": "character", "kb": ["CapsLock"], "pad": ["Gamepad_Special_Left"], "deadzone": 0.2, "trigger": "pressed", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; recorded"},
	{"id": "primary_action", "ia": "IA_Ability_Action_Primary", "ctx": "character", "kb": ["LeftMouseButton"], "pad": ["Gamepad_RightTrigger"], "deadzone": 0.2, "trigger": "tap+hold:0.2", "chord": "", "mappable": {"category": "Primary Fire", "label": "InputSetting.PrimaryFire"}, "consumer": "thief_character.gd:837", "note": "authored also has _Tap and _Hold variants (0.2 s); the port has one press action"},
	{"id": "secondary_action", "ia": "IA_Ability_Action_Secondary", "ctx": "character", "kb": ["RightMouseButton"], "pad": ["Gamepad_LeftTrigger"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "thief_character.gd:839", "note": ""},
	{"id": "attack", "ia": "IA_Ability_Attack", "ctx": "character", "kb": ["C"], "pad": ["Gamepad_RightShoulder"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; C was previously mis-bound to crouch"},
	{"id": "block", "ia": "IA_Ability_Block", "ctx": "character", "kb": ["V"], "pad": ["Gamepad_LeftTrigger"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; V was previously mis-bound to thief_vision"},
	{"id": "melee_toggle", "ia": "IA_Ability_MeleeToggle", "ctx": "character", "kb": ["H"], "pad": ["Gamepad_LeftShoulder"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; recorded"},
	{"id": "ranged_attack", "ia": "IA_Ability_RangedAttack", "ctx": "character", "kb": ["RightMouseButton"], "pad": ["Gamepad_LeftTrigger"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; recorded"},
	{"id": "ranged_reload", "ia": "IA_Ability_RangedReload", "ctx": "character", "kb": ["F"], "pad": ["Gamepad_FaceButton_Left"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; recorded"},
	{"id": "traversal", "ia": "IA_Ability_Traversal", "ctx": "character", "kb": ["E"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; E was previously mis-bound to interact"},
	{"id": "ability", "ia": "IA_Ability_OpenThiefsignRadial", "ctx": "character", "kb": ["X"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "thief_character.gd:819", "note": "EXPANSION: the port's per-thief signature ability takes the authored thiefsign slot (X); the shipped radial menu is unimplemented"},
	{"id": "tool_1", "ia": "IA_Ability03", "ctx": "character", "kb": ["One"], "pad": ["Gamepad_DPad_Left"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {"category": "Tools", "label": "InputSetting.Tools.SlotOne"}, "consumer": "thief_character.gd:821", "note": ""},
	{"id": "tool_2", "ia": "IA_Ability04", "ctx": "character", "kb": ["Two"], "pad": ["Gamepad_DPad_Up"], "deadzone": 0.2, "trigger": "pressed", "chord": "", "mappable": {"category": "Tools", "label": "InputSetting.Tools.SlotTwo"}, "consumer": "thief_character.gd:823", "note": "authored row carries a redundant InputTriggerPressed"},
	{"id": "tool_3", "ia": "IA_Ability05", "ctx": "character", "kb": ["Three"], "pad": ["Gamepad_DPad_Right"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {"category": "Tools", "label": "InputSetting.Tools.SlotThree"}, "consumer": "thief_character.gd:825", "note": ""},
	{"id": "tool_4", "ia": "IA_ToolSelect_EquipVistaraDiamond", "ctx": "character", "kb": ["Four"], "pad": ["Gamepad_DPad_Down"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {"category": "Tools", "label": "InputSetting.Tools.SlotFour"}, "consumer": "thief_character.gd:835", "note": "Four is authored on both IA_Ability06 and the Vistara action; the port ships Vistara"},
	{"id": "tool_select_next", "ia": "IA_ToolSelect_EquipNextWeapon", "ctx": "character", "kb": ["MouseWheelAxis+"], "pad": ["Gamepad_RightX+"], "deadzone": 0.2, "trigger": "", "chord": "IA_ControllerLeftShoulder", "mappable": {}, "consumer": "", "note": "no port consumer; wheel direction is an inference from RequireSign (see report)"},
	{"id": "tool_select_prev", "ia": "IA_ToolSelect_EquipPreviousWeapon", "ctx": "character", "kb": ["MouseWheelAxis-"], "pad": ["Gamepad_RightX-"], "deadzone": 0.2, "trigger": "", "chord": "IA_ControllerLeftShoulder", "mappable": {}, "consumer": "", "note": "no port consumer; wheel direction is an inference from RequireSign (see report)"},
	{"id": "input_chord_lb", "ia": "IA_ControllerLeftShoulder", "ctx": "character", "kb": [], "pad": ["Gamepad_LeftShoulder"], "deadzone": 0.2, "trigger": "hold:0.2", "chord": "", "mappable": {}, "consumer": "input_context.gd chord source", "note": ""},
	{"id": "pause", "ia": "Pause", "ctx": "legacy", "kb": ["Escape", "Pause"], "pad": ["Gamepad_Special_Right"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "hud.gd:2340", "note": "legacy ActionMapping Pause; DefaultInput.ini keeps Pause/BackCancel/ToggleDevToolUI after the -/+ migration"},
	{"id": "change_input_mapping", "ia": "IA_ChangeInputMapping", "ctx": "character", "kb": ["Backslash"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "input_context.gd device toggle", "note": "toggles the displayed input device"},
	{"id": "display_input_debug", "ia": "IA_DisplayInputDebug", "ctx": "character", "kb": ["Enter"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; recorded"},
	{"id": "display_input_cycle", "ia": "IA_DisplayInputCycle", "ctx": "character", "kb": ["Enter"], "pad": [], "deadzone": 0.2, "trigger": "tap", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; recorded"},
	{"id": "", "ia": "IA_Ability_Action_Primary_Tap", "ctx": "character", "kb": ["LeftMouseButton"], "pad": ["Gamepad_RightTrigger"], "deadzone": 0.2, "trigger": "tap", "chord": "", "mappable": {}, "consumer": "", "note": "covered by primary_action"},
	{"id": "", "ia": "IA_Ability_Action_Primary_Hold", "ctx": "character", "kb": ["LeftMouseButton"], "pad": ["Gamepad_RightTrigger"], "deadzone": 0.2, "trigger": "hold:0.2", "chord": "", "mappable": {}, "consumer": "", "note": "covered by primary_action"},
	{"id": "", "ia": "IA_Ability_RunToggle", "ctx": "character", "kb": [], "pad": ["Gamepad_LeftThumbstick"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "merged into sprint"},
	{"id": "", "ia": "IA_Ability06", "ctx": "character", "kb": ["Four"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "Four double-bound; the port's tool_4 carries the Vistara action"},
	{"id": "", "ia": "IA_Ability07", "ctx": "character", "kb": ["Five"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no consumer and no port slot"},
	{"id": "", "ia": "IA_Ability08", "ctx": "character", "kb": ["Six"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no consumer and no port slot"},
	{"id": "", "ia": "IA_Ability09", "ctx": "character", "kb": ["Seven"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no consumer and no port slot"},
	{"id": "", "ia": "IA_Ability10", "ctx": "character", "kb": ["Eight"], "pad": [], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no consumer and no port slot"},
	{"id": "", "ia": "IA_Radial_Directional", "ctx": "radial", "kb": [], "pad": ["Gamepad_RightX-", "Gamepad_RightX+", "Gamepad_RightY-", "Gamepad_RightY+"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "radial context has no port consumer (the HUD ping radial uses 1-4)"},
	{"id": "", "ia": "IA_Radial_Cancel", "ctx": "radial", "kb": ["RightMouseButton"], "pad": ["Gamepad_FaceButton_Right"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer"},
	{"id": "", "ia": "IA_Radial_NextPage", "ctx": "radial", "kb": ["E"], "pad": ["Gamepad_DPad_Right"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer"},
	{"id": "", "ia": "IA_Radial_PreviousPage", "ctx": "radial", "kb": ["Q"], "pad": ["Gamepad_DPad_Left"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer"},
	{"id": "", "ia": "IA_Radial_Select_Primary", "ctx": "radial", "kb": ["G"], "pad": ["Gamepad_DPad_Up"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer; G was previously mis-bound to the port's ability verb"},
	{"id": "", "ia": "IA_Radial_Select_Secondary", "ctx": "radial", "kb": ["T"], "pad": ["Gamepad_DPad_Down"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer"},
	{"id": "", "ia": "IA_MapSwitch_Prev", "ctx": "map", "kb": ["R"], "pad": ["Gamepad_DPad_Up"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer (the port map has one page)"},
	{"id": "", "ia": "IA_MapSwitch_Next", "ctx": "map", "kb": ["F"], "pad": ["Gamepad_DPad_Down"], "deadzone": 0.2, "trigger": "", "chord": "", "mappable": {}, "consumer": "", "note": "no port consumer (the port map has one page)"},
]


## Deep copy so callers cannot mutate the const rows.
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in AUTHORED_ROWS:
		out.append(r.duplicate(true))
	return out


static func row_for(id: String) -> Dictionary:
	for r: Dictionary in AUTHORED_ROWS:
		if str(r.get("id", "")) == id:
			return r.duplicate(true)
	return {}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in AUTHORED_ROWS:
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
	for r: Dictionary in AUTHORED_ROWS:
		if str(r.get("ia", "")) == ia:
			var id: String = str(r.get("id", ""))
			if id != "":
				return id
	return ""


static func is_pad_key(key_name: String) -> bool:
	return key_name.begins_with("Gamepad_")


# ---------------------------------------------------------------------------
# Table loading (T01 contract + fallback)
# ---------------------------------------------------------------------------

## Returns {source, rows, warnings}. `source` is "generated", "authored", or "".
static func load_table() -> Dictionary:
	var warnings: Array[String] = []
	if FileAccess.file_exists(GENERATED_PATH):
		var f: FileAccess = FileAccess.open(GENERATED_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				var checked: Dictionary = _validate_generated(parsed as Dictionary)
				warnings.append_array(checked.get("warnings", []) as Array[String])
				var gen_rows: Array = checked.get("rows", [])
				if not gen_rows.is_empty():
					var converted: Array[Dictionary] = []
					for r: Variant in gen_rows:
						converted.append((r as Dictionary).duplicate(true))
					return {"source": "generated", "rows": converted, "warnings": warnings}
			warnings.append("generated input table is not schema-valid; using the authored fallback")
	if not AUTHORED_ROWS.is_empty():
		return {"source": "authored", "rows": rows(), "warnings": warnings}
	return {"source": "", "rows": [], "warnings": warnings}


## Contract check for T01's producer. Accepts `actions[]` or `rows[]` and a
## `schema` string; returns {rows, warnings}. Unknown extra fields are preserved.
static func _validate_generated(doc: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	var schema: String = str(doc.get("schema", ""))
	if schema != "" and schema != SCHEMA:
		warnings.append("generated input schema %s != %s" % [schema, SCHEMA])
	var bag: Variant = doc.get("actions", doc.get("rows", null))
	if not (bag is Array):
		warnings.append("generated input table has no actions[]/rows[] array")
		return {"rows": [], "warnings": warnings}
	var ok: Array = []
	for v: Variant in (bag as Array):
		if not (v is Dictionary):
			warnings.append("generated input row is not a dictionary")
			continue
		var r: Dictionary = v as Dictionary
		if str(r.get("ia", "")) == "":
			warnings.append("generated input row without an ia name")
			continue
		if not (r.get("kb", []) is Array) or not (r.get("pad", []) is Array):
			warnings.append("generated input row %s has non-array kb/pad" % str(r.get("ia", "?")))
			continue
		if not r.has("deadzone"):
			r["deadzone"] = 0.2
		ok.append(r)
	if ok.is_empty():
		warnings.append("generated input table had no usable rows")
	return {"rows": ok, "warnings": warnings}


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
	report["source"] = "generated" if not table_rows.is_empty() else "authored"
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
