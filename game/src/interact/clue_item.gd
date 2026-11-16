extends Area3D
## Interactive Clue / Note / Electrotype item.

signal clue_collected(title: String, body: String)

@export var clue_title: String = 'Contract Clue'
@export var clue_body: String = 'Check the guard patrol schedule near the courtyard.'

var collected: bool = false
var visual_root: Node3D
var mesh_inst: MeshInstance3D
var glow_light: OmniLight3D
var label: Label3D


func _ready() -> void:
	add_to_group('interactables')
	add_to_group('thief_vision_highlight')

	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.6, 0.4, 0.6)
	col.shape = box
	add_child(col)

	visual_root = Node3D.new()
	add_child(visual_root)

	var glb_path: String = 'res://assets/ue/Content/Art/Environment/Props/Paper/SM_NoteOpenA.glb'
	if ResourceLoader.exists(glb_path):
		var packed: PackedScene = ResourceLoader.load(glb_path) as PackedScene
		if packed != null:
			var inst: Node3D = packed.instantiate() as Node3D
			visual_root.add_child(inst)
		else:
			_build_parchment_fallback()
	else:
		_build_parchment_fallback()

	glow_light = OmniLight3D.new()
	glow_light.light_color = Color(0.55, 0.95, 1.0)
	glow_light.light_energy = 0.4
	glow_light.omni_range = 2.0
	add_child(glow_light)

	label = Label3D.new()
	label.position = Vector3(0.0, 0.6, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = clue_title
	label.font_size = 28
	label.visible = false
	add_child(label)


func _build_parchment_fallback() -> void:
	mesh_inst = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.5, 0.06, 0.35)
	mesh_inst.mesh = bm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.87, 0.62)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.9, 1.0)
	mat.emission_energy_multiplier = 0.6
	mesh_inst.material_override = mat
	visual_root.add_child(mesh_inst)


func interact(actor: Node) -> void:
	collected = true
	clue_collected.emit(clue_title, clue_body)
	NoiseBus.emit_noise(global_position, 1.5, actor, 'clue')
	if label != null:
		label.visible = true
	if glow_light != null:
		var dim_tween: Tween = create_tween()
		dim_tween.tween_property(glow_light, 'light_energy', 0.1, 0.5)
	if visual_root != null:
		var fade_tween: Tween = create_tween()
		fade_tween.tween_property(visual_root, 'scale', Vector3(0.85, 0.85, 0.85), 0.25)


func get_interact_prompt() -> String:
	if collected:
		return '[Read] ' + clue_title
	return '[E] Read Clue: ' + clue_title


func set_highlighted(on: bool) -> void:
	if label != null and not collected:
		label.visible = on
