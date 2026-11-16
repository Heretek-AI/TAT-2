class_name CivilianNPC
extends CharacterBody3D
## Ambient civilian spawned from BP_MissionSpawner_Civilian_C markers. Real
## body/head skeletal meshes (see spawners.json civilian_meshes), generic
## MM_Unarmed_* locomotion retargeted by bone name through
## animation_library.gd, simple wander around the spawn point.
##
## Non-behaviours by design: no detection, no interaction, and no collision
## with the player (layer 8 / mask 1: the player mask 1|4 never touches
## layer 8, while the world on layer 1 still grounds the civilian).
##
## Documented approximations (nothing survives cooking here):
##   WALK_SPEED_M_S  = 1.4 m/s wander speed.
##   No CivFemale clips exist in the animation manifest, so female civilians
##   use the same generic MM_Unarmed_* clips; when a clip shares no bones
##   with the civilian skeleton it is skipped and the civilian holds rest
##   pose with a procedural position bob.

const AnimLib := preload("res://src/core/animation_library.gd")

## APPROXIMATION: no UE civilian walk-speed source.
const WALK_SPEED_M_S: float = 1.4
const WANDER_RADIUS_M: float = 6.0
const IDLE_MIN_S: float = 2.0
const IDLE_MAX_S: float = 5.0
const ARRIVE_DIST_M: float = 0.4

## Generic clips (manifest-verified names). IdleBreak_Fidget is the only
## non-pose generic idle in the MM_Unarmed set; the AO_CC entries are
## two-frame aim poses, not locomotion idles.
const IDLE_CLIP: String = "MM_Unarmed_IdleBreak_Fidget"
const WALK_CLIP: String = "MM_Unarmed_Walk_Fwd"

var body_res_path: String = ""
var head_res_path: String = ""
var wander_center: Vector3 = Vector3.ZERO

var _target: Vector3 = Vector3.ZERO
var _idle_ttl: float = 0.0
var _anim_player: AnimationPlayer = null
var _has_anims: bool = false
var _bob_phase: float = 0.0
var _skel: Skeleton3D = null


## Must be called before add_child.
func setup(p_body: String, p_head: String, p_spawn: Vector3) -> void:
	body_res_path = p_body
	head_res_path = p_head
	wander_center = p_spawn
	_target = p_spawn


func _ready() -> void:
	add_to_group("civilians")
	collision_layer = 8
	collision_mask = 1
	_build_meshes()
	_pick_new_target()
	_idle_ttl = randf_range(0.5, 2.0)


func civilian_mesh_paths() -> Array[String]:
	var out: Array[String] = []
	if body_res_path != "":
		out.append(body_res_path)
	if head_res_path != "":
		out.append(head_res_path)
	return out


func _build_meshes() -> void:
	var root := Node3D.new()
	root.name = "MeshRoot"
	add_child(root)
	if body_res_path != "" and ResourceLoader.exists(body_res_path):
		var packed := ResourceLoader.load(body_res_path) as PackedScene
		if packed != null:
			root.add_child(packed.instantiate())
	_skel = _find_skeleton(root)
	if head_res_path != "" and ResourceLoader.exists(head_res_path):
		var head_packed := ResourceLoader.load(head_res_path) as PackedScene
		if head_packed != null:
			var head_inst := head_packed.instantiate() as Node
			if head_inst != null:
				root.add_child(head_inst)
				_graft_head_meshes(head_inst, root)
	if _skel != null:
		_setup_civilian_anims()


## Moves skinned head meshes onto the body skeleton so one AnimationPlayer
## drives both. When no body skeleton exists the head instance is left as
## a static child (rest pose).
func _graft_head_meshes(head_inst: Node, root: Node3D) -> void:
	if _skel == null:
		return
	var meshes: Array[Node] = head_inst.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		var mi := m as MeshInstance3D
		var prev_parent := mi.get_parent()
		if prev_parent != null:
			prev_parent.remove_child(mi)
		root.add_child(mi)
		mi.skeleton = mi.get_path_to(_skel)
		_remap_head_skin(mi)
	# Drop the now-empty head container (its own skeleton + player, if any).
	head_inst.queue_free()


## The head GLBs ship a short skeleton whose bone names differ in case from
## the full body skeleton ("Head" vs "head"); grafting the skinned head mesh
## onto the body skeleton would leave those binds unresolvable (engine
## error, collapsed vertices). Remap bind names case-insensitively onto the
## body bones; exact-name binds (e.g. the female heads) are untouched.
func _remap_head_skin(mi: MeshInstance3D) -> void:
	if mi.skin == null or _skel == null:
		return
	var body_names := {}
	for i in range(_skel.get_bone_count()):
		body_names[_skel.get_bone_name(i).to_lower()] = _skel.get_bone_name(i)
	var skin := mi.skin as Skin
	var needed := false
	for b in range(skin.get_bind_count()):
		var bn := str(skin.get_bind_name(b))
		if _skel.find_bone(bn) < 0 and body_names.has(bn.to_lower()):
			needed = true
			break
	if not needed:
		return
	var dup := skin.duplicate() as Skin
	for b2 in range(dup.get_bind_count()):
		var bn2 := str(dup.get_bind_name(b2))
		if _skel.find_bone(bn2) < 0 and body_names.has(bn2.to_lower()):
			dup.set_bind_name(b2, body_names[bn2.to_lower()])
	mi.skin = dup


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


## Retargets the generic MM_Unarmed idle/walk clips onto the civilian body
## skeleton by bone name. Clips sharing no bones are skipped (the library
## returns null and logs); the civilian then uses rest pose + bob.
func _setup_civilian_anims() -> void:
	var lib = AnimLib.new()
	if not lib.setup("club", _skel):
		return
	var idle_anim: Animation = lib._retarget_general(IDLE_CLIP, false, true)
	var walk_anim: Animation = lib._retarget_general(WALK_CLIP, true, true)
	if idle_anim == null and walk_anim == null:
		return
	var skel_parent := _skel.get_parent() as Node
	if skel_parent == null:
		return
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "CivilianAnimPlayer"
	skel_parent.add_child(_anim_player)
	_anim_player.root_node = _anim_player.get_path_to(skel_parent)
	var lib_anim := AnimationLibrary.new()
	if idle_anim != null:
		lib_anim.add_animation("idle", idle_anim)
	if walk_anim != null:
		lib_anim.add_animation("walk", walk_anim)
	_anim_player.add_animation_library("", lib_anim)
	_has_anims = true
	_anim_player.play("idle" if lib_anim.has_animation("idle") else "walk")


func has_civilian_anims() -> bool:
	return _has_anims and _anim_player != null


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	if _idle_ttl > 0.0:
		_idle_ttl -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_play_role("idle")
		_rest_bob(delta)
	else:
		var to: Vector3 = _target - global_position
		to.y = 0.0
		if to.length() < ARRIVE_DIST_M:
			_idle_ttl = randf_range(IDLE_MIN_S, IDLE_MAX_S)
			_play_role("idle")
		else:
			var dir: Vector3 = to.normalized()
			velocity.x = dir.x * WALK_SPEED_M_S
			velocity.z = dir.z * WALK_SPEED_M_S
			rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 6.0, 0.0, 1.0))
			_play_role("walk")
			_rest_bob(delta)
	move_and_slide()


## Rest-pose bob so unanimated civilians still read as alive. Runs always;
## the retargeted clips drive the bones on top when present.
func _rest_bob(delta: float) -> void:
	if _has_anims:
		return
	_bob_phase += delta * 2.2
	var root := get_node_or_null("MeshRoot") as Node3D
	if root != null:
		root.position.y = 0.02 * sin(_bob_phase)


func _play_role(role: String) -> void:
	if not _has_anims or _anim_player == null:
		return
	if not _anim_player.has_animation(role):
		return
	if _anim_player.current_animation != role or not _anim_player.is_playing():
		_anim_player.play(role, 0.3)


func _pick_new_target() -> void:
	_target = Vector3(
		wander_center.x + randf_range(-WANDER_RADIUS_M, WANDER_RADIUS_M),
		wander_center.y,
		wander_center.z + randf_range(-WANDER_RADIUS_M, WANDER_RADIUS_M)
	)
