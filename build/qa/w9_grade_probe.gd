extends SceneTree
## W9-P1 interior grade calibration probe (diagnostic; NOT a gate capture).
##
## The two L1 poses that miss the KF27 band (upper_foyer, foyer_sweep yaw180)
## are captured once and then re-captured across a bracket of
## `Environment.tonemap_exposure` x `Environment.ambient_light_energy` values,
## mutating the *live* gameplay Environment that mission_controller built. That
## turns a 2-parameter search into one Vulkan run instead of one launch per
## combination, so the calibrated constants are chosen from measured histograms
## rather than guesses.
##
## The numbers this file prints are only a non-black guard (the same sampled
## luma as w9_capture.gd). The authoritative histograms come from
## `python3 build/qa/w9_frame_stats.py <png>` on the saved PNGs.
##
## Usage (one Godot at a time, shared flock, Xvfb):
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "xvfb-run -a -s '-screen 0 1920x1080x24' tools/godot --path game \
##      --rendering-driver vulkan --script build/qa/w9_grade_probe.gd \
##      -- --tag=grade1"
##
## Env:
##   W9_QA_OUT                 output dir (default <repo>/build/qa/w9/captures)
##   W9_GRADE_POSES            comma list of upper_foyer|yaw180|yaw090|yaw270|
##                             foyer|saferoom, default "upper_foyer,yaw180"
##   W9_GRADE_EXPOSURES        comma list, default "0.30,0.40,0.50,0.60"
##   W9_GRADE_AMBIENT_SCALES   comma list of multipliers on the authored ambient,
##                             default "1.0,0.5"
##   W9_GRADE_FILL_SCALES      comma list of energy multipliers on ONLY the two
##                             `GuildhallFoyerFill_*` nodes (W9-P2 B1), default 1.0
##   W9_GRADE_FILL_RANGE_SCALES comma list of range multipliers on the same two
##                             fills (W9-P2 B1), default 1.0
##   W9_GRADE_CAM_MULTS        comma list of `CameraAttributes.exposure_multiplier`
##                             values applied to the probe camera. The 0.49 room
##                             grader this axis was built for was REVERTED after
##                             the W9-P2 pre-registered FAIL; `TAT2_ROOM_GRADE`
##                             no longer exists (the env line in older docs is a
##                             no-op). Kept for a future pre-registered attempt.
##   W9_GRADE_FILLS=off        free the two mission_controller foyer fills before
##                             the bracket (P2-owned fill attribution)
##   TAT2_AO                   inherited (on|off), echoed for provenance

const DEFAULT_SIZE := Vector2i(1920, 1080)
const EYE_OFFSET := 1.67
const SHIPPED_FOV := 54.54
## Pose table: the L1 capture poses (w9_capture.gd) plus the yaw sweep, so one
## bracket run can cover several rooms. `foyer` is the courtyard/gate approach
## (the map's exterior view) and is the regression check for a map-scoped grade.
const POSES := {
	"upper_foyer": [Vector3(27.0, 28.0 + 1.67, -50.0), Vector3(27.0, 29.67, -60.0)],
	"yaw180": [Vector3(27.0, 28.0 + 1.67, -50.0), Vector3(27.0, 29.67, -40.0)],
	"yaw090": [Vector3(27.0, 28.0 + 1.67, -50.0), Vector3(37.0, 29.67, -50.0)],
	"yaw270": [Vector3(27.0, 28.0 + 1.67, -50.0), Vector3(17.0, 29.67, -50.0)],
	"foyer": [Vector3(22.0, 22.17, 125.3), Vector3(22.0, 22.17, 115.3)],
	"saferoom": [Vector3(22.0, 20.5 + 1.67, 128.4), Vector3(22.0, 22.17, 118.4)],
	## Street-side gate approach (KF16/KF18 subject): the authored gate tunnel is
	## (10,20,100)->(10,22,88), the sign plane sits at z 48.35-49.02 and the
	## HERO_LIGHT_POINT is (10,26,49.8). Eye on the wet street looking at the arch.
	"gate": [Vector3(10.0, 24.0, 66.0), Vector3(10.0, 25.0, 48.0)],
}

var _tag: String = "grade"
var _size: Vector2i = DEFAULT_SIZE


func _init() -> void:
	call_deferred("_run")


func _arg(prefix: String, fallback: String) -> String:
	for list: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for arg: String in list:
			if arg.begins_with(prefix):
				return arg.substr(prefix.length()).strip_edges()
	return fallback


func _out_dir() -> String:
	var env: String = OS.get_environment("W9_QA_OUT").strip_edges()
	if env != "":
		return env
	var root_dir: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return root_dir.path_join("build/qa/w9/captures")


func _wait(n: int) -> void:
	for _i: int in range(maxi(n, 1)):
		await process_frame


func _find_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child: Node in node.get_children():
		var found: WorldEnvironment = _find_env(child)
		if found != null:
			return found
	return null


## Sampled ITU-R 601 luma non-black guard (same as w9_capture.gd).
func _sampled_stats(img: Image) -> Dictionary:
	var total: int = 0
	var sum: float = 0.0
	var below8: int = 0
	var peak: float = 0.0
	var step: int = 4
	for y: int in range(0, img.get_height(), step):
		for x: int in range(0, img.get_width(), step):
			var c: Color = img.get_pixel(x, y)
			var l: float = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255.0
			sum += l
			total += 1
			if l < 8.0:
				below8 += 1
			peak = maxf(peak, l)
	if total == 0:
		return {"mean": 0.0, "pct_lt8": 100.0, "peak": 0.0}
	return {"mean": sum / float(total), "pct_lt8": 100.0 * float(below8) / float(total), "peak": peak}


func _save(name: String) -> bool:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		printerr("W9_GRADE FAILED empty image name=", name)
		return false
	var path: String = _out_dir().path_join(name + ".png")
	var err: int = img.save_png(path)
	var st: Dictionary = _sampled_stats(img)
	print("W9_GRADE file=%s err=%d mean601=%.2f pct_lt8=%.1f peak=%.1f" % [
		name, err, float(st.get("mean", 0.0)), float(st.get("pct_lt8", 100.0)), float(st.get("peak", 0.0)),
	])
	return err == OK and float(st.get("peak", 0.0)) > 8.0


func _float_list(raw: String, fallback: Array) -> Array:
	var out: Array = []
	for part: String in raw.split(",", false):
		var p: String = part.strip_edges()
		if p.is_valid_float():
			out.append(float(p))
	return out if not out.is_empty() else fallback


func _free_foyer_fills(mission: Node, which: String = "both") -> int:
	var freed: int = 0
	var stack: Array = [mission]
	while not stack.is_empty():
		var n: Node = stack.pop_back() as Node
		for c: Node in n.get_children():
			stack.append(c)
		if str(n.name).begins_with("GuildhallFoyerFill_"):
			var z: float = (n as Node3D).position.z
			var free_it: bool = which == "both" or (which == "near" and z > -58.0) or (which == "far" and z <= -58.0)
			if free_it:
				n.queue_free()
				freed += 1
	return freed


## W9-P2 B1 calibration: the two P2-owned foyer fills are the measured cause
## of the upper-foyer overshoot (p1-report §0.2). This axis scales their
## energy and/or range in the live scene so one launch can bracket the pair
## instead of one launch per guess. Only nodes named `GuildhallFoyerFill_*`
## are touched; the safe-room fill, authored lights and the preset grade are
## untouched by design (a preset-wide cut is forbidden by the W9-P1 guard).
func _foyer_fill_base(mission: Node) -> Array:
	var out: Array = []
	var stack: Array = [mission]
	while not stack.is_empty():
		var n: Node = stack.pop_back() as Node
		for c: Node in n.get_children():
			stack.append(c)
		if n is OmniLight3D and str(n.name).begins_with("GuildhallFoyerFill_"):
			var o: OmniLight3D = n as OmniLight3D
			out.append([o, o.light_energy, o.omni_range])
	return out


func _apply_fill_scale(base: Array, energy_scale: float, range_scale: float) -> void:
	for row: Array in base:
		var l: OmniLight3D = row[0] as OmniLight3D
		if is_instance_valid(l):
			l.light_energy = float(row[1]) * energy_scale
			l.omni_range = maxf(0.1, float(row[2]) * range_scale)


## Authored-light energies: every light level_loader built carries the
## `tat_ue_intensity` meta, while mission_controller's hand fills, the moon and
## the VFX/guard lights do not. Scaling this set by a constant therefore mirrors
## a post-selection energy factor (selection untouched, hand fills untouched).
## NOTE: only the exposure and ambient axes were captured (grade1/2/3/5/7); the
## light-scale axis is wired but unmeasured, so it must not be quoted.
func _authored_light_base(mission: Node) -> Array:
	var out: Array = []
	var stack: Array = [mission]
	while not stack.is_empty():
		var n: Node = stack.pop_back() as Node
		for c: Node in n.get_children():
			stack.append(c)
		if n is Light3D and n.has_meta("tat_ue_intensity"):
			out.append([n, (n as Light3D).light_energy])
	return out


func _apply_light_scale(base: Array, scale: float) -> void:
	for row: Array in base:
		var l: Light3D = row[0] as Light3D
		if is_instance_valid(l):
			l.light_energy = float(row[1]) * scale


func _run() -> void:
	_tag = _arg("--tag=", "grade")
	var raw_size: String = _arg("--size=", "1920x1080")
	var parts: PackedStringArray = raw_size.to_lower().split("x", false)
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		_size = Vector2i(int(parts[0]), int(parts[1]))
	DirAccess.make_dir_recursive_absolute(_out_dir())
	var exposures: Array = _float_list(OS.get_environment("W9_GRADE_EXPOSURES"), [0.30, 0.40, 0.50, 0.60])
	var amb_scales: Array = _float_list(OS.get_environment("W9_GRADE_AMBIENT_SCALES"), [1.0, 0.5])
	var poses_raw: String = OS.get_environment("W9_GRADE_POSES").strip_edges()
	var light_scales: Array = _float_list(OS.get_environment("W9_GRADE_LIGHT_SCALES"), [1.0])
	## B1 (W9-P2): axes for the two hand-placed foyer fills only.
	var fill_scales: Array = _float_list(OS.get_environment("W9_GRADE_FILL_SCALES"), [1.0])
	var fill_range_scales: Array = _float_list(OS.get_environment("W9_GRADE_FILL_RANGE_SCALES"), [1.0])
	## W9-P2 B1: the implemented lever is `CameraAttributes.exposure_multiplier`
	## on the active camera (mission_controller room grade). Run the probe with
	## TAT2_ROOM_GRADE=off so the mission does not also apply it, then this axis
	## measures the exact render path the game uses. 1.0 = no attributes.
	var cam_mults: Array = _float_list(OS.get_environment("W9_GRADE_CAM_MULTS"), [1.0])
	var poses: Array = []
	for pp: String in (poses_raw if poses_raw != "" else "upper_foyer,yaw180").split(",", false):
		var pname: String = pp.strip_edges()
		if POSES.has(pname):
			poses.append(pname)
		else:
			printerr("W9_GRADE unknown pose=%s (known: %s)" % [pname, str(POSES.keys())])
	if poses.is_empty():
		poses = ["upper_foyer", "yaw180"]
	var fills_raw: String = OS.get_environment("W9_GRADE_FILLS").strip_edges().to_lower()
	## "off"/"both" = free both fills; "near"/"far" = free only that one (B1).
	var fills_mode: String = ""
	if fills_raw in ["off", "both", "near", "far"]:
		fills_mode = "both" if fills_raw == "off" else fills_raw
	var fills_off: bool = fills_mode != ""
	print("W9_GRADE_START tag=%s size=%s exposures=%s ambient_scales=%s light_scales=%s fill_scales=%s fill_range_scales=%s cam_mults=%s poses=%s fills=%s ao=%s out=%s" % [
		_tag, str(_size), str(exposures), str(amb_scales), str(light_scales),
		str(fill_scales), str(fill_range_scales), str(cam_mults), str(poses),
		"off" if fills_off else "on",
		OS.get_environment("TAT2_AO"), _out_dir(),
	])

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
	while (mission.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and waited < 1800:
		await process_frame
		waited += 1
	await _wait(40)
	var hud: Node = mission.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(10)
	var wenv: WorldEnvironment = _find_env(mission)
	if wenv == null or wenv.environment == null:
		printerr("W9_GRADE missing WorldEnvironment")
		quit(1)
		return
	var env: Environment = wenv.environment
	var base_exposure: float = env.tonemap_exposure
	var base_ambient: float = env.ambient_light_energy
	print("W9_GRADE base tonemap=%d exposure=%.3f ambient=%.3f glow=%.3f ssil=%s ssao=%s" % [
		env.tonemap_mode, base_exposure, base_ambient, env.glow_intensity,
		str(env.ssil_enabled), str(env.ssao_enabled),
	])
	if fills_off:
		var freed: int = _free_foyer_fills(mission, fills_mode)
		await _wait(12)
		print("W9_GRADE fills freed=%d mode=%s" % [freed, fills_mode])
	var authored_lights: Array = _authored_light_base(mission)
	var foyer_fills: Array = _foyer_fill_base(mission)
	print("W9_GRADE authored_lights=%d (tat_ue_intensity meta, the set level_loader scales) foyer_fills=%d" % [authored_lights.size(), foyer_fills.size()])

	var cam: Camera3D = Camera3D.new()
	cam.name = "W9GradeCamera"
	cam.fov = SHIPPED_FOV
	cam.far = 4000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	mission.add_child(cam)
	cam.current = true
	var cam_attrs: CameraAttributesPractical = null

	var ok_all: bool = true
	for pose: String in poses:
		var pair: Array = POSES[pose] as Array
		cam.global_position = pair[0] as Vector3
		cam.look_at(pair[1] as Vector3, Vector3.UP)
		for scale: float in amb_scales:
			for lscale: float in light_scales:
				for fscale: float in fill_scales:
					for rscale: float in fill_range_scales:
						for cm: float in cam_mults:
							if is_equal_approx(cm, 1.0):
								cam.attributes = null
							else:
								if cam_attrs == null:
									cam_attrs = CameraAttributesPractical.new()
									cam_attrs.auto_exposure_enabled = false
								cam_attrs.exposure_multiplier = cm
								cam.attributes = cam_attrs
							for expo: float in exposures:
								env.tonemap_exposure = expo
								env.ambient_light_energy = base_ambient * scale
								_apply_light_scale(authored_lights, lscale)
								_apply_fill_scale(foyer_fills, fscale, rscale)
								await _wait(10)
								print("W9_GRADE shot pose=%s exposure=%.3f ambient=%.3f (ambient_scale=%.2f) light_scale=%.2f fill_scale=%.2f fill_range_scale=%.2f cam_mult=%.3f" % [
									pose, env.tonemap_exposure, env.ambient_light_energy, scale, lscale, fscale, rscale, cm,
								])
								var fill_tag: String = ""
								if not is_equal_approx(fscale, 1.0) or not is_equal_approx(rscale, 1.0):
									fill_tag = "_f%03d_r%03d" % [int(round(fscale * 100.0)), int(round(rscale * 100.0))]
								var cam_tag: String = "" if is_equal_approx(cm, 1.0) else "_c%03d" % int(round(cm * 100.0))
								ok_all = await _save("%s_%s_e%03d_a%03d_l%03d%s%s%s" % [
									_tag, pose, int(round(expo * 100.0)), int(round(scale * 100.0)),
									int(round(lscale * 100.0)), fill_tag, cam_tag,
									("_nofill_" + fills_mode) if fills_off else "",
								]) and ok_all
	# Restore the live grade so a later diagnostic in the same run is not polluted.
	cam.attributes = null
	env.tonemap_exposure = base_exposure
	env.ambient_light_energy = base_ambient
	_apply_light_scale(authored_lights, 1.0)
	_apply_fill_scale(foyer_fills, 1.0, 1.0)
	print("W9_GRADE_DONE tag=%s ok=%s" % [_tag, str(ok_all)])
	quit(0 if ok_all else 1)
