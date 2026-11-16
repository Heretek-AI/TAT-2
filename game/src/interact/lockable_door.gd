extends StaticBody3D
## Interactive door with optional lock level (1..4, using CT_LockpickDamage).

signal lockpick_updated(active: bool, progress: float, lock_level: int)

const _VfxManager = preload('res://src/core/vfx_manager.gd')

const INTERACTABLES_PATH := "res://data/generated/gameplay/interactables.json"
## Fallbacks mirror the extracted table (CT_LockpickDamage DamageByLockLevel
## 5/10/20/40, doors MaxLockLevel 4); the JSON above is authoritative.
const FALLBACK_JAM_DAMAGE := {1: 5.0, 2: 10.0, 3: 20.0, 4: 40.0}
const FALLBACK_MAX_LOCK_LEVEL := 4

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
	return float(FALLBACK_JAM_DAMAGE.get(clampi(lock_level, 1, 4), 5.0))

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
	var variations: Variant = lockpick_table().get("variations_by_difficulty", {})
	if variations is Dictionary:
		var diff_variants: Variant = (variations as Dictionary).get(str(lvl - 1), [])
		if diff_variants is Array and not (diff_variants as Array).is_empty():
			var first: Variant = (diff_variants as Array)[0]
			if first is Dictionary:
				var tracks: Variant = (first as Dictionary).get("tracks", [])
				if tracks is Array and not (tracks as Array).is_empty():
					return (tracks as Array)[0]
	return {}


func get_track_duration() -> float:
	return float(get_minigame_track().get("duration_s", 0.0))


func interact(actor: Node) -> void:
	lock_level = clampi(lock_level, 1, table_max_lock_level())
	if locked:
		var dmg: float = get_jam_damage()
		# One attempt strains the pick by the base unit (5) against this
		# level's jam damage (5/10/20/40): L1 opens in 1 attempt, L4 in 8.
		# Longer exposure + per-attempt noise is the per-level penalty,
		# mapped from the real CT_LockpickDamage values.
		var gain: float = 5.0 / maxf(dmg, 1.0)
		lockpick_progress = minf(1.0, lockpick_progress + gain)
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
