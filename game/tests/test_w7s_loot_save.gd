extends RefCounted
## Suite 90 (W7S-S2): save v8 (save_schema/loot_schema/last_match/
## pending_payout), payout migration and idempotency, and the major-loot mesh
## contract (one instance, authored-off point light stays off).
##
## Save objects are created outside the autoload tree so the developer save is
## only touched by the deliberate write/load round-trip at the end; the
## autoload's data + user:// file are snapshotted and restored.

const SaveScript := preload("res://src/core/save_system.gd")
const LootItemScript := preload("res://src/interact/loot_item.gd")

const LOOT_ACTORS_PATH := "res://data/generated/gameplay/loot_actors.json"

var _save_snap: Dictionary = {}


func run(host: Node) -> Array[String]:
	var problems: Array[String] = []
	_save_snap = (SaveSystem.data as Dictionary).duplicate(true)
	_check_defaults(problems)
	_check_normaliser(problems)
	_check_idempotent_bank(problems)
	_check_free_play_bank(problems)
	_check_pending_recovery(problems)
	_check_migration(problems)
	await _check_major_mesh(host, problems)
	# Put the developer save back exactly as this suite found it.
	SaveSystem.data = _save_snap
	SaveSystem.write_save()
	return problems


func _expect(problems: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		problems.append(msg)


func _new_save() -> Node:
	var sv: Node = SaveScript.new() as Node
	sv.set("data", sv.call("_defaults"))
	return sv


func _read_json(res_path: String) -> Variant:
	if not FileAccess.file_exists(res_path):
		return null
	var f: FileAccess = FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _payout(match_id: String, money: int, free_play: bool = false) -> Dictionary:
	return {
		"match_id": match_id,
		"mission_id": "Mission.Guildhall.VaultHeist",
		"contract_order": 2,
		"map_id": "guildhall",
		"outcome": "escape",
		"original": 1000,
		"kept": 1000,
		"stashed": 250,
		"reward": 1000,
		"score": 1250,
		"money_taken": money,
		"stealth_mult": 1.25,
		"capture": false,
		"free_play": free_play,
		"applied": false,
		"banked": 0,
		"carried": [],
	}


# --------------------------------------------------------------- defaults ---
func _check_defaults(problems: Array[String]) -> void:
	var sv: Node = _new_save()
	var data: Dictionary = sv.get("data") as Dictionary
	_expect(problems, int(data.get("save_schema", 0)) == SaveScript.SAVE_SCHEMA_VERSION, "90.1 save_schema != 8")
	_expect(problems, int(data.get("loot_schema", 0)) == SaveScript.LOOT_SCHEMA_VERSION, "90.2 loot_schema != 1")
	_expect(problems, data.get("last_match") is Dictionary, "90.3 last_match missing")
	_expect(problems, data.get("pending_payout") is Dictionary, "90.4 pending_payout missing")
	var blank: Dictionary = sv.call("_normalise_payout", {})
	for key: String in ["match_id", "original", "kept", "stashed", "reward", "score", "money_taken", "applied", "banked", "carried"]:
		_expect(problems, blank.has(key), "90.5 default payout missing %s" % key)
	sv.free()
	print("PASS: 90 save schema (v8 root stamp, loot schema 1, payout records)")


# ------------------------------------------------------------- normaliser ---
func _check_normaliser(problems: Array[String]) -> void:
	var sv: Node = _new_save()
	var dirty: Dictionary = {
		"match_id": "m-dirty",
		"original": "1000",
		"kept": -5.0,
		"stashed": 250.0,
		"reward": 1000,
		"score": 1250,
		"money_taken": 2500,
		"stealth_mult": 1.25,
		"capture": "yes",
		"free_play": false,
		"applied": true,
		"banked": 2500,
		"evil_key": 99,
		"carried": [
			{"name": "Purse", "value": 45, "tier": "minor", "slot_cost": 1, "is_quest_item": false, "evil": 1},
			{"name": "Bad", "value": 10, "tier": "not_a_tier", "slot_cost": 999},
			"not-a-dict",
		],
	}
	var clean: Dictionary = sv.call("_normalise_payout", dirty)
	_expect(problems, not clean.has("evil_key"), "90.6 normaliser minted an unknown payout key")
	_expect(problems, int(clean.get("original", -1)) == 0, "90.7 string original was coerced instead of dropped")
	_expect(problems, int(clean.get("kept", -1)) == 0, "90.8 negative kept survived")
	_expect(problems, bool(clean.get("capture", true)) == false, "90.9 non-bool capture survived")
	var carried: Array = clean.get("carried", []) as Array
	_expect(problems, carried.size() == 2, "90.10 carried normaliser did not drop the non-dict")
	if carried.size() == 2:
		_expect(problems, not (carried[0] as Dictionary).has("evil"), "90.11 carried minted an unknown key")
		_expect(problems, str((carried[1] as Dictionary).get("tier", "")) == "minor", "90.12 bad carried tier not reset")

	# A merge cannot mint root keys or payout keys.
	var merged: Node = _new_save()
	merged.call("_merge_validated", {
		"totally_new": 1,
		"last_match": {"mint": 2, "match_id": "m1"},
		"pending_payout": {"mint": 3, "match_id": "m2", "money_taken": 500},
	})
	var mdata: Dictionary = merged.get("data") as Dictionary
	_expect(problems, not mdata.has("totally_new"), "90.13 merge minted an unknown root key")
	var lm: Dictionary = mdata.get("last_match", {}) as Dictionary
	var pp: Dictionary = mdata.get("pending_payout", {}) as Dictionary
	_expect(problems, not lm.has("mint") and not pp.has("mint"), "90.14 merge minted an unknown payout key")
	_expect(problems, str(pp.get("match_id", "")) == "m2" and int(pp.get("money_taken", 0)) == 500, "90.15 pending payout fields did not merge")
	sv.free()
	merged.free()
	print("PASS: 90 payout normaliser (typed, bounded, no unknown-key minting)")


# ------------------------------------------------------------ idempotency ---
func _check_idempotent_bank(problems: Array[String]) -> void:
	var sv: Node = _new_save()
	var data: Dictionary = sv.get("data") as Dictionary
	data["currency"] = 0
	var first: Dictionary = sv.call("bank_payout", _payout("match-1", 2500))
	_expect(problems, bool(first.get("applied", false)), "90.16 first payout not applied")
	_expect(problems, int(data.get("currency", -1)) == 2500, "90.17 first payout banked %d != 2500" % int(data.get("currency", -1)))
	var second: Dictionary = sv.call("bank_payout", _payout("match-1", 2500))
	_expect(problems, not bool(second.get("applied", true)), "90.18 duplicate payout applied twice")
	_expect(problems, str(second.get("reason", "")) == "duplicate", "90.19 duplicate reason != duplicate")
	_expect(problems, int(data.get("currency", -1)) == 2500, "90.20 duplicate payout changed currency")
	var last: Dictionary = sv.call("get_last_match")
	_expect(problems, str(last.get("match_id", "")) == "match-1" and bool(last.get("applied", false)), "90.21 last_match not recorded")
	_expect(problems, int(last.get("original", 0)) == 1000 and int(last.get("kept", 0)) == 1000 and int(last.get("stashed", 0)) == 250 and int(last.get("money_taken", 0)) == 2500, "90.22 Original/Kept/Stashed/MoneyTaken not persisted")
	var pending: Dictionary = sv.call("get_pending_payout")
	_expect(problems, str(pending.get("match_id", "")) == "", "90.23 pending payout not cleared after banking")
	sv.free()
	print("PASS: 90 idempotent payout (match_id key, last_match fields)")


func _check_free_play_bank(problems: Array[String]) -> void:
	var sv: Node = _new_save()
	var data: Dictionary = sv.get("data") as Dictionary
	data["currency"] = 123
	var result: Dictionary = sv.call("bank_payout", _payout("free-1", 1500, true))
	_expect(problems, bool(result.get("applied", false)), "90.24 free-play payout not recorded")
	_expect(problems, int(result.get("banked", -1)) == 0, "90.25 free play banked %d != 0" % int(result.get("banked", -1)))
	_expect(problems, int(data.get("currency", -1)) == 123, "90.26 free play changed currency")
	var last: Dictionary = sv.call("get_last_match")
	_expect(problems, bool(last.get("free_play", false)) and int(last.get("money_taken", 0)) == 1500, "90.27 free-play record fields wrong")
	sv.free()
	print("PASS: 90 free play banks nothing (record only)")


# --------------------------------------------------------- crash recovery ---
func _check_pending_recovery(problems: Array[String]) -> void:
	var sv: Node = _new_save()
	var data: Dictionary = sv.get("data") as Dictionary
	data["currency"] = 100
	var staged: Dictionary = sv.call("stage_pending_payout", _payout("crash-1", 700))
	_expect(problems, not bool(staged.get("applied", true)), "90.28 staged payout marked applied")
	_expect(problems, int(sv.call("get_pending_payout").get("money_taken", 0)) == 700, "90.29 staged payout not pending")
	# A fresh save object load_save()s the file staged above: the pending
	# record is settled exactly once.
	var reloaded: Node = SaveScript.new() as Node
	reloaded.set("data", reloaded.call("_defaults"))
	reloaded.call("load_save")
	var rdata: Dictionary = reloaded.get("data") as Dictionary
	_expect(problems, int(rdata.get("currency", -1)) == 800, "90.30 crash recovery banked %d != 800" % int(rdata.get("currency", -1)))
	_expect(problems, str(reloaded.call("get_last_match").get("match_id", "")) == "crash-1", "90.31 recovery did not record last_match")
	_expect(problems, str(reloaded.call("get_pending_payout").get("match_id", "")) == "", "90.32 recovery left the pending record")
	reloaded.call("load_save")
	var rdata2: Dictionary = reloaded.get("data") as Dictionary
	_expect(problems, int(rdata2.get("currency", -1)) == 800, "90.33 second load double-banked the pending payout")
	sv.free()
	reloaded.free()
	print("PASS: 90 pending payout recovery (settled once on reload)")


# ------------------------------------------------------------- migration ---
func _check_migration(problems: Array[String]) -> void:
	# A pre-v8 in-memory record (stamp 0) upgrades in one pass and stamps 8/1.
	var sv: Node = _new_save()
	var data: Dictionary = sv.get("data") as Dictionary
	data["save_schema"] = 0
	data["loot_schema"] = 0
	data["currency"] = 900
	data["last_match"] = {"match_id": "old", "original": 5, "evil": 1}
	data["pending_payout"] = {"match_id": "old-pending", "money_taken": 0, "evil": 2}
	var changed: bool = bool(sv.call("_migrate_save_schema"))
	_expect(problems, changed, "90.34 migration did not report a change")
	_expect(problems, int(data.get("save_schema", 0)) == 8 and int(data.get("loot_schema", 0)) == 1, "90.35 migration did not stamp 8/1")
	var lm: Dictionary = data.get("last_match", {}) as Dictionary
	var pp: Dictionary = data.get("pending_payout", {}) as Dictionary
	_expect(problems, not lm.has("evil") and not pp.has("evil"), "90.36 migration kept unknown payout keys")
	_expect(problems, str(lm.get("match_id", "")) == "old", "90.37 migration lost the last match id")
	var again: bool = bool(sv.call("_migrate_save_schema"))
	_expect(problems, not again, "90.38 migration was not one-shot")
	_expect(problems, int(data.get("currency", 0)) == 900, "90.39 migration touched currency")
	# A newer forward stamp is never downgraded.
	data["save_schema"] = 9
	sv.call("_migrate_save_schema")
	_expect(problems, int(data.get("save_schema", 0)) == 9, "90.40 migration downgraded a newer save_schema")
	sv.free()
	print("PASS: 90 save migration (pre-v8 -> v8, one-shot, no unknown keys)")


# ------------------------------------------------------------ major mesh ---
func _check_major_mesh(host: Node, problems: Array[String]) -> void:
	var actors_data: Variant = _read_json(LOOT_ACTORS_PATH)
	var faberge: Dictionary = {}
	if actors_data is Dictionary:
		var actors: Variant = (actors_data as Dictionary).get("actors", {})
		if actors is Dictionary:
			faberge = (actors as Dictionary).get("BP_LootActor_Major_FabergeEgg_C", {}) as Dictionary
	var mesh: String = str(faberge.get("mesh_res", ""))
	_expect(problems, mesh != "" and FileAccess.file_exists(mesh), "90.41 major loot mesh missing")
	if mesh == "":
		return
	var nodes: Array[Node] = []
	for i: int in range(2):
		var item: Node = LootItemScript.new() as Node
		item.set("loot_tier", "major")
		item.set("is_quest_item", false)
		item.set("value", 1000)
		item.set("item_name", "Jeweled Egg")
		item.set("display_name", "Jeweled Egg")
		item.set("mesh_path", mesh)
		item.set("carry_mesh_path", str(faberge.get("carry_mesh_res", "")))
		item.set("is_large_carry", bool(faberge.get("is_large_carry", false)))
		host.add_child(item)
		nodes.append(item)
	await host.get_tree().process_frame

	for idx: int in range(nodes.size()):
		var item: Node = nodes[idx]
		var root: Node3D = item.get("visual_root") as Node3D
		_expect(problems, root != null, "90.42 major visual root missing")
		if root == null:
			continue
		# Exactly one instantiated visual (never a duplicated GLB instance).
		_expect(problems, root.get_child_count() == 1, "90.43 major loot spawned %d visual roots (expected 1)" % root.get_child_count())
		var meshes: Array[int] = [0]
		var lights: Array[int] = [0]
		_count_render_nodes(root, meshes, lights)
		_expect(problems, meshes[0] >= 1, "90.44 major loot has no MeshInstance3D")
		# BP_LootActor_Major_FabergeEgg authors PointLight bVisible=false; the
		# port spawns no light for loot, so the authored-off indicator stays off.
		_expect(problems, lights[0] == 0, "90.45 major loot spawned %d authored-off light(s)" % lights[0])
		var carry_mesh: String = str(item.get("carry_mesh_path"))
		_expect(problems, carry_mesh != "", "90.46 major loot carry mesh not applied")
		_expect(problems, not bool(item.get("is_large_carry")), "90.47 Faberge wrongly flagged large carry")
		item.queue_free()
	await host.get_tree().process_frame
	print("PASS: 90 major loot mesh (one instance per item, zero authored-off lights)")


func _count_render_nodes(node: Node, meshes: Array[int], lights: Array[int]) -> void:
	if node is MeshInstance3D:
		meshes[0] += 1
	if node is Light3D:
		lights[0] += 1
	for child: Node in node.get_children():
		_count_render_nodes(child, meshes, lights)
