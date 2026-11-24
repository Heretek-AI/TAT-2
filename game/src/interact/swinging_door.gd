extends Node3D
## Real swinging door built from extracted UE data (one node per
## TATSwingingDoorPivotComponent, see tools/parse_tables.py).
##
## The door root sits at the authored pivot world transform (pos + basis from
## the .tatlevel.json swinging_doors entry). A child pivot node carries one
## MeshInstance3D per leaf at its authored relative transform (real GLB +
## materials resolved through the level loader's existing
## _get_mesh_and_shape/get_material_for_ue path) plus one AnimatableBody3D
## (sync_to_physics) + BoxShape3D collider per leaf, so collision rotates
## with the door. Past OPEN_DISABLE_DEG the leaf shapes are disabled
## (deferred) and the leaf layer is 0 so the open doorway never blocks;
## closing re-enables them. Frame/jamb stay StaticBody3D level collision.
## interact() toggles a 90-degree swing around the pivot's local up axis over
## ~0.4 s; only the pivot rotates (no physics teleport), closing returns to 0,
## and repeated toggles are ignored while the tween runs.
##
## Close-while-occupied contract (todo 6, behavior of record): closing only
## rotates the pivot back to 0 and re-enables the leaf shapes; occupants are
## never moved or teleported — a body standing in the doorway is simply
## overlapped by the re-enabled leaf until it steps out.

signal lockpick_updated(active: bool, progress: float, lock_level: int)

const LockableDoorScript := preload("res://src/interact/lockable_door.gd")
const _VfxManager := preload("res://src/core/vfx_manager.gd")

## Half-turn swing target in radians (90 degrees about pivot-local +Y).
const OPEN_YAW_RAD: float = PI * 0.5
## Swing duration in seconds (matches the authored door feel).
const SWING_SEC: float = 0.4
## Past this pivot yaw the open leaf must not block the doorway.
const OPEN_DISABLE_DEG: float = 70.0

var door_entry: Dictionary = {}
var level_loader: Node = null
var pivot: Node3D = null
var is_open: bool = false
@export var locked: bool = false
@export var lock_level: int = 0
var lockpick_progress: float = 0.0
var is_lockpicking: bool = false

var _valid: bool = false
var _tweening: bool = false
var _tween: Tween = null
var _lockpick_actor: Node = null
## Leaf movers toggled by open angle (frame/jamb stay static level bodies).
var _leaf_bodies: Array = []
var _leaf_disabled: bool = false


func set_locked(p_locked: bool, p_lock_level: int = 1) -> void:
	locked = p_locked
	lock_level = clampi(p_lock_level, 1, LockableDoorScript.table_max_lock_level()) if p_locked else 0
	lockpick_progress = 0.0
	is_lockpicking = false


func get_minigame_variation() -> Dictionary:
	if lock_level <= 0:
		return {}
	return LockableDoorScript.minigame_variation_for_level(lock_level, 0)


func get_minigame_track() -> Dictionary:
	if lock_level <= 0:
		return {}
	return LockableDoorScript.minigame_track_for_level(lock_level, 0)


func get_track_duration() -> float:
	return float(get_minigame_track().get("duration_s", 0.0))


## Must be called before add_child (like world_pickup.setup). Applies the
## pivot world transform immediately; visuals/colliders are built in _ready.
func configure(entry: Dictionary, loader: Node) -> void:
	door_entry = entry
	level_loader = loader
	var entry_lvl: int = int(entry.get("lock_level", 0))
	if entry.get("locked") == true or entry_lvl > 0:
		set_locked(true, maxi(entry_lvl, 1))
	var pos_arr: Array = entry.get("pos", [])
	var basis_arr: Array = entry.get("basis", [])
	if pos_arr.size() < 3 or basis_arr.size() < 9:
		return
	var b := Basis(
		Vector3(float(basis_arr[0]), float(basis_arr[3]), float(basis_arr[6])),
		Vector3(float(basis_arr[1]), float(basis_arr[4]), float(basis_arr[7])),
		Vector3(float(basis_arr[2]), float(basis_arr[5]), float(basis_arr[8]))
	).orthonormalized()
	if absf(b.determinant()) < 0.0001:
		return
	transform = Transform3D(
		b, Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	)
	_valid = true


func _ready() -> void:
	if not _valid:
		return
	add_to_group("interactables")
	add_to_group("swinging_doors")
	pivot = Node3D.new()
	pivot.name = "DoorPivot"
	add_child(pivot)
	for leaf_var in door_entry.get("leaves", []):
		if leaf_var is Dictionary:
			_build_leaf(leaf_var as Dictionary)


func _leaf_transform(leaf: Dictionary) -> Transform3D:
	var p: Array = leaf.get("rel_pos", [0.0, 0.0, 0.0])
	var b: Array = leaf.get("rel_basis", [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0])
	var basis := Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	).orthonormalized()
	if absf(basis.determinant()) < 0.0001:
		basis = Basis.IDENTITY
	return Transform3D(
		basis,
		Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() >= 3 else Vector3.ZERO
	)


## One leaf: real mesh/material from the level loader plus a BoxShape3D body
## parented to the pivot. A leaf whose mesh cannot be resolved is skipped
## (fail closed, never a placeholder box).
func _build_leaf(leaf: Dictionary) -> void:
	if level_loader == null or pivot == null:
		return
	var ue_mesh := str(leaf.get("mesh", ""))
	if ue_mesh == "" or not level_loader.has_method("_get_mesh_and_shape"):
		return
	var info: Dictionary = level_loader.call("_get_mesh_and_shape", ue_mesh)
	var mesh: Mesh = info.get("mesh") as Mesh
	if mesh == null:
		return
	var ltr := _leaf_transform(leaf)
	var sc_arr: Variant = leaf.get("rel_scale", null)
	var leaf_scale: Vector3 = Vector3.ONE
	if sc_arr is Array and (sc_arr as Array).size() >= 3:
		var sa: Array = sc_arr as Array
		leaf_scale = Vector3(maxf(absf(float(sa[0])), 0.01), maxf(absf(float(sa[1])), 0.01), maxf(absf(float(sa[2])), 0.01))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(ltr.basis.scaled(leaf_scale), ltr.origin)
	# Mirrored leaves: 36 POI + 4 vault pivots carry a negative-determinant
	# basis. UE draws those two-sided; a single-sided Godot surface culls the
	# face the player sees and the leaf disappears. The leaf-local mi basis is
	# always +1 for an identity leaf stub, so test the composed door-root x
	# leaf basis the pivot actually renders (global when the door is already
	# parented, so a mirrored host is caught; local fallback before _ready's
	# add_child path is inside the tree). Duplicate only the BaseMaterial3D
	# surfaces with culling disabled — multi-slot doors must keep per-surface
	# materials, so never use one material_override.
	var leaf_basis: Basis = mi.transform.basis
	var door_basis: Basis = global_transform.basis if is_inside_tree() else transform.basis
	if door_basis.determinant() * leaf_basis.determinant() < 0.0:
		for s: int in range(mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(s)
			if src == null:
				src = mesh.surface_get_material(s)
			var bm := src as BaseMaterial3D
			if bm == null:
				continue
			var mirrored := bm.duplicate() as BaseMaterial3D
			if mirrored == null:
				continue
			mirrored.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.set_surface_override_material(s, mirrored)
	pivot.add_child(mi)
	var aabb: AABB = mesh.get_aabb()
	var body := AnimatableBody3D.new()
	body.sync_to_physics = true
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = ltr
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(aabb.size.x * leaf_scale.x, 0.05),
		maxf(aabb.size.y * leaf_scale.y, 0.05),
		maxf(aabb.size.z * leaf_scale.z, 0.05)
	)
	cs.shape = box
	cs.position = aabb.get_center() * leaf_scale
	body.add_child(cs)
	pivot.add_child(body)
	_leaf_bodies.append(body)


## Current pivot yaw in degrees (0 = closed, 90 = fully open).
func open_angle_deg() -> float:
	if pivot == null:
		return 0.0
	return absf(rad_to_deg(pivot.rotation.y))


## Pure helper so tests can assert the 70-degree gate without physics.
func should_disable_leaf(angle_deg: float) -> bool:
	return absf(angle_deg) > OPEN_DISABLE_DEG


## Disables the leaf movers past OPEN_DISABLE_DEG (deferred + layer 0),
## re-enables on close. Frame/jamb level statics are never touched here.
func _update_leaf_collision() -> void:
	if pivot == null:
		return
	_leaf_bodies = _leaf_bodies.filter(func(b: Variant) -> bool: return is_instance_valid(b))
	var disable: bool = should_disable_leaf(open_angle_deg())
	if disable == _leaf_disabled:
		return
	_leaf_disabled = disable
	for b_var: Variant in _leaf_bodies:
		if not (b_var is AnimatableBody3D):
			continue
		var leaf: AnimatableBody3D = b_var as AnimatableBody3D
		if disable:
			leaf.set_deferred("collision_layer", 0)
			for ch: Node in leaf.get_children():
				if ch is CollisionShape3D:
					(ch as CollisionShape3D).set_deferred("disabled", true)
		else:
			leaf.set_deferred("collision_layer", 1)
			for ch2: Node in leaf.get_children():
				if ch2 is CollisionShape3D:
					(ch2 as CollisionShape3D).set_deferred("disabled", false)


func _process(_delta: float) -> void:
	if pivot != null and not _leaf_bodies.is_empty():
		_update_leaf_collision()


func get_interact_prompt() -> String:
	if locked:
		if is_lockpicking:
			return "[Picking Lock...]"
		return "[F] PICK LOCK (Lv %d)" % maxi(lock_level, 1)
	if is_open:
		return "[F] CLOSE"
	return "[F] OPEN"


## Interaction LOS point (W2): the door root is the hinge at the jamb, which
## sits inside the frame; target the average leaf centre instead.
func get_interact_point() -> Vector3:
	var acc: Vector3 = Vector3.ZERO
	var n: int = 0
	for body_var: Variant in _leaf_bodies:
		var body: Node3D = body_var as Node3D
		if body == null or not is_instance_valid(body):
			continue
		var local_center: Vector3 = Vector3.ZERO
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				local_center = (child as CollisionShape3D).position
				break
		acc += body.global_transform * local_center
		n += 1
	if n == 0:
		return global_position + Vector3.UP * 1.1
	return acc / float(n)


## KF24: closed unlocked doors stack [F] [HOLD] LOCK under the primary OPEN.
func get_interact_secondary_prompt() -> String:
	if locked or is_open or _tweening:
		return ""
	return "[F] [HOLD] LOCK"


## KF24 secondary action: hold F to lock the closed door again.
func interact_hold(actor: Node) -> void:
	if locked or is_open or _tweening:
		return
	# P2 relock downgrade fixed: the old set_locked(true, 1) reset any vault to
	# Lv1; keep the authored level like lockable_door.interact_hold does.
	set_locked(true, maxi(lock_level, 1))
	lockpick_updated.emit(false, 0.0, lock_level)
	NoiseBus.emit_noise(global_position, 3.0, _audible_source(actor), "lock")


## P1 door noise sourced self (swinging leaf): same HUD-arcs gap as the
## frame door. Emits use the stored player driver when one is
## mid-interaction (UE lockpick/door noise path).
func _noise_source() -> Node:
	if _lockpick_actor != null and is_instance_valid(_lockpick_actor):
		return _lockpick_actor
	return self


## Hold/relock path carries the actor directly (no stored driver).
func _audible_source(actor: Node) -> Node:
	if actor != null and is_instance_valid(actor):
		return actor
	return _noise_source()


func _exit_tree() -> void:
	_clear_actor_lockpicking()


func _clear_actor_lockpicking() -> void:
	is_lockpicking = false
	if _lockpick_actor != null and is_instance_valid(_lockpick_actor) and _lockpick_actor.has_method("set_lockpicking_active"):
		_lockpick_actor.call("set_lockpicking_active", false)
	_lockpick_actor = null


func _find_hud() -> Node:
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	var mission: Node = tree.get_first_node_in_group("mission")
	if mission != null:
		var h_v: Variant = mission.get("hud")
		if h_v is Node and is_instance_valid(h_v as Node):
			return h_v as Node
	var h_group: Node = tree.get_first_node_in_group("hud")
	if h_group != null and is_instance_valid(h_group):
		return h_group
	return null


func _start_swing_toggle() -> void:
	if pivot == null or _tweening:
		return
	is_open = not is_open
	_begin_swing()
	_announce_world_state()


## Starts the authored swing toward the current is_open state. Shared by local
## interaction and host-authoritative remote application (which never echoes).
func _begin_swing() -> void:
	_tweening = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var target: float = OPEN_YAW_RAD if is_open else 0.0
	_tween.tween_property(pivot, "rotation:y", target, SWING_SEC).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_on_swing_finished)


## W6b: a successful local interaction announces the new swing state. Solo play
## is a no-op; the transport decides whether this peer requests or applies.
func _announce_world_state() -> void:
	if NetManager == null or not NetManager.is_coop:
		return
	NetManager.send_world_event("open" if is_open else "close", name)


## W6b: apply the host-validated swing state on a peer. Idempotent, never
## announces, and retargets a local tween when the two peers disagree.
func apply_remote_toggle(p_open: bool) -> void:
	if pivot == null:
		return
	if is_open == p_open:
		return
	if _tweening:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tweening = false
	is_open = p_open
	_begin_swing()


func _on_lockpick_finished(success: bool, actor: Node) -> void:
	is_lockpicking = false
	if actor != null and is_instance_valid(actor) and actor.has_method("set_lockpicking_active"):
		actor.call("set_lockpicking_active", false)
	if _lockpick_actor == actor:
		_lockpick_actor = null
	if not is_inside_tree():
		return
	if success:
		locked = false
		lockpick_progress = 1.0
		lockpick_updated.emit(false, 1.0, maxi(lock_level, 1))
		NoiseBus.emit_noise(global_position, 5.5, _noise_source(), "door")
		if not is_open:
			_start_swing_toggle()
	else:
		_VfxManager.spawn_lockpick_sparks(get_parent(), global_position + Vector3(0.0, 1.1, 0.0))
		NoiseBus.emit_noise(global_position, 5.0, _noise_source(), "lockpick")
		lockpick_updated.emit(false, lockpick_progress, maxi(lock_level, 1))


func interact(actor: Node) -> void:
	if pivot == null or _tweening:
		return
	if locked:
		if is_lockpicking:
			return
		var lvl: int = clampi(maxi(lock_level, 1), 1, LockableDoorScript.table_max_lock_level())
		lock_level = lvl
		if actor != null and actor.has_method("set_lockpicking_active"):
			_lockpick_actor = actor
			actor.call("set_lockpicking_active", true)
		var hud_node: Node = _find_hud()
		if actor != null and hud_node != null and hud_node.has_method("start_lockpick_minigame"):
			is_lockpicking = true
			lockpick_updated.emit(true, lockpick_progress, lvl)
			NoiseBus.emit_noise(global_position, 4.0, _noise_source(), "lockpick")
			hud_node.call("start_lockpick_minigame", lvl, "Door Lock (Lv %d)" % lvl, func(success: bool = true) -> void:
				_on_lockpick_finished(success, actor)
			)
			return
		if actor != null and is_inside_tree():
			# Headless fallback: timed unlock so Status.Lockpicking (5.0/s) ticks.
			is_lockpicking = true
			lockpick_updated.emit(true, lockpick_progress, lvl)
			_VfxManager.spawn_lockpick_sparks(get_parent(), global_position + Vector3(0.0, 1.1, 0.0))
			NoiseBus.emit_noise(global_position, 4.0, _noise_source(), "lockpick")
			var dur: float = clampf(get_track_duration(), 0.35, 1.2)
			get_tree().create_timer(dur).timeout.connect(func() -> void:
				if is_instance_valid(self) and is_lockpicking:
					_on_lockpick_finished(true, actor)
			)
			return
		var dmg: float = LockableDoorScript.jam_damage_for_level(lvl)
		lockpick_progress = minf(1.0, lockpick_progress + 5.0 / maxf(dmg, 1.0))
		NoiseBus.emit_noise(global_position, 4.0, _noise_source(), "lockpick")
		lockpick_updated.emit(true, lockpick_progress, lvl)
		if lockpick_progress >= 1.0:
			_on_lockpick_finished(true, actor)
		return
	_start_swing_toggle()


func _on_swing_finished() -> void:
	_tweening = false
	_update_leaf_collision()
