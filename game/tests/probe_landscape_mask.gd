extends SceneTree
## P4.4 landscape visibility-mask probe (headless).
##
##   tools/godot --headless --path game --script res://tests/probe_landscape_mask.gd
##
## What it proves, without a renderer:
##   1. `TAT2_LANDSCAPE_MASK=discard|raw|off` parses to the three shader paths,
##      with unknown/empty values falling back to the authored `discard` rule.
##   2. The raw weight convention is one place: `vis > 0.5` = hole.
##   3. A synthetic 50/50 mask (left half hole, right half visible) is counted
##      exactly: 50 % holes on a stride-1 scan, 0 % on the colour channel, and
##      50 % at stride 2. This is the CPU half of the raw-mask A/B; the GPU
##      readback belongs to the integrator.
##   4. The Guildhall safe-room gap is on a component with **no**
##      `LandscapeVisibilityLayerInfo`, so the resolved mask is 0.0 (< 0.5) and
##      the gap stays visible under the shipped `discard` rule. This is the
##      data assertion; it does not flip the convention.
##   5. A control component (`Weightmap_6`) has authored 1.0 holes, so the
##      discard rule is not vacuous and the mask data is real.
##   6. The loader binds `sample_mask` / `discard_holes` / `mask_raw_view` for
##      each mode, and a component with no mask never discards.
##
## The summary line is stable for the gate:
##   LANDSCAPE_MASK_SUMMARY: fails=0 checks=N components=18 masked=10 safe_room=12 mask=absent

const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const GUILDHALL_LANDSCAPE := "res://data/generated/levels/Guildhall/Guildhall_Landscape.tatlevel.json"
const SAFE_ROOM_GAP := [
	Vector3(126.0, 18.56, -10.43),
	Vector3(114.5, 18.56, -3.2),
]

var _fails: int = 0
var _checks: int = 0
var _last: String = ""


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, line: String) -> void:
	_checks += 1
	if ok:
		print("LANDSCAPE_MASK OK ", line)
	else:
		_fails += 1
		printerr("LANDSCAPE_MASK FAIL ", line)
	_last = line


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _visibility_layer(lc: Dictionary) -> Dictionary:
	for l_var: Variant in (lc.get("layers", []) as Array):
		if not (l_var is Dictionary):
			continue
		var l: Dictionary = l_var
		if str(l.get("layer", "")).to_lower().contains("visibility"):
			return l
	return {}


## The landscape builder bypasses `_dict_to_transform`'s 40 m clamp and uses
## `quads * abs(scale) * 0.01` metres per tile, so the probe must do the same.
func _component_contains(lc: Dictionary, p: Vector3) -> bool:
	var pos_arr: Array = lc.get("pos", []) as Array
	if pos_arr.size() < 3:
		return false
	var origin := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var b: Array = lc.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]) as Array
	var basis := Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	).orthonormalized()
	var sc: Array = lc.get("scale", [100.0, 100.0, 100.0]) as Array
	var quads: int = int(lc.get("quads", 63))
	var sx: float = absf(float(sc[0])) * 0.01 if sc.size() > 0 else 1.0
	var sz: float = absf(float(sc[2])) * 0.01 if sc.size() > 2 else 1.0
	var p00: Vector3 = origin
	var p10: Vector3 = origin + basis.x * (float(quads) * sx)
	var p01: Vector3 = origin + basis.z * (float(quads) * sz)
	var p11: Vector3 = p10 + p01 - origin
	var xmin: float = minf(minf(p00.x, p10.x), minf(p01.x, p11.x))
	var xmax: float = maxf(maxf(p00.x, p10.x), maxf(p01.x, p11.x))
	var zmin: float = minf(minf(p00.z, p10.z), minf(p01.z, p11.z))
	var zmax: float = maxf(maxf(p00.z, p10.z), maxf(p01.z, p11.z))
	return p.x >= xmin and p.x <= xmax and p.z >= zmin and p.z <= zmax


func _component_label(lc: Dictionary) -> String:
	var pos_arr: Array = lc.get("pos", []) as Array
	if pos_arr.size() < 3:
		return "?"
	return "(%.1f,%.1f,%.1f)" % [float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])]


func _run() -> void:
	await process_frame
	_check_modes()
	_check_shader_contract()
	_check_synthetic_5050()
	_check_guildhall_data()
	await _check_loader_binding()

	print("LANDSCAPE_MASK_SUMMARY: %s fails=%d checks=%d last=%s" % [
		"PASS" if _fails == 0 else "FAIL", _fails, _checks, _last])
	quit(0 if _fails == 0 else 1)


func _check_modes() -> void:
	var default_mode: String = LevelLoaderScript.landscape_mask_mode("")
	var mode_ok: bool = default_mode == "discard" \
		and LevelLoaderScript.landscape_mask_mode("DISCARD") == "discard" \
		and LevelLoaderScript.landscape_mask_mode("raw") == "raw" \
		and LevelLoaderScript.landscape_mask_mode(" off ") == "off" \
		and LevelLoaderScript.landscape_mask_mode("bogus") == "discard"
	var p_discard: Dictionary = LevelLoaderScript.landscape_mask_params("discard")
	var p_raw: Dictionary = LevelLoaderScript.landscape_mask_params("raw")
	var p_off: Dictionary = LevelLoaderScript.landscape_mask_params("off")
	var params_ok: bool = float(p_discard["sample_mask"]) == 1.0 \
		and float(p_discard["discard_holes"]) == 1.0 \
		and float(p_discard["mask_raw_view"]) == 0.0 \
		and float(p_raw["sample_mask"]) == 1.0 \
		and float(p_raw["discard_holes"]) == 0.0 \
		and float(p_raw["mask_raw_view"]) == 1.0 \
		and float(p_off["sample_mask"]) == 0.0 \
		and float(p_off["discard_holes"]) == 0.0 \
		and float(p_off["mask_raw_view"]) == 0.0
	var hole_ok: bool = not LevelLoaderScript.landscape_mask_hole(0.0) \
		and not LevelLoaderScript.landscape_mask_hole(0.49) \
		and not LevelLoaderScript.landscape_mask_hole(0.5) \
		and LevelLoaderScript.landscape_mask_hole(0.51) \
		and LevelLoaderScript.landscape_mask_hole(1.0)
	_check(mode_ok and params_ok and hole_ok,
		"modes default=%s discard=%s raw=%s off=%s rule=vis>0.5" % [
			default_mode, str(p_discard), str(p_raw), str(p_off)])


func _check_shader_contract() -> void:
	var txt: String = _read_text("res://src/core/tat_landscape.gdshader")
	var ok: bool = txt.find("sample_mask") >= 0 \
		and txt.find("mask_raw_view") >= 0 \
		and txt.find("discard_holes") >= 0 \
		and txt.find("discard_holes > 0.5 && vis > 0.5") >= 0 \
		and txt.find("discard;") >= 0
	_check(ok, "shader keeps the authored vis>0.5 discard and the sample/raw controls")


func _check_synthetic_5050() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y: int in range(64):
		for x: int in range(64):
			# Channel 1 = visibility: left half authored hole (1), right half
			# visible (0). Channel 0 stays 0 so it is the negative control.
			img.set_pixel(x, y, Color(0.0, 1.0 if x < 32 else 0.0, 0.0, 1.0))
	var full: Dictionary = LevelLoaderScript.landscape_mask_stats(img, 1, 1)
	var half: Dictionary = LevelLoaderScript.landscape_mask_stats(img, 1, 2)
	var wrong: Dictionary = LevelLoaderScript.landscape_mask_stats(img, 0, 1)
	var ok: bool = int(full["samples"]) == 4096 and int(full["holes"]) == 2048 \
		and absf(float(full["hole_frac"]) - 0.5) < 0.000001 \
		and absf(float(full["min"])) < 0.000001 and absf(float(full["max"]) - 1.0) < 0.000001 \
		and absf(float(full["mean"]) - 0.5) < 0.000001 \
		and int(half["samples"]) == 1024 and int(half["holes"]) == 512 \
		and absf(float(half["hole_frac"]) - 0.5) < 0.000001 \
		and int(wrong["holes"]) == 0
	_check(ok, "synthetic 50/50 mask samples=%d holes=%d frac=%.3f stride2=%d/%d channel0_holes=%d" % [
		int(full["samples"]), int(full["holes"]), float(full["hole_frac"]),
		int(half["holes"]), int(half["samples"]), int(wrong["holes"])])


func _check_guildhall_data() -> void:
	var doc: Variant = _read_json(GUILDHALL_LANDSCAPE)
	if not (doc is Dictionary):
		_check(false, "Guildhall_Landscape JSON missing")
		return
	var lands: Array = (doc as Dictionary).get("landscapes", []) as Array
	var masked: int = 0
	var control: Dictionary = {}
	var control_idx: int = -1
	for i: int in range(lands.size()):
		var lc: Dictionary = lands[i] as Dictionary
		if not _visibility_layer(lc).is_empty():
			masked += 1
			if control.is_empty():
				control = lc
				control_idx = i
	var comp_idx: int = -1
	var comp: Dictionary = {}
	for i2: int in range(lands.size()):
		var lc2: Dictionary = lands[i2] as Dictionary
		if _component_contains(lc2, SAFE_ROOM_GAP[0]) and _component_contains(lc2, SAFE_ROOM_GAP[1]):
			comp_idx = i2
			comp = lc2
			break
	var vis_layer: Dictionary = _visibility_layer(comp)
	var wm: String = str(comp.get("weightmap", ""))
	var wm_ok: bool = wm.ends_with("Weightmap_20.png")
	var mask_resolved: float = 0.0  # no visibility layer -> shader fail-safe
	var gap_ok: bool = comp_idx == 12 and wm_ok and vis_layer.is_empty() \
		and not LevelLoaderScript.landscape_mask_hole(mask_resolved)
	_check(gap_ok, "safe-room gap comp=%d %s wm=%s mask=%s resolved=%.1f <0.5 visible=%s (points %s / %s)" % [
		comp_idx, _component_label(comp), wm.get_file(),
		"present" if not vis_layer.is_empty() else "absent",
		mask_resolved, str(not LevelLoaderScript.landscape_mask_hole(mask_resolved)),
		str(SAFE_ROOM_GAP[0]), str(SAFE_ROOM_GAP[1])])

	# Control: the first masked component must carry real 1.0 holes; otherwise
	# the discard rule would be vacuous and the "convention" claim empty.
	var control_ok: bool = control_idx >= 0 and not control.is_empty()
	var c_holes: int = 0
	var c_frac: float = 0.0
	var c_max: float = 0.0
	var c_samples: int = 0
	if control_ok:
		var cv: Dictionary = _visibility_layer(control)
		var wm_paths: Array = control.get("weightmaps", []) as Array
		var tex_idx: int = int(cv.get("tex", 0))
		var tex_path: String = str(wm_paths[tex_idx]) if tex_idx >= 0 and tex_idx < wm_paths.size() else str(control.get("weightmap", ""))
		var tex: Texture2D = null
		if tex_path != "":
			if ResourceLoader.exists(tex_path):
				tex = load(tex_path) as Texture2D
			elif FileAccess.file_exists(tex_path):
				var img: Image = Image.load_from_file(ProjectSettings.globalize_path(tex_path))
				if img != null and not img.is_empty():
					tex = ImageTexture.create_from_image(img)
		if tex != null:
			var st: Dictionary = LevelLoaderScript.landscape_mask_stats(tex.get_image(), int(cv.get("channel", -1)), 8)
			c_holes = int(st["holes"])
			c_frac = float(st["hole_frac"])
			c_max = float(st["max"])
			c_samples = int(st["samples"])
	_check(control_ok and c_holes > 0 and c_max > 0.5,
		"control comp=%d %s mask present ch=%d samples=%d holes=%d frac=%.3f max=%.3f" % [
			control_idx, _component_label(control),
			int(_visibility_layer(control).get("channel", -1)),
			c_samples, c_holes, c_frac, c_max])
	_check(masked > 0 and masked < lands.size(),
		"Guildhall components=%d masked=%d unmasked=%d" % [
			lands.size(), masked, lands.size() - masked])


func _param_int(mat: ShaderMaterial, name: String, fallback: int = -1) -> int:
	if mat == null:
		return fallback
	var v: Variant = mat.get_shader_parameter(name)
	if v == null:
		return fallback
	return int(v)


func _check_loader_binding() -> void:
	var doc: Variant = _read_json(GUILDHALL_LANDSCAPE)
	if not (doc is Dictionary):
		_check(false, "loader binding: Guildhall_Landscape JSON missing")
		return
	var lands: Array = (doc as Dictionary).get("landscapes", []) as Array
	var masked_comp: Dictionary = {}
	var gap_comp: Dictionary = {}
	for i: int in range(lands.size()):
		var lc: Dictionary = lands[i] as Dictionary
		if not _visibility_layer(lc).is_empty() and masked_comp.is_empty():
			masked_comp = lc
		if i == 12:
			gap_comp = lc
	var ll: Node = LevelLoaderScript.new()
	root.add_child(ll)
	await process_frame
	var binding_ok: bool = true
	var lines: Array[String] = []
	for mode: String in ["discard", "raw", "off"]:
		OS.set_environment("TAT2_LANDSCAPE_MASK", mode)
		var mat: ShaderMaterial = ll.call("_landscape_weighted_material", masked_comp) as ShaderMaterial
		var params: Dictionary = LevelLoaderScript.landscape_mask_params(mode)
		var ok: bool = mat != null \
			and is_equal_approx(float(mat.get_shader_parameter("sample_mask")), float(params["sample_mask"])) \
			and is_equal_approx(float(mat.get_shader_parameter("discard_holes")), float(params["discard_holes"])) \
			and is_equal_approx(float(mat.get_shader_parameter("mask_raw_view")), float(params["mask_raw_view"])) \
			and _param_int(mat, "visibility_tex_idx") >= 0 \
			and _param_int(mat, "visibility_channel") >= 0
		binding_ok = binding_ok and ok
		lines.append("%s=%s" % [mode, str(ok)])
	OS.set_environment("TAT2_LANDSCAPE_MASK", "discard")
	var gap_mat: ShaderMaterial = ll.call("_landscape_weighted_material", gap_comp) as ShaderMaterial
	var gap_ok: bool = gap_mat != null \
		and _param_int(gap_mat, "visibility_tex_idx") == -1 \
		and _param_int(gap_mat, "visibility_channel") == -1 \
		and is_equal_approx(float(gap_mat.get_shader_parameter("discard_holes")), 1.0)
	OS.unset_environment("TAT2_LANDSCAPE_MASK")
	_check(binding_ok and gap_ok,
		"loader binding masked[%s] gap_comp12=%s" % [", ".join(lines), str(gap_ok)])
	ll.queue_free()
	await process_frame
