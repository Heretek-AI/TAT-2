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
}
# All three FP clips are in-place locomotion (scripted velocity drives
# displacement), so `root` translation is always stripped; all loop.
const FP_BLEND: float = 0.2
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
	weapon = "hauntstable" if p_weapon == "hauntstable" else "club"
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


func bone_report() -> Dictionary:
	var animated := {}
	for clip_name in _source_cache:
		var info = _source_cache[clip_name]
		if info is Dictionary:
			var bones = (info as Dictionary).get("bones", [])
			if bones is PackedStringArray:
				for b in (bones as PackedStringArray):
					animated[str(b)] = true
			elif bones is Array:
				for b in (bones as Array):
					animated[str(b)] = true
	var mesh_set := {}
	for b in mesh_bones:
		mesh_set[str(b)] = true
	var matched: int = 0
	var missing: Array = []
	for b in mesh_set:
		if animated.has(b):
			matched += 1
		else:
			missing.append(b)
	var extra: Array = []
	for b in animated:
		if not mesh_set.has(b):
			extra.append(b)
	return {
		"mesh_bones": mesh_set.size(),
		"anim_bones": animated.size(),
		"matched": matched,
		"missing": missing,
		"extra": extra,
	}


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
	var clip_name := ""
	var loop := true
	if FP_TOOL_CLIPS.has(role):
		var spec: Dictionary = FP_TOOL_CLIPS[role] as Dictionary
		clip_name = str(spec.get("clip", ""))
		loop = spec.get("loop", true) == true
	elif FP_CLIPS.has(role):
		clip_name = str(FP_CLIPS[role])
		loop = true
	else:
		return ""
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
	return _retarget_general(clip_name, STRIP_ROOT_TRANSLATION.has(role), LOOP_ROLES.has(role), false)


func _retarget_general(clip_name: String, strip_root: bool, loop: bool, use_similarity: bool = false) -> Animation:
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
			for p in inst.find_children("*", "AnimationPlayer", true, false):
				var pl := p as AnimationPlayer
				for lib_name in pl.get_animation_library_list():
					var lib := pl.get_animation_library(lib_name)
					for an in lib.get_animation_list():
						if anim == null:
							anim = lib.get_animation(an) as Animation
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
					for p in gen.find_children("*", "AnimationPlayer", true, false):
						var pl := p as AnimationPlayer
						for lib_name in pl.get_animation_library_list():
							var lib := pl.get_animation_library(lib_name)
							for an in lib.get_animation_list():
								if anim == null:
									anim = lib.get_animation(an) as Animation
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
