extends SceneTree
## W0R standalone headless beam-geometry truth test.
##
## Guildhall_Gameplay has 134 authored SM_LightBeam cards, one per
## BP_Detector_LightBeam_C. The UE StaticMesh is 10.2 cm long on its local X
## (Bounds X -0.1..10.1 cm) and 1.0008 m wide on Y/Z; the blueprint reaches the
## authored span with LightBeam_Root RelativeScale3D.X = 24.5..195.5291. The
## .tatlevel record carries that length scale in scale[2] and a basis whose
## col0 is the actor-local Z beam direction.
##
## The generic loader path applied scale[2] to basis col2 (a 1 m width axis)
## and clamped every axis at 40 m: 129/134 cards rendered as a 40 m ribbon
## 90 deg off the beam. level_loader.beam_card_transform() moves the scale onto
## col0 and lifts the ceiling to 200.
##
## This test asserts, for all 134 records:
##   * world length == BeamLength_m within 2 % (0.102 m authored card axis);
##   * direction == the record's col0 (and the device record's actor-local Z)
##     within 1 deg;
##   * the applied scale is never clamped (max authored 195.5291 <= 200);
##   * the runtime security_beam.gd capsule/visual use the same actor-local +Z;
##   * exactly one visual per detector once an authored card is adopted.
## A negative control rebuilds the old col2 + 40 m clamp transform and proves
## it fails the same length/direction assertions for every card.
##
## Run:
##   XDG_DATA_HOME=... tools/godot --headless --path game \
##     --script res://tests/test_beam_geometry.gd

const LEVEL_PATH := "res://data/generated/levels/Guildhall/Guildhall_Gameplay.tatlevel.json"
const DEVICES_PATH := "res://data/generated/gameplay/devices_runtime.json"
const BEAM_MESH := "/Game/Art/Effects/LightBeam/SM_LightBeam"
## Authored UE StaticMesh bounds (X -0.1..10.1 cm). The imported GLB is 0.1 m
## long (2 % short), so the authored axis is used for the authoring check and
## the GLB shortfall is reported, not silently folded into the tolerance.
const BEAM_CARD_AXIS_M: float = 0.102
const LEN_TOL: float = 0.02
const ANG_TOL_DEG: float = 1.0
const OLD_CLAMP_M: float = 40.0
const BEAM_SCALE_CEIL: float = 200.0
const SAMPLE_IDS: Array[String] = [
	"guildhall/Guildhall_Gameplay:BP_Detector_LightBeam_C_0",
	"guildhall/Guildhall_Gameplay:BP_Detector_LightBeam_C_1",
	"guildhall/Guildhall_Gameplay:BP_Detector_LightBeam_C_134",
]

var fails: int = 0


func _check(cond: bool, ok_msg: String, fail_msg: String) -> void:
	if cond:
		print("PASS: ", ok_msg)
	else:
		printerr("FAIL: ", fail_msg)
		fails += 1


## .tatlevel stores the rotation row-major; the loader builds a Godot Basis
## whose columns are those rows (Basis(col0, col1, col2)).
func _basis_from_record(b: Array) -> Basis:
	return Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	)


func _pos_key(p: Array) -> String:
	return "%.3f,%.3f,%.3f" % [float(p[0]), float(p[1]), float(p[2])]


func _angle_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


## The exact pre-W0R behaviour: every axis clamped at 40 m, scale left on the
## record's col2 (a 1 m width axis), card long axis never scaled.
func _old_transform(rec: Dictionary) -> Transform3D:
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
	var level_text: String = FileAccess.get_file_as_string(LEVEL_PATH)
	var dev_text: String = FileAccess.get_file_as_string(DEVICES_PATH)
	var level_doc: Variant = JSON.parse_string(level_text)
	var dev_doc: Variant = JSON.parse_string(dev_text)
	if not (level_doc is Dictionary) or not (dev_doc is Dictionary):
		_check(false, "", "W0R.0 could not parse %s / %s" % [LEVEL_PATH, DEVICES_PATH])
		_finish()
		return

	var cards: Array = []
	for m_v: Variant in ((level_doc as Dictionary).get("meshes", []) as Array):
		if m_v is Dictionary and str((m_v as Dictionary).get("mesh", "")) == BEAM_MESH:
			cards.append(m_v)
	var cards_by_pos: Dictionary = {}
	for c_v: Variant in cards:
		cards_by_pos[_pos_key((c_v as Dictionary).get("pos", [0, 0, 0]))] = c_v

	var maps: Dictionary = (dev_doc as Dictionary).get("maps", {}) as Dictionary
	var guildhall: Dictionary = maps.get("guildhall", {}) as Dictionary
	var devices: Array = guildhall.get("devices", []) as Array
	var dev_by_pos: Dictionary = {}
	var beam_devices: int = 0
	for d_v: Variant in devices:
		if d_v is Dictionary and str((d_v as Dictionary).get("family", "")) == "light_beam":
			beam_devices += 1
			dev_by_pos[_pos_key((d_v as Dictionary).get("pos", [0, 0, 0]))] = d_v
	var defaults: Dictionary = ((dev_doc as Dictionary).get("stats", {}) as Dictionary).get("family_defaults", {}) as Dictionary

	_check(cards.size() == 134, "W0R.1 Guildhall_Gameplay has 134 %s cards" % BEAM_MESH,
		"W0R.1 expected 134 cards, got %d" % cards.size())
	_check(beam_devices == 134, "W0R.1b devices_runtime has 134 light_beam records",
		"W0R.1b expected 134 light_beam devices, got %d" % beam_devices)

	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	var ll: Node = ll_scr.new()
	var helper_ok: bool = ll_scr.beam_card_transform(cards[0]) is Transform3D
	_check(helper_ok, "W0R.2 level_loader.beam_card_transform() returns a Transform3D",
		"W0R.2 beam_card_transform() helper missing/broken")

	var len_bad: int = 0
	var ang_bad: int = 0
	var clamp_bad: int = 0
	var width_bad: int = 0
	var unmatched: int = 0
	var max_scale: float = 0.0
	var max_len_err: float = 0.0
	var max_ang: float = 0.0
	var sample: Array[String] = []
	# Negative control counters (the old axis + clamp must fail).
	var old_len_pass: int = 0
	var old_dir_pass: int = 0
	var old_clamped: int = 0

	for card_v: Variant in cards:
		var rec: Dictionary = card_v as Dictionary
		var dev: Dictionary = dev_by_pos.get(_pos_key(rec.get("pos", [0, 0, 0])), {}) as Dictionary
		if dev.is_empty():
			unmatched += 1
			continue
		var tr: Transform3D = ll_scr.beam_card_transform(rec)
		var dir: Vector3 = tr.basis.x.normalized()
		var rec_col0: Vector3 = _basis_from_record(rec.get("basis", [])).x.normalized()
		var dev_col2: Vector3 = _basis_from_record(dev.get("basis", [])).z.normalized()
		var s: Array = rec.get("scale", [1, 1, 1])
		var s_auth: float = maxf(float(s[0]), float(s[2]))
		max_scale = maxf(max_scale, s_auth)

		var length_m: float = tr.basis.x.length() * BEAM_CARD_AXIS_M
		var auth_v: Variant = (dev.get("params", {}) as Dictionary).get("BeamLength")
		var auth_m: float = (float(auth_v) / 100.0) if auth_v != null else 10.0
		var err: float = absf(length_m - auth_m) / auth_m
		max_len_err = maxf(max_len_err, err)
		if err > LEN_TOL:
			len_bad += 1

		var ang: float = _angle_deg(dir, rec_col0)
		max_ang = maxf(max_ang, ang)
		if ang > ANG_TOL_DEG:
			ang_bad += 1
		# The record col0 is the device record's actor-local Z (the authored
		# runtime axis): 90 deg away from the actor-local +X the old code used.
		if _angle_deg(dir, dev_col2) > ANG_TOL_DEG:
			ang_bad += 1

		# No clamp: applied length scale is the authored one, ceiling 200.
		if not is_equal_approx(tr.basis.x.length(), s_auth) or s_auth > BEAM_SCALE_CEIL:
			clamp_bad += 1
		# Y/Z stay the authored 1 m cross width.
		if absf(tr.basis.y.length() - 1.0) > 0.0001 or absf(tr.basis.z.length() - 1.0) > 0.0001:
			width_bad += 1

		# Negative control: the old transform must fail length and direction.
		var old: Transform3D = _old_transform(rec)
		var old_run: float = old.basis.z.length()          # scaled 1 m width axis
		var old_err: float = absf(old_run - auth_m) / auth_m
		if old_err <= LEN_TOL:
			old_len_pass += 1
		if _angle_deg(old.basis.z.normalized(), rec_col0) <= ANG_TOL_DEG:
			old_dir_pass += 1
		if float(s[2]) > OLD_CLAMP_M:
			old_clamped += 1
		if SAMPLE_IDS.has(str(dev.get("id", ""))):
			sample.append("%s len=%.4f m (auth %.4f, err %.3f%%) dir=%s scale=%.4f old_ribbon=%.2f m" % [
				str(dev.get("id", "")).get_file(), length_m, auth_m, err * 100.0,
				str(dir), s_auth, old_run])

	_check(unmatched == 0, "W0R.3 134/134 cards pair with their detector record by authored position",
		"W0R.3 %d cards have no matching light_beam device" % unmatched)
	_check(len_bad == 0,
		"W0R.4 134/134 world lengths match BeamLength_m within 2%% (max err %.3f%%)" % (max_len_err * 100.0),
		"W0R.4 %d/134 lengths outside 2%% (max err %.3f%%)" % [len_bad, max_len_err * 100.0])
	_check(ang_bad == 0,
		"W0R.5 134/134 directions equal the record col0 / actor-local Z within 1 deg (max %.4f deg)" % max_ang,
		"W0R.5 %d direction checks outside 1 deg (max %.4f deg)" % [ang_bad, max_ang])
	_check(clamp_bad == 0,
		"W0R.6 134/134 applied scales are unclamped; max authored scale %.4f (ceiling %.0f)" % [max_scale, BEAM_SCALE_CEIL],
		"W0R.6 %d cards clamped or over the 200 ceiling (max authored %.4f)" % [clamp_bad, max_scale])
	_check(width_bad == 0, "W0R.7 134/134 cards keep the authored 1 m cross width (Y/Z scale 1)",
		"W0R.7 %d cards changed a width axis" % width_bad)
	_check(is_equal_approx(max_scale, 195.5291) and max_scale > OLD_CLAMP_M,
		"W0R.8 authored max scale is 195.5291 (19.55 m), above the old 40 m clamp",
		"W0R.8 unexpected max scale %.4f" % max_scale)
	for line: String in sample:
		print("  sample: ", line)

	# The loader's own transform path (counters + BEAM_FIX evidence) delegates.
	var delegate_ok: bool = true
	for card_v2: Variant in cards:
		var rec2: Dictionary = card_v2 as Dictionary
		var via_loader: Transform3D = ll.call("_dict_to_transform", rec2)
		var pure: Transform3D = ll_scr.beam_card_transform(rec2)
		if not via_loader.is_equal_approx(pure):
			delegate_ok = false
			break
	_check(delegate_ok, "W0R.9 _dict_to_transform delegates the exact SM_LightBeam path to beam_card_transform()",
		"W0R.9 _dict_to_transform disagrees with beam_card_transform() for a beam record")
	_check(int(ll.get("_beam_fix_count")) == 134,
		"W0R.10 loader applied the beam fix 134 times (BEAM_FIX count)",
		"W0R.10 loader beam fix count %d != 134" % int(ll.get("_beam_fix_count")))
	_check(absf(float(ll.get("_beam_fix_max_scale")) - 195.5291) < 0.0001,
		"W0R.10b loader BEAM_FIX max scale 195.5291",
		"W0R.10b loader max scale %.4f != 195.5291" % float(ll.get("_beam_fix_max_scale")))

	# Negative control (old scale-on-col2 + 40 m clamp): every card must fail.
	_check(old_len_pass == 0,
		"W0R.11 negative control: old col2+40 m transform fails length for 134/134 cards",
		"W0R.11 %d cards would still pass the old length check" % old_len_pass)
	_check(old_dir_pass == 0,
		"W0R.12 negative control: old transform axis is 90 deg off col0 for 134/134 cards",
		"W0R.12 %d cards would still pass the old direction check" % old_dir_pass)
	_check(old_clamped == 129,
		"W0R.13 negative control: the old 40 m clamp clipped exactly 129/134 cards",
		"W0R.13 expected 129 clipped by the old clamp, got %d" % old_clamped)

	# Runtime security_beam.gd: capsule/visual along actor-local +Z, one visual.
	await _test_runtime_beam(dev_by_pos, cards_by_pos, defaults)

	ll.free()
	_finish()


func _test_runtime_beam(dev_by_pos: Dictionary, cards_by_pos: Dictionary, defaults: Dictionary) -> void:
	var sample_id: String = SAMPLE_IDS[0]
	var dev: Dictionary = {}
	var card_rec: Dictionary = {}
	for d_v: Variant in dev_by_pos.values():
		if str((d_v as Dictionary).get("id", "")) == sample_id:
			dev = d_v as Dictionary
			break
	if dev.is_empty():
		_check(false, "", "W0R.14 sample detector C_0 missing")
		return
	card_rec = cards_by_pos.get(_pos_key(dev.get("pos", [0, 0, 0])), {}) as Dictionary
	if card_rec.is_empty():
		_check(false, "", "W0R.14b sample card C_0 missing")
		return

	var beam_scr: GDScript = load("res://src/devices/security_beam.gd") as GDScript
	var host := Node3D.new()
	root.add_child(host)
	var beam: Area3D = beam_scr.new() as Area3D
	host.add_child(beam)
	beam.call("configure", dev, defaults, 2)
	var device_basis: Basis = _basis_from_record(dev.get("basis", []))
	beam.global_transform = Transform3D(device_basis, Vector3.ZERO)
	var pivot: Node3D = beam.get_node_or_null("BeamPivot") as Node3D
	var shape: CollisionShape3D = beam.get_node_or_null("BeamPivot/BeamShape") as CollisionShape3D
	var visual: MeshInstance3D = beam.get_node_or_null("BeamPivot/BeamVisual") as MeshInstance3D
	var rec_col0: Vector3 = _basis_from_record(dev.get("basis", [])).z.normalized()
	var dir_ok: bool = pivot != null and _angle_deg(pivot.global_transform.basis.z, rec_col0) <= ANG_TOL_DEG
	_check(dir_ok, "W0R.14 runtime beam pivot +Z equals the authored actor-local Z (%.3f deg)" %
		(_angle_deg(pivot.global_transform.basis.z, rec_col0) if pivot != null else -1.0),
		"W0R.14 runtime beam direction is not actor-local +Z")
	var beam_len: float = float(beam.get("beam_length_m"))
	var cap_ok: bool = shape != null and shape.shape is CapsuleShape3D \
		and absf(shape.position.z - beam_len * 0.5) < 0.001 \
		and absf(shape.rotation.x - PI * 0.5) < 0.0001 \
		and absf(shape.position.x) < 0.0001
	_check(cap_ok, "W0R.15 runtime capsule runs along +Z (centre %.3f, rot X %.3f)" % [
		shape.position.z if shape != null else -1.0, shape.rotation.x if shape != null else -1.0],
		"W0R.15 runtime capsule not rotated onto +Z")
	var vis_ok: bool = visual != null and absf(visual.position.z - beam_len * 0.5) < 0.001 \
		and absf(visual.rotation.x - PI * 0.5) < 0.0001
	_check(vis_ok, "W0R.16 stand-in visual fallback also runs along +Z",
		"W0R.16 stand-in visual not rotated onto +Z")

	# Card adoption: exactly one visual, and it follows power state.
	var card := Node3D.new()
	card.name = "BeamCard"
	host.add_child(card)
	var ll_scr: GDScript = load("res://src/core/level_loader.gd") as GDScript
	card.global_transform = ll_scr.beam_card_transform(card_rec)
	beam.call("adopt_beam_card", card)
	beam.call("_on_power_changed", false)
	var off_one: bool = (not card.visible) and (visual != null and not visual.visible)
	beam.call("_on_power_changed", true)
	var on_one: bool = card.visible and (visual != null and not visual.visible)
	_check(off_one and on_one,
		"W0R.17 adopted card is the single visual: unpowered both dark, powered card on and cylinder off",
		"W0R.17 visual ownership/power state wrong (card=%s cylinder=%s)" % [
			card.visible, visual.visible if visual != null else false])
	var card_dir: Vector3 = card.global_transform.basis.x.normalized()
	var card_ok: bool = _angle_deg(card_dir, rec_col0) <= ANG_TOL_DEG
	_check(card_ok, "W0R.18 adopted card keeps the authored col0 direction after adoption",
		"W0R.18 adopted card direction drifted %.3f deg" % _angle_deg(card_dir, rec_col0))
	host.queue_free()
	await process_frame


func _finish() -> void:
	print("BEAM_GEOMETRY_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)
