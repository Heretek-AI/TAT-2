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
##   relative to the measured RMS of the decoded clip (ffmpeg astats), so the
##   BUS level lands on the absolute KEYFRAME dBFS target (see BED_TRIM_DB);
##   absolute clip dBFS from the keyframe table is preserved, not re-mastered.
##   Scene beds: S01 menu rain only; S03 Den room tone only; S12+ Guildhall
##   rain + quiet safe-room tone; loading screens stop all beds. The wind bed
##   is opt-in via start_bed("wind") for the S05/S09 rooftop sky view.
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
## W5D: duplicate-cue guard. Several fan-outs (button pressed + menu confirm,
## NoiseBus stimulus + explicit cue, cast + impact) fire the same cue twice in
## the same frame. A 120 ms cue|position window drops the repeat. Footsteps are
## cadence-gated by the player controller already and are exempt.
const CUE_DEDUPE_MS: int = 120
## W5D: sustained cues. These must replace, never stack, and keep a stop handle
## (alarm reset, smoke cloud end). They are looped on a private duplicate of the
## shared Ogg so one-shot players of the same clip keep their finished signal.
const LOOP_CUES: Array[String] = ["alarm_loop", "smoke_cloud", "lightbeam_hum"]
## Honest event->clip map produced by tools/convert_wwise.py. When the audit
## recovers no confirmed mapping, every tag keeps its synthesized fallback
## and has_real_clip() returns false.
const AUDIO_EVENTS_PATH: String = "res://data/generated/audio_events.json"

const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"
const BUS_AMBIENCE: String = "Ambience"
const BUS_UI: String = "UI"
const BUS_DIALOGUE: String = "Dialogue"

# AU1 bed levels. `BED_CLIP_RMS_DB` is the whole-loop RMS of the resolved
# decoded Ogg measured with ffmpeg astats (48 kHz stereo) on 2026-11-19; the
# player trim is `BED_TARGET_DBFS - BED_CLIP_RMS_DB`, so the Ambience bus
# carries the absolute KEYFRAME §4 level and the clip is never re-mastered.
# Targets:
#   rain      -51.0 (S01 -53..-49, zero BGM)
#   den       -74.5 (S03 -76.3..-73.1)
#   roomtone    -61.5 (interior safe room / foyer bed)
#   wind      -39.4 (S05 PONDER swell RMS)
#   guildhall -64.0 (safe-room bed layered under the S12 rain)
#   wind_prep -58.0 (S09 prep bed, -64..-52 RMS)
const BED_CLIP_RMS_DB: Dictionary = {
	"rain": -45.7,
	"den": -34.1,
	"roomtone": -32.8,
	"wind": -31.9,
	"guildhall": -32.8,
	"wind_prep": -31.9,
}
const BED_TARGET_DBFS: Dictionary = {
	"rain": -51.0,
	"den": -74.5,
	"roomtone": -61.5,
	"wind": -39.4,
	"guildhall": -64.0,
	"wind_prep": -58.0,
}
const BED_TRIM_DB: Dictionary = {
	"rain": -5.3,
	"den": -40.4,
	"roomtone": -28.7,
	"wind": -7.5,
	"guildhall": -31.2,
	"wind_prep": -26.1,
}
# S07 diegetic gramophone: clip RMS -23.3 -> about -41.5 RMS with the trim
# below (doc -40..-45 RMS, pk -24.9). Only Music-bus source in the game;
# started on activation.
const GRAMOPHONE_TRIM_DB: float = -18.2
const UI_DB: float = -8.0
const COUNTDOWN_DB: float = -10.0
const VO_DB: float = -6.0
## S27: opening the pause menu ducks gameplay ambience by 19 dB (doc:
## -53 -> -72.4 dBFS by 03:42.6); resuming restores the saved bus level.
const PAUSE_DUCK_DB: float = -19.0

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
	"ui_hover": ["Play_UI_Menu_Hover", "UI_Radial_Hover_TP_02.wav"],
	"ui_click": ["Play_UI_Menu_Press", "UI_Menu_Press.wav"],
	"ui_confirm": ["Play_UI_ClickedJoinGameValidSound", "UI_Menu_Hover2.wav"],
	"ui_back": ["Play_UI_Radial_Close", "UI_Radial_Close_TP_01.wav"],
	"ui_open": ["Play_UI_Radial_Open", "UI_Radial_Open_TP_01.wav"],
	"ui_tab": ["Play_UI_Radial_Tab", "UI_Radial_Tab_TP_01.wav"],
	"ui_error": ["Play_UI_Invalid", "UI_Invalid_V1_01.wav"],
	"ui_purchase": ["Play_UI_Upgrade_Button_Press", "UI_Purchase_Upgrade.wav"],
	"wardrobe_open": ["Play_UI_Open_ChangeLoadout_CabinetWood_Open__01", "UI_ChangeEquipment_Cabinet_Open_01.wav"],
}
# AU5 contextual one-shots that are not NoiseBus mirrors (cast/attach/crank/
# impact families). Resolved through the events join exactly like EXTRA_PINS.
const CUE_PINS: Dictionary = {
	"smoke_cast": ["Eqp_SmokeBomb_Cast", "Eqp_SmokeGrenade_Throw_01.wav"],
	"smoke_cloud": ["Eqp_SmokeBomb_Alive_Loop", "Eqp_KnockoutGas_Alive_Loop_Sml_02.wav"],
	"zipwire_launch": ["Play_Ability_Hotwire_Cast", "S_BL_Skill_Hotwire_Launch_02.wav"],
	"zipwire_attach": ["Play_Ability_Hotwire_Attach", "Ability_Climbing_Rope_Attach_V2_02.wav"],
	"zipwire_crank": ["Play_Ability_Hotwire_Crank_Loop", "Eqp_Zipwire_Crank_Single_01.wav"],
	"zipwire_detach": ["Play_Ability_Hotwire_Detach", "Ability_Vrilwire_Detatch_03.wav"],
	"pickpocket_success": ["Play_PickpocketingTool_Success", "PickpocketingTool_Success_02.wav"],
	"pickpocket_fail": ["Play_PickpocketingTool_Failure", "PickpocketingTool_Failure_01.wav"],
	"takedown_impact": ["Play_Ability_TakeDown_BodyFall", "Ability_Takedown_Bodyfall_01.wav"],
	"lightbeam_trip": ["Play_Obj_LightBeam_Triggering", "Obj_LightBeam_Triggering_02.wav"],
	"lightbeam_hum": ["Play_Obj_LightBeam_Beam_Loop", "Obj_LightBeam_Beam_Loop_04.wav"],
	"alarm_loop": ["Play_Prop_Alarm_Guard_Alarm_Lp", "Obj_SecurityCamera_MagicEye_Alarm_02.wav"],
	"door_latch": ["Play_Prop_Int_Door_Wood_Open", "Props_Int_Door_Open_Wood_V1_02.wav"],
	"lock_unlock": ["Play_Obj_PickableLock_Unlock", "Prop_LockPick_OpenV2_01.wav"],
}
const COUNTDOWN_PIN := ["Play_UI_MainMenu_Countdown", "UI_MainMenu_Countdown_TP_01.wav"]
const BED_PINS := {
	"rain": ["Play_Amb_Weather_Rain_Impact_Puddle_Loop", ""],
	"den": ["Play_Amb_ThievesDen_Interior_Small_Room", ""],
	"roomtone": ["Play_Amb_Int_RoomTone_A", ""],
	"wind": ["Play_Amb_AbbotsfordPark_Exterior_Rooftops", ""],
	"guildhall": ["Play_Amb_Int_RoomTone_A", ""],
	# S09 Mission Preparation: softer rooftop wind under the 6 s countdown
	# (-64..-52 RMS), distinct from the S05 PONDER swell above.
	"wind_prep": ["Play_Amb_AbbotsfordPark_Exterior_Rooftops", ""],
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
## U1: live voice list for stealing. The old code silently dropped new
## voices past MAX_VOICES (fights lost alert/VO cues with no signal). Now
## the oldest voice is stolen, the steal is counted, and UE-path-identified
## warnings fire (5 s throttle) so drops are visible, never silent.
var _voice_players: Array[Node] = []
var _voice_steals: int = 0
var _last_steal_warn_msec: int = -100000
var _event_clips: Dictionary = {}
var _foot_pools: Dictionary = {}
var _foot_idx: Dictionary = {}
var _beds: Dictionary = {}
## W5D: beds currently fading out, key -> {player, tween}. A re-entry for the
## same bed (play_bed_scene / start_bed) cancels the fade and frees the old
## player immediately, so two players never overlap on one bed key.
var _fading_beds: Dictionary = {}
## W5D: cue|position -> Time.get_ticks_msec() of the last accepted play.
var _cue_last_msec: Dictionary = {}
## W5D: live sustained-cue handles (LOOP_CUES), keyed cue|position ->
## {player, token}. A TTL duration bumps the token so a replaced handle is
## never stopped by the previous handle's timer.
var _loop_players: Dictionary = {}
var _loop_generation: int = 0
var _gramophone_player: AudioStreamPlayer = null
## U3: scene-safe countdown. The old fire-and-forget loop held
## _countdown_running = true across scene changes forever (blocking every
## later start_countdown) and ticked into dead scenes. Now the loop captures
## the tree + scene + a generation token and bails (resetting the flag) when
## the scene changes or a newer countdown starts.
var _countdown_token: int = 0
var _countdown_running: bool = false
## Fade tweens created by start_bed/stop_bed/stop_all_beds. They hold a
## reference to the player node until they finish, so teardown must kill them
## before freeing players or the last ambience beds survive shutdown.
var _bed_tweens: Array[Tween] = []
## Set by cleanup_on_exit(); every late async caller (countdown timer, second
## car-horn blast, deferred VO) must not create a new playback after teardown.
var _shutdown: bool = false
var _named_clips: Dictionary = {}
## U4: one looped duplicate per unique bed/gramophone clip (see _bed_stream).
var _bed_loop_cache: Dictionary = {}
## Bus linear levels are cached so the S27 pause duck can be applied on top of
## the saved slider value without losing it.
var _bus_linear: Dictionary = {}
var _pause_duck_db: float = 0.0
var _pause_was_active: bool = false


func _ready() -> void:
	# S27 pause duck must keep evaluating while the scene tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_was_active = get_tree() != null and get_tree().paused
	_pause_duck_db = PAUSE_DUCK_DB if _pause_was_active else 0.0
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
	# S01: the Startscreen owns the rain bed and no music score. The menu
	# script is outside this file's ownership, so the bed autostarts when the
	# main-menu scene is the current scene (mission loads replace it via
	# play_bed_scene).
	call_deferred("_autostart_scene_bed")


func _exit_tree() -> void:
	cleanup_on_exit()


## Release every live playback, stream reference and cached clip before the
## manager leaves the tree. Without this, active Ogg playbacks and their
## OggPacketSequence resources survive shutdown (leaked resources/RIDs).
func cleanup_on_exit() -> void:
	# Invalidate every deferred/async producer before stopping players. The
	# countdown coroutine and the 0.15 s second car-horn blast would otherwise
	# spawn a fresh playback in the two frames between teardown and quit.
	_shutdown = true
	_countdown_token += 1
	_countdown_running = false
	for tw: Tween in _bed_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_bed_tweens.clear()
	# Free, not queue_free: at process shutdown the deferred free queue is not
	# guaranteed to run, and that is exactly where the Ogg playback refs leaked
	# (countdown tick, briefing VO, rain/roomtone beds).
	for child: Node in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.call("stop")
			child.set("stream", null)
			child.free()
	for player: Node in _voice_players:
		if is_instance_valid(player):
			player.call("stop")
			player.set("stream", null)
			player.free()
	_voice_players.clear()
	_active_voices = 0
	if _gramophone_player != null and is_instance_valid(_gramophone_player):
		_gramophone_player.stop()
		_gramophone_player.stream = null
		_gramophone_player.free()
	_gramophone_player = null
	for bed: Variant in _beds.values():
		if bed is Node and is_instance_valid(bed as Node):
			(bed as Node).call("stop")
			(bed as Node).set("stream", null)
			(bed as Node).free()
	_beds.clear()
	_fading_beds.clear()
	_loop_players.clear()
	_cue_last_msec.clear()
	_bed_loop_cache.clear()
	_event_clips.clear()
	_named_clips.clear()
	_real_clips.clear()
	_sfx.clear()
	_foot_pools.clear()
	_foot_idx.clear()


func _ensure_buses() -> void:
	for bus_name: String in [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE, BUS_UI, BUS_DIALOGUE]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _set_bus_vol(bus_name: String, vol: float) -> void:
	_bus_linear[bus_name] = clampf(vol, 0.0, 1.0)
	_apply_bus_level(bus_name)


## Applies a cached slider level plus the transient pause duck. Called by
## apply_volumes and by the pause transition; never clobbers the saved level.
func _apply_bus_level(bus_name: String) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v: float = float(_bus_linear.get(bus_name, 1.0))
	var db: float = linear_to_db(maxf(v, 0.001))
	if bus_name == BUS_AMBIENCE:
		db += _pause_duck_db
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, v <= 0.001)


## S27: pause menu ambience duck (AU4-05). The tree's paused flag is the
## authority, so HUD pause handling stays outside this file's ownership.
func _process(_delta: float) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var paused: bool = tree.paused
	if paused == _pause_was_active:
		return
	_pause_was_active = paused
	_pause_duck_db = PAUSE_DUCK_DB if paused else 0.0
	_apply_bus_level(BUS_AMBIENCE)


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
	for cue: Variant in CUE_PINS.keys():
		_register_named(str(cue), _resolve_pin(CUE_PINS[cue] as Array), false)
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


## Resolves the surface actually under the player for the current map: the
## Den is timber; the Guildhall route is wet cobblestone outside and marble
## stone inside; Elway Manor is stone outside and parquet timber inside. The
## indoor test is a ceiling probe, so no gameplay state is touched.
func _scene_surface(preferred: String) -> String:
	var gs: Node = get_node_or_null("/root/GameState")
	var map_id: String = str(gs.get("active_map_id")) if gs != null else ""
	if map_id == "thieves_den":
		return "wood"
	if map_id == "guildhall":
		return "stone" if _is_indoor() else "wet"
	if map_id == "old_manor":
		return "wood" if _is_indoor() else "stone"
	var p: String = preferred.to_lower().strip_edges()
	return p if FOOTSTEP_SURFACE_KEYS.has(p) else "stone"


func _is_indoor() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	var player: Node3D = tree.get_first_node_in_group("player") as Node3D
	var vp: Viewport = get_viewport()
	if player == null or vp == null:
		return false
	var world: World3D = vp.find_world_3d()
	if world == null:
		return false
	var from: Vector3 = player.global_position + Vector3.UP * 1.2
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 10.0)
	var excluded: Array[RID] = []
	if player is CollisionObject3D:
		var body: CollisionObject3D = player as CollisionObject3D
		excluded.append_array(body.get_collision_exceptions())
		excluded.append(body.get_rid())
	q.exclude = excluded
	return not world.direct_space_state.intersect_ray(q).is_empty()


## Round-robin pool draw. Crouch/Jog families lack some surfaces in the Wwise
## event (e.g. no crouch wood/stone), so the search falls back across gaits
## before ever returning a single fixed clip.
func _footstep_clip(gait: String, surface: String) -> String:
	var g: String = gait.to_lower().strip_edges()
	if not FOOTSTEP_GAIT_EVENTS.has(g):
		g = "walk"
	var s: String = _scene_surface(surface)
	var gaits: Array[String] = [g, "walk", "jog", "run", "crouch"]
	for gg: String in gaits:
		var pool_key: String = gg + "|" + s
		if _foot_pools.has(pool_key):
			return _next_foot_clip(pool_key)
	for gg: String in gaits:
		var wood_key: String = gg + "|wood"
		if _foot_pools.has(wood_key):
			return _next_foot_clip(wood_key)
	for pool_key_v: Variant in _foot_pools.keys():
		return _next_foot_clip(str(pool_key_v))
	return ""


func _next_foot_clip(pool_key: String) -> String:
	var pool: Array = _foot_pools[pool_key] as Array
	if pool.is_empty():
		return ""
	var idx: int = int(_foot_idx.get(pool_key, 0)) % pool.size()
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


## AU4: UI cue (2D, UI bus). Accepts either the bare cue name ("click",
## "ledger_open", ...) or the "ui_"-prefixed tag form; unknown cues fall
## back to the click. Cue names: hover / click / confirm / back (also
## cancel, close) / open / tab / error / purchase / ledger_open / paper /
## wardrobe_open / countdown.
## AU4: recursively wires hover ticks onto every button under [param root].
## UIs call this once after building (and again after lazy sub-panels), so the
## S04/S08 metallic hover ticks fire without duplicating per-control plumbing.
func wire_hover_sfx(root: Node) -> void:
	if root == null:
		return
	for child: Node in root.get_children():
		if child is BaseButton and not child.has_meta("pg6_hover"):
			child.set_meta("pg6_hover", true)
			(child as BaseButton).mouse_entered.connect(_on_ui_hover)
		wire_hover_sfx(child)


func _on_ui_hover() -> void:
	play_ui("hover")


func play_ui(cue: String = "click") -> bool:
	var c := cue.to_lower().strip_edges()
	if c == "countdown" or c == "ui_countdown":
		return play_countdown_tick(0)
	var alias: String = c
	if c == "hover" or c == "mouseover":
		alias = "ui_hover"
	elif c == "click" or c == "press" or c == "select":
		alias = "ui_click"
	elif c == "confirm" or c == "accept":
		alias = "ui_confirm"
	elif c == "back" or c == "cancel" or c == "close":
		alias = "ui_back"
	elif c == "open":
		alias = "ui_open"
	elif c == "tab" or c == "tab_switch":
		alias = "ui_tab"
	elif c == "error" or c == "invalid" or c == "fail":
		alias = "ui_error"
	elif c == "purchase" or c == "buy":
		alias = "ui_purchase"
	elif c == "ledger":
		alias = "ledger_open"
	elif c == "wardrobe":
		alias = "wardrobe_open"
	elif c == "page" or c == "page_turn":
		alias = "paper"
	var key := ""
	if _sfx.has(alias):
		key = alias
	elif _sfx.has("ui_" + alias):
		key = "ui_" + alias
	elif _sfx.has("ui_click"):
		key = "ui_click"
	else:
		return false
	# W5D: duplicate UI fan-out (button pressed + menu confirm in one frame).
	if _cue_duplicate(key, null):
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


## Cancels the in-flight tick loop (prep UNREADY / BACK). Bumping the token
## makes the suspended coroutine stop at its next 1 s boundary.
func stop_countdown() -> void:
	_countdown_token += 1
	_countdown_running = false


func _countdown_async() -> void:
	_countdown_token += 1
	var token: int = _countdown_token
	var tree: SceneTree = get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	for i: int in range(6):
		play_countdown_tick(i)
		if tree == null:
			break
		await tree.create_timer(1.0).timeout
		if _countdown_token != token or get_tree() == null or get_tree().current_scene != scene:
			break
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
		# U4: Godot 4 has no AudioStreamLoop (Godot 3 API), and the bed
		# clips are shared with one-shot events (audio_events.json reuses
		# the same .ogg across events), so flipping loop on the shared
		# resource would strand one-shot players (finished never fires).
		# One looped duplicate per unique clip, cached — not one per
		# start_bed call — so map changes stop re-duplicating the OGG.
		var cached: AudioStream = _bed_loop_cache.get(clip) as AudioStream
		if cached != null:
			return cached
		var looped: AudioStream = stream.duplicate() as AudioStream
		if looped == null:
			continue
		if looped is AudioStreamOggVorbis:
			(looped as AudioStreamOggVorbis).loop = true
		_bed_loop_cache[clip] = looped
		return looped
	return null


## AU1/AU2: start a looped ambience bed (2D, Ambience bus).
## Beds: rain / den / roomtone / wind / guildhall. The player trim lands the
## bed on BED_TARGET_DBFS (KEYFRAME §4); fade_s crossfades in.
## Registers a bed fade tween so cleanup_on_exit() can kill it before freeing
## the player it references. The tween removes itself when it finishes.
func _track_bed_tween(tw: Tween) -> Tween:
	_bed_tweens.append(tw)
	tw.finished.connect(func() -> void:
		_bed_tweens.erase(tw)
	)
	return tw


## W5D: cancel a bed already fading out on [param key]. Called by start_bed
## before creating the replacement player: without this the old player kept
## sounding (and stayed a child) for the whole 0.2-0.35 s fade.
func _cancel_fading_bed(key: String) -> void:
	var entry_v: Variant = _fading_beds.get(key)
	if not (entry_v is Dictionary):
		return
	_fading_beds.erase(key)
	var entry: Dictionary = entry_v
	var tw: Tween = entry.get("tween") as Tween
	if tw != null and tw.is_valid():
		tw.kill()
	var player: Node = entry.get("player") as Node
	if player != null and is_instance_valid(player):
		player.call("stop")
		player.set("stream", null)
		# free(), not queue_free(): the deferred queue would leave the old
		# player in the tree for a frame, which is the overlap being fixed.
		player.free()


## W5D: shared fade-out path. The fade is registered per bed key so a same-key
## re-entry can cancel it (see _cancel_fading_bed) instead of overlapping.
func _fade_out_bed(key: String, player: AudioStreamPlayer, fade_s: float) -> void:
	if not is_instance_valid(player):
		return
	if fade_s <= 0.0:
		player.stop()
		player.stream = null
		player.queue_free()
		return
	var tw: Tween = _track_bed_tween(create_tween())
	_fading_beds[key] = {"player": player, "tween": tw}
	tw.tween_property(player, "volume_db", -60.0, fade_s)
	tw.tween_callback(func() -> void:
		_fading_beds.erase(key)
		if is_instance_valid(player):
			player.stop()
			player.stream = null
			player.queue_free()
	)


func start_bed(bed: String, fade_s: float = 0.6) -> bool:
	if _shutdown:
		return false
	var key := bed.to_lower().strip_edges()
	if not BED_PINS.has(key):
		return false
	# W5D: never let a fading player for this key overlap its replacement.
	_cancel_fading_bed(key)
	if _beds.has(key):
		return true
	var pin: Array = BED_PINS[key] as Array
	var stream: AudioStream = _bed_stream(str(pin[0]), str(pin[1]))
	if stream == null:
		return false
	var target: float = float(BED_TRIM_DB.get(key, 0.0))
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_AMBIENCE
	player.volume_db = target if fade_s <= 0.0 else target - 20.0
	add_child(player)
	player.play()
	_beds[key] = player
	if fade_s > 0.0:
		var tw: Tween = _track_bed_tween(create_tween())
		tw.tween_property(player, "volume_db", target, fade_s)
	return true


func stop_bed(bed: String, fade_s: float = 0.25) -> void:
	var key := bed.to_lower().strip_edges()
	if not _beds.has(key):
		return
	var player: AudioStreamPlayer = _beds[key] as AudioStreamPlayer
	_beds.erase(key)
	if not is_instance_valid(player):
		return
	_fade_out_bed(key, player, fade_s)


func stop_all_beds(fade_s: float = 0.0) -> void:
	for key: Variant in _beds.keys():
		var player: AudioStreamPlayer = _beds[key] as AudioStreamPlayer
		if not is_instance_valid(player):
			continue
		_fade_out_bed(str(key), player, fade_s)
	_beds.clear()
	stop_gramophone()


## AU1 scene beds against KEYFRAME §4. The Den is room tone only (no BGM);
## Guildhall layers the S12 rain under a quiet safe-room bed; the Manor is
## exterior rain; loading screens silence everything (LoadingScreen calls
## stop_all_beds). The wind bed is opt-in for the S05/S09 rooftop view.
func play_bed_scene(map_id: String) -> void:
	stop_all_beds(0.2)
	var m := map_id.to_lower()
	if m.find("thieves_den") >= 0 or m == "den":
		start_bed("den")
	elif m.find("guildhall") >= 0:
		start_bed("rain")
		start_bed("guildhall")
	elif m.find("old_manor") >= 0:
		start_bed("rain")
	else:
		start_bed("rain")


func _autostart_scene_bed() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or _beds.has("rain"):
		return
	var scene: Node = tree.current_scene
	if scene == null:
		return
	if scene.scene_file_path.ends_with("main_menu.tscn"):
		start_bed("rain", 1.2)


## Effective bed level on the bus for QA/reporting: target dBFS, applied trim
## and which beds are currently live.
func bed_target_dbfs(bed: String) -> float:
	return float(BED_TARGET_DBFS.get(bed.to_lower().strip_edges(), 0.0))


func active_bed_levels() -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in _beds.keys():
		var player: AudioStreamPlayer = _beds[key] as AudioStreamPlayer
		if not is_instance_valid(player):
			continue
		out[str(key)] = {
			"target_dbfs": bed_target_dbfs(str(key)),
			"volume_db": player.volume_db,
			"bus": player.bus,
		}
	return out


## AU2: diegetic gramophone record (S07, ONLY music in the clip) on Music bus.
func start_gramophone() -> bool:
	if _shutdown:
		return false
	if is_instance_valid(_gramophone_player):
		return true
	var stream: AudioStream = _bed_stream(str(GRAMOPHONE_PIN[0]), str(GRAMOPHONE_PIN[1]))
	if stream == null:
		return false
	_gramophone_player = AudioStreamPlayer.new()
	_gramophone_player.stream = stream
	_gramophone_player.bus = BUS_MUSIC
	_gramophone_player.volume_db = GRAMOPHONE_TRIM_DB
	add_child(_gramophone_player)
	_gramophone_player.play()
	return true


func stop_gramophone() -> void:
	if not is_instance_valid(_gramophone_player):
		_gramophone_player = null
		return
	_gramophone_player.stop()
	_gramophone_player.stream = null
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
	# U3: the 0.15 s replay is skipped when the scene changed under it, so a
	# stale timer never honks at a dead position in the new scene.
	var tree: SceneTree = get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	await get_tree().create_timer(0.15).timeout
	if horn != null and get_tree() != null and get_tree().current_scene == scene:
		_play_stream_3d(horn, pos, 0.0, BUS_SFX)


## U2: calibrated play trims per bus. The old fire_event path played
## everything at -10.0 dB, bypassing BED_TRIM_DB / UI_DB / VO_DB.
## Ambience events resolve a bed trim by event-name substring (rain / den /
## room / wind / guildhall); anything else uses a documented uncalibrated
## fallback const instead of a magic literal.
const AMB_FALLBACK_DB: float = -10.0
const MUSIC_FALLBACK_DB: float = -10.0


func _ambience_trim_db(ev: String) -> float:
	var low: String = ev.to_lower()
	for bed_key: Variant in BED_TRIM_DB.keys():
		if low.find(str(bed_key)) >= 0:
			return float(BED_TRIM_DB[bed_key])
	return AMB_FALLBACK_DB


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
	# U2: per-bus calibrated trims (UI_DB / VO_DB / BED_TRIM_DB) instead of
	# the old flat -10.0 dB. Music keeps a documented uncalibrated fallback.
	if bus == BUS_UI:
		_play_stream_2d(stream, bus, UI_DB)
	elif bus == BUS_DIALOGUE:
		_play_stream_2d(stream, bus, VO_DB)
	elif bus == BUS_AMBIENCE:
		_play_stream_2d(stream, bus, _ambience_trim_db(ev))
	elif bus == BUS_MUSIC:
		_play_stream_2d(stream, bus, MUSIC_FALLBACK_DB)
	elif use_3d:
		_play_stream_3d(stream, pos, 0.0, bus)
	else:
		_play_stream_2d(stream, BUS_SFX, 0.0)
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
		# P2 (gameplay lane P2-8): door/swinging-door relock emits tag "lock";
		# mirror it on the lockpick cue so the audio path matches the
		# NoiseBus path guards already hear.
		"lock", "lockpick_jam":
			return "lockpick"
	return ""


func play_sfx(tag: String, pos: Vector3 = Vector3.ZERO) -> void:
	var key: String = _resolve_tag(tag)
	if key.is_empty():
		return
	_play_at(key, pos, 0.0)


func _on_noise_emitted(origin: Vector3, loudness_meters: float, _source: Node, tag: String) -> void:
	# Footsteps already fire with a per-surface variation pool from the player
	# controller; mirroring the tag here would double every step with the
	# single fallback clip and defeat the variation requirement.
	if tag == "footstep":
		return
	var key: String = _resolve_tag(tag)
	if key.is_empty():
		return
	var volume_db: float = clampf((loudness_meters - 6.0) * 1.5, -10.0, 4.0)
	_play_at(key, origin, volume_db)


## AU5 contextual cue resolved from CUE_PINS (3D on the SFX bus when a
## position is supplied, otherwise 2D). Returns false when the pin did not
## resolve through the events join, or when the same cue|position already
## fired inside CUE_DEDUPE_MS. Sustained cues (LOOP_CUES) replace the previous
## handle instead of stacking and can be stopped by name/position.
func play_cue(cue: String, pos: Variant = null, duration_s: float = 0.0) -> bool:
	var key: String = cue.to_lower().strip_edges()
	if not _named_clips.has(key):
		return false
	var stream: AudioStream = _named_clips[key] as AudioStream
	if stream == null:
		return false
	if LOOP_CUES.has(key):
		_replace_loop_cue(key, stream, pos, duration_s)
		return true
	if _cue_duplicate(key, pos):
		return false
	if pos is Vector3:
		_play_stream_3d(stream, pos, 0.0, BUS_SFX)
	else:
		_play_stream_2d(stream, BUS_SFX, 0.0)
	return true


## W5D: stable cue key component. 2D cues share one bucket; 3D cues are
## distinguished at centimetre granularity (two guards at the same spot should
## not double a cue, two different emitters should).
func _position_key(pos: Variant) -> String:
	if pos is Vector3:
		var v: Vector3 = pos
		return "%.2f,%.2f,%.2f" % [v.x, v.y, v.z]
	return "2d"


## W5D: true when [param cue] at [param pos] already fired inside the window.
## Records the accepted time otherwise. The map is pruned opportunistically so
## position-keyed gameplay cues cannot grow it without bound.
func _cue_duplicate(cue: String, pos: Variant) -> bool:
	var now: int = Time.get_ticks_msec()
	if _cue_last_msec.size() > 256:
		for stale: Variant in _cue_last_msec.keys():
			if now - int(_cue_last_msec[stale]) > CUE_DEDUPE_MS * 8:
				_cue_last_msec.erase(stale)
	var key: String = cue + "|" + _position_key(pos)
	if _cue_last_msec.has(key) and now - int(_cue_last_msec[key]) < CUE_DEDUPE_MS:
		return true
	_cue_last_msec[key] = now
	return false


## W5D: a looped duplicate of a shared Ogg (cached like the beds) so the
## one-shot players of the same clip still emit finished.
func _loop_variant(stream: AudioStream) -> AudioStream:
	if not (stream is AudioStreamOggVorbis):
		return stream
	var path: String = stream.resource_path
	var cache_key: String = path if not path.is_empty() else "loop:%d" % stream.get_instance_id()
	var cached: AudioStream = _bed_loop_cache.get(cache_key) as AudioStream
	if cached != null:
		return cached
	var looped: AudioStream = stream.duplicate() as AudioStream
	if looped is AudioStreamOggVorbis:
		(looped as AudioStreamOggVorbis).loop = true
	_bed_loop_cache[cache_key] = looped
	return looped


## W5D: start (or restart) the single sustained-cue player for cue|position.
## [param duration_s] > 0 auto-stops this handle after that many seconds (smoke
## cloud lifetime); 0 keeps it until stop_cue / the owner's teardown.
func _replace_loop_cue(cue: String, stream: AudioStream, pos: Variant, duration_s: float = 0.0) -> void:
	if _shutdown:
		return
	var loop_stream: AudioStream = _loop_variant(stream)
	if loop_stream == null:
		return
	var key: String = cue + "|" + _position_key(pos)
	_stop_loop_key(key)
	var player: Node
	if pos is Vector3:
		var p3: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p3.stream = loop_stream
		p3.position = pos
		p3.bus = BUS_SFX
		p3.max_distance = MAX_DISTANCE_M
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player = p3
	else:
		var p2: AudioStreamPlayer = AudioStreamPlayer.new()
		p2.stream = loop_stream
		p2.bus = BUS_SFX
		player = p2
	add_child(player)
	player.call("play")
	_loop_generation += 1
	var token: int = _loop_generation
	_loop_players[key] = {"player": player, "token": token}
	if duration_s > 0.0 and is_inside_tree():
		var timer: SceneTreeTimer = get_tree().create_timer(duration_s)
		timer.timeout.connect(func() -> void:
			var held: Variant = _loop_players.get(key)
			if held is Dictionary and int((held as Dictionary).get("token", -1)) == token:
				_stop_loop_key(key)
		)


func _stop_loop_key(key: String) -> void:
	if not _loop_players.has(key):
		return
	var held: Variant = _loop_players[key]
	_loop_players.erase(key)
	var player: Node = null
	if held is Dictionary:
		player = (held as Dictionary).get("player") as Node
	elif held is Node:
		player = held as Node
	if player != null and is_instance_valid(player):
		player.call("stop")
		player.set("stream", null)
		player.queue_free()


## W5D: stop sustained cue handles. With [param pos] only that position stops
## (one alarm eye's loop); without it every live handle for the cue stops.
func stop_cue(cue: String, pos: Variant = null) -> void:
	var key: String = cue.to_lower().strip_edges()
	if _loop_players.is_empty():
		return
	if pos is Vector3:
		_stop_loop_key(key + "|" + _position_key(pos))
		return
	for held: Variant in _loop_players.keys():
		if str(held).begins_with(key + "|"):
			_stop_loop_key(str(held))


## W5D: sorted handle keys for QA/tests (cue|position).
func active_loop_cues() -> Array[String]:
	var out: Array[String] = []
	for held: Variant in _loop_players.keys():
		out.append(str(held))
	out.sort()
	return out


func _play_at(key: String, pos: Vector3, volume_db: float) -> void:
	if not _sfx.has(key):
		return
	# W5D: one-shot tag fan-out guard; footsteps keep their own cadence.
	if key != "footstep" and _cue_duplicate(key, pos):
		return
	var stream: AudioStream = _sfx[key] as AudioStream
	if stream == null:
		return
	_play_stream_3d(stream, pos, volume_db, BUS_SFX)


func _play_stream_3d(stream: AudioStream, pos: Vector3, volume_db: float, bus: String) -> void:
	if stream == null or _shutdown:
		return
	_steal_voice_if_full("3d")
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
	_voice_players.append(player)
	_active_voices += 1
	player.finished.connect(_on_player_finished.bind(player))
	player.play()


func _play_stream_2d(stream: AudioStream, bus: String, volume_db: float) -> void:
	if stream == null or _shutdown:
		return
	_steal_voice_if_full("2d")
	if AudioServer.get_bus_index(bus) == -1:
		bus = "Master"
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	add_child(player)
	_voice_players.append(player)
	_active_voices += 1
	player.finished.connect(_on_player_finished.bind(player))
	player.play()


func _on_player_finished(player: Node) -> void:
	_active_voices = maxi(0, _active_voices - 1)
	_voice_players.erase(player)
	player.queue_free()


## U1: voice stealing. At cap the oldest live voice is freed for the new
## one (fights keep their alert/VO cues); the steal is counted and warned
## with the bus path at most once per 5 s. finished-signal cleanup keeps
## the list exact, so a double-free can never happen (is_instance_valid
## guard + erase before free).
func _steal_voice_if_full(kind: String) -> void:
	_prune_dead_voices()
	if _active_voices < MAX_VOICES:
		return
	_voice_steals += 1
	var now: int = Time.get_ticks_msec()
	if now - _last_steal_warn_msec > 5000:
		_last_steal_warn_msec = now
		push_warning("[audio_manager] MAX_VOICES (", MAX_VOICES, ") reached on ", kind, " playback; stealing oldest voice (steals=", _voice_steals, ")")
	for old: Node in _voice_players:
		if is_instance_valid(old):
			_voice_players.erase(old)
			_active_voices = maxi(0, _active_voices - 1)
			old.queue_free()
			return


## Drops finished/freed players the finished signal never saw (scene churn).
func _prune_dead_voices() -> void:
	for i: int in range(_voice_players.size() - 1, -1, -1):
		if not is_instance_valid(_voice_players[i]):
			_voice_players.remove_at(i)
	_active_voices = mini(_active_voices, _voice_players.size())
