extends RefCounted
## Runtime token resolver for level Niagara sprite renderers (W9-P1, A3b).
##
## `tools/parse_vfx.py::_resolve_sprite_texture()` prefers albedo, emissive, normal
## and orm, and never prefers opacity, so the catalogue's pre-baked
## `renderers[].sprite_texture` is an opaque albedo or atlas page for 23 of the 29
## sprite textures measured in `sprite_masks.gd`. Those systems keep the procedural
## falloff. The producer is frozen for this wave, so the runtime re-resolves the
## authored slot from the same `materials.json` record `level_loader` already loads.
##
## `resolve_sprite_texture()` returns `{path, slot, reason}` (plus `subuv` for an
## atlas) and applies this order:
##   * candidates follow the authored slot order opacity, albedo, emissive, then
##     normal/orm only when no colour or alpha slot exists;
##   * the first candidate that passes `SpriteMasks.acceptable()` wins (`gate`);
##   * with none acceptable the authored opacity slot is returned even though the
##     sampler will reject it (`opacity_fallback`), else the catalogue's token is
##     kept (`kept`) — behaviour can never get worse than the pre-baked choice;
##   * a SubUV atlas (`Horizontal/Vertical Subimages` > 1) records `subuv=<h>x<v>`
##     and is never claimed as a mask: the billboard shader samples one UV rect and
##     cannot slice an atlas page (`level_niagara.gdshader`).
## The load is lazy and cached; a missing or corrupt materials.json is counted in
## `stats()["load_error"]` and every sprite keeps its catalogue token, never a crash.

const MATERIALS_PATH: String = "res://data/generated/materials.json"
const SpriteMasks := preload("res://src/core/vfx/sprite_masks.gd")

## Colour/alpha slots, strongest first. The authored opacity mask is the correct
## sprite token and the producer never prefers it.
const STRONG_SLOTS: Array[String] = ["opacity", "albedo", "emissive"]
## Only consulted when no colour or alpha slot exists: a normal/orm page is a
## material input, not an effect sprite, but it still beats an empty sampler.
const WEAK_SLOTS: Array[String] = ["normal", "orm"]
const SUBUV_H: String = "Horizontal Subimages"
const SUBUV_V: String = "Vertical Subimages"

static var _loaded: bool = false
static var _materials: Dictionary = {}
## material path -> decision without the per-renderer `current` token, so a shared
## material resolves once per process.
static var _cache: Dictionary = {}
static var _stats: Dictionary = {"records": 0, "load_ms": 0, "load_error": ""}


static func ensure_loaded() -> bool:
	if _loaded:
		return not _materials.is_empty()
	_loaded = true
	var t0: int = Time.get_ticks_msec()
	var text: String = FileAccess.get_file_as_string(MATERIALS_PATH)
	if text == "":
		_stats["load_error"] = "materials.json missing"
		_stats["load_ms"] = Time.get_ticks_msec() - t0
		push_warning("[sprite_tokens] materials.json missing; sprite renderers keep the catalogue token")
		return false
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		_stats["load_error"] = "materials.json is not a JSON object"
		_stats["load_ms"] = Time.get_ticks_msec() - t0
		push_warning("[sprite_tokens] materials.json unreadable; sprite renderers keep the catalogue token")
		return false
	_materials = doc as Dictionary
	_stats["records"] = _materials.size()
	_stats["load_ms"] = Time.get_ticks_msec() - t0
	return not _materials.is_empty()


## Authored texture slot for one sprite renderer material.
##
## [param material_path] is the renderer's UE material path (the `materials.json`
## key); [param current] is the catalogue's pre-baked `sprite_texture` and is
## returned unchanged when the material carries no usable token. The result always
## has `path`, `slot` and `reason`; `subuv` is present when the material is a
## SubUV atlas.
static func resolve_sprite_texture(material_path: String, current: String) -> Dictionary:
	var decision: Dictionary = _cache.get(material_path, {}) as Dictionary
	if decision.is_empty():
		decision = _decide(material_path)
		_cache[material_path] = decision
	var out: Dictionary = decision.duplicate()
	if str(out.get("path", "")) == "":
		# No authored candidate: the pre-baked token stays, so nothing gets worse.
		out["path"] = current
	return out


## One-time parse cost and record count, for the probe's `ms=` field.
static func stats() -> Dictionary:
	return _stats


## Authored material facts the probe needs for the additive-sprite follow-up metric:
## `blend` is the authored `render.blend_mode`, `additive` says it is an additive
## family, and `slots` is the resolution order (`[{slot, path}]`, strong slots first).
## It never decides a bind — `resolve_sprite_texture()` owns that.
static func material_tokens(material_path: String) -> Dictionary:
	var out: Dictionary = {"blend": "", "additive": false, "slots": []}
	if material_path == "" or not ensure_loaded():
		return out
	var rec_v: Variant = _materials.get(material_path, null)
	if not (rec_v is Dictionary):
		return out
	var rec: Dictionary = rec_v as Dictionary
	var render_v: Variant = rec.get("render", null)
	if render_v is Dictionary:
		out["blend"] = str((render_v as Dictionary).get("blend_mode", ""))
	out["additive"] = "additive" in str(out["blend"]).to_lower()
	var texs_v: Variant = rec.get("texs", null)
	var texs: Dictionary = texs_v as Dictionary if texs_v is Dictionary else {}
	var rows: Array = []
	for slot: String in _candidate_order(texs):
		rows.append({"slot": slot, "path": str(texs.get(slot, ""))})
	out["slots"] = rows
	return out


## Drop the parsed table and every cached decision. Called by probes before they
## quit so a headless run holds no 2.7 MB dictionary past its last use.
static func release() -> void:
	_materials = {}
	_cache = {}
	_loaded = false
	_stats = {"records": 0, "load_ms": 0, "load_error": ""}


static func _decide(material_path: String) -> Dictionary:
	if material_path == "":
		return {"path": "", "slot": "", "reason": "no_material"}
	if not ensure_loaded():
		return {"path": "", "slot": "", "reason": "materials_missing"}
	var rec_v: Variant = _materials.get(material_path, null)
	if not (rec_v is Dictionary):
		return {"path": "", "slot": "", "reason": "no_material_record"}
	var rec: Dictionary = rec_v as Dictionary
	var texs_v: Variant = rec.get("texs", null)
	var texs: Dictionary = texs_v as Dictionary if texs_v is Dictionary else {}
	var candidates: Array[String] = _candidate_order(texs)
	if candidates.is_empty():
		return {"path": "", "slot": "", "reason": "no_texture"}
	for slot: String in candidates:
		var path: String = str(texs.get(slot, ""))
		if SpriteMasks.acceptable(path):
			var hit: Dictionary = {"path": path, "slot": slot, "reason": "gate"}
			_add_subuv(hit, rec)
			return hit
	var subuv: String = _subuv_tag(rec)
	var opacity: String = str(texs.get("opacity", ""))
	if opacity != "":
		# The authored mask is the right token even while the measured band rejects
		# it (a packed or opaque page needs a channel/atlas reader first).
		var fallback: Dictionary = {"path": opacity, "slot": "opacity", "reason": "opacity_fallback"}
		if subuv != "":
			fallback["subuv"] = subuv
		return fallback
	if subuv != "":
		# An atlas page without slicing reads as a box; record the grid, bind nothing.
		return {"path": str(texs.get(candidates[0], "")), "slot": candidates[0],
			"reason": "subuv_atlas", "subuv": subuv}
	return {"path": "", "slot": candidates[0], "reason": "kept"}


## Slot order for one record: the three colour/alpha slots, then normal/orm only
## when none of those exists.
static func _candidate_order(texs: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for slot: String in STRONG_SLOTS:
		if str(texs.get(slot, "")) != "":
			out.append(slot)
	if out.is_empty():
		for slot: String in WEAK_SLOTS:
			if str(texs.get(slot, "")) != "":
				out.append(slot)
	return out


## `8x8` for a SubUV material, or "" when it is a single-image sprite.
static func _subuv_tag(rec: Dictionary) -> String:
	var params_v: Variant = rec.get("params", null)
	if not (params_v is Dictionary):
		return ""
	var params: Dictionary = params_v as Dictionary
	var h: float = float(params.get(SUBUV_H, 1.0))
	var v: float = float(params.get(SUBUV_V, 1.0))
	if h <= 1.0 and v <= 1.0:
		return ""
	return "%dx%d" % [int(h), int(v)]


static func _add_subuv(hit: Dictionary, rec: Dictionary) -> void:
	var tag: String = _subuv_tag(rec)
	if tag != "":
		hit["subuv"] = tag
