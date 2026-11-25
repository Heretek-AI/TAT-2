extends Area3D
## Interactive Clue / Note / Electrotype item.

const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const UIStringsScript := preload("res://src/ui/ui_strings.gd")

signal clue_collected(title: String, body: String)

@export var clue_title: String = 'Contract Clue'
@export var clue_body: String = 'Check the guard patrol schedule near the courtyard.'
## Authored prompt verb. Authored clues pass "Read" so the prompt is [E] Read;
## the legacy fallback keeps its descriptive prompt when this is empty.
@export var prompt_verb: String = ""
## Authored visual actor class (BP_ReadableClueActor_*_C) and readable type.
@export var authored_class: String = ""
@export var visual_type: String = ""
## Authored fact ids granted on first read (GameData.get_fact).
var fact_ids: Array[String] = []
var fact_params: Dictionary = {}
var fact_source: String = "clue"
var fact_source_item_tag: String = ""
var fact_source_index: int = -1

var collected: bool = false
var visual_root: Node3D
var mesh_inst: MeshInstance3D
var glow_light: OmniLight3D
var label: Label3D


func _ready() -> void:
	add_to_group('interactables')
	add_to_group('thief_vision_highlight')
	add_to_group('xray_target')

	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.6, 0.4, 0.6)
	col.shape = box
	add_child(col)

	visual_root = Node3D.new()
	add_child(visual_root)

	var glb_path: String = "res://assets/ue/Content/Art/Gameplay/Clues/Notes/SM_NoteOpenA.glb"
	match authored_class:
		"BP_ReadableClueActor_Note_C":
			glb_path = "res://assets/ue/Content/Art/Gameplay/Clues/Notes/SM_NoteOpenA.glb"
		"BP_ReadableClueActor_Newspaper_C":
			glb_path = "res://assets/ue/Content/Art/Gameplay/Loot/SM_ClueNewspaper.glb"
		"BP_ReadableClueActor_Journal_C":
			glb_path = "res://assets/ue/Content/Art/Gameplay/Loot/SM_ClueJournal.glb"
	if ResourceLoader.exists(glb_path):
		var packed: PackedScene = ResourceLoader.load(glb_path) as PackedScene
		if packed != null:
			var inst: Node3D = packed.instantiate() as Node3D
			visual_root.add_child(inst)
			# C2-01: rebind the authored slot materials (the GLB itself has no
			# textures and defaults to white).
			LevelLoaderScript.bind_prop_scene_materials(inst, glb_path)
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
	label.text = UIStringsScript.loc(clue_title) if clue_title != "" else prompt_verb
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
	# P1 clue re-fire: every press re-emitted 1.5 m noise (guards
	# re-investigate) + the HUD toast. The first read collects; later reads are
	# silent re-reads (UE clue pickup is one-shot; prompt flips to [Read]).
	if collected:
		return
	collected = true
	for fact_id: String in fact_ids:
		GameState.grant_fact(fact_id, fact_params, fact_source, fact_source_item_tag, fact_source_index)
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
	if prompt_verb != "":
		# The verb is authored (mission_controller passes ST_Interactables.PromptRead);
		# the [E] alias is the legacy token the HUD maps to the live interact glyph.
		return ("[%s]" % prompt_verb) if collected else (UIStringsScript.loc("[E] %s") % prompt_verb) ## PORT COPY format (no authored row)
	if collected:
		return UIStringsScript.loc("[Read] ") + clue_title ## PORT COPY (no authored row)
	return UIStringsScript.loc("[E] Read Clue: ") + clue_title ## PORT COPY (no authored row)


## Interaction LOS point (W2): the note lies flat on its surface; +0.35 m puts
## the LOS target just above the paper instead of inside it.
func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.35


func set_highlighted(on: bool) -> void:
	if label != null and not collected:
		label.visible = on
	# C2: authored MI_XrayClue green silhouette, including the mesh (the old
	# path only toggled the label).
	if visual_root != null and not collected:
		XrayOverlay.set_xray_highlight(visual_root, on, "clue")


func set_xray_highlight(on: bool, _category: String = "") -> void:
	set_highlighted(on)
