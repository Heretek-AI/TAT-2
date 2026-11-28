extends SceneTree
## P0b Lane I — fixed-pose Vulkan capture + Master-bus audio tap (port side).
##
## Tracked source; PNG/WAV/PCM output is gitignored. The tracked artifact is the
## manifest under docs/reports/logs/p0b/<run_id>/manifest.json (HEAD, seed, GPU,
## pose, lens, settle, audio state). A dry-run manifest is committed as the
## schema proof; the actual GPU capture is run by the integrator after the
## harness/governance lanes merge.
##
## Usage (never two GPU jobs at once; the wrapper takes the shared flock):
##   build/qa/p0b_capture.sh                       # real capture, every pose
##   build/qa/p0b_capture.sh --beam-card=off       # TAT2_BEAM_CARD A/B
##   build/qa/p0b_capture.sh --poses=lounge_beam,beam_close
##   build/qa/p0b_capture.sh --settle-seconds=25   # extra >=25 s hold after the frames
##   build/qa/p0b_capture.sh --dry-run             # headless, no GPU, manifest only
##   build/qa/p0b_capture.sh --self-test           # headless checks
##
## Direct (the wrapper is preferred):
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "xvfb-run -a -s '-screen 0 1920x1080x24' tools/godot --path game \
##      --rendering-driver vulkan --script '$PWD/build/qa/p0b_capture.gd' -- --mode=capture"
##
## Poses: gate, upper_foyer, yaw180, foyer_beam, foyer_beam_wide, lounge,
## lounge_beam, beam_close, gap_view.
## `foyer_beam` is the KF27-framed cue at the authored C_107 foyer card;
## `foyer_beam_wide` is the lateral KF27 framing of the same authored terms (the
## card projects at ~18 %/40 % from ~8 m, the reference emitter box);
## `gap_view` is the authored SafeRoomPlayerStart landscape-gap view with a
## labelled PORT_DECISION pitch, and `beam_close` is the Lounge C_57 extra
## (ref=EXTRA), never a KF27 frame.
## Lens: the shipped authored 54.54 deg vertical (UE 85 deg horizontal at 16:9),
## 1920x1080, KEEP_HEIGHT. Each pose waits SETTLE_FRAMES=60, then captures
## CAPTURE_FRAMES=5 frames and saves the median-mean frame; an optional
## `--settle-seconds=N` (0 or >=25) adds a further N-second hold after those
## frames for the AEM/A-B sessions. The authoritative luma percentiles/beam
## rows/16x9 cream map come from
## build/qa/p0b_roi_stats.py on the saved PNG; the sampled numbers printed here
## are only a non-black guard and the median selector.
##
## TAT2_BEAM_CARD=off is a *capture-side* A/B: level_loader.gd has no such env
## flag, so the harness hides the `lightbeam_cards` group at runtime after the
## mission loads. It never edits the beam fix, scale or material. The manifest
## records the mode and how many cards were hidden.

const SCHEMA: String = "tat2.p0b_capture/1"
const SIZE := Vector2i(1920, 1080)
const SHIPPED_FOV: float = 54.54
const EYE_OFFSET: float = 1.67
const SETTLE_FRAMES: int = 60
const CAPTURE_FRAMES: int = 5
## A requested `--settle-seconds` must be 0 (off) or at least this many seconds;
## the AEM/A-B sessions use 25 s. It is an *extra* hold after SETTLE_FRAMES.
const MIN_SETTLE_SECONDS: float = 25.0
## Authored STAND_HEAD_HEIGHT (thief_character.gd: 1.66875 m above the floor).
const PLAYER_EYE_HEIGHT: float = 1.66875
const OFFICIAL_CLIP_SEED: int = 1025051536
const AUDIO_SRC: String = "res://src/core/audio_capture.gd"
const POSE_IDS: Array[String] = ["gate", "upper_foyer", "yaw180", "foyer_beam", "foyer_beam_wide", "lounge", "lounge_beam", "beam_close", "gap_view"]

## Pose table. `ground=false` uses the authored absolute eye (the W9 capture
## poses); `ground=true` casts a downward ray at the authored x/z and places the
## eye at hit.y + 1.67, so a floor-height mismatch cannot silently float a pose.
## Lounge geometry: POI floor bbox [20,24,-46]-[52,32,-5]; guard marker C_20 at
## (43.7149, 27.05, -26.2188); BP_Detector_LightBeam_C_57 beam card at
## (42.3362, 28.9, -28.9669) along Z (267.29 cm authored BeamLength).
const POSES := {
	"gate": {
		"eye": Vector3(10.0, 24.0, 66.0),
		"target": Vector3(10.0, 25.0, 48.0),
		"ground": false,
		"beat": "S13",
		"ref": "KF16",
		"note": "street-side gate approach (W9 grade-probe pose); reference KF16 is the gate/headlights keyframe",
	},
	"upper_foyer": {
		"eye": Vector3(27.0, 28.0 + 1.67, -50.0),
		"target": Vector3(27.0, 29.67, -60.0),
		"ground": false,
		"beat": "S24",
		"ref": "KF27",
		"note": "authored upper-foyer slot looking into the hall; KF27 is the foyer security-beam keyframe",
	},
	"yaw180": {
		"eye": Vector3(27.0, 28.0 + 1.67, -50.0),
		"target": Vector3(27.0, 29.67, -40.0),
		"ground": false,
		"beat": "S24",
		"ref": "KF27",
		"note": "same slot turned 180 deg; W9-P1 showed the armchair/ottoman/vitrine from here",
	},
	"foyer_beam": {
		"eye": Vector3(27.0, 29.67, -55.0),
		"target": Vector3(23.27, 29.76, -57.4),
		"ground": false,
		"beat": "S24",
		"ref": "KF27",
		"note": "KF27-framed cue aimed at the authored BP_Detector_LightBeam_C_107 card at (23.27,29.76,-57.4); the one-band/emitter criteria are in build/qa/kf27_beam_reference.json",
	},
	"foyer_beam_wide": {
		# Derived, not authored: eye = card + 8 m * (-0.766, 0, 0.643)
		#   (23.27 - 6.128, 29.76, -57.4 + 5.144) = (17.1, 29.7, -52.3).
		# Looking 30.26 deg right / 5.81 deg down of the eye->card ray puts the
		# authored card centre at 18.0 %/40.0 % of a 54.54 deg KEEP_HEIGHT 16:9
		# frame (the KF27 reference emitter is 17.8 %/40.0 %, +-2 %). Same
		# authored terms as foyer_beam; only the lateral framing changes.
		"eye": Vector3(17.1, 29.7, -52.3),
		"target": Vector3(24.96, 28.95, -53.59),
		"ground": false,
		"beat": "S24",
		"ref": "KF27",
		"note": "lateral KF27 wide cue: 8.005 m from the authored C_107 card; the derived target rotates the eye->card ray +30.26 deg yaw / -5.81 deg pitch so the emitter projects at 18.0 %/40.0 % (inside the 10-26 % x / 33-47 % y emitter box). foyer_beam is untouched.",
	},
	"lounge": {
		"eye": Vector3(31.0, 28.72, -26.2),
		"target": Vector3(44.2, 28.72, -26.2),
		"ground": true,
		"beat": "S24",
		"ref": "KF27",
		"note": "Lounge wide view toward guard marker C_20; the C_57 beam crosses the left half",
	},
	"lounge_beam": {
		"eye": Vector3(34.0, 28.72, -28.97),
		"target": Vector3(42.4, 28.9, -28.97),
		"ground": true,
		"beat": "S24",
		"ref": "KF27",
		"note": "head-on to the C_57 beam card (x=42.34, y=28.9, z=-28.97); the beam runs along Z so it crosses the frame",
	},
	"beam_close": {
		"eye": Vector3(39.0, 28.82, -28.97),
		"target": Vector3(42.4, 28.9, -28.97),
		"ground": true,
		"beat": "",
		"ref": "EXTRA",
		"note": "Lounge C_57 extra (not KF27/S24): 3.4 m from the C_57 card; luma stats only, no KF27 criteria",
	},
	"gap_view": {
		# Anchored to the authored TATSafeRoomPlayerStart_0 at
		# (127.2747, 25.4694, -5.3296); the eye adds the authored player eye
		# height (STAND_HEAD_HEIGHT = 1.66875) so it is a first-person view from
		# the start, not the actor origin. The target is the EXACT authored
		# landscape-gap centroid (120.25, 18.56, -6.815) = the midpoint of the
		# measured (114.5, 18.56, -3.2) / (126.0, 18.56, -10.43) collision
		# points, so the aim is exact (0.00 % offset; well inside 1 %). The
		# derived pitch is -50.0702 deg. The -48.6 deg figure needs a 26.7041 m
		# eye (start + 1.2347); with the +1.66875 first-person eye the pitch is
		# -50.07 deg, still inside the spec's -42..-53 deg band. The pitch is
		# NOT authored -> PORT_DECISION.
		"eye": Vector3(127.2747, 27.13815, -5.3296),
		"target": Vector3(120.25, 18.56, -6.815),
		"ground": false,
		"beat": "S12",
		"ref": "EXTRA",
		"decision": "PORT_DECISION",
		"authored_start": Vector3(127.2747, 25.4694, -5.3296),
		"note": "landscape-gap A/B view for the P4.4 discard|raw|off comparison: eye = authored SafeRoomPlayerStart_0 x/z + player eye height (1.66875), target = exact authored gap centroid (120.25,18.56,-6.815), so the aim is exact (0.00 % offset). Derived pitch -50.0702 deg (the -48.6 deg figure would need a 26.7041 m eye); labelled PORT_DECISION (no authored camera aims at the gap).",
	},
}

var _mode: String = "capture"
var _tag: String = ""
var _poses: Array[String] = []
var _beam_mode: String = "on"
var _seed_arg: String = "derived"
var _settle_seconds: float = 0.0
var _run_id: String = ""
var _out_dir: String = ""
var _manifest_path: String = ""
var _repo_root: String = ""
var _checks: int = 0
var _fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _arg(prefix: String, fallback: String) -> String:
	for list: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for arg: String in list:
			if arg.begins_with(prefix):
				return arg.substr(prefix.length()).strip_edges()
	return fallback


func _env(name: String) -> String:
	return OS.get_environment(name).strip_edges()


func _wait(n: int) -> void:
	for _i: int in range(maxi(n, 1)):
		await process_frame


## Parse `--settle-seconds`: "" -> 0 (off), a non-negative number -> that value,
## anything else -> -1. The 0-or->=25 contract is enforced separately by
## _settle_ok so the parser stays a pure value reader.
func _parse_settle_seconds(raw: String) -> float:
	var s: String = raw.strip_edges()
	if s == "":
		return 0.0
	if not s.is_valid_float():
		return -1.0
	var v: float = s.to_float()
	if v < 0.0:
		return -1.0
	return v


func _settle_ok(v: float) -> bool:
	return v == 0.0 or (v >= MIN_SETTLE_SECONDS and v <= 3600.0)


## Gnomonic projection of `point` for a Camera3D at `eye` looking at `target`
## with the shipped vertical FOV and KEEP_HEIGHT=height. Returns the image
## percentage from the top-left (x right, y down). Used only by the self-test to
## prove the derived poses' framing arithmetic mirrors Godot's camera.
func _project_pct(eye: Vector3, target: Vector3, point: Vector3) -> Vector2:
	var fwd: Vector3 = (target - eye).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(fwd)
	var v: Vector3 = point - eye
	var depth: float = v.dot(fwd)
	if absf(depth) < 1e-6:
		return Vector2(-1.0, -1.0)
	var tan_h: float = tan(deg_to_rad(SHIPPED_FOV * 0.5))
	var x_ndc: float = (v.dot(right) / depth) / (tan_h * (16.0 / 9.0))
	var y_ndc: float = (v.dot(up) / depth) / tan_h
	return Vector2(50.0 * (x_ndc + 1.0), 50.0 * (1.0 - y_ndc))


func _pitch_deg(eye: Vector3, target: Vector3) -> float:
	var d: Vector3 = target - eye
	return rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))


## Hold the pose: SETTLE_FRAMES first, then an *additional* `_settle_seconds`
## wall-clock hold when requested. Returns the total waited milliseconds so the
## manifest can prove the flag was not a no-op.
func _wait_settle() -> int:
	var t0: int = Time.get_ticks_msec()
	await _wait(SETTLE_FRAMES)
	if _settle_seconds > 0.0:
		var deadline: int = Time.get_ticks_msec() + int(round(_settle_seconds * 1000.0))
		while Time.get_ticks_msec() < deadline:
			await process_frame
	return Time.get_ticks_msec() - t0


func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true)


func _stamp() -> String:
	return _now_iso().replace("-", "").replace(":", "") + "Z"


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _rel(path: String) -> String:
	if _repo_root != "" and path.begins_with(_repo_root + "/"):
		return path.substr(_repo_root.length() + 1)
	return path


func _run_cmd(cmd: String, args: Array) -> Dictionary:
	var out: Array = []
	var code: int = OS.execute(cmd, PackedStringArray(args), out, true)
	var lines: Array = []
	for line: Variant in out:
		lines.append(str(line))
	return {"code": code, "lines": lines}


func _git(args: Array) -> Dictionary:
	return _run_cmd("git", ["-C", _repo_root] + args)


func _git_line(args: Array, fallback: String = "unknown") -> String:
	var r: Dictionary = _git(args)
	var lines: Array = r.get("lines", []) as Array
	if int(r.get("code", 1)) != 0 or lines.is_empty():
		return fallback
	return str(lines[0]).strip_edges()


func _gpu() -> Dictionary:
	var q: String = "name,driver_version,temperature.gpu,memory.used,utilization.gpu,clocks.current.graphics"
	var r: Dictionary = _run_cmd("nvidia-smi", ["--query-gpu=" + q, "--format=csv,noheader,nounits"])
	var rows: Array = []
	for line: Variant in (r.get("lines", []) as Array):
		var s: String = str(line).strip_edges()
		if s == "":
			continue
		var row: Array = []
		for part: String in s.split(","):
			row.append(part.strip_edges())
		rows.append(row)
	return {
		"query": q,
		"command": "nvidia-smi --query-gpu=" + q + " --format=csv,noheader,nounits",
		"available": int(r.get("code", 1)) == 0 and not rows.is_empty(),
		"rows": rows,
	}


func _engine() -> Dictionary:
	var v: Dictionary = Engine.get_version_info()
	return {
		"godot": str(v.get("string", "")),
		"godot_hex": str(v.get("hex", "")),
		"display_server": DisplayServer.get_name(),
		"audio_driver": AudioServer.get_driver_name(),
		"audio_mix_rate": AudioServer.get_mix_rate(),
		"rendering_driver": str(ProjectSettings.get_setting("rendering/rendering_device/driver", "")),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"video_vendor": RenderingServer.get_video_adapter_vendor(),
		"video_api": RenderingServer.get_video_adapter_api_version(),
		"cmdline": OS.get_cmdline_args(),
	}


func _env_snapshot() -> Dictionary:
	var keys: Array[String] = [
		"TAT2_BEAM_CARD", "TAT2_AO", "TAT2_COLLISION", "TAT2_PREP_STAGE",
		"TAT2_ROUGH_BAKE", "TAT2_STATETREE", "TAT2_PARITY_ONLY", "TAT2_GC_LAYERS",
		"DISPLAY", "XDG_SESSION_TYPE", "VK_ICD_FILENAMES",
	]
	var out: Dictionary = {}
	for k: String in keys:
		var v: String = _env(k)
		if v != "":
			out[k] = v
	return out


func _base_manifest(dry_run: bool, self_test: bool) -> Dictionary:
	var sha: String = _git_line(["rev-parse", "HEAD"])
	var dirty_raw: String = _git_line(["status", "--porcelain", "--untracked-files=no"], "")
	var gpu: Dictionary = _gpu()
	gpu["used_by_capture"] = not dry_run
	return {
		"schema": SCHEMA,
		"run_id": _run_id,
		"dry_run": dry_run,
		"self_test": self_test,
		"started_at_utc": _now_iso(),
		"repo_root": _repo_root,
		"out_dir": _out_dir,
		"git": {
			"sha": sha,
			"sha_short": _git_line(["rev-parse", "--short=12", "HEAD"]),
			"branch": _git_line(["rev-parse", "--abbrev-ref", "HEAD"]),
			"dirty": dirty_raw != "",
		},
		"host": {
			"hostname": _env("HOSTNAME"),
			"os": OS.get_name(),
			"os_version": OS.get_version(),
			"cpu": OS.get_processor_name(),
			"nproc": OS.get_processor_count(),
		},
		"gpu": gpu,
		"engine": _engine(),
		"lens": {
			"fov_vertical_deg": SHIPPED_FOV,
			"fov_source": "shipped authored lens: UE 85 deg horizontal at 16:9 -> 54.54 deg vertical",
			"resolution": [SIZE.x, SIZE.y],
			"aspect": 16.0 / 9.0,
			"keep_aspect": "height",
		},
		"settle": {
			"frames": SETTLE_FRAMES,
			"capture_frames": CAPTURE_FRAMES,
			"selector": "median-mean",
			"seconds": _settle_seconds,
			"min_seconds": MIN_SETTLE_SECONDS,
			"mode": "frames+extra" if _settle_seconds > 0.0 else "frames",
		},
		"seed": {
			"requested": _seed_arg,
			"active_map_seed": 0,
			"official_clip_seed": OFFICIAL_CLIP_SEED,
		},
		"env": _env_snapshot(),
		"beam_card": {
			"mode": _beam_mode,
			"hidden": 0,
			"mechanism": "capture-side runtime hide of the lightbeam_cards group; level_loader.gd has no TAT2_BEAM_CARD flag and the beam fix is unchanged",
		},
		"poses": [],
		"audio": {},
		"notes": [
			"Pose alignment against the reference keyframe is approximate; p0b_roi_stats.py reports numbers, not a pixel registration.",
			"The beam numbers are diagnostic: KF27 criteria are encoded in p0b_roi_stats.py from the cream/beam RE (emitter x~17.8% y~40.0%, beam rows 39-40%).",
			"TAT2_BEAM_CARD=off hides the lightbeam_cards group at runtime; it is an A/B control, not a game setting.",
			"The fixed-pose run marks poses, not route beats. A 27-beat route run must call mark_beat(S01..S27); p0b_audio_stats.py --route prints the reference table.",
			"Reference audio is documented RMS/peak dBFS (not LUFS); the script computes RMS/peak only and states the clip's -43.9 LUFS as context.",
		],
	}


func _write_json(path: String, obj: Dictionary) -> bool:
	var dir: String = path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		printerr("P0B_WRITE_FAIL dir=", dir)
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("P0B_WRITE_FAIL path=", path, " err=", FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(obj, "  ") + "\n")
	f.close()
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _validate_manifest(m: Dictionary) -> Array:
	var errs: Array = []
	if str(m.get("schema", "")) != SCHEMA:
		errs.append("schema != " + SCHEMA)
	if typeof(m.get("dry_run")) != TYPE_BOOL:
		errs.append("dry_run is not a bool")
	if typeof(m.get("self_test")) != TYPE_BOOL:
		errs.append("self_test is not a bool")
	if not (m.get("host", null) is Dictionary):
		errs.append("host block missing")
	if not (m.get("gpu", null) is Dictionary):
		errs.append("gpu block missing")
	if not (m.get("engine", null) is Dictionary):
		errs.append("engine block missing")
	var lens: Dictionary = m.get("lens", {}) as Dictionary
	if absf(float(lens.get("fov_vertical_deg", 0.0)) - SHIPPED_FOV) > 0.0005:
		errs.append("lens.fov_vertical_deg != %.2f" % SHIPPED_FOV)
	var res: Array = lens.get("resolution", []) as Array
	if res.size() != 2 or int(res[0]) != SIZE.x or int(res[1]) != SIZE.y:
		errs.append("lens.resolution != [1920,1080]")
	if str(lens.get("keep_aspect", "")) != "height":
		errs.append("lens.keep_aspect != height")
	var settle: Dictionary = m.get("settle", {}) as Dictionary
	if int(settle.get("frames", 0)) != SETTLE_FRAMES:
		errs.append("settle.frames != %d" % SETTLE_FRAMES)
	if int(settle.get("capture_frames", 0)) != CAPTURE_FRAMES:
		errs.append("settle.capture_frames != %d" % CAPTURE_FRAMES)
	if str(settle.get("selector", "")) != "median-mean":
		errs.append("settle.selector != median-mean")
	if settle.has("seconds") and float(settle.get("seconds", 0.0)) < 0.0:
		errs.append("settle.seconds is negative")
	var seed: Dictionary = m.get("seed", {}) as Dictionary
	if not seed.has("requested") or not seed.has("active_map_seed") or int(seed.get("official_clip_seed", 0)) != OFFICIAL_CLIP_SEED:
		errs.append("seed block incomplete")
	var beam: Dictionary = m.get("beam_card", {}) as Dictionary
	if str(beam.get("mode", "")) not in ["on", "off"]:
		errs.append("beam_card.mode not on/off")
	if str(beam.get("mechanism", "")).is_empty():
		errs.append("beam_card.mechanism empty")
	var git: Dictionary = m.get("git", {}) as Dictionary
	if str(git.get("sha", "")).is_empty() or str(git.get("sha", "")) == "unknown":
		errs.append("git.sha missing")
	var poses: Array = m.get("poses", []) as Array
	if poses.size() != _poses.size():
		errs.append("poses size != selected %d" % _poses.size())
	var seen: Dictionary = {}
	for p: Variant in poses:
		if not (p is Dictionary):
			errs.append("pose entry is not a dictionary")
			continue
		var pd: Dictionary = p as Dictionary
		var pid: String = str(pd.get("id", ""))
		seen[pid] = true
		if not POSE_IDS.has(pid):
			errs.append("unknown pose id " + pid)
		var eye: Array = pd.get("eye", []) as Array
		var tgt: Array = pd.get("target", []) as Array
		if eye.size() != 3 or tgt.size() != 3:
			errs.append("%s eye/target is not 3 numbers" % pid)
		var st: String = str(pd.get("status", ""))
		if not ["dry_run", "captured", "failed", "skipped"].has(st):
			errs.append("%s status %s" % [pid, st])
		if bool(m.get("dry_run")):
			if st != "dry_run":
				errs.append("%s dry_run manifest has status %s" % [pid, st])
			if str(pd.get("png", "")) != "":
				errs.append("%s dry_run manifest has a png" % pid)
		elif st == "captured":
			var means: Array = pd.get("frames_mean", []) as Array
			if means.size() != CAPTURE_FRAMES:
				errs.append("%s frames_mean size != %d" % [pid, CAPTURE_FRAMES])
			if str(pd.get("png", "")).is_empty():
				errs.append("%s captured without a png" % pid)
			var ps: Array = pd.get("png_size", []) as Array
			if ps.size() != 2 or int(ps[0]) != SIZE.x or int(ps[1]) != SIZE.y:
				errs.append("%s png_size != [1920,1080]" % pid)
			var mi: int = int(pd.get("median_index", -1))
			if mi < 0 or mi >= CAPTURE_FRAMES:
				errs.append("%s median_index out of range" % pid)
	for id: String in _poses:
		if not seen.has(id):
			errs.append("missing pose " + id)
	var audio: Dictionary = m.get("audio", {}) as Dictionary
	if not audio.has("enabled") or not audio.has("reason"):
		errs.append("audio block missing enabled/reason")
	if bool(m.get("dry_run")) and not bool(audio.get("enabled", true)):
		if str(audio.get("reason", "")).is_empty():
			errs.append("disabled audio has no reason")
	return errs


func _pose_selection() -> Array[String]:
	var raw: String = _arg("--poses=", "")
	var out: Array[String] = []
	if raw.strip_edges() == "":
		out.assign(POSE_IDS)
		return out
	for part: String in raw.split(",", false):
		var pid: String = part.strip_edges()
		if not POSES.has(pid):
			printerr("P0B_UNKNOWN_POSE ", pid, " known=", ", ".join(POSE_IDS))
			continue
		if not out.has(pid):
			out.append(pid)
	return out


func _setup_paths() -> void:
	_repo_root = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var raw_tag: String = _arg("--tag=", "")
	_tag = raw_tag.replace(" ", "_")
	var beam: String = _beam_mode
	var run: String = _arg("--run-id=", "")
	if run == "":
		run = _stamp()
		if _tag != "":
			run += "_" + _tag
		run += "_" + _git_line(["rev-parse", "--short=12", "HEAD"], "nogit") + "_" + beam
	_run_id = run
	var env_out: String = _env("P0B_OUT")
	_out_dir = env_out if env_out != "" else _repo_root.path_join("build/qa/p0b/captures").path_join(_run_id)
	var env_manifest: String = _env("P0B_MANIFEST")
	if env_manifest != "":
		_manifest_path = env_manifest
	elif _mode == "dry-run":
		_manifest_path = _repo_root.path_join("docs/reports/logs/p0b/dry-run/manifest.json")
	elif _mode == "self-test":
		_manifest_path = _repo_root.path_join("build/qa/p0b/selftest/manifest.json")
	else:
		_manifest_path = _repo_root.path_join("docs/reports/logs/p0b").path_join(_run_id).path_join("manifest.json")


## Per-pose provenance that must survive into every manifest: the labelled
## decision (only PORT_DECISION poses carry one), the authored anchor if the eye
## was raised from it, and the look-at pitch so a reviewer can recompute it.
func _pose_provenance(p: Dictionary) -> Dictionary:
	var row: Dictionary = {
		"decision": str(p.get("decision", "")),
		"pitch_deg": snappedf(_pitch_deg(p["eye"] as Vector3, p["target"] as Vector3), 0.001),
	}
	if p.has("authored_start"):
		row["authored_start"] = _v3(p["authored_start"] as Vector3)
	return row


func _dry_run() -> void:
	var m: Dictionary = _base_manifest(true, false)
	var poses: Array = []
	for pid: String in _poses:
		var p: Dictionary = POSES[pid] as Dictionary
		var eye: Vector3 = p["eye"] as Vector3
		# A dry run cannot ground; the authored x/z and the authored y are
		# recorded with grounded=false so nobody mistakes it for a measurement.
		var row: Dictionary = {
			"id": pid, "status": "dry_run",
			"beat": str(p.get("beat", "")), "ref_keyframe": str(p.get("ref", "")),
			"eye": _v3(eye), "target": _v3(p["target"] as Vector3),
			"grounded": false, "ground_planned": bool(p.get("ground", false)),
			"fov_vertical_deg": SHIPPED_FOV,
			"resolution": [SIZE.x, SIZE.y],
			"note": str(p.get("note", "")),
		}
		row.merge(_pose_provenance(p), true)
		poses.append(row)
	m["poses"] = poses
	m["audio"] = {
		"schema": "tat2.audio_capture/1",
		"enabled": false,
		"reason": "dry_run",
		"driver": AudioServer.get_driver_name(),
		"sample_rate": AudioServer.get_mix_rate(),
		"channels": 2,
		"frames": 0,
		"seconds": 0.0,
		"marks": [],
		"note": "dry run: the tap was not started; a real capture records WAV/PCM + per-mark dBFS windows",
	}
	m["finished_at_utc"] = _now_iso()
	m["selection"] = {"poses": _poses, "tag": _tag}
	var errs: Array = _validate_manifest(m)
	if not errs.is_empty():
		for e: Variant in errs:
			printerr("P0B_MANIFEST_INVALID ", str(e))
		quit(1)
		return
	if not _write_json(_manifest_path, m):
		quit(1)
		return
	print("P0B_DRY_RUN manifest=%s poses=%d schema=%s audio=disabled reason=dry_run" % [
		_manifest_path, poses.size(), SCHEMA,
	])
	quit(0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("P0B_SELFTEST ok ", what)
	else:
		_fails += 1
		printerr("P0B_SELFTEST FAIL ", what)


func _self_test() -> void:
	# 1. Contract constants.
	_check(POSE_IDS.size() == 9, "nine pose ids (incl. KF27 foyer_beam/wide, gap view + Lounge extra)")
	_check(is_equal_approx(SHIPPED_FOV, 54.54), "shipped vertical FOV is 54.54")
	_check(SIZE == Vector2i(1920, 1080), "resolution is 1920x1080")
	_check(SETTLE_FRAMES == 60 and CAPTURE_FRAMES == 5, "settle 60 + 5 frames")
	_check(OFFICIAL_CLIP_SEED == 1025051536, "official clip seed recorded")
	var foyer_beam: Dictionary = POSES["foyer_beam"] as Dictionary
	_check((foyer_beam.get("eye") as Vector3).is_equal_approx(Vector3(27.0, 29.67, -55.0))
		and (foyer_beam.get("target") as Vector3).is_equal_approx(Vector3(23.27, 29.76, -57.4))
		and str(foyer_beam.get("ref", "")) == "KF27"
		and str(foyer_beam.get("beat", "")) == "S24",
		"foyer_beam is the KF27 cue (27,29.67,-55) -> (23.27,29.76,-57.4)")
	var lounge_extra: Dictionary = POSES["beam_close"] as Dictionary
	_check(str(lounge_extra.get("ref", "")) == "EXTRA"
		and str(lounge_extra.get("beat", "")) == "",
		"beam_close is the Lounge C_57 extra, not a KF27/S24 frame")
	# The two derived poses are validated by arithmetic, not by literal values:
	# the card centre must project to ~18 %/40 % from the wide eye, and the gap
	# view must be the authored start + player eye height with a -42..-53 deg
	# pitch labelled PORT_DECISION. The look-at target must project to 50/50,
	# which independently proves _project_pct matches the camera convention.
	var wide: Dictionary = POSES["foyer_beam_wide"] as Dictionary
	var wide_eye: Vector3 = wide["eye"] as Vector3
	var wide_tgt: Vector3 = wide["target"] as Vector3
	var wproj: Vector2 = _project_pct(wide_eye, wide_tgt, Vector3(23.27, 29.76, -57.4))
	var wcenter: Vector2 = _project_pct(wide_eye, wide_tgt, wide_tgt)
	var gap: Dictionary = POSES["gap_view"] as Dictionary
	var gap_eye: Vector3 = gap["eye"] as Vector3
	var gap_tgt: Vector3 = gap["target"] as Vector3
	var gap_start: Vector3 = gap["authored_start"] as Vector3
	var gap_pitch: float = _pitch_deg(gap_eye, gap_tgt)
	var pose_ok: bool = true
	var seen_poses: Dictionary = {}
	for pid: String in POSE_IDS:
		var p: Dictionary = POSES[pid] as Dictionary
		if not (p.get("eye") is Vector3) or not (p.get("target") is Vector3):
			pose_ok = false
			continue
		var eye: Vector3 = p["eye"] as Vector3
		var tgt: Vector3 = p["target"] as Vector3
		if eye.is_equal_approx(tgt):
			pose_ok = false
		# 9 distinct (eye,target) pairs: a copy-paste duplicate must fail.
		var key: String = "%.4f,%.4f,%.4f->%.4f,%.4f,%.4f" % [
			eye.x, eye.y, eye.z, tgt.x, tgt.y, tgt.z,
		]
		if seen_poses.has(key):
			pose_ok = false
		seen_poses[key] = pid
		if not p.has("beat") or not p.has("ref"):
			pose_ok = false
	pose_ok = pose_ok \
		and absf(wcenter.x - 50.0) < 0.01 and absf(wcenter.y - 50.0) < 0.01 \
		and absf(wproj.x - 18.0) <= 2.0 and absf(wproj.y - 40.0) <= 2.0 \
		and str(wide.get("ref", "")) == "KF27" \
		and str(gap.get("decision", "")) == "PORT_DECISION" \
		and gap_tgt.is_equal_approx(Vector3(120.25, 18.56, -6.815)) \
		and absf(gap_eye.x - gap_start.x) < 0.0001 \
		and absf(gap_eye.z - gap_start.z) < 0.0001 \
		and absf((gap_eye.y - gap_start.y) - PLAYER_EYE_HEIGHT) < 0.0001 \
		and gap_pitch >= -53.0 and gap_pitch <= -42.0
	if not pose_ok:
		printerr("P0B_SELFTEST detail wide_card_pct=", wproj, " wide_center_pct=", wcenter,
			" gap_pitch_deg=", gap_pitch)
	_check(pose_ok, "poses valid: distinct eye/target, beat/ref; foyer_beam_wide card ~18/40; gap_view start+eye, PORT_DECISION, pitch -42..-53")
	_check(_pose_selection().size() >= 1
		and MIN_SETTLE_SECONDS == 25.0
		and _parse_settle_seconds("") == 0.0
		and _parse_settle_seconds("25") == 25.0
		and _parse_settle_seconds("nope") < 0.0
		and _settle_ok(0.0) and _settle_ok(25.0) and _settle_ok(30.0)
		and not _settle_ok(10.0),
		"pose selection is non-empty; --settle-seconds parses and enforces 0 or >=25 s")

	# 2. Audio tap: must not crash and must report disabled under headless.
	var tap_script: GDScript = load(AUDIO_SRC) as GDScript
	_check(tap_script != null, "audio_capture.gd loads")
	if tap_script != null:
		var tap: Node = tap_script.new() as Node
		root.add_child(tap)
		var started: bool = bool(tap.call("start", 1.0))
		await _wait(3)
		var bad_beat: bool = bool(tap.call("mark_beat", "S99", "bad"))
		var good_beat: bool = bool(tap.call("mark_beat", "S24", "foyer"))
		var audio_dir: String = _repo_root.path_join("build/qa/p0b/selftest")
		var res: Dictionary = tap.call("stop_to", audio_dir, "selftest_audio") as Dictionary
		var is_dummy: bool = AudioServer.get_driver_name().to_lower() == "dummy"
		_check(not bad_beat, "mark_beat rejects S99")
		_check(good_beat, "mark_beat accepts S24")
		_check(typeof(res.get("enabled")) == TYPE_BOOL, "audio result has enabled")
		_check(not str(res.get("reason", "")).is_empty() or bool(res.get("enabled")), "audio result explains a disabled tap")
		if is_dummy:
			_check(not bool(res.get("enabled", true)), "dummy driver -> disabled tap")
			_check(str(res.get("reason", "")) == "dummy_audio_driver", "dummy reason is dummy_audio_driver")
		_check(FileAccess.file_exists(str(res.get("sidecar", ""))), "audio sidecar written")
		if started:
			print("P0B_SELFTEST audio=enabled (non-headless host)")
		tap.queue_free()
		await _wait(1)

	# 3. Dry-run manifest: build, validate, round-trip.
	var m: Dictionary = _base_manifest(true, true)
	var poses: Array = []
	for pid: String in _poses:
		var p: Dictionary = POSES[pid] as Dictionary
		var row: Dictionary = {
			"id": pid, "status": "dry_run",
			"beat": str(p.get("beat", "")), "ref_keyframe": str(p.get("ref", "")),
			"eye": _v3(p["eye"] as Vector3), "target": _v3(p["target"] as Vector3),
			"grounded": false, "ground_planned": bool(p.get("ground", false)),
			"fov_vertical_deg": SHIPPED_FOV, "resolution": [SIZE.x, SIZE.y],
			"note": str(p.get("note", "")),
		}
		row.merge(_pose_provenance(p), true)
		poses.append(row)
	m["poses"] = poses
	m["audio"] = {"schema": "tat2.audio_capture/1", "enabled": false, "reason": "self_test", "marks": []}
	var errs: Array = _validate_manifest(m)
	_check(errs.is_empty(), "manifest validates (%d errors)" % errs.size())
	for e: Variant in errs:
		printerr("P0B_MANIFEST_INVALID ", str(e))
	var path: String = _repo_root.path_join("build/qa/p0b/selftest/manifest.json")
	_check(_write_json(path, m), "manifest writes")
	var back: Dictionary = _read_json(path)
	_check(not back.is_empty(), "manifest reads back")
	_check(_validate_manifest(back).is_empty(), "round-tripped manifest validates")
	# Negative control: a manifest with a wrong lens must fail.
	var bad: Dictionary = m.duplicate(true)
	(bad["lens"] as Dictionary)["fov_vertical_deg"] = 75.0
	_check(not _validate_manifest(bad).is_empty(), "wrong FOV is rejected")
	var bad2: Dictionary = m.duplicate(true)
	(bad2["settle"] as Dictionary)["frames"] = 12
	_check(not _validate_manifest(bad2).is_empty(), "wrong settle count is rejected")

	print("P0B_SELFTEST_SUMMARY checks=%d fails=%d" % [_checks, _fails])
	print("P0B_SELFTEST %s checks=%d fails=%d" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	quit(0 if _fails == 0 else 1)


func _apply_seed(gs: Node) -> void:
	if _seed_arg.to_lower() == "derived":
		return
	if not _seed_arg.is_valid_int():
		printerr("P0B bad --seed=", _seed_arg, " (int or derived)")
		return
	gs.set("active_map_seed", int(_seed_arg))


func _mission() -> Node3D:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("P0B_MISSION_FAIL GameState missing")
		return null
	gs.set("state", "playing")
	gs.set("thief_id", "spider")
	gs.set("active_contract_order", 4)
	gs.set("active_map_id", "guildhall")
	_apply_seed(gs)
	var mission: Node3D = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(mission)
	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and waited < 1800:
		await process_frame
		waited += 1
	await _wait(40)
	if mission.get("player") == null:
		printerr("P0B_MISSION_FAIL player missing waited=", waited)
		return null
	var hud: Node = mission.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(10)
	print("P0B_MISSION ready waited=%d player=%s doors=%d seed_requested=%s active_seed=%d" % [
		waited, str(mission.get("player") != null), get_nodes_in_group("swinging_doors").size(),
		_seed_arg, int(gs.get("active_map_seed")),
	])
	return mission


func _hide_beam_cards() -> int:
	var hidden: int = 0
	for n: Node in get_nodes_in_group("lightbeam_cards"):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if gi != null and gi.visible:
			gi.visible = false
			hidden += 1
	print("P0B_BEAM_CARD mode=off hidden=%d group=lightbeam_cards" % hidden)
	return hidden


## Downward floor ray at the authored x/z. Excludes the player capsule and its
## collision exceptions (the audio_manager occlusion-ray pattern).
func _ground_eye(mission: Node3D, eye: Vector3) -> Dictionary:
	var world: World3D = mission.get_world_3d()
	if world == null:
		return {"grounded": false, "eye": eye, "hit": []}
	var from: Vector3 = Vector3(eye.x, eye.y + 0.05, eye.z)
	var to: Vector3 = Vector3(eye.x, eye.y - 24.0, eye.z)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	var excluded: Array[RID] = []
	var body: Node = get_first_node_in_group("player")
	if body is CollisionObject3D:
		var co: CollisionObject3D = body as CollisionObject3D
		excluded.append(co.get_rid())
		if co.has_method("get_collision_exceptions"):
			for exc: Variant in co.call("get_collision_exceptions"):
				if exc is RID:
					excluded.append(exc)
				elif exc is CollisionObject3D:
					excluded.append((exc as CollisionObject3D).get_rid())
	q.exclude = excluded
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		print("P0B_GROUND pose_eye=%s grounded=false (no floor hit)" % str(eye))
		return {"grounded": false, "eye": eye, "hit": []}
	var hp: Vector3 = hit.get("position", eye) as Vector3
	var grounded_eye := Vector3(eye.x, hp.y + EYE_OFFSET, eye.z)
	print("P0B_GROUND eye=%s hit=%s grounded=true eye_y=%.3f" % [
		str(eye), str(hp), grounded_eye.y,
	])
	return {"grounded": true, "eye": grounded_eye, "hit": [hp.x, hp.y, hp.z]}


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var tex: ViewportTexture = root.get_texture()
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return null
	return img


## Sampled ITU-R 601 luma (the same weights Pillow convert("L") uses), every 4th
## pixel. Only a non-black guard and the median selector; the authoritative
## percentiles come from build/qa/w9_frame_stats.py / p0b_roi_stats.py.
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
		return {"mean": 0.0, "pct_lt8": 100.0, "peak": 0.0, "samples": 0}
	return {
		"mean": sum / float(total),
		"pct_lt8": 100.0 * float(below8) / float(total),
		"peak": peak,
		"samples": total,
	}


func _shoot(mission: Node3D, cam: Camera3D, pid: String, tap: Node) -> Dictionary:
	var p: Dictionary = POSES[pid] as Dictionary
	var eye: Vector3 = p["eye"] as Vector3
	var target: Vector3 = p["target"] as Vector3
	var grounded: bool = false
	var ground_hit: Array = []
	if bool(p.get("ground", false)):
		var g: Dictionary = _ground_eye(mission, eye)
		eye = g.get("eye", eye) as Vector3
		grounded = bool(g.get("grounded", false))
		ground_hit = g.get("hit", []) as Array
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.current = true
	var t0: int = Time.get_ticks_msec()
	var settle_waited_ms: int = await _wait_settle()
	if _settle_seconds > 0.0:
		print("P0B_SETTLE pose=%s frames=%d extra_s=%.2f waited_ms=%d" % [
			pid, SETTLE_FRAMES, _settle_seconds, settle_waited_ms,
		])
	if tap != null:
		# Mark at the captured pose (after the settle hold, not before it). A
		# fixed pose is not a route beat: label it, never claim Sxx. The pose's
		# beat/reference keyframe stays in the manifest for provenance only.
		tap.call("mark", pid, "")
	var imgs: Array = []
	var means: Array = []
	for i: int in range(CAPTURE_FRAMES):
		var img: Image = await _grab()
		if img == null:
			printerr("P0B_SHOT_FAIL pose=", pid, " frame=", i, " empty image")
			return {"id": pid, "status": "failed", "error": "empty frame"}
		var st: Dictionary = _sampled_stats(img)
		imgs.append(img)
		means.append(float(st.get("mean", 0.0)))
		print("P0B_FRAME pose=%s frame=%d mean601=%.2f lt8=%.1f peak=%.1f" % [
			pid, i, float(st.get("mean", 0.0)), float(st.get("pct_lt8", 100.0)),
			float(st.get("peak", 0.0)),
		])
	# Median by mean luma: sort indices, take the middle, save that exact frame
	# (a median of five frames is a selection, never a pixel average).
	var order: Array = []
	for i: int in range(means.size()):
		order.append([float(means[i]), i])
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var median_index: int = int((order[int(order.size() / 2)] as Array)[1])
	var med: Image = imgs[median_index] as Image
	var png: String = _out_dir.path_join(pid + ("_nobeam" if _beam_mode == "off" else "") + ".png")
	var err: int = med.save_png(png)
	var st_med: Dictionary = _sampled_stats(med)
	var size_ok: bool = med.get_width() == SIZE.x and med.get_height() == SIZE.y
	if not size_ok:
		printerr("P0B_SHOT_SIZE_FAIL pose=%s size=%dx%d want=%dx%d" % [
			pid, med.get_width(), med.get_height(), SIZE.x, SIZE.y,
		])
	var nonblack: bool = err == OK and size_ok and float(st_med.get("peak", 0.0)) > 8.0 and float(st_med.get("mean", 0.0)) > 1.0
	print("P0B_SHOT pose=%s median=%d mean601=%.2f lt8=%.1f peak=%.1f err=%d size=%dx%d nonblack=%s png=%s" % [
		pid, median_index, float(st_med.get("mean", 0.0)), float(st_med.get("pct_lt8", 100.0)),
		float(st_med.get("peak", 0.0)), err, med.get_width(), med.get_height(), str(nonblack), _rel(png),
	])
	imgs.clear()
	var row: Dictionary = {
		"id": pid, "status": "captured" if nonblack else "failed",
		"beat": str(p.get("beat", "")), "ref_keyframe": str(p.get("ref", "")),
		"eye": _v3(eye), "target": _v3(target),
		"grounded": grounded, "ground_hit": ground_hit,
		"fov_vertical_deg": SHIPPED_FOV, "resolution": [SIZE.x, SIZE.y],
		"png_size": [med.get_width(), med.get_height()],
		"frames_mean": means, "median_index": median_index,
		"median_mean": float(st_med.get("mean", 0.0)),
		"median_lt8": float(st_med.get("pct_lt8", 100.0)),
		"median_peak": float(st_med.get("peak", 0.0)),
		"png": _rel(png), "duration_ms": Time.get_ticks_msec() - t0,
		"settle_seconds": _settle_seconds, "settle_waited_ms": settle_waited_ms,
		"note": str(p.get("note", "")),
	}
	row.merge(_pose_provenance(p), true)
	return row


func _capture() -> void:
	root.size = SIZE
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# The tap is created before the mission so its Master effect is the last
	# element on the chain from the first gameplay frame; a headless/absent
	# device disables it and writes a sidecar instead of a WAV.
	var tap_script: GDScript = load(AUDIO_SRC) as GDScript
	var tap: Node = null
	if tap_script != null:
		tap = tap_script.new() as Node
		root.add_child(tap)
		tap.call("start", 10.0)
		tap.call("mark", "capture_start", "")
	var m: Dictionary = _base_manifest(false, false)
	var mission: Node3D = await _mission()
	if mission == null:
		m["status"] = "failed"
		m["error"] = "mission load"
		m["poses"] = []
		m["audio"] = tap.call("stop_to", _out_dir, "audio_" + _beam_mode) if tap != null else {"enabled": false, "reason": "audio_script_missing"}
		m["finished_at_utc"] = _now_iso()
		_write_json(_manifest_path, m)
		quit(1)
		return
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		(m["seed"] as Dictionary)["active_map_seed"] = int(gs.get("active_map_seed"))
	if _beam_mode == "off":
		var hidden: int = _hide_beam_cards()
		(m["beam_card"] as Dictionary)["hidden"] = hidden
		await _wait(10)
	var cam: Camera3D = Camera3D.new()
	cam.name = "P0bCaptureCamera"
	cam.fov = SHIPPED_FOV
	cam.far = 4000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	mission.add_child(cam)
	cam.current = true
	var rows: Array = []
	var ok_all: bool = true
	for pid: String in _poses:
		var row: Dictionary = await _shoot(mission, cam, pid, tap)
		rows.append(row)
		if str(row.get("status", "")) != "captured":
			ok_all = false
		await _wait(5)
	m["poses"] = rows
	m["status"] = "captured" if ok_all else "partial"
	if tap != null:
		var audio_res: Dictionary = tap.call("stop_to", _out_dir, "audio_" + _beam_mode) as Dictionary
		m["audio"] = audio_res
	else:
		m["audio"] = {"schema": "tat2.audio_capture/1", "enabled": false, "reason": "audio_script_missing", "marks": []}
	m["finished_at_utc"] = _now_iso()
	var errs: Array = _validate_manifest(m)
	if not errs.is_empty():
		for e: Variant in errs:
			printerr("P0B_MANIFEST_INVALID ", str(e))
		ok_all = false
	m["manifest_errors"] = errs
	if not _write_json(_manifest_path, m):
		ok_all = false
	print("P0B_CAPTURE_DONE status=%s poses=%d ok=%s manifest=%s out=%s" % [
		str(m.get("status", "")), rows.size(), str(ok_all), _manifest_path, _out_dir,
	])
	if tap != null:
		tap.queue_free()
	quit(0 if ok_all else 1)


func _run() -> void:
	_mode = _arg("--mode=", "capture")
	_beam_mode = _arg("--beam-card=", _env("TAT2_BEAM_CARD")).to_lower()
	if _beam_mode == "":
		_beam_mode = "on"
	if _beam_mode not in ["on", "off"]:
		printerr("P0B bad --beam-card=", _beam_mode, " (on|off)")
		quit(2)
		return
	_seed_arg = _arg("--seed=", "derived")
	_settle_seconds = _parse_settle_seconds(_arg("--settle-seconds=", ""))
	if _settle_seconds < 0.0 or not _settle_ok(_settle_seconds):
		printerr("P0B bad --settle-seconds (want 0 or >= %.0f s, <= 3600 s)" % MIN_SETTLE_SECONDS)
		quit(2)
		return
	_poses = _pose_selection()
	if _poses.is_empty():
		printerr("P0B no poses selected")
		quit(2)
		return
	_setup_paths()
	print("P0B_START mode=%s run=%s poses=%s beam=%s seed=%s settle_s=%.2f fov=%.2f size=%s out=%s manifest=%s" % [
		_mode, _run_id, ",".join(_poses), _beam_mode, _seed_arg, _settle_seconds,
		SHIPPED_FOV, str(SIZE), _out_dir, _manifest_path,
	])
	if _mode == "dry-run":
		_dry_run()
	elif _mode == "self-test":
		await _self_test()
	elif _mode == "capture":
		await _capture()
	else:
		printerr("P0B unknown mode=", _mode, " (capture|dry-run|self-test)")
		quit(2)
