extends StaticBody3D
## Interactive door with optional lock level (1..4, using CT_LockpickDamage).
## The root StaticBody3D is the frame/jamb (kept static); the swinging leaf
## is an AnimatableBody3D (sync_to_physics) under the pivot so rotation never
## teleports physics. Past OPEN_DISABLE_DEG the leaf shapes are disabled
## (deferred) and the leaf layer is 0; closing re-enables them.

signal lockpick_updated(active: bool, progress: float, lock_level: int)

const _VfxManager = preload('res://src/core/vfx_manager.gd')
const LevelLoaderScript := preload("res://src/core/level_loader.gd")

const INTERACTABLES_PATH := "res://data/generated/gameplay/interactables.json"
## Fallbacks mirror the extracted table (CT_LockpickDamage DamageByLockLevel
## 5/10/20/40, doors MaxLockLevel 4); Lv5-6 continue the authored doubling
## (80/160, retained inference — containers accept 1-6 while the jam rows stop
## at 4). The table above wins whenever it provides the row; the JSON is
## authoritative.
const FALLBACK_JAM_DAMAGE := {1: 5.0, 2: 10.0, 3: 20.0, 4: 40.0, 5: 80.0, 6: 160.0}
## Authored door cap: BP_SwingingDoor._lockConfig.MaxLockLevel (produced into
## interactables.json doors.max_lock_level). W9-P2 B2 port decision: the dump
## has no per-instance `LockLevel`, so a record's level is its authored
## `_lockConfig.MaxLockLevel` cap clamped by this table (cap-as-level). The
## key-only door class is excluded from authored locks entirely
## (`CanBeLockpicked == false`: BP_VaultDoor_Sliding_C and the Res/FTUE
## apartment doorway) because the port ships no key inventory; see
## `swinging_door.configure` and build/qa/w9/b2-impl.md.
const FALLBACK_MAX_LOCK_LEVEL := 4
## GA_Lockpick.distance_before_cancel fallback (200 cm).
const FALLBACK_CANCEL_DISTANCE_CM := 200.0
## Past this pivot yaw the open leaf must not block the doorway.
const OPEN_DISABLE_DEG: float = 70.0

static var _interactables: Dictionary = {}


static func lockpick_table() -> Dictionary:
	if _interactables.is_empty():
		var data: Variant = null
		if FileAccess.file_exists(INTERACTABLES_PATH):
			var f: FileAccess = FileAccess.open(INTERACTABLES_PATH, FileAccess.READ)
			if f != null:
				data = JSON.parse_string(f.get_as_text())
		if data is Dictionary and (data as Dictionary).has("lockpick"):
			_interactables = (data as Dictionary)["lockpick"]
	return _interactables


static func table_max_lock_level() -> int:
	var doors: Variant = _doors_section()
	return int(doors.get("max_lock_level", FALLBACK_MAX_LOCK_LEVEL))


## Authored lockpick cancel radius in metres (GA_Lockpick
## `distance_before_cancel` = 200 cm). Walking further than this from the lock
## cancels the minigame; the shipped rule is absent from the HUD, so the lock
## owner enforces it (swinging_door / loot_container `_process`).
static func lockpick_cancel_distance_m() -> float:
	var cm_v: Variant = lockpick_table().get("distance_before_cancel", FALLBACK_CANCEL_DISTANCE_CM)
	var cm: float = float(cm_v) if cm_v is int or cm_v is float else FALLBACK_CANCEL_DISTANCE_CM
	return maxf(cm, 1.0) / 100.0


static func _doors_section() -> Dictionary:
	var data: Variant = null
	if FileAccess.file_exists(INTERACTABLES_PATH):
		var f: FileAccess = FileAccess.open(INTERACTABLES_PATH, FileAccess.READ)
		if f != null:
			data = JSON.parse_string(f.get_as_text())
	if data is Dictionary and (data as Dictionary).has("doors"):
		var doors: Variant = (data as Dictionary)["doors"]
		if doors is Dictionary:
			return doors
	return {}


static func jam_damage_for_level(lock_level: int) -> float:
	var per_level: Variant = lockpick_table().get("jam_damage_by_lock_level", {})
	if per_level is Dictionary and (per_level as Dictionary).has(str(lock_level)):
		return float((per_level as Dictionary)[str(lock_level)])
	return float(FALLBACK_JAM_DAMAGE.get(clampi(lock_level, 1, 6), 5.0))

@export var locked: bool = false
@export var lock_level: int = 1
var is_open: bool = false
var pivot: Node3D
var mesh_inst: MeshInstance3D
var lockpick_progress: float = 0.0
var is_lockpicking: bool = false
var _lockpick_actor: Node = null
## Leaf mover + shape toggled by open angle (frame root stays static).
var _leaf_body: AnimatableBody3D = null
var _leaf_shape: CollisionShape3D = null
var _leaf_disabled: bool = false


static func minigame_variation_for_level(p_lock_level: int, variant_index: int = 0) -> Dictionary:
	var lvl: int = clampi(p_lock_level, 1, 6)
	var variations: Variant = lockpick_table().get("variations_by_difficulty", {})
	if variations is Dictionary:
		var diff_variants: Variant = (variations as Dictionary).get(str(lvl - 1), [])
		if diff_variants is Array and not (diff_variants as Array).is_empty():
			var arr: Array = diff_variants as Array
			var chosen: Variant = arr[posmod(variant_index, arr.size())]
			if chosen is Dictionary:
				return (chosen as Dictionary).duplicate(true)
	return {}


static func minigame_track_for_level(p_lock_level: int, variant_index: int = 0) -> Dictionary:
	var variation: Dictionary = minigame_variation_for_level(p_lock_level, variant_index)
	var tracks: Variant = variation.get("tracks", [])
	if tracks is Array and not (tracks as Array).is_empty():
		var first: Variant = (tracks as Array)[0]
		if first is Dictionary:
			return (first as Dictionary).duplicate(true)
	return {}


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = 1
	pivot = Node3D.new()
	add_child(pivot)

	_leaf_body = AnimatableBody3D.new()
	_leaf_body.sync_to_physics = true
	_leaf_body.collision_layer = 1
	_leaf_body.collision_mask = 0
	pivot.add_child(_leaf_body)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 2.4, 0.16)
	col.shape = box
	col.position = Vector3(0.65, 1.2, 0)
	_leaf_body.add_child(col)
	_leaf_shape = col

	var packed := ResourceLoader.load("res://assets/ue/Content/Art/Environment/City/Architecture/Doorways/SM_DoorCityExtA.glb") as PackedScene
	if packed != null:
		var inst := packed.instantiate()
		inst.position = Vector3(0.65, 0.0, 0)
		pivot.add_child(inst)
		# C2-01: authored door slots, not the white glTF default.
		LevelLoaderScript.bind_prop_scene_materials(inst, "res://assets/ue/Content/Art/Environment/City/Architecture/Doorways/SM_DoorCityExtA.glb")
	else:
		mesh_inst = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.3, 2.4, 0.14)
		mesh_inst.mesh = bm
		mesh_inst.position = Vector3(0.65, 1.2, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.25, 0.12) if locked else Color(0.32, 0.22, 0.14)
		mesh_inst.material_override = mat
		pivot.add_child(mesh_inst)


## Current pivot yaw in degrees (0 = closed, ~88 = fully open).
func open_angle_deg() -> float:
	if pivot == null:
		return 0.0
	return absf(rad_to_deg(pivot.rotation.y))


## Pure helper so tests can assert the 70-degree gate without physics.
func should_disable_leaf(angle_deg: float) -> bool:
	return absf(angle_deg) > OPEN_DISABLE_DEG


## Disables the leaf mover past OPEN_DISABLE_DEG (deferred + layer 0),
## re-enables on close. The frame root stays on layer 1 the whole time.
func _update_leaf_collision() -> void:
	if pivot == null or _leaf_body == null or not is_instance_valid(_leaf_body):
		return
	var disable: bool = should_disable_leaf(open_angle_deg())
	if disable == _leaf_disabled:
		return
	_leaf_disabled = disable
	if disable:
		_leaf_body.set_deferred("collision_layer", 0)
		if _leaf_shape != null and is_instance_valid(_leaf_shape):
			_leaf_shape.set_deferred("disabled", true)
	else:
		_leaf_body.set_deferred("collision_layer", 1)
		if _leaf_shape != null and is_instance_valid(_leaf_shape):
			_leaf_shape.set_deferred("disabled", false)


func _process(_delta: float) -> void:
	if pivot != null and _leaf_body != null:
		_update_leaf_collision()


func get_jam_damage() -> float:
	var lvl: int = clampi(lock_level, 1, table_max_lock_level())
	var dmg: float = GameData.eval_curve("CT_LockpickDamage", "DamageByLockLevel", float(lvl), -1.0)
	if dmg < 0.0:
		dmg = jam_damage_for_level(lvl)
	return dmg


## Real minigame track params for this lock level (DA_LockpickMinigameVariations,
## difficulty = lock_level - 1). Returns {} when the table provides nothing.
func get_minigame_track() -> Dictionary:
	var lvl: int = clampi(lock_level, 1, table_max_lock_level())
	return minigame_track_for_level(lvl, 0)


func get_minigame_variation() -> Dictionary:
	var lvl: int = clampi(lock_level, 1, table_max_lock_level())
	return minigame_variation_for_level(lvl, 0)


func get_track_duration() -> float:
	return float(get_minigame_track().get("duration_s", 0.0))


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


## P1 door noise sourced self: lockpick/door noises passed self, so the HUD
## player-only soundwave arcs never flashed though guards heard everything
## (audibility was correct; the UI feedback was missing). Emits use the stored
## player driver when one is mid-interaction (UE lockpick/door noise path).
func _noise_source() -> Node:
	if _lockpick_actor != null and is_instance_valid(_lockpick_actor):
		return _lockpick_actor
	return self


## Hold/relock path carries the actor directly (no stored driver).
func _audible_source(actor: Node) -> Node:
	if actor != null and is_instance_valid(actor):
		return actor
	return _noise_source()


func _on_minigame_finished(success: bool, actor: Node) -> void:
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
		is_open = true
		lockpick_updated.emit(false, 1.0, lock_level)
		var open_tween: Tween = create_tween()
		open_tween.tween_property(pivot, "rotation_degrees:y", 88.0, 0.35)
		NoiseBus.emit_noise(global_position, 5.5, _noise_source(), "door")
	else:
		_VfxManager.spawn_lockpick_sparks(get_parent(), global_position + Vector3(0.4, 1.1, 0))
		NoiseBus.emit_noise(global_position, 5.0, _noise_source(), "lockpick")
		lockpick_updated.emit(false, lockpick_progress, lock_level)


func interact(actor: Node) -> void:
	lock_level = clampi(lock_level, 1, table_max_lock_level())
	if locked:
		if is_lockpicking:
			return
		var hud_node: Node = _find_hud()
		if actor != null and actor.has_method("set_lockpicking_active"):
			_lockpick_actor = actor
			actor.call("set_lockpicking_active", true)
		if actor != null and hud_node != null and hud_node.has_method("start_lockpick_minigame"):
			is_lockpicking = true
			lockpick_updated.emit(true, lockpick_progress, lock_level)
			NoiseBus.emit_noise(global_position, 4.0, _noise_source(), "lockpick")
			hud_node.call("start_lockpick_minigame", lock_level, "Door Lock", func(success: bool = true) -> void:
				_on_minigame_finished(success, actor)
			)
			return
		var dmg: float = get_jam_damage()
		# One attempt strains the pick by the base unit (5) against this
		# level's jam damage (5/10/20/40): L1 opens in 1 attempt, L4 in 8.
		# Longer exposure + per-attempt noise is the per-level penalty,
		# mapped from the real CT_LockpickDamage values.
		var gain: float = 5.0 / maxf(dmg, 1.0)
		lockpick_progress = minf(1.0, lockpick_progress + gain)
		_VfxManager.spawn_lockpick_sparks(get_parent(), global_position + Vector3(0.4, 1.1, 0))
		NoiseBus.emit_noise(global_position, 4.0, _noise_source(), "lockpick")
		lockpick_updated.emit(true, lockpick_progress, lock_level)
		if lockpick_progress >= 1.0:
			locked = false
			is_open = true
			_clear_actor_lockpicking()
			lockpick_updated.emit(false, 1.0, lock_level)
			var open_tween: Tween = create_tween()
			open_tween.tween_property(pivot, "rotation_degrees:y", 88.0, 0.35)
			NoiseBus.emit_noise(global_position, 5.5, _noise_source(), "door")
		elif actor != null and is_inside_tree():
			# Headless fallback: keep Status.Lockpicking active briefly so
			# disguise drain ticks, then clear when the attempt window ends.
			is_lockpicking = true
			var dur: float = clampf(get_track_duration(), 0.35, 1.5)
			get_tree().create_timer(dur).timeout.connect(func() -> void:
				if is_instance_valid(self) and is_lockpicking:
					_clear_actor_lockpicking()
			)
		return
	is_open = not is_open
	var target_yaw: float = 88.0 if is_open else 0.0
	var swing_tween: Tween = create_tween()
	swing_tween.tween_property(pivot, "rotation_degrees:y", target_yaw, 0.35)
	NoiseBus.emit_noise(global_position, 5.5, _noise_source(), "door")


func get_interact_prompt() -> String:
	if locked:
		return "[E] Pick Lock (Lv %d) %d%%" % [lock_level, int(lockpick_progress * 100.0)]
	if is_open:
		return "[E] Close Door"
	return "[E] Open Door"


## Interaction LOS point (W2): door handle height above the node origin, so a
## closed leaf at the origin plane does not read as an occluder.
func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.1


## KF24: closed unlocked doors stack [F] [HOLD] LOCK under the primary OPEN.
func get_interact_secondary_prompt() -> String:
	if locked or is_open:
		return ""
	return "[F] [HOLD] LOCK"


## KF24 secondary action: hold F to lock the closed door again.
func interact_hold(actor: Node) -> void:
	if locked or is_open:
		return
	locked = true
	lock_level = maxi(lock_level, 1)
	lockpick_progress = 0.0
	lockpick_updated.emit(false, 0.0, lock_level)
	NoiseBus.emit_noise(global_position, 3.0, _audible_source(actor), "lock")
