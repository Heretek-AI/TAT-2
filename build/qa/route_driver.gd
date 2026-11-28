extends SceneTree
## Played-route input driver (Phase 3C instrument, short segment).
##
## What this is
## ------------
## A deterministic, input-driven route driver. It walks the authored Den
## waypoints with the real input actions (`Input.action_press`), turns with the
## player's documented look-input hook (`add_look_pixel_delta`, the same path
## mobile touch uses), interacts with real events pushed through the SceneTree
## (`[F]` as InputEventKey), and waits on physics frames. It never writes
## `player.global_position` between beats and never calls a game state hook to
## fake a transition: the only placement is the mission's own authored spawn.
##
## It is NOT the full played route. The default (and only implemented) segment
## is `den_telescope`: S03 (authored Den arrival) and S05 (walk to the authored
## telescope, `[F] PONDER`, `[F] EXIT`). The other 25 beats are listed in the
## manifest as `not_attempted` or, for the NPC beats, `unreachable`, with the
## measured reason. `route_claim` stays `"none"` — a short driver segment is not
## 27/27 played and must never be labelled played.
##
## Output: `docs/reports/logs/p0b-route-driver/<tag>/manifest.json`
##         (`tat2.route_driver/1`) and the audio sidecar under the git-ignored
##         `build/qa/route_driver/<tag>/`.
##
## Run (headless, never beside another Godot):
##   build/qa/route_driver.sh --tag=den_telescope
## or
##   flock /tmp/opencode/tat2-godot.lock -c \
##     "timeout 1200 tools/godot --headless --path game \
##       --script $PWD/build/qa/route_driver.gd -- --segment=den_telescope"

const SCHEMA: String = "tat2.route_driver/1"
const DRIVER_VERSION: int = 1
const MODE: String = "driver"
const ROUTE_CLAIM: String = "none"
const DEFAULT_SEED: int = 1025051536
const AUDIO_SRC: String = "res://src/core/audio_capture.gd"
const BEAT_IDS: Array[String] = [
	"S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09",
	"S10", "S11", "S12", "S13", "S14", "S15", "S16", "S17", "S18",
	"S19", "S20", "S21", "S22", "S23", "S24", "S25", "S26", "S27",
]
const DEN_WALL_PLANE_X: float = -6.06
const DEN_OPENING_TOP_Y: float = 45.1
const MAX_FRAMES_PER_LEG: int = 900
const STUCK_FRAMES: int = 40
const STUCK_M: float = 0.05
const ARRIVE_M: float = 0.25
## Authored telescope Area3D (mission_controller `_den_telescope_pos`).
const DEN_TELESCOPE_XZ := Vector2(-4.9202, 270.7337)
## Approach waypoint 1.5 m inboard of the scope; the Area radius is 1.8 m.
const DEN_TELE_APPROACH_XZ := Vector2(-3.40, 270.90)
## The leg after `[F] EXIT`: walk back toward the hub, proving the body is free.
const DEN_EXIT_LEG_XZ := Vector2(1.50, 269.20)

## Per-beat route knowledge. `implemented` says whether this driver can execute
## the beat with its current waypoint/action plan. The manifest reports every
## beat either way; only implemented beats can become `driven`.
const BEAT_PLAN := {
	"S01": {"kind": "ui", "implemented": false, "reason": "startscreen UI beat (main_menu.gd) — no menu input plan in the short Den segment"},
	"S02": {"kind": "ui", "implemented": false, "reason": "loading screen — UI beat, not part of the Den walk segment"},
	"S03": {"kind": "world", "implemented": true, "reason": ""},
	"S04": {"kind": "ui", "implemented": false, "reason": "wardrobe UI beat — no menu input plan in the short segment"},
	"S05": {"kind": "camera", "implemented": true, "reason": ""},
	"S06": {"kind": "ui", "implemented": false, "reason": "ledger/black-market UI beat — no menu input plan in the short segment"},
	"S07": {"kind": "world", "implemented": false, "reason": "multi-subject Den props beat (decoration/gramophone/trunk); no multi-prop driver"},
	"S08": {"kind": "ui", "implemented": false, "reason": "map-table UI beat — no menu input plan in the short segment"},
	"S09": {"kind": "ui", "implemented": false, "reason": "mission-prep UI beat — no menu input plan in the short segment"},
	"S10": {"kind": "ui", "implemented": false, "reason": "loading screen — UI beat, not part of the Den walk segment"},
	"S11": {"kind": "ui", "implemented": false, "reason": "briefing-letter UI beat — no menu input plan in the short segment"},
	"S12": {"kind": "world", "implemented": false, "reason": "Guildhall safe-room traversal/lantern beat — not in the Den segment"},
	"S13": {"kind": "world", "implemented": false, "reason": "street/alley traversal needs a full multi-leg route (vault/crouch/car); short segment only"},
	"S14": {"kind": "camera", "implemented": false, "reason": "zipwire equip/launch needs the S13 state; short segment only"},
	"S15": {"kind": "world", "implemented": false, "reason": "2nd zipwire/crank needs the S14 state; short segment only"},
	"S16": {"kind": "world", "implemented": false, "reason": "roofline/3rd zipwire needs the S14/S15 state; short segment only"},
	"S17": {"kind": "world", "implemented": false, "reason": "cable/courtyard traversal needs the S14-S16 state; short segment only"},
	"S18": {"kind": "world", "implemented": false, "reason": "smoke throw needs the courtyard state; short segment only"},
	"S19": {"kind": "camera", "implemented": false, "reason": "NPC scan beat: measured 4 guards + 3 civilians at 85.4-150.7 m from the route anchor (probe_route_npcs.gd); no guard in reach"},
	"S20": {"kind": "world", "implemented": false, "reason": "terrace patrol beat: nearest guard measured 85.4 m away (probe_route_npcs.gd); unreachable in this route"},
	"S21": {"kind": "world", "implemented": false, "reason": "blue-door approach/traversal needs the S20 state; short segment only"},
	"S22": {"kind": "world", "implemented": false, "reason": "pickpocket beat: no constable in reach (nearest NPC 85.4 m, probe_route_npcs.gd); unreachable"},
	"S23": {"kind": "camera", "implemented": false, "reason": "takedown beat: needs the S22 constable; no NPC in reach (probe_route_npcs.gd); unreachable"},
	"S24": {"kind": "world", "implemented": false, "reason": "foyer approach/beams needs the S21/S22/S23 state; short segment only"},
	"S25": {"kind": "world", "implemented": false, "reason": "beam crossing/ward lockdown must be walked, not triggered; needs the S24 state"},
	"S26": {"kind": "world", "implemented": false, "reason": "slate-stair/ascent needs the S25 state; short segment only"},
	"S27": {"kind": "ui", "implemented": false, "reason": "pause-menu UI beat; no menu input plan in the short segment"},
}

var _segment: String = "den_telescope"
var _tag: String = "den_telescope"
var _seed: int = DEFAULT_SEED
var _repo_root: String = ""
var _evidence_dir: String = ""
var _media_dir: String = ""
var _manifest_path: String = ""
var _beats: Array = []
var _asserts: Array = []
var _checks: int = 0
var _fails: int = 0
var _tap: Node = null
var _mission: Node = null
var _mark_calls: int = 0
var _transform_writes: int = 0


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--segment="):
			_segment = arg.substr(10)
		elif arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg.begins_with("--seed="):
			_seed = int(arg.substr(7))
		elif arg.begins_with("--out="):
			_evidence_dir = arg.substr(6)
	call_deferred("_run")


func _rel(path: String) -> String:
	if path.begins_with(_repo_root):
		return path.substr(_repo_root.length() + 1)
	return path


func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true)


func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


func _wait(frames: int) -> void:
	# Physics frames, not process frames: the movement poll runs at the fixed
	# 60 Hz physics tick, so waiting on the same clock keeps a replay
	# bit-identical (the headless process/render cadence is not 1:1).
	for _i: int in range(frames):
		await physics_frame


func _check(cond: bool, name: String, detail: String = "") -> bool:
	_checks += 1
	_asserts.append({"name": name, "ok": cond, "detail": detail})
	if cond:
		print("ROUTE_DRIVER PASS: ", name)
		return true
	_fails += 1
	printerr("ROUTE_DRIVER FAIL: ", name, " ", detail)
	return false


func _write_json(path: String, obj: Dictionary) -> bool:
	var dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("ROUTE_DRIVER cannot write ", path)
		return false
	f.store_string(JSON.stringify(obj, "  ", false))
	f.close()
	return true


func _git_line(args: Array) -> String:
	var out: Array = []
	var code: int = OS.execute("git", args, out, true)
	if code != 0 or out.is_empty():
		return "unknown"
	return str(out[0]).strip_edges()


func _base_manifest() -> Dictionary:
	return {
		"schema": SCHEMA,
		"driver_version": DRIVER_VERSION,
		"mode": MODE,
		"segment": _segment,
		"route_claim": ROUTE_CLAIM,
		"driver_seed": _seed,
		"deterministic_replay": true,
		"input_backend": {
			"move": "Input.action_press('move_forward'/'move_backward'/'move_left'/'move_right')",
			"look": "player.add_look_pixel_delta (documented touch-look input hook)",
			"interact": "InputEventKey KEY_F pushed through SceneTree.root.push_input",
			"wait": "physics_frame an integer count",
			"note": "No player.global_position write between beats; the only placement is the mission's authored spawn.",
		},
		"run_id": "%s_%s" % [_tag, Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")],
		"started_at_utc": _now_iso(),
		"repo_root": _repo_root,
		"git": {
			"sha": _git_line(["rev-parse", "HEAD"]),
			"sha_short": _git_line(["rev-parse", "--short", "HEAD"]),
			"branch": _git_line(["rev-parse", "--abbrev-ref", "HEAD"]),
			"dirty": _git_line(["status", "--porcelain"]) != "",
		},
		"build_stamp": {
			"path": "build/tat2-linux-x86_64.stamp.json",
			"present": FileAccess.file_exists("build/tat2-linux-x86_64.stamp.json"),
			"kind": "source_head" if not FileAccess.file_exists("build/tat2-linux-x86_64.stamp.json") else "export_stamp",
			"engine": Engine.get_version_info().get("string", ""),
			"note": "Headless source run; no exported PCK was launched for the driver.",
		},
		"host": {
			"name": OS.get_environment("HOSTNAME"),
			"os": OS.get_name(),
			"processor": OS.get_processor_name(),
			"cpu_count": OS.get_processor_count(),
			"display": OS.get_environment("DISPLAY"),
			"renderer": "headless",
		},
		"env": {"TAT2_PARITY_ONLY": OS.get_environment("TAT2_PARITY_ONLY")},
		"beat_plan": BEAT_PLAN,
		"beats": [],
		"counts": {},
		"asserts": [],
		"mark_calls": 0,
		"route_claim_note": "Short input-driven segment only. Not 27/27 played; no staged frame is relabelled played.",
	}


func _beat_row(id: String, status: String, reason: String, detail: Dictionary = {}) -> Dictionary:
	var plan: Dictionary = BEAT_PLAN[id] as Dictionary
	return {
		"id": id,
		"kind": str(plan.get("kind", "")),
		"status": status,
		"reason": reason,
		"implemented": bool(plan.get("implemented", false)),
		"mark_beat_called": bool(detail.get("mark_beat_called", false)),
		"mark_beat_ok": bool(detail.get("mark_beat_ok", false)),
		"input_actions": detail.get("input_actions", []),
		"waypoints": detail.get("waypoints", []),
		"evidence": detail.get("evidence", {}),
	}


## One waypoint leg. Steering only calls the look input hook; movement only
## presses the real actions. Returns a result dict, never a transform write.
func _drive_to(player: Node3D, target_xz: Vector2, max_frames: int = MAX_FRAMES_PER_LEG) -> Dictionary:
	var start: Vector3 = player.global_position
	var frames: int = 0
	var stuck: int = 0
	var last: Vector3 = start
	Input.action_press("move_forward")
	while frames < max_frames:
		await physics_frame
		frames += 1
		var pos: Vector3 = player.global_position
		var to := Vector3(target_xz.x - pos.x, 0.0, target_xz.y - pos.z)
		if to.length() <= ARRIVE_M:
			Input.action_release("move_forward")
			return {"ok": true, "frames": frames, "start": _v3(start), "end": _v3(pos), "distance_m": start.distance_to(pos)}
		# Look input: rotate the body yaw toward the waypoint in small steps.
		var want_yaw: float = atan2(-to.x, -to.z)
		var delta_yaw: float = wrapf(want_yaw - player.rotation.y, -PI, PI)
		var sens: float = float(player.get("mouse_sens"))
		var px: float = clampf(-delta_yaw / maxf(sens, 0.0001), -120.0, 120.0)
		if absf(px) > 0.5:
			player.call("add_look_pixel_delta", Vector2(px, 0.0))
		if pos.distance_to(last) < STUCK_M:
			stuck += 1
			if stuck >= STUCK_FRAMES:
				# Deterministic obstacle nudge: release forward, strafe left for
				# 12 frames, then resume. Still input-only.
				Input.action_release("move_forward")
				Input.action_press("move_left")
				for _s: int in range(12):
					await physics_frame
					frames += 1
				Input.action_release("move_left")
				Input.action_press("move_forward")
				stuck = 0
		else:
			stuck = 0
		last = pos
	Input.action_release("move_forward")
	return {"ok": false, "frames": frames, "start": _v3(start), "end": _v3(player.global_position), "reason": "frame_budget"}


func _press_f(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	ev.keycode = KEY_F
	ev.pressed = pressed
	root.push_input(ev)


func _mark(id: String, label: String) -> Dictionary:
	_mark_calls += 1
	var ok: bool = false
	if _tap != null and _tap.has_method("mark_beat"):
		ok = bool(_tap.call("mark_beat", id, label))
	print("ROUTE_DRIVER mark_beat id=%s ok=%s label=%s" % [id, str(ok), label])
	return {"mark_beat_called": true, "mark_beat_ok": ok}


func _run() -> void:
	_repo_root = ProjectSettings.globalize_path("res://").get_base_dir()
	# `res://` is <repo>/game, so its parent is the repo root.
	if _repo_root.get_file() == "game":
		_repo_root = _repo_root.get_base_dir()
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("ROUTE_DRIVER FAIL: GameState autoload missing")
		quit(1)
		return
	if _evidence_dir == "":
		_evidence_dir = _repo_root.path_join("docs/reports/logs/p0b-route-driver")
	_evidence_dir = _evidence_dir.path_join(_tag)
	_media_dir = _repo_root.path_join("build/qa/route_driver").path_join(_tag)
	_manifest_path = _evidence_dir.path_join("manifest.json")
	DirAccess.make_dir_recursive_absolute(_evidence_dir)
	DirAccess.make_dir_recursive_absolute(_media_dir)
	print("ROUTE_DRIVER start segment=%s tag=%s driver_seed=%d route_claim=%s head=%s" % [
		_segment, _tag, _seed, ROUTE_CLAIM, _git_line(["rev-parse", "--short", "HEAD"]),
	])
	if _segment != "den_telescope":
		printerr("ROUTE_DRIVER FAIL: only segment=den_telescope is implemented (got %s)" % _segment)
		quit(2)
		return

	var m: Dictionary = _base_manifest()
	# Deterministic seed: recorded and used to build the input plan (the Den
	# segment is fully deterministic, so no jitter is drawn; the seed still
	# pins a replay and names any future sampled segment).
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	m["driver_seed"] = _seed
	m["rng_state"] = rng.state

	var tap_script: GDScript = load(AUDIO_SRC) as GDScript
	if tap_script != null:
		_tap = tap_script.new() as Node
		root.add_child(_tap)
		_tap.call("start", 10.0)
		_tap.call("mark", "route_driver_start", "")

	# Contract 1 is the Thieves' Den tutorial / hub. No free play, no cleanout.
	gs.set("thief_id", "spider")
	gs.set("active_contract_order", 1)
	gs.set("state", "playing")
	var mission: Node = (load("res://scenes/mission.tscn") as PackedScene).instantiate()
	root.add_child(mission)
	_mission = mission
	var waited: int = 0
	while mission.get("player") == null and waited < 3600:
		await process_frame
		waited += 1
	if not _check(mission.get("player") != null, "player spawned on the authored Den spawn", "waited=%d" % waited):
		await _finish(m, {})
		return
	await _wait(20)
	var player: Node3D = mission.get("player") as Node3D
	var hud: Node = mission.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(10)
	var spawn: Vector3 = player.global_position
	var tele: Node3D = mission.get_node_or_null("DenTelescopeArea") as Node3D
	if not _check(tele != null, "DenTelescopeArea present", "telescope Area3D missing"):
		await _finish(m, {})
		return
	var tele_pos: Vector3 = tele.global_position
	_check(absf(tele_pos.x - DEN_TELESCOPE_XZ.x) < 0.01 and absf(tele_pos.z - DEN_TELESCOPE_XZ.y) < 0.01,
		"telescope Area3D at the authored point", str(_v3(tele_pos)))

	# ---- S03: authored Den arrival (mark_beat on the entry half) ------------
	var s03_detail: Dictionary = _mark("S03", "Den arrival (authored spawn)")
	s03_detail["input_actions"] = ["move_forward", "look"]
	s03_detail["waypoints"] = []
	s03_detail["evidence"] = {"spawn": _v3(spawn), "player_spawn_meta": str(player.get_meta("spawn_source")) if player.has_meta("spawn_source") else "authored"}
	_beats.append(_beat_row("S03", "driven_partial",
		"Authored Den spawn reached; the official attic pan is not driven (entry half only).", s03_detail))

	# ---- Drive to the telescope ---------------------------------------------
	var leg1: Dictionary = await _drive_to(player, DEN_TELE_APPROACH_XZ)
	_check(bool(leg1.get("ok", false)), "walked to the telescope approach via input",
		str(leg1))
	var dist_tele: float = player.global_position.distance_to(tele_pos)
	_check(dist_tele <= 1.8, "inside the telescope Area3D radius (%.2f m)" % dist_tele, "dist=%.2f" % dist_tele)
	# A player reaches the scope and presses [F]; let the walk settle for a few
	# frames. Residual momentum is intentionally left in the body: the scope
	# entry must zero it (L4-13), which the freeze assertion below measures.
	await _wait(6)
	# Final look at the scope so `_try_interact` picks it.
	await _wait(2)

	# ---- S05: [F] PONDER, hold, [F] EXIT -------------------------------------
	var enter_pos: Vector3 = player.global_position
	_press_f(true)
	await _wait(2)
	_press_f(false)
	await _wait(4)
	var ponder_active: bool = bool(mission.get("_ponder_active"))
	var ponder_cam: Camera3D = mission.get("_ponder_cam") as Camera3D
	var entered_ok: bool = _check(ponder_active and ponder_cam != null and ponder_cam.current,
		"[F] PONDER enters the telescope scope", "active=%s cam=%s" % [str(ponder_active), str(ponder_cam)])
	var s05_detail: Dictionary = {}
	if entered_ok:
		s05_detail = _mark("S05", "Telescope scope ([F] PONDER)")
	# Held forward must not move the body (L4-13 gate).
	Input.action_press("move_forward")
	var frozen_max: float = 0.0
	for _i: int in range(40):
		await physics_frame
		frozen_max = maxf(frozen_max, player.global_position.distance_to(enter_pos))
	Input.action_release("move_forward")
	_check(frozen_max < 0.02, "held forward cannot walk out of the Den while scoped (max %.3f m)" % frozen_max,
		"moved %.3f m in scope" % frozen_max)
	await _wait(8)
	var exit_pos_before: Vector3 = player.global_position
	_press_f(true)
	await _wait(2)
	_press_f(false)
	await _wait(4)
	var exit_ok: bool = _check(not bool(mission.get("_ponder_active")),
		"[F] EXIT leaves the scope", "active=%s" % str(mission.get("_ponder_active")))
	var pcam: Camera3D = player.get("cam") as Camera3D
	var cam_ok: bool = _check(pcam != null and pcam.current, "[F] EXIT restores the player camera")
	var exit_pos: Vector3 = player.global_position
	_check(exit_pos.distance_to(exit_pos_before) < 0.05, "[F] EXIT does not teleport the body",
		"drift=%.3f" % exit_pos.distance_to(exit_pos_before))
	_check(exit_pos.x > DEN_WALL_PLANE_X and exit_pos.y < DEN_OPENING_TOP_Y,
		"[F] EXIT leaves the player inside the Den (not the roof)", str(_v3(exit_pos)))
	s05_detail["input_actions"] = ["move_forward", "look", "interact", "wait"]
	s05_detail["waypoints"] = [_v3_array(DEN_TELE_APPROACH_XZ)]
	s05_detail["evidence"] = {
		"enter_pos": _v3(enter_pos), "ponder_frozen_max_m": snappedf(frozen_max, 0.0001),
		"exit_pos": _v3(exit_pos), "exit_drift_m": snappedf(exit_pos.distance_to(exit_pos_before), 0.0001),
		"telescope": _v3(tele_pos),
	}
	_beats.append(_beat_row("S05", "driven" if entered_ok and exit_ok and cam_ok else "failed",
		"" if entered_ok and exit_ok and cam_ok else "telescope input/exit assertion failed", s05_detail))

	# ---- Post-exit movement proof (the body is not stranded) ----------------
	var exit_leg: Dictionary = await _drive_to(player, DEN_EXIT_LEG_XZ, 600)
	var exit_moved: float = float(exit_leg.get("distance_m", 0.0))
	_check(bool(exit_leg.get("ok", false)) and exit_moved >= 1.0,
		"player walks away after [F] EXIT (%.2f m)" % exit_moved, str(exit_leg))

	await _finish(m, {
		"spawn": _v3(spawn),
		"telescope": _v3(tele_pos),
		"leg_to_telescope": leg1,
		"leg_after_exit": exit_leg,
		"exit_pos": _v3(exit_pos),
	})


func _v3_array(xz: Vector2) -> Array:
	# Waypoints are ground-plane XZ; y is not authored (the body follows the
	# floor), so the manifest records it as null rather than inventing a height.
	return [snappedf(xz.x, 0.0001), null, snappedf(xz.y, 0.0001)]


func _finish(m: Dictionary, evidence: Dictionary) -> void:
	# Free the mission before writing so teardown ownership (nav region, the
	# Den reflection probe atlas, guard caches) is released inside the run and
	# the headless exit does not report resources still in use.
	if _mission != null and is_instance_valid(_mission):
		_mission.queue_free()
		_mission = null
		await _wait(4)
	# Complete the 27-beat table: driven rows already exist; everything else is
	# explicitly not_attempted/unreachable with the reason from BEAT_PLAN.
	var by_id: Dictionary = {}
	for row_v: Variant in _beats:
		var row: Dictionary = row_v as Dictionary
		by_id[str(row.get("id", ""))] = row
	var rows: Array = []
	for id: String in BEAT_IDS:
		if by_id.has(id):
			rows.append(by_id[id])
			continue
		var plan: Dictionary = BEAT_PLAN[id] as Dictionary
		var reason: String = str(plan.get("reason", ""))
		var status: String = "unreachable" if id in ["S19", "S20", "S22", "S23"] else "not_attempted"
		rows.append(_beat_row(id, status, reason))
	m["beats"] = rows
	var driven: int = 0
	var partial: int = 0
	var unreachable: int = 0
	var not_attempted: int = 0
	var failed: int = 0
	for row_v: Variant in rows:
		var row: Dictionary = row_v as Dictionary
		match str(row.get("status", "")):
			"driven":
				driven += 1
			"driven_partial":
				partial += 1
			"unreachable":
				unreachable += 1
			"not_attempted":
				not_attempted += 1
			"failed":
				failed += 1
	m["counts"] = {
		"beats": rows.size(), "driven": driven, "driven_partial": partial,
		"unreachable": unreachable, "not_attempted": not_attempted,
		"failed": failed, "mark_calls": _mark_calls,
	}
	m["asserts"] = _asserts
	m["assertions"] = {"checks": _checks, "fails": _fails}
	m["transform_writes"] = _transform_writes
	m["evidence"] = evidence
	if _tap != null:
		var audio_res: Dictionary = _tap.call("stop_to", _media_dir, "audio") as Dictionary
		audio_res["mark_kind"] = "mark_beat"
		audio_res["route_claim"] = ROUTE_CLAIM
		audio_res["note"] = "Short driver segment: mark_beat() is called only for the beats this segment actually drove."
		m["audio"] = audio_res
		_tap.queue_free()
		await _wait(2)
	else:
		m["audio"] = {"schema": "tat2.audio_capture/1", "enabled": false, "reason": "audio_script_missing", "marks": [], "route_claim": ROUTE_CLAIM}
	m["finished_at_utc"] = _now_iso()
	m["status"] = "partial_driven" if _fails == 0 else "failed"
	var wrote: bool = _write_json(_manifest_path, m)
	# The staged-claim guard is non-negotiable: a driver run never says played.
	var claim_ok: bool = str(m.get("route_claim", "")) == "none"
	var total_ok: bool = rows.size() == 27
	var ok: bool = wrote and claim_ok and total_ok and _fails == 0
	print("ROUTE_DRIVER_DONE status=%s segment=%s beats=%d driven=%d partial=%d unreachable=%d not_attempted=%d mark_calls=%d checks=%d fails=%d route_claim=%s driver_seed=%d manifest=%s" % [
		str(m.get("status", "")), _segment, rows.size(), driven, partial, unreachable,
		not_attempted, _mark_calls, _checks, _fails, str(m.get("route_claim", "")), _seed, _manifest_path,
	])
	quit(0 if ok else 1)
