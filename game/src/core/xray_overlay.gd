extends RefCounted
class_name XrayOverlay
## OSEXray overlay (C2). The authored TATXrayComponent materials and draw
## distances are the source of truth:
##   MI_XrayGuard  Color 0.1094/0/0.0044, Fresnel Highlight 5/0/0, 2500 cm
##   MI_XrayLoot   Color 1/0.4514/0,     Fresnel Highlight 1/0.5775/0, 2000 cm
##   MI_XrayClue   Color 0/0.9583/0.0319, Fresnel Highlight 0.0076/1/0.1571, 1500 cm
##   MI_XrayPlayer 0.5677 grey, no max distance
## Traps/turrets/cameras use MI_XrayGuard (1800-2500 cm).
## Applied as material_overlay with depth test disabled: the real PBR pass is
## untouched and the silhouette reads through walls.

const XRAY_SHADER := preload("res://src/core/tat_xray.gdshader")

const CATEGORIES: Dictionary = {
	"guard": {
		"color": Color(0.1094, 0.0, 0.0044, 1.0),
		"highlight": Color(5.0, 0.0, 0.0, 1.0),
		"max_distance": 25.0,
	},
	"loot": {
		"color": Color(1.0, 0.4514, 0.0, 1.0),
		"highlight": Color(1.0, 0.5775, 0.0, 1.0),
		"max_distance": 20.0,
	},
	"clue": {
		"color": Color(0.0, 0.9583, 0.0319, 1.0),
		"highlight": Color(0.0076, 1.0, 0.1571, 1.0),
		"max_distance": 15.0,
	},
	"player": {
		"color": Color(0.5677, 0.5677, 0.5677, 1.0),
		"highlight": Color(0.5677, 0.5677, 0.5677, 1.0),
		"max_distance": 0.0,
	},
}

static var _materials: Dictionary = {}


static func material_for(category: String) -> ShaderMaterial:
	var key: String = category if CATEGORIES.has(category) else "loot"
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var spec: Dictionary = CATEGORIES[key] as Dictionary
	var mat := ShaderMaterial.new()
	mat.shader = XRAY_SHADER
	mat.set_shader_parameter("xray_color", spec["color"])
	mat.set_shader_parameter("xray_highlight", spec["highlight"])
	mat.set_shader_parameter("max_distance", float(spec["max_distance"]))
	mat.set_shader_parameter("fresnel_power", 5.0)
	mat.set_shader_parameter("fresnel_intensity", 1.0)
	mat.set_shader_parameter("base_alpha", 0.58)
	_materials[key] = mat
	return mat


## The reserved component interface: enabled + category.
static func set_xray_highlight(target: Node, enabled: bool, category: String = "") -> void:
	if target == null or not is_instance_valid(target):
		return
	var cat: String = category
	if cat == "":
		cat = str(target.get_meta("xray_category", "loot"))
	var meshes: Array = []
	if target is MeshInstance3D or target is MultiMeshInstance3D or target is GeometryInstance3D:
		meshes.append(target)
	for child: Node in target.find_children("*", "GeometryInstance3D", true, false):
		meshes.append(child)
	for mesh_var: Variant in meshes:
		if not (mesh_var is GeometryInstance3D):
			continue
		var gi: GeometryInstance3D = mesh_var as GeometryInstance3D
		if enabled:
			if gi.has_meta("_xray_on") and bool(gi.get_meta("_xray_on")):
				continue
			gi.set_meta("_xray_prev_overlay", gi.material_overlay)
			gi.set_meta("_xray_on", true)
			gi.material_overlay = material_for(cat)
		else:
			if not gi.has_meta("_xray_on"):
				continue
			gi.material_overlay = gi.get_meta("_xray_prev_overlay", null) as Material
			gi.remove_meta("_xray_on")
			gi.remove_meta("_xray_prev_overlay")


static func clear_static_caches() -> void:
	_materials.clear()


static func category_color(category: String) -> Color:
	var spec: Dictionary = CATEGORIES.get(category, CATEGORIES["loot"]) as Dictionary
	return spec["color"] as Color
