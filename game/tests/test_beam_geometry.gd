extends SceneTree
## P0a lane-B standalone headless beam-geometry truth test.
##
## The shipped maps have 330 authored SM_LightBeam cards: 134 in
## Guildhall_Gameplay and 196 in OldManor_Gameplay, one per
## BP_Detector_LightBeam_C and paired 1:1 with devices_runtime.json by authored
## position. The UE StaticMesh is 10.2 cm long on its local X (bounds
## X -0.1..10.1 cm) and 1.0008 m wide on Y/Z. The SM_LightBeam component is
## authored with RelativeRotation.Yaw = 90, so on the detector the mesh's local
## X runs along the actor's local +Z: the merged record/device basis **column 2**
## (Basis.z), which is also the runtime security_beam.gd axis. The authored span
## is record scale slot 2 (`BeamLength` / 0.102 m; Old Manor max 236.9539 =
## 24.169 m).
##
## The pre-P0a code scaled column 0 (the 1 m cross axis), so all 330 cards were
## 90 deg cross-beam bars; the even older generic path also clamped every axis
## at 40 m (322/330 clipped) and a later 200 ceiling still clipped 5/196 Old
## Manor cards. level_loader.beam_card_transform() now rotates the card's local
## X onto column 2, applies slot 2 there and never clips the authored scale.
##
## Asserts, for all 330 cards against the real generated data:
##   * card_axis == device basis column 2 within 2 deg;
##   * card_len (0.102 m authored axis * applied scale) within 2 % of
##     BeamLength (10 m family default for the one record per map without it);
##   * the applied scale equals the authored scale (clamped == 0);
##   * the 1 m cross width (Y/Z) is unchanged.
## Negative controls prove the assertions are not vacuous: the pre-P0a col0
## transform fails direction 330/330 (its lengths pass 326/330 — the stale test
## hid the axis, and the other 4 are its own 200-ceiling clips), and the pre-W0R
## col2+40 m path fails length 330/330 and clips 129 Guildhall / 193 Old Manor.
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_beam_geometry.gd

const DEVICES_PATH := "res://data/generated/gameplay/devices_runtime.json"
const BEAM_MESH := "/Game/Art/Effects/LightBeam/SM_LightBeam"
## Authored UE StaticMesh long axis (X -0.1..10.1 cm). The imported GLB AABB is
## 0.100 m (2 % short); the transform is authored-exact against 0.102 m and the
## GLB shortfall is reported, not folded into the tolerance.
const BEAM_CARD_AXIS_M: float = 0.102
const BEAM_CARD_GLB_AXIS_M: float = 0.100
const BEAM_LEN_DEFAULT_M: float = 10.0
const LEN_TOL: float = 0.02
const AXIS_TOL_DEG: float = 2.0
const OLD_CLAMP_M: float = 40.0
const OLD_CEIL: float = 200.0
const SAMPLE_ID := "guildhall/Guildhall_Gameplay:BP_Detector_LightBeam_C_0"
const MAPS: Array = [
	{
		"key": "guildhall",
		"level": "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json",
		"cards": 134,
		"authored_max": 195.5291,
		"old40_clipped": 129,
		"old200_clipped": 0,
		"old_col0_len_pass": 134,
	},
	{
		"key": "old_manor",
		"level": "res://data/generated/levels/OldManor/OldManor_Gameplay.tatlevel.json",
		"cards": 196,
		"authored_max": 236.9539,
		"old40_clipped": 193,
		"old200_clipped": 5,
		"old_col0_len_pass": 192,
	},
]

var fails: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


## .tatlevel stores the basis row-major; the loader builds a Godot Basis whose
## columns are the record's axis vectors.
func _basis_from_record(b: Array) -> Basis:
	return Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	)


func _pos_key(p: Array) -> String:
	return "%.3f,%.3f,%.3f" % [float(p[0]), float(p[1]), float(p[2])]


## atan2 form: acos(dot) on float32 gives ~0.03 deg of noise near 1.
func _angle_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(atan2(a.normalized().cross(b.normalized()).length(),
		a.normalized().dot(b.normalized())))


## The exact pre-P0a (W0R) transform: authored length scale on record col0.
## This is the code this lane replaces; it is 90 deg off but its length passes.
func _old_col0_transform(rec: Dictionary) -> Transform3D:
	var b: Array = rec.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	var s: Array = rec.get("scale", [1, 1, 1])
	var p: Array = rec.get("pos", [0, 0, 0])
	var s_len: float = clampf(float(s[2]), 0.05, OLD_CEIL)
	var basis: Basis = _basis_from_record(b).scaled_local(Vector3(s_len, 1.0, 1.0))
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2])))


## The exact pre-W0R generic path: every axis clamped at 40 m, length scale left
## on record col2 (a 1 m width axis), card long axis never scaled.
func _old_generic_transform(rec: Dictionary) -> Transform3D:
	var b: Array = rec.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	var s: Array = rec.get("scale", [1, 1, 1])
	var p: Array = rec.get("pos", [0, 0, 0])
	var basis: Basis = _basis_from_record(b).scaled_local(Vector3(
		clampf(float(s[0]), 0.05, OLD_CLAMP_M),
		clampf(float(s[1]), 0.05, OLD_CLAMP_M),
		clampf(float(s[2]), 0.05, OLD_CLAMP_M)
	))
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2])))


func _initialize() -> void:
	await process_frame
	var dev_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEVICES_PATH))
	if not (dev_doc is Dictionary):
		_check(false, "", "P0A-B.0 could not parse %s" % DEVICES_PATH)
		_finish()
		return
	var maps: Dictionary = (dev_doc as Dictionary).get("maps", {}) as Dictionary
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	if ll_scr == null or not ll_scr.has_method("beam_card_transform"):
		_check(false, "", "P0A-B.0 level_loader.beam_card_transform() missing")
		_finish()
		return
	var ll: Node = ll_scr.new()
	var all_cards: Array = []
	var all_devs: Dictionary = {}
	var total_axis_max: float = 0.0
	var total_len_max: float = 0.0
	var total_glb_max: float = 0.0
	var total_axis_bad: int = 0
	var total_len_bad: int = 0
	var total_clamped: int = 0
	var total_unmatched: int = 0
	var total_old_col0_axis_bad: int = 0
	var total_old_col0_len_pass: int = 0
	var total_old40_len_pass: int = 0
	var total_old40_clip: int = 0
	var total_old200_clip: int = 0
	var total_default_len: int = 0

	for m_v: Variant in MAPS:
		var m: Dictionary = m_v as Dictionary
		var map_key: String = str(m["key"])
		var level_doc: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(str(m["level"])))
		if not (level_doc is Dictionary):
			_check(false, "", "P0A-B.1 could not parse %s" % str(m["level"]))
			continue
		var cards: Array = []
		for mesh_v: Variant in ((level_doc as Dictionary).get("meshes", []) as Array):
			if mesh_v is Dictionary and str((mesh_v as Dictionary).get("mesh", "")) == BEAM_MESH:
				cards.append(mesh_v)
		var devices: Array = ((maps.get(map_key, {}) as Dictionary).get("devices", []) as Array)
		var by_pos: Dictionary = {}
		var beam_devices: int = 0
		for d_v: Variant in devices:
			if not (d_v is Dictionary):
				continue
			var dev: Dictionary = d_v as Dictionary
			if str(dev.get("family", "")) != "light_beam":
				continue
			beam_devices += 1
			by_pos[_pos_key(dev.get("pos", [0, 0, 0]))] = dev
		var expected: int = int(m["cards"])
		_check(cards.size() == expected,
			"P0A-B.1 %s has %d %s cards" % [map_key, expected, BEAM_MESH],
			"P0A-B.1 %s expected %d cards, got %d" % [map_key, expected, cards.size()])
		_check(beam_devices == expected,
			"P0A-B.1b %s devices_runtime has %d light_beam records" % [map_key, expected],
			"P0A-B.1b %s expected %d light_beam devices, got %d" % [map_key, expected, beam_devices])

		var axis_max: float = 0.0
		var len_max: float = 0.0
		var glb_max: float = 0.0
		var axis_bad: int = 0
		var len_bad: int = 0
		var clamped: int = 0
		var width_bad: int = 0
		var unmatched: int = 0
		var authored_max: float = 0.0
		var default_len: int = 0
		var old_col0_axis_bad: int = 0
		var old_col0_len_pass: int = 0
		var old40_len_pass: int = 0
		var old40_clip: int = 0
		var old200_clip: int = 0
		var samples: Array[String] = []

		for card_v: Variant in cards:
			var rec: Dictionary = card_v as Dictionary
			var dev: Dictionary = by_pos.get(
				_pos_key(rec.get("pos", [0, 0, 0])), {}) as Dictionary
			if dev.is_empty():
				unmatched += 1
				continue
			var rec_basis: Basis = _basis_from_record(
				rec.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]))
			var dev_basis: Basis = _basis_from_record(
				dev.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1]))
			var dev_axis: Vector3 = dev_basis.z.normalized()
			var s: Array = rec.get("scale", [1, 1, 1])
			var s_auth: float = float(s[2])
			authored_max = maxf(authored_max, s_auth)

			# The new authored transform.
			var tr: Transform3D = ll_scr.beam_card_transform(rec)
			var card_axis: Vector3 = tr.basis.x.normalized()
			var axis_err: float = _angle_deg(card_axis, dev_axis)
			axis_max = maxf(axis_max, axis_err)
			if axis_err > AXIS_TOL_DEG:
				axis_bad += 1
			var axis_len: float = maxf(rec_basis.z.length(), 0.000001)
			var applied_scale: float = tr.basis.x.length() / axis_len
			if absf(applied_scale - s_auth) / s_auth > 0.00001:
				clamped += 1
			var card_len: float = tr.basis.x.length() * BEAM_CARD_AXIS_M
			var params: Dictionary = dev.get("params", {}) as Dictionary
			var beam_v: Variant = params.get("BeamLength")
			var auth_m: float = BEAM_LEN_DEFAULT_M
			if beam_v != null:
				auth_m = float(beam_v) / 100.0
			else:
				default_len += 1
			var len_err: float = absf(card_len - auth_m) / auth_m
			len_max = maxf(len_max, len_err)
			if len_err > LEN_TOL:
				len_bad += 1
			# Imported GLB is 0.100 m long: report the real rendered shortfall.
			var glb_len: float = tr.basis.x.length() * BEAM_CARD_GLB_AXIS_M
			glb_max = maxf(glb_max, absf(glb_len - auth_m) / auth_m)
			if absf(tr.basis.y.length() - 1.0) > 0.0001 \
					or absf(tr.basis.z.length() - 1.0) > 0.0001:
				width_bad += 1

			# Negative control A: the pre-P0a col0 transform (length passes,
			# direction is 90 deg off).
			var old_col0: Transform3D = _old_col0_transform(rec)
			if _angle_deg(old_col0.basis.x, dev_axis) > AXIS_TOL_DEG:
				old_col0_axis_bad += 1
			if absf(old_col0.basis.x.length() * BEAM_CARD_AXIS_M - auth_m) / auth_m <= LEN_TOL:
				old_col0_len_pass += 1
			# Negative control B: the pre-W0R col2 + 40 m clamp path.
			var old40: Transform3D = _old_generic_transform(rec)
			if absf(old40.basis.z.length() - auth_m) / auth_m <= LEN_TOL:
				old40_len_pass += 1
			if s_auth > OLD_CLAMP_M:
				old40_clip += 1
			if s_auth > OLD_CEIL:
				old200_clip += 1

			if str(dev.get("id", "")) == SAMPLE_ID:
				samples.append("%s len=%.4f m (auth %.4f, err %.3f%%) dir=%s scale=%.4f" % [
					str(dev.get("id", "")).get_file(), card_len, auth_m, len_err * 100.0,
					str(card_axis), applied_scale])

		_check(unmatched == 0,
			"P0A-B.2 %s: %d/%d cards pair with their detector record by authored position" % [
				map_key, expected, expected],
			"P0A-B.2 %s: %d cards have no matching light_beam device" % [map_key, unmatched])
		_check(axis_bad == 0,
			"P0A-B.3 %s: %d/%d card axes equal device column 2 within %.0f deg (max %.6f deg)" % [
				map_key, expected, expected, AXIS_TOL_DEG, axis_max],
			"P0A-B.3 %s: %d/%d axes outside %.0f deg (max %.6f deg)" % [
				map_key, axis_bad, expected, AXIS_TOL_DEG, axis_max])
		_check(len_bad == 0,
			"P0A-B.4 %s: %d/%d card lengths match BeamLength within %.0f%% (max err %.4f%%)" % [
				map_key, expected, expected, LEN_TOL * 100.0, len_max * 100.0],
			"P0A-B.4 %s: %d/%d lengths outside %.0f%% (max err %.4f%%)" % [
				map_key, len_bad, expected, LEN_TOL * 100.0, len_max * 100.0])
		_check(clamped == 0,
			"P0A-B.5 %s: %d/%d authored length scales applied verbatim (clamped=0, max %.4f)" % [
				map_key, expected, expected, authored_max],
			"P0A-B.5 %s: %d/%d cards had their authored scale rewritten (max %.4f)" % [
				map_key, clamped, expected, authored_max])
		_check(width_bad == 0,
			"P0A-B.6 %s: %d/%d cards keep the authored 1 m cross width (Y/Z)" % [
				map_key, expected, expected],
			"P0A-B.6 %s: %d cards changed a width axis" % [map_key, width_bad])
		_check(is_equal_approx(authored_max, float(m["authored_max"])),
			"P0A-B.7 %s authored max scale is %.4f" % [map_key, authored_max],
			"P0A-B.7 %s unexpected authored max scale %.4f (expected %.4f)" % [
				map_key, authored_max, float(m["authored_max"])])
		_check(old_col0_axis_bad == expected,
			"P0A-B.8 negative control: pre-P0a col0 transform is 90 deg off %d/%d (the stale test hid this axis)" % [
				expected, expected],
			"P0A-B.8 negative control: pre-P0a col0 axis bad %d/%d (expected all)" % [
				old_col0_axis_bad, expected])
		_check(old_col0_len_pass == int(m["old_col0_len_pass"]),
			"P0A-B.8b negative control: pre-P0a col0 lengths pass %d/%d (only its 200-ceiling clips fail)" % [
				old_col0_len_pass, expected],
			"P0A-B.8b %s expected %d pre-P0a col0 length passes, got %d" % [
				map_key, int(m["old_col0_len_pass"]), old_col0_len_pass])
		_check(old40_len_pass == 0,
			"P0A-B.9 negative control: pre-W0R col2+40 m transform fails length %d/%d" % [
				expected, expected],
			"P0A-B.9 %d cards would still pass the old length check" % old40_len_pass)
		_check(old40_clip == int(m["old40_clipped"]),
			"P0A-B.10 negative control: the old 40 m clamp clipped %d/%d %s cards" % [
				old40_clip, expected, map_key],
			"P0A-B.10 %s expected %d clipped by the old 40 m clamp, got %d" % [
				map_key, int(m["old40_clipped"]), old40_clip])
		_check(old200_clip == int(m["old200_clipped"]),
			"P0A-B.11 negative control: the 200 ceiling would clip %d/%d %s cards" % [
				old200_clip, expected, map_key],
			"P0A-B.11 %s expected %d clipped by the 200 ceiling, got %d" % [
				map_key, int(m["old200_clipped"]), old200_clip])
		_check(default_len == 1,
			"P0A-B.12 %s: exactly 1 card has no BeamLength and uses the authored 10 m family default" % map_key,
			"P0A-B.12 %s: %d cards without BeamLength (expected 1)" % [map_key, default_len])

		for line: String in samples:
			print("  sample: ", line)
		print("BEAM_MAP %s cards=%d max_axis_err_deg=%.6f max_len_err=%.6f glb_len_err=%.6f clamped=%d authored_max=%.4f old40_clipped=%d old200_clipped=%d" % [
			map_key, cards.size(), axis_max, len_max, glb_max, clamped, authored_max,
			old40_clip, old200_clip])

		all_cards.append_array(cards)
		all_devs[map_key] = by_pos
		total_axis_max = maxf(total_axis_max, axis_max)
		total_len_max = maxf(total_len_max, len_max)
		total_glb_max = maxf(total_glb_max, glb_max)
		total_axis_bad += axis_bad
		total_len_bad += len_bad
		total_clamped += clamped
		total_unmatched += unmatched
		total_old_col0_axis_bad += old_col0_axis_bad
		total_old_col0_len_pass += old_col0_len_pass
		total_old40_len_pass += old40_len_pass
		total_old40_clip += old40_clip
		total_old200_clip += old200_clip
		total_default_len += default_len

	var total_expected: int = 134 + 196
	_check(all_cards.size() == total_expected,
		"P0A-B.13 total authored SM_LightBeam cards: %d (Guildhall 134 + Old Manor 196)" % all_cards.size(),
		"P0A-B.13 total cards %d != 330" % all_cards.size())
	_check(total_axis_bad == 0 and total_unmatched == 0,
		"P0A-B.14 all %d cards: axis aligned to device column 2, 0 unmatched (max %.6f deg)" % [
			total_expected, total_axis_max],
		"P0A-B.14 totals: axis bad %d, unmatched %d (max %.6f deg)" % [
			total_axis_bad, total_unmatched, total_axis_max])
	_check(total_len_bad == 0 and total_clamped == 0,
		"P0A-B.15 all %d cards: length within %.0f%% of BeamLength and clamped=0 (max err %.4f%%)" % [
			total_expected, LEN_TOL * 100.0, total_len_max * 100.0],
		"P0A-B.15 totals: length bad %d, clamped %d (max err %.4f%%)" % [
			total_len_bad, total_clamped, total_len_max * 100.0])
	_check(total_old_col0_axis_bad == total_expected and total_old_col0_len_pass == 326,
		"P0A-B.16 negative control: pre-P0a col0 transform fails direction %d/%d while passing length %d/%d (4 over-200 cards also fail length)" % [
			total_expected, total_expected, total_old_col0_len_pass, total_expected],
		"P0A-B.16 negative control totals: axis bad %d, length pass %d (expected %d/326)" % [
			total_old_col0_axis_bad, total_old_col0_len_pass, total_expected])
	_check(total_old40_len_pass == 0 and total_old40_clip == 322 and total_old200_clip == 5,
		"P0A-B.17 negative controls: pre-W0R 40 m clamp clips %d/%d; 200 ceiling clips %d/196 Old Manor" % [
			total_old40_clip, total_expected, total_old200_clip],
		"P0A-B.17 negative controls: old40 clip %d (expected 322), old200 clip %d (expected 5)" % [
			total_old40_clip, total_old200_clip])
	print("BEAM_AXIS_TOTAL cards=%d max_axis_err_deg=%.6f max_len_err=%.6f glb_len_err=%.6f clamped=%d old40_clipped=%d old200_clipped=%d" % [
		total_expected, total_axis_max, total_len_max, total_glb_max, total_clamped,
		total_old40_clip, total_old200_clip])
	print("  note: GLB card axis is 0.100 m vs the authored 0.102 m (%.3f%% short in engine)" % [
		total_glb_max * 100.0])

	# The loader's own transform path (counters + BEAM_FIX/BEAM_AXIS evidence)
	# delegates to the same pure transform.
	var delegate_ok: bool = true
	for card_v2: Variant in all_cards:
		var rec2: Dictionary = card_v2 as Dictionary
		var via_loader: Transform3D = ll.call("_dict_to_transform", rec2)
		var pure: Transform3D = ll_scr.beam_card_transform(rec2)
		if not via_loader.is_equal_approx(pure):
			delegate_ok = false
			break
	_check(delegate_ok,
		"P0A-B.18 _dict_to_transform delegates the exact SM_LightBeam path to beam_card_transform()",
		"P0A-B.18 _dict_to_transform disagrees with beam_card_transform() for a beam record")
	_check(int(ll.get("_beam_fix_count")) == total_expected,
		"P0A-B.19 loader applied the beam fix %d times (BEAM_FIX count)" % total_expected,
		"P0A-B.19 loader beam fix count %d != %d" % [
			int(ll.get("_beam_fix_count")), total_expected])
	_check(absf(float(ll.get("_beam_fix_max_scale")) - 236.9539) < 0.0001,
		"P0A-B.19b loader BEAM_FIX max authored scale 236.9539",
		"P0A-B.19b loader max scale %.4f != 236.9539" % float(ll.get("_beam_fix_max_scale")))
	_check(float(ll.get("_beam_fix_max_axis_err_deg")) <= 0.01,
		"P0A-B.19c loader BEAM_AXIS max axis error %.6f deg (<= 0.01)" % float(ll.get("_beam_fix_max_axis_err_deg")),
		"P0A-B.19c loader max axis error %.6f deg > 0.01" % float(ll.get("_beam_fix_max_axis_err_deg")))
	_check(float(ll.get("_beam_fix_max_len_err")) <= 0.00001,
		"P0A-B.19d loader BEAM_AXIS max length error %.8f (<= 0.00001)" % float(ll.get("_beam_fix_max_len_err")),
		"P0A-B.19d loader max length error %.8f > 0.00001" % float(ll.get("_beam_fix_max_len_err")))
	_check(int(ll.get("_beam_fix_clamped")) == 0,
		"P0A-B.19e loader BEAM_AXIS clamped=0",
		"P0A-B.19e loader clamped %d != 0" % int(ll.get("_beam_fix_clamped")))

	# Runtime security_beam.gd: capsule/visual along actor-local +Z, the same
	# device column 2 as the card, and one visual after adoption.
	await _test_runtime_beam(all_devs.get("guildhall", {}) as Dictionary)
	ll.free()
	_finish()


func _test_runtime_beam(dev_by_pos: Dictionary) -> void:
	var dev: Dictionary = {}
	for d_v: Variant in dev_by_pos.values():
		if str((d_v as Dictionary).get("id", "")) == SAMPLE_ID:
			dev = d_v as Dictionary
			break
	if dev.is_empty():
		_check(false, "", "P0A-B.20 sample detector C_0 missing")
		return
	var dev_basis: Basis = _basis_from_record(dev.get("basis", []))
	var dev_axis: Vector3 = dev_basis.z.normalized()

	var defaults: Dictionary = {}
	var dev_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEVICES_PATH))
	if dev_doc is Dictionary:
		defaults = ((dev_doc as Dictionary).get("stats", {}) as Dictionary).get(
			"family_defaults", {}) as Dictionary
	var beam_scr: GDScript = load("res://src/devices/security_beam.gd") as GDScript
	var host := Node3D.new()
	root.add_child(host)
	var beam: Area3D = beam_scr.new() as Area3D
	host.add_child(beam)
	beam.call("configure", dev, defaults, 2)
	beam.global_transform = Transform3D(dev_basis, Vector3.ZERO)
	var pivot: Node3D = beam.get_node_or_null("BeamPivot") as Node3D
	var shape: CollisionShape3D = beam.get_node_or_null("BeamPivot/BeamShape") as CollisionShape3D
	var visual: MeshInstance3D = beam.get_node_or_null("BeamPivot/BeamVisual") as MeshInstance3D
	var pivot_err: float = _angle_deg(pivot.global_transform.basis.z, dev_axis) if pivot != null else -1.0
	_check(pivot != null and pivot_err <= AXIS_TOL_DEG,
		"P0A-B.20 runtime beam pivot +Z equals device column 2 (%.6f deg)" % pivot_err,
		"P0A-B.20 runtime beam direction is not device column 2 (%.6f deg)" % pivot_err)
	var beam_len: float = float(beam.get("beam_length_m"))
	var cap_ok: bool = shape != null and shape.shape is CapsuleShape3D \
		and absf(shape.position.z - beam_len * 0.5) < 0.001 \
		and absf(shape.rotation.x - PI * 0.5) < 0.0001 \
		and absf(shape.position.x) < 0.0001
	_check(cap_ok, "P0A-B.21 runtime capsule runs along +Z (centre %.3f, rot X %.3f)" % [
		shape.position.z if shape != null else -1.0, shape.rotation.x if shape != null else -1.0],
		"P0A-B.21 runtime capsule not rotated onto +Z")
	var vis_ok: bool = visual != null and absf(visual.position.z - beam_len * 0.5) < 0.001 \
		and absf(visual.rotation.x - PI * 0.5) < 0.0001
	_check(vis_ok, "P0A-B.22 stand-in visual fallback also runs along +Z",
		"P0A-B.22 stand-in visual not rotated onto +Z")

	# Card adoption: the authored card's long axis is the same column 2, and it
	# is the single visual.
	var card := Node3D.new()
	card.name = "BeamCard"
	host.add_child(card)
	var card_rec: Dictionary = {}
	for m_v: Variant in MAPS:
		var m: Dictionary = m_v as Dictionary
		if str(m["key"]) != "guildhall":
			continue
		var level_doc: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(str(m["level"])))
		if not (level_doc is Dictionary):
			continue
		for mesh_v: Variant in ((level_doc as Dictionary).get("meshes", []) as Array):
			if mesh_v is Dictionary and str((mesh_v as Dictionary).get("mesh", "")) == BEAM_MESH:
				var r: Dictionary = mesh_v as Dictionary
				if _pos_key(r.get("pos", [0, 0, 0])) == _pos_key(dev.get("pos", [0, 0, 0])):
					card_rec = r
					break
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	card.global_transform = ll_scr.beam_card_transform(card_rec)
	beam.call("adopt_beam_card", card)
	beam.call("_on_power_changed", false)
	var off_one: bool = (not card.visible) and (visual != null and not visual.visible)
	beam.call("_on_power_changed", true)
	var on_one: bool = card.visible and (visual != null and not visual.visible)
	_check(off_one and on_one,
		"P0A-B.23 adopted card is the single visual: unpowered both dark, powered card on and cylinder off",
		"P0A-B.23 visual ownership/power state wrong (card=%s cylinder=%s)" % [
			card.visible, visual.visible if visual != null else false])
	var card_err: float = _angle_deg(card.global_transform.basis.x, dev_axis)
	_check(card_err <= AXIS_TOL_DEG,
		"P0A-B.24 adopted card long axis equals device column 2 (%.6f deg)" % card_err,
		"P0A-B.24 adopted card direction drifted %.6f deg" % card_err)
	host.queue_free()
	await process_frame


func _finish() -> void:
	print("BEAM_GEOMETRY_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)
