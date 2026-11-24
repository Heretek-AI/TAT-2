extends Node3D
## Authored magic alarm eye / security camera (BP_MagicAlarm*_C).
##
## Sight/lose/FOV and swivel come from the merged variant metric in
## stats.family_defaults.alarm_eye.variants[class]; per-instance _swivel*
## overrides win. The instance's OuterConeAngle/InnerConeAngle/LightRange are
## the authored spotlight cone (visual), not the TATAISenseConfig_Sight
## perception half-angle, so detection uses the variant metric instead. The
## alarm delay is the authored per-variant base (2.0 s, or 0.25 s on the FTUE
## eye) times the authored difficulty multiplier 1.0 / 0.5 / 0.1. On expiry it
## emits the authored 25 m Heavy guard_alert stimulus through NoiseBus — the
## guard hearing path already consumes it.
##
## Runtime-only breakable health is 50. A cheap emissive flash marks the alarm;
## the authored camera mesh itself is level geometry and is never duplicated.

signal alarm_triggered(source: Node)
signal power_state_changed(on: bool)

const Geometry := preload("res://src/devices/device_geometry.gd")

const ALARM_LOUDNESS_M: float = 25.0
const ALARM_TAG: String = "guard_alert"
const FALLBACK_HEALTH: float = 50.0

var device_id: String = ""
var family: String = "alarm_eye"
var class_name_hint: String = ""
var params: Dictionary = {}
var variant: String = "base"
var sight_m: float = 25.0
var lose_sight_m: float = 30.0
var half_fov_deg: float = 10.0
var alarm_base_seconds: float = 2.0
var alarm_delay_s: float = 2.0
var swivel_angle_deg: float = 45.0
var swivel_seconds: float = 10.0
var swivel_pause_seconds: float = 2.0
var health: float = FALLBACK_HEALTH
var max_health: float = FALLBACK_HEALTH

var player: Node3D = null
var action_targets: Array = []
var awake: bool = true
var alive: bool = true
var power_source: Node = null
var power_required: bool = true
var alarms: int = 0

var _powered: bool = true
var _seen_seconds: float = 0.0
var _time: float = 0.0
var _alarmed: bool = false
var _flash: MeshInstance3D = null
var _flash_mat: StandardMaterial3D = null
var _built: bool = false


func configure(rec: Dictionary, family_defaults: Dictionary, difficulty_value: int = -1) -> void:
	device_id = str(rec.get("id", ""))
	family = str(rec.get("family", "alarm_eye"))
	class_name_hint = str(rec.get("class", ""))
	var params_v: Variant = rec.get("params", {})
	params = params_v as Dictionary if params_v is Dictionary else {}
	var defaults: Dictionary = family_defaults.get(family, {}) as Dictionary
	var metric: Dictionary = defaults.get("metric", {}) as Dictionary
	var variants: Dictionary = defaults.get("variants", {}) as Dictionary
	var variant_def: Dictionary = variants.get(class_name_hint, {}) as Dictionary
	var variant_metric: Dictionary = variant_def.get("metric", {}) as Dictionary
	variant = str(params.get("variant", variant_def.get("variant", "base")))
	sight_m = float(variant_metric.get("sight_m", 25.0))
	lose_sight_m = float(variant_metric.get("lose_sight_m", 30.0))
	half_fov_deg = float(variant_metric.get("half_fov_deg", 10.0))
	swivel_angle_deg = _param_or_metric("_swivelAngle", "swivel_angle_deg", variant_metric, float(metric.get("swivel_angle_deg", 45.0)))
	swivel_seconds = _param_or_metric("_swivelSeconds", "swivel_seconds", variant_metric, float(metric.get("swivel_seconds", 10.0)))
	swivel_pause_seconds = _param_or_metric("_swivelPauseSeconds", "swivel_pause_seconds", variant_metric, float(metric.get("swivel_pause_seconds", 2.0)))
	var delay_steps_v: Variant = metric.get("alarm_delay_multipliers_by_difficulty", [1.0, 0.5, 0.1])
	var delay_steps: Array = delay_steps_v as Array if delay_steps_v is Array else [1.0, 0.5, 0.1]
	var diff: int = difficulty_value if difficulty_value >= 0 else int(GameState.difficulty)
	var multiplier: float = float(delay_steps[clampi(diff - 1, 0, delay_steps.size() - 1)]) if not delay_steps.is_empty() else 1.0
	var fallback_delay: float = 2.0
	var family_delays_v: Variant = metric.get("alarm_delay_seconds_by_difficulty", [2.0])
	if family_delays_v is Array and not (family_delays_v as Array).is_empty():
		fallback_delay = float((family_delays_v as Array)[0])
	alarm_base_seconds = float(variant_metric.get("alarm_delay_seconds", fallback_delay))
	alarm_delay_s = maxf(alarm_base_seconds * multiplier, 0.0)
	health = FALLBACK_HEALTH
	max_health = FALLBACK_HEALTH
	var power_v: Variant = rec.get("power", {})
	var power: Dictionary = power_v as Dictionary if power_v is Dictionary else {}
	var req_v: Variant = power.get("require", null)
	power_required = true if req_v == null else bool(req_v)
	_build()


func _param_or_metric(param_key: String, metric_key: String, variant_metric: Dictionary, fallback: float) -> float:
	if params.has(param_key):
		var v: Variant = params.get(param_key)
		if v is float or v is int:
			return float(v)
	return float(variant_metric.get(metric_key, fallback))


func _ready() -> void:
	add_to_group("devices")
	add_to_group("device_detector")
	_build()


func _build() -> void:
	if _built:
		return
	_built = true


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
		_seen_seconds = 0.0


func can_trigger() -> bool:
	return alive and awake and (not power_required or _powered)


func set_awake(value: bool) -> void:
	awake = value


func tick(delta: float) -> void:
	_time += delta
	if _flash_mat != null:
		_flash_mat.emission_energy_multiplier = 1.5 + 1.0 * sin(_time * 18.0)
	if not can_trigger():
		_seen_seconds = 0.0
		return
	var target: Node3D = _resolve_player()
	if target == null:
		_seen_seconds = 0.0
		return
	if _sees(target):
		_seen_seconds += delta
		if not _alarmed and _seen_seconds + 0.000001 >= alarm_delay_s:
			_trigger_alarm()
	else:
		_seen_seconds = maxf(0.0, _seen_seconds - delta)
		if _seen_seconds <= 0.0:
			_alarmed = false


## Detection seam matching the turret: range + half-FOV + LOS on 1|2|4|8.
func _sees(target: Node3D) -> bool:
	var from: Vector3 = global_position + Vector3.UP * 0.6
	var aim: Vector3 = Geometry.body_aim_point(target)
	var to_target: Vector3 = aim - from
	var distance: float = to_target.length()
	if distance <= 0.0001:
		return false
	var max_range: float = lose_sight_m if _seen_seconds > 0.0 else sight_m
	if distance > max_range:
		return false
	var fwd: Vector3 = _forward()
	var angle_deg: float = rad_to_deg(fwd.angle_to(to_target / distance))
	if angle_deg > half_fov_deg + 0.0001:
		return false
	return _has_los(target, from, aim)


func _forward() -> Vector3:
	var basis: Basis = global_transform.basis
	var offset: float = _swivel_offset_rad()
	if absf(offset) > 0.000001:
		basis = basis * Basis(Vector3.UP, offset)
	var fwd: Vector3 = basis.x
	return fwd.normalized() if fwd.length_squared() > 0.5 else Vector3.RIGHT


func _swivel_offset_rad() -> float:
	if swivel_seconds <= 0.0:
		return 0.0
	var amp: float = deg_to_rad(swivel_angle_deg * 0.5)
	return amp * sin(_time * TAU / maxf(swivel_seconds, 0.001))


func _has_los(target: Node3D, from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return true
	var exclusions: Array[RID] = []
	if target is CollisionObject3D:
		exclusions.append((target as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4 | 8, exclusions)
	var hit: Dictionary = space.intersect_ray(q)
	return hit.is_empty()


func _trigger_alarm() -> void:
	_alarmed = true
	alarms += 1
	alarm_triggered.emit(self)
	NoiseBus.emit_noise(global_position, ALARM_LOUDNESS_M, self, ALARM_TAG)
	for target_v: Variant in action_targets:
		if not (target_v is Node) or not is_instance_valid(target_v as Node):
			continue
		var target: Node = target_v as Node
		if target.has_method("activate_from"):
			target.call("activate_from", self)
		elif target.has_method("trigger_from"):
			target.call("trigger_from", self)
		elif target.has_method("activate"):
			target.call("activate")
	if AudioManager != null and AudioManager.has_method("play_cue"):
		AudioManager.call("play_cue", "alarm_loop", global_position)
	_flash_alarm()


func _flash_alarm() -> void:
	if _flash != null and is_instance_valid(_flash):
		return
	_flash = MeshInstance3D.new()
	_flash.name = "AlarmFlash"
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	sphere.radial_segments = 8
	sphere.rings = 4
	_flash.mesh = sphere
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1.0, 0.12, 0.08, 0.9)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(1.0, 0.1, 0.05)
	_flash_mat.emission_energy_multiplier = 2.0
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)


func reset_alarm() -> void:
	_seen_seconds = 0.0
	_alarmed = false
	if _flash != null and is_instance_valid(_flash):
		_flash.queue_free()


func take_damage(amount: float, _source: String = "") -> void:
	if amount <= 0.0 or not alive:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		alive = false
		_seen_seconds = 0.0
		if _flash != null and is_instance_valid(_flash):
			_flash.visible = false


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
