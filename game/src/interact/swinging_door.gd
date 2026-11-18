extends Node3D
## Real swinging door built from extracted UE data (one node per
## TATSwingingDoorPivotComponent, see tools/parse_tables.py).
##
## The door root sits at the authored pivot world transform (pos + basis from
## the .tatlevel.json swinging_doors entry). A child pivot node carries one
## MeshInstance3D per leaf at its authored relative transform (real GLB +
## materials resolved through the level loader's existing
## _get_mesh_and_shape/get_material_for_ue path) plus one StaticBody3D +
## BoxShape3D collider per leaf, so collision rotates with the door.
## interact() toggles a 90-degree swing around the pivot's local up axis over
## ~0.4 s; only the pivot rotates (no physics teleport), closing returns to 0,
## and repeated toggles are ignored while the tween runs.

signal lockpick_updated(active: bool, progress: float, lock_level: int)

const LockableDoorScript := preload("res://src/interact/lockable_door.gd")
const _VfxManager := preload("res://src/core/vfx_manager.gd")

## Half-turn swing target in radians (90 degrees about pivot-local +Y).
const OPEN_YAW_RAD: float = PI * 0.5
## Swing duration in seconds (matches the authored door feel).
const SWING_SEC: float = 0.4

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
	pivot.add_child(mi)
	var aabb: AABB = mesh.get_aabb()
	var body := StaticBody3D.new()
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


func get_interact_prompt() -> String:
	if locked:
		if is_lockpicking:
			return "[Picking Lock...]"
		return "[F] PICK LOCK (Lv %d)" % maxi(lock_level, 1)
	if is_open:
		return "[F] CLOSE"
	return "[F] OPEN"


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
	_tweening = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var target: float = OPEN_YAW_RAD if is_open else 0.0
	_tween.tween_property(pivot, "rotation:y", target, SWING_SEC).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_on_swing_finished)


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
		NoiseBus.emit_noise(global_position, 5.5, self, "door")
		if not is_open:
			_start_swing_toggle()
	else:
		_VfxManager.spawn_lockpick_sparks(get_parent(), global_position + Vector3(0.0, 1.1, 0.0))
		NoiseBus.emit_noise(global_position, 5.0, self, "lockpick")
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
			NoiseBus.emit_noise(global_position, 4.0, self, "lockpick")
			hud_node.call("start_lockpick_minigame", lvl, "Door Lock (Lv %d)" % lvl, func(success: bool = true) -> void:
				_on_lockpick_finished(success, actor)
			)
			return
		if actor != null and is_inside_tree():
			# Headless fallback: timed unlock so Status.Lockpicking (5.0/s) ticks.
			is_lockpicking = true
			lockpick_updated.emit(true, lockpick_progress, lvl)
			_VfxManager.spawn_lockpick_sparks(get_parent(), global_position + Vector3(0.0, 1.1, 0.0))
			NoiseBus.emit_noise(global_position, 4.0, self, "lockpick")
			var dur: float = clampf(get_track_duration(), 0.35, 1.2)
			get_tree().create_timer(dur).timeout.connect(func() -> void:
				if is_instance_valid(self) and is_lockpicking:
					_on_lockpick_finished(true, actor)
			)
			return
		var dmg: float = LockableDoorScript.jam_damage_for_level(lvl)
		lockpick_progress = minf(1.0, lockpick_progress + 5.0 / maxf(dmg, 1.0))
		NoiseBus.emit_noise(global_position, 4.0, self, "lockpick")
		lockpick_updated.emit(true, lockpick_progress, lvl)
		if lockpick_progress >= 1.0:
			_on_lockpick_finished(true, actor)
		return
	_start_swing_toggle()


func _on_swing_finished() -> void:
	_tweening = false
