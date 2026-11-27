extends Control
## HUD status icon above the Light Gem (UI5-06, KF28 #6 / KF29 #4).
##
## The reference icon is a white mechanical jaw/bear-trap render with a
## countdown ring. The shipped 3D jaw-trap meshes are extracted
## (`SM_JawTrapBase`, `SM_JawTrapFangsA/B`), so the icon renders those authored
## meshes in a small orthographic SubViewport and draws the ring procedurally.
## No 2D jaw-trap texture exists in the extracted UI set, so the 3D render is
## the authored-art path; the ring is HUD chrome (PORT_DECISION, no authored
## ring atlas recovered).
##
## Headless runs skip the 3D viewport (no render target work); the icon Control,
## ring state and API still exist so probes can assert them.

const JAW_BASE := "res://assets/ue/Content/Art/Gameplay/Gear/JawTrap/SM_JawTrapBase.glb"
const JAW_FANGS_A := "res://assets/ue/Content/Art/Gameplay/Gear/JawTrap/SM_JawTrapFangsA.glb"
const JAW_FANGS_B := "res://assets/ue/Content/Art/Gameplay/Gear/JawTrap/SM_JawTrapFangsB.glb"
const ICON_SIZE: float = 76.0
const VIEW_SIZE: int = 56
const RING_RADIUS: float = 30.0
const RING_WIDTH: float = 3.0

var kind: String = ""
var duration: float = 0.0
var remaining: float = 0.0
var active: bool = false

var _vp_container: SubViewportContainer = null
var _pivot: Node3D = null
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	size = Vector2(ICON_SIZE, ICON_SIZE)
	set_process(false)
	if DisplayServer.get_name() != "headless":
		_build_mesh_icon()


func show_icon(kind_value: String, seconds: float) -> void:
	kind = kind_value
	duration = maxf(seconds, 0.0)
	remaining = duration
	active = true
	visible = true
	_time = 0.0
	set_process(true)
	queue_redraw()


func clear_icon() -> void:
	active = false
	kind = ""
	duration = 0.0
	remaining = 0.0
	visible = false
	set_process(false)
	queue_redraw()


func state() -> Dictionary:
	return {
		"kind": kind,
		"active": active,
		"duration": duration,
		"remaining": remaining,
		"mesh_viewport": _vp_container != null,
		"visible": visible,
	}


func _process(delta: float) -> void:
	_time += delta
	if remaining > 0.0:
		remaining = maxf(0.0, remaining - delta)
		queue_redraw()
	if _pivot != null:
		_pivot.rotation.y = sin(_time * 0.9) * 0.55


func _draw() -> void:
	var centre: Vector2 = Vector2(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
	draw_circle(centre, RING_RADIUS - 2.0, Color(0.02, 0.02, 0.04, 0.55))
	# Countdown ring: full at spawn, empty at zero. When the duration is 0 the
	# ring stays full (state icon, no timer).
	var frac: float = 1.0
	if duration > 0.0:
		frac = clampf(remaining / duration, 0.0, 1.0)
	var start_angle: float = -PI * 0.5
	draw_arc(centre, RING_RADIUS, start_angle, start_angle + TAU * frac, 48, Color(0.92, 0.93, 0.98, 0.95), RING_WIDTH, true)
	draw_arc(centre, RING_RADIUS, start_angle + TAU * frac, start_angle + TAU, 48, Color(0.92, 0.93, 0.98, 0.20), 1.0, true)


func _build_mesh_icon() -> void:
	_vp_container = SubViewportContainer.new()
	_vp_container.name = "JawTrapView"
	_vp_container.position = Vector2(10.0, 10.0)
	_vp_container.size = Vector2(VIEW_SIZE, VIEW_SIZE)
	_vp_container.stretch = true
	_vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vp_container)
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	vp.transparent_bg = true
	# The jaw-trap key/fill lights below must light only the icon. Without an
	# own World3D the SubViewport shares the gameplay world and the 1.6-energy
	# DirectionalLight brightens the whole level (P1 capture: upper_foyer
	# 45.8 -> 71.0, yaw180 39.0 -> 84.4). Every other UI SubViewport already
	# sets this; the status icon was the exception.
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	_vp_container.add_child(vp)
	var cam: Camera3D = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.25
	cam.position = Vector3(0.0, 0.55, 2.2)
	vp.add_child(cam)
	cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38.0, -26.0, 0.0)
	light.light_energy = 1.6
	vp.add_child(light)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(-0.8, 0.6, 1.0)
	fill.light_energy = 0.8
	fill.omni_range = 3.0
	vp.add_child(fill)
	_pivot = Node3D.new()
	vp.add_child(_pivot)
	var white: StandardMaterial3D = StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(0.93, 0.94, 0.98, 1.0)
	var span: float = 1.0
	var meshes: Array[Mesh] = []
	for path: String in [JAW_BASE, JAW_FANGS_A, JAW_FANGS_B]:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		var holder: Node3D = Node3D.new()
		holder.add_child(inst)
		_pivot.add_child(holder)
		for child: Node in holder.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = child as MeshInstance3D
			mi.material_override = white
			var aabb: AABB = mi.get_aabb()
			span = maxf(span, maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)))
	# One authored mesh path per holder keeps the assembly's authored offsets;
	# rescale the whole assembly to fit the icon.
	if span > 0.0001:
		_pivot.scale = Vector3.ONE * (0.95 / span)
