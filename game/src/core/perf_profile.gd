extends RefCounted
## QA performance profile: the single place that turns `--perf-*` command-line
## overrides into runtime settings.
##
## The old "quality ladder" was not real: every capture run logged the same
## WeatherQuality level because nothing parsed an override and `SaveSystem`
## had no `graphics_quality` key. This helper is deliberately explicit and
## fail-closed: an unknown quality, scale, scaling mode or malformed limit is
## an error (the harness exits nonzero) rather than a silent default.
##
## Flags (all optional, all after `--` or before it):
##   --perf-quality=low|medium|high
##   --perf-scale=1.0|0.85|0.75
##   --perf-scaling=bilinear|fsr1|fsr2
##   --perf-lights=N
##   --perf-shadows=N
##   --perf-vsync=off|on
##
## `apply_cli()` is called by the main menu before the mission scene is
## instantiated (and by the perf matrix before it adds the scene), so
## WeatherProfile/MobileProfile read the override during environment setup.
## Values are not persisted; they are a QA envelope over the user's save.

const WeatherProfile: GDScript = preload("res://src/core/weather_profile.gd")
const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")

const QUALITY_KEYS: Array[String] = ["low", "medium", "high"]
const SCALE_VALUES: Array[float] = [1.0, 0.85, 0.75]
const SCALING_KEYS: Array[String] = ["bilinear", "fsr1", "fsr2"]
const MAX_LIMIT: int = 4096


## Parses only `--perf-*` args. Returns a config dictionary:
##   ok (bool), errors (Array[String]), requested (bool),
##   quality (String), quality_index (int, -1 when unset),
##   scale (float, -1 when unset), scaling (String),
##   lights (int, -1 when unset), shadows (int, -1 when unset),
##   vsync (-1 unchanged, 0 off, 1 on).
## Unknown `--perf-*` flags fail too, so a typo cannot silently measure the
## previous configuration again.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var cfg: Dictionary = {
		"ok": true,
		"errors": [],
		"requested": false,
		"quality": "",
		"quality_index": -1,
		"scale": -1.0,
		"scaling": "",
		"lights": -1,
		"shadows": -1,
		"vsync": -1,
	}
	for raw: String in args:
		var arg: String = raw.strip_edges()
		if not arg.begins_with("--perf-"):
			continue
		# Selector understood by main_menu (starts this runner in exports); it
		# carries no value and must not be mistaken for a typo.
		if arg == "--perf-matrix":
			continue
		cfg["requested"] = true
		if arg.begins_with("--perf-quality="):
			var quality: String = _value(arg).to_lower()
			var q_idx: int = QUALITY_KEYS.find(quality)
			if q_idx < 0:
				_fail(cfg, "--perf-quality must be low|medium|high, got '" + _value(arg) + "'")
			else:
				cfg["quality"] = quality
				cfg["quality_index"] = q_idx
		elif arg.begins_with("--perf-scale="):
			var scale_text: String = _value(arg)
			if not scale_text.is_valid_float():
				_fail(cfg, "--perf-scale must be 1.0|0.85|0.75, got '" + scale_text + "'")
			else:
				var scale: float = float(scale_text)
				var matched: bool = false
				for allowed: float in SCALE_VALUES:
					if is_equal_approx(scale, allowed):
						matched = true
						break
				if not matched:
					_fail(cfg, "--perf-scale must be 1.0|0.85|0.75, got '" + scale_text + "'")
				else:
					cfg["scale"] = scale
		elif arg.begins_with("--perf-scaling="):
			var scaling: String = _value(arg).to_lower()
			if not SCALING_KEYS.has(scaling):
				_fail(cfg, "--perf-scaling must be bilinear|fsr1|fsr2, got '" + _value(arg) + "'")
			else:
				cfg["scaling"] = scaling
		elif arg.begins_with("--perf-lights="):
			cfg["lights"] = _parse_limit(cfg, arg, "--perf-lights")
		elif arg.begins_with("--perf-shadows="):
			cfg["shadows"] = _parse_limit(cfg, arg, "--perf-shadows")
		elif arg.begins_with("--perf-vsync="):
			var vsync: String = _value(arg).to_lower()
			match vsync:
				"off", "disabled":
					cfg["vsync"] = 0
				"on", "enabled":
					cfg["vsync"] = 1
				_:
					_fail(cfg, "--perf-vsync must be off|on, got '" + _value(arg) + "'")
		else:
			_fail(cfg, "unknown performance flag: " + arg)
	return cfg


## Scans user args (after `--`) first, then engine args. Avoids parsing the
## same flag twice when Godot already merged user args into get_cmdline_args().
static func collect_cli_config() -> Dictionary:
	var cfg: Dictionary = parse_args(OS.get_cmdline_user_args())
	if bool(cfg.get("requested", false)):
		return cfg
	return parse_args(OS.get_cmdline_args())


## Applies a parsed config to the live tree and prints one `PERF_CONFIG` line
## with the effective (not merely requested) values. No-op when the config is
## invalid or no perf flags were supplied.
static func apply(tree: SceneTree, cfg: Dictionary, log_line: bool = true) -> void:
	if tree == null or not bool(cfg.get("ok", false)) or not bool(cfg.get("requested", false)):
		return
	var root: Window = tree.root
	var quality_idx: int = int(cfg.get("quality_index", -1))
	if quality_idx >= 0:
		WeatherProfile.set_quality_level(quality_idx)
	var scale: float = float(cfg.get("scale", -1.0))
	if scale > 0.0:
		root.scaling_3d_scale = clampf(scale, 0.5, 1.0)
	var scaling: String = str(cfg.get("scaling", ""))
	if scaling != "":
		match scaling:
			"bilinear":
				root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			"fsr1":
				root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			"fsr2":
				root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	var lights: int = int(cfg.get("lights", -1))
	var shadows: int = int(cfg.get("shadows", -1))
	if lights >= 0 or shadows >= 0:
		MobileProfile.set_override_limits(lights, shadows)
	var vsync: int = int(cfg.get("vsync", -1))
	if vsync >= 0 and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync == 1 else DisplayServer.VSYNC_DISABLED)
	if log_line:
		# stderr is unbuffered: PERF_CONFIG survives a hung window teardown.
		printerr(build_config_line(tree, cfg))


## Convenience for the main menu: parse + apply in one call. Invalid flags do
## not apply anything; the caller decides how loud to be about `errors`.
static func apply_cli(tree: SceneTree) -> Dictionary:
	var cfg: Dictionary = collect_cli_config()
	if bool(cfg.get("ok", false)):
		apply(tree, cfg, true)
	return cfg


static func build_config_line(tree: SceneTree, cfg: Dictionary = {}) -> String:
	var resolution: String = "unknown"
	var window: String = "unknown"
	if tree != null and tree.root != null:
		resolution = "%dx%d" % [tree.root.size.x, tree.root.size.y]
		window = "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	var refresh: float = -1.0
	if DisplayServer.get_name() != "headless":
		refresh = DisplayServer.screen_get_refresh_rate()
		if not is_finite(refresh) or refresh <= 0.0:
			refresh = -1.0
	var effective: Dictionary = {
		"requested": bool(cfg.get("requested", false)),
		"quality": QUALITY_KEYS[clampi(WeatherProfile.quality_level(), 0, QUALITY_KEYS.size() - 1)],
		"quality_level": WeatherProfile.quality_level(),
		"scale": snappedf(_root_scale(tree), 0.001),
		"scaling": _scaling_name(_root_scaling_mode(tree)),
		"vsync": _vsync_name(DisplayServer.window_get_vsync_mode()) if DisplayServer.get_name() != "headless" else "headless",
		"lights": MobileProfile.max_lights(),
		"shadows": MobileProfile.hero_shadows(),
	}
	var line: Dictionary = {
		"git_sha": git_sha(),
		"binary": OS.get_executable_path(),
		"engine": str(Engine.get_version_info().get("string", "unknown")),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"resolution": resolution,
		"window": window,
		"refresh_hz": refresh,
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"gpu_api": RenderingServer.get_video_adapter_api_version(),
		"effective": effective,
	}
	if bool(cfg.get("requested", false)):
		line["args"] = {
			"quality": str(cfg.get("quality", "")),
			"scale": float(cfg.get("scale", -1.0)),
			"scaling": str(cfg.get("scaling", "")),
			"lights": int(cfg.get("lights", -1)),
			"shadows": int(cfg.get("shadows", -1)),
			"vsync": int(cfg.get("vsync", -1)),
		}
	return "PERF_CONFIG " + JSON.stringify(line)


## Build SHA for reports. `TAT_GIT_SHA` wins so an exported binary run from a
## build directory can still record provenance; otherwise ask git in the
## project directory. "unknown" is explicit, never fabricated.
static func git_sha() -> String:
	var env_sha: String = OS.get_environment("TAT_GIT_SHA").strip_edges()
	if env_sha != "":
		return env_sha
	var output: Array = []
	var args: PackedStringArray = PackedStringArray([
		"-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--short=12", "HEAD",
	])
	var code: int = OS.execute("git", args, output, true)
	if code == 0 and not output.is_empty():
		var sha: String = str(output[0]).strip_edges()
		if sha != "":
			return sha
	return "unknown"


static func effective_config(tree: SceneTree) -> Dictionary:
	return {
		"quality": QUALITY_KEYS[clampi(WeatherProfile.quality_level(), 0, QUALITY_KEYS.size() - 1)],
		"quality_level": WeatherProfile.quality_level(),
		"scale": _root_scale(tree),
		"scaling": _scaling_name(_root_scaling_mode(tree)),
		"lights": MobileProfile.max_lights(),
		"shadows": MobileProfile.hero_shadows(),
	}


## Parsed config must equal the live runtime before a measurement run starts.
## Returns an array of human-readable mismatches (empty == match).
static func config_mismatches(tree: SceneTree, cfg: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if tree == null:
		out.append("no SceneTree")
		return out
	if int(cfg.get("quality_index", -1)) >= 0:
		var want_q: int = int(cfg.get("quality_index", -1))
		var got_q: int = WeatherProfile.quality_level()
		if got_q != want_q:
			out.append("quality_level want=%d got=%d" % [want_q, got_q])
	if float(cfg.get("scale", -1.0)) > 0.0:
		var want_s: float = float(cfg.get("scale", -1.0))
		var got_s: float = _root_scale(tree)
		if not is_equal_approx(got_s, want_s):
			out.append("scaling_3d_scale want=%.3f got=%.3f" % [want_s, got_s])
	if str(cfg.get("scaling", "")) != "":
		var want_mode: String = str(cfg.get("scaling", ""))
		var got_mode: String = _scaling_name(_root_scaling_mode(tree))
		if got_mode != want_mode:
			out.append("scaling_3d_mode want=%s got=%s" % [want_mode, got_mode])
	if int(cfg.get("lights", -1)) >= 0 and MobileProfile.max_lights() != int(cfg.get("lights", -1)):
		out.append("lights want=%d got=%d" % [int(cfg.get("lights", -1)), MobileProfile.max_lights()])
	if int(cfg.get("shadows", -1)) >= 0 and MobileProfile.hero_shadows() != int(cfg.get("shadows", -1)):
		out.append("shadows want=%d got=%d" % [int(cfg.get("shadows", -1)), MobileProfile.hero_shadows()])
	if int(cfg.get("vsync", -1)) == 0 and DisplayServer.get_name() != "headless":
		if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
			out.append("vsync want=off got=" + _vsync_name(DisplayServer.window_get_vsync_mode()))
	return out


static func _value(arg: String) -> String:
	var idx: int = arg.find("=")
	return arg.substr(idx + 1) if idx >= 0 else ""


static func _parse_limit(cfg: Dictionary, arg: String, flag: String) -> int:
	var text: String = _value(arg)
	if not text.is_valid_int():
		_fail(cfg, flag + " must be an integer 0.." + str(MAX_LIMIT) + ", got '" + text + "'")
		return -1
	var value: int = int(text)
	if value < 0 or value > MAX_LIMIT:
		_fail(cfg, flag + " must be 0.." + str(MAX_LIMIT) + ", got " + text)
		return -1
	return value


static func _fail(cfg: Dictionary, msg: String) -> void:
	cfg["ok"] = false
	(cfg["errors"] as Array).append(msg)


static func _root_scale(tree: SceneTree) -> float:
	if tree == null or tree.root == null:
		return -1.0
	return tree.root.scaling_3d_scale


static func _root_scaling_mode(tree: SceneTree) -> int:
	if tree == null or tree.root == null:
		return -1
	return tree.root.scaling_3d_mode


static func _scaling_name(mode: int) -> String:
	match mode:
		Viewport.SCALING_3D_MODE_BILINEAR:
			return "bilinear"
		Viewport.SCALING_3D_MODE_FSR:
			return "fsr1"
		Viewport.SCALING_3D_MODE_FSR2:
			return "fsr2"
		_:
			return "mode_" + str(mode)


static func _vsync_name(mode: int) -> String:
	match mode:
		DisplayServer.VSYNC_DISABLED:
			return "off"
		DisplayServer.VSYNC_ENABLED:
			return "on"
		DisplayServer.VSYNC_ADAPTIVE:
			return "adaptive"
		DisplayServer.VSYNC_MAILBOX:
			return "mailbox"
		_:
			return "mode_" + str(mode)
