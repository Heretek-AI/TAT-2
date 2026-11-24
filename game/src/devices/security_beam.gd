extends Area3D
## Authored security light beam (BP_Detector_LightBeam_C).
##
## Geometry comes from devices_runtime.json: BeamLength is the authored cooked
## centimetre clear span, emitted as a capsule along the detector's authored
## actor-local +Z with the authored 0.10 m radius. (The static SM_LightBeam
## card's record basis col0 is that same actor-local +Z direction, 90 deg from
## the actor-local +X used by the old code, so both now point the same way.)
## Trigger/reset timings and the radius come from
## family_defaults.light_beam.metric; per-instance BaseRotation is applied
## to the component pivot, never to the actor transform.
##
## Visual ownership: the level loader now spawns the authored additive
## SM_LightBeam card per detector (group "lightbeam_cards"). When the device
## layer can pair one of those cards with this detector it calls
## adopt_beam_card(): the card becomes the single visual and follows power
## state; the cheap stand-in cylinder is only used when no authored card
## exists (other maps/tests).
##
## The beam is repeatable: a continuous intrusion re-fires after
## trigger_seconds + reset_seconds. The authoritative test is the distance
## between the beam axis and the thief's authored body segment (feet -> 1.78 m
## standing / 1.0 m crouched), so a 7.748 m beam rejects a body at 7.9 m while
## still crossing a standing body at 1.75 m. The Area3D capsule is kept for
## proximity/wake-up parity and ignores every body that is not the player.

signal beam_triggered(source: Node)
signal power_state_changed(on: bool)

const Geometry := preload("res://src/devices/device_geometry.gd")
const BEAM_SHADER: Shader = preload("res://src/core/tat_beam.gdshader")

const CUE_TRIP: String = "lightbeam_trip"
const VISUAL_RADIUS_M: float = 0.012

var device_id: String = ""
var family: String = "light_beam"
var params: Dictionary = {}
var beam_length_m: float = 10.0
var beam_radius_m: float = 0.1
var trigger_seconds: float = 0.5
var reset_seconds: float = 0.2
var base_rotation_deg: Vector2 = Vector2.ZERO

var player: Node3D = null
var action_targets: Array = []
var actions_fired: int = 0
var awake: bool = true
var alive: bool = true
var power_source: Node = null
var power_required: bool = true
var _powered: bool = true

var _pivot: Node3D = null
var _shape_node: CollisionShape3D = null
var _visual: MeshInstance3D = null
## Authored loader card adopted as the single visual (null when absent).
var _card: Node3D = null
var _card_base_basis: Basis = Basis.IDENTITY
var _dwell: float = 0.0
var _cooldown: float = 0.0
var _inside: bool = false
var _built: bool = false


func configure(rec: Dictionary, family_defaults: Dictionary, difficulty_value: int = -1) -> void:
	device_id = str(rec.get("id", ""))
	family = str(rec.get("family", "light_beam"))
	params = rec.get("params", {}) as Dictionary if rec.get("params", {}) is Dictionary else {}
	var defaults: Dictionary = family_defaults.get(family, {}) as Dictionary
	var metric: Dictionary = defaults.get("metric", {}) as Dictionary
	beam_radius_m = float(metric.get("radius_m", 0.1))
	trigger_seconds = float(metric.get("trigger_seconds", 0.5))
	reset_seconds = float(metric.get("reset_seconds", 0.2))
	if params.has("BeamLength"):
		# Authored UE centimetres.
		beam_length_m = maxf(float(params.get("BeamLength", 0.0)) * Geometry.CM_TO_M, beam_radius_m * 2.0)
	else:
		# family_defaults.metric.beam_length_default_m is already metres.
		beam_length_m = maxf(float(metric.get("beam_length_default_m", 10.0)), beam_radius_m * 2.0)
	var br_v: Variant = params.get("BaseRotation", null)
	if br_v is Dictionary:
		var br: Dictionary = br_v as Dictionary
		base_rotation_deg = Vector2(float(br.get("X", 0.0)), float(br.get("Y", 0.0)))
	var pv: Variant = rec.get("power", {})
	var power: Dictionary = pv as Dictionary if pv is Dictionary else {}
	var req_v: Variant = power.get("require", null)
	power_required = true if req_v == null else bool(req_v)
	if _built:
		_apply_geometry()
	else:
		_build()


func _ready() -> void:
	add_to_group("devices")
	add_to_group("device_detector")
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	collision_layer = 0
	collision_mask = 2 # player only; non-player bodies are ignored by design
	monitoring = awake
	monitorable = false
	_pivot = Node3D.new()
	_pivot.name = "BeamPivot"
	_pivot.basis = Basis(Vector3.UP, deg_to_rad(base_rotation_deg.y)) * Basis(Vector3.BACK, deg_to_rad(base_rotation_deg.x))
	add_child(_pivot)

	_shape_node = CollisionShape3D.new()
	_shape_node.name = "BeamShape"
	var cap := CapsuleShape3D.new()
	cap.radius = beam_radius_m
	cap.height = maxf(beam_length_m, beam_radius_m * 2.0)
	_shape_node.shape = cap
	_shape_node.position = Vector3(0.0, 0.0, beam_length_m * 0.5)
	_shape_node.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_pivot.add_child(_shape_node)

	# Cheap additive stand-in for the authored UE beam card. The cooked
	# material graph was not decompiled; tat_beam.gdshader is the documented
	# stand-in already used by the level loader for security beams.
	var cyl := CylinderMesh.new()
	cyl.height = beam_length_m
	cyl.top_radius = VISUAL_RADIUS_M
	cyl.bottom_radius = VISUAL_RADIUS_M
	cyl.radial_segments = 6
	cyl.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	mat.set_shader_parameter("beam_color", Color(1.0, 0.82, 0.62, 0.55))
	mat.set_shader_parameter("energy", 2.0)
	_visual = MeshInstance3D.new()
	_visual.name = "BeamVisual"
	_visual.mesh = cyl
	_visual.material_override = mat
	_visual.position = Vector3(0.0, 0.0, beam_length_m * 0.5)
	_visual.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(_visual)
	_apply_geometry()


func _apply_geometry() -> void:
	if _pivot == null or _shape_node == null:
		return
	_pivot.basis = Basis(Vector3.UP, deg_to_rad(base_rotation_deg.y)) * Basis(Vector3.BACK, deg_to_rad(base_rotation_deg.x))
	var cap: CapsuleShape3D = _shape_node.shape as CapsuleShape3D
	if cap != null:
		cap.radius = beam_radius_m
		cap.height = maxf(beam_length_m, beam_radius_m * 2.0)
	_shape_node.position = Vector3(0.0, 0.0, beam_length_m * 0.5)
	_shape_node.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	if _visual != null and _visual.mesh is CylinderMesh:
		var cyl: CylinderMesh = _visual.mesh as CylinderMesh
		cyl.height = beam_length_m
		_visual.position = Vector3(0.0, 0.0, beam_length_m * 0.5)
		_visual.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_sync_card()
	_update_visual()


## Adopt an authored loader SM_LightBeam card as this detector's only visual.
## The card record is authored unrotated for BaseRotation, so apply the same
## pivot rotation the beam uses: card_world = A*pivot * A^-1 * card_basis.
func adopt_beam_card(card: Node3D) -> void:
	if card == null or not is_instance_valid(card):
		return
	if _card != null and is_instance_valid(_card) and _card != card:
		release_beam_card()
	_card = card
	_card_base_basis = card.global_transform.basis
	_sync_card()
	_update_visual()


## Drop the adopted card and restore its authored transform/visibility.
func release_beam_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.global_transform = Transform3D(_card_base_basis, _card.global_transform.origin)
		_card.visible = true
	_card = null
	_card_base_basis = Basis.IDENTITY
	_update_visual()


func has_beam_card() -> bool:
	return _card != null and is_instance_valid(_card)


func _sync_card() -> void:
	if _card == null or not is_instance_valid(_card) or _pivot == null:
		return
	if not _card.is_inside_tree() or not is_inside_tree():
		return
	var actor_basis: Basis = global_transform.basis
	var actor_inv: Basis = actor_basis.inverse()
	var rotated: Basis = _pivot.global_transform.basis * actor_inv * _card_base_basis
	_card.global_transform = Transform3D(rotated, _card.global_transform.origin)


## Exactly one visual: the authored card when adopted, else the cheap stand-in
## cylinder. Both follow power; only the stand-in is distance-culled with the
## device (the authored card is level geometry and stays visible at range).
func _update_visual() -> void:
	var dark: bool = (not alive) or (power_required and not _powered)
	if _visual != null:
		_visual.visible = awake and not dark and not has_beam_card()
	if _card != null and is_instance_valid(_card):
		_card.visible = not dark


func set_player(p: Node3D) -> void:
	player = p


func set_action_targets(targets: Array) -> void:
	action_targets = targets


func set_power_source(src: Node) -> void:
	power_source = src
	if src != null and src.has_signal("powered"):
		if not src.is_connected("powered", Callable(self, "_on_power_changed")):
			src.connect("powered", Callable(self, "_on_power_changed"))
		_powered = bool(src.call("is_powered")) if src.has_method("is_powered") else true
	else:
		_powered = true
	_update_visual()


func _on_power_changed(on: bool) -> void:
	_powered = on
	power_state_changed.emit(on)
	if power_required and not on:
		_dwell = 0.0
		_inside = false
	_update_visual()


func can_trigger() -> bool:
	return alive and awake and (not power_required or _powered)


func set_awake(value: bool) -> void:
	awake = value
	monitoring = value
	_update_visual()
	if not value:
		_dwell = 0.0
		_inside = false


func tick(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if not can_trigger():
		_dwell = 0.0
		_inside = false
		return
	var target: Node3D = _resolve_player()
	if target == null:
		_dwell = 0.0
		_inside = false
		return
	_inside = _player_in_beam(target)
	if not _inside:
		_dwell = 0.0
		return
	if _cooldown > 0.0:
		return
	_dwell += delta
	if _dwell + 0.000001 >= maxf(trigger_seconds, 0.0):
		_dwell = 0.0
		_cooldown = reset_seconds
		_fire()


func is_player_inside() -> bool:
	return _inside


func _fire() -> void:
	actions_fired += 1
	beam_triggered.emit(self)
	for target_v: Variant in action_targets:
		if not (target_v is Node) or not is_instance_valid(target_v as Node):
			continue
		var target: Node = target_v as Node
		if target.has_method("activate_from"):
			target.call("activate_from", self)
		elif target.has_method("trigger_from"):
			target.call("trigger_from", self)
		elif target.has_method("activate"):
			target.call("activate")
	if AudioManager != null and AudioManager.has_method("play_cue"):
		AudioManager.call("play_cue", CUE_TRIP, global_position)


func _player_in_beam(target: Node3D) -> bool:
	if _pivot == null:
		return false
	var origin: Vector3 = _pivot.global_position
	# Authored beam axis: actor-local +Z (record col0), not actor-local +X.
	var dir: Vector3 = _pivot.global_transform.basis.z.normalized()
	if dir.length_squared() < 0.5:
		dir = Vector3.FORWARD
	var end: Vector3 = origin + dir * beam_length_m
	var body: PackedVector3Array = Geometry.body_segment(target)
	if body.size() < 2:
		return false
	return Geometry.segment_segment_distance(origin, end, body[0], body[1]) <= beam_radius_m


func _resolve_player() -> Node3D:
	if player != null and is_instance_valid(player):
		return player
	if not is_inside_tree():
		return null
	var found: Node = get_tree().get_first_node_in_group("player")
	if found is Node3D:
		player = found as Node3D
		return player
	return null
