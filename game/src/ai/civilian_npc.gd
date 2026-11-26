class_name CivilianNPC
extends CharacterBody3D
## Ambient civilian spawned from BP_MissionSpawner_Civilian_C markers. Real
## body/head skeletal meshes (see spawners.json civilian_meshes), generic
## MM_Unarmed_* locomotion retargeted by bone name through
## animation_library.gd, simple wander around the spawn point.
##
## W8 (RE-I-09): the shipped civilian is not a wander loop. `AIC_Civilian`
## authors its own sight config (`TATAISenseConfig_Sight_0`, 4 escalation rows:
## Fresh 1500/2000 cm 50 deg half-angle, Mindful 2000/2500, Vigilant 2500/3000),
## `DA_DetectionSettings_Civilian` its own detection ramps, `CT_AIStats`
## CivilianBaseHealth 40 / CivilianKnockoutDuration 60 s, and `ST_Civilian`
## (73 states) drives React to Intruder -> Flee -> Cower with
## `ST_TriggerFlee_Civilian` (17) and `ST_Subtree_Flee` (32). The port now runs:
##   WANDER -> (sees the thief OR hears a Heavy authored stimulus) -> FLEE
##          -> COWER -> WANDER (after a cooldown)
## with the authored `NPC.Yelp` (25 m) on sight and `NPC.CallForHelp` (30 m) once
## while fleeing, both real `DT_HearingStimProperties` rows, so a witness is what
## makes noise in the world instead of doing nothing.
##
## Still not implemented (honest list, not silence): clue giving
## (`ST_ClueGiving`), the EQS cower-point search (`EQS_FindCivilianCowerPoint`),
## the civ VO lines, and the `DA_DetectionSettings_Civilian` ramp values (the
## port uses one sight gate, not a staged detection meter). Those need a
## producer plus a civilian state machine; the label is in the team report.
##
## Physics: a capsule on Godot layer 4 (bit 8) means AI sight/hurt queries can hit
## them, while the player mask 1|4 never touches layer 8 and the world on layer 1
## still grounds the civilian.
##
## Documented approximations (nothing survives cooking here):
##   WALK_SPEED_M_S  = 1.4 m/s wander speed.
##   FLEE_SPEED_M_S  = 3.2 m/s -- no authored civilian run speed; the authored
##   DA_AIStatesToSpeed rows cover guards and the Hauntstable only.
##   No CivFemale clips exist in the animation manifest, so female civilians
##   use the same generic MM_Unarmed_* clips; when a clip shares no bones
##   with the civilian skeleton it is skipped and the civilian holds rest
##   pose with a procedural position bob.
##
## W10-A2: the body/head GLBs face +Z while this actor's forward is -Z (see
## _build_meshes), and the two GLBs are dressed separately because they carry
## different authored slot lists (body 3, female head 6, male head 7). Sight uses
## the authored frustum from `SightModel.eye_position()` but the occlusion ray
## leaves `SightModel.head_position()`.

const AnimLib := preload("res://src/core/animation_library.gd")
const HearingData := preload("res://src/ai/hearing_data.gd")
const SightModel := preload("res://src/ai/sight_model.gd")
const NavSteering := preload("res://src/ai/nav_steering.gd")
## Standalone prop material binding (W10-A2): the civilian GLBs ship no images,
## so an unbound body/head renders the glTF default white.
const LevelLoaderScript := preload("res://src/core/level_loader.gd")

## APPROXIMATION: no UE civilian walk-speed source.
const WALK_SPEED_M_S: float = 1.4
## APPROXIMATION: no authored civilian run speed (see header).
const FLEE_SPEED_M_S: float = 3.2
const WANDER_RADIUS_M: float = 6.0
const IDLE_MIN_S: float = 2.0
const IDLE_MAX_S: float = 5.0
const ARRIVE_DIST_M: float = 0.4
const STUCK_TIMEOUT_S: float = 8.0
const MAX_TARGET_ATTEMPTS: int = 8

## Authored civilian stats (CT_AIStats CivilianBaseHealth / CivilianKnockoutDuration).
const CIVILIAN_MAX_HP: float = 40.0
const CIVILIAN_KNOCKOUT_S: float = 60.0
const CIVILIAN_REGEN_PER_S: float = 5.0

## Behaviour timings. The authored state tree owns the structure (React to
## Intruder -> Flee Behavior -> In Smoke/Unconscious); the durations are port
## tuning with no authored seconds, so they are named here, not scattered.
const SIGHT_INTERVAL_S: float = 0.25
const FLEE_SECONDS: float = 6.0
const COWER_SECONDS: float = 8.0
const CALM_COOLDOWN_S: float = 20.0
const CALL_HELP_DELAY_S: float = 1.5

const STATE_WANDER: String = "wander"
const STATE_FLEE: String = "flee"
const STATE_COWER: String = "cower"
const STATE_DOWNED: String = "downed"

enum Mode { WANDER, FLEE, COWER, DOWNED }

## Generic clips (manifest-verified names). IdleBreak_Fidget is the only
## non-pose generic idle in the MM_Unarmed set; the AO_CC entries are
## two-frame aim poses, not locomotion idles.
const IDLE_CLIP: String = "MM_Unarmed_IdleBreak_Fidget"
const WALK_CLIP: String = "MM_Unarmed_Walk_Fwd"

## Navmesh queries before the first map sync log an engine ERROR
## ("navigation map query failed ... before first map synchronization").
## The snap is deferred until NavigationServer3D has synced once
## (map iteration id > 0); targets fail open meanwhile. Exactly one loud
## warning is kept for the first pre-sync query that still lands; the rest
## are counted silently via nav_pre_sync_deferred().
static var _nav_pre_sync_warned: bool = false
static var _nav_pre_sync_deferred: int = 0

var body_res_path: String = ""
var head_res_path: String = ""
var wander_center: Vector3 = Vector3.ZERO

var _target: Vector3 = Vector3.ZERO
var _idle_ttl: float = 0.0
var _stuck_ttl: float = 8.0
var _anim_player: AnimationPlayer = null
var _has_anims: bool = false
var _bob_phase: float = 0.0
var _skel: Skeleton3D = null
## Surface census of the last _build_meshes() bind (see material_bind_stats()).
var _material_stats: Dictionary = {"total": 0, "bound": 0, "textured": 0, "default_white": 0}

## W8 authored civilian behaviour state.
var mode: int = Mode.WANDER
var health: float = CIVILIAN_MAX_HP
var mode_timer: float = 0.0
var _sight_timer: float = 0.0
var _calm_cooldown: float = 0.0
var _called_help: bool = false
var _flee_from: Vector3 = Vector3.ZERO
var _nav: NavSteering = NavSteering.new()
var yelps: int = 0
var last_sight_distance_m: float = -1.0


## Must be called before add_child.
func setup(p_body: String, p_head: String, p_spawn: Vector3) -> void:
	body_res_path = p_body
	head_res_path = p_head
	wander_center = p_spawn
	_target = p_spawn


func _ready() -> void:
	add_to_group("civilians")
	# Godot layer 4 (bit value 8): civilians occupy space for AI sight/hearing
	# ray masks that include layer 8, while the player mask (1|4) still walks
	# through them and their own mask (1) keeps the world grounding them. The
	# capsule was missing entirely, so civilians were ghosts for every physics
	# query. Authored art is ~1.7 m tall; radius 0.35 m, centred at 0.85 m puts
	# the capsule bottom exactly on the civilian origin (floor).
	collision_layer = 8
	collision_mask = 1
	var col := CollisionShape3D.new()
	col.name = "CivilianCollision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	col.position = Vector3(0.0, 0.85, 0.0)
	add_child(col)
	_build_meshes()
	_pick_new_target()
	_idle_ttl = randf_range(0.5, 2.0)
	_nav.setup(self)
	if NoiseBus != null:
		NoiseBus.noise_record_emitted.connect(_on_noise_record)


## Authored civilian sight row (AIC_Civilian, Fresh row while calm). Falls back
## to the documented asset values via SightModel until T01 extracts them.
func sight_row() -> Dictionary:
	return SightModel.row("civilian", "Fresh")


func state_name() -> String:
	match mode:
		Mode.FLEE:
			return STATE_FLEE
		Mode.COWER:
			return STATE_COWER
		Mode.DOWNED:
			return STATE_DOWNED
	return STATE_WANDER


func is_alarmed() -> bool:
	return mode == Mode.FLEE or mode == Mode.COWER


## 40 HP / 60 s knockout (CT_AIStats CivilianBaseHealth, CivilianKnockoutDuration).
## The civilian has no combat role, so damage means "seen a fight" -> down.
func take_damage(amount: float, _source: String = "") -> void:
	if mode == Mode.DOWNED:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_enter_downed()


func take_knockout(dmg: float) -> void:
	take_damage(dmg)


func _enter_downed() -> void:
	mode = Mode.DOWNED
	mode_timer = CIVILIAN_KNOCKOUT_S
	velocity = Vector3.ZERO
	_play_role("idle")


func _wake_from_downed() -> void:
	health = CIVILIAN_MAX_HP
	mode = Mode.COWER
	mode_timer = COWER_SECONDS


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
	# W10-A2 measured: the civilian GLBs' front is +Z (the exported Blender/UE
	# rig), while this actor's forward convention is -Z (_face_and_move writes
	# atan2(-dir.x, -dir.z) and _can_see uses -global_transform.basis.z). Every
	# civilian therefore walked and looked backwards. Rotate the shared MeshRoot
	# -- not the CharacterBody3D (the sight cone and movement would turn with
	# it), not one MeshInstance3D (skinning follows the Skeleton3D), and not only
	# the body instance (the grafted head would stay backwards).
	root.rotation.y = PI
	var body_inst: Node = null
	if body_res_path != "" and ResourceLoader.exists(body_res_path):
		var packed := ResourceLoader.load(body_res_path) as PackedScene
		if packed != null:
			body_inst = packed.instantiate()
			root.add_child(body_inst)
	_skel = _find_skeleton(root)
	var head_inst: Node = null
	if head_res_path != "" and ResourceLoader.exists(head_res_path):
		var head_packed := ResourceLoader.load(head_res_path) as PackedScene
		if head_packed != null:
			head_inst = head_packed.instantiate() as Node
			if head_inst != null:
				root.add_child(head_inst)
	# Dress both GLBs after add_child (bind_prop_scene_materials looks up the live
	# level loader in the tree) and before _graft_head_meshes (the head container
	# is freed there). Two binds, one slot list each: the body carries 3 authored
	# slots, the female head 6 and the male head 7. Binding MeshRoot with one path
	# would apply the body list to the head and leave half its surfaces white.
	_material_stats = {"total": 0, "bound": 0, "textured": 0, "default_white": 0}
	if body_inst != null:
		_bind_materials(body_inst, body_res_path)
	if head_inst != null:
		_bind_materials(head_inst, head_res_path)
	if head_inst != null:
		_graft_head_meshes(head_inst, root)
	if _skel != null:
		_setup_civilian_anims()


## Authored surface census for the last _build_meshes() bind. `total` counts
## every surface on both GLBs, `bound` those that got an authored override,
## `textured` those whose StandardMaterial3D carries an albedo texture, and
## `default_white` those still on the glTF default (no material, or no albedo
## texture with a white albedo colour). A dressed civilian reports
## total == bound == 9, textured == 8, default_white == 0 on the female rig.
func material_bind_stats() -> Dictionary:
	return _material_stats.duplicate()


func _bind_materials(scene: Node, glb_path: String) -> void:
	LevelLoaderScript.bind_prop_scene_materials(scene, glb_path)
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s: int in range(mi.mesh.get_surface_count()):
			_material_stats.total += 1
			var override_mat: Material = mi.get_surface_override_material(s)
			if override_mat != null:
				_material_stats.bound += 1
			var effective: Material = override_mat if override_mat != null else mi.get_active_material(s)
			var sm := effective as StandardMaterial3D
			if sm != null:
				if sm.albedo_texture != null:
					_material_stats.textured += 1
				elif _is_white(sm.albedo_color):
					_material_stats.default_white += 1
			elif effective == null:
				_material_stats.default_white += 1


static func _is_white(c: Color) -> bool:
	return c.r >= 0.99 and c.g >= 0.99 and c.b >= 0.99


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
	# P2 civilian guard-table coupling: the old call passed the guard weapon
	# token ("club"). Civilian locomotion only uses the generic MM_Unarmed
	# retarget below, so pass the civilian token; the core library (read-only)
	# still coerces unknown weapons to its club table, behavior identical.
	var lib = AnimLib.new()
	if not lib.setup("civilian", _skel):
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


## Exact pre-sync deferral count this session (first deferral warns loudly).
static func nav_pre_sync_deferred() -> int:
	return _nav_pre_sync_deferred


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	# CT_AIStats CivilianBaseHealthRegenRate 5: an unhurt-again civilian recovers.
	if health < CIVILIAN_MAX_HP and mode != Mode.DOWNED:
		health = minf(CIVILIAN_MAX_HP, health + CIVILIAN_REGEN_PER_S * delta)
	_calm_cooldown = maxf(0.0, _calm_cooldown - delta)
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = SIGHT_INTERVAL_S
		_scan_for_thief()
	match mode:
		Mode.DOWNED:
			mode_timer -= delta
			velocity.x = 0.0
			velocity.z = 0.0
			if mode_timer <= 0.0:
				_wake_from_downed()
		Mode.FLEE:
			mode_timer -= delta
			_do_flee(delta)
			if mode_timer <= CALL_HELP_DELAY_S and not _called_help:
				# ST_Subtree_Flee: the civilian calls for help once while running.
				_called_help = true
				NoiseBus.emit_noise(global_position, 30.0, self, "npc_call_help")
			if mode_timer <= 0.0:
				mode = Mode.COWER
				mode_timer = COWER_SECONDS
				_play_role("idle")
		Mode.COWER:
			mode_timer -= delta
			velocity.x = 0.0
			velocity.z = 0.0
			_play_role("idle")
			_rest_bob(delta)
			if mode_timer <= 0.0:
				mode = Mode.WANDER
				_calm_cooldown = CALM_COOLDOWN_S
				_pick_new_target()
		_:
			_do_wander(delta)
	move_and_slide()


## Calm wander loop (the pre-W8 behaviour, unchanged except for the nav helper).
func _do_wander(delta: float) -> void:
	if _idle_ttl > 0.0:
		_idle_ttl -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_play_role("idle")
		_rest_bob(delta)
		if _idle_ttl <= 0.0:
			_pick_new_target()
		return
	var to: Vector3 = _target - global_position
	to.y = 0.0
	if to.length() < ARRIVE_DIST_M:
		_idle_ttl = randf_range(IDLE_MIN_S, IDLE_MAX_S)
		_pick_new_target()
		_play_role("idle")
		return
	_stuck_ttl -= delta
	if _stuck_ttl <= 0.0:
		_idle_ttl = randf_range(0.5, 1.5)
		_pick_new_target()
		_play_role("idle")
		return
	_face_and_move(_nav.step_towards(_target), WALK_SPEED_M_S, delta)
	_play_role("walk")
	_rest_bob(delta)


## FLEE: run directly away from the threat, with the same navigation helper.
func _do_flee(delta: float) -> void:
	var away: Vector3 = global_position - _flee_from
	away.y = 0.0
	if away.length() < 0.1:
		away = global_transform.basis.z
	var target: Vector3 = global_position + away.normalized() * 4.0
	_face_and_move(_nav.step_towards(target), FLEE_SPEED_M_S, delta)
	_play_role("walk")


func _face_and_move(dir: Vector3, speed: float, delta: float) -> void:
	if dir.length() < 0.0001:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 6.0, 0.0, 1.0))


## Authored civilian sight (AIC_Civilian Fresh: 15 m, 50 deg half-angle, POV
## 1.2 m, near clip 1.5 m, aspect 2.0, pitch -20 deg). Astral and disguised
## thieves are not recognised: the civilian has no disguise detection row.
func _scan_for_thief() -> void:
	if mode == Mode.DOWNED or _calm_cooldown > 0.0:
		return
	if mode != Mode.WANDER:
		return
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group("player"):
		var player: CharacterBody3D = node as CharacterBody3D
		if player == null or not is_instance_valid(player):
			continue
		if _is_hidden_from_civilians(player):
			continue
		if not _can_see(player):
			continue
		_start_flee(player.global_position)
		return


func _is_hidden_from_civilians(player: CharacterBody3D) -> bool:
	if _bool_property(player, "astral_active"):
		return true
	if _bool_property(player, "disguise_active"):
		return true
	return false


func _can_see(player: CharacterBody3D) -> bool:
	var row: Dictionary = sight_row()
	var eye: Vector3 = SightModel.eye_position(self, row)
	var to_target: Vector3 = SightModel.target_point(player) - eye
	if to_target.length() > float(row.get("sight_radius_m", 15.0)):
		return false
	if not SightModel.frustum_admits(row, to_target, -global_transform.basis.z):
		return false
	var world: World3D = get_world_3d()
	if world == null:
		return true
	# W10-A2 measured: the authored POV backward offset (1.2 m) orients the
	# frustum; it must not move the occlusion ray. Casting from eye_position()
	# started the ray behind the head, so a wall 0.6 m behind the civilian
	# blocked a player 4 m in front. The ray leaves the model head, same
	# contract as guard_ai.
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		SightModel.head_position(self), SightModel.target_point(player), 1 | 2 | 4, [get_rid(), player.get_rid()])
	if not world.direct_space_state.intersect_ray(q).is_empty():
		return false
	last_sight_distance_m = global_position.distance_to(player.global_position)
	return true


## Witness reaction: yelp (authored NPC.Yelp, 25 m Heavy Long) then run.
func _start_flee(threat: Vector3) -> void:
	if mode == Mode.FLEE or mode == Mode.DOWNED:
		return
	mode = Mode.FLEE
	mode_timer = FLEE_SECONDS
	_flee_from = threat
	_called_help = false
	yelps += 1
	NoiseBus.emit_noise(global_position, 25.0, self, "npc_yelp")


## Authored hearing: a Heavy stimulus inside its authored radius (capped by the
## civilian's own 25 m HearingRange) is enough to run. Light stimuli are ignored:
## the civilian has no investigation branch in this port.
func _on_noise_record(record: Dictionary) -> void:
	if mode == Mode.DOWNED or mode == Mode.FLEE:
		return
	var source: Node = record.get("source") as Node
	if source == self:
		return
	var stim: Dictionary = record.get("stim", {}) as Dictionary
	if stim.is_empty():
		return
	if str(stim.get("severity", "")).to_lower() != "heavy":
		return
	if not HearingData.heard_by(stim, HearingData.FACTION_NEUTRALS):
		return
	var origin: Vector3 = record.get("origin", global_position)
	var dist: float = global_position.distance_to(origin)
	var radius: float = minf(float(stim.get("max_range_m", 0.0)) * float(record.get("surface_multiplier", 1.0)), 25.0)
	if dist > radius:
		return
	_start_flee(origin)


static func _bool_property(obj: Object, prop: String) -> bool:
	if obj == null:
		return false
	var value: Variant = obj.get(prop)
	return value is bool and value == true


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
	for i in range(MAX_TARGET_ATTEMPTS):
		var candidate := Vector3(
			wander_center.x + randf_range(-WANDER_RADIUS_M, WANDER_RADIUS_M),
			wander_center.y,
			wander_center.z + randf_range(-WANDER_RADIUS_M, WANDER_RADIUS_M)
		)
		if _is_target_valid(candidate):
			_target = candidate
			_stuck_ttl = STUCK_TIMEOUT_S
			return
	_target = wander_center
	_stuck_ttl = STUCK_TIMEOUT_S


## Rejects targets inside/through geometry (horizontal world ray) and targets
## with no floor below (vertical drop ray), then snaps to the navmesh when a
## navigation map exists. Fail-open before the civilian is inside the tree
## (e.g. setup/_ready before physics) so spawn never blocks.
func _is_target_valid(candidate: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var world := get_world_3d()
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	var h_from := wander_center + Vector3.UP * 1.0
	var h_to := candidate + Vector3.UP * 1.0
	var h_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(h_from, h_to, 1))
	if not h_hit.is_empty():
		return false
	var d_from := candidate + Vector3.UP * 1.5
	var d_to := candidate + Vector3.UP * -1.0
	var d_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(d_from, d_to, 1))
	if d_hit.is_empty():
		return false
	if world.has_method("get_navigation_map"):
		var nav_map: RID = world.get_navigation_map()
		if nav_map.is_valid():
			if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
				_nav_pre_sync_deferred += 1
				if not _nav_pre_sync_warned:
					_nav_pre_sync_warned = true
					push_warning("[civilian_npc] navmesh snap deferred: query landed before first map sync (deferred=", _nav_pre_sync_deferred, "); target fails open until sync")
				return true
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, candidate)
			var flat := Vector2(snapped.x - candidate.x, snapped.z - candidate.z)
			if flat.length() > 1.0:
				return false
	return true
