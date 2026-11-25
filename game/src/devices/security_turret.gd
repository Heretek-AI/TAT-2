extends Node3D
## Authored security turret (BP_SecurityTurret*_C).
##
## Family metric: 12 m sight, +/-15 deg half-FOV, 0.5 s fire interval at the
## Normal difficulty, 40 m/s projectile, 10 damage, 30 s projectile life.
## Per-variant starts_on/swivel values merge from
## stats.family_defaults.turret.variants[class]; a per-instance starts_on or
## _state.bIsOn wins. BP_SecurityTurret_180_Triggered_C starts off and is
## switched on by a linked plate/beam through activate_from().
##
## Runtime-only breakable health is 150 (the cooked breakable component is not
## part of the runtime export); at zero the turret stops firing. Detection is
## a point/FOV/LOS test against the player's authored body aim point, never a
## distance-only radius.

signal turret_fired(source: Node, projectile: Node)
signal turret_activated(source: Node)
signal turret_alarmed(source: Node)
signal power_state_changed(on: bool)

const Geometry := preload("res://src/devices/device_geometry.gd")
const ProjectileScript := preload("res://src/devices/turret_projectile.gd")

const FALLBACK_HEALTH: float = 150.0

var device_id: String = ""
var family: String = "turret"
var class_name_hint: String = ""
var params: Dictionary = {}
var variant: String = "base"
var sight_m: float = 12.0
var lose_sight_m: float = 12.0
var half_fov_deg: float = 15.0
var sight_origin_height_m: float = 0.6
var fire_interval_s: float = 0.5
var projectile_speed_m_s: float = 40.0
var projectile_damage: float = 10.0
var projectile_life_s: float = 30.0
var swivel_angle_deg: float = 0.0
var swivel_seconds: float = 0.0
var swivel_type: String = ""
var starts_on: bool = true
var health: float = FALLBACK_HEALTH
var max_health: float = FALLBACK_HEALTH
## Authored alarm (BP_SecurityTurret `_difficultyToSwivelSettingsMap[*].Value
## .SecondsUntilAlarmTriggers` = 2.0/1.0/0.25 s) and reset (10 s without a
## target). The turret used to shoot in silence: guards never heard it and the
## alarm state never re-armed.
var alarm_delay_s: float = 2.0
var reset_seconds: float = 10.0
var alarm_raised: bool = false
var alarm_count: int = 0
var _alarm_hold: float = 0.0
var _no_target_sec: float = 0.0
## The authored security-device alarm stim (hearing.json
## SecurityDevice.Alarm.Triggered, 25 m Heavy). No turret-specific hearing row
## is authored, so the security alarm row is the honest stimulus.
const ALARM_STIM_TAG: String = "AI.Stim.Hearing.SecurityDevice.Alarm.Triggered"
const ALARM_STIM_RANGE_M: float = 25.0

var player: Node3D = null
var action_targets: Array = []
var awake: bool = true
var alive: bool = true
var is_on: bool = false
var shots_fired: int = 0
var last_projectile: Node = null
var power_source: Node = null
var power_required: bool = false

var _powered: bool = true
var _fire_cooldown: float = 0.0
var _time: float = 0.0
var _built: bool = false


func configure(rec: Dictionary, family_defaults: Dictionary, difficulty_value: int = -1) -> void:
	device_id = str(rec.get("id", ""))
	family = str(rec.get("family", "turret"))
	class_name_hint = str(rec.get("class", ""))
	var params_v: Variant = rec.get("params", {})
	params = params_v as Dictionary if params_v is Dictionary else {}
	var defaults: Dictionary = family_defaults.get(family, {}) as Dictionary
	var metric: Dictionary = defaults.get("metric", {}) as Dictionary
	var variants: Dictionary = defaults.get("variants", {}) as Dictionary
	var variant_def: Dictionary = variants.get(class_name_hint, {}) as Dictionary
	var variant_metric: Dictionary = variant_def.get("metric", {}) as Dictionary
	variant = str(params.get("variant", variant_def.get("variant", "base")))
	sight_m = float(metric.get("sight_m", 12.0))
	lose_sight_m = float(metric.get("lose_sight_m", sight_m))
	half_fov_deg = float(metric.get("half_fov_deg", 15.0))
	sight_origin_height_m = float(metric.get("pov_backward_m", 0.5))
	fire_interval_s = _difficulty_interval(metric, difficulty_value)
	alarm_delay_s = _difficulty_alarm_delay(defaults, difficulty_value)
	reset_seconds = float(defaults.get("reset_seconds", 10.0))
	var projectile: Dictionary = metric.get("projectile", {}) as Dictionary
	projectile_speed_m_s = float(projectile.get("speed_m_s", 40.0))
	projectile_damage = float(projectile.get("damage", 10.0))
	projectile_life_s = float(projectile.get("life_seconds", 30.0))
	swivel_angle_deg = _param_or_metric("_swivelAngle", "swivel_angle_deg", variant_metric, 0.0)
	swivel_seconds = _param_or_metric("_swivelSeconds", "swivel_seconds", variant_metric, 0.0)
	swivel_type = str(params.get("_swivelType", variant_metric.get("swivel_type", "")))
	# A 360 variant carries the rotation type but no per-instance seconds; use
	# the authored difficulty swivel table (12/10/8 s) instead of inventing a
	# speed. A zero-second non-360 row keeps its authored static pose.
	if swivel_seconds <= 0.0 and swivel_type.find("ThreeSixty") >= 0:
		var swivel_rows_v: Variant = defaults.get("_difficultyToSwivelSettingsMap", [])
		if swivel_rows_v is Array and not (swivel_rows_v as Array).is_empty():
			var rows: Array = swivel_rows_v as Array
			var diff_idx: int = clampi((difficulty_value if difficulty_value >= 0 else int(GameState.difficulty)) - 1, 0, rows.size() - 1)
			var row_v: Variant = rows[diff_idx]
			if row_v is Dictionary:
				var value_v: Variant = (row_v as Dictionary).get("Value", {})
				if value_v is Dictionary:
					swivel_seconds = float((value_v as Dictionary).get("SwivelSeconds", 0.0))
	# Resolution order: per-instance starts_on, authored State.bIsOn, variant
	# metric, then the base-class runtime fallback (on). This keeps the
	# explicitly-off _180_Triggered variant off and the silent base variant on.
	if params.has("starts_on") and (params.get("starts_on") is bool or params.get("starts_on") == null):
		var so_v: Variant = params.get("starts_on")
		starts_on = true if so_v == null else bool(so_v)
	elif params.has("State") and params.get("State") is Dictionary and (params.get("State") as Dictionary).has("bIsOn"):
		starts_on = bool((params.get("State") as Dictionary).get("bIsOn"))
	elif variant_metric.has("starts_on") and variant_metric.get("starts_on") != null:
		starts_on = bool(variant_metric.get("starts_on"))
	else:
		starts_on = true
	is_on = starts_on
	health = FALLBACK_HEALTH
	max_health = FALLBACK_HEALTH
	var power_v: Variant = rec.get("power", {})
	var power: Dictionary = power_v as Dictionary if power_v is Dictionary else {}
	power_required = bool(power.get("require", false))
	_build()


func _difficulty_interval(metric: Dictionary, difficulty_value: int) -> float:
	var diff: int = difficulty_value
	if diff < 0:
		diff = int(GameState.difficulty)
	var steps_v: Variant = metric.get("fire_interval_seconds_by_difficulty", [1.0, 0.5, 0.33])
	var steps: Array = steps_v as Array if steps_v is Array else [1.0, 0.5, 0.33]
	if steps.is_empty():
		return 0.5
	return float(steps[clampi(diff - 1, 0, steps.size() - 1)])


func _param_or_metric(param_key: String, metric_key: String, variant_metric: Dictionary, fallback: float) -> float:
	if params.has(param_key):
		var v: Variant = params.get(param_key)
		if v is float or v is int:
			return float(v)
	return float(variant_metric.get(metric_key, fallback))


## Authored per-difficulty `SecondsUntilAlarmTriggers`
## (family_defaults.turret.alarm_delay_seconds_by_difficulty 2.0/1.0/0.25).
func _difficulty_alarm_delay(defaults: Dictionary, difficulty_value: int) -> float:
	var diff: int = difficulty_value
	if diff < 0:
		diff = int(GameState.difficulty)
	var steps_v: Variant = defaults.get("alarm_delay_seconds_by_difficulty", [2.0, 1.0, 0.25])
	var steps: Array = steps_v as Array if steps_v is Array else [2.0, 1.0, 0.25]
	if steps.is_empty():
		return 2.0
	return maxf(float(steps[clampi(diff - 1, 0, steps.size() - 1)]), 0.0)


func _ready() -> void:
	add_to_group("devices")
	add_to_group("device_action")
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


func can_fire() -> bool:
	return alive and awake and is_on and (not power_required or _powered)


func activate_from(_source: Node = null) -> void:
	if not alive or is_on:
		return
	is_on = true
	turret_activated.emit(self)


func activate() -> void:
	activate_from(null)


func set_awake(value: bool) -> void:
	awake = value


func tick(delta: float) -> void:
	_time += delta
	if _fire_cooldown > 0.0:
		_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	if not can_fire():
		return
	var target: Node3D = _resolve_player()
	if target == null:
		return
	if not can_see(target):
		# Authored reset_seconds (10 s): the alarm state re-arms after the
		# turret has had no target for that long.
		_no_target_sec += delta
		if _no_target_sec >= reset_seconds:
			_alarm_hold = 0.0
			alarm_raised = false
		return
	_no_target_sec = 0.0
	# Authored SecondsUntilAlarmTriggers: detection must persist before the
	# security alarm is raised (guards then investigate the authored 25 m stim).
	if not alarm_raised:
		_alarm_hold += delta
		if _alarm_hold + 0.000001 >= alarm_delay_s:
			_raise_alarm()
	if _fire_cooldown <= 0.0:
		_fire()
		_fire_cooldown = fire_interval_s


## Raise the authored security alarm once per detection streak.
func _raise_alarm() -> void:
	alarm_raised = true
	alarm_count += 1
	NoiseBus.emit_noise(global_position, ALARM_STIM_RANGE_M, self, ALARM_STIM_TAG)
	turret_alarmed.emit(self)


func alarm_active() -> bool:
	return alarm_raised


## Public detection seam used by the suite (and by tick): range, half-FOV and
## an unobstructed LOS ray on mask 1|2|4|8 excluding the target.
func can_see(target: Node3D) -> bool:
	if target == null:
		return false
	var from: Vector3 = global_position + Vector3.UP * sight_origin_height_m
	var aim: Vector3 = Geometry.body_aim_point(target)
	var to_target: Vector3 = aim - from
	var distance: float = to_target.length()
	if distance <= 0.0001 or distance > sight_m:
		return false
	var fwd: Vector3 = forward_direction()
	var angle_deg: float = rad_to_deg(fwd.angle_to(to_target / distance))
	if angle_deg > half_fov_deg + 0.0001:
		return false
	return _has_los(target, from, aim)


func forward_direction() -> Vector3:
	var basis: Basis = global_transform.basis
	var offset: float = _swivel_offset_rad()
	if absf(offset) > 0.000001:
		basis = basis * Basis(Vector3.UP, offset)
	var fwd: Vector3 = basis.x
	return fwd.normalized() if fwd.length_squared() > 0.5 else Vector3.RIGHT


func _swivel_offset_rad() -> float:
	if swivel_seconds <= 0.0:
		return 0.0
	if swivel_type.find("ThreeSixty") >= 0:
		var period: float = swivel_seconds
		var angle: float = fmod(_time * TAU / period, TAU)
		return -angle if swivel_type.find("CounterClockwise") >= 0 else angle
	var amp: float = deg_to_rad(swivel_angle_deg * 0.5)
	return amp * sin(_time * TAU / swivel_seconds)


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


func _fire() -> void:
	var fwd: Vector3 = forward_direction()
	var origin: Vector3 = global_position + fwd * 0.4 + Vector3.UP * 0.2
	var projectile: Node = ProjectileScript.new()
	projectile.call("configure", origin, fwd, projectile_speed_m_s, projectile_damage, projectile_life_s, self)
	var host: Node = get_parent()
	if host == null:
		host = self
	host.add_child(projectile)
	projectile.set("global_position", origin)
	shots_fired += 1
	last_projectile = projectile
	turret_fired.emit(self, projectile)


func take_damage(amount: float, _source: String = "") -> void:
	if amount <= 0.0 or not alive:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		alive = false
		is_on = false


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
