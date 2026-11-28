extends SceneTree
## P1-BEAMS probe: authored security-beam material + KF27 foyer dressing.
##
##   tools/godot --headless --path game --script res://tests/probe_p1_beams.gd
##
## Prints one PASS/FAIL line per check plus the stable gate marker:
##   P1_BEAMS PASS beam_mat=... cards=330 axis_err_deg=... bulb=1 node=1 plaques=2 plate=1
##
## What it measures (source in brackets):
##   1. the shader's render_mode + authored uniforms [tat_beam.gdshader]
##   2. the loader-built MI_LightBeam_SM material [materials.json]
##   3. the P0a card transform: local X -> record col2, slot-2 length
##      [Guildhall_Gameplay / OldManor_Gameplay cards]
##   4. the authored centre-line / fake-glow / 25 m-fade profile, evaluated
##      with the same math as the shader (no broad shell); the P4.5 core
##      (Fake Glow Thickness + Center Power) is measured glow-only so the
##      centre line cannot mask it
##   5. every authored beam scalar is consumed from materials.json (no
##      literals), including the exposed-but-inert side/sphere/edge terms
##   6. the KF27 contract: one band at 40.0-40.5 %, emitter 17.8 %/40.0 %,
##      the foyer_beam cue, and the Lounge beam_close extra
##      [build/qa/kf27_beam_reference.json + capture/ROI tables]
##   7. the authored foyer dressing records (vitrine, armchair/ottoman,
##      plaques, node, emitter hardware) [Building_Guildhall_POI + Gameplay]
##   8. the dressing module on a synthetic scene: bulb/node material repair,
##      authored plaque text, PORT_APPROX floor plate
##
## It is headless and loads no map, so it can run beside the other P1 probes.

const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const FoyerDressingScript := preload("res://src/core/foyer_dressing.gd")

const BEAM_SHADER_PATH := "res://src/core/tat_beam.gdshader"
const BEAM_MAT := "/Game/Gameplay/Traps/Detectors/LightBeam/MI_LightBeam_SM"
const BEAM_CARD_MESH := "/Game/Art/Effects/LightBeam/SM_LightBeam"
const MATERIALS := "res://data/generated/materials.json"
const GUILDHALL_GAMEPLAY := "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json"
const OLDMANOR_GAMEPLAY := "res://data/generated/levels/OldManor/OldManor_Gameplay.tatlevel.json"
const POI_LEVEL := "res://data/generated/levels/Buildings/Guildhall/Building_Guildhall_POI.tatlevel.json"

const BULB_UE := "/Game/Art/Gameplay/LightBeam/SM_LightBeam_Bulb"
const NODE_UE := "/Game/Art/Environment/Lights/LightModules/EmissiveShapes/SM_Sphere2Count"
const NODE_POS := Vector3(28.8973, 30.4025, -58.002)

var _fails: int = 0
var _checks: int = 0
var _last: String = ""


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, line: String) -> void:
	_checks += 1
	if ok:
		print("P1_BEAMS OK ", line)
	else:
		_fails += 1
		printerr("P1_BEAMS FAIL ", line)
	_last = line


func _run() -> void:
	await process_frame
	var shader_txt: String = _read_text(BEAM_SHADER_PATH)
	_check_shader_source(shader_txt)

	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	if ll_scr == null or not ll_scr.can_instantiate():
		printerr("P1_BEAMS FAIL level_loader.gd failed to compile (see the SCRIPT ERROR above)")
		print("P1_BEAMS FAIL checks=%d fails=%d (loader)" % [_checks, _fails])
		quit(1)
		return
	var ll: Node = ll_scr.new()
	root.add_child(ll)
	await process_frame
	ll.call("_load_material_dbs")

	var mat: ShaderMaterial = ll.call("get_material_for_ue", BEAM_MAT) as ShaderMaterial
	var values: Dictionary = _check_material(mat)
	_check_authored_row(values, _read_json(MATERIALS) as Dictionary)
	_check_authored_terms(values, _read_json(MATERIALS) as Dictionary)
	_check_geometry(ll)
	_check_profile(values)
	_check_kf27_contract()
	_check_foyer_records()
	_check_dressing_module(ll)

	print("P1_BEAMS %s checks=%d fails=%d last=%s" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails, _last])
	ll.queue_free()
	await process_frame
	quit(0 if _fails == 0 else 1)


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _check_shader_source(txt: String) -> void:
	var render_ok: bool = txt.find("render_mode unshaded") >= 0 \
		and txt.find("blend_add") >= 0 and txt.find("cull_disabled") >= 0
	var defaults_ok: bool = txt.find("center_line_thickness = 0.015") >= 0 \
		and txt.find("center_line_opacity = 0.5") >= 0 \
		and txt.find("fake_glow_opacity = 0.06") >= 0 \
		and txt.find("fake_glow_thickness = 0.02") >= 0 \
		and txt.find("fake_glow_center_power = 2.0") >= 0 \
		and txt.find("fake_glow_side_width = 1.0") >= 0 \
		and txt.find("center_line_sphere_mask_radius = 1.0") >= 0 \
		and txt.find("sphere_mask_opacity = 0.25") >= 0 \
		and txt.find("sphere_mask_power = 2.0") >= 0 \
		and txt.find("edge_fade_power = 0.5") >= 0 \
		and txt.find("fade_distance = 25.0") >= 0 \
		and txt.find("4.3813") >= 0 and txt.find("3.5156") >= 0
	var radial_ok: bool = txt.find("v_local.yz") >= 0 and txt.find("radial_axis") >= 0
	# The three ambiguous groups must be documented as exposed/not applied,
	# not silently dropped: the probe pins the rationale next to the uniforms.
	var ambiguous_ok: bool = txt.find("Fake Glow Side Width = 1.0 m    (exposed, not applied") >= 0 \
		and txt.find("Center Line Sphere Mask Radius = 1.0 m  (exposed, not applied") >= 0 \
		and txt.find("EdgeFadePower        = 0.5     (exposed, not applied") >= 0
	# The four ambiguous groups are exposed as uniforms but must not enter the
	# fragment math (no `uniform * ...` / `uniform / ...` use).
	var inert_ok: bool = txt.find("fake_glow_side_width *") < 0 \
		and txt.find("center_line_sphere_mask_radius *") < 0 \
		and txt.find("sphere_mask_opacity *") < 0 \
		and txt.find("sphere_mask_power *") < 0 \
		and txt.find("edge_fade_power *") < 0
	_check(render_ok and defaults_ok and radial_ok and ambiguous_ok and inert_ok,
		"shader render_mode=unshaded+blend_add+cull_disabled authored_defaults=%s radial=%s ambiguous_documented=%s inert=%s" % [
			str(defaults_ok), str(radial_ok), str(ambiguous_ok), str(inert_ok)])


func _check_material(mat: ShaderMaterial) -> Dictionary:
	var col := Color(0, 0, 0, 0)
	var emissive := 0.0
	var thickness := 0.0
	var line_opacity := 0.0
	var falloff := 0.0
	var glow := 0.0
	var glow_thickness := 0.0
	var glow_width := 0.0
	var glow_center_power := 0.0
	var glow_power := 0.0
	var glow_side_width := 0.0
	var sphere_radius := 0.0
	var sphere_opacity := 0.0
	var sphere_power := 0.0
	var edge_fade := 0.0
	var fade := 0.0
	var axis := -1
	if mat != null and mat.shader != null:
		var cv: Variant = mat.get_shader_parameter("beam_color")
		if cv is Color:
			col = cv as Color
		emissive = float(mat.get_shader_parameter("emissive_multiplier"))
		thickness = float(mat.get_shader_parameter("center_line_thickness"))
		line_opacity = float(mat.get_shader_parameter("center_line_opacity"))
		falloff = float(mat.get_shader_parameter("center_line_falloff"))
		glow = float(mat.get_shader_parameter("fake_glow_opacity"))
		glow_thickness = float(mat.get_shader_parameter("fake_glow_thickness"))
		glow_width = float(mat.get_shader_parameter("fake_glow_center_width"))
		glow_center_power = float(mat.get_shader_parameter("fake_glow_center_power"))
		glow_power = float(mat.get_shader_parameter("fake_glow_power"))
		glow_side_width = float(mat.get_shader_parameter("fake_glow_side_width"))
		sphere_radius = float(mat.get_shader_parameter("center_line_sphere_mask_radius"))
		sphere_opacity = float(mat.get_shader_parameter("sphere_mask_opacity"))
		sphere_power = float(mat.get_shader_parameter("sphere_mask_power"))
		edge_fade = float(mat.get_shader_parameter("edge_fade_power"))
		fade = float(mat.get_shader_parameter("fade_distance"))
		axis = int(mat.get_shader_parameter("radial_axis"))
	var ok: bool = mat != null and mat.shader != null \
		and mat.shader.resource_path.ends_with("tat_beam.gdshader") \
		and absf(col.r - 5.0) < 0.0001 and absf(col.g - 4.3813) < 0.0001 \
		and absf(col.b - 3.5156) < 0.0001 and absf(col.a - 0.5) < 0.0001 \
		and absf(emissive - 3.0) < 0.0001 and absf(thickness - 0.015) < 0.0001 \
		and absf(line_opacity - 0.5) < 0.0001 and absf(falloff - 0.25) < 0.0001 \
		and absf(glow - 0.06) < 0.0001 and absf(glow_thickness - 0.02) < 0.0001 \
		and absf(glow_width - 0.085) < 0.0001 and absf(glow_center_power - 2.0) < 0.0001 \
		and absf(glow_power - 1.1) < 0.0001 and absf(glow_side_width - 1.0) < 0.0001 \
		and absf(sphere_radius - 1.0) < 0.0001 and absf(sphere_opacity - 0.25) < 0.0001 \
		and absf(sphere_power - 2.0) < 0.0001 and absf(edge_fade - 0.5) < 0.0001 \
		and absf(fade - 25.0) < 0.0001 and axis == 0
	_check(ok, "loader MI_LightBeam_SM shader=%s color=(%.4f,%.4f,%.4f,%.2f) emissive=%.1f line=%.3fm a=%.2f falloff=%.2f glow=%.2f/%.3fm core=%.3fm cp=%.1f p=%.1f side=%.2fm sphere=%.1f/%.2f/%.1f edge=%.2f fade=%.0fm axis=%d" % [
		mat.shader.resource_path.get_file() if mat != null and mat.shader != null else "<none>",
		col.r, col.g, col.b, col.a, emissive, thickness, line_opacity, falloff,
		glow, glow_width, glow_thickness, glow_center_power, glow_power, glow_side_width,
		sphere_radius, sphere_opacity, sphere_power, edge_fade, fade, axis])
	return {
		"color": col, "emissive": emissive, "thickness": thickness,
		"line_opacity": line_opacity, "falloff": falloff, "glow": glow,
		"glow_thickness": glow_thickness, "glow_width": glow_width,
		"glow_center_power": glow_center_power, "glow_power": glow_power,
		"glow_side_width": glow_side_width, "sphere_radius": sphere_radius,
		"sphere_opacity": sphere_opacity, "sphere_power": sphere_power,
		"edge_fade": edge_fade, "fade": fade,
	}


func _check_authored_row(values: Dictionary, mats: Dictionary) -> void:
	var row: Dictionary = mats.get(BEAM_MAT, {}) as Dictionary
	var base: Array = (row.get("vectors", {}) as Dictionary).get("BaseColor", []) as Array
	var params: Dictionary = row.get("params", {}) as Dictionary
	var render: Dictionary = row.get("render", {}) as Dictionary
	var ok: bool = base.size() >= 4 \
		and absf(float(base[0]) - 5.0) < 0.0001 \
		and absf(float(base[1]) - 4.3813) < 0.0001 \
		and absf(float(base[2]) - 3.5156) < 0.0001 \
		and absf(float(base[3]) - 0.5) < 0.0001 \
		and absf(float(params.get("EmissiveMultiplier", 0.0)) - 3.0) < 0.0001 \
		and absf(float(params.get("Center Line Thickness", 0.0)) - 0.015) < 0.0001 \
		and absf(float(params.get("Center Line Opacity", 0.0)) - 0.5) < 0.0001 \
		and absf(float(params.get("Fake Glow Opacity", 0.0)) - 0.06) < 0.0001 \
		and absf(float(params.get("FadeDistance", 0.0)) - 25.0) < 0.0001 \
		and str(render.get("blend_mode", "")).ends_with("BLEND_Additive") \
		and bool(render.get("two_sided", false)) \
		and str(render.get("shading_model", "")).ends_with("MSM_Unlit") \
		and values.get("color", Color()) == Color(5.0, 4.3813, 3.5156, 0.5)
	_check(ok, "authored MI_LightBeam_SM row matches the port params (BaseColor=%s, line=%.3f, glow=%.2f, fade=%.0f, additive/two-sided/unlit)" % [
		str(base), float(params.get("Center Line Thickness", 0.0)),
		float(params.get("Fake Glow Opacity", 0.0)),
		float(params.get("FadeDistance", 0.0))])


func _check_authored_terms(values: Dictionary, mats: Dictionary) -> void:
	# P4.5 consumption contract: every authored scalar that the shader/loader
	# exposes must come from the generated row, not a literal. This is the
	# check that fails if a producer drops a term or the loader stops reading it.
	var row: Dictionary = mats.get(BEAM_MAT, {}) as Dictionary
	var params: Dictionary = row.get("params", {}) as Dictionary
	var terms: Dictionary = {
		"EmissiveMultiplier": "emissive",
		"Center Line Thickness": "thickness",
		"Center Line Opacity": "line_opacity",
		"Center Line Falloff": "falloff",
		"Fake Glow Opacity": "glow",
		"Fake Glow Thickness": "glow_thickness",
		"Fake Glow Center Width": "glow_width",
		"Fake Glow Center Power": "glow_center_power",
		"Fake Glow Power": "glow_power",
		"Fake Glow Side Width": "glow_side_width",
		"Center Line Sphere Mask Radius": "sphere_radius",
		"Sphere Mask Opacity": "sphere_opacity",
		"Sphere Mask Power": "sphere_power",
		"EdgeFadePower": "edge_fade",
		"FadeDistance": "fade",
	}
	var consumed: int = 0
	var missing: Array[String] = []
	var mismatched: Array[String] = []
	for row_name: String in terms.keys():
		var key: String = str(terms[row_name])
		if not params.has(row_name):
			missing.append(row_name)
			continue
		var want: float = float(params[row_name])
		var got: float = float(values.get(key, -9999.0))
		if absf(want - got) > 0.000001:
			mismatched.append("%s(row=%.6f mat=%.6f)" % [row_name, want, got])
		else:
			consumed += 1
	# The three exposed-but-not-applied groups are still consumed as uniforms
	# (so the authored data reaches the material) even though the shader leaves
	# them inert on purpose; that distinction is asserted in _check_profile().
	var ok: bool = missing.is_empty() and mismatched.is_empty() and consumed == terms.size()
	_check(ok, "authored beam terms consumed=%d/%d missing=%s mismatched=%s" % [
		consumed, terms.size(), str(missing), str(mismatched)])


func _check_geometry(ll: Node) -> void:
	# P0a regression guard: local X must land on record col2 and the length
	# scale must stay record slot 2, with no ceiling.
	var fake: Dictionary = {
		"mesh": BEAM_CARD_MESH,
		"pos": [1.0, 2.0, 3.0],
		"basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
		"scale": [1.0, 1.0, 42.0],
	}
	var tr: Transform3D = LevelLoaderScript.beam_card_transform(fake)
	var axis: Vector3 = tr.basis.x.normalized()
	var scale_len: float = tr.basis.x.length()
	var fake_ok: bool = axis.is_equal_approx(Vector3(0.0, 0.0, 1.0)) \
		and absf(scale_len - 42.0) < 0.0001
	var cards: int = 0
	var max_axis_err: float = 0.0
	var max_len_err: float = 0.0
	for path: String in [GUILDHALL_GAMEPLAY, OLDMANOR_GAMEPLAY]:
		var doc: Variant = _read_json(path)
		if not (doc is Dictionary):
			continue
		for m_v: Variant in ((doc as Dictionary).get("meshes", []) as Array):
			if not (m_v is Dictionary):
				continue
			var m: Dictionary = m_v as Dictionary
			if str(m.get("mesh", "")) != BEAM_CARD_MESH:
				continue
			cards += 1
			var b: Array = m.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]) as Array
			var s: Array = m.get("scale", [1, 1, 1]) as Array
			var col2 := Vector3(float(b[2]), float(b[5]), float(b[8]))
			var card_tr: Transform3D = LevelLoaderScript.beam_card_transform(m)
			var card_axis: Vector3 = card_tr.basis.x.normalized()
			var err: float = rad_to_deg(atan2(card_axis.cross(col2.normalized()).length(), card_axis.dot(col2.normalized())))
			max_axis_err = maxf(max_axis_err, err)
			if s.size() >= 3 and float(s[2]) > 0.0:
				var len_err: float = absf(card_tr.basis.x.length() - float(s[2])) / float(s[2])
				max_len_err = maxf(max_len_err, len_err)
	var info: Dictionary = ll.call("_get_mesh_and_shape", BEAM_CARD_MESH) as Dictionary
	var mesh: Mesh = null
	var mesh_v: Variant = info.get("mesh", null)
	if mesh_v is Mesh:
		mesh = mesh_v as Mesh
	var size := Vector3.ZERO
	if mesh != null:
		size = mesh.get_aabb().size
	var mesh_ok: bool = size.x > 0.09 and size.x < 0.11 and size.y > 0.99 and size.y < 1.01 and size.z > 0.99 and size.z < 1.01
	_check(fake_ok and cards == 330 and max_axis_err < 0.001 and max_len_err < 0.0001 and mesh_ok,
		"geometry col2 axis=%s len=%.1fm cards=%d max_axis_err_deg=%.6f max_len_err=%.7f card_aabb=(%.3f,%.3f,%.3f)" % [
			str(axis), scale_len, cards, max_axis_err, max_len_err, size.x, size.y, size.z])


func _check_profile(values: Dictionary) -> void:
	var thickness: float = float(values.get("thickness", 0.015))
	var line_a: float = float(values.get("line_opacity", 0.5))
	var falloff: float = float(values.get("falloff", 0.25))
	var glow_a: float = float(values.get("glow", 0.06))
	var glow_thick: float = float(values.get("glow_thickness", 0.02))
	var glow_w: float = float(values.get("glow_width", 0.085))
	var glow_cp: float = float(values.get("glow_center_power", 2.0))
	var glow_p: float = float(values.get("glow_power", 1.1))
	var fade: float = float(values.get("fade", 25.0))

	var a_core: float = _beam_alpha(0.0, 8.0, thickness, line_a, falloff, glow_a, glow_thick, glow_w, glow_cp, glow_p, fade)
	var a_half: float = _beam_alpha(thickness * 0.5, 8.0, thickness, line_a, falloff, glow_a, glow_thick, glow_w, glow_cp, glow_p, fade)
	var a_1cm: float = _beam_alpha(0.01, 8.0, thickness, line_a, falloff, glow_a, glow_thick, glow_w, glow_cp, glow_p, fade)
	var a_25cm: float = _beam_alpha(0.25, 8.0, thickness, line_a, falloff, glow_a, glow_thick, glow_w, glow_cp, glow_p, fade)
	var a_shell: float = _beam_alpha(0.50, 8.0, thickness, line_a, falloff, glow_a, glow_thick, glow_w, glow_cp, glow_p, fade)
	var a_near: float = _beam_alpha(0.0, 8.0, thickness, line_a, falloff, glow_a, glow_thick, glow_w, glow_cp, glow_p, fade)
	var a_mid: float = _beam_alpha(0.0, 20.0, thickness, line_a, falloff, glow_a, glow_thick, glow_w, glow_cp, glow_p, fade)
	var a_far: float = _beam_alpha(0.0, 25.0, thickness, line_a, falloff, glow_a, glow_thick, glow_w, glow_cp, glow_p, fade)

	# P4.5 core: the authored 2 cm thickness / 2.0 centre power must show up in
	# the glow-only profile (the 1.5 cm centre line would otherwise mask it).
	var g_zero: float = _beam_glow(0.0, glow_a, glow_thick, glow_w, glow_cp, glow_p)
	var g_plateau: float = _beam_glow(glow_thick * 0.25, glow_a, glow_thick, glow_w, glow_cp, glow_p)
	var g_core_edge: float = _beam_glow(glow_thick * 0.5, glow_a, glow_thick, glow_w, glow_cp, glow_p)
	var g_cp4: float = _beam_glow(glow_thick * 0.4, glow_a, glow_thick, glow_w, 4.0, glow_p)
	var g_thick2x: float = _beam_glow(glow_thick * 0.4, glow_a, glow_thick * 2.0, glow_w, glow_cp, glow_p)
	var g_tail: float = _beam_glow(0.05, glow_a, glow_thick, glow_w, glow_cp, glow_p)
	var g_end: float = _beam_glow(glow_w, glow_a, glow_thick, glow_w, glow_cp, glow_p)
	var core_ok: bool = absf(g_zero - glow_a) < 0.0001 \
		and absf(g_plateau - glow_a) < 0.0001 \
		and g_core_edge < g_plateau and g_core_edge > 0.0 \
		and g_cp4 < g_plateau and g_thick2x > g_core_edge
	var ok: bool = absf(a_core - clampf(line_a + glow_a, 0.0, 1.0)) < 0.0001 \
		and a_half > 0.25 and a_half < a_core \
		and a_1cm < glow_a + 0.005 \
		and a_25cm <= 0.0001 and a_shell <= 0.0001 \
		and absf(a_near - a_core) < 0.0001 and a_mid < a_near and a_mid > 0.1 \
		and a_far <= 0.0001 and core_ok \
		and g_tail > 0.0 and g_end <= 0.0001
	_check(ok, "profile center=%.3f half=%.3f 1cm=%.3f 25cm=%.4f shell=%.4f fade@8=%.3f @20=%.3f @25=%.4f core=(0=%.3f plateau=%.3f edge=%.3f cp4=%.3f thick2x=%.3f)" % [
		a_core, a_half, a_1cm, a_25cm, a_shell, a_near, a_mid, a_far,
		g_zero, g_plateau, g_core_edge, g_cp4, g_thick2x])


static func _beam_glow(radius: float, glow_a: float, glow_thick: float,
		glow_w: float, glow_cp: float, glow_p: float) -> float:
	var core_r: float = maxf(glow_thick * 0.5, 0.0001)
	var center_r: float = maxf(glow_w, core_r + 0.0001)
	var body_t: float = clampf(1.0 - radius / center_r, 0.0, 1.0)
	var body: float = pow(body_t, maxf(glow_p, 0.001))
	var core_t: float = clampf(1.0 - radius / core_r, 0.0, 1.0)
	var core: float = pow(core_t, maxf(glow_cp, 0.001))
	return glow_a * minf(body + core, 1.0)


static func _beam_alpha(radius: float, cam_dist: float, thickness: float, line_a: float,
		falloff: float, glow_a: float, glow_thick: float, glow_w: float,
		glow_cp: float, glow_p: float, fade: float) -> float:
	var half_t: float = maxf(thickness * 0.5, 0.0005)
	var inner: float = maxf(half_t * (1.0 - falloff), 0.0)
	var outer: float = maxf(half_t * (1.0 + falloff), inner + 0.0001)
	var line: float = 1.0 - smoothstep(inner, outer, radius)
	var glow: float = _beam_glow(radius, glow_a, glow_thick, glow_w, glow_cp, glow_p)
	var a: float = clampf(line_a * line + glow, 0.0, 1.0)
	var fade_start: float = fade * 0.75
	a *= 1.0 - smoothstep(fade_start, maxf(fade, fade_start + 0.001), cam_dist)
	return a


func _check_kf27_contract() -> void:
	# The KF27 expectation is one measured contract shared by the headless probe
	# and the ROI scorer: one band at 40.0-40.5 %, emitter at 17.8 %/40.0 %,
	# the foyer_beam cue, and the Lounge beam_close extra (no KF27 criteria).
	var ref: Variant = _read_json("res://../build/qa/kf27_beam_reference.json")
	var j: Dictionary = ref as Dictionary if ref is Dictionary else {}
	var measured: Dictionary = j.get("measured", {}) as Dictionary
	var emitter: Dictionary = measured.get("emitter_pct", {}) as Dictionary
	var band: Array = measured.get("beam_band_row_pct", []) as Array
	var cue: Dictionary = j.get("foyer_beam_cue", {}) as Dictionary
	var extra: Dictionary = j.get("lounge_extra", {}) as Dictionary
	var cue_eye: Array = cue.get("eye", []) as Array
	var cue_target: Array = cue.get("target", []) as Array
	var ref_ok: bool = not j.is_empty() \
		and str(j.get("keyframe", "")) == "KF27" \
		and absf(float(emitter.get("x", 0.0)) - 17.8) < 0.0001 \
		and absf(float(emitter.get("y", 0.0)) - 40.0) < 0.0001 \
		and int(measured.get("beam_bands", 0)) == 1 \
		and band.size() == 2 and absf(float(band[0]) - 40.0) < 0.0001 and absf(float(band[1]) - 40.5) < 0.0001 \
		and cue_eye.size() == 3 and cue_target.size() == 3 \
		and absf(float(cue_eye[0]) - 27.0) < 0.0001 and absf(float(cue_eye[1]) - 29.67) < 0.0001 \
		and absf(float(cue_eye[2]) + 55.0) < 0.0001 \
		and absf(float(cue_target[0]) - 23.27) < 0.0001 and absf(float(cue_target[1]) - 29.76) < 0.0001 \
		and absf(float(cue_target[2]) + 57.4) < 0.0001 \
		and str(extra.get("pose", "")) == "beam_close"
	# The capture table and the ROI script must point at the same contract.
	var cap_txt: String = _read_text("res://../build/qa/p0b_capture.gd")
	var roi_txt: String = _read_text("res://../build/qa/p0b_roi_stats.py")
	var cap_ok: bool = cap_txt.find("\"foyer_beam\"") >= 0 \
		and cap_txt.find("Vector3(27.0, 29.67, -55.0)") >= 0 \
		and cap_txt.find("Vector3(23.27, 29.76, -57.4)") >= 0 \
		and cap_txt.find("\"ref\": \"EXTRA\"") >= 0 \
		and cap_txt.find("\"lounge\"") >= 0
	var roi_ok: bool = roi_txt.find("\"foyer_beam\": \"KF27_03m27s_foyer_security_beam.jpg\"") >= 0 \
		and roi_txt.find("POSE_EXTRAS") >= 0 and roi_txt.find("\"beam_close\"") >= 0 \
		and roi_txt.find("\"one_band\":") >= 0 \
		and roi_txt.find("\"emitter_at_kf27\":") >= 0 \
		and roi_txt.find("and pose not in POSE_EXTRAS") >= 0 \
		and roi_txt.find("kf27_beam_reference.json") >= 0
	_check(ref_ok and cap_ok and roi_ok,
		"KF27 contract emitter=(%.1f,%.1f) bands=%d row=(%.1f,%.1f) foyer_beam=%s lounge_extra=%s ref=%s capture=%s roi=%s" % [
			float(emitter.get("x", 0.0)), float(emitter.get("y", 0.0)),
			int(measured.get("beam_bands", 0)), float(band[0]) if band.size() > 0 else -1.0,
			float(band[1]) if band.size() > 1 else -1.0, str(cue_eye), str(extra.get("pose", "")),
			str(ref_ok), str(cap_ok), str(roi_ok)])


func _check_foyer_records() -> void:
	var poi: Variant = _read_json(POI_LEVEL)
	var gp: Variant = _read_json(GUILDHALL_GAMEPLAY)
	if not (poi is Dictionary) or not (gp is Dictionary):
		_check(false, "foyer records: POI/Gameplay level JSON missing")
		return
	var counts: Dictionary = {}
	var node_pos := Vector3.ZERO
	var node_found: bool = false
	for m_v: Variant in ((poi as Dictionary).get("meshes", []) as Array):
		if not (m_v is Dictionary):
			continue
		var m: Dictionary = m_v as Dictionary
		var p: Array = m.get("pos", [0, 0, 0]) as Array
		var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
		if pos.x < 18.0 or pos.x > 36.0 or pos.y < 27.0 or pos.y > 34.0 or pos.z < -62.0 or pos.z > -42.0:
			continue
		var mp: String = str(m.get("mesh", ""))
		var key: String = mp.get_file()
		counts[key] = int(counts.get(key, 0)) + 1
		if key == "SM_Sphere2Count" and pos.distance_to(NODE_POS) < 0.01:
			node_found = true
			node_pos = pos
	var emitter: int = 0
	for m_v2: Variant in ((gp as Dictionary).get("meshes", []) as Array):
		if not (m_v2 is Dictionary):
			continue
		var m2: Dictionary = m_v2 as Dictionary
		var p2: Array = m2.get("pos", [0, 0, 0]) as Array
		var pos2 := Vector3(float(p2[0]), float(p2[1]), float(p2[2]))
		if pos2.x < 18.0 or pos2.x > 36.0 or pos2.y < 27.0 or pos2.y > 34.0 or pos2.z < -62.0 or pos2.z > -42.0:
			continue
		var k2: String = str(m2.get("mesh", "")).get_file()
		if k2 in ["SM_LightBeam_Base", "SM_LightBeam_Bulb", "SM_LightBeam_Lens"]:
			emitter += 1
	var vitrine: int = 0
	for i: int in range(1, 6):
		vitrine += int(counts.get("SM_Museum_DisplayCase_2x2_Tall_0%d" % i, 0))
	var ok: bool = emitter == 15 \
		and vitrine == 5 and int(counts.get("SM_GuardEnforcer_Salute", 0)) == 1 \
		and int(counts.get("SM_SofaFancyA", 0)) == 1 and int(counts.get("SM_StoolA", 0)) == 1 \
		and int(counts.get("SM_Manor_RugA", 0)) == 2 \
		and int(counts.get("SM_InteriorSign_WealthyA", 0)) == 1 \
		and int(counts.get("SM_InteriorSign_CommonC", 0)) == 1 \
		and node_found
	_check(ok, "foyer records emitter_instances=%d (5 base+bulb+lens x3) vitrine=%d statue=%d armchair=%d ottoman=%d rug=%d plaques=%d cyan_node=%s at %s" % [
		emitter, vitrine, int(counts.get("SM_GuardEnforcer_Salute", 0)),
		int(counts.get("SM_SofaFancyA", 0)), int(counts.get("SM_StoolA", 0)),
		int(counts.get("SM_Manor_RugA", 0)),
		int(counts.get("SM_InteriorSign_WealthyA", 0)) + int(counts.get("SM_InteriorSign_CommonC", 0)),
		str(node_found), str(node_pos)])


static func _find_meta_node(root: Node, meta_key: String) -> Node3D:
	if root == null:
		return null
	for child: Node in root.get_children():
		if child.has_meta(meta_key):
			return child as Node3D
		var found: Node3D = _find_meta_node(child, meta_key)
		if found != null:
			return found
	return null


func _check_dressing_module(ll: Node) -> void:
	var host := Node3D.new()
	host.name = "P1DressingProbeHost"
	root.add_child(host)
	# Authored bulb item (all 134 emitters share one MultiMesh in a real load).
	var bulb := MultiMeshInstance3D.new()
	bulb.name = "BulbItem"
	bulb.set_meta("ue_mesh", BULB_UE)
	host.add_child(bulb)
	# Authored cyan node item with one instance at the POI placement.
	var node := MultiMeshInstance3D.new()
	node.name = "CyanNodeItem"
	node.position = NODE_POS
	node.set_meta("ue_mesh", NODE_UE)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	node.multimesh = mm
	host.add_child(node)

	var dressing: Node3D = FoyerDressingScript.build(host, ll)
	var cyan_node: Node3D = _find_meta_node(host, "p1_cyan_node")
	var stats: Dictionary = {}
	if dressing != null:
		var sv: Variant = dressing.get("stats")
		if sv is Dictionary:
			stats = sv as Dictionary
	var labels: Array[String] = []
	var plate: Node3D = null
	if dressing != null:
		for child: Node in dressing.get_children():
			if child is Label3D:
				labels.append((child as Label3D).text)
			if child is MeshInstance3D and child.has_meta("p1_floor_plate"):
				plate = child as Node3D
	labels.sort()
	var bulb_mat: StandardMaterial3D = bulb.material_override as StandardMaterial3D
	var node_mat: StandardMaterial3D = null
	if cyan_node != null:
		var nmv: Variant = cyan_node.get("material_override")
		if nmv is StandardMaterial3D:
			node_mat = nmv as StandardMaterial3D
	var bulb_ok: bool = bulb_mat != null \
		and bulb_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
		and bulb_mat.albedo_color.is_equal_approx(Color(1.0, 0.6892, 0.2661, 1.0) * 2.0)
	var node_ok: bool = node_mat != null \
		and node_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
		and node_mat.albedo_color.b > node_mat.albedo_color.r + 0.4 \
		and node_mat.albedo_color.g > node_mat.albedo_color.r
	var stats_ok: bool = dressing != null \
		and int(stats.get("emitter_bulbs", 0)) == 1 \
		and int(stats.get("node_items", 0)) + int(stats.get("node_created", 0)) >= 1 \
		and int(stats.get("plaque_labels", 0)) == 2 \
		and int(stats.get("floor_plate", 0)) == 1 \
		and labels.has("WC") and labels.has("Basement\nStairs")
	var plate_ok: bool = plate != null and str(plate.get_meta("placement", "")).find("PORT_APPROX") >= 0
	_check(bulb_ok and node_ok and stats_ok and plate_ok,
		"dressing bulb=%s node=%s stats=%s labels=%s plate=%s approx=%s" % [
			str(bulb_ok), str(node_ok), str(stats), str(labels), str(plate != null), str(plate_ok)])
	host.queue_free()
