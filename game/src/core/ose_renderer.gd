extends Node3D
class_name OSERenderer
## C1 OSE.NPR / OSE.SNN screen-space renderer.
##
## A camera-child quad at the near plane samples the screen, depth and
## normal-roughness buffers. It is a camera effect, not a scene mesh: invisible
## by default, no shadow, no GI, no collision.
##
## Authored defaults (MPC_Painterly): HSV 0.65, Depth 1.25, Hue 0.55,
## Effect Intensity 0.0 (off). The post-process edge/ink implementation is an
## approximation of the shipped material-layer painterly path (documented in
## tat_npr.gdshader).

const POST_SHADER := preload("res://src/core/tat_npr.gdshader")
const QUAD_Z := -0.09
const QUAD_MARGIN := 1.35

var _camera: Camera3D
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _npr: bool = false
var _snn: bool = false
var _snn_effect: float = 0.0


static func attach(camera: Camera3D) -> OSERenderer:
	var renderer := OSERenderer.new()
	renderer.name = "OSERenderer"
	camera.add_child(renderer)
	renderer._camera = camera
	renderer._build()
	return renderer


func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = POST_SHADER
	_mat.set_shader_parameter("npr_enabled", false)
	_mat.set_shader_parameter("snn_enabled", false)
	_mat.set_shader_parameter("snn_effect", 0.0)
	_quad = MeshInstance3D.new()
	_quad.name = "PostQuad"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_quad.mesh = quad
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_quad.extra_cull_margin = 16384.0
	_quad.position = Vector3(0.0, 0.0, QUAD_Z)
	_quad.visible = false
	add_child(_quad)
	_resize()
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.size_changed.connect(_resize)


func _resize() -> void:
	if _camera == null or _quad == null or _quad.mesh == null:
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var size: Vector2 = vp.get_visible_rect().size
	if size.y <= 0.0:
		return
	var aspect: float = size.x / size.y
	var half_h: float = tan(deg_to_rad(_camera.fov) * 0.5) * absf(QUAD_Z)
	var h: float = half_h * 2.0 * QUAD_MARGIN
	var w: float = h * aspect * QUAD_MARGIN
	var quad := _quad.mesh as QuadMesh
	quad.size = Vector2(w, h)


func set_npr(enabled: bool) -> void:
	_npr = enabled
	if _mat != null:
		_mat.set_shader_parameter("npr_enabled", _npr)
	_refresh_visible()


func set_snn(enabled: bool, intensity: float = 0.65) -> void:
	_snn = enabled
	_snn_effect = clampf(intensity, 0.0, 1.0) if enabled else 0.0
	if _mat != null:
		_mat.set_shader_parameter("snn_enabled", _snn)
		_mat.set_shader_parameter("snn_effect", _snn_effect)
	_refresh_visible()


func set_snn_effect(intensity: float) -> void:
	_snn_effect = clampf(intensity, 0.0, 1.0)
	if _mat != null:
		_mat.set_shader_parameter("snn_effect", _snn_effect)


func set_npr_strength(strength: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("ink_strength", clampf(strength, 0.0, 2.0))


func _refresh_visible() -> void:
	if _quad != null:
		_quad.visible = _npr or _snn


func is_npr_active() -> bool:
	return _npr


func is_snn_active() -> bool:
	return _snn


func get_post_material() -> ShaderMaterial:
	return _mat
