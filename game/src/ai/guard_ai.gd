extends CharacterBody3D
## Constabulary Guard AI: Neutral -> Suspicious -> Alerted -> Combat.
## Implements sight cone + light visibility scaling + smoke LOS blocking + NoiseBus hearing.

enum Alertness { NEUTRAL, SUSPICIOUS, ALERTED, COMBAT, SEARCH, KNOCKED_OUT }

const GuardAnimLib = preload("res://src/core/animation_library.gd")

# Real UE values (tools/parse_gameplay.py; sources in
# game/data/generated/gameplay/*.json "sources"). Curve-table overrides are kept
# only for rows the real data defines (GuardBaseHealth, GuardKnockoutDuration).
const PATROL_SPEED: float = 1.5 # DA_AIStatesToSpeed_Guard Neutral 150 cm/s
const SUSPICIOUS_SPEED: float = 1.7 # DA_AIStatesToSpeed_Guard Suspicious 170 cm/s
const ALERTED_SPEED: float = 2.5 # BP_Guard_Base TATCharacterAIMovement MaxWalkSpeed 250 cm/s
const SIGHT_RANGE: float = 20.0 # AIC_GuardBase Fresh SightRadius 2000cm
const LOSE_SIGHT_RANGE: float = 30.0 # Bouncer/Hauntstable Fresh LoseSightRadius 3000cm (GuardBase Fresh=2500, see report)
const HEARING_RANGE: float = 25.0 # AIC_GuardBase TATAISenseConfig_Hearing.HearingRange 2500cm
const FOV_DEG: float = 80.0 # PeripheralVisionAngleDegrees 40 (UE half-angle) x 2
const MELEE_DAMAGE: float = 10.0 # CT_Melee_RangedAttackDamage close key
const MELEE_COOLDOWN: float = 2.0 # GE_Melee_RangedAttack_Cooldown
const MELEE_RADIUS: float = 1.0 # GA_MeleeRangedAttack DamageRadius 100cm
# Real UE values (game/data/generated/gameplay/downed.json + CT_AIStats;
# fallbacks are the extracted numbers and apply only when sources are missing).
const DOWNED_PATH := "res://data/generated/gameplay/downed.json"
const REVIVE_HOLD_FALLBACK: float = 5.0 # GA_SyncedAbility_Revive InteractHoldDuration
const GUARD_REGEN_FALLBACK: float = 15.0 # CT_AIStats GuardBaseHealthRegenRate
const GUARD_MAX_HP_FALLBACK: float = 30.0 # CT_AIStats GuardBaseHealth
static var _downed_data: Dictionary = {}
# Detection ramps: time-to-detect(s) = agnostic * dist_m + critical_time;
# rate = 100/time. Crouch x0.75 applies at/over crouch_min (DA_DetectionSettings).
const DETECTION_RAMPS: Dictionary = {
	0: {"agnostic": 0.4, "critical_time": 0.0, "critical_range": 2.0, "crouch_min": 2.75, "crouch_mult": 0.75},
	1: {"agnostic": 0.4, "critical_time": 0.0, "critical_range": 2.0, "crouch_min": 2.75, "crouch_mult": 0.75},
	2: {"agnostic": 0.2, "critical_time": 0.0, "critical_range": 2.0, "crouch_min": 2.75, "crouch_mult": 0.75},
	3: {"agnostic": 0.2, "critical_time": 0.0, "critical_range": 2.0, "crouch_min": 2.0, "crouch_mult": 0.75},
}

@export var patrol_points: Array[Vector3] = []
@export var patrol_speed: float = PATROL_SPEED
@export var suspicious_speed: float = SUSPICIOUS_SPEED
@export var chase_speed: float = ALERTED_SPEED
@export var sight_range: float = SIGHT_RANGE
@export var lose_sight_range: float = LOSE_SIGHT_RANGE
@export var hearing_range: float = HEARING_RANGE
@export var fov_deg: float = FOV_DEG

var state: int = Alertness.NEUTRAL
var health: float = 30.0
var detection: float = 0.0 # 0..100
var ko_timer: float = 0.0
var wp_index: int = 0
var investigate_pos: Vector3 = Vector3.ZERO
var state_timer: float = 0.0
var attack_cooldown: float = 0.0
var _speed_scale: float = 1.0
var gravity: float = 18.0
var walk_phase: float = 0.0
var search_scan_phase: float = 0.0
var _ko_tween: Tween
var _search_goal: Vector3 = Vector3.ZERO
var _search_goal_timer: float = 0.0
var _revive_target: Node = null
var _revive_progress: float = 0.0
var _ally_scan_timer: float = 0.0
# Real-clip animation state (animation_library.gd). When _use_real_anims is
# false the guard falls back to the procedural bob in _update_procedural_anim.
var anim_player: AnimationPlayer
var _anim_lib: RefCounted
var _anim_weapon: String = "club"
var _use_real_anims: bool = false
var _attack_anim_lock: float = 0.0
var _slip_anim: bool = false

var visual_root: Node3D
var body_mesh: MeshInstance3D
var _highlight_mat: StandardMaterial3D
var alert_indicator: Label3D
var level_ctrl: Node


func _ready() -> void:
	add_to_group("guards")
	add_to_group("thief_vision_highlight")
	collision_layer = 4
	collision_mask = 1 | 2
	var diff_x := GameState.difficulty_curve_x()
	health = _guard_max_hp()
	_speed_scale = lerpf(0.85, 1.2, (diff_x - 1.0) * 0.5)
	patrol_speed *= _speed_scale
	suspicious_speed *= _speed_scale
	sight_range *= lerpf(0.85, 1.25, (diff_x - 1.0) * 0.5)
	_build_visuals()
	NoiseBus.noise_emitted.connect(_on_noise_emitted)
	if patrol_points.is_empty():
		patrol_points = [global_position, global_position + Vector3(6, 0, 0), global_position + Vector3(6, 0, 6)]


func _build_visuals() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 2.36
	col.shape = cap
	col.position = Vector3(0, 1.18, 0)
	add_child(col)

	visual_root = Node3D.new()
	add_child(visual_root)

	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.albedo_color = Color(0.95, 0.2, 0.2, 0.45)
	_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.emission_enabled = true
	_highlight_mat.emission = Color(0.95, 0.2, 0.2)
	_highlight_mat.emission_energy_multiplier = 1.6
	# Thief Vision silhouette reads through walls (x-ray overlay) for all thieves.
	_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_mat.no_depth_test = true
	_highlight_mat.render_priority = 1

	var glb_path: String = _resolve_guard_glb_path()
	var packed := ResourceLoader.load(glb_path) as PackedScene
	if packed != null:
		var inst := packed.instantiate()
		inst.rotation_degrees.y = 180.0
		visual_root.add_child(inst)
	else:
		body_mesh = MeshInstance3D.new()
		var m := CapsuleMesh.new()
		m.radius = 0.45
		m.height = 2.36
		body_mesh.mesh = m
		body_mesh.position = Vector3(0, 1.18, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.14, 0.19, 0.36)
		body_mesh.material_override = mat
		visual_root.add_child(body_mesh)

	alert_indicator = Label3D.new()
	alert_indicator.position = Vector3(0, 2.56, 0)
	alert_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert_indicator.font_size = 48
	alert_indicator.text = ""
	add_child(alert_indicator)
	_setup_guard_anims()


## Builds the real-clip AnimationPlayer on visual_root. Guarded: any failure
## (missing manifest, unreadable GLB, zero shared bones) leaves anim_player
## null and the procedural fallback in charge.
func _guard_weapon_set() -> String:
	var lname: String = name.to_lower()
	if lname.find("haunt") >= 0:
		return "hauntstable"
	return "club"


func _setup_guard_anims() -> void:
	_use_real_anims = false
	anim_player = null
	_anim_lib = null
	if visual_root == null:
		return
	var skels := visual_root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	if sk == null or sk.get_bone_count() == 0:
		return
	_anim_weapon = _guard_weapon_set()
	var lib = GuardAnimLib.new()
	if not lib.setup(_anim_weapon, sk):
		return
	var skel_parent := sk.get_parent()
	if skel_parent == null:
		return
	var player := lib.build_player(sk, skel_parent, visual_root)
	if player == null or lib.applied_clip_count() < 4:
		return
	_anim_lib = lib
	anim_player = player
	_use_real_anims = true
	anim_player.animation_finished.connect(_on_guard_anim_finished)


func _anim_can_play() -> bool:
	return _use_real_anims and is_instance_valid(anim_player) and anim_player.is_inside_tree() and not is_queued_for_deletion() and _anim_lib != null


func _play_guard_clip(role: String, force: bool = false) -> void:
	if not _anim_can_play():
		return
	var key := String(_anim_lib.clip_for_role(role))
	if key == "" or not anim_player.has_animation(key):
		return
	if not force and anim_player.current_animation == key:
		return
	anim_player.play(key, 0.25)


func _play_guard_attack() -> void:
	if not _anim_can_play():
		return
	var key := String(_anim_lib.clip_for_role("attack"))
	if key == "" or not anim_player.has_animation(key):
		return
	_attack_anim_lock = maxf(0.5, _anim_lib.clip_length(key))
	_slip_anim = false
	anim_player.play(key, 0.15)


## Plays the MagicSlime slip montage once, then falls through to the prone
## knockdown loop. Called by the tool wave; forces KO visuals if needed.
func play_slip() -> void:
	if state != Alertness.KNOCKED_OUT:
		knock_out()
	if not _anim_can_play():
		return
	var key := String(_anim_lib.clip_for_role("slip"))
	if key == "" or not anim_player.has_animation(key):
		return
	_slip_anim = true
	_attack_anim_lock = 0.0
	anim_player.play(key, 0.2)


func _on_guard_anim_finished(anim_name: StringName) -> void:
	if not _anim_can_play():
		_slip_anim = false
		_attack_anim_lock = 0.0
		return
	if _slip_anim:
		_slip_anim = false
		if state == Alertness.KNOCKED_OUT:
			_play_guard_clip("knockdown", true)
		return
	var attack_key := String(_anim_lib.clip_for_role("attack"))
	if attack_key != "" and String(anim_name) == attack_key:
		_attack_anim_lock = 0.0


## Drives the real-clip state machine; falls back to procedural bob when no
## clips are available. Never plays while KO handling owns the player.
func _update_guard_anim(delta: float) -> void:
	if not _use_real_anims or not _anim_can_play():
		_update_procedural_anim(delta)
		return
	if _slip_anim:
		return
	if state == Alertness.KNOCKED_OUT:
		_play_guard_clip("knockdown")
		return
	_attack_anim_lock = maxf(0.0, _attack_anim_lock - delta)
	if _attack_anim_lock > 0.0:
		return
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.5
	match state:
		Alertness.NEUTRAL:
			_play_guard_clip("neutral_walk" if moving else "neutral_idle")
		Alertness.SUSPICIOUS:
			_play_guard_clip("suspicious_walk" if moving else "suspicious_idle")
		Alertness.ALERTED:
			_play_guard_clip("alert_run" if moving else "alert_idle")
		Alertness.COMBAT:
			_play_guard_clip("alert_run" if moving else "alert_idle")
		Alertness.SEARCH:
			_play_guard_clip("search")


func _resolve_guard_glb_path() -> String:
	var lname: String = name.to_lower()
	if lname.find("haunt") >= 0:
		return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Hauntstable/SK_Hauntstable__Body.glb"
	if lname.find("security") >= 0:
		return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Security/SK_GuardSecurity_01__Body.glb"
	if lname.find("enforcer") >= 0:
		return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/SK_GuardEnforcer__Preview.glb"
	match GameState.difficulty:
		GameState.Difficulty.MASTER_THIEF:
			return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Hauntstable/SK_Hauntstable__Body.glb"
		GameState.Difficulty.THIEF:
			if absi(get_index()) % 3 == 2:
				return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Security/SK_GuardSecurity_01__Body.glb"
			return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/SK_GuardEnforcer__Preview.glb"
		_:
			if absi(get_index()) % 3 == 2:
				return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/SK_GuardEnforcer__Preview.glb"
			return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Security/SK_GuardSecurity_01__Body.glb"


## Real CT_AIStats values (GuardBaseHealth 30, GuardBaseHealthRegenRate 15/s);
## eval_curve fallbacks repeat the extracted numbers for missing tables.
func _guard_max_hp() -> float:
	return GameData.eval_curve("CT_AIStats", "GuardBaseHealth", GameState.difficulty_curve_x(), GUARD_MAX_HP_FALLBACK)


func _guard_regen_rate() -> float:
	return GameData.eval_curve("CT_AIStats", "GuardBaseHealthRegenRate", GameState.difficulty_curve_x(), GUARD_REGEN_FALLBACK)


## Ally-revive hold (GA_SyncedAbility_Revive InteractHoldDuration 5.0 s);
## falls back to 5.0 when downed.json is unreadable.
static func revive_hold_s() -> float:
	if _downed_data.is_empty() and FileAccess.file_exists(DOWNED_PATH):
		var f: FileAccess = FileAccess.open(DOWNED_PATH, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				_downed_data = data
	return float(_downed_data.get("revive_hold_s", REVIVE_HOLD_FALLBACK))


## Health regen while conscious: +regen_rate/s up to the real max.
func _tick_regen(delta: float) -> void:
	if state == Alertness.KNOCKED_OUT:
		return
	var cap: float = _guard_max_hp()
	if health < cap:
		health = minf(cap, health + _guard_regen_rate() * delta)


func _enter_alerted() -> void:
	if state == Alertness.ALERTED or state == Alertness.COMBAT:
		return
	state = Alertness.ALERTED
	NoiseBus.emit_noise(global_position, 14.0, self, "guard_alert")


func _enter_combat() -> void:
	if state == Alertness.COMBAT:
		return
	state = Alertness.COMBAT
	NoiseBus.emit_noise(global_position, 12.0, self, "guard_alert")


func _ramp_for_state() -> Dictionary:
	match state:
		Alertness.NEUTRAL:
			return DETECTION_RAMPS[0]
		Alertness.SUSPICIOUS, Alertness.SEARCH:
			return DETECTION_RAMPS[1]
		Alertness.ALERTED:
			return DETECTION_RAMPS[2]
		_:
			return DETECTION_RAMPS[3]


## Real UE detection rate (detections/sec) at a distance for the current
## alertness: 100 / (agnostic * dist_m + critical_time), with the crouch
## multiplier applied only at/over CrouchSettings.MinimumDistance.
## Returns INF inside critical range (instant spot).
func get_detection_rate(dist_m: float, crouching: bool) -> float:
	var ramp: Dictionary = _ramp_for_state()
	var time_s: float = float(ramp.get("agnostic", 0.4)) * dist_m + float(ramp.get("critical_time", 0.0))
	if dist_m <= float(ramp.get("critical_range", 2.0)) or time_s <= 0.0:
		return INF
	var rate: float = 100.0 / time_s
	if crouching and dist_m >= float(ramp.get("crouch_min", 2.75)):
		rate *= float(ramp.get("crouch_mult", 0.75))
	return rate


## Real movement speed (m/s) for the current alertness state.
func get_state_speed() -> float:
	match state:
		Alertness.NEUTRAL:
			return patrol_speed
		Alertness.SUSPICIOUS:
			return suspicious_speed
		Alertness.ALERTED:
			return ALERTED_SPEED * _speed_scale
		Alertness.SEARCH:
			return patrol_speed * 1.15
		Alertness.COMBAT:
			return chase_speed
		_:
			return 0.0


func _physics_process(delta: float) -> void:
	if GameState.state != "playing":
		return
	if state == Alertness.KNOCKED_OUT:
		ko_timer -= delta
		if ko_timer <= 0.0:
			_recover_from_ko()
		else:
			_update_guard_anim(delta)
		return

	_tick_regen(delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player") as CharacterBody3D
	var sees_player: bool = _can_see_player(player)

	if sees_player:
		# Real UE ramp (DA_DetectionSettings): time-to-detect(s) = agnostic *
		# dist_m + critical_time; rate = 100/time; crouch x0.75 at/over 2.75m.
		# Light-visibility multiplier, smoke/LOS checks and the 15/45/100 state
		# thresholds below are retained (no UE source for them).
		var vis_mult: float = clampf(0.35 + GameState.player_light_visibility * 1.15, 0.35, 1.5)
		var dist_m: float = player.global_position.distance_to(global_position)
		var rate: float = get_detection_rate(dist_m, bool(player.get("is_crouching")))
		if is_inf(rate):
			detection = 100.0
		else:
			detection = minf(100.0, detection + rate * vis_mult * delta)
		investigate_pos = player.global_position
		if detection >= 100.0:
			_enter_combat()
			GameState.ever_spotted = true
			GameState.ever_chased = true
		elif detection >= 45.0 and state < Alertness.ALERTED:
			_enter_alerted()
			state_timer = 6.0
			GameState.ever_spotted = true
		elif detection >= 15.0 and state == Alertness.NEUTRAL:
			state = Alertness.SUSPICIOUS
			state_timer = 5.0
	else:
		detection = maxf(0.0, detection - 22.0 * delta)
		if state == Alertness.COMBAT and detection <= 35.0:
			state = Alertness.ALERTED
			state_timer = 6.0
		elif state == Alertness.ALERTED:
			state_timer -= delta
			if state_timer <= 0.0:
				state = Alertness.SEARCH
				state_timer = 6.0
		elif state == Alertness.SUSPICIOUS and detection <= 0.0:
			state = Alertness.SEARCH
			state_timer = 4.0
		elif state == Alertness.SEARCH:
			state_timer -= delta
			if state_timer <= 0.0:
				state = Alertness.NEUTRAL

	_update_indicator()
	_update_ally_wakeup(delta)
	_move_ai(delta, player)
	_update_guard_anim(delta)


func _move_ai(delta: float, player: CharacterBody3D) -> void:
	var target: Vector3 = global_position
	var spd: float = patrol_speed
	match state:
		Alertness.NEUTRAL:
			target = patrol_points[wp_index]
			if global_position.distance_to(target) < 1.0:
				wp_index = (wp_index + 1) % patrol_points.size()
		Alertness.SUSPICIOUS:
			target = investigate_pos
			spd = suspicious_speed
		Alertness.ALERTED:
			target = investigate_pos
			spd = ALERTED_SPEED * _speed_scale
		Alertness.SEARCH:
			# Fan out around the last known position instead of freezing on it.
			_search_goal_timer -= delta
			if _search_goal_timer <= 0.0 or _search_goal == Vector3.ZERO or global_position.distance_to(_search_goal) < 1.2:
				var ang: float = fmod(search_scan_phase * 2.3 + float(get_instance_id() % 29), TAU)
				_search_goal = investigate_pos + Vector3(cos(ang) * 4.0, 0.0, sin(ang) * 4.0)
				_search_goal_timer = 2.5
			target = _search_goal
			spd = patrol_speed * 1.15 # retained search-hustle factor on the real Neutral base
		Alertness.COMBAT:
			if player != null:
				target = player.global_position
				spd = chase_speed
				if global_position.distance_to(player.global_position) <= MELEE_RADIUS and attack_cooldown <= 0.0:
					if player.has_method("take_damage"):
						player.take_damage(MELEE_DAMAGE)
					_play_guard_attack()
					attack_cooldown = MELEE_COOLDOWN

	var flat: Vector3 = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if flat.length() > 0.25:
		var dir: Vector3 = flat.normalized()
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


func _can_see_player(player: CharacterBody3D) -> bool:
	if player == null:
		return false
	# The Moth's astral form is a spirit: guards cannot see or hear it.
	if bool(player.get("astral_active")):
		return false
	var dist_to_player: float = global_position.distance_to(player.global_position)
	if bool(player.get("disguise_active")):
		# Chameleon disguise edge cases: alerted/searching guards and tattered
		# disguises no longer pass inspection at range; close range is always risky.
		var guard_alerted: bool = state == Alertness.ALERTED or state == Alertness.COMBAT or state == Alertness.SEARCH
		var integrity: float = float(player.get("disguise_integrity"))
		if not guard_alerted and integrity >= 35.0 and dist_to_player > 3.5:
			return false
	# Retention: once sensed, the guard holds the target out to lose_sight_range.
	var sensed: bool = detection > 0.0 or state != Alertness.NEUTRAL
	var effective_range: float = lose_sight_range if sensed else sight_range
	var to_player: Vector3 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist > effective_range or dist < 0.1:
		return false
	var fwd: Vector3 = -global_transform.basis.z
	var angle: float = rad_to_deg(fwd.angle_to(to_player.normalized()))
	if angle > fov_deg * 0.5 and dist > 3.5:
		return false
	# Smoke bomb LOS check
	if level_ctrl != null and level_ctrl.has_method("is_blocked_by_smoke"):
		if level_ctrl.is_blocked_by_smoke(global_position + Vector3.UP * 1.5, player.global_position + Vector3.UP * 1.0):
			return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, player.global_position + Vector3.UP * 1.0, 1, [get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	return hit.is_empty()


func _on_noise_emitted(origin: Vector3, loudness: float, source: Node, tag: String) -> void:
	if state == Alertness.KNOCKED_OUT or source == self:
		return
	# Only the player thief carries astral_active (guards have no such
	# property, so bool() must not be called on their lookup): the Moth's
	# astral form makes no noise.
	if source != null and source.is_in_group("player") and bool(source.get("astral_active")):
		return
	if tag == "guard_alert":
		if global_position.distance_to(origin) <= loudness:
			investigate_pos = origin
			detection = maxf(detection, 60.0)
			if state != Alertness.ALERTED and state != Alertness.COMBAT:
				_enter_alerted()
				state_timer = 6.0
		return
	if global_position.distance_to(origin) <= loudness:
		investigate_pos = origin
		if state < Alertness.SUSPICIOUS:
			state = Alertness.SUSPICIOUS
			state_timer = 5.0
		detection = maxf(detection, 25.0)


func take_knockout(dmg: float) -> void:
	health -= dmg
	if health <= 0.0:
		knock_out()


func apply_damage(dmg: float) -> void:
	take_knockout(dmg)


func knock_out(duration_override: float = -1.0) -> void:
	if state == Alertness.KNOCKED_OUT:
		return
	state = Alertness.KNOCKED_OUT
	if duration_override > 0.0:
		ko_timer = duration_override
	else:
		ko_timer = GameData.eval_curve("CT_AIStats", "GuardKnockoutDuration", GameState.difficulty_curve_x(), 180.0)
	alert_indicator.text = "ZZZ"
	_slip_anim = false
	_attack_anim_lock = 0.0
	if visual_root == null:
		return
	if _use_real_anims and _anim_can_play():
		var ko_key := String(_anim_lib.clip_for_role("knockdown"))
		if ko_key != "" and anim_player.has_animation(ko_key):
			anim_player.play(ko_key, 0.25)
			return
	if _ko_tween != null and _ko_tween.is_valid():
		_ko_tween.kill()
	_ko_tween = create_tween()
	_ko_tween.set_parallel(true)
	_ko_tween.tween_property(visual_root, "rotation_degrees:x", 90.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_ko_tween.tween_property(visual_root, "position:y", 0.25, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func wake_up_from_ko() -> void:
	if state != Alertness.KNOCKED_OUT:
		return
	ko_timer = 0.0
	_recover_from_ko()


func _recover_from_ko() -> void:
	health = _guard_max_hp()
	alert_indicator.text = ""
	state = Alertness.SEARCH
	state_timer = 6.0
	investigate_pos = global_position
	if visual_root == null:
		return
	if _use_real_anims and _anim_can_play():
		# The real search clip owns the next frames; no tip-over tween.
		_slip_anim = false
		_play_guard_clip("search", true)
		return
	if _ko_tween != null and _ko_tween.is_valid():
		_ko_tween.kill()
	_ko_tween = create_tween()
	_ko_tween.set_parallel(true)
	_ko_tween.tween_property(visual_root, "rotation_degrees:x", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ko_tween.tween_property(visual_root, "position:y", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _update_ally_wakeup(delta: float) -> void:
	if state != Alertness.NEUTRAL and state != Alertness.SUSPICIOUS and state != Alertness.SEARCH:
		return
	_ally_scan_timer -= delta
	if _ally_scan_timer > 0.0:
		return
	_ally_scan_timer = 0.4
	var revived: bool = false
	var guards: Array[Node] = get_tree().get_nodes_in_group("guards")
	for g in guards:
		if g == self:
			continue
		if not (g is Node3D):
			continue
		var other: Node3D = g as Node3D
		var other_pos: Vector3 = other.global_position
		if global_position.distance_to(other_pos) > 6.0:
			continue
		var state_var: Variant = g.get("state")
		if state_var == null:
			continue
		var ally_state: int = int(state_var)
		if ally_state != Alertness.KNOCKED_OUT:
			continue
		investigate_pos = other_pos
		if global_position.distance_to(other_pos) <= 1.8:
			# Reviving an ally takes a sustained hold over them (real
			# GA_SyncedAbility_Revive InteractHoldDuration 5.0 s).
			if _revive_target != g:
				_revive_target = g
				_revive_progress = 0.0
			_revive_progress += 0.4
			if _revive_progress >= revive_hold_s():
				_revive_target = null
				_revive_progress = 0.0
				g.set("ko_timer", 0.0)
				if g.has_method("wake_up_from_ko"):
					g.call("wake_up_from_ko")
				state = Alertness.SEARCH
				state_timer = 6.0
				detection = maxf(detection, 40.0)
				NoiseBus.emit_noise(global_position, 10.0, self, "guard_alert")
				revived = true
		else:
			if state == Alertness.NEUTRAL:
				state = Alertness.SUSPICIOUS
				state_timer = 5.0
		break
	if not revived and _revive_target != null:
		var still_close: bool = false
		if is_instance_valid(_revive_target) and _revive_target is Node3D:
			still_close = global_position.distance_to((_revive_target as Node3D).global_position) <= 2.0
		if not still_close:
			_revive_target = null
			_revive_progress = 0.0


func _update_procedural_anim(delta: float) -> void:
	if visual_root == null:
		return
	if state == Alertness.KNOCKED_OUT:
		return
	if state == Alertness.SEARCH:
		search_scan_phase += delta * 1.6
		var pan: float = sin(search_scan_phase) * 35.0
		var rot: Vector3 = visual_root.rotation_degrees
		rot.y = pan
		visual_root.rotation_degrees = rot
		var planar: float = Vector2(velocity.x, velocity.z).length()
		if planar > 0.5:
			walk_phase += delta * planar * 2.2
			var pos: Vector3 = visual_root.position
			pos.y = abs(sin(walk_phase)) * 0.05
			visual_root.position = pos
		return
	if state == Alertness.NEUTRAL or state == Alertness.SUSPICIOUS or state == Alertness.ALERTED or state == Alertness.COMBAT:
		var speed: float = Vector2(velocity.x, velocity.z).length()
		if speed > 0.5:
			walk_phase += delta * speed * 2.2
			var bob: float = abs(sin(walk_phase)) * 0.05
			var sway: float = sin(walk_phase) * 3.0
			var p: Vector3 = visual_root.position
			p.y = bob
			visual_root.position = p
			var r: Vector3 = visual_root.rotation_degrees
			r.y = sway
			r.x = 0.0
			visual_root.rotation_degrees = r
		else:
			var p0: Vector3 = visual_root.position
			p0.y = lerpf(p0.y, 0.0, minf(1.0, delta * 8.0))
			visual_root.position = p0
			if state != Alertness.SEARCH:
				var r0: Vector3 = visual_root.rotation_degrees
				r0.y = lerpf(r0.y, 0.0, minf(1.0, delta * 6.0))
				visual_root.rotation_degrees = r0


func set_highlighted(on: bool) -> void:
	if visual_root == null:
		return
	_apply_highlight_recursive(visual_root, _highlight_mat if on else null)


func _apply_highlight_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = mat
	for c in node.get_children():
		_apply_highlight_recursive(c, mat)


func _update_indicator() -> void:
	match state:
		Alertness.NEUTRAL: alert_indicator.text = ""
		Alertness.SUSPICIOUS:
			alert_indicator.text = "?"
			alert_indicator.modulate = Color(1.0, 0.85, 0.2)
		Alertness.ALERTED:
			alert_indicator.text = "!"
			alert_indicator.modulate = Color(1.0, 0.45, 0.1)
		Alertness.COMBAT:
			alert_indicator.text = "!!"
			alert_indicator.modulate = Color(1.0, 0.15, 0.15)
		Alertness.SEARCH:
			alert_indicator.text = "?"
			alert_indicator.modulate = Color(1.0, 0.6, 0.1)
		Alertness.KNOCKED_OUT:
			alert_indicator.text = "ZZZ"
