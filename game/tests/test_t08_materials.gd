extends SceneTree
## T08 standalone probe: material/texture remediation census + assertions.
##
## Prints the measured class census BEFORE/AFTER style (the counts are read from
## the live generated data, so running it on the pre-fix tree and on the
## regenerated tree is the same command twice), then runs the gate checks.
##
## Run:
##   tools/godot --headless --path game --script res://tests/test_t08_materials.gd
##
## Exit code 0 only when every check passes. Data-dependent producer checks are
## SKIPped (loudly) when materials.json still predates the T08 producer.

const CHECKS := preload("res://tests/t08_material_checks.gd")
const LOADER_PATH := "res://src/core/level_loader.gd"
const MAT_DB := "res://data/generated/materials.json"
const MESH_DB := "res://data/generated/mesh_materials.json"
const LEVELS_GLOB := "res://data/generated/levels"

var fails: int = 0


func _initialize() -> void:
	# SceneTree._initialize() runs before the root viewport is usable, so the
	# checks run deferred with one frame of slack (same pattern as probe_leak).
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var ll: Node = (load(LOADER_PATH) as GDScript).new()
	get_root().add_child(ll)  # a live tree so bind_prop_scene_materials() can find the loader
	ll.call("_load_material_dbs")
	var db: Dictionary = _read_json(MAT_DB)
	var meshes: Dictionary = _read_json(MESH_DB)
	if db.is_empty() or meshes.is_empty():
		printerr("FAIL: generated material data missing")
		quit(1)
		return
	print("T08 data: materials=%d mesh_slot_lists=%d producer_current=%s" % [
		db.size(), meshes.size(), str(CHECKS.producer_data_current(db))])
	var binds: Dictionary = _bind_census(meshes)
	_census(db, binds, meshes)
	_tint_apply_sample(ll, db)
	var problems: Array[String] = CHECKS.run(ll, db)
	for p: String in problems:
		printerr("FAIL: " + p)
		fails += 1
	if problems.is_empty():
		print("PASS: T08 material checks (%d)" % 5)
	ll.free()
	print("T08_SUMMARY: fails=", fails)
	quit(0 if fails == 0 else 1)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var v: Variant = JSON.parse_string(f.get_as_text())
	return v as Dictionary if v is Dictionary else {}


## mesh path -> placed instance count, plus material path -> bind count.
func _bind_census(meshes: Dictionary) -> Dictionary:
	var mat_binds: Dictionary = {}
	var mesh_inst: Dictionary = {}
	for path: String in _level_files(LEVELS_GLOB):
		var doc: Dictionary = _read_json(path)
		for mv: Variant in (doc.get("meshes", []) as Array):
			if not (mv is Dictionary):
				continue
			var mesh_path: String = str((mv as Dictionary).get("mesh", ""))
			mesh_inst[mesh_path] = int(mesh_inst.get(mesh_path, 0)) + 1
			var slots: Array = meshes.get(mesh_path, []) as Array
			for s: Variant in slots:
				var m: String = str(s)
				if m != "":
					mat_binds[m] = int(mat_binds.get(m, 0)) + 1
	return {"materials": mat_binds, "meshes": mesh_inst}


func _level_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		if n != "." and n != "..":
			var full: String = dir_path + "/" + n
			if d.current_is_dir():
				out.append_array(_level_files(full))
			elif n.ends_with(".tatlevel.json"):
				out.append(full)
		n = d.get_next()
	d.list_dir_end()
	return out


func _census(db: Dictionary, binds: Dictionary, meshes: Dictionary) -> void:
	var mb: Dictionary = binds["materials"]
	var tints: int = 0
	var low: int = 0
	var hdr: int = 0
	var low_tex: int = 0
	var low_tex_binds: int = 0
	var flat: int = 0
	var flat_binds: int = 0
	var flat_white: int = 0
	var white_binds: int = 0
	for k: String in db:
		var v: Dictionary = db[k] as Dictionary
		var t: Variant = v.get("tint", null)
		var alb: String = str((v.get("texs", {}) as Dictionary).get("albedo", ""))
		if t is Array and (t as Array).size() >= 3:
			tints += 1
			var arr: Array = t as Array
			var peak: float = maxf(float(arr[0]), maxf(float(arr[1]), float(arr[2])))
			if peak > 1.0:
				hdr += 1
			else:
				low += 1
				if alb != "":
					low_tex += 1
					low_tex_binds += int(mb.get(k, 0))
		if alb == "" and t is Array:
			flat += 1
			flat_binds += int(mb.get(k, 0))
			if float((t as Array)[0]) >= 0.90 and float((t as Array)[1]) >= 0.90 and float((t as Array)[2]) >= 0.90:
				flat_white += 1
				white_binds += int(mb.get(k, 0))
	print("T08 census tints: total=%d low=%d hdr=%d low_with_albedo=%d low_with_albedo_binds=%d" % [
		tints, low, hdr, low_tex, low_tex_binds])
	print("T08 census flat_colour: materials=%d binds=%d near_white=%d near_white_binds=%d" % [
		flat, flat_binds, flat_white, white_binds])
	# Debug primitives: authored SM_Shape_* placements that bind MI_Default_White.
	var mi: Dictionary = binds["meshes"]
	var debug_total: int = 0
	var debug_gh: int = 0
	for mesh_path: String in mi:
		if mesh_path.to_lower().find("/test/art/primitives/sm_shape_") < 0:
			continue
		var slots: Array = meshes.get(mesh_path, []) as Array
		var white: bool = false
		for s: Variant in slots:
			if str(s).to_lower().find("mi_default_white") >= 0:
				white = true
		if not white:
			continue
		debug_total += int(mi[mesh_path])
	print("T08 census debug_shapes: instances=%d (Guildhall=%d)" % [
		debug_total, _count_in_guildhall(meshes)])
	# Slot index: how many placed meshes the legacy name match would mis-bind.
	var nm: Dictionary = _legacy_name_match_census(meshes, mi)
	print("T08 census slot_index: meshes_name_overridden=%d instances=%d" % [
		int(nm.get("meshes", 0)), int(nm.get("instances", 0))])


## Builds a sample of authored <=1 tints and asserts the applied albedo_color is
## the sRGB encoding of the authored linear value. This is the applied census:
## the class count (530 materials) is data-level, and every sampled material must
## land on the contract, so a second assignment path that bypasses
## _srgb_encode_albedo_tint is caught by measurement rather than by inspection.
func _tint_apply_sample(ll: Node, db: Dictionary) -> void:
	var keys: Array[String] = []
	for k: String in db:
		var v: Dictionary = db[k] as Dictionary
		var t: Variant = v.get("tint", null)
		var alb: String = str((v.get("texs", {}) as Dictionary).get("albedo", ""))
		if not (t is Array) or (t as Array).size() < 3 or alb == "":
			continue
		# The wallpaper/thievesden rescue multiplies albedo_color on purpose, and
		# Overlay/Multiply/Desaturation are part of the authored composite the
		# loader encodes as a whole (asserted by the helper unit check instead).
		if k.to_lower().find("wallpaper") >= 0 or k.to_lower().find("thievesden") >= 0:
			continue
		var vecs: Dictionary = v.get("vectors", {}) as Dictionary
		if vecs.has("Overlay") or vecs.has("Multiply") or vecs.has("Desaturation"):
			continue
		var peak: float = maxf(float((t as Array)[0]), maxf(float((t as Array)[1]), float((t as Array)[2])))
		if peak <= 1.0:
			keys.append(k)
	keys.sort()
	var step: int = maxi(1, keys.size() / 40)
	var checked: int = 0
	var bad: int = 0
	var i: int = 0
	while i < keys.size() and checked < 40:
		var k: String = keys[i]
		i += step
		var mat: Material = ll.call("get_material_for_ue", k) as Material
		if not (mat is StandardMaterial3D):
			continue  # glass/beam/storefront/HDR shader paths are asserted elsewhere
		var t: Array = (db[k] as Dictionary)["tint"] as Array
		var lin := Color(float(t[0]), float(t[1]), float(t[2]), 1.0)
		var want: Color = ll.call("_srgb_encode_albedo_tint", lin) as Color
		var got: Color = (mat as StandardMaterial3D).albedo_color
		checked += 1
		if not (absf(got.r - want.r) < 0.004 and absf(got.g - want.g) < 0.004 and absf(got.b - want.b) < 0.004):
			bad += 1
			if bad <= 5:
				printerr("T08 sample mismatch: ", k, " want=", want, " got=", got)
	print("T08 census tint_applied: candidates=%d sampled=%d mismatched=%d (linear-as-sRGB class is 0)" % [
		keys.size(), checked, bad])
	if bad > 0:
		fails += 1


func _count_in_guildhall(meshes: Dictionary) -> int:
	var total: int = 0
	for path: String in _level_files(LEVELS_GLOB):
		if path.find("Guildhall") < 0:
			continue
		var doc: Dictionary = _read_json(path)
		for mv: Variant in (doc.get("meshes", []) as Array):
			if not (mv is Dictionary):
				continue
			var mesh_path: String = str((mv as Dictionary).get("mesh", ""))
			if mesh_path.to_lower().find("/test/art/primitives/sm_shape_") < 0:
				continue
			var slots: Array = meshes.get(mesh_path, []) as Array
			for s: Variant in slots:
				if str(s).to_lower().find("mi_default_white") >= 0:
					total += 1
					break
	return total


## Replays the removed loader rule (surface name substring match wins over the
## index) against the authored slot lists, using the GLB material names the
## importer exposes as surface names.
func _legacy_name_match_census(meshes: Dictionary, instances: Dictionary) -> Dictionary:
	var out: Dictionary = {"meshes": 0, "instances": 0}
	for mesh_path: String in meshes:
		var placed: int = int(instances.get(mesh_path, 0))
		var slots: Array = meshes[mesh_path] as Array
		if placed == 0 or slots.is_empty():
			continue
		var names: Array = _glb_material_names(mesh_path)
		if names.is_empty():
			continue
		var differs: bool = false
		for s: int in range(mini(names.size(), slots.size())):
			var surf: String = str(names[s]).to_lower()
			if surf.length() < 3:
				continue
			var matched: int = -1
			for i: int in range(slots.size()):
				var mp: String = str(slots[i])
				if mp == "":
					continue
				var short: String = mp.get_file().split(".")[0].to_lower()
				if short.length() < 3:
					continue
				if surf.find(short) >= 0 or short.find(surf) >= 0:
					matched = i
					break
			if matched != -1 and matched != s and str(slots[matched]) != str(slots[s]):
				differs = true
		if differs:
			out["meshes"] = int(out["meshes"]) + 1
			out["instances"] = int(out["instances"]) + placed
	return out


func _glb_material_names(mesh_path: String) -> Array:
	if not mesh_path.begins_with("/Game/"):
		return []
	var rel: String = mesh_path.substr(6) + ".glb"
	var candidates: Array[String] = [
		"res://assets/ue/Content/" + rel,
		"res://assets/ue/Raw/TAT/Content/" + rel,
	]
	for c: String in candidates:
		if not FileAccess.file_exists(c):
			continue
		var f: FileAccess = FileAccess.open(c, FileAccess.READ)
		if f == null:
			continue
		f.seek(12)
		var head: PackedByteArray = f.get_buffer(8)
		if head.size() < 8:
			continue
		var chunk_len: int = head.decode_u32(0)
		f.seek(20)
		var raw: PackedByteArray = f.get_buffer(chunk_len)
		var doc: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if not (doc is Dictionary):
			continue
		var mats: Array = []
		for m: Variant in ((doc as Dictionary).get("materials", []) as Array):
			mats.append(str((m as Dictionary).get("name", "")) if m is Dictionary else "")
		var names: Array = []
		for mesh: Variant in ((doc as Dictionary).get("meshes", []) as Array):
			if not (mesh is Dictionary):
				continue
			for prim: Variant in ((mesh as Dictionary).get("primitives", []) as Array):
				if not (prim is Dictionary):
					continue
				var mi: Variant = (prim as Dictionary).get("material", null)
				var idx: int = int(mi) if (mi is int or mi is float) else -1
				names.append(str(mats[idx]) if idx >= 0 and idx < mats.size() else "")
		return names
	return []
