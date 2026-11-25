class_name TutorialText
extends RefCounted
## Authored FTUE rich-text renderer (W9-P3-C1/C3).
##
## The shipped tutorial copy is not plain text: `ST_Tutorial` /
## `ST_Tutorial_Infographics` / `ST_Tutorial_ThievesDen` carry UE rich-text tags
## and inline input icons:
##   * `<img id="Jump"/>` -> the *currently bound* glyph for that action,
##     resolved through `DT_RichTextInputs` (id -> `IA_*` -> port action) and
##     `InputGlyphs` (rebind/device aware),
##   * `<Highlight>`, `<Danger>`, `<Special>`, `<Noise>` -> the authored colours
##     in `DT_RichTextStyleSheet_FTUE` (#00D8CC / #BD1F1F / #D0AA4E / #6195FF),
##   * `<Num>` (lobby sheet) -> the same colour scheme's Special tone.
##
## Citations: `extracted/json/UI/HUD/FTUE/DT_RichTextStyleSheet_FTUE.json`
## (rows Default/Highlight/Special/Danger/Noise), `DT_RichTextInputs.json`
## (15 ids), `game/data/generated/tables/UI/HUD/FTUE/*.json` (the generated
## copies this reader consumes). No tutorial prose is invented here: an unknown
## tag is rendered as plain text, and an unbound input resolves to no keycap
## exactly as the shipped touch/mobile HUD hides it.

const STYLE_PATH: String = "res://data/generated/tables/UI/HUD/FTUE/DT_RichTextStyleSheet_FTUE.json"
const INPUTS_PATH: String = "res://data/generated/tables/UI/HUD/FTUE/DT_RichTextInputs.json"

## Fallback colours copied from DT_RichTextStyleSheet_FTUE.json, used only when
## the generated table is unreadable (each use is counted in style_fallbacks).
const STYLE_COLORS: Dictionary = {
	"Default": "#ffffff",
	"Highlight": "#00d8cc",
	"Special": "#d0aa4e",
	"Danger": "#bd1f1f",
	"Noise": "#6195ff",
}

static var _input_rows: Dictionary = {}
static var _style_colors: Dictionary = {}
static var _loaded: bool = false
static var _style_fallbacks: int = 0


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_inputs()
	_load_styles()


static func _load_inputs() -> void:
	_input_rows.clear()
	if not FileAccess.file_exists(INPUTS_PATH):
		return
	var f: FileAccess = FileAccess.open(INPUTS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var rows_v: Variant = (parsed as Dictionary).get("rows", {})
	if not (rows_v is Dictionary):
		return
	for id_v: Variant in (rows_v as Dictionary).keys():
		var row_v: Variant = (rows_v as Dictionary)[id_v]
		if not (row_v is Dictionary):
			continue
		var ia_v: Variant = (row_v as Dictionary).get("InputAction", {})
		if not (ia_v is Dictionary):
			continue
		var ia_name: String = _object_name(str((ia_v as Dictionary).get("ObjectName", "")))
		if ia_name != "":
			_input_rows[str(id_v)] = ia_name


static func _load_styles() -> void:
	_style_colors.clear()
	if FileAccess.file_exists(STYLE_PATH):
		var f: FileAccess = FileAccess.open(STYLE_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				var rows_v: Variant = (parsed as Dictionary).get("rows", {})
				if rows_v is Dictionary:
					for name_v: Variant in (rows_v as Dictionary).keys():
						var row: Dictionary = ((rows_v as Dictionary)[name_v] as Dictionary) if (rows_v as Dictionary)[name_v] is Dictionary else {}
						var ts: Dictionary = row.get("TextStyle", {}) as Dictionary
						var col: Dictionary = ts.get("ColorAndOpacity", {}) as Dictionary
						var spec: Dictionary = col.get("SpecifiedColor", {}) as Dictionary
						var hex: String = str(spec.get("Hex", ""))
						if hex != "":
							_style_colors[str(name_v)] = "#" + hex.to_lower()
	if _style_colors.is_empty():
		for k: Variant in STYLE_COLORS.keys():
			_style_colors[k] = STYLE_COLORS[k]
			_style_fallbacks += 1


static func _object_name(raw: String) -> String:
	# "InputAction'IA_Movement_Jump'" -> "IA_Movement_Jump"
	var a: int = raw.find("'")
	var b: int = raw.rfind("'")
	if a >= 0 and b > a:
		return raw.substr(a + 1, b - a - 1)
	return raw


## Port action id for a DT_RichTextInputs id ("Jump" -> "jump"), or "".
static func action_for_input_id(id: String) -> String:
	ensure_loaded()
	var ia_name: String = str(_input_rows.get(id, ""))
	if ia_name == "":
		return ""
	return InputActions.port_id_for_ia(ia_name)


## Authored colour for a style-sheet row name ("Danger" -> "#bd1f1f").
static func color_for(name: String) -> String:
	ensure_loaded()
	return str(_style_colors.get(name, _style_colors.get("Default", "#ffffff")))


## Render authored FTUE copy to Godot BBCode. `device` empty follows the active
## device in InputGlyphs.
static func render(body: String, device: String = "") -> String:
	if body == "":
		return ""
	ensure_loaded()
	var out: String = body.replace("[", "[lb]")
	out = _replace_input_icons(out, device)
	out = _replace_style_tags(out)
	return out


static func _replace_input_icons(text: String, device: String) -> String:
	var re: RegEx = RegEx.new()
	# Both the self-closing authored form and a bare form.
	if re.compile("<img\\s+id=\"([^\"]+)\"\\s*/?>") != OK:
		return text
	var out: String = text
	# Walk matches from the end so earlier offsets stay valid.
	var matches: Array[RegExMatch] = re.search_all(out)
	for i: int in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var id: String = m.get_string(1)
		var action: String = action_for_input_id(id)
		var key: String = InputGlyphs.bracket(action, device) if action != "" else ""
		out = out.substr(0, m.get_start()) + key + out.substr(m.get_end())
	return out


static func _replace_style_tags(text: String) -> String:
	var re: RegEx = RegEx.new()
	if re.compile("<([A-Za-z][A-Za-z0-9_]*)>(.+?)</>") != OK:
		return text
	var out: String = text
	var matches: Array[RegExMatch] = re.search_all(out)
	for i: int in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var tag: String = m.get_string(1)
		var inner: String = m.get_string(2)
		var color: String = color_for(tag)
		var bb: String = "[color=%s]%s[/color]" % [color, inner]
		out = out.substr(0, m.get_start()) + bb + out.substr(m.get_end())
	return out


## Plain-text form for tests/logs: tags and icons removed, authored prose kept.
static func strip_tags(body: String) -> String:
	var out: String = body
	var re_img: RegEx = RegEx.new()
	if re_img.compile("<img\\s+id=\"[^\"]+\"\\s*/?>") == OK:
		out = re_img.sub(out, "", true)
	var re_tag: RegEx = RegEx.new()
	if re_tag.compile("<[^>]+>") == OK:
		out = re_tag.sub(out, "", true)
	return out.strip_edges()


## Diagnostic: how many style rows came from the fallback table (must be 0 in a
## normal install; a test pins it).
static func style_fallbacks() -> int:
	return _style_fallbacks


static func input_id_count() -> int:
	ensure_loaded()
	return _input_rows.size()
