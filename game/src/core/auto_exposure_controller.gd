extends Node
## P4.1b/c runtime adapter: the AEM meter drives the authored auto-exposure.
##
## Only `TAT2_AEM=meter` attaches this node (`setup()` returns false otherwise):
## `fixed` is today's constant path in `weather_profile.gd`, and `model` is the
## static authored-model path there too. This controller owns the live loop:
##   CompositorEffect meter -> measured scene EV100
##   AutoExposure.step(dt, ev100) -> adapted EV100 -> tonemap_exposure
##
## The one global calibration lives in `auto_exposure.gd`
## (`AEM_CALIBRATION`); this file adds no second scale. The integrator's GPU
## run reads the `TAT-2 AEM meter:` lines (one per second once a measurement
## exists) to record the gate-pose residual and, if it re-pins the calibration,
## changes exactly one constant. Headless prints a single `no measurement yet`
## line instead of a per-second pending stream.
##
## Headless: `RenderingServer.get_rendering_device()` is null, the meter never
## produces a measurement, and the exposure keeps its attach value (the
## authored night anchor). No headless run claims the GPU path works.

const AutoExposure := preload("res://src/core/auto_exposure.gd")
const AutoExposureMeter := preload("res://src/core/auto_exposure_meter.gd")

## Scene EV100 the model starts from (the documented shipped-night anchor; the
## authored V3 curve then resolves the -7 EV100 / 1.15 exposure baseline).
const ATTACH_SCENE_EV100 := -3.0
## Calibration-run diagnostics: one line per second, not per frame.
const LOG_INTERVAL_S := 1.0

var env: Environment = null
var preset: Dictionary = {}
## Untyped on purpose: the model/meter are scripts, and this adapter calls
## their own methods (configure/step/exposure, read_ev100/has_measurement).
var model = null
var meter = null
var camera: Camera3D = null
var attached: bool = false

var _compositor: Compositor = null
var _owns_compositor: bool = false
var _log_accum: float = 0.0
var _frames: int = 0
var _pending_logged: bool = false
var _meter_mode: String = AutoExposure.MODE_FIXED


## True when the meter controller should be instantiated at all. Callers use it
## to avoid creating (and leaking) a Node in the default `fixed` path.
static func wanted() -> bool:
	return AutoExposure.mode() == AutoExposure.MODE_METER


## True when this node should be added to the tree.
func setup(environment: Environment, weather_preset: Dictionary) -> bool:
	if environment == null:
		return false
	_meter_mode = AutoExposure.mode()
	if _meter_mode != AutoExposure.MODE_METER:
		return false
	env = environment
	preset = weather_preset
	model = AutoExposure.new()
	model.configure(preset)
	model.reset(ATTACH_SCENE_EV100)
	# Keep the attach frame at the calibration-identical value (1.15).
	env.tonemap_exposure = model.exposure()
	print("TAT-2 AEM meter: attached preset=%s exposure=%.3f (authored %s %.2f..%.2f speed %.2f/%.2f curve=%s); waiting for the GPU meter" % [
		str(preset.get("preset", "?")),
		env.tonemap_exposure,
		str(model.get("method")),
		float(model.get("min_brightness")),
		float(model.get("max_brightness")),
		float(model.get("speed_up")),
		float(model.get("speed_down")),
		str(model.get("bias_curve")),
	])
	return true


func _process(delta: float) -> void:
	if _meter_mode != AutoExposure.MODE_METER or model == null or env == null:
		return
	if not _ensure_camera():
		return
	if meter != null and meter.has_measurement():
		model.step(delta, meter.read_ev100())
		env.tonemap_exposure = model.exposure()
	_frames += 1
	_log_accum += delta
	if _log_accum < LOG_INTERVAL_S:
		return
	_log_accum = 0.0
	var measured: float = meter.read_ev100() if meter != null else NAN
	if not is_finite(measured):
		# Headless (no RenderingDevice) or the first frames: say it once, not
		# once per second, so a calibration log stays readable.
		if not _pending_logged:
			_pending_logged = true
			print("TAT-2 AEM meter: no measurement yet (headless has no RenderingDevice; the GPU run supplies it)")
		return
	print("TAT-2 AEM meter: ev100=%.3f adapted_ev100=%.3f exposure=%.4f calibration=%.9f frames=%d" % [
		measured,
		float(model.call("adapted_ev100")),
		env.tonemap_exposure,
		float(AutoExposure.AEM_CALIBRATION),
		_frames,
	])


func _ensure_camera() -> bool:
	if camera != null and is_instance_valid(camera):
		return true
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	camera = vp.get_camera_3d()
	if camera == null:
		return false
	_attach_meter()
	return true


func _attach_meter() -> void:
	if meter != null or camera == null:
		return
	meter = AutoExposureMeter.new()
	var effects: Array[CompositorEffect] = [meter]
	if camera.compositor == null:
		_compositor = Compositor.new()
		_compositor.compositor_effects = effects
		camera.compositor = _compositor
		_owns_compositor = true
	else:
		var existing: Array[CompositorEffect] = camera.compositor.compositor_effects
		existing.append_array(effects)
		camera.compositor.compositor_effects = existing
	attached = true
	print("TAT-2 AEM meter: CompositorEffect attached to %s" % str(camera.name))


func _exit_tree() -> void:
	if _owns_compositor and camera != null and is_instance_valid(camera) and camera.compositor == _compositor:
		camera.compositor = null
	_compositor = null
	meter = null
	camera = null


func state() -> Dictionary:
	var m: Dictionary = meter.state() if meter != null and meter.has_method("state") else {}
	return {
		"mode": _meter_mode,
		"attached": attached,
		"frames": _frames,
		"exposure": env.tonemap_exposure if env != null else NAN,
		"model": model.state() if model != null else {},
		"meter": m,
	}
