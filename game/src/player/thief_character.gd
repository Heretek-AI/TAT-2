extends CharacterBody3D
## Playable Thief controller (Spider, Chameleon, Moth) with stamina, crouch, lean,
## grapple/disguise/astral abilities, Slithersap, Smoke Bomb, Pickpocket Fairy, and Blackjack.

const VfxManager = preload("res://src/core/vfx_manager.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")
const ThiefAnimLib = preload("res://src/core/animation_library.gd")
const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const OSERendererScript := preload("res://src/core/ose_renderer.gd")
const SmokeProjectileScript := preload("res://src/player/smoke_projectile.gd")

# Real ThiefNisha meshes (BP_Player_Thief_Spider skeletal components -> GLB;
# sources in extracted/json/Character/Player/BP_Player_Thief_Spider.json).
const THIEF_3P_BODY_GLB: String = "res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/Dyn/SK_ThiefNisha_Dyn__Body_NoPostProcABP.glb"
const THIEF_3P_HEAD_GLB: String = "res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/Dyn/SK_ThiefNisha_Dyn__Head.glb"
const THIEF_1P_UPPER_GLB: String = "res://assets/ue/Content/Art/Animation/ThiefNisha/Skin/Base/SK_ThiefNisha__BodyUpper.glb"
# Right-hand candidates for the tool mount, in preference order.
const FP_TOOL_BONES: Array[String] = ["weapon_r_1p", "hand_r_1p", "hand_r"]
# Skeleton joints marking the UE first-person camera, in preference order.
const FP_CAM_BONES: Array[String] = ["camera_position", "game_camera"]
const FP_ANIM_BLEND: float = 0.2 # crossfade window 0.15-0.25 s per deliverable
# UE OSECameraComponent.FirstPersonFieldOfView = 85.0 is a HORIZONTAL angle;
# at 16:9 that is 54.54 deg vertical (2*atan(tan(85/2)*9/16) = 54.54). The
# world/default camera now uses that authored vertical angle so the 3D view
# matches the UE framing. The first-person viewmodel keeps its own 85 deg
# projection lock (FP_VM_FOV_DEG) and 0.5 view-space scale: those frame the
# tools/arms, not the world.
const UE_FP_FOV_HORIZONTAL_DEG: float = 85.0
const UE_FP_FOV_VERTICAL_16X9_DEG: float = 54.54
const FP_VM_FOV_DEG: float = 85.0 # OSECameraComponent.FirstPersonFieldOfView lock (unchanged) for the VM only
# UE first-person view-space scale applied in the VM shader; the mesh itself
# stays at scale 1.0 (tool roll and socket net transform unchanged).
const FP_VM_SCALE: float = 0.5
# UE OSECableComponent normal traversal cable: authored steel, no emission.
# MI_Zipwire is the launcher and M_Hotwire_Glow only the shock helper.
const ZIPWIRE_CABLE_MAT: String = "/Game/Art/Environment/Props/WiringKit/MI_WiredCableSmall"

const STAND_HEAD_HEIGHT: float = 1.66875
const CROUCH_HEAD_HEIGHT: float = 0.88875
# UE eye heights are relative to the capsule centre (Spider CDO BaseEyeHeight
# 77.875 cm over capsule half-height 89 cm; crouched 38.875 cm over 50 cm):
# stand = 0.89 + 0.77875, crouch = 0.50 + 0.38875.
const LEAN_OFFSET: float = 0.45
const LEAN_ROLL: float = 0.14
const LEAN_WALL_CHECK_DIST: float = 0.6

# Real UE gameplay values (tools/parse_gameplay.py; sources in
# game/data/generated/gameplay/*.json "sources"). Curve-table overrides via
# GameData.eval_curve are kept only for rows the real data defines.
const AIR_CONTROL: float = 0.5 # TATCharacterMovement CharMoveComp.AirControl
const FLOOR_MAX_ANGLE_DEG: float = 50.0 # CharMoveComp.WalkableFloorAngle 60.0 retuned to 50.0 for stair stick (no mantle)
const FLOOR_SNAP_LENGTH: float = 0.3 # stairs snap fix: 0.25-0.3 window keeps body grounded on 0.18-0.2 m risers
const STEP_UP_MAX_M: float = 0.3 # stair assist bound: 0.18-0.2 m risers climb, 0.6 m walls block
const STEP_UP_FORWARD_M: float = 0.35 # forward probe after the lift: clears one tread, not a room
const STEP_UP_SKIN_M: float = 0.02 # headroom probe skin above the lift
const INTERACT_RANGE: float = 1.75 # TATInteractionTargeterComponent.MaxInteractionRange 175cm
## KF25/KF26: F taps the primary action (pick pocket / OPEN), holding F runs
## the stacked secondary ([HOLD] TAKEDOWN on a guard, [HOLD] LOCK on a door).
const HOLD_INTERACT_SEC: float = 0.45
const CAMERA_FOV: float = UE_FP_FOV_VERTICAL_16X9_DEG # UE 85 horizontal -> 54.54 vertical at 16:9
const CAMERA_FOV_SPRINT: float = CAMERA_FOV + 4.0 # retained +4 velocity-feedback shape (58.54)
const CAMERA_FOV_MIN: float = 50.0 # settings slider/user floor; explicit values clamp consistently
const CAMERA_FOV_MAX: float = 105.0
const WIRE_RANGE: float = 20.0 # DA_StandardToolSettings "Hotwire Range" 2000cm
const WIRE_PULL_SPEED: float = 23.0 # DA_StandardToolSettings "Hotwire Speed" 2300cm/s
const WIRE_CRANK_MIN_TIME: float = 0.5 # GA_Hotwire_Crank.MinimumCrankTime
const WIRE_CRANK_DURATION_FALLBACK: float = 6.0 # CT_WireCrank.CrankDuration (lvl 0)
## UE IA_Ability_Action_Primary_Hold is a 0.2 s hold trigger; the launch
## ability (GA_Hotwire_Child_Launch travel) fires only after the hold
## completes, not on the raw mouse-down event.
const WIRE_LAUNCH_HOLD_SEC: float = 0.2
const GRAPPLE_MIN_HOLD_SEC: float = 0.12 # P1 tap-fire guard: releases shorter than this keep the winch engaged (no UE source; one physics-frame margin at 60 Hz physics + input jitter). Below this the tap becomes a hop, not a pull.
const SPRINT_START_STAMINA: float = 3.0 # P2 no-hysteresis sprint: sprint (re)starts only above this; stops at 2.0. Kills the FOV flicker at the old single 2.0 threshold.
const SPRINT_STOP_STAMINA: float = 2.0
const SAP_ARM_DELAY_SEC: float = 0.3 # P1 sap instant-placement: fixed arm delay between throw anim and puddle setup (no UE InitialSpeed source; delay is Godot-side pacing, not an invented speed).
const FAIRY_FAIL_RADIUS_M: float = 8.0 # P2 dynamic fail radius: blocked-pickpocket noise was distance_to(mark)+2.0 (farther mark = louder failure). Fixed 8 m FailRadius replaces it.
const GRAPPLE_MAX_CHARGES: int = 4 # BP_Hotwire_Tool.MaxAmmo
const MANTLE_MAX_HEIGHT_M: float = 4.0 # BP_Player_Base._mantleSettings.MaxHeight 400cm
const MANTLE_MAX_ANGLE_DEG: float = 25.0 # BP_Player_Base._mantleSettings.MaxAngleFacing
const WALL_CLIMB_SPEED: float = 2.5 # BP_Player_Base._wallClimbSettings.WallClimbDashSpeed 250cm/s
const WALL_CLIMB_ACCEL: float = 12.0 # BP_Player_Base._wallClimbSettings.WallClimbDashAcceleration 1200cm/s2
# Documented gameplay fallback: CT_StaminaSystem.StaminaPerSecond.Climb.Base stores 0.0;
# 5.0/s matches StaminaPerSecond.Sprint so wall-climb consumes stamina per M2 scope.
const CLIMB_STAMINA_BURN_FALLBACK: float = 5.0
const DISGUISE_COOLDOWN: float = 15.0 # GE_Disguise_Cooldown magnitude
const DISGUISE_ACTIVE_TIME: float = 60.0 # GE_Disguise_Active magnitude (max active time)
# Authored disguise integrity rows (DT_DisguiseV3IntegrityReduction, enabled rows).
const DISGUISE_DRAIN_TIMER: float = 1.0 # DisguiseTimer.IntegrityReduction.Value per s
const DISGUISE_DRAIN_SPRINTING: float = 40.0 # Sprinting.IntegrityReduction.Value per s
const DISGUISE_DRAIN_GUARD_PROXIMITY: float = 5.0 # GuardProximity.IntegrityReduction.Value per s
const DISGUISE_GUARD_PROXIMITY_M: float = 1.0 # GuardProximity.CharacterRadius 100cm
const DISGUISE_DAMAGE_INTEGRITY_LOSS: float = 40.0 # DamageTaken.IntegrityReduction.Value
const DISGUISE_DRAIN_LOCKPICKING: float = 5.0 # Lockpicking (Status.Lockpicking) per s
const DISGUISE_DRAIN_GUARD_VIEWCONE: float = 10.0 # GuardViewCone per s
const DISGUISE_GUARD_VIEWCONE_M: float = 10.0 # GuardViewCone.CharacterRadius 1000cm
const DISGUISE_GUARD_VIEWCONE_DEG: float = 65.0 # GuardViewCone.CharacterViewConeAngleDegrees
const BLACKJACK_LIGHT_DMG: float = 40.0 # CT_Tool_Blackjack.BlackjackDamageLight
const BLACKJACK_HEAVY_DMG: float = 75.0 # CT_Tool_Blackjack.BlackjackDamageHeavy

signal health_changed(hp: float, max_hp: float)
signal stamina_changed(stam: float, max_stam: float)
signal disguise_changed(integrity: float, active: bool)
signal thief_vision_toggled(enabled: bool)
signal tool_used(tool_id: String, charges_left: int)
signal tool_equipped(tool_id: String, slot_index: int)
signal interacted(target: Node)
signal downed_started(seconds: float)
signal downed()
signal revived() # P2 hygiene: revive previously emitted only health_changed; co-op help-up now has a downed-cleared counterpart.

@export var walk_speed: float = 3.6
@export var sprint_speed: float = 5.4
@export var crouch_speed: float = 1.8
@export var jump_velocity: float = 5.5
@export var gravity: float = 9.8
@export var mouse_sens: float = 0.0024

var max_health: float = 300.0
var health: float = 300.0
var max_stamina: float = 260.0
var stamina: float = 260.0
var stamina_regen: float = 12.0

# Real combat/health tuning (game/data/generated/gameplay/*.json; fallbacks are
# the extracted values and apply only when the JSON is unreadable).
const FALL_DAMAGE_PATH := "res://data/generated/gameplay/fall_damage.json"
const DOWNED_PATH := "res://data/generated/gameplay/downed.json"
const HEALTH_BLOCKS_PATH := "res://data/generated/gameplay/health_blocks.json"
const FALL_SAFE_M_FALLBACK: float = 6.5 # BP_TATPlayerCharacter._safeFallHeight 650cm
const FALL_DEATH_M_FALLBACK: float = 23.25 # BP_Player_Base._deathFallHeight 2325cm
const DOWNED_DURATION_FALLBACK: float = 10.0 # GE_GrantPlayerDowned_Duration
const POST_REVIVE_COOLDOWN_FALLBACK: float = 3.0 # GE_PostReviveCooldown
const HEALTH_BLOCKS_FALLBACK: Array = [25, 25, 25, 25] # Spider row
var is_downed: bool = false
var downed_timer: float = 0.0
var post_revive_cooldown_s: float = 3.0
var post_revive_ttl: float = 0.0
var _downed_duration: float = 10.0
var _downed_fired: bool = false
var _fall_safe_m: float = 6.5
var _fall_death_m: float = 23.25
var _fall_curve: Curve
var _was_on_floor: bool = true
var _fall_peak_y: float = 0.0
var _fall_data: Dictionary = {}
var _downed_data: Dictionary = {}
var _health_block_data: Dictionary = {}

var is_crouching: bool = false
var is_sprinting: bool = false
var _sprint_toggled: bool = false
var invert_y: bool = false
var sprint_toggle_mode: bool = false
var reduced_camera_bounce: bool = false
var base_fov: float = CAMERA_FOV
var lean_dir: float = 0.0
var thief_vision_on: bool = false
var thief_vision: bool = false
const DISGUISE_STEAL_RANGE: float = 2.8 # retained approximation: no UE source; interaction targeter range is 1.75
const GRAPPLE_ARRIVE_DIST: float = 1.8 # retained: no UE source; HotwireArrivalThreshold 1.0m noted in player_tools.json
const GRAPPLE_VAULT_Y: float = 6.5
const GRAPPLE_MIN_RANGE: float = 3.0
const GRAPPLE_MAX_RANGE: float = WIRE_RANGE
const GRAPPLE_WINCH_TIME: float = 0.35
## RMB attach window after the winch reaches GRAPPLE_ARRIVE_DIST: pressing
## within this window still hangs instead of dropping the cable (RMB "at
## arrival"). Also keeps the cable visible for that instant.
const WIRE_ARRIVAL_GRACE_SEC: float = 0.25
## Hanging crank pulls the body along the cable toward the anchor, stopping
## this far short so the arrival vault has room (collision-safe, never a
## teleport). The full crank still takes CT_WireCrank.CrankDuration (6 s).
const WIRE_HANG_STANDOFF: float = 0.6
const ASTRAL_DURATION: float = 8.0
const PROP_SCAN_INTERVAL: float = 0.1
var _bj_punch_tween: Tween = null
var _prop_scan_accum: float = 0.0
var grapple_time: float = 0.0

# First-person viewmodel rig (Workstream 5). When _fp_use_real_arms is true
# the rig holds the real SK_ThiefNisha__BodyUpper mesh + retargeted 1P clips;
# otherwise the procedural box-glove fallback below is built instead.
var fp_rig: Node3D
var fp_hand_l_root: Node3D
var fp_hand_r_root: Node3D
var fp_tool_root: Node3D
var fp_anim_player: AnimationPlayer
var _fp_use_real_arms: bool = false
var _fp_anim_lib: RefCounted
var _fp_arm_skel: Skeleton3D
var _fp_arm_holder: Node3D
var _fp_current_clip: String = ""
var _fp_tool_on_bone: bool = false
## True once the physics tick has observed no floor contact. The 1P state
## machine must not read is_on_floor() directly: a rig with physics disabled
## (test/probe) never calls move_and_slide, so is_on_floor() is false at rest
## and a stationary zipwire idle was misclassified as jump_inair (M2.3).
var _fp_airborne: bool = false
## Separate AnimationPlayer for the SK_Zipwire tool skeleton: the gear montage
## animates gear/arrow/spring/blade/hinge/trigger, a different skeleton from the
## 1P arms and 3P body (UE AN_ThiefNisha_Zipwire__Gear_Zipwire_Reload_*).
var _gear_anim_player: AnimationPlayer = null
var _gear_anim_lib: RefCounted = null
var _gear_skel: Skeleton3D = null
var _gear_loop_clip: String = ""
var _gear_current_clip: String = ""
var mesh_3p_glb: String = ""
var fp_tool_id: String = "zipwire"
var equipped_tool: String = "zipwire"
var _slot3_subtool: String = "slithersap"
var _vistara_vision_active: bool = false
var _manual_vision_active: bool = false
## Press timestamp for the KF25/KF26 hold-secondary interact; -1 = not armed.
var _interact_hold_ms: int = -1
## 0..1 hold progress published to the HUD reticle's active takedown arc.
var interact_hold_progress: float = 0.0
var _fp_action_ttl: float = 0.0
var _fp_mat_loader: Node = null
static var _vm_opaque_shader: Shader = null
static var _vm_opaque_cull_disabled_shader: Shader = null
static var _vm_glass_shader: Shader = null
var fp_bob_phase: float = 0.0
var fp_breathe_time: float = 0.0
var fp_step_left: bool = false
var fp_swing_t: float = 0.0
var fp_base_rig_pos: Vector3 = Vector3.ZERO
var fp_highlight_target: Node = null

# Abilities & M2 traversal/tool states
var ability_cooldown: float = 0.0
var disguise_active: bool = false
var disguise_integrity: float = 100.0
var disguise_ttl: float = 0.0
var is_lockpicking: bool = false
var _viewcone_decay_handled: bool = false # retained: external viewcone decay is now queued (see _pending_viewcone_*); flag kept for save-compat, no longer gates the drain.
var _pending_viewcone_delta: float = 0.0 # P1 viewcone call-order: guard calls queue here; _physics_process consumes before its own drain section so external-before-tick order no longer matters.
var _pending_viewcone_in_cone: bool = false
## Launch/winch travel only (LMB launch -> arrival). Attaching to the cable
## with RMB switches to is_wire_hanging, which holds position and owns cranking.
var is_grappling: bool = false
## Attached to the fired cable. Position is held (no gravity/steering) while
## the cable stays live; RMB cranks along it. Cleared on every exit path.
var is_wire_hanging: bool = false
var grapple_target: Vector3 = Vector3.ZERO
var _is_cranking: bool = false
var _crank_elapsed: float = 0.0
var crank_progress: float = 0.0
## RMB-at-arrival attach window and the hanging crank's along-cable speed.
var _wire_arrival_grace: float = 0.0
var _wire_hang_travel_speed: float = 0.0
## LMB launch hold (IA_Ability_Action_Primary_Hold 0.2 s). Armed on press,
## accumulated in physics, cleared on release/cancel.
var _wire_launch_arming: bool = false
var _wire_launch_hold_sec: float = 0.0
var _zipwire_cable_mesh: MeshInstance3D = null
var _smoke_traj_mesh: MeshInstance3D = null
var is_mantling: bool = false
var _mantle_start: Vector3 = Vector3.ZERO
var _mantle_end: Vector3 = Vector3.ZERO
var _mantle_t: float = 0.0
var _mantle_clip_role: String = "mantle_100"
var _was_wall_climbing: bool = false
var is_wall_climbing: bool = false
var astral_active: bool = false
var astral_ttl: float = 0.0

# Gadgets (charges mirror BP MaxAmmo: Slithersap/MagicSlime 4, SmokeBomb 1;
# PickpocketFairy has no ammo field (infinite), Zipwire/Hotwire 4).
# See game/data/generated/gameplay/player_tools.json "sources" and
# docs/reports/tool-mechanics.md.
const SLITHERSAP_CHARGES: int = 4 # BP_MagicSlime_Tool MaxAmmo
const SLITHERSAP_AIM_DISTANCE: float = 30.0 # aim-raycast affordance only; no UE throw-range source
const SMOKE_CHARGES: int = 1 # BP_SmokeBomb_Bomb_Tool
const PICKPOCKET_RANGE: float = 25.0 # BP_Pickpocket_Tool TargetMaxRange 2500 cm
const PICKPOCKET_CONE_DEG: float = 9.0 # TargetMaxViewAngleDeg
const PICKPOCKET_COOLDOWN: float = 0.5 # GE_Pickpocket_Cooldown
const PICKPOCKET_INFINITE_DISPLAY: int = 999 # no ammo field: never consumed; HUD has no infinity glyph
const FAIRY_SPEED: float = 4.5 # BP_PickpocketFairy_FollowActor FairySpeed 450 cm/s
const FAIRY_LIFE: float = 20.0 # FairyLifeDuration
const FAIRY_BLOCK_ANGLE_DEG: float = 30.0 # MaximumFacingAngleToBlock
const FAIRY_STEAL_RADIUS: float = 10.0 # retained: no UE source; loot the mark picks up nearby
const SlipPuddleScript := preload("res://src/interact/slip_puddle.gd")
const ThrownBottleScript := preload("res://src/interact/thrown_bottle.gd")
var charges: Dictionary = {
	"slithersap": 4,
	"smoke_bomb": 1,
	"pickpocket_fairy": 999,
	"grapple": 4,
	"bottle": 0,
}
var pickpocket_cooldown: float = 0.0
var noise_timer: float = 0.0
var _fairy_seq: int = 0 # P1 fairy SceneTree-timer cancel: each cast bumps the seq; stale arrivals (level change, downed mid-flight, superseded cast) return silently.
var _sap_seq: int = 0 # P1 sap arm-delay guard: same stale-timer discipline as the fairy.
var _air_grapple_chains: int = 0 # P1 fall-immunity chains: consecutive airborne grapple/astral engagements without a grounded reset.
var _fall_immunity_revoked: bool = false # set at the chain limit; cleared on grounded reset.
var _interact_hold_sec: float = -1.0 # P2 two-clock hold: physics-delta accumulation replaces wall-clock diffs (pause/slow-mo safe).
var _last_stamina_emitted: float = -1.0 # P2 per-tick signal spam: emit only on change.
var _last_disguise_emitted: float = -1.0
var _last_disguise_active_emitted: bool = false
var _smoke_preview_accum: float = 0.0 # P2 smoke preview: 32-ray ballistic sweep throttled to PROP_SCAN_INTERVAL (was every rendered frame).

var head: Node3D
var cam: Camera3D
var ose_renderer: Node3D
var _npr_enabled: bool = false
var _snn_enabled: bool = false
var spring_arm: SpringArm3D
var col_shape: CollisionShape3D
var mesh_root: Node3D
var light_probe: Node
var level_ctrl: Node
## UI3 light-gem warm sector: world direction and 0..1 strength of the
## strongest nearby light, refreshed at ~4 Hz from the stealth probe's lights.
var light_sector_dir: Vector3 = Vector3.ZERO
var light_sector_strength: float = 0.0
var _light_sector_refresh: float = 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	_apply_tuning()
	_build_body()
	if not OS.has_feature("headless") and DisplayServer.get_name() != "headless" and not MobileProfile.is_mobile():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	if _fp_mat_loader != null and is_instance_valid(_fp_mat_loader):
		_fp_mat_loader.queue_free()
		_fp_mat_loader = null


func _apply_tuning() -> void:
	var diff_x: float = GameState.difficulty_curve_x()
	max_health = GameData.eval_curve("CT_PlayerStats", "BaseHealth", diff_x, 300.0)
	health = max_health
	max_stamina = GameData.eval_curve("CT_PlayerStats", "BaseStamina", diff_x, 260.0)
	stamina = max_stamina
	# GE_Stamina_Regen: 0.25 x StaminaRegenRate per 0.1s tick -> rate x 2.5/s.
	stamina_regen = GameData.eval_curve("CT_PlayerStats", "BaseStaminaRegenRate", diff_x, 2.0) * 2.5
	_load_combat_tuning()


## Real fall/downed/health-block values from generated gameplay JSON.
## Member fallbacks are the extracted UE numbers; they apply only when the
## JSON files are missing or unreadable.
func _load_combat_tuning() -> void:
	_fall_data = _read_generated_json(FALL_DAMAGE_PATH)
	_downed_data = _read_generated_json(DOWNED_PATH)
	_health_block_data = _read_generated_json(HEALTH_BLOCKS_PATH)
	_fall_safe_m = float(_fall_data.get("safe_fall_height_m", FALL_SAFE_M_FALLBACK))
	_fall_death_m = float(_fall_data.get("death_fall_height_m", FALL_DEATH_M_FALLBACK))
	_downed_duration = float(_downed_data.get("downed_duration_s", DOWNED_DURATION_FALLBACK))
	post_revive_cooldown_s = float(_downed_data.get("post_revive_cooldown_s", POST_REVIVE_COOLDOWN_FALLBACK))
	_fall_curve = _build_fall_curve()


static func _read_generated_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		return data
	return {}


## Godot Curve (cubic interpolation) built from the three real
## Curve_FallingDamage keys, tangents included for the UE RCIM_Cubic shape.
func _build_fall_curve() -> Curve:
	var c := Curve.new()
	c.bake_resolution = 64
	var keys: Array = _fall_data.get("curve_keys", [])
	if keys.size() == 3:
		for k: Variant in keys:
			var kd: Dictionary = k
			var t: float = float(kd.get("time", 0.0))
			var v: float = float(kd.get("value", 0.0))
			var lt: float = float(kd.get("arrive_tangent", 0.0))
			var rt: float = float(kd.get("leave_tangent", 0.0))
			c.add_point(Vector2(t, v), lt, rt, Curve.TANGENT_FREE, Curve.TANGENT_FREE)
	else:
		c.add_point(Vector2(0.0, 0.0), 0.0, 0.0, Curve.TANGENT_FREE, Curve.TANGENT_FREE)
		c.add_point(Vector2(0.7, 0.4), 1.2960153, 1.2960153, Curve.TANGENT_FREE, Curve.TANGENT_FREE)
		c.add_point(Vector2(1.0, 1.0), 0.05426467, 0.05426467, Curve.TANGENT_FREE, Curve.TANGENT_FREE)
	return c


## Damage for a vertical fall of drop_m meters: 0 at/below the safe height,
## max_health at/above the death height, and the real 3-key curve as a
## fraction of max_health in between.
func fall_damage_for_drop(drop_m: float) -> float:
	if _fall_curve == null:
		_load_combat_tuning()
	if drop_m <= _fall_safe_m:
		return 0.0
	if drop_m >= _fall_death_m:
		return max_health
	var t: float = clampf((drop_m - _fall_safe_m) / (_fall_death_m - _fall_safe_m), 0.0, 1.0)
	var frac: float = clampf(_fall_curve.sample(t), 0.0, 1.0)
	return frac * max_health


## Landing damage gate. Assumption (no UE source found for immunity): the
## zipwire winch controls descent while grappling and the Moth astral form is
## a spirit, so neither takes fall damage; the peak tracker is refreshed
## instead so no drop accumulates across those states.
## P1 fall-immunity chains: the immunity above is per-engagement. Consecutive
## airborne re-engagements without a grounded reset (release-at-apex +
## re-grapple) revoke it at the chain limit (UE path: none authored; retained
## tuning AIR_GRAPPLE_CHAIN_LIMIT, fail-loud below).
const AIR_GRAPPLE_CHAIN_LIMIT: int = 2
## P1 fall-immunity chains: counts consecutive airborne immune-engagement
## starts (grapple fire, astral activation) without a grounded reset. Starting
## link 3+ revokes the immunity so release-at-apex + re-grapple loops pay
## normal fall damage (UE path: none authored; retained tuning, fail-loud).
func _note_air_link_start() -> void:
	if is_on_floor():
		_air_grapple_chains = 1
		_fall_immunity_revoked = false
		return
	_air_grapple_chains += 1
	if _air_grapple_chains > AIR_GRAPPLE_CHAIN_LIMIT:
		_fall_immunity_revoked = true
		push_warning("[thief] fall immunity revoked: ", _air_grapple_chains, " consecutive air links (UE path: none; retained tuning AIR_GRAPPLE_CHAIN_LIMIT=", AIR_GRAPPLE_CHAIN_LIMIT, ")")
func _apply_fall_damage(drop_m: float) -> float:
	if (is_grappling or is_wire_hanging or astral_active) and not _fall_immunity_revoked:
		return 0.0
	if _fall_immunity_revoked:
		push_warning("[thief] fall immunity revoked after ", _air_grapple_chains, " chained air engagements (no UE immunity chain source; retained tuning AIR_GRAPPLE_CHAIN_LIMIT=", AIR_GRAPPLE_CHAIN_LIMIT, ")")
	var dmg: float = fall_damage_for_drop(drop_m)
	if dmg > 0.0:
		take_damage(dmg, "fall")
	return dmg


## Tracks the airborne peak and converts the air->floor transition into a
## fall-damage event. Call at the top of _physics_process (is_on_floor
## reflects the previous frame's move_and_slide).
func _track_fall_state() -> void:
	var on_floor_now: bool = is_on_floor()
	_fp_airborne = not on_floor_now
	if on_floor_now and not _was_on_floor:
		_apply_fall_damage(_fall_peak_y - global_position.y)
		_fp_play_action("jump_land")
	if on_floor_now:
		_fall_peak_y = global_position.y
		if not is_grappling and not is_wire_hanging and not astral_active:
			_air_grapple_chains = 0
			_fall_immunity_revoked = false
	else:
		if is_grappling or is_wire_hanging or astral_active:
			_fall_peak_y = global_position.y
		else:
			_fall_peak_y = maxf(_fall_peak_y, global_position.y)
	_was_on_floor = on_floor_now


## False while downed: movement, sprint, abilities, tools and interact are
## blocked, but camera look stays live (handled in _unhandled_input).
func can_act() -> bool:
	return not is_downed


func downed_remaining() -> float:
	if not is_downed:
		return 0.0
	return downed_timer


## Health-block split for the current thief (Spider 4x25, Chameleon
## 30/30/20/20). Moth has no extracted row and falls back to Spider;
## documented assumption, not a UE value.
func health_block_percentages() -> Array:
	var picked: Array = []
	var blocks: Variant = _health_block_data.get("blocks", {})
	if blocks is Dictionary:
		if (blocks as Dictionary).has(str(GameState.thief_id)):
			picked = Array((blocks as Dictionary)[str(GameState.thief_id)])
		elif (blocks as Dictionary).has("spider"):
			picked = Array((blocks as Dictionary)["spider"])
	var out: Array = []
	for v: Variant in picked:
		out.append(int(v))
	if out.is_empty():
		return HEALTH_BLOCKS_FALLBACK.duplicate()
	return out


func _enter_downed() -> void:
	if is_downed:
		return
	is_downed = true
	downed_timer = _downed_duration
	_downed_fired = false
	is_sprinting = false
	is_grappling = false
	_exit_wire_states()
	_tp_takedown_stop() # P2: the attacker montage kept playing over the KO loop; stop it on downed.
	downed_started.emit(_downed_duration)


func _tick_downed(delta: float) -> void:
	if not is_downed or _downed_fired:
		return
	downed_timer = maxf(0.0, downed_timer - delta)
	if downed_timer <= 0.0:
		_downed_fired = true
		downed.emit()


func _tick_post_revive(delta: float) -> void:
	if post_revive_ttl > 0.0:
		post_revive_ttl = maxf(0.0, post_revive_ttl - delta)


## Single-player revive is not wired to any ability; this helper restores the
## thief (e.g. after a co-op help-up) and starts the real 3 s post-revive
## cooldown value. Restored HP is full health: the real post-revive attribute
## set (GE_SetPlayerAttributesAfterRecoverFromDowned) was not extracted, so
## full restore is an assumption.
func revive() -> void:
	is_downed = false
	downed_timer = 0.0
	_downed_fired = false
	health = max_health
	health_changed.emit(health, max_health)
	post_revive_ttl = post_revive_cooldown_s
	revived.emit() # P2 hygiene: downed-cleared counterpart to downed_started/downed.


func _build_body() -> void:
	col_shape = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	# Spider capsule: half-height 89 cm, radius 32 cm (centre y = 0.89).
	cap.radius = 0.32
	cap.height = 1.78
	col_shape.shape = cap
	col_shape.position = Vector3(0, 0.89, 0)
	add_child(col_shape)
	floor_max_angle = deg_to_rad(FLOOR_MAX_ANGLE_DEG)
	floor_snap_length = FLOOR_SNAP_LENGTH
	floor_block_on_wall = true
	floor_constant_speed = true

	mesh_root = Node3D.new()
	add_child(mesh_root)
	# Real 3P body (BP_Player_Thief_Spider Mesh3P_Body/Mesh3P_Head):
	# SK_ThiefNisha_Dyn__Body_NoPostProcABP + SK_ThiefNisha_Dyn__Head.
	# Any load failure falls back to the procedural capsule below so there is
	# no regression on machines without the assets.
	var loaded_3p: bool = false
	for glb_path in [THIEF_3P_BODY_GLB, THIEF_3P_HEAD_GLB]:
		var packed_3p: PackedScene = ResourceLoader.load(glb_path) as PackedScene
		if packed_3p == null:
			continue
		var inst_3p: Node = packed_3p.instantiate()
		inst_3p.rotation_degrees.y = 180.0
		mesh_root.add_child(inst_3p)
		loaded_3p = true
	if loaded_3p:
		mesh_3p_glb = THIEF_3P_BODY_GLB
	else:
		var body_mi: MeshInstance3D = MeshInstance3D.new()
		var body_mesh: CapsuleMesh = CapsuleMesh.new()
		body_mesh.radius = 0.32
		body_mesh.height = 1.65
		body_mi.mesh = body_mesh
		body_mi.position = Vector3(0, 0.85, 0)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		match GameState.thief_id:
			"spider": mat.albedo_color = Color(0.18, 0.22, 0.34)
			"chameleon": mat.albedo_color = Color(0.16, 0.32, 0.24)
			_: mat.albedo_color = Color(0.28, 0.2, 0.36)
		body_mi.material_override = mat
		mesh_root.add_child(body_mi)

	mesh_root.visible = false

	head = Node3D.new()
	head.position = Vector3(0, STAND_HEAD_HEIGHT, 0)
	add_child(head)

	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 0.0
	spring_arm.position = Vector3.ZERO
	head.add_child(spring_arm)

	cam = Camera3D.new()
	apply_saved_settings(true)
	cam.fov = base_fov
	cam.current = true
	spring_arm.add_child(cam)
	_build_first_person_rig()
	# C1 renderer: camera-child graph effect, off by default (authored
	# MPC_Painterly EffectIntensity 0). F6/F7 toggle NPR/SNN.
	ose_renderer = OSERendererScript.attach(cam)
	if ose_renderer != null:
		ose_renderer.name = "OSERenderer"


func apply_saved_settings(sync_cam: bool = false) -> void:
	var save_node: Node = get_node_or_null("/root/SaveSystem")
	if save_node == null:
		return
	var data_v: Variant = save_node.get("data")
	if not (data_v is Dictionary):
		return
	var settings_v: Variant = (data_v as Dictionary).get("settings", {})
	if not (settings_v is Dictionary):
		return
	var s: Dictionary = settings_v as Dictionary
	if s.has("mouse_sensitivity"):
		mouse_sens = clampf(float(s["mouse_sensitivity"]), 0.0005, 0.008)
	if s.has("invert_y"):
		invert_y = bool(s["invert_y"])
	if s.has("sprint_toggle"):
		sprint_toggle_mode = bool(s["sprint_toggle"])
	if s.has("reduced_camera_bounce"):
		reduced_camera_bounce = bool(s["reduced_camera_bounce"])
	if s.has("fov"):
		base_fov = clampf(float(s["fov"]), CAMERA_FOV_MIN, CAMERA_FOV_MAX)
	if sync_cam and cam != null:
		cam.fov = base_fov


func _unhandled_input(event: InputEvent) -> void:
	# C1 debug toggles (F6 NPR ink, F7 SNN painterly). Defaults stay off;
	# the authored MPC_Painterly Effect Intensity is 0.0.
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_F6:
				set_npr_effect(not _npr_enabled)
				return
			KEY_F7:
				set_snn_effect(not _snn_enabled)
				return
	if GameState.state != "playing":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not MobileProfile.is_mobile():
		apply_saved_settings()
		var y_dir: float = 1.0 if invert_y else -1.0
		rotate_y(-event.relative.x * mouse_sens)
		head.rotation.x = clampf(head.rotation.x + event.relative.y * mouse_sens * y_dir, deg_to_rad(-80), deg_to_rad(80))
		return
	# Downed: camera look above stays live; everything else is blocked.
	if not can_act():
		return
	if sprint_toggle_mode and event.is_action_pressed("sprint"):
		# P2 hysteresis: a fresh keypress only engages above the start floor;
		# disengaging is free. Recovery never auto-sprints (see physics).
		if _sprint_toggled:
			_sprint_toggled = false
		elif stamina >= SPRINT_START_STAMINA:
			_sprint_toggled = true
	if event.is_action_pressed("crouch"):
		is_crouching = not is_crouching
		var cap: CapsuleShape3D = col_shape.shape as CapsuleShape3D
		if cap != null:
			cap.height = 1.0 if is_crouching else 1.78
			col_shape.position.y = cap.height * 0.5
	elif event.is_action_pressed("interact"):
		# Defer when a hold-secondary is offered; otherwise interact on press.
		if get_look_secondary_prompt() != "":
			_interact_hold_ms = Time.get_ticks_msec()
			_interact_hold_sec = 0.0 # P2 two-clock hold: physics accumulates from here.
		else:
			_interact_hold_ms = -1
			_try_interact()
	elif event.is_action_released("interact"):
		if _interact_hold_ms >= 0:
			# P2 two-clock hold: release reads the physics-accumulated seconds
			# (pause/slow-mo safe), not a wall-clock diff.
			var held_sec: float = maxf(_interact_hold_sec, 0.0)
			_interact_hold_ms = -1
			_interact_hold_sec = -1.0
			if held_sec >= HOLD_INTERACT_SEC:
				_perform_hold_action()
			else:
				_try_interact()
	elif event.is_action_pressed("ability"):
		_trigger_thief_ability()
	elif event.is_action_pressed("tool_1"):
		equip_tool("zipwire")
	elif event.is_action_pressed("tool_2"):
		equip_tool("smoke_bomb")
	elif event.is_action_pressed("tool_3"):
		# Slot [3] pair: Slithersap <-> Pickpocket Fairy, never a dead key.
		if equipped_tool == "slithersap":
			_slot3_subtool = "fairy"
			equip_tool("fairy")
		elif equipped_tool == "fairy":
			_slot3_subtool = "slithersap"
			equip_tool("slithersap")
		else:
			equip_tool(_slot3_subtool)
	elif event.is_action_pressed("tool_4"):
		equip_tool("vistara_diamond")
	elif event.is_action_pressed("primary_action"):
		_use_equipped_primary()
	elif event.is_action_pressed("secondary_action"):
		if equipped_tool == "zipwire":
			# RMB during travel attaches to the cable (hang) and starts the
			# crank; at arrival the grace window does the same. Grounded RMB
			# keeps the legacy crank channel.
			if is_grappling:
				_begin_wire_hang()
			_begin_wire_crank()
		elif int(charges.get("bottle", 0)) > 0:
			_throw_bottle()
	elif event.is_action_released("secondary_action"):
		if _is_cranking:
			# Releasing while hanging keeps the attachment, height and crank
			# progress; the next press resumes the same channel.
			_end_wire_crank(is_wire_hanging)
	elif event.is_action_pressed("thief_vision"):
		_manual_vision_active = not _manual_vision_active
		_sync_thief_vision()


func _slot_for_tool(tool_id: String) -> int:
	match tool_id:
		"zipwire":
			return 1
		"smoke_bomb":
			return 2
		"slithersap", "fairy":
			return 3
		"vistara_diamond":
			return 4
		_:
			return 0


func _sync_thief_vision() -> void:
	var next_on: bool = _vistara_vision_active or _manual_vision_active or astral_active
	if next_on != thief_vision_on:
		thief_vision_on = next_on
		thief_vision = next_on
		thief_vision_toggled.emit(thief_vision_on)
		_update_thief_vision()


func set_npr_effect(enabled: bool) -> void:
	_npr_enabled = enabled
	if ose_renderer != null and ose_renderer.has_method("set_npr"):
		ose_renderer.call("set_npr", enabled)


func set_snn_effect(enabled: bool, intensity: float = 0.65) -> void:
	_snn_enabled = enabled
	if ose_renderer != null and ose_renderer.has_method("set_snn"):
		ose_renderer.call("set_snn", enabled, intensity)


func is_npr_effect_active() -> bool:
	return _npr_enabled


func is_snn_effect_active() -> bool:
	return _snn_enabled


func _audio_gait() -> String:
	if is_crouching:
		return "crouch"
	if is_sprinting:
		return "run"
	return "walk"


## AU3 footstep surface for AudioManager variation pools (PG-6): the Den hub
## (contract 1) is timber; Guildhall stone. Kept to existing GameState data.
func _audio_surface() -> String:
	if GameState.active_contract_order == 1:
		return NoiseBus.SURFACE_WOOD
	return NoiseBus.SURFACE_STONE


## UI3: strongest local light direction for the HUD light-gem warm sector.
## Reuses the stealth probe's registered light set and its falloff shape
## ((1 - d/range)^2 * energy); no extra raycast, since the HUD only needs
## direction and relative strength.
func _refresh_light_sector() -> void:
	light_sector_dir = Vector3.ZERO
	light_sector_strength = 0.0
	if light_probe == null or not is_inside_tree():
		return
	var lights_v: Variant = light_probe.get("registered_lights")
	if not (lights_v is Array):
		return
	var lights: Array = lights_v
	var eye: Vector3 = global_position + Vector3.UP * 1.2
	var best: float = 0.0
	var best_dir: Vector3 = Vector3.ZERO
	for l_var: Variant in lights:
		if not (l_var is Light3D):
			continue
		var l: Light3D = l_var
		if not is_instance_valid(l) or not l.visible or l.light_energy <= 0.01:
			continue
		if l is DirectionalLight3D:
			# Directional light emits along local -Z; +Z points at the source.
			var d_weight: float = clampf(l.light_energy * 0.25, 0.0, 0.35)
			if d_weight > best:
				best = d_weight
				best_dir = l.global_transform.basis.z.normalized()
			continue
		var to_light: Vector3 = l.global_position - eye
		var dist: float = to_light.length()
		var max_range: float = 12.0
		if l is OmniLight3D:
			max_range = (l as OmniLight3D).omni_range
		elif l is SpotLight3D:
			max_range = (l as SpotLight3D).spot_range
		if dist <= 0.01 or dist > max_range:
			continue
		var falloff: float = 1.0 - clampf(dist / max_range, 0.0, 1.0)
		var weight: float = falloff * falloff * l.light_energy
		if weight > best:
			best = weight
			best_dir = to_light / dist
	if best > 0.0:
		light_sector_dir = best_dir
		light_sector_strength = clampf(best / 1.2, 0.2, 1.0)


func equip_tool(tool_id: String) -> void:
	if not (tool_id in ["zipwire", "smoke_bomb", "slithersap", "fairy", "vistara_diamond", "blackjack"]):
		return
	if tool_id != "zipwire":
		_exit_wire_states()
	equipped_tool = tool_id
	_fp_action_ttl = 0.0
	if tool_id == "slithersap" or tool_id == "fairy":
		_slot3_subtool = tool_id
	_vistara_vision_active = (tool_id == "vistara_diamond")
	_sync_thief_vision()
	_fp_set_tool(tool_id)
	if tool_id == "vistara_diamond":
		_fp_play_action("vistara_equip")
	else:
		_update_fp_anim_state()
	tool_equipped.emit(equipped_tool, _slot_for_tool(equipped_tool))


func _use_equipped_primary() -> void:
	match equipped_tool:
		"zipwire":
			_arm_wire_launch()
		"smoke_bomb":
			_use_smoke_bomb()
		"slithersap":
			_use_slithersap()
		"fairy":
			_use_pickpocket_fairy()
		"vistara_diamond":
			_fp_play_action("vistara_equip")
		_:
			_try_blackjack()


## IA_Ability_Action_Primary_Hold: arm the 0.2 s hold. The launch itself is
## fired by _tick_wire_launch once the hold completes; releasing early
## cancels (GA_Hotwire_Child_Launch travel never starts).
func _arm_wire_launch() -> void:
	_wire_launch_arming = true
	_wire_launch_hold_sec = 0.0


func _tick_wire_launch(delta: float) -> void:
	if not _wire_launch_arming:
		return
	if not can_act() or equipped_tool != "zipwire" or not Input.is_action_pressed("primary_action"):
		_wire_launch_arming = false
		_wire_launch_hold_sec = 0.0
		return
	_wire_launch_hold_sec += delta
	if _wire_launch_hold_sec < WIRE_LAUNCH_HOLD_SEC:
		return
	_wire_launch_arming = false
	_wire_launch_hold_sec = 0.0
	_try_spider_grapple()


func get_equipped_tool() -> String:
	return equipped_tool


func get_tool_slots() -> Array[Dictionary]:
	var s3_count: int = int(charges.get("slithersap", 0)) if _slot3_subtool == "slithersap" else -1
	var slots: Array[Dictionary] = [
		{
			"slot": 1,
			"id": "zipwire",
			"count": int(charges.get("grapple", 0)),
			"active": equipped_tool == "zipwire",
		},
		{
			"slot": 2,
			"id": "smoke_bomb",
			"count": int(charges.get("smoke_bomb", 0)),
			"active": equipped_tool == "smoke_bomb",
		},
		{
			"slot": 3,
			"id": _slot3_subtool,
			"count": s3_count,
			"active": equipped_tool == "slithersap" or equipped_tool == "fairy",
		},
		{
			"slot": 4,
			"id": "vistara_diamond",
			"count": -1,
			"active": equipped_tool == "vistara_diamond",
		},
	]
	return slots


func get_active_reticle_state() -> Dictionary:
	var target_valid: bool = false
	var hints: Array[Dictionary] = []
	match equipped_tool:
		"zipwire":
			var zw: Dictionary = validate_zipwire_target()
			target_valid = zw.get("valid", false) == true
			var can_launch: bool = target_valid and ability_cooldown <= 0.0 and int(charges.get("grapple", 0)) > 0
			var can_crank: bool = is_wire_hanging or (not is_grappling and (ability_cooldown > 0.0 or int(charges.get("grapple", 0)) < GRAPPLE_MAX_CHARGES))
			hints.append({"key": "LMB", "label": "LAUNCH", "enabled": can_launch})
			hints.append({"key": "RMB", "label": "[HOLD] CRANK", "enabled": can_crank})
		"smoke_bomb":
			target_valid = int(charges.get("smoke_bomb", 0)) > 0
			hints.append({"key": "LMB", "label": "THROW", "enabled": target_valid})
		"slithersap":
			target_valid = int(charges.get("slithersap", 0)) > 0
			hints.append({"key": "LMB", "label": "SPLASH", "enabled": target_valid})
		"fairy":
			var fwd: Vector3 = -cam.global_transform.basis.z if cam != null else -global_transform.basis.z
			var guards: Array = get_tree().get_nodes_in_group("guards") if is_inside_tree() else []
			target_valid = pickpocket_select_target(guards, global_position, fwd) != null
			hints.append({"key": "LMB", "label": "PICK POCKET", "enabled": pickpocket_cooldown <= 0.0})
		"vistara_diamond":
			target_valid = true
			hints.append({"key": "4", "label": "THIEF VISION", "enabled": true})
		_:
			target_valid = is_inside_tree() and _find_nearest_guard(2.4) != null
			hints.append({"key": "LMB", "label": "TAKEDOWN", "enabled": true})
	return {
		"mode": equipped_tool,
		"target_valid": target_valid,
		"crank_progress": crank_progress,
		"crank_active": _is_cranking,
		"hints": hints,
	}


func is_thief_vision_active() -> bool:
	# P2 dual vision vars: thief_vision_on is the single source of truth;
	# thief_vision mirrors it for legacy readers. New code must call this.
	return thief_vision_on


## Touch look hook used by src/ui/mobile_touch_ui.gd: mouse look is unavailable on Android.
func add_look_pixel_delta(delta_px: Vector2) -> void:
	if GameState.state != "playing":
		return
	if absf(delta_px.x) < 0.001 and absf(delta_px.y) < 0.001:
		return
	apply_saved_settings()
	var y_dir: float = 1.0 if invert_y else -1.0
	rotate_y(-delta_px.x * mouse_sens)
	if head != null:
		head.rotation.x = clampf(head.rotation.x + delta_px.y * mouse_sens * y_dir, deg_to_rad(-80), deg_to_rad(80))


func _physics_process(delta: float) -> void:
	if GameState.state != "playing":
		_update_zipwire_cable()
		return
	ability_cooldown = maxf(0.0, ability_cooldown - delta)
	pickpocket_cooldown = maxf(0.0, pickpocket_cooldown - delta)
	_wire_arrival_grace = maxf(0.0, _wire_arrival_grace - delta)
	_tick_astral(delta)
	_tick_downed(delta)
	_tick_post_revive(delta)
	_track_fall_state()

	# Downed: no input movement, sprint, abilities or tools; gravity still
	# settles the body and the downed timer (above) runs to mission failure.
	if is_downed:
		_exit_wire_states()
		is_mantling = false
		is_wall_climbing = false
		is_grappling = false # P2 single-entry invariant: _enter_downed clears this too; both sites clear so neither can strand the winch.
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		_update_zipwire_cable()
		return

	# Smooth crouch camera height interpolation.
	var target_head_h: float = CROUCH_HEAD_HEIGHT if is_crouching else STAND_HEAD_HEIGHT
	head.position.y = lerpf(head.position.y, target_head_h, delta * 10.0)

	# Wall-raycast-clamped Q/R lean.
	var target_lean: float = 0.0
	if Input.is_action_pressed("lean_left"):
		target_lean -= 1.0
	if Input.is_action_pressed("lean_right"):
		target_lean += 1.0
	if target_lean != 0.0:
		target_lean *= _get_lean_wall_factor(signf(target_lean))
	lean_dir = lerpf(lean_dir, target_lean, delta * 10.0)
	head.position.x = lean_dir * LEAN_OFFSET
	head.rotation.z = -lean_dir * LEAN_ROLL

	# Active Zipwire [RMB] crank tick.
	_tick_wire_crank(delta, false)
	# LMB 0.2 s hold -> GA_Hotwire_Child_Launch travel.
	_tick_wire_launch(delta)

	# Cable hang: hold the attach point with no gravity or steering. The crank
	# tick above already performed any collision-safe along-cable movement and
	# completion may have dropped the hang, so re-check the live state.
	if is_wire_hanging:
		if not _is_cranking:
			velocity = Vector3.ZERO
			_fall_peak_y = global_position.y
		_tick_sustained_systems(delta)
		_update_zipwire_cable()
		return

	# Auto-mantle interpolation (BP_Player_Base _mantleSettings + GE_Traversal_AutoMantle 0.3s).
	# P1 mantle-skips-systems: stamina regen, disguise drain, light probe and
	# hold progress tick here too (via _tick_sustained_systems) so the 0.3 s
	# traversal no longer freezes them (disguise-TTL pause exploit + hold freeze).
	if is_mantling:
		_mantle_t = minf(1.0, _mantle_t + delta / 0.3)
		var smooth_t: float = _mantle_t * _mantle_t * (3.0 - 2.0 * _mantle_t)
		global_position = _mantle_start.lerp(_mantle_end, smooth_t)
		velocity = Vector3.ZERO
		_fall_peak_y = global_position.y
		stamina = minf(max_stamina, stamina + stamina_regen * delta)
		_emit_stamina_if_changed()
		_tick_sustained_systems(delta)
		if _mantle_t >= 1.0:
			is_mantling = false
			global_position = _mantle_end
		_update_zipwire_cable()
		return

	# Spider grapple pull override (smooth winch ramp toward the anchor, then
	# preserve momentum and vault upward on arrival/release).
	if is_grappling:
		var wire_speed: float = WIRE_PULL_SPEED
		grapple_time += delta
		var to_anchor: Vector3 = grapple_target - global_position
		var anchor_dist: float = to_anchor.length()
		var raw_released: bool = Input.is_action_just_released("ability") or Input.is_action_just_released("tool_4") or Input.is_action_just_released("primary_action")
		# P1 tap-fire hop: a tap-to-fire releases on the next physics frame with
		# winch starting at 0.3 (instant vault). Releases shorter than
		# GRAPPLE_MIN_HOLD_SEC keep the winch engaged so quick taps pull.
		var released: bool = raw_released and grapple_time >= GRAPPLE_MIN_HOLD_SEC
		var winch: float = clampf(grapple_time / GRAPPLE_WINCH_TIME, 0.3, 1.0)
		var pull_dir: Vector3 = to_anchor.normalized() if anchor_dist > 0.05 else Vector3.ZERO
		if anchor_dist < GRAPPLE_ARRIVE_DIST or released:
			# RMB held/pressed at arrival attaches to the cable instead of
			# dropping it: the winch becomes a hang and cranking starts.
			if Input.is_action_pressed("secondary_action"):
				_begin_wire_hang()
				_begin_wire_crank()
				_update_zipwire_cable()
				return
			is_grappling = false
			# Keep the just-fired cable attachable for a short window so a
			# near-simultaneous RMB press still hangs "at arrival".
			_wire_arrival_grace = WIRE_ARRIVAL_GRACE_SEC
			velocity = pull_dir * wire_speed * (0.45 + 0.15 * winch)
			velocity.y = maxf(velocity.y, GRAPPLE_VAULT_Y * (0.7 + 0.3 * winch))
			move_and_slide()
			_update_zipwire_cable()
			return
		else:
			var desired: Vector3 = pull_dir * wire_speed * winch + Vector3.UP * 1.4
			velocity = velocity.lerp(desired, clampf(delta * 7.0, 0.0, 1.0))
			move_and_slide()
			_update_zipwire_cable()
			return

	_update_zipwire_cable()

	# Movement & Stamina
	apply_saved_settings()
	var inp: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish: Vector3 = (transform.basis * Vector3(inp.x, 0.0, inp.y)).normalized()
	if sprint_toggle_mode:
		# P2 hysteresis: dropping the toggle needs the stop floor; re-enabling
		# needs a fresh keypress (gated at the input site) so stamina recovery
		# never auto-sprints.
		if wish.length() <= 0.1 or is_crouching or stamina <= SPRINT_STOP_STAMINA:
			_sprint_toggled = false
		is_sprinting = _sprint_toggled and not is_crouching and wish.length() > 0.1 and stamina > SPRINT_STOP_STAMINA
	else:
		var want_sprint: bool = Input.is_action_pressed("sprint") and not is_crouching and wish.length() > 0.1
		if want_sprint and not is_sprinting and stamina < SPRINT_START_STAMINA:
			want_sprint = false
		is_sprinting = want_sprint and stamina > SPRINT_STOP_STAMINA

	var climbing_now: bool = _tick_wall_climb(delta, wish)
	var speed: float = walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting:
		speed = sprint_speed
		# P2 absf sign check: CT_StaminaSystem.Sprint stores a drain (<= 0).
		# absf would silently turn a future positive regen row into a drain.
		var raw_drain: float = GameData.eval_curve("CT_StaminaSystem", "StaminaPerSecond.Sprint", 1.0, -5.0)
		if raw_drain > 0.0:
			push_error("[thief] CT_StaminaSystem.StaminaPerSecond.Sprint returned positive ", raw_drain, "; expected a drain (UE CT_StaminaSystem)")
			assert(false, "sprint stamina curve sign flipped positive")
		var drain: float = absf(raw_drain)
		stamina = maxf(0.0, stamina - drain * delta)
	elif not climbing_now:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)
	_emit_stamina_if_changed()

	# Velocity FOV feedback (BP_CameraModifier_VelocityFOV) honoring persisted base_fov
	var target_fov: float = (base_fov + (CAMERA_FOV_SPRINT - CAMERA_FOV)) if is_sprinting else base_fov
	cam.fov = lerpf(cam.fov, target_fov, delta * 8.0)

	if not climbing_now:
		if not is_on_floor():
			velocity.y -= gravity * delta
		elif Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
			_fp_play_action("jump_inair")

		var steer: float = 14.0 if is_on_floor() else 14.0 * AIR_CONTROL
		velocity.x = lerpf(velocity.x, wish.x * speed, delta * steer)
		velocity.z = lerpf(velocity.z, wish.z * speed, delta * steer)
	move_and_slide()

	# Stair step-up assist, bounded by the 0.3 m snap philosophy. When the body
	# is grounded but a riser face blocked horizontal motion, test a lift ->
	# forward -> down sequence and commit only if all three fit: headroom must
	# be free, the lifted pose must advance one tread, and a floor must catch
	# the drop. 0.18 m risers climb; 0.6 m walls still block, and
	# floor_block_on_wall keeps true walls solid. One assist per frame at most.
	if not climbing_now and not is_mantling and is_on_floor() and is_on_wall():
		var push_dir := Vector3(wish.x, 0.0, wish.z)
		if push_dir.length() > 0.05:
			push_dir = push_dir.normalized()
			if not test_move(global_transform, Vector3.UP * (STEP_UP_MAX_M + STEP_UP_SKIN_M)):
				var stepped := global_transform
				stepped.origin += Vector3.UP * STEP_UP_MAX_M
				if not test_move(stepped, push_dir * STEP_UP_FORWARD_M):
					stepped.origin += push_dir * STEP_UP_FORWARD_M
					if test_move(stepped, Vector3.DOWN * (STEP_UP_MAX_M + FLOOR_SNAP_LENGTH)):
						global_position = stepped.origin

	# Grounded mantle: walking into a 0.5-1.2 m ledge used to do nothing until
	# the player jumped. is_on_wall() is populated by the move_and_slide above.
	if not is_mantling and (not is_on_floor() or is_on_wall()) 			and (Input.is_action_pressed("jump") or wish.length() > 0.1):
		try_auto_mantle()

	# Footstep cadence timer while moving on floor. Astral form makes no noise.
	var planar_speed: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar_speed > 0.5 and not astral_active:
		fp_bob_phase += delta * (9.0 if is_sprinting else 6.5)
		noise_timer -= delta
		if noise_timer <= 0.0:
			var loudness: float = 3.5
			if is_crouching:
				loudness = 1.5
			elif is_sprinting:
				loudness = 8.0
			NoiseBus.emit_noise(global_position, loudness, self, "footstep")
			if AudioManager != null and AudioManager.has_method("play_footstep"):
				AudioManager.play_footstep(_audio_surface(), _audio_gait(), global_position)
			fp_step_left = not fp_step_left
			var fwd_flat: Vector3 = Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
			if fwd_flat.length() < 0.05:
				fwd_flat = Vector3(0.0, 0.0, -1.0)
			fwd_flat = fwd_flat.normalized()
			VfxManager.spawn_footprint_decal(global_position, fwd_flat, fp_step_left)
			if is_crouching:
				noise_timer = 0.5
			elif is_sprinting:
				noise_timer = 0.28
			else:
				noise_timer = 0.4
	# Interactive-prop highlight scanning is throttled to 10 Hz instead of every
	# physics tick (it walks the interactables/guards groups).
	_prop_scan_accum += delta
	if _prop_scan_accum >= PROP_SCAN_INTERVAL:
		_prop_scan_accum = 0.0
		_update_prop_highlight()

	# Chameleon Disguise Integrity drain + light probe + hold progress. Held in
	# one helper so the mid-mantle branch ticks the identical systems (P1).
	_tick_sustained_systems(delta)


## P1 mantle-skips-systems: sustained per-tick systems that must run even
## mid-mantle (called from the mantle branch and from the normal path).
## P1 viewcone call-order: queued external decay is consumed here, before the
## local scan, so guard-call-vs-tick ordering no longer matters.
## P2 two-clock hold: progress accumulates from physics delta (pause-safe).
## P2 signal spam: stamina/disguise emit only on change (see _emit_*).
func _tick_sustained_systems(delta: float) -> void:
	# Chameleon Disguise Integrity drain. Per-second rates are summed from all 6
	# enabled rows of DT_DisguiseV3IntegrityReduction (DisguiseTimer, Sprinting,
	# GuardProximity, Lockpicking, GuardViewCone; DamageTaken is in take_damage).
	if disguise_active:
		var guard_near: bool = _is_guard_within(DISGUISE_GUARD_PROXIMITY_M)
		var in_cone: bool = _consume_pending_viewcone() or _is_in_guard_viewcone()
		var drain_rate: float = disguise_drain_rate(is_sprinting, guard_near, is_lockpicking, in_cone)
		disguise_integrity = maxf(0.0, disguise_integrity - drain_rate * delta)
		disguise_ttl = maxf(0.0, disguise_ttl - delta)
		if disguise_ttl <= 0.0:
			disguise_active = false
		if disguise_integrity <= 0.0:
			disguise_integrity = 0.0
			disguise_active = false
		_emit_disguise_if_changed()
	_viewcone_decay_handled = false
	# Light visibility probe
	if light_probe != null and light_probe.has_method("sample_visibility"):
		var excl: Array[RID] = [get_rid()]
		GameState.player_light_visibility = light_probe.sample_visibility(global_position, get_world_3d().direct_space_state, excl)
		_light_sector_refresh -= delta
		if _light_sector_refresh <= 0.0:
			_light_sector_refresh = 0.25
			_refresh_light_sector()
	if _interact_hold_ms >= 0:
		_interact_hold_sec += delta
		interact_hold_progress = clampf(_interact_hold_sec / HOLD_INTERACT_SEC, 0.0, 1.0)
	else:
		_interact_hold_sec = -1.0
		interact_hold_progress = 0.0


## P2 per-tick signal spam: stamina_changed fires only when the value moved.
func _emit_stamina_if_changed() -> void:
	if absf(stamina - _last_stamina_emitted) > 0.01:
		_last_stamina_emitted = stamina
		stamina_changed.emit(stamina, max_stamina)


## P2 per-tick signal spam: disguise_changed fires only when integrity or state moved.
func _emit_disguise_if_changed() -> void:
	if absf(disguise_integrity - _last_disguise_emitted) > 0.01 or disguise_active != _last_disguise_active_emitted:
		_last_disguise_emitted = disguise_integrity
		_last_disguise_active_emitted = disguise_active
		disguise_changed.emit(disguise_integrity, disguise_active)


## P1 viewcone call-order: consume the queued external decay (one drain per
## tick no matter how many guards called, no ordering dependence).
func _consume_pending_viewcone() -> bool:
	var pending: bool = _pending_viewcone_in_cone
	_pending_viewcone_in_cone = false
	_pending_viewcone_delta = 0.0
	return pending


## Attaches to the live fired cable (RMB during travel, or within the arrival
## grace window). Launch/travel remains is_grappling; the hang owns position
## and cranking until completion or an explicit exit.
func _begin_wire_hang() -> void:
	if not can_act() or equipped_tool != "zipwire":
		return
	if is_wire_hanging:
		return
	if not is_grappling and _wire_arrival_grace <= 0.0:
		return
	is_grappling = false
	is_wire_hanging = true
	_wire_arrival_grace = 0.0
	velocity = Vector3.ZERO
	_fall_peak_y = global_position.y
	_crank_elapsed = 0.0
	crank_progress = 0.0
	var dur: float = GameData.eval_curve("CT_WireCrank", "CrankDuration", 0.0, WIRE_CRANK_DURATION_FALLBACK)
	if dur <= 0.0:
		dur = WIRE_CRANK_DURATION_FALLBACK
	var travel_room: float = maxf(0.0, global_position.distance_to(grapple_target) - WIRE_HANG_STANDOFF)
	_wire_hang_travel_speed = travel_room / maxf(dur, WIRE_CRANK_MIN_TIME)
	_update_zipwire_cable()


## Starts/continues the [RMB] crank. While travelling (or inside the arrival
## grace) the first press attaches to the cable; a connected hang preserves
## crank progress across release/re-press. Grounded crank keeps the legacy
## channel that restores a charge after a full hold.
func _begin_wire_crank() -> void:
	# P1 crank-on-wall-climb: GA_Hotwire_Crank never authorizes crank while
	# climbing (UE crank is a grounded/channelled action); wall-climb excluded
	# at both entry and tick so no charge accrues mid-climb.
	if not can_act() or equipped_tool != "zipwire" or is_mantling or is_wall_climbing:
		return
	if not is_wire_hanging and (is_grappling or _wire_arrival_grace > 0.0):
		_begin_wire_hang()
	if not is_wire_hanging:
		# Grounded crank channel: a fresh press restarts the 6 s reward.
		_crank_elapsed = 0.0
		crank_progress = 0.0
	_is_cranking = true
	_play_wire_crank_clip()
	_start_gear_crank()


## Starts the looping zipwire crank 1P clip (AN_ThiefNisha_Zipwire__Reload_Loop
## via ensure_fp_clip; 1P viewmodel of the F13 UE montage
## TAT/Content/Art/Animation/Thief/Anim/Gear/Zipwire/AN_Zipwire_Crank_Montage).
## Logged no-op when the manifest lacks the clip, the retarget shares zero
## bones, or the real-arms rig is off; never crashes. The per-frame state
## machine (_update_fp_anim_state) sustains the loop while _is_cranking holds.
## Also starts the 3P drive (_tp_crank_start): the AN_Zipwire_Crank_Montage
## player on the firing thief rig plus the crank-handle spin, so the handle
## moves when cranking after firing even where the 1P viewmodel is hidden.
func _play_wire_crank_clip() -> void:
	if not _fp_use_real_arms or fp_anim_player == null or _fp_anim_lib == null:
		push_warning("ZipwireCrank: crank clip no-op without real arms (UE clip TAT/Content/Art/Animation/ThiefNisha/Anim/Zipwire/AN_ThiefNisha_Zipwire__Reload_Loop)")
		_tp_crank_start()
		return
	var clip_name: String = str(_fp_anim_lib.call("ensure_fp_clip", fp_anim_player, "zipwire_crank"))
	if clip_name == "":
		push_warning("ZipwireCrank: crank clip no-op, manifest lacks clip or zero shared bones (UE clip TAT/Content/Art/Animation/ThiefNisha/Anim/Zipwire/AN_ThiefNisha_Zipwire__Reload_Loop)")
		_tp_crank_start()
		return
	_fp_play_fp_clip(clip_name)
	_tp_crank_start()


func _tick_wire_crank(delta: float, force_holding: bool = false) -> void:
	if not _is_cranking:
		return
	var holding: bool = force_holding or Input.is_action_pressed("secondary_action")
	if not holding or equipped_tool != "zipwire" or is_mantling or is_wall_climbing or not can_act():
		# A connected hang pauses in place (progress/cable kept); anything
		# else is a real cancel and resets the charge channel.
		_end_wire_crank(is_wire_hanging)
		return
	_crank_elapsed += delta
	var dur: float = GameData.eval_curve("CT_WireCrank", "CrankDuration", 0.0, WIRE_CRANK_DURATION_FALLBACK)
	if dur <= 0.0:
		dur = WIRE_CRANK_DURATION_FALLBACK
	crank_progress = clampf(_crank_elapsed / maxf(dur, WIRE_CRANK_MIN_TIME), 0.0, 1.0)
	if is_wire_hanging:
		_move_along_cable(delta)
	_tp_crank_tick()
	_tick_gear_crank()
	if _crank_elapsed >= dur:
		ability_cooldown = 0.0
		charges["grapple"] = mini(GRAPPLE_MAX_CHARGES, int(charges.get("grapple", 0)) + 1)
		tool_used.emit("zipwire_crank", int(charges["grapple"]))
		_tp_crank_stop()
		_is_cranking = false
		_crank_elapsed = 0.0
		crank_progress = 0.0
		if is_wire_hanging:
			_finish_wire_hang_arrival()
		else:
			_update_zipwire_cable()


## Collision-safe along-cable pull during a hanging crank: move_and_collide
## stops at the first contact, so the body can never tunnel or teleport. The
## attach-time speed covers the remaining cable room over one full crank.
func _move_along_cable(delta: float) -> void:
	if _wire_hang_travel_speed <= 0.0:
		return
	var to_target: Vector3 = grapple_target - global_position
	var dist: float = to_target.length()
	var room: float = dist - WIRE_HANG_STANDOFF
	if room <= 0.001:
		return
	var step: float = minf(_wire_hang_travel_speed * delta, room)
	if step <= 0.0:
		return
	var dir: Vector3 = to_target / maxf(dist, 0.0001)
	move_and_collide(dir * step)


## Full hanging crank: grant the charge, drop the cable, reset gear/handle and
## push a small collision-safe arrival hop toward the anchor.
func _finish_wire_hang_arrival() -> void:
	var to_target: Vector3 = grapple_target - global_position
	var horiz: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	if horiz.length() > 0.001:
		horiz = horiz.normalized()
	else:
		horiz = -global_transform.basis.z
	is_wire_hanging = false
	_wire_arrival_grace = 0.0
	_wire_hang_travel_speed = 0.0
	velocity = horiz * 1.5 + Vector3.UP * 2.0
	_fall_peak_y = global_position.y
	_update_zipwire_cable()


## Drops hang + crank + cable (tool switch, downed, astral, new grapple).
func _exit_wire_states() -> void:
	if _is_cranking:
		_end_wire_crank()
	is_wire_hanging = false
	_wire_arrival_grace = 0.0
	_wire_hang_travel_speed = 0.0
	_crank_elapsed = 0.0
	crank_progress = 0.0
	_update_zipwire_cable()


func _end_wire_crank(keep_hang: bool = false) -> void:
	if not _is_cranking:
		return
	_tp_crank_stop()
	# P1 crank 0.5 s trickle refund removed: GA_Hotwire_Crank.MinimumCrankTime
	# gates the channel, but only a FULL crank (see _tick_wire_crank) clears
	# the cooldown and grants the charge. Partial cranks now grant nothing, so
	# repeated taps can no longer offset WireCooldownSecondary without
	# completing (UE GA_Hotwire_Crank full-crank reward).
	_is_cranking = false
	if keep_hang and is_wire_hanging:
		# Early RMB release while attached holds position and keeps progress;
		# the next press resumes this same channel.
		return
	_crank_elapsed = 0.0
	crank_progress = 0.0


func _update_zipwire_cable() -> void:
	if not (is_grappling or is_wire_hanging or _wire_arrival_grace > 0.0):
		if _zipwire_cable_mesh != null and is_instance_valid(_zipwire_cable_mesh):
			_zipwire_cable_mesh.visible = false
		return
	if not is_inside_tree():
		return
	if _zipwire_cable_mesh == null or not is_instance_valid(_zipwire_cable_mesh):
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.022 # BP_Hotwire_Cable CableWidth 5cm (~0.044m diameter)
		cyl.bottom_radius = 0.022
		cyl.height = 1.0
		# 12 radial x 8 rings keeps the cable round and taut up close (KF17)
		# instead of the old 8-sided single-ring tube.
		cyl.radial_segments = 12
		cyl.rings = 8
		var cmat: Material = null
		var loader: Node = _get_fp_mat_loader()
		if loader != null:
			cmat = loader.call("get_material_for_ue", ZIPWIRE_CABLE_MAT) as Material
		if cmat == null:
			# Fallback only when the material DB is unavailable: authored steel,
			# never emissive (UE OSECableComponent has no glow on traversal).
			var fallback := StandardMaterial3D.new()
			fallback.albedo_color = Color(0.06, 0.065, 0.07, 1.0)
			fallback.roughness = 0.45
			fallback.metallic = 0.35
			cmat = fallback
		cyl.material = cmat
		_zipwire_cable_mesh = MeshInstance3D.new()
		_zipwire_cable_mesh.name = "ZipwireCableMesh"
		_zipwire_cable_mesh.top_level = true
		_zipwire_cable_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_zipwire_cable_mesh.mesh = cyl
		add_child(_zipwire_cable_mesh)
	var from_pos: Vector3 = global_position + Vector3.UP * 1.2
	if fp_tool_root != null and is_instance_valid(fp_tool_root) and fp_tool_root.is_inside_tree():
		# SK_Zipwire muzzle (max x ~= 0.3377 m in tool space), not the hand.
		from_pos = fp_tool_root.global_transform * Vector3(0.34, 0.0, 0.0)
	var offset: Vector3 = grapple_target - from_pos
	var dist: float = offset.length()
	if dist < 0.05:
		_zipwire_cable_mesh.visible = false
		return
	_zipwire_cable_mesh.visible = true
	var y_axis: Vector3 = offset / dist
	var up_hint: Vector3 = Vector3.RIGHT if absf(y_axis.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x_axis: Vector3 = up_hint.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	_zipwire_cable_mesh.global_position = (from_pos + grapple_target) * 0.5
	# Stretch along the local Y column. Basis.scaled() scales rows, which
	# sheared the tube off the muzzle-to-anchor line for diagonal cables.
	_zipwire_cable_mesh.basis = Basis(x_axis, y_axis * dist, z_axis)


func try_auto_mantle() -> bool:
	if not can_act() or is_grappling or is_wire_hanging or is_mantling or not is_inside_tree():
		return false
	var w3d := get_world_3d()
	if w3d == null:
		return false
	var space: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var fwd: Vector3 = Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
	if fwd.length() < 0.05:
		return false
	fwd = fwd.normalized()
	var excl: Array[RID] = [get_rid()]
	var wall_hit: Dictionary = {}
	for h_off: float in [0.5, 1.1, 1.7]:
		var from: Vector3 = global_position + Vector3.UP * h_off
		var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 0.85, 1, excl)
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			wall_hit = hit
			break
	if wall_hit.is_empty():
		return false
	var wn: Vector3 = wall_hit.get("normal", Vector3.ZERO) as Vector3
	if absf(wn.y) > 0.35:
		return false
	var wall_in: Vector3 = Vector3(-wn.x, 0.0, -wn.z)
	if wall_in.length() < 0.05:
		return false
	if rad_to_deg(wall_in.normalized().angle_to(fwd)) > MANTLE_MAX_ANGLE_DEG:
		return false
	var wp: Vector3 = wall_hit["position"] as Vector3
	var top_from: Vector3 = Vector3(wp.x + fwd.x * 0.45, global_position.y + MANTLE_MAX_HEIGHT_M + 0.25, wp.z + fwd.z * 0.45)
	var top_to: Vector3 = Vector3(top_from.x, global_position.y + 0.45, top_from.z)
	var top_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(top_from, top_to, 1, excl))
	if top_hit.is_empty():
		return false
	var ledge_n: Vector3 = top_hit.get("normal", Vector3.ZERO) as Vector3
	if ledge_n.dot(Vector3.UP) < 0.7:
		return false
	var ledge_pos: Vector3 = top_hit["position"] as Vector3
	var ledge_h: float = ledge_pos.y - global_position.y
	if ledge_h < 0.45 or ledge_h > MANTLE_MAX_HEIGHT_M:
		return false
	var need_h: float = 1.05 if is_crouching else 1.8
	var head_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(ledge_pos + Vector3.UP * 0.1, ledge_pos + Vector3.UP * need_h, 1, excl))
	if not head_hit.is_empty():
		return false
	is_mantling = true
	is_wall_climbing = false
	_mantle_t = 0.0
	_mantle_start = global_position
	_mantle_end = ledge_pos + Vector3.UP * 0.05
	_fall_peak_y = ledge_pos.y
	if ledge_h < 0.75:
		_mantle_clip_role = "mantle_050"
	elif ledge_h < 1.25:
		_mantle_clip_role = "mantle_100"
	elif ledge_h < 1.75:
		_mantle_clip_role = "mantle_150"
	elif ledge_h < 2.25:
		_mantle_clip_role = "mantle_200"
	elif ledge_h < 2.75:
		_mantle_clip_role = "mantle_250"
	else:
		_mantle_clip_role = "mantle_300"
	_fp_play_action(_mantle_clip_role)
	return true


func _tick_wall_climb(delta: float, wish: Vector3) -> bool:
	var was_climbing: bool = is_wall_climbing
	if is_on_floor() or is_crouching or is_grappling or is_wire_hanging or is_mantling or stamina <= 2.0 or not is_inside_tree():
		is_wall_climbing = false
		return false
	var w3d := get_world_3d()
	if w3d == null:
		is_wall_climbing = false
		return false
	var fwd: Vector3 = Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
	if fwd.length() < 0.05:
		is_wall_climbing = false
		return false
	fwd = fwd.normalized()
	var from: Vector3 = global_position + Vector3.UP * 1.1
	var hit: Dictionary = w3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + fwd * 0.65, 1, [get_rid()]))
	if hit.is_empty():
		is_wall_climbing = false
		return false
	var wn: Vector3 = hit.get("normal", Vector3.ZERO) as Vector3
	if absf(wn.y) > 0.35:
		is_wall_climbing = false
		return false
	var pressing_into_wall: bool = (wish.length() > 0.1 and wish.dot(-wn) > 0.3) or Input.is_action_pressed("jump")
	if not pressing_into_wall:
		is_wall_climbing = false
		return false
	is_wall_climbing = true
	if not was_climbing:
		_fp_play_action("climb_wall")
	velocity.y = move_toward(velocity.y, WALL_CLIMB_SPEED, WALL_CLIMB_ACCEL * delta)
	velocity.x = -wn.x * 0.5
	velocity.z = -wn.z * 0.5
	var climb_curve: float = absf(GameData.eval_curve("CT_StaminaSystem", "StaminaPerSecond.Climb.Base", 1.0, 0.0))
	var climb_burn: float = climb_curve if climb_curve > 0.0 else CLIMB_STAMINA_BURN_FALLBACK
	stamina = maxf(0.0, stamina - climb_burn * delta)
	_fall_peak_y = global_position.y
	if stamina <= 0.0:
		is_wall_climbing = false
	return is_wall_climbing


func _get_lean_wall_factor(side_sign: float) -> float:
	if head == null:
		return 1.0
	if side_sign == 0.0:
		return 1.0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var side: Vector3 = global_transform.basis.x.normalized() * side_sign
	var from: Vector3 = head.global_position
	var to: Vector3 = from + side * LEAN_WALL_CHECK_DIST
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	var hit_pos: Vector3 = hit["position"] as Vector3
	var dist: float = from.distance_to(hit_pos)
	return clampf(dist / LEAN_WALL_CHECK_DIST, 0.0, 1.0)


func _is_guard_within(dist_max: float) -> bool:
	var guards: Array[Node] = get_tree().get_nodes_in_group("guards")
	for g: Node in guards:
		if g is Node3D:
			var guard_node: Node3D = g as Node3D
			if global_position.distance_to(guard_node.global_position) <= dist_max:
				return true
	return false


## Authored per-second disguise drain from the 6 enabled rows of
## DT_DisguiseV3IntegrityReduction: DisguiseTimer (1.0/s), Sprinting (40.0/s),
## GuardProximity (5.0/s <= 1.0 m), Lockpicking (5.0/s, Status.Lockpicking),
## GuardViewCone (10.0/s <= 10.0 m & <= 65 deg); DamageTaken (40.0) in take_damage.
static func disguise_drain_rate(
	sprinting: bool,
	guard_near: bool,
	lockpicking: bool = false,
	in_viewcone: bool = false
) -> float:
	var rate: float = DISGUISE_DRAIN_TIMER
	if sprinting:
		rate += DISGUISE_DRAIN_SPRINTING
	if guard_near:
		rate += DISGUISE_DRAIN_GUARD_PROXIMITY
	if lockpicking:
		rate += DISGUISE_DRAIN_LOCKPICKING
	if in_viewcone:
		rate += DISGUISE_DRAIN_GUARD_VIEWCONE
	return rate


func set_lockpicking_active(active: bool) -> void:
	is_lockpicking = active


func apply_guard_viewcone_disguise_decay(delta: float, in_cone: bool) -> void:
	# P1 viewcone call-order: the old code drained immediately AND set the
	# handled flag, so correctness depended on the external call landing before
	# this tick's drain section (and two guards per tick double-drained).
	# Now the call only queues; _tick_sustained_systems consumes once per tick.
	if not disguise_active or not in_cone or delta <= 0.0:
		return
	_pending_viewcone_delta += delta
	_pending_viewcone_in_cone = true


func _is_in_guard_viewcone() -> bool:
	if not is_inside_tree():
		return false
	var w3d := get_world_3d()
	if w3d == null:
		return false
	var space: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var player_eye: Vector3 = global_position + Vector3.UP * 1.3
	for g: Node in get_tree().get_nodes_in_group("guards"):
		if not (g is Node3D):
			continue
		var st: Variant = g.get("state")
		if st is int and int(st) == 5:
			continue
		var gn: Node3D = g as Node3D
		var guard_eye: Vector3 = gn.global_position + Vector3.UP * 1.5
		var to_p: Vector3 = player_eye - guard_eye
		var dist: float = to_p.length()
		if dist > DISGUISE_GUARD_VIEWCONE_M or dist < 0.05:
			continue
		var g_fwd: Vector3 = -gn.global_transform.basis.z
		if g_fwd.length() < 0.05:
			continue
		var ang_deg: float = rad_to_deg(g_fwd.normalized().angle_to(to_p / dist))
		if ang_deg > DISGUISE_GUARD_VIEWCONE_DEG:
			continue
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(guard_eye, player_eye, 1, [get_rid()]))
		if hit.is_empty():
			return true
	return false


func take_damage(amount: float, source: String = "") -> void:
	if is_downed:
		return
	# Fall damage is exempt from DT_DisguiseV3IntegrityReduction.DamageTaken:
	# a bad jump must not silently strip the Chameleon's cover.
	if disguise_active and source != "fall":
		# DT_DisguiseV3IntegrityReduction.DamageTaken: EventType
		# AttributeDecrease on Health, IntegrityReduction.Value 40.0,
		# AttributeDeltaMultiplier 1.0 but MaxExtraReductionFromAttributeDelta
		# 0.0, so the health delta adds nothing. InstantCancel is false: damage
		# removes 40 integrity instead of zeroing the disguise outright.
		disguise_integrity = maxf(0.0, disguise_integrity - DISGUISE_DAMAGE_INTEGRITY_LOSS)
		if disguise_integrity <= 0.0:
			disguise_active = false
		disguise_changed.emit(disguise_integrity, disguise_active)
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_enter_downed()


func get_nearest_interactable() -> Node:
	var best: Node = null
	var best_d: float = INTERACT_RANGE
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		if not (node is Node3D):
			continue
		var node3d: Node3D = node as Node3D
		var d: float = global_position.distance_to(node3d.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func get_look_interact_prompt() -> String:
	var ko_guard: Node = _get_nearest_ko_guard()
	if ko_guard != null:
		return "[E] Steal Guard Disguise"
	var n: Node = get_nearest_interactable()
	if n == null:
		return ""
	if n.has_method("get_interact_prompt"):
		return str(n.call("get_interact_prompt"))
	var item_nm: Variant = n.get("item_name")
	if item_nm != null:
		return "[E] Steal %s" % str(item_nm)
	return "[E] Interact"


## KF24/KF25 stacked secondary prompt, shown beneath the primary centre
## prompt: [F] [HOLD] TAKEDOWN over a guard, [F] [HOLD] LOCK on a closed
## unlocked door. Empty when no hold action is available.
func get_look_secondary_prompt() -> String:
	if not can_act():
		return ""
	if _find_nearest_guard(2.4) != null:
		return "[F] [HOLD] TAKEDOWN"
	var n: Node = get_nearest_interactable()
	if n != null and n.has_method("get_interact_secondary_prompt"):
		return str(n.call("get_interact_secondary_prompt"))
	return ""


## Runs the stacked secondary action on F release after HOLD_INTERACT_SEC.
func _perform_hold_action() -> void:
	if not can_act():
		return
	var prompted_guard: Node3D = _find_nearest_guard(2.4)
	if prompted_guard != null:
		_try_blackjack(prompted_guard) # P1: strike the prompted guard, not group-order first.
		return
	var n: Node = get_nearest_interactable()
	if n != null and n.has_method("interact_hold"):
		n.call("interact_hold", self)
		interacted.emit(n)


func _get_nearest_ko_guard() -> Node:
	if GameState.thief_id != "chameleon":
		return null
	var best: Node = null
	var best_d: float = DISGUISE_STEAL_RANGE
	var fwd: Vector3 = Vector3.ZERO
	var has_fwd: bool = cam != null
	if has_fwd:
		fwd = -cam.global_transform.basis.z
	for g: Node in get_tree().get_nodes_in_group("guards"):
		if not (g is Node3D):
			continue
		var guard_node: Node3D = g as Node3D
		var guard_state: int = int(g.get("state"))
		if guard_state != 5:
			continue
		var d: float = global_position.distance_to(guard_node.global_position)
		if d > best_d:
			continue
		if has_fwd:
			var to_guard: Vector3 = (guard_node.global_position - global_position).normalized()
			var flat_fwd: Vector3 = Vector3(fwd.x, 0.0, fwd.z).normalized()
			var flat_to: Vector3 = Vector3(to_guard.x, 0.0, to_guard.z).normalized()
			if flat_fwd.length() > 0.1 and flat_to.length() > 0.1 and flat_fwd.dot(flat_to) < -0.2 and d > 1.2:
				continue
		best_d = d
		best = g
	return best


func _try_steal_disguise(guard: Node) -> bool:
	if guard == null:
		return false
	disguise_active = true
	disguise_integrity = 100.0
	disguise_ttl = DISGUISE_ACTIVE_TIME
	disguise_changed.emit(disguise_integrity, disguise_active)
	tool_used.emit("disguise", -1) # P1 tool_used gap (disguise steal path).
	NoiseBus.emit_noise(global_position, 3.0, self, "disguise")
	interacted.emit(guard)
	return true


func _try_interact() -> void:
	if not can_act():
		return
	var ko_guard: Node = _get_nearest_ko_guard()
	if ko_guard != null:
		_try_steal_disguise(ko_guard)
		return
	var best: Node = get_nearest_interactable()
	if best != null and best.has_method("interact"):
		best.interact(self)
		interacted.emit(best)


func _trigger_thief_ability() -> void:
	if not can_act():
		return
	if ability_cooldown > 0.0:
		return
	match GameState.thief_id:
		"spider":
			_try_spider_grapple()
		"chameleon":
			disguise_active = not disguise_active
			if disguise_active:
				disguise_ttl = DISGUISE_ACTIVE_TIME
				if disguise_integrity <= 1.0:
					disguise_integrity = 100.0
				_fp_play_action("disguise_apply")
			disguise_changed.emit(disguise_integrity, disguise_active)
			_last_disguise_emitted = disguise_integrity
			_last_disguise_active_emitted = disguise_active
			tool_used.emit("disguise", -1) # P1 tool_used gap: HUD/cooldown listeners keyed on tool_used missed the chameleon toggle.
			ability_cooldown = DISGUISE_COOLDOWN
		"moth":
			# P1 no-astral-cleanup: the moth branch set astral_active without
				# clearing grapple/mantle/climb/crank, so movement priority was
				# ambiguous and fall immunity stacked (UE moth astral owns
				# movement while active; winch/crank/climb must be down first).
			if is_grappling:
				is_grappling = false
			is_mantling = false
			is_wall_climbing = false
			_exit_wire_states()
			astral_active = true
			_note_air_link_start()
			astral_ttl = ASTRAL_DURATION
			ability_cooldown = 12.0
			tool_used.emit("astral", -1) # P1 tool_used gap.
			_sync_thief_vision()


func _tick_astral(delta: float) -> void:
	if not astral_active:
		return
	astral_ttl = maxf(0.0, astral_ttl - delta)
	if astral_ttl <= 0.0:
		_end_astral()


func _end_astral() -> void:
	# P2 inverted guard fixed: astral owns the timer; vision is synced, never
	# gating. Old `not active and not vision` form could reset vision state on
	# a path where astral was never on.
	if not astral_active:
		return
	astral_active = false
	astral_ttl = 0.0
	_sync_thief_vision()


func validate_zipwire_target() -> Dictionary:
	if cam == null or not is_inside_tree():
		return {"valid": false, "pos": Vector3.ZERO, "reason": "no_camera"}
	var w3d := get_world_3d()
	if w3d == null:
		return {"valid": false, "pos": Vector3.ZERO, "reason": "no_world"}
	var space: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var from: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_transform.basis.z
	var to: Vector3 = from + fwd * GRAPPLE_MAX_RANGE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {"valid": false, "pos": Vector3.ZERO, "reason": "no_hit"}
	var hit_pos: Vector3 = hit["position"] as Vector3
	var hit_normal: Vector3 = Vector3.UP
	var normal_var: Variant = hit.get("normal", Vector3.UP)
	if normal_var is Vector3:
		hit_normal = normal_var
	# Anchor surface check: reject point-blank hooks, walkable floor below the
	# thief, and downward anchors (the zipwire only winches up/forward).
	if hit_pos.distance_to(global_position) < GRAPPLE_MIN_RANGE:
		return {"valid": false, "pos": hit_pos, "reason": "too_close"}
	if hit_normal.dot(Vector3.UP) > 0.7 and hit_pos.y < global_position.y + 2.0:
		return {"valid": false, "pos": hit_pos, "reason": "floor"}
	if hit_pos.y < global_position.y - 0.5:
		return {"valid": false, "pos": hit_pos, "reason": "below"}
	return {"valid": true, "pos": hit_pos, "normal": hit_normal, "reason": "ok"}


func _try_spider_grapple() -> bool:
	if not can_act():
		return false
	if ability_cooldown > 0.0:
		return is_grappling
	if cam == null:
		return false
	if int(charges.get("grapple", 0)) <= 0:
		return false
	var check: Dictionary = validate_zipwire_target()
	if check.get("valid", false) != true:
		return false
	# A new launch supersedes any cable hang/crank and its cable.
	if is_wire_hanging or _is_cranking:
		_exit_wire_states()
	grapple_target = check["pos"] as Vector3
	is_grappling = true
	_wire_arrival_grace = 0.0
	_note_air_link_start()
	_wire_launch_arming = false
	_wire_launch_hold_sec = 0.0
	grapple_time = 0.0
	charges["grapple"] = int(charges.get("grapple", 0)) - 1
	tool_used.emit("grapple", int(charges.get("grapple", 0)))
	if equipped_tool != "zipwire":
		_fp_set_tool("zipwire")
	_fp_play_action("zipwire_cast")
	_fp_play_swing()
	ability_cooldown = GameData.eval_curve("CT_Tool_Wire", "WireCooldownSecondary", 1.0, 5.0)
	_update_zipwire_cable()
	NoiseBus.emit_noise(global_position, 5.0, self, "wire")
	return true


func _use_slithersap() -> void:
	if not can_act():
		return
	if int(charges.get("slithersap", 0)) <= 0:
		return
	_fp_set_tool("slithersap")
	_fp_play_action("slithersap_throw")
	_fp_play_swing()
	charges["slithersap"] = int(charges.get("slithersap", 0)) - 1
	# P1 sap instant-30 m: the throw anim no longer teleports the puddle to
	# the 30 m aim point on the same tick (UE cook stores no InitialSpeed, so
	# no speed is invented). Snapshot the aim now, arm after SAP_ARM_DELAY_SEC;
	# _on_sap_armed re-validates before spawning (stale-timer discipline).
	var aim: Vector3 = _slithersap_aim_point()
	_sap_seq += 1
	var seq: int = _sap_seq
	get_tree().create_timer(SAP_ARM_DELAY_SEC).timeout.connect(_on_sap_armed.bind(seq, aim))


## P1 sap arm delay: spawns the MagicSlime puddle (2.0 m radius, 30 s) at the
## throw-time aim snapshot; the puddle runs the 1.5 m / 30 s light inhibitor.
## Stale timers (level change, downed mid-arm, superseded throw) refund the
## charge instead of spawning into a dead scene (UE path: no InitialSpeed
## source; Godot-side SAP_ARM_DELAY_SEC pacing only).
func _on_sap_armed(seq: int, aim: Vector3) -> void:
	if seq != _sap_seq or not is_inside_tree() or GameState.state != "playing" or not can_act():
		charges["slithersap"] = int(charges.get("slithersap", 0)) + 1
		push_warning("[thief] sap arm timer went stale (seq/state/down); charge refunded (UE MagicSlime throw path, no speed source)")
		return
	var host: Node = get_parent()
	if host == null:
		host = self
	var puddle: Area3D = SlipPuddleScript.new()
	host.add_child(puddle)
	puddle.call("setup", aim, light_probe, GameState.elapsed_sec)
	VfxManager.spawn_sap_burst(host, aim + Vector3.UP * 0.2)
	NoiseBus.emit_noise(aim, 4.0, self, "slithersap")
	tool_used.emit("slithersap", int(charges.get("slithersap", 0)))
## Aim raycast for the Slithersap puddle. Falls back to flat ground ahead.
func _slithersap_aim_point() -> Vector3:
	var fallback: Vector3 = global_position + (-global_transform.basis.z) * 2.5
	fallback.y = global_position.y
	if cam == null:
		return fallback
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = cam.global_position
	var to: Vector3 = from + (-cam.global_transform.basis.z) * SLITHERSAP_AIM_DISTANCE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return fallback
	return hit["position"] as Vector3


func _use_smoke_bomb() -> void:
	if not can_act():
		return
	if int(charges.get("smoke_bomb", 0)) <= 0:
		return
	_fp_set_tool("smoke_bomb")
	_fp_play_action("smoke_throw")
	_fp_play_swing()
	# P1 smoke charge-before-spawn: the charge used to decrement before the
	# spawn path was known, so a missing camera AND missing level spawner ate
	# the charge with no cloud (UE BP_SmokeBomb_Bomb_Tool throw path). Decrement
	# only after a spawn path commits; otherwise fail loudly and keep it.
	var smoke_spawned: bool = false
	if cam != null and get_parent() != null:
		var fwd: Vector3 = -cam.global_transform.basis.z
		var right: Vector3 = cam.global_transform.basis.x
		var up: Vector3 = cam.global_transform.basis.y
		var origin: Vector3 = cam.global_position + fwd * 0.5 + right * 0.14 - up * 0.05
		SmokeProjectileScript.throw_from(get_parent(), origin, fwd, self, level_ctrl)
		smoke_spawned = true
	elif level_ctrl != null and level_ctrl.has_method("spawn_smoke"):
		var ground: Vector3 = global_position + (-global_transform.basis.z) * 2.5
		level_ctrl.spawn_smoke(ground, 25.0)
		smoke_spawned = true
	if not smoke_spawned:
		push_error("[thief] smoke throw had no camera and no level smoke spawner; charge kept (UE BP_SmokeBomb_Bomb_Tool path)")
		assert(false, "smoke spawn has no valid path")
		return
	charges["smoke_bomb"] = int(charges.get("smoke_bomb", 0)) - 1
	NoiseBus.emit_noise(global_position, 7.0, self, "smoke")
	tool_used.emit("smoke_bomb", int(charges.get("smoke_bomb", 0)))


## Throws a distraction bottle (secondary_action) when a bottle charge is
## held. Speed/noise are documented approximations (see thrown_bottle.gd);
## charges decrement and the HUD bottle count follows the charges dict.
func _throw_bottle() -> void:
	if not can_act():
		return
	if int(charges.get("bottle", 0)) <= 0:
		return
	if cam == null:
		return
	_fp_play_swing()
	charges["bottle"] = int(charges.get("bottle", 0)) - 1
	var fwd: Vector3 = -cam.global_transform.basis.z
	var origin: Vector3 = cam.global_position + fwd * 0.6
	var host: Node = get_parent()
	if host == null:
		host = self
	ThrownBottleScript.throw_from(host, origin, fwd, self)
	tool_used.emit("bottle", int(charges.get("bottle", 0)))


## Nearest guard inside the real 25 m / 9 deg cone. Returns null when empty.
func pickpocket_select_target(candidates: Array, from_pos: Vector3, fwd: Vector3) -> Node:
	var flat_fwd: Vector3 = Vector3(fwd.x, 0.0, fwd.z)
	if flat_fwd.length() < 0.1:
		return null
	flat_fwd = flat_fwd.normalized()
	var best: Node = null
	var best_d: float = PICKPOCKET_RANGE
	for c: Variant in candidates:
		if not (c is Node3D):
			continue
		var n3d: Node3D = c as Node3D
		var to: Vector3 = n3d.global_position - from_pos
		var d: float = to.length()
		if d > PICKPOCKET_RANGE or d < 0.1:
			continue
		var flat_to: Vector3 = Vector3(to.x, 0.0, to.z)
		if flat_to.length() < 0.05:
			continue
		if rad_to_deg(flat_fwd.angle_to(flat_to.normalized())) > PICKPOCKET_CONE_DEG:
			continue
		if d < best_d:
			best_d = d
			best = c
	return best


## True when the mark is facing the player within MaximumFacingAngleToBlock
## (30 deg): the attempt fails.
func pickpocket_is_blocked(guard: Node3D, player_pos: Vector3) -> bool:
	if guard == null:
		return true
	var to_player: Vector3 = player_pos - guard.global_position
	to_player.y = 0.0
	if to_player.length() < 0.05:
		return false
	var gf: Vector3 = -guard.global_transform.basis.z
	gf.y = 0.0
	if gf.length() < 0.05:
		return false
	return rad_to_deg(gf.normalized().angle_to(to_player.normalized())) <= FAIRY_BLOCK_ANGLE_DEG


## Fairy flight time for a steal run (m/s, capped at FairyLifeDuration).
func fairy_travel_time(dist: float) -> float:
	return minf(maxf(dist, 0.0) / FAIRY_SPEED, FAIRY_LIFE)


func _use_pickpocket_fairy() -> void:
	if not can_act():
		return
	if pickpocket_cooldown > 0.0:
		return
	pickpocket_cooldown = PICKPOCKET_COOLDOWN
	_fp_set_tool("fairy")
	_fp_play_action("fairy_deploy")
	_fp_play_swing()
	# No ammo field on BP_Pickpocket_Tool: the charge display is infinite and
	# nothing is consumed.
	charges["pickpocket_fairy"] = PICKPOCKET_INFINITE_DISPLAY
	var fwd: Vector3 = -global_transform.basis.z
	if cam != null:
		fwd = -cam.global_transform.basis.z
	var target: Node = pickpocket_select_target(get_tree().get_nodes_in_group("guards"), global_position, fwd)
	if target == null or not (target is Node3D):
		tool_used.emit("pickpocket_fairy", PICKPOCKET_INFINITE_DISPLAY)
		return
	var mark: Node3D = target as Node3D
	if pickpocket_is_blocked(mark, global_position):
		# P2 dynamic fail radius fixed: was distance_to+2.0 (farther = louder).
		NoiseBus.emit_noise(mark.global_position, FAIRY_FAIL_RADIUS_M, self, "pickpocket_spotted")
		tool_used.emit("pickpocket_fairy", PICKPOCKET_INFINITE_DISPLAY)
		return
	var throw_pos: Vector3 = global_position # P1 fairy recheck: arrival re-tested with the moved player pos, so walking into view mid-flight converted success into spotted. Snapshot throw-time geometry.
	_fairy_seq += 1
	var seq: int = _fairy_seq
	var dist: float = global_position.distance_to(mark.global_position)
	var travel: float = fairy_travel_time(dist)
	VfxManager.spawn_fairy_orb(get_parent(), global_position + Vector3.UP * 1.3, mark.global_position + Vector3.UP * 1.2, travel)
	NoiseBus.emit_noise(mark.global_position, 3.0, self, "fairy")
	get_tree().create_timer(travel).timeout.connect(_on_fairy_arrived.bind(mark, throw_pos, seq))
	tool_used.emit("pickpocket_fairy", PICKPOCKET_INFINITE_DISPLAY)


## The fairy steals the nearest uncollected loot around the mark on arrival.
## P1 SceneTree-cancel: stale timers (level change, downed mid-flight,
## superseded cast) return silently via the seq guard. P1 recheck: the
## block test replays throw-time player geometry (UE BP_Pickpocket_Tool
## MaximumFacingAngleToBlock), not the moved position.
func _on_fairy_arrived(mark: Node, throw_pos: Vector3, seq: int) -> void:
	if seq != _fairy_seq or not is_inside_tree() or GameState.state != "playing" or not can_act():
		return
	if not is_instance_valid(mark) or not (mark is Node3D):
		push_warning("[thief] fairy arrived at a freed mark; steal skipped (UE BP_PickpocketFairy_FollowActor path)")
		return
	var mark_pos: Vector3 = (mark as Node3D).global_position
	if pickpocket_is_blocked(mark as Node3D, throw_pos):
		NoiseBus.emit_noise(mark_pos, 6.0, self, "pickpocket_spotted")
		return
	var best: Node3D = null
	var best_d: float = FAIRY_STEAL_RADIUS
	for n: Node in get_tree().get_nodes_in_group("loot"):
		if n is Node3D and not n.get_meta("collected", false):
			var loot_node: Node3D = n as Node3D
			var d: float = mark_pos.distance_to(loot_node.global_position)
			if d < best_d:
				best_d = d
				best = loot_node
	if best != null and best.has_method("interact"):
		best.interact(self)


func _find_nearest_guard(max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d: float = max_dist
	for g: Node in get_tree().get_nodes_in_group("guards"):
		if not (g is Node3D):
			continue
		var st: Variant = g.get("state")
		if st is int and int(st) == 5:
			continue
		var guard_node: Node3D = g as Node3D
		var d: float = global_position.distance_to(guard_node.global_position)
		if d < best_d:
			best_d = d
			best = guard_node
	return best


func _try_blackjack(preferred: Node3D = null) -> void:
	# P1 prompt/target mismatch: the hold action prompts off _find_nearest_guard
	# but the old loop struck group-order first, so the struck guard could differ
	# from the prompted one. The prompted guard leads; the loop is the fallback.
	if not can_act():
		return
	_fp_set_tool("blackjack")
	_fp_play_action("blackjack_swing")
	_fp_play_swing()
	tool_used.emit("blackjack", -1) # P1 tool_used gap.
	if head != null and cam != null:
		var swing_dir: Vector3 = -cam.global_transform.basis.z
		var swing_pos: Vector3 = head.global_position + swing_dir * 0.7
		VfxManager.spawn_blackjack_swing(get_parent(), swing_pos, swing_dir)
	_play_blackjack_camera_punch()
	_tp_takedown_atk_start()
	var base_dmg: float = GameData.eval_curve("CT_Tool_Blackjack", "BlackjackDamageLight", 1.0, BLACKJACK_LIGHT_DMG)
	var heavy_dmg: float = GameData.eval_curve("CT_Tool_Blackjack", "BlackjackDamageHeavy", 1.0, BLACKJACK_HEAVY_DMG)
	if heavy_dmg <= 0.0:
		heavy_dmg = base_dmg
	for g: Node in _blackjack_candidates(preferred):
		if not (g is Node3D):
			continue
		var guard_node: Node3D = g as Node3D
		if global_position.distance_to(guard_node.global_position) > 2.4:
			continue
		if not g.has_method("take_knockout"):
			continue
		var guard_state: int = int(g.get("state"))
		if guard_state == 5: # Alertness.KNOCKED_OUT: already down, not a target
			continue
		var final_dmg: float = base_dmg
		if guard_state == 0 or guard_state == 1:
			var to_player: Vector3 = (global_position - guard_node.global_position).normalized()
			var guard_back: Vector3 = guard_node.global_transform.basis.z.normalized()
			var behind_dot: float = guard_back.dot(to_player)
			if behind_dot > 0.25:
				final_dmg = heavy_dmg
		g.take_knockout(final_dmg)
		if int(g.get("state")) == 5: # count/noise only on transitions into KO
			GameState.takedowns += 1
			NoiseBus.emit_noise(global_position, 4.5, self, "takedown")
		return


## P1 prompt/target mismatch: prompted (nearest) guard first, group order after.
func _blackjack_candidates(preferred: Node3D) -> Array[Node]:
	var candidates: Array[Node] = []
	if preferred != null and is_instance_valid(preferred):
		candidates.append(preferred)
	for g: Node in get_tree().get_nodes_in_group("guards"):
		if g != (preferred as Node):
			candidates.append(g)
	return candidates


func _play_blackjack_camera_punch() -> void:
	if cam == null:
		return
	if _bj_punch_tween != null and _bj_punch_tween.is_valid():
		_bj_punch_tween.kill()
	var base_pitch: float = cam.rotation.x
	var base_roll: float = cam.rotation.z
	_bj_punch_tween = create_tween()
	_bj_punch_tween.tween_property(cam, "rotation:x", base_pitch + deg_to_rad(-4.0), 0.08)
	_bj_punch_tween.parallel().tween_property(cam, "rotation:z", base_roll + deg_to_rad(2.0), 0.08)
	_bj_punch_tween.tween_property(cam, "rotation:x", base_pitch, 0.14)
	_bj_punch_tween.parallel().tween_property(cam, "rotation:z", base_roll, 0.14)


## Takedown attacker handoff (thief 3P form): plays the BlackJack stealth
## montage vs GuardEnforcer on the firing thief rig (mesh_root 3P skeleton),
## synced with the guard victim montage (guard_ai play_takedown_vic).
## Camera punch + takedown counter + noise are kept by the caller; this is
## the animation half only. No-op (loud UE-path warning, never a crash) when
## the 3P body failed to load, the manifest lacks the clip, or the skeletons
## share no bones -- the instant-KO + punch path still applies.
func _tp_takedown_atk_start() -> void:
	_tp_takedown_stop() # P2: kill a stale attacker montage before replaying so swings never layer.
	var skel := _tp_crank_body_skel()
	if skel == null:
		return
	var host := skel.get_parent() as Node
	if host == null:
		return
	var player := host.get_node_or_null("TPTakedownPlayer") as AnimationPlayer
	if player == null:
		player = AnimationPlayer.new()
		player.name = "TPTakedownPlayer"
		host.add_child(player)
		player.root_node = player.get_path_to(host)
	var clip_name := ""
	if player.has_animation("AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage"):
		clip_name = "AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage"
	else:
		var lib = ThiefAnimLib.new()
		if not lib.setup("club", skel):
			push_warning("BlackjackTakedown3P: no 3P takedown player, skeleton bind failed (UE clip TAT/Content/Art/Animation/Thief/Anim/Gear/BlackJack/AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage)")
			return
		clip_name = str(lib.ensure_tp_takedown_atk_clip(player))
	if clip_name == "" or not player.has_animation(clip_name):
		push_warning("BlackjackTakedown3P: takedown Atk clip no-op on 3P rig, manifest lacks clip or zero shared bones (UE clip TAT/Content/Art/Animation/Thief/Anim/Gear/BlackJack/AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage)")
		return
	player.play(clip_name, FP_ANIM_BLEND)


func _process(delta: float) -> void:
	_update_first_person(delta)
	# P2 smoke preview: 32-ray ballistic sweep throttled to 10 Hz (was every
	# rendered frame; same PROP_SCAN_INTERVAL discipline as prop highlight).
	_smoke_preview_accum += delta
	if _smoke_preview_accum >= PROP_SCAN_INTERVAL:
		_smoke_preview_accum = 0.0
		_update_smoke_trajectory()


func _build_first_person_rig() -> void:
	if cam == null:
		return
	if fp_rig != null and is_instance_valid(fp_rig):
		return
	fp_tool_id = equipped_tool
	fp_rig = Node3D.new()
	fp_rig.name = "FirstPersonRig"
	cam.add_child(fp_rig)
	fp_rig.position = Vector3.ZERO
	fp_base_rig_pos = fp_rig.position
	if _try_build_real_fp_arms():
		_fp_use_real_arms = true
	else:
		_fp_use_real_arms = false
		_build_procedural_fp_hands()
	fp_tool_root = Node3D.new()
	fp_tool_root.name = "ToolRoot"
	fp_tool_root.position = Vector3(0.28, -0.18, -0.62)
	if _fp_use_real_arms:
		_attach_fp_tool_to_hand()
	if fp_tool_root.get_parent() == null:
		fp_rig.add_child(fp_tool_root)
	_fp_set_tool(fp_tool_id)
	if _fp_use_real_arms:
		_update_fp_anim_state()


func _get_fp_mat_loader() -> Node:
	if _fp_mat_loader == null or not is_instance_valid(_fp_mat_loader):
		_fp_mat_loader = LevelLoaderScript.new()
		_fp_mat_loader.name = "FPMaterialLoader"
		add_child(_fp_mat_loader)
	return _fp_mat_loader


func _bind_ue_mesh_materials(root_node: Node, ue_mesh_path: String) -> void:
	if root_node == null or ue_mesh_path == "":
		return
	var loader: Node = _get_fp_mat_loader()
	if loader == null:
		return
	var db: Variant = loader.get("_mesh_mats_db")
	var slots_v: Variant = (db as Dictionary).get(ue_mesh_path, null) if db is Dictionary else null
	if not (slots_v is Array):
		var db_low: Variant = loader.get("_mesh_mats_db_lower")
		if db_low is Dictionary:
			slots_v = (db_low as Dictionary).get(ue_mesh_path.to_lower(), null)
	if not (slots_v is Array):
		return
	var slots: Array = slots_v as Array
	for child: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var count: int = mini(mi.mesh.get_surface_count(), slots.size())
		for s: int in range(count):
			var mat_path: String = str(slots[s])
			if mat_path == "":
				continue
			var mat: Material = loader.call("get_material_for_ue", mat_path) as Material
			if mat != null:
				mi.set_surface_override_material(s, mat)


func _set_cast_shadow_recursive(root_node: Node, mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	if root_node is GeometryInstance3D:
		(root_node as GeometryInstance3D).cast_shadow = mode
	for child: Node in root_node.get_children():
		_set_cast_shadow_recursive(child, mode)


static func _ensure_vm_shaders() -> void:
	if _vm_opaque_shader == null:
		_vm_opaque_shader = Shader.new()
		_vm_opaque_shader.code = """shader_type spatial;
render_mode depth_draw_opaque, specular_schlick_ggx;

uniform float vm_fov_deg = 85.0;
uniform float vm_scale = 0.5;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear, repeat_enable;
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float roughness_val = 0.78;
uniform float metallic_val = 0.0;
uniform float specular_val = 0.5;
uniform float uv_scale = 1.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform bool use_albedo_tex = false;
uniform bool use_normal_tex = false;
uniform bool use_orm_tex = false;
uniform bool use_emission_tex = false;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// UE's first-person view-space scale: halving xyz leaves screen placement
	// unchanged while pulling the VM into the near half of the depth range.
	// The old z-only 0.996..0.78 remap is gone.
	view_pos.xyz *= vm_scale;
	float cur_fy = abs(PROJECTION_MATRIX[1][1]);
	float vm_fy = 1.0 / tan(radians(vm_fov_deg) * 0.5);
	float fov_scale = vm_fy / max(cur_fy, 0.0001);
	mat4 vm_proj = PROJECTION_MATRIX;
	vm_proj[0][0] *= fov_scale;
	vm_proj[1][1] *= fov_scale;
	POSITION = vm_proj * view_pos;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 alb = use_albedo_tex ? texture(albedo_tex, uv) : vec4(1.0);
	ALBEDO = alb.rgb * albedo_tint.rgb;
	if (use_orm_tex) {
		vec3 orm = texture(orm_tex, uv).rgb;
		AO = orm.r;
		ROUGHNESS = clamp(orm.g * roughness_val, 0.04, 1.0);
		METALLIC = clamp(orm.b * metallic_val, 0.0, 1.0);
	} else {
		ROUGHNESS = clamp(roughness_val, 0.04, 1.0);
		METALLIC = clamp(metallic_val, 0.0, 1.0);
	}
	SPECULAR = specular_val;
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
	}
	if (use_emission_tex) {
		// max(emission_energy, 1.0) defeated the 0.65 VM cap and ignore
		// EmissiveTint; the authored energy and colour must both apply.
		EMISSION = texture(emission_tex, uv).rgb * emission_color * emission_energy;
	} else if (emission_energy > 0.001) {
		EMISSION = emission_color * emission_energy;
	}
}
"""
	if _vm_opaque_cull_disabled_shader == null:
		_vm_opaque_cull_disabled_shader = Shader.new()
		_vm_opaque_cull_disabled_shader.code = _vm_opaque_shader.code.replace(
			"render_mode depth_draw_opaque, specular_schlick_ggx;",
			"render_mode depth_draw_opaque, cull_disabled, specular_schlick_ggx;"
		)
	if _vm_glass_shader == null:
		_vm_glass_shader = Shader.new()
		_vm_glass_shader.code = """shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform float vm_fov_deg = 85.0;
uniform float vm_scale = 0.5;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear, repeat_enable;
uniform sampler2D opacity_tex : hint_default_white, filter_linear, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float opacity_scale = 1.0;
uniform float roughness_val = 0.2;
uniform float metallic_val = 0.0;
uniform float specular_val = 0.5;
uniform float uv_scale = 1.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform vec3 fresnel_color : source_color = vec3(0.0);
uniform float fresnel_power = 3.0;
uniform float fresnel_strength = 0.0;
uniform bool use_albedo_tex = false;
uniform bool use_opacity_tex = false;
uniform bool use_normal_tex = false;
uniform bool use_orm_tex = false;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Same UE view-space first-person scale as the opaque VM shader.
	view_pos.xyz *= vm_scale;
	float cur_fy = abs(PROJECTION_MATRIX[1][1]);
	float vm_fy = 1.0 / tan(radians(vm_fov_deg) * 0.5);
	float fov_scale = vm_fy / max(cur_fy, 0.0001);
	mat4 vm_proj = PROJECTION_MATRIX;
	vm_proj[0][0] *= fov_scale;
	vm_proj[1][1] *= fov_scale;
	POSITION = vm_proj * view_pos;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 alb = use_albedo_tex ? texture(albedo_tex, uv) : vec4(1.0);
	ALBEDO = alb.rgb * albedo_tint.rgb;
	float op_sample = use_opacity_tex ? texture(opacity_tex, uv).r : (use_albedo_tex ? alb.a : 1.0);
	ALPHA = clamp(op_sample * albedo_tint.a * opacity_scale, 0.0, 1.0);
	if (use_orm_tex) {
		vec3 orm = texture(orm_tex, uv).rgb;
		AO = orm.r;
		ROUGHNESS = clamp(orm.g * roughness_val, 0.04, 1.0);
		METALLIC = clamp(orm.b * metallic_val, 0.0, 1.0);
	} else {
		ROUGHNESS = clamp(roughness_val, 0.04, 1.0);
		METALLIC = clamp(metallic_val, 0.0, 1.0);
	}
	SPECULAR = specular_val;
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
	}
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	EMISSION = emission_color * emission_energy + fresnel_color * fresnel_strength * fres;
}
"""


func _wrap_material_for_vm(src_mat: Material) -> ShaderMaterial:
	const VM_EMISSION_CAP := 0.65
	_ensure_vm_shaders()
	var smat := ShaderMaterial.new()
	if src_mat is ShaderMaterial:
		var src_sh := src_mat as ShaderMaterial
		smat.shader = _vm_glass_shader
		smat.set_shader_parameter("vm_fov_deg", FP_VM_FOV_DEG)
		smat.set_shader_parameter("vm_scale", FP_VM_SCALE)
		for p_name: String in [
			"albedo_tex", "opacity_tex", "normal_tex", "orm_tex",
			"albedo_tint", "opacity_scale", "roughness_val", "metallic_val",
			"specular_val", "uv_scale", "emission_color", "emission_energy",
			"use_albedo_tex", "use_opacity_tex", "use_normal_tex", "use_orm_tex"
		]:
			var val: Variant = src_sh.get_shader_parameter(p_name)
			if val != null:
				smat.set_shader_parameter(p_name, val)
		return smat
	var std := src_mat as StandardMaterial3D
	if std == null:
		smat.shader = _vm_opaque_shader
		smat.set_shader_parameter("vm_fov_deg", FP_VM_FOV_DEG)
		smat.set_shader_parameter("vm_scale", FP_VM_SCALE)
		return smat
	var is_trans: bool = std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	if is_trans:
		smat.shader = _vm_glass_shader
		smat.set_shader_parameter("opacity_scale", 1.0)
		smat.set_shader_parameter("use_opacity_tex", false)
	else:
		smat.shader = _vm_opaque_cull_disabled_shader if std.cull_mode == BaseMaterial3D.CULL_DISABLED else _vm_opaque_shader
	smat.set_shader_parameter("vm_fov_deg", FP_VM_FOV_DEG)
	smat.set_shader_parameter("vm_scale", FP_VM_SCALE)
	smat.set_shader_parameter("albedo_tint", std.albedo_color)
	smat.set_shader_parameter("roughness_val", std.roughness)
	var metal_v: float = 1.0 if (std.metallic_texture != null and std.metallic <= 0.001) else std.metallic
	smat.set_shader_parameter("metallic_val", metal_v)
	smat.set_shader_parameter("specular_val", std.metallic_specular)
	smat.set_shader_parameter("uv_scale", std.uv1_scale.x)
	smat.set_shader_parameter("use_albedo_tex", std.albedo_texture != null)
	if std.albedo_texture != null:
		smat.set_shader_parameter("albedo_tex", std.albedo_texture)
	smat.set_shader_parameter("use_normal_tex", std.normal_enabled and std.normal_texture != null)
	if std.normal_enabled and std.normal_texture != null:
		smat.set_shader_parameter("normal_tex", std.normal_texture)
	var has_orm: bool = std.roughness_texture != null
	smat.set_shader_parameter("use_orm_tex", has_orm)
	if has_orm:
		smat.set_shader_parameter("orm_tex", std.roughness_texture)
	if std.emission_enabled:
		var vm_e: float = minf(std.emission_energy_multiplier, VM_EMISSION_CAP)
		assert(vm_e <= VM_EMISSION_CAP + 0.001, "TongCap: viewmodel emission exceeds cap")
		print("TongCap: viewmodel emission_energy=", vm_e, " cap=", VM_EMISSION_CAP, " (loader PBR tongs/3P clamped to mission glow 0.65)")
		smat.set_shader_parameter("emission_color", Vector3(std.emission.r, std.emission.g, std.emission.b))
		smat.set_shader_parameter("emission_energy", vm_e)
		if not is_trans:
			smat.set_shader_parameter("use_emission_tex", std.emission_texture != null)
			if std.emission_texture != null:
				smat.set_shader_parameter("emission_tex", std.emission_texture)
	if std.has_meta("fresnel_strength"):
		var fc: Color = std.get_meta("fresnel_color", Color(0.75, 0.92, 1.0)) as Color
		smat.set_shader_parameter("fresnel_color", Vector3(fc.r, fc.g, fc.b))
		smat.set_shader_parameter("fresnel_power", float(std.get_meta("fresnel_power", 2.5)))
		smat.set_shader_parameter("fresnel_strength", float(std.get_meta("fresnel_strength", 0.0)))
	return smat


func _apply_viewmodel_isolation(root_node: Node) -> void:
	if root_node == null:
		return
	for child: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s: int in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var vm_mat: ShaderMaterial = _wrap_material_for_vm(mat)
			mi.set_surface_override_material(s, vm_mat)


## Real 1P viewmodel (BP_Player_Thief_Spider.Mesh1P_UpperBody):
## SK_ThiefNisha__BodyUpper attached under the camera with retargeted 1P clips.
## SK_ThiefNisha__BodyUpper faces +Z in glTF Y-up (like 3P meshes), so it is
## rotated 180 deg around Y and shifted down by the authored 1P eye height
## (instead of inverting camera_position's +90 deg X root basis, which pitched
## the torso onto its back). Identity scale is kept (mesh bounds already in
## meters).
func _try_build_real_fp_arms() -> bool:
	_fp_arm_skel = null
	_fp_arm_holder = null
	fp_anim_player = null
	_fp_anim_lib = null
	_fp_tool_on_bone = false
	if not ResourceLoader.exists(THIEF_1P_UPPER_GLB):
		return false
	var packed: PackedScene = ResourceLoader.load(THIEF_1P_UPPER_GLB) as PackedScene
	if packed == null:
		return false
	var holder := Node3D.new()
	holder.name = "RealArms"
	fp_rig.add_child(holder)
	var inst: Node = packed.instantiate()
	inst.name = "BodyUpper1P"
	holder.add_child(inst)
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		holder.queue_free()
		return false
	var sk := skels[0] as Skeleton3D
	if sk == null or sk.get_bone_count() == 0:
		holder.queue_free()
		return false
	var cam_bone: int = -1
	for bone_name in FP_CAM_BONES:
		cam_bone = sk.find_bone(bone_name)
		if cam_bone >= 0:
			break
	if cam_bone < 0:
		holder.queue_free()
		return false
	var inst3d := inst as Node3D
	if inst3d == null:
		holder.queue_free()
		return false
	# 1P camera anchor: the authored UE eye height, not the GLB
	# camera_position rest (1.61 m). Spider BaseEyeHeight 77.875 cm over the
	# 89 cm capsule half-height = 1.66875 m, so arms/tool sit ~6 cm lower to
	# match the authored framing (KU/KF16/KF17/KF24). Mesh scale stays 1.0.
	var cam_origin := Vector3(0.0, STAND_HEAD_HEIGHT, 0.0)
	inst3d.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	inst3d.position = Vector3(cam_origin.x, -cam_origin.y, cam_origin.z)
	_bind_ue_mesh_materials(inst3d, "/Game/Art/Animation/ThiefNisha/Skin/Base/SK_ThiefNisha__BodyUpper")
	_set_cast_shadow_recursive(inst3d, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_apply_viewmodel_isolation(inst3d)
	_fp_arm_holder = holder
	_fp_arm_skel = sk
	if not _setup_fp_anims():
		holder.queue_free()
		_fp_arm_skel = null
		_fp_arm_holder = null
		return false
	return true


## Retargets the 1P clips onto the 1P arm skeleton. Any failure
## (manifest, GLB, zero shared bones) returns false for the fallback path.
func _setup_fp_anims() -> bool:
	fp_anim_player = null
	_fp_anim_lib = null
	if _fp_arm_skel == null or _fp_arm_holder == null:
		return false
	var lib = ThiefAnimLib.new()
	if not lib.setup("club", _fp_arm_skel):
		return false
	var skel_parent := _fp_arm_skel.get_parent() as Node
	if skel_parent == null:
		return false
	var player := lib.build_fp_player(_fp_arm_skel, skel_parent, _fp_arm_holder)
	if player == null or lib.applied_clip_count() < 3:
		return false
	_fp_anim_lib = lib
	fp_anim_player = player
	_fp_current_clip = ""
	return true


## Attaches fp_tool_root to the 1P right-hand bone via BoneAttachment3D
## (weapon_r_1p first, then hand fallbacks). Without a matching bone the
## tool root stays parentless and the caller keeps the camera-relative
## fallback.
func _attach_fp_tool_to_hand() -> void:
	_fp_tool_on_bone = false
	if _fp_arm_skel == null or not is_instance_valid(_fp_arm_skel):
		return
	var bone_idx: int = -1
	for bone_name in FP_TOOL_BONES:
		bone_idx = _fp_arm_skel.find_bone(bone_name)
		if bone_idx >= 0:
			break
	if bone_idx < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "ToolBoneAttachment"
	_fp_arm_skel.add_child(attach)
	attach.bone_idx = bone_idx
	attach.add_child(fp_tool_root)
	fp_tool_root.position = Vector3.ZERO
	fp_tool_root.rotation = Vector3.ZERO
	_fp_tool_on_bone = true


func _fp_play_action(role: String) -> void:
	if not _fp_use_real_arms or fp_anim_player == null or _fp_anim_lib == null:
		return
	var clip_name: String = str(_fp_anim_lib.call("ensure_fp_clip", fp_anim_player, role))
	if clip_name == "" or not fp_anim_player.has_animation(clip_name):
		return
	var dur: float = fp_anim_player.get_animation(clip_name).length
	_fp_action_ttl = maxf(dur, 0.25)
	_fp_current_clip = clip_name
	fp_anim_player.play(clip_name, 0.08)


func _select_fp_anim_role(moving: bool) -> String:
	if is_mantling:
		return _mantle_clip_role
	if is_wall_climbing:
		return "climb_wall"
	if is_grappling or is_wire_hanging:
		# KF17: keep the launcher/hands in frame through the winch and cable
		# hang. The AN_Zipwire_Travel_1P retarget dropped the 1P tool below the
		# camera (muzzle y ~= -0.34), so it is never selected here; CastIdle is
		# proven in-frame from the KF16/KF17 launch capture. Crank wins while
		# the hands are on the handle.
		return "zipwire_crank" if _is_cranking else "zipwire_cast_idle"
	if _is_cranking:
		return "zipwire_crank"
	if _fp_airborne:
		return "jump_inair"
	if disguise_active:
		if moving:
			if is_crouching:
				return "disguise_crouch"
			if is_sprinting:
				return "disguise_sprint"
			return "disguise_walk"
		if is_crouching:
			return "disguise_crouch_idle"
		return "disguise_idle"
	# Zipwire cast/aim/anchored pose: the 0.2 s LMB launch hold and a live
	# zipwire action clip keep the authored CastIdle. The is_grappling branch
	# above selects the same in-frame pose for the winch itself; a relaxed
	# standing idle falls through to StandIdle below.
	if fp_tool_id == "zipwire" and not is_crouching \
			and (_wire_launch_arming or _fp_action_ttl > 0.0):
		return "zipwire_cast_idle"
	match fp_tool_id:
		"zipwire":
			if moving:
				if is_crouching:
					return "crouch"
				if is_sprinting:
					return "zipwire_sprint"
				return "zipwire_walk"
			return "zipwire_crouch_idle" if is_crouching else "zipwire_idle"
		"blackjack":
			if moving:
				if is_crouching:
					return "crouch"
				if is_sprinting:
					return "sprint"
				return "blackjack_walk"
			return "blackjack_crouch_idle" if is_crouching else "blackjack_idle"
		"smoke_bomb":
			if moving:
				if is_crouching:
					return "crouch"
				if is_sprinting:
					return "sprint"
				return "smoke_walk"
			return "smoke_crouch_idle" if is_crouching else "smoke_idle"
		"slithersap":
			if moving:
				return "crouch" if is_crouching else ("sprint" if is_sprinting else "walk")
			return "slithersap_crouch_idle" if is_crouching else "slithersap_idle"
		"fairy":
			if moving:
				return "crouch" if is_crouching else ("sprint" if is_sprinting else "walk")
			return "fairy_crouch_idle" if is_crouching else "fairy_idle"
		"vistara_diamond":
			if moving:
				return "crouch" if is_crouching else ("sprint" if is_sprinting else "walk")
			return "vistara_crouch_idle" if is_crouching else "vistara_idle"
		_:
			if moving:
				return "crouch" if is_crouching else ("sprint" if is_sprinting else "walk")
			return "unarmed_idle"


## Drives the real 1P clip state machine using verified tool idle/loco/crank/
## disguise clips (respecting R3 L6: no fabricated unarmed 1P jump/idle clips).
func _update_fp_anim_state() -> void:
	if not _fp_use_real_arms or fp_anim_player == null or _fp_anim_lib == null:
		return
	if _fp_action_ttl > 0.0 and fp_anim_player.is_playing():
		return
	var planar: float = Vector2(velocity.x, velocity.z).length()
	var moving: bool = is_on_floor() and planar > 0.5
	var role: String = _select_fp_anim_role(moving)
	var clip_name: String = str(_fp_anim_lib.call("ensure_fp_clip", fp_anim_player, role))
	if clip_name == "" and moving:
		# P2 anim fallback asymmetry: the crank path warns loudly on missing
		# clips; the locomotion fallback was silent. Warn the same way.
		push_warning("[thief] FP role clip missing, falling back to locomotion clip (UE clip manifest path)")
		var fallback_role: String = "crouch" if is_crouching else ("sprint" if is_sprinting else "walk")
		clip_name = str(_fp_anim_lib.clip_for_role(fallback_role))
	if clip_name != "":
		_fp_play_fp_clip(clip_name)


func _fp_play_fp_clip(clip_name: String) -> void:
	if fp_anim_player == null or clip_name == "":
		return
	if _fp_current_clip == clip_name and fp_anim_player.is_playing():
		return
	if not fp_anim_player.has_animation(clip_name):
		return
	_fp_current_clip = clip_name
	fp_anim_player.play(clip_name, FP_ANIM_BLEND)


## Builds the separate gear (SK_Zipwire tool) AnimationPlayer. The UE zipwire
## reload is a montage pair: the character clip drives the 1P/3P arm skeleton,
## and AN_ThiefNisha_Zipwire__Gear_Zipwire_Reload_* drives the tool skeleton's
## gear/arrow/spring/blade/hinge/trigger joints. Without this second player the
## crank hand moved but the mechanism stayed frozen.
func _setup_gear_anim(loaded: Node) -> void:
	_gear_anim_player = null
	_gear_anim_lib = null
	_gear_skel = null
	_gear_loop_clip = ""
	_gear_current_clip = ""
	if loaded == null:
		return
	var skel: Skeleton3D = null
	for n: Node in loaded.find_children("*", "Skeleton3D", true, false):
		var sk := n as Skeleton3D
		if sk != null and sk.get_bone_count() > 0 and sk.find_bone("crank_arm") >= 0:
			skel = sk
			break
	if skel == null:
		push_warning("ZipwireGear: SK_Zipwire skeleton has no crank_arm bone; gear montage skipped")
		return
	var lib = ThiefAnimLib.new()
	if not lib.setup("club", skel):
		push_warning("ZipwireGear: gear animation library bind failed; mechanism falls back to the manual crank spin")
		return
	var host := skel.get_parent() as Node
	if host == null:
		return
	var player := AnimationPlayer.new()
	player.name = "GearAnimPlayer"
	host.add_child(player)
	player.root_node = player.get_path_to(host)
	_gear_anim_player = player
	_gear_anim_lib = lib
	_gear_skel = skel


## Plays the 4.35 s authored reload montage once, then the 1.32 s crank loop
## for the remainder of the 6 s hold (CT_WireCrank.CrankDuration lvl 0).
func _start_gear_crank() -> void:
	if _gear_anim_player == null or not is_instance_valid(_gear_anim_player) or _gear_anim_lib == null:
		return
	var start_clip: String = str(_gear_anim_lib.call("ensure_gear_clip", _gear_anim_player, "zipwire_gear_reload_start"))
	var loop_clip: String = str(_gear_anim_lib.call("ensure_gear_clip", _gear_anim_player, "zipwire_gear_reload_loop"))
	_gear_loop_clip = loop_clip
	if start_clip != "" and _gear_anim_player.has_animation(start_clip):
		_gear_current_clip = start_clip
		_gear_anim_player.play(start_clip, 0.0)
	elif loop_clip != "" and _gear_anim_player.has_animation(loop_clip):
		_gear_current_clip = loop_clip
		_gear_anim_player.play(loop_clip, 0.0)


func _tick_gear_crank() -> void:
	if _gear_anim_player == null or not is_instance_valid(_gear_anim_player):
		return
	if _gear_loop_clip == "" or _gear_current_clip == _gear_loop_clip:
		return
	if not _gear_anim_player.is_playing():
		_gear_current_clip = _gear_loop_clip
		_gear_anim_player.play(_gear_loop_clip, 0.0)


func _stop_gear_crank() -> void:
	if _gear_anim_player != null and is_instance_valid(_gear_anim_player) and _gear_anim_player.is_playing():
		_gear_anim_player.stop()
	# Stop() leaves the last evaluated pose on the tool skeleton, so the gear/
	# handle stayed frozen cranked after release (KF24 exit capture). Reset the
	# tool bind pose explicitly; the arm clip already returns to StandIdle.
	if _gear_skel != null and is_instance_valid(_gear_skel):
		_gear_skel.reset_bone_poses()
		_gear_skel.force_update_all_bone_transforms()
	_gear_current_clip = ""


## True when the gear player is actually driving crank_arm this frame. The
## manual _tp_crank_tick spin is then skipped so the authored UE rotation (and
## its arrow/gear phase) is not overwritten; the probe still gets the manual
## path because it calls _tp_crank_tick without starting a crank.
func _gear_drives_crank_arm() -> bool:
	if _gear_anim_player == null or not is_instance_valid(_gear_anim_player) or not _gear_anim_player.is_playing():
		return false
	var an: String = _gear_anim_player.current_animation
	if an == "":
		return false
	var anim: Animation = _gear_anim_player.get_animation(an)
	if anim == null:
		return false
	for ti in range(anim.get_track_count()):
		var path: NodePath = anim.track_get_path(ti)
		if path.get_subname_count() > 0 and str(path.get_subname(0)) == "crank_arm" \
				and anim.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
			return true
	return false


## Third-person crank drive (F13 3P form). Resolves the firing thief rig --
## the 3P body skeleton under mesh_root (SK_ThiefNisha_Dyn__Body) for the
## AN_Zipwire_Crank_Montage player, and the zipwire tool's crank handle
## (real SK_Zipwire crank_handle bone, else the ZipwireCrankHandle fallback
## sub-node) for the per-tick spin. Never touches fp_anim_player: the hidden
## 1P viewmodel keeps its own reload loop (animation_library.gd:84 untouched).
func _tp_crank_body_skel() -> Skeleton3D:
	if mesh_root == null or not is_instance_valid(mesh_root):
		return null
	for n in mesh_root.find_children("*", "Skeleton3D", true, false):
		var sk := n as Skeleton3D
		if sk != null and sk.get_bone_count() > 0:
			return sk
	return null


## Starts the 3P crank montage on the firing thief rig. No-op with a warning
## (never a crash) when the 3P body failed to load, the manifest lacks the
## clip, or the skeletons share no bones; the fallback handle still spins
## procedurally via _tp_crank_tick in that case.
func _tp_crank_start() -> void:
	_stop_gear_crank()
	_tp_crank_reset_handle()
	var skel := _tp_crank_body_skel()
	if skel == null:
		return
	var host := skel.get_parent() as Node
	if host == null:
		return
	var player := host.get_node_or_null("TPCrankPlayer") as AnimationPlayer
	if player == null:
		player = AnimationPlayer.new()
		player.name = "TPCrankPlayer"
		host.add_child(player)
		player.root_node = player.get_path_to(host)
	var clip_name := ""
	if player.has_animation("AN_Zipwire_Crank_Montage"):
		clip_name = "AN_Zipwire_Crank_Montage"
	else:
		var lib = ThiefAnimLib.new()
		if not lib.setup("club", skel):
			push_warning("ZipwireCrank3P: no 3P crank player, skeleton bind failed (UE clip TAT/Content/Art/Animation/Thief/Anim/Gear/Zipwire/AN_Zipwire_Crank_Montage)")
			return
		clip_name = str(lib.ensure_tp_crank_clip(player))
	if clip_name == "" or not player.has_animation(clip_name):
		push_warning("ZipwireCrank3P: crank clip no-op on 3P rig, manifest lacks clip or zero shared bones (UE clip TAT/Content/Art/Animation/Thief/Anim/Gear/Zipwire/AN_Zipwire_Crank_Montage)")
		return
	player.play(clip_name, FP_ANIM_BLEND)


## Spins the crank handle from crank_progress (absolute: 3 full turns over a
## full crank, so the handle rests exactly when cranking stops). The shipped
## SK_Zipwire.glb weights all 1,321 crank vertices to `crank_arm`; the
## `crank_handle` bone has ZERO weighted vertices. The old code rotated
## `crank_handle`, so the hand moved but the visible handle never did.
## Fallback order: crank_arm -> crank_handle -> crank -> procedural pivot.
const ZIPWIRE_CRANK_BONES: Array[String] = ["crank_arm", "crank_handle", "crank"]


func _tp_crank_tick() -> void:
	if fp_tool_root == null or not is_instance_valid(fp_tool_root):
		return
	if _gear_drives_crank_arm():
		return
	var angle: float = TAU * 3.0 * clampf(crank_progress, 0.0, 1.0)
	for n in fp_tool_root.find_children("*", "Skeleton3D", true, false):
		var sk := n as Skeleton3D
		if sk == null:
			continue
		for bone_name: String in ZIPWIRE_CRANK_BONES:
			var bi: int = sk.find_bone(bone_name)
			if bi >= 0:
				sk.set_bone_pose_rotation(bi, Quaternion(Vector3.UP, angle))
				return
	var handle := fp_tool_root.get_node_or_null("ZipwireCrankHandle") as Node3D
	if handle != null:
		handle.rotation = Vector3(angle, 0.0, 0.0)


## Resets the handle to rest pose (identity bone pose / zero pivot rotation).
func _tp_crank_reset_handle() -> void:
	if fp_tool_root == null or not is_instance_valid(fp_tool_root):
		return
	for n in fp_tool_root.find_children("*", "Skeleton3D", true, false):
		var sk := n as Skeleton3D
		if sk == null:
			continue
		for bone_name: String in ZIPWIRE_CRANK_BONES:
			var bi: int = sk.find_bone(bone_name)
			if bi >= 0:
				sk.set_bone_pose_rotation(bi, Quaternion.IDENTITY)
				return
	var handle := fp_tool_root.get_node_or_null("ZipwireCrankHandle") as Node3D
	if handle != null:
		handle.rotation = Vector3.ZERO


## Stops the 3P crank montage player; the handle keeps its final pose until
## the next crank resets it.
func _tp_crank_stop() -> void:
	_stop_gear_crank()
	_tp_crank_reset_handle()
	if mesh_root == null or not is_instance_valid(mesh_root):
		return
	for n in mesh_root.find_children("*", "TPCrankPlayer", true, false):
		var player := n as AnimationPlayer
		if player != null and player.is_playing():
			player.stop()


## P2 TPTakedownPlayer never stopped: overlapping crank+takedown montages
## fought on the same rig. Stops the attacker montage (never a crash when the
## rig failed to load; UE clip TAT/Content/Art/Animation/Thief/Anim/Gear/BlackJack/AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage).
func _tp_takedown_stop() -> void:
	if mesh_root == null or not is_instance_valid(mesh_root):
		return
	for n in mesh_root.find_children("*", "TPTakedownPlayer", true, false):
		var player := n as AnimationPlayer
		if player != null and player.is_playing():
			player.stop()


## Small procedural swing offset for the bone-attached tool when no real
## one-shot action animation is driving the wrist/socket.
func _update_fp_tool_on_bone(swing_k: float) -> void:
	if not _fp_tool_on_bone or fp_tool_root == null:
		return
	if _fp_action_ttl > 0.0 or swing_k <= 0.001:
		fp_tool_root.position = Vector3.ZERO
		fp_tool_root.rotation = Vector3.ZERO
		return
	fp_tool_root.position = Vector3(0.0, swing_k * -0.05, swing_k * -0.08)
	fp_tool_root.rotation_degrees = Vector3(swing_k * -40.0, 0.0, 0.0)


## Procedural fallback rig (box gloves). Built only when the real ThiefNisha
## 1P mesh or clips fail to load, so machines without the assets see no
## regression.
func _build_procedural_fp_hands() -> void:
	var glove_mat: StandardMaterial3D = StandardMaterial3D.new()
	glove_mat.albedo_color = Color(0.07, 0.075, 0.10)
	glove_mat.roughness = 0.9
	glove_mat.metallic = 0.05
	fp_hand_l_root = Node3D.new()
	fp_hand_l_root.name = "HandLeft"
	fp_hand_l_root.position = Vector3(-0.28, -0.24, -0.55)
	fp_hand_l_root.rotation_degrees = Vector3(-8.0, 18.0, 6.0)
	fp_rig.add_child(fp_hand_l_root)
	_make_glove_hand(fp_hand_l_root, glove_mat, false)
	fp_hand_r_root = Node3D.new()
	fp_hand_r_root.name = "HandRight"
	fp_hand_r_root.position = Vector3(0.28, -0.24, -0.55)
	fp_hand_r_root.rotation_degrees = Vector3(-8.0, -18.0, -6.0)
	fp_rig.add_child(fp_hand_r_root)
	_make_glove_hand(fp_hand_r_root, glove_mat, true)


func _make_glove_hand(parent: Node3D, glove_mat: StandardMaterial3D, is_right: bool) -> void:
	var palm_mesh: BoxMesh = BoxMesh.new()
	palm_mesh.size = Vector3(0.09, 0.055, 0.15)
	palm_mesh.material = glove_mat
	var palm: MeshInstance3D = MeshInstance3D.new()
	palm.name = "PalmRight" if is_right else "PalmLeft"
	palm.mesh = palm_mesh
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(palm)
	var finger_mesh: BoxMesh = BoxMesh.new()
	finger_mesh.size = Vector3(0.08, 0.045, 0.09)
	finger_mesh.material = glove_mat
	var fingers: MeshInstance3D = MeshInstance3D.new()
	fingers.name = "FingersRight" if is_right else "FingersLeft"
	fingers.mesh = finger_mesh
	fingers.position = Vector3(0.0, -0.008, -0.105)
	fingers.rotation_degrees.x = 12.0
	fingers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fingers)
	var cuff_mesh: CylinderMesh = CylinderMesh.new()
	cuff_mesh.top_radius = 0.045
	cuff_mesh.bottom_radius = 0.055
	cuff_mesh.height = 0.10
	cuff_mesh.radial_segments = 10
	cuff_mesh.material = glove_mat
	var cuff: MeshInstance3D = MeshInstance3D.new()
	cuff.name = "CuffRight" if is_right else "CuffLeft"
	cuff.mesh = cuff_mesh
	cuff.position = Vector3(0.0, 0.01, 0.11)
	cuff.rotation_degrees.x = 78.0
	cuff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(cuff)


func _fp_clear_tool() -> void:
	_stop_gear_crank()
	_gear_anim_player = null
	_gear_anim_lib = null
	_gear_skel = null
	_gear_loop_clip = ""
	if fp_tool_root == null:
		return
	for child: Node in fp_tool_root.get_children():
		fp_tool_root.remove_child(child)
		child.queue_free()


func _fp_set_tool(tool_id: String) -> void:
	fp_tool_id = tool_id
	if fp_tool_root == null:
		return
	_fp_clear_tool()
	var loaded: Node = _fp_try_load_tool_glb(tool_id)
	if loaded != null:
		fp_tool_root.add_child(loaded)
		if tool_id == "zipwire":
			_setup_gear_anim(loaded)
		return
	match tool_id:
		"zipwire":
			_build_fp_zipwire_fallback()
		"smoke_bomb":
			_build_fp_smoke_fallback()
		"slithersap":
			_build_fp_sap_fallback()
		"fairy":
			_build_fp_fairy_fallback()
		_:
			_build_fp_blackjack_fallback()


func _load_raw_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


func _apply_blackjack_materials(root_node: Node) -> void:
	# Mi_Blackjack is null in materials.json (lowercase Mi_ skipped by parser);
	# bind T_Blackjack_{D,N,ORM}.png directly per Mi_Blackjack.json.
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.6
	mat.albedo_texture = _load_raw_tex("res://assets/ue/Raw/Art/Gameplay/Gear/BlackJack/T_Blackjack_D.png")
	var norm: Texture2D = _load_raw_tex("res://assets/ue/Raw/Art/Gameplay/Gear/BlackJack/T_Blackjack_N.png")
	if norm != null:
		mat.normal_enabled = true
		mat.normal_texture = norm
	var orm: Texture2D = _load_raw_tex("res://assets/ue/Raw/Art/Gameplay/Gear/BlackJack/T_Blackjack_ORM.png")
	if orm != null:
		mat.ao_enabled = true
		mat.ao_texture = orm
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness_texture = orm
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic = 1.0
		mat.metallic_texture = orm
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	for child: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi != null and mi.mesh != null:
			for s: int in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(s, mat)


func _apply_vistara_materials(root_node: Node) -> void:
	# SK_VistaraDiamond collides in mesh_materials.json on MI_VistaraDiamond:
	# surface 0 is GemShader crystal, surface 1 is brass tongs.
	# UE-derived energy cap: MI_VistaraDiamond cooks with "Emissive On?" = false
	# and null Emissive (extracted/json/Art/Gameplay/Gear/VistaraDiamond/
	# MI_VistaraDiamond.json), so the port gem emissive stays modest under
	# bloom (mission glow_intensity 0.65, DenMoonBeam 0.65). VFX spawn knobs
	# stay in the 0.3-4.5 range, light_probe.gd:115 weight unchanged.
	const TONGS_ENERGY_CAP := 0.65
	const DIAMOND_ENERGY_CAP := 0.65
	var loader: Node = _get_fp_mat_loader()
	var gem_mat := StandardMaterial3D.new()
	gem_mat.albedo_color = Color(0.318, 0.664, 1.0, 0.78)
	gem_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gem_mat.roughness = 0.2
	gem_mat.metallic = 0.05
	gem_mat.emission_enabled = true
	gem_mat.emission = Color(0.32, 0.72, 1.0)
	gem_mat.emission_energy_multiplier = DIAMOND_ENERGY_CAP
	assert(gem_mat.emission_energy_multiplier <= DIAMOND_ENERGY_CAP + 0.001, "DiamondCap: gem energy exceeds UE-derived cap")
	print("DiamondCap: vistara gem emission_energy=", gem_mat.emission_energy_multiplier, " cap=", DIAMOND_ENERGY_CAP, " (UE MI_VistaraDiamond Emissive Off; mission glow 0.65)")
	gem_mat.set_meta("fresnel_color", Color(0.75, 0.94, 1.0))
	gem_mat.set_meta("fresnel_power", 2.4)
	gem_mat.set_meta("fresnel_strength", 1.8)
	var tong_mat: Material = null
	if loader != null:
		tong_mat = loader.call("get_material_for_ue", "/Game/Art/Gameplay/Gear/VistaraDiamond/MI_VistaraDiamond") as Material
	if tong_mat is StandardMaterial3D and (tong_mat as StandardMaterial3D).emission_enabled:
		(tong_mat as StandardMaterial3D).emission_energy_multiplier = minf((tong_mat as StandardMaterial3D).emission_energy_multiplier, TONGS_ENERGY_CAP)
		assert((tong_mat as StandardMaterial3D).emission_energy_multiplier <= TONGS_ENERGY_CAP + 0.001, "TongsCap: tongs energy exceeds cap")
		print("TongsCap: tongs emission_energy=", (tong_mat as StandardMaterial3D).emission_energy_multiplier, " cap=", TONGS_ENERGY_CAP, " (UE MI_VistaraDiamond Emissive Off; mission glow 0.65)")
	for child: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh.get_surface_count() >= 1:
			mi.set_surface_override_material(0, gem_mat)
		if mi.mesh.get_surface_count() >= 2 and tong_mat != null:
			mi.set_surface_override_material(1, tong_mat)


func _apply_fairy_materials(root_node: Node) -> void:
	const FAIRY_ORB_ENERGY_CAP := 0.65
	# SK_PickpocketFairy has 5 surfaces: [0] bubble orb & [2] jar had stem
	# collision onto T_InsultFairy_Teeth_D.png in materials.json; override
	# [0] & [2] cleanly and load [1, 3, 4] via LevelLoader.
	_bind_ue_mesh_materials(root_node, "/Game/Art/Gameplay/Gear/PickpocketFairy/SK_PickpocketFairy")
	var orb_mat := StandardMaterial3D.new()
	orb_mat.albedo_color = Color(0.48, 0.25, 1.0, 0.65)
	orb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orb_mat.roughness = 0.15
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(0.45, 0.85, 1.0)
	orb_mat.emission_energy_multiplier = FAIRY_ORB_ENERGY_CAP
	assert(orb_mat.emission_energy_multiplier <= FAIRY_ORB_ENERGY_CAP + 0.001, "FairyCap: fairy orb energy exceeds cap")
	print("FairyCap: fairy orb emission_energy=", orb_mat.emission_energy_multiplier, " cap=", FAIRY_ORB_ENERGY_CAP, " (no UE orb authoring; mission glow 0.65)")
	orb_mat.set_meta("fresnel_color", Color(0.55, 0.95, 1.0))
	orb_mat.set_meta("fresnel_power", 2.2)
	orb_mat.set_meta("fresnel_strength", 1.5)
	var jar_mat := StandardMaterial3D.new()
	jar_mat.albedo_color = Color(0.06, 0.042, 0.034)
	jar_mat.roughness = 0.72
	jar_mat.metallic = 0.15
	var wicker_n: Texture2D = _load_raw_tex("res://assets/ue/Raw/MaterialLibrary/Environment/WickerClay/T_WickerClayTrimTexture_N.png")
	if wicker_n != null:
		jar_mat.normal_enabled = true
		jar_mat.normal_texture = wicker_n
	var wicker_orm: Texture2D = _load_raw_tex("res://assets/ue/Raw/MaterialLibrary/Environment/WickerClay/T_WickerClayTrimTexture_ORM.png")
	if wicker_orm != null:
		jar_mat.roughness_texture = wicker_orm
		jar_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	for child: Node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh.get_surface_count() >= 1:
			mi.set_surface_override_material(0, orb_mat)
		if mi.mesh.get_surface_count() >= 3:
			mi.set_surface_override_material(2, jar_mat)


func _fp_try_load_tool_glb(tool_id: String) -> Node:
	var specs: Dictionary = {
		"zipwire": {
			"glb": "res://assets/ue/Content/Art/Gameplay/Gear/Zipwire/SK_Zipwire.glb",
			"ue": "/Game/Art/Gameplay/Gear/Zipwire/SK_Zipwire",
		},
		"smoke_bomb": {
			"glb": "res://assets/ue/Content/Art/Gameplay/Gear/SmokeBomb/SK_SmokeBomb.glb",
			"ue": "/Game/Art/Gameplay/Gear/SmokeBomb/SK_SmokeBomb",
		},
		"slithersap": {
			"glb": "res://assets/ue/Content/Art/Gameplay/Gear/Slithersap/SK_SlimeBomb.glb",
			"ue": "/Game/Art/Gameplay/Gear/Slithersap/SK_SlimeBomb",
		},
		"blackjack": {
			"glb": "res://assets/ue/Content/Art/Gameplay/Gear/BlackJack/SK_BlackJack.glb",
			"ue": "/Game/Art/Gameplay/Gear/BlackJack/SK_BlackJack",
		},
		"fairy": {
			"glb": "res://assets/ue/Content/Art/Gameplay/Gear/PickpocketFairy/SK_PickpocketFairy.glb",
			"ue": "/Game/Art/Gameplay/Gear/PickpocketFairy/SK_PickpocketFairy",
		},
		"vistara_diamond": {
			"glb": "res://assets/ue/Content/Art/Gameplay/Gear/VistaraDiamond/SK_VistaraDiamond.glb",
			"ue": "/Game/Art/Gameplay/Gear/VistaraDiamond/SK_VistaraDiamond",
		},
	}
	if not specs.has(tool_id):
		return null
	var spec: Dictionary = specs[tool_id] as Dictionary
	var glb_path: String = str(spec["glb"])
	if not ResourceLoader.exists(glb_path):
		return null
	var res: Resource = ResourceLoader.load(glb_path)
	if not (res is PackedScene):
		return null
	var inst: Node = (res as PackedScene).instantiate()
	var inst3d := inst as Node3D
	if inst3d != null:
		inst3d.scale = Vector3.ONE
		# SKEL_Base.json weapon_r_1pSocket RelativeRotation Roll = -90 deg.
		inst3d.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	match tool_id:
		"blackjack":
			_apply_blackjack_materials(inst)
		"vistara_diamond":
			_apply_vistara_materials(inst)
		"fairy":
			_apply_fairy_materials(inst)
		_:
			_bind_ue_mesh_materials(inst, str(spec["ue"]))
	_set_cast_shadow_recursive(inst, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_apply_viewmodel_isolation(inst)
	return inst


const FP_FALLBACK_ENERGY_CAP := 0.65
func _fp_fallback_mat(base: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = base
	mat.roughness = 0.55
	mat.metallic = 0.25
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = minf(energy, FP_FALLBACK_ENERGY_CAP)
		assert(mat.emission_energy_multiplier <= FP_FALLBACK_ENERGY_CAP + 0.001, "FallbackCap: fp fallback energy exceeds cap")
		if energy > FP_FALLBACK_ENERGY_CAP + 0.001:
			print("FallbackCap: fp fallback emission_energy=", mat.emission_energy_multiplier, " cap=", FP_FALLBACK_ENERGY_CAP, " (port-authored glow clamped to mission glow 0.65)")
	return mat


func _build_fp_blackjack_fallback() -> void:
	var leather: StandardMaterial3D = _fp_fallback_mat(Color(0.12, 0.09, 0.07), Color(0, 0, 0), 0.0)
	var handle_mesh: CylinderMesh = CylinderMesh.new()
	handle_mesh.top_radius = 0.022
	handle_mesh.bottom_radius = 0.026
	handle_mesh.height = 0.16
	handle_mesh.radial_segments = 10
	handle_mesh.material = leather
	var handle: MeshInstance3D = MeshInstance3D.new()
	handle.name = "BlackjackHandle"
	handle.mesh = handle_mesh
	handle.rotation_degrees = Vector3(65.0, 0.0, 0.0)
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fp_tool_root.add_child(handle)
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = 0.045
	head_mesh.height = 0.09
	head_mesh.radial_segments = 12
	head_mesh.rings = 8
	head_mesh.material = leather
	var club_head: MeshInstance3D = MeshInstance3D.new()
	club_head.name = "BlackjackHead"
	club_head.mesh = head_mesh
	club_head.position = Vector3(0.0, 0.055, -0.075)
	club_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fp_tool_root.add_child(club_head)


func _build_fp_zipwire_fallback() -> void:
	const ZIPWIRE_TIP_ENERGY_CAP := 0.65
	var frame_mat: StandardMaterial3D = _fp_fallback_mat(Color(0.16, 0.15, 0.14), Color(0, 0, 0), 0.0)
	var glow_mat: StandardMaterial3D = _fp_fallback_mat(Color(0.4, 0.85, 1.0), Color(0.35, 0.8, 1.0), 2.0)
	assert(glow_mat.emission_energy_multiplier <= ZIPWIRE_TIP_ENERGY_CAP + 0.001, "ZipwireTipCap: zipwire tip energy exceeds cap")
	print("ZipwireTipCap: zipwire tip emission_energy=", glow_mat.emission_energy_multiplier, " cap=", ZIPWIRE_TIP_ENERGY_CAP, " (port-authored glow clamped to mission glow 0.65)")
	var body_mesh: BoxMesh = BoxMesh.new()
	body_mesh.size = Vector3(0.05, 0.07, 0.30)
	body_mesh.material = frame_mat
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "ZipwireBody"
	body.mesh = body_mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fp_tool_root.add_child(body)
	var bow_mesh: BoxMesh = BoxMesh.new()
	bow_mesh.size = Vector3(0.22, 0.03, 0.04)
	bow_mesh.material = frame_mat
	var bow: MeshInstance3D = MeshInstance3D.new()
	bow.name = "ZipwireBow"
	bow.mesh = bow_mesh
	bow.position = Vector3(0.0, 0.02, -0.15)
	bow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fp_tool_root.add_child(bow)
	var tip_mesh: SphereMesh = SphereMesh.new()
	tip_mesh.radius = 0.02
	tip_mesh.height = 0.04
	tip_mesh.material = glow_mat
	for i: int in range(2):
		var tip: MeshInstance3D = MeshInstance3D.new()
		tip.name = "ZipwireTip"
		tip.mesh = tip_mesh
		tip.position = Vector3(-0.10 if i == 0 else 0.10, 0.02, -0.15)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fp_tool_root.add_child(tip)
	# Crank-handle sub-node (F13 3P form). The driven pivot the 3P crank tick
	# spins while _is_cranking holds: Node3D pivot + arm + knob, mirroring the
	# SKEL_Zipwire crank_arm -> crank_handle chain on the real SK_Zipwire GLB
	# (UE /Game/Art/Gameplay/Gear/Zipwire/SKEL_Zipwire). Absolute rotation is
	# set from crank_progress, so the handle rests when cranking stops.
	var crank_pivot: Node3D = Node3D.new()
	crank_pivot.name = "ZipwireCrankHandle"
	crank_pivot.position = Vector3(0.035, -0.01, 0.06)
	fp_tool_root.add_child(crank_pivot)
	var crank_arm_mesh: BoxMesh = BoxMesh.new()
	crank_arm_mesh.size = Vector3(0.015, 0.09, 0.015)
	crank_arm_mesh.material = frame_mat
	var crank_arm: MeshInstance3D = MeshInstance3D.new()
	crank_arm.name = "CrankArm"
	crank_arm.mesh = crank_arm_mesh
	crank_arm.position = Vector3(0.0, 0.045, 0.0)
	crank_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crank_pivot.add_child(crank_arm)
	var knob_mesh: CylinderMesh = CylinderMesh.new()
	knob_mesh.top_radius = 0.012
	knob_mesh.bottom_radius = 0.012
	knob_mesh.height = 0.05
	knob_mesh.radial_segments = 8
	knob_mesh.material = frame_mat
	var knob: MeshInstance3D = MeshInstance3D.new()
	knob.name = "CrankKnob"
	knob.mesh = knob_mesh
	knob.position = Vector3(0.0, 0.09, -0.02)
	knob.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crank_pivot.add_child(knob)


func _build_fp_smoke_fallback() -> void:
	var bomb_mat: StandardMaterial3D = _fp_fallback_mat(Color(0.10, 0.10, 0.12), Color(0, 0, 0), 0.0)
	var bomb_mesh: SphereMesh = SphereMesh.new()
	bomb_mesh.radius = 0.05
	bomb_mesh.height = 0.10
	bomb_mesh.radial_segments = 12
	bomb_mesh.rings = 8
	bomb_mesh.material = bomb_mat
	var bomb: MeshInstance3D = MeshInstance3D.new()
	bomb.name = "SmokeBomb"
	bomb.mesh = bomb_mesh
	bomb.position = Vector3(0.0, 0.03, 0.0)
	bomb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fp_tool_root.add_child(bomb)
	var fuse_mesh: CylinderMesh = CylinderMesh.new()
	fuse_mesh.top_radius = 0.008
	fuse_mesh.bottom_radius = 0.008
	fuse_mesh.height = 0.05
	fuse_mesh.material = _fp_fallback_mat(Color(0.5, 0.35, 0.15), Color(0, 0, 0), 0.0)
	var fuse: MeshInstance3D = MeshInstance3D.new()
	fuse.name = "SmokeFuse"
	fuse.mesh = fuse_mesh
	fuse.position = Vector3(0.0, 0.09, 0.0)
	fuse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fp_tool_root.add_child(fuse)


func _build_fp_sap_fallback() -> void:
	const SAP_VIAL_ENERGY_CAP := 0.65
	var vial_mat: StandardMaterial3D = StandardMaterial3D.new()
	vial_mat.albedo_color = Color(0.3, 0.9, 0.65, 0.85)
	vial_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vial_mat.emission_enabled = true
	vial_mat.emission = Color(0.3, 1.0, 0.7)
	vial_mat.emission_energy_multiplier = SAP_VIAL_ENERGY_CAP
	assert(vial_mat.emission_energy_multiplier <= SAP_VIAL_ENERGY_CAP + 0.001, "SapCap: sap vial energy exceeds cap")
	print("SapCap: sap vial emission_energy=", vial_mat.emission_energy_multiplier, " cap=", SAP_VIAL_ENERGY_CAP, " (UE MI_SlimeBomb EmissiveStrength unrecovered; mission glow 0.65)")
	var vial_mesh: CylinderMesh = CylinderMesh.new()
	vial_mesh.top_radius = 0.03
	vial_mesh.bottom_radius = 0.03
	vial_mesh.height = 0.11
	vial_mesh.radial_segments = 12
	vial_mesh.material = vial_mat
	var vial: MeshInstance3D = MeshInstance3D.new()
	vial.name = "SapVial"
	vial.mesh = vial_mesh
	vial.rotation_degrees = Vector3(55.0, 0.0, 0.0)
	vial.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fp_tool_root.add_child(vial)


func _build_fp_fairy_fallback() -> void:
	const FAIRY_FALLBACK_ENERGY_CAP := 0.65
	var glow_mat: StandardMaterial3D = _fp_fallback_mat(Color(0.55, 0.95, 1.0), Color(0.4, 0.9, 1.0), 2.5)
	var orb_mesh: SphereMesh = SphereMesh.new()
	orb_mesh.radius = 0.035
	assert(glow_mat.emission_energy_multiplier <= FAIRY_FALLBACK_ENERGY_CAP + 0.001, "FairyFallbackCap: fairy fallback energy exceeds cap")
	print("FairyFallbackCap: fairy fallback emission_energy=", glow_mat.emission_energy_multiplier, " cap=", FAIRY_FALLBACK_ENERGY_CAP, " (port-authored glow clamped to mission glow 0.65)")
	orb_mesh.height = 0.07
	orb_mesh.radial_segments = 12
	orb_mesh.rings = 8
	orb_mesh.material = glow_mat
	var orb: MeshInstance3D = MeshInstance3D.new()
	orb.name = "FairyOrb"
	orb.mesh = orb_mesh
	orb.position = Vector3(0.0, 0.05, -0.02)
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fp_tool_root.add_child(orb)


func _fp_play_swing() -> void:
	fp_swing_t = 0.32


func _update_smoke_trajectory() -> void:
	const SMOKE_TRAJ_ENERGY_CAP := 0.65
	var show_traj: bool = (
		equipped_tool == "smoke_bomb"
		and int(charges.get("smoke_bomb", 0)) > 0
		and GameState.state == "playing"
		and can_act()
		and cam != null
		and is_inside_tree()
	)
	if not show_traj:
		if _smoke_traj_mesh != null and is_instance_valid(_smoke_traj_mesh):
			_smoke_traj_mesh.visible = false
		return
	var w3d := get_world_3d()
	if w3d == null:
		return
	if _smoke_traj_mesh == null or not is_instance_valid(_smoke_traj_mesh):
		var im := ImmediateMesh.new()
		var tmat := StandardMaterial3D.new()
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		tmat.albedo_color = Color(0.98, 0.96, 0.84, 0.85)
		tmat.emission_enabled = true
		tmat.emission = Color(0.95, 0.92, 0.78)
		tmat.emission_energy_multiplier = SMOKE_TRAJ_ENERGY_CAP
		assert(tmat.emission_energy_multiplier <= SMOKE_TRAJ_ENERGY_CAP + 0.001, "SmokeTrajCap: smoke traj energy exceeds cap")
		print("SmokeTrajCap: smoke traj emission_energy=", tmat.emission_energy_multiplier, " cap=", SMOKE_TRAJ_ENERGY_CAP, " (no UE traj authoring; mission glow 0.65)")
		_smoke_traj_mesh = MeshInstance3D.new()
		_smoke_traj_mesh.name = "SmokeTrajectoryMesh"
		_smoke_traj_mesh.top_level = true
		_smoke_traj_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_smoke_traj_mesh.mesh = im
		_smoke_traj_mesh.material_override = tmat
		add_child(_smoke_traj_mesh)
	var mesh_im := _smoke_traj_mesh.mesh as ImmediateMesh
	if mesh_im == null:
		return
	mesh_im.clear_surfaces()
	var fwd: Vector3 = -cam.global_transform.basis.z
	var right: Vector3 = cam.global_transform.basis.x
	var up: Vector3 = cam.global_transform.basis.y
	var p0: Vector3 = cam.global_position + fwd * 0.5 + right * 0.14 - up * 0.05
	var v0: Vector3 = fwd * SmokeProjectileScript.INITIAL_SPEED_M_S
	var g_vec := Vector3(0.0, -gravity, 0.0)
	var pts: PackedVector3Array = [p0]
	var space: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var excl: Array[RID] = [get_rid()]
	var prev: Vector3 = p0
	for i: int in range(1, 33):
		var t: float = float(i) * 0.06
		var nxt: Vector3 = p0 + v0 * t + 0.5 * g_vec * (t * t)
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(prev, nxt, 1, excl))
		if not hit.is_empty():
			pts.append(hit["position"] as Vector3)
			break
		pts.append(nxt)
		prev = nxt
	if pts.size() < 2:
		_smoke_traj_mesh.visible = false
		return
	_smoke_traj_mesh.visible = true
	_smoke_traj_mesh.global_transform = Transform3D.IDENTITY
	mesh_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in range(pts.size()):
		var pt: Vector3 = pts[i]
		var frac: float = float(i) / float(pts.size() - 1)
		var half_w: float = lerpf(0.016, 0.008, frac)
		var tang: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side: Vector3 = tang.cross(Vector3.UP)
		if side.length() < 0.05:
			side = right
		else:
			side = side.normalized()
		mesh_im.surface_add_vertex(pt - side * half_w)
		mesh_im.surface_add_vertex(pt + side * half_w)
	mesh_im.surface_end()


func _update_first_person(delta: float) -> void:
	if fp_rig == null or cam == null:
		return
	fp_breathe_time += delta
	if _fp_action_ttl > 0.0:
		_fp_action_ttl = maxf(0.0, _fp_action_ttl - delta)
	if fp_swing_t > 0.0:
		fp_swing_t = maxf(0.0, fp_swing_t - delta)
	var planar: float = Vector2(velocity.x, velocity.z).length()
	var moving: bool = is_on_floor() and planar > 0.5
	var bob_amp: float = 0.012
	if is_sprinting:
		bob_amp = 0.022
	elif is_crouching:
		bob_amp = 0.008
	elif not moving:
		bob_amp = 0.003
	var bob_y: float = sin(fp_bob_phase * 2.0) * bob_amp + sin(fp_breathe_time * 1.6) * 0.004
	var bob_x: float = cos(fp_bob_phase) * bob_amp * 0.6
	fp_rig.position = fp_base_rig_pos + Vector3(bob_x, bob_y, 0.0)
	fp_rig.rotation.z = cos(fp_bob_phase * 0.5) * 0.008
	var swing_k: float = 0.0
	if fp_swing_t > 0.0:
		swing_k = fp_swing_t / 0.32
	if _fp_use_real_arms:
		_update_fp_anim_state()
		_update_fp_tool_on_bone(swing_k)
		return
	if fp_tool_root != null:
		fp_tool_root.position = Vector3(0.28, -0.18, -0.62 + swing_k * -0.22)
		fp_tool_root.rotation_degrees = Vector3(swing_k * -55.0, 0.0, swing_k * 12.0)
	if fp_hand_r_root != null:
		fp_hand_r_root.position = Vector3(0.28, -0.24 + swing_k * -0.06, -0.55 + swing_k * -0.12)
		fp_hand_r_root.rotation_degrees = Vector3(-8.0 + swing_k * -30.0, -18.0, -6.0)
	if fp_hand_l_root != null and moving:
		fp_hand_l_root.position.y = -0.24 + cos(fp_bob_phase * 2.0 + 1.2) * bob_amp * 0.7


func _update_prop_highlight() -> void:
	var best: Node = _get_nearest_ko_guard()
	if best == null:
		best = get_nearest_interactable()
	if best == fp_highlight_target:
		return
	if fp_highlight_target != null and is_instance_valid(fp_highlight_target):
		VfxManager.set_prop_highlight(fp_highlight_target, false)
	fp_highlight_target = best
	if fp_highlight_target != null:
		VfxManager.set_prop_highlight(fp_highlight_target, true)


func _update_thief_vision() -> void:
	thief_vision = thief_vision_on
	if not is_inside_tree():
		return
	for n: Node in get_tree().get_nodes_in_group("thief_vision_highlight"):
		if n.has_method("set_xray_highlight"):
			n.call("set_xray_highlight", thief_vision_on, "")
		elif n.has_method("set_highlighted"):
			n.call("set_highlighted", thief_vision_on)
		elif n.has_method("set_highlight"):
			n.call("set_highlight", thief_vision_on)
