extends StaticBody3D
## Interactive door with optional lock level (1..4, using CT_LockpickDamage).

signal lockpick_updated(active: bool, progress: float, lock_level: int)

const _VfxManager = preload('res://src/core/vfx_manager.gd')

@export var locked: bool = false
@export var lock_level: int = 1
var is_open: bool = false
var pivot: Node3D
var mesh_inst: MeshInstance3D
var lockpick_progress: float = 0.0


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = 1
	pivot = Node3D.new()
	add_child(pivot)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 2.4, 0.16)
	col.shape = box
	col.position = Vector3(0.65, 1.2, 0)
	pivot.add_child(col)

	var packed := ResourceLoader.load("res://assets/ue/Content/Art/Environment/City/Architecture/Doorways/SM_DoorCityExtA.glb") as PackedScene
	if packed != null:
		var inst := packed.instantiate()
		inst.position = Vector3(0.65, 0.0, 0)
		pivot.add_child(inst)
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


func interact(actor: Node) -> void:
	if locked:
		var dmg: float = GameData.eval_curve("CT_LockpickDamage", "LockpickDamage", float(lock_level), 0.35)
		dmg = clampf(dmg, 0.18, 1.0)
		lockpick_progress = minf(1.0, lockpick_progress + dmg)
		_VfxManager.spawn_lockpick_sparks(get_parent(), global_position + Vector3(0.4, 1.1, 0))
		NoiseBus.emit_noise(global_position, 4.0, self, "lockpick")
		lockpick_updated.emit(true, lockpick_progress, lock_level)
		if lockpick_progress >= 1.0:
			locked = false
			is_open = true
			lockpick_updated.emit(false, 1.0, lock_level)
			var open_tween: Tween = create_tween()
			open_tween.tween_property(pivot, "rotation_degrees:y", 88.0, 0.35)
			NoiseBus.emit_noise(global_position, 5.5, self, "door")
		return
	is_open = not is_open
	var target_yaw: float = 88.0 if is_open else 0.0
	var swing_tween: Tween = create_tween()
	swing_tween.tween_property(pivot, "rotation_degrees:y", target_yaw, 0.35)
	NoiseBus.emit_noise(global_position, 5.5, self, "door")


func get_interact_prompt() -> String:
	if locked:
		return "[E] Pick Lock (Lv %d) %d%%" % [lock_level, int(lockpick_progress * 100.0)]
	if is_open:
		return "[E] Close Door"
	return "[E] Open Door"
