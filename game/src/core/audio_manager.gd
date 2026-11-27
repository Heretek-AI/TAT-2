extends Node
## Full audio runtime (PG-6): authored bus architecture + Wwise-event cues.
##
## Buses: Master / Music / SFX / Ambience / UI / Dialogue (created once here,
## volumes driven by SaveSystem.apply_saved_settings via apply_volumes) plus,
## when the generated Wwise control plane is present, the 16 authored VERB_*
## aux/reverb buses with real AudioEffect instances and the authored mastering
## limiter/EQ on Master (T03, RE-M-01).
## Routing: gameplay SFX -> SFX (3D), UI -> UI (2D), ambience -> Ambience
## (authored placed emitters in 3D, room bed 2D), gramophone/music -> Music,
## VO -> Dialogue.
##
## Source clips come ONLY from the decoded Wwise OGGs via the events join in
## res://data/generated/audio_events.json (parsed at runtime; pins below name
## an AkAudioEvent + media DebugName and resolve through that join, never to
## invented paths). Anything unresolvable is skipped, never synthesized here:
## the only synthesized audio is the pre-existing ue/audio/*.wav fallback set
## for the original nine gameplay tags.
##
## AU coverage against docs/reference/clip_1795033698901 KEYFRAME_INDEX §4:
## - AU1 beds: authored placed ambience (90 emitters, 136 room beds in the
##   extraction) when data/generated/audio_wwise.json exists; otherwise the
##   legacy rain/den/roomtone/wind bed keys, whose trims are calibrated to the
##   measured clip RMS (BED_TRIM_DB).
## - AU4 UI: hover/select/confirm/back/open/close/ledger/paper + the S09
##   6 x 1.00 s countdown ticks (UI_MainMenu_Countdown) + modal chime.
## - AU3 footsteps: per-surface variation pools drawn from the
##   Play_FS_Player_{Walk,Run,Jog,Crouch} event media (wood/stone/carpet/
##   metal/wet/earth/glass), round-robin, 3D on the SFX bus, authored radius.
## - AU5 gameplay SFX: original nine tags + bottle smash, car horn
##   double-honk (S13), ward activate/hit/end (S25), jaw-trap trigger (S26).
## - AU6 VO: guard alert/suspicious/search + fairy intro lines plus the W11-A
##   VO director over the 645 authored VO lines; the extraction carries no
##   dialogue text (localisation keys are GUIDs), so subtitles are functional
##   descriptors emitted through `subtitle_shown`, never presented as
##   transcribed speech.
## Music (T03): the shipped build hard-wires Play_Mus_MainTitleScreen in
## MainMenu_C, so the menu starts it (music.title_music.enabled in
## data/expansion/audio_mix.json). Gameplay music is state-driven and starts
## only when an owning system calls start_music()/play_music_event(): no map
## plays un-authored music. The 2026-11-24 capture's continuous tonal bed is
## capture-borne (it is audible during the engine boot splash and through the
## loading screen where every bed is stopped), which is why the old "no BGM
## anywhere" claim was removed.
## Mix states (T03): the pause duck covers Ambience+SFX+Music (AU4-05),
## begin_loading_silence() reaches digital zero for AU1-03, and indoor/outdoor
## switches the authored reverb send (8.0 s exterior / 0.45 s interior decay).
## The per-room *bed* swap is BLOCKED-ON T09: TATSpatialAudioVolume brush
## geometry is not in the extraction.


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
## T03: the authored duck is a *gameplay* duck. It used to attenuate the
## Ambience bus only, so a bed or one-shot living on SFX/Music was untouched.
## UI stays up (pause clicks are the thing the player just pressed) and
## Dialogue keeps an already-speaking line audible.
const PAUSE_DUCK_BUSES: Array[String] = [BUS_AMBIENCE, BUS_SFX, BUS_MUSIC]
## T03 authored control plane. `tools/parse_wwise.py` writes
## data/generated/audio_wwise.json (buses, fx sharesets, attenuations,
## transmission loss, music, placed emitters, VO lines). It is loaded
## dynamically and never required: a fresh clone without the generated file
## keeps the pre-T03 behaviour and reports the degraded path in mix_state().
const WWISE_SCRIPT_PATH: String = "res://src/core/audio_wwise.gd"
const MIX_CONFIG_PATH: String = "res://data/expansion/audio_mix.json"
## B3a authored switch/state/RTPC control plane (tools/parse_audio_control.py).
## Loaded dynamically like the Wwise helper: a fresh clone without the generated
## file keeps the token footstep pools and the pre-B3a behaviour, and
## mix_state().control says why.
const CONTROL_SCRIPT_PATH: String = "res://src/core/audio_control.gd"
## W11-A: the authored VO director (pure selector over AudioWwise.vo_index()).
const VO_DIRECTOR_PATH: String = "res://src/core/vo_director.gd"
## W11-C: the authored surface resolver owns surface -> audio token and the
## FS_Layers value, so the footstep path cannot drift from the loudness path.
const SurfaceResolver: GDScript = preload("res://src/stealth/surface_resolver.gd")
const CONTROL_DETECTION_RTPC: String = "Character_Enemy_Detection_Level_RTPC"
## The RTPC's authored curve is per node; the music container is the node whose
## curve the port applies (the detection level is a music mix control in the
## shipped bank — 3 of its 24 node rows sit on music containers).
const CONTROL_MUSIC_NODE_TYPE: String = "MusicRandomSequenceContainer"
const CONTROL_STATE_ENV: String = "Weather_isExterior"
const CONTROL_STATE_MODAL: String = "Modal_State"
const CONTROL_SWITCH_GAIT: String = "Character_Movement_Mode"
const CONTROL_SWITCH_MATERIAL: String = "FS_Material"
const CONTROL_SWITCH_LAYER: String = "FS_Layers"
const CONTROL_SWITCH_LOCAL: String = "Character_IsLocallyControlled"
## W11-D: the five authored mix parameters this port has real callers for
## (stamina, crouch, fall velocity, rain, disguise). See authored_rtpc_state().
const AUTHORED_RTPCS: Array[String] = [
	"Character_Stamina_RTPC",
	"Character_FS_isCrouching",
	"Character_Fall_Velocity_Z",
	"Weather_Rain_Intensity",
	"Character_DisguiseIntegrity",
]
## Port surface key -> authored FS_Material value. Derived by measuring which
## bank package carries the family's media (tools/parse_audio_control.py +
## audio_events.json), never invented; the full evidence table is in
## docs/reports/w10-p3-audio.md §5. "wood" is WoodFloor because the bank puts
## the wood floor family there (WoodBeam is the sibling package that carries
## the beam samples).
const CONTROL_SURFACE_VALUES := {
	"wood": "WoodFloor",
	"stone": "Stone",
	"carpet": "Carpet",
	"metal": "MetalGrate",
	"wet": "ShallowWater",
	"earth": "Dirt",
	"glass": "Glass",
}
## Guards are polled for their normalized detection (guard_ai.get_alert_state
## .suspicion) at this interval; the RTPC is the max across live guards.
const DETECTION_POLL_MS: int = 250
## Concurrent authored ambience emitters. 90 are placed across the shipped
## audio sublevels; the four maps the port loads carry 34/27/17/12, and a
## cap keeps a 34-emitter room from eating the 16-voice one-shot budget.
const EMITTER_CAP: int = 24
## Occlusion probe: a hit closer than this to either endpoint is the floor
## under the player or the emitter's own wall, not a wall between them.
const OCCLUSION_MIN_HIT_M: float = 0.4
const OCCLUSION_WALL_DB_FALLBACK: float = -12.0
const OCCLUSION_MIN_CUTOFF_HZ: float = 400.0

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
## T03 authored music events by kind. Literal authored names (extracted event
## assets), used when the generated control plane is absent; audio_wwise.json
## is the authority when present. Gameplay kinds are NOT started anywhere by
## this file — an owning system must ask for them, so no map plays un-authored
## music (see game/data/expansion/audio_mix.json music.mission_music).
const MUSIC_FALLBACK_PINS := {
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
## Music-bus trim for an authored music event. Not measured: the recording's
## startscreen bed is capture-borne (see game/data/expansion/audio_mix.json
## music.title_music.conflict), so there is no reference level to calibrate
## against. Documented TAT-2 choice, overridable per event from the overlay.
const MUSIC_TRIM_DB: float = -10.0
## W11-B: fade used when the event is not bound to an authored
## MusicSwitchContainer (no authored transition to read).
const MUSIC_FADE_FALLBACK_S: float = 0.6

## Gait event per movement gait; surfaces match substrings of media DebugNames.
## T03 (RE-M-09): every authored media family present in the player FS events is
## reached now. The previous seven keys missed Tile/Marble, the whole
## ShallowWater family (85 media), Mud, MetalPipe/MetalVehicle and
## WoodBeam/WoodObject, so those clips were decoded and never played. The
## authored surface -> token mapping still lives in surface_resolver.gd (T10),
## so "Tile" reaches the stone pool exactly as its authored loudness row says.
const FOOTSTEP_GAIT_EVENTS := {
	"walk": "Play_FS_Player_Walk",
	"run": "Play_FS_Player_Run",
	"jog": "Play_FS_Player_Jog",
	"crouch": "Play_FS_Player_Crouch",
}
const FOOTSTEP_SURFACE_KEYS := {
	"wood": ["woodgeneric", "woodfloor", "woodbeam", "woodobject", "plank"],
	"stone": ["stone", "concrete", "tile", "marble", "granite", "brick", "cobble", "terrazzo"],
	"carpet": ["carpet", "rug"],
	"metal": ["metalsheet", "metalgrate", "metalpipe", "metalvehicle", "metalthick", "ladder"],
	"wet": ["wethardsurface", "puddle", "shallowwater", "groundwet"],
	"earth": ["dirt", "grass", "foliage", "gravel", "mud", "ivy"],
	"glass": ["brokenglass", "glasshorizontal", "glass"],
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
## W11-C: authored FS_Layers recordings per `gait|surface|layer`, and their
## round-robin cursors. Built lazily from the authored package media.
var _layer_pools: Dictionary = {}
var _layer_idx: Dictionary = {}
## B3a: pool key -> media ids parallel to _foot_pools[key], so the authored
## switch selection can filter the token pool by MediaId.
var _foot_media: Dictionary = {}
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

## T03 authored-control-plane state.
## `_wwise` is the AudioWwise helper (res://src/core/audio_wwise.gd) or null.
var _wwise: RefCounted = null
## B3a: the AudioControl helper (res://src/core/audio_control.gd) or null.
var _control: RefCounted = null
## W11-A: the VoDirector (res://src/core/vo_director.gd) or null.
var _vo_director: RefCounted = null
## W11-A: last resolved guard speaker per guard state transition (QA only).
var _vo_last_transition: Dictionary = {}
## W11-A: true once the live player's disguise signal is bound.
var _vo_player_bound: bool = false
## Authored RTPC gain/pitch currently applied to the music player.
var _rtpc_music_gain_db: float = 0.0
var _rtpc_music_pitch: float = 1.0
## Music player's authored trim (fade target without the RTPC gain) and whether
## a fade tween currently owns volume_db.
var _music_base_db: float = 0.0
var _music_fading: bool = false
## Last detection level pushed to the control plane (-1 = never pushed).
var _detection_level: float = -1.0
var _last_detection_msec: int = -100000
## game/data/expansion/audio_mix.json — TAT-2 mix keys (see that file).
var _mix_cfg: Dictionary = {}
var _bus_gain_db: Dictionary = {}
## Authored music player (menu title / explicit gameplay event). One at a time,
## mirroring the shipped MainMenu_C Music_Start/Music_Stop pair.
var _music_player: AudioStreamPlayer = null
var _music_kind: String = ""
## Authored placed ambience emitters, key -> AudioStreamPlayer3D.
var _emitters: Dictionary = {}
var _emitter_map: String = ""
## Environment (indoor/outdoor) as last applied; drives the authored reverb
## send and the authored room-tone bed swap.
var _interior: bool = false
var _env_initialised: bool = false
## True while a LOADING screen owns the mix (AU1-03 digital silence).
var _loading_silence: bool = false
var _last_scene_state_msec: int = -100000
## Functional VO descriptor for the UI (no authored dialogue text exists in
## the extraction, so this is never presented as transcribed speech).
signal subtitle_shown(text: String)



func _ready() -> void:
	# S27 pause duck must keep evaluating while the scene tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_was_active = get_tree() != null and get_tree().paused
	_pause_duck_db = PAUSE_DUCK_DB if _pause_was_active else 0.0
	_load_mix_config()
	_load_wwise()
	_load_control()
	_load_vo_director()
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
	# W11-A: guard/quest VO owns the GameState phase transition line; the
	# director is only an observer, it never changes the phase.
	if GameState != null and not GameState.phase_changed.is_connected(_on_phase_changed):
		GameState.phase_changed.connect(_on_phase_changed)
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
	# T03 authored players: emitters and music are freed (not queue_free) for
	# the same reason as the beds below — the deferred queue may not run.
	for key: Variant in _emitters.keys():
		var em: Node = _emitters[key] as Node
		if em != null and is_instance_valid(em):
			em.call("stop")
			em.set("stream", null)
			em.free()
	_emitters.clear()
	_emitter_map = ""
	if _music_player != null and is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
		_music_player.free()
	_music_player = null
	_music_kind = ""
	_loading_silence = false
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
	_foot_media.clear()
	_foot_idx.clear()
	_layer_pools.clear()
	_layer_idx.clear()


func _ensure_buses() -> void:
	for bus_name: String in [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE, BUS_UI, BUS_DIALOGUE]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	# T03: authored bus tree (16 VERB_* aux buses with real AudioEffectReverb,
	# mastering limiter + EQ on Master, sends). Idempotent and a no-op when the
	# generated control plane is absent — the legacy six buses stay the only
	# graph then, which mix_state() reports as `authored_buses: false`.
	_ww_call("build_buses", [])


## Loads the TAT-2 audio mix keys (game/data/expansion/audio_mix.json). A
## missing or malformed file keeps every documented default.
func _load_mix_config() -> void:
	_mix_cfg.clear()
	_bus_gain_db.clear()
	if not FileAccess.file_exists(MIX_CONFIG_PATH):
		return
	var f: FileAccess = FileAccess.open(MIX_CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_warning("[audio_manager] %s is not a JSON object; defaults kept" % MIX_CONFIG_PATH)
		return
	_mix_cfg = parsed as Dictionary
	var gains: Variant = _mix_cfg.get("bus_gains_db", {})
	if gains is Dictionary:
		for k: Variant in (gains as Dictionary).keys():
			_bus_gain_db[str(k)] = float((gains as Dictionary)[k])


## Instantiates the authored-control-plane helper. Dynamic on purpose: the
## helper reads a generated file that a fresh clone does not have, so a missing
## script or a missing JSON must degrade, never fail the autoload.
func _load_wwise() -> void:
	_wwise = null
	if not ResourceLoader.exists(WWISE_SCRIPT_PATH):
		return
	var scr: GDScript = ResourceLoader.load(WWISE_SCRIPT_PATH) as GDScript
	if scr == null:
		return
	var inst: Variant = scr.new()
	if inst == null:
		return
	_wwise = inst as RefCounted
	_ww_call("load_data", [])
	if not bool(_ww_call("is_loaded", []) or false):
		# Keep the helper for its documented neutral getters (so callers never
		# need a second null test) but report the reason through mix_state().
		push_warning("[audio_manager] authored Wwise control plane unavailable: %s" % str(_ww_call("degraded_reason", [])))


## Calls a method on the authored-control-plane helper when it exists.
## Returns null when the helper or the method is absent.
func _ww_call(method: String, args: Array) -> Variant:
	if _wwise == null or not _wwise.has_method(method):
		return null
	return _wwise.callv(method, args)


## String result of a helper call, "" when the helper is absent or returns null.
## (Must not be written as `str(_ww_call(...) or "")`: GDScript's `or` yields a
## bool, so an empty authored string would become the literal "false".)
func _ww_string(method: String, args: Array) -> String:
	var v: Variant = _ww_call(method, args)
	if v == null:
		return ""
	return str(v)


## True when the authored control plane (buses/attenuation/music/emitters/VO)
## is loaded. False on a fresh clone; every authored path then falls back to
## the pre-T03 behaviour instead of failing.
func has_authored_audio() -> bool:
	return bool(_ww_call("is_loaded", []) or false)


## ---------------------------------------------------------------------------
## W11-A authored VO director.
## ---------------------------------------------------------------------------

## Instantiates the VO director and feeds it the authored index. Dynamic for the
## same reason as the other helpers: a fresh clone has no audio_wwise.json, so
## the director stays unloaded and every cue resolves to "no authored line".
func _load_vo_director() -> void:
	_vo_director = null
	if not ResourceLoader.exists(VO_DIRECTOR_PATH):
		return
	var scr: GDScript = ResourceLoader.load(VO_DIRECTOR_PATH) as GDScript
	if scr == null:
		return
	var inst: Variant = scr.new()
	if inst == null:
		return
	_vo_director = inst as RefCounted
	var index_v: Variant = _ww_call("vo_index", [])
	if index_v is Dictionary:
		_vo_director.call("load_index", index_v)
	if not bool(_vo_director.call("is_loaded")):
		push_warning("[audio_manager] authored VO index unavailable; guard/quest VO stays silent")


## The director instance (null on a build without the script).
func vo_director() -> RefCounted:
	return _vo_director


## QA surface for the VO director (index size, cooldowns, last pick).
func vo_state() -> Dictionary:
	var lines: int = 0
	var stats_v: Variant = _ww_call("stats", [])
	if stats_v is Dictionary:
		lines = int((stats_v as Dictionary).get("vo_lines", 0))
	var out: Dictionary = {
		"available": _vo_director != null,
		"authored_lines": lines,
		"last_transition": _vo_last_transition.duplicate(true),
	}
	if _vo_director != null:
		out["director"] = _vo_director.call("report")
	return out


## Plays one authored VO event on the Dialogue bus and emits its functional
## subtitle. Zero-media authored lines (`Play_VO_Enforcer1_0_Silent_Empty_01`)
## are refused before any clip lookup: they are authored silence, not a missing
## join. Returns true only when a real clip started.
func play_vo_line(event_name: String, pos: Variant = null) -> bool:
	if _shutdown:
		return false
	var ev: String = event_name.strip_edges()
	if ev.is_empty():
		return false
	if has_authored_audio():
		var media_v: Variant = _ww_call("vo_media_count", [ev])
		if media_v is int and int(media_v) == 0:
			return false
	var clips: Variant = _event_clips.get(ev, [])
	if not (clips is Array):
		return false
	var stream: AudioStream = null
	for c: Variant in (clips as Array):
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
	if pos is Vector3:
		_play_stream_3d(stream, pos, VO_DB, BUS_DIALOGUE, ev)
	else:
		_play_stream_2d(stream, BUS_DIALOGUE, VO_DB)
	var sub: String = vo_subtitle(ev)
	if not sub.is_empty():
		subtitle_shown.emit(sub)
	return true


## Resolves a guard alertness transition to an authored line and plays it.
## [param speaker] is the authored speaker (`Enforcer1` / `Hauntstable1`).
func play_vo_transition(previous: String, next: String, speaker: String = "Enforcer1", pos: Variant = null) -> bool:
	_vo_last_transition = {
		"previous": previous,
		"next": next,
		"speaker": speaker,
	}
	if _vo_director == null:
		return false
	var now_s: float = float(Time.get_ticks_msec()) / 1000.0
	var pick_v: Variant = _vo_director.callv("vo_pick_transition", [previous, next, speaker, now_s])
	if not (pick_v is Dictionary):
		return false
	var pick: Dictionary = pick_v
	if not bool(pick.get("ok", false)):
		return false
	_vo_last_transition["event"] = str(pick.get("event", ""))
	_vo_last_transition["verb"] = str(pick.get("verb", ""))
	_vo_last_transition["state"] = str(pick.get("state", ""))
	return play_vo_line(str(pick.get("event", "")), pos)


## Resolves a player/quest cue (see VoDirector.EVENT_CUES) and plays it.
func play_vo_cue(cue: String, pos: Variant = null) -> bool:
	if _shutdown or _vo_director == null:
		return false
	var now_s: float = float(Time.get_ticks_msec()) / 1000.0
	var pick_v: Variant = _vo_director.callv("vo_pick_event", [cue, now_s])
	if not (pick_v is Dictionary):
		return false
	var pick: Dictionary = pick_v
	if not bool(pick.get("ok", false)):
		return false
	return play_vo_line(str(pick.get("event", "")), pos)


## GameState phase -> authored escape-phase player line. The line is authored
## voice; nothing about the mission flow changes here.
func _on_phase_changed(phase: String) -> void:
	if phase == GameState.PHASE_ENDGAME:
		var player: Node = get_tree().get_first_node_in_group("player") if get_tree() != null else null
		var pos: Variant = (player as Node3D).global_position if player is Node3D else null
		play_vo_cue("escape_phase", pos)


## Binds the player's disguise signal once the player exists. The same handler
## pushes the authored disguise-integrity RTPC and plays the authored
## DisguiseEnding line when the disguise collapses.
func _sync_vo_sources() -> void:
	if _vo_player_bound:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var player: Node = tree.get_first_node_in_group("player")
	if player == null or not player.has_signal("disguise_changed"):
		return
	player.connect("disguise_changed", _on_disguise_changed)
	_vo_player_bound = true


func _on_disguise_changed(integrity: float, active: bool) -> void:
	# W11-D: the authored Character_DisguiseIntegrity curve is in 0..100 units.
	set_rtpc("Character_DisguiseIntegrity", clampf(integrity, 0.0, 100.0))
	if not active and integrity <= 0.0:
		var player: Node = get_tree().get_first_node_in_group("player") if get_tree() != null else null
		var pos: Variant = (player as Node3D).global_position if player is Node3D else null
		play_vo_cue("disguise_ending", pos)


## ---------------------------------------------------------------------------
## B3a authored switch/state/RTPC control plane.
## Additive like T03: with no `audio_control.json` the token footstep pools and
## the legacy mix stay exactly as they were.
## ---------------------------------------------------------------------------

## Instantiates the control-plane helper. Dynamic for the same reason as
## `_load_wwise`: the JSON is derived content a fresh clone does not have.
func _load_control() -> void:
	_control = null
	if not ResourceLoader.exists(CONTROL_SCRIPT_PATH):
		return
	var scr: GDScript = ResourceLoader.load(CONTROL_SCRIPT_PATH) as GDScript
	if scr == null:
		return
	var inst: Variant = scr.new()
	if inst == null:
		return
	_control = inst as RefCounted
	_c_call("load_data", [])
	if not has_control_plane():
		push_warning("[audio_manager] authored Wwise control plane unavailable: %s" % str(_c_call("degraded_reason", [])))
		return
	# Single-player build: every character is locally controlled. The authored
	# group exists so a networked build could flip it; the port never sets Remote.
	_c_set_switch(CONTROL_SWITCH_LOCAL, "Local")


## Calls a method on the control helper when it exists; null otherwise.
func _c_call(method: String, args: Array) -> Variant:
	if _control == null or not _control.has_method(method):
		return null
	return _control.callv(method, args)


func _c_set_switch(group: String, value: String) -> bool:
	return bool(_c_call("set_switch", [group, value]) or false)


func _c_set_state(group: String, value: String) -> bool:
	return bool(_c_call("set_state", [group, value]) or false)


## True when audio_control.json loaded (switches/states/RTPCs available).
func has_control_plane() -> bool:
	return bool(_c_call("is_loaded", []) or false)


## Sets an authored switch (name or id either side). Public so a system that
## owns a group (e.g. enemy identity) can drive it without reaching into the
## helper.
func set_switch(group: Variant, value: Variant) -> bool:
	return bool(_c_call("set_switch", [group, value]) or false)


## Sets an authored state. States drive property overrides, not media selection.
func set_state(group: Variant, value: Variant) -> bool:
	return bool(_c_call("set_state", [group, value]) or false)


## Sets an authored RTPC value. Returns false when the id is not authored.
func set_rtpc(name: Variant, value: float) -> bool:
	return bool(_c_call("set_rtpc", [name, value]) or false)


## Switch/state/RTPC snapshot for QA (`mix_state().control`).
func control_state() -> Dictionary:
	var out: Variant = _c_call("state", [])
	return (out as Dictionary) if out is Dictionary else {"loaded": false, "degraded_reason": "missing_helper"}


## B3a: pushes the authored detection RTPC. [param level] is the normalized
## guard detection (0..1) already used by guard_ai.get_alert_state().suspicion.
## The value is always recorded; the authored music-node curve's gain and pitch
## are applied to the live music player (Godot has no bus pitch, and applying
## the gain to the Music bus would fight the slider/duck contract).
func set_detection_level(level: float) -> bool:
	if not has_control_plane():
		return false
	var v: float = clampf(level, 0.0, 1.0)
	if not bool(_c_call("set_rtpc", [CONTROL_DETECTION_RTPC, v]) or false):
		return false
	_detection_level = v
	# Never write `x or default` for a number: GDScript's `or` yields a bool, so
	# a non-zero authored value would become 1.0 (the `_ww_string` trap).
	var node_v: Variant = _c_call("curve_node_for_type", [CONTROL_DETECTION_RTPC, "volume_db", CONTROL_MUSIC_NODE_TYPE])
	var node: String = str(node_v) if node_v != null else ""
	var gain_v: Variant = _c_call("gain_db", [CONTROL_DETECTION_RTPC, node])
	_rtpc_music_gain_db = float(gain_v) if gain_v != null else 0.0
	var pitch_v: Variant = _c_call("pitch_scale", [CONTROL_DETECTION_RTPC, node])
	_rtpc_music_pitch = float(pitch_v) if pitch_v != null else 1.0
	_apply_music_rtpc()
	return true


## Applies the stored RTPC gain/pitch to the live music player. Volume is only
## touched when no fade tween owns it (`_music_fading`), so a fade-in and the
## RTPC can never overwrite each other in the same frame.
func _apply_music_rtpc() -> void:
	if _music_player == null or not is_instance_valid(_music_player):
		return
	_music_player.pitch_scale = _rtpc_music_pitch
	if not _music_fading:
		_music_player.volume_db = _music_base_db + _rtpc_music_gain_db


## Polls every live guard for its normalized detection and pushes the max into
## the authored RTPC. Throttled; a frame with no guards pushes 0 once.
func _sync_detection() -> void:
	if not has_control_plane():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_detection_msec < DETECTION_POLL_MS:
		return
	_last_detection_msec = now
	var worst: float = 0.0
	for node: Node in tree.get_nodes_in_group("guards"):
		if not node.has_method("get_alert_state"):
			continue
		var info: Variant = node.call("get_alert_state")
		if info is Dictionary:
			worst = maxf(worst, clampf(float((info as Dictionary).get("suspicion", 0.0)), 0.0, 1.0))
	if is_equal_approx(worst, _detection_level):
		return
	set_detection_level(worst)



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
	db += float(_bus_gain_db.get(bus_name, 0.0))
	if PAUSE_DUCK_BUSES.has(bus_name):
		db += _pause_duck_db
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, v <= 0.001)


## Effective bus gain in dB for QA/tests (slider + authored trim + duck).
func bus_level_db(bus_name: String) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 0.0
	return AudioServer.get_bus_volume_db(idx)


## S27: pause menu ambience duck (AU4-05). The tree's paused flag is the
## authority, so HUD pause handling stays outside this file's ownership.
## T03: the duck is a gameplay duck over Ambience+SFX+Music; the pre-T03 code
## attenuated Ambience alone, so a bed or a one-shot on another bus kept its
## level through the pause menu.
func _process(_delta: float) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var paused: bool = tree.paused
	if paused != _pause_was_active:
		_pause_was_active = paused
		_pause_duck_db = PAUSE_DUCK_DB if paused else 0.0
		for bus_name: String in PAUSE_DUCK_BUSES:
			_apply_bus_level(bus_name)
		# B3a: authored modal state (the bank's Modal_State group). Recorded for
		# the control plane and for any system that reads the state; the duck
		# above stays the audible pause change.
		_c_set_state(CONTROL_STATE_MODAL, "Modal_Menu" if paused else "Modal_Gameplay")
	_sync_environment()
	_sync_detection()
	_sync_vo_sources()


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


## ---------------------------------------------------------------------------
## T03 authored control plane (RE-M-01/02/03/04/05/10).
## Every function here is additive: with no generated `audio_wwise.json` the
## pre-T03 behaviour is unchanged and mix_state() reports why.
## ---------------------------------------------------------------------------

## T03: environment = indoor/outdoor from the existing ceiling probe. It drives
## the authored reverb send (8.0 s exterior / 0.45 s interior decay, from
## DefaultReverbAssignmentTable). Throttled, and skipped without a player.
func _sync_environment() -> void:
	if not has_authored_audio():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_scene_state_msec < 500:
		return
	_last_scene_state_msec = now
	if tree.get_first_node_in_group("player") == null:
		return
	set_environment(_is_indoor())


## Applies the authored room reverb for [param indoor] to the gameplay buses.
## The per-room *bed* swap needs the TATSpatialAudioVolume geometry, which the
## extraction does not carry (no Brush bounds) — that half is BLOCKED-ON T09 and
## reported as `bed_step: "blocked:T09"` rather than invented as a dB trim.
func set_environment(indoor: bool) -> void:
	# B3a: authored Weather_isExterior state. Set before the early return so a
	# repeated environment push still reaches the control plane's state table.
	_c_set_state(CONTROL_STATE_ENV, "Interior" if indoor else "Exterior")
	if _env_initialised and indoor == _interior:
		return
	_interior = indoor
	_env_initialised = true
	var kind: String = "interior" if indoor else "exterior"
	var rb: String = _ww_string("reverb_bus_for", [kind])
	if rb.is_empty():
		return
	for bus_name: String in [BUS_AMBIENCE, BUS_SFX]:
		_route_bus_reverb(bus_name, rb)


## Routes [param bus_name]'s output through the authored reverb bus. Returns
## false when the reverb bus does not exist (fresh clone) or the helper cannot
## express the send; the bus then stays dry instead of being re-parented.
func _route_bus_reverb(bus_name: String, reverb_bus: String) -> bool:
	if AudioServer.get_bus_index(reverb_bus) == -1:
		return false
	var routed: Variant = _ww_call("route_bus_to_reverb", [bus_name, reverb_bus])
	return routed is bool and bool(routed)


## Authored attenuation for [param event_name] (RE-M-02). Empty when unknown.
func authored_attenuation(event_name: String) -> Dictionary:
	var info: Variant = _ww_call("attenuation_for", [event_name])
	return (info as Dictionary) if info is Dictionary else {}


## Stamps an authored radius/curve on a 3D player. Returns false when the event
## has no authored attenuation, in which case the legacy 60 m inverse-distance
## model stays in place (documented fallback, not a silent change).
func _apply_authored_attenuation(player: AudioStreamPlayer3D, event_name: String) -> bool:
	var info: Dictionary = authored_attenuation(event_name)
	if not bool(info.get("found", false)):
		player.max_distance = MAX_DISTANCE_M
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		return false
	var radius: float = float(info.get("max_distance_m", MAX_DISTANCE_M))
	if bool(info.get("is_2d", false)) or radius <= 0.0:
		# Authored 2D event (radius 0): keep it omnipresent instead of muting it
		# at a distance it never had. unit_size >= max_distance = flat.
		player.max_distance = MAX_DISTANCE_M
		player.unit_size = MAX_DISTANCE_M
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		return true
	var inner: float = float(info.get("unit_size", radius * 0.1))
	player.max_distance = radius
	player.unit_size = clampf(inner, 0.1, radius)
	player.max_db = 0.0
	# Godot 4.7 has no authored-curve model (INVERSE_DISTANCE / INVERSE_SQUARE /
	# LOGARITHMIC / DISABLED only). The authored dB curve is matched at its
	# endpoint by unit_size (see AudioWwise._unit_size_for), so the inverse
	# distance model reproduces the authored level at the authored cull radius
	# and is flat when the curve is flat. The curve shape is reported in
	# mix_state() so the approximation is visible rather than silent.
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	return true


## T03 occlusion settings from the TAT-2 mix overlay (game/data/expansion/
## audio_mix.json). Defaults are the documented values in that file.
func _occlusion_cfg() -> Dictionary:
	var occ: Variant = _mix_cfg.get("occlusion", {})
	return (occ as Dictionary) if occ is Dictionary else {}


## Extra gain in dB for a 3D one-shot at [param pos], from one listener→source
## ray (RE-M-03). 0.0 when nothing blocks it.
func occlusion_gain_db(pos: Vector3) -> float:
	var cfg: Dictionary = _occlusion_cfg()
	if not bool(cfg.get("enabled", true)):
		return 0.0
	var loss: float = float(cfg.get("authored_loss", 1.0))
	if loss <= 0.0:
		return 0.0
	var wall_db: float = float(cfg.get("wall_db", OCCLUSION_WALL_DB_FALLBACK))
	if not _occluded(pos):
		return 0.0
	return wall_db * loss


## Authored low-pass cutoff for an occluded source (Hz).
func occlusion_cutoff_hz() -> float:
	var cfg: Dictionary = _occlusion_cfg()
	var max_hz: float = float(cfg.get("max_cutoff_hz", 20000.0))
	var min_hz: float = float(cfg.get("min_cutoff_hz", OCCLUSION_MIN_CUTOFF_HZ))
	var loss: float = clampf(float(cfg.get("authored_loss", 1.0)), 0.001, 1.0)
	return clampf(max_hz * loss * loss, min_hz, max_hz)


## One listener→source ray. Hits closer than OCCLUSION_MIN_HIT_M to either end
## are the floor under the player or the emitter's own wall, not a wall between.
func _occluded(pos: Vector3) -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	var world: World3D = vp.find_world_3d()
	if world == null:
		return false
	var from: Vector3 = _listener_position()
	var d: float = from.distance_to(pos)
	if d < 1.0:
		return false
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, pos)
	q.hit_from_inside = false
	# The player's own capsule sits between the camera and its feet; excluding
	# it keeps a footstep from being occluded by its emitter.
	var tree: SceneTree = get_tree()
	if tree != null:
		var body: CollisionObject3D = tree.get_first_node_in_group("player") as CollisionObject3D
		if body != null:
			# The player's own capsule sits between the camera and its feet, so
			# excluding it keeps a footstep from being occluded by its emitter.
			# `get_collision_exceptions()` returns physics bodies, not RIDs, in
			# this engine build: assigning it straight to Array[RID] raised a
			# SCRIPT ERROR on every footstep AND left the list empty, so the ray
			# hit the player capsule and occlusion never applied. Convert by
			# type, defensively, and always exclude the body itself.
			var excluded: Array[RID] = [body.get_rid()]
			if body.has_method("get_collision_exceptions"):
				for exc: Variant in body.call("get_collision_exceptions"):
					if exc is RID:
						excluded.append(exc)
					elif exc is CollisionObject3D:
						excluded.append((exc as CollisionObject3D).get_rid())
			q.exclude = excluded
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var hp: Vector3 = hit.get("position", from) as Vector3
	var along: float = from.distance_to(hp)
	return along >= OCCLUSION_MIN_HIT_M and (d - along) >= OCCLUSION_MIN_HIT_M


## Listener position for attenuation/occlusion: the active camera, else the
## player, else the origin (menus and headless probes).
func _listener_position() -> Vector3:
	var vp: Viewport = get_viewport()
	if vp != null:
		var cam: Camera3D = vp.get_camera_3d()
		if cam != null:
			return cam.global_position
	var tree: SceneTree = get_tree()
	if tree != null:
		var p: Node3D = tree.get_first_node_in_group("player") as Node3D
		if p != null:
			return p.global_position
	return Vector3.ZERO


## Spawns the authored placed emitters for [param map_id] (RE-M-04). Returns the
## number started. `[]` for a map with no authored emitters — never invented.
func start_map_emitters(map_id: String) -> int:
	stop_map_emitters()
	if not has_authored_audio():
		return 0
	var list: Variant = _ww_call("emitters_for_map", [map_id])
	if not (list is Array):
		return 0
	var arr: Array = list as Array
	if arr.is_empty():
		_emitter_map = map_id
		return 0
	var chosen: Array = arr
	if arr.size() > EMITTER_CAP:
		chosen = _nearest_emitters(arr, _listener_position(), EMITTER_CAP)
	var started: int = 0
	for i: int in range(chosen.size()):
		var e: Variant = chosen[i]
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e
		var ev: String = str(ed.get("event", ""))
		var pos_v: Variant = ed.get("pos")
		if ev.is_empty() or not (pos_v is Vector3):
			continue
		var stream: AudioStream = _bed_stream(ev, "")
		if stream == null:
			continue
		var p := AudioStreamPlayer3D.new()
		p.stream = stream
		p.bus = BUS_AMBIENCE
		p.position = pos_v as Vector3
		p.volume_db = _ambience_trim_db(ev)
		_apply_authored_attenuation(p, ev)
		add_child(p)
		p.play()
		_emitters[map_id + "|" + str(ed.get("actor", str(i)))] = p
		started += 1
	_emitter_map = map_id
	return started


## Deterministic nearest-first selection when a map authors more emitters than
## the cap (stable sort on distance then actor name).
func _nearest_emitters(arr: Array, listener: Vector3, cap: int) -> Array:
	var keyed: Array = []
	for e: Variant in arr:
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e
		var pos_v: Variant = ed.get("pos")
		var d: float = listener.distance_to(pos_v as Vector3) if pos_v is Vector3 else 0.0
		keyed.append([d, str(ed.get("actor", "")), ed])
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		if is_equal_approx(float(a[0]), float(b[0])):
			return str(a[1]) < str(b[1])
		return float(a[0]) < float(b[0])
	)
	var out: Array = []
	for i: int in range(mini(cap, keyed.size())):
		out.append((keyed[i] as Array)[2])
	return out


func stop_map_emitters() -> void:
	for key: Variant in _emitters.keys():
		var p: Node = _emitters[key] as Node
		if p != null and is_instance_valid(p):
			p.call("stop")
			p.set("stream", null)
			p.queue_free()
	_emitters.clear()
	_emitter_map = ""


## Count of live authored emitters (QA/probes).
func active_emitters() -> int:
	return _emitters.size()


## ---------------------------------------------------------------------------
## Music (RE-M-05). The shipped build hard-wires the title theme in
## MainMenu_C (MusicEvent_Play = Play_Mus_MainTitleScreen). Gameplay music is
## state-driven and stays off until an owning system calls start_music() with
## an authored kind, so no map can play un-authored music.
## ---------------------------------------------------------------------------

## Authored music event for [param kind]; [] when the build has none. Falls back
## to the literal authored names so this works before the JSON is regenerated.
func music_event_for(kind: String) -> String:
	var k: String = kind.to_lower().strip_edges()
	if has_authored_audio():
		var ev: Variant = _ww_call("music_event", [k])
		if ev is String and not (ev as String).is_empty():
			return ev as String
	return str(MUSIC_FALLBACK_PINS.get(k, ""))


## Starts an authored music event on the Music bus. One at a time (the shipped
## MainMenu_C has a single Music_Start/Music_Stop pair). Returns false when the
## kind is not authored or the clip did not resolve.
## [param trim_db] NaN means "use the TAT-2 overlay's music.title_music.trim_db,
## else MUSIC_TRIM_DB".
## [param fade_s] NaN means "use the authored transition fade when the event is
## bound to a MusicSwitchContainer, else MUSIC_FADE_FALLBACK_S" (W11-B).
func start_music(kind: String, trim_db: float = NAN, fade_s: float = NAN) -> bool:
	if _shutdown:
		return false
	var k: String = kind.to_lower().strip_edges()
	if _music_kind == k and is_instance_valid(_music_player):
		return true
	return _start_music_event(music_event_for(k), k, trim_db, fade_s)


## Plays an explicit authored music event (a gameplay system that knows its own
## state, e.g. a stinger). Only authored `Play_Mus_*` events that resolve a clip
## are accepted, so no map can play un-authored music.
func play_music_event(event_name: String, trim_db: float = NAN, fade_s: float = NAN) -> bool:
	if _shutdown:
		return false
	var ev: String = event_name.strip_edges()
	if not ev.begins_with("Play_Mus_"):
		return false
	if not _event_clips.has(ev):
		return false
	return _start_music_event(ev, "event:" + ev, trim_db, fade_s)


## W11-B: the authored transition fade for a music event, in seconds; NAN when
## the event is not bound to a MusicSwitchContainer or the document has no music
## block. A 0 ms authored fade is a real authored value (0.0), not "unknown".
func music_fade_for_event(event_name: String) -> float:
	if not has_control_plane():
		return NAN
	var container_v: Variant = _c_call("music_container_for_event", [event_name])
	if not (container_v is int) or int(container_v) == 0:
		return NAN
	var rule_v: Variant = _c_call("music_transition", [int(container_v)])
	if not (rule_v is Dictionary):
		return NAN
	var rule: Dictionary = rule_v as Dictionary
	if not bool(rule.get("found", false)):
		return NAN
	return maxf(float(rule.get("fade_ms", 0.0)) / 1000.0, 0.0)


func _start_music_event(ev: String, kind: String, trim_db: float, fade_s: float) -> bool:
	if ev.is_empty():
		return false
	var stream: AudioStream = _bed_stream(ev, "")
	if stream == null:
		return false
	var fade: float = fade_s
	if is_nan(fade):
		var authored: float = music_fade_for_event(ev)
		fade = authored if not is_nan(authored) else MUSIC_FADE_FALLBACK_S
	var trim: float = _music_trim_db() if is_nan(trim_db) else trim_db
	stop_music(0.0)
	_music_base_db = trim
	_music_fading = false
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = stream
	_music_player.bus = BUS_MUSIC
	_music_player.pitch_scale = _rtpc_music_pitch
	_music_player.volume_db = (trim + _rtpc_music_gain_db) if fade <= 0.0 else trim - 20.0
	add_child(_music_player)
	_music_player.play()
	if fade > 0.0:
		_music_fading = true
		var tw: Tween = _track_bed_tween(create_tween())
		tw.tween_property(_music_player, "volume_db", trim + _rtpc_music_gain_db, fade)
		tw.finished.connect(func() -> void:
			_music_fading = false
		)
	_music_kind = kind
	return true


## Music trim from the TAT-2 overlay (music.title_music.trim_db), else the
## documented MUSIC_TRIM_DB.
func _music_trim_db() -> float:
	var music: Variant = _mix_cfg.get("music", {})
	if music is Dictionary:
		var title: Variant = (music as Dictionary).get("title_music", {})
		if title is Dictionary:
			return float((title as Dictionary).get("trim_db", MUSIC_TRIM_DB))
	return MUSIC_TRIM_DB


func stop_music(fade_s: float = 0.4) -> void:
	var p: AudioStreamPlayer = _music_player
	_music_player = null
	_music_kind = ""
	_music_fading = false
	if not is_instance_valid(p):
		return
	if fade_s <= 0.0:
		p.stop()
		p.stream = null
		p.queue_free()
		return
	var tw: Tween = _track_bed_tween(create_tween())
	tw.tween_property(p, "volume_db", -60.0, fade_s)
	tw.tween_callback(func() -> void:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
			p.queue_free()
	)


func music_kind() -> String:
	return _music_kind


## True while an authored music event is playing.
func is_music_playing() -> bool:
	return _music_kind != "" and is_instance_valid(_music_player)


## ---------------------------------------------------------------------------
## VO (RE-M-10). The 645 authored lines now reach the director (W11-A); this is
## the single playback entry point for them plus the functional subtitle the UI
## can display. It is NOT a claim that all 645 lines are wired: the director maps
## the guard transitions and the player/quest beats it owns, and the lines with
## no honest caller stay unmapped (see VoDirector.EVENT_CUES).
## ---------------------------------------------------------------------------

## Plays one authored VO line. Back-compat alias of [method play_vo_line].
func play_vo_event(event_name: String, pos: Variant = null) -> bool:
	return play_vo_line(event_name, pos)


## Functional VO descriptor from the authored event name, e.g.
## "Enforcer1 · ThiefSeen · VisionStim · Heavy (01)". The extraction carries no
## authored dialogue text (localization keys are GUIDs), so this is a
## description of the authored line, never presented as transcribed speech.
func vo_subtitle(event_name: String) -> String:
	var s: Variant = _ww_call("vo_subtitle", [event_name])
	return str(s) if s is String else ""


## Everything the mix currently is, for QA/tests and the wave report.
func mix_state() -> Dictionary:
	var buses: Dictionary = {}
	for bus_name: String in ["Master", BUS_MUSIC, BUS_SFX, BUS_AMBIENCE, BUS_UI, BUS_DIALOGUE]:
		buses[bus_name] = bus_level_db(bus_name)
	return {
		"authored_audio": has_authored_audio(),
		"degraded_reason": _ww_string("degraded_reason", []),
		"bus_levels_db": buses,
		"authored_bus_report": _ww_call("bus_report", []),
		"pause_duck_db": _pause_duck_db,
		"duck_buses": PAUSE_DUCK_BUSES,
		"interior": _interior,
		"bed_step": "blocked:T09" if _interior else "exterior",
		"music_kind": _music_kind,
		"music": authored_music_state(_current_music_event()),
		"emitters": _emitters.size(),
		"emitter_map": _emitter_map,
		"beds": active_bed_levels(),
		"master_volume_db": bus_level_db("Master"),
		"control": control_state(),
		"vo": vo_state(),
		"rtpc": authored_rtpc_state(),
		"detection_level": _detection_level,
		"rtpc_music_gain_db": _rtpc_music_gain_db,
		"rtpc_music_pitch": _rtpc_music_pitch,
	}


## W11-B: the authored music transition state for one event (fade, container,
## rule). Empty-ish when the event is not bound to a MusicSwitchContainer.
func authored_music_state(event_name: String) -> Dictionary:
	var fade: float = music_fade_for_event(event_name)
	var out: Dictionary = {
		"event": event_name,
		"container_id": 0,
		"fade_s": -1.0 if is_nan(fade) else fade,
		"transition": {},
	}
	if not has_control_plane() or event_name.is_empty():
		return out
	var container_v: Variant = _c_call("music_container_for_event", [event_name])
	if not (container_v is int) or int(container_v) == 0:
		return out
	out["container_id"] = int(container_v)
	out["transition"] = _c_call("music_transition", [int(container_v)])
	return out


func _current_music_event() -> String:
	if _music_kind.begins_with("event:"):
		return _music_kind.substr(6)
	if _music_kind.is_empty():
		return ""
	return music_event_for(_music_kind)


## W11-D: the authored mix parameters with real callers in this port, with the
## exact curve values at their current setting. The five curves live on
## ActorMixer/LayerContainer nodes the port does not instantiate as buses, so
## they are recorded and exposed rather than applied to a global bus (a global
## application would fight the slider + duck contract pinned by
## test_audio_mix.gd). The crouch curve is the exception: `play_footstep` adds
## its exact authored gain to the footstep playback.
func authored_rtpc_state() -> Dictionary:
	var out: Dictionary = {}
	for name: String in AUTHORED_RTPCS:
		if not has_control_plane():
			out[name] = {"value": 0.0, "gain_db": 0.0, "pitch_scale": 1.0, "low_pass_hz": 0.0}
			continue
		var value_v: Variant = _c_call("rtpc_value", [name])
		var gain_v: Variant = _c_call("gain_db", [name])
		var pitch_v: Variant = _c_call("pitch_scale", [name])
		var lpf_v: Variant = _c_call("low_pass_hz", [name])
		out[name] = {
			"value": float(value_v) if value_v != null else 0.0,
			"gain_db": float(gain_v) if gain_v != null else 0.0,
			"pitch_scale": float(pitch_v) if pitch_v != null else 1.0,
			"low_pass_hz": float(lpf_v) if lpf_v != null else 0.0,
		}
	return out


## True when a LOADING screen currently owns the mix (AU1-03).
func is_loading_silence() -> bool:
	return _loading_silence



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
			clips.append({
				"debug_name": str(md.get("debug_name", "")),
				"clip": clip,
				# B3a: the authored MediaId, the key audio_control.json selects on.
				"media_id": int(md.get("media_id", 0)),
			})
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
	_foot_media.clear()
	_foot_idx.clear()
	for gait: Variant in FOOTSTEP_GAIT_EVENTS.keys():
		var ev_name := str(FOOTSTEP_GAIT_EVENTS[gait])
		var clips: Variant = _event_clips.get(ev_name, [])
		if not (clips is Array):
			continue
		for surface: Variant in FOOTSTEP_SURFACE_KEYS.keys():
			var keys: Array = FOOTSTEP_SURFACE_KEYS[surface] as Array
			var pool: Array = []
			var media: Array = []
			for c: Variant in (clips as Array):
				if not (c is Dictionary):
					continue
				var cd: Dictionary = c
				var dn := str(cd.get("debug_name", "")).to_lower().replace("\\", "/")
				if dn.find("loot_bag") >= 0:
					continue
				for sk: Variant in keys:
					if dn.find(str(sk)) >= 0:
						pool.append(str(cd.get("clip", "")))
						media.append(int(cd.get("media_id", 0)))
						break
			if not pool.is_empty():
				var pool_key := str(gait) + "|" + str(surface)
				_foot_pools[pool_key] = pool
				_foot_media[pool_key] = media
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
## B3a: when the authored control plane is loaded the surface/gait switches are
## set first and the token pool is filtered by the authored package media, so
## the clip family is the bank's choice. The token pool stays the fallback (and
## the whole path on a fresh clone).
## W11-C: [param layer] is the authored `FS_Layers` value (Puddle /
## Glass_Broken / Foliage / Grass / Nothing). Empty derives it from the surface
## through the resolver, which is exact for the wet/glass tokens and cannot
## recover Grass/Foliage from the collapsed "earth" token — a caller that knows
## the authored surface name should pass `SurfaceResolver.layer_for(name)`.
func play_footstep(surface: String = "wood", gait: String = "walk", pos: Vector3 = Vector3.ZERO, layer: String = "") -> bool:
	var g: String = gait.to_lower().strip_edges()
	var s: String = _scene_surface(surface)
	var l: String = layer.strip_edges()
	if l.is_empty():
		l = str(SurfaceResolver.layer_for(surface))
	_apply_footstep_control(g, s, l)
	var clip: String = _footstep_clip_control(g, s)
	if clip.is_empty():
		clip = _footstep_clip(gait, surface)
	# W11-D: the authored Character_FS_isCrouching curve is applied to the
	# footstep playback (its authored target is the FS actor-mixer chain). The
	# value is the exact authored curve output; the node binding is the port's
	# documented choice because the port has one footstep player, not the bank's
	# ActorMixer tree.
	var crouch_gain_db: float = 0.0
	if has_control_plane():
		var gain_v: Variant = _c_call("gain_db", ["Character_FS_isCrouching"])
		if gain_v != null:
			crouch_gain_db = float(gain_v)
	var played: bool = false
	if not clip.is_empty() and ResourceLoader.exists(clip):
		var stream: AudioStream = ResourceLoader.load(clip) as AudioStream
		if stream != null:
			_play_stream_3d(stream, pos, crouch_gain_db, BUS_SFX,
				str(FOOTSTEP_GAIT_EVENTS.get(gait.to_lower(), "")))
			played = true
	if not played and _sfx.has("footstep"):
		_play_at("footstep", pos, 0.0)
		played = true
	# W11-C: the authored layer is a *second* Play action branch in the bank
	# (FS_Layers=Puddle adds 8 recordings on top of the 44 Stone ones), so it
	# plays alongside the surface clip, not instead of it. No authored trim is
	# applied; the recordings carry their own level.
	var layer_clip: String = _layer_clip_control(g, s, l)
	if not layer_clip.is_empty() and ResourceLoader.exists(layer_clip):
		var layer_stream: AudioStream = ResourceLoader.load(layer_clip) as AudioStream
		if layer_stream != null:
			_play_stream_3d(layer_stream, pos, 0.0, BUS_SFX, str(FOOTSTEP_GAIT_EVENTS.get(g, "")))
			played = true
	return played


## W11-C: round-robin over the layer recordings the authored `FS_Layers`
## package adds on top of the selected `FS_Material` package. Empty when the
## control plane is absent, the layer is `Nothing`, or the material/layer
## packages do not resolve for this gait. The pool is authored package media
## joined to clips through `audio_events.json`; nothing is guessed from a name.
func _layer_clip_control(gait: String, surface: String, layer: String) -> String:
	if not has_control_plane() or layer.is_empty() or layer == "Nothing":
		return ""
	var key: String = gait + "|" + surface + "|" + layer
	if not _layer_pools.has(key):
		_layer_pools[key] = _build_layer_pool(gait, surface, layer)
	var pool: Array = _layer_pools[key] as Array
	if pool.is_empty():
		return ""
	var idx: int = int(_layer_idx.get(key, 0)) % pool.size()
	_layer_idx[key] = idx + 1
	return str(pool[idx])


func _build_layer_pool(gait: String, surface: String, layer: String) -> Array:
	var ev: String = str(FOOTSTEP_GAIT_EVENTS.get(gait, ""))
	var material: String = str(CONTROL_SURFACE_VALUES.get(surface, ""))
	if ev.is_empty() or material.is_empty():
		return []
	var base_v: Variant = _c_call("media_ids_for", [ev, CONTROL_SWITCH_MATERIAL, material])
	var layer_v: Variant = _c_call("media_ids_for", [ev, CONTROL_SWITCH_LAYER, layer])
	if not (base_v is Array) or not (layer_v is Array):
		return []
	# The layer package list is a per-container superset (it carries nested
	# branches), so intersect it with the current selection before subtracting
	# the material package: the authored layer set is what the ban leaves alive.
	var allowed_v: Variant = _c_call("select_media", [ev, layer_v])
	var allowed: Array = allowed_v as Array if allowed_v is Array else (layer_v as Array)
	var base: Dictionary = {}
	for mid: Variant in (base_v as Array):
		base[int(mid)] = true
	var want: Dictionary = {}
	for mid: Variant in allowed:
		if not base.has(int(mid)):
			want[int(mid)] = true
	if want.is_empty():
		return []
	var clips: Variant = _event_clips.get(ev, [])
	if not (clips is Array):
		return []
	var out: Array = []
	for c: Variant in (clips as Array):
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		if not want.has(int(cd.get("media_id", 0))):
			continue
		var clip: String = str(cd.get("clip", ""))
		if not clip.is_empty() and not out.has(clip):
			out.append(clip)
	out.sort()
	return out


## B3a: pushes the authored footstep switch set. Gait is one of the authored
## Character_Movement_Mode values (walk/run/jog/crouch/wallclimb); a surface the
## table does not cover leaves FS_Material at its authored default.
## W11-C: `FS_Layers` is set from the authored layer value; an empty/unknown
## layer falls back to the authored group default (`Nothing`), never a guess.
func _apply_footstep_control(gait: String, surface: String, layer: String = "Nothing") -> void:
	if not has_control_plane():
		return
	_c_set_switch(CONTROL_SWITCH_GAIT, gait)
	var value: String = str(CONTROL_SURFACE_VALUES.get(surface, ""))
	if not value.is_empty():
		_c_set_switch(CONTROL_SWITCH_MATERIAL, value)
	var layer_value: String = layer.strip_edges()
	if layer_value.is_empty():
		layer_value = "Nothing"
	_c_set_switch(CONTROL_SWITCH_LAYER, layer_value)


## B3a: round-robin inside the token pool restricted to the media the authored
## switch selection allows. "" when the control plane is absent, the pool has no
## media ids, or the authored selection empties the pool (then the caller keeps
## the unfiltered pool).
func _footstep_clip_control(gait: String, surface: String) -> String:
	if not has_control_plane():
		return ""
	var pool_key: String = gait + "|" + surface
	var media_v: Variant = _foot_media.get(pool_key, null)
	if not (media_v is Array):
		return ""
	var media: Array = media_v as Array
	if media.is_empty():
		return ""
	var event_name: String = str(FOOTSTEP_GAIT_EVENTS.get(gait, ""))
	if event_name.is_empty():
		return ""
	var filtered_v: Variant = _c_call("select_media", [event_name, media])
	if not (filtered_v is Array) or (filtered_v as Array).is_empty():
		return ""
	var allowed: Dictionary = {}
	for mid: Variant in (filtered_v as Array):
		allowed[int(mid)] = true
	var pool: Array = _foot_pools[pool_key] as Array
	var n: int = pool.size()
	var start: int = int(_foot_idx.get(pool_key, 0))
	for i: int in range(n):
		var idx: int = (start + i) % n
		if not allowed.has(int(media[idx])):
			continue
		_foot_idx[pool_key] = idx + 1
		return str(pool[idx])
	return ""


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
	stop_map_emitters()
	stop_gramophone()


## T03 (AU1-03): true silence for a loading screen. Loading is a screen cut in
## the shipped build, so the beds/emitters/music stop at once and the gameplay
## buses are muted until the next scene. The caller keeps ownership of *when*
## (loading_screen.gd:197 already stops the beds); this guarantees the result is
## digital zero instead of a 0.35 s tail.
func begin_loading_silence() -> void:
	var cfg: Variant = _mix_cfg.get("mix_states", {})
	if cfg is Dictionary:
		var ls: Variant = (cfg as Dictionary).get("loading_silence", {})
		if ls is Dictionary and not bool((ls as Dictionary).get("enabled", true)):
			return
	_loading_silence = true
	stop_all_beds(0.0)
	stop_music(0.0)
	for bus_name: String in [BUS_AMBIENCE, BUS_SFX, BUS_MUSIC]:
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_mute(idx, true)


## Restores the gameplay buses muted by begin_loading_silence().
func end_loading_silence() -> void:
	if not _loading_silence:
		return
	_loading_silence = false
	for bus_name: String in [BUS_AMBIENCE, BUS_SFX, BUS_MUSIC]:
		_apply_bus_level(bus_name)


## Starts a looped 2D bed from an authored event (any event, first resolvable
## clip). Used by the authored ambience path; [param key] is the bed slot.
func start_event_bed(key: String, ev_name: String, trim_db: float, fade_s: float = 0.6) -> bool:
	if _shutdown:
		return false
	var k: String = key.to_lower().strip_edges()
	if k.is_empty() or ev_name.is_empty():
		return false
	_cancel_fading_bed(k)
	if _beds.has(k):
		return true
	var stream: AudioStream = _bed_stream(ev_name, "")
	if stream == null:
		return false
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_AMBIENCE
	player.volume_db = trim_db if fade_s <= 0.0 else trim_db - 20.0
	add_child(player)
	player.play()
	_beds[k] = player
	if fade_s > 0.0:
		var tw: Tween = _track_bed_tween(create_tween())
		tw.tween_property(player, "volume_db", trim_db, fade_s)
	return true


## AU1 scene beds against KEYFRAME §4. The Den is room tone only (no BGM);
## Guildhall layers the S12 rain under a quiet safe-room bed; the Manor is
## exterior rain; loading screens silence everything (LoadingScreen calls
## stop_all_beds). The wind bed is opt-in for the S05/S09 rooftop view.
##
## T03 (RE-M-04): when the authored control plane is present the map's 90 placed
## emitters (3D, authored event + position + attenuation) plus the authored
## per-room bed replace the invented bed keys. The legacy path stays as the
## documented degraded fallback and is what mix_state() reports as
## `authored_audio: false`.
func play_bed_scene(map_id: String) -> void:
	end_loading_silence()
	stop_all_beds(0.2)
	if has_authored_audio():
		var started: int = start_map_emitters(map_id)
		var base_ev: String = scene_bed_event(map_id)
		if base_ev.is_empty():
			base_ev = _ww_string("room_bed_for", [map_id])
		if started > 0 or not base_ev.is_empty():
			if not base_ev.is_empty():
				start_event_bed("authored_room", base_ev, _ambience_trim_db(base_ev))
			return
		# A map that authors neither a placed emitter the contract can read nor a
		# room bed (the Thieves' Den: its only placed component carries
		# AkLoopingAudio, and its room volume has no event) falls through to the
		# legacy bed rather than going silent.
		stop_map_emitters()
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


## T03: authored title music switch (music.title_music.enabled). The shipped
## MainMenu_C hard-wires MusicEvent_Play = Play_Mus_MainTitleScreen; the
## 2026-11-24 capture's startscreen bed matches neither that event nor any port
## bed (see game/data/expansion/audio_mix.json), so the switch exists to match
## the recording instead of the build.
func title_music_enabled() -> bool:
	var music: Variant = _mix_cfg.get("music", {})
	if music is Dictionary:
		var title: Variant = (music as Dictionary).get("title_music", {})
		if title is Dictionary:
			return bool((title as Dictionary).get("enabled", true))
	return true


func _autostart_scene_bed() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var scene: Node = tree.current_scene
	if scene == null:
		return
	if not scene.scene_file_path.ends_with("main_menu.tscn"):
		return
	# T03: authored players are restored on every scene that owns the mix, so a
	# loading screen that is dismissed without a map change cannot leave the
	# gameplay buses muted.
	end_loading_silence()
	if has_authored_audio():
		# T03: the startscreen authors 12 placed emitters + 12 room beds
		# (BeautifulCorner_Startscreen_P), a base ambience event
		# (MainMenu_C.AmbientEvent_Play = Play_Amb_MainMenu) and the title theme
		# (MainMenu_C.MusicEvent_Play).
		if _emitter_map == "main_menu" and not _emitters.is_empty():
			return
		start_map_emitters("main_menu")
		var base_ev: String = scene_bed_event("main_menu")
		if base_ev.is_empty():
			base_ev = _ww_string("room_bed_for", ["main_menu"])
		if not base_ev.is_empty():
			start_event_bed("authored_room", base_ev, _ambience_trim_db(base_ev), 1.2)
		if title_music_enabled():
			start_music("title", NAN, 1.2)
		return
	if _beds.has("rain"):
		return
	start_bed("rain", 1.2)


## T03: authored base ambience event for a scene, from the TAT-2 overlay
## (scene_beds.<key>.event). Empty when the scene has none.
func scene_bed_event(scene_key: String) -> String:
	var beds: Variant = _mix_cfg.get("scene_beds", {})
	if not (beds is Dictionary):
		return ""
	var row: Variant = (beds as Dictionary).get(scene_key.to_lower(), {})
	if not (row is Dictionary):
		return ""
	return str((row as Dictionary).get("event", ""))


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
		_play_stream_3d(stream, pos, VO_DB, BUS_DIALOGUE, str(pin[0]))
	else:
		_play_stream_2d(stream, BUS_DIALOGUE, VO_DB)
	var sub: String = vo_subtitle(str(pin[0]))
	if not sub.is_empty():
		subtitle_shown.emit(sub)
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
		_play_stream_3d(horn, pos, 0.0, BUS_SFX, str((EXTRA_PINS["car_horn"] as Array)[0]))


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
		_play_stream_3d(stream, pos, 0.0, bus, ev)
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
	var ev: String = ""
	if CUE_PINS.has(key):
		ev = str((CUE_PINS[key] as Array)[0])
	if pos is Vector3:
		_play_stream_3d(stream, pos, 0.0, BUS_SFX, ev)
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
		if CUE_PINS.has(cue):
			_apply_authored_attenuation(p3, str((CUE_PINS[cue] as Array)[0]))
		else:
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


## T03: [param event_name] switches the player from the legacy 60 m
## inverse-distance model to the authored radius/curve (RE-M-02) and enables
## the occlusion probe (RE-M-03). Empty = legacy behaviour, unchanged.
func _play_stream_3d(stream: AudioStream, pos: Vector3, volume_db: float, bus: String, event_name: String = "") -> void:
	if stream == null or _shutdown:
		return
	_steal_voice_if_full("3d")
	if AudioServer.get_bus_index(bus) == -1:
		bus = "Master"
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.position = pos
	player.bus = bus
	if event_name.is_empty():
		player.max_distance = MAX_DISTANCE_M
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.volume_db = volume_db
	else:
		_apply_authored_attenuation(player, event_name)
		var occ_db: float = occlusion_gain_db(pos)
		player.volume_db = volume_db + occ_db
		if occ_db < 0.0:
			player.attenuation_filter_cutoff_hz = occlusion_cutoff_hz()
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
