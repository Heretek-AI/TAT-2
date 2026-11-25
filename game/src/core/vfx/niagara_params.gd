extends RefCounted
## Decoder for the authored Niagara component overrides that the level records
## point at (T12-VFX, RE-E-03 / RE-E-04).
##
## A UE5 `NiagaraComponent` serialises its per-instance override set as a raw
## byte buffer plus an inline schema:
##
##     Properties.OverrideParameters = {
##         "UserParameterRedirects": [{Key{Name,TypeDef}, Value{Name,TypeDef}}, ...],
##         "SortedParameterOffsets": [{Name, TypeDef, Offset}, ...],
##         "ParameterData": [byte, byte, ...],
##     }
##
## so the buffer is self-describing: each `SortedParameterOffsets` row gives the
## parameter name, its type and its little-endian offset. Decoding needs no
## cook, no VM and no guesswork - it is a struct read. `bAutoActivate` sits next
## to it on the same component and is the authored activation flag.
##
## The loader only needs the components whose Blueprint is referenced by a
## Niagara placement in the level being loaded, so `prepare()` opens at most a
## few dozen files per map and caches them for the process.

## Little-endian byte size per authored type. Unknown types are skipped and
## counted (never guessed).
const TYPE_SIZES: Dictionary = {
	"Vector4f": 16,
	"Vector4": 16,
	"LinearColor": 16,
	"Color": 16,
	"Quat": 16,
	"Vector": 12,
	"Vector3f": 12,
	"Vector2f": 8,
	"Vector2D": 8,
	"NiagaraFloat": 4,
	"Float": 4,
	"NiagaraInt32": 4,
	"Int32": 4,
	"NiagaraBool": 4,
	"Bool": 4,
}

## Candidate roots for the JSON dump, in priority order. The port is private-use
## and already links `game/assets/ue/Raw` -> `extracted/assets`, so the JSON
## sibling of that tree is the normal dev-tree location; an exported build has
## none of them and falls back to the authored colours in `systems.json` only.
const ROOT_CANDIDATES: Array[String] = [
	"res://assets/ue/Raw/../json",
	"res://../extracted/json",
]

## Systems whose placed components carry an explicit `bAutoActivate = False`
## somewhere in the extraction, i.e. the build turns them on from Blueprint when
## a device changes state (turret destroyed, door broken, eye alerted, goo pipe
## opened). Verified against all 12,541 extracted JSON files by
## `probe_niagara.gd --verify-activation` (30 systems, 30 negatives, 2 positives).
## A placement whose own component states a flag always wins over this table.
const EVENT_GATED_SYSTEMS: Array[String] = [
	"ne_respawnritual",
	"ns_candelabras_flame_out",
	"ns_chestbreakdust",
	"ns_disguisedcoopplayer",
	"ns_doorbreakdust",
	"ns_escapepoint",
	"ns_featherfall",
	"ns_goopipe_enabled",
	"ns_gootrails",
	"ns_knockoutgas",
	"ns_lootattract_shine",
	"ns_lootaura",
	"ns_lootglint",
	"ns_magicmarker_footstep",
	"ns_noisealarm_targeteffect",
	"ns_pickpocket_spawn",
	"ns_powersupplywall_brokenstate",
	"ns_powersupply_electrify",
	"ns_securityeye_alerted",
	"ns_securityeye_spotted",
	"ns_securityturret_desactivated",
	"ns_securityturret_destruction",
	"ns_stamina_bomb",
	"ns_throwpath",
	"ns_tutorialfairy_spawn",
	"ns_wardzone_shards",
	"ns_watersinking_center",
	"ns_watersinking_left",
	"ns_watersinking_right",
	"ns_wirespline_electrify_idle",
]

static var _root: String = ""
static var _root_probed: bool = false
static var _files: Dictionary = {}
static var _file_stats: Dictionary = {}


## Normalised asset key: case- and underscore-insensitive, because the catalogue
## records `NS_Fireplace` for the file `NS_FirePlace` (RE-E-01).
static func asset_key(path: String) -> String:
	return path.get_file().to_lower().replace("_", "")


## The directory holding `extracted/json`, or "" when the extraction is absent.
## Resolves through the `Raw -> extracted/assets` link, so `../json` is a sibling.
static func extraction_json_root() -> String:
	if _root_probed:
		return _root
	_root_probed = true
	for cand: String in ROOT_CANDIDATES:
		var dir: DirAccess = DirAccess.open(cand)
		if dir != null:
			_root = cand
			return _root
	# Environment escape hatch for a relocated extraction (dev only).
	var env: String = OS.get_environment("TAT2_EXTRACTED_JSON")
	if env != "":
		var dir2: DirAccess = DirAccess.open(env)
		if dir2 != null:
			_root = env
	return _root


## True when [param name] is in the authored event-gated set. Compared on the
## plain lower-case file name, because the table is written the way the assets
## are named (`NS_DoorBreakDust`) while [method asset_key] strips underscores.
static func is_event_gated(name: String) -> bool:
	return EVENT_GATED_SYSTEMS.has(name.get_file().to_lower())


## Load every Blueprint JSON referenced by [param sources] and decode the
## Niagara components in it. Returns a handle for [method resolve]:
##     {"root": String, "files": {rel: [comp, ...]}, "stats": {...}}
## where a comp is {"actor", "asset", "auto", "params"}.
static func prepare(sources: Array) -> Dictionary:
	var handle: Dictionary = {"root": extraction_json_root(), "files": {}, "stats": {}}
	var files: Dictionary = {}
	var missing: int = 0
	for s: Variant in sources:
		var rel: String = str(s)
		if rel == "" or files.has(rel):
			continue
		if handle["root"] == "":
			missing += 1
			continue
		var comps: Array = _load_file(str(handle["root"]).path_join(rel))
		if comps.is_empty() and not FileAccess.file_exists(str(handle["root"]).path_join(rel)):
			missing += 1
			continue
		files[rel] = comps
	handle["files"] = files
	var st: Dictionary = {"root": handle["root"], "files_requested": sources.size(),
		"files_loaded": files.size(), "files_missing": missing}
	if handle["root"] == "":
		st["files_missing"] = sources.size()
	handle["stats"] = st
	return handle


## Resolve one placement record to its authored activation flag and parameters.
## Returns {"matched": bool, "auto": Variant (bool or null), "params": Dictionary}.
## `matched` is false when the placement's Blueprint has no own component for the
## asset (inherited components on a parent BP are not chased: see the report).
static func resolve(handle: Dictionary, rec: Dictionary) -> Dictionary:
	var out: Dictionary = {"matched": false, "auto": null, "params": {}}
	var files: Dictionary = handle.get("files", {}) as Dictionary
	if files.is_empty():
		return out
	var src: String = str(rec.get("source", ""))
	var sep: int = src.find("::")
	var file: String = src.substr(0, sep) if sep >= 0 else src
	if file == "" or not files.has(file):
		return out
	var want: String = asset_key(str(rec.get("asset", "")))
	var first_params: Dictionary = {}
	var auto: Variant = null
	for c_v: Variant in (files[file] as Array):
		var c: Dictionary = c_v as Dictionary
		if asset_key(str(c.get("asset", ""))) != want:
			continue
		out["matched"] = true
		if c.get("auto") is bool:
			if not bool(c["auto"]):
				auto = false
			elif auto == null:
				auto = true
		var p: Dictionary = c.get("params", {}) as Dictionary
		if first_params.is_empty() and not p.is_empty():
			first_params = p
	out["auto"] = auto
	out["params"] = first_params
	return out


## Decode `Properties.OverrideParameters` of one NiagaraComponent export.
## Returns {param_name: Color|Vector3|Vector2|float|int|bool}.
static func decode_override(props: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var ov_v: Variant = props.get("OverrideParameters", null)
	if not (ov_v is Dictionary):
		return out
	var ov: Dictionary = ov_v as Dictionary
	var schema_v: Variant = ov.get("SortedParameterOffsets", null)
	var data_v: Variant = ov.get("ParameterData", null)
	if not (schema_v is Array) or not (data_v is Array):
		return out
	var schema: Array = schema_v as Array
	var data: Array = data_v as Array
	if schema.is_empty() or data.is_empty():
		return out
	for row_v: Variant in schema:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v as Dictionary
		var name: String = str(row.get("Name", "")).replace("User.", "")
		var off: int = int(row.get("Offset", 0))
		var tn: String = _type_name(row.get("TypeDef", {}))
		var size: int = int(TYPE_SIZES.get(tn, 0))
		if name == "" or size <= 0 or off < 0 or off + size > data.size():
			continue
		var raw: PackedByteArray = PackedByteArray()
		raw.resize(size)
		for i: int in range(size):
			raw[i] = int(data[off + i]) & 0xFF
		var v: Variant = _decode_value(name, tn, raw)
		if v != null:
			out[name] = v
	return out


static func _decode_value(name: String, tn: String, raw: PackedByteArray) -> Variant:
	match tn:
		"Vector4f", "Vector4", "LinearColor", "Color":
			var c := _floats(raw, 4)
			if _is_colour_name(name):
				return Color(c[0], c[1], c[2], c[3])
			return c
		"Quat":
			return _floats(raw, 4)
		"Vector", "Vector3f":
			var v3 := _floats(raw, 3)
			return Vector3(v3[0], v3[1], v3[2])
		"Vector2f", "Vector2D":
			var v2 := _floats(raw, 2)
			return Vector2(v2[0], v2[1])
		"NiagaraFloat", "Float":
			return _floats(raw, 1)[0]
		"NiagaraInt32", "Int32":
			return raw.decode_s32(0)
		"NiagaraBool", "Bool":
			return raw.decode_s32(0) != 0
	return null


static func _floats(raw: PackedByteArray, n: int) -> Array:
	var out: Array = []
	for i: int in range(n):
		out.append(raw.decode_float(i * 4))
	return out


static func _is_colour_name(name: String) -> bool:
	var n: String = name.to_lower()
	return n.contains("color") or n.contains("colour") or n.contains("tint")


static func _type_name(td_v: Variant) -> String:
	if not (td_v is Dictionary):
		return ""
	var td: Dictionary = td_v as Dictionary
	var cse_v: Variant = td.get("ClassStructOrEnum", null)
	if not (cse_v is Dictionary):
		return ""
	var object_name: String = str((cse_v as Dictionary).get("ObjectName", ""))
	var a: int = object_name.find("'")
	var b: int = object_name.rfind("'")
	if a >= 0 and b > a:
		return object_name.substr(a + 1, b - a - 1)
	return ""


## Parse one Blueprint JSON and return its NiagaraComponent exports. Cached.
static func _load_file(abs_path: String) -> Array:
	if _files.has(abs_path):
		return _files[abs_path] as Array
	var out: Array = []
	var text: String = FileAccess.get_file_as_string(abs_path)
	if text != "":
		var doc: Variant = JSON.parse_string(text)
		if doc is Array:
			for e_v: Variant in (doc as Array):
				if not (e_v is Dictionary):
					continue
				var e: Dictionary = e_v as Dictionary
				if str(e.get("Type", "")) != "NiagaraComponent":
					continue
				var props_v: Variant = e.get("Properties", null)
				if not (props_v is Dictionary):
					continue
				var props: Dictionary = props_v as Dictionary
				var asset: String = ""
				var asset_v: Variant = props.get("Asset", null)
				if asset_v is Dictionary:
					asset = str((asset_v as Dictionary).get("ObjectPath", ""))
					var dot: int = asset.rfind(".")
					if dot > 0:
						asset = asset.substr(0, dot)
				var auto_v: Variant = props.get("bAutoActivate", null)
				var params: Dictionary = decode_override(props)
				if asset == "" and auto_v == null and params.is_empty():
					continue
				out.append({
					"actor": str(e.get("Name", "")),
					"asset": asset,
					"auto": auto_v if auto_v is bool else null,
					"params": params,
				})
	_files[abs_path] = out
	return out


## Process cache stats (files parsed, components decoded) for the probe.
static func cache_stats() -> Dictionary:
	var comps: int = 0
	var decoded: int = 0
	for k: String in _files.keys():
		for c_v: Variant in (_files[k] as Array):
			comps += 1
			if not ((c_v as Dictionary).get("params", {}) as Dictionary).is_empty():
				decoded += 1
	return {"files": _files.size(), "components": comps, "decoded": decoded}
