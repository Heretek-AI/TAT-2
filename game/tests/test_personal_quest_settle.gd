extends RefCounted
## W4O suite 88: the Spider personal-chain settle path and thief binding.
##
## `run(host)` is called by `tests/run_tests.gd` (suite 88) and returns a list
## of problems. Nothing here loads a map or starts a second engine.
##
## The W3O audit found the pure placement policy correct but the application
## path unsafe: `_settle_node()` wrote a *local* `node.position` from a world pin
## and floor ray, so any parent transform shifted every actor; the floor
## fallback invented a y; nothing bound the pass to the Spider thief; and the
## authored facing claim was false. This suite exercises the real
## `spawn_anchor()` / `_settle_node()` code with synthetic records on one
## deliberately transformed host (off-tree, so no map or physics tick is
## needed — the floor-ray gate is the subset probe's job on a real map):
##
##   * a readable keeps the authored world pin y and gets the authored readable
##     class, even under a translated + rotated host;
##   * the quest item is `is_quest_item`, keeps the pin and is not rotated;
##   * an NPC's feet land on the requested world y (mesh-AABB bottom as a world
##     Y offset), the authored `yaw_deg` is applied, and its thief is bound;
##   * a pin without `pos` is skipped (never Vector3.ZERO), non-Array fallbacks
##     are ignored, and an occupied primary pin uses the authored fallback;
##   * a Chameleon pass spawns zero actors and mutates no save record.
##
## Every shared autoload field is restored before returning.

const SpawnerScript := preload("res://src/quests/personal_quest_spawner.gd")
const PersonalQuestScript := preload("res://src/quests/personal_quest.gd")
const EXPANSION_PATH := "res://data/expansion/personal_spider.json"

const TOL: float = 0.0005
const NPC_CLEARANCE: float = 0.02


func run(host: Node) -> Array[String]:
	var problems: Array[String] = []
	var ss: Node = host.get_node_or_null("/root/SaveSystem")
	var gs: Node = host.get_node_or_null("/root/GameState")
	if ss == null or gs == null:
		problems.append("suite 88 needs the SaveSystem/GameState autoloads")
		return problems
	var anchors: Array = _anchors()
	if anchors.is_empty():
		problems.append("cannot read %s" % EXPANSION_PATH)
		return problems
	var note_a: Dictionary = _anchor(anchors, "library_note")
	var owl_a: Dictionary = _anchor(anchors, "owl")
	var courier_a: Dictionary = _anchor(anchors, "courier")
	var informant_a: Dictionary = _anchor(anchors, "informant")
	var note_pin: Vector3 = SpawnerScript.vec3_from(note_a.get("pos", []))
	var owl_pin: Vector3 = SpawnerScript.vec3_from(owl_a.get("pos", []))
	var courier_pin: Vector3 = SpawnerScript.vec3_from(courier_a.get("pos", []))
	var informant_pin: Vector3 = SpawnerScript.vec3_from(informant_a.get("pos", []))

	# --- authored yaw is data, and only the two NPCs carry it -------------
	_check(problems, _finite_num(courier_a.get("yaw_deg", null)),
		"courier anchor carries yaw_deg", "courier yaw_deg=%s" % str(courier_a.get("yaw_deg", null)))
	_check(problems, _finite_num(informant_a.get("yaw_deg", null)),
		"04 informant anchor carries yaw_deg", "informant yaw_deg=%s" % str(informant_a.get("yaw_deg", null)))
	_check(problems, courier_a.get("yaw_deg", null) != null and str(courier_a.get("yaw_note", "")).contains("TAT-2"),
		"courier yaw is marked TAT-2 authored", "courier yaw_note=%s" % str(courier_a.get("yaw_note", "")))
	_check(problems, informant_a.get("yaw_deg", null) != null and str(informant_a.get("yaw_note", "")).contains("TAT-2"),
		"informant yaw is marked TAT-2 authored", "informant yaw_note=%s" % str(informant_a.get("yaw_note", "")))
	_check(problems, not owl_a.has("yaw_deg") and not note_a.has("yaw_deg"),
		"the Owl and the Library note carry no yaw (spin / flat sheet)")

	# --- one transformed host: world pins must not shift -------------------
	var world := Node3D.new()
	world.name = "PersonalQuestSettleHost"
	world.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(35.0)), Vector3(120.0, 8.0, -60.0))
	var spawner: Node = SpawnerScript.new()
	spawner.set("name", "PersonalQuestSettleSpawner")
	spawner.call("setup", world)
	_check(problems, spawner.get("host") == world, "setup() keeps the host reference")

	var save_backup: Dictionary = (ss.get("data") as Dictionary).duplicate(true)
	var gs_thief: String = str(gs.get("thief_id"))

	# --- readable: authored pin y + authored readable class ---------------
	var note_rec: Dictionary = spawner.call("spawn_anchor", note_a, "spider") as Dictionary
	_check(problems, not note_rec.is_empty(), "readable spawn_anchor() places the Library note")
	if not note_rec.is_empty():
		var note: Node3D = note_rec.get("node", null) as Node3D
		_check(problems, note != null and is_instance_valid(note), "readable record has a live node")
		_check(problems, str(note_rec.get("y_source", "")) == SpawnerScript.PLACE_PIN,
			"readable y_source=pin", "readable y_source=%s" % str(note_rec.get("y_source", "")))
		_check(problems, str(note_rec.get("thief", "")) == "spider",
			"readable record is bound to the Spider", "readable thief=%s" % str(note_rec.get("thief", "")))
		if note != null:
			_check(problems, _near(note.global_position, note_pin),
				"readable global_position == authored world pin under a transformed host",
				"readable global=%s pin=%s" % [note.global_position, note_pin])
			_check(problems, not _near(note.position, note_pin),
				"readable local position is not the world pin (settle writes global, not local)")
			_check(problems, str(note.get("authored_class")) == SpawnerScript.NOTE_READABLE_CLASS,
				"readable uses the authored note class",
				"readable authored_class=%s" % str(note.get("authored_class")))
			_check(problems, str(note.call("get_interact_prompt")) == "[E] Read",
				"readable prompt is [E] Read", "readable prompt=%s" % str(note.call("get_interact_prompt")))
			_check(problems, note.rotation.is_zero_approx(), "readable is never rotated")

	# --- quest item: is_quest_item, pin y, no rotation --------------------
	var owl_rec: Dictionary = spawner.call("spawn_anchor", owl_a, "spider") as Dictionary
	_check(problems, not owl_rec.is_empty(), "quest_item spawn_anchor() places the Vault Owl")
	if not owl_rec.is_empty():
		var owl: Node3D = owl_rec.get("node", null) as Node3D
		_check(problems, str(owl_rec.get("y_source", "")) == SpawnerScript.PLACE_PIN,
			"Owl y_source=pin", "Owl y_source=%s" % str(owl_rec.get("y_source", "")))
		_check(problems, _near(owl_rec.get("pos", Vector3.ZERO) as Vector3, owl_pin),
			"Owl global_position == authored world pin",
			"Owl pos=%s pin=%s" % [str(owl_rec.get("pos", Vector3.ZERO)), owl_pin])
		if owl != null:
			_check(problems, bool(owl.get("is_quest_item")), "Owl is is_quest_item=true")
			_check(problems, str(owl.get("personal_quest_id")) == "personal_spider",
				"Owl keeps its personal quest id", "Owl id=%s" % str(owl.get("personal_quest_id")))
			_check(problems, str(owl.call("get_interact_prompt")) == "[E] Take Theban Owl",
				"Owl prompt is [E] Take Theban Owl", "Owl prompt=%s" % str(owl.call("get_interact_prompt")))
			_check(problems, owl.rotation.is_zero_approx(), "Owl node is not rotated (its visual root spins)")

	# --- NPC: feet on the requested world y, authored yaw, thief bound ----
	var npc_rec: Dictionary = spawner.call("spawn_anchor", courier_a, "spider") as Dictionary
	_check(problems, not npc_rec.is_empty(), "npc spawn_anchor() places the Lounge courier")
	if not npc_rec.is_empty():
		var npc: Node3D = npc_rec.get("node", null) as Node3D
		_check(problems, str(npc_rec.get("y_source", "")) == SpawnerScript.PLACE_PIN_NO_FLOOR,
			"off-tree NPC records y_source=pin_no_floor",
			"courier y_source=%s" % str(npc_rec.get("y_source", "")))
		_check(problems, str(npc_rec.get("thief", "")) == "spider",
			"NPC record is bound to the Spider", "NPC thief=%s" % str(npc_rec.get("thief", "")))
		if npc != null:
			_check(problems, absf(npc.global_position.y - (courier_pin.y + NPC_CLEARANCE)) <= TOL,
				"off-tree NPC sits at pin y + clearance",
				"courier y=%.4f expected %.4f" % [npc.global_position.y, courier_pin.y + NPC_CLEARANCE])
			_check(problems, str(npc.get("thief_id")) == "spider",
				"NPC talk chain is bound to the Spider", "NPC thief_id=%s" % str(npc.get("thief_id")))
			_check(problems, str(npc.get("anchor_id")) == "courier",
				"NPC anchor id is courier", "NPC anchor=%s" % str(npc.get("anchor_id")))
			var want_yaw: float = deg_to_rad(float(courier_a.get("yaw_deg", 0.0)))
			_check(problems, absf(angle_difference(npc.global_rotation.y, want_yaw)) <= 0.01,
				"courier node yaw matches the authored record (%.1f deg)" % float(courier_a.get("yaw_deg", 0.0)),
				"courier yaw=%.1f deg expected %.1f deg" % [
					rad_to_deg(npc.global_rotation.y), float(courier_a.get("yaw_deg", 0.0))])

	# --- 04 informant: same policy, authored yaw 0 is a real assignment ---
	var inf_rec: Dictionary = spawner.call("spawn_anchor", informant_a, "spider") as Dictionary
	_check(problems, not inf_rec.is_empty(), "npc spawn_anchor() places the 04 informant")
	if not inf_rec.is_empty():
		var inf: Node3D = inf_rec.get("node", null) as Node3D
		_check(problems, str(inf_rec.get("thief", "")) == "spider",
			"04 informant record is bound to the Spider", "informant thief=%s" % str(inf_rec.get("thief", "")))
		_check(problems, absf((inf_rec.get("pos", Vector3.ZERO) as Vector3).y - (informant_pin.y + NPC_CLEARANCE)) <= TOL,
			"04 informant sits at pin y + clearance",
			"informant y=%.4f expected %.4f" % [
				(inf_rec.get("pos", Vector3.ZERO) as Vector3).y, informant_pin.y + NPC_CLEARANCE])
		if inf != null:
			_check(problems, absf(angle_difference(inf.global_rotation.y, deg_to_rad(float(informant_a.get("yaw_deg", 0.0))))) <= 0.01,
				"04 informant node yaw matches the authored record (0 deg)",
				"informant yaw=%.1f deg" % rad_to_deg(inf.global_rotation.y))
			_check(problems, str(inf.get("anchor_id")) == "informant",
				"04 informant anchor id is informant", "informant anchor=%s" % str(inf.get("anchor_id")))

	# --- direct _settle_node(): mesh bottom lands on the target world y ---
	var body := Node3D.new()
	body.name = "SyntheticNpcBody"
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 1.0, 0.4)
	mi.mesh = box
	mi.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(mi)
	world.add_child(body)
	_check(problems, absf(SpawnerScript.mesh_bottom(body) - 0.4) <= TOL,
		"synthetic mesh bottom is 0.4 m", "mesh_bottom=%.4f" % SpawnerScript.mesh_bottom(body))
	spawner.call("_settle_node", "npc", body, Vector3(5.0, 10.0, -3.0), 180.0)
	var foot: float = body.global_position.y + body.global_transform.basis.y.y * SpawnerScript.mesh_bottom(body)
	_check(problems, absf(foot - 10.0) <= TOL,
		"_settle_node puts the NPC mesh bottom on the requested world y",
		"foot=%.4f expected 10.0000" % foot)
	_check(problems, absf(body.global_position.x - 5.0) <= TOL and absf(body.global_position.z + 3.0) <= TOL,
		"_settle_node puts the NPC at the requested world XZ",
		"body global=%s expected (5, ?, -3)" % body.global_position)
	_check(problems, absf(angle_difference(body.global_rotation.y, PI)) <= 0.01,
		"_settle_node applies the authored NPC yaw in world space",
		"body yaw=%.1f deg" % rad_to_deg(body.global_rotation.y))

	var prop := Node3D.new()
	prop.name = "SyntheticProp"
	world.add_child(prop)
	spawner.call("_settle_node", "readable", prop, Vector3(1.0, 2.0, 3.0), 45.0)
	_check(problems, prop.global_position.is_equal_approx(Vector3(1.0, 2.0, 3.0)),
		"_settle_node places a prop at the exact world pin", "prop global=%s" % prop.global_position)
	_check(problems, prop.rotation.is_zero_approx(), "a prop ignores an NPC yaw argument")

	# --- guards: missing pos, non-Array fallbacks, occupied primary -------
	var no_pos: Dictionary = spawner.call("spawn_anchor",
		{"id": "no_pos", "kind": "readable", "map_id": "guildhall"}, "spider") as Dictionary
	_check(problems, no_pos.is_empty(), "an anchor without pos is skipped (never Vector3.ZERO)")
	for rec: Dictionary in spawner.get("actors") as Array:
		_check(problems, str(rec.get("anchor_id", "")) != "no_pos", "no_pos actor was not created")
	var bad_fb: Dictionary = spawner.call("spawn_anchor", {
		"id": "bad_fallbacks", "kind": "readable", "map_id": "guildhall",
		"pos": [note_pin.x + 40.0, note_pin.y, note_pin.z],
		"fallbacks": {"actor": "not_an_array"},
	}, "spider") as Dictionary
	_check(problems, not bad_fb.is_empty(), "non-Array fallbacks are ignored and the primary still spawns",
		"bad_fallbacks was skipped: %s" % str(bad_fb))

	var occupied: Dictionary = spawner.call("spawn_anchor", {
		"id": "occupied_note", "kind": "readable", "map_id": "guildhall",
		"pos": [note_pin.x, note_pin.y, note_pin.z],
		"fallbacks": [{
			"actor": "BP_Readable_ClueSpawner_Guildhall_C_33",
			"pos": [note_pin.x + 30.0, note_pin.y + 0.5, note_pin.z - 12.0],
		}],
	}, "spider") as Dictionary
	_check(problems, str(occupied.get("source", "")) == "fallback",
		"an occupied primary pin uses the authored fallback",
		"occupied source=%s pos=%s" % [str(occupied.get("source", "")), str(occupied.get("pos", Vector3.ZERO))])
	_check(problems, not (spawner.get("actors") as Array).is_empty() and _anchor_ids(spawner) != [],
		"the occupied-pin fallback is recorded")

	# --- Chameleon: zero actors, no record mutation ------------------------
	# Give the Chameleon record a Spider stage in memory only (never
	# `set_personal_quest_stage()`, which would write the developer save), then
	# prove the pass still yields no plan, no actors and an untouched record.
	var live: Dictionary = ss.get("data") as Dictionary
	if not (live.get("personal_quest", null) is Dictionary):
		live["personal_quest"] = {}
	var pq_root: Dictionary = live["personal_quest"] as Dictionary
	pq_root["chameleon"] = {"stage": "intro", "owl": "none", "facts": []}
	_check(problems, PersonalQuestScript.spawn_plan("guildhall", "chameleon").is_empty(),
		"Chameleon spawn_plan() is empty even at a Spider stage")
	# Snapshot after the plan read (which runs the record's normalization) and
	# before the spawn, so the comparison can only see the spawn's own writes.
	var cham_data_before: Dictionary = (ss.get("data") as Dictionary).duplicate(true)
	spawner.call("spawn_for_map", "guildhall", "chameleon")
	_check(problems, (spawner.get("actors") as Array).is_empty(),
		"Chameleon spawn_for_map() spawns zero actors",
		"Chameleon actors=%d" % (spawner.get("actors") as Array).size())
	_check(problems, (ss.get("data") as Dictionary) == cham_data_before,
		"Chameleon spawn mutates no save record")
	var cham_rec: Dictionary = ss.call("get_personal_quest", "chameleon") as Dictionary
	_check(problems, str(cham_rec.get("stage", "")) == "intro" and (cham_rec.get("facts", []) as Array).is_empty()
			and str(cham_rec.get("owl", "none")) == "none",
		"Chameleon record keeps its own stage/facts and no Owl", "Chameleon record=%s" % str(cham_rec))
	_check(problems, str(spawner.get("thief_id")) == "chameleon",
		"the pass binds the thief it was given", "spawner thief=%s" % str(spawner.get("thief_id")))

	# --- restore shared state --------------------------------------------
	ss.set("data", save_backup)
	gs.set("thief_id", gs_thief)
	spawner.call("_release_actors")
	spawner.free()
	world.free()
	return problems


static func _finite_num(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


static func _near(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) <= TOL and absf(a.y - b.y) <= TOL and absf(a.z - b.z) <= TOL


static func _check(problems: Array[String], cond: bool, ok: String, fail: String = "") -> void:
	if cond:
		print("PASS: [pq-settle] ", ok)
	else:
		problems.append(fail if fail != "" else ok)


static func _anchors() -> Array:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPANSION_PATH))
	if doc is Dictionary:
		return (doc as Dictionary).get("anchors", []) as Array
	return []


static func _anchor(anchors: Array, anchor_id: String) -> Dictionary:
	for rec_v: Variant in anchors:
		if rec_v is Dictionary and str((rec_v as Dictionary).get("id", "")) == anchor_id:
			return (rec_v as Dictionary).duplicate(true)
	return {}


static func _anchor_ids(spawner: Node) -> Array[String]:
	var out: Array[String] = []
	for rec_v: Variant in spawner.get("actors") as Array:
		if rec_v is Dictionary:
			out.append(str((rec_v as Dictionary).get("anchor_id", "")))
	return out
