extends Node
## High-performance UE5 -> Godot 4.7 level builder.
## Loads extracted .tatlevel.json sublevels, batches repeated .glb meshes into MultiMeshInstance3D,
## binds real PBR materials (Albedo/Normal/ORM) from materials.json + mesh_materials.json,
## generates StaticBody3D collision, and extracts real spawn/guard/loot/escape markers.

const _VfxManager: GDScript = preload("res://src/core/vfx_manager.gd")

signal load_progress(pct: float, status: String)

var _materials_db: Dictionary = {}
var _materials_db_lower: Dictionary = {}
var _mesh_mats_db: Dictionary = {}
var _mesh_mats_db_lower: Dictionary = {}
var _tex_cache: Dictionary = {}
var _std_mat_cache: Dictionary = {}
var _mesh_res_cache: Dictionary = {} # ue_path -> { "mesh": Mesh, "shape": Shape3D }


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


func get_material_for_ue(ue_mat_path: String) -> StandardMaterial3D:
	if _std_mat_cache.has(ue_mat_path):
		return _std_mat_cache[ue_mat_path]
	var low_mat := ue_mat_path.to_lower()
	var info: Dictionary = _materials_db.get(ue_mat_path, _materials_db_lower.get(low_mat, {}))
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.78
	var texs: Dictionary = info.get("texs", {})
	var alb := _load_tex(str(texs.get("albedo", "")))
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


func load_sublevels(json_paths: Array[String], parent: Node3D, light_probe: Node, max_lights: int = 96, generate_collision: bool = true) -> Dictionary:
	if _materials_db.is_empty():
		_load_material_dbs()
	var result: Dictionary = {
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
	}

	var batches: Dictionary = {} # ue_mesh_path -> Array[Transform3D]
	var lights_added: int = 0
	var pending_lights: Array = []
	var seen_lights: Dictionary = {}
	var pending_landscapes: Array = []

	for jp in json_paths:
		if not FileAccess.file_exists(jp):
			continue
		var f: FileAccess = FileAccess.open(jp, FileAccess.READ)
		if f == null:
			continue
		var data: Variant = JSON.parse_string(f.get_as_text())
		if not (data is Dictionary):
			continue
		var data_dict: Dictionary = data
		for lc in data_dict.get("landscapes", []):
			if lc is Dictionary:
				pending_landscapes.append(lc)

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
				var desk_arr: Array = result["desk_positions"]
				desk_arr.append(prop_pos)
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
			if seen_lights.has(lkey):
				continue
			seen_lights[lkey] = true
			pending_lights.append(l_dict)

		for mk in data_dict.get("markers", []):
			if not (mk is Dictionary):
				continue
			var cls: String = str(mk.get("class", ""))
			var pos_arr: Array = mk.get("pos", [0, 0, 0])
			var p: Vector3 = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			if "PlayerStart" in cls:
				result["player_spawns"].append(p)
			elif "MissionSpawner_Character" in cls or "Guard" in cls:
				result["guard_spawns"].append(p)
			elif "MissionSpawner_MajorLoot" in cls or "MissionSpawner_MinorLoot" in cls or "QuestSpawner" in cls:
				result["loot_spawns"].append(p)
			elif "Escape" in cls:
				result["escape_points"].append(p)
			elif "Door" in cls:
				result["door_spawns"].append(p)

	# Sort all collected lights by intensity/priority (brightest first),
	# enable shadows only on the top 4 hero lights so Forward+ Clustered
	# can handle up to 96 lights at high FPS.
	pending_lights.sort_custom(_sort_lights_desc)
	var light_budget: int = mini(pending_lights.size(), max_lights)
	for li in range(light_budget):
		var linfo: Dictionary = pending_lights[li]
		var hero_shadow: bool = li < 4
		var lnode: Light3D = _build_light(linfo, hero_shadow)
		if lnode != null:
			# Enforce shadow policy explicitly (top 4 brightest only).
			lnode.shadow_enabled = hero_shadow
			parent.add_child(lnode)
			if light_probe != null and light_probe.has_method("register_light"):
				light_probe.register_light(lnode)
			lights_added += 1

	# Build MultiMeshInstance3D batches + StaticBody3D colliders
	var col_body: StaticBody3D = null
	if generate_collision:
		col_body = StaticBody3D.new()
		col_body.name = "LevelCollision"
		col_body.collision_layer = 1
		parent.add_child(col_body)
	if not pending_landscapes.is_empty():
		_build_landscape_terrain(pending_landscapes, parent, col_body)

	var total_inst: int = 0
	for mp in batches.keys():
		var info: Dictionary = _get_mesh_and_shape(mp)
		var mesh: Mesh = info["mesh"]
		if mesh == null:
			continue
		var trs: Array = batches[mp]
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = trs.size()
		var shape: Shape3D = info["shape"]
		var soff: Vector3 = info.get("shape_offset", Vector3.ZERO)
		for i in range(trs.size()):
			var tr: Transform3D = trs[i]
			mm.set_instance_transform(i, tr)
			if col_body != null and shape != null and trs.size() <= 3000 and absf(tr.basis.determinant()) >= 0.0001:
				var cs: CollisionShape3D = CollisionShape3D.new()
				cs.shape = shape
				var sc: Vector3 = tr.basis.get_scale()
				cs.transform = Transform3D(tr.basis.orthonormalized(), tr * soff)
				cs.scale = Vector3(maxf(absf(sc.x), 0.05), maxf(absf(sc.y), 0.05), maxf(absf(sc.z), 0.05))
				col_body.add_child(cs)
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var aabb_len: float = mesh.get_aabb().size.length()
		if aabb_len < 0.8:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if aabb_len < 1.5:
			mmi.visibility_range_end = 85.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mmi)
		total_inst += trs.size()

	result["mesh_instances"] = total_inst
	result["light_count"] = lights_added
	return result


func load_sublevels_async(json_paths: Array, parent: Node3D, light_probe: Node = null, max_lights: int = 96, generate_collision: bool = true) -> Dictionary:
	if _materials_db.is_empty():
		_load_material_dbs()
	var result: Dictionary = {
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
	}
	var batches: Dictionary = {}
	var lights_added: int = 0
	var pending_lights: Array = []
	var seen_lights: Dictionary = {}
	var pending_landscapes: Array = []
	var total_files: int = maxi(json_paths.size(), 1)
	var file_idx: int = 0
	load_progress.emit(0.0, "Parsing JSON...")
	for jp in json_paths:
		var jp_str: String = str(jp)
		if FileAccess.file_exists(jp_str):
			var f: FileAccess = FileAccess.open(jp_str, FileAccess.READ)
			if f != null:
				var data: Variant = JSON.parse_string(f.get_as_text())
				if data is Dictionary:
					var data_dict: Dictionary = data
					for lc in data_dict.get("landscapes", []):
						if lc is Dictionary:
							pending_landscapes.append(lc)
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
							var desk_arr: Array = result["desk_positions"]
							desk_arr.append(prop_pos)
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
						if seen_lights.has(lkey):
							continue
						seen_lights[lkey] = true
						pending_lights.append(l_dict)
					for mk in data_dict.get("markers", []):
						if not (mk is Dictionary):
							continue
						var cls: String = str(mk.get("class", ""))
						var pos_arr: Array = mk.get("pos", [0, 0, 0])
						var p: Vector3 = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
						if "PlayerStart" in cls:
							result["player_spawns"].append(p)
						elif "MissionSpawner_Character" in cls or "Guard" in cls:
							result["guard_spawns"].append(p)
						elif "MissionSpawner_MajorLoot" in cls or "MissionSpawner_MinorLoot" in cls or "QuestSpawner" in cls:
							result["loot_spawns"].append(p)
						elif "Escape" in cls:
							result["escape_points"].append(p)
						elif "Door" in cls:
							result["door_spawns"].append(p)
		file_idx += 1
		load_progress.emit(0.3 * float(file_idx) / float(total_files), "Parsing JSON %d/%d..." % [file_idx, json_paths.size()])
		if parent.get_tree() != null:
			await parent.get_tree().process_frame
	load_progress.emit(0.35, "Sorting lights...")
	pending_lights.sort_custom(_sort_lights_desc)
	var light_budget: int = mini(pending_lights.size(), max_lights)
	for li in range(light_budget):
		var linfo: Dictionary = pending_lights[li]
		var hero_shadow: bool = li < 4
		var lnode: Light3D = _build_light(linfo, hero_shadow)
		if lnode != null:
			lnode.shadow_enabled = hero_shadow
			parent.add_child(lnode)
			if light_probe != null and light_probe.has_method("register_light"):
				light_probe.register_light(lnode)
			lights_added += 1
		if li % 20 == 0 or li == light_budget - 1:
			load_progress.emit(0.35 + 0.2 * float(li + 1) / float(maxi(light_budget, 1)), "Creating lights %d/%d..." % [li + 1, light_budget])
			if parent.get_tree() != null:
				await parent.get_tree().process_frame
	var col_body: StaticBody3D = null
	if generate_collision:
		col_body = StaticBody3D.new()
		col_body.name = "LevelCollision"
		col_body.collision_layer = 1
		parent.add_child(col_body)
	if not pending_landscapes.is_empty():
		_build_landscape_terrain(pending_landscapes, parent, col_body)
	var total_inst: int = 0
	var batch_keys: Array = batches.keys()
	var batch_idx: int = 0
	for mp in batch_keys:
		var info: Dictionary = _get_mesh_and_shape(str(mp))
		var mesh: Mesh = info["mesh"]
		if mesh == null:
			batch_idx += 1
			continue
		var trs: Array = batches[mp]
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = trs.size()
		var shape: Shape3D = info["shape"]
		var soff: Vector3 = info.get("shape_offset", Vector3.ZERO)
		for i in range(trs.size()):
			var tr: Transform3D = trs[i]
			mm.set_instance_transform(i, tr)
			if col_body != null and shape != null and trs.size() <= 3000 and absf(tr.basis.determinant()) >= 0.0001:
				var cs: CollisionShape3D = CollisionShape3D.new()
				cs.shape = shape
				var sc: Vector3 = tr.basis.get_scale()
				cs.transform = Transform3D(tr.basis.orthonormalized(), tr * soff)
				cs.scale = Vector3(maxf(absf(sc.x), 0.05), maxf(absf(sc.y), 0.05), maxf(absf(sc.z), 0.05))
				col_body.add_child(cs)
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var aabb_len: float = mesh.get_aabb().size.length()
		if aabb_len < 0.8:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if aabb_len < 1.5:
			mmi.visibility_range_end = 85.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mmi)
		total_inst += trs.size()
		batch_idx += 1
		if batch_idx % 80 == 0 or batch_idx == batch_keys.size():
			load_progress.emit(0.55 + 0.4 * float(batch_idx) / float(maxi(batch_keys.size(), 1)), "Batching meshes %d/%d..." % [batch_idx, batch_keys.size()])
			if parent.get_tree() != null:
				await parent.get_tree().process_frame
	result["mesh_instances"] = total_inst
	result["light_count"] = lights_added
	load_progress.emit(1.0, "Done")
	return result


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
	light.transform = _dict_to_transform(info)
	if light is SpotLight3D or light is DirectionalLight3D:
		# UE5 spotlights/directionals aim along +X; Godot aims along -Z
		light.rotate_object_local(Vector3.UP, -PI * 0.5)
	return light


func _build_landscape_terrain(landscapes: Array, parent: Node3D, col_body: StaticBody3D) -> void:
	var mat := StandardMaterial3D.new()
	var ground_alb: Texture2D = _load_tex("res://assets/ue/Raw/MaterialLibrary/Legacy/T_CobbleStoneA_D.png")
	if ground_alb == null:
		ground_alb = _load_tex("res://assets/ue/Raw/MaterialLibrary/Environment/Nature/Dirt/T_GroundDirtA_D.png")
	if ground_alb != null:
		mat.albedo_texture = ground_alb
	mat.albedo_color = Color(0.36, 0.37, 0.35)
	mat.roughness = 0.90
	mat.uv1_scale = Vector3(12.0, 12.0, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for lc_var: Variant in landscapes:
		if not (lc_var is Dictionary):
			continue
		var lc: Dictionary = lc_var as Dictionary
		var hpath: String = str(lc.get("heightmap", ""))
		if hpath == "":
			continue
		var img: Image = null
		var htex: Texture2D = _load_tex(hpath)
		if htex != null:
			img = htex.get_image()
		if img == null or img.is_empty():
			img = Image.load_from_file(hpath)
		if img == null or img.is_empty():
			continue
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

		var verts: PackedVector3Array = PackedVector3Array()
		var uvs: PackedVector2Array = PackedVector2Array()
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
			continue
		arr_mesh.surface_set_material(0, mat)

		var mi := MeshInstance3D.new()
		mi.mesh = arr_mesh
		mi.transform = Transform3D(tr_raw.basis.orthonormalized(), tr_raw.origin)
		parent.add_child(mi)

		if col_body != null and not faces.is_empty():
			var cshape := ConcavePolygonShape3D.new()
			cshape.backface_collision = true
			cshape.set_faces(faces)
			var cs := CollisionShape3D.new()
			cs.shape = cshape
			cs.transform = Transform3D(tr_raw.basis.orthonormalized(), tr_raw.origin)
			col_body.add_child(cs)
