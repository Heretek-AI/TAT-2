extends RefCounted
## W7H geometric surface resolver: which authored physical surface is under the
## player's feet?
##
## The port used to answer that with a map rule (`_audio_surface()`: contract 1
## = wood, everything else = stone), so 20 of the 22 authored
## `DA_LoudnessModifiers` rows were unreachable: carpet, grass, dirt and foliage
## never silenced a footstep, glass/stone/metal never amplified one. This module
## replaces the rule with a downward ray onto the authored collider and a
## deterministic name -> surface classification.
##
## Resolution order (first hit wins, never a guess):
##   1. explicit designer/author override on the collider node or on the
##      CollisionShape3D that owns the hit shape
##      (`surface` / `surface_type` / `ue_surface`; `surface_type` is the name
##      the E2E helpers already use);
##   2. the hit shape's owning CollisionShape3D `ue_mesh` meta, which the level
##      loader stamps with the authored UE mesh path
##      (`_add_collider(..., label)` and `_get_mesh_and_shape`);
##   3. the collider node's own `ue_mesh` / `merged_ue_meshes` /
##      `override_materials` metas plus the surface materials of a
##      MeshInstance3D visual it carries (props, doors, merged cells);
##   4. `SURFACE_FALLBACK` ("stone", the authored 1.5 multiplier).
##
## The authored physical-material asset itself was not extracted as a table, so
## the mesh/material name is the best honest evidence available; an unknown
## name resolves to stone and is counted, never to a silent 1.0.
##
## The AudioManager variation pools only know seven tokens, so `audio_token()`
## maps the 22 authored names onto them. Both the loudness multiplier and the
## audio pool therefore come from one ray and one decision.

## Authored DA_LoudnessModifiers surface names (22 rows) keyed by the
## lower-case, punctuation-free form used for matching.
const CANONICAL: Dictionary = {
	"carpet": "Carpet",
	"brokenglass": "BrokenGlass",
	"electricalwire": "ElectricalWire",
	"foliage": "Foliage",
	"glass": "Glass",
	"glasshorizontal": "GlassHorizontal",
	"ivy": "Ivy",
	"grass": "Grass",
	"metalpipe": "MetalPipe",
	"metalsheet": "MetalSheet",
	"metalthick": "MetalThick",
	"metalvehicle": "MetalVehicle",
	"puddle": "Puddle",
	"woodfloor": "WoodFloor",
	"woodobject": "WoodObject",
	"metalgrate": "MetalGrate",
	"stone": "Stone",
	"lattice": "Lattice",
	"woodbeam": "WoodBeam",
	"dirt": "Dirt",
	"groundwet": "GroundWet",
	"tile": "Tile",
}

## The seven AudioManager footstep tokens -> the authored row they stand for
## (mirrors GameData.get_surface_loudness / HearingData.SURFACE_TOKEN_ALIASES,
## so "wood" is WoodFloor 1.5 in both places).
const TOKEN_ALIASES: Dictionary = {
	"wood": "woodfloor",
	"metal": "metalthick",
	"wet": "puddle",
	"earth": "dirt",
	"stone": "stone",
	"carpet": "carpet",
	"glass": "glass",
}

## Authored surface -> AudioManager pool token.
const AUDIO_TOKEN: Dictionary = {
	"WoodFloor": "wood",
	"WoodBeam": "wood",
	"WoodObject": "wood",
	"Stone": "stone",
	"Tile": "stone",
	"Lattice": "stone",
	"Carpet": "carpet",
	"MetalPipe": "metal",
	"MetalSheet": "metal",
	"MetalThick": "metal",
	"MetalVehicle": "metal",
	"MetalGrate": "metal",
	"ElectricalWire": "metal",
	"Puddle": "wet",
	"GroundWet": "wet",
	"Dirt": "earth",
	"Grass": "earth",
	"Foliage": "earth",
	"Ivy": "earth",
	"Glass": "glass",
	"GlassHorizontal": "glass",
	"BrokenGlass": "glass",
}

const SURFACE_FALLBACK: String = "Stone"

## Ordered name rules (specific before generic). Tokens are matched against the
## lower-case, punctuation-free mesh/material text. Order matters: "woodbeam"
## before "wood", "metalgrate" before "metal", "glass" after "stone" so a
## WindowStone sill reads as stone rather than glass.
const RULES: Array[Dictionary] = [
	{"surface": "BrokenGlass", "tokens": ["brokenglass", "shatteredglass", "glassdebris", "glassshard"]},
	{"surface": "GlassHorizontal", "tokens": ["glasshorizontal", "horizontalglass", "skylight", "glassroof"]},
	{"surface": "ElectricalWire", "tokens": ["electricalwire", "electricwire", "cable", "wire"]},
	{"surface": "Carpet", "tokens": ["carpet", "rug", "placemat", "doormat", "runner"]},
	{"surface": "Ivy", "tokens": ["ivy", "vine", "creeper"]},
	{"surface": "Foliage", "tokens": ["foliage", "bush", "hedge", "shrub", "leaf", "fern"]},
	{"surface": "Grass", "tokens": ["grass", "lawn", "turf", "meadow"]},
	{"surface": "Dirt", "tokens": ["dirt", "soil", "earth", "gravel", "mud"]},
	{"surface": "Puddle", "tokens": ["puddle"]},
	{"surface": "GroundWet", "tokens": ["groundwet", "wetground", "wet"]},
	{"surface": "MetalGrate", "tokens": ["metalgrate", "grate", "grating", "manhole", "draincover"]},
	{"surface": "MetalPipe", "tokens": ["metalpipe", "pipe"]},
	{"surface": "MetalSheet", "tokens": ["metalsheet", "sheetmetal", "metalroof"]},
	{"surface": "MetalVehicle", "tokens": ["metalvehicle", "vehicle", "automobile"]},
	{"surface": "MetalThick", "tokens": ["metalthick", "metal"]},
	{"surface": "Lattice", "tokens": ["lattice", "trellis"]},
	{"surface": "Tile", "tokens": ["tile", "ceramic", "terracotta"]},
	{"surface": "WoodBeam", "tokens": ["woodbeam", "beam", "rafter", "joist"]},
	{"surface": "WoodFloor", "tokens": ["woodfloor", "floorboard", "parquet", "hardwood", "decking", "floorwood"]},
	{"surface": "WoodObject", "tokens": ["woodobject", "wooden", "timber", "plank", "barrel", "crate", "table", "chair", "wood"]},
	{"surface": "Stone", "tokens": ["stone", "marble", "granite", "cobble", "brick", "concrete", "rock", "slab", "masonry", "terrazzo", "paving", "sidewalk", "asphalt"]},
	{"surface": "Glass", "tokens": ["glass", "window", "mirror"]},
]

## Meta keys an author/test may set on a collider or its shape owner.
const OVERRIDE_META_KEYS: Array[String] = ["surface_type", "ue_surface", "surface", "surface_name"]


## Lower-case, punctuation-free form. "WoodFloor.WoodFloor" -> "woodfloor",
## "/Game/.../SM_Carpet_A" -> "smcarpeta" (rules match on substrings).
static func _norm(text: String) -> String:
	var out: String = ""
	for ch: String in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


## Canonical authored surface name for a bare token/name, "" when it is not an
## authored surface. Accepts the 22 names in any casing and the seven audio
## tokens ("wood" -> WoodFloor, "earth" -> Dirt, ...).
static func canonical(name: String) -> String:
	var key: String = _norm(name)
	if key == "":
		return ""
	if CANONICAL.has(key):
		return str(CANONICAL[key])
	if TOKEN_ALIASES.has(key):
		return str(CANONICAL[str(TOKEN_ALIASES[key])])
	return ""


## Authored surface implied by a mesh/material path or free text. Falls back to
## "" (unknown) so callers can decide; `resolve_text()` applies SURFACE_FALLBACK.
##
## The file name is matched before the full path: UE paths carry folder words
## ("/Game/Art/Environment/...", ".../Roofs/...", ".../Props/...") that are not
## evidence about what the surface is made of ("Environment" contains "iron").
static func surface_from_name(text: String) -> String:
	if text.strip_edges() == "":
		return ""
	var exact: String = canonical(text)
	if exact != "":
		return exact
	var base: String = _basename(text)
	var from_base: String = _match_rules(base)
	if from_base != "":
		return from_base
	return _match_rules(_norm(text))


## File name without folder path or UE object suffix ("/Game/.../SM_Rug_A.Rug" ->
## "SM_Rug_A").
static func _basename(text: String) -> String:
	var s: String = text.strip_edges()
	var slash: int = s.rfind("/")
	if slash >= 0:
		s = s.substr(slash + 1)
	var dot: int = s.find(".")
	if dot >= 0:
		s = s.substr(0, dot)
	return _norm(s)


static func _match_rules(key: String) -> String:
	if key == "":
		return ""
	for rule: Dictionary in RULES:
		for token_v: Variant in (rule.get("tokens", []) as Array):
			if key.find(str(token_v)) >= 0:
				return str(rule.get("surface", ""))
	return ""


## Surface for free text with the documented fallback (never crashes, never
## returns ""). Unknown -> "stone" (the authored 1.5 multiplier).
static func resolve_text(text: String) -> String:
	var s: String = surface_from_name(text)
	return s if s != "" else SURFACE_FALLBACK


## First name in `names` that classifies, else "". Used for multi-name evidence
## (a merged cell's members, a mesh's material slots).
static func first_from_names(names: Array) -> String:
	for n: Variant in names:
		if not (n is String):
			continue
		var s: String = surface_from_name(str(n))
		if s != "":
			return s
	return ""


## AudioManager pool token for an authored surface (7 tokens). Unknown -> the
## resolver fallback's token so audio and loudness never disagree.
static func audio_token(surface: String) -> String:
	var s: String = canonical(surface)
	if s == "":
		s = resolve_text(surface)
	return str(AUDIO_TOKEN.get(s, "stone"))


## Explicit author/test override on a node (see OVERRIDE_META_KEYS).
static func override_surface(node: Object) -> String:
	if node == null:
		return ""
	for key: String in OVERRIDE_META_KEYS:
		if not node.has_meta(key):
			continue
		var v: Variant = node.get_meta(key)
		if v is String or v is StringName:
			var s: String = surface_from_name(str(v))
			if s != "":
				return s
	return ""


## Evidence names carried by a node: its authored mesh path(s), per-instance
## override materials and (for a MeshInstance3D) its surface materials.
static func names_from_node(node: Object) -> Array:
	var names: Array = []
	if node == null:
		return names
	if node.has_meta("ue_mesh"):
		names.append(str(node.get_meta("ue_mesh")))
	if node.has_meta("merged_ue_meshes"):
		var merged: Variant = node.get_meta("merged_ue_meshes")
		if merged is Array:
			for m: Variant in (merged as Array):
				names.append(str(m))
	if node.has_meta("override_materials"):
		var ov: Variant = node.get_meta("override_materials")
		if ov is Array:
			for o: Variant in (ov as Array):
				names.append(str(o))
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null:
		for s: int in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null and mi.mesh != null:
				mat = mi.mesh.surface_get_material(s)
			if mat == null:
				continue
			if mat.resource_path != "":
				names.append(mat.resource_path)
			elif mat.resource_name != "":
				names.append(mat.resource_name)
	return names


## Surface for a ray hit dictionary (PhysicsDirectSpaceState3D.intersect_ray
## result). Never returns ""; a missing/odd collider is SURFACE_FALLBACK.
static func surface_for_hit(hit: Dictionary) -> String:
	return str(surface_detail_for_hit(hit).get("surface", SURFACE_FALLBACK))


## surface + known flag: `known` is false when every evidence name was
## unrecognised and the documented stone fallback answered.
static func surface_detail_for_hit(hit: Dictionary) -> Dictionary:
	if hit.is_empty():
		return {"surface": SURFACE_FALLBACK, "known": false}
	var collider_v: Variant = hit.get("collider")
	if not (collider_v is Node):
		return {"surface": SURFACE_FALLBACK, "known": false}
	var collider: Node = collider_v as Node
	if not is_instance_valid(collider):
		return {"surface": SURFACE_FALLBACK, "known": false}
	var body_override: String = override_surface(collider)
	if body_override != "":
		return {"surface": body_override, "known": true}
	var co: CollisionObject3D = collider as CollisionObject3D
	if co != null:
		var idx: int = int(hit.get("shape", -1))
		if idx >= 0:
			var owner_id: int = co.shape_find_owner(idx)
			if owner_id >= 0:
				var owner_obj: Object = co.shape_owner_get_owner(owner_id)
				var owner_override: String = override_surface(owner_obj)
				if owner_override != "":
					return {"surface": owner_override, "known": true}
				var owner_surface: String = first_from_names(names_from_node(owner_obj))
				if owner_surface != "":
					return {"surface": owner_surface, "known": true}
	var node_surface: String = first_from_names(names_from_node(collider))
	if node_surface != "":
		return {"surface": node_surface, "known": true}
	return {"surface": SURFACE_FALLBACK, "known": false}


## Full resolution for a ray: surface name, audio token and the raw hit.
static func resolve_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = [], mask: int = 1) -> Dictionary:
	if space == null:
		return {"surface": SURFACE_FALLBACK, "audio_token": audio_token(SURFACE_FALLBACK), "hit": {}, "known": false}
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	var hit: Dictionary = space.intersect_ray(q)
	var detail: Dictionary = surface_detail_for_hit(hit)
	var surface: String = str(detail.get("surface", SURFACE_FALLBACK))
	return {
		"surface": surface,
		"audio_token": audio_token(surface),
		"hit": hit,
		"known": bool(detail.get("known", false)) and not hit.is_empty(),
	}


## Down-ray under a body: the surface it stands on. `down_m` starts slightly
## above the origin (which for the thief is the capsule foot point) so a
## coincident contact still registers.
static func surface_under(node: Node3D, down_m: float = 0.45, exclude: Array[RID] = []) -> Dictionary:
	if node == null or not node.is_inside_tree():
		return {"surface": SURFACE_FALLBACK, "audio_token": audio_token(SURFACE_FALLBACK), "hit": {}, "known": false}
	var world: World3D = node.get_world_3d()
	if world == null:
		return {"surface": SURFACE_FALLBACK, "audio_token": audio_token(SURFACE_FALLBACK), "hit": {}, "known": false}
	return resolve_ray(
		world.direct_space_state,
		node.global_position + Vector3.UP * 0.15,
		node.global_position - Vector3.UP * maxf(down_m, 0.05),
		exclude, 1)
