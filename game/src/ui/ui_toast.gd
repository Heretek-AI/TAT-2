class_name UIToast
extends Control
## Authored HUD toast widget (W9-P3-C4).
##
## The shipped loot pickup is a toast, not a world-space label:
## `extracted/json/UI/HUD/BPUI_ToastWidget.json` is a `Border Border_255` whose
## Background is the UI material `M_UI_Smoke` (MaterialDomain MD_UI,
## BlendMode BLEND_TranslucentGreyTransmittance, global params CornerRadius /
## Power — it is a rounded translucent smoke panel, no texture ships), a
## `CommonTextBlock ToastText`, an `Image MessageIcon` and a `SizeBox` icon well,
## with the animations `Show` and `EyeCatchingShow`.
## `BPUI_ToastContainerWidget` stacks them in a `VerticalBox`.
## The loot row itself is `DT_ToastConfig.NewRow_12` (icon
## `S_LootItem_Artifact_Chalice`, sound `Play_ToastSystem_LootDeposited_Message_FlyIn`)
## with the authored text `ST_Toasts.MajorLootTaken` =
## "{PlayerName} took the {MajorLootName}!" (C5-03, RE-L-09).
##
## This is the port reconstruction: a rounded smoke-style panel (StyleBoxFlat;
## the authored material is not convertible, so the label says so), the authored
## icon when a decoded sprite exists, the authored template with the live
## player/loot names, and the two authored animations as Tweens. The local
## player's name is `GameState.player_display_name()` ("The Spider" /
## "The Chameleon", localised).

const ST_TOASTS: String = "ST_Toasts"
## Authored per-toast sound (DT_ToastConfig NewRow_12, Toast.Type.Gameplay.Loot.Taken).
## NewRow_12's cue is Play_ToastSystem_LootDeposited_Message_FlyIn (Generic_Message_FlyIn
## belongs to NewRow_13 Loot.Dropped). The port's AudioManager has no arbitrary
## Wwise-event API, so playback is the labelled `play_ui("toast")` channel.
const LOOT_SOUND: String = "Play_ToastSystem_LootDeposited_Message_FlyIn"
## Authored major-loot indicator glyph (fallback when the exact PaperSprite
## S_LootItem_Artifact_Chalice has no decoded PNG — counted, never silent).
const MAJOR_LOOT_ICON: String = "res://assets/ue/Raw/Art/UI/Icons/T_Glyph_MajorLoot.png"
const TOAST_WIDTH: float = 560.0
const TOAST_MARGIN_TOP: float = 118.0
const HOLD_SECONDS: float = 3.6
const SHOW_SECONDS: float = 0.22
const MAX_VISIBLE: int = 4

var _stack: VBoxContainer
var _live: Array[Control] = []
var _shown: int = 0
var _icon_fallback: int = 0


func _ready() -> void:
	name = "ToastStack"
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -TOAST_WIDTH * 0.5
	offset_right = TOAST_WIDTH * 0.5
	offset_top = TOAST_MARGIN_TOP
	offset_bottom = TOAST_MARGIN_TOP + 400.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack = VBoxContainer.new()
	_stack.name = "ToastContainer"
	_stack.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_stack.add_theme_constant_override("separation", 8)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)


## The authored local pickup line: `Toasts.MajorLootTaken`.
static func major_loot_text(player_name: String, loot_name: String) -> String:
	return UIStrings.st_template(ST_TOASTS, "MajorLootTaken",
		"{PlayerName} took the {MajorLootName}!",
		{"PlayerName": player_name, "MajorLootName": loot_name})


## The authored stash line: `Toasts.DepositedMajorLoot_Local`.
static func stashed_text(loot_name: String) -> String:
	return UIStrings.st_template(ST_TOASTS, "DepositedMajorLoot_Local",
		"You stashed the {MajorLootName}!", {"MajorLootName": loot_name})


## Show the authored major-loot toast for the local player. `icon_res` is the
## authored per-item icon when a decoded PNG exists; empty uses the authored
## major-loot glyph.
func show_major_loot(loot_name: String, icon_res: String = "") -> Dictionary:
	var player: String = "The Spider"
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("player_display_name"):
		player = str(gs.call("player_display_name"))
	return show_text(major_loot_text(player, loot_name), icon_res)


## Generic authored toast: text already localised by the caller.
func show_text(text: String, icon_res: String = "", eye_catching: bool = false) -> Dictionary:
	if _stack == null:
		return {"shown": false}
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Toast_%d" % (_shown + 1)
	panel.add_theme_stylebox_override("panel", _smoke_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var icon_path: String = icon_res if icon_res != "" else MAJOR_LOOT_ICON
	var icon_tex: Texture2D = null
	if ResourceLoader.exists(icon_path):
		icon_tex = ResourceLoader.load(icon_path) as Texture2D
	var icon_source: String = "none"
	if icon_path == MAJOR_LOOT_ICON:
		# The row's authored PaperSprite (S_LootItem_Artifact_Chalice) is not
		# decoded, so the generic authored major-loot glyph is a substitution;
		# count it instead of claiming the row icon.
		icon_source = "major_loot_glyph"
		if icon_tex != null:
			_icon_fallback += 1
	elif icon_tex != null:
		icon_source = "authored"
	if icon_tex != null:
		var well: PanelContainer = PanelContainer.new()
		var well_style: StyleBoxFlat = StyleBoxFlat.new()
		well_style.bg_color = Color(0.03, 0.06, 0.08, 0.55)
		well_style.set_corner_radius_all(3)
		well_style.set_content_margin_all(4)
		well.add_theme_stylebox_override("panel", well_style)
		var icon: TextureRect = TextureRect.new()
		icon.texture = icon_tex
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		well.add_child(icon)
		row.add_child(well)
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", ArtNouveauTheme.TEAL_TEXT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	_stack.add_child(panel)
	_live.append(panel)
	_shown += 1
	_trim()
	_play_show(panel, eye_catching)
	# Autoload identifiers are not resolvable when this script is `preload`ed by
	# a `--script` test (autoloads register after parse), so look the node up.
	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_ui"):
		# Authored cue is a Wwise event; play_ui is the port's registered
		# channel (audio_manager maps unknown cues to a no-op).
		am.call("play_ui", "toast")
	return {
		"shown": true,
		"text": text,
		"icon": icon_source,
		"eye_catching": eye_catching,
		"authored_text": UIStrings.raw(ST_TOASTS, "MajorLootTaken", ""),
	}


## Authored `Show` (fade + slide from the right) and `EyeCatchingShow` (a single
## scale pulse) as Tweens. The authored animations are UMG widget animations;
## their curves are not in the dump, so the timing below is the port's labelled
## reconstruction of the two states.
func _play_show(panel: Control, eye_catching: bool) -> void:
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var start_x: float = panel.position.x
	panel.position.x = start_x + 52.0
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, SHOW_SECONDS)
	tw.tween_property(panel, "position:x", start_x, SHOW_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(HOLD_SECONDS)
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(func() -> void: _retire(panel))
	if eye_catching:
		var pulse: Tween = create_tween()
		pulse.tween_property(panel, "scale", Vector2(1.06, 1.06), 0.12)
		pulse.tween_property(panel, "scale", Vector2.ONE, 0.16)


func _retire(panel: Control) -> void:
	if not is_instance_valid(panel):
		return
	_live.erase(panel)
	panel.queue_free()


func _trim() -> void:
	while _live.size() > MAX_VISIBLE:
		var old: Control = _live[0]
		_live.remove_at(0)
		if is_instance_valid(old):
			old.queue_free()


## Port reconstruction of `M_UI_Smoke`: a rounded translucent near-black panel
## (MD_UI / BLEND_TranslucentGreyTransmittance, CornerRadius + Power params).
func _smoke_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.020, 0.035, 0.045, 0.88)
	s.border_color = Color(0.32, 0.62, 0.64, 0.55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	return s


func visible_toasts() -> Array[Control]:
	var out: Array[Control] = []
	for c: Control in _live:
		if is_instance_valid(c):
			out.append(c)
	return out


func toast_texts() -> Array[String]:
	var out: Array[String] = []
	for c: Control in visible_toasts():
		for lbl: Node in c.find_children("*", "Label", true, false):
			out.append((lbl as Label).text)
	return out


## Diagnostics: how many toasts were shown and how many icons used the authored
## major-loot glyph instead of the row's PaperSprite.
func stats() -> Dictionary:
	return {"shown": _shown, "live": _live.size(), "icon_fallback": _icon_fallback}
