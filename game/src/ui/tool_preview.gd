class_name ToolPreviewStage
extends Node3D
## Shared live 3D tool-preview stage for the Wardrobe (KF03/KF04 tooltip card)
## and the Ledger Black Market preview (KF08). One authored gear-mesh map and
## one warm tool-card world, so both panels show the same asset and lighting.
##
## Usage:
##   var stage := ToolPreviewStage.new()
##   viewport.add_child(stage)
##   stage.setup(viewport)          # env + lights + backdrop + holder + camera
##   stage.show_mesh_path(path)     # loads, binds authored PBR, frames camera
##   stage.clear()
## The preview is decorative: no collision, no gameplay registration.

const LevelLoaderScript: GDScript = preload("res://src/core/level_loader.gd")

## Catalog save id -> authored gear mesh (all verified on disk). Every tool the
## Black Market sells has a 3D preview; blackjack is the built-in.
const TOOL_MESHES: Dictionary = {
	"zipwire": "res://assets/ue/Content/Art/Gameplay/Gear/Zipwire/SM_Zipwire.glb",
	"smoke_bomb": "res://assets/ue/Content/Art/Gameplay/Gear/SmokeBomb/SK_SmokeBomb.glb",
	"pickpocket_fairy": "res://assets/ue/Content/Art/Gameplay/Gear/PickpocketFairy/SK_PickpocketFairy.glb",
	"insult_fairy": "res://assets/ue/Content/Art/Gameplay/Gear/InsultFairy/SK_InsultFairy.glb",
	"slither_sap": "res://assets/ue/Content/Art/Gameplay/Gear/Slithersap/SK_SlimeBomb.glb",
	"glamour": "res://assets/ue/Content/Art/Gameplay/Gear/Disguise/SK_DisguiseMask.glb",
	"vistara_diamond": "res://assets/ue/Content/Art/Gameplay/Gear/VistaraDiamond/SM_VistaraDiamond_Gem.glb",
	"blackjack": "res://assets/ue/Content/Art/Gameplay/Gear/BlackJack/SM_Blackjack.glb",
}

## Slow turntable for panels without drag-to-rotate (the Ledger preview).
var auto_rotate: bool = true
var spin_speed: float = 0.55

var holder: Node3D = null
var cam: Camera3D = null
var _loader: Node = null
var _mesh_path: String = ""

static func mesh_path_for(save_id: String) -> String:
	return str(TOOL_MESHES.get(save_id, ""))


## Builds the warm tool-card world inside `viewport` (mirrors the Wardrobe's
## KF03 staging). Call once; `holder` and `cam` are then valid.
func setup(viewport: SubViewport) -> void:
	name = "ToolPreviewStage"
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.075, 0.052, 0.040)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.42, 0.28)
	env.ambient_light_energy = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_bloom = 0.05
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "ToolPreviewEnv"
	world_env.environment = env
	viewport.add_child(world_env)
	_add_box(viewport, Vector3(3.2, 2.2, 0.08), Vector3(0.0, 1.0, -0.8), Color(0.13, 0.078, 0.052), 0.9)
	_add_box(viewport, Vector3(3.2, 0.08, 2.0), Vector3(0.0, -0.05, 0.2), Color(0.145, 0.095, 0.065), 0.86)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "ToolPreviewKey"
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	viewport.add_child(key)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.name = "ToolPreviewFill"
	fill.light_color = Color(1.0, 0.72, 0.45)
	fill.light_energy = 0.8
	fill.position = Vector3(-1.2, 1.4, 1.6)
	viewport.add_child(fill)
	var kicker: OmniLight3D = OmniLight3D.new()
	kicker.name = "ToolPreviewRim"
	kicker.light_color = Color(0.55, 0.70, 1.0)
	kicker.light_energy = 0.55
	kicker.position = Vector3(1.3, 0.9, -0.9)
	viewport.add_child(kicker)
	holder = Node3D.new()
	holder.name = "ToolHolder"
	add_child(holder)
	cam = Camera3D.new()
	cam.name = "ToolPreviewCam"
	cam.position = Vector3(0.0, 0.4, 1.7)
	cam.fov = 38.0
	cam.current = true
	add_child(cam)
	cam.environment = env
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.25, 0.0))


func _process(delta: float) -> void:
	if not auto_rotate or holder == null or not is_visible_in_tree():
		return
	holder.rotate_y(spin_speed * delta)


## Loads a tool mesh and binds the authored PBR slots. Returns false when the
## path is empty, missing or not a PackedScene (the caller shows the icon).
func show_mesh_path(path: String) -> bool:
	clear()
	if path == "" or not ResourceLoader.exists(path):
		return false
	var res: Resource = ResourceLoader.load(path)
	if not (res is PackedScene):
		return false
	var node: Node = (res as PackedScene).instantiate()
	holder.add_child(node)
	_mesh_path = path
	_bind_materials(node, _glb_to_ue_mesh(path))
	call_deferred("frame_camera")
	return true


func show_save_id(save_id: String) -> bool:
	var path: String = mesh_path_for(save_id)
	return show_mesh_path(path)


func clear() -> void:
	_mesh_path = ""
	if holder == null:
		return
	for c: Node in holder.get_children():
		holder.remove_child(c)
		c.queue_free()


## Auto-frames from the composed mesh bounds so small gear (a ring, a mask)
## fills the preview card instead of sitting as a pixel in the corner.
func frame_camera() -> void:
	if cam == null or holder == null:
		return
	if not holder.is_inside_tree() or not cam.is_inside_tree():
		return
	var box: AABB = AABB()
	var have: bool = false
	var inv: Transform3D = holder.global_transform.affine_inverse()
	for node: Node in holder.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		var ab: AABB = xf * mi.get_aabb()
		box = ab if not have else box.merge(ab)
		have = true
	if not have:
		return
	var center: Vector3 = holder.global_transform * box.get_center()
	var max_dim: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	max_dim = maxf(max_dim, 0.15)
	var fov: float = deg_to_rad(cam.fov)
	var dist: float = (max_dim * 0.5) / tan(fov * 0.5) * 1.25
	var pos: Vector3 = center + Vector3(0.0, max_dim * 0.18, dist)
	cam.position = pos
	cam.look_at_from_position(pos, center)


func has_mesh() -> bool:
	return _mesh_path != "" and holder != null and holder.get_child_count() > 0


func _add_box(parent: Node, box_size: Vector3, pos: Vector3, color: Color, roughness: float, metallic: bool = false) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = box_size
	mi.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 1.0 if metallic else 0.0
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _glb_to_ue_mesh(res_path: String) -> String:
	var marker: String = "assets/ue/Content/"
	var idx: int = res_path.find(marker)
	if idx < 0:
		return ""
	var rel: String = res_path.substr(idx + marker.length())
	if rel.ends_with(".glb"):
		rel = rel.substr(0, rel.length() - 4)
	return "/Game/" + rel


func _get_mat_loader() -> Node:
	if _loader == null:
		_loader = LevelLoaderScript.new()
		add_child(_loader)
	return _loader


func _bind_materials(root: Node, ue_mesh_path: String) -> void:
	if root == null or ue_mesh_path == "":
		return
	var loader: Node = _get_mat_loader()
	if loader == null:
		return
	var db: Variant = loader.get("_mesh_mats_db")
	var slots_v: Variant = (db as Dictionary).get(ue_mesh_path, null) if db is Dictionary else null
	if not (slots_v is Array):
		var db_low: Variant = loader.get("_mesh_mats_db_lower")
		slots_v = (db_low as Dictionary).get(ue_mesh_path.to_lower(), null) if db_low is Dictionary else null
	if not (slots_v is Array):
		return
	_bind_meshes(root, loader, slots_v as Array)


func _bind_meshes(node: Node, loader: Node, slots: Array) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			var count: int = mini(mi.mesh.get_surface_count(), slots.size())
			for s: int in range(count):
				var mat_path: String = str(slots[s])
				if mat_path == "":
					continue
				var mat: Material = loader.call("get_material_for_ue", mat_path) as Material
				if mat != null:
					mi.set_surface_override_material(s, mat)
	for child: Node in node.get_children():
		_bind_meshes(child, loader, slots)
