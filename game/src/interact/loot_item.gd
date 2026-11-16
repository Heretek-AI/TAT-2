extends Area3D
## Collectible loot or contract quest item.

@export var item_name: String = "Silver Candlestick"
@export var value: int = 75
@export var is_quest_item: bool = false

var visual_root: Node3D
var mesh_inst: MeshInstance3D
var _highlight_mat: StandardMaterial3D
var label: Label3D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("loot")
	add_to_group("thief_vision_highlight")
	set_meta("collected", false)

	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.7
	col.shape = sph
	add_child(col)

	visual_root = Node3D.new()
	add_child(visual_root)

	_highlight_mat = StandardMaterial3D.new()
	var hl_col := Color(1.0, 0.85, 0.2) if is_quest_item else Color(0.3, 0.85, 1.0)
	_highlight_mat.albedo_color = Color(hl_col.r, hl_col.g, hl_col.b, 0.45)
	_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.emission_enabled = true
	_highlight_mat.emission = hl_col
	_highlight_mat.emission_energy_multiplier = 1.6

	var glb_path := "res://assets/ue/Content/Art/Gameplay/CallingCards/Spider/SM_CallingCard_Spider_Gold.glb" if is_quest_item else "res://assets/ue/Content/Art/Gameplay/Clues/Notes/SM_NoteOpenA.glb"
	var packed := ResourceLoader.load(glb_path) as PackedScene
	if packed != null:
		var inst := packed.instantiate()
		inst.scale = Vector3(2.2, 2.2, 2.2) if is_quest_item else Vector3(1.8, 1.8, 1.8)
		visual_root.add_child(inst)
	else:
		mesh_inst = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 0.35, 0.45) if not is_quest_item else Vector3(0.55, 0.55, 0.55)
		mesh_inst.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.78, 0.25) if is_quest_item else Color(0.75, 0.82, 0.9)
		mat.metallic = 0.7
		mat.roughness = 0.25
		mesh_inst.material_override = mat
		visual_root.add_child(mesh_inst)

	label = Label3D.new()
	label.position = Vector3(0, 0.75, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = item_name
	label.font_size = 28
	label.visible = is_quest_item
	add_child(label)


func _process(delta: float) -> void:
	if visual_root != null:
		visual_root.rotate_y(delta * 1.4)


func interact(_actor: Node) -> void:
	if get_meta("collected", false):
		return
	set_meta("collected", true)
	GameState.add_loot(1, value, is_quest_item)
	queue_free()


func set_highlighted(on: bool) -> void:
	label.visible = on or is_quest_item
	if visual_root != null:
		_apply_highlight_recursive(visual_root, _highlight_mat if on else null)


func _apply_highlight_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = mat
	for c in node.get_children():
		_apply_highlight_recursive(c, mat)
