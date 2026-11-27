extends RefCounted
## Authored UE5 auto-exposure (AEM_Basic) as a pure, headless model.
##
## The shipped Gloomy -> Base_Skybox -> Base weather chain authors:
##   Method            AEM_Basic            (BP_WeatherPreset_Base)
##   Min EV100         -10.0                (Base_Skybox)
##   Max EV100          +1.0                (Base, inherited)
##   SpeedUp (f-stops/s)  0.2               (Base, inherited)
##   SpeedDown (f-stops/s) 2.0              (Base, inherited)
##   Bias (EV)           0.0                (Base_Skybox)
##   BiasCurve           Curve_Exposure_Compensation_Float_V3
##                        (Base_Skybox; 8 keys, -0.5 EV at -12.1 to -4.0 EV)
## Source: `tools/parse_weather.py` -> `postprocess.*`; citations in
## `build/qa/w9/re-b1-exposure.md` §1-§2. Nothing here is invented: absent
## fields fall back to the documented authored values with one warning.
##
## What the model does (UE AEM_Basic, the part Godot cannot do itself):
##   target_ev100 = clamp(scene_ev100 + bias + bias_curve(scene_ev100),
##                        min_brightness, max_brightness)
##   adapted_ev100 moves toward target at speed_up (image getting brighter,
##   i.e. target below the current EV100) or speed_down (image getting darker)
##   f-stops per second — UE's asymmetric eye adaptation.
##
## Direction convention (matches the authored 0.2 slow / 2.0 fast pair and the
## plan's "+4 EV 20 s / -4 EV 2 s" probe): a LOWER EV100 is a BRIGHTER image.
## Entering a bright place darkens the image (EV100 rises) at 2.0 EV/s; dark
## adaptation (+exposure, EV100 falls) takes 0.2 EV/s.
##
## `AEM_CALIBRATION` is the port's ONE global calibration from the authored
## EV100 model to Godot's `Environment.tonemap_exposure` (a linear multiplier).
## It is pinned so that the authored night anchor (scene EV100 -3.0 -> curve
## -4.0 -> adapted EV100 -7.0) reproduces today's measured `NIGHT_EXPOSURE`
## 1.15 exactly:
##     exposure = AEM_CALIBRATION * 2^-adapted_ev100
##     AEM_CALIBRATION = 1.15 * 2^-7 = 0.008984375
## The P4.1b/c GPU calibration may re-pin this SINGLE constant (the integrator
## records the gate-pose residual); it is never a per-room or per-preset grade.

const MODE_FIXED := "fixed"
const MODE_MODEL := "model"
const MODE_METER := "meter"
const MODES: Array[String] = [MODE_FIXED, MODE_MODEL, MODE_METER]

## Authored defaults (Base_Skybox / Base chain; see header). Used when the
## generated preset predates the T01 producer fields.
const DEFAULT_METHOD := "AEM_Basic"
const DEFAULT_MIN_BRIGHTNESS := -10.0
const DEFAULT_MAX_BRIGHTNESS := 1.0
const DEFAULT_SPEED_UP := 0.2
const DEFAULT_SPEED_DOWN := 2.0
const DEFAULT_BIAS := 0.0
const DEFAULT_BIAS_CURVE := "Curve_Exposure_Compensation_Float_V3"

## One global calibration: 1.15 * 2^-7 (see header). Do not add a second.
const AEM_CALIBRATION := 0.008984375
## EV100 the calibration anchor resolves to (authored night anchor -3.0 plus
## the authored V3 bias -4.0).
const AEM_CALIBRATION_EV100 := -7.0
## Today's measured night tonemap exposure, reproduced exactly at the anchor.
const AEM_FIXED_NIGHT_EXPOSURE := 1.15

## Authored `Curve_Exposure_Compensation_Float_V3` keys (x = average scene
## EV100, y = EV bias). The production read is
## `GameData.eval_standalone_curve()` (`curves.json`); these points are the
## transcribed fallback for a tree whose generated curve index is missing and
## for the headless probe's point assertions. Linear interpolation, clamped at
## both ends (all keys are authored RCIM_Linear).
const V3_CURVE_POINTS: Array[Vector2] = [
	Vector2(-12.1, -0.5), Vector2(-11.1, -1.5), Vector2(-10.1, -2.0),
	Vector2(-9.1, -2.25), Vector2(-8.1, -2.5), Vector2(-6.1, -3.0),
	Vector2(-3.0, -4.0), Vector2(0.2, -4.0),
]

var method: String = DEFAULT_METHOD
var min_brightness: float = DEFAULT_MIN_BRIGHTNESS
var max_brightness: float = DEFAULT_MAX_BRIGHTNESS
var speed_up: float = DEFAULT_SPEED_UP
var speed_down: float = DEFAULT_SPEED_DOWN
var bias: float = DEFAULT_BIAS
var bias_curve: String = DEFAULT_BIAS_CURVE
## True when configure() found the authored producer fields in the preset.
var authored: bool = false
var _adapted_ev100: float = 0.0
var _steps: int = 0
var _elapsed: float = 0.0

static var _fallback_curve_warned: bool = false
static var _mode_warned: bool = false


## `TAT2_AEM=fixed|model|meter`. Unset/unknown -> fixed (today's behaviour).
static func mode() -> String:
	var raw: String = OS.get_environment("TAT2_AEM").strip_edges().to_lower()
	if raw == "":
		return MODE_FIXED
	if MODES.has(raw):
		return raw
	if not _mode_warned:
		_mode_warned = true
		push_warning("TAT2_AEM='%s' is not one of %s; using fixed" % [raw, str(MODES)])
	return MODE_FIXED


## Configure from one generated weather preset. The authored chain values are
## the fallback, never a neutral zero: a stale preset must still meter with the
## shipped -10/+1, 0.2/2.0, 0 and V3 curve rather than an invented daytime one.
func configure(preset: Dictionary) -> void:
	var pp_v: Variant = preset.get("postprocess", {})
	var pp: Dictionary = pp_v as Dictionary if pp_v is Dictionary else {}
	method = str(pp.get("auto_exposure_method", DEFAULT_METHOD))
	if method == "":
		method = DEFAULT_METHOD
	min_brightness = _num(pp.get("min_brightness"), DEFAULT_MIN_BRIGHTNESS)
	max_brightness = _num(pp.get("max_brightness"), DEFAULT_MAX_BRIGHTNESS)
	speed_up = maxf(0.0, _num(pp.get("speed_up"), DEFAULT_SPEED_UP))
	speed_down = maxf(0.0, _num(pp.get("speed_down"), DEFAULT_SPEED_DOWN))
	bias = _num(pp.get("auto_exposure_bias"), DEFAULT_BIAS)
	bias_curve = str(pp.get("bias_curve", ""))
	if bias_curve == "":
		bias_curve = DEFAULT_BIAS_CURVE
	authored = pp.has("auto_exposure_method") and pp.has("min_brightness") \
		and pp.has("max_brightness") and pp.has("speed_up") \
		and pp.has("speed_down") and pp.has("bias_curve")
	if min_brightness > max_brightness:
		# A reversed pair would make every clamp meaningless; keep the authored
		# numbers as data but order the clamp bounds deterministically.
		var lo: float = max_brightness
		max_brightness = min_brightness
		min_brightness = lo


## Adapted EV100 for a converged model at `scene_ev100` (no transient).
func reset(scene_ev100: float = 0.0) -> void:
	_adapted_ev100 = target(scene_ev100)
	_steps = 0
	_elapsed = 0.0


## One time step toward the authored target. Returns the adapted EV100 (lower
## is a brighter image; see header). `dt` seconds, `ev100` the measured/average
## scene EV100. dt <= 0 is a no-op (never teleports the adaptation).
func step(dt: float, ev100: float) -> float:
	if dt <= 0.0:
		return _adapted_ev100
	var tgt: float = target(ev100)
	var delta: float = tgt - _adapted_ev100
	var rate: float = speed_up if delta < 0.0 else speed_down
	var max_step: float = rate * dt
	if absf(delta) <= max_step or max_step <= 0.0:
		_adapted_ev100 = tgt
	else:
		_adapted_ev100 += signf(delta) * max_step
	_steps += 1
	_elapsed += dt
	return _adapted_ev100


## The authored clamp applied to scene EV100 + bias + bias curve.
func target(scene_ev100: float) -> float:
	var raw: float = scene_ev100 + bias_at(scene_ev100)
	return clampf(raw, min_brightness, max_brightness)


## Authored Bias + AutoExposureBiasCurve at the measured scene EV100.
func bias_at(scene_ev100: float) -> float:
	return bias + curve_value(bias_curve, scene_ev100)


## Godot tonemap multiplier for the current adapted EV100 (see AEM_CALIBRATION).
func exposure() -> float:
	return AEM_CALIBRATION * pow(2.0, -_adapted_ev100)


func adapted_ev100() -> float:
	return _adapted_ev100


func state() -> Dictionary:
	return {
		"method": method,
		"min_brightness": min_brightness,
		"max_brightness": max_brightness,
		"speed_up": speed_up,
		"speed_down": speed_down,
		"bias": bias,
		"bias_curve": bias_curve,
		"authored": authored,
		"adapted_ev100": _adapted_ev100,
		"exposure": exposure(),
		"steps": _steps,
		"elapsed": _elapsed,
		"calibration": AEM_CALIBRATION,
	}


## Authored V3 bias read through GameData's standalone curve index, with the
## transcribed keys as the fallback. This is what `WeatherProfile.ev_curve_bias`
## delegates to; the hard-coded table exists once, here.
static func ev_curve_bias(ev100: float) -> float:
	return curve_value(DEFAULT_BIAS_CURVE, ev100)


## Named authored curve evaluation. Unknown name / no index -> 0.0 EV unless the
## name is the V3 curve, whose transcribed keys are the documented fallback.
static func curve_value(curve_name: String, ev100: float) -> float:
	var gd: Node = _game_data()
	if gd != null and gd.has_method("eval_standalone_curve"):
		var got: Variant = gd.call("eval_standalone_curve", curve_name, ev100, "Value", NAN)
		if got is float and not is_nan(got as float):
			return got as float
	if curve_name == DEFAULT_BIAS_CURVE:
		if not _fallback_curve_warned:
			_fallback_curve_warned = true
			print("TAT-2 AEM: curves.json has no %s; using the transcribed 8-key table" % curve_name)
		return eval_points(V3_CURVE_POINTS, ev100)
	return 0.0


## Piecewise-linear read with end clamps, matching the authored RCIM_Linear keys.
static func eval_points(points: Array[Vector2], x: float) -> float:
	if points.is_empty():
		return 0.0
	if x <= points[0].x:
		return points[0].y
	for i: int in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		if x <= b.x:
			var span: float = b.x - a.x
			var t: float = 0.0 if is_zero_approx(span) else (x - a.x) / span
			return lerpf(a.y, b.y, t)
	return points[points.size() - 1].y


## Converged exposure for `preset` at a known/measured scene EV100. This is the
## static (no meter) use: it applies exactly the authored clamp + bias curve.
static func exposure_for_preset(preset: Dictionary, scene_ev100: float) -> float:
	var m := new()
	m.configure(preset)
	m.reset(scene_ev100)
	return m.exposure()


static func _num(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		return float(v)
	return fallback


static func _game_data() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("GameData")
	return null
