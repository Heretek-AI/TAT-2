extends CharacterBody3D
## Constabulary Guard AI: Neutral -> Suspicious -> Alerted -> Combat.
## Implements sight cone + light visibility scaling + smoke LOS blocking + NoiseBus hearing.

enum Alertness { NEUTRAL, SUSPICIOUS, ALERTED, COMBAT, SEARCH, KNOCKED_OUT }

signal alert_state_changed(state_info: Dictionary)
signal carried_item_stolen(item: Dictionary)
## W8: one authored ranged attack landed. `result` = RangedAttack.deliver()
## output ({damage, shock_seconds, shock_applied, damage_type, hud_icon}).
signal ranged_attack_fired(result: Dictionary)

const GuardAnimLib = preload("res://src/core/animation_library.gd")
const LightProbeScript = preload("res://src/stealth/light_probe.gd")
## W6G authored hearing + perception (hearing.json / perception.json) and the
## weather SoundCarry accessor (map weather tag -> range row).
const HearingData = preload("res://src/ai/hearing_data.gd")
const WeatherProfile = preload("res://src/core/weather_profile.gd")
## W8 authored AI consumers (RE-I): the five dropped sight fields, the roster,
## the reaction-role caps, the ranged attack and binary acoustic occlusion.
const SightModel = preload("res://src/ai/sight_model.gd")
const GuardRoster = preload("res://src/ai/guard_roster.gd")
const ReactionRoles = preload("res://src/ai/reaction_roles.gd")
const RangedAttack = preload("res://src/ai/ranged_attack.gd")
const HearingOcclusion = preload("res://src/ai/hearing_occlusion.gd")
const NavSteering = preload("res://src/ai/nav_steering.gd")
## W9-P4 S1: the authored StateTree shadow interpreter (`TAT2_STATETREE=off|shadow`).
## `off` is one null check per frame; nothing is loaded until a guard exists.
const StateTreeShadow = preload("res://src/ai/statetree/shadow_runner.gd")
## Phase 3B.1: the authored `StateTreeEvent.*` tag vocabulary and the live
## emitter census (`StateTreeEvents.EMITTERS`).
const StateTreeEvents = preload("res://src/ai/statetree/events.gd")
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
## Per-clip overrides where one role resolves to a different clip than the
## measured club/Hauntstable set above (RE-F-13). Values are the authored root
## travel / clip length x the 1.16 rig scale, measured from each GLB:
## lantern run __F 673.4 cm / 1.450 s = 4.64 m/s -> 5.39 m/s world, so the
## shared 7.6 constant clamped playback to 0.35 and the legs cycled at ~1.9 m/s
## under a 2.5 m/s body. `..._Run_F` has a zero-length root track (in-place),
## so it must never be rate-scaled.
const CLIP_GROUND_SPEED_BY_CLIP: Dictionary = {
	"AN_GuardEnforcer_Lantern_Alert_Run__F": 5.39,
	"AN_GuardEnforcer_Lantern_Alert_Run_F": 0.0,
}
## Authored melee hit window source: the AnimSequence carries the 9 overlapping
## CombatHitbox states (0.920-1.170 s of a 2.133 s swing) while the played
## _Montage sibling repeats only the audio/VO events (RE-F-06/RE-F-12).
const AnimNotifyScript = preload("res://src/player/anim_notify.gd")
const SIGHT_RANGE: float = 20.0 # AIC_GuardBase Fresh SightRadius 2000cm
const LOSE_SIGHT_RANGE: float = 30.0 # Bouncer/Hauntstable Fresh LoseSightRadius 3000cm (GuardBase Fresh=2500, see report)
const HEARING_RANGE: float = 25.0 # AIC_GuardBase TATAISenseConfig_Hearing.HearingRange 2500cm
const FOV_DEG: float = 80.0 # PeripheralVisionAngleDegrees 40 (UE half-angle) x 2
## W7H indoor weather scope: a listener's authored sound-carry side is decided by
## a straight-up ceiling probe, throttled to one probe per second and re-run when
## the guard has moved 2 m (see _update_weather_scope).
const WEATHER_SCOPE_PROBE_SEC: float = 1.0
const WEATHER_SCOPE_MOVE_M: float = 2.0
## W6G escalation profiles (game/data/generated/gameplay/guard_ai.json
## escalation_tables). AIC_Bouncer drives the Hauntstable guards, so the same
## name hint guard_ai already uses for the Hauntstable skeleton selects the
## bouncer row. The GuardBase rows are identical for Fresh/Mindful/Vigilant;
## only Drowsy differs (30/35/60) and its vision range is scaled by the authored
## AI.Status.Escalation.Drowsy.Asleep x0.1 perception modifier.
const ESCALATION_PROFILE_GUARD: String = "guardbase"
const ESCALATION_PROFILE_BOUNCER: String = "bouncer"
const ESCALATION_STATE_ROWS: Dictionary = {
	Alertness.NEUTRAL: "Fresh",
	Alertness.SUSPICIOUS: "Mindful",
	Alertness.SEARCH: "Mindful",
	Alertness.ALERTED: "Vigilant",
	Alertness.COMBAT: "Vigilant",
	Alertness.KNOCKED_OUT: "Drowsy",
}
const MELEE_DAMAGE: float = 10.0 # CT_Melee_RangedAttackDamage close key
const MELEE_COOLDOWN: float = 2.0 # GE_Melee_RangedAttack_Cooldown
## Close-engagement distance reused from the ranged attack's authored splash
## radius (GA_MeleeRangedAttack DamageRadius 100 cm); the dump authors no melee
## reach, so the chaser's 1 m is this value, not a separate invention.
const MELEE_RADIUS: float = 1.0
## W8 ranged attack (RE-I-11). The authored guard attack is a 20 m falloff
## weapon, not a 1 m melee: the Chaser role closes (melee above) while every
## other combatant holds the authored EQS band 2..10 m and fires for
## 10 dmg @ 0 m -> 2 dmg @ 20 m on a 2 s cooldown. See src/ai/ranged_attack.gd.
const COMBAT_ROLE_CHASER: String = ReactionRoles.ROLE_CHASER
const COMBAT_ROLE_RANGED: String = ReactionRoles.ROLE_RANGED
## Downed-guard witnesses (RE-I-12 `DT_StimProperties.GuardDowned`, Heavy). A
## body is noticed through the same authored sight geometry, throttled so eight
## guards do not scan eight bodies every physics frame.
const BODY_SCAN_INTERVAL_S: float = 0.5
const GUARD_BODY_GROUP: String = "guard_bodies"
## Direct pickpocket reach (TATInteractionTargeterComponent.MaxInteractionRange
## 175 cm, same value the player uses) plus eye/torso ray heights.
const PICKPOCKET_RANGE_M: float = 1.75
const PICKPOCKET_PLAYER_EYE_M: float = 1.3
const PICKPOCKET_GUARD_TORSO_M: float = 1.1
# Real UE values (game/data/generated/gameplay/downed.json + CT_AIStats;
# fallbacks are the extracted numbers and apply only when sources are missing).
const DOWNED_PATH := "res://data/generated/gameplay/downed.json"
const REVIVE_HOLD_FALLBACK: float = 5.0 # GA_SyncedAbility_Revive InteractHoldDuration
const GUARD_REGEN_FALLBACK: float = 15.0 # CT_AIStats GuardBaseHealthRegenRate
const GUARD_MAX_HP_FALLBACK: float = 30.0 # CT_AIStats GuardBaseHealth
static var _downed_data: Dictionary = {}
static var _carry_scr_cache: GDScript = null # P2 per-guard runtime compile: shared carried-item script, compiled once.
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
## Authored patrol timing/orientation, parallel to patrol_points (mission
## controller fills these from APatrolPath points). Empty arrays keep the
## legacy behaviour: no dwell, no authored facing, wrap-around loop.
@export var patrol_waits: Array[float] = []
@export var patrol_yaws: Array[float] = []
@export var patrol_facing: Array[bool] = []
## Authored `EPatrolPointType` per point (`EPatrolPointType::PatrolToLocation` /
## `SmartObjectInteraction`), parallel to patrol_points. The shipped data has
## 668/673 location points and 5 smart-object points, so a consumer must not
## assume one type. Empty = no authored type (synthetic fallback patrol).
@export var patrol_types: Array[String] = []
## Authored `FPatrolPoint.WaitDeviation` per point. 24 of the 673 authored points
## have a non-zero deviation, so a consumer must not assume 0.0.
@export var patrol_wait_deviations: Array[float] = []
## APatrolPath.LoopType, e.g. "EPatrolLoopType::PingPong". Any value containing
## "pingpong" reverses at both ends instead of wrapping.
@export var patrol_loop_mode: String = ""
## Authored roster bucket or bucket class (`BP_GuardEnforcer_Club_C`,
## `DA_SpawnBucket_KeyHolder`, ...). guard_roster.gd resolves it to the authored
## sense profile, animation set, body model, lantern and carried key. Empty =
## no bucket was supplied (today's spawner passes none); the name heuristic below
## then keeps the legacy behaviour and `roster_source()` reports "unbound" so the
## gap is visible instead of silent (RE-I-07).
@export var roster_bucket: String = ""
## Per-instance switch for the authored vertical frustum gate (SightModel). On by
## default; a designer or test can isolate the pitch on one guard. The
## `--sight-frustum=off` diagnostic is global.
@export var sight_frustum_enabled: bool = true
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
## W6G authored hearing. The stimulus's authored MaxRange replaces the emitter's
## hand-tuned metre value (capped by hearing_range x weather x perception); the
## query bitmask gates which stim families this listener accepts.
var hearing_query_mask: int = 127
var last_heard_tag: String = ""
var last_heard_stim_tag: String = ""
var last_heard_distance_m: float = -1.0
var last_heard_radius_m: float = -1.0
## "short" / "long": the authored AI.Behaviors.Investigate.Short/Long row
## (ST_InvestigateStims_Guard -> Short/Long Investigation). Long fans the
## post-investigation search out for longer.
var last_investigation_kind: String = ""
var investigation_search_seconds: float = 4.0
## Authored range modifiers active on this listener. The port authors no
## gameplay tag for Status.Nervous, so this stays empty until a system pushes
## one; the plumbing is asserted by test_hearing_ranges.
var perception_tags: Array[String] = []
var _weather_sound_carry: float = 1.0
## W7H: the guard's own indoor/outdoor side. Probed at most every
## WEATHER_SCOPE_PROBE_SEC so a guard walking a corridor into a courtyard
## crosses the authored row instead of keeping its spawn-side multiplier.
var _weather_indoors: bool = false
var _weather_scope_next_ms: int = 0
var _weather_scope_pos: Vector3 = Vector3.ZERO
## Authored escalation writes the sense exports only while they still hold the
## value this script last wrote. A caller/test that pins sight_range (E2E LOS
## probes do) disables the authored writes for that instance instead of being
## silently overwritten on the next alertness transition.
var _authored_senses_enabled: bool = true
var _sense_diff_scale: float = 1.0
var _written_sight: float = -1.0
var _written_lose: float = -1.0
var _written_fov: float = -1.0
## Authored waypoint dwell/patrol direction. _patrol_wait_left > 0 means the
## guard is standing at patrol_points[wp_index] until the authored WaitSeconds
## elapses; _patrol_dir is +1/-1 for PingPong reversal.
var _patrol_wait_left: float = 0.0
var _patrol_dir: int = 1
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
var _regen_blackout: float = 0.0 # P1 in-combat regen: damage starts a blackout window; regen is gated on it (see _tick_regen).
var _ally_scan_timer: float = 0.0
## W8 authored sight row for the current alertness (SightModel.row output) plus
## the resolved roster row. Rebuilt on every escalation write.
var _sight_row: Dictionary = {}
var _sight_key: String = ""
var _roster_row: Dictionary = {}
## W8 ranged attack: authored accuracy stacks (GE limit 3, 10 s window) and the
## last combat role this guard registered for (DT_ReactionEvents.Combat).
var ranged_accuracy_stacks: int = 0
var _accuracy_age_s: float = 0.0
var combat_role: String = ""
var last_ranged_damage: float = 0.0
var _ranged_hits: int = 0
var _body_scan_timer: float = 0.0
var bodies_seen: int = 0
var _roster_cache_key: String = ""
## W8 navigation: NavigationAgent3D consumer with documented degradation.
var _nav: NavSteering = NavSteering.new()
## W9-P4 S1 shadow runner (null unless TAT2_STATETREE=shadow, or =patrol with
## the experimental TAT2_STATETREE_WRITER flag).
var _st_shadow: RefCounted = null
## Phase 3B.1 experimental writer (null unless the writer flag is on); when set it
## replaces `_move_ai` for the NEUTRAL patrol branch. Not a cutover.
var _st_writer: RefCounted = null
var _nav_bound: bool = false
## Hearing diagnostics: stimuli refused by occlusion / by the role cap.
var heard_blocked_by_wall: int = 0
var heard_as_standby: int = 0
# Real-clip animation state (animation_library.gd). When _use_real_anims is
# false the guard falls back to the procedural bob in _update_procedural_anim.
var anim_player: AnimationPlayer
var _anim_lib: RefCounted
var _anim_weapon: String = "club"
var _use_real_anims: bool = false
var _attack_anim_lock: float = 0.0
## Authored hitbox clock for the swing in flight (null outside a swing).
var _attack_clock = null
var _attack_clip: String = ""
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
	"res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/Dyn/SK_GuardEnforcer_Dyn__Body.glb": "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/Heads/SK_Guard_Head01__Helm.glb",
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
	add_to_group("xray_target")
	collision_layer = 4
	collision_mask = 1 | 2
	if name.to_lower().find("lantern") >= 0:
		carries_lantern = true
	var diff_x := GameState.difficulty_curve_x()
	health = _guard_max_hp()
	_speed_scale = lerpf(0.85, 1.2, (diff_x - 1.0) * 0.5)
	patrol_speed *= _speed_scale
	suspicious_speed *= _speed_scale
	# P1 ALERTED-outruns-COMBAT: chase_speed was never scaled while ALERTED was
	# (ALERTED 3.0 m/s > COMBAT 2.5 m/s at max scale: the guard slowed down on
	# catching the player). Scale the chase with the same difficulty lever
	# (UE TATCharacterAIMovement MaxWalkSpeed 250 cm/s base).
	chase_speed *= _speed_scale
	# W6G: the authored escalation rows are the sense base; difficulty keeps its
	# retained 0.85..1.25 lever applied on top, and the exports stay overridable.
	_sense_diff_scale = lerpf(0.85, 1.25, (diff_x - 1.0) * 0.5)
	sight_range *= _sense_diff_scale
	lose_sight_range *= _sense_diff_scale
	_apply_authored_escalation(state)
	_nav.setup(self)
	refresh_weather_sound_carry()
	# W8 authored roster (RE-I-07): a supplied bucket decides the lantern and the
	# class patrol speed (DA_AIStatesToSpeed_Hauntstable authors 75 cm/s). An
	# unbound spawn keeps today's index/name behaviour and says so.
	if roster_source() != "unbound":
		carries_lantern = roster().get("lantern", carries_lantern) == true
		patrol_speed = GuardRoster.patrol_speed_m_s(roster()) * _speed_scale
		# The authored KeyHolder carries the map's key from spawn; steal_carried_item
		# is then the only way it reaches GameState.stolen_keys.
		var key_id: String = GuardRoster.carried_key_id(roster(), str(GameState.active_map_id))
		if key_id != "" and carried_item.is_empty():
			carried_item = {
				"id": key_id,
				"name": GuardRoster.carried_key_name(key_id),
				"kind": "key",
				"value": 150,
				"mesh_path": DEFAULT_KEY_GLB,
			}
	_build_visuals()
	if carries_lantern:
		_build_lantern()
	if not carried_item.is_empty():
		_rebuild_carried_visual()
	NoiseBus.noise_record_emitted.connect(_on_noise_record)
	if patrol_points.is_empty():
		patrol_points = [global_position, global_position + Vector3(6, 0, 0), global_position + Vector3(6, 0, 6)]
	# W9-P4 S1 shadow mode is attached after the patrol data exists so the first
	# observation is the real path, not the seeded fallback. `attach` returns null
	# when the mode is off (or when `patrol` is refused without the experimental
	# writer flag), so the steady-state cost is one null check per frame.
	_st_shadow = StateTreeShadow.attach(self)
	_st_writer = _st_shadow.writer if _st_shadow != null else null


## Authored sense profile for this guard (RE-I-07). The roster bucket wins when
## the spawner supplies one; the legacy node-name heuristic is kept as the
## documented fallback so an unbound spawn behaves exactly as before. The old
## heuristic conflated Bouncer and Hauntstable -- they are different assets
## (Bouncer 2500/3000/40, aspect 1.2, pitch -21; Hauntstable 3000/3500/40).
func escalation_profile() -> String:
	var profile: String = str(roster().get("profile", ""))
	if profile != "":
		return profile
	var lname: String = name.to_lower()
	if lname.find("haunt") >= 0:
		return GuardRoster.PROFILE_HAUNTSTABLE
	if lname.find("bouncer") >= 0:
		return ESCALATION_PROFILE_BOUNCER
	return ESCALATION_PROFILE_GUARD


## Roster row backing this guard, with `source` = authored/contract/unbound.
## Re-resolved whenever `roster_bucket` changes, so a spawner that assigns the
## bucket after add_child() still wins.
func roster() -> Dictionary:
	if _roster_row.is_empty() or _roster_cache_key != roster_bucket:
		_roster_cache_key = roster_bucket
		_roster_row = GuardRoster.roster_for(roster_bucket)
	return _roster_row


## Where the roster row came from ("unbound" when no spawner bucket was passed).
func roster_source() -> String:
	return str(roster().get("source", "unbound"))


## Authored escalation row name ("Fresh"/"Mindful"/"Vigilant"/"Drowsy") for an
## alertness level. KNOCKED_OUT is the Drowsy/asleep row.
static func escalation_row_name(alertness: int) -> String:
	return str(ESCALATION_STATE_ROWS.get(alertness, "Fresh"))


## Authored escalation row for this guard + alertness (producer JSON, else the
## documented asset fallback in SightModel.AUTHORED_FALLBACK).
func escalation_row(alertness: int) -> Dictionary:
	return SightModel.row(escalation_profile(), escalation_row_name(alertness))


## Authored full sight row for the current alertness: the five fields the
## producer drops are included (RE-I-02). Rebuilt when the alertness level or a
## pinned export changes, so a test/pose override takes effect immediately while
## an unpinned guard reads the authored row without per-frame work.
func sight_row() -> Dictionary:
	var key: String = "%d|%.3f|%.3f" % [state, sight_range, fov_deg]
	if _sight_row.is_empty() or key != _sight_key:
		_sight_key = key
		_rebuild_sight_row()
	return _sight_row


func _rebuild_sight_row() -> void:
	_sight_row = escalation_row(state)
	# The exported fov/range stay authoritative when a caller pins them: the
	# horizontal half-angle the geometry test uses is the export, not a second
	# copy of the authored number (a pinned pose must stay pinned).
	var row: Dictionary = _sight_row.duplicate(true)
	row["peripheral_half_angle_deg"] = fov_deg * 0.5
	row["sight_radius_m"] = sight_range
	row["lose_sight_radius_m"] = lose_sight_range
	_sight_row = row


## Writes the authored sense values for an alertness level (scaled by the
## retained difficulty lever). Refuses once a caller has pinned the exports, so
## authored escalation can never clobber a test/pose override.
func _apply_authored_escalation(alertness: int) -> void:
	if not _authored_senses_enabled:
		return
	if _written_sight >= 0.0 \
		and (not is_equal_approx(sight_range, _written_sight) \
			or not is_equal_approx(lose_sight_range, _written_lose) \
			or not is_equal_approx(fov_deg, _written_fov)):
		_authored_senses_enabled = false
		return
	var row: Dictionary = escalation_row(alertness)
	if row.is_empty():
		return
	sight_range = float(row.get("sight_radius_m", sight_range / maxf(_sense_diff_scale, 0.001))) * _sense_diff_scale
	lose_sight_range = float(row.get("lose_sight_radius_m", lose_sight_range / maxf(_sense_diff_scale, 0.001))) * _sense_diff_scale
	fov_deg = float(row.get("peripheral_half_angle_deg", fov_deg * 0.5)) * 2.0
	_written_sight = sight_range
	_written_lose = lose_sight_range
	_written_fov = fov_deg


## Effective sight range for the current alertness. KNOCKED_OUT maps to the
## authored Drowsy/asleep row and its x0.1 vision range modifier
## (AI.Status.Escalation.Drowsy.Asleep). Conscious states are unchanged.
func effective_vision_range(use_lose_range: bool = false) -> float:
	var base: float = lose_sight_range if use_lose_range else sight_range
	if state == Alertness.KNOCKED_OUT:
		base *= HearingData.drowsy_vision_multiplier()
	return base


## Weather sound carry for this guard's map (authored Weather.SoundCarry row).
## W7H: the outdoor side is chosen by the guard's own ceiling probe, not only by
## the map's preset. Old Manor (DenseFog) and Jaspering (HeavyRain) are outdoor
## presets that also cover interiors, so a guard standing in a room used to
## attenuate every footstep with the street multiplier (0.9 / 0.8) instead of the
## authored indoors row (1.0). The probe is throttled (WEATHER_SCOPE_PROBE_SEC)
## and re-runs when the guard moves; `refresh_weather_sound_carry()` still forces
## a fresh classification at spawn and for tests/mission reloads.
func refresh_weather_sound_carry() -> void:
	_update_weather_scope(true)


func _update_weather_scope(force: bool = false) -> void:
	var now_ms: int = Time.get_ticks_msec()
	var moved: bool = global_position.distance_squared_to(_weather_scope_pos) >= WEATHER_SCOPE_MOVE_M * WEATHER_SCOPE_MOVE_M
	if not force and not moved and now_ms < _weather_scope_next_ms:
		return
	_weather_scope_next_ms = now_ms + int(WEATHER_SCOPE_PROBE_SEC * 1000.0)
	_weather_scope_pos = global_position
	var map_id: String = GameState.active_map_id
	var preset_indoor: bool = WeatherProfile.map_is_indoor(map_id)
	if preset_indoor or not is_inside_tree() or get_world_3d() == null:
		_weather_indoors = preset_indoor
	else:
		_weather_indoors = WeatherProfile.is_indoors_at(
			get_world_3d().direct_space_state,
			global_position + Vector3.UP * 1.2,
			[get_rid()])
	_weather_sound_carry = WeatherProfile.sound_carry_multiplier_for_map(map_id, _weather_indoors)


## W7H: the listener side actually used for the current sound-carry row.
func weather_indoors() -> bool:
	return _weather_indoors


func hearing_weather_multiplier() -> float:
	return _weather_sound_carry


## One listening-side range multiplier: weather sound carry x the shared-config
## perception modifiers for the tags currently on this guard. Applied once, in
## _hear; the emitter never applies it.
func hearing_sense_multiplier() -> float:
	var perception: float = HearingData.perception_range_multiplier(HearingData.SENSE_HEARING, perception_tags)
	return maxf(0.0, _weather_sound_carry * perception)


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
## W8: the authored roster bucket decides the set when one was supplied
## (RE-I-07); the name heuristic stays for unbound spawns.
func _guard_weapon_set() -> String:
	var roster_weapon: String = str(roster().get("weapon", ""))
	if roster_source() != "unbound" and roster_weapon != "":
		return roster_weapon
	var lname: String = name.to_lower()
	if lname.find("haunt") >= 0:
		return "hauntstable"
	if carries_lantern or lname.find("lantern") >= 0:
		return "lantern"
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
	# RE-F-12: the swing owns the damage window. Arm the authored CombatHitbox
	# states (the _Montage sibling has none, so the clock resolves the sequence)
	# and let _tick_attack_hit_window apply MELEE_DAMAGE when the club connects.
	# build_player names the animation after the role ("attack"), so the source
	# clip name for the notify lookup comes from the same weapon table.
	_attack_clock = AnimNotifyScript.new()
	_attack_clip = key
	if int(_attack_clock.arm(_attack_source_clip())) == 0:
		# No authored hitbox for this clip: keep the legacy instant hit rather
		# than silently dropping damage, and say so (a manifest/meta drift bug).
		push_warning("GuardMelee: no authored CombatHitbox for " + key + "; falling back to instant damage")
		_attack_clock = null
		_apply_guard_melee_hit()


## Authored manifest clip for a role in this weapon set. The animation library
## renames retargeted animations to role keys, so `player.current_animation`
## cannot be used for anims_meta lookups (notify windows, per-clip speeds).
func _source_clip_for_role(role: String) -> String:
	var table: Dictionary = GuardAnimLib.CLUB_CLIPS
	if _anim_weapon == "lantern":
		table = GuardAnimLib.LANTERN_CLIPS
	elif _anim_weapon == "hauntstable":
		table = GuardAnimLib.HA_CLIPS
	for nm: Variant in (table.get(role, []) as Array):
		if AnimNotifyScript.authored_length(str(nm)) > 0.0:
			return str(nm)
	return ""


## Authored manifest clip for the "attack" role (notify lookup).
func _attack_source_clip() -> String:
	return _source_clip_for_role("attack")


## Applies the authored melee contact if the player is still inside the UE
## DamageRadius (GA_MeleeRangedAttack 100 cm). Called from the notify poll, so
## the hit lands at 0.92-1.17 s of the 2.13 s club swing instead of frame 0.
func _apply_guard_melee_hit() -> void:
	if not is_inside_tree():
		return
	var player := _nearest_player(get_tree().get_nodes_in_group("player"))
	if player == null or not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) > MELEE_RADIUS:
		return
	if player.has_method("take_damage"):
		player.take_damage(MELEE_DAMAGE)
		# A landed chaser melee is the authored non-lethal Combat.Hit stim
		# (10 m Heavy Long); the blackjack path emits its own Takedown row.
		NoiseBus.emit_noise(player.global_position, 10.0, self, "combat_hit")


func _tick_attack_hit_window() -> void:
	if _attack_clock == null:
		return
	if not _anim_can_play() or anim_player.current_animation != _attack_clip:
		_attack_clock = null
		return
	var window: Vector2 = _attack_clock.poll(anim_player.current_animation_position)
	if window == Vector2.ZERO:
		return
	_apply_guard_melee_hit()
	_attack_clock = null # one contact per swing, like the montage's single hitbox set


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
	_attack_clock = null # a cancelled swing must not land after the state changed
	anim_player.speed_scale = 1.0
	anim_player.play(key, 0.2)


## Takedown victim entry (synced montage, UE role "takedown_vic":
## AN_StealthTakedown_GuardEnforcer__Vic_Montage primary, overhead behind /
## front as manifest fallback, anims_manifest.json). Wired on the blackjack
## takedown path via take_knockout -> knock_out, which calls this explicitly;
## falls through to the prone knockdown loop on finish. Loud UE-path warning
## (never a crash) when the role did not retarget or the player cannot play,
## so a silent procedural fallback is always diagnosable.
func play_takedown_vic() -> void:
	if not _anim_can_play():
		push_warning("[guard_ai] play_takedown_vic no-op, real anims unavailable (UE clip TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Vic_Montage); knockdown loop owns KO")
		return
	var key := String(_anim_lib.clip_for_role("takedown_vic"))
	if key == "" or not anim_player.has_animation(key):
		push_warning("[guard_ai] play_takedown_vic no-op, role 'takedown_vic' did not retarget (UE clip TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Vic_Montage); knockdown loop owns KO")
		return
	_takedown_vic_anim = true
	_slip_anim = false
	_attack_anim_lock = 0.0
	_attack_clock = null # a cancelled swing must not land after the state changed
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
		_attack_clock = null # a cancelled swing must not land after the state changed
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
		_attack_clock = null


## Alertness -> ST_Guard / clip_for_state state name. KNOCKED_OUT never
## reaches clip_for_state (KO handling owns the player in _update_guard_anim).
func _anim_state_name() -> String:
	return alertness_name(state)


## Alertness enum -> the authored state name. Single source for the animation
## state machine and the W11-A VO transition mapping (which keys on the same
## six names).
static func alertness_name(value: int) -> String:
	match value:
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
	_tick_attack_hit_window()
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
	# Per-clip override first: one role can resolve to different clips per weapon
	# set (RE-F-13), and the measured speed belongs to the clip, not the role.
	var source_clip: String = _source_clip_for_role(role)
	var clip_speed: float = float(CLIP_GROUND_SPEED_BY_CLIP.get(source_clip, CLIP_GROUND_SPEED.get(role, 0.0)))
	if not moving or clip_speed <= 0.0:
		anim_player.speed_scale = 1.0
		return
	var planar: float = Vector2(velocity.x, velocity.z).length()
	var target_rate: float = clampf(planar / clip_speed, 0.35, 1.8)
	anim_player.speed_scale = lerpf(anim_player.speed_scale, target_rate, clampf(delta * 8.0, 0.0, 1.0))


func _resolve_guard_glb_path() -> String:
	var roster_model: String = str(roster().get("model", ""))
	if roster_source() != "unbound" and roster_model != "":
		return roster_model
	var lname: String = name.to_lower()
	if lname.find("haunt") >= 0:
		return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Hauntstable/SK_Hauntstable__Body.glb"
	if lname.find("security") >= 0:
		# task-7: headed _Body variant (skeleton-identical to the headless __Body
		# torso, 97 joints same name+order; mesh_materials slots cover head+badge).
		return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Security/SK_GuardSecurity_01_Body.glb"
	if lname.find("enforcer") >= 0:
		return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/Dyn/SK_GuardEnforcer_Dyn__Body.glb"
	match GameState.difficulty:
		GameState.Difficulty.MASTER_THIEF:
			return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Hauntstable/SK_Hauntstable__Body.glb"
		_:
			return "res://assets/ue/Content/Art/Animation/GuardEnforcer/Skin/Base/Dyn/SK_GuardEnforcer_Dyn__Body.glb"


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
	var head_skels: Array[Node] = head_inst.find_children("*", "Skeleton3D", true, false)
	var head_skel: Skeleton3D = (head_skels[0] as Skeleton3D) if not head_skels.is_empty() else null
	visual_root.add_child(head_inst)
	head_inst.rotation_degrees.y = 180.0
	var moved := 0
	for mi_var in head_inst.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_var as MeshInstance3D
		if mi == null:
			continue
		if not head_slots.is_empty():
			_bind_guard_mi_surfaces(mi, head_slots, head_ue_key)
		if mi.skin != null and head_skel != null:
			# Dyn body has 100 joints, Head01 Helm 95 and a different order;
			# remap every skin bind to the body index by bone name.
			var old_skin: Skin = mi.skin
			var new_skin: Skin = old_skin.duplicate() as Skin
			if new_skin != null:
				for b in range(new_skin.get_bind_count()):
					var bn: String = str(new_skin.get_bind_name(b))
					if bn == "":
						var ob: int = new_skin.get_bind_bone(b)
						if ob >= 0 and ob < head_skel.get_bone_count():
							bn = str(head_skel.get_bone_name(ob))
					var nb: int = body_skel.find_bone(bn)
					if nb >= 0:
						new_skin.set_bind_bone(b, nb)
				mi.skin = new_skin
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
## P1 in-combat regen: CT_AIStats GuardBaseHealthRegenRate 15/s healed 0->full
## in ~2 s mid-fight, so chip damage evaporated (UE CT_AIStats regen rows are
## real; the Godot-side combat gate + damage blackout below are retained
## tuning, fail-loud when the table is unreadable).
func _tick_regen(delta: float) -> void:
	if state == Alertness.KNOCKED_OUT or state == Alertness.COMBAT:
		return
	if _regen_blackout > 0.0:
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
	# P1 sticky de-escalation: state_timer was set manually at every call
	# site, so one miss = stale-timer leak. Central reset (callers overwrite).
	state_timer = 0.0
	# P1 ally-revive strand: escalating mid-revive left _revive_target set with
	# no reset path (the old early return skipped cleanup). Clear on leaving
	# the calm set (UE GA_SyncedAbility_Revive channel breaks on alert).
	if new_state != Alertness.NEUTRAL and new_state != Alertness.SUSPICIOUS and new_state != Alertness.SEARCH and new_state != Alertness.ALERTED:
		_revive_target = null
		_revive_progress = 0.0
	detection = clamped_detection_for_transition(previous_state, new_state, detection)
	_apply_authored_escalation(new_state)
	# W11-A: authored VO for the transition. The speaker comes from the weapon
	# set (Hauntstable -> Hauntstable1); the director skips a triple that speaker
	# never authored and enforces its own cooldowns, so no line is invented and
	# no bark repeats back to back.
	if AudioManager != null and AudioManager.has_method("play_vo_transition"):
		var speaker: String = "Hauntstable1" if _guard_weapon_set() == "hauntstable" else "Enforcer1"
		AudioManager.play_vo_transition(
			alertness_name(previous_state), alertness_name(new_state), speaker, global_position)
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


func _enter_combat() -> void:
	if state == Alertness.COMBAT:
		return
	_set_state(Alertness.COMBAT)
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


## Full authored detection gain (points/sec) for one visible frame: the distance
## ramp x the sprint modifier x the Neutral-only height-difference curve. Light
## visibility is deliberately absent: C_LightIntensityToRangeMultiplier gates
## acquisition range in _can_see_player, so light affects whether the guard can
## see the player, never a second multiplicative ramp once it can. Pure, so the
## single-light contract is directly testable.
func detection_gain_per_second(dist_m: float, crouching: bool, sprinting: bool, height_diff_m: float) -> float:
	var rate: float = get_detection_rate(dist_m, crouching)
	rate *= sprint_ramp_multiplier(sprinting)
	if state == Alertness.NEUTRAL:
		# DA_DetectionSettings wires the height curve only on the Neutral ramp.
		rate *= height_difference_strength_multiplier(height_diff_m)
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
			if _st_shadow != null:
				_st_shadow.tick(delta)
		return

	_tick_regen(delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	_regen_blackout = maxf(0.0, _regen_blackout - delta)
	_seconds_in_state += delta
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	var player: CharacterBody3D = _nearest_player(players)
	_update_disguise_viewcone(delta, player)
	var sees_player: bool = _can_see_player(player)

	if sees_player:
		# Real UE ramp (DA_DetectionSettings): time-to-detect(s) = agnostic *
		# dist_m + critical_time; rate = 100/time; crouch x0.75 at/over 2.75m.
		# Sprint x8 and the Neutral-only height curve are authored; the smoke/LOS
		# checks and 15/45/100 state thresholds are retained (no UE source).
		# W6G single light: light visibility gates acquisition RANGE only
		# (_can_see_player -> C_LightIntensityToRangeMultiplier). The old
		# port-only `vis_mult` here scaled the ramp too, so darkness slowed
		# detection twice; it is gone.
		_seconds_since_visible = 0.0
		var dist_m: float = player.global_position.distance_to(global_position)
		var rate: float = detection_gain_per_second(
			dist_m,
			_bool_property(player, "is_crouching"),
			_bool_property(player, "is_sprinting"),
			absf(player.global_position.y - global_position.y))
		if is_inf(rate):
			detection = 100.0
		else:
			detection = minf(100.0, detection + rate * delta)
		investigate_pos = player.global_position
		# Rank-based promotion: the enum declares SEARCH(4) after COMBAT(3),
		# so raw </== comparisons misorder it (T2 dead zone 15-99). Compare
		# detection-ladder ranks instead; KNOCKED_OUT is unranked and sorts
		# above every conscious level so sight can never promote it (the KO
		# branch returns before this ramp in any case).
		var sight_rank: int = int(ALERTNESS_RANK.get(state, 99))
		if detection >= DETECTION_COMBAT_AT:
			_enter_combat()
			GameState.ever_spotted = true
			GameState.ever_chased = true
		elif detection >= DETECTION_ALERTED_AT and sight_rank < int(ALERTNESS_RANK[Alertness.ALERTED]):
			_enter_alerted()
			state_timer = 6.0
			GameState.ever_spotted = true
		elif detection >= DETECTION_SUSPICIOUS_AT and sight_rank < int(ALERTNESS_RANK[Alertness.SUSPICIOUS]):
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
			# W6G: the authored short/long investigation selects how long the
			# guard fans out (ST_InvestigateStims_Guard Short/Long Investigation).
			state_timer = investigation_search_seconds
		elif state == Alertness.SEARCH:
			state_timer -= delta
			if state_timer <= 0.0:
				_set_state(Alertness.NEUTRAL)

	_update_indicator()
	_emit_alert_state_if_needed(false)
	_update_ally_wakeup(delta)
	_scan_downed_guards(delta)
	if _st_writer != null:
		# Phase 3B.1 experimental spike: the interpreter's selected leaf drives the
		# NEUTRAL patrol move instead of `_move_ai`. One authority per frame.
		_st_writer.apply_step(delta)
	else:
		_move_ai(delta, player)
	_update_guard_anim(delta)
	if _st_shadow != null:
		_st_shadow.tick(delta)


## P2 players.back(): the guard sensed only the last node in the player
## group, fragile if a decoy/astral clone ever joins. Sense the nearest
## player-group body instead (single-player behavior unchanged).
func _nearest_player(players: Array[Node]) -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_d: float = INF
	for n in players:
		var b := n as CharacterBody3D
		if b == null:
			continue
		var d: float = global_position.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func _move_ai(delta: float, player: CharacterBody3D) -> void:
	var target: Vector3 = global_position
	var spd: float = patrol_speed
	match state:
		Alertness.NEUTRAL:
			# Authored patrol: stand at a waypoint for its WaitSeconds, face the
			# authored yaw when the point carries facing, and reverse at the
			# ends of a PingPong path. Without authored data this is the same
			# walk-then-advance loop as before.
			if _patrol_service_waypoint(delta):
				target = global_position
				spd = 0.0
			else:
				target = patrol_points[wp_index]
		Alertness.SUSPICIOUS:
			target = investigate_pos
			spd = suspicious_speed
		Alertness.ALERTED:
			target = investigate_pos
			spd = get_state_speed()
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
			# W8 authored ranged combat + the DT_ReactionEvents.Combat pair
			# (RE-I-11/12): one Chaser closes and melees, everyone else is the
			# default Combat.RangedAttack role and holds the authored EQS band
			# 2..10 m with line of sight, firing the CT_Melee_RangedAttackDamage
			# curve (10 dmg @ 0 m -> 2 @ 20 m) on the 2 s cooldown.
			if player != null:
				var combat: Dictionary = _service_combat(player, delta)
				target = combat.get("target", global_position) as Vector3
				spd = float(combat.get("speed", 0.0))

	var flat: Vector3 = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if flat.length() > 0.25 and spd > 0.0:
		# RE-I-10: route through the navigation map when one exists; the helper
		# falls back to this same straight-line vector (loudly, once) when no
		# NavigationRegion3D has been baked. Arrival stays the caller's test.
		var steer: Vector3 = _nav.step_towards(target)
		var dir: Vector3 = steer if steer.length() > 0.0001 else flat.normalized()
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		if state == Alertness.SEARCH:
			# P2 SEARCH pan vs look_at: the body snap-turn fought the
			# procedural visual_root +/-35 deg scan. Ease the yaw so the scan
			# reads as head motion over a turning body.
			var target_yaw: float = atan2(-dir.x, -dir.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 5.0, 0.0, 1.0))
		else:
			look_at(global_position + dir, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


## One combat frame for this guard. Returns {"target": Vector3, "speed": float}.
## Chaser: close on the target and melee inside the authored damage radius.
## Ranged (default role): hold the authored 2..10 m EQS band, fire when the
## target is inside the damage curve's 20 m extent with line of sight, and back
## off when the player closes inside the band minimum.
func _service_combat(player: CharacterBody3D, _delta: float) -> Dictionary:
	var to_player: Vector3 = player.global_position - global_position
	var dist: float = to_player.length()
	# "Melee up close" (ST_Subtree_Combat Chaser branch) applies to every role:
	# nobody fires a ranged weapon at 1 m.
	if dist <= MELEE_RADIUS:
		if attack_cooldown <= 0.0:
			# RE-F-12: the swing starts here; _apply_guard_melee_hit lands the
			# damage inside the authored CombatHitbox window (0.92-1.17 s of a
			# 2.13 s club swing), never on this frame. The Combat.Hit stim is
			# emitted at contact, not at swing start.
			_play_guard_attack()
			attack_cooldown = MELEE_COOLDOWN
		combat_role = _combat_role(player, true)
		return {"target": player.global_position, "speed": get_state_speed()}
	var role: String = _combat_role(player, false)
	if role == COMBAT_ROLE_CHASER:
		return {"target": player.global_position, "speed": get_state_speed()}
	var los: bool = _los_to_player(player)
	var band: Vector2 = RangedAttack.ideal_band_m()
	if RangedAttack.can_fire(dist, attack_cooldown, los):
		_fire_ranged_at(player, dist)
		return {"target": global_position, "speed": 0.0}
	if dist < band.x:
		# Too close for the authored firing position: step back to the band.
		var away: Vector3 = -to_player
		away.y = 0.0
		if away.length() < 0.001:
			away = global_transform.basis.z
		return {"target": global_position + away.normalized() * 2.0, "speed": suspicious_speed}
	if not los or dist > band.y:
		return {"target": player.global_position, "speed": get_state_speed()}
	# Inside the band with LOS but on cooldown: hold position and keep facing.
	_face_towards(player.global_position)
	return {"target": global_position, "speed": 0.0}


## The authored combat role for this guard (DT_ReactionEvents.Combat: one Chaser
## with a 5 s registration grace, RangedAttack as the default role).
func _combat_role(player: CharacterBody3D, wants_chaser: bool) -> String:
	var key: String = "combat:%d" % player.get_instance_id()
	combat_role = ReactionRoles.claim_combat(key, get_instance_id(), Time.get_ticks_msec(), wants_chaser)
	return combat_role


## Fire one authored ranged attack: damage from the distance curve, accuracy
## stack bookkeeping, 2 s cooldown, shock contract on the victim and the authored
## Combat.Hit hearing stimulus.
func _fire_ranged_at(player: CharacterBody3D, dist_m: float) -> void:
	var result: Dictionary = RangedAttack.deliver(player, dist_m, "guard_ranged")
	last_ranged_damage = float(result.get("damage", 0.0))
	_ranged_hits += 1
	ranged_accuracy_stacks = RangedAttack.stacks_after_shot(ranged_accuracy_stacks)
	_accuracy_age_s = 0.0
	attack_cooldown = RangedAttack.COOLDOWN_S
	_play_guard_attack()
	_face_towards(player.global_position)
	ranged_attack_fired.emit(result)
	NoiseBus.emit_noise(player.global_position, 10.0, self, "combat_hit")


func _face_towards(point: Vector3) -> void:
	var dir: Vector3 = point - global_position
	dir.y = 0.0
	if dir.length() > 0.25:
		look_at(global_position + dir.normalized(), Vector3.UP)


## World LOS from the guard eye to the player's torso, same mask/exclusions as
## the sight ray (layer 1 world + player/guard bodies).
func _los_to_player(player: CharacterBody3D) -> bool:
	if player == null or not is_inside_tree() or get_world_3d() == null:
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return false
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.5,
		player.global_position + Vector3.UP * 1.0,
		1 | 2 | 4, [get_rid(), player.get_rid()])
	return space.intersect_ray(q).is_empty()


## `GuardDowned` (RE-I-12): look for downed guards inside the authored sight
## geometry and react. Heavy severity, so the first two witnesses (the same
## authored investigator cap as a heavy stimulus) walk to the body; everyone who
## sees it is at least raised to SUSPICIOUS. Throttled: eight guards do not scan
## eight bodies every physics frame.
func _scan_downed_guards(delta: float) -> void:
	if not is_inside_tree():
		return
	_body_scan_timer -= delta
	if _body_scan_timer > 0.0:
		return
	_body_scan_timer = BODY_SCAN_INTERVAL_S
	var seen: int = 0
	var row: Dictionary = sight_row()
	var eye: Vector3 = SightModel.eye_position(self, row)
	var fwd: Vector3 = -global_transform.basis.z
	var max_range: float = effective_vision_range(true)
	var world: World3D = get_world_3d()
	var space: PhysicsDirectSpaceState3D = world.direct_space_state if world != null else null
	for node: Node in get_tree().get_nodes_in_group(GUARD_BODY_GROUP):
		var body: Node3D = node as Node3D
		if body == null or body == self or not is_instance_valid(body):
			continue
		var to_body: Vector3 = body.global_position - global_position
		if to_body.length() > max_range:
			continue
		var to_target: Vector3 = SightModel.target_point(body) - eye
		if not SightModel.frustum_admits(row, to_target, fwd, -1.0, sight_frustum_enabled):
			continue
		if space != null:
			# W10-A2: `eye` orients the frustum only (it sits behind the head by
			# the authored POV offset); the occlusion ray leaves the model head,
			# or a guard backed against a wall starts the ray inside it.
			var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(SightModel.head_position(self), SightModel.target_point(body), 1, [get_rid(), body.get_rid()])
			if not space.intersect_ray(q).is_empty():
				continue
		seen += 1
		_on_downed_guard_noticed(body)
	bodies_seen = seen


## One witness reaction to a downed colleague. Every witness of the same body
## shares one stimulus id, so the authored investigator cap applies once for the
## body rather than once per witness.
func _on_downed_guard_noticed(body: Node3D) -> void:
	if state == Alertness.KNOCKED_OUT or state == Alertness.COMBAT:
		return
	var event_id: int = 0x40000000 + (body.get_instance_id() % 0x3FFFFFFF)
	var role: String = ReactionRoles.claim_hearing(event_id, "vision.guard_downed", "Heavy", get_instance_id(), Time.get_ticks_msec())
	if role == ReactionRoles.ROLE_INVESTIGATOR:
		investigate_pos = body.global_position
		detection = maxf(detection, DETECTION_ALERTED_AT)
		state_timer = 6.0
		_enter_alerted()
		last_investigation_kind = HearingData.BEHAVIOUR_LONG
		investigation_search_seconds = 8.0
	else:
		# Standby witnesses still register the body: suspicion, no walk.
		detection = maxf(detection, DETECTION_SUSPICIOUS_AT)
		if state == Alertness.NEUTRAL:
			_set_state(Alertness.SUSPICIOUS)
			state_timer = 5.0


## One frame of authored waypoint handling. Returns true while the guard must
## stand still (dwelling at the current point); false when it may walk on.
## Waits come from APatrolPath FPatrolPoint.WaitSeconds; the yaw is applied only
## for points whose HasFacing was authored. Authored positions keep their y, so
## the guard never floats: _move_ai is planar and gravity/floor contact own y.
func _patrol_service_waypoint(delta: float) -> bool:
	if patrol_points.is_empty():
		return false
	if _patrol_wait_left > 0.0:
		_patrol_wait_left = maxf(0.0, _patrol_wait_left - delta)
		_apply_patrol_yaw(delta, wp_index)
		if _patrol_wait_left <= 0.0:
			_advance_patrol_index()
		return true
	if global_position.distance_to(patrol_points[wp_index]) < 1.0:
		var wait_s: float = _patrol_wait_for(wp_index)
		_apply_patrol_yaw(delta, wp_index)
		if wait_s > 0.0:
			_patrol_wait_left = wait_s
			return true
		_advance_patrol_index()
	return false


## Authored dwell still owed at the current waypoint. Read-only accessor for the
## StateTree shadow binding (W9-P4 S1): `_patrol_wait_left` stays private.
func patrol_wait_remaining() -> float:
	return maxf(0.0, _patrol_wait_left)


## Authored WaitSeconds for a waypoint (0.0 when the index has no record).
func _patrol_wait_for(index: int) -> float:
	if index < 0 or index >= patrol_waits.size():
		return 0.0
	return maxf(0.0, patrol_waits[index])


## Authored facing yaw for a waypoint, in Godot radians. UE yaw 0 faces +X and
## positive yaw turns toward +Y (Godot +Z); Godot rotation.y 0 faces -Z, so
## rot.y = -(yaw + 90 deg). Applied only when HasFacing was authored.
func _apply_patrol_yaw(delta: float, index: int) -> void:
	if index < 0 or index >= patrol_yaws.size() or index >= patrol_facing.size():
		return
	if not patrol_facing[index]:
		return
	var target_yaw: float = deg_to_rad(-(patrol_yaws[index] + 90.0))
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 4.0, 0.0, 1.0))


## Advance to the next waypoint: wrap for Loop, reverse at both ends for
## PingPong (APatrolPath.LoopType). No-op for a single-point path.
func _advance_patrol_index() -> void:
	var count: int = patrol_points.size()
	if count <= 1:
		wp_index = 0
		return
	if patrol_loop_mode.to_lower().find("pingpong") >= 0:
		if wp_index + _patrol_dir >= count:
			_patrol_dir = -1
		elif wp_index + _patrol_dir < 0:
			_patrol_dir = 1
		wp_index = clampi(wp_index + _patrol_dir, 0, count - 1)
	else:
		wp_index = (wp_index + 1) % count


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
		# P1 hard-gate: calm + healthy disguise was invisible at 4 m in full
		# light while the viewcone drain still ran (two systems disagreeing).
		# The gate now needs distance (> 9 m) or darkness (sampled < 0.35);
		# near + lit still inspects (UE DT_DisguiseV3 proximity/viewcone rows
		# keep draining through _update_disguise_viewcone).
		if not guard_alerted and integrity >= 35.0 and dist_to_player > 3.5:
			if dist_to_player > 9.0 or GameState.player_light_visibility < 0.35:
				return false
	# Retention: once sensed, the guard holds the target out to lose_sight_range.
	# P1 retention snap + light drop: any 1-point blip held the unscaled 30 m
	# lose_sight_range and dropped the light gate acquisition obeys. Retention
	# now needs a real lead (>= SUSPICIOUS threshold or a non-neutral state)
	# and the authored light multiplier gates both branches (UE
	# _LightIntensityToRangeMultiplierCurve).
	var sensed: bool = detection >= DETECTION_SUSPICIOUS_AT or state != Alertness.NEUTRAL
	var effective_range: float = effective_vision_range(sensed)
	effective_range *= LightProbeScript.light_intensity_range_multiplier(_player_light_value(player))
	var to_player: Vector3 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist > effective_range:
		return false
	# W8 authored sight geometry (RE-I-02). Before this the cone was bypassed
	# for *every* target inside 3.5 m -- 3.5x the authored MinimumSightRadius
	# (100 cm) -- so a guard saw a player anywhere in the 2.4 m blackjack reach
	# and the 0.45 s takedown hold lost the race against the detection ramp.
	# The frustum now applies the authored horizontal half-angle, the vertical
	# band (FrustumPitch -22 deg + FrustumAspectRatio 2.0 => -44.7..+0.7 deg of
	# elevation) and the authored near plane, with the authored minimum radius
	# as the only cone-free zone. The POV backward offset orients the frustum;
	# the occlusion ray still leaves the model head (a POV pushed 1.2 m behind a
	# guard backed against a wall would start inside geometry and blind it).
	var row: Dictionary = sight_row()
	var eye: Vector3 = SightModel.eye_position(self, row)
	var to_target: Vector3 = SightModel.target_point(player) - eye
	var fwd: Vector3 = -global_transform.basis.z
	# `sight_frustum_enabled` is the per-instance diagnostic: it drops only the
	# vertical band (the authored pitch), never the horizontal cone or the
	# minimum radius.
	if not SightModel.frustum_admits(row, to_target, fwd, -1.0, sight_frustum_enabled):
		return false
	# Smoke bomb LOS check
	if level_ctrl != null and level_ctrl.has_method("is_blocked_by_smoke"):
		if level_ctrl.is_blocked_by_smoke(global_position + Vector3.UP * 1.5, player.global_position + Vector3.UP * 1.0):
			return false
	# P1 body-transparent sight: the world-only mask let a line of guards
	# screen the player (UE sight is body-blocked). World + player + guard
	# layers. Both the guard and the player are excluded by RID: the eye ray
	# starts inside the guard capsule, and its endpoint (player + 1.0 m) sits
	# inside the player capsule on layer 2, so without the player RID every ray
	# self-occludes on the target and no guard can ever see the player.
	# W8 (RE-I-09): civilian layer 8 is NOT in the mask. A civilian standing in
	# a corridor used to make a guard blind to the player, but the shipped AI
	# treats civilians as detectable actors, not cover.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, player.global_position + Vector3.UP * 1.0, 1 | 2 | 4, [get_rid(), player.get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	return hit.is_empty()


func _on_noise_emitted(origin: Vector3, loudness: float, source: Node, tag: String) -> void:
	# Backwards-compatible 4-argument entry (external callers/tests). The bus is
	# the normal path and hands the richer record below.
	_hear(NoiseBus.build_record(origin, loudness, source, tag, ""))


## W6G hearing. The emitted record already carries the resolved authored stim
## (HearingData), so this function never guesses a range:
##   authored:  radius = min(stim.MaxRange x surface multiplier,
##                          HearingRange x weather x perception modifiers)
##   legacy:    radius = min(emitter loudness, HearingRange) x weather/perception
##             (tags with no honest authored row: guard_alert, smoke, ...)
## Hearing raises ALERTNESS only. It never writes the 0..100 detection meter
## any more (the meter is the sight ramp's; hearing used to seed 25/60 and leak
## stale suspicion into the next sight acquisition). guard_alert keeps its
## authored shout behaviour: it enters ALERTED and, when a real alerted guard is
## the caller, marks the intruder spotted.
func _on_noise_record(record: Dictionary) -> void:
	_hear(record)


func _hear(record: Dictionary) -> void:
	if record.is_empty():
		return
	var source: Node = record.get("source") as Node
	if state == Alertness.KNOCKED_OUT or source == self:
		return
	# Only the player thief carries astral_active (guards have no such
	# property, so the typed lookup returns false): the Moth's astral form
	# makes no noise.
	if source != null and source.is_in_group("player") and _bool_property(source, "astral_active"):
		return
	var origin: Vector3 = record.get("origin", global_position)
	var tag: String = str(record.get("tag", ""))
	var dist_m: float = global_position.distance_to(origin)
	# W7H: the listener-side weather scope (indoor/outdoor) can change as the
	# guard walks, so refresh it before the multiplier is read.
	_update_weather_scope()
	var sense_mult: float = hearing_sense_multiplier()
	var stim: Dictionary = record.get("stim", {}) as Dictionary
	var radius_m: float = 0.0
	var kind: String = HearingData.BEHAVIOUR_SHORT
	var stim_tag: String = ""
	if not stim.is_empty():
		if not HearingData.heard_by(stim, HearingData.FACTION_HOSTILES):
			return
		if not HearingData.accepts_query(stim, hearing_query_mask):
			return
		var surface_mult: float = float(record.get("surface_multiplier", 1.0))
		var sense_range: float = maxf(hearing_range, 0.0) * sense_mult
		radius_m = minf(float(stim.get("max_range_m", 0.0)) * surface_mult, sense_range)
		kind = str(stim.get("behaviour", HearingData.BEHAVIOUR_SHORT))
		stim_tag = str(stim.get("tag", ""))
	else:
		# Legacy tag (HearingData.LEGACY_TAGS / unknown). Preserves the existing
		# contract: emitter loudness capped by the authored sense range.
		var loudness: float = float(record.get("loudness_m", 0.0))
		if loudness > hearing_range:
			push_warning("[guard_ai] noise '", tag, "' loudness ", loudness, " m exceeds HearingRange ", hearing_range, " m; clamped (UE TATAISenseConfig_Hearing)")
		radius_m = HearingData.unknown_fallback_range(loudness, hearing_range) * sense_mult
	if dist_m > radius_m:
		return
	# W8 binary acoustic occlusion (RE-I-05): all 54 authored rows declare
	# PropogateThroughOpenPortals, so a segment that crosses world geometry is
	# heard only when the crossing lies inside an authored AkAcousticPortal box
	# with no closed swinging door in it. Fail-open when the space is unusable.
	var space: PhysicsDirectSpaceState3D = null
	if is_inside_tree() and get_world_3d() != null:
		space = get_world_3d().direct_space_state
	if not HearingOcclusion.clear(space, HearingOcclusion.listener_eye(self), HearingOcclusion.source_point(origin), [get_rid()]):
		heard_blocked_by_wall += 1
		return
	last_heard_tag = tag
	last_heard_stim_tag = stim_tag
	last_heard_distance_m = dist_m
	last_heard_radius_m = radius_m
	last_investigation_kind = kind
	# Authored investigation target: exact stim location inside the outer
	# investigation range, otherwise the midpoint of the authored inner..outer
	# band on the guard's side (see HearingData.investigation_point).
	investigate_pos = HearingData.investigation_point(stim, origin, global_position) if not stim.is_empty() else origin
	investigation_search_seconds = 8.0 if kind == HearingData.BEHAVIOUR_LONG else 4.0
	# Phase 3B.1: the one live `StateTreeEvent.*` emitter. PORT INFERENCE, not
	# authored data: the cook serialises only the tag name, and nothing in the
	# payload says a heard record is a `StimChange`. The inference is that a
	# record which passed the authored heard-by/query/range/occlusion filters is
	# a stimulus change for this listener, so the tag goes into the live
	# interpreter here -- before the guard_alert early return and before the
	# reaction-role cap (the stim changed even if the guard takes Standby). The
	# payload dictionary is trace metadata copied from the record; no bound
	# parameter is invented.
	if _st_shadow != null:
		_st_shadow.push_event(StateTreeEvents.STIM_CHANGE, {
			"heard_tag": tag,
			"stim_tag": stim_tag,
		})
	# guard_alert is the authored shout path (the only stim-shaped legacy tag):
	# ST_InvestigateStims_Guard "React To Guard Calling For Help" raises
	# alertness and investigates. Keep the existing ALERTED transition.
	if tag == "guard_alert":
		# A shout is a long investigation even on the legacy loudness path (the
		# state tree routes "React To Guard Calling For Help" through the same
		# investigate subtree with the extra nearby-location loop).
		last_investigation_kind = HearingData.BEHAVIOUR_LONG
		investigation_search_seconds = 8.0
		if state != Alertness.ALERTED and state != Alertness.COMBAT:
			state_timer = 6.0
			_enter_alerted()
		if hearing_marks_spotted(source):
			GameState.ever_spotted = true
		return
	# W8 reaction-role cap (RE-I-12, DT_ReactionEvents): only two listeners
	# investigate one stimulus (HeavyStim row, 0.5 s registration grace; the four
	# light rows cap at two with no grace; Phonograph caps at zero). Everyone
	# else takes the authored default role -- Standby -- which means "heard it,
	# hold post": the guard keeps the memory of the sound but does not walk.
	# Before this, one footstep pulled every guard in radius to the same spot.
	var event_id: int = int(record.get("event_id", 0))
	if event_id == 0:
		event_id = ReactionRoles.next_event_id()
	ReactionRoles.prune(Time.get_ticks_msec())
	var severity: String = str(stim.get("severity", "")) if not stim.is_empty() else "Light"
	var role: String = ReactionRoles.claim_hearing(event_id, stim_tag if stim_tag != "" else tag, severity, get_instance_id(), Time.get_ticks_msec())
	if role != ReactionRoles.ROLE_INVESTIGATOR:
		heard_as_standby += 1
		return
	# Every other stimulus raises alertness through the existing transition and
	# leaves the meter to the sight ramp. Promotion only from NEUTRAL, so hearing
	# can never de-escalate an alerted guard.
	# W7H: a repeated noise while SEARCH is already running refreshes the
	# authored fan-out window (4 s short / 8 s long) instead of letting the
	# search expire mid-investigation; the detection meter is still untouched.
	if state == Alertness.SEARCH:
		state_timer = maxf(state_timer, investigation_search_seconds)
		if _search_goal_timer <= 0.0:
			_search_goal_timer = 2.5
	if state == Alertness.NEUTRAL:
		_set_state(Alertness.SUSPICIOUS)
		state_timer = 5.0


## A guard shout marks the intruder spotted only when a real guard that is
## already alerted/combat is the caller (the sight path sets ever_spotted there
## anyway). Alarm eyes and revive calls share the guard_alert tag but are not
## "the thief was spotted" evidence.
static func hearing_marks_spotted(source: Node) -> bool:
	if source == null or not source.is_in_group("guards"):
		return false
	var source_state: Variant = source.get("state")
	if source_state == null:
		return false
	return int(source_state) == Alertness.ALERTED or int(source_state) == Alertness.COMBAT


func take_knockout(dmg: float) -> void:
	health -= dmg
	_regen_blackout = 4.0 # P1: chip damage must stick; regen resumes 4 s after the last hit.
	# W8 `React to Damage` (RE-I-08): the port lowered HP with no alertness
	# change, so a guard that survived a hit kept patrolling. The authored
	# transition raises alertness on damage; a lethal hit falls through to the KO
	# below and never writes it. A *non-lethal* hit is also the authored
	# Combat.Hit hearing stimulus (10 m Heavy Long) -- a blackjack one-shot is
	# the Takedown row instead, which is why this is gated on surviving.
	if health > 0.0 and state != Alertness.KNOCKED_OUT:
		investigate_pos = global_position
		detection = maxf(detection, DETECTION_ALERTED_AT)
		if state != Alertness.ALERTED and state != Alertness.COMBAT:
			state_timer = 6.0
			_enter_alerted()
		NoiseBus.emit_noise(global_position, 10.0, self, "combat_hit")
	if health <= 0.0:
		knock_out()


func apply_damage(dmg: float) -> void:
	take_knockout(dmg)


func knock_out(duration_override: float = -1.0) -> void:
	if state == Alertness.KNOCKED_OUT:
		return
	_set_state(Alertness.KNOCKED_OUT)
	# W8 `GuardDowned` (RE-I-12): a downed guard is a Heavy *visual* stimulus
	# (DT_StimProperties), so the body joins the group other guards scan.
	add_to_group(GUARD_BODY_GROUP)
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
	_attack_clock = null # a cancelled swing must not land after the state changed
	if visual_root == null:
		return
	if _use_real_anims and _anim_can_play():
		# Explicit victim-montage call: take_knockout -> knock_out -> play_takedown_vic.
		# play_takedown_vic warns loudly when the role did not retarget.
		play_takedown_vic()
		if _takedown_vic_anim:
			return
		push_warning("[guard_ai] knock_out victim montage unavailable, falling back to knockdown loop (UE clip TAT/Content/Art/Animation/Base/Anim/Synced/AN_StealthTakedown_GuardEnforcer__Vic_Montage)")
		var ko_key := String(_anim_lib.clip_for_role("knockdown"))
		if ko_key != "" and anim_player.has_animation(ko_key):
			anim_player.play(ko_key, 0.25)
			return
		push_warning("[guard_ai] knock_out knockdown role missing too; procedural tween owns KO")
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
	remove_from_group(GUARD_BODY_GROUP)
	if lantern_light != null and is_instance_valid(lantern_light):
		lantern_light.visible = true
	# P1 KO wake searches own feet + keeps pre-KO 100: clamp the meter to the
	# revive ceiling (40, like the ally-revive path) and keep the last
	# stimulus instead of overwriting investigate_pos with the fall spot
	# (UE path: none authored for wake position/meter; Godot-side parity with
	# wake_up_from_ko, fail-loud if the meter table is unreadable).
	detection = minf(detection, 40.0)
	if investigate_pos == Vector3.ZERO:
		investigate_pos = global_position
	_set_state(Alertness.SEARCH)
	state_timer = 6.0
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
	# P1 ally-revive: the old scan acted on the first KO in group order (a
	# distant KO blocked an adjacent one) and stranded progress when the
	# reviver escalated (early return skipped the reset). Scan nearest-first;
	# _set_state clears the strand on escalation. ALERTED may revive (COMBAT
	# may not: it is fighting for its life; UE GA_SyncedAbility_Revive
	# InteractHoldDuration 5.0 s still gates the hold).
	if state != Alertness.NEUTRAL and state != Alertness.SUSPICIOUS and state != Alertness.SEARCH and state != Alertness.ALERTED:
		_revive_target = null
		_revive_progress = 0.0
		return
	_ally_scan_timer -= delta
	if _ally_scan_timer > 0.0:
		return
	_ally_scan_timer = 0.4
	var best_ko: Node = null
	var best_d: float = 6.0
	for g in get_tree().get_nodes_in_group("guards"):
		if g == self or not (g is Node3D):
			continue
		var d: float = global_position.distance_to((g as Node3D).global_position)
		if d > best_d:
			continue
		var state_var: Variant = g.get("state")
		if state_var == null or int(state_var) != Alertness.KNOCKED_OUT:
			continue
		best_ko = g
		best_d = d
	var revived: bool = false
	if best_ko != null:
		var other_pos: Vector3 = (best_ko as Node3D).global_position
		investigate_pos = other_pos
		if best_d <= 1.8:
			# Reviving an ally takes a sustained hold over them (real
			# GA_SyncedAbility_Revive InteractHoldDuration 5.0 s).
			if _revive_target != best_ko:
				_revive_target = best_ko
				_revive_progress = 0.0
			_revive_progress += 0.4
			if _revive_progress >= revive_hold_s():
				_revive_target = null
				_revive_progress = 0.0
				best_ko.set("ko_timer", 0.0)
				if best_ko.has_method("wake_up_from_ko"):
					best_ko.call("wake_up_from_ko")
				_set_state(Alertness.SEARCH)
				state_timer = 6.0
				detection = maxf(detection, 40.0)
				NoiseBus.emit_noise(global_position, 10.0, self, "guard_alert")
				revived = true
		elif state == Alertness.NEUTRAL:
			_set_state(Alertness.SUSPICIOUS)
			state_timer = 5.0
	if not revived and _revive_target != null:
		var still_close: bool = false
		if is_instance_valid(_revive_target) and _revive_target is Node3D:
			still_close = global_position.distance_to((_revive_target as Node3D).global_position) <= 2.0
		if not still_close or _revive_target != best_ko:
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
	# C2: authored MI_XrayGuard silhouette (through walls, category red).
	if visual_root == null:
		return
	XrayOverlay.set_xray_highlight(visual_root, on, "guard")


func set_xray_highlight(on: bool, _category: String = "") -> void:
	set_highlighted(on)


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
		# W6G diagnostic: what the hearing path last resolved (authored stim,
		# distance vs the final radius, short/long investigation).
		"hearing_multiplier": hearing_sense_multiplier(),
		"last_heard_stim": last_heard_stim_tag,
		"last_heard_tag": last_heard_tag,
		"last_heard_distance_m": last_heard_distance_m,
		"last_heard_radius_m": last_heard_radius_m,
		"investigation_kind": last_investigation_kind,
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
	# P1 pickpocket not free/silent: a calm (NEUTRAL) lift still risks the
	# victim noticing (UE path: none authored for theft awareness; Godot-side
	# SUSPICIOUS bump + 4 m tell, fail-loud below if the meter table breaks).
	if state == Alertness.NEUTRAL:
		detection = maxf(detection, DETECTION_SUSPICIOUS_AT)
		NoiseBus.emit_noise(global_position, 4.0, self, "pickpocket")
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
	# P2 per-guard runtime GDScript compile: the carried-item script was built
	# and compiled per guard. One shared script resource, compiled once, reused
	# by every guard (UE path: none; Godot-side compile cache, fail-loud).
	if _carry_scr_cache == null:
		_carry_scr_cache = GDScript.new()
		_carry_scr_cache.source_code = """extends Node3D
var owner_guard: Node = null
func get_interact_prompt() -> String:
\tif owner_guard != null and owner_guard.has_method("get_interact_prompt"):
\t\treturn str(owner_guard.call("get_interact_prompt"))
\treturn "[F] PICK POCKET"
func get_interact_point() -> Vector3:
\t# W2: LOS targets the guard torso (not the belt prop), matching the
\t# direct interact() gate in guard_ai.
\tif owner_guard is Node3D:
\t\treturn (owner_guard as Node3D).global_position + Vector3.UP * 1.1
\treturn global_position + Vector3.UP * 0.5
func interact(actor: Node) -> void:
\t# P1 pickpocket gate bypass: this proxy used to call steal_carried_item
\t# directly, skipping the owner's alert-state gate. Route through
\t# interact(actor) so alert victims notice the attempt.
\tif owner_guard != null and owner_guard.has_method("interact"):
\t\towner_guard.call("interact", actor)
"""
		var scr_err: Error = _carry_scr_cache.reload()
		if scr_err != OK:
			push_error("[guard_ai] carried-item shared script failed to compile (UE key-belt visual path)")
			assert(false, "carried item script compile failed")
			return
	_carried_node.set_script(_carry_scr_cache)
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
	# Direct pickpocket gate: reach <= 1.75 m and clear world LOS from the
	# player eye to the guard torso. No facing cone: lifting from behind is
	# intended. A blocked attempt refuses silently and never escalates, so the
	# prompt and the outcome agree (get_nearest_interactable applies the same
	# world LOS for the carried-item prompt).
	if not _pickpocket_reachable(_actor):
		return
	# P1 pickpocket free/silent on alert victims: SUSPICIOUS/ALERTED/SEARCH
	# victims used to pay out with no check, cooldown, detection bump, noise
	# or state change. Only calm (NEUTRAL) victims can be lifted and knocked
	# down (KNOCKED_OUT) victims are looted; an attempt on an alert victim
	# escalates it instead (UE path: none authored for alert theft; Godot-side
	# escalation, fail-loud below if the alert path breaks).
	if state != Alertness.NEUTRAL and state != Alertness.KNOCKED_OUT:
		var actor_pos: Vector3 = global_position
		if _actor is Node3D:
			actor_pos = (_actor as Node3D).global_position
		investigate_pos = actor_pos
		detection = maxf(detection, DETECTION_ALERTED_AT)
		if state != Alertness.ALERTED and state != Alertness.COMBAT:
			_enter_alerted()
			state_timer = 6.0
		NoiseBus.emit_noise(global_position, 6.0, self, "pickpocket_spotted")
		return
	steal_carried_item()


## Reach + world-geometry LOS for a direct pickpocket (layer 1 only; both the
## player and this guard are excluded so capsules can never self-occlude).
func _pickpocket_reachable(actor: Node) -> bool:
	if not (actor is Node3D):
		return false
	var actor3d: Node3D = actor as Node3D
	if actor3d.global_position.distance_to(global_position) > PICKPOCKET_RANGE_M:
		return false
	var w3d: World3D = get_world_3d()
	if w3d == null or w3d.direct_space_state == null:
		return false
	var from: Vector3 = actor3d.global_position + Vector3.UP * PICKPOCKET_PLAYER_EYE_M
	var to: Vector3 = global_position + Vector3.UP * PICKPOCKET_GUARD_TORSO_M
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid(), actor3d.get_rid()])
	return w3d.direct_space_state.intersect_ray(q).is_empty()


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
	# P1 body-transparent sight (disguise ray): same layer fix as _can_see_player.
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(guard_eye, player_eye, 1 | 2 | 4 | 8, [get_rid(), player.get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		player.call("apply_guard_viewcone_disguise_decay", delta, true)


## Drops per-guard shared caches held for the process lifetime.
static func cleanup_static_caches() -> void:
	_downed_data.clear()
	_carry_scr_cache = null
	StateTreeShadow.cleanup_static_caches()
