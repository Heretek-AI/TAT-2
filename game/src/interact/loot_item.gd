extends Area3D
## Collectible loot or contract quest item.

@export var item_name: String = "Silver Candlestick"
@export var value: int = 75
@export var is_quest_item: bool = false
@export var loot_tier: String = "minor"
## Real loot-actor GLB (res://assets/ue/...glb from loot_actors.json). Empty
## keeps the legacy calling-card/note mesh (quest fallback path).
@export var mesh_path: String = ""
## Marker orientation, applied to the visual root.
@export var mesh_rotation_deg: Vector3 = Vector3.ZERO
## Shown on the name label (major/quest); defaults to item_name when empty.
@export var display_name: String = ""

const INTERACTABLES_PATH := "res://data/generated/gameplay/interactables.json"

static var _interactables: Dictionary = {}


static func interactables() -> Dictionary:
	if _interactables.is_empty():
		var data: Variant = null
		if FileAccess.file_exists(INTERACTABLES_PATH):
			var f: FileAccess = FileAccess.open(INTERACTABLES_PATH, FileAccess.READ)
			if f != null:
				data = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			_interactables = data
	return _interactables


static func _loot_section(tier: String) -> Dictionary:
	var loot: Variant = interactables().get("loot", {})
	if loot is Dictionary and (loot as Dictionary).has(tier):
		var section: Variant = (loot as Dictionary)[tier]
		if section is Dictionary:
			return section
	return {}


## Spawnable rows for a tier (Value > 1: skips currency placeholders and
## the renown test item). Falls back to the full entry list when empty.
static func spawn_pool(tier: String) -> Array:
	var section: Dictionary = _loot_section(tier)
	var entries: Array = section.get("entries", [])
	var pool: Array = []
	for e: Variant in entries:
		if e is Dictionary and int((e as Dictionary).get("value", 0)) > 1:
			pool.append(e)
	if pool.is_empty():
		return entries
	return pool


## Deterministic tier entry (cycles the spawn pool). Returns {} when the
## table provides nothing.
static func tier_entry(tier: String, index: int) -> Dictionary:
	var pool: Array = spawn_pool(tier)
	if pool.is_empty():
		return {}
	var entry: Variant = pool[posmod(index, pool.size())]
	return (entry as Dictionary).duplicate() if entry is Dictionary else {}


static func tier_min_value(tier: String, fallback: float = 0.0) -> float:
	return float(_loot_section(tier).get("min_value", fallback))


static func tier_max_value(tier: String, fallback: float = 0.0) -> float:
	return float(_loot_section(tier).get("max_value", fallback))


static func quest_flagship_value(fallback: int = 2500) -> int:
	return int(_loot_section("quest").get("flagship_value", fallback))


## Quest table entry for a contract loot tag ({} when unknown).
static func quest_entry_for_tag(tag: String) -> Dictionary:
	var entries: Array = _loot_section("quest").get("entries", [])
	for e: Variant in entries:
		if e is Dictionary and str((e as Dictionary).get("loot_tag", "")) == tag:
			return (e as Dictionary).duplicate()
	return {}


## Real quest value for a contract loot tag (e.g. "Loot.Quest.Diamond").
## Falls back to the quest flagship value (2500) when the tag is unknown.
static func quest_value_for_tag(tag: String, fallback: int = -1) -> int:
	if fallback < 0:
		fallback = quest_flagship_value()
	var entries: Array = _loot_section("quest").get("entries", [])
	for e: Variant in entries:
		if e is Dictionary and str((e as Dictionary).get("loot_tag", "")) == tag:
			return int((e as Dictionary).get("value", fallback))
	return fallback

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

	# Real loot-actor mesh when the spawner resolved one; legacy
	# calling-card/note meshes only when mesh_path is unset (quest fallback
	# path); the procedural box appears only when the mesh is missing.
	var glb_path := mesh_path
	if glb_path == "":
		glb_path = "res://assets/ue/Content/Art/Gameplay/CallingCards/Spider/SM_CallingCard_Spider_Gold.glb" if is_quest_item else "res://assets/ue/Content/Art/Gameplay/Clues/Notes/SM_NoteOpenA.glb"
	var packed := ResourceLoader.load(glb_path) as PackedScene
	if packed != null:
		visual_root.rotation_degrees = mesh_rotation_deg
		var inst := packed.instantiate()
		visual_root.add_child(inst)
		_fit_prop_scale(inst)
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
	label.text = display_name if display_name != "" else item_name
	label.font_size = 28
	label.visible = is_quest_item or loot_tier == "major"
	add_child(label)


## Authored GLB units vary per asset: keep scale 1.0 when the assembled prop
## already reads as a hand prop (max dimension 0.08-1.6 m); otherwise rescale
## uniformly so the max dimension hits the tier target (minor 0.35 m, major
## 0.55 m, quest 0.45 m). Deterministic; never a random scale.
func _fit_prop_scale(inst: Node) -> void:
	var boxes: Array = []
	_collect_mesh_boxes(inst, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return
	var box: AABB = boxes[0]
	for i in range(1, boxes.size()):
		box = box.merge(boxes[i] as AABB)
	var max_dim: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if max_dim < 0.08 or max_dim > 1.6:
		var target := 0.45
		if loot_tier == "minor":
			target = 0.35
		elif loot_tier == "major":
			target = 0.55
		if max_dim > 0.0001:
			var s: float = target / max_dim
			inst.scale = Vector3(s, s, s)


func _collect_mesh_boxes(n: Node, parent_tr: Transform3D, boxes: Array) -> void:
	var my_tr := parent_tr
	if n is Node3D:
		my_tr = parent_tr * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			boxes.append(my_tr * mi.mesh.get_aabb())
	for c in n.get_children():
		_collect_mesh_boxes(c, my_tr, boxes)


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
