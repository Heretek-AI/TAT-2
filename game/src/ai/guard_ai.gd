extends CharacterBody3D
## Constabulary Guard AI: Neutral -> Suspicious -> Alerted -> Combat.
## Implements sight cone + light visibility scaling + smoke LOS blocking + NoiseBus hearing.

enum Alertness { NEUTRAL, SUSPICIOUS, ALERTED, COMBAT, SEARCH, KNOCKED_OUT }

signal alert_state_changed(state_info: Dictionary)
signal carried_item_stolen(item: Dictionary)

const GuardAnimLib = preload("res://src/core/animation_library.gd")
const LightProbeScript = preload("res://src/stealth/light_probe.gd")
const LANTERN_GLB_PRIMARY := "res://assets/ue/Content/Art/Environment/Lights/Mobile/SM_LanternGuardA.glb"
const LANTERN_GLB_FALLBACK := "res://assets/ue/Content/Art/Gameplay/Gear/Lantern/SK_Lantern.glb"
const DEFAULT_KEY_GLB := "res://assets/ue/Content/Art/Gameplay/KeyCabinets/SM_LootableKeys_LockedRoomKey.glb"
const VIEWCONE_DISGUISE_RANGE_M: float = 10.0
const VIEWCONE_DISGUISE_HALF_DEG: float = 65.0

# Real UE values (tools/parse_gameplay.py; sources in
# game/data/generated/gameplay/*.json "sources"). Curve-table overrides are kept
# only for rows the real data defines (GuardBaseHealth, GuardKnockoutDuration).
const PATROL_SPEED: float = 1.5 # DA_AIStatesToSpeed_Guard Neutral 150 cm/s
const SUSPICIOUS_SPEED: float = 1.7 # DA_AIStatesToSpeed_Guard Suspicious 170 cm/s
const ALERTED_SPEED: float = 2.5 # BP_Guard_Base TATCharacterAIMovement MaxWalkSpeed 250 cm/s
## Authored in-place ground speed per locomotion clip (root-motion audit in
## docs/reports/guard-animations.md). Playback is scaled by scripted speed /
## clip speed so the feet plant instead of sliding.
const CLIP_GROUND_SPEED: Dictionary = {
	"neutral_walk": 1.24,
	"suspicious_walk": 2.5,
	"alert_run": 7.6,
}
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

# Authored detection decay timing. game/data/generated/gameplay/detection.json
# `decay` rows 30-34 (fields rows 31-33) is parsed from
# extracted/json/AI/Data/DA_DetectionSettings.json DetectionSettings.DecaySettings
# rows 130-134:
# - min_seconds_in_level_before_decay 6.0
#   = MinSecondsInCurrentDetectionLevelBeforeDecay (row 131): gate, the guard
#     must spend 6 s in the current alertness level before the meter may decay.
# - min_seconds_since_visible_before_decay 4.0
#   = MinSecondsSinceVisibleBeforeDecay (row 132): gate, the guard must go 4 s
#     without seeing the player before the meter may decay.
# - detection_decay_seconds 7.0
#   = DetectionDecaySeconds (row 133): authored base duration for the 0..100
#     meter. SEARCH has no authored DA_AlertnessSettings row (it is Godot-only),
#     so its fallback duration is DetectionDecaySeconds 7.0. That reuse is an
#     inference from the data, not decompiled behaviour.
const DECAY_MIN_SECONDS_IN_LEVEL: float = 6.0
const DECAY_MIN_SECONDS_SINCE_VISIBLE: float = 4.0
const DECAY_BASE_SECONDS: float = 7.0
# extracted/json/AI/Alertness/DA_AlertnessSettings.json
# Properties.DecaySettings.DecayTimeSeconds rows 26-43: the per-state duration
# over which the 0..100 detection meter empties once both gates above are met.
# Neutral 1.0 (row 29), Suspicious 5.0 (row 33), Alerted 10.0 (row 37),
# Combat 10.0 (row 41). SEARCH falls back to DECAY_BASE_SECONDS.
const DECAY_SECONDS_BY_STATE: Dictionary = {
	Alertness.NEUTRAL: 1.0,
	Alertness.SUSPICIOUS: 5.0,
	Alertness.ALERTED: 10.0,
	Alertness.COMBAT: 10.0,
}
# Retained Godot state thresholds (no UE source; docs/reports/gameplay-constants.md
# records "15/45/100 state thresholds"). The upward ramp branches and the
# downward-transition clamp below both read these constants, so the numbers have
# one source.
const DETECTION_SUSPICIOUS_AT: float = 15.0
const DETECTION_ALERTED_AT: float = 45.0
const DETECTION_COMBAT_AT: float = 100.0
# Alertness order used to detect a DOWNWARD transition. The enum's declaration
# order puts SEARCH after COMBAT, so it cannot be used directly: SEARCH sits
# above SUSPICIOUS and below ALERTED for detection purposes.
const ALERTNESS_RANK: Dictionary = {
	Alertness.NEUTRAL: 0,
	Alertness.SUSPICIOUS: 1,
	Alertness.SEARCH: 2,
	Alertness.ALERTED: 3,
	Alertness.COMBAT: 4,
}
# Detection ceiling applied when a guard drops into a state, so stale detection
# cannot carry across. NEUTRAL has no threshold of its own; it reuses the 15
# value below which the guard stays Neutral and at/above which it becomes
# Suspicious. SEARCH is absent on purpose: it is Godot-only with no authored row
# and no retained threshold, so it decays unconditionally instead (see
# decay_step_detection).
const DETECTION_ENTRY_CEILING: Dictionary = {
	Alertness.NEUTRAL: DETECTION_SUSPICIOUS_AT,
	Alertness.SUSPICIOUS: DETECTION_SUSPICIOUS_AT,
	Alertness.ALERTED: DETECTION_ALERTED_AT,
	Alertness.COMBAT: DETECTION_COMBAT_AT,
}
# game/data/generated/gameplay/detection.json
# tag_ramp_modifiers["Status.Sprinting"] rows 54-59 (values rows 55-58, all
# 8.0), parsed from DA_DetectionSettings.GameplayTagRampModifiers rows 105-115.
const SPRINT_RAMP_MULTIPLIER: float = 8.0
# extracted/json/AI/Alertness/Curve_AI_HeightDifferenceToStrengthMultiplier.json
# FloatCurve.Keys rows 10-33: (2.0 m -> 1.0) RCIM_Constant rows 15-16,
# (3.0 m -> 0.0) RCIM_Linear rows 26-27. DA_DetectionSettings wires this curve
# only on the Neutral ramp
# (RampSettings[0].Value.HeightDifferenceToStrengthMultiplierCurve rows 18-21);
# the Suspicious/Alerted/Combat ramps author null (rows 35/49/63).
const HEIGHT_STRENGTH_ZERO_M: float = 3.0

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
var _seconds_in_state: float = 0.0
var _seconds_since_visible: float = 0.0
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
var _takedown_vic_anim: bool = false

var visual_root: Node3D
var body_mesh: MeshInstance3D
var _highlight_mat: StandardMaterial3D
var alert_indicator: Label3D
var level_ctrl: Node

@export var carries_lantern: bool = false
var carried_item: Dictionary = {}
var lantern_root: Node3D = null
var lantern_light: OmniLight3D = null
var _carried_node: Node3D = null
var _last_emitted_suspicion: float = -1.0

# Authored guard materials (F11 ground truth). mesh_materials.json keys are UE
# paths without extension; materials.json keys are UE material paths. Coverage
# (task-3.md, extended task-7.md): SK_Hauntstable__Body 2/2 + SK_Hauntstable__Head
# 3/3 via head sub-skeleton attach, SK_GuardSecurity_01_Body 5/5 headed (path
# swap from the headless __Body torso), SK_GuardEnforcer__Preview 8 slots
# (slots 0-2 empty upstream -> authored eye rescue below; slots 3-7 covered).
# Only a genuinely missing bind falls back to the retained navy uniform below
# with the UE path logged; never white.
const GUARD_NAVY: Color = Color(0.14, 0.19, 0.36)
## Eye-material rescue (task-7). The Preview GLB carries generic eye material
## names (Cornea/Eyes/Overlay) for slots 0-2, which are empty upstream; a raw
## substring match would misroute the "Eyes" surface onto the HelmetEyes slot
## ("helmeteyes".find("eyes")). Exact-match rescue binds the authored eye
## materials instead. All three rescue paths are covered in materials.json with
## albedo textures on disk (see task-7.md).
const GUARD_EYE_RESCUE := {
	"cornea": "/Game/MaterialLibrary/Character/EyeLibrary/MI_Eye_Cornea",
	"eyes": "/Game/MaterialLibrary/Character/EyeLibrary/MI_Eye_Base_Brown",
	"overlay": "/Game/MaterialLibrary/Character/EyeLibrary/MI_Eye_Overlay",
}
## Preview slot-index eye rescue (task-7). When the import leaves surface names
## empty, slots 0-2 fall through to slot-index fallback; map those indices to
## the authored eye materials instead of navy (same three paths as above).
const GUARD_PREVIEW_EYE_BY_SLOT := [
	"/Game/MaterialLibrary/Character/EyeLibrary/MI_Eye_Cornea",
	"/Game/MaterialLibrary/Character/EyeLibrary/MI_Eye_Base_Brown",
	"/Game/MaterialLibrary/Character/EyeLibrary/MI_Eye_Overlay",
]
## Head-GLB attach map (task-7): body-only SK res path -> headed SK res path.
## SK_Hauntstable__Body.glb carries torso only (2 prims); its head geometry
## lives in SK_Hauntstable__Head.glb (3 prims, 97 joints in identical name+order
## to the body — verified by GLB JSON dump in task-7.md). Security needs no
## entry: SK_GuardSecurity_01_Body is the skeleton-identical headed variant, so
## the path swap in _resolve_guard_glb_path covers it with no extra instance.
const GUARD_HEAD_GLB := {
	"res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Hauntstable/SK_Hauntstable__Body.glb": "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Hauntstable/SK_Hauntstable__Head.glb",
}
var _guard_mats_db: Dictionary = {}
var _guard_mats_lower: Dictionary = {}
var _guard_mesh_mats: Dictionary = {}
var _guard_mesh_lower: Dictionary = {}
var _guard_tex_cache: Dictionary = {}
var _guard_std_cache: Dictionary = {}


func _ready() -> void:
	add_to_group("guards")
	add_to_group("thief_vision_highlight")
	collision_layer = 4
	collision_mask = 1 | 2
	if name.to_lower().find("lantern") >= 0:
		carries_lantern = true
	var diff_x := GameState.difficulty_curve_x()
	health = _guard_max_hp()
	_speed_scale = lerpf(0.85, 1.2, (diff_x - 1.0) * 0.5)
	patrol_speed *= _speed_scale
	suspicious_speed *= _speed_scale
	sight_range *= lerpf(0.85, 1.25, (diff_x - 1.0) * 0.5)
	_build_visuals()
	if carries_lantern:
		_build_lantern()
	if not carried_item.is_empty():
		_rebuild_carried_visual()
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
		# F11/task-7: bind the authored slot materials. Untextured GLB imports
		# render white; every missing bind below resolves to logged navy, never
		# white. Body-only SKs then get their extracted head sub-skeleton.
		_bind_guard_glb_materials(inst)
		_attach_guard_head(inst, glb_path)
	else:
		# Retained navy capsule fallback (compare civilian rest-pose + bob:
		# missing art holds a readable pose, never white). Unexpected: all 3
		# task-3.md SK GLBs ship, so log the missing GLB path.
		push_warning("[guard_ai] guard GLB missing, navy capsule fallback (never white): " + glb_path)
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


## UE weapon-set mapping (F12 ground truth): "hauntstable" -> HA_CLIPS
## (AnimSet_Guard_Hauntsable + DAM_CharacterAnimationMapping_GuardHauntsable);
## every other guard (club / ClubLantern / Security bodies) -> CLUB_CLIPS
## (AnimSet_Guard_Club + DAM_CharacterAnimationMapping_GuardBase). Retained
## approximation, not silence: AnimSet_Guard_ClubLantern authors its own
## Lantern locomotion rows (AN_GuardEnforcer_Lantern_* in anims_manifest.json)
## and the Security SK has no Security-specific anims, so both reuse the Club
## table until a lantern/security clip table is authored.
func _guard_weapon_set() -> String:
	var lname: String = name.to_lower()
	if lname.find("haunt") >= 0:
		return "hauntstable"
	return "club"


## Real-clip AnimationPlayer (UE sources: ST_Guard StateTree states,
## DAM_CharacterAnimationMapping_GuardBase / _GuardHauntsable tags,
## AnimSet_Guard_Club / _Hauntsable rows, anims_manifest.json clip GLBs).
## Guarded: any failure (missing manifest, unreadable GLB, zero shared bones)
## leaves anim_player null and the procedural fallback in charge.
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


## Role playback (UE clip role; see GuardAnimationLibrary.clip_for_role).
func _play_guard_clip(role: String, force: bool = false) -> void:
	if not _anim_can_play():
		return
	var key := String(_anim_lib.clip_for_role(role))
	if key == "" or not anim_player.has_animation(key):
		return
	if not force and anim_player.current_animation == key:
		return
	anim_player.play(key, 0.25)


## Melee attack one-shot (UE role "attack":
## AN_GuardEnforcer_Club_Attack_Light_A_Montage for both weapon sets; no
## HA-specific attack clip exists in anims_manifest.json. DAM
## Guard.Attack.Ranged (AN_GuardEnforcer_Club_Attack_Ranged_Montage) is the
## ranged tag, not this melee swing). Locks locomotion for the clip length.
func _play_guard_attack() -> void:
	if not _anim_can_play():
		return
	var key := String(_anim_lib.clip_for_role("attack"))
	if key == "" or not anim_player.has_animation(key):
		return
	_attack_anim_lock = maxf(0.5, _anim_lib.clip_length(key))
	_slip_anim = false
	_takedown_vic_anim = false
	anim_player.speed_scale = 1.0
	anim_player.play(key, 0.15)


## Plays the MagicSlime slip montage once (UE role "slip":
## AN_GuardEnforcer_Slip_MagicSlime_Montage, anims_manifest.json), then falls
## through to the prone knockdown loop. Called by the tool wave; forces KO
## visuals if needed.
func play_slip() -> void:
	if state != Alertness.KNOCKED_OUT:
		knock_out()
	if not _anim_can_play():
		return
	var key := String(_anim_lib.clip_for_role("slip"))
	if key == "" or not anim_player.has_animation(key):
		return
	_slip_anim = true
	_takedown_vic_anim = false
	_attack_anim_lock = 0.0
	anim_player.speed_scale = 1.0
	anim_player.play(key, 0.2)


## Takedown victim entry (synced montage, UE role "takedown_vic":
## AN_StealthTakedown_GuardEnforcer__Vic_Montage primary, overhead behind /
## front as manifest fallback, anims_manifest.json). Called by the blackjack
## takedown path via take_knockout -> knock_out; falls through to the prone
## knockdown loop on finish. No-op when the role did not retarget (caller
## keeps the knockdown loop).
func play_takedown_vic() -> void:
	if not _anim_can_play():
		return
	var key := String(_anim_lib.clip_for_role("takedown_vic"))
	if key == "" or not anim_player.has_animation(key):
		return
	_takedown_vic_anim = true
	_slip_anim = false
	_attack_anim_lock = 0.0
	anim_player.speed_scale = 1.0
	anim_player.play(key, 0.2)


## One-shot handoff: slip montage -> knockdown loop, takedown victim montage
## -> knockdown loop (all UE roles above); attack montage end releases the
## locomotion lock.
func _on_guard_anim_finished(anim_name: StringName) -> void:
	if not _anim_can_play():
		_slip_anim = false
		_takedown_vic_anim = false
		_attack_anim_lock = 0.0
		return
	if _slip_anim:
		_slip_anim = false
		if state == Alertness.KNOCKED_OUT:
			_play_guard_clip("knockdown", true)
		return
	if _takedown_vic_anim:
		_takedown_vic_anim = false
		if state == Alertness.KNOCKED_OUT:
			_play_guard_clip("knockdown", true)
		return
	var attack_key := String(_anim_lib.clip_for_role("attack"))
	if attack_key != "" and String(anim_name) == attack_key:
		_attack_anim_lock = 0.0


## Alertness -> ST_Guard / clip_for_state state name. KNOCKED_OUT never
## reaches clip_for_state (KO handling owns the player in _update_guard_anim).
func _anim_state_name() -> String:
	match state:
		Alertness.NEUTRAL:
			return "NEUTRAL"
		Alertness.SUSPICIOUS:
			return "SUSPICIOUS"
		Alertness.ALERTED:
			return "ALERTED"
		Alertness.COMBAT:
			return "COMBAT"
		Alertness.SEARCH:
			return "SEARCH"
	return "NEUTRAL"


## Drives the real-clip state machine, single-sourced against
## GuardAnimationLibrary.clip_for_state so every transition cites the UE clip
## roles (ST_Guard states + DAM tags + AnimSet rows; KF16 patrol/alert,
## KF25 idle stance, KF26 grapple). Falls back to procedural bob when no
## clips are available. Never plays while KO handling owns the player, while
## the slip or takedown-victim montage owns it, or while the attack lock holds it.
func _update_guard_anim(delta: float) -> void:
	if not _use_real_anims or not _anim_can_play():
		_update_procedural_anim(delta)
		return
	if _slip_anim or _takedown_vic_anim:
		return
	if state == Alertness.KNOCKED_OUT:
		_play_guard_clip("knockdown")
		anim_player.speed_scale = 1.0
		return
	_attack_anim_lock = maxf(0.0, _attack_anim_lock - delta)
	if _attack_anim_lock > 0.0:
		return
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.5
	# Single transition source: Alertness -> clip_for_state -> UE clip role.
	# (Repaired: the per-state match duplicated clip_for_state here and pinned
	# SEARCH to the stationary search clip even while fanning out; ST_Guard
	# search states Move to nearby location / EQS, so clip_for_state now plays
	# suspicious_walk while SEARCH is moving.)
	var role: String = String(_anim_lib.clip_for_state(_anim_state_name(), _anim_weapon, moving))
	if role == "":
		_update_procedural_anim(delta)
		return
	_update_guard_loco_playback(role, moving, delta)


## Foot-slide fix: match locomotion playback to the speed the controller is
## actually moving. The authored clips carry root speeds of 1.24 m/s (neutral
## walk), 2.5 m/s (suspicious walk) and 7.6 m/s (alert run); scripted speeds
## are 1.5/1.7/2.5, so the unmodified clips slide. Clamped to [0.35, 1.8] so a
## blend or a stall can never freeze or whirl the legs.
func _update_guard_loco_playback(role: String, moving: bool, delta: float) -> void:
	_play_guard_clip(role)
	if not _anim_can_play():
		return
	var clip_speed: float = float(CLIP_GROUND_SPEED.get(role, 0.0))
	if not moving or clip_speed <= 0.0:
		anim_player.speed_scale = 1.0
		return
	var planar: float = Vector2(velocity.x, velocity.z).length()
	var target_rate: float = clampf(planar / clip_speed, 0.35, 1.8)
	anim_player.speed_scale = lerpf(anim_player.speed_scale, target_rate, clampf(delta * 8.0, 0.0, 1.0))


func _resolve_guard_glb_path() -> String:
	var lname: String = name.to_lower()
	if lname.find("haunt") >= 0:
		return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Hauntstable/SK_Hauntstable__Body.glb"
	if lname.find("security") >= 0:
		# task-7: headed _Body variant (skeleton-identical to the headless __Body
		# torso, 97 joints same name+order; mesh_materials slots cover head+badge).
		return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Security/SK_GuardSecurity_01_Body.glb"
	if lname.find("enforcer") >= 0:
		return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/SK_GuardEnforcer__Preview.glb"
	match GameState.difficulty:
		GameState.Difficulty.MASTER_THIEF:
			return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Hauntstable/SK_Hauntstable__Body.glb"
		GameState.Difficulty.THIEF:
			if absi(get_index()) % 3 == 2:
				return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Security/SK_GuardSecurity_01_Body.glb"
			return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/SK_GuardEnforcer__Preview.glb"
		_:
			if absi(get_index()) % 3 == 2:
				return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/SK_GuardEnforcer__Preview.glb"
			return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Security/SK_GuardSecurity_01_Body.glb"


## Loads materials.json + mesh_materials.json once (the same generated DBs
## the level_loader PBR path binds; re-read here so guards never depend on
## loader ordering). Keys: materials.json = UE material paths (exact +
## case-insensitive); mesh_materials.json = UE mesh paths without extension.
func _guard_ensure_material_dbs() -> void:
	if _guard_mats_db.is_empty() and FileAccess.file_exists("res://data/generated/materials.json"):
		var f := FileAccess.open("res://data/generated/materials.json", FileAccess.READ)
		if f != null:
			var p: Variant = JSON.parse_string(f.get_as_text())
			if p is Dictionary:
				_guard_mats_db = p
				for k: Variant in _guard_mats_db.keys():
					_guard_mats_lower[str(k).to_lower()] = _guard_mats_db[k]
	if _guard_mesh_mats.is_empty() and FileAccess.file_exists("res://data/generated/mesh_materials.json"):
		var f2 := FileAccess.open("res://data/generated/mesh_materials.json", FileAccess.READ)
		if f2 != null:
			var p2: Variant = JSON.parse_string(f2.get_as_text())
			if p2 is Dictionary:
				_guard_mesh_mats = p2
				for k2: Variant in _guard_mesh_mats.keys():
					_guard_mesh_lower[str(k2).to_lower()] = _guard_mesh_mats[k2]


## Minimal texture load for guard binds. Returns null on a missing path; the
## caller logs the UE material path and falls back to navy, never white.
func _guard_load_tex(res_path: String) -> Texture2D:
	if res_path == "":
		return null
	if _guard_tex_cache.has(res_path):
		return _guard_tex_cache[res_path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		var loaded: Variant = load(res_path)
		if loaded is Texture2D:
			tex = loaded as Texture2D
	elif FileAccess.file_exists(res_path):
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(res_path))
		if img != null and not img.is_empty():
			if not img.has_mipmaps():
				img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_guard_tex_cache[res_path] = tex
	return tex


## Logged navy fallback. Never returns white: the retained uniform navy keeps
## the guard readable and the UE path is always pushed to the warning log
## (compare civilian rest-pose + bob: missing art holds a readable pose).
func _guard_navy_fallback(ue_path: String) -> StandardMaterial3D:
	push_warning("[guard_ai] missing authored bind, navy fallback (never white): " + ue_path)
	var fb := StandardMaterial3D.new()
	fb.albedo_color = GUARD_NAVY
	fb.roughness = 0.78
	return fb


## Authored PBR bind for one UE material path (materials.json "texs"
## albedo / normal / ORM + "tint"). A missing entry, a missing texture, or
## an authored white-with-no-texture all resolve to the logged navy fallback,
## never white.
func get_guard_material_for_ue(ue_mat_path: String) -> Material:
	if ue_mat_path == "":
		return _guard_navy_fallback("(empty slot)")
	if _guard_std_cache.has(ue_mat_path):
		return _guard_std_cache[ue_mat_path] as Material
	var low_mat: String = ue_mat_path.to_lower()
	var info: Variant = _guard_mats_db.get(ue_mat_path, _guard_mats_lower.get(low_mat, {}))
	if not (info is Dictionary) or (info as Dictionary).is_empty():
		var fb_missing := _guard_navy_fallback(ue_mat_path)
		_guard_std_cache[ue_mat_path] = fb_missing
		return fb_missing
	var texs: Dictionary = (info as Dictionary).get("texs", {})
	var tint: Variant = (info as Dictionary).get("tint")
	var has_tint: bool = tint is Array and (tint as Array).size() >= 3
	var alb: Texture2D = _guard_load_tex(str(texs.get("albedo", "")))
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.78
	if alb != null:
		mat.albedo_texture = alb
		if has_tint:
			mat.albedo_color = Color(float((tint as Array)[0]), float((tint as Array)[1]), float((tint as Array)[2]), 1.0)
	else:
		if has_tint and Color(float((tint as Array)[0]), float((tint as Array)[1]), float((tint as Array)[2]), 1.0) != Color(1, 1, 1, 1):
			mat.albedo_color = Color(float((tint as Array)[0]), float((tint as Array)[1]), float((tint as Array)[2]), 1.0)
		else:
			mat.albedo_color = GUARD_NAVY
			push_warning("[guard_ai] no recoverable albedo texture, navy fallback (never white): " + ue_mat_path)
	var norm: Texture2D = _guard_load_tex(str(texs.get("normal", "")))
	if norm != null:
		mat.normal_enabled = true
		mat.normal_texture = norm
	var orm: Texture2D = _guard_load_tex(str(texs.get("orm", "")))
	if orm != null:
		mat.ao_enabled = true
		mat.ao_texture = orm
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness_texture = orm
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture = orm
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	_guard_std_cache[ue_mat_path] = mat
	return mat


## GLB UE key for the mesh_materials.json lookup (keys are UE paths without
## extension, e.g. /Game/Art/Animation/GuardEnforcer/Skin/Hauntstable/..).
func _guard_ue_key_for_glb(glb_path: String) -> String:
	var p: String = glb_path
	if p.begins_with("res://assets/ue/Content/"):
		p = p.replace("res://assets/ue/Content/", "/Game/")
	if p.ends_with(".glb"):
		p = p.substr(0, p.length() - 4)
	return p


## Slot lookup shared by the body bind and the head attach (mesh_materials
## exact key first, case-insensitive fallback; empty = no authored data).
func _guard_slots_for_ue_key(ue_key: String) -> Array:
	var slots: Array = []
	if _guard_mesh_mats.has(ue_key):
		var raw: Variant = _guard_mesh_mats[ue_key]
		if raw is Array:
			slots = (raw as Array).duplicate()
	if slots.is_empty():
		var low_key: String = ue_key.to_lower()
		if _guard_mesh_lower.has(low_key):
			var raw2: Variant = _guard_mesh_lower[low_key]
			if raw2 is Array:
				slots = (raw2 as Array).duplicate()
	return slots


## Per-MeshInstance3D surface bind shared by the body GLB and the head
## sub-skeleton (per-surface overrides, so the shared import is never
## mutated). Surface match mirrors level_loader _bind_glb_materials: exact
## eye rescue first (task-7: "Eyes" would substring-match the HelmetEyes
## slot), then GLB material-name substring, then slot-index fallback.
## A Preview slot-index hit on empty slots 0-2 resolves to the authored eye
## rescue; only a genuinely missing bind resolves to the logged navy fallback,
## never white.
func _bind_guard_mi_surfaces(mi: MeshInstance3D, slots: Array, ue_key: String) -> void:
	if mi == null or mi.mesh == null:
		return
	var is_preview: bool = ue_key.ends_with("SK_GuardEnforcer__Preview")
	for s in range(mi.mesh.get_surface_count()):
		var surf_name: String = str(mi.mesh.surface_get_name(s)).to_lower()
		if GUARD_EYE_RESCUE.has(surf_name):
			mi.set_surface_override_material(s, get_guard_material_for_ue(str(GUARD_EYE_RESCUE[surf_name])))
			continue
		var matched: int = -1
		if surf_name != "" and surf_name.length() >= 3:
			for i in range(slots.size()):
				var mp := str(slots[i])
				if mp == "":
					continue
				var short := mp.get_file().split(".")[0].to_lower()
				if short == "" or short.length() < 3:
					continue
				if surf_name.find(short) >= 0 or short.find(surf_name) >= 0:
					matched = i
					break
		if matched == -1 and s < slots.size():
			matched = s
		if matched < 0 or matched >= slots.size():
			mi.set_surface_override_material(s, _guard_navy_fallback(ue_key + " surface " + str(s)))
			continue
		var slot_path := str(slots[matched])
		if slot_path == "":
			if is_preview and matched >= 0 and matched < GUARD_PREVIEW_EYE_BY_SLOT.size():
				mi.set_surface_override_material(s, get_guard_material_for_ue(str(GUARD_PREVIEW_EYE_BY_SLOT[matched])))
			else:
				mi.set_surface_override_material(s, _guard_navy_fallback(ue_key + " slot " + str(matched)))
		else:
			mi.set_surface_override_material(s, get_guard_material_for_ue(slot_path))


## Binds the authored slot materials from mesh_materials.json onto the
## instantiated guard GLB (per-MeshInstance3D surface overrides, so the shared
## import is never mutated). Head geometry for body-only SKs arrives via
## _attach_guard_head below; this bind covers the body instance only.
func _bind_guard_glb_materials(inst: Node) -> void:
	_guard_ensure_material_dbs()
	var ue_key: String = _guard_ue_key_for_glb(_resolve_guard_glb_path())
	var slots: Array = _guard_slots_for_ue_key(ue_key)
	if slots.is_empty():
		push_warning("[guard_ai] no mesh_materials slots for " + ue_key + "; surfaces keep import material (white risk logged)")
		return
	for mi_var in inst.find_children("*", "MeshInstance3D", true, false):
		_bind_guard_mi_surfaces(mi_var as MeshInstance3D, slots, ue_key)


## Head sub-skeleton attach (task-7). Body-only SKs carry no head geometry;
## the extracted headed SK is instanced and its MeshInstance3Ds are reparented
## under the body Skeleton3D, so the head follows the guard animation (the
## joint name+order identity is verified by GLB JSON dump in task-7.md).
## The moved meshes keep their global transform and resolve their skeleton via
## the new parent; the spare head instance is freed. Head surfaces bind the
## head UE key slots through the same authored chain; only a genuinely missing
## bind falls to logged navy with the UE path.
func _attach_guard_head(inst: Node, body_glb_path: String) -> void:
	var head_glb: String = str(GUARD_HEAD_GLB.get(body_glb_path, ""))
	if head_glb == "":
		return
	var packed := ResourceLoader.load(head_glb) as PackedScene
	if packed == null:
		push_warning("[guard_ai] head GLB missing, body keeps torso-only mesh (never white): " + head_glb)
		return
	var skels: Array[Node] = inst.find_children("*", "Skeleton3D", true, false)
	var body_skel := (skels[0] as Skeleton3D) if not skels.is_empty() else null
	if body_skel == null:
		push_warning("[guard_ai] no body Skeleton3D under " + body_glb_path + "; head attach skipped")
		return
	_guard_ensure_material_dbs()
	var head_ue_key: String = _guard_ue_key_for_glb(head_glb)
	var head_slots: Array = _guard_slots_for_ue_key(head_ue_key)
	var head_inst := packed.instantiate() as Node
	if head_inst == null:
		push_warning("[guard_ai] head GLB failed to instantiate: " + head_glb)
		return
	visual_root.add_child(head_inst)
	head_inst.rotation_degrees.y = 180.0
	var moved := 0
	for mi_var in head_inst.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_var as MeshInstance3D
		if mi == null:
			continue
		if not head_slots.is_empty():
			_bind_guard_mi_surfaces(mi, head_slots, head_ue_key)
		var t: Transform3D = mi.global_transform
		mi.get_parent().remove_child(mi)
		body_skel.add_child(mi)
		mi.global_transform = t
		mi.skeleton = mi.get_path_to(body_skel)
		moved += 1
	head_inst.queue_free()
	if moved == 0:
		push_warning("[guard_ai] head GLB carried no meshes, body keeps torso-only mesh: " + head_glb)


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


## Central alertness transition. Resets the authored "time in current detection
## level" decay gate (detection.json min_seconds_in_level_before_decay) and
## clamps detection on a downward transition so stale meter value cannot leak
## into a calmer level. SEARCH also resets this clock, but SEARCH decay bypasses
## the gate entirely (decay_step_detection), so the reset cannot freeze the meter.
func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	var previous_state: int = state
	state = new_state
	_seconds_in_state = 0.0
	detection = clamped_detection_for_transition(previous_state, new_state, detection)
	_emit_alert_state_if_needed(true)


## Typed bool read for Object.get(): Godot 4.7 rejects bool(Variant) on a
## lookup that may be null or non-bool.
static func _bool_property(obj: Object, prop: String) -> bool:
	if obj == null:
		return false
	var value: Variant = obj.get(prop)
	return value is bool and value == true


func _enter_alerted() -> void:
	if state == Alertness.ALERTED or state == Alertness.COMBAT:
		return
	_set_state(Alertness.ALERTED)
	NoiseBus.emit_noise(global_position, 14.0, self, "guard_alert")
	if AudioManager != null and AudioManager.has_method("play_vo"):
		AudioManager.play_vo("guard_alert", global_position)


func _enter_combat() -> void:
	if state == Alertness.COMBAT:
		return
	_set_state(Alertness.COMBAT)
	NoiseBus.emit_noise(global_position, 12.0, self, "guard_alert")
	if AudioManager != null and AudioManager.has_method("play_vo"):
		AudioManager.play_vo("guard_alert", global_position)


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


## Authored detection-meter decay duration for an alertness level.
static func detection_decay_seconds(alertness: int) -> float:
	return float(DECAY_SECONDS_BY_STATE.get(alertness, DECAY_BASE_SECONDS))


## Authored detection-meter decay in points per second: the 0..100 meter empties
## over DA_AlertnessSettings.DecayTimeSeconds for the current alertness level.
static func detection_decay_per_second(alertness: int) -> float:
	var seconds: float = detection_decay_seconds(alertness)
	if seconds <= 0.0:
		return 0.0
	return 100.0 / seconds


## One frame of authored decay for the 0..100 meter. _physics_process checks
## the two detection.json gates before calling this.
static func decayed_detection(current: float, delta: float, alertness: int) -> float:
	return maxf(0.0, current - detection_decay_per_second(alertness) * delta)


## One no-sight frame of the detection meter. NEUTRAL, SUSPICIOUS, ALERTED and
## COMBAT keep both authored DA_DetectionSettings gates. SEARCH has no authored
## DA_AlertnessSettings row, so it decays unconditionally at the fallback
## duration DetectionDecaySeconds (7.0 s): an inference from the data (the
## Godot-only search level reuses the base decay duration), not decompiled
## behaviour. Its 6 s state_timer therefore cannot freeze the meter.
static func decay_step_detection(alertness: int, current: float, seconds_in_state: float, seconds_since_visible: float, delta: float) -> float:
	if alertness != Alertness.SEARCH \
		and (seconds_in_state < DECAY_MIN_SECONDS_IN_LEVEL \
			or seconds_since_visible < DECAY_MIN_SECONDS_SINCE_VISIBLE):
		return current
	return decayed_detection(current, delta, alertness)


## Detection value a state change may carry into the new level. Upward
## transitions keep the meter; a downward transition clamps it to the new
## state's entry ceiling so stale detection cannot leak across. SEARCH has no
## authored/retained threshold, so it is never clamped: its unconditional
## fallback decay empties the meter instead.
static func clamped_detection_for_transition(old_state: int, new_state: int, current: float) -> float:
	var old_rank: int = int(ALERTNESS_RANK.get(old_state, -1))
	var new_rank: int = int(ALERTNESS_RANK.get(new_state, -1))
	if old_rank < 0 or new_rank < 0 or new_rank >= old_rank:
		return current
	var ceiling: float = float(DETECTION_ENTRY_CEILING.get(new_state, current))
	return minf(current, ceiling)


## Entry ceiling for a state, exposed for tests. -1.0 means the level has no
## clamp (SEARCH / KNOCKED_OUT).
static func detection_entry_ceiling(alertness: int) -> float:
	return float(DETECTION_ENTRY_CEILING.get(alertness, -1.0))


## detection.json tag_ramp_modifiers["Status.Sprinting"]: x8 detection ramp
## while the player is sprinting, x1 otherwise.
static func sprint_ramp_multiplier(sprinting: bool) -> float:
	return SPRINT_RAMP_MULTIPLIER if sprinting else 1.0


## Curve_AI_HeightDifferenceToStrengthMultiplier. The 2.0 m key is
## RCIM_Constant, so it holds 1.0 until the 3.0 m key drops the strength to 0.0.
static func height_difference_strength_multiplier(height_diff_m: float) -> float:
	if height_diff_m < HEIGHT_STRENGTH_ZERO_M:
		return 1.0
	return 0.0


## Light value the guard uses for the player: sampled light visibility raised to
## the authored movement-speed floor (C_MovementSpeedToMinimumLightDetectionValue,
## BP_TATPlayerCharacter LightDetectionComponent._MovementSpeedToMinimumLightIntensity).
func _player_light_value(player: CharacterBody3D) -> float:
	if player == null:
		return GameState.player_light_visibility
	var planar_speed_cm_s: float = Vector2(player.velocity.x, player.velocity.z).length() * 100.0
	var floor_value: float = LightProbeScript.minimum_light_detection_for_speed(planar_speed_cm_s)
	return maxf(GameState.player_light_visibility, floor_value)


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
	_seconds_in_state += delta
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	var player: CharacterBody3D = (players.back() if not players.is_empty() else null) as CharacterBody3D
	_update_disguise_viewcone(delta, player)
	var sees_player: bool = _can_see_player(player)

	if sees_player:
		# Real UE ramp (DA_DetectionSettings): time-to-detect(s) = agnostic *
		# dist_m + critical_time; rate = 100/time; crouch x0.75 at/over 2.75m.
		# The light/sprint/height multipliers below are authored; the smoke/LOS
		# checks and 15/45/100 state thresholds are retained (no UE source).
		_seconds_since_visible = 0.0
		var effective_light: float = _player_light_value(player)
		var vis_mult: float = clampf(0.35 + effective_light * 1.15, 0.35, 1.5)
		var dist_m: float = player.global_position.distance_to(global_position)
		var rate: float = get_detection_rate(dist_m, _bool_property(player, "is_crouching"))
		rate *= sprint_ramp_multiplier(_bool_property(player, "is_sprinting"))
		if state == Alertness.NEUTRAL:
			# DA_DetectionSettings wires the height curve only on the Neutral ramp.
			rate *= height_difference_strength_multiplier(absf(player.global_position.y - global_position.y))
		if is_inf(rate):
			detection = 100.0
		else:
			detection = minf(100.0, detection + rate * vis_mult * delta)
		investigate_pos = player.global_position
		if detection >= DETECTION_COMBAT_AT:
			_enter_combat()
			GameState.ever_spotted = true
			GameState.ever_chased = true
		elif detection >= DETECTION_ALERTED_AT and state < Alertness.ALERTED:
			_enter_alerted()
			state_timer = 6.0
			GameState.ever_spotted = true
		elif detection >= DETECTION_SUSPICIOUS_AT and state == Alertness.NEUTRAL:
			_set_state(Alertness.SUSPICIOUS)
			state_timer = 5.0
	else:
		_seconds_since_visible += delta
		# Authored decay: NEUTRAL/SUSPICIOUS/ALERTED/COMBAT need 6 s in level
		# and 4 s without sight. SEARCH has no authored row and decays
		# unconditionally at the fallback rate (see decay_step_detection).
		detection = decay_step_detection(state, detection, _seconds_in_state, _seconds_since_visible, delta)
		if state == Alertness.COMBAT and detection <= 35.0:
			_set_state(Alertness.ALERTED)
			state_timer = 6.0
		elif state == Alertness.ALERTED:
			state_timer -= delta
			if state_timer <= 0.0:
				_set_state(Alertness.SEARCH)
				state_timer = 6.0
		elif state == Alertness.SUSPICIOUS and detection <= 0.0:
			_set_state(Alertness.SEARCH)
			state_timer = 4.0
		elif state == Alertness.SEARCH:
			state_timer -= delta
			if state_timer <= 0.0:
				_set_state(Alertness.NEUTRAL)

	_update_indicator()
	_emit_alert_state_if_needed(false)
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
	if _bool_property(player, "astral_active"):
		return false
	var dist_to_player: float = global_position.distance_to(player.global_position)
	if _bool_property(player, "disguise_active"):
		# Chameleon disguise edge cases: alerted/searching guards and tattered
		# disguises no longer pass inspection at range; close range is always risky.
		var guard_alerted: bool = state == Alertness.ALERTED or state == Alertness.COMBAT or state == Alertness.SEARCH
		var integrity: float = float(player.get("disguise_integrity"))
		if not guard_alerted and integrity >= 35.0 and dist_to_player > 3.5:
			return false
	# Retention: once sensed, the guard holds the target out to lose_sight_range.
	var sensed: bool = detection > 0.0 or state != Alertness.NEUTRAL
	var effective_range: float = lose_sight_range if sensed else sight_range
	if not sensed:
		# C_LightIntensityToRangeMultiplier (BP_NPC_Base
		# _LightIntensityToRangeMultiplierCurve) scales the fresh detection
		# range. Limitation: the authored curve gates acquisition only. Once
		# `sensed` is true (detection > 0, or any state above NEUTRAL), the
		# retained 30 m lose_sight_range applies unscaled, so retention is a
		# Godot concept with no UE source (see LOSE_SIGHT_RANGE); it is
		# deliberately unchanged here.
		effective_range *= LightProbeScript.light_intensity_range_multiplier(_player_light_value(player))
	var to_player: Vector3 = player.global_position - global_position
	var dist: float = to_player.length()
	# No point-blank blind spot: inside the 2 m critical range the authored
	# ramp (get_detection_rate) already resolves to an instant spot, so a
	# near-zero distance must still count as seen.
	if dist > effective_range:
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
	# property, so the typed lookup returns false): the Moth's astral form
	# makes no noise.
	if source != null and source.is_in_group("player") and _bool_property(source, "astral_active"):
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
			_set_state(Alertness.SUSPICIOUS)
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
	_set_state(Alertness.KNOCKED_OUT)
	if duration_override > 0.0:
		ko_timer = duration_override
	else:
		ko_timer = GameData.eval_curve("CT_AIStats", "GuardKnockoutDuration", GameState.difficulty_curve_x(), 180.0)
	alert_indicator.text = "ZZZ"
	if lantern_light != null and is_instance_valid(lantern_light):
		lantern_light.visible = false
	_slip_anim = false
	_takedown_vic_anim = false
	_attack_anim_lock = 0.0
	if visual_root == null:
		return
	if _use_real_anims and _anim_can_play():
		var vic_key := String(_anim_lib.clip_for_role("takedown_vic"))
		if vic_key != "" and anim_player.has_animation(vic_key):
			_takedown_vic_anim = true
			_slip_anim = false
			anim_player.speed_scale = 1.0
			anim_player.play(vic_key, 0.25)
			return
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
	if lantern_light != null and is_instance_valid(lantern_light):
		lantern_light.visible = true
	_set_state(Alertness.SEARCH)
	state_timer = 6.0
	investigate_pos = global_position
	if visual_root == null:
		return
	if _use_real_anims and _anim_can_play():
		# The real search clip owns the next frames; no tip-over tween.
		_slip_anim = false
		_takedown_vic_anim = false
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
				_set_state(Alertness.SEARCH)
				state_timer = 6.0
				detection = maxf(detection, 40.0)
				NoiseBus.emit_noise(global_position, 10.0, self, "guard_alert")
				if AudioManager != null and AudioManager.has_method("play_vo"):
					AudioManager.play_vo("guard_search", global_position)
				revived = true
		else:
			if state == Alertness.NEUTRAL:
				_set_state(Alertness.SUSPICIOUS)
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


func _state_name() -> String:
	match state:
		Alertness.NEUTRAL:
			return "NEUTRAL"
		Alertness.SUSPICIOUS:
			return "SUSPICIOUS"
		Alertness.ALERTED:
			return "ALERTED"
		Alertness.COMBAT:
			return "COMBAT"
		Alertness.SEARCH:
			return "SEARCH"
		Alertness.KNOCKED_OUT:
			return "KNOCKED_OUT"
	return "NEUTRAL"


## Alert telemetry snapshot consumed by M3 HUD pips & offscreen threat arcs.
func get_alert_state() -> Dictionary:
	return {
		"state": _state_name(),
		"suspicion": clampf(detection / 100.0, 0.0, 1.0),
		"world_pos": global_position,
		"alerted": state == Alertness.ALERTED or state == Alertness.COMBAT,
		"combat": state == Alertness.COMBAT,
	}


func _emit_alert_state_if_needed(force: bool) -> void:
	var norm: float = clampf(detection / 100.0, 0.0, 1.0)
	if not force and absf(norm - _last_emitted_suspicion) < 0.05:
		return
	_last_emitted_suspicion = norm
	alert_state_changed.emit(get_alert_state())


## Enables the warm handheld lantern on ClubLantern guards and registers its
## OmniLight3D with LightProbe so the guard illuminates the player for stealth.
func enable_lantern() -> void:
	carries_lantern = true
	if visual_root != null and lantern_light == null:
		_build_lantern()


func _build_lantern() -> void:
	if visual_root == null or lantern_root != null:
		return
	lantern_root = Node3D.new()
	lantern_root.name = "GuardLantern"
	lantern_root.position = Vector3(-0.36, 1.12, -0.38)
	visual_root.add_child(lantern_root)

	var glb_path: String = ""
	if ResourceLoader.exists(LANTERN_GLB_PRIMARY):
		glb_path = LANTERN_GLB_PRIMARY
	elif ResourceLoader.exists(LANTERN_GLB_FALLBACK):
		glb_path = LANTERN_GLB_FALLBACK
	if glb_path != "":
		var packed: PackedScene = ResourceLoader.load(glb_path) as PackedScene
		if packed != null:
			var inst: Node3D = packed.instantiate() as Node3D
			if inst != null:
				inst.name = "LanternMesh"
				lantern_root.add_child(inst)

	lantern_light = OmniLight3D.new()
	lantern_light.name = "LanternLight"
	lantern_light.position = Vector3(0.0, 0.08, 0.0)
	lantern_light.light_color = Color(1.0, 0.72, 0.34)
	lantern_light.light_energy = 1.4
	lantern_light.omni_range = 8.5
	lantern_light.omni_attenuation = 1.35
	lantern_light.shadow_enabled = false
	lantern_root.add_child(lantern_light)
	_register_lantern_with_probe()


func _register_lantern_with_probe() -> void:
	if lantern_light == null:
		return
	var lp: Node = null
	if level_ctrl != null:
		var lp_v: Variant = level_ctrl.get("light_probe")
		if lp_v is Node:
			lp = lp_v as Node
	if lp == null and is_inside_tree():
		var m: Node = get_tree().get_first_node_in_group("mission")
		if m != null:
			var lp_v2: Variant = m.get("light_probe")
			if lp_v2 is Node:
				lp = lp_v2 as Node
	if lp != null and lp.has_method("register_light"):
		lp.call("register_light", lantern_light)


func set_carried_item(item: Dictionary) -> void:
	carried_item = item.duplicate(true)
	if visual_root != null:
		_rebuild_carried_visual()


func has_carried_item() -> bool:
	return not carried_item.is_empty()


func steal_carried_item() -> Dictionary:
	if carried_item.is_empty():
		return {}
	var stolen: Dictionary = carried_item.duplicate(true)
	carried_item = {}
	if _carried_node != null and is_instance_valid(_carried_node):
		_carried_node.set_meta("collected", true)
		_carried_node.remove_from_group("loot")
		_carried_node.remove_from_group("interactables")
		_carried_node.queue_free()
	_carried_node = null
	if is_in_group("interactables"):
		remove_from_group("interactables")
	var val: int = int(stolen.get("value", 0))
	if val > 0:
		GameState.add_loot(1, val, false)
	if str(stolen.get("kind", "")) == "key":
		var kid: String = str(stolen.get("id", stolen.get("name", "guard_key")))
		if GameState.has_method("add_stolen_key"):
			GameState.call("add_stolen_key", kid)
	carried_item_stolen.emit(stolen)
	return stolen


func _rebuild_carried_visual() -> void:
	if _carried_node != null and is_instance_valid(_carried_node):
		_carried_node.set_meta("collected", true)
		_carried_node.remove_from_group("loot")
		_carried_node.queue_free()
	_carried_node = null
	if carried_item.is_empty() or visual_root == null:
		if is_in_group("interactables"):
			remove_from_group("interactables")
		return
	add_to_group("interactables")
	_carried_node = Node3D.new()
	_carried_node.name = "CarriedItemNode"
	_carried_node.position = Vector3(0.32, 0.96, 0.08)
	_carried_node.add_to_group("loot")
	_carried_node.set_meta("collected", false)
	var carry_scr := GDScript.new()
	carry_scr.source_code = """extends Node3D
var owner_guard: Node = null
func get_interact_prompt() -> String:
\tif owner_guard != null and owner_guard.has_method("get_interact_prompt"):
\t\treturn str(owner_guard.call("get_interact_prompt"))
\treturn "[F] PICK POCKET"
func interact(_actor: Node) -> void:
\tif owner_guard != null and owner_guard.has_method("steal_carried_item"):
\t\towner_guard.call("steal_carried_item")
"""
	carry_scr.reload()
	_carried_node.set_script(carry_scr)
	_carried_node.set("owner_guard", self)
	visual_root.add_child(_carried_node)

	var mesh_path: String = str(carried_item.get("mesh_path", DEFAULT_KEY_GLB))
	if mesh_path != "" and ResourceLoader.exists(mesh_path):
		var packed: PackedScene = ResourceLoader.load(mesh_path) as PackedScene
		if packed != null:
			var inst: Node3D = packed.instantiate() as Node3D
			if inst != null:
				inst.name = "CarriedKeyMesh"
				inst.scale = Vector3(0.85, 0.85, 0.85)
				_carried_node.add_child(inst)


func get_interact_prompt() -> String:
	if carried_item.is_empty():
		return ""
	var item_name: String = str(carried_item.get("name", "Key"))
	if state == Alertness.KNOCKED_OUT:
		return "[F] LOOT %s" % item_name
	return "[F] PICK POCKET"


func interact(_actor: Node) -> void:
	if carried_item.is_empty():
		return
	if state == Alertness.COMBAT:
		return
	steal_carried_item()


## DT_DisguiseV3IntegrityReduction GuardViewCone row: drains Chameleon disguise
## integrity at 10.0/s when disguised player is within 10.0 m and <= 65 deg
## half-cone with unobstructed LOS.
func _update_disguise_viewcone(delta: float, player: CharacterBody3D) -> void:
	if player == null or state == Alertness.KNOCKED_OUT or delta <= 0.0:
		return
	if _bool_property(player, "astral_active"):
		return
	if not _bool_property(player, "disguise_active"):
		return
	if not player.has_method("apply_guard_viewcone_disguise_decay"):
		return
	var guard_eye: Vector3 = global_position + Vector3.UP * 1.5
	var player_eye: Vector3 = player.global_position + Vector3.UP * 1.3
	var to_player: Vector3 = player_eye - guard_eye
	var dist: float = to_player.length()
	if dist > VIEWCONE_DISGUISE_RANGE_M or dist < 0.05:
		return
	var fwd: Vector3 = -global_transform.basis.z
	if fwd.length() < 0.05:
		return
	var angle_deg: float = rad_to_deg(fwd.normalized().angle_to(to_player / dist))
	if angle_deg > VIEWCONE_DISGUISE_HALF_DEG:
		return
	if level_ctrl != null and level_ctrl.has_method("is_blocked_by_smoke"):
		if level_ctrl.call("is_blocked_by_smoke", guard_eye, player_eye) == true:
			return
	var w3d: World3D = get_world_3d()
	if w3d == null:
		return
	var space: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(guard_eye, player_eye, 1, [get_rid(), player.get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		player.call("apply_guard_viewcone_disguise_decay", delta, true)
