extends Node
## Fixed-pose performance matrix runner for the Guildhall map (W0b).
##
## Node form so both entry points share one implementation:
##   - editor: `perf_matrix.gd` (SceneTree) adds this runner to the root
##   - export: `main_menu.gd` instantiates it when `--perf-matrix` is present
##     (release exports do not honour `--script`)
##
## Loads `res://scenes/mission.tscn` once, waits for the new `mission_ready`
## signal instead of polling player/doors, discards a fixed warm-up, then walks
## the same six authored camera poses used by the capture scripts:
##   spawn_overlook, gate_approach, gate_sign, foyer, upper_foyer, door_approach
##
## Each pose holds still for 3 s, then pans 30 deg over 4 s while recording:
##   - wall-clock frame time (Time.get_ticks_usec between process_frame ticks)
##   - Performance.TIME_PROCESS / TIME_PHYSICS_PROCESS
##   - RenderingServer.viewport_get_measured_render_time_cpu/gpu
##   - draw calls, visible objects, primitives, node count, VRAM
##   - light nodes, device nodes, level chunks
## One JSON object per pose is printed (JSONL), then PERF_SUMMARY and
## PERF_DONE. Any missing mission_ready, runtime/config mismatch, unknown pose
## or deadline overrun exits nonzero; the shell wrapper also fails a log
## without PERF_DONE (truncated runs cannot pass).
##
## The player is frozen (physics + look input off); the camera path never reads
## input. The player camera is used deliberately so the 1P viewmodel remains in
## the measured frame.
##
## The lens is the shipped one unless `--perf-fov`/`--perf-far` say otherwise:
## 54.54 vertical (UE 85 horizontal at 16:9) and a 4000 m far plane. The matrix
## used to force 60/500, which measured a wider, shallower frustum than any
## shipped frame (docs/reports/w0p-perf-rig.md).
##
## Usage:
##   build/qa/run_perf_matrix.sh --quality=...   (see the wrapper)
##   or: tools/godot --path game --script res://tests/perf/perf_matrix.gd -- \
##     --perf-quality=high --perf-scale=1.0 --perf-scaling=bilinear \
##     --perf-lights=160 --perf-shadows=6 --perf-vsync=off \
##     --perf-fov=54.54 --perf-far=4000 \
##     --res=1920x1080 --contract=4
##
## Short validation:
##   ... --pose=spawn_overlook --frames=300 --warmup=180

const PerfProfile: GDScript = preload("res://src/core/perf_profile.gd")

const HOLD_SEC: float = 3.0
const PAN_SEC: float = 4.0
const PAN_DEG: float = 30.0
const DEFAULT_WARMUP: int = 180
const DEFAULT_SETTLE: int = 30
const DEFAULT_LOAD_TIMEOUT_SEC: int = 240
const DEFAULT_DEADLINE_SEC: int = 2400

## `pos` is the player (feet) position from the capture script; `eye` is an
## exact camera position from a capture script and is converted to feet using
## the live player head offset so the player camera lands on the authored eye.
const POSES: Array[Dictionary] = [
	{
		"id": "spawn_overlook",
		"pos": Vector3(55.86, 23.2, 83.46),
		"target": Vector3(60.0, 40.0, 20.0),
	},
	{
		"id": "gate_approach",
		"eye": Vector3(10.0, 20.0, 100.0),
		"target": Vector3(10.0, 22.0, 88.0),
	},
	{
		"id": "gate_sign",
		"eye": Vector3(10.0, 24.0, 62.0),
		"target": Vector3(10.0, 25.3, 48.7),
	},
	{
		"id": "foyer",
		"pos": Vector3(22.0, 20.5, 125.3),
		"target": Vector3(22.0, 22.17, 115.3),
	},
	{
		"id": "upper_foyer",
		"pos": Vector3(27.0, 28.0, -50.0),
		"target": Vector3(27.0, 29.67, -60.0),
	},
	{
		"id": "door_approach",
		"pos": Vector3(22.0, 20.5, 128.4),
		"target": Vector3(22.0, 22.17, 118.4),
	},
]

var _mission: Node = null
var _player: CharacterBody3D = null
var _head: Node3D = null
var _cam: Camera3D = null
var _eye_offset: float = 1.67
var _ready_fired: bool = false
var _ready_map: String = ""
var _ready_stats: Dictionary = {}
var _in_pose: bool = false
var _pose_start_yaw: float = 0.0
var _pose_start_pitch: float = 0.0
var _lights: int = 0
var _devices: int = 0
var _chunks: int = 0
var _deadline_ms: int = 0
var _fov: float = PerfProfile.DEFAULT_FOV
var _far: float = PerfProfile.DEFAULT_FAR


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var cfg: Dictionary = PerfProfile.collect_cli_config()
	if not bool(cfg.get("ok", true)):
		for err: Variant in cfg.get("errors", []):
			printerr("PERF_ERROR config: ", str(err))
		get_tree().quit(2)
		return
	if not bool(cfg.get("requested", false)):
		printerr("PERF_ERROR no --perf-* config supplied; refusing to measure an unknown ladder")
		get_tree().quit(2)
		return
	if int(cfg.get("vsync", -1)) != 0:
		printerr("PERF_ERROR --perf-vsync=off is required; a vsync-capped run is not a frame-time measurement")
		get_tree().quit(2)
		return

	var res: Vector2i = _parse_res(_arg("--res=", "1920x1080"))
	var contract: int = int(_arg("--contract=", "4"))
	_fov = PerfProfile.resolved_fov(cfg)
	_far = PerfProfile.resolved_far(cfg)
	var warmup: int = int(_arg("--warmup=", str(DEFAULT_WARMUP)))
	var settle: int = int(_arg("--settle=", str(DEFAULT_SETTLE)))
	var frames: int = int(_arg("--frames=", "0"))
	var load_timeout_ms: int = int(_arg("--load-timeout=", str(DEFAULT_LOAD_TIMEOUT_SEC))) * 1000
	var deadline_sec: int = int(_arg("--deadline=", str(DEFAULT_DEADLINE_SEC)))
	_deadline_ms = Time.get_ticks_msec() + deadline_sec * 1000
	var pose_ids: Array[String] = _selected_poses()
	if pose_ids.is_empty():
		printerr("PERF_ERROR no poses selected")
		get_tree().quit(2)
		return

	get_tree().root.size = res
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(res)
	RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)
	for _i: int in range(3):
		await get_tree().process_frame
	PerfProfile.apply(get_tree(), cfg, true)

	var gd: Node = get_tree().root.get_node_or_null("/root/GameData")
	if gd == null:
		printerr("PERF_ERROR GameData autoload missing")
		get_tree().quit(2)
		return
	var map_row: Dictionary = gd.call("get_contract_display", contract) as Dictionary
	var expected_map: String = str(map_row.get("map_id", ""))
	printerr("PERF_RUN " + JSON.stringify({
		"map": expected_map,
		"contract": contract,
		"poses": pose_ids,
		"fov": _fov,
		"far": _far,
		"warmup_frames": warmup,
		"settle_frames": settle,
		"measure_mode": "frames" if frames > 0 else "time",
		"measure_frames": frames,
		"hold_sec": HOLD_SEC,
		"pan_sec": PAN_SEC,
		"pan_deg": PAN_DEG,
		"headless": DisplayServer.get_name() == "headless",
	}))

	var gs: Node = get_tree().root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("PERF_ERROR GameState autoload missing")
		get_tree().quit(2)
		return
	gs.set("active_contract_order", contract)

	var mission_scene: PackedScene = load("res://scenes/mission.tscn") as PackedScene
	if mission_scene == null:
		printerr("PERF_ERROR mission scene missing")
		get_tree().quit(2)
		return
	_mission = mission_scene.instantiate()
	_mission.connect("mission_ready", _on_mission_ready)
	get_tree().root.add_child(_mission)

	var load_start: int = Time.get_ticks_msec()
	while not _ready_fired:
		if Time.get_ticks_msec() - load_start > load_timeout_ms:
			printerr("PERF_ERROR mission_ready timeout after ", load_timeout_ms / 1000, " s")
			get_tree().quit(3)
			return
		if Time.get_ticks_msec() > _deadline_ms:
			printerr("PERF_ERROR deadline hit while waiting for mission_ready")
			get_tree().quit(4)
			return
		await get_tree().process_frame
	if _ready_map != expected_map:
		printerr("PERF_ERROR mission_ready map mismatch want=", expected_map, " got=", _ready_map)
		get_tree().quit(3)
		return
	printerr("PERF_READY map=", _ready_map, " meshes=", int(_ready_stats.get("mesh_instances", 0)), " lights=", int(_ready_stats.get("light_count", 0)), " chunks=", int(_ready_stats.get("chunk_count", 0)))

	await _close_mission_letter()
	_freeze_player()
	_lights = _count_lights(_mission)
	_devices = get_tree().get_nodes_in_group("devices").size()
	_chunks = int(_ready_stats.get("chunk_count", 0))

	# Warm-up is discarded once after load; shader/pipeline compilation is a
	# first-view cost, not part of the steady-state pose measurement.
	for _i: int in range(maxi(0, warmup)):
		await get_tree().process_frame
		if Time.get_ticks_msec() > _deadline_ms:
			printerr("PERF_ERROR deadline hit during warm-up")
			get_tree().quit(4)
			return

	var mismatches: Array[String] = PerfProfile.config_mismatches(get_tree(), cfg, _cam)
	if not mismatches.is_empty():
		for mismatch: String in mismatches:
			printerr("PERF_ERROR config mismatch: ", mismatch)
		get_tree().quit(5)
		return

	var all_frames: Array[float] = []
	var pose_records: Array[Dictionary] = []
	for pose_id: String in pose_ids:
		if Time.get_ticks_msec() > _deadline_ms:
			printerr("PERF_ERROR deadline hit before pose ", pose_id)
			get_tree().quit(4)
			return
		var pose: Dictionary = _pose_by_id(pose_id)
		if pose.is_empty():
			printerr("PERF_ERROR unknown pose ", pose_id)
			get_tree().quit(2)
			return
		_apply_pose(pose)
		for _s: int in range(maxi(0, settle)):
			await get_tree().process_frame
		var record: Dictionary = await _measure_pose(pose_id, frames)
		if record.is_empty():
			return
		pose_records.append(record)
		for sample_v: Variant in record.get("samples_ms", []):
			all_frames.append(float(sample_v))
		var emit: Dictionary = record.duplicate(true)
		emit.erase("samples_ms")
		printerr(JSON.stringify(emit))

	if pose_records.size() != pose_ids.size():
		printerr("PERF_ERROR truncated pose list: ", pose_records.size(), "/", pose_ids.size())
		get_tree().quit(6)
		return
	_print_summary(pose_records, all_frames)
	printerr("PERF_DONE poses=", pose_records.size(), " expected=", pose_ids.size(), " samples=", all_frames.size())
	get_tree().quit(0)


func _on_mission_ready(map_id: String, stats: Dictionary) -> void:
	_ready_fired = true
	_ready_map = map_id
	_ready_stats = stats


func _close_mission_letter() -> void:
	var hud: Node = _mission.get("hud") as Node
	if hud == null:
		return
	if hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		if hud.has_method("_close_mission_letter"):
			hud.call("_close_mission_letter")
		for _i: int in range(6):
			await get_tree().process_frame


func _freeze_player() -> void:
	_player = _mission.get("player") as CharacterBody3D
	if _player == null:
		return
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_player.velocity = Vector3.ZERO
	_head = _player.get("head") as Node3D
	_cam = _player.get("cam") as Camera3D
	if _head != null:
		_eye_offset = maxf(0.1, _head.position.y)
	if _cam != null:
		_cam.fov = _fov
		_cam.far = _far
		_cam.current = true


func _apply_pose(pose: Dictionary) -> void:
	if _player == null:
		return
	# Re-assert the configured lens every pose: the player's camera controller
	# (disabled here) is the only other writer, but a pose must never measure a
	# silently inherited FOV/far plane.
	if _cam != null:
		_cam.fov = _fov
		_cam.far = _far
		_cam.current = true
	var pos: Vector3
	if pose.has("eye"):
		pos = (pose["eye"] as Vector3) - Vector3(0.0, _eye_offset, 0.0)
	else:
		pos = pose["pos"] as Vector3
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	var target: Vector3 = pose["target"] as Vector3
	var eye: Vector3 = pos + Vector3(0.0, _eye_offset, 0.0)
	var diff: Vector3 = target - eye
	_pose_start_yaw = atan2(-diff.x, -diff.z)
	_pose_start_pitch = clampf(atan2(diff.y, maxf(Vector2(diff.x, diff.z).length(), 0.001)), deg_to_rad(-78.0), deg_to_rad(78.0))
	_player.rotation = Vector3(0.0, _pose_start_yaw, 0.0)
	if _head != null:
		_head.rotation.x = _pose_start_pitch
	_in_pose = true


func _measure_pose(pose_id: String, frame_limit: int) -> Dictionary:
	var frame_ms: Array[float] = []
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var render_cpu_ms: Array[float] = []
	var render_gpu_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var visible_objects: Array[float] = []
	var primitives: Array[float] = []
	var vram_mb: Array[float] = []
	var viewport_rid: RID = get_tree().root.get_viewport_rid()
	var use_frames: bool = frame_limit > 0
	var total_frames: int = frame_limit if use_frames else 0
	var hold_us: int = int(HOLD_SEC * 1_000_000.0)
	var pan_us: int = int(PAN_SEC * 1_000_000.0)
	var total_us: int = hold_us + pan_us

	var start_us: int = Time.get_ticks_usec()
	var last_us: int = start_us
	while true:
		if Time.get_ticks_msec() > _deadline_ms:
			printerr("PERF_ERROR deadline hit during pose ", pose_id, " samples=", frame_ms.size())
			get_tree().quit(4)
			return {}
		await get_tree().process_frame
		var now_us: int = Time.get_ticks_usec()
		var elapsed_us: int = now_us - start_us
		var dt_ms: float = float(now_us - last_us) / 1000.0
		last_us = now_us
		var frame_index: int = frame_ms.size()
		if not use_frames and elapsed_us >= total_us and frame_index > 0:
			break
		if use_frames and frame_index >= total_frames:
			break
		frame_ms.append(dt_ms)
		process_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		physics_ms.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid))
		render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
		draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		visible_objects.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		primitives.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		vram_mb.append(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0)
		# Pan 30 deg linearly after the 3 s hold. Frame mode pan starts after
		# the same 3/7 fraction so the pose still holds first.
		var pan_frac: float = 0.0
		if use_frames:
			var hold_frames: int = int(float(total_frames) * (HOLD_SEC / (HOLD_SEC + PAN_SEC)))
			if frame_index > hold_frames:
				pan_frac = clampf(float(frame_index - hold_frames) / float(maxi(1, total_frames - hold_frames)), 0.0, 1.0)
		else:
			pan_frac = clampf(float(elapsed_us - hold_us) / float(pan_us), 0.0, 1.0)
		if _player != null:
			_player.rotation.y = _pose_start_yaw - deg_to_rad(PAN_DEG) * pan_frac
	_in_pose = false

	frame_ms.sort()
	var record: Dictionary = {
		"event": "pose",
		"pose": pose_id,
		"mode": "frames" if use_frames else "time",
		"fov": snappedf(_cam.fov, 0.001) if _cam != null else _fov,
		"far": snappedf(_cam.far, 0.1) if _cam != null else _far,
		"samples": frame_ms.size(),
		"frame_ms": _stats(frame_ms),
		"fps": _fps_stats(frame_ms),
		"process_ms": _stats(process_ms),
		"physics_ms": _stats(physics_ms),
		"render_cpu_ms": _stats(render_cpu_ms),
		"render_gpu_ms": _stats(render_gpu_ms),
		"draw_calls": int(_median(draw_calls)),
		"visible_objects": int(_median(visible_objects)),
		"primitives": int(_median(primitives)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"vram_mb": snappedf(_median(vram_mb), 0.1),
		"lights": _lights,
		"devices": _devices,
		"chunks": _chunks,
		"samples_ms": frame_ms.duplicate(),
	}
	return record


func _print_summary(records: Array[Dictionary], all_frames: Array[float]) -> void:
	all_frames.sort()
	var summary: Dictionary = {
		"event": "summary",
		"poses": records.size(),
		"samples": all_frames.size(),
		"frame_ms": _stats(all_frames),
		"fps": _fps_stats(all_frames),
		"per_pose": [],
	}
	var per_pose: Array = []
	for rec: Dictionary in records:
		per_pose.append({
			"pose": str(rec.get("pose", "")),
			"p50_ms": (rec.get("frame_ms", {}) as Dictionary).get("p50", 0.0),
			"p95_ms": (rec.get("frame_ms", {}) as Dictionary).get("p95", 0.0),
			"p99_ms": (rec.get("frame_ms", {}) as Dictionary).get("p99", 0.0),
			"one_percent_low_fps": (rec.get("fps", {}) as Dictionary).get("one_percent_low", 0.0),
		})
	summary["per_pose"] = per_pose
	printerr("PERF_SUMMARY " + JSON.stringify(summary))


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"p50": 0.0, "p95": 0.0, "p99": 0.0, "min": 0.0, "max": 0.0, "mean": 0.0}
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for v: float in sorted:
		total += v
	return {
		"p50": snappedf(_percentile(sorted, 0.50), 0.001),
		"p95": snappedf(_percentile(sorted, 0.95), 0.001),
		"p99": snappedf(_percentile(sorted, 0.99), 0.001),
		"min": snappedf(sorted[0], 0.001),
		"max": snappedf(sorted[sorted.size() - 1], 0.001),
		"mean": snappedf(total / float(sorted.size()), 0.001),
	}


func _fps_stats(frame_values: Array[float]) -> Dictionary:
	if frame_values.is_empty():
		return {"mean": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "one_percent_low": 0.0}
	var sorted: Array[float] = frame_values.duplicate()
	sorted.sort()
	var p50: float = _percentile(sorted, 0.50)
	var p95: float = _percentile(sorted, 0.95)
	var p99: float = _percentile(sorted, 0.99)
	# 1% low = mean FPS over the slowest 1% of frames (never fabricated from
	# a single worst frame).
	var slow_count: int = maxi(1, int(ceil(float(sorted.size()) * 0.01)))
	var slow_sum: float = 0.0
	for i: int in range(sorted.size() - slow_count, sorted.size()):
		slow_sum += sorted[i]
	var slow_mean_ms: float = slow_sum / float(slow_count)
	var total: float = 0.0
	for v: float in sorted:
		total += v
	return {
		"mean": snappedf(1000.0 / maxf(total / float(sorted.size()), 0.001), 0.01),
		"p50": snappedf(1000.0 / maxf(p50, 0.001), 0.01),
		"p95": snappedf(1000.0 / maxf(p95, 0.001), 0.01),
		"p99": snappedf(1000.0 / maxf(p99, 0.001), 0.01),
		"one_percent_low": snappedf(1000.0 / maxf(slow_mean_ms, 0.001), 0.01),
	}


func _percentile(sorted: Array[float], pct: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx: int = clampi(int(ceil(float(sorted.size()) * pct)) - 1, 0, sorted.size() - 1)
	return sorted[idx]


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[int(float(sorted.size()) * 0.5)]


func _count_lights(node: Node) -> int:
	var count: int = 1 if node is Light3D else 0
	for child: Node in node.get_children():
		count += _count_lights(child)
	return count


func _pose_by_id(pose_id: String) -> Dictionary:
	for pose: Dictionary in POSES:
		if str(pose.get("id", "")) == pose_id:
			return pose
	return {}


func _selected_poses() -> Array[String]:
	var raw: String = _arg("--poses=", "")
	if raw == "":
		raw = _arg("--pose=", "")
	if raw == "" or raw == "all":
		var all_ids: Array[String] = []
		for pose: Dictionary in POSES:
			all_ids.append(str(pose.get("id", "")))
		return all_ids
	var out: Array[String] = []
	for part: String in raw.split(",", false):
		var clean: String = part.strip_edges()
		if clean != "" and not out.has(clean):
			out.append(clean)
	return out


func _parse_res(raw: String) -> Vector2i:
	var parts: PackedStringArray = raw.to_lower().split("x", false)
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return Vector2i(maxi(320, int(parts[0])), maxi(180, int(parts[1])))
	return Vector2i(1920, 1080)


func _arg(prefix: String, fallback: String) -> String:
	for list: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for arg: String in list:
			if arg.begins_with(prefix):
				return arg.substr(prefix.length()).strip_edges()
	return fallback
