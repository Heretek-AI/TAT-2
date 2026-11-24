extends SceneTree
## W3O standalone test for the Spider personal-chain placement policy.
##
## Pure: it never loads a map, spawns an actor or starts a second engine. It
## reads the real expansion pins from `data/expansion/personal_spider.json` and
## calls `personal_quest_spawner.placement_position()` directly, so it answers
## one question without any world:
##
##   readable / quest_item keep the authored pin y (no floor drop);
##   npc / info_npc feet go to floor + 0.02 m;
##   XZ always comes from the pin;
##   a quest item never falls back to the floor (W4O removed the invented y).
##
## The floor constants below are the W2P static-scan surface tops
## (`docs/reports/w2p-subset-probe.md`), not invented values. The Owl's authored
## support is the Vault `SM_Manor_BookcasePedestal` (W4O RE evidence, world top
## 36.4645, pin 36.4655). The real-map subset probe is still the authority for
## collision and that pedestal surface.
##
## Run alone (no GPU, thermal rule still applies):
##
##   tools/godot --headless --path game \
##     --script res://tests/test_personal_quest_spawner.gd
##
## Exits non-zero when a check fails.

var SpawnerScript: GDScript
const PLACE_PIN := "pin"
const PLACE_FLOOR := "floor"
const PLACE_PIN_NO_FLOOR := "pin_no_floor"
const EXPANSION_PATH := "res://data/expansion/personal_spider.json"

## W2P measured walk-surface tops under each authored pin.
const FLOOR_LETTER: float = 28.000
const FLOOR_OWL: float = 35.500
const FLOOR_COURIER: float = 26.000
const FLOOR_INFORMANT: float = 10.050
const CLEARANCE: float = 0.02
const TOL: float = 0.0001
## W4O RE evidence: `SM_Manor_BookcasePedestal` (Guildhall_Gameplay) world top
## under the Owl pin (~36.4645). The pin is 1 mm above it; the walk floor is
## 0.965 m below. The real-map subset probe gates the same value.
const PEDESTAL_TOP_Y: float = 36.4645
const PEDESTAL_TOL_M: float = 0.10

var fails: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, ok: String, fail: String = "") -> void:
	checks += 1
	if cond:
		print("PASS: [pq-place] ", ok)
		return
	fails += 1
	printerr("FAIL: [pq-place] ", fail if fail != "" else ok)


func _anchor_pin(anchors: Array, anchor_id: String) -> Vector3:
	return SpawnerScript.vec3_from(_anchor_record(anchors, anchor_id).get("pos", []))


func _anchor_record(anchors: Array, anchor_id: String) -> Dictionary:
	for rec_v: Variant in anchors:
		if not (rec_v is Dictionary):
			continue
		var rec: Dictionary = rec_v as Dictionary
		if str(rec.get("id", "")) == anchor_id:
			return rec
	return {}


func _placed(result: Dictionary) -> Vector3:
	return result.get("pos", Vector3.ZERO) as Vector3


func _source(result: Dictionary) -> String:
	return str(result.get("y_source", ""))


func _same_xz(result: Dictionary, pin: Vector3) -> bool:
	var pos: Vector3 = _placed(result)
	return absf(pos.x - pin.x) <= TOL and absf(pos.z - pin.z) <= TOL


func _run() -> void:
	SpawnerScript = load("res://src/quests/personal_quest_spawner.gd") as GDScript
	if SpawnerScript == null:
		printerr("PQ-PLACE FAIL: cannot load personal_quest_spawner.gd")
		quit(1)
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPANSION_PATH))
	if not (doc is Dictionary):
		printerr("PQ-PLACE FAIL: cannot read ", EXPANSION_PATH)
		quit(1)
		return
	var anchors: Array = (doc as Dictionary).get("anchors", []) as Array
	_check(anchors.size() == 4, "expansion record carries four authored anchors",
		"anchors=%d" % anchors.size())

	var note: Vector3 = _anchor_pin(anchors, "library_note")
	var owl: Vector3 = _anchor_pin(anchors, "owl")
	var courier: Vector3 = _anchor_pin(anchors, "courier")
	var informant: Vector3 = _anchor_pin(anchors, "informant")
	_check(note != Vector3.ZERO and owl != Vector3.ZERO and courier != Vector3.ZERO and informant != Vector3.ZERO,
		"all four authored pins parsed from the expansion record",
		"missing pin: note=%s owl=%s courier=%s informant=%s" % [note, owl, courier, informant])
	_check(owl.is_equal_approx(Vector3(-31.6286, 36.4655, -43.9759)),
		"Owl pin is the authored BP_QuestSpawner_Item_C_2 origin",
		"Owl pin=%s" % owl)
	_check(absf(owl.y - FLOOR_OWL) > 0.9,
		"Owl pin sits %.3f m over the Vault floor (not a floor point)" % (owl.y - FLOOR_OWL),
		"Owl pin y=%.4f, expected ~0.965 m over floor %.3f" % [owl.y, FLOOR_OWL])

	# --- quest_item (Owl): authored pin, no vertical drop -----------------
	var owl_r: Dictionary = SpawnerScript.placement_position("quest_item", owl, FLOOR_OWL)
	_check(not owl_r.is_empty(), "quest_item places from its authored pin")
	_check(_source(owl_r) == PLACE_PIN, "quest_item uses y_source=pin",
		"quest_item y_source=%s" % _source(owl_r))
	_check(absf(_placed(owl_r).y - owl.y) <= TOL,
		"Owl y == authored pin y (%.4f)" % owl.y,
		"Owl y=%.4f expected pin y=%.4f" % [_placed(owl_r).y, owl.y])
	_check(absf(_placed(owl_r).y - (FLOOR_OWL + CLEARANCE)) > 0.9,
		"Owl is not floor-grounded at floor+0.02",
		"Owl y=%.4f is floor+0.02" % _placed(owl_r).y)
	_check(_same_xz(owl_r, owl), "Owl keeps the authored XZ")
	# The authored surface is the Vault bookcase pedestal, not the walk floor.
	_check(absf(owl.y - PEDESTAL_TOP_Y) <= PEDESTAL_TOL_M,
		"Owl pin rests on the SM_Manor_BookcasePedestal top (%.4f +/- %.2f m)" % [PEDESTAL_TOP_Y, PEDESTAL_TOL_M],
		"Owl pin y=%.4f vs pedestal top %.4f (tolerance %.2f)" % [owl.y, PEDESTAL_TOP_Y, PEDESTAL_TOL_M])

	# --- quest_item has no invented floor fallback (W4O) ------------------
	var owl_no_surface := Vector3(owl.x, NAN, owl.z)
	var owl_quiet: Dictionary = SpawnerScript.placement_position("quest_item", owl_no_surface, FLOOR_OWL)
	_check(owl_quiet.is_empty(), "quest_item with no authored surface is refused (no floor fallback)",
		"quest_item invented a position: %s" % str(owl_quiet))
	var owl_no_floor: Dictionary = SpawnerScript.placement_position("quest_item", owl_no_surface, NAN)
	_check(owl_no_floor.is_empty(), "quest_item with neither surface nor floor is refused",
		"quest_item invented a position with neither surface nor floor: %s" % str(owl_no_floor))

	# --- authored yaw is data, applied only to NPCs by the settle path ----
	var courier_yaw: Variant = _anchor_record(anchors, "courier").get("yaw_deg", null)
	var informant_yaw: Variant = _anchor_record(anchors, "informant").get("yaw_deg", null)
	_check(courier_yaw is float or courier_yaw is int, "courier carries a TAT-2 authored yaw",
		"courier yaw_deg=%s" % str(courier_yaw))
	_check(informant_yaw is float or informant_yaw is int, "04 informant carries a TAT-2 authored yaw",
		"informant yaw_deg=%s" % str(informant_yaw))
	_check(_anchor_record(anchors, "owl").get("yaw_deg", null) == null,
		"Owl anchor has no yaw (its visual root spins)")
	_check(_anchor_record(anchors, "library_note").get("yaw_deg", null) == null,
		"Library note anchor has no yaw (flat on the table)")

	# --- readable (Library note): authored pin, no vertical drop ----------
	var note_r: Dictionary = SpawnerScript.placement_position("readable", note, FLOOR_LETTER)
	_check(not note_r.is_empty() and _source(note_r) == PLACE_PIN,
		"readable uses the authored pin (y_source=pin)",
		"readable=%s" % str(note_r))
	_check(absf(_placed(note_r).y - note.y) <= TOL and _same_xz(note_r, note),
		"letter y == authored pin y (%.4f) with the authored XZ" % note.y,
		"letter pos=%s expected pin=%s" % [_placed(note_r), note])
	var note_no_surface: Dictionary = SpawnerScript.placement_position("readable", Vector3(note.x, NAN, note.z), FLOOR_LETTER)
	_check(note_no_surface.is_empty(), "readable never falls back to the floor",
		"readable invented a floor position: %s" % str(note_no_surface))

	# --- npc / info_npc: feet on the floor + 0.02 m -----------------------
	var courier_r: Dictionary = SpawnerScript.placement_position("npc", courier, FLOOR_COURIER)
	_check(not courier_r.is_empty() and _source(courier_r) == PLACE_FLOOR,
		"courier uses y_source=floor", "courier=%s" % str(courier_r))
	_check(absf(_placed(courier_r).y - (FLOOR_COURIER + CLEARANCE)) <= TOL and _same_xz(courier_r, courier),
		"courier y == floor + 0.02 (%.4f) with the authored XZ" % (FLOOR_COURIER + CLEARANCE),
		"courier pos=%s" % _placed(courier_r))
	_check(absf(_placed(courier_r).y - courier.y) > 0.9,
		"courier is not left at its ~1 m spawner origin",
		"courier y=%.4f still equals the pin y=%.4f" % [_placed(courier_r).y, courier.y])
	var inf_r: Dictionary = SpawnerScript.placement_position("npc", informant, FLOOR_INFORMANT)
	var inf_alias: Dictionary = SpawnerScript.placement_position("info_npc", informant, FLOOR_INFORMANT)
	_check(absf(_placed(inf_r).y - (FLOOR_INFORMANT + CLEARANCE)) <= TOL and _same_xz(inf_r, informant),
		"04 informant y == floor + 0.02 (%.4f) with the authored XZ" % (FLOOR_INFORMANT + CLEARANCE),
		"informant pos=%s" % _placed(inf_r))
	_check(_source(inf_alias) == _source(inf_r) and _placed(inf_alias).is_equal_approx(_placed(inf_r)),
		"info_npc is an alias of the npc floor policy",
		"npc=%s info_npc=%s" % [str(inf_r), str(inf_alias)])
	var npc_no_floor: Dictionary = SpawnerScript.placement_position("npc", courier, NAN)
	_check(_source(npc_no_floor) == PLACE_PIN_NO_FLOOR
			and absf(_placed(npc_no_floor).y - (courier.y + CLEARANCE)) <= TOL,
		"npc without a floor hit reports pin_no_floor explicitly",
		"npc no-floor=%s" % str(npc_no_floor))

	# --- unexpected kinds are rejected ------------------------------------
	_check(SpawnerScript.placement_position("unknown_kind", owl, FLOOR_OWL).is_empty(),
		"unknown kinds are not placed")

	print("PQ-PLACE SUMMARY: fails=", fails, " checks=", checks)
	quit(0 if fails == 0 else 1)
