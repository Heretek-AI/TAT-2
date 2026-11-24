extends Node
## Reusable Spider personal-chain actor pass (W2P seam).
##
## The mission controller and the subset real-map QA probe both run this exact
## code: one spawn plan, one grounding rule, one dedupe rule and one letter/
## Owl callback. Keeping it out of `mission_controller` removes the mission-
## only dependencies (`spawner_civilians`, HUD, player) that used to make the
## pass impossible to exercise without loading a whole map.
##
## Spawn pins come from `game/data/expansion/personal_spider.json` through
## `PersonalQuest.spawn_plan()`. Every position is a producer-recorded
## actor/point: the primary pin is used when it grounds, and an authored
## `fallbacks` entry is only tried when the primary cannot be grounded. No
## position is invented; a pin with no usable authored candidate is skipped
## with a warning.
##
## The Owl is not loot: it is a personal item that advances the chain and asks
## this pass to spawn the courier immediately.
##
## The host is the parent every actor is added to (the mission root in play,
## the subset world in the probe). `hud` is optional: when present the letter
## read toasts and the NPC modal uses the real HUD; headless probes may pass a
## stub or null.

const PersonalQuestScript := preload("res://src/quests/personal_quest.gd")
const ClueItemScript := preload("res://src/interact/clue_item.gd")
const LootScript := preload("res://src/interact/loot_item.gd")
const PersonalQuestNpcScript := preload("res://src/quests/npc_clue_actor.gd")

## Quest pins sit on authored interior floors, so they use the tighter W1S
## 0.02 m clearance (the general spawner path uses 0.03).
const GROUND_CLEARANCE: float = 0.02
## Two personal actors must never share one pin (plan overlap, or the courier
## spawned by the pickup callback after the deploy pass).
const OCCUPY_FLAT_M: float = 0.5
const OCCUPY_VERTICAL_M: float = 2.0

var host: Node3D = null
var hud: Node = null
## {anchor_id, kind, node, pos, source, actor} for every actor spawned this run.
var actors: Array[Dictionary] = []


## Must be called before spawning. `p_host` is the parent that is inside the
## tree (floor queries need its World3D); `p_hud` is optional.
func setup(p_host: Node3D, p_hud: Node = null) -> void:
	host = p_host
	hud = p_hud


## Spawn every pin the current beat places on `map_id`. Clears the previous
## list first; returns the persistent `actors` array (same reference).
func spawn_for_map(map_id: String) -> Array[Dictionary]:
	actors.clear()
	var plan: Array = PersonalQuestScript.spawn_plan(map_id)
	var ids: Array[String] = []
	for rec_v: Variant in plan:
		if not (rec_v is Dictionary):
			continue
		var spawned: Dictionary = spawn_anchor(rec_v as Dictionary)
		if not spawned.is_empty():
			ids.append(str(spawned.get("anchor_id", "")))
	if not plan.is_empty() or not actors.is_empty():
		print("TAT-2 personal quest: map=", map_id, " stage=", PersonalQuestScript.stage_for(),
			" plan=", plan.size(), " spawned=", actors.size(), " anchors=", ",".join(ids))
	return actors


## Spawn one pin. Idempotent per anchor id and per occupied point; returns the
## record stored in `actors` ({} when the pin is not spawnable).
func spawn_anchor(rec: Dictionary) -> Dictionary:
	var anchor_id: String = str(rec.get("id", ""))
	if anchor_id == "":
		return {}
	for existing: Dictionary in actors:
		if str(existing.get("anchor_id", "")) == anchor_id:
			return existing
	var placed: Dictionary = _resolve_anchor(rec)
	if placed.is_empty():
		push_warning("[personal_quest_spawner] anchor '", anchor_id, "' has no grounded authored position; skipped (no invented fallback)")
		return {}
	var pos: Vector3 = placed.get("pos", Vector3.ZERO)
	if _anchor_occupied(pos):
		push_warning("[personal_quest_spawner] anchor '", anchor_id, "' resolves to an occupied point ", pos, "; skipped")
		return {}
	var node: Node3D = _make_node(rec, pos)
	if node == null:
		return {}
	node.name = "PersonalQuest_" + anchor_id
	host.add_child(node)
	_ground_node(node, pos)
	var record: Dictionary = {
		"anchor_id": anchor_id,
		"kind": str(rec.get("kind", "")),
		"node": node,
		"pos": node.global_position,
		"source": str(placed.get("source", "primary")),
		"actor": str(placed.get("actor", "")),
	}
	actors.append(record)
	return record


## Called after the Owl is taken: the Lounge courier appears at once instead of
## waiting for the next deploy. Returns the spawned record ({}) when the map or
## beat has no courier pin.
func on_owl_taken() -> Dictionary:
	if host == null or not is_instance_valid(host):
		return {}
	var map_id: String = str(GameState.active_map_id)
	if map_id != "guildhall":
		return {}
	var anchor_rec: Dictionary = PersonalQuestScript.anchor("guildhall", "courier")
	if anchor_rec.is_empty():
		return {}
	var spawned: Dictionary = spawn_anchor(anchor_rec)
	if not spawned.is_empty():
		print("TAT-2 personal quest: courier spawned after Owl pickup at ", spawned.get("pos", Vector3.ZERO))
	return spawned


func find(anchor_id: String) -> Dictionary:
	for rec: Dictionary in actors:
		if str(rec.get("anchor_id", "")) == anchor_id:
			return rec
	return {}


## Primary pin first, then the authored fallback actors. A candidate only wins
## when the world floor ray under it hits; off-tree previews/tests keep the
## primary pin. Empty means no authored candidate was usable.
func _resolve_anchor(rec: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = [{
		"actor": str(rec.get("actor", "")),
		"pos": vec3_from(rec.get("pos", [])),
		"source": "primary",
	}]
	for fb_v: Variant in rec.get("fallbacks", []) as Array:
		if not (fb_v is Dictionary):
			continue
		var fb: Dictionary = fb_v as Dictionary
		candidates.append({
			"actor": str(fb.get("actor", "")),
			"pos": vec3_from(fb.get("pos", [])),
			"source": "fallback",
		})
	for cand: Dictionary in candidates:
		var p: Vector3 = cand.get("pos", Vector3.ZERO)
		var hit: Dictionary = floor_hit(host, p)
		if hit.is_empty():
			continue
		var hp: Variant = hit.get("position", null)
		if hp is Vector3:
			cand["pos"] = Vector3(p.x, (hp as Vector3).y, p.z)
			return cand
	if host == null or not host.is_inside_tree():
		return candidates[0]
	return {}


func _anchor_occupied(pos: Vector3) -> bool:
	for e: Dictionary in actors:
		var ep: Vector3 = e.get("pos", Vector3.ZERO)
		var flat := Vector2(ep.x - pos.x, ep.z - pos.z)
		if flat.length() < OCCUPY_FLAT_M and absf(ep.y - pos.y) < OCCUPY_VERTICAL_M:
			return true
	return false


static func vec3_from(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


## World floor query shared by the spawner and the QA probes: +2 m down to -6 m
## on the layer-1 world. Empty when the host is off-tree or has no world.
static func floor_hit(parent: Node3D, pos: Vector3) -> Dictionary:
	if parent == null or not parent.is_inside_tree():
		return {}
	var w3d: World3D = parent.get_world_3d()
	if w3d == null or w3d.direct_space_state == null:
		return {}
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * 2.0, pos + Vector3.DOWN * 6.0, 1)
	return w3d.direct_space_state.intersect_ray(q)


func _make_node(rec: Dictionary, pos: Vector3) -> Node3D:
	match str(rec.get("kind", "")):
		"readable":
			return _make_note(rec, pos)
		"quest_item":
			return _make_owl(rec, pos)
		"npc":
			return _make_npc(rec, pos)
	return null


## Library note: a normal authored readable (ClueItem) whose read transitions
## intro -> letter. The note carries no clue_set facts; PersonalQuest owns the
## grant, and the toast text is the authored `letter` journal line.
func _make_note(rec: Dictionary, pos: Vector3) -> Node3D:
	var chain: Dictionary = PersonalQuestScript.chain()
	var note: Node = ClueItemScript.new()
	var beat: Dictionary = PersonalQuestScript.beat_for("letter")
	var lines: PackedStringArray = PackedStringArray()
	for line_v: Variant in beat.get("journal", []) as Array:
		var line: String = str(line_v).strip_edges()
		if line != "":
			lines.append(line)
	note.set("clue_title", str(chain.get("title", "The Theban Owl")))
	note.set("clue_body", "\n".join(lines))
	note.set("prompt_verb", "Read")
	note.set("authored_class", str(rec.get("actor_class", "BP_ReadableClueActor_Note_C")))
	note.connect("clue_collected", Callable(self, "_on_letter_read"))
	(note as Node3D).position = pos
	return note as Node3D


## Vault Owl: a personal item through LootItem's personal branch (no loot
## value/objective). The authored mesh comes from the expansion record.
func _make_owl(rec: Dictionary, pos: Vector3) -> Node3D:
	var chain: Dictionary = PersonalQuestScript.chain()
	var owl_data: Dictionary = chain.get("owl", {}) as Dictionary
	var owl: Node = LootScript.new()
	var display_name: String = str(owl_data.get("display_name", "Theban Owl"))
	owl.set("item_name", display_name)
	owl.set("display_name", display_name)
	owl.set("value", 0)
	owl.set("loot_tier", "quest")
	owl.set("mesh_path", str(owl_data.get("mesh_res", "")))
	owl.set("personal_quest_id", str(chain.get("id", "personal_spider")))
	owl.set("authored_actor_class", str(rec.get("actor_class", "")))
	(owl as Node3D).position = pos
	return owl as Node3D


## Courier (Guildhall Lounge) / 04 informant (Old Manor Courtyard C1): the
## authored civilian rig, standing still at the pin. Couriers use variant 0 and
## the informant variant 1 when available (visual variety only, no authorship).
## Meshes come from GameData (spawners.json civilian_meshes), not mission state.
func _make_npc(rec: Dictionary, pos: Vector3) -> Node3D:
	var civilians: Array[Dictionary] = civilian_variants()
	var idx: int = 1 if str(rec.get("id", "")) == "informant" else 0
	if idx >= civilians.size():
		idx = 0
	var variant: Dictionary = civilians[idx] if not civilians.is_empty() else {}
	var npc: Node = PersonalQuestNpcScript.new()
	npc.call("setup_npc", str(rec.get("id", "")), PersonalQuestScript.runtime_thief(),
		str(variant.get("body", "")), str(variant.get("head", "")), pos)
	(npc as Node3D).position = pos
	return npc as Node3D


## Authored civilian body/head variants from GameData (never mission state).
static func civilian_variants() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if GameData != null and GameData.has_method("get_civilian_meshes"):
		for rec_v: Variant in GameData.call("get_civilian_meshes") as Array:
			if rec_v is Dictionary:
				out.append((rec_v as Dictionary).duplicate(true))
	return out


## Ground the spawned actor's real mesh AABB onto the floor hit with the W1S
## 0.02 m clearance (the general spawner path uses 0.03).
func _ground_node(node: Node3D, marker: Vector3) -> void:
	var bottom: float = mesh_bottom(node)
	var hit: Dictionary = floor_hit(host, marker)
	if not hit.is_empty():
		var hp: Variant = hit.get("position", null)
		if hp is Vector3:
			node.position = Vector3(marker.x, (hp as Vector3).y + GROUND_CLEARANCE - bottom, marker.z)
			return
	node.position = marker + Vector3(0.0, GROUND_CLEARANCE - bottom, 0.0)


## Lowest mesh point of a spawned node in its own local space (loot visual
## root, civilian mesh root). Includes each MeshInstance3D's authored scale and
## rotation so the AABB bottom is the real resting point; 0.0 when the node
## carries no mesh (small clearance only).
static func mesh_bottom(node: Node3D) -> float:
	var boxes: Array[AABB] = []
	_collect_mesh_boxes(node, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return 0.0
	var box: AABB = boxes[0]
	for i: int in range(1, boxes.size()):
		box = box.merge(boxes[i])
	return box.position.y


static func _collect_mesh_boxes(n: Node, parent_tr: Transform3D, boxes: Array[AABB]) -> void:
	for c: Node in n.get_children():
		var tr: Transform3D = parent_tr
		if c is Node3D:
			tr = parent_tr * (c as Node3D).transform
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c as MeshInstance3D
			if mi.mesh != null:
				boxes.append(tr * mi.mesh.get_aabb())
		_collect_mesh_boxes(c, tr, boxes)


## intro -> letter. The note read is the only writer of this beat.
func _on_letter_read(title: String, body: String) -> void:
	var advance: Dictionary = PersonalQuestScript.record("letter")
	if not bool(advance.get("ok", false)):
		return
	if hud != null and hud.has_method("show_clue_toast"):
		hud.show_clue_toast(title, body)
	print("TAT-2 personal quest: letter read stage=", PersonalQuestScript.stage_for())
