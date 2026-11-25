class_name MapBoundaries
extends RefCounted
## Authored `TATWorldMapBoundary` reader for the `[TAB]` map (W9-P3-C4).
##
## The shipped world map is not a hand-drawn screen: each map's persistent level
## carries `TATWorldMapBoundary` actors (a C++ `UBoxComponent` root) that define
## a floor's world rect and its authored label. The full set is 13 actors:
##   Guildhall_P     TATWorldMapBoundary_0/1/2/3/5  (Constables' Guildhall,
##                   First Floor, Second Floor, Rooftop, Basement)
##   OldManor_P      _1/_4/_5/_6/_7/_8             (Elway Manor, Ground Floor,
##                   2nd Floor, 3rd Floor, Tower, Basement)
##   FTUE_P          _0                             (Kilcairn Back Alley)
##   ThievesDenTest_P _1                            (no MapLabel)
## Each actor authors `MapLabel` (a StringTable ref or a locres GUID),
## `MapType` (Primary/Secondary), `MapTextureAnchorTopLeft/BottomRight` and
## `MapRenderTextureHeightOffset`; the BoxComponent's transform + scale place
## the floor rect in the world. `BoxExtent` is not serialized: the class default
## is 100 cm (verified against the map extent — Guildhall_P's mesh pivots span
## 228 x 113 m and boundary_0 is 100 cm x 117.5 scale = 235 m full), so the
## producer emits `size` as the FULL extent in Godot metres.
##
## The generated `*.tatlevel.json` does not carry these actors yet — the
## producer contract is `build/qa/w9/parse_tables-map-boundaries.patch`
## (`tools/parse_tables.py`, integrator regeneration). This reader consumes the
## `map_boundaries` array as soon as it exists and returns an empty array today,
## which the HUD reports as `fallback` (the player-centred 64 m window is the
## port's labelled stand-in, not authored data).
##
## Citations: extracted/json/Maps/{Guildhall,OldManor,FTUE,ThievesDenTest}/*_P.json;
## extracted/json/UI/MapTool/BPUI_MapToolDisplay.json; ST_MapTool / ST_OldManor_map.

## Map id -> persistent level payload. The port's GameState.active_map_id values.
## PORT DECISION: the loader resolves the same persistent level through
## mission_controller's per-map sublevel lists; this table only names the JSON
## file the boundaries live in so the HUD does not have to duplicate the loader.
const LEVEL_FOR_MAP: Dictionary = {
	"guildhall": "res://data/generated/levels/Guildhall/Guildhall_P.tatlevel.json",
	"old_manor": "res://data/generated/levels/OldManor/OldManor_P.tatlevel.json",
	"ftue": "res://data/generated/levels/FTUE/FTUE_P.tatlevel.json",
	"thieves_den": "res://data/generated/levels/ThievesDenTest/ThievesDenTest_P.tatlevel.json",
}

## Authored map render texture size (the anchors are 0..2048 px in the dump;
## Guildhall 315,621 -> 1712,1679 and OldManor 451,577 -> 1598,1724).
const MAP_TEXTURE_SIZE: float = 2048.0

static var _cache: Dictionary = {}


static func level_path(map_id: String) -> String:
	return str(LEVEL_FOR_MAP.get(map_id.strip_edges().to_lower(), ""))


## Boundary records for a map. Empty when the payload does not carry the
## producer's `map_boundaries` array (today) or the file is missing.
static func for_map(map_id: String) -> Array[Dictionary]:
	var key: String = map_id.strip_edges().to_lower()
	if _cache.has(key):
		return _cached_array(key)
	var path: String = level_path(key)
	var out: Array[Dictionary] = []
	if path != "" and FileAccess.file_exists(path):
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				out = parse(parsed as Dictionary)
	_cache[key] = out
	return _cached_array(key)


static func _cached_array(key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rows_v: Variant = _cache.get(key, [])
	if rows_v is Array:
		for r_v: Variant in (rows_v as Array):
			if r_v is Dictionary:
				out.append(r_v as Dictionary)
	return out


## Parse the producer's `map_boundaries` array. Pure and defensive: every field
## is optional, a malformed row is skipped, and the array is returned in level
## order. A test feeds a synthetic payload through this.
static func parse(doc: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rows_v: Variant = doc.get("map_boundaries", [])
	if not (rows_v is Array):
		return out
	for row_v: Variant in (rows_v as Array):
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		var pos: Vector3 = _vec3(row.get("pos", []))
		var size: Vector3 = _vec3(row.get("size", []), Vector3(16.0, 0.5, 16.0))
		var rec: Dictionary = {
			"name": str(row.get("name", "")),
			"pos": pos,
			"size": size,
			"label_source": str(row.get("label_source", "")),
			"label_key": str(row.get("label_key", "")),
			"label_table": _table_stem(str(row.get("label_table", ""))),
			"map_type": str(row.get("map_type", "")),
			"primary": bool(row.get("primary", str(row.get("map_type", "")) == "")),
			"anchor_top_left": _vec2(row.get("anchor_top_left", [])),
			"anchor_bottom_right": _vec2(row.get("anchor_bottom_right", [])),
			"texture_height_offset": float(row.get("texture_height_offset", 0.0)),
		}
		if rec["name"] == "" and rec["label_source"] == "" and rec["label_key"] == "":
			continue
		out.append(rec)
	return out


static func _table_stem(table_id: String) -> String:
	# "/Game/StringTables/ST_MapTool.ST_MapTool" -> "ST_MapTool"
	var t: String = table_id.strip_edges()
	if t == "":
		return ""
	var dot: int = t.rfind(".")
	if dot >= 0:
		t = t.substr(dot + 1)
	var slash: int = t.rfind("/")
	if slash >= 0:
		t = t.substr(slash + 1)
	return t


static func _vec3(raw: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func _vec2(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		var a: Array = raw as Array
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


## Authored label of a boundary: a StringTable row when the actor names one,
## else the locres source string, else the actor name (never invented prose).
static func label_for(boundary: Dictionary) -> String:
	if boundary.is_empty():
		return ""
	var table: String = str(boundary.get("label_table", ""))
	var key: String = str(boundary.get("label_key", ""))
	if table != "" and key != "":
		var row: String = UIStrings.st_text(table, key, "")
		if row != "":
			return row
	var source: String = str(boundary.get("label_source", ""))
	if source != "":
		return UIStrings.loc(source)
	return str(boundary.get("name", ""))


## The primary boundary (the map capture volume; `MapType` empty/Primary) — its
## XZ box is the authored map extent.
static func primary_for(boundaries: Array[Dictionary]) -> Dictionary:
	for b: Dictionary in boundaries:
		if bool(b.get("primary", false)):
			return b
	return {} if boundaries.is_empty() else boundaries[0]


## Boundary whose authored box contains the player (Y included), else the
## primary boundary, else the first. Empty when the map has no authored data.
## The primary actor is a thin slab at the map-capture height (Guildhall
## _0 at y 67.3 m), so a player never falls inside it; the floor boxes are the
## secondaries. Prefer a containing secondary, then the primary.
static func boundary_at(boundaries: Array[Dictionary], player_pos: Vector3) -> Dictionary:
	if boundaries.is_empty():
		return {}
	for b: Dictionary in boundaries:
		if bool(b.get("primary", false)):
			continue
		if contains(b, player_pos):
			return b
	var prim: Dictionary = primary_for(boundaries)
	if not prim.is_empty():
		return prim
	return boundaries[0]


static func contains(boundary: Dictionary, p: Vector3) -> bool:
	var c: Vector3 = boundary.get("pos", Vector3.ZERO) as Vector3
	var s: Vector3 = boundary.get("size", Vector3.ZERO) as Vector3
	if s.x <= 0.01 or s.z <= 0.01:
		return false
	# `size` is the FULL extent. The boxes are floor volumes (Guildhall _1 is
	# 14 m tall, the primary capture slab 2 m); allow 3 m below and 1 m above
	# the volume so a player on the stairs still reads as on that floor.
	var half_y: float = maxf(s.y * 0.5, 0.25)
	var y_ok: bool = p.y >= c.y - half_y - 3.0 and p.y <= c.y + half_y + 1.0
	return y_ok and absf(p.x - c.x) <= s.x * 0.5 and absf(p.z - c.z) <= s.z * 0.5


## The authored render-texture placement as a normalized rect (0..1) inside the
## map widget: anchors are 0..2048 px in the dump. A degenerate pair returns a
## full-rect so a partial row still draws.
static func anchor_rect(boundary: Dictionary) -> Rect2:
	var tl: Vector2 = boundary.get("anchor_top_left", Vector2.ZERO) as Vector2
	var br: Vector2 = boundary.get("anchor_bottom_right", Vector2.ZERO) as Vector2
	if br.x > tl.x and br.y > tl.y:
		return Rect2(tl / MAP_TEXTURE_SIZE, (br - tl) / MAP_TEXTURE_SIZE)
	return Rect2(0.0, 0.0, 1.0, 1.0)


## Diagnostic for tests/report: "authored" when the producer emitted rows,
## "fallback" when the HUD is using its invented player-centred window.
static func source_for_map(map_id: String) -> String:
	return "authored" if not for_map(map_id).is_empty() else "fallback"


## Test hook: drop the per-map cache.
static func clear_cache() -> void:
	_cache.clear()
