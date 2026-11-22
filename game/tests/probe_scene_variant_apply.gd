extends SceneTree
## #11 application probe: deterministic exact-tag + class-map overrides.

func _init() -> void:
	call_deferred("_run")


func _make_stats(door_count: int) -> Dictionary:
	var doors: Array = []
	for i: int in range(door_count):
		doors.append({
			"name": "Door_%d" % i,
			"actor": "Actor_%d" % i,
			"pos": [float(i), 0.0, 0.0],
		})
	return {
		"guard_spawns": [] as Array[Vector3],
		"loot_spawns": [] as Array[Vector3],
		"door_spawns": [] as Array[Vector3],
		"civilian_spawns": [] as Array[Vector3],
		"major_loot_spawns": [] as Array,
		"minor_loot_spawns": [] as Array,
		"swinging_doors": doors,
		"scene_element_spawns": [] as Array,
	}


func _locked_flags(stats: Dictionary) -> Array:
	var flags: Array = []
	for d: Variant in stats.get("swinging_doors", []):
		if d is Dictionary:
			flags.append(bool((d as Dictionary).get("scene_locked", false)))
	return flags


func _run() -> void:
	var ll: Node = (load("res://src/core/level_loader.gd") as GDScript).new()
	root.add_child(ll)
	await process_frame

	# Never -> every door unlocked.
	var s_never: Dictionary = _make_stats(40)
	var o_never: Dictionary = ll.call("apply_scene_variant_overrides", "guildhall", 4242, ["SV_Apartment_Lower_Open"] as Array[String], s_never) as Dictionary
	var never_flags: Array = _locked_flags(s_never)
	var never_ok: bool = never_flags.size() == 40 and int(o_never.get("locked", 0)) == 0
	for f: Variant in never_flags:
		if bool(f):
			never_ok = false
			break

	# OverrideChance: deterministic for the same seed, different for another.
	var s_a: Dictionary = _make_stats(40)
	var s_b: Dictionary = _make_stats(40)
	var s_c: Dictionary = _make_stats(40)
	var o_a: Dictionary = ll.call("apply_scene_variant_overrides", "guildhall", 4242, ["SV_Apartment_Balcony_1A_Closed"] as Array[String], s_a) as Dictionary
	var o_b: Dictionary = ll.call("apply_scene_variant_overrides", "guildhall", 4242, ["SV_Apartment_Balcony_1A_Closed"] as Array[String], s_b) as Dictionary
	var o_c: Dictionary = ll.call("apply_scene_variant_overrides", "guildhall", 9999, ["SV_Apartment_Balcony_1A_Closed"] as Array[String], s_c) as Dictionary
	var flags_a: Array = _locked_flags(s_a)
	var flags_b: Array = _locked_flags(s_b)
	var flags_c: Array = _locked_flags(s_c)
	var chance_ok: bool = flags_a == flags_b and flags_a != flags_c \
		and int(o_a.get("locked", 0)) > 0 and int(o_a.get("locked", 0)) < 40

	# Always keep: Quest/MajorLoot exact authored tags are not suppressed.
	var s_quest: Dictionary = _make_stats(1)
	(s_quest["scene_element_spawns"] as Array).append({
		"kind": "quest",
		"name": "Quest_0",
		"pos": [3.0, 0.0, 0.0],
		"element_tag": "MapVariation.SceneElement.Quest",
	})
	(s_quest["loot_spawns"] as Array[Vector3]).append(Vector3(3, 0, 0))
	var o_quest: Dictionary = ll.call("apply_scene_variant_overrides", "guildhall", 4242, ["SV_POI_Example_VaultA_Quest"] as Array[String], s_quest) as Dictionary
	var quest_ok: bool = int(o_quest.get("suppressed", 0)) == 0 and int(o_quest.get("applied", 0)) >= 1

	# Per-source (LevelInstance building) selection: no global IDs are passed,
	# yet the apartment scene variant's Locks.Doors override applies because the
	# door records carry their source map.
	var s_src: Dictionary = _make_stats(20)
	for d_var: Variant in s_src["swinging_doors"]:
		if d_var is Dictionary:
			(d_var as Dictionary)["source"] = "Buildings/Apartment_Balcony/Apartment_Balcony_Geo.json"
	var o_src: Dictionary = ll.call("apply_scene_variant_overrides", "guildhall", 4242, [] as Array[String], s_src) as Dictionary
	var src_locked: int = int(o_src.get("locked", 0))
	var src_ok: bool = int(o_src.get("source_variants", 0)) > 0 and src_locked > 0 and src_locked < 20

	# Static override semantics.
	var never_applies: bool = bool(ll.call("_sv_override_applies", "ETATSceneSpawnerOverrideType::Never", 100.0, 1, "x", "t"))
	var always_applies: bool = bool(ll.call("_sv_override_applies", "ETATSceneSpawnerOverrideType::Always", 100.0, 1, "x", "t"))
	var semantics_ok: bool = (not never_applies) and always_applies

	if not never_ok or not chance_ok or not quest_ok or not src_ok or not semantics_ok:
		printerr("SV_APPLY PROBE FAIL never=", never_ok, " chance=", chance_ok, " quest=", quest_ok, " source=", src_ok, " semantics=", semantics_ok, " locked_a=", o_a.get("locked", 0), " locked_c=", o_c.get("locked", 0), " src_locked=", src_locked)
		quit(1)
		return
	print("SV_APPLY PROBE PASS locked=", o_a.get("locked", 0), "/40 deterministic=true varies_by_seed=true quest_applied=", o_quest.get("applied", 0), " source_locked=", src_locked, "/20")
	quit(0)
