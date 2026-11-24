extends Area3D
## Authored pressure plate (BP_Detector_PressurePlate_C).
##
## The authored overlap sphere is 45 cm and the authored shape is a 45x45x3 cm
## plate (family_defaults.pressure_plate.metric). Trigger is 1.5 s, reset 0.2 s;
## a crossing applies the authored 10 Physical damage once and fires the
## authored TrapActionsToTrigger graph. Leaving the plate is required before the
## next crossing can re-fire, so standing still does not tick damage.

signal plate_triggered(source: Node)
signal power_state_changed(on: bool)

const Geometry := preload("res://src/devices/device_geometry.gd")

const CUE_TRIGGER: String = "jawtrap"

var device_id: String = ""
var family: String = "pressure_plate"
var params: Dictionary = {}
var radius_m: float = 0.45
var trigger_seconds: float = 1.5
var reset_seconds: float = 0.2
var damage_amount: float = 10.0
var damage_type: String = "DamageType.Physical"

var player: Node3D = null
var action_targets: Array = []
var actions_fired: int = 0
var damage_applied: int = 0
var awake: bool = true
var alive: bool = true
var power_source: Node = null
var power_required: bool = true
var _powered: bool = true

var _shape_node: CollisionShape3D = null
var _dwell: float = 0.0
var _cooldown: float = 0.0
var _inside: bool = false
var _needs_exit: bool = false
var _built: bool = false


func configure(rec: Dictionary, family_defaults: Dictionary, difficulty_value: int = -1) -> void:
	device_id = str(rec.get("id", ""))
	family = str(rec.get("family", "pressure_plate"))
	var params_v: Variant = rec.get("params", {})
	params = params_v as Dictionary if params_v is Dictionary else {}
	var defaults: Dictionary = family_defaults.get(family, {}) as Dictionary
	var metric: Dictionary = defaults.get("metric", {}) as Dictionary
	radius_m = float(metric.get("overlap_radius_m", 0.45))
	trigger_seconds = float(metric.get("trigger_seconds", 1.5))
	reset_seconds = float(metric.get("reset_seconds", 0.2))
	var damage: Dictionary = metric.get("damage", {}) as Dictionary
	damage_amount = float(damage.get("amount", 10.0))
	damage_type = str(damage.get("type", "DamageType.Physical"))
	var power_v: Variant = rec.get("power", {})
	var power: Dictionary = power_v as Dictionary if power_v is Dictionary else {}
	var req_v: Variant = power.get("require", null)
	power_required = true if req_v == null else bool(req_v)
	if _built:
		_apply_geometry()
	else:
		_build()


func _ready() -> void:
	add_to_group("devices")
	add_to_group("device_detector")
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	collision_layer = 0
	collision_mask = 2
	monitoring = awake
	monitorable = false
	_shape_node = CollisionShape3D.new()
	_shape_node.name = "PlateShape"
	var sphere := SphereShape3D.new()
	sphere.radius = radius_m
	_shape_node.shape = sphere
	add_child(_shape_node)
	_apply_geometry()


func _apply_geometry() -> void:
	if _shape_node == null:
		return
	var sphere: SphereShape3D = _shape_node.shape as SphereShape3D
	if sphere != null:
		sphere.radius = radius_m


func set_player(p: Node3D) -> void:
	player = p


func set_action_targets(targets: Array) -> void:
	action_targets = targets


func set_power_source(src: Node) -> void:
	power_source = src
	if src != null and src.has_signal("powered"):
		if not src.is_connected("powered", Callable(self, "_on_power_changed")):
			src.connect("powered", Callable(self, "_on_power_changed"))
		_powered = bool(src.call("is_powered")) if src.has_method("is_powered") else true
	else:
		_powered = true


func _on_power_changed(on: bool) -> void:
	_powered = on
	power_state_changed.emit(on)
	if power_required and not on:
		_dwell = 0.0
		_inside = false


func can_trigger() -> bool:
	return alive and awake and (not power_required or _powered)


func set_awake(value: bool) -> void:
	awake = value
	monitoring = value
	if not value:
		_dwell = 0.0
		_inside = false


func tick(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if not can_trigger():
		_dwell = 0.0
		_inside = false
		return
	var target: Node3D = _resolve_player()
	if target == null:
		_dwell = 0.0
		_inside = false
		return
	_inside = _player_on_plate(target)
	if not _inside:
		_dwell = 0.0
		_needs_exit = false
		return
	if _needs_exit:
		# The authored reset is a re-arm; a body that never left the plate is
		# the same crossing and must not take damage again.
		return
	if _cooldown > 0.0:
		return
	_dwell += delta
	if _dwell + 0.000001 >= maxf(trigger_seconds, 0.0):
		_dwell = 0.0
		_cooldown = reset_seconds
		_needs_exit = true
		_fire(target)


func is_player_inside() -> bool:
	return _inside


func _fire(target: Node3D) -> void:
	actions_fired += 1
	plate_triggered.emit(self)
	if damage_amount > 0.0 and target.has_method("take_damage"):
		target.call("take_damage", damage_amount)
		damage_applied += 1
	for target_v: Variant in action_targets:
		if not (target_v is Node) or not is_instance_valid(target_v as Node):
			continue
		var action: Node = target_v as Node
		if action.has_method("activate_from"):
			action.call("activate_from", self)
		elif action.has_method("trigger_from"):
			action.call("trigger_from", self)
		elif action.has_method("activate"):
			action.call("activate")
	if AudioManager != null and AudioManager.has_method("play_cue"):
		AudioManager.call("play_cue", CUE_TRIGGER, global_position)


func _player_on_plate(target: Node3D) -> bool:
	var body: PackedVector3Array = Geometry.body_segment(target)
	if body.size() < 2:
		return false
	return Geometry.point_segment_distance(global_position, body[0], body[1]) <= radius_m


func _resolve_player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	if not is_inside_tree():
		return null
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is Node3D:
		player = found as Node3D
		return player
	return null
