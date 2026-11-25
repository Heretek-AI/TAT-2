class_name AudioWwise
extends RefCounted
## T03: the authored Wwise asset graph -> a real Godot audio bus graph.
##
## Source: `res://data/generated/audio_wwise.json`, schema
## `tat2.audio_wwise/1`, produced by `tools/parse_wwise.py` from the shipped
## `WwiseSharedAssetLibrary.json` + `extracted/audio-meta/**` dump. This class
## consumes that document; it never parses the bank itself and never invents a
## name, event, radius or curve.
##
## Degradation contract: the JSON is derived content and is absent on a fresh
## clone. [method load_data] then returns false, [method degraded_reason]
## explains why, every getter returns a documented empty/neutral value and
## [method build_buses] touches nothing (no bus is created, Master is left
## alone), so the legacy `audio_manager` bus layout keeps working.
##
## Bus topology (what [method build_buses] actually builds):
##   * one Godot bus per authored named `VERB_*` aux bus, output -> Master;
##   * one `AudioEffectReverb` insert per such bus, seeded from the authored
##     `reverb_assignment[].decay_s` (see [method reverb_params_for_decay]);
##   * the authored convolution impulse cannot be loaded (the media is a PLUG
##     chunk, and Godot 4.7.2 has no `AudioEffectConvolution`), so a bus whose
##     `reverb_buses[].ir_name` is authored reports
##     `"convolution": "unavailable:<ir_name>"` + `"fallback": "AudioEffectReverb"`
##     instead of silently pretending the impulse plays;
##   * the authored mastering chain on Master: `AudioEffectEQ10` (flat) ->
##     `AudioEffectHardLimiter` (ceiling from AkPeakLimiterFX/MasteringSuiteFX
##     params when present, else a documented -0.3 dB).
##
## The build is idempotent: a second call reuses the buses/effects it finds and
## changes nothing. `AudioServer` is a global singleton, so the report — not the
## call — is the source of truth for what this instance created.
##
## Godot limitation, stated honestly: a Godot bus has exactly one output and no
## per-send gain. A true Wwise aux send/return (dry to Master + N independent
## sends) cannot be represented. [method build_buses] therefore re-parents each
## existing gameplay bus through the exterior reverb bus, whose
## `AudioEffectReverb` keeps `dry = 1.0` and adds the authored wet tail: the dry
## and wet paths are summed inside that bus. [method set_reverb_send] can scale
## that wet level, but the level is shared by every source feeding the reverb
## bus. Master (bus 0) is the terminal output and cannot be sent anywhere.

const SCHEMA: String = "tat2.audio_wwise/1"
const DEFAULT_PATH: String = "res://data/generated/audio_wwise.json"
const ENV_OVERRIDE: String = "TAT2_AUDIO_WWISE_JSON"

const MASTER_BUS: String = "Master"
## Legacy gameplay buses owned by audio_manager.gd; build_buses only reparents
## the ones that already exist (it never creates them).
const GAMEPLAY_BUSES: Array[String] = ["SFX", "Ambience", "Music", "UI", "Dialogue"]
const REVERB_PREFIX: String = "VERB_"

# -- reverb seed mapping (decay seconds -> AudioEffectReverb) ----------------
# Documented, monotonic in the authored decay:
#   t          = clamp((decay - 0.2) / (10.0 - 0.2), 0, 1)
#   room_size  = t                                   (bigger hall  -> bigger room)
#   damping    = clamp(1.0 - 0.7 * t, 0.05, 1.0)     (bigger hall  -> less HF damping)
#   wet        = 0.08 + 0.32 * t                     (bigger hall  -> more wet, max 0.40)
#   predelay   = clamp(decay * 15.0, 10, 120) ms
# dry stays 1.0 so the direct path through the bus is never attenuated.
const REVERB_DECAY_MIN_S: float = 0.2
const REVERB_DECAY_MAX_S: float = 10.0
const REVERB_WET_MIN: float = 0.08
const REVERB_WET_MAX: float = 0.40
const REVERB_DAMPING_MIN: float = 0.05
const REVERB_DAMPING_SLOPE: float = 0.7
const REVERB_PREDELAY_PER_S: float = 15.0
const REVERB_PREDELAY_MIN_MS: float = 10.0
const REVERB_PREDELAY_MAX_MS: float = 120.0
## Used for a named aux bus with no `reverb_assignment` row (the fixture's
## second bus, and any authored bus the assignment table does not cover).
const REVERB_DEFAULT_DECAY_S: float = 1.0

# -- mastering chain ---------------------------------------------------------
## Authored Wwise mastering plugins, in the order their params are consulted.
const MASTERING_PLUGINS: Array[String] = ["AkPeakLimiterFX", "MasteringSuiteFX"]
## Param keys tried for the limiter ceiling, normalised (lowercase, no `_`/space).
const CEILING_KEYS: Array[String] = [
	"ceilingdb", "ceiling", "outputceiling", "outputceilingdb", "limitedb",
	"thresholddb", "threshold", "outputlevel", "output_level", "outputgain",
]
## The authored ceiling is absent from most banks; -0.3 dB is the documented
## fallback (a conventional inter-sample-safe master ceiling).
const LIMITER_DEFAULT_CEILING_DB: float = -0.3
const LIMITER_CEILING_MIN_DB: float = -24.0
const EQ_BANDS_NOTE: String = "flat: the authored bus EQ params are not present in the bank"

# -- attenuation ------------------------------------------------------------
## Wwise attenuation curve abscissae are authored in metres; they are consumed
## verbatim (no cm scaling) and the ordinate is dB, applied to `max_db = 0`.
const UNIT_SIZE_MIN: float = 0.1
const UNIT_SIZE_MAX: float = 400.0
## Curve points fainter than this are inaudible; they are excluded from the
## unit_size fit so a -60 dB tail cannot drag the whole falloff down.
const AUDIBLE_FIT_FLOOR_DB: float = -24.0
## `max_distance_m * 0.1` when the authored curve has no 0 dB plateau point.
const UNIT_SIZE_RADIUS_RATIO: float = 0.1
const DEFAULT_MAX_DISTANCE_M: float = 60.0
## Godot 4.7.2 has no `ATTENUATION_LINEAR` (that was Godot 3) and cannot
## evaluate an authored curve per frame. A curved event therefore stamps the
## authored envelope onto inverse distance with `unit_size` pinned to the end of
## the authored 0 dB plateau, which reproduces the authored inner radius and the
## hard `max_distance`; `attenuation_for()` still returns the full dB curve for a
## caller that wants to drive `volume_db` itself.
const CURVE_ATTENUATION_MODEL: AudioStreamPlayer3D.AttenuationModel = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
const FLAT_ATTENUATION_MODEL: AudioStreamPlayer3D.AttenuationModel = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
const ZERO_DB_EPSILON: float = 0.01

# -- occlusion --------------------------------------------------------------
## The authored `TransmissionLoss = 1.0` is a multiplier on transmitted energy
## (1.0 = no extra loss authored), not a dB value. The occlusion model adds one
## documented wall loss, scaled by that authored multiplier:
##   occlusion_gain_db(loss) = -20 * log10(max(loss, 0.001))   (0 dB at 1.0)
##   apply_occlusion(blocked) = OCCLUSION_WALL_DB * loss       (-12 dB at 1.0)
const OCCLUSION_WALL_DB: float = -12.0
const OCCLUSION_LOSS_FLOOR: float = 0.001
const OCCLUSION_CUTOFF_UNITY_HZ: float = 20000.0
const OCCLUSION_CUTOFF_MIN_HZ: float = 400.0
const OCCLUSION_CUTOFF_MAX_HZ: float = 22000.0

# -- authored music events (kind -> exact event name) -----------------------
## Exact names from the shipped bank. A name is returned only when it really is
## in `music.play_events`; an absent name returns "" (nothing is invented).
const MUSIC_EVENTS: Dictionary = {
	"title": "Play_Mus_MainTitleScreen",
	"character_select": "Play_Mus_CharacterSelectScreen",
	"guard_alerted": "Play_Mus_GuardAlerted_Generic_01",
	"guard_search": "Play_Mus_Guard_Searching_Suspense_Generic_MX",
	"quest_complete": "Play_Mus_Stinger_Quest_Complete",
	"escape_riser": "Play_Mus_Stinger_EscapePoint_Riser",
	"end_escape": "Play_Mus_EndMission_Escape",
	"end_caught": "Play_Mus_EndMission_Caught",
	"mission": "Play_Mus_TVT_Match_Generic_Mission_MX",
	"tutorial": "Play_Mus_TVT_Tutorial_Generic_MX",
	"tutorial_intro": "Play_Mus_TutorialIntro_01",
	"endgame": "Play_Mus_EndGame_Start_MX",
	"end_match_1m": "Play_Mus_EndMatch_MX_1m",
}

## Game map id -> the dump basenames the producer stores on emitters/room beds.
## Documented prefix mapping; an unlisted id resolves to no basename at all, so
## no emitter is ever invented for an unknown map.
const EMITTER_MAP_KEYS: Dictionary = {
	"guildhall": ["Guildhall_Audio"],
	"ftue": ["FTUE_Audio"],
	"old_manor": ["OldManor_Audio", "OldManor_Audio_Ext"],
	"oldmanor": ["OldManor_Audio", "OldManor_Audio_Ext"],
	"manor": ["OldManor_Audio", "OldManor_Audio_Ext"],
	"main_menu": ["BeautifulCorner_Startscreen_P"],
	"startscreen": ["BeautifulCorner_Startscreen_P"],
	"beautifulcorner": ["BeautifulCorner_Startscreen_P"],
}
## Reverb bus kind -> documented default authored bus (used when no decay is
## supplied). Returned only when the data really contains that named bus.
const REVERB_DEFAULTS: Dictionary = {
	"interior": "VERB_Cmn_Int_Room_Medium",
	"exterior": "VERB_Cmn_Ext_World",
}
const REVERB_INT_MARKER: String = "_int_"
const REVERB_EXT_MARKER: String = "_ext_"

const TOPOLOGY_LIMITATIONS: Array[String] = [
	"Godot buses have exactly one output and no per-send gain: a true Wwise multi-send return with independent send levels is not representable. build_buses() re-parents each existing gameplay bus output through one reverb bus; set_reverb_send() scales that reverb bus's shared wet level.",
	"Master (bus 0) is the terminal output: sending it to a reverb bus would create a cycle, so the Master send is reported as skipped, not applied.",
	"AudioEffectConvolution does not exist in Godot 4.7.2 and the authored impulse media is a PLUG chunk: a named IR degrades to AudioEffectReverb seeded from the authored decay, reported per bus.",
	"Godot has no per-bus distance attenuation; the authored MaxAttenuationRadius is reported as an informational note only.",
	"Authored aux bus volume_db is reported but not applied: gameplay bus levels are owned by audio_manager.apply_volumes().",
]

## Diagnostic prints only; off by default (no print on any runtime path).
var debug: bool = false

var _loaded: bool = false
var _reason: String = ""
var _path: String = ""
var _generated_by: String = ""
var _sources: Dictionary = {}
var _declared_counts: Dictionary = {}

var _buses: Array[Dictionary] = []
var _bus_by_name: Dictionary = {}
var _fx: Array[Dictionary] = []
var _fx_by_id: Dictionary = {}
var _attenuations: Dictionary = {}
var _events: Dictionary = {}
var _transmission: Array[Dictionary] = []
var _reverb_assignments: Array[Dictionary] = []
var _reverb_buses: Array[Dictionary] = []
var _reverb_by_name: Dictionary = {}
var _music_play: PackedStringArray = PackedStringArray()
var _music_stop: PackedStringArray = PackedStringArray()
var _music_mute: PackedStringArray = PackedStringArray()
var _music_unmute: PackedStringArray = PackedStringArray()
var _music_segments: int = 0
var _music_tracks: int = 0
var _emitters: Array[Dictionary] = []
var _room_beds: Array[Dictionary] = []
var _vo_lines: Dictionary = {}
var _vo_speakers: Dictionary = {}
var _warnings: PackedStringArray = PackedStringArray()

var _built: bool = false
var _report: Dictionary = {}


# =========================================================================
# Loading
# =========================================================================


## Loads the produced Wwise document. Path resolution: explicit [param path] ->
## `TAT2_AUDIO_WWISE_JSON` -> [constant DEFAULT_PATH]. A missing/unreadable/
## wrong-schema file is not fatal: it clears the graph, returns false and stores
## a human-readable reason in [method degraded_reason].
func load_data(path: String = "") -> bool:
	_reset()
	var target: String = path.strip_edges()
	if target.is_empty():
		var override: String = OS.get_environment(ENV_OVERRIDE).strip_edges()
		target = override if not override.is_empty() else DEFAULT_PATH
	_path = target

	if not FileAccess.file_exists(target):
		_reason = "audio_wwise.json absent: %s (authored Wwise graph unavailable; legacy bus layout untouched)" % target
		return false
	var file: FileAccess = FileAccess.open(target, FileAccess.READ)
	if file == null:
		_reason = "audio_wwise.json unreadable: %s (error %d)" % [target, FileAccess.get_open_error()]
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_reason = "audio_wwise.json is not a JSON object: %s" % target
		return false
	var doc: Dictionary = parsed
	var schema: String = str(doc.get("schema", ""))
	if schema != SCHEMA:
		_reason = "audio_wwise.json schema '%s' != '%s': %s" % [schema, SCHEMA, target]
		return false

	_generated_by = str(doc.get("generated_by", ""))
	_sources = _as_dict(doc.get("sources")).duplicate(true)
	_declared_counts = _as_dict(doc.get("counts")).duplicate(true)
	_parse_buses(_as_array(doc.get("buses")))
	_parse_fx(_as_array(doc.get("fx")))
	_parse_attenuations(_as_array(doc.get("attenuation")))
	_parse_events(_as_array(doc.get("events")))
	_parse_transmission(_as_array(doc.get("transmission_loss")))
	_parse_reverb(_as_array(doc.get("reverb_assignment")), _as_array(doc.get("reverb_buses")))
	_parse_music(_as_dict(doc.get("music")))
	_parse_ambience(_as_dict(doc.get("ambience")))
	_parse_vo(_as_dict(doc.get("vo")))
	for w: Variant in _as_array(doc.get("warnings")):
		_warnings.append(str(w))

	_loaded = true
	_reason = ""
	return true


func is_loaded() -> bool:
	return _loaded


## "" when loaded, otherwise the reason the authored graph is unavailable.
func degraded_reason() -> String:
	return _reason


## The producer's declared `counts` block (a copy). Empty when not loaded.
func counts() -> Dictionary:
	return _declared_counts.duplicate(true)


# =========================================================================
# Bus construction
# =========================================================================


## Builds the authored reverb buses + mastering chain into `AudioServer`.
## Idempotent. Returns (and stores) the same report as [method bus_report].
func build_buses() -> Dictionary:
	if not _loaded:
		_report = _empty_report()
		return _report.duplicate(true)
	if _built:
		# audio_manager._ensure_buses() creates SFX/Ambience/Music/UI/Dialogue
		# after _load_wwise() and then calls build_buses() again; refresh the send
		# graph so those buses are routed the first time they exist. Nothing is
		# re-created, so bus/effect idempotency is unchanged.
		_report["sends"] = _build_default_sends()
		_report["master_effects"] = _master_effect_classes()
		return _report.duplicate(true)
	_built = true

	var report: Dictionary = _empty_report()
	report["built"] = true
	report["degraded"] = ""
	report["schema"] = SCHEMA
	report["generated_by"] = _generated_by
	report["path"] = _path
	report["topology"] = _topology_text()

	var rows: Array = []
	var created: int = 0
	var existing: int = 0
	var effects_added: int = 0
	for bus_name: String in _reverb_bus_names():
		var idx: int = AudioServer.get_bus_index(bus_name)
		var was_created: bool = false
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, MASTER_BUS)
			created += 1
			was_created = true
		else:
			existing += 1

		var decay_s: float = _decay_for(bus_name)
		var params: Dictionary = reverb_params_for_decay(decay_s)
		var effect: AudioEffectReverb = _find_reverb_effect(idx)
		var effect_created: bool = false
		if effect == null:
			effect = AudioEffectReverb.new()
			AudioServer.add_bus_effect(idx, effect, -1)
			effects_added += 1
			effect_created = true
		effect.room_size = float(params["room_size"])
		effect.damping = float(params["damping"])
		effect.wet = float(params["wet"])
		effect.dry = 1.0
		effect.predelay_msec = float(params["predelay_ms"])
		effect.predelay_feedback = 0.0
		effect.hipass = 0.0
		effect.spread = 1.0

		var ir_name: String = _ir_for(bus_name)
		var radius_m: float = _max_radius_m_for(bus_name)
		var row: Dictionary = {
			"name": bus_name,
			"kind": _bus_kind(bus_name),
			"index": idx,
			"created": was_created,
			"output": MASTER_BUS,
			"effect": "AudioEffectReverb",
			"effect_created": effect_created,
			"decay_s": decay_s,
			"room_size": effect.room_size,
			"damping": effect.damping,
			"wet": effect.wet,
			"dry": effect.dry,
			"predelay_ms": effect.predelay_msec,
			"authored_volume_db": _authored_bus_volume(bus_name),
			"volume_applied": false,
			"max_radius_m": radius_m if radius_m >= 0.0 else null,
			"convolution": "unavailable:%s" % ir_name if not ir_name.is_empty() else "none",
			"fallback": "AudioEffectReverb" if not ir_name.is_empty() else "",
			"distance_note": _distance_note(bus_name, radius_m),
		}
		rows.append(row)
	report["buses"] = rows

	# Mastering chain on Master: EQ10 (flat, first) -> HardLimiter (last).
	var master: Dictionary = _build_master_chain()
	effects_added += int(master.get("effects_added", 0))
	report["master"] = master

	# Default sends for the gameplay buses that already exist.
	report["sends"] = _build_default_sends()

	var built_effects: Array = _master_effect_classes()
	report["master_effects"] = built_effects

	report["counts"] = {
		"buses_created": created,
		"buses_existing": existing,
		"bus_effects_added": effects_added,
		"reverb_buses": rows.size(),
	}
	_report = report
	if debug:
		print("[audio_wwise] built reverb buses=%d (created=%d) effects_added=%d" % [
			rows.size(), created, effects_added])
	return _report.duplicate(true)


## Re-applies the default send graph and returns it. The integrator's
## audio_manager calls build_buses() from _ensure_buses(), which already covers
## the normal ordering; this is the explicit hook for any other boot order.
func apply_default_sends() -> Dictionary:
	if not _loaded:
		return {}
	var sends: Dictionary = _build_default_sends()
	if not _report.is_empty():
		_report["sends"] = sends
	return sends.duplicate(true)


## What this instance actually built (a copy). Empty-but-shaped when not built.
func bus_report() -> Dictionary:
	if _report.is_empty():
		return _empty_report()
	return _report.duplicate(true)


## Documented decay -> AudioEffectReverb seed mapping (see the constants block).
func reverb_params_for_decay(decay_s: float) -> Dictionary:
	var t: float = clampf(
		(decay_s - REVERB_DECAY_MIN_S) / (REVERB_DECAY_MAX_S - REVERB_DECAY_MIN_S),
		0.0, 1.0)
	return {
		"decay_s": decay_s,
		"room_size": t,
		"damping": clampf(1.0 - REVERB_DAMPING_SLOPE * t, REVERB_DAMPING_MIN, 1.0),
		"wet": clampf(REVERB_WET_MIN + (REVERB_WET_MAX - REVERB_WET_MIN) * t,
			REVERB_WET_MIN, REVERB_WET_MAX),
		"dry": 1.0,
		"predelay_ms": clampf(decay_s * REVERB_PREDELAY_PER_S,
			REVERB_PREDELAY_MIN_MS, REVERB_PREDELAY_MAX_MS),
	}


## Re-parents [param bus]'s output into [param reverb_bus]. The dry path is kept
## by the reverb bus's `dry = 1.0` insert, not by a second bus. Refuses cycles
## and Master. Returns true when the bus output now targets the reverb bus.
## (audio_manager._route_bus_reverb calls this and expects a bool; use
## [method set_reverb_send] when the reason for a refusal is needed.)
func route_bus_to_reverb(bus: String, reverb_bus: String) -> bool:
	return bool(_route_bus_detailed(bus, reverb_bus)["ok"])


func _route_bus_detailed(bus: String, reverb_bus: String) -> Dictionary:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx < 0:
		return {"ok": false, "output": "", "reason": "source bus absent: %s" % bus}
	if bus == MASTER_BUS:
		return {"ok": false, "output": "", "reason": "Master is the terminal bus (send would cycle)"}
	if AudioServer.get_bus_index(reverb_bus) < 0:
		return {"ok": false, "output": "", "reason": "reverb bus absent: %s" % reverb_bus}
	if bus == reverb_bus:
		return {"ok": false, "output": "", "reason": "source and target are the same bus"}
	var walk: String = reverb_bus
	var guard: int = 0
	while not walk.is_empty() and guard < 64:
		if walk == bus:
			return {"ok": false, "output": "", "reason": "routing would create a cycle"}
		var walk_idx: int = AudioServer.get_bus_index(walk)
		if walk_idx < 0:
			break
		walk = str(AudioServer.get_bus_send(walk_idx))
		guard += 1
	AudioServer.set_bus_send(idx, reverb_bus)
	return {"ok": true, "output": reverb_bus, "reason": "routed"}


## Routes [param bus] into [param reverb_bus] and scales that reverb bus's shared
## wet level by [param amount_db]. Godot has no per-send volume, so the amount is
## applied to the reverb bus (documented in the returned `limitation`).
func set_reverb_send(bus: String, reverb_bus: String, amount_db: float) -> Dictionary:
	if not _loaded:
		return {"ok": false, "applied": false, "reason": "degraded: %s" % _reason,
			"limitation": _send_limitation()}
	if not _built:
		build_buses()
	var routed: Dictionary = _route_bus_detailed(bus, reverb_bus)
	if not bool(routed.get("ok", false)):
		return {"ok": false, "applied": false, "reason": str(routed.get("reason", "")),
			"limitation": _send_limitation()}
	var idx: int = AudioServer.get_bus_index(reverb_bus)
	var effect: AudioEffectReverb = _find_reverb_effect(idx)
	var base_wet: float = float(_base_wet_for(reverb_bus))
	var wet: float = clampf(base_wet * db_to_linear(amount_db), 0.0, 1.0)
	if effect != null:
		effect.wet = wet
	return {
		"ok": true,
		"applied": true,
		"output": reverb_bus,
		"amount_db": amount_db,
		"wet": wet,
		"limitation": _send_limitation(),
	}


# =========================================================================
# Attenuation / occlusion
# =========================================================================


## Authored attenuation for [param event_name].
## `{found, max_distance_m, unit_size, curve:[{from_m, gain_db}], is_2d,
##   attenuation_id}`. Unknown event (or no data): found=false with neutral
## zeros. `max_radius_cm == 0` is the authored 2D case.
func attenuation_for(event_name: String) -> Dictionary:
	var out: Dictionary = {
		"found": false,
		"max_distance_m": 0.0,
		"unit_size": 0.0,
		"curve": [],
		"is_2d": false,
		"attenuation_id": 0,
	}
	if not _loaded:
		return out
	var raw: Variant = _events.get(event_name)
	if not (raw is Dictionary):
		return out
	var event: Dictionary = raw
	var radius_cm: float = maxf(float(event["max_radius_cm"]), 0.0)
	var max_m: float = radius_cm / 100.0
	var attenuation_id: int = int(event["attenuation"])
	var raw_curve: Array = []
	if attenuation_id != 0 and _attenuations.has(attenuation_id):
		var att: Dictionary = _attenuations[attenuation_id]
		for point: Variant in (att["curve"] as Array):
			if point is Dictionary:
				var pd: Dictionary = point
				raw_curve.append({"from_m": float(pd["from_m"]), "gain_db": float(pd["gain_db"])})
	# Authored pairing: an attenuation curve ends at the radius it is applied
	# with. Verified on two independent sharesets — 530952049 ends at 2500 and
	# its only user (Play_Prop_Int_Door_Wood_Open) authors MaxAttenuationRadius
	# 2500 cm; 364264856 ends at 7500 and Play_VO_Enforcer1_169_* authors
	# 7500 cm — so the bank stores the abscissa in the event's centimetre space.
	# Normalising the last point onto the event's authored radius resolves that
	# unit without guessing, and is a no-op when the bank is already in metres.
	var raw_end: float = 0.0
	for point: Variant in raw_curve:
		raw_end = maxf(raw_end, float((point as Dictionary)["from_m"]))
	var curve_scale: float = 1.0
	if raw_end > 0.0 and max_m > 0.0 and not is_equal_approx(raw_end, max_m):
		curve_scale = max_m / raw_end
	var curve: Array = []
	for point: Variant in raw_curve:
		var pd: Dictionary = point
		curve.append({"from_m": float(pd["from_m"]) * curve_scale, "gain_db": float(pd["gain_db"])})
	out["found"] = true
	out["max_distance_m"] = radius_cm / 100.0
	out["is_2d"] = radius_cm <= 0.0
	out["attenuation_id"] = attenuation_id
	out["curve"] = curve
	out["unit_size"] = _unit_size_for(float(out["max_distance_m"]), curve, bool(out["is_2d"]))
	return out


## Stamps the authored attenuation envelope onto a 3D player. Returns false for
## an unknown event. A 2D-authored event disables distance attenuation (the
## caller should use an AudioStreamPlayer); see CURVE_ATTENUATION_MODEL for why
## a curved event uses inverse distance rather than a missing linear model.
func apply_attenuation(player: AudioStreamPlayer3D, event_name: String) -> bool:
	if player == null:
		return false
	var att: Dictionary = attenuation_for(event_name)
	if not bool(att["found"]):
		return false
	player.max_db = 0.0
	if bool(att["is_2d"]):
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.max_distance = DEFAULT_MAX_DISTANCE_M
		player.unit_size = 1.0
		return true
	player.max_distance = maxf(float(att["max_distance_m"]), 1.0)
	player.unit_size = float(att["unit_size"])
	var has_curve: bool = not (att["curve"] as Array).is_empty()
	player.attenuation_model = CURVE_ATTENUATION_MODEL if has_curve else FLAT_ATTENUATION_MODEL
	return true


## Energy model: the authored transmission loss is a multiplier on transmitted
## energy, so 1.0 yields 0 dB here (no *extra* authored loss). The concrete wall
## dB lives in [method apply_occlusion].
func occlusion_gain_db(transmission_loss: float) -> float:
	if transmission_loss >= 1.0:
		return 0.0
	return -20.0 * log(maxf(transmission_loss, OCCLUSION_LOSS_FLOOR)) / log(10.0)


## Low-pass corner for an occluded source: `20000 * loss^2` clamped to
## [400, 22000] Hz, so the authored 1.0 does not muffle.
func occlusion_cutoff_hz(transmission_loss: float) -> float:
	var cutoff: float = OCCLUSION_CUTOFF_UNITY_HZ * pow(maxf(transmission_loss, 0.0), 2.0)
	return clampf(cutoff, OCCLUSION_CUTOFF_MIN_HZ, OCCLUSION_CUTOFF_MAX_HZ)


## Applies occlusion to [param player] and returns the dB to add to its level.
## With [param blocked] false the filter is opened and 0 dB is returned. With
## blocked true the documented default wall loss (-12 dB) is scaled by the
## authored transmission multiplier.
func apply_occlusion(player: AudioStreamPlayer3D, blocked: bool, transmission_loss: float) -> float:
	if player == null:
		return 0.0
	if not blocked:
		player.attenuation_filter_db = 0.0
		player.attenuation_filter_cutoff_hz = OCCLUSION_CUTOFF_MAX_HZ
		return 0.0
	var loss: float = clampf(transmission_loss, 0.0, 1.0)
	var db: float = clampf(OCCLUSION_WALL_DB * loss, -60.0, 0.0)
	player.attenuation_filter_db = db
	player.attenuation_filter_cutoff_hz = occlusion_cutoff_hz(loss)
	return db


# =========================================================================
# Events, emitters, beds, music, VO
# =========================================================================


func has_event(event_name: String) -> bool:
	return _events.has(event_name)


## Sorted names of the authored 2D events (`max_radius_cm == 0`).
func events_2d() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for name: Variant in _events.keys():
		var event: Dictionary = _events[name]
		if float(event["max_radius_cm"]) <= 0.0:
			out.append(str(name))
	out.sort()
	return out


## Authored placed emitters for [param map_id], filtered by the documented dump
## basename mapping ([constant EMITTER_MAP_KEYS]) and sorted by actor.
## Returns `[{event, pos:Vector3, actor}]`; an unlisted map returns [].
func emitters_for_map(map_id: String) -> Array:
	var out: Array = []
	if not _loaded:
		return out
	var keys: PackedStringArray = _map_basenames(map_id)
	if keys.is_empty():
		return out
	for emitter: Dictionary in _emitters:
		if not keys.has(str(emitter["map"])):
			continue
		out.append({
			"event": str(emitter["event"]),
			"pos": emitter["pos"],
			"actor": str(emitter["actor"]),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["actor"]) < str(b["actor"]))
	return out


## The raw dump basenames present in `ambience.emitters[]`, sorted (probes).
func emitter_map_keys() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for emitter: Dictionary in _emitters:
		var key: String = str(emitter["map"])
		if not key.is_empty() and not out.has(key):
			out.append(key)
	out.sort()
	return out


## Back-compat projection of [method emitters_for_map] to `[{event, pos}]`.
func emitter_events(map_id: String) -> Array:
	var out: Array = []
	for emitter: Dictionary in emitters_for_map(map_id):
		out.append({"event": str(emitter["event"]), "pos": emitter["pos"]})
	return out


## Authored room bed event for [param map_id] (same basename mapping as the
## emitters). `""` when the map is unlisted or has no authored bed.
func room_bed_for(map_id: String) -> String:
	if not _loaded:
		return ""
	var keys: PackedStringArray = _map_basenames(map_id)
	if keys.is_empty():
		return ""
	var best: String = ""
	var best_volume: String = ""
	for bed: Dictionary in _room_beds:
		if not keys.has(str(bed["map"])):
			continue
		var event: String = str(bed["event"])
		if event.is_empty():
			continue
		var volume: String = str(bed["volume"])
		if best.is_empty() or volume < best_volume:
			best = event
			best_volume = volume
	return best


## Authored music event for [param kind] ([constant MUSIC_EVENTS]). Returns ""
## when the kind is unknown or the authored name is not in `music.play_events`.
func music_event(kind: String) -> String:
	if not _loaded:
		return ""
	var wanted: String = str(MUSIC_EVENTS.get(kind.to_lower().strip_edges(), ""))
	if wanted.is_empty():
		return ""
	return wanted if _music_play.has(wanted) else ""


## The authored aux bus for a reverb kind. With [param decay_s] >= 0 the nearest
## authored `reverb_assignment` decay of that kind wins; otherwise the
## documented default bus is returned when the data really contains it. "" when
## the data is absent (the caller keeps the bus dry).
func reverb_bus_for(kind: String, decay_s: float = -1.0) -> String:
	if not _loaded:
		return ""
	var k: String = kind.to_lower().strip_edges()
	if not REVERB_DEFAULTS.has(k):
		return ""
	if decay_s >= 0.0:
		var best_name: String = ""
		var best_delta: float = INF
		for row: Dictionary in _reverb_assignments:
			var name: String = str(row["aux_bus"])
			if name.is_empty() or not _is_named_reverb(name):
				continue
			if not _reverb_matches_kind(name, k):
				continue
			var delta: float = absf(float(row["decay_s"]) - decay_s)
			if delta < best_delta:
				best_delta = delta
				best_name = name
		if not best_name.is_empty():
			return best_name
		return ""
	var fallback: String = str(REVERB_DEFAULTS[k])
	return fallback if _is_named_reverb(fallback) else ""


# =========================================================================
# VO subtitles
# =========================================================================


## Functional subtitle label from the authored event name, e.g.
## `"Enforcer1 · ThiefSeen · VisionStim · Heavy (01)"`. No dialogue text exists
## anywhere in the extraction, so this is a label, never invented speech.
## `""` when the authored graph is absent (degraded getters stay neutral) or the
## event is not VO-shaped.
func vo_subtitle(event_name: String) -> String:
	if not _loaded:
		return ""
	var event: String = event_name.strip_edges()
	if event.is_empty():
		return ""
	var raw: Variant = _vo_lines.get(event)
	if raw is Dictionary:
		return _vo_format(raw)
	return _vo_label_from_name(event)


# =========================================================================
# Probe statistics
# =========================================================================


## Computed counts (from the parsed arrays, never from the declared block) plus
## load/build state. Safe on a missing file: zeros + `loaded=false`.
func stats() -> Dictionary:
	var aux: int = 0
	var named: int = 0
	for bus: Dictionary in _buses:
		if str(bus["kind"]) == "aux":
			aux += 1
		if not str(bus["name"]).is_empty():
			named += 1
	var with_bus: int = 0
	var with_attenuation: int = 0
	var two_d: int = 0
	for name: Variant in _events.keys():
		var event: Dictionary = _events[name]
		if int(event["bus"]) != 0:
			with_bus += 1
		if int(event["attenuation"]) != 0:
			with_attenuation += 1
		if float(event["max_radius_cm"]) <= 0.0:
			two_d += 1
	var built_buses: int = 0
	var built_effects: int = 0
	if not _report.is_empty() and bool(_report.get("built", false)):
		built_buses = (_report.get("buses", []) as Array).size()
		var c: Dictionary = _as_dict(_report.get("counts"))
		built_effects = int(c.get("bus_effects_added", 0))
	return {
		"schema": SCHEMA,
		"path": _path,
		"loaded": _loaded,
		"degraded": _reason,
		"generated_by": _generated_by,
		"buses": _buses.size(),
		"aux_buses": aux,
		"named_buses": named,
		"named_reverb_buses": _reverb_bus_names().size(),
		"fx": _fx.size(),
		"attenuations": _attenuations.size(),
		"events": _events.size(),
		"events_with_bus": with_bus,
		"events_with_attenuation": with_attenuation,
		"events_2d": two_d,
		"vo_lines": _vo_lines.size(),
		"vo_speakers": _vo_speakers.size(),
		"emitters": _emitters.size(),
		"emitter_maps": emitter_map_keys().size(),
		"room_beds": _room_beds.size(),
		"music_play_events": _music_play.size(),
		"music_stop_events": _music_stop.size(),
		"music_mute_events": _music_mute.size(),
		"music_unmute_events": _music_unmute.size(),
		"music_segments": _music_segments,
		"music_tracks": _music_tracks,
		"reverb_buses": _reverb_buses.size(),
		"reverb_assignments": _reverb_assignments.size(),
		"transmission_loss_rows": _transmission.size(),
		"warnings": _warnings.size(),
		"built_buses": built_buses,
		"built_effects": built_effects,
	}


## Sorted unique authored event radii in metres (3D events only), for probes.
func event_radii_m() -> PackedFloat32Array:
	var seen: Dictionary = {}
	var out: PackedFloat32Array = PackedFloat32Array()
	for name: Variant in _events.keys():
		var radius_m: float = float((_events[name] as Dictionary)["max_radius_cm"]) / 100.0
		if radius_m <= 0.0 or seen.has(radius_m):
			continue
		seen[radius_m] = true
		out.append(radius_m)
	out.sort()
	return out


# =========================================================================
# Parsing
# =========================================================================


func _reset() -> void:
	_loaded = false
	_reason = ""
	_generated_by = ""
	_sources = {}
	_declared_counts = {}
	_buses = []
	_bus_by_name = {}
	_fx = []
	_fx_by_id = {}
	_attenuations = {}
	_events = {}
	_transmission = []
	_reverb_assignments = []
	_reverb_buses = []
	_reverb_by_name = {}
	_music_play = PackedStringArray()
	_music_stop = PackedStringArray()
	_music_mute = PackedStringArray()
	_music_unmute = PackedStringArray()
	_music_segments = 0
	_music_tracks = 0
	_emitters = []
	_room_beds = []
	_vo_lines = {}
	_vo_speakers = {}
	_warnings = PackedStringArray()
	_built = false
	_report = {}


func _parse_buses(rows: Array) -> void:
	for raw: Variant in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var bus_id: int = _id(row.get("id"))
		if bus_id == 0:
			continue
		var name: String = _str(row.get("name")).strip_edges()
		var entry: Dictionary = {
			"id": bus_id,
			"kind": _str(row.get("kind")),
			"name": name,
			"parent": _id(row.get("parent")),
			"volume_db": _num(row.get("volume_db"), 0.0),
			"has_volume": row.get("volume_db") != null,
			"hpf_db": _num(row.get("hpf_db"), 0.0),
			"lpf_db": _num(row.get("lpf_db"), 0.0),
			"effects": _parse_fx_refs(_as_array(row.get("effects"))),
			"aux_sends": _parse_ids(_as_array(row.get("aux_sends"))),
			"reflections_aux": _id(row.get("reflections_aux")),
			"device": _id(row.get("device")),
		}
		_buses.append(entry)
		if not name.is_empty() and not _bus_by_name.has(name):
			_bus_by_name[name] = entry


func _parse_fx_refs(rows: Array) -> Array:
	var out: Array = []
	for raw: Variant in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		out.append({"fx": _id(row.get("fx")), "shareset": _truthy(row.get("shareset"))})
	return out


func _parse_ids(rows: Array) -> Array:
	var out: Array = []
	for raw: Variant in rows:
		var value: int = _id(raw)
		if value != 0:
			out.append(value)
	return out


func _parse_fx(rows: Array) -> void:
	for raw: Variant in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var entry: Dictionary = {
			"id": _id(row.get("id")),
			"kind": _str(row.get("kind")),
			"plugin": _str(row.get("plugin")),
			"params": _as_dict(row.get("params")).duplicate(true),
			"ir_source_id": _id(row.get("ir_source_id")),
			"ir_name": _str(row.get("ir_name")).strip_edges(),
		}
		_fx.append(entry)
		if int(entry["id"]) != 0 and not _fx_by_id.has(int(entry["id"])):
			_fx_by_id[int(entry["id"])] = entry


func _parse_attenuations(rows: Array) -> void:
	for raw: Variant in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var att_id: int = _id(row.get("id"))
		if att_id == 0 or _attenuations.has(att_id):
			continue
		var curve: Array = []
		for curve_raw: Variant in _as_array(row.get("curves")):
			if not (curve_raw is Dictionary):
				continue
			var curve_row: Dictionary = curve_raw
			if _str(curve_row.get("scaling")) != "dB":
				continue
			for point_raw: Variant in _as_array(curve_row.get("points")):
				if not (point_raw is Dictionary):
					continue
				var point: Dictionary = point_raw
				curve.append({
					"from_m": _num(point.get("from"), 0.0),
					"gain_db": _num(point.get("to"), 0.0),
				})
		curve.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["from_m"]) < float(b["from_m"]))
		_attenuations[att_id] = {
			"id": att_id,
			"curve": curve,
			"cone": _truthy(row.get("cone")),
			"height_spread": _truthy(row.get("height_spread")),
		}


func _parse_events(rows: Array) -> void:
	for raw: Variant in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var name: String = _str(row.get("name")).strip_edges()
		if name.is_empty() or _events.has(name):
			continue
		var duration: Dictionary = _as_dict(row.get("duration_s"))
		_events[name] = {
			"name": name,
			"id": _id(row.get("id")),
			"play": _truthy(row.get("play")),
			"bus": _id(row.get("bus")),
			"attenuation": _id(row.get("attenuation")),
			"max_radius_cm": _num(row.get("max_radius_cm"), 0.0),
			"is_infinite": _truthy(row.get("is_infinite")),
			"duration_min_s": _num(duration.get("min"), 0.0),
			"duration_max_s": _num(duration.get("max"), 0.0),
			"media_count": int(_num(row.get("media_count"), 0.0)),
		}


func _parse_transmission(rows: Array) -> void:
	for raw: Variant in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		_transmission.append({
			"material": _str(row.get("material")),
			"transmission_loss": _num(row.get("transmission_loss"), 1.0),
			"acoustic_texture": _str(row.get("acoustic_texture")),
		})


func _parse_reverb(assignments: Array, buses: Array) -> void:
	for raw: Variant in assignments:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		_reverb_assignments.append({
			"decay_s": _num(row.get("decay_s"), REVERB_DEFAULT_DECAY_S),
			"aux_bus": _str(row.get("aux_bus")).strip_edges(),
			"aux_bus_id": _id(row.get("aux_bus_id")),
		})
	for raw: Variant in buses:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var name: String = _str(row.get("name")).strip_edges()
		if name.is_empty():
			continue
		var entry: Dictionary = {
			"name": name,
			"id": _id(row.get("id")),
			"ir_name": _str(row.get("ir_name")).strip_edges(),
			"max_radius_cm": _num(row.get("max_radius_cm"), -1.0),
		}
		_reverb_buses.append(entry)
		if not _reverb_by_name.has(name):
			_reverb_by_name[name] = entry


func _parse_music(music: Dictionary) -> void:
	_music_play = _to_sorted_strings(_as_array(music.get("play_events")))
	_music_stop = _to_sorted_strings(_as_array(music.get("stop_events")))
	_music_mute = _to_sorted_strings(_as_array(music.get("mute_events")))
	_music_unmute = _to_sorted_strings(_as_array(music.get("unmute_events")))
	_music_segments = _as_array(music.get("segments")).size()
	_music_tracks = int(_num(music.get("track_count"), 0.0))


func _parse_ambience(ambience: Dictionary) -> void:
	for raw: Variant in _as_array(ambience.get("emitters")):
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var event: String = _str(row.get("event")).strip_edges()
		if event.is_empty():
			continue
		_emitters.append({
			"map": _str(row.get("map")).strip_edges(),
			"actor": _str(row.get("actor")).strip_edges(),
			"class": _str(row.get("class")).strip_edges(),
			"event": event,
			"pos": _vec3(row.get("pos")),
		})
	for raw: Variant in _as_array(ambience.get("room_beds")):
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		_room_beds.append({
			"map": _str(row.get("map")).strip_edges(),
			"volume": _str(row.get("volume")).strip_edges(),
			"event": _str(row.get("event")).strip_edges(),
			"aux_bus": _str(row.get("aux_bus")).strip_edges(),
		})


func _parse_vo(vo: Dictionary) -> void:
	_vo_speakers = _as_dict(vo.get("speakers")).duplicate(true)
	for raw: Variant in _as_array(vo.get("lines")):
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var event: String = _str(row.get("event")).strip_edges()
		if event.is_empty() or _vo_lines.has(event):
			continue
		_vo_lines[event] = {
			"event": event,
			"speaker": _str(row.get("speaker")).strip_edges(),
			"line": int(_num(row.get("line"), 0.0)),
			"verb": _str(row.get("verb")).strip_edges(),
			"state": _str(row.get("state")).strip_edges(),
			"severity": _str(row.get("severity")).strip_edges(),
			"variant": int(_num(row.get("variant"), 0.0)),
			"media_count": int(_num(row.get("media_count"), 0.0)),
		}


# =========================================================================
# Build helpers
# =========================================================================


func _empty_report() -> Dictionary:
	return {
		"built": false,
		"schema": SCHEMA,
		"degraded": _reason,
		"buses": [],
		"sends": {},
		"master": {},
		"master_effects": [],
		"counts": {"buses_created": 0, "buses_existing": 0, "bus_effects_added": 0, "reverb_buses": 0},
		"topology": "",
		"limitations": TOPOLOGY_LIMITATIONS.duplicate(),
	}


func _topology_text() -> String:
	return "flat bus tree: %s -> %s -> %s; reverb buses are inserts (AudioEffectReverb dry=1.0 + wet=<decay-mapped>) so each carries both the dry and the wet path; Master is terminal" % [
		"/".join(GAMEPLAY_BUSES), _default_exterior_bus(), MASTER_BUS]


func _send_limitation() -> String:
	return "Godot buses have one output and no per-send gain: the send is a re-parent of the source bus output and the amount scales the reverb bus's shared wet level"


func _reverb_bus_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for bus: Dictionary in _buses:
		var name: String = str(bus["name"])
		if name.begins_with(REVERB_PREFIX) and not out.has(name):
			out.append(name)
	for bus: Dictionary in _reverb_buses:
		var name: String = str(bus["name"])
		if name.begins_with(REVERB_PREFIX) and not out.has(name):
			out.append(name)
	out.sort()
	return out


func _bus_kind(bus_name: String) -> String:
	if _bus_by_name.has(bus_name):
		return str((_bus_by_name[bus_name] as Dictionary)["kind"])
	return "aux"


func _authored_bus_volume(bus_name: String) -> Variant:
	if not _bus_by_name.has(bus_name):
		return null
	var bus: Dictionary = _bus_by_name[bus_name]
	return float(bus["volume_db"]) if bool(bus["has_volume"]) else null


func _decay_for(bus_name: String) -> float:
	var best: float = -1.0
	for row: Dictionary in _reverb_assignments:
		if str(row["aux_bus"]) != bus_name:
			continue
		best = maxf(best, float(row["decay_s"]))
	return best if best >= 0.0 else REVERB_DEFAULT_DECAY_S


func _ir_for(bus_name: String) -> String:
	if _reverb_by_name.has(bus_name):
		var ir: String = str((_reverb_by_name[bus_name] as Dictionary)["ir_name"])
		if not ir.is_empty():
			return ir
	if _bus_by_name.has(bus_name):
		var bus: Dictionary = _bus_by_name[bus_name]
		for ref: Variant in (bus["effects"] as Array):
			if not (ref is Dictionary):
				continue
			var fx_id: int = int((ref as Dictionary)["fx"])
			if not _fx_by_id.has(fx_id):
				continue
			var fx: Dictionary = _fx_by_id[fx_id]
			if str(fx["plugin"]).find("Convolution") < 0:
				continue
			var name: String = str(fx["ir_name"])
			if not name.is_empty():
				return name
	return ""


func _max_radius_m_for(bus_name: String) -> float:
	if not _reverb_by_name.has(bus_name):
		return -1.0
	var cm: float = float((_reverb_by_name[bus_name] as Dictionary)["max_radius_cm"])
	return cm / 100.0 if cm > 0.0 else -1.0


func _distance_note(bus_name: String, radius_m: float) -> String:
	if radius_m < 0.0:
		return "no authored MaxAttenuationRadius for %s (informational only)" % bus_name
	return "authored MaxAttenuationRadius %.1f m; Godot has no per-bus distance attenuation (informational only)" % radius_m


func _find_reverb_effect(bus_idx: int) -> AudioEffectReverb:
	if bus_idx < 0:
		return null
	for i: int in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect: AudioEffect = AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectReverb:
			return effect as AudioEffectReverb
	return null


func _find_effect_of_class(bus_idx: int, wanted: String) -> AudioEffect:
	if bus_idx < 0:
		return null
	for i: int in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect: AudioEffect = AudioServer.get_bus_effect(bus_idx, i)
		if effect != null and effect.get_class() == wanted:
			return effect
	return null


func _master_effect_classes() -> Array:
	var out: Array = []
	var master_idx: int = AudioServer.get_bus_index(MASTER_BUS)
	if master_idx < 0:
		return out
	for i: int in range(AudioServer.get_bus_effect_count(master_idx)):
		var effect: AudioEffect = AudioServer.get_bus_effect(master_idx, i)
		if effect != null:
			out.append(effect.get_class())
	return out


func _build_master_chain() -> Dictionary:
	var idx: int = AudioServer.get_bus_index(MASTER_BUS)
	if idx < 0:
		return {"error": "no Master bus in AudioServer", "effects_added": 0}
	var added: int = 0

	var eq: AudioEffectEQ10 = _find_effect_of_class(idx, "AudioEffectEQ10") as AudioEffectEQ10
	var eq_created: bool = false
	if eq == null:
		eq = AudioEffectEQ10.new()
		AudioServer.add_bus_effect(idx, eq, 0)
		added += 1
		eq_created = true
	for band: int in range(eq.get_band_count()):
		eq.set_band_gain_db(band, 0.0)

	var limiter: AudioEffectHardLimiter = _find_effect_of_class(idx, "AudioEffectHardLimiter") as AudioEffectHardLimiter
	var limiter_created: bool = false
	if limiter == null:
		limiter = AudioEffectHardLimiter.new()
		AudioServer.add_bus_effect(idx, limiter, -1)
		added += 1
		limiter_created = true
	var ceiling: Dictionary = _authored_limiter_ceiling()
	var ceiling_db: float = float(ceiling.get("db", LIMITER_DEFAULT_CEILING_DB))
	limiter.ceiling_db = clampf(ceiling_db, LIMITER_CEILING_MIN_DB, 0.0)
	limiter.pre_gain_db = 0.0

	return {
		"index": idx,
		"effects_added": added,
		"chain": ["AudioEffectEQ10(flat)", "AudioEffectHardLimiter(ceiling=%.2f dB)" % limiter.ceiling_db],
		"limiter": {
			"created": limiter_created,
			"ceiling_db": limiter.ceiling_db,
			"source": str(ceiling.get("source", "default")),
			"authored_plugins": ceiling.get("plugins", []),
			"param_keys": ceiling.get("param_keys", []),
		},
		"eq": {
			"created": eq_created,
			"bands": eq.get_band_count(),
			"note": EQ_BANDS_NOTE,
		},
	}


## Looks for an authored ceiling in the first AkPeakLimiterFX/MasteringSuiteFX
## shareset that carries one. Reports which key/plugin was used, or "default".
func _authored_limiter_ceiling() -> Dictionary:
	var plugins: Array = []
	var keys: Array = []
	for fx: Dictionary in _fx:
		var plugin: String = str(fx["plugin"])
		if not MASTERING_PLUGINS.has(plugin):
			continue
		if not plugins.has(plugin):
			plugins.append(plugin)
		var params: Dictionary = fx["params"]
		var normalised: Dictionary = {}
		for param_key: Variant in params.keys():
			var key_text: String = str(param_key)
			if not keys.has(key_text):
				keys.append(key_text)
			normalised[_norm_key(key_text)] = params[param_key]
		for candidate: String in CEILING_KEYS:
			var norm_candidate: String = _norm_key(candidate)
			if not normalised.has(norm_candidate):
				continue
			var value: float = _num(normalised[norm_candidate], NAN)
			if is_nan(value) or value < -60.0 or value > 6.0:
				continue
			return {
				"found": true,
				"db": clampf(value, LIMITER_CEILING_MIN_DB, 0.0),
				"source": "authored:%s:%s" % [plugin, candidate],
				"plugins": plugins,
				"param_keys": keys.duplicate(),
			}
	return {
		"found": false,
		"db": LIMITER_DEFAULT_CEILING_DB,
		"source": "default -0.3 dB (no authored AkPeakLimiterFX/MasteringSuiteFX ceiling param)",
		"plugins": plugins,
		"param_keys": keys.duplicate(),
	}


func _build_default_sends() -> Dictionary:
	var sends: Dictionary = {}
	var target: String = _default_exterior_bus()
	for bus_name: String in GAMEPLAY_BUSES:
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx < 0:
			sends[bus_name] = {"status": "absent", "output": "", "amount_db": 0.0}
			continue
		if target.is_empty():
			sends[bus_name] = {"status": "no-reverb-bus", "output": str(AudioServer.get_bus_send(idx)), "amount_db": 0.0}
			continue
		var routed: Dictionary = _route_bus_detailed(bus_name, target)
		sends[bus_name] = {
			"status": "routed" if bool(routed["ok"]) else "skipped:%s" % str(routed["reason"]),
			"output": target if bool(routed["ok"]) else str(AudioServer.get_bus_send(idx)),
			"amount_db": 0.0,
			"limitation": _send_limitation(),
		}
	sends[MASTER_BUS] = {
		"status": "skipped:Master is the terminal bus (a send would cycle)",
		"output": "",
		"amount_db": 0.0,
		"limitation": _send_limitation(),
	}
	return sends


func _default_exterior_bus() -> String:
	var name: String = str(REVERB_DEFAULTS["exterior"])
	return name if _is_named_reverb(name) else ""


func _is_named_reverb(bus_name: String) -> bool:
	if bus_name.is_empty():
		return false
	if _bus_by_name.has(bus_name):
		return true
	return _reverb_by_name.has(bus_name)


func _base_wet_for(bus_name: String) -> float:
	var decay: float = _decay_for(bus_name)
	return float(reverb_params_for_decay(decay)["wet"])


func _reverb_matches_kind(bus_name: String, kind: String) -> bool:
	var low: String = bus_name.to_lower()
	if kind == "interior":
		return low.find(REVERB_INT_MARKER) >= 0
	if kind == "exterior":
		return low.find(REVERB_EXT_MARKER) >= 0
	return false


# =========================================================================
# Attenuation / map / VO helpers
# =========================================================================


## Godot 4.7 has no authored-curve attenuation model (inverse, inverse-square,
## logarithmic, disabled), and no single unit_size can reproduce a Wwise curve
## that has a plateau, a knee and a steep tail. The one free parameter of the
## inverse-distance model (`db(d) = -20*log10(d/unit)`, flat below unit) is
## therefore least-squares fitted to the authored curve over its audible part
## (distance > 0, 0 > gain_db >= -24 dB):
##     unit = 10^mean( log10(d_i) + gain_i / 20 )
## A two-point curve is reproduced exactly at its knee (the door's authored
## 0 -> -1 dB over 25 m gives unit 22.3 m, i.e. -0.99 dB at 25 m); a curve with
## a plateau and a -60 dB tail lands on the audible middle instead of vanishing
## half a metre from the source, which the endpoint rule did.
func _unit_size_for(max_distance_m: float, curve: Array, is_2d: bool) -> float:
	if is_2d or max_distance_m <= 0.0:
		return UNIT_SIZE_MIN
	if curve.is_empty():
		return clampf(max_distance_m * UNIT_SIZE_RADIUS_RATIO, UNIT_SIZE_MIN, UNIT_SIZE_MAX)
	var acc: float = 0.0
	var n: int = 0
	for point: Variant in curve:
		if not (point is Dictionary):
			continue
		var pd: Dictionary = point
		var d: float = float(pd["from_m"])
		var gain: float = float(pd["gain_db"])
		if d <= 0.0 or gain > 0.0 or gain < AUDIBLE_FIT_FLOOR_DB:
			continue
		acc += log(d) / log(10.0) + gain / 20.0
		n += 1
	if n == 0:
		return clampf(max_distance_m * UNIT_SIZE_RADIUS_RATIO, UNIT_SIZE_MIN, UNIT_SIZE_MAX)
	var unit: float = pow(10.0, acc / float(n))
	return clampf(unit, UNIT_SIZE_MIN, minf(max_distance_m, UNIT_SIZE_MAX))


func _map_basenames(map_id: String) -> PackedStringArray:
	var key: String = map_id.to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	var out: PackedStringArray = PackedStringArray()
	if EMITTER_MAP_KEYS.has(key):
		for name: Variant in (EMITTER_MAP_KEYS[key] as Array):
			out.append(str(name))
		return out
	# Also accept the dump basename itself (e.g. "Guildhall_Audio").
	for raw: Variant in EMITTER_MAP_KEYS.values():
		for name: Variant in (raw as Array):
			if str(name).to_lower() == key:
				out.append(str(name))
	return out


func _vo_format(record: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["speaker", "verb", "state", "severity"]:
		var value: String = str(record.get(key, "")).strip_edges()
		if not value.is_empty():
			parts.append(value)
	if parts.is_empty():
		return ""
	var label: String = " · ".join(parts)
	var variant: int = int(record.get("variant", 0))
	return "%s (%02d)" % [label, variant] if variant > 0 else label


## Functional fallback: author-shaped `Play_VO_<speaker>_<line>_<verb>_<state>_
## <severity>_<variant>`. Returns "" when the name is not shaped like a VO line.
func _vo_label_from_name(event_name: String) -> String:
	var low: String = event_name.to_lower()
	var prefix_at: int = low.find("vo_")
	if prefix_at < 0:
		return ""
	var rest: String = event_name.substr(prefix_at + 3)
	if rest.begins_with("_"):
		rest = rest.substr(1)
	var tokens: PackedStringArray = rest.split("_", false)
	if tokens.size() < 6:
		return ""
	var variant: String = tokens[tokens.size() - 1]
	if not variant.is_valid_int():
		return ""
	var severity: String = tokens[tokens.size() - 2]
	var state: String = tokens[tokens.size() - 3]
	var verb: String = tokens[tokens.size() - 4]
	var line: String = tokens[tokens.size() - 5]
	if not line.is_valid_int():
		return ""
	var speaker_parts: PackedStringArray = PackedStringArray()
	for i: int in range(tokens.size() - 5):
		speaker_parts.append(tokens[i])
	if speaker_parts.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray([speaker_parts[0]])
	if not verb.is_empty():
		parts.append(verb)
	if not state.is_empty():
		parts.append(state)
	if not severity.is_empty():
		parts.append(severity)
	return "%s (%s)" % [" · ".join(parts), variant]


# =========================================================================
# JSON value helpers (the document is untrusted: every getter tolerates null)
# =========================================================================


func _as_array(value: Variant) -> Array:
	return value if value is Array else []


func _as_dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return float(value)
	return fallback


func _id(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return int(round(float(value)))
	return 0


func _str(value: Variant) -> String:
	return "" if value == null else str(value)


func _truthy(value: Variant) -> bool:
	return value == true


func _norm_key(text: String) -> String:
	return text.to_lower().replace("_", "").replace(" ", "").replace("-", "")


func _to_sorted_strings(rows: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for raw: Variant in rows:
		var text: String = str(raw).strip_edges()
		if not text.is_empty() and not out.has(text):
			out.append(text)
	out.sort()
	return out


func _vec3(value: Variant) -> Vector3:
	if value is Array:
		var rows: Array = value
		if rows.size() >= 3:
			return Vector3(_num(rows[0], 0.0), _num(rows[1], 0.0), _num(rows[2], 0.0))
	elif value is Dictionary:
		var d: Dictionary = value
		return Vector3(_num(d.get("x"), 0.0), _num(d.get("y"), 0.0), _num(d.get("z"), 0.0))
	return Vector3.ZERO
