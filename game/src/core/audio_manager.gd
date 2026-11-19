extends Node
## Full audio runtime (PG-6): bus architecture + Wwise-event-driven cues.
##
## Buses: Master / Music / SFX / Ambience / UI / Dialogue (created once here,
## volumes driven by SaveSystem.apply_saved_settings via apply_volumes).
## Routing: gameplay SFX -> SFX (3D), UI -> UI (2D), ambience beds -> Ambience
## (2D looped), gramophone -> Music (2D looped, diegetic), VO -> Dialogue.
##
## Source clips come ONLY from the decoded Wwise OGGs via the events join in
## res://data/generated/audio_events.json (parsed at runtime; pins below name
## an AkAudioEvent + media DebugName and resolve through that join, never to
## invented paths). Anything unresolvable is skipped, never synthesized here:
## the only synthesized audio is the pre-existing ue/audio/*.wav fallback set
## for the original nine gameplay tags.
##
## AU coverage against docs/reference/clip_1795033698901 KEYFRAME_INDEX §4:
## - AU1 beds: rain (S01, -53..-49 dBFS, zero BGM) / den roomtone (S03,
##   -76..-73) / rooftop wind (S05/S09) / roomtone. Bed players are trimmed
##   relative to the mastered clip level (RAIN_DB etc.); absolute clip dBFS
##   from the keyframe table is preserved, not re-mastered.
## - AU4 UI: hover/select/confirm/back/open/close/ledger/paper + the S09
##   6 x 1.00 s countdown ticks (UI_MainMenu_Countdown) + modal chime.
## - AU3 footsteps: per-surface variation pools drawn from the
##   Play_FS_Player_{Walk,Run,Jog,Crouch} event media (wood/stone/carpet/
##   metal/wet/earth/glass), round-robin, 3D on the SFX bus.
## - AU5 gameplay SFX: original nine tags + bottle smash, car horn
##   double-honk (S13), ward activate/hit/end (S25), jaw-trap trigger (S26).
## - AU6 VO: guard alert/suspicious/search + fairy intro lines (real Wwise VO
##   cues mapped by function; the clip transcript is bandpass-resolved VO in
##   KEYFRAME §4, not per-line Wwise subtitles, so cues are functional, not
##   verbatim replicas of "Let the thieving begin.").
## Explicit absences honored: no BGM score anywhere (only the diegetic
## gramophone), digital silence on loading screens (beds stop on map change
## via play_bed_scene / stop_all_beds called from the mission flow).

const FOOTSTEP_SFX: AudioStream = preload("res://assets/ue/audio/footstep.wav")
const BLACKJACK_SFX: AudioStream = preload("res://assets/ue/audio/blackjack.wav")
const LOCKPICK_SFX: AudioStream = preload("res://assets/ue/audio/lockpick.wav")
const GRAPPLE_SFX: AudioStream = preload("res://assets/ue/audio/grapple.wav")
const SMOKE_SFX: AudioStream = preload("res://assets/ue/audio/smoke.wav")
const FAIRY_SFX: AudioStream = preload("res://assets/ue/audio/fairy.wav")
const ALERT_SFX: AudioStream = preload("res://assets/ue/audio/alert.wav")
const LOOT_SFX: AudioStream = preload("res://assets/ue/audio/loot.wav")
const DOOR_SFX: AudioStream = preload("res://assets/ue/audio/door.wav")

const MAX_VOICES: int = 16
const MAX_DISTANCE_M: float = 60.0
## Honest event->clip map produced by tools/convert_wwise.py. When the audit
## recovers no confirmed mapping, every tag keeps its synthesized fallback
## and has_real_clip() returns false.
const AUDIO_EVENTS_PATH: String = "res://data/generated/audio_events.json"

const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"
const BUS_AMBIENCE: String = "Ambience"
const BUS_UI: String = "UI"
const BUS_DIALOGUE: String = "Dialogue"

# Bed trims relative to mastered clip level (KEYFRAME §4 peak/RMS preserved).
const BED_RAIN_DB: float = -14.0
const BED_DEN_DB: float = -20.0
const BED_ROOMTONE_DB: float = -22.0
const BED_WIND_DB: float = -18.0
const BED_GUILDHALL_DB: float = -24.0
const BED_GRAMOPHONE_DB: float = -12.0
const UI_DB: float = -8.0
const COUNTDOWN_DB: float = -10.0
const VO_DB: float = -6.0

# (event, media DebugName) pins. Clips resolve through the events join only.
const EXTRA_PINS := {
	"bottle": ["Play_Glass_Window_Large_Smash_Shards_Break", "Glass_Window_Large_Shards_Tail_Seq_01.wav"],
	"car_horn": ["Play_Obj_Vehicle_Car_Horn_OneOff", "Obj_Car_Vehicle_Horn_Honk_Single_Seq_01.wav"],
	"ward_activate": ["Play_Obj_WardZone_Activate", "Obj_WardZone_Activate_01.wav"],
	"ward_hit": ["Play_Obj_WardZone_Blocker_OnHit", "Obj_WardZone_Blocker_OnHit_01.wav"],
	"ward_end": ["Play_Obj_WardZone_Ended", "Obj_WardZone_Ended_01.wav"],
	"jawtrap": ["Play_JawTrapTriggered", "Projectile_JawTrap_Trigger_TEMP_03.wav"],
	"paper": ["Play_Equipment_Map_Paper_Movement", "Obj_Page_Turn_Soft_Sequence_01.wav"],
	"ledger_open": ["Play_UI_Open_Ledger_Book_01", "UI_Radial_Open_TP_01.wav"],
	"ui_hover": ["Play_UI_MapAvailableHover", "UI_ThievesDen_Map_Hover_Available_02.wav"],
	"ui_click": ["Play_UI_Item_Loot_Generic_Acquire", "Obj_Loot_Minor_TEMP_02.wav"],
	"ui_confirm": ["Play_UI_ClickedJoinGameValidSound", "UI_Menu_Hover2.wav"],
	"ui_back": ["Play_UI_Radial_Close", "UI_Radial_Close_TP_01.wav"],
	"ui_open": ["Play_UI_Radial_Open", "UI_Radial_Open_TP_01.wav"],
	"wardrobe_open": ["Play_UI_Open_ChangeLoadout_CabinetWood_Open__01", "UI_Radial_Open_TP_01.wav"],
}
const COUNTDOWN_PIN := ["Play_UI_MainMenu_Countdown", "UI_MainMenu_Countdown_TP_01.wav"]
const BED_PINS := {
	"rain": ["Play_Amb_Weather_Rain_Impact_Puddle_Loop", "", -14.0],
	"den": ["Play_Amb_ThievesDen_Interior_Small_Room", "", -20.0],
	"roomtone": ["Play_Amb_Int_RoomTone_A", "", -22.0],
	"wind": ["Play_Amb_AbbotsfordPark_Exterior_Rooftops", "", -18.0],
	"guildhall": ["Play_Amb_Int_RoomTone_A", "", -24.0],
}
const GRAMOPHONE_PIN := ["Play_Mus_Source_WindowLife_Random_Playlist_All", "Mus_Source_Phonograph_FX_Piano_Sonatina_Loop_01.wav"]
const VO_PINS := {
	"guard_alert": ["Play_VO_Enforcer1_169_ThiefSeen_VisionStim_Heavy_01", "VO_Enforcer1_169_NoiseHeard_HighSeverityNoiseSearching_18.wav"],
	"guard_suspicious": ["Play_VO_Enforcer1_135_NoiseHeard_LowSeverityNoise_01", "VO_Enforcer1_135_NoiseHeard_LowSeverityNoise_01.wav"],
	"guard_search": ["Play_VO_Enforcer1_10_ThiefObserved_LostTargetToPatrol_02", "VO_Enforcer1_10_ThiefObserved_LostTargetToPatrol_02.wav"],
	"fairy_intro": ["Play_tristan_fairy_ftue_intro_01", "VO_FairyTristan_597_Tutorial_Intro_01.wav"],
}
# Gait event per movement gait; surfaces match substrings of media DebugNames.
const FOOTSTEP_GAIT_EVENTS := {
	"walk": "Play_FS_Player_Walk",
	"run": "Play_FS_Player_Run",
	"jog": "Play_FS_Player_Jog",
	"crouch": "Play_FS_Player_Crouch",
}
const FOOTSTEP_SURFACE_KEYS := {
	"wood": ["woodgeneric", "woodfloor"],
	"stone": ["stone", "concrete"],
	"carpet": ["carpet"],
	"metal": ["metalsheet", "metalgrate", "ladder"],
	"wet": ["wethardsurface", "puddle"],
	"earth": ["dirt", "grass", "foliage", "gravel"],
	"glass": ["brokenglass", "glass"],
}

var _sfx: Dictionary = {}
var _real_clips: Dictionary = {}
var _active_voices: int = 0
var _event_clips: Dictionary = {}
var _foot_pools: Dictionary = {}
var _foot_idx: Dictionary = {}
var _beds: Dictionary = {}
var _gramophone_player: AudioStreamPlayer = null
var _countdown_running: bool = false
var _named_clips: Dictionary = {}


func _ready() -> void:
	_ensure_buses()
	_sfx["footstep"] = FOOTSTEP_SFX
	_sfx["blackjack"] = BLACKJACK_SFX
	_sfx["lockpick"] = LOCKPICK_SFX
	_sfx["grapple"] = GRAPPLE_SFX
	_sfx["smoke"] = SMOKE_SFX
	_sfx["fairy"] = FAIRY_SFX
	_sfx["alert"] = ALERT_SFX
	_sfx["loot"] = LOOT_SFX
	_sfx["door"] = DOOR_SFX
	_load_events()
	_load_real_clips()
	_load_extra_pins()
	_build_footstep_pools()
	_pull_volumes_from_savesystem()
	NoiseBus.noise_emitted.connect(_on_noise_emitted)


func _ensure_buses() -> void:
	for bus_name: String in [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE, BUS_UI, BUS_DIALOGUE]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _set_bus_vol(bus_name: String, vol: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v: float = clampf(vol, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)


## Push volumes from SaveSystem settings (also called by SaveSystem so the
## audio side never depends on load order).
func apply_volumes(master_vol: float, music_vol: float, sfx_vol: float, ambience_vol: float, ui_vol: float, dialogue_vol: float) -> void:
	_ensure_buses()
	_set_bus_vol("Master", master_vol)
	_set_bus_vol(BUS_MUSIC, music_vol)
	_set_bus_vol(BUS_SFX, sfx_vol)
	_set_bus_vol(BUS_AMBIENCE, ambience_vol)
	_set_bus_vol(BUS_UI, ui_vol)
	_set_bus_vol(BUS_DIALOGUE, dialogue_vol)


func _pull_volumes_from_savesystem() -> void:
	var ss: Node = get_node_or_null("/root/SaveSystem")
	if ss == null or not ss.has_method("get_settings"):
		return
	var s: Dictionary = ss.call("get_settings") as Dictionary
	if s.is_empty():
		return
	apply_volumes(
		float(s.get("master_volume", 0.8)),
		float(s.get("music_volume", 0.8)),
		float(s.get("sfx_volume", 0.8)),
		float(s.get("ambience_volume", s.get("sfx_volume", 0.8))),
		float(s.get("ui_volume", s.get("sfx_volume", 0.8))),
		float(s.get("dialogue_volume", s.get("sfx_volume", 0.8)))
	)


## Returns true when [param tag] currently resolves to a real extracted clip
## instead of the synthesized fallback.
func has_real_clip(tag: String) -> bool:
	var normalized: String = tag.to_lower().strip_edges()
	var key: String = _resolve_tag(normalized)
	if not key.is_empty() and bool(_real_clips.get(key, false)):
		return true
	return bool(_real_clips.get(normalized, false))


func _load_events() -> void:
	_event_clips.clear()
	if not FileAccess.file_exists(AUDIO_EVENTS_PATH):
		return
	var f: FileAccess = FileAccess.open(AUDIO_EVENTS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	var events: Variant = (parsed as Dictionary).get("events", [])
	if not (events is Array):
		return
	for e: Variant in (events as Array):
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e
		var ev_name := str(ed.get("event", ""))
		if ev_name.is_empty():
			continue
		var clips: Array = []
		for m: Variant in (ed.get("media", []) as Array):
			if not (m is Dictionary):
				continue
			var md: Dictionary = m
			var clip := str(md.get("clip", ""))
			if clip.is_empty():
				continue
			clips.append({"debug_name": str(md.get("debug_name", "")), "clip": clip})
		if not clips.is_empty():
			_event_clips[ev_name] = clips


func _resolve_pin(pin: Array) -> String:
	if pin.size() < 2:
		return ""
	var clips: Variant = _event_clips.get(str(pin[0]), [])
	if not (clips is Array):
		return ""
	var want := str(pin[1]).to_lower().replace("\\", "/")
	for c: Variant in (clips as Array):
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		var dn := str(cd.get("debug_name", "")).to_lower().replace("\\", "/")
		# The join preserves Wwise source paths (e.g. Objects\WardZone\...)
		# while pins use bare filenames; accept either full or basename match.
		if want.is_empty() or dn == want or dn.rsplit("/", true, 1)[-1] == want.rsplit("/", true, 1)[-1]:
			var clip := str(cd.get("clip", ""))
			if not clip.is_empty() and ResourceLoader.exists(clip):
				return clip
	return ""


func _load_real_clips() -> void:
	if not FileAccess.file_exists(AUDIO_EVENTS_PATH):
		return
	var f: FileAccess = FileAccess.open(AUDIO_EVENTS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	var tags: Variant = (parsed as Dictionary).get("tags", {})
	if not (tags is Dictionary):
		return
	for tag: Variant in (tags as Dictionary).keys():
		var key := str(tag)
		if not _sfx.has(key):
			continue
		var entry: Variant = (tags as Dictionary)[tag]
		if not (entry is Dictionary):
			continue
		var clip_path := str((entry as Dictionary).get("clip", ""))
		if clip_path.is_empty() or not ResourceLoader.exists(clip_path):
			continue
		var stream: AudioStream = ResourceLoader.load(clip_path) as AudioStream
		if stream == null:
			continue
		_sfx[key] = stream
		_real_clips[key] = true


func _load_extra_pins() -> void:
	for key: Variant in EXTRA_PINS.keys():
		_register_named(str(key), _resolve_pin(EXTRA_PINS[key] as Array), true)
	# Countdown / gramophone / VO / beds are played through dedicated AU
	# paths (not the SFX-tag mirror), but they must still report real clips.
	_register_named("ui_countdown", _resolve_pin(COUNTDOWN_PIN), true)
	_register_named("gramophone", _resolve_pin(GRAMOPHONE_PIN), true)
	for vkey: Variant in VO_PINS.keys():
		var vp: Array = VO_PINS[vkey] as Array
		var vclip: String = _resolve_pin(vp)
		_register_named(str(vkey), vclip, false)
		_register_named(str(vkey) + "_vo", vclip, false)
	for bed: Variant in BED_PINS.keys():
		var bp: Array = BED_PINS[bed] as Array
		var bclip: String = _resolve_pin(bp)
		_register_named(str(bed), bclip, false)
		_register_named(str(bed) + "_bed", bclip, false)


## Registers a named real clip. When [param mirror_sfx] is true the stream
## also joins the 3D SFX-tag mirror (gameplay one-shots); otherwise it is a
## dedicated-path cue (UI/bed/VO/gramophone) that still reports a real clip.
func _register_named(tag: String, clip: String, mirror_sfx: bool) -> void:
	if clip.is_empty():
		return
	var stream: AudioStream = ResourceLoader.load(clip) as AudioStream
	if stream == null:
		return
	if mirror_sfx:
		_sfx[tag] = stream
	_named_clips[tag] = stream
	_real_clips[tag] = true


func _build_footstep_pools() -> void:
	_foot_pools.clear()
	_foot_idx.clear()
	for gait: Variant in FOOTSTEP_GAIT_EVENTS.keys():
		var ev_name := str(FOOTSTEP_GAIT_EVENTS[gait])
		var clips: Variant = _event_clips.get(ev_name, [])
		if not (clips is Array):
			continue
		for surface: Variant in FOOTSTEP_SURFACE_KEYS.keys():
			var keys: Array = FOOTSTEP_SURFACE_KEYS[surface] as Array
			var pool: Array = []
			for c: Variant in (clips as Array):
				if not (c is Dictionary):
					continue
				var dn := str((c as Dictionary).get("debug_name", "")).to_lower().replace("\\", "/")
				if dn.find("loot_bag") >= 0:
					continue
				for sk: Variant in keys:
					if dn.find(str(sk)) >= 0:
						pool.append(str((c as Dictionary).get("clip", "")))
						break
			if not pool.is_empty():
				var pool_key := str(gait) + "|" + str(surface)
				_foot_pools[pool_key] = pool
				_foot_idx[pool_key] = 0


func _footstep_clip(gait: String, surface: String) -> String:
	var g: String = gait.to_lower().strip_edges()
	if not FOOTSTEP_GAIT_EVENTS.has(g):
		g = "walk"
	var s: String = surface.to_lower().strip_edges()
	var pool_key := g + "|" + s
	if not _foot_pools.has(pool_key):
		pool_key = g + "|wood"
	if not _foot_pools.has(pool_key):
		return ""
	var pool: Array = _foot_pools[pool_key] as Array
	var idx: int = int(_foot_idx.get(pool_key, 0)) % maxi(1, pool.size())
	_foot_idx[pool_key] = idx + 1
	return str(pool[idx])


## AU3: per-surface footstep with variation pools (3D, SFX bus). Falls back
## to the resolved footstep tag clip when no pool matches.
func play_footstep(surface: String = "wood", gait: String = "walk", pos: Vector3 = Vector3.ZERO) -> bool:
	var clip: String = _footstep_clip(gait, surface)
	if not clip.is_empty() and ResourceLoader.exists(clip):
		var stream: AudioStream = ResourceLoader.load(clip) as AudioStream
		if stream != null:
			_play_stream_3d(stream, pos, 0.0, BUS_SFX)
			return true
	if _sfx.has("footstep"):
		_play_at("footstep", pos, 0.0)
		return true
	return false


## AU4: UI cue (2D, UI bus). Names: hover/click/confirm/back/open/close/
## ledger_open/paper/countdown/wardrobe_open.
## AU4: UI cue (2D, UI bus). Accepts either the bare cue name ("click",
## "ledger_open", "paper", "wardrobe_open", ...) or the "ui_"-prefixed
## tag form; unknown cues fall back to the click.
func play_ui(cue: String = "click") -> bool:
	var c := cue.to_lower().strip_edges()
	if c == "countdown" or c == "ui_countdown":
		return play_countdown_tick(0)
	var key := ""
	if _sfx.has(c):
		key = c
	elif _sfx.has("ui_" + c):
		key = "ui_" + c
	elif _sfx.has("ui_click"):
		key = "ui_click"
	else:
		return false
	_play_stream_2d(_sfx[key] as AudioStream, BUS_UI, UI_DB)
	return true


## AU4: single S09 countdown tick (2D, UI bus).
func play_countdown_tick(_n: int = 0) -> bool:
	var clip: String = _resolve_pin(COUNTDOWN_PIN)
	if clip.is_empty():
		return play_ui("click")
	var stream: AudioStream = ResourceLoader.load(clip) as AudioStream
	if stream == null:
		return false
	_play_stream_2d(stream, BUS_UI, COUNTDOWN_DB)
	return true


## AU4: S09 6 x 1.00 s countdown ticks. Fire-and-forget; safe across scene
## changes (ticks stay on the UI bus).
func start_countdown() -> void:
	if _countdown_running:
		return
	_countdown_running = true
	_countdown_async()


func _countdown_async() -> void:
	for i: int in range(6):
		play_countdown_tick(i)
		await get_tree().create_timer(1.0).timeout
	_countdown_running = false


func _bed_stream(ev_name: String, media_sub: String) -> AudioStream:
	var clips: Variant = _event_clips.get(ev_name, [])
	if not (clips is Array):
		return null
	var want := media_sub.to_lower()
	for c: Variant in (clips as Array):
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		if not want.is_empty() and str(cd.get("debug_name", "")).to_lower() != want:
			continue
		var clip := str(cd.get("clip", ""))
		if clip.is_empty() or not ResourceLoader.exists(clip):
			continue
		var stream: AudioStream = ResourceLoader.load(clip) as AudioStream
		if stream == null:
			continue
		var dup: Resource = stream.duplicate() as Resource
		var looped: AudioStream = stream
		if dup != null and dup is AudioStream:
			looped = dup as AudioStream
		if looped is AudioStreamOggVorbis:
			(looped as AudioStreamOggVorbis).loop = true
		return looped
	return null


## AU1/AU2: start a looped ambience bed (2D, Ambience bus).
## Beds: rain / den / roomtone / wind / guildhall. Volumes mirror the
## KEYFRAME §4 hierarchy (rain loudest outdoors, roomtone quietest).
func start_bed(bed: String) -> bool:
	var key := bed.to_lower().strip_edges()
	if not BED_PINS.has(key):
		return false
	if _beds.has(key):
		return true
	var pin: Array = BED_PINS[key] as Array
	var stream: AudioStream = _bed_stream(str(pin[0]), str(pin[1]))
	if stream == null:
		return false
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_AMBIENCE
	player.volume_db = float(pin[2])
	add_child(player)
	player.play()
	_beds[key] = player
	return true


func stop_bed(bed: String) -> void:
	var key := bed.to_lower().strip_edges()
	if not _beds.has(key):
		return
	var player: AudioStreamPlayer = _beds[key] as AudioStreamPlayer
	_beds.erase(key)
	if is_instance_valid(player):
		player.stop()
		player.queue_free()


func stop_all_beds() -> void:
	for key: Variant in _beds.keys():
		var player: AudioStreamPlayer = _beds[key] as AudioStreamPlayer
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_beds.clear()
	stop_gramophone()


## AU1 scene beds: thieves_den -> den roomtone; elsewhere rain + roomtone.
## Loading screens stay silent (call stop_all_beds there).
func play_bed_scene(map_id: String) -> void:
	stop_all_beds()
	var m := map_id.to_lower()
	if m.find("thieves_den") >= 0 or m.find("den") >= 0:
		start_bed("den")
		start_bed("roomtone")
	else:
		start_bed("rain")
		start_bed("roomtone")
		if m.find("guildhall") >= 0 or m.find("roof") >= 0 or m.find("mission") >= 0:
			start_bed("wind")


## AU2: diegetic gramophone record (S07, ONLY music in the clip) on Music bus.
func start_gramophone() -> bool:
	if is_instance_valid(_gramophone_player):
		return true
	var stream: AudioStream = _bed_stream(str(GRAMOPHONE_PIN[0]), str(GRAMOPHONE_PIN[1]))
	if stream == null:
		return false
	_gramophone_player = AudioStreamPlayer.new()
	_gramophone_player.stream = stream
	_gramophone_player.bus = BUS_MUSIC
	_gramophone_player.volume_db = BED_GRAMOPHONE_DB
	add_child(_gramophone_player)
	_gramophone_player.play()
	return true


func stop_gramophone() -> void:
	if not is_instance_valid(_gramophone_player):
		_gramophone_player = null
		return
	_gramophone_player.stop()
	_gramophone_player.queue_free()
	_gramophone_player = null


func is_gramophone_playing() -> bool:
	return is_instance_valid(_gramophone_player)


## Gramophone [F] toggle for the Den interactable.
func toggle_gramophone() -> bool:
	if is_gramophone_playing():
		stop_gramophone()
		return false
	play_ui("click")
	start_gramophone()
	return true


## AU6: voice line (Dialogue bus; 3D when a position is given).
## Cues: guard_alert / guard_suspicious / guard_search / fairy_intro.
func play_vo(cue: String, pos: Variant = null) -> bool:
	var key := cue.to_lower().strip_edges()
	if not VO_PINS.has(key):
		return false
	var pin: Array = VO_PINS[key] as Array
	var clips: Variant = _event_clips.get(str(pin[0]), [])
	var want := str(pin[1]).to_lower()
	var stream: AudioStream = null
	if clips is Array:
		for c: Variant in (clips as Array):
			if not (c is Dictionary):
				continue
			var cd: Dictionary = c
			if str(cd.get("debug_name", "")).to_lower() != want:
				continue
			var clip := str(cd.get("clip", ""))
			if clip.is_empty() or not ResourceLoader.exists(clip):
				continue
			stream = ResourceLoader.load(clip) as AudioStream
			break
	if stream == null:
		return false
	if pos is Vector3:
		_play_stream_3d(stream, pos, VO_DB, BUS_DIALOGUE)
	else:
		_play_stream_2d(stream, BUS_DIALOGUE, VO_DB)
	return true


## AU5: vintage car double-honk (S13: short blast, ~50 ms gap, long blast).
func play_car_horn(pos: Vector3 = Vector3.ZERO) -> bool:
	if not _sfx.has("car_horn"):
		return false
	_play_at("car_horn", pos, 0.0)
	var horn: AudioStream = _sfx["car_horn"] as AudioStream
	_horn_second_blast(horn, pos)
	return true


func _horn_second_blast(horn: AudioStream, pos: Vector3) -> void:
	await get_tree().create_timer(0.15).timeout
	if horn != null:
		_play_stream_3d(horn, pos, 0.0, BUS_SFX)


## Generic probe/event entry: plays the first joined clip of any Wwise event
## on the bus its name implies. Returns true when a real clip fired.
func fire_event(event_name: String, pos: Vector3 = Vector3.ZERO, use_3d: bool = false) -> bool:
	var ev := event_name.strip_edges()
	if ev.is_empty() or not _event_clips.has(ev):
		return false
	if ev == "Play_UI_MainMenu_Countdown":
		return play_countdown_tick(0)
	var bus := BUS_SFX
	if ev.begins_with("Play_UI_") or ev.begins_with("UI_"):
		bus = BUS_UI
	elif ev.begins_with("Play_Amb_"):
		bus = BUS_AMBIENCE
	elif ev.begins_with("Play_VO_") or ev.begins_with("VO_") or ev.find("tristan_fairy") >= 0 or ev.find("FairyTristan") >= 0:
		bus = BUS_DIALOGUE
	elif ev.begins_with("Play_Mus_"):
		bus = BUS_MUSIC
	var clips: Array = _event_clips[ev] as Array
	var stream: AudioStream = null
	for c: Variant in clips:
		if not (c is Dictionary):
			continue
		var clip := str((c as Dictionary).get("clip", ""))
		if clip.is_empty() or not ResourceLoader.exists(clip):
			continue
		stream = ResourceLoader.load(clip) as AudioStream
		if stream != null:
			break
	if stream == null:
		return false
	if bus == BUS_UI or bus == BUS_AMBIENCE or bus == BUS_MUSIC:
		_play_stream_2d(stream, bus, -10.0)
	elif use_3d:
		_play_stream_3d(stream, pos, 0.0, bus)
	else:
		_play_stream_2d(stream, bus, -10.0)
	return true


func _resolve_tag(tag: String) -> String:
	var normalized: String = tag.to_lower().strip_edges()
	if _sfx.has(normalized):
		return normalized
	match normalized:
		"takedown", "slithersap", "ko", "melee":
			return "blackjack"
		"wire", "rope":
			return "grapple"
		"moth", "chime", "vision", "disguise":
			return "fairy"
		"spotted", "alert", "whistle", "hunt", "guard_alert", "pickpocket_spotted":
			return "alert"
		"pickup", "coin", "steal", "clue":
			return "loot"
		"gate":
			return "door"
		"generic", "step", "walk":
			return "footstep"
		"bottle", "smash", "shatter":
			return "bottle"
		"lockpick_jam":
			return "lockpick"
	return ""


func play_sfx(tag: String, pos: Vector3 = Vector3.ZERO) -> void:
	var key: String = _resolve_tag(tag)
	if key.is_empty():
		return
	_play_at(key, pos, 0.0)


func _on_noise_emitted(origin: Vector3, loudness_meters: float, _source: Node, tag: String) -> void:
	var key: String = _resolve_tag(tag)
	if key.is_empty():
		return
	var volume_db: float = clampf((loudness_meters - 6.0) * 1.5, -10.0, 4.0)
	_play_at(key, origin, volume_db)


func _play_at(key: String, pos: Vector3, volume_db: float) -> void:
	if not _sfx.has(key):
		return
	var stream: AudioStream = _sfx[key] as AudioStream
	if stream == null:
		return
	_play_stream_3d(stream, pos, volume_db, BUS_SFX)


func _play_stream_3d(stream: AudioStream, pos: Vector3, volume_db: float, bus: String) -> void:
	if _active_voices >= MAX_VOICES or stream == null:
		return
	if AudioServer.get_bus_index(bus) == -1:
		bus = "Master"
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.position = pos
	player.volume_db = volume_db
	player.bus = bus
	player.max_distance = MAX_DISTANCE_M
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player)
	_active_voices += 1
	player.finished.connect(_on_player_finished.bind(player))
	player.play()


func _play_stream_2d(stream: AudioStream, bus: String, volume_db: float) -> void:
	if _active_voices >= MAX_VOICES or stream == null:
		return
	if AudioServer.get_bus_index(bus) == -1:
		bus = "Master"
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	add_child(player)
	_active_voices += 1
	player.finished.connect(_on_player_finished.bind(player))
	player.play()


func _on_player_finished(player: Node) -> void:
	_active_voices = maxi(0, _active_voices - 1)
	player.queue_free()
