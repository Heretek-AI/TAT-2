extends RefCounted
## Runtime consumer of the authored Niagara catalogue (T12-VFX, RE-E-02).
##
## `game/data/generated/vfx/systems.json` (tools/parse_vfx.py) has recorded every
## system's renderers, resolved material and resolved sprite texture since the VFX
## wave, but had zero runtime readers: the loader tinted one additive blob per
## placement by substring-matching the asset name. This module is that reader.
##
## It owns three answers per system:
##   * which authored sprite texture to sample — `sprite_tokens.gd` re-resolves the
##     material's authored slot (opacity first, the producer preferred albedo) and
##     the measured soft mask in `sprite_masks.gd` decides whether it binds,
##   * which authored colour the renderer material carries (`materials.json`
##     vectors / tint), and
##   * a base billboard size band derived from the authored complexity class.
## Per-placement authored values (user parameters, placement scale) win over all
## three and are applied by the loader; this module is the fallback that replaces
## the old name regex.

const SYSTEMS_PATH: String = "res://data/generated/vfx/systems.json"
const MATERIALS_PATH: String = "res://data/generated/materials.json"
const SpriteMasks := preload("res://src/core/vfx/sprite_masks.gd")
const SpriteTokens := preload("res://src/core/vfx/sprite_tokens.gd")

## Base billboard size (metres) per authored complexity class. A stand-in where
## neither the placement scale nor a User.Scale parameter is authored; it is
## keyed by the catalogue's own classification, never by a substring of the name.
const BASE_SIZE_BY_CLASS: Dictionary = {
	"sprite_only": 0.12,
	"graph_heavy": 0.18,
	"mesh_or_ribbon": 0.25,
}

## Last-resort tints for systems with no authored user colour and no material
## vector. Kept deliberately tiny and keyed by the catalogue folder family, but
## every use is counted by the loader and reported by the probe so the fallback
## cannot silently become the normal path again.
const FALLBACK_TINTS: Dictionary = {
	"flame": Color(1.0, 0.55, 0.18, 0.9),
	"smoke": Color(0.55, 0.55, 0.58, 0.5),
	"alarm": Color(1.0, 0.22, 0.18, 0.85),
	"arcane": Color(0.55, 0.35, 1.0, 0.8),
	"nature": Color(0.62, 0.78, 0.42, 0.7),
	"default": Color(0.9, 0.9, 0.95, 0.55),
}

static var _loaded: bool = false
static var _by_key: Dictionary = {}
static var _materials: Dictionary = {}
static var _materials_loaded: bool = false
static var _stats: Dictionary = {}


static func ensure_loaded() -> bool:
	if _loaded:
		return not _by_key.is_empty()
	_loaded = true
	var text: String = FileAccess.get_file_as_string(SYSTEMS_PATH)
	if text == "":
		push_warning("[niagara_library] systems.json missing; level Niagara falls back to the procedural billboard")
		return false
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		return false
	var systems_v: Variant = (doc as Dictionary).get("systems", [])
	if not (systems_v is Array):
		return false
	var sprites_usable: int = 0
	var token_fixed: int = 0
	var token_kept: int = 0
	var token_none: int = 0
	var textures: Dictionary = {}
	var resolved_textures: Dictionary = {}
	for s_v: Variant in (systems_v as Array):
		if not (s_v is Dictionary):
			continue
		var s: Dictionary = s_v as Dictionary
		var key: String = asset_key(str(s.get("name", "")))
		if key == "":
			continue
		var sprite_path: String = ""
		var sprite_count: int = 0
		var textured: int = 0
		var materials: Array[String] = []
		var tokens: Array = []
		for r_v: Variant in (s.get("renderers", []) as Array):
			if not (r_v is Dictionary):
				continue
			var r: Dictionary = r_v as Dictionary
			var mat_v: Variant = r.get("material", null)
			var mat: String = str(mat_v) if mat_v != null else ""
			if mat != "" and not materials.has(mat):
				materials.append(mat)
			if str(r.get("type", "")) != "sprite":
				continue
			sprite_count += 1
			# JSON null must stay empty: `str(null)` is the literal "<null>", which
			# would count a texture-less renderer as textured and defeat the counters.
			var tex_v: Variant = r.get("sprite_texture", null)
			var tex: String = str(tex_v) if tex_v != null else ""
			if tex != "":
				textured += 1
				textures[tex] = true
			# The producer's pick prefers albedo and never opacity, so re-resolve the
			# authored slot from the material record; the catalogue token is kept when
			# the material carries nothing better.
			var token: Dictionary = SpriteTokens.resolve_sprite_texture(mat, tex)
			var token_path: String = str(token.get("path", ""))
			var token_slot: String = str(token.get("slot", ""))
			var token_reason: String = str(token.get("reason", ""))
			if token_path == "":
				token_none += 1
			elif token_path == tex:
				token_kept += 1
			else:
				token_fixed += 1
			if token_path != "":
				resolved_textures[token_path] = true
			tokens.append({
				"material": mat,
				"current": tex,
				"path": token_path,
				"slot": token_slot,
				"reason": token_reason,
				"subuv": str(token.get("subuv", "")),
			})
			if sprite_path == "" and token_path != "" and token_reason != "subuv_atlas" \
					and SpriteMasks.acceptable(token_path):
				sprite_path = token_path
		if sprite_path != "":
			sprites_usable += 1
		_by_key[key] = {
			"name": str(s.get("name", "")),
			"class": str(s.get("complexity", "")),
			"sprite_path": sprite_path,
			"sprite_count": sprite_count,
			"sprites_textured": textured,
			"base_size": float(BASE_SIZE_BY_CLASS.get(str(s.get("complexity", "")), 0.12)),
			"folder": str(s.get("folder", "")),
			"materials": materials,
			"sprite_tokens": tokens,
		}
	_stats = {
		"systems": _by_key.size(),
		"sprites_usable": sprites_usable,
		"textures_referenced": textures.size(),
		"textures_resolved": resolved_textures.size(),
		"sprite_token_fixed": token_fixed,
		"sprite_token_kept": token_kept,
		"sprite_token_none": token_none,
	}
	return not _by_key.is_empty()


## Normalised key shared with `niagara_params.gd` (case/underscore insensitive).
static func asset_key(path: String) -> String:
	return path.get_file().to_lower().replace("_", "")


## Catalogue record for [param asset_path], or an empty dictionary when the
## system has no record (e.g. the `NE_*` standalone emitters).
static func info(asset_path: String) -> Dictionary:
	if not ensure_loaded():
		return {}
	var rec: Variant = _by_key.get(asset_key(asset_path), null)
	return rec as Dictionary if rec is Dictionary else {}


## Authored colour carried by the renderer material, or transparent black when no
## authored vector exists. Checked in order: the catalogue's resolved `tint`, then
## the usual UE colour vector names (`Color`, `Color 1`, `Color 2`, `Emissive`).
static func material_tint(asset_path: String) -> Color:
	if not ensure_loaded():
		return Color(0.0, 0.0, 0.0, 0.0)
	var rec: Variant = _by_key.get(asset_key(asset_path), null)
	if not (rec is Dictionary):
		return Color(0.0, 0.0, 0.0, 0.0)
	_load_materials()
	if _materials.is_empty():
		return Color(0.0, 0.0, 0.0, 0.0)
	for mat_path: String in ((rec as Dictionary).get("materials", []) as Array):
		var m_v: Variant = _materials.get(mat_path, null)
		if not (m_v is Dictionary):
			continue
		var c: Color = _pick_material_colour(m_v as Dictionary)
		if c.a > 0.0:
			return c
	return Color(0.0, 0.0, 0.0, 0.0)


## The catalogued fallback tint family for a system, by authored folder.
static func fallback_tint(asset_path: String) -> Color:
	var rec: Dictionary = info(asset_path)
	var folder: String = str(rec.get("folder", "")).to_lower()
	var name: String = asset_path.to_lower()
	if "candle" in name or "fire" in name or "flame" in name or "torch" in folder:
		return FALLBACK_TINTS["flame"]
	if "smoke" in name or "dust" in name or "chimney" in name:
		return FALLBACK_TINTS["smoke"]
	if "security" in name or "alarm" in name or "turret" in name:
		return FALLBACK_TINTS["alarm"]
	if "ward" in name or "magic" in name or "arcane" in name:
		return FALLBACK_TINTS["arcane"]
	if "leaf" in name or "moth" in name or "goo" in name:
		return FALLBACK_TINTS["nature"]
	return FALLBACK_TINTS["default"]


static func stats() -> Dictionary:
	ensure_loaded()
	return _stats


static func _load_materials() -> void:
	if _materials_loaded:
		return
	_materials_loaded = true
	var text: String = FileAccess.get_file_as_string(MATERIALS_PATH)
	if text == "":
		return
	var doc: Variant = JSON.parse_string(text)
	if doc is Dictionary:
		_materials = doc as Dictionary


## `materials.json` is keyed by UE package path, so the catalogue's material path
## is the join key. Values are authored material vectors; no value is invented.
static func _pick_material_colour(m: Dictionary) -> Color:
	var tint_v: Variant = m.get("tint", null)
	if tint_v is Array and (tint_v as Array).size() >= 3:
		var t: Array = tint_v as Array
		var c := Color(float(t[0]), float(t[1]), float(t[2]), float(t[3]) if t.size() > 3 else 1.0)
		if not (is_equal_approx(c.r, 1.0) and is_equal_approx(c.g, 1.0) and is_equal_approx(c.b, 1.0)):
			return c
	var vectors_v: Variant = m.get("vectors", null)
	if not (vectors_v is Dictionary):
		return Color(0.0, 0.0, 0.0, 0.0)
	var vectors: Dictionary = vectors_v as Dictionary
	for key: String in ["Color", "Color 1", "Color1", "Emissive Color", "EmissiveColor", "Tint", "Base Color"]:
		var v: Variant = vectors.get(key, null)
		if v is Array and (v as Array).size() >= 3:
			var a: Array = v as Array
			return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return Color(0.0, 0.0, 0.0, 0.0)
