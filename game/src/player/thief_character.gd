extends CharacterBody3D
## Playable Thief controller (Spider, Chameleon, Moth) with stamina, crouch, lean,
## grapple/disguise/astral abilities, Slithersap, Smoke Bomb, Pickpocket Fairy, and Blackjack.

const VfxManager = preload("res://src/core/vfx_manager.gd")
const MobileProfile := preload("res://src/core/mobile_profile.gd")
const ThiefAnimLib = preload("res://src/core/animation_library.gd")

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
const FLOOR_MAX_ANGLE_DEG: float = 60.0 # CharMoveComp.WalkableFloorAngle
const INTERACT_RANGE: float = 1.75 # TATInteractionTargeterComponent.MaxInteractionRange 175cm
const CAMERA_FOV: float = 85.0 # OSECameraComponent.FirstPersonFieldOfView
const CAMERA_FOV_SPRINT: float = 89.0 # retained velocity-feedback shape rebased on 85
const WIRE_RANGE: float = 20.0 # DA_StandardToolSettings "Hotwire Range" 2000cm
const WIRE_PULL_SPEED: float = 23.0 # DA_StandardToolSettings "Hotwire Speed" 2300cm/s
const DISGUISE_COOLDOWN: float = 15.0 # GE_Disguise_Cooldown magnitude
const DISGUISE_ACTIVE_TIME: float = 60.0 # GE_Disguise_Active magnitude (max active time)
const BLACKJACK_LIGHT_DMG: float = 40.0 # CT_Tool_Blackjack.BlackjackDamageLight
const BLACKJACK_HEAVY_DMG: float = 75.0 # CT_Tool_Blackjack.BlackjackDamageHeavy

signal health_changed(hp: float, max_hp: float)
signal stamina_changed(stam: float, max_stam: float)
signal disguise_changed(integrity: float, active: bool)
signal thief_vision_toggled(enabled: bool)
signal tool_used(tool_id: String, charges_left: int)
signal interacted(target: Node)
signal downed_started(seconds: float)
signal downed()

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
var lean_dir: float = 0.0
var thief_vision_on: bool = false
var thief_vision: bool = false
const DISGUISE_STEAL_RANGE: float = 2.8 # retained approximation: no UE source; interaction targeter range is 1.75
const GRAPPLE_ARRIVE_DIST: float = 1.8 # retained: no UE source; HotwireArrivalThreshold 1.0m noted in player_tools.json
const GRAPPLE_VAULT_Y: float = 6.5
const GRAPPLE_MIN_RANGE: float = 3.0
const GRAPPLE_MAX_RANGE: float = WIRE_RANGE
const GRAPPLE_WINCH_TIME: float = 0.35
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
var mesh_3p_glb: String = ""
var fp_tool_id: String = "blackjack"
var fp_bob_phase: float = 0.0
var fp_breathe_time: float = 0.0
var fp_step_left: bool = false
var fp_swing_t: float = 0.0
var fp_base_rig_pos: Vector3 = Vector3.ZERO
var fp_highlight_target: Node = null

# Abilities
var ability_cooldown: float = 0.0
var disguise_active: bool = false
var disguise_integrity: float = 100.0
var disguise_ttl: float = 0.0
var is_grappling: bool = false
var grapple_target: Vector3 = Vector3.ZERO
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

var head: Node3D
var cam: Camera3D
var spring_arm: SpringArm3D
var col_shape: CollisionShape3D
var mesh_root: Node3D
var light_probe: Node
var level_ctrl: Node


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4
	_apply_tuning()
	_build_body()
	if not OS.has_feature("headless") and DisplayServer.get_name() != "headless" and not MobileProfile.is_mobile():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
func _apply_fall_damage(drop_m: float) -> float:
	if is_grappling or astral_active:
		return 0.0
	var dmg: float = fall_damage_for_drop(drop_m)
	if dmg > 0.0:
		take_damage(dmg)
	return dmg


## Tracks the airborne peak and converts the air->floor transition into a
## fall-damage event. Call at the top of _physics_process (is_on_floor
## reflects the previous frame's move_and_slide).
func _track_fall_state() -> void:
	var on_floor_now: bool = is_on_floor()
	if on_floor_now and not _was_on_floor:
		_apply_fall_damage(_fall_peak_y - global_position.y)
	if on_floor_now:
		_fall_peak_y = global_position.y
	else:
		if is_grappling or astral_active:
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
	cam.fov = CAMERA_FOV
	cam.current = true
	spring_arm.add_child(cam)
	_build_first_person_rig()


func _unhandled_input(event: InputEvent) -> void:
	if GameState.state != "playing":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not MobileProfile.is_mobile():
		rotate_y(-event.relative.x * mouse_sens)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * mouse_sens, deg_to_rad(-80), deg_to_rad(80))
		return
	# Downed: camera look above stays live; everything else is blocked.
	if not can_act():
		return
	if event.is_action_pressed("crouch"):
		is_crouching = not is_crouching
		var cap: CapsuleShape3D = col_shape.shape as CapsuleShape3D
		if cap != null:
			cap.height = 1.0 if is_crouching else 1.78
			col_shape.position.y = cap.height * 0.5
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("ability"):
		_trigger_thief_ability()
	elif event.is_action_pressed("tool_1"):
		_use_slithersap()
	elif event.is_action_pressed("tool_2"):
		_use_smoke_bomb()
	elif event.is_action_pressed("tool_3"):
		_use_pickpocket_fairy()
	elif event.is_action_pressed("tool_4") or event.is_action_pressed("primary_action"):
		if GameState.thief_id == "spider":
			var grappled: bool = _try_spider_grapple()
			if not grappled:
				_try_blackjack()
		else:
			_try_blackjack()
	elif event.is_action_pressed("secondary_action"):
		_throw_bottle()
	elif event.is_action_pressed("thief_vision"):
		thief_vision = not thief_vision
		thief_vision_on = thief_vision
		thief_vision_toggled.emit(thief_vision)
		_update_thief_vision()


## Touch look hook used by src/ui/mobile_touch_ui.gd: mouse look is unavailable on Android.
func add_look_pixel_delta(delta_px: Vector2) -> void:
	if GameState.state != "playing":
		return
	if absf(delta_px.x) < 0.001 and absf(delta_px.y) < 0.001:
		return
	rotate_y(-delta_px.x * mouse_sens)
	if head != null:
		head.rotation.x = clampf(head.rotation.x - delta_px.y * mouse_sens, deg_to_rad(-80), deg_to_rad(80))


func _physics_process(delta: float) -> void:
	if GameState.state != "playing":
		return
	ability_cooldown = maxf(0.0, ability_cooldown - delta)
	pickpocket_cooldown = maxf(0.0, pickpocket_cooldown - delta)
	_tick_astral(delta)
	_tick_downed(delta)
	_tick_post_revive(delta)
	_track_fall_state()

	# Downed: no input movement, sprint, abilities or tools; gravity still
	# settles the body and the downed timer (above) runs to mission failure.
	if is_downed:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
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

	# Spider grapple pull override (smooth winch ramp toward the anchor, then
	# preserve momentum and vault upward on arrival/release).
	if is_grappling:
		var wire_speed: float = WIRE_PULL_SPEED
		grapple_time += delta
		var to_anchor: Vector3 = grapple_target - global_position
		var anchor_dist: float = to_anchor.length()
		var released: bool = Input.is_action_just_released("ability") or Input.is_action_just_released("tool_4") or Input.is_action_just_released("primary_action")
		var winch: float = clampf(grapple_time / GRAPPLE_WINCH_TIME, 0.3, 1.0)
		var pull_dir: Vector3 = to_anchor.normalized() if anchor_dist > 0.05 else Vector3.ZERO
		if anchor_dist < GRAPPLE_ARRIVE_DIST or released:
			is_grappling = false
			velocity = pull_dir * wire_speed * (0.45 + 0.15 * winch)
			velocity.y = maxf(velocity.y, GRAPPLE_VAULT_Y * (0.7 + 0.3 * winch))
			move_and_slide()
			return
		else:
			var desired: Vector3 = pull_dir * wire_speed * winch + Vector3.UP * 1.4
			velocity = velocity.lerp(desired, clampf(delta * 7.0, 0.0, 1.0))
			move_and_slide()
			return

	# Movement & Stamina
	var inp: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish: Vector3 = (transform.basis * Vector3(inp.x, 0.0, inp.y)).normalized()
	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching and wish.length() > 0.1 and stamina > 2.0

	var speed: float = walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting:
		speed = sprint_speed
		var drain: float = absf(GameData.eval_curve("CT_StaminaSystem", "StaminaPerSecond.Sprint", 1.0, -5.0))
		stamina = maxf(0.0, stamina - drain * delta)
	else:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)
	stamina_changed.emit(stamina, max_stamina)

	# Velocity FOV feedback (BP_CameraModifier_VelocityFOV)
	cam.fov = lerpf(cam.fov, CAMERA_FOV_SPRINT if is_sprinting else CAMERA_FOV, delta * 8.0)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var steer: float = 14.0 if is_on_floor() else 14.0 * AIR_CONTROL
	velocity.x = lerpf(velocity.x, wish.x * speed, delta * steer)
	velocity.z = lerpf(velocity.z, wish.z * speed, delta * steer)
	move_and_slide()

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

	# Chameleon Disguise Integrity drain (faster while sprinting or near guards).
	if disguise_active:
		var drain_rate: float = 6.7
		if is_sprinting:
			drain_rate *= 1.8
		if _is_guard_within(5.0):
			drain_rate *= 2.0
		disguise_integrity = maxf(0.0, disguise_integrity - drain_rate * delta)
		disguise_ttl = maxf(0.0, disguise_ttl - delta)
		if disguise_ttl <= 0.0:
			disguise_active = false
			disguise_changed.emit(disguise_integrity, disguise_active)
		if disguise_integrity <= 0.0:
			disguise_integrity = 0.0
			disguise_active = false
		disguise_changed.emit(disguise_integrity, disguise_active)

	# Light visibility probe
	if light_probe != null and light_probe.has_method("sample_visibility"):
		var excl: Array[RID] = [get_rid()]
		GameState.player_light_visibility = light_probe.sample_visibility(global_position, get_world_3d().direct_space_state, excl)


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


func take_damage(amount: float) -> void:
	if is_downed:
		return
	if disguise_active:
		disguise_active = false
		disguise_integrity = 0.0
		disguise_changed.emit(0.0, false)
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
			disguise_changed.emit(disguise_integrity, disguise_active)
			ability_cooldown = DISGUISE_COOLDOWN
		"moth":
			astral_active = true
			astral_ttl = ASTRAL_DURATION
			ability_cooldown = 12.0
			thief_vision = true
			thief_vision_on = true
			thief_vision_toggled.emit(true)
			_update_thief_vision()


func _tick_astral(delta: float) -> void:
	if not astral_active:
		return
	astral_ttl = maxf(0.0, astral_ttl - delta)
	if astral_ttl <= 0.0:
		_end_astral()


func _end_astral() -> void:
	if not astral_active and not thief_vision_on:
		return
	astral_active = false
	astral_ttl = 0.0
	thief_vision = false
	thief_vision_on = false
	thief_vision_toggled.emit(false)
	_update_thief_vision()


func _try_spider_grapple() -> bool:
	if not can_act():
		return false
	if ability_cooldown > 0.0:
		return is_grappling
	if cam == null:
		return false
	if int(charges.get("grapple", 0)) <= 0:
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_transform.basis.z
	var to: Vector3 = from + fwd * GRAPPLE_MAX_RANGE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_pos: Vector3 = hit["position"] as Vector3
	var hit_normal: Vector3 = Vector3.UP
	var normal_var: Variant = hit.get("normal", Vector3.UP)
	if normal_var is Vector3:
		hit_normal = normal_var
	# Anchor surface check: reject point-blank hooks, walkable floor below the
	# thief, and downward anchors (the zipwire only winches up/forward).
	if hit_pos.distance_to(global_position) < GRAPPLE_MIN_RANGE:
		return false
	if hit_normal.dot(Vector3.UP) > 0.7 and hit_pos.y < global_position.y + 2.0:
		return false
	if hit_pos.y < global_position.y - 0.5:
		return false
	grapple_target = hit_pos
	is_grappling = true
	grapple_time = 0.0
	charges["grapple"] = int(charges.get("grapple", 0)) - 1
	tool_used.emit("grapple", int(charges.get("grapple", 0)))
	_fp_set_tool("zipwire")
	_fp_play_swing()
	ability_cooldown = GameData.eval_curve("CT_Tool_Wire", "WireCooldownSecondary", 1.0, 5.0)
	VfxManager.spawn_grapple_beam(get_parent(), global_position + Vector3.UP * 1.2, grapple_target, 0.45)
	NoiseBus.emit_noise(global_position, 5.0, self, "wire")
	return true


func _use_slithersap() -> void:
	if not can_act():
		return
	if int(charges.get("slithersap", 0)) <= 0:
		return
	_fp_set_tool("slithersap")
	_fp_play_swing()
	charges["slithersap"] = int(charges.get("slithersap", 0)) - 1
	# Real behaviour: spawn the MagicSlime puddle (2.0 m radius, 30 s) at the
	# aim point; the puddle itself runs the 1.5 m / 30 s light inhibitor.
	# The cooked projectile stores no InitialSpeed, so no flight speed is
	# invented — the puddle appears at the raycast aim point (explosion
	# delay 0).
	var aim: Vector3 = _slithersap_aim_point()
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
	_fp_play_swing()
	charges["smoke_bomb"] = int(charges.get("smoke_bomb", 0)) - 1
	if level_ctrl != null and level_ctrl.has_method("spawn_smoke"):
		var ground: Vector3 = global_position + (-global_transform.basis.z) * 2.5
		level_ctrl.spawn_smoke(ground, 25.0)
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
		NoiseBus.emit_noise(mark.global_position, global_position.distance_to(mark.global_position) + 2.0, self, "pickpocket_spotted")
		tool_used.emit("pickpocket_fairy", PICKPOCKET_INFINITE_DISPLAY)
		return
	var dist: float = global_position.distance_to(mark.global_position)
	var travel: float = fairy_travel_time(dist)
	VfxManager.spawn_fairy_orb(get_parent(), global_position + Vector3.UP * 1.3, mark.global_position + Vector3.UP * 1.2, travel)
	NoiseBus.emit_noise(mark.global_position, 3.0, self, "fairy")
	get_tree().create_timer(travel).timeout.connect(_on_fairy_arrived.bind(mark))
	tool_used.emit("pickpocket_fairy", PICKPOCKET_INFINITE_DISPLAY)


## The fairy steals the nearest uncollected loot around the mark on arrival.
func _on_fairy_arrived(mark: Node) -> void:
	if not is_instance_valid(mark) or not (mark is Node3D):
		return
	var mark_pos: Vector3 = (mark as Node3D).global_position
	if pickpocket_is_blocked(mark as Node3D, global_position):
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


func _try_blackjack() -> void:
	if not can_act():
		return
	_fp_set_tool("blackjack")
	_fp_play_swing()
	if head != null and cam != null:
		var swing_dir: Vector3 = -cam.global_transform.basis.z
		var swing_pos: Vector3 = head.global_position + swing_dir * 0.7
		VfxManager.spawn_blackjack_swing(get_parent(), swing_pos, swing_dir)
	_play_blackjack_camera_punch()
	var base_dmg: float = GameData.eval_curve("CT_Tool_Blackjack", "BlackjackDamageLight", 1.0, BLACKJACK_LIGHT_DMG)
	var heavy_dmg: float = GameData.eval_curve("CT_Tool_Blackjack", "BlackjackDamageHeavy", 1.0, BLACKJACK_HEAVY_DMG)
	if heavy_dmg <= 0.0:
		heavy_dmg = base_dmg
	for g: Node in get_tree().get_nodes_in_group("guards"):
		if not (g is Node3D):
			continue
		var guard_node: Node3D = g as Node3D
		if global_position.distance_to(guard_node.global_position) > 2.4:
			continue
		if not g.has_method("take_knockout"):
			continue
		var final_dmg: float = heavy_dmg
		var guard_state: int = int(g.get("state"))
		if guard_state == 0 or guard_state == 1:
			var to_player: Vector3 = (global_position - guard_node.global_position).normalized()
			var guard_back: Vector3 = guard_node.global_transform.basis.z.normalized()
			var behind_dot: float = guard_back.dot(to_player)
			if behind_dot > 0.25:
				final_dmg = heavy_dmg
		g.take_knockout(final_dmg)
		GameState.takedowns += 1
		NoiseBus.emit_noise(global_position, 4.5, self, "takedown")
		return


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


func _process(delta: float) -> void:
	_update_first_person(delta)


func _build_first_person_rig() -> void:
	if cam == null:
		return
	if fp_rig != null and is_instance_valid(fp_rig):
		return
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


## Real 1P viewmodel (BP_Player_Thief_Spider.Mesh1P_UpperBody):
## SK_ThiefNisha__BodyUpper attached under the camera with the three
## retargeted 1P clips. Placement and scale are derived, not guessed:
## the Skeleton3D bind pose already carries the UE first-person framing in
## the `camera_position` joint (present in both the mesh and the anim
## skeletons), so the instanced root is counter-moved so that joint's global
## rest lands exactly on the holder origin (i.e. the camera). Identity scale
## is kept: the mesh is authored in meters (POSITION bounds span y 0.94-1.52
## and the imported skeleton rests read out in meters), while the animation
## side (authored in cm) is converted by the pelvis-rest unit factor in
## animation_library.gd. SK_ThiefNisha__BodyLower is intentionally omitted:
## it ships the same full skeleton (a second instance would need its own
## AnimationPlayer) and the legs sit below the FP camera frustum.
## Any failure returns false and the caller keeps the procedural fallback.
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
	# Skeleton-space -> holder-space chain (local only, no world dependency).
	var holder_from_skel := Transform3D.IDENTITY
	var cursor: Node = sk
	while cursor != null and cursor != holder:
		if cursor is Node3D:
			holder_from_skel = (cursor as Node3D).transform * holder_from_skel
		cursor = cursor.get_parent()
	var joint_in_holder: Transform3D = holder_from_skel * sk.get_bone_global_rest(cam_bone)
	inst3d.transform = joint_in_holder.affine_inverse() * inst3d.transform
	_fp_arm_holder = holder
	_fp_arm_skel = sk
	if not _setup_fp_anims():
		holder.queue_free()
		_fp_arm_skel = null
		_fp_arm_holder = null
		return false
	return true


## Retargets the three real 1P clips onto the 1P arm skeleton. Any failure
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


## Drives the real 1P clip state machine: crouch clip while crouching,
## sprint clip while sprinting, walk clip while moving, each crossfaded over
## FP_ANIM_BLEND (0.2 s). When stationary there is no 1P idle or jump clip
## in the install, so nothing is fabricated: the player stops and the
## skeleton holds its rest (bind) pose.
func _update_fp_anim_state() -> void:
	if not _fp_use_real_arms or fp_anim_player == null or _fp_anim_lib == null:
		return
	var key: String = ""
	if GameState.state == "playing" and _fp_arm_skel != null:
		var planar: float = Vector2(velocity.x, velocity.z).length()
		var moving: bool = is_on_floor() and planar > 0.5
		if moving:
			if is_crouching:
				key = String(_fp_anim_lib.clip_for_role("crouch"))
			elif is_sprinting:
				key = String(_fp_anim_lib.clip_for_role("sprint"))
			else:
				key = String(_fp_anim_lib.clip_for_role("walk"))
	_fp_play_fp_clip(key)


func _fp_play_fp_clip(clip_name: String) -> void:
	if fp_anim_player == null:
		return
	if clip_name == "":
		if _fp_current_clip != "":
			_fp_current_clip = ""
			fp_anim_player.stop()
			if _fp_arm_skel != null and is_instance_valid(_fp_arm_skel):
				_fp_arm_skel.reset_bone_poses()
		return
	if _fp_current_clip == clip_name and fp_anim_player.is_playing():
		return
	if not fp_anim_player.has_animation(clip_name):
		return
	_fp_current_clip = clip_name
	fp_anim_player.play(clip_name, FP_ANIM_BLEND)


## Small procedural swing offset for the bone-attached tool (local to the
## hand bone; the camera-space fallback path below is untouched).
func _update_fp_tool_on_bone(swing_k: float) -> void:
	if not _fp_tool_on_bone or fp_tool_root == null:
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
	if tool_id == "zipwire":
		var loaded: Node = _fp_try_load_zipwire()
		if loaded != null:
			fp_tool_root.add_child(loaded)
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


func _fp_try_load_zipwire() -> Node:
	var candidates: Array[String] = [
		"res://assets/ue/Content/Art/Tools/SM_Zipwire.glb",
		"res://assets/ue/Content/Art/Tools/Zipwire/SM_Zipwire.glb",
		"res://assets/ue/Content/Art/Tool/SM_Zipwire.glb",
		"res://assets/ue/Content/Art/Tools/SM_Zipwire.tscn",
	]
	for path: String in candidates:
		if not ResourceLoader.exists(path):
			continue
		var res: Resource = ResourceLoader.load(path)
		if res is PackedScene:
			var inst: Node = (res as PackedScene).instantiate()
			(inst as Node3D).scale = Vector3.ONE * 0.35
			return inst
	return null


func _fp_fallback_mat(base: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = base
	mat.roughness = 0.55
	mat.metallic = 0.25
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
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
	var frame_mat: StandardMaterial3D = _fp_fallback_mat(Color(0.16, 0.15, 0.14), Color(0, 0, 0), 0.0)
	var glow_mat: StandardMaterial3D = _fp_fallback_mat(Color(0.4, 0.85, 1.0), Color(0.35, 0.8, 1.0), 2.0)
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
	var vial_mat: StandardMaterial3D = StandardMaterial3D.new()
	vial_mat.albedo_color = Color(0.3, 0.9, 0.65, 0.85)
	vial_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vial_mat.emission_enabled = true
	vial_mat.emission = Color(0.3, 1.0, 0.7)
	vial_mat.emission_energy_multiplier = 1.5
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
	var glow_mat: StandardMaterial3D = _fp_fallback_mat(Color(0.55, 0.95, 1.0), Color(0.4, 0.9, 1.0), 2.5)
	var orb_mesh: SphereMesh = SphereMesh.new()
	orb_mesh.radius = 0.035
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


func _update_first_person(delta: float) -> void:
	if fp_rig == null or cam == null:
		return
	fp_breathe_time += delta
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
	for n: Node in get_tree().get_nodes_in_group("thief_vision_highlight"):
		if n.has_method("set_highlighted"):
			n.call("set_highlighted", thief_vision_on)
		elif n.has_method("set_highlight"):
			n.call("set_highlight", thief_vision_on)
