class_name GuardAnimationLibrary
extends RefCounted
## Real GuardEnforcer motion: resolves clips from
## res://data/generated/anims_manifest.json, parses the animation GLBs at
## runtime with GLTFDocument (the Anims folder ships without editor .import
## files, so ResourceLoader cannot open them directly), and retargets the
## Animation tracks onto the guard mesh Skeleton3D by bone name.
##
## The same retarget core is reused for the ThiefNisha first-person viewmodel
## (build_fp_player): explicit 1P clip names, root translation always
## stripped, all clips looped. See FP_CLIPS.
##
## Retarget rule: a source track `.../Skeleton3D:<bone>` is kept only when
## <bone> exists in the target skeleton; everything else (first-person `_1p`
## bones, cameras, SKEL helper nodes) is dropped and reported. Locomotion
## clips additionally drop `root` translation (in-place conversion: scripted
## velocity drives displacement, the clip must not). No motion is invented:
## if a skeleton shares no bones with a clip, the clip is skipped and the
## guard keeps its procedural fallback.

const MANIFEST_PATH := "res://data/generated/anims_manifest.json"
const ANIM_BASE := "res://assets/ue/Anims/"

# Explicit clip names per weapon set, in priority order. Regex patterns in
# ROLE_PATTERNS are the fallback when an explicit name is absent.
const CLUB_CLIPS := {
	"neutral_idle": ["AN_GuardEnforcer_NeutralFresh_Idle"],
	"neutral_walk": ["AN_GuardEnforcer_NeutralFresh_Walk_F"],
	"suspicious_idle": ["AN_GuardEnforcer_Suspicious_Idle"],
	"suspicious_walk": ["AN_GuardEnforcer_Suspicious_Walk_F"],
	"alert_idle": ["AN_GuardEnforcer_Club_Alert_Idle"],
	"alert_run": ["AN_GuardEnforcer_Club_Alert_Run_F"],
	"attack": ["AN_GuardEnforcer_Club_Attack_Light_A_Montage"],
	"search": ["AN_GuardEnforcer_Club_VigilantSuspicious_Search"],
	"knockdown": ["AN_GuardEnforcer_Club_Knockdown_Prone__Idle"],
	"slip": ["AN_GuardEnforcer_Slip_MagicSlime_Montage"],
	"takedown_vic": ["AN_StealthTakedown_GuardEnforcer__Vic_Montage", "AN_StealthTakedown_GuardEnforcer__Vic", "AN_TakedownOverhead_Behind_Montage", "AN_TakedownOverhead_Behind", "AN_TakedownOverhead_Front_Montage", "AN_TakedownOverhead_Front"],
}
const HA_CLIPS := {
	"neutral_idle": ["AN_GE_HA_NeutralFresh_Idle"],
	"neutral_walk": ["AN_GE_HA_NeutralFresh_Walk_F"],
	"suspicious_idle": ["AN_GE_HA_Suspicious_Idle"],
	"suspicious_walk": ["AN_GE_HA_Suspicious_Walk_F"],
	"alert_idle": ["AN_GE_HA_Alert_Idle"],
	"alert_run": ["AN_GE_HA_Alert_Run_F"],
	"attack": ["AN_GuardEnforcer_Club_Attack_Light_A_Montage"],
	"search": ["AN_Hauntstable_VigilantSuspicious_Search_Montage"],
	"knockdown": ["AN_GuardEnforcer_Club_Knockdown_Prone__Idle"],
	"slip": ["AN_GuardEnforcer_Slip_MagicSlime_Montage"],
	"takedown_vic": ["AN_StealthTakedown_GuardEnforcer__Vic_Montage", "AN_StealthTakedown_GuardEnforcer__Vic", "AN_TakedownOverhead_Behind_Montage", "AN_TakedownOverhead_Behind", "AN_TakedownOverhead_Front_Montage", "AN_TakedownOverhead_Front"],
}
const LANTERN_CLIPS := {
	"neutral_idle": ["AN_GuardEnforcer_Lantern_NeutralFresh_Idle"],
	"neutral_walk": ["AN_GuardEnforcer_Lantern_NeutralFresh_Walk_F"],
	"suspicious_idle": ["AN_GuardEnforcer_Lantern_Suspicious_Idle"],
	"suspicious_walk": ["AN_GuardEnforcer_Lantern_Suspicious_Walk_F"],
	"alert_idle": ["AN_GuardEnforcer_Lantern_Alert_Idle"],
	"alert_run": ["AN_GuardEnforcer_Lantern_Alert_Run__F", "AN_GuardEnforcer_Lantern_Alert_Run_F"],
	"attack": ["AN_GuardEnforcer_Club_Attack_Light_A_Montage"],
	"search": ["AN_GuardEnforcer_Lantern_VigilantAlert_Search", "AN_GuardEnforcer_Lantern_MindfulSuspicious_Search", "AN_GuardEnforcer_Lantern_VigilantSuspicious_Search"],
	"knockdown": ["AN_GuardEnforcer_Club_Knockdown_Prone__Idle"],
	"slip": ["AN_GuardEnforcer_Slip_MagicSlime_Montage"],
	"takedown_vic": ["AN_StealthTakedown_GuardEnforcer__Vic_Montage", "AN_StealthTakedown_GuardEnforcer__Vic", "AN_TakedownOverhead_Behind_Montage", "AN_TakedownOverhead_Behind", "AN_TakedownOverhead_Front_Montage", "AN_TakedownOverhead_Front"],
}
const ROLE_ORDER: Array[String] = [
	"neutral_idle", "neutral_walk", "suspicious_idle", "suspicious_walk",
	"alert_idle", "alert_run", "attack", "search", "knockdown", "slip",
	"takedown_vic",
]
const ROLE_PATTERNS := {
	"neutral_idle": "(?i)neutral.*idle",
	"suspicious_idle": "(?i)suspicious.*idle",
	"alert_idle": "(?i)alert.*idle",
	"neutral_walk": "(?i)neutral.*walk[^_]*_F$",
	"suspicious_walk": "(?i)suspicious.*walk[^_]*_F$",
	"alert_run": "(?i)alert.*run[^_]*_F$",
	"attack": "(?i)attack.*light_a.*montage",
	"search": "(?i)(vIGILANT|mindful).*search$",
	"knockdown": "(?i)knockdown.*prone.*idle",
	"slip": "(?i)slip.*magicslime.*montage",
	"takedown_vic": "(?i)(stealthtakedown.*vic|takedownoverhead.*(behind|front|left|right)).*montage",
}
# Roles whose `root`-bone translation is stripped (in-place locomotion).
const STRIP_ROOT_TRANSLATION: Array[String] = ["neutral_walk", "suspicious_walk", "alert_run"]
# First-person (ThiefNisha 1P) clip set. Explicit manifest names only: a name
# absent from the manifest is skipped and the caller keeps its procedural
# fallback. No motion is invented, and no guard regex fallback applies here.
const FP_CLIPS := {
	"walk": "AN_Walk_F_1P",
	"sprint": "AN_Sprint_F_1P",
	"crouch": "AN_Crouch_F_1P",
}
const FP_ORDER: Array[String] = ["walk", "sprint", "crouch"]
# Verified 1P tool, idle, crank, action, and disguise clips (all 70/70 `_1p`
# bones in SK_ThiefNisha__BodyUpper.glb; loaded lazily via ensure_fp_clip).
const FP_TOOL_CLIPS := {
	"zipwire_idle": {"clip": "AN_ThiefNisha_Zipwire_StandIdle", "loop": true},
	"zipwire_crouch_idle": {"clip": "AN_ThiefNisha_Zipwire_Crouch_Idle", "loop": true},
	# Cast/aim/anchored pose (UE zipwire CastIdle); the relaxed idle above is
	# only for standing with the tool equipped and no cast/aim in flight.
	"zipwire_cast_idle": {"clip": "AN_ThiefNisha_Zipwire__CastIdle", "loop": true},
	"zipwire_walk": {"clip": "AN_Zipwire_Walk_F_1P", "loop": true},
	"zipwire_sprint": {"clip": "AN_Zipwire_Run_F_1P", "loop": true},
	"zipwire_crank": {"clip": "AN_ThiefNisha_Zipwire__Reload_Loop", "loop": true},
	"zipwire_cast": {"clip": "AN_ThiefNisha_Zipwire__Cast", "loop": false},
	"zipwire_travel": {"clip": "AN_Zipwire_Travel_1P", "loop": true},
	"blackjack_idle": {"clip": "AN_BlackJack__StandIdle", "loop": true},
	"blackjack_crouch_idle": {"clip": "AN_BlackJack_CrouchIdle", "loop": true},
	"blackjack_walk": {"clip": "AN_BlackJack_Walk_F", "loop": true},
	"blackjack_swing": {"clip": "AN_BlackJack_Attack_Light__Slash_R_01", "loop": false},
	"smoke_idle": {"clip": "AN_SmokeBomb__Idle", "loop": true},
	"smoke_crouch_idle": {"clip": "AN_SmokeBomb_Loco_CrouchIdle", "loop": true},
	"smoke_walk": {"clip": "AN_SmokeBomb_Loco_Walk_F", "loop": true},
	"smoke_throw": {"clip": "AN_SmokeBomb__Throw", "loop": false},
	"slithersap_idle": {"clip": "AN_Gear_Generic_InHand_R_Idle", "loop": true},
	"slithersap_crouch_idle": {"clip": "AN_Gear_Generic_InHand_R_CrouchIdle", "loop": true},
	"slithersap_throw": {"clip": "AN_Slime_Throw", "loop": false},
	"fairy_idle": {"clip": "AN_Pickpocket_StandIdle", "loop": true},
	"fairy_crouch_idle": {"clip": "AN_Pickpocket_CrouchIdle", "loop": true},
	"fairy_deploy": {"clip": "AN_Pickpocket_Deploy", "loop": false},
	"vistara_idle": {"clip": "AN_VistaraDiamond_StandIdle", "loop": true},
	"vistara_crouch_idle": {"clip": "AN_VistaraDiamond_CrouchIdle", "loop": true},
	"vistara_equip": {"clip": "AN_VistaraDiamond_Equip", "loop": false},
	"disguise_walk": {"clip": "AN_Disguise_Walk_F_1P", "loop": true},
	"disguise_sprint": {"clip": "AN_Disguise_Sprint_1P", "loop": true},
	"disguise_crouch": {"clip": "AN_Disguise_Crouch_F_1P", "loop": true},
	"disguise_crouch_idle": {"clip": "AN_Disguise_Crouch_Idle_1P", "loop": true},
	"disguise_apply": {"clip": "AN_Disguise_ApplySelf", "loop": false},
	"unarmed_idle": {"clip": "AN_ThiefNisha_Unarmed_StandIdle", "loop": true},
	# Traversal clips exist in the 995-clip manifest and retarget onto the same
	# 1P arm skeleton. They were never wired, so the arms stayed in zipwire_idle
	# through mantles/wall climbs (S15/S26 reference expects visible traversal).
	"mantle_050": {"clip": "AN_Mantle_050CM", "loop": false},
	"mantle_100": {"clip": "AN_Mantle_100CM", "loop": false},
	"mantle_150": {"clip": "AN_Mantle_150CM", "loop": false},
	"mantle_200": {"clip": "AN_Mantle_200CM", "loop": false},
	"mantle_250": {"clip": "AN_Mantle_250CM", "loop": false},
	"mantle_300": {"clip": "AN_Mantle_300CM", "loop": false},
	"climb_wall": {"clip": "AN_Climb_WallToMantle_200CM", "loop": true},
	"climb_idle": {"clip": "AN_Climb_Ledge_Idle", "loop": true},
	"climb_to_mantle": {"clip": "AN_Climb_Ledge_ToMantle", "loop": false},
	"jump_inair": {"clip": "AN_Jump_100CM__InAir", "loop": true},
	"jump_land": {"clip": "AN_Jump_100CM__Land", "loop": false},
	"zipwire_travel_up": {"clip": "AN_Zipwire_Travel_Up", "loop": true},
	"zipwire_travel_up_start": {"clip": "AN_Zipwire_Travel_Up_Start", "loop": false},
	"zipwire_travel_start": {"clip": "AN_Zipwire_Travel_Start_1P", "loop": false},
	"vault": {"clip": "AN_CrouchMantle_100", "loop": false},
}
# All three FP clips are in-place locomotion (scripted velocity drives
# displacement), so `root` translation is always stripped; all loop.
const LOOP_ROLES: Array[String] = [
	"neutral_idle", "neutral_walk", "suspicious_idle", "suspicious_walk",
	"alert_idle", "alert_run", "search", "knockdown",
]

static var _manifest_loaded: bool = false
static var _manifest_ok: bool = false
static var _manifest_by_name: Dictionary = {}
static var _manifest_entries: Array = []
# clip_name -> {"anim": Animation, "bones": PackedStringArray}
static var _source_cache: Dictionary = {}
# clip_name + "|" + skeleton node name -> Animation (retargeted)
static var _retarget_cache: Dictionary = {}

var weapon: String = "club"
var skeleton_name: String = "Skeleton3D"
var mesh_bones: PackedStringArray = []
var applied: Dictionary = {}
var anim_lengths: Dictionary = {}
var missing_roles: PackedStringArray = []
var _mesh_local: Dictionary = {}
var _mesh_parents: Dictionary = {}
var _mesh_global: Dictionary = {}


static func load_manifest() -> bool:
	if _manifest_loaded:
		return _manifest_ok
	_manifest_loaded = true
	_manifest_ok = false
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("GuardAnimationLibrary: manifest missing: " + MANIFEST_PATH)
		return false
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		push_warning("GuardAnimationLibrary: cannot open manifest")
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("GuardAnimationLibrary: manifest JSON is not a dictionary")
		return false
	var entries = (parsed as Dictionary).get("entries", [])
	if not (entries is Array):
		return false
	_manifest_entries = (entries as Array).duplicate()
	for e in _manifest_entries:
		if e is Dictionary:
			var nm := str((e as Dictionary).get("animation", ""))
			if nm != "" and not _manifest_by_name.has(nm):
				_manifest_by_name[nm] = e
	_manifest_ok = not _manifest_by_name.is_empty()
	return _manifest_ok


static func manifest_clip_count() -> int:
	return _manifest_by_name.size()


func _role_table() -> Dictionary:
	if weapon == "hauntstable":
		return HA_CLIPS
	if weapon == "lantern":
		return LANTERN_CLIPS
	return CLUB_CLIPS


## UE weapon-set mapping (F12 ground truth): "hauntstable" -> HA_CLIPS
## (AnimSet_Guard_Hauntsable + DAM_CharacterAnimationMapping_GuardHauntsable);
## every other guard (club / ClubLantern / Security bodies) -> CLUB_CLIPS
## (AnimSet_Guard_Club + DAM_CharacterAnimationMapping_GuardBase). Retained
## approximation, not silence: AnimSet_Guard_ClubLantern authors its own
## Lantern locomotion rows (AN_GuardEnforcer_Lantern_* in anims_manifest.json)
## and the Security SK has no Security-specific anims, so both reuse the Club
## table until a lantern/security clip table is authored.
func setup(p_weapon: String, skeleton: Skeleton3D) -> bool:
	if not load_manifest():
		return false
	weapon = p_weapon if p_weapon in ["hauntstable", "lantern"] else "club"
	if skeleton != null:
		skeleton_name = str(skeleton.name)
		mesh_bones = _read_bone_names(skeleton)
		_mesh_local = _read_local_rests(skeleton)
		_mesh_parents = _read_parents(skeleton)
		_mesh_global = _global_rests(_mesh_local, _mesh_parents)
	return true


static func _read_bone_names(skeleton: Skeleton3D) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(skeleton.get_bone_count()):
		out.append(skeleton.get_bone_name(i))
	return out


## Rest-space helpers. Source and mesh skeletons share bone names but were
## exported with different rest poses and units (cm vs m), so every animated
## value is converted as a deviation from its own rest pose.
static func _read_local_rests(skeleton: Skeleton3D) -> Dictionary:
	var local := {}
	for i in range(skeleton.get_bone_count()):
		local[str(skeleton.get_bone_name(i))] = skeleton.get_bone_rest(i)
	return local


static func _read_parents(skeleton: Skeleton3D) -> Dictionary:
	var parents := {}
	for i in range(skeleton.get_bone_count()):
		var p: int = skeleton.get_bone_parent(i)
		parents[str(skeleton.get_bone_name(i))] = "" if p < 0 else str(skeleton.get_bone_name(p))
	return parents


static func _global_rest_fk(bone: String, local: Dictionary, parents: Dictionary, memo: Dictionary) -> Transform3D:
	if memo.has(bone):
		return memo[bone] as Transform3D
	var g: Transform3D = local.get(bone, Transform3D.IDENTITY) as Transform3D
	var p := str(parents.get(bone, ""))
	if p != "" and local.has(p):
		g = _global_rest_fk(p, local, parents, memo) * g
	memo[bone] = g
	return g


static func _global_rests(local: Dictionary, parents: Dictionary) -> Dictionary:
	var memo := {}
	for b in local:
		_global_rest_fk(str(b), local, parents, memo)
	return memo


func has_clips() -> bool:
	return load_manifest() and not applied.is_empty()


func applied_clip_count() -> int:
	return applied.size()


## Role lookup against the retargeted table. ROLE_ORDER roles derive from the
## UE AnimSet rows (FreshNeutral / MindfulNeutral / MindfulSuspicious /
## MindfulAlert / VigilantAlert / Combat + VigilantSuspicious search) and the
## DAM GuardBase tags (Guard.Idle, Guard.Search, Guard.Attack.Ranged, Alert.*).
## Returns "" when the role did not retarget; callers keep their fallback.
func clip_for_role(role: String, _weapon: String = "") -> String:
	return str(applied.get(role, ""))


## State-machine transitions, single-sourced against the UE clip roles above.
## ST_Guard states mapped: Patrolling -> NEUTRAL, Greet/React/Intruder stims ->
## SUSPICIOUS, Raise-Alertness/Combat -> ALERTED/COMBAT (AnimSet Combat_* rows
## reuse the Club Alert locomotion: Combat_Idle = Club_Alert_Idle,
## Combat_Run = Club_Alert_Run_F), Search Defensive Locations + Move to nearby
## location / EQS (states 9-17) -> SEARCH, Unconscious -> KNOCKED_OUT.
## DAM tags: Guard.Idle (AN_GuardEnforcer_Suspicious_Idle_Montage_Shortened) is
## the tag-driven idle one-shot; the locomotion loops below are the AnimSet
## rows. DAM Guard.Search (AN_GuardEnforcer_MindfulSuspicious_Search_Montage_
## Shortened) is the stationary tag montage; the port loops the AnimSet
## VigilantSuspicious search row for the SEARCH state instead. Footage:
## KF16 (01:40.20 patrol/alert) for locomotion, KF25 (03:16.80 idle stance,
## hands behind back) for stationary search/idle, KF26 (03:20.20 grapple).
## SEARCH while moving plays suspicious_walk: ST_Guard searches fan out
## (Move to nearby location / EQS), and the search clip is stationary, so
## sliding it under scripted velocity would be wrong motion.
func clip_for_state(state_name: String, _weapon: String = "", moving: bool = false) -> String:
	match String(state_name).to_upper():
		"NEUTRAL":
			return clip_for_role("neutral_walk" if moving else "neutral_idle")
		"SUSPICIOUS":
			return clip_for_role("suspicious_walk" if moving else "suspicious_idle")
		"ALERTED", "COMBAT":
			return clip_for_role("alert_run" if moving else "alert_idle")
		"SEARCH":
			if moving:
				var walk := clip_for_role("suspicious_walk")
				if walk != "":
					return walk
			return clip_for_role("search")
		"KNOCKED_OUT":
			return clip_for_role("knockdown")
	return ""


func clip_length(key: String) -> float:
	return float(anim_lengths.get(key, 0.0))





func build_player(skeleton: Skeleton3D, skeleton_parent: Node, player_host: Node) -> AnimationPlayer:
	applied.clear()
	anim_lengths.clear()
	missing_roles.clear()
	if skeleton == null or skeleton_parent == null or player_host == null:
		return null
	if mesh_bones.is_empty():
		mesh_bones = _read_bone_names(skeleton)
	skeleton_name = str(skeleton.name)
	var player := AnimationPlayer.new()
	player.name = "GuardAnimPlayer"
	player_host.add_child(player)
	player.root_node = player.get_path_to(skeleton_parent)
	var lib := AnimationLibrary.new()
	var table := _role_table()
	for role in ROLE_ORDER:
		var clip_name := _resolve_clip(role, table)
		if clip_name == "":
			missing_roles.append(role)
			continue
		var anim := _retargeted(clip_name, role)
		if anim == null:
			missing_roles.append(role)
			continue
		lib.add_animation(role, anim)
		applied[role] = role
		anim_lengths[role] = anim.get_length()
	if lib.get_animation_list().is_empty():
		player.queue_free()
		return null
	player.add_animation_library("", lib)
	return player


func _resolve_clip(role: String, table: Dictionary) -> String:
	var explicit = table.get(role, [])
	if explicit is Array:
		for nm in (explicit as Array):
			if _manifest_by_name.has(str(nm)):
				return str(nm)
	var pattern := str(ROLE_PATTERNS.get(role, ""))
	if pattern == "":
		return ""
	var rx := RegEx.new()
	if rx.compile(pattern) != OK:
		return ""
	for e in _manifest_entries:
		if not (e is Dictionary):
			continue
		var nm := str((e as Dictionary).get("animation", ""))
		var glb := str((e as Dictionary).get("glb", ""))
		var guard_related: bool = glb.contains("GuardEnforcer") or nm.contains("GuardEnforcer") or nm.contains("GE_HA") or nm.contains("Hauntstable")
		if not guard_related:
			continue
		if rx.search(nm) != null:
			return nm
	return ""


## Builds the real-clip AnimationPlayer for the ThiefNisha 1P viewmodel,
## mirroring build_player but with the explicit FP_CLIPS table (no guard
## regex fallback, root translation always stripped, all clips looped).
## Uses similarity retargeting (use_similarity=true) so +90 deg X rest-frame
## differences between mesh and anim GLBs are properly rotated.
## Returns null when nothing retargeted so the caller keeps its procedural
## fallback.
func build_fp_player(skeleton: Skeleton3D, skeleton_parent: Node, player_host: Node) -> AnimationPlayer:
	applied.clear()
	anim_lengths.clear()
	missing_roles.clear()
	if skeleton == null or skeleton_parent == null or player_host == null:
		return null
	if mesh_bones.is_empty():
		mesh_bones = _read_bone_names(skeleton)
	skeleton_name = str(skeleton.name)
	var player := AnimationPlayer.new()
	player.name = "FPAnimPlayer"
	player_host.add_child(player)
	player.root_node = player.get_path_to(skeleton_parent)
	var lib := AnimationLibrary.new()
	for role in FP_ORDER:
		var clip_name := str(FP_CLIPS.get(role, ""))
		if clip_name == "" or not _manifest_by_name.has(clip_name):
			missing_roles.append(role)
			continue
		var anim := _retarget_general(clip_name, true, true, true)
		if anim == null:
			missing_roles.append(role)
			continue
		lib.add_animation(clip_name, anim)
		applied[role] = clip_name
		anim_lengths[role] = anim.get_length()
	if lib.get_animation_list().is_empty():
		player.queue_free()
		return null
	player.add_animation_library("", lib)
	ensure_fp_clip(player, "zipwire_idle")
	return player


func ensure_fp_clip(player: AnimationPlayer, role: String) -> String:
	if applied.has(role):
		return str(applied[role])
	if player == null or not load_manifest():
		return ""
	# D2: has_fp_role() is the single table-membership check (the applied hit
	# returned above, so reaching here with no table entry means unknown role).
	if not has_fp_role(role):
		return ""
	var clip_name := ""
	var loop := true
	if FP_TOOL_CLIPS.has(role):
		var spec: Dictionary = FP_TOOL_CLIPS[role] as Dictionary
		clip_name = str(spec.get("clip", ""))
		loop = spec.get("loop", true) == true
	else:
		clip_name = str(FP_CLIPS[role])
		loop = true
	if clip_name == "" or not _manifest_by_name.has(clip_name):
		return ""
	var anim := _retarget_general(clip_name, true, loop, true)
	if anim == null:
		return ""
	var lib: AnimationLibrary = player.get_animation_library("") if player.has_animation_library("") else null
	if lib == null:
		lib = AnimationLibrary.new()
		player.add_animation_library("", lib)
	if not lib.has_animation(clip_name):
		lib.add_animation(clip_name, anim)
	applied[role] = clip_name
	anim_lengths[role] = anim.get_length()
	return clip_name


func has_fp_role(role: String) -> bool:
	return applied.has(role) or FP_TOOL_CLIPS.has(role) or FP_CLIPS.has(role)


func fp_clip_for_role(role: String) -> String:
	if applied.has(role):
		return str(applied[role])
	if FP_TOOL_CLIPS.has(role):
		return str((FP_TOOL_CLIPS[role] as Dictionary).get("clip", ""))
	if FP_CLIPS.has(role):
		return str(FP_CLIPS[role])
	return ""


## Third-person crank entry (F13 3P form): AN_Zipwire_Crank_Montage, the 4.65 s
## full-body montage (Slot UpperBody, linked sequence AN_Zipwire__Reload).
## Distinct from FP_TOOL_CLIPS["zipwire_crank"] (the 1P reload loop
## AN_ThiefNisha_Zipwire__Reload_Loop): that entry stays untouched, and this
## table is consumed only by the thief 3P rig, never by the 1P viewmodel.
const TP_CRANK_CLIPS := {
	"zipwire_crank_3p": {"clip": "AN_Zipwire_Crank_Montage", "loop": true},
}


## Zipwire gear (tool skeletal mesh) reload clips. The gear mesh is a separate
## skeleton from the thief character: SK_Zipwire.glb carries 18 joints
## (root/base/barrel/crank/crank_arm/crank_handle/gear/arrow/spring01-03/
## blade_*/hinge_*/battery/trigger), and the UE gear montage animates exactly
## those joints (AN_ThiefNisha_Zipwire__Gear_Zipwire_Reload_Montage 4.35 s,
## 507 keys on crank_arm/gear; _Loop 1.32 s, 81 keys). The character 1P reload
## loop (FP_TOOL_CLIPS["zipwire_crank"]) and 3P body montage (TP_CRANK_CLIPS)
## stay separate; this table is consumed only by the tool's own AnimationPlayer
## so the crank/arrow/spring/blade mechanism moves with the hand.
## `start` is the full one-shot reload (4.35 s), `loop` the sustained crank
## cycle (1.32 s at ~1.5 rev/s). Both are authored for the same Zipwire rest
## skeleton as SK_Zipwire.glb, so local rotation tracks map 1:1.
const GEAR_CLIPS := {
	"zipwire_gear_reload_start": {"clip": "AN_ThiefNisha_Zipwire__Gear_Zipwire_Reload_Montage", "loop": false},
	"zipwire_gear_reload_loop": {"clip": "AN_ThiefNisha_Zipwire__Gear_Zipwire_Reload_Loop", "loop": true},
}


## Lazily retargets a zipwire gear clip onto the tool skeleton this instance
## was setup() with (mirrors ensure_fp_clip / ensure_tp_crank_clip). Source and
## target are the same SKEL_Zipwire skeleton exported at different unit/root
## frames, so this uses the same-skeleton rotation retarget below (not the
## cross-rig similarity path). Returns the animation name, or "" when the
## manifest lacks the clip or the skeletons share no bones. Dedicated library
## instance bound to the tool skeleton only (never the 1P/3P character instances).
func ensure_gear_clip(player: AnimationPlayer, role: String) -> String:
	if applied.has(role):
		return str(applied[role])
	if player == null or not load_manifest():
		return ""
	if not GEAR_CLIPS.has(role):
		return ""
	var spec: Dictionary = GEAR_CLIPS[role] as Dictionary
	var clip_name := str(spec.get("clip", ""))
	var loop: bool = spec.get("loop", true) == true
	if clip_name == "" or not _manifest_by_name.has(clip_name):
		return ""
	var anim := _retarget_gear_clip(clip_name, loop)
	if anim == null:
		return ""
	var lib: AnimationLibrary = player.get_animation_library("") if player.has_animation_library("") else null
	if lib == null:
		lib = AnimationLibrary.new()
		player.add_animation_library("", lib)
	if not lib.has_animation(clip_name):
		lib.add_animation(clip_name, anim)
	applied[role] = clip_name
	anim_lengths[role] = anim.get_length()
	return clip_name


## Synced takedown attacker entries (thief 3P form). Primary is the thief-side
## BlackJack stealth pair vs GuardEnforcer (AN_BlackJack_StealthTakedown__
## GuardEnforcer_FromBehind_Montage); alternates are the base Synced stealth
## Atk and the overhead front. Consumed only by the thief 3P rig via
## ensure_tp_takedown_atk_clip, never by the 1P viewmodel or the guard
## tables above. Manifest + GLB cites in task-9 evidence; Attack/unused
## quarantine clips (AN_Takedown_Fall*_Vic, AN_Takedown_Guard_Heavy_Front_Atk,
## AN_BlackJack_Takedown_In/Loop) are NOT listed here.
const TP_TAKEDOWN_CLIPS := {
	"takedown_atk_3p": {"clip": "AN_BlackJack_StealthTakedown__GuardEnforcer_FromBehind_Montage", "loop": false},
	"takedown_atk_stealth_3p": {"clip": "AN_StealthTakedown_GuardEnforcer__Atk_Montage", "loop": false},
	"takedown_atk_overhead_3p": {"clip": "AN_TakedownOverhead_Front_Montage", "loop": false},
}


## Lazily retargets the 3P crank montage onto the 3P skeleton this instance
## was setup() with (mirrors ensure_fp_clip for the single 3P crank role;
## similarity retarget matches the thief-skeleton precedent in
## build_fp_player/ensure_fp_clip). Returns the animation name, or "" when
## the manifest lacks the clip or the skeletons share no bones. The caller
## must use a dedicated library instance bound to the 3P skeleton: sharing
## the 1P instance would pollute its applied map with 3P bones.
func ensure_tp_crank_clip(player: AnimationPlayer) -> String:
	if applied.has("zipwire_crank_3p"):
		return str(applied["zipwire_crank_3p"])
	if player == null or not load_manifest():
		return ""
	var spec: Dictionary = TP_CRANK_CLIPS["zipwire_crank_3p"] as Dictionary
	var clip_name := str(spec.get("clip", ""))
	if clip_name == "" or not _manifest_by_name.has(clip_name):
		return ""
	var anim := _retarget_general(clip_name, true, true, true)
	if anim == null:
		return ""
	var lib: AnimationLibrary = player.get_animation_library("") if player.has_animation_library("") else null
	if lib == null:
		lib = AnimationLibrary.new()
		player.add_animation_library("", lib)
	if not lib.has_animation(clip_name):
		lib.add_animation(clip_name, anim)
	applied["zipwire_crank_3p"] = clip_name
	anim_lengths["zipwire_crank_3p"] = anim.get_length()
	return clip_name


## Lazily retargets the 3P takedown attacker montage onto the 3P skeleton
## this instance was setup() with (mirrors ensure_tp_crank_clip; one-shot,
## root stripped in-place, similarity retarget for the thief skeleton).
## role defaults to the BlackJack GuardEnforcer FromBehind pair; alternates
## are TP_TAKEDOWN_CLIPS keys. Returns the animation name, or "" when the
## manifest lacks the clip or the skeletons share no bones. Dedicated library
## instance bound to the 3P skeleton only (never the 1P instance).
func ensure_tp_takedown_atk_clip(player: AnimationPlayer, role: String = "takedown_atk_3p") -> String:
	if applied.has(role):
		return str(applied[role])
	if player == null or not load_manifest():
		return ""
	if not TP_TAKEDOWN_CLIPS.has(role):
		return ""
	var spec: Dictionary = TP_TAKEDOWN_CLIPS[role] as Dictionary
	var clip_name := str(spec.get("clip", ""))
	if clip_name == "" or not _manifest_by_name.has(clip_name):
		return ""
	var anim := _retarget_general(clip_name, true, false, true)
	if anim == null:
		return ""
	var lib: AnimationLibrary = player.get_animation_library("") if player.has_animation_library("") else null
	if lib == null:
		lib = AnimationLibrary.new()
		player.add_animation_library("", lib)
	if not lib.has_animation(clip_name):
		lib.add_animation(clip_name, anim)
	applied[role] = clip_name
	anim_lengths[role] = anim.get_length()
	return clip_name


func _retargeted(clip_name: String, role: String) -> Animation:
	return _retarget_general(clip_name, STRIP_ROOT_TRANSLATION.has(role), LOOP_ROLES.has(role), true)


## Same-skeleton retarget for the zipwire gear (SK_Zipwire -> SK_Zipwire).
## The Anims GLB and the mesh GLB share every local bone rest except the root
## (+90 deg X in the imported mesh skeleton, -90 deg X instance rotation) and
## crank (-19.5 deg X static roll), so the identity that must be preserved is
## the *bind-relative* local pose:
##   pose_delta = anim_local * source_rest_local^-1
## Only rotation tracks are mapped: the exporter's translation/scale channels
## are written in an absolute node space whose rest differs from the skin bind
## rest (e.g. crank_arm track 5.25 cm vs bind 6.0 cm), so replaying them would
## translate the mechanism off its pivots. The UE reload's visible motion is
## rotational (crank/gear/arrow/blades); one-key rotation tracks are skipped so
## the crank bind roll is not double-applied.
## The generic similarity retarget rotates the crank axis from local +Y into
## local +Z because it compensates the root export difference; that is correct
## for cross-rig character retargets but wrong for this same-skeleton pair.
func _retarget_gear_clip(clip_name: String, loop: bool) -> Animation:
	var key := clip_name + "|gear|" + skeleton_name
	if _retarget_cache.has(key):
		return _retarget_cache[key] as Animation
	var info := _load_source(clip_name)
	if info.is_empty():
		return null
	var src := info["anim"] as Animation
	if src == null:
		return null
	var src_local := info["src_local"] as Dictionary
	if src_local.is_empty() or _mesh_local.is_empty():
		return null
	var mesh_set := {}
	for b in mesh_bones:
		mesh_set[str(b)] = true
	var out := Animation.new()
	out.set_length(src.get_length())
	out.set_step(src.get_step())
	for ti in range(src.get_track_count()):
		var path: NodePath = src.track_get_path(ti)
		if path.get_subname_count() == 0:
			continue
		if src.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := str(path.get_subname(0))
		if not mesh_set.has(bone) or not src_local.has(bone):
			continue
		if src.track_get_key_count(ti) <= 1:
			continue
		var nti: int = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(nti, NodePath(skeleton_name + ":" + bone))
		out.track_set_interpolation_type(nti, src.track_get_interpolation_type(ti))
		var src_rest: Transform3D = src_local[bone] as Transform3D
		var inv_rest_q: Quaternion = src_rest.basis.get_rotation_quaternion().inverse().normalized()
		for ki in range(src.track_get_key_count(ti)):
			var kt: float = src.track_get_key_time(ti, ki)
			var kv = src.track_get_key_value(ti, ki)
			var nv = kv
			if kv is Quaternion:
				nv = ((kv as Quaternion) * inv_rest_q).normalized()
			var nki: int = out.track_insert_key(nti, kt, nv)
			out.track_set_key_transition(nti, nki, src.track_get_key_transition(ti, ki))
	if out.get_track_count() == 0:
		push_warning("GuardAnimationLibrary: gear clip '" + clip_name + "' shares no rotation tracks with the tool skeleton; skipped")
		return null
	out.set_loop_mode(Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE)
	_retarget_cache[key] = out
	return out


func _retarget_general(clip_name: String, strip_root: bool, loop: bool, use_similarity: bool = true) -> Animation:
	var key := clip_name + "|" + skeleton_name + ("|sim" if use_similarity else "")
	if _retarget_cache.has(key):
		return _retarget_cache[key] as Animation
	var info := _load_source(clip_name)
	if info.is_empty():
		return null
	var src := info["anim"] as Animation
	if src == null:
		return null
	var src_local := info["src_local"] as Dictionary
	var src_global := info["src_global"] as Dictionary
	var src_parents := info["src_parents"] as Dictionary
	if src_local.is_empty() or src_global.is_empty():
		return null
	if _mesh_local.is_empty() or _mesh_global.is_empty():
		return null
	var mesh_set := {}
	for b in mesh_bones:
		mesh_set[str(b)] = true
	# Unit factor from the pelvis rest-length ratio (cm -> m).
	var k: float = 0.01
	var mrest_p = _mesh_local.get("pelvis", null)
	var arest_p = src_local.get("pelvis", null)
	if mrest_p is Transform3D and arest_p is Transform3D:
		var ml: float = (mrest_p as Transform3D).origin.length()
		var al: float = (arest_p as Transform3D).origin.length()
		if al > 0.0001 and ml > 0.0001:
			k = ml / al
	# Per-bone constants: rotation pre-rotation and parent-frame correction.
	var pre: Dictionary = {}
	for b in mesh_set:
		var bs := str(b)
		if not src_local.has(bs):
			continue
		var qm: Quaternion = ((_mesh_local[bs] as Transform3D).basis.get_rotation_quaternion()).normalized()
		var qa: Quaternion = ((src_local[bs] as Transform3D).basis.get_rotation_quaternion()).normalized()
		var mp := str(_mesh_parents.get(bs, ""))
		var sp := str(src_parents.get(bs, ""))
		var rm := Quaternion.IDENTITY
		var ra := Quaternion.IDENTITY
		if mp != "" and _mesh_global.has(mp):
			rm = ((_mesh_global[mp] as Transform3D).basis.get_rotation_quaternion()).normalized()
		if sp != "" and src_global.has(sp):
			ra = ((src_global[sp] as Transform3D).basis.get_rotation_quaternion()).normalized()
		if use_similarity:
			var gm_b: Quaternion = ((_mesh_global[bs] as Transform3D).basis.get_rotation_quaternion()).normalized() if _mesh_global.has(bs) else Quaternion.IDENTITY
			var ga_b: Quaternion = ((src_global[bs] as Transform3D).basis.get_rotation_quaternion()).normalized() if src_global.has(bs) else Quaternion.IDENTITY
			pre[bs] = {
				"q_left": (rm.inverse() * ra).normalized(),
				"q_right": (ga_b.inverse() * gm_b).normalized(),
				"corr": (rm.inverse() * ra).normalized(),
				"pa": (src_local[bs] as Transform3D).origin,
				"pm": (_mesh_local[bs] as Transform3D).origin,
			}
		else:
			pre[bs] = {
				"q": (qm * qa.inverse()).normalized(),
				"corr": (rm * ra.inverse()).normalized(),
				"pa": (src_local[bs] as Transform3D).origin,
				"pm": (_mesh_local[bs] as Transform3D).origin,
			}
	var out := Animation.new()
	out.set_length(src.get_length())
	out.set_step(src.get_step())
	for ti in range(src.get_track_count()):
		var path: NodePath = src.track_get_path(ti)
		if path.get_subname_count() == 0:
			continue
		var bone := str(path.get_subname(0))
		if not mesh_set.has(bone) or not pre.has(bone):
			continue
		if strip_root and bone == "root" and src.track_get_type(ti) == Animation.TYPE_POSITION_3D:
			continue
		var ttype: int = src.track_get_type(ti)
		var nti: int = out.add_track(ttype)
		out.track_set_path(nti, NodePath(skeleton_name + ":" + bone))
		out.track_set_interpolation_type(nti, src.track_get_interpolation_type(ti))
		var c: Dictionary = pre[bone] as Dictionary
		for ki in range(src.track_get_key_count(ti)):
			var kt: float = src.track_get_key_time(ti, ki)
			var kv = src.track_get_key_value(ti, ki)
			var nv = kv
			if ttype == Animation.TYPE_POSITION_3D and kv is Vector3:
				var off: Vector3 = ((kv as Vector3) - (c["pa"] as Vector3)) * k
				nv = (c["pm"] as Vector3) + ((c["corr"] as Quaternion) * off)
			elif ttype == Animation.TYPE_ROTATION_3D and kv is Quaternion:
				if use_similarity:
					nv = ((c["q_left"] as Quaternion) * (kv as Quaternion) * (c["q_right"] as Quaternion)).normalized()
				else:
					nv = ((c["q"] as Quaternion) * (kv as Quaternion)).normalized()
			var nki: int = out.track_insert_key(nti, kt, nv)
			out.track_set_key_transition(nti, nki, src.track_get_key_transition(ti, ki))
	if out.get_track_count() == 0:
		push_warning("GuardAnimationLibrary: clip '" + clip_name + "' shares no bones with skeleton; skipped (procedural fallback kept)")
		return null
	if loop:
		out.set_loop_mode(Animation.LOOP_LINEAR)
	else:
		out.set_loop_mode(Animation.LOOP_NONE)
	_retarget_cache[key] = out
	return out


# Verified GLB-internal take names (the importer keeps the take name, which
# can differ from the manifest stem derived from the filename). Consulted by
# _pick_named_animation's exact pass only, so the firing crank path resolves
# exact with no warning while genuinely unknown clips keep the
# exact -> contains -> first chain with its warnings. Probe-verified:
# AN_ThiefNisha_Zipwire__Reload_Loop.glb carries exactly one take named
# AN_ThiefNisha_Zipwire__Reload (400 tracks, 162/162 BodyUpper bones shared).
# The 3P AN_Zipwire_Crank_Montage needs no entry: its internal name already
# matches the manifest stem exactly.
const CLIP_INTERNAL_EXACT := {
	"AN_ThiefNisha_Zipwire__Reload_Loop": "AN_ThiefNisha_Zipwire__Reload",
	"AN_ThiefNisha_Zipwire__Gear_Zipwire_Reload_Loop": "AN_ThiefNisha_Zipwire__Gear_Zipwire_Reload",
}


## Name-matched clip pick (P0-2 fix). Manifest clip names equal the GLB stem
## (e.g. AN_StealthTakedown_GuardEnforcer__Vic_Montage); a takedown GLB packing
## Atk+Vic takes must resolve the requested side, never the first animation.
## Pass 1: exact match. Pass 2: contains-match (importer renames). Else first
## with a loud warning naming the mismatch. Returns null when no player carries
## any animation.
static func _pick_named_animation(players: Array, clip_name: String) -> Animation:
	var fallback: Animation = null
	var fallback_name := ""
	var loose: Animation = null
	var loose_name := ""
	var exact_alias := str(CLIP_INTERNAL_EXACT.get(clip_name, ""))
	for p in players:
		var pl := p as AnimationPlayer
		if pl == null:
			continue
		for lib_name in pl.get_animation_library_list():
			var lib := pl.get_animation_library(lib_name)
			if lib == null:
				continue
			for an in lib.get_animation_list():
				var cand := lib.get_animation(an) as Animation
				if cand == null:
					continue
				if fallback == null:
					fallback = cand
					fallback_name = str(an)
				var an_name := str(an)
				if an_name == clip_name or (exact_alias != "" and an_name == exact_alias):
					return cand
				if loose == null and (an_name.contains(clip_name) or clip_name.contains(an_name)):
					loose = cand
					loose_name = an_name
	if loose != null:
		push_warning("GuardAnimationLibrary: clip '" + clip_name + "' has no exact animation; using contains-match '" + loose_name + "' (verify Atk vs Vic side)")
		return loose
	if fallback != null:
		push_warning("GuardAnimationLibrary: clip '" + clip_name + "' not found in GLB; using first animation '" + fallback_name + "' (wrong-side risk)")
	return fallback


static func _load_source(clip_name: String) -> Dictionary:
	if _source_cache.has(clip_name):
		return _source_cache[clip_name] as Dictionary
	var result := {}
	if not _manifest_by_name.has(clip_name):
		return result
	var entry = _manifest_by_name[clip_name]
	var res_path := ANIM_BASE + str((entry as Dictionary).get("glb", ""))
	var anim: Animation = null
	var src_local := {}
	var src_parents := {}
	var packed: PackedScene = null
	if ResourceLoader.exists(res_path):
		packed = ResourceLoader.load(res_path) as PackedScene
	if packed != null:
		var inst: Node = packed.instantiate()
		if inst != null:
			var anim_players := inst.find_children("*", "AnimationPlayer", true, false)
			anim = _pick_named_animation(anim_players, clip_name)
			for s in inst.find_children("*", "Skeleton3D", true, false):
				if src_local.is_empty():
					var ssk := s as Skeleton3D
					src_local = _read_local_rests(ssk)
					src_parents = _read_parents(ssk)
			inst.queue_free()
	if packed == null and FileAccess.file_exists(res_path):
		var f := FileAccess.open(res_path, FileAccess.READ)
		if f != null:
			var data := f.get_buffer(f.get_length())
			f.close()
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			var err: Error = doc.append_from_buffer(data, ANIM_BASE + "TAT/", state, 0)
			if err == OK:
				var gen: Node = doc.generate_scene(state, 30.0, false, true)
				if gen != null:
					var gen_players := gen.find_children("*", "AnimationPlayer", true, false)
					anim = _pick_named_animation(gen_players, clip_name)
					for s in gen.find_children("*", "Skeleton3D", true, false):
						if src_local.is_empty():
							var ssk := s as Skeleton3D
							src_local = _read_local_rests(ssk)
							src_parents = _read_parents(ssk)
					gen.queue_free()
	if anim == null or src_local.is_empty():
		push_warning("GuardAnimationLibrary: could not load clip '" + clip_name + "'")
		return result
	var src_global := _global_rests(src_local, src_parents)
	var bones := PackedStringArray()
	var seen := {}
	for ti in range(anim.get_track_count()):
		var tpath: NodePath = anim.track_get_path(ti)
		if tpath.get_subname_count() == 0:
			continue
		var bone := str(tpath.get_subname(0))
		if not seen.has(bone):
			seen[bone] = true
			bones.append(bone)
	result = {"anim": anim, "bones": bones, "src_local": src_local, "src_parents": src_parents, "src_global": src_global}
	_source_cache[clip_name] = result
	return result


## Drops manifest and retarget caches so animations do not survive shutdown.
static func cleanup_static_caches() -> void:
	_manifest_loaded = false
	_manifest_ok = false
	_manifest_by_name.clear()
	_manifest_entries.clear()
	_source_cache.clear()
	_retarget_cache.clear()
