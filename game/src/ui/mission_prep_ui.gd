class_name MissionPrepUI
extends Control
## Mission Preparation screen: full-screen 3D moonlit rooftop stage (SubViewport)
## with a full-body Thief standing on a slanted tiled roof, plus the official
## left-side info stack (Location / Mission / Contract cards) and
## bottom-right [F] READY | [ESC] BACK controls.
## Flow: ContractTableUI confirm dialog -> open_prep(...) -> READY (F/Space)
## emits ready_pressed(map_id, difficulty, mode, contract_order); ESC/BACK
## emits closed().

signal ready_pressed(map_id: String, difficulty: int, mode: String, contract_order: int)
signal closed()

const BODY_CANDIDATES: Array[String] = [
	"res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/SK_ThiefNisha__Body.glb",
	"res://assets/ue/Content/Art/Character/SK_ThiefNisha__Body.glb",
	"res://assets/ue/Content/Art/Character/Thief/SK_ThiefNisha__Body.glb",
	"res://assets/ue/Raw/Art/Character/SK_ThiefNisha__Body.glb",
	"res://assets/ue/Content/Art/Gameplay/Thief/SK_ThiefNisha__Body.glb",
]
const HEAD_CANDIDATES: Array[String] = [
	"res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/SK_ThiefNisha__Head.glb",
	"res://assets/ue/Content/Art/Character/SK_ThiefNisha__Head.glb",
	"res://assets/ue/Content/Art/Character/Thief/SK_ThiefNisha__Head.glb",
	"res://assets/ue/Raw/Art/Character/SK_ThiefNisha__Head.glb",
	"res://assets/ue/Content/Art/Gameplay/Thief/SK_ThiefNisha__Head.glb",
]

const LOC_OLD_MANOR_TITLE: String = "ELWAY MANOR"
const LOC_OLD_MANOR_DESC: String = "This is the estate of the three Elway sisters. Although it has fallen into disrepair, both the house and the family that holds it have a very long history in Kilcairn."
const LOC_GUILDHALL_TITLE: String = "CONSTABLES' GUILDHALL"
const LOC_GUILDHALL_DESC: String = "This is the headquarters and operational base for the Constables, Kilcairn's police force."
const CONTRACT_INACTIVE: String = "Contract Inactive"

const LOCATION_ART_MAP: Dictionary = {
	"old_manor": "res://assets/ue/Raw/Art/UI/Icons/Rewards/Maps/T_Map_OldManor.png",
	"guildhall": "res://assets/ue/Raw/Art/UI/Shell/MapSplash_Guildhall.png",
	"jaspering_hall": "res://assets/ue/Raw/Art/UI/Shell/SplashScreen/T_loadingScreen_1.png",
	"thieves_den": "res://assets/ue/Raw/Art/UI/Shell/SplashScreen/T_loadingScreen_2.png",
}

const LevelLoaderScript: GDScript = preload("res://src/core/level_loader.gd")
const WeatherProfile: GDScript = preload("res://src/core/weather_profile.gd")
const WeatherVisuals: GDScript = preload("res://src/core/weather_visuals.gd")
const GuardAnimLibScript: GDScript = preload("res://src/core/animation_library.gd")
const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")
const ThemeScript: GDScript = preload("res://src/ui/art_nouveau_theme.gd")

## Authored MissionLobby_Geo3 CameraActor_0 FieldOfView 20.0. UE FOV is the
## horizontal field of view, so Godot maps it with keep_aspect KEEP_WIDTH:
## fov reads 20.0 while the rendered vertical stays ~11.33 at 16:9.
## Authored CameraActor_0 in the level's (x, z, y) Godot mapping is
## (12.6065, -0.16698, -1.05384) looking (-0.986184, 0.116419, +0.117848).
## That slot sits tight against the foreground facade, so the prep stage
## mirrors the Z position/look component across the dummy: same X/Y, FOV 20
## and roll -14.78, but it looks back across the open rooftop instead of into
## the wall. This is a deliberate stage reframe, not a coordinate fix.
const LOBBY_CAM_POS: Vector3 = Vector3(12.6065, -0.16698, 1.05384)
const LOBBY_CAM_FWD: Vector3 = Vector3(-0.986184, 0.116419, -0.117848)
const LOBBY_CAM_FOV: float = 20.0
const LOBBY_CAM_ROLL_DEG: float = -14.780165
## Authored BP_MatchLobbyDummyPlayer_C_1 (IsForLocalPlayer: True) rooftop slot.
## The GLB's front is +Z, so the authored 45° faces the camera (world +X) and
## screen-left (+Z): the KF11 three-quarter view.
const LOBBY_THIEF_POS: Vector3 = Vector3(-1.5871, 0.82, -0.7868)
const LOBBY_THIEF_YAW_DEG: float = 45.0
## KF11 stage exposure lift. The weather preset is authored for a
## multiplayer-lobby camera and lands at 0.5 tonemap exposure / 0.3 ambient,
## which renders the rooftop as near-black behind the opaque UI cards.
const STAGE_EXPOSURE: float = 2.6
const STAGE_AMBIENT_ENERGY: float = 1.8
const STAGE_GLOW_INTENSITY: float = 1.0
## The authored weather preset points the moon off-frame. Re-aim the shared
## moon light/disc toward the open upper-centre-right of the prep camera
## (normalised UI coords) so it can key the thief; the near rooftop can still
## occlude the disc itself, but the light direction remains authored-overridable.
const MOON_SCREEN_X: float = 0.63
const MOON_SCREEN_Y: float = 0.10
const STAGE_MOON_ENERGY: float = 0.85
const STAGE_SKY_ENERGY: float = 3.0
const STAGE_MOON_DISC_ENERGY: float = 2.4

## Authored backdrop size for the 3D rooftop stage. The stage container must
## deliver at least this size at runtime: anything smaller (in particular the
## (2,2) engine-minimum floor) plus SSIL enabled reproduces the
## godotengine/godot#86631 RenderingDevice error cascade, so both _build_all
## and _ensure_stage_size treat this as a floor that is never shrunk.
const STAGE_VIEWPORT_SIZE: Vector2i = Vector2i(1280, 720)

## Authored 6-tick lobby countdown (AU4 plays exactly 6 one-second ticks).
const COUNTDOWN_SECONDS: float = 6.0
## Body copy wrap width. The card's content box is ~500 px at 1280x720; this
## inset keeps the final glyph off the right border (the pre-W5 value wrapped
## exactly at the content edge and clipped the last character).
const CARD_BODY_WRAP_WIDTH: float = 468.0

var map_id: String = "old_manor"
var difficulty: int = 1
var mode: String = "Solo"
var contract_order: int = 1
## Free-play ("Contract Inactive") prep: no contract card, the Guildhall
## Cleanout row pre-selected by id, and READY stages the mode for reset_run.
var free_play: bool = false

var _location_body: Label
var _location_title_lbl: Label
var _location_art: TextureRect
var _mission_title_lbl: Label
var _mission_body: Label
var _mission_icon: TextureRect
var _mission_selector: OptionButton
var _mission_rows: Array[Dictionary] = []
var _selected_mission_idx: int = -1
var _contract_title_lbl: Label
var _contract_body: Label
var _controls_lbl: Label
var _mode_sub_lbl: Label
var _diff_sub_lbl: Label
var _countdown_lbl: Label
var _readiness_lbl: Label
var _ready_btn: Button
var _thief_name_lbl: Label
var _thief_body_node: Node = null
var _thief_head_node: Node = null
var _mat_loader: Node = null

## Player-paced READY/UNREADY countdown state. The first press starts a real
## 6 s countdown; a second press cancels it; reaching zero deploys exactly once.
var _countdown_running: bool = false
var _countdown_remaining: float = 0.0
var _countdown_last_int: int = int(COUNTDOWN_SECONDS)
var _deploy_emitted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_all()
	_refresh_all()
	resized.connect(_ensure_stage_size)
	call_deferred("_ensure_stage_size")
	if AudioManager != null and AudioManager.has_method("wire_hover_sfx"):
		AudioManager.wire_hover_sfx(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Show the prep screen for the given settings and take mouse control.
func open_prep(p_map_id: String, p_difficulty: int, p_mode: String, p_contract_order: int, p_free_play: bool = false) -> void:
	map_id = p_map_id
	difficulty = clampi(p_difficulty, 1, 3)
	mode = p_mode
	contract_order = p_contract_order
	free_play = p_free_play
	# A re-opened prep is a fresh decision: never carry a running countdown
	# (or its audio ticks) across open_prep calls.
	_cancel_countdown(false)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("open")
	# S09: soft rooftop wind bed under the prep screen. The louder
	# S05 PONDER swell remains opt-in through start_bed("wind").
	if AudioManager != null and AudioManager.has_method("start_bed"):
		AudioManager.start_bed("wind_prep", 0.8)
	_refresh_all()


## Hide, restore mouse, emit closed and free.
func close_prep() -> void:
	_cancel_countdown(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("back")
	closed.emit()
	visible = false
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo:
			var vp: Viewport = get_viewport()
			if kev.keycode == KEY_F or kev.keycode == KEY_SPACE:
				if vp != null:
					vp.set_input_as_handled()
				_on_ready_action()
				return
			if kev.keycode == KEY_ESCAPE:
				if vp != null:
					vp.set_input_as_handled()
				close_prep()
				return


## READY is now a two-state action: first press starts the authored 6 s
## countdown, a second press cancels it. The deploy itself happens at zero.
func _on_ready_action() -> void:
	if _deploy_emitted:
		return
	if _countdown_running:
		_cancel_countdown(true)
		if AudioManager != null and AudioManager.has_method("play_ui"):
			AudioManager.play_ui("back")
		return
	_start_countdown()


func _start_countdown() -> void:
	_countdown_running = true
	_countdown_remaining = COUNTDOWN_SECONDS
	_countdown_last_int = int(COUNTDOWN_SECONDS)
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("confirm")
	# AU4: the shipped countdown is exactly 6 x 1.00 s ticks; starting it with
	# the UI countdown keeps label and audio aligned tick-for-tick.
	if AudioManager != null and AudioManager.has_method("start_countdown"):
		AudioManager.start_countdown()
	_refresh_countdown()
	_refresh_ready_controls()


## `stop_audio` is false for open_prep resets (nothing is playing yet).
func _cancel_countdown(stop_audio: bool) -> void:
	if stop_audio and _countdown_running:
		if AudioManager != null and AudioManager.has_method("stop_countdown"):
			AudioManager.stop_countdown()
	_countdown_running = false
	_countdown_remaining = 0.0
	_countdown_last_int = int(COUNTDOWN_SECONDS)
	_refresh_countdown()
	_refresh_ready_controls()


func _process(delta: float) -> void:
	if not _countdown_running or _deploy_emitted:
		return
	_countdown_remaining = maxf(0.0, _countdown_remaining - delta)
	var shown: int = int(ceil(_countdown_remaining))
	if shown >= 1 and shown != _countdown_last_int:
		_countdown_last_int = shown
		_refresh_countdown()
	if _countdown_remaining <= 0.0:
		_countdown_running = false
		_refresh_ready_controls()
		_emit_ready()


## Final deploy. Guarded so a countdown that reaches zero while another path
## (BACK, queue_free) races it can never emit `ready_pressed` twice.
func _emit_ready() -> void:
	if _deploy_emitted:
		return
	_deploy_emitted = true
	_countdown_running = false
	if AudioManager != null and AudioManager.has_method("stop_countdown"):
		AudioManager.stop_countdown()
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("confirm")
	# T7: thread the OptionButton choice into the deploy handoff. _selected_mission_idx
	# carries the player's override (_on_mission_selected) or the map default; without
	# this, setup re-derived positionally and the override was silently discarded.
	var picked_id: String = ""
	if _selected_mission_idx >= 0 and _selected_mission_idx < _mission_rows.size():
		var picked: Dictionary = _mission_rows[_selected_mission_idx]
		if str(picked.get("map_id", "")) == map_id:
			picked_id = str(picked.get("id", ""))
	if picked_id != "":
		GameState.active_mission_id = picked_id
	# Free-play READY stages mode + mission id together: reset_run clears the
	# live flag on the map-change reset and republishes this stash.
	if free_play:
		GameState.begin_free_play(picked_id if picked_id != "" else GameState.FREE_PLAY_MISSION_ID)
	else:
		GameState.end_free_play()
	ready_pressed.emit(map_id, difficulty, mode, contract_order)
	visible = false
	queue_free()


## Leaving the prep screen (READY, BACK, or table teardown) ends the S09 bed;
## mission_controller then starts the destination scene beds.
func _exit_tree() -> void:
	if _countdown_running and AudioManager != null and AudioManager.has_method("stop_countdown"):
		AudioManager.stop_countdown()
	if AudioManager != null and AudioManager.has_method("stop_bed"):
		AudioManager.stop_bed("wind_prep", 0.25)


func _build_all() -> void:
	# NOTE: keep_offsets=false is load-bearing on both full-rect presets below.
	# This Control is constructed via .new() at size (0,0) and parented to a
	# CanvasLayer; the set_anchors_preset default (keep_offsets=true) would
	# preserve that zero size, leaving this Control and stage_box at (0,0) and
	# crushing the authored 1280x720 backdrop SubViewport to the (2,2)
	# engine-minimum floor, which emits the godot#86631 cascade with SSIL on.
	set_anchors_preset(Control.PRESET_FULL_RECT, false)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stage_box: SubViewportContainer = SubViewportContainer.new()
	stage_box.name = "PrepBackdropContainer"
	stage_box.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	stage_box.offset_left = 0.0
	stage_box.offset_top = 0.0
	stage_box.offset_right = 0.0
	stage_box.offset_bottom = 0.0
	stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Floor, not a shrink target: the authored backdrop is 1280x720 and the
	# container must never report smaller; it still stretches to fill the
	# window via the full-rect anchors above.
	stage_box.custom_minimum_size = Vector2(STAGE_VIEWPORT_SIZE)
	stage_box.stretch = true
	stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage_box)
	var viewport: SubViewport = SubViewport.new()
	viewport.name = "PrepBackdropViewport"
	viewport.own_world_3d = true
	viewport.size = STAGE_VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	stage_box.add_child(viewport)
	_build_stage(viewport)

	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.01, 0.03, 0.08)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()
	var italic: Font = ThemeScript.font_italic()

	var top_hdr: VBoxContainer = VBoxContainer.new()
	top_hdr.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_hdr.offset_left = -240.0
	top_hdr.offset_top = 14.0
	top_hdr.offset_right = 240.0
	top_hdr.offset_bottom = 96.0
	top_hdr.add_theme_constant_override("separation", 2)
	top_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_hdr)

	var title: Label = Label.new()
	title.text = "MISSION STARTING IN 5..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.05, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	if serif != null:
		title.add_theme_font_override("font", serif)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_hdr.add_child(title)
	_countdown_lbl = title
	var underline: ColorRect = ColorRect.new()
	underline.custom_minimum_size = Vector2(0.0, 1.0)
	underline.color = Color(ThemeScript.TEAL_ACCENT.r, ThemeScript.TEAL_ACCENT.g, ThemeScript.TEAL_ACCENT.b, 0.55)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_hdr.add_child(underline)

	_mode_sub_lbl = Label.new()
	_mode_sub_lbl.text = "Mode: Solo"
	_mode_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_sub_lbl.add_theme_font_size_override("font_size", 14)
	_mode_sub_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_mode_sub_lbl.add_theme_font_override("font", sans)
	_mode_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_hdr.add_child(_mode_sub_lbl)

	_diff_sub_lbl = Label.new()
	_diff_sub_lbl.text = "Difficulty: Novice"
	_diff_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diff_sub_lbl.add_theme_font_size_override("font_size", 14)
	_diff_sub_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	if sans != null:
		_diff_sub_lbl.add_theme_font_override("font", sans)
	_diff_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_hdr.add_child(_diff_sub_lbl)

	var left: VBoxContainer = VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.position = Vector2(28, 34)
	left.custom_minimum_size = Vector2(416, 0)
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(left)
	var loc_card: PanelContainer = _make_card("LOCATION", "", "")
	left.add_child(loc_card)
	_location_title_lbl = loc_card.get_meta("title_lbl") as Label
	_location_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_location_body = loc_card.get_meta("body_lbl") as Label
	_location_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_location_body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if italic != null:
		_location_body.add_theme_font_override("font", italic)
	var loc_vb: VBoxContainer = loc_card.get_meta("vbox") as VBoxContainer
	_location_art = TextureRect.new()
	_location_art.name = "LocationArt"
	_location_art.custom_minimum_size = Vector2(382, 108)
	_location_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_location_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_location_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loc_vb.add_child(_location_art)
	loc_vb.move_child(_location_art, 2)

	var mis_card: PanelContainer = _make_card("MISSION", "", "")
	mis_card.mouse_filter = Control.MOUSE_FILTER_PASS
	left.add_child(mis_card)
	_mission_title_lbl = mis_card.get_meta("title_lbl") as Label
	_mission_body = mis_card.get_meta("body_lbl") as Label
	var mis_vb: VBoxContainer = mis_card.get_meta("vbox") as VBoxContainer
	mis_vb.mouse_filter = Control.MOUSE_FILTER_PASS
	var mis_row: HBoxContainer = HBoxContainer.new()
	mis_row.add_theme_constant_override("separation", 10)
	mis_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_icon = TextureRect.new()
	_mission_icon.name = "MissionIcon"
	_mission_icon.custom_minimum_size = Vector2(48, 48)
	_mission_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mission_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mission_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mis_row.add_child(_mission_icon)
	mis_vb.remove_child(_mission_title_lbl)
	_mission_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mis_row.add_child(_mission_title_lbl)
	mis_vb.add_child(mis_row)
	mis_vb.move_child(mis_row, 1)
	_mission_selector = OptionButton.new()
	_mission_selector.name = "MissionSelector"
	_mission_selector.custom_minimum_size = Vector2(380, 28)
	ThemeScript.style_teal_option(_mission_selector)
	_mission_selector.item_selected.connect(_on_mission_selected)
	mis_vb.add_child(_mission_selector)
	_populate_mission_rows()

	var con_card: PanelContainer = _make_card("CONTRACT", "", "")
	left.add_child(con_card)
	_contract_title_lbl = con_card.get_meta("title_lbl") as Label
	_contract_body = con_card.get_meta("body_lbl") as Label

	# KF11: READY / player name sit under the thief, above the action row.
	var ready_box: VBoxContainer = VBoxContainer.new()
	ready_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ready_box.offset_left = -360.0
	ready_box.offset_top = -180.0
	ready_box.offset_right = -24.0
	ready_box.offset_bottom = -132.0
	ready_box.alignment = BoxContainer.ALIGNMENT_END
	ready_box.add_theme_constant_override("separation", 0)
	ready_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ready_box)
	_readiness_lbl = Label.new()
	_readiness_lbl.text = "READY"
	_readiness_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_readiness_lbl.add_theme_font_size_override("font_size", 22)
	_readiness_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	if serif != null:
		_readiness_lbl.add_theme_font_override("font", serif)
	_readiness_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_box.add_child(_readiness_lbl)
	_thief_name_lbl = Label.new()
	_thief_name_lbl.text = "The Spider"
	_thief_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_thief_name_lbl.add_theme_font_size_override("font_size", 16)
	_thief_name_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if serif != null:
		_thief_name_lbl.add_theme_font_override("font", serif)
	_thief_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_box.add_child(_thief_name_lbl)

	var bottom: VBoxContainer = VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom.offset_left = -360.0
	bottom.offset_top = -126.0
	bottom.offset_right = -24.0
	bottom.offset_bottom = -20.0
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	add_child(bottom)
	_controls_lbl = Label.new()
	_controls_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_controls_lbl.add_theme_font_size_override("font_size", 14)
	_controls_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	if sans != null:
		_controls_lbl.add_theme_font_override("font", sans)
	_controls_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_controls_lbl)
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	bottom.add_child(btn_row)
	var ready_btn: Button = Button.new()
	ready_btn.text = "[F]  READY"
	ready_btn.custom_minimum_size = Vector2(150, 42)
	ThemeScript.style_teal_button(ready_btn, true)
	ready_btn.pressed.connect(_on_ready_action)
	btn_row.add_child(ready_btn)
	_ready_btn = ready_btn
	var back_btn: Button = Button.new()
	back_btn.text = "[ESC]  BACK"
	back_btn.custom_minimum_size = Vector2(146, 42)
	ThemeScript.style_teal_button(back_btn, false)
	back_btn.pressed.connect(close_prep)
	btn_row.add_child(back_btn)


## Container-crush guard (godot#86631): re-asserts full-rect layout without
## keeping offsets and re-applies the authored 1280x720 backdrop floor if the
## container chain ever measures near-zero again (late layout, window resize).
## Runs deferred after _ready and on every resized signal. SSIL/SSAO handling
## is untouched: this only guarantees the viewport SSIL renders into is real.
func _ensure_stage_size() -> void:
	if not is_inside_tree():
		return
	set_anchors_preset(Control.PRESET_FULL_RECT, false)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	if size.x < 32.0 or size.y < 32.0:
		var want: Vector2 = get_viewport_rect().size
		if want.x >= 32.0 and want.y >= 32.0:
			position = Vector2.ZERO
			size = want
	for child: Node in get_children():
		if not (child is SubViewportContainer):
			continue
		var box: SubViewportContainer = child as SubViewportContainer
		box.set_anchors_preset(Control.PRESET_FULL_RECT, false)
		box.offset_left = 0.0
		box.offset_top = 0.0
		box.offset_right = 0.0
		box.offset_bottom = 0.0
		for vp_child: Node in box.get_children():
			if not (vp_child is SubViewport):
				continue
			var sv: SubViewport = vp_child as SubViewport
			if sv.size.x < STAGE_VIEWPORT_SIZE.x or sv.size.y < STAGE_VIEWPORT_SIZE.y:
				sv.size = STAGE_VIEWPORT_SIZE


func _make_card(header: String, title_text: String, body_text: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	panel.add_theme_stylebox_override("panel", ThemeScript.teal_card_style(1, 4, Color(0.024, 0.056, 0.075, 0.84), 12))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ThemeScript.add_teal_filigree(panel, 3.0, 16.0)
	var serif: Font = ThemeScript.font_serif()
	var sans: Font = ThemeScript.font_sans()
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	var hdr: Label = Label.new()
	hdr.text = header
	hdr.add_theme_font_size_override("font_size", 13)
	hdr.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	if sans != null:
		hdr.add_theme_font_override("font", sans)
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hdr)
	var title_lbl: Label = Label.new()
	title_lbl.text = title_text
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if serif != null:
		title_lbl.add_theme_font_override("font", serif)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title_lbl)
	var body_lbl: Label = Label.new()
	body_lbl.text = body_text
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Fixed wrap width inside the card content box: autowrap alone wrapped at
	# the exact content edge, clipping the last glyph at 1280x720.
	body_lbl.custom_minimum_size = Vector2(CARD_BODY_WRAP_WIDTH, 0)
	body_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body_lbl.add_theme_font_size_override("font_size", 14)
	body_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		body_lbl.add_theme_font_override("font", sans)
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(body_lbl)
	panel.set_meta("title_lbl", title_lbl)
	panel.set_meta("body_lbl", body_lbl)
	panel.set_meta("vbox", vb)
	return panel


func _build_stage(viewport: SubViewport) -> void:
	var stage_root: Node3D = Node3D.new()
	stage_root.name = "MissionLobbyStage"
	viewport.add_child(stage_root)

	var wenv: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.20
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.03, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.36, 0.56)
	env.ambient_light_energy = 0.45
	wenv.environment = env
	stage_root.add_child(wenv)

	var moonlight: DirectionalLight3D = DirectionalLight3D.new()
	moonlight.name = "MissionLobbyMoonLight"
	moonlight.light_color = Color(0.6039, 0.702, 1.0)
	moonlight.light_energy = 0.35
	moonlight.shadow_enabled = true
	stage_root.add_child(moonlight)

	var preset: Dictionary = WeatherProfile.load_preset("midnight_clear_mission_lobby")
	if not preset.is_empty():
		WeatherProfile.apply_environment(env, moonlight, preset)
		WeatherVisuals.apply_sky(env, preset, moonlight)
	# SSIL on this own-world SubViewport is unstable in 4.7 (the static/RGB
	# cascade). The lobby is lit by the practical rig; keep SSR/glow only.
	env.ssil_enabled = false
	# KF11 lift: keep the authored midnight sky and practicals, but raise the
	# camera-bound environment's exposure/ambient so the rooftop reads behind
	# the UI. The CanvasLayer UI is unaffected (no WorldEnvironment on it).
	env.tonemap_exposure = maxf(env.tonemap_exposure, STAGE_EXPOSURE)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.50, 0.72)
	env.ambient_light_sky_contribution = 0.0
	env.ambient_light_energy = STAGE_AMBIENT_ENERGY
	env.glow_enabled = true
	env.glow_intensity = STAGE_GLOW_INTENSITY
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.95
	env.background_energy_multiplier = STAGE_SKY_ENERGY

	var loader: Node = _get_preview_mat_loader()
	if loader != null:
		var sublevels: Array[String] = [
			"res://data/generated/levels/MissionLobby/MissionLobby_Geo3.tatlevel.json",
			"res://data/generated/levels/MissionLobby/MissionLobby_Periphery.tatlevel.json",
		]
		loader.call("load_sublevels", sublevels, stage_root, null, 64, false)

	var cam: Camera3D = Camera3D.new()
	cam.name = "MissionLobbyCamera"
	cam.position = LOBBY_CAM_POS
	cam.fov = LOBBY_CAM_FOV
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.far = 2000.0
	cam.current = true
	stage_root.add_child(cam)
	# Godot 4.7: a WorldEnvironment inside an own-world SubViewport registers on
	# the parent world; bind the environment to the camera after it enters the
	# tree so the lobby stage is actually lit.
	cam.environment = env
	# The authored yaw already keeps the information stack left and the
	# thief in the open right half; adding yaw here swings into the facade.
	cam.look_at_from_position(cam.position, cam.position + LOBBY_CAM_FWD.normalized() * 15.0, Vector3.UP)
	cam.rotate_object_local(Vector3.FORWARD, deg_to_rad(LOBBY_CAM_ROLL_DEG))
	_aim_kf11_moon(env, cam, viewport, moonlight)

	var thief_anchor: Node3D = Node3D.new()
	thief_anchor.name = "MissionLobbyThiefAnchor"
	thief_anchor.position = LOBBY_THIEF_POS
	thief_anchor.rotation_degrees = Vector3(0.0, LOBBY_THIEF_YAW_DEG, 0.0)
	stage_root.add_child(thief_anchor)
	_add_thief(thief_anchor)


## Re-aims the moon light so its sky disc lands at the KF11 screen position,
## and pushes the same world direction into the sky shader (built earlier by
## WeatherVisuals before the prep camera existed). The light also becomes the
## cool key that lifts the thief's front out of the dark rooftop.
func _aim_kf11_moon(env: Environment, cam: Camera3D, viewport: SubViewport, moonlight: DirectionalLight3D) -> void:
	if env == null or cam == null or moonlight == null:
		return
	var basis: Basis = cam.global_transform.basis
	var fwd: Vector3 = -basis.z
	var right: Vector3 = basis.x
	var up: Vector3 = basis.y
	var aspect: float = 1.7777778
	if viewport != null and viewport.size.y > 0:
		aspect = float(viewport.size.x) / float(viewport.size.y)
	var tan_h: float = tan(deg_to_rad(cam.fov * 0.5))
	var tan_v: float = tan(atan(tan_h / aspect)) if aspect > 0.001 else tan_h
	var ndc_x: float = MOON_SCREEN_X * 2.0 - 1.0
	var ndc_y: float = 1.0 - MOON_SCREEN_Y * 2.0
	var moon_dir: Vector3 = (fwd + right * (ndc_x * tan_h) + up * (ndc_y * tan_v)).normalized()
	moonlight.light_energy = maxf(moonlight.light_energy, STAGE_MOON_ENERGY)
	moonlight.look_at_from_position(moonlight.global_position, moonlight.global_position - moon_dir, Vector3.UP)
	var sky_mat: Material = env.sky.sky_material if env.sky != null else null
	if sky_mat is ShaderMaterial:
		var sm: ShaderMaterial = sky_mat as ShaderMaterial
		sm.set_shader_parameter("moon_direction", moon_dir)
		sm.set_shader_parameter("moon_energy", STAGE_MOON_DISC_ENERGY)
		sm.set_shader_parameter("moon_halo_strength", 0.7)


func _add_thief(anchor: Node3D) -> void:
	var body_path: String = _first_existing(BODY_CANDIDATES)
	var head_path: String = _first_existing(HEAD_CANDIDATES)
	if body_path != "":
		var body_res: Resource = ResourceLoader.load(body_path) as Resource
		if body_res is PackedScene:
			var body_node: Node = (body_res as PackedScene).instantiate()
			_thief_body_node = body_node
			anchor.add_child(body_node)
			_bind_preview_character_materials(body_node, _glb_to_ue_mesh(body_path))
			_apply_thief_idle_pose(body_node)
		else:
			_add_placeholder_body(anchor)
	else:
		_add_placeholder_body(anchor)
	if head_path != "":
		var head_res: Resource = ResourceLoader.load(head_path) as Resource
		if head_res is PackedScene:
			var head_node: Node = (head_res as PackedScene).instantiate()
			_thief_head_node = head_node
			head_node.position = Vector3.ZERO
			anchor.add_child(head_node)
			_bind_preview_character_materials(head_node, _glb_to_ue_mesh(head_path))
			_apply_thief_idle_pose(head_node)
		else:
			_add_placeholder_head(anchor)
	else:
		_add_placeholder_head(anchor)


func _apply_thief_idle_pose(root: Node) -> void:
	if root == null:
		return
	var skels: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0] as Skeleton3D
	if skel == null or skel.get_parent() == null:
		return
	var alib: GuardAnimationLibrary = GuardAnimLibScript.new()
	if not alib.setup("club", skel):
		return
	var anim: Animation = alib._retarget_general("AN_ThiefNisha_Unarmed_StandIdle", true, true, true)
	if anim == null:
		anim = alib._retarget_general("AN_ThiefNisha_WardrobeIdle", true, true, true)
	if anim == null:
		return
	var ap := AnimationPlayer.new()
	ap.name = "ThiefIdleAnimPlayer"
	root.add_child(ap)
	ap.root_node = ap.get_path_to(skel.get_parent())
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", anim)
	ap.add_animation_library("", lib)
	ap.play("idle")


func _add_placeholder_body(anchor: Node3D) -> void:
	var coat_mat: StandardMaterial3D = StandardMaterial3D.new()
	coat_mat.albedo_color = Color(0.07, 0.09, 0.13)
	coat_mat.roughness = 0.8
	var body: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.32
	capsule.height = 1.15
	body.mesh = capsule
	body.material_override = coat_mat
	body.position = Vector3(0, 0.75, 0)
	anchor.add_child(body)
	var trim_mat: StandardMaterial3D = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.55, 0.38, 0.16)
	trim_mat.roughness = 0.6
	var belt: MeshInstance3D = MeshInstance3D.new()
	var belt_box: BoxMesh = BoxMesh.new()
	belt_box.size = Vector3(0.5, 0.09, 0.4)
	belt.mesh = belt_box
	belt.material_override = trim_mat
	belt.position = Vector3(0, 0.72, 0)
	anchor.add_child(belt)


func _add_placeholder_head(anchor: Node3D) -> void:
	var hood_mat: StandardMaterial3D = StandardMaterial3D.new()
	hood_mat.albedo_color = Color(0.06, 0.07, 0.11)
	hood_mat.roughness = 0.85
	var head: MeshInstance3D = MeshInstance3D.new()
	var skull: SphereMesh = SphereMesh.new()
	skull.radius = 0.22
	skull.height = 0.44
	head.mesh = skull
	head.material_override = hood_mat
	head.position = Vector3(0, 1.5, 0)
	anchor.add_child(head)
	var mask_mat: StandardMaterial3D = StandardMaterial3D.new()
	mask_mat.albedo_color = Color(0.45, 0.08, 0.10)
	mask_mat.roughness = 0.5
	var mask: MeshInstance3D = MeshInstance3D.new()
	var band: BoxMesh = BoxMesh.new()
	band.size = Vector3(0.34, 0.11, 0.10)
	mask.mesh = band
	mask.material_override = mask_mat
	mask.position = Vector3(0, 1.52, 0.16)
	anchor.add_child(mask)


func _first_existing(paths: Array[String]) -> String:
	for p: String in paths:
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			return p
	return ""


## Maps a res:// GLB path under assets/ue/Content to its UE package key,
## so mesh_materials.json can be looked up without a second table.
func _glb_to_ue_mesh(res_path: String) -> String:
	var marker: String = "assets/ue/Content/"
	var idx: int = res_path.find(marker)
	if idx < 0:
		return ""
	var rel: String = res_path.substr(idx + marker.length())
	if rel.ends_with(".glb"):
		rel = rel.substr(0, rel.length() - 4)
	return "/Game/" + rel


## Lazily creates the LevelLoader used only as a material resolver for the
## preview character. Its _ready() loads materials.json + mesh_materials.json;
## no level is loaded through it.
func _get_preview_mat_loader() -> Node:
	if _mat_loader == null:
		_mat_loader = LevelLoaderScript.new()
		add_child(_mat_loader)
	return _mat_loader


## Binds authored PBR materials onto an instantiated character GLB by its
## GLB primitive-order slots (mesh_materials.json). Surfaces are overridden,
## not the shared mesh resource, so the GLB import cache stays immutable.
func _bind_preview_character_materials(root: Node, ue_mesh_path: String) -> void:
	if root == null or ue_mesh_path == "":
		return
	var loader: Node = _get_preview_mat_loader()
	if loader == null:
		return
	var db: Dictionary = loader.get("_mesh_mats_db") as Dictionary
	var slots_v: Variant = db.get(ue_mesh_path, null) if db != null else null
	if not (slots_v is Array):
		var db_low: Dictionary = loader.get("_mesh_mats_db_lower") as Dictionary
		slots_v = db_low.get(ue_mesh_path.to_lower(), null) if db_low != null else null
	if not (slots_v is Array):
		return
	_bind_preview_meshes(root, loader, slots_v as Array)


func _bind_preview_meshes(node: Node, loader: Node, slots: Array) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			var count: int = mini(mi.mesh.get_surface_count(), slots.size())
			for s: int in range(count):
				var mat_path: String = str(slots[s])
				if mat_path == "":
					continue
				var mat: Material = loader.call("get_material_for_ue", mat_path) as Material
				if mat != null:
					mi.set_surface_override_material(s, mat)
	for child: Node in node.get_children():
		_bind_preview_meshes(child, loader, slots)


func _load_ui_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var t: Variant = load(path)
		if t is Texture2D:
			return t as Texture2D
	if FileAccess.file_exists(path):
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func _populate_mission_rows() -> void:
	_mission_rows.clear()
	if _mission_selector != null:
		_mission_selector.clear()
	var gd: Node = get_node_or_null("/root/GameData")
	if gd != null and gd.has_method("get_all_missions"):
		var raw: Variant = gd.call("get_all_missions")
		if raw is Array:
			for m_v: Variant in (raw as Array):
				if m_v is Dictionary:
					_mission_rows.append(m_v as Dictionary)
	for m: Dictionary in _mission_rows:
		if _mission_selector != null:
			_mission_selector.add_item("%s (%s)" % [str(m.get("title", "")), str(m.get("id", ""))])


func _on_mission_selected(idx: int) -> void:
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("click")
	if idx >= 0 and idx < _mission_rows.size():
		_selected_mission_idx = idx
		_apply_selected_mission_row()


func _refresh_all() -> void:
	if _mission_rows.is_empty():
		_populate_mission_rows()
	_select_default_mission_for_map()
	_refresh_location_card()
	_refresh_mission_card()
	_refresh_contract_card()
	_refresh_controls()


func _select_default_mission_for_map() -> void:
	if free_play:
		# Free play selects the Cleanout row by id, not positionally: the
		# authored thresholds/duration live on Mission.Guildhall.LootTheRoom.
		for i: int in range(_mission_rows.size()):
			if str(_mission_rows[i].get("id", "")) == GameState.FREE_PLAY_MISSION_ID:
				_selected_mission_idx = i
				if _mission_selector != null and i < _mission_selector.item_count:
					_mission_selector.select(i)
				return
	var matching: Array[int] = []
	for i: int in range(_mission_rows.size()):
		if str(_mission_rows[i].get("map_id", "")) == map_id:
			matching.append(i)
	if not matching.is_empty():
		_selected_mission_idx = matching[abs(contract_order) % matching.size()]
	elif not _mission_rows.is_empty():
		_selected_mission_idx = 0
	else:
		_selected_mission_idx = -1
	if _mission_selector != null and _selected_mission_idx >= 0 and _selected_mission_idx < _mission_selector.item_count:
		_mission_selector.select(_selected_mission_idx)


func _refresh_location_card() -> void:
	if _location_title_lbl == null or _location_body == null:
		return
	var info: Array = _location_info()
	_location_title_lbl.text = str(info[0])
	_location_body.text = str(info[1])
	if _location_art != null:
		var art_path: String = str(LOCATION_ART_MAP.get(map_id, ""))
		var tex: Texture2D = _load_ui_tex(art_path)
		_location_art.texture = tex
		_location_art.visible = tex != null


func _location_info() -> Array:
	if map_id == "old_manor":
		return [LOC_OLD_MANOR_TITLE, LOC_OLD_MANOR_DESC]
	if map_id == "guildhall":
		return [LOC_GUILDHALL_TITLE, LOC_GUILDHALL_DESC]
	if map_id == "jaspering_hall":
		return ["JASPERING HALL", "A glittering jewelry house and private gallery in Kilcairn's merchant quarter, heavy with private security."]
	return [map_id.to_upper(), "A shadowed mark in Kilcairn, ripe for the taking."]


func _refresh_mission_card() -> void:
	if _mission_title_lbl == null or _mission_body == null:
		return
	if _selected_mission_idx >= 0 and _selected_mission_idx < _mission_rows.size():
		_apply_selected_mission_row()
		return
	var idx: int = abs(contract_order) % 3
	var titles: Array[String] = ["Vault Heist", "Item Collection Heist", "Cleanout Heist"]
	_mission_title_lbl.text = titles[idx]
	var minutes: int = _mission_minutes(idx, difficulty)
	var desc: String = _mission_description(idx, minutes)
	_mission_body.text = desc + "\nTime Limit: %d minutes" % minutes
	if _mission_icon != null:
		_mission_icon.texture = null
		_mission_icon.visible = false


func _apply_selected_mission_row() -> void:
	var row: Dictionary = _mission_rows[_selected_mission_idx]
	_mission_title_lbl.text = str(row.get("title", row.get("id", "Mission")))
	var durs_v: Variant = row.get("durations", [])
	var durs: Array = durs_v as Array if durs_v is Array else []
	var d_idx: int = clampi(difficulty - 1, 0, maxi(durs.size() - 1, 0))
	var dur_sec: float = float(durs[d_idx]) if d_idx < durs.size() else 0.0
	var minutes: int = int(round(dur_sec / 60.0))
	var desc: String = str(row.get("description", ""))
	if desc.find("{MatchDurationInMinutes}") >= 0:
		desc = desc.replace("{MatchDurationInMinutes}", str(minutes))
	if minutes > 0:
		_mission_body.text = desc + "\nTime Limit: %d minutes" % minutes
	else:
		_mission_body.text = desc + "\nTime Limit: Unlimited"
	if _mission_icon != null:
		var icon_tex: Texture2D = _load_ui_tex(str(row.get("icon_path", "")))
		_mission_icon.texture = icon_tex
		_mission_icon.visible = icon_tex != null


func _mission_minutes(mission_idx: int, diff: int) -> int:
	var d: int = clampi(diff, 1, 3)
	if mission_idx == 2:
		if map_id == "old_manor":
			var old_times: Array[int] = [75, 30, 25]
			return old_times[d - 1]
		if map_id == "guildhall":
			var gh_times: Array[int] = [55, 20, 20]
			return gh_times[d - 1]
		var other_times: Array[int] = [60, 30, 20]
		return other_times[d - 1]
	var std_times: Array[int] = [120, 45, 30]
	return std_times[d - 1]


func _mission_description(mission_idx: int, minutes: int) -> String:
	var mins: String = str(minutes)
	if map_id == "old_manor":
		if mission_idx == 0:
			return "The Elway family has a magical tome they keep under the utmost protection in a vault. Tonight you will have a %s minute window when security is light. Find the book, steal it, and get out alive." % mins
		if mission_idx == 1:
			return "The Claymur Urns have been held by the Elway family for centuries. The Guild will pay handsomely if you retrieve the full set. You have a %s minute window to pilfer the Urns and make your escape." % mins
		return "Though both the Elway family and their estate are a shadow of what they once were, there are still ample treasures to be found. Get in, steal everything you can, and get out before anyone is the wiser."
	if mission_idx == 0:
		return "A rare bust called the Warburg Effigy is being held at the Guildhall for safekeeping. Tonight there is a %s minute window when security will be light. Steal the bust, embarrass the police, and turn a tidy profit." % mins
	if mission_idx == 1:
		return "The precious gems needed to restore an artifact are hidden among the trinkets gathering dust in the Guildhall. You have a %s minute window to pilfer the gems from under the very noses of the police." % mins
	return "The Constables' Guildhall is full of confiscated treasures. Infiltrate the building and reacquire some of the riches they have just left lying around, then slip away before anyone notices."


func _refresh_contract_card() -> void:
	if _contract_title_lbl == null or _contract_body == null:
		return
	var info: Array = _contract_info()
	_contract_title_lbl.text = str(info[0])
	_contract_body.text = str(info[1])


func _contract_info() -> Array:
	if free_play:
		return [_loc(CONTRACT_INACTIVE), "Free play: clean out the location for a score. No contract progress is recorded."]
	if contract_order <= 0:
		return [_loc(CONTRACT_INACTIVE), "Your active contract is not available for the currently selected map."]
	var disp: Dictionary = GameData.get_contract_display(contract_order)
	var title_text: String = str(disp.get("title", ""))
	if title_text == "":
		return [_loc(CONTRACT_INACTIVE), "Your active contract is not available for the currently selected map."]
	var quest_text: String = str(disp.get("quest_item", ""))
	var loc_text: String = str(disp.get("location", ""))
	var body_text: String = "Active contract: %s" % title_text
	if quest_text != "":
		body_text += "\nTarget: %s" % quest_text
	if loc_text != "":
		body_text += "\n%s" % loc_text
	return [title_text, body_text]


func _refresh_controls() -> void:
	if _mode_sub_lbl != null:
		_mode_sub_lbl.text = _loc_fmt("Mode: {mode}", {"mode": mode})
	if _diff_sub_lbl != null:
		_diff_sub_lbl.text = _loc_fmt("Difficulty: {difficulty}", {"difficulty": _difficulty_label()})
	_refresh_countdown()
	if _thief_name_lbl != null:
		_thief_name_lbl.text = _thief_label()
	_refresh_ready_controls()


## READY/UNREADY wording shared by the header label, the [F] button and the
## controls hint, so all three can never disagree about countdown state.
func _refresh_ready_controls() -> void:
	var word: String = _loc("Unready") if _countdown_running else _loc("Ready")
	var upper: String = word.to_upper()
	if _readiness_lbl != null:
		_readiness_lbl.text = upper
	if _ready_btn != null:
		_ready_btn.text = "[F]  %s" % upper
	if _controls_lbl != null:
		_controls_lbl.text = "[F] %s  ·  [ESC] BACK" % upper


## Header line: the authored MissionLobby countdown template with its number
## substituted ("MISSION STARTING IN 6..." down to "1..."). At rest it shows
## the full countdown so the player knows what READY starts.
func _refresh_countdown() -> void:
	if _countdown_lbl == null:
		return
	var shown: int = _countdown_last_int if _countdown_running else int(COUNTDOWN_SECONDS)
	var tmpl: String = _loc("Mission Starting in <Num>{number}</>...")
	tmpl = tmpl.replace("<Num>", "").replace("</>", "")
	_countdown_lbl.text = tmpl.replace("{number}", str(shown)).to_upper()


func _loc(source: String) -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc != null and loc.has_method("t"):
		return str(loc.call("t", source))
	return source


func _loc_fmt(source: String, values: Dictionary) -> String:
	var out: String = _loc(source)
	for key: Variant in values.keys():
		out = out.replace("{%s}" % str(key), str(values[key]))
	return out


func _thief_label() -> String:
	if str(GameState.thief_id) == "chameleon":
		return _loc("The Chameleon")
	return _loc("The Spider")


func _difficulty_label() -> String:
	if difficulty == 1:
		return _loc("Novice")
	if difficulty == 2:
		return _loc("Thief")
	return _loc("Master Thief")
