extends Node
## Reusable Spider personal-chain actor pass (W2P seam).
##
## The mission controller and the subset real-map QA probe both run this exact
## code: one spawn plan, one per-kind placement policy, one dedupe rule and one
## letter/Owl callback. Keeping it out of `mission_controller` removes the mission-
## only dependencies (`spawner_civilians`, HUD, player) that used to make the
## pass impossible to exercise without loading a whole map.
##
## Spawn pins come from `game/data/expansion/personal_spider.json` through
## `PersonalQuest.spawn_plan()`. Every position is a producer-recorded
## actor/point: the primary pin is used when it grounds, and an authored
## `fallbacks` entry is only tried when the primary cannot be grounded or is
## already occupied. No position is invented; a pin with no usable authored
## candidate is skipped with a warning.
##
## Placement is per kind (W3O). The authored pin is a spawner origin, not a
## floor point: the Library note is on a table and the Vault Owl's pin rests on
## the `SM_Manor_BookcasePedestal` top in the Vault, so `readable` and
## `quest_item` keep the authored pin exactly and get no vertical drop. NPCs are
## actors, not props: their feet go to the floor ray plus the 0.02 m clearance.
## There is no floor fallback for a quest item: an authored pin without a
## surface is a content defect, not something this pass may paper over.
##
## W4O: the settle path writes `global_position` (authored pins are world
## coordinates) and only compensates the NPC mesh bottom along world Y, so a
## transformed host cannot shift an actor. Authored `yaw_deg` (TAT-2 addition on
## the courier and 04 informant) is applied to NPC nodes only; the spinning Owl
## and the flat note are never rotated.
##
## The Owl is a quest item, not loot: it advances the chain and asks this pass
## to spawn the courier immediately. Every entry point carries one `thief_id`;
## a non-Spider thief gets no plan and no actors.
##
## The host is the parent every actor is added to (the mission root in play,
## the subset world in the probe). `hud` is optional: when present the letter
## read toasts and the NPC modal uses the real HUD; headless probes may pass a
## stub or null.

const PersonalQuestScript := preload("res://src/quests/personal_quest.gd")
const ClueItemScript := preload("res://src/interact/clue_item.gd")
const LootScript := preload("res://src/interact/loot_item.gd")
const PersonalQuestNpcScript := preload("res://src/quests/npc_clue_actor.gd")

## NPC feet sit on the authored interior floor with the tighter W1S 0.02 m
## clearance (the general spawner path uses 0.03). Readables/quest items do not
## use it: they keep their authored pin.
const GROUND_CLEARANCE: float = 0.02
## `placement_position()` y sources, printed as `PQ_PLACE kind=<k> y=<source>`.
const PLACE_PIN: String = "pin"
const PLACE_FLOOR: String = "floor"
const PLACE_PIN_NO_FLOOR: String = "pin_no_floor"
## Kinds whose feet are grounded on the floor ray (actors, not props).
const NPC_KINDS: Array[String] = ["npc", "info_npc"]
## Authored readable class for the Library note (ClueItem mesh match). The
## anchor's `actor` is a spawner component, not the readable actor class.
const NOTE_READABLE_CLASS: String = "BP_ReadableClueActor_Note_C"
## Two personal actors must never share one pin (plan overlap, or the courier
## spawned by the pickup callback after the deploy pass).
const OCCUPY_FLAT_M: float = 0.5
const OCCUPY_VERTICAL_M: float = 2.0

var host: Node3D = null
var hud: Node = null
## Thief this pass is bound to; `spawn_for_map()`/`spawn_anchor()` set it and
## every record read (`spawn_plan`, `anchor`, `record`) uses it, so a Chameleon
## deploy can never spawn or advance the Spider chain.
var thief_id: String = ""
## {anchor_id, kind, node, pos, source, actor, y_source, yaw_deg} per actor.
var actors: Array[Dictionary] = []


## Must be called before spawning. `p_host` is the parent every actor is added
## to (it needs a World3D for floor queries); `p_hud` is optional.
##
## Fallback guard: authored pins are world coordinates, so the host is expected
## to be untransformed. The settle path writes global positions, which keeps a
## transformed host correct anyway; this warning exists for consumers that
## reason in the host's local space (QA expectations, derived tooling).
func setup(p_host: Node3D, p_hud: Node = null) -> void:
	host = p_host
	hud = p_hud
	if host != null and is_instance_valid(host) and host.is_inside_tree():
		var tr: Transform3D = host.global_transform
		if not tr.basis.is_equal_approx(Basis.IDENTITY) or not tr.origin.is_zero_approx():
			push_warning("[personal_quest_spawner] host '", host.name,
				"' is transformed ", tr, "; authored pins are world space and settle writes global positions")


## Spawn every pin the current beat places on `map_id` for one thief. Previous
## actors of this pass are released first; returns the persistent `actors` array
## (same reference). A non-Spider thief yields an empty plan and no actors.
func spawn_for_map(map_id: String, p_thief_id: String = "") -> Array[Dictionary]:
	thief_id = PersonalQuestScript.runtime_thief(p_thief_id)
	_release_actors()
	var plan: Array = PersonalQuestScript.spawn_plan(map_id, thief_id)
	var ids: Array[String] = []
	for rec_v: Variant in plan:
		if not (rec_v is Dictionary):
			continue
		var spawned: Dictionary = spawn_anchor(rec_v as Dictionary, thief_id)
		if not spawned.is_empty():
			ids.append(str(spawned.get("anchor_id", "")))
	if not plan.is_empty() or not actors.is_empty():
		print("TAT-2 personal quest: map=", map_id, " thief=", thief_id,
			" stage=", PersonalQuestScript.stage_for(thief_id),
			" plan=", plan.size(), " spawned=", actors.size(), " anchors=", ",".join(ids))
	return actors


## Spawn one pin. Idempotent per anchor id and per occupied point; returns the
## record stored in `actors` ({} when the pin is not spawnable).
func spawn_anchor(rec: Dictionary, p_thief_id: String = "") -> Dictionary:
	var anchor_id: String = str(rec.get("id", ""))
	if anchor_id == "":
		return {}
	var thief: String = PersonalQuestScript.runtime_thief(p_thief_id if p_thief_id != "" else thief_id)
	if thief != PersonalQuestScript.character_id():
		return {}
	thief_id = thief
	for existing: Dictionary in actors:
		if str(existing.get("anchor_id", "")) == anchor_id:
			return existing
	var placed: Dictionary = _resolve_anchor(rec)
	if placed.is_empty():
		push_warning("[personal_quest_spawner] anchor '", anchor_id,
			"' has no usable authored position (missing/occupied/ungrounded pin); skipped (no invented fallback)")
		return {}
	if host == null or not is_instance_valid(host):
		push_warning("[personal_quest_spawner] anchor '", anchor_id, "' has no host; skipped")
		return {}
	var kind: String = str(rec.get("kind", ""))
	var y_source: String = str(placed.get("y_source", ""))
	var pos: Vector3 = placed.get("pos", Vector3.ZERO)
	var yaw_deg: float = NAN
	if rec.has("yaw_deg"):
		yaw_deg = float(rec.get("yaw_deg"))
	var node: Node3D = _make_node(rec, pos, thief)
	if node == null:
		return {}
	node.name = "PersonalQuest_" + anchor_id
	node.set_meta("personal_quest_anchor", anchor_id)
	node.set_meta("personal_quest_thief", thief)
	host.add_child(node)
	_settle_node(kind, node, pos, yaw_deg)
	print("PQ_PLACE kind=", kind, " y=", y_source, " anchor=", anchor_id,
		" yaw=", ("%.1f" % yaw_deg if is_finite(yaw_deg) else "none"),
		" pin_y=%.4f floor_y=%.4f pos=(%.4f, %.4f, %.4f)" % [
			(placed.get("pin", pos) as Vector3).y,
			float(placed.get("floor_y", NAN)),
			node.global_position.x, node.global_position.y, node.global_position.z])
	var record: Dictionary = {
		"anchor_id": anchor_id,
		"kind": kind,
		"node": node,
		"pos": node.global_position,
		"source": str(placed.get("source", "primary")),
		"actor": str(placed.get("actor", "")),
		"y_source": y_source,
		"yaw_deg": yaw_deg,
		"thief": thief,
	}
	actors.append(record)
	return record


## Called after the Owl is taken: the Lounge courier appears at once instead of
## waiting for the next deploy. Returns the spawned record ({}) when the map,
## thief or beat has no courier pin.
func on_owl_taken(p_thief_id: String = "") -> Dictionary:
	if host == null or not is_instance_valid(host):
		return {}
	var thief: String = PersonalQuestScript.runtime_thief(p_thief_id if p_thief_id != "" else thief_id)
	if thief != PersonalQuestScript.character_id():
		return {}
	thief_id = thief
	var map_id: String = str(GameState.active_map_id)
	if map_id != "guildhall":
		return {}
	var anchor_rec: Dictionary = PersonalQuestScript.anchor("guildhall", "courier", thief)
	if anchor_rec.is_empty():
		return {}
	var spawned: Dictionary = spawn_anchor(anchor_rec, thief)
	if not spawned.is_empty():
		print("TAT-2 personal quest: courier spawned after Owl pickup at ", spawned.get("pos", Vector3.ZERO))
	return spawned


## Release the actors of a previous pass (map switch or a new deploy) so one pin
## never accumulates duplicate nodes. In-tree nodes are queued; off-tree nodes
## (preview/tests) are freed at once, which is also what `queue_free()` requires.
func _release_actors() -> void:
	for rec: Dictionary in actors:
		var node_v: Variant = rec.get("node", null)
		if not (node_v is Node) or not is_instance_valid(node_v as Node):
			continue
		var node: Node = node_v as Node
		if node.is_inside_tree():
			node.queue_free()
		else:
			node.free()
	actors.clear()


func find(anchor_id: String) -> Dictionary:
	for rec: Dictionary in actors:
		if str(rec.get("anchor_id", "")) == anchor_id:
			return rec
	return {}


## Pure per-kind placement policy (W3O). `pin` is the authored spawner origin,
## `floor_y` the world floor under the pin's XZ (NAN when the ray missed).
## Returns {"pos", "y_source"} or {} when the kind cannot be placed from this
## pin. XZ always comes from the pin; rotation is not part of this policy.
##
##   readable    the authored pin is a table/shelf point: no vertical drop.
##   quest_item  the authored spawner origin is the item surface (the Vault Owl
##               rests on `SM_Manor_BookcasePedestal`): no vertical drop. A pin
##               with no authored surface is a content defect; there is no
##               invented floor fallback.
##   npc/info_npc  feet: floor ray + GROUND_CLEARANCE.
static func placement_position(kind: String, pin: Vector3, floor_y: float) -> Dictionary:
	var authored: bool = is_finite(pin.x) and is_finite(pin.y) and is_finite(pin.z)
	var floor_ok: bool = is_finite(floor_y)
	match kind:
		"readable":
			if authored:
				return {"pos": pin, "y_source": PLACE_PIN}
			return {}
		"quest_item":
			if authored:
				return {"pos": pin, "y_source": PLACE_PIN}
			return {}
		"npc", "info_npc":
			if floor_ok:
				return {
					"pos": Vector3(pin.x, floor_y + GROUND_CLEARANCE, pin.z),
					"y_source": PLACE_FLOOR,
				}
			if authored:
				# Off-tree preview only: no world to ray, so keep the pin and
				# say so instead of silently pretending it was grounded.
				return {
					"pos": Vector3(pin.x, pin.y + GROUND_CLEARANCE, pin.z),
					"y_source": PLACE_PIN_NO_FLOOR,
				}
			return {}
	return {}


## Primary pin first, then the authored fallback actors. A candidate only wins
## when the world floor ray under it hits (that ray proves the authored point is
## not in a void) and no actor of this pass already occupies it; the candidate's
## y then comes from `placement_position()`, so a readable/quest item keeps its
## authored pin y. Off-tree previews/tests keep the primary pin and the same
## per-kind policy. Empty means no authored candidate was usable.
func _resolve_anchor(rec: Dictionary) -> Dictionary:
	var kind: String = str(rec.get("kind", ""))
	var candidates: Array[Dictionary] = []
	var primary: Dictionary = _candidate(rec, "primary")
	if not primary.is_empty():
		candidates.append(primary)
	var fbs_v: Variant = rec.get("fallbacks", [])
	var fbs: Array = fbs_v if fbs_v is Array else []
	for fb_v: Variant in fbs:
		if not (fb_v is Dictionary):
			continue
		var fb: Dictionary = _candidate(fb_v as Dictionary, "fallback")
		if not fb.is_empty():
			candidates.append(fb)
	var on_tree: bool = host != null and is_instance_valid(host) and host.is_inside_tree()
	for cand: Dictionary in candidates:
		var pin: Vector3 = cand.get("pos", Vector3.ZERO)
		var floor_y: float = NAN
		if on_tree:
			var hit: Dictionary = floor_hit(host, pin)
			if hit.is_empty():
				continue
			var hp: Variant = hit.get("position", null)
			if not (hp is Vector3):
				continue
			floor_y = (hp as Vector3).y
		var placed: Dictionary = placement_position(kind, pin, floor_y)
		if placed.is_empty():
			continue
		var resolved: Vector3 = placed.get("pos", pin)
		if _anchor_occupied(resolved):
			push_warning("[personal_quest_spawner] authored ", cand.get("source", "?"), " pin of '",
				str(rec.get("id", "")), "' (", str(cand.get("actor", "")), ") is occupied at ", resolved,
				"; trying the next authored candidate")
			continue
		cand["pin"] = pin
		cand["floor_y"] = floor_y
		cand["pos"] = resolved
		cand["y_source"] = str(placed.get("y_source", ""))
		return cand
	return {}


## One authored candidate from a record with an `actor`/`pos`, or {} when the
## record has no usable three-component `pos` (never Vector3.ZERO).
static func _candidate(rec: Dictionary, source: String) -> Dictionary:
	var pv: Variant = rec.get("pos", null)
	if not (pv is Array) or (pv as Array).size() < 3:
		return {}
	var a: Array = pv as Array
	for v: Variant in [a[0], a[1], a[2]]:
		if not (v is float or v is int):
			return {}
	return {
		"actor": str(rec.get("actor", "")),
		"pos": Vector3(float(a[0]), float(a[1]), float(a[2])),
		"source": source,
	}


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


func _make_node(rec: Dictionary, pos: Vector3, thief: String) -> Node3D:
	match str(rec.get("kind", "")):
		"readable":
			return _make_note(rec, pos)
		"quest_item":
			return _make_owl(rec, pos)
		"npc", "info_npc":
			return _make_npc(rec, pos, thief)
	return null


## Library note: a normal authored readable (ClueItem) whose read transitions
## intro -> letter. The note carries no clue_set facts; PersonalQuest owns the
## grant, and the toast text is the authored `letter` journal line.
##
## The note's mesh is `SM_NoteOpenA` with its origin at the sheet centre
## (local y -0.00494..+0.00737). At the authored pin (28.0021) over the table
## top (28.000) the sheet bottom sits 2.84 mm into the table: desirable paper
## contact, so the pin is not moved and no vertical offset is applied.
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
	note.set("authored_class", str(rec.get("readable_class", NOTE_READABLE_CLASS)))
	note.connect("clue_collected", Callable(self, "_on_letter_read"))
	(note as Node3D).position = pos
	return note as Node3D


## Vault Owl: a personal quest item through LootItem's personal branch (no loot
## value/objective). The authored mesh comes from the expansion record and the
## item is marked `is_quest_item` so its highlighting and prompt match quest
## loot without joining the loot economy.
func _make_owl(rec: Dictionary, pos: Vector3) -> Node3D:
	var chain: Dictionary = PersonalQuestScript.chain()
	var owl_data: Dictionary = chain.get("owl", {}) as Dictionary
	var owl: Node = LootScript.new()
	var display_name: String = str(owl_data.get("display_name", "Theban Owl"))
	owl.set("item_name", display_name)
	owl.set("display_name", display_name)
	owl.set("value", 0)
	owl.set("loot_tier", "quest")
	owl.set("is_quest_item", true)
	owl.set("mesh_path", str(owl_data.get("mesh_res", "")))
	owl.set("personal_quest_id", str(chain.get("id", "personal_spider")))
	owl.set("authored_actor_class", str(rec.get("actor_class", "")))
	(owl as Node3D).position = pos
	return owl as Node3D


## Courier (Guildhall Lounge) / 04 informant (Old Manor Courtyard C1): the
## authored civilian rig, standing still at the pin. Couriers use variant 0 and
## the informant variant 1 when available (visual variety only, no authorship).
## Meshes come from GameData (spawners.json civilian_meshes), not mission state.
## `thief` binds the NPC's talk chain so it can never advance another thief.
func _make_npc(rec: Dictionary, pos: Vector3, thief: String) -> Node3D:
	var civilians: Array[Dictionary] = civilian_variants()
	var idx: int = 1 if str(rec.get("id", "")) == "informant" else 0
	if idx >= civilians.size():
		idx = 0
	var variant: Dictionary = civilians[idx] if not civilians.is_empty() else {}
	var npc: Node = PersonalQuestNpcScript.new()
	npc.call("setup_npc", str(rec.get("id", "")), thief,
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


## Kind-aware settle (W3O/W4O). Authored pins are world coordinates, so the
## node is placed with `global_position` (a transformed host cannot shift an
## actor). NPC feet rest on the floor: `pos.y` already carries the 0.02 m
## clearance, so subtract the mesh AABB bottom as a world-Y offset. Props
## (`readable`, `quest_item`) keep the authored pin exactly: no vertical drop
## and no AABB compensation. `yaw_deg` is applied to NPCs only (authored facing);
## props are never rotated, so the Owl's visual spin and the flat note are safe.
func _settle_node(kind: String, node: Node3D, pos: Vector3, yaw_deg: float = NAN) -> void:
	if node == null or not is_instance_valid(node):
		return
	if NPC_KINDS.has(kind):
		var bottom_world_y: float = node.global_transform.basis.y.y * mesh_bottom(node)
		node.global_position = Vector3(pos.x, pos.y - bottom_world_y, pos.z)
		if is_finite(yaw_deg):
			node.global_rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
		return
	node.global_position = pos


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
	var advance: Dictionary = PersonalQuestScript.record("letter", thief_id)
	if not bool(advance.get("ok", false)):
		return
	if hud != null and hud.has_method("show_clue_toast"):
		hud.show_clue_toast(title, body)
	print("TAT-2 personal quest: letter read thief=", thief_id, " stage=", PersonalQuestScript.stage_for(thief_id))
