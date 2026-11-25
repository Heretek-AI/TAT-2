extends SceneTree
## W9-P2 B1 — room-grade temporal/threshold sweep (diagnostic capture).
##
## STATUS: the 0.49 room grade this probe was built to test was REVERTED after
## the pre-registered W9_SWEEP_VERDICT FAIL in `b1_sweep1.log` (p2-report
## §0.3). The harness is kept as the reproducible instrument for a future,
## separately pre-registered attempt; against the shipped tree the grade is
## absent, both legs are fill-only and the on/off ratio is ~1.0.
##
## The probe answers the integrator's questions with pixels:
##
##   * at every sample along a 20 m walk THROUGH the hall threshold and back,
##     capture the same frame twice -- grade ON and grade OFF -- so the ratio
##     isolates the grade from the scene (geometry, lights, rain);
##   * print mean/p50/%<8 for both, the measured camera multiplier, and the
##     on/off gain ratio;
##   * summary: min/max ratio, the largest adjacent-sample ratio step, and the
##     number of sign changes of the ratio sequence (a pump/oscillation shows
##     up as many sign changes; a smooth ramp has at most one direction change
##     per pass);
##   * fixed controls: the gate approach (multiplier 1.0) and the upper-foyer
##     eye (0.49), so the endpoints are in the same run as the ramp.
##
## Usage (one Godot at a time, under the flock, Xvfb):
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "xvfb-run -a -s '-screen 0 1920x1080x24' tools/godot --path game \
##      --rendering-driver vulkan --script build/qa/w9_room_grade_sweep.gd \
##      -- --tag=sweep1"
##
## Env: W9_SWEEP_Z0 (default -30), W9_SWEEP_Z1 (default -50),
##      W9_SWEEP_STEP (default 0.25), W9_QA_OUT (default build/qa/w9/captures).

const DEFAULT_SIZE := Vector2i(1920, 1080)
const EYE_Y := 29.67
const X := 27.0
const SHIPPED_FOV := 54.54
const GATE_EYE := Vector3(10.0, 24.0, 66.0)
const GATE_TARGET := Vector3(10.0, 25.0, 48.0)
const UPPER_EYE := Vector3(27.0, 29.67, -50.0)
const UPPER_TARGET := Vector3(27.0, 29.67, -60.0)

## PRE-REGISTERED pass criteria (written into p2-report §0.3 BEFORE the run;
## derived from the 4 m feather geometry, not from the observed data).
const C_RATIO_STEP := 0.030      # C1 adjacent on/off ratio step per 0.25 m
const C_GRADE_STEP := 2.0        # C2 adjacent grade-only mean-delta step (luma)
const C_DIR_TOL := 0.005         # C3/C4 direction tolerance on the ratio
const C_REV_RATIO := 0.03        # C5 in/out ratio agreement at matched z
const C_REV_SCENE := 0.03        # C5 in/out off-mean agreement at matched z
const C_BLEED_RMSE := 1.0        # C7 on/off RMSE %, where multiplier == 1
const C_BLEED_AE := 0.1          # C7 on/off differing pixels %, where mult == 1
const C_UPPER_MULT := 0.49       # C8
const C_MID_MIN := 0.70          # C8 threshold midpoint (z=-32, d=2 m)
const C_MID_MAX := 0.79

var _tag: String = "sweep"
var _size: Vector2i = DEFAULT_SIZE
var _z0: float = -30.0
var _z1: float = -50.0
var _step: float = 0.25
var _out: String = ""


func _init() -> void:
	call_deferred("_run")


func _arg(prefix: String, fallback: String) -> String:
	for list: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for arg: String in list:
			if arg.begins_with(prefix):
				return arg.substr(prefix.length()).strip_edges()
	return fallback


func _wait(n: int) -> void:
	for _i: int in range(maxi(n, 1)):
		await process_frame


func _find_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for c: Node in node.get_children():
		var f: WorldEnvironment = _find_env(c)
		if f != null:
			return f
	return null


## L1-pipeline analogue in-engine: gray, 480 px wide, 256-bin histogram.
## Returns the 8-bit gray buffer too, so the on/off pair can be differenced
## pixel-for-pixel (RMSE/AE) and not just compared by mean.
func _gray(img: Image) -> Dictionary:
	var w: int = 480
	var h: int = maxi(1, int(round(float(img.get_height()) * 480.0 / float(img.get_width()))))
	var g: Image = img.duplicate()
	g.convert(Image.FORMAT_RGB8)
	g.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var data: PackedByteArray = PackedByteArray()
	data.resize(w * h)
	for y: int in range(h):
		for x: int in range(w):
			var c: Color = g.get_pixel(x, y)
			data[y * w + x] = clampi(int(round((0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255.0)), 0, 255)
	return {"w": w, "h": h, "data": data}


func _stats(g: Dictionary) -> Dictionary:
	var w: int = int(g.get("w", 480))
	var h: int = int(g.get("h", 270))
	var data: PackedByteArray = g.get("data", PackedByteArray()) as PackedByteArray
	var hist: Array[int] = []
	hist.resize(256)
	hist.fill(0)
	var total: int = 0
	var sum: float = 0.0
	for i: int in range(w * h):
		var l: int = int(data[i])
		hist[l] += 1
		total += 1
		sum += float(l)
	var p50: int = 0
	var acc: int = 0
	for i: int in range(256):
		acc += hist[i]
		if acc * 2 >= total:
			p50 = i
			break
	var below8: int = 0
	for i: int in range(8):
		below8 += hist[i]
	return {
		"mean": sum / float(maxi(total, 1)),
		"p50": p50,
		"lt8": 100.0 * float(below8) / float(maxi(total, 1)),
	}


## RMSE on the 0..255 scale (percent of 255) and the share of differing pixels.
func _diff(g1: Dictionary, g2: Dictionary) -> Dictionary:
	var n: int = mini(int(g1.get("w", 0)) * int(g1.get("h", 0)), int(g2.get("w", 0)) * int(g2.get("h", 0)))
	var d1: PackedByteArray = g1.get("data", PackedByteArray()) as PackedByteArray
	var d2: PackedByteArray = g2.get("data", PackedByteArray()) as PackedByteArray
	if n <= 0 or d1.size() < n or d2.size() < n:
		return {"rmse_pct": 100.0, "ae_pct": 100.0}
	var se: float = 0.0
	var ae: int = 0
	for i: int in range(n):
		var d: int = int(d1[i]) - int(d2[i])
		se += float(d * d)
		if d != 0:
			ae += 1
	return {"rmse_pct": 100.0 * sqrt(se / float(n)) / 255.0, "ae_pct": 100.0 * float(ae) / float(n)}


func _shot(cam: Camera3D) -> Dictionary:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		return {"ok": false}
	return {"ok": true, "img": img}


func _mult(cam: Camera3D) -> float:
	if cam.attributes is CameraAttributesPractical:
		return (cam.attributes as CameraAttributesPractical).exposure_multiplier
	return 1.0


func _pair(cam: Camera3D, pos: Vector3, target: Vector3, tag: String, save_on: bool = false) -> Dictionary:
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.current = true
	# OFF: the mission's _process reads the env each frame, so this is the
	# exact same render path with the grade disabled (not a reimplementation).
	OS.set_environment("TAT2_ROOM_GRADE", "off")
	await _wait(3)
	var off: Dictionary = await _shot(cam)
	# ON: restore the real code path.
	OS.set_environment("TAT2_ROOM_GRADE", "on")
	await _wait(3)
	var mult: float = _mult(cam)
	var on: Dictionary = await _shot(cam)
	if save_on and bool(on.get("ok", false)):
		var img: Image = root.get_texture().get_image()
		if img != null and not img.is_empty():
			img.save_png(_out.path_join("%s_%s.png" % [_tag, tag]))
	if not (bool(off.get("ok", false)) and bool(on.get("ok", false))):
		return {"ok": false, "pos": pos, "mult": mult}
	var g_off: Dictionary = _gray(off.get("img") as Image)
	var g_on: Dictionary = _gray(on.get("img") as Image)
	var os: Dictionary = _stats(g_off)
	var ns: Dictionary = _stats(g_on)
	var diff: Dictionary = _diff(g_off, g_on)
	var ratio: float = 0.0
	if float(os.get("mean", 0.0)) > 0.01:
		ratio = float(ns.get("mean", 0.0)) / float(os.get("mean", 0.0))
	return {
		"pos": pos, "mult": mult, "ratio": ratio,
		"on_mean": float(ns.get("mean", 0.0)), "off_mean": float(os.get("mean", 0.0)),
		"on_p50": int(ns.get("p50", 0)), "off_p50": int(os.get("p50", 0)),
		"on_lt8": float(ns.get("lt8", 0.0)), "off_lt8": float(os.get("lt8", 0.0)),
		"rmse_pct": float(diff.get("rmse_pct", 100.0)), "ae_pct": float(diff.get("ae_pct", 100.0)),
		"ok": true,
	}


func _line(r: Dictionary, i: int, leg: String) -> void:
	var p: Vector3 = r.get("pos", Vector3.ZERO) as Vector3
	print("W9_SWEEP sample=%d leg=%s x=%.2f y=%.2f z=%.2f mult=%.4f ratio=%.4f on_mean=%.2f off_mean=%.2f on_p50=%d off_p50=%d on_lt8=%.1f off_lt8=%.1f rmse=%.4f ae=%.4f ok=%s" % [
		i, leg, p.x, p.y, p.z, float(r.get("mult", 0.0)), float(r.get("ratio", 0.0)),
		float(r.get("on_mean", 0.0)), float(r.get("off_mean", 0.0)),
		int(r.get("on_p50", 0)), int(r.get("off_p50", 0)),
		float(r.get("on_lt8", 0.0)), float(r.get("off_lt8", 0.0)),
		float(r.get("rmse_pct", 100.0)), float(r.get("ae_pct", 100.0)), str(r.get("ok", false)),
	])


func _summary(rows: Array, leg: String) -> void:
	if rows.is_empty():
		printerr("W9_SWEEP FAIL empty leg=", leg)
		return
	var rmin: float = 99.0
	var rmax: float = -1.0
	var max_step: float = 0.0
	var max_step_z: float = 0.0
	var sign_changes: int = 0
	var last_sign: int = 0
	var mmin: float = 9.0
	var mmax: float = -1.0
	var prev: float = -1.0
	for r_var: Variant in rows:
		var r: Dictionary = r_var as Dictionary
		var ratio: float = float(r.get("ratio", 0.0))
		var m: float = float(r.get("mult", 0.0))
		rmin = minf(rmin, ratio)
		rmax = maxf(rmax, ratio)
		mmin = minf(mmin, m)
		mmax = maxf(mmax, m)
		if prev >= 0.0:
			var d: float = ratio - prev
			if absf(d) > max_step:
				max_step = absf(d)
				max_step_z = (r.get("pos", Vector3.ZERO) as Vector3).z
			var s: int = 0 if absf(d) < 0.004 else (1 if d > 0.0 else -1)
			if s != 0:
				if last_sign != 0 and s != last_sign:
					sign_changes += 1
				last_sign = s
		prev = ratio
	print("W9_SWEEP_SUMMARY leg=%s samples=%d ratio_min=%.4f ratio_max=%.4f mult_min=%.4f mult_max=%.4f max_adjacent_step=%.4f at_z=%.2f ratio_sign_changes=%d" % [
		leg, rows.size(), rmin, rmax, mmin, mmax, max_step, max_step_z, sign_changes,
	])


func _verdict(rows_in: Array, rows_out: Array, gate: Dictionary, upper: Dictionary) -> void:
	print("W9_SWEEP_CRITERIA C1_ratio_step<=%.3f C2_grade_step<=%.1f C3_4_dir_tol=%.3f C5_rev_ratio<=%.2f C5_rev_scene<=%.2f C7_rmse<=%.2f C7_ae<=%.2f C8_upper=%.3f C8_mid=[%.2f,%.2f]" % [
		C_RATIO_STEP, C_GRADE_STEP, C_DIR_TOL, C_REV_RATIO, C_REV_SCENE,
		C_BLEED_RMSE, C_BLEED_AE, C_UPPER_MULT, C_MID_MIN, C_MID_MAX,
	])
	var pass_all: bool = true
	# C1 / C2: adjacent steps, both legs.
	var max_rstep: float = 0.0
	var max_gstep: float = 0.0
	for rows: Array in [rows_in, rows_out]:
		for i: int in range(1, rows.size()):
			var a: Dictionary = rows[i - 1] as Dictionary
			var b: Dictionary = rows[i] as Dictionary
			max_rstep = maxf(max_rstep, absf(float(b.get("ratio", 0.0)) - float(a.get("ratio", 0.0))))
			var ga: float = float(a.get("on_mean", 0.0)) - float(a.get("off_mean", 0.0))
			var gb: float = float(b.get("on_mean", 0.0)) - float(b.get("off_mean", 0.0))
			max_gstep = maxf(max_gstep, absf(gb - ga))
	var c1: bool = max_rstep <= C_RATIO_STEP
	var c2: bool = max_gstep <= C_GRADE_STEP
	print("W9_SWEEP_CHECK C1 max_ratio_step=%.4f %s" % [max_rstep, "PASS" if c1 else "FAIL"])
	print("W9_SWEEP_CHECK C2 max_grade_step=%.4f %s" % [max_gstep, "PASS" if c2 else "FAIL"])
	pass_all = pass_all and c1 and c2
	# C3 / C4: direction, with tolerance.
	var c3: bool = true
	var c3_detail: String = ""
	for i: int in range(1, rows_in.size()):
		var a: Dictionary = rows_in[i - 1] as Dictionary
		var b: Dictionary = rows_in[i] as Dictionary
		var d: float = float(b.get("ratio", 0.0)) - float(a.get("ratio", 0.0))
		if d > C_DIR_TOL:
			c3 = false
			c3_detail = " at z=%.2f d=+%.4f" % [(b.get("pos", Vector3.ZERO) as Vector3).z, d]
	var c4: bool = true
	var c4_detail: String = ""
	for i: int in range(1, rows_out.size()):
		var a: Dictionary = rows_out[i - 1] as Dictionary
		var b: Dictionary = rows_out[i] as Dictionary
		var d: float = float(b.get("ratio", 0.0)) - float(a.get("ratio", 0.0))
		if d < -C_DIR_TOL:
			c4 = false
			c4_detail = " at z=%.2f d=%.4f" % [(b.get("pos", Vector3.ZERO) as Vector3).z, d]
	print("W9_SWEEP_CHECK C3 in_monotone=%s%s" % [str(c3), c3_detail])
	print("W9_SWEEP_CHECK C4 out_monotone=%s%s" % [str(c4), c4_detail])
	pass_all = pass_all and c3 and c4
	# C5: reversibility at matched z.
	var c5r: bool = true
	var c5s: bool = true
	var worst_r: float = 0.0
	var worst_s: float = 0.0
	var n_match: int = mini(rows_in.size(), rows_out.size())
	for i: int in range(n_match):
		var a: Dictionary = rows_in[i] as Dictionary
		var b: Dictionary = rows_out[n_match - 1 - i] as Dictionary
		var dr: float = absf(float(a.get("ratio", 0.0)) - float(b.get("ratio", 0.0)))
		var oa: float = float(a.get("off_mean", 0.0))
		var ob: float = float(b.get("off_mean", 0.0))
		var ds: float = absf(oa - ob) / maxf(maxf(oa, ob), 1.0)
		worst_r = maxf(worst_r, dr)
		worst_s = maxf(worst_s, ds)
	c5r = worst_r <= C_REV_RATIO
	c5s = worst_s <= C_REV_SCENE
	print("W9_SWEEP_CHECK C5 reversibility_ratio=%.4f %s scene_drift=%.4f %s" % [
		worst_r, "PASS" if c5r else "FAIL", worst_s, "PASS" if c5s else "FAIL"])
	pass_all = pass_all and c5r and c5s
	# C6: gate multiplier exactly 1.
	var gate_mult: float = float(gate.get("mult", 0.0))
	var c6: bool = absf(gate_mult - 1.0) <= 0.0001
	print("W9_SWEEP_CHECK C6 gate_mult=%.6f %s" % [gate_mult, "PASS" if c6 else "FAIL"])
	pass_all = pass_all and c6
	# C7: no bleed where the multiplier is 1.
	var worst_rmse: float = float(gate.get("rmse_pct", 100.0))
	var worst_ae: float = float(gate.get("ae_pct", 100.0))
	for rows: Array in [rows_in, rows_out]:
		for r_var: Variant in rows:
			var r: Dictionary = r_var as Dictionary
			if float(r.get("mult", 0.0)) >= 0.999:
				worst_rmse = maxf(worst_rmse, float(r.get("rmse_pct", 100.0)))
				worst_ae = maxf(worst_ae, float(r.get("ae_pct", 100.0)))
	var c7: bool = worst_rmse <= C_BLEED_RMSE and worst_ae <= C_BLEED_AE
	print("W9_SWEEP_CHECK C7 bleed_rmse=%.4f bleed_ae=%.4f %s" % [worst_rmse, worst_ae, "PASS" if c7 else "FAIL"])
	pass_all = pass_all and c7
	# C8: analytic scope values.
	var upper_mult: float = float(upper.get("mult", 0.0))
	var mid_mult: float = -1.0
	for r_var: Variant in rows_in:
		var r: Dictionary = r_var as Dictionary
		if absf((r.get("pos", Vector3.ZERO) as Vector3).z - (-32.0)) < 0.13:
			mid_mult = float(r.get("mult", -1.0))
			break
	var c8: bool = absf(upper_mult - C_UPPER_MULT) <= 0.002 and mid_mult >= C_MID_MIN and mid_mult <= C_MID_MAX
	print("W9_SWEEP_CHECK C8 upper_mult=%.4f mid_mult(z=-32)=%.4f %s" % [upper_mult, mid_mult, "PASS" if c8 else "FAIL"])
	pass_all = pass_all and c8
	print("W9_SWEEP_VERDICT %s" % ("PASS" if pass_all else "FAIL"))


func _run() -> void:
	_tag = _arg("--tag=", "sweep")
	_z0 = float(_arg("--z0=", "-30"))
	_z1 = float(_arg("--z1=", "-50"))
	_step = maxf(0.05, float(_arg("--step=", "0.25")))
	var out_env: String = OS.get_environment("W9_QA_OUT").strip_edges()
	if out_env != "":
		_out = out_env
	else:
		_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join("build/qa/w9/captures")
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = _size
	await _wait(3)
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("state", "playing")
		gs.set("thief_id", "spider")
		gs.set("active_contract_order", 4)
		gs.set("active_map_id", "guildhall")
	var mission: Node3D = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(mission)
	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and waited < 2400:
		await process_frame
		waited += 1
	await _wait(40)
	var hud: Node = mission.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(10)
	var wenv: WorldEnvironment = _find_env(mission)
	var env_exposure: float = wenv.environment.tonemap_exposure if wenv != null and wenv.environment != null else -1.0
	print("W9_SWEEP_START tag=%s z0=%.2f z1=%.2f step=%.2f size=%s env_exposure=%.3f out=%s" % [
		_tag, _z0, _z1, _step, str(_size), env_exposure, _out,
	])
	var cam := Camera3D.new()
	cam.name = "W9SweepCamera"
	cam.fov = SHIPPED_FOV
	cam.far = 4000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	mission.add_child(cam)

	# Fixed controls first: gate (mult 1.0) and upper eye (0.49).
	var gate: Dictionary = await _pair(cam, GATE_EYE, GATE_TARGET, "gate", true)
	_line(gate, 0, "gate")
	var upper: Dictionary = await _pair(cam, UPPER_EYE, UPPER_TARGET, "upper", true)
	_line(upper, 1, "upper")
	print("W9_SWEEP_CONTROL gate_on=%.2f gate_off=%.2f gate_ratio=%.4f upper_on=%.2f upper_off=%.2f upper_ratio=%.4f gate_mult=%.4f upper_mult=%.4f" % [
		float(gate.get("on_mean", 0.0)), float(gate.get("off_mean", 0.0)), float(gate.get("ratio", 0.0)),
		float(upper.get("on_mean", 0.0)), float(upper.get("off_mean", 0.0)), float(upper.get("ratio", 0.0)),
		float(gate.get("mult", 0.0)), float(upper.get("mult", 0.0)),
	])

	# Forward: foyer (outside the hall) -> upper eye (inside). Backward after.
	var legs: Dictionary = {}
	for leg: String in ["in", "out"]:
		var rows: Array = []
		var n: int = int(round(absf(_z1 - _z0) / _step)) + 1
		for i: int in range(n):
			var f: float = float(i) / float(maxi(n - 1, 1))
			var z: float = lerpf(_z0, _z1, f)
			if leg == "out":
				z = lerpf(_z1, _z0, f)
			var target: Vector3 = Vector3(X, EYE_Y, z - 10.0)
			var sample_tag: String = "%s_z%03d" % [leg, int(round(z * 10.0))]
			var r: Dictionary = await _pair(cam, Vector3(X, EYE_Y, z), target, sample_tag, i % 8 == 0)
			_line(r, i, leg)
			rows.append(r)
		_summary(rows, leg)
		legs[leg] = rows
	_verdict(legs.get("in", []) as Array, legs.get("out", []) as Array, gate, upper)

	mission.queue_free()
	await _wait(2)
	print("W9_SWEEP_DONE tag=%s" % _tag)
	quit(0)
