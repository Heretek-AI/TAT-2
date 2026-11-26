extends RefCounted
## Pure guard placement rules (A2.1). Kept engine-free so the standalone unit
## checks can exercise the same code the mission uses, with no world, no
## physics and no scene tree.
##
## A prepared row is one eligible authored marker that passed the 2 m grounding
## skip:
##   {
##     "marker":   Vector3,  # authored MissionSpawner_Character position
##     "grounded": Vector3,  # _ground_position() result (floor + clearance)
##     "hit_y":    float,    # raw floor hit from the same cast
##     "order":    int,      # candidate order (authored array index)
##   }
## `order` is the deterministic tie-break: two candidates on the same storey
## never swap because of dictionary iteration order.
class_name GuardPlacement

## Candidates whose grounded floor is within this many metres of another
## candidate's floor are the same storey for selection.
const STOREY_MERGE_M: float = 5.0
## A marker is only usable when its own downward cast lands within this many
## metres of it. The old +8 m first-hit cast made a ceiling one storey up
## "ground" a guard 7.7 m above its marker.
const GROUND_SKIP_M: float = 2.0


## True when `grounded_y` is a real floor close enough to the authored marker.
## Non-finite values (no hit) are never acceptable.
static func ground_delta_ok(marker_y: float, grounded_y: float, skip_m: float = GROUND_SKIP_M) -> bool:
	return is_finite(grounded_y) and absf(grounded_y - marker_y) <= skip_m


## Cluster rows into storeys by grounded floor height. Sorted floors split on
## a gap larger than `merge_m` (single linkage), so a 4.5 m half-storey joins
## the nearest storey instead of inventing a third one. Members are returned in
## authored candidate order so "first on the storey" is deterministic.
static func cluster_by_storey(rows: Array, merge_m: float = STOREY_MERGE_M) -> Array:
	var sorted_rows: Array = rows.duplicate()
	sorted_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay: float = (a["grounded"] as Vector3).y
		var by: float = (b["grounded"] as Vector3).y
		if not is_equal_approx(ay, by):
			return ay < by
		return int(a.get("order", 0)) < int(b.get("order", 0))
	)
	var clusters: Array = []
	for row_v: Variant in sorted_rows:
		var row: Dictionary = row_v as Dictionary
		var y: float = (row["grounded"] as Vector3).y
		if clusters.is_empty():
			clusters.append([row])
			continue
		var last: Array = clusters[clusters.size() - 1] as Array
		var prev: Dictionary = last[last.size() - 1] as Dictionary
		var prev_y: float = (prev["grounded"] as Vector3).y
		if y - prev_y > merge_m:
			clusters.append([row])
		else:
			last.append(row)
	for cluster_v: Variant in clusters:
		var cluster: Array = cluster_v as Array
		cluster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("order", 0)) < int(b.get("order", 0))
		)
	return clusters


## Storeys at/above the player first (ascending: lowest storey above first),
## then storeys below (nearest first: highest floor first).
static func order_storeys(clusters: Array, anchor_y: float) -> Array:
	var above: Array = []
	var below: Array = []
	for cluster_v: Variant in clusters:
		var cluster: Array = cluster_v as Array
		if cluster.is_empty():
			continue
		var y: float = _storey_y(cluster)
		if y >= anchor_y:
			above.append({"y": y, "cluster": cluster})
		else:
			below.append({"y": y, "cluster": cluster})
	above.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["y"]), float(b["y"])):
			return float(a["y"]) < float(b["y"])
		return int((a["cluster"] as Array)[0].get("order", 0)) < int((b["cluster"] as Array)[0].get("order", 0))
	)
	below.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["y"]), float(b["y"])):
			return float(a["y"]) > float(b["y"])
		return int((a["cluster"] as Array)[0].get("order", 0)) < int((b["cluster"] as Array)[0].get("order", 0))
	)
	var ordered: Array = []
	for entry: Dictionary in above:
		ordered.append(entry["cluster"])
	for entry: Dictionary in below:
		ordered.append(entry["cluster"])
	return ordered


## Pick up to `limit` prepared rows storey-first: one per storey in the order
## above, then a second pass, etc. A storey never loses its first slot to a
## skip because skipped markers are not in `rows` at all; the caller back-fills
## from its skipped list only after this returns fewer than `limit`.
static func pick(rows: Array, anchor_y: float, limit: int, merge_m: float = STOREY_MERGE_M) -> Array[Dictionary]:
	var chosen: Array[Dictionary] = []
	if limit <= 0 or rows.is_empty():
		return chosen
	var clusters: Array = order_storeys(cluster_by_storey(rows, merge_m), anchor_y)
	var used: Dictionary = {}
	var progress: bool = true
	while chosen.size() < limit and progress:
		progress = false
		for cluster_v: Variant in clusters:
			if chosen.size() >= limit:
				break
			for row_v: Variant in (cluster_v as Array):
				var row: Dictionary = row_v as Dictionary
				var key: int = int(row.get("order", 0))
				if used.has(key):
					continue
				used[key] = true
				chosen.append(row)
				progress = true
				break
	return chosen


static func _storey_y(cluster: Array) -> float:
	if cluster.is_empty():
		return NAN
	var acc: float = 0.0
	for row_v: Variant in cluster:
		acc += ((row_v as Dictionary)["grounded"] as Vector3).y
	return acc / float(cluster.size())
