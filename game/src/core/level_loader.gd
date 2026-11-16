extends Node
## High-performance UE5 -> Godot 4.7 level builder.
## Loads extracted .tatlevel.json sublevels, batches repeated .glb meshes into MultiMeshInstance3D,
## binds real PBR materials (Albedo/Normal/ORM) from materials.json + mesh_materials.json,
## generates StaticBody3D collision, and extracts real spawn/guard/loot/escape markers.

const _VfxManager: GDScript = preload("res://src/core/vfx_manager.gd")
const MobileProfile: GDScript = preload("res://src/core/mobile_profile.gd")

signal load_progress(pct: float, status: String)

var _materials_db: Dictionary = {}
var _materials_db_lower: Dictionary = {}
var _mesh_mats_db: Dictionary = {}
var _mesh_mats_db_lower: Dictionary = {}
var _tex_cache: Dictionary = {}
var _std_mat_cache: Dictionary = {}
var _mesh_res_cache: Dictionary = {} # ue_path -> { "mesh": Mesh, "shape": Shape3D }

# --- Spatial chunking & culling tuning (perf P1/P2/P4) ----------------------
## Repeated meshes are partitioned into CHUNK_SIZE x CHUNK_SIZE XZ cells so every
## MultiMeshInstance3D gets a tight AABB that Godot's frustum culler can reject.
const CHUNK_SIZE: float = 32.0
## visibility_range_* is measured from the instance AABB centre; a 32m chunk's
## centre can be half a cell away from the prop being culled, so pad the ranges.
const CHUNK_RADIUS_PAD: float = CHUNK_SIZE * 0.5
const CLUTTER_VIS_RANGE: float = 22.0
const TINY_PROP_VIS_RANGE: float = 45.0
const SMALL_PROP_VIS_RANGE: float = 95.0
const TINY_PROP_LEN: float = 1.2
const SMALL_PROP_LEN: float = 4.0
const OCCLUDER_MIN_LEN: float = 6.0
const OCCLUDER_MAX_LEN: float = 48.0
const MAX_OCCLUDERS: int = 768
const MAX_SHAPES_PER_BODY: int = 384
const MAX_TOTAL_SHAPES: int = 24000
const LIGHT_DISTANCE_FADE_BEGIN: float = 28.0
const LIGHT_DISTANCE_FADE_LENGTH: float = 12.0
const PROGRESS_YIELD_EVERY: int = 64

## Foliage/debris/clutter: aggressively culled, never casts shadows or collides.
const CLUTTER_TOKENS: Array[String] = [
	"sm_leaf", "sm_grass", "sm_newgrass", "sm_newspaper", "sm_pebble", "sm_debris",
	"foliage", "ivy", "vine", "moss", "cobweb", "sm_dust",
]
## Sublevels that only dress the horizon: no physics colliders, no occluders.
const DECORATIVE_SUBLEVEL_TOKENS: Array[String] = ["skyboxgeo", "periphery"]
## Occlusion occluders are opt-in: only obviously solid structural piece names
## (never see-through pieces like windows, doors, rails, frames or light fixtures).
const OCCLUDER_INCLUDE_TOKENS: Array[String] = [
	"wall", "floor", "ceiling", "roof", "building", "pillar", "column", "stair", "block",
]
const OCCLUDER_EXCLUDE_TOKENS: Array[String] = [
	"window", "door", "glass", "gate", "archway", "arch_", "frame", "rail", "beam",
	"hole", "gap", "curtain", "drape", "cloth", "banner", "flag", "foliage", "leaf",
	"sky", "cloud", "fog", "smoke", "water", "carpet", "rug", "paper", "poster",
	"scroll", "cable", "wire", "rope", "ladder", "light", "lamp", "vent", "pipe",
	"trim", "deco", "panel",
]


func _ready() -> void:
	_load_material_dbs()


func _load_material_dbs() -> void:
	if FileAccess.file_exists("res://data/generated/materials.json"):
		var f := FileAccess.open("res://data/generated/materials.json", FileAccess.READ)
		var p: Variant = JSON.parse_string(f.get_as_text())
		if p is Dictionary:
			_materials_db = p
			_materials_db_lower.clear()
			for k: Variant in _materials_db.keys():
				_materials_db_lower[str(k).to_lower()] = _materials_db[k]
	if FileAccess.file_exists("res://data/generated/mesh_materials.json"):
		var f2 := FileAccess.open("res://data/generated/mesh_materials.json", FileAccess.READ)
		var p2: Variant = JSON.parse_string(f2.get_as_text())
		if p2 is Dictionary:
			_mesh_mats_db = p2
			_mesh_mats_db_lower.clear()
			for k2: Variant in _mesh_mats_db.keys():
				_mesh_mats_db_lower[str(k2).to_lower()] = _mesh_mats_db[k2]


func _load_tex(res_path: String) -> Texture2D:
	if res_path == "" or not ResourceLoader.exists(res_path):
		return null
	if _tex_cache.has(res_path):
		return _tex_cache[res_path]
	var t: Variant = load(res_path)
	if t is Texture2D:
		_tex_cache[res_path] = t
		return t
	return null


## Normalizes a UE parameter dict for case/space/underscore-insensitive lookup.
func _ue_norm_map(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[str(k).to_lower().replace(" ", "").replace("_", "")] = d[k]
	return out


func _ue_lookup(normed: Dictionary, names: Array) -> Variant:
	for n in names:
		var key := str(n).to_lower().replace(" ", "").replace("_", "")
		if normed.has(key):
			return normed[key]
	return null


## Applies real UE scalar PBR params (Roughness/Metallic/Specular families from
## materials.json "params"). Runs before the art-direction overrides in
## get_material_for_ue() so those keep precedence; missing params keep current
## defaults (roughness 0.78, metallic/specular 0).
func _apply_ue_pbr_params(mat: StandardMaterial3D, info: Dictionary) -> void:
	var params: Dictionary = _ue_norm_map(info.get("params", {}))
	var rough: Variant = _ue_lookup(params, ["roughness", "flatroughness"])
	if rough == null:
		var rlo: Variant = _ue_lookup(params, ["roughnesslow", "roughnessmin"])
		var rhi: Variant = _ue_lookup(params, ["roughnesshigh", "roughnessmax"])
		if rlo != null and rhi != null:
			rough = (float(rlo) + float(rhi)) * 0.5
	if rough != null:
		mat.roughness = clampf(float(rough), 0.0, 1.0)
	var metal: Variant = _ue_lookup(params, ["metallic", "metalness", "flatmetallic"])
	if metal == null:
		var mlo: Variant = _ue_lookup(params, ["metallicmin"])
		var mhi: Variant = _ue_lookup(params, ["metallicmax"])
		if mlo != null and mhi != null:
			metal = (float(mlo) + float(mhi)) * 0.5
	if metal != null:
		mat.metallic = clampf(float(metal), 0.0, 1.0)
	var spec: Variant = _ue_lookup(params, ["specular", "spec"])
	if spec != null:
		mat.metallic_specular = clampf(float(spec), 0.0, 1.0)


## Applies real UE render flags from materials.json "render": TwoSided ->
## double-sided, translucent/AlphaComposite blend -> alpha transparency, masked
## blend -> alpha scissor. Glass art overrides below still take precedence.
func _apply_ue_render_flags(mat: StandardMaterial3D, info: Dictionary) -> void:
	var render: Dictionary = info.get("render", {})
	if render.get("two_sided", false):
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blend := str(render.get("blend_mode", "")).to_lower()
	if blend.find("translucent") >= 0 or blend.find("alphacomposite") >= 0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	elif blend.find("masked") >= 0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = clampf(float(render.get("opacity_mask_clip", 0.5)), 0.0, 1.0)


## Applies real UE emissive vectors/scalars from materials.json. Merges with an
## emissive texture bound above (the texture keeps its art-tuned energy while
## the UE colour fills in the emission tint); otherwise enables emission from
## the UE colour scaled by the emissive scalar. Skipped when the UE switches
## explicitly gate emissive off.
func _apply_ue_emissive(mat: StandardMaterial3D, info: Dictionary) -> void:
	var switches: Dictionary = _ue_norm_map(info.get("switches", {}))
	if _ue_lookup(switches, ["emissiveon?"]) == false:
		return
	if _ue_lookup(switches, ["disableemissivecontribution"]) == true:
		return
	var vectors: Dictionary = _ue_norm_map(info.get("vectors", {}))
	var ecol: Variant = _ue_lookup(vectors, ["emissivecolor", "emissive", "emissivetint", "emiscolor"])
	var params: Dictionary = _ue_norm_map(info.get("params", {}))
	var estr: Variant = _ue_lookup(params, ["emissivestrength", "emissiveintensity", "emissivemultiplier", "emissivemultiply", "emismultiply", "emissivemult", "emissivepower", "emissivebrightness", "emissivebrillance"])
	if ecol == null and estr == null:
		return
	var col := Color(1.0, 1.0, 1.0)
	if ecol is Array and (ecol as Array).size() >= 3:
		var ea: Array = ecol
		col = Color(float(ea[0]), float(ea[1]), float(ea[2]))
		if maxf(col.r, maxf(col.g, col.b)) <= 0.02 and estr == null:
			return
	if mat.emission_enabled:
		mat.emission = col
		if estr != null:
			mat.emission_energy_multiplier = clampf(float(mat.emission_energy_multiplier) * float(estr), 0.0, 16.0)
	else:
		mat.emission_enabled = true
		mat.emission = col
		if estr != null:
			mat.emission_energy_multiplier = clampf(float(estr), 0.0, 8.0)
		else:
			mat.emission_energy_multiplier = 1.0


func get_material_for_ue(ue_mat_path: String) -> StandardMaterial3D:
	if _std_mat_cache.has(ue_mat_path):
		return _std_mat_cache[ue_mat_path]
	var low_mat := ue_mat_path.to_lower()
	var info: Dictionary = _materials_db.get(ue_mat_path, _materials_db_lower.get(low_mat, {}))
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.78
	_apply_ue_pbr_params(mat, info)
	_apply_ue_render_flags(mat, info)
	var texs: Dictionary = info.get("texs", {})
	var alb := _load_tex(str(texs.get("albedo", "")))
	# Hard rule: the UI map textures (T_MapBuilding_*) must never dress 3D geometry.
	if str(texs.get("albedo", "")).to_lower().find("mapbuilding") >= 0:
		alb = null
	if "oldmanorpanels" in low_mat:
		var wood_alb := _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Wood/Manor/T_ManorWood_D.png")
		if wood_alb != null:
			alb = wood_alb
		mat.albedo_color = Color(0.65, 0.55, 0.48)
	elif "glasspanels" in low_mat or "windowglass" in low_mat:
		# Never bind map-building icon textures to glass panels; keep frosted translucent glass
		alb = null
		mat.albedo_color = Color(0.35, 0.55, 0.72, 0.34)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.22
		mat.metallic = 0.08
		mat.rim_enabled = true
		mat.rim = 0.3
		_std_mat_cache[ue_mat_path] = mat
		return mat
	if alb != null:
		mat.albedo_texture = alb
	var norm := _load_tex(str(texs.get("normal", "")))
	if norm != null:
		mat.normal_enabled = true
		mat.normal_texture = norm
	var orm := _load_tex(str(texs.get("orm", "")))
	if orm != null:
		mat.ao_enabled = true
		mat.ao_texture = orm
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness_texture = orm
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture = orm
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	var tint: Variant = info.get("tint")
	if tint is Array and tint.size() >= 3:
		mat.albedo_color = Color(float(tint[0]), float(tint[1]), float(tint[2]), 1.0)
	var em := _load_tex(str(texs.get("emissive", "")))
	if em != null:
		mat.emission_enabled = true
		mat.emission_texture = em
		mat.emission_energy_multiplier = 2.2
	_apply_ue_emissive(mat, info)
	if alb == null and tint == null:
		var low: String = ue_mat_path.to_lower()
		if "brick" in low:
			var brick_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Brick/T_OldBricksA_D.png")
			if brick_alb != null:
				mat.albedo_texture = brick_alb
			mat.albedo_color = Color(0.45, 0.36, 0.32)
			mat.roughness = 0.85
		elif "stone" in low or "cobble" in low:
			var stone_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Legacy/T_CobbleStoneA_D.png")
			if stone_alb != null:
				mat.albedo_texture = stone_alb
			mat.albedo_color = Color(0.42, 0.41, 0.40)
			mat.roughness = 0.88
		elif "dirt" in low or "ground" in low or "mud" in low:
			var dirt_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Nature/Dirt/T_GroundDirtA_D.png")
			if dirt_alb != null:
				mat.albedo_texture = dirt_alb
			mat.albedo_color = Color(0.38, 0.30, 0.22)
			mat.roughness = 0.92
		elif "wood" in low or "plank" in low or "floor" in low or "desk" in low or "trim" in low or "door" in low:
			var manor_wood_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Wood/Manor/T_ManorWood_D.png")
			if manor_wood_alb != null:
				mat.albedo_texture = manor_wood_alb
			else:
				var floor_wood_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Wood/Floors/T_WoodFloorA_D.png")
				if floor_wood_alb != null:
					mat.albedo_texture = floor_wood_alb
			mat.albedo_color = Color(0.52, 0.40, 0.30)
			mat.roughness = 0.72
		elif "brass" in low or "gold" in low:
			mat.albedo_color = Color(0.72, 0.56, 0.24)
			mat.metallic = 0.85
			mat.roughness = 0.3
		elif "metal" in low or "iron" in low or "steel" in low:
			mat.albedo_color = Color(0.24, 0.26, 0.29)
			mat.metallic = 0.8
			mat.roughness = 0.42
		elif "glass" in low or "window" in low:
			mat.albedo_color = Color(0.35, 0.52, 0.68, 0.35)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.12
		elif "wall" in low:
			mat.albedo_color = Color(0.26, 0.25, 0.27)
		else:
			mat.albedo_color = Color(0.32, 0.30, 0.28)
	var low_wall: String = ue_mat_path.to_lower()
	if "wallpaper" in low_wall or "thievesden" in low_wall:
		if mat.albedo_texture == null:
			mat.albedo_color = mat.albedo_color * Color(0.42, 0.35, 0.35, 1.0)
		if mat.roughness < 0.72:
			mat.roughness = 0.72
	# Thieves' Den neon fix: T_Wallpaper_Floral and T_WallpaperC_D are channel-packed RGB masks.
	var albedo_path_lower: String = str(texs.get("albedo", "")).to_lower()
	if "wallpaper" in low_mat or "t_wallpaper_floral" in albedo_path_lower or "t_wallpaperc_d" in albedo_path_lower:
		var manor_wall_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Wallpaper/ManorWallpaper/T_ManorWallpaper_C_Diffuse.png")
		if manor_wall_alb != null:
			mat.albedo_texture = manor_wall_alb
			alb = manor_wall_alb
		var manor_wall_norm: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Wallpaper/ManorWallpaper/T_ManorWallpaper_Normal.png")
		if manor_wall_norm != null:
			mat.normal_enabled = true
			mat.normal_texture = manor_wall_norm
		mat.albedo_color = Color(0.28, 0.24, 0.21, 1.0)
		mat.roughness = 0.82
	_std_mat_cache[ue_mat_path] = mat
	return mat


func _ue_mesh_to_res(ue_path: String) -> String:
	var clean := ue_path.split(".")[0]
	if clean.begins_with("/Game/"):
		clean = clean.substr(6)
	var candidate := "res://assets/ue/Content/" + clean + ".glb"
	if ResourceLoader.exists(candidate):
		return candidate
	var gltf := "res://assets/ue/Content/" + clean + ".gltf"
	if ResourceLoader.exists(gltf):
		return gltf
	return ""


func _get_mesh_and_shape(ue_path: String) -> Dictionary:
	if _mesh_res_cache.has(ue_path):
		return _mesh_res_cache[ue_path]
	var out: Dictionary = {"mesh": null, "shape": null}
	var res_path: String = _ue_mesh_to_res(ue_path)
	if res_path == "":
		_mesh_res_cache[ue_path] = out
		return out
	var packed: Variant = load(res_path)
	if packed is PackedScene:
		var inst: Node = packed.instantiate()
		var mi := _find_first_mesh(inst)
		if mi != null and mi.mesh != null:
			var m := mi.mesh.duplicate() as Mesh
			var low_u := ue_path.to_lower()
			if "lightshaft" in low_u or "godray" in low_u:
				var beam_mat := StandardMaterial3D.new()
				beam_mat.albedo_color = Color(0.55, 0.78, 0.95, 0.08)
				beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				for s in range(m.get_surface_count()):
					m.surface_set_material(s, beam_mat)
				out["mesh"] = m
				out["shape"] = null
			else:
				# Bind UE material slots (exact, then case-insensitive fallback)
				var mesh_key: String = ue_path.split(".")[0]
				var mat_slots: Array = _mesh_mats_db.get(mesh_key, _mesh_mats_db_lower.get(mesh_key.to_lower(), []))
				for s in range(mini(m.get_surface_count(), mat_slots.size())):
					var mp: String = str(mat_slots[s])
					if mp != "":
						m.surface_set_material(s, get_material_for_ue(mp))
				out["mesh"] = m
				var is_nonblocking: bool = ("rug" in low_u or "carpet" in low_u or "placemat" in low_u or "paper" in low_u or "poster" in low_u or "scroll" in low_u or "curtain" in low_u or "cloth" in low_u or "drape" in low_u or "sheet" in low_u or "cable" in low_u or "wire" in low_u or "rope" in low_u or "ivy" in low_u or "vine" in low_u or "foliage" in low_u)
				# Fast BoxShape3D for props; trimesh only for large structural geometry
				var aabb := m.get_aabb()
				var sz := aabb.size
				if not is_nonblocking and sz.length() > 0.45:
					if sz.length() < 12.0:
						var bx := BoxShape3D.new()
						bx.size = Vector3(maxf(sz.x, 0.1), maxf(sz.y, 0.1), maxf(sz.z, 0.1))
						out["shape"] = bx
						out["shape_offset"] = aabb.get_center()
					else:
						out["shape"] = m.create_trimesh_shape()
						out["shape_offset"] = Vector3.ZERO
		inst.free()
	_mesh_res_cache[ue_path] = out
	return out


func _find_first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_first_mesh(c)
		if r != null:
			return r
	return null


func _has_token(haystack_low: String, tokens: Array[String]) -> bool:
	for token: String in tokens:
		if haystack_low.find(token) >= 0:
			return true
	return false


## Skybox/periphery sublevels are horizon dressing: never spawn physics or occluders.
func _is_decorative_sublevel(json_path: String) -> bool:
	return _has_token(json_path.to_lower(), DECORATIVE_SUBLEVEL_TOKENS)


func _new_accumulator() -> Dictionary:
	return {
		"batches": {},
		"batches_nocol": {},
		"lights": [] as Array,
		"landscapes": [] as Array,
		"seen_lights": {},
		"result": {
			"player_spawns": [] as Array[Vector3],
			"guard_spawns": [] as Array[Vector3],
			"loot_spawns": [] as Array[Vector3],
			"escape_points": [] as Array[Vector3],
			"door_spawns": [] as Array[Vector3],
			"candelabra_positions": [] as Array[Vector3],
			"wardrobe_positions": [] as Array[Vector3],
			"desk_positions": [] as Array[Vector3],
			"ledger_positions": [] as Array[Vector3],
			"window_positions": [] as Array[Vector3],
			"mesh_instances": 0,
			"light_count": 0,
			"chunk_count": 0,
			"collision_bodies": 0,
			"collision_shapes": 0,
			"occluder_count": 0,
		},
	}


func _new_build_ctx(parent: Node3D, light_probe: Node, generate_collision: bool) -> Dictionary:
	return {
		"parent": parent,
		"light_probe": light_probe,
		"generate_collision": generate_collision,
		"col_bodies": {},
		"col_counts": {},
		"collision_shapes": 0,
		"collision_bodies": 0,
		"occluders": 0,
		"chunk_count": 0,
		"light_count": 0,
		"landscapes_built": 0,
		"landscape_mat": null,
	}


## Parses one .tatlevel.json into the accumulator. Meshes from skybox/periphery
## sublevels go into the non-colliding batch table so they never spawn physics.
func _parse_sublevel_file(json_path: String, acc: Dictionary, parent: Node3D) -> void:
	if not FileAccess.file_exists(json_path):
		return
	var f: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	var data_dict: Dictionary = data
	var result: Dictionary = acc["result"]
	var landscapes: Array = acc["landscapes"]
	for lc in data_dict.get("landscapes", []):
		if lc is Dictionary:
			landscapes.append(lc)

	var collide_sublevel: bool = not _is_decorative_sublevel(json_path)
	var batches: Dictionary = acc["batches"] if collide_sublevel else acc["batches_nocol"]

	for m in data_dict.get("meshes", []):
		if not (m is Dictionary):
			continue
		var m_dict: Dictionary = m
		var mp: String = str(m_dict.get("mesh", ""))
		if mp == "":
			continue
		var low_mp: String = mp.to_lower()
		if "emissiveshapes/sm_sphere" in low_mp or "primitives/sm_shape" in low_mp or "fogsheet" in low_mp or "volumetric" in low_mp or "skysphere" in low_mp or "blocker" in low_mp:
			continue
		var tr: Transform3D = _dict_to_transform(m_dict)
		if not batches.has(mp):
			batches[mp] = [] as Array[Transform3D]
		var arr: Array = batches[mp]
		arr.append(tr)
		var prop_pos: Vector3 = tr.origin
		if "candelabra" in low_mp or "candle" in low_mp or "brazier" in low_mp or "torch" in low_mp:
			var candle_arr: Array = result["candelabra_positions"]
			candle_arr.append(prop_pos)
			_VfxManager.spawn_candle_flame(parent, prop_pos + Vector3(0.0, 0.48, 0.0))
		if "wardrobe" in low_mp or "bureau" in low_mp or "armoire" in low_mp:
			var ward_arr: Array = result["wardrobe_positions"]
			ward_arr.append(prop_pos)
		if "sm_map_thievesden" in low_mp:
			var desk_arr: Array = result["desk_positions"]
			desk_arr.insert(0, prop_pos)
		elif "maptable" in low_mp or "table_map" in low_mp or "desk" in low_mp:
			var desk_arr2: Array = result["desk_positions"]
			desk_arr2.append(prop_pos)
		if "openedledger" in low_mp:
			var led_arr: Array = result["ledger_positions"]
			led_arr.append(prop_pos)
		if "windowborder" in low_mp or "thievesden_window" in low_mp:
			var win_arr: Array = result["window_positions"]
			win_arr.append(prop_pos)

	for l in data_dict.get("lights", []):
		if not (l is Dictionary):
			continue
		var l_dict: Dictionary = l
		var lpos: Array = l_dict.get("pos", [0, 0, 0])
		var lkey: String = "%d,%d,%d" % [roundi(float(lpos[0])), roundi(float(lpos[1])), roundi(float(lpos[2]))]
		var seen_lights: Dictionary = acc["seen_lights"]
		if seen_lights.has(lkey):
			continue
		seen_lights[lkey] = true
		var pending_lights: Array = acc["lights"]
		pending_lights.append(l_dict)

	for mk in data_dict.get("markers", []):
		if not (mk is Dictionary):
			continue
		var cls: String = str(mk.get("class", ""))
		var pos_arr: Array = mk.get("pos", [0, 0, 0])
		var p: Vector3 = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		if "PlayerStart" in cls:
			var ps: Array = result["player_spawns"]
			ps.append(p)
		elif "MissionSpawner_Character" in cls or "Guard" in cls:
			var gs: Array = result["guard_spawns"]
			gs.append(p)
		elif "MissionSpawner_MajorLoot" in cls or "MissionSpawner_MinorLoot" in cls or "QuestSpawner" in cls:
			var ls: Array = result["loot_spawns"]
			ls.append(p)
		elif "Escape" in cls:
			var es: Array = result["escape_points"]
			es.append(p)
		elif "Door" in cls:
			var ds: Array = result["door_spawns"]
			ds.append(p)


func _cell_of(tr: Transform3D) -> Vector2i:
	return Vector2i(floori(tr.origin.x / CHUNK_SIZE), floori(tr.origin.z / CHUNK_SIZE))


## Splits one mesh-path batch into per-cell draw items. Single instances (or
## batches that fit in one cell) stay as a single tight-AABB node.
func _make_draw_items(batches: Dictionary, collide: bool) -> Array:
	var items: Array = []
	for mp_var in batches.keys():
		var mp: String = str(mp_var)
		var trs: Array = batches[mp_var]
		if trs.is_empty():
			continue
		if trs.size() == 1:
			var single_tr: Transform3D = trs[0]
			items.append({"mp": mp, "trs": trs, "collide": collide, "cell": _cell_of(single_tr)})
			continue
		var cells: Dictionary = {}
		for tr_var in trs:
			var tr: Transform3D = tr_var
			var ck: String = "%d_%d" % [floori(tr.origin.x / CHUNK_SIZE), floori(tr.origin.z / CHUNK_SIZE)]
			if not cells.has(ck):
				cells[ck] = [] as Array
			var cell_arr: Array = cells[ck]
			cell_arr.append(tr)
		for ck_var in cells.keys():
			var ck_str: String = str(ck_var)
			var parts: PackedStringArray = ck_str.split("_")
			var cell: Vector2i = Vector2i(int(parts[0]), int(parts[1]))
			items.append({"mp": mp, "trs": cells[ck_var], "collide": collide, "cell": cell})
	return items


func _collect_draw_items(acc: Dictionary) -> Array:
	var items: Array = []
	items.append_array(_make_draw_items(acc["batches"], true))
	items.append_array(_make_draw_items(acc["batches_nocol"], false))
	return items


func _apply_culling_policy(node: GeometryInstance3D, low_mp: String, mesh: Mesh) -> void:
	var aabb_len: float = mesh.get_aabb().size.length()
	if _has_token(low_mp, CLUTTER_TOKENS):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = CLUTTER_VIS_RANGE + CHUNK_RADIUS_PAD
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		return
	if aabb_len < TINY_PROP_LEN:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = TINY_PROP_VIS_RANGE + CHUNK_RADIUS_PAD
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	elif aabb_len < SMALL_PROP_LEN:
		node.visibility_range_end = SMALL_PROP_VIS_RANGE + CHUNK_RADIUS_PAD
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _qualifies_as_occluder(low_mp: String, mesh: Mesh) -> bool:
	var aabb_len: float = mesh.get_aabb().size.length()
	if aabb_len < OCCLUDER_MIN_LEN or aabb_len > OCCLUDER_MAX_LEN:
		return false
	if not _has_token(low_mp, OCCLUDER_INCLUDE_TOKENS):
		return false
	return not _has_token(low_mp, OCCLUDER_EXCLUDE_TOKENS)


func _add_occluder(ctx: Dictionary, mesh: Mesh, tr: Transform3D) -> void:
	var aabb: AABB = mesh.get_aabb()
	var box: BoxOccluder3D = BoxOccluder3D.new()
	box.size = aabb.size
	var occ: OccluderInstance3D = OccluderInstance3D.new()
	occ.occluder = box
	occ.transform = Transform3D(tr.basis, tr * aabb.get_center())
	var parent: Node3D = ctx["parent"]
	parent.add_child(occ)
	ctx["occluders"] = int(ctx.get("occluders", 0)) + 1


## Adds one BoxShape3D/trimesh collider to the per-cell StaticBody3D bucket.
## Bodies are capped at MAX_SHAPES_PER_BODY so Jolt never rebuilds a huge compound.
func _add_collider(ctx: Dictionary, cell: Vector2i, shape: Shape3D, tr: Transform3D, shape_offset: Vector3) -> void:
	if int(ctx.get("collision_shapes", 0)) >= MAX_TOTAL_SHAPES:
		return
	var bodies: Dictionary = ctx["col_bodies"]
	var counts: Dictionary = ctx["col_counts"]
	var base_key: String = "%d_%d" % [cell.x, cell.y]
	var used: int = int(counts.get(base_key, 0))
	var bucket: int = used / MAX_SHAPES_PER_BODY
	var body_key: String = "%s_%d" % [base_key, bucket]
	var body: StaticBody3D = bodies.get(body_key) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "LevelCollision_%s" % body_key
		body.collision_layer = 1
		var parent: Node3D = ctx["parent"]
		parent.add_child(body)
		bodies[body_key] = body
		ctx["collision_bodies"] = int(ctx.get("collision_bodies", 0)) + 1
	counts[base_key] = used + 1
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	var sc: Vector3 = tr.basis.get_scale()
	cs.transform = Transform3D(tr.basis.orthonormalized(), tr * shape_offset)
	cs.scale = Vector3(maxf(absf(sc.x), 0.05), maxf(absf(sc.y), 0.05), maxf(absf(sc.z), 0.05))
	body.add_child(cs)
	ctx["collision_shapes"] = int(ctx.get("collision_shapes", 0)) + 1


## Emits one chunked MultiMeshInstance3D (or plain MeshInstance3D) plus its
## colliders and occluders. Returns the number of mesh instances added.
func _build_one_draw_item(item: Dictionary, parent: Node3D, ctx: Dictionary) -> int:
	var mp: String = str(item.get("mp", ""))
	var trs: Array = item.get("trs", [])
	if trs.is_empty():
		return 0
	var info: Dictionary = _get_mesh_and_shape(mp)
	var mesh: Mesh = info["mesh"]
	if mesh == null:
		return 0
	var low_mp: String = mp.to_lower()
	var count: int = trs.size()
	var node: GeometryInstance3D
	if count >= 2:
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = count
		# Explicit tight bounds: Godot only frustum-culls a MultiMesh against
		# its AABB, so each 32m chunk gets the real merged instance bounds.
		var mesh_aabb: AABB = mesh.get_aabb()
		var chunk_aabb: AABB = AABB()
		var have_bounds: bool = false
		for i in range(count):
			var tr_i: Transform3D = trs[i]
			mm.set_instance_transform(i, tr_i)
			var world_aabb: AABB = tr_i * mesh_aabb
			if not have_bounds:
				chunk_aabb = world_aabb
				have_bounds = true
			else:
				chunk_aabb = chunk_aabb.merge(world_aabb)
		if have_bounds:
			mm.custom_aabb = chunk_aabb
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		node = mmi
	else:
		var tr_one: Transform3D = trs[0]
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = tr_one
		node = mi
	_apply_culling_policy(node, low_mp, mesh)
	if MobileProfile.is_mobile():
		node.lod_bias = MobileProfile.lod_bias()
	parent.add_child(node)
	ctx["chunk_count"] = int(ctx.get("chunk_count", 0)) + 1

	var is_clutter: bool = _has_token(low_mp, CLUTTER_TOKENS)
	if bool(item.get("collide", false)) and bool(ctx.get("generate_collision", false)) and not is_clutter:
		var shape: Shape3D = info["shape"] as Shape3D
		if shape != null:
			var soff: Vector3 = info.get("shape_offset", Vector3.ZERO)
			var cell: Vector2i = item.get("cell", Vector2i.ZERO)
			for i2 in range(count):
				var tr_c: Transform3D = trs[i2]
				if absf(tr_c.basis.determinant()) < 0.0001:
					continue
				_add_collider(ctx, cell, shape, tr_c, soff)

	if not is_clutter and _qualifies_as_occluder(low_mp, mesh):
		for i3 in range(count):
			if int(ctx.get("occluders", 0)) >= MAX_OCCLUDERS:
				break
			var tr_o: Transform3D = trs[i3]
			_add_occluder(ctx, mesh, tr_o)
	return count


func _build_landscapes_sync(landscapes: Array, parent: Node3D, ctx: Dictionary) -> void:
	for lc_var: Variant in landscapes:
		_build_one_landscape(lc_var, parent, ctx)


func _add_one_light(linfo: Dictionary, parent: Node3D, light_probe: Node, hero_shadow: bool) -> bool:
	var lnode: Light3D = _build_light(linfo, hero_shadow)
	if lnode == null:
		return false
	lnode.shadow_enabled = hero_shadow
	parent.add_child(lnode)
	if light_probe != null and light_probe.has_method("register_light"):
		light_probe.register_light(lnode)
	return true


func _add_lights(pending_lights: Array, parent: Node3D, light_probe: Node, max_lights: int, ctx: Dictionary) -> void:
	pending_lights.sort_custom(_sort_lights_desc)
	var budget: int = mini(pending_lights.size(), max_lights)
	var hero_shadows: int = mini(MobileProfile.hero_shadows(), budget)
	var added: int = 0
	for li in range(budget):
		var linfo: Dictionary = pending_lights[li]
		if _add_one_light(linfo, parent, light_probe, li < hero_shadows):
			added += 1
	ctx["light_count"] = added


func _finalize(result: Dictionary, ctx: Dictionary, mesh_instances: int) -> Dictionary:
	result["mesh_instances"] = mesh_instances
	result["light_count"] = int(ctx.get("light_count", 0))
	result["chunk_count"] = int(ctx.get("chunk_count", 0))
	result["collision_bodies"] = int(ctx.get("collision_bodies", 0))
	result["collision_shapes"] = int(ctx.get("collision_shapes", 0))
	result["occluder_count"] = int(ctx.get("occluders", 0))
	return result


func load_sublevels(json_paths: Array[String], parent: Node3D, light_probe: Node, max_lights: int = 96, generate_collision: bool = true) -> Dictionary:
	if _materials_db.is_empty():
		_load_material_dbs()
	var acc: Dictionary = _new_accumulator()
	for jp: String in json_paths:
		_parse_sublevel_file(jp, acc, parent)

	var ctx: Dictionary = _new_build_ctx(parent, light_probe, generate_collision)
	_add_lights(acc["lights"], parent, light_probe, max_lights, ctx)
	_build_landscapes_sync(acc["landscapes"], parent, ctx)

	var items: Array = _collect_draw_items(acc)
	var total_inst: int = 0
	for item: Dictionary in items:
		total_inst += _build_one_draw_item(item, parent, ctx)
	return _finalize(acc["result"], ctx, total_inst)


func load_sublevels_async(json_paths: Array, parent: Node3D, light_probe: Node = null, max_lights: int = 96, generate_collision: bool = true) -> Dictionary:
	if _materials_db.is_empty():
		_load_material_dbs()
	var acc: Dictionary = _new_accumulator()
	var total_files: int = maxi(json_paths.size(), 1)
	var file_idx: int = 0
	load_progress.emit(0.0, "Parsing JSON...")
	for jp in json_paths:
		_parse_sublevel_file(str(jp), acc, parent)
		file_idx += 1
		load_progress.emit(0.3 * float(file_idx) / float(total_files), "Parsing JSON %d/%d..." % [file_idx, json_paths.size()])
		if parent.get_tree() != null:
			await parent.get_tree().process_frame

	var ctx: Dictionary = _new_build_ctx(parent, light_probe, generate_collision)
	var pending_lights: Array = acc["lights"]
	pending_lights.sort_custom(_sort_lights_desc)
	load_progress.emit(0.3, "Sorting lights...")
	var light_budget: int = mini(pending_lights.size(), max_lights)
	var lights_added: int = 0
	var hero_shadows: int = mini(MobileProfile.hero_shadows(), light_budget)
	for li in range(light_budget):
		var linfo: Dictionary = pending_lights[li]
		if _add_one_light(linfo, parent, light_probe, li < hero_shadows):
			lights_added += 1
		if li % 20 == 0 or li == light_budget - 1:
			load_progress.emit(0.3 + 0.2 * float(li + 1) / float(maxi(light_budget, 1)), "Creating lights %d/%d..." % [li + 1, light_budget])
			if parent.get_tree() != null:
				await parent.get_tree().process_frame
	ctx["light_count"] = lights_added

	var landscapes: Array = acc["landscapes"]
	for lc_i in range(landscapes.size()):
		_build_one_landscape(landscapes[lc_i], parent, ctx)
		load_progress.emit(0.5 + 0.02 * float(lc_i + 1) / float(landscapes.size()), "Building terrain %d/%d..." % [lc_i + 1, landscapes.size()])
		if parent.get_tree() != null:
			await parent.get_tree().process_frame

	var items: Array = _collect_draw_items(acc)
	var built: int = 0
	var total_inst: int = 0
	for item: Dictionary in items:
		total_inst += _build_one_draw_item(item, parent, ctx)
		built += 1
		if built % PROGRESS_YIELD_EVERY == 0 or built == items.size():
			load_progress.emit(0.52 + 0.46 * float(built) / float(maxi(items.size(), 1)), "Batching meshes %d/%d..." % [built, items.size()])
			if parent.get_tree() != null:
				await parent.get_tree().process_frame
	load_progress.emit(1.0, "Done")
	return _finalize(acc["result"], ctx, total_inst)


func _light_score(info: Dictionary) -> float:
	var raw: float = _to_float(info.get("intensity"), 2.5)
	var energy: float = raw * 0.95 if raw < 20.0 else raw * 0.08
	var ltype: String = str(info.get("type", ""))
	if "Directional" in ltype:
		energy += 10.0
	elif "Spot" in ltype:
		energy += 2.0
	return energy


func _sort_lights_desc(a: Dictionary, b: Dictionary) -> bool:
	return _light_score(a) > _light_score(b)


func _dict_to_transform(d: Dictionary) -> Transform3D:
	var p: Array = d.get("pos", [0, 0, 0])
	var b: Array = d.get("basis", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	var s: Array = d.get("scale", [1, 1, 1])
	var basis: Basis = Basis(
		Vector3(float(b[0]), float(b[3]), float(b[6])),
		Vector3(float(b[1]), float(b[4]), float(b[7])),
		Vector3(float(b[2]), float(b[5]), float(b[8]))
	).scaled(Vector3(
		clampf(float(s[0]), 0.05, 40.0),
		clampf(float(s[1]), 0.05, 40.0),
		clampf(float(s[2]), 0.05, 40.0)
	))
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2])))


func _to_float(v: Variant, fallback: float) -> float:
	if v == null:
		return fallback
	return float(v)


func _build_light(info: Dictionary, cast_shadow: bool = false) -> Light3D:
	var ltype: String = str(info.get("type", ""))
	var raw_i := _to_float(info.get("intensity"), 2.5)
	var intensity := clampf(raw_i * 0.95, 1.0, 4.2) if raw_i < 20.0 else clampf(raw_i * 0.08, 1.0, 4.2)
	var col_dict: Variant = info.get("color")
	var col := Color(1.0, 0.85, 0.62)
	if col_dict is Dictionary:
		col = Color(
			_to_float(col_dict.get("R"), 255.0) / 255.0,
			_to_float(col_dict.get("G"), 215.0) / 255.0,
			_to_float(col_dict.get("B"), 150.0) / 255.0
		)
	var light: Light3D
	if "Directional" in ltype:
		light = DirectionalLight3D.new()
		light.light_energy = 0.45
	elif "Spot" in ltype:
		var sl := SpotLight3D.new()
		sl.spot_range = clampf(_to_float(info.get("radius"), 6.0) * 2.5, 6.0, 26.0)
		sl.spot_angle = clampf(_to_float(info.get("outer_cone"), 50.0), 18.0, 78.0)
		sl.spot_attenuation = 0.85
		sl.light_energy = intensity
		light = sl
	else:
		var ol := OmniLight3D.new()
		ol.omni_range = clampf(_to_float(info.get("radius"), 5.0) * 2.2, 5.0, 20.0)
		ol.omni_attenuation = 0.9
		ol.light_energy = intensity
		light = ol
	light.light_color = col
	light.shadow_enabled = cast_shadow
	# P3: non-hero point/spot lights fade out with camera distance so the
	# Forward+ clustered light list only uploads nearby lights.
	if not cast_shadow and (light is OmniLight3D or light is SpotLight3D):
		light.distance_fade_enabled = true
		light.distance_fade_begin = LIGHT_DISTANCE_FADE_BEGIN
		light.distance_fade_length = LIGHT_DISTANCE_FADE_LENGTH
		light.distance_fade_shadow = true
	light.transform = _dict_to_transform(info)
	if light is SpotLight3D or light is DirectionalLight3D:
		# UE5 spotlights/directionals aim along +X; Godot aims along -Z
		light.rotate_object_local(Vector3.UP, -PI * 0.5)
	return light


func _landscape_material(ctx: Dictionary) -> StandardMaterial3D:
	var cached: StandardMaterial3D = ctx.get("landscape_mat") as StandardMaterial3D
	if cached != null:
		return cached
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	var ground_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Legacy/T_CobbleStoneA_D.png")
	if ground_alb == null:
		ground_alb = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Nature/Dirt/T_GroundDirtA_D.png")
	if ground_alb != null:
		mat.albedo_texture = ground_alb
	mat.albedo_color = Color(0.36, 0.37, 0.35)
	mat.roughness = 0.90
	mat.uv1_scale = Vector3(12.0, 12.0, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ctx["landscape_mat"] = mat
	return mat


## Builds one LandscapeComponent heightfield mesh. Each component gets its own
## StaticBody3D so a single landscape never becomes a massive compound body.
func _build_one_landscape(lc_var: Variant, parent: Node3D, ctx: Dictionary) -> void:
	if not (lc_var is Dictionary):
		return
	var lc: Dictionary = lc_var as Dictionary
	var hpath: String = str(lc.get("heightmap", ""))
	if hpath == "":
		return
	if not FileAccess.file_exists(hpath) and not ResourceLoader.exists(hpath):
		return
	var img: Image = null
	var htex: Texture2D = _load_tex(hpath)
	if htex != null:
		img = htex.get_image()
	if img == null or img.is_empty():
		if FileAccess.file_exists(hpath):
			img = Image.load_from_file(hpath)
	if img == null or img.is_empty():
		return
	var mat: StandardMaterial3D = _landscape_material(ctx)
	var iw: int = img.get_width()
	var ih: int = img.get_height()
	var quads: int = int(lc.get("quads", 63))
	var sb: Array = lc.get("scale_bias", [1.0 / 64.0, 1.0 / 64.0, 0.0, 0.0])
	var sx_b: float = float(sb[0]) if sb.size() > 0 else 1.0 / 64.0
	var sy_b: float = float(sb[1]) if sb.size() > 1 else 1.0 / 64.0
	var ox_b: float = float(sb[2]) if sb.size() > 2 else 0.0
	var oy_b: float = float(sb[3]) if sb.size() > 3 else 0.0

	var tr_raw: Transform3D = _dict_to_transform(lc)
	var sc: Vector3 = tr_raw.basis.get_scale()
	# UE LandscapeComponent scale is 100.0 (= 1m per quad)
	var step_x: float = absf(sc.x) * 0.01
	var step_y: float = absf(sc.y) * 0.01
	var step_z: float = absf(sc.z) * 0.01
	if step_x < 0.05:
		step_x = 1.0
	if step_y < 0.05:
		step_y = 1.0
	if step_z < 0.05:
		step_z = 1.0

	var heights: Array[float] = []
	var stride: int = quads + 1
	heights.resize(stride * stride)
	for vy: int in range(stride):
		for vx: int in range(stride):
			var px: int = clampi(int(round((float(vx) * sx_b + ox_b) * float(iw))), 0, iw - 1)
			var py: int = clampi(int(round((float(vy) * sy_b + oy_b) * float(ih))), 0, ih - 1)
			var c: Color = img.get_pixel(px, py)
			var h16: int = (c.r8 << 8) | c.g8
			var h_val: float = ((float(h16) - 32768.0) / 128.0) * step_y
			heights[vy * stride + vx] = h_val

	var faces: PackedVector3Array = PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for qy: int in range(quads):
		for qx: int in range(quads):
			var p00 := Vector3(float(qx) * step_x, heights[qy * stride + qx], float(qy) * step_z)
			var p10 := Vector3(float(qx + 1) * step_x, heights[qy * stride + (qx + 1)], float(qy) * step_z)
			var p01 := Vector3(float(qx) * step_x, heights[(qy + 1) * stride + qx], float(qy + 1) * step_z)
			var p11 := Vector3(float(qx + 1) * step_x, heights[(qy + 1) * stride + (qx + 1)], float(qy + 1) * step_z)
			var u00 := Vector2(float(qx) / float(quads), float(qy) / float(quads))
			var u10 := Vector2(float(qx + 1) / float(quads), float(qy) / float(quads))
			var u01 := Vector2(float(qx) / float(quads), float(qy + 1) / float(quads))
			var u11 := Vector2(float(qx + 1) / float(quads), float(qy + 1) / float(quads))
			st.set_uv(u00); st.add_vertex(p00)
			st.set_uv(u11); st.add_vertex(p11)
			st.set_uv(u10); st.add_vertex(p10)
			st.set_uv(u00); st.add_vertex(p00)
			st.set_uv(u01); st.add_vertex(p01)
			st.set_uv(u11); st.add_vertex(p11)
			faces.append(p00); faces.append(p11); faces.append(p10)
			faces.append(p00); faces.append(p01); faces.append(p11)
	st.generate_normals()
	var arr_mesh: ArrayMesh = st.commit()
	if arr_mesh == null:
		return
	arr_mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = arr_mesh
	mi.transform = Transform3D(tr_raw.basis.orthonormalized(), tr_raw.origin)
	parent.add_child(mi)

	if bool(ctx.get("generate_collision", false)) and not faces.is_empty():
		var cshape := ConcavePolygonShape3D.new()
		cshape.backface_collision = true
		cshape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = cshape
		cs.transform = Transform3D(tr_raw.basis.orthonormalized(), tr_raw.origin)
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "LandscapeCollision_%d" % int(ctx.get("landscapes_built", 0))
		body.collision_layer = 1
		body.add_child(cs)
		parent.add_child(body)
		ctx["collision_bodies"] = int(ctx.get("collision_bodies", 0)) + 1
		ctx["collision_shapes"] = int(ctx.get("collision_shapes", 0)) + 1
	ctx["landscapes_built"] = int(ctx.get("landscapes_built", 0)) + 1
