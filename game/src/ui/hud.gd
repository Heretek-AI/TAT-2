extends CanvasLayer
## Authentic UE5-parity in-game HUD:
## - Top-left Health Bar (T_healthBar_straight_* + authored health_block_percentages),
##   loot counter (£), and multi-part Mission Objectives.
## - Top-center slim glowing blue Compass (T_compass_lines + PoI diamonds).
## - Top-right Portrait + T_portrait_levelFrame numeric badge.
## - Bottom-center light-reactive shaded Stealth Ball (T_stealthball_frame)
##   with a directional warm light sector (UI3) + bilateral red SoundWaves
##   driven by the player's own NoiseBus output (UI5).
## - Bottom-left octagonal Tool Hotbar (T_Ability_Border + masked T_Ability_Background +
##   real tool icons + ∞ glyph) + [TAB] MAP / [MMB] PING MENU hints.
## - Bottom-right contextual [LMB]/[RMB] tool & Den action hints.
## - Dynamic tool reticles + clockwise Zipwire crank progress ring.
## - World-projected Guard Pips (T_GuardPip_SpriteSheet) & Offscreen Threat Arcs.
## - Circular/arc Lockpicking Timing Minigame (DA_LockpickMinigameVariations).
## - [TAB] Tactical Map overlay, [MMB] Ping radial + HUD/compass PoI markers.
## - Mission Start Letter (T_Paper01 + [SPACE] CONTINUE) & Den Look-At Card.
## - Clean edge-vignette Thief Vision presentation (no flat cyan screen wash).

const SettingsUIScript := preload("res://src/ui/settings_ui.gd")
const ThemeScript := preload("res://src/ui/art_nouveau_theme.gd")
const FocusNavScript := preload("res://src/ui/focus_nav.gd")
const MapBoundariesScript := preload("res://src/ui/map_boundaries.gd")
const UIToastScript := preload("res://src/ui/ui_toast.gd")
const UIStringsScript := preload("res://src/ui/ui_strings.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")

## W9-P3: legacy "[KEY]" tokens in the HUD's own prompt lines -> port action ids,
## so `InputGlyphs.format_legend()` prints the live bound key on the active device.
const LOCKPICK_LEGEND_ACTIONS: Dictionary = {"SPACE": "jump", "LMB": "primary_action", "ESC": "pause"}
const MAP_LEGEND_ACTIONS: Dictionary = {"LMB": "primary_action", "TAB": "map_toggle", "ESC": "pause"}

const VERSION_STRING: String = "v1.5.148559"
## W5D: one heading at the centre tick, matching the reference HUD. The old
## 580 px scrolling cardinal ribbon is gone (compass_lbl still owns the public
## contract and the E2E wrap-around mapping).
const COMPASS_DIRECTIONS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const INTERACTABLES_JSON_PATH: String = "res://data/generated/gameplay/interactables.json"
## T_healthBar_straight_frame.png / _RGB.png / _splatter_red.png are all authored
## at 1024x256 (4:1). The frame and the authored shaped fill must share one rect
## at that aspect or the fill's corners cut across the frame's slanted border.
const HP_BAR_MAX_W: float = 256.0
const HP_BAR_H: float = 64.0
## The authored red fill is the health bar; the splatter asset is a DAMAGE
## overlay, not a permanent decoration (C3-08 / ADJUDICATIONS C-4).
const HP_SPLATTER_THRESHOLD: float = 0.5
const STAM_BAR_MAX_W: float = 176.0
const DEN_SCENE_PATH: String = "res://scenes/mission.tscn"
const LootInventoryScript := preload("res://src/interact/loot_inventory.gd")

const TOOL_ICON_MAP: Dictionary = {
	"zipwire": "res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_Zipwire_Wide.png",
	"smoke_bomb": "res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_Bomb_Smoke_Wide.png",
	"slithersap": "res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_SlimeBomb_Wide.png",
	"fairy": "res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_PickpocketFairy_Wide.png",
	"vistara_diamond": "res://assets/ue/Raw/Art/UI/Icons/Rewards/Gear/T_VistaraDiamond_Wide.png",
	"blackjack": "res://assets/ue/Raw/Art/UI/Icons/T_Icon_Abilities.png",
}

const ABILITY_BG_MASK_SHADER: String = """
shader_type canvas_item;
uniform vec4 tint_color : source_color = vec4(0.05, 0.08, 0.16, 0.74);
void fragment() {
	float m = texture(TEXTURE, UV).r;
	COLOR = vec4(tint_color.rgb, m * tint_color.a);
}
"""

const STEALTH_ORB_SHADER: String = """
shader_type canvas_item;
uniform float visibility : hint_range(0.0, 1.0) = 0.2;
// UI3: warm sector pointing at the strongest scene light. sector_angle is in
// canvas space (+Y down), mirroring the HUD's screen-space mapping.
uniform float sector_angle = 0.0;
uniform float sector_strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// UI3/W5D: the Light Gem is a glazed sphere (reference art), not a cut
	// diamond. length(p) gives the circular mask; the normals below already
	// assume the unit sphere.
	float d = length(p);
	float mask = 1.0 - smoothstep(0.90, 1.0, d);
	float z = sqrt(max(0.0, 1.0 - dot(p, p)));
	vec3 n = normalize(vec3(p.x, p.y, z));
	vec3 light_dir = normalize(vec3(-0.38, -0.45, 0.80));
	float ndl = max(0.0, dot(n, light_dir));
	float spec = pow(max(0.0, dot(n, normalize(light_dir + vec3(0.0, 0.0, 1.0)))), 18.0);
	float fresnel = pow(1.0 - clamp(z, 0.0, 1.0), 2.2);
	vec3 dark_base = vec3(0.055, 0.068, 0.24);
	vec3 dark_hi = vec3(0.70, 0.76, 0.96);
	vec3 lit_base = vec3(0.68, 0.62, 0.42);
	vec3 lit_hi = vec3(0.99, 0.96, 0.82);
	vec3 base_col = mix(dark_base, lit_base, visibility);
	vec3 hi_col = mix(dark_hi, lit_hi, visibility);
	vec3 shaded = base_col * (0.42 + 0.68 * ndl) + hi_col * (0.28 * ndl * visibility + 0.82 * spec);
	shaded += mix(vec3(0.12, 0.18, 0.46), vec3(0.96, 0.90, 0.62), visibility) * fresnel * 0.35;
	float ang = atan(p.y, p.x);
	float d_ang = abs(mod(ang - sector_angle + PI, 6.28318530718) - PI);
	float wedge = 1.0 - smoothstep(0.32, 0.88, d_ang);
	float rim = smoothstep(0.42, 0.90, d);
	shaded += mix(vec3(0.16, 0.22, 0.58), vec3(1.0, 0.96, 0.78), visibility) * pow(rim, 2.4) * 0.55;
	shaded += vec3(1.0, 0.70, 0.30) * wedge * sector_strength * (0.30 + 0.55 * rim);
	COLOR = vec4(shaded, mask * 0.98);
}
"""

const THIEF_VISION_VIGNETTE_SHADER: String = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p * vec2(0.88, 1.0));
	float edge = smoothstep(0.68, 1.32, d);
	vec3 col = mix(vec3(0.02, 0.06, 0.14), vec3(0.14, 0.42, 0.56), smoothstep(0.98, 1.32, d));
	COLOR = vec4(col, edge * 0.28 * strength);
}
"""

## KF13 briefing backdrop: the live safe-room view, blurred and darkened, not a
## flat dim. The letter is opened after the gameplay HUD is hidden, so this
## samples only the 3D frame. CanvasItem screen textures cannot use mipmaps
## reliably, so the blur is a 13-tap linear kernel.
const BRIEFING_BLUR_SHADER: String = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float blur_px : hint_range(0.5, 8.0) = 3.0;
uniform vec4 tint : source_color = vec4(0.50, 0.52, 0.60, 1.0);
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * blur_px;
	vec3 c = texture(screen_tex, SCREEN_UV).rgb * 0.20;
	c += (texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb
		+ texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb) * 0.10;
	c += (texture(screen_tex, SCREEN_UV + px).rgb
		+ texture(screen_tex, SCREEN_UV - px).rgb
		+ texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y)).rgb
		+ texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y)).rgb) * 0.05;
	c += (texture(screen_tex, SCREEN_UV + vec2(px.x * 2.0, 0.0)).rgb
		+ texture(screen_tex, SCREEN_UV - vec2(px.x * 2.0, 0.0)).rgb
		+ texture(screen_tex, SCREEN_UV + vec2(0.0, px.y * 2.0)).rgb
		+ texture(screen_tex, SCREEN_UV - vec2(0.0, px.y * 2.0)).rgb) * 0.05;
	COLOR = vec4(c * tint.rgb, 1.0);
}
"""

## KF13 parchment sheet at 1280x720 design resolution: the 1920x1080 reference
## sheet is 824x666 (crop 107,69 813x882 in the 1024^2 T_Paper01 source).
## The text column is 412 px at 19 px SpecialElite, which reproduces the
## reference's authored 11-line wrap exactly (measured by TextServer; see
## suite W6U1).
##
## The authored T_Paper01 sheet carries vertical crease shadows that read as
## grime over the typewriter text at the KF13 824x666 scale. Lift them toward
## the paper tone while preserving the torn-edge alpha (a plain modulate would
## brighten the shadows proportionally and a ColorRect would square the edge).
const BRIEFING_PAPER_LIFT_SHADER: String = """
shader_type canvas_item;
uniform float lift : hint_range(0.0, 0.5) = 0.26;
uniform vec4 paper_color : source_color = vec4(0.93, 0.88, 0.80, 1.0);
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(mix(t.rgb, paper_color.rgb, lift), t.a);
}
"""

const BRIEFING_PAPER_SIZE: Vector2 = Vector2(549.0, 444.0)
const BRIEFING_PAPER_SOURCE_CROP: Rect2 = Rect2(107.0, 69.0, 813.0, 882.0)
const BRIEFING_TEXT_ORIGIN: Vector2 = Vector2(68.0, 52.0)
const BRIEFING_TEXT_WIDTH: float = 412.0
const BRIEFING_FONT_SIZE: int = 19
const BRIEFING_SCROLLBAR_X: float = 524.0
const BRIEFING_SCROLLBAR_TOP: float = 60.0
const BRIEFING_SCROLLBAR_HEIGHT: float = 300.0

# Preserved public properties (checked by game/tests/run_tests.gd and callers).
var obj_lbl: Label
var compass_lbl: Label
var ribbon_clip: Control
var ribbon_lbl: Label
var interact_lbl: Label
var _prompt_secondary_lbl: Label
var stealth_gem: TextureRect
## T05: the authored shaped fill (T_healthBar_straight_RGB.png) is a TextureRect;
## its size.x still scales with health (E2E T1-13-E) and it shares the frame rect.
var hp_fill: TextureRect
var stam_fill: ColorRect
var hotbar_lbl: Label
var slot_count_lbls: Array[Label] = []
var disguise_vignette: TextureRect
var thief_vision_overlay: ColorRect
var clue_toast_lbl: Label
var downed_lbl: Label
## W7E two-phase HUD: gold door banner shown only during the endgame window.
var door_lbl: Label
var lockpick_bar: ProgressBar
var pause_center: CenterContainer
var pause_panel: PanelContainer
var _pause_panel_for_focus: Control = null
var result_panel: PanelContainer
var result_lbl: Label
var _result_lines: VBoxContainer
var _result_continue_btn: Button
var contract_data: Dictionary = {}
var current_prompt: String = ""
var fps_overlay: Label
var fps_overlay_enabled: bool = false

# Internal HUD controls & state
var _root: Control
var _sans: Font
var _italic: Font
var _serif: Font
var _typewriter: Font
var _fps_refresh: float = 0.0
## KF30 footer seed: the deterministic run seed published by GameState, so the
## pause footer and the mission share one value (no wall-clock randomness).
var _run_seed: int = 0

var _pause_root: Control
## KF30: the pause screen shows the modal over a darkened, blurred world with
## NO live HUD. Visibility is snapshotted on pause and restored on resume.
var _pause_visibility: Dictionary = {}
var _pause_hud_hidden: bool = false
## One-shot guard for the pause -> Den abandonment payout.
var _payout_applied: bool = false
## NPC conversation modal (Spider personal chain). The dialogue node registers
## itself here so HUD input, the pause key and the interaction prompt can yield.
var _npc_dialogue: Node = null
## Frame the dialogue closed itself (Escape/interact consumed in its _input).
## The pause key is polled in _process after _input, so this keeps the same
## Escape press from also pausing the mission.
var _npc_dialogue_closed_frame: int = -1
var _prompt_keycap: PanelContainer
var _prompt_keycap_lbl: Label
var _thief_name_lbl: Label
var _level_badge_lbl: Label

# Top-left Health / Loot / Objectives
var _hp_container: Control
var _hp_clip: Control
var _hp_splatter: TextureRect
var _hp_ticks_box: Control
var _hp_block_cache: Array = []
var _stam_bg: ColorRect
var _loot_lbl: Label
## C-4 experiment: one HUD instance per mission; the recording showed the hp
## frame's right cap and some labels drawn twice with only one HudScript, so the
## build path now accounts for itself (printed once on _ready, exposed via
## debug_hud_counts() and asserted by game/tests/test_t05_ui_contract.gd).
static var _hud_build_serial: int = 0
var hud_build_id: int = 0
var _hp_frame_builds: int = 0

# Bottom-center Stealth Ball & SoundWaves
var _stealth_holder: Control
var _stealth_orb_mat: ShaderMaterial
var _soundwaves_draw: SoundWavesDraw
var _soundwave_energy: float = 0.0
var _soundwave_phase: float = 0.0
var _vis_smooth: float = 0.2

# Bottom-left Octagonal Tool Hotbar
var _hotbar_anchor: Control
var _slot_icons: Array[TextureRect] = []
var _slot_borders: Array[TextureRect] = []
var _slot_bgs: Array[TextureRect] = []
var _slot_key_lbls: Array[Label] = []
var _slot_last_ids: Array[String] = ["", "", "", ""]

# Bottom-left stolen-key row (above the tool hotbar)
var _keys_anchor: Control
var _keys_lbl: Label
var _keys_sig: String = ""
var _keys_shown: bool = false

# Bottom-right Action Hints
var _action_hints_box: VBoxContainer
var _den_bottom_hints: Array = []
var _last_hints_sig: String = ""

# Dynamic Center Reticle
var _reticle_draw: ReticleDraw
var _crank_prompt_lbl: Label

# Compass PoIs
var _compass_poi_layer: Control
var _compass_poi_pool: Array[TextureRect] = []
var _poi_gold_tex: AtlasTexture
var _poi_teal_tex: AtlasTexture
# Compass verticality arrows (authored T_compass_verticality_arrow): shown for
# a PoI above/below the player's eye plane, flipped for below.
var _compass_verticality_tex: Texture2D
var _compass_verticality_pool: Array[TextureRect] = []
const COMPASS_VERTICALITY_THRESHOLD_M: float = 0.75

# Guard Pips & Offscreen Threat Arcs
var _alert_layer: Control
var _pip_pool: Array[TextureRect] = []
var _offscreen_pool: Array[TextureRect] = []
var _pip_tex_warn: AtlasTexture
var _pip_tex_susp: AtlasTexture
var _pip_tex_alert: AtlasTexture
var _pip_tex_combat: AtlasTexture
var _offscreen_tex: Texture2D

# Lockpicking Timing Minigame (DA_LockpickMinigameVariations)
var _lockpick_db: Dictionary = {}
var _lockpick_root: Control
var _lockpick_dial: LockpickDialDraw
var _lockpick_title_lbl: Label
var _lockpick_track_lbl: Label
var _lockpick_status_lbl: Label
var _lockpick_active: bool = false
var _lockpick_level: int = 1
var _lockpick_tracks: Array = []
var _lockpick_track_idx: int = 0
var _lockpick_cursor_t: float = 0.0
var _lockpick_broken_flags: Array[bool] = []
var _lockpick_jam_timer: float = 0.0
var _lockpick_callback: Callable = Callable()
var _lockpick_prev_mouse: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
## W9-P2 C1: frame stamp for the ESC the lockpick already consumed in
## `_input`. The same frame's `_process` still sees the `pause` action as
## "just pressed" and used to open the pause menu over the cancelled dialog.
## This is the same guard pattern as `_npc_dialogue_closed_frame`; the process
## frame counter is monotonic, so a stale stamp can never match a later frame
## and no explicit reset is needed.
var _pause_consumed_frame: int = -1

# [TAB] Tactical Map Overlay
var _map_root: Control
var _map_panel: Control = null
var _boundary_rows: Array[Dictionary] = []
var _boundary_source: String = "fallback"
var _toast: Control = null
var _run_xp_start: int = -1
var _result_xp_btn: Button = null
var _hint_map_key_lbl: Label = null
var _hint_ping_key_lbl: Label = null
var _pause_esc_key_lbl: Label = null
var _map_foot_lbl: Label = null
var _carried_used_seen: int = -1
var _thief_vision_was_on: bool = false
var _last_won: bool = false
var _last_score: int = 0
var _last_info: Dictionary = {}
var _map_title_lbl: Label
var _map_draw: TacticalMapDraw
var _map_open: bool = false
var _map_prev_mouse: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

# [MMB] Ping Radial & Active World Pings
var _ping_root: Control
var _ping_radial: PingRadialDraw
var _ping_open: bool = false
var _ping_selected: int = 0
var _ping_prev_mouse: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _active_pings: Array[Dictionary] = []
var _ping_marker_layer: Control
var _ping_marker_pool: Array[Control] = []

# Mission Start Letter (T_Paper01 + [SPACE] CONTINUE)
var _letter_root: Control
var _letter_title_lbl: Label
var _letter_body_lbl: Label
var _letter_open: bool = false
var _letter_prev_mouse: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _letter_blur_backdrop: ColorRect
var _letter_paper: TextureRect
var _letter_scrollbar: Panel
var _letter_hud_visibility: Dictionary = {}

# Thieves' Den Look-At Card
var _den_card_panel: PanelContainer
var _den_card_title_lbl: Label
var _den_card_lines_box: VBoxContainer


# =============================================================================
# Inner Custom-Draw Controls
# =============================================================================

class SoundWavesDraw extends Control:
	var energy: float = 0.0
	var phase: float = 0.0

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var base_r: float = 46.0
		# Subtle resting brackets at very low opacity.
		var rest_alpha: float = lerpf(0.22, 0.05, clampf(energy * 2.0, 0.0, 1.0))
		if rest_alpha > 0.02:
			var rest_col: Color = Color(0.56, 0.66, 0.90, rest_alpha)
			draw_arc(center, base_r + 6.0, deg_to_rad(-32.0), deg_to_rad(32.0), 18, rest_col, 1.6, true)
			draw_arc(center, base_r + 6.0, deg_to_rad(148.0), deg_to_rad(212.0), 18, rest_col, 1.6, true)
		if energy <= 0.03:
			return
		var waves: int = 1 + int(clampf(energy * 2.5, 0.0, 2.0))
		for i: int in range(waves):
			var fi: float = float(i)
			var pulse: float = fposmod(phase + fi * 0.34, 1.0)
			var radius: float = base_r + 6.0 + fi * 10.0 + pulse * 10.0
			var span_deg: float = lerpf(26.0, 44.0, energy) - fi * 4.0
			var a: float = clampf(energy * (1.0 - fi * 0.24) * (1.0 - pulse * 0.45), 0.0, 0.92)
			var col: Color = Color(0.96, 0.18, 0.16, a)
			var width: float = lerpf(3.4, 2.0, fi / 3.0)
			draw_arc(center, radius, deg_to_rad(-span_deg), deg_to_rad(span_deg), 22, col, width, true)
			draw_arc(center, radius, deg_to_rad(180.0 - span_deg), deg_to_rad(180.0 + span_deg), 22, col, width, true)


class ReticleDraw extends Control:
	var mode: String = "blackjack"
	var target_valid: bool = false
	var crank_progress: float = 0.0
	var crank_active: bool = false
	var hold_progress: float = 0.0

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		# Center dot always visible.
		draw_circle(c, 2.2, Color(0.96, 0.98, 1.0, 0.92))
		# KF26: active circular hold-progress arc for [HOLD] TAKEDOWN.
		if hold_progress > 0.001:
			var r_hold: float = 22.0
			draw_arc(c, r_hold, 0.0, TAU, 40, Color(0.86, 0.92, 1.0, 0.22), 2.0, true)
			draw_arc(c, r_hold, -PI * 0.5, -PI * 0.5 + TAU * clampf(hold_progress, 0.0, 1.0), 40, Color(1.0, 0.94, 0.72, 0.95), 3.0, true)
		if mode == "zipwire":
			if crank_active or crank_progress > 0.001:
				var r_crank: float = 28.0
				draw_arc(c, r_crank, 0.0, TAU, 48, Color(0.45, 0.58, 0.85, 0.35), 2.0, true)
				for k: int in range(6):
					var ang: float = deg_to_rad(float(k) * 60.0 - 90.0)
					var dir: Vector2 = Vector2(cos(ang), sin(ang))
					draw_line(c + dir * (r_crank - 5.0), c + dir * (r_crank + 5.0), Color(0.75, 0.90, 1.0, 0.85), 1.6, true)
				var prog: float = clampf(crank_progress, 0.0, 1.0)
				if prog > 0.005:
					draw_arc(c, r_crank, -PI * 0.5, -PI * 0.5 + TAU * prog, 48, Color(0.38, 0.86, 1.0, 0.96), 3.6, true)
			else:
				var col: Color = Color(0.45, 0.94, 1.0, 0.95) if target_valid else Color(0.72, 0.82, 0.96, 0.42)
				var r_zw: float = 16.0 if target_valid else 13.0
				draw_arc(c, r_zw, 0.0, TAU, 36, Color(col.r, col.g, col.b, col.a * 0.35), 1.2, true)
				for k: int in range(4):
					var ang: float = deg_to_rad(45.0 + float(k) * 90.0)
					var dir: Vector2 = Vector2(cos(ang), sin(ang))
					draw_line(c + dir * (r_zw - 5.0), c + dir * (r_zw + 4.0), col, 2.0, true)
		elif mode == "smoke_bomb" or mode == "slithersap":
			var col2: Color = Color(0.95, 0.92, 0.65, 0.85) if target_valid else Color(0.70, 0.76, 0.88, 0.32)
			draw_arc(c, 13.0, deg_to_rad(-155.0), deg_to_rad(-25.0), 18, col2, 1.6, true)
			draw_arc(c, 13.0, deg_to_rad(25.0), deg_to_rad(155.0), 18, col2, 1.6, true)
		elif mode == "fairy":
			var col3: Color = Color(0.45, 0.96, 0.90, 0.92) if target_valid else Color(0.65, 0.80, 0.92, 0.38)
			var d: float = 12.0 if target_valid else 9.0
			var pts: PackedVector2Array = PackedVector2Array([
				c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0), c + Vector2(0, -d)
			])
			draw_polyline(pts, col3, 1.6, true)


class LockpickDialDraw extends Control:
	var track_data: Dictionary = {}
	var cursor_t: float = 0.0
	var broken_flags: Array[bool] = []
	var jam_flash: float = 0.0
	var track_idx: int = 0
	var track_total: int = 1

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var outer_r: float = minf(size.x, size.y) * 0.43
		var track_r: float = outer_r - 16.0
		# Subtle outer Art Nouveau ring.
		draw_arc(c, outer_r, 0.0, TAU, 64, Color(0.28, 0.72, 0.74, 0.55), 2.0, true)
		draw_arc(c, track_r - 16.0, 0.0, TAU, 48, Color(0.24, 0.52, 0.58, 0.35), 1.4, true)
		# Progress pips for multi-track locks.
		for ti: int in range(track_total):
			var pip_x: float = c.x + (float(ti) - float(track_total - 1) * 0.5) * 18.0
			var pip_col: Color = Color(0.35, 0.95, 0.75, 0.95) if ti < track_idx else (Color(0.55, 0.94, 0.96, 1.0) if ti == track_idx else Color(0.30, 0.40, 0.48, 0.65))
			draw_circle(Vector2(pip_x, c.y + outer_r - 4.0), 4.5, pip_col)

		var dur: float = maxf(0.2, float(track_data.get("duration_s", 1.8)))
		var arc_deg: float = clampf(float(track_data.get("arc_angle_deg", 120.0)), 40.0, 340.0)
		var start_ang: float = -PI * 0.5 - deg_to_rad(arc_deg * 0.5)
		var end_ang: float = start_ang + deg_to_rad(arc_deg)

		# Base jammable track arc.
		var base_col: Color = Color(0.92, 0.24, 0.22, 0.90) if jam_flash > 0.0 else Color(0.55, 0.26, 0.24, 0.75)
		draw_arc(c, track_r, start_ang, end_ang, 56, base_col, 14.0, true)

		# Breakable sweet-spot sections from DA_LockpickMinigameVariations.
		var secs_v: Variant = track_data.get("defined_sections", [])
		if secs_v is Array:
			var secs: Array = secs_v as Array
			for i: int in range(secs.size()):
				var sv: Variant = secs[i]
				if not (sv is Dictionary):
					continue
				var sd: Dictionary = sv as Dictionary
				var s0: float = clampf(float(sd.get("start_s", 0.0)) / dur, 0.0, 1.0)
				var s1: float = clampf(float(sd.get("end_s", 0.2)) / dur, 0.0, 1.0)
				var a0: float = lerpf(start_ang, end_ang, s0)
				var a1: float = lerpf(start_ang, end_ang, s1)
				var is_broken: bool = i < broken_flags.size() and broken_flags[i]
				var sec_col: Color = Color(0.32, 0.92, 0.56, 0.95) if is_broken else Color(0.45, 0.94, 0.92, 0.98)
				draw_arc(c, track_r, a0, a1, 24, sec_col, 16.0, true)

		# Track end caps.
		var cap0: Vector2 = c + Vector2(cos(start_ang), sin(start_ang)) * track_r
		var cap1: Vector2 = c + Vector2(cos(end_ang), sin(end_ang)) * track_r
		draw_circle(cap0, 5.0, Color(0.75, 0.92, 0.95, 0.85))
		draw_circle(cap1, 5.0, Color(0.75, 0.92, 0.95, 0.85))

		# Sweeping lockpick cursor needle.
		var frac: float = clampf(cursor_t / dur, 0.0, 1.0)
		var cur_ang: float = lerpf(start_ang, end_ang, frac)
		var dir: Vector2 = Vector2(cos(cur_ang), sin(cur_ang))
		draw_line(c + dir * (track_r - 22.0), c + dir * (track_r + 18.0), Color(0.98, 0.88, 0.48, 1.0), 3.6, true)
		draw_circle(c + dir * track_r, 6.0, Color(1.0, 0.98, 0.85, 1.0))


class TacticalMapDraw extends Control:
	signal map_clicked(world_pos: Vector3)

	var player_pos: Vector3 = Vector3.ZERO
	var player_yaw: float = 0.0
	var guard_points: Array[Dictionary] = []
	var loot_points: Array[Dictionary] = []
	var objective_points: Array[Dictionary] = []
	var ping_points: Array[Dictionary] = []
	var _world_center: Vector2 = Vector2.ZERO
	var _world_span: float = 64.0
	## Authored TATWorldMapBoundary rows for the active map (empty until the
	## producer emits `map_boundaries`; see MapBoundariesScript).
	var boundaries: Array[Dictionary] = []
	var active_boundary: Dictionary = {}
	var boundary_source: String = "fallback"

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				var wpos: Vector3 = _screen_to_world(mb.position)
				map_clicked.emit(wpos)
				accept_event()

	func _compute_bounds() -> void:
		# Authored map extent: the Primary boundary is the map capture volume
		# (Guildhall _0 is a 235 m wide, 2 m tall capture slab), so its XZ box is the authored frame.
		if not boundaries.is_empty():
			var prim: Dictionary = MapBoundariesScript.primary_for(boundaries)
			if not prim.is_empty():
				var pc: Vector3 = prim.get("pos", Vector3.ZERO) as Vector3
				var ps: Vector3 = prim.get("size", Vector3(64.0, 1.0, 64.0)) as Vector3
				_world_center = Vector2(pc.x, pc.z)
				_world_span = clampf(maxf(ps.x, ps.z), 36.0, 400.0)
				return
		var min_x: float = player_pos.x - 24.0
		var max_x: float = player_pos.x + 24.0
		var min_z: float = player_pos.z - 24.0
		var max_z: float = player_pos.z + 24.0
		var all_lists: Array = [guard_points, loot_points, objective_points, ping_points]
		for lst_v: Variant in all_lists:
			if lst_v is Array:
				for item_v: Variant in (lst_v as Array):
					if item_v is Dictionary:
						var p: Vector3 = (item_v as Dictionary).get("pos", Vector3.ZERO) as Vector3
						min_x = minf(min_x, p.x - 6.0)
						max_x = maxf(max_x, p.x + 6.0)
						min_z = minf(min_z, p.z - 6.0)
						max_z = maxf(max_z, p.z + 6.0)
		_world_center = Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)
		_world_span = clampf(maxf(max_x - min_x, max_z - min_z), 36.0, 220.0)

	func _world_to_screen(pos: Vector3) -> Vector2:
		var pad: float = 28.0
		var usable: float = maxf(10.0, minf(size.x, size.y) - pad * 2.0)
		var rel_x: float = (pos.x - _world_center.x) / _world_span
		var rel_z: float = (pos.z - _world_center.y) / _world_span
		return size * 0.5 + Vector2(rel_x, rel_z) * usable

	func _screen_to_world(pt: Vector2) -> Vector3:
		var pad: float = 28.0
		var usable: float = maxf(10.0, minf(size.x, size.y) - pad * 2.0)
		var rel: Vector2 = (pt - size * 0.5) / usable
		return Vector3(_world_center.x + rel.x * _world_span, player_pos.y, _world_center.y + rel.y * _world_span)

	func _draw() -> void:
		_compute_bounds()
		# Blueprint grid backdrop.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.024, 0.052, 0.072, 0.94), true)
		var grid_col: Color = Color(0.22, 0.56, 0.60, 0.16)
		var step: float = 40.0
		var gx: float = step
		while gx < size.x:
			draw_line(Vector2(gx, 0.0), Vector2(gx, size.y), grid_col, 1.0)
			gx += step
		var gy: float = step
		while gy < size.y:
			draw_line(Vector2(0.0, gy), Vector2(size.x, gy), grid_col, 1.0)
			gy += step
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.28, 0.72, 0.74, 0.55), false, 1.5)

		# Authored TATWorldMapBoundary floors (W9-P3-C4). The primary box is the
		# map extent (already used by _compute_bounds); the secondaries are the
		# floors, the active one highlighted with its authored label. When the
		# generated payload has no boundaries, the HUD draws its labelled
		# fallback window (port stand-in; not authored data).
		var font: Font = ThemeDB.fallback_font
		if not boundaries.is_empty():
			for bv: Variant in boundaries:
				if not (bv is Dictionary):
					continue
				var b: Dictionary = bv as Dictionary
				var bp: Vector3 = b.get("pos", Vector3.ZERO) as Vector3
				var bs: Vector3 = b.get("size", Vector3(16.0, 1.0, 16.0)) as Vector3
				var tl: Vector2 = _world_to_screen(bp + Vector3(-bs.x * 0.5, 0.0, -bs.z * 0.5))
				var br: Vector2 = _world_to_screen(bp + Vector3(bs.x * 0.5, 0.0, bs.z * 0.5))
				var rect: Rect2 = Rect2(tl, br - tl)
				var is_active: bool = str(b.get("name", "")) == str(active_boundary.get("name", ""))
				if bool(b.get("primary", false)):
					draw_rect(rect, Color(0.10, 0.24, 0.28, 0.18), true)
				draw_rect(rect, Color(0.55, 0.92, 0.94, 0.86 if is_active else 0.26),
					false, 2.0 if is_active else 1.0)
			var ly: float = 18.0
			for bv2: Variant in boundaries:
				if not (bv2 is Dictionary):
					continue
				var b2: Dictionary = bv2 as Dictionary
				var label: String = MapBoundariesScript.label_for(b2)
				if label == "":
					continue
				var active2: bool = str(b2.get("name", "")) == str(active_boundary.get("name", ""))
				var col: Color = Color(0.86, 0.97, 0.98, 0.95) if active2 else Color(0.55, 0.72, 0.75, 0.62)
				draw_string(font, Vector2(12.0, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, col)
				ly += 17.0
			var active_label: String = MapBoundariesScript.label_for(active_boundary)
			if active_label != "":
				draw_string(font, Vector2(0.0, 22.0), active_label, HORIZONTAL_ALIGNMENT_CENTER,
					size.x, 15, Color(0.86, 0.97, 0.98, 0.95))
		elif boundary_source == "fallback":
			# PORT COPY (diagnostic, no authored row): names the invented window.
			draw_string(font, Vector2(12.0, size.y - 14.0),
				"FALLBACK BOUNDS - NO AUTHORED TATWorldMapBoundary",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(0.72, 0.55, 0.36, 0.85))

		# Loot dots.
		for lv: Variant in loot_points:
			if lv is Dictionary:
				var pt: Vector2 = _world_to_screen((lv as Dictionary).get("pos", Vector3.ZERO) as Vector3)
				draw_circle(pt, 3.2, Color(0.95, 0.80, 0.36, 0.78))

		# Objectives (gold diamonds). Map buildings grow/shrink with map zoom
		# (KF10/S08 KILCAIRN tokens): marker size tracks _world_span against
		# the 64.0 default so buildings stay world-proportioned (7.0 px at the
		# default span) while guard/loot/ping markers stay screen-constant.
		for ov: Variant in objective_points:
			if ov is Dictionary:
				var pt2: Vector2 = _world_to_screen((ov as Dictionary).get("pos", Vector3.ZERO) as Vector3)
				var d: float = 7.0 * (64.0 / maxf(_world_span, 1.0))
				var poly: PackedVector2Array = PackedVector2Array([
					pt2 + Vector2(0, -d), pt2 + Vector2(d, 0), pt2 + Vector2(0, d), pt2 + Vector2(-d, 0)
				])
				draw_colored_polygon(poly, Color(0.98, 0.84, 0.34, 0.96))

		# Guards (triangles colored by alert state).
		for gv: Variant in guard_points:
			if gv is Dictionary:
				var gd: Dictionary = gv as Dictionary
				var pt3: Vector2 = _world_to_screen(gd.get("pos", Vector3.ZERO) as Vector3)
				var gcol: Color = Color(0.95, 0.24, 0.22, 0.95) if gd.get("combat", false) == true else (
					Color(0.98, 0.58, 0.20, 0.92) if gd.get("alerted", false) == true else Color(0.92, 0.82, 0.32, 0.75)
				)
				var tri: PackedVector2Array = PackedVector2Array([
					pt3 + Vector2(0, -6), pt3 + Vector2(5.5, 5), pt3 + Vector2(-5.5, 5)
				])
				draw_colored_polygon(tri, gcol)

		# Active pings (teal rings).
		for pv: Variant in ping_points:
			if pv is Dictionary:
				var pd: Dictionary = pv as Dictionary
				var pt4: Vector2 = _world_to_screen(pd.get("pos", Vector3.ZERO) as Vector3)
				var pcol: Color = pd.get("color", Color(0.45, 0.95, 0.92, 0.96)) as Color
				draw_arc(pt4, 9.0, 0.0, TAU, 24, pcol, 2.0, true)
				draw_circle(pt4, 3.5, pcol)

		# Player marker + facing cone.
		var pp: Vector2 = _world_to_screen(player_pos)
		var fwd_ang: float = -player_yaw - PI * 0.5
		var cone_pts: PackedVector2Array = PackedVector2Array([
			pp,
			pp + Vector2(cos(fwd_ang - 0.45), sin(fwd_ang - 0.45)) * 28.0,
			pp + Vector2(cos(fwd_ang + 0.45), sin(fwd_ang + 0.45)) * 28.0,
		])
		draw_colored_polygon(cone_pts, Color(0.42, 0.92, 0.96, 0.22))
		draw_circle(pp, 6.0, Color(0.55, 0.96, 0.98, 1.0))
		draw_arc(pp, 8.5, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.85), 1.5, true)


class PingRadialDraw extends Control:
	var selected_idx: int = 0
	## Number of radial choices; the copy lives in HUD.ping_label_text() so the
	## labels are Loc-routed (an inner-class const cannot call the Loc pipeline).
	const LABEL_COUNT: int = 4
	const COLORS: Array[Color] = [
		Color(0.96, 0.82, 0.38, 0.96),
		Color(0.96, 0.26, 0.24, 0.96),
		Color(0.42, 0.94, 0.88, 0.96),
		Color(0.54, 0.82, 1.0, 0.96),
	]

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r_out: float = 98.0
		var r_in: float = 34.0
		draw_circle(c, r_out, Color(0.025, 0.058, 0.080, 0.82))
		draw_arc(c, r_out, 0.0, TAU, 56, Color(0.30, 0.76, 0.78, 0.85), 2.0, true)
		draw_arc(c, r_in, 0.0, TAU, 36, Color(0.30, 0.76, 0.78, 0.70), 1.6, true)
		# Diagonal dividers between 4 quadrants (Top=0, Right=1, Bottom=2, Left=3).
		for k: int in range(4):
			var ang: float = deg_to_rad(45.0 + float(k) * 90.0)
			var d: Vector2 = Vector2(cos(ang), sin(ang))
			draw_line(c + d * r_in, c + d * r_out, Color(0.30, 0.76, 0.78, 0.45), 1.5, true)
		# Highlight selected wedge arc.
		var sel_center_deg: float = -90.0 + float(selected_idx) * 90.0
		var a0: float = deg_to_rad(sel_center_deg - 43.0)
		var a1: float = deg_to_rad(sel_center_deg + 43.0)
		var col: Color = COLORS[clampi(selected_idx, 0, COLORS.size() - 1)]
		draw_arc(c, (r_in + r_out) * 0.5, a0, a1, 24, Color(col.r, col.g, col.b, 0.34), r_out - r_in - 4.0, true)
		draw_arc(c, r_out, a0, a1, 24, col, 3.6, true)


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# C-4 experiment: account for every HUD build (the recording showed duplicated
	# hp-frame caps / labels with only one HudScript). One line per instance.
	hud_build_id = _hud_build_serial + 1
	_hud_build_serial = hud_build_id
	_sans = ThemeScript.font_sans()
	_italic = ThemeScript.font_italic()
	_serif = ThemeScript.font_serif()
	_typewriter = ThemeScript.font_typewriter()
	_load_lockpick_db()
	# Deterministic pause-footer seed: the mission's published map seed. The
	# old wall-clock seed changed every HUD session for the same run.
	_run_seed = int(GameState.active_map_seed)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Disguise vignette (full-screen overlay, hidden unless disguised).
	disguise_vignette = _tex_rect_full("res://assets/ue/Raw/Art/UI/HUD/T_Disguise_Vignette02.png")
	if disguise_vignette != null:
		disguise_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disguise_vignette.visible = false
		_root.add_child(disguise_vignette)

	# Clean Thief Vision outer edge vignette (NO flat cyan full-screen wash!).
	thief_vision_overlay = ColorRect.new()
	thief_vision_overlay.name = "ThiefVisionVignette"
	thief_vision_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	thief_vision_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thief_vision_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	var tv_sh: Shader = Shader.new()
	tv_sh.code = THIEF_VISION_VIGNETTE_SHADER
	var tv_mat: ShaderMaterial = ShaderMaterial.new()
	tv_mat.shader = tv_sh
	tv_mat.set_shader_parameter("strength", 1.0)
	thief_vision_overlay.material = tv_mat
	thief_vision_overlay.visible = false
	_root.add_child(thief_vision_overlay)

	# World-projected alert pips, offscreen threat arcs & ping markers.
	_alert_layer = Control.new()
	_alert_layer.name = "AlertOverlayLayer"
	_alert_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_alert_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_alert_layer)
	_init_alert_textures()

	_ping_marker_layer = Control.new()
	_ping_marker_layer.name = "PingMarkerLayer"
	_ping_marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ping_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ping_marker_layer)

	# Clue toast label (top-center below compass).
	clue_toast_lbl = Label.new()
	clue_toast_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	clue_toast_lbl.position = Vector2(-280, 56)
	clue_toast_lbl.custom_minimum_size = Vector2(560, 44)
	clue_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clue_toast_lbl.add_theme_font_size_override("font_size", 15)
	clue_toast_lbl.add_theme_color_override("font_color", Color(0.65, 0.92, 1.0))
	clue_toast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clue_toast_lbl.visible = false
	_root.add_child(clue_toast_lbl)

	# Downed countdown label.
	downed_lbl = Label.new()
	downed_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	downed_lbl.position = Vector2(-280, 104)
	downed_lbl.custom_minimum_size = Vector2(560, 44)
	downed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	downed_lbl.add_theme_font_size_override("font_size", 26)
	downed_lbl.add_theme_color_override("font_color", Color(1.0, 0.32, 0.28))
	downed_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	downed_lbl.add_theme_constant_override("shadow_offset_x", 2)
	downed_lbl.add_theme_constant_override("shadow_offset_y", 2)
	downed_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	downed_lbl.visible = false
	_root.add_child(downed_lbl)

	# W7E door banner (endgame only). Sits below the downed countdown so both
	# can never overlap; the countdown in the objective strip stays the compact
	# form while this spells out the collapsed-door rule.
	door_lbl = Label.new()
	door_lbl.name = "DoorWarningLabel"
	door_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	door_lbl.position = Vector2(-360, 144)
	door_lbl.custom_minimum_size = Vector2(720, 32)
	door_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	door_lbl.add_theme_font_size_override("font_size", 17)
	door_lbl.add_theme_color_override("font_color", Color(0.96, 0.78, 0.34))
	door_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	door_lbl.add_theme_constant_override("shadow_offset_x", 2)
	door_lbl.add_theme_constant_override("shadow_offset_y", 2)
	door_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	door_lbl.visible = false
	_root.add_child(door_lbl)

	# Legacy lockpick progress bar (preserved property name for backwards compatibility).
	lockpick_bar = ProgressBar.new()
	lockpick_bar.set_anchors_preset(Control.PRESET_CENTER)
	lockpick_bar.position = Vector2(-90, 56)
	lockpick_bar.custom_minimum_size = Vector2(180, 12)
	lockpick_bar.max_value = 1.0
	lockpick_bar.show_percentage = false
	lockpick_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lockpick_bar.visible = false
	_root.add_child(lockpick_bar)

	_build_compass_strip(_root)
	_build_thief_plate(_root)
	_build_top_left_health_and_objectives(_root)
	_build_stealth_ball_and_soundwaves(_root)
	_build_reticle_and_prompt(_root)
	_build_action_hints(_root)
	_build_den_lookat_card(_root)
	_build_fps_overlay(_root)

	hotbar_lbl = Label.new()
	hotbar_lbl.visible = false
	_root.add_child(hotbar_lbl)

	var is_hub: bool = GameState.active_contract_order <= 1
	if not is_hub and not MobileProfile.is_mobile():
		_build_tool_hotbar(_root)
	_build_key_row(_root)

	_build_lockpick_minigame(_root)
	_build_map_overlay(_root)
	_build_ping_radial(_root)
	_build_mission_letter(_root)
	_build_result_panel(_root)
	_build_pause_menu(_root)

	print("TAT-2 HUD build: id=%d root_children=%d hp_frame=%d hp_fill=%d objectives=%d" % [
		hud_build_id, _root.get_child_count(), int(debug_hud_counts().get("hp_frames", 0)),
		int(debug_hud_counts().get("hp_fills", 0)), int(debug_hud_counts().get("objectives", 0))])

	# Wire global buses safely.
	var nb: Node = get_node_or_null("/root/NoiseBus")
	if nb != null and nb.has_signal("noise_emitted"):
		nb.connect("noise_emitted", _on_noise_emitted)
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("mission_letter_requested"):
		gs.connect("mission_letter_requested", _on_mission_letter_requested)
	_setup_authored_toast()
	_capture_run_xp_start()
	_suppress_invented_loot_labels()
	# W9-P3-C3: a device swap re-texts the built-once glyph labels (InputGlyphs
	# tracks the active device in InputContext.note_event).
	var ic: Node = get_node_or_null("/root/InputContext")
	if ic != null and ic.has_signal("device_changed"):
		if not ic.is_connected("device_changed", _on_input_device_changed):
			ic.connect("device_changed", _on_input_device_changed)


## W9-P3-C4: authored loot toast (`BPUI_ToastWidget` / `Toasts.MajorLootTaken`).
## GameState.carried_loot_changed fires once per accepted pickup; the toast is
## the authored major-loot row, minor pickups keep the HUD counter only.
func _setup_authored_toast() -> void:
	if _toast != null:
		return
	_toast = UIToastScript.new()
	_toast.name = "AuthoredToastStack"
	_root.add_child(_toast)
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("carried_slots_used"):
		_carried_used_seen = int(gs.call("carried_slots_used"))
	if gs != null and gs.has_signal("carried_loot_changed"):
		if not gs.is_connected("carried_loot_changed", _on_carried_loot_changed):
			gs.connect("carried_loot_changed", _on_carried_loot_changed)


func _on_carried_loot_changed(used: int, _maximum: int, _value: int) -> void:
	if _toast == null:
		return
	# Only a GROWTH is a pickup: a stash deposit / run reset also emits this
	# signal with fewer (or zero) slots. The baseline is ALWAYS updated, so the
	# first major pickup after a stash/reset is not swallowed (audit-c4 5c).
	var grew: bool = _carried_used_seen < 0 or used > _carried_used_seen
	_carried_used_seen = used
	if not grew:
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var carried_v: Variant = gs.get("carried_loot")
	if not (carried_v is Array) or (carried_v as Array).is_empty():
		return
	var last_v: Variant = (carried_v as Array)[(carried_v as Array).size() - 1]
	if not (last_v is Dictionary):
		return
	var entry: Dictionary = last_v as Dictionary
	# DT_ToastConfig NewRow_12 is Toast.Type.Gameplay.Loot.Taken: the authored
	# template is ST_Toasts.MajorLootTaken. Minor loot has no authored toast row.
	if str(entry.get("tier", "")) != "major":
		return
	var loot_name: String = str(entry.get("display_name", entry.get("name", ""))).strip_edges()
	if loot_name == "":
		return
	_toast.call("show_major_loot", loot_name, "")


## RE-L/C5-03: the world-space loot Label3D (font 28, no panel) is port
## invented. The authored pickup is the HUD toast above, so the HUD suppresses
## the label. The creation site (game/src/interact/loot_item.gd) is a P2-owned
## file; deleting it there is recorded as BLOCKED-ON P2 in the W9-P3 report.
func _hide_all_loot_labels() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for n: Node in tree.get_nodes_in_group("loot"):
		_hide_loot_label(n)


func _suppress_invented_loot_labels() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for n: Node in tree.get_nodes_in_group("loot"):
		_hide_loot_label(n)
	if not tree.node_added.is_connected(_on_hud_node_added):
		tree.node_added.connect(_on_hud_node_added)


func _on_hud_node_added(n: Node) -> void:
	if n is Node3D:
		call_deferred("_hide_loot_label_if_grouped", n)


func _hide_loot_label_if_grouped(n: Node) -> void:
	if n != null and is_instance_valid(n) and n.is_in_group("loot"):
		_hide_loot_label(n)


func _hide_loot_label(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if not (n.get("label") is Label3D):
		return
	# The property exists on the loot-item script; never poke an unrelated node.
	if n.get("label") == null:
		return
	(n.get("label") as Label3D).visible = false


## W9-P3-C1: the XP at HUD creation. mission_controller awards the run's XP
## before show_result, so `now - run_start` is the measured award for the
## post-match XP screen (0 on capture/free play, -1 when unreadable).
func _capture_run_xp_start() -> void:
	var ss: Node = get_node_or_null("/root/SaveSystem")
	if ss == null or not ss.has_method("get_level_progress"):
		_run_xp_start = -1
		return
	var prog: Variant = ss.call("get_level_progress")
	if not (prog is Dictionary):
		_run_xp_start = -1
		return
	var d: Dictionary = prog as Dictionary
	var total: int = int(ss.call("xp_total_for_level", int(d.get("level", 1)))) + int(d.get("xp_in_level", 0))
	_run_xp_start = total


func run_xp_awarded() -> int:
	if _run_xp_start < 0:
		return -1
	var ss: Node = get_node_or_null("/root/SaveSystem")
	if ss == null or not ss.has_method("get_level_progress"):
		return -1
	var prog: Variant = ss.call("get_level_progress")
	if not (prog is Dictionary):
		return -1
	var d: Dictionary = prog as Dictionary
	var total: int = int(ss.call("xp_total_for_level", int(d.get("level", 1)))) + int(d.get("xp_in_level", 0))
	return maxi(total - _run_xp_start, 0)


## Test hooks (W9-P3): the authored-boundary source for the current map, the
## pause panel and its first focusable control.
func map_boundary_source() -> String:
	return _boundary_source


func map_boundary_rows() -> Array[Dictionary]:
	return _boundary_rows


func pause_panel_for_test() -> Control:
	return _pause_panel_for_focus


func pause_first_control_for_test() -> Control:
	if _pause_panel_for_focus == null:
		return null
	var controls: Array[Control] = FocusNavScript.focusable_controls(_pause_panel_for_focus)
	return controls[0] if not controls.is_empty() else null


## W9-P3-C3: live glyph re-render on a device swap. The labels below are built
## once at HUD construction, so without this a pad player keeps reading [TAB].
func _on_input_device_changed(_device: String) -> void:
	if _hint_map_key_lbl != null:
		_hint_map_key_lbl.text = InputGlyphs.text("map_toggle").to_upper()
	if _hint_ping_key_lbl != null:
		_hint_ping_key_lbl.text = InputGlyphs.text("ping_menu").to_upper()
	if _pause_esc_key_lbl != null:
		_pause_esc_key_lbl.text = InputGlyphs.bracket("pause")
	if _map_foot_lbl != null:
		_map_foot_lbl.text = InputGlyphs.format_legend(
			UIStringsScript.loc("[LMB] PLACE WAYPOINT   ·   [TAB] / [ESC] CLOSE MAP"), MAP_LEGEND_ACTIONS)


func _exit_tree() -> void:
	var nb: Node = get_node_or_null("/root/NoiseBus")
	if nb != null and nb.has_signal("noise_emitted") and nb.is_connected("noise_emitted", _on_noise_emitted):
		nb.disconnect("noise_emitted", _on_noise_emitted)
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("mission_letter_requested") and gs.is_connected("mission_letter_requested", _on_mission_letter_requested):
		gs.disconnect("mission_letter_requested", _on_mission_letter_requested)
	var ic: Node = get_node_or_null("/root/InputContext")
	if ic != null and ic.has_signal("device_changed") and ic.is_connected("device_changed", _on_input_device_changed):
		ic.disconnect("device_changed", _on_input_device_changed)


# =============================================================================
# HUD Layout Builders
# =============================================================================

## W5D: nearest of the eight authored headings to a compass angle in degrees
## (0 = north, clockwise). The centre tick is the only heading shown now.
static func compass_heading_name(deg: float) -> String:
	return COMPASS_DIRECTIONS[int(round(fposmod(deg, 360.0) / 45.0)) % COMPASS_DIRECTIONS.size()]


## W5D: write the single centre heading (kept separate so a structural test
## can exercise the mapping without a live player).
func update_compass_heading(deg: float) -> String:
	var name: String = compass_heading_name(deg)
	if compass_lbl != null:
		compass_lbl.text = name
	return name


func _build_compass_strip(root: Control) -> void:
	var compass_box: Control = Control.new()
	compass_box.name = "CompassStrip"
	compass_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass_box.offset_left = -290.0
	compass_box.offset_top = 10.0
	compass_box.offset_right = 290.0
	compass_box.offset_bottom = 40.0
	compass_box.custom_minimum_size = Vector2(580, 30)
	compass_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(compass_box)

	# W5D: subtle centre line. The authored T_compass_lines strip is kept (the
	# E2E contract names it) but at native 100x30 centred on the tick, not
	# stretched across 580 px with every cardinal in between.
	var c_lines: TextureRect = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/T_compass_lines.png", Vector2(100, 30))
	if c_lines != null:
		c_lines.name = "CompassCenterLine"
		c_lines.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		c_lines.position = Vector2(240, 0)
		c_lines.modulate = Color(0.55, 0.72, 1.0, 0.42)
		compass_box.add_child(c_lines)

	# Subtle center '+' tick matching UE5 compass strip.
	var tick_v: ColorRect = ColorRect.new()
	tick_v.color = Color(0.66, 0.80, 1.0, 0.55)
	tick_v.position = Vector2(289.5, 9.0)
	tick_v.size = Vector2(1.0, 12.0)
	tick_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_box.add_child(tick_v)

	# W5D: the full scrolling cardinal ribbon is retired. ribbon_clip/ribbon_lbl
	# stay as preserved public properties (callers and E2E read them), but are
	# hidden and empty so only the centre heading is shown.
	ribbon_clip = Control.new()
	ribbon_clip.name = "CompassRibbonRetired"
	ribbon_clip.position = Vector2(40, 2)
	ribbon_clip.custom_minimum_size = Vector2(500, 24)
	ribbon_clip.size = Vector2(500, 24)
	ribbon_clip.clip_contents = true
	ribbon_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon_clip.visible = false
	compass_box.add_child(ribbon_clip)

	ribbon_lbl = Label.new()
	ribbon_lbl.name = "CompassRibbonLabelRetired"
	ribbon_lbl.text = ""
	ribbon_lbl.position = Vector2(0, 0)
	ribbon_lbl.custom_minimum_size = Vector2(1600, 24)
	ribbon_lbl.size = Vector2(1600, 24)
	ribbon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ribbon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ribbon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon_lbl.visible = false
	ribbon_lbl.add_theme_font_size_override("font_size", 13)
	ribbon_lbl.add_theme_color_override("font_color", Color(0.76, 0.84, 0.96, 0.62))
	if _sans != null:
		ribbon_lbl.add_theme_font_override("font", _sans)
	ribbon_clip.add_child(ribbon_lbl)

	# The single heading nearest the centre tick (W5D reference HUD).
	compass_lbl = Label.new()
	compass_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	compass_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compass_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	compass_lbl.add_theme_font_size_override("font_size", 15)
	compass_lbl.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0, 0.92))
	compass_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	compass_lbl.add_theme_constant_override("shadow_offset_x", 1)
	compass_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if _sans != null:
		compass_lbl.add_theme_font_override("font", _sans)
	compass_box.add_child(compass_lbl)

	# Compass PoI markers layer (gold objective + teal ping diamonds).
	_compass_poi_layer = Control.new()
	_compass_poi_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_compass_poi_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_box.add_child(_compass_poi_layer)
	var poi_sheet: Texture2D = ResourceLoader.load("res://assets/ue/Raw/Art/UI/HUD/T_Compass_PoI_IconSheet.png") as Texture2D
	if poi_sheet != null:
		_poi_gold_tex = AtlasTexture.new()
		_poi_gold_tex.atlas = poi_sheet
		_poi_gold_tex.region = Rect2(0, 0, 100, 100)
		_poi_teal_tex = AtlasTexture.new()
		_poi_teal_tex.atlas = poi_sheet
		_poi_teal_tex.region = Rect2(100, 0, 100, 100)
	# Authored above/below chevron for compass PoIs (UE WBP_Compass verticality
	# arrow). No invented art: a missing texture leaves the pool empty.
	_compass_verticality_tex = ResourceLoader.load("res://assets/ue/Raw/Art/UI/HUD/T_compass_verticality_arrow.png") as Texture2D


func _build_thief_plate(root: Control) -> void:
	var port_anchor: Control = Control.new()
	port_anchor.name = "PortraitBadge"
	port_anchor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	port_anchor.offset_left = -98.0
	port_anchor.offset_top = 14.0
	port_anchor.offset_right = -16.0
	port_anchor.offset_bottom = 104.0
	port_anchor.custom_minimum_size = Vector2(82, 90)
	port_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(port_anchor)

	var p_bg: TextureRect = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/portrait/T_portrait_frameBg.png", Vector2(76, 76))
	if p_bg != null:
		p_bg.modulate = Color(0.14, 0.18, 0.34, 0.92)
		port_anchor.add_child(p_bg)

	var port_path: String = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_spider.png"
	if GameState.thief_id == "chameleon" or GameState.thief_id == "moth":
		port_path = "res://assets/ue/Raw/Art/UI/Shell/CharacterSelect/T_portrait_chameleon.png"
	var p_img: TextureRect = _tex_rect(port_path, Vector2(68, 68))
	if p_img != null:
		p_img.position = Vector2(4, 4)
		if GameState.thief_id == "moth":
			p_img.modulate = Color(0.75, 0.65, 1.0)
		port_anchor.add_child(p_img)

	var p_frame: TextureRect = _tex_rect("res://assets/ue/Raw/Art/UI/Components/T_PortraitFrame_noPlayerColor.png", Vector2(76, 76))
	if p_frame != null:
		p_frame.modulate = Color(0.46, 0.56, 0.96, 0.98)
		port_anchor.add_child(p_frame)

	# Centered bottom-edge level badge (T_portrait_levelBg + T_portrait_levelFrame).
	var lvl_box: Control = Control.new()
	lvl_box.name = "PortraitLevelBadge"
	lvl_box.position = Vector2(25, 62)
	lvl_box.custom_minimum_size = Vector2(26, 26)
	lvl_box.size = Vector2(26, 26)
	lvl_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port_anchor.add_child(lvl_box)

	var lvl_bg: TextureRect = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/portrait/T_portrait_levelBg.png", Vector2(26, 26))
	if lvl_bg != null:
		lvl_bg.modulate = Color(0.06, 0.09, 0.18, 0.96)
		lvl_box.add_child(lvl_bg)
	var lvl_frame: TextureRect = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/portrait/T_portrait_levelFrame.png", Vector2(26, 26))
	if lvl_frame != null:
		lvl_frame.modulate = Color(0.50, 0.60, 0.98, 0.98)
		lvl_box.add_child(lvl_frame)

	var lvl: int = 1
	var saved_lvl: Variant = SaveSystem.data.get("level", 1)
	if saved_lvl is float or saved_lvl is int:
		lvl = int(saved_lvl)
	_level_badge_lbl = Label.new()
	_level_badge_lbl.text = "%d" % lvl
	_level_badge_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Authored numbers role (CF_FacultyGlyphic 32 -> 21 on the 720p canvas).
	_level_badge_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_NUMBERS)
	_level_badge_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	var num_font: Font = ThemeScript.font_numbers()
	if num_font != null:
		_level_badge_lbl.add_theme_font_override("font", num_font)
	elif _sans != null:
		_level_badge_lbl.add_theme_font_override("font", _sans)
	_level_badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lvl_box.add_child(_level_badge_lbl)

	_thief_name_lbl = Label.new()
	_thief_name_lbl.text = _player_display_name()
	_thief_name_lbl.position = Vector2(-180, 4)
	_thief_name_lbl.custom_minimum_size = Vector2(170, 24)
	_thief_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_thief_name_lbl.add_theme_font_size_override("font_size", 15)
	_thief_name_lbl.add_theme_color_override("font_color", Color(0.86, 0.91, 0.98, 0.95))
	_thief_name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_thief_name_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_thief_name_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if _sans != null:
		_thief_name_lbl.add_theme_font_override("font", _sans)
	_thief_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port_anchor.add_child(_thief_name_lbl)


func _build_top_left_health_and_objectives(root: Control) -> void:
	var is_hub: bool = GameState.active_contract_order <= 1
	var tl_stack: VBoxContainer = VBoxContainer.new()
	tl_stack.name = "TopLeftStack"
	tl_stack.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tl_stack.position = Vector2(18, 12)
	tl_stack.custom_minimum_size = Vector2(360, 0)
	tl_stack.add_theme_constant_override("separation", 4)
	tl_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl_stack)

	# Top-left ornate Health Bar using T_healthBar_straight_* + health_block_percentages().
	# Authored composition (C3-08 / ADJUDICATIONS C-4): frame + authored SHAPED
	# fill share one 4:1 rect; the splatter is a damage overlay gated on health.
	_hp_container = Control.new()
	_hp_container.name = "HealthBarContainer"
	_hp_container.custom_minimum_size = Vector2(HP_BAR_MAX_W, HP_BAR_H + 8.0)
	_hp_container.size = Vector2(HP_BAR_MAX_W, HP_BAR_H + 8.0)
	_hp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_container.visible = not is_hub
	tl_stack.add_child(_hp_container)

	var hp_back: ColorRect = ColorRect.new()
	hp_back.name = "HpBack"
	hp_back.position = Vector2.ZERO
	hp_back.size = Vector2(HP_BAR_MAX_W, HP_BAR_H)
	hp_back.color = Color(0.06, 0.04, 0.08, 0.78)
	hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_container.add_child(hp_back)

	_hp_clip = Control.new()
	_hp_clip.name = "HpClip"
	_hp_clip.position = Vector2.ZERO
	_hp_clip.size = Vector2(HP_BAR_MAX_W, HP_BAR_H)
	_hp_clip.clip_contents = true
	_hp_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_container.add_child(_hp_clip)

	# The authored shaped red fill (never loaded before T05). Sized to the frame
	# rect; size.x shrinks with health (the shaped left end stays put, the right
	# end retracts instead of a rectangle cutting the frame).
	hp_fill = TextureRect.new()
	hp_fill.name = "HpFill"
	hp_fill.position = Vector2.ZERO
	hp_fill.size = Vector2(HP_BAR_MAX_W, HP_BAR_H)
	hp_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hp_fill.stretch_mode = TextureRect.STRETCH_SCALE
	var hp_fill_tex: Texture2D = ResourceLoader.load("res://assets/ue/Raw/Art/UI/HUD/HealthBar/hpBar_straight/T_healthBar_straight_RGB.png") as Texture2D
	if hp_fill_tex != null:
		hp_fill.texture = hp_fill_tex
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_clip.add_child(hp_fill)

	_hp_splatter = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/HealthBar/hpBar_straight/T_healthBar_splatter_red.png", Vector2(HP_BAR_MAX_W, HP_BAR_H))
	if _hp_splatter != null:
		_hp_splatter.name = "HpSplatter"
		_hp_splatter.stretch_mode = TextureRect.STRETCH_SCALE
		_hp_splatter.position = Vector2.ZERO
		_hp_splatter.modulate = Color(0.62, 0.06, 0.08, 0.92)
		_hp_splatter.visible = false
		_hp_clip.add_child(_hp_splatter)

	_hp_ticks_box = Control.new()
	_hp_ticks_box.position = Vector2.ZERO
	_hp_ticks_box.size = Vector2(HP_BAR_MAX_W, HP_BAR_H)
	_hp_ticks_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_container.add_child(_hp_ticks_box)
	_rebuild_hp_block_ticks([25, 25, 25, 25])

	var hp_frame: TextureRect = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/HealthBar/hpBar_straight/T_healthBar_straight_frame.png", Vector2(HP_BAR_MAX_W, HP_BAR_H))
	if hp_frame != null:
		hp_frame.name = "HpFrame"
		# The frame is authored 1024x256 and drawn at the same 4:1 aspect, so
		# STRETCH_SCALE is aspect-exact (no ornament distortion).
		hp_frame.stretch_mode = TextureRect.STRETCH_SCALE
		hp_frame.position = Vector2.ZERO
		_hp_container.add_child(hp_frame)
		_hp_frame_builds += 1

	# Subtle Stamina bar right below the HP frame (preserved stam_fill property).
	_stam_bg = ColorRect.new()
	_stam_bg.position = Vector2(6, HP_BAR_H + 2.0)
	_stam_bg.size = Vector2(STAM_BAR_MAX_W, 4)
	_stam_bg.color = Color(0.06, 0.10, 0.16, 0.55)
	_stam_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_container.add_child(_stam_bg)

	stam_fill = ColorRect.new()
	stam_fill.name = "StamFill"
	stam_fill.position = Vector2(6, HP_BAR_H + 2.0)
	stam_fill.size = Vector2(STAM_BAR_MAX_W, 4)
	stam_fill.color = Color(0.42, 0.82, 0.94, 0.82)
	stam_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_container.add_child(stam_fill)

	# Loot counter ((£) 0) directly below Health Bar.
	_loot_lbl = Label.new()
	_loot_lbl.name = "LootCounterLabel"
	_loot_lbl.text = "(£) 0"
	_loot_lbl.add_theme_font_size_override("font_size", 16)
	_loot_lbl.add_theme_color_override("font_color", Color(0.78, 0.86, 0.98, 0.96))
	_loot_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_loot_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_loot_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if _sans != null:
		_loot_lbl.add_theme_font_override("font", _sans)
	_loot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loot_lbl.visible = not is_hub
	tl_stack.add_child(_loot_lbl)

	# Preserved obj_lbl (Mission + multi-part sub-objectives).
	obj_lbl = Label.new()
	obj_lbl.name = "ObjectivesLabel"
	obj_lbl.add_theme_font_size_override("font_size", 14)
	obj_lbl.add_theme_color_override("font_color", Color(0.84, 0.88, 0.96, 0.94))
	obj_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.88))
	obj_lbl.add_theme_constant_override("shadow_offset_x", 1)
	obj_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if _italic != null:
		obj_lbl.add_theme_font_override("font", _italic)
	elif _sans != null:
		obj_lbl.add_theme_font_override("font", _sans)
	obj_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl_stack.add_child(obj_lbl)


func _rebuild_hp_block_ticks(blocks: Array) -> void:
	if _hp_ticks_box == null:
		return
	_hp_block_cache = blocks.duplicate()
	for c: Node in _hp_ticks_box.get_children():
		c.queue_free()
	var total: float = 0.0
	for b: Variant in blocks:
		total += maxf(0.0, float(b))
	if total <= 0.0:
		return
	var accum: float = 0.0
	for i: int in range(blocks.size() - 1):
		accum += maxf(0.0, float(blocks[i]))
		var frac: float = clampf(accum / total, 0.0, 1.0)
		var tick: ColorRect = ColorRect.new()
		tick.color = Color(0.10, 0.14, 0.28, 0.82)
		tick.position = Vector2(HP_BAR_MAX_W * frac - 1.0, 2.0)
		tick.size = Vector2(2.0, HP_BAR_H - 4.0)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hp_ticks_box.add_child(tick)


func _build_stealth_ball_and_soundwaves(root: Control) -> void:
	var is_hub: bool = GameState.active_contract_order <= 1
	_stealth_holder = Control.new()
	_stealth_holder.name = "StealthBallContainer"
	_stealth_holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stealth_holder.offset_left = -110.0
	_stealth_holder.offset_top = -102.0
	_stealth_holder.offset_right = 110.0
	_stealth_holder.offset_bottom = -6.0
	_stealth_holder.custom_minimum_size = Vector2(220, 96)
	_stealth_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stealth_holder.visible = not is_hub
	root.add_child(_stealth_holder)

	# Bilateral red SoundWaves flanking the Stealth Ball.
	_soundwaves_draw = SoundWavesDraw.new()
	_soundwaves_draw.name = "SoundWaves"
	_soundwaves_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_soundwaves_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stealth_holder.add_child(_soundwaves_draw)

	# Shaded light-reactive inner orb.
	var orb: ColorRect = ColorRect.new()
	orb.name = "StealthOrbInner"
	orb.position = Vector2(110.0 - 31.0, 48.0 - 31.0)
	orb.size = Vector2(62.0, 62.0)
	orb.color = Color(1.0, 1.0, 1.0, 1.0)
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var orb_sh: Shader = Shader.new()
	orb_sh.code = STEALTH_ORB_SHADER
	_stealth_orb_mat = ShaderMaterial.new()
	_stealth_orb_mat.shader = orb_sh
	_stealth_orb_mat.set_shader_parameter("visibility", 0.2)
	orb.material = _stealth_orb_mat
	_stealth_holder.add_child(orb)

	# Ornate Art Nouveau Stealth Ball frame (preserved stealth_gem property).
	stealth_gem = _tex_rect("res://assets/ue/Raw/Art/UI/HUD/Stealth_Ball/T_stealthball_frame.png", Vector2(84, 84))
	if stealth_gem != null:
		stealth_gem.name = "StealthGemFrame"
		stealth_gem.position = Vector2(110.0 - 42.0, 48.0 - 42.0)
		stealth_gem.modulate = Color(0.48, 0.58, 0.96, 0.98)
		_stealth_holder.add_child(stealth_gem)


func _build_reticle_and_prompt(root: Control) -> void:
	_reticle_draw = ReticleDraw.new()
	_reticle_draw.name = "DynamicReticle"
	_reticle_draw.set_anchors_preset(Control.PRESET_CENTER)
	_reticle_draw.offset_left = -64.0
	_reticle_draw.offset_top = -64.0
	_reticle_draw.offset_right = 64.0
	_reticle_draw.offset_bottom = 64.0
	_reticle_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_reticle_draw)

	_crank_prompt_lbl = Label.new()
	_crank_prompt_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_crank_prompt_lbl.offset_left = -90.0
	_crank_prompt_lbl.offset_top = 34.0
	_crank_prompt_lbl.offset_right = 90.0
	_crank_prompt_lbl.offset_bottom = 56.0
	_crank_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# "Crank" is an authored source (ST_Tools Tools_Deploy_Crank / the locres);
	# [RMB] is the live secondary-action glyph.
	_crank_prompt_lbl.text = InputGlyphs.prompt("secondary_action", UIStringsScript.loc("Crank").to_upper())
	_crank_prompt_lbl.add_theme_font_size_override("font_size", 12)
	_crank_prompt_lbl.add_theme_color_override("font_color", Color(0.58, 0.92, 1.0, 0.96))
	_crank_prompt_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_crank_prompt_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_crank_prompt_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if _sans != null:
		_crank_prompt_lbl.add_theme_font_override("font", _sans)
	_crank_prompt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crank_prompt_lbl.visible = false
	root.add_child(_crank_prompt_lbl)

	# Diegetic center prompt: white keycap badge + crisp periwinkle-teal label.
	var prompt_row: HBoxContainer = HBoxContainer.new()
	prompt_row.set_anchors_preset(Control.PRESET_CENTER)
	prompt_row.offset_left = -190.0
	prompt_row.offset_top = 28.0
	prompt_row.offset_right = 190.0
	prompt_row.offset_bottom = 58.0
	prompt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_row.add_theme_constant_override("separation", 8)
	prompt_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_row)
	_prompt_keycap = ThemeScript.white_keycap("F", 13)
	_prompt_keycap.visible = false
	prompt_row.add_child(_prompt_keycap)
	_prompt_keycap_lbl = _prompt_keycap.get_child(0) as Label
	interact_lbl = Label.new()
	interact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	interact_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interact_lbl.add_theme_font_size_override("font_size", 15)
	interact_lbl.add_theme_color_override("font_color", Color(0.58, 0.72, 0.98, 0.98))
	interact_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	interact_lbl.add_theme_constant_override("shadow_offset_x", 1)
	interact_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if _sans != null:
		interact_lbl.add_theme_font_override("font", _sans)
	interact_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_row.add_child(interact_lbl)

	# KF24/KF25 stacked secondary prompt: [F] [HOLD] LOCK on blue doors and
	# [F] [HOLD] TAKEDOWN over a guard, directly beneath the primary prompt.
	_prompt_secondary_lbl = Label.new()
	_prompt_secondary_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_secondary_lbl.offset_left = -190.0
	_prompt_secondary_lbl.offset_top = 58.0
	_prompt_secondary_lbl.offset_right = 190.0
	_prompt_secondary_lbl.offset_bottom = 82.0
	_prompt_secondary_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_secondary_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_secondary_lbl.add_theme_font_size_override("font_size", 14)
	_prompt_secondary_lbl.add_theme_color_override("font_color", Color(0.58, 0.72, 0.98, 0.88))
	_prompt_secondary_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_prompt_secondary_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_prompt_secondary_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if _sans != null:
		_prompt_secondary_lbl.add_theme_font_override("font", _sans)
	_prompt_secondary_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_secondary_lbl.visible = false
	root.add_child(_prompt_secondary_lbl)


func _build_tool_hotbar(root: Control) -> void:
	slot_count_lbls.clear()
	_slot_icons.clear()
	_slot_borders.clear()
	_slot_bgs.clear()
	_slot_key_lbls.clear()

	_hotbar_anchor = Control.new()
	_hotbar_anchor.name = "BottomLeftToolHotbar"
	_hotbar_anchor.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hotbar_anchor.offset_left = 20.0
	_hotbar_anchor.offset_top = -104.0
	_hotbar_anchor.offset_right = 330.0
	_hotbar_anchor.offset_bottom = -12.0
	_hotbar_anchor.custom_minimum_size = Vector2(310, 92)
	_hotbar_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hotbar_anchor)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.position = Vector2(0, 0)
	hb.custom_minimum_size = Vector2(284, 62)
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar_anchor.add_child(hb)

	var bg_tex: Texture2D = ResourceLoader.load("res://assets/ue/Raw/Art/UI/HUD/T_Ability_Background.png") as Texture2D
	var border_tex: Texture2D = ResourceLoader.load("res://assets/ue/Raw/Art/UI/HUD/T_Ability_Border.png") as Texture2D
	var bg_shader: Shader = Shader.new()
	bg_shader.code = ABILITY_BG_MASK_SHADER

	var default_keys: Array[String] = ["1", "2", "3", "4"]
	var default_ids: Array[String] = ["zipwire", "smoke_bomb", "slithersap", "vistara_diamond"]

	for i: int in range(4):
		var slot: Control = Control.new()
		slot.name = "ToolSlot_%d" % (i + 1)
		slot.custom_minimum_size = Vector2(62, 62)
		slot.size = Vector2(62, 62)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(slot)

		# Masked octagonal background (T_Ability_Background luminance mask).
		var bg_tr: TextureRect = TextureRect.new()
		bg_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tr.stretch_mode = TextureRect.STRETCH_SCALE
		bg_tr.texture = bg_tex
		bg_tr.size = Vector2(62, 62)
		bg_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm: ShaderMaterial = ShaderMaterial.new()
		sm.shader = bg_shader
		sm.set_shader_parameter("tint_color", Color(0.05, 0.08, 0.16, 0.72))
		bg_tr.material = sm
		slot.add_child(bg_tr)
		_slot_bgs.append(bg_tr)

		# Real tool icon texture.
		var icon: TextureRect = TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(10, 9)
		icon.size = Vector2(42, 42)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var init_tex: Texture2D = _tool_icon_for(default_ids[i])
		if init_tex != null:
			icon.texture = init_tex
		slot.add_child(icon)
		_slot_icons.append(icon)

		# Octagonal Art Nouveau border (T_Ability_Border transparent RGBA).
		var border_tr: TextureRect = TextureRect.new()
		border_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		border_tr.stretch_mode = TextureRect.STRETCH_SCALE
		border_tr.texture = border_tex
		border_tr.size = Vector2(62, 62)
		border_tr.modulate = Color(1.0, 1.0, 1.0, 0.96) if i == 0 else Color(0.46, 0.58, 0.92, 0.65)
		border_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(border_tr)
		_slot_borders.append(border_tr)

		# Crisp white square keycap badge at bottom-left of slot.
		var key_badge: PanelContainer = ThemeScript.white_keycap(default_keys[i], 11)
		key_badge.position = Vector2(-2, 44)
		key_badge.custom_minimum_size = Vector2(18, 18)
		slot.add_child(key_badge)
		_slot_key_lbls.append(key_badge.get_child(0) as Label)

		# Count / ∞ glyph at bottom-right (preserved slot_count_lbls).
		var count_lbl: Label = Label.new()
		count_lbl.text = "∞" if i == 3 else "0"
		count_lbl.position = Vector2(30, 42)
		count_lbl.custom_minimum_size = Vector2(28, 18)
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_lbl.add_theme_font_size_override("font_size", 13)
		count_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
		count_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		count_lbl.add_theme_constant_override("shadow_offset_x", 1)
		count_lbl.add_theme_constant_override("shadow_offset_y", 1)
		if _sans != null:
			count_lbl.add_theme_font_override("font", _sans)
		count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(count_lbl)
		slot_count_lbls.append(count_lbl)

	# [TAB] MAP   [MMB] [HOLD] PING MENU hint bar directly below hotbar.
	var hint_row: HBoxContainer = HBoxContainer.new()
	hint_row.name = "MapPingHintBar"
	hint_row.position = Vector2(0, 68)
	hint_row.add_theme_constant_override("separation", 6)
	hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar_anchor.add_child(hint_row)

	# W9-P3-C3: the keycap follows the active device/rebind (map_toggle).
	var map_key: PanelContainer = ThemeScript.white_keycap(InputGlyphs.text("map_toggle").to_upper(), 10)
	_hint_map_key_lbl = map_key.get_child(0) as Label
	hint_row.add_child(map_key)
	var map_lbl: Label = Label.new()
	# T05 l10n: authored ST_HUD rows (source -> Loc translation), literal fallback.
	map_lbl.text = UIStringsScript.st_upper("ST_HUD", "MapButtonLabel", "MAP")
	map_lbl.add_theme_font_size_override("font_size", 12)
	map_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 0.98, 0.88))
	if _sans != null:
		map_lbl.add_theme_font_override("font", _sans)
	hint_row.add_child(map_lbl)

	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(8, 1)
	hint_row.add_child(gap)

	var ping_key: PanelContainer = ThemeScript.white_keycap(InputGlyphs.text("ping_menu").to_upper(), 10)
	_hint_ping_key_lbl = ping_key.get_child(0) as Label
	hint_row.add_child(ping_key)
	var ping_lbl: Label = Label.new()
	ping_lbl.text = UIStringsScript.st_upper("ST_HUD", "PingButtonLabel", "[HOLD] PING MENU")
	ping_lbl.add_theme_font_size_override("font_size", 12)
	ping_lbl.add_theme_color_override("font_color", Color(0.62, 0.72, 0.94, 0.84))
	if _sans != null:
		ping_lbl.add_theme_font_override("font", _sans)
	hint_row.add_child(ping_lbl)


## Bottom-left stolen-key row, sitting just above the tool hotbar. Hidden when
## no keys are carried; names come from the shipped key-cabinet ids.
func _build_key_row(root: Control) -> void:
	_keys_anchor = Control.new()
	_keys_anchor.name = "BottomLeftKeyRow"
	_keys_anchor.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_keys_anchor.offset_left = 20.0
	_keys_anchor.offset_top = -136.0
	_keys_anchor.offset_right = 330.0
	_keys_anchor.offset_bottom = -110.0
	_keys_anchor.custom_minimum_size = Vector2(310, 26)
	_keys_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_keys_anchor)

	_keys_lbl = Label.new()
	_keys_lbl.name = "StolenKeysLabel"
	_keys_lbl.custom_minimum_size = Vector2(310, 26)
	_keys_lbl.add_theme_font_size_override("font_size", 13)
	_keys_lbl.add_theme_color_override("font_color", Color(0.95, 0.84, 0.55, 0.96))
	_keys_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.88))
	_keys_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_keys_lbl.add_theme_constant_override("shadow_offset_y", 1)
	if _sans != null:
		_keys_lbl.add_theme_font_override("font", _sans)
	_keys_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_lbl.visible = false
	_keys_anchor.add_child(_keys_lbl)


func _update_key_row(is_hub: bool) -> void:
	if _keys_lbl == null:
		return
	var names: Array[String] = GameState.stolen_key_display_names()
	var show: bool = (not is_hub) and not names.is_empty()
	var sig: String = "|".join(names)
	if sig == _keys_sig and show == _keys_shown:
		return
	_keys_sig = sig
	_keys_shown = show
	_keys_lbl.text = "  ·  ".join(names)
	_keys_lbl.visible = show


func _build_action_hints(root: Control) -> void:
	_action_hints_box = VBoxContainer.new()
	_action_hints_box.name = "BottomRightActionHints"
	_action_hints_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_action_hints_box.offset_left = -280.0
	_action_hints_box.offset_top = -124.0
	_action_hints_box.offset_right = -22.0
	_action_hints_box.offset_bottom = -18.0
	_action_hints_box.alignment = BoxContainer.ALIGNMENT_END
	_action_hints_box.add_theme_constant_override("separation", 6)
	_action_hints_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_action_hints_box)


func _build_den_lookat_card(root: Control) -> void:
	_den_card_panel = PanelContainer.new()
	_den_card_panel.name = "DenLookAtCard"
	_den_card_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_den_card_panel.offset_left = -140.0
	_den_card_panel.offset_top = 18.0
	_den_card_panel.offset_right = 140.0
	_den_card_panel.offset_bottom = 178.0
	_den_card_panel.custom_minimum_size = Vector2(280, 0)
	_den_card_panel.add_theme_stylebox_override("panel", ThemeScript.teal_card_style(1, 4, Color(0.018, 0.038, 0.052, 0.88), 14))
	_den_card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_den_card_panel.visible = false
	root.add_child(_den_card_panel)
	ThemeScript.add_teal_filigree(_den_card_panel, 3.0, 14.0)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_den_card_panel.add_child(vb)

	_den_card_title_lbl = Label.new()
	_den_card_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_den_card_title_lbl.add_theme_font_size_override("font_size", 22)
	_den_card_title_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	# Authored Heading_Handwritten role (CF_PermanentMarker).
	var hand_font: Font = ThemeScript.font_handwritten()
	if hand_font != null:
		_den_card_title_lbl.add_theme_font_override("font", hand_font)
	elif _serif != null:
		_den_card_title_lbl.add_theme_font_override("font", _serif)
	_den_card_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_den_card_title_lbl)

	vb.add_child(ThemeScript.teal_divider(0.55))

	_den_card_lines_box = VBoxContainer.new()
	_den_card_lines_box.add_theme_constant_override("separation", 5)
	_den_card_lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_den_card_lines_box)


func _build_fps_overlay(root: Control) -> void:
	fps_overlay = Label.new()
	fps_overlay.position = Vector2(24, 150)
	fps_overlay.custom_minimum_size = Vector2(620, 44)
	fps_overlay.add_theme_font_size_override("font_size", 13)
	fps_overlay.add_theme_color_override("font_color", Color(0.62, 1.0, 0.72))
	fps_overlay.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	fps_overlay.add_theme_constant_override("shadow_offset_x", 1)
	fps_overlay.add_theme_constant_override("shadow_offset_y", 1)
	if _sans != null:
		fps_overlay.add_theme_font_override("font", _sans)
	fps_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_overlay.visible = false
	root.add_child(fps_overlay)


func _build_lockpick_minigame(root: Control) -> void:
	_lockpick_root = Control.new()
	_lockpick_root.name = "LockpickMinigameOverlay"
	_lockpick_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lockpick_root.visible = false
	root.add_child(_lockpick_root)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.006, 0.010, 0.022, 0.56)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lockpick_root.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lockpick_root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(390, 440)
	panel.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(2, 8, Color(0.025, 0.052, 0.070, 0.92), 18))
	center.add_child(panel)
	ThemeScript.add_teal_filigree(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)

	_lockpick_title_lbl = Label.new()
	_lockpick_title_lbl.text = UIStringsScript.loc("Lockpicking").to_upper() ## PORT COPY (no authored row)
	_lockpick_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lockpick_title_lbl.add_theme_font_size_override("font_size", 20)
	_lockpick_title_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	if _serif != null:
		_lockpick_title_lbl.add_theme_font_override("font", _serif)
	vb.add_child(_lockpick_title_lbl)

	_lockpick_track_lbl = Label.new()
	_lockpick_track_lbl.text = UIStringsScript.loc("TUMBLER %d / %d") % [1, 1] ## PORT COPY (no authored row)
	_lockpick_track_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lockpick_track_lbl.add_theme_font_size_override("font_size", 13)
	_lockpick_track_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	vb.add_child(_lockpick_track_lbl)

	var dial_wrap: Control = Control.new()
	dial_wrap.custom_minimum_size = Vector2(280, 280)
	dial_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(dial_wrap)

	var bg_tex: TextureRect = _tex_rect("res://assets/ue/Raw/Art/Gameplay/Lockpicking/T_Lockpicking_BG.png", Vector2(260, 260))
	if bg_tex != null:
		bg_tex.position = Vector2(10, 10)
		bg_tex.modulate = Color(0.85, 0.92, 0.96, 0.88)
		dial_wrap.add_child(bg_tex)

	_lockpick_dial = LockpickDialDraw.new()
	_lockpick_dial.name = "LockpickDial"
	_lockpick_dial.position = Vector2(0, 0)
	_lockpick_dial.size = Vector2(280, 280)
	_lockpick_dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dial_wrap.add_child(_lockpick_dial)

	var keyhole: TextureRect = _tex_rect("res://assets/ue/Raw/Art/Gameplay/Lockpicking/T_Lockpicking_KeyholeCover.png", Vector2(96, 96))
	if keyhole != null:
		keyhole.position = Vector2(92, 92)
		keyhole.modulate = Color(0.82, 0.88, 0.94, 0.72)
		dial_wrap.add_child(keyhole)

	_lockpick_status_lbl = Label.new()
	# PORT COPY (no authored row): the port's minigame legend. The [KEY] tokens are
	# re-keyed live by InputGlyphs (keyboard text is unchanged: SPACE / LMB / ESC).
	_lockpick_status_lbl.text = InputGlyphs.format_legend(
		UIStringsScript.loc("[SPACE] / [LMB] STRIKE PIN   ·   [ESC] CANCEL"), LOCKPICK_LEGEND_ACTIONS)
	_lockpick_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lockpick_status_lbl.add_theme_font_size_override("font_size", 13)
	_lockpick_status_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	vb.add_child(_lockpick_status_lbl)


func _build_map_overlay(root: Control) -> void:
	_map_root = Control.new()
	_map_root.name = "TacticalMapOverlay"
	_map_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_root.visible = false
	root.add_child(_map_root)

	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.008, 0.012, 0.026, 0.72)
	_map_root.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	_map_panel = panel
	panel.custom_minimum_size = Vector2(760, 540)
	panel.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(2, 6, ThemeScript.TEAL_PANEL_BG, 18))
	center.add_child(panel)
	ThemeScript.add_teal_filigree(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	_map_title_lbl = Label.new()
	_map_title_lbl.text = UIStringsScript.loc("Tactical Map").to_upper() ## PORT COPY (no authored row)
	_map_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Authored MapTool_Handwritten role (CF_Caveat 28 -> 19).
	_map_title_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_MAP_HAND + 7)
	_map_title_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	var map_font: Font = ThemeScript.font_map_hand()
	if map_font != null:
		_map_title_lbl.add_theme_font_override("font", map_font)
	elif _serif != null:
		_map_title_lbl.add_theme_font_override("font", _serif)
	vb.add_child(_map_title_lbl)

	var legend: Label = Label.new()
	# PORT COPY (no authored row): the shipped MapTool legend rows are a different
	# set (Main Target / Loot Stash...). This is the port overlay's own legend and
	# is not presented as an authored row.
	legend.text = UIStringsScript.loc("● YOU    ◆ OBJECTIVE    • LOOT    ▲ GUARD    ◎ WAYPOINT PING")
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 12)
	legend.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED)
	vb.add_child(legend)

	_map_draw = TacticalMapDraw.new()
	_map_draw.name = "TacticalMapCanvas"
	_map_draw.custom_minimum_size = Vector2(700, 410)
	_map_draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_draw.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_draw.map_clicked.connect(_on_map_clicked)
	vb.add_child(_map_draw)

	var foot: Label = Label.new()
	_map_foot_lbl = foot
	# PORT COPY (no authored row): the overlay's footer legend, with live glyphs.
	foot.text = InputGlyphs.format_legend(
		UIStringsScript.loc("[LMB] PLACE WAYPOINT   ·   [TAB] / [ESC] CLOSE MAP"), MAP_LEGEND_ACTIONS)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 13)
	foot.add_theme_color_override("font_color", ThemeScript.TEAL_ACCENT)
	vb.add_child(foot)


func _build_ping_radial(root: Control) -> void:
	_ping_root = Control.new()
	_ping_root.name = "PingRadialOverlay"
	_ping_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ping_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ping_root.visible = false
	root.add_child(_ping_root)

	_ping_radial = PingRadialDraw.new()
	_ping_radial.name = "PingRadialWheel"
	_ping_radial.set_anchors_preset(Control.PRESET_CENTER)
	_ping_radial.offset_left = -120.0
	_ping_radial.offset_top = -120.0
	_ping_radial.offset_right = 120.0
	_ping_radial.offset_bottom = 120.0
	_ping_radial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ping_root.add_child(_ping_radial)

	var offsets: Array[Vector2] = [
		Vector2(-48, -82),
		Vector2(44, -10),
		Vector2(-48, 62),
		Vector2(-116, -10),
	]
	for i: int in range(PingRadialDraw.LABEL_COUNT):
		var lbl: Label = Label.new()
		lbl.text = ping_label_text(i)
		lbl.position = Vector2(120, 120) + offsets[i]
		lbl.custom_minimum_size = Vector2(96, 20)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", PingRadialDraw.COLORS[i])
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		if _sans != null:
			lbl.add_theme_font_override("font", _sans)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ping_radial.add_child(lbl)


func _build_mission_letter(root: Control) -> void:
	_letter_root = Control.new()
	_letter_root.name = "MissionStartLetter"
	_letter_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_letter_root.visible = false
	root.add_child(_letter_root)

	# KF13: the safe-room view stays visible, blurred and darkened, instead of
	# a flat dim over a legible HUD. The gameplay HUD is hidden while the letter
	# is open (so the blur samples only the 3D frame) and restored on close.
	_letter_blur_backdrop = ColorRect.new()
	_letter_blur_backdrop.name = "MissionLetterBlurBackdrop"
	_letter_blur_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_letter_blur_backdrop.color = Color.WHITE
	_letter_blur_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur_mat: ShaderMaterial = ShaderMaterial.new()
	var blur_shader: Shader = Shader.new()
	blur_shader.code = BRIEFING_BLUR_SHADER
	blur_mat.shader = blur_shader
	_letter_blur_backdrop.material = blur_mat
	_letter_root.add_child(_letter_blur_backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_letter_root.add_child(center)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	center.add_child(vb)

	var paper_box: Control = Control.new()
	paper_box.name = "MissionLetterPaperBox"
	paper_box.custom_minimum_size = BRIEFING_PAPER_SIZE
	paper_box.size = BRIEFING_PAPER_SIZE
	vb.add_child(paper_box)

	_letter_paper = TextureRect.new()
	_letter_paper.name = "MissionLetterPaper"
	_letter_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_letter_paper.stretch_mode = TextureRect.STRETCH_SCALE
	_letter_paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_letter_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper_lift: ShaderMaterial = ShaderMaterial.new()
	var paper_lift_shader: Shader = Shader.new()
	paper_lift_shader.code = BRIEFING_PAPER_LIFT_SHADER
	paper_lift.shader = paper_lift_shader
	_letter_paper.material = paper_lift
	var paper_src: Texture2D = null
	if ResourceLoader.exists("res://assets/ue/Raw/Art/UI/InGameScreens/T_Paper01.png"):
		paper_src = ResourceLoader.load("res://assets/ue/Raw/Art/UI/InGameScreens/T_Paper01.png") as Texture2D
	if paper_src != null:
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = paper_src
		atlas.region = BRIEFING_PAPER_SOURCE_CROP
		_letter_paper.texture = atlas
		paper_box.add_child(_letter_paper)
	else:
		var fallback_paper: ColorRect = ColorRect.new()
		fallback_paper.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback_paper.color = Color(0.84, 0.77, 0.68, 0.98)
		paper_box.add_child(fallback_paper)

	# KF13 right inner-margin scrollbar: a thin bright thumb over a darker track.
	var scroll_track: ColorRect = ColorRect.new()
	scroll_track.name = "MissionLetterScrollbarTrack"
	scroll_track.position = Vector2(BRIEFING_SCROLLBAR_X - 1.0, BRIEFING_SCROLLBAR_TOP)
	scroll_track.size = Vector2(5.0, BRIEFING_SCROLLBAR_HEIGHT)
	scroll_track.color = Color(0.36, 0.31, 0.26, 0.22)
	scroll_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper_box.add_child(scroll_track)
	_letter_scrollbar = Panel.new()
	_letter_scrollbar.name = "MissionLetterScrollbar"
	_letter_scrollbar.position = Vector2(BRIEFING_SCROLLBAR_X, BRIEFING_SCROLLBAR_TOP + 18.0)
	_letter_scrollbar.size = Vector2(3.0, BRIEFING_SCROLLBAR_HEIGHT - 46.0)
	_letter_scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumb_style: StyleBoxFlat = StyleBoxFlat.new()
	thumb_style.bg_color = Color(0.99, 0.97, 0.92, 0.86)
	thumb_style.set_corner_radius_all(1)
	_letter_scrollbar.add_theme_stylebox_override("panel", thumb_style)
	paper_box.add_child(_letter_scrollbar)

	var text_box: Control = Control.new()
	text_box.name = "MissionLetterText"
	text_box.position = BRIEFING_TEXT_ORIGIN
	text_box.size = Vector2(BRIEFING_TEXT_WIDTH, BRIEFING_PAPER_SIZE.y - BRIEFING_TEXT_ORIGIN.y - 26.0)
	text_box.custom_minimum_size = text_box.size
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper_box.add_child(text_box)

	_letter_title_lbl = Label.new()
	_letter_title_lbl.name = "MissionLetterTitle"
	_letter_title_lbl.text = UIStringsScript.loc("Esteemed Colleague -")
	_letter_title_lbl.position = Vector2.ZERO
	_letter_title_lbl.size = Vector2(BRIEFING_TEXT_WIDTH, 26.0)
	_letter_title_lbl.add_theme_font_size_override("font_size", BRIEFING_FONT_SIZE)
	_letter_title_lbl.add_theme_color_override("font_color", Color(0.11, 0.09, 0.08, 0.96))
	if _typewriter != null:
		_letter_title_lbl.add_theme_font_override("font", _typewriter)
	text_box.add_child(_letter_title_lbl)

	_letter_body_lbl = Label.new()
	_letter_body_lbl.name = "MissionLetterBody"
	_letter_body_lbl.position = Vector2(0.0, 30.0)
	_letter_body_lbl.size = Vector2(BRIEFING_TEXT_WIDTH, text_box.size.y - 30.0)
	_letter_body_lbl.custom_minimum_size = _letter_body_lbl.size
	_letter_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_letter_body_lbl.add_theme_font_size_override("font_size", BRIEFING_FONT_SIZE)
	_letter_body_lbl.add_theme_color_override("font_color", Color(0.12, 0.10, 0.08, 0.95))
	if _typewriter != null:
		_letter_body_lbl.add_theme_font_override("font", _typewriter)
	text_box.add_child(_letter_body_lbl)

	var btn_wrap: CenterContainer = CenterContainer.new()
	vb.add_child(btn_wrap)
	var cont_btn: Button = Button.new()
	cont_btn.name = "MissionLetterContinueBtn"
	cont_btn.text = ("[%s]  " + UIStringsScript.st_upper("ST_Screens", "Screen.Continue", "CONTINUE")) % InputGlyphs.text("jump")
	cont_btn.custom_minimum_size = Vector2(210, 42)
	ThemeScript.style_teal_button(cont_btn, false, 24)
	cont_btn.pressed.connect(_close_mission_letter)
	btn_wrap.add_child(cont_btn)


## Post-match rack-up, rebuilt from the authored ST_PostMatch (71 rows) and
## ST_Screens.PostMatch rows (T05). The old panel invented "CONTRACT COMPLETE /
## CAPTURED BY THE CONSTABULARY", "GHOST/SHADOW/BRAWLER" and a score line with
## no authored counterpart (RE-L-09).
func _build_result_panel(root: Control) -> void:
	var cc: CenterContainer = CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	result_panel = PanelContainer.new()
	result_panel.name = "PostMatchPanel"
	result_panel.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style(2, 8, ThemeScript.TEAL_PANEL_BG, 24))
	result_panel.visible = false
	cc.add_child(result_panel)
	ThemeScript.add_authored_frame(result_panel, true, 0)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.custom_minimum_size = Vector2(560, 0)
	vb.add_theme_constant_override("separation", 10)
	result_panel.add_child(vb)
	result_lbl = Label.new()
	result_lbl.name = "PostMatchStatus"
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_lbl.add_theme_font_size_override("font_size", ThemeScript.PX_HEADER)
	result_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
	var display: Font = ThemeScript.font_display()
	if display != null:
		result_lbl.add_theme_font_override("font", display)
	vb.add_child(result_lbl)
	vb.add_child(ThemeScript.teal_divider(0.55))
	_result_lines = VBoxContainer.new()
	_result_lines.name = "PostMatchLines"
	_result_lines.add_theme_constant_override("separation", 6)
	vb.add_child(_result_lines)
	# W9-P3-C1: the authored rack-up/XP screen (BPUI_PostMatchRackup_AllPlayers +
	# BPUI_EndMatchXPScreen) opens from the summary; the summary itself stays the
	# authored status + haul block (T05) so its contract is unchanged.
	_result_xp_btn = Button.new()
	_result_xp_btn.name = "PostMatchXPButton"
	_result_xp_btn.text = UIStringsScript.st_upper("ST_PostMatch", "XP.Breakdown", "XP BREAKDOWN")
	ThemeScript.style_teal_button(_result_xp_btn, false, 20)
	_result_xp_btn.pressed.connect(_open_post_match_xp)
	_result_xp_btn.visible = false
	vb.add_child(_result_xp_btn)
	_result_continue_btn = Button.new()
	_result_continue_btn.text = UIStringsScript.st_upper("ST_Screens", "Screen.Continue", "CONTINUE")
	ThemeScript.style_teal_button(_result_continue_btn, true, 24)
	_result_continue_btn.pressed.connect(func() -> void: _continue_to_den())
	vb.add_child(_result_continue_btn)


func _build_pause_menu(root: Control) -> void:
	_pause_root = Control.new()
	_pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.visible = false
	root.add_child(_pause_root)
	var dim: ColorRect = ColorRect.new()
	dim.name = "PauseDim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# KF30 measures the world band at mean luma 38.1 -> 5.2 (~86 % darkening).
	# The old 0.72 alpha only reached ~72 %; 0.86 is the authored dim.
	dim.color = Color(0.004, 0.006, 0.014, 0.86)
	_pause_root.add_child(dim)
	var tint: ColorRect = ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.10, 0.28, 0.30, 0.12)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_root.add_child(tint)

	pause_center = CenterContainer.new()
	pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.add_child(pause_center)
	pause_panel = PanelContainer.new()
	# 520 px: the authored MenuButton size (48 -> 32) needs room for
	# "RETURN TO THIEF'S DEN" on one line.
	_pause_panel_for_focus = pause_panel
	pause_panel.custom_minimum_size = Vector2(520, 0)
	pause_panel.add_theme_stylebox_override("panel", ThemeScript.teal_panel_style())
	pause_center.add_child(pause_panel)
	ThemeScript.add_authored_frame(pause_panel, false, 0)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	pause_panel.add_child(margin)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.custom_minimum_size = Vector2(440, 0)
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	var resume_btn: Button = Button.new()
	resume_btn.text = _loc_upper("Resume")
	ThemeScript.style_teal_button(resume_btn, true)
	resume_btn.pressed.connect(func() -> void: _set_paused(false))
	vb.add_child(resume_btn)
	var settings_btn: Button = Button.new()
	settings_btn.text = _loc_upper("Settings")
	ThemeScript.style_teal_button(settings_btn, false)
	settings_btn.pressed.connect(func() -> void:
		# Remember the pause control so closing settings returns focus to it
		# (no focus trapped behind the freed modal).
		FocusNavScript.remember()
		var sui: CanvasLayer = SettingsUIScript.new()
		add_child(sui)
		if sui.has_signal("closed"):
			sui.connect("closed", func() -> void:
				FocusNavScript.install(_pause_panel_for_focus)
				FocusNavScript.restore())
		if sui.has_method("open_settings"):
			sui.call("open_settings")
	)
	vb.add_child(settings_btn)
	var menu_btn: Button = Button.new()
	menu_btn.text = _loc_upper("Return to Thief's Den")
	ThemeScript.style_teal_button(menu_btn, false)
	# T05: this used to change_scene_to_file(main_menu.tscn) — the start screen,
	# not the Den — and bypassed the payout outbox entirely (hud.gd:1839-1846).
	# The Den is contract 1 (thieves_den), loaded through the mission scene.
	menu_btn.pressed.connect(func() -> void: _pause_return_to_den())
	vb.add_child(menu_btn)
	var quit_btn: Button = Button.new()
	quit_btn.text = _loc_upper("Quit To Desktop")
	ThemeScript.style_teal_button(quit_btn, false)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(quit_btn)
	var esc_row: HBoxContainer = HBoxContainer.new()
	esc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	esc_row.add_theme_constant_override("separation", 6)
	esc_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(esc_row)
	var esc_badge: PanelContainer = ThemeScript.keycap(InputGlyphs.bracket("pause"), 12)
	_pause_esc_key_lbl = esc_badge.get_child(0) as Label
	esc_row.add_child(esc_badge)
	var esc_lbl: Label = Label.new()
	esc_lbl.text = _loc_upper("Resume")
	esc_lbl.add_theme_font_size_override("font_size", 12)
	esc_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.78))
	esc_row.add_child(esc_lbl)
	var ver: Label = Label.new()
	ver.text = _pause_footer_text()
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(16, -30)
	# Authored Base_sessionlist role (Abel 24 -> 16).
	ver.add_theme_font_size_override("font_size", ThemeScript.PX_SESSION)
	var session_font: Font = ThemeScript.font_session()
	if session_font != null:
		ver.add_theme_font_override("font", session_font)
	ver.add_theme_color_override("font_color", Color(0.55, 0.60, 0.65, 0.92))
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_root.add_child(ver)


## KF30-exact pause footer: build number (no "v" prefix), difficulty label
## and the deterministic run seed published by GameState.
func _pause_footer_text() -> String:
	var build: String = VERSION_STRING
	if build.begins_with("v"):
		build = build.substr(1)
	var diff_lbl: String = UIStringsScript.st_text("ST_GeneralUI", "Mission.Difficulty.Easy", "Novice")
	var d: int = int(GameState.difficulty)
	if d == 2:
		diff_lbl = UIStringsScript.st_text("ST_GeneralUI", "Mission.Difficulty.Normal", "Thief")
	elif d >= 3:
		diff_lbl = UIStringsScript.st_text("ST_GeneralUI", "Mission.Difficulty.Hard", "Master Thief")
	return "%s   %s   %d" % [build, diff_lbl, int(GameState.active_map_seed)]


# =============================================================================
# Public API (Preserved + M3/M4 Interface Contracts)
# =============================================================================

func is_fps_overlay_visible() -> bool:
	return fps_overlay_enabled


func toggle_fps_overlay() -> void:
	fps_overlay_enabled = not fps_overlay_enabled
	_fps_refresh = 0.0
	if fps_overlay != null:
		fps_overlay.visible = fps_overlay_enabled
		if fps_overlay_enabled:
			_update_fps_overlay()
	print("TAT-2 perf overlay ", "ON" if fps_overlay_enabled else "OFF")


func toggle_pause() -> void:
	_toggle_pause()


func set_contract_info(info: Dictionary) -> void:
	contract_data = info


func update_loot(collected: int, needed: int, value: int) -> void:
	if _loot_lbl != null:
		_loot_lbl.text = "(£) %d" % value
	if obj_lbl == null:
		return
	var title: String = str(contract_data.get("title", "Contract"))
	# PORT COPY (no authored row): the objective wrapper format; the head is authored.
	obj_lbl.text = UIStringsScript.loc("%s: %s [%d/%d]\n  (£) %d") % [
		UIStringsScript.st_text("ST_PostMatch", "PostMatch.Mission", "Mission"),
		title, collected, needed, value]


func set_steal_prompt(text: String) -> void:
	_set_prompt(text)


func show_toast(text: String) -> void:
	show_clue_toast(UIStringsScript.loc("NOTICE"), text) ## PORT COPY (no authored row)


func show_result(won: bool, score: int, info: Dictionary) -> void:
	set_downed_display(false, 0.0)
	if _lockpick_active:
		_finish_lockpick(false)
	if _map_open:
		toggle_map_overlay()
	if _ping_open:
		close_ping_radial(false)
	if _letter_open:
		_close_mission_letter()
	result_panel.visible = true
	_last_won = won
	_last_score = maxi(score, 0)
	_last_info = info.duplicate(true)
	if _result_xp_btn != null:
		_result_xp_btn.visible = true
	var status_key: String = "PostMatch.Status.Escaped" if won else "PostMatch.Status.Caught"
	result_lbl.text = UIStringsScript.st_text("ST_PostMatch", status_key, "Escaped" if won else "Caught").to_upper()
	for c: Node in _result_lines.get_children():
		_result_lines.remove_child(c)
		c.queue_free()
	# Payout: mission_controller banks before show_result, so SaveSystem's
	# last_match is the authoritative record for this run.
	var payout: Dictionary = SaveSystem.get_last_match()
	if str(payout.get("match_id", "")) == "":
		var score_only: int = maxi(0, score)
		if score_only > 0:
			payout = {"kept": score_only, "original": score_only, "money_taken": score_only, "stashed": 0}
	var mission_line: String = _post_match_mission_line(won)
	if mission_line != "":
		_add_result_line(mission_line, ThemeScript.TEAL_TEXT, 18)
	var contract_line: String = _post_match_contract_line(won)
	if contract_line != "":
		_add_result_line(contract_line, ThemeScript.TEAL_MUTED, 16)
	var haul_header: String = UIStringsScript.st_text("ST_PostMatch", "PostMatch.Haul", "Ill-Gotten Gains")
	_add_result_line(haul_header.to_upper(), ThemeScript.GOLD, 18)
	var kept: int = int(payout.get("kept", 0))
	var original: int = int(payout.get("original", kept))
	var cash: int = int(payout.get("money_taken", kept))
	_add_result_line(UIStringsScript.st_text("ST_Screens", "Screen.PostMatch.LootEarned", "Loot Earned: £{0}").replace("{0}", str(kept)),
		ThemeScript.TEAL_TEXT, 16)
	if original > kept:
		_add_result_line(UIStringsScript.st_text("ST_Screens", "Screen.PostMatch.LootLost", "Loot Lost: £{0}").replace("{0}", str(original - kept)),
			ThemeScript.RED_INSUFFICIENT, 16)
	var cash_label: String = UIStringsScript.st_text("ST_Screens", "Screen.PostMatch.CashInHand", "Cash in Hand")
	_add_result_line("%s   £ %d" % [cash_label, cash], ThemeScript.TEAL_TITLE, 16)


## Open the authored post-match/XP screen with the *measured* award (the save
## delta since HUD creation), so the screen never recomputes a banked number.
func _open_post_match_xp() -> void:
	var script: GDScript = load("res://src/ui/post_match_ui.gd") as GDScript
	if script == null:
		return
	FocusNavScript.remember()
	var ui: CanvasLayer = script.new() as CanvasLayer
	# The HUD is a CanvasLayer; a same/default layer child has non-deterministic
	# ordering (audit-c1 F2). 25 is above the HUD and the result panel.
	ui.layer = 25
	add_child(ui)
	if ui.has_signal("closed"):
		ui.connect("closed", func() -> void:
			FocusNavScript.install(_root)
			FocusNavScript.restore())
	ui.call("open_result", _last_won, _last_score, _last_info, run_xp_awarded())


func _add_result_line(text: String, color: Color, font_size: int) -> void:
	if _result_lines == null or text.strip_edges() == "":
		return
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	_result_lines.add_child(lbl)


## Authored mission outcome row: PostMatch.Mission.<Map>.<MissionType>.<Result>.
## The key set is data (ST_PostMatch), so an unknown map/type simply shows no
## line instead of inventing prose.
func _post_match_mission_line(won: bool) -> String:
	var map_tag: String = ""
	match str(GameState.active_map_id):
		"guildhall": map_tag = "GuildHall"
		"old_manor": map_tag = "OldManor"
		_: map_tag = ""
	if map_tag == "":
		return ""
	var mission: String = str(GameState.active_mission_id)
	var type_tag: String = ""
	for candidate: String in ["LootTheRoom", "VaultHeist", "SetCollection", "FTUE"]:
		if mission.find(candidate) >= 0:
			type_tag = candidate
			break
	if type_tag == "":
		return ""
	var key: String = "PostMatch.Mission.%s.%s.%s" % [map_tag, type_tag, "Success" if won else "Failure"]
	return UIStringsScript.st_text("ST_PostMatch", key, "")


## Authored contract outcome row: PostMatch.Contract.<order>.<Result>.
func _post_match_contract_line(won: bool) -> String:
	var order: int = int(GameState.active_contract_order)
	if order <= 0:
		return ""
	var key: String = "PostMatch.Contract.%d.%s" % [order, "Success" if won else "Failure"]
	var row: String = UIStringsScript.st_text("ST_PostMatch", key, "")
	if row == "":
		return ""
	var head: String = UIStringsScript.st_text("ST_PostMatch", "PostMatch.Contract", "Contract")
	return "%s: %s" % [head, row]


func set_thief_vision(enabled: bool) -> void:
	if thief_vision_overlay != null:
		thief_vision_overlay.visible = enabled
	# The authored thief-vision highlight (thief_character._update_thief_vision ->
	# loot_item.set_xray_highlight) re-shows the port-invented world Label3D:
	# `label.visible = on or is_quest_item`. Re-hide it after the blueprint
	# toggle settles (deferred so it runs after every _process), so the authored
	# toast stays the only pickup text (audit-c4 5d).
	if enabled != _thief_vision_was_on:
		_thief_vision_was_on = enabled
		call_deferred("_hide_all_loot_labels")


func set_downed_display(active: bool, seconds: float) -> void:
	if downed_lbl == null:
		return
	downed_lbl.visible = active
	if active:
		downed_lbl.text = UIStringsScript.loc("DOWNED — %ds") % maxi(0, int(ceil(seconds))) ## PORT COPY (no authored row)


func show_clue_toast(title: String, body: String) -> void:
	if clue_toast_lbl == null:
		return
	var snippet: String = body if body.length() <= 110 else body.substr(0, 110) + "..."
	clue_toast_lbl.text = UIStringsScript.loc("CLUE — %s: %s") % [title, snippet] ## PORT COPY (no authored row)
	clue_toast_lbl.visible = true
	if is_inside_tree():
		get_tree().create_timer(5.5).timeout.connect(func() -> void:
			if is_instance_valid(clue_toast_lbl):
				clue_toast_lbl.visible = false
		)


func set_lockpick_progress(active: bool, progress: float, _lock_level: int) -> void:
	# P2-2: the LockpickDialDraw minigame is the live UI; this legacy bar stays
	# hidden and only retains its M2 value/property contract for callers.
	if lockpick_bar == null:
		return
	lockpick_bar.visible = false
	lockpick_bar.value = clampf(progress, 0.0, 1.0)


func get_soundwave_intensity() -> float:
	return _soundwave_energy


## M4 Contract: Start the circular/arc lockpicking timing minigame driven by
## DA_LockpickMinigameVariations.
## Alias kept for the LockpickWheel/LockpickArc node names referenced by the
## live-E2E parity capture (S15b circular_lockpick_minigame_ui).
func open_lockpick_minigame(lock_level: int, target_label: String, on_complete: Callable) -> void:
	start_lockpick_minigame(lock_level, target_label, on_complete)


func start_lockpick_minigame(lock_level: int, target_label: String, on_complete: Callable) -> void:
	if _lockpick_active:
		return
	_lockpick_level = clampi(lock_level, 0, 5)
	_lockpick_callback = on_complete
	_lockpick_tracks = _pick_lockpick_tracks(_lockpick_level)
	_lockpick_track_idx = 0
	_lockpick_cursor_t = 0.0
	_lockpick_jam_timer = 0.0
	_lockpick_active = true
	_init_lockpick_track(0)
	if _lockpick_title_lbl != null:
		var lbl: String = target_label.strip_edges()
		_lockpick_title_lbl.text = (lbl.to_upper() if lbl != "" else UIStringsScript.st_upper("ST_Lockpicking", "LockPicking.Lock.NoKeyLock", "Lock")) + UIStringsScript.loc(" — LV %d") % maxi(1, _lockpick_level)
	if _lockpick_root != null:
		_lockpick_root.visible = true
	_lockpick_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p: Node = _get_player()
	if p != null and p.has_method("set_lockpicking_active"):
		p.call("set_lockpicking_active", true)
	if DisplayServer.get_name() == "headless":
		_headless_auto_resolve_lockpick()


func _headless_auto_resolve_lockpick() -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.5).timeout
	if _lockpick_active:
		_finish_lockpick(true)


func is_lockpicking() -> bool:
	return _lockpick_active


## M4 Contract: Mission Start Letter overlay (T_Paper01 + [SPACE] CONTINUE).
## Alias kept for the Map Table look-at card name used by the Den diegetic
## flow and the live-E2E parity capture (S03 map_table_look_at_card).
func set_map_table_card(card: Dictionary) -> void:
	set_den_lookat_card(card)


func show_mission_letter(title: String, intro_text: String) -> void:
	if _letter_root == null:
		return
	var was_open: bool = _letter_open
	_letter_open = true
	_letter_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var header: String = title.strip_edges()
	var body_text: String = intro_text.strip_edges()
	# An authored briefing (KF13) carries its own salutation as line 1, so the
	# caller passes an empty title and the whole letter is laid out as one block.
	var own_salutation: bool = header == ""
	if _letter_title_lbl != null:
		_letter_title_lbl.visible = not own_salutation
		_letter_title_lbl.text = header if not own_salutation else ""
	if _letter_body_lbl != null:
		if own_salutation:
			var lines: PackedStringArray = format_briefing_layout(body_text)
			if lines.size() > 0:
				body_text = "\n".join(lines)
			_letter_body_lbl.position = Vector2.ZERO
			_letter_body_lbl.size = Vector2(BRIEFING_TEXT_WIDTH, BRIEFING_PAPER_SIZE.y - BRIEFING_TEXT_ORIGIN.y - 26.0)
			_letter_body_lbl.custom_minimum_size = _letter_body_lbl.size
		else:
			_letter_body_lbl.position = Vector2(0.0, 30.0)
			_letter_body_lbl.size = Vector2(BRIEFING_TEXT_WIDTH, BRIEFING_PAPER_SIZE.y - BRIEFING_TEXT_ORIGIN.y - 56.0)
			_letter_body_lbl.custom_minimum_size = _letter_body_lbl.size
		_letter_body_lbl.text = body_text
	if not was_open:
		_set_letter_hud_hidden(true)
	_letter_root.visible = true


## KF13 layout: wrap the authored letter at the measured parchment text width
## with the authored typewriter face. TextServer (not Label.get_line_count,
## which needs a draw pass) is the source of truth so a headless test can pin
## the reference's 11-line layout.
func format_briefing_layout(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var body: String = text.replace("\r\n", "\n").replace("\r", "\n").strip_edges()
	if body == "":
		return out
	if _typewriter == null:
		return body.split("\n")
	var ts: TextServer = TextServerManager.get_primary_interface()
	var rid: RID = ts.create_shaped_text()
	ts.shaped_text_add_string(rid, body, _typewriter.get_rids(), BRIEFING_FONT_SIZE)
	var breaks: PackedInt32Array = ts.shaped_text_get_line_breaks(
		rid, BRIEFING_TEXT_WIDTH, 0, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	)
	for i: int in range(0, breaks.size() - 1, 2):
		out.append(body.substr(breaks[i], breaks[i + 1] - breaks[i]).strip_edges())
	ts.free_rid(rid)
	return out


## Hide every HUD sibling while the letter is open (KF13 has no gameplay HUD
## behind the parchment) and restore the exact prior visibility on close.
func _set_letter_hud_hidden(hide_rest: bool) -> void:
	if _root == null:
		return
	if hide_rest:
		_letter_hud_visibility.clear()
		for ch: Node in _root.get_children():
			if ch == _letter_root or not (ch is CanvasItem):
				continue
			var item: CanvasItem = ch as CanvasItem
			_letter_hud_visibility[item] = item.visible
			item.visible = false
	else:
		for item_v: Variant in _letter_hud_visibility.keys():
			if item_v is CanvasItem and is_instance_valid(item_v):
				(item_v as CanvasItem).visible = bool(_letter_hud_visibility[item_v])
		_letter_hud_visibility.clear()


func is_mission_letter_open() -> bool:
	return _letter_open


## W1S: register/clear the NPC conversation modal. The dialogue node calls this
## on open/close; null clears. Kept as a reference (not a bool) so a stale
## freed dialogue can never keep the HUD thinking a modal is open.
func set_npc_dialogue(node: Node) -> void:
	if node == null and _npc_dialogue != null:
		_npc_dialogue_closed_frame = Engine.get_process_frames()
	_npc_dialogue = node


func is_npc_dialogue_open() -> bool:
	if _npc_dialogue == null or not is_instance_valid(_npc_dialogue):
		return false
	if not _npc_dialogue.has_method("is_open"):
		return false
	return bool(_npc_dialogue.call("is_open"))


## M4 Contract: Render Thieves' Den diegetic Map Table / Telescope look-at card.
func set_den_lookat_card(card: Dictionary) -> void:
	if _den_card_panel == null or _den_card_lines_box == null:
		return
	var show_card: bool = card.get("visible", false) == true
	_den_card_panel.visible = show_card
	_den_bottom_hints.clear()
	if not show_card:
		return
	var title_txt: String = str(card.get("title", "")).strip_edges()
	if _den_card_title_lbl != null:
		_den_card_title_lbl.text = title_txt.to_upper()
		_den_card_title_lbl.visible = title_txt != ""
	for c: Node in _den_card_lines_box.get_children():
		c.queue_free()
	var lines_v: Variant = card.get("lines", null)
	if lines_v is Array and not (lines_v as Array).is_empty():
		for item_v: Variant in (lines_v as Array):
			if item_v is Dictionary:
				var ld: Dictionary = item_v as Dictionary
				_add_den_card_row(str(ld.get("key", "")), str(ld.get("label", "")), str(ld.get("value", "")))
			else:
				_add_den_card_row("", str(item_v), "")
	else:
		if card.has("difficulty"):
			_add_den_card_row("H", UIStringsScript.st_text("ST_ThievesDen", "CityMap.DifficultyHeader", "Difficulty:"), str(card.get("difficulty", "Novice")))
		if card.has("mode"):
			_add_den_card_row("R", UIStringsScript.st_text("ST_ThievesDen", "CityMap.GameModeHeader", "Mode:"), str(card.get("mode", "Solo")))
		if card.has("prompt"):
			_add_den_card_row("F", str(card.get("prompt", UIStringsScript.st_text("ST_ThievesDen", "CityMap.JoinLobby", "Prepare for Mission"))), "")
	var bh_v: Variant = card.get("bottom_hints", null)
	if bh_v is Array:
		_den_bottom_hints = (bh_v as Array).duplicate()


func toggle_map_overlay() -> void:
	if _map_root == null:
		return
	if not _map_open and (get_tree().paused or _lockpick_active or _letter_open or is_npc_dialogue_open()):
		return
	_map_open = not _map_open
	_map_root.visible = _map_open
	if _map_open:
		_map_prev_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh_tactical_map()
	else:
		Input.mouse_mode = _map_prev_mouse


func is_map_open() -> bool:
	return _map_open


func open_ping_radial() -> void:
	if _ping_root == null or get_tree().paused or _lockpick_active or _letter_open or _map_open or is_npc_dialogue_open():
		return
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("open")
	_ping_open = true
	_ping_selected = 0
	_ping_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _ping_radial != null:
		_ping_radial.selected_idx = _ping_selected
		_ping_radial.queue_redraw()
	_ping_root.visible = true


func close_ping_radial(commit: bool = true) -> void:
	if not _ping_open:
		return
	_ping_open = false
	if _ping_root != null:
		_ping_root.visible = false
	Input.mouse_mode = _ping_prev_mouse
	if commit:
		_commit_radial_ping(_ping_selected)


func is_ping_radial_open() -> bool:
	return _ping_open


func get_active_pings() -> Array[Dictionary]:
	return _active_pings


# =============================================================================
# Input Handling
# =============================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo:
			if kev.keycode == KEY_F3 or kev.physical_keycode == KEY_F3:
				toggle_fps_overlay()
				_mark_input_handled()
				return
			# Mission Start Letter input
			if _letter_open:
				if kev.keycode == KEY_SPACE or kev.keycode == KEY_ENTER or kev.keycode == KEY_ESCAPE:
					_close_mission_letter()
					_mark_input_handled()
				return
			# Lockpicking minigame input
			if _lockpick_active:
				if kev.keycode == KEY_ESCAPE:
					# W9-P2 C1: ESC is the pick's CANCEL. Stamp the frame
					# before finishing so the `pause` action bound to the same
					# key cannot also open the pause menu in `_process`.
					_pause_consumed_frame = Engine.get_process_frames()
					_finish_lockpick(false)
					_mark_input_handled()
					return
				if kev.keycode == KEY_SPACE:
					_attempt_lockpick_strike()
					_mark_input_handled()
					return
			# Map overlay close
			if _map_open:
				if kev.keycode == KEY_TAB or kev.keycode == KEY_ESCAPE:
					toggle_map_overlay()
					_mark_input_handled()
					return
			# Ping radial number selection
			if _ping_open:
				if kev.keycode == KEY_ESCAPE:
					close_ping_radial(false)
					_mark_input_handled()
					return
				if kev.keycode >= KEY_1 and kev.keycode <= KEY_4:
					_ping_selected = int(kev.keycode - KEY_1)
					close_ping_radial(true)
					_mark_input_handled()
					return
			# Map toggle via TAB or map_toggle action
			if GameState.state == "playing" and not get_tree().paused and not is_npc_dialogue_open():
				if (InputMap.has_action("map_toggle") and event.is_action_pressed("map_toggle")) or kev.keycode == KEY_TAB:
					toggle_map_overlay()
					_mark_input_handled()
					return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if _lockpick_active and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_attempt_lockpick_strike()
			_mark_input_handled()
			return
		if GameState.state == "playing" and not get_tree().paused and not _lockpick_active and not _letter_open and not _map_open and not is_npc_dialogue_open():
			var is_ping_btn: bool = mb.button_index == MOUSE_BUTTON_MIDDLE or (InputMap.has_action("ping_menu") and (event.is_action_pressed("ping_menu") or event.is_action_released("ping_menu")))
			if is_ping_btn:
				if mb.pressed:
					open_ping_radial()
				elif _ping_open:
					close_ping_radial(true)
				_mark_input_handled()
				return
		if _ping_open and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close_ping_radial(true)
			_mark_input_handled()
			return

	if event is InputEventMouseMotion and _ping_open:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var vp: Viewport = get_viewport()
		if vp != null:
			var center: Vector2 = vp.get_visible_rect().size * 0.5
			var rel: Vector2 = mm.position - center
			if rel.length() > 18.0:
				var deg: float = rad_to_deg(atan2(rel.y, rel.x))
				# Top: [-135, -45), Right: [-45, 45), Bottom: [45, 135), Left: else
				if deg >= -135.0 and deg < -45.0:
					_ping_selected = 0
				elif deg >= -45.0 and deg < 45.0:
					_ping_selected = 1
				elif deg >= 45.0 and deg < 135.0:
					_ping_selected = 2
				else:
					_ping_selected = 3
				if _ping_radial != null:
					_ping_radial.selected_idx = _ping_selected
					_ping_radial.queue_redraw()


func _mark_input_handled() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_set_paused(not get_tree().paused)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if MobileProfile.is_mobile() and GameState.state == "playing" and not get_tree().paused:
			_set_paused(true)


# =============================================================================
# Per-Frame Update
# =============================================================================

func _process(delta: float) -> void:
	if fps_overlay_enabled:
		_fps_refresh += delta
		if _fps_refresh >= 0.25:
			_fps_refresh = 0.0
			_update_fps_overlay()

	if InputMap.has_action("pause") and Input.is_action_just_pressed("pause"):
		if Engine.get_process_frames() == _pause_consumed_frame:
			# The lockpick's own `_input` consumed this Escape (W9-P2 C1);
			# set_input_as_handled() does not clear the Input action state, so
			# the pause action is still "just pressed" this frame.
			pass
		elif Engine.get_process_frames() == _npc_dialogue_closed_frame:
			# The dialogue consumed this Escape in its own _input.
			pass
		elif is_npc_dialogue_open():
			# Escape is the pause key: while a conversation is open it closes
			# the conversation instead of pausing the mission.
			_npc_dialogue.call("close")
		elif _letter_open:
			_close_mission_letter()
		elif _lockpick_active:
			_finish_lockpick(false)
		elif _map_open:
			toggle_map_overlay()
		elif _ping_open:
			close_ping_radial(false)
		else:
			_toggle_pause()

	if get_tree().paused:
		return

	# Tick active pings even when menu/playing.
	_tick_active_pings(delta)

	# Tick lockpicking minigame cursor.
	if _lockpick_active:
		_tick_lockpick(delta)

	if GameState.state != "playing":
		return

	var is_hub: bool = GameState.active_contract_order <= 1
	var p: Node3D = _get_player()

	_update_objectives_and_loot(is_hub)
	_update_phase_banner(is_hub)
	_update_key_row(is_hub)
	_update_stealth_ball_and_soundwaves(p, delta, is_hub)
	_update_portrait_plate()

	if p != null:
		var deg: float = fposmod(-p.rotation_degrees.y, 360.0)
		update_compass_heading(deg)

		_update_health_and_stamina(p, is_hub)
		_update_tool_hotbar_and_reticle(p, is_hub)

		if disguise_vignette != null:
			disguise_vignette.visible = p.get("disguise_active") == true
		if p.has_method("is_thief_vision_active"):
			set_thief_vision(p.call("is_thief_vision_active") == true)
		if p.has_method("downed_remaining") and downed_lbl != null:
			var downed_now: bool = p.get("is_downed") == true
			set_downed_display(downed_now, float(p.call("downed_remaining")))
		if is_npc_dialogue_open():
			# The conversation panel owns the frame; no world prompt behind it.
			_set_prompt("")
			_set_secondary_prompt("")
		elif p.has_method("get_look_interact_prompt"):
			_set_prompt(str(p.call("get_look_interact_prompt")))
			if p.has_method("get_look_secondary_prompt"):
				_set_secondary_prompt(str(p.call("get_look_secondary_prompt")))
			else:
				_set_secondary_prompt("")

		_update_compass_pois(p)
		_update_guard_pips_and_offscreen(p, is_hub)
		_update_world_ping_markers(p)
		if _map_open:
			_refresh_tactical_map()


func _update_objectives_and_loot(is_hub: bool) -> void:
	if _loot_lbl != null:
		_loot_lbl.visible = not is_hub
		var goal_v: Variant = GameState.get("loot_goal")
		var goal: int = int(goal_v) if (goal_v is int or goal_v is float) else 0
		if GameState.free_play:
			# Reference Contract Inactive counter: just the take, no "/ £ goal".
			_loot_lbl.text = "(£) %d" % GameState.loot_value
		elif goal > 0:
			_loot_lbl.text = "(£) %d / £ %d" % [GameState.loot_value, goal]
		else:
			_loot_lbl.text = "(£) %d" % GameState.loot_value

	if obj_lbl == null:
		return
	if is_hub:
		obj_lbl.text = ""
		return

	var objs_v: Variant = GameState.get("mission_objectives")
	# Free play: the reference prints the objective inline with its progress in
	# the same bracket ("Mission: Steal 4,000 in loot value[0/4,000]") and no
	# timer suffix or ❧ sub-line. Normal contracts keep the formatter below.
	if GameState.free_play:
		var fp_label: String = UIStringsScript.loc_template("Steal {Amount} in loot value", {"Amount": GameState.format_thousands(maxi(GameState.loot_goal, 0))})
		var fp_cur: int = 0
		var fp_tgt: int = maxi(GameState.loot_goal, 0)
		if objs_v is Array:
			for o_v: Variant in (objs_v as Array):
				if o_v is Dictionary:
					var od: Dictionary = o_v as Dictionary
					if str(od.get("id", "")) == "cleanout_loot":
						fp_label = str(od.get("label", fp_label))
						fp_cur = int(od.get("current", 0))
						fp_tgt = int(od.get("target", fp_tgt))
						break
		obj_lbl.text = UIStringsScript.loc("%s: %s[%s/%s]") % [
			UIStringsScript.st_text("ST_PostMatch", "PostMatch.Mission", "Mission"),
			fp_label, GameState.format_thousands(fp_cur), GameState.format_thousands(fp_tgt)]
		return

	var timing: String = ""
	if GameState.phase == GameState.PHASE_ENDGAME:
		timing = "  (%s)" % (UIStringsScript.loc("DOOR ") + phase_countdown_text()) ## PORT COPY (no authored row)
	elif GameState.run_time_limit > 0.0:
		timing = "  (%s)" % phase_countdown_text()

	if objs_v is Array and not (objs_v as Array).is_empty():
		var objs: Array = objs_v as Array
		var done_cnt: int = 0
		var sub_lines: Array[String] = []
		for o_v: Variant in objs:
			if o_v is Dictionary:
				var od: Dictionary = o_v as Dictionary
				var done: bool = od.get("done", false) == true
				if done:
					done_cnt += 1
				var mark: String = "✓" if done else "❧"
				sub_lines.append("   %s %s" % [mark, str(od.get("label", UIStringsScript.loc("Objective")))]) ## PORT COPY fallback
		var hdr_title: String = str(contract_data.get("title", UIStringsScript.loc("Heist"))) ## PORT COPY fallback
		obj_lbl.text = UIStringsScript.loc("%s: %s [%d/%d]%s\n%s") % [
			UIStringsScript.st_text("ST_PostMatch", "PostMatch.Mission", "Mission"),
			hdr_title, done_cnt, objs.size(), timing, "\n".join(sub_lines)]
		return

	var title: String = str(contract_data.get("title", UIStringsScript.st_template("ST_Screens", "Screen.Contract.Number", "Contract #{number}", {"number": GameState.active_contract_order})))
	var item: String = str(contract_data.get("quest_item", UIStringsScript.loc("Objective"))) ## PORT COPY fallback
	var _loot_goal: int = maxi(GameState.loot_goal, 0)
	var _loot_status: String = "❧ %s  (£) %d / £ %d" % [item, GameState.loot_value, _loot_goal] if _loot_goal > 0 else "❧ %s" % item
	var status: String = UIStringsScript.loc("Reach Escape Gate") if GameState.are_all_objectives_complete() else _loot_status ## PORT COPY (no authored row)
	obj_lbl.text = UIStringsScript.loc("%s: %s%s\n   %s") % [
		UIStringsScript.st_text("ST_PostMatch", "PostMatch.Mission", "Mission"), title, timing, status]


## W7E: active-phase countdown in the authored MM:SS form (3300 s -> "55:00",
## 1200 s -> "20:00"). Empty when the active phase is unlimited/resolved.
func phase_countdown_text() -> String:
	var limit: float = GameState.phase_time_limit()
	if limit <= 0.0:
		return ""
	var remain: float = maxf(0.0, GameState.phase_time_remaining())
	return "%02d:%02d" % [int(remain) / 60, int(remain) % 60]


## W7E: endgame door banner. Empty outside the endgame phase so the banner is
## never shown over the main window or the result screen.
func door_warning_text() -> String:
	if GameState.phase != GameState.PHASE_ENDGAME:
		return ""
	var countdown: String = phase_countdown_text()
	if countdown == "":
		return UIStringsScript.loc("THE MAGIC DOOR IS OPEN") ## PORT COPY (no authored row)
	return UIStringsScript.loc("THE MAGIC DOOR IS OPEN — %s BEFORE IT COLLAPSES") % countdown ## PORT COPY (no authored row)


func _update_phase_banner(is_hub: bool) -> void:
	if door_lbl == null:
		return
	var show: bool = not is_hub and GameState.state == "playing" and GameState.phase == GameState.PHASE_ENDGAME
	door_lbl.visible = show
	if show:
		door_lbl.text = door_warning_text()


func _update_stealth_ball_and_soundwaves(p: Node3D, delta: float, is_hub: bool) -> void:
	if _stealth_holder != null:
		_stealth_holder.visible = not is_hub
	if is_hub:
		return
	var target_vis: float = clampf(GameState.player_light_visibility, 0.0, 1.0)
	_vis_smooth = lerpf(_vis_smooth, target_vis, clampf(delta * 8.0, 0.0, 1.0))
	if _stealth_orb_mat != null:
		_stealth_orb_mat.set_shader_parameter("visibility", _vis_smooth)
		# UI3 directional warm sector: the player publishes the strongest
		# nearby light direction; convert it to canvas angle (+Y down).
		var sector_angle: float = 0.0
		var sector_strength: float = 0.0
		if p != null:
			var dir_v: Variant = p.get("light_sector_dir")
			var strength_v: Variant = p.get("light_sector_strength")
			var strength: float = float(strength_v) if (strength_v is float or strength_v is int) else 0.0
			var cam3d: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
			if dir_v is Vector3 and cam3d != null:
				var dir: Vector3 = dir_v
				if dir.length_squared() > 0.0001:
					dir = dir.normalized()
					var cam_right: Vector3 = cam3d.global_transform.basis.x
					var cam_up: Vector3 = cam3d.global_transform.basis.y
					sector_angle = atan2(-dir.dot(cam_up), dir.dot(cam_right))
					sector_strength = clampf(strength, 0.0, 1.0)
		_stealth_orb_mat.set_shader_parameter("sector_angle", sector_angle)
		_stealth_orb_mat.set_shader_parameter("sector_strength", sector_strength)
	if stealth_gem != null:
		stealth_gem.modulate = Color(0.45, 0.56, 0.96, 0.96).lerp(Color(0.96, 0.90, 0.62, 1.0), _vis_smooth * 0.65)
	if _soundwave_energy > 0.0:
		_soundwave_energy = maxf(0.0, _soundwave_energy - delta * 1.35)
		_soundwave_phase = fposmod(_soundwave_phase + delta * 2.2, 1.0)
	if _soundwaves_draw != null:
		_soundwaves_draw.energy = _soundwave_energy
		_soundwaves_draw.phase = _soundwave_phase
		_soundwaves_draw.queue_redraw()


func _update_portrait_plate() -> void:
	if _thief_name_lbl != null:
		_thief_name_lbl.text = _player_display_name()
	if _level_badge_lbl != null:
		var saved_lvl: Variant = SaveSystem.data.get("level", 1)
		if saved_lvl is float or saved_lvl is int:
			_level_badge_lbl.text = "%d" % int(saved_lvl)


## Player handle (explicit save name, else the authored thief title). The
## portrait plate never shows an empty label or the capture persona.
func _player_display_name() -> String:
	return GameState.player_display_name()


func _loc(source: String) -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc != null and loc.has_method("t"):
		return str(loc.call("t", source))
	return source


func _loc_upper(source: String) -> String:
	return _loc(source).to_upper()


func _update_health_and_stamina(p: Node3D, is_hub: bool) -> void:
	if _hp_container != null:
		_hp_container.visible = not is_hub
	var mhp_v: Variant = p.get("max_health")
	var hp_v: Variant = p.get("health")
	var mst_v: Variant = p.get("max_stamina")
	var st_v: Variant = p.get("stamina")
	var mhp: float = maxf(1.0, float(mhp_v) if (mhp_v is float or mhp_v is int) else 100.0)
	var hp: float = float(hp_v) if (hp_v is float or hp_v is int) else mhp
	var mst: float = maxf(1.0, float(mst_v) if (mst_v is float or mst_v is int) else 100.0)
	var st: float = float(st_v) if (st_v is float or st_v is int) else mst

	var hp_frac: float = clampf(hp / mhp, 0.0, 1.0)
	# KF12/KF14: the ornate Health Bar stays hidden at 100% HP and only
	# appears once damage is taken.
	if _hp_container != null:
		_hp_container.visible = (not is_hub) and hp_frac < 0.999
	if hp_fill != null:
		hp_fill.size.x = HP_BAR_MAX_W * hp_frac
		hp_fill.visible = hp_frac > 0.001
	if _hp_clip != null:
		_hp_clip.size.x = HP_BAR_MAX_W
	# Damage overlay, never a permanent decoration: appears below half health
	# (KF19 shows the bar clean at full; the authored splatter is a hurt state).
	if _hp_splatter != null:
		_hp_splatter.visible = hp_frac < HP_SPLATTER_THRESHOLD and hp_frac > 0.001
	if p.has_method("health_block_percentages"):
		var blocks_v: Variant = p.call("health_block_percentages")
		if blocks_v is Array and (blocks_v as Array) != _hp_block_cache:
			_rebuild_hp_block_ticks(blocks_v as Array)

	var st_frac: float = clampf(st / mst, 0.0, 1.0)
	if stam_fill != null:
		stam_fill.size.x = STAM_BAR_MAX_W * st_frac
		var stam_alpha: float = 0.22 if st_frac > 0.98 else 0.88
		stam_fill.modulate.a = stam_alpha
		if _stam_bg != null:
			_stam_bg.modulate.a = stam_alpha


func _update_tool_hotbar_and_reticle(p: Node3D, is_hub: bool) -> void:
	## P2-2: legacy hotbar_lbl is a hidden API-compat stub (e2e_tier2_boundaries
	## asserts its existence). The octagonal hotbar below is the live UI, so no
	## per-frame text is pushed here anymore.
	var ch_v: Variant = p.get("charges")
	var ch: Dictionary = ch_v as Dictionary if ch_v is Dictionary else {}

	if p.has_method("get_tool_slots"):
		var slots_v: Variant = p.call("get_tool_slots")
		if slots_v is Array:
			var slots: Array = slots_v as Array
			var n: int = mini(slots.size(), slot_count_lbls.size())
			for i: int in range(n):
				var sv: Variant = slots[i]
				if not (sv is Dictionary):
					continue
				var sd: Dictionary = sv as Dictionary
				var tid: String = str(sd.get("id", ""))
				var cnt: int = int(sd.get("count", 0))
				var is_active: bool = sd.get("active", false) == true
				slot_count_lbls[i].text = "∞" if cnt < 0 else str(cnt)
				if i < _slot_icons.size() and i < _slot_last_ids.size() and _slot_last_ids[i] != tid:
					_slot_last_ids[i] = tid
					var tex: Texture2D = _tool_icon_for(tid)
					if tex != null:
						_slot_icons[i].texture = tex
				if i < _slot_borders.size():
					_slot_borders[i].modulate = Color(1.0, 1.0, 1.0, 1.0) if is_active else Color(0.46, 0.58, 0.92, 0.62)
				if i < _slot_icons.size():
					_slot_icons[i].modulate = Color(1.0, 1.0, 1.0, 1.0) if is_active else Color(0.75, 0.82, 0.96, 0.80)
	else:
		if slot_count_lbls.size() >= 4:
			slot_count_lbls[0].text = str(int(ch.get("grapple", ch.get("slithersap", 0))))
			slot_count_lbls[1].text = str(int(ch.get("smoke_bomb", 0)))
			slot_count_lbls[2].text = str(int(ch.get("slithersap", ch.get("pickpocket_fairy", 0))))
			slot_count_lbls[3].text = "∞"

	# Dynamic reticle & bottom-right contextual hints.
	var ret_state: Dictionary = {}
	if p.has_method("get_active_reticle_state"):
		var rs_v: Variant = p.call("get_active_reticle_state")
		if rs_v is Dictionary:
			ret_state = rs_v as Dictionary
	var mode_str: String = str(ret_state.get("mode", p.call("get_equipped_tool") if p.has_method("get_equipped_tool") else "blackjack"))
	var target_valid: bool = ret_state.get("target_valid", false) == true
	var crank_prog: float = float(ret_state.get("crank_progress", 0.0))
	var crank_act: bool = ret_state.get("crank_active", false) == true
	var hold_prog_v: Variant = p.get("interact_hold_progress")
	var hold_prog: float = float(hold_prog_v) if (hold_prog_v is float or hold_prog_v is int) else 0.0

	if _reticle_draw != null:
		_reticle_draw.mode = "blackjack" if is_hub else mode_str
		_reticle_draw.target_valid = target_valid
		_reticle_draw.crank_progress = crank_prog
		_reticle_draw.crank_active = crank_act
		_reticle_draw.hold_progress = hold_prog
		_reticle_draw.queue_redraw()
	if _crank_prompt_lbl != null:
		_crank_prompt_lbl.visible = (not is_hub) and mode_str == "zipwire" and (crank_act or crank_prog > 0.001)

	var hints_to_show: Array = []
	if is_hub and not _den_bottom_hints.is_empty():
		hints_to_show = _den_bottom_hints
	elif not is_hub:
		var hints_v: Variant = ret_state.get("hints", [])
		if hints_v is Array:
			for hv: Variant in (hints_v as Array):
				if hv is Dictionary:
					var hd: Dictionary = hv as Dictionary
					# Keep Vistara Diamond viewport clean (matches 20261118093123_1.jpg).
					if mode_str == "vistara_diamond" and str(hd.get("key", "")) == "4":
						continue
					hints_to_show.append(hd)
	_refresh_action_hints(hints_to_show)


func _refresh_action_hints(hints: Array) -> void:
	if _action_hints_box == null:
		return
	var sig_parts: PackedStringArray = PackedStringArray()
	for hv: Variant in hints:
		if hv is Dictionary:
			var hd: Dictionary = hv as Dictionary
			sig_parts.append("%s|%s|%s" % [str(hd.get("key", "")), str(hd.get("label", "")), str(hd.get("enabled", true) == true)])
	var sig: String = ";".join(sig_parts)
	if sig == _last_hints_sig:
		return
	_last_hints_sig = sig
	for c: Node in _action_hints_box.get_children():
		# remove_child before queue_free: queue_free alone leaves the old rows
		# drawing for one more frame beside the new ones (C3-12's same-frame
		# double draw, the "LAUNCH / HOLD CRANK" overprint class).
		_action_hints_box.remove_child(c)
		c.queue_free()
	for hv2: Variant in hints:
		if not (hv2 is Dictionary):
			continue
		var hd2: Dictionary = hv2 as Dictionary
		var row: HBoxContainer = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size = Vector2(0, 20)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var enabled: bool = hd2.get("enabled", true) == true
		var lbl: Label = Label.new()
		lbl.text = str(hd2.get("label", "")).to_upper()
		lbl.add_theme_font_size_override("font_size", 14)
		# Prompt contrast (L3-14): the disabled state used 48 % alpha over lit
		# walls (measured ~2 % luminance separation). Both states now carry a
		# near-white body and a 2 px black shadow; no type/colour restyle.
		lbl.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0, 1.0) if enabled else Color(0.80, 0.85, 0.94, 0.82))
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
		lbl.add_theme_constant_override("shadow_offset_x", 2)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
		if _sans != null:
			lbl.add_theme_font_override("font", _sans)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)
		var key_str: String = str(hd2.get("key", "")).to_upper()
		if key_str != "":
			var badge: PanelContainer = ThemeScript.white_keycap(key_str, 11)
			badge.modulate = Color(1, 1, 1, 0.96) if enabled else Color(0.8, 0.85, 0.95, 0.48)
			row.add_child(badge)
		_action_hints_box.add_child(row)


# =============================================================================
# Compass PoIs, Guard Pips & Offscreen Threat Arcs
# =============================================================================

func _init_alert_textures() -> void:
	var sheet: Texture2D = ResourceLoader.load("res://assets/ue/Raw/Art/UI/HUD/GuardPips/T_GuardPip_SpriteSheet.png") as Texture2D
	if sheet != null:
		_pip_tex_warn = AtlasTexture.new()
		_pip_tex_warn.atlas = sheet
		_pip_tex_warn.region = Rect2(512, 0, 128, 128)
		_pip_tex_susp = AtlasTexture.new()
		_pip_tex_susp.atlas = sheet
		_pip_tex_susp.region = Rect2(640, 128, 128, 128)
		_pip_tex_alert = AtlasTexture.new()
		_pip_tex_alert.atlas = sheet
		_pip_tex_alert.region = Rect2(768, 256, 128, 128)
		_pip_tex_combat = AtlasTexture.new()
		_pip_tex_combat.atlas = sheet
		_pip_tex_combat.region = Rect2(768, 384, 128, 128)
	_offscreen_tex = ResourceLoader.load("res://assets/ue/Raw/Art/UI/HUD/T_DetectionMeter_Offscreen.png") as Texture2D


func _update_compass_pois(p: Node3D) -> void:
	if _compass_poi_layer == null:
		return
	var pois: Array[Dictionary] = []
	for ping: Dictionary in _active_pings:
		pois.append({"pos": ping.get("pos", Vector3.ZERO), "kind": "ping"})
	for node: Node in get_tree().get_nodes_in_group("objectives"):
		if node is Node3D and (node as Node3D).visible:
			pois.append({"pos": (node as Node3D).global_position, "kind": "objective"})
	var used: int = 0
	var vert_used: int = 0
	var strip_w: float = 500.0
	var fwd: Vector3 = -p.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	var right: Vector3 = Vector3.UP.cross(-fwd).normalized()

	for poi: Dictionary in pois:
		var pos: Vector3 = poi.get("pos", Vector3.ZERO) as Vector3
		var to_poi: Vector3 = pos - p.global_position
		to_poi.y = 0.0
		if to_poi.length_squared() < 0.25:
			continue
		var dir: Vector3 = to_poi.normalized()
		var angle_rad: float = atan2(dir.dot(right), dir.dot(fwd))
		if absf(angle_rad) > deg_to_rad(85.0):
			continue
		var norm_x: float = clampf(angle_rad / deg_to_rad(85.0), -1.0, 1.0)
		var px: float = 40.0 + (norm_x * 0.5 + 0.5) * strip_w - 9.0
		var tr: TextureRect = _get_compass_poi_node(used)
		used += 1
		tr.texture = _poi_teal_tex if str(poi.get("kind", "")) == "ping" else _poi_gold_tex
		tr.position = Vector2(px, 6.0)
		tr.visible = tr.texture != null
		var dy: float = pos.y - p.global_position.y
		if absf(dy) > COMPASS_VERTICALITY_THRESHOLD_M and _compass_verticality_tex != null:
			var va: TextureRect = _get_compass_verticality_node(vert_used)
			vert_used += 1
			va.texture = _compass_verticality_tex
			va.flip_v = dy < 0.0
			va.position = Vector2(px + 7.0, 14.0)
			va.visible = true

	for i: int in range(used, _compass_poi_pool.size()):
		_compass_poi_pool[i].visible = false
	for j: int in range(vert_used, _compass_verticality_pool.size()):
		_compass_verticality_pool[j].visible = false


func _get_compass_verticality_node(idx: int) -> TextureRect:
	while _compass_verticality_pool.size() <= idx:
		var tr: TextureRect = TextureRect.new()
		tr.name = "CompassVerticalityArrow"
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(10, 10)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_compass_poi_layer.add_child(tr)
		_compass_verticality_pool.append(tr)
	return _compass_verticality_pool[idx]


func _get_compass_poi_node(idx: int) -> TextureRect:
	while _compass_poi_pool.size() <= idx:
		var tr: TextureRect = TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(18, 18)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_compass_poi_layer.add_child(tr)
		_compass_poi_pool.append(tr)
	return _compass_poi_pool[idx]


func _update_guard_pips_and_offscreen(p: Node3D, is_hub: bool) -> void:
	if _alert_layer == null:
		return
	var pip_used: int = 0
	var off_used: int = 0
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if not is_hub and cam != null and vp != null:
		var vp_size: Vector2 = vp.get_visible_rect().size
		var center: Vector2 = vp_size * 0.5
		for g: Node in get_tree().get_nodes_in_group("guards"):
			if not (g is Node3D):
				continue
			var alert: Dictionary = _read_guard_alert_state(g as Node3D)
			var st_str: String = str(alert.get("state", "neutral")).to_lower()
			if st_str == "knocked_out" or st_str == "5":
				continue
			var susp: float = clampf(float(alert.get("suspicion", 0.0)), 0.0, 1.0)
			var alerted: bool = alert.get("alerted", false) == true
			var combat: bool = alert.get("combat", false) == true
			if susp <= 0.04 and not alerted and not combat:
				continue
			var wpos: Vector3 = (alert.get("world_pos", (g as Node3D).global_position) as Vector3) + Vector3(0.0, 2.25, 0.0)
			var behind: bool = cam.is_position_behind(wpos)
			var spos: Vector2 = cam.unproject_position(wpos)
			var on_screen: bool = (not behind) and spos.x >= 24.0 and spos.x <= vp_size.x - 24.0 and spos.y >= 24.0 and spos.y <= vp_size.y - 24.0
			if on_screen:
				var pip: TextureRect = _get_pip_node(pip_used)
				pip_used += 1
				if combat:
					pip.texture = _pip_tex_combat
				elif alerted:
					pip.texture = _pip_tex_alert
				elif susp >= 0.45:
					pip.texture = _pip_tex_susp
				else:
					pip.texture = _pip_tex_warn
				pip.position = spos - Vector2(22.0, 44.0)
				# UI5: red = alerted/combat, green = suspicion/warning.
				var pip_alpha: float = clampf(0.45 + susp * 0.55, 0.45, 1.0)
				pip.modulate = Color(1.0, 0.36, 0.30, pip_alpha) if (alerted or combat) else Color(0.46, 1.0, 0.58, pip_alpha)
				pip.visible = pip.texture != null
			else:
				var off: TextureRect = _get_offscreen_node(off_used)
				off_used += 1
				var rel_world: Vector3 = (g as Node3D).global_position - p.global_position
				var cam_right: Vector3 = cam.global_transform.basis.x
				var cam_fwd: Vector3 = -cam.global_transform.basis.z
				var dir2: Vector2 = Vector2(rel_world.dot(cam_right), -rel_world.dot(cam_fwd))
				if dir2.length_squared() < 0.0001:
					dir2 = Vector2(0.0, 1.0)
				else:
					dir2 = dir2.normalized()
				var pos2: Vector2 = center + Vector2(dir2.x * minf(260.0, vp_size.x * 0.34), dir2.y * minf(175.0, vp_size.y * 0.34))
				off.position = pos2 - Vector2(18.0, 21.0)
				# T_DetectionMeter_Offscreen points downward (+Y), so align +Y with dir2.
				off.rotation = atan2(dir2.y, dir2.x) - PI * 0.5
				# UI5 parity: red = alerted/combat, green = suspicion/warning,
				# matching the overhead pips (KF21/KF22).
				var col: Color = Color(0.98, 0.22, 0.20, 0.95) if (combat or alerted) else Color(0.46, 1.0, 0.58, clampf(0.4 + susp * 0.6, 0.4, 0.92))
				off.modulate = col
				off.visible = off.texture != null

	for i: int in range(pip_used, _pip_pool.size()):
		_pip_pool[i].visible = false
	for j: int in range(off_used, _offscreen_pool.size()):
		_offscreen_pool[j].visible = false


func _read_guard_alert_state(g: Node3D) -> Dictionary:
	if g.has_method("get_alert_state"):
		var raw: Variant = g.call("get_alert_state")
		if raw is Dictionary:
			return raw as Dictionary
	var st_v: Variant = g.get("state")
	var st_i: int = int(st_v) if (st_v is int or st_v is float) else 0
	var det_v: Variant = g.get("detection")
	var det: float = float(det_v) if (det_v is float or det_v is int) else 0.0
	var names: Array[String] = ["neutral", "suspicious", "alerted", "combat", "search", "knocked_out"]
	var st_name: String = names[clampi(st_i, 0, names.size() - 1)]
	return {
		"state": st_name,
		"suspicion": clampf(det / 100.0, 0.0, 1.0),
		"world_pos": g.global_position,
		"alerted": st_i == 2 or st_i == 4,
		"combat": st_i == 3,
	}


func _get_pip_node(idx: int) -> TextureRect:
	while _pip_pool.size() <= idx:
		var tr: TextureRect = TextureRect.new()
		tr.name = "GuardPip_%d" % _pip_pool.size()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(44, 44)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_alert_layer.add_child(tr)
		_pip_pool.append(tr)
	return _pip_pool[idx]


func _get_offscreen_node(idx: int) -> TextureRect:
	while _offscreen_pool.size() <= idx:
		var tr: TextureRect = TextureRect.new()
		tr.name = "OffscreenArc_%d" % _offscreen_pool.size()
		tr.texture = _offscreen_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(36, 42)
		tr.pivot_offset = Vector2(18, 21)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_alert_layer.add_child(tr)
		_offscreen_pool.append(tr)
	return _offscreen_pool[idx]


# =============================================================================
# Lockpicking Minigame Logic (DA_LockpickMinigameVariations)
# =============================================================================

func _load_lockpick_db() -> void:
	if not FileAccess.file_exists(INTERACTABLES_JSON_PATH):
		return
	var f: FileAccess = FileAccess.open(INTERACTABLES_JSON_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var lp_v: Variant = (parsed as Dictionary).get("lockpick", {})
		if lp_v is Dictionary:
			_lockpick_db = lp_v as Dictionary


func _pick_lockpick_tracks(lock_level: int) -> Array:
	var vars_v: Variant = _lockpick_db.get("variations_by_difficulty", {})
	if vars_v is Dictionary:
		var vars: Dictionary = vars_v as Dictionary
		var key: String = str(clampi(lock_level, 0, 5))
		var list_v: Variant = vars.get(key, vars.get("1", []))
		if list_v is Array and not (list_v as Array).is_empty():
			var arr: Array = list_v as Array
			var pick_idx: int = int(Time.get_ticks_msec() / 100) % arr.size()
			var chosen_v: Variant = arr[pick_idx]
			if chosen_v is Dictionary:
				var tracks_v: Variant = (chosen_v as Dictionary).get("tracks", [])
				if tracks_v is Array and not (tracks_v as Array).is_empty():
					return (tracks_v as Array).duplicate(true)
	# Deterministic fallback if JSON unavailable.
	return [{
		"duration_s": 1.8,
		"arc_angle_deg": 90.0,
		"default_section_type": "Lockpick.TrackSection.Jammable",
		"defined_sections": [
			{"section_type": "Lockpick.TrackSection.Breakable", "start_s": 0.4, "end_s": 0.8},
			{"section_type": "Lockpick.TrackSection.Breakable", "start_s": 1.1, "end_s": 1.6},
		],
	}]


func _init_lockpick_track(idx: int) -> void:
	_lockpick_track_idx = clampi(idx, 0, maxi(0, _lockpick_tracks.size() - 1))
	_lockpick_cursor_t = 0.0
	_lockpick_broken_flags.clear()
	var tr_v: Variant = _lockpick_tracks[_lockpick_track_idx] if _lockpick_track_idx < _lockpick_tracks.size() else {}
	var tr: Dictionary = tr_v as Dictionary if tr_v is Dictionary else {}
	var secs_v: Variant = tr.get("defined_sections", [])
	if secs_v is Array:
		for _s: Variant in (secs_v as Array):
			_lockpick_broken_flags.append(false)
	if _lockpick_track_lbl != null:
		_lockpick_track_lbl.text = UIStringsScript.loc("TUMBLER %d / %d") % [_lockpick_track_idx + 1, maxi(1, _lockpick_tracks.size())] ## PORT COPY (no authored row)
	if _lockpick_status_lbl != null:
		_lockpick_status_lbl.text = InputGlyphs.format_legend(
			UIStringsScript.loc("[SPACE] / [LMB] STRIKE PIN   ·   [ESC] CANCEL"), LOCKPICK_LEGEND_ACTIONS)
		_lockpick_status_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TEXT)
	_sync_lockpick_dial(tr)


func _tick_lockpick(delta: float) -> void:
	if _lockpick_tracks.is_empty():
		_finish_lockpick(true)
		return
	var tr_v: Variant = _lockpick_tracks[_lockpick_track_idx]
	var tr: Dictionary = tr_v as Dictionary if tr_v is Dictionary else {}
	var dur: float = maxf(0.2, float(tr.get("duration_s", 1.8)))
	if _lockpick_jam_timer > 0.0:
		_lockpick_jam_timer = maxf(0.0, _lockpick_jam_timer - delta)
	else:
		_lockpick_cursor_t = fposmod(_lockpick_cursor_t + delta, dur)
	_sync_lockpick_dial(tr)


func _sync_lockpick_dial(tr: Dictionary) -> void:
	if _lockpick_dial == null:
		return
	_lockpick_dial.track_data = tr
	_lockpick_dial.cursor_t = _lockpick_cursor_t
	_lockpick_dial.broken_flags = _lockpick_broken_flags
	_lockpick_dial.jam_flash = _lockpick_jam_timer
	_lockpick_dial.track_idx = _lockpick_track_idx
	_lockpick_dial.track_total = maxi(1, _lockpick_tracks.size())
	_lockpick_dial.queue_redraw()


func _attempt_lockpick_strike() -> void:
	if not _lockpick_active or _lockpick_jam_timer > 0.0 or _lockpick_tracks.is_empty():
		return
	var tr_v: Variant = _lockpick_tracks[_lockpick_track_idx]
	var tr: Dictionary = tr_v as Dictionary if tr_v is Dictionary else {}
	var grace: float = float(_lockpick_db.get("early_unlock_threshold_s", 0.1))
	var secs_v: Variant = tr.get("defined_sections", [])
	var hit_idx: int = -1
	if secs_v is Array:
		var secs: Array = secs_v as Array
		for i: int in range(secs.size()):
			if i < _lockpick_broken_flags.size() and _lockpick_broken_flags[i]:
				continue
			var sv: Variant = secs[i]
			if sv is Dictionary:
				var sd: Dictionary = sv as Dictionary
				var s0: float = float(sd.get("start_s", 0.0)) - grace
				var s1: float = float(sd.get("end_s", 0.2)) + grace
				if _lockpick_cursor_t >= s0 and _lockpick_cursor_t <= s1:
					hit_idx = i
					break
	if hit_idx >= 0:
		if hit_idx < _lockpick_broken_flags.size():
			_lockpick_broken_flags[hit_idx] = true
		var all_broken: bool = true
		for f: bool in _lockpick_broken_flags:
			if not f:
				all_broken = false
				break
		if all_broken:
			if _lockpick_track_idx + 1 < _lockpick_tracks.size():
				_init_lockpick_track(_lockpick_track_idx + 1)
			else:
				_finish_lockpick(true)
		else:
			if _lockpick_status_lbl != null:
				_lockpick_status_lbl.text = UIStringsScript.loc("PIN SET! HIT NEXT SWEET SPOT") ## PORT COPY (no authored row)
				_lockpick_status_lbl.add_theme_color_override("font_color", Color(0.40, 0.96, 0.68))
			_sync_lockpick_dial(tr)
	else:
		# Jammed! Apply authored jam delay, emit noise, and apply jam damage if supported.
		_lockpick_jam_timer = float(_lockpick_db.get("jam_damage_delay_s", 0.5))
		if _lockpick_status_lbl != null:
			_lockpick_status_lbl.text = UIStringsScript.st_upper("ST_Lockpicking", "LockPicking.Lock.NoKeyLock", "LOCK") + " " + UIStringsScript.st_upper("ST_Lockpicking", "Lockpicking.Term.Jammed", "JAMMED!")
			_lockpick_status_lbl.add_theme_color_override("font_color", Color(0.98, 0.34, 0.30))
		var p: Node3D = _get_player()
		if p != null:
			var nb: Node = get_node_or_null("/root/NoiseBus")
			if nb != null and nb.has_method("emit_noise"):
				nb.call("emit_noise", p.global_position, 9.0, p, "lockpick_jam")
			var dmg_tbl_v: Variant = _lockpick_db.get("jam_damage_by_lock_level", {})
			if dmg_tbl_v is Dictionary and p.has_method("take_damage"):
				var dmg: float = float((dmg_tbl_v as Dictionary).get(str(clampi(_lockpick_level, 1, 4)), 5.0))
				p.call("take_damage", dmg)
		_sync_lockpick_dial(tr)


func _finish_lockpick(success: bool) -> void:
	_lockpick_active = false
	if _lockpick_root != null:
		_lockpick_root.visible = false
	Input.mouse_mode = _lockpick_prev_mouse
	var p: Node = _get_player()
	if p != null and p.has_method("set_lockpicking_active"):
		p.call("set_lockpicking_active", false)
	var cb: Callable = _lockpick_callback
	_lockpick_callback = Callable()
	if cb.is_valid():
		cb.call(success)


# =============================================================================
# Map, Ping & Mission Letter Helpers
# =============================================================================

func _refresh_tactical_map() -> void:
	if _map_draw == null:
		return
	# Authored map-name rows (ST_ThievesDen CityMap.* / ST_MapTool *.MapName), so the
	# overlay header follows the locale like the rest of the UI.
	var map_title: String = UIStringsScript.st_upper("ST_ThievesDen", "CityMap.OldManor", "Elway Manor") if GameState.active_map_id == "old_manor" else (
		UIStringsScript.st_upper("ST_MapTool", "Guildhall.MapName", "Constables' Guildhall") if GameState.active_map_id == "guildhall" else (
			UIStringsScript.loc("Thieves' Den").to_upper() if GameState.active_contract_order <= 1 else str(GameState.active_map_id).to_upper() ## PORT COPY (no authored row)
		)
	)
	if _map_title_lbl != null:
		_map_title_lbl.text = UIStringsScript.loc("Tactical Map").to_upper() + " — " + map_title ## PORT COPY (no authored row)
	var p: Node3D = _get_player()
	if p != null:
		_map_draw.player_pos = p.global_position
		_map_draw.player_yaw = p.rotation.y
	# Authored TATWorldMapBoundary floors (W9-P3-C4). Empty today: the generated
	# level payloads do not carry `map_boundaries` yet (producer contract
	# build/qa/w9/parse_tables-map-boundaries.patch). The fallback is labelled.
	_boundary_rows = MapBoundariesScript.for_map(str(GameState.active_map_id))
	_boundary_source = "authored" if not _boundary_rows.is_empty() else "fallback"
	_map_draw.boundaries = _boundary_rows
	_map_draw.boundary_source = _boundary_source
	_map_draw.active_boundary = MapBoundariesScript.boundary_at(
		_boundary_rows, p.global_position if p != null else Vector3.ZERO)
	var guards: Array[Dictionary] = []
	for g: Node in get_tree().get_nodes_in_group("guards"):
		if g is Node3D:
			var alert: Dictionary = _read_guard_alert_state(g as Node3D)
			if str(alert.get("state", "")) == "knocked_out":
				continue
			guards.append({
				"pos": (g as Node3D).global_position,
				"alerted": alert.get("alerted", false) == true,
				"combat": alert.get("combat", false) == true,
			})
	_map_draw.guard_points = guards
	var loot_pts: Array[Dictionary] = []
	for ln: Node in get_tree().get_nodes_in_group("loot"):
		if ln is Node3D and (ln as Node3D).visible:
			loot_pts.append({"pos": (ln as Node3D).global_position})
	_map_draw.loot_points = loot_pts
	var obj_pts: Array[Dictionary] = []
	for on: Node in get_tree().get_nodes_in_group("objectives"):
		if on is Node3D and (on as Node3D).visible:
			obj_pts.append({"pos": (on as Node3D).global_position})
	_map_draw.objective_points = obj_pts
	_map_draw.ping_points = _active_pings
	_map_draw.queue_redraw()


func _on_map_clicked(world_pos: Vector3) -> void:
	_add_ping(world_pos, UIStringsScript.loc("Waypoint").to_upper(), Color(0.45, 0.95, 0.92, 0.96)) ## PORT COPY (no authored row)
	_refresh_tactical_map()


## Routed copy for the ping radial (PingRadialDraw.LABEL_COUNT, same order):
## LOOT and DANGER are authored ST_Social rows; MOVE/OBJECTIVE are port copy.
static func ping_label_text(idx: int) -> String:
	match idx:
		0:
			return UIStringsScript.st_text("ST_Social", "Ping.Loot", "Loot").to_upper()
		1:
			return UIStringsScript.st_text("ST_Social", "Ping.Danger", "Danger").to_upper()
		2:
			return UIStringsScript.loc("Move").to_upper() ## PORT COPY (no authored row)
		_:
			return UIStringsScript.loc("Objective").to_upper() ## PORT COPY (no authored row)


func _commit_radial_ping(idx: int) -> void:
	var ci: int = clampi(idx, 0, PingRadialDraw.LABEL_COUNT - 1)
	var label: String = ping_label_text(ci)
	var col: Color = PingRadialDraw.COLORS[ci]
	var target_pos: Vector3 = Vector3.ZERO
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam != null:
		var from: Vector3 = cam.global_position
		var dir: Vector3 = -cam.global_transform.basis.z
		target_pos = from + dir * 12.0
		var w3d: World3D = cam.get_world_3d()
		if w3d != null:
			var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + dir * 60.0)
			var hit: Dictionary = w3d.direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				target_pos = hit.get("position", target_pos) as Vector3
	else:
		var p: Node3D = _get_player()
		if p != null:
			target_pos = p.global_position - p.global_transform.basis.z * 8.0
	_add_ping(target_pos, label, col)


func _add_ping(world_pos: Vector3, label: String, col: Color) -> void:
	_active_pings.append({
		"pos": world_pos,
		"label": label,
		"color": col,
		"ttl": 15.0,
	})
	while _active_pings.size() > 6:
		_active_pings.pop_front()


func _tick_active_pings(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for ping: Dictionary in _active_pings:
		var ttl: float = float(ping.get("ttl", 0.0)) - delta
		if ttl > 0.0:
			ping["ttl"] = ttl
			keep.append(ping)
	_active_pings = keep


func _update_world_ping_markers(p: Node3D) -> void:
	if _ping_marker_layer == null:
		return
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	var used: int = 0
	if cam != null and vp != null:
		var vp_size: Vector2 = vp.get_visible_rect().size
		for ping: Dictionary in _active_pings:
			var pos: Vector3 = ping.get("pos", Vector3.ZERO) as Vector3
			if cam.is_position_behind(pos):
				continue
			var spos: Vector2 = cam.unproject_position(pos)
			if spos.x < 16.0 or spos.x > vp_size.x - 16.0 or spos.y < 16.0 or spos.y > vp_size.y - 16.0:
				continue
			var m: Control = _get_ping_marker_node(used)
			used += 1
			m.position = spos - Vector2(56.0, 22.0)
			var lbl: Label = m.get_meta("lbl") as Label
			var col: Color = ping.get("color", Color(0.45, 0.95, 0.92, 0.96)) as Color
			var dist_m: int = int(round(p.global_position.distance_to(pos)))
			if lbl != null:
				var dist_text: String = UIStringsScript.st_template("ST_GeneralUI", "Format.Distance", "{Distance} m", {"Distance": str(dist_m)})
				lbl.text = "◆ %s (%s)" % [
					str(ping.get("label", UIStringsScript.st_upper("ST_Settings", "Settings.Controls.Ping", "Ping"))), dist_text]
				lbl.add_theme_color_override("font_color", col)
			m.visible = true
	for i: int in range(used, _ping_marker_pool.size()):
		_ping_marker_pool[i].visible = false


func _get_ping_marker_node(idx: int) -> Control:
	while _ping_marker_pool.size() <= idx:
		var box: PanelContainer = PanelContainer.new()
		box.add_theme_stylebox_override("panel", ThemeScript.teal_card_style(1, 3, Color(0.02, 0.05, 0.07, 0.78), 4))
		box.custom_minimum_size = Vector2(112, 22)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lbl: Label = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		if _sans != null:
			lbl.add_theme_font_override("font", _sans)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lbl)
		box.set_meta("lbl", lbl)
		_ping_marker_layer.add_child(box)
		_ping_marker_pool.append(box)
	return _ping_marker_pool[idx]


func _close_mission_letter() -> void:
	_letter_open = false
	_set_letter_hud_hidden(false)
	if _letter_root != null:
		_letter_root.visible = false
	Input.mouse_mode = _letter_prev_mouse


func _on_mission_letter_requested(title: String, intro_text: String) -> void:
	show_mission_letter(title, intro_text)


func _on_noise_emitted(_origin: Vector3, loudness_meters: float, source: Node, _tag: String) -> void:
	if not is_inside_tree():
		return
	# UI5: the bilateral arcs read the player's own noise output only. Guard
	# alerts, door slams and tool hisses must never drive them even when they
	# happen right next to the player, so the source group is the sole authority.
	if source != null and not source.is_in_group("player"):
		return
	# T2-13-B: a zero-loudness event must not flash the arcs.
	if loudness_meters <= 0.0:
		return
	var amp: float = clampf(loudness_meters / 16.0, 0.25, 1.0)
	_soundwave_energy = maxf(_soundwave_energy, amp)


func _add_den_card_row(key_txt: String, label_txt: String, value_txt: String) -> void:
	if _den_card_lines_box == null:
		return
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if key_txt != "":
		row.add_child(ThemeScript.white_keycap(key_txt.to_upper(), 11))
	if label_txt != "":
		var lbl: Label = Label.new()
		lbl.text = label_txt
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", ThemeScript.TEAL_MUTED if value_txt != "" else ThemeScript.TEAL_TEXT)
		if _sans != null:
			lbl.add_theme_font_override("font", _sans)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)
	if value_txt != "":
		var val_lbl: Label = Label.new()
		val_lbl.text = value_txt
		val_lbl.add_theme_font_size_override("font_size", 15)
		val_lbl.add_theme_color_override("font_color", ThemeScript.TEAL_TITLE)
		if _serif != null:
			val_lbl.add_theme_font_override("font", _serif)
		val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(val_lbl)
	_den_card_lines_box.add_child(row)


# =============================================================================
# Internal Utilities
# =============================================================================

func _get_player() -> Node3D:
	if not is_inside_tree():
		return null
	# Prefer the newest group member: a stale mission/arena player can linger
	# in the "player" group when feats transition (T1-13-E: HUD bound the
	# stale first entry and ignored damage on the current player).
	var members: Array[Node] = get_tree().get_nodes_in_group("player")
	if members.is_empty():
		return null
	return members.back() as Node3D


func _toggle_pause() -> void:
	_set_paused(not get_tree().paused)


func _set_paused(value: bool) -> void:
	get_tree().paused = value
	if AudioManager != null and AudioManager.has_method("play_ui"):
		AudioManager.play_ui("open" if value else "back")
	var touch_ui: Node = get_tree().get_first_node_in_group("mobile_touch_ui")
	if touch_ui != null and touch_ui.has_method("clear_input"):
		touch_ui.call("clear_input")
	if _pause_root != null:
		_pause_root.visible = value
	if pause_center != null and _pause_root == null:
		pause_center.visible = value
	if value:
		_hide_live_hud_for_pause()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# W9-P3-C3: the pad enters the management panel on Resume and rings the
		# four authored actions (BPUI_StartMenuOptions).
		if _pause_panel_for_focus != null:
			FocusNavScript.install_and_focus(_pause_panel_for_focus)
	else:
		# Never leave focus behind the hidden panel.
		FocusNavScript.release_if_inside(_pause_panel_for_focus)
		_restore_live_hud_after_pause()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## KF30: the management screen hides the entire live HUD and shows only the
## modal + footer over the darkened world. Snapshot visibility so a resume puts
## every element back exactly as it was (including conditionally hidden ones).
func _hide_live_hud_for_pause() -> void:
	if _root == null or _pause_hud_hidden:
		return
	_pause_visibility.clear()
	for c: Node in _root.get_children():
		if c == _pause_root:
			continue
		if c is CanvasItem:
			var ci: CanvasItem = c as CanvasItem
			_pause_visibility[ci] = ci.visible
			ci.visible = false
	_pause_hud_hidden = true


func _restore_live_hud_after_pause() -> void:
	if _root == null or not _pause_hud_hidden:
		return
	for key: Variant in _pause_visibility.keys():
		var ci: CanvasItem = key as CanvasItem
		if ci != null and is_instance_valid(ci):
			ci.visible = bool(_pause_visibility[key])
	_pause_visibility.clear()
	_pause_hud_hidden = false


## Destination of the pause menu's "RETURN TO THIEF'S DEN". The Den hub is
## contract 1 (map thieves_den) inside the mission scene; there is no separate
## Den scene in this port (C3-10 / RE-L-03).
func pause_return_scene_path() -> String:
	return DEN_SCENE_PATH


## Leaving a live run for the Den is an abandonment: carried loot is lost, the
## stashed haul is kept (authored kept_on_capture = 0.0). Every failure path owes
## a payout (AGENTS.md), so settle once through the shared payout outbox before
## the scene change. save_system owns the bank; this only calls it.
func _settle_run_for_exit() -> Dictionary:
	# Hub exits (Den, contract order <= 1) have no run to settle; a live mission
	# always owes exactly one payout.
	if _payout_applied or GameState.state != "playing" or int(GameState.active_contract_order) <= 1:
		return {"applied": false, "banked": 0}
	var payout: Dictionary = LootInventoryScript.build_payout("capture", {"objectives_complete": false})
	var res: Dictionary = SaveSystem.bank_payout(payout)
	_payout_applied = true
	GameState.resolve_phase()
	return {"applied": bool(res.get("applied", false)), "banked": int(res.get("banked", 0))}


func _pause_return_to_den() -> void:
	_settle_run_for_exit()
	_set_paused(false)
	GameState.active_contract_order = 1
	GameState.end_free_play()
	get_tree().change_scene_to_file(pause_return_scene_path())


## Post-match Continue: mission_controller has already banked the run, so this
## only returns to the Den hub (contract 1) through the mission scene.
func _continue_to_den() -> void:
	GameState.active_contract_order = 1
	GameState.end_free_play()
	get_tree().change_scene_to_file(DEN_SCENE_PATH)


## C-4 instrumentation: exact in-tree node counts for the elements the recorded
## client drew twice. One HudScript/one hp_frame is the expected result; the
## recording's doubling is then a render-path question, not a build-path one.
func debug_hud_counts() -> Dictionary:
	if _root == null:
		return {}
	return {
		"hud_build_id": hud_build_id,
		"root_children": _root.get_child_count(),
		"hp_frames": find_children("HpFrame", "TextureRect", true, false).size(),
		"hp_fills": find_children("HpFill", "TextureRect", true, false).size(),
		"hp_splatters": find_children("HpSplatter", "TextureRect", true, false).size(),
		"objectives": find_children("ObjectivesLabel", "Label", true, false).size(),
		"map_ping_hints": find_children("MapPingHintBar", "HBoxContainer", true, false).size(),
		"hp_frame_builds": _hp_frame_builds,
	}


func _set_prompt(raw: String) -> void:
	if interact_lbl == null:
		return
	var txt: String = raw.strip_edges()
	current_prompt = txt
	if txt == "":
		interact_lbl.text = ""
		if _prompt_keycap != null:
			_prompt_keycap.visible = false
		return
	var key: String = ""
	var rest: String = txt
	if txt.begins_with("["):
		var end: int = txt.find("]")
		if end > 1:
			key = txt.substr(1, end - 1).strip_edges()
			rest = txt.substr(end + 1).strip_edges()
	# Interact is bound to F (project.godot physical key 70); E is a legacy
	# alias, so the visible keycap always reads F. Lock/close phrasing follows
	# the KF24 door prompts while the test-facing door strings stay intact.
	if key == "E":
		key = "F"
	# KF24 door flow: OPEN / CLOSE are the primary prompts. The [HOLD] LOCK
	# secondary is pushed separately by the door's secondary prompt so a pick
	# lock action is never mislabelled as a hold action.
	if rest == "Open Door":
		rest = UIStringsScript.st_upper("ST_Interactables", "PromptOpen", "Open")
	elif rest == "Close Door":
		rest = UIStringsScript.st_upper("ST_Interactables", "PromptClose", "Close")
	if key != "" and _prompt_keycap != null and _prompt_keycap_lbl != null:
		_prompt_keycap_lbl.text = key.to_upper()
		_prompt_keycap.visible = true
	elif _prompt_keycap != null:
		_prompt_keycap.visible = false
	interact_lbl.text = rest.to_upper()
	if MobileProfile.is_mobile():
		if _prompt_keycap != null:
			_prompt_keycap.visible = false
		interact_lbl.visible = false


func _set_secondary_prompt(raw: String) -> void:
	if _prompt_secondary_lbl == null:
		return
	var txt: String = raw.strip_edges()
	if txt == "" or MobileProfile.is_mobile():
		_prompt_secondary_lbl.text = ""
		_prompt_secondary_lbl.visible = false
		return
	_prompt_secondary_lbl.text = txt.to_upper()
	_prompt_secondary_lbl.visible = true


func _update_fps_overlay() -> void:
	if fps_overlay == null:
		return
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = 1000.0 / maxf(fps, 1.0)
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var pos_txt: String = "-"
	var p: Node3D = _get_player()
	if p != null:
		pos_txt = "%.1f, %.1f, %.1f" % [p.global_position.x, p.global_position.y, p.global_position.z]
	fps_overlay.text = "FPS %d | %.1f ms | draws %d | objs %d | prims %d\nnodes %d | VRAM %.0f MB | pos %s | %s" % [
		int(round(fps)), frame_ms, draw_calls, objects, primitives, nodes, vram_mb, pos_txt,
		str(contract_data.get("title", "Contract #%d" % GameState.active_contract_order)),
	]


func _tool_icon_for(tool_id: String) -> Texture2D:
	var path: String = str(TOOL_ICON_MAP.get(tool_id, ""))
	if path != "" and ResourceLoader.exists(path):
		return ResourceLoader.load(path) as Texture2D
	return null


func _tex_rect(path: String, min_sz: Vector2) -> TextureRect:
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	if tex == null:
		return null
	var tr: TextureRect = TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = tex
	tr.custom_minimum_size = min_sz
	tr.offset_right = min_sz.x
	tr.offset_bottom = min_sz.y
	tr.size = min_sz
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _tex_rect_full(path: String) -> TextureRect:
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	if tex == null:
		return null
	var tr: TextureRect = TextureRect.new()
	tr.texture = tex
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr
