extends SceneTree
## P0b route runner v1 — a STAGED/MIXED 27-beat capture, port side.
##
## What this is, and what it is not
## --------------------------------
## `build/qa/p0b_capture.gd` captures six fixed poses but has no multi-beat
## runner. A full *played* 27-beat route is blocked by remaining port gaps:
##   * no NPC population near the route (4 guards + 3 civilians at 85.4-150.7 m
##     at the current HEAD, C4-08/L4-08; re-measured by probe_route_npcs.gd);
##   * no full continuous input driver for S13-S26 traversal (a short
##     input-driven Den/telescope segment exists in build/qa/route_driver.gd).
## L4-13 (telescope `[F] EXIT` stranding) is fixed in Phase 3C; the staged
## runner still does not drive the exit key.
## This runner therefore plans to stage the beats that have a real UI/API hook,
## records every other beat as deferred with a reason, and never claims a played
## route.
##
## `route_claim` is always "none". The official S01..S27 start/end times are
## provenance anchors from the reference clip (`KEYFRAME_INDEX.md` §2, mirrored
## by `build/qa/p0b_audio_stats.py` REFERENCE_BEATS). They are NOT wall-clock
## targets: this run does not align to them. Staged frames call the audio tap's
## generic mark() only; the tap's S01..S27 beat-marker entry point is never
## called, so a fixed/staged frame cannot claim a played-beat alignment.
##
## Modes
## -----
##   --mode=dry-run    manifest only; no scene, no GPU render (headless-safe)
##   --mode=self-test  table/schema checks; no scene, no GPU render
##   --mode=capture    real Vulkan staging; the owner runs it under Xvfb
##
## The wrapper `build/qa/p0b_route.sh` owns the shared flock, the Xvfb display
## and the timeout; prefer it over a direct invocation.
##
## Manifest: `tat2.p0b_route/1`, a compatible superset of
## `tat2.p0b_capture/1`: every provenance field is present, but `poses[]` is
## replaced by `beats[]` (a beat may carry its own `frames[]`). It is not a
## drop-in input for `p0b_roi_stats.py --validate-manifest`/`--all`. A later
## lane maps the 27 rows onto the 120-row scorecard; this runner only records
## what was staged.

const SCHEMA: String = "tat2.p0b_route/1"
const BASE_SCHEMA: String = "tat2.p0b_capture/1"
const MODE_STAGED: String = "staged"
const ROUTE_CLAIM: String = "none"
const SIZE := Vector2i(1920, 1080)
const SHIPPED_FOV: float = 54.54
const EYE_OFFSET: float = 1.67
const SETTLE_FRAMES: int = 60
const CAPTURE_FRAMES: int = 5
const OFFICIAL_CLIP_SEED: int = 1025051536
const AUDIO_SRC: String = "res://src/core/audio_capture.gd"
const ROUTE_BEAT_COUNT: int = 27

const BEAT_IDS: Array[String] = [
	"S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09",
	"S10", "S11", "S12", "S13", "S14", "S15", "S16", "S17", "S18",
	"S19", "S20", "S21", "S22", "S23", "S24", "S25", "S26", "S27",
]

## The official clip, recorded for provenance only — this runner captures
## stills, not video, and makes no live-reference claim.
const VIDEO := {
	"source_clip": "clip_1,795,033,698,901.mp4 (docs/reference/clip_1795033698901/KEYFRAME_INDEX.md §1)",
	"duration_s": 225.642333,
	"native_resolution": [3840, 2160],
	"frame_rate": {"r_frame_rate": "179/6 (29.833 fps)", "avg_fps": 29.672, "nb_frames": 6696},
	"audio": {"codec": "aac lc", "sample_rate": 48000, "channels": 2},
	"keyframes": 30,
	"note": "Reference metadata only. The runner stages stills; nothing here is a played-route or video capture.",
}

## Official 27-beat table. `plan = "staged"` means v1 plans to stage the beat
## through the hook in `hook`; `plan = "deferred"` means it is out of scope for
## v1 and `reason` says exactly why. `frames` are the staged frames of a
## planned beat:
##   {"name": String, "ui": true}                      a CanvasLayer/Control screen
##   {"name": String, "eye": Vector3, "target": Vector3} a world camera pose
##   {"name": String, "mission_cam": "_ponder_cam"}     the mission's own camera
## Names/paths/coordinates are labelled `evidence` at capture time.
const BEATS := {
	"S01": {
		"label": "Startscreen (main menu)",
		"start": 0.00, "end": 2.15, "class": "ui", "ref": "KF01",
		"plan": "staged",
		"hook": "main_menu.gd instantiate; the real PLAY/SETTINGS/CREDITS/QUIT menu over its 3D backdrop",
		"reason": "",
		"frames": [{"name": "startscreen", "ui": true}],
	},
	"S02": {
		"label": "Loading screen 1",
		"start": 2.15, "end": 2.60, "class": "ui", "ref": "KF12",
		"plan": "staged",
		"hook": "loading_screen.gd instantiate + start_loading('', '', 'guildhall') + set_progress(0.62, '')",
		"reason": "",
		"frames": [{"name": "loading_1", "ui": true}],
	},
	"S03": {
		"label": "Thieves' Den entry / pan",
		"start": 2.60, "end": 6.57, "class": "world", "ref": "KF02",
		"plan": "staged",
		"hook": "mission.tscn with GameState contract_order=1 map=thieves_den; fixed Den-wide camera (capture_e2e_parity Den pose)",
		"reason": "",
		"frames": [{"name": "den_entry", "eye": Vector3(4.2, 41.9, 271.2), "target": Vector3(-4.5, 41.5, 271.5)}],
	},
	"S04": {
		"label": "Wardrobe UI",
		"start": 6.57, "end": 18.24, "class": "ui", "ref": "KF03/KF04",
		"plan": "staged",
		"hook": "mission_controller.open_wardrobe_ui() -> wardrobe_ui.open_customizer()",
		"reason": "",
		"frames": [{"name": "wardrobe", "ui": true}],
	},
	"S05": {
		"label": "Thieves' Den telescope sky (no exit)",
		"start": 18.24, "end": 26.58, "class": "camera", "ref": "KF05/KF06",
		"plan": "staged",
		"hook": "mission_controller.toggle_telescope_ponder(); the mission's _ponder_cam; the staged runner captures the scope and does not drive the [F] EXIT key (the live exit is fixed; the input assertion is probe_den_window.gd)",
		"reason": "",
		"frames": [{"name": "telescope_sky", "mission_cam": "_ponder_cam"}],
	},
	"S06": {
		"label": "Ledger / Black Market",
		"start": 26.58, "end": 38.17, "class": "ui", "ref": "KF07/KF08",
		"plan": "staged",
		"hook": "mission_controller.open_ledger_ui() -> ledger_ui._show_tab(0)/(1)",
		"reason": "",
		"frames": [{"name": "journal", "ui": true}, {"name": "black_market", "ui": true}],
	},
	"S07": {
		"label": "Den props, decals & gramophone",
		"start": 38.17, "end": 51.08, "class": "world", "ref": "KF09",
		"plan": "deferred",
		"hook": "",
		"reason": "Multi-subject beat: decoration swap (DenDecorationPedestal.interact), boot-trail decal crossing, gramophone ON (gram area -> AudioManager.toggle_gramophone), trunk-treasure cycling, then a walk to the map table. The two interact hooks exist, but there is no camera/pan driver for the sequence; a single prop frame would misrepresent the beat. Deferred to a v2 lane, not faked.",
		"frames": [],
	},
	"S08": {
		"label": "Map table & confirmation modal",
		"start": 51.08, "end": 56.08, "class": "ui", "ref": "KF10",
		"plan": "staged",
		"hook": "mission_controller.set_den_selected_map('guildhall') + open_contract_table_ui() + contract_table_ui.open_confirm(); Novice/Solo kept",
		"reason": "",
		"frames": [{"name": "map_table", "ui": true}, {"name": "confirm", "ui": true}],
	},
	"S09": {
		"label": "Mission preparation",
		"start": 56.08, "end": 64.80, "class": "ui", "ref": "KF11",
		"plan": "staged",
		"hook": "mission_prep_ui.gd instantiate + open_prep('guildhall', 1, 'Solo', 2, true) (free play: Contract Inactive)",
		"reason": "",
		"frames": [{"name": "mission_prep", "ui": true}],
	},
	"S10": {
		"label": "Loading screen 2",
		"start": 64.80, "end": 69.44, "class": "ui", "ref": "KF12",
		"plan": "staged",
		"hook": "loading_screen.gd instantiate + start_loading('', '', 'guildhall') + set_progress(0.31, '')",
		"reason": "",
		"frames": [{"name": "loading_2", "ui": true}],
	},
	"S11": {
		"label": "Briefing letter",
		"start": 69.44, "end": 70.81, "class": "ui", "ref": "KF13",
		"plan": "staged",
		"hook": "mission.tscn free play Mission.Guildhall.LootTheRoom on contract_order=2 map=guildhall; hud.is_mission_letter_open() (GameState.request_mission_letter -> hud.show_mission_letter)",
		"reason": "",
		"frames": [{"name": "briefing_letter", "ui": true}],
	},
	"S12": {
		"label": "Guildhall safe-room HUD / lantern / portal",
		"start": 70.81, "end": 80.10, "class": "world", "ref": "KF14",
		"plan": "staged",
		"hook": "safe_room_dressing.gd (mission_controller._add_guildhall_saferoom_dressing) + SafeRoomLanternStation.set_lit(true, false) + authored TATSafeRoomPlayerStart_0 pose",
		"reason": "",
		"frames": [{"name": "safe_room", "eye": Vector3(127.2747, 27.1394, -5.3296), "target": Vector3(125.70, 26.70, -2.29)}],
	},
	"S13": {
		"label": "Street / alley approach, vintage car & gate alert",
		"start": 80.10, "end": 99.30, "class": "world", "ref": "KF15",
		"plan": "deferred",
		"hook": "",
		"reason": "Needs a continuous movement driver from the safe-room catwalk to the alley: vault, wet-cobble sprint, crouch, and the car [F] INTERACT at the wrought-iron gate. No multi-beat input driver exists. The authored BARRON'S DEMOLITION banner asset is also absent (HARD_LIMIT, docs/reports/p1-integration-20261126.md).",
		"frames": [],
	},
	"S14": {
		"label": "ZipWire [1] equip, gate headlights, 1st launch",
		"start": 99.30, "end": 109.50, "class": "camera", "ref": "KF16",
		"plan": "deferred",
		"hook": "",
		"reason": "Requires [1] equip, gate aim, the 1st zipwire launch and a planter landing. The zipwire traversal has no stable still-stage hook without an input driver.",
		"frames": [],
	},
	"S15": {
		"label": "2nd ZipWire launch & crank ascent",
		"start": 109.50, "end": 118.50, "class": "world", "ref": "KF17",
		"plan": "deferred",
		"hook": "",
		"reason": "Requires the 2nd zipwire shot plus ~7 s of crank input ([HOLD] CRANK) to the roof ridge; depends on S14 state and a continuous driver.",
		"frames": [],
	},
	"S16": {
		"label": "Roofline traversal & 3rd ZipWire",
		"start": 118.50, "end": 131.00, "class": "world", "ref": "none",
		"plan": "deferred",
		"hook": "",
		"reason": "Roofline/chimney traversal and the 3rd zipwire to the gate pillar; depends on S14/S15 state and has no input driver. The reference table links no keyframe to S16.",
		"frames": [],
	},
	"S17": {
		"label": "Gate pillar gear plate & courtyard descent",
		"start": 131.00, "end": 143.30, "class": "world", "ref": "KF18",
		"plan": "deferred",
		"hook": "",
		"reason": "Cable crossing, gear-plate landing and the courtyard drop that takes authored fall damage; cannot be staged without the prior zipwire state and physics-driven traversal.",
		"frames": [],
	},
	"S18": {
		"label": "Smoke bomb [2] throw & plume",
		"start": 143.30, "end": 150.70, "class": "world", "ref": "KF19/KF20",
		"plan": "deferred",
		"hook": "",
		"reason": "Needs the throw input and the plume VFX; Niagara is a labelled procedural stand-in (HL-1, docs/REFERENCE_BASELINE.md). No input driver.",
		"frames": [],
	},
	"S19": {
		"label": "Vistara Diamond [4] scan pulse",
		"start": 150.70, "end": 153.00, "class": "camera", "ref": "KF21/KF22",
		"plan": "deferred",
		"hook": "",
		"reason": "Requires a live guard at the portico steps plus the [4] scan input (RED->GREEN silhouette). The staged route has no NPC in view: 4 guards + 3 civilians spawn at 48–151 m (C4-08/L4-08).",
		"frames": [],
	},
	"S20": {
		"label": "Side wing, MACLEOD sign & terrace patrol",
		"start": 153.00, "end": 174.50, "class": "world", "ref": "KF23",
		"plan": "deferred",
		"hook": "",
		"reason": "A ~21 s balcony/terrace traversal with a patrol guard; no continuous driver and no NPC on the staged route.",
		"frames": [],
	},
	"S21": {
		"label": "Arched portico, blue double doors & scaffolding",
		"start": 174.50, "end": 184.50, "class": "world", "ref": "KF24",
		"plan": "deferred",
		"hook": "",
		"reason": "Needs the approach plus [F] OPEN / [HOLD] LOCK on the blue double doors and a walk-through. The door content is proven by the P1 probes, but the staged runner cannot drive the approach.",
		"frames": [],
	},
	"S22": {
		"label": "Fireplace parlor stealth & pickpocket",
		"start": 184.50, "end": 197.10, "class": "world", "ref": "KF25",
		"plan": "deferred",
		"hook": "",
		"reason": "Requires a live constable, a crouch approach and the [F] PICK POCKET hold; no NPC on the staged route and no input driver.",
		"frames": [],
	},
	"S23": {
		"label": "Guard takedown",
		"start": 197.10, "end": 202.00, "class": "camera", "ref": "KF26",
		"plan": "deferred",
		"hook": "",
		"reason": "Requires the S22 guard and the [HOLD] TAKEDOWN lunge camera. The rig was repaired, but a takedown needs a live guard and input; it is not stageable as a still.",
		"frames": [],
	},
	"S24": {
		"label": "Foyer approach & sweeping security beams",
		"start": 202.00, "end": 209.00, "class": "world", "ref": "KF27",
		"plan": "staged",
		"hook": "mission.tscn map=guildhall; live KF27 foyer poses: upper_foyer + yaw180 (p0b foyer slots) + foyer_beam at the authored C_107 beam card cue; player camera, camera_source=player",
		"reason": "",
		"frames": [
			{"name": "upper_foyer", "eye": Vector3(27.0, 29.67, -50.0), "target": Vector3(27.0, 29.67, -60.0)},
			{"name": "yaw180", "eye": Vector3(27.0, 29.67, -50.0), "target": Vector3(27.0, 29.67, -40.0)},
			{"name": "foyer_beam", "eye": Vector3(27.0, 29.67, -55.0), "target": Vector3(23.27, 29.76, -57.4)},
		],
	},
	"S25": {
		"label": "Beam trigger, purple ward, green arcane lock",
		"start": 209.00, "end": 217.40, "class": "world", "ref": "KF28",
		"plan": "deferred",
		"hook": "",
		"reason": "Requires the player to walk through the foreground beam so the authored signal seals the ward and vine lock. The lockdown hooks exist (_spawn_foyer_lockdown, security_beam.beam_triggered), but firing them directly would be a faked played beat; deferred.",
		"frames": [],
	},
	"S26": {
		"label": "Crimson alarm spotlight & slate-stair ascent",
		"start": 217.40, "end": 221.90, "class": "world", "ref": "KF29",
		"plan": "deferred",
		"hook": "",
		"reason": "Depends on S25 (breaking a barrier triggers the crimson alarm) and a stair traversal to the upper landing; no input driver.",
		"frames": [],
	},
	"S27": {
		"label": "Pause menu",
		"start": 221.90, "end": 225.64, "class": "ui", "ref": "KF30",
		"plan": "staged",
		"hook": "hud.toggle_pause() over the loaded Guildhall mission; the audio tap is switched to PROCESS_MODE_ALWAYS before the pause so marks keep draining",
		"reason": "",
		"frames": [{"name": "pause", "ui": true}],
	},
}

## Ids the capture dispatcher stages, in capture order. Kept separate from
## BEATS so `--self-test` can prove the plan and the dispatcher agree.
const STAGED_IDS: Array[String] = [
	"S01", "S02", "S03", "S04", "S06", "S08", "S05",
	"S09", "S10", "S11", "S12", "S24", "S27",
]

## The p0b `beam_close` pose is the Lounge C_57 card
## (39.0,28.82,-28.97)->(42.4,28.9,-28.97), NOT the KF27 foyer beam. It is
## captured as a labelled extra (ref_keyframe=null, subject="Lounge C_57 beam")
## and is never presented as an S24 / KF27 frame.
const LOUNGE_BEAM_ID: String = "lounge_beam_close"
const LOUNGE_BEAM_EYE := Vector3(39.0, 28.82, -28.97)
const LOUNGE_BEAM_TARGET := Vector3(42.4, 28.9, -28.97)

## Authored Guildhall foyer beam card in the upper_foyer view:
## `guildhall/Guildhall_Gameplay:BP_Detector_LightBeam_C_107` at
## (23.27, 29.76, -57.4), 4.4 m from the (27,29.67,-50) eye
## (`build/qa/w9/facts-a4.md:576`). The KF27 foyer-beam cue looks at it from
## (27,29.67,-55). If no visible `lightbeam_cards` member is within
## FOYER_BEAM_CARD_TOL_M of that authored point, the frame is recorded as a
## failed planned frame with `beam_visible=false` — the Lounge pose is not a
## substitute.
const FOYER_BEAM_CARD_POS := Vector3(23.27, 29.76, -57.4)
const FOYER_BEAM_CARD_TOL_M: float = 1.5

var _mode: String = "capture"
var _tag: String = ""
var _seed_arg: String = "derived"
var _run_id: String = ""
var _out_dir: String = ""
var _manifest_path: String = ""
var _repo_root: String = ""
var _checks: int = 0
var _fails: int = 0
var _frame_seq: int = 0
var _capture_start_msec: int = 0
var _extra_poses: Array = []


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
		"display_server_headless": DisplayServer.get_name().to_lower() == "headless",
		"audio_driver": AudioServer.get_driver_name(),
		"audio_mix_rate": AudioServer.get_mix_rate(),
		"configured_rendering_driver": str(ProjectSettings.get_setting("rendering/rendering_device/driver", "")),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"video_vendor": RenderingServer.get_video_adapter_vendor(),
		"video_api": RenderingServer.get_video_adapter_api_version(),
		"cmdline": OS.get_cmdline_args(),
	}


func _env_snapshot() -> Dictionary:
	var keys: Array[String] = [
		"TAT2_AO", "TAT2_COLLISION", "TAT2_PREP_STAGE", "TAT2_ROUGH_BAKE",
		"TAT2_STATETREE", "TAT2_PARITY_ONLY", "TAT2_GC_LAYERS",
		"DISPLAY", "XDG_SESSION_TYPE", "XDG_DATA_HOME", "VK_ICD_FILENAMES",
		"P0B_ROUTE_OUT", "P0B_ROUTE_MANIFEST",
	]
	var out: Dictionary = {}
	for k: String in keys:
		var v: String = _env(k)
		if v != "":
			out[k] = v
	return out


## Read-only view of the owner's save. The runner never calls write_save; the
## save/profile fields let a later re-score separate an owner-restore run from a
## fresh-save run without touching the file.
func _store_probe() -> Dictionary:
	var path: String = ProjectSettings.globalize_path("user://tat2_save.json")
	var exists: bool = FileAccess.file_exists(path)
	var sha: String = FileAccess.get_sha256(path) if exists else ""
	var save: Node = root.get_node_or_null("/root/SaveSystem")
	var data: Dictionary = {}
	var settings: Dictionary = {}
	var load_failed: bool = false
	var schema_v: int = 0
	if save != null:
		var d: Variant = save.get("data")
		if d is Dictionary:
			data = d as Dictionary
		if save.has_method("has_load_failure"):
			load_failed = bool(save.call("has_load_failure"))
		if save.has_method("get_settings"):
			var s: Variant = save.call("get_settings")
			if s is Dictionary:
				settings = s as Dictionary
		schema_v = int(data.get("save_schema", 0))
	return {
		"source": "fresh" if (not exists or load_failed) else "owner_restore",
		"path": path,
		"exists": exists,
		"sha256": sha,
		"schema_version": schema_v,
		"load_failed": load_failed,
		"profile": {
			"level": int(data.get("level", 0)),
			"xp": int(data.get("xp", 0)),
			"currency": int(data.get("currency", 0)),
			"completed_contracts": (data.get("completed_contracts", {}) as Dictionary).size() if data.get("completed_contracts") is Dictionary else 0,
			"unlocked_tools": (data.get("unlocked_tools", []) as Array).size() if data.get("unlocked_tools") is Array else 0,
			"unlocked_perks": (data.get("unlocked_perks", []) as Array).size() if data.get("unlocked_perks") is Array else 0,
			"unlocked_cosmetics": (data.get("unlocked_cosmetics", []) as Array).size() if data.get("unlocked_cosmetics") is Array else 0,
		},
		"settings": {
			"fov": float(settings.get("fov", SHIPPED_FOV)),
			"master_volume": float(settings.get("master_volume", 0.8)),
			"graphics_quality": str(settings.get("graphics_quality", "")),
		},
		"note": "Read-only: this runner never calls SaveSystem.write_save. source=owner_restore when a save file existed and loaded cleanly at boot, else fresh.",
	}


func _base_manifest(dry_run: bool, self_test: bool) -> Dictionary:
	var sha: String = _git_line(["rev-parse", "HEAD"])
	var dirty_raw: String = _git_line(["status", "--porcelain", "--untracked-files=no"], "")
	var gpu: Dictionary
	if dry_run or self_test:
		# Headless modes must not run nvidia-smi: no GPU is touched or rendered.
		gpu = {
			"queried": false,
			"reason": "headless",
			"used_by_capture": false,
			"query": "",
			"command": "",
			"available": false,
			"rows": [],
		}
	else:
		gpu = _gpu()
		gpu["queried"] = true
		gpu["reason"] = ""
		gpu["used_by_capture"] = true
	return {
		"schema": SCHEMA,
		"base_schema": BASE_SCHEMA,
		"mode": MODE_STAGED,
		"route_claim": ROUTE_CLAIM,
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
		"video": VIDEO.duplicate(true),
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
		},
		"seed": {
			"requested": _seed_arg,
			"active_map_seed": 0,
			"official_clip_seed": OFFICIAL_CLIP_SEED,
		},
		"env": _env_snapshot(),
		"beam_card": {
			"mode": "on",
			"hidden": 0,
			"mechanism": "not applicable: the route runner never hides beam cards and never touches the beam fix; the field is kept for tat2.p0b_capture/1 compatibility",
		},
		"level": {
			"route_contract": "CONSTABLES' GUILDHALL — Cleanout Heist (staged substitute, free play)",
			"difficulty": "Novice",
			"mission_mode": "Solo",
			"den_contract_order": 1,
			"guildhall_contract_order": 2,
			"scope": "Den beats S03/S04/S06/S08/S05 (contract 1); prep/loading S09/S10; Guildhall beats S11/S12/S24/S27 (free play LootTheRoom on contract 2)",
			"free_play": true,
			"free_play_substitute": true,
			"official_free_play": false,
			"free_play_mission_id": "Mission.Guildhall.LootTheRoom",
			"historical_mission_id": "Mission.Guildhall.LootTheRoom",
			"canonical_mission_id": "Mission.Guildhall.VaultHeist",
			"note": "The Guildhall stage is a STAGED SUBSTITUTE: free play Mission.Guildhall.LootTheRoom on contract 2 is used only to show the KF13 briefing letter over the live safe room. It is not the official mission selection. The 2026-11-24 port baseline ran Mission.Guildhall.LootTheRoom on Contract.Main.2 with free_play=false, and the canonical contract-2 Guildhall row is Mission.Guildhall.VaultHeist (docs/reports/contract-flow.md). The 120-row scorer must not treat this free-play combination as official.",
		},
		"store": _store_probe(),
		"settings": {
			"fov_vertical_deg": SHIPPED_FOV,
			"difficulty": 1,
			"difficulty_label": "Novice",
			"mission_mode": "Solo",
			"den_contract_order": 1,
			"guildhall_contract_order": 2,
			"thief_id": "spider",
			"free_play": true,
			"free_play_substitute": true,
			"free_play_mission_id": "Mission.Guildhall.LootTheRoom",
			"resolution": [SIZE.x, SIZE.y],
			"graphics_quality": str(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", "")),
			"note": "Staged state recorded for a later re-score; the runner does not drive gameplay input.",
		},
		"beats": [],
		"extras": [],
		"audio": {},
		"notes": [
			"This is a STAGED/MIXED capture, not a played route. route_claim=none.",
			"13 of the 27 official beats are PLANNED to be staged through live UI/API hooks; 14 are deferred with an explicit reason. No beat is claimed as reached in a played run.",
			"Official S01..S27 times and keyframes are provenance anchors from KEYFRAME_INDEX.md §2 (mirrored in p0b_audio_stats.py); the run does not align to them.",
			"Staged frames use the audio tap's generic mark() only; the S01..S27 beat-marker entry point is never called, so a staged frame cannot claim a played-beat alignment.",
			"The Den stage is contract 1 (no free play). The Guildhall stage is a STAGED SUBSTITUTE: free play Mission.Guildhall.LootTheRoom on contract 2, used only to show the KF13 briefing letter over the live safe room. It is not the official mission selection (canonical contract-2 row: Mission.Guildhall.VaultHeist; historical 2026-11-24 baseline: LootTheRoom, free_play=false). The 120-row scorer must not treat it as official.",
			"S05 enters the telescope view and never exits: the [F] EXIT path is L4-13 (player stranded on the Den roof).",
			"S03 uses a synthetic camera (camera_source=synthetic); S12/S24 and the Lounge extra use the player camera (camera_source=player) at the authored eye/target.",
			"S24 is the foyer only: upper_foyer + yaw180 + foyer_beam (KF27 cue aimed at the authored C_107 card). The p0b beam_close pose is the Lounge C_57 card and is recorded in extras[0], never as S24.",
			"TAT2_PARITY_ONLY=1 is exported by the wrapper for every mode, so expansion content is excluded from the staged run.",
			"Under a headless/Dummy audio driver the tap records enabled=false with a reason; that is not an audio measurement.",
			"A later lane maps these 27 rows onto docs/reference/clip_1795033698901/COMPARISON_PORT_20261124.md; this runner does not score the 120 rows.",
		],
	}


func _write_json(path: String, obj: Dictionary) -> bool:
	var dir: String = path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		printerr("P0B_ROUTE_WRITE_FAIL dir=", dir)
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("P0B_ROUTE_WRITE_FAIL path=", path, " err=", FileAccess.get_open_error())
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


func _row(status: String) -> Dictionary:
	return {
		"id": "",
		"label": "",
		"official_start_s": 0.0,
		"official_end_s": 0.0,
		"class": "ui",
		"ref_keyframe": "",
		"source": "absent",
		"status": status,
		"reason": "",
		"stage_hook": "",
		"png": "",
		"t_s": -1.0,
		"frame_no": -1,
		"eye": [],
		"target": [],
		"camera_source": "",
		"mark_kind": "mark",
		"staged": false,
		"evidence": "",
		"frames": [],
		"frame_errors": [],
	}


func _make_rows() -> Array:
	var rows: Array = []
	for id: String in BEAT_IDS:
		var b: Dictionary = BEATS[id] as Dictionary
		var planned: bool = str(b.get("plan", "")) == "staged"
		var row: Dictionary = _row("planned" if planned else "deferred")
		row["id"] = id
		row["label"] = str(b.get("label", ""))
		row["official_start_s"] = float(b.get("start", 0.0))
		row["official_end_s"] = float(b.get("end", 0.0))
		row["class"] = str(b.get("class", "ui"))
		row["ref_keyframe"] = str(b.get("ref", "none"))
		row["source"] = "staged" if planned else "absent"
		row["reason"] = "" if planned else str(b.get("reason", ""))
		row["stage_hook"] = str(b.get("hook", ""))
		row["camera_source"] = _planned_camera_source(id)
		row["frame_count_planned"] = (b.get("frames", []) as Array).size()
		rows.append(row)
	return rows


func _planned_camera_source(id: String) -> String:
	if id == "S03":
		return "synthetic"
	if id == "S27" or str((BEATS[id] as Dictionary).get("class", "")) == "world":
		return "player"
	return "ui"


func _row_by_id(rows: Array, id: String) -> Dictionary:
	for r: Variant in rows:
		if r is Dictionary and str((r as Dictionary).get("id", "")) == id:
			return r as Dictionary
	return {}


func _beat_frames(id: String) -> Array:
	return (BEATS[id] as Dictionary).get("frames", []) as Array


func _counts(rows: Array) -> Dictionary:
	var captured: int = 0
	var planned: int = 0
	var deferred: int = 0
	var partial: int = 0
	var frames: int = 0
	var frame_errors: int = 0
	for r: Variant in rows:
		var row: Dictionary = r as Dictionary
		match str(row.get("status", "")):
			"captured":
				captured += 1
			"planned":
				planned += 1
			"deferred":
				deferred += 1
			"partial":
				partial += 1
		frames += (row.get("frames", []) as Array).size()
		frame_errors += (row.get("frame_errors", []) as Array).size()
	for e: Variant in _extra_poses:
		if e is Dictionary and str((e as Dictionary).get("status", "")) == "failed":
			frame_errors += 1
	return {
		"beats": rows.size(),
		"captured": captured,
		"planned": planned,
		"deferred": deferred,
		"partial": partial,
		"frames": frames,
		"frame_errors": frame_errors,
		"plan_staged": _count_source(rows, "staged"),
		"extras": _extra_poses.size(),
	}


func _count_source(rows: Array, source: String) -> int:
	var n: int = 0
	for r: Variant in rows:
		if str((r as Dictionary).get("source", "")) == source:
			n += 1
	return n


func _validate_manifest(m: Dictionary) -> Array:
	var errs: Array = []
	if str(m.get("schema", "")) != SCHEMA:
		errs.append("schema != " + SCHEMA)
	if str(m.get("base_schema", "")) != BASE_SCHEMA:
		errs.append("base_schema != " + BASE_SCHEMA)
	if str(m.get("mode", "")) != MODE_STAGED:
		errs.append("mode != staged")
	if str(m.get("route_claim", "")) != ROUTE_CLAIM:
		errs.append("route_claim != none")
	if typeof(m.get("dry_run")) != TYPE_BOOL:
		errs.append("dry_run is not a bool")
	if typeof(m.get("self_test")) != TYPE_BOOL:
		errs.append("self_test is not a bool")
	if str(m.get("started_at_utc", "")).is_empty():
		errs.append("started_at_utc missing")
	if str(m.get("repo_root", "")).is_empty() or str(m.get("out_dir", "")).is_empty():
		errs.append("repo_root/out_dir missing")
	for block: String in ["git", "host", "gpu", "engine", "video", "lens", "settle", "seed", "level", "store", "settings"]:
		if not (m.get(block, null) is Dictionary):
			errs.append("%s block missing" % block)
	var git: Dictionary = m.get("git", {}) as Dictionary
	if str(git.get("sha", "")).is_empty() or str(git.get("sha", "")) == "unknown":
		errs.append("git.sha missing")
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
	var seed: Dictionary = m.get("seed", {}) as Dictionary
	if not seed.has("requested") or not seed.has("active_map_seed") or int(seed.get("official_clip_seed", 0)) != OFFICIAL_CLIP_SEED:
		errs.append("seed block incomplete")
	var video: Dictionary = m.get("video", {}) as Dictionary
	if absf(float(video.get("duration_s", 0.0)) - 225.642333) > 0.001:
		errs.append("video.duration_s != 225.642333")
	var store: Dictionary = m.get("store", {}) as Dictionary
	if str(store.get("source", "")) not in ["owner_restore", "fresh"]:
		errs.append("store.source not owner_restore|fresh")
	if str(store.get("path", "")).is_empty():
		errs.append("store.path missing")
	var beats: Array = m.get("beats", []) as Array
	if beats.size() != ROUTE_BEAT_COUNT:
		errs.append("beats size %d != %d" % [beats.size(), ROUTE_BEAT_COUNT])
	var seen: Dictionary = {}
	var prev_end: float = -1.0
	var n_captured: int = 0
	var n_planned: int = 0
	var n_deferred: int = 0
	var n_staged_src: int = 0
	var n_partial: int = 0
	var n_frames: int = 0
	var n_frame_errors: int = 0
	for i: int in range(beats.size()):
		var rv: Variant = beats[i]
		if not (rv is Dictionary):
			errs.append("beat[%d] is not a dictionary" % i)
			continue
		var row: Dictionary = rv as Dictionary
		var id: String = str(row.get("id", ""))
		if i < BEAT_IDS.size() and id != BEAT_IDS[i]:
			errs.append("beat[%d] id %s != %s" % [i, id, BEAT_IDS[i]])
		if seen.has(id):
			errs.append("duplicate beat id " + id)
		seen[id] = true
		var start: float = float(row.get("official_start_s", -1.0))
		var end: float = float(row.get("official_end_s", -1.0))
		if end <= start:
			errs.append("%s end <= start" % id)
		if start < prev_end - 0.0005:
			errs.append("%s start not monotonic" % id)
		prev_end = maxf(prev_end, end)
		if str(row.get("label", "")).is_empty():
			errs.append("%s label empty" % id)
		if str(row.get("class", "")) not in ["ui", "world", "camera"]:
			errs.append("%s class invalid" % id)
		if str(row.get("ref_keyframe", "")).is_empty():
			errs.append("%s ref_keyframe empty" % id)
		var source: String = str(row.get("source", ""))
		if source not in ["staged", "absent"]:
			errs.append("%s source %s" % [id, source])
		var status: String = str(row.get("status", ""))
		if status not in ["captured", "deferred", "planned", "partial"]:
			errs.append("%s status %s" % [id, status])
		match status:
			"captured":
				n_captured += 1
			"planned":
				n_planned += 1
			"deferred":
				n_deferred += 1
			"partial":
				n_partial += 1
		if source == "staged":
			n_staged_src += 1
		n_frames += (row.get("frames", []) as Array).size()
		n_frame_errors += (row.get("frame_errors", []) as Array).size()
		if status in ["deferred", "partial"] and str(row.get("reason", "")).strip_edges().is_empty():
			errs.append("%s %s without a reason" % [id, status])
		if source == "staged" and str(row.get("stage_hook", "")).strip_edges().is_empty():
			errs.append("%s staged without a stage_hook" % id)
		if str(row.get("mark_kind", "")) != "mark":
			errs.append("%s mark_kind != mark" % id)
		if typeof(row.get("staged")) != TYPE_BOOL:
			errs.append("%s staged is not a bool" % id)
		var eye: Array = row.get("eye", []) as Array
		var tgt: Array = row.get("target", []) as Array
		if eye.size() != 0 and eye.size() != 3:
			errs.append("%s eye is not 0 or 3 numbers" % id)
		if tgt.size() != 0 and tgt.size() != 3:
			errs.append("%s target is not 0 or 3 numbers" % id)
		for field: String in ["png", "t_s", "frame_no", "evidence", "frames", "frame_errors", "camera_source"]:
			if not row.has(field):
				errs.append("%s missing field %s" % [id, field])
		if bool(m.get("dry_run")):
			if status != "planned" and source == "staged":
				errs.append("%s dry_run staged row is %s" % [id, status])
			if str(row.get("png", "")) != "":
				errs.append("%s dry_run row has a png" % id)
		elif status in ["captured", "partial"]:
			if str(row.get("png", "")).is_empty():
				errs.append("%s %s without a png" % [id, status])
			if float(row.get("t_s", -1.0)) < 0.0:
				errs.append("%s %s without t_s" % [id, status])
			if int(row.get("frame_no", -1)) < 0:
				errs.append("%s %s without frame_no" % [id, status])
			if (row.get("frames", []) as Array).is_empty():
				errs.append("%s %s without frames" % [id, status])
			if str(row.get("class", "")) == "world" and (eye.size() != 3 or tgt.size() != 3):
				errs.append("%s %s world beat without a camera pose" % [id, status])
			if status == "captured" and str(row.get("evidence", "")).strip_edges().is_empty():
				errs.append("%s captured without evidence" % id)
			if status == "captured" and not (row.get("frame_errors", []) as Array).is_empty():
				errs.append("%s captured with frame_errors" % id)
			if str(row.get("class", "")) in ["world", "camera"] and str(row.get("camera_source", "")) in ["", "ui"]:
				errs.append("%s %s world beat without a camera_source" % [id, status])
	for id: String in BEAT_IDS:
		if not seen.has(id):
			errs.append("missing beat " + id)
	var counts: Dictionary = m.get("counts", {}) as Dictionary
	if int(counts.get("beats", 0)) != ROUTE_BEAT_COUNT:
		errs.append("counts.beats != 27")
	if int(counts.get("plan_staged", 0)) != STAGED_IDS.size():
		errs.append("counts.plan_staged != %d" % STAGED_IDS.size())
	if int(counts.get("captured", 0)) + int(counts.get("planned", 0)) + int(counts.get("deferred", 0)) + int(counts.get("partial", 0)) != ROUTE_BEAT_COUNT:
		errs.append("counts do not add up to 27")
	if int(counts.get("captured", 0)) != n_captured:
		errs.append("counts.captured %d != rows %d" % [int(counts.get("captured", 0)), n_captured])
	if int(counts.get("planned", 0)) != n_planned:
		errs.append("counts.planned %d != rows %d" % [int(counts.get("planned", 0)), n_planned])
	if int(counts.get("deferred", 0)) != n_deferred:
		errs.append("counts.deferred %d != rows %d" % [int(counts.get("deferred", 0)), n_deferred])
	if int(counts.get("partial", 0)) != n_partial:
		errs.append("counts.partial %d != rows %d" % [int(counts.get("partial", 0)), n_partial])
	if int(counts.get("frame_errors", 0)) < n_frame_errors:
		errs.append("counts.frame_errors %d < row errors %d" % [int(counts.get("frame_errors", 0)), n_frame_errors])
	if int(counts.get("plan_staged", 0)) != n_staged_src:
		errs.append("counts.plan_staged %d != rows %d" % [int(counts.get("plan_staged", 0)), n_staged_src])
	if int(counts.get("frames", 0)) != n_frames:
		errs.append("counts.frames %d != frames %d" % [int(counts.get("frames", 0)), n_frames])
	if not m.has("extras"):
		errs.append("extras block missing")
	var extras: Array = m.get("extras", []) as Array
	if int(counts.get("extras", 0)) != extras.size():
		errs.append("counts.extras %d != extras %d" % [int(counts.get("extras", 0)), extras.size()])
	for i: int in range(extras.size()):
		var ev: Variant = extras[i]
		if not (ev is Dictionary):
			errs.append("extras[%d] is not a dictionary" % i)
			continue
		var ex: Dictionary = ev as Dictionary
		if str(ex.get("id", "")).is_empty():
			errs.append("extras[%d] id empty" % i)
		if str(ex.get("subject", "")).is_empty():
			errs.append("extras[%d] subject empty" % i)
		if ex.get("ref_keyframe", null) != null and typeof(ex.get("ref_keyframe")) != TYPE_STRING:
			errs.append("extras[%d] ref_keyframe is not null or a string" % i)
		var est: String = str(ex.get("status", ""))
		if est not in ["captured", "failed", "planned"]:
			errs.append("extras[%d] status %s" % [i, est])
		if est == "captured" and str(ex.get("png", "")).is_empty():
			errs.append("extras[%d] captured without a png" % i)
		if est in ["failed", "planned"] and str(ex.get("png", "")) != "":
			errs.append("extras[%d] %s row has a png" % [i, est])
		if str(ex.get("beat", "")) != "":
			errs.append("extras[%d] must not claim a beat" % i)
	var audio: Dictionary = m.get("audio", {}) as Dictionary
	if not audio.has("enabled") or not audio.has("reason"):
		errs.append("audio block missing enabled/reason")
	if not audio.has("enabled") or typeof(audio.get("enabled")) != TYPE_BOOL:
		errs.append("audio.enabled is not a bool")
	if bool(m.get("dry_run")) and bool(audio.get("enabled", true)):
		errs.append("dry_run audio must be disabled")
	if bool(m.get("dry_run")) and str(audio.get("reason", "")).is_empty():
		errs.append("dry_run audio needs a reason")
	var notes: Array = m.get("notes", []) as Array
	if notes.is_empty():
		errs.append("notes missing")
	return errs


func _setup_paths() -> void:
	_repo_root = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	_tag = _arg("--tag=", "").replace(" ", "_")
	var run: String = _arg("--run-id=", "")
	if run == "":
		run = _stamp()
		if _tag != "":
			run += "_" + _tag
		run += "_" + _git_line(["rev-parse", "--short=12", "HEAD"], "nogit") + "_staged"
	_run_id = run
	var env_out: String = _env("P0B_ROUTE_OUT")
	if env_out != "":
		_out_dir = env_out
	elif _mode == "capture":
		_out_dir = _repo_root.path_join("build/qa/p0b_route").path_join(_run_id)
	else:
		_out_dir = _repo_root.path_join("build/qa/p0b_route").path_join(_mode)
	var env_manifest: String = _env("P0B_ROUTE_MANIFEST")
	if env_manifest != "":
		_manifest_path = env_manifest
	elif _mode == "dry-run":
		_manifest_path = dry_manifest_path()
	elif _mode == "self-test":
		_manifest_path = self_test_manifest_path()
	else:
		_manifest_path = capture_manifest_path(_run_id)


func dry_manifest_path() -> String:
	return _repo_root.path_join("docs/reports/logs/p0b-route/dry-run/manifest.json")


func self_test_manifest_path() -> String:
	return _repo_root.path_join("build/qa/p0b_route/selftest/manifest.json")


func capture_manifest_path(run_id: String) -> String:
	return _repo_root.path_join("docs/reports/logs/p0b-route").path_join(run_id).path_join("manifest.json")


func _apply_seed(gs: Node) -> void:
	if _seed_arg.to_lower() == "derived":
		return
	if not _seed_arg.is_valid_int():
		printerr("P0B_ROUTE bad --seed=", _seed_arg, " (int or derived)")
		return
	gs.set("active_map_seed", int(_seed_arg))


func _grab() -> Image:
	for _try: int in range(4):
		await RenderingServer.frame_post_draw
		var tex: ViewportTexture = root.get_texture()
		if tex != null:
			var img: Image = tex.get_image()
			if img != null and not img.is_empty():
				return img
		await _wait(2)
	return null


## Sampled ITU-R 601 luma (Pillow convert("L") weights), every 4th pixel; only a
## non-black guard and the median selector. Authoritative ROI numbers for a
## later score come from p0b_roi_stats.py on the saved PNG.
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


## One staged frame: settle, capture 5, save the median-mean frame. A UI frame
## passes cam=null (no world pose); a world frame passes the camera that framed
## it so the manifest records the pose the pixels came from.
func _shoot_frame(id: String, fname: String, tap: Node, cam: Camera3D, camera_source: String = "ui") -> Dictionary:
	var t_s: float = float(Time.get_ticks_msec() - _capture_start_msec) / 1000.0
	var frame_no: int = _frame_seq
	if tap != null:
		tap.call("mark", id + "_" + fname, "")
	if cam != null and is_instance_valid(cam):
		# Re-assert the camera that framed this pose so the saved pixels and the
		# recorded eye/target cannot disagree if another camera went current.
		cam.current = true
	await _wait(SETTLE_FRAMES)
	var imgs: Array = []
	var means: Array = []
	for i: int in range(CAPTURE_FRAMES):
		var img: Image = await _grab()
		if img == null:
			return {"name": fname, "ok": false, "error": "empty frame at %d" % i}
		var st: Dictionary = _sampled_stats(img)
		imgs.append(img)
		means.append(float(st.get("mean", 0.0)))
		print("P0B_ROUTE_FRAME id=%s frame=%s idx=%d mean601=%.2f lt8=%.1f peak=%.1f" % [
			id, fname, i, float(st.get("mean", 0.0)), float(st.get("pct_lt8", 100.0)),
			float(st.get("peak", 0.0)),
		])
	var order: Array = []
	for i: int in range(means.size()):
		order.append([float(means[i]), i])
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var median_index: int = int((order[int(order.size() / 2)] as Array)[1])
	var med: Image = imgs[median_index] as Image
	var png: String = _out_dir.path_join(id + "_" + fname + ".png")
	var err: int = med.save_png(png)
	var st_med: Dictionary = _sampled_stats(med)
	var size_ok: bool = med.get_width() == SIZE.x and med.get_height() == SIZE.y
	var nonblack: bool = err == OK and size_ok and float(st_med.get("peak", 0.0)) > 8.0 and float(st_med.get("mean", 0.0)) > 1.0
	var eye: Array = []
	var target: Array = []
	if cam != null and is_instance_valid(cam):
		eye = _v3(cam.global_position)
		target = _v3(cam.global_position - cam.global_transform.basis.z * 10.0)
	print("P0B_ROUTE_SHOT id=%s frame=%s median=%d mean601=%.2f lt8=%.1f peak=%.1f ok=%s size=%dx%d png=%s" % [
		id, fname, median_index, float(st_med.get("mean", 0.0)),
		float(st_med.get("pct_lt8", 100.0)), float(st_med.get("peak", 0.0)),
		str(nonblack), med.get_width(), med.get_height(), _rel(png),
	])
	_frame_seq += 1
	imgs.clear()
	return {
		"name": fname,
		"ok": nonblack,
		"error": "" if nonblack else "non-black guard failed (err=%d size_ok=%s)" % [err, str(size_ok)],
		"png": _rel(png),
		"t_s": t_s,
		"frame_no": frame_no,
		"eye": eye,
		"target": target,
		"camera_source": camera_source,
		"mark_kind": "mark",
		"staged": true,
		"median_index": median_index,
		"frames_mean": means.duplicate(),
		"median_mean": float(st_med.get("mean", 0.0)),
		"median_lt8": float(st_med.get("pct_lt8", 100.0)),
		"median_peak": float(st_med.get("peak", 0.0)),
		"png_size": [med.get_width(), med.get_height()],
	}


func _add_frame(row: Dictionary, fr: Dictionary) -> Dictionary:
	var errs: Array = row.get("frame_errors", []) as Array
	if not bool(fr.get("ok", false)):
		errs.append("%s: %s" % [str(fr.get("name", "")), str(fr.get("error", "unknown"))])
		row["frame_errors"] = errs
		if fr.has("beam_visible"):
			row["beam_visible"] = bool(fr.get("beam_visible", false))
		if (row.get("frames", []) as Array).is_empty():
			row["status"] = "deferred"
			row["reason"] = "capture_failed: " + str(fr.get("error", "unknown"))
		else:
			# A secondary planned frame failed: never leave the beat "captured".
			row["status"] = "partial"
			row["reason"] = "partial_capture: %d frame(s) failed; first=%s" % [errs.size(), str(errs[0])]
		return row
	var frames: Array = row.get("frames", []) as Array
	frames.append(fr)
	row["frames"] = frames
	row["frame_errors"] = errs
	row["staged"] = true
	if fr.has("beam_visible"):
		row["beam_visible"] = bool(fr.get("beam_visible", false))
	if errs.is_empty():
		row["status"] = "captured"
	else:
		row["status"] = "partial"
		row["reason"] = "partial_capture: %d frame(s) failed; first=%s" % [errs.size(), str(errs[0])]
	if str(row.get("png", "")) == "":
		row["png"] = str(fr.get("png", ""))
		row["t_s"] = float(fr.get("t_s", -1.0))
		row["frame_no"] = int(fr.get("frame_no", -1))
		row["eye"] = (fr.get("eye", []) as Array).duplicate()
		row["target"] = (fr.get("target", []) as Array).duplicate()
		row["camera_source"] = str(fr.get("camera_source", ""))
	return row


func _finish_row(row: Dictionary, evidence: String) -> void:
	if str(row.get("status", "")) == "captured":
		row["evidence"] = evidence
	print("P0B_ROUTE_BEAT id=%s status=%s frames=%d hook=%s evidence=%s" % [
		str(row.get("id", "")), str(row.get("status", "")),
		(row.get("frames", []) as Array).size(),
		str(row.get("stage_hook", "")), str(row.get("evidence", "")),
	])


func _defer_row(rows: Array, id: String, reason: String) -> void:
	var row: Dictionary = _row_by_id(rows, id)
	if row.is_empty():
		return
	row["status"] = "deferred"
	row["reason"] = reason
	print("P0B_ROUTE_BEAT id=%s status=deferred reason=%s" % [id, reason])


## Records a planned secondary frame that could not be staged at all (missing
## hook) without touching the frames already saved. The beat becomes partial,
## never captured.
func _note_frame_error(row: Dictionary, message: String) -> void:
	var errs: Array = row.get("frame_errors", []) as Array
	errs.append(message)
	row["frame_errors"] = errs
	if str(row.get("status", "")) != "deferred":
		row["status"] = "partial"
		row["reason"] = "partial_capture: %d frame(s) failed; first=%s" % [errs.size(), str(errs[0])]
	print("P0B_ROUTE_FRAME_ERROR id=%s %s" % [str(row.get("id", "")), message])


func _find_ui_node(host: Node, suffix: String) -> Node:
	if host == null:
		return null
	for n: Node in host.find_children("*", "CanvasLayer", true, false):
		var scr: Script = n.get_script() as Script
		if scr != null and str(scr.resource_path).ends_with(suffix):
			return n
	for n: Node in host.find_children("*", "Control", true, false):
		var scr2: Script = n.get_script() as Script
		if scr2 != null and str(scr2.resource_path).ends_with(suffix):
			var p: Node = n.get_parent()
			return p if p is CanvasLayer else n
	return null


func _find_ui_control(host: Node, suffix: String) -> Node:
	if host == null:
		return null
	for n: Node in host.find_children("*", "Control", true, false):
		var scr: Script = n.get_script() as Script
		if scr != null and str(scr.resource_path).ends_with(suffix):
			return n
	return null


func _free_ui(host: Node, suffix: String) -> bool:
	var n: Node = _find_ui_node(host, suffix)
	if n == null:
		return false
	n.queue_free()
	return true


func _wait_for_mission(mission: Node3D, budget: int) -> int:
	var waited: int = 0
	while (mission.get("player") == null or get_nodes_in_group("swinging_doors").is_empty()) and waited < budget:
		await process_frame
		waited += 1
	return waited


func _mission(map_id: String, order: int, free_play: bool = false, mission_id: String = "") -> Node3D:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		printerr("P0B_ROUTE_MISSION_FAIL GameState missing")
		return null
	gs.set("state", "playing")
	gs.set("thief_id", "spider")
	gs.set("difficulty", 1)
	gs.set("active_mission_mode", "Solo")
	gs.set("active_contract_order", order)
	gs.set("active_map_id", map_id)
	if free_play and gs.has_method("begin_free_play"):
		gs.call("begin_free_play", mission_id)
	elif gs.has_method("end_free_play"):
		gs.call("end_free_play")
	else:
		gs.set("free_play", false)
	_apply_seed(gs)
	var mission: Node3D = (load("res://scenes/mission.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(mission)
	var waited: int = await _wait_for_mission(mission, 1800)
	await _wait(40)
	if mission.get("player") == null:
		printerr("P0B_ROUTE_MISSION_FAIL map=%s player missing waited=%d" % [map_id, waited])
		mission.queue_free()
		return null
	print("P0B_ROUTE_MISSION ready map=%s order=%d free_play=%s mission=%s waited=%d doors=%d seed_requested=%s active_seed=%d" % [
		map_id, order, str(free_play), mission_id, waited,
		get_nodes_in_group("swinging_doors").size(),
		_seed_arg, int(gs.get("active_map_seed")),
	])
	return mission


func _make_camera(mission: Node3D, name: String) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = name
	cam.fov = SHIPPED_FOV
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 4000.0
	mission.add_child(cam)
	return cam


func _aim(cam: Camera3D, eye: Vector3, target: Vector3) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.current = true


## Places the real first-person rig at the authored eye and aims it at the
## target, so S12/S24 pixels come from `mission.player.cam`, not a synthetic
## camera: feet = eye - 1.67 (the capture's EYE_OFFSET), yaw on the body, pitch
## on the head, base_fov/cam.fov = 54.54. Physics and _process are frozen for
## the still so the settle does not bob or step the eye. Returns the camera or
## null when the rig is unavailable.
func _aim_player(mission: Node3D, eye: Vector3, target: Vector3) -> Camera3D:
	if mission == null or not is_instance_valid(mission):
		return null
	var player: Node3D = mission.get("player") as Node3D
	if player == null or not is_instance_valid(player):
		return null
	var head: Node3D = player.get("head") as Node3D
	var cam: Camera3D = player.get("cam") as Camera3D
	if head == null or cam == null:
		return null
	var dir: Vector3 = target - eye
	if dir.length() < 0.001:
		return null
	dir = dir.normalized()
	player.set("velocity", Vector3.ZERO)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_rotation.y = atan2(-dir.x, -dir.z)
	head.rotation.x = asin(clampf(dir.y, -1.0, 1.0))
	player.global_position = Vector3(eye.x, eye.y - EYE_OFFSET, eye.z)
	player.set("base_fov", SHIPPED_FOV)
	cam.fov = SHIPPED_FOV
	cam.current = true
	return cam


## True when a visible `lightbeam_cards` member sits within `FOYER_BEAM_CARD_TOL_M`
## of the authored foyer beam card. A missing/hidden card means the S24
## foyer_beam frame is a failed planned frame, never a Lounge substitute.
func _beam_card_visible_near(pos: Vector3) -> bool:
	for n: Node in get_nodes_in_group("lightbeam_cards"):
		var gi: GeometryInstance3D = n as GeometryInstance3D
		if gi == null or not gi.is_inside_tree():
			continue
		if gi.global_position.distance_to(pos) <= FOYER_BEAM_CARD_TOL_M:
			return gi.is_visible_in_tree()
	return false


func _frame_by_name(id: String, fname: String) -> Dictionary:
	for f: Variant in _beat_frames(id):
		var fd: Dictionary = f as Dictionary
		if str(fd.get("name", "")) == fname:
			return fd
	return {}


## The Lounge C_57 reference pose is planned in every mode but is never a beat.
func _extra_plan() -> Dictionary:
	return {
		"id": LOUNGE_BEAM_ID, "subject": "Lounge C_57 beam", "beat": "",
		"ref_keyframe": null, "status": "planned", "reason": "",
		"png": "", "t_s": -1.0, "frame_no": -1,
		"eye": _v3(LOUNGE_BEAM_EYE), "target": _v3(LOUNGE_BEAM_TARGET),
		"camera_source": "player",
		"note": "p0b beam_close pose; Lounge C_57 beam at (39,28.82,-28.97)->(42.4,28.9,-28.97). NOT S24/KF27.",
	}


func _clear_beat(rows: Array, id: String, reason: String) -> void:
	var row: Dictionary = _row_by_id(rows, id)
	row["frames"] = []
	row["frame_errors"] = []
	row["png"] = ""
	row["t_s"] = -1.0
	row["frame_no"] = -1
	row["eye"] = []
	row["target"] = []
	row["camera_source"] = ""
	row["staged"] = false
	row["evidence"] = ""
	row["status"] = "deferred"
	row["reason"] = reason
	print("P0B_ROUTE_BEAT id=%s status=deferred reason=%s" % [str(row.get("id", "")), reason])


# ---------------------------------------------------------------------------
# Stage S01 / S02: front end
# ---------------------------------------------------------------------------

func _stage_s01(rows: Array, tap: Node) -> void:
	var row: Dictionary = _row_by_id(rows, "S01")
	var mm_script: GDScript = load("res://src/ui/main_menu.gd") as GDScript
	if mm_script == null:
		_defer_row(rows, "S01", "main_menu.gd did not load")
		return
	var mm: Control = mm_script.new() as Control
	mm.size = Vector2(SIZE)
	root.add_child(mm)
	await _wait(20)
	if not mm.is_visible_in_tree():
		_defer_row(rows, "S01", "main_menu Control is not visible after 20 frames")
		mm.queue_free()
		return
	row = _add_frame(row, await _shoot_frame("S01", "startscreen", tap, null))
	await _wait(4)
	mm.queue_free()
	await _wait(4)
	_finish_row(row, "main_menu.gd instantiated (real startscreen over its 3D backdrop); no menu input driven")


func _stage_s02(rows: Array, tap: Node) -> void:
	var row: Dictionary = _row_by_id(rows, "S02")
	var ls_script: GDScript = load("res://src/ui/loading_screen.gd") as GDScript
	if ls_script == null:
		_defer_row(rows, "S02", "loading_screen.gd did not load")
		return
	var ls: CanvasLayer = ls_script.new() as CanvasLayer
	root.add_child(ls)
	await _wait(4)
	if not ls.has_method("start_loading"):
		_defer_row(rows, "S02", "loading_screen.start_loading missing")
		ls.queue_free()
		return
	ls.call("start_loading", "", "", "guildhall")
	if ls.has_method("set_progress"):
		ls.call("set_progress", 0.62, "")
	await _wait(12)
	if not ls.visible:
		_defer_row(rows, "S02", "loading_screen did not become visible after start_loading")
		ls.queue_free()
		return
	row = _add_frame(row, await _shoot_frame("S02", "loading_1", tap, null))
	await _wait(4)
	ls.queue_free()
	await _wait(4)
	_finish_row(row, "loading_screen.gd start_loading('', '', 'guildhall') + set_progress(0.62); authored T_loadingScreen_1 splash")


# ---------------------------------------------------------------------------
# Stage S03/S04/S06/S08/S05: the Den, S05 last (no telescope exit)
# ---------------------------------------------------------------------------

func _stage_den(rows: Array, tap: Node) -> void:
	var mission: Node3D = await _mission("thieves_den", 1)
	if mission == null:
		for id: String in ["S03", "S04", "S06", "S08", "S05"]:
			_clear_beat(rows, id, "mission_load_failed: mission.tscn did not become ready for thieves_den")
		return
	var hud: Node = mission.get("hud") as Node
	if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
		hud.call("_close_mission_letter")
		await _wait(10)
	var cam: Camera3D = _make_camera(mission, "P0bRouteCamera")

	# S03 Den entry/pan: fixed Den-wide pose (capture_e2e_parity Den pose).
	var r03: Dictionary = _row_by_id(rows, "S03")
	var f03: Dictionary = _frame_by_name("S03", "den_entry")
	_aim(cam, f03.get("eye", Vector3.ZERO) as Vector3, f03.get("target", Vector3.FORWARD) as Vector3)
	await _wait(20)
	r03 = _add_frame(r03, await _shoot_frame("S03", "den_entry", tap, cam, "synthetic"))
	_finish_row(r03, "mission.tscn order=1 map=thieves_den; synthetic Den-wide camera (camera_source=synthetic) at the capture_e2e_parity Den pose; HUD live")

	# S04 Wardrobe.
	var r04: Dictionary = _row_by_id(rows, "S04")
	if mission.has_method("open_wardrobe_ui"):
		mission.call("open_wardrobe_ui")
		await _wait(30)
		var ward: Node = _find_ui_node(mission, "wardrobe_ui.gd")
		if ward == null:
			_defer_row(rows, "S04", "open_wardrobe_ui() did not add a wardrobe_ui.gd CanvasLayer")
		else:
			r04 = _add_frame(r04, await _shoot_frame("S04", "wardrobe", tap, null))
			_finish_row(r04, "mission_controller.open_wardrobe_ui() -> wardrobe_ui.open_customizer(); 3D Spider turntable + loadout panels")
		_free_ui(mission, "wardrobe_ui.gd")
		await _wait(6)
	else:
		_defer_row(rows, "S04", "mission_controller.open_wardrobe_ui missing")

	# S06 Ledger: Journal then Black Market.
	# `open_ledger_ui()` adds a plain CanvasLayer holding a LedgerUI Control;
	# `_show_tab` lives on the Control, not the layer. Resolve both so the
	# layer is freed correctly and the tab switch actually runs.
	var r06: Dictionary = _row_by_id(rows, "S06")
	if mission.has_method("open_ledger_ui"):
		mission.call("open_ledger_ui")
		await _wait(20)
		var ledger_layer: Node = _find_ui_node(mission, "ledger_ui.gd")
		var ledger: Node = _find_ui_control(mission, "ledger_ui.gd")
		if ledger_layer == null or ledger == null:
			_defer_row(rows, "S06", "open_ledger_ui() did not yield both a ledger_ui.gd CanvasLayer and a LedgerUI Control")
		else:
			if ledger.has_method("_show_tab"):
				ledger.call("_show_tab", 0)
			await _wait(10)
			r06 = _add_frame(r06, await _shoot_frame("S06", "journal", tap, null))
			if ledger.has_method("_show_tab"):
				ledger.call("_show_tab", 1)
				await _wait(12)
				r06 = _add_frame(r06, await _shoot_frame("S06", "black_market", tap, null))
			else:
				_note_frame_error(r06, "black_market: ledger_ui._show_tab missing on the Control")
			_finish_row(r06, "mission_controller.open_ledger_ui() -> LedgerUI Control _show_tab(0) journal + _show_tab(1) black market")
		_free_ui(mission, "ledger_ui.gd")
		await _wait(6)
	else:
		_defer_row(rows, "S06", "mission_controller.open_ledger_ui missing")

	# S08 Map table + confirmation modal, Novice/Solo kept.
	var r08: Dictionary = _row_by_id(rows, "S08")
	if mission.has_method("open_contract_table_ui"):
		if mission.has_method("set_den_selected_map"):
			mission.call("set_den_selected_map", "guildhall")
			await _wait(4)
		mission.call("open_contract_table_ui")
		await _wait(20)
		var table: Node = _find_ui_node(mission, "contract_table_ui.gd")
		var gs: Node = root.get_node_or_null("/root/GameState")
		var card: Dictionary = {}
		if mission.has_method("get_den_lookat_card"):
			card = mission.call("get_den_lookat_card") as Dictionary
		print("P0B_ROUTE_DEN_CARD map=%s difficulty=%d mode=%s card_target=%s" % [
			str(gs.get("active_map_id")) if gs != null else "",
			int(gs.get("difficulty")) if gs != null else -1,
			str(gs.get("active_mission_mode")) if gs != null else "",
			str(card.get("target", "")),
		])
		if table == null:
			_defer_row(rows, "S08", "open_contract_table_ui() did not add a contract_table_ui.gd CanvasLayer")
		else:
			r08 = _add_frame(r08, await _shoot_frame("S08", "map_table", tap, null))
			if table.has_method("open_confirm"):
				table.call("open_confirm")
				await _wait(12)
				r08 = _add_frame(r08, await _shoot_frame("S08", "confirm", tap, null))
			else:
				_note_frame_error(r08, "confirm: contract_table_ui.open_confirm missing")
			_finish_row(r08, "set_den_selected_map('guildhall') + open_contract_table_ui() + open_confirm(); difficulty=Novice mode=Solo kept")
		_free_ui(mission, "contract_table_ui.gd")
		await _wait(6)
	else:
		_defer_row(rows, "S08", "mission_controller.open_contract_table_ui missing")

	# S05 Telescope last: enter and DO NOT exit (L4-13 strands the player).
	var r05: Dictionary = _row_by_id(rows, "S05")
	if mission.has_method("toggle_telescope_ponder"):
		mission.call("toggle_telescope_ponder")
		await _wait(24)
		var ponder: Camera3D = mission.get("_ponder_cam") as Camera3D
		if ponder != null and is_instance_valid(ponder) and ponder.current:
			r05 = _add_frame(r05, await _shoot_frame("S05", "telescope_sky", tap, ponder, "mission"))
			_finish_row(r05, "toggle_telescope_ponder(): mission _ponder_cam current, fov=%.1f; no exit call (L4-13)" % ponder.fov)
		else:
			_defer_row(rows, "S05", "toggle_telescope_ponder did not make _ponder_cam current")
	else:
		_defer_row(rows, "S05", "mission_controller.toggle_telescope_ponder missing")

	cam.queue_free()
	mission.queue_free()
	await _wait(8)


# ---------------------------------------------------------------------------
# Stage S09/S10: prep + second loading screen
# ---------------------------------------------------------------------------

func _stage_s09(rows: Array, tap: Node) -> void:
	var row: Dictionary = _row_by_id(rows, "S09")
	var mp_script: GDScript = load("res://src/ui/mission_prep_ui.gd") as GDScript
	if mp_script == null:
		_defer_row(rows, "S09", "mission_prep_ui.gd did not load")
		return
	var mp: Control = mp_script.new() as Control
	mp.size = Vector2(SIZE)
	root.add_child(mp)
	await _wait(6)
	if not mp.has_method("open_prep"):
		_defer_row(rows, "S09", "mission_prep_ui.open_prep missing")
		mp.queue_free()
		return
	mp.call("open_prep", "guildhall", 1, "Solo", 2, true)
	await _wait(70)
	if not mp.visible:
		_defer_row(rows, "S09", "mission_prep_ui did not become visible after open_prep")
		mp.queue_free()
		return
	row = _add_frame(row, await _shoot_frame("S09", "mission_prep", tap, null))
	await _wait(4)
	mp.queue_free()
	await _wait(4)
	_finish_row(row, "mission_prep_ui.open_prep('guildhall', 1, 'Solo', 2, true): MissionLobby stage, Novice/Solo, Contract Inactive")


func _stage_s10(rows: Array, tap: Node) -> void:
	var row: Dictionary = _row_by_id(rows, "S10")
	var ls_script: GDScript = load("res://src/ui/loading_screen.gd") as GDScript
	if ls_script == null:
		_defer_row(rows, "S10", "loading_screen.gd did not load")
		return
	var ls: CanvasLayer = ls_script.new() as CanvasLayer
	root.add_child(ls)
	await _wait(4)
	if not ls.has_method("start_loading"):
		_defer_row(rows, "S10", "loading_screen.start_loading missing")
		ls.queue_free()
		return
	ls.call("start_loading", "", "", "guildhall")
	if ls.has_method("set_progress"):
		ls.call("set_progress", 0.31, "")
	await _wait(12)
	if not ls.visible:
		_defer_row(rows, "S10", "loading_screen did not become visible after start_loading")
		ls.queue_free()
		return
	row = _add_frame(row, await _shoot_frame("S10", "loading_2", tap, null))
	await _wait(4)
	ls.queue_free()
	await _wait(4)
	_finish_row(row, "loading_screen.gd start_loading('', '', 'guildhall') + set_progress(0.31); second loading beat")


# ---------------------------------------------------------------------------
# Stage S11/S12/S24/S27: Guildhall
# ---------------------------------------------------------------------------

func _stage_guildhall(rows: Array, tap: Node) -> void:
	var mission: Node3D = await _mission("guildhall", 2, true, "Mission.Guildhall.LootTheRoom")
	if mission == null:
		for id: String in ["S11", "S12", "S24", "S27"]:
			_clear_beat(rows, id, "mission_load_failed: mission.tscn did not become ready for guildhall")
		return
	var hud: Node = mission.get("hud") as Node

	# S11 Briefing letter: wait for the real mission letter.
	var r11: Dictionary = _row_by_id(rows, "S11")
	var letter_seen: bool = false
	for _i: int in range(300):
		if hud != null and hud.has_method("is_mission_letter_open") and bool(hud.call("is_mission_letter_open")):
			letter_seen = true
			break
		await process_frame
	if letter_seen:
		await _wait(20)
		r11 = _add_frame(r11, await _shoot_frame("S11", "briefing_letter", tap, null))
		_finish_row(r11, "GameState.request_mission_letter -> hud.show_mission_letter; KF13 parchment over the live safe-room view")
		if hud.has_method("_close_mission_letter"):
			hud.call("_close_mission_letter")
		await _wait(20)
	else:
		_defer_row(rows, "S11", "hud.is_mission_letter_open() never became true for guildhall order=2")

	# S12 Safe room: authored spawn eye, player camera, dressing lantern lit.
	# Missing dressing / lantern / set_lit / lit=true defers the beat — the
	# evidence never claims a lantern state the runner did not observe.
	var r12: Dictionary = _row_by_id(rows, "S12")
	var dressing: Node = mission.get_node_or_null("SafeRoomDressing")
	if dressing == null:
		for n: Node in mission.find_children("*", "Node3D", true, false):
			if str(n.name) == "SafeRoomDressing":
				dressing = n
				break
	var lantern: Node = dressing.get_node_or_null("SafeRoomLanternStation") if dressing != null else null
	var lantern_lit: bool = false
	var f12: Dictionary = _frame_by_name("S12", "safe_room")
	if dressing == null:
		_clear_beat(rows, "S12", "SafeRoomDressing missing from the loaded Guildhall mission; no safe-room portal/lantern frame staged")
	elif lantern == null:
		_clear_beat(rows, "S12", "SafeRoomLanternStation missing from SafeRoomDressing; S12 lantern state not stageable")
	elif not lantern.has_method("set_lit"):
		_clear_beat(rows, "S12", "SafeRoomLanternStation has no set_lit(); S12 lantern state not stageable")
	else:
		lantern.call("set_lit", true, false)
		lantern_lit = bool(lantern.get("lit"))
		if not lantern_lit:
			_clear_beat(rows, "S12", "SafeRoomLanternStation.set_lit(true) left lit=false; S12 would claim an unlit lantern")
		else:
			var cam12: Camera3D = _aim_player(mission, f12.get("eye", Vector3.ZERO) as Vector3, f12.get("target", Vector3.FORWARD) as Vector3)
			if cam12 == null:
				_clear_beat(rows, "S12", "player camera rig missing (player/head/cam); S12 needs camera_source=player")
			else:
				await _wait(20)
				r12 = _add_frame(r12, await _shoot_frame("S12", "safe_room", tap, cam12, "player"))
				_finish_row(r12, "SafeRoomDressing present=true; SafeRoomLanternStation.set_lit(true) -> lit=true; player camera at the authored TATSafeRoomPlayerStart_0 eye (camera_source=player)")
	print("P0B_ROUTE_S12 dressing=%s lantern=%s lantern_lit=%s" % [
		str(dressing != null), str(lantern != null), str(lantern_lit),
	])

	# S24 foyer only: upper_foyer + yaw180 + foyer_beam at the KF27 cue. The
	# authored foyer beam card must be visible; otherwise the frame is a failed
	# planned frame (beam_visible=false), never the Lounge beam_close pose.
	var r24: Dictionary = _row_by_id(rows, "S24")
	for pose: String in ["upper_foyer", "yaw180"]:
		var f: Dictionary = _frame_by_name("S24", pose)
		var cam24: Camera3D = _aim_player(mission, f.get("eye", Vector3.ZERO) as Vector3, f.get("target", Vector3.FORWARD) as Vector3)
		if cam24 == null:
			_clear_beat(rows, "S24", "player camera rig missing (player/head/cam); S24 needs camera_source=player")
			break
		await _wait(14)
		r24 = _add_frame(r24, await _shoot_frame("S24", pose, tap, cam24, "player"))
	if str(r24.get("status", "")) != "deferred":
		var fb: Dictionary = _frame_by_name("S24", "foyer_beam")
		var beam_visible: bool = _beam_card_visible_near(FOYER_BEAM_CARD_POS)
		print("P0B_ROUTE_S24 beam_visible=%s card=%s" % [str(beam_visible), str(FOYER_BEAM_CARD_POS)])
		if not beam_visible:
			r24 = _add_frame(r24, {
				"name": "foyer_beam",
				"ok": false,
				"beam_visible": false,
				"error": "beam_visible=false: no visible lightbeam_cards node within %.1f m of the authored C_107 card at %s" % [
					FOYER_BEAM_CARD_TOL_M, str(FOYER_BEAM_CARD_POS),
				],
			})
		else:
			var camf: Camera3D = _aim_player(mission, fb.get("eye", Vector3.ZERO) as Vector3, fb.get("target", Vector3.FORWARD) as Vector3)
			if camf == null:
				r24 = _add_frame(r24, {"name": "foyer_beam", "ok": false, "error": "player camera rig missing for the foyer_beam frame"})
			else:
				await _wait(14)
				var fbf: Dictionary = await _shoot_frame("S24", "foyer_beam", tap, camf, "player")
				fbf["beam_visible"] = true
				r24 = _add_frame(r24, fbf)
		_finish_row(r24, "S24 foyer poses upper_foyer/yaw180/foyer_beam via player camera (camera_source=player); the C_107 foyer beam card must be visible for the beam frame")

	# The p0b `beam_close` pose is the LOUNGE C_57 card, not S24/KF27. Record it
	# as a labelled extra (ref_keyframe=null) so it can never be read as a beat.
	var f_lounge_eye := LOUNGE_BEAM_EYE
	var f_lounge_target := LOUNGE_BEAM_TARGET
	var caml: Camera3D = _aim_player(mission, f_lounge_eye, f_lounge_target)
	if caml == null:
		_extra_poses.append({
			"id": LOUNGE_BEAM_ID, "subject": "Lounge C_57 beam", "beat": "",
			"ref_keyframe": null, "status": "failed",
			"reason": "player camera rig missing for the Lounge extra",
			"png": "", "t_s": -1.0, "frame_no": -1, "eye": _v3(f_lounge_eye),
			"target": _v3(f_lounge_target), "camera_source": "player", "note": "",
		})
	else:
		await _wait(14)
		var lx: Dictionary = await _shoot_frame("extra_" + LOUNGE_BEAM_ID, "pose", tap, caml, "player")
		_extra_poses.append({
			"id": LOUNGE_BEAM_ID, "subject": "Lounge C_57 beam", "beat": "",
			"ref_keyframe": null,
			"status": "captured" if bool(lx.get("ok", false)) else "failed",
			"reason": "" if bool(lx.get("ok", false)) else str(lx.get("error", "unknown")),
			"png": str(lx.get("png", "")), "t_s": float(lx.get("t_s", -1.0)),
			"frame_no": int(lx.get("frame_no", -1)),
			"eye": (lx.get("eye", []) as Array).duplicate(),
			"target": (lx.get("target", []) as Array).duplicate(),
			"camera_source": "player",
			"note": "p0b beam_close pose; Lounge C_57 beam at (39,28.82,-28.97)->(42.4,28.9,-28.97). NOT S24/KF27.",
		})
	print("P0B_ROUTE_EXTRA id=%s status=%s" % [
		LOUNGE_BEAM_ID, str((_extra_poses[_extra_poses.size() - 1] as Dictionary).get("status", "")),
	])

	# S27 Pause last: the tap must keep draining while the tree is paused.
	# Put the player back on the upper_foyer backdrop first (the Lounge extra
	# would otherwise be the paused view); this is staging, not an S24 claim.
	var r27: Dictionary = _row_by_id(rows, "S27")
	if hud != null and hud.has_method("toggle_pause"):
		var fp: Dictionary = _frame_by_name("S24", "upper_foyer")
		var cam27: Camera3D = _aim_player(mission, fp.get("eye", Vector3.ZERO) as Vector3, fp.get("target", Vector3.FORWARD) as Vector3)
		if cam27 == null:
			_defer_row(rows, "S27", "player camera rig missing for the upper_foyer backdrop")
		else:
			if tap != null:
				tap.set("process_mode", Node.PROCESS_MODE_ALWAYS)
			hud.call("toggle_pause")
			await _wait(16)
			if not paused:
				_defer_row(rows, "S27", "hud.toggle_pause() did not pause the SceneTree")
			else:
				r27 = _add_frame(r27, await _shoot_frame("S27", "pause", tap, null, "player"))
				_finish_row(r27, "hud.toggle_pause() over the loaded Guildhall mission; upper_foyer backdrop (player camera); audio tap PROCESS_MODE_ALWAYS; tree_paused=true")
				hud.call("toggle_pause")
				await _wait(8)
	else:
		_defer_row(rows, "S27", "hud.toggle_pause missing")

	mission.queue_free()
	await _wait(8)


# ---------------------------------------------------------------------------
# Capture / dry-run / self-test
# ---------------------------------------------------------------------------

func _capture() -> void:
	root.size = SIZE
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_capture_start_msec = Time.get_ticks_msec()
	_frame_seq = 0
	_extra_poses = []
	# The tap is created before the first screen so its Master effect is the
	# last element on the chain from the first staged frame.
	var tap_script: GDScript = load(AUDIO_SRC) as GDScript
	var tap: Node = null
	if tap_script != null:
		tap = tap_script.new() as Node
		root.add_child(tap)
		tap.call("start", 10.0)
		tap.call("mark", "route_start", "")
	var m: Dictionary = _base_manifest(false, false)
	var rows: Array = _make_rows()
	await _stage_s01(rows, tap)
	await _stage_s02(rows, tap)
	await _stage_den(rows, tap)
	await _stage_s09(rows, tap)
	await _stage_s10(rows, tap)
	await _stage_guildhall(rows, tap)
	m["beats"] = rows
	m["extras"] = _extra_poses
	var counts: Dictionary = _counts(rows)
	m["counts"] = counts
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs != null:
		(m["seed"] as Dictionary)["active_map_seed"] = int(gs.get("active_map_seed"))
		(m["settings"] as Dictionary)["difficulty"] = int(gs.get("difficulty"))
		(m["settings"] as Dictionary)["mission_mode"] = str(gs.get("active_mission_mode"))
		(m["settings"] as Dictionary)["active_map_id"] = str(gs.get("active_map_id"))
		(m["settings"] as Dictionary)["active_contract_order"] = int(gs.get("active_contract_order"))
		(m["settings"] as Dictionary)["free_play"] = bool(gs.get("free_play"))
		(m["settings"] as Dictionary)["active_mission_id"] = str(gs.get("active_mission_id"))
	if tap != null:
		var audio_res: Dictionary = tap.call("stop_to", _out_dir, "audio") as Dictionary
		audio_res["mark_kind"] = "mark"
		audio_res["route_claim"] = ROUTE_CLAIM
		audio_res["note"] = "Staged frames use mark() only; the S01..S27 beat-marker entry point is never called."
		m["audio"] = audio_res
	else:
		m["audio"] = {
			"schema": "tat2.audio_capture/1", "enabled": false,
			"reason": "audio_script_missing", "marks": [], "route_claim": ROUTE_CLAIM,
		}
	var captured: int = int(counts.get("captured", 0))
	var deferred: int = int(counts.get("deferred", 0))
	var partial: int = int(counts.get("partial", 0))
	var frame_errors: int = int(counts.get("frame_errors", 0))
	var failed: int = 0
	for r: Variant in rows:
		var row: Dictionary = r as Dictionary
		if str(row.get("status", "")) == "deferred" and str(row.get("source", "")) == "staged":
			failed += 1
	var all_good: bool = captured == STAGED_IDS.size() and deferred == 14 and partial == 0 and failed == 0 and frame_errors == 0
	m["status"] = "captured" if all_good else ("partial" if (captured > 0 or partial > 0) else "failed")
	m["finished_at_utc"] = _now_iso()
	var errs: Array = _validate_manifest(m)
	if not errs.is_empty():
		for e: Variant in errs:
			printerr("P0B_ROUTE_MANIFEST_INVALID ", str(e))
	m["manifest_errors"] = errs
	var ok: bool = _write_json(_manifest_path, m)
	if tap != null:
		tap.queue_free()
	var exit_ok: bool = ok and errs.is_empty() and failed == 0 and partial == 0 and frame_errors == 0 and str(m.get("status", "")) == "captured"
	print("P0B_ROUTE_CAPTURE_DONE status=%s beats=%d captured=%d deferred=%d partial=%d staged_failed=%d frame_errors=%d frames=%d errors=%d exit_ok=%s manifest=%s out=%s" % [
		str(m.get("status", "")), rows.size(), captured, deferred, partial, failed,
		frame_errors, int(counts.get("frames", 0)), errs.size(), str(exit_ok),
		_manifest_path, _out_dir,
	])
	quit(0 if exit_ok else 1)


func _dry_run() -> void:
	var m: Dictionary = _base_manifest(true, false)
	var rows: Array = _make_rows()
	_extra_poses = [_extra_plan()]
	m["beats"] = rows
	m["extras"] = _extra_poses
	m["counts"] = _counts(rows)
	m["status"] = "planned"
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
		"mark_kind": "mark",
		"route_claim": ROUTE_CLAIM,
		"note": "dry run: the tap was not started; a real capture records the WAV/PCM + per-mark dBFS windows or enabled=false with a reason.",
	}
	m["finished_at_utc"] = _now_iso()
	var errs: Array = _validate_manifest(m)
	m["manifest_errors"] = errs
	if not errs.is_empty():
		for e: Variant in errs:
			printerr("P0B_ROUTE_MANIFEST_INVALID ", str(e))
		quit(1)
		return
	if not _write_json(_manifest_path, m):
		quit(1)
		return
	var counts: Dictionary = m["counts"] as Dictionary
	print("P0B_ROUTE_DRY_RUN beats=%d planned=%d deferred=%d schema=%s manifest=%s" % [
		int(counts.get("beats", 0)), int(counts.get("planned", 0)),
		int(counts.get("deferred", 0)), SCHEMA, _manifest_path,
	])
	quit(0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("P0B_ROUTE_SELFTEST ok ", what)
	else:
		_fails += 1
		printerr("P0B_ROUTE_SELFTEST FAIL ", what)


func _self_path() -> String:
	var p: String = get_script().resource_path
	if p != "" and FileAccess.file_exists(p):
		return p
	for list: PackedStringArray in [OS.get_cmdline_user_args(), OS.get_cmdline_args()]:
		for i: int in range(list.size()):
			if list[i] == "--script" and i + 1 < list.size():
				return list[i + 1]
	return ""


func _self_test() -> void:
	# 1. Contract constants.
	_check(SCHEMA == "tat2.p0b_route/1", "schema is tat2.p0b_route/1")
	_check(BASE_SCHEMA == "tat2.p0b_capture/1", "base schema is tat2.p0b_capture/1")
	_check(MODE_STAGED == "staged" and ROUTE_CLAIM == "none", "mode=staged route_claim=none")
	_check(is_equal_approx(SHIPPED_FOV, 54.54), "shipped vertical FOV is 54.54")
	_check(SIZE == Vector2i(1920, 1080), "resolution is 1920x1080")
	_check(SETTLE_FRAMES == 60 and CAPTURE_FRAMES == 5, "settle 60 + 5 frames")
	_check(OFFICIAL_CLIP_SEED == 1025051536, "official clip seed recorded")

	# 2. The 27-beat table.
	_check(_beat_count_ok(), "27 beat ids S01..S27 in order")
	var times_ok: bool = true
	var monotonic: bool = true
	var prev_end: float = -1.0
	var meta_ok: bool = true
	var deferred_reason_ok: bool = true
	var staged_hook_ok: bool = true
	var class_ok: bool = true
	var frames_ok: bool = true
	for id: String in BEAT_IDS:
		var b: Dictionary = BEATS[id] as Dictionary
		var start: float = float(b.get("start", -1.0))
		var end: float = float(b.get("end", -1.0))
		if start < 0.0 or end <= start:
			times_ok = false
		if start < prev_end - 0.0005:
			monotonic = false
		prev_end = maxf(prev_end, end)
		if str(b.get("label", "")).is_empty() or str(b.get("ref", "")).is_empty():
			meta_ok = false
		if str(b.get("class", "")) not in ["ui", "world", "camera"]:
			class_ok = false
		if str(b.get("plan", "")) == "deferred" and str(b.get("reason", "")).strip_edges().is_empty():
			deferred_reason_ok = false
		if str(b.get("plan", "")) == "staged":
			if str(b.get("hook", "")).strip_edges().is_empty():
				staged_hook_ok = false
			if (b.get("frames", []) as Array).is_empty():
				frames_ok = false
			for f: Variant in (b.get("frames", []) as Array):
				var fd: Dictionary = f as Dictionary
				if str(fd.get("name", "")).is_empty():
					frames_ok = false
				if fd.has("eye") and fd.has("target"):
					if fd.get("eye", Vector3.ZERO) == fd.get("target", Vector3.ZERO):
						frames_ok = false
	_check(times_ok, "every beat has start >= 0 and end > start")
	_check(monotonic, "official start times are monotonic")
	_check(is_equal_approx(float((BEATS["S01"] as Dictionary).get("start", -1.0)), 0.0), "S01 starts at 0.00")
	_check(is_equal_approx(float((BEATS["S27"] as Dictionary).get("end", -1.0)), 225.64), "S27 ends at 225.64")
	_check(meta_ok, "every beat has a label and a reference keyframe")
	_check(class_ok, "every beat class is ui|world|camera")
	_check(deferred_reason_ok, "every deferred beat has a non-empty reason")
	_check(staged_hook_ok, "every staged beat has a non-empty stage_hook")
	_check(frames_ok, "every staged beat has frames with names and distinct eye/target")

	# 3. Plan vs dispatcher.
	var plan_ids: Array[String] = []
	for id: String in BEAT_IDS:
		if str((BEATS[id] as Dictionary).get("plan", "")) == "staged":
			plan_ids.append(id)
	_check(plan_ids.size() == 13, "13 beats planned to be staged (%d)" % plan_ids.size())
	_check(_sorted_ids(plan_ids) == _sorted_ids(STAGED_IDS), "plan ids match the capture dispatcher set")
	_check(STAGED_IDS.find("S05") > STAGED_IDS.find("S08"), "S05 is staged after S08 (no telescope exit before the Den beats)")
	_check(STAGED_IDS[STAGED_IDS.size() - 1] == "S27", "S27 pause is staged last")
	var deferred_n: int = 0
	for id: String in BEAT_IDS:
		if str((BEATS[id] as Dictionary).get("plan", "")) == "deferred":
			deferred_n += 1
	_check(deferred_n == 14, "14 beats deferred (%d)" % deferred_n)
	var known: bool = true
	for id: String in STAGED_IDS:
		if not BEAT_IDS.has(id):
			known = false
	_check(known, "every dispatcher id is an official beat")
	var s24_frames: Array = _beat_frames("S24")
	var s24_names: Array[String] = []
	for f: Variant in s24_frames:
		s24_names.append(str((f as Dictionary).get("name", "")))
	_check(s24_names == ["upper_foyer", "yaw180", "foyer_beam"], "S24 frames are the foyer poses + foyer_beam (no Lounge beam_close)")
	_check(not s24_names.has("beam_close"), "S24 does not use the Lounge beam_close pose")
	_check(LOUNGE_BEAM_ID == "lounge_beam_close" and LOUNGE_BEAM_EYE == Vector3(39.0, 28.82, -28.97), "Lounge C_57 extra pose is labelled separately")
	_check(FOYER_BEAM_CARD_POS == Vector3(23.27, 29.76, -57.4), "foyer beam cue targets the authored C_107 card")

	# 4. Frame-result state machine (E3): a secondary failure is never captured.
	var prow: Dictionary = _row("planned")
	prow["id"] = "S24"
	prow["source"] = "staged"
	prow = _add_frame(prow, {
		"name": "a", "ok": true, "png": "x.png", "t_s": 1.0, "frame_no": 0,
		"eye": [0.0, 0.0, 0.0], "target": [0.0, 0.0, 1.0], "camera_source": "player",
	})
	_check(str(prow.get("status", "")) == "captured", "a successful first frame marks captured")
	prow = _add_frame(prow, {"name": "b", "ok": false, "error": "unit"})
	_check(str(prow.get("status", "")) == "partial" and int((prow.get("frame_errors", []) as Array).size()) == 1,
		"a secondary frame failure marks partial, not captured")

	# 5. No played-beat marker in this runner.
	var src: String = _self_path()
	var needle_call: String = "mark_" + "beat("
	var needle_any: String = "mark_" + "beat"
	var body: String = ""
	if src != "":
		var f: FileAccess = FileAccess.open(src, FileAccess.READ)
		if f != null:
			body = f.get_as_text()
			f.close()
	_check(body != "", "runner source readable for the marker scan")
	_check(body.find(needle_call) < 0, "no beat-marker call in the runner")
	_check(body.find(needle_any) < 0, "no beat-marker token in the runner")

	# 6. Manifest shape: build a dry-run manifest, validate, round-trip.
	var m: Dictionary = _base_manifest(true, true)
	var rows: Array = _make_rows()
	m["beats"] = rows
	m["counts"] = _counts(rows)
	m["audio"] = {"schema": "tat2.audio_capture/1", "enabled": false, "reason": "self_test", "marks": []}
	var errs: Array = _validate_manifest(m)
	_check(errs.is_empty(), "dry-run manifest validates (%d errors)" % errs.size())
	for e: Variant in errs:
		printerr("P0B_ROUTE_MANIFEST_INVALID ", str(e))
	_check(int((m["counts"] as Dictionary).get("plan_staged", 0)) == 13, "manifest counts 13 staged")
	_check(int((m["counts"] as Dictionary).get("deferred", 0)) == 14, "manifest counts 14 deferred")
	_check(_write_json(self_test_manifest_path(), m), "self-test manifest writes")
	var back: Dictionary = _read_json(self_test_manifest_path())
	_check(not back.is_empty(), "self-test manifest reads back")
	_check(_validate_manifest(back).is_empty(), "round-tripped manifest validates")

	# 7. Output paths.
	_check(dry_manifest_path().ends_with("docs/reports/logs/p0b-route/dry-run/manifest.json"), "dry-run manifest path is tracked")
	_check(capture_manifest_path("R").ends_with("docs/reports/logs/p0b-route/R/manifest.json"), "capture manifest path is tracked per run")
	_check(_repo_root.path_join("build/qa/p0b_route").begins_with(_repo_root), "capture media root is under build/qa/p0b_route")

	# 8. Headless provenance and wrapper governance.
	var gb: Dictionary = back.get("gpu", {}) as Dictionary
	_check(bool(gb.get("queried", true)) == false and str(gb.get("reason", "")) == "headless", "dry-run gpu block is not queried (no nvidia-smi)")
	var eb: Dictionary = back.get("engine", {}) as Dictionary
	_check(eb.has("configured_rendering_driver") and not eb.has("rendering_driver"), "engine records configured_rendering_driver")
	var wrapper_path: String = _repo_root.path_join("build/qa/p0b_route.sh")
	var wrapper_txt: String = ""
	if FileAccess.file_exists(wrapper_path):
		var wf: FileAccess = FileAccess.open(wrapper_path, FileAccess.READ)
		if wf != null:
			wrapper_txt = wf.get_as_text()
			wf.close()
	_check(wrapper_txt.find("export TAT2_PARITY_ONLY=1") >= 0, "wrapper exports TAT2_PARITY_ONLY=1 for every mode")

	# 9. Negative controls: the validator must reject each defect.
	var bad: Dictionary = back.duplicate(true)
	(bad["lens"] as Dictionary)["fov_vertical_deg"] = 75.0
	_check(not _validate_manifest(bad).is_empty(), "wrong FOV is rejected")
	var bad2: Dictionary = back.duplicate(true)
	var b2: Array = bad2["beats"] as Array
	b2.remove_at(26)
	_check(not _validate_manifest(bad2).is_empty(), "26 beats is rejected")
	var bad3: Dictionary = back.duplicate(true)
	var b3: Array = bad3["beats"] as Array
	(b3[1] as Dictionary)["id"] = "S01"
	_check(not _validate_manifest(bad3).is_empty(), "duplicate id is rejected")
	var bad4: Dictionary = back.duplicate(true)
	(bad4["beats"] as Array)[6] = _bad_row_copy(back, 6, "reason", "")
	_check(not _validate_manifest(bad4).is_empty(), "deferred without a reason is rejected")
	var bad5: Dictionary = back.duplicate(true)
	(bad5["beats"] as Array)[0] = _bad_row_copy(back, 0, "stage_hook", "")
	_check(not _validate_manifest(bad5).is_empty(), "staged without a hook is rejected")
	var bad6: Dictionary = back.duplicate(true)
	bad6["route_claim"] = "played"
	_check(not _validate_manifest(bad6).is_empty(), "route_claim=played is rejected")
	var bad7: Dictionary = back.duplicate(true)
	(bad7["beats"] as Array)[0] = _bad_row_copy(back, 0, "mark_kind", "mark_" + "beat")
	_check(not _validate_manifest(bad7).is_empty(), "non-mark mark_kind is rejected")
	var bad8: Dictionary = back.duplicate(true)
	(bad8["settle"] as Dictionary)["frames"] = 12
	_check(not _validate_manifest(bad8).is_empty(), "wrong settle count is rejected")
	var bad9: Dictionary = back.duplicate(true)
	(bad9["counts"] as Dictionary)["captured"] = 1
	_check(not _validate_manifest(bad9).is_empty(), "counts/rows mismatch is rejected")
	var bad10: Dictionary = back.duplicate(true)
	var r10: Dictionary = ((bad10["beats"] as Array)[0] as Dictionary)
	r10["status"] = "partial"
	r10["reason"] = ""
	_check(not _validate_manifest(bad10).is_empty(), "partial without a reason is rejected")
	var bad11: Dictionary = back.duplicate(true)
	bad11["extras"] = [{"id": "x", "subject": "y", "beat": "S24", "ref_keyframe": null, "status": "captured", "png": "x.png"}]
	(bad11["counts"] as Dictionary)["extras"] = 1
	_check(not _validate_manifest(bad11).is_empty(), "an extra claiming a beat is rejected")
	var bad12: Dictionary = back.duplicate(true)
	bad12["dry_run"] = false
	var r12: Dictionary = ((bad12["beats"] as Array)[0] as Dictionary)
	r12["status"] = "captured"
	r12["png"] = "x.png"
	r12["t_s"] = 1.0
	r12["frame_no"] = 0
	r12["evidence"] = "x"
	r12["frames"] = [{"name": "x", "ok": true, "png": "x.png"}]
	r12["frame_errors"] = ["secondary: missing"]
	(bad12["counts"] as Dictionary)["captured"] = 1
	(bad12["counts"] as Dictionary)["planned"] = 12
	_check(not _validate_manifest(bad12).is_empty(), "captured with frame_errors is rejected")

	# 10. Audio tap: disabled under headless with a reason, never a crash.
	var tap_script: GDScript = load(AUDIO_SRC) as GDScript
	_check(tap_script != null, "audio_capture.gd loads")
	if tap_script != null:
		var tap: Node = tap_script.new() as Node
		root.add_child(tap)
		tap.call("start", 1.0)
		await _wait(3)
		tap.call("mark", "selftest", "")
		var res: Dictionary = tap.call("stop_to", _repo_root.path_join("build/qa/p0b_route/selftest"), "selftest_audio") as Dictionary
		var is_dummy: bool = AudioServer.get_driver_name().to_lower() == "dummy"
		_check(typeof(res.get("enabled")) == TYPE_BOOL, "audio result has enabled")
		_check(not str(res.get("reason", "")).is_empty() or bool(res.get("enabled")), "audio result explains a disabled tap")
		if is_dummy:
			_check(not bool(res.get("enabled", true)), "dummy driver -> disabled tap")
			_check(str(res.get("reason", "")) == "dummy_audio_driver", "dummy reason is dummy_audio_driver")
		_check(FileAccess.file_exists(str(res.get("sidecar", ""))), "audio sidecar written")
		tap.queue_free()
		await _wait(1)

	print("P0B_ROUTE_SELFTEST_SUMMARY checks=%d fails=%d" % [_checks, _fails])
	print("P0B_ROUTE_SELFTEST %s checks=%d fails=%d" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	quit(0 if _fails == 0 else 1)


func _bad_row_copy(m: Dictionary, idx: int, key: String, value: Variant) -> Dictionary:
	var row: Dictionary = ((m["beats"] as Array)[idx] as Dictionary).duplicate(true)
	row[key] = value
	return row


func _sorted_ids(ids: Array[String]) -> Array[String]:
	var out: Array[String] = ids.duplicate()
	out.sort()
	return out


func _beat_count_ok() -> bool:
	if BEAT_IDS.size() != ROUTE_BEAT_COUNT:
		return false
	for i: int in range(ROUTE_BEAT_COUNT):
		var want: String = "S%02d" % (i + 1)
		if BEAT_IDS[i] != want or not BEATS.has(want):
			return false
	return true


func _run() -> void:
	_mode = _arg("--mode=", "capture")
	_seed_arg = _arg("--seed=", "derived")
	_setup_paths()
	print("P0B_ROUTE_START mode=%s run=%s schema=%s seed=%s fov=%.2f size=%s out=%s manifest=%s" % [
		_mode, _run_id, SCHEMA, _seed_arg, SHIPPED_FOV, str(SIZE), _out_dir, _manifest_path,
	])
	if _mode == "dry-run":
		_dry_run()
	elif _mode == "self-test":
		await _self_test()
	elif _mode == "capture":
		await _capture()
	else:
		printerr("P0B_ROUTE unknown mode=", _mode, " (capture|dry-run|self-test)")
		quit(2)
