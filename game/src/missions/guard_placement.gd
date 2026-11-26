extends RefCounted
## Pure guard placement rules (P0a). Kept engine-free so the standalone unit
## checks can exercise the same code the mission uses, with no world, no
## physics and no scene tree.
##
## A prepared row is one eligible authored marker that passed the 2 m grounding
## skip:
##   {
##     "marker":        Vector3,  # authored MissionSpawner_Character position
##     "grounded":      Vector3,  # _ground_position() result (floor + clearance)
##     "hit_y":         float,    # raw floor hit from the same cast
##     "order":         int,      # authored marker index (deterministic tie-break)
##     "name":          String,   # authored marker actor name (C_20 report)
##     "spawn_bucket":  String,   # authored SpawnBucket asset name
##     "spawn_layers":  Array,    # authored Layers entries
##   }
##
## PARITY_APPROX (until a live Contract 02 capture): the shipped game chooses a
## guard from an authored SpawnBucket/Layers pair. This port selects one marker
## per authored layer first, then fills from the remaining guard-bucket markers
## in authored order. The 4/6/8 difficulty count is a labelled PORT_DECISION.
class_name GuardPlacement

## Authored guard buckets. The producer emits the asset name
## (`DA_SpawnBucket_` prefix included); `normalize_bucket()` strips both that
## prefix and any object-name/path wrapper. `PrivateSecurity` / `StandardGuards`
## without a suffix are authored buckets too (Old Manor uses the former).
const GUARD_BUCKET_PREFIXES: Array[String] = ["StandardGuards_", "PrivateSecurity_"]
const GUARD_BUCKET_EXACT: Array[String] = ["KeyHolder", "PrivateSecurity", "StandardGuards"]
const SPAWN_MIN_M: float = 10.0
const SPAWN_MAX_M: float = 120.0
## A marker is only usable when its own downward cast lands within this many
## metres of it. The old +8 m first-hit cast made a ceiling one storey up
## "ground" a guard 7.7 m above its marker.
const GROUND_SKIP_M: float = 2.0


## Accept the producer's bare asset name and the authored object name/path.
## `DA_SpawnBucket_StandardGuards_Bouncers` -> `StandardGuards_Bouncers`.
static func normalize_bucket(bucket: String) -> String:
	var b: String = bucket.strip_edges()
	if b == "":
		return ""
	var quote: int = b.find("'")
	if quote >= 0:
		var rest: String = b.substr(quote + 1)
		var close: int = rest.find("'")
		b = rest.substr(0, close) if close >= 0 else rest
	b = b.get_file().split(".")[0]
	if b.begins_with("DA_SpawnBucket_"):
		b = b.substr("DA_SpawnBucket_".length())
	return b


## True only for an authored guard bucket. Hauntstable, civilians and
## SmartObject defensive posts are deliberately excluded.
static func is_guard_bucket(bucket: String) -> bool:
	var b: String = normalize_bucket(bucket)
	if b == "":
		return false
	if GUARD_BUCKET_EXACT.has(b):
		return true
	for prefix: String in GUARD_BUCKET_PREFIXES:
		if b.begins_with(prefix):
			return true
	return false


## True when `grounded_y` is a real floor close enough to the authored marker.
## Non-finite values (no hit) are never acceptable.
static func ground_delta_ok(marker_y: float, grounded_y: float, skip_m: float = GROUND_SKIP_M) -> bool:
	return is_finite(grounded_y) and absf(grounded_y - marker_y) <= skip_m


## Eligibility is the authored 10-120 m annulus AND a guard SpawnBucket.
static func eligible_spawn(marker: Vector3, bucket: String, anchor: Vector3) -> bool:
	if not is_guard_bucket(bucket):
		return false
	var d: float = marker.distance_to(anchor)
	return d > SPAWN_MIN_M and d < SPAWN_MAX_M


## Deterministic authored-layer-aware selection:
##   1. one marker per authored `spawn_layer`, in authored order (a marker
##      claims every layer it carries, so a shared layer is never doubled);
##   2. fill from the remaining eligible guard-bucket markers in authored order.
## No storey merge: the 5 m floor clustering collapsed an 18-marker chain and
## let a Hauntstable marker stand in for the authored Lounge guard.
static func pick(rows: Array, limit: int) -> Array[Dictionary]:
	var chosen: Array[Dictionary] = []
	if limit <= 0 or rows.is_empty():
		return chosen
	var ordered: Array = rows.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 0)) < int(b.get("order", 0))
	)
	var used_layers: Dictionary = {}
	var chosen_idx: Dictionary = {}
	for idx: int in range(ordered.size()):
		if chosen.size() >= limit:
			break
		var row: Dictionary = ordered[idx] as Dictionary
		var layers_v: Variant = row.get("spawn_layers", [])
		if not (layers_v is Array):
			continue
		var fresh: bool = false
		for layer_v: Variant in (layers_v as Array):
			var layer: String = str(layer_v)
			if layer != "" and not used_layers.has(layer):
				fresh = true
				break
		if not fresh:
			continue
		chosen.append(row)
		chosen_idx[idx] = true
		for layer_v: Variant in (layers_v as Array):
			var layer: String = str(layer_v)
			if layer != "":
				used_layers[layer] = true
	if chosen.size() < limit:
		for idx: int in range(ordered.size()):
			if chosen.size() >= limit:
				break
			if chosen_idx.has(idx):
				continue
			chosen.append(ordered[idx] as Dictionary)
	return chosen
