extends Node3D
## Authored one-way door ward / green arcane lock (BP_OneWayBarrier_C).
##
## The shipped `BP_OneWayBarrier` (extracted/json/Gameplay/Interactables/Doors/
## BP_OneWayBarrier.json) is a `Plane` mesh with `MI_DoorWard_OneSided_Green`
## on its inside face, a second (purple) plane on the outside face, and a
## BlockerBox. It is *not* a level actor: Kismet spawns it when the foyer
## beam trip fires, which is why no `BP_OneWayBarrier` placement exists in
## `game/data/generated/levels/**`.
##
## Authored values carried here:
##   * plane  — /Engine/BasicShapes/Plane, relative scale (2.6, 3.4, 1.0),
##              relative location Z = 168 cm, yaw 90 / roll 90.
##   * colour — MI_DoorWard_OneSided_Green tint (0.1334, 1.0, 0.0, 1.0).
##   * mask   — T_DoorWard_Mask.png (arch) is NOT bound: it is a 2048 px
##              uncapped texture and a new reference fails the fail-closed
##              texture-cap gate; the shader uses a soft rectangular frame.
##              The glyph (T_DoorWard_Glyph_Hand.png) and lines
##              (T_DoorWard_Lines.png; opaque black/white so luminance is the
##              mask) are bound.
##   * blocker — BoxExtent (4, 128, 168) cm = 0.08 x 2.56 x 3.36 m box.
## Placement on the `Basement Stairs` doorway is APPROX_PLACEMENT: the Kismet
## spawn transform is not in the dump. The port anchors it on the measured
## east-wall door cluster (the authored `SM_InteriorSign_WealthyA` plaque at
## x 30.72 / z -45.79, `SM_FixtureWallC` sconce and `SM_LightSwitch_Main`), just
## south of the 4 m ward archway, facing west. The exact authored spawn point is
## HARD_LIMIT (HL-3, Kismet).
##
## Behaviour contract:
##   * starts hidden and non-solid; `activate_from()` seals it (the beam's
##     existing action-target call),
##   * `shatter()` opens it, emits `shattered`, plays the authored
##     `Play_Obj_WardZone_Ended` cue (`ward_end`),
##   * contact shatter: the player pressing into the active barrier for
##     IMPACT_DWELL_SECONDS breaks it. The shipped trigger is Kismet and not
##     recoverable, so the dwell is a PORT_DECISION, labelled HL-3.

signal sealed(source: Node)
signal shattered(source: Node)

const VINE_SHADER: Shader = preload("res://src/core/tat_vine_lock.gdshader")
const GLYPH_TEX: String = "res://assets/ue/Raw/Art/Effects/DoorWard/T_DoorWard_Glyph_Hand.png"
const LINES_TEX: String = "res://assets/ue/Raw/Art/Effects/DoorWard/T_DoorWard_Lines.png"

## Authored BP_OneWayBarrier values (UE cm -> m).
const PLANE_WIDTH_M: float = 2.6
const PLANE_HEIGHT_M: float = 3.4
const PLANE_CENTRE_Y_M: float = 1.68
## Authored BlockerBox BoxExtent (4, 128, 168) cm -> full (0.08, 2.56, 3.36).
## Local axes: X = plane width, Y = height, Z = plane normal (thin).
const BLOCKER_SIZE_M: Vector3 = Vector3(2.56, 3.36, 0.16)
const BLOCKER_CENTRE_Y_M: float = 1.68
## Authored MI_DoorWard_OneSided_Green Color vector (sRGB 0-1).
const VINE_COLOR: Color = Color(0.1334, 1.0, 0.0, 1.0)
## PORT_DECISION (HL-3): contact dwell for the unrecoverable Kismet shatter.
const IMPACT_DWELL_SECONDS: float = 0.35
const WARD_BLOCKER_LAYER: int = 16
const PLAYER_LAYER: int = 2

var active: bool = false
var impact_seconds: float = 0.0
var player: Node3D = null
var device_id: String = ""
var trigger_source: Node = null

var _visual: MeshInstance3D = null
var _blocker: StaticBody3D = null
var _material: ShaderMaterial = null
var _built: bool = false


func _ready() -> void:
	add_to_group("vine_lock")
	_build()


func configure(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(PLANE_WIDTH_M, PLANE_HEIGHT_M)
	_material = ShaderMaterial.new()
	_material.shader = VINE_SHADER
	_material.set_shader_parameter("vine_color", VINE_COLOR)
	var glyph: Texture2D = load(GLYPH_TEX) as Texture2D
	var lines: Texture2D = load(LINES_TEX) as Texture2D
	if glyph != null:
		_material.set_shader_parameter("glyph_tex", glyph)
	if lines != null:
		_material.set_shader_parameter("lines_tex", lines)
	plane.material = _material
	_visual = MeshInstance3D.new()
	_visual.name = "VinePlane"
	_visual.mesh = plane
	_visual.material_override = _material
	_visual.position = Vector3(0.0, PLANE_CENTRE_Y_M, 0.0)
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.visible = false
	add_child(_visual)

	# Authored BlockerBox (4 x 128 x 168 cm half extents). The barrier's thin
	# axis is local Z (the plane normal), width local X, height local Y.
	_blocker = StaticBody3D.new()
	_blocker.name = "VineBlocker"
	_blocker.collision_layer = 0
	_blocker.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "VineBox"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = BLOCKER_SIZE_M
	shape.shape = box
	shape.position = Vector3(0.0, BLOCKER_CENTRE_Y_M, 0.0)
	_blocker.add_child(shape)
	add_child(_blocker)


func set_player(p: Node3D) -> void:
	player = p


func activate_from(source: Node = null) -> void:
	trigger_source = source
	activate()


func activate() -> void:
	if active:
		return
	active = true
	impact_seconds = 0.0
	if _visual != null:
		_visual.visible = true
	if _blocker != null:
		_blocker.collision_layer = WARD_BLOCKER_LAYER
	sealed.emit(self)


## Public shatter seam (mission lockdown / probe). Idempotent.
func shatter(source: Node = null) -> void:
	if not active:
		return
	active = false
	impact_seconds = 0.0
	if _visual != null:
		_visual.visible = false
	if _blocker != null:
		_blocker.collision_layer = 0
	if AudioManager != null and AudioManager.has_method("play_cue"):
		# Authored Play_Obj_WardZone_Ended: the ward-zone barrier's own end cue.
		AudioManager.call("play_cue", "ward_end", global_position)
	shattered.emit(self if source == null else source)


func tick(delta: float) -> void:
	if not active:
		return
	var target: Node3D = _resolve_player()
	if target == null:
		impact_seconds = 0.0
		return
	if not _player_touching(target):
		impact_seconds = 0.0
		return
	impact_seconds += delta
	if impact_seconds + 0.000001 >= IMPACT_DWELL_SECONDS:
		shatter(self)


## The vine lock is mission-owned (not a device-layer record), so it runs its
## own contact tick while sealed. No per-frame work when hidden/inactive.
func _physics_process(delta: float) -> void:
	if active:
		tick(delta)


func is_sealed() -> bool:
	return active


func _player_touching(target: Node3D) -> bool:
	if not is_inside_tree():
		return false
	# The barrier's own 0.16 m box stops the player capsule, so "within 1.0 m of
	# the plane centre" is contact for the 0.4 m capsule plus the stand-off.
	var body: PackedVector3Array = PackedVector3Array()
	var geo: GDScript = load("res://src/devices/device_geometry.gd") as GDScript
	if geo != null:
		body = geo.call("body_segment", target) as PackedVector3Array
	if body.size() < 2:
		return false
	var mid: Vector3 = (body[0] + body[1]) * 0.5
	var to_plane: Vector3 = global_position + Vector3(0.0, PLANE_CENTRE_Y_M, 0.0) - mid
	return to_plane.length() <= 1.0


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
