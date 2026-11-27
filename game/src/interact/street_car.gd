extends Area3D
## KF15/KF16 vintage-car interaction: `[F] INTERACT` fires the authored car
## alarm — the double-honk SFX and the flashing headlights on the wet cobbles.
##
## Authored source (extracted/json/Art/Environment/Vehicles/Land/Interactable/
## BP_Automobile_AlarmBase.json, CDO + timelines + curves):
##   TurnOnPrompt      "Interact"  (ST_Interactable_Props.PromptInteract)
##   Horn SFX          Play_Obj_Vehicle_Car_Horn_OneOff
##                     (MinimumDuration 1.2772 s / MaximumDuration 1.7245 s)
##   AlarmDuration     10.0 s
##   AlarmTimeline     2.0 s loop; AudioEvent key at 0.09 s
##   CurveFloat_2      EmissiveMultiply: 0 @ 0.0, 1 @ 0.2..1.0, 0 @ 1.1
##   LightIntensity    50.0 (authored lumens); light colour FFD7A6
##   StimTag           AI.Stim.Hearing.CarAlarm (hearing.json MaxRange 50 m)
##
## No timing or level is invented here: the 10 s window, the 2 s loop, the
## flash key times/values and the 50 lm flash are the authored values. The
## authored UE float curve is cubic; this port samples its authored keys
## linearly between them (APPROX_CURVE, visual only). The headlight spots are
## the port's existing authored-placement KF16 beams; the flash is an additive
## 50 lm on top of them, matching the alarm's LightIntensity component.

const LevelLoaderScript := preload("res://src/core/level_loader.gd")

const CAR_HORN_EVENT: String = "Play_Obj_Vehicle_Car_Horn_OneOff"
const ALARM_DURATION_S: float = 10.0
const ALARM_LOOP_S: float = 2.0
const FLASH_LIGHT_LUMENS: float = 50.0
const FLASH_LIGHT_COLOR: Color = Color(1.0, 0.843, 0.651)  # authored FFD7A6
const LENS_EMISSION_AUTHORED: float = 2.0
const LENS_EMISSION_COLOR: Color = Color(1.0, 0.6186, 0.2552)
const CAR_ALARM_STIM_TAG: String = "AI.Stim.Hearing.CarAlarm"
const CAR_ALARM_STIM_RANGE_M: float = 50.0
## Authored CurveFloat_2 keys, sampled in authored order (seconds, multiplier).
const FLASH_KEYS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(0.2, 1.0),
	Vector2(1.0, 1.0),
	Vector2(1.1, 0.0),
]

signal car_honked

var lens_mesh: MeshInstance3D = null
var headlight_spots: Array[SpotLight3D] = []
var _base_energies: Array[float] = []
var _lens_materials: Array[BaseMaterial3D] = []
var _lens_shader_materials: Array[ShaderMaterial] = []
var _flash_energy: float = 0.0
var _alarm_elapsed: float = 0.0
var _alarm_active: bool = false
var _honk_count: int = 0
var _last_flash: float = 0.0


## Must be called before add_child. The mission controller passes the KF16 lens
## node it already overrode and the two authored headlight spots.
func setup(p_lens: MeshInstance3D, p_spots: Array[SpotLight3D]) -> void:
	lens_mesh = p_lens
	headlight_spots = p_spots
	_flash_energy = LevelLoaderScript.light_energy_for_intensity(FLASH_LIGHT_LUMENS)
	_base_energies.clear()
	for spot: SpotLight3D in headlight_spots:
		_base_energies.append(spot.light_energy)
	if lens_mesh != null and lens_mesh.mesh != null:
		for s: int in range(lens_mesh.mesh.get_surface_count()):
			# Only the authored glass lens surface is emissive; the housing and
			# trim surfaces must not glow with the alarm.
			if not lens_mesh.mesh.surface_get_name(s).to_lower().contains("glass"):
				continue
			var mat: Material = lens_mesh.get_active_material(s)
			if mat is StandardMaterial3D:
				_lens_materials.append(mat as BaseMaterial3D)
			elif mat is ShaderMaterial:
				_lens_shader_materials.append(mat as ShaderMaterial)
	# Authored alarm starts dark; the flash multiplier drives the lamps.
	_set_lens_emission(0.0)
	set_meta("headlight_count", headlight_spots.size())
	set_meta("flash_energy", _flash_energy)
	set_meta("horn_event", CAR_HORN_EVENT)
	set_meta("alarm_duration_s", ALARM_DURATION_S)


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("street_car")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	shape.shape = sphere
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)
	set_process(false)


func get_interact_prompt() -> String:
	return InputGlyphs.prompt("interact", "INTERACT")


## The car body is 4.6 m long and 1.6 m tall above its root; aim at the cabin
## side so a player standing on the cobbles can reach it (1.75 m authored reach).
func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.4


func interact(_actor: Node) -> void:
	if _alarm_active:
		return
	_alarm_active = true
	_alarm_elapsed = 0.0
	_honk_count += 1
	set_meta("honk_count", _honk_count)
	set_meta("last_horn_event", CAR_HORN_EVENT)
	var horn_played: bool = false
	if AudioManager != null and AudioManager.has_method("play_car_horn"):
		horn_played = AudioManager.play_car_horn(global_position)
	set_meta("horn_played", horn_played)
	# Authored StimTag on BP_Automobile_AlarmBase; NoiseBus maps the port tag to
	# the authored AI.Stim.Hearing.CarAlarm row (50 m, Long investigation).
	NoiseBus.emit_noise(global_position, CAR_ALARM_STIM_RANGE_M, self, "car_alarm")
	_apply_flash(flash_value_at(0.0))
	set_process(true)
	car_honked.emit()


## Public for the probe and future UI: authored key sampling in the 2 s loop.
func flash_value_at(t: float) -> float:
	var phase: float = fmod(maxf(t, 0.0), ALARM_LOOP_S)
	if phase <= FLASH_KEYS[0].x:
		return FLASH_KEYS[0].y
	for i: int in range(1, FLASH_KEYS.size()):
		var a: Vector2 = FLASH_KEYS[i - 1]
		var b: Vector2 = FLASH_KEYS[i]
		if phase <= b.x:
			var span: float = b.x - a.x
			if span <= 0.0:
				return b.y
			var f: float = (phase - a.x) / span
			return lerpf(a.y, b.y, f)
	return 0.0


func is_alarm_active() -> bool:
	return _alarm_active


func get_honk_count() -> int:
	return _honk_count


func get_flash_energy() -> float:
	return _flash_energy


func get_last_flash() -> float:
	return _last_flash


func get_headlight_count() -> int:
	return headlight_spots.size()


func get_headlight_energy(index: int) -> float:
	if index < 0 or index >= headlight_spots.size():
		return -1.0
	return headlight_spots[index].light_energy


func get_base_headlight_energy(index: int) -> float:
	if index < 0 or index >= _base_energies.size():
		return -1.0
	return _base_energies[index]


func get_lens_emission_energy() -> float:
	if lens_mesh == null or lens_mesh.mesh == null:
		return -1.0
	for s: int in range(lens_mesh.mesh.get_surface_count()):
		if not lens_mesh.mesh.surface_get_name(s).to_lower().contains("glass"):
			continue
		var mat: Material = lens_mesh.get_active_material(s)
		if mat is StandardMaterial3D:
			var smat: StandardMaterial3D = mat as StandardMaterial3D
			if smat.emission_enabled:
				return smat.emission_energy_multiplier
		elif mat is ShaderMaterial:
			var shmat: ShaderMaterial = mat as ShaderMaterial
			if shmat.get_shader_parameter("emission_energy") != null:
				return float(shmat.get_shader_parameter("emission_energy"))
	return 0.0


func stop_alarm() -> void:
	_alarm_active = false
	_alarm_elapsed = 0.0
	set_process(false)
	_apply_flash(0.0)


func _process(delta: float) -> void:
	if not _alarm_active:
		return
	_alarm_elapsed += delta
	if _alarm_elapsed >= ALARM_DURATION_S:
		stop_alarm()
		return
	_apply_flash(flash_value_at(_alarm_elapsed))


func _apply_flash(value: float) -> void:
	_last_flash = clampf(value, 0.0, 1.0)
	for i: int in range(headlight_spots.size()):
		var spot: SpotLight3D = headlight_spots[i]
		var base: float = _base_energies[i] if i < _base_energies.size() else spot.light_energy
		spot.light_energy = base + _flash_energy * _last_flash
	_set_lens_emission(LENS_EMISSION_AUTHORED * _last_flash)


func _set_lens_emission(energy: float) -> void:
	for mat: BaseMaterial3D in _lens_materials:
		if mat is StandardMaterial3D:
			var smat: StandardMaterial3D = mat as StandardMaterial3D
			smat.emission_enabled = true
			smat.emission = LENS_EMISSION_COLOR
			smat.emission_energy_multiplier = energy
	for shmat: ShaderMaterial in _lens_shader_materials:
		shmat.set_shader_parameter("emission_color", Vector3(LENS_EMISSION_COLOR.r, LENS_EMISSION_COLOR.g, LENS_EMISSION_COLOR.b))
		shmat.set_shader_parameter("emission_energy", energy)
