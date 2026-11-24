extends Node3D
## Authored wall power supply / light switch (BP_PowerSupply_Wall_C,
## BP_PowerSupply_LightSwitch_C).
##
## _state.bIsOn and the family metric decide the initial state; the authored
## _configTimeUntilAutoReset (10/30 s on the wall supplies) arms the reset only
## while the supply is off. Interact is the [F] toggle; the scripted breakable
## health is 20 (the cooked breakable component is not in the runtime export,
## so this is a documented runtime-only value). Detectors linked to this supply
## receive set_power_source() and gate themselves on the powered signal.

signal powered(on: bool)
signal power_state_changed(on: bool)

const DEFAULT_HEALTH: float = 20.0

var device_id: String = ""
var family: String = "power_wall"
var params: Dictionary = {}
var starts_on: bool = true
var auto_reset_seconds: float = 0.0
var health: float = DEFAULT_HEALTH
var max_health: float = DEFAULT_HEALTH

var _is_on: bool = true
var _reset_timer: float = 0.0
var broken: bool = false
var toggles: int = 0
var _built: bool = false


func configure(rec: Dictionary, family_defaults: Dictionary, difficulty_value: int = -1) -> void:
	device_id = str(rec.get("id", ""))
	family = str(rec.get("family", "power_wall"))
	var params_v: Variant = rec.get("params", {})
	params = params_v as Dictionary if params_v is Dictionary else {}
	var defaults: Dictionary = family_defaults.get(family, {}) as Dictionary
	var metric: Dictionary = defaults.get("metric", {}) as Dictionary
	var state_v: Variant = params.get("_state", null)
	if state_v is Dictionary and (state_v as Dictionary).has("bIsOn"):
		starts_on = bool((state_v as Dictionary).get("bIsOn"))
	elif params.has("starts_on"):
		starts_on = bool(params.get("starts_on"))
	else:
		starts_on = bool(metric.get("starts_on", family == "power_wall"))
	_is_on = starts_on
	auto_reset_seconds = _resolve_auto_reset(metric)
	_build()


func _resolve_auto_reset(metric: Dictionary) -> float:
	if params.has("_shouldAutoReset") and not bool(params.get("_shouldAutoReset")):
		return 0.0
	var time_v: Variant = params.get("_configTimeUntilAutoReset", null)
	if time_v is float or time_v is int:
		return maxf(float(time_v), 0.0)
	if bool(params.get("_shouldAutoReset", false)):
		var options_v: Variant = metric.get("auto_reset_seconds_options", [])
		if options_v is Array:
			for option_v: Variant in (options_v as Array):
				var option: float = float(option_v)
				if option > 0.0:
					return option
	return 0.0


func _ready() -> void:
	add_to_group("devices")
	add_to_group("power_source")
	if family == "power_wall" or family == "power_switch":
		add_to_group("interactables")
	_build()


func _build() -> void:
	if _built:
		return
	_built = true


func is_powered() -> bool:
	return _is_on


func set_power_state(on: bool, notify: bool = true) -> void:
	if _is_on == on:
		if not on and auto_reset_seconds > 0.0 and not broken:
			_reset_timer = auto_reset_seconds
		return
	_is_on = on
	if on:
		_reset_timer = 0.0
	elif auto_reset_seconds > 0.0 and not broken:
		_reset_timer = auto_reset_seconds
	if notify:
		powered.emit(_is_on)
		power_state_changed.emit(_is_on)


func toggle() -> void:
	toggles += 1
	set_power_state(not _is_on)


func interact(_actor: Node) -> void:
	if broken:
		return
	toggle()
	if AudioManager != null and AudioManager.has_method("play_cue"):
		AudioManager.call("play_cue", "ui_click", global_position)


func get_interact_prompt() -> String:
	if broken:
		return "[F] POWER SUPPLY BROKEN"
	return "[F] POWER OFF" if _is_on else "[F] POWER ON"


func take_damage(amount: float, _source: String = "") -> void:
	if amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		broken = true
		_reset_timer = 0.0
		set_power_state(false)


func tick(delta: float) -> void:
	if _is_on or _reset_timer <= 0.0:
		return
	_reset_timer = maxf(0.0, _reset_timer - delta)
	if _reset_timer <= 0.0:
		broken = false
		set_power_state(true)


func auto_reset_remaining() -> float:
	return _reset_timer
