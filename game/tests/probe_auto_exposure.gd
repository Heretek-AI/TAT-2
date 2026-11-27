extends SceneTree
## P4.1a/b headless probe: authored auto-exposure data, the pure AEM model and
## the meter's log-luminance reduction.
##
##   tools/godot --headless --path game --script res://tests/probe_auto_exposure.gd
##
## No GPU, no Vulkan, no Xvfb, no capture. Exit 0 = every check passed. The GPU
## meter shader is NOT executed here: `AutoExposureMeter.reduce_log_luminance()`
## is the deterministic CPU mirror the synthetic harness asserts, and the live
## CompositorEffect is the integrator's `TAT2_AEM=meter` run.
##
## Data assertions are deliberately two-layered:
##   1. the raw authored dumps under `extracted/json/...` (when present) must
##      carry Base -3.5/1.0/0.5/V1 and Base_Skybox -10.0/0.0/V3; the merged
##      shipped chain is therefore -10/+1/0.2/2.0/0/V3;
##   2. `game/data/generated/weather/gloomy.json` must carry the producer
##      fields once `make normalize` has run. Before that regeneration the probe
##      prints a PENDING line instead of inventing a pass or failing the lane
##      that cannot write shared generated data.

const AutoExposure := preload("res://src/core/auto_exposure.gd")
const MeterScript := preload("res://src/core/auto_exposure_meter.gd")
const WeatherProfile := preload("res://src/core/weather_profile.gd")

const RAW_WEATHER := "extracted/json/Art/Environment/Weather/"
const GENERATED_GLOOMY := "res://data/generated/weather/gloomy.json"
const AUTHORED_CURVE := "Curve_Exposure_Compensation_Float_V3"
const AEM_TOL := 1e-6

var fails: int = 0
var checks: int = 0
var _env_backup: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, title: String, detail: String = "") -> void:
	checks += 1
	if cond:
		print("PASS: ", title, ("" if detail == "" else " (" + detail + ")"))
	else:
		printerr("FAIL: ", title, ("" if detail == "" else " (" + detail + ")"))
		fails += 1


func _run() -> void:
	await process_frame
	_env_backup = OS.get_environment("TAT2_AEM")
	var gd: Node = root.get_node_or_null("GameData")
	_check(gd != null, "GameData autoload present", "null" if gd == null else "ok")

	var preset: Dictionary = _read_json(GENERATED_GLOOMY)
	_check(not preset.is_empty(), "generated gloomy preset readable", GENERATED_GLOOMY)
	if preset.is_empty():
		_finish()
		return

	_test_raw_authored_chain()
	_test_generated_fields(preset)
	_test_model_fields(preset)
	_test_curve(gd)
	_test_fixed_mode(preset)
	_test_model_anchor(preset)
	_test_speeds()
	_test_clamps_and_determinism()
	_test_meter_reduction()
	_test_mode_env()
	_finish()


# ------------------------------------------------------------------ data tests
## Raw authored CDO chain: Base authors -3.5/1.0/0.5/V1; Base_Skybox overrides
## Min -10.0, Bias 0.0 and V3, so the shipped Gloomy chain is
## -10/+1, 0.2/2.0, 0, V3. Read from the private extract when it is present.
func _test_raw_authored_chain() -> void:
	var base_dump: String = _repo_path(RAW_WEATHER + "BP_WeatherPreset_Base.json")
	var sky_dump: String = _repo_path(RAW_WEATHER + "BP_WeatherPreset_Base_Skybox.json")
	if not FileAccess.file_exists(base_dump) or not FileAccess.file_exists(sky_dump):
		print("PENDING: raw weather dumps not present (private extract); chain values pinned by the generated-data test after make normalize")
		return
	var base: Dictionary = _postprocess_settings(base_dump)
	var sky: Dictionary = _postprocess_settings(sky_dump)
	_check(str(base.get("AutoExposureMethod", "")) == "EAutoExposureMethod::AEM_Basic",
		"Base authors AEM_Basic", str(base.get("AutoExposureMethod", "")))
	_check(is_equal_approx(float(base.get("AutoExposureMinBrightness", 0.0)), -3.5),
		"Base MinBrightness is the inherited -3.5 (not the shipped clamp)",
		str(base.get("AutoExposureMinBrightness", "")))
	_check(is_equal_approx(float(base.get("AutoExposureMaxBrightness", 0.0)), 1.0),
		"Base MaxBrightness +1.0", str(base.get("AutoExposureMaxBrightness", "")))
	_check(is_equal_approx(float(base.get("AutoExposureSpeedUp", 0.0)), 0.2),
		"Base SpeedUp 0.2 f-stops/s", str(base.get("AutoExposureSpeedUp", "")))
	_check(is_equal_approx(float(base.get("AutoExposureSpeedDown", 0.0)), 2.0),
		"Base SpeedDown 2.0 f-stops/s", str(base.get("AutoExposureSpeedDown", "")))
	_check(is_equal_approx(float(base.get("AutoExposureBias", 1.0)), 0.5),
		"Base Bias +0.5 (overridden by Skybox)", str(base.get("AutoExposureBias", "")))
	_check(_curve_name(base) == "Curve_Exposure_Compensation_Float",
		"Base selects the V1 curve", _curve_name(base))
	_check(is_equal_approx(float(sky.get("AutoExposureMinBrightness", 0.0)), -10.0),
		"Base_Skybox MinBrightness -10.0 (the shipped clamp)", str(sky.get("AutoExposureMinBrightness", "")))
	_check(is_equal_approx(float(sky.get("AutoExposureBias", 1.0)), 0.0),
		"Base_Skybox Bias 0.0", str(sky.get("AutoExposureBias", "")))
	_check(_curve_name(sky) == AUTHORED_CURVE,
		"Base_Skybox selects the V3 curve", _curve_name(sky))
	_check(not sky.has("AutoExposureMethod") and not sky.has("AutoExposureSpeedUp"),
		"Base_Skybox inherits Method/Speeds from Base", "inherited")
	# The shipped chain = Base overridden by Base_Skybox (the child wins).
	var merged: Dictionary = base.duplicate(true)
	for key: Variant in sky.keys():
		merged[key] = sky[key]
	var merged_curve: String = _curve_name(merged)
	var merged_ok: bool = str(merged.get("AutoExposureMethod", "")) == "EAutoExposureMethod::AEM_Basic" \
		and is_equal_approx(float(merged.get("AutoExposureMinBrightness", 0.0)), -10.0) \
		and is_equal_approx(float(merged.get("AutoExposureMaxBrightness", 0.0)), 1.0) \
		and is_equal_approx(float(merged.get("AutoExposureSpeedUp", 0.0)), 0.2) \
		and is_equal_approx(float(merged.get("AutoExposureSpeedDown", 0.0)), 2.0) \
		and is_equal_approx(float(merged.get("AutoExposureBias", 1.0)), 0.0) \
		and merged_curve == AUTHORED_CURVE
	_check(merged_ok, "shipped merged chain is AEM_Basic -10/+1, 0.2/2.0, 0, V3",
		"min=%s max=%s speed=%s/%s bias=%s curve=%s" % [
			str(merged.get("AutoExposureMinBrightness", "")),
			str(merged.get("AutoExposureMaxBrightness", "")),
			str(merged.get("AutoExposureSpeedUp", "")),
			str(merged.get("AutoExposureSpeedDown", "")),
			str(merged.get("AutoExposureBias", "")),
			merged_curve,
		])


## Generated producer fields (after `make normalize`).
func _test_generated_fields(preset: Dictionary) -> void:
	var pp_v: Variant = preset.get("postprocess", {})
	var pp: Dictionary = pp_v as Dictionary if pp_v is Dictionary else {}
	if not pp.has("auto_exposure_method"):
		print("PENDING: weather/gloomy.json predates the P4.1 producer fields; the integrator runs make normalize, then this block asserts -10/+1, 0.2/2.0, 0, V3 strictly")
		return
	_check(str(pp.get("auto_exposure_method", "")) == "AEM_Basic",
		"generated method AEM_Basic", str(pp.get("auto_exposure_method", "")))
	_check(is_equal_approx(float(pp.get("min_brightness", 0.0)), -10.0),
		"generated min_brightness -10.0", str(pp.get("min_brightness", "")))
	_check(is_equal_approx(float(pp.get("max_brightness", 0.0)), 1.0),
		"generated max_brightness +1.0", str(pp.get("max_brightness", "")))
	_check(is_equal_approx(float(pp.get("speed_up", 0.0)), 0.2),
		"generated speed_up 0.2", str(pp.get("speed_up", "")))
	_check(is_equal_approx(float(pp.get("speed_down", 0.0)), 2.0),
		"generated speed_down 2.0", str(pp.get("speed_down", "")))
	_check(is_equal_approx(float(pp.get("auto_exposure_bias", 1.0)), 0.0),
		"generated bias 0.0", str(pp.get("auto_exposure_bias", "")))
	_check(str(pp.get("bias_curve", "")) == AUTHORED_CURVE,
		"generated bias_curve V3", str(pp.get("bias_curve", "")))


# --------------------------------------------------------------------- model
func _test_model_fields(preset: Dictionary) -> void:
	var m = AutoExposure.new()
	m.configure(preset)
	_check(str(m.get("method")) == "AEM_Basic", "model method AEM_Basic", str(m.get("method")))
	_check(is_equal_approx(float(m.get("min_brightness")), -10.0), "model clamp min -10.0")
	_check(is_equal_approx(float(m.get("max_brightness")), 1.0), "model clamp max +1.0")
	_check(is_equal_approx(float(m.get("speed_up")), 0.2), "model speed_up 0.2")
	_check(is_equal_approx(float(m.get("speed_down")), 2.0), "model speed_down 2.0")
	_check(is_equal_approx(float(m.get("bias")), 0.0), "model bias 0.0")
	_check(str(m.get("bias_curve")) == AUTHORED_CURVE, "model bias curve V3", str(m.get("bias_curve")))
	var st: Dictionary = m.state()
	for key: String in ["method", "min_brightness", "max_brightness", "speed_up", "speed_down", "bias", "bias_curve", "adapted_ev100", "exposure", "steps", "calibration"]:
		if not st.has(key):
			_check(false, "model state carries %s" % key)
			return
	_check(true, "model state carries the documented keys", "%d keys" % st.size())
	_check(is_equal_approx(float(AutoExposure.AEM_CALIBRATION) * pow(2.0, -float(AutoExposure.AEM_CALIBRATION_EV100)), AutoExposure.AEM_FIXED_NIGHT_EXPOSURE),
		"AEM_CALIBRATION resolves the -7 EV100 anchor to today's 1.15",
		"%.9f * 2^7 = %.9f" % [float(AutoExposure.AEM_CALIBRATION), float(AutoExposure.AEM_CALIBRATION) * 128.0])


func _test_curve(gd: Node) -> void:
	var pts: Array[Vector2] = AutoExposure.V3_CURVE_POINTS
	var expect: Array = [
		[-12.1, -0.5], [-11.1, -1.5], [-10.1, -2.0], [-9.1, -2.25],
		[-8.1, -2.5], [-6.1, -3.0], [-3.0, -4.0], [0.2, -4.0],
	]
	var ok: bool = pts.size() == expect.size()
	for i: int in range(mini(pts.size(), expect.size())):
		if absf(pts[i].x - float(expect[i][0])) > AEM_TOL or absf(pts[i].y - float(expect[i][1])) > AEM_TOL:
			ok = false
	_check(ok, "transcribed V3 table is the authored 8-key curve", "%d keys" % pts.size())
	if gd != null:
		for row: Array in expect:
			var x: float = float(row[0])
			var y: float = float(row[1])
			var via_gd: float = float(gd.call("eval_standalone_curve", AUTHORED_CURVE, x, "Value", NAN))
			if is_nan(via_gd):
				_check(false, "GameData curve index has %s" % AUTHORED_CURVE)
				return
			var via_static: float = AutoExposure.ev_curve_bias(x)
			var via_weather: float = WeatherProfile.ev_curve_bias(x)
			if absf(via_gd - y) > AEM_TOL or absf(via_static - y) > AEM_TOL or absf(via_weather - y) > AEM_TOL:
				_check(false, "V3 key %+.1f" % x, "game_data=%.6f static=%.6f weather=%.6f want=%.6f" % [via_gd, via_static, via_weather, y])
				return
		_check(true, "all 8 V3 keys match 3 readers", "GameData + AutoExposure + WeatherProfile")
		_check(is_equal_approx(float(gd.call("eval_standalone_curve", AUTHORED_CURVE, -40.0, "Value", NAN)), -0.5),
			"V3 clamps before the first key", "-0.5")
		# Linear interpolation between -11.1/-1.5 and -10.1/-2.0.
		_check(is_equal_approx(float(gd.call("eval_standalone_curve", AUTHORED_CURVE, -10.6, "Value", NAN)), -1.75),
			"V3 interpolates linearly", "-10.6 -> -1.75")
		_check(is_equal_approx(float(gd.call("eval_standalone_curve", AUTHORED_CURVE, 9.0, "Value", NAN)), -4.0),
			"V3 saturates at -4.0 after the last key", "9.0 -> -4.0")
	else:
		_check(false, "GameData autoload missing for the curve assertion")


## `TAT2_AEM=fixed` (and the default) must reproduce today's 1.15 exactly.
func _test_fixed_mode(preset: Dictionary) -> void:
	OS.set_environment("TAT2_AEM", "fixed")
	_check(AutoExposure.mode() == "fixed", "TAT2_AEM=fixed selects fixed")
	var env := Environment.new()
	var moon := DirectionalLight3D.new()
	var applied: bool = WeatherProfile.apply_environment(env, moon, preset)
	_check(applied, "fixed: authored gloomy preset applies")
	_check(is_equal_approx(env.tonemap_exposure, WeatherProfile.NIGHT_EXPOSURE),
		"fixed reproduces today's 1.15 exactly", "exposure=%.6f" % env.tonemap_exposure)
	_check(is_equal_approx(env.tonemap_exposure, AutoExposure.AEM_FIXED_NIGHT_EXPOSURE),
		"fixed matches the model's calibration anchor", "%.6f" % env.tonemap_exposure)
	_check(env.tonemap_mode == Environment.TONE_MAPPER_AGX, "fixed keeps the AGX night tonemapper")
	moon.free()


## `TAT2_AEM=model` uses the authored fields and resolves to the same 1.15 at
## the documented night anchor (a no-op there, by construction).
func _test_model_anchor(preset: Dictionary) -> void:
	OS.set_environment("TAT2_AEM", "model")
	_check(AutoExposure.mode() == "model", "TAT2_AEM=model selects the model")
	var env := Environment.new()
	var moon := DirectionalLight3D.new()
	var applied: bool = WeatherProfile.apply_environment(env, moon, preset)
	_check(applied, "model: authored gloomy preset applies")
	_check(is_equal_approx(env.tonemap_exposure, AutoExposure.AEM_FIXED_NIGHT_EXPOSURE),
		"model at the night anchor equals the fixed 1.15",
		"exposure=%.6f" % env.tonemap_exposure)
	moon.free()


## Asymmetric authored speeds, in EV100 terms: RISING +4 (dark -> bright,
## SpeedUp 0.2) takes 20 s; FALLING -4 (bright -> dark, SpeedDown 2.0) takes
## 2 s. A flat synthetic curve isolates the ramp from the V3 curve. The
## measured-times comparison is the negative control against an inverted
## SpeedUp/SpeedDown mapping.
func _test_speeds() -> void:
	var m = _flat_model()
	# +4 EV100: -8 -> -4, both inside the authored -10..+1 clamp.
	m.reset(-8.0)
	_check(is_equal_approx(float(m.call("adapted_ev100")), -8.0), "flat model starts converged at -8 EV100")
	var first: float = float(m.call("step", 0.1, -4.0))
	_check(is_equal_approx(first - (-8.0), 0.02), "SpeedUp ramp is +0.2 EV100/s per 0.1 s",
		"delta=%+.6f" % (first - (-8.0)))
	for _i: int in range(198):
		m.call("step", 0.1, -4.0)
	_check(float(m.call("adapted_ev100")) < -4.0 - 1e-4, "after 19.9 s the +4 EV100 ramp is not settled",
		"adapted=%.6f" % float(m.call("adapted_ev100")))
	m.call("step", 0.1, -4.0)
	_check(is_equal_approx(float(m.call("adapted_ev100")), -4.0), "+4 EV100 settles at 20.0 s at the authored SpeedUp 0.2",
		"adapted=%.6f" % float(m.call("adapted_ev100")))
	_check(is_equal_approx(float(m.call("exposure")), float(AutoExposure.AEM_CALIBRATION) * 16.0),
		"adapted EV100 -4 is 2^4 brighter than the anchor", "exposure=%.9f" % float(m.call("exposure")))

	# -4 EV100: +1 -> -3 (the authored max clamp down to the dark anchor),
	# SpeedDown 2.0.
	m.reset(1.0)
	var down_first: float = float(m.call("step", 0.1, -3.0))
	_check(is_equal_approx(down_first - 1.0, -0.2), "SpeedDown ramp is -2.0 EV100/s per 0.1 s",
		"delta=%+.6f" % (down_first - 1.0))
	for _i: int in range(18):
		m.call("step", 0.1, -3.0)
	_check(float(m.call("adapted_ev100")) > -3.0 + 1e-4, "after 1.9 s the -4 EV100 ramp is not settled",
		"adapted=%.6f" % float(m.call("adapted_ev100")))
	m.call("step", 0.1, -3.0)
	_check(is_equal_approx(float(m.call("adapted_ev100")), -3.0), "-4 EV100 settles at 2.0 s at the authored SpeedDown 2.0",
		"adapted=%.6f" % float(m.call("adapted_ev100")))
	_check(float(m.call("step", 0.0, 40.0)) == -3.0, "dt=0 never teleports the adaptation")
	m.call("step", 5.0, -40.0)
	_check(is_equal_approx(float(m.call("adapted_ev100")), -10.0), "a huge step still clamps at min -10.0",
		"adapted=%.6f" % float(m.call("adapted_ev100")))

	# Measured negative control: with the authored 0.2/2.0 pair the rising
	# (+4, SpeedUp) ramp must be ~10x slower than the falling (-4, SpeedDown)
	# ramp. An inverted selection would make this 2.0 s vs 20.0 s and fail.
	var t_up: float = _time_to_settle(-8.0, -4.0)
	var t_down: float = _time_to_settle(1.0, -3.0)
	_check(t_up > t_down * 5.0, "+4 EV100 (SpeedUp) is strictly slower than -4 EV100 (SpeedDown)",
		"t_up=%.2fs t_down=%.2fs" % [t_up, t_down])
	_check(absf(t_up - 20.0) < 0.15 and absf(t_down - 2.0) < 0.15,
		"measured settle times are the authored 20 s / 2 s",
		"t_up=%.2fs t_down=%.2fs" % [t_up, t_down])


## Wall-clock seconds for the flat model to reach its clamp at `ev100`, stepping
## 0.05 s (test-only mirror of the same `step` call).
func _time_to_settle(start_ev100: float, ev100: float) -> float:
	var m = _flat_model()
	m.reset(start_ev100)
	var t: float = 0.0
	var want: float = float(m.call("target", ev100))
	while t < 60.0:
		m.call("step", 0.05, ev100)
		t += 0.05
		if is_equal_approx(float(m.call("adapted_ev100")), want):
			return t
	return INF


## Authored clamps + determinism + the V3 target at the documented anchors.
func _test_clamps_and_determinism() -> void:
	var preset := {
		"postprocess": {
			"auto_exposure_method": "AEM_Basic",
			"min_brightness": -10.0,
			"max_brightness": 1.0,
			"speed_up": 0.2,
			"speed_down": 2.0,
			"auto_exposure_bias": 0.0,
			"bias_curve": AUTHORED_CURVE,
		},
	}
	var m = AutoExposure.new()
	m.configure(preset)
	_check(is_equal_approx(float(m.call("target", -3.0)), -7.0), "V3 target at the -3.0 night anchor is -7.0 EV100",
		"%.6f" % float(m.call("target", -3.0)))
	_check(is_equal_approx(float(m.call("target", -20.0)), -10.0), "target clamps at min -10.0 EV100",
		"%.6f" % float(m.call("target", -20.0)))
	_check(is_equal_approx(float(m.call("target", 20.0)), 1.0), "target clamps at max +1.0 EV100",
		"%.6f" % float(m.call("target", 20.0)))
	_check(absf(float(m.call("bias_at", -3.0)) + 4.0) < 1e-5, "authored bias at -3.0 is -4.0 EV (bias 0 + V3)",
		"%.6f" % float(m.call("bias_at", -3.0)))

	# Same input sequence twice -> identical float state.
	var a = AutoExposure.new()
	a.configure(preset)
	a.reset(-3.0)
	var b = AutoExposure.new()
	b.configure(preset)
	b.reset(-3.0)
	for i: int in range(120):
		var ev: float = -3.0 + sin(float(i) * 0.1) * 4.0
		a.call("step", 1.0 / 60.0, ev)
		b.call("step", 1.0 / 60.0, ev)
	_check(float(a.call("adapted_ev100")) == float(b.call("adapted_ev100")),
		"the model is deterministic for an identical sequence", "%.9f" % float(a.call("adapted_ev100")))

	# dt subdivision in the linear phase: 1 s steps vs 0.05 s steps.
	var c = AutoExposure.new()
	c.configure(preset)
	c.reset(0.0)
	var d = AutoExposure.new()
	d.configure(preset)
	d.reset(0.0)
	for _i: int in range(3):
		c.call("step", 1.0, -9.0)
	for _i: int in range(60):
		d.call("step", 0.05, -9.0)
	_check(absf(float(c.call("adapted_ev100")) - float(d.call("adapted_ev100"))) < 1e-9,
		"dt subdivision does not change the linear ramp",
		"1s=%.9f 0.05s=%.9f" % [float(c.call("adapted_ev100")), float(d.call("adapted_ev100"))])


## CPU mirror of the GPU log-luminance reduction (the shader is not run here).
func _test_meter_reduction() -> void:
	var flat: PackedFloat32Array = PackedFloat32Array()
	flat.resize(64 * 64)
	flat.fill(0.18)
	var r: Dictionary = MeterScript.reduce_log_luminance(flat, 64, 64)
	var want: float = log(18.0) / log(2.0)
	_check(is_equal_approx(float(r.get("ev100", 0.0)), want), "0.18 grey meters log2(18) EV100",
		"%.6f want %.6f" % [float(r.get("ev100", 0.0)), want])
	_check(int(r.get("groups", 0)) == 4, "64x64 is four 32x32 meter groups", "%d" % int(r.get("groups", 0)))
	_check(int(r.get("samples", 0)) == 64 * 64, "the reduction covers every pixel", "%d" % int(r.get("samples", 0)))

	var bright: PackedFloat32Array = PackedFloat32Array()
	bright.resize(64 * 64)
	bright.fill(0.36)
	var r2: Dictionary = MeterScript.reduce_log_luminance(bright, 64, 64)
	_check(absf(float(r2.get("ev100", 0.0)) - float(r.get("ev100", 0.0)) - 1.0) < AEM_TOL,
		"doubling luminance is exactly +1 EV100",
		"%.6f -> %.6f" % [float(r.get("ev100", 0.0)), float(r2.get("ev100", 0.0))])

	var black: PackedFloat32Array = PackedFloat32Array()
	black.resize(64 * 64)
	black.fill(0.0)
	var r3: Dictionary = MeterScript.reduce_log_luminance(black, 64, 64)
	_check(float(r3.get("ev100", 0.0)) < -13.0 and is_finite(float(r3.get("ev100", 0.0))),
		"black pixels use the EPS floor, never -inf", "%.6f" % float(r3.get("ev100", 0.0)))

	# Equal-sized tiles: the tile-average mean equals the global mean. (The
	# meter is a mean of per-tile averages, so a partial edge tile carries the
	# same weight; that residual is constant per resolution and documented.)
	var w: int = 64
	var h: int = 32
	var grad: PackedFloat32Array = PackedFloat32Array()
	grad.resize(w * h)
	var brute: float = 0.0
	for y: int in range(h):
		for x: int in range(w):
			var v: float = 0.001 + 0.5 * (float(x + y) / float(w + h))
			grad[y * w + x] = v
			brute += log(maxf(v, 1e-6) * 100.0) / log(2.0)
	brute /= float(w * h)
	var r4: Dictionary = MeterScript.reduce_log_luminance(grad, w, h)
	_check(int(r4.get("groups", 0)) == 2, "64x32 uses two equal 32x32 groups", "%d" % int(r4.get("groups", 0)))
	_check(absf(float(r4.get("ev100", 0.0)) - brute) < 1e-5, "gradient EV100 matches the brute-force mean",
		"%.9f vs %.9f" % [float(r4.get("ev100", 0.0)), brute])
	var odd: PackedFloat32Array = PackedFloat32Array()
	odd.resize(40 * 20)
	odd.fill(0.1)
	var r_odd: Dictionary = MeterScript.reduce_log_luminance(odd, 40, 20)
	_check(int(r_odd.get("groups", 0)) == 2, "40x20 uses two groups (2x1, one partial)", "%d" % int(r_odd.get("groups", 0)))

	var short_buf: PackedFloat32Array = PackedFloat32Array([0.1, 0.2])
	var r5: Dictionary = MeterScript.reduce_log_luminance(short_buf, 4, 4)
	_check(is_nan(float(r5.get("ev100", 0.0))), "a short pixel buffer is refused (NAN), not guessed")

	var meter = MeterScript.new()
	_check(int(meter.get("effect_callback_type")) == CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT,
		"meter registers at POST_TRANSPARENT")
	_check(not meter.has_measurement(), "meter has no measurement before the GPU run")
	_check(is_nan(float(meter.read_ev100())), "meter read_ev100 is NAN headless")
	var st: Dictionary = meter.state()
	_check(st.has("ev100") and st.has("readbacks") and st.has("groups"), "meter state exposes ev100/readbacks/groups")
	meter = null

	# The compute shader is compiled to SPIR-V at import time (no GPU needed to
	# check that); the dispatch itself is the integrator's GPU run.
	var shader_res: Resource = load("res://src/core/auto_exposure_meter.glsl")
	if shader_res is RDShaderFile:
		var spirv: RDShaderSPIRV = (shader_res as RDShaderFile).get_spirv()
		_check(spirv != null and spirv.compile_error_compute == "" and spirv.bytecode_compute.size() > 0,
			"meter GLSL compiles to SPIR-V", "bytes=%d" % (spirv.bytecode_compute.size() if spirv != null else 0))
	else:
		print("PENDING: the meter .glsl is not imported yet (run tools/godot --headless --path game --import)")


func _test_mode_env() -> void:
	OS.set_environment("TAT2_AEM", "bogus")
	_check(AutoExposure.mode() == "fixed", "an unknown TAT2_AEM falls back to fixed")
	OS.set_environment("TAT2_AEM", "meter")
	_check(AutoExposure.mode() == "meter", "TAT2_AEM=meter selects the meter")


func _flat_model():
	var m = AutoExposure.new()
	m.configure({
		"postprocess": {
			"auto_exposure_method": "AEM_Basic",
			"min_brightness": -10.0,
			"max_brightness": 1.0,
			"speed_up": 0.2,
			"speed_down": 2.0,
			"auto_exposure_bias": 0.0,
			"bias_curve": "Curve_Flat_Test",
		},
	})
	return m


# --------------------------------------------------------------------- helpers
func _postprocess_settings(path: String) -> Dictionary:
	var exports: Variant = _read_json_array(path)
	if not (exports is Array):
		return {}
	for e: Variant in (exports as Array):
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e as Dictionary
		if str(ed.get("Type", "")) != "PostProcessComponent":
			continue
		var props_v: Variant = ed.get("Properties", {})
		var props: Dictionary = props_v as Dictionary if props_v is Dictionary else {}
		var settings_v: Variant = props.get("Settings", {})
		if settings_v is Dictionary and not (settings_v as Dictionary).is_empty():
			return settings_v as Dictionary
	return {}


func _curve_name(settings: Dictionary) -> String:
	var c_v: Variant = settings.get("AutoExposureBiasCurve", {})
	var c: Dictionary = c_v as Dictionary if c_v is Dictionary else {}
	var obj: String = str(c.get("ObjectName", ""))
	var m := RegEx.create_from_string("'([^']+)'")
	var hit: RegExMatch = m.search(obj)
	if hit != null:
		return hit.get_string(1)
	return ""


func _read_json(path: String) -> Dictionary:
	var v: Variant = _read_json_array(path)
	return v as Dictionary if v is Dictionary else {}


func _read_json_array(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _repo_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../" + rel).simplify_path()


func _finish() -> void:
	if _env_backup == "":
		OS.unset_environment("TAT2_AEM")
	else:
		OS.set_environment("TAT2_AEM", _env_backup)
	print("AEM_PROBE: fails=%d passed=%d" % [fails, checks])
	quit(0 if fails == 0 else 1)
