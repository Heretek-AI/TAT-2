extends Node3D
## Authored noise alarm trap action (BP_Trap_Action_NoiseAlarm_C).
##
## It is not a detector: a linked beam/plate calls trigger_from() and the
## authored _triggeringDuration (0.5 s on 11 placements, null on 125) delays
## the stimulus. A null keeps the family fallback 0.5 s instead of inventing a
## per-instance zero. The alarm then emits the authored 15 m Heavy hearing
## stimulus through NoiseBus, which guards already listen to.

signal alarm_fired(source: Node)
signal power_state_changed(on: bool)

const FALLBACK_TRIGGER_SECONDS: float = 0.5
const STIM_LOUDNESS_M: float = 15.0
const STIM_TAG: String = "noise_alarm"

var device_id: String = ""
var family: String = "noise_alarm"
var params: Dictionary = {}
var trigger_seconds: float = FALLBACK_TRIGGER_SECONDS

var power_source: Node = null
var power_required: bool = true
var _powered: bool = true
var awake: bool = true
var alive: bool = true
var pending_seconds: float = 0.0
var fires: int = 0
var _built: bool = false


func configure(rec: Dictionary, family_defaults: Dictionary, difficulty_value: int = -1) -> void:
	device_id = str(rec.get("id", ""))
	family = str(rec.get("family", "noise_alarm"))
	var params_v: Variant = rec.get("params", {})
	params = params_v as Dictionary if params_v is Dictionary else {}
	var defaults: Dictionary = family_defaults.get(family, {}) as Dictionary
	var metric: Dictionary = defaults.get("metric", {}) as Dictionary
	var duration_v: Variant = params.get("_triggeringDuration", null)
	if duration_v is float or duration_v is int:
		trigger_seconds = maxf(float(duration_v), 0.0)
	else:
		trigger_seconds = float(metric.get("trigger_seconds", FALLBACK_TRIGGER_SECONDS))
	var power_v: Variant = rec.get("power", {})
	var power: Dictionary = power_v as Dictionary if power_v is Dictionary else {}
	var req_v: Variant = power.get("require", null)
	# The noise-alarm CDO serializes neither require flag; a linked supply is
	# still authored intent, so the null fallback is "requires power".
	power_required = true if req_v == null else bool(req_v)
	_build()


func _ready() -> void:
	add_to_group("devices")
	add_to_group("device_action")
	_build()


func _build() -> void:
	if _built:
		return
	_built = true


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
		pending_seconds = 0.0


func can_trigger() -> bool:
	return alive and awake and (not power_required or _powered)


func set_awake(value: bool) -> void:
	awake = value


## Linked detector entry point. A second call while pending restarts the
## authored delay rather than stacking stimuli.
func trigger_from(_source: Node = null) -> void:
	if not can_trigger():
		return
	if trigger_seconds <= 0.0:
		_emit_alarm()
		return
	pending_seconds = trigger_seconds


func activate_from(source: Node = null) -> void:
	trigger_from(source)


func activate() -> void:
	trigger_from(null)


func tick(delta: float) -> void:
	if pending_seconds <= 0.0:
		return
	if not can_trigger():
		pending_seconds = 0.0
		return
	pending_seconds = maxf(0.0, pending_seconds - delta)
	if pending_seconds <= 0.0:
		_emit_alarm()


func _emit_alarm() -> void:
	fires += 1
	alarm_fired.emit(self)
	NoiseBus.emit_noise(global_position, STIM_LOUDNESS_M, self, STIM_TAG)
