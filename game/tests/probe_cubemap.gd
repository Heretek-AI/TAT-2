extends SceneTree
## P4.1 IBL headless probe: authored cubemap face mapping + CPU cosine
## irradiance + `TAT2_IBL=off` compatibility.
##
##   tools/godot --headless --path game --script res://tests/probe_cubemap.gd
##
## Synthetic six-face cubes only: no extractor run, no GPU, no capture. The
## real `Cubemap_GroundFloor_01` faces are produced by the integrator's
## `cubemaps` extract + `parse_cubemap`, and this probe then pins their
## manifest. Stage-1 irradiance is a CPU integral, so it is fully testable here;
## the GPU/visual result is not claimed.

const CubemapLoader := preload("res://src/core/cubemap_loader.gd")
const WeatherProfile := preload("res://src/core/weather_profile.gd")

const INDEX_PATH := "res://data/generated/ibl/cubemaps.json"
## Independent reference for a unit-radiance +Y face only:
##   E(n=+Y)/pi = (1/pi) * integral_{-1..1}{-1..1} (1+x^2+z^2)^-2 dx dz
## evaluated with an 800x800 midpoint grid (Python, 2026-11-27).
const REF_PLUS_Y_ONLY := 0.5541266519420135
## 8-bit linear quantisation step: every texel of a PNG face is a multiple of
## 1/255, so a cube whose radiance is ~1.5e-3 cannot be represented at all.
const QUANT8_STEP := 1.0 / 255.0
## Measured ambient luminance of the pre-fix 8-bit PNG path (P4.1 audit). The
## HDR faces must clear it by a wide margin, not by a rounding step.
const QUANT8_MEASURED_LUM := 5.0e-5

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
	_env_backup = OS.get_environment("TAT2_IBL")
	_test_mode()
	_test_face_mapping()
	_test_uniform_and_axis()
	_test_srgb_transfer()
	_test_off_matches_today()
	_test_units_expression()
	_test_real_cube_energy()
	_test_generated_index()
	_finish()


func _test_mode() -> void:
	OS.unset_environment("TAT2_IBL")
	_check(CubemapLoader.mode() == "off", "unset TAT2_IBL is off (today's look)")
	OS.set_environment("TAT2_IBL", "ambient")
	_check(CubemapLoader.mode() == "ambient", "TAT2_IBL=ambient selects stage-1 IBL")
	OS.set_environment("TAT2_IBL", "bogus")
	_check(CubemapLoader.mode() == "off", "an unknown TAT2_IBL falls back to off")


func _test_face_mapping() -> void:
	var axes: Array[Vector3] = [
		Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD,
	]
	var ok: bool = true
	for i: int in range(6):
		var centre: Vector3 = CubemapLoader.direction_for_face_uv(i, 0.5, 0.5)
		if centre.distance_to(axes[i]) > 1e-6:
			ok = false
		if CubemapLoader.face_index(axes[i]) != i:
			ok = false
	_check(ok, "face centres round-trip to their axis (0..5 = +X,-X,+Y,-Y,+Z,-Z)")
	_check(CubemapLoader.face_index(Vector3(-3.0, -0.5, 0.2)) == 1, "face_index picks the dominant axis (-X)")
	_check(CubemapLoader.face_index(Vector3(0.1, 2.0, -3.0)) == 5, "face_index picks the dominant axis (-Z)")
	_check(CubemapLoader.face_index(Vector3.ZERO) == -1, "face_index rejects a zero vector")
	# Intra-face orientation: +Y image is +X right, -Z up (D3D/UE layout).
	var top: Vector3 = CubemapLoader.direction_for_face_uv(2, 0.5, 0.0)
	var bottom: Vector3 = CubemapLoader.direction_for_face_uv(2, 0.5, 1.0)
	var left: Vector3 = CubemapLoader.direction_for_face_uv(2, 0.0, 0.5)
	var right: Vector3 = CubemapLoader.direction_for_face_uv(2, 1.0, 0.5)
	_check(top.z < -0.7 and bottom.z > 0.7 and left.x < -0.7 and right.x > 0.7,
		"+Y face: image top is -Z, right is +X", "top=%s right=%s" % [str(top), str(right)])


func _test_uniform_and_axis() -> void:
	var grey: Array = _cube([Color(0.2, 0.2, 0.2)] as Array, 96)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		var e: Color = CubemapLoader.irradiance(grey, axis)
		if absf(e.r - 0.2) > 5e-4 or absf(e.g - 0.2) > 5e-4 or absf(e.b - 0.2) > 5e-4:
			_check(false, "uniform grey cube is isotropic on the six axes", "n=%s E=(%.5f,%.5f,%.5f)" % [str(axis), e.r, e.g, e.b])
			return
	_check(true, "uniform grey cube returns exactly its radiance on the six axes", "0.2 grey (RGBA8-exact), tol 5e-4")
	# A diagonal normal crosses the horizon mid-cell: the exact solid-angle
	# weights still converge, but the coarse midpoint radiance test leaves a
	# ~1.4 % boundary term. Document it rather than hide it.
	var diag: Color = CubemapLoader.irradiance(grey, Vector3(1, 1, 1).normalized())
	_check(absf(diag.r - 0.2) < 5e-3, "the diagonal normal stays within 2 % (coarse horizon cells)",
		"%.6f" % diag.r)

	var amb: Dictionary = CubemapLoader.ambient(grey)
	_check(absf(float(amb.get("energy", 0.0)) - 0.2) < 5e-4, "ambient energy is the irradiance luminance",
		"%.6f" % float(amb.get("energy", 0.0)))
	var hue: Color = amb.get("color", Color.BLACK) as Color
	_check(absf(hue.r - 1.0) < 1e-3 and absf(hue.g - 1.0) < 1e-3 and absf(hue.b - 1.0) < 1e-3,
		"ambient colour is luminance-normalised (no double scale)")

	# Only +Y red: UP gets the analytic face integral, DOWN gets exactly 0.
	var up_only: Array = _cube([
		Color.BLACK, Color.BLACK, Color.RED, Color.BLACK, Color.BLACK, Color.BLACK,
	] as Array, 96)
	var e_up: Color = CubemapLoader.irradiance(up_only, Vector3.UP)
	var e_down: Color = CubemapLoader.irradiance(up_only, Vector3.DOWN)
	_check(absf(e_up.r - REF_PLUS_Y_ONLY) < 0.02,
		"+Y-only cube matches the independent analytic face integral",
		"%.6f want %.6f" % [e_up.r, REF_PLUS_Y_ONLY])
	_check(e_up.g < 1e-6 and e_up.b < 1e-6, "+Y-only cube has no borrowed channels")
	_check(e_down.r < 1e-6, "the opposite hemisphere receives exactly zero", "%.9f" % e_down.r)
	_check(e_up.r > CubemapLoader.irradiance(up_only, Vector3.RIGHT).r,
		"the authored up-face dominates the up normal")


func _test_srgb_transfer() -> void:
	var mid: Array = _cube([Color(0.4, 0.4, 0.4)] as Array, 96)
	var linear: Color = CubemapLoader.irradiance(mid, Vector3.UP, "linear")
	var srgb: Color = CubemapLoader.irradiance(mid, Vector3.UP, "srgb")
	var want: float = Color(0.4, 0.4, 0.4).srgb_to_linear().r
	_check(absf(linear.r - 0.4) < 2e-3, "linear transfer keeps the decoded value", "%.5f" % linear.r)
	_check(absf(srgb.r - want) < 2e-3, "srgb transfer converts to linear", "%.5f want %.5f" % [srgb.r, want])


## `off` must leave exactly today's authored ambient path (no cubemap index,
## no contribution change).
func _test_off_matches_today() -> void:
	OS.set_environment("TAT2_IBL", "off")
	var preset: Dictionary = _read_json("res://data/generated/weather/gloomy.json")
	if preset.is_empty():
		_check(false, "generated gloomy preset readable for the off check")
		return
	var cm: Dictionary = CubemapLoader.ambient_for_preset(preset)
	_check(not bool(cm.get("available", true)), "off reports available=false")
	_check(str(cm.get("mode", "")) == "off", "off reports mode=off", str(cm.get("reason", "")))

	var env := Environment.new()
	var moon := DirectionalLight3D.new()
	var applied: bool = WeatherProfile.apply_environment(env, moon, preset)
	_check(applied, "gloomy preset still applies with TAT2_IBL=off")
	var want_c: Variant = WeatherProfile.ambient_color(preset)
	var want_e: Variant = WeatherProfile.ambient_energy(preset)
	_check(want_c != null and (env.ambient_light_color as Color).is_equal_approx(want_c as Color),
		"off keeps the authored SkyLight colour", str(env.ambient_light_color))
	_check(want_e != null and is_equal_approx(env.ambient_light_energy, float(want_e)),
		"off keeps the authored SkyLight energy", "%.6f" % env.ambient_light_energy)
	_check(not bool(WeatherProfile.sky_ibl_state(preset).get("available", true)),
		"off keeps sky_ibl_state unavailable (no sky_contribution flip)")
	moon.free()

	# ambient mode without the converted data is also a no-op (PENDING data).
	OS.set_environment("TAT2_IBL", "ambient")
	CubemapLoader.reset_cache()
	var cm2: Dictionary = CubemapLoader.ambient_for_preset(preset)
	if not FileAccess.file_exists(INDEX_PATH):
		_check(not bool(cm2.get("available", true)), "ambient without the converted index is a no-op",
			str(cm2.get("reason", "")))
	else:
		_check(true, "converted cubemap index present", INDEX_PATH)


## P3-3A.4 units: the IBL ambient energy is
##   luminance(E(+Y)) * authored sky.intensity * IBL_AMBIENT_PORT_SCALE
## and deliberately NOT the flat `clamp(intensity * 0.08)` substitute: the two
## are different quantities (a measured linear radiance vs a tuned Godot
## energy), so comparing them directly is the defect this pins.
func _test_units_expression() -> void:
	var preset: Dictionary = _read_json("res://data/generated/weather/gloomy.json")
	if preset.is_empty():
		_check(false, "generated gloomy preset readable for the units check")
		return
	var sky_v: Variant = preset.get("sky", {})
	var sky: Dictionary = sky_v as Dictionary if sky_v is Dictionary else {}
	var authored: float = float(sky.get("intensity", -1.0))
	_check(authored > 0.0 and is_equal_approx(WeatherProfile.sky_intensity(preset), authored),
		"the IBL path reads the authored sky.intensity unchanged (no 0.08, no clamp)",
		"authored=%.3f applied=%.3f" % [authored, WeatherProfile.sky_intensity(preset)])
	_check(is_equal_approx(WeatherProfile.sky_intensity({}), 1.0),
		"a preset that authors no sky.intensity keeps UE's default 1.0")
	_check(is_equal_approx(WeatherProfile.IBL_AMBIENT_PORT_SCALE, 1.0),
		"the one port scale is the documented identity (linear radiance -> linear ambient energy)")

	var lum: float = 0.0017
	var energy: float = WeatherProfile.ibl_ambient_energy(preset, lum)
	var want: float = lum * authored * WeatherProfile.IBL_AMBIENT_PORT_SCALE
	_check(is_equal_approx(energy, want) and energy > lum,
		"IBL energy applies the authored intensity on top of the measured radiance",
		"%.6f = %.6f * %.3f" % [energy, lum, authored])
	var flat: float = float(WeatherProfile.ambient_energy(preset))
	_check(flat > energy and not is_equal_approx(flat, energy),
		"the flat clamp(intensity*0.08) substitute is a different quantity, not the IBL energy",
		"flat=%.4f ibl=%.5f ratio=%.1fx" % [flat, energy, flat / maxf(energy, 1e-9)])


## The real shipped cube, through the same public entry the game uses. Pins the
## measured energy against the 8-bit quantisation floor the PNG path produced.
func _test_real_cube_energy() -> void:
	OS.set_environment("TAT2_IBL", "ambient")
	CubemapLoader.reset_cache()
	var amb: Dictionary = CubemapLoader.ambient_for_ue_path("/Game/MaterialLibrary/Utility/Cubemap_GroundFloor_01")
	if not bool(amb.get("available", false)):
		_check(false, "the authored Gloomy cubemap loads as linear radiance",
			str(amb.get("reason", "")))
		return
	var lum: float = float(amb.get("lum", 0.0))
	# The same cube re-integrated after an 8-bit linear quantisation (round to
	# 1/255, exactly what the PNG path wrote). This is the falsifier that needs
	# no remembered constant: the HDR faces must carry energy the 8-bit encoding
	# cannot represent.
	var faces: Array = CubemapLoader.cube_faces("cubemap_ground_floor_01")
	var quant_lum: float = 0.0
	if faces.size() == 6:
		var q_e: Color = CubemapLoader.irradiance(_quantise8(faces), Vector3.UP, "linear")
		quant_lum = 0.2126 * q_e.r + 0.7152 * q_e.g + 0.0722 * q_e.b
	_check(faces.size() == 6, "the Gloomy cube's six faces load for the quantisation check", "%d" % faces.size())
	_check(lum > maxf(quant_lum, QUANT8_MEASURED_LUM) * 5.0,
		"the HDR irradiance clears what the same cube measures at 8 bits",
		"hdr=%.6f 8bit=%.6f audited_8bit_floor=%.6f ratio=%.1fx" % [
			lum, quant_lum, QUANT8_MEASURED_LUM, lum / maxf(quant_lum, QUANT8_MEASURED_LUM)])
	_check(lum < QUANT8_STEP,
		"the cube still sits below one 8-bit step, so only the .hdr faces can carry it",
		"lum=%.6f step=%.6f" % [lum, QUANT8_STEP])

	var preset: Dictionary = _read_json("res://data/generated/weather/gloomy.json")
	if preset.is_empty():
		_check(false, "generated gloomy preset readable for the apply check")
		return
	var env := Environment.new()
	var moon := DirectionalLight3D.new()
	var applied: bool = WeatherProfile.apply_environment(env, moon, preset)
	var want: float = WeatherProfile.ibl_ambient_energy(preset, lum)
	_check(applied and is_equal_approx(env.ambient_light_energy, want),
		"TAT2_IBL=ambient sets ambient_light_energy = lum * sky.intensity * port scale",
		"applied=%.6f want=%.6f" % [env.ambient_light_energy, want])
	_check(not is_equal_approx(env.ambient_light_energy,
			float(WeatherProfile.ambient_energy(preset))),
		"ambient mode does not fall back to the flat SkyLight energy")
	moon.free()


func _test_generated_index() -> void:
	if not FileAccess.file_exists(INDEX_PATH):
		print("PENDING: %s absent; the integrator runs the cubemaps extract + parse_cubemap, then this block pins schema/faces" % INDEX_PATH)
		return
	CubemapLoader.reset_cache()
	var idx: Dictionary = CubemapLoader.load_index()
	_check(str(idx.get("schema", "")) == "tat2.cubemaps/1", "cubemap index schema", str(idx.get("schema", "")))
	_check(idx.get("faces_order", []) == ["px", "nx", "py", "ny", "pz", "nz"], "cubemap face order is explicit")
	var cubes_v: Variant = idx.get("cubemaps", {})
	var cubes: Dictionary = cubes_v as Dictionary if cubes_v is Dictionary else {}
	_check(not cubes.is_empty(), "cubemap index has at least one converged cube", "%d" % cubes.size())
	var by_path_v: Variant = idx.get("by_ue_path", {})
	var by_path: Dictionary = by_path_v as Dictionary if by_path_v is Dictionary else {}
	for id: String in cubes.keys():
		var rec: Dictionary = cubes[id] as Dictionary
		var faces_v: Variant = rec.get("faces", {})
		var faces: Dictionary = faces_v as Dictionary if faces_v is Dictionary else {}
		if faces.size() != 6:
			_check(false, "cubemap %s carries six faces" % id, "%d" % faces.size())
			continue
		var ok: bool = true
		var all_hdr: bool = true
		for name: String in CubemapLoader.FACE_NAMES:
			var face_path: String = str(faces.get(name, ""))
			if not ResourceLoader.exists(face_path):
				ok = false
			if not (face_path.get_extension().to_lower() in ["hdr", "exr"]):
				all_hdr = false
		_check(ok, "cubemap %s face files resolve" % id, str(rec.get("ue_path", "")))
		# P3-3A.4: the shipped cubes are PF_FloatRGBA. An 8-bit face clamps
		# ~1.5e-3 linear radiance to 0 / 1/255 (the measured 0.00005 floor), so a
		# PNG here is the quantized cube, never an acceptable export.
		_check(all_hdr and bool(rec.get("hdr", false)),
			"cubemap %s faces are HDR .hdr (linear radiance, not 8-bit PNG)" % id,
			"encoding=%s" % str(rec.get("encoding", "")))
		_check(str(rec.get("transfer", "")) in ["linear", "srgb"], "cubemap %s records its transfer" % id,
			str(rec.get("transfer", "")))
		_check(str(by_path.get(str(rec.get("ue_path", "")), "")) == id, "cubemap %s is indexed by UE path" % id)
		var means_v: Variant = rec.get("face_mean", {})
		if means_v is Dictionary and (means_v as Dictionary).has("py") and (means_v as Dictionary).has("ny"):
			var means: Dictionary = means_v as Dictionary
			var py: float = _lum(means["py"] as Array)
			var ny: float = _lum(means["ny"] as Array)
			var nz: float = _lum(means["nz"] as Array) if means.has("nz") else 0.0
			# P3-3A.4 orientation record: face order and seams are unchanged
			# (suite pins the axes); the +Y/-Y ordering is an AUTHORED property
			# of each cube, not a port decision. With the HDR export it is stable
			# across re-extractions, so a reversal is information about the
			# authored sky, never a reason to re-map a face.
			if py < ny:
				print("CUBEMAP_ORIENT: WARN %s +Y luminance %.4f < -Y %.4f — recorded as an authored property (daylight's authored sky is brighter below the horizon); the face order is pinned by the axis test, not by this ordering" % [id, py, ny])
			else:
				print("CUBEMAP_ORIENT: %s +Y luminance %.4f >= -Y %.4f (authored; the pre-HDR 8-bit means inverted this by quantisation)" % [id, py, ny])
			if id == "cubemap_ground_floor_01":
				# The Gloomy cube's -Z face was near-black under the 8-bit clamp
				# (0.00011 linear mean) because its radiance sat under one step;
				# the HDR faces carry the real energy.
				_check(nz > 1e-4,
					"the Gloomy cube's -Z face is no longer black (the 8-bit clamp zeroed it)",
					"-Z lum=%.6f" % nz)


# --------------------------------------------------------------------- helpers
## An 8-bit linear copy of each face (round to 1/255), i.e. what the PNG path
## would have stored. `convert` runs in C++, so 512^2 x 6 stays cheap.
func _quantise8(faces: Array) -> Array:
	var out: Array = []
	for f: Variant in faces:
		if not (f is Image):
			continue
		var img: Image = (f as Image).duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.convert(Image.FORMAT_RGBAF)
		out.append(img)
	return out


## Six images from six colours (8x8 RGBA8; the integral is size-independent).
func _cube(colors: Array, size: int) -> Array:
	var out: Array = []
	for i: int in range(6):
		var col: Color = (colors[0] if colors.size() == 1 else colors[i]) as Color
		var img: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		img.fill(col)
		out.append(img)
	return out


func _lum(rgb: Array) -> float:
	if rgb.size() < 3:
		return 0.0
	return 0.2126 * float(rgb[0]) + 0.7152 * float(rgb[1]) + 0.0722 * float(rgb[2])


func _read_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _finish() -> void:
	if _env_backup == "":
		OS.unset_environment("TAT2_IBL")
	else:
		OS.set_environment("TAT2_IBL", _env_backup)
	CubemapLoader.reset_cache()
	print("CUBEMAP_PROBE: fails=%d passed=%d" % [fails, checks])
	quit(0 if fails == 0 else 1)
