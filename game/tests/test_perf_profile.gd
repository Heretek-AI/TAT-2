extends SceneTree
## W0p headless test for the perf QA envelope (`game/src/core/perf_profile.gd`).
##
## Covers the measurement-rig provenance without any GPU work:
##   - fail-closed parsing of --perf-fov/--perf-far/--perf-occlusion/
##     --perf-mesh-lod/--perf-dir-shadow/--perf-shadow-splits/
##     --perf-shadow-max-distance (accept + reject, unknown flags reject);
##   - the shipped defaults (54.54 vertical, 4000 m far) when no override;
##   - apply() writes Viewport.use_occlusion_culling / mesh_lod_threshold and
##     leaves the viewport untouched for an invalid or absent config;
##   - config_mismatches() sees occlusion, mesh lod, camera FOV/far and the
##     moon's shadow enabled/splits/max-distance;
##   - apply_directional_shadow() maps splits 1|2|4 and is a no-op without
##     perf flags.
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_perf_profile.gd

const PerfProfile: GDScript = preload("res://src/core/perf_profile.gd")

var fails: int = 0


func _initialize() -> void:
	await process_frame
	_test_defaults()
	_test_parser_accept()
	_test_parser_reject()
	_test_config_line()
	await _test_apply_viewport()
	await _test_mismatches()
	await _test_directional_shadow()
	print("PERF_PROFILE_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		printerr("FAIL: ", msg)
		fails += 1


static func _parse(args: Array) -> Dictionary:
	return PerfProfile.parse_args(PackedStringArray(args))


func _test_defaults() -> void:
	var cfg: Dictionary = _parse([])
	_check(bool(cfg.get("ok", false)) and not bool(cfg.get("requested", false)),
		"empty args parse ok, requested=false")
	_check(int(cfg.get("fov", 0)) == -1 and int(cfg.get("far", 0)) == -1,
		"fov/far unset are explicit sentinels (-1), not a silent 0")
	_check(is_equal_approx(PerfProfile.DEFAULT_FOV, 54.54) and is_equal_approx(PerfProfile.DEFAULT_FAR, 4000.0),
		"shipped lens constants are 54.54 vertical / 4000 m far")
	_check(is_equal_approx(float(PerfProfile.resolved_fov(cfg)), 54.54) \
			and is_equal_approx(float(PerfProfile.resolved_far(cfg)), 4000.0),
		"no --perf-fov/--perf-far resolves to the shipped 54.54/4000")
	var only_quality: Dictionary = _parse(["--perf-quality=high"])
	_check(bool(only_quality.get("ok", false)) and is_equal_approx(float(PerfProfile.resolved_fov(only_quality)), 54.54),
		"a non-lens perf flag still resolves the shipped FOV")
	_check(int(PerfProfile.resolved_dir_shadow(cfg)) == PerfProfile.SHIPPED_DIR_SHADOW \
			and int(PerfProfile.resolved_shadow_splits(cfg)) == 4 \
			and int(PerfProfile.resolved_shadow_max_distance(cfg)) == 80,
		"unset directional-shadow flags resolve to the shipped on/4 splits/80 m")


func _test_parser_accept() -> void:
	var cfg: Dictionary = _parse([
		"--perf-quality=high",
		"--perf-scale=0.85",
		"--perf-scaling=fsr1",
		"--perf-lights=80",
		"--perf-shadows=3",
		"--perf-vsync=off",
		"--perf-fov=54.54",
		"--perf-far=4000",
		"--perf-occlusion=off",
		"--perf-mesh-lod=0.5",
		"--perf-dir-shadow=off",
		"--perf-shadow-splits=2",
		"--perf-shadow-max-distance=120",
	])
	_check(bool(cfg.get("ok", false)) and bool(cfg.get("requested", false)),
		"accepts a full perf envelope: " + str(cfg.get("errors", [])))
	_check(is_equal_approx(float(cfg.get("fov", 0.0)), 54.54) and is_equal_approx(float(cfg.get("far", 0.0)), 4000.0),
		"accepted fov=54.54 far=4000")
	_check(int(cfg.get("occlusion", -2)) == 0 and is_equal_approx(float(cfg.get("mesh_lod", -2.0)), 0.5),
		"accepted occlusion=off mesh_lod=0.5")
	_check(int(cfg.get("dir_shadow", -2)) == 0 and int(cfg.get("shadow_splits", -1)) == 2 \
			and int(cfg.get("shadow_max_distance", -1)) == 120,
		"accepted dir_shadow=off splits=2 max_distance=120")
	var on_values: Dictionary = _parse(["--perf-occlusion=on", "--perf-dir-shadow=on", "--perf-mesh-lod=0"])
	_check(bool(on_values.get("ok", false)) and int(on_values.get("occlusion", -1)) == 1 \
			and int(on_values.get("dir_shadow", -1)) == 1 \
			and is_equal_approx(float(on_values.get("mesh_lod", -1.0)), 0.0),
		"accepts on switches and mesh_lod=0 (disables mesh LOD)")
	for splits: String in ["1", "2", "4"]:
		var split_cfg: Dictionary = _parse(["--perf-shadow-splits=" + splits])
		_check(bool(split_cfg.get("ok", false)) and str(int(split_cfg.get("shadow_splits", -1))) == splits,
			"accepts --perf-shadow-splits=" + splits)
	var with_selector: Dictionary = _parse(["--perf-matrix", "--perf-fov=60"])
	_check(bool(with_selector.get("ok", false)) and is_equal_approx(float(with_selector.get("fov", 0.0)), 60.0),
		"--perf-matrix selector is not treated as a typo")


func _test_parser_reject() -> void:
	var bad: Array = [
		"--perf-fov=abc",
		"--perf-fov=0",
		"--perf-fov=180",
		"--perf-far=nope",
		"--perf-far=0",
		"--perf-far=1e9",
		"--perf-occlusion=maybe",
		"--perf-mesh-lod=abc",
		"--perf-mesh-lod=-1",
		"--perf-dir-shadow=maybe",
		"--perf-shadow-splits=3",
		"--perf-shadow-splits=two",
		"--perf-shadow-max-distance=0",
		"--perf-shadow-max-distance=abc",
		"--perf-bogus=1",
	]
	for arg: String in bad:
		var cfg: Dictionary = _parse([arg])
		_check(not bool(cfg.get("ok", true)) and not (cfg.get("errors", []) as Array).is_empty(),
			"rejects " + arg + " (" + str((cfg.get("errors", []) as Array)[0] if not (cfg.get("errors", []) as Array).is_empty() else "") + ")")
	var empty_value: Dictionary = _parse(["--perf-fov="])
	_check(not bool(empty_value.get("ok", true)), "rejects an empty --perf-fov= value")


func _test_config_line() -> void:
	var cfg: Dictionary = _parse(["--perf-fov=54.54", "--perf-far=4000", "--perf-occlusion=on", "--perf-mesh-lod=1.0", "--perf-dir-shadow=on", "--perf-shadow-splits=4", "--perf-shadow-max-distance=80"])
	var line: String = PerfProfile.build_config_line(self, cfg)
	_check(line.begins_with("PERF_CONFIG "), "config line is a PERF_CONFIG record")
	var parsed: Variant = JSON.parse_string(line.trim_prefix("PERF_CONFIG "))
	var obj: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	var args: Dictionary = obj.get("args", {}) as Dictionary
	var effective: Dictionary = obj.get("effective", {}) as Dictionary
	var shadow: Dictionary = effective.get("directional_shadow", {}) as Dictionary
	_check(args.has("fov") and args.has("far") and is_equal_approx(float(args.get("fov", 0.0)), 54.54) \
			and is_equal_approx(float(args.get("far", 0.0)), 4000.0),
		"PERF_CONFIG args carry fov/far")
	_check(effective.has("occlusion_culling") and effective.has("mesh_lod_threshold"),
		"PERF_CONFIG effective carries occlusion_culling and mesh_lod_threshold")
	_check(int(shadow.get("enabled", -1)) == 1 and int(shadow.get("splits", -1)) == 4 \
			and int(shadow.get("max_distance", -1)) == 80 \
			and str(shadow.get("applied_in", "")) == "mission_controller",
		"PERF_CONFIG exposes effective directional shadow (on/4/80, applied by mission_controller)")


func _test_apply_viewport() -> void:
	var root_vp: Window = root
	var orig_occlusion: bool = root_vp.use_occlusion_culling
	var orig_lod: float = root_vp.mesh_lod_threshold

	var off_cfg: Dictionary = _parse(["--perf-occlusion=off", "--perf-mesh-lod=0.25"])
	PerfProfile.apply(self, off_cfg, false)
	_check(root_vp.use_occlusion_culling == false, "apply(occlusion=off) clears use_occlusion_culling")
	_check(is_equal_approx(root_vp.mesh_lod_threshold, 0.25), "apply(mesh_lod=0.25) sets mesh_lod_threshold")

	var on_cfg: Dictionary = _parse(["--perf-occlusion=on", "--perf-mesh-lod=0"])
	PerfProfile.apply(self, on_cfg, false)
	_check(root_vp.use_occlusion_culling == true, "apply(occlusion=on) sets use_occlusion_culling")
	_check(is_equal_approx(root_vp.mesh_lod_threshold, 0.0), "apply(mesh_lod=0) disables mesh LOD")

	root_vp.use_occlusion_culling = false
	root_vp.mesh_lod_threshold = 0.75
	var bad_cfg: Dictionary = _parse(["--perf-occlusion=maybe", "--perf-mesh-lod=abc"])
	PerfProfile.apply(self, bad_cfg, false)
	_check(root_vp.use_occlusion_culling == false and is_equal_approx(root_vp.mesh_lod_threshold, 0.75),
		"invalid config applies nothing (fail closed)")

	PerfProfile.apply(self, _parse([]), false)
	_check(root_vp.use_occlusion_culling == false and is_equal_approx(root_vp.mesh_lod_threshold, 0.75),
		"absent perf flags leave the viewport untouched")

	root_vp.use_occlusion_culling = orig_occlusion
	root_vp.mesh_lod_threshold = orig_lod


func _test_mismatches() -> void:
	var root_vp: Window = root
	var orig_occlusion: bool = root_vp.use_occlusion_culling
	var orig_lod: float = root_vp.mesh_lod_threshold

	var cfg: Dictionary = _parse(["--perf-occlusion=off", "--perf-mesh-lod=0.25", "--perf-fov=54.54", "--perf-far=4000"])
	PerfProfile.apply(self, cfg, false)

	var cam := Camera3D.new()
	cam.fov = 54.54
	cam.far = 4000.0
	root.add_child(cam)
	_check(PerfProfile.config_mismatches(self, cfg, cam).is_empty(),
		"applied config matches the live viewport and camera")
	_check(PerfProfile.config_mismatches(self, cfg).is_empty(),
		"camera-free mismatch check still passes for viewport-only settings")

	root_vp.use_occlusion_culling = true
	var occ_mismatch: Array[String] = PerfProfile.config_mismatches(self, cfg, cam)
	_check(_has_mismatch(occ_mismatch, "use_occlusion_culling"), "mismatch: occlusion flipped under the run")
	root_vp.use_occlusion_culling = false

	root_vp.mesh_lod_threshold = 0.5
	var lod_mismatch: Array[String] = PerfProfile.config_mismatches(self, cfg, cam)
	_check(_has_mismatch(lod_mismatch, "mesh_lod_threshold"), "mismatch: mesh lod threshold drifted")
	root_vp.mesh_lod_threshold = 0.25

	cam.fov = 60.0
	var fov_mismatch: Array[String] = PerfProfile.config_mismatches(self, cfg, cam)
	_check(_has_mismatch(fov_mismatch, "camera fov"), "mismatch: camera FOV 60 vs requested 54.54")
	cam.fov = 54.54

	cam.far = 500.0
	var far_mismatch: Array[String] = PerfProfile.config_mismatches(self, cfg, cam)
	_check(_has_mismatch(far_mismatch, "camera far"), "mismatch: camera far 500 vs requested 4000")
	cam.far = 4000.0

	# No moon in the tree yet: directional-shadow checks must stay silent.
	var dir_cfg: Dictionary = _parse(["--perf-dir-shadow=off", "--perf-shadow-splits=2", "--perf-shadow-max-distance=120"])
	_check(PerfProfile.config_mismatches(self, dir_cfg, cam).is_empty(),
		"no directional light => no shadow mismatch is fabricated")

	cam.queue_free()
	root_vp.use_occlusion_culling = orig_occlusion
	root_vp.mesh_lod_threshold = orig_lod
	await process_frame


func _test_directional_shadow() -> void:
	var moon := DirectionalLight3D.new()
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.directional_shadow_max_distance = 80.0
	root.add_child(moon)

	var cfg: Dictionary = _parse(["--perf-dir-shadow=off", "--perf-shadow-splits=2", "--perf-shadow-max-distance=120"])
	PerfProfile.apply_directional_shadow(moon, cfg, false)
	_check(moon.shadow_enabled == false, "dir_shadow=off disables the moon's shadows")
	_check(moon.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"shadow_splits=2 selects SHADOW_PARALLEL_2_SPLITS")
	_check(is_equal_approx(moon.directional_shadow_max_distance, 120.0),
		"shadow_max_distance=120 is applied to the moon")
	_check(PerfProfile.config_mismatches(self, cfg).is_empty(),
		"applied directional shadow matches config_mismatches")

	var splits_one: Dictionary = _parse(["--perf-dir-shadow=on", "--perf-shadow-splits=1"])
	PerfProfile.apply_directional_shadow(moon, splits_one, false)
	_check(moon.shadow_enabled == true and moon.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL,
		"shadow_splits=1 selects SHADOW_ORTHOGONAL and re-enables shadows")

	var splits_four: Dictionary = _parse(["--perf-shadow-splits=4"])
	PerfProfile.apply_directional_shadow(moon, splits_four, false)
	_check(moon.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"shadow_splits=4 selects SHADOW_PARALLEL_4_SPLITS")

	# A flag-less run must not touch the moon.
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.directional_shadow_max_distance = 80.0
	PerfProfile.apply_directional_shadow(moon, _parse([]), false)
	_check(moon.shadow_enabled == true \
			and moon.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS \
			and is_equal_approx(moon.directional_shadow_max_distance, 80.0),
		"no perf flags leave the shipped moon untouched")

	# A partially supplied config only touches what it asked for.
	var only_distance: Dictionary = _parse(["--perf-shadow-max-distance=200"])
	PerfProfile.apply_directional_shadow(moon, only_distance, false)
	_check(moon.shadow_enabled == true \
			and moon.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS \
			and is_equal_approx(moon.directional_shadow_max_distance, 200.0),
		"only --perf-shadow-max-distance changes the max distance")

	moon.queue_free()
	await process_frame


func _has_mismatch(mismatches: Array[String], needle: String) -> bool:
	for mismatch: String in mismatches:
		if mismatch.contains(needle):
			return true
	return false
