extends Node
## Spatial SFX player mirroring NoiseBus stimuli as 3D positional audio.
## Preloads fallback PCM cues from res://assets/ue/audio/ and spawns a
## one-shot AudioStreamPlayer3D per event, freed when finished.

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

var _sfx: Dictionary = {}
var _active_voices: int = 0


func _ready() -> void:
	_sfx["footstep"] = FOOTSTEP_SFX
	_sfx["blackjack"] = BLACKJACK_SFX
	_sfx["lockpick"] = LOCKPICK_SFX
	_sfx["grapple"] = GRAPPLE_SFX
	_sfx["smoke"] = SMOKE_SFX
	_sfx["fairy"] = FAIRY_SFX
	_sfx["alert"] = ALERT_SFX
	_sfx["loot"] = LOOT_SFX
	_sfx["door"] = DOOR_SFX
	NoiseBus.noise_emitted.connect(_on_noise_emitted)


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
	if _active_voices >= MAX_VOICES:
		return
	if not _sfx.has(key):
		return
	var stream: AudioStream = _sfx[key] as AudioStream
	if stream == null:
		return
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.stream = stream
	player.position = pos
	player.volume_db = volume_db
	player.max_distance = MAX_DISTANCE_M
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player)
	_active_voices += 1
	player.finished.connect(_on_player_finished.bind(player))
	player.play()


func _on_player_finished(player: AudioStreamPlayer3D) -> void:
	_active_voices = maxi(0, _active_voices - 1)
	player.queue_free()


func _resolve_tag(tag: String) -> String:
	var normalized: String = tag.to_lower().strip_edges()
	if _sfx.has(normalized):
		return normalized
	match normalized:
		"takedown", "slithersap", "ko", "melee":
			return "blackjack"
		"wire", "rope":
			return "grapple"
		"moth", "chime", "vision":
			return "fairy"
		"spotted", "alarm", "whistle", "hunt":
			return "alert"
		"pickup", "coin", "steal":
			return "loot"
		"gate":
			return "door"
		"generic", "step", "walk":
			return "footstep"
	return ""
