class_name InputGlyphs
extends RefCounted
## Single formatter for every printed key/prompt glyph (RE-H-06/07/14).
##
## The shipped build does not hardcode prompt text: `UOSEInputFunctionLibrary::
## GetKeyTextForInputAction()` resolves the *currently bound* key, `DT_InputKeysToGlyphs`
## (132 rows, normalised at `res://data/generated/tables/Art/UI/Icons/`) supplies the
## sprite, and `BPUI_InputActionIcon::_OnInputHardwareTypeChanged` re-renders the icon
## when the device changes. This class is the port equivalent: callers name an
## **action**, never a key, so a rebind or a device swap updates every label.
##
## Contract for T05-UI: replace hardcoded `[X]` labels with
##   InputGlyphs.bracket("interact")            -> "[F]" / "[X]"
##   InputGlyphs.prompt("interact", "OPEN")     -> "[F] OPEN"
##   InputGlyphs.format_legacy(raw, "interact") -> re-keys an interactable sentence
## and add `InputGlyphs.note_event(event)` at the top of the HUD `_input`.
## See the T06 report for the full call-site list.

const GLYPHS_PATH: String = "res://data/generated/tables/Art/UI/Icons/DT_InputKeysToGlyphs.json"
const STRINGS_PATH: String = "res://data/generated/tables/StringTables/ST_Settings_Input.json"

const DEVICE_KB: String = "kb"
const DEVICE_PAD: String = "pad"
## Touch is a port-only third surface: the shipped build has no mobile UI
## (DefaultInput.ini only inherits Engine's DefaultVirtualJoysticks, and the only
## pak is pakchunk0-Windows), so there is no authored touch glyph to print.
## Selecting it makes bracket()/text() return "" so a caller hides the keycap
## exactly as the shipped desktop HUD does on mobile.
const DEVICE_TOUCH: String = "touch"

## Authored device labels (EOSEInputHardwareType) plus the port's touch surface.
const DEVICE_LABELS: Dictionary = {"kb": "Keyboard / Mouse", "pad": "Gamepad", "touch": "Touch"}

## Tokens that are prose, not keys: never rewritten by format_legend().
const NON_KEY_TOKENS: Array[String] = [
	"HOLD", "PRESS", "AIM", "STICK", "DRAG", "USE", "HIT", "WIRE", "EYE",
	"II", "BACK", "SELECT", "CONTINUE",
]

## UE key name -> the short text the shipped HUD prints.
const KEY_LABELS: Dictionary = {
	"LeftMouseButton": "LMB", "RightMouseButton": "RMB", "MiddleMouseButton": "MMB",
	"ThumbMouseButton": "MB4", "ThumbMouseButton2": "MB5",
	"MouseWheelAxis+": "WHEEL UP", "MouseWheelAxis-": "WHEEL DOWN",
	"SpaceBar": "SPACE", "Tab": "TAB", "CapsLock": "CAPS", "Enter": "ENTER",
	"Escape": "ESC", "Backslash": "\\", "Pause": "PAUSE",
	"LeftControl": "CTRL", "RightControl": "CTRL",
	"LeftShift": "SHIFT", "RightShift": "SHIFT",
	"LeftAlt": "ALT", "RightAlt": "ALT",
	"One": "1", "Two": "2", "Three": "3", "Four": "4", "Five": "5",
	"Six": "6", "Seven": "7", "Eight": "8", "Nine": "9", "Zero": "0",
	"Gamepad_FaceButton_Bottom": "A", "Gamepad_FaceButton_Right": "B",
	"Gamepad_FaceButton_Left": "X", "Gamepad_FaceButton_Top": "Y",
	"Gamepad_LeftTrigger": "LT", "Gamepad_RightTrigger": "RT",
	"Gamepad_LeftShoulder": "LB", "Gamepad_RightShoulder": "RB",
	"Gamepad_Special_Left": "VIEW", "Gamepad_Special_Right": "MENU",
	"Gamepad_LeftThumbstick": "L3", "Gamepad_RightThumbstick": "R3",
	"Gamepad_DPad_Up": "DPAD UP", "Gamepad_DPad_Down": "DPAD DOWN",
	"Gamepad_DPad_Left": "DPAD LEFT", "Gamepad_DPad_Right": "DPAD RIGHT",
	"Gamepad_LeftX-": "LS LEFT", "Gamepad_LeftX+": "LS RIGHT",
	"Gamepad_LeftY-": "LS UP", "Gamepad_LeftY+": "LS DOWN",
	"Gamepad_RightX-": "RIGHT STICK", "Gamepad_RightX+": "RIGHT STICK",
	"Gamepad_RightY-": "RIGHT STICK", "Gamepad_RightY+": "RIGHT STICK",
	"Mouse2D": "MOUSE",
}

static var _device: String = DEVICE_KB
static var _icons: Dictionary = {}
static var _strings: Dictionary = {}

static func _ensure_tables() -> void:
	if _icons.is_empty() and FileAccess.file_exists(GLYPHS_PATH):
		var f: FileAccess = FileAccess.open(GLYPHS_PATH, FileAccess.READ)
		if f != null:
			var doc: Variant = JSON.parse_string(f.get_as_text())
			if doc is Dictionary and (doc as Dictionary).get("rows") is Dictionary:
				for row_v: Variant in ((doc as Dictionary)["rows"] as Dictionary).values():
					if not (row_v is Dictionary):
						continue
					var key_name: String = ""
					var icon: String = ""
					for cell_v: Variant in (row_v as Dictionary).values():
						if not (cell_v is Dictionary):
							continue
						var cell: Dictionary = cell_v as Dictionary
						if cell.has("KeyName"):
							key_name = str(cell["KeyName"])
						elif cell.has("ObjectName"):
							icon = _sprite_name(str(cell["ObjectName"]))
					if key_name != "" and icon != "" and not _icons.has(key_name):
						_icons[key_name] = icon
	if _strings.is_empty() and FileAccess.file_exists(STRINGS_PATH):
		var fs: FileAccess = FileAccess.open(STRINGS_PATH, FileAccess.READ)
		if fs != null:
			var sdoc: Variant = JSON.parse_string(fs.get_as_text())
			if sdoc is Dictionary and (sdoc as Dictionary).get("entries") is Dictionary:
				_strings = ((sdoc as Dictionary)["entries"] as Dictionary).duplicate()


static func _sprite_name(object_name: String) -> String:
	# "PaperSprite'S_Controller_Xbox_X'" -> "S_Controller_Xbox_X"
	var a: int = object_name.find("'")
	var b: int = object_name.rfind("'")
	if a >= 0 and b > a:
		return object_name.substr(a + 1, b - a - 1)
	return object_name


# ---------------------------------------------------------------------------
# Device state
# ---------------------------------------------------------------------------

static func current_device() -> String:
	return _device


static func set_device(device: String) -> void:
	if device == DEVICE_PAD or device == DEVICE_TOUCH:
		_device = device
	else:
		_device = DEVICE_KB


## Called by InputContext for every input event: the last device to produce input
## is the device whose glyphs the UI should show (authored `IA_ChangeInputMapping`
## is the manual override).
static func note_event(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_device = DEVICE_KB
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_device = DEVICE_PAD


static func toggle_device() -> String:
	_device = DEVICE_PAD if _device == DEVICE_KB else DEVICE_KB
	return _device


# ---------------------------------------------------------------------------
# Text
# ---------------------------------------------------------------------------

static func key_label(key_name: String) -> String:
	if KEY_LABELS.has(key_name):
		return str(KEY_LABELS[key_name])
	if key_name.length() == 1:
		return key_name.to_upper()
	return key_name.to_upper()


static func device_of_key(key_name: String) -> String:
	return DEVICE_PAD if key_name.begins_with("Gamepad_") else DEVICE_KB


## First bound key name for an action on a device ("" when unbound).
static func key_name_for_action(id: String, device: String = "") -> String:
	if not InputMap.has_action(id):
		return ""
	var want: String = device if device != "" else _device
	for ev: InputEvent in InputMap.action_get_events(id):
		var name: String = InputActions.key_name_for_event(ev)
		if name == "":
			continue
		if device_of_key(name) == want:
			return name
	return ""


static func chord_of(id: String) -> String:
	var row: Dictionary = InputActions.row_for(id)
	return str(row.get("chord", ""))


## "F" / "X" / "LB + LS LEFT"; "" when the action resolves to nothing on `device`.
static func text(id: String, device: String = "") -> String:
	var want: String = device if device != "" else _device
	if want == DEVICE_TOUCH:
		return "" # no authored touch glyph; callers hide the keycap
	var key_name: String = key_name_for_action(id, device)
	if key_name == "":
		return ""
	var label: String = key_label(key_name)
	var chord: String = chord_of(id)
	if chord == "":
		return label
	var chord_id: String = InputActions.port_id_for_ia(chord)
	if chord_id == "":
		return label
	var chord_key: String = key_name_for_action(chord_id, device)
	if chord_key == "":
		return label
	return "%s + %s" % [key_label(chord_key), label]


## "[F]" / "[X]" / "[LB + LS LEFT]"; "" when unbound (callers keep their fallback).
static func bracket(id: String, device: String = "") -> String:
	var t: String = text(id, device)
	return "[" + t + "]" if t != "" else ""


## The one call a prompt needs: prompt("interact", "OPEN") -> "[F] OPEN".
static func prompt(id: String, verb: String, device: String = "") -> String:
	var k: String = bracket(id, device)
	if k == "":
		return verb.strip_edges()
	return (k + " " + verb.strip_edges()).strip_edges()


## Rewrites only the leading "[KEY]" of a legacy sentence, e.g. the interactable
## strings "[E] Pick Lock (Lv 3)" / "[F] OPEN". Text after the token is untouched,
## so the KF24 phrasings and every test-facing `get_interact_prompt()` stay valid.
## `id` empty or unbound leaves the sentence unchanged.
static func format_legacy(raw: String, id: String, device: String = "") -> String:
	var txt: String = raw.strip_edges()
	if txt == "" or id == "":
		return raw
	if not txt.begins_with("["):
		return raw
	var end: int = txt.find("]")
	if end <= 1:
		return raw
	var token: String = txt.substr(1, end - 1).strip_edges()
	if NON_KEY_TOKENS.has(token.to_upper()):
		return raw
	var k: String = bracket(id, device)
	if k == "":
		return raw
	return k + " " + txt.substr(end + 1).strip_edges()


## Rewrites every "[TOKEN]" whose token is a key in `token_actions`
## ({ "LMB": "primary_action", "ESC": "pause", ... }). Used for one-line legends
## such as "[SPACE] / [LMB] STRIKE PIN · [ESC] CANCEL".
static func format_legend(raw: String, token_actions: Dictionary, device: String = "") -> String:
	var txt: String = raw
	var out: String = ""
	var idx: int = 0
	while idx < txt.length():
		var open: int = txt.find("[", idx)
		if open < 0:
			out += txt.substr(idx)
			break
		var close: int = txt.find("]", open + 1)
		if close < 0:
			out += txt.substr(idx)
			break
		out += txt.substr(idx, open - idx)
		var token: String = txt.substr(open + 1, close - open - 1).strip_edges()
		var id: String = str(token_actions.get(token.to_upper(), ""))
		if id != "" and not NON_KEY_TOKENS.has(token.to_upper()):
			var k: String = bracket(id, device)
			out += k if k != "" else "[" + token + "]"
		else:
			out += "[" + token + "]"
		idx = close + 1
	return out


## Authored sprite name for the bound key ("S_Controller_Xbox_X"), or "".
static func icon_name(id: String, device: String = "") -> String:
	_ensure_tables()
	var key_name: String = key_name_for_action(id, device)
	if key_name == "":
		return ""
	return str(_icons.get(key_name, ""))


## Authored display label ("Interact", "Slot 4", ...) from ST_Settings_Input.
static func action_label(id: String) -> String:
	_ensure_tables()
	var row: Dictionary = InputActions.row_for(id)
	var mappable: Dictionary = row.get("mappable", {}) as Dictionary
	var key: String = str(mappable.get("label", ""))
	if key == "":
		return id.capitalize()
	return str(_strings.get(key, id.capitalize()))


## Authored category ("Movement", "Interaction", "Tools", "Primary Fire").
static func action_category(id: String) -> String:
	var row: Dictionary = InputActions.row_for(id)
	var mappable: Dictionary = row.get("mappable", {}) as Dictionary
	return str(mappable.get("category", ""))


## Every rebindable action, grouped by authored category in the authored order.
static func rebindable_by_category() -> Dictionary:
	var out: Dictionary = {}
	for r: Dictionary in InputActions.rows():
		var id: String = str(r.get("id", ""))
		if id == "":
			continue
		var mappable: Dictionary = r.get("mappable", {}) as Dictionary
		if mappable.is_empty():
			continue
		var cat: String = str(mappable.get("category", ""))
		if not out.has(cat):
			out[cat] = [] as Array[String]
		(out[cat] as Array[String]).append(id)
	return out
