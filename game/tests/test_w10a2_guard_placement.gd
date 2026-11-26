extends SceneTree
## Standalone unit checks for the P0a pure guard-placement helper
## (game/src/missions/guard_placement.gd). Not registered in run_tests.gd: the
## acceptance lane owns suite registration, so this script is run directly:
##
##   tools/godot --headless --path game --script res://tests/test_w10a2_guard_placement.gd
##
## It needs no scene tree, world or physics. Prints one PASS/FAIL line per
## check, then `GUARD_PLACEMENT_SUMMARY: fails=N`, and exits non-zero on any
## failure.

const GP := preload("res://src/missions/guard_placement.gd")

var fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS: ", label)
	else:
		fails += 1
		printerr("FAIL: ", label, (" — " + detail) if detail != "" else "")


func _row(
	order: int,
	bucket: String,
	layers: Array,
	grounded_y: float = 20.0,
	marker_y: float = NAN,
	name: String = ""
) -> Dictionary:
	var my: float = marker_y if is_finite(marker_y) else grounded_y
	return {
		"marker": Vector3(0.0, my, 0.0),
		"grounded": Vector3(0.0, grounded_y, 0.0),
		"hit_y": grounded_y - 0.15,
		"order": order,
		"name": name,
		"spawn_bucket": bucket,
		"spawn_layers": layers.duplicate(),
	}


func _orders(rows: Array) -> Array:
	var out: Array = []
	for row_v: Variant in rows:
		out.append(int((row_v as Dictionary)["order"]))
	return out


## The caller-side eligibility filter, exercised with the same helper the
## mission uses (10-120 m annulus + authored guard bucket).
func _eligible(rows: Array, anchor: Vector3) -> Array:
	var out: Array = []
	for row_v: Variant in rows:
		var row: Dictionary = row_v as Dictionary
		if GP.eligible_spawn(row["marker"] as Vector3, str(row["spawn_bucket"]), anchor):
			out.append(row)
	return out


func _run() -> void:
	# 1. Grounding skip rule: <= 2.0 m usable, > 2.0 m not, non-finite not.
	_check("ground_delta_ok 0.00 m", GP.ground_delta_ok(10.0, 10.0))
	_check("ground_delta_ok 1.99 m", GP.ground_delta_ok(10.0, 8.01))
	_check("ground_delta_ok 2.00 m (inclusive)", GP.ground_delta_ok(10.0, 8.0))
	_check("ground_delta_ok 2.01 m rejected", not GP.ground_delta_ok(10.0, 7.99))
	_check("ground_delta_ok NAN rejected", not GP.ground_delta_ok(10.0, NAN))
	_check("ground_delta_ok INF rejected", not GP.ground_delta_ok(10.0, INF))

	# 2. Bucket normalisation and the authored guard allowlist.
	_check("normalize bare bucket",
		GP.normalize_bucket("StandardGuards_Bouncers") == "StandardGuards_Bouncers")
	_check("normalize authored object name",
		GP.normalize_bucket("TATActorSpawnBucketAsset'DA_SpawnBucket_StandardGuards_Bouncers'")
		== "StandardGuards_Bouncers")
	_check("normalize authored asset path",
		GP.normalize_bucket("/Game/Missions/Spawners/Buckets/DA_SpawnBucket_Hauntstable.0")
		== "Hauntstable")
	_check("guard bucket StandardGuards_Bouncers", GP.is_guard_bucket("StandardGuards_Bouncers"))
	_check("guard bucket StandardGuards_Lanterns", GP.is_guard_bucket("StandardGuards_Lanterns"))
	_check("guard bucket StandardGuards_PrivateSecurity_JasperingHall_Lantern",
		GP.is_guard_bucket("StandardGuards_PrivateSecurity_JasperingHall_Lantern"))
	_check("guard bucket PrivateSecurity", GP.is_guard_bucket("PrivateSecurity"))
	_check("guard bucket PrivateSecurity_Lanterns", GP.is_guard_bucket("PrivateSecurity_Lanterns"))
	_check("guard bucket KeyHolder", GP.is_guard_bucket("KeyHolder"))
	_check("Hauntstable is not a guard bucket", not GP.is_guard_bucket("Hauntstable"))
	_check("civilians are not guard buckets", not GP.is_guard_bucket("Civilians"))
	_check("SmartObject posts are not guard buckets",
		not GP.is_guard_bucket("SmartObject_GuardDefensiveLocation"))
	_check("empty bucket is not a guard bucket", not GP.is_guard_bucket(""))

	# 3. Eligibility: 10-120 m annulus AND a guard bucket.
	_check("eligible_spawn 9.99 m rejected",
		not GP.eligible_spawn(Vector3(0.0, 9.99, 0.0), "StandardGuards_Bouncers", Vector3.ZERO))
	_check("eligible_spawn 10.00 m rejected (exclusive)",
		not GP.eligible_spawn(Vector3(0.0, 10.0, 0.0), "StandardGuards_Bouncers", Vector3.ZERO))
	_check("eligible_spawn 10.01 m accepted",
		GP.eligible_spawn(Vector3(0.0, 10.01, 0.0), "StandardGuards_Bouncers", Vector3.ZERO))
	_check("eligible_spawn 119.99 m accepted",
		GP.eligible_spawn(Vector3(0.0, 119.99, 0.0), "PrivateSecurity", Vector3.ZERO))
	_check("eligible_spawn 120.00 m rejected (exclusive)",
		not GP.eligible_spawn(Vector3(0.0, 120.0, 0.0), "PrivateSecurity", Vector3.ZERO))
	_check("eligible_spawn Hauntstable rejected at 30 m",
		not GP.eligible_spawn(Vector3(0.0, 30.0, 0.0), "Hauntstable", Vector3.ZERO))

	# 4. Layer-first selection on the measured Guildhall Novice candidate order.
	# Authored-order subset: C_100 (SecondFloor_D), C_114 (Tower_D), C_101
	# (SecondFloor_D, duplicate), C_18 (Basement_Storage_A), C_20 (Lounge_A/B),
	# plus C_16 (Hauntstable, Lounge_E) which eligibility must drop.
	var novice_all: Array = [
		_row(3, "StandardGuards_Lanterns", ["Security_SecondFloor_D"], 44.0, NAN, "C_100"),
		_row(16, "Hauntstable", ["Security_GroundFloor_Lounge_E"], 26.2, NAN, "C_16"),
		_row(17, "StandardGuards_Lanterns", ["Security_Tower_D"], 45.0, NAN, "C_114"),
		_row(18, "StandardGuards_Lanterns", ["Security_SecondFloor_D"], 36.0, NAN, "C_101"),
		_row(34, "StandardGuards_Bouncers", ["Security_Basement_Storage_A"], 36.0, NAN, "C_18"),
		_row(37, "StandardGuards_Bouncers", [
			"Security_GroundFloor_Lounge_A",
			"Security_GroundFloor_Lounge_A_Easy",
			"Security_GroundFloor_Lounge_B",
			"Security_GroundFloor_Lounge_B_Easy",
		], 26.1, NAN, "C_20"),
	]
	var novice_eligible: Array = _eligible(novice_all, Vector3.ZERO)
	_check("eligibility drops the Hauntstable C_16 marker",
		not _orders(novice_eligible).has(16), "got %s" % str(_orders(novice_eligible)))
	var novice_pick: Array = GP.pick(novice_eligible, 4)
	_check("layer-first pick is C_100/C_114/C_18/C_20",
		str(_orders(novice_pick)) == str([3, 17, 34, 37]), "got %s" % str(_orders(novice_pick)))
	_check("Novice pick contains the Lounge marker C_20",
		_orders(novice_pick).has(37))
	_check("Novice pick never contains the Hauntstable C_16",
		not _orders(novice_pick).has(16))

	# 5. One per layer, then authored-order fill: the duplicate SecondFloor_D
	# marker (C_101) cannot win a layer slot and only appears as fill.
	var dedupe: Array = [
		_row(0, "StandardGuards_Lanterns", ["L1"], 20.0),
		_row(1, "StandardGuards_Lanterns", ["L1"], 20.0),
		_row(2, "StandardGuards_Lanterns", ["L2"], 20.0),
		_row(3, "StandardGuards_Bouncers", [], 20.0),
	]
	var dedupe_pick: Array = GP.pick(dedupe, 4)
	_check("one per layer, then fill in authored order",
		str(_orders(dedupe_pick)) == str([0, 2, 1, 3]), "got %s" % str(_orders(dedupe_pick)))
	var capped_pick: Array = GP.pick(dedupe, 3)
	_check("layer winners fill the limit before the duplicate layer",
		str(_orders(capped_pick)) == str([0, 2, 1]), "got %s" % str(_orders(capped_pick)))

	# 6. A marker claims every layer it carries, so a shared layer is not
	# selected twice in the layer pass.
	var shared: Array = [
		_row(0, "StandardGuards_Bouncers", ["L1", "L2"], 20.0),
		_row(1, "StandardGuards_Lanterns", ["L2"], 20.0),
		_row(2, "StandardGuards_Lanterns", ["L3"], 20.0),
	]
	var shared_pick: Array = GP.pick(shared, 2)
	_check("shared layer L2 is not double-claimed in the layer pass",
		str(_orders(shared_pick)) == str([0, 2]), "got %s" % str(_orders(shared_pick)))

	# 7. Determinism: the same authored orders in a shuffled input array give
	# the same result, and no-layer rows stay eligible for fill only.
	var shuffled: Array = [novice_eligible[4], novice_eligible[0], novice_eligible[3], novice_eligible[2], novice_eligible[1]]
	var again: Array = GP.pick(shuffled, 4)
	_check("pick: deterministic across input order",
		str(_orders(novice_pick)) == str(_orders(again)), "got %s" % str(_orders(again)))

	# 8. Degenerate inputs never crash and never invent a pick.
	_check("pick: limit 0 is empty", (GP.pick(novice_eligible, 0) as Array).is_empty())
	_check("pick: empty rows is empty", (GP.pick([], 4) as Array).is_empty())

	print("GUARD_PLACEMENT_SUMMARY: fails=%d" % fails)
	quit(1 if fails > 0 else 0)
