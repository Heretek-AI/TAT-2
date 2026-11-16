class_name GuardAnimationLibrary
extends RefCounted
## Real GuardEnforcer motion: resolves clips from
## res://data/generated/anims_manifest.json, parses the animation GLBs at
## runtime with GLTFDocument (the Anims folder ships without editor .import
## files, so ResourceLoader cannot open them directly), and retargets the
## Animation tracks onto the guard mesh Skeleton3D by bone name.
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
}
const ROLE_ORDER: Array[String] = [
	"neutral_idle", "neutral_walk", "suspicious_idle", "suspicious_walk",
	"alert_idle", "alert_run", "attack", "search", "knockdown", "slip",
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
}
# Roles whose `root`-bone translation is stripped (in-place locomotion).
const STRIP_ROOT_TRANSLATION: Array[String] = ["neutral_walk", "suspicious_walk", "alert_run"]
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


func clip_for_role(role: String, _weapon: String = "") -> String:
	return str(applied.get(role, ""))


func clip_for_state(state_name: String, _weapon: String = "", moving: bool = false) -> String:
	match String(state_name).to_upper():
		"NEUTRAL":
			return clip_for_role("neutral_walk" if moving else "neutral_idle")
		"SUSPICIOUS":
			return clip_for_role("suspicious_walk" if moving else "suspicious_idle")
		"ALERTED", "COMBAT":
			return clip_for_role("alert_run" if moving else "alert_idle")
		"SEARCH":
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


func _retargeted(clip_name: String, role: String) -> Animation:
	var key := clip_name + "|" + skeleton_name
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
	var strip_root: bool = STRIP_ROOT_TRANSLATION.has(role)
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
				nv = ((c["q"] as Quaternion) * (kv as Quaternion)).normalized()
			var nki: int = out.track_insert_key(nti, kt, nv)
			out.track_set_key_transition(nti, nki, src.track_get_key_transition(ti, ki))
	if out.get_track_count() == 0:
		push_warning("GuardAnimationLibrary: clip '" + clip_name + "' shares no bones with skeleton; skipped (procedural fallback kept)")
		return null
	if LOOP_ROLES.has(role):
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
