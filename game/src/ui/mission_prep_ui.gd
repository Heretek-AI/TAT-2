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

const LOC_OLD_MANOR_DESC: String = "This is the estate of the three Elway sisters. Although it has fallen into disrepair, both the house and the family that holds it have a very long history in Kilcairn."
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
const UIStringsScript: GDScript = preload("res://src/ui/ui_strings.gd")
const FocusNavScript: GDScript = preload("res://src/ui/focus_nav.gd")

## Authored MissionLobby_Geo3 CameraActor_0. UE FOV is the horizontal field of
## view, so Godot maps it with keep_aspect KEEP_WIDTH: fov reads 20.0 while the
## rendered vertical stays ~11.33 at 16:9.
##
## The live stage camera IS the authored camera (T05 P0, 2026-11-25). It was
## replaced in 7128d43 by a 14.06 m / 69.1 deg-off reframe; that reframe is the
## mission-prep regression the user reported ("empty blue-violet void"): a
## position-only cone test over the two generated lobby sublevels finds only
## **13** mesh pivots inside the current 10 deg half-angle versus **387** from
## the authored transform (2,107 meshes total). The void was the reframe, not
## missing geometry. Do not re-introduce a stage reframe here: re-author the
## level or the expansion data instead.
##
## Authored CameraActor_0 in the level's (x, z, y) Godot mapping is
## (12.6065, -0.16698, -1.05384) looking (-0.986184, 0.116419, +0.117848);
## pitch 6.68548 (the forward Y), yaw 173.18552, roll -14.780165, FOV 20.0
## horizontal / 11.33 vertical at 16:9 (extracted/json/Maps/MissionLobby/
## MissionLobby_Geo3.json, CameraActor_0 -> CameraComponent).
const LOBBY_CAM_POS: Vector3 = Vector3(12.6065, -0.16698, -1.05384)
const LOBBY_CAM_FWD: Vector3 = Vector3(-0.986184, 0.116419, 0.117848)
const LOBBY_CAM_FOV: float = 20.0
const LOBBY_CAM_ROLL_DEG: float = -14.780165
## Authored BP_MatchLobbyDummyPlayer_C_1 (IsForLocalPlayer: True) rooftop slot,
## (-1.5871, 0.9399, -0.7868) m with 45 deg yaw. The authored Y is the dummy
## actor's pivot; the port keeps its measured feet-on-roof delta of 0.12 m
## (0.82) because the pilgrim's GLB origin sits at the hips, not the soles.
## The GLB's front is +Z, so 45 deg faces the authored camera: KF11's
## three-quarter view. Measured chest screen x from the authored camera: 0.78,
## inside KF11's 0.70-0.84 band without any dummy offset.
const LOBBY_THIEF_POS: Vector3 = Vector3(-1.5871, 0.82, -0.7868)
const LOBBY_THIEF_YAW_DEG: float = 45.0
## W9-P1: the stage grade is the AUTHORED gameplay grade, not four stage
## constants. `WeatherProfile.stage_grade_values(preset)` (T07's hand-off, dead
## code until W9-P1) returns the numbers `apply_environment` itself applies to a
## night preset: AGX, exposure 1.15 (NIGHT_EXPOSURE), ambient 0.35
## (sky.intensity 5.0 x 0.08), glow 0.12672 (bloom_intensity 6.336 x 0.02),
## background_energy_multiplier 1.0. The stage used to override to
## ACES/2.6/1.8/1.0/0.18 (the "ACES" label was stale: the preset apply already
## forced AGX, so the live mode was AGX at 2.6). One grade, one product.
## Measured at the authored composition: 37.1 mean / p50 19 / 18.8 % < 8; the
## same grade on the legacy full-lobby frame is 27.2 / 12 / 16.6 % — the old
## 2.6 exposure + 1.8 ambient was compensating for the occluded backdrop, so
## dropping it makes the composition rule the thing that carries the frame.
const STAGE_AMBIENT_COLOR: Color = Color(0.42, 0.50, 0.72)
## The two glow-shape values the grade dictionary does not carry (it carries
## intensity only). Unchanged from the pre-W9 stage, named so the grade has no
## unnamed literals left.
const STAGE_GLOW_BLOOM: float = 0.12
const STAGE_GLOW_HDR_THRESHOLD: float = 0.95
## The authored weather preset points the moon off-frame. W6U1 decoupled the
## visible disc from the key light:
##  * MOON_DISC_SCREEN is the sky disc only (KF13/KF11 upper-right composition).
##  * KEY_SCREEN is the cool directional key, aimed at the thief independently
##    (upper-left), so moving the disc can never drag the character lighting.
## W7V reframes the disc to KF11's measured (0.76, 0.09).
const MOON_DISC_SCREEN_X: float = 0.76
const MOON_DISC_SCREEN_Y: float = 0.09
const KEY_SCREEN_X: float = 0.30
const KEY_SCREEN_Y: float = 0.28
const STAGE_MOON_ENERGY: float = 0.85
## The sky background is the one grade value W9-P1 keeps a stage say over:
## `apply_sky` escalates night presets to 2.0 and the pre-W9 stage crushed it to
## 0.18 while exposure sat at 2.6 (a hack for the occluded composition). At the
## authored 1.15 exposure the authored 1.0 measures mean 37.1 / p50 19 / 18.8 %
## < 8 with the sky reading deep navy above the silhouette (p1_after_prep.png);
## higher washes the city out, so the refinement stays at the authored 1.0.
const STAGE_SKY_ENERGY: float = 1.0
const STAGE_MOON_DISC_ENERGY: float = 2.4
## Local character rig on the prep stage (KF11 keys the thief separately from
## the sky). Key = cool moonlight from the camera side, fill = warm neutral,
## rim = cool back edge to separate the silhouette from the slate roof.
const STAGE_KEY_ENERGY: float = 1.8
const STAGE_FILL_ENERGY: float = 0.32
const STAGE_RIM_ENERGY: float = 1.4

## W7V KF11 distant skyline: tracked TAT-2 expansion layout over the shipped
## Skybox distant-building kit. Stage-relative (azimuth/distance/base_y) so a
## reframe keeps the composition. See game/data/expansion/prep_skyline.json.
## T05: base_y is an ABSOLUTE world Y (the code's contract); the layout note says
## so. The composition band below is the numeric contract the headless test
## enforces against the REAL spawned MeshInstance AABBs under the authored
## camera, and W9-P1 re-measured it: KF11's city is the MID-GROUND roofline
## (silhouette tops p50 sy 0.372), not the near roof. The band is now
## [0.28, 0.46] against a measured 0.300 / p50 0.380 / 0.440, replacing
## [0.65, 0.98] which had encoded the pre-T05 310-500 m standoff at base_y 0 —
## that projection puts the tops at 0.746-0.954, i.e. where KF11 has the near
## roof, and it left every piece below the visible sky (measured: zero pixels,
## prep vs prep_nosky identical). Do not widen this band without a capture.
const PREP_SKYLINE_PATH: String = "res://data/expansion/prep_skyline.json"
const PREP_SKYLINE_SCHEMA: String = "tat2.prep_skyline/1"
const PREP_SKYLINE_GROUP: String = "prep_skyline"
const PREP_SKYLINE_MAX_WIDTH_FRAC: float = 0.60
const PREP_SKYLINE_TOP_MIN: float = 0.28
const PREP_SKYLINE_TOP_MAX: float = 0.46

## W9-P1 stage composition. The authored frame's occluder is the NEAR lobby
## facade 14-22 m behind the thief, not the far city and not the Periphery:
## freeing all 306 Periphery nodes leaves the frame statistically identical
## (mean 37.21 -> 36.91, build/qa/w9/captures/p1_before_prep.png), while hiding
## the lobby geometry beyond LOBBY_STAGE_KEEP_RADIUS_M from the authored thief
## slot reveals the already-built sky, the authored moon disc at (0.76, 0.09)
## and the distant silhouettes without touching the camera. So the composition
## is a data-driven cull rule, NOT a reframe: the camera transform, the thief
## slot, the 8 expansion skyline pieces and every node within the radius stay
## exactly as authored.
##
## Measured at 1920x1080, TAT2_AO=on, grade = the authored night grade
## (build/qa/w9/captures/p1_after_prep.png, log build/qa/w9/logs/cap_p1_after_prep.log):
##   kept=19 hid=397 radius=9.0  ->  mean 37.1 / p50 19 / p95 125 / 18.8 % < 8
##   same grade + TAT2_PREP_STAGE=legacy (p1_after_legacy.png): kept=422
##     ->  mean 27.2 / p50 12 / p95 117 / 16.6 % < 8, no sky, no moon
##   same grade + prep_nosky (p1_after_nosky.png): mean 43.9 / p50 29 / 8.8 % < 8
##     -> the skyline alone darkens the mid-ground by 6.8 mean / 10 p50 points,
##        so the far city is provably in frame.
## The pre-W9 composition at the old 2.6/1.8 grade measured 37.2 / 25 / 7.1 %
## < 8 — the same global mean with the wrong distribution (7.1 % black floor
## versus 18.8 %, because the frame was a rain-streaked wall, not a night city).
##
## TAT2_PREP_STAGE=legacy reproduces the pre-W9 full-lobby frame for A/B; any
## other value (default authored) applies the rule.
const LOBBY_STAGE_ENV: String = "TAT2_PREP_STAGE"
const LOBBY_STAGE_KEEP_RADIUS_M: float = 9.0
## Named exclusions for nodes the radius keeps but that do not belong to the
## authored ledge (matched case-insensitively against a node's `ue_mesh` meta or
## its name). Deliberately narrow: "hide anything ugly" is not a rule. Empty is
## the measured answer: at 9.0 m the kept set is the ledge, the roof under it and
## the lobby towers that KF11 also frames beside the subject (the pale 7 m
## columns at 6-8 m are authored lobby geometry, not floating props), and the
## captured frame reads as the authored ledge without a hole. Add a token only
## with a capture that shows the artefact.
const LOBBY_STAGE_EXCLUDE_TOKENS: Array[String] = []

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
## First-class Cleanout prep: non-empty id of an authored side-mission row
## (Mission.Guildhall.LootTheRoom). READY stages GameState.begin_cleanout():
## free_play stays false, the haul banks, the hosting contract is not credited.
var side_mission_id: String = ""

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
## `p_side_mission_id` non-empty opens a first-class Cleanout prep for that
## authored side-mission row with free_play left false.
func open_prep(p_map_id: String, p_difficulty: int, p_mode: String, p_contract_order: int, p_free_play: bool = false, p_side_mission_id: String = "") -> void:
	map_id = p_map_id
	difficulty = clampi(p_difficulty, 1, 3)
	mode = p_mode
	contract_order = p_contract_order
	free_play = p_free_play
	side_mission_id = "" if p_free_play else p_side_mission_id
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
	# W9-P3-C3: pad focus enters on the first authored card action.
	FocusNavScript.install_and_focus(self)


## Hide, restore mouse, emit closed and free.
func close_prep() -> void:
	FocusNavScript.release_if_inside(self)
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
	# live flag on the map-change reset and republishes this stash. A
	# first-class Cleanout stages begin_cleanout() instead: free_play stays
	# false and the side-mission row is forced by id.
	if free_play:
		GameState.begin_free_play(picked_id if picked_id != "" else GameState.FREE_PLAY_MISSION_ID)
	elif side_mission_id != "":
		GameState.active_mission_id = side_mission_id
		GameState.begin_cleanout(side_mission_id)
	else:
		GameState.end_free_play()
		GameState.end_cleanout()
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
	# QA hook (W9-P3): the focus-walk test builds the prep chrome without the
	# 2,107-mesh MissionLobby stage. Unset in every shipped/run path; only the
	# SubViewport stage is skipped, never a Control.
	if not OS.has_environment("TAT2_UI_NO_STAGE"):
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
	title.text = _countdown_text(int(COUNTDOWN_SECONDS))
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
	_mode_sub_lbl.text = UIStringsScript.st_template("ST_Screens", "Screen.MissionLobby.Mode", "Mode: {mode}", {"mode": _loc("Solo")})
	_mode_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_sub_lbl.add_theme_font_size_override("font_size", 14)
	_mode_sub_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	if sans != null:
		_mode_sub_lbl.add_theme_font_override("font", sans)
	_mode_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_hdr.add_child(_mode_sub_lbl)

	_diff_sub_lbl = Label.new()
	_diff_sub_lbl.text = UIStringsScript.st_template("ST_Screens", "Screen.MissionLobby.Difficulty", "Difficulty: {difficulty}", {"difficulty": _loc("Novice")})
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
	var loc_card: PanelContainer = _make_card(UIStringsScript.loc("Location").to_upper(), "", "") ## PORT COPY (no authored row)
	left.add_child(loc_card)
	_location_title_lbl = loc_card.get_meta("title_lbl") as Label
	_location_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_location_body = loc_card.get_meta("body_lbl") as Label
	_location_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_location_body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if italic != null:
		_location_body.add_theme_font_override("font", italic)
	var loc_vb: VBoxContainer = loc_card.get_meta("vbox") as VBoxContainer
	# LOCATION art box. The splash is 3138x1765 (1.78:1); the old 382x108 box was
	# a 3.54:1 STRETCH_KEEP_ASPECT_COVERED crop that kept only the middle ~50 %
	# of rows (C3-05 / L3-09: the "Gate Entrance" fence band instead of the gate
	# arch). An AspectRatioContainer pins the thumbnail to the source aspect at a
	# height the 720p card stack can afford, so COVERED becomes an exact fit.
	var art_box: AspectRatioContainer = AspectRatioContainer.new()
	art_box.name = "LocationArtBox"
	art_box.ratio = 1.7779773
	art_box.stretch_mode = AspectRatioContainer.STRETCH_HEIGHT_CONTROLS_WIDTH
	art_box.custom_minimum_size = Vector2(0, 152)
	art_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loc_vb.add_child(art_box)
	_location_art = TextureRect.new()
	_location_art.name = "LocationArt"
	_location_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_location_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_location_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_location_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_box.add_child(_location_art)
	loc_vb.move_child(art_box, 2)

	var mis_card: PanelContainer = _make_card(UIStringsScript.st_upper("ST_PostMatch", "PostMatch.Mission", "Mission"), "", "")
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

	var con_card: PanelContainer = _make_card(UIStringsScript.st_upper("ST_PostMatch", "PostMatch.Contract", "Contract"), "", "")
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
	_readiness_lbl.text = UIStringsScript.st_upper("ST_Screens", "Screen.Lobby.Ready", "Ready")
	_readiness_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_readiness_lbl.add_theme_font_size_override("font_size", 22)
	_readiness_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	if serif != null:
		_readiness_lbl.add_theme_font_override("font", serif)
	_readiness_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_box.add_child(_readiness_lbl)
	_thief_name_lbl = Label.new()
	_thief_name_lbl.text = GameState.player_display_name()
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
	# KF11 shows ONE stack of prompts (`[F] UNREADY` above `[ESC] BACK`), not a
	# hint line repeating both buttons. The label stays in the tree (the T05
	# contract reads its text) but is not drawn; the two action buttons below
	# are the single visible READY/BACK prompt pair.
	_controls_lbl.visible = false
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	bottom.add_child(btn_row)
	var ready_btn: Button = Button.new()
	ready_btn.text = ("[%s]  " + UIStringsScript.st_upper("ST_Screens", "Screen.Lobby.Ready", "Ready")) % InputGlyphs.text("interact")
	ready_btn.custom_minimum_size = Vector2(150, 42)
	ThemeScript.style_teal_button(ready_btn, true, 28)
	ready_btn.pressed.connect(_on_ready_action)
	btn_row.add_child(ready_btn)
	_ready_btn = ready_btn
	var back_btn: Button = Button.new()
	back_btn.text = ("[%s]  " + UIStringsScript.st_upper("ST_Screens", "Screen.Back", "Back")) % InputGlyphs.text("pause")
	back_btn.custom_minimum_size = Vector2(146, 42)
	ThemeScript.style_teal_button(back_btn, false, 28)
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
	# Authored BP_BorderStyle_Frame_Ornate 9-slice (T05). Replaces the procedural
	# filigree that C5-03 identified as the "corrupted ribbon" substitute.
	ThemeScript.add_authored_frame(panel, true, 0)
	var serif: Font = ThemeScript.font_display()
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
	title_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_BODY)
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
	# Construction-time fallback only. The preset apply below selects AGX for
	# this night preset and _apply_stage_grade re-applies it: the live tonemap has
	# always been AGX once midnight_clear_mission_lobby loads, so the pre-W9
	# "ACES" label on the stage was stale (W9 audit: W9_ENV tonemap=4).
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
	# W9-P1: one grade for the product — the authored night grade the gameplay
	# path applies (see the STAGE_* note above), not four stage constants.
	_apply_stage_grade(env, preset)

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
	# Authored CameraActor_0 roll (-14.780165 deg). The authored pitch is already
	# encoded in LOBBY_CAM_FWD.y, so look_at reproduces pitch/yaw and this adds
	# only the roll component.
	cam.rotate_object_local(Vector3.FORWARD, deg_to_rad(LOBBY_CAM_ROLL_DEG))
	_aim_stage_moon_and_key(env, cam, viewport, moonlight)
	_add_prep_skyline(stage_root, cam)
	# Composition after the level AND the skyline exist: the rule measures what
	# is actually spawned, and skips the expansion skyline by group.
	_apply_stage_composition(stage_root)

	var thief_anchor: Node3D = Node3D.new()
	thief_anchor.name = "MissionLobbyThiefAnchor"
	thief_anchor.position = LOBBY_THIEF_POS
	thief_anchor.rotation_degrees = Vector3(0.0, LOBBY_THIEF_YAW_DEG, 0.0)
	stage_root.add_child(thief_anchor)
	_add_thief(thief_anchor)
	_build_stage_character_lights(stage_root)


## W9-P1 stage grade: the authored gameplay night grade, values from
## `WeatherProfile.stage_grade_values` (T07's C1-09 hand-off). Nothing here is
## invented: exposure / ambient energy / glow intensity / background energy come
## from the preset, and the two glow shape values are the stage's own named
## constants. `background_energy_multiplier` is the one value the stage may
## refine (STAGE_SKY_ENERGY, see its comment).
## A missing preset is a broken data tree (the weather presets are an audit
## gate), so this leaves the environment exactly as constructed and says so in
## the log instead of inventing a grade for it.
func _apply_stage_grade(env: Environment, preset: Dictionary) -> void:
	if env == null:
		return
	if preset.is_empty():
		push_warning("TAT-2 prep stage: midnight_clear_mission_lobby preset missing; authored grade not applied")
		return
	var grade: Dictionary = WeatherProfile.stage_grade_values(preset)
	env.tonemap_mode = int(grade.get("tonemap_mode", Environment.TONE_MAPPER_AGX))
	env.tonemap_exposure = float(grade.get("tonemap_exposure", 1.15))
	# The authored ambient colour wins when the preset carries one (this preset's
	# sky.light_color is (0.443, 0.498, 1.0)); STAGE_AMBIENT_COLOR is only the
	# fallback for a preset that authors none.
	var amb: Variant = grade.get("ambient_light_color")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = amb if amb is Color else STAGE_AMBIENT_COLOR
	env.ambient_light_sky_contribution = 0.0
	env.ambient_light_energy = float(grade.get("ambient_light_energy", 0.35))
	env.glow_enabled = true
	env.glow_intensity = float(grade.get("glow_intensity", 0.12672))
	env.glow_bloom = STAGE_GLOW_BLOOM
	env.glow_hdr_threshold = STAGE_GLOW_HDR_THRESHOLD
	env.background_energy_multiplier = STAGE_SKY_ENERGY * float(grade.get("background_energy_multiplier", 1.0))
	print("TAT-2 prep grade: tonemap=%d exposure=%.3f ambient=%.3f glow=%.4f sky=%.3f" % [
		env.tonemap_mode, env.tonemap_exposure, env.ambient_light_energy,
		env.glow_intensity, env.background_energy_multiplier])


## W9-P1 stage composition rule (see LOBBY_STAGE_* above). Keeps every draw node
## whose world AABB comes within LOBBY_STAGE_KEEP_RADIUS_M of the authored thief
## slot — the slate ledge, the roof it stands on and the near props — and hides
## the rest of the lobby, which is what fills the sky sector in the authored
## frame. The expansion skyline is skipped by group (it is the far layer the rule
## exists to reveal, and `_grade_skyline_material` already excludes it from fog).
## One summary line is printed so a capture log proves which rule ran.
func _apply_stage_composition(stage_root: Node3D) -> void:
	var mode: String = OS.get_environment(LOBBY_STAGE_ENV).strip_edges().to_lower()
	if mode == "legacy":
		var all_n: int = 0
		for n: Node in _stage_draw_nodes(stage_root):
			if (n as GeometryInstance3D).is_visible_in_tree():
				all_n += 1
		print("TAT-2 prep stage: kept=%d hid=0 radius=%.1f legacy=1" % [all_n, LOBBY_STAGE_KEEP_RADIUS_M])
		return
	var kept: int = 0
	var hid: int = 0
	var excluded: int = 0
	for n: Node in _stage_draw_nodes(stage_root):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if gi.is_in_group(PREP_SKYLINE_GROUP):
			continue
		var token: String = _stage_exclusion_token(gi)
		if token != "":
			gi.visible = false
			excluded += 1
			continue
		var world: AABB = gi.global_transform * gi.get_aabb()
		var nearest: Vector3 = world.get_center().clamp(world.position, world.end)
		if LOBBY_THIEF_POS.distance_to(nearest) <= LOBBY_STAGE_KEEP_RADIUS_M:
			kept += 1
		else:
			gi.visible = false
			hid += 1
	print("TAT-2 prep stage: kept=%d hid=%d radius=%.1f" % [kept, hid, LOBBY_STAGE_KEEP_RADIUS_M])
	if excluded > 0:
		print("TAT-2 prep stage exclusions: %d node(s) matched %s" % [excluded, str(LOBBY_STAGE_EXCLUDE_TOKENS)])


## Every GeometryInstance3D the loader spawned under the stage, in tree order.
func _stage_draw_nodes(root_node: Node) -> Array[Node]:
	var out: Array[Node] = []
	if root_node == null:
		return out
	for child: Node in root_node.get_children():
		if child is GeometryInstance3D:
			out.append(child)
		out.append_array(_stage_draw_nodes(child))
	return out


## Named exclusion match for one draw node: the first LOBBY_STAGE_EXCLUDE_TOKENS
## entry contained in its `ue_mesh` meta or node name, else "".
func _stage_exclusion_token(gi: GeometryInstance3D) -> String:
	if gi == null or LOBBY_STAGE_EXCLUDE_TOKENS.is_empty():
		return ""
	var hay: String = (str(gi.get_meta("ue_mesh", "")) + " " + str(gi.name)).to_lower()
	for tok: String in LOBBY_STAGE_EXCLUDE_TOKENS:
		if tok != "" and hay.find(tok.to_lower()) >= 0:
			return tok
	return ""


## KF11 character rig: the authored weather preset gives the rooftop one cool
## directional key and nothing else, so the thief reads as a silhouette. These
## three local lights key/fill/rim the character only (short ranges), leaving
## the authored environment exposure and glow untouched.
func _build_stage_character_lights(stage_root: Node3D) -> void:
	var key_spot: SpotLight3D = SpotLight3D.new()
	key_spot.name = "MissionLobbyKey"
	key_spot.position = LOBBY_THIEF_POS + Vector3(2.4, 2.9, 2.4)
	key_spot.light_color = Color(0.80, 0.88, 1.0)
	key_spot.light_energy = STAGE_KEY_ENERGY
	key_spot.spot_range = 14.0
	key_spot.spot_angle = 30.0
	key_spot.spot_attenuation = 1.4
	key_spot.shadow_enabled = true
	key_spot.set_meta("stage_light_role", "key")
	stage_root.add_child(key_spot)
	key_spot.look_at(LOBBY_THIEF_POS + Vector3(0.0, 1.05, 0.0), Vector3.UP)

	var fill_omni: OmniLight3D = OmniLight3D.new()
	fill_omni.name = "MissionLobbyFill"
	fill_omni.position = LOBBY_THIEF_POS + Vector3(1.6, 1.4, 2.6)
	fill_omni.light_color = Color(1.0, 0.86, 0.72)
	fill_omni.light_energy = STAGE_FILL_ENERGY
	fill_omni.omni_range = 6.0
	fill_omni.omni_attenuation = 2.0
	fill_omni.shadow_enabled = false
	fill_omni.light_specular = 0.0
	fill_omni.set_meta("stage_light_role", "fill")
	stage_root.add_child(fill_omni)

	var rim_spot: SpotLight3D = SpotLight3D.new()
	rim_spot.name = "MissionLobbyRim"
	rim_spot.position = LOBBY_THIEF_POS + Vector3(-1.8, 2.3, -2.2)
	rim_spot.light_color = Color(0.55, 0.78, 1.0)
	rim_spot.light_energy = STAGE_RIM_ENERGY
	rim_spot.spot_range = 9.0
	rim_spot.spot_angle = 32.0
	rim_spot.spot_attenuation = 1.8
	rim_spot.shadow_enabled = false
	rim_spot.set_meta("stage_light_role", "rim")
	stage_root.add_child(rim_spot)
	rim_spot.look_at(LOBBY_THIEF_POS + Vector3(0.0, 1.3, 0.0), Vector3.UP)


## Places the KF11 sky disc at MOON_DISC_SCREEN and, independently, aims the
## cool directional key at the thief from KEY_SCREEN. The sky shader direction
## (disc) and the DirectionalLight travel direction (key) are deliberately
## different values; the earlier code forced both onto one screen point, so
## moving the moon also re-lit the character from the wall.
func _aim_stage_moon_and_key(env: Environment, cam: Camera3D, viewport: SubViewport, moonlight: DirectionalLight3D) -> void:
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
	var disc_dir: Vector3 = _screen_dir(fwd, right, up, tan_h, tan_v, MOON_DISC_SCREEN_X, MOON_DISC_SCREEN_Y)
	var key_dir: Vector3 = _screen_dir(fwd, right, up, tan_h, tan_v, KEY_SCREEN_X, KEY_SCREEN_Y)
	moonlight.light_energy = maxf(moonlight.light_energy, STAGE_MOON_ENERGY)
	moonlight.look_at_from_position(moonlight.global_position, moonlight.global_position - key_dir, Vector3.UP)
	moonlight.set_meta("stage_light_role", "moon_key")
	var sky_mat: Material = env.sky.sky_material if env.sky != null else null
	if sky_mat is ShaderMaterial:
		var sm: ShaderMaterial = sky_mat as ShaderMaterial
		sm.set_shader_parameter("moon_direction", disc_dir)
		sm.set_shader_parameter("moon_energy", STAGE_MOON_DISC_ENERGY)
		sm.set_shader_parameter("moon_halo_strength", 0.7)


## Normalised camera ray through a UI-space point (0..1, top-left origin).
func _screen_dir(fwd: Vector3, right: Vector3, up: Vector3, tan_h: float, tan_v: float, sx: float, sy: float) -> Vector3:
	return (fwd + right * ((sx * 2.0 - 1.0) * tan_h) + up * ((1.0 - sy * 2.0) * tan_v)).normalized()


## W7V KF11 backdrop. Reads the tracked expansion layout and instantiates the
## shipped Skybox distant-building meshes into the open sector behind the thief.
## Decorative only: no collision, no light registration, no shadows. Returns the
## number placed (0 when the file is missing or malformed: the stage still
## renders, it just keeps the authored sky).
func _add_prep_skyline(stage_root: Node3D, cam: Camera3D) -> int:
	var data: Dictionary = _load_prep_skyline()
	if data.is_empty() or stage_root == null or cam == null:
		return 0
	var loader: Node = _get_preview_mat_loader()
	if loader == null:
		return 0
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return 0
	fwd = fwd.normalized()
	var pieces: Array = data.get("pieces", []) as Array
	var placed: int = 0
	var missing: Array[String] = []
	for piece_v: Variant in pieces:
		if not (piece_v is Dictionary):
			continue
		var piece: Dictionary = piece_v as Dictionary
		var mesh_ue: String = str(piece.get("mesh", ""))
		if mesh_ue == "":
			continue
		var info: Dictionary = loader.call("_get_mesh_and_shape", mesh_ue) as Dictionary
		var mesh: Mesh = info.get("mesh") as Mesh
		if mesh == null:
			missing.append(mesh_ue)
			continue
		var az: float = deg_to_rad(float(piece.get("azimuth_deg", 0.0)))
		var dir: Vector3 = Vector3(
			fwd.x * cos(az) + fwd.z * sin(az), 0.0,
			-fwd.x * sin(az) + fwd.z * cos(az))
		var distance: float = maxf(float(piece.get("distance_m", 100.0)), 1.0)
		var pos: Vector3 = cam.global_position + dir * distance
		# Absolute world Y (the mesh AABB bottom). The layout note used to claim a
		# camera-relative Y while this line was always absolute; the data is now
		# authored against the absolute contract.
		pos.y = float(piece.get("base_y", 0.0))
		var mi := MeshInstance3D.new()
		var piece_id: String = str(piece.get("id", "piece"))
		mi.name = "PrepSkyline_%s" % piece_id
		mi.mesh = mesh
		var mat_ue: String = str(piece.get("material", ""))
		if mat_ue != "":
			var mat: Material = loader.call("get_material_for_ue", mat_ue) as Material
			var graded: Material = _grade_skyline_material(mat)
			if graded != null:
				for s: int in range(mesh.get_surface_count()):
					mi.set_surface_override_material(s, graded)
		mi.position = pos
		mi.rotation_degrees = Vector3(0.0, float(piece.get("yaw_deg", 0.0)), 0.0)
		var sc: float = maxf(float(piece.get("scale", 1.0)), 0.01)
		mi.scale = Vector3(sc, sc, sc)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("ue_mesh", mesh_ue)
		mi.set_meta("expansion", true)
		mi.set_meta("prep_skyline_layer", str(piece.get("layer", "")))
		mi.add_to_group(PREP_SKYLINE_GROUP)
		stage_root.add_child(mi)
		placed += 1
	if not missing.is_empty():
		print("TAT-2 prep skyline: %d piece(s) missing mesh: %s" % [missing.size(), ", ".join(missing)])
	print("TAT-2 prep skyline: placed %d/%d expansion pieces (group=%s)" % [
		placed, pieces.size(), PREP_SKYLINE_GROUP])
	return placed


## Night grade for the KF11 backdrop: builds a fresh opaque StandardMaterial3D
## from the authored Skybox material (never mutates the shared material DB) so
## the distant city reads as a silhouette under the prep stage's exposure. The
## authored albedo/emissive textures are preserved; blending is forced opaque
## because a translucent skybox-material pass washed the blocks to flat lilac.
func _grade_skyline_material(base: Material) -> Material:
	if base == null:
		return null
	var src: StandardMaterial3D = base as StandardMaterial3D
	if src == null:
		return base
	var out: StandardMaterial3D = StandardMaterial3D.new()
	out.albedo_texture = src.albedo_texture
	out.albedo_color = Color(0.11, 0.14, 0.21, 1.0)
	out.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	out.roughness = 1.0
	out.metallic = 0.0
	out.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The lobby preset carries 0.02/m height fog + volumetric clouds. At a
	# 300-500 m standoff the fog fully veils the backdrop into flat lilac, so the
	# distant city is excluded from the fog/ambient passes and graded as a
	# backlit silhouette (KF11's city is darker than the sky behind it).
	out.disable_fog = true
	out.disable_ambient_light = true
	# The authored distant-building emissive pass is a full-surface daylight
	# window mask; at the lobby's 2.6 exposure it blows the block to white. The
	# backdrop is graded as a silhouette instead (KF11's city is backlit).
	out.emission_enabled = false
	return out


## Reads + fail-closed validates the tracked expansion layout. A missing or
## drifted file yields {} so the stage silently keeps the authored sky.
func _load_prep_skyline() -> Dictionary:
	if not ParityGovernance.record_allowed(PREP_SKYLINE_PATH):
		# P0b parity-only: the KF11 backdrop is TAT-2 expansion content built
		# from shipped Skybox meshes. Exclude it; the stage keeps the authored
		# sky. Counted once per prep build; default off = no change.
		print("TAT-2 prep skyline: TAT2_PARITY_ONLY=1, expansion backdrop excluded (0 pieces)")
		return {}
	if not FileAccess.file_exists(PREP_SKYLINE_PATH):
		return {}
	var f: FileAccess = FileAccess.open(PREP_SKYLINE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed as Dictionary
	if str(d.get("schema", "")) != PREP_SKYLINE_SCHEMA:
		push_warning("TAT-2 prep skyline: schema %s != %s" % [str(d.get("schema", "")), PREP_SKYLINE_SCHEMA])
		return {}
	if not bool(d.get("expansion", false)):
		push_warning("TAT-2 prep skyline: layout is not marked expansion; ignored")
		return {}
	var pieces_v: Variant = d.get("pieces", [])
	if not (pieces_v is Array) or (pieces_v as Array).is_empty():
		return {}
	return d


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
			# KF11: the mission card names the authored heist, not the internal
			# mission id (`Mission.Guildhall.LootTheRoom`). The id still drives
			# selection by index and is kept as item metadata for tests/tools;
			# it is never shown.
			var item_idx: int = _mission_selector.item_count
			_mission_selector.add_item(str(m.get("title", "")))
			_mission_selector.set_item_metadata(item_idx, str(m.get("id", "")))


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
	var wanted_id: String = GameState.FREE_PLAY_MISSION_ID if free_play else side_mission_id
	if wanted_id != "":
		# Free play / first-class Cleanout select the Cleanout row by id, not
		# positionally: the authored thresholds/duration live on the row.
		for i: int in range(_mission_rows.size()):
			if str(_mission_rows[i].get("id", "")) == wanted_id:
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


## Authored location copy (ST_OldManor_map / ST_MapTool map rows). The old consts
## held the same English but bypassed Loc; the routes below keep the identical
## English and translate with the locale.
func _location_info() -> Array:
	if map_id == "old_manor":
		return [
			UIStringsScript.st_upper("ST_OldManor_map", "OldManor.MapName", "Elway Manor"),
			UIStringsScript.st_text("ST_OldManor_map", "OldManor.MapFlavorText", LOC_OLD_MANOR_DESC)]
	if map_id == "guildhall":
		return [
			UIStringsScript.st_upper("ST_MapTool", "Guildhall.MapName", "Constables' Guildhall"),
			UIStringsScript.st_text("ST_MapTool", "Guildhall.MapFlavorText", LOC_GUILDHALL_DESC)]
	if map_id == "jaspering_hall":
		return [UIStringsScript.loc("JASPERING HALL"), ## PORT COPY (no authored row)
			UIStringsScript.loc("A glittering jewelry house and private gallery in Kilcairn's merchant quarter, heavy with private security.")] ## PORT COPY (no authored row)
	return [map_id.to_upper(), UIStringsScript.loc("A shadowed mark in Kilcairn, ripe for the taking.")] ## PORT COPY (no authored row)


func _refresh_mission_card() -> void:
	if _mission_title_lbl == null or _mission_body == null:
		return
	if _selected_mission_idx >= 0 and _selected_mission_idx < _mission_rows.size():
		_apply_selected_mission_row()
		return
	var idx: int = abs(contract_order) % 3
	# Authored heist titles (ST_Screens MissionLobby quest titles).
	var titles: Array[String] = [
		UIStringsScript.st_text("ST_Screens", "Screen.MissionLobby.VaultQuestTitle", "Vault Heist"),
		UIStringsScript.st_text("ST_Screens", "Screen.MissionLobby.SetQuestTitle", "Item Collection Heist"),
		UIStringsScript.st_text("ST_Screens", "Screen.MissionLobby.GuildHall.LootTheRoomTitle", "Cleanout Heist"),
	]
	_mission_title_lbl.text = titles[idx]
	var minutes: int = _mission_minutes(idx, difficulty)
	var desc: String = _mission_description(idx, minutes)
	_mission_body.text = desc + "\n" + UIStringsScript.st_template("ST_Screens", "Screen.MissionLobby.TimeLimit", "Time Limit: {matchDurationInMinutes} minutes", {"matchDurationInMinutes": minutes})
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
		_mission_body.text = desc + "\n" + UIStringsScript.st_template("ST_Screens", "Screen.MissionLobby.TimeLimit", "Time Limit: {matchDurationInMinutes} minutes", {"matchDurationInMinutes": minutes})
	else:
		_mission_body.text = desc + "\n" + UIStringsScript.loc("Time Limit: Unlimited") ## PORT COPY (no authored row)
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
	# Authored MissionLobby description rows (ST_Screens), with the port's literal
	# as the last-resort fallback. The shipped rows use {MatchDurationInMinutes};
	# their OldManor keys are authored with a lower-case "manor".
	var mins: String = str(minutes)
	var key: String = ""
	var fallback: String = ""
	if map_id == "old_manor":
		if mission_idx == 0:
			key = "Screen.MissionLobby.Oldmanor.VaultQuestDescription"
			fallback = "The Elway family has a magical tome they keep under the utmost protection in a vault. Tonight you will have a {MatchDurationInMinutes} minute window when security is light. Find the book, steal it, and get out alive."
		elif mission_idx == 1:
			key = "Screen.MissionLobby.Oldmanor.SetQuestDescription"
			fallback = "The Claymur Urns have been held by the Elway family for centuries. The Guild will pay handsomely if you retrieve the full set. You have a {MatchDurationInMinutes} minute window to pilfer the Urns and make your escape."
		else:
			key = "Screen.MissionLobby.OldManor.LootTheRoomDescription"
			fallback = "Though both the Elway family and their estate are a shadow of what they once were, there are still ample treasures to be found. Get in, steal everything you can, and get out before anyone is the wiser."
	elif mission_idx == 0:
		key = "Screen.MissionLobby.VaultQuestDescription"
		fallback = "A rare bust called the Warburg Effigy is being held at the Guildhall for safekeeping. Tonight there is a {MatchDurationInMinutes} minute window when security will be light. Steal the bust, embarrass the police, and turn a tidy profit."
	elif mission_idx == 1:
		key = "Screen.MissionLobby.SetQuestDescription"
		fallback = "The precious gems needed to restore an artifact are hidden among the trinkets gathering dust in the Guildhall. You have a {MatchDurationInMinutes} minute window to pilfer the gems from under the very noses of the police."
	else:
		key = "Screen.MissionLobby.GuildHall.LootTheRoomDescription"
		fallback = "The Constables' Guildhall is full of confiscated treasures. Infiltrate the building and reacquire some of the riches they have just left lying around, then slip away before anyone notices."
	return UIStringsScript.st_text("ST_Screens", key, fallback).replace("{MatchDurationInMinutes}", mins)


func _refresh_contract_card() -> void:
	if _contract_title_lbl == null or _contract_body == null:
		return
	var info: Array = _contract_info()
	_contract_title_lbl.text = str(info[0])
	_contract_body.text = str(info[1])


func _contract_info() -> Array:
	if free_play:
		return [_loc(CONTRACT_INACTIVE), UIStringsScript.loc("Free play: clean out the location for a score. No contract progress is recorded.")] ## PORT COPY (no authored row)
	if side_mission_id != "":
		# First-class Cleanout: the card names the authored side mission and its
		# own description; the hosting contract order is only a map host.
		var side_v: Variant = GameData.missions_by_id.get(side_mission_id)
		var side_body: String = ""
		if side_v is Dictionary:
			side_body = str((side_v as Dictionary).get("description", ""))
		return [_loc(CONTRACT_INACTIVE), side_body]
	if contract_order <= 0:
		return [_loc(CONTRACT_INACTIVE), UIStringsScript.st_text("ST_Screens", "Screen.MissionLobby.ContractWrongMap",
			"Your active contract is not available for the currently selected map.")]
	var disp: Dictionary = GameData.get_contract_display(contract_order)
	var title_text: String = str(disp.get("title", ""))
	if title_text == "":
		return [_loc(CONTRACT_INACTIVE), UIStringsScript.st_text("ST_Screens", "Screen.MissionLobby.ContractWrongMap",
			"Your active contract is not available for the currently selected map.")]
	var quest_text: String = str(disp.get("quest_item", ""))
	var loc_text: String = str(disp.get("location", ""))
	# PORT COPY (no authored row): the port's own contract summary sentence.
	var body_text: String = UIStringsScript.loc("Active contract: %s") % title_text
	if quest_text != "":
		body_text += "\n" + UIStringsScript.loc("Target: %s") % quest_text
	if loc_text != "":
		body_text += "\n%s" % loc_text
	return [title_text, body_text]


func _refresh_controls() -> void:
	if _mode_sub_lbl != null:
		var mode_tmpl: String = UIStringsScript.st_text("ST_Screens", "Screen.MissionLobby.Mode", "Mode: {mode}")
		_mode_sub_lbl.text = mode_tmpl.replace("{mode}", mode)
	if _diff_sub_lbl != null:
		var diff_tmpl: String = UIStringsScript.st_text("ST_Screens", "Screen.MissionLobby.Difficulty", "Difficulty: {difficulty}")
		_diff_sub_lbl.text = diff_tmpl.replace("{difficulty}", _difficulty_label())
	_refresh_countdown()
	if _thief_name_lbl != null:
		_thief_name_lbl.text = _thief_label()
	_refresh_ready_controls()


## KF11: the nameplate above the thief is the player's readiness STATE and keeps
## reading READY; only the [F] button and the controls hint flip to UNREADY while
## a countdown runs. KF11 at 01:00 shows label READY + button [F] UNREADY + hint
## [F] UNREADY / [ESC] BACK. (Before T05 all three shared one word, so the
## nameplate read UNREADY during the countdown.)
func _refresh_ready_controls() -> void:
	if _readiness_lbl != null:
		_readiness_lbl.text = UIStringsScript.st_upper("ST_Screens", "Screen.Lobby.Ready", "Ready")
	var action: String = UIStringsScript.st_text("ST_Screens", "Screen.Lobby.Unready", "Unready") if _countdown_running \
		else UIStringsScript.st_text("ST_Screens", "Screen.Lobby.Ready", "Ready")
	var upper: String = action.to_upper()
	if _ready_btn != null:
		_ready_btn.text = ("[%s]  " + upper) % InputGlyphs.text("interact")
	if _controls_lbl != null:
		_controls_lbl.text = ("[%s] %s  ·  [%s] " + UIStringsScript.st_upper("ST_Screens", "Screen.Back", "Back")) % [
			InputGlyphs.text("interact"), upper, InputGlyphs.text("pause")]


## Header line: the authored MissionLobby countdown template with its number
## substituted ("MISSION STARTING IN 6..." down to "1..."). At rest it shows
## the full countdown so the player knows what READY starts.
func _refresh_countdown() -> void:
	if _countdown_lbl == null:
		return
	var shown: int = _countdown_last_int if _countdown_running else int(COUNTDOWN_SECONDS)
	_countdown_lbl.text = _countdown_text(shown)


## One countdown render shared by the build-time initial label and the ticker, so
## the header never shows a hardcoded digit that differs from COUNTDOWN_SECONDS.
func _countdown_text(seconds: int) -> String:
	var tmpl: String = UIStringsScript.st_text("ST_Screens", "Screen.MissionLobby.Countdown", "Mission Starting in <Num>{number}</>...")
	tmpl = tmpl.replace("<Num>", "").replace("</>", "")
	return tmpl.replace("{number}", str(seconds)).to_upper()


## Every prep label that has an authored StringTable row goes through
## UIStrings (T05 l10n): authored English -> Loc locale translation -> literal.
func _loc(source: String) -> String:
	return UIStringsScript.t(source)


func _loc_fmt(source: String, values: Dictionary) -> String:
	var out: String = _loc(source)
	for key: Variant in values.keys():
		out = out.replace("{%s}" % str(key), str(values[key]))
	return out


## Nameplate: the explicit player handle, else the authored thief title. The
## 3D thief and its card always match because both read GameState.
func _thief_label() -> String:
	return GameState.player_display_name()


func _difficulty_label() -> String:
	if difficulty == 1:
		return _loc("Novice")
	if difficulty == 2:
		return _loc("Thief")
	return _loc("Master Thief")
