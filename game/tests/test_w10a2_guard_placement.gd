extends SceneTree
## Standalone unit checks for the A2 pure guard-placement helper
## (game/src/missions/guard_placement.gd). Not registered in run_tests.gd: the
## acceptance lane owns suite 117, so this script is run directly:
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


func _row(order: int, grounded_y: float, marker_y: float = NAN) -> Dictionary:
	var my: float = marker_y if is_finite(marker_y) else grounded_y
	return {
		"marker": Vector3(0.0, my, 0.0),
		"grounded": Vector3(0.0, grounded_y, 0.0),
		"hit_y": grounded_y - 0.15,
		"order": order,
	}


func _orders(rows: Array) -> Array:
	var out: Array = []
	for row_v: Variant in rows:
		out.append(int((row_v as Dictionary)["order"]))
	return out


func _run() -> void:
	# 1. Grounding skip rule: <= 2.0 m usable, > 2.0 m not, non-finite not.
	_check("ground_delta_ok 0.00 m", GP.ground_delta_ok(10.0, 10.0))
	_check("ground_delta_ok 1.99 m", GP.ground_delta_ok(10.0, 8.01))
	_check("ground_delta_ok 2.00 m (inclusive)", GP.ground_delta_ok(10.0, 8.0))
	_check("ground_delta_ok 2.01 m rejected", not GP.ground_delta_ok(10.0, 7.99))
	_check("ground_delta_ok NAN rejected", not GP.ground_delta_ok(10.0, NAN))
	_check("ground_delta_ok INF rejected", not GP.ground_delta_ok(10.0, INF))

	# 2. Storey clustering: merge within 5.0 m (inclusive), split above; single
	# linkage means a chain of near floors is one storey.
	var clusters: Array = GP.cluster_by_storey([
		_row(0, 10.0), _row(1, 14.9), _row(2, 20.1),
	])
	_check("clusters: 10.0 + 14.9 same storey, 20.1 separate", clusters.size() == 2,
		"sizes=%s" % str(clusters.map(func(c: Array) -> int: return c.size())))
	var chain: Array = GP.cluster_by_storey([_row(0, 10.0), _row(1, 14.9), _row(2, 19.8)])
	_check("clusters: single linkage chain 10/14.9/19.8 is one storey", chain.size() == 1,
		"size=%d" % chain.size())
	var exact_five: Array = GP.cluster_by_storey([_row(0, 10.0), _row(1, 15.0)])
	_check("clusters: exactly 5.0 m merges", exact_five.size() == 1)

	# 3. Storey order: at/above the player ascending, then below nearest first.
	var ordered: Array = GP.order_storeys(GP.cluster_by_storey([
		_row(0, -10.0), _row(1, 5.0), _row(2, 20.0), _row(3, -3.0),
	]), 0.0)
	var ordered_y: Array = []
	for cluster_v: Variant in ordered:
		ordered_y.append(float((cluster_v as Array)[0]["grounded"].y))
	_check("storeys above-first ascending then below nearest-first",
		str(ordered_y) == str([5.0, 20.0, -3.0, -10.0]), "got %s" % str(ordered_y))

	# 4. One per storey, then a second pass (limit 5 over 3 storeys).
	var two_each: Array = [
		_row(0, 10.0), _row(1, 10.0),
		_row(2, 20.0), _row(3, 20.0),
		_row(4, 30.0), _row(5, 30.0),
	]
	var picked: Array = GP.pick(two_each, 5.0, 5)
	_check("pick: one per storey then second pass",
		str(_orders(picked)) == str([0, 2, 4, 1, 3]), "got %s" % str(_orders(picked)))

	# 5. Authored order is the deterministic tie-break inside a storey, even
	# when the input rows arrive in another order.
	var shuffled: Array = [_row(4, 35.6), _row(3, 35.6), _row(1, 26.1)]
	var tie_pick: Array = GP.pick(shuffled, 23.0, 2)
	_check("pick: same-storey winner uses authored order, not input order",
		str(_orders(tie_pick)) == str([1, 3]), "got %s" % str(_orders(tie_pick)))

	# 6. Novice Guildhall model (measured floors from the A2 static model):
	# C_16 26.165, C_20 26.150, C_100/101 35.683, C_114 45.202, C_118 53.702,
	# anchor y 23.31. Prediction: 16, 100, 114, 118.
	var novice: Array = [
		_row(0, 35.683),   # C_100
		_row(1, 35.683),   # C_101
		_row(2, 53.702),   # C_118
		_row(3, 26.165),   # C_16
		_row(4, 26.150),   # C_20
		_row(5, 45.202),   # C_114
		_row(6, 18.768),   # below-anchor storey
	]
	var novice_pick: Array = GP.pick(novice, 23.3085, 4)
	_check("pick: Novice prediction is storey-first 16/100/114/118",
		str(_orders(novice_pick)) == str([3, 0, 5, 2]), "got %s" % str(_orders(novice_pick)))

	# 7. Determinism: the same input twice gives the same result.
	var again: Array = GP.pick(novice, 23.3085, 4)
	_check("pick: deterministic across runs",
		str(_orders(novice_pick)) == str(_orders(again)))

	# 8. Degenerate inputs never crash and never invent a pick.
	_check("pick: limit 0 is empty", (GP.pick(novice, 23.0, 0) as Array).is_empty())
	_check("pick: empty rows is empty", (GP.pick([], 23.0, 4) as Array).is_empty())

	print("GUARD_PLACEMENT_SUMMARY: fails=%d" % fails)
	quit(1 if fails > 0 else 0)
