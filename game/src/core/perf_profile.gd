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
##   --perf-fov=54.54        (vertical degrees, shipped lens; default below)
##   --perf-far=4000         (camera far plane, shipped value; default below)
##   --perf-occlusion=on|off (root Viewport.use_occlusion_culling)
##   --perf-mesh-lod=1.0     (root Viewport.mesh_lod_threshold, 0 disables)
##   --perf-dir-shadow=on|off           (mission moon DirectionalLight3D)
##   --perf-shadow-splits=1|2|4         (PSSM splits)
##   --perf-shadow-max-distance=80      (metres)
##
## `apply_cli()` is called by the main menu before the mission scene is
## instantiated (and by the perf matrix before it adds the scene), so
## WeatherProfile/MobileProfile read the override during environment setup.
## Values are not persisted; they are a QA envelope over the user's save.
##
## The three directional-shadow flags cannot be applied here: the moon is
## created inside `mission_controller._setup_environment()` *after* the weather
## preset. `apply_directional_shadow()` is called from there and prints the
## measured back-values as `PERF_SHADOW`, so the log records the real moon, not
## just the request.

const WeatherProfile: GDScript = preload("res://src/core/weather_profile.gd")
const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")

const QUALITY_KEYS: Array[String] = ["low", "medium", "high"]
const SCALE_VALUES: Array[float] = [1.0, 0.85, 0.75]
const SCALING_KEYS: Array[String] = ["bilinear", "fsr1", "fsr2"]
const MAX_LIMIT: int = 4096

## The shipped lens: UE 85 horizontal -> 54.54 vertical at 16:9, and Godot's
## default Camera3D far, which the game never overrides. The perf matrix used
## to force 60/500 here, so every published frame time was a wider, shallower
## frustum than the shipped frame (see docs/reports/w0p-perf-rig.md).
const DEFAULT_FOV: float = 54.54
const DEFAULT_FAR: float = 4000.0
const FOV_MIN: float = 1.0
const FOV_MAX: float = 179.0
const FAR_MIN: float = 1.0
const FAR_MAX: float = 1000000.0
const MESH_LOD_MAX: float = 64.0
const SHADOW_SPLITS_VALUES: Array[int] = [1, 2, 4]
const SHADOW_MAX_DISTANCE_MIN: int = 1
const SHADOW_MAX_DISTANCE_MAX: int = 10000

## What the shipped build actually does (project.godot
## `lights_and_shadows/directional_shadow/max_distance=80`, DirectionalLight3D
## default 4-split PSSM, `_apply_fallback_moon()` shadow_enabled=true). Reported
## as the effective value when no override was requested.
const SHIPPED_DIR_SHADOW: int = 1
const SHIPPED_SHADOW_SPLITS: int = 4
const SHIPPED_SHADOW_MAX_DISTANCE: int = 80


## Parses only `--perf-*` args. Returns a config dictionary:
##   ok (bool), errors (Array[String]), requested (bool),
##   quality (String), quality_index (int, -1 when unset),
##   scale (float, -1 when unset), scaling (String),
##   lights (int, -1 when unset), shadows (int, -1 when unset),
##   vsync (-1 unchanged, 0 off, 1 on),
##   fov / far (float, -1 when unset), occlusion (int, -1 unchanged, 0 off,
##   1 on), mesh_lod (float, -1 when unset), dir_shadow (int, -1 unchanged),
##   shadow_splits (int, -1 when unset), shadow_max_distance (int, -1 when
##   unset).
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
		"fov": -1.0,
		"far": -1.0,
		"occlusion": -1,
		"mesh_lod": -1.0,
		"dir_shadow": -1,
		"shadow_splits": -1,
		"shadow_max_distance": -1,
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
		elif arg.begins_with("--perf-fov="):
			cfg["fov"] = _parse_positive_float(cfg, arg, "--perf-fov", FOV_MIN, FOV_MAX)
		elif arg.begins_with("--perf-far="):
			cfg["far"] = _parse_positive_float(cfg, arg, "--perf-far", FAR_MIN, FAR_MAX)
		elif arg.begins_with("--perf-occlusion="):
			cfg["occlusion"] = _parse_switch(cfg, arg, "--perf-occlusion")
		elif arg.begins_with("--perf-mesh-lod="):
			cfg["mesh_lod"] = _parse_positive_float(cfg, arg, "--perf-mesh-lod", 0.0, MESH_LOD_MAX)
		elif arg.begins_with("--perf-dir-shadow="):
			cfg["dir_shadow"] = _parse_switch(cfg, arg, "--perf-dir-shadow")
		elif arg.begins_with("--perf-shadow-splits="):
			var splits_text: String = _value(arg)
			if not splits_text.is_valid_int() or not SHADOW_SPLITS_VALUES.has(int(splits_text)):
				_fail(cfg, "--perf-shadow-splits must be 1|2|4, got '" + splits_text + "'")
			else:
				cfg["shadow_splits"] = int(splits_text)
		elif arg.begins_with("--perf-shadow-max-distance="):
			cfg["shadow_max_distance"] = _parse_limit_range(cfg, arg, "--perf-shadow-max-distance", SHADOW_MAX_DISTANCE_MIN, SHADOW_MAX_DISTANCE_MAX)
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
	var occlusion: int = int(cfg.get("occlusion", -1))
	if occlusion >= 0 and root != null:
		root.use_occlusion_culling = occlusion == 1
	var mesh_lod: float = float(cfg.get("mesh_lod", -1.0))
	if mesh_lod >= 0.0 and root != null:
		root.mesh_lod_threshold = clampf(mesh_lod, 0.0, MESH_LOD_MAX)
	if log_line:
		# stderr is unbuffered: PERF_CONFIG survives a hung window teardown.
		printerr(build_config_line(tree, cfg))


## Applies the directional-shadow overrides to the real moon and logs the
## values read back from it (`PERF_SHADOW`). Called by mission_controller after
## the weather preset/sky apply, because the moon does not exist when
## `apply()` runs at startup. No-op without a valid requested config, so normal
## play is untouched.
static func apply_directional_shadow(moon: DirectionalLight3D, cfg: Dictionary, log_line: bool = true) -> void:
	if moon == null or not bool(cfg.get("ok", false)) or not bool(cfg.get("requested", false)):
		return
	var enabled: int = int(cfg.get("dir_shadow", -1))
	if enabled >= 0:
		moon.shadow_enabled = enabled == 1
	var splits: int = int(cfg.get("shadow_splits", -1))
	if splits > 0:
		moon.directional_shadow_mode = _shadow_mode_for_splits(splits)
	var max_distance: int = int(cfg.get("shadow_max_distance", -1))
	if max_distance > 0:
		moon.directional_shadow_max_distance = float(max_distance)
	if log_line:
		printerr("PERF_SHADOW " + JSON.stringify({
			"enabled": moon.shadow_enabled,
			"splits": _splits_for_shadow_mode(moon.directional_shadow_mode),
			"mode": moon.directional_shadow_mode,
			"max_distance": snappedf(moon.directional_shadow_max_distance, 0.1),
			"requested": {
				"dir_shadow": enabled,
				"splits": splits,
				"max_distance": max_distance,
			},
		}))


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
		"occlusion_culling": _root_occlusion(tree),
		"mesh_lod_threshold": snappedf(_root_mesh_lod(tree), 0.001),
		# Directional shadow: resolved request, applied later by
		# mission_controller (the moon does not exist yet). PERF_SHADOW carries
		# the values read back from the real light.
		"directional_shadow": {
			"enabled": resolved_dir_shadow(cfg),
			"splits": resolved_shadow_splits(cfg),
			"max_distance": resolved_shadow_max_distance(cfg),
			"applied_in": "mission_controller",
		},
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
			"fov": resolved_fov(cfg),
			"far": resolved_far(cfg),
			"occlusion": int(cfg.get("occlusion", -1)),
			"mesh_lod": float(cfg.get("mesh_lod", -1.0)),
			"dir_shadow": int(cfg.get("dir_shadow", -1)),
			"shadow_splits": int(cfg.get("shadow_splits", -1)),
			"shadow_max_distance": int(cfg.get("shadow_max_distance", -1)),
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
		"occlusion_culling": _root_occlusion(tree),
		"mesh_lod_threshold": _root_mesh_lod(tree),
	}


## The lens a run will measure: explicit `--perf-fov`/`--perf-far`, else the
## shipped values. Shared by the matrix runner and the config line so the two
## cannot drift apart.
static func resolved_fov(cfg: Dictionary) -> float:
	var fov: float = float(cfg.get("fov", -1.0))
	return DEFAULT_FOV if fov <= 0.0 else fov


static func resolved_far(cfg: Dictionary) -> float:
	var far: float = float(cfg.get("far", -1.0))
	return DEFAULT_FAR if far <= 0.0 else far


static func resolved_dir_shadow(cfg: Dictionary) -> int:
	var value: int = int(cfg.get("dir_shadow", -1))
	return SHIPPED_DIR_SHADOW if value < 0 else value


static func resolved_shadow_splits(cfg: Dictionary) -> int:
	var value: int = int(cfg.get("shadow_splits", -1))
	return SHIPPED_SHADOW_SPLITS if value <= 0 else value


static func resolved_shadow_max_distance(cfg: Dictionary) -> int:
	var value: int = int(cfg.get("shadow_max_distance", -1))
	return SHIPPED_SHADOW_MAX_DISTANCE if value <= 0 else value


## Parsed config must equal the live runtime before a measurement run starts.
## Returns an array of human-readable mismatches (empty == match). `camera` is
## optional: when supplied, the FOV/far plane actually used for the frames is
## checked too (the matrix runner passes the player camera).
static func config_mismatches(tree: SceneTree, cfg: Dictionary, camera: Camera3D = null) -> Array[String]:
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
	if int(cfg.get("occlusion", -1)) >= 0:
		var want_occ: bool = int(cfg.get("occlusion", -1)) == 1
		var got_occ: bool = _root_occlusion(tree)
		if got_occ != want_occ:
			out.append("use_occlusion_culling want=%s got=%s" % [str(want_occ), str(got_occ)])
	if float(cfg.get("mesh_lod", -1.0)) >= 0.0:
		var want_lod: float = float(cfg.get("mesh_lod", -1.0))
		var got_lod: float = _root_mesh_lod(tree)
		if not is_equal_approx(got_lod, want_lod):
			out.append("mesh_lod_threshold want=%.3f got=%.3f" % [want_lod, got_lod])
	if camera != null:
		var want_fov: float = resolved_fov(cfg)
		if not is_equal_approx(camera.fov, want_fov):
			out.append("camera fov want=%.2f got=%.2f" % [want_fov, camera.fov])
		var want_far: float = resolved_far(cfg)
		if not is_equal_approx(camera.far, want_far):
			out.append("camera far want=%.1f got=%.1f" % [want_far, camera.far])
	var moon: DirectionalLight3D = _find_directional_light(tree)
	if moon != null:
		var want_enabled: int = int(cfg.get("dir_shadow", -1))
		if want_enabled >= 0 and moon.shadow_enabled != (want_enabled == 1):
			out.append("shadow_enabled want=%s got=%s" % [str(want_enabled == 1), str(moon.shadow_enabled)])
		var want_splits: int = int(cfg.get("shadow_splits", -1))
		if want_splits > 0 and _splits_for_shadow_mode(moon.directional_shadow_mode) != want_splits:
			out.append("shadow_splits want=%d got=%d" % [want_splits, _splits_for_shadow_mode(moon.directional_shadow_mode)])
		var want_distance: int = int(cfg.get("shadow_max_distance", -1))
		if want_distance > 0 and not is_equal_approx(moon.directional_shadow_max_distance, float(want_distance)):
			out.append("shadow_max_distance want=%d got=%.1f" % [want_distance, moon.directional_shadow_max_distance])
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


static func _parse_limit_range(cfg: Dictionary, arg: String, flag: String, lo: int, hi: int) -> int:
	var text: String = _value(arg)
	if not text.is_valid_int():
		_fail(cfg, flag + " must be an integer %d..%d, got '%s'" % [lo, hi, text])
		return -1
	var value: int = int(text)
	if value < lo or value > hi:
		_fail(cfg, flag + " must be %d..%d, got %d" % [lo, hi, value])
		return -1
	return value


static func _parse_positive_float(cfg: Dictionary, arg: String, flag: String, lo: float, hi: float) -> float:
	var text: String = _value(arg)
	if not text.is_valid_float():
		_fail(cfg, flag + " must be a number %.2f..%.2f, got '%s'" % [lo, hi, text])
		return -1.0
	var value: float = float(text)
	if not is_finite(value) or value < lo or value > hi:
		_fail(cfg, flag + " must be %.2f..%.2f, got %s" % [lo, hi, text])
		return -1.0
	return value


static func _parse_switch(cfg: Dictionary, arg: String, flag: String) -> int:
	match _value(arg).to_lower():
		"on", "enabled", "1", "true":
			return 1
		"off", "disabled", "0", "false":
			return 0
		_:
			_fail(cfg, flag + " must be on|off, got '" + _value(arg) + "'")
			return -1


static func _shadow_mode_for_splits(splits: int) -> int:
	match splits:
		2:
			return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		4:
			return DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_:
			return DirectionalLight3D.SHADOW_ORTHOGONAL


static func _splits_for_shadow_mode(mode: int) -> int:
	match mode:
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS:
			return 2
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
			return 4
		_:
			return 1


## The mission's moon; used only to verify directional-shadow overrides after
## the mission is up. The stable `MissionMoon` name wins, so an authored
## DirectionalLight3D from the extracted level can never be mistaken for it.
static func _find_directional_light(tree: SceneTree) -> DirectionalLight3D:
	if tree == null or tree.root == null:
		return null
	var named: Array[Node] = tree.root.find_children("MissionMoon", "DirectionalLight3D", true, false)
	for node: Node in named:
		if node is DirectionalLight3D:
			return node as DirectionalLight3D
	var found: Array[Node] = tree.root.find_children("*", "DirectionalLight3D", true, false)
	for node: Node in found:
		if node is DirectionalLight3D:
			return node as DirectionalLight3D
	return null


static func _root_occlusion(tree: SceneTree) -> bool:
	if tree == null or tree.root == null:
		return false
	return tree.root.use_occlusion_culling


static func _root_mesh_lod(tree: SceneTree) -> float:
	if tree == null or tree.root == null:
		return -1.0
	return tree.root.mesh_lod_threshold


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
