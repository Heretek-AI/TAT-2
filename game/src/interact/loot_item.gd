extends Area3D
## Collectible loot or contract quest item.

@export var item_name: String = "Silver Candlestick"
@export var value: int = 75
@export var is_quest_item: bool = false
@export var loot_tier: String = "minor"
## Real loot-actor GLB (res://assets/ue/...glb from loot_actors.json). Empty
## keeps the legacy calling-card/note mesh (quest fallback path).
@export var mesh_path: String = ""
## Real carried-loot tool mesh (CarriedLootMeshData.ToolMesh from the loot
## row); empty when the capture has no carried variant. The post-match/HUD
## carried-loot art pass reads this, not the world mesh.
@export var carry_mesh_path: String = ""
## Authored DT_LootInfo row IsLargeCarry (large relics are visually carried
## two-handed in the reference; the slot cost still follows loot_tier).
@export var is_large_carry: bool = false
## Marker orientation, applied to the visual root.
@export var mesh_rotation_deg: Vector3 = Vector3.ZERO
## Shown on the name label (major/quest); defaults to item_name when empty.
@export var display_name: String = ""
## Authored quest-item metadata (DT_LootInfo_Quest / quest spawner).
@export var authored_actor_class: String = ""
## W1S personal-chain pickup (empty for ordinary loot). When set, the item is
## a personal quest item: `interact` calls PersonalQuest.acquire_owl(), never
## GameState.add_loot, and it carries no value/objective/fact of its own.
@export var personal_quest_id: String = ""
var clue_location_text: String = ""
var objective_id: String = ""
var loot_tag: String = ""
## Authored clue facts granted on pickup (spawner _spawnActions + pickup clue).
var fact_ids: Array[String] = []
var fact_params: Dictionary = {}
var fact_source: String = "loot"
var fact_source_item_tag: String = ""
var fact_source_index: int = -1

const INTERACTABLES_PATH := "res://data/generated/gameplay/interactables.json"
const PersonalQuestScript := preload("res://src/quests/personal_quest.gd")
const LootInventoryScript := preload("res://src/interact/loot_inventory.gd")

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


## Authored DT_LootInfo `TimeTakenToSteal` for this actor
## (interactables.json loot.<tier>.entries). Quest rows resolve by loot_tag,
## bucket rows by their authored display name (the loot_actors name IS the
## DT_LootInfo row name). 0.0 = no authored row (unparsed row / synthetic test
## item) and the pickup stays instant.
static func authored_steal_time_s(tier: String, tag: String, item_label: String) -> float:
	var entries: Array = _loot_section(tier).get("entries", [])
	if tag != "":
		for e: Variant in entries:
			if e is Dictionary and str((e as Dictionary).get("loot_tag", "")) == tag:
				return maxf(float((e as Dictionary).get("steal_time_s", 0.0)), 0.0)
	if item_label != "":
		for e: Variant in entries:
			if e is Dictionary and str((e as Dictionary).get("name", "")) == item_label:
				return maxf(float((e as Dictionary).get("steal_time_s", 0.0)), 0.0)
	return 0.0


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
	# A personal-chain item is not loot: joining "loot" would feed the loot
	# economy audit, the tactical map and the pickpocket fairy. Keep it
	# interactable and thief-vision highlightable only.
	if personal_quest_id == "":
		add_to_group("loot")
		add_to_group("xray_target")
	add_to_group("thief_vision_highlight")
	# C4-14: the compass and TAB map read the "objectives" group; nothing else
	# produced it, so a contract item 90 m away had no marker. A contract quest
	# item is the objective marker; it leaves the group on pickup
	# (loot_inventory.PICKUP_GROUPS).
	if is_quest_item and personal_quest_id == "":
		add_to_group("objectives")
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
	label.visible = is_quest_item or loot_tier == "major" or personal_quest_id != ""
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
	# A collected actor lingers for the authored pickup beat; freeze its idle
	# spin so the beat reads as a pickup, not as a still-live world item.
	if get_meta("collected", false):
		return
	if visual_root != null:
		visual_root.rotate_y(delta * 1.4)


## P2 loot_item prompt fallback: quest loot used to fall through to the
## generic "[E] Steal %s" branch in thief_character (wrong verb for a
## contract relic the player must take). Quest items read Take; regular loot
## keeps Steal. A full carried inventory reads the authored INVENTORY FULL
## line (loot_inventory.gd) instead of an action that cannot complete.
func get_interact_prompt() -> String:
	return LootInventoryScript.prompt_for(self)


## Interaction LOS point (W2): named loot is grounded on its mesh AABB, so the
## origin can be inside the item; +0.4 m targets the readable top of the prop.
func get_interact_point() -> Vector3:
	return global_position + Vector3.UP * 0.4


## Authored hold-to-steal beat in seconds (DT_LootInfo TimeTakenToSteal; up to
## 4 s on the big relics). The player controller gates its tap->hold on this;
## `interact()` itself stays the instant apply so scripted/QA callers keep the
## documented synchronous contract.
func get_interact_hold_seconds() -> float:
	if personal_quest_id != "":
		return 0.0
	if get_meta("collected", false):
		return 0.0
	var label: String = display_name if display_name != "" else item_name
	return authored_steal_time_s(loot_tier, loot_tag, label)


func interact(actor: Node) -> void:
	if get_meta("collected", false):
		return
	if personal_quest_id != "":
		_interact_personal_quest()
		return
	# Carried inventory (W7S-S2): capacity first, then the gross counter and the
	# carried entry in one place (loot_inventory.carry). A refusal leaves the
	# world actor untouched and shows the authored INVENTORY FULL line.
	var carried: Dictionary = LootInventoryScript.carry(self, actor)
	if not bool(carried.get("ok", false)):
		return
	if objective_id.begins_with("set_item_"):
		GameState.advance_set_objective()
	for fact_id: String in fact_ids:
		GameState.grant_fact(fact_id, fact_params, fact_source, fact_source_item_tag, fact_source_index)
	# The actor remains visible for the authored pickup beat, out of every
	# gameplay group, then frees itself (loot_inventory.begin_linger).
	LootInventoryScript.begin_linger(self)


## Theban Owl path: a personal item, not loot. Advance the chain through the
## controller only, then let the mission spawn the courier right away. No
## GameState.add_loot, no value, no quest_item_acquired, no objective/fact.
func _interact_personal_quest() -> void:
	var result: Dictionary = PersonalQuestScript.acquire_owl()
	if not bool(result.get("ok", false)) or str(result.get("stage", "")) != "carrying":
		return
	set_meta("collected", true)
	if is_inside_tree():
		var mission: Node = get_tree().get_first_node_in_group("mission")
		if mission != null and mission.has_method("on_personal_quest_owl_taken"):
			mission.call("on_personal_quest_owl_taken")
	queue_free()


func set_highlighted(on: bool) -> void:
	label.visible = on or is_quest_item
	if visual_root != null:
		# C2: authored MI_XrayLoot orange silhouette.
		XrayOverlay.set_xray_highlight(visual_root, on, "loot")


func set_xray_highlight(on: bool, _category: String = "") -> void:
	set_highlighted(on)


func _apply_highlight_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = mat
	for c in node.get_children():
		_apply_highlight_recursive(c, mat)
