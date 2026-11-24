extends CanvasLayer
## One-page modal line for the Spider personal chain (W1S).
##
## The shipped 03/04 beats have a single spoken line and a separate follow-up
## line that is shown on the next interaction, never as a second page here.
## There is no VO, portrait, nameplate or invented speaker: the panel only
## shows the authored line and a CONTINUE button.
##
## Input arbitration:
##   * the dialogue is a CanvasLayer child of the HUD and handles its own
##     input so the player modal keys do not leak into the world;
##   * Escape and the interact action close it;
##   * input in the frame that opened it is ignored, so the press that talked
##     to the NPC cannot immediately dismiss the panel ("no immediate
##     self-close");
##   * it never pauses the tree (the mission keeps running behind the panel).
##
## The host registers this node through set_npc_dialogue() so HUD input and
## the interaction prompt can be suppressed while it is open.

const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")

signal closed

const BODY_FONT_SIZE: int = 32
const BUTTON_FONT_SIZE: int = 30
const BUTTON_TEXT: String = "CONTINUE"
const ALATA_PATH: String = "res://assets/ue/fonts/Alata-Regular.ttf"
const PANEL_MIN_WIDTH: float = 760.0

var _open: bool = false
## Frame that opened the panel; same-frame input is the opening press.
var _opened_frame: int = -1
var _host: Node = null
var _prev_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _body_label: Label = null
var _button: Button = null
var _panel: PanelContainer = null
var _font: Font = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# HUD is a CanvasLayer at layer 1; draw the modal above every HUD element.
	layer = 32
	visible = false
	_font = _load_alata()
	_build_ui()


func _load_alata() -> Font:
	if ResourceLoader.exists(ALATA_PATH):
		var loaded: Resource = load(ALATA_PATH)
		if loaded is Font:
			return loaded as Font
	return ThemeScript.font_sans()


func _build_ui() -> void:
	var root: Control = Control.new()
	root.name = "NpcDialogueRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var dim: ColorRect = ColorRect.new()
	dim.name = "NpcDialogueDim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Lighter than the pause/letter dims: the conversation is not a pause.
	dim.color = Color(0.01, 0.015, 0.032, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "NpcDialoguePanel"
	_panel.custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0)
	_panel.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(2, 8, ThemeScript.TEAL_PANEL_BG, 26))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)
	ThemeScript.add_teal_filigree(_panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.name = "NpcDialogueBody"
	vb.add_theme_constant_override("separation", 18)
	_panel.add_child(vb)

	_body_label = Label.new()
	_body_label.name = "NpcDialogueLine"
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(PANEL_MIN_WIDTH - 64.0, 0)
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_body_label.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if _font != null:
		_body_label.add_theme_font_override("font", _font)
	vb.add_child(_body_label)

	var btn_wrap: CenterContainer = CenterContainer.new()
	btn_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(btn_wrap)

	_button = Button.new()
	_button.name = "NpcDialogueContinueBtn"
	_button.text = BUTTON_TEXT
	_button.custom_minimum_size = Vector2(240, 52)
	ThemeScript.style_teal_button(_button, true)
	# style_teal_button forces its 15 px default; the authored conversation
	# button reads Alata 30 (body 32) per the W1S brief.
	_button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	if _font != null:
		_button.add_theme_font_override("font", _font)
	_button.pressed.connect(close)
	btn_wrap.add_child(_button)


## Open with one authored line. `host` is the HUD (or a mock implementing
## set_npc_dialogue) and is notified so other modals and the prompt yield.
func open(host: Node, line: String) -> void:
	if _open:
		if _body_label != null:
			_body_label.text = line.strip_edges()
		return
	_host = host
	_open = true
	_opened_frame = Engine.get_process_frames()
	if _body_label != null:
		_body_label.text = line.strip_edges()
	visible = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _button != null:
		_button.grab_focus()
	if _host != null and is_instance_valid(_host) and _host.has_method("set_npc_dialogue"):
		_host.call("set_npc_dialogue", self)


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	Input.mouse_mode = _prev_mouse_mode
	if _host != null and is_instance_valid(_host) and _host.has_method("set_npc_dialogue"):
		_host.call("set_npc_dialogue", null)
	closed.emit()


func is_open() -> bool:
	return _open


## Test/QA surface (no node poking in suite 87).
func body_text() -> String:
	return _body_label.text if _body_label != null else ""


func body_font_size() -> int:
	return _body_label.get_theme_font_size("font_size") if _body_label != null else -1


func button_text() -> String:
	return _button.text if _button != null else ""


func button_font_size() -> int:
	return _button.get_theme_font_size("font_size") if _button != null else -1


func _input(event: InputEvent) -> void:
	if not _open:
		return
	# The press that opened the panel is delivered to the tree after the NPC
	# interaction; swallowing it here would close the panel in the same frame.
	if Engine.get_process_frames() <= _opened_frame:
		return
	if not (event is InputEventKey):
		return
	var kev: InputEventKey = event as InputEventKey
	if not kev.pressed or kev.echo:
		return
	var escape: bool = kev.keycode == KEY_ESCAPE or kev.physical_keycode == KEY_ESCAPE
	var interact: bool = InputMap.has_action("interact") and event.is_action_pressed("interact")
	if not escape and not interact:
		return
	close()
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()
