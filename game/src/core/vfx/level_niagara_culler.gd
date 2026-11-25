extends Node3D
## Distance culler and runtime switch for the chunked level-Niagara MultiMeshes
## (T12-VFX, RE-E-14 + RE-E-03).
##
## Before this node existed the loader parented one MultiMeshInstance3D per
## system straight to the map root, so each system's AABB spanned the whole map
## and all 3,308 additive quads stayed in the frustum test from anywhere. The
## loader now splits each system per 32 m chunk and registers every chunk here.
##
## Culling is a pure distance test against the registered chunk centre, shrunk by
## the chunk's bounding radius, with hysteresis so a boundary walk does not
## flicker. It is deliberately *not* a Godot `visibility_range`: that would need
## a real camera per viewport, while this can be exercised headless through
## [method update_for_position] and measured in the probe.
##
## [method set_system_active] is the Blueprint switch counterpart of the authored
## `bAutoActivate`: an event-gated system (turret destroyed, door broken, eye
## alerted, goo pipe opened) is spawned but kept invisible until the owning device
## turns it on. Device wiring is owned by the device layer; this is the API.

const CULL_DISTANCE_M: float = 60.0
const HYSTERESIS_M: float = 10.0
const TICK_S: float = 0.5

var _chunks: Array[Node3D] = []
var _radii: Array[float] = []
var _systems: Array[String] = []
var _system_on: Dictionary = {}
var _origin: Vector3 = Vector3.ZERO
var _have_origin: bool = false
var _elapsed: float = 0.0
var _last_visible: int = -1
var _last_switched: int = 0


## [param system] is the authored system file name (`NS_SecurityTurret_Destruction`);
## empty means "always on" (a system with no activation state to switch).
func add_chunk(node: Node3D, radius: float, system: String = "") -> void:
	if node == null:
		return
	_chunks.append(node)
	_radii.append(maxf(0.0, radius))
	_systems.append(system)


## The Blueprint switch. Returns the number of chunk nodes whose visibility
## changed. Off wins over distance; turning a system back on restores the normal
## distance rule immediately.
func set_system_active(system: String, on: bool) -> int:
	var key: String = system.get_file()
	_system_on[key] = on
	_last_switched = 0
	for i: int in range(_chunks.size()):
		if _systems[i] != key:
			continue
		var node: Node3D = _chunks[i]
		if not is_instance_valid(node):
			continue
		var was: bool = node.visible
		node.visible = on and _in_range(i)
		if node.visible != was:
			_last_switched += 1
	return _last_switched


## Whether [param system] is switched on (default true: authored-on systems).
func is_system_active(system: String) -> bool:
	return bool(_system_on.get(system.get_file(), true))


## Hide every chunk whose bounding sphere is farther than CULL_DISTANCE_M from
## [param origin] and show the rest. Returns {"visible", "hidden", "total"}.
func update_for_position(origin: Vector3) -> Dictionary:
	_origin = origin
	_have_origin = true
	var visible: int = 0
	for i: int in range(_chunks.size()):
		var node: Node3D = _chunks[i]
		if not is_instance_valid(node):
			continue
		node.visible = _in_range(i) and bool(_system_on.get(_systems[i], true))
		if node.visible:
			visible += 1
	_last_visible = visible
	return {"visible": visible, "hidden": _chunks.size() - visible, "total": _chunks.size()}


func stats() -> Dictionary:
	return {"visible": _last_visible, "total": _chunks.size(), "origin": _origin}


func _in_range(i: int) -> bool:
	var node: Node3D = _chunks[i]
	var reach: float = maxf(0.0, node.global_position.distance_to(_origin) - _radii[i])
	var limit: float = CULL_DISTANCE_M + (HYSTERESIS_M if node.visible else 0.0)
	return reach <= limit


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < TICK_S:
		return
	_elapsed = 0.0
	var cam: Camera3D = null
	var vp: Viewport = get_viewport()
	if vp != null:
		cam = vp.get_camera_3d()
	if cam != null:
		update_for_position(cam.global_position)
	elif _have_origin:
		update_for_position(_origin)
